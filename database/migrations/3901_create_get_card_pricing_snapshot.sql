-- Query 3901 — CONFIRMADO EXECUTADO (Incremento P11, 2026-08-17)
-- Contrato seguro de leitura de preços por card_id para o frontend, mesmo padrão de
-- ADR-030 (search_cards()/search_card_filter_options()): função SECURITY DEFINER em
-- public, verificação explícita de auth.uid() IS NOT NULL (nunca is_admin()), REVOKE
-- ALL FROM PUBLIC/anon + GRANT EXECUTE só a authenticated. Bypassa deliberadamente a
-- policy pricing_admin_select das tabelas base (só assim um usuário autenticado comum
-- consegue ler Pricing) mas nunca expõe as tabelas brutas diretamente — o único caminho
-- de leitura para authenticated não-admin é esta função, com projeção estritamente
-- curada (nunca external_product_id, raw_payload ou histórico completo).
--
-- Filtros de negócio obrigatórios, todos aplicados no corpo da função (não pela RLS,
-- que esta função contorna por desenho): pricing_card_mapping.match_status = 'CONFIRMED',
-- pricing_product.is_active = TRUE, pricing_source.is_active = TRUE. Hoje, is_active =
-- FALSE na única fonte cadastrada (JUSTTCG) — o contrato retorna zero linhas em produção
-- até uma licença comercial ser contratada e a fonte ser reativada (ADR-029).
--
-- Snapshot mais recente por produto/condição/tipo de preço/mercado: DISTINCT ON com
-- ORDER BY observed_at DESC, created_at DESC, id DESC (desempate determinístico) sobre
-- o próprio índice ix_pricing_observation_latest_lookup (pricing_product_id, condition_id,
-- price_type, observed_at DESC), sem escanear o histórico completo da tabela para além
-- do necessário. Equivalente BRL reaproveita exatamente a mesma regra do Incremento P10
-- (última pricing_fx_rate BCB_PTAX com rate_date <= data UTC de observed_at, nunca taxa
-- futura, rótulo fixo "Equivalente em BRL pela PTAX Venda") — restrito a
-- currency_code = 'USD', única moeda real observada e único par cambial modelado em
-- pricing_fx_rate hoje; outras moedas retornam fx_status = 'FX_RATE_UNAVAILABLE'.

CREATE OR REPLACE FUNCTION public.get_card_pricing_snapshot(p_card_id uuid)
RETURNS TABLE (
    pricing_source_code    text,
    pricing_source_name    text,
    price_type              text,
    original_amount         numeric,
    original_currency_code  text,
    equivalent_brl_amount   numeric,
    fx_status                text,
    fx_rate                  numeric,
    fx_rate_date              date,
    equivalent_label          text,
    condition_code            text,
    condition_name             text,
    printing_label              text,
    market_label                text,
    observed_at                  timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'PRICING_SNAPSHOT_REQUIRES_AUTHENTICATION'
            USING ERRCODE = '28000';
    END IF;

    RETURN QUERY
    WITH latest AS (
        SELECT DISTINCT ON (po.pricing_product_id, po.condition_id, po.price_type, po.market_label)
            po.pricing_product_id,
            po.condition_id,
            po.price_type,
            po.price,
            po.currency_code,
            po.market_label,
            po.observed_at,
            pp.source_printing_label,
            ps.code   AS source_code,
            ps.name   AS source_name,
            ps.source_order
        FROM public.pricing_observation po
        JOIN public.pricing_product pp
            ON pp.id = po.pricing_product_id
           AND pp.is_active = TRUE
        JOIN public.pricing_card_mapping pcm
            ON pcm.id = pp.pricing_card_mapping_id
           AND pcm.match_status = 'CONFIRMED'
        JOIN public.pricing_source ps
            ON ps.id = pcm.pricing_source_id
           AND ps.is_active = TRUE
        WHERE pcm.card_id = p_card_id
        ORDER BY
            po.pricing_product_id, po.condition_id, po.price_type, po.market_label,
            po.observed_at DESC, po.created_at DESC, po.id DESC
    )
    SELECT
        l.source_code,
        l.source_name,
        l.price_type,
        l.price,
        l.currency_code,
        CASE WHEN fx.rate IS NOT NULL THEN round(l.price * fx.rate, 2) ELSE NULL END,
        CASE WHEN fx.rate IS NOT NULL THEN 'CONVERTED' ELSE 'FX_RATE_UNAVAILABLE' END,
        fx.rate,
        fx.rate_date,
        CASE WHEN fx.rate IS NOT NULL THEN 'Equivalente em BRL pela PTAX Venda' ELSE NULL END,
        cc.code,
        cc.name,
        l.source_printing_label,
        l.market_label,
        l.observed_at
    FROM latest l
    JOIN public.card_condition cc ON cc.id = l.condition_id
    LEFT JOIN LATERAL (
        SELECT r.rate, r.rate_date
        FROM public.pricing_fx_rate r
        WHERE l.currency_code = 'USD'
          AND r.from_currency = 'USD'
          AND r.to_currency = 'BRL'
          AND r.rate_source_code = 'BCB_PTAX'
          AND r.rate_date <= (l.observed_at AT TIME ZONE 'UTC')::date
        ORDER BY r.rate_date DESC
        LIMIT 1
    ) fx ON TRUE
    ORDER BY
        cc.condition_order, l.price_type, l.market_label NULLS LAST,
        l.source_order, l.source_printing_label, l.pricing_product_id;
END;
$$;

COMMENT ON FUNCTION public.get_card_pricing_snapshot(uuid) IS
'Contrato seguro de leitura de preços por card_id (Incremento P11, ADR-029): snapshot mais recente por produto/condição/tipo de preço/mercado, com equivalente BRL pela última PTAX Venda (Incremento P10). SECURITY DEFINER, auth.uid() IS NOT NULL (nunca is_admin()) — qualquer usuário autenticado, sem exigir perfil administrativo. Só retorna mapping CONFIRMED, produto ativo e fonte ativa. Nunca expõe external_product_id, raw_payload ou histórico completo. Tabelas brutas de Pricing continuam inacessíveis fora desta função (RLS pricing_admin_select/card_condition_admin_select inalteradas).';

REVOKE ALL ON FUNCTION public.get_card_pricing_snapshot(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_card_pricing_snapshot(uuid) TO authenticated;
