/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2196 - Reconcile Variant Type Mapping LOOKUPS
              for Source-Set Scope (precedência determinística)
Versão......: 1.0
Status......: MIGRATION / CONFIRMADO EXECUTADO / LIVE
              Precheck de rebase PASSOU: md5(prosrc) do consumidor 1 era
              4ce5cc4ca573955c744ffe376eb03ca4 antes da aplicacao.
              Pos-aplicacao: ea56488f9805858ab2b1839de2a85515 (16.211 chars,
              366 linhas) — hash conferido pelo caso AE do harness 2826.
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-14
Executado...: 2026-09-14, via apply_migration (MCP Supabase), projeto
              qjfutqujxrbzgrtkpgkg. Ledger: 20260914025208 /
              2196_reconcile_variant_type_mapping_lookups_for_scope
Reclassif..: 2026-09-18, BULK-STP-01-CANONICAL-RECONCILIATION-IMPLEMENTATION-01
Canônica....: internal.lookup_variant_type_for_row() vive em
              database/schema/2192_..._scope_read_contract.sql v2.0; a parte
              alteradora do worker de Perfil de Impressão vive em
              database/schema/2189_..._with_backfill_function.sql v3.0
Mandato.....: CARD-VARIANTS — EDITORIAL-CONVERGENCE-16 /
              SOURCE-SET-SCOPED-FOUNDATION / GATE-A-STAGING-01

Descrição...:
Faz os consumidores SQL do mapping enxergarem o escopo, com
precedência determinística de UM nível.

--------------------------------------------------------------
DESENHO: UM HELPER, NÃO TRÊS CÓPIAS
--------------------------------------------------------------
A auditoria (EDITORIAL-CONVERGENCE-14) mapeou EXATAMENTE dois
consumidores SQL do mapping em caminho de lookup:

  1. internal.create_card_printing_profile_with_backfill()
     (Queries 2189 v2.1 -> 2190, linhas 258-264: LEFT JOIN vm)
  2. public.admin_resolve_catalog_variant_import_printing_mapping()
     (Query 2181, linhas 195-201: LEFT JOIN vm)

A tentação seria colar o novo LATERAL com precedência nos dois.
Isso criaria a TERCEIRA e a QUARTA cópia da mesma regra (a Edge
é a segunda) — exatamente a classe de divergência que esta frente
inteira existe para eliminar.

Em vez disso, esta Query cria UM helper —
`internal.lookup_variant_type_for_row()` — e os dois consumidores
passam a chamá-lo. A regra de precedência existe em UM lugar no
banco.

ESTE ARQUIVO CONTÉM o helper + o CONSUMIDOR 1.
O CONSUMIDOR 2 vive na Query 2197 (arquivo separado, gerado
mecanicamente a partir do prosrc LIVE).

>>> DIFF EXECUTÁVEL DO CONSUMIDOR 1, PARA REVISÃO BARATA <<<

  create_card_printing_profile_with_backfill (base: Query 2190):
     - `touched` passa a expor cs.id AS card_set_id;
     - o LEFT JOIN de 6 linhas contra o mapping some;
     - `classified` ganha LEFT JOIN LATERAL que resolve o helper
       UMA vez por row.
     Nada mais muda: guards, selo, locks, contadores, action log,
     contrato NEW-only e o array_agg da Query 2190 permanecem
     byte-idênticos.

--------------------------------------------------------------
PRECEDÊNCIA — PROVA DE DETERMINISMO
--------------------------------------------------------------
    ORDER BY (external_set_id IS NULL) ASC
    LIMIT 1

- o conjunto candidato tem NO MÁXIMO 2 elementos: um scoped e um
  global. Garantido pelos DOIS índices parciais únicos da Query
  2191, não por convenção;
- a expressão de ordenação é booleana e TOTAL sobre esse conjunto:
  FALSE (scoped) vem antes de TRUE (global);
- portanto não há empate possível, e o LIMIT 1 é determinístico.

NUNCA se usa timestamp, display_order ou is_active como critério
de desempate. Não há cascata: um nível só.

>>> FONTE CANÔNICA DO ESCOPO <<<
O helper resolve o source-set por `internal.resolve_variant_mapping_scope`
(Query 2192), que lê `card_set_external_reference` ATIVA — NUNCA
`catalog_variant_import_job.external_set_id`. Se o Card Set não
tiver referência ativa, `v_scope` é NULL e o lookup considera
somente mappings GLOBAIS. Nunca se inventa escopo.

