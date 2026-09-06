/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 6123 - Fix Fatia D Already-Applied Objects (PAUSE SQL Direct
               Audit — correção incremental, sem reescrever migration já
               executada)
Versão......: 1.1 (CONFIRMADO EXECUTADO E PROMOVIDO — renumerada de
               6125 para 6123 em RENUMBER-FIX-STAGING-01)
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-05 (staging em resposta a
               COLLECTIONS-POKEDEX-FATIA-D-IMPLEMENTATION-01 /
               PAUSE-SQL-DIRECT-AUDIT-01; renumerada de 6125 para 6123
               em RENUMBER-FIX-STAGING-01, para refletir a ordem
               cronológica real: esta correção precisa ser aplicada
               ANTES de remove_pokedex_position_assignment() e das RPCs
               de Primary Representative — que por isso passam a ser
               6124 e 6125, respectivamente; executada no banco real em
               IMPLEMENTATION-RESUME-02; promovida para database/schema/
               em COLLECTIONS-POKEDEX-FATIA-D-PROMOTION-CLOSEOUT-01 —
               corpo SQL byte-idêntico ao executado, apenas cabeçalho
               Status/Versão/Data atualizados)

ATENÇÃO — DIVERGÊNCIA FACTUAL CONFIRMADA (ver relatório desta rodada):
diferente do que a auditoria independente presumiu ("6122-6124 ainda não
aplicadas" — numeração ANTIGA, anterior a esta renumeração: o "6124" ali
citado é o arquivo hoje renomeado para 6125), a Query 6122
(set_pokedex_position_assignment) JÁ ESTÁ aplicada e viva no banco real
(confirmado via pg_get_functiondef nesta sessão — corpo idêntico ao
arquivo 6122 v1.1 staged, incluindo os bugs abaixo). Por isso ela entra
nesta migration incremental junto com 6118/6119, e não como edição
direta do arquivo 6122 histórico.

Descrição...:
Migration incremental (CREATE OR REPLACE FUNCTION) para os três objetos
desta Fatia D que JÁ FORAM aplicados ao banco real (6118, 6119, 6122) e
que, portanto, não podem ser corrigidos reescrevendo o conteúdo histórico
dos arquivos 6118/6119/6122 — mesma convenção já usada para qualquer
objeto pós-execução neste projeto. Os arquivos 6118/6119/6122 permanecem
inalterados como registro exato do que foi de fato executado; esta
migration é quem corrige o comportamento ao vivo, via CREATE OR REPLACE
FUNCTION (mesma assinatura, sem DROP).

Três correções, motivadas pela auditoria independente linha a linha de
Fabrício (PAUSE-SQL-DIRECT-AUDIT-01):

1. enforce_pokedex_position_assignment_pokedex_match() (trigger function
   de 6118/trg_010) — item 4: adicionado JOIN explícito
   col.mode = 'REFERENCE_BASED', mesma defesa em profundidade já aplicada
   em 6119 (STAGING-AUDIT-01 item 2). Sem essa checagem explícita, uma
   Collection em outro mode com uma collection_reference remanescente
   (estado não impedido por nenhuma constraint) poderia validar uma
   Position indevidamente.

2. auto_assign_pokedex_position_species_match() (trigger function de
   6119) — item 5: adicionado JOIN explícito card + card_category com
   cc.code = 'POKEMON'. A versão aplicada dependia apenas da existência
   de uma linha em card_primary_species para inferir "é POKEMON" — uma
   relação hoje verdadeira por construção (card_primary_species só é
   populada para Cards POKEMON, Fatia C), mas não estruturalmente
   garantida por nenhuma FK/CHECK que impeça uma linha órfã em outro
   cenário futuro. A checagem explícita remove essa dependência
   implícita.

