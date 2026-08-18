-- Query 3903 — CONFIRMADO EXECUTADO (Incremento P12 v4, 2026-08-18)
-- Variante em lote de get_card_pricing_snapshot (3901, Incremento P11): resolve o resumo
-- de preço de N cartas numa única consulta SQL, eliminando o N+1 real (servidor->Postgres)
-- que a primeira versão do endpoint batch (`POST /api/cards/pricing/batch`, sem migration)
-- ainda tinha — chamava get_card_pricing_snapshot uma vez por carta, em paralelo
-- (Promise.all no servidor): resolvia o N+1 cliente->servidor (uma única requisição do
-- navegador), mas não o N+1 servidor->Postgres (ainda N consultas). Fabrício apontou que
-- esse N+1 real continuava existindo e pediu esta função.
--
-- Mesmo padrão de segurança de get_card_pricing_snapshot: SECURITY DEFINER, verificação
-- explícita de auth.uid() IS NOT NULL (nunca is_admin()), REVOKE ALL FROM PUBLIC + GRANT
-- EXECUTE só a authenticated. Dois guards de validação de entrada adicionais, que
-- get_card_pricing_snapshot não precisa por operar sobre um único card_id: array vazio/nulo
-- (PRICING_SUMMARY_EMPTY_INPUT) e mais de 100 elementos (PRICING_SUMMARY_TOO_MANY_CARD_IDS)
-- — o teto de 100 é um limite duro da função, não só uma convenção do chamador (o Route
-- Handler em web/app/api/cards/pricing/batch/route.ts também aplica MAX_CARD_IDS = 100,
-- mas a função rejeita de qualquer forma se for chamada diretamente com mais).
--
-- Retorno deliberadamente mínimo (card_id, has_pricing, brl_amount, fx_status), pedido
-- explícito de Fabrício ("retorno mínimo") — ao contrário de get_card_pricing_snapshot, que
-- devolve o detalhe completo por condição/tipo de preço/mercado, esta função já resolve a
-- seleção de UMA linha por carta, sob uma regra de negócio fixa e determinística: condição
-- NM (card_condition.code = 'NM'), printing "Normal" (pricing_product.source_printing_label
-- = 'Normal'), price_type = 'MARKET'. Não é uma heurística de "melhor preço" — é sempre essa
-- combinação específica, pedido literal de Fabrício ("valor BRL padrão NM/Normal").
--
-- Consequência real desta regra fixa, não um bug: cartas cujo único printing catalogado é
-- Holofoil (ex.: cartas "ex" quase sempre holo-exclusivas na origem dos dados) nunca têm
-- has_pricing = true por esta função, mesmo tendo preço real sob o printing Holofoil —
-- confirmado com os 6 cards piloto do Incremento P8: Abra/Arcanine/Bulbasaur têm produto
-- "Normal" e resolvem; Alakazam/Mega Gardevoir ex/Mega Venusaur ex são Holofoil-only e
-- sempre retornam has_pricing = false por esta regra.
--
-- Mesmos filtros de negócio de get_card_pricing_snapshot, agora aplicados no CTE `candidate`:
-- pricing_card_mapping.match_status = 'CONFIRMED', pricing_product.is_active = TRUE,
-- pricing_source.is_active = TRUE — fonte inativa (JUSTTCG hoje) resulta em has_pricing =
-- false para todas as cartas em produção, sem exceção, até uma licença comercial ser
-- contratada (ADR-029).
--
-- Desenho da consulta: `input_ids` (DISTINCT unnest de p_card_ids) LEFT JOIN `candidate`
-- (DISTINCT ON (card_id), uma linha de observação mais recente por carta que satisfaz a
-- regra NM+Normal+MARKET) LEFT JOIN LATERAL para a taxa PTAX aplicável (mesma lógica de
-- get_card_pricing_snapshot, restrita a currency_code = 'USD') — LEFT JOIN garante
-- exatamente uma linha de saída por card_id de entrada, mesmo para cartas sem qualquer
-- observação. Validado via EXPLAIN (ANALYZE, BUFFERS) com 100 card_id reais: 12,9ms, um
-- único Function Scan, sem laço.

