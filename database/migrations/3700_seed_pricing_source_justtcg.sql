-- Query 3700 — Seed pricing_source: JustTCG (homologação condicionada)
-- Objetivo: cadastrar a fonte JustTCG em public.pricing_source, refletindo o resultado real
-- da prova técnica (19/19 cartas e 7/7 Card Sets encontrados, preços em USD, printings,
-- condições e histórico disponíveis, zero falha técnica, 15 requisições, nenhum segredo
-- persistido). Decisão A aprovada; Decisão B inconclusiva (idioma das 18 consultas novas
-- ficou UNDETERMINED). JustTCG fica homologada para piloto técnico de produtos, printings,
-- condições, preços originais em USD e histórico — não homologada para determinar PT-BR
-- nem como preço do mercado brasileiro. Nunca inferir idioma pelo USD.
--
-- is_active = FALSE: a única semântica real desta coluna no modelo (05f-pricing.md,
-- Regra de Negócio 3; mesmo padrão de card_variant_type/asset_source) é "não excluída
-- fisicamente" (soft delete), sem nenhum consumidor operacional hoje (nenhuma Edge
-- Function/cron/mapping/sincronização existe). Mantida FALSE deliberadamente para não
-- sinalizar, num futuro picker/consulta "WHERE is_active", uma fonte pronta para uso
-- operacional/produção — o que ainda não é o caso: plano comercial compatível não está
-- contratado, e a Decisão B (idioma) segue inconclusiva. Reavaliar para TRUE em
-- incremento futuro, quando existir plano pago contratado e mecanismo de sincronização
-- real (fora de escopo deste incremento).
--
-- requires_commercial_agreement = TRUE: os Termos de Uso vigentes da JustTCG
-- (https://justtcg.com/terms, "Last updated: 7/27/2026", Seção 6/7.1) restringem o
-- tier gratuito a uso pessoal/não comercial; uso comercial (exibição a usuários finais,
-- cache/armazenamento, combinação com outras fontes) exige assinatura paga com licença
-- comercial explícita nos Termos. Nenhuma tela deve publicar dado desta fonte sem
-- confirmação prévia de que um plano compatível está contratado.

INSERT INTO public.pricing_source (
    code,
    name,
    source_type,
    default_market_scope,
    base_currency,
    base_url,
    api_base_url,
    documentation_url,
    terms_url,
    attribution_text,
    requires_commercial_agreement,
    supports_api,
    is_active,
    source_order
) VALUES (
    'JUSTTCG',
    'JustTCG',
    'API',
    'INTERNATIONAL',
    'USD',
    'https://justtcg.com',
    'https://api.justtcg.com/v1',
    'https://justtcg.com/docs',
    'https://justtcg.com/terms',
    'Dados de preço fornecidos por JustTCG (https://justtcg.com).',
    TRUE,
    TRUE,
    FALSE,
    1
)
ON CONFLICT (code) DO NOTHING;
