-- ============================================================================
-- Query 2220 — variant_type_mapping_impact() + _decision() v2.0
-- Status: PROPOSTA — NÃO EXECUTADA · Versão 1.0
-- WRITE-PATH-STAGING-01 · itens 1, 6
--
-- BASE: database/schema/2192_..._read_contract.sql (CANÔNICA / LIVE, 563 li).
--
-- ----------------------------------------------------------------------------
-- ESCOPO — duas funções mudam, uma NÃO muda
-- ----------------------------------------------------------------------------
--   internal.variant_type_mapping_impact   → v2.0  (linha 183 da canônica)
--   internal.variant_type_mapping_decision → v2.0  (linha 399 da canônica)
--   internal.lookup_variant_type_for_row   → **INALTERADA**
--   internal.resolve_variant_mapping_scope → **INALTERADA**
--
--   PROVA NEGATIVA de lookup_variant_type_for_row. Ela recebe o residual
--   como PARÂMETRO (p_residual_type/foil/subtype/stamp); não o calcula.
--   Quem muda é o CHAMADOR, que passa a entregar o residual pós-DOIS-eixos
--   em vez de pós-um-eixo. O corpo da função — a precedência scoped > global
--   dos dois índices parciais da 2191 — permanece correto letra por letra.
--   Reescrevê-la só para "acompanhar" introduziria risco sem ganho.
--   O que muda é o COMMENT, para que o contrato de entrada fique explícito.
--
--   internal.resolve_variant_mapping_scope não toca em eixo nenhum: resolve
--   Card Set → external_set_id. Inalterada, sem sequer novo COMMENT.
--
-- ----------------------------------------------------------------------------
-- O QUE MUDA
-- ----------------------------------------------------------------------------
--   (a) `compute_variant_residual_signature` → `resolve_variant_row_axes`
--       nos dois pontos (impact 2.2 · decision pré-condição);
--   (b) o universo do impact exige os DOIS eixos terminais;
--   (c) `decision` ganha o bloqueio EDITION_CONTEXT_UNRESOLVED, simétrico
--       ao PRINTING_UNRESOLVED que já existia.
--
-- PRESERVADO: assinaturas · RETURNS TABLE · STABLE · SECURITY DEFINER ·
--   search_path='' · REVOKEs · a ordem de precedência de veredito corrigida
--   em GATE-A-REV-01 (C antes de B antes de PROVENANCE) · o guard
--   conservador de provenance · o guard SCOPE_MISMATCH · DUPLICATE_GLOBAL /
--   DUPLICATE_SCOPED · todas as mensagens.
--
-- ----------------------------------------------------------------------------
-- POR QUE O RESIDUAL PÓS-DOIS-EIXOS MUDA O IMPACTO
-- ----------------------------------------------------------------------------
--   O impact compara o residual de cada row contra o residual do mapping
--   proposto. Com residual pós-UM-eixo, uma row cujos tokens de contexto
--   ainda estão no resíduo teria assinatura diferente de outra idêntica cujo
--   contexto já foi consumido — e as duas seriam classificadas em universos
--   distintos. O preview mostraria um número, o execute agiria sobre outro.
--   Comparar sempre o residual pós-DOIS-eixos elimina a assimetria.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------- GATE ------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                    WHERE n.nspname='internal' AND p.proname='resolve_variant_row_axes') THEN
        RAISE EXCEPTION 'READ_CONTRACT_V2_BLOCKED: internal.resolve_variant_row_axes ausente. Rode a Query 2211 antes.';
    END IF;
END $$;

