-- Migration 3969 — Preço Manual: fallback nas superfícies de relatório/valuation
-- Status: CONFIRMADO EXECUTADO em 2026-08-27 via Supabase MCP (apply_migration).
--
-- Escopo (definido por Fabrício, aprovado após fechamento formal da 3968):
--   Integrar fallback de preço manual (pricing_manual_price /
--   pricing_latest_manual_price, migration 3967) nas 4 superfícies de
--   relatório/valuation já aprovadas do módulo Pricing Admin:
--     1. admin_pricing_report_set_price_candidates  (DROP + CREATE)
--     2. admin_get_pricing_report_set                (sem alteração de código —
--        herda o fallback transitivamente via #1, ver nota abaixo)
--     3. admin_get_pricing_report_set_cards           (DROP + CREATE)
--     4. admin_get_pricing_report_card                (CREATE OR REPLACE)
--
-- Regra de precedência (por card + condition):
--   AUTOMÁTICO UTILIZÁVEL > MANUAL UTILIZÁVEL > SEM PREÇO
--   "Utilizável" = price_display resolvido (moeda nativa == p_currency, ou
--   conversão de câmbio bem-sucedida via pricing_fx_rate/BCB_PTAX).
--
-- Nota sobre #2 (admin_get_pricing_report_set): esta função apenas consome
-- admin_pricing_report_set_price_candidates via
--   `priced AS (SELECT card_id, price_display, fx_blocked FROM ...)`
-- Como o nome dos 3 campos lidos (card_id, price_display, fx_blocked)
-- permanece inalterado e a assinatura da função (uuid, uuid, text) não muda,
-- nenhuma alteração de código foi necessária: `estimated_value_covered`,
-- `priced_convertible_count`, `no_price_count` etc. passaram a refletir
-- corretamente o fallback manual automaticamente assim que #1 foi corrigida.
-- Validado explicitamente no teste transacional (ver Revision History).
--
-- Assimetria preservada (rule 1 do pedido): a conversão de câmbio automática
-- permanece restrita a USD→BRL (comportamento pré-existente, fora de escopo
-- corrigir). A conversão de câmbio manual (herdada da migration 3967/3968)
-- continua genérica: qualquer par (manual.currency_code → p_currency) com
-- linha em pricing_fx_rate (rate_source_code = 'BCB_PTAX') é aceito.
--
-- Validação: teste transacional único (BEGIN/ROLLBACK) cobrindo os 9 critérios
-- da rule 7 do pedido — Set sem manual idêntico ao anterior (comparação linha
-- a linha via EXCEPT contra baseline pré-migration em outro Set, SVE);
-- Set com manual = soma aumenta exatamente pelo fallback esperado; automático
-- válido continua vencendo manual mesmo com manual cadastrado para a mesma
-- carta/condition; manual sem taxa de câmbio disponível (EUR sem linha em
-- pricing_fx_rate) não entra; condições tratadas de forma independente
-- (manual cadastrado para NM não interfere na consulta por LP, que preserva
-- seu próprio preço automático); reconciliação exata entre o resumo do Set e
-- a soma da lista de cartas; price_origin correto em todas as 3 funções;
-- grants sem regressão (candidates seguiu postgres-only, set_cards e card
-- seguiram authenticated+postgres) — validado via pg_proc.proacl dentro da
-- própria transação e reconfirmado após a aplicação real. Fixtures usaram o
-- Set MEE (8 cartas) com 2 observações automáticas removidas transacionalmente
-- para simular ausência de preço automático, e o Set SVE (24 cartas, nunca
-- alterado) como baseline de "Set sem manual".
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1) admin_pricing_report_set_price_candidates — DROP + CREATE
--    Nova coluna: price_origin ('AUTOMATIC' | 'MANUAL' | NULL)
--    LANGUAGE sql — sem risco de ambiguidade 42702 (essa classe de bug é
--    específica de PL/pgSQL, ver nota na migration 3968).
-- -----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.admin_pricing_report_set_price_candidates(uuid, uuid, text);

