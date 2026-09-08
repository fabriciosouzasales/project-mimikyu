/*
================================================================
Projeto.....: Project Mimikyu
Artefato....: PROVA DE CONCORRÊNCIA EXTERNA — K01, K02, K03 (BULK-01)
Versão......: 1.2
Status......: ROTEIRO MANUAL — EXECUTADO em 2026-09-07 (K01/K02/K03 PASS)
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-07 (criado em
               COLLECTIONS-BULK-01-PHYSICAL-PROPOSAL-01;
               v1.1 em -POST-AUDIT-HARDENING-01;
               v1.2 em -PRECOMMIT-CORRECTION-02)

v1.1 — quatro correções:
  (a) guard de resíduo prévio cobre AS DUAS chaves, não só a primeira;
  (b) limpeza escopada por `(owner_user_id, operation_type,
      idempotency_key)` — a chave de identidade completa, não só
      `idempotency_key`;
  (c) postcheck com o MESMO escopo da limpeza;
  (d) canal de conexão declarado explicitamente.
      [SUPERSEDIDO pela v1.2 no que diz respeito ao PAPEL exigido.]

v1.2 — quatro correções, todas de ROTEIRO/DOCUMENTAÇÃO (nenhuma
lógica de migration foi tocada):
  (a) DEFEITO REAL DE ROTEIRO CORRIGIDO — o PASSO 4 recuperava o
      `operation_id` com um SELECT DIRETO em `public.bulk_operation`.
      Isso reproduzia exatamente a primeira tentativa inválida de `K02`
      na execução de 2026-09-07 e CONTRADIZIA o próprio contrato do
      ledger, que não tem caminho de acesso direto. O `operation_id`
      passa a ser ANOTADO no PASSO 1, a partir do retorno de CLAIMED,
      e usado literalmente no PASSO 4;
  (b) PAPEL DE CONEXÃO reescrito — não se exige mais "postgres ou papel
      administrativo" para A/B. Exige-se papel com EXECUTE EXPLÍCITO
      nos dois helpers, o que no estado normal só o owner possui; para
      a prova, cria-se uma role temporária de teste com privilégio
      mínimo (EXECUTE nos helpers e NADA na tabela), removida no
      cleanup;
  (c) SQL EDITOR DO SUPABASE deixa de ser tratado em bloco — ele NÃO
      serve para A/B (não preserva sessão/transação), mas SERVE como
      OBSERVADOR one-shot, porque o observador não precisa manter
      transação alguma;
  (d) as etapas que tocam a tabela diretamente (guard, contagens de
      estado e limpeza) passam a estar EXPLICITAMENTE marcadas como
      "CONEXÃO ADMINISTRATIVA", separadas das sessões A/B.

NÃO É MIGRATION. NÃO É NUMERADO NA FAIXA 5xxx.
Não promover para database/schema/. Não aplicar via apply_migration.

RESULTADO DESTA EXECUÇÃO (2026-09-07)
-------------------------------------
**`K01` PASS · `K02` PASS · `K03` PASS.**

Configuração efetivamente usada:
  - SESSÃO A: `psql` persistente, Session Pooler, porta 5432;
  - SESSÃO B: `psql` persistente, Session Pooler, porta 5432;
  - A e B conectaram com a role temporária `bulk_k_probe`, com EXECUTE
    explícito nos dois helpers e SEM acesso direto à tabela;
  - OBSERVADOR: consulta one-shot pelo SQL Editor do Supabase — não
    precisa de sessão persistente;
  - `bulk_k_probe` foi REMOVIDA no cleanup (`role_residuo = 0`).

Ou seja: DUAS sessões `psql` persistentes para A/B, mais observador
externo via SQL Editor do Supabase. Não foram três sessões `psql`.

Evidências registradas em `docs/05d-colecoes-e-usuarios.md`, seção
"Bulk Operations Foundation (BULK-01)": `pg_blocking_pids(B) = [A]`,
`bloqueado_por_a = true`, `wait_event_type = Lock`,
`wait_event = transactionid`; após COMMIT de A, B devolveu REPLAY com o
mesmo `operation_id` e contagem final da identidade = 1; após ROLLBACK
de A, B devolveu CLAIMED e a contagem final foi 0. Cleanup:
`fx_residuo = 0`, `role_residuo = 0`.

NOTA DE HONESTIDADE DA EXECUÇÃO: houve uma primeira tentativa inválida
de `K02` que tentou recuperar o `operation_id` por SELECT DIRETO na
tabela usando a role temporária — que, corretamente, não tem esse
privilégio. A transação foi revertida, a chave reconfirmada em
`count = 0`, e `K02` foi reexecutado usando o `operation_id` devolvido
pelo próprio claim. Não foi defeito do produto nem da migration: foi
defeito DESTE ROTEIRO, corrigido na v1.2 (correção `a` acima).

Este arquivo permanece no repositório como **roteiro genérico
reutilizável** — os valores de OWNER/CHAVE1/CHAVE2/OPERATION_ID são
placeholders de propósito, para que a prova possa ser repetida em
qualquer ambiente sem carregar identificadores de uma execução
específica.

POR QUE ESTE ARQUIVO EXISTE
---------------------------
`K01`/`K02`/`K03` são gravados como NOT PROVEN **dentro** do harness
`5821`, por honestidade: exigem DUAS SESSÕES PERSISTENTES E
SIMULTÂNEAS, com a transação da sessão A ABERTA enquanto B tenta o
mesmo claim.

O canal MCP `execute_sql` NÃO oferece isso — foi medido, não presumido:
cada chamada é sessão/transação independente. Mesma classe de
`C04`/`R18` do `5818`, e mesmo tratamento: NOT PROVEN no harness,
PROVADO aqui.

O QUE ESTA PROVA ESTABELECE
---------------------------
Que o ÍNDICE ÚNICO `uq_bulk_operation_owner_type_key` — e não código de
aplicação — é o mecanismo de serialização:

  K01  B BLOQUEIA enquanto A está em voo com a mesma chave;
  K02  A COMMITA   -> B desbloqueia e NÃO insere linha nova
                      (REPLAY se mesmo hash, CONFLICT se hash diferente);
  K03  A ABORTA    -> B consegue o claim (CLAIMED).

================================================================
PAPEL DE CONEXÃO — LEIA ANTES DE ESCOLHER A STRING
================================================================
`claim_bulk_operation` e `complete_bulk_operation` são helpers
INTERNOS: `EXECUTE` está REVOGADO de `PUBLIC`, `anon`, `authenticated`
e `service_role`. No estado normal do banco, só o owner (`postgres`)
os alcança.

REGRA PARA A E B
----------------
  A e B precisam de um papel com EXECUTE **EXPLÍCITO** sobre os dois
  helpers. Não é exigido que esse papel seja `postgres` nem que seja
  administrativo — é exigido que TENHA O EXECUTE.

  No estado normal, apenas `postgres` satisfaz isso. Para a prova,
  a via recomendada é criar uma ROLE TEMPORÁRIA DE TESTE com
  privilégio MÍNIMO — EXECUTE nos dois helpers e NADA na tabela —,
  removida no cleanup. Foi exatamente o que a execução de 2026-09-07
  fez, com a role `bulk_k_probe`.

  `authenticated`, `anon` e `service_role` continuam SEM EXECUTE por
  padrão e NÃO SERVEM: a chamada falha com `42501 permission denied
  for function claim_bulk_operation` e a prova não chega a começar.
  Isso não é defeito — é o contrato do ledger interno funcionando.

  A role temporária NÃO deve receber privilégio sobre
  `public.bulk_operation`. Se ela conseguir dar SELECT na tabela, o
  ledger não está mais fechado. As etapas deste roteiro que precisam
  ler ou apagar linhas rodam por CONEXÃO ADMINISTRATIVA separada, e
  estão marcadas como tal.

  NÃO emitir `SET ROLE authenticated` em nenhum momento. O
  `set_config('request.jwt.claims', ...)` de cada passo existe apenas
  para que `auth.uid()` resolva o dono — ele NÃO troca de papel, e é
  exatamente assim que o chamador real opera: a RPC `SECURITY DEFINER`
  de BULK-02/BULK-04 roda como `postgres`.

REGRA PARA O OBSERVADOR
-----------------------
  Somente leitura sobre `pg_stat_activity` e `pg_blocking_pids`.
  Qualquer papel que enxergue os outros backends serve.

REGRA PARA A CONEXÃO ADMINISTRATIVA
-----------------------------------
  Os passos de guard, contagem de estado e limpeza tocam
  `public.bulk_operation` diretamente e portanto exigem o OWNER
  (`postgres`) — nenhuma role de aplicação tem esse acesso, por
  desenho. Podem ser executados por qualquer canal one-shot.

================================================================
CANAL DE EXECUÇÃO
================================================================

TRÊS PAPÉIS, NEM TODOS PRECISANDO DE SESSÃO PERSISTENTE:

    SESSÃO A   — MUTANTE. PRECISA de sessão persistente: abre
                 transação e a mantém ABERTA entre comandos.
    SESSÃO B   — MUTANTE. PRECISA de sessão persistente: tenta o mesmo
                 claim e deve BLOQUEAR, pendurada.
    OBSERVADOR — SOMENTE LEITURA, ONE-SHOT. NÃO precisa de sessão
                 persistente: cada consulta é autocontida. Prova, de
                 fora, que B está bloqueada por A. Se participasse da
                 disputa, a evidência seria circular.

CANAL PARA A E B: `psql` em conexões persistentes.
    Direct Connection ........ porta 5432
    Session Pooler ........... porta 5432, modo `session`

    PROIBIDO para A/B: Transaction Pooler (porta 6543) — devolve a
    conexão ao pool a cada transação e NÃO garante que A siga segurando
    o claim entre comandos. Usar 6543 em A ou B INVALIDA a prova.

SQL EDITOR DO SUPABASE — distinção obrigatória:

    NÃO SERVE PARA A/B se não preservar sessão/transação entre
    execuções. A e B dependem de transação aberta ATRAVESSANDO
    comandos; um canal que não preserva isso não consegue nem montar
    o cenário.

    SERVE COMO OBSERVADOR, e foi assim que a execução de 2026-09-07
    o usou. O observador emite uma consulta única e autocontida sobre
    `pg_stat_activity`/`pg_blocking_pids`; não abre transação, não
    precisa manter estado, e a evidência é lida no próprio retorno.

    Também serve para as etapas de CONEXÃO ADMINISTRATIVA (guard,
    contagens, limpeza), pelo mesmo motivo: são one-shot.

    Se ainda assim quiser usá-lo para A/B, teste antes numa aba:
        CREATE TEMP TABLE _probe(x int);
        SELECT count(*) FROM _probe;
    Se a segunda falhar, o canal NÃO serve para A/B.

REGISTRO OBRIGATÓRIO DE PID — em CADA conexão, antes de tudo:

    SELECT pg_backend_pid()  AS pid,
           inet_server_port() AS porta,
           current_user       AS papel;

    PID_A   = ______  porta = ____  papel = ________  (5432, com EXECUTE)
    PID_B   = ______  porta = ____  papel = ________  (5432, com EXECUTE)
    PID_OBS = ______  porta = ____  papel = ________  (one-shot)

Os PIDs de A e B precisam ser DISTINTOS. Porta 6543 em A ou B => PARE.
Papel sem EXECUTE nos helpers em A ou B => PARE.

================================================================
PASSO 0 — PREPARO E GUARD DE RESÍDUO PRÉVIO
CONEXÃO ADMINISTRATIVA (owner). One-shot serve.
================================================================
-- Escolha um OWNER real e DUAS chaves de teste. Anote os três valores.
SELECT id AS owner FROM auth.users ORDER BY created_at, id LIMIT 1;
SELECT gen_random_uuid() AS chave1, gen_random_uuid() AS chave2;

-- GUARD: NENHUMA das duas chaves pode já existir para este owner.
-- Resíduo prévio => PARE e investigue; não limpe em silêncio.
SELECT count(*) AS deve_ser_zero
  FROM public.bulk_operation
 WHERE owner_user_id  = '<OWNER>'::uuid
   AND operation_type = 'REGISTER_PHYSICAL_CARDS'
   AND idempotency_key IN ('<CHAVE1>'::uuid, '<CHAVE2>'::uuid);

/*
----------------------------------------------------------------
PASSO 0-bis — ROLE TEMPORÁRIA DE TESTE (opcional, recomendado)
CONEXÃO ADMINISTRATIVA (owner).

Só é necessário se A/B não forem conectar como o próprio owner.
Privilégio MÍNIMO: EXECUTE nos dois helpers, NADA na tabela.
A senha é descartável e a role é REMOVIDA no PASSO 13.
----------------------------------------------------------------
*/
-- CREATE ROLE bulk_k_probe LOGIN PASSWORD '<SENHA_TEMPORARIA_DESCARTAVEL>';
-- GRANT EXECUTE ON FUNCTION
--     public.claim_bulk_operation(TEXT, UUID, TEXT, TEXT)   TO bulk_k_probe;
-- GRANT EXECUTE ON FUNCTION
--     public.complete_bulk_operation(UUID, JSONB)           TO bulk_k_probe;
--
-- CONFERÊNCIA OBRIGATÓRIA — a role NÃO pode ler a tabela:
-- SELECT has_table_privilege('bulk_k_probe','public.bulk_operation','SELECT')
--            AS deve_ser_false,
--        has_function_privilege('bulk_k_probe',
--            'public.claim_bulk_operation(text,uuid,text,text)','EXECUTE')
--            AS deve_ser_true;
-- Se deve_ser_false vier TRUE => PARE: o ledger deixou de ser fechado.

