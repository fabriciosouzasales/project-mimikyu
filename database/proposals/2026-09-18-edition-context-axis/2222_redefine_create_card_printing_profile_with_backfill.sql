-- ===========================================================================
-- Query 2222 — internal.create_card_printing_profile_with_backfill()
--              v4.0 — terceiro eixo (Contexto de Edição) no backfill
-- ===========================================================================
-- STATUS: PROPOSTA — NÃO EXECUTADA. Pacote EDITION-CONTEXT-AXIS.
-- Base canônica: database/schema/2189_create_admin_create_card_printing_profile_with_backfill_function.sql (v3.0)
--   · worker `internal.…` ............ linhas 63–447 (dollar-quote `worker`)
--   · PASSO 6 (candidatas) ........... linhas 252–266  ← call site 1 de 2176
--   · PASSO 8 (`touched`) ............ linhas 292–313  ← call site 2 de 2176
--   · `classified` ................... linhas 314–352
--   · `updated` ...................... linhas 353–385
--   · gates de reconciliação ......... linhas 394–408
--   · RPC pública `public.…` ......... linhas 468–508
--
-- Este é o ÚLTIMO dos 5 callers de compute_variant_residual_signature
-- inventariados em IMPACTED-CONTRACTS.md (7 call sites; 2 deles aqui).
--
-- ---------------------------------------------------------------------------
-- O QUE MUDA
-- ---------------------------------------------------------------------------
--   (a) Os DOIS call sites passam a chamar internal.resolve_variant_row_axes(),
--       com o ESCOPO CANÔNICO como p_external_set_id — o identificador EXTERNO
--       do Card Set na Fonte, devolvido por
--       internal.resolve_variant_mapping_scope(card_set_id, asset_source_id).
--       NÃO é `card_set.code`: o código interno é maiúsculo ('BASE2') e o
--       identificador da Fonte é minúsculo ('base2'), de modo que passar
--       `cs.code` tornaria todo mapping SCOPED inalcançável. Mesma convenção
--       fixada em 2219 e 2221 (SOURCE-SCOPE-CORRECTION-01).
--   (b) `classified` exige os DOIS eixos terminalmente resolvidos.
--   (c) `updated` grava a terceira chave em A e B e a remove em C.
--   (d) metadata do action log ganha `rows_blocked_edition_context` e
--       `axes_contract`.
--
-- ---------------------------------------------------------------------------
-- O QUE NÃO MUDA — e por quê
-- ---------------------------------------------------------------------------
--   · A assinatura e o RETURNS TABLE do worker, BYTE A BYTE. É condição para
--     que a RPC pública (`public.admin_create_card_printing_profile_with_backfill`)
--     continue válida sem ser tocada — ver PROVA NEGATIVA no fim do arquivo.
--   · Os 5 GUARDs de entrada (ator, escalares, forma do array, existência/
--     atividade/Game único, unicidade de code/display_order/signature).
--   · PASSOS 1–5 (criar o Perfil, compor, forçar e PROVAR o selo). O selo é
--     pré-condição do backfill: sem `traits_signature` selada, a seleção de
--     candidatas do PASSO 6 seria vazia e silenciosa.
--   · PASSO 7 (ordem de lock JOB → ROW), PASSO 9 (recontagem dos jobs),
--     PASSO 10 (restaurar o selo DEFERRED), PASSO 11 (action log).
--   · O contrato NEW-ONLY do `updated` (`match_status='NEW'`,
--     `matched_variant_id=NULL`, `error_detail=NULL`), fixado em GATE-A-REV-03.
--   · Os dois códigos de erro de reconciliação
--     (`…_RECONCILIATION_GAP`, `…_COUNTER_GAP`).
--   · Os 4 REVOKE do worker (OWNER-ONLY: PUBLIC, anon, authenticated,
--     service_role).
--
-- ---------------------------------------------------------------------------
-- NOTA SEMÂNTICA — por que o eixo 3 é RECALCULADO e não "copiado"
-- ---------------------------------------------------------------------------
-- O mandato exige que o backfill PRESERVE `edition_context_profile_id`. A
-- leitura ingênua seria copiar o valor anterior da chave. Está errada, e a
-- razão é o encadeamento dos eixos em 2211:
--
--     raw_data → size-scope → Printing → RESÍDUO → Contexto de Edição
--
-- Criar um Perfil de Impressão muda o que a etapa de Printing CONSOME. Logo
-- muda o resíduo, e portanto pode mudar o que o eixo 3 enxerga. Copiar o valor
-- antigo afirmaria um resultado que a nova composição não apurou — exatamente
-- o defeito que a BACKFILL-SEMANTICS-CORRECTION-01 eliminou.
--
-- "Preservar" aqui significa: **nunca apagar a chave como efeito colateral de
-- uma operação de Impressão.** É isso que este artefato garante — em A e B a
-- chave é reescrita com o valor recalculado; em C ela é removida junto com as
-- outras duas, e a remoção é a afirmação correta ("esta passada não apurou").
-- O que NÃO pode acontecer, e não acontece, é a chave sumir enquanto as outras
-- duas permanecem — os três destinos são gravados na mesma expressão.
-- ===========================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- PRECONDIÇÃO 1 — contrato de três eixos (2211).
-- ---------------------------------------------------------------------------
DO $pre1$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'internal'
           AND p.proname = 'resolve_variant_row_axes'
    ) THEN
        RAISE EXCEPTION 'PRECONDITION_FAILED_2222_A: internal.resolve_variant_row_axes() nao existe. Executar a Query 2211 antes desta.';
    END IF;
