-- ============================================================================
-- Query 2224 — GUARD SAME-GAME DO CONTEXTO DE EDIÇÃO (3º eixo)
-- Status: PROPOSTA — NÃO EXECUTADA · Versão 1.0
-- Mandato: BATCH9-2217-READINESS-CORRECTION-01 (fecha o BLOCKER B4 da
--          BATCH9-2217-READINESS-AUDIT-01)
--
-- ----------------------------------------------------------------------------
-- POR QUE ESTA QUERY EXISTE — A LACUNA QUE A AUDITORIA ENCONTROU
-- ----------------------------------------------------------------------------
--   A `2217` (EXPAND do writer) declarava, no seu cabecalho v3.0:
--
--     "SAME-GAME: NAO validado aqui, de proposito. A autoridade e
--      public.validate_card_variant_game_consistency, que a Query 2220
--      estende para o terceiro eixo."
--
--   A auditoria mecanica provou que essa afirmacao era FALSA em dois pontos:
--
--   (a) `public.validate_card_variant_game_consistency` (161:60-104) compara
--       o Game da Card com o Game do **Variant Type**, e so isso. O corpo
--       NUNCA menciona `edition_context_profile_id`, e o trigger que a
--       dispara — `trg_card_variant_validate_game_consistency` (161:101-105)
--       — e `BEFORE INSERT OR UPDATE OF card_id, variant_type_id`, portanto
--       **nem sequer acorda** quando so o contexto de edicao muda.
--
--   (b) A `2220` NAO a estende. O escopo declarado no proprio cabecalho da
--       2220 e `internal.variant_type_mapping_impact` +
--       `internal.variant_type_mapping_decision` — o *read contract* do
--       mapping de Variant Type. Nao ha `CREATE TRIGGER`, `DROP TRIGGER` nem
--       qualquer mencao a `validate_card_variant_game_consistency` no arquivo.
--
--   Resultado: ANTES desta Query, o unico guard sobre
--   `card_variant.edition_context_profile_id` era a FK simples da `2208`, que
--   garante que o profile EXISTE — nao a qual Game pertence. Como
--   `card_edition_context_profile.game_id` e NOT NULL (2204:68), um profile
--   de OUTRO Game era perfeitamente inserivel.
--
--   Os outros dois eixos ja tinham guard dedicado. Este nao tinha:
--
--     Variant Type ....... public.validate_card_variant_game_consistency   161
--     Printing Profile ... internal.enforce_card_variant_printing_profile_game
--                          + trg_card_variant_printing_profile_game        2170
--     Edition Context .... (NADA)                                   ← esta Query
--
-- ----------------------------------------------------------------------------
-- DESENHO — ESPELHO LITERAL DA 2170, POR DECISAO DE ARQUITETURA
-- ----------------------------------------------------------------------------
--   Guard DEDICADO por eixo, nao extensao da funcao de Variant Type. Tres
--   razoes:
--
--   1. PRECEDENTE. A 2170 ja resolveu exatamente este problema para Printing.
--      Espelha-la da ao terceiro eixo o mesmo contrato, os mesmos nomes de
--      erro por analogia, e o mesmo custo — zero no caminho NULL.
--
--   2. SEGURANCA. `validate_card_variant_game_consistency` (161) e
--      SECURITY INVOKER **sem `SET search_path`**. Estende-la herdaria um
--      padrao inferior ao vigente. Esta funcao nasce SECURITY DEFINER com
--      `search_path = ''`, como a 2170 e como toda funcao nova do projeto
--      desde `2132_harden_search_path_catalogo_functions`.
--
--   3. AUTORIDADE UNICA POR EIXO. Cada eixo tem um e apenas um guard. Nao ha
--      funcao multi-eixo cujo `UPDATE OF` precise crescer a cada eixo novo —
--      e era justamente um `UPDATE OF` que nao cobria a coluna que deixava a
--      invariante silenciosamente desprotegida em (a).
--
--   O writer (`2217`) continua NAO validando same-Game. Esta Query e a
--   autoridade, e duplicar a regra la criaria a segunda fonte de verdade que
--   o proprio cabecalho da 2217 diz querer evitar — agora com uma autoridade
--   que de fato existe.
--
-- ----------------------------------------------------------------------------
-- ORDEM NO ROLLOUT
-- ----------------------------------------------------------------------------
--   2224 (GUARD) → 2217 (EXPAND) → 2218 (SWITCH) → 2223 (CONTRACT)
--
--   O NUMERO NAO E A ORDEM. `2224 > 2223` e consequencia de a numeracao
--   estar ocupada ate 2223 quando esta Query foi escrita; o `DAG.md` e a
--   autoridade de sequencia. Esta Query roda ANTES da 2217 de proposito: o
--   guard tem de existir antes de haver assinatura capaz de gravar a coluna.
--
--   Pre-requisito duro: `2208` (a coluna) e `2204` (a tabela de profiles).
--   Ambos verificados no PASSO 1.
--
-- ----------------------------------------------------------------------------
-- PRE-INSTALACAO — SEM CARDINALIDADE ASSUMIDA
-- ----------------------------------------------------------------------------
--   O PASSO 2 prova que NENHUMA `card_variant` existente com
--   `edition_context_profile_id IS NOT NULL` viola a invariante, ANTES de
--   instalar o guard. Nao ha numero esperado hardcoded: o gate conta
--   violacoes e exige ZERO. Se o universo atual for vazio, passa
--   trivialmente; se tiver 1 ou 10.000 linhas, todas sao verificadas.
--
--   Instalar um guard sobre dados que ja o violam produziria uma tabela onde
--   linhas legitimas existentes se tornam intocaveis — o mesmo modo de falha
--   que a `2214` evitou no staging.
--
-- ----------------------------------------------------------------------------
-- MEDIR E PROTEGER SEM JANELA (BATCH9-2224-READINESS-CORRECTION-02)
-- ----------------------------------------------------------------------------
--   Medir o estado e depois instalar o guard sao dois momentos; entre eles
--   cabe uma escrita concorrente. Em READ COMMITTED isso produziria "trigger
--   correto instalado + dado invalido ja persistido" — e o guard tornaria
--   essa linha intocavel.
--
--   Tres mecanismos fecham a janela, nesta ordem:
--     PASSO 1-BIS  `LOCK TABLE public.card_variant IN SHARE ROW EXCLUSIVE
--                  MODE`, ANTES de qualquer leitura. Barra INSERT/UPDATE/
--                  DELETE concorrentes ate o COMMIT; SELECTs seguem livres.
--     PASSO 2      mede um estado que ja nao pode mudar.
--     PASSO 5 · G9 remede a invariante DEPOIS do DDL. Se divergir do PASSO 2,
--                  o lock nao segurou — e a migration aborta inteira.
--
--   O MODO NUNCA SOBE. O PASSO 4 usa `CREATE OR REPLACE TRIGGER`
--   (PostgreSQL >= 14), que adquire SHARE ROW EXCLUSIVE — o mesmo modo ja
--   retido. O par `DROP TRIGGER` + `CREATE TRIGGER`, usado ate a
--   CORRECTION-02, elevava implicitamente para ACCESS EXCLUSIVE e teria
--   bloqueado tambem os leitores. `ACCESS SHARE` permanece permitido do
--   `BEGIN;` ao `COMMIT;`, e o lock so cai no COMMIT/ROLLBACK.
--
--   O FREEZE do rollout continua valendo, mas deixou de ser a unica garantia:
--   FREEZE e governanca, o LOCK e enforcement.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------- PASSO 1 ---
-- GATE DE PRE-REQUISITOS. Falha alto, antes de qualquer DDL.
DO $$
BEGIN
    -- (0) VERSAO DO SERVIDOR. `CREATE OR REPLACE TRIGGER` (PASSO 4) existe
    --     desde o PostgreSQL 14. O repositorio prova 17.6 no LIVE
    --     (2209:32; README.md:174 — `PostgreSQL 17.6 on aarch64-unknown-
    --     linux-gnu`), mas evidencia DOCUMENTAL nao e evidencia de RUNTIME:
    --     o mesmo arquivo pode ser rodado noutro servidor. Precedente da
    --     mesma classe nesta proposta: 2840, PASSO 1.
    IF current_setting('server_version_num')::INT < 140000 THEN
        RAISE EXCEPTION 'GUARD_EC_GAME_SERVER_TOO_OLD: server_version_num=% (< 140000). CREATE OR REPLACE TRIGGER indisponivel; esta migration depende dele para nao escalar o lock para ACCESS EXCLUSIVE.', current_setting('server_version_num')::INT;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_schema = 'public' AND table_name = 'card_variant'
           AND column_name = 'edition_context_profile_id'
    ) THEN
        RAISE EXCEPTION 'GUARD_EC_GAME_BLOCKED: public.card_variant.edition_context_profile_id nao existe. Rode a Query 2208 antes.';
    END IF;

    IF to_regclass('public.card_edition_context_profile') IS NULL THEN
        RAISE EXCEPTION 'GUARD_EC_GAME_BLOCKED: public.card_edition_context_profile nao existe. Rode a Query 2204 antes.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_schema = 'public' AND table_name = 'card_edition_context_profile'
           AND column_name = 'game_id'
    ) THEN
        RAISE EXCEPTION 'GUARD_EC_GAME_BLOCKED: card_edition_context_profile.game_id nao existe — a invariante nao e expressavel.';
    END IF;
