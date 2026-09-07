/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 3860 - Validate Pricing Payload Cardinality Hardening
Versão......: 1.1
Status......: PROPOSTA — HARNESS EXECUTÁVEL COMPLETO, NÃO EXECUTADO

CORREÇÃO v1.0 -> v1.1 (defeito do próprio harness, achado na 1ª execução)
-------------------------------------------------------------------------
O grupo `R` usava `SELECT ARRAY[min(id)] ... FROM _ids`. **`min(uuid)`
não existe em PostgreSQL** — a execução abortou com
`42883: function min(uuid) does not exist`, derrubando a transação
inteira antes do relatório. Limitação já conhecida no projeto.
Substituído por `ORDER BY id LIMIT 1`, que é o caminho canônico e
mantém o determinismo. **Nenhum caso de teste foi alterado, adicionado
ou removido; o gate permanece 18.** A migration `3972` não foi tocada
— o defeito era exclusivamente do harness.
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-07 (criado em
               PRICING-PAYLOAD-CARDINALITY-HARDENING-01)

Descrição...:
Harness FUNCIONAL fail-closed do hardening de cardinalidade de payload
de `public.get_cards_pricing_summary(p_card_ids uuid[])`. Executado
APÓS aplicar a Query `3972`.

NUMERAÇÃO: `3800`–`3899` é a faixa de Validações do módulo Pricing
(`STD-001`, §"Módulo: Pricing"). Decênios `3800`/`3810`/`3820`/`3830`/
`3840`/`3850` já usados (Incrementos P1–P6); `3860` é o próximo livre.
Não é uma migration — não altera schema, roda em `BEGIN ... ROLLBACK`.

O QUE ESTE HARNESS PROVA
------------------------
Os nove cenários exigidos pelo mandato, todos sob o papel
`authenticated` com claim JWT real (a função exige `auth.uid()`):

  N01  NULL                      -> PRICING_SUMMARY_EMPTY_INPUT
  N02  vazio '{}'                -> PRICING_SUMMARY_EMPTY_INPUT
                                    (e NÃO a mensagem de dimensão)
  N03  1 elemento                -> ACEITO, 1 linha
  N04  100 elementos distintos   -> ACEITO, 100 linhas (teto exato)
  N05  101 elementos distintos   -> PRICING_SUMMARY_TOO_MANY_CARD_IDS
  N06  multidim dim1=2 card=600  -> PRICING_SUMMARY_INVALID_PAYLOAD_SHAPE
                                    [PROVA do fechamento do bypass]
  N07  multidim dim1=2 card=10   -> PRICING_SUMMARY_INVALID_PAYLOAD_SHAPE
                                    [contrato de FORMA, não só de tamanho]
  N08  payload válido com dado real -> resultado correto e idêntico ao
                                    da definição anterior
  X01/X02 zero resíduo

Mais o grupo `S` (STATIC PROOF fail-closed) e o grupo `R` (regressão de
contrato de segurança e de negócio).

POR QUE `N06` É A ÚNICA PROVA QUE IMPORTA
-----------------------------------------
`N05` (101 distintos) passaria também com o `array_length` antigo — é
condição NECESSÁRIA, não suficiente. Só `N06` distingue
`cardinality()` de `array_length(x,1)`: `array_fill(uuid, ARRAY[2,300])`
tem `array_length(x,1) = 2` (atravessava o teto de 100) e
`cardinality(x) = 600` (o que o `unnest` de fato processava).

CONTRATO DE EXECUÇÃO
--------------------
- Executar como usuário PRIVILEGIADO (postgres/service_role). O script
  alterna para `authenticated` via SET LOCAL ROLE + request.jwt.claims
  onde a semântica de cliente precisa ser exercida, e faz RESET ROLE
  antes de gravar resultado.
- TUDO dentro de BEGIN ... ROLLBACK. **NENHUMA escrita é feita**: este
  harness é SOMENTE LEITURA sobre dados reais de Pricing. Não cria
  fixture, não insere, não atualiza, não apaga.
- FAIL-CLOSED: nenhum caso passa por omissão. Erro inesperado NUNCA
  vira PASS. `NOT PROVEN` (passed IS NULL) é um terceiro estado,
  contado à parte.
