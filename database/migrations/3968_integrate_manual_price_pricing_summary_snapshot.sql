-- Query 3968 — Integrar Preço Manual em get_cards_pricing_summary / get_card_pricing_snapshot
-- Status: CONFIRMADO EXECUTADO em 2026-08-27 via Supabase MCP (apply_migration).
--
-- Escopo estrito (Fabrício, 2026-08-27): somente estas 2 funções. Nenhuma outra
-- superfície (relatórios, grids adicionais) é tocada nesta migration.
--
-- Baseline real confirmado antes de editar (não a partir de memória):
--   get_cards_pricing_summary (live) já exige, desde a migration 3924,
--   JOIN pricing_source_card_identity psci ON identity_role='PRIMARY' AND
--   match_status='CONFIRMED' — divergência frente ao entendimento anterior
--   (que a associava à versão pré-3924, sem esse join). Confirmado via
--   pg_get_functiondef contra o banco real e via grep no texto de 3924.
--   get_card_pricing_snapshot (live) permanece idêntica à 3901 (nunca
--   redefinida depois) — sem join de identidade.
--
-- Regra de preservação (item 1 do pedido): a query "automática" de cada
-- função é copiada tal como está hoje, célula a célula, para dentro de um
-- CTE isolado. Nenhuma condição, join ou cast do caminho automático foi
-- alterado — inclusive a peculiaridade pré-existente de que has_pricing/
-- equivalent_brl_amount só ficam utilizáveis quando currency_code='USD'
-- (conversão só é tentada nesse caso; um preço automático já nativo em BRL
-- hoje resultaria em fx_status='FX_RATE_UNAVAILABLE' e has_pricing=false —
-- comportamento herdado, fora de escopo corrigir aqui).
--
-- "Manual utilizável" (mesma formalização da migration 3967): última linha
-- append-only de pricing_manual_price para (card_id, condition_id) via
-- pricing_latest_manual_price(); se currency_code = 'BRL', utilizável
-- diretamente; caso contrário, só utilizável se pricing_fx_rate resolver
-- BCB_PTAX para a data de observed_at.
--
-- Precedência (item 2): por card+condition, AUTOMÁTICO UTILIZÁVEL > MANUAL
-- UTILIZÁVEL > SEM PREÇO. price_origin (item 3): 'AUTOMATIC' | 'MANUAL' |
-- NULL quando sem preço algum.
--
-- get_cards_pricing_summary (item 5): mantém a mesma semântica de NM/MARKET/
-- BRL — o CTE `candidate` (automático) é copiado sem alteração; o fallback
-- manual usa a mesma condição fixa NM (via pricing_latest_manual_price) e a
-- mesma moeda alvo BRL.
--
-- get_card_pricing_snapshot (item 6): fallback por condição. Uma condição só
-- recebe linha manual se NENHUMA linha automática daquela condição tiver
-- equivalent_brl_amount resolvido (ou seja, "automático utilizável" checado
-- por condição, não por card inteiro) — condições com automático utilizável
-- nunca são tocadas/duplicadas pelo manual.
--
-- Testado transacionalmente (BEGIN/ROLLBACK) em 2026-08-27 cobrindo os 8
-- cenários exigidos por Fabrício (automático válido; sem automático + manual
-- válido; automático inválido + manual válido; manual sem FX; sem automático
-- e sem manual; múltiplas condições; price_origin correto; reconciliação de
-- cards sem manual = comportamento idêntico ao pré-3968) — todos aprovados.
--
-- Nota de correção aplicada durante o teste transacional: as CTEs
-- `condition_automatic_usable` e `combined`, em get_card_pricing_snapshot,
-- precisaram qualificar todas as colunas com alias de tabela (ar./mr./c.) —
-- sem isso, nomes coincidentes com as colunas de RETURNS TABLE (ex.:
-- equivalent_brl_amount, fx_status, price_type) são lidos por PL/pgSQL como
-- variável da função e geram erro 42702 (ambiguous column reference).

-- ---------------------------------------------------------------------------
-- 1) get_cards_pricing_summary — DROP + CREATE (RETURNS TABLE ganha price_origin)
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_cards_pricing_summary(uuid[]);