END $$;

-- ------------------------------------------------------------ PASSO 1-BIS ---
-- LOCK EXPLICITO — FECHA A JANELA TOCTOU ENTRE MEDIR E PROTEGER.
--
-- O PROBLEMA QUE ISTO RESOLVE. Sem lock, em READ COMMITTED, esta sequencia e
-- possivel e produz "trigger correto instalado + dado invalido persistido":
--
--   T1 (2224)  PASSO 2 -> 0 mismatches
--   T2         INSERT/UPDATE cross-Game em card_variant -> COMMIT
--              (atravessa a janela: o trigger novo ainda nao existe)
--   T1 (2224)  CREATE TRIGGER -> postcheck estrutural -> COMMIT
--
--   Resultado: o guard passa a valer para o FUTURO, mas a linha invalida de
--   T2 ja esta gravada — e o guard a torna intocavel, que e exatamente o
--   estado que o PASSO 2 existe para impedir.
--
--   O FREEZE do rollout tornaria isso improvavel. Mas FREEZE e GOVERNANCA:
--   um controle humano, sem enforcement no banco. Uma invariante de
--   integridade nao pode ter a disciplina de um operador como unica garantia.
--
-- POR QUE `SHARE ROW EXCLUSIVE` E NAO OUTRO MODO.
--
--   Conflitos de SHARE ROW EXCLUSIVE (pg_catalog, matriz de conflitos):
--     ROW EXCLUSIVE ......... CONFLITA  <- e o modo que INSERT/UPDATE/DELETE
--                                          adquirem. E este conflito que
--                                          fecha a janela.
--     SHARE / SHARE ROW EXCL. CONFLITA  <- serializa contra outro 2224
--     EXCLUSIVE / ACCESS EXCL. CONFLITA
--     ACCESS SHARE .......... NAO conflita <- SELECT puro segue livre
--     ROW SHARE ............. NAO conflita <- SELECT FOR SHARE/UPDATE segue
--
--   Ou seja: barra exatamente os writers, e so eles. Leitores nao sao
--   afetados — importante porque `card_variant` tem 24.893 linhas e e lida
--   por read models de Collections.
--
--   NAO usamos ACCESS EXCLUSIVE — E ISTO E UMA AFIRMACAO SEMANTICA, NAO
--   UM RESULTADO DE BUSCA TEXTUAL. Vale porque TODO comando desta
--   transacao que toca `card_variant` adquire, no maximo, SHARE ROW
--   EXCLUSIVE:
--     PASSO 2  SELECT ................................. ACCESS SHARE
--     PASSO 3  CREATE OR REPLACE FUNCTION ............. nao toca a tabela
--     PASSO 4  CREATE OR REPLACE TRIGGER .............. SHARE ROW EXCLUSIVE
--     PASSO 5  SELECT sobre catalogos + a tabela ...... ACCESS SHARE
--   Todos ja cobertos pelo lock adquirido aqui. Nao ha um unico comando
--   capaz de elevar o modo. `DROP TRIGGER` elevaria — por isso o PASSO 4
--   NAO o usa (ver justificativa la).
--
--   NAO usamos advisory lock: advisory e cooperativo — protege apenas quem
--   concorda em consulta-lo. Um INSERT comum nao consulta nada. So um lock
--   de TABELA e compulsorio para qualquer writer.
--
--   NENHUMA outra tabela e travada. `card`, `card_set`, `expansion` e
--   `card_edition_context_profile` sao apenas LIDAS nos gates. O que
--   sustenta isso nao e impossibilidade fisica, e CONTRATO:
--     - pelos WRITE PATHS CANONICOS, `expansion.game_id`,
--       `card_set.expansion_id` e `card.card_set_id` sao atributos de
--       IDENTIDADE e imutaveis apos a criacao — nao ha caminho canonico que
--       remapeie uma Card para outro Game;
--     - escrita SQL privilegiada direta, fora desses contratos, NAO e
--       protegida por este lock e esta FORA DO CONTRATO OPERACIONAL desta
--       migration. Um UPDATE manual de `expansion.game_id` durante a janela
--       criaria mismatch sem tocar `card_variant`, e nem este lock nem o
--       guard impediriam a linha ja existente — seria capturado depois, por
--       auditoria, nao aqui.
--   Travar as quatro tabelas nao esta no escopo desta rodada.
--
-- UPGRADE TARDIO NAO E O MECANISMO. O lock e adquirido AQUI, antes de
--   qualquer leitura do PASSO 2, e nao mais tarde. Depender do lock implicito
--   do `CREATE TRIGGER` (PASSO 4) seria upgrade tardio: entre a medicao e o
--   upgrade existe justamente a janela que queremos fechar.
--
-- LIBERACAO: automatica no COMMIT ou no ROLLBACK. Nao ha (nem pode haver)
--   UNLOCK explicito em PostgreSQL — locks de transacao vivem ate o fim dela.
--   Se qualquer gate abortar, o ROLLBACK libera a tabela e nenhuma alteracao
--   estrutural persiste.
LOCK TABLE public.card_variant IN SHARE ROW EXCLUSIVE MODE;

