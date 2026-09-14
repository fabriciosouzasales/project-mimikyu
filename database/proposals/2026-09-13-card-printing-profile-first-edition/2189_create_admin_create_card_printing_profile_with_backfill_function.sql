/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2189 - Create Card Printing Profile with Backfill (worker + RPC)
Versão......: 2.1
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-13
Mandato.....: CARD-VARIANTS — EDITORIAL-CONVERGENCE-10 /
              FIRST-EDITION-PROFILE-IMPLEMENTATION-01 / GATE-A-STAGING-01 (§2–§11)
              + GATE-A-REV-01 (§2–§5, §12) + GATE-A-REV-02 (§1)
              + GATE-A-REV-03 (§1) — contrato NEW-only

-------------------------------------------------------------------------------
Alterações da versão 2.1 (GATE-A-REV-03) — ÚNICA mudança executável desta rodada
-------------------------------------------------------------------------------
Removido o lookup em public.card_variant do PASSO 8. O CTE `matched` deixou de
existir e o UPDATE passa a fixar, para toda linha tocada:

    match_status       = 'NEW'
    matched_variant_id = NULL

Motivo: MATCHED era inalcançável POR CONTRATO, não apenas descoberto. Esta
função cria o Perfil, sela, seleciona só linhas que resolvem para esse Perfil
recém-criado e nunca cria card_variant — logo nenhuma card_variant pode
referenciar o UUID em questão no instante do backfill.

`card_id` saiu das projeções de `touched` e `classified` junto: seu único
consumidor era o lookup removido.

Preservados sem alteração: outcomes A/B/C, normalized_data, validation_status,
error_detail = NULL, resulting_variant_id intocado, contadores, action log,
guards, selo, elegibilidade e locks.

-------------------------------------------------------------------------------
Alterações da versão 2.0 (GATE-A-REV-01)
-------------------------------------------------------------------------------
A v1.0 tinha UMA função pública que acumulava fronteira de autorização e
núcleo transacional. Consequência prática, apontada na revisão:

  - o único caminho de execução exigia auth.uid()/is_admin();
  - esta frente NÃO tem UI nem Edge Function que invoque a RPC;
  - portanto o teste POSITIVO e a execução REAL só aconteceriam forjando
    request.jwt.claims — técnica que o ambiente operacional desta sessão
    recusou explicitamente (Security Weaken) durante PokéTour/BASE1.

Promover um desenho cujo caminho feliz depende de fabricar contexto de
sessão é promover um desenho que não pode ser executado nem testado
honestamente. A v2.0 corta isso na raiz SEPARANDO as duas coisas:

    internal.create_card_printing_profile_with_backfill(p_actor_id, ...)
        -> TODO o núcleo transacional. Owner-only. NÃO usa auth.uid().
           p_actor_id é PARÂMETRO EXPLÍCITO DE AUDITORIA, validado contra
           public.admin_user.

    public.admin_create_card_printing_profile_with_backfill(...)
        -> fronteira FINA: is_admin() -> auth.uid() -> delega ao worker.
           Zero lógica de Profile/backfill.

Nenhuma semântica aprovada mudou: elegibilidade, locks JOB->ROW, tri-state,
outcomes A/B/C, match_status, contadores, reconciliação e o tratamento
IMMEDIATE -> provas -> DEFERRED são byte-a-byte os mesmos da v1.0, apenas
realocados para dentro do worker.

Ganho colateral: passa a existir um caminho de manutenção legítimo — o owner
chama o worker informando QUAL administrador autorizou a operação. Isso é
mais honesto que impersonar uma sessão: o log grava o autorizador real, e não
uma identidade fabricada.

-------------------------------------------------------------------------------
Descrição resumida
-------------------------------------------------------------------------------
Criação de Perfil de Impressão + reconciliação do staging de Card Variants que
a existência desse Perfil passa a resolver, numa transação única.

GENÉRICA. Nada de FIRST_EDITION aparece na lógica: a composição é o parâmetro
p_trait_ids e o universo do backfill é DERIVADO do Perfil recém-criado.

-------------------------------------------------------------------------------
POR QUE ESTA FUNÇÃO EXISTE (lacuna G-2)
-------------------------------------------------------------------------------
- criar MAPEAMENTO externo de Impressão tem RPC com backfill (Query 2181);
- criar MAPEAMENTO de Variant Type tem o mesmo (Queries 2150/2158);
- criar um PERFIL não tinha nada. Os 6 Perfis vieram da seed 2169.

Medido em 2026-09-13: 62 linhas de BASE3 presas em NEEDS_REVIEW_NO_PROFILE
com assinatura {FIRST_EDITION}, sem caminho editorial nenhum.

-------------------------------------------------------------------------------
O SELO É DIFERIDO — E ISSO DECIDE O DESENHO
-------------------------------------------------------------------------------
Leia antes de alterar qualquer coisa.

trg_card_printing_profile_seal (Query 2168) é
`CONSTRAINT TRIGGER ... DEFERRABLE INITIALLY DEFERRED`: só dispara no COMMIT.
Antes disso card_printing_profile.traits_signature É NULL.

