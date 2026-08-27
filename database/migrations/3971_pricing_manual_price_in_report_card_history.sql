-- Query 3971 — Incluir pricing_manual_price no histórico de
-- admin_get_pricing_report_card (Relatório "Preço por Carta").
-- Status: CONFIRMADO EXECUTADO em 2026-08-27 via Supabase MCP (apply_migration).
--
-- Contexto: Fabrício reportou gap funcional — "Preços atuais" já suporta
-- MANUAL (migration 3969), mas o gráfico de Histórico de Preço ignora
-- pricing_manual_price por completo (CTEs history_rows/history_with_fx só
-- liam pricing_observation). Carta com preço manual vigente e zero
-- observação automática recente exibia "Sem histórico no período
-- selecionado", apesar de "Preços atuais" mostrar MANUAL corretamente.
--
-- Mudança (função RETORNA jsonb — CREATE OR REPLACE, sem DROP, preserva
-- grants existentes): duas novas CTEs paralelas às automáticas —
-- manual_history_rows (linhas REAIS append-only de pricing_manual_price,
-- filtradas por card_id + condition_id = v_condition_id + observed_at
-- dentro de v_history_days — nunca só a última linha, diferente de
-- manual_raw/current que usa pricing_latest_manual_price()) e
-- manual_history_with_fx (câmbio genérico via pricing_fx_rate/BCB_PTAX para
-- qualquer par de moeda, mesmo padrão já usado para MANUAL em
-- current_prices_combined e em admin_get_pricing_report_set_cards, migration
-- 3969 — não o hardcode USD->BRL usado para AUTOMATIC). Nova CTE
-- history_combined faz UNION ALL de history_with_fx (tag AUTOMATIC) com
-- manual_history_with_fx (tag MANUAL) — cada item do jsonb 'history' ganha
-- o campo novo 'price_origin'. Histórico representa OBSERVAÇÕES, não só o
-- valor vigente: automático e manual podem coexistir no mesmo período
-- (deliberadamente SEM a exclusividade "NOT EXISTS automático usável" que
-- current_prices_combined aplica para decidir o preço VIGENTE).
--
-- Intocado neste ciclo: current_rows/current_with_fx/manual_raw/
-- manual_with_fx/manual_usable/current_prices_combined (cálculo do preço
-- atual e precedência AUTOMATIC > MANUAL, byte-idênticos); history_rows/
-- history_with_fx (histórico automático, byte-idênticos). Nenhuma outra
-- RPC alterada.
--
-- Testado transacionalmente (BEGIN/ROLLBACK) com carta real com histórico
-- automático genuíno (Flareon, SV8.5, condição NM — 30 observações reais
-- 2026-08-20..27) + 2 linhas manuais sintéticas inseridas em datas
-- distintas (15 e 5 dias atrás): (1) current_prices permanece 100%
-- AUTOMATIC (precedência intacta, manual não usado como vigente pois
-- automático usável existe); (2) history com período 90d retorna 16
-- AUTOMATIC + 2 MANUAL nas datas corretas, price_display/fx_status
-- corretos (NATIVE, mesma moeda); (3) período 7d retorna exatamente 1 ponto
-- MANUAL (só o de 5 dias atrás, excluindo o de 15) — filtro de período
-- funcional; (4) condição diferente (LP) retorna 0 pontos MANUAL — filtro
-- de condição funcional; (5) contagem automática (16) idêntica em todos os
-- testes — zero regressão no histórico automático. Nenhuma linha real foi
-- gravada em produção (INSERT + checagens dentro da mesma transação,
-- revertida por ROLLBACK).
--
-- Validado pós-aplicação real (fora de transação de teste): grants
-- preservados (authenticated + owner, sem PUBLIC/anon); chamada real
-- autenticada contra Flareon/NM/90d retorna history_count=16, 100%
-- AUTOMATIC (produção não tem nenhuma linha em pricing_manual_price hoje —
-- comportamento idêntico ao pré-migration, zero regressão confirmada).

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
  ),
  manual_history_rows AS (
    SELECT mp.price, mp.currency_code, mp.observed_at
    FROM public.pricing_manual_price mp
    WHERE mp.card_id = p_card_id
      AND mp.condition_id = v_condition_id
      AND mp.observed_at >= now() - (v_history_days || ' days')::interval
  ),
  manual_history_with_fx AS (
    SELECT mh.*, fx.rate AS fx_rate
    FROM manual_history_rows mh
    LEFT JOIN LATERAL (
      SELECT r.rate
      FROM public.pricing_fx_rate r
      WHERE mh.currency_code IS NOT NULL AND mh.currency_code <> p_currency
        AND r.from_currency = mh.currency_code AND r.to_currency = p_currency
        AND r.rate_source_code = 'BCB_PTAX'
        AND r.rate_date <= (mh.observed_at AT TIME ZONE 'UTC')::date
      ORDER BY r.rate_date DESC LIMIT 1
    ) fx ON TRUE
  ),
  history_combined AS (
    SELECT
      hf.pricing_source_id, hf.pricing_source_code, hf.printing_label,
      hf.price, hf.currency_code, hf.observed_at, hf.fx_rate,
      'AUTOMATIC'::text AS price_origin
    FROM history_with_fx hf
    UNION ALL
    SELECT
      NULL::uuid, NULL::text, NULL::text,
      mh.price, mh.currency_code, mh.observed_at, mh.fx_rate,
      'MANUAL'::text
    FROM manual_history_with_fx mh
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
        'pricing_source_id', hc.pricing_source_id, 'pricing_source_code', hc.pricing_source_code,
        'printing_label', hc.printing_label, 'price', hc.price, 'currency_code', hc.currency_code,
        'price_display', CASE WHEN hc.currency_code = p_currency THEN hc.price
                               WHEN hc.fx_rate IS NOT NULL THEN round(hc.price * hc.fx_rate, 2)
                               ELSE NULL END,
        'fx_status', CASE WHEN hc.currency_code = p_currency THEN 'NATIVE'
                          WHEN hc.price_origin = 'MANUAL' THEN
                            (CASE WHEN hc.fx_rate IS NOT NULL THEN 'CONVERTED' ELSE 'FX_RATE_UNAVAILABLE' END)
                          WHEN p_currency = 'BRL' AND hc.currency_code = 'USD' AND hc.fx_rate IS NOT NULL THEN 'CONVERTED'
                          WHEN p_currency = 'BRL' AND hc.currency_code = 'USD' THEN 'FX_RATE_UNAVAILABLE'
                          ELSE 'UNSUPPORTED_CONVERSION' END,
        'observed_at', hc.observed_at,
        'price_origin', hc.price_origin
      ) ORDER BY hc.observed_at)
      FROM history_combined hc
    ), '[]'::jsonb)
  ) INTO v_result
  FROM resolved_card rc;

  IF v_result IS NULL THEN
    RAISE EXCEPTION 'ADMIN_GET_PRICING_REPORT_CARD_NOT_FOUND: id=%', p_card_id;
  END IF;

  RETURN v_result;
END;
$function$;