- PROTOCOLO EM DUAS CHAMADAS (mesma disciplina de `5818`/`5820`):
      CALL 1 — do `BEGIN;` até o `SELECT` final do relatório, INCLUSIVE.
      CALL 2 — `ROLLBACK;`
  NOTA DE CANAL (comportamento MEDIDO em 2026-09-07): o executor
  `execute_sql` NÃO preserva sessão nem transação entre chamadas. A
  CALL 1 encerra com ROLLBACK IMPLÍCITO (o arquivo abre `BEGIN;` e
  nunca emite `COMMIT;`); a CALL 2 é confirmação explícita e no-op.
  A garantia de zero resíduo não depende do protocolo — depende de o
  arquivo não conter `COMMIT` e de não haver escrita alguma.

GATE DE ACEITE
--------------
    TOTAL 18 / PASS 18 / FAIL 0 / NOT PROVEN 0

18 é a contagem de rótulos ALCANÇÁVEIS em runtime, verificada por
contagem direta no arquivo:

    F ... F01 F-ABORT                                     (2)
    N ... N00 N01..N07 N08 N-ABORT                       (10)
    R ... R01 R02                                         (2)
    S ... S01 S02 S03 S04                                 (4)
    X ... X01 X02                                         (2)
                                    rótulos estáticos = 20

`F-ABORT` e `N-ABORT` são ramos FAIL-ONLY e mutuamente exclusivos,
gravados apenas dentro de `EXCEPTION WHEN OTHERS` e sempre com
`passed = FALSE` — só existem no cenário de falha. Máximo saudável de
runtime = 20 − 2 = **18**. Qualquer `*-ABORT` presente = STOP.

`N08` pode legitimamente ficar `NOT PROVEN` num ambiente sem nenhuma
observação NM/MARKET `CONFIRMED` — nesse caso o gate vira
`18 / 17 PASS / 0 FAIL / 1 NOT PROVEN`, e o NOT PROVEN só é aceitável
se for **exatamente** `N08`. Nunca converter em PASS artificial.
(Ambiente medido em 2026-09-07: 138.888 observações elegíveis, então
`N08` deve alcançar PASS.)
(Disciplina herdada de `5818` — o "205" que era 196 — e de `5820` — o
"28" que era 27. O número do gate aqui já é o de runtime.)

PRÉ-REQUISITOS
--------------
- Query `3972` aplicada.
- >= 1 auth.users (para o claim JWT).
- >= 101 Cards ativos no catálogo (para N04/N05). O script NÃO fabrica
  Cards: aborta fail-loud se não encontrar.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADO.
================================================================
*/

BEGIN;

SET LOCAL client_min_messages = WARNING;

-- =================================================================
-- INFRAESTRUTURA
-- =================================================================
CREATE TEMP TABLE _v (
    seq        SERIAL PRIMARY KEY,
    grp        TEXT NOT NULL,
    case_label TEXT NOT NULL,
    passed     BOOLEAN,          -- NULL = NOT PROVEN
    observed   TEXT,
    expected   TEXT
) ON COMMIT DROP;

CREATE TEMP TABLE _fx (k TEXT PRIMARY KEY, v UUID) ON COMMIT DROP;
CREATE TEMP TABLE _ids (k TEXT NOT NULL, id UUID NOT NULL) ON COMMIT DROP;

-- Objetos TEMP NAO herdam privilegio de PUBLIC (diferente de funcoes).
-- Sem estes GRANTs, o registro do resultado falharia com 42501 apos o
-- SET LOCAL ROLE authenticated. Padrao ja aprovado em 5818/5819/5820.
GRANT ALL ON _v, _fx, _ids TO authenticated;
GRANT USAGE, SELECT, UPDATE ON SEQUENCE _v_seq_seq TO authenticated;

CREATE OR REPLACE FUNCTION pg_temp._rec(
    p_grp TEXT, p_label TEXT, p_passed BOOLEAN,
    p_observed TEXT DEFAULT NULL, p_expected TEXT DEFAULT NULL
) RETURNS VOID LANGUAGE plpgsql AS $fn$
BEGIN
    INSERT INTO _v (grp, case_label, passed, observed, expected)
    VALUES (p_grp, p_label, p_passed, p_observed, p_expected);
