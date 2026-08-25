-- Query 3943 — CONFIRMADO EXECUTADO (Bloco 5 — Central de Relatórios de Pricing Admin, V1,
-- 2026-08-23). Aplicada originalmente via Supabase MCP no mesmo dia; este arquivo foi
-- versionado retroativamente em 2026-08-24, numa micro-rodada de governança documental pedida
-- por Fabrício (gap já conhecido e documentado no cabeçalho da migration 3944, que redefine
-- parte desta função). SQL idêntico ao efetivamente aplicado, extraído diretamente de
-- `supabase_migrations.schema_migrations` (coluna `statements`, version `20260823012452`) —
-- fonte primária e autoritativa, não uma reconstrução por inferência. Nenhuma execução nova
-- realizada por este arquivo; nenhuma alteração de comportamento em relação ao que já está em
-- produção.
--
-- Nota: `admin_get_pricing_report_set` criada aqui foi posteriormente REDEFINIDA pela migration
-- 3944 (consumindo a helper `admin_pricing_report_set_price_candidates`, mesmo contrato) e sua
-- `ORDER BY` de listagem de cartas foi ajustada pela migration 3949 — ambas já versionadas. Já
-- `admin_get_pricing_report_card`, criada aqui, foi posteriormente REDEFINIDA pela migration
-- 3948 (conversão FX no histórico, ver esse arquivo). Este arquivo representa a versão
-- originalmente aplicada em 3943, não o estado atual das duas funções.
-- =============================================================================

/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 3943 - Pricing Admin: Central de Relatorios (Bloco 5, V1)
Versao......: 1.0
Status......: CANONICA
Autor.......: Claude (agente responsavel pela documentacao e schema)
Data........: 2026-08-23

Descricao...:
Duas RPCs de leitura agregada para a Central de Relatorios de Pricing
(/pricing/relatorios), V1 funcional: Preco por Carta e Valor por Set.
Contrato fechado por Fabricio: seletor de condicao (NM padrao), moeda
BRL padrao com USD opcional e transparencia de conversao cambial
(origem/cotacao/data), somente cartas ativas no calculo de Valor por
Set, ausencia de preco NUNCA tratada como zero, cobertura sempre
explicita, dados temporais reais (nao apenas snapshot) no relatorio
por carta.

Reaproveita o padrao de selecao por hierarquia de printing (Normal >
Holofoil > Reverse Holofoil > Unlimited > Unlimited Holofoil > 1st
Edition > 1st Edition Holofoil) e o padrao de conversao cambial via
pricing_fx_rate (BCB_PTAX) ja estabelecidos em
get_cards_pricing_summary (migrations 3903/3904/3918), agora
parametrizados por condicao (em vez de NM fixo) e com metadados de
FX explicitos na saida.

admin_get_pricing_report_card(p_card_id, p_condition_id, p_currency,
p_history_days): preco atual por fonte/printing + historico real
(janela 30/90/180/365 dias, padrao 90) na condicao selecionada.

admin_get_pricing_report_set(p_card_set_id, p_condition_id,
p_currency): valor estimado coberto (soma apenas dos precos
efetivamente convertiveis), cobertura percentual, quantidade sem
cotacao e quantidade com preco mas sem taxa de cambio disponivel
(nunca somada ao total), flag is_partial explicito.

Ambas SECURITY DEFINER, is_admin() obrigatorio, SET search_path TO
''; REVOKE ALL FROM PUBLIC + GRANT EXECUTE somente a authenticated.

Validacao de performance (EXPLAIN ANALYZE, testado transacionalmente
antes de aplicar): Preco por Carta ~poucos ms (card unico). Valor por
Set no maior Set confirmado hoje (ME2.5, 295 cartas ativas)
~650-1080ms — risco de performance aceito por Fabricio para esta V1
(relatorio sob demanda, sem otimizacao preventiva). Debito registrado:
pricing_observation e append-only (P13) e o custo do latest-price por
carta tende a crescer com o historico acumulado. Gatilho de revisao
futura definido por Fabricio: ~2s no maior Set suportado.
================================================================
*/

