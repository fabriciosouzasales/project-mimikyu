/*
================================================================
Projeto.....: Project Mimikyu
Runbook.....: CONCURRENCY-PROOF-PREVIEW-STALE
               Prova externa de PREVIEW_STALE sob espera real de lock
Versão......: 1.0
Status......: EXECUTADO (2026-09-09) — VEREDITO PASS
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-08 (COLLECTIONS-BULK-02-GATE-A-REVISION-02)

================================================================
O QUE ESTA PROVA COBRE — E O QUE NÃO COBRE
================================================================
COBRE **um único** blocker concreto, distinto de tudo que BULK-01 já
provou: quando a sessão B **espera** no `FOR UPDATE` da Collection
(passo 4 de `5150`, adquirido por `5148`) e o lock é liberado pelo
COMMIT de A, o recálculo do `preview_fingerprint` (passo 5, `5149`)
**tem de enxergar o estado NOVO** e devolver `PREVIEW_STALE`.

É a prova de correção do `VOLATILE` de `5149`. Com `STABLE`, o
snapshot poderia ser anterior ao COMMIT de A, o fingerprint bateria
com o antigo e B escreveria sobre um mundo que já mudou — falha
silenciosa, invisível em sessão única.

NÃO COBRE, e não deve repetir: `K01`/`K02`/`K03` de BULK-01, que
provaram a serialização de `claim_bulk_operation()` pelo índice único.
`5150` apenas consome aquele helper; aquilo continua provado e não é
reaberto aqui.

================================================================
POR QUE NÃO CABE NO HARNESS 5822
================================================================
Exige DUAS transações simultâneas, com a de A aberta enquanto B
bloqueia. A limitação do canal MCP `execute_sql` já havia sido
observada em 2026-09-07 no BULK-01 e foi reconfirmada nesta rodada, em
2026-09-09: chamadas separadas não preservam a mesma
sessão/transação. Mesma classe de
`K01`–`K03`; mesmo tratamento: prova externa por roteiro manual,
**jamais** convertida em PASS artificial dentro do harness.

================================================================
CONFIGURAÇÃO DE CONEXÕES
================================================================
| Papel | Conexão | Tipo | Para quê |
|---|---|---|---|
| **ADMIN** | `psql` ou SQL Editor | one-shot | fixtures, F0, guards, cleanup |
| **A** | `psql` PERSISTENTE | Session Pooler :5432 | segura a Collection com transação aberta |
| **B** | `psql` PERSISTENTE | Session Pooler :5432 | chama `register_physical_cards_bulk()` e bloqueia |
| **OBS** | SQL Editor do Supabase | one-shot | `pg_blocking_pids` / `pg_stat_activity` |

Só A e B precisam de sessão PERSISTENTE, porque dependem de transação
aberta atravessando comandos. O observador emite uma consulta única e
autocontida — por isso o SQL Editor serve para ele e **não** serve
para A/B.

**Papel de conexão de B.** B precisa de `EXECUTE` em
`register_physical_cards_bulk` e de nada mais. `authenticated` tem
esse `EXECUTE` por `5150`. Para não depender de sessão autenticada
real, o PASSO 0-bis cria a role temporária `bulk_preview_probe` com
exatamente esse privilégio — **sem** acesso direto a tabela alguma e
**sem** `EXECUTE` nos helpers internos (`5147`/`5148`/`5149`,
`claim`/`complete`). Ela é removida no cleanup.

**Papel de conexão de A.** A precisa apenas de `EXECUTE` em
`archive_collection` (que `authenticated` tem). Neste roteiro A usa a
mesma role temporária, com esse `EXECUTE` adicional.

**F0 é obtido pelo ADMIN.** `preview_fingerprint_register_physical_cards`
é helper INTERNO desde a `REVISION-02` — `EXECUTE` revogado dos quatro
papéis. Só o owner (`postgres`) a alcança. Isso é o contrato, não uma
limitação do roteiro: em produção o F0 virá da RPC pública de Preview
de `BULK-03`, que a chamará de dentro do seu próprio `SECURITY DEFINER`.

================================================================
RESULTADO OBRIGATÓRIO
================================================================
    B falha com PREVIEW_STALE.

NÃO é aceito:
  - `collection is archived — reactivate before registering`
    (significaria que a validação de domínio rodou ANTES do
     fingerprint — ordem errada);
  - sucesso `CREATED`
    (significaria que o recálculo leu estado velho — `STABLE`);
  - qualquer outro erro.

E a `idempotency_key` de B **não pode deixar resíduo**: a linha em
`bulk_operation` some com o ROLLBACK implícito do erro.

================================================================
*/


