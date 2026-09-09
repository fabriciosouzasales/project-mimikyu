/*
================================================================
Query 5823 — validação de preview_bulk_operation() (BULK-03)
================================================================
Versão......: 2.2
Status......: CONFIRMADO EXECUTADO (2026-09-09) — gate 60/60/0/0
Frente......: COLLECTIONS-BULK-03 — Preview
Rodada......: -GATE-A-REVISION-01 -> -REVISION-02 -> -EXECUTION-01
              -> -GATE-A-HARNESS-CORRECTION-01
Valida......: 5151_create_preview_bulk_operation_function.sql
Pré-req.....: 5151 APLICADA. 5142-5150 LIVE e intocadas.

================================================================
GATE OBRIGATÓRIO
================================================================
    60 TOTAL / 60 PASS / 0 FAIL / 0 NOT PROVEN

Nenhum caso pode ser "N/A", "pulado" ou "assumido". Um caso que não
consegue rodar é FAIL, não ausência.

================================================================
GRUPOS
================================================================
  X (2)  baseline e resíduo relativo das NOVE tabelas
  F (3)  fixtures, incluindo o Game sintético ZZTEST_BULK03_<único>
  E (7)  estrutura estática: DEFINER, VOLATILE, search_path,
         sobrecarga única, ausência de TODA DML e de lock/claim
  S (4)  ACL nos quatro papéis
  V (3)  vocabulário de operation_type — as TRÊS situações
  G (10) guards estruturais -> exceção, com SQLSTATE verificado
  T (4)  teto 1000 aceito / 1001 rejeitado, bruto e expandido
  K (4)  contrato ok=true
  I (11) contrato ok=false, um por code de issue
  N (6)  não-enumeração de Collection E de Storage
  P (3)  fingerprint Preview x execução, como `authenticated` REAL
  D (3)  performance observacional com 1000 Card Variants REAIS

================================================================
O QUE MUDOU NA v2.0 (`-GATE-A-REVISION-01`)
================================================================
`5151` NÃO foi alterada. Todas as mudanças são deste harness.

  1. `I10` fecha a lacuna de `GAME_MISMATCH`, com um Game sintético
     de código ÚNICO por execução criado DENTRO da transação e uma
     Collection de `u1` nesse Game, contra uma Card Variant REAL do
     Game Pokémon. Nenhum catálogo sintético de segundo Game é criado.
  2. `I11` fecha a lacuna de `INVENTORY_NOT_FOUND`, com um `sub` de
     JWT sintético sem Inventory. Nenhum `auth.users` é criado ou
     apagado.
  3. `N04`-`N06` estendem a prova de não-enumeração ao Storage.
  4. `E07` passa a rejeitar TODA DML — o predicado anterior anunciava
     `UPDATE` no rótulo e não o verificava. Defeito do harness.
  5. `_expect_error` passa a validar SQLSTATE além da mensagem;
     `G10` prova `28000` para `auth.uid()` ausente.
  6. `D01`-`D03` trocam o payload de 2 itens x 500 por 1000
     `card_variant_id` REAIS e distintos, `quantity = 1`. Sem
     Collection e sem Storage. Se o catálogo não tiver 1000 Card
     Variants, o caso FALHA — jamais reduz a carga em silêncio.
  7. `P03` captura exceção de `5150` e registra FAIL, em vez de
     abortar o harness antes do relatório.
  8. Baseline e postcheck passam de OITO para NOVE tabelas:
     `public.game` agora é tocada pela fixture de `I10`.

================================================================
O QUE MUDOU NA v2.1 (`-GATE-A-REVISION-02`)
================================================================
`5151` continua APROVADA e INTOCADA. Os dois defeitos eram do `F03`
deste harness — e o primeiro teria derrubado a execução ANTES do gate:

  1. `F03` passava `NULL` em `p_default_storage_container_id`. O guard
     de `create_collection()` (`5034`) é um `NOT EXISTS`
     INCONDICIONAL: com `NULL`, `sc.id = NULL` nunca é verdadeiro, o
     `NOT EXISTS` dispara e a RPC aborta. Agora usa `sc1`, o Storage
     de `u1` criado em `F02`. O que `I10` prova não muda — Storage não
     entra no cálculo de Game.
  2. O código do Game sintético era o literal fixo `ZZTEST`.
     `public.game.code` tem `uq_game_code`: um literal faria a segunda
     execução colidir com qualquer resíduo da primeira. Agora é
     `ZZTEST_BULK03_<32 hex maiúsculos>`, único por execução, com
     comprimento e formato asserido pelo próprio `F03`.
  3. Postcheck externo passa de `code = 'ZZTEST'` para
     `code LIKE 'ZZTEST_BULK03_%'`, que cobre TODAS as execuções.

Contagem de casos INALTERADA: o gate continua `60/60/0/0`.

================================================================
O QUE MUDOU NA v2.2 (`-GATE-A-HARNESS-CORRECTION-01`)
================================================================
`5151` foi APLICADA em 2026-09-09 (ledger `20260909024422`) e
permanece FROZEN — nada nela mudou nesta correção.

A execução da v2.1 deu **59/60**. O único FAIL foi `E06`, e era
defeito EXCLUSIVO do harness:

  - `pg_get_function_identity_arguments()` devolve os NOMES dos
    parâmetros junto com os tipos: `p_request jsonb`, não `jsonb`.
    A v2.1 comparava com `'jsonb'` e falhava sempre.
  - O produto estava correto: o postcheck estrutural externo, na mesma
    rodada, mediu 1 sobrecarga / `p_request jsonb` / `jsonb`.
  - O idioma correto já existia no repositório — é literalmente o
    `E06` do `5822`. Não foi reaproveitado. Mesma classe do defeito de
    `search_path` em BULK-02.

Correções desta versão, ambas SÓ no harness:

  1. `E06` passa a exigir as três coisas: exatamente 1 sobrecarga,
     `identity arguments = 'p_request jsonb'` e
     `format_type(prorettype) = 'jsonb'`.
  2. O relatório final imprime `got` também nos PASS do grupo `D`,
     para que a medição de `D03` chegue ao output. Casos
     observacionais que só mostram o número quando falham não entregam
     medição nenhuma.

Nenhum caso foi adicionado ou removido. A lógica do gate é a mesma:
`count(*) = 60 AND fail = 0`.

================================================================
TRANSPORTE — ADAPTAÇÃO REGISTRADA
================================================================
Foi medido em BULK-02 (2026-09-09) que o canal MCP `execute_sql` não
preserva sessão nem transação entre chamadas. Este harness roda
portanto em CHAMADA ÚNICA, e entrega o relatório final por
`RAISE EXCEPTION` — que aborta a transação e força o ROLLBACK POR
CONSTRUÇÃO, sem depender de o executor lembrar de rodar `ROLLBACK`.

Nenhum caso de teste é alterado por essa adaptação: o gate avaliado é
o mesmo `count(*) = 60 AND fail = 0`. Se o executor tiver uma sessão
`psql` real, pode rodar `BEGIN; \i 5823...; ROLLBACK;` — o resultado
é idêntico, apenas sem a exceção final.

================================================================
POR QUE O GRUPO `P` USA `SET LOCAL ROLE authenticated`
================================================================
Este é o ponto mais delicado do harness, e merece justificativa
explícita porque contraria a escolha feita no grupo `C` do `5821`.

`5821` deliberadamente NÃO troca de papel: define apenas
`request.jwt.claims`, porque é assim que o chamador real opera contra
uma RPC `SECURITY DEFINER`, que roda como `postgres` de qualquer jeito.

Aqui isso NÃO serve. O risco que o grupo `P` existe para pegar é
`5151` ter sido escrita como `SECURITY INVOKER`. Se o harness rodar
como `postgres` (o executor normal), uma `5151` INVOKER TAMBÉM leria o
catálogo inteiro, os fingerprints bateriam e o teste passaria — sendo
que em produção, com `authenticated` de verdade, o catálogo viria
vazio por RLS (`ADR-022`/`ADR-030`) e 100% das execuções falhariam com
`PREVIEW_STALE`.

Um teste que passa tanto no código certo quanto no errado não prova
nada. Por isso `P` assume o papel `authenticated` DE VERDADE.

Consequência operacional, aprendida em `5808`: enquanto o papel está
trocado, NÃO se lê `pg_temp` nem tabelas temporárias. Todo valor de
fixture é capturado ANTES do switch, e todo `_rec` acontece DEPOIS do
`RESET ROLE`.

STATUS DESTA QUERY: CONFIRMADO EXECUTADO (2026-09-09) — gate
60 TOTAL / 60 PASS / 0 FAIL / 0 NOT PROVEN. Nao promovido para
database/schema/ por politica canonica: harness e evidencia
historica, permanece somente nesta pasta.
================================================================
*/

BEGIN;

-- ================================================================
-- INFRAESTRUTURA
-- ================================================================
CREATE TEMP TABLE _r (
    grp    TEXT    NOT NULL,
    label  TEXT    NOT NULL,
    passed BOOLEAN NOT NULL,
    got    TEXT,
    want   TEXT
) ON COMMIT DROP;

CREATE TEMP TABLE _bl (k TEXT PRIMARY KEY, n BIGINT NOT NULL) ON COMMIT DROP;
CREATE TEMP TABLE _fx (k TEXT PRIMARY KEY, v UUID) ON COMMIT DROP;

CREATE FUNCTION pg_temp._rec(
    p_grp TEXT, p_label TEXT, p_passed BOOLEAN, p_got TEXT, p_want TEXT
) RETURNS VOID LANGUAGE sql AS $$
    INSERT INTO _r (grp, label, passed, got, want)
    VALUES (p_grp, p_label, COALESCE(p_passed, FALSE), p_got, p_want);
$$;

