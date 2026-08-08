/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2123 - Create Catalog Card Set Metrics Views
Versão......: 1.0
Status......: MIGRATION — CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-08

Descrição...:
Camada canônica de métricas do Catálogo Editorial (Sprint Gerencial 1
— Visão Geral + métricas canônicas), reutilizável por Visão Geral e,
futuramente, pela Central de Relatórios. Duas views, security_invoker
= true (PostgreSQL 15+): RLS e privilégios avaliados pela identidade
de quem consulta, nunca pelo dono da view — sem isso, uma view comum
sobre tabela com RLS herdaria o contexto do owner (que normalmente
contorna RLS), expondo os dados a qualquer authenticated
independente de is_admin(). Ambas seguem o mesmo padrão de acesso já
usado nas tabelas do catálogo (ADR-022, Query 274): GRANT SELECT só
para authenticated, RLS resolvendo is_admin() nas tabelas de origem.

1. catalog_card_set_metrics — estrutural, grão = 1 linha por Card Set.
   Escopo deliberadamente restrito a card_set/expansion/game/card —
   sem catalog_import_job, para não multiplicar linhas por job e para
   manter separadas as métricas estruturais do catálogo das métricas
   operacionais do pipeline de importação (decisão de Fabrício,
   revisão de plano anterior a esta Query). Semântica dos campos:
   - total_set_size: tamanho OFICIAL esperado do Card Set
     (card_set.total_set_size, preenchido manualmente) — pode
     divergir do real da fonte externa.
   - cards_cadastradas: COUNT(card) por Card Set, sem filtro de
     is_active — mesmo critério de "Cartas"/cardsCatalogados já usado
     em toda a aplicação (web/lib/catalogo/queries.ts).
   - cards_ativas: COUNT(card) WHERE is_active = true.
   - cards_inativas: cards_cadastradas - cards_ativas. Cards
     desativadas (ADR-023, soft delete) — nunca cartas nunca
     cadastradas (ajuste explícito de Fabrício: não usar
     total_set_size - cards_ativas para isso, pois misturaria as duas
     populações).
   - cards_pendentes_cadastro: GREATEST(total_set_size -
     cards_cadastradas, 0). Estimativa agregada — NÃO substitui a
     futura identificação de quais collector_number específicos estão
     ausentes.

2. catalog_card_set_image_coverage — grão = (Card Set, idioma ATIVO).
   CROSS JOIN contra public.language (is_active = true) garante uma
   linha por combinação sempre, mesmo sem nenhuma imagem (zero
   explícito) — extensível a novos idiomas sem alteração de schema,
   em vez de colunas fixas por idioma (cards_com_imagem_en/pt_br),
   que criariam acoplamento desnecessário (ajuste explícito de
   Fabrício). Definição canônica de "Card com imagem", idêntica à já
   usada em getCartasCatalogoStats()/getImagesImportadasPorCardSet()
   (web/lib/catalogo/queries.ts): existe pelo menos um card_asset com
   is_primary = true E card_asset_type.code = 'CARD_FRONT' para a
   Card, no idioma da linha. NÃO considera card_asset.is_active nem
   card.is_active — limitação conhecida e já existente em produção,
   preservada deliberadamente para não criar uma segunda definição
   divergente entre telas.

Validação de segurança (Query 2820) confirmou, com os três papéis
simulados por SET LOCAL ROLE dentro de uma transação com ROLLBACK:
admin lê ambas as views (> 0 linhas); authenticated não-admin lê 0
linhas nas duas (RLS filtra); anon recebe permission denied nas duas
(sem GRANT). Números de catalog_card_set_metrics conferidos contra a
produção real (37 Card Sets, incluindo os casos esperados onde
cards_cadastradas > total_set_size por secret rares além da
numeração oficial — ex. SV1, SV3). Cobertura de MEE conferida: 8/8 em
en e pt-BR.

Regras de Negócio:
- Nenhuma tabela nova nem coluna nova — só views sobre estruturas já
  existentes (ADR-006: dados derivados não persistidos
  redundantemente sem justificativa técnica).
- security_invoker = true nas duas views, sem exceção.
- GRANT SELECT só para authenticated — nunca para anon, nunca para
  PUBLIC.

