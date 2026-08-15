/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2147 - Least Privilege: Revoke TRUNCATE/REFERENCES/TRIGGER/
               MAINTAIN de anon/authenticated nas Tabelas do Catálogo
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-15

Descrição...:
Achado de segurança levantado durante a validação do Incremento 3 de
Card Variant (Query 2145): `anon` e `authenticated` possuíam TRUNCATE,
REFERENCES, TRIGGER e MAINTAIN em todas as 24 tabelas do Catálogo
Editorial — privilégios de administração de schema, nunca exercidos
pelo app (que só faz SELECT autenticado, filtrado por RLS/is_admin(),
ou escreve via funções SECURITY DEFINER). TRUNCATE é o mais grave:
não é governado por RLS — `anon` (role totalmente não-autenticada)
tinha, em tese, poder de apagar essas tabelas por completo.

Causa raiz confirmada via pg_default_acl: um default ACL do papel
`postgres` sobre o schema public (`anon=Dxtm/postgres,
authenticated=Dxtm/postgres`) concedia esses 4 privilégios
automaticamente a toda tabela nova criada por `postgres` (dono de
todas as tabelas do projeto) — nunca concedido explicitamente em
nenhuma Query individual, e não originado de nenhuma migration
versionada deste repositório (confirmado por busca textual em
database/). Configuração de plataforma feita fora do fluxo de
migrations, nunca documentada até este achado.

Regras de Negócio:
- REVOKE só de TRUNCATE, REFERENCES, TRIGGER, MAINTAIN — nenhum
  SELECT já concedido é tocado (authenticated mantém SELECT onde já
  tinha, via padrão catalog_admin_select/Query 274).
- Escopo travado nas 24 tabelas atuais do Catálogo Editorial listadas
  abaixo. As 5 tabelas fora do Catálogo com o mesmo padrão
  (admin_user, admin_action_log, user_profile, storage_bucket,
  reserved_username) são deliberadamente NÃO tocadas nesta rodada —
  apenas registradas como achado para ciclo futuro, por instrução
  explícita de Fabrício.
- ALTER DEFAULT PRIVILEGES corrige a causa raiz para tabelas futuras
  do schema public criadas por `postgres`: sem isso, qualquer tabela
  nova (Catálogo ou não) voltaria a nascer com os mesmos 4
  privilégios excessivos para anon/authenticated.
- Nenhuma RLS, policy, função ou frontend alterado — confirmado por
  dry-run (diff de pg_policies e pg_get_functiondef() das funções
  admin_*/write_*/is_admin() antes/depois: 0 diferenças).
- service_role não é tocado — mantém os privilégios que já tinha
  (usado só server-side, fora do escopo de "least privilege de
  cliente" desta correção).

Pré-requisitos:
- Nenhum (correção de grants, não depende de nenhuma Query anterior).
================================================================
*/

BEGIN;

-- 1. REVOKE nas 24 tabelas atuais do Catálogo Editorial
REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON
    public.game, public.expansion, public.card_set, public.card_set_external_reference,
    public.card, public.card_external_reference, public.card_category,
    public.card_asset_type, public.card_asset, public.rarity, public.rarity_external_mapping,
    public.language, public.card_variant, public.card_variant_type,
    public.card_variant_type_external_mapping, public.catalog_import_job,
    public.catalog_import_row, public.catalog_variant_import_job,
    public.catalog_variant_import_row, public.catalog_admin_action_log,
    public.asset_import_run, public.asset_import_failure, public.asset_source
FROM anon, authenticated;

-- 2. Correção da causa raiz: default ACL de tabelas futuras do schema public
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
    REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
    ON TABLES FROM anon, authenticated;

COMMIT;

-- ================================================================
-- Confirmado executado (2026-08-15, via execute_sql/MCP do Supabase,
-- projeto qjfutqujxrbzgrtkpgkg), depois de dry-run em BEGIN...ROLLBACK
-- que confirmou, antes de executar de verdade:
-- - grants finais nas 24 tabelas: authenticated só com SELECT (exatamente
--   as que já tinham antes), anon sem nenhum privilégio remanescente;
-- - default ACL futuro de postgres para relations: entradas de anon/
--   authenticated removidas por completo (colapsaram a "nenhum
--   privilégio" ao perder Dxtm, que era tudo que tinham); service_role
--   preservado (Dxtm), fora do escopo;
-- - as 5 tabelas fora do escopo (admin_user, admin_action_log,
--   user_profile, storage_bucket, reserved_username) permaneceram
--   intocadas, com REFERENCES/TRIGGER/TRUNCATE ainda presentes —
--   achado registrado para ciclo futuro, não corrigido aqui;
-- - diff de pg_policies (schema public) antes/depois: 0;
-- - diff de pg_get_functiondef() de is_admin() e de toda função
--   admin_*/write_* (public + internal) antes/depois: 0.
-- Execução real repetiu a mesma sequência com COMMIT e foi
-- reverificada com as mesmas consultas, resultado idêntico.
-- ================================================================

-- ================================================================
-- Como validar:
-- SELECT table_name, grantee, string_agg(privilege_type, ',')
-- FROM information_schema.role_table_grants
-- WHERE table_schema = 'public' AND grantee IN ('anon','authenticated')
--   AND table_name IN ('card','card_variant', ...)  -- as 24 tabelas
-- GROUP BY table_name, grantee;
-- Esperado: anon sem nenhuma linha; authenticated só com SELECT onde já
-- tinha antes.
--
-- SELECT defaclacl FROM pg_default_acl d JOIN pg_namespace n
--   ON n.oid = d.defaclnamespace
-- WHERE n.nspname = 'public' AND pg_get_userbyid(d.defaclrole) = 'postgres'
--   AND d.defaclobjtype = 'r';
-- Esperado: sem entrada de anon/authenticated (só postgres e service_role).
-- ================================================================
