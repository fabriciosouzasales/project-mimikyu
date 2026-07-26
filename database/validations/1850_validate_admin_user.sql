/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 1850 - Validate Admin User
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-26

Descrição...:
Validação de public.admin_user: estrutura, constraints e RLS
(esperado: habilitado, zero políticas).
================================================================
*/

-- 1. Estrutura
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'admin_user'
ORDER BY ordinal_position;

-- 2. Constraints (FKs)
SELECT conname, pg_get_constraintdef(oid) AS definicao
FROM pg_constraint
WHERE conrelid = 'public.admin_user'::regclass
ORDER BY conname;

-- 3. RLS habilitado, zero políticas
SELECT schemaname, tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public' AND tablename = 'admin_user';

SELECT policyname
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'admin_user';

-- 4. Administradores atuais (bootstrap + concessões desde então)
SELECT au.email, adm.granted_at, adm.granted_by
FROM public.admin_user adm
JOIN auth.users au ON au.id = adm.id
ORDER BY adm.granted_at;