CREATE FUNCTION public.admin_pricing_report_set_price_candidates(
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
  fx_blocked boolean,
  price_origin text
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
    JOIN public.pricing_card_mapping pcm
      ON pcm.card_id = ac.card_id AND pcm.match_status = 'CONFIRMED'
    JOIN public.pricing_source ps
      ON ps.id = pcm.pricing_source_id AND ps.is_active = TRUE
    JOIN public.pricing_product pp
      ON pp.pricing_card_mapping_id = pcm.id AND pp.is_active = TRUE
     AND pp.source_printing_label IN (
       'Normal', 'Holofoil', 'Reverse Holofoil', 'Unlimited',
       'Unlimited Holofoil', '1st Edition', '1st Edition Holofoil'
     )
    JOIN public.pricing_source_card_identity psci
      ON psci.id = pp.pricing_source_card_identity_id
     AND psci.identity_role = 'PRIMARY' AND psci.match_status = 'CONFIRMED'
    JOIN public.pricing_observation po
      ON po.pricing_product_id = pp.id
     AND po.condition_id = p_condition_id AND po.price_type = 'MARKET'
    ORDER BY ac.card_id, pp.source_printing_label,
             po.observed_at DESC, po.created_at DESC, po.id DESC
  ),
  candidate AS (
    SELECT DISTINCT ON (cbp.card_id)
      cbp.card_id, cbp.pricing_source_id, cbp.pricing_source_code,
      cbp.source_printing_label, cbp.price, cbp.currency_code, cbp.observed_at
    FROM candidate_by_printing cbp
    ORDER BY cbp.card_id,
      CASE cbp.source_printing_label
        WHEN 'Normal' THEN 1
        WHEN 'Holofoil' THEN 2
        WHEN 'Reverse Holofoil' THEN 3
        WHEN 'Unlimited' THEN 4
        WHEN 'Unlimited Holofoil' THEN 5
        WHEN '1st Edition' THEN 6
        WHEN '1st Edition Holofoil' THEN 7
        ELSE 8
      END
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
  ),
  -- ---- Caminho automático: lógica idêntica à vigente antes da 3969 (rule 1) ----
  automatic AS (
    SELECT
      cf.card_id,
      cf.pricing_source_id, cf.pricing_source_code, cf.source_printing_label AS printing_label,
      cf.price AS price_native, cf.currency_code AS currency_native, cf.observed_at,
      cf.fx_rate, cf.fx_rate_date, cf.fx_rate_source AS fx_source,
      CASE WHEN cf.currency_code = p_currency THEN cf.price
           WHEN p_currency = 'BRL' AND cf.currency_code = 'USD' AND cf.fx_rate IS NOT NULL
             THEN round(cf.price * cf.fx_rate, 2)
           ELSE NULL END AS price_display,
      (cf.currency_code <> p_currency
       AND NOT (p_currency = 'BRL' AND cf.currency_code = 'USD' AND cf.fx_rate IS NOT NULL)
      ) AS fx_blocked
    FROM candidate_with_fx cf
  ),
  -- ---- Fallback manual (novo em 3969) — mesma condition_id, moeda alvo p_currency ----
  manual_raw AS (
    SELECT ac.card_id, mp.price, mp.currency_code, mp.observed_at
    FROM active_cards ac
    LEFT JOIN LATERAL public.pricing_latest_manual_price(ac.card_id, p_condition_id) mp ON TRUE
    WHERE mp.price IS NOT NULL
  ),
  manual_with_fx AS (
    SELECT mr.*, mfx.rate AS fx_rate, mfx.rate_date AS fx_rate_date
    FROM manual_raw mr
    LEFT JOIN LATERAL (
      SELECT r.rate, r.rate_date
      FROM public.pricing_fx_rate r
      WHERE mr.currency_code IS NOT NULL AND mr.currency_code <> p_currency
        AND r.from_currency = mr.currency_code AND r.to_currency = p_currency
        AND r.rate_source_code = 'BCB_PTAX'
        AND r.rate_date <= (mr.observed_at AT TIME ZONE 'UTC')::date
      ORDER BY r.rate_date DESC LIMIT 1
    ) mfx ON TRUE
  ),
  manual AS (
    SELECT
      mf.card_id,
      mf.price AS price_native, mf.currency_code AS currency_native, mf.observed_at,
      mf.fx_rate, mf.fx_rate_date,
      CASE WHEN mf.fx_rate IS NOT NULL THEN 'BCB_PTAX' ELSE NULL END AS fx_source,
      CASE WHEN mf.currency_code = p_currency THEN mf.price
           WHEN mf.fx_rate IS NOT NULL THEN round(mf.price * mf.fx_rate, 2)
           ELSE NULL END AS price_display
    FROM manual_with_fx mf
  )
  SELECT
    ac.card_id,
    CASE WHEN v.use_automatic THEN a.pricing_source_id ELSE NULL END AS pricing_source_id,
    CASE WHEN v.use_automatic THEN a.pricing_source_code ELSE NULL END AS pricing_source_code,
    CASE WHEN v.use_automatic THEN a.printing_label ELSE NULL END AS printing_label,
    CASE WHEN v.use_automatic THEN a.price_native ELSE m.price_native END AS price_native,
    CASE WHEN v.use_automatic THEN a.currency_native ELSE m.currency_native END AS currency_native,
    CASE WHEN v.use_automatic THEN a.observed_at ELSE m.observed_at END AS observed_at,
    CASE WHEN v.use_automatic THEN a.fx_rate ELSE m.fx_rate END AS fx_rate,
    CASE WHEN v.use_automatic THEN a.fx_rate_date ELSE m.fx_rate_date END AS fx_rate_date,
    CASE WHEN v.use_automatic THEN a.fx_source ELSE m.fx_source END AS fx_source,
    CASE WHEN v.use_automatic THEN a.price_display ELSE m.price_display END AS price_display,
    CASE WHEN v.use_automatic THEN a.fx_blocked ELSE FALSE END AS fx_blocked,
    CASE WHEN v.use_automatic AND a.price_display IS NOT NULL THEN 'AUTOMATIC'
         WHEN NOT v.use_automatic AND m.price_display IS NOT NULL THEN 'MANUAL'
         ELSE NULL END AS price_origin
  FROM active_cards ac
  LEFT JOIN automatic a ON a.card_id = ac.card_id
  LEFT JOIN manual m ON m.card_id = ac.card_id
  CROSS JOIN LATERAL (
    SELECT (a.card_id IS NOT NULL AND (a.price_display IS NOT NULL OR m.price_display IS NULL)) AS use_automatic
  ) v
  WHERE a.card_id IS NOT NULL OR m.price_display IS NOT NULL;