/*
================================================================
K01 + K02 — A COMMITA  (usa CHAVE1)
================================================================
Substituir <OWNER> e <CHAVE1> pelos valores anotados.
*/

-- ---------- PASSO 1 — SESSÃO A (pid = PID_A): claim e NÃO commita ---
BEGIN;
SELECT set_config('request.jwt.claims',
       json_build_object('sub','<OWNER>','role','authenticated')::text, TRUE);
SELECT * FROM public.claim_bulk_operation(
    'REGISTER_PHYSICAL_CARDS', '<CHAVE1>'::uuid, 'hash-A', 'fp-A');
-- ESPERADO: outcome = CLAIMED. PARE AQUI. NÃO commitar.
--
-- >>> ANOTE AGORA a coluna `operation_id` desta linha como
-- >>> <OPERATION_ID_A>. Ela é o ÚNICO caminho legítimo para obter o id:
-- >>> a sessão A não tem — e não deve ter — acesso direto à tabela.
--
--     OPERATION_ID_A = ________________________________________

-- ---------- PASSO 2 — SESSÃO B (pid = PID_B): deve BLOQUEAR ---------
BEGIN;
SELECT set_config('request.jwt.claims',
       json_build_object('sub','<OWNER>','role','authenticated')::text, TRUE);
SELECT * FROM public.claim_bulk_operation(
    'REGISTER_PHYSICAL_CARDS', '<CHAVE1>'::uuid, 'hash-A', 'fp-B');
