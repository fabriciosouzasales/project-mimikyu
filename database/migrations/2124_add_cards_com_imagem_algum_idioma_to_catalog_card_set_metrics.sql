/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2124 - Add cards_com_imagem_algum_idioma to catalog_card_set_metrics
Versão......: 1.0
Status......: MIGRATION — CONFIRMADO EXECUTADO E VALIDADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-08

Descrição...:
Evolução incremental da Query 2123: adiciona cards_com_imagem_algum_idioma
a catalog_card_set_metrics, ao final da lista de colunas (CREATE OR REPLACE
VIEW só aceita adicionar coluna nova no fim, sem remover/retipar as
existentes). Conta Cards distintas com imagem canônica — is_primary = true
E card_asset_type.code = 'CARD_FRONT', mesmo critério exato documentado em
catalog_card_set_image_coverage (Query 2123) — em PELO MENOS UM idioma
ativo (união entre idiomas via COUNT(DISTINCT card.id) sem GROUP BY
language_id, diferente da view de cobertura, que agrupa POR idioma).

Motivação: getEstadoDoCatalogo()/getCardSetsOverview() (web/lib/catalogo/
queries.ts) calculam cardSetsComImagensCompletas/temImagensCompletas
checando se uma Card tem QUALQUER card_asset, em QUALQUER tipo/idioma —
uma união entre idiomas que catalog_card_set_image_coverage não consegue
reconstruir (seu grão é por idioma; duas Cards cobertas em idiomas
diferentes ficariam invisíveis como união na agregação por contagem).

Importante (ajuste de Fabrício sobre a redação original desta Query):
cards_com_imagem_algum_idioma NÃO é uma reprodução mecânica da lógica
antiga — ela aplica a definição CANÔNICA de "Card com imagem" (is_primary
= true, card_asset_type.code = 'CARD_FRONT', idioma ativo), enquanto a
lógica antiga em queries.ts conta qualquer card_asset, de qualquer tipo,
em qualquer idioma, sem essas restrições. As duas coincidem hoje porque,
na prática, só CARD_FRONT/is_primary é gravado em produção (ARTWORK/
CARD_BACK são placeholders futuros no card_asset_type, nunca usados pelo
pipeline) — Query 2821, item 3, provou essa coincidência linha a linha
contra os dados reais de produção (0 divergências). Essa coincidência é
empírica, válida para o estado atual dos dados, não uma garantia lógica
permanente: se um dia a aplicação passar a gravar ARTWORK/CARD_BACK ou
imagens não-primárias, os dois critérios podem divergir. A partir desta
Query, cards_com_imagem_algum_idioma formaliza cardSetsComImagensCompletas/
temImagensCompletas segundo a definição canônica — não perpetua o critério
solto que existia antes só porque nunca havia sido escrito em nenhum outro
lugar.

Regras de Negócio:
- Coluna nova sempre ao final da lista de SELECT — nunca reordenar ou
  retipar colunas existentes de uma view em CREATE OR REPLACE.
- Mesmo critério de "Card com imagem" já documentado em
  catalog_card_set_image_coverage (Query 2123) — is_primary = true E
  card_asset_type.code = 'CARD_FRONT'.
- Filtra por language.is_active = true, mesma disciplina já usada na view
  de cobertura — imagem presa a um idioma desativado não conta.
- security_invoker = true e GRANT SELECT só para authenticated,
  inalterados (CREATE OR REPLACE VIEW preserva GRANTs já concedidos;
  reafirmado abaixo por clareza, não por necessidade).

Validação (Query 2821): estrutural (coluna na última posição,
security_invoker mantido, GRANT inalterado — authenticated=true,
anon=false) e de equivalência (comparação linha a linha contra a lógica
antiga para todo Card Set, 0 divergências confirmadas). Indicador
agregado reconstruído: 33 Card Sets com cardSetsComImagensCompletas = true
na produção atual. Spot check MEE: 8 Cards cadastradas, 8 com imagem
canônica em algum idioma (consistente com a cobertura 8/8 em en e pt-BR
já confirmada pela Query 2123).

Pré-requisitos:
- Query 2123 - Create Catalog Card Set Metrics Views.
================================================================
*/

CREATE OR REPLACE VIEW public.catalog_card_set_metrics
WITH (security_invoker = true) AS
SELECT
    cs.id                                                          AS card_set_id,
    cs.code                                                        AS card_set_code,
    cs.name                                                        AS card_set_name,
    e.code                                                         AS expansion_code,
    g.code                                                         AS game_code,
    cs.total_set_size,
    COALESCE(card_counts.cards_cadastradas, 0)                     AS cards_cadastradas,
    COALESCE(card_counts.cards_ativas, 0)                          AS cards_ativas,
    COALESCE(card_counts.cards_cadastradas, 0)
        - COALESCE(card_counts.cards_ativas, 0)                    AS cards_inativas,
    GREATEST(
        cs.total_set_size - COALESCE(card_counts.cards_cadastradas, 0),
        0
    )                                                               AS cards_pendentes_cadastro,
    COALESCE(image_union_counts.cards_com_imagem_algum_idioma, 0)   AS cards_com_imagem_algum_idioma
FROM public.card_set cs
JOIN public.expansion e
    ON e.id = cs.expansion_id
JOIN public.game g
    ON g.id = e.game_id
LEFT JOIN (
    SELECT
        crd.card_set_id,
        COUNT(*)                                    AS cards_cadastradas,
        COUNT(*) FILTER (WHERE crd.is_active)        AS cards_ativas
    FROM public.card crd
    GROUP BY crd.card_set_id
) AS card_counts
    ON card_counts.card_set_id = cs.id
LEFT JOIN (
    SELECT
        crd.card_set_id,
        COUNT(DISTINCT crd.id) AS cards_com_imagem_algum_idioma
    FROM public.card_asset ca
    JOIN public.card_asset_type cat
        ON cat.id = ca.asset_type_id
    JOIN public.card crd
        ON crd.id = ca.card_id
    JOIN public.language lang
        ON lang.id = ca.language_id
       AND lang.is_active = TRUE
    WHERE ca.is_primary = TRUE
      AND cat.code = 'CARD_FRONT'
    GROUP BY crd.card_set_id
) AS image_union_counts
    ON image_union_counts.card_set_id = cs.id;

COMMENT ON COLUMN public.catalog_card_set_metrics.cards_com_imagem_algum_idioma IS
    'COUNT(DISTINCT card.id) com imagem canônica (is_primary = true E card_asset_type.code = ''CARD_FRONT'') em PELO MENOS UM idioma ativo — união entre idiomas, não por idioma (diferente de catalog_card_set_image_coverage, que agrupa por idioma). Formaliza cardSetsComImagensCompletas/temImagensCompletas (web/lib/catalogo/queries.ts) segundo a definição canônica de "Card com imagem" — completa quando cards_cadastradas > 0 E cards_cadastradas = cards_com_imagem_algum_idioma. Coincide com o critério solto usado antes em queries.ts (qualquer card_asset, qualquer tipo/idioma) apenas porque hoje só CARD_FRONT/is_primary é gravado em produção (validado pela Query 2821) — não é uma reprodução mecânica dessa lógica antiga, e pode divergir dela no futuro se outros tipos de asset passarem a ser usados.';

GRANT SELECT ON public.catalog_card_set_metrics TO authenticated;
