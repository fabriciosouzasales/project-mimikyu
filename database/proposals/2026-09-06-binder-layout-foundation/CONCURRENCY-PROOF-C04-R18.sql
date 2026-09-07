/*
================================================================
Projeto.....: Project Mimikyu
Artefato....: PROVA DE CONCORRÊNCIA EXTERNA — C04 e R18
Versão......: 2.0
Status......: ROTEIRO MANUAL — NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-07 (v1.0 em ...-IMPLEMENTATION-01-FIX-02 item 4;
               v2.0 em ...-CONCURRENCY-PROOF-REVISION-01)

NÃO É MIGRATION. NÃO É NUMERADO NA FAIXA 5xxx. NÃO USAR `5142`.
Não promover para database/schema/. Não aplicar via apply_migration.
Não altera nenhuma migration nem nenhuma regra de negócio.

MUDANÇAS v1.0 -> v2.0 (REVISION-01)
-----------------------------------
§1 FIXTURE. Deixa de criar `inventory`. Passa a EXIGIR um Owner que
   JÁ possua Inventory; se nenhum existir, ABORTA. Passa a exigir
   AUSÊNCIA de resíduo prévio (`__C04R18__coll` / `__C04R18__sc`):
   resíduo prévio é STOP, não é limpo automaticamente.
§2 CANAL. Deixa de sugerir o SQL Editor do Supabase como sessão
   persistente — isso nunca foi provado e não deve ser assumido. A
   execução preferencial passa a ser `psql` em conexões persistentes,
   por Direct Connection ou Session Pooler. Transaction Pooler é
   PROIBIDO. Passa a exigir registro do PID das TRÊS conexões.
§4 CLEANUP. O postcheck passa a ser FIXTURE-SCOPED: conta apenas os
   objetos desta prova, nunca o total global das tabelas Binder
   (exigir zero global seria falso — o banco pode ter Layouts reais).
   Limpeza obrigatória mesmo quando a prova FALHA.

A SEMÂNTICA DAS PROVAS C04 E R18 E OS CRITÉRIOS PASS/FAIL ESTÃO
PRESERVADOS EXATAMENTE COMO NA v1.0.


POR QUE ESTE ARQUIVO EXISTE
---------------------------
`C04` e `R18` são os DOIS únicos casos do `5818` que permanecem
NOT PROVEN, por honestidade: exigem DUAS SESSÕES PERSISTENTES E
SIMULTÂNEAS, com a transação da sessão A ABERTA enquanto a sessão B
tenta a operação concorrente.

O canal MCP `execute_sql` NÃO oferece isso — foi medido, não presumido:
uma TEMP TABLE criada numa chamada já não existe na chamada seguinte,
ou seja, cada chamada é uma sessão/transação independente. A prova
NÃO é executável pelo agente.


================================================================
§2 — CANAL DE EXECUÇÃO (LEIA ANTES DE COMEÇAR)
================================================================

SÃO NECESSÁRIAS TRÊS CONEXÕES SIMULTÂNEAS:

    SESSÃO A   — MUTANTE. Abre transação e a mantém ABERTA.
    SESSÃO B   — MUTANTE. Tenta a operação concorrente e deve BLOQUEAR.
    OBSERVADOR — SOMENTE LEITURA. Nunca abre transação de escrita;
                 existe para provar, de fora, que B está bloqueada
                 por A. Se o observador participasse da disputa, a
                 evidência seria circular.

CANAL PREFERENCIAL: `psql` em conexões persistentes.

    Direct Connection ......... porta 5432, host db.<ref>.supabase.co
    Session Pooler ............ porta 5432, modo `session`

    PROIBIDO: Transaction Pooler (porta 6543). Ele devolve a conexão
    ao pool a cada transação e NÃO garante que a sessão A continue
    segurando o lock entre comandos — exatamente a propriedade que
    esta prova precisa. Usar Transaction Pooler INVALIDA a prova.

SOBRE O SQL EDITOR DO SUPABASE: NÃO é recomendado aqui. Não há prova
de que ele mantenha sessão/transação persistente entre execuções, e
esta rodada não vai assumir o que não mediu. Se você quiser usá-lo,
prove antes: numa aba rode `CREATE TEMP TABLE _probe(x int);` e, em
seguida, `SELECT count(*) FROM _probe;`. Se a segunda falhar com
`relation "_probe" does not exist`, o canal NÃO serve — foi
exatamente assim que o canal do agente foi reprovado.

REGISTRO OBRIGATÓRIO DE PID. Em CADA uma das três conexões, antes de
tudo, execute e ANOTE:

    SELECT pg_backend_pid() AS pid, inet_server_port() AS porta;

    PID_A  = __________   porta = ______   (deve ser 5432)
    PID_B  = __________   porta = ______   (deve ser 5432)
    PID_OBS= __________   porta = ______   (deve ser 5432)

Os três PIDs precisam ser DISTINTOS. Porta 6543 em qualquer um deles
=> PARE e reconecte pelo canal correto.


================================================================
PASSO 0 — FIXTURE (SESSÃO A, privilegiada). §1 REVISION-01.
Executar isolado, ANTES de qualquer transação de prova.
================================================================
--
-- Este bloco:
--   (a) EXIGE ausência de resíduo prévio da prova — se houver, ABORTA
--       sem limpar nada (resíduo prévio significa que uma execução
--       anterior não chegou ao PASSO 9; isso é um fato a investigar,
--       não algo a apagar em silêncio);
--   (b) NÃO cria `inventory`. Seleciona um Owner que JÁ possua
--       Inventory. Se nenhum existir, ABORTA — a prova não fabrica
--       pré-requisito de outro agregado;
--   (c) cria APENAS: 1 storage_container, 1 collection, 1 layout,
--       1 page e os 16 slots, todos com o prefixo `__C04R18__`.
--
-- A fixture é COMMITADA de propósito: duas sessões só enxergam a
-- mesma linha se ela estiver commitada. Enquanto o PASSO 9 não rodar,
-- existem linhas reais no banco. Isso é inerente à prova.

DO $blk$
DECLARE
    v_n INTEGER;
    v_owner UUID; v_inv UUID; v_game UUID;
    v_sc UUID; v_coll UUID; v_layout UUID; v_page UUID;
BEGIN
    -- (a) GUARD DE RESÍDUO PRÉVIO — fail-closed.
    SELECT count(*) INTO v_n FROM public.collection WHERE name = '__C04R18__coll';
    IF v_n > 0 THEN
        RAISE EXCEPTION
            'STOP — residuo previo: existe(m) % collection(s) __C04R18__coll. Uma execucao anterior nao chegou ao PASSO 9. Investigar e limpar MANUALMENTE antes de repetir.', v_n;
    END IF;

    SELECT count(*) INTO v_n FROM public.storage_container WHERE name = '__C04R18__sc';
    IF v_n > 0 THEN
        RAISE EXCEPTION
            'STOP — residuo previo: existe(m) % storage_container(s) __C04R18__sc. Investigar e limpar MANUALMENTE antes de repetir.', v_n;
    END IF;

    -- (b) OWNER COM INVENTORY JA EXISTENTE. Nada de INSERT em inventory.
    SELECT i.owner_user_id, i.id
      INTO v_owner, v_inv
      FROM public.inventory i
      JOIN auth.users u ON u.id = i.owner_user_id
     ORDER BY u.created_at, u.id
     LIMIT 1;

    IF v_owner IS NULL THEN
        RAISE EXCEPTION
            'ABORT — nenhum Owner com Inventory existente. Esta prova NAO cria Inventory. Provisione o Inventory pelo caminho normal do produto e repita.';
    END IF;

    SELECT ex.game_id INTO v_game
      FROM public.card_variant cv
      JOIN public.card ca      ON ca.id = cv.card_id
      JOIN public.card_set cs  ON cs.id = ca.card_set_id
      JOIN public.expansion ex ON ex.id = cs.expansion_id
     ORDER BY cv.id LIMIT 1;

    IF v_game IS NULL THEN
        RAISE EXCEPTION 'ABORT — catalogo minimo ausente (nenhum Game alcancavel por card_variant).';
    END IF;

    -- (c) FIXTURE MINIMA.
    INSERT INTO public.storage_container (inventory_id, name)
    VALUES (v_inv, '__C04R18__sc') RETURNING id INTO v_sc;

    INSERT INTO public.collection
        (owner_user_id, game_id, default_storage_container_id, name, mode, completion_policy)
    VALUES (v_owner, v_game, v_sc, '__C04R18__coll', 'OPEN_CURATION', 'NONE')
    RETURNING id INTO v_coll;

    INSERT INTO public.collection_layout (collection_id, grid_rows, grid_columns)
    VALUES (v_coll, 4, 4) RETURNING id INTO v_layout;

    INSERT INTO public.collection_layout_page (layout_id, page_number)
    VALUES (v_layout, 1) RETURNING id INTO v_page;

    INSERT INTO public.collection_layout_slot (page_id, row_index, column_index)
    SELECT v_page, r, c FROM generate_series(1,4) r CROSS JOIN generate_series(1,4) c;

    RAISE NOTICE 'OWNER  = %', v_owner;
    RAISE NOTICE 'INV    = % (PRE-EXISTENTE, nao criado por esta prova)', v_inv;
    RAISE NOTICE 'COLL   = %', v_coll;
    RAISE NOTICE 'LAYOUT = %', v_layout;
    RAISE NOTICE 'PAGE   = %', v_page;
END $blk$;

-- Recuperar os ids a qualquer momento (inclusive <SLOT> para C04):
SELECT c.owner_user_id                       AS owner,
       c.id                                  AS coll,
       l.id                                  AS layout,
       p.id                                  AS page,
       (SELECT s.id FROM public.collection_layout_slot s
         WHERE s.page_id = p.id AND s.row_index = 1 AND s.column_index = 1) AS slot_1_1
  FROM public.collection c
  JOIN public.collection_layout l      ON l.collection_id = c.id
  JOIN public.collection_layout_page p ON p.layout_id = l.id
 WHERE c.name = '__C04R18__coll';


/*
================================================================
C04 — SERIALIZAÇÃO REAL COLLECTION -> LAYOUT (helper 5122)
Semântica e critérios PRESERVADOS da v1.0.
================================================================
Substituir <OWNER>, <SLOT> pelos valores devolvidos acima.
*/

