/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2821 - Validate cards_com_imagem_algum_idioma
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO E VALIDADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-08

Descrição...:
Validação estrutural e de equivalência da coluna cards_com_imagem_algum_
idioma (Query 2124) em catalog_card_set_metrics. O item 3 (equivalência)
não prova que a definição canônica É a lógica antiga — prova que, no
estado atual de produção, as duas coincidem numericamente, porque hoje
só CARD_FRONT/is_primary é gravado (ver nota em 2124). Resultado
confirmado por Fabrício: 0 divergências, 33 Card Sets com
cardSetsComImagensCompletas = true, MEE com 8/8.
================================================================
*/

-- 1. Coluna existe, na posição certa (última), view ainda security_invoker
SELECT column_name, ordinal_position
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'catalog_card_set_metrics'
ORDER BY ordinal_position;

SELECT c.relname, c.reloptions
FROM pg_class c
WHERE c.relname = 'catalog_card_set_metrics';
-- Confirmado: cards_com_imagem_algum_idioma na última posição; reloptions
-- ainda contém security_invoker=true.

-- 2. GRANT inalterado
SELECT
    has_table_privilege('authenticated', 'public.catalog_card_set_metrics', 'SELECT') AS auth,
    has_table_privilege('anon', 'public.catalog_card_set_metrics', 'SELECT') AS anon;
-- Confirmado: auth = true, anon = false — sem mudança desde a 2820.

-- ================================================================
-- 3. Coincidência numérica, linha a linha, entre a definição canônica
--    (view) e o critério solto anterior (getEstadoDoCatalogo/
--    getCardSetsOverview: qualquer card_asset, qualquer tipo/idioma),
--    contra os dados reais de produção. 0 linhas = coincidem hoje; não
--    é prova de equivalência lógica permanente entre os dois critérios.
-- ================================================================
WITH logica_antiga AS (
    SELECT
        crd.card_set_id,
        COUNT(DISTINCT crd.id) AS cards_com_imagem_qualquer_asset
    FROM public.card crd
    JOIN public.card_asset ca
        ON ca.card_id = crd.id
    GROUP BY crd.card_set_id
)
SELECT
    m.card_set_code,
    m.cards_com_imagem_algum_idioma AS via_view_nova,
    COALESCE(la.cards_com_imagem_qualquer_asset, 0) AS via_logica_antiga
FROM public.catalog_card_set_metrics m
LEFT JOIN logica_antiga la
    ON la.card_set_id = m.card_set_id
WHERE m.cards_com_imagem_algum_idioma <> COALESCE(la.cards_com_imagem_qualquer_asset, 0);
-- Confirmado: 0 linhas.

-- 4. Reconstrução do indicador agregado cardSetsComImagensCompletas
SELECT COUNT(*) AS card_sets_com_imagens_completas
FROM public.catalog_card_set_metrics
WHERE cards_cadastradas > 0
  AND cards_cadastradas = cards_com_imagem_algum_idioma;
-- Confirmado: 33.

-- 5. Spot check MEE (8 Cards, 8/8 em en e pt-BR — esperado 8 também na união)
SELECT card_set_code, cards_cadastradas, cards_com_imagem_algum_idioma
FROM public.catalog_card_set_metrics
WHERE card_set_code = 'MEE';
-- Confirmado: 8, 8.
