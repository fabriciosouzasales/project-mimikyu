/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5822 - Harness funcional de BULK-02
               (5147 / 5148 / 5149 / 5150)
Versão......: 2.1
Status......: CONFIRMADO EXECUTADO (2026-09-09) — gate 64/64/0/0
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-08 (COLLECTIONS-BULK-02-GATE-A-REVISION-02)

Descrição...:
Harness FUNCIONAL fail-closed das quatro Queries de BULK-02. Executado
APÓS aplicá-las, na ordem 5147 -> 5148 -> 5149 -> 5150, e somente
depois delas.

================================================================
GATE DE ACEITE (v2.1)
================================================================
    TOTAL 64 / PASS 64 / FAIL 0 / NOT PROVEN 0

Contagem de rótulos — MEDIDA no arquivo, não estimada:

    X ... X01 X02                                        (2)
    F ... F01 F02 F-ABORT                                (3)
    E ... E01..E08                                       (8)
    S ... S01..S08                                       (8)
    H ... H01..H05 H-ABORT                               (6)
    L ... L01 L02                                        (2)
    P ... P01..P15 P-ABORT                              (16)
    R ... R01..R06 R-ABORT                               (7)
    G ... G01..G05 G-ABORT                               (6)
    A ... A01..A06 A-ABORT (x2)                          (8)
    I ... I01..I05 I-ABORT                               (6)
                      LINHAS de rótulo no arquivo   =   72

`F-ABORT`, `H-ABORT`, `P-ABORT`, `R-ABORT`, `G-ABORT`, `A-ABORT` e
`I-ABORT` são ramos FAIL-ONLY: só são gravados com `passed = FALSE`,
dentro de `EXCEPTION WHEN OTHERS` — ou, no caso da segunda ocorrência
de `A-ABORT`, dentro do `IF` que detecta escrita indevida em `A06`.
No caminho saudável nenhum deles é alcançável.

    linhas de rótulo              72
    − linhas fail-only           − 8
    = TOTAL de runtime            64
        PASS                      64
        FAIL                       0
        NOT PROVEN                 0

================================================================
SOBRE CONCORRÊNCIA — POSIÇÃO EXPLÍCITA
================================================================
Este harness **não repete** `K01`/`K02`/`K03` de BULK-01. Aquela prova
— duas sessões `psql` persistentes mais observador one-shot pelo SQL
Editor — cobriu a serialização de `claim_bulk_operation()`, que B1
apenas CONSOME e não redefine.

E **não se afirma aqui que B1 não introduz resource locks novos.** Ele
introduz: `5148` adquire `FOR UPDATE` em `inventory`, `collection` e
`storage_container`. É justamente por isso que a ordem dessas três
aquisições virou UMA implementação compartilhada (`I9`), provada
estaticamente pelo grupo `L`.

**Existe UM blocker concreto de concorrência específico de BULK-02**,
identificado na `REVISION-02` e distinto de tudo que BULK-01 provou:
*snapshot pós-espera*. Quando a sessão B espera no `FOR UPDATE` da
Collection e o lock é liberado pelo COMMIT da sessão A, o recálculo do
`preview_fingerprint` (passo 5 de `5150`, via `5149`) TEM de enxergar o
estado NOVO. É por isso que `5149` é `VOLATILE` e nunca `STABLE` — o
grupo `E` prova a volatilidade estaticamente (`E08`), mas o
comportamento sob espera real não cabe em sessão única.

Esse blocker é provado EXTERNAMENTE pelo runbook
`CONCURRENCY-PROOF-PREVIEW-STALE.sql` desta mesma pasta, com duas
sessões `psql` persistentes e observador one-shot. **O runbook é
OBRIGATÓRIO para o fechamento técnico de BULK-02** — este harness,
sozinho, não fecha a frente.

================================================================
PROTOCOLO DE TRÊS CHAMADAS — OBRIGATÓRIO
================================================================
    CALL 1 — do BEGIN; até o SELECT final, inclusive
    CALL 2 — ROLLBACK;
    CALL 3 — postcheck externo de ZERO RESÍDUO, BASELINE-RELATIVO:

        SELECT (SELECT count(*) FROM public.bulk_operation)                 AS bulk_operation,
               (SELECT count(*) FROM public.physical_card)                  AS physical_card,
               (SELECT count(*) FROM public.collection_allocation)          AS collection_allocation,
               (SELECT count(*) FROM public.collection)                     AS collection,
               (SELECT count(*) FROM public.collection_reference)           AS collection_reference,
               (SELECT count(*) FROM public.collection_card_set_reference)  AS collection_card_set_reference,
               (SELECT count(*) FROM public.storage_container)              AS storage_container,
               (SELECT count(*) FROM public.inventory)                      AS inventory;

O critério NÃO é "tudo zero". É **igualdade com a coluna `baseline` do
relatório da CALL 1**, que traz exatamente estas OITO contagens
medidas ANTES de qualquer escrita do harness. O harness funciona com o
banco já povoado.

São OITO, e não seis: a fixture `col_ref` é criada por
`create_reference_based_card_set_collection()`, que escreve também em
`collection_reference` e `collection_card_set_reference`. Deixá-las de
fora tornaria o postcheck cego a resíduo nessas duas tabelas.

O relatório é lido ANTES do `ROLLBACK`; logo, nenhum caso interno pode
provar zero resíduo — quando os casos rodam, o rollback ainda não
aconteceu. A prova é a CALL 3, e só ela. `X01` garante o outro lado da
conta: registra o baseline antes da primeira escrita.

================================================================
PAPEL DE EXECUÇÃO
================================================================
`postgres`, ou outra role administrativa com `EXECUTE` explícito sobre
as funções de `5147`/`5148` e sobre `claim_bulk_operation` /
`complete_bulk_operation`.

`service_role` NÃO serve — `EXECUTE` está revogado dela, e provar isso
é o próprio `S03`. `authenticated` também não: o harness precisa criar
fixtures e ler catálogo de sistema.

O grupo `S` usa `SET LOCAL ROLE` deliberadamente e SOMENTE para provar
AUSÊNCIA de acesso (`42501`). Os demais grupos apenas definem
`request.jwt.claims`, sem trocar de papel — que é exatamente como o
chamador real opera.

STATUS DESTA QUERY: CONFIRMADO EXECUTADO (2026-09-09) — gate
64 TOTAL / 64 PASS / 0 FAIL / 0 NOT PROVEN, com residuo Delta = 0 nas
oito tabelas do postcheck baseline-relativo.
================================================================
*/

BEGIN;

-- ================================================================
-- INFRAESTRUTURA DO HARNESS
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

CREATE TEMP TABLE _fp (k TEXT PRIMARY KEY, v TEXT) ON COMMIT DROP;

CREATE FUNCTION pg_temp._rec(
    p_grp TEXT, p_label TEXT, p_passed BOOLEAN, p_got TEXT, p_want TEXT
) RETURNS VOID LANGUAGE sql AS $$
    INSERT INTO _r (grp, label, passed, got, want)
    VALUES (p_grp, p_label, COALESCE(p_passed, FALSE), p_got, p_want);
$$;

-- Executa `p_sql` esperando FALHA cujo SQLERRM contenha `p_needle`.
CREATE FUNCTION pg_temp._expect_error(
    p_grp TEXT, p_label TEXT, p_sql TEXT, p_needle TEXT
) RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_msg TEXT;
BEGIN
    BEGIN
        EXECUTE p_sql;
        PERFORM pg_temp._rec(p_grp, p_label, FALSE,
            'NAO levantou excecao', 'excecao contendo: ' || p_needle);
        RETURN;
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM;
    END;
    PERFORM pg_temp._rec(p_grp, p_label, position(p_needle in v_msg) > 0,
        v_msg, 'excecao contendo: ' || p_needle);
