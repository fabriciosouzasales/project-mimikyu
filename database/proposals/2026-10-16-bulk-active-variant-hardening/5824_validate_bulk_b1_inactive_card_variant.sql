/*
================================================================
Query 5824 — validação de 5152 (Bulk B1 × Card Variant inativa)
================================================================
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO — offline (RUN-PASS) e LIVE em
              2026-10-16, apos 5152 (ledger 20261016234129): gate
              30/29/0/1, GATE OK. K01 = NOT PROVEN / ACCEPTED RISK.
              Substituida por v1.1 (pasta 2026-10-16-bulk-04-...) a
              partir de 5155.
Frente......: COLLECTION-BULK-ACTIVE-VARIANT-HARDENING-01
Valida......: 5152_harden_bulk_b1_inactive_card_variant.sql
Pré-req.....: 5152 APLICADA. 5142-5151, 2268-2270 aplicadas.
Executor....: postgres (como 5822/5823). Escreve fixtures e alterna
              card_variant.is_active DENTRO da própria transação; o
              relatório final sai por RAISE EXCEPTION, que força o
              ROLLBACK por construção (mesmo transporte de 5823).

================================================================
GATE OBRIGATÓRIO
================================================================
    TOTAL 30 / PASS 29 / FAIL 0 / NOT PROVEN 1

O único NOT PROVEN admitido é K01 (corrida entre a validação 6.2b e o
INSERT, que exige duas sessões persistentes). Qualquer outro caso que
não rode é FAIL.

================================================================
GRUPOS
================================================================
  X (2)  baseline e prova de escrita
  F (2)  fixtures: usuário, inventory, idioma, 3 variantes ativas e
         não-padrão (cv_a, cv_off, cv_rep); cv_off desativada
  E (8)  estrutura estática das 3 funções, I9, ACL e trigger 2268
  A (3)  variante ATIVA: preview ok, confirmação CREATED, sem issue novo
  P (4)  variante INATIVA no preview: issue BLOCKING, offenders exatos,
         sem fingerprint, item misto
  C (3)  variante INATIVA na confirmação: erro contratual com lista,
         nenhuma escrita, claim revertido
  T (3)  fingerprint reflete is_active; ativa→inativa após o preview
         dá PREVIEW_STALE sem escrita
  I (2)  idempotência: REPLAY sem duplicar; REPLAY sobrevive à
         desativação posterior (D9)
  R (2)  regressão do fingerprint: estável, independente de ordem e de
         quantity
  K (1)  concorrência validação×INSERT — NOT PROVEN (runbook no README)
================================================================
*/

BEGIN;

CREATE TEMP TABLE _r (
    grp    TEXT NOT NULL,
    label  TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('PASS','FAIL','NOT PROVEN')),
    got    TEXT,
    want   TEXT
) ON COMMIT DROP;

CREATE TEMP TABLE _fx (k TEXT PRIMARY KEY, v UUID) ON COMMIT DROP;
CREATE TEMP TABLE _tx (k TEXT PRIMARY KEY, v TEXT) ON COMMIT DROP;

CREATE FUNCTION pg_temp._rec(p_grp TEXT, p_label TEXT, p_passed BOOLEAN, p_got TEXT, p_want TEXT)
RETURNS VOID LANGUAGE sql AS $$
    INSERT INTO _r VALUES (p_grp, p_label,
        CASE WHEN COALESCE(p_passed, FALSE) THEN 'PASS' ELSE 'FAIL' END, p_got, p_want);
$$;

CREATE FUNCTION pg_temp._np(p_grp TEXT, p_label TEXT, p_why TEXT)
RETURNS VOID LANGUAGE sql AS $$
    INSERT INTO _r VALUES (p_grp, p_label, 'NOT PROVEN', p_why, 'prova externa');
$$;

CREATE FUNCTION pg_temp._fx(p_k TEXT) RETURNS UUID LANGUAGE sql STABLE AS $$
    SELECT v FROM _fx WHERE k = p_k;
$$;