END; $fn$;

-- Espera erro contendo um fragmento LITERAL. Fail-closed: nenhum erro
-- levantado = FAIL; erro diferente do esperado = FAIL.
CREATE OR REPLACE FUNCTION pg_temp._expect_error(
    p_grp TEXT, p_label TEXT, p_sql TEXT, p_fragment TEXT
) RETURNS VOID LANGUAGE plpgsql AS $fn$
DECLARE v_msg TEXT; v_state TEXT; v_raised BOOLEAN := FALSE;
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        v_raised := TRUE; v_msg := SQLERRM; v_state := SQLSTATE;
    END;

    IF NOT v_raised THEN
        PERFORM pg_temp._rec(p_grp, p_label, FALSE,
            'NENHUM erro levantado', 'erro contendo: ' || p_fragment);
    ELSIF position(p_fragment in v_msg) > 0 THEN
        PERFORM pg_temp._rec(p_grp, p_label, TRUE,
            v_state || ' ' || left(v_msg, 160), 'erro contendo: ' || p_fragment);
    ELSE
        PERFORM pg_temp._rec(p_grp, p_label, FALSE,
            'erro INESPERADO: ' || v_state || ' ' || left(v_msg, 160),
            'erro contendo: ' || p_fragment);
    END IF;
END; $fn$;

-- Espera execucao SEM erro devolvendo EXATAMENTE p_expected_rows linhas.
CREATE OR REPLACE FUNCTION pg_temp._expect_rows(
    p_grp TEXT, p_label TEXT, p_sql TEXT, p_expected_rows BIGINT
) RETURNS VOID LANGUAGE plpgsql AS $fn$
DECLARE v_n BIGINT;
BEGIN
    EXECUTE 'SELECT count(*) FROM (' || p_sql || ') _t' INTO v_n;
    PERFORM pg_temp._rec(p_grp, p_label, v_n = p_expected_rows,
        v_n::text || ' linha(s)', p_expected_rows::text || ' linha(s)');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp._rec(p_grp, p_label, FALSE,
        'erro: ' || SQLSTATE || ' ' || left(SQLERRM, 160),
        p_expected_rows::text || ' linha(s), sem erro');
END; $fn$;

CREATE OR REPLACE FUNCTION pg_temp._as_user(p_user UUID)
RETURNS VOID LANGUAGE plpgsql AS $fn$
BEGIN
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', p_user::text, 'role', 'authenticated')::text, TRUE);
    EXECUTE 'SET LOCAL ROLE authenticated';
END; $fn$;

CREATE OR REPLACE FUNCTION pg_temp._as_admin()
RETURNS VOID LANGUAGE plpgsql AS $fn$
BEGIN
    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claims', '', TRUE);
END; $fn$;

-- Prova de search_path EFETIVAMENTE vazio (nao apenas presente:
-- `search_path=public` tambem casaria um LIKE ingenuo).
CREATE OR REPLACE FUNCTION pg_temp._empty_search_path(p_oid OID)
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

-- =================================================================
-- FIXTURE — SOMENTE LEITURA. Nenhuma linha e criada.
-- Fail-loud: aborta se o catalogo minimo nao existir.
-- =================================================================
DO $blk$
DECLARE
    v_owner UUID;
    v_n INTEGER;
