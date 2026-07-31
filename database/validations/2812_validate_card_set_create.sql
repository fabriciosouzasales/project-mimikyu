/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2812 - Validate Card Set Create
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-31

Descrição...:
Validação estrutural e funcional de admin_create_card_set()
(Query 2051, ADR-023, emenda 2026-07-31 "Card Set: cadastro real
via UI"). Mesmo roteiro de validação já usado para as demais
funções administrativas de criação (Queries 2804/2805).
================================================================
*/

-- 1. Estrutura de admin_create_card_set()
SELECT p.proname, p.prosecdef, p.proconfig
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'admin_create_card_set';

-- 2. Privilégios de admin_create_card_set()
SELECT
    has_function_privilege('anon', 'public.admin_create_card_set(uuid, text, text, text, integer, integer, integer, date)', 'EXECUTE') AS anon_execute,
    has_function_privilege('authenticated', 'public.admin_create_card_set(uuid, text, text, text, integer, integer, integer, date)', 'EXECUTE') AS auth_execute;

-- 3. Constraint de catalog_admin_action_log já cobre CARD_SET_CREATED
--    (reconfirmação — o valor já existia desde a Query 2049, v1.2)
SELECT conname, pg_get_constraintdef(oid) AS definicao
FROM pg_constraint
WHERE conrelid = 'public.catalog_admin_action_log'::regclass
  AND conname IN ('ck_catalog_admin_action_log_action_valid', 'ck_catalog_admin_action_log_action_entity_match');

-- ================================================================
-- Validação estrutural (query 2 acima): CONFIRMADA EXECUTADA em
-- 2026-07-31 — has_function_privilege confirma anon sem EXECUTE,
-- authenticated com EXECUTE. Constraint de catalog_admin_action_log
-- (query 3) não re-testada isoladamente nesta rodada — já confirmada
-- com CARD_SET_CREATED desde a Query 2049 (v1.2).
--
-- Validação funcional: CONFIRMADA por Fabrício em 2026-07-31,
-- testada diretamente pela interface ("Nova Coleção" na galeria de
-- Coleções) — "Funcionando perfeitamente bem". Cenário PROMO
-- exercitado explicitamente: segunda tentativa de Card Set PROMO na
-- mesma Expansion bloqueada corretamente por
-- uq_card_set_expansion_promo, com a mensagem administrativa clara
-- (ADMIN_CREATE_CARD_SET_DUPLICATE_PROMO) exibida na tela. Cenários
-- de expansion_id inexistente e sessão não-administrativa não são
-- alcançáveis pela UI normal — ficam como cobertura teórica, mesmo
-- critério já aplicado às demais funções de criação do módulo.
-- ================================================================
