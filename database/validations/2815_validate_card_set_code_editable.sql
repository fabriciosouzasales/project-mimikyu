/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2815 - Validate Card Set Code Editable
Versão......: 1.0
Status......: CONFIRMADA EXECUTADA (Fabrício, 2026-08-01)
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-01

Descrição...:
Validação estrutural e funcional da Migration 2091
(admin_update_card_set() ganha `code` como campo condicionalmente
editável — ADR-023, emenda "Card Set: código editável sem Cards
cadastradas"). Mesmo roteiro de validação já usado em 2811, com um
cenário funcional extra para a trava condicional (bloqueio quando
já existem Cards cadastradas).
================================================================
*/

-- 1. Estrutura e privilégios da nova assinatura (6 parâmetros)
SELECT p.proname, p.prosecdef, p.proconfig
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'admin_update_card_set';

SELECT
    has_function_privilege('anon', 'public.admin_update_card_set(uuid, text, text, text, integer, date)', 'EXECUTE') AS anon_execute,
    has_function_privilege('authenticated', 'public.admin_update_card_set(uuid, text, text, text, integer, date)', 'EXECUTE') AS auth_execute;

-- 2. Confirma que a assinatura antiga (5 parâmetros, v2.0) não existe mais
--    — deve retornar zero linhas (DROP FUNCTION da Migration 2091 aplicado).
SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS assinatura
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'admin_update_card_set'
  AND pg_get_function_identity_arguments(p.oid) = 'p_id uuid, p_name text, p_set_type text, p_release_order integer, p_release_date date';

-- ================================================================
-- Validação estrutural (queries 1–2 acima): PENDENTE — aguardando
-- execução da Migration 2091 por Fabrício no Supabase, seguindo o
-- ritual de pareamento de SQL do projeto.
--
-- Validação funcional: PENDENTE — cobre três cenários:
-- (a) Card Set sem nenhuma Card cadastrada: código pode ser trocado
--     livremente pela tela de edição (caso real que motivou esta
--     Query — Coleção "151", código SV4 → MEW).
-- (b) Card Set com ao menos uma Card cadastrada: tentar trocar o
--     código deve falhar com ADMIN_UPDATE_CARD_SET_CODE_LOCKED,
--     mensagem visível na tela de edição.
-- (c) Trocar o código para um valor já usado por outro Card Set da
--     mesma Expansão deve falhar com
--     ADMIN_UPDATE_CARD_SET_DUPLICATE_CODE.
-- Cenários de id inexistente e sessão não-administrativa não são
-- alcançáveis pela UI normal — ficam como cobertura teórica, mesmo
-- critério já aplicado às validações anteriores desta família.
-- ================================================================