-- ================================================================
-- PASSO 0 — ADMIN. Pré-condições.
-- ================================================================
-- CONEXÃO ADMINISTRATIVA (owner)

SELECT
    (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'register_physical_cards_bulk')            AS tem_5150,
    (SELECT p.provolatile FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'preview_fingerprint_register_physical_cards')
                                                                                            AS volatilidade_5149,
    (SELECT count(*) FROM public.bulk_operation)                                            AS bulk_ops_antes;

-- Esperado: tem_5150 = 1, volatilidade_5149 = 'v', e anote
-- `bulk_ops_antes` para o postcheck do PASSO 12.
--     BULK_OPS_ANTES = ____________


-- ================================================================
-- PASSO 0-bis — ADMIN. Role temporária de privilégio mínimo.
-- ================================================================
-- CONEXÃO ADMINISTRATIVA (owner)

CREATE ROLE bulk_preview_probe LOGIN PASSWORD '<SENHA_TEMPORARIA_FORTE>';

GRANT USAGE ON SCHEMA public TO bulk_preview_probe;
GRANT EXECUTE ON FUNCTION public.register_physical_cards_bulk(JSONB) TO bulk_preview_probe;
GRANT EXECUTE ON FUNCTION public.archive_collection(UUID)            TO bulk_preview_probe;

-- CHECK OBRIGATÓRIO: a role NÃO pode ler tabela alguma de patrimônio
-- nem alcançar helper interno. Se qualquer coluna vier `true`, PARE.
SELECT has_table_privilege('bulk_preview_probe','public.bulk_operation','SELECT')        AS le_ledger,
       has_table_privilege('bulk_preview_probe','public.collection','SELECT')            AS le_collection,
       has_table_privilege('bulk_preview_probe','public.physical_card','SELECT')         AS le_physical_card,
       has_function_privilege('bulk_preview_probe',
           'public.preview_fingerprint_register_physical_cards(jsonb,uuid,uuid)','EXECUTE') AS exec_5149,
       has_function_privilege('bulk_preview_probe',
           'public.bulk_lock_operation_scope(uuid,uuid)','EXECUTE')                      AS exec_5148,
       has_function_privilege('bulk_preview_probe',
           'public.claim_bulk_operation(text,uuid,text,text)','EXECUTE')                 AS exec_claim;

-- Esperado: TODAS false.


-- ================================================================
-- PASSO 1 — ADMIN. Fixtures.
-- ================================================================
-- CONEXÃO ADMINISTRATIVA (owner)
--
-- Esta prova COMITA dados reais. O PASSO 11 os remove e o PASSO 12
-- confirma resíduo zero. Rodar em ambiente onde isso é aceitável.

BEGIN;

-- Identidade do usuário dono, para as RPCs que dependem de auth.uid().
SELECT set_config('request.jwt.claims',
    json_build_object('sub', (SELECT id::text FROM auth.users ORDER BY created_at, id LIMIT 1),
                      'role','authenticated')::text, TRUE);

-- Storage e Collection ACTIVE, pelas RPCs canônicas.
SELECT id AS storage_id FROM public.create_storage_container('PREVIEW STALE PROBE SC');
-- >>> ANOTE:  STORAGE_ID = ____________________________________

SELECT c.id AS collection_id
  FROM public.create_collection(
           (SELECT ex.game_id
              FROM public.card_variant cv
              JOIN public.card ca      ON ca.id = cv.card_id
              JOIN public.card_set cs  ON cs.id = ca.card_set_id
              JOIN public.expansion ex ON ex.id = cs.expansion_id
             ORDER BY cv.id LIMIT 1),
           'PREVIEW STALE PROBE COL', NULL,
           '<STORAGE_ID>'::uuid) c;
-- >>> ANOTE:  COLLECTION_ID = _________________________________

SELECT cv.id AS card_variant_id,
       (SELECT l.id FROM public.language l ORDER BY l.id LIMIT 1) AS language_id,
       (SELECT u.id FROM auth.users u ORDER BY u.created_at, u.id LIMIT 1) AS owner_user_id
  FROM public.card_variant cv ORDER BY cv.id LIMIT 1;
