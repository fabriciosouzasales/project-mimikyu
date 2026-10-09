-- =============================================================================
-- Query NR-REMEASURE-01 — Remedição do resíduo NEEDS_REVIEW de Card Variants
-- STATUS: PROPOSTA — leitura apenas (um único SELECT; sem DML/DDL, sem função
--         interna, sem tabela temporária). Autorizada por Fabrício em 2026-10-09.
-- -----------------------------------------------------------------------------
-- Objetivo: medir o universo operacional atual do staging de variantes, com o
--   mesmo critério da 2212 (job vivo + persistence PENDING), e descrever o
--   resíduo NEEDS_REVIEW antes de desenhar a experiência editorial.
--   Baseline de 2026-09-18: 1.642 linhas NEEDS_REVIEW nos jobs vivos.
-- Seções (1 linha, 1 coluna jsonb):
--   universo    — contagem por validation_status / decision_status
--   jobs        — jobs vivos por status
--   eixos       — NEEDS_REVIEW por estado de cada eixo no normalized_data
--                 (acabamento resolvido? tiragem: ausente/null/uuid? EC: ausente/null/uuid?)
--   motivos     — top 25 error_detail (texto cortado em 120 caracteres)
--   sets        — NEEDS_REVIEW por Card Set (top 40) + nº de Sets
--   assinaturas — top 40 assinaturas brutas (raw_data sem ids) com nº de Sets
-- Resultado esperado: NEEDS_REVIEW <= 1.642 (nada deveria tê-las aumentado).
-- Como validar: soma de "sets" = total NEEDS_REVIEW de "universo".
-- =============================================================================
WITH op AS (
  SELECT r.id, r.job_id, r.card_id, r.raw_data, r.normalized_data, r.validation_status,
         r.decision_status, r.error_detail, j.card_set_id, j.status AS job_status
  FROM public.catalog_variant_import_row r
  JOIN public.catalog_variant_import_job j ON j.id = r.job_id
  WHERE j.status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING')
    AND r.persistence_status = 'PENDING'
),
nr AS (SELECT * FROM op WHERE validation_status = 'NEEDS_REVIEW'),
eixo AS (
  SELECT
    CASE WHEN jsonb_typeof(normalized_data->'variant_type_id') = 'string' THEN 'resolvido' ELSE 'nao_resolvido' END AS acabamento,
    CASE WHEN NOT (normalized_data ? 'printing_profile_id') THEN 'ausente'
         WHEN jsonb_typeof(normalized_data->'printing_profile_id') = 'null' THEN 'null'
         ELSE 'uuid' END AS tiragem,
    CASE WHEN NOT (normalized_data ? 'edition_context_profile_id') THEN 'ausente'
         WHEN jsonb_typeof(normalized_data->'edition_context_profile_id') = 'null' THEN 'null'
         ELSE 'uuid' END AS edition_context
  FROM nr
)
SELECT jsonb_build_object(
  'universo', (SELECT jsonb_object_agg(k, n) FROM (
      SELECT validation_status || '/' || decision_status AS k, count(*) AS n FROM op GROUP BY 1) t),
  'needs_review_total', (SELECT count(*) FROM nr),
  'jobs', (SELECT jsonb_object_agg(job_status, n) FROM (
      SELECT j.status AS job_status, count(*) AS n FROM public.catalog_variant_import_job j
      WHERE j.status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING') GROUP BY 1) t),
  'eixos', (SELECT jsonb_agg(jsonb_build_object('acabamento', acabamento, 'tiragem', tiragem,
                                                'edition_context', edition_context, 'n', n) ORDER BY n DESC)
            FROM (SELECT acabamento, tiragem, edition_context, count(*) AS n FROM eixo GROUP BY 1,2,3) t),
  'motivos', (SELECT jsonb_agg(jsonb_build_object('motivo', m, 'n', n) ORDER BY n DESC) FROM (
      SELECT left(coalesce(error_detail, '(sem error_detail)'), 120) AS m, count(*) AS n
      FROM nr GROUP BY 1 ORDER BY 2 DESC LIMIT 25) t),
  'sets_total', (SELECT count(DISTINCT card_set_id) FROM nr),
  'sets', (SELECT jsonb_agg(jsonb_build_object('set', code, 'n', n) ORDER BY n DESC, code) FROM (
      SELECT cs.code, count(*) AS n FROM nr JOIN public.card_set cs ON cs.id = nr.card_set_id
      GROUP BY cs.code ORDER BY 2 DESC, 1 LIMIT 40) t),
  'assinaturas_total', (SELECT count(DISTINCT raw_data - 'id' - 'card_id' - 'external_card_id') FROM nr),
  'assinaturas', (SELECT jsonb_agg(jsonb_build_object('raw', sig, 'n', n, 'sets', s) ORDER BY n DESC) FROM (
      SELECT raw_data - 'id' - 'card_id' - 'external_card_id' AS sig, count(*) AS n,
             count(DISTINCT card_set_id) AS s
      FROM nr GROUP BY 1 ORDER BY 2 DESC LIMIT 40) t)
) AS nr_remeasure;