-- ESPERADO (K01): fica pendurado. Se retornar imediatamente => K01 FAIL.

-- ---------- PASSO 3 — OBSERVADOR (pid = PID_OBS) --------------------
-- SOMENTE LEITURA, ONE-SHOT. Esta linha é a EVIDÊNCIA do relatório.
SELECT <PID_B>                                   AS pid_b,
       <PID_A>                                   AS pid_a,
       pg_blocking_pids(<PID_B>)                 AS b_bloqueado_por,
       <PID_A> = ANY (pg_blocking_pids(<PID_B>)) AS b_bloqueado_por_a,
       (SELECT a.state           FROM pg_stat_activity a WHERE a.pid = <PID_B>) AS estado_b,
       (SELECT a.wait_event_type FROM pg_stat_activity a WHERE a.pid = <PID_B>) AS wait_type_b,
       (SELECT a.wait_event      FROM pg_stat_activity a WHERE a.pid = <PID_B>) AS wait_event_b,
       (SELECT left(a.query, 90) FROM pg_stat_activity a WHERE a.pid = <PID_B>) AS query_b;
-- ESPERADO (K01): b_bloqueado_por_a = TRUE, wait_event_type = 'Lock',
-- wait_event = 'transactionid'.
-- Se b_bloqueado_por_a = FALSE => K01 FAIL. Registrar a linha inteira.

