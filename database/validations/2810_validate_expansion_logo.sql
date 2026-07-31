/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2810 - Validate Expansion Logo
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-31

Descrição...:
Validação consolidada das Queries 2045-2047 (mesmo padrão da Query 277,
que consolidou a validação da logo de Card Set): coluna e CHECK de logo
em expansion, a função administrativa de escrita, e o bucket privado com
suas quatro políticas de Storage.
================================================================
*/

-- Bloco 1: coluna + CHECK em expansion
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'expansion' AND column_name = 'logo_storage_path';
-- Esperado: logo_storage_path / text / YES / NULL

SELECT conname, pg_get_constraintdef(oid) AS definicao
FROM pg_constraint
WHERE conrelid = 'public.expansion'::regclass
  AND conname = 'ck_expansion_logo_storage_path_not_url';
-- Esperado: CHECK (((logo_storage_path IS NULL) OR (logo_storage_path !~* '^[a-z][a-z0-9+.-]*://'::text)))

-- Bloco 2: nenhuma política de escrita em expansion (a escrita é só via função)
SELECT policyname, cmd
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'expansion' AND cmd <> 'SELECT';
-- Esperado: zero linhas

-- Bloco 3: segurança da função admin_set_expansion_logo()
SELECT p.proname, p.prosecdef, p.proconfig,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_pode_executar,
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_pode_executar
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'admin_set_expansion_logo';
-- Esperado: prosecdef = true, proconfig contém search_path="", authenticated = true, anon = false

-- Bloco 4: bucket privado, fora do catálogo storage_bucket
SELECT id, public FROM storage.buckets WHERE id = 'expansion-logo';
-- Esperado: public = false

SELECT COUNT(*) AS registrado_em_storage_bucket
FROM public.storage_bucket WHERE code = 'expansion-logo';
-- Esperado: 0

-- Bloco 5: as quatro políticas de Storage
SELECT policyname, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname LIKE 'expansion_logo_admin_%'
ORDER BY policyname;
-- Esperado: 4 linhas (select/insert/update/delete), todas com
-- bucket_id = 'expansion-logo' AND is_admin() em qual e/ou with_check

-- ================================================================
-- Blocos 1 (só a constraint), 3 e 5: CONFIRMADOS EXECUTADOS em 2026-07-31,
-- resultados reais conferidos individualmente durante a execução pareada
-- das Queries 2045-2047 (consolidados aqui como roteiro reexecutável).
-- Blocos 2 e 4, e a parte de information_schema.columns do Bloco 1: não
-- rodados isoladamente nesta rodada — a constraint (Bloco 1) e as políticas
-- (Bloco 5) só existiriam se a coluna e o bucket também tivessem sido
-- criados com sucesso (mesma transação em cada Query), então a ausência de
-- erro nas Queries 2045/2047 já é evidência indireta. Chamada efetiva de
-- admin_set_expansion_logo() não testada em tempo real — validado por
-- revisão estrutural da função (mesmo critério da Query 277).
-- ================================================================
