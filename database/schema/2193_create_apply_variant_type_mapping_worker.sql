/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2193 - Create internal.apply_variant_type_mapping()
              (worker consolidado: mapping + propagation)
Versão......: 1.0
Status......: CANÔNICA — CONFIRMADO EXECUTADO / LIVE
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-14 (execução) · 2026-09-18 (promoção canônica)
Ledger......: 20260914024939 / 2193_create_apply_variant_type_mapping_worker
Promovida...: 2026-09-18, BULK-STP-01-CANONICAL-RECONCILIATION-IMPLEMENTATION-01

Descrição...:
Worker ÚNICO de criação de mapping de Card Variant Type, GLOBAL ou
SOURCE_SET_SCOPED, com propagação na MESMA transação. Os dois caminhos
públicos (Query 2150 v2.0) delegam aqui — não existe segunda
implementação da regra.

Esta é a forma que uma INSTALAÇÃO LIMPA deve executar. A cópia original
do ciclo permanece em database/proposals/2026-09-14-card-variant-mapping
-source-set-scope/ como evidência histórica, e a migration histórica em
database/migrations/.

Pré-requisitos:
- Query 2192 - Variant Type Mapping Scope Read Contract (v2.0).
- Query 2140 - Create card_variant_type_external_mapping Table (v2.0).
- Query 2138 - Create Catalog Variant Import Row Table (v2.0).

----------------------------------------------------------------
REVISION HISTORY
----------------------------------------------------------------
| 1.0 | **Criação do worker consolidado (2026-09-14, GATE-B-EXECUTION-01).**
        Corpo idêntico ao executado. Promovido a CANÔNICA em 2026-09-18
        sem alteração de corpo. |