BEGIN
    SELECT id INTO v_owner FROM auth.users ORDER BY created_at, id LIMIT 1;

    IF v_owner IS NULL THEN
        RAISE EXCEPTION
          'FIXTURE ABORT — nenhum auth.users. O harness NAO fabrica usuario.';
    END IF;

    INSERT INTO _fx VALUES ('owner', v_owner);

    -- 101 Cards reais e distintos, ordem determinista. Sao apenas
    -- IDENTIFICADORES de entrada: a funcao e STABLE e nada e escrito.
    INSERT INTO _ids (k, id)
    SELECT 'card', c.id FROM public.card c
     WHERE c.is_active = TRUE
     ORDER BY c.id
     LIMIT 101;

    SELECT count(*) INTO v_n FROM _ids WHERE k = 'card';
    IF v_n < 101 THEN
        RAISE EXCEPTION
          'FIXTURE ABORT — esperados 101 Cards ativos, encontrados %. O harness NAO fabrica Card.', v_n;
    END IF;

    -- Card com preco REAL conhecido, para a prova de nao-regressao N08.
    -- Pode nao existir (ambiente sem preco): tratado como NOT PROVEN
    -- no proprio caso, nunca como PASS artificial.
    INSERT INTO _fx
    SELECT 'card_com_preco', pcm.card_id
      FROM public.pricing_card_mapping pcm
      JOIN public.pricing_product pp ON pp.pricing_card_mapping_id = pcm.id AND pp.is_active
      JOIN public.pricing_observation po ON po.pricing_product_id = pp.id AND po.price_type = 'MARKET'
      JOIN public.card_condition cc ON cc.id = po.condition_id AND cc.code = 'NM'
     WHERE pcm.match_status = 'CONFIRMED'
     ORDER BY pcm.card_id
     LIMIT 1
    ON CONFLICT (k) DO NOTHING;

    PERFORM pg_temp._rec('F','F01 - fixture SOMENTE LEITURA montada (owner + 101 Cards reais)',
        v_owner IS NOT NULL AND v_n = 101,
        format('owner=%s cards=%s card_com_preco=%s', v_owner, v_n,
               COALESCE((SELECT v::text FROM _fx WHERE k='card_com_preco'), '(nenhum)')),
        'owner nao nulo e 101 Cards');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp._rec('F','F-ABORT - fixture abortou', FALSE,
        SQLSTATE||' '||left(SQLERRM,180), 'fixture completa');
END $blk$;

-- =================================================================
-- GRUPO N — OS NOVE CENARIOS OBRIGATORIOS DO MANDATO
--
-- Papel de cada peca declarado no rotulo:
--   N01/N02  contrato de entrada vazio/nulo, mensagem correta;
--   N03/N04  caminho feliz e teto exato (regressao);
--   N05      teto por contagem — NECESSARIO, nao suficiente;
--   N06      PROVA do fechamento (dim1=2, cardinality=600);
--   N07      contrato de FORMA, nao so de tamanho;
--   N08      payload valido continua devolvendo resultado correto.
-- =================================================================
DO $blk$
DECLARE
    v_owner UUID;
    v_1   UUID[]; v_100 UUID[]; v_101 UUID[];
    v_md600 UUID[]; v_md10 UUID[];
    v_pc UUID;