-- ---------- PASSO 4 — SESSÃO A: completa e COMMITA ------------------
-- O claim precisa de result_summary, senão o trigger de 5143 reprova o
-- COMMIT. E o valor precisa ser um JSON OBJECT: 5146 rejeita
-- 'null'::jsonb, array e escalares.
--
-- USAR O <OPERATION_ID_A> ANOTADO NO PASSO 1.
-- PROIBIDO recuperar esse id por SELECT em public.bulk_operation: a
-- sessão A não tem acesso direto ao ledger, e tentar isso foi
-- exatamente o erro da primeira execução de K02 em 2026-09-07.
SELECT public.complete_bulk_operation(
    '<OPERATION_ID_A>'::uuid,
    '{"created":0,"nota":"prova de concorrencia K01/K02"}'::jsonb
);
COMMIT;

-- ---------- PASSO 5 — SESSÃO B: destrava --------------------------
-- ESPERADO (K02): B retorna AGORA, com outcome = REPLAY (hash igual),
-- operation_id IGUAL a <OPERATION_ID_A>, e o result_summary gravado
-- por A.
-- Em seguida, ainda na B:
ROLLBACK;

-- ---------- PASSO 6 — Estado ----------------------------------------
-- CONEXÃO ADMINISTRATIVA (owner). One-shot serve.
SELECT count(*) AS deve_ser_1
  FROM public.bulk_operation
 WHERE owner_user_id  = '<OWNER>'::uuid
   AND operation_type = 'REGISTER_PHYSICAL_CARDS'
   AND idempotency_key = '<CHAVE1>'::uuid;