E internal.compute_variant_residual_signature() (Query 2176, linhas 162-165)
procura o Perfil por:

    WHERE p.game_id = p_game_id AND p.traits_signature = v_sig

Um backfill na MESMA transação, sem forçar o selo, encontraria NULL, casaria
ZERO linhas e retornaria rows_touched = 0 SEM ERRO — parecendo ter funcionado.

Mitigação obrigatória, dentro do worker:

    SET CONSTRAINTS public.trg_card_printing_profile_seal IMMEDIATE;

`SET CONSTRAINTS` é comando utilitário (não é controle transacional) e é
permitido em plpgsql. Depois dele: assinatura materializada,
CARD_PRINTING_PROFILE_EMPTY_COMPOSITION já teria abortado, e
uq_card_printing_profile_game_signature já rejeitou composição duplicada.
Todos os modos de falha do Perfil acontecem ANTES do backfill.

RESTAURAÇÃO. Ao final o worker executa

    SET CONSTRAINTS public.trg_card_printing_profile_seal DEFERRED;

porque `SET CONSTRAINTS` tem escopo de TRANSAÇÃO, não de função. Sem
restaurar, uma transação externa que continuasse criando Perfis por outro
caminho teria o selo disparando a cada INSERT — comportamento diferente do
contratado pela Query 2168.

-------------------------------------------------------------------------------
CONTRATO DE CRIAÇÃO (Queries 2166/2167/2168)
-------------------------------------------------------------------------------
1. INSERT card_printing_profile com traits_signature = NULL ("em montagem")
2. INSERT card_printing_profile_trait (1..N)   (liberado enquanto NULL)
3. SET CONSTRAINTS ... IMMEDIATE  -> sela, valida, deduplica
4. reler e PROVAR o selo
5. só então reconciliar o staging

traits_signature NUNCA é escrita pela função — aceitá-la como parâmetro seria
convidar o selo falsificado que enforce_printing_profile_signature_write
existe para impedir. is_active também não é parâmetro (DEFAULT true).
game_id é DERIVADO dos traits: transforma o same-game guard estrutural (FKs
compostas da 2167) em validação de entrada com mensagem legível.

-------------------------------------------------------------------------------
ELEGIBILIDADE DO BACKFILL
-------------------------------------------------------------------------------
    job.status             = 'STAGED'
AND row.decision_status    = 'PENDING'
AND row.persistence_status = 'PENDING'

Os dois últimos NÃO são redundantes. Em 2026-09-13 havia 931 linhas em jobs
STAGED já decididas e persistidas (BASE1 412, SV5 408, SVE 64, BASEP 47) —
linhas com card_variant REAL. Recomputar o validation_status delas produziria
registro que contradiz o fato físico.

Diferente do precedente de Cards (2105/2106), que preserva decisões por
OMISSÃO DE COLUNA e recalcula todas as linhas do job, aqui o filtro é de
LINHA. Omissão de coluna preserva a decisão; só o filtro preserva a coerência
entre registro e persistência.

-------------------------------------------------------------------------------
OUTCOMES — o backfill NÃO é "NR -> VALID"
-------------------------------------------------------------------------------
A. Printing resolvido + Variant Type resolvido
   -> variant_type_id UUID, printing_profile_id UUID/JSON null, VALID
B. Printing resolvido + Variant Type NÃO resolvido
   -> variant_type_id REMOVIDO, printing_profile_id gravado, NEEDS_REVIEW
C. Printing NÃO resolvido
   -> as DUAS chaves removidas, NEEDS_REVIEW

O outcome B é o coração do contrato: a linha recebe o Perfil e CONTINUA
NEEDS_REVIEW porque o outro eixo não fechou. O backfill materializa o que
ficou provado, não só o que ficou completo.

Para {FIRST_EDITION} em 2026-09-13: 62 touched = 16 A + 46 B + 0 C.

C é estruturalmente inalcançável pelo critério de seleção (só entram linhas
cujo Printing resolveu PARA este Perfil), mas está implementado porque o
estado pode mudar entre a seleção e a escrita sob lock — e aí o desfecho
honesto é remover as duas chaves, não preservar conclusão tirada de premissa
inválida (mesmo raciocínio do tri-state da Query 2181).

-------------------------------------------------------------------------------
TRI-STATE (contrato final, Queries 2177/2181)
-------------------------------------------------------------------------------
    resolvido sem perfil  -> printing_profile_id : null   (JSON null)
    resolvido com perfil  -> printing_profile_id : "uuid" (string)
    não resolvido         -> chave AUSENTE

Ausência NUNCA significa null. jsonb_typeof distingue; `->>` não.

-------------------------------------------------------------------------------
Pré-requisitos
-------------------------------------------------------------------------------
- Query 2165/2166/2167/2168 - Printing Trait, Profile, composição e guards.
- Query 2176 - internal.compute_variant_residual_signature().
- Query 2177 - identidade de staging (índices parciais do tri-state).
- Query 2188 - widen do action log para CARD_PRINTING_PROFILE (APLICAR ANTES).
- Query 2140 - card_variant_type_external_mapping.
- Query 2000 - schema internal.

