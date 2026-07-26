/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 1810 - Validate Reserved Username
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-25

Descrição...:
Validação de public.reserved_username: estrutura, contagem de
registros, trigger de updated_at e ausência de políticas de RLS
(esperado — só functions SECURITY DEFINER leem esta tabela).
================================================================
*/

SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'reserved_username'
ORDER BY ordinal_position;

SELECT count(*) AS total FROM public.reserved_username;

SELECT trigger_name, event_manipulation, action_timing
FROM information_schema.triggers
WHERE event_object_schema = 'public' AND event_object_table = 'reserved_username';

-- Esperado: nenhuma linha (sem política direta para anon/authenticated).
SELECT policyname FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'reserved_username';