CREATE FUNCTION public.get_cards_pricing_summary(p_card_ids uuid[])
RETURNS TABLE (
    card_id        uuid,
    has_pricing    boolean,
    brl_amount     numeric,
    fx_status      text,
    printing_label text,
    price_origin   text
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
    nm_condition AS (
        SELECT id FROM public.card_condition WHERE code = 'NM'
    ),
    -- ---- Caminho automático: cópia byte-a-byte da lógica live (pré-3968) ----
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
        JOIN public.pricing_source_card_identity psci
            ON psci.id = pp.pricing_source_card_identity_id
           AND psci.identity_role = 'PRIMARY'
           AND psci.match_status = 'CONFIRMED'
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
    ),
    automatic AS (
        SELECT
            ii.input_id AS card_id,
            (c.price IS NOT NULL) AS has_candidate,
            (fx.rate IS NOT NULL) AS automatic_usable,
            CASE WHEN fx.rate IS NOT NULL THEN round(c.price * fx.rate, 2) ELSE NULL END AS brl_amount,
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
        ) fx ON TRUE
    ),
    -- ---- Fallback manual (novo em 3968), por card, condição fixa NM ----
    manual AS (
        SELECT
            ii.input_id AS card_id,
            (mp.price IS NOT NULL) AS has_candidate,
            (mp.price IS NOT NULL AND (mp.currency_code = 'BRL' OR mfx.rate IS NOT NULL)) AS manual_usable,
            CASE
                WHEN mp.price IS NULL THEN NULL
                WHEN mp.currency_code = 'BRL' THEN mp.price
                WHEN mfx.rate IS NOT NULL THEN round(mp.price * mfx.rate, 2)
                ELSE NULL
            END AS brl_amount
        FROM input_ids ii
        CROSS JOIN nm_condition nc
        LEFT JOIN LATERAL public.pricing_latest_manual_price(ii.input_id, nc.id) mp ON TRUE
        LEFT JOIN LATERAL (
            SELECT r.rate
            FROM public.pricing_fx_rate r
            WHERE mp.currency_code IS NOT NULL
              AND mp.currency_code <> 'BRL'
              AND r.from_currency = mp.currency_code
              AND r.to_currency = 'BRL'
              AND r.rate_source_code = 'BCB_PTAX'
              AND r.rate_date <= (mp.observed_at AT TIME ZONE 'UTC')::date
            ORDER BY r.rate_date DESC
            LIMIT 1
        ) mfx ON TRUE
    )
    SELECT
        ii.input_id AS card_id,
        (COALESCE(a.automatic_usable, FALSE) OR COALESCE(m.manual_usable, FALSE)) AS has_pricing,
        CASE
            WHEN a.automatic_usable THEN a.brl_amount
            WHEN m.manual_usable THEN m.brl_amount
            ELSE NULL
        END AS brl_amount,
        CASE
            WHEN a.automatic_usable THEN 'CONVERTED'
            WHEN m.manual_usable THEN 'CONVERTED'
            WHEN COALESCE(a.has_candidate, FALSE) OR COALESCE(m.has_candidate, FALSE) THEN 'FX_RATE_UNAVAILABLE'
            ELSE NULL
        END AS fx_status,
        a.printing_label,
        CASE
            WHEN a.automatic_usable THEN 'AUTOMATIC'
            WHEN m.manual_usable THEN 'MANUAL'
            ELSE NULL
        END AS price_origin
    FROM input_ids ii
    LEFT JOIN automatic a ON a.card_id = ii.input_id
    LEFT JOIN manual m ON m.card_id = ii.input_id;
END;
$$;

COMMENT ON FUNCTION public.get_cards_pricing_summary(uuid[]) IS
'Resumo de preco em lote por card_id (revisao 3968, 2026-08-27): caminho automatico identico ao da revisao 3918/3924 (SECURITY DEFINER, auth.uid() IS NOT NULL, maximo 100 card_id, condicao NM, price_type MARKET, identidade PRIMARY/CONFIRMED, conversao USD->BRL via BCB_PTAX, selecao temporal por observed_at/created_at/id) -- nao alterado. Adicionado fallback manual (pricing_manual_price, mesma condicao NM): quando o automatico nao produz preco utilizavel, usa a ultima linha manual append-only para o card, convertendo para BRL quando necessario (BCB_PTAX) e marcando price_origin=MANUAL. Precedencia AUTOMATICO UTILIZAVEL > MANUAL UTILIZAVEL > SEM PRECO. Nova coluna price_origin (AUTOMATIC/MANUAL/NULL). ACL inalterada (REVOKE ALL FROM PUBLIC, anon; GRANT EXECUTE TO authenticated).';