-------------------------------------------------------------------------------
REVISION HISTORY
-------------------------------------------------------------------------------
| 1.0 | **Versão inicial (2026-09-13).** Função pública única acumulando
        autorização e núcleo transacional. NÃO EXECUTADA. |
| 2.0 | **Separação worker/fronteira (2026-09-13, GATE-A-REV-01).** Núcleo
        movido para internal.create_card_printing_profile_with_backfill(),
        owner-only, com p_actor_id explícito e sem auth.uid(). A RPC pública
        vira fronteira fina (is_admin + auth.uid + delegação). Motivo: o
        caminho positivo da v1.0 só era executável/testável forjando
        request.jwt.claims. Nenhuma semântica de Profile/backfill alterada.
        Ainda NÃO EXECUTADA. |
| 2.1 | **Contrato NEW-only (2026-09-13, GATE-A-REV-03).** Removido o lookup em
        public.card_variant no PASSO 8 (CTE `matched`) e fixados match_status =
        'NEW' e matched_variant_id = NULL para toda linha tocada. Motivo: um
        Printing Profile recém-criado não pode ter card_variant preexistente
        apontando para seu UUID — MATCHED era inalcançável por contrato, não
        apenas não coberto por teste. `card_id` saiu de `touched`/`classified`
        por ter perdido o único consumidor. Nada mais mudou. NÃO EXECUTADA. |
===============================================================================
*/

BEGIN;

