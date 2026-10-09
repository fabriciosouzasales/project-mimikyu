-- =============================================================================
-- Query G-COMP-DB-01 — Contagens persistidas para o gate G-COMP (VARIANT-DISPLAY-SEMANTICS-01)
-- STATUS: PROPOSTA — NÃO EXECUTADA. Somente leitura (um único SELECT).
--         Sem DML/DDL, sem função, sem tabela temporária.
-- -----------------------------------------------------------------------------
-- Objetivo: medir no banco o mesmo universo que getCartasCompletas() carrega,
--   para comparar com o rawCount que a aplicação recebe.
--     - galeria /catalogo/cartas  → incluirInativas: true  → cards_todas / variants_todas
--     - relatórios (Checklist, Variantes por carta) → só ativas → cards_ativas / variants_ativas
--   Seções:
--     sets     — ME2.5 (alvo do P9), BASE5 e SVE (Sets dos casos F0)
--     f0       — variantes por carta dos 4 casos F0 (esperado 2/6/6/6)
--     limites  — maior Set por nº de cartas e maior nº de variantes por carta
--                (risco de truncamento por max-rows do PostgREST na raiz)
--     pgrst    — configuração de role do authenticator (max-rows, se definida ali)
-- Resultado esperado: 1 linha, 1 coluna jsonb.
--     sets.ME2.5 = { cards_todas 295, variants_todas 630 } (igual ao S1 e ao P9).
--     f0 = Dark Alakazam BASE5 → 2; SVE 001/015/016 → 6 cada.
--     limites.max_cards_por_set < max-rows efetivo (padrão do Supabase: 1000).
-- Como validar: comparar com o lado da aplicação (gallery.cartas e Σ rawCount
--   capturados no navegador para os mesmos Sets). Qualquer divergência ⇒ G-COMP FAIL.
-- =============================================================================
WITH alvo AS (
  SELECT cs.id, cs.code
  FROM public.card_set cs
  WHERE cs.code IN ('ME2.5', 'BASE5', 'SVE')
),
por_set AS (
  SELECT a.code,
         count(DISTINCT c.id)                                  AS cards_todas,
         count(DISTINCT c.id) FILTER (WHERE c.is_active)       AS cards_ativas,
         count(cv.id)                                          AS variants_todas,
         count(cv.id) FILTER (WHERE c.is_active)               AS variants_ativas
  FROM alvo a
  JOIN public.card c               ON c.card_set_id = a.id
  LEFT JOIN public.card_variant cv ON cv.card_id = c.id
  GROUP BY a.code
),
f0 AS (
  SELECT a.code, c.collector_number, c.name, c.is_active,
         (SELECT count(*) FROM public.card_variant cv WHERE cv.card_id = c.id) AS variants
  FROM alvo a
  JOIN public.card c ON c.card_set_id = a.id
  WHERE (a.code = 'BASE5' AND c.name ILIKE '%Alakazam%')
     OR (a.code = 'SVE'   AND c.collector_number IN ('001', '015', '016', '1', '15', '16'))
),
cards_por_set AS (
  SELECT cs.code,
         count(c.id)                             AS cards_todas,
         count(c.id) FILTER (WHERE c.is_active)  AS cards_ativas
  FROM public.card_set cs
  JOIN public.card c ON c.card_set_id = cs.id
  GROUP BY cs.code
),
variants_por_card AS (
  SELECT cv.card_id, count(*) AS n
  FROM public.card_variant cv
  GROUP BY cv.card_id
)
SELECT jsonb_build_object(
  'sets', (SELECT jsonb_object_agg(code, jsonb_build_object(
             'cards_todas', cards_todas, 'cards_ativas', cards_ativas,
             'variants_todas', variants_todas, 'variants_ativas', variants_ativas))
           FROM por_set),
  'f0', (SELECT jsonb_agg(jsonb_build_object(
           'set', code, 'collector_number', collector_number, 'name', name,
           'is_active', is_active, 'variants', variants)
           ORDER BY code, collector_number)
         FROM f0),
  'limites', jsonb_build_object(
     'max_cards_por_set_todas', (SELECT max(cards_todas) FROM cards_por_set),
     'set_com_mais_cards',      (SELECT code FROM cards_por_set ORDER BY cards_todas DESC, code LIMIT 1),
     'sets_acima_de_1000',      (SELECT count(*) FROM cards_por_set WHERE cards_todas > 1000),
     'max_variants_por_card',   (SELECT max(n) FROM variants_por_card)),
  'pgrst', (SELECT to_jsonb(r.rolconfig) FROM pg_catalog.pg_roles r WHERE r.rolname = 'authenticator')
) AS g_comp;
