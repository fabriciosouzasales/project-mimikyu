/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2134 - Harden is_admin() RLS Performance (Opção C)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO (via MCP do Supabase, projeto qjfutqujxrbzgrtkpgkg)
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-14

Descrição...:
Achado "RLS Admin Performance Hardening", registrado durante a frente de
performance de /catalogo/card-sets (Incrementos 1-5, mesma data) e aberto
como investigação formal a pedido de Fabrício: public.is_admin() é
VOLATILE (categoria padrão, nunca declarada explicitamente) e é chamada
nua (sem `(select ...)`) em 24 policies RLS (14 em public.*, 10 em
storage.objects) — o Postgres não pode tratar uma função VOLATILE como
constante dentro da consulta, reavaliando-a como Filter a cada linha
varrida da tabela protegida. Investigação completa (inventário, semântica
STABLE/VOLATILE/InitPlan, benchmarks controlados em transações com
ROLLBACK, análise de segurança) apresentada e aprovada por Fabrício antes
desta execução.

Mudança (Opção C, a única aprovada):
1. ALTER FUNCTION public.is_admin() STABLE — semanticamente correto: o
   MVCC do Postgres já garante snapshot consistente de admin_user dentro
   de UM statement, com ou sem essa declaração; STABLE só permite ao
   planner reaproveitar o resultado. SECURITY DEFINER, search_path='' e
   o corpo da função permanecem inalterados.
2. ALTER POLICY nas 24 policies — troca SOMENTE `is_admin()` por
   `(select is_admin())` em cada expressão; nenhum outro predicado
   (bucket_id, roles, comandos, nomes de policy) foi tocado. Nenhum
   DROP/CREATE — só ALTER POLICY, preservando os objetos originais.

Preservação semântica confirmada por comparação textual antes/depois nas
24 policies (14 public.*: asset_import_run, asset_source, card,
card_asset, card_asset_type, card_category, card_set, card_variant,
catalog_import_job, catalog_import_row, expansion, game, language,
rarity — policy catalog_admin_select, cmd SELECT, roles {public}; 10
storage.objects: card_front_admin_delete/_insert, card_set_logo_admin_
delete/_insert/_select/_update, expansion_logo_admin_delete/_insert/
_select/_update) — única diferença textual em cada expressão é
`is_admin()` → `(select is_admin())`.

Validação de segurança (2026-08-14, mesma sessão, todas dentro de
BEGIN...ROLLBACK, nunca contra um usuário real):
- is_admin() pós-migration: STABLE, SECURITY DEFINER=true, search_path=
  '""', owner postgres, EXECUTE só para authenticated (+postgres) —
  idêntico ao estado anterior, só a volatilidade mudou.
- Admin sintético (auth.users/admin_user inseridos e revertidos dentro
  da mesma transação, nunca um usuário real): is_admin()=true, SELECT
  em card (7104), card_asset (13376) e catalog_card_set_metrics (43)
  retornam o total completo — acesso permitido, idêntico ao esperado.
- Não-admin autenticado (UUID sintético sem linha em admin_user):
  is_admin()=false, 0 linhas em card/card_asset — acesso negado,
  idêntico ao esperado.
- anon: `permission denied for table card` — inalterado (bloqueado por
  ausência de GRANT, RLS nunca é avaliada).
- service_role: bypassa RLS (rolbypassrls=true), vê as 7104 linhas de
  card independente de is_admin() — inalterado.
- Buckets: INSERT como admin sintético aceito nos 3 buckets (card-front,
  card-set-logo, expansion-logo); INSERT como não-admin rejeitado com
  "new row violates row-level security policy" nos buckets privados;
  SELECT como não-admin retorna 0 linhas em card-set-logo/expansion-logo
  (privados); card-front é bucket público (storage.buckets.public=true),
  por isso nunca teve policy de SELECT — comportamento pré-existente,
  não alterado por esta migration.

Validação de performance (2026-08-14, mesma sessão, admin sintético,
EXPLAIN (ANALYZE, BUFFERS) sob role authenticated):
- public.card (7.104 linhas): Filter: is_admin() por linha → Filter:
  (InitPlan 1).col1, InitPlan avaliado 1x. 102,774 ms → 2,228 ms.
- public.card_asset (13.376 linhas): mesmo padrão. 358,265 ms → 4,872 ms.
- public.catalog_card_set_metrics (view completa, 43 Card Sets, com
  cards_com_imagem_algum_idioma — o caso mais pesado, une card_set,
  expansion, game, card, card_asset, card_asset_type, language): 8
  InitPlans (um por tabela protegida referenciada), nenhum Filter por
  linha restante. 58,908 ms — praticamente igual ao baseline de leitura
  direta como postgres (bypass RLS) medido na investigação original
  (~59,5 ms), ante os ~1.300-1.600 ms observados em produção antes desta
  migration (auditoria de /catalogo/card-sets, mesma data).

Pré-requisitos:
- Query 1060 - Create is_admin Function.
- Query 274 - Add Admin-Only Select Policies to Catalog Tables.
- Query 2047, 2119, 2113 e correlatas - policies de storage.objects
  (card-set-logo, expansion-logo, card-front).
================================================================
*/

begin;

alter function public.is_admin() stable;

