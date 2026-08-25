-- Query 3948 — CONFIRMADO EXECUTADO (Central de Relatórios de Pricing Admin — correção de
-- conversão FX no histórico do relatório "Preço por Carta", 2026-08-23). Aplicada originalmente
-- via Supabase MCP no mesmo dia; este arquivo foi versionado retroativamente em 2026-08-24, numa
-- micro-rodada de governança documental pedida por Fabrício (gap já conhecido e documentado em
-- `docs/05f-pricing.md`, seção "Estado Atual do Pricing — Síntese Executiva", item D/E). SQL
-- idêntico ao efetivamente aplicado, extraído diretamente de
-- `supabase_migrations.schema_migrations` (coluna `statements`, version `20260823182330`) —
-- fonte primária e autoritativa, não uma reconstrução por inferência. Conteúdo confirmado
-- também por Fabrício em chat na mesma rodada de reconciliação (2026-08-23), antes da consulta
-- direta ao Supabase ter sido feita; ambas as fontes coincidem integralmente, sem divergência.
-- Nenhuma execução nova realizada por este arquivo; nenhuma alteração de comportamento em
-- relação ao que já está em produção.
--
-- Contexto: antes desta migration, o preço ATUAL da carta em `admin_get_pricing_report_card`
-- (criada pela migration 3943) já podia ser exibido convertido para BRL, mas o HISTÓRICO do
-- gráfico continuava usando sempre o preço nativo em USD — inconsistência real percebida por
-- Fabrício ao selecionar BRL no relatório "Preço por Carta" (preço atual em BRL, gráfico em
-- USD). Esta migration REDEFINE `admin_get_pricing_report_card` para aplicar ao array `history`
-- exatamente a mesma lógica de conversão cambial já usada no array `current_prices`:
--
--   - `price`/`currency_code` nativos de cada observação histórica são preservados sem alteração;
--   - cada ponto do histórico ganha `price_display` (preço convertido para a moeda pedida, ou o
--     próprio preço nativo quando já está na moeda pedida);
--   - cada ponto do histórico ganha `fx_status` explícito
--     (`NATIVE`/`CONVERTED`/`FX_RATE_UNAVAILABLE`/`UNSUPPORTED_CONVERSION`);
--   - a conversão de cada ponto histórico usa a `pricing_fx_rate` (`BCB_PTAX`) cuja `rate_date`
--     é a mais recente ANTERIOR OU IGUAL à data da PRÓPRIA observação (`hr.observed_at`) — nunca
--     a cotação atual/mais recente aplicada retroativamente a preços antigos, mesmo padrão de
--     `LEFT JOIN LATERAL` já usado em `current_with_fx` (migration 3943), agora replicado como
--     `history_with_fx`;
--   - quando não há taxa PTAX aplicável para a data daquele ponto, `price_display` fica `NULL` e
--     `fx_status = 'FX_RATE_UNAVAILABLE'` — nunca tratado silenciosamente como zero ou omitido.
--
-- Único objeto alterado: `admin_get_pricing_report_card` (CTE nova `history_with_fx`; bloco
-- `history` do `jsonb_build_object` final passa a expor `price_display`/`fx_status` por ponto,
-- além dos campos nativos já existentes). `admin_get_pricing_report_set` (também criada pela
-- 3943) não é tocada por esta migration. Assinatura, `SECURITY DEFINER`, `is_admin()` obrigatório
-- e `SET search_path TO ''` preservados sem alteração — mesmo contrato de acesso da 3943.
-- Consumidores de frontend (`price-history-chart.tsx`, `preco-por-carta-report.tsx`) passaram a
-- usar `price_display` no gráfico, tooltip, labels finais e cálculo de variação, em vez do preço
-- nativo. Ver `docs/05f-pricing.md`, seção "Estado Atual do Pricing — Síntese Executiva", item E,
-- para o detalhamento funcional completo (relatório "Preço por Carta" aprovado por Fabrício em
-- 2026-08-23).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.admin_get_pricing_report_card(p_card_id uuid, p_condition_id uuid DEFAULT NULL::uuid, p_currency text DEFAULT 'BRL'::text, p_history_days integer DEFAULT 90)
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
    ORDER BY pcm.pricing_source_id, pp.source_printing_label, po.observed_at DESC, po.created_at DESC, po.id DESC
  ),
  current_with_fx AS (
    SELECT cr.*, fx.rate AS fx_rate, fx.rate_date AS fx_rate_date, fx.rate_source_code AS fx_rate_source
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
  history_rows AS (
    SELECT pcm.pricing_source_id, ps.code AS pricing_source_code,
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
      AND po.observed_at >= (now() - make_interval(days => v_history_days))
  ),
  history_with_fx AS (
    SELECT hr.*, fx.rate AS fx_rate, fx.rate_date AS fx_rate_date, fx.rate_source_code AS fx_rate_source
    FROM history_rows hr
    LEFT JOIN LATERAL (
      SELECT r.rate, r.rate_date, r.rate_source_code
      FROM public.pricing_fx_rate r
      WHERE hr.currency_code = 'USD' AND p_currency = 'BRL'
        AND r.from_currency = 'USD' AND r.to_currency = 'BRL' AND r.rate_source_code = 'BCB_PTAX'
        AND r.rate_date <= (hr.observed_at AT TIME ZONE 'UTC')::date
      ORDER BY r.rate_date DESC LIMIT 1
    ) fx ON TRUE
  )
  SELECT jsonb_build_object(
    'card', jsonb_build_object('id', rc.id, 'name', rc.name, 'collector_number', rc.collector_number,
       'collector_total', rc.collector_total, 'is_active', rc.is_active,
       'card_set_id', rc.card_set_id, 'card_set_code', rc.card_set_code, 'card_set_name', rc.card_set_name),
    'condition', jsonb_build_object('id', v_condition_id,
       'code', (SELECT code FROM public.card_condition WHERE id = v_condition_id),
       'name', (SELECT name FROM public.card_condition WHERE id = v_condition_id)),
    'currency', p_currency,
    'history_days', v_history_days,
    'current_prices', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'pricing_source_id', cf.pricing_source_id, 'pricing_source_code', cf.pricing_source_code,
        'printing_label', cf.printing_label, 'price_native', cf.price, 'currency_native', cf.currency_code,
        'price_display', CASE WHEN cf.currency_code = p_currency THEN cf.price
                               WHEN p_currency = 'BRL' AND cf.currency_code = 'USD' AND cf.fx_rate IS NOT NULL THEN round(cf.price * cf.fx_rate, 2)
                               ELSE NULL END,
        'fx_status', CASE WHEN cf.currency_code = p_currency THEN 'NATIVE'
                          WHEN p_currency = 'BRL' AND cf.currency_code = 'USD' AND cf.fx_rate IS NOT NULL THEN 'CONVERTED'
                          WHEN p_currency = 'BRL' AND cf.currency_code = 'USD' THEN 'FX_RATE_UNAVAILABLE'
                          ELSE 'UNSUPPORTED_CONVERSION' END,
        'fx_source', cf.fx_rate_source, 'fx_rate', cf.fx_rate, 'fx_rate_date', cf.fx_rate_date,
        'observed_at', cf.observed_at
      ) ORDER BY cf.pricing_source_code, cf.printing_label) FROM current_with_fx cf), '[]'::jsonb),
    'history', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'pricing_source_id', hf.pricing_source_id, 'pricing_source_code', hf.pricing_source_code,
        'printing_label', hf.printing_label, 'price', hf.price, 'currency_code', hf.currency_code,
        'price_display', CASE WHEN hf.currency_code = p_currency THEN hf.price
                               WHEN p_currency = 'BRL' AND hf.currency_code = 'USD' AND hf.fx_rate IS NOT NULL THEN round(hf.price * hf.fx_rate, 2)
                               ELSE NULL END,
        'fx_status', CASE WHEN hf.currency_code = p_currency THEN 'NATIVE'
                          WHEN p_currency = 'BRL' AND hf.currency_code = 'USD' AND hf.fx_rate IS NOT NULL THEN 'CONVERTED'
                          WHEN p_currency = 'BRL' AND hf.currency_code = 'USD' THEN 'FX_RATE_UNAVAILABLE'
                          ELSE 'UNSUPPORTED_CONVERSION' END,
        'observed_at', hf.observed_at
      ) ORDER BY hf.observed_at) FROM history_with_fx hf), '[]'::jsonb)
  ) INTO v_result
  FROM resolved_card rc;

  IF v_result IS NULL THEN
    RAISE EXCEPTION 'ADMIN_GET_PRICING_REPORT_CARD_NOT_FOUND: id=%', p_card_id;
  END IF;

  RETURN v_result;
END;
$function$;
