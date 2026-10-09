-- =============================================================================
-- Query NR-DRYRUN-01 — O que as 1.642 NEEDS_REVIEW precisam de verdade?
-- STATUS: PROPOSTA — leitura apenas. Um único SELECT; chama só funções STABLE
--         já existentes (2211, 2192, resolve_variant_mapping_scope); sem DML,
--         DDL, DO, TEMP, CALL. Aguarda autorização de Fabrício.
-- -----------------------------------------------------------------------------
-- Objetivo: reavaliar cada linha NEEDS_REVIEW com o vocabulário ATUAL (eixos
--   Printing + Edition Context + mapping de acabamento), exatamente como o
--   worker 2219 faz, e separar:
--     A_AUTO        — os três eixos já se resolvem hoje; a linha só ficou
--                     NEEDS_REVIEW porque nunca foi reavaliada depois das seeds
--                     de Edition Context. Não exige decisão editorial.
--     B_FINISH_GAP  — Printing e Edition Context terminais, mas não existe
--                     mapping de acabamento para o residual. Decisão editorial
--                     por assinatura residual (tipo/foil/subtype/stamp).
--     C_EC_PENDING  — Edition Context não terminal (token conhecido-inativo ou
--                     perfil ausente). Decisão de vocabulário de Edition Context.
--     D_PRINTING    — Printing não terminal. Decisão de vocabulário de Printing.
-- Mesmo universo da 2212/NR-REMEASURE: job vivo + persistence PENDING.
-- Seções (1 linha, 1 coluna jsonb):
--   classes        — contagem por classe
--   auto_por_tipo  — A_AUTO por Variant Type que seria atribuído
--   unidades       — B/C/D agrupadas por residual (tipo, foil, subtype, stamp)
--                    com nº de linhas e de Sets (top 80) + total de unidades
-- Resultado esperado: soma das classes = 1.642.
-- Como validar: classes somam needs_review_total; Σ unidades(B+C+D) + A = 1.642.
-- =============================================================================
WITH src AS (
  SELECT id FROM public.asset_source WHERE code = 'TCGDEX'
),
nr AS (
  SELECT r.id, r.raw_data, cs.id AS card_set_id, cs.code AS set_code, e.game_id
  FROM public.catalog_variant_import_row r
  JOIN public.catalog_variant_import_job j ON j.id = r.job_id
  JOIN public.card_set  cs ON cs.id = j.card_set_id
  JOIN public.expansion e  ON e.id  = cs.expansion_id
  WHERE j.status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING')
    AND r.persistence_status = 'PENDING'
    AND r.validation_status  = 'NEEDS_REVIEW'
),
ax AS (
  SELECT nr.id, nr.set_code, nr.card_set_id, nr.game_id,
         a.printing_state, a.edition_context_state,
         a.residual_type, a.residual_foil, a.residual_subtype,
         COALESCE(a.residual_stamp, '{}'::text[]) AS residual_stamp
  FROM nr
  CROSS JOIN src
  LEFT JOIN LATERAL internal.resolve_variant_mapping_scope(nr.card_set_id, src.id) sc ON TRUE
  CROSS JOIN LATERAL internal.resolve_variant_row_axes(nr.raw_data, nr.game_id, src.id, sc.external_set_id) a
),
cl AS (
  SELECT ax.*,
         CASE
           WHEN ax.printing_state NOT IN ('RESOLVED_NO_PRINTING','RESOLVED_WITH_PROFILE') THEN NULL
           WHEN ax.edition_context_state NOT IN ('RESOLVED_NO_EDITION_CONTEXT','RESOLVED_WITH_EC_PROFILE') THEN NULL
           ELSE internal.lookup_variant_type_for_row(ax.game_id, (SELECT id FROM src), ax.card_set_id,
                  ax.residual_type, ax.residual_foil, ax.residual_subtype, ax.residual_stamp)
         END AS variant_type_id
  FROM ax
),
k AS (
  SELECT cl.*,
         CASE
           WHEN printing_state NOT IN ('RESOLVED_NO_PRINTING','RESOLVED_WITH_PROFILE') THEN 'D_PRINTING'
           WHEN edition_context_state NOT IN ('RESOLVED_NO_EDITION_CONTEXT','RESOLVED_WITH_EC_PROFILE') THEN 'C_EC_PENDING'
           WHEN variant_type_id IS NULL THEN 'B_FINISH_GAP'
           ELSE 'A_AUTO'
         END AS classe
  FROM cl
)
SELECT jsonb_build_object(
  'needs_review_total', (SELECT count(*) FROM k),
  'classes', (SELECT jsonb_object_agg(classe, n) FROM (SELECT classe, count(*) AS n FROM k GROUP BY 1) t),
  'estados', (SELECT jsonb_agg(jsonb_build_object('printing', printing_state, 'ec', edition_context_state, 'n', n) ORDER BY n DESC)
              FROM (SELECT printing_state, edition_context_state, count(*) AS n FROM k GROUP BY 1,2) t),
  'auto_por_tipo', (SELECT jsonb_agg(jsonb_build_object('tipo', vt.code, 'n', n) ORDER BY n DESC)
              FROM (SELECT variant_type_id, count(*) AS n FROM k WHERE classe = 'A_AUTO' GROUP BY 1) t
              JOIN public.card_variant_type vt ON vt.id = t.variant_type_id),
  'unidades_total', (SELECT count(*) FROM (SELECT DISTINCT classe, residual_type, residual_foil, residual_subtype, residual_stamp
              FROM k WHERE classe <> 'A_AUTO') u),
  'unidades', (SELECT jsonb_agg(jsonb_build_object('classe', classe, 'type', residual_type, 'foil', residual_foil,
                 'subtype', residual_subtype, 'stamp', residual_stamp, 'n', n, 'sets', s, 'ex_sets', ex) ORDER BY n DESC)
              FROM (SELECT classe, residual_type, residual_foil, residual_subtype, residual_stamp,
                           count(*) AS n, count(DISTINCT set_code) AS s,
                           (array_agg(DISTINCT set_code))[1:4] AS ex
                    FROM k WHERE classe <> 'A_AUTO'
                    GROUP BY 1,2,3,4,5 ORDER BY n DESC LIMIT 80) t)
) AS nr_dryrun;
