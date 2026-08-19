-- Query 3918 — CONFIRMADO EXECUTADO (correção pós-diagnóstico onda 1 P14.4.2, 2026-08-19)
-- Não edita a migration 3904 (já aplicada) — CREATE OR REPLACE sobre a mesma assinatura e
-- mesmo tipo de retorno de 3904 (card_id, has_pricing, brl_amount, fx_status, printing_label),
-- por isso não precisa de DROP FUNCTION desta vez (3904 precisou, porque mudava o retorno
-- frente a 3903; aqui só o corpo muda). SECURITY DEFINER, search_path, comentário-base e ACL
-- (REVOKE ALL FROM PUBLIC/anon + GRANT EXECUTE TO authenticated) preservados sem alteração —
-- CREATE OR REPLACE FUNCTION não reseta privilégios já concedidos numa função existente.
--
-- Contexto: diagnóstico somente-leitura (2026-08-19, mesma sessão) confirmou, com evidência
-- direta no banco (RPC executado sob papel authenticated, não postgres/service_role), que os
-- 3.375 produtos escritos na onda 1 do P14.4.2 (BASE2/BASE3/BASE5/GYM2, run
-- 598610e6-c23a-47aa-ad65-88113a008984) ficam 100% fora da hierarquia fixa de 3904
-- ('Normal', 'Holofoil', 'Reverse Holofoil') — a JustTCG rotula printings da era clássica
-- (WOTC) como '1st Edition', 'Unlimited', '1st Edition Holofoil', 'Unlimited Holofoil', nenhum
-- dos quais estava coberto. Resultado: has_pricing=false para as 341 cartas da onda inteira,
-- apesar de dado real e correto persistido (produtos/observações auditados sem duplicidade,
-- órfão ou sobrescrita). BASE4 (era moderna, printing 'Holofoil') não era afetado — controle
-- usado no diagnóstico e revalidado nesta migration.
--
-- Correção: hierarquia estendida, aprovada por Fabrício (2026-08-19) — Unlimited antes de
-- 1st Edition porque representa a edição padrão mais comum; 1st Edition é premium, prioridade
-- mais baixa:
--   1. Normal
--   2. Holofoil
--   3. Reverse Holofoil
--   4. Unlimited
--   5. Unlimited Holofoil
--   6. 1st Edition
--   7. 1st Edition Holofoil
-- Sem fallback genérico para printing desconhecido — só estes sete valores entram no filtro
-- `IN (...)` do CTE `candidate_by_printing`; um printing fora da lista simplesmente não vira
-- candidato, mesmo pedido explícito de Fabrício nesta rodada. Mesmo racional de 3904: has_pricing
-- = true se QUALQUER um dos sete tiver observação NM+MARKET elegível (produto ativo, fonte
-- ativa, mapping CONFIRMED); escolha determinística dentro do mesmo printing inalterada
-- (observed_at/created_at/id mais recentes).
--
-- Nenhuma outra regra alterada frente a 3904: condição fixa NM, price_type fixo MARKET,
-- conversão USD→BRL via pricing_fx_rate/BCB_PTAX inalterada, seleção temporal (observed_at DESC,
-- created_at DESC, id DESC) inalterada, guards de entrada (array vazio/nulo, >100 elementos)
-- inalterados. `get_card_pricing_snapshot` (3901, contrato por-carta) foi inspecionada e não tem
-- filtro fixo de printing equivalente — devolve todas as variantes sem restrição — por isso não
-- foi alterada nesta migration (item 5 do pedido: só alinhar se o mesmo filtro existir).

CREATE OR REPLACE FUNCTION public.get_cards_pricing_summary(p_card_ids uuid[])
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
           AND pp.source_printing_label IN (
               'Normal', 'Holofoil', 'Reverse Holofoil',
               'Unlimited', 'Unlimited Holofoil',
               '1st Edition', '1st Edition Holofoil'
           )
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
    candidate AS (
        SELECT DISTINCT ON (cbp.card_id)
            cbp.card_id, cbp.source_printing_label, cbp.price, cbp.currency_code, cbp.observed_at
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
'Resumo de preco em lote por card_id (revisao 3918, 2026-08-19): mesma base da revisao 3904 (SECURITY DEFINER, auth.uid() IS NOT NULL, maximo 100 card_id, condicao NM, price_type MARKET, conversao USD->BRL via BCB_PTAX, selecao temporal por observed_at/created_at/id), agora com hierarquia de printing estendida para cobrir a era classica (WOTC) alem da era moderna -- Normal > Holofoil > Reverse Holofoil > Unlimited > Unlimited Holofoil > 1st Edition > 1st Edition Holofoil. Sem fallback generico: printing fora desta lista de sete nao vira candidato. Corrige has_pricing=false sistemico para Sets cujo printing e 1st Edition/Unlimited (nao coberto pela revisao 3904). ACL inalterada (REVOKE ALL FROM PUBLIC, anon; GRANT EXECUTE TO authenticated, ja concedida desde 3903/3904).';
