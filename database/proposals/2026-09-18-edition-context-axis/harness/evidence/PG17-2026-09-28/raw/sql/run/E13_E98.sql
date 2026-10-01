-- ============================================================================
-- 2830H · E98 — POSTCHECK DE RESÍDUO ESTENDIDO (game, datas de criação, marcador nos campos de fixture)
-- ============================================================================
-- Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO. Somente SELECT, um statement.
-- Uso ........... statement SEPARADO, logo DEPOIS do E99 (S6b), nos lotes que escrevem
--                 fora das 3 tabelas EC: L5 (game), L6 (card_variant), L7/L11/L12
--                 (job/row). Opcional nos demais (sem efeito se nada foi escrito).
--
-- ANTES DE RODAR, o operador substitui EXATAMENTE DOIS marcadores, copiando da
-- saída registrada do precheck DO LOTE da MESMA RODADA (colar, nunca redigitar):
--   __XP_D_XBASELINE__      ← o valor integral de d_xbaseline (JSON)
--   __XP_D_XBASELINE_MD5__  ← o valor de d_xbaseline_md5
-- Marcador não substituído, JSON truncado ou alterado ⇒ gate falso.
--
-- O md5 prova FIDELIDADE DA CÓPIA, não a origem da rodada; a vinculação
-- precheck → envelope → E99 → E98 é documental, como no E99.
--
-- Gates: g_captured_present · g_captured_integrity · g_keys_identical ·
--        g_xbaseline_equal (todas as chaves, uma a uma; d_diff) · g_xmarker_absent.
-- ============================================================================
WITH
captured_raw AS (
    SELECT '{"game": 2, "marker_job": 0, "marker_game": 0, "cv_max_upd_utc": "2026-09-19T00:48:41.964146Z", "game_max_upd_utc": "2026-07-26T18:32:18.887225Z", "marker_trait_name": 0, "cv_max_created_utc": "2026-09-19T00:48:41.964146Z", "marker_mapping_set": 0, "job_max_created_utc": "2026-09-18T20:49:03.726273Z", "marker_profile_name": 0, "cvir_max_created_utc": "2026-09-18T20:49:05.392832Z"}'::text     AS x_text,
           'fd61200beba5eefea1efd4e7d94949f8'::text AS x_md5
),
captured AS (
    SELECT CASE WHEN x_text LIKE '\_\_XP%' THEN NULL ELSE x_text::jsonb END AS c,
           CASE WHEN x_md5  LIKE '\_\_XP%' THEN NULL ELSE x_md5 END        AS md5_declared
      FROM captured_raw
),
xbase AS (
    -- XBASELINE-BUILDER:BEGIN
    SELECT jsonb_build_object(
        'game',                 (SELECT count(*) FROM public.game),
        'game_max_upd_utc',     (SELECT to_char(max(updated_at) AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') FROM public.game),
        'cv_max_created_utc',   (SELECT to_char(max(created_at) AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') FROM public.card_variant),
        'cv_max_upd_utc',       (SELECT to_char(max(updated_at) AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') FROM public.card_variant),
        'job_max_created_utc',  (SELECT to_char(max(created_at) AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') FROM public.catalog_variant_import_job),
        'cvir_max_created_utc', (SELECT to_char(max(created_at) AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') FROM public.catalog_variant_import_row),
        'marker_game',          (SELECT count(*) FROM public.game WHERE strpos(code, 'H2830') > 0 OR strpos(name, 'H2830') > 0),
        'marker_job',           (SELECT count(*) FROM public.catalog_variant_import_job WHERE strpos(external_set_id, 'H2830') > 0),
        'marker_trait_name',    (SELECT count(*) FROM public.card_edition_context_trait WHERE strpos(name, 'H2830') > 0),
        'marker_profile_name',  (SELECT count(*) FROM public.card_edition_context_profile WHERE strpos(name, 'H2830') > 0),
        'marker_mapping_set',   (SELECT count(*) FROM public.card_edition_context_external_mapping WHERE strpos(COALESCE(external_set_id, ''), 'H2830') > 0)
    ) AS x
    -- XBASELINE-BUILDER:END
),
diff AS (
    SELECT k AS key, captured.c -> k AS captured, xbase.x -> k AS now
      FROM captured, xbase, jsonb_object_keys(xbase.x) AS k
     WHERE captured.c IS NOT NULL AND (captured.c -> k) IS DISTINCT FROM (xbase.x -> k)
),
gates AS (
    SELECT
        ((SELECT c FROM captured) IS NOT NULL AND (SELECT md5_declared FROM captured) IS NOT NULL) AS g_captured_present,
        (SELECT md5(c::text) = md5_declared FROM captured)                                         AS g_captured_integrity,
        ((SELECT array_agg(k ORDER BY k) FROM captured, jsonb_object_keys(captured.c) AS k)
          = (SELECT array_agg(k ORDER BY k) FROM xbase, jsonb_object_keys(xbase.x) AS k))          AS g_keys_identical,
        ((SELECT c FROM captured) IS NOT NULL AND NOT EXISTS (SELECT 1 FROM diff))                  AS g_xbaseline_equal,
        ((SELECT x->>'marker_game' FROM xbase)::int = 0 AND (SELECT x->>'marker_job' FROM xbase)::int = 0
         AND (SELECT x->>'marker_trait_name' FROM xbase)::int = 0 AND (SELECT x->>'marker_profile_name' FROM xbase)::int = 0
         AND (SELECT x->>'marker_mapping_set' FROM xbase)::int = 0)                  AS g_xmarker_absent_now
)
SELECT to_jsonb(g)
    || jsonb_build_object(
        'gate_pass', (SELECT bool_and(v::boolean) FROM jsonb_each_text(to_jsonb(g)) AS e(k, v))
                     AND NOT EXISTS (SELECT 1 FROM jsonb_each_text(to_jsonb(g)) AS e(k, v) WHERE v IS NULL),
        'd_diff',             COALESCE((SELECT jsonb_agg(to_jsonb(d) ORDER BY d.key) FROM diff d), '[]'::jsonb),
        'd_xbaseline_now',    (SELECT x FROM xbase),
        'd_xbaseline_now_md5',(SELECT md5(x::text) FROM xbase),
        'd_session', jsonb_build_object('backend_pid', pg_backend_pid(), 'checked_at', clock_timestamp())
    ) AS e98_postcheck
  FROM gates g;
