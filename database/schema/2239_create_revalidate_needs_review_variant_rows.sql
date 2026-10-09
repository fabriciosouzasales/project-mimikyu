/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2239 - internal.revalidate_needs_review_variant_rows()
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO / LIVE — 2026-10-09, via apply_migration (MCP Supabase),
              projeto qjfutqujxrbzgrtkpgkg. Ledger: 20261009232048 / 2239_create_revalidate_needs_review_variant_rows
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-09
Mandato.....: NEEDS-REVIEW-REVALIDATION-01
Pré-req.....: 2238 (action de auditoria), 2211 (resolve_variant_row_axes),
              2192/2220 (lookup_variant_type_for_row), 2214 (guard VALID exige
              chave de Edition Context), 2210 (uq_cvir_row_identity).

-------------------------------------------------------------------------------
PROBLEMA (medido — NR-DRYRUN-01, 2026-10-09)
-------------------------------------------------------------------------------
Das 1.642 linhas NEEDS_REVIEW do staging de Card Variant, 1.086 já se resolvem
nos três eixos com o vocabulário vigente. Elas só continuam NEEDS_REVIEW porque
o único caminho de reavaliação existente (worker 2219) é disparado pela
CRIAÇÃO de um mapping de acabamento; as seeds de Edition Context (2230–2232)
mudaram o residual dessas linhas sem nenhuma reavaliação posterior.

-------------------------------------------------------------------------------
O QUE ESTA FUNÇÃO FAZ
-------------------------------------------------------------------------------
Reavalia, com o MESMO contrato do worker 2219, as linhas:
    job STAGED · validation NEEDS_REVIEW · decision PENDING ·
    persistence PENDING · resulting_variant_id NULL ·
    sem marcador review_reason / skip_reason
e promove a VALID somente as que:
    Printing terminal  (RESOLVED_NO_PRINTING | RESOLVED_WITH_PROFILE)
    Edition Context terminal (RESOLVED_NO_EDITION_CONTEXT | RESOLVED_WITH_EC_PROFILE)
    acabamento encontrado por internal.lookup_variant_type_for_row()
gravando as TRÊS chaves de normalized_data numa única operação (idêntico à
PASSO 4 da 2219). Decisão e persistência NÃO são tocadas: a linha vira
VALID / PENDING / PENDING e segue o fluxo normal (decide 2144 → confirm 2145).

NÃO cria mapping, perfil, trait ou Card Variant. NÃO toca linha já VALID.

-------------------------------------------------------------------------------
HOLDS — EXCLUSÃO EXPLÍCITA (HOLD-MANIFEST)
-------------------------------------------------------------------------------
  H2  stamp SET-LOGO em Card Sets EX7, EX8, EX9, EX10        -> nunca promovida
  H3  foil LEAGUE | PLAYER-REWARD | PROFESSOR-PROGRAM        -> nunca promovida
      (o NR-DRYRUN-01 mostrou 1 linha de H3 que resolveria sozinha como
       STANDARDS_LEAGUE; B3 é decisão editorial pendente e não pode ser
       tomada por reavaliação)
As exclusões são contadas e devolvidas no resultado.

-------------------------------------------------------------------------------
SEGURANÇA, INTEGRIDADE E IDEMPOTÊNCIA
-------------------------------------------------------------------------------
- p_actor_id obrigatório e precisa ser admin_user (mesmo GUARD 1 da 2219).
- SECURITY DEFINER, search_path = '', EXECUTE revogado de PUBLIC, anon,
  authenticated e service_role. Só o owner executa (SQL Editor / futura RPC
  admin com is_admin(), em mandato próprio).
- MODO PADRÃO = DRY-RUN (p_apply = false): calcula o plano, não escreve nada.
- APLICAR exige p_expected_rows = tamanho do plano medido no dry-run. Se o
  universo mudou entre as duas chamadas, aborta sem escrever (pin).
- Locks em ordem determinística JOB -> ROW antes de recalcular o plano.
- Colisão de identidade de staging (uq_cvir_row_identity) é detectada ANTES
  da escrita, contra o próprio plano e contra as linhas já identificadas do
  mesmo job. Havendo colisão, APPLY aborta; o dry-run apenas reporta.