-- ESPERADO: 1. B NÃO criou linha nova.
--
-- K01 PASS <=> B bloqueou no PASSO 2 e o PASSO 3 mostrou
--              b_bloqueado_por_a = TRUE.
-- K02 PASS <=> B só concluiu após o COMMIT de A, com REPLAY e o mesmo
--              operation_id, e a contagem final é 1.

/*
================================================================
K03 — A ABORTA  (usa CHAVE2)
================================================================
*/

-- ---------- PASSO 7 — SESSÃO A: claim e NÃO commita -----------------
BEGIN;
SELECT set_config('request.jwt.claims',
       json_build_object('sub','<OWNER>','role','authenticated')::text, TRUE);
SELECT * FROM public.claim_bulk_operation(
    'REGISTER_PHYSICAL_CARDS', '<CHAVE2>'::uuid, 'hash-X', 'fp-X');
-- ESPERADO: CLAIMED. PARE. NÃO commitar.
-- (Aqui não é preciso anotar o operation_id: K03 termina em ROLLBACK,
--  não há complete_bulk_operation neste ramo.)

-- ---------- PASSO 8 — SESSÃO B: deve BLOQUEAR -----------------------
BEGIN;
SELECT set_config('request.jwt.claims',
       json_build_object('sub','<OWNER>','role','authenticated')::text, TRUE);
SELECT * FROM public.claim_bulk_operation(
    'REGISTER_PHYSICAL_CARDS', '<CHAVE2>'::uuid, 'hash-X', 'fp-Y');
-- ESPERADO: pendura.
--
-- ==> REEXECUTAR O PASSO 3 NO OBSERVADOR AGORA.
--     Mesmo critério: b_bloqueado_por_a = TRUE. Registrar a linha.

-- ---------- PASSO 9 — SESSÃO A: ROLLBACK ----------------------------
ROLLBACK;

-- ---------- PASSO 10 — SESSÃO B: destrava ---------------------------
-- ESPERADO (K03): B retorna AGORA com outcome = CLAIMED.
-- O claim de A sumiu no rollback, então a chave estava livre.
-- Em seguida, ainda na B:
ROLLBACK;

-- ---------- PASSO 11 — Estado ---------------------------------------
-- CONEXÃO ADMINISTRATIVA (owner). One-shot serve.
SELECT count(*) AS deve_ser_0
  FROM public.bulk_operation
 WHERE owner_user_id  = '<OWNER>'::uuid
   AND operation_type = 'REGISTER_PHYSICAL_CARDS'
   AND idempotency_key = '<CHAVE2>'::uuid;