CREATE FUNCTION pg_temp._as(p_uid UUID) RETURNS VOID LANGUAGE sql AS $$
    SELECT set_config('request.jwt.claims',
        json_build_object('sub', p_uid::text, 'role', 'authenticated')::text, TRUE);
$$;

CREATE FUNCTION pg_temp._it(p_cv UUID, p_lang UUID, p_qty INT)
RETURNS JSONB LANGUAGE sql IMMUTABLE AS $$
    SELECT jsonb_build_object('card_variant_id', p_cv::text,
                              'language_id',     p_lang::text,
                              'quantity',        p_qty);
$$;

CREATE FUNCTION pg_temp._preq(p_items JSONB) RETURNS JSONB LANGUAGE sql IMMUTABLE AS $$
    SELECT jsonb_build_object('operation_type', 'REGISTER_PHYSICAL_CARDS', 'items', p_items);
$$;

CREATE FUNCTION pg_temp._xreq(p_key UUID, p_fp TEXT, p_items JSONB) RETURNS JSONB LANGUAGE sql IMMUTABLE AS $$
    SELECT jsonb_build_object('idempotency_key', p_key::text,
                              'preview_fingerprint', p_fp,
                              'items', p_items);
$$;

-- Issue BLOCKING por code; devolve o objeto (ou NULL).
CREATE FUNCTION pg_temp._issue(p_res JSONB, p_code TEXT) RETURNS JSONB LANGUAGE sql IMMUTABLE AS $$
    SELECT i.e FROM jsonb_array_elements(p_res -> 'issues') AS i(e)
     WHERE i.e ->> 'code' = p_code AND i.e ->> 'severity' = 'BLOCKING'
     LIMIT 1;
$$;

-- Executa e captura (SQLSTATE, mensagem). Subtransação: o que a
-- chamada escreveu antes de falhar é desfeito, como em produção.
CREATE FUNCTION pg_temp._try(p_sql TEXT, OUT o_state TEXT, OUT o_msg TEXT, OUT o_res JSONB)
LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        EXECUTE p_sql INTO o_res;
        o_state := '00000';
    EXCEPTION WHEN OTHERS THEN
        o_state := SQLSTATE; o_msg := SQLERRM;
    END;
END;
$$;

CREATE FUNCTION pg_temp._pc() RETURNS BIGINT LANGUAGE sql STABLE AS $$
    SELECT count(*) FROM public.physical_card;
$$;

CREATE FUNCTION pg_temp._bo() RETURNS BIGINT LANGUAGE sql STABLE AS $$
    SELECT count(*) FROM public.bulk_operation;
$$;

-- ================================================================
-- X01 — baseline
-- ================================================================
INSERT INTO _tx VALUES
    ('pc0', (SELECT count(*)::text FROM public.physical_card)),
    ('bo0', (SELECT count(*)::text FROM public.bulk_operation)),
    ('inactive0', (SELECT count(*)::text FROM public.card_variant WHERE NOT is_active));

SELECT pg_temp._rec('X','X01 - baseline capturado antes de qualquer escrita (physical_card, bulk_operation, variantes inativas)',
    (SELECT count(*) FROM _tx) = 3,
    (SELECT string_agg(k || '=' || v, ' ' ORDER BY k) FROM _tx), '3 contagens');

