/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 6122 - Create set_pokedex_position_assignment() Function
Versão......: 1.1 (CONFIRMADO EXECUTADO E PROMOVIDO)
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-05 (staging em COLLECTIONS-POKEDEX-FATIA-D-STAGING-01,
               após -PHYSICAL-MODELING-AUDIT-01 e
               -PHYSICAL-MODELING-REVISION-01, item 1;
               revisado em ...-STAGING-AUDIT-01, item 3; fix adicional
               em GATE 4 (reordenar no-op check); executada no banco
               real em IMPLEMENTATION-RESUME-02; promovida para
               database/schema/ em COLLECTIONS-POKEDEX-FATIA-D-
               PROMOTION-CLOSEOUT-01 — corpo SQL byte-idêntico ao
               executado, apenas cabeçalho Status/Versão/Data
               atualizados)

Correção v1.1 (STAGING-AUDIT-01, item 3) — bug real encontrado: na
versão 1.0, a checagem de "já existe Assignment para esta Allocation
com a MESMA Position" (no-op idempotente) rodava só DEPOIS das
checagens de Collection-é-Pokédex, Position-pertence-ao-Pokédex e
resolução de SPECIES_MATCH/USER_OVERRIDE. Isso violava literalmente
"mesma Position -> no-op real" (mandato desta rodada): se a evidência
de card_primary_species tivesse mudado depois que a Assignment original
foi criada (ex.: uma correção editorial posterior mudou a Primary
Species resolvida da Card), uma chamada de reafirmação idempotente
para a MESMA Position já atribuída podia ser incorretamente bloqueada
exigindo p_confirm_override = true, mesmo a Position já estando
correta e nada precisando mudar. Corrigido: a checagem de no-op agora
roda IMEDIATAMENTE após resolver ownership+lifecycle (ANTES de
Collection-é-Pokédex, Position-pertence-ao-Pokédex e SPECIES_MATCH/
USER_OVERRIDE) — se a Position-alvo já é a Position atual da
Assignment existente, a função retorna a linha existente de imediato,
sem rodar nenhuma validação adicional. Toda a cadeia de validação
(passos 3-5 do ALGORITMO abaixo) só roda quando não há Assignment
ainda, ou quando a Position-alvo é DIFERENTE da Position atual (caso
em que é, de fato, um MOVE ou uma CREATE, e precisa ser plenamente
revalidado).

Descrição...:
Único ponto de escrita para criar OU mover uma Pokédex Position
Assignment (LDM-178/179). Cobre tanto o caminho SPECIES_MATCH manual
(quando o trigger automático da Query 6119 não disparou, por exemplo
porque a Card não tinha Primary Species resolvida no momento da
Allocation, mas passou a ter depois) quanto USER_OVERRIDE.

CONTRATO:
    set_pokedex_position_assignment(
        p_physical_card_id UUID,
        p_pokedex_position_id UUID,
        p_confirm_override BOOLEAN DEFAULT false
    )

ALGORITMO (reordenado em v1.1, STAGING-AUDIT-01 item 3):
1. Ownership: resolve collection_allocation_id a partir de
   p_physical_card_id, exigindo que a Collection pertença a auth.uid()
   (mesmo padrão de allocate_physical_cards_to_collection, 2C).
2. Collection precisa estar ACTIVE (LDM-185).
3. NO-OP CHECK (movido para cá em v1.1 — antes valia como último passo
   antes da escrita, o que permitia que o bloqueio do passo 5 disparasse
   indevidamente para uma reafirmação idempotente): se já existe uma
   Assignment para esta Allocation E sua pokedex_position_id já é
   p_pokedex_position_id, retorna a linha existente IMEDIATAMENTE — não
   roda os passos 4-6 abaixo. "Mesma Position -> no-op real", sem
   depender de nenhuma validação de Species ainda ser satisfeita.
4. Collection precisa ser Pokédex (reference_kind = 'POKEDEX') — mesma
   checagem do trigger da Query 6118, repetida aqui para uma mensagem
   de erro mais específica antes de qualquer escrita. Só roda quando o
   passo 3 não retornou (não é no-op).
5. Position precisa pertencer ao mesmo Pokédex da Collection (LDM-179,
   item B da auditoria) — mesma checagem do trigger da Query 6118,
   repetida aqui pela mesma razão. Só roda quando o passo 3 não
   retornou.
6. Resolve Species Match: Card categoria POKEMON com card_primary_
   species resolvida E igual à Species da Position -> SPECIES_MATCH.
   Qualquer outro caso (mismatch, sem Species resolvida, ou categoria
   != POKEMON) exige p_confirm_override = true, senão RAISE EXCEPTION
   ANTES de qualquer escrita -> USER_OVERRIDE quando confirmado. Só
   roda quando o passo 3 não retornou.
7. MOVE vs. CREATE (Revision-01, item 1 — correção estrutural desta
   rodada): a linha é imutável (Query 6118, trg_020) — nunca um
   UPDATE de pokedex_position_id.
   - Já existe Assignment para esta Allocation com Position DIFERENTE
     (única possibilidade restante aqui, já que o caso "mesma Position"
     foi resolvido e retornado no passo 3): DELETE da linha antiga (o
     CASCADE da Query 6120 já remove um Primary Representative órfão
     que apontasse para ela, sem trigger de sincronização adicional)
     seguido de INSERT da linha nova — dois statements na MESMA chamada
     de função, logo na MESMA transação: qualquer RAISE EXCEPTION entre
     o DELETE e o INSERT (ex.: passo 6 falhar para a nova Position)
     desfaz TUDO, inclusive o DELETE já executado — a Assignment antiga
     nunca fica "no limbo".
   - Não existe Assignment ainda: INSERT direto.
