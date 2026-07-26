/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2801 - Validate Catalog Admin Action Log
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-26

Descrição...:
Validação de public.catalog_admin_action_log: estrutura,
constraints (3 CHECKs, FK anulável) e RLS (esperado: habilitado,
zero políticas).
================================================================
*/

-- 1. Estrutura
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'catalog_admin_action_log'
ORDER BY ordinal_position;

-- 2. Constraints (3 CHECKs + FK anulável + PK)
SELECT conname, pg_get_constraintdef(oid) AS definicao
FROM pg_constraint
WHERE conrelid = 'public.catalog_admin_action_log'::regclass
ORDER BY conname;

-- 3. RLS habilitado, zero políticas
SELECT schemaname, tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public' AND tablename = 'catalog_admin_action_log';

SELECT policyname
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'catalog_admin_action_log';

-- ================================================================
-- Validação executada e confirmada (2026-07-26):
-- - 7 colunas conforme especificado; entity_id e action NOT NULL,
--   metadata/actor_id anuláveis, created_at DEFAULT now().
-- - 5 constraints: PK, FK (actor_id → auth.users, ON DELETE SET
--   NULL), ck_..._action_valid, ck_..._entity_type_valid,
--   ck_..._action_entity_match.
-- - rowsecurity = true; zero políticas.
-- ================================================================