-- Espera FALHA cujo SQLERRM contenha `p_needle` E cujo SQLSTATE seja
-- exatamente `p_sqlstate`. Validar so a mensagem deixaria passar um
-- erro certo pelo motivo errado — por exemplo um `22P02` de cast mal
-- posicionado que por acaso contivesse o texto esperado.
CREATE FUNCTION pg_temp._expect_error(
    p_grp TEXT, p_label TEXT, p_sql TEXT, p_needle TEXT,
    p_sqlstate TEXT DEFAULT '22023'
) RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_msg TEXT; v_state TEXT;
BEGIN
    BEGIN
        EXECUTE p_sql;
        PERFORM pg_temp._rec(p_grp, p_label, FALSE,
            'NAO levantou excecao',
            format('excecao SQLSTATE %s contendo: %s', p_sqlstate, p_needle));
        RETURN;
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM; v_state := SQLSTATE;
    END;
    PERFORM pg_temp._rec(p_grp, p_label,
        position(p_needle in v_msg) > 0 AND v_state = p_sqlstate,
        format('SQLSTATE=%s | %s', v_state, v_msg),
        format('excecao SQLSTATE %s contendo: %s', p_sqlstate, p_needle));
END;
$$;

CREATE FUNCTION pg_temp._as(p_uid UUID) RETURNS VOID LANGUAGE sql AS $$
    SELECT set_config('request.jwt.claims',
        json_build_object('sub', p_uid::text, 'role', 'authenticated')::text, TRUE);
$$;

-- Claims SEM `sub`: `auth.uid()` devolve NULL. Objeto JSON valido de
-- proposito — string vazia faria o cast para json estourar antes, e o
-- teste passaria pelo motivo errado.
CREATE FUNCTION pg_temp._anon() RETURNS VOID LANGUAGE sql AS $$
    SELECT set_config('request.jwt.claims', '{}', TRUE);
$$;

CREATE FUNCTION pg_temp._fx(p_k TEXT) RETURNS UUID LANGUAGE sql STABLE AS $$
    SELECT v FROM _fx WHERE k = p_k;
$$;