8. RETURNING sempre reflete o estado final da linha (existente,
   recriada, ou nova).

Compatibilidade com o fluxo UX atômico futuro (Revision-01, item 2,
provado sem implementar): como esta função e
allocate_physical_cards_to_collection() (2C) são ambas funções plpgsql
comuns no mesmo schema, uma futura RPC orquestradora ("Position
selecionada -> escolher Physical Card -> validar -> alocar -> criar
Assignment -> tudo ou nada") pode simplesmente CHAMAR as duas em
sequência dentro do próprio corpo, sem duplicar nenhuma validação de
ownership/allocation/SPECIES_MATCH/USER_OVERRIDE — qualquer RAISE
EXCEPTION em qualquer uma delas desfaz a transação inteira,
automaticamente, porque ambas rodam na mesma transação implícita de
uma única chamada de RPC. Nenhuma mudança é necessária nesta função
nem em allocate_physical_cards_to_collection() para viabilizar isso no
futuro — não implementado nesta rodada.

Pré-requisitos:
- Query 6117/6118 - Collection Pokédex Position Assignment + Triggers.
- Query 6112 - Create Card Primary Species Table.
================================================================
*/

BEGIN;

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

    SELECT ca.id, ca.collection_id
      INTO v_collection_allocation_id, v_collection_id
      FROM public.collection_allocation ca
      JOIN public.collection col ON col.id = ca.collection_id
     WHERE ca.physical_card_id = p_physical_card_id
       AND col.owner_user_id = auth.uid()
     FOR UPDATE OF ca;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'SET_POKEDEX_POSITION_ASSIGNMENT_NOT_ALLOCATED: physical_card não está alocado a uma Collection do chamador.';
    END IF;

    SELECT col.lifecycle_status INTO v_lifecycle_status
      FROM public.collection col WHERE col.id = v_collection_id;

    IF v_lifecycle_status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'SET_POKEDEX_POSITION_ASSIGNMENT_COLLECTION_ARCHIVED: collection is archived — reactivate before assigning.';
    END IF;

    -- NO-OP CHECK (STAGING-AUDIT-01, item 3): resolvido ANTES de
    -- qualquer validação de Pokédex/Position/Species. Se a Assignment
    -- já existe e já aponta para p_pokedex_position_id, é uma
    -- reafirmação idempotente — retorna direto, sem revalidar nada.
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

    SELECT cpr.pokedex_id INTO v_pokedex_id_from_col
      FROM public.collection_reference cr
      JOIN public.collection_pokedex_reference cpr ON cpr.collection_reference_id = cr.id
     WHERE cr.collection_id = v_collection_id
       AND cr.reference_kind = 'POKEDEX';

    IF v_pokedex_id_from_col IS NULL THEN
        RAISE EXCEPTION 'SET_POKEDEX_POSITION_ASSIGNMENT_NOT_POKEDEX_COLLECTION: collection não é uma Collection Pokédex.';
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
        IF NOT p_confirm_override THEN
            RAISE EXCEPTION 'SET_POKEDEX_POSITION_ASSIGNMENT_CONFIRMATION_REQUIRED: Card não corresponde à Species da Position (ou não é Pokémon/sem Species resolvida) — confirme explicitamente com p_confirm_override = true.';
        END IF;
        v_basis := 'USER_OVERRIDE';
    END IF;

    -- Se chegou até aqui, as validações de Pokédex/Position/Species
    -- (passos 4-6, acima) já rodaram e passaram. Ou não havia Assignment
    -- ainda (v_existing_position_id NULL -> CREATE), ou havia uma com
    -- Position DIFERENTE (o caso "mesma Position" já retornou no NO-OP
    -- CHECK antes dessas validações rodarem -> MOVE).
    IF v_existing_position_id IS NOT NULL THEN
        -- MOVE (Revision-01, item 1): DELETE + INSERT, nunca UPDATE.
        -- O CASCADE da Query 6120 já remove um Primary Representative
        -- órfão apontando para a linha antiga. A resolução de Species
        -- (passo 6, acima) já rodou e já passou antes deste DELETE —
        -- se tivesse falhado, teria levantado exceção antes de chegar
        -- aqui, e este DELETE nunca seria executado. O único caso em
        -- que este DELETE já executado precisaria ser desfeito é um
        -- erro no INSERT logo abaixo, o que o Postgres resolve
        -- desfazendo a transação inteira da própria chamada de RPC —
        -- a Assignment antiga nunca fica "no limbo" (ver header, passo 7).
        DELETE FROM public.collection_pokedex_position_assignment
         WHERE collection_allocation_id = v_collection_allocation_id;
    END IF;

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
    RETURNING collection_allocation_id, pokedex_position_id, assignment_basis, assigned_at;
END;
$$;

COMMENT ON FUNCTION public.set_pokedex_position_assignment(UUID, UUID, BOOLEAN) IS
    'Cria ou move (DELETE+INSERT atômico, nunca UPDATE) uma Pokédex Position Assignment. SPECIES_MATCH automático quando a Primary Species da Card corresponde à Species da Position; caso contrário exige p_confirm_override = true -> USER_OVERRIDE. Idempotente quando a Position não muda. Ownership via auth.uid(); Collection precisa estar ACTIVE e ser Pokédex; Position precisa pertencer ao mesmo Pokédex da Collection.';

REVOKE ALL ON FUNCTION public.set_pokedex_position_assignment(UUID, UUID, BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_pokedex_position_assignment(UUID, UUID, BOOLEAN) FROM anon;
GRANT EXECUTE ON FUNCTION public.set_pokedex_position_assignment(UUID, UUID, BOOLEAN) TO authenticated;

COMMIT;