-- ---------------------------------------------------------------- PASSO 2 ---
-- PRE-INSTALACAO: o estado ATUAL ja satisfaz a invariante?
-- Executa com o LOCK do PASSO 1-BIS ja retido: mede um estado ESTAVEL, que
-- nenhum writer concorrente pode alterar ate o COMMIT desta transacao.
-- Zero cardinalidade assumida. Zero numero hardcoded. So o universo com a
-- coluna preenchida e verificado — as linhas com NULL sao, por definicao
-- semantica ("sem contexto de edicao"), fora do alcance da regra.
DO $$
DECLARE
    v_alcance    BIGINT;
    v_violacoes  BIGINT;
    v_orfas      BIGINT;
    v_sem_game   BIGINT;
    v_amostra    TEXT;
BEGIN
    SELECT count(*) INTO v_alcance
      FROM public.card_variant cv
     WHERE cv.edition_context_profile_id IS NOT NULL;

    -- (a) Profile referenciado que nao existe. A FK da 2208 deveria tornar
    --     isto impossivel; medimos assim mesmo — um gate que confia noutro
    --     gate nao e um gate.
    SELECT count(*) INTO v_orfas
      FROM public.card_variant cv
      LEFT JOIN public.card_edition_context_profile p
             ON p.id = cv.edition_context_profile_id
     WHERE cv.edition_context_profile_id IS NOT NULL
       AND p.id IS NULL;

    IF v_orfas > 0 THEN
        RAISE EXCEPTION 'GUARD_EC_GAME_PREINSTALL_ORPHAN: % card_variant referenciam edition_context_profile inexistente. A FK fk_card_variant_edition_context (Query 2208) deveria impedir isso — investigar ANTES de instalar o guard.', v_orfas;
    END IF;

    -- (b) Card cujo Game nao e resolvivel por card -> card_set -> expansion.
    SELECT count(*) INTO v_sem_game
      FROM public.card_variant cv
      LEFT JOIN public.card      c  ON c.id  = cv.card_id
      LEFT JOIN public.card_set  cs ON cs.id = c.card_set_id
      LEFT JOIN public.expansion e  ON e.id  = cs.expansion_id
     WHERE cv.edition_context_profile_id IS NOT NULL
       AND e.game_id IS NULL;

    IF v_sem_game > 0 THEN
        RAISE EXCEPTION 'GUARD_EC_GAME_PREINSTALL_UNRESOLVED: % card_variant com contexto de edicao nao permitem resolver o Game da Card (cadeia card -> card_set -> expansion quebrada). O guard as tornaria intocaveis. Investigar ANTES de instalar.', v_sem_game;
    END IF;

    -- (c) A violacao propriamente dita: Games diferentes.
    --
    -- CONTAGEM e AMOSTRA sao DUAS queries, de proposito. Versao anterior
    -- aplicava `count(*)` sobre uma subquery que ja tinha `LIMIT 10`: com
    -- 5.000 violacoes o total reportado seria 10 — um numero FALSO dentro de
    -- uma mensagem normativa, que o operador usaria para dimensionar a
    -- correcao. O gate abortava corretamente, mas mentia sobre a escala.
    --
    -- (c.1) CONTAGEM TOTAL — universo completo, SEM LIMIT.
    SELECT count(*) INTO v_violacoes
      FROM public.card_variant cv
      JOIN public.card      c  ON c.id  = cv.card_id
      JOIN public.card_set  cs ON cs.id = c.card_set_id
      JOIN public.expansion e  ON e.id  = cs.expansion_id
      JOIN public.card_edition_context_profile p
                                ON p.id = cv.edition_context_profile_id
     WHERE cv.edition_context_profile_id IS NOT NULL
       AND e.game_id <> p.game_id;

    IF v_violacoes > 0 THEN
        -- (c.2) AMOSTRA — so quando ha o que amostrar. `ORDER BY cv.id` ANTES
        -- do LIMIT torna a escolha DETERMINISTICA: duas execucoes sobre o
        -- mesmo estado devolvem os mesmos IDs, e o relatorio e reproduzivel.
        SELECT COALESCE(string_agg(t.amostra, ' | ' ORDER BY t.ordem), '(indisponivel)')
          INTO v_amostra
          FROM (
            SELECT cv.id AS ordem,
                   cv.id::TEXT || ' (card_game=' || e.game_id::TEXT
                               || ' profile_game=' || p.game_id::TEXT || ')' AS amostra
              FROM public.card_variant cv
              JOIN public.card      c  ON c.id  = cv.card_id
              JOIN public.card_set  cs ON cs.id = c.card_set_id
              JOIN public.expansion e  ON e.id  = cs.expansion_id
              JOIN public.card_edition_context_profile p
                                        ON p.id = cv.edition_context_profile_id
             WHERE cv.edition_context_profile_id IS NOT NULL
               AND e.game_id <> p.game_id
             ORDER BY cv.id
             LIMIT 10
          ) t;

        RAISE EXCEPTION 'GUARD_EC_GAME_PREINSTALL_MISMATCH: % card_variant (de % com contexto de edicao) ja violam Same-Game. Instalar o guard agora tornaria essas linhas intocaveis. Corrigir o dado ANTES. Amostra deterministica (ate 10 de %, ordenada por cv.id): %', v_violacoes, v_alcance, v_violacoes, v_amostra;
    END IF;

    RAISE NOTICE 'PRE-INSTALACAO OK — % card_variant com contexto de edicao, 0 orfas, 0 Game irresolvivel, 0 mismatch.', v_alcance;