-- ---------- PASSO 1 — SESSÃO A (pid = PID_A): abre e NÃO commita ---
BEGIN;
SELECT set_config('request.jwt.claims',
       json_build_object('sub','<OWNER>','role','authenticated')::text, TRUE);
SET LOCAL ROLE authenticated;
SELECT public.set_slot_lock(ARRAY['<SLOT>']::uuid[], TRUE);
-- PARE AQUI. NÃO commitar. A transação A detém o lock
-- COLLECTION -> LAYOUT adquirido dentro de assert_collection_layout_mutable().

-- ---------- PASSO 2 — SESSÃO B (pid = PID_B): deve BLOQUEAR --------
-- Na SEGUNDA conexão. O comando NÃO deve retornar.
BEGIN;
SELECT set_config('request.jwt.claims',
       json_build_object('sub','<OWNER>','role','authenticated')::text, TRUE);
SET LOCAL ROLE authenticated;
SELECT public.set_slot_lock(ARRAY['<SLOT>']::uuid[], FALSE);
-- ESPERADO: fica pendurado. Se retornar imediatamente => C04 FAIL.

-- ---------- PASSO 3 — OBSERVADOR (pid = PID_OBS) -------------------
-- TERCEIRA conexão, SOMENTE LEITURA. Esta é a EVIDÊNCIA do relatório.
-- Substituir <PID_A> e <PID_B> pelos PIDs anotados.
SELECT <PID_B>                                   AS pid_b,
       <PID_A>                                   AS pid_a,
       pg_blocking_pids(<PID_B>)                 AS b_bloqueado_por,
       <PID_A> = ANY (pg_blocking_pids(<PID_B>)) AS b_bloqueado_por_a,
       (SELECT a.state           FROM pg_stat_activity a WHERE a.pid = <PID_B>) AS estado_b,
       (SELECT a.wait_event_type FROM pg_stat_activity a WHERE a.pid = <PID_B>) AS wait_type_b,
       (SELECT a.wait_event      FROM pg_stat_activity a WHERE a.pid = <PID_B>) AS wait_event_b,
       (SELECT left(a.query, 90) FROM pg_stat_activity a WHERE a.pid = <PID_B>) AS query_b;
