/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 3972 - Harden get_cards_pricing_summary() — Payload Cardinality
Versão......: 1.0
Status......: PROPOSTA — STAGING, NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-07 (criado em
               PRICING-PAYLOAD-CARDINALITY-HARDENING-01)

Descrição...:
MIGRATION INCREMENTAL de segurança. NÃO edita nenhuma migration
histórica. A cadeia `3903` → `3904` → `3918` → `3924` → `3968`
permanece intacta como registro do que foi executado.

ATENÇÃO — DIVERGÊNCIA DE PREMISSA, CORRIGIDA AQUI
-------------------------------------------------
O mandato citava `3903`/`3904`/`3918` como as migrations históricas a
preservar. A definição EFETIVA no banco NÃO é a `3918`: é a **`3968`**
(`DROP FUNCTION` + `CREATE FUNCTION`, integração do preço manual), que
adicionou o fallback `MANUAL`, as colunas de retorno `printing_label` e
`price_origin` e o join com `pricing_source_card_identity`. A `3924`
também redefiniu a função no meio do caminho.

Consequência prática: o corpo abaixo é cópia **verbatim** de
`pg_get_functiondef()` da definição efetiva `3968` — não da `3918`.
Reescrever a partir da `3918` teria REVERTIDO silenciosamente o preço
manual em produção.

ACHADO (BYPASS REAL, MESMA CLASSE DE 5024/5046/5047)
----------------------------------------------------
A definição efetiva limita o lote com:

    IF p_card_ids IS NULL OR array_length(p_card_ids, 1) IS NULL THEN
        RAISE EXCEPTION 'PRICING_SUMMARY_EMPTY_INPUT' ...
    IF array_length(p_card_ids, 1) > 100 THEN
        RAISE EXCEPTION 'PRICING_SUMMARY_TOO_MANY_CARD_IDS' ...

`array_length(x, 1)` mede APENAS A PRIMEIRA DIMENSÃO. Medido no banco
real em 2026-09-07 (prova aritmética, somente leitura):

    array_fill(uuid, ARRAY[2, 300])
        array_ndims        = 2
        array_length(x, 1) = 2      <- passa pelo teto de 100
        cardinality(x)     = 600
        unnest(x)          = 600 linhas   <- CONFIRMADO

Ou seja: uma RPC pública `SECURITY DEFINER` executa `unnest` +
`DISTINCT` + toda a cadeia de CTEs de resolução de preço
(`candidate_by_printing` → `candidate` → `automatic` → `manual`,
incluindo dois `LEFT JOIN LATERAL` de PTAX e uma chamada por linha a
`pricing_latest_manual_price()`) sobre um array de tamanho arbitrário
escolhido pelo chamador. O teto existia no papel e não no comportamento.

Precedente idêntico e já fechado no projeto: `5138`/`5139`/`5140` sobre
`5024`/`5046`/`5047` (2026-09-07), validadas por `5820` 27/27.

CORREÇÃO
--------
Guards, todos ANTES do `RETURN QUERY` e portanto antes de qualquer
`unnest`/`DISTINCT`/`LATERAL`:
  1. NULL                        -> PRICING_SUMMARY_EMPTY_INPUT;
  2. cardinality(...) = 0        -> PRICING_SUMMARY_EMPTY_INPUT
                                    (cobre '{}', cujo array_ndims é NULL
                                    — por isso o teste de vazio vem
                                    ANTES do teste de dimensão);
  3. array_ndims(...) <> 1       -> PRICING_SUMMARY_INVALID_PAYLOAD_SHAPE
                                    (código NOVO, ver nota abaixo);
  4. cardinality(...) > 100      -> PRICING_SUMMARY_TOO_MANY_CARD_IDS.

Ordem obrigatória: vazio antes de dimensão. `array_ndims('{}')` é NULL,
e `NULL <> 1` é NULL (não TRUE) — sem o teste de vazio antes, um array
vazio escaparia do guard de forma e cairia adiante com a mensagem
errada. Mesma disciplina de `5138`–`5140`.

SOBRE O CÓDIGO DE ERRO NOVO
---------------------------
`PRICING_SUMMARY_INVALID_PAYLOAD_SHAPE`, `ERRCODE = '22023'` — mesmo
ERRCODE dos dois guards pré-existentes deste módulo. É um estado que
antes era IMPOSSÍVEL de observar (o payload multidimensional não era
rejeitado, era processado), então nenhum chamador existente pode
depender dele. As duas mensagens pré-existentes foram preservadas
LITERALMENTE, com o mesmo ERRCODE.

O QUE **NÃO** MUDA
------------------
- assinatura: `(p_card_ids uuid[])`;
- retorno: TABLE(card_id uuid, has_pricing boolean, brl_amount numeric,
  fx_status text, printing_label text, price_origin text);
- LANGUAGE plpgsql, STABLE, SECURITY DEFINER, SET search_path = '';
- verificação `auth.uid() IS NULL` -> PRICING_SUMMARY_REQUIRES_AUTHENTICATION
  (ERRCODE 28000), primeira instrução do corpo, intocada;
