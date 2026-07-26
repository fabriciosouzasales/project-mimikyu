/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 1800 - Validate User Profile
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-25

Descrição...:
Validação de public.user_profile: estrutura, constraints,
triggers, políticas de RLS e uma checagem de inconsistência —
usuários em auth.users sem linha correspondente em user_profile
(esperado ser zero a partir da Query 1020; contas criadas antes
dela não têm perfil retroativo e precisam de decisão manual).
================================================================
*/

-- 1. Estrutura
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'user_profile'
ORDER BY ordinal_position;

-- 2. Constraints
SELECT conname, pg_get_constraintdef(oid) AS definicao
FROM pg_constraint
WHERE conrelid = 'public.user_profile'::regclass
ORDER BY conname;

-- 3. Triggers
SELECT trigger_name, event_manipulation, action_timing
FROM information_schema.triggers
WHERE event_object_schema = 'public' AND event_object_table = 'user_profile'
ORDER BY trigger_name;

-- 4. Políticas de RLS
SELECT policyname, cmd, roles, qual, with_check
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'user_profile'
ORDER BY policyname;

-- 5. Inconsistência: usuários sem perfil (esperado zero daqui pra frente)
SELECT au.id, au.email, au.created_at
FROM auth.users au
LEFT JOIN public.user_profile up ON up.id = au.id
WHERE up.id IS NULL;