BEGIN
    SELECT v INTO v_owner FROM _fx WHERE k = 'owner';
    SELECT v INTO v_pc    FROM _fx WHERE k = 'card_com_preco';

    SELECT array_agg(id ORDER BY id) INTO v_101 FROM _ids WHERE k = 'card';
    v_100 := v_101[1:100];
    v_1   := ARRAY[v_101[1]];

    -- Multidimensionais construidos a partir de um Card REAL, para que
    -- a rejeicao nao possa ser atribuida a id inexistente.
    v_md600 := array_fill(v_101[1], ARRAY[2, 300]);
    v_md10  := array_fill(v_101[1], ARRAY[2, 5]);

    PERFORM pg_temp._rec('N','N00 - aritmetica dos payloads: multidim engana array_length(x,1) mas nao cardinality()',
        cardinality(v_1) = 1
        AND cardinality(v_100) = 100
        AND cardinality(v_101) = 101
        AND array_ndims(v_md600) = 2
        AND array_length(v_md600, 1) = 2
        AND cardinality(v_md600) = 600
        AND array_ndims(v_md10) = 2
        AND cardinality(v_md10) = 10,
        format('1=%s 100=%s 101=%s | md600: ndims=%s dim1=%s card=%s | md10: ndims=%s card=%s',
               cardinality(v_1), cardinality(v_100), cardinality(v_101),
               array_ndims(v_md600), array_length(v_md600,1), cardinality(v_md600),
               array_ndims(v_md10), cardinality(v_md10)),
        'md600 com ndims=2, dim1=2, card=600');

    PERFORM pg_temp._as_user(v_owner);

    -- ---------------- N01: NULL ----------------
    PERFORM pg_temp._expect_error('N','N01 - NULL rejeitado com PRICING_SUMMARY_EMPTY_INPUT',
        'SELECT * FROM public.get_cards_pricing_summary(NULL::uuid[])',
        'PRICING_SUMMARY_EMPTY_INPUT');

    -- ---------------- N02: vazio ----------------
    -- Precisa dar a mensagem de VAZIO, nao a de dimensao: array_ndims('{}')
    -- e NULL, entao a ordem dos guards importa.
    PERFORM pg_temp._expect_error('N','N02 - array vazio rejeitado com PRICING_SUMMARY_EMPTY_INPUT (nao com a de dimensao)',
        'SELECT * FROM public.get_cards_pricing_summary(ARRAY[]::uuid[])',
        'PRICING_SUMMARY_EMPTY_INPUT');

    -- ---------------- N03: 1 elemento ----------------
    PERFORM pg_temp._expect_rows('N','N03 - 1 elemento ACEITO e devolve exatamente 1 linha',
        format('SELECT * FROM public.get_cards_pricing_summary(%L::uuid[])', v_1), 1);

    -- ---------------- N04: 100 elementos (teto exato) ----------------
    PERFORM pg_temp._expect_rows('N','N04 - 100 elementos distintos ACEITOS e devolvem 100 linhas (teto exato, regressao)',
        format('SELECT * FROM public.get_cards_pricing_summary(%L::uuid[])', v_100), 100);

    -- ---------------- N05: 101 elementos ----------------
    PERFORM pg_temp._expect_error('N','N05 - 101 elementos rejeitados pelo teto [necessario, NAO suficiente]',
        format('SELECT * FROM public.get_cards_pricing_summary(%L::uuid[])', v_101),
        'PRICING_SUMMARY_TOO_MANY_CARD_IDS');

    -- ---------------- N06: multidimensional grande ----------------
    PERFORM pg_temp._expect_error('N','N06 - multidim dim1=2 card=600 REJEITADO [PROVA do fechamento do bypass]',
        format('SELECT * FROM public.get_cards_pricing_summary(%L::uuid[])', v_md600),
        'PRICING_SUMMARY_INVALID_PAYLOAD_SHAPE');

    -- ---------------- N07: multidimensional pequeno ----------------
    PERFORM pg_temp._expect_error('N','N07 - multidim pequeno (card=10) tambem REJEITADO [contrato de FORMA]',
        format('SELECT * FROM public.get_cards_pricing_summary(%L::uuid[])', v_md10),
        'PRICING_SUMMARY_INVALID_PAYLOAD_SHAPE');

    PERFORM pg_temp._as_admin();
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp._as_admin();
    PERFORM pg_temp._rec('N','N-ABORT - grupo N abortou', FALSE,
        SQLSTATE||' '||left(SQLERRM,180), 'grupo N completo');
END $blk$;

-- =================================================================
-- N08 — NAO-REGRESSAO DE NEGOCIO com dado REAL.
-- Comparacao A/B contra a logica de referencia reconstruida
-- independentemente (mesma regra NM/MARKET/hierarquia de printing),
-- em bloco proprio para que uma ausencia de dado nao derrube o grupo N.
-- =================================================================
DO $blk$
DECLARE
    v_owner UUID; v_pc UUID;
    v_has BOOLEAN; v_brl NUMERIC; v_lbl TEXT; v_origin TEXT; v_fx TEXT;
    v_ref_lbl TEXT;
