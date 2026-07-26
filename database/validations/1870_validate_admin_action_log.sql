/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 1870 - Validate Admin Action Log
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-26

Descrição...:
Validação de public.admin_action_log: estrutura, constraints
(CHECK de action, FKs ON DELETE SET NULL) e RLS (esperado:
habilitado, zero políticas).
================================================================
*/

-- 1. Estrutura
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'admin_action_log'
ORDER BY ordinal_position;

-- 2. Constraints (CHECK + FKs anuláveis)
SELECT conname, pg_get_constraintdef(oid) AS definicao
FROM pg_constraint
WHERE conrelid = 'public.admin_action_log'::regclass
ORDER BY conname;

-- 3. RLS habilitado, zero políticas
SELECT schemaname, tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public' AND tablename = 'admin_action_log';

SELECT policyname
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'admin_action_log';

-- 4. Ações registradas até o momento
SELECT action, metadata, created_at
FROM public.admin_action_log
ORDER BY created_at;