END
$pre1$;

-- ---------------------------------------------------------------------------
-- PRECONDIÇÃO 2 — o worker precisa existir com ESTA assinatura, e a RPC
-- pública com a dela. CREATE OR REPLACE com assinatura divergente criaria
-- sobrecarga e deixaria dois caminhos de backfill vivos.
-- ---------------------------------------------------------------------------
DO $pre2$
BEGIN
    -- IDENTIFICACAO POR OID (FUNCTION-IDENTITY-GATE-CORRECTION-01).
    -- NAO comparar o TEXTO devolvido por pg_get_function_identity_arguments():
    -- essa funcao INCLUI os nomes dos parametros, de modo que literais como
    -- 'uuid, text, text, text, integer, uuid[]' nunca casam com funcoes de
    -- parametros nomeados — e ambos os alvos abaixo os tem. to_regprocedure()
    -- resolve schema + tipos e devolve NULL (sem excecao) quando o alvo nao
    -- existe, que e exatamente o teste desejado aqui.
    IF to_regprocedure('internal.create_card_printing_profile_with_backfill(uuid,text,text,text,integer,uuid[])') IS NULL THEN
        RAISE EXCEPTION 'PRECONDITION_FAILED_2222_B: internal.create_card_printing_profile_with_backfill(uuid, text, text, text, integer, uuid[]) nao encontrada com a assinatura esperada.';
    END IF;

    IF to_regprocedure('public.admin_create_card_printing_profile_with_backfill(text,text,text,integer,uuid[])') IS NULL THEN
        RAISE EXCEPTION 'PRECONDITION_FAILED_2222_C: public.admin_create_card_printing_profile_with_backfill(text, text, text, integer, uuid[]) nao encontrada. A prova negativa do wrapper depende dela.';
    END IF;
END
$pre2$;

-- ---------------------------------------------------------------------------
-- PRECONDIÇÃO 3 — o destino do terceiro eixo precisa existir.
-- ---------------------------------------------------------------------------
DO $pre3$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_schema = 'public'
           AND table_name   = 'card_variant'
           AND column_name  = 'edition_context_profile_id'
    ) THEN
        RAISE EXCEPTION 'PRECONDITION_FAILED_2222_D: public.card_variant.edition_context_profile_id nao existe. Executar a Query 2208 antes desta.';
    END IF;
END
$pre3$;


-- =============================================================================
-- WORKER — internal.create_card_printing_profile_with_backfill() v4.0
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
    -- v4.0: desdobramento auditável de rows_still_pending por causa.
    v_blocked_ec  INTEGER := 0;