$function$;

COMMENT ON FUNCTION public.admin_pricing_report_set_price_candidates(uuid, uuid, text) IS
  'Helper interno (não exposto a authenticated) — candidatos de preço por carta em um Set, condition e moeda, com fallback de preço manual (migration 3969). Precedência: automático utilizável > manual utilizável > sem preço.';

REVOKE ALL ON FUNCTION public.admin_pricing_report_set_price_candidates(uuid, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_pricing_report_set_price_candidates(uuid, uuid, text) FROM authenticated, anon, service_role;


-- -----------------------------------------------------------------------------
-- 2) admin_get_pricing_report_set — SEM ALTERAÇÃO DE CÓDIGO
--    Herda o fallback manual transitivamente via #1 (ver nota no cabeçalho).
--    Nenhum DROP/CREATE/REPLACE foi necessário; grants permanecem intocados.
-- -----------------------------------------------------------------------------


-- -----------------------------------------------------------------------------
-- 3) admin_get_pricing_report_set_cards — DROP + CREATE
--    Nova coluna: price_origin. fx_status ganha branch específico para
--    origem MANUAL (a lógica USD/BRL hardcoded do automático não se aplica
--    a conversões manuais em outras moedas — bug evitado, ver nota abaixo).
-- -----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.admin_get_pricing_report_set_cards(uuid, uuid, text, integer, integer);

