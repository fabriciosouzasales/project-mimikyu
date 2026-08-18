-- Query 3904 — CONFIRMADO EXECUTADO (Incremento P12, correção pós-teste "Reverse-only", 2026-08-18)
-- Não edita a migration 3903 (já aplicada) — substitui a função get_cards_pricing_summary
-- (Query 3903) via DROP + CREATE, porque a mudança muda a assinatura de retorno (nova coluna
-- printing_label); CREATE OR REPLACE FUNCTION não permite alterar o tipo de retorno de uma
-- função existente.
--
-- Contexto: um teste transacional (BEGIN/ROLLBACK, 2026-08-18) usando o Bulbasaur real do
-- piloto P8 (ME1 #001, que tem produtos Normal e Reverse Holofoil) provou que a revisão 3903
-- não tinha nenhum fallback de printing — o filtro do CTE `candidate` era rígido a
-- pricing_product.source_printing_label = 'Normal'. Com Normal temporariamente desativado e
-- Reverse Holofoil ativo, a função retornou has_pricing = false em vez de escolher Reverse
-- Holofoil, mesmo havendo observação NM+MARKET real (US$ 0,31) sob esse printing. O mesmo
-- problema já afetava permanentemente Alakazam/Mega Gardevoir ex/Mega Venusaur ex (piloto P8),
-- cujo único printing catalogado é Holofoil — nunca mostravam resumo, mesmo com preço real.
--
-- Correção: hierarquia de printing aprovada por Fabrício, aplicada só dentro da condição NM e
-- só sobre price_type = 'MARKET' (nenhuma mudança nesses dois filtros, já corretos em 3903):
--   1. Normal
--   2. Holofoil
--   3. Reverse Holofoil
-- has_pricing = true (e brl_amount resolvido) se QUALQUER uma das três tiver uma observação
-- NM+MARKET elegível (produto ativo, fonte ativa, mapping CONFIRMED) — não mais só Normal.
-- Escolha determinística dentro do mesmo printing preservada sem alteração: observed_at DESC,
-- created_at DESC, id DESC (mesmos critérios de desempate de 3901/3903).
--
-- Nova coluna de retorno printing_label (texto cru do banco: 'Normal'/'Holofoil'/'Reverse
-- Holofoil', nunca traduzido aqui — tradução PT-BR continua responsabilidade do frontend, mesmo
-- padrão de pricing_product.source_printing_label já usado no detalhe por-carta) — devolve ao
-- chamador qual printing foi efetivamente escolhido pela hierarquia, em vez de o frontend ter
-- de assumir "Normal" ou recalcular a hierarquia por conta própria a partir de um resumo mínimo
-- que não a carrega.
--
-- Desenho da consulta: `candidate_by_printing` (DISTINCT ON (card_id, source_printing_label) —
-- uma observação mais recente por printing elegível, mesmos critérios de desempate de sempre)
-- alimenta `candidate` (DISTINCT ON (card_id), ordenado pela hierarquia via CASE) — exatamente
-- um candidato final por carta, sempre o printing de maior prioridade entre os elegíveis. Mesmo
-- padrão de segurança de 3901/3903, sem alteração: SECURITY DEFINER, verificação explícita de
-- auth.uid() IS NOT NULL, REVOKE ALL FROM PUBLIC + GRANT EXECUTE só a authenticated, mesmos dois
-- guards de entrada (array vazio/nulo, mais de 100 elementos).

DROP FUNCTION IF EXISTS public.get_cards_pricing_summary(uuid[]);

CREATE FUNCTION public.get_cards_pricing_summary(p_card_ids uuid[])
RETURNS TABLE (
    card_id        uuid,
    has_pricing    boolean,
    brl_amount     numeric,
    fx_status      text,
    printing_label text
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
    candidate_by_printing AS (
        SELECT DISTINCT ON (pcm.card_id, pp.source_printing_label)
            pcm.card_id,
            pp.source_printing_label,
            po.price,
            po.currency_code,
            po.observed_at
        FROM public.pricing_card_mapping pcm
        JOIN public.pricing_product pp
            ON pp.pricing_card_mapping_id = pcm.id
           AND pp.is_active = TRUE
           AND pp.source_printing_label IN ('Normal', 'Holofoil', 'Reverse Holofoil')
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
        ORDER BY pcm.card_id, pp.source_printing_label, po.observed_at DESC, po.created_at DESC, po.id DESC
    ),
    -- Colunas sempre qualificadas com o alias `cbp` (nunca `card_id` cru) — o parâmetro de
    -- retorno da função também se chama `card_id` (RETURNS TABLE), e dentro de uma função
    -- PL/pgSQL um identificador não qualificado é ambíguo entre a variável de retorno e a
    -- coluna da CTE (erro real encontrado nesta rodada: "column reference card_id is
    -- ambiguous"). candidate_by_printing, acima, já não tinha esse problema por já qualificar
    -- tudo com pcm./pp./po.
    candidate AS (
        SELECT DISTINCT ON (cbp.card_id)
            cbp.card_id, cbp.source_printing_label, cbp.price, cbp.currency_code, cbp.observed_at
        FROM candidate_by_printing cbp
        ORDER BY cbp.card_id,
            CASE cbp.source_printing_label
                WHEN 'Normal' THEN 1
                WHEN 'Holofoil' THEN 2
                WHEN 'Reverse Holofoil' THEN 3
                ELSE 4
            END
    )
    SELECT
        ii.input_id AS card_id,
        (fx.rate IS NOT NULL) AS has_pricing,
        CASE WHEN fx.rate IS NOT NULL THEN round(c.price * fx.rate, 2) ELSE NULL END AS brl_amount,
        CASE
            WHEN c.card_id IS NULL THEN NULL
            WHEN fx.rate IS NOT NULL THEN 'CONVERTED'
            ELSE 'FX_RATE_UNAVAILABLE'
        END AS fx_status,
        c.source_printing_label AS printing_label
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
'Resumo de preco em lote por card_id (Incremento P12, revisao 3904, 2026-08-18): mesma base da revisao 3903 (elimina N+1 servidor->Postgres), agora com hierarquia de printing aprovada -- Normal > Holofoil > Reverse Holofoil -- dentro da condicao NM e price_type MARKET. has_pricing=true se QUALQUER um dos tres printings tiver observacao elegivel (produto ativo, fonte ativa, mapping CONFIRMED); escolha deterministica dentro do mesmo printing por observed_at/created_at/id mais recentes. Nova coluna printing_label devolve ao chamador qual printing foi efetivamente escolhido (texto cru do banco, traducao PT-BR e responsabilidade do frontend). SECURITY DEFINER, auth.uid() IS NOT NULL, maximo 100 card_id por chamada -- sem alteracao nesses pontos frente a 3903. Fonte inativa (pricing_source.is_active=FALSE) resulta em has_pricing=false para todas as cartas, sem excecao.';

REVOKE ALL ON FUNCTION public.get_cards_pricing_summary(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_cards_pricing_summary(uuid[]) TO authenticated;