CREATE OR REPLACE FUNCTION public.admin_get_pricing_report_card(
  p_card_id uuid,
  p_condition_id uuid DEFAULT NULL,
  p_currency text DEFAULT 'BRL',
  p_history_days integer DEFAULT 90
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
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
        'pricing_source_id', hr.pricing_source_id, 'pricing_source_code', hr.pricing_source_code,
        'printing_label', hr.printing_label, 'price', hr.price, 'currency_code', hr.currency_code,
        'observed_at', hr.observed_at
      ) ORDER BY hr.observed_at) FROM history_rows hr), '[]'::jsonb)
  ) INTO v_result
  FROM resolved_card rc;

  IF v_result IS NULL THEN
    RAISE EXCEPTION 'ADMIN_GET_PRICING_REPORT_CARD_NOT_FOUND: id=%', p_card_id;
  END IF;

  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_get_pricing_report_card(uuid, uuid, text, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_pricing_report_card(uuid, uuid, text, integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_get_pricing_report_set(
  p_card_set_id uuid,
  p_condition_id uuid DEFAULT NULL,
  p_currency text DEFAULT 'BRL'
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
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
  candidate_by_printing AS (
    SELECT DISTINCT ON (ac.card_id, pp.source_printing_label)
      ac.card_id, pp.source_printing_label, po.price, po.currency_code, po.observed_at
    FROM active_cards ac
    JOIN public.pricing_card_mapping pcm ON pcm.card_id = ac.card_id AND pcm.match_status = 'CONFIRMED'
    JOIN public.pricing_source ps ON ps.id = pcm.pricing_source_id AND ps.is_active = TRUE
    JOIN public.pricing_product pp ON pp.pricing_card_mapping_id = pcm.id AND pp.is_active = TRUE
       AND pp.source_printing_label IN ('Normal','Holofoil','Reverse Holofoil','Unlimited','Unlimited Holofoil','1st Edition','1st Edition Holofoil')
    JOIN public.pricing_source_card_identity psci ON psci.id = pp.pricing_source_card_identity_id
       AND psci.identity_role = 'PRIMARY' AND psci.match_status = 'CONFIRMED'
    JOIN public.pricing_observation po ON po.pricing_product_id = pp.id
       AND po.condition_id = v_condition_id AND po.price_type = 'MARKET'
    ORDER BY ac.card_id, pp.source_printing_label, po.observed_at DESC, po.created_at DESC, po.id DESC
  ),
  candidate AS (
    SELECT DISTINCT ON (cbp.card_id)
      cbp.card_id, cbp.source_printing_label, cbp.price, cbp.currency_code, cbp.observed_at
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
  ),
  priced AS (
    SELECT
      cf.card_id,
      CASE WHEN cf.currency_code = p_currency THEN cf.price
           WHEN p_currency = 'BRL' AND cf.currency_code = 'USD' AND cf.fx_rate IS NOT NULL THEN round(cf.price * cf.fx_rate, 2)
           ELSE NULL END AS price_display,
      (cf.currency_code <> p_currency AND NOT (p_currency = 'BRL' AND cf.currency_code = 'USD' AND cf.fx_rate IS NOT NULL)) AS fx_blocked
    FROM candidate_with_fx cf
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
    'no_price_count', (SELECT count(*) FROM active_cards ac WHERE NOT EXISTS (SELECT 1 FROM candidate c WHERE c.card_id = ac.card_id)),
    'coverage_pct', CASE WHEN (SELECT count(*) FROM active_cards) = 0 THEN 0
        ELSE round((SELECT count(*) FROM priced WHERE price_display IS NOT NULL)::numeric
                    / (SELECT count(*) FROM active_cards)::numeric * 100, 2) END,
    'estimated_value_covered', COALESCE((SELECT sum(price_display) FROM priced WHERE price_display IS NOT NULL), 0),
    'is_partial', (SELECT count(*) FROM priced WHERE price_display IS NOT NULL) < (SELECT count(*) FROM active_cards)
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_get_pricing_report_set(uuid, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_pricing_report_set(uuid, uuid, text) TO authenticated;