CREATE OR REPLACE FUNCTION public.get_cards_pricing_summary(p_card_ids uuid[])
RETURNS TABLE (
    card_id      uuid,
    has_pricing  boolean,
    brl_amount   numeric,
    fx_status    text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'PRICING_SUMMARY_REQUIRES_AUTHENTICATION'
            USING ERRCODE = '28000';
    END IF;

    IF p_card_ids IS NULL OR array_length(p_card_ids, 1) IS NULL THEN
        RAISE EXCEPTION 'PRICING_SUMMARY_EMPTY_INPUT'
            USING ERRCODE = '22023';
    END IF;

    IF array_length(p_card_ids, 1) > 100 THEN
        RAISE EXCEPTION 'PRICING_SUMMARY_TOO_MANY_CARD_IDS'
            USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    WITH input_ids AS (
        SELECT DISTINCT input_id FROM unnest(p_card_ids) AS input_id
    ),
    candidate AS (
        SELECT DISTINCT ON (pcm.card_id)
            pcm.card_id,
            po.price,
            po.currency_code,
            po.observed_at
        FROM public.pricing_card_mapping pcm
        JOIN public.pricing_product pp
            ON pp.pricing_card_mapping_id = pcm.id
           AND pp.is_active = TRUE
           AND pp.source_printing_label = 'Normal'
        JOIN public.pricing_source ps
            ON ps.id = pcm.pricing_source_id
           AND ps.is_active = TRUE
        JOIN public.pricing_observation po
            ON po.pricing_product_id = pp.id
           AND po.price_type = 'MARKET'
        JOIN public.card_condition cc
            ON cc.id = po.condition_id
           AND cc.code = 'NM'
        WHERE pcm.match_status = 'CONFIRMED'
          AND pcm.card_id IN (SELECT input_id FROM input_ids)
        ORDER BY pcm.card_id, po.observed_at DESC, po.created_at DESC, po.id DESC
    )
    SELECT
        ii.input_id AS card_id,
        (fx.rate IS NOT NULL) AS has_pricing,
        CASE WHEN fx.rate IS NOT NULL THEN round(c.price * fx.rate, 2) ELSE NULL END AS brl_amount,
        CASE
            WHEN c.card_id IS NULL THEN NULL
            WHEN fx.rate IS NOT NULL THEN 'CONVERTED'
            ELSE 'FX_RATE_UNAVAILABLE'
        END AS fx_status
    FROM input_ids ii
    LEFT JOIN candidate c ON c.card_id = ii.input_id
    LEFT JOIN LATERAL (
        SELECT r.rate
        FROM public.pricing_fx_rate r
        WHERE c.currency_code = 'USD'
          AND r.from_currency = 'USD'
          AND r.to_currency = 'BRL'
          AND r.rate_source_code = 'BCB_PTAX'
          AND r.rate_date <= (c.observed_at AT TIME ZONE 'UTC')::date
        ORDER BY r.rate_date DESC
        LIMIT 1
    ) fx ON TRUE;
END;
$$;

COMMENT ON FUNCTION public.get_cards_pricing_summary(uuid[]) IS
'Resumo de preço em lote por card_id (Incremento P12 v4, 2026-08-18): elimina o N+1 servidor->Postgres do endpoint batch (antes, uma chamada de get_card_pricing_snapshot por carta). SECURITY DEFINER, auth.uid() IS NOT NULL (mesmo padrao de get_card_pricing_snapshot), maximo 100 card_id por chamada. Retorno minimo (card_id, has_pricing, brl_amount, fx_status) sob uma regra de selecao fixa e deterministica: condicao NM, printing Normal, price_type MARKET -- nao e um resumo heuristico, e a mesma condicao/printing/tipo sempre. Consequencia real: cartas cujo unico printing catalogado e Holofoil (ex.: muitas cartas ex) nunca tem has_pricing=true por esta funcao, mesmo com preco real sob outro printing. Fonte inativa (pricing_source.is_active=FALSE) resulta em has_pricing=false para todas as cartas, sem excecao.';

REVOKE ALL ON FUNCTION public.get_cards_pricing_summary(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_cards_pricing_summary(uuid[]) TO authenticated;