-- >>> ANOTE:  CARD_VARIANT_ID = _______________________________
-- >>> ANOTE:  LANGUAGE_ID     = _______________________________
-- >>> ANOTE:  OWNER_USER_ID   = _______________________________

COMMIT;


-- ================================================================
-- PASSO 2 — ADMIN. Obter F0, o fingerprint do estado ACTIVE.
-- ================================================================
-- CONEXÃO ADMINISTRATIVA (owner) — 5149 é helper INTERNO e só o owner
-- a alcança. Em produção este valor virá da RPC de Preview de BULK-03.

SELECT set_config('request.jwt.claims',
    json_build_object('sub','<OWNER_USER_ID>','role','authenticated')::text, FALSE);

SELECT public.preview_fingerprint_register_physical_cards(
           jsonb_build_array(jsonb_build_object(
               'card_variant_id','<CARD_VARIANT_ID>',
               'language_id','<LANGUAGE_ID>',
               'quantity', 2)),
           '<COLLECTION_ID>'::uuid,
           '<STORAGE_ID>'::uuid
       ) AS f0;

-- >>> ANOTE:  F0 = ___________________________________________
--
-- F0 é o ÚNICO caminho legítimo: a sessão B não tem — e não deve ter —
-- acesso a 5149 nem às tabelas para recalcular por conta própria.


-- ================================================================
-- PASSO 3 — SESSÃO A. Trava e altera a Collection. NÃO comita ainda.
-- ================================================================
-- psql PERSISTENTE, role bulk_preview_probe

BEGIN;

SELECT set_config('request.jwt.claims',
    json_build_object('sub','<OWNER_USER_ID>','role','authenticated')::text, TRUE);

SELECT public.archive_collection('<COLLECTION_ID>'::uuid);

-- >>> DEIXE A TRANSAÇÃO ABERTA. Não digite COMMIT ainda.
-- >>> Anote o PID desta sessão:
SELECT pg_backend_pid() AS pid_a;
--     PID_A = ____________


-- ================================================================
-- PASSO 4 — SESSÃO B. Chama B1 com F0. DEVE BLOQUEAR.
-- ================================================================
-- psql PERSISTENTE, role bulk_preview_probe
--
-- Use uma idempotency_key nova e ANOTE-A: o PASSO 10 confirma que ela
-- não deixou resíduo.
--     IDEMPOTENCY_KEY_B = _____________________________________

BEGIN;

SELECT set_config('request.jwt.claims',
    json_build_object('sub','<OWNER_USER_ID>','role','authenticated')::text, TRUE);

SELECT pg_backend_pid() AS pid_b;
--     PID_B = ____________

SELECT public.register_physical_cards_bulk(jsonb_build_object(
    'idempotency_key',      '<IDEMPOTENCY_KEY_B>',
    'preview_fingerprint',  '<F0>',
    'items',                jsonb_build_array(jsonb_build_object(
                                'card_variant_id','<CARD_VARIANT_ID>',
                                'language_id','<LANGUAGE_ID>',
                                'quantity', 2)),
    'collection_id',        '<COLLECTION_ID>',
    'storage_container_id', '<STORAGE_ID>'
));

-- >>> ESPERADO: o comando FICA PENDURADO. B passou pelos guards, pelo
-- >>> claim e pelo lock de INVENTORY, e agora espera no FOR UPDATE da
-- >>> COLLECTION que A segura. NÃO cancele.


-- ================================================================
-- PASSO 5 — OBSERVADOR. Confirmar que B está bloqueado POR A.
-- ================================================================
-- SQL Editor do Supabase — consulta ONE-SHOT, somente leitura

SELECT a.pid,
       a.state,
       a.wait_event_type,
       a.wait_event,
       pg_blocking_pids(a.pid) AS bloqueado_por,
       (pg_blocking_pids(a.pid) @> ARRAY[<PID_A>]) AS bloqueado_por_a,
       left(a.query, 60) AS query
  FROM pg_stat_activity a
 WHERE a.pid IN (<PID_A>, <PID_B>);

-- Esperado para PID_B: state='active', wait_event_type='Lock',
-- wait_event='transactionid', bloqueado_por_a = true.
--
-- Se B NÃO estiver bloqueado, a prova está inválida: ou B falhou antes
-- do passo 4 de 5150 (leia o erro), ou A não segurou o lock.