Pré-requisitos:
- Query 2191 - coluna/índices de escopo.
- Query 2192 - internal.resolve_variant_mapping_scope().
- Query 2190 - versão vigente do worker de Printing Profile.
- Query 2181 - versão vigente do resolvedor de Printing Mapping.

>>> AVISO DE ORDEM DE APLICAÇÃO <<<
Esta Query faz CREATE OR REPLACE de duas funções LIVE. Os corpos
abaixo partem das versões vigentes em 2026-09-14 (2190 e 2181).
Se qualquer uma delas for alterada entre o staging e a aplicação,
este arquivo precisa ser rebaseado — o harness 2826 (caso Y) e o
GATE-B precheck confrontam o corpo LIVE antes de aplicar.
================================================================
*/

BEGIN;

-- =============================================================
-- 0. PRECHECK DE REBASE — ANTES DE QUALQUER ESCRITA
--
-- >>> ACRESCENTADO EM GATE-A-REV-03 §5 <<<
--
-- Havia uma inconsistência real: o harness 2826 exige a 2196 JÁ
-- aplicada (o caso AA confronta o md5 do consumidor 2), logo o
-- caso AE NÃO podia servir de precheck pré-2196 — ele só roda
-- depois. Chamar de "proteção pre-apply" algo que só executa
-- depois da aplicação é afirmar uma proteção que não existe.
--
-- O precheck passa a viver AQUI, no próprio artefato executável,
-- antes do primeiro CREATE OR REPLACE. Se o corpo LIVE do
-- consumidor 1 não for a baseline da qual este arquivo partiu, a
-- transação aborta e NADA é escrito — nem o helper novo.
--
-- Baseline medida no LIVE em 2026-09-14:
--   internal.create_card_printing_profile_with_backfill
--   md5(prosrc) = 4ce5cc4ca573955c744ffe376eb03ca4
--   15.868 caracteres, 356 linhas
--
-- Depois da aplicação, o caso AE do harness 2826 atua como
-- POSTCHECK por propriedades — não como precheck.
-- =============================================================
DO $precheck2196$
DECLARE
    v_n   INTEGER;
    v_md5 TEXT;
BEGIN
    SELECT count(*) INTO v_n
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'internal'
       AND p.proname = 'create_card_printing_profile_with_backfill';

    IF v_n <> 1 THEN
        RAISE EXCEPTION
          'REBASE_REQUIRED: esperada EXATAMENTE 1 internal.create_card_printing_profile_with_backfill, encontradas %. A Query 2196 substitui o corpo inteiro dessa funcao; sobrecarga ou ausencia invalida o diff. NADA foi escrito.',
          v_n;
    END IF;

    SELECT md5(p.prosrc) INTO v_md5
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'internal'
       AND p.proname = 'create_card_printing_profile_with_backfill';

    IF v_md5 <> '4ce5cc4ca573955c744ffe376eb03ca4' THEN
        RAISE EXCEPTION
          'REBASE_REQUIRED: md5(prosrc) do consumidor 1 e %, esperado 4ce5cc4ca573955c744ffe376eb03ca4 (baseline de 2026-09-14). O corpo LIVE mudou entre o staging e a aplicacao — este arquivo partiu de outra versao. REBASEAR o corpo do consumidor 1 contra o prosrc atual antes de aplicar. NADA foi escrito.',
          v_md5;
    END IF;
END;
$precheck2196$;

-- =============================================================
-- 1. HELPER ÚNICO DE LOOKUP COM PRECEDÊNCIA
-- =============================================================

CREATE OR REPLACE FUNCTION internal.lookup_variant_type_for_row(
    p_game_id          UUID,
    p_asset_source_id  UUID,
    p_card_set_id      UUID,
    p_residual_type    TEXT,
    p_residual_foil    TEXT,
    p_residual_subtype TEXT,
    p_residual_stamp   TEXT[]
)
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    WITH escopo AS (
        SELECT s.external_set_id
          FROM internal.resolve_variant_mapping_scope(p_card_set_id, p_asset_source_id) s
    )
    SELECT vm.variant_type_id
      FROM public.card_variant_type_external_mapping vm
      LEFT JOIN escopo ON TRUE
     WHERE vm.game_id         = p_game_id
       AND vm.asset_source_id = p_asset_source_id
       AND (vm.external_set_id IS NULL
            OR vm.external_set_id = escopo.external_set_id)
       AND vm.normalized_type = p_residual_type
       AND COALESCE(vm.normalized_foil, '')            = COALESCE(p_residual_foil, '')
       AND COALESCE(vm.normalized_subtype, '')         = COALESCE(p_residual_subtype, '')
       AND COALESCE(vm.normalized_stamp, '{}'::TEXT[]) = COALESCE(p_residual_stamp, '{}'::TEXT[])
     ORDER BY (vm.external_set_id IS NULL) ASC
     LIMIT 1;