3. set_pokedex_position_assignment() (RPC de 6122) — itens 1, 2 e 3,
   três correções na mesma função:
   a. p_confirm_override fail-closed: "IF NOT p_confirm_override" tratava
      NULL como falso em SQL (NOT NULL = NULL, IF NULL = não entra no
      bloco), permitindo que uma chamada com p_confirm_override = NULL
      explícito criasse um USER_OVERRIDE SEM confirmação real — bug de
      fail-open confirmado por leitura direta do corpo aplicado. Corrigido
      para "IF p_confirm_override IS DISTINCT FROM TRUE", que trata NULL
      exatamente como false.
   b. RETURNING/WHERE ambíguos: confirmado nesta sessão via
      "SHOW plpgsql.variable_conflict" que o projeto real roda com
      variable_conflict = 'error'. A função tem RETURNS TABLE
      (collection_allocation_id, pokedex_position_id, assignment_basis,
      assigned_at) — os mesmos nomes das colunas da tabela. O DELETE
      interno do MOVE (WHERE collection_allocation_id = ...) e a
      RETURNING do INSERT final usavam esses nomes SEM qualificação —
      ambíguo em tempo de EXECUÇÃO (CREATE FUNCTION não valida o corpo,
      só a sintaxe — por isso o bug não apareceu no apply_migration
      original). Corrigido qualificando ambos pelo nome da tabela
      (collection_pokedex_position_assignment.<coluna>), padrão canônico
      de 5046/5047. NOTA: este é um achado MAIS AMPLO do que o mandato
      original (que citava só "RETURNING") — o mesmo bug existia também
      na cláusula WHERE do DELETE, por ser a mesma causa raiz.
   c. Lock order: a versão aplicada travava a linha de collection_
      allocation (FOR UPDATE OF ca) e só depois lia (sem lock)
      collection.lifecycle_status — nenhum lock real sobre Collection,
      permitindo que um archive_collection() concorrente intercalasse
      entre essa leitura e a escrita da Assignment, sem nunca ser
      bloqueado. Corrigido para travar Collection PRIMEIRO (FOR UPDATE,
      ownership na própria WHERE, padrão 5046/5047), só então revalidar e
      travar a Allocation — ordem de domínio Collection -> Allocation,
      nunca invertida, e reforça a defesa REFERENCE_BASED explícita
      (item 4) também no caminho da RPC, não só no trigger.

Pré-requisitos:
- Query 6117/6118/6119/6120/6121/6122 já aplicadas ao projeto
  qjfutqujxrbzgrtkpgkg (confirmado via pg_proc/pg_get_functiondef nesta
  sessão).
================================================================
*/

BEGIN;

-- ----------------------------------------------------------------
-- 1. Correção de enforce_pokedex_position_assignment_pokedex_match()
--    (6118/trg_010) — REFERENCE_BASED explícito.
-- ----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_pokedex_position_assignment_pokedex_match()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_pokedex_id_from_collection UUID;
    v_pokedex_id_from_position   UUID;
BEGIN
    SELECT cpr.pokedex_id
      INTO v_pokedex_id_from_collection
      FROM public.collection_allocation ca
      JOIN public.collection col
          ON col.id = ca.collection_id
         AND col.mode = 'REFERENCE_BASED'
      JOIN public.collection_reference cr
          ON cr.collection_id = col.id
         AND cr.reference_kind = 'POKEDEX'
      JOIN public.collection_pokedex_reference cpr
          ON cpr.collection_reference_id = cr.id
     WHERE ca.id = NEW.collection_allocation_id;

    IF v_pokedex_id_from_collection IS NULL THEN
        RAISE EXCEPTION 'COLLECTION_POKEDEX_POSITION_ASSIGNMENT_REQUIRES_POKEDEX_COLLECTION';
    END IF;

    SELECT pp.pokedex_id
      INTO v_pokedex_id_from_position
      FROM public.pokedex_position pp
     WHERE pp.id = NEW.pokedex_position_id;

    IF v_pokedex_id_from_position IS DISTINCT FROM v_pokedex_id_from_collection THEN
        RAISE EXCEPTION 'COLLECTION_POKEDEX_POSITION_ASSIGNMENT_WRONG_POKEDEX';
    END IF;

    RETURN NEW;
END;
$$;

-- ----------------------------------------------------------------
-- 2. Correção de auto_assign_pokedex_position_species_match()
--    (6119) — POKEMON explícito via card_category.
-- ----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.auto_assign_pokedex_position_species_match()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.collection_pokedex_position_assignment
        (collection_allocation_id, pokedex_position_id, assignment_basis, assigned_at, assigned_by_user_id)
    SELECT
        nt.id,
        pp.id,
        'SPECIES_MATCH',
        NOW(),
        NULL
    FROM new_table nt
    JOIN public.collection col
        ON col.id = nt.collection_id
       AND col.mode = 'REFERENCE_BASED'
    JOIN public.collection_reference cr
        ON cr.collection_id = col.id
       AND cr.reference_kind = 'POKEDEX'
    JOIN public.collection_pokedex_reference cpr
        ON cpr.collection_reference_id = cr.id
    JOIN public.physical_card pc
        ON pc.id = nt.physical_card_id
    JOIN public.card_variant cv
        ON cv.id = pc.card_variant_id
    JOIN public.card c
        ON c.id = cv.card_id
    JOIN public.card_category cc
        ON cc.id = c.category_id
       AND cc.code = 'POKEMON'
    JOIN public.card_primary_species cps
        ON cps.card_id = c.id
    JOIN public.pokedex_position pp
        ON pp.pokedex_id = cpr.pokedex_id
       AND pp.species_id = cps.pokemon_species_id
    ON CONFLICT (collection_allocation_id) DO NOTHING;

    RETURN NULL;
