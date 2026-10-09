-- Query NR-REMEASURE-02 (v1.1: guarda de jsonb_typeof via CASE; a v1.0 falhou sem efeito por avaliar jsonb_array_length em escalar) — distribuição por atributo bruto (read-only, mesmo universo da 01)
-- Objetivo: completar a 01 (que só trouxe as 40 maiores assinaturas de 215) com a
--   distribuição por cada atributo da fonte: type, foil, subtype e cada valor de stamp.
WITH nr AS (
  SELECT r.raw_data, j.card_set_id
  FROM public.catalog_variant_import_row r
  JOIN public.catalog_variant_import_job j ON j.id = r.job_id
  WHERE j.status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING')
    AND r.persistence_status = 'PENDING' AND r.validation_status = 'NEEDS_REVIEW'
)
SELECT jsonb_build_object(
  'type', (SELECT jsonb_object_agg(coalesce(k,'(null)'), n) FROM (SELECT raw_data->>'type' k, count(*) n FROM nr GROUP BY 1) t),
  'foil', (SELECT jsonb_object_agg(coalesce(k,'(null)'), n) FROM (SELECT raw_data->>'foil' k, count(*) n FROM nr GROUP BY 1) t),
  'subtype', (SELECT jsonb_object_agg(coalesce(k,'(null)'), n) FROM (SELECT raw_data->>'subtype' k, count(*) n FROM nr GROUP BY 1) t),
  'size', (SELECT jsonb_object_agg(coalesce(k,'(null)'), n) FROM (SELECT raw_data->>'size' k, count(*) n FROM nr GROUP BY 1) t),
  'com_stamp', (SELECT count(*) FROM nr WHERE CASE WHEN jsonb_typeof(raw_data->'stamp') = 'array' THEN jsonb_array_length(raw_data->'stamp') > 0 ELSE false END),
  'stamp_multiplo', (SELECT count(*) FROM nr WHERE CASE WHEN jsonb_typeof(raw_data->'stamp') = 'array' THEN jsonb_array_length(raw_data->'stamp') > 1 ELSE false END),
  'stamp_valores', (SELECT jsonb_agg(jsonb_build_object('stamp', s, 'n', n, 'sets', c) ORDER BY n DESC, s) FROM (
      SELECT e AS s, count(*) n, count(DISTINCT card_set_id) c
      FROM nr, jsonb_array_elements_text(CASE WHEN jsonb_typeof(raw_data->'stamp')='array' THEN raw_data->'stamp' ELSE '[]'::jsonb END) e
      GROUP BY 1) t)
) AS nr_attr;