END $$;

-- ---------------------------------------------------------------- PASSO 3 ---
-- A FUNCAO DO GUARD. Espelho estrutural de
-- internal.enforce_card_variant_printing_profile_game() (Query 2170:100-141).
CREATE OR REPLACE FUNCTION internal.enforce_card_variant_edition_context_profile_game()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_card_game_id    UUID;
    v_profile_game_id UUID;
BEGIN
    -- Caminho sem contexto de edicao: zero trabalho. E o caso da esmagadora
    -- maioria das Variants — NULL aqui significa "sem contexto de edicao", um
    -- VALOR, nao desconhecido (Query 2208).
    IF NEW.edition_context_profile_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT e.game_id INTO v_card_game_id
      FROM public.card c
      JOIN public.card_set cs ON cs.id = c.card_set_id
      JOIN public.expansion e ON e.id = cs.expansion_id
     WHERE c.id = NEW.card_id;

    IF v_card_game_id IS NULL THEN
        RAISE EXCEPTION 'CARD_VARIANT_EDITION_CONTEXT_GAME_NOT_FOUND: nao foi possivel resolver o Game da Card % desta variante.', NEW.card_id;
    END IF;

    SELECT p.game_id INTO v_profile_game_id
      FROM public.card_edition_context_profile p
     WHERE p.id = NEW.edition_context_profile_id;

    IF v_profile_game_id IS NULL THEN
        RAISE EXCEPTION 'CARD_VARIANT_EDITION_CONTEXT_PROFILE_NOT_FOUND: Perfil de Contexto de Edicao % nao encontrado.', NEW.edition_context_profile_id;
    END IF;

    IF v_card_game_id <> v_profile_game_id THEN
        RAISE EXCEPTION 'CARD_VARIANT_EDITION_CONTEXT_GAME_MISMATCH: a Card pertence ao Game % e o Perfil de Contexto de Edicao ao Game % — combinacao invalida.', v_card_game_id, v_profile_game_id;
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION internal.enforce_card_variant_edition_context_profile_game() IS
'Guard de integridade do TERCEIRO eixo (Contexto de Edicao), Query 2224. Garante que card_variant.edition_context_profile_id, quando NAO NULO, pertenca ao MESMO Game da Card (resolvido por card -> card_set -> expansion). Retorna cedo quando a coluna e NULL — NULL significa "sem contexto de edicao", um VALOR. Esta funcao e a AUTORIDADE UNICA de Same-Game deste eixo: internal.write_card_variant() valida apenas EXISTENCIA do profile, de proposito, para nao criar segunda fonte de verdade. Espelha internal.enforce_card_variant_printing_profile_game() (Query 2170), que faz o mesmo para o eixo de Impressao.';

-- ACL — menor privilegio. Helper de trigger, JAMAIS contrato RPC publico.
-- A 2170:142 revoga so de PUBLIC; o padrao vigente do projeto (2210:205,
-- 2214:207) revoga tambem de anon e authenticated. Adotado o mais estrito.
--
-- O REVOKE abaixo e a ACAO; o gate G3 do PASSO 5 e a PROVA, e ele exige mais
-- do que este REVOKE remove: exige ACL **OWNER-ONLY**. Um grant posterior a
-- service_role, por exemplo, sobreviveria a este REVOKE e seria barrado la.
REVOKE ALL ON FUNCTION internal.enforce_card_variant_edition_context_profile_game()
    FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------- PASSO 4 ---