-- ESPERADO (C04): b_bloqueado_por_a = TRUE, wait_type_b = 'Lock'.
-- Se b_bloqueado_por_a = FALSE => C04 FAIL. Registrar a linha inteira.

-- ---------- PASSO 4 — SESSÃO A: COMMIT -----------------------------
COMMIT;

-- ---------- PASSO 5 — SESSÃO B: destrava e conclui -----------------
-- A B deve retornar AGORA, e não antes.
COMMIT;

-- ---------- PASSO 6 — Estado final (qualquer conexão) --------------
SELECT id, locked FROM public.collection_layout_slot WHERE id = '<SLOT>';
-- ESPERADO: locked = false (B aplicou FALSE depois de A ter aplicado TRUE).
--
-- C04 PASS <=> B bloqueou no PASSO 2, o PASSO 3 mostrou
--              b_bloqueado_por_a = TRUE, e B só concluiu após o
--              COMMIT do PASSO 4.


/*
================================================================
R18 — OVERLAP CONCORRENTE DE REGION (trigger 5121 + lock da Page)
Semântica e critérios PRESERVADOS da v1.0.
================================================================
Substituir <OWNER> e <PAGE>. Garantir que a Page está sem Region:
    DELETE FROM public.collection_layout_region WHERE page_id = '<PAGE>';
*/