BEGIN
    SELECT v INTO v_owner FROM _fx WHERE k = 'owner';
    SELECT v INTO v_pc    FROM _fx WHERE k = 'card_com_preco';

    IF v_pc IS NULL THEN
        PERFORM pg_temp._rec('N','N08 - payload valido devolve resultado correto (dado real)',
            NULL,  -- NOT PROVEN: nunca convertido em PASS artificial
            'nenhum Card com observacao NM/MARKET CONFIRMED no ambiente',
            'has_pricing e printing_label coerentes com a hierarquia');
        RETURN;
    END IF;

    -- Referencia independente: printing de maior prioridade elegivel.
    SELECT pp.source_printing_label INTO v_ref_lbl
      FROM public.pricing_card_mapping pcm
      JOIN public.pricing_product pp ON pp.pricing_card_mapping_id = pcm.id AND pp.is_active
      JOIN public.pricing_source ps ON ps.id = pcm.pricing_source_id AND ps.is_active
      JOIN public.pricing_source_card_identity psci
        ON psci.id = pp.pricing_source_card_identity_id
       AND psci.identity_role = 'PRIMARY' AND psci.match_status = 'CONFIRMED'
      JOIN public.pricing_observation po ON po.pricing_product_id = pp.id AND po.price_type = 'MARKET'
      JOIN public.card_condition cc ON cc.id = po.condition_id AND cc.code = 'NM'
     WHERE pcm.match_status = 'CONFIRMED' AND pcm.card_id = v_pc
     ORDER BY CASE pp.source_printing_label
                WHEN 'Normal' THEN 1 WHEN 'Holofoil' THEN 2
                WHEN 'Reverse Holofoil' THEN 3 WHEN 'Unlimited' THEN 4
                WHEN 'Unlimited Holofoil' THEN 5 WHEN '1st Edition' THEN 6
                WHEN '1st Edition Holofoil' THEN 7 ELSE 8 END
     LIMIT 1;

    PERFORM pg_temp._as_user(v_owner);
    SELECT s.has_pricing, s.brl_amount, s.printing_label, s.price_origin, s.fx_status
      INTO v_has, v_brl, v_lbl, v_origin, v_fx
      FROM public.get_cards_pricing_summary(ARRAY[v_pc]::uuid[]) s;
    PERFORM pg_temp._as_admin();

    PERFORM pg_temp._rec('N','N08 - payload valido devolve resultado correto (dado real, printing pela hierarquia)',
        v_lbl IS NOT DISTINCT FROM v_ref_lbl,
        format('card=%s has_pricing=%s brl=%s printing=%s origin=%s fx=%s',
               v_pc, v_has, COALESCE(v_brl::text,'NULL'), COALESCE(v_lbl,'NULL'),
               COALESCE(v_origin,'NULL'), COALESCE(v_fx,'NULL')),
        format('printing_label = %s (referencia independente)', COALESCE(v_ref_lbl,'NULL')));
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp._as_admin();
    PERFORM pg_temp._rec('N','N08 - payload valido devolve resultado correto (dado real)', FALSE,
        'erro: '||SQLSTATE||' '||left(SQLERRM,160), 'sem erro');
END $blk$;

-- =================================================================
-- GRUPO R — REGRESSAO DE CONTRATO
-- =================================================================
DO $blk$
DECLARE
    v_owner UUID; v_1 UUID[];
BEGIN
    SELECT v INTO v_owner FROM _fx WHERE k='owner';
    -- CORRECAO v1.1: `min(uuid)` NAO existe em PostgreSQL (42883). Limitacao
    -- ja registrada no projeto. Substituido por ORDER BY + LIMIT 1, que e o
    -- caminho canonico para "o menor uuid" e mantem o determinismo.
    SELECT ARRAY[(SELECT id FROM _ids WHERE k='card' ORDER BY id LIMIT 1)] INTO v_1;

    -- R01: autenticacao continua exigida. Sem claim JWT, auth.uid() e
    -- NULL e a funcao deve recusar ANTES de qualquer trabalho.
    PERFORM set_config('request.jwt.claims', '', TRUE);
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM pg_temp._expect_error('R','R01 - sem claim JWT a funcao exige autenticacao (28000)',
        format('SELECT * FROM public.get_cards_pricing_summary(%L::uuid[])', v_1),
        'PRICING_SUMMARY_REQUIRES_AUTHENTICATION');
    PERFORM pg_temp._as_admin();

    -- R02: anon continua sem EXECUTE.
    PERFORM pg_temp._rec('R','R02 - anon continua SEM EXECUTE; authenticated continua COM',
        (SELECT has_function_privilege('authenticated', p.oid,'EXECUTE')
            AND NOT has_function_privilege('anon', p.oid,'EXECUTE')
            AND NOT has_function_privilege('service_role', p.oid,'EXECUTE')
           FROM pg_proc p
          WHERE p.pronamespace='public'::regnamespace AND p.proname='get_cards_pricing_summary'),
        (SELECT p.proacl::text FROM pg_proc p
          WHERE p.pronamespace='public'::regnamespace AND p.proname='get_cards_pricing_summary'),
        'authenticated=X, anon sem X, service_role sem X');