alter policy catalog_admin_select on public.asset_import_run using ((select is_admin()));
alter policy catalog_admin_select on public.asset_source using ((select is_admin()));
alter policy catalog_admin_select on public.card using ((select is_admin()));
alter policy catalog_admin_select on public.card_asset using ((select is_admin()));
alter policy catalog_admin_select on public.card_asset_type using ((select is_admin()));
alter policy catalog_admin_select on public.card_category using ((select is_admin()));
alter policy catalog_admin_select on public.card_set using ((select is_admin()));
alter policy catalog_admin_select on public.card_variant using ((select is_admin()));
alter policy catalog_admin_select on public.catalog_import_job using ((select is_admin()));
alter policy catalog_admin_select on public.catalog_import_row using ((select is_admin()));
alter policy catalog_admin_select on public.expansion using ((select is_admin()));
alter policy catalog_admin_select on public.game using ((select is_admin()));
alter policy catalog_admin_select on public.language using ((select is_admin()));
alter policy catalog_admin_select on public.rarity using ((select is_admin()));

alter policy card_front_admin_delete on storage.objects
  using ((bucket_id = 'card-front'::text) and (select is_admin()));
alter policy card_front_admin_insert on storage.objects
  with check ((bucket_id = 'card-front'::text) and (select is_admin()));
alter policy card_set_logo_admin_delete on storage.objects
  using ((bucket_id = 'card-set-logo'::text) and (select is_admin()));
alter policy card_set_logo_admin_insert on storage.objects
  with check ((bucket_id = 'card-set-logo'::text) and (select is_admin()));
alter policy card_set_logo_admin_select on storage.objects
  using ((bucket_id = 'card-set-logo'::text) and (select is_admin()));
alter policy card_set_logo_admin_update on storage.objects
  using ((bucket_id = 'card-set-logo'::text) and (select is_admin()))
  with check ((bucket_id = 'card-set-logo'::text) and (select is_admin()));
alter policy expansion_logo_admin_delete on storage.objects
  using ((bucket_id = 'expansion-logo'::text) and (select is_admin()));
alter policy expansion_logo_admin_insert on storage.objects
  with check ((bucket_id = 'expansion-logo'::text) and (select is_admin()));
alter policy expansion_logo_admin_select on storage.objects
  using ((bucket_id = 'expansion-logo'::text) and (select is_admin()));
alter policy expansion_logo_admin_update on storage.objects
  using ((bucket_id = 'expansion-logo'::text) and (select is_admin()))
  with check ((bucket_id = 'expansion-logo'::text) and (select is_admin()));

commit;

-- ================================================================
-- Confirmado executado (2026-08-14, via execute_sql/MCP do Supabase)
-- e validado: is_admin() STABLE com SECURITY DEFINER/search_path/owner/
-- grants preservados; 24 policies com a única mudança textual
-- is_admin() -> (select is_admin()), roles/cmd/predicados de
-- bucket_id/path preservados byte-a-byte; autorização confirmada
-- inalterada nos 4 perfis (admin/não-admin/anon/service_role) e nos 3
-- buckets; EXPLAIN confirma InitPlan/One-Time Filter no lugar de Filter
-- por linha em card/card_asset/catalog_card_set_metrics, com ganhos de
-- ~50-370x conforme a tabela. Ver docs/log.md para o relatório completo
-- da investigação e desta validação.
-- ================================================================

-- ================================================================
-- ROLLBACK (não executado, documentado para reversão futura se
-- necessário — reverte is_admin() para VOLATILE e as 24 policies para
-- a chamada nua is_admin(), exatamente como estavam antes desta Query):
--
-- begin;
-- alter function public.is_admin() volatile;
-- alter policy catalog_admin_select on public.asset_import_run using (is_admin());
-- alter policy catalog_admin_select on public.asset_source using (is_admin());
-- alter policy catalog_admin_select on public.card using (is_admin());
-- alter policy catalog_admin_select on public.card_asset using (is_admin());
-- alter policy catalog_admin_select on public.card_asset_type using (is_admin());
-- alter policy catalog_admin_select on public.card_category using (is_admin());
-- alter policy catalog_admin_select on public.card_set using (is_admin());
-- alter policy catalog_admin_select on public.card_variant using (is_admin());
-- alter policy catalog_admin_select on public.catalog_import_job using (is_admin());
-- alter policy catalog_admin_select on public.catalog_import_row using (is_admin());
-- alter policy catalog_admin_select on public.expansion using (is_admin());
-- alter policy catalog_admin_select on public.game using (is_admin());
-- alter policy catalog_admin_select on public.language using (is_admin());
-- alter policy catalog_admin_select on public.rarity using (is_admin());
-- alter policy card_front_admin_delete on storage.objects
--   using ((bucket_id = 'card-front'::text) and is_admin());
-- alter policy card_front_admin_insert on storage.objects
--   with check ((bucket_id = 'card-front'::text) and is_admin());
-- alter policy card_set_logo_admin_delete on storage.objects
--   using ((bucket_id = 'card-set-logo'::text) and is_admin());
-- alter policy card_set_logo_admin_insert on storage.objects
--   with check ((bucket_id = 'card-set-logo'::text) and is_admin());
-- alter policy card_set_logo_admin_select on storage.objects
--   using ((bucket_id = 'card-set-logo'::text) and is_admin());
-- alter policy card_set_logo_admin_update on storage.objects
--   using ((bucket_id = 'card-set-logo'::text) and is_admin())
--   with check ((bucket_id = 'card-set-logo'::text) and is_admin());
-- alter policy expansion_logo_admin_delete on storage.objects
--   using ((bucket_id = 'expansion-logo'::text) and is_admin());
-- alter policy expansion_logo_admin_insert on storage.objects
--   with check ((bucket_id = 'expansion-logo'::text) and is_admin());
-- alter policy expansion_logo_admin_select on storage.objects
--   using ((bucket_id = 'expansion-logo'::text) and is_admin());
-- alter policy expansion_logo_admin_update on storage.objects
--   using ((bucket_id = 'expansion-logo'::text) and is_admin())
--   with check ((bucket_id = 'expansion-logo'::text) and is_admin());
-- commit;
-- ================================================================