Pré-requisitos:
- Query 274 - Add Admin-Only SELECT Policies to Catalog Tables.
- Query 2053 - Add Admin Select Policy to card_asset_type.
- Query 193 - Add Language to Card Asset (language_id em card_asset).
- PostgreSQL 15+ no projeto (security_invoker) — confirmado.
================================================================
*/

-- 1. catalog_card_set_metrics — estrutural, grão = 1 linha por Card Set

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
    )                                                               AS cards_pendentes_cadastro
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
    ON card_counts.card_set_id = cs.id;

COMMENT ON VIEW public.catalog_card_set_metrics IS
    'Métricas estruturais canônicas do Catálogo Editorial, grão = 1 linha por Card Set. security_invoker = true: RLS avaliada pela identidade de quem consulta, nunca pelo dono da view. Sem dado de pipeline de importação (catalog_import_job) — só volume/estado do catálogo. Reutilizável por Visão Geral e Central de Relatórios.';

COMMENT ON COLUMN public.catalog_card_set_metrics.total_set_size IS
    'Tamanho OFICIAL esperado do Card Set (card_set.total_set_size, preenchido manualmente) — pode divergir do real da fonte externa.';

COMMENT ON COLUMN public.catalog_card_set_metrics.cards_cadastradas IS
    'COUNT(card) por Card Set, sem filtro de is_active — mesmo critério de "Cartas"/cardsCatalogados já usado em toda a aplicação.';

COMMENT ON COLUMN public.catalog_card_set_metrics.cards_ativas IS
    'COUNT(card) WHERE is_active = true por Card Set.';

COMMENT ON COLUMN public.catalog_card_set_metrics.cards_inativas IS
    'cards_cadastradas - cards_ativas. Cards desativadas (ADR-023, soft delete) — nunca cartas nunca cadastradas.';

COMMENT ON COLUMN public.catalog_card_set_metrics.cards_pendentes_cadastro IS
    'GREATEST(total_set_size - cards_cadastradas, 0). Estimativa agregada — NÃO substitui a identificação futura de quais collector_number específicos estão ausentes.';

GRANT SELECT ON public.catalog_card_set_metrics TO authenticated;

-- 2. catalog_card_set_image_coverage — grão = (Card Set, Idioma ativo)

CREATE OR REPLACE VIEW public.catalog_card_set_image_coverage
WITH (security_invoker = true) AS
SELECT
    cs.id                                            AS card_set_id,
    cs.code                                          AS card_set_code,
    lang.code                                        AS language_code,
    COALESCE(image_counts.cards_com_imagem, 0)       AS cards_com_imagem
FROM public.card_set cs
CROSS JOIN public.language lang
LEFT JOIN (
    SELECT
        crd.card_set_id,
        ca.language_id,
        COUNT(DISTINCT crd.id) AS cards_com_imagem
    FROM public.card_asset ca
    JOIN public.card_asset_type cat
        ON cat.id = ca.asset_type_id
    JOIN public.card crd
        ON crd.id = ca.card_id
    WHERE ca.is_primary = TRUE
      AND cat.code = 'CARD_FRONT'
    GROUP BY crd.card_set_id, ca.language_id
) AS image_counts
    ON image_counts.card_set_id = cs.id
   AND image_counts.language_id = lang.id
WHERE lang.is_active = TRUE;

COMMENT ON VIEW public.catalog_card_set_image_coverage IS
    'Cobertura de imagem por Card Set e idioma ATIVO, grão = (card_set_id, language_id), sempre uma linha por combinação (zero explícito quando não há imagem) — extensível a novos idiomas sem alteração de schema. security_invoker = true, mesma justificativa de catalog_card_set_metrics.';

COMMENT ON COLUMN public.catalog_card_set_image_coverage.cards_com_imagem IS
    'Definição canônica de "Card com imagem" (idêntica ao critério já usado em getCartasCatalogoStats()/getImagesImportadasPorCardSet(), web/lib/catalogo/queries.ts): existe pelo menos um card_asset com is_primary = true E card_asset_type.code = ''CARD_FRONT'' para a Card, no idioma desta linha. NÃO considera card_asset.is_active nem card.is_active — limitação conhecida e já existente em produção, não uma mudança de comportamento introduzida aqui.';

GRANT SELECT ON public.catalog_card_set_image_coverage TO authenticated;