END;
$$;

-- ----------------------------------------------------------------
-- 3. Correção de set_pokedex_position_assignment() (6122) — NULL
--    fail-closed, RETURNING/WHERE qualificados, lock Collection-first.
-- ----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_pokedex_position_assignment(
    p_physical_card_id UUID,
    p_pokedex_position_id UUID,
    p_confirm_override BOOLEAN DEFAULT false
)
RETURNS TABLE (
    collection_allocation_id UUID,
    pokedex_position_id UUID,
    assignment_basis TEXT,
    assigned_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_collection_allocation_id UUID;
    v_collection_id            UUID;
    v_lifecycle_status         TEXT;
    v_pokedex_id_from_col      UUID;
    v_pokedex_id_from_pos      UUID;
    v_species_id_from_pos      UUID;
    v_card_id                  UUID;
    v_category_code            TEXT;
    v_resolved_species_id      UUID;
    v_existing_position_id     UUID;
    v_basis                    TEXT;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'authentication required';
    END IF;

    IF p_physical_card_id IS NULL OR p_pokedex_position_id IS NULL THEN
        RAISE EXCEPTION 'SET_POKEDEX_POSITION_ASSIGNMENT_MISSING_PARAMETER: p_physical_card_id e p_pokedex_position_id são obrigatórios.';
    END IF;

    -- Leitura inicial (sem lock) só para descobrir qual Collection travar
    -- primeiro (PAUSE, item 3 — ordem de domínio Collection -> Allocation,
    -- padrão 5046/5047).
    SELECT ca.id, ca.collection_id
      INTO v_collection_allocation_id, v_collection_id
      FROM public.collection_allocation ca
      JOIN public.collection col ON col.id = ca.collection_id
     WHERE ca.physical_card_id = p_physical_card_id
       AND col.owner_user_id = auth.uid();

    IF NOT FOUND THEN
        RAISE EXCEPTION 'SET_POKEDEX_POSITION_ASSIGNMENT_NOT_ALLOCATED: physical_card não está alocado a uma Collection do chamador.';
    END IF;

    -- Lock real de Collection PRIMEIRO — ownership revalidada na própria
    -- WHERE do FOR UPDATE. Serializa contra archive_collection()/
    -- reactivate_collection() concorrente (PAUSE, item 3).
    SELECT col.lifecycle_status
      INTO v_lifecycle_status
      FROM public.collection col
     WHERE col.id = v_collection_id
       AND col.owner_user_id = auth.uid()
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'SET_POKEDEX_POSITION_ASSIGNMENT_NOT_ALLOCATED: physical_card não está alocado a uma Collection do chamador.';
    END IF;

    IF v_lifecycle_status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'SET_POKEDEX_POSITION_ASSIGNMENT_COLLECTION_ARCHIVED: collection is archived — reactivate before assigning.';
    END IF;

    -- Só DEPOIS do lock de Collection, trava e revalida a própria
    -- Allocation (ordem: Collection -> Allocation, nunca invertida).
    SELECT ca.id
      INTO v_collection_allocation_id
      FROM public.collection_allocation ca
     WHERE ca.physical_card_id = p_physical_card_id
       AND ca.collection_id = v_collection_id
     FOR UPDATE OF ca;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'SET_POKEDEX_POSITION_ASSIGNMENT_NOT_ALLOCATED: physical_card não está mais alocado a esta Collection (removido concorrentemente).';
    END IF;

    -- NO-OP CHECK (STAGING-AUDIT-01 item 3, preservado sem mudança de
    -- comportamento): resolvido antes de qualquer validação de Pokédex/
    -- Position/Species. Já usa alias "a." — nunca foi ambíguo.
    SELECT a.pokedex_position_id INTO v_existing_position_id
      FROM public.collection_pokedex_position_assignment a
     WHERE a.collection_allocation_id = v_collection_allocation_id;

    IF FOUND AND v_existing_position_id = p_pokedex_position_id THEN
        RETURN QUERY
        SELECT a.collection_allocation_id, a.pokedex_position_id, a.assignment_basis, a.assigned_at
          FROM public.collection_pokedex_position_assignment a
         WHERE a.collection_allocation_id = v_collection_allocation_id;
        RETURN;
    END IF;

    -- Collection precisa ser Pokédex E REFERENCE_BASED, explícito (PAUSE,
    -- item 4 — mesma defesa em profundidade já aplicada em 6119/trigger 1
    -- acima).
    SELECT cpr.pokedex_id INTO v_pokedex_id_from_col
      FROM public.collection col
      JOIN public.collection_reference cr ON cr.collection_id = col.id
      JOIN public.collection_pokedex_reference cpr ON cpr.collection_reference_id = cr.id
     WHERE col.id = v_collection_id
       AND col.mode = 'REFERENCE_BASED'
       AND cr.reference_kind = 'POKEDEX';

    IF v_pokedex_id_from_col IS NULL THEN
        RAISE EXCEPTION 'SET_POKEDEX_POSITION_ASSIGNMENT_NOT_POKEDEX_COLLECTION: collection não é uma Collection Pokédex REFERENCE_BASED.';
    END IF;

    SELECT pp.pokedex_id, pp.species_id
      INTO v_pokedex_id_from_pos, v_species_id_from_pos
      FROM public.pokedex_position pp
     WHERE pp.id = p_pokedex_position_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'SET_POKEDEX_POSITION_ASSIGNMENT_POSITION_NOT_FOUND: pokedex_position_id inexistente.';
    END IF;

    IF v_pokedex_id_from_pos IS DISTINCT FROM v_pokedex_id_from_col THEN
        RAISE EXCEPTION 'SET_POKEDEX_POSITION_ASSIGNMENT_WRONG_POKEDEX: a Position pertence a um Pokédex diferente do referenciado pela Collection.';
    END IF;

    SELECT c.id, cc.code
      INTO v_card_id, v_category_code
      FROM public.physical_card pc
      JOIN public.card_variant cv ON cv.id = pc.card_variant_id
      JOIN public.card c ON c.id = cv.card_id
      JOIN public.card_category cc ON cc.id = c.category_id
     WHERE pc.id = p_physical_card_id;

    SELECT cps.pokemon_species_id INTO v_resolved_species_id
      FROM public.card_primary_species cps
     WHERE cps.card_id = v_card_id;

    IF v_category_code = 'POKEMON'
       AND v_resolved_species_id IS NOT NULL
       AND v_resolved_species_id = v_species_id_from_pos
    THEN
        v_basis := 'SPECIES_MATCH';
    ELSE
        -- Fail-closed (PAUSE, item 1): NULL nunca é tratado como
        -- confirmação — só p_confirm_override = TRUE literal libera
        -- USER_OVERRIDE. "IF NOT p_confirm_override" original tratava
        -- NULL como falso-negativo (NOT NULL = NULL, IF NULL não entra),
        -- permitindo bypass silencioso da confirmação.
        IF p_confirm_override IS DISTINCT FROM TRUE THEN
            RAISE EXCEPTION 'SET_POKEDEX_POSITION_ASSIGNMENT_CONFIRMATION_REQUIRED: Card não corresponde à Species da Position (ou não é Pokémon/sem Species resolvida) — confirme explicitamente com p_confirm_override = true.';
        END IF;
        v_basis := 'USER_OVERRIDE';
    END IF;

    IF v_existing_position_id IS NOT NULL THEN
        -- MOVE: DELETE + INSERT, nunca UPDATE. WHERE qualificado pelo
        -- nome da tabela (PAUSE, item 2 — achado mais amplo que o
        -- mandato original: a mesma ambiguidade também existia aqui, não
        -- só na RETURNING do INSERT abaixo).
        DELETE FROM public.collection_pokedex_position_assignment
         WHERE collection_pokedex_position_assignment.collection_allocation_id = v_collection_allocation_id;
    END IF;

    -- RETURNING qualificada pelo nome da tabela (PAUSE, item 2).
    RETURN QUERY
    INSERT INTO public.collection_pokedex_position_assignment
        (collection_allocation_id, pokedex_position_id, assignment_basis, assigned_at, assigned_by_user_id)
    VALUES (
        v_collection_allocation_id,
        p_pokedex_position_id,
        v_basis,
        NOW(),
        CASE WHEN v_basis = 'USER_OVERRIDE' THEN auth.uid() ELSE NULL END
    )
    RETURNING
        collection_pokedex_position_assignment.collection_allocation_id,
        collection_pokedex_position_assignment.pokedex_position_id,
        collection_pokedex_position_assignment.assignment_basis,
        collection_pokedex_position_assignment.assigned_at;
END;
$$;

COMMENT ON FUNCTION public.set_pokedex_position_assignment(UUID, UUID, BOOLEAN) IS
    'Cria ou move (DELETE+INSERT atômico, nunca UPDATE) uma Pokédex Position Assignment. SPECIES_MATCH automático quando a Primary Species da Card corresponde à Species da Position; caso contrário exige p_confirm_override = true (NULL não conta como confirmação, fail-closed) -> USER_OVERRIDE. Idempotente quando a Position não muda. Ownership via auth.uid(); Collection precisa estar ACTIVE, ser Pokédex e REFERENCE_BASED; Position precisa pertencer ao mesmo Pokédex da Collection. Lock order: Collection primeiro, depois Allocation (correção PAUSE-SQL-DIRECT-AUDIT-01).';

COMMIT;
