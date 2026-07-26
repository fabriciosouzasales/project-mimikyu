/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 277 - Validate Catalog Editorial Authorization and Logo Infrastructure
Versão......: 1.0
Status......: MIGRATION
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-26

Descrição...:
Validação consolidada das Queries 273-276 (mesmo padrão da Query 995,
que consolidou a validação de asset_import_run+asset_import_failure):
coluna e CHECK de logo em card_set, as 10 políticas admin-only de leitura
do Catálogo Editorial, a função administrativa de escrita da logo, e o
bucket privado com suas quatro políticas de Storage. Formaliza em SQL o
que ADR-022 decidiu em prosa.

Regras de Negócio validadas:
- card_set.logo_storage_path existe, é TEXT, nullable, sem default.
- ck_card_set_logo_storage_path_not_url existe com a definição exata.
- Nenhuma política de INSERT/UPDATE/DELETE existe em card_set (a escrita
  da logo passa exclusivamente pela função SECURITY DEFINER).
- As 10 tabelas do Catálogo Editorial usadas pela Visão Geral têm política
  catalog_admin_select + GRANT SELECT para authenticated.
- As 7 tabelas do Catálogo Editorial ainda não usadas por nenhuma tela
  seguem sem qualquer política (fechadas).
- admin_set_card_set_logo() é SECURITY DEFINER, com search_path vazio,
  EXECUTE concedido a authenticated e negado a anon/public.
- O bucket card-set-logo é privado e não está registrado em storage_bucket.
- As quatro políticas de storage.objects (SELECT/INSERT/UPDATE/DELETE)
  existem, cada uma restrita a bucket_id = 'card-set-logo' AND is_admin().
================================================================
*/

-- Bloco 1: coluna + CHECK em card_set
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'card_set' AND column_name = 'logo_storage_path';
-- Esperado: logo_storage_path / text / YES / NULL

SELECT conname, pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid = 'public.card_set'::regclass
  AND conname = 'ck_card_set_logo_storage_path_not_url';
-- Esperado: CHECK (((logo_storage_path IS NULL) OR (logo_storage_path !~* '^[a-z][a-z0-9+.-]*://'::text)))

-- Bloco 2: nenhuma política de escrita em card_set (a escrita é só via função)
SELECT policyname, cmd
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'card_set' AND cmd <> 'SELECT';
-- Esperado: zero linhas

-- Bloco 3: as 10 políticas admin-only de leitura do Catálogo Editorial
SELECT tablename, policyname, cmd, qual
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('game','expansion','card_set','card','card_variant','card_asset','language','rarity','card_category','asset_import_run')
ORDER BY tablename;
-- Esperado: 10 linhas, uma por tabela, policyname = catalog_admin_select, qual = is_admin()

SELECT table_name, grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name IN ('game','expansion','card_set','card','card_variant','card_asset','language','rarity','card_category','asset_import_run')
  AND grantee = 'authenticated'
  AND privilege_type = 'SELECT'
ORDER BY table_name;
-- Esperado: 10 linhas (uma por tabela)

-- Bloco 4: as 7 tabelas do catálogo ainda não usadas seguem fechadas
SELECT t.tablename,
       EXISTS (SELECT 1 FROM pg_policies p WHERE p.schemaname = 'public' AND p.tablename = t.tablename) AS tem_politica
FROM pg_tables t
WHERE t.schemaname = 'public'
  AND t.tablename IN ('card_variant_type','card_asset_type','storage_bucket','asset_source','card_external_reference','card_set_external_reference','asset_import_failure')
ORDER BY t.tablename;
-- Esperado: tem_politica = false nas 7 linhas

-- Bloco 5: segurança da função admin_set_card_set_logo()
SELECT p.proname, p.prosecdef, p.proconfig,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_pode_executar,
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_pode_executar
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'admin_set_card_set_logo';
-- Esperado: prosecdef = true, proconfig contém search_path="", authenticated = true, anon = false

-- Bloco 6: bucket privado, fora do catálogo storage_bucket
SELECT id, public FROM storage.buckets WHERE id = 'card-set-logo';
-- Esperado: public = false

SELECT COUNT(*) AS registrado_em_storage_bucket
FROM public.storage_bucket WHERE code = 'card-set-logo';
-- Esperado: 0

-- Bloco 7: as quatro políticas de Storage
SELECT policyname, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname LIKE 'card_set_logo_admin_%'
ORDER BY policyname;
-- Esperado: 4 linhas (select/insert/update/delete), todas com
-- bucket_id = 'card-set-logo' AND is_admin() em qual e/ou with_check

-- ================================================================
-- Todos os blocos executados e confirmados em 2026-07-26 (resultados reais
-- conferidos individualmente durante a execução pareada das Queries
-- 273-276; consolidados aqui como um único roteiro de validação
-- reexecutável). Único bloco não testado em tempo real: a chamada efetiva
-- de admin_set_card_set_logo() (bloqueada pelo classificador automático do
-- ambiente de execução por se parecer com uma ação de escrita) — validado
-- por revisão estrutural da função em vez de execução ao vivo.
-- ================================================================