$$;

COMMENT ON FUNCTION internal.lookup_variant_type_for_row(UUID, UUID, UUID, TEXT, TEXT, TEXT, TEXT[]) IS
    'UNICO ponto do banco onde a precedencia scoped > global do mapping de Card Variant Type e implementada. Determinismo garantido pelos dois indices parciais unicos da Query 2191: o conjunto candidato tem no maximo 2 elementos e ORDER BY (external_set_id IS NULL) e total sobre ele. Escopo vem de card_set_external_reference ATIVA, nunca do job.';

REVOKE ALL ON FUNCTION internal.lookup_variant_type_for_row(UUID, UUID, UUID, TEXT, TEXT, TEXT, TEXT[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION internal.lookup_variant_type_for_row(UUID, UUID, UUID, TEXT, TEXT, TEXT, TEXT[]) FROM anon, authenticated, service_role;

-- =============================================================
-- 2. CONSUMIDOR 1 — WORKER DE PRINTING PROFILE (base: Query 2190)
--
-- Único diff executável: `touched` expõe card_set_id; o LEFT JOIN
-- contra o mapping vira chamada ao helper em `classified`.
-- =============================================================

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

    -- PASSO 6 — SELEÇÃO DAS CANDIDATAS.
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

        -- PASSO 8 — RECONCILIAÇÃO.
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
                   s.id      AS asset_source_id,
                   cs.id     AS card_set_id      -- >>> DIFF 2196 <<<
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
            SELECT t.id,
                   t.job_id,
                   t.printing_profile_id,
                   lk.variant_type_id,
                   CASE
                     WHEN t.printing_state NOT IN ('RESOLVED_NO_PRINTING', 'RESOLVED_WITH_PROFILE')
                          THEN 'C'
                     WHEN lk.variant_type_id IS NOT NULL
                          THEN 'A'
                     ELSE 'B'
                   END AS outcome
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

        IF v_reconciled IS DISTINCT FROM v_touched THEN
            RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_RECONCILIATION_GAP: % linha(s) atingidas, % reconciliadas. Alguma linha ficou sem estado terminal definido.',
                v_touched, v_reconciled;
        END IF;

        IF (v_revalidated + v_pending) IS DISTINCT FROM v_touched THEN
            RAISE EXCEPTION 'CREATE_CARD_PRINTING_PROFILE_COUNTER_GAP: rows_revalidated (%) + rows_still_pending (%) <> universo atingido (%).',
                v_revalidated, v_pending, v_touched;
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
            'jobs_affected',      v_jobs
        )
    );

    RETURN QUERY
        SELECT v_profile_id, v_sealed, v_touched, v_revalidated, v_pending, v_jobs;
END;
$worker$;

-- ACL preservada por CREATE OR REPLACE. Os REVOKEs da Query 2189
-- NÃO são repetidos aqui, de propósito e pelo mesmo motivo da
-- Query 2190: repeti-los mascararia uma eventual perda de ACL que
-- o postcheck precisa ser capaz de detectar.

-- =============================================================
-- ESCOPO DESTE ARQUIVO — UM CONSUMIDOR, NÃO DOIS
--
-- Corrigido em GATE-A-REV-01: a v1.0 anunciava no cabeçalho um
-- "Consumidor 2" que o arquivo NÃO continha fisicamente, deixando
-- uma promessa em comentário. Promessa em comentário não é
-- artefato.
--
-- Esta Query contém, de fato:
--   1. internal.lookup_variant_type_for_row()  — o helper único
--   2. internal.create_card_printing_profile_with_backfill()
--
-- O segundo consumidor —
-- public.admin_resolve_catalog_variant_import_printing_mapping —
-- vive na Query 2197, gerada mecanicamente a partir do prosrc
-- LIVE, com diff textual exaustivo. Arquivo separado, real,
-- versionado.
-- =============================================================

COMMIT;

-- ================================================================
-- CONFIRMADO EXECUTADO em 2026-09-14 (GATE-B-EXECUTION-01). O precheck de
-- rebase da Seção 0 passou na aplicação real. Cópia mantida em proposals/
-- como evidência histórica do ciclo.
-- ================================================================