-- ================================================================
-- PASSO 6 — SESSÃO A. COMMIT.
-- ================================================================
-- psql PERSISTENTE — a MESMA sessão A do PASSO 3

COMMIT;


-- ================================================================
-- PASSO 7 — SESSÃO B. Ler o desfecho.
-- ================================================================
-- Nada a digitar: o comando do PASSO 4 desbloqueia sozinho.
--
-- RESULTADO OBRIGATÓRIO:
--
--     ERROR:  PREVIEW_STALE: o estado mudou desde o preview —
--             refaca o preview e confirme novamente
--
-- >>> TRANSCREVA a mensagem EXATA recebida:
--     MENSAGEM_B = ____________________________________________
--
-- FALHA DA PROVA se vier:
--   - 'collection is archived — reactivate before registering'
--         => a validação de domínio rodou ANTES do fingerprint.
--            Ordem do caminho NEW está errada em 5150.
--   - sucesso (outcome CREATED)
--         => o recálculo leu estado ANTERIOR ao COMMIT de A.
--            É exatamente o defeito do STABLE. Reverificar
--            `provolatile` de 5149.
--   - qualquer outro erro
--         => investigar antes de prosseguir.


-- ================================================================
-- PASSO 8 — SESSÃO B. Encerrar a transação abortada.
-- ================================================================
-- psql PERSISTENTE — a MESMA sessão B

ROLLBACK;


-- ================================================================
-- PASSO 9 — SESSÃO B. Contraprova: com o fingerprint NOVO, funciona.
-- ================================================================
-- Primeiro, ADMIN reativa a Collection e emite F1:
--
--   -- CONEXÃO ADMINISTRATIVA (owner)
--   SELECT set_config('request.jwt.claims',
--       json_build_object('sub','<OWNER_USER_ID>','role','authenticated')::text, FALSE);
--   SELECT public.reactivate_collection('<COLLECTION_ID>'::uuid);
--   SELECT public.preview_fingerprint_register_physical_cards(
--              jsonb_build_array(jsonb_build_object(
--                  'card_variant_id','<CARD_VARIANT_ID>',
--                  'language_id','<LANGUAGE_ID>','quantity',2)),
--              '<COLLECTION_ID>'::uuid, '<STORAGE_ID>'::uuid) AS f1;
--   -- >>> ANOTE: F1 = ______________________  (deve ser DIFERENTE de F0)
--
-- Depois, na SESSÃO B (role bulk_preview_probe), com chave NOVA:

BEGIN;
SELECT set_config('request.jwt.claims',
    json_build_object('sub','<OWNER_USER_ID>','role','authenticated')::text, TRUE);

SELECT public.register_physical_cards_bulk(jsonb_build_object(
    'idempotency_key',      '<IDEMPOTENCY_KEY_B2>',
    'preview_fingerprint',  '<F1>',
    'items',                jsonb_build_array(jsonb_build_object(
                                'card_variant_id','<CARD_VARIANT_ID>',
                                'language_id','<LANGUAGE_ID>',
                                'quantity', 2)),
    'collection_id',        '<COLLECTION_ID>',
    'storage_container_id', '<STORAGE_ID>'
));

ROLLBACK;

-- Esperado: outcome = 'CREATED', created_count = 2.
-- Esta contraprova importa: sem ela, um PREVIEW_STALE que dispara
-- SEMPRE passaria pelo PASSO 7 sem provar nada.
-- O ROLLBACK garante que nada é escrito aqui.


-- ================================================================
-- PASSO 10 — ADMIN. Resíduo do claim de B.
-- ================================================================
-- CONEXÃO ADMINISTRATIVA (owner)

SELECT count(*) AS residuo_chave_b
  FROM public.bulk_operation
 WHERE idempotency_key IN ('<IDEMPOTENCY_KEY_B>'::uuid, '<IDEMPOTENCY_KEY_B2>'::uuid);

-- Esperado: 0. A falha do PASSO 7 e o ROLLBACK do PASSO 9 derrubaram
-- também os claims — a chave nunca é consumida por operação que não
-- comitou.


-- ================================================================
-- PASSO 11 — ADMIN. Cleanup.
-- ================================================================
-- CONEXÃO ADMINISTRATIVA (owner)

BEGIN;