-- ---------- PASSO 7 — SESSÃO A: merge (3,1,1,2), NÃO commita -------
BEGIN;
SELECT set_config('request.jwt.claims',
       json_build_object('sub','<OWNER>','role','authenticated')::text, TRUE);
SET LOCAL ROLE authenticated;
SELECT * FROM public.merge_layout_region('<PAGE>'::uuid, 3, 1, 1, 2);
-- PARE AQUI. NÃO commitar.

-- ---------- PASSO 8 — SESSÃO B: merge SOBREPOSTO (3,2,1,2) ---------
-- Deve BLOQUEAR na Page FOR UPDATE tomada pelo trigger 5121.
BEGIN;
SELECT set_config('request.jwt.claims',
       json_build_object('sub','<OWNER>','role','authenticated')::text, TRUE);
SET LOCAL ROLE authenticated;
SELECT * FROM public.merge_layout_region('<PAGE>'::uuid, 3, 2, 1, 2);
-- ESPERADO: pendura.
--
-- ==> REEXECUTAR O PASSO 3 NO OBSERVADOR AGORA. Mesmo critério:
--     b_bloqueado_por_a = TRUE. Registrar a linha.
--
-- Em seguida, na SESSÃO A:  COMMIT;
-- A SESSÃO B deve então FALHAR com:
--     'Layout Region sobrepoe outra Region da mesma Page'
-- Na SESSÃO B, depois do erro:  ROLLBACK;
--
-- R18 PASS <=> B bloqueou, o observador comprovou o bloqueio por A, e
--              após o COMMIT de A a B recebeu o erro de sobreposição.
-- R18 FAIL <=> B não bloqueou, OU as duas Regions sobrepostas coexistem.

-- Contagem final da prova (qualquer conexão):
SELECT count(*) AS regions_na_page
  FROM public.collection_layout_region WHERE page_id = '<PAGE>';