-- O TRIGGER. `UPDATE OF` cobre as DUAS colunas que participam da invariante:
-- trocar a Card muda o Game do lado esquerdo; trocar o profile muda o direito.
-- Omitir card_id era exatamente o defeito de trg_card_variant_validate_game_
-- consistency em relacao a este eixo.
--
-- POR QUE `CREATE OR REPLACE TRIGGER` E NAO `DROP` + `CREATE`
-- (BATCH9-2224-READINESS-CORRECTION-03)
--
--   O par `DROP TRIGGER IF EXISTS` + `CREATE TRIGGER` produzia ESCALADA DE
--   LOCK dentro desta mesma transacao:
--
--     PASSO 1-BIS  SHARE ROW EXCLUSIVE   (explicito)
--     PASSO 4      ACCESS EXCLUSIVE      <- adquirido IMPLICITAMENTE pelo
--                                           DROP TRIGGER
--     PASSO 4      SHARE ROW EXCLUSIVE   (CREATE TRIGGER, ja coberto)
--
--   ACCESS EXCLUSIVE conflita com ACCESS SHARE — ou seja, com SELECT puro.
--   A partir do momento em que o DROP fosse enfileirado, LEITORES de
--   `card_variant` passariam a esperar ate o COMMIT, e leitores novos
--   ficariam atras do pedido pendente. Isso contradizia tanto o requisito
--   de nao elevar o modo quanto a afirmacao de que leitores seguem livres.
--
--   `CREATE OR REPLACE TRIGGER` (PostgreSQL >= 14) substitui a definicao
--   IN PLACE, sem remover o objeto: adquire o mesmo SHARE ROW EXCLUSIVE que
--   `CREATE TRIGGER` — que esta transacao JA RETEM desde o PASSO 1-BIS.
--   Resultado: NENHUMA aquisicao nova, NENHUMA escalada, leitores livres do
--   `BEGIN;` ao `COMMIT;`.
--
--   ESTE E UM TRIGGER NORMAL, nao um CONSTRAINT TRIGGER. A restricao do
--   `OR REPLACE` — nao permitir trocar entre trigger normal e constraint
--   trigger — nao se aplica: tanto o objeto eventualmente existente quanto o
--   declarado abaixo sao normais (`CREATE TRIGGER ... FOR EACH ROW`, sem
--   `CONSTRAINT`, sem `DEFERRABLE`).
--
--   NENHUM UPDATE EM `card_variant` OCORRE ANTES DESTE PONTO NA TRANSACAO.
--   PASSO 1 le catalogos; PASSO 1-BIS so trava; PASSO 2 so faz SELECT;
--   PASSO 3 mexe em `pg_proc`, nao na tabela. A restricao do `OR REPLACE`
--   contra substituir um trigger em transacao que ja escreveu na tabela do
--   trigger, portanto, tambem nao e atingida.
--
--   IDEMPOTENCIA PRESERVADA: primeira execucao cria; reexecucao substitui.
--   Nao ha janela em que o trigger deixe de existir — diferentemente do
--   `DROP` + `CREATE`, que abria uma (curta, dentro da transacao, mas real
--   para qualquer sessao que enxergasse o estado intermediario).
CREATE OR REPLACE TRIGGER trg_card_variant_edition_context_profile_game
BEFORE INSERT OR UPDATE OF card_id, edition_context_profile_id
ON public.card_variant
FOR EACH ROW
EXECUTE FUNCTION internal.enforce_card_variant_edition_context_profile_game();

-- ---------------------------------------------------------------- PASSO 5 ---
-- POSTCHECK ESTRUTURAL, FAIL-CLOSED. Nenhuma heuristica de nome: o vinculo
-- trigger -> funcao e provado por OID, o tgtype por identidade exata, e o
-- UPDATE OF pelo conjunto de attnum resolvido.
DO $$
DECLARE
    v_oid        OID;
    v_n          INT;
    v_sec        BOOLEAN;
    v_cfg        TEXT[];
    v_acl_nula   BOOLEAN;
    v_owner      OID;
    v_owner_nome TEXT;
    v_owner_tem  BOOLEAN;
    v_n_grantee  INT;
    v_quem       TEXT;
    v_tgtype     INT;
    v_tgfoid     OID;
    v_cols       NAME[];
    v_trgs       NAME[];
    v_dups       TEXT;
    v_final      BIGINT;