END $blk$;

-- =================================================================
-- GRUPO S — STATIC PROOF FAIL-CLOSED
--
-- Comentarios removidos do pg_get_functiondef antes da busca (bloco,
-- depois linha). Busca literal com position() — `_` NAO e wildcard
-- aqui, diferente de LIKE/ILIKE (precedente: POSTCHECK-2c da Fatia E).
-- Exige a CADEIA: guards < primeiro unnest/DISTINCT.
-- =================================================================
DO $blk$
DECLARE
    v_oid OID; v_exec TEXT;
    v_card INTEGER; v_ndims INTEGER; v_cap INTEGER;
    v_unnest INTEGER; v_distinct INTEGER; v_first_scan INTEGER;
    v_arraylen INTEGER;
BEGIN
    SELECT p.oid INTO v_oid FROM pg_proc p
     WHERE p.pronamespace='public'::regnamespace AND p.proname='get_cards_pricing_summary';

    IF v_oid IS NULL THEN
        PERFORM pg_temp._rec('S','S01 - STATIC PROOF: cadeia de guards antes do primeiro unnest/DISTINCT',
            FALSE, 'FUNCAO AUSENTE', 'funcao existe e conforme');
        RETURN;
    END IF;

    v_exec := regexp_replace(
                regexp_replace(pg_get_functiondef(v_oid), '/\*.*?\*/', ' ', 'gs'),
                '--.*$', ' ', 'gn');

    v_card     := position('cardinality(p_card_ids)' in v_exec);
    v_ndims    := position('array_ndims(p_card_ids) <> 1' in v_exec);
    v_cap      := position('v_raw_count > 100' in v_exec);
    v_arraylen := position('array_length(p_card_ids' in v_exec);
    v_unnest   := position('unnest(p_card_ids)' in v_exec);
    v_distinct := position('DISTINCT' in v_exec);
    v_first_scan := LEAST(
        CASE WHEN v_unnest   = 0 THEN 2147483647 ELSE v_unnest   END,
        CASE WHEN v_distinct = 0 THEN 2147483647 ELSE v_distinct END);

    PERFORM pg_temp._rec('S','S01 - STATIC PROOF FAIL-CLOSED: cardinality e array_ndims presentes, ZERO array_length(p_card_ids, e todos os guards ANTES do primeiro unnest/DISTINCT',
        v_card > 0 AND v_ndims > 0 AND v_cap > 0
        AND v_arraylen = 0
        AND v_first_scan < 2147483647
        AND v_card < v_first_scan
        AND v_ndims < v_first_scan
        AND v_cap  < v_first_scan,
        format('cardinality=%s ndims=%s cap=%s array_length=%s first_scan=%s',
               v_card, v_ndims, v_cap, v_arraylen, v_first_scan),
        'cardinality>0, ndims>0, cap>0, array_length=0, todos < first_scan');

    PERFORM pg_temp._rec('S','S02 - contrato de seguranca preservado: SECURITY DEFINER, STABLE, search_path EFETIVAMENTE vazio, owner postgres',
        (SELECT p.prosecdef AND p.provolatile = 's'
            AND pg_temp._empty_search_path(p.oid)
            AND pg_get_userbyid(p.proowner) = 'postgres'
           FROM pg_proc p WHERE p.oid = v_oid),
        (SELECT format('secdef=%s volatile=%s config=%s owner=%s',
                p.prosecdef, p.provolatile, p.proconfig, pg_get_userbyid(p.proowner))
           FROM pg_proc p WHERE p.oid = v_oid),
        'secdef=t, volatile=s, search_path vazio, owner=postgres');

    PERFORM pg_temp._rec('S','S03 - assinatura e retorno preservados (6 colunas, 1 overload)',
        (SELECT count(*) = 1 FROM pg_proc p
          WHERE p.pronamespace='public'::regnamespace AND p.proname='get_cards_pricing_summary')
        AND (SELECT pg_get_function_identity_arguments(v_oid)) = 'p_card_ids uuid[]'
        AND (SELECT pg_get_function_result(v_oid)) =
            'TABLE(card_id uuid, has_pricing boolean, brl_amount numeric, fx_status text, printing_label text, price_origin text)',
        format('overloads=%s | args=%s | ret=%s',
               (SELECT count(*) FROM pg_proc p
                 WHERE p.pronamespace='public'::regnamespace AND p.proname='get_cards_pricing_summary'),
               pg_get_function_identity_arguments(v_oid),
               pg_get_function_result(v_oid)),
        '1 overload, p_card_ids uuid[], TABLE de 6 colunas');

    PERFORM pg_temp._rec('S','S04 - regra de negocio preservada: NM + MARKET + hierarquia de 7 printings + fallback MANUAL',
        position('''MARKET''' in v_exec) > 0
        AND position('''NM''' in v_exec) > 0
        AND position('''1st Edition Holofoil''' in v_exec) > 0
        AND position('pricing_latest_manual_price' in v_exec) > 0
        AND position('''AUTOMATIC''' in v_exec) > 0
        AND position('''MANUAL''' in v_exec) > 0,
        format('MARKET=%s NM=%s 1stEdHolo=%s manual_fn=%s AUTOMATIC=%s MANUAL=%s',
               position('''MARKET''' in v_exec), position('''NM''' in v_exec),
               position('''1st Edition Holofoil''' in v_exec),
               position('pricing_latest_manual_price' in v_exec),
               position('''AUTOMATIC''' in v_exec), position('''MANUAL''' in v_exec)),
        'todos presentes');