================================================================
*/

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

    v_row_ids    UUID[];
    v_job_ids    UUID[];
    v_touched    INTEGER := 0;
    v_reconciled INTEGER := 0;
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
    --
    -- >>> ZERO LÓGICA DE PRÉ-CONDIÇÃO DUPLICADA AQUI. <<<
    --
    -- internal.variant_type_mapping_decision() (Query 2192) avalia
    -- TODAS as pré-condições e o impacto A/B/C e devolve
    -- ok/block_reason como DADO. O PREVIEW (Query 2194) devolve
    -- exatamente este mesmo retorno.
    --
    -- O worker não reimplementa nenhuma verificação: apenas
    -- converte `ok = FALSE` em exceção — e faz isso ANTES de
    -- qualquer escrita. É por construção impossível o preview
    -- dizer "pode aplicar" e o execute abortar por regra de
    -- negócio, ou vice-versa.
    -- =========================================================
    SELECT * INTO v_dec
      FROM internal.variant_type_mapping_decision(
               p_origin_row_id, p_variant_type_id, p_scope_kind);

    IF NOT v_dec.ok THEN
        -- Mensagens dos dois motivos herdados da Query 2150 são
        -- reproduzidas LITERALMENTE, para que clientes atuais que
        -- casem por texto continuem funcionando.
        IF v_dec.block_reason = 'ORIGIN_NOT_NEEDS_REVIEW' THEN
            RAISE EXCEPTION 'ADMIN_RESOLVE_CATALOG_VARIANT_IMPORT_MAPPING_NOT_NEEDS_REVIEW: so linhas sem mapeamento (NEEDS_REVIEW) podem ser resolvidas por aqui.';
        ELSIF v_dec.block_reason = 'DUPLICATE_GLOBAL' THEN
            RAISE EXCEPTION 'ADMIN_RESOLVE_CATALOG_VARIANT_IMPORT_MAPPING_DUPLICATE: ja existe um mapeamento para esta combinacao residual nesta Fonte/Game.';
        ELSIF v_dec.block_reason = 'SCOPE_MISMATCH' THEN
            -- Não é caso de reconciliação editorial: é dado de
            -- operação corrompido. Erro próprio, para não ser
            -- confundido com identidade materializada.
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
    -- PASSO 1 — CRIAR O MAPPING (COEXISTÊNCIA, NUNCA UPDATE)
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
    -- PASSO 2 — UNIVERSO CLASSE A (o mesmo do impact)
    -- =========================================================
    SELECT ARRAY(
        SELECT r.id
          FROM public.catalog_variant_import_row r
          JOIN public.catalog_variant_import_job j ON j.id = r.job_id
          JOIN public.card_set  cs ON cs.id = j.card_set_id
          JOIN public.expansion e  ON e.id  = cs.expansion_id
          LEFT JOIN LATERAL internal.resolve_variant_mapping_scope(cs.id, v_src_id) sc ON TRUE
          CROSS JOIN LATERAL internal.compute_variant_residual_signature(
              r.raw_data, e.game_id, v_src_id) sg
         WHERE j.source  = v_job_source
           AND e.game_id = v_game_id
           AND (v_scope IS NULL OR sc.external_set_id = v_scope)
           AND j.status              = 'STAGED'
           AND r.decision_status     = 'PENDING'
           AND r.persistence_status  = 'PENDING'
           AND r.resulting_variant_id IS NULL
           AND sg.printing_state IN ('RESOLVED_NO_PRINTING', 'RESOLVED_WITH_PROFILE')
           AND sg.residual_type = v_dec.residual_type
           AND COALESCE(sg.residual_foil, '')            = COALESCE(v_dec.residual_foil, '')
           AND COALESCE(sg.residual_subtype, '')         = COALESCE(v_dec.residual_subtype, '')
           AND COALESCE(sg.residual_stamp, '{}'::TEXT[]) = COALESCE(v_dec.residual_stamp, '{}'::TEXT[])
         ORDER BY r.id
    ) INTO v_row_ids;

    v_touched := COALESCE(cardinality(v_row_ids), 0);

    IF v_touched = 0 THEN
        v_job_ids := ARRAY[]::UUID[];
    ELSE
        SELECT ARRAY(
            SELECT DISTINCT r.job_id FROM public.catalog_variant_import_row r
             WHERE r.id = ANY(v_row_ids) ORDER BY 1
        ) INTO v_job_ids;

        -- PASSO 3 — LOCKS, ordem determinística JOB -> ROW.
        PERFORM 1 FROM public.catalog_variant_import_job j
          WHERE j.id = ANY(v_job_ids) ORDER BY j.id FOR UPDATE;

        PERFORM 1 FROM public.catalog_variant_import_row r
          WHERE r.id = ANY(v_row_ids) ORDER BY r.id FOR UPDATE;

        -- PASSO 4 — PROPAGATION
        --
        -- Aceita VALID -> VALID (com variant_type diferente) e
        -- NEEDS_REVIEW -> VALID. printing_profile_id vem do
        -- resolvedor, nunca é assumido. Campos de decisão e
        -- persistência NÃO são tocados: as linhas de A já estão
        -- PENDING/PENDING com resulting_variant_id NULL.
        WITH alvo AS (
            SELECT r.id, r.job_id, sg.printing_profile_id
              FROM public.catalog_variant_import_row r
              JOIN public.catalog_variant_import_job j ON j.id = r.job_id
              JOIN public.card_set  cs ON cs.id = j.card_set_id
              JOIN public.expansion e  ON e.id  = cs.expansion_id
              CROSS JOIN LATERAL internal.compute_variant_residual_signature(
                  r.raw_data, e.game_id, v_src_id) sg
             WHERE r.id = ANY(v_row_ids)
        ),
        atualizado AS (
            UPDATE public.catalog_variant_import_row r
               SET normalized_data =
                       jsonb_set(
                           jsonb_set(r.normalized_data,
                                     '{variant_type_id}',
                                     to_jsonb(p_variant_type_id::TEXT), true),
                           '{printing_profile_id}',
                           CASE WHEN a.printing_profile_id IS NULL
                                THEN 'null'::JSONB
                                ELSE to_jsonb(a.printing_profile_id::TEXT) END,
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

        IF v_reconciled IS DISTINCT FROM v_touched THEN
            RAISE EXCEPTION 'APPLY_VARIANT_TYPE_MAPPING_RECONCILIATION_GAP: % linha(s) no universo A, % reconciliadas.',
                v_touched, v_reconciled;
        END IF;

        -- PASSO 5 — COUNTERS, SOMENTE DOS JOBS AFETADOS
        UPDATE public.catalog_variant_import_job j
           SET total_rows = (SELECT count(*) FROM public.catalog_variant_import_row r
                              WHERE r.job_id = j.id),
               valid_rows = (SELECT count(*) FROM public.catalog_variant_import_row r
                              WHERE r.job_id = j.id AND r.validation_status = 'VALID')
         WHERE j.id = ANY(v_job_ids);
    END IF;

    v_valid   := v_reconciled;    -- toda linha de A termina VALID
    v_pending := v_touched - v_reconciled;

    -- =========================================================
    -- PASSO 6 — AUDITORIA
    --
    -- REUTILIZA o par já válido na CHECK. Sem widen, sem action
    -- nova (decisão 9). O escopo vive na metadata.
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
            'signature_basis',            'RESIDUAL',
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
            'jobs_affected',              v_jobs
        )
    );

    RETURN QUERY SELECT v_mapping_id, p_scope_kind, v_scope,
                        v_touched, v_reconciled, v_pending, v_jobs;
END;
$worker$;

COMMENT ON FUNCTION internal.apply_variant_type_mapping(UUID, UUID, UUID, TEXT) IS
    'Worker UNICO de criacao de mapping de Card Variant Type (GLOBAL ou SOURCE_SET) com propagation na MESMA transacao. Fail-closed via internal.variant_type_mapping_impact(). Coexistencia: jamais faz UPDATE do mapping global. Reutiliza a action CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED.';

REVOKE ALL ON FUNCTION internal.apply_variant_type_mapping(UUID, UUID, UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION internal.apply_variant_type_mapping(UUID, UUID, UUID, TEXT) FROM anon, authenticated, service_role;

COMMIT;

-- ================================================================
-- CONFIRMADO EXECUTADO / LIVE — ver a migration histórica correspondente
-- em database/migrations/ e o ledger supabase_migrations.schema_migrations.
--
-- Esta Query CANÔNICA foi promovida em 2026-09-18
-- (BULK-STP-01-CANONICAL-RECONCILIATION-IMPLEMENTATION-01) a partir do
-- corpo comprovadamente equivalente ao LIVE. NÃO foi reexecutada contra o
-- Supabase: promoção canônica é alteração de arquivo, não execução.
-- ================================================================