BEGIN
    -- GUARD 1 — ATOR. Primeira instrução.
    IF p_actor_id IS NULL THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_MISSING_ACTOR: p_actor_id é obrigatório. Toda criação de Perfil precisa de um administrador autorizador nomeado.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.admin_user a WHERE a.id = p_actor_id) THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_ACTOR_NOT_ADMIN: p_actor_id (%) não corresponde a um administrador cadastrado em public.admin_user.', p_actor_id;
    END IF;

    -- GUARD 2 — ESCALARES.
    v_code        := upper(btrim(coalesce(p_code, '')));
    v_name        := btrim(coalesce(p_name, ''));
    v_description := btrim(coalesce(p_description, ''));
    IF v_description = '' THEN v_description := NULL; END IF;

    IF v_code = '' OR v_code !~ '^[A-Z][A-Z0-9_]*$' THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_INVALID_CODE: código inválido (%). Esperado ^[A-Z][A-Z0-9_]*$.', p_code;
    END IF;

    IF v_name = '' THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_INVALID_NAME: o nome não pode ser vazio.';
    END IF;

    IF p_display_order IS NULL OR p_display_order <= 0 THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_INVALID_DISPLAY_ORDER: ordem inválida (%). Precisa ser inteiro positivo.', p_display_order;
    END IF;

    -- GUARD 3 — FORMA DO ARRAY DE TRAITS.
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

    -- GUARD 4 — EXISTÊNCIA, ATIVIDADE E GAME ÚNICO.
    -- array_agg(DISTINCT ... ORDER BY ...)[1] preservado da Query
    -- 2190: PostgreSQL não tem min(uuid).
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

    SELECT count(DISTINCT ct.game_id),
           (array_agg(DISTINCT ct.game_id ORDER BY ct.game_id))[1]
      INTO v_game_count, v_game_id
      FROM public.card_printing_trait ct
     WHERE ct.id = ANY(p_trait_ids);

    IF v_game_count <> 1 THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_MIXED_GAME: os traits informados pertencem a % Games distintos. Um Perfil pertence a exatamente um Game.', v_game_count;
    END IF;

    -- GUARD 5 — UNICIDADE.
    IF EXISTS (SELECT 1 FROM public.card_printing_profile p
                WHERE p.game_id = v_game_id AND p.code = v_code) THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_DUPLICATE_CODE: já existe um Perfil de Impressão com o código % para este Game.', v_code;
    END IF;

    IF EXISTS (SELECT 1 FROM public.card_printing_profile p
                WHERE p.game_id = v_game_id AND p.display_order = p_display_order) THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_DUPLICATE_DISPLAY_ORDER: já existe um Perfil de Impressão com a ordem % para este Game.', p_display_order;
    END IF;

    v_expected := ARRAY(SELECT DISTINCT t FROM unnest(p_trait_ids) AS t ORDER BY t);

    IF EXISTS (SELECT 1 FROM public.card_printing_profile p
                WHERE p.game_id = v_game_id AND p.traits_signature = v_expected) THEN
        RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_DUPLICATE_SIGNATURE: já existe um Perfil de Impressão com exatamente esta composição neste Game. Composição é identidade — reutilize o Perfil existente.';
    END IF;

    -- PASSO 1 — CRIAR O PERFIL "EM MONTAGEM".
    INSERT INTO public.card_printing_profile
        (game_id, code, name, description, display_order)
    VALUES
        (v_game_id, v_code, v_name, v_description, p_display_order)
    RETURNING id INTO v_profile_id;

    -- PASSO 2 — COMPOSIÇÃO.
    INSERT INTO public.card_printing_profile_trait (profile_id, trait_id, game_id)
    SELECT v_profile_id, t, v_game_id FROM unnest(v_expected) AS t;

    -- PASSO 3 — FORÇAR O SELO.
    SET CONSTRAINTS public.trg_card_printing_profile_seal IMMEDIATE;

    -- PASSOS 4 e 5 — RELER E PROVAR O SELO.
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

    -- =======================================================================
    -- PASSO 6 — SELEÇÃO DAS CANDIDATAS.  >>> CALL SITE 1 de 2, v4.0 <<<
    --
    -- O contrato de DOIS eixos (2176) foi substituído pelo de TRÊS (2211),
    -- com o escopo EXTERNO canônico (SOURCE-SCOPE-CORRECTION-01) — nunca
    -- `card_set.code`. Os nomes das funções NÃO são citados
    -- neste comentário de propósito: o POSTCHECK 1 varre `prosrc`, que inclui
    -- comentários, e conta as chamadas — citações produziriam falso-positivo.
    --
    -- O predicado de seleção NÃO muda: continua `ax.printing_profile_id =
    -- v_profile_id`, isto é, "linhas que o Perfil recém-criado passa a
    -- resolver". O eixo 3 não participa da SELEÇÃO — participa da
    -- CLASSIFICAÇÃO, no PASSO 8. Misturar os dois aqui excluiria do backfill
    -- justamente as linhas que o novo Perfil destravou mas cujo Contexto de
    -- Edição segue indeterminado — e elas PRECISAM ser reescritas, para que a
    -- chave de Impressão recém-resolvida seja gravada.
    -- =======================================================================
    SELECT ARRAY(
        SELECT r.id
          FROM public.catalog_variant_import_row r
          JOIN public.catalog_variant_import_job j ON j.id = r.job_id
          JOIN public.card_set cs    ON cs.id = j.card_set_id
          JOIN public.expansion e    ON e.id  = cs.expansion_id
          JOIN public.asset_source s ON s.code = j.source
          -- ESCOPO CANONICO (SOURCE-SCOPE-CORRECTION-01): identificador EXTERNO
          -- do Card Set na Fonte, nunca card_set.code.
          LEFT JOIN LATERAL internal.resolve_variant_mapping_scope(cs.id, s.id) sc ON TRUE
          CROSS JOIN LATERAL internal.resolve_variant_row_axes(
              r.raw_data, e.game_id, s.id, sc.external_set_id
          ) ax
         WHERE j.status = 'STAGED'
           AND r.decision_status = 'PENDING'
           AND r.persistence_status = 'PENDING'
           AND e.game_id = v_game_id
           AND ax.printing_profile_id = v_profile_id
         ORDER BY r.id
    ) INTO v_row_ids;

    IF v_row_ids IS NULL OR cardinality(v_row_ids) = 0 THEN
        v_row_ids := ARRAY[]::UUID[];
        v_job_ids := ARRAY[]::UUID[];
    ELSE
        SELECT ARRAY(
            SELECT DISTINCT r.job_id
              FROM public.catalog_variant_import_row r
             WHERE r.id = ANY(v_row_ids)
             ORDER BY 1
        ) INTO v_job_ids;

        -- PASSO 7 — LOCKS. Ordem JOB -> ROW.
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

        -- ===================================================================
        -- PASSO 8 — RECONCILIAÇÃO.  >>> CALL SITE 2 de 2, v4.0 <<<
        -- ===================================================================
        WITH touched AS (
            SELECT r.id,
                   r.job_id,
                   ax.printing_state,
                   ax.printing_profile_id,
                   ax.edition_context_state,          -- >>> NOVO v4.0 <<<
                   ax.edition_context_profile_id,     -- >>> NOVO v4.0 <<<
                   ax.residual_type,
                   ax.residual_foil,
                   ax.residual_subtype,
                   ax.residual_stamp,
                   e.game_id AS game_id,
                   s.id      AS asset_source_id,
                   cs.id     AS card_set_id      -- >>> DIFF 2196 <<<
              FROM public.catalog_variant_import_row r
              JOIN public.catalog_variant_import_job j ON j.id = r.job_id
              JOIN public.card_set cs    ON cs.id = j.card_set_id
              JOIN public.expansion e    ON e.id  = cs.expansion_id
              JOIN public.asset_source s ON s.code = j.source
              -- ESCOPO CANONICO (SOURCE-SCOPE-CORRECTION-01): identificador
              -- EXTERNO do Card Set na Fonte, nunca card_set.code.
              LEFT JOIN LATERAL internal.resolve_variant_mapping_scope(cs.id, s.id) sc ON TRUE
              CROSS JOIN LATERAL internal.resolve_variant_row_axes(
                  r.raw_data, e.game_id, s.id, sc.external_set_id
              ) ax
             WHERE r.id = ANY(v_row_ids)
               AND j.status = 'STAGED'
               AND r.decision_status = 'PENDING'
               AND r.persistence_status = 'PENDING'
        ),
        classified AS (
            -- >>> DIFF 2196: lookup com precedência scoped > global.
            -- Substitui o LEFT JOIN direto contra
            -- card_variant_type_external_mapping.
            --
            -- >>> CORRIGIDO EM GATE-A-REV-01 <<<
            -- A v1.0 chamava o helper DUAS vezes por row (uma para
            -- a coluna, outra dentro do CASE). O helper resolve o
            -- escopo e varre o mapping — duplicar a chamada dobra o
            -- trabalho por linha sem nenhum ganho, e o planner não
            -- tem como deduplicar com segurança uma função STABLE
            -- em contextos distintos da mesma projeção.
            --
            -- LEFT JOIN LATERAL resolve UMA vez por row e o valor é
            -- reutilizado nos dois pontos. Semântica idêntica:
            -- LATERAL sobre função escalar produz exatamente uma
            -- linha (NULL inclusive), então nenhuma row de `touched`
            -- é perdida nem duplicada.
            --
            -- >>> v4.0: o outcome passa a depender dos DOIS eixos. O teste do
            -- eixo 3 é simétrico ao do eixo 1 — ver justificativa idêntica em
            -- 2219 e 2221. O residual passado a lookup_variant_type_for_row já
            -- é o residual PÓS-DOIS-EIXOS, porque vem do contrato de 2211.
            SELECT t.id,
                   t.job_id,
                   t.printing_profile_id,
                   t.edition_context_profile_id,
                   lk.variant_type_id,
                   CASE
                     WHEN t.printing_state NOT IN ('RESOLVED_NO_PRINTING', 'RESOLVED_WITH_PROFILE')
                          THEN 'C'
                     WHEN t.edition_context_state NOT IN ('RESOLVED_NO_EDITION_CONTEXT', 'RESOLVED_WITH_EC_PROFILE')
                          THEN 'C'
                     WHEN lk.variant_type_id IS NOT NULL
                          THEN 'A'
                     ELSE 'B'
                   END AS outcome,
                   -- Precedência: Impressão primeiro. Uma linha com os dois
                   -- eixos indeterminados conta como bloqueio de Impressão.
                   -- Contar nos dois inflaria o total e quebraria o gate.
                   (t.printing_state IN ('RESOLVED_NO_PRINTING', 'RESOLVED_WITH_PROFILE')
                    AND t.edition_context_state NOT IN ('RESOLVED_NO_EDITION_CONTEXT', 'RESOLVED_WITH_EC_PROFILE'))
                       AS blocked_by_edition_context
              FROM touched t
              LEFT JOIN LATERAL (
                  SELECT internal.lookup_variant_type_for_row(
                             t.game_id, t.asset_source_id, t.card_set_id,
                             t.residual_type, t.residual_foil,
                             t.residual_subtype, t.residual_stamp
                         ) AS variant_type_id
              ) lk ON TRUE
        ),
        -- CONTRATO NEW-ONLY (GATE-A-REV-03): sem lookup em public.card_variant.
        updated AS (
            UPDATE public.catalog_variant_import_row r
               SET normalized_data =
                       CASE c.outcome
                           -- A — identidade completa, TRÊS chaves numa única
                           -- expressão. Não existe estado intermediário.
                           WHEN 'A' THEN
                               jsonb_set(
                                   jsonb_set(
                                       jsonb_set(r.normalized_data,
                                                 '{variant_type_id}',
                                                 to_jsonb(c.variant_type_id::TEXT), true),
                                       '{printing_profile_id}',
                                       CASE WHEN c.printing_profile_id IS NULL
                                            THEN 'null'::JSONB
                                            ELSE to_jsonb(c.printing_profile_id::TEXT) END,
                                       true),
                                   '{edition_context_profile_id}',
                                   CASE WHEN c.edition_context_profile_id IS NULL
                                        THEN 'null'::JSONB
                                        ELSE to_jsonb(c.edition_context_profile_id::TEXT) END,
                                   true)
                           -- B — eixos resolvidos, Variant Type não mapeado.
                           -- As duas chaves de eixo são gravadas: o trabalho
                           -- feito é preservado e fica visível ao revisor.
                           WHEN 'B' THEN
                               jsonb_set(
                                   jsonb_set(
                                       r.normalized_data - 'variant_type_id',
                                       '{printing_profile_id}',
                                       CASE WHEN c.printing_profile_id IS NULL
                                            THEN 'null'::JSONB
                                            ELSE to_jsonb(c.printing_profile_id::TEXT) END,
                                       true),
                                   '{edition_context_profile_id}',
                                   CASE WHEN c.edition_context_profile_id IS NULL
                                        THEN 'null'::JSONB
                                        ELSE to_jsonb(c.edition_context_profile_id::TEXT) END,
                                   true)
                           -- C — algum eixo indeterminado. TODAS as chaves
                           -- saem. Ver NOTA SEMÂNTICA no cabeçalho: a remoção
                           -- é a afirmação correta, não perda de dado.
                           ELSE
                               ((r.normalized_data - 'variant_type_id')
                                                   - 'printing_profile_id')
                                                   - 'edition_context_profile_id'
                       END,
                   validation_status =
                       CASE c.outcome WHEN 'A' THEN 'VALID' ELSE 'NEEDS_REVIEW' END,
                   match_status        = 'NEW',
                   matched_variant_id  = NULL,
                   error_detail        = NULL
              FROM classified c
             WHERE r.id = c.id
            RETURNING r.id, r.job_id, c.outcome, c.blocked_by_edition_context
        )
        SELECT
            (SELECT count(*) FROM touched),
            (SELECT count(*) FROM updated),
            (SELECT count(*) FROM updated WHERE outcome = 'A'),
            (SELECT count(*) FROM updated WHERE outcome IN ('B', 'C')),
            (SELECT count(DISTINCT job_id) FROM updated),
            (SELECT count(*) FROM updated WHERE blocked_by_edition_context)
          INTO v_touched, v_reconciled, v_revalidated, v_pending, v_jobs, v_blocked_ec;

        IF v_reconciled IS DISTINCT FROM v_touched THEN
            RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_RECONCILIATION_GAP: % linha(s) atingidas, % reconciliadas. Alguma linha ficou sem estado terminal definido.',
                v_touched, v_reconciled;
        END IF;

        IF (v_revalidated + v_pending) IS DISTINCT FROM v_touched THEN
            RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_COUNTER_GAP: rows_revalidated (%) + rows_still_pending (%) <> universo atingido (%).',
                v_revalidated, v_pending, v_touched;
        END IF;

        -- Gate NOVO em v4.0 — o desdobramento por causa não pode exceder o
        -- total pendente. Se exceder, o CASE de causa divergiu do CASE de
        -- outcome: defeito de código, não de dado.
        IF v_blocked_ec > v_pending THEN
            RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_CAUSE_GAP: rows_blocked_edition_context (%) > rows_still_pending (%). A classificacao por causa divergiu da classificacao por outcome.',
                v_blocked_ec, v_pending;
        END IF;

        -- PASSO 9 — CONTADORES DOS JOBS AFETADOS.
        UPDATE public.catalog_variant_import_job j
           SET total_rows = (SELECT count(*) FROM public.catalog_variant_import_row r
                              WHERE r.job_id = j.id),
               valid_rows = (SELECT count(*) FROM public.catalog_variant_import_row r
                              WHERE r.job_id = j.id AND r.validation_status = 'VALID')
         WHERE j.id = ANY(v_job_ids);
    END IF;

    -- PASSO 10 — RESTAURAR O MODO DIFERIDO DO SELO.
    SET CONSTRAINTS public.trg_card_printing_profile_seal DEFERRED;

    -- PASSO 11 — AUDITORIA.
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
            'rows_blocked_edition_context', v_blocked_ec,
            'axes_contract',      'resolve_variant_row_axes/v1',
            'jobs_affected',      v_jobs
        )
    );

    RETURN QUERY
        SELECT v_profile_id, v_sealed, v_touched, v_revalidated, v_pending, v_jobs;
