-- Query 3919 — CONFIRMADO EXECUTADO (P14.4.3 — Cobertura completa de Sets já confirmados),
-- a pedido de Fabrício.
-- Aplicada via Supabase MCP em 2026-08-19.
--
-- Contexto: o planejador de expansão (scripts/sync-justtcg-pricing.ts, --expansion-plan) trata
-- todo Set com pricing_set_mapping.match_status = 'CONFIRMED' como ALREADY_CONFIRMED e o exclui
-- de todo planejamento futuro. Isso presume, sem verificar, que "Set confirmado" implica
-- "todas as cartas ativas do Set têm pricing_card_mapping" — uma premissa falsa: BASE1 e ME1
-- foram confirmados no nível do Set em pilotos anteriores (P14.1/P8), mas mapeados apenas
-- parcialmente (3 cartas cada, de um total de 102 e 188 cartas ativas respectivamente).
--
-- Introspecção prévia a esta migration (mesma rodada, sem chamada à JustTCG) confirmou
-- objetivamente, contra os 7 Sets hoje CONFIRMED, que apenas BASE1 (3/102 mapeadas, 99
-- faltantes) e ME1 (3/188 mapeadas, 185 faltantes) estão incompletos; BASE2/BASE3/BASE4/BASE5/
-- GYM2 já têm cobertura total (0 faltantes) — confirmando precisamente a lacuna descrita por
-- Fabrício e dando base numérica ao próximo incremento (backfill de cartas sem mapeamento em
-- Sets já confirmados no nível do Set).
--
-- Esta migration estende a view pricing_set_coverage (Query 3916, P14.4.1) — que já agregava
-- products_count/observations_count por Card Set x Fonte para evitar o truncamento de 1.000
-- linhas do Data API — com 4 novas colunas finais, sem alterar nem reordenar as colunas
-- existentes (CREATE OR REPLACE VIEW preserva OID/ACL/dependências quando só colunas novas são
-- adicionadas ao final do SELECT list):
--
--   mapped_cards_count    — count(DISTINCT pcm.id): cartas ativas do Set com QUALQUER
--                           pricing_card_mapping (CONFIRMED, PENDING ou NOT_FOUND contam como
--                           "mapeada" — o gap real é ausência total de mapping, não o status).
--   confirmed_cards_count — count(DISTINCT pcm.id) FILTER (WHERE match_status = 'CONFIRMED').
--   pending_cards_count   — idem, FILTER (WHERE match_status = 'PENDING').
--   not_found_cards_count — idem, FILTER (WHERE match_status = 'NOT_FOUND').
--
-- Todas as 4 novas colunas usam COUNT(DISTINCT pcm.id) [+ FILTER], nunca count(pp.id)/count(po.id)
-- — pcm (pricing_card_mapping) é a tabela-âncora do JOIN, anterior aos LEFT JOINs de
-- pricing_product/pricing_observation na mesma view; contar por pcm.id evita que o fan-out
-- desses LEFT JOINs infle as contagens de cartas (uma carta com N produtos não deve contar N
-- vezes). A constraint uq_pricing_card_mapping_card_source (UNIQUE card_id, pricing_source_id)
-- garante que count(DISTINCT pcm.id) é exatamente "cartas mapeadas", sem duplicação possível.
--
-- Mantidos sem alteração: security_invoker=true (nunca SECURITY DEFINER), SELECT restrito a
-- service_role, REVOKE ALL FROM PUBLIC/anon/authenticated. Nenhum GRANT novo em tabela base —
-- service_role já detinha SELECT em public.card e public.pricing_card_mapping antes desta
-- migration (confirmado por introspecção prévia), o que security_invoker exige para a view
-- funcionar sob a identidade do papel chamador.
--
-- Testada transacionalmente (BEGIN/ROLLBACK) antes desta aplicação real, contra dados reais dos
-- 7 Sets hoje CONFIRMED:
--   BASE1: mapped=3  confirmed=3   pending=0 not_found=0 | products=15   observations=30
--   BASE2: mapped=64 confirmed=63  pending=1 not_found=0 | products=630  observations=630
--   BASE3: mapped=62 confirmed=62  pending=0 not_found=0 | products=620  observations=620
--   BASE4: mapped=130 confirmed=127 pending=3 not_found=0 | products=635  observations=787
--   BASE5: mapped=83 confirmed=83  pending=0 not_found=0 | products=830  observations=830
--   GYM2:  mapped=132 confirmed=130 pending=2 not_found=0 | products=1295 observations=1295
--   ME1:   mapped=3  confirmed=3   pending=0 not_found=0 | products=17   observations=34
-- products_count/observations_count idênticos aos valores já registrados na Query 3916 (BASE1
-- 15/30, BASE4 635/787, ME1 17/34) — confirma que a extensão não alterou o comportamento das
-- colunas pré-existentes. As 4 novas contagens batem exatamente com a introspecção manual
-- independente (GROUP BY match_status sobre pricing_card_mapping) feita antes de desenhar esta
-- migration. Transação revertida (ROLLBACK) — zero mudança real até a aplicação abaixo.
--
-- Reexecutado pós-aplicação real: os mesmos 7 Sets retornam valores idênticos aos do teste
-- transacional. reloptions confirma security_invoker=true preservado. ACL (information_schema.
-- role_table_grants) confirma SELECT apenas para service_role (e postgres, owner) — nenhum
-- grant para PUBLIC/anon/authenticated. Advisors de segurança e performance revisados
-- pós-aplicação: nenhum achado novo relacionado a pricing_set_coverage.
--
-- Ver 05f-pricing.md / ADR-029 (P14.4.3, quando a documentação deste incremento for encerrada
-- em rodada própria — por instrução explícita de Fabrício, esta rodada NÃO atualiza
-- documentação).