SELECT set_config('request.jwt.claims',
    json_build_object('sub','<OWNER_USER_ID>','role','authenticated')::text, TRUE);

-- Ordem: Collection antes do Storage (FK de default_storage_container_id).
SELECT public.delete_collection('<COLLECTION_ID>'::uuid);

DELETE FROM public.storage_container WHERE id = '<STORAGE_ID>'::uuid;

COMMIT;

REVOKE EXECUTE ON FUNCTION public.register_physical_cards_bulk(JSONB) FROM bulk_preview_probe;
REVOKE EXECUTE ON FUNCTION public.archive_collection(UUID)            FROM bulk_preview_probe;
REVOKE USAGE ON SCHEMA public                                          FROM bulk_preview_probe;
DROP ROLE bulk_preview_probe;


-- ================================================================
-- PASSO 12 — ADMIN. Postcheck de resíduo zero.
-- ================================================================
-- CONEXÃO ADMINISTRATIVA (owner)

SELECT (SELECT count(*) FROM public.bulk_operation) AS bulk_ops_depois,
       (SELECT count(*) FROM public.collection
         WHERE name = 'PREVIEW STALE PROBE COL')     AS col_residuo,
       (SELECT count(*) FROM public.storage_container
         WHERE name = 'PREVIEW STALE PROBE SC')      AS sc_residuo,
       (SELECT count(*) FROM pg_roles
         WHERE rolname = 'bulk_preview_probe')       AS role_residuo;

-- Esperado: bulk_ops_depois = <BULK_OPS_ANTES> (PASSO 0);
-- col_residuo = 0; sc_residuo = 0; role_residuo = 0.


/*
================================================================
REGISTRO DA EXECUÇÃO — PREENCHIDO
================================================================
Data ...........................: 2026-09-09
Executor .......................: Fabrício Sales
Configuração ...................: duas sessões `psql` PERSISTENTES (A e B,
                                  Session Pooler porta 5432, role temporária
                                  `bulk_preview_probe`) + observador one-shot
                                  pelo SQL Editor do Supabase

volatilidade_5149 (PASSO 0) ....: v                       [OBRIGATÓRIO 'v'  — OK]
PID_A / PID_B ..................: observados e conferidos na execução;
                                  NÃO transcritos aqui — identificadores
                                  efêmeros de processo, sem valor de
                                  auditoria posterior. O que importa é o
                                  `bloqueado_por_a` abaixo, que foi medido
                                  com esses PIDs.
bloqueado_por_a (PASSO 5) ......: true                    [OBRIGATÓRIO true — OK]
wait_event (PASSO 5) ...........: transactionid           [ESPERADO         — OK]
MENSAGEM_B (PASSO 7) ...........: PREVIEW_STALE           [OBRIGATÓRIO      — OK]
                                  NÃO veio 'collection is archived'
                                  NÃO veio sucesso CREATED
F0 <> F1 (PASSO 9) .............: true                    [OBRIGATÓRIO true — OK]
contraprova (PASSO 9) ..........: CREATED / 2 cartas      [OBRIGATÓRIO      — OK]
residuo das 2 chaves (PASSO 10) : 0                       [OBRIGATÓRIO 0    — OK]
Collection temporária (PASSO 12): 0                       [OBRIGATÓRIO 0    — OK]
Storage temporário (PASSO 12) ..: 0                       [OBRIGATÓRIO 0    — OK]
role bulk_preview_probe (P.12) .: 0                       [OBRIGATÓRIO 0    — OK]

VEREDITO .......................: **PASS**
================================================================
O QUE ESTE PASS PROVA, LITERALMENTE
----------------------------------------------------------------
Que o recálculo do `preview_fingerprint` feito por `5149` DEPOIS de a
sessão B esperar no `FOR UPDATE` da Collection enxerga o estado
posterior ao COMMIT de A — e não o anterior. É a prova de correção do
`VOLATILE`: com `STABLE`, B teria escrito sobre um mundo já mudado, em
silêncio.

E prova também a ORDEM do caminho NEW: o erro foi `PREVIEW_STALE`
(passo 5), não `collection is archived` (passo 6).

NÃO transcritos por política: UUIDs das fixtures, senha da role
temporária, valores reais de F0/F1. Nenhum deles tem valor de auditoria
e todos são recriáveis reexecutando o roteiro.
================================================================
*/
