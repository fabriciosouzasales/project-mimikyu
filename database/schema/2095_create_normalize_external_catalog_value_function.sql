/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2095 - Create normalize_external_catalog_value() Function
Versão......: 1.0
Status......: CANÔNICA — CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-07

Descrição...:
Cria normalize_external_catalog_value(), função de normalização
compartilhada entre o cadastro self-service de Raridade
(admin_create_rarity_external_mapping(), Query 2101) e a
importação TCGdex (ADR-024) — substitui o antigo mecanismo
hardcoded RARITY_NAME_ALIASES em código-fonte por comparação de
dado, via rarity_external_mapping (Query 2096).

Regras de Negócio:
- NFD via extensions.unaccent() (Query 2094) remove acentos;
  trim + colapso de espaços múltiplos (regexp_replace) + upper()
  tornam a comparação insensível a maiúsculas/acentos/espaçamento
  — mas NÃO a variação de redação ("Hiper Rara" não casa com
  "Hyper Rare"; cada variante de texto precisa do seu próprio
  mapeamento).
- LANGUAGE sql STABLE (não VOLATILE) — resultado determinístico
  para a mesma entrada dentro de uma mesma transação, permite
  otimizações do planner (ex. em índices funcionais futuros).
- SET search_path = '' com toda referência qualificada
  (extensions.unaccent) — nunca um nome ambíguo.

Pré-requisitos:
- Query 2094 - Enable unaccent Extension.
================================================================
*/

CREATE OR REPLACE FUNCTION public.normalize_external_catalog_value(p_value TEXT)
RETURNS TEXT
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
    SELECT upper(regexp_replace(trim(extensions.unaccent(coalesce(p_value, ''))), '\s+', ' ', 'g'));
$$;

-- ================================================================
-- Confirmado executado (2026-08-07): definição em produção lida
-- via pg_get_functiondef() e conferida idêntica a este arquivo.
-- Usada em produção por admin_create_rarity_external_mapping()
-- (Query 2101) e pelo processador import-catalog-cards
-- (_shared/catalog-normalization/), sem regressão observada.
-- ================================================================