-- ================================================================
-- F — FIXTURES
-- ================================================================
DO $F$
DECLARE v_u1 UUID; v_inv UUID; v_lang UUID; v_cv UUID[];
BEGIN
    SELECT id INTO v_u1 FROM auth.users ORDER BY created_at, id LIMIT 1;
    SELECT id INTO v_lang FROM public.language ORDER BY id LIMIT 1;

    -- Três variantes ATIVAS e NÃO-padrão (o CHECK de 2268 impede
    -- desativar a padrão), em cartas distintas.
    SELECT array_agg(x.id ORDER BY x.id) INTO v_cv FROM (
        SELECT DISTINCT ON (cv.card_id) cv.id
          FROM public.card_variant cv
         WHERE cv.is_active AND NOT cv.is_default
         ORDER BY cv.card_id, cv.id
         LIMIT 3) x;

    PERFORM pg_temp._as(v_u1);
    SELECT inv.id INTO v_inv FROM public.inventory inv WHERE inv.owner_user_id = v_u1;
    IF v_inv IS NULL THEN
        INSERT INTO public.inventory (owner_user_id) VALUES (v_u1) RETURNING id INTO v_inv;
    END IF;

    INSERT INTO _fx VALUES ('u1', v_u1), ('inv', v_inv), ('lang', v_lang),
        ('cv_a', v_cv[1]), ('cv_off', v_cv[2]), ('cv_rep', v_cv[3]);

    PERFORM pg_temp._rec('F','F01 - fixture: usuario, inventory, idioma e 3 variantes ativas nao-padrao distintas',
        v_u1 IS NOT NULL AND v_inv IS NOT NULL AND v_lang IS NOT NULL
        AND cardinality(v_cv) = 3,
        format('u1=%s inv=%s lang=%s cvs=%s', v_u1 IS NOT NULL, v_inv IS NOT NULL,
               v_lang IS NOT NULL, cardinality(v_cv)),
        'tudo presente, 3 variantes');

    UPDATE public.card_variant SET is_active = FALSE WHERE id = v_cv[2];

    PERFORM pg_temp._rec('F','F02 - cv_off desativada dentro da transacao do harness',
        (SELECT NOT is_active AND NOT is_default FROM public.card_variant WHERE id = v_cv[2]),
        'cv_off is_active=false', 'inativa e nao-padrao');
END;
$F$;