-- ESPERADO: 1 (somente a Region da sessão A).


/*
================================================================
PASSO 9 — LIMPEZA OBRIGATÓRIA (§4 REVISION-01)
Executar SEMPRE ao final — inclusive se C04 ou R18 FALHAREM.
Antes de rodar: garantir que A e B encerraram (COMMIT/ROLLBACK).
Escopo: EXCLUSIVAMENTE os objetos desta fixture.
================================================================
*/
BEGIN;

DELETE FROM public.collection_layout_region r
 USING public.collection_layout_page p, public.collection_layout l, public.collection c
 WHERE r.page_id = p.id AND p.layout_id = l.id AND l.collection_id = c.id
   AND c.name = '__C04R18__coll';

DELETE FROM public.collection_layout_slot s
 USING public.collection_layout_page p, public.collection_layout l, public.collection c
 WHERE s.page_id = p.id AND p.layout_id = l.id AND l.collection_id = c.id
   AND c.name = '__C04R18__coll';

DELETE FROM public.collection_layout_page p
 USING public.collection_layout l, public.collection c
 WHERE p.layout_id = l.id AND l.collection_id = c.id
   AND c.name = '__C04R18__coll';

DELETE FROM public.collection_layout l
 USING public.collection c
 WHERE l.collection_id = c.id AND c.name = '__C04R18__coll';

DELETE FROM public.collection        WHERE name = '__C04R18__coll';
DELETE FROM public.storage_container WHERE name = '__C04R18__sc';

COMMIT;

-- POSTCHECK FIXTURE-SCOPED. NÃO exige zero global nas tabelas Binder —
-- o banco pode legitimamente conter Layouts reais de outras Collections.
-- O que se prova aqui é que NADA desta prova sobrou.
SELECT
  (SELECT count(*) FROM public.collection
    WHERE name = '__C04R18__coll')                                      AS fx_collection,
  (SELECT count(*) FROM public.storage_container
    WHERE name = '__C04R18__sc')                                        AS fx_storage,
  (SELECT count(*) FROM public.collection_layout l
     JOIN public.collection c ON c.id = l.collection_id
    WHERE c.name = '__C04R18__coll')                                    AS fx_layouts,
  (SELECT count(*) FROM public.collection_layout_page p
     JOIN public.collection_layout l ON l.id = p.layout_id
     JOIN public.collection c        ON c.id = l.collection_id
    WHERE c.name = '__C04R18__coll')                                    AS fx_pages,
  (SELECT count(*) FROM public.collection_layout_slot s
     JOIN public.collection_layout_page p ON p.id = s.page_id
     JOIN public.collection_layout l      ON l.id = p.layout_id
     JOIN public.collection c             ON c.id = l.collection_id
    WHERE c.name = '__C04R18__coll')                                    AS fx_slots,
  (SELECT count(*) FROM public.collection_layout_region r
     JOIN public.collection_layout_page p ON p.id = r.page_id
     JOIN public.collection_layout l      ON l.id = p.layout_id
     JOIN public.collection c             ON c.id = l.collection_id
    WHERE c.name = '__C04R18__coll')                                    AS fx_regions;
-- ESPERADO: as SEIS colunas = 0. Qualquer valor > 0 é resíduo da
-- prova e precisa ser resolvido antes de encerrar a rodada.


/*
================================================================
RELATÓRIO A DEVOLVER
================================================================
1. PID_A / PID_B / PID_OBS + porta de cada conexão (todas 5432) e o
   canal usado (Direct Connection ou Session Pooler).
2. C04: a linha completa do PASSO 3 (b_bloqueado_por_a, wait_type_b,
   query_b) + o resultado do PASSO 6 + veredito PASS/FAIL.
3. R18: a linha do PASSO 3 reexecutado + a mensagem de erro recebida
   pela sessão B após o COMMIT de A + `regions_na_page` + PASS/FAIL.
4. Postcheck fixture-scoped do PASSO 9: as seis colunas.
================================================================
*/