-- =============================================================
-- 1. CLASSIFICADOR DE IMPACTO A / B / C — v2.0
-- =============================================================
CREATE OR REPLACE FUNCTION internal.variant_type_mapping_impact(
    p_game_id                UUID,
    p_asset_source_id        UUID,
    p_external_set_id        TEXT,      -- NULL = escopo GLOBAL
    p_residual_type          TEXT,
    p_residual_foil          TEXT,
    p_residual_subtype       TEXT,
    p_residual_stamp         TEXT[],
    p_target_variant_type_id UUID
)
RETURNS TABLE(
    current_effective_mapping_id     UUID,
    current_effective_scope          TEXT,
    current_effective_variant_type_id UUID,
    supersedes_interpretation        BOOLEAN,
    rows_total                       INTEGER,
    rows_class_a                     INTEGER,
    rows_class_b                     INTEGER,
    canonical_class_c                INTEGER,
    rows_valid_reclassified          INTEGER,
    jobs_affected                    INTEGER,
    block_reason                     TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $impact$
DECLARE
    v_src_code   TEXT;
    v_cur_id     UUID;
    v_cur_scope  TEXT;
    v_cur_vt     UUID;
    v_supersedes BOOLEAN;
    v_total      INTEGER := 0;
    v_a          INTEGER := 0;
    v_b          INTEGER := 0;
    v_c          INTEGER := 0;
    v_reclass    INTEGER := 0;
    v_jobs       INTEGER := 0;
    v_prov_risk  BOOLEAN := FALSE;
    v_block      TEXT    := NULL;
BEGIN
    SELECT a.code INTO v_src_code
      FROM public.asset_source a WHERE a.id = p_asset_source_id;

    IF v_src_code IS NULL THEN
        RAISE EXCEPTION 'VARIANT_TYPE_MAPPING_IMPACT_SOURCE_NOT_FOUND: asset_source_id % nao existe.', p_asset_source_id;
    END IF;

    -- 1.1 INTERPRETAÇÃO EFETIVA VIGENTE. INALTERADO.
    SELECT vm.id,
           CASE WHEN vm.external_set_id IS NULL THEN 'GLOBAL' ELSE 'SOURCE_SET' END,
           vm.variant_type_id
      INTO v_cur_id, v_cur_scope, v_cur_vt
      FROM public.card_variant_type_external_mapping vm
     WHERE vm.game_id         = p_game_id
       AND vm.asset_source_id = p_asset_source_id
       AND (vm.external_set_id IS NULL
            OR (p_external_set_id IS NOT NULL AND vm.external_set_id = p_external_set_id))
       AND vm.normalized_type = p_residual_type
       AND COALESCE(vm.normalized_foil, '')          = COALESCE(p_residual_foil, '')
       AND COALESCE(vm.normalized_subtype, '')       = COALESCE(p_residual_subtype, '')
       AND COALESCE(vm.normalized_stamp, '{}'::TEXT[]) = COALESCE(p_residual_stamp, '{}'::TEXT[])
     ORDER BY (vm.external_set_id IS NULL) ASC
     LIMIT 1;

    v_supersedes := (v_cur_vt IS NOT NULL
                     AND v_cur_vt IS DISTINCT FROM p_target_variant_type_id);

    -- ---------------------------------------------------------
    -- 1.2 UNIVERSO ALVO + PARTIÇÃO A / B  — v2.0
    --     Contrato de TRÊS eixos (2211) no lugar do de DOIS (2176);
    --     o universo exige os DOIS eixos terminais. O nome antigo não
    --     é citado aqui: o postcheck varre `prosrc`, que inclui
    --     comentários, e a citação viraria falso-positivo.
    -- ---------------------------------------------------------
    WITH universo AS (
        SELECT r.id,
               r.job_id,
               r.validation_status,
               r.decision_status,
               r.persistence_status,
               r.resulting_variant_id,
               r.normalized_data,
               j.status AS job_status
          FROM public.catalog_variant_import_row r
          JOIN public.catalog_variant_import_job j ON j.id = r.job_id
          JOIN public.card_set  cs ON cs.id = j.card_set_id
          JOIN public.expansion e  ON e.id  = cs.expansion_id
          LEFT JOIN LATERAL internal.resolve_variant_mapping_scope(cs.id, p_asset_source_id) sc ON TRUE
          -- ESCOPO CANONICO (SOURCE-SCOPE-CORRECTION-01). O 4o argumento do
          -- routing e o identificador EXTERNO da Fonte (card_set_external_reference
          -- .external_set_id), NUNCA card_set.code. Os dois nao coincidem: os
          -- mappings SCOPED gravam o id da Fonte (ex.: 'base2'), enquanto
          -- card_set.code e o codigo interno ('BASE2'). A autoridade unica e
          -- internal.resolve_variant_mapping_scope(), ja materializada em `sc`.
          CROSS JOIN LATERAL internal.resolve_variant_row_axes(
              r.raw_data, e.game_id, p_asset_source_id, sc.external_set_id
          ) ax
         WHERE j.source  = v_src_code
           AND e.game_id = p_game_id
           AND (p_external_set_id IS NULL OR sc.external_set_id = p_external_set_id)
           AND ax.printing_state IN ('RESOLVED_NO_PRINTING', 'RESOLVED_WITH_PROFILE')
           AND ax.edition_context_state IN ('RESOLVED_NO_EDITION_CONTEXT', 'RESOLVED_WITH_EC_PROFILE')
           AND ax.residual_type = p_residual_type
           AND COALESCE(ax.residual_foil, '')          = COALESCE(p_residual_foil, '')
           AND COALESCE(ax.residual_subtype, '')       = COALESCE(p_residual_subtype, '')
           AND COALESCE(ax.residual_stamp, '{}'::TEXT[]) = COALESCE(p_residual_stamp, '{}'::TEXT[])
    ),
    classificado AS (
        SELECT u.*,
               (u.job_status = 'STAGED'
                AND u.decision_status    = 'PENDING'
                AND u.persistence_status = 'PENDING'
                AND u.resulting_variant_id IS NULL) AS is_a
          FROM universo u
    )
    SELECT count(*),
           count(*) FILTER (WHERE is_a),
           count(*) FILTER (WHERE NOT is_a),
           count(DISTINCT resulting_variant_id) FILTER (WHERE resulting_variant_id IS NOT NULL),
           count(*) FILTER (WHERE is_a
                              AND validation_status = 'VALID'
                              AND jsonb_typeof(normalized_data->'variant_type_id') = 'string'
                              AND (normalized_data->>'variant_type_id')::UUID
                                  IS DISTINCT FROM p_target_variant_type_id),
           count(DISTINCT job_id) FILTER (WHERE is_a)
      INTO v_total, v_a, v_b, v_c, v_reclass, v_jobs
      FROM classificado;

    -- 1.3 GUARD CONSERVADOR DE PROVENANCE. INALTERADO.
    IF v_supersedes AND v_c = 0 AND v_cur_vt IS NOT NULL THEN
        SELECT EXISTS (
            SELECT 1
              FROM public.card_variant cv
              JOIN public.card c   ON c.id  = cv.card_id
              JOIN public.card_set cs2 ON cs2.id = c.card_set_id
              LEFT JOIN LATERAL internal.resolve_variant_mapping_scope(cs2.id, p_asset_source_id) sc2 ON TRUE
              JOIN public.expansion e2 ON e2.id = cs2.expansion_id
             WHERE cv.variant_type_id = v_cur_vt
               AND e2.game_id = p_game_id
               AND (p_external_set_id IS NULL OR sc2.external_set_id = p_external_set_id)
        ) INTO v_prov_risk;
    END IF;

    -- 1.4 VEREDITO. ORDEM DE PRECEDÊNCIA PRESERVADA (GATE-A-REV-01):
    -- C antes de B antes de PROVENANCE — a condição mais grave primeiro.
    IF v_supersedes THEN
        IF v_c > 0 THEN
            v_block := 'CANONICAL_VARIANT_MATERIALIZED';
        ELSIF v_b > 0 THEN
            v_block := 'ROWS_NOT_ELIGIBLE';
        ELSIF v_prov_risk THEN
            v_block := 'PROVENANCE_INSUFFICIENT';
        END IF;
    END IF;

    RETURN QUERY SELECT v_cur_id, v_cur_scope, v_cur_vt, v_supersedes,
                        v_total, v_a, v_b, v_c, v_reclass, v_jobs, v_block;
END;
$impact$;

COMMENT ON FUNCTION internal.variant_type_mapping_impact(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT[], UUID) IS
    'Contrato UNICO de classificacao A/B/C, compartilhado por preview e execute. Leitura pura. v2.0: o universo e montado por internal.resolve_variant_row_axes e exige os DOIS eixos (Printing e Edition Context) TERMINALMENTE resolvidos — comparar residual pos-um-eixo classificaria em universos distintos duas rows identicas cujo contexto ainda estivesse no residuo. block_reason so e preenchido quando o mapping novo SUPERA uma interpretacao efetiva vigente.';

-- =============================================================
-- 2. DECISÃO COMPLETA — v2.0
-- =============================================================
CREATE OR REPLACE FUNCTION internal.variant_type_mapping_decision(
    p_origin_row_id   UUID,
    p_variant_type_id UUID,
    p_scope_kind      TEXT
)
RETURNS TABLE(
    ok                               BOOLEAN,
    block_reason                     TEXT,
    block_detail                     TEXT,
    game_id                          UUID,
    asset_source_id                  UUID,
    external_set_id                  TEXT,
    residual_type                    TEXT,
    residual_foil                    TEXT,
    residual_subtype                 TEXT,
    residual_stamp                   TEXT[],
    current_effective_mapping_id     UUID,
    current_effective_scope          TEXT,
    current_effective_variant_type_id UUID,
    supersedes_interpretation        BOOLEAN,
    rows_total                       INTEGER,
    rows_class_a                     INTEGER,
    rows_class_b                     INTEGER,
    canonical_class_c                INTEGER,
    rows_valid_reclassified          INTEGER,
    jobs_affected                    INTEGER
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $decision$
DECLARE
    v_row        public.catalog_variant_import_row%ROWTYPE;
    v_job_source TEXT;
    v_job_scope  TEXT;      -- catalog_variant_import_job.external_set_id (NAO e autoridade)
    v_card_set   UUID;
    -- v2.1 (SOURCE-SCOPE-CORRECTION-01): o 4o argumento do routing e o
    -- identificador EXTERNO da Fonte, resolvido por
    -- internal.resolve_variant_mapping_scope(). A variavel antiga
    -- `v_card_set_code` (card_set.code) foi ELIMINADA: era a origem do defeito
    -- de escopo — 'BASE2' (interno) nunca casa com 'base2' (Fonte).
    v_game_id    UUID;
    v_src_id     UUID;
    v_canon      TEXT := NULL;
    v_scope      TEXT := NULL;
    v_sig        RECORD;
    v_imp        RECORD;
    v_reason     TEXT := NULL;
    v_detail     TEXT := NULL;
BEGIN
    IF p_scope_kind IS NULL OR p_scope_kind NOT IN ('GLOBAL', 'SOURCE_SET') THEN
        RAISE EXCEPTION 'VARIANT_TYPE_MAPPING_INVALID_SCOPE: p_scope_kind deve ser GLOBAL ou SOURCE_SET (recebido: %).', p_scope_kind;
    END IF;

    IF p_origin_row_id IS NULL OR p_variant_type_id IS NULL THEN
        RETURN QUERY SELECT FALSE, 'MISSING_IDS',
            'p_origin_row_id e p_variant_type_id sao obrigatorios.',
            NULL::UUID, NULL::UUID, NULL::TEXT, NULL::TEXT, NULL::TEXT, NULL::TEXT, NULL::TEXT[],
            NULL::UUID, NULL::TEXT, NULL::UUID, NULL::BOOLEAN,
            0, 0, 0, 0, 0, 0;
        RETURN;
    END IF;

    SELECT r.* INTO v_row FROM public.catalog_variant_import_row r WHERE r.id = p_origin_row_id;
    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, 'ROW_NOT_FOUND',
            format('nenhuma linha para o id informado (%s).', p_origin_row_id),
            NULL::UUID, NULL::UUID, NULL::TEXT, NULL::TEXT, NULL::TEXT, NULL::TEXT, NULL::TEXT[],
            NULL::UUID, NULL::TEXT, NULL::UUID, NULL::BOOLEAN,
            0, 0, 0, 0, 0, 0;
        RETURN;
    END IF;

    SELECT j.source, j.card_set_id, j.external_set_id
      INTO v_job_source, v_card_set, v_job_scope
      FROM public.catalog_variant_import_job j WHERE j.id = v_row.job_id;

    SELECT e.game_id INTO v_game_id
      FROM public.card c
      JOIN public.card_set cs ON cs.id = c.card_set_id
      JOIN public.expansion e ON e.id  = cs.expansion_id
     WHERE c.id = v_row.card_id;

    SELECT a.id INTO v_src_id FROM public.asset_source a WHERE a.code = v_job_source;

    IF v_job_source IS NULL OR v_game_id IS NULL OR v_src_id IS NULL THEN
        RETURN QUERY SELECT FALSE, 'CONTEXT_NOT_RESOLVABLE',
            'nao foi possivel resolver job, Game ou Fonte a partir da linha de origem.',
            v_game_id, v_src_id, NULL::TEXT, NULL::TEXT, NULL::TEXT, NULL::TEXT, NULL::TEXT[],
            NULL::UUID, NULL::TEXT, NULL::UUID, NULL::BOOLEAN,
            0, 0, 0, 0, 0, 0;
        RETURN;
    END IF;

    -- Compatibilidade histórica do caminho GLOBAL (Query 2150). INALTERADO.
    IF p_scope_kind = 'GLOBAL' AND v_row.validation_status <> 'NEEDS_REVIEW' THEN
        v_reason := 'ORIGIN_NOT_NEEDS_REVIEW';
        v_detail := 'so linhas sem mapeamento (NEEDS_REVIEW) podem ser resolvidas pelo caminho GLOBAL.';
    END IF;

    IF v_reason IS NULL
       AND NOT EXISTS (SELECT 1 FROM public.card_variant_type t
                        WHERE t.id = p_variant_type_id AND t.game_id = v_game_id) THEN
        v_reason := 'VARIANT_TYPE_MISMATCH';
        v_detail := 'o Card Variant Type informado nao existe ou nao pertence ao Game desta combinacao.';
    END IF;

    -- v2.0 — ROUTING TERMINAL ÚNICO: contrato de TRÊS eixos (2211) no lugar do
    -- de DOIS (2176). O nome antigo não é citado aqui — o postcheck varre
    -- `prosrc`, que inclui comentários, e a citação viraria falso-positivo.
    -- ESCOPO CANONICO (SOURCE-SCOPE-CORRECTION-01). A resolucao de `v_canon`
    -- foi HOISTADA para ca — antes do routing — porque o 4o argumento de
    -- resolve_variant_row_axes() e o identificador EXTERNO da Fonte, nao
    -- card_set.code. A unica autoridade e resolve_variant_mapping_scope().
    -- O guard de SCOPE_MISMATCH abaixo consome o MESMO `v_canon`; a resolucao
    -- nao e refeita (chamada STABLE, resultado identico, uma leitura a menos).
    SELECT s.external_set_id INTO v_canon
      FROM internal.resolve_variant_mapping_scope(v_card_set, v_src_id) s;

    SELECT * INTO v_sig
      FROM internal.resolve_variant_row_axes(v_row.raw_data, v_game_id, v_src_id, v_canon);

    IF v_reason IS NULL
       AND v_sig.printing_state NOT IN ('RESOLVED_NO_PRINTING', 'RESOLVED_WITH_PROFILE') THEN
        v_reason := 'PRINTING_UNRESOLVED';
        v_detail := format('linha pendente pelo eixo de IMPRESSAO (estado: %s). Resolva o Printing antes.', v_sig.printing_state);
    END IF;

    -- v2.0 — BLOQUEIO SIMÉTRICO DO TERCEIRO EIXO.
    -- Sem isto, um mapping de Variant Type seria criado a partir de um
    -- residual que ainda contém tokens de contexto: o Finish absorveria
    -- contexto de edição, que é a contaminação que o eixo 3 existe para
    -- eliminar. Mesma forma, mesmo nível, mesmo fail-closed do Printing.
    IF v_reason IS NULL
       AND v_sig.edition_context_state NOT IN ('RESOLVED_NO_EDITION_CONTEXT', 'RESOLVED_WITH_EC_PROFILE') THEN
        v_reason := 'EDITION_CONTEXT_UNRESOLVED';
        v_detail := format('linha pendente pelo eixo de CONTEXTO DE EDICAO (estado: %s). Resolva o mapping de Edition Context antes — criar Variant Type sobre residual contaminado absorveria contexto no acabamento.', v_sig.edition_context_state);
    END IF;

    -- GUARD DE MISMATCH. A resolucao de `v_canon` foi hoistada para antes do
    -- routing (SOURCE-SCOPE-CORRECTION-01); o guard consome o mesmo valor.
    IF v_reason IS NULL
       AND v_job_scope IS NOT NULL
       AND v_canon IS NOT NULL
       AND v_job_scope IS DISTINCT FROM v_canon THEN
        v_reason := 'SCOPE_MISMATCH';
        v_detail := format('job.external_set_id=%s diverge da referencia canonica ATIVA=%s para este Card Set/Fonte. A autoridade e card_set_external_reference; a divergencia indica dado de operacao corrompido e bloqueia por seguranca.',
                           v_job_scope, v_canon);
    END IF;

    IF p_scope_kind = 'SOURCE_SET' THEN
        v_scope := v_canon;

        IF v_reason IS NULL AND v_scope IS NULL THEN
            v_reason := 'SOURCE_SET_NOT_FOUND';
            v_detail := 'o Card Set deste job nao possui referencia externa ATIVA em card_set_external_reference para esta Fonte.';
        END IF;
    END IF;

    -- Duplicidade NO MESMO ESCOPO. INALTERADO.
    IF v_reason IS NULL AND EXISTS (
        SELECT 1 FROM public.card_variant_type_external_mapping m
         WHERE m.game_id         = v_game_id
           AND m.asset_source_id = v_src_id
           AND m.external_set_id IS NOT DISTINCT FROM v_scope
           AND m.normalized_type = v_sig.residual_type
           AND COALESCE(m.normalized_foil, '')            = COALESCE(v_sig.residual_foil, '')
           AND COALESCE(m.normalized_subtype, '')         = COALESCE(v_sig.residual_subtype, '')
           AND COALESCE(m.normalized_stamp, '{}'::TEXT[]) = COALESCE(v_sig.residual_stamp, '{}'::TEXT[])
    ) THEN
        v_reason := CASE WHEN p_scope_kind = 'GLOBAL' THEN 'DUPLICATE_GLOBAL' ELSE 'DUPLICATE_SCOPED' END;
        v_detail := 'ja existe um mapeamento para esta combinacao residual NESTE escopo.';
    END IF;

    -- Impacto A/B/C — sempre calculado. INALTERADO.
    SELECT * INTO v_imp
      FROM internal.variant_type_mapping_impact(
               v_game_id, v_src_id, v_scope,
               v_sig.residual_type, v_sig.residual_foil,
               v_sig.residual_subtype, v_sig.residual_stamp,
               p_variant_type_id);

    IF v_reason IS NULL AND v_imp.block_reason IS NOT NULL THEN
        v_reason := v_imp.block_reason;
        v_detail := format('universo=%s classe_A=%s classe_B=%s canonicas_C=%s',
                           v_imp.rows_total, v_imp.rows_class_a,
                           v_imp.rows_class_b, v_imp.canonical_class_c);
    END IF;

    RETURN QUERY SELECT
        (v_reason IS NULL), v_reason, v_detail,
        v_game_id, v_src_id, v_scope,
        v_sig.residual_type, v_sig.residual_foil, v_sig.residual_subtype, v_sig.residual_stamp,
        v_imp.current_effective_mapping_id, v_imp.current_effective_scope,
        v_imp.current_effective_variant_type_id, v_imp.supersedes_interpretation,
        v_imp.rows_total, v_imp.rows_class_a, v_imp.rows_class_b,
        v_imp.canonical_class_c, v_imp.rows_valid_reclassified, v_imp.jobs_affected;
END;
$decision$;

COMMENT ON FUNCTION internal.variant_type_mapping_decision(UUID, UUID, TEXT) IS
    'Contrato UNICO de pre-condicoes + impacto. NAO levanta excecao de regra de negocio: devolve ok/block_reason como DADO. v2.0: residual vem de internal.resolve_variant_row_axes (POS-DOIS-EIXOS) e ha bloqueio EDITION_CONTEXT_UNRESOLVED simetrico ao PRINTING_UNRESOLVED. O preview devolve este retorno verbatim; o worker converte block_reason em excecao antes de escrever.';

-- =============================================================
-- 3. lookup_variant_type_for_row — CORPO INALTERADO, COMMENT novo
--    Nao ha CREATE OR REPLACE: a funcao nao muda. Apenas o contrato
--    de ENTRADA fica explicito, para que nenhum chamador futuro lhe
--    entregue residual pos-um-eixo por engano.
-- =============================================================
COMMENT ON FUNCTION internal.lookup_variant_type_for_row(UUID, UUID, UUID, TEXT, TEXT, TEXT, TEXT[]) IS
    'UNICO ponto do banco onde a precedencia scoped > global do mapping de Card Variant Type e implementada. Determinismo garantido pelos dois indices parciais unicos da Query 2191. Escopo vem de card_set_external_reference ATIVA, nunca do job. CONTRATO DE ENTRADA (Query 2220): os quatro parametros de residual DEVEM vir de internal.resolve_variant_row_axes, isto e, residual POS-DOIS-EIXOS. Entregar residual pos-um-eixo faria o Finish absorver tokens de contexto de edicao. Esta funcao NAO calcula residual e nao tem como se defender disso — a responsabilidade e do chamador.';

REVOKE ALL ON FUNCTION internal.variant_type_mapping_decision(UUID, UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION internal.variant_type_mapping_decision(UUID, UUID, TEXT) FROM anon, authenticated, service_role;
REVOKE ALL ON FUNCTION internal.variant_type_mapping_impact(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT[], UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION internal.variant_type_mapping_impact(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT[], UUID) FROM anon, authenticated, service_role;

-- ---------------------------------------------------------------- POSTCHECK -
DO $$
DECLARE v_i TEXT; v_d TEXT; v_l TEXT;
BEGIN
    SELECT p.prosrc INTO v_i FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='internal' AND p.proname='variant_type_mapping_impact';
    SELECT p.prosrc INTO v_d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='internal' AND p.proname='variant_type_mapping_decision';
    SELECT p.prosrc INTO v_l FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='internal' AND p.proname='lookup_variant_type_for_row';

    -- PROVA NEGATIVA nas duas que mudam.
    IF v_i LIKE '%compute_variant_residual_signature%' THEN
        RAISE EXCEPTION 'IMPACT_V2_STALE_ROUTING.'; END IF;
    IF v_d LIKE '%compute_variant_residual_signature%' THEN
        RAISE EXCEPTION 'DECISION_V2_STALE_ROUTING.'; END IF;
    IF v_i NOT LIKE '%edition_context_state IN%' THEN
        RAISE EXCEPTION 'IMPACT_V2_NO_EC_FILTER.'; END IF;
    IF v_d NOT LIKE '%EDITION_CONTEXT_UNRESOLVED%' THEN
        RAISE EXCEPTION 'DECISION_V2_NO_EC_BLOCK.'; END IF;

    -- PROVA POSITIVA de NÃO-alteração: lookup continua sem calcular residual.
    IF v_l LIKE '%resolve_variant_row_axes%' OR v_l LIKE '%compute_variant_residual_signature%' THEN
        RAISE EXCEPTION 'LOOKUP_UNEXPECTEDLY_CHANGED: lookup_variant_type_for_row passou a calcular residual. Ela deve apenas RECEBE-lo.';
    END IF;

    -- Precedência de veredito preservada.
    IF position('CANONICAL_VARIANT_MATERIALIZED' in v_i) > position('ROWS_NOT_ELIGIBLE' in v_i) THEN
        RAISE EXCEPTION 'IMPACT_V2_VERDICT_ORDER: precedencia C-antes-de-B perdida.';
    END IF;

    RAISE NOTICE 'read contract v2.0 OK — 6/6 provas (2 alteradas, 1 provadamente inalterada).';
END $$;

-- ============================================================================
-- PERFORMANCE
--   Mesmo número de LATERAIs da canônica: uma por row, set-based. A 2211
--   acrescenta um lookup indexado em card_edition_context_external_mapping
--   por token residual — não há iteração por trait.
--
-- ARMADO PARA ROLLOUT (ROLLOUT-EXECUTION-READINESS-01). Terminador COMMIT.
-- Corpo auditado PRESERVADO byte a byte; a unica alteracao de armamento foi
-- ROLLBACK; -> COMMIT;. A protecao contra execucao prematura e GOVERNANCA
-- (autorizacao de Fabricio + ordem de batches), nao o terminador — mesma
-- decisao ja aceita em R1 para 2203-2211.
-- ============================================================================
COMMIT;
