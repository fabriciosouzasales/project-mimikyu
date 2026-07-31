/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2812 - Validate Card Set Create
Versão......: 1.1
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-31

Descrição...:
Validação estrutural e funcional de admin_create_card_set()
(Query 2051, ADR-023, emenda 2026-07-31 "Card Set: cadastro real
via UI"). Mesmo roteiro de validação já usado para as demais
funções administrativas de criação (Queries 2804/2805).

v1.1 (mesmo dia): reaberta para re-execução depois do
CREATE OR REPLACE de admin_create_card_set() v1.1 (correção do
gap ENERGY, ver Query 2051) — assinatura da função não mudou
(mesmos 8 parâmetros), só a lógica interna, então a query 2
(privilégios) permanece válida como está; adicionado item 4 para
exercitar o cenário ENERGY que motivou a correção.
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

-- 4. Constraint de card_set já aceita ENERGY (Migration 263,
--    reconciliada no arquivo canônico 120 nesta mesma rodada — v2.2)
SELECT conname, pg_get_constraintdef(oid) AS definicao
FROM pg_constraint
WHERE conrelid = 'public.card_set'::regclass
  AND conname = 'ck_card_set_type';

-- ================================================================
-- Validação estrutural (queries 2/4 acima): query 2 CONFIRMADA
-- EXECUTADA em 2026-07-31 contra a v1.0 (anon sem EXECUTE,
-- authenticated com EXECUTE) — assinatura inalterada em v1.1, não
-- precisa ser re-rodada. Query 3 (catalog_admin_action_log) não
-- re-testada isoladamente — já confirmada com CARD_SET_CREATED desde
-- a Query 2049 (v1.2). Query 4 (ck_card_set_type inclui ENERGY):
-- PENDENTE, nova nesta rodada.
--
-- Validação funcional: cadastro geral, cenário PROMO e cenário ENERGY
-- TODOS CONFIRMADOS por Fabrício em 2026-07-31, testados diretamente
-- pela interface ("Nova Coleção") — "Teste em tela validado! e
-- resposta da query como esperado." Segunda tentativa de Card Set
-- PROMO na mesma Expansion bloqueada corretamente por
-- uq_card_set_expansion_promo (ADMIN_CREATE_CARD_SET_DUPLICATE_PROMO);
-- cadastro de Card Set do tipo Energia confirmado funcionando após o
-- CREATE OR REPLACE de admin_create_card_set() v1.1. Cenários de
-- expansion_id inexistente e sessão não-administrativa não são
-- alcançáveis pela UI normal — ficam como cobertura teórica, mesmo
-- critério já aplicado às demais funções de criação do módulo.
-- ================================================================
