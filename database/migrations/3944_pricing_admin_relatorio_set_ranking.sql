-- CONFIRMADO EXECUTADO em 2026-08-22 (aplicada em duas etapas: 3944 + correção 3944b, consolidadas aqui)
-- =============================================================================
-- Migration 3944 — Pricing Admin: Relatório "Valor por Set" — lista/ranking de
-- cartas (fechamento do Bloco 5, reabertura solicitada por Fabrício).
--
-- Contexto: o Bloco 5 (Central de Relatórios) havia sido entregue sem o
-- ranking/lista de cartas do relatório "Valor por Set" — item que fazia parte
-- do escopo aprovado. Fabrício pediu uma RPC dedicada, set-based (nunca N
-- chamadas a get_cards_pricing_summary), reusando exatamente a mesma regra
-- econômica de admin_get_pricing_report_set (3943).
--
-- Desenho (3 objetos):
--   1. admin_pricing_report_set_price_candidates(card_set_id, condition_id,
--      currency) — função helper SQL pura, extrai o encadeamento de CTEs
--      (active_cards → candidate_by_printing → candidate → candidate_with_fx)
--      que decide o candidato de preço por carta. NÃO é exposta via GRANT
--      (REVOKE explícito de PUBLIC/authenticated/anon/service_role) — só é
--      chamável a partir de outra SECURITY DEFINER que já tenha passado pelo
--      gate de admin.
--   2. admin_get_pricing_report_set (3943) — REDEFINIDA para consumir a
--      helper em vez de reimplementar os CTEs. Estrutura de RETURNS jsonb e
--      todos os campos permanecem idênticos à versão anterior; único efeito
--      colateral esperado é o de tornar o cálculo estruturalmente idêntico
--      ao da nova RPC de lista abaixo — reconciliação por construção, não
--      apenas por coincidência revalidada a cada mudança futura.
--   3. admin_get_pricing_report_set_cards(card_set_id, condition_id,
--      currency, limit, offset) — nova RPC de lista/ranking por carta.
--      Paginação server-side (p_limit clamped 1-100, p_offset >= 0,
--      total_count via count(*) OVER()). Nunca trata ausência de preço como
--      zero: status distingue PRICED (price_display IS NOT NULL) de
--      FX_UNAVAILABLE (candidato existe mas price_display é NULL por câmbio)
--      de NO_PRICE (nenhum candidato). fx_status detalha
--      NATIVE/CONVERTED/FX_RATE_UNAVAILABLE/UNSUPPORTED_CONVERSION.
--      participation_pct e ranking calculados sobre o conjunto PRICED do
--      próprio Set; set_covered_value replica o mesmo somatório retornado
--      como estimated_value_covered pela 3943.
--
-- Ajustes exigidos por Fabrício antes de aplicar (ambos incorporados abaixo):
--   1. ACL da helper explícito na própria migration (REVOKE ALL ... FROM
--      PUBLIC; REVOKE ALL ... FROM authenticated, anon, service_role;) — não
--      depender apenas de pg_default_acl.
--   2. Status de 3 vias na lista por carta (PRICED / FX_UNAVAILABLE /
--      NO_PRICE), com fx_status detalhado mantido.
--
-- Correção pós-aplicação (originalmente aplicada como migration avulsa
-- "3944b_fix_ambiguous_price_display_reference", consolidada neste arquivo):
--   admin_get_pricing_report_set_cards declara `price_display` em RETURNS
--   TABLE, o que o torna um parâmetro OUT implícito visível em toda a função
--   — inclusive dentro de CTEs aninhadas. A CTE `covered` referenciava
--   `price_display` sem qualificar o alias da CTE `priced`, colidindo com o
--   OUT parameter e causando erro em runtime ("column reference is
--   ambiguous"). Este bug não é detectável testando a query equivalente fora
--   de uma função (foi assim que a query foi validada antes de aplicar) — só
--   se manifesta com o wrapper PL/pgSQL real. Corrigido qualificando
--   explicitamente `pr.price_display` (alias `pr` para `priced`) na CTE
--   `covered`. A versão abaixo já reflete a correção.
--
-- Validação pós-correção (dados reais, reconciliação exata contra 3943):
--   BASE1 × BRL: 101 PRICED (R$ 10.963,33) + 1 NO_PRICE = 102 total_active_cards.
--   BASE1 × USD: 101 PRICED ($ 2.120,60) + 1 NO_PRICE = 102 total_active_cards.
--   ME2.5 × BRL: 295 PRICED (R$ 30.083,14), 100% cobertura.
--   ME2.5 × USD: 295 PRICED ($ 5.826,61), 100% cobertura.
--   Todos os 4 cenários reconciliam exatamente (sem arredondamento residual)
--   contra estimated_value_covered/priced_convertible_count/no_price_count
--   retornados por admin_get_pricing_report_set.
--
-- Divergência documental pré-existente (não introduzida por esta migration):
--   admin_get_pricing_report_set (3943) foi originalmente criada em uma
--   migration própria que não chegou a ser versionada fisicamente em
--   database/migrations/ antes desta rodada. Este arquivo versiona apenas o
--   estado resultante da 3944 (que redefine a 3943 para consumir a nova
--   helper) — não reconstitui retroativamente a migration 3943 original.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Helper — candidato de preço por carta, fonte única de verdade.
--    NÃO recebe GRANT: só é chamável a partir de outra SECURITY DEFINER que
--    já tenha passado pelo gate de admin (herança de privilégio do definer).
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.admin_pricing_report_set_price_candidates(
  p_card_set_id uuid,
  p_condition_id uuid,
  p_currency text
)
RETURNS TABLE(
  card_id uuid,
  pricing_source_id uuid,
  pricing_source_code text,
  printing_label text,
  price_native numeric,
  currency_native text,
  observed_at timestamptz,
  fx_rate numeric,
  fx_rate_date date,
  fx_source text,
  price_display numeric,
  fx_blocked boolean
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
  WITH active_cards AS (
    SELECT c.id AS card_id
    FROM public.card c
    WHERE c.card_set_id = p_card_set_id AND c.is_active = TRUE
  ),
  candidate_by_printing AS (
    SELECT DISTINCT ON (ac.card_id, pp.source_printing_label)
      ac.card_id,
      pcm.pricing_source_id,
      ps.code AS pricing_source_code,
      pp.source_printing_label,
      po.price,
      po.currency_code,
      po.observed_at
    FROM active_cards ac
    JOIN public.pricing_card_mapping pcm ON pcm.card_id = ac.card_id AND pcm.match_status = 'CONFIRMED'
    JOIN public.pricing_source ps ON ps.id = pcm.pricing_source_id AND ps.is_active = TRUE
    JOIN public.pricing_product pp ON pp.pricing_card_mapping_id = pcm.id AND pp.is_active = TRUE
       AND pp.source_printing_label IN ('Normal','Holofoil','Reverse Holofoil','Unlimited','Unlimited Holofoil','1st Edition','1st Edition Holofoil')
    JOIN public.pricing_source_card_identity psci ON psci.id = pp.pricing_source_card_identity_id
       AND psci.identity_role = 'PRIMARY' AND psci.match_status = 'CONFIRMED'
    JOIN public.pricing_observation po ON po.pricing_product_id = pp.id
       AND po.condition_id = p_condition_id AND po.price_type = 'MARKET'
    ORDER BY ac.card_id, pp.source_printing_label, po.observed_at DESC, po.created_at DESC, po.id DESC
  ),
  candidate AS (
    SELECT DISTINCT ON (cbp.card_id)
      cbp.card_id, cbp.pricing_source_id, cbp.pricing_source_code,
      cbp.source_printing_label, cbp.price, cbp.currency_code, cbp.observed_at
    FROM candidate_by_printing cbp
    ORDER BY cbp.card_id,
      CASE cbp.source_printing_label
        WHEN 'Normal' THEN 1 WHEN 'Holofoil' THEN 2 WHEN 'Reverse Holofoil' THEN 3
        WHEN 'Unlimited' THEN 4 WHEN 'Unlimited Holofoil' THEN 5
        WHEN '1st Edition' THEN 6 WHEN '1st Edition Holofoil' THEN 7 ELSE 8 END
  ),
  candidate_with_fx AS (
    SELECT c.*, fx.rate AS fx_rate, fx.rate_date AS fx_rate_date, fx.rate_source_code AS fx_rate_source
    FROM candidate c
    LEFT JOIN LATERAL (
      SELECT r.rate, r.rate_date, r.rate_source_code
      FROM public.pricing_fx_rate r
      WHERE c.currency_code = 'USD' AND p_currency = 'BRL'
        AND r.from_currency = 'USD' AND r.to_currency = 'BRL' AND r.rate_source_code = 'BCB_PTAX'
        AND r.rate_date <= (c.observed_at AT TIME ZONE 'UTC')::date
      ORDER BY r.rate_date DESC LIMIT 1
    ) fx ON TRUE
  )
  SELECT
    cf.card_id,
    cf.pricing_source_id,
    cf.pricing_source_code,
    cf.source_printing_label AS printing_label,
    cf.price AS price_native,
    cf.currency_code AS currency_native,
    cf.observed_at,
    cf.fx_rate,
    cf.fx_rate_date,
    cf.fx_rate_source AS fx_source,
    CASE WHEN cf.currency_code = p_currency THEN cf.price
         WHEN p_currency = 'BRL' AND cf.currency_code = 'USD' AND cf.fx_rate IS NOT NULL THEN round(cf.price * cf.fx_rate, 2)
         ELSE NULL END AS price_display,
    (cf.currency_code <> p_currency AND NOT (p_currency = 'BRL' AND cf.currency_code = 'USD' AND cf.fx_rate IS NOT NULL)) AS fx_blocked
  FROM candidate_with_fx cf;
$function$;

REVOKE ALL ON FUNCTION public.admin_pricing_report_set_price_candidates(uuid, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_pricing_report_set_price_candidates(uuid, uuid, text) FROM authenticated, anon, service_role;

-- -----------------------------------------------------------------------------
-- 2. admin_get_pricing_report_set (3943) — redefinida para consumir a helper.
--    Assinatura, RETURNS jsonb e todos os campos do payload permanecem
--    idênticos à versão anterior.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.admin_get_pricing_report_set(
  p_card_set_id uuid,
  p_condition_id uuid DEFAULT NULL,
  p_currency text DEFAULT 'BRL'
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_condition_id uuid;
  v_result jsonb;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'ADMIN_GET_PRICING_REPORT_SET_FORBIDDEN: acesso restrito a administradores.';
  END IF;

  IF p_currency NOT IN ('BRL', 'USD') THEN
    RAISE EXCEPTION 'ADMIN_GET_PRICING_REPORT_SET_INVALID_CURRENCY: %', p_currency;
  END IF;

  IF p_condition_id IS NULL THEN
    SELECT id INTO v_condition_id FROM public.card_condition WHERE code = 'NM';
  ELSE
    SELECT id INTO v_condition_id FROM public.card_condition WHERE id = p_condition_id;
  END IF;

  IF v_condition_id IS NULL THEN
    RAISE EXCEPTION 'ADMIN_GET_PRICING_REPORT_SET_CONDITION_NOT_FOUND: id=%', p_condition_id;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.card_set WHERE id = p_card_set_id) THEN
    RAISE EXCEPTION 'ADMIN_GET_PRICING_REPORT_SET_NOT_FOUND: id=%', p_card_set_id;
  END IF;

  WITH active_cards AS (
    SELECT c.id AS card_id
    FROM public.card c
    WHERE c.card_set_id = p_card_set_id AND c.is_active = TRUE
  ),
  priced AS (
    SELECT card_id, price_display, fx_blocked
    FROM public.admin_pricing_report_set_price_candidates(p_card_set_id, v_condition_id, p_currency)
  )
  SELECT jsonb_build_object(
    'card_set_id', p_card_set_id,
    'condition', jsonb_build_object('id', v_condition_id,
       'code', (SELECT code FROM public.card_condition WHERE id = v_condition_id),
       'name', (SELECT name FROM public.card_condition WHERE id = v_condition_id)),
    'currency', p_currency,
    'total_active_cards', (SELECT count(*) FROM active_cards),
    'priced_convertible_count', (SELECT count(*) FROM priced WHERE price_display IS NOT NULL),
    'priced_fx_unavailable_count', (SELECT count(*) FROM priced WHERE fx_blocked),
    'no_price_count', (SELECT count(*) FROM active_cards ac WHERE NOT EXISTS (SELECT 1 FROM priced p WHERE p.card_id = ac.card_id)),
    'coverage_pct', CASE WHEN (SELECT count(*) FROM active_cards) = 0 THEN 0
        ELSE round((SELECT count(*) FROM priced WHERE price_display IS NOT NULL)::numeric
                    / (SELECT count(*) FROM active_cards)::numeric * 100, 2) END,
    'estimated_value_covered', COALESCE((SELECT sum(price_display) FROM priced WHERE price_display IS NOT NULL), 0),
    'is_partial', (SELECT count(*) FROM priced WHERE price_display IS NOT NULL) < (SELECT count(*) FROM active_cards)
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

-- Grants inalterados em relação à versão anterior de admin_get_pricing_report_set
-- (já era authenticated-only desde a migration original, não versionada
-- fisicamente — ver nota de divergência documental no cabeçalho).
REVOKE ALL ON FUNCTION public.admin_get_pricing_report_set(uuid, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_pricing_report_set(uuid, uuid, text) TO authenticated;

-- -----------------------------------------------------------------------------
-- 3. admin_get_pricing_report_set_cards — nova RPC: lista/ranking por carta.
--    Correção de ambiguidade de coluna (price_display vs. OUT parameter de
--    RETURNS TABLE) já incorporada na CTE `covered` via alias `pr`.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.admin_get_pricing_report_set_cards(
  p_card_set_id uuid,
  p_condition_id uuid DEFAULT NULL,
  p_currency text DEFAULT 'BRL',
  p_limit integer DEFAULT 20,
  p_offset integer DEFAULT 0
)
RETURNS TABLE(
  card_id uuid,
  card_name text,
  collector_number text,
  collector_total integer,
  status text,
  pricing_source_id uuid,
  pricing_source_code text,
  printing_label text,
  price_native numeric,
  currency_native text,
  price_display numeric,
  currency text,
  fx_status text,
  fx_source text,
  fx_rate numeric,
  fx_rate_date date,
  observed_at timestamptz,
  participation_pct numeric,
  ranking integer,
  set_covered_value numeric,
  total_count bigint
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_condition_id uuid;
  v_limit int;
  v_offset int;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'ADMIN_GET_PRICING_REPORT_SET_CARDS_FORBIDDEN: acesso restrito a administradores.';
  END IF;

  IF p_currency NOT IN ('BRL', 'USD') THEN
    RAISE EXCEPTION 'ADMIN_GET_PRICING_REPORT_SET_CARDS_INVALID_CURRENCY: %', p_currency;
  END IF;

  IF p_condition_id IS NULL THEN
    SELECT id INTO v_condition_id FROM public.card_condition WHERE code = 'NM';
  ELSE
    SELECT id INTO v_condition_id FROM public.card_condition WHERE id = p_condition_id;
  END IF;

  IF v_condition_id IS NULL THEN
    RAISE EXCEPTION 'ADMIN_GET_PRICING_REPORT_SET_CARDS_CONDITION_NOT_FOUND: id=%', p_condition_id;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.card_set WHERE id = p_card_set_id) THEN
    RAISE EXCEPTION 'ADMIN_GET_PRICING_REPORT_SET_CARDS_NOT_FOUND: id=%', p_card_set_id;
  END IF;

  v_limit := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 100);
  v_offset := GREATEST(COALESCE(p_offset, 0), 0);

  RETURN QUERY
  WITH active_cards AS (
    SELECT c.id AS card_id, c.name::text AS card_name, c.collector_number::text AS collector_number,
           c.collector_total, c.collector_order
    FROM public.card c
    WHERE c.card_set_id = p_card_set_id AND c.is_active = TRUE
  ),
  priced AS (
    SELECT * FROM public.admin_pricing_report_set_price_candidates(p_card_set_id, v_condition_id, p_currency)
  ),
  covered AS (
    -- Alias `pr` obrigatório: `price_display` também é OUT parameter de
    -- RETURNS TABLE nesta função — referência não qualificada é ambígua.
    SELECT COALESCE(sum(pr.price_display), 0) AS v FROM priced pr WHERE pr.price_display IS NOT NULL
  ),
  ranked AS (
    SELECT p.card_id, rank() OVER (ORDER BY p.price_display DESC) AS rnk
    FROM priced p WHERE p.price_display IS NOT NULL
  ),
  rows AS (
    SELECT
      ac.card_id, ac.card_name, ac.collector_number, ac.collector_total, ac.collector_order,
      CASE WHEN p.card_id IS NULL THEN 'NO_PRICE'
           WHEN p.price_display IS NOT NULL THEN 'PRICED'
           ELSE 'FX_UNAVAILABLE' END AS status,
      p.pricing_source_id, p.pricing_source_code, p.printing_label,
      p.price_native, p.currency_native, p.price_display,
      p_currency AS currency,
      CASE WHEN p.card_id IS NULL THEN NULL
           WHEN p.currency_native = p_currency THEN 'NATIVE'
           WHEN p_currency = 'BRL' AND p.currency_native = 'USD' AND p.fx_rate IS NOT NULL THEN 'CONVERTED'
           WHEN p_currency = 'BRL' AND p.currency_native = 'USD' THEN 'FX_RATE_UNAVAILABLE'
           ELSE 'UNSUPPORTED_CONVERSION' END AS fx_status,
      p.fx_source, p.fx_rate, p.fx_rate_date, p.observed_at,
      CASE WHEN p.price_display IS NOT NULL AND (SELECT v FROM covered) > 0
           THEN round(p.price_display / (SELECT v FROM covered) * 100, 2) ELSE NULL END AS participation_pct,
      r.rnk::int AS ranking,
      (SELECT v FROM covered) AS set_covered_value
    FROM active_cards ac
    LEFT JOIN priced p ON p.card_id = ac.card_id
    LEFT JOIN ranked r ON r.card_id = ac.card_id
  )
  SELECT
    rows.card_id, rows.card_name, rows.collector_number, rows.collector_total,
    rows.status, rows.pricing_source_id, rows.pricing_source_code, rows.printing_label,
    rows.price_native, rows.currency_native, rows.price_display, rows.currency,
    rows.fx_status, rows.fx_source, rows.fx_rate, rows.fx_rate_date, rows.observed_at,
    rows.participation_pct, rows.ranking, rows.set_covered_value,
    count(*) OVER() AS total_count
  FROM rows
  ORDER BY (rows.price_display IS NULL), rows.price_display DESC NULLS LAST, rows.collector_order ASC NULLS LAST
  LIMIT v_limit
  OFFSET v_offset;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_get_pricing_report_set_cards(uuid, uuid, text, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_pricing_report_set_cards(uuid, uuid, text, integer, integer) TO authenticated;

-- =============================================================================
-- Validação pós-aplicação (CONFIRMADO):
--   - Grants: helper com ZERO EXECUTE para anon/authenticated/service_role
--     (só postgres); ambas as RPCs públicas com EXECUTE authenticated-only
--     (anon_exec=false, service_role_exec=false) — confirmado via
--     has_function_privilege() e cruzado com Security Advisors (mesmo padrão
--     `authenticated_security_definer_function_executable` já aceito em toda
--     a superfície admin_* existente; helper não aparece na lista, confirmando
--     ausência de grant).
--   - Performance Advisors: nenhum achado novo referente a estas 3 funções;
--     achados pré-existentes (FKs sem índice, índices não usados) não
--     relacionados a este incremento.
--   - Reconciliação BASE1×BRL/USD e ME2.5×BRL/USD: soma exata contra
--     estimated_value_covered/priced_convertible_count/no_price_count da
--     admin_get_pricing_report_set (ver relatório final do incremento).
-- =============================================================================
