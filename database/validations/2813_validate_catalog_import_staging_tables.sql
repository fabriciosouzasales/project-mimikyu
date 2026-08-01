/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2813 - Validate Catalog Import Staging Tables
Versão......: 1.0
Status......: PROPOSTA (aguardando execução/confirmação de Fabrício)
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-01

Descrição...:
Validação estrutural da infraestrutura comum de staging da ingestão
de Cards (ADR-024, Ciclo 1): catalog_import_job (Query 2060/2061),
catalog_import_row (Query 2070/2071) e a ampliação de
catalog_admin_action_log (Query 2054).
================================================================
*/

-- 1. As duas tabelas existem
SELECT to_regclass('public.catalog_import_job') AS catalog_import_job,
       to_regclass('public.catalog_import_row') AS catalog_import_row;

-- 2. Constraints de catalog_import_job
SELECT conname, pg_get_constraintdef(oid) AS definicao
FROM pg_constraint
WHERE conrelid = 'public.catalog_import_job'::regclass
ORDER BY conname;

-- 3. Constraints de catalog_import_row
SELECT conname, pg_get_constraintdef(oid) AS definicao
FROM pg_constraint
WHERE conrelid = 'public.catalog_import_row'::regclass
ORDER BY conname;

-- 4. Índices de ambas as tabelas (inclui o índice único parcial de fingerprint)
SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN ('catalog_import_job', 'catalog_import_row')
ORDER BY tablename, indexname;

-- 5. Triggers de ambas as tabelas
SELECT tgrelid::regclass AS tabela, tgname
FROM pg_trigger
WHERE tgrelid IN ('public.catalog_import_job'::regclass, 'public.catalog_import_row'::regclass)
  AND NOT tgisinternal
ORDER BY 1, 2;

-- 6. RLS habilitado + política catalog_admin_select em ambas
SELECT relname, relrowsecurity
FROM pg_class
WHERE relname IN ('catalog_import_job', 'catalog_import_row');

SELECT schemaname, tablename, policyname, cmd, qual
FROM pg_policies
WHERE tablename IN ('catalog_import_job', 'catalog_import_row');

-- 7. Privilégios de tabela: authenticated (SELECT) e service_role (INSERT/UPDATE)
SELECT
    has_table_privilege('authenticated', 'public.catalog_import_job', 'SELECT') AS auth_select_job,
    has_table_privilege('service_role', 'public.catalog_import_job', 'INSERT') AS svc_insert_job,
    has_table_privilege('service_role', 'public.catalog_import_job', 'UPDATE') AS svc_update_job,
    has_table_privilege('authenticated', 'public.catalog_import_row', 'SELECT') AS auth_select_row,
    has_table_privilege('service_role', 'public.catalog_import_row', 'INSERT') AS svc_insert_row,
    has_table_privilege('service_role', 'public.catalog_import_row', 'UPDATE') AS svc_update_row;

-- 8. catalog_admin_action_log ampliada (CATALOG_IMPORT_JOB / CATALOG_IMPORT_CONFIRMED) —
--    as três constraints, não só duas (gap real da Query 2054, corrigido pela 2055)
SELECT conname, pg_get_constraintdef(oid) AS definicao
FROM pg_constraint
WHERE conrelid = 'public.catalog_admin_action_log'::regclass
  AND conname IN (
      'ck_catalog_admin_action_log_action_valid',
      'ck_catalog_admin_action_log_entity_type_valid',
      'ck_catalog_admin_action_log_action_entity_match'
  );

-- ================================================================
-- Validação estrutural (queries 1–8 acima): PENDENTE — aguardando
-- execução das Queries 2054/2060/2061/2070/2071 por Fabrício no
-- Supabase, seguindo o ritual de pareamento de SQL do projeto (uma
-- Query por vez, confirmada antes de avançar).
--
-- Validação funcional: cobre-se em conjunto com a Query 2814
-- (funções admin_start/decide/confirm_catalog_import), já que estas
-- tabelas não têm nenhum caminho de uso isolado das funções — toda
-- escrita passa por elas ou pela Edge Function processadora (fora
-- do escopo desta Query).
-- ================================================================