CREATE FUNCTION public.admin_get_pricing_report_set_cards(
  p_card_set_id uuid,
  p_condition_id uuid DEFAULT NULL::uuid,
  p_currency text DEFAULT 'BRL'::text,
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
  total_count bigint,
  price_origin text
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
           WHEN p.price_origin = 'MANUAL'
             THEN (CASE WHEN p.currency_native = p_currency THEN 'NATIVE' ELSE 'CONVERTED' END)
           WHEN p.currency_native = p_currency THEN 'NATIVE'
           WHEN p_currency = 'BRL' AND p.currency_native = 'USD' AND p.fx_rate IS NOT NULL THEN 'CONVERTED'
           WHEN p_currency = 'BRL' AND p.currency_native = 'USD' THEN 'FX_RATE_UNAVAILABLE'
           ELSE 'UNSUPPORTED_CONVERSION' END AS fx_status,
      p.fx_source, p.fx_rate, p.fx_rate_date, p.observed_at,
      CASE WHEN p.price_display IS NOT NULL AND (SELECT v FROM covered) > 0
           THEN round(p.price_display / (SELECT v FROM covered) * 100, 2) ELSE NULL END AS participation_pct,
      r.rnk::int AS ranking,
      (SELECT v FROM covered) AS set_covered_value,
      p.price_origin
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
    count(*) OVER() AS total_count,
    rows.price_origin
  FROM rows
  ORDER BY rows.collector_order ASC NULLS LAST
  LIMIT v_limit
  OFFSET v_offset;
END;
$function$;

COMMENT ON FUNCTION public.admin_get_pricing_report_set_cards(uuid, uuid, text, integer, integer) IS
  'Admin-only — lista paginada de cartas de um Set com preço/ranking/participação, com fallback de preço manual e price_origin (migration 3969).';

REVOKE ALL ON FUNCTION public.admin_get_pricing_report_set_cards(uuid, uuid, text, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_pricing_report_set_cards(uuid, uuid, text, integer, integer) TO authenticated;


-- -----------------------------------------------------------------------------
-- 4) admin_get_pricing_report_card — CREATE OR REPLACE
--    'current_prices' ganha 'price_origin' em cada item e um item MANUAL
--    (fonte/printing NULL) é anexado somente quando nenhum item automático
--    tiver price_display resolvido. 'history' permanece intocado (rule 5).
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.admin_get_pricing_report_card(
  p_card_id uuid,
  p_condition_id uuid DEFAULT NULL::uuid,
  p_currency text DEFAULT 'BRL'::text,
  p_history_days integer DEFAULT 90
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_condition_id uuid;
  v_history_days integer;
  v_result jsonb;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'ADMIN_GET_PRICING_REPORT_CARD_FORBIDDEN: acesso restrito a administradores.';
  END IF;

  IF p_currency NOT IN ('BRL', 'USD') THEN
    RAISE EXCEPTION 'ADMIN_GET_PRICING_REPORT_CARD_INVALID_CURRENCY: %', p_currency;
  END IF;

  IF p_condition_id IS NULL THEN
    SELECT id INTO v_condition_id FROM public.card_condition WHERE code = 'NM';
  ELSE
    SELECT id INTO v_condition_id FROM public.card_condition WHERE id = p_condition_id;
  END IF;

  IF v_condition_id IS NULL THEN
    RAISE EXCEPTION 'ADMIN_GET_PRICING_REPORT_CARD_CONDITION_NOT_FOUND: id=%', p_condition_id;
  END IF;

  v_history_days := LEAST(GREATEST(COALESCE(p_history_days, 90), 1), 365);

  WITH resolved_card AS (
    SELECT c.id, c.name, c.collector_number, c.collector_total, c.is_active,
           cs.id AS card_set_id, cs.code AS card_set_code, cs.name AS card_set_name
    FROM public.card c
    JOIN public.card_set cs ON cs.id = c.card_set_id
    WHERE c.id = p_card_id
  ),
  current_rows AS (
    SELECT DISTINCT ON (pcm.pricing_source_id, pp.source_printing_label)
      pcm.pricing_source_id, ps.code AS pricing_source_code,
      pp.source_printing_label AS printing_label,
      po.price, po.currency_code, po.observed_at
    FROM public.pricing_card_mapping pcm
    JOIN public.pricing_source ps ON ps.id = pcm.pricing_source_id AND ps.is_active = TRUE
    JOIN public.pricing_product pp ON pp.pricing_card_mapping_id = pcm.id AND pp.is_active = TRUE
    JOIN public.pricing_source_card_identity psci ON psci.id = pp.pricing_source_card_identity_id
       AND psci.identity_role = 'PRIMARY' AND psci.match_status = 'CONFIRMED'
    JOIN public.pricing_observation po ON po.pricing_product_id = pp.id
       AND po.condition_id = v_condition_id AND po.price_type = 'MARKET'
    WHERE pcm.card_id = p_card_id AND pcm.match_status = 'CONFIRMED'
    ORDER BY pcm.pricing_source_id, pp.source_printing_label,
             po.observed_at DESC, po.created_at DESC, po.id DESC
  ),
  current_with_fx AS (
    SELECT cr.*, fx.rate AS fx_rate, fx.rate_date AS fx_rate_date, fx.rate_source_code AS fx_rate_source,
      CASE WHEN cr.currency_code = p_currency THEN cr.price
           WHEN p_currency = 'BRL' AND cr.currency_code = 'USD' AND fx.rate IS NOT NULL
             THEN round(cr.price * fx.rate, 2)
           ELSE NULL END AS price_display
    FROM current_rows cr
    LEFT JOIN LATERAL (
      SELECT r.rate, r.rate_date, r.rate_source_code
      FROM public.pricing_fx_rate r
      WHERE cr.currency_code = 'USD' AND p_currency = 'BRL'
        AND r.from_currency = 'USD' AND r.to_currency = 'BRL' AND r.rate_source_code = 'BCB_PTAX'
        AND r.rate_date <= (cr.observed_at AT TIME ZONE 'UTC')::date
      ORDER BY r.rate_date DESC LIMIT 1
    ) fx ON TRUE
  ),
  -- ---- Fallback manual (novo em 3969): só entra quando NENHUM preço
  -- automático for utilizável (price_display resolvido) para a condição pedida ----
  manual_raw AS (
    SELECT mp.price, mp.currency_code, mp.observed_at
    FROM public.pricing_latest_manual_price(p_card_id, v_condition_id) mp
  ),
  manual_with_fx AS (
    SELECT mr.*, mfx.rate AS fx_rate, mfx.rate_date AS fx_rate_date
    FROM manual_raw mr
    LEFT JOIN LATERAL (
      SELECT r.rate, r.rate_date
      FROM public.pricing_fx_rate r
      WHERE mr.currency_code IS NOT NULL AND mr.currency_code <> p_currency
        AND r.from_currency = mr.currency_code AND r.to_currency = p_currency
        AND r.rate_source_code = 'BCB_PTAX'
        AND r.rate_date <= (mr.observed_at AT TIME ZONE 'UTC')::date
      ORDER BY r.rate_date DESC LIMIT 1
    ) mfx ON TRUE
  ),
  manual_usable AS (
    SELECT mf.*
    FROM manual_with_fx mf
    WHERE mf.price IS NOT NULL
      AND (mf.currency_code = p_currency OR mf.fx_rate IS NOT NULL)
      AND NOT EXISTS (SELECT 1 FROM current_with_fx cf WHERE cf.price_display IS NOT NULL)
  ),
  current_prices_combined AS (
    SELECT
      cf.pricing_source_id, cf.pricing_source_code, cf.printing_label,
      cf.price AS price_native, cf.currency_code AS currency_native,
      cf.price_display,
      CASE WHEN cf.currency_code = p_currency THEN 'NATIVE'
           WHEN p_currency = 'BRL' AND cf.currency_code = 'USD' AND cf.fx_rate IS NOT NULL THEN 'CONVERTED'
           WHEN p_currency = 'BRL' AND cf.currency_code = 'USD' THEN 'FX_RATE_UNAVAILABLE'
           ELSE 'UNSUPPORTED_CONVERSION' END AS fx_status,
      cf.fx_rate_source AS fx_source, cf.fx_rate, cf.fx_rate_date, cf.observed_at,
      'AUTOMATIC'::text AS price_origin
    FROM current_with_fx cf
    UNION ALL
    SELECT
      NULL::uuid, NULL::text, NULL::text,
      mu.price, mu.currency_code,
      CASE WHEN mu.currency_code = p_currency THEN mu.price ELSE round(mu.price * mu.fx_rate, 2) END,
      CASE WHEN mu.currency_code = p_currency THEN 'NATIVE' ELSE 'CONVERTED' END,
      CASE WHEN mu.fx_rate IS NOT NULL THEN 'BCB_PTAX' ELSE NULL END,
      mu.fx_rate, mu.fx_rate_date, mu.observed_at,
      'MANUAL'::text
    FROM manual_usable mu
  ),
  history_rows AS (
    SELECT
      pcm.pricing_source_id, ps.code AS pricing_source_code,
      pp.source_printing_label AS printing_label,
      po.price, po.currency_code, po.observed_at
    FROM public.pricing_card_mapping pcm
    JOIN public.pricing_source ps ON ps.id = pcm.pricing_source_id AND ps.is_active = TRUE
    JOIN public.pricing_product pp ON pp.pricing_card_mapping_id = pcm.id AND pp.is_active = TRUE
    JOIN public.pricing_source_card_identity psci ON psci.id = pp.pricing_source_card_identity_id
       AND psci.identity_role = 'PRIMARY' AND psci.match_status = 'CONFIRMED'
    JOIN public.pricing_observation po ON po.pricing_product_id = pp.id
       AND po.condition_id = v_condition_id AND po.price_type = 'MARKET'
    WHERE pcm.card_id = p_card_id AND pcm.match_status = 'CONFIRMED'
      AND po.observed_at >= now() - (v_history_days || ' days')::interval
  ),
  history_with_fx AS (
    SELECT hr.*, fx.rate AS fx_rate
    FROM history_rows hr
    LEFT JOIN LATERAL (
      SELECT r.rate
      FROM public.pricing_fx_rate r
      WHERE hr.currency_code = 'USD' AND p_currency = 'BRL'
        AND r.from_currency = 'USD' AND r.to_currency = 'BRL' AND r.rate_source_code = 'BCB_PTAX'
        AND r.rate_date <= (hr.observed_at AT TIME ZONE 'UTC')::date
      ORDER BY r.rate_date DESC LIMIT 1
    ) fx ON TRUE
  )
  SELECT jsonb_build_object(
    'card', jsonb_build_object(
      'id', rc.id, 'name', rc.name, 'collector_number', rc.collector_number,
      'collector_total', rc.collector_total, 'is_active', rc.is_active,
      'card_set_id', rc.card_set_id, 'card_set_code', rc.card_set_code, 'card_set_name', rc.card_set_name
    ),
    'condition', (SELECT jsonb_build_object('id', id, 'code', code, 'name', name)
                  FROM public.card_condition WHERE id = v_condition_id),
    'currency', p_currency,
    'history_days', v_history_days,
    'current_prices', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'pricing_source_id', cpc.pricing_source_id, 'pricing_source_code', cpc.pricing_source_code,
        'printing_label', cpc.printing_label, 'price_native', cpc.price_native, 'currency_native', cpc.currency_native,
        'price_display', cpc.price_display, 'fx_status', cpc.fx_status, 'fx_source', cpc.fx_source,
        'fx_rate', cpc.fx_rate, 'fx_rate_date', cpc.fx_rate_date, 'observed_at', cpc.observed_at,
        'price_origin', cpc.price_origin
      ) ORDER BY cpc.pricing_source_code NULLS LAST, cpc.printing_label NULLS LAST)
      FROM current_prices_combined cpc
    ), '[]'::jsonb),
    'history', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'pricing_source_id', hf.pricing_source_id, 'pricing_source_code', hf.pricing_source_code,
        'printing_label', hf.printing_label, 'price', hf.price, 'currency_code', hf.currency_code,
        'price_display', CASE WHEN hf.currency_code = p_currency THEN hf.price
                               WHEN p_currency = 'BRL' AND hf.currency_code = 'USD' AND hf.fx_rate IS NOT NULL
                                 THEN round(hf.price * hf.fx_rate, 2)
                               ELSE NULL END,
        'fx_status', CASE WHEN hf.currency_code = p_currency THEN 'NATIVE'
                          WHEN p_currency = 'BRL' AND hf.currency_code = 'USD' AND hf.fx_rate IS NOT NULL THEN 'CONVERTED'
                          WHEN p_currency = 'BRL' AND hf.currency_code = 'USD' THEN 'FX_RATE_UNAVAILABLE'
                          ELSE 'UNSUPPORTED_CONVERSION' END,
        'observed_at', hf.observed_at
      ) ORDER BY hf.observed_at)
      FROM history_with_fx hf
    ), '[]'::jsonb)
  ) INTO v_result
  FROM resolved_card rc;

  IF v_result IS NULL THEN
    RAISE EXCEPTION 'ADMIN_GET_PRICING_REPORT_CARD_NOT_FOUND: id=%', p_card_id;
  END IF;

  RETURN v_result;