-- Padrão CANÔNICO de `5821`/`5822`: o PostgreSQL persiste
-- `SET search_path = ''` como `search_path=""`, com aspas. Comparar
-- com o literal 'search_path=' nunca casa.
CREATE FUNCTION pg_temp._empty_search_path(p_oid OID)
RETURNS BOOLEAN LANGUAGE plpgsql STABLE AS $fn$
DECLARE v_elem TEXT; v_val TEXT;
BEGIN
    SELECT c INTO v_elem
      FROM pg_proc p, unnest(COALESCE(p.proconfig, ARRAY[]::text[])) AS c
     WHERE p.oid = p_oid AND c LIKE 'search_path=%'
     LIMIT 1;
    IF v_elem IS NULL THEN RETURN FALSE; END IF;
    v_val := substring(v_elem from length('search_path=') + 1);
    RETURN btrim(COALESCE(v_val, ''), '''" ') = '';
END; $fn$;

-- Envelope de 5151 (SEM idempotency_key, SEM preview_fingerprint).
CREATE FUNCTION pg_temp._preq(
    p_op TEXT, p_items JSONB, p_col UUID DEFAULT NULL, p_stg UUID DEFAULT NULL
) RETURNS JSONB LANGUAGE sql IMMUTABLE AS $$
    SELECT jsonb_strip_nulls(jsonb_build_object(
        'operation_type',       p_op,
        'items',                p_items,
        'collection_id',        p_col::text,
        'storage_container_id', p_stg::text
    ));
$$;

-- Envelope de 5150 (congelado em BULK-02).
CREATE FUNCTION pg_temp._xreq(
    p_key UUID, p_fp TEXT, p_items JSONB,
    p_col UUID DEFAULT NULL, p_stg UUID DEFAULT NULL
) RETURNS JSONB LANGUAGE sql IMMUTABLE AS $$
    SELECT jsonb_strip_nulls(jsonb_build_object(
        'idempotency_key',      p_key::text,
        'preview_fingerprint',  p_fp,
        'items',                p_items,
        'collection_id',        p_col::text,
        'storage_container_id', p_stg::text
    ));
$$;

CREATE FUNCTION pg_temp._it(p_cv TEXT, p_lang TEXT, p_qty NUMERIC)
RETURNS JSONB LANGUAGE sql IMMUTABLE AS $$
    SELECT jsonb_build_object('card_variant_id', p_cv,
                              'language_id',     p_lang,
                              'quantity',        p_qty);
$$;

-- Um issue especifico esta presente?
CREATE FUNCTION pg_temp._has_issue(p_res JSONB, p_code TEXT)
RETURNS BOOLEAN LANGUAGE sql IMMUTABLE AS $$
    SELECT EXISTS (
        SELECT 1 FROM jsonb_array_elements(p_res -> 'issues') AS i(e)
         WHERE i.e ->> 'code' = p_code
           AND i.e ->> 'severity' = 'BLOCKING'
    );
$$;

-- ================================================================
-- X01 — BASELINE das NOVE tabelas que o harness cria ou toca.
--       Capturado ANTES de qualquer escrita. O critério de resíduo é
--       RELATIVO ao baseline, nunca "tudo zero".
--
--       `public.game` entrou na v2.0: a fixture de `I10` cria o Game
--       sintetico ZZTEST_BULK03_<unico> para provar GAME_MISMATCH. Toda tabela que o
--       harness toca precisa estar no baseline — senao o postcheck
--       mediria menos do que o harness escreveu.
-- ================================================================
INSERT INTO _bl (k, n)
SELECT 'bulk_operation',        count(*) FROM public.bulk_operation
UNION ALL SELECT 'physical_card',                  count(*) FROM public.physical_card
UNION ALL SELECT 'collection_allocation',          count(*) FROM public.collection_allocation
UNION ALL SELECT 'collection',                     count(*) FROM public.collection
UNION ALL SELECT 'collection_reference',           count(*) FROM public.collection_reference
UNION ALL SELECT 'collection_card_set_reference',  count(*) FROM public.collection_card_set_reference
UNION ALL SELECT 'storage_container',              count(*) FROM public.storage_container
UNION ALL SELECT 'inventory',                      count(*) FROM public.inventory
UNION ALL SELECT 'game',                           count(*) FROM public.game;

DO $X1$
BEGIN
    PERFORM pg_temp._rec('X','X01 - baseline das 9 tabelas capturado ANTES de qualquer escrita (criterio de residuo e RELATIVO)',
        (SELECT count(*) FROM _bl) = 9,
        (SELECT string_agg(k || '=' || n, ' ' ORDER BY k) FROM _bl),
        '9 contagens registradas');
END;
$X1$;

-- ================================================================
-- GRUPO F — FIXTURES
-- ================================================================
DO $F$
DECLARE
    v_u1 UUID; v_u2 UUID;
    v_cv1 UUID; v_cv2 UUID; v_cv_other UUID;
    v_lang UUID; v_game UUID; v_set1 UUID;
    v_inv1 UUID; v_sc1 UUID; v_sc2 UUID;
    v_col_open UUID; v_col_ref UUID; v_col_arch UUID; v_col_alheia UUID;
BEGIN
    SELECT id INTO v_u1 FROM auth.users ORDER BY created_at, id LIMIT 1;
    SELECT id INTO v_u2 FROM auth.users WHERE id <> v_u1 ORDER BY created_at, id LIMIT 1;

    -- Catalogo real: duas Card Variants do MESMO Card Set e uma de
    -- OUTRO Card Set do MESMO Game (prova de elegibilidade).
    SELECT cv.id, ca.card_set_id, ex.game_id
      INTO v_cv1, v_set1, v_game
      FROM public.card_variant cv
      JOIN public.card ca      ON ca.id = cv.card_id
      JOIN public.card_set cs  ON cs.id = ca.card_set_id
      JOIN public.expansion ex ON ex.id = cs.expansion_id
     ORDER BY cv.id LIMIT 1;

    SELECT cv.id INTO v_cv2
      FROM public.card_variant cv
      JOIN public.card ca ON ca.id = cv.card_id
     WHERE ca.card_set_id = v_set1 AND cv.id <> v_cv1
     ORDER BY cv.id LIMIT 1;

    SELECT cv.id INTO v_cv_other
      FROM public.card_variant cv
      JOIN public.card ca      ON ca.id = cv.card_id
      JOIN public.card_set cs  ON cs.id = ca.card_set_id
      JOIN public.expansion ex ON ex.id = cs.expansion_id
     WHERE ex.game_id = v_game AND ca.card_set_id <> v_set1
     ORDER BY cv.id LIMIT 1;

    SELECT id INTO v_lang FROM public.language ORDER BY id LIMIT 1;

    PERFORM pg_temp._rec('F','F01 - fixture de catalogo e usuarios resolvida (2 users, 3 card_variants sendo 1 de outro Card Set do mesmo Game, 1 language)',
        v_u1 IS NOT NULL AND v_u2 IS NOT NULL AND v_cv1 IS NOT NULL
        AND v_cv2 IS NOT NULL AND v_cv_other IS NOT NULL AND v_lang IS NOT NULL,
        format('u1=%s u2=%s cv1=%s cv2=%s cv_other=%s lang=%s',
               v_u1 IS NOT NULL, v_u2 IS NOT NULL, v_cv1 IS NOT NULL,
               v_cv2 IS NOT NULL, v_cv_other IS NOT NULL, v_lang IS NOT NULL),
        'todos NOT NULL');

    -- ---- usuario 1 -------------------------------------------------
    PERFORM pg_temp._as(v_u1);

    SELECT inv.id INTO v_inv1 FROM public.inventory inv WHERE inv.owner_user_id = v_u1;
    IF v_inv1 IS NULL THEN
        INSERT INTO public.inventory (owner_user_id) VALUES (v_u1) RETURNING id INTO v_inv1;
    END IF;

    -- Fixtures pelas RPCs CANONICAS: mais fidelidade ao caminho real.
    SELECT s.id INTO v_sc1 FROM public.create_storage_container('BULK03 HARNESS SC1') s;

    SELECT c.id INTO v_col_open
      FROM public.create_collection(v_game, 'BULK03 HARNESS OPEN', NULL, v_sc1) c;

    SELECT c.id INTO v_col_arch
      FROM public.create_collection(v_game, 'BULK03 HARNESS ARCH', NULL, v_sc1) c;

    SELECT c.id INTO v_col_ref
      FROM public.create_reference_based_card_set_collection(
               v_game, 'BULK03 HARNESS REF', NULL, v_sc1, v_set1) c;

    PERFORM public.archive_collection(v_col_arch);

    -- ---- usuario 2 (recursos ALHEIOS, para nao-enumeracao) ---------
    PERFORM pg_temp._as(v_u2);

    IF NOT EXISTS (SELECT 1 FROM public.inventory inv WHERE inv.owner_user_id = v_u2) THEN
        INSERT INTO public.inventory (owner_user_id) VALUES (v_u2);
    END IF;

    SELECT s.id INTO v_sc2 FROM public.create_storage_container('BULK03 HARNESS SC2-ALHEIO') s;

    SELECT c.id INTO v_col_alheia
      FROM public.create_collection(v_game, 'BULK03 HARNESS ALHEIA', NULL, v_sc2) c;

    PERFORM pg_temp._as(v_u1);

    INSERT INTO _fx (k, v) VALUES
        ('u1', v_u1), ('u2', v_u2),
        ('cv1', v_cv1), ('cv2', v_cv2), ('cv_other', v_cv_other),
        ('lang', v_lang), ('game', v_game), ('set1', v_set1),
        ('inv1', v_inv1), ('sc1', v_sc1), ('sc2', v_sc2),
        ('col_open', v_col_open), ('col_ref', v_col_ref),
        ('col_arch', v_col_arch), ('col_alheia', v_col_alheia);

    PERFORM pg_temp._rec('F','F02 - fixtures de dominio criadas pelas RPCs canonicas (2 storage, 4 collections sendo 1 arquivada e 1 alheia)',
        (SELECT count(*) FROM _fx) = 15,
        (SELECT count(*)::text FROM _fx), '15 chaves de fixture');
END;
$F$;

-- ----------------------------------------------------------------
-- F03 — GAME SINTETICO para a prova de GAME_MISMATCH.
--
-- Por que um Game sintetico, e nao um segundo Game real: provar
-- GAME_MISMATCH exige uma Collection cujo Game seja DIFERENTE do Game
-- da Card Variant. A Card Variant continua sendo REAL (do Game
-- Pokemon); o que e sintetico e apenas o Game da Collection. Nenhum
-- catalogo sintetico (Card Set, Card, Card Variant) e criado — foi
-- exatamente o obstaculo enfrentado no Caso K de `5808`.
--
-- CODIGO UNICO POR EXECUCAO (`-GATE-A-REVISION-02`):
-- `public.game.code` tem `uq_game_code`. Um literal fixo faria a
-- SEGUNDA execucao do harness colidir com um residuo da primeira que
-- porventura tivesse sobrevivido — um harness que so roda uma vez nao
-- e um harness. O codigo e portanto
-- `ZZTEST_BULK03_<32 hex maiusculos>`: 14 + 32 = 46 chars (limite 50),
-- so `[A-Z0-9_]` apos a inicial, satisfazendo `ck_game_code_format`
-- (^[A-Z][A-Z0-9_]*$). O prefixo `ZZ` mantem a linha visivel e no fim
-- de qualquer ordenacao por `code`.
--
-- STORAGE PADRAO OBRIGATORIO (`-GATE-A-REVISION-02`):
-- `create_collection()` (`5034`) valida
-- `p_default_storage_container_id` com um `NOT EXISTS` INCONDICIONAL:
-- com NULL, `sc.id = NULL` nunca e verdadeiro, o NOT EXISTS dispara e
-- a RPC aborta com 'default_storage_container_id does not belong to
-- caller inventory'. A versao anterior desta fixture passava NULL e
-- teria abortado o harness ANTES do gate. Passamos `sc1`, o Storage
-- de `u1` ja criado em `F02`.
--
-- Isso NAO afeta o que `I10` prova: o GAME_MISMATCH continua sendo
-- entre a Collection no Game sintetico e a Card Variant real do Game
-- Pokemon. O Storage nao entra no calculo de Game.
--
-- A linha de `public.game` e revertida pelo ROLLBACK do harness e
-- coberta pelo baseline da nona tabela.
-- ----------------------------------------------------------------
DO $F3$
DECLARE v_game_zz UUID; v_col_zz UUID; v_u1 UUID; v_code TEXT;
BEGIN
    v_u1 := pg_temp._fx('u1');

    v_code := 'ZZTEST_BULK03_' ||
              upper(replace(gen_random_uuid()::text, '-', ''));

    INSERT INTO public.game (code, name)
    VALUES (v_code, 'BULK03 HARNESS GAME SINTETICO')
    RETURNING id INTO v_game_zz;

    PERFORM pg_temp._as(v_u1);

    -- `sc1` — Storage de u1, exigido por 5034. Ver nota acima.
    SELECT c.id INTO v_col_zz
      FROM public.create_collection(
               v_game_zz, 'BULK03 HARNESS COL ZZTEST', NULL,
               pg_temp._fx('sc1')) c;

    INSERT INTO _fx (k, v) VALUES ('game_zz', v_game_zz), ('col_zz', v_col_zz);

    PERFORM pg_temp._rec('F','F03 - Game sintetico ZZTEST_BULK03_<unico> e Collection de u1 nesse Game (com o Storage sc1, exigido por 5034) criados DENTRO da transacao, sem catalogo sintetico',
        v_game_zz IS NOT NULL AND v_col_zz IS NOT NULL
        AND v_game_zz IS DISTINCT FROM pg_temp._fx('game')
        AND length(v_code) <= 50 AND v_code ~ '^[A-Z][A-Z0-9_]*$',
        format('code=%s len=%s formato_ok=%s col_zz=%s distinto_do_game_real=%s',
               v_code, length(v_code), v_code ~ '^[A-Z][A-Z0-9_]*$',
               v_col_zz IS NOT NULL,
               v_game_zz IS DISTINCT FROM pg_temp._fx('game')),
        'code unico <=50 no formato canonico, Collection criada, Game distinto do real');
END;
$F3$;

-- ================================================================
-- GRUPO E — ESTRUTURA ESTÁTICA
-- ================================================================
DO $E$
DECLARE
    pr RECORD;
    v_src TEXT;
BEGIN
    SELECT p.oid, p.prosecdef, p.provolatile, p.proname, p.prorettype,
           pg_get_userbyid(p.proowner) AS owner, p.prosrc
      INTO pr
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'preview_bulk_operation';

    PERFORM pg_temp._rec('E','E01 - 5151 existe em public',
        pr.oid IS NOT NULL, coalesce(pr.proname,'<ausente>'), 'preview_bulk_operation');

    PERFORM pg_temp._rec('E','E02 - 5151 e SECURITY DEFINER (obrigatorio: 5149 le catalogo fechado por RLS; INVOKER quebraria 100% das execucoes com PREVIEW_STALE)',
        pr.prosecdef IS TRUE, pr.prosecdef::text, 'true');

    PERFORM pg_temp._rec('E','E03 - 5151 e VOLATILE (leitura do mundo AGORA, nao cacheavel na query chamadora)',
        pr.provolatile = 'v', pr.provolatile, 'v');

    PERFORM pg_temp._rec('E','E04 - 5151 tem search_path EFETIVAMENTE vazio',
        pg_temp._empty_search_path(pr.oid), 'ver proconfig', 'search_path vazio');

    PERFORM pg_temp._rec('E','E05 - 5151 tem owner postgres',
        pr.owner = 'postgres', pr.owner, 'postgres');

    -- CORRIGIDO na v2.2 (`-GATE-A-HARNESS-CORRECTION-01`). A v2.1
    -- exigia `pg_get_function_identity_arguments(...) = 'jsonb'` e
    -- FALHOU: essa funcao devolve os NOMES dos parametros junto com os
    -- tipos quando eles tem nome, ou seja `p_request jsonb`. Defeito da
    -- expectativa, nunca do produto — o postcheck estrutural externo
    -- media 1 sobrecarga / `p_request jsonb` / `jsonb` na mesma rodada.
    --
    -- O idioma correto ja existia no repositorio: e literalmente o que
    -- o `E06` do `5822` (BULK-02) faz. Registro honesto: nao foi
    -- reaproveitado na primeira escrita deste harness.
    PERFORM pg_temp._rec('E','E06 - ASSINATURA CONGELADA: exatamente uma sobrecarga, p_request jsonb -> jsonb',
        (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname='public' AND p.proname='preview_bulk_operation') = 1
        AND pg_get_function_identity_arguments(pr.oid) = 'p_request jsonb'
        AND format_type(pr.prorettype, NULL) = 'jsonb',
        format('args=%s ret=%s sobrecargas=%s',
               pg_get_function_identity_arguments(pr.oid),
               format_type(pr.prorettype, NULL),
               (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                 WHERE n.nspname='public' AND p.proname='preview_bulk_operation')),
        'args=p_request jsonb / ret=jsonb / 1 sobrecarga');

    -- Prova estatica de que Preview nao escreve, nao trava e nao faz
    -- claim. CORRIGIDO na v2.0: a versao anterior anunciava `UPDATE`
    -- no rotulo e NAO o verificava no predicado — rotulo e assercao
    -- divergentes, que e a forma mais silenciosa de teste inutil.
    -- Defeito do harness, nunca do produto.
    --
    -- Substring simples basta e e verificavel: o corpo real de `5151`
    -- nao contem NENHUMA das nove agulhas. Em particular `trunc(`, do
    -- guard de `quantity`, NAO contem `truncate`.
    v_src := lower(pr.prosrc);
    PERFORM pg_temp._rec('E','E07 - corpo de 5151 nao contem NENHUMA DML (INSERT/UPDATE/DELETE/MERGE/TRUNCATE), nem FOR UPDATE, nem bulk_lock_operation_scope/claim_bulk_operation/complete_bulk_operation',
        position('insert'                    in v_src) = 0
        AND position('update'                in v_src) = 0
        AND position('delete'                in v_src) = 0
        AND position('merge'                 in v_src) = 0
        AND position('truncate'              in v_src) = 0
        AND position('for update'            in v_src) = 0
        AND position('bulk_lock_operation_scope' in v_src) = 0
        AND position('claim_bulk_operation'  in v_src) = 0
        AND position('complete_bulk_operation' in v_src) = 0,
        format('insert=%s update=%s delete=%s merge=%s truncate=%s for_update=%s lock_scope=%s claim=%s complete=%s',
               position('insert' in v_src), position('update' in v_src),
               position('delete' in v_src), position('merge' in v_src),
               position('truncate' in v_src), position('for update' in v_src),
               position('bulk_lock_operation_scope' in v_src),
               position('claim_bulk_operation' in v_src),
               position('complete_bulk_operation' in v_src)),
        'todas as nove posicoes = 0');
END;
$E$;

-- ================================================================
-- GRUPO S — ACL NOS QUATRO PAPÉIS
-- ================================================================
DO $S$
DECLARE v_oid OID; v_acl ACLITEM[];
BEGIN
    SELECT p.oid, p.proacl INTO v_oid, v_acl
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname='preview_bulk_operation';

    PERFORM pg_temp._rec('S','S01 - authenticated TEM EXECUTE em 5151',
        has_function_privilege('authenticated', v_oid, 'EXECUTE'),
        has_function_privilege('authenticated', v_oid, 'EXECUTE')::text, 'true');

    PERFORM pg_temp._rec('S','S02 - anon NAO tem EXECUTE em 5151',
        NOT has_function_privilege('anon', v_oid, 'EXECUTE'),
        has_function_privilege('anon', v_oid, 'EXECUTE')::text, 'false');

    PERFORM pg_temp._rec('S','S03 - service_role NAO tem EXECUTE em 5151',
        NOT has_function_privilege('service_role', v_oid, 'EXECUTE'),
        has_function_privilege('service_role', v_oid, 'EXECUTE')::text, 'false');

    -- proacl NULL significa PRIVILEGIOS PADRAO = EXECUTE TO PUBLIC.
    -- NULL e o caso RUIM. has_function_privilege('public', ...) nao
    -- funciona: PUBLIC nao e um papel de pg_roles.
    PERFORM pg_temp._rec('S','S04 - PUBLIC NAO tem EXECUTE em 5151 (proacl NOT NULL e sem grantee=0 em aclexplode)',
        v_acl IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM aclexplode(v_acl) a WHERE a.grantee = 0),
        format('proacl_null=%s public_grants=%s', v_acl IS NULL,
               (SELECT count(*) FROM aclexplode(COALESCE(v_acl, ARRAY[]::aclitem[])) a WHERE a.grantee = 0)),
        'proacl NOT NULL e zero grants para PUBLIC');
END;
$S$;

-- ================================================================
-- GRUPO V — VOCABULÁRIO DE operation_type (as TRÊS situações)
-- ================================================================
DO $V$
DECLARE v_items JSONB; v_cv TEXT; v_lang TEXT;
BEGIN
    v_cv   := pg_temp._fx('cv1')::text;
    v_lang := pg_temp._fx('lang')::text;
    v_items := jsonb_build_array(pg_temp._it(v_cv, v_lang, 1));
    PERFORM pg_temp._as(pg_temp._fx('u1'));

    PERFORM pg_temp._expect_error('V','V01 - operation_type FORA do vocabulario e recusado como INVALIDO',
        format('SELECT public.preview_bulk_operation(%L::jsonb)',
               pg_temp._preq('REGISTER_UNICORNS', v_items)),
        'operation_type invalido');

    -- A distincao entre V01 e V02 e o ponto: REGISTER_CARD_SET e um
    -- valor LEGITIMO do dominio (esta no CHECK de 5142). Chama-lo de
    -- "invalido" mandaria o desenvolvedor cacar o bug no lugar errado.
    PERFORM pg_temp._expect_error('V','V02 - REGISTER_CARD_SET e reconhecido como do vocabulario porem NAO SUPORTADO nesta versao (mensagem propria, NAO "invalido")',
        format('SELECT public.preview_bulk_operation(%L::jsonb)',
               pg_temp._preq('REGISTER_CARD_SET', v_items)),
        'ainda nao e suportado pelo Preview nesta versao');

    PERFORM pg_temp._rec('V','V03 - REGISTER_PHYSICAL_CARDS e aceito e produz ok=true',
        (public.preview_bulk_operation(pg_temp._preq('REGISTER_PHYSICAL_CARDS', v_items)) ->> 'ok')::boolean,
        (public.preview_bulk_operation(pg_temp._preq('REGISTER_PHYSICAL_CARDS', v_items)) ->> 'ok'),
        'true');
END;
$V$;

-- ================================================================
-- GRUPO G — GUARDS ESTRUTURAIS -> EXCEÇÃO (bug de cliente)
-- ================================================================
DO $G$
DECLARE v_cv TEXT; v_lang TEXT; v_items JSONB;
BEGIN
    v_cv   := pg_temp._fx('cv1')::text;
    v_lang := pg_temp._fx('lang')::text;
    v_items := jsonb_build_array(pg_temp._it(v_cv, v_lang, 1));
    PERFORM pg_temp._as(pg_temp._fx('u1'));

    PERFORM pg_temp._expect_error('G','G01 - p_request nao-objeto e recusado',
        'SELECT public.preview_bulk_operation(''[]''::jsonb)',
        'p_request deve ser um objeto JSON');

    PERFORM pg_temp._expect_error('G','G02 - chave desconhecida no envelope e recusada (contrato FECHADO)',
        format('SELECT public.preview_bulk_operation(%L::jsonb)',
               pg_temp._preq('REGISTER_PHYSICAL_CARDS', v_items) || '{"surpresa": 1}'::jsonb),
        'p_request aceita exatamente as chaves');

    -- idempotency_key NAO pertence ao envelope do Preview: e a
    -- assimetria deliberada com 5150.
    PERFORM pg_temp._expect_error('G','G03 - idempotency_key e recusada no envelope do Preview (assimetria deliberada com 5150)',
        format('SELECT public.preview_bulk_operation(%L::jsonb)',
               pg_temp._preq('REGISTER_PHYSICAL_CARDS', v_items)
               || jsonb_build_object('idempotency_key', gen_random_uuid()::text)),
        'p_request aceita exatamente as chaves');

    PERFORM pg_temp._expect_error('G','G04 - envelope sem items e recusado',
        'SELECT public.preview_bulk_operation(''{"operation_type":"REGISTER_PHYSICAL_CARDS"}''::jsonb)',
        'p_request exige operation_type e items');

    PERFORM pg_temp._expect_error('G','G05 - items vazio e recusado',
        format('SELECT public.preview_bulk_operation(%L::jsonb)',
               pg_temp._preq('REGISTER_PHYSICAL_CARDS', '[]'::jsonb)),
        'items nao pode ser vazio');

    PERFORM pg_temp._expect_error('G','G06 - chave desconhecida DENTRO de um item e recusada',
        format('SELECT public.preview_bulk_operation(%L::jsonb)',
               pg_temp._preq('REGISTER_PHYSICAL_CARDS',
                   jsonb_build_array(pg_temp._it(v_cv, v_lang, 1) || '{"extra": true}'::jsonb))),
        'cada item de items aceita exatamente as chaves');

    PERFORM pg_temp._expect_error('G','G07 - UUID sintaticamente invalido aborta com a LISTA dos ofensores',
        format('SELECT public.preview_bulk_operation(%L::jsonb)',
               pg_temp._preq('REGISTER_PHYSICAL_CARDS',
                   jsonb_build_array(pg_temp._it('nao-e-uuid', v_lang, 1)))),
        'identificador(es) invalido(s)');

    PERFORM pg_temp._expect_error('G','G08 - quantity fracionaria e recusada',
        format('SELECT public.preview_bulk_operation(%L::jsonb)',
               pg_temp._preq('REGISTER_PHYSICAL_CARDS',
                   jsonb_build_array(pg_temp._it(v_cv, v_lang, 2.5)))),
        'quantity deve ser um inteiro maior ou igual a 1');

    PERFORM pg_temp._expect_error('G','G09 - quantity zero e recusada',
        format('SELECT public.preview_bulk_operation(%L::jsonb)',
               pg_temp._preq('REGISTER_PHYSICAL_CARDS',
                   jsonb_build_array(pg_temp._it(v_cv, v_lang, 0)))),
        'quantity deve ser um inteiro maior ou igual a 1');

    -- G10 — SEM autenticacao. SQLSTATE proprio (28000), distinto dos
    -- 22023 estruturais: falta de identidade nao e payload invalido.
    -- Claims sem `sub` -> auth.uid() NULL. Restaurado logo depois.
    PERFORM pg_temp._anon();

    PERFORM pg_temp._expect_error('G','G10 - sem auth.uid() a chamada e recusada com SQLSTATE 28000 (nao 22023): falta de identidade nao e payload invalido',
        format('SELECT public.preview_bulk_operation(%L::jsonb)',
               pg_temp._preq('REGISTER_PHYSICAL_CARDS', v_items)),
        'authentication required', '28000');

    PERFORM pg_temp._as(pg_temp._fx('u1'));
END;
$G$;

-- ================================================================
-- GRUPO T — TETO 1000 / 1001
--
-- Equivalencia com o teto de `5150` provada COMPORTAMENTALMENTE, do
-- lado do Preview (T01-T04) e do lado da execucao (ja provado em
-- `5822`, grupos `P` e `A`). NAO se parseia o source de `5150` para
-- comparar a constante: o que importa e que os dois se comportem
-- igual na fronteira, nao que o literal apareca duas vezes.
-- ================================================================
DO $T$
DECLARE
    v_cv TEXT; v_lang TEXT; v_res JSONB;
    v_1000 JSONB; v_1001 JSONB;
BEGIN
    v_cv   := pg_temp._fx('cv1')::text;
    v_lang := pg_temp._fx('lang')::text;
    PERFORM pg_temp._as(pg_temp._fx('u1'));

    -- 1000 itens BRUTOS distintos exigiriam 1000 card_variants reais.
    -- Em vez disso, o teto BRUTO e exercitado com UUIDs sinteticos
    -- distintos: o guard de cardinalidade e ANTERIOR a qualquer
    -- resolucao de catalogo, entao a existencia nao importa aqui.
    SELECT jsonb_agg(pg_temp._it(
               ('00000000-0000-4000-8000-' || lpad(g::text, 12, '0')), v_lang, 1))
      INTO v_1000
      FROM generate_series(1, 1000) g;

    SELECT jsonb_agg(pg_temp._it(
               ('00000000-0000-4000-8000-' || lpad(g::text, 12, '0')), v_lang, 1))
      INTO v_1001
      FROM generate_series(1, 1001) g;

    -- 1000 BRUTOS passa o guard de cardinalidade. Ele para depois, em
    -- issues (card_variant inexistente) — que e exatamente a prova de
    -- que o teto NAO foi o motivo da recusa.
    v_res := public.preview_bulk_operation(
                 pg_temp._preq('REGISTER_PHYSICAL_CARDS', v_1000));

    PERFORM pg_temp._rec('T','T01 - 1000 itens BRUTOS passam o guard de cardinalidade (recusa vem de issues, nao do teto)',
        (v_res ->> 'ok')::boolean IS FALSE
        AND pg_temp._has_issue(v_res, 'CARD_VARIANT_NOT_FOUND'),
        format('ok=%s issues=%s', v_res ->> 'ok',
               (SELECT string_agg(i.e ->> 'code', ',') FROM jsonb_array_elements(v_res->'issues') i(e))),
        'ok=false por CARD_VARIANT_NOT_FOUND, nunca por teto');

    PERFORM pg_temp._expect_error('T','T02 - 1001 itens BRUTOS sao rejeitados pelo teto, com excecao',
        format('SELECT public.preview_bulk_operation(%L::jsonb)',
               pg_temp._preq('REGISTER_PHYSICAL_CARDS', v_1001)),
        'items excede o limite de 1000 itens por chamada');

    -- Teto EXPANDIDO: 1 item com quantity 1000 -> aceito;
    -- 2 itens somando 1001 -> recusado.
    v_res := public.preview_bulk_operation(
                 pg_temp._preq('REGISTER_PHYSICAL_CARDS',
                     jsonb_build_array(pg_temp._it(v_cv, v_lang, 1000))));

    PERFORM pg_temp._rec('T','T03 - total EXPANDIDO de exatamente 1000 e aceito (ok=true, will_create_count=1000)',
        (v_res ->> 'ok')::boolean IS TRUE
        AND (v_res -> 'summary' ->> 'will_create_count')::int = 1000,
        format('ok=%s will_create=%s', v_res ->> 'ok',
               v_res -> 'summary' ->> 'will_create_count'),
        'ok=true e will_create_count=1000');

    PERFORM pg_temp._expect_error('T','T04 - total EXPANDIDO de 1001 e rejeitado pelo teto (1000 + 1 em itens distintos)',
        format('SELECT public.preview_bulk_operation(%L::jsonb)',
               pg_temp._preq('REGISTER_PHYSICAL_CARDS',
                   jsonb_build_array(pg_temp._it(v_cv, v_lang, 1000),
                                     pg_temp._it(pg_temp._fx('cv2')::text, v_lang, 1)))),
        'excede o limite de 1000');
END;
$T$;

-- ================================================================
-- GRUPO K — CONTRATO ok=true
-- ================================================================
DO $K$
DECLARE v_res JSONB; v_items JSONB; v_cv TEXT; v_lang TEXT;
BEGIN
    v_cv   := pg_temp._fx('cv1')::text;
    v_lang := pg_temp._fx('lang')::text;
    v_items := jsonb_build_array(pg_temp._it(v_cv, v_lang, 3),
                                 pg_temp._it(pg_temp._fx('cv2')::text, v_lang, 2));
    PERFORM pg_temp._as(pg_temp._fx('u1'));

    v_res := public.preview_bulk_operation(
                 pg_temp._preq('REGISTER_PHYSICAL_CARDS', v_items,
                               pg_temp._fx('col_open'), pg_temp._fx('sc1')));

    PERFORM pg_temp._rec('K','K01 - ok=true traz preview_fingerprint NOT NULL e nao-branco',
        (v_res ->> 'ok')::boolean IS TRUE
        AND v_res ->> 'preview_fingerprint' IS NOT NULL
        AND btrim(v_res ->> 'preview_fingerprint') <> '',
        format('ok=%s fp_len=%s', v_res ->> 'ok',
               coalesce(length(v_res ->> 'preview_fingerprint')::text, 'NULL')),
        'ok=true e fingerprint preenchido');

    PERFORM pg_temp._rec('K','K02 - ok=true traz issues EXATAMENTE vazio',
        jsonb_array_length(v_res -> 'issues') = 0,
        jsonb_array_length(v_res -> 'issues')::text, '0');

    PERFORM pg_temp._rec('K','K03 - summary reflete o payload: 2 distintos, 5 expandidos, 5 a alocar (ha Collection)',
        (v_res -> 'summary' ->> 'distinct_items')::int = 2
        AND (v_res -> 'summary' ->> 'total_quantity')::int = 5
        AND (v_res -> 'summary' ->> 'will_create_count')::int = 5
        AND (v_res -> 'summary' ->> 'will_allocate_count')::int = 5,
        v_res -> 'summary' #>> '{}', 'distinct=2 total=5 create=5 allocate=5');

    -- Sem Collection, nada e alocado — e o summary tem de dizer isso.
    v_res := public.preview_bulk_operation(
                 pg_temp._preq('REGISTER_PHYSICAL_CARDS', v_items));

    PERFORM pg_temp._rec('K','K04 - sem collection_id, will_allocate_count = 0 e ok continua true',
        (v_res ->> 'ok')::boolean IS TRUE
        AND (v_res -> 'summary' ->> 'will_allocate_count')::int = 0
        AND (v_res -> 'summary' ->> 'will_create_count')::int = 5,
        format('ok=%s allocate=%s create=%s', v_res ->> 'ok',
               v_res -> 'summary' ->> 'will_allocate_count',
               v_res -> 'summary' ->> 'will_create_count'),
        'ok=true allocate=0 create=5');
END;
$K$;

-- ================================================================
-- GRUPO I — CONTRATO ok=false, UM CASO POR CODE
--
-- Em TODOS: preview_fingerprint tem de ser JSON null. Um Preview
-- reprovado nao pode entregar token utilizavel ao cliente.
-- ================================================================
DO $I$
DECLARE
    v_res JSONB; v_cv TEXT; v_cv2 TEXT; v_lang TEXT; v_other TEXT;
    v_ghost CONSTANT TEXT := '00000000-0000-4000-8000-0000000000ff';
BEGIN
    v_cv    := pg_temp._fx('cv1')::text;
    v_cv2   := pg_temp._fx('cv2')::text;
    v_other := pg_temp._fx('cv_other')::text;
    v_lang  := pg_temp._fx('lang')::text;
    PERFORM pg_temp._as(pg_temp._fx('u1'));

    -- I01/I02 — duplicidade SEMANTICA. A caixa ALTA no segundo item e
    -- o ponto: comparacao textual crua deixaria passar.
    v_res := public.preview_bulk_operation(
                 pg_temp._preq('REGISTER_PHYSICAL_CARDS',
                     jsonb_build_array(pg_temp._it(v_cv, v_lang, 1),
                                       pg_temp._it(upper(v_cv), upper(v_lang), 1))));

    PERFORM pg_temp._rec('I','I01 - duplicidade SEMANTICA (mesmo par em CAIXA ALTA) vira issue DUPLICATE_ITEM',
        (v_res ->> 'ok')::boolean IS FALSE AND pg_temp._has_issue(v_res, 'DUPLICATE_ITEM'),
        format('ok=%s codes=%s', v_res ->> 'ok',
               (SELECT string_agg(i.e ->> 'code', ',') FROM jsonb_array_elements(v_res->'issues') i(e))),
        'ok=false com DUPLICATE_ITEM');

    PERFORM pg_temp._rec('I','I02 - com ok=false, preview_fingerprint e JSON null (token de Preview reprovado NUNCA chega ao cliente)',
        jsonb_typeof(v_res -> 'preview_fingerprint') = 'null',
        jsonb_typeof(v_res -> 'preview_fingerprint'), 'null');

    -- I03 — card_variant inexistente, com LISTA.
    v_res := public.preview_bulk_operation(
                 pg_temp._preq('REGISTER_PHYSICAL_CARDS',
                     jsonb_build_array(pg_temp._it(v_ghost, v_lang, 1))));

    PERFORM pg_temp._rec('I','I03 - card_variant_id inexistente vira CARD_VARIANT_NOT_FOUND com o id em offenders, e fingerprint null',
        (v_res ->> 'ok')::boolean IS FALSE
        AND pg_temp._has_issue(v_res, 'CARD_VARIANT_NOT_FOUND')
        AND jsonb_typeof(v_res -> 'preview_fingerprint') = 'null'
        AND EXISTS (SELECT 1 FROM jsonb_array_elements(v_res->'issues') i(e)
                     WHERE i.e ->> 'code' = 'CARD_VARIANT_NOT_FOUND'
                       AND i.e -> 'offenders' @> to_jsonb(v_ghost)),
        v_res -> 'issues' #>> '{}', 'CARD_VARIANT_NOT_FOUND com offender e fp null');

    -- I04 — language inexistente.
    v_res := public.preview_bulk_operation(
                 pg_temp._preq('REGISTER_PHYSICAL_CARDS',
                     jsonb_build_array(pg_temp._it(v_cv, v_ghost, 1))));

    PERFORM pg_temp._rec('I','I04 - language_id inexistente vira LANGUAGE_NOT_FOUND com fingerprint null',
        (v_res ->> 'ok')::boolean IS FALSE
        AND pg_temp._has_issue(v_res, 'LANGUAGE_NOT_FOUND')
        AND jsonb_typeof(v_res -> 'preview_fingerprint') = 'null',
        format('ok=%s fp=%s', v_res ->> 'ok', jsonb_typeof(v_res -> 'preview_fingerprint')),
        'LANGUAGE_NOT_FOUND e fp null');

    -- I05 — Collection ARQUIVADA.
    v_res := public.preview_bulk_operation(
                 pg_temp._preq('REGISTER_PHYSICAL_CARDS',
                     jsonb_build_array(pg_temp._it(v_cv, v_lang, 1)),
                     pg_temp._fx('col_arch')));

    PERFORM pg_temp._rec('I','I05 - Collection ARCHIVED vira COLLECTION_ARCHIVED com fingerprint null',
        (v_res ->> 'ok')::boolean IS FALSE
        AND pg_temp._has_issue(v_res, 'COLLECTION_ARCHIVED')
        AND jsonb_typeof(v_res -> 'preview_fingerprint') = 'null',
        format('ok=%s codes=%s', v_res ->> 'ok',
               (SELECT string_agg(i.e ->> 'code', ',') FROM jsonb_array_elements(v_res->'issues') i(e))),
        'COLLECTION_ARCHIVED e fp null');

    -- I06 — elegibilidade de Reference: carta de OUTRO Card Set.
    v_res := public.preview_bulk_operation(
                 pg_temp._preq('REGISTER_PHYSICAL_CARDS',
                     jsonb_build_array(pg_temp._it(v_other, v_lang, 1)),
                     pg_temp._fx('col_ref')));

    PERFORM pg_temp._rec('I','I06 - carta fora do Card Set referenciado vira NOT_ELIGIBLE_FOR_REFERENCE com fingerprint null',
        (v_res ->> 'ok')::boolean IS FALSE
        AND pg_temp._has_issue(v_res, 'NOT_ELIGIBLE_FOR_REFERENCE')
        AND jsonb_typeof(v_res -> 'preview_fingerprint') = 'null',
        format('ok=%s codes=%s', v_res ->> 'ok',
               (SELECT string_agg(i.e ->> 'code', ',') FROM jsonb_array_elements(v_res->'issues') i(e))),
        'NOT_ELIGIBLE_FOR_REFERENCE e fp null');

    -- I07 — Storage de terceiro.
    v_res := public.preview_bulk_operation(
                 pg_temp._preq('REGISTER_PHYSICAL_CARDS',
                     jsonb_build_array(pg_temp._it(v_cv, v_lang, 1)),
                     NULL, pg_temp._fx('sc2')));

    PERFORM pg_temp._rec('I','I07 - Storage Container alheio vira STORAGE_NOT_ACCESSIBLE com fingerprint null',
        (v_res ->> 'ok')::boolean IS FALSE
        AND pg_temp._has_issue(v_res, 'STORAGE_NOT_ACCESSIBLE')
        AND jsonb_typeof(v_res -> 'preview_fingerprint') = 'null',
        format('ok=%s codes=%s', v_res ->> 'ok',
               (SELECT string_agg(i.e ->> 'code', ',') FROM jsonb_array_elements(v_res->'issues') i(e))),
        'STORAGE_NOT_ACCESSIBLE e fp null');

    -- I08 — Preview reporta TODOS os impedimentos de uma vez. Esta e
    -- a razao de ser de issues[]: quem tem 300 cartas nao pode
    -- descobrir um erro por round-trip.
    v_res := public.preview_bulk_operation(
                 pg_temp._preq('REGISTER_PHYSICAL_CARDS',
                     jsonb_build_array(pg_temp._it(v_ghost, v_lang, 1),
                                       pg_temp._it(v_cv,    v_ghost, 1)),
                     pg_temp._fx('col_arch')));

    PERFORM pg_temp._rec('I','I08 - MULTIPLOS impedimentos voltam JUNTOS numa unica chamada (>= 3 codes distintos), nao um por vez',
        (v_res ->> 'ok')::boolean IS FALSE
        AND pg_temp._has_issue(v_res, 'CARD_VARIANT_NOT_FOUND')
        AND pg_temp._has_issue(v_res, 'LANGUAGE_NOT_FOUND')
        AND pg_temp._has_issue(v_res, 'COLLECTION_ARCHIVED')
        AND jsonb_array_length(v_res -> 'issues') >= 3,
        format('n=%s codes=%s', jsonb_array_length(v_res -> 'issues'),
               (SELECT string_agg(i.e ->> 'code', ',') FROM jsonb_array_elements(v_res->'issues') i(e))),
        '>=3 issues, incluindo os tres codes');

    -- I09 — summary continua util mesmo reprovado.
    PERFORM pg_temp._rec('I','I09 - com ok=false o summary AINDA e devolvido (usuario precisa ver a dimensao do que tentou)',
        v_res -> 'summary' IS NOT NULL
        AND (v_res -> 'summary' ->> 'distinct_items')::int = 2,
        coalesce(v_res -> 'summary' #>> '{}', 'NULL'), 'summary presente com distinct_items=2');

    -- I10 — GAME_MISMATCH. Card Variant REAL do Game Pokemon contra a
    -- Collection do Game sintetico ZZTEST_BULK03_<unico> (fixture F03). Nenhum outro
    -- impedimento deve aparecer: a carta existe, o idioma existe, a
    -- Collection e do chamador, esta ACTIVE e nao e REFERENCE_BASED.
    v_res := public.preview_bulk_operation(
                 pg_temp._preq('REGISTER_PHYSICAL_CARDS',
                     jsonb_build_array(pg_temp._it(v_cv, v_lang, 1)),
                     pg_temp._fx('col_zz')));

    PERFORM pg_temp._rec('I','I10 - Card Variant de Game diferente do Game da Collection vira GAME_MISMATCH, com o id em offenders e fingerprint null',
        (v_res ->> 'ok')::boolean IS FALSE
        AND pg_temp._has_issue(v_res, 'GAME_MISMATCH')
        AND jsonb_typeof(v_res -> 'preview_fingerprint') = 'null'
        AND EXISTS (SELECT 1 FROM jsonb_array_elements(v_res->'issues') i(e)
                     WHERE i.e ->> 'code' = 'GAME_MISMATCH'
                       AND i.e -> 'offenders' @> to_jsonb(v_cv)),
        format('ok=%s fp=%s codes=%s', v_res ->> 'ok',
               jsonb_typeof(v_res -> 'preview_fingerprint'),
               (SELECT string_agg(i.e ->> 'code', ',') FROM jsonb_array_elements(v_res->'issues') i(e))),
        'GAME_MISMATCH com offender e fp null');

    -- I11 — INVENTORY_NOT_FOUND. `sub` sintetico que nao possui
    -- Inventory. NENHUM auth.users e criado ou apagado: o guard de
    -- 5151 depende so de auth.uid(), nao da existencia do usuario.
    PERFORM pg_temp._as('00000000-0000-4000-8000-00000000dead'::uuid);

    v_res := public.preview_bulk_operation(
                 pg_temp._preq('REGISTER_PHYSICAL_CARDS',
                     jsonb_build_array(pg_temp._it(v_cv, v_lang, 1))));

    PERFORM pg_temp._as(pg_temp._fx('u1'));

    PERFORM pg_temp._rec('I','I11 - chamador sem Inventory vira INVENTORY_NOT_FOUND com fingerprint null (sem criar nem apagar auth.users)',
        (v_res ->> 'ok')::boolean IS FALSE
        AND pg_temp._has_issue(v_res, 'INVENTORY_NOT_FOUND')
        AND jsonb_typeof(v_res -> 'preview_fingerprint') = 'null',
        format('ok=%s fp=%s codes=%s', v_res ->> 'ok',
               jsonb_typeof(v_res -> 'preview_fingerprint'),
               (SELECT string_agg(i.e ->> 'code', ',') FROM jsonb_array_elements(v_res->'issues') i(e))),
        'INVENTORY_NOT_FOUND e fp null');
END;
$I$;

-- ================================================================
-- GRUPO N — NÃO-ENUMERAÇÃO
--
-- Risco NOVO introduzido por issues[]: resposta estruturada e mais
-- informativa que excecao generica. Se "nao existe" e "e de terceiro"
-- produzissem sinais diferentes, o Preview viraria oraculo de
-- enumeracao — regressao em relacao ao que 5148/5149/5150 protegem.
-- ================================================================
DO $N$
DECLARE
    v_a JSONB; v_b JSONB; v_items JSONB;
    v_ghost CONSTANT UUID := '00000000-0000-4000-8000-0000000000fe';
    fa TEXT; fb TEXT;
BEGIN
    v_items := jsonb_build_array(
                   pg_temp._it(pg_temp._fx('cv1')::text, pg_temp._fx('lang')::text, 1));
    PERFORM pg_temp._as(pg_temp._fx('u1'));

    -- A: Collection INEXISTENTE.  B: Collection de TERCEIRO.
    v_a := public.preview_bulk_operation(
               pg_temp._preq('REGISTER_PHYSICAL_CARDS', v_items, v_ghost));
    v_b := public.preview_bulk_operation(
               pg_temp._preq('REGISTER_PHYSICAL_CARDS', v_items, pg_temp._fx('col_alheia')));

    SELECT i.e ->> 'message' INTO fa
      FROM jsonb_array_elements(v_a -> 'issues') i(e)
     WHERE i.e ->> 'code' = 'COLLECTION_NOT_ACCESSIBLE';
    SELECT i.e ->> 'message' INTO fb
      FROM jsonb_array_elements(v_b -> 'issues') i(e)
     WHERE i.e ->> 'code' = 'COLLECTION_NOT_ACCESSIBLE';

    PERFORM pg_temp._rec('N','N01 - Collection INEXISTENTE e Collection de TERCEIRO produzem o MESMO code COLLECTION_NOT_ACCESSIBLE',
        pg_temp._has_issue(v_a, 'COLLECTION_NOT_ACCESSIBLE')
        AND pg_temp._has_issue(v_b, 'COLLECTION_NOT_ACCESSIBLE'),
        format('inexistente=%s alheia=%s',
               pg_temp._has_issue(v_a, 'COLLECTION_NOT_ACCESSIBLE'),
               pg_temp._has_issue(v_b, 'COLLECTION_NOT_ACCESSIBLE')),
        'ambos COLLECTION_NOT_ACCESSIBLE');

    PERFORM pg_temp._rec('N','N02 - as duas mensagens sao BYTE-IDENTICAS (nada distingue inexistente de alheia)',
        fa IS NOT NULL AND fb IS NOT NULL AND fa = fb,
        format('a=%L b=%L', fa, fb), 'mensagens iguais');

    -- E o numero de issues tem de ser o mesmo: um contador diferente
    -- tambem seria canal lateral.
    PERFORM pg_temp._rec('N','N03 - as duas respostas tem a MESMA quantidade de issues (contagem nao vira canal lateral)',
        jsonb_array_length(v_a -> 'issues') = jsonb_array_length(v_b -> 'issues'),
        format('a=%s b=%s', jsonb_array_length(v_a -> 'issues'),
               jsonb_array_length(v_b -> 'issues')),
        'contagens iguais');
END;
$N$;

-- ----------------------------------------------------------------
-- N04-N06 — NAO-ENUMERACAO DE STORAGE
--
-- Prova equivalente a de Collection. `5148`/`5150` colapsam os dois
-- casos na mesma mensagem via `inventory_id` DENTRO do WHERE; se o
-- Preview distinguisse Storage inexistente de Storage alheio, seria
-- uma regressao de seguranca — e o Storage e tao enumeravel quanto a
-- Collection.
-- ----------------------------------------------------------------
DO $N2$
DECLARE
    v_a JSONB; v_b JSONB; v_items JSONB;
    v_ghost CONSTANT UUID := '00000000-0000-4000-8000-0000000000fd';
    fa TEXT; fb TEXT;
BEGIN
    v_items := jsonb_build_array(
                   pg_temp._it(pg_temp._fx('cv1')::text, pg_temp._fx('lang')::text, 1));
    PERFORM pg_temp._as(pg_temp._fx('u1'));

    -- A: Storage INEXISTENTE.  B: Storage de TERCEIRO (sc2, de u2).
    v_a := public.preview_bulk_operation(
               pg_temp._preq('REGISTER_PHYSICAL_CARDS', v_items, NULL, v_ghost));
    v_b := public.preview_bulk_operation(
               pg_temp._preq('REGISTER_PHYSICAL_CARDS', v_items, NULL, pg_temp._fx('sc2')));

    SELECT i.e ->> 'message' INTO fa
      FROM jsonb_array_elements(v_a -> 'issues') i(e)
     WHERE i.e ->> 'code' = 'STORAGE_NOT_ACCESSIBLE';
    SELECT i.e ->> 'message' INTO fb
      FROM jsonb_array_elements(v_b -> 'issues') i(e)
     WHERE i.e ->> 'code' = 'STORAGE_NOT_ACCESSIBLE';

    PERFORM pg_temp._rec('N','N04 - Storage INEXISTENTE e Storage de TERCEIRO produzem o MESMO code STORAGE_NOT_ACCESSIBLE',
        pg_temp._has_issue(v_a, 'STORAGE_NOT_ACCESSIBLE')
        AND pg_temp._has_issue(v_b, 'STORAGE_NOT_ACCESSIBLE'),
        format('inexistente=%s alheio=%s',
               pg_temp._has_issue(v_a, 'STORAGE_NOT_ACCESSIBLE'),
               pg_temp._has_issue(v_b, 'STORAGE_NOT_ACCESSIBLE')),
        'ambos STORAGE_NOT_ACCESSIBLE');

    PERFORM pg_temp._rec('N','N05 - as duas mensagens de Storage sao BYTE-IDENTICAS (nada distingue inexistente de alheio)',
        fa IS NOT NULL AND fb IS NOT NULL AND fa = fb,
        format('a=%L b=%L', fa, fb), 'mensagens iguais');

    PERFORM pg_temp._rec('N','N06 - as duas respostas de Storage tem a MESMA quantidade de issues (contagem nao vira canal lateral)',
        jsonb_array_length(v_a -> 'issues') = jsonb_array_length(v_b -> 'issues'),
        format('a=%s b=%s', jsonb_array_length(v_a -> 'issues'),
               jsonb_array_length(v_b -> 'issues')),
        'contagens iguais');
END;
$N2$;

-- ================================================================
-- GRUPO P — FINGERPRINT PREVIEW x EXECUÇÃO, COMO `authenticated` REAL
--
-- O caso critico do harness inteiro. Ver a justificativa no cabecalho:
-- rodando como `postgres`, uma 5151 INVOKER passaria neste teste e
-- quebraria em producao. Por isso aqui — e SO aqui — trocamos de papel
-- de verdade.
--
-- Regra operacional (aprendida em 5808): com o papel trocado, NAO se
-- le pg_temp nem tabela temporaria. Tudo e capturado antes; todo _rec
-- acontece depois do RESET ROLE.
-- ================================================================
DO $P$
DECLARE
    v_u1 UUID; v_cv TEXT; v_cv2 TEXT; v_lang TEXT;
    v_col UUID; v_stg UUID;
    v_items JSONB; v_req JSONB;
    v_fp_ref  TEXT;   -- calculado como postgres = privilegio de 5150
    v_fp_prev TEXT;   -- devolvido pelo Preview como authenticated REAL
    v_res JSONB; v_exec JSONB;
    v_err TEXT := NULL;
BEGIN
    -- ---- captura ANTES de qualquer troca de papel -----------------
    v_u1   := pg_temp._fx('u1');
    v_cv   := pg_temp._fx('cv1')::text;
    v_cv2  := pg_temp._fx('cv2')::text;
    v_lang := pg_temp._fx('lang')::text;
    v_col  := pg_temp._fx('col_open');
    v_stg  := pg_temp._fx('sc1');

    v_items := jsonb_build_array(pg_temp._it(v_cv,  v_lang, 2),
                                 pg_temp._it(v_cv2, v_lang, 1));
    v_req   := pg_temp._preq('REGISTER_PHYSICAL_CARDS', v_items, v_col, v_stg);

    PERFORM pg_temp._as(v_u1);

    -- Referencia: 5149 chamada com o privilegio que 5150 tem.
    v_fp_ref := public.preview_fingerprint_register_physical_cards(v_items, v_col, v_stg);

    -- ---- agora como `authenticated` DE VERDADE ---------------------
    BEGIN
        SET LOCAL ROLE authenticated;
        v_res := public.preview_bulk_operation(v_req);
        RESET ROLE;
    EXCEPTION WHEN OTHERS THEN
        RESET ROLE;
        v_err := SQLERRM;
    END;

    -- ---- daqui em diante, papel normal: pode ler pg_temp -----------
    v_fp_prev := v_res ->> 'preview_fingerprint';

    PERFORM pg_temp._rec('P','P01 - Preview executado com SET ROLE authenticated REAL retorna ok=true (se 5151 fosse INVOKER, o catalogo viria vazio por RLS)',
        v_err IS NULL AND (v_res ->> 'ok')::boolean IS TRUE,
        coalesce('erro: ' || v_err, 'ok=' || (v_res ->> 'ok')), 'sem erro e ok=true');

    PERFORM pg_temp._rec('P','P02 - fingerprint do Preview (como authenticated) e BYTE-IDENTICO ao de 5149 com o privilegio de 5150 — prova direta de que SECURITY DEFINER esta correto',
        v_fp_prev IS NOT NULL AND v_fp_ref IS NOT NULL AND v_fp_prev = v_fp_ref,
        format('preview=%s referencia=%s iguais=%s',
               left(coalesce(v_fp_prev,'NULL'), 12),
               left(coalesce(v_fp_ref,'NULL'), 12),
               (v_fp_prev IS NOT DISTINCT FROM v_fp_ref)),
        'fingerprints identicos');

    -- P03 — prova COMPORTAMENTAL ponta a ponta: o token do Preview e
    -- aceito por 5150. Se os fingerprints divergissem, aqui viria
    -- PREVIEW_STALE em vez de CREATED.
    --
    -- A chamada e envolvida em BEGIN/EXCEPTION porque, sem isso, uma
    -- falha real de 5150 (PREVIEW_STALE, por exemplo — exatamente o
    -- sintoma que este grupo existe para pegar) abortaria o harness
    -- ANTES do relatorio. O caso tem de virar FAIL legivel, nao um
    -- erro cru que esconde os outros 59 resultados.
    v_err := NULL;
    BEGIN
        v_exec := public.register_physical_cards_bulk(
                      pg_temp._xreq(gen_random_uuid(), v_fp_prev, v_items, v_col, v_stg));
    EXCEPTION WHEN OTHERS THEN
        v_err  := format('SQLSTATE=%s | %s', SQLSTATE, SQLERRM);
        v_exec := NULL;
    END;

    PERFORM pg_temp._rec('P','P03 - o fingerprint do Preview e ACEITO por 5150: outcome CREATED e 3 Physical Cards (divergencia teria dado PREVIEW_STALE)',
        v_err IS NULL
        AND v_exec ->> 'outcome' = 'CREATED'
        AND (v_exec -> 'result_summary' ->> 'created_count')::int = 3
        AND (v_exec -> 'result_summary' ->> 'allocated_count')::int = 3,
        coalesce('excecao: ' || v_err,
                 format('outcome=%s created=%s allocated=%s', v_exec ->> 'outcome',
                        v_exec -> 'result_summary' ->> 'created_count',
                        v_exec -> 'result_summary' ->> 'allocated_count')),
        'CREATED / created=3 / allocated=3');
END;
$P$;

-- ================================================================
-- GRUPO D — PERFORMANCE OBSERVACIONAL COM 1000 CARD VARIANTS REAIS
--
-- OBSERVACIONAL, nao benchmark: mede e REGISTRA, sem SLO arbitrario.
-- Nenhum indice novo e proposto nesta frente.
--
-- MUDANCA da v2.0: a versao anterior usava 2 itens x quantity 500.
-- Isso media o caminho de EXPANSAO, mas resolvia so DUAS tuplas de
-- catalogo — justamente a parte cara do fingerprint. O payload agora
-- e 1000 `card_variant_id` REAIS e DISTINTOS, `quantity = 1`, sem
-- Collection e sem Storage: 1000 resolucoes reais de catalogo, que e
-- o que o caminho de producao vai enfrentar.
--
-- Se o catalogo nao tiver 1000 Card Variants, `D01` FALHA. A carga
-- NAO e reduzida em silencio — um numero medido sobre menos trabalho
-- do que o declarado e pior que numero nenhum.
-- ================================================================
DO $D$
DECLARE
    v_items JSONB; v_res JSONB; v_n INT;
    t0 TIMESTAMPTZ; t1 TIMESTAMPTZ; v_ms NUMERIC;
BEGIN
    PERFORM pg_temp._as(pg_temp._fx('u1'));

    SELECT count(*) INTO v_n
      FROM (SELECT cv.id FROM public.card_variant cv ORDER BY cv.id LIMIT 1000) s;

    PERFORM pg_temp._rec('D','D01 - o catalogo tem pelo menos 1000 Card Variants REAIS para a medicao (se nao tiver, FALHA — a carga jamais e reduzida em silencio)',
        v_n = 1000, format('disponiveis=%s', v_n), 'exatamente 1000');

    SELECT jsonb_agg(pg_temp._it(s.id::text, pg_temp._fx('lang')::text, 1))
      INTO v_items
      FROM (SELECT cv.id FROM public.card_variant cv ORDER BY cv.id LIMIT 1000) s;

    t0 := clock_timestamp();
    v_res := public.preview_bulk_operation(
                 pg_temp._preq('REGISTER_PHYSICAL_CARDS', v_items));
    t1 := clock_timestamp();
    v_ms := round(extract(epoch FROM (t1 - t0)) * 1000, 2);

    PERFORM pg_temp._rec('D','D02 - Preview com 1000 card_variant_id REAIS e distintos, quantity=1, sem Collection e sem Storage: ok=true, 1000 distintos, fingerprint presente',
        (v_res ->> 'ok')::boolean IS TRUE
        AND (v_res -> 'summary' ->> 'distinct_items')::int = 1000
        AND (v_res -> 'summary' ->> 'will_create_count')::int = 1000
        AND (v_res -> 'summary' ->> 'will_allocate_count')::int = 0
        AND v_res ->> 'preview_fingerprint' IS NOT NULL,
        format('ok=%s distinct=%s create=%s allocate=%s fp=%s', v_res ->> 'ok',
               v_res -> 'summary' ->> 'distinct_items',
               v_res -> 'summary' ->> 'will_create_count',
               v_res -> 'summary' ->> 'will_allocate_count',
               (v_res ->> 'preview_fingerprint') IS NOT NULL),
        'ok=true, distinct=1000, create=1000, allocate=0, fingerprint presente');

    PERFORM pg_temp._rec('D','D03 - tempo do Preview com 1000 Card Variants reais REGISTRADO para leitura humana (observacional, sem SLO nesta rodada)',
        v_ms IS NOT NULL,
        format('%s ms', v_ms), 'medicao registrada');
END;
$D$;

-- ================================================================
-- X02 — RESÍDUO RELATIVO AO BASELINE
--
-- O harness ESCREVE de fato (fixtures, o Game sintetico e o CREATED do
-- grupo P). O criterio nao e "tudo zero": e que o ROLLBACK devolva as
-- NOVE tabelas ao baseline. A verificacao definitiva e EXTERNA, apos
-- o rollback; aqui provamos apenas que houve escrita real — um
-- harness que nao escreve nada nao prova nada sobre residuo.
-- ================================================================
DO $X2$
DECLARE
    v_pc_now BIGINT; v_pc_bl BIGINT;
    v_gm_now BIGINT; v_gm_bl BIGINT;
BEGIN
    SELECT count(*) INTO v_pc_now FROM public.physical_card;
    SELECT n INTO v_pc_bl FROM _bl WHERE k = 'physical_card';
    SELECT count(*) INTO v_gm_now FROM public.game;
    SELECT n INTO v_gm_bl FROM _bl WHERE k = 'game';

    PERFORM pg_temp._rec('X','X02 - o harness ESCREVEU de fato em physical_card E em game (ambos acima do baseline); zero residuo REAL e provado externamente apos o ROLLBACK',
        v_pc_now > v_pc_bl AND v_gm_now > v_gm_bl,
        format('physical_card agora=%s baseline=%s | game agora=%s baseline=%s',
               v_pc_now, v_pc_bl, v_gm_now, v_gm_bl),
        'ambos: agora > baseline');
END;
$X2$;

-- ================================================================
-- RELATÓRIO FINAL + GATE
--
-- Entregue por RAISE EXCEPTION: aborta a transacao e garante o
-- ROLLBACK por construcao. Ver "TRANSPORTE" no cabecalho.
-- ================================================================
DO $REPORT$
DECLARE
    v_total INT; v_pass INT; v_fail INT;
    v_detail TEXT;
    v_gate BOOLEAN;
BEGIN
    SELECT count(*), count(*) FILTER (WHERE passed), count(*) FILTER (WHERE NOT passed)
      INTO v_total, v_pass, v_fail
      FROM _r;

    -- v2.2: casos OBSERVACIONAIS (grupo `D`) imprimem `got` tambem
    -- quando PASSAM. Sem isso a medicao de `D03` nunca chega ao
    -- relatorio — um caso observacional que so mostra o numero quando
    -- falha nao entrega medicao nenhuma. FAIL continua imprimindo
    -- got+want em qualquer grupo. A logica do gate NAO muda.
    SELECT string_agg(
               format('%s | %s | %s%s', grp, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END,
                      label,
                      CASE
                          WHEN NOT passed
                              THEN E'\n      got : ' || coalesce(got, '<null>')
                                   || E'\n      want: ' || coalesce(want, '<null>')
                          WHEN grp = 'D'
                              THEN E'\n      got : ' || coalesce(got, '<null>')
                          ELSE ''
                      END),
               E'\n' ORDER BY grp, label)
      INTO v_detail
      FROM _r;

    v_gate := (v_total = 60 AND v_fail = 0);

    RAISE EXCEPTION E'\n%',
        format(E'============== 5823 v2.2 — PREVIEW BULK OPERATION ==============\n%s\n'
               '---------------------------------------------------------------\n'
               'BASELINE (9 tabelas): %s\n'
               '---------------------------------------------------------------\n'
               'TOTAL=%s  PASS=%s  FAIL=%s  NOT PROVEN=0\n'
               'GATE ESPERADO: 60/60/0/0   ->   GATE_OK = %s\n'
               'ROLLBACK GARANTIDO POR CONSTRUCAO (esta excecao aborta a transacao).\n'
               '===============================================================',
               v_detail,
               (SELECT string_agg(k || '=' || n, ' ' ORDER BY k) FROM _bl),
               v_total, v_pass, v_fail, v_gate)
        USING ERRCODE = '55000';
END;
$REPORT$;

ROLLBACK;

/*
================================================================
APÓS O ROLLBACK — POSTCHECK EXTERNO, BASELINE-RELATIVO
================================================================
Rodar em chamada SEPARADA, depois do rollback:

SELECT (SELECT count(*) FROM public.bulk_operation)                AS bulk_operation,
       (SELECT count(*) FROM public.physical_card)                 AS physical_card,
       (SELECT count(*) FROM public.collection_allocation)         AS collection_allocation,
       (SELECT count(*) FROM public.collection)                    AS collection,
       (SELECT count(*) FROM public.collection_reference)          AS collection_reference,
       (SELECT count(*) FROM public.collection_card_set_reference) AS collection_card_set_reference,
       (SELECT count(*) FROM public.storage_container)             AS storage_container,
       (SELECT count(*) FROM public.inventory)                     AS inventory,
       (SELECT count(*) FROM public.game)                          AS game;

Critério: cada uma destas NOVE contagens tem de ser IGUAL ao valor
correspondente na linha `BASELINE (9 tabelas)` do relatório. Não é
"tudo zero" — é igualdade com o estado anterior ao harness.

Complementos — todos devem devolver 0:

SELECT count(*) FROM public.collection WHERE name LIKE 'BULK03 HARNESS%';
SELECT count(*) FROM public.storage_container WHERE name LIKE 'BULK03 HARNESS%';
SELECT count(*) FROM public.game WHERE code LIKE 'ZZTEST_BULK03_%';

O último é o mais importante: `public.game` é uma tabela de catálogo
global, e o Game sintético é a única linha que este harness cria fora
do escopo de um Owner. Se ele sobreviver a um rollback que falhou,
aparece aqui — e não em silêncio. O `LIKE` casa TODAS as execuções,
não só a última, porque o código é único por execução (`F03`).

Nota sobre o padrão: em `LIKE`, `_` é curinga de um caractere. Aqui
isso só torna a checagem MAIS ampla que o literal — direção segura
para uma verificação de resíduo, que deve pecar por excesso.
================================================================
*/