-- =============================================================================
-- WORKER — internal.create_card_printing_profile_with_backfill()
--
-- Superfície OWNER-ONLY. Concentra TODA a lógica transacional. Não conhece
-- auth.uid(): o administrador autorizador chega como p_actor_id e é validado
-- contra public.admin_user.
-- =============================================================================
CREATE OR REPLACE FUNCTION internal.create_card_printing_profile_with_backfill(
    p_actor_id      UUID,
    p_code          TEXT,
    p_name          TEXT,
    p_description   TEXT,
    p_display_order INTEGER,
    p_trait_ids     UUID[]
)
RETURNS TABLE(
    profile_id         UUID,
    traits_signature   UUID[],
    rows_touched       INTEGER,
    rows_revalidated   INTEGER,
    rows_still_pending INTEGER,
    jobs_affected      INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $worker$
DECLARE
    -- Teto de composição. Um Perfil real tem 1..3 traits; 64 é folga ampla e
    -- mantém custo previsível. Mesma disciplina de teto das Queries 2163/6115.
    c_max_trait_ids CONSTANT INTEGER := 64;

    v_code        TEXT;
    v_name        TEXT;
    v_description TEXT;

    v_trait_count    INTEGER;
    v_distinct_count INTEGER;
    v_game_count     INTEGER;
    v_inactive       TEXT;
    v_unknown        INTEGER;

    v_game_id    UUID;
    v_profile_id UUID;
    v_expected   UUID[];
    v_sealed     UUID[];
    v_active     BOOLEAN;

    v_row_ids  UUID[];
    v_job_ids  UUID[];

    v_touched     INTEGER := 0;
    v_revalidated INTEGER := 0;
    v_pending     INTEGER := 0;
    v_jobs        INTEGER := 0;
    v_reconciled  INTEGER := 0;
BEGIN
    -- =====================================================================
    -- GUARD 1 — ATOR. Primeira instrução.
    --
    -- O worker NÃO consulta auth.uid(). Quem autoriza chega por parâmetro e
    -- precisa ser um administrador REAL. Isso serve aos dois caminhos:
    -- a RPC pública passa auth.uid() (sessão real verificada lá), e a
    -- manutenção por owner passa o admin que explicitamente autorizou.
    --
    -- public.admin_user.id referencia auth.users, então existir aqui já
    -- implica usuário válido — não há como injetar um UUID arbitrário.
    -- =====================================================================
    IF p_actor_id IS NULL THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_MISSING_ACTOR: p_actor_id é obrigatório. Toda criação de Perfil precisa de um administrador autorizador nomeado.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.admin_user a WHERE a.id = p_actor_id) THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_ACTOR_NOT_ADMIN: p_actor_id (%) não corresponde a um administrador cadastrado em public.admin_user.', p_actor_id;
    END IF;

    -- =====================================================================
    -- GUARD 2 — ESCALARES.
    -- =====================================================================
    v_code        := upper(btrim(coalesce(p_code, '')));
    v_name        := btrim(coalesce(p_name, ''));
    v_description := btrim(coalesce(p_description, ''));
    IF v_description = '' THEN v_description := NULL; END IF;

    -- Mesmo formato da CHECK ck_card_printing_profile_code_format.
    IF v_code = '' OR v_code !~ '^[A-Z][A-Z0-9_]*$' THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_INVALID_CODE: código inválido (%). Esperado ^[A-Z][A-Z0-9_]*$.', p_code;
    END IF;

    IF v_name = '' THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_INVALID_NAME: o nome não pode ser vazio.';
    END IF;

    IF p_display_order IS NULL OR p_display_order <= 0 THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_INVALID_DISPLAY_ORDER: ordem inválida (%). Precisa ser inteiro positivo.', p_display_order;
    END IF;

    -- =====================================================================
    -- GUARD 3 — FORMA DO ARRAY DE TRAITS.
    --
    -- array_ndims ANTES de qualquer ANY(): um array multidimensional passa
    -- por array_length(...,1) reportando só a primeira dimensão, enquanto
    -- ANY() varre TODOS os elementos. Fail-closed, lição da Query 2163.
    -- =====================================================================
    IF p_trait_ids IS NULL THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_MISSING_TRAITS: p_trait_ids é obrigatório e não pode ser vazio.';
    END IF;

    IF array_ndims(p_trait_ids) <> 1 THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_INVALID_ARRAY_SHAPE: p_trait_ids deve ser um array de uma única dimensão (recebido: % dimensões).', array_ndims(p_trait_ids);
    END IF;

    v_trait_count := cardinality(p_trait_ids);

    IF v_trait_count = 0 THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_MISSING_TRAITS: p_trait_ids é obrigatório e não pode ser vazio.';
    END IF;

    IF v_trait_count > c_max_trait_ids THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_TOO_MANY_TRAITS: p_trait_ids tem % ids, acima do teto de % por Perfil.', v_trait_count, c_max_trait_ids;
    END IF;

    IF array_position(p_trait_ids, NULL) IS NOT NULL THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_NULL_TRAIT: p_trait_ids contém elemento NULL.';
    END IF;

    SELECT count(DISTINCT t) INTO v_distinct_count FROM unnest(p_trait_ids) AS t;

    IF v_distinct_count <> v_trait_count THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_DUPLICATE_TRAIT: p_trait_ids tem % elementos mas apenas % distintos. Composição é um CONJUNTO.', v_trait_count, v_distinct_count;
    END IF;

    -- =====================================================================
    -- GUARD 4 — EXISTÊNCIA, ATIVIDADE E GAME ÚNICO. game_id é derivado aqui.
    -- =====================================================================
    SELECT count(*) INTO v_unknown
      FROM unnest(p_trait_ids) AS t(id)
     WHERE NOT EXISTS (SELECT 1 FROM public.card_printing_trait ct WHERE ct.id = t.id);

    IF v_unknown > 0 THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_TRAIT_NOT_FOUND: % dos ids informados não existem em card_printing_trait.', v_unknown;
    END IF;

    SELECT string_agg(ct.code, ', ' ORDER BY ct.code) INTO v_inactive
      FROM public.card_printing_trait ct
     WHERE ct.id = ANY(p_trait_ids) AND NOT ct.is_active;

    IF v_inactive IS NOT NULL THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_TRAIT_INACTIVE: Característica(s) de Impressão inativa(s) na composição: %. Um Perfil ativo não pode ser composto por trait desativado.', v_inactive;
    END IF;

    SELECT count(DISTINCT ct.game_id), min(ct.game_id)
      INTO v_game_count, v_game_id
      FROM public.card_printing_trait ct
     WHERE ct.id = ANY(p_trait_ids);

    IF v_game_count <> 1 THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_MIXED_GAME: os traits informados pertencem a % Games distintos. Um Perfil pertence a exatamente um Game.', v_game_count;
    END IF;

    -- =====================================================================
    -- GUARD 5 — UNICIDADE (mensagem amigável; as constraints continuam sendo
    -- a autoridade final e decidem sob concorrência).
    -- =====================================================================
    IF EXISTS (SELECT 1 FROM public.card_printing_profile p
                WHERE p.game_id = v_game_id AND p.code = v_code) THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_DUPLICATE_CODE: já existe um Perfil de Impressão com o código % para este Game.', v_code;
    END IF;

    IF EXISTS (SELECT 1 FROM public.card_printing_profile p
                WHERE p.game_id = v_game_id AND p.display_order = p_display_order) THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_DUPLICATE_DISPLAY_ORDER: já existe um Perfil de Impressão com a ordem % para este Game.', p_display_order;
    END IF;

    -- Assinatura canônica: conjunto ordenado ascendente pelo próprio id —
    -- mesma ordem que seal_printing_profile_composition() vai calcular.
    v_expected := ARRAY(SELECT DISTINCT t FROM unnest(p_trait_ids) AS t ORDER BY t);

    IF EXISTS (SELECT 1 FROM public.card_printing_profile p
                WHERE p.game_id = v_game_id AND p.traits_signature = v_expected) THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_DUPLICATE_SIGNATURE: já existe um Perfil de Impressão com exatamente esta composição neste Game. Composição é identidade — reutilize o Perfil existente.';
    END IF;

    -- =====================================================================
    -- PASSO 1 — CRIAR O PERFIL "EM MONTAGEM" (traits_signature = NULL).
    -- =====================================================================
    INSERT INTO public.card_printing_profile
        (game_id, code, name, description, display_order)
    VALUES
        (v_game_id, v_code, v_name, v_description, p_display_order)
    RETURNING id INTO v_profile_id;

    -- =====================================================================
    -- PASSO 2 — COMPOSIÇÃO. Liberada enquanto a assinatura for NULL.
    -- =====================================================================
    INSERT INTO public.card_printing_profile_trait (profile_id, trait_id, game_id)
    SELECT v_profile_id, t, v_game_id FROM unnest(v_expected) AS t;

    -- =====================================================================
    -- PASSO 3 — FORÇAR O SELO. VER O CABEÇALHO.
    -- Sem esta linha o backfill abaixo casaria ZERO linhas, em silêncio.
    -- =====================================================================
    SET CONSTRAINTS public.trg_card_printing_profile_seal IMMEDIATE;

    -- =====================================================================
    -- PASSOS 4 e 5 — RELER E PROVAR O SELO. Fail-closed.
    -- =====================================================================
    SELECT p.traits_signature, p.is_active
      INTO v_sealed, v_active
      FROM public.card_printing_profile p
     WHERE p.id = v_profile_id;

    IF v_sealed IS NULL THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_SEAL_NOT_APPLIED: traits_signature continua NULL depois de SET CONSTRAINTS IMMEDIATE. O trigger de selo não disparou — qualquer backfill a partir daqui seria vazio e silencioso. STOP.';
    END IF;

    IF cardinality(v_sealed) <> v_trait_count THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_SEAL_CARDINALITY: assinatura selada tem % traits, esperado %.', cardinality(v_sealed), v_trait_count;
    END IF;

    IF v_sealed IS DISTINCT FROM v_expected THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_SEAL_MISMATCH: a assinatura selada não corresponde aos trait_ids informados (ordenados).';
    END IF;

    IF v_active IS NOT TRUE THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_NOT_ACTIVE: o Perfil recém-criado não está ativo. Estado estruturalmente inesperado. STOP.';
    END IF;

    -- =====================================================================
    -- PASSO 6 — SELEÇÃO DAS CANDIDATAS.
    --
    -- Derivada do Perfil, nunca de literal: entram as linhas elegíveis cujo
    -- roteamento de Impressão resolve PARA ESTE profile_id. Passa pela
    -- máquina de estados inteira da Query 2176 — trait inativo, mapping
    -- inativo e perfil inativo continuam excluindo a linha, de graça.
    -- =====================================================================
    SELECT ARRAY(
        SELECT r.id
          FROM public.catalog_variant_import_row r
          JOIN public.catalog_variant_import_job j ON j.id = r.job_id
          JOIN public.card_set cs    ON cs.id = j.card_set_id
          JOIN public.expansion e    ON e.id  = cs.expansion_id
          JOIN public.asset_source s ON s.code = j.source
          CROSS JOIN LATERAL internal.compute_variant_residual_signature(
              r.raw_data, e.game_id, s.id
          ) sig
         WHERE j.status = 'STAGED'
           AND r.decision_status = 'PENDING'
           AND r.persistence_status = 'PENDING'
           AND e.game_id = v_game_id
           AND sig.printing_profile_id = v_profile_id
         ORDER BY r.id
    ) INTO v_row_ids;

    IF v_row_ids IS NULL OR cardinality(v_row_ids) = 0 THEN
        -- Nenhuma linha a reconciliar é desfecho LEGÍTIMO: um Perfil pode ser
        -- cadastrado antes de existir staging que o use. Segue para o log.
        v_row_ids := ARRAY[]::UUID[];
        v_job_ids := ARRAY[]::UUID[];
    ELSE
        SELECT ARRAY(
            SELECT DISTINCT r.job_id
              FROM public.catalog_variant_import_row r
             WHERE r.id = ANY(v_row_ids)
             ORDER BY 1
        ) INTO v_job_ids;

        -- =================================================================
        -- PASSO 7 — LOCKS. Ordem JOB -> ROW, determinística nos dois níveis.
        --
        -- JOB antes de ROW é a mesma ordem de
        -- admin_confirm_catalog_variant_import (2145/2179): os dois
        -- serializam em vez de deadlockar. ORDER BY id evita deadlock contra
        -- qualquer outro caminho que trave as mesmas linhas.
        --
        -- O lock de ROW é indispensável: admin_decide_catalog_variant_import_
        -- row (2144/2163) NÃO trava o job — opera por p_row_ids — e portanto
        -- o lock de job sozinho não a serializa.
        -- =================================================================
        PERFORM 1
           FROM public.catalog_variant_import_job j
          WHERE j.id = ANY(v_job_ids)
          ORDER BY j.id
            FOR UPDATE;

        PERFORM 1
           FROM public.catalog_variant_import_row r
          WHERE r.id = ANY(v_row_ids)
          ORDER BY r.id
            FOR UPDATE;

        -- =================================================================
        -- PASSO 8 — RECONCILIAÇÃO. Set-based, uma única instrução.
        --
        -- A elegibilidade é REAVALIADA sob o lock e o roteamento é
        -- RECOMPUTADO — não se reaproveita o resultado da seleção. Se algo
        -- mudou nesse intervalo, o desfecho reflete o estado real.
        -- =================================================================
        WITH touched AS (
            SELECT r.id,
                   r.job_id,
                   sig.printing_state,
                   sig.printing_profile_id,
                   sig.residual_type,
                   sig.residual_foil,
                   sig.residual_subtype,
                   sig.residual_stamp,
                   e.game_id AS game_id,
                   s.id      AS asset_source_id
              FROM public.catalog_variant_import_row r
              JOIN public.catalog_variant_import_job j ON j.id = r.job_id
              JOIN public.card_set cs    ON cs.id = j.card_set_id
              JOIN public.expansion e    ON e.id  = cs.expansion_id
              JOIN public.asset_source s ON s.code = j.source
              CROSS JOIN LATERAL internal.compute_variant_residual_signature(
                  r.raw_data, e.game_id, s.id
              ) sig
             WHERE r.id = ANY(v_row_ids)
               AND j.status = 'STAGED'
               AND r.decision_status = 'PENDING'
               AND r.persistence_status = 'PENDING'
        ),
        classified AS (
            SELECT t.id,
                   t.job_id,
                   t.printing_profile_id,
                   vm.variant_type_id,
                   CASE
                     WHEN t.printing_state NOT IN ('RESOLVED_NO_PRINTING', 'RESOLVED_WITH_PROFILE')
                          THEN 'C'
                     WHEN vm.variant_type_id IS NOT NULL
                          THEN 'A'
                     ELSE 'B'
                   END AS outcome
              FROM touched t
              LEFT JOIN public.card_variant_type_external_mapping vm
                ON vm.game_id = t.game_id
               AND vm.asset_source_id = t.asset_source_id
               AND vm.normalized_type = t.residual_type
               AND COALESCE(vm.normalized_foil, '')    = COALESCE(t.residual_foil, '')
               AND COALESCE(vm.normalized_subtype, '') = COALESCE(t.residual_subtype, '')
               AND COALESCE(vm.normalized_stamp, '{}'::TEXT[]) = COALESCE(t.residual_stamp, '{}'::TEXT[])
        ),
        -- ---------------------------------------------------------------
        -- CONTRATO NEW-ONLY (GATE-A-REV-03).
        --
        -- Não há lookup em public.card_variant aqui, e não pode haver.
        -- Um Printing Profile RECÉM-CRIADO não pode possuir card_variant
        -- preexistente referenciando seu UUID: esta mesma função cria o
        -- Perfil (PASSO 4), sela (PASSO 5), seleciona apenas linhas cujo
        -- roteamento resolve PARA ESSE Perfil (PASSO 6) e nunca cria
        -- card_variant. Nenhuma instrução externa se interpõe entre a
        -- criação e este backfill — estão na mesma chamada.
        --
        -- Portanto esta operação SEMPRE produz match_status = 'NEW' com
        -- matched_variant_id = NULL. O ramo MATCHED que existia aqui era
        -- inalcançável por contrato e foi removido: mantê-lo sugeriria uma
        -- cobertura de teste que nenhuma fixture segura consegue exercitar.
        --
        -- Se no futuro existir revalidação sobre um Profile JÁ EXISTENTE,
        -- MATCHED pertence ÀQUELA operação — que enxerga card_variant
        -- preexistentes — e não a esta.
        -- ---------------------------------------------------------------
        updated AS (
            UPDATE public.catalog_variant_import_row r
               SET normalized_data =
                       CASE c.outcome
                           WHEN 'A' THEN
                               jsonb_set(
                                   jsonb_set(r.normalized_data,
                                             '{variant_type_id}',
                                             to_jsonb(c.variant_type_id::TEXT), true),
                                   '{printing_profile_id}',
                                   CASE WHEN c.printing_profile_id IS NULL
                                        THEN 'null'::JSONB
                                        ELSE to_jsonb(c.printing_profile_id::TEXT) END,
                                   true)
                           WHEN 'B' THEN
                               jsonb_set(
                                   r.normalized_data - 'variant_type_id',
                                   '{printing_profile_id}',
                                   CASE WHEN c.printing_profile_id IS NULL
                                        THEN 'null'::JSONB
                                        ELSE to_jsonb(c.printing_profile_id::TEXT) END,
                                   true)
                           ELSE
                               (r.normalized_data - 'variant_type_id') - 'printing_profile_id'
                       END,
                   validation_status =
                       CASE c.outcome WHEN 'A' THEN 'VALID' ELSE 'NEEDS_REVIEW' END,
                   match_status        = 'NEW',
                   matched_variant_id  = NULL,
                   error_detail        = NULL
              FROM classified c
             WHERE r.id = c.id
            RETURNING r.id, r.job_id, c.outcome
        )
        SELECT
            (SELECT count(*) FROM touched),
            (SELECT count(*) FROM updated),
            (SELECT count(*) FROM updated WHERE outcome = 'A'),
            (SELECT count(*) FROM updated WHERE outcome IN ('B', 'C')),
            (SELECT count(DISTINCT job_id) FROM updated)
          INTO v_touched, v_reconciled, v_revalidated, v_pending, v_jobs;

        -- =================================================================
        -- GUARDS DE RECONCILIAÇÃO. Toda linha atingida precisa ter recebido
        -- estado terminal, e a soma dos desfechos precisa fechar o universo.
        -- Mesma disciplina da Query 2181.
        -- =================================================================
        IF v_reconciled IS DISTINCT FROM v_touched THEN
            RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_RECONCILIATION_GAP: % linha(s) atingidas, % reconciliadas. Alguma linha ficou sem estado terminal definido.',
                v_touched, v_reconciled;
        END IF;

        IF (v_revalidated + v_pending) IS DISTINCT FROM v_touched THEN
            RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_COUNTER_GAP: rows_revalidated (%) + rows_still_pending (%) <> universo atingido (%).',
                v_revalidated, v_pending, v_touched;
        END IF;

        -- =================================================================
        -- PASSO 9 — CONTADORES DOS JOBS AFETADOS.
        --
        -- Recalculados na MESMA transação, ao contrário de 2150 e 2181.
        -- Motivo empírico: a rodada PokéTour de 2026-09-13 deixou
        -- catalog_variant_import_job.valid_rows de BASE1 defasado (411 vs
        -- 412) até o confirm reconciliar. Precedente do lado de Cards:
        -- svc_apply_catalog_import_revalidation (2106) já recalcula.
        --
        -- SOMENTE total_rows e valid_rows. inserted/unchanged/failed e status
        -- pertencem a admin_confirm_catalog_variant_import e NÃO são tocados.
        -- =================================================================
        UPDATE public.catalog_variant_import_job j
           SET total_rows = (SELECT count(*) FROM public.catalog_variant_import_row r
                              WHERE r.job_id = j.id),
               valid_rows = (SELECT count(*) FROM public.catalog_variant_import_row r
                              WHERE r.job_id = j.id AND r.validation_status = 'VALID')
         WHERE j.id = ANY(v_job_ids);
    END IF;

    -- =====================================================================
    -- PASSO 10 — RESTAURAR O MODO DIFERIDO DO SELO.
    --
    -- SET CONSTRAINTS tem escopo de TRANSAÇÃO, não de função. Sem restaurar,
    -- uma transação externa que continuasse criando Perfis por outro caminho
    -- teria o selo disparando a cada INSERT.
    -- =====================================================================
    SET CONSTRAINTS public.trg_card_printing_profile_seal DEFERRED;

    -- =====================================================================
    -- PASSO 11 — AUDITORIA. Exatamente 1 evento por Perfil criado.
    -- Contrato ampliado pela Query 2188. actor_id = p_actor_id, o
    -- administrador autorizador — nunca uma identidade inferida.
    -- =====================================================================
    INSERT INTO public.catalog_admin_action_log
        (actor_id, action, entity_type, entity_id, metadata)
    VALUES (
        p_actor_id,
        'CARD_PRINTING_PROFILE_CREATED',
        'CARD_PRINTING_PROFILE',
        v_profile_id,
        jsonb_build_object(
            'game_id',            v_game_id,
            'code',               v_code,
            'name',               v_name,
            'display_order',      p_display_order,
            'trait_ids',          to_jsonb(v_expected),
            'traits_signature',   to_jsonb(v_sealed),
            'rows_touched',       v_touched,
            'rows_revalidated',   v_revalidated,
            'rows_still_pending', v_pending,
            'jobs_affected',      v_jobs
        )
    );

    RETURN QUERY
        SELECT v_profile_id, v_sealed, v_touched, v_revalidated, v_pending, v_jobs;
