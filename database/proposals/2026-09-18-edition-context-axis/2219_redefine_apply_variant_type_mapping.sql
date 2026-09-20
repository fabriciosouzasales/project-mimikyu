-- ============================================================================
-- Query 2219 — internal.apply_variant_type_mapping() v2.0
-- Status: PROPOSTA — NÃO EXECUTADA · Versão 1.0
-- WRITE-PATH-STAGING-01 · itens 6, 7, 8
--
-- BASE: database/schema/2193_..._worker.sql (CANÔNICA / LIVE, 324 li).
-- Estado FINAL — corpo inteiro.
--
-- ----------------------------------------------------------------------------
-- O QUE MUDA
-- ----------------------------------------------------------------------------
--   (a) As DUAS chamadas a compute_variant_residual_signature (linhas 175 e
--       222 da canônica) passam a ser internal.resolve_variant_row_axes();
--   (b) o universo A exige os DOIS eixos TERMINALMENTE resolvidos;
--   (c) a propagation grava as TRÊS chaves numa única operação coerente;
--   (d) rows com residual casando mas Edition Context indeterminado NÃO são
--       promovidas a VALID — ficam contadas em rows_still_pending.
--
-- PRESERVADO: assinatura · RETURNS TABLE · SECURITY DEFINER · search_path=''
--   REVOKEs · GUARD 1 (ator admin) · GUARD 2 (decisão única, zero lógica de
--   pré-condição duplicada) · todas as mensagens de block_reason LITERAIS
--   · GLOBAL/SOURCE_SET · coexistência (jamais UPDATE do mapping global)
--   · locks JOB→ROW em ordem determinística · counters só dos jobs afetados
--   · audit log reutilizando a action existente · fail-closed.
--
-- ----------------------------------------------------------------------------
-- NÃO PROMOVER A VALID COM EIXO EM ABERTO (item 7)
-- ----------------------------------------------------------------------------
--   A canônica marcava VALID todo o universo A. Com o terceiro eixo isso
--   deixa de ser seguro: uma row cujo residual casa com o mapping novo pode
--   ter Edition Context ainda INDETERMINADO. Promovê-la a VALID
--     (i)  violaria o guard de 2214 (VALID operacional exige a chave);
--     (ii) afirmaria uma decisão que ninguém tomou.
--
--   Solução: o universo A é PARTICIONADO.
--     A-RESOLVIDO ... os dois eixos terminais ⇒ VALID + três chaves.
--     A-BLOQUEADO ... residual casa, EC indeterminado ⇒ permanece
--                     NEEDS_REVIEW, chave de EC AUSENTE, nada é escrito.
--   `rows_total` soma os dois. `rows_reclassified` conta o primeiro.
--   `rows_still_pending` conta o segundo — que era sempre 0 na canônica e
--   agora carrega significado real.
--
--   O gate de reconciliação continua existindo, reformulado: nada pode se
--   perder entre as duas partições.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION internal.apply_variant_type_mapping(
    p_actor_id         UUID,
    p_origin_row_id    UUID,
    p_variant_type_id  UUID,
    p_scope_kind       TEXT           -- 'GLOBAL' | 'SOURCE_SET'
)
RETURNS TABLE(
    mapping_id              UUID,
    scope_kind              TEXT,
    external_set_id         TEXT,
    rows_total              INTEGER,
    rows_reclassified       INTEGER,
    rows_still_pending      INTEGER,
    jobs_affected           INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $worker$
DECLARE
    v_job_source TEXT;
    v_card_set   UUID;
    v_game_id    UUID;
    v_src_id     UUID;
    v_scope      TEXT;
    v_dec        RECORD;   -- retorno de internal.variant_type_mapping_decision()
    v_mapping_id UUID;

    v_row_ids     UUID[];  -- A-RESOLVIDO
    v_blocked_ids UUID[];  -- A-BLOQUEADO (v2.0)
    v_job_ids    UUID[];
    v_touched    INTEGER := 0;
    v_reconciled INTEGER := 0;
    v_blocked    INTEGER := 0;
    v_valid      INTEGER := 0;
    v_pending    INTEGER := 0;
    v_jobs       INTEGER := 0;
BEGIN
    -- =========================================================
    -- GUARD 1 — ATOR E ESCOPO
    -- =========================================================
    IF p_actor_id IS NULL THEN
        RAISE EXCEPTION 'APPLY_VARIANT_TYPE_MAPPING_MISSING_ACTOR: p_actor_id e obrigatorio.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.admin_user a WHERE a.id = p_actor_id) THEN
        RAISE EXCEPTION 'APPLY_VARIANT_TYPE_MAPPING_ACTOR_NOT_ADMIN: p_actor_id (%) nao e administrador cadastrado.', p_actor_id;
    END IF;

    IF p_scope_kind IS NULL OR p_scope_kind NOT IN ('GLOBAL', 'SOURCE_SET') THEN
        RAISE EXCEPTION 'APPLY_VARIANT_TYPE_MAPPING_INVALID_SCOPE: p_scope_kind deve ser GLOBAL ou SOURCE_SET (recebido: %).', p_scope_kind;
    END IF;

    IF p_origin_row_id IS NULL OR p_variant_type_id IS NULL THEN
        RAISE EXCEPTION 'APPLY_VARIANT_TYPE_MAPPING_MISSING_IDS: p_origin_row_id e p_variant_type_id sao obrigatorios.';
    END IF;

    -- =========================================================
    -- GUARD 2 — DECISÃO COMPLETA, EM UMA ÚNICA CHAMADA
    -- >>> ZERO LÓGICA DE PRÉ-CONDIÇÃO DUPLICADA AQUI. <<<
    -- (INALTERADO. A 2220 atualiza a decision para devolver residual
    --  pós-DOIS-eixos; este worker continua apenas consumindo.)
    -- =========================================================
    SELECT * INTO v_dec
      FROM internal.variant_type_mapping_decision(
               p_origin_row_id, p_variant_type_id, p_scope_kind);

    IF NOT v_dec.ok THEN
        IF v_dec.block_reason = 'ORIGIN_NOT_NEEDS_REVIEW' THEN
            RAISE EXCEPTION 'ADMIN_RESOLVE_CATALOG_VARIANT_IMPORT_MAPPING_NOT_NEEDS_REVIEW: so linhas sem mapeamento (NEEDS_REVIEW) podem ser resolvidas por aqui.';
        ELSIF v_dec.block_reason = 'DUPLICATE_GLOBAL' THEN
            RAISE EXCEPTION 'ADMIN_RESOLVE_CATALOG_VARIANT_IMPORT_MAPPING_DUPLICATE: ja existe um mapeamento para esta combinacao residual nesta Fonte/Game.';
        ELSIF v_dec.block_reason = 'SCOPE_MISMATCH' THEN
            RAISE EXCEPTION 'VARIANT_IMPORT_SCOPE_MISMATCH: %.', COALESCE(v_dec.block_detail, '');
        ELSIF v_dec.block_reason IN ('ROWS_NOT_ELIGIBLE',
                                     'CANONICAL_VARIANT_MATERIALIZED',
                                     'PROVENANCE_INSUFFICIENT') THEN
            RAISE EXCEPTION 'VARIANT_TYPE_MAPPING_RECONCILIATION_REQUIRED: % — %. O mapping NAO foi criado e NENHUMA linha foi alterada. Identidade ja materializada sob a interpretacao anterior exige reconciliacao editorial explicita.',
                v_dec.block_reason, COALESCE(v_dec.block_detail, '');
        ELSE
            RAISE EXCEPTION 'APPLY_VARIANT_TYPE_MAPPING_BLOCKED: % — %.',
                v_dec.block_reason, COALESCE(v_dec.block_detail, '');
        END IF;
    END IF;

    v_game_id    := v_dec.game_id;
    v_src_id     := v_dec.asset_source_id;
    v_scope      := v_dec.external_set_id;

    SELECT j.source, j.card_set_id INTO v_job_source, v_card_set
      FROM public.catalog_variant_import_job j
      JOIN public.catalog_variant_import_row r ON r.job_id = j.id
     WHERE r.id = p_origin_row_id;

    -- =========================================================
    -- PASSO 1 — CRIAR O MAPPING (COEXISTÊNCIA, NUNCA UPDATE). INALTERADO.
    -- =========================================================
    INSERT INTO public.card_variant_type_external_mapping (
        game_id, asset_source_id, external_set_id,
        external_type, external_foil, external_subtype, external_stamp,
        normalized_type, normalized_foil, normalized_subtype, normalized_stamp,
        variant_type_id
    ) VALUES (
        v_game_id, v_src_id, v_scope,
        v_dec.residual_type, v_dec.residual_foil, v_dec.residual_subtype,
        NULLIF(v_dec.residual_stamp, '{}'::TEXT[]),
        v_dec.residual_type, v_dec.residual_foil, v_dec.residual_subtype,
        NULLIF(v_dec.residual_stamp, '{}'::TEXT[]),
        p_variant_type_id
    ) RETURNING id INTO v_mapping_id;

    -- =========================================================
    -- PASSO 2 — UNIVERSO CLASSE A, PARTICIONADO (v2.0)
    --
    -- O contrato de TRÊS eixos (2211) substitui o de DOIS (2176) — o nome
    -- antigo não é citado neste comentário porque o postcheck varre `prosrc`,
    -- que inclui comentários, e a citação viraria falso-positivo:
    -- o residual comparado é o que sobra APÓS OS DOIS EIXOS. Comparar contra
    -- o residual pós-um-eixo casaria linhas cujos tokens de contexto ainda
    -- estão no resíduo — exatamente a contaminação que o eixo 3 elimina.
    --
    -- A-RESOLVIDO: os dois eixos terminais.
    -- =========================================================
    SELECT ARRAY(
        SELECT r.id
          FROM public.catalog_variant_import_row r
          JOIN public.catalog_variant_import_job j ON j.id = r.job_id
          JOIN public.card_set  cs ON cs.id = j.card_set_id
          JOIN public.expansion e  ON e.id  = cs.expansion_id
          LEFT JOIN LATERAL internal.resolve_variant_mapping_scope(cs.id, v_src_id) sc ON TRUE
          CROSS JOIN LATERAL internal.resolve_variant_row_axes(
              r.raw_data, e.game_id, v_src_id, sc.external_set_id) ax
         WHERE j.source  = v_job_source
           AND e.game_id = v_game_id
           AND (v_scope IS NULL OR sc.external_set_id = v_scope)
           AND j.status              = 'STAGED'
           AND r.decision_status     = 'PENDING'
           AND r.persistence_status  = 'PENDING'
           AND r.resulting_variant_id IS NULL
           AND ax.printing_state IN ('RESOLVED_NO_PRINTING', 'RESOLVED_WITH_PROFILE')
           AND ax.edition_context_state IN ('RESOLVED_NO_EDITION_CONTEXT', 'RESOLVED_WITH_EC_PROFILE')
           AND ax.residual_type = v_dec.residual_type
           AND COALESCE(ax.residual_foil, '')            = COALESCE(v_dec.residual_foil, '')
           AND COALESCE(ax.residual_subtype, '')         = COALESCE(v_dec.residual_subtype, '')
           AND COALESCE(ax.residual_stamp, '{}'::TEXT[]) = COALESCE(v_dec.residual_stamp, '{}'::TEXT[])
         ORDER BY r.id
    ) INTO v_row_ids;

    -- A-BLOQUEADO: residual casa, Printing terminal, mas Edition Context
    -- INDETERMINADO. Nao entra na propagation — ficaria VALID com o eixo 3
    -- em aberto, que o guard de 2214 recusa e que seria mentira semantica.
    SELECT ARRAY(
        SELECT r.id
          FROM public.catalog_variant_import_row r
          JOIN public.catalog_variant_import_job j ON j.id = r.job_id
          JOIN public.card_set  cs ON cs.id = j.card_set_id
          JOIN public.expansion e  ON e.id  = cs.expansion_id
          LEFT JOIN LATERAL internal.resolve_variant_mapping_scope(cs.id, v_src_id) sc ON TRUE
          CROSS JOIN LATERAL internal.resolve_variant_row_axes(
              r.raw_data, e.game_id, v_src_id, sc.external_set_id) ax
         WHERE j.source  = v_job_source
           AND e.game_id = v_game_id
           AND (v_scope IS NULL OR sc.external_set_id = v_scope)
           AND j.status              = 'STAGED'
           AND r.decision_status     = 'PENDING'
           AND r.persistence_status  = 'PENDING'
           AND r.resulting_variant_id IS NULL
           AND ax.printing_state IN ('RESOLVED_NO_PRINTING', 'RESOLVED_WITH_PROFILE')
           AND ax.edition_context_state NOT IN ('RESOLVED_NO_EDITION_CONTEXT', 'RESOLVED_WITH_EC_PROFILE')
           AND ax.residual_type = v_dec.residual_type
           AND COALESCE(ax.residual_foil, '')            = COALESCE(v_dec.residual_foil, '')
           AND COALESCE(ax.residual_subtype, '')         = COALESCE(v_dec.residual_subtype, '')
           AND COALESCE(ax.residual_stamp, '{}'::TEXT[]) = COALESCE(v_dec.residual_stamp, '{}'::TEXT[])
         ORDER BY r.id
    ) INTO v_blocked_ids;

    v_blocked := COALESCE(cardinality(v_blocked_ids), 0);
    v_touched := COALESCE(cardinality(v_row_ids), 0) + v_blocked;

    IF COALESCE(cardinality(v_row_ids), 0) = 0 THEN
        v_job_ids := ARRAY[]::UUID[];
    ELSE
        SELECT ARRAY(
            SELECT DISTINCT r.job_id FROM public.catalog_variant_import_row r
             WHERE r.id = ANY(v_row_ids) ORDER BY 1
        ) INTO v_job_ids;

        -- PASSO 3 — LOCKS, ordem determinística JOB -> ROW. INALTERADO.
        PERFORM 1 FROM public.catalog_variant_import_job j
          WHERE j.id = ANY(v_job_ids) ORDER BY j.id FOR UPDATE;

        PERFORM 1 FROM public.catalog_variant_import_row r
          WHERE r.id = ANY(v_row_ids) ORDER BY r.id FOR UPDATE;

        -- =====================================================
        -- PASSO 4 — PROPAGATION, AS TRÊS CHAVES NUMA OPERAÇÃO
        --
        -- Um único jsonb_set encadeado, um único UPDATE, uma única
        -- transação: os três eixos nunca ficam parcialmente gravados.
        -- Os dois eixos opcionais vêm do RESOLVEDOR, nunca são assumidos;
        -- JSON null explícito quando o contrato diz "resolvido SEM".
        -- Campos de decisão e persistência continuam intocados.
        -- =====================================================
        WITH alvo AS (
            SELECT r.id, r.job_id,
                   ax.printing_profile_id,
                   ax.edition_context_profile_id
              FROM public.catalog_variant_import_row r
              JOIN public.catalog_variant_import_job j ON j.id = r.job_id
              JOIN public.card_set  cs ON cs.id = j.card_set_id
              JOIN public.expansion e  ON e.id  = cs.expansion_id
              -- ESCOPO CANONICO (SOURCE-SCOPE-CORRECTION-01): mesmo criterio
              -- dos dois call sites acima. Sem este LEFT JOIN o argumento de
              -- escopo seria cs.code, que NUNCA casa com external_set_id.
              LEFT JOIN LATERAL internal.resolve_variant_mapping_scope(cs.id, v_src_id) sc ON TRUE
              CROSS JOIN LATERAL internal.resolve_variant_row_axes(
                  r.raw_data, e.game_id, v_src_id, sc.external_set_id) ax
             WHERE r.id = ANY(v_row_ids)
        ),
        atualizado AS (
            UPDATE public.catalog_variant_import_row r
               SET normalized_data =
                       jsonb_set(
                         jsonb_set(
                           jsonb_set(r.normalized_data,
                                     '{variant_type_id}',
                                     to_jsonb(p_variant_type_id::TEXT), true),
                           '{printing_profile_id}',
                           CASE WHEN a.printing_profile_id IS NULL
                                THEN 'null'::JSONB
                                ELSE to_jsonb(a.printing_profile_id::TEXT) END,
                           true),
                         '{edition_context_profile_id}',
                         CASE WHEN a.edition_context_profile_id IS NULL
                              THEN 'null'::JSONB
                              ELSE to_jsonb(a.edition_context_profile_id::TEXT) END,
                         true),
                   validation_status  = 'VALID',
                   match_status       = 'NEW',
                   matched_variant_id = NULL,
                   error_detail       = NULL
              FROM alvo a
             WHERE r.id = a.id
            RETURNING r.id, r.job_id
        )
        SELECT count(*), count(DISTINCT job_id) INTO v_reconciled, v_jobs FROM atualizado;

        -- GATE DE RECONCILIAÇÃO, reformulado: nada pode se perder ENTRE as
        -- duas partições. A soma tem de fechar com o universo medido.
        IF v_reconciled + v_blocked IS DISTINCT FROM v_touched THEN
            RAISE EXCEPTION 'APPLY_VARIANT_TYPE_MAPPING_RECONCILIATION_GAP: % linha(s) no universo A, % reconciliadas, % bloqueadas por Edition Context indeterminado.',
                v_touched, v_reconciled, v_blocked;
        END IF;

        -- PASSO 5 — COUNTERS, SOMENTE DOS JOBS AFETADOS. INALTERADO.
        UPDATE public.catalog_variant_import_job j
           SET total_rows = (SELECT count(*) FROM public.catalog_variant_import_row r
                              WHERE r.job_id = j.id),
               valid_rows = (SELECT count(*) FROM public.catalog_variant_import_row r
                              WHERE r.job_id = j.id AND r.validation_status = 'VALID')
         WHERE j.id = ANY(v_job_ids);
    END IF;

    v_valid   := v_reconciled;
    -- rows_still_pending deixa de ser sempre 0: carrega as linhas cujo
    -- residual casou mas cujo Edition Context segue indeterminado.
    v_pending := v_blocked;

    -- =========================================================
    -- PASSO 6 — AUDITORIA. Mesma action, mesma CHECK, sem widen.
    -- Metadata ganha o recorte novo — aditivo, nunca substitutivo.
    -- =========================================================
    INSERT INTO public.catalog_admin_action_log
        (actor_id, action, entity_type, entity_id, metadata)
    VALUES (
        p_actor_id,
        'CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED',
        'CARD_VARIANT_TYPE_EXTERNAL_MAPPING',
        v_mapping_id,
        jsonb_build_object(
            'scope_kind',                 p_scope_kind,
            'game_id',                    v_game_id,
            'asset_source_id',            v_src_id,
            'external_set_id',            v_scope,
            'variant_type_id',            p_variant_type_id,
            'residual_type',              v_dec.residual_type,
            'residual_foil',              v_dec.residual_foil,
            'residual_subtype',           v_dec.residual_subtype,
            'residual_stamp',             v_dec.residual_stamp,
            'signature_basis',            'RESIDUAL_POST_BOTH_AXES',
            'origin_row_id',              p_origin_row_id,
            'fallback_global_mapping_id',
                CASE WHEN v_dec.current_effective_scope = 'GLOBAL'
                     THEN v_dec.current_effective_mapping_id ELSE NULL END,
            'superseded_interpretation_variant_type_id',
                CASE WHEN v_dec.supersedes_interpretation
                     THEN v_dec.current_effective_variant_type_id ELSE NULL END,
            'rows_total',                 v_touched,
            'rows_reclassified',          v_reconciled,
            'rows_updated',               v_reconciled,
            'rows_blocked_edition_context', v_blocked,
            'jobs_affected',              v_jobs
        )
    );

    RETURN QUERY SELECT v_mapping_id, p_scope_kind, v_scope,
                        v_touched, v_reconciled, v_pending, v_jobs;
END;
$worker$;

COMMENT ON FUNCTION internal.apply_variant_type_mapping(UUID, UUID, UUID, TEXT) IS
    'Worker UNICO de criacao de mapping de Card Variant Type (GLOBAL ou SOURCE_SET) com propagation na MESMA transacao. v2.0: usa internal.resolve_variant_row_axes (residual POS-DOIS-EIXOS) e grava as TRES chaves de normalized_data numa unica operacao. Rows com residual casando mas Edition Context indeterminado NAO sao promovidas a VALID — contam em rows_still_pending. Fail-closed via internal.variant_type_mapping_impact(). Coexistencia: jamais faz UPDATE do mapping global.';

REVOKE ALL ON FUNCTION internal.apply_variant_type_mapping(UUID, UUID, UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION internal.apply_variant_type_mapping(UUID, UUID, UUID, TEXT) FROM anon, authenticated, service_role;

-- ---------------------------------------------------------------- POSTCHECK -
DO $$
DECLARE v_src TEXT; v_sec BOOLEAN; v_cfg TEXT[];
BEGIN
    SELECT p.prosrc, p.prosecdef, p.proconfig INTO v_src, v_sec, v_cfg
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='internal' AND p.proname='apply_variant_type_mapping';

    IF v_sec IS NOT TRUE THEN RAISE EXCEPTION 'APPLY_V2_NOT_SECDEF.'; END IF;
    IF NOT (v_cfg::TEXT LIKE '%search_path=%') THEN RAISE EXCEPTION 'APPLY_V2_NO_SEARCH_PATH.'; END IF;

    -- PROVA NEGATIVA: a chamada antiga nao sobrevive em lugar nenhum.
    IF v_src LIKE '%compute_variant_residual_signature%' THEN
        RAISE EXCEPTION 'APPLY_V2_STALE_ROUTING: ainda chama compute_variant_residual_signature. Todo consumidor de residual deve passar por resolve_variant_row_axes.';
    END IF;
    IF v_src NOT LIKE '%resolve_variant_row_axes%' THEN
        RAISE EXCEPTION 'APPLY_V2_NO_ROUTING: nao chama resolve_variant_row_axes.';
    END IF;
    -- As tres chaves na propagation.
    IF v_src NOT LIKE '%{edition_context_profile_id}%' THEN
        RAISE EXCEPTION 'APPLY_V2_NO_EC_KEY: propagation nao grava edition_context_profile_id.';
    END IF;
    -- Guarda contra promocao indevida.
    IF v_src NOT LIKE '%edition_context_state NOT IN%' THEN
        RAISE EXCEPTION 'APPLY_V2_NO_BLOCKED_PARTITION: universo A nao particiona por eixo indeterminado.';
    END IF;
    -- Locks preservados.
    IF v_src NOT LIKE '%ORDER BY j.id FOR UPDATE%' OR v_src NOT LIKE '%ORDER BY r.id FOR UPDATE%' THEN
        RAISE EXCEPTION 'APPLY_V2_LOCK_ORDER_LOST: ordem deterministica JOB->ROW removida.';
    END IF;

    RAISE NOTICE 'apply_variant_type_mapping v2.0 OK — 7/7 provas estruturais.';
END $$;

-- ============================================================================
-- PERFORMANCE
--   resolve_variant_row_axes é chamada uma vez por row por partição, via
--   CROSS JOIN LATERAL set-based — mesma forma da canônica, sem N+1 novo.
--   O custo adicional frente à v1.0 é a camada de Edition Context dentro da
--   própria 2211, que resolve por lookup indexado em
--   card_edition_context_external_mapping (uq_cecem_active_global /
--   uq_cecem_active_scoped, parciais em is_active — 2207 v3.0).
--   Nenhum lookup de trait individual: a assinatura vem do mapping.
--
-- ARMADO PARA ROLLOUT (ROLLOUT-EXECUTION-READINESS-01). Terminador COMMIT.
-- Corpo auditado PRESERVADO byte a byte; a unica alteracao de armamento foi
-- ROLLBACK; -> COMMIT;. A protecao contra execucao prematura e GOVERNANCA
-- (autorizacao de Fabricio + ordem de batches), nao o terminador — mesma
-- decisao ja aceita em R1 para 2203-2211.
-- ============================================================================
COMMIT;
