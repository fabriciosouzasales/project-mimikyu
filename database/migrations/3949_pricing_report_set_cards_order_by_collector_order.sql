-- Query 3949 — "Valor por Set": ordenar a lista de cartas em ordem editorial
-- da coleção (collector_order), não mais por valor
-- Status: CONFIRMADO EXECUTADO em 2026-08-23 (Fabrício, via Supabase SQL
-- Editor — confirmado por Claude pós-aplicação via pg_get_functiondef,
-- projeto qjfutqujxrbzgrtkpgkg)
--
-- Objetivo: correção de direção de produto (Fabrício, 2026-08-23) — a tela
-- "Valor por Set" não é um ranking econômico, é um relatório de composição
-- de custo/valor do Set em ordem editorial da coleção. Único ponto alterado
-- em relação à migration 3944 (definição original desta função): a cláusula
-- ORDER BY final.
--   antes: ORDER BY (price_display IS NULL), price_display DESC NULLS LAST, collector_order ASC NULLS LAST
--   agora: ORDER BY collector_order ASC NULLS LAST
--
-- Preservado sem alteração: valuation, cobertura, escolha de preço,
-- conversão FX, `participation_pct`, e `ranking` interno (calculado via
-- `rank() OVER (ORDER BY price_display DESC)` na CTE `ranked`, que roda
-- ANTES da ORDER BY final e não é afetada por ela — continua disponível
-- como dado, só deixou de reger a ordem de exibição).
--
-- Segurança: mesma STABLE SECURITY DEFINER, SET search_path TO '', guard
-- explícito public.is_admin(), REVOKE ALL FROM PUBLIC + GRANT EXECUTE
-- restrito a authenticated — idêntico à definição de produção anterior.

CREATE OR REPLACE FUNCTION public.admin_get_pricing_report_set_cards(p_card_set_id uuid, p_condition_id uuid DEFAULT NULL::uuid, p_currency text DEFAULT 'BRL'::text, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS TABLE(card_id uuid, card_name text, collector_number text, collector_total integer, status text, pricing_source_id uuid, pricing_source_code text, printing_label text, price_native numeric, currency_native text, price_display numeric, currency text, fx_status text, fx_source text, fx_rate numeric, fx_rate_date date, observed_at timestamp with time zone, participation_pct numeric, ranking integer, set_covered_value numeric, total_count bigint)
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
  ORDER BY rows.collector_order ASC NULLS LAST
  LIMIT v_limit
  OFFSET v_offset;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_get_pricing_report_set_cards(uuid, uuid, text, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_pricing_report_set_cards(uuid, uuid, text, integer, integer) TO authenticated;

-- Como validar pós-aplicação:
-- 1. `pg_get_functiondef('public.admin_get_pricing_report_set_cards'::regproc)`
--    confirma a ORDER BY nova (feito por Claude em 2026-08-23).
-- 2. A validação funcional real (ordem ascendente na tela) precisa rodar
--    autenticado como admin — o SQL Editor/MCP roda como postgres/service
--    role, sem sessão de usuário, então cai no guard is_admin() antes de
--    chegar na ORDER BY. Validação real: abrir /pricing/relatorios/valor-
--    por-set com um Set qualquer e confirmar que as cartas aparecem em
--    ordem crescente de número de coleção.