CREATE OR REPLACE VIEW public.pricing_set_coverage
WITH (security_invoker = true) AS
SELECT
  crd.card_set_id,
  pcm.pricing_source_id,
  count(DISTINCT pp.id) AS products_count,
  count(po.id) AS observations_count,
  count(DISTINCT pcm.id) AS mapped_cards_count,
  count(DISTINCT pcm.id) FILTER (WHERE pcm.match_status = 'CONFIRMED') AS confirmed_cards_count,
  count(DISTINCT pcm.id) FILTER (WHERE pcm.match_status = 'PENDING') AS pending_cards_count,
  count(DISTINCT pcm.id) FILTER (WHERE pcm.match_status = 'NOT_FOUND') AS not_found_cards_count
FROM public.pricing_card_mapping pcm
JOIN public.card crd
  ON crd.id = pcm.card_id
LEFT JOIN public.pricing_product pp
  ON pp.pricing_card_mapping_id = pcm.id
LEFT JOIN public.pricing_observation po
  ON po.pricing_product_id = pp.id
WHERE crd.is_active = TRUE
GROUP BY crd.card_set_id, pcm.pricing_source_id;

REVOKE ALL ON public.pricing_set_coverage
FROM PUBLIC, anon, authenticated;

GRANT SELECT ON public.pricing_set_coverage TO service_role;

COMMENT ON VIEW public.pricing_set_coverage IS
  'Fix P14.4.1 (2026-08-19) — cobertura Pricing agregada por Card Set x Fonte (products_count/observations_count), 1 linha por combinação, nunca sujeita ao limite de 1.000 linhas do Data API. Estendida no P14.4.3 (2026-08-19, Query 3919) com mapped_cards_count/confirmed_cards_count/pending_cards_count/not_found_cards_count (contagens DISTINCT sobre pricing_card_mapping.id, imunes ao fan-out dos LEFT JOINs de produtos/observações) — permite ao planejador de backfill distinguir Sets ALREADY_CONFIRMED completos (mapped_cards_count = cartas ativas do Set) de incompletos, sem carregar mappings individuais no cliente. Só cartas ativas (WHERE card.is_active = TRUE) entram na contagem. security_invoker=true. SELECT restrito a service_role (REVOKE ALL FROM PUBLIC/anon/authenticated) — nunca exposta ao frontend. Usada por scripts/sync-justtcg-pricing.ts (--expansion-plan/--backfill-wave). Ver Query 3916/3919 e ADR-029/05f-pricing.md.';