END;
$function$;

COMMENT ON FUNCTION public.admin_get_pricing_report_card(uuid, uuid, text, integer) IS
  'Admin-only — snapshot de preços atuais + histórico de uma carta, com fallback de preço manual e price_origin em current_prices (migration 3969). history permanece inalterado.';

REVOKE ALL ON FUNCTION public.admin_get_pricing_report_card(uuid, uuid, text, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_pricing_report_card(uuid, uuid, text, integer) TO authenticated;


-- =============================================================================
-- Revision History
-- =============================================================================
-- | 1.0 | Criação e aplicação em 2026-08-27. Integra fallback de preço manual
-- |     | nas 4 superfícies de relatório/valuation do Pricing Admin, seguindo
-- |     | precedência automático > manual > sem preço, com price_origin
-- |     | propagado em todas as funções que expõem granularidade por carta
-- |     | (candidates, set_cards, current_prices de report_card). Validado
-- |     | transacionalmente (9 critérios) e pós-aplicação com dado real do
-- |     | Set MEE (8/8 cartas AUTOMATIC, estimated_value_covered=8.92 BRL,
-- |     | reconciliação exata Set×cartas) e grants confirmados via
-- |     | pg_proc.proacl (candidates=postgres-only; set_cards e card =
-- |     | authenticated+postgres, sem regressão). |