END;
$worker$;

-- -----------------------------------------------------------------------------
-- O worker é OWNER-ONLY. Nenhum papel externo executa. O único caminho de
-- aplicação é (a) a RPC pública abaixo, que é SECURITY DEFINER e portanto roda
-- como owner, ou (b) manutenção explícita pelo próprio owner.
-- Mesmo princípio de isolamento de internal.write_card() e
-- internal.persist_catalog_import_revalidation().
-- -----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION internal.create_card_printing_profile_with_backfill(UUID, TEXT, TEXT, TEXT, INTEGER, UUID[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION internal.create_card_printing_profile_with_backfill(UUID, TEXT, TEXT, TEXT, INTEGER, UUID[]) FROM anon;
REVOKE ALL ON FUNCTION internal.create_card_printing_profile_with_backfill(UUID, TEXT, TEXT, TEXT, INTEGER, UUID[]) FROM authenticated;
REVOKE ALL ON FUNCTION internal.create_card_printing_profile_with_backfill(UUID, TEXT, TEXT, TEXT, INTEGER, UUID[]) FROM service_role;

-- =============================================================================
-- FRONTEIRA PÚBLICA — public.admin_create_card_printing_profile_with_backfill()
--
-- FINA por decisão de desenho. Ela responde por UMA coisa: provar que quem
-- chamou é administrador e informar QUEM é. Toda a semântica está no worker.
-- Duplicar qualquer regra aqui criaria dois lugares para corrigir o mesmo bug.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.admin_create_card_printing_profile_with_backfill(
    p_code          TEXT,
    p_name          TEXT,
    p_description   TEXT,
    p_display_order INTEGER,
    p_trait_ids     UUID[]
)
RETURNS TABLE(
    profile_id         UUID,
    traits_signature   UUID[],
    rows_touched       INTEGER,
    rows_revalidated   INTEGER,
    rows_still_pending INTEGER,
    jobs_affected      INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $rpc$
DECLARE
    v_actor UUID;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_CREATE_CARD_PRINTING_PROFILE_FORBIDDEN: apenas administradores podem cadastrar um Perfil de Impressão.';
    END IF;

    -- Identidade da sessão real. NUNCA vem do corpo da chamada.
    v_actor := auth.uid();

    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'ADMIN_CREATE_CARD_PRINTING_PROFILE_NO_SESSION: is_admin() passou mas auth.uid() é NULL. Estado inconsistente — não há ator a registrar. STOP.';
    END IF;

    RETURN QUERY
        SELECT w.profile_id, w.traits_signature, w.rows_touched,
               w.rows_revalidated, w.rows_still_pending, w.jobs_affected
          FROM internal.create_card_printing_profile_with_backfill(
                   v_actor, p_code, p_name, p_description, p_display_order, p_trait_ids
               ) w;
END;
$rpc$;

REVOKE ALL ON FUNCTION public.admin_create_card_printing_profile_with_backfill(TEXT, TEXT, TEXT, INTEGER, UUID[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_create_card_printing_profile_with_backfill(TEXT, TEXT, TEXT, INTEGER, UUID[]) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_create_card_printing_profile_with_backfill(TEXT, TEXT, TEXT, INTEGER, UUID[]) TO authenticated;
-- service_role NÃO recebe grant: não há Edge Function no caminho desta operação.

COMMIT;

-- ============================================================================
-- Resultado esperado:
--   2 funções criadas (1 internal owner-only, 1 public admin-gated).
--
-- DOIS CAMINHOS OPERACIONAIS LEGÍTIMOS (nenhum depende de JWT fabricado):
--
--   A. SESSÃO ADMINISTRATIVA REAL DA APLICAÇÃO.
--
--      Uma sessão em que o usuário autenticou pelo GoTrue e o JWT dele chega
--      ao Postgres, de modo que auth.uid() devolve o id real e is_admin()
--      avalia esse id. Hoje isso significa a UI/servidor da aplicação.
--
--      O SQL Editor do painel Supabase NÃO é esse caminho. Ele executa com
--      papel administrativo do banco e SEM request.jwt.claims: auth.uid()
--      é NULL, is_admin() é FALSE e esta RPC recusa com _FORBIDDEN. Isso é o
--      comportamento correto, não um defeito — e é exatamente o que o caso A
--      da Query 2825 prova. Para operar pelo SQL Editor, use o caminho B.
--
--        SELECT * FROM public.admin_create_card_printing_profile_with_backfill(
--            'FIRST_EDITION',
--            '1ª Edição',
--            'Perfil de impressão com selo de 1ª Edição, sem outras marcas de tiragem.',
--            7,
--            ARRAY[(SELECT id FROM public.card_printing_trait
--                    WHERE code = 'FIRST_EDITION'
--                      AND game_id = (SELECT id FROM public.game WHERE code = 'POKEMON'))]
--        );
--
--   B. MANUTENÇÃO EXPLICITAMENTE AUTORIZADA, por owner/postgres, com o
--      administrador autorizador NOMEADO em p_actor_id.
--
--      É este o caminho do SQL Editor e de qualquer operação de manutenção.
--      Não há JWT envolvido: p_actor_id é parâmetro de auditoria, informado
--      por quem executa e validado contra public.admin_user. Registra-se no
--      action log o admin que autorizou, não o papel do banco.
--
--        SELECT * FROM internal.create_card_printing_profile_with_backfill(
--            '<uuid do admin que autorizou>',
--            'FIRST_EDITION',
--            '1ª Edição',
--            'Perfil de impressão com selo de 1ª Edição, sem outras marcas de tiragem.',
--            7,
--            ARRAY[(SELECT id FROM public.card_printing_trait
--                    WHERE code = 'FIRST_EDITION'
--                      AND game_id = (SELECT id FROM public.game WHERE code = 'POKEMON'))]
--        );
--
--   Retorno esperado em 2026-09-13, nos dois caminhos:
--     rows_touched = 62 | rows_revalidated = 16 | rows_still_pending = 46
--     jobs_affected = 1 (BASE3)
--
-- Como validar:
--   Query 2825 - Validate Card Printing Profile Creation Backfill.
-- ============================================================================
