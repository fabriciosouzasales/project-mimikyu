/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2811 - Validate Card Set Update and Delete
Versão......: 1.0
Status......: PROPOSTA (aguardando execução/confirmação de Fabrício)
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-31

Descrição...:
Validação estrutural e funcional da emenda de atualização e
exclusão real de Card Set (ADR-023, 2026-07-31):
admin_update_card_set() (Query 2048), constraints atualizadas
(Query 2049) e admin_delete_card_set() (Query 2050). Mesmo
roteiro de validação já usado em Expansion (Query 2809), com um
bloco a mais (4) para a função de atualização.
================================================================
*/

-- 1. Constraints de catalog_admin_action_log incluem CARD_SET_DELETED
--    (e, por reconciliação do gap do arquivo canônico, EXPANSION_DELETED)
SELECT conname, pg_get_constraintdef(oid) AS definicao
FROM pg_constraint
WHERE conrelid = 'public.catalog_admin_action_log'::regclass
  AND conname IN ('ck_catalog_admin_action_log_action_valid', 'ck_catalog_admin_action_log_action_entity_match');

-- 2. Estrutura de admin_delete_card_set()
SELECT p.proname, p.prosecdef, p.proconfig
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'admin_delete_card_set';

-- 3. Privilégios de admin_delete_card_set()
SELECT
    has_function_privilege('anon', 'public.admin_delete_card_set(uuid)', 'EXECUTE') AS anon_execute,
    has_function_privilege('authenticated', 'public.admin_delete_card_set(uuid)', 'EXECUTE') AS auth_execute;

-- 4. Estrutura e privilégios de admin_update_card_set()
SELECT p.proname, p.prosecdef, p.proconfig
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'admin_update_card_set';

SELECT
    has_function_privilege('anon', 'public.admin_update_card_set(uuid, text, integer)', 'EXECUTE') AS anon_execute,
    has_function_privilege('authenticated', 'public.admin_update_card_set(uuid, text, integer)', 'EXECUTE') AS auth_execute;

-- ================================================================
-- Validação estrutural (queries 1–4 acima): PENDENTE — aguardando
-- execução das Queries 2048/2049/2050 por Fabrício no Supabase,
-- seguindo o ritual de pareamento de SQL do projeto (uma Query por
-- vez, confirmada por captura de tela antes de avançar).
--
-- Validação funcional: PENDENTE — cobre o caminho principal do
-- usuário (edição bem-sucedida via "Editar Card Set" na galeria de
-- Coleções; exclusão bem-sucedida e bloqueio ao tentar excluir um
-- Card Set com Cards associadas). Cenários de id inexistente e
-- sessão não-administrativa não são alcançáveis pela UI normal —
-- ficam como cobertura teórica, mesmo critério já aplicado a
-- admin_delete_expansion()/admin_delete_game().
-- ================================================================