END;
$worker$;


COMMENT ON FUNCTION internal.create_card_printing_profile_with_backfill(UUID, TEXT, TEXT, TEXT, INTEGER, UUID[]) IS
'v4.1 (EDITION-CONTEXT-AXIS + SOURCE-SCOPE-CORRECTION-01). Cria um Perfil de Impressao com sua composicao selada e reconcilia, na mesma transacao, as linhas STAGED que o novo Perfil passa a resolver.
Os DOIS call sites de resolucao usam internal.resolve_variant_row_axes() — TRES eixos, com o escopo canonico devolvido por internal.resolve_variant_mapping_scope(card_set_id, asset_source_id): o identificador EXTERNO do Card Set na Fonte, nunca card_set.code.
SELECAO (PASSO 6) por Impressao apenas; CLASSIFICACAO (PASSO 8) exige os dois eixos terminalmente resolvidos.
O eixo de Contexto de Edicao e RECALCULADO, nao copiado: criar um Perfil de Impressao muda o residual que o eixo 3 consome. A chave nunca desaparece isoladamente — os tres destinos sao gravados na mesma expressao.
Assinatura e RETURNS TABLE identicos a v3.0, para que a RPC publica permaneca valida sem alteracao.';


-- -----------------------------------------------------------------------------
-- O worker é OWNER-ONLY. Nenhum papel externo executa. O único caminho de
-- aplicação é (a) a RPC pública, que é SECURITY DEFINER e portanto roda
-- como owner, ou (b) manutenção explícita pelo próprio owner.
-- Mesmo princípio de isolamento de internal.write_card() e
-- internal.persist_catalog_import_revalidation().
-- -----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION internal.create_card_printing_profile_with_backfill(UUID, TEXT, TEXT, TEXT, INTEGER, UUID[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION internal.create_card_printing_profile_with_backfill(UUID, TEXT, TEXT, TEXT, INTEGER, UUID[]) FROM anon;
REVOKE ALL ON FUNCTION internal.create_card_printing_profile_with_backfill(UUID, TEXT, TEXT, TEXT, INTEGER, UUID[]) FROM authenticated;
REVOKE ALL ON FUNCTION internal.create_card_printing_profile_with_backfill(UUID, TEXT, TEXT, TEXT, INTEGER, UUID[]) FROM service_role;


-- ===========================================================================
-- PROVA NEGATIVA — public.admin_create_card_printing_profile_with_backfill()
-- NÃO É ALTERADA, e isso é uma decisão, não um esquecimento.
-- ===========================================================================
-- A RPC pública (2189, linhas 468–508) é fina por desenho. O corpo dela faz
-- exatamente três coisas:
--
--   1. `IF NOT public.is_admin() THEN RAISE … _FORBIDDEN`
--   2. `v_actor := auth.uid()` + guard `_NO_SESSION`
--   3. `RETURN QUERY SELECT w.profile_id, w.traits_signature, w.rows_touched,
--       w.rows_revalidated, w.rows_still_pending, w.jobs_affected
--       FROM internal.create_card_printing_profile_with_backfill(…) w;`
--
-- Nenhuma delas toca eixo, residual ou normalized_data. O ponto 3 projeta as
-- SEIS colunas do RETURNS TABLE do worker — e o RETURNS TABLE foi preservado
-- byte a byte acima, justamente para que essa projeção continue válida.
--
-- Alterar a RPC seria pior que inútil: duplicaria em dois lugares uma regra
-- que existe em um só — o antipadrão que o cabeçalho da 2189 nomeia
-- explicitamente ("Duplicar qualquer regra aqui criaria dois lugares para
-- corrigir o mesmo bug").
--
-- A prova é mecanizada no POSTCHECK 3: se a RPC algum dia passar a mencionar
-- residual, eixo ou normalized_data, ela deixou de ser fina e esta decisão
-- precisa ser reaberta.
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- POSTCHECK 1 — o worker NÃO pode mais chamar 2176 diretamente.
-- ---------------------------------------------------------------------------
DO $post1$
DECLARE
    v_oid REGPROCEDURE;
    v_src TEXT;
    v_hits INTEGER;
BEGIN
    -- IDENTIFICACAO POR OID (FUNCTION-IDENTITY-GATE-CORRECTION-01). O alvo e
    -- resolvido ANTES da leitura e a ausencia FALHA EXPLICITAMENTE. Com o
    -- predicado textual anterior o SELECT nao encontrava linha, v_src ficava
    -- NULL, `NULL LIKE '%...%'` devolvia NULL e a contagem de call sites era
    -- feita sobre NULL — de modo que TODO este postcheck passava sem verificar
    -- coisa alguma. PASS vacuoso e proibido.
    v_oid := to_regprocedure('internal.create_card_printing_profile_with_backfill(uuid,text,text,text,integer,uuid[])');

    IF v_oid IS NULL THEN
        RAISE EXCEPTION 'POSTCHECK_FAILED_2222_A0: alvo internal.create_card_printing_profile_with_backfill(uuid, text, text, text, integer, uuid[]) nao resolvido apos o CREATE OR REPLACE. Nenhuma prova de routing pode ser considerada satisfeita.';
    END IF;

    SELECT p.prosrc INTO v_src FROM pg_proc p WHERE p.oid = v_oid;

    IF NOT FOUND OR v_src IS NULL THEN
        RAISE EXCEPTION 'POSTCHECK_FAILED_2222_A1: prosrc do worker nao pode ser lido (oid: %). Postcheck de routing NAO satisfeito.', v_oid;
    END IF;

    IF v_src LIKE '%compute_variant_residual_signature%' THEN
        RAISE EXCEPTION 'POSTCHECK_FAILED_2222_A: o corpo ainda chama compute_variant_residual_signature diretamente.';
    END IF;

    -- Os DOIS call sites têm de ter migrado. Um só significaria seleção e
    -- classificação divergindo de contrato — o pior defeito possível aqui.
    --
    -- O token contado é `internal.resolve_variant_row_axes(` — com prefixo de
    -- schema e parêntese — e não o nome nu. `prosrc` contém também a string
    -- literal 'resolve_variant_row_axes/v1' gravada no metadata do action log;
    -- contar o nome nu devolveria 3 e falharia sem defeito nenhum.
    v_hits := (length(v_src) - length(replace(v_src, 'internal.resolve_variant_row_axes(', '')))
              / length('internal.resolve_variant_row_axes(');

    IF v_hits <> 2 THEN
        RAISE EXCEPTION 'POSTCHECK_FAILED_2222_B: esperadas 2 chamadas a resolve_variant_row_axes (PASSO 6 e PASSO 8); encontradas %.', v_hits;
    END IF;

    IF v_src NOT LIKE '%edition_context_profile_id%' THEN
        RAISE EXCEPTION 'POSTCHECK_FAILED_2222_C: o corpo nao grava a chave edition_context_profile_id.';
    END IF;
END
$post1$;

-- ---------------------------------------------------------------------------
-- POSTCHECK 2 — o worker continua OWNER-ONLY.
-- ---------------------------------------------------------------------------
DO $post2$
DECLARE
    v_oid REGPROCEDURE;
    v_acl TEXT;
BEGIN
    -- IDENTIFICACAO POR OID (FUNCTION-IDENTITY-GATE-CORRECTION-01). Mesma
    -- classe de defeito do POSTCHECK 1: alvo nao encontrado deixava v_acl
    -- NULL e as tres comparacoes LIKE devolviam NULL, aprovando o contrato
    -- OWNER-ONLY sem jamais te-lo lido. Aqui a ausencia FALHA.
    v_oid := to_regprocedure('internal.create_card_printing_profile_with_backfill(uuid,text,text,text,integer,uuid[])');

    IF v_oid IS NULL THEN
        RAISE EXCEPTION 'POSTCHECK_FAILED_2222_D0: alvo internal.create_card_printing_profile_with_backfill(uuid, text, text, text, integer, uuid[]) nao resolvido. A ACL OWNER-ONLY NAO foi verificada.';
    END IF;

    SELECT COALESCE(array_to_string(p.proacl, ','), '<null>') INTO v_acl
      FROM pg_proc p WHERE p.oid = v_oid;

    IF NOT FOUND OR v_acl IS NULL THEN
        RAISE EXCEPTION 'POSTCHECK_FAILED_2222_D1: proacl do worker nao pode ser lida (oid: %). Postcheck de ACL NAO satisfeito.', v_oid;
    END IF;

    IF v_acl LIKE '%anon=%'
       OR v_acl LIKE '%authenticated=%'
       OR v_acl LIKE '%service_role=%' THEN
        RAISE EXCEPTION 'POSTCHECK_FAILED_2222_D: o worker OWNER-ONLY tem EXECUTE para alguma role externa (acl: %).', v_acl;
    END IF;
END
$post2$;

-- ---------------------------------------------------------------------------
-- POSTCHECK 3 — a RPC pública continua FINA (prova negativa mecanizada).
-- ---------------------------------------------------------------------------
DO $post3$
DECLARE
    v_oid REGPROCEDURE;
    v_src TEXT;
BEGIN
    -- IDENTIFICACAO POR OID (FUNCTION-IDENTITY-GATE-CORRECTION-01). Este
    -- postcheck ja falhava em v_src IS NULL, mas com o predicado textual
    -- anterior ele falharia SEMPRE — e com diagnostico enganoso ("a RPC
    -- publica desapareceu") quando a RPC esta intacta e o defeito e do
    -- proprio gate. Resolver por OID separa as duas causas.
    v_oid := to_regprocedure('public.admin_create_card_printing_profile_with_backfill(text,text,text,integer,uuid[])');

    IF v_oid IS NULL THEN
        RAISE EXCEPTION 'POSTCHECK_FAILED_2222_E: a RPC publica desapareceu.';
    END IF;

    SELECT p.prosrc INTO v_src FROM pg_proc p WHERE p.oid = v_oid;

    IF NOT FOUND OR v_src IS NULL THEN
        RAISE EXCEPTION 'POSTCHECK_FAILED_2222_E1: prosrc da RPC publica nao pode ser lido (oid: %). A prova de que ela continua FINA NAO foi feita.', v_oid;
    END IF;

    IF v_src LIKE '%normalized_data%'
       OR v_src LIKE '%residual%'
       OR v_src LIKE '%printing_profile_id%'
       OR v_src LIKE '%edition_context%' THEN
        RAISE EXCEPTION 'POSTCHECK_FAILED_2222_F: a RPC publica deixou de ser fina — passou a mencionar eixo/residual/normalized_data. A decisao de nao altera-la precisa ser reaberta.';
    END IF;

    IF v_src NOT LIKE '%create_card_printing_profile_with_backfill%' THEN
        RAISE EXCEPTION 'POSTCHECK_FAILED_2222_G: a RPC publica nao delega mais ao worker.';
    END IF;
END
$post3$;

-- ---------------------------------------------------------------------------
-- POSTCHECK 4 — nenhuma sobrecarga, nem do worker nem da RPC.
-- ---------------------------------------------------------------------------
DO $post4$
DECLARE
    v_w INTEGER;
    v_p INTEGER;
BEGIN
    SELECT count(*) INTO v_w FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'internal' AND p.proname = 'create_card_printing_profile_with_backfill';

    SELECT count(*) INTO v_p FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'   AND p.proname = 'admin_create_card_printing_profile_with_backfill';

    IF v_w <> 1 OR v_p <> 1 THEN
        RAISE EXCEPTION 'POSTCHECK_FAILED_2222_H: sobrecargas encontradas (worker: %, rpc: %); esperado 1 e 1.', v_w, v_p;
    END IF;
END
$post4$;

COMMIT;
-- ARMADO PARA ROLLOUT (ROLLOUT-EXECUTION-READINESS-01). Terminador COMMIT.
-- Corpo auditado PRESERVADO byte a byte; a unica alteracao de armamento foi
-- ROLLBACK; -> COMMIT;. A protecao contra execucao prematura e GOVERNANCA
-- (autorizacao de Fabricio + ordem de batches), nao o terminador — mesma
-- decisao ja aceita em R1 para 2203-2211.