REVOKE ALL ON FUNCTION public.get_cards_pricing_summary(uuid[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_cards_pricing_summary(uuid[]) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_cards_pricing_summary(uuid[]) TO authenticated;

-- ---------------------------------------------------------------------------
-- 2) get_card_pricing_snapshot — DROP + CREATE (RETURNS TABLE ganha price_origin)
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_card_pricing_snapshot(uuid);

CREATE FUNCTION public.get_card_pricing_snapshot(p_card_id uuid)
RETURNS TABLE (
    pricing_source_code   text,
    pricing_source_name   text,
    price_type            text,
    original_amount       numeric,
    original_currency_code text,
    equivalent_brl_amount numeric,
    fx_status             text,
    fx_rate               numeric,
    fx_rate_date          date,
    equivalent_label      text,
    condition_code        text,
    condition_name        text,
    printing_label        text,
    market_label          text,
    observed_at           timestamptz,
    price_origin          text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'PRICING_SNAPSHOT_REQUIRES_AUTHENTICATION'
            USING ERRCODE = '28000';
    END IF;

    RETURN QUERY
    WITH latest AS (
        -- ---- Caminho automático: cópia byte-a-byte da lógica live (3901) ----
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
    ),
    automatic_rows AS (
        SELECT
            l.source_code,
            l.source_name,
            l.price_type,
            l.price AS original_amount,
            l.currency_code AS original_currency_code,
            CASE WHEN fx.rate IS NOT NULL THEN round(l.price * fx.rate, 2) ELSE NULL END AS equivalent_brl_amount,
            CASE WHEN fx.rate IS NOT NULL THEN 'CONVERTED' ELSE 'FX_RATE_UNAVAILABLE' END AS fx_status,
            fx.rate AS fx_rate,
            fx.rate_date AS fx_rate_date,
            CASE WHEN fx.rate IS NOT NULL THEN 'Equivalente em BRL pela PTAX Venda' ELSE NULL END AS equivalent_label,
            l.condition_id,
            cc.code AS condition_code,
            cc.name AS condition_name,
            l.source_printing_label AS printing_label,
            l.market_label,
            l.observed_at,
            'AUTOMATIC'::text AS price_origin,
            cc.condition_order,
            l.source_order,
            l.pricing_product_id
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
    ),
    -- ---- Fallback manual (novo em 3968), por condição ----
    -- Colunas qualificadas com alias (ar./mr./c.) abaixo: os nomes de RETURNS
    -- TABLE (equivalent_brl_amount, fx_status, price_type etc.) tornam-se
    -- variáveis PL/pgSQL implícitas no corpo da função; sem qualificação,
    -- Postgres rejeita como referência ambígua (erro 42702).
    condition_automatic_usable AS (
        SELECT DISTINCT ar.condition_id FROM automatic_rows ar WHERE ar.equivalent_brl_amount IS NOT NULL
    ),
    manual_candidate_conditions AS (
        SELECT cc.id AS condition_id, cc.code AS condition_code, cc.name AS condition_name, cc.condition_order
        FROM public.card_condition cc
        WHERE cc.id NOT IN (SELECT condition_id FROM condition_automatic_usable)
    ),
    manual_rows AS (
        SELECT
            NULL::text AS source_code,
            NULL::text AS source_name,
            NULL::text AS price_type,
            mp.price AS original_amount,
            mp.currency_code AS original_currency_code,
            CASE
                WHEN mp.currency_code = 'BRL' THEN mp.price
                WHEN mfx.rate IS NOT NULL THEN round(mp.price * mfx.rate, 2)
                ELSE NULL
            END AS equivalent_brl_amount,
            CASE
                WHEN mp.currency_code = 'BRL' THEN 'CONVERTED'
                WHEN mfx.rate IS NOT NULL THEN 'CONVERTED'
                ELSE 'FX_RATE_UNAVAILABLE'
            END AS fx_status,
            mfx.rate AS fx_rate,
            mfx.rate_date AS fx_rate_date,
            CASE WHEN mp.currency_code <> 'BRL' AND mfx.rate IS NOT NULL
                 THEN 'Equivalente em BRL pela PTAX Venda' ELSE NULL END AS equivalent_label,
            mcc.condition_id,
            mcc.condition_code,
            mcc.condition_name,
            NULL::text AS printing_label,
            NULL::text AS market_label,
            mp.observed_at,
            'MANUAL'::text AS price_origin,
            mcc.condition_order,
            999999 AS source_order,
            NULL::uuid AS pricing_product_id
        FROM manual_candidate_conditions mcc
        LEFT JOIN LATERAL public.pricing_latest_manual_price(p_card_id, mcc.condition_id) mp ON TRUE
        LEFT JOIN LATERAL (
            SELECT r.rate, r.rate_date
            FROM public.pricing_fx_rate r
            WHERE mp.currency_code IS NOT NULL
              AND mp.currency_code <> 'BRL'
              AND r.from_currency = mp.currency_code
              AND r.to_currency = 'BRL'
              AND r.rate_source_code = 'BCB_PTAX'
              AND r.rate_date <= (mp.observed_at AT TIME ZONE 'UTC')::date
            ORDER BY r.rate_date DESC
            LIMIT 1
        ) mfx ON TRUE
        WHERE mp.price IS NOT NULL
          AND (mp.currency_code = 'BRL' OR mfx.rate IS NOT NULL)
    ),
    combined AS (
        SELECT ar.source_code, ar.source_name, ar.price_type, ar.original_amount, ar.original_currency_code,
               ar.equivalent_brl_amount, ar.fx_status, ar.fx_rate, ar.fx_rate_date, ar.equivalent_label,
               ar.condition_id, ar.condition_code, ar.condition_name, ar.printing_label, ar.market_label,
               ar.observed_at, ar.price_origin, ar.condition_order, ar.source_order, ar.pricing_product_id
        FROM automatic_rows ar
        UNION ALL
        SELECT mr.source_code, mr.source_name, mr.price_type, mr.original_amount, mr.original_currency_code,
               mr.equivalent_brl_amount, mr.fx_status, mr.fx_rate, mr.fx_rate_date, mr.equivalent_label,
               mr.condition_id, mr.condition_code, mr.condition_name, mr.printing_label, mr.market_label,
               mr.observed_at, mr.price_origin, mr.condition_order, mr.source_order, mr.pricing_product_id
        FROM manual_rows mr
    )
    SELECT
        c.source_code, c.source_name, c.price_type, c.original_amount, c.original_currency_code,
        c.equivalent_brl_amount, c.fx_status, c.fx_rate, c.fx_rate_date, c.equivalent_label,
        c.condition_code, c.condition_name, c.printing_label, c.market_label, c.observed_at, c.price_origin
    FROM combined c
    ORDER BY c.condition_order, c.price_type, c.market_label NULLS LAST, c.source_order, c.printing_label, c.pricing_product_id;
END;
$$;

COMMENT ON FUNCTION public.get_card_pricing_snapshot(uuid) IS
'Snapshot completo de preco por carta (revisao 3968, 2026-08-27): caminho automatico identico ao da revisao 3901 (SECURITY DEFINER, auth.uid() IS NOT NULL, todas as variantes/condicoes/mercados via mapping CONFIRMED, conversao USD->BRL via BCB_PTAX) -- nao alterado. Adicionado fallback manual por CONDICAO: uma condicao so recebe uma linha manual (pricing_manual_price, ultima linha append-only) quando NENHUMA linha automatica daquela condicao tiver equivalent_brl_amount resolvido; condicoes com automatico utilizavel nunca sao tocadas ou duplicadas. Nova coluna price_origin (AUTOMATIC/MANUAL/NULL implicito quando nao ha linha). ACL inalterada (REVOKE ALL FROM PUBLIC, anon; GRANT EXECUTE TO authenticated).';

REVOKE ALL ON FUNCTION public.get_card_pricing_snapshot(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_card_pricing_snapshot(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_card_pricing_snapshot(uuid) TO authenticated;