BEGIN
    -- G1 — exatamente UMA funcao com a assinatura esperada.
    SELECT count(*) INTO v_n
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'internal'
       AND p.proname = 'enforce_card_variant_edition_context_profile_game'
       AND p.pronargs = 0;

    IF v_n <> 1 THEN
        RAISE EXCEPTION 'GUARD_EC_G1_FUNCTION_COUNT: esperada 1 funcao, encontradas %.', v_n;
    END IF;

    v_oid := to_regprocedure('internal.enforce_card_variant_edition_context_profile_game()')::OID;
    IF v_oid IS NULL THEN
        RAISE EXCEPTION 'GUARD_EC_G1_FUNCTION_OID: nao foi possivel resolver o OID da funcao do guard.';
    END IF;

    -- G2 — SECURITY DEFINER e search_path EXATAMENTE vazio.
    -- Igualdade de array, NUNCA `LIKE '%search_path=%'`: o LIKE aceitaria
    -- `search_path=public`, que em SECURITY DEFINER e vetor de hijacking.
    SELECT p.prosecdef, p.proconfig INTO v_sec, v_cfg
      FROM pg_proc p WHERE p.oid = v_oid;

    IF v_sec IS NOT TRUE THEN
        RAISE EXCEPTION 'GUARD_EC_G2_NOT_SECDEF: a funcao do guard nao e SECURITY DEFINER.';
    END IF;
    IF v_cfg IS DISTINCT FROM ARRAY['search_path=""']::TEXT[] THEN
        RAISE EXCEPTION 'GUARD_EC_G2_SEARCH_PATH: proconfig deve ser exatamente ARRAY[''search_path=""''], obtido %.', COALESCE(v_cfg::TEXT, '(NULO)');
    END IF;

    -- G3 — ACL **OWNER-ONLY**, fail-closed. Esta funcao e helper de trigger,
    -- JAMAIS contrato RPC: o unico principal que pode ter EXECUTE e o proprio
    -- owner. Nao basta barrar PUBLIC/anon/authenticated por nome — uma lista
    -- de roles proibidas e sempre incompleta (service_role, um role de BI,
    -- qualquer role futura). A prova e por CARDINALIDADE e IDENTIDADE:
    -- exatamente UM grantee, e esse grantee E o proowner. Qualquer outro
    -- principal, nomeado ou nao, reprova.
    SELECT p.proacl IS NULL, p.proowner, pg_get_userbyid(p.proowner)
      INTO v_acl_nula, v_owner, v_owner_nome
      FROM pg_proc p WHERE p.oid = v_oid;

    -- G3.a — proacl NULL e ACL PADRAO, e o padrao para funcao e EXECUTE a
    -- PUBLIC. Ausencia de grant explicito NAO e prova de restricao.
    IF v_acl_nula THEN
        RAISE EXCEPTION 'GUARD_EC_G3_ACL_DEFAULT: proacl e NULL — ACL padrao, que concede EXECUTE a PUBLIC. O REVOKE do PASSO 3 nao surtiu efeito.';
    END IF;

    SELECT count(DISTINCT a.grantee),
           COALESCE(bool_or(a.grantee = v_owner), false),
           COALESCE(string_agg(DISTINCT CASE WHEN a.grantee = 0
                                             THEN 'PUBLIC'
                                             ELSE pg_get_userbyid(a.grantee) END, ', '),
                    '(ninguem)')
      INTO v_n_grantee, v_owner_tem, v_quem
      FROM pg_proc p, aclexplode(p.proacl) a
     WHERE p.oid = v_oid AND a.privilege_type = 'EXECUTE';

    -- G3.b — o owner precisa poder executar. Sem isso o trigger nao roda.
    IF NOT v_owner_tem THEN
        RAISE EXCEPTION 'GUARD_EC_G3_OWNER_SEM_EXECUTE: o owner (%) nao tem EXECUTE. Mantem EXECUTE: %.', v_owner_nome, v_quem;
    END IF;

    -- G3.c — cardinalidade: UM e apenas um grantee.
    IF v_n_grantee <> 1 THEN
        RAISE EXCEPTION 'GUARD_EC_G3_ACL_NAO_OWNER_ONLY: esperado EXATAMENTE 1 grantee com EXECUTE (o owner %), encontrados %. Mantem EXECUTE: %. Esta funcao e helper de trigger — qualquer principal alem do owner (PUBLIC, anon, authenticated, service_role ou outro) e violacao de contrato.', v_owner_nome, v_n_grantee, v_quem;
    END IF;

    -- G3.b + G3.c juntos implicam: o unico grantee E o proowner. Nenhuma
    -- lista de roles proibidas foi usada — a prova e fechada por construcao.

    -- G4 — exatamente UM trigger com o nome esperado na tabela.
    -- Contagem primeiro; SO DEPOIS a leitura dos atributos, via SELECT INTO
    -- STRICT. Nenhum agregado sobre `oid`: a versao anterior usava
    -- `COALESCE(max(t.tgfoid), 0)`, que depende do agregado `max(oid)` — um
    -- caminho que este rollout nunca exercitou no LIVE. `INTO STRICT` da o
    -- mesmo resultado sem depender disso, e ainda levanta NO_DATA_FOUND /
    -- TOO_MANY_ROWS se a cardinalidade mudar entre as duas leituras.
    SELECT count(*) INTO v_n
      FROM pg_trigger t
      JOIN pg_class c ON c.oid = t.tgrelid
      JOIN pg_namespace ns ON ns.oid = c.relnamespace
     WHERE NOT t.tgisinternal
       AND ns.nspname = 'public' AND c.relname = 'card_variant'
       AND t.tgname = 'trg_card_variant_edition_context_profile_game';

    IF v_n <> 1 THEN
        RAISE EXCEPTION 'GUARD_EC_G4_TRIGGER_COUNT: esperado 1 trigger, encontrados %.', v_n;
    END IF;

    SELECT t.tgtype::INT, t.tgfoid
      INTO STRICT v_tgtype, v_tgfoid
      FROM pg_trigger t
      JOIN pg_class c ON c.oid = t.tgrelid
      JOIN pg_namespace ns ON ns.oid = c.relnamespace
     WHERE NOT t.tgisinternal
       AND ns.nspname = 'public' AND c.relname = 'card_variant'
       AND t.tgname = 'trg_card_variant_edition_context_profile_game';

    -- G5 — vinculo trigger -> funcao provado por OID, nao por nome.
    IF v_tgfoid <> v_oid THEN
        RAISE EXCEPTION 'GUARD_EC_G5_TGFOID: o trigger aponta para o OID % , esperado % (a funcao do guard).', v_tgfoid, v_oid;
    END IF;

    -- G6 — tgtype EXATO: 1 ROW + 2 BEFORE + 4 INSERT + 16 UPDATE = 23.
    -- Identidade, nao conjuncao de bits: um DELETE (8) ou TRUNCATE (32) extra
    -- faria o guard rodar com NEW nulo/indefinido e reprova aqui.
    IF v_tgtype <> 23 THEN
        RAISE EXCEPTION 'GUARD_EC_G6_TGTYPE: tgtype deve ser exatamente 23 (BEFORE+ROW+INSERT+UPDATE), obtido %.', v_tgtype;
    END IF;

    -- G7 — UPDATE OF exatamente as DUAS colunas, resolvidas por attnum.
    SELECT array_agg(a.attname ORDER BY a.attname) INTO v_cols
      FROM pg_trigger t
      JOIN pg_class c ON c.oid = t.tgrelid
      JOIN pg_namespace ns ON ns.oid = c.relnamespace
      CROSS JOIN LATERAL unnest(t.tgattr::INT2[]) u(attnum)
      JOIN pg_attribute a ON a.attrelid = t.tgrelid AND a.attnum = u.attnum
     WHERE NOT t.tgisinternal
       AND ns.nspname = 'public' AND c.relname = 'card_variant'
       AND t.tgname = 'trg_card_variant_edition_context_profile_game';

    IF v_cols IS DISTINCT FROM ARRAY['card_id','edition_context_profile_id']::NAME[] THEN
        RAISE EXCEPTION 'GUARD_EC_G7_UPDATE_OF: UPDATE OF deve cobrir exatamente card_id + edition_context_profile_id, obtido %.', COALESCE(v_cols::TEXT, '(nenhuma)');
    END IF;

    -- G8a — TOPOLOGIA DA TABELA. Apos a 2224, public.card_variant tem
    -- EXATAMENTE quatro triggers nao-internos, e sao estes quatro. Comparacao
    -- de CONJUNTO EXATO por nome, nao `count = 4`: quatro triggers dos quais
    -- um e intruso e outro sumiu daria count correto e topologia errada.
    SELECT array_agg(t.tgname ORDER BY t.tgname) INTO v_trgs
      FROM pg_trigger t
      JOIN pg_class c ON c.oid = t.tgrelid
      JOIN pg_namespace ns ON ns.oid = c.relnamespace
     WHERE NOT t.tgisinternal
       AND ns.nspname = 'public' AND c.relname = 'card_variant';

    IF v_trgs IS DISTINCT FROM ARRAY[
            'trg_card_variant_edition_context_profile_game',
            'trg_card_variant_printing_profile_game',
            'trg_card_variant_set_updated_at',
            'trg_card_variant_validate_game_consistency'
       ]::NAME[] THEN
        RAISE EXCEPTION 'GUARD_EC_G8A_TOPOLOGIA: public.card_variant deve ter EXATAMENTE os 4 triggers canonicos (edition_context_profile_game, printing_profile_game, set_updated_at, validate_game_consistency). Obtido: %.', COALESCE(v_trgs::TEXT, '(nenhum)');
    END IF;

    -- G8b — DUPLICACAO DA FUNCAO DO GUARD, varredura CLUSTER-WIDE por tgfoid.
    -- A exclusao da instancia canonica e pela IDENTIDADE EXATA
    -- schema + tabela + nome — NAO apenas pelo nome. Excluir so por `tgname`
    -- deixaria passar um trigger homonimo em OUTRA tabela executando o mesmo
    -- guard: ele seria silenciosamente tratado como "o canonico".
    SELECT count(*),
           COALESCE(string_agg(ns.nspname || '.' || c.relname || '.' || t.tgname,
                               ', ' ORDER BY ns.nspname, c.relname, t.tgname),
                    '(nenhum)')
      INTO v_n, v_dups
      FROM pg_trigger t
      JOIN pg_class c ON c.oid = t.tgrelid
      JOIN pg_namespace ns ON ns.oid = c.relnamespace
     WHERE NOT t.tgisinternal
       AND t.tgfoid = v_oid
       AND NOT (ns.nspname = 'public'
                AND c.relname = 'card_variant'
                AND t.tgname  = 'trg_card_variant_edition_context_profile_game');

    IF v_n <> 0 THEN
        RAISE EXCEPTION 'GUARD_EC_G8B_TRIGGER_DUPLICADO: % trigger(s) alem do canonico executam internal.enforce_card_variant_edition_context_profile_game(): %. Autoridade unica por eixo — investigar antes de prosseguir.', v_n, v_dups;
    END IF;

    -- G9 — INVARIANTE SAME-GAME FINAL, sobre os DADOS, depois do DDL.
    --
    -- NAO substitui o PASSO 2. O PASSO 2 e pre-condicao: decide se a migration
    -- PODE prosseguir. Este e prova posterior: confirma que a populacao
    -- continua valida DEPOIS de a funcao e o trigger existirem.
    --
    -- Sob o LOCK do PASSO 1-BIS os dois necessariamente coincidem — e e essa
    -- coincidencia que se esta provando. Se G9 divergir do PASSO 2, o lock
    -- nao segurou (modo errado, adquirido tarde, ou liberado cedo) e a janela
    -- TOCTOU esteve aberta. Medir de novo e barato; assumir e que nao e.
    --
    -- Sem LIMIT, sem amostra: aqui so importa a cardinalidade, e ela tem de
    -- ser ZERO.
    SELECT count(*) INTO v_final
      FROM public.card_variant cv
      JOIN public.card      c  ON c.id  = cv.card_id
      JOIN public.card_set  cs ON cs.id = c.card_set_id
      JOIN public.expansion e  ON e.id  = cs.expansion_id
      JOIN public.card_edition_context_profile p
                                ON p.id = cv.edition_context_profile_id
     WHERE cv.edition_context_profile_id IS NOT NULL
       AND e.game_id <> p.game_id;

    IF v_final <> 0 THEN
        RAISE EXCEPTION 'GUARD_EC_G9_INVARIANTE_FINAL: % card_variant violam Same-Game APOS a instalacao do guard, embora o PASSO 2 tenha medido 0. Isso significa que uma escrita concorrente atravessou a janela entre medir e proteger — o LOCK do PASSO 1-BIS nao segurou. ROLLBACK de toda a migration; investigar antes de repetir.', v_final;
    END IF;

    RAISE NOTICE 'GUARD 2224 OK — 1 funcao (SECDEF, search_path vazio, ACL OWNER-ONLY: unico grantee com EXECUTE = % = owner), 1 trigger canonico (tgfoid por OID, tgtype=23, UPDATE OF = card_id + edition_context_profile_id), topologia da tabela = os 4 triggers canonicos, 0 duplicatas cluster-wide, invariante Same-Game FINAL = 0 violacoes sob LOCK SHARE ROW EXCLUSIVE.', v_quem;