-- ================================================================
-- E — ESTRUTURA
-- ================================================================
DO $E$
DECLARE v49 TEXT; v50 TEXT; v51 TEXT; o49 OID; o50 OID; o51 OID;
BEGIN
    SELECT p.oid, p.prosrc INTO o49, v49 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'preview_fingerprint_register_physical_cards';
    SELECT p.oid, p.prosrc INTO o50, v50 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'register_physical_cards_bulk';
    SELECT p.oid, p.prosrc INTO o51, v51 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'preview_bulk_operation';

    PERFORM pg_temp._rec('E','E01 - 5149 inclui is_active no catalogo do fingerprint',
        position('''is_active'',       cv.is_active' in v49) > 0, NULL, 'chave is_active presente');

    PERFORM pg_temp._rec('E','E02 - 5150 valida CARD_VARIANT_INACTIVE ANTES do INSERT em physical_card',
        position('CARD_VARIANT_INACTIVE' in v50) > 0
        AND position('CARD_VARIANT_INACTIVE' in v50) < position('INSERT INTO public.physical_card' in v50),
        format('check=%s insert=%s', position('CARD_VARIANT_INACTIVE' in v50),
               position('INSERT INTO public.physical_card' in v50)), 'check < insert');

    PERFORM pg_temp._rec('E','E03 - 5151 emite issue CARD_VARIANT_INACTIVE',
        position('''CARD_VARIANT_INACTIVE''' in v51) > 0, NULL, 'code presente');

    PERFORM pg_temp._rec('E','E04 - I9 preservado: 5150 continua sem FOR UPDATE/FOR SHARE proprio e usa 5148',
        position('FOR UPDATE' in v50) = 0 AND position('FOR SHARE' in v50) = 0
        AND position('bulk_lock_operation_scope' in v50) > 0, NULL, 'sem lock proprio');

    PERFORM pg_temp._rec('E','E05 - 5151 continua sem DML e sem lock',
        position('insert into' in lower(v51)) = 0 AND position('update public' in lower(v51)) = 0
        AND position('delete from' in lower(v51)) = 0 AND position('for update' in lower(v51)) = 0
        AND position('for share' in lower(v51)) = 0, NULL, 'consultivo');

    PERFORM pg_temp._rec('E','E06 - atributos inalterados: 5149 INVOKER/VOLATILE; 5150 DEFINER; 5151 DEFINER/VOLATILE; search_path vazio nas tres',
        (SELECT NOT prosecdef AND provolatile = 'v' FROM pg_proc WHERE oid = o49)
        AND (SELECT prosecdef FROM pg_proc WHERE oid = o50)
        AND (SELECT prosecdef AND provolatile = 'v' FROM pg_proc WHERE oid = o51)
        AND (SELECT bool_and(EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%'))
               FROM pg_proc p WHERE p.oid IN (o49, o50, o51)),
        NULL, 'atributos de 5149/5150/5151');

    PERFORM pg_temp._rec('E','E07 - ACL inalterada: authenticated executa 5150/5151 e NAO 5149; anon nao executa nenhuma',
        has_function_privilege('authenticated', o50, 'EXECUTE')
        AND has_function_privilege('authenticated', o51, 'EXECUTE')
        AND NOT has_function_privilege('authenticated', o49, 'EXECUTE')
        AND NOT has_function_privilege('anon', o49, 'EXECUTE')
        AND NOT has_function_privilege('anon', o50, 'EXECUTE')
        AND NOT has_function_privilege('anon', o51, 'EXECUTE'),
        NULL, 'matriz de EXECUTE');

    PERFORM pg_temp._rec('E','E08 - trigger 2268 intacto em physical_card (BEFORE INSERT, habilitado)',
        EXISTS (SELECT 1 FROM pg_trigger t
                 WHERE t.tgrelid = 'public.physical_card'::regclass
                   AND t.tgname = 'trg_guard_card_variant_active'
                   AND NOT t.tgisinternal AND t.tgenabled = 'O'
                   AND (t.tgtype & 2) = 2 AND (t.tgtype & 4) = 4),
        NULL, 'BEFORE INSERT, enabled');
END;
$E$;

-- ================================================================
-- A — VARIANTE ATIVA
-- ================================================================
DO $A$
DECLARE v_items JSONB; v_res JSONB; v_x JSONB; v_pc0 BIGINT;
BEGIN
    PERFORM pg_temp._as(pg_temp._fx('u1'));
    v_items := jsonb_build_array(pg_temp._it(pg_temp._fx('cv_a'), pg_temp._fx('lang'), 2));

    v_res := public.preview_bulk_operation(pg_temp._preq(v_items));
    PERFORM pg_temp._rec('A','A01 - preview de variante ativa: ok=true e fingerprint emitido',
        (v_res ->> 'ok')::boolean AND (v_res ->> 'preview_fingerprint') IS NOT NULL,
        v_res::text, 'ok=true, fingerprint NOT NULL');
    PERFORM pg_temp._rec('A','A02 - variante ativa NAO gera issue CARD_VARIANT_INACTIVE',
        pg_temp._issue(v_res, 'CARD_VARIANT_INACTIVE') IS NULL, NULL, 'sem issue');

    v_pc0 := pg_temp._pc();
    v_x := public.register_physical_cards_bulk(
               pg_temp._xreq(gen_random_uuid(), v_res ->> 'preview_fingerprint', v_items));
    PERFORM pg_temp._rec('A','A03 - confirmacao de variante ativa: CREATED com 2 Physical Cards',
        v_x ->> 'outcome' = 'CREATED' AND (v_x -> 'result_summary' ->> 'created_count')::int = 2
        AND pg_temp._pc() - v_pc0 = 2,
        format('outcome=%s delta=%s', v_x ->> 'outcome', pg_temp._pc() - v_pc0), 'CREATED, delta 2');
END;
$A$;

-- ================================================================
-- P — VARIANTE INATIVA NO PREVIEW
-- ================================================================
DO $P$
DECLARE v_res JSONB; v_i JSONB;
BEGIN
    PERFORM pg_temp._as(pg_temp._fx('u1'));

    v_res := public.preview_bulk_operation(pg_temp._preq(
                 jsonb_build_array(pg_temp._it(pg_temp._fx('cv_off'), pg_temp._fx('lang'), 1))));
    v_i := pg_temp._issue(v_res, 'CARD_VARIANT_INACTIVE');

    PERFORM pg_temp._rec('P','P01 - preview de variante inativa: ok=false com issue BLOCKING CARD_VARIANT_INACTIVE',
        NOT (v_res ->> 'ok')::boolean AND v_i IS NOT NULL, v_res::text, 'ok=false + issue');
    PERFORM pg_temp._rec('P','P02 - preview reprovado NAO emite fingerprint',
        (v_res ->> 'preview_fingerprint') IS NULL, v_res ->> 'preview_fingerprint', 'NULL');

    v_res := public.preview_bulk_operation(pg_temp._preq(jsonb_build_array(
                 pg_temp._it(pg_temp._fx('cv_a'),   pg_temp._fx('lang'), 1),
                 pg_temp._it(pg_temp._fx('cv_off'), pg_temp._fx('lang'), 1))));
    v_i := pg_temp._issue(v_res, 'CARD_VARIANT_INACTIVE');

    PERFORM pg_temp._rec('P','P03 - item misto: offenders contem EXATAMENTE a variante inativa',
        v_i -> 'offenders' = jsonb_build_array(pg_temp._fx('cv_off')::text),
        v_i::text, format('offenders = ["%s"]', pg_temp._fx('cv_off')));
    PERFORM pg_temp._rec('P','P04 - resumo continua presente com ok=false (contrato do Preview)',
        (v_res -> 'summary' ->> 'distinct_items')::int = 2, v_res -> 'summary' ->> 'distinct_items', '2');
END;
$P$;

-- ================================================================
-- C — VARIANTE INATIVA NA CONFIRMACAO
--     O fingerprint vem de 5149 sobre o estado JA inativo: assim a
--     chamada passa pelo PREVIEW_STALE e chega a validacao 6.2b, que
--     e o que este grupo prova.
-- ================================================================
DO $C$
DECLARE v_items JSONB; v_fp TEXT; v_key UUID := gen_random_uuid();
        v_t RECORD; v_pc0 BIGINT; v_bo0 BIGINT;
BEGIN
    PERFORM pg_temp._as(pg_temp._fx('u1'));
    v_items := jsonb_build_array(
        pg_temp._it(pg_temp._fx('cv_a'),   pg_temp._fx('lang'), 1),
        pg_temp._it(pg_temp._fx('cv_off'), pg_temp._fx('lang'), 3));
    v_fp := public.preview_fingerprint_register_physical_cards(v_items, NULL, NULL);
    v_pc0 := pg_temp._pc(); v_bo0 := pg_temp._bo();

    SELECT * INTO v_t FROM pg_temp._try(format(
        'SELECT public.register_physical_cards_bulk(%L::jsonb)', pg_temp._xreq(v_key, v_fp, v_items)));

    PERFORM pg_temp._rec('C','C01 - confirmacao com variante inativa: excecao 22023 CARD_VARIANT_INACTIVE',
        v_t.o_state = '22023' AND position('CARD_VARIANT_INACTIVE' in v_t.o_msg) > 0,
        format('SQLSTATE=%s | %s', v_t.o_state, v_t.o_msg), '22023 + CARD_VARIANT_INACTIVE');
    PERFORM pg_temp._rec('C','C02 - mensagem traz contagem e o id ofensor (lista do contrato), sem o id ativo',
        position('1 card_variant_id' in v_t.o_msg) > 0
        AND position(pg_temp._fx('cv_off')::text in v_t.o_msg) > 0
        AND position(pg_temp._fx('cv_a')::text in v_t.o_msg) = 0,
        v_t.o_msg, 'contagem 1 + cv_off');
    PERFORM pg_temp._rec('C','C03 - nenhuma escrita: physical_card inalterado e claim revertido (chave reutilizavel)',
        pg_temp._pc() = v_pc0 AND pg_temp._bo() = v_bo0,
        format('dpc=%s dbo=%s', pg_temp._pc() - v_pc0, pg_temp._bo() - v_bo0), '0 e 0');
END;
$C$;

-- ================================================================
-- T — FINGERPRINT × is_active
-- ================================================================
DO $T$
DECLARE v_items JSONB; v_fp_off TEXT; v_fp_on TEXT; v_res JSONB; v_t RECORD; v_pc0 BIGINT;
BEGIN
    PERFORM pg_temp._as(pg_temp._fx('u1'));
    v_items := jsonb_build_array(pg_temp._it(pg_temp._fx('cv_off'), pg_temp._fx('lang'), 1));

    v_fp_off := public.preview_fingerprint_register_physical_cards(v_items, NULL, NULL);
    UPDATE public.card_variant SET is_active = TRUE WHERE id = pg_temp._fx('cv_off');
    v_fp_on  := public.preview_fingerprint_register_physical_cards(v_items, NULL, NULL);

    PERFORM pg_temp._rec('T','T01 - fingerprint muda quando is_active muda',
        v_fp_off IS DISTINCT FROM v_fp_on, NULL, 'fp(inativa) <> fp(ativa)');

    -- Preview com a variante ATIVA, depois desativa e confirma.
    v_res := public.preview_bulk_operation(pg_temp._preq(v_items));
    UPDATE public.card_variant SET is_active = FALSE WHERE id = pg_temp._fx('cv_off');
    v_pc0 := pg_temp._pc();

    SELECT * INTO v_t FROM pg_temp._try(format(
        'SELECT public.register_physical_cards_bulk(%L::jsonb)',
        pg_temp._xreq(gen_random_uuid(), v_res ->> 'preview_fingerprint', v_items)));

    PERFORM pg_temp._rec('T','T02 - ativa no preview e desativada antes da confirmacao: PREVIEW_STALE',
        (v_res ->> 'ok')::boolean AND v_t.o_state = '22023' AND position('PREVIEW_STALE' in v_t.o_msg) > 0,
        format('preview_ok=%s SQLSTATE=%s | %s', v_res ->> 'ok', v_t.o_state, v_t.o_msg),
        'preview ok, depois PREVIEW_STALE');
    PERFORM pg_temp._rec('T','T03 - PREVIEW_STALE nao escreve nada',
        pg_temp._pc() = v_pc0, (pg_temp._pc() - v_pc0)::text, '0');
END;
$T$;

-- ================================================================
-- I — IDEMPOTENCIA
-- ================================================================
DO $I$
DECLARE v_items JSONB; v_res JSONB; v_req JSONB; v_x1 JSONB; v_x2 JSONB; v_x3 JSONB; v_pc0 BIGINT;
BEGIN
    PERFORM pg_temp._as(pg_temp._fx('u1'));
    v_items := jsonb_build_array(pg_temp._it(pg_temp._fx('cv_rep'), pg_temp._fx('lang'), 3));
    v_res := public.preview_bulk_operation(pg_temp._preq(v_items));
    v_req := pg_temp._xreq(gen_random_uuid(), v_res ->> 'preview_fingerprint', v_items);

    v_pc0 := pg_temp._pc();
    v_x1 := public.register_physical_cards_bulk(v_req);
    v_x2 := public.register_physical_cards_bulk(v_req);

    PERFORM pg_temp._rec('I','I01 - mesma chave: CREATED e depois REPLAY com o mesmo operation_id, sem duplicar',
        v_x1 ->> 'outcome' = 'CREATED' AND v_x2 ->> 'outcome' = 'REPLAY'
        AND v_x1 ->> 'operation_id' = v_x2 ->> 'operation_id'
        AND pg_temp._pc() - v_pc0 = 3,
        format('%s/%s delta=%s', v_x1 ->> 'outcome', v_x2 ->> 'outcome', pg_temp._pc() - v_pc0),
        'CREATED/REPLAY delta 3');

    -- D9: desativar DEPOIS nao invalida o replay da operacao concluida.
    UPDATE public.card_variant SET is_active = FALSE WHERE id = pg_temp._fx('cv_rep');
    v_x3 := public.register_physical_cards_bulk(v_req);

    PERFORM pg_temp._rec('I','I02 - replay apos desativar a variante continua REPLAY (D9), sem escrita nova',
        v_x3 ->> 'outcome' = 'REPLAY' AND v_x3 ->> 'operation_id' = v_x1 ->> 'operation_id'
        AND pg_temp._pc() - v_pc0 = 3,
        format('%s delta=%s', v_x3 ->> 'outcome', pg_temp._pc() - v_pc0), 'REPLAY delta 3');
END;
$I$;

-- ================================================================
-- R — REGRESSAO DO FINGERPRINT (variante ativa)
-- ================================================================
DO $R$
DECLARE v1 TEXT; v2 TEXT; v3 TEXT; v4 TEXT; v_l UUID; v_a UUID; v_b UUID;
BEGIN
    PERFORM pg_temp._as(pg_temp._fx('u1'));
    v_l := pg_temp._fx('lang'); v_a := pg_temp._fx('cv_a');
    -- segunda variante ativa: cv_off reativada so para este grupo
    v_b := pg_temp._fx('cv_off');
    UPDATE public.card_variant SET is_active = TRUE WHERE id = v_b;

    v1 := public.preview_fingerprint_register_physical_cards(
              jsonb_build_array(pg_temp._it(v_a, v_l, 1), pg_temp._it(v_b, v_l, 1)), NULL, NULL);
    v2 := public.preview_fingerprint_register_physical_cards(
              jsonb_build_array(pg_temp._it(v_a, v_l, 1), pg_temp._it(v_b, v_l, 1)), NULL, NULL);
    v3 := public.preview_fingerprint_register_physical_cards(
              jsonb_build_array(pg_temp._it(v_b, v_l, 1), pg_temp._it(v_a, v_l, 1)), NULL, NULL);
    v4 := public.preview_fingerprint_register_physical_cards(
              jsonb_build_array(pg_temp._it(v_a, v_l, 7), pg_temp._it(v_b, v_l, 9)), NULL, NULL);

    PERFORM pg_temp._rec('R','R01 - fingerprint estavel em chamadas consecutivas e independente da ordem dos itens',
        v1 = v2 AND v1 = v3, NULL, 'iguais');
    PERFORM pg_temp._rec('R','R02 - quantity nao entra no fingerprint (D9 inalterado)',
        v1 = v4, NULL, 'iguais');

    UPDATE public.card_variant SET is_active = FALSE WHERE id = v_b;
END;
$R$;

-- ================================================================
-- K — CONCORRENCIA
-- ================================================================
SELECT pg_temp._np('K','K01 - desativacao comitada entre a validacao 6.2b e o INSERT: barrada pelo trigger 2268 (MV001) sem resultado parcial',
    'exige duas sessoes persistentes (mesma classe de K01-K03 de 5821); roteiro no README');

-- ================================================================
-- X02 — o harness escreveu de fato (A03 + I01)
-- ================================================================
SELECT pg_temp._rec('X','X02 - o harness escreveu de fato (A03 + I01 = 5 Physical Cards)',
    pg_temp._pc() - (SELECT v::bigint FROM _tx WHERE k = 'pc0') = 5,
    (pg_temp._pc() - (SELECT v::bigint FROM _tx WHERE k = 'pc0'))::text, '5');

-- ================================================================
-- RELATORIO — RAISE EXCEPTION forca o ROLLBACK por construcao.
-- ================================================================
DO $Z$
DECLARE v_total INT; v_pass INT; v_fail INT; v_np INT; v_lines TEXT;
BEGIN
    SELECT count(*), count(*) FILTER (WHERE status = 'PASS'),
           count(*) FILTER (WHERE status = 'FAIL'), count(*) FILTER (WHERE status = 'NOT PROVEN')
      INTO v_total, v_pass, v_fail, v_np FROM _r;
    SELECT string_agg(format('[%s] %s | got=%s | want=%s', status, label, COALESCE(got,''), COALESCE(want,'')),
                      E'\n' ORDER BY grp, label) INTO v_lines FROM _r;
    RAISE EXCEPTION E'5824 GATE: TOTAL % / PASS % / FAIL % / NOT PROVEN % — %\n%',
        v_total, v_pass, v_fail, v_np,
        CASE WHEN v_total = 30 AND v_pass = 29 AND v_fail = 0 AND v_np = 1 THEN 'GATE OK' ELSE 'GATE FALHOU' END,
        v_lines;
END;
$Z$;

ROLLBACK;
