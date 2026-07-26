/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 274 - Add Admin-Only SELECT Policies to Catalog Tables
Versão......: 1.0
Status......: MIGRATION
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-26

Descrição...:
Concede leitura (SELECT) do Catálogo Editorial exclusivamente a
administradores, nas 10 tabelas efetivamente consultadas pela tela Visão
Geral do módulo (/catalogo): game, expansion, card_set, card, card_variant,
card_asset, language, rarity, card_category, asset_import_run. Reutiliza
is_admin() (ADR-021). Decisão formalizada em ADR-022: todo o Catálogo
Editorial é restrito a administradores; leitura é liberada tabela a tabela,
apenas onde uma tela real consulta — nunca em todo o schema de uma vez. As
7 tabelas do catálogo ainda não consultadas por nenhuma tela real
(card_variant_type, card_asset_type, storage_bucket, asset_source,
card_external_reference, card_set_external_reference, asset_import_failure)
permanecem sem política nesta rodada.

Regras de Negócio:
- Cada tabela recebe uma única política de SELECT, USING (is_admin()).
- GRANT SELECT concedido à role authenticated — sem o GRANT de nível de
  tabela do PostgreSQL, a política de RLS nunca chega a ser avaliada (mesmo
  gap já documentado nas Queries 250/253/254/272).
- Nenhuma política de INSERT/UPDATE/DELETE é criada por esta Query.
================================================================
*/

begin;

create policy catalog_admin_select on public.game
    for select using (is_admin());
grant select on public.game to authenticated;

create policy catalog_admin_select on public.expansion
    for select using (is_admin());
grant select on public.expansion to authenticated;

create policy catalog_admin_select on public.card_set
    for select using (is_admin());
grant select on public.card_set to authenticated;

create policy catalog_admin_select on public.card
    for select using (is_admin());
grant select on public.card to authenticated;

create policy catalog_admin_select on public.card_variant
    for select using (is_admin());
grant select on public.card_variant to authenticated;

create policy catalog_admin_select on public.card_asset
    for select using (is_admin());
grant select on public.card_asset to authenticated;

create policy catalog_admin_select on public.language
    for select using (is_admin());
grant select on public.language to authenticated;

create policy catalog_admin_select on public.rarity
    for select using (is_admin());
grant select on public.rarity to authenticated;

create policy catalog_admin_select on public.card_category
    for select using (is_admin());
grant select on public.card_category to authenticated;

create policy catalog_admin_select on public.asset_import_run
    for select using (is_admin());
grant select on public.asset_import_run to authenticated;

commit;

-- ================================================================
-- Validação executada e confirmada (2026-07-26):
-- - pg_policies: catalog_admin_select presente nas 10 tabelas, USING (is_admin()).
-- - information_schema.role_table_grants: SELECT concedido a authenticated
--   nas 10 tabelas.
-- - As 7 tabelas restantes do Catálogo Editorial confirmadas sem nenhuma
--   política (pg_policies vazio para elas).
-- ================================================================