-- ESPERADO: 0 — ambas as transações foram desfeitas.
--
-- K03 PASS <=> B bloqueou, o observador comprovou o bloqueio por A, e
--              após o ROLLBACK de A a B recebeu CLAIMED.

/*
================================================================
PASSO 12 — LIMPEZA OBRIGATÓRIA DE LINHAS
CONEXÃO ADMINISTRATIVA (owner).
Executar SEMPRE ao final, inclusive se algum caso FALHAR.
Antes: garantir que A e B encerraram (COMMIT/ROLLBACK).

ESCOPO: a CHAVE DE IDENTIDADE COMPLETA — (owner_user_id,
operation_type, idempotency_key). Filtrar só por idempotency_key
apagaria linhas de outro owner que por acaso usassem o mesmo UUID.
================================================================
*/
BEGIN;
DELETE FROM public.bulk_operation
 WHERE owner_user_id  = '<OWNER>'::uuid
   AND operation_type = 'REGISTER_PHYSICAL_CARDS'
   AND idempotency_key IN ('<CHAVE1>'::uuid, '<CHAVE2>'::uuid);
COMMIT;

-- POSTCHECK FIXTURE-SCOPED, MESMO ESCOPO DA LIMPEZA.
-- NÃO exige zero global em bulk_operation — o banco pode legitimamente
-- conter operações reais.
SELECT count(*) AS fx_residuo
  FROM public.bulk_operation
 WHERE owner_user_id  = '<OWNER>'::uuid
   AND operation_type = 'REGISTER_PHYSICAL_CARDS'
   AND idempotency_key IN ('<CHAVE1>'::uuid, '<CHAVE2>'::uuid);
-- ESPERADO: 0. Qualquer valor > 0 é resíduo desta prova.

/*
================================================================
PASSO 13 — REMOÇÃO DA ROLE TEMPORÁRIA
CONEXÃO ADMINISTRATIVA (owner).
Obrigatório se o PASSO 0-bis foi usado. A role de teste NÃO pode
sobreviver à prova: ela detém EXECUTE em helpers internos.
Encerrar as sessões A e B ANTES (a role não pode estar conectada).
================================================================
*/
-- REVOKE EXECUTE ON FUNCTION
--     public.claim_bulk_operation(TEXT, UUID, TEXT, TEXT)   FROM bulk_k_probe;
-- REVOKE EXECUTE ON FUNCTION
--     public.complete_bulk_operation(UUID, JSONB)           FROM bulk_k_probe;
-- DROP ROLE bulk_k_probe;
--
-- POSTCHECK:
-- SELECT count(*) AS role_residuo
--   FROM pg_roles WHERE rolname = 'bulk_k_probe';
-- ESPERADO: 0.

/*
================================================================
RELATÓRIO A DEVOLVER
================================================================
1. PID_A / PID_B / PID_OBS, a porta de cada, o PAPEL de cada (A e B
   com EXECUTE explícito nos helpers) e o canal usado por cada um —
   distinguindo quais foram sessões persistentes (A e B,
   obrigatoriamente) e quais foram one-shot (observador e conexão
   administrativa).
2. O `deve_ser_zero` do PASSO 0.
3. O <OPERATION_ID_A> anotado no PASSO 1.
4. K01: a linha completa do PASSO 3 (b_bloqueado_por_a, wait_type_b,
   wait_event_b, query_b) + veredito PASS/FAIL.
5. K02: o `outcome` e o `operation_id` recebidos por B no PASSO 5
   (o id deve bater com <OPERATION_ID_A>) + `deve_ser_1` do PASSO 6
   + PASS/FAIL.
6. K03: a linha do PASSO 3 reexecutado + o `outcome` de B no PASSO 10
   + `deve_ser_0` do PASSO 11 + PASS/FAIL.
7. Postcheck do PASSO 12: `fx_residuo`.
8. Postcheck do PASSO 13: `role_residuo`, se a role temporária foi
   usada.
================================================================
*/