- Gate pós-escrita: linhas atualizadas == plano. Senão, RAISE (rollback).
- Idempotente: após aplicar, o universo elegível fica vazio; reexecutar
  devolve plano 0 e não escreve nem audita.
- Auditoria: 1 linha por job afetado em catalog_admin_action_log
  (CATALOG_VARIANT_IMPORT_JOB / CARD_VARIANT_IMPORT_ROWS_REVALIDATED), com
  run_id comum, contagens e distribuição por acabamento.
- Counters total_rows/valid_rows recalculados só dos jobs afetados (igual 2219).
===============================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION internal.revalidate_needs_review_variant_rows(
    p_actor_id      UUID,
    p_apply         BOOLEAN DEFAULT false,
    p_expected_rows INTEGER DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
    v_src_id     UUID;
    v_run_id     UUID := gen_random_uuid();
    v_job_ids    UUID[];
    v_plan       INTEGER := 0;
    v_conflicts  INTEGER := 0;
    v_updated    INTEGER := 0;
    v_jobs       INTEGER := 0;
    v_universe   INTEGER := 0;
    v_hold_h2    INTEGER := 0;
    v_hold_h3    INTEGER := 0;
    v_not_ready  INTEGER := 0;
    v_by_type    JSONB;
    v_plan_j     JSONB;
BEGIN
    -- GUARD 1 — ator
    IF p_actor_id IS NULL THEN
        RAISE EXCEPTION 'REVALIDATE_NR_MISSING_ACTOR: p_actor_id e obrigatorio.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.admin_user a WHERE a.id = p_actor_id) THEN
        RAISE EXCEPTION 'REVALIDATE_NR_ACTOR_NOT_ADMIN: p_actor_id (%) nao e administrador cadastrado.', p_actor_id;
    END IF;
    IF p_apply AND p_expected_rows IS NULL THEN
        RAISE EXCEPTION 'REVALIDATE_NR_EXPECTED_REQUIRED: aplicar exige p_expected_rows (tamanho do plano medido no dry-run).';
    END IF;

    SELECT s.id INTO v_src_id FROM public.asset_source s WHERE s.code = 'TCGDEX';
    IF v_src_id IS NULL THEN
        RAISE EXCEPTION 'REVALIDATE_NR_SOURCE_NOT_FOUND: asset_source TCGDEX ausente.';
    END IF;

    -- LOCKS (só no apply), ordem determinística JOB -> ROW, antes do plano.
    IF p_apply THEN
        PERFORM 1 FROM public.catalog_variant_import_job j
          WHERE j.status = 'STAGED'
            AND EXISTS (SELECT 1 FROM public.catalog_variant_import_row r
                         WHERE r.job_id = j.id AND r.validation_status = 'NEEDS_REVIEW'
                           AND r.persistence_status = 'PENDING')
          ORDER BY j.id FOR UPDATE;
        PERFORM 1 FROM public.catalog_variant_import_row r
          JOIN public.catalog_variant_import_job j ON j.id = r.job_id
          WHERE j.status = 'STAGED' AND r.validation_status = 'NEEDS_REVIEW'
            AND r.persistence_status = 'PENDING'
          ORDER BY r.id FOR UPDATE OF r;
    END IF;

    -- PLANO — recalculado depois dos locks. Sem TEMP TABLE (precedente 5079):
    -- o plano vive num JSONB local e é relido com jsonb_to_recordset.
    WITH base AS (
        SELECT r.id AS row_id, r.job_id, r.card_id, cs.code AS set_code,
               CASE
                 WHEN cs.code IN ('EX7','EX8','EX9','EX10')
                      AND EXISTS (SELECT 1 FROM jsonb_array_elements_text(
                                     CASE jsonb_typeof(r.raw_data->'stamp')
                                          WHEN 'array'  THEN r.raw_data->'stamp'
                                          WHEN 'string' THEN jsonb_build_array(r.raw_data->>'stamp')
                                          ELSE '[]'::jsonb END) st
                                   WHERE public.normalize_external_catalog_value(st) = 'SET-LOGO')
                   THEN 'H2'
                 WHEN public.normalize_external_catalog_value(r.raw_data->>'foil')
                      IN ('LEAGUE','PLAYER-REWARD','PROFESSOR-PROGRAM')
                   THEN 'H3'
               END AS hold,
               CASE
                 WHEN ax.printing_state IN ('RESOLVED_NO_PRINTING','RESOLVED_WITH_PROFILE')
                  AND ax.edition_context_state IN ('RESOLVED_NO_EDITION_CONTEXT','RESOLVED_WITH_EC_PROFILE')
                 THEN internal.lookup_variant_type_for_row(e.game_id, v_src_id, cs.id,
                        ax.residual_type, ax.residual_foil, ax.residual_subtype,
                        COALESCE(ax.residual_stamp, '{}'::TEXT[]))
               END AS variant_type_id,
               ax.printing_profile_id,
               ax.edition_context_profile_id
          FROM public.catalog_variant_import_row r
          JOIN public.catalog_variant_import_job j ON j.id = r.job_id
          JOIN public.card_set  cs ON cs.id = j.card_set_id
          JOIN public.expansion e  ON e.id  = cs.expansion_id
          LEFT JOIN LATERAL internal.resolve_variant_mapping_scope(cs.id, v_src_id) sc ON TRUE
          CROSS JOIN LATERAL internal.resolve_variant_row_axes(r.raw_data, e.game_id, v_src_id, sc.external_set_id) ax
         WHERE j.status = 'STAGED'
           AND r.validation_status  = 'NEEDS_REVIEW'
           AND r.decision_status    = 'PENDING'
           AND r.persistence_status = 'PENDING'
           AND r.resulting_variant_id IS NULL
           AND NOT (r.normalized_data ? 'review_reason')
           AND NOT (r.normalized_data ? 'skip_reason')
    )
    SELECT coalesce(jsonb_agg(to_jsonb(b) || jsonb_build_object(
               'eligible', (b.variant_type_id IS NOT NULL AND b.hold IS NULL))
             ORDER BY b.row_id), '[]'::jsonb)
      INTO v_plan_j
      FROM base b;

    SELECT count(*),
           count(*) FILTER (WHERE eligible),
           count(*) FILTER (WHERE hold = 'H2'),
           count(*) FILTER (WHERE hold = 'H3'),
           count(*) FILTER (WHERE NOT eligible AND hold IS NULL)
      INTO v_universe, v_plan, v_hold_h2, v_hold_h3, v_not_ready
      FROM jsonb_to_recordset(v_plan_j) AS p(row_id UUID, hold TEXT, eligible BOOLEAN);

    -- COLISÃO DE IDENTIDADE (uq_cvir_row_identity), antes de escrever.
    WITH pl AS (
        SELECT * FROM jsonb_to_recordset(v_plan_j) AS p(
            row_id UUID, job_id UUID, card_id UUID, variant_type_id UUID,
            printing_profile_id UUID, edition_context_profile_id UUID, eligible BOOLEAN)
         WHERE eligible
    ),
    k AS (
        SELECT p.job_id, p.card_id, p.variant_type_id::TEXT AS vt,
               CASE WHEN p.printing_profile_id IS NULL THEN 'N' ELSE 'U:' || p.printing_profile_id END AS pp,
               CASE WHEN p.edition_context_profile_id IS NULL THEN 'N' ELSE 'U:' || p.edition_context_profile_id END AS ec,
               true AS is_plan
          FROM pl p
        UNION ALL
        SELECT r.job_id, r.card_id, r.normalized_data->>'variant_type_id',
               internal.axis_identity_token(r.normalized_data, 'printing_profile_id'),
               internal.axis_identity_token(r.normalized_data, 'edition_context_profile_id'),
               false
          FROM public.catalog_variant_import_row r
         WHERE r.job_id IN (SELECT job_id FROM pl)
           AND r.normalized_data->>'variant_type_id' IS NOT NULL
           AND r.id NOT IN (SELECT row_id FROM pl)
    )
    SELECT coalesce(sum(n) FILTER (WHERE n > 1 AND has_plan), 0) INTO v_conflicts
      FROM (SELECT count(*) AS n, bool_or(is_plan) AS has_plan
              FROM k GROUP BY job_id, card_id, vt, pp, ec) g;

    SELECT coalesce(jsonb_object_agg(code, n), '{}'::jsonb) INTO v_by_type
      FROM (SELECT vt.code, count(*) AS n
              FROM jsonb_to_recordset(v_plan_j) AS p(variant_type_id UUID, eligible BOOLEAN)
              JOIN public.card_variant_type vt ON vt.id = p.variant_type_id
             WHERE p.eligible GROUP BY vt.code) t;

    IF NOT p_apply THEN
        RETURN jsonb_build_object(
            'mode', 'DRY_RUN', 'run_id', v_run_id,
            'universe_needs_review', v_universe, 'plan_rows', v_plan,
            'excluded_hold_h2', v_hold_h2, 'excluded_hold_h3', v_hold_h3,
            'not_resolvable_yet', v_not_ready, 'identity_conflicts', v_conflicts,
            'plan_by_variant_type', v_by_type,
            'jobs_in_plan', (SELECT count(DISTINCT job_id)
                               FROM jsonb_to_recordset(v_plan_j) AS p(job_id UUID, eligible BOOLEAN)
                              WHERE eligible));
    END IF;

    -- APPLY — pins e gates.
    IF v_plan IS DISTINCT FROM p_expected_rows THEN
        RAISE EXCEPTION 'REVALIDATE_NR_PLAN_DRIFT: plano atual = % linha(s), esperado = %. Nada foi escrito. Refazer o dry-run.', v_plan, p_expected_rows;
    END IF;
    IF v_conflicts > 0 THEN
        RAISE EXCEPTION 'REVALIDATE_NR_IDENTITY_CONFLICT: % linha(s) colidiriam em uq_cvir_row_identity. Nada foi escrito.', v_conflicts;
    END IF;
    IF v_plan = 0 THEN
        RETURN jsonb_build_object('mode', 'APPLY', 'run_id', v_run_id, 'rows_revalidated', 0,
                                  'jobs_affected', 0, 'note', 'plano vazio — nada a fazer (idempotente)');
    END IF;

    -- PROPAGATION — as três chaves numa única operação (contrato da 2219).
    WITH upd AS (
        UPDATE public.catalog_variant_import_row r
           SET normalized_data =
                   jsonb_set(
                     jsonb_set(
                       jsonb_set(r.normalized_data, '{variant_type_id}',
                                 to_jsonb(p.variant_type_id::TEXT), true),
                       '{printing_profile_id}',
                       CASE WHEN p.printing_profile_id IS NULL THEN 'null'::JSONB
                            ELSE to_jsonb(p.printing_profile_id::TEXT) END, true),
                     '{edition_context_profile_id}',
                     CASE WHEN p.edition_context_profile_id IS NULL THEN 'null'::JSONB
                          ELSE to_jsonb(p.edition_context_profile_id::TEXT) END, true),
               validation_status  = 'VALID',
               match_status       = 'NEW',
               matched_variant_id = NULL,
               error_detail       = NULL
          FROM jsonb_to_recordset(v_plan_j) AS p(
                   row_id UUID, variant_type_id UUID, printing_profile_id UUID,
                   edition_context_profile_id UUID, eligible BOOLEAN)
         WHERE p.row_id = r.id AND p.eligible
           AND r.validation_status = 'NEEDS_REVIEW'
        RETURNING r.id, r.job_id
    )
    SELECT count(*), count(DISTINCT job_id), array_agg(DISTINCT job_id)
      INTO v_updated, v_jobs, v_job_ids FROM upd;

    IF v_updated IS DISTINCT FROM v_plan THEN
        RAISE EXCEPTION 'REVALIDATE_NR_RECONCILIATION_GAP: plano %, atualizadas %.', v_plan, v_updated;
    END IF;

    -- COUNTERS — só dos jobs afetados (igual 2219).
    UPDATE public.catalog_variant_import_job j
       SET total_rows = (SELECT count(*) FROM public.catalog_variant_import_row r WHERE r.job_id = j.id),
           valid_rows = (SELECT count(*) FROM public.catalog_variant_import_row r
                          WHERE r.job_id = j.id AND r.validation_status = 'VALID')
     WHERE j.id = ANY (v_job_ids);

    -- AUDITORIA — 1 linha por job.
    INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
    SELECT p_actor_id, 'CARD_VARIANT_IMPORT_ROWS_REVALIDATED', 'CATALOG_VARIANT_IMPORT_JOB', p.job_id,
           jsonb_build_object(
               'run_id', v_run_id,
               'mandate', 'NEEDS-REVIEW-REVALIDATION-01',
               'reason', 'reavaliacao apos seeds de Edition Context (2230-2232)',
               'signature_basis', 'RESIDUAL_POST_BOTH_AXES',
               'card_set_code', min(p.set_code),
               'rows_revalidated', count(*),
               'by_variant_type', (SELECT jsonb_object_agg(code, n) FROM (
                    SELECT vt.code, count(*) AS n
                      FROM jsonb_to_recordset(v_plan_j) AS q(job_id UUID, variant_type_id UUID, eligible BOOLEAN)
                      JOIN public.card_variant_type vt ON vt.id = q.variant_type_id
                     WHERE q.eligible AND q.job_id = p.job_id GROUP BY vt.code) t),
               'run_totals', jsonb_build_object('rows', v_plan, 'jobs', v_jobs,
                    'excluded_hold_h2', v_hold_h2, 'excluded_hold_h3', v_hold_h3))
      FROM jsonb_to_recordset(v_plan_j) AS p(job_id UUID, set_code TEXT, eligible BOOLEAN)
     WHERE p.eligible
     GROUP BY p.job_id;

    RETURN jsonb_build_object(
        'mode', 'APPLY', 'run_id', v_run_id,
        'rows_revalidated', v_updated, 'jobs_affected', v_jobs,
        'excluded_hold_h2', v_hold_h2, 'excluded_hold_h3', v_hold_h3,
        'not_resolvable_yet', v_not_ready, 'by_variant_type', v_by_type);
END;
$fn$;

COMMENT ON FUNCTION internal.revalidate_needs_review_variant_rows(UUID, BOOLEAN, INTEGER) IS
    'NEEDS-REVIEW-REVALIDATION-01 (Query 2239). Reavalia linhas NEEDS_REVIEW de jobs STAGED com o vocabulario vigente (resolve_variant_row_axes + lookup_variant_type_for_row, mesmo contrato do worker 2219) e promove a VALID apenas as resolvidas nos tres eixos. Exclui HOLD H2 (SET-LOGO EX7-EX10) e H3 (foil LEAGUE/PLAYER-REWARD/PROFESSOR-PROGRAM). Padrao = dry-run; apply exige p_expected_rows igual ao plano. Detecta colisao de uq_cvir_row_identity antes de escrever. Idempotente. Audita CARD_VARIANT_IMPORT_ROWS_REVALIDATED por job. Nao cria mapping, perfil nem Card Variant.';

REVOKE ALL ON FUNCTION internal.revalidate_needs_review_variant_rows(UUID, BOOLEAN, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION internal.revalidate_needs_review_variant_rows(UUID, BOOLEAN, INTEGER) FROM anon, authenticated, service_role;

COMMIT;

-- ============================================================================
-- Resultado esperado: 1 função criada, SECURITY DEFINER, search_path='',
-- EXECUTE só do owner.
-- Como validar:
SELECT p.prosecdef, p.proconfig,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_exec,
       has_function_privilege('anon', p.oid, 'EXECUTE')          AS anon_exec,
       has_function_privilege('service_role', p.oid, 'EXECUTE')  AS service_exec
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'internal' AND p.proname = 'revalidate_needs_review_variant_rows';
-- Esperado: 1 linha · prosecdef true · {search_path=""} · false / false / false.
-- ============================================================================