- REVOKE de PUBLIC/anon + GRANT EXECUTE para authenticated;
- owner `postgres`;
- **toda a lógica de negócio**: regra NM + `price_type = 'MARKET'`, a
  hierarquia de sete printings (Normal → Holofoil → Reverse Holofoil →
  Unlimited → Unlimited Holofoil → 1st Edition → 1st Edition Holofoil),
  o caminho AUTOMATIC, o fallback MANUAL, a conversão PTAX, o
  `fx_status`, o `price_origin` — byte-idênticos à `3968`.

`CREATE OR REPLACE` é suficiente e correto aqui: assinatura e tipo de
retorno são idênticos aos da definição efetiva. Não é necessário
`DROP FUNCTION` (que exigiria recriar grants e invalidaria o OID).

COMPATIBILIDADE
---------------
Chamador único e verificado: `web/app/api/cards/pricing/batch/route.ts`
(linha 348). Ele já valida `Array.isArray`, deduplica com `Set`, exige
`UUID_RE` por elemento e impõe `MAX_CARD_IDS = 100` antes de chamar a
RPC. Um array JS plano serializado pelo PostgREST é sempre
unidimensional — nenhum lote legítimo muda de comportamento. Nenhum
outro caller existe no repositório (varredura em `web/` e `supabase/`).

Dependências:
- public.get_cards_pricing_summary() já existente (definição efetiva 3968).
- public.pricing_latest_manual_price() (Query 3967).

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADO.
================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.get_cards_pricing_summary(p_card_ids uuid[])
RETURNS TABLE(
    card_id uuid,
    has_pricing boolean,
    brl_amount numeric,
    fx_status text,
    printing_label text,
    price_origin text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_raw_count INTEGER;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'PRICING_SUMMARY_REQUIRES_AUTHENTICATION'
            USING ERRCODE = '28000';
    END IF;

    -- ================================================================
    -- HARDENING 3972 — CONTRATO DE PAYLOAD.
    --
    -- Substitui `array_length(p_card_ids, 1)`, que media apenas a
    -- PRIMEIRA DIMENSAO e permitia que um array multidimensional
    -- atravessasse o teto de 100 enquanto o `unnest` processava todos
    -- os elementos (array_fill(uuid, ARRAY[2,300]): dim1=2, card=600).
    --
    -- Todos os guards abaixo sao avaliados ANTES do RETURN QUERY, e
    -- portanto antes de qualquer unnest/DISTINCT/LATERAL.
    --
    -- ORDEM OBRIGATORIA: vazio ANTES de dimensao. array_ndims('{}') e
    -- NULL, e `NULL <> 1` e NULL (nao TRUE) — sem o teste de vazio
    -- primeiro, '{}' escaparia do guard de forma.
    --
    -- Padrao ja aprovado e aplicado em 5138/5139/5140 sobre
    -- 5024/5046/5047, validado por 5820 (27/27).
    -- ================================================================
    IF p_card_ids IS NULL THEN
        RAISE EXCEPTION 'PRICING_SUMMARY_EMPTY_INPUT'
            USING ERRCODE = '22023';
    END IF;

    v_raw_count := cardinality(p_card_ids);

    IF v_raw_count = 0 THEN
        RAISE EXCEPTION 'PRICING_SUMMARY_EMPTY_INPUT'
            USING ERRCODE = '22023';
    END IF;

    IF array_ndims(p_card_ids) <> 1 THEN
        RAISE EXCEPTION 'PRICING_SUMMARY_INVALID_PAYLOAD_SHAPE'
            USING ERRCODE = '22023';
    END IF;

    IF v_raw_count > 100 THEN
        RAISE EXCEPTION 'PRICING_SUMMARY_TOO_MANY_CARD_IDS'
            USING ERRCODE = '22023';
    END IF;
    -- ================ FIM DO HARDENING 3972 =========================

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
$function$;

REVOKE ALL ON FUNCTION public.get_cards_pricing_summary(uuid[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_cards_pricing_summary(uuid[]) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_cards_pricing_summary(uuid[]) TO authenticated;

COMMIT;

/*
Como validar (estático, APÓS aplicar):

SELECT p.prosecdef,
       p.provolatile,
       p.proconfig,
       pg_get_userbyid(p.proowner) AS owner,
       pg_get_function_identity_arguments(p.oid) AS assinatura,
       pg_get_function_result(p.oid) AS retorno,
       has_function_privilege('authenticated', p.oid,'EXECUTE') AS auth_exec,
       has_function_privilege('anon',          p.oid,'EXECUTE') AS anon_exec,
       (position('cardinality(p_card_ids)' in pg_get_functiondef(p.oid)) > 0)      AS usa_cardinality,
       (position('array_ndims(p_card_ids) <> 1' in pg_get_functiondef(p.oid)) > 0) AS usa_ndims,
       (position('array_length(p_card_ids' in pg_get_functiondef(p.oid)) = 0)      AS sem_array_length
FROM pg_proc p
WHERE p.pronamespace='public'::regnamespace AND p.proname='get_cards_pricing_summary';

Esperado: prosecdef=t, provolatile='s', proconfig={search_path=""},
owner=postgres, assinatura='p_card_ids uuid[]', retorno com as 6
colunas, auth_exec=t, anon_exec=f, usa_cardinality=t, usa_ndims=t,
sem_array_length=t.

Prova comportamental completa: harness `3860`, nesta mesma pasta.
*/