END;
$$;

-- Assume a identidade do chamador SEM trocar de papel — igual ao real.
CREATE FUNCTION pg_temp._as(p_uid UUID) RETURNS VOID LANGUAGE sql AS $$
    SELECT set_config('request.jwt.claims',
        json_build_object('sub', p_uid::text, 'role', 'authenticated')::text, TRUE);
$$;

CREATE FUNCTION pg_temp._fx(p_k TEXT) RETURNS UUID LANGUAGE sql STABLE AS $$
    SELECT v FROM _fx WHERE k = p_k;
$$;

-- search_path EFETIVAMENTE vazio (nao apenas presente).
-- Padrao CANONICO, reaproveitado literalmente de `5821` (BULK-01).
-- Comparar com o literal 'search_path=' NAO funciona: o PostgreSQL
-- persiste `SET search_path = ''` como `search_path=""`, com o valor
-- entre aspas. Este helper remove o prefixo e desfaz o quoting.
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

-- Monta o envelope congelado de 5150.
CREATE FUNCTION pg_temp._req(
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

-- Um item.
CREATE FUNCTION pg_temp._it(p_cv TEXT, p_lang TEXT, p_qty NUMERIC)
RETURNS JSONB LANGUAGE sql IMMUTABLE AS $$
    SELECT jsonb_build_object('card_variant_id', p_cv,
                              'language_id',     p_lang,
                              'quantity',        p_qty);
$$;

-- ================================================================
-- X01 — BASELINE das OITO tabelas que o harness cria ou toca.
--       Capturado ANTES de qualquer escrita.
-- ================================================================
-- As OITO tabelas: `create_reference_based_card_set_collection()`
-- escreve tambem em `collection_reference` e
-- `collection_card_set_reference`, entao elas entram no baseline.
INSERT INTO _bl (k, n)
SELECT 'bulk_operation',        count(*) FROM public.bulk_operation
UNION ALL SELECT 'physical_card',                  count(*) FROM public.physical_card
UNION ALL SELECT 'collection_allocation',          count(*) FROM public.collection_allocation
UNION ALL SELECT 'collection',                     count(*) FROM public.collection
UNION ALL SELECT 'collection_reference',           count(*) FROM public.collection_reference
UNION ALL SELECT 'collection_card_set_reference',  count(*) FROM public.collection_card_set_reference
UNION ALL SELECT 'storage_container',              count(*) FROM public.storage_container
UNION ALL SELECT 'inventory',                      count(*) FROM public.inventory;

DO $X1$
BEGIN
    PERFORM pg_temp._rec('X','X01 - baseline das 8 tabelas capturado ANTES de qualquer escrita (criterio de residuo e RELATIVO, nao "tudo zero")',
        (SELECT count(*) FROM _bl) = 8,
        (SELECT string_agg(k || '=' || n, ' ' ORDER BY k) FROM _bl),
        '8 contagens registradas');
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
    v_col_open UUID; v_col_ref UUID; v_col_stale UUID; v_col_alheia UUID;
BEGIN
    SELECT id INTO v_u1 FROM auth.users ORDER BY created_at, id LIMIT 1;
    SELECT id INTO v_u2 FROM auth.users WHERE id <> v_u1 ORDER BY created_at, id LIMIT 1;

    -- Catalogo real: duas Card Variants do MESMO Card Set e uma de
    -- OUTRO Card Set do MESMO Game (para a prova de elegibilidade).
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

    -- Fixtures pelas RPCs CANONICAS sempre que existirem: menos
    -- chance de o harness brigar com trigger e mais fidelidade ao
    -- caminho real do produto.
    SELECT s.id INTO v_sc1 FROM public.create_storage_container('BULK02 HARNESS SC1') s;

    SELECT c.id INTO v_col_open
      FROM public.create_collection(v_game, 'BULK02 HARNESS OPEN', NULL, v_sc1) c;

    SELECT c.id INTO v_col_stale
      FROM public.create_collection(v_game, 'BULK02 HARNESS STALE', NULL, v_sc1) c;

    SELECT c.id INTO v_col_ref
      FROM public.create_reference_based_card_set_collection(
               v_game, 'BULK02 HARNESS REF', NULL, v_sc1, v_set1) c;

    -- ---- usuario 2 (recursos ALHEIOS, para nao-enumeracao) ---------
    PERFORM pg_temp._as(v_u2);

    IF NOT EXISTS (SELECT 1 FROM public.inventory inv WHERE inv.owner_user_id = v_u2) THEN
        INSERT INTO public.inventory (owner_user_id) VALUES (v_u2);
    END IF;

    SELECT s.id INTO v_sc2 FROM public.create_storage_container('BULK02 HARNESS SC2-ALHEIO') s;

    SELECT c.id INTO v_col_alheia
      FROM public.create_collection(v_game, 'BULK02 HARNESS ALHEIA', NULL, v_sc2) c;

    PERFORM pg_temp._as(v_u1);

    INSERT INTO _fx (k, v) VALUES
        ('u1', v_u1), ('u2', v_u2),
        ('cv1', v_cv1), ('cv2', v_cv2), ('cv_other', v_cv_other),
        ('lang', v_lang), ('game', v_game), ('set1', v_set1),
        ('inv1', v_inv1), ('sc1', v_sc1), ('sc2', v_sc2),
        ('col_open', v_col_open), ('col_ref', v_col_ref),
        ('col_stale', v_col_stale), ('col_alheia', v_col_alheia);

    PERFORM pg_temp._rec('F','F02 - fixture patrimonial criada pelas RPCs canonicas (1 inventory, 2 storages sendo 1 alheio, 4 collections sendo 1 REFERENCE_BASED e 1 alheia)',
        v_inv1 IS NOT NULL AND v_sc1 IS NOT NULL AND v_sc2 IS NOT NULL
        AND v_col_open IS NOT NULL AND v_col_ref IS NOT NULL
        AND v_col_stale IS NOT NULL AND v_col_alheia IS NOT NULL,
        format('inv=%s sc1=%s sc2=%s open=%s ref=%s stale=%s alheia=%s',
               v_inv1 IS NOT NULL, v_sc1 IS NOT NULL, v_sc2 IS NOT NULL,
               v_col_open IS NOT NULL, v_col_ref IS NOT NULL,
               v_col_stale IS NOT NULL, v_col_alheia IS NOT NULL),
        'todos NOT NULL');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp._rec('F','F-ABORT - grupo F abortou', FALSE, SQLERRM, 'sem excecao');
END;
$F$;

-- ================================================================
-- GRUPO E — ESTRUTURAL
-- ================================================================
DO $E$
DECLARE p RECORD;
BEGIN
    SELECT pr.oid, pr.provolatile, pr.prosecdef, pr.proconfig
      INTO p FROM pg_proc pr JOIN pg_namespace n ON n.oid = pr.pronamespace
     WHERE n.nspname = 'public' AND pr.proname = 'bulk_canonical_json';
    PERFORM pg_temp._rec('E','E01 - bulk_canonical_json existe, e IMMUTABLE, NAO e SECURITY DEFINER e tem search_path vazio',
        p.provolatile = 'i' AND p.prosecdef IS FALSE AND pg_temp._empty_search_path(p.oid),
        format('volatile=%s secdef=%s search_path_vazio=%s',
               p.provolatile, p.prosecdef, pg_temp._empty_search_path(p.oid)),
        'volatile=i secdef=false search_path_vazio=true');

    SELECT pr.oid, pr.provolatile, pr.prosecdef, pr.proconfig
      INTO p FROM pg_proc pr JOIN pg_namespace n ON n.oid = pr.pronamespace
     WHERE n.nspname = 'public' AND pr.proname = 'bulk_request_hash';
    PERFORM pg_temp._rec('E','E02 - bulk_request_hash existe, e IMMUTABLE, NAO e SECURITY DEFINER e tem search_path vazio',
        p.provolatile = 'i' AND p.prosecdef IS FALSE AND pg_temp._empty_search_path(p.oid),
        format('volatile=%s secdef=%s search_path_vazio=%s',
               p.provolatile, p.prosecdef, pg_temp._empty_search_path(p.oid)),
        'volatile=i secdef=false search_path_vazio=true');

    SELECT pr.oid, pr.prosecdef, pr.proconfig, pg_get_userbyid(pr.proowner) AS owner
      INTO p FROM pg_proc pr JOIN pg_namespace n ON n.oid = pr.pronamespace
     WHERE n.nspname = 'public' AND pr.proname = 'bulk_lock_operation_scope';
    PERFORM pg_temp._rec('E','E03 - bulk_lock_operation_scope e SECURITY DEFINER, owner postgres e search_path vazio',
        p.prosecdef IS TRUE AND p.owner = 'postgres' AND pg_temp._empty_search_path(p.oid),
        format('secdef=%s owner=%s search_path_vazio=%s',
               p.prosecdef, p.owner, pg_temp._empty_search_path(p.oid)),
        'secdef=true owner=postgres search_path_vazio=true');

    SELECT pr.oid, pr.prosecdef, pr.proconfig, pg_get_userbyid(pr.proowner) AS owner
      INTO p FROM pg_proc pr JOIN pg_namespace n ON n.oid = pr.pronamespace
     WHERE n.nspname = 'public' AND pr.proname = 'preview_fingerprint_register_physical_cards';
    PERFORM pg_temp._rec('E','E04 - preview_fingerprint_register_physical_cards e SECURITY INVOKER (helper interno, nao endpoint publico), owner postgres e search_path vazio',
        p.prosecdef IS FALSE AND p.owner = 'postgres' AND pg_temp._empty_search_path(p.oid),
        format('secdef=%s owner=%s search_path_vazio=%s',
               p.prosecdef, p.owner, pg_temp._empty_search_path(p.oid)),
        'secdef=false owner=postgres search_path_vazio=true');

    SELECT pr.oid, pr.prosecdef, pr.proconfig, pg_get_userbyid(pr.proowner) AS owner
      INTO p FROM pg_proc pr JOIN pg_namespace n ON n.oid = pr.pronamespace
     WHERE n.nspname = 'public' AND pr.proname = 'register_physical_cards_bulk';
    PERFORM pg_temp._rec('E','E05 - register_physical_cards_bulk e SECURITY DEFINER, owner postgres e search_path vazio',
        p.prosecdef IS TRUE AND p.owner = 'postgres' AND pg_temp._empty_search_path(p.oid),
        format('secdef=%s owner=%s search_path_vazio=%s',
               p.prosecdef, p.owner, pg_temp._empty_search_path(p.oid)),
        'secdef=true owner=postgres search_path_vazio=true');

    SELECT pg_get_function_identity_arguments(pr.oid) AS args,
           pg_get_function_result(pr.oid) AS ret,
           count(*) OVER () AS n
      INTO p
      FROM pg_proc pr JOIN pg_namespace n ON n.oid = pr.pronamespace
     WHERE n.nspname = 'public' AND pr.proname = 'register_physical_cards_bulk';
    PERFORM pg_temp._rec('E','E06 - ASSINATURA CONGELADA: exatamente uma sobrecarga, p_request jsonb -> jsonb',
        p.args = 'p_request jsonb' AND p.ret = 'jsonb' AND p.n = 1,
        format('args=%s ret=%s sobrecargas=%s', p.args, p.ret, p.n),
        'args=p_request jsonb / ret=jsonb / 1 sobrecarga');

    -- add_physical_cards e allocate_... permanecem INTACTAS ate BULK-05.
    -- BLOCKER da REVISION-02. STABLE usaria o snapshot do inicio da
    -- query chamadora: apos esperar no FOR UPDATE de 5148, o recalculo
    -- poderia enxergar o estado ANTERIOR ao commit que liberou o lock,
    -- e o PREVIEW_STALE nunca dispararia. VOLATILE forca snapshot novo.
    SELECT pr.provolatile INTO p
      FROM pg_proc pr JOIN pg_namespace n ON n.oid = pr.pronamespace
     WHERE n.nspname = 'public' AND pr.proname = 'preview_fingerprint_register_physical_cards';
    PERFORM pg_temp._rec('E','E08 - preview_fingerprint_register_physical_cards e VOLATILE (nunca STABLE): o recalculo pos-lock TEM de enxergar o estado corrente',
        p.provolatile = 'v',
        format('provolatile=%s', p.provolatile), 'provolatile=v');

    PERFORM pg_temp._rec('E','E07 - add_physical_cards e allocate_physical_cards_to_collection seguem existindo e com o teto de 500 INTACTO',
        EXISTS (SELECT 1 FROM pg_proc pr JOIN pg_namespace n ON n.oid = pr.pronamespace
                 WHERE n.nspname = 'public' AND pr.proname = 'add_physical_cards'
                   AND pr.prosrc LIKE '%500%')
        AND EXISTS (SELECT 1 FROM pg_proc pr JOIN pg_namespace n ON n.oid = pr.pronamespace
                     WHERE n.nspname = 'public' AND pr.proname = 'allocate_physical_cards_to_collection'
                       AND pr.prosrc LIKE '%500%'),
        'ver expressao', 'ambas existem e mencionam o teto 500');
END;
$E$;

-- ================================================================
-- GRUPO S — SEGURANÇA
-- ================================================================
DO $S$
DECLARE
    v_reg OID; v_fp OID;
    v_pub INT;
BEGIN
    SELECT pr.oid INTO v_reg FROM pg_proc pr JOIN pg_namespace n ON n.oid = pr.pronamespace
     WHERE n.nspname = 'public' AND pr.proname = 'register_physical_cards_bulk';
    SELECT pr.oid INTO v_fp  FROM pg_proc pr JOIN pg_namespace n ON n.oid = pr.pronamespace
     WHERE n.nspname = 'public' AND pr.proname = 'preview_fingerprint_register_physical_cards';

    PERFORM pg_temp._rec('S','S01 - register_physical_cards_bulk: authenticated TEM execute',
        has_function_privilege('authenticated', v_reg, 'EXECUTE'),
        format('%s', has_function_privilege('authenticated', v_reg, 'EXECUTE')), 'true');

    PERFORM pg_temp._rec('S','S02 - register_physical_cards_bulk: anon NAO tem execute',
        NOT has_function_privilege('anon', v_reg, 'EXECUTE'),
        format('%s', has_function_privilege('anon', v_reg, 'EXECUTE')), 'false');

    PERFORM pg_temp._rec('S','S03 - register_physical_cards_bulk: service_role NAO tem execute',
        NOT has_function_privilege('service_role', v_reg, 'EXECUTE'),
        format('%s', has_function_privilege('service_role', v_reg, 'EXECUTE')), 'false');

    -- PUBLIC nao e papel de pg_roles: a prova direta e o catalogo.
    -- proacl NULL significaria privilegios DEFAULT, e o default de
    -- function e justamente EXECUTE TO PUBLIC — por isso NULL e o caso RUIM.
    SELECT count(*) INTO v_pub
      FROM pg_proc pr, aclexplode(pr.proacl) a
     WHERE pr.oid = v_reg AND a.grantee = 0;

    PERFORM pg_temp._rec('S','S04 - register_physical_cards_bulk: PUBLIC NAO tem execute (proacl nao-NULL e sem grantee=0)',
        (SELECT pr.proacl FROM pg_proc pr WHERE pr.oid = v_reg) IS NOT NULL AND v_pub = 0,
        format('proacl_null=%s grantee0=%s',
               (SELECT pr.proacl FROM pg_proc pr WHERE pr.oid = v_reg) IS NULL, v_pub),
        'proacl_null=false grantee0=0');

    SELECT count(*) INTO v_pub
      FROM pg_proc pr, aclexplode(pr.proacl) a
     WHERE pr.oid = v_fp AND a.grantee = 0;

    -- REVISION-02: 5149 deixou de ser endpoint publico. A interface
    -- publica de Preview sera BULK-03. Nenhum dos quatro papeis executa.
    PERFORM pg_temp._rec('S','S05 - preview_fingerprint e HELPER INTERNO: authenticated, anon, service_role e PUBLIC TODOS sem execute',
        NOT has_function_privilege('authenticated', v_fp, 'EXECUTE')
        AND NOT has_function_privilege('anon', v_fp, 'EXECUTE')
        AND NOT has_function_privilege('service_role', v_fp, 'EXECUTE')
        AND (SELECT pr.proacl FROM pg_proc pr WHERE pr.oid = v_fp) IS NOT NULL
        AND v_pub = 0,
        format('auth=%s anon=%s svc=%s grantee0=%s',
               has_function_privilege('authenticated', v_fp, 'EXECUTE'),
               has_function_privilege('anon', v_fp, 'EXECUTE'),
               has_function_privilege('service_role', v_fp, 'EXECUTE'), v_pub),
        'auth=false anon=false svc=false grantee0=0');

    PERFORM pg_temp._rec('S','S06 - helpers internos NOVOS (bulk_canonical_json, bulk_request_hash, bulk_lock_operation_scope) sem execute para os 4',
        NOT has_function_privilege('authenticated','public.bulk_canonical_json(jsonb)','EXECUTE')
        AND NOT has_function_privilege('anon','public.bulk_canonical_json(jsonb)','EXECUTE')
        AND NOT has_function_privilege('service_role','public.bulk_canonical_json(jsonb)','EXECUTE')
        AND NOT has_function_privilege('authenticated','public.bulk_request_hash(text,jsonb)','EXECUTE')
        AND NOT has_function_privilege('anon','public.bulk_request_hash(text,jsonb)','EXECUTE')
        AND NOT has_function_privilege('service_role','public.bulk_request_hash(text,jsonb)','EXECUTE')
        AND NOT has_function_privilege('authenticated','public.bulk_lock_operation_scope(uuid,uuid)','EXECUTE')
        AND NOT has_function_privilege('anon','public.bulk_lock_operation_scope(uuid,uuid)','EXECUTE')
        AND NOT has_function_privilege('service_role','public.bulk_lock_operation_scope(uuid,uuid)','EXECUTE')
        AND (SELECT count(*) FROM pg_proc pr, aclexplode(pr.proacl) a
              WHERE pr.oid IN ('public.bulk_canonical_json(jsonb)'::regprocedure,
                               'public.bulk_request_hash(text,jsonb)'::regprocedure,
                               'public.bulk_lock_operation_scope(uuid,uuid)'::regprocedure)
                AND a.grantee = 0) = 0,
        'ver expressao', 'todos false e nenhum grantee=0');

    PERFORM pg_temp._rec('S','S07 - helpers de BULK-01 (claim/complete) seguem sem execute para os 4 papeis',
        NOT has_function_privilege('authenticated','public.claim_bulk_operation(text,uuid,text,text)','EXECUTE')
        AND NOT has_function_privilege('anon','public.claim_bulk_operation(text,uuid,text,text)','EXECUTE')
        AND NOT has_function_privilege('service_role','public.claim_bulk_operation(text,uuid,text,text)','EXECUTE')
        AND NOT has_function_privilege('authenticated','public.complete_bulk_operation(uuid,jsonb)','EXECUTE')
        AND NOT has_function_privilege('anon','public.complete_bulk_operation(uuid,jsonb)','EXECUTE')
        AND NOT has_function_privilege('service_role','public.complete_bulk_operation(uuid,jsonb)','EXECUTE')
        AND (SELECT count(*) FROM pg_proc pr, aclexplode(pr.proacl) a
              WHERE pr.oid IN ('public.claim_bulk_operation(text,uuid,text,text)'::regprocedure,
                               'public.complete_bulk_operation(uuid,jsonb)'::regprocedure)
                AND a.grantee = 0) = 0,
        'ver expressao', 'todos false e nenhum grantee=0');
END;
$S$;

-- S08 — prova de AUSENCIA de acesso em RUNTIME. Unico SET ROLE do arquivo.
DO $S8$
DECLARE v_msg TEXT; v_ok BOOLEAN := FALSE;
BEGIN
    BEGIN
        SET LOCAL ROLE authenticated;
        PERFORM 1 FROM public.bulk_operation LIMIT 1;
        v_msg := 'leitura direta em bulk_operation SUCEDEU';
    EXCEPTION WHEN insufficient_privilege THEN
        v_ok := TRUE; v_msg := SQLERRM;
    WHEN OTHERS THEN
        v_msg := SQLERRM;
    END;
    RESET ROLE;
    PERFORM pg_temp._rec('S','S08 - sessao authenticated recebe 42501 ao ler bulk_operation diretamente (runtime, nao catalogo)',
        v_ok, v_msg, '42501 insufficient_privilege');
END;
$S8$;

-- ================================================================
-- GRUPO H — CANONICALIZAÇÃO (5147)
-- ================================================================
DO $H$
DECLARE
    v_a TEXT; v_b TEXT;
BEGIN
    v_a := public.bulk_request_hash('T', '{"items":[{"a":1},{"a":2}]}'::jsonb);
    v_b := public.bulk_request_hash('T', '{"items":[{"a":2},{"a":1}]}'::jsonb);
    PERFORM pg_temp._rec('H','H01 - ORDEM DO ARRAY nao muda o hash (semantica de conjunto, deliberada)',
        v_a = v_b, format('a=%s b=%s', left(v_a,16), left(v_b,16)), 'iguais');

    v_a := public.bulk_request_hash('T', '{"x":1,"y":2}'::jsonb);
    v_b := public.bulk_request_hash('T', '{"y":2,"x":1}'::jsonb);
    PERFORM pg_temp._rec('H','H02 - ORDEM DAS CHAVES de objeto nao muda o hash',
        v_a = v_b, format('a=%s b=%s', left(v_a,16), left(v_b,16)), 'iguais');

    v_a := public.bulk_request_hash('T', '{"n":1.50}'::jsonb);
    v_b := public.bulk_request_hash('T', '{"n":1.5}'::jsonb);
    PERFORM pg_temp._rec('H','H03 - NORMALIZACAO NUMERICA: 1.50 e 1.5 produzem o mesmo hash',
        v_a = v_b, format('a=%s b=%s', left(v_a,16), left(v_b,16)), 'iguais');

    v_a := public.bulk_request_hash('REGISTER_PHYSICAL_CARDS', '{"n":1}'::jsonb);
    v_b := public.bulk_request_hash('REGISTER_CARD_SET',       '{"n":1}'::jsonb);
    PERFORM pg_temp._rec('H','H04 - operation_type DIFERENTE com intencao igual produz hash DIFERENTE (sem colisao entre B1 e B2)',
        v_a <> v_b, format('a=%s b=%s', left(v_a,16), left(v_b,16)), 'diferentes');

    v_a := public.bulk_request_hash('T', '{"items":[{"q":1}]}'::jsonb);
    v_b := public.bulk_request_hash('T', '{"items":[{"q":2}]}'::jsonb);
    PERFORM pg_temp._rec('H','H05 - sanidade NEGATIVA: intencao diferente produz hash diferente',
        v_a <> v_b, format('a=%s b=%s', left(v_a,16), left(v_b,16)), 'diferentes');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp._rec('H','H-ABORT - grupo H abortou', FALSE, SQLERRM, 'sem excecao');
END;
$H$;

-- ================================================================
-- GRUPO L — ORDEM DE LOCKS COMO FONTE ÚNICA (I9)
-- ================================================================
DO $L$
DECLARE
    v_src TEXT; v_i INT; v_c INT; v_s INT;
    v_reg TEXT;
BEGIN
    SELECT pr.prosrc INTO v_src FROM pg_proc pr JOIN pg_namespace n ON n.oid = pr.pronamespace
     WHERE n.nspname = 'public' AND pr.proname = 'bulk_lock_operation_scope';

    v_i := position('FROM public.inventory inv'          in v_src);
    v_c := position('FROM public.collection col'          in v_src);
    v_s := position('FROM public.storage_container sc'    in v_src);

    PERFORM pg_temp._rec('L','L01 - ordem canonica INVENTORY -> COLLECTION -> STORAGE provada na fonte unica de 5148',
        v_i > 0 AND v_c > 0 AND v_s > 0 AND v_i < v_c AND v_c < v_s,
        format('inventory@%s collection@%s storage@%s', v_i, v_c, v_s),
        '0 < inventory < collection < storage');

    SELECT pr.prosrc INTO v_reg FROM pg_proc pr JOIN pg_namespace n ON n.oid = pr.pronamespace
     WHERE n.nspname = 'public' AND pr.proname = 'register_physical_cards_bulk';

    PERFORM pg_temp._rec('L','L02 - B1 NAO tem FOR UPDATE proprio: a ordem de locks vem exclusivamente de 5148 (fonte unica, I9)',
        position('FOR UPDATE' in v_reg) = 0
        AND position('bulk_lock_operation_scope' in v_reg) > 0,
        format('for_update@%s chama_5148@%s',
               position('FOR UPDATE' in v_reg),
               position('bulk_lock_operation_scope' in v_reg)),
        'for_update@0 e chama_5148 > 0');
END;
$L$;

-- ================================================================
-- GRUPO P — CONTRATO DE PAYLOAD (tudo ANTES do claim)
-- ================================================================
DO $P$
DECLARE
    v_u1   UUID := pg_temp._fx('u1');
    v_cv1  TEXT := pg_temp._fx('cv1')::text;
    v_cv2  TEXT := pg_temp._fx('cv2')::text;
    v_lang TEXT := pg_temp._fx('lang')::text;
    v_one  JSONB;
    v_big  JSONB;
    v_call TEXT := 'SELECT public.register_physical_cards_bulk(%L::jsonb)';
BEGIN
    PERFORM pg_temp._as(v_u1);
    v_one := jsonb_build_array(pg_temp._it(v_cv1, v_lang, 1));

    PERFORM pg_temp._expect_error('P','P01 - p_request nao-objeto e rejeitado',
        format(v_call, '[]'), 'p_request deve ser um objeto JSON');

    PERFORM pg_temp._expect_error('P','P02 - chave desconhecida no envelope e rejeitada',
        format(v_call, (pg_temp._req(gen_random_uuid(), 'fp', v_one) || '{"lixo":1}'::jsonb)::text),
        'p_request aceita exatamente as chaves');

    PERFORM pg_temp._expect_error('P','P03 - chave obrigatoria ausente no envelope e rejeitada',
        format(v_call, jsonb_build_object('idempotency_key', gen_random_uuid()::text,
                                          'items', v_one)::text),
        'p_request exige idempotency_key, preview_fingerprint e items');

    PERFORM pg_temp._expect_error('P','P04 - items nao-array e rejeitado',
        format(v_call, pg_temp._req(gen_random_uuid(), 'fp', '{"a":1}'::jsonb)::text),
        'items deve ser um array JSON');

    PERFORM pg_temp._expect_error('P','P05 - items vazio e rejeitado',
        format(v_call, pg_temp._req(gen_random_uuid(), 'fp', '[]'::jsonb)::text),
        'items nao pode ser vazio');

    -- JSON REALMENTE VALIDO com elemento nao-objeto: ["x"]
    PERFORM pg_temp._expect_error('P','P06 - elemento nao-objeto e rejeitado, com JSON realmente valido (["x"])',
        format(v_call, pg_temp._req(gen_random_uuid(), 'fp', '["x"]'::jsonb)::text),
        'cada item de items deve ser um objeto JSON');

    PERFORM pg_temp._expect_error('P','P07 - chave desconhecida dentro do item e rejeitada',
        format(v_call, pg_temp._req(gen_random_uuid(), 'fp',
            jsonb_build_array(pg_temp._it(v_cv1, v_lang, 1) || '{"extra":true}'::jsonb))::text),
        'cada item de items aceita exatamente as chaves');

    PERFORM pg_temp._expect_error('P','P08 - quantity como string e rejeitada (tipo errado)',
        format(v_call, pg_temp._req(gen_random_uuid(), 'fp',
            jsonb_build_array(jsonb_build_object('card_variant_id', v_cv1,
                                                 'language_id', v_lang,
                                                 'quantity', '2')))::text),
        'tipos invalidos em items');

    PERFORM pg_temp._expect_error('P','P09 - UUID sintaticamente invalido e rejeitado COM LISTA do ofensor',
        format(v_call, pg_temp._req(gen_random_uuid(), 'fp',
            jsonb_build_array(pg_temp._it('nao-e-uuid', v_lang, 1)))::text),
        'invalido(s) em items: nao-e-uuid');

    PERFORM pg_temp._expect_error('P','P10 - quantity = 0 e rejeitada',
        format(v_call, pg_temp._req(gen_random_uuid(), 'fp',
            jsonb_build_array(pg_temp._it(v_cv1, v_lang, 0)))::text),
        'maior ou igual a 1');

    PERFORM pg_temp._expect_error('P','P11 - quantity negativa e rejeitada',
        format(v_call, pg_temp._req(gen_random_uuid(), 'fp',
            jsonb_build_array(pg_temp._it(v_cv1, v_lang, -3)))::text),
        'maior ou igual a 1');

    PERFORM pg_temp._expect_error('P','P12 - quantity fracionaria e rejeitada',
        format(v_call, pg_temp._req(gen_random_uuid(), 'fp',
            jsonb_build_array(pg_temp._it(v_cv1, v_lang, 2.5)))::text),
        'maior ou igual a 1');

    -- DUPLICIDADE SEMANTICA: mesma tupla, um dos UUIDs em CAIXA ALTA.
    -- Comparacao textual crua deixaria passar; comparacao por uuid nao.
    PERFORM pg_temp._expect_error('P','P13 - duplicidade SEMANTICA com variacao de CAIXA no UUID e rejeitada (upper(cv1) = cv1)',
        format(v_call, pg_temp._req(gen_random_uuid(), 'fp',
            jsonb_build_array(pg_temp._it(v_cv1, v_lang, 1),
                              pg_temp._it(upper(v_cv1), v_lang, 1)))::text),
        'duplicado(s)');

    -- BRUTO 1001: 1001 pares distintos sinteticos. O teto do payload
    -- bruto e anterior a qualquer checagem de existencia, entao UUIDs
    -- sinteticos servem e o caso fica barato.
    SELECT jsonb_agg(pg_temp._it(gen_random_uuid()::text, v_lang, 1))
      INTO v_big FROM generate_series(1, 1001);

    PERFORM pg_temp._expect_error('P','P14 - payload BRUTO com 1001 itens e rejeitado',
        format(v_call, pg_temp._req(gen_random_uuid(), 'fp', v_big)::text),
        'items excede o limite de 1000 itens por chamada (recebido 1001)');

    -- EXPANDIDO 1001 com BRUTO pequeno: 2 itens, 1000 + 1.
    PERFORM pg_temp._expect_error('P','P15 - TOTAL EXPANDIDO 1001 com payload bruto de apenas 2 itens e rejeitado',
        format(v_call, pg_temp._req(gen_random_uuid(), 'fp',
            jsonb_build_array(pg_temp._it(v_cv1, v_lang, 1000),
                              pg_temp._it(v_cv2, v_lang, 1)))::text),
        'criaria 1001 Physical Cards e excede o limite de 1000');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp._rec('P','P-ABORT - grupo P abortou', FALSE, SQLERRM, 'sem excecao');
END;
$P$;

-- ================================================================
-- GRUPO R — RELACIONAL / NÃO-ENUMERAÇÃO
-- ================================================================
DO $R$
DECLARE
    v_u1   UUID := pg_temp._fx('u1');
    v_cv1  TEXT := pg_temp._fx('cv1')::text;
    v_lang TEXT := pg_temp._fx('lang')::text;
    v_one  JSONB;
    v_fake UUID;
    v_call TEXT := 'SELECT public.register_physical_cards_bulk(%L::jsonb)';
BEGIN
    v_one := jsonb_build_array(pg_temp._it(v_cv1, v_lang, 1));

    PERFORM set_config('request.jwt.claims', NULL, TRUE);
    PERFORM pg_temp._expect_error('R','R01 - chamada sem auth.uid() e rejeitada',
        format(v_call, pg_temp._req(gen_random_uuid(), 'fp', v_one)::text),
        'authentication required');

    PERFORM pg_temp._as(v_u1);
    v_fake := gen_random_uuid();

    PERFORM pg_temp._expect_error('R','R02 - Storage de OUTRO Inventory e rejeitado com mensagem NAO-ENUMERANTE',
        format(v_call, pg_temp._req(gen_random_uuid(), 'fp', v_one, NULL, pg_temp._fx('sc2'))::text),
        'storage container not found or not owned by caller');

    PERFORM pg_temp._expect_error('R','R03 - Storage INEXISTENTE produz a MESMA mensagem de R02 (nao-enumeracao)',
        format(v_call, pg_temp._req(gen_random_uuid(), 'fp', v_one, NULL, v_fake)::text),
        'storage container not found or not owned by caller');

    PERFORM pg_temp._expect_error('R','R04 - Collection INEXISTENTE e rejeitada',
        format(v_call, pg_temp._req(gen_random_uuid(), 'fp', v_one, v_fake)::text),
        'collection not found or not owned by caller');

    PERFORM pg_temp._expect_error('R','R05 - Collection de TERCEIRO produz a MESMA mensagem de R04 (nao-enumeracao)',
        format(v_call, pg_temp._req(gen_random_uuid(), 'fp', v_one, pg_temp._fx('col_alheia'))::text),
        'collection not found or not owned by caller');

    -- Inexistente no catalogo: o fingerprint recalculado bate (a tupla
    -- inexistente simplesmente nao entra no catalogo dos dois lados),
    -- entao a falha vem da validacao de dominio, COM LISTA.
    DECLARE
        v_ghost UUID := gen_random_uuid();
        v_items JSONB;
        v_fp    TEXT;
    BEGIN
        v_items := jsonb_build_array(pg_temp._it(v_ghost::text, v_lang, 1));
        v_fp := public.preview_fingerprint_register_physical_cards(v_items);
        INSERT INTO _fp (k, v) VALUES ('ghost_fp', v_fp);
        INSERT INTO _fx (k, v) VALUES ('ghost', v_ghost);

        PERFORM pg_temp._expect_error('R','R06 - card_variant_id INEXISTENTE e rejeitado COM LISTA do ofensor, antes de qualquer escrita',
            format(v_call, pg_temp._req(gen_random_uuid(), v_fp, v_items)::text),
            '1 card_variant_id inexistente(s): ' || v_ghost::text);
    END;
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp._rec('R','R-ABORT - grupo R abortou', FALSE, SQLERRM, 'sem excecao');
END;
$R$;

-- ================================================================
-- GRUPO G — FINGERPRINT E PREVIEW_STALE
-- ================================================================
DO $G$
DECLARE
    v_u1    UUID := pg_temp._fx('u1');
    v_cv1   TEXT := pg_temp._fx('cv1')::text;
    v_cv2   TEXT := pg_temp._fx('cv2')::text;
    v_lang  TEXT := pg_temp._fx('lang')::text;
    v_stale UUID := pg_temp._fx('col_stale');
    v_i1 JSONB; v_i2 JSONB; v_i3 JSONB;
    v_a TEXT; v_b TEXT;
    v_call TEXT := 'SELECT public.register_physical_cards_bulk(%L::jsonb)';
BEGIN
    PERFORM pg_temp._as(v_u1);

    v_i1 := jsonb_build_array(pg_temp._it(v_cv1, v_lang, 1), pg_temp._it(v_cv2, v_lang, 2));
    v_i2 := jsonb_build_array(pg_temp._it(v_cv2, v_lang, 2), pg_temp._it(v_cv1, v_lang, 1));
    v_i3 := jsonb_build_array(pg_temp._it(v_cv1, v_lang, 7), pg_temp._it(v_cv2, v_lang, 9));

    v_a := public.preview_fingerprint_register_physical_cards(v_i1, v_stale);
    v_b := public.preview_fingerprint_register_physical_cards(v_i1, v_stale);
    PERFORM pg_temp._rec('G','G01 - fingerprint e DETERMINISTICO: dois calculos sem mudanca de estado devolvem o mesmo valor',
        v_a = v_b, format('a=%s b=%s', left(v_a,16), left(v_b,16)), 'iguais');

    v_b := public.preview_fingerprint_register_physical_cards(v_i2, v_stale);
    PERFORM pg_temp._rec('G','G02 - REORDENAR items nao muda o fingerprint',
        v_a = v_b, format('a=%s b=%s', left(v_a,16), left(v_b,16)), 'iguais');

    v_b := public.preview_fingerprint_register_physical_cards(v_i3, v_stale);
    PERFORM pg_temp._rec('G','G03 - mudar QUANTITY nao muda o fingerprint (quantity e intencao, nao estado do mundo)',
        v_a = v_b, format('a=%s b=%s', left(v_a,16), left(v_b,16)), 'iguais');

    -- MUDANCA REAL do estado, pela RPC canonica de lifecycle.
    PERFORM public.archive_collection(v_stale);

    v_b := public.preview_fingerprint_register_physical_cards(v_i1, v_stale);
    PERFORM pg_temp._rec('G','G04 - MUDANCA REAL do estado (archive_collection) MUDA o fingerprint',
        v_a <> v_b, format('antes=%s depois=%s', left(v_a,16), left(v_b,16)), 'diferentes');

    -- E a confirmacao com o fingerprint ANTIGO tem de falhar por
    -- PREVIEW_STALE — NAO por "collection is archived". Isso prova a
    -- ORDEM exigida: fingerprint (passo 5) ANTES da validacao de
    -- dominio (passo 6).
    PERFORM pg_temp._expect_error('G','G05 - PREVIEW_STALE por mudanca REAL do estado, e ANTES da validacao de lifecycle (prova a ordem passo 5 -> passo 6)',
        format(v_call, pg_temp._req(gen_random_uuid(), v_a, v_i1, v_stale)::text),
        'PREVIEW_STALE');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp._rec('G','G-ABORT - grupo G abortou', FALSE, SQLERRM, 'sem excecao');
END;
$G$;

-- ================================================================
-- GRUPO A — ATOMICIDADE / ZERO PARTIAL SUCCESS
-- ================================================================
DO $A$
DECLARE
    v_u1    UUID := pg_temp._fx('u1');
    v_cv1   TEXT := pg_temp._fx('cv1')::text;
    v_cv2   TEXT := pg_temp._fx('cv2')::text;
    v_other TEXT := pg_temp._fx('cv_other')::text;
    v_lang  TEXT := pg_temp._fx('lang')::text;
    v_inv   UUID := pg_temp._fx('inv1');
    v_col   UUID := pg_temp._fx('col_open');
    v_ref   UUID := pg_temp._fx('col_ref');
    v_sc1   UUID := pg_temp._fx('sc1');
    v_key   UUID := gen_random_uuid();
    v_items JSONB; v_fp TEXT; v_out JSONB; v_ids JSONB;
    v_before INT; v_after INT; v_alloc INT;
    v_call TEXT := 'SELECT public.register_physical_cards_bulk(%L::jsonb)';
BEGIN
    PERFORM pg_temp._as(v_u1);
    SELECT count(*) INTO v_before FROM public.physical_card WHERE inventory_id = v_inv;

    -- Falha de validacao de dominio DEPOIS do claim: card_variant
    -- inexistente (o mesmo fantasma de R06, ja com fingerprint valido).
    v_items := jsonb_build_array(pg_temp._it(pg_temp._fx('ghost')::text, v_lang, 5));
    v_fp := (SELECT v FROM _fp WHERE k = 'ghost_fp');

    BEGIN
        PERFORM public.register_physical_cards_bulk(
            pg_temp._req(v_key, v_fp, v_items));
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    SELECT count(*) INTO v_after FROM public.physical_card WHERE inventory_id = v_inv;

    PERFORM pg_temp._rec('A','A01 - falha na validacao de ID inexistente NAO cria Physical Card alguma (zero partial success)',
        v_after = v_before, format('antes=%s depois=%s', v_before, v_after), 'antes = depois');

    PERFORM pg_temp._rec('A','A02 - a mesma falha NAO consome o claim: a idempotency_key volta a estar livre',
        NOT EXISTS (SELECT 1 FROM public.bulk_operation b WHERE b.idempotency_key = v_key),
        format('linhas_com_a_chave=%s',
               (SELECT count(*) FROM public.bulk_operation b WHERE b.idempotency_key = v_key)),
        '0');

    -- Caminho feliz: 3 + 2 = 5, com Storage e Collection.
    v_items := jsonb_build_array(pg_temp._it(v_cv1, v_lang, 3), pg_temp._it(v_cv2, v_lang, 2));
    v_fp := public.preview_fingerprint_register_physical_cards(v_items, v_col, v_sc1);

    v_out := public.register_physical_cards_bulk(
                 pg_temp._req(gen_random_uuid(), v_fp, v_items, v_col, v_sc1));
    v_ids := v_out -> 'result_summary' -> 'physical_card_ids';

    PERFORM pg_temp._rec('A','A03 - multiplicidade SOMENTE por quantity: 3 + 2 produz exatamente 5 Physical Cards e 2 itens distintos',
        v_out ->> 'outcome' = 'CREATED'
        AND (v_out -> 'result_summary' ->> 'created_count')::int = 5
        AND jsonb_array_length(v_ids) = 5
        AND (v_out -> 'result_summary' ->> 'distinct_items')::int = 2,
        format('outcome=%s created=%s ids=%s distinct=%s',
               v_out ->> 'outcome',
               v_out -> 'result_summary' ->> 'created_count',
               jsonb_array_length(v_ids),
               v_out -> 'result_summary' ->> 'distinct_items'),
        'CREATED / created=5 / ids=5 / distinct=2');

    SELECT count(*) INTO v_alloc
      FROM public.collection_allocation ca WHERE ca.collection_id = v_col;

    PERFORM pg_temp._rec('A','A04 - Storage e Collection aplicados as 5 linhas, em uma unica operacao',
        v_alloc = 5
        AND (SELECT count(*) FROM public.physical_card pc
              WHERE pc.id = ANY (SELECT (jsonb_array_elements_text(v_ids))::uuid)
                AND pc.storage_container_id = v_sc1
                AND pc.inventory_id = v_inv) = 5,
        format('alocadas=%s com_storage=%s', v_alloc,
               (SELECT count(*) FROM public.physical_card pc
                 WHERE pc.id = ANY (SELECT (jsonb_array_elements_text(v_ids))::uuid)
                   AND pc.storage_container_id = v_sc1)),
        'alocadas=5 com_storage=5');

    -- TETO EXATO: 500 + 500 = 1000 tem de ser ACEITO.
    v_items := jsonb_build_array(pg_temp._it(v_cv1, v_lang, 500), pg_temp._it(v_cv2, v_lang, 500));
    v_fp := public.preview_fingerprint_register_physical_cards(v_items);

    v_out := public.register_physical_cards_bulk(
                 pg_temp._req(gen_random_uuid(), v_fp, v_items));

    PERFORM pg_temp._rec('A','A05 - TOTAL EXPANDIDO de EXATAMENTE 1000 e ACEITO (o teto e inclusivo)',
        v_out ->> 'outcome' = 'CREATED'
        AND (v_out -> 'result_summary' ->> 'created_count')::int = 1000
        AND jsonb_array_length(v_out -> 'result_summary' -> 'physical_card_ids') = 1000,
        format('outcome=%s created=%s ids=%s',
               v_out ->> 'outcome',
               v_out -> 'result_summary' ->> 'created_count',
               jsonb_array_length(v_out -> 'result_summary' -> 'physical_card_ids')),
        'CREATED / created=1000 / ids=1000');

    -- ELEGIBILIDADE CARD_SET com cv_other (outro Card Set, MESMO Game:
    -- passa no Game e tem de barrar na elegibilidade), COM LISTA.
    SELECT count(*) INTO v_before FROM public.physical_card WHERE inventory_id = v_inv;

    v_items := jsonb_build_array(pg_temp._it(v_other, v_lang, 4));
    v_fp := public.preview_fingerprint_register_physical_cards(v_items, v_ref);

    PERFORM pg_temp._expect_error('A','A06 - elegibilidade CARD_SET barra cv_other_set COM LISTA (passa no Game, falha na referencia)',
        format(v_call, pg_temp._req(gen_random_uuid(), v_fp, v_items, v_ref)::text),
        'nao pertence(m) ao Card Set referenciado pela Collection: ' || v_other);

    SELECT count(*) INTO v_after FROM public.physical_card WHERE inventory_id = v_inv;
    IF v_after <> v_before THEN
        PERFORM pg_temp._rec('A','A-ABORT - A06 escreveu apesar de falhar', FALSE,
            format('antes=%s depois=%s', v_before, v_after), 'antes = depois');
    END IF;
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp._rec('A','A-ABORT - grupo A abortou', FALSE, SQLERRM, 'sem excecao');
END;
$A$;

-- ================================================================
-- GRUPO I — IDEMPOTÊNCIA
-- ================================================================
DO $I$
DECLARE
    v_u1   UUID := pg_temp._fx('u1');
    v_cv1  TEXT := pg_temp._fx('cv1')::text;
    v_cv2  TEXT := pg_temp._fx('cv2')::text;
    v_lang TEXT := pg_temp._fx('lang')::text;
    v_inv  UUID := pg_temp._fx('inv1');
    v_key  UUID := gen_random_uuid();
    v_p1 JSONB; v_p2 JSONB;
    v_fp1 TEXT; v_fp2 TEXT;
    v_a JSONB; v_b JSONB;
    v_before INT; v_after INT;
    v_call TEXT := 'SELECT public.register_physical_cards_bulk(%L::jsonb)';
BEGIN
    PERFORM pg_temp._as(v_u1);

    -- MESMA intencao, ordem dos itens INVERTIDA e um UUID em CAIXA ALTA.
    v_p1 := jsonb_build_array(pg_temp._it(v_cv1, v_lang, 2), pg_temp._it(v_cv2, v_lang, 1));
    v_p2 := jsonb_build_array(pg_temp._it(v_cv2, v_lang, 1), pg_temp._it(upper(v_cv1), v_lang, 2));

    v_fp1 := public.preview_fingerprint_register_physical_cards(v_p1);

    v_a := public.register_physical_cards_bulk(pg_temp._req(v_key, v_fp1, v_p1));

    PERFORM pg_temp._rec('I','I01 - primeira chamada devolve CREATED com 3 Physical Cards',
        v_a ->> 'outcome' = 'CREATED'
        AND (v_a -> 'result_summary' ->> 'created_count')::int = 3,
        format('outcome=%s created=%s', v_a ->> 'outcome',
               v_a -> 'result_summary' ->> 'created_count'),
        'CREATED / created=3');

    SELECT count(*) INTO v_before FROM public.physical_card WHERE inventory_id = v_inv;

    -- REPLAY: mesma chave, MESMA intencao (reordenada e com caixa
    -- diferente) e preview_fingerprint DIFERENTE de proposito — o
    -- replay NAO valida fingerprint (D9).
    v_b := public.register_physical_cards_bulk(
               pg_temp._req(v_key, 'fp-COMPLETAMENTE-DIFERENTE', v_p2));

    SELECT count(*) INTO v_after FROM public.physical_card WHERE inventory_id = v_inv;

    PERFORM pg_temp._rec('I','I02 - mesma intencao com JSON REORDENADO e UUID em outra CAIXA devolve REPLAY (hash canonico server-side)',
        v_b ->> 'outcome' = 'REPLAY',
        format('outcome=%s', v_b ->> 'outcome'), 'REPLAY');

    PERFORM pg_temp._rec('I','I03 - REPLAY devolve o resultado JA COMPROMETIDO, identico ao da primeira chamada, mesmo com fingerprint diferente (D9)',
        (v_b -> 'result_summary') = (v_a -> 'result_summary')
        AND (v_b ->> 'operation_id') = (v_a ->> 'operation_id'),
        format('result_igual=%s operation_id_igual=%s',
               (v_b -> 'result_summary') = (v_a -> 'result_summary'),
               (v_b ->> 'operation_id') = (v_a ->> 'operation_id')),
        'ambos true');

    PERFORM pg_temp._rec('I','I04 - REPLAY tem ZERO escrita: nenhuma Physical Card nova',
        v_after = v_before,
        format('antes=%s depois=%s', v_before, v_after), 'antes = depois');

    PERFORM pg_temp._expect_error('I','I05 - mesma idempotency_key com intencao DIFERENTE falha com BULK_IDEMPOTENCY_CONFLICT',
        format(v_call, pg_temp._req(v_key, v_fp1,
            jsonb_build_array(pg_temp._it(v_cv1, v_lang, 9)))::text),
        'BULK_IDEMPOTENCY_CONFLICT');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp._rec('I','I-ABORT - grupo I abortou', FALSE, SQLERRM, 'sem excecao');
END;
$I$;

-- ================================================================
-- X02 — o harness escreveu de fato
-- ================================================================
DO $X2$
DECLARE v_base BIGINT; v_now BIGINT;
BEGIN
    SELECT n INTO v_base FROM _bl WHERE k = 'physical_card';
    SELECT count(*) INTO v_now FROM public.physical_card;
    PERFORM pg_temp._rec('X','X02 - o harness ESCREVEU de fato (physical_card acima do baseline); zero residuo REAL e provado na CALL 3, pos-ROLLBACK, NAO aqui',
        v_now > v_base, format('baseline=%s fim=%s', v_base, v_now),
        'physical_card no fim > baseline');
END;
$X2$;

-- ================================================================
-- RELATÓRIO FINAL — gate fail-closed + baseline para a CALL 3
-- ================================================================
SELECT
    count(*)                                           AS total,
    count(*) FILTER (WHERE passed)                     AS pass,
    count(*) FILTER (WHERE NOT passed)                 AS fail,
    0                                                  AS not_proven,
    (count(*) = 64 AND count(*) FILTER (WHERE NOT passed) = 0)
                                                       AS gate_ok,
    (SELECT jsonb_object_agg(k, n) FROM _bl)           AS baseline,
    jsonb_agg(jsonb_build_object('grupo', grp, 'caso', label,
                                 'got', got, 'want', want)
              ORDER BY grp, label)
        FILTER (WHERE NOT passed)                      AS failing_cases
FROM _r;

ROLLBACK;

/*
================================================================
APÓS O ROLLBACK — CALL 3, POSTCHECK BASELINE-RELATIVO
================================================================
SELECT (SELECT count(*) FROM public.bulk_operation)                 AS bulk_operation,
       (SELECT count(*) FROM public.physical_card)                  AS physical_card,
       (SELECT count(*) FROM public.collection_allocation)          AS collection_allocation,
       (SELECT count(*) FROM public.collection)                     AS collection,
       (SELECT count(*) FROM public.collection_reference)           AS collection_reference,
       (SELECT count(*) FROM public.collection_card_set_reference)  AS collection_card_set_reference,
       (SELECT count(*) FROM public.storage_container)              AS storage_container,
       (SELECT count(*) FROM public.inventory)                      AS inventory;

Critério: cada uma destas OITO contagens tem de ser IGUAL ao valor
correspondente na coluna `baseline` do relatório da CALL 1. Não é
"tudo zero" — é igualdade com o estado anterior ao harness.
================================================================
*/