END $$;

-- ============================================================================
-- ESTADO APOS ESTA QUERY
-- ----------------------------------------------------------------------------
--   Os TRES eixos de identidade de card_variant passam a ter guard same-Game:
--     Variant Type ....... public.validate_card_variant_game_consistency   161
--     Printing Profile ... internal.enforce_card_variant_printing_profile_game
--                                                                          2170
--     Edition Context .... internal.enforce_card_variant_edition_context_profile_game
--                                                                    ← ESTA
--
--   internal.write_card_variant() NAO muda nesta Query e NAO ganha validacao
--   de same-Game. Continua validando apenas EXISTENCIA — pela 2143 (Printing)
--   e, apos a 2217, tambem para o Contexto de Edicao.
--
-- PROXIMO PASSO DO ROLLOUT: 2217 (EXPAND). A ordem e
--   2224 -> 2217 -> 2218 -> 2223, definida no DAG.md, NAO pela numeracao.
--
-- CONCORRENCIA — os quatro cenarios, sob o LOCK do PASSO 1-BIS
--   A) writer comeca ANTES do LOCK e comita linha VALIDA
--      O `LOCK TABLE` espera o RowExclusiveLock dele ser liberado no COMMIT.
--      So entao a 2224 prossegue, e o PASSO 2 ja enxerga a linha nova.
--      -> SEGURO. A linha e valida; os gates passam; o guard cobre-a dai em
--         diante.
--
--   B) writer comeca ANTES do LOCK e comita linha CROSS-GAME
--      Mesma espera. O PASSO 2 mede DEPOIS e encontra a violacao.
--      -> STOP antes de qualquer DDL: `GUARD_EC_GAME_PREINSTALL_MISMATCH`
--         reporta total real e amostra deterministica. Nenhuma funcao,
--         nenhum trigger foi criado.
--
--   C) writer comeca DEPOIS do LOCK
--      Seu RowExclusiveLock conflita com o SHARE ROW EXCLUSIVE ja retido e
--      ele ESPERA. A 2224 mede, instala e comita; o lock cai no COMMIT.
--      -> SEGURO. O writer prossegue com o trigger JA ATIVO: se a linha for
--         cross-Game, o guard a recusa com
--         `CARD_VARIANT_EDITION_CONTEXT_GAME_MISMATCH`.
--
--   D) 2224 ABORTA depois de adquirir o lock (qualquer gate, G1..G9)
--      O ROLLBACK libera o lock e desfaz tudo — `CREATE OR REPLACE FUNCTION`,
--      `CREATE OR REPLACE TRIGGER` e o proprio LOCK sao transacionais.
--      -> Nenhuma alteracao estrutural persiste; writers em espera retomam
--         contra o estado ORIGINAL, sem o guard e sem resíduo.
--
--   Nao ha janela entre medir e proteger: o mesmo lock cobre PASSO 2, PASSO 3,
--   PASSO 4 e PASSO 5, e so e liberado quando o guard ja esta no lugar.
--
-- LOCK EFETIVO — PERFIL COMPLETO DA TRANSACAO
--   Sobre `public.card_variant`, do BEGIN ao COMMIT:
--     modo maximo retido ......... SHARE ROW EXCLUSIVE
--     escaladas .................. NENHUMA
--     INSERT/UPDATE/DELETE ....... BLOQUEADOS (ROW EXCLUSIVE conflita)
--     SELECT ..................... LIVRE (ACCESS SHARE nao conflita)
--     SELECT FOR SHARE/UPDATE .... LIVRE (ROW SHARE nao conflita)
--     liberacao .................. COMMIT ou ROLLBACK, automatica
--
-- DEADLOCK
--   Um unico lock, adquirido cedo, sobre uma unica tabela. Nao ha escalada
--   tardia nem ordem variavel de aquisicao — as duas causas classicas.
--   A CORRECTION-03 eliminou a ultima escalada que restava (o DROP TRIGGER).
--
-- ROLLBACK
--   DROP TRIGGER trg_card_variant_edition_context_profile_game ON public.card_variant;
--   DROP FUNCTION internal.enforce_card_variant_edition_context_profile_game();
--   Nenhum dado e alterado por esta Query — ela so acrescenta uma recusa.
--
-- REEXECUCAO
--   Idempotente, e agora SEM remover nada. `CREATE OR REPLACE FUNCTION`
--   substitui o corpo e `CREATE OR REPLACE TRIGGER` substitui a definicao do
--   gatilho in place; os gates do PASSO 2 remedem o universo atual e o
--   PASSO 5 revalida a estrutura. Rodar duas vezes converge ao mesmo estado,
--   e em nenhum instante o trigger deixa de existir. O LOCK tambem e
--   readquirido a cada execucao — na segunda, com o guard ja ativo, nenhum
--   writer conseguiria ter criado violacao de qualquer modo.
--
-- TERMINADOR COMMIT. A protecao contra execucao prematura e GOVERNANCA
-- (autorizacao de Fabricio + ordem do DAG), nao o terminador — mesma decisao
-- ja aceita em R1 para 2203-2211 e reafirmada em 2214.
-- ============================================================================
COMMIT;
