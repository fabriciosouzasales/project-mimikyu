/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2816 - Validate admin_start_asset_import_run()
Versão......: 1.2
Status......: EXECUTADA E CONFIRMADA por Fabrício em 2026-08-02
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-01 (v1.0), 2026-08-02 (v1.1, v1.2)

Descrição...:
Validação estrutural e funcional da Query 2092
(admin_start_asset_import_run(), continuação automática cartas →
imagens, emenda de ADR-024).

v1.1: a v1.0 confirmou só a estrutura (privilégios) — a validação
funcional real (cenário a) nunca chegou a ser exercitada de fato pelo
usuário antes de um bug ser descoberto em produção: a v1.0 da função
tinha `run_code` ambíguo (variável implícita de `RETURNS TABLE`
colidindo com a coluna), nunca conseguia inserir uma run de verdade —
toda chamada com `supported = true` falhava com um erro genérico de
Postgres não relacionado ao domínio (`column reference "run_code" is
ambiguous`), confirmado nos logs. Query 3 abaixo, nova nesta versão,
comprova a correção diretamente.

v1.2: testando a v1.1 contra uma Coleção real e grande (SV4/Fenda
Paradoxal, 266 cartas), a Edge Function import-card-assets morreu no
meio do processamento (timeout de plataforma) e deixou uma linha
presa em RUNNING para sempre — a regra "evita runs duplicadas" da
v1.0/v1.1 então bloqueava qualquer nova tentativa para aquele Card Set
indefinidamente. Query 4 abaixo, nova nesta versão, comprova que a
correção (fechar automaticamente runs PENDING/RUNNING mais velhas que
15 minutos como FAILED, antes de abrir uma nova) libera o Card Set.
================================================================
*/

-- 1. Estrutura e privilégios
SELECT p.proname, p.prosecdef, p.proconfig
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'admin_start_asset_import_run';

SELECT
    has_function_privilege('anon', 'public.admin_start_asset_import_run(uuid, text, text)', 'EXECUTE') AS anon_execute,
    has_function_privilege('authenticated', 'public.admin_start_asset_import_run(uuid, text, text)', 'EXECUTE') AS auth_execute;

-- 2. Card Sets com suporte real hoje (card_set_external_reference ativo para TCGDEX)
--    — útil para escolher um cenário de teste "supported = true" real.
SELECT cs.code, cs.name, cser.external_set_id
FROM card_set_external_reference cser
JOIN card_set cs ON cs.id = cser.card_set_id
JOIN asset_source src ON src.id = cser.asset_source_id
WHERE src.code = 'TCGDEX' AND cser.is_active = true
ORDER BY cs.code;

-- 3. Prova direta da correção v1.1 — nenhuma run deveria existir para
--    nenhum Card Set ainda (bug da v1.0 impedia o INSERT de sempre
--    completar); depois de reexecutar a Query 2092 corrigida e usar a
--    tela normalmente em um Card Set com suporte (ex.: recadastrar a
--    referência de "151"/MEW — ver correção de dado à parte), esta
--    consulta deve passar a listar linhas.
SELECT air.id, air.run_code, air.status, air.card_set_id, air.created_at
FROM asset_import_run air
WHERE air.execution_context = 'SYSTEM'
ORDER BY air.created_at DESC
LIMIT 20;

-- 4. Prova direta da correção v1.2 — depois de reexecutar a Query
--    2092 corrigida e usar a tela de importação de imagens novamente
--    no Card Set SV4 (que tinha uma run presa em RUNNING desde
--    2026-08-02 01:39 UTC), a linha antiga deve aparecer como FAILED
--    (com o error_summary explicando o motivo) e uma nova linha em
--    PENDING/RUNNING deve existir para o mesmo card_set_id.
SELECT air.id, air.run_code, air.status, air.card_set_id,
       air.error_summary, air.created_at, air.finished_at
FROM asset_import_run air
WHERE air.card_set_id = '6964017b-4df5-4053-af56-9b22f6f7d353'
ORDER BY air.created_at DESC;

-- ================================================================
-- Validação estrutural (queries 1–2 acima): CONFIRMADA EXECUTADA
-- (Fabrício, 2026-08-01) — mas cobria só privilégios/assinatura, não
-- pegou o bug de `run_code` ambíguo (erro em tempo de execução, não
-- de instalação).
--
-- Validação funcional (query 3): CONFIRMADA EXECUTADA (Fabrício,
-- 2026-08-02) — os três cenários (a/b/c) descritos abaixo foram
-- exercitados de fato ao testar a Coleção "151" e depois SV4.
--
-- Validação funcional v1.2 (query 4): PENDENTE — cobre o cenário (d):
-- (d) Run PENDING/RUNNING mais velha que 15 minutos: a próxima
--     chamada para o mesmo Card Set deve fechá-la como FAILED
--     automaticamente (error_summary preenchido, finished_at =
--     NOW()) e abrir uma run nova normalmente, em vez de devolver
--     `already_active = true` para sempre.
--
-- Cenários (a)/(b)/(c) originais, para referência:
-- (a) Card Set com card_set_external_reference/TCGDEX ativo:
--     `supported = true`, nova run criada em PENDING, run_code no
--     formato RUN-AAAAMMDD-NNNNNNNN.
-- (b) Card Set sem essa referência (ex.: Promo/Energia): `supported
--     = false`, run_id/run_code NULL, nenhuma linha inserida em
--     asset_import_run.
-- (c) Chamar duas vezes seguidas para o mesmo Card Set antes da
--     primeira run terminar (menos de 15 minutos): a segunda chamada
--     devolve `already_active = true` com o mesmo run_id/run_code da
--     primeira, sem duplicar.
-- ================================================================
