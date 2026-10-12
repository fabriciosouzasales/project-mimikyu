/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2266 - View de cartas pendentes de variante padrão
Versão......: 1.0
Status......: PROPOSTA — aguardando autorização de Fabrício para executar no LIVE.
Data........: 2026-10-11
Mandato.....: Fabrício, 2026-10-11 — relatório Variantes por carta › "Só cartas sem padrão"
              (pendências em todo o catálogo).

O que faz
  View public.catalog_card_variant_default_pending: cartas ATIVAS com ao menos uma variante e
  nenhuma variante padrão (mesmo critério de cartaNeedsDefaultVariant no frontend). Devolve só
  ids (card_id, card_set_id); o relatório busca os detalhes das poucas cartas encontradas.

Por que uma view (e não filtro no PostgREST)
  O anti-join via embed do PostgREST monta JSON de todas as ~21 mil cartas: ~0,9 s medido no
  LIVE. NOT EXISTS aqui usa os índices existentes (uq_card_variant_one_default_per_card e
  ix_card_variant_card_id) em merge anti/semi join: ~35 ms medido no LIVE (9 linhas).

Segurança
  security_invoker = true (mesmo padrão das views catalog_card_set_*): o RLS admin-only de
  card/card_variant vale para quem consulta. SELECT só para authenticated; nada para anon.

Como validar
  select count(*) from public.catalog_card_variant_default_pending;  -- = pendências atuais
  select reloptions from pg_class where relname = 'catalog_card_variant_default_pending';
  -- esperado: {security_invoker=true}
===============================================================================
*/
CREATE OR REPLACE VIEW public.catalog_card_variant_default_pending
WITH (security_invoker = true) AS
SELECT c.id AS card_id, c.card_set_id
  FROM public.card c
 WHERE c.is_active
   AND EXISTS (SELECT 1 FROM public.card_variant v WHERE v.card_id = c.id)
   AND NOT EXISTS (SELECT 1 FROM public.card_variant d WHERE d.card_id = c.id AND d.is_default);

REVOKE ALL ON public.catalog_card_variant_default_pending FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.catalog_card_variant_default_pending TO authenticated;

COMMENT ON VIEW public.catalog_card_variant_default_pending IS
  'Cartas ativas com variantes e sem variante padrão (P1, Query 2266). security_invoker: RLS admin-only.';
