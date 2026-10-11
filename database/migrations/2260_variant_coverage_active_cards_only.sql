/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2260 - Cobertura de variantes conta só cartas ativas
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO (2026-10-11, apply_migration no LIVE qjfutqujxrbzgrtkpgkg)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-11
Mandato.....: Fabrício, 2026-10-11 — "Vamos tentar resolver essa pendência" (Importar Variantes
              mostrava 1 Coleção com pendência / 1 Card sem variante após CARD VARIANTS CLOSED).
Substitui...: definição da view criada em 2135.

Causa
  catalog_card_set_variant_coverage contava TODAS as cartas (catalog_card_set_metrics.cards_cadastradas),
  inclusive desativadas. A única carta sem variante no banco é SVP 226 "Terapagos & Friends",
  desativada em 2026-10-10 (CARD_DEACTIVATED). Carta inativa está fora do catálogo e não pode
  receber variante pelo fluxo de importação; contá-la criava uma pendência impossível de resolver.

O que muda
  - cards_cadastradas passa a ser o total de cartas ATIVAS do Set (m.cards_ativas);
  - cards_com_variante conta só cartas ativas;
  - cards_sem_variante = ativas − ativas com variante.
  Mesmas colunas, mesma ordem, security_invoker mantido, grants preservados (CREATE OR REPLACE).
  Consumidores: Importar Variantes (seletor e cards de resumo) e relatório Cobertura de Variantes
  (percentual = com variante / cadastradas, agora ambos sobre ativas).

Como validar
  select count(*) filter (where cards_sem_variante > 0), coalesce(sum(cards_sem_variante),0)
    from public.catalog_card_set_variant_coverage;   -- esperado 0 | 0
===============================================================================
*/

CREATE OR REPLACE VIEW public.catalog_card_set_variant_coverage
WITH (security_invoker = true) AS
SELECT m.card_set_id,
       m.card_set_code,
       m.card_set_name,
       m.cards_ativas AS cards_cadastradas,
       COALESCE(variant_counts.cards_com_variante, 0::bigint) AS cards_com_variante,
       m.cards_ativas - COALESCE(variant_counts.cards_com_variante, 0::bigint) AS cards_sem_variante
  FROM public.catalog_card_set_metrics m
  LEFT JOIN (
        SELECT crd.card_set_id, count(DISTINCT crd.id) AS cards_com_variante
          FROM public.card crd
          JOIN public.card_variant cv ON cv.card_id = crd.id
         WHERE crd.is_active
         GROUP BY crd.card_set_id) variant_counts
    ON variant_counts.card_set_id = m.card_set_id;
