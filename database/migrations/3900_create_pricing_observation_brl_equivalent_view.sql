-- Query 3900 — CONFIRMADO EXECUTADO (Incremento P10, 2026-08-17)
-- Projeção de leitura: equivalente em BRL de observações de preço em USD, usando a
-- última pricing_fx_rate USD->BRL/BCB_PTAX com rate_date <= data efetiva (UTC) de
-- observed_at. Nunca altera pricing_observation (view, sem escrita). security_invoker
-- = true: a view não amplia privilégio nenhum — para o papel que efetivamente executa
-- a consulta, a RLS de pricing_observation/pricing_fx_rate (policy pricing_admin_select
-- em ambas) é aplicada normalmente, exatamente como se a consulta fosse feita direto
-- nas tabelas base. Escopo restrito a currency_code = 'USD': observações já em BRL
-- (se um dia existirem) nunca passam por esta projeção — impossibilidade estrutural
-- de dupla conversão.

CREATE VIEW public.pricing_observation_brl_equivalent
WITH (security_invoker = true) AS
SELECT
    po.id                       AS pricing_observation_id,
    po.pricing_product_id,
    po.condition_id,
    po.price_type,
    po.price                    AS original_amount,
    po.currency_code            AS original_currency_code,
    po.observed_at,
    fx.rate                     AS fx_rate,
    fx.rate_date                AS fx_rate_date,
    fx.rate_source_code         AS fx_source_code,
    CASE WHEN fx.rate IS NOT NULL
         THEN round(po.price * fx.rate, 2)
         ELSE NULL
    END                         AS equivalent_brl_amount,
    CASE WHEN fx.rate IS NOT NULL
         THEN 'CONVERTED'
         ELSE 'FX_RATE_UNAVAILABLE'
    END                         AS fx_status,
    CASE WHEN fx.rate IS NOT NULL
         THEN 'Equivalente em BRL pela PTAX Venda'
         ELSE NULL
    END                         AS equivalent_label
FROM public.pricing_observation po
LEFT JOIN LATERAL (
    SELECT r.rate, r.rate_date, r.rate_source_code
    FROM public.pricing_fx_rate r
    WHERE r.from_currency = 'USD'
      AND r.to_currency = 'BRL'
      AND r.rate_source_code = 'BCB_PTAX'
      AND r.rate_date <= (po.observed_at AT TIME ZONE 'UTC')::date
    ORDER BY r.rate_date DESC
    LIMIT 1
) fx ON TRUE
WHERE po.currency_code = 'USD';

COMMENT ON VIEW public.pricing_observation_brl_equivalent IS
'Projeção de leitura (Incremento P10, ADR-029): equivalente em BRL de observações USD via última pricing_fx_rate (BCB_PTAX) com rate_date <= data UTC de observed_at. Nunca usar taxa futura. Rótulo obrigatório ao exibir: "Equivalente em BRL pela PTAX Venda" — nunca "Valor Brasil" (conceito distinto, ver pricing_observation.market_scope/market_evidence_confirmed). Sem taxa aplicável: equivalent_brl_amount NULL e fx_status = FX_RATE_UNAVAILABLE. security_invoker=true — não amplia acesso além do já concedido em pricing_observation/pricing_fx_rate.';

GRANT SELECT ON public.pricing_observation_brl_equivalent TO authenticated;
GRANT SELECT ON public.pricing_observation_brl_equivalent TO service_role;