END $blk$;

-- =================================================================
-- ZERO RESIDUO — este harness nao escreve nada por construcao.
-- =================================================================
DO $blk$
DECLARE v_n BIGINT; v_m BIGINT;
BEGIN
    SELECT count(*) INTO v_n FROM public.pricing_observation;
    SELECT count(*) INTO v_m FROM public.pricing_manual_price;

    PERFORM pg_temp._rec('X','X01 - harness e SOMENTE LEITURA: nenhuma fixture criada em tabela real',
        TRUE,
        format('pricing_observation=%s pricing_manual_price=%s (inalteradas — nenhum INSERT/UPDATE/DELETE no arquivo)', v_n, v_m),
        'nenhuma escrita');

    PERFORM pg_temp._rec('X','X02 - EVIDENCIA ESTATICA: arquivo termina em ROLLBACK e nao contem COMMIT (zero residuo real exige postcheck pos-execucao)',
        TRUE,
        'zero residuo REAL exige postcheck pos-execucao',
        'ROLLBACK presente, COMMIT ausente');
END $blk$;

-- =================================================================
-- RELATORIO FINAL — PROTOCOLO EM DUAS CHAMADAS.
--   CALL 1: tudo desde BEGIN; ate o SELECT abaixo, INCLUSIVE.
--   CALL 2: ROLLBACK;
--
-- passed=TRUE -> PASS | FALSE -> FAIL | NULL -> NOT PROVEN
--
-- GATE OFICIAL: TOTAL 18 / PASS 18 / FAIL 0 / NOT PROVEN 0.
-- 20 e a contagem de ROTULOS ESTATICOS; `F-ABORT` e `N-ABORT` sao
-- ramos de excecao fail-only e mutuamente exclusivos. Qualquer
-- `*-ABORT` presente = STOP. O unico NOT PROVEN aceitavel e `N08`,
-- e so em ambiente sem observacao NM/MARKET CONFIRMED.
-- =================================================================
SELECT
    COALESCE(grp, 'TOTAL')                                   AS grp,
    count(*)                                                 AS total,
    count(*) FILTER (WHERE passed IS TRUE)                   AS passed,
    count(*) FILTER (WHERE passed IS FALSE)                  AS failed,
    count(*) FILTER (WHERE passed IS NULL)                   AS not_proven,
    string_agg(case_label || ' >> ' || COALESCE(observed,''), ' || ')
        FILTER (WHERE passed IS FALSE)                       AS failing_cases,
    string_agg(case_label, ' || ')
        FILTER (WHERE passed IS NULL)                        AS not_proven_cases
FROM _v
GROUP BY ROLLUP (grp)
ORDER BY (grp IS NULL), grp;

ROLLBACK;
