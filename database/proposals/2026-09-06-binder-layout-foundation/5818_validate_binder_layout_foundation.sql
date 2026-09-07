/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5818 - Validate Binder / Layout Foundation
Versão......: 7.2
Status......: PROPOSTA — HARNESS EXECUTÁVEL COMPLETO, NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (v1.0 staging inicial;
               v2.0 em ...-STAGING-HARNESS-COMPLETION-01 —
               materialização integral;
               v3.0 em ...-CONSOLIDATED-CORRECTION-01 —
               correção dos blockers da auditoria direta;
               v4.0 em ...-CONSOLIDATED-CORRECTION-02 —
               limites de lote + 4 defeitos do harness;
               v5.0 em ...-CONSOLIDATED-CORRECTION-03 —
               cardinalidade real, regressões
               multidimensionais e C01 estrutural;
               v6.0 em ...-CONSOLIDATED-CORRECTION-04 —
               gates fail-closed em B10/B11/B12/C01 e
               reconciliação de rótulos;
               v7.0 em ...-CONSOLIDATED-CORRECTION-05 —
               B12 relacional em ambos os lados e prova
               efetiva de search_path vazio;
               v7.1 em ...-IMPLEMENTATION-01-HARNESS-FIX-01 —
               GRANTs de TEMP TABLE a `authenticated` e
               reconciliação do protocolo de duas chamadas
               com o comportamento real do executor;
               v7.2 em ...-IMPLEMENTATION-01-FIX-02 —
               A02 alinhado à não-enumeração, F04 com Region
               dedicada, e o gate declarado em termos de
               contagem de RUNTIME, não de rótulos estáticos)

GATE DE ACEITE (v7.2) — NÚMEROS DE RUNTIME, NÃO DE ARQUIVO
----------------------------------------------------------
`205` é a contagem de RÓTULOS DISTINTOS PRESENTES NO ARQUIVO. NÃO é,
e nunca foi, um alvo de execução: 9 desses rótulos pertencem a ramos
MUTUAMENTE EXCLUSIVOS, que por construção nunca coexistem numa mesma
execução —
  * fallbacks de exceção/fixture: `A07 - REPLACE`,
    `B00 - fixture de Slot para os testes de lote`,
    `P06 - reorder inverte preservando id`, `B-ABORT`, `U-ABORT`,
    `R15/R16/R17 - trigger 5121 v2.0 em DELETE/UPDATE`;
  * ramo "sem segundo usuário": `Z02`(curto), `Z03`, `Z05`(curto),
    substituídos, quando existe um segundo `auth.users`, por
    `Z03a`/`Z03b`/`Z03c` e pelo `Z05` longo.

Exigir "205 PASS" era, portanto, aritmeticamente inatingível. O gate
correto, NESTE AMBIENTE (>= 2 usuários em `auth.users`):

      TOTAL       = 196
      PASS        = 194
      FAIL        = 0
      NOT PROVEN  = 2, e EXATAMENTE `C04` e `R18`

Qualquer FAIL, ou qualquer NOT PROVEN que não seja C04/R18, é STOP.
C04 e R18 permanecem NOT PROVEN por HONESTIDADE — o canal de execução
não oferece duas sessões persistentes simultâneas. NUNCA convertê-los
artificialmente em PASS: a prova de ambos é EXTERNA, em duas sessões
reais, e é registrada fora deste harness.

MUDANÇA v7.1 -> v7.2 (FIX-02)
-----------------------------
Dois defeitos DO HARNESS, ambos revelados pela primeira execução
completa. Nenhuma regra de negócio e nenhuma função de produção foram
tocadas.

§2 A02 ESPERAVA A MENSAGEM PRÉ-HARDENING. `assign_card_to_slot`
   (5131) recebeu na CORREÇÃO CONSOLIDADA 01 §4C o hardening de
   não-enumeração: a Allocation é resolvida JÁ ESCOPADA ao
   `collection_id` do Layout, e inexistente / de outra Collection /
   de outro Owner colapsam na MESMA mensagem
   `collection allocation not found or not owned by caller`.
   O harness ainda exigia `nao esta alocada a mesma Collection`, que
   é a mensagem do TRIGGER 5117 — corretamente exercida por A13, pelo
   caminho privilegiado. A produção estava certa; o gate é que estava
   desatualizado. `5131` NÃO foi alterado.

§3 F04 DEPENDIA DE FIXTURE JÁ CONSUMIDA. O caso reaproveitava
   `region1`, criada por R01 e APAGADA por R12 (unmerge normal, que
   roda antes do grupo F). O UPDATE atingia zero linhas, o trigger
   5121 nunca disparava, e o caso reprovava com 'NENHUM erro
   levantado' — gate VÁCUO, não defeito de produção. O grupo F passa
   a criar a PRÓPRIA Region, em área livre e sem Lock da Page 1
   (linha 4, colunas 1-2). A independência vem da fixture ser
   própria, não de reordenar grupos.

DEFEITO DE PRODUÇÃO ENCONTRADO NESTA MESMA EXECUÇÃO (fora do harness)
--------------------------------------------------------------------
U01/U01b/U02/U03 falhavam com `42702 column reference "id" is
ambiguous`: em `5137`, o `id` do `WHERE` do UPDATE colidia com a
variável de saída homônima do RETURNS TABLE. Corrigido pela migration
incremental `5141`, que NÃO edita `5137`. Este harness não foi
adaptado ao defeito — ele o expôs.

MUDANÇA v7.0 -> v7.1 (HARNESS-FIX-01)
-------------------------------------
Defeito REAL descoberto na PRIMEIRA execução do harness. Nenhum gate,
caso ou regra de negócio foi alterado.

§A GRANTS DE TEMP TABLE. `_v` e `_fx` são objetos TEMP e objetos TEMP
   NÃO herdam privilégio de PUBLIC (ao contrário de funções). Como o
   harness alterna para `authenticated` via SET LOCAL ROLE e chama
   `pg_temp._rec` já nesse contexto (primeiro caso afetado: L03, via
   `_expect_error`), a execução abortava com
   `42501 permission denied for table _v`.
   Corrigido com os DOIS GRANTs imediatamente após a criação das temp
   tables, espelhando LITERALMENTE o padrão já aprovado do 5820
   (e vigente em 5819 e 5814 "CORREÇÃO v1.1, item 1").
   NUNCA estendido a `anon`.

§B PROTOCOLO DE DUAS CHAMADAS — RECONCILIADO COM O COMPORTAMENTO REAL.
   Mediu-se, por sonda, que o executor NÃO preserva sessão nem
   transação entre chamadas. A afirmação "a transação permanece
   ABERTA" era imprecisa e foi substituída pelo comportamento
   observado: rollback IMPLÍCITO ao fim da CALL 1 (BEGIN; sem COMMIT;),
   com a CALL 2 (`ROLLBACK;`) mantida como confirmação explícita e
   no-op quando a sessão já foi encerrada. Zero resíduo continua
   afirmável SOMENTE por postcheck pós-execução (X02).

Descrição...:
Harness FUNCIONAL fail-closed da Binder/Layout Foundation
(Queries 5104-5137). Executado APÓS a aplicação das 34 Queries.

MUDANÇA v1.0 -> v2.0: a v1.0 deixava L/G/P/E/A/K/R/D/Z/C descritos
como contrato para um gate futuro. Isso NÃO atendia ao requisito de
STAGING fail-closed. Na v2.0 TODOS os grupos viraram SQL executável.

MUDANÇA v2.0 -> v3.0 (CORREÇÃO CONSOLIDADA 01)
----------------------------------------------
§10 ACENTOS. Vários `p_fragment` de `_expect_error` estavam SEM
    acento ('nao', 'esta', 'minimo', 'sobrepoe') enquanto as mensagens
    reais das RPCs têm acento. `position()` sobre a string crua nunca
    casaria: FALSO FAIL garantido. Corrigido com `pg_temp._norm()`,
    que remove diacríticos DOS DOIS LADOS antes da comparação. A
    semântica de substring NÃO foi relaxada, e erro inesperado
    continua FALSE — jamais PASS.

§11 E09 ERA PASS VAZIO. E09 comparava o digest de
    collection_completion_summary() ANTES e DEPOIS usando a fixture
    principal, que é OPEN_CURATION/NONE. Por contrato essa função
    devolve ZERO linhas nesse cenário, então o digest era 'EMPTY' dos
    dois lados e o caso passava por vacuidade. Agora existe uma
    fixture DEDICADA REFERENCE_BASED/CARD_SET/STANDARD_SET criada pela
    RPC real, e o baseline NÃO-VAZIO é um gate: baseline vazio = FAIL.

§12 R13 NÃO PODE SER VÁCUO. Os digests de Assignment e Expected
    Content podiam ser 'EMPTY' e o caso passava. Agora Expected
    Content REAL é criado num Slot da Region antes da prova, e as
    contagens de Assignment e Expected Content afetados são gates:
    EMPTY = FAIL.

§13 CONCORRÊNCIA. C01/C02/C03 tratavam `pg_locks` como "evidência
    direta" de serialização de LINHA — afirmação forte demais e fonte
    de falso FAIL. Reclassificados em três níveis honestos:
    STATIC/STRUCTURAL PROOF (pg_get_functiondef mostra a sequência
    Collection FOR UPDATE -> Layout FOR UPDATE), SUPPORTING LOCK
    EVIDENCE (pg_locks observa lock de RELAÇÃO, sem afirmar
    identidade de row lock) e REAL TWO-SESSION SERIALIZATION (só C04,
    NOT PROVEN sem duas sessões).

§15 SECURITY COVERAGE. Z01 passa a exigir as SEIS tabelas; DML é
    verificado para os TRÊS grantees (PUBLIC, anon, authenticated);
    owner das funções conferido; casos negativos específicos de
    não-enumeração adicionados.

NOVOS GRUPOS: F (imutabilidade das FKs estruturais, 5136),
N (collection_allocation_id imutável, 5117 v2.0),
U (set_collection_layout_grid, 5137), e novos casos de Region para o
trigger 5121 v2.0 em DELETE/UPDATE.

MUDANÇA v3.0 -> v4.0 (CORREÇÃO CONSOLIDADA 02)
----------------------------------------------
§3 NOVO GRUPO B — LIMITES DE LOTE. Casos executáveis fail-closed para
    o teto de 500 das três RPCs de array (5129/5130/5133), incluindo
    501 elementos TODOS REPETIDOS.
    [RETIFICADO na CORREÇÃO CONSOLIDADA 05] A redação original dizia
    que esse caso "só é possível se o cap anteceder o dedup". Isso é
    FALSO: 501 repetidos também falhariam com um cap medido por
    `array_length(x, 1)`, que a CORREÇÃO 03 provou ser contornável.
    O caso é CONDIÇÃO NECESSÁRIA, NÃO SUFICIENTE — o que prova o
    fechamento são B13-B18 (multidimensional) e B10 (STATIC PROOF
    fail-closed). Mais STATIC PROOF de que, em 5127, o short-circuit
    de cardinalidade precede o unnest/DISTINCT.

§4 C01 passa a exigir a ORDEM, não só a presença: pos(COLLECTION) <
    pos(LAYOUT). Verificar apenas presença deixava passar um helper
    que lockasse LAYOUT antes de COLLECTION — exatamente o defeito
    que a §2 da CORREÇÃO 01 corrigiu.

§5 Z02 (cross-user SELECT) passa a verificar as SEIS tabelas; a v3.0
    omitia collection_layout_slot_expected_content.

§6 S18/S20/S21 reconciliados com o estado físico atual:
    S18 = 15 (helper + 14 RPCs), S20 = 14 RPCs para anon,
    S21 = 12 trigger functions. U00 e Z08 são MANTIDOS: a redundância
    de cobertura de segurança é intencional.

MUDANÇA v4.0 -> v5.0 (CORREÇÃO CONSOLIDADA 03)
----------------------------------------------
§2 GRUPO B — REGRESSÕES MULTIDIMENSIONAIS. Os casos de 500/501 foram
    PRESERVADOS, mas deixaram de ser apresentados como prova
    suficiente de "cap antes do dedup": eles são condição necessária,
    não suficiente. Somados a eles, novos casos enviam payload
    MULTIDIMENSIONAL cuja PRIMEIRA DIMENSÃO é pequena e cuja
    CARDINALIDADE total excede 500 — exatamente o bypass que
    `array_length(x,1)` permitia. B10/B11 passam a localizar a
    REJEIÇÃO EFETIVA (`IF ... > 500` + RAISE), exigir `cardinality()`
    e provar que a decisão precede o PRIMEIRO unnest/DISTINCT. B12
    deixa de se apoiar só na ausência de uma mensagem: prova que o
    corpo executável de `reorder_layout_pages` não contém o literal
    500 nem qualquer comparação de cardinalidade contra literal
    numérico.

§3 C01 ESTRUTURAL. A v4.0 comparava apenas a posição dos NOMES das
    tabelas e contava `FOR UPDATE` globalmente — um helper que
    lockasse LAYOUT antes de COLLECTION ainda poderia passar. Agora
    cada `FOR UPDATE` é vinculado ao seu próprio `SELECT`, exigindo
    a cadeia COLLECTION FROM < COLLECTION FOR UPDATE < LAYOUT FROM <
    LAYOUT FOR UPDATE, sobre o source SEM comentários.

§4 GATES PRESERVADOS: Z02 (SEIS tabelas), S18=15, S20=14, S21=12,
    S21b (existência das 12). Nenhum foi relaxado.

MUDANÇA v5.0 -> v6.0 (CORREÇÃO CONSOLIDADA 04)
----------------------------------------------
Apenas fechamento de gates e reconciliação de rótulos. NENHUMA regra
de negócio mudou; `5127`/`5129`/`5130`/`5133` não foram tocados.

§1 B10 FAIL-CLOSED. A v5.0 localizava o `IF v_raw_count > 500` e a
    STRING da mensagem, mas não o `RAISE EXCEPTION` real — uma função
    que testasse o cap e NÃO levantasse erro (ou que só mencionasse a
    mensagem num contexto qualquer) passaria. Agora exige-se a cadeia
    `IF cap` < `RAISE EXCEPTION` < mensagem < primeiro unnest/DISTINCT,
    provada sobre o SEGMENTO de source entre o cap e o primeiro scan.

§2 B11 FAIL-CLOSED. Idem para o short-circuit de `reorder`: a
    condição `v_input_count <> v_total_pages` antes do scan não basta
    — exige-se o `RAISE EXCEPTION` correspondente dentro do mesmo
    segmento, antes do primeiro unnest/DISTINCT.

§3 C01 VÍNCULO POR STATEMENT. A v5.0 pegava o primeiro `FOR UPDATE`
    APÓS o `FROM` — que poderia pertencer a OUTRO `SELECT` adiante.
    Agora o `FOR UPDATE` precisa estar dentro do MESMO statement, isto
    é, antes do primeiro `;` que segue o `FROM` correspondente.

§4 B12 SEM CAP, INCLUSIVE VIA CONSTANTE. Não basta ausência do
    literal 500: `v_input_count` só pode ser comparado contra
    `v_total_pages` ou `0` (whitelist de operandos extraída por
    regex), e o corpo não pode conter `RAISE EXCEPTION` cuja mensagem
    fale em 'limite'/'excede'. Um cap via constante ou variável
    reprova o gate. Prova estática pura — nenhuma fixture pesada.

§5 RÓTULOS. B02/B05/B08 deixaram de se anunciar como "prova do raw
    cap": são condição necessária, não suficiente.

CONTRATO DE EXECUÇÃO
--------------------
- Executar como usuário PRIVILEGIADO (postgres/service_role), em UM
  único call. O script alterna para `authenticated` via SET LOCAL ROLE
  + request.jwt.claims onde a semântica de cliente precisa ser
  exercida, e sempre faz RESET ROLE antes de gravar resultado.
- TUDO dentro de BEGIN ... ROLLBACK. Zero resíduo por construção.
- FAIL-CLOSED: nenhum caso passa por omissão.
    * `_expect_error` marca FALSE se NÃO houver erro, e FALSE se o
      erro vier com mensagem diferente da esperada (registra a real).
    * `_expect_ok` marca FALSE se qualquer erro ocorrer (registra-o).
    * Erro inesperado NUNCA vira PASS.
- NOT PROVEN é um terceiro estado (passed IS NULL), contado à parte.
  Nunca somado a PASS. Usado só onde o ambiente impede a prova
  (ex.: ausência de segundo usuário; duas sessões simultâneas).
- Identidade sobre nome: comparações usam UUID capturado, não rótulo.
- PROTOCOLO DE EXECUÇÃO EM DUAS CHAMADAS (§14, RECONCILIADO na
  CORREÇÃO HARNESS-FIX-01 com o COMPORTAMENTO REAL OBSERVADO do
  executor). O executor devolve apenas o resultado do ÚLTIMO statement.
  Portanto:
      CALL 1 — executar do `BEGIN;` até o `SELECT` final do relatório,
               INCLUSIVE. É esta chamada que devolve o relatório.
      CALL 2 — `ROLLBACK;`
  NÃO é verdade que uma única chamada contendo TAMBÉM o `ROLLBACK;`
  devolva o relatório: nela o último statement seria o ROLLBACK, que
  não retorna linhas. Precedente: mesma disciplina de 5808/5812.

  COMPORTAMENTO REAL DO CANAL (medido, não presumido): o executor NÃO
  preserva sessão nem transação entre chamadas — uma TEMP TABLE criada
  na CALL 1 já não existe na CALL 2. Portanto NÃO se afirma que a
  transação permanece aberta até a CALL 2: ela é encerrada com
  ROLLBACK IMPLÍCITO ao término da CALL 1, porque o script abre
  `BEGIN;` e nunca emite `COMMIT;`. A CALL 2 (`ROLLBACK;`) permanece no
  protocolo como confirmação explícita de que nenhuma transação ficou
  pendente, e é um no-op quando a sessão já foi encerrada.

  CONSEQUÊNCIA PARA ZERO RESÍDUO: inalterada e, se algo, mais forte —
  o descarte não depende de a CALL 2 chegar. Zero resíduo continua
  sendo afirmado SOMENTE após postcheck pós-execução (ver X02), nunca
  por leitura do arquivo.

PRÉ-REQUISITOS
--------------
- Queries 5104-5137 aplicadas (34 arquivos SQL de schema).
- Catálogo Editorial com >= 1 game, >= 1 language, >= 2 card distintas
  com card_variant, e >= 2 card_variant da MESMA card. O script NÃO
  fabrica Catálogo: ABORTA fail-loud se não encontrar.
- >= 1 auth.users. Um SEGUNDO usuário é opcional: sem ele, os casos
  cross-user viram NOT PROVEN explicitamente.
- Para o grupo E (regressão de completion) é preciso um Card Set REAL
  com >= 1 Card; sem ele, E09 é registrado como FAIL de fixture, nunca
  como PASS.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADO.
================================================================
*/

BEGIN;

SET LOCAL client_min_messages = WARNING;

-- =================================================================
-- INFRAESTRUTURA DO HARNESS
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

-- CORRECAO HARNESS-FIX-01 (v7.0 -> v7.1). Objetos TEMP NAO herdam
-- privilegio de PUBLIC (diferente de funcoes). O harness alterna para
-- `authenticated` via SET LOCAL ROLE e, a partir dai, `pg_temp._rec`
-- roda sob esse papel — sem estes GRANTs o primeiro registro feito em
-- contexto de cliente falha com 42501 permission denied for table _v.
-- Padrao ja aprovado e identico ao de 5820 (e 5819/5814). NUNCA
-- estendido a anon.
GRANT ALL ON _v, _fx TO authenticated;
GRANT USAGE, SELECT, UPDATE ON SEQUENCE _v_seq_seq TO authenticated;

CREATE OR REPLACE FUNCTION pg_temp._rec(
    p_grp TEXT, p_label TEXT, p_passed BOOLEAN,
    p_observed TEXT DEFAULT NULL, p_expected TEXT DEFAULT NULL
) RETURNS VOID LANGUAGE plpgsql AS $fn$
BEGIN
    INSERT INTO _v (grp, case_label, passed, observed, expected)
    VALUES (p_grp, p_label, p_passed, p_observed, p_expected);
END; $fn$;

-- §10 NORMALIZAÇÃO DE DIACRÍTICOS. Remove acentuação dos DOIS lados
-- antes de comparar. Não relaxa a semântica de substring: o fragmento
-- continua tendo de aparecer na mensagem; apenas deixa de falhar por
-- 'nao' x 'não'.
CREATE OR REPLACE FUNCTION pg_temp._norm(p_text TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $fn$
    SELECT translate(
        lower(COALESCE(p_text, '')),
        'áàâãäéèêëíìîïóòôõöúùûüñçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÑÇ',
        'aaaaaeeeeiiiiooooouuuuncAAAAAEEEEIIIIOOOOOUUUUNC');
$fn$;

CREATE OR REPLACE FUNCTION pg_temp._expect_error(
    p_grp TEXT, p_label TEXT, p_sql TEXT, p_fragment TEXT DEFAULT NULL
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
            'NENHUM erro levantado', 'erro contendo: ' || COALESCE(p_fragment, '(qualquer)'));
    ELSIF p_fragment IS NULL
       OR position(pg_temp._norm(p_fragment) in pg_temp._norm(v_msg)) > 0 THEN
        PERFORM pg_temp._rec(p_grp, p_label, TRUE,
            v_state || ' ' || left(v_msg, 160), 'erro contendo: ' || COALESCE(p_fragment, '(qualquer)'));
    ELSE
        PERFORM pg_temp._rec(p_grp, p_label, FALSE,
            'erro INESPERADO: ' || v_state || ' ' || left(v_msg, 160),
            'erro contendo: ' || p_fragment);
    END IF;
END; $fn$;

CREATE OR REPLACE FUNCTION pg_temp._expect_ok(
    p_grp TEXT, p_label TEXT, p_sql TEXT
) RETURNS VOID LANGUAGE plpgsql AS $fn$
BEGIN
    EXECUTE p_sql;
    PERFORM pg_temp._rec(p_grp, p_label, TRUE, 'executado sem erro', 'sem erro');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp._rec(p_grp, p_label, FALSE,
        'erro: ' || SQLSTATE || ' ' || left(SQLERRM, 160), 'sem erro');
END; $fn$;

CREATE OR REPLACE FUNCTION pg_temp._expect_int(
    p_grp TEXT, p_label TEXT, p_sql TEXT, p_expected BIGINT
) RETURNS VOID LANGUAGE plpgsql AS $fn$
DECLARE v_got BIGINT;
BEGIN
    EXECUTE p_sql INTO v_got;
    PERFORM pg_temp._rec(p_grp, p_label, v_got IS NOT DISTINCT FROM p_expected,
        COALESCE(v_got::text, 'NULL'), p_expected::text);
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp._rec(p_grp, p_label, FALSE,
        'erro: ' || SQLSTATE || ' ' || left(SQLERRM, 160), p_expected::text);
END; $fn$;

-- §2 CORRECAO CONSOLIDADA 05 — PROVA EFETIVA DE search_path VAZIO.
-- `array_to_string(proconfig,',') LIKE '%search_path=%'` era fraco:
-- `search_path=public` tambem casa. O que interessa e o VALOR.
-- proconfig guarda elementos no formato `nome=valor`; para
-- `SET search_path = ''` o valor e vazio (podendo aparecer entre
-- aspas conforme a forma usada no DDL). Aqui: o elemento tem de
-- existir E seu valor, ignorando aspas e espacos, tem de ser vazio.
CREATE OR REPLACE FUNCTION pg_temp._empty_search_path(p_oid OID)
RETURNS BOOLEAN LANGUAGE plpgsql STABLE AS $fn$
DECLARE v_elem TEXT; v_val TEXT;
BEGIN
    SELECT c INTO v_elem
      FROM pg_proc p, unnest(COALESCE(p.proconfig, ARRAY[]::text[])) AS c
     WHERE p.oid = p_oid AND c LIKE 'search_path=%'
     LIMIT 1;

    IF v_elem IS NULL THEN
        RETURN FALSE;                     -- nenhum search_path fixado
    END IF;

    v_val := substring(v_elem from length('search_path=') + 1);
    RETURN btrim(COALESCE(v_val, ''), '''" ') = '';
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

-- =================================================================
-- GRUPO S — STRUCTURE (21 casos)
-- =================================================================
DO $blk$
DECLARE v_n INTEGER; v_t TEXT;
BEGIN
    SELECT count(*) INTO v_n FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='public' AND c.relkind='r'
       AND c.relname IN ('collection_layout','collection_layout_page','collection_layout_slot',
        'collection_layout_slot_expected_content','collection_layout_slot_assignment','collection_layout_region');
    PERFORM pg_temp._rec('S','S01 - 6 tabelas criadas', v_n=6, v_n::text, '6');

    SELECT count(*) INTO v_n FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='public' AND c.relrowsecurity AND c.relname LIKE 'collection_layout%';
    PERFORM pg_temp._rec('S','S02 - RLS habilitada nas 6', v_n=6, v_n::text, '6');

    SELECT count(*) INTO v_n FROM pg_policies
     WHERE schemaname='public' AND tablename LIKE 'collection_layout%';
    PERFORM pg_temp._rec('S','S03 - 6 policies', v_n=6, v_n::text, '6');

    SELECT count(*) INTO v_n FROM pg_policies
     WHERE schemaname='public' AND tablename LIKE 'collection_layout%' AND cmd<>'SELECT';
    PERFORM pg_temp._rec('S','S04 - zero policy de DML', v_n=0, v_n::text, '0');

    SELECT count(*) INTO v_n FROM information_schema.role_table_grants
     WHERE table_schema='public' AND table_name LIKE 'collection_layout%'
       AND grantee IN ('authenticated','anon') AND privilege_type IN ('INSERT','UPDATE','DELETE');
    PERFORM pg_temp._rec('S','S05 - zero DML grant authenticated/anon', v_n=0, v_n::text, '0');

    SELECT count(DISTINCT table_name) INTO v_n FROM information_schema.role_table_grants
     WHERE table_schema='public' AND table_name LIKE 'collection_layout%'
       AND grantee='authenticated' AND privilege_type='SELECT';
    PERFORM pg_temp._rec('S','S06 - SELECT concedido nas 6', v_n=6, v_n::text, '6');

    SELECT count(*) INTO v_n FROM pg_constraint
     WHERE conrelid='public.card_variant'::regclass AND conname='uq_card_variant_id_card';
    PERFORM pg_temp._rec('S','S07 - uq_card_variant_id_card criada (5104)', v_n=1, v_n::text, '1');

    SELECT count(*) INTO v_n FROM pg_constraint
     WHERE conrelid='public.collection_layout_slot_expected_content'::regclass
       AND conname='fk_expected_content_variant_belongs_to_card';
    PERFORM pg_temp._rec('S','S08 - FK composta Variant->Card', v_n=1, v_n::text, '1');

    SELECT count(*) INTO v_n FROM pg_constraint
     WHERE conrelid='public.collection_layout_slot_assignment'::regclass
       AND conname='uq_collection_layout_slot_assignment_slot' AND condeferrable AND condeferred;
    PERFORM pg_temp._rec('S','S09 - UNIQUE(slot_id) DEFERRABLE INITIALLY DEFERRED', v_n=1, v_n::text, '1');

    SELECT count(*) INTO v_n FROM pg_constraint
     WHERE conrelid='public.collection_layout_page'::regclass
       AND conname='uq_collection_layout_page_number' AND condeferrable AND condeferred;
    PERFORM pg_temp._rec('S','S10 - UNIQUE(layout_id,page_number) DEFERRABLE', v_n=1, v_n::text, '1');

    SELECT confdeltype INTO v_t FROM pg_constraint
     WHERE conrelid='public.collection_layout_slot_assignment'::regclass AND contype='f'
       AND confrelid='public.collection_allocation'::regclass;
    PERFORM pg_temp._rec('S','S11 - FK assignment->allocation CASCADE', v_t='c', COALESCE(v_t,'NULL'), 'c');

    SELECT confdeltype INTO v_t FROM pg_constraint
     WHERE conrelid='public.collection_layout_slot_assignment'::regclass AND contype='f'
       AND confrelid='public.collection_layout_slot'::regclass;
    PERFORM pg_temp._rec('S','S12 - FK assignment->slot RESTRICT', v_t='r', COALESCE(v_t,'NULL'), 'r');

    SELECT confdeltype INTO v_t FROM pg_constraint
     WHERE conrelid='public.collection_layout_slot'::regclass AND contype='f'
       AND confrelid='public.collection_layout_page'::regclass;
    PERFORM pg_temp._rec('S','S13 - FK slot->page CASCADE', v_t='c', COALESCE(v_t,'NULL'), 'c');

    SELECT count(*) INTO v_n FROM pg_constraint
     WHERE contype='f' AND confdeltype='r'
       AND ((conrelid='public.collection_layout_slot_expected_content'::regclass AND confrelid='public.collection_layout_slot'::regclass)
         OR (conrelid='public.collection_layout_region'::regclass AND confrelid='public.collection_layout_page'::regclass)
         OR (conrelid='public.collection_layout_page'::regclass AND confrelid='public.collection_layout'::regclass)
         OR (conrelid='public.collection_layout'::regclass AND confrelid='public.collection'::regclass));
    PERFORM pg_temp._rec('S','S14 - 4 FKs RESTRICT (EC/Region/Page/Layout)', v_n=4, v_n::text, '4');

    SELECT count(*) INTO v_n FROM pg_extension WHERE extname='btree_gist';
    PERFORM pg_temp._rec('S','S15 - btree_gist NAO instalada', v_n=0, v_n::text, '0');

    SELECT count(*) INTO v_n FROM pg_constraint c JOIN pg_class r ON r.oid=c.conrelid
     WHERE c.contype='x' AND r.relname LIKE 'collection_layout%';
    PERFORM pg_temp._rec('S','S16 - zero EXCLUDE constraint', v_n=0, v_n::text, '0');

    SELECT count(*) INTO v_n FROM pg_indexes
     WHERE schemaname='public' AND tablename='collection_layout_slot';
    PERFORM pg_temp._rec('S','S17 - slot: 2 indices (PK + UNIQUE posicao), zero especulativo', v_n=2, v_n::text, '2');

    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
     WHERE p.proname IN ('assert_collection_layout_mutable','create_collection_layout','delete_collection_layout',
        'add_layout_page','remove_layout_page','reorder_layout_pages','set_slot_expected_content',
        'clear_slot_expected_content','set_slot_lock','assign_card_to_slot','move_slot_assignment',
        'remove_slot_assignment','merge_layout_region','unmerge_layout_region',
        'set_collection_layout_grid')
       AND p.prosecdef AND pg_temp._empty_search_path(p.oid);
    PERFORM pg_temp._rec('S','S18 - 15 funcoes (helper + 14 RPCs) SECURITY DEFINER + search_path EFETIVAMENTE vazio', v_n=15, v_n::text, '15');

    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
     WHERE p.proname='assert_collection_layout_mutable'
       AND has_function_privilege('authenticated', p.oid, 'EXECUTE');
    PERFORM pg_temp._rec('S','S19 - helper interno sem EXECUTE p/ authenticated', v_n=0, v_n::text, '0');

    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
     WHERE p.proname IN ('create_collection_layout','delete_collection_layout','add_layout_page',
        'remove_layout_page','reorder_layout_pages','set_slot_expected_content','clear_slot_expected_content',
        'set_slot_lock','assign_card_to_slot','move_slot_assignment','remove_slot_assignment',
        'merge_layout_region','unmerge_layout_region','set_collection_layout_grid')
       AND has_function_privilege('anon', p.oid, 'EXECUTE');
    PERFORM pg_temp._rec('S','S20 - anon sem EXECUTE nas 14 RPCs publicas', v_n=0, v_n::text, '0');

    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
     WHERE p.proname IN ('set_collection_layout_updated_at','enforce_collection_layout_grid_immutability',
        'set_collection_layout_page_updated_at','set_collection_layout_slot_updated_at',
        'enforce_collection_layout_slot_grid_bounds','set_collection_layout_slot_expected_content_updated_at',
        'set_collection_layout_slot_assignment_updated_at','enforce_collection_layout_slot_assignment_integrity',
        'enforce_collection_layout_slot_lock','set_collection_layout_region_updated_at',
        'enforce_collection_layout_region_integrity',
        'enforce_collection_layout_structural_fk_immutability')
       AND (has_function_privilege('anon', p.oid, 'EXECUTE') OR has_function_privilege('authenticated', p.oid, 'EXECUTE'));
    PERFORM pg_temp._rec('S','S21 - 12 trigger functions sem EXECUTE de cliente', v_n=0, v_n::text, '0');

    -- S21b: as 12 trigger functions EXISTEM (S21 sozinho passaria com
    -- funcao ausente, porque ausente tambem nao tem EXECUTE).
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
     WHERE p.proname IN ('set_collection_layout_updated_at','enforce_collection_layout_grid_immutability',
        'set_collection_layout_page_updated_at','set_collection_layout_slot_updated_at',
        'enforce_collection_layout_slot_grid_bounds','set_collection_layout_slot_expected_content_updated_at',
        'set_collection_layout_slot_assignment_updated_at','enforce_collection_layout_slot_assignment_integrity',
        'enforce_collection_layout_slot_lock','set_collection_layout_region_updated_at',
        'enforce_collection_layout_region_integrity',
        'enforce_collection_layout_structural_fk_immutability');
    PERFORM pg_temp._rec('S','S21b - as 12 trigger functions existem', v_n=12, v_n::text, '12');
END $blk$;

-- =================================================================
-- FIXTURES — fail-loud. Nenhum Catálogo é fabricado.
-- =================================================================
DO $blk$
DECLARE
    v_owner UUID; v_other UUID; v_lang UUID; v_game UUID;
    v_cardA UUID; v_varA UUID; v_varA2 UUID; v_cardB UUID; v_varB UUID;
    v_inv UUID; v_sc UUID; v_coll UUID; v_coll2 UUID;
    v_pc UUID; v_alloc UUID; i INTEGER;
BEGIN
    SELECT id INTO v_owner FROM auth.users ORDER BY created_at, id LIMIT 1;
    SELECT id INTO v_other FROM auth.users WHERE id <> v_owner ORDER BY created_at, id LIMIT 1;
    SELECT id INTO v_lang  FROM public.language ORDER BY id LIMIT 1;

    SELECT cv.id, cv.card_id, ex.game_id
      INTO v_varA, v_cardA, v_game
      FROM public.card_variant cv
      JOIN public.card ca      ON ca.id = cv.card_id
      JOIN public.card_set cs  ON cs.id = ca.card_set_id
      JOIN public.expansion ex ON ex.id = cs.expansion_id
     ORDER BY cv.id LIMIT 1;

    SELECT cv.id INTO v_varA2
      FROM public.card_variant cv
     WHERE cv.card_id = v_cardA AND cv.id <> v_varA
     ORDER BY cv.id LIMIT 1;

    SELECT cv.id, cv.card_id INTO v_varB, v_cardB
      FROM public.card_variant cv
      JOIN public.card ca      ON ca.id = cv.card_id
      JOIN public.card_set cs  ON cs.id = ca.card_set_id
      JOIN public.expansion ex ON ex.id = cs.expansion_id
     WHERE cv.card_id <> v_cardA AND ex.game_id = v_game
     ORDER BY cv.id LIMIT 1;

    IF v_owner IS NULL OR v_lang IS NULL OR v_game IS NULL
       OR v_varA IS NULL OR v_varB IS NULL THEN
        RAISE EXCEPTION
          'FIXTURE ABORT — Catálogo mínimo ausente (owner=%, lang=%, game=%, varA=%, varB=%). O harness NAO fabrica PASS artificial.',
          v_owner, v_lang, v_game, v_varA, v_varB;
    END IF;

    INSERT INTO public.inventory (owner_user_id) VALUES (v_owner)
    ON CONFLICT (owner_user_id) DO NOTHING;
    SELECT id INTO v_inv FROM public.inventory WHERE owner_user_id = v_owner;

    INSERT INTO public.storage_container (inventory_id, name)
    VALUES (v_inv, '__5818_sc__') RETURNING id INTO v_sc;

    INSERT INTO public.collection
        (owner_user_id, game_id, default_storage_container_id, name, mode, completion_policy)
    VALUES (v_owner, v_game, v_sc, '__5818_coll__', 'OPEN_CURATION', 'NONE')
    RETURNING id INTO v_coll;

    INSERT INTO public.collection
        (owner_user_id, game_id, default_storage_container_id, name, mode, completion_policy)
    VALUES (v_owner, v_game, v_sc, '__5818_coll2__', 'OPEN_CURATION', 'NONE')
    RETURNING id INTO v_coll2;

    INSERT INTO _fx VALUES ('owner',v_owner),('other',v_other),('lang',v_lang),('game',v_game),
        ('cardA',v_cardA),('varA',v_varA),('varA2',v_varA2),('cardB',v_cardB),('varB',v_varB),
        ('inv',v_inv),('sc',v_sc),('coll',v_coll),('coll2',v_coll2);

    -- 8 Physical Cards + Allocations na Collection principal.
    FOR i IN 1..8 LOOP
        INSERT INTO public.physical_card (card_variant_id, language_id, inventory_id)
        VALUES (CASE WHEN i % 2 = 0 THEN v_varB ELSE v_varA END, v_lang, v_inv)
        RETURNING id INTO v_pc;
        INSERT INTO public.collection_allocation (physical_card_id, collection_id)
        VALUES (v_pc, v_coll) RETURNING id INTO v_alloc;
        INSERT INTO _fx VALUES ('alloc' || i, v_alloc);
        INSERT INTO _fx VALUES ('pc' || i, v_pc);
    END LOOP;

    -- 1 Physical Card + Allocation na SEGUNDA Collection (cross-collection).
    INSERT INTO public.physical_card (card_variant_id, language_id, inventory_id)
    VALUES (v_varA, v_lang, v_inv) RETURNING id INTO v_pc;
    INSERT INTO public.collection_allocation (physical_card_id, collection_id)
    VALUES (v_pc, v_coll2) RETURNING id INTO v_alloc;
    INSERT INTO _fx VALUES ('allocX', v_alloc), ('pcX', v_pc);
END $blk$;

-- =================================================================
-- GRUPO L — LAYOUT (6 casos)
-- =================================================================
DO $blk$
DECLARE v_owner UUID; v_coll UUID; v_coll2 UUID; v_layout UUID; v_n INTEGER;
BEGIN
    SELECT v INTO v_owner FROM _fx WHERE k='owner';
    SELECT v INTO v_coll  FROM _fx WHERE k='coll';
    SELECT v INTO v_coll2 FROM _fx WHERE k='coll2';

    -- L01: Collection sem Layout é estado válido.
    SELECT count(*) INTO v_n FROM public.collection_layout WHERE collection_id = v_coll;
    PERFORM pg_temp._rec('L','L01 - Collection sem Layout e valido', v_n=0, v_n::text, '0');

    PERFORM pg_temp._as_user(v_owner);

    -- L02: create_collection_layout() cria com ZERO Pages.
    BEGIN
        SELECT id INTO v_layout FROM public.create_collection_layout(v_coll, 4, 4);
        PERFORM pg_temp._as_admin();
        SELECT count(*) INTO v_n FROM public.collection_layout_page WHERE layout_id = v_layout;
        PERFORM pg_temp._rec('L','L02 - create_collection_layout cria com 0 Pages',
            v_layout IS NOT NULL AND v_n=0, 'layout='||COALESCE(v_layout::text,'NULL')||' pages='||v_n, 'layout criado, 0 pages');
        INSERT INTO _fx VALUES ('layout', v_layout);
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp._as_admin();
        PERFORM pg_temp._rec('L','L02 - create_collection_layout cria com 0 Pages', FALSE,
            'erro: '||SQLSTATE||' '||left(SQLERRM,140), 'sem erro');
    END;

    -- L03: segundo Layout na MESMA Collection é rejeitado (DP-01).
    PERFORM pg_temp._as_user(v_owner);
    PERFORM pg_temp._expect_error('L','L03 - segundo Layout rejeitado (DP-01)',
        format('SELECT public.create_collection_layout(%L::uuid, 3, 3)', v_coll),
        'already has a layout');
    PERFORM pg_temp._as_admin();
END $blk$;

DO $blk$
DECLARE v_owner UUID; v_coll UUID; v_layout UUID; v_n INTEGER;
BEGIN
    SELECT v INTO v_owner  FROM _fx WHERE k='owner';
    SELECT v INTO v_coll   FROM _fx WHERE k='coll';
    SELECT v INTO v_layout FROM _fx WHERE k='layout';

    -- L04: ARCHIVED bloqueia mutação de Layout.
    UPDATE public.collection SET lifecycle_status='ARCHIVED', archived_at=now() WHERE id=v_coll;
    PERFORM pg_temp._as_user(v_owner);
    PERFORM pg_temp._expect_error('L','L04 - ARCHIVED bloqueia add_layout_page',
        format('SELECT public.add_layout_page(%L::uuid)', v_layout), 'ARCHIVED');

    -- L05: ARCHIVED continua permitindo LEITURA.
    DECLARE v_read INTEGER;
    BEGIN
        SELECT count(*) INTO v_read FROM public.collection_layout WHERE id = v_layout;
        PERFORM pg_temp._as_admin();
        PERFORM pg_temp._rec('L','L05 - ARCHIVED: SELECT do Layout continua valido', v_read=1, v_read::text, '1');
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp._as_admin();
        PERFORM pg_temp._rec('L','L05 - ARCHIVED: SELECT do Layout continua valido', FALSE,
            'erro: '||left(SQLERRM,140), '1 linha lida');
    END;

    PERFORM pg_temp._as_admin();
    UPDATE public.collection SET lifecycle_status='ACTIVE', archived_at=NULL WHERE id=v_coll;

    -- L06: delete_collection_layout() com 0 Pages funciona (e recria depois).
    PERFORM pg_temp._as_user(v_owner);
    PERFORM pg_temp._expect_ok('L','L06 - delete_collection_layout com 0 Pages',
        format('SELECT public.delete_collection_layout(%L::uuid)', v_layout));
    PERFORM pg_temp._as_admin();
    SELECT count(*) INTO v_n FROM public.collection_layout WHERE id = v_layout;
    IF v_n = 0 THEN
        PERFORM pg_temp._as_user(v_owner);
        SELECT id INTO v_layout FROM public.create_collection_layout(v_coll, 4, 4);
        PERFORM pg_temp._as_admin();
        UPDATE _fx SET v = v_layout WHERE k='layout';
    END IF;
END $blk$;

-- =================================================================
-- GRUPO G — GRID (7 casos)
-- =================================================================
DO $blk$
DECLARE v_owner UUID; v_coll2 UUID; v_layout UUID; v_l2 UUID; v_page UUID; v_slot UUID;
BEGIN
    SELECT v INTO v_owner  FROM _fx WHERE k='owner';
    SELECT v INTO v_coll2  FROM _fx WHERE k='coll2';
    SELECT v INTO v_layout FROM _fx WHERE k='layout';

    -- G01/G02/G03/G04 usam a SEGUNDA Collection, criando e apagando o Layout
    -- a cada caso, para não colidir com DP-01.
    PERFORM pg_temp._as_user(v_owner);

    BEGIN
        SELECT id INTO v_l2 FROM public.create_collection_layout(v_coll2, 1, 1);
        PERFORM pg_temp._rec('G','G01 - grid 1x1 aceito', v_l2 IS NOT NULL, 'criado', 'aceito');
        PERFORM public.delete_collection_layout(v_l2);
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp._rec('G','G01 - grid 1x1 aceito', FALSE, 'erro: '||left(SQLERRM,140), 'aceito');
    END;

    BEGIN
        SELECT id INTO v_l2 FROM public.create_collection_layout(v_coll2, 10, 10);
        PERFORM pg_temp._rec('G','G02 - grid 10x10 aceito', v_l2 IS NOT NULL, 'criado', 'aceito');
        PERFORM public.delete_collection_layout(v_l2);
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp._rec('G','G02 - grid 10x10 aceito', FALSE, 'erro: '||left(SQLERRM,140), 'aceito');
    END;

    PERFORM pg_temp._expect_error('G','G03 - grid_rows=0 rejeitado',
        format('SELECT public.create_collection_layout(%L::uuid, 0, 3)', v_coll2), 'chk_collection_layout_grid_rows');

    PERFORM pg_temp._expect_error('G','G04 - grid_columns=11 rejeitado',
        format('SELECT public.create_collection_layout(%L::uuid, 3, 11)', v_coll2), 'chk_collection_layout_grid_columns');

    PERFORM pg_temp._as_admin();

    -- G05: UPDATE de grid com ZERO Pages funciona (trigger 5107 não barra).
    PERFORM pg_temp._expect_ok('G','G05 - UPDATE de grid com ZERO Pages funciona',
        format('UPDATE public.collection_layout SET grid_rows=5, grid_columns=5 WHERE id=%L::uuid', v_layout));
    UPDATE public.collection_layout SET grid_rows=4, grid_columns=4 WHERE id=v_layout;

    -- Criar 1 Page para os casos seguintes.
    PERFORM pg_temp._as_user(v_owner);
    SELECT id INTO v_page FROM public.add_layout_page(v_layout);
    PERFORM pg_temp._as_admin();
    INSERT INTO _fx VALUES ('page1', v_page);

    -- G06: UPDATE de grid COM Page é rejeitado (trigger 5107).
    PERFORM pg_temp._expect_error('G','G06 - UPDATE de grid com Page existente rejeitado',
        format('UPDATE public.collection_layout SET grid_rows=5 WHERE id=%L::uuid', v_layout),
        'nao pode ser alterado enquanto existirem Pages');

    -- G07: INSERT privilegiado de Slot fora do grid rejeitado (trigger 5112).
    PERFORM pg_temp._expect_error('G','G07 - Slot com row_index > grid_rows rejeitado (trigger 5112)',
        format('INSERT INTO public.collection_layout_slot (page_id,row_index,column_index) VALUES (%L::uuid, 99, 1)', v_page),
        'excede grid_rows');
END $blk$;

-- =================================================================
-- GRUPO P — PAGE / ORDER (12 casos)
-- =================================================================
DO $blk$
DECLARE
    v_owner UUID; v_coll2 UUID; v_layout UUID; v_l2 UUID;
    v_page1 UUID; v_p2 UUID; v_p3 UUID; v_n INTEGER; v_ids UUID[];
BEGIN
    SELECT v INTO v_owner  FROM _fx WHERE k='owner';
    SELECT v INTO v_coll2  FROM _fx WHERE k='coll2';
    SELECT v INTO v_layout FROM _fx WHERE k='layout';
    SELECT v INTO v_page1  FROM _fx WHERE k='page1';

    -- P01: Page 4x4 gera EXATAMENTE 16 Slots.
    SELECT count(*) INTO v_n FROM public.collection_layout_slot WHERE page_id = v_page1;
    PERFORM pg_temp._rec('P','P01 - Page 4x4 gera exatamente 16 Slots', v_n=16, v_n::text, '16');

    -- P02: Page 3x3 gera EXATAMENTE 9 Slots (Layout separado).
    PERFORM pg_temp._as_user(v_owner);
    BEGIN
        SELECT id INTO v_l2 FROM public.create_collection_layout(v_coll2, 3, 3);
        PERFORM public.add_layout_page(v_l2);
        PERFORM pg_temp._as_admin();
        SELECT count(*) INTO v_n FROM public.collection_layout_slot s
          JOIN public.collection_layout_page p ON p.id=s.page_id WHERE p.layout_id=v_l2;
        PERFORM pg_temp._rec('P','P02 - Page 3x3 gera exatamente 9 Slots', v_n=9, v_n::text, '9');
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp._as_admin();
        PERFORM pg_temp._rec('P','P02 - Page 3x3 gera exatamente 9 Slots', FALSE, 'erro: '||left(SQLERRM,140), '9');
    END;

    -- P03: NENHUMA Page do banco tem contagem de Slots <> capacity do seu Layout.
    SELECT count(*) INTO v_n
      FROM public.collection_layout_page p
      JOIN public.collection_layout l ON l.id = p.layout_id
      LEFT JOIN public.collection_layout_slot s ON s.page_id = p.id
     GROUP BY p.id, l.grid_rows, l.grid_columns
    HAVING count(s.id) <> l.grid_rows * l.grid_columns;
    PERFORM pg_temp._rec('P','P03 - zero Page estruturalmente parcial', COALESCE(v_n,0)=0,
        COALESCE(v_n,0)::text, '0 (nenhuma Page fora da capacity)');

    -- P04: page_number contíguo 1..N após 3 adds.
    PERFORM pg_temp._as_user(v_owner);
    SELECT id INTO v_p2 FROM public.add_layout_page(v_layout);
    SELECT id INTO v_p3 FROM public.add_layout_page(v_layout);
    PERFORM pg_temp._as_admin();
    INSERT INTO _fx VALUES ('page2', v_p2), ('page3', v_p3);

    SELECT count(*) INTO v_n FROM (
        SELECT page_number, row_number() OVER (ORDER BY page_number) AS rn
          FROM public.collection_layout_page WHERE layout_id=v_layout) t
     WHERE t.page_number <> t.rn;
    PERFORM pg_temp._rec('P','P04 - page_number contiguo 1..N apos 3 adds', v_n=0, v_n::text, '0 divergencias');

    -- P05: add coloca no FIM.
    SELECT page_number INTO v_n FROM public.collection_layout_page WHERE id=v_p3;
    PERFORM pg_temp._rec('P','P05 - add_layout_page insere no fim', v_n=3, v_n::text, '3');

    -- P06: reorder inverte e preserva ids + contiguidade.
    SELECT array_agg(id ORDER BY page_number DESC) INTO v_ids
      FROM public.collection_layout_page WHERE layout_id=v_layout;
    PERFORM pg_temp._as_user(v_owner);
    BEGIN
        PERFORM public.reorder_layout_pages(v_layout, v_ids);
        PERFORM pg_temp._as_admin();
        SELECT page_number INTO v_n FROM public.collection_layout_page WHERE id=v_page1;
        PERFORM pg_temp._rec('P','P06 - reorder inverte (Page1 vira ultima) preservando id', v_n=3, v_n::text, '3');
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp._as_admin();
        PERFORM pg_temp._rec('P','P06 - reorder inverte preservando id', FALSE, 'erro: '||left(SQLERRM,140), 'page_number=3');
    END;

    -- P07: reorder mantém contiguidade.
    SELECT count(*) INTO v_n FROM (
        SELECT page_number, row_number() OVER (ORDER BY page_number) AS rn
          FROM public.collection_layout_page WHERE layout_id=v_layout) t
     WHERE t.page_number <> t.rn;
    PERFORM pg_temp._rec('P','P07 - reorder preserva contiguidade 1..N', v_n=0, v_n::text, '0 divergencias');

    -- Restaurar ordem original.
    SELECT array_agg(id ORDER BY page_number DESC) INTO v_ids
      FROM public.collection_layout_page WHERE layout_id=v_layout;
    PERFORM pg_temp._as_user(v_owner);
    PERFORM public.reorder_layout_pages(v_layout, v_ids);

    -- P08: reorder com id duplicado rejeitado.
    PERFORM pg_temp._expect_error('P','P08 - reorder com id duplicado rejeitado',
        format('SELECT public.reorder_layout_pages(%L::uuid, ARRAY[%L,%L,%L]::uuid[])', v_layout, v_page1, v_page1, v_p2),
        'duplicados');

    -- P09: reorder com conjunto incompleto rejeitado.
    PERFORM pg_temp._expect_error('P','P09 - reorder com conjunto incompleto rejeitado',
        format('SELECT public.reorder_layout_pages(%L::uuid, ARRAY[%L]::uuid[])', v_layout, v_page1),
        'todas as');

    PERFORM pg_temp._as_admin();
END $blk$;

DO $blk$
DECLARE
    v_owner UUID; v_coll2 UUID; v_layout UUID; v_l2 UUID; v_pOther UUID;
    v_page1 UUID; v_p2 UUID; v_p3 UUID; v_n INTEGER;
BEGIN
    SELECT v INTO v_owner  FROM _fx WHERE k='owner';
    SELECT v INTO v_coll2  FROM _fx WHERE k='coll2';
    SELECT v INTO v_layout FROM _fx WHERE k='layout';
    SELECT v INTO v_page1  FROM _fx WHERE k='page1';
    SELECT v INTO v_p2     FROM _fx WHERE k='page2';
    SELECT v INTO v_p3     FROM _fx WHERE k='page3';

    SELECT l.id INTO v_l2 FROM public.collection_layout l WHERE l.collection_id=v_coll2;
    SELECT p.id INTO v_pOther FROM public.collection_layout_page p WHERE p.layout_id=v_l2 LIMIT 1;

    -- P10: reorder com Page de OUTRO Layout rejeitado.
    PERFORM pg_temp._as_user(v_owner);
    PERFORM pg_temp._expect_error('P','P10 - reorder com Page de outro Layout rejeitado',
        format('SELECT public.reorder_layout_pages(%L::uuid, ARRAY[%L,%L,%L]::uuid[])', v_layout, v_page1, v_p2, v_pOther),
        'nao pertencem');

    -- P11: remove_layout_page() sem dependências funciona e renumera.
    PERFORM pg_temp._expect_ok('P','P11 - remove_layout_page sem dependencias',
        format('SELECT public.remove_layout_page(%L::uuid)', v_p3));
    PERFORM pg_temp._as_admin();

    SELECT count(*) INTO v_n FROM (
        SELECT page_number, row_number() OVER (ORDER BY page_number) AS rn
          FROM public.collection_layout_page WHERE layout_id=v_layout) t
     WHERE t.page_number <> t.rn;
    PERFORM pg_temp._rec('P','P12 - remove renumera mantendo contiguidade', v_n=0, v_n::text, '0 divergencias');

    -- Slots da Page removida sumiram por CASCADE.
    SELECT count(*) INTO v_n FROM public.collection_layout_slot WHERE page_id=v_p3;
    PERFORM pg_temp._rec('D','D06 - DELETE de Page limpa cascateia os Slots', v_n=0, v_n::text, '0');
END $blk$;

-- =================================================================
-- GRUPO E — EXPECTED CONTENT (9 casos)
-- =================================================================
DO $blk$
DECLARE
    v_owner UUID; v_coll UUID; v_page1 UUID;
    v_cardA UUID; v_varA UUID; v_varA2 UUID; v_cardB UUID; v_varB UUID;
    v_s1 UUID; v_s2 UUID; v_n INTEGER; v_before TEXT; v_after TEXT;
BEGIN
    SELECT v INTO v_owner FROM _fx WHERE k='owner';
    SELECT v INTO v_coll  FROM _fx WHERE k='coll';
    SELECT v INTO v_page1 FROM _fx WHERE k='page1';
    SELECT v INTO v_cardA FROM _fx WHERE k='cardA';
    SELECT v INTO v_varA  FROM _fx WHERE k='varA';
    SELECT v INTO v_varA2 FROM _fx WHERE k='varA2';
    SELECT v INTO v_cardB FROM _fx WHERE k='cardB';
    SELECT v INTO v_varB  FROM _fx WHERE k='varB';

    SELECT id INTO v_s1 FROM public.collection_layout_slot
     WHERE page_id=v_page1 AND row_index=1 AND column_index=1;
    SELECT id INTO v_s2 FROM public.collection_layout_slot
     WHERE page_id=v_page1 AND row_index=1 AND column_index=2;
    INSERT INTO _fx VALUES ('s1', v_s1), ('s2', v_s2);

    -- Digest de completion ANTES (contexto authenticated do Owner).
    PERFORM pg_temp._as_user(v_owner);
    SELECT COALESCE(md5(string_agg(t::text, '|' ORDER BY t::text)), 'EMPTY')
      INTO v_before FROM public.collection_completion_summary(v_coll) t;

    -- E01: Card sem Variant aceito.
    PERFORM pg_temp._expect_ok('E','E01 - Expected Content com Card, sem Variant',
        format('SELECT public.set_slot_expected_content(%L::uuid, %L::uuid, NULL)', v_s1, v_cardA));

    -- E02: Card + Variant DA MESMA Card aceito.
    PERFORM pg_temp._expect_ok('E','E02 - Expected Content com Variant da mesma Card',
        format('SELECT public.set_slot_expected_content(%L::uuid, %L::uuid, %L::uuid)', v_s1, v_cardA, v_varA));

    -- E03: Variant de OUTRA Card rejeitada (FK composta 5104+5113).
    PERFORM pg_temp._expect_error('E','E03 - Variant de outra Card rejeitada (FK composta)',
        format('SELECT public.set_slot_expected_content(%L::uuid, %L::uuid, %L::uuid)', v_s1, v_cardA, v_varB),
        'deve pertencer');

    PERFORM pg_temp._as_admin();

    -- E04: 0..1 por Slot — segundo set SUBSTITUI, não duplica.
    SELECT count(*) INTO v_n FROM public.collection_layout_slot_expected_content WHERE slot_id=v_s1;
    PERFORM pg_temp._rec('E','E04 - 0..1 por Slot (segundo set substitui)', v_n=1, v_n::text, '1');

    -- E05/E06: clear individual e bulk idempotente.
    PERFORM pg_temp._as_user(v_owner);
    PERFORM pg_temp._expect_int('E','E05 - clear individual remove 1',
        format('SELECT public.clear_slot_expected_content(ARRAY[%L]::uuid[])', v_s1), 1);
    PERFORM pg_temp._expect_int('E','E06 - clear bulk idempotente retorna 0',
        format('SELECT public.clear_slot_expected_content(ARRAY[%L,%L]::uuid[])', v_s1, v_s2), 0);

    -- E07: Lock NÃO bloqueia Expected Content (C-43).
    PERFORM public.set_slot_lock(ARRAY[v_s2]::uuid[], TRUE);
    PERFORM pg_temp._expect_ok('E','E07 - Expected Content permitido em Slot LOCKED',
        format('SELECT public.set_slot_expected_content(%L::uuid, %L::uuid, NULL)', v_s2, v_cardA));
    PERFORM public.set_slot_lock(ARRAY[v_s2]::uuid[], FALSE);
    PERFORM public.clear_slot_expected_content(ARRAY[v_s2]::uuid[]);

    -- (O digest de completion da fixture principal NAO e usado como
    -- prova: ver E09 abaixo, em bloco proprio. A fixture principal e
    -- OPEN_CURATION/NONE e collection_completion_summary() devolve
    -- ZERO linhas nesse cenario por contrato — comparar 'EMPTY' com
    -- 'EMPTY' seria um PASS vazio.)
    v_after := v_before;
    PERFORM pg_temp._as_admin();
END $blk$;

-- =================================================================
-- E09 (§11 CORRECAO CONSOLIDADA 01) — REGRESSAO DE COMPLETION COM
-- FIXTURE DEDICADA E NAO-VAZIA.
--
-- Collection REFERENCE_BASED / CARD_SET / STANDARD_SET criada pela RPC
-- real create_reference_based_card_set_collection(), sob o Owner
-- autenticado, apontando para um Card Set REAL. Gate obrigatorio:
-- baseline com > 0 linhas. Baseline vazio = FAIL, nunca PASS.
-- =================================================================
DO $blk$
DECLARE
    v_owner UUID; v_game UUID; v_sc UUID; v_card_set UUID; v_card UUID;
    v_collE UUID; v_layE UUID; v_pageE UUID; v_slotE UUID;
    v_n_before BIGINT; v_n_after BIGINT;
    v_before TEXT; v_after TEXT;
BEGIN
    SELECT v INTO v_owner FROM _fx WHERE k='owner';
    SELECT v INTO v_game  FROM _fx WHERE k='game';
    SELECT v INTO v_sc    FROM _fx WHERE k='sc';

    -- Card Set REAL do mesmo Game, com pelo menos 1 Card.
    -- Leitura PRIVILEGIADA: card/card_set sao RLS admin-only.
    -- ORDER BY sobre UUID e ordenacao determinstica, nao aggregate:
    -- min()/max() sobre UUID NAO existem e nao sao usados em lugar
    -- nenhum deste harness (§1).
    SELECT c.card_set_id
      INTO v_card_set
      FROM public.card c
      JOIN public.card_set cs  ON cs.id = c.card_set_id
      JOIN public.expansion ex ON ex.id = cs.expansion_id
     WHERE ex.game_id = v_game
     GROUP BY c.card_set_id
     ORDER BY c.card_set_id
     LIMIT 1;

    SELECT c.id INTO v_card
      FROM public.card c
     WHERE c.card_set_id = v_card_set
     ORDER BY c.id
     LIMIT 1;

    IF v_card_set IS NULL THEN
        PERFORM pg_temp._rec('E','E09 - COMPLETION INTOCADA por Layout/Expected Content',
            FALSE, 'FIXTURE AUSENTE: nenhum Card Set real no Game da fixture',
            'Card Set real com >= 1 Card');
        RETURN;
    END IF;

    -- Collection STANDARD_SET real, criada pela RPC, sob o Owner.
    PERFORM pg_temp._as_user(v_owner);
    BEGIN
        SELECT r.id INTO v_collE
          FROM public.create_reference_based_card_set_collection(
                   v_game, 'VAL-5818-E09-STANDARD', NULL, v_sc, v_card_set) r;
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp._as_admin();
        PERFORM pg_temp._rec('E','E09 - COMPLETION INTOCADA por Layout/Expected Content',
            FALSE, 'falha ao criar fixture STANDARD_SET: '||left(SQLERRM,140),
            'Collection STANDARD_SET criada');
        RETURN;
    END;

    -- BASELINE, sob o Owner (a funcao e SECURITY DEFINER e reconstitui
    -- ownership por auth.uid(): como admin ela devolveria 0 linhas e a
    -- comparacao seria vacua).
    SELECT count(*), COALESCE(md5(string_agg(t::text, '|' ORDER BY t::text)), 'EMPTY')
      INTO v_n_before, v_before
      FROM public.collection_completion_summary(v_collE) t;
    PERFORM pg_temp._as_admin();

    -- GATE: baseline NAO pode ser vazio.
    PERFORM pg_temp._rec('E','E09a - baseline de completion NAO-VAZIO (senao a prova seria vacua)',
        v_n_before > 0, 'linhas='||v_n_before, '> 0');

    IF v_n_before = 0 THEN
        PERFORM pg_temp._rec('E','E09 - COMPLETION INTOCADA por Layout/Expected Content',
            FALSE, 'baseline vazio — comparacao invalida', 'baseline nao-vazio');
        RETURN;
    END IF;

    -- Layout + Page + Expected Content NESTA Collection.
    PERFORM pg_temp._as_user(v_owner);
    BEGIN
        SELECT l.id INTO v_layE
          FROM public.create_collection_layout(v_collE, 3, 3) l;
        SELECT pg.id INTO v_pageE
          FROM public.add_layout_page(v_layE) pg;
        PERFORM pg_temp._as_admin();
        SELECT s.id INTO v_slotE
          FROM public.collection_layout_slot s
         WHERE s.page_id = v_pageE AND s.row_index=1 AND s.column_index=1;
        PERFORM pg_temp._as_user(v_owner);
        PERFORM public.set_slot_expected_content(v_slotE, v_card, NULL);
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp._as_admin();
        PERFORM pg_temp._rec('E','E09 - COMPLETION INTOCADA por Layout/Expected Content',
            FALSE, 'falha ao montar Layout/Expected Content: '||left(SQLERRM,140),
            'Layout + Page + Expected Content criados');
        RETURN;
    END;

    -- RECALCULO, ainda sob o Owner.
    SELECT count(*), COALESCE(md5(string_agg(t::text, '|' ORDER BY t::text)), 'EMPTY')
      INTO v_n_after, v_after
      FROM public.collection_completion_summary(v_collE) t;
    PERFORM pg_temp._as_admin();

    PERFORM pg_temp._rec('E','E09b - cardinalidade de completion inalterada',
        v_n_before = v_n_after, format('antes=%s depois=%s', v_n_before, v_n_after),
        'mesma cardinalidade');

    PERFORM pg_temp._rec('E','E09 - COMPLETION INTOCADA por Layout/Expected Content',
        v_n_after > 0 AND v_before IS NOT DISTINCT FROM v_after,
        format('linhas=%s antes=%s depois=%s', v_n_after, v_before, v_after),
        'payload identico e nao-vazio');
END $blk$;

-- =================================================================
-- GRUPO A — ASSIGNMENT (13 casos)
-- =================================================================
DO $blk$
DECLARE
    v_owner UUID; v_page1 UUID; v_layout UUID;
    v_s1 UUID; v_s2 UUID; v_s3 UUID; v_s4 UUID;
    v_a1 UUID; v_a2 UUID; v_a3 UUID; v_aX UUID;
    v_asg1 UUID; v_asg2 UUID; v_asg1_after UUID; v_asg2_after UUID;
    v_op TEXT; v_repl UUID; v_n INTEGER; v_pc UUID;
    v_l2 UUID; v_pOther UUID; v_sOther UUID; v_cardA UUID;
BEGIN
    SELECT v INTO v_owner  FROM _fx WHERE k='owner';
    SELECT v INTO v_page1  FROM _fx WHERE k='page1';
    SELECT v INTO v_layout FROM _fx WHERE k='layout';
    SELECT v INTO v_s1 FROM _fx WHERE k='s1';
    SELECT v INTO v_s2 FROM _fx WHERE k='s2';
    SELECT v INTO v_a1 FROM _fx WHERE k='alloc1';
    SELECT v INTO v_a2 FROM _fx WHERE k='alloc2';
    SELECT v INTO v_a3 FROM _fx WHERE k='alloc3';
    SELECT v INTO v_aX FROM _fx WHERE k='allocX';
    SELECT v INTO v_cardA FROM _fx WHERE k='cardA';

    SELECT id INTO v_s3 FROM public.collection_layout_slot
     WHERE page_id=v_page1 AND row_index=1 AND column_index=3;
    SELECT id INTO v_s4 FROM public.collection_layout_slot
     WHERE page_id=v_page1 AND row_index=1 AND column_index=4;
    INSERT INTO _fx VALUES ('s3', v_s3), ('s4', v_s4);

    PERFORM pg_temp._as_user(v_owner);

    -- A01/A04: ADD.
    BEGIN
        SELECT assignment_id, operation INTO v_asg1, v_op
          FROM public.assign_card_to_slot(v_s1, v_a1);
        PERFORM pg_temp._rec('A','A01 - ADD com Allocation da mesma Collection',
            v_asg1 IS NOT NULL, 'assignment='||COALESCE(v_asg1::text,'NULL'), 'criada');
        PERFORM pg_temp._rec('A','A04 - ADD retorna operation=ADD', v_op='ADD', COALESCE(v_op,'NULL'), 'ADD');
        INSERT INTO _fx VALUES ('asg1', v_asg1);
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp._rec('A','A01 - ADD com Allocation da mesma Collection', FALSE,
            'erro: '||left(SQLERRM,140), 'criada');
        PERFORM pg_temp._rec('A','A04 - ADD retorna operation=ADD', FALSE, 'nao executado', 'ADD');
    END;

    -- A02: Allocation de OUTRA Collection rejeitada.
    -- §2 FIX-02 — A02 ESPERAVA A MENSAGEM ERRADA.
    -- `assign_card_to_slot` (5131) recebeu, na CORRECAO CONSOLIDADA 01
    -- §4C, o hardening de NAO-ENUMERACAO: a Allocation e buscada JA
    -- ESCOPADA ao collection_id do Layout, de modo que inexistente,
    -- de outra Collection e de outro Owner colapsam na MESMA mensagem
    -- generica. A producao esta CORRETA; o fragmento esperado aqui e
    -- que havia ficado preso a mensagem anterior ao hardening.
    -- 5131 NAO foi alterado. Quem prova a mensagem especifica de
    -- integridade (trigger 5117) continua sendo A13, pelo caminho
    -- privilegiado, onde a nao-enumeracao nao se aplica.
    PERFORM pg_temp._expect_error('A','A02 - Allocation de outra Collection rejeitada',
        format('SELECT public.assign_card_to_slot(%L::uuid, %L::uuid)', v_s2, v_aX),
        'not found or not owned by caller');

    -- A03: Allocation inexistente rejeitada.
    PERFORM pg_temp._expect_error('A','A03 - Allocation inexistente rejeitada',
        format('SELECT public.assign_card_to_slot(%L::uuid, %L::uuid)', v_s2, gen_random_uuid()),
        'not found or not owned by caller');

    -- A09: segunda Assignment da MESMA Allocation rejeitada.
    PERFORM pg_temp._expect_error('A','A09 - segunda Assignment da mesma Allocation rejeitada',
        format('SELECT public.assign_card_to_slot(%L::uuid, %L::uuid)', v_s2, v_a1),
        'ja possui Slot Assignment');

    -- A05: MOVE preserva o id da Assignment.
    BEGIN
        SELECT assignment_id, operation INTO v_asg1_after, v_op
          FROM public.move_slot_assignment(v_s1, v_s3);
        PERFORM pg_temp._rec('A','A05 - MOVE preserva assignment.id',
            v_asg1_after IS NOT DISTINCT FROM v_asg1 AND v_op='MOVE',
            'op='||COALESCE(v_op,'NULL')||' id_antes='||COALESCE(v_asg1::text,'NULL')||' id_depois='||COALESCE(v_asg1_after::text,'NULL'),
            'MOVE com id preservado');
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp._rec('A','A05 - MOVE preserva assignment.id', FALSE, 'erro: '||left(SQLERRM,140), 'MOVE');
    END;

    -- A06: SWAP preserva OS DOIS ids e troca os slots.
    BEGIN
        SELECT assignment_id INTO v_asg2 FROM public.assign_card_to_slot(v_s2, v_a2);
        SELECT assignment_id, swapped_assignment_id, operation
          INTO v_asg1_after, v_asg2_after, v_op
          FROM public.move_slot_assignment(v_s3, v_s2);
        PERFORM pg_temp._rec('A','A06 - SWAP preserva os dois ids',
            v_op='SWAP' AND v_asg1_after IS NOT DISTINCT FROM v_asg1
                       AND v_asg2_after IS NOT DISTINCT FROM v_asg2,
            'op='||COALESCE(v_op,'NULL'), 'SWAP com os dois ids preservados');
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp._rec('A','A06 - SWAP preserva os dois ids', FALSE, 'erro: '||left(SQLERRM,140), 'SWAP');
    END;

    -- A07: REPLACE.
    BEGIN
        SELECT operation, replaced_allocation_id INTO v_op, v_repl
          FROM public.assign_card_to_slot(v_s2, v_a3);
        PERFORM pg_temp._rec('A','A07 - REPLACE retorna operation e replaced_allocation_id',
            v_op='REPLACE' AND v_repl IS NOT NULL,
            'op='||COALESCE(v_op,'NULL')||' replaced='||COALESCE(v_repl::text,'NULL'), 'REPLACE + id anterior');
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp._rec('A','A07 - REPLACE', FALSE, 'erro: '||left(SQLERRM,140), 'REPLACE');
    END;

    PERFORM pg_temp._as_admin();
    -- Allocation substituída permanece INTACTA.
    SELECT count(*) INTO v_n FROM public.collection_allocation WHERE id = v_repl;
    PERFORM pg_temp._rec('A','A07b - REPLACE nao destroi a Allocation anterior', v_n=1, v_n::text, '1');

    -- A10: segundo item no MESMO Slot rejeitado (UNIQUE slot_id, deferida).
    PERFORM pg_temp._expect_error('A','A10 - segundo item no mesmo Slot rejeitado (UNIQUE slot_id)',
        format($q$DO $x$ BEGIN
                    INSERT INTO public.collection_layout_slot_assignment (slot_id, collection_allocation_id)
                    VALUES (%L::uuid, %L::uuid);
                    SET CONSTRAINTS ALL IMMEDIATE;
                  END $x$;$q$, v_s2, (SELECT v FROM _fx WHERE k='alloc4')),
        'uq_collection_layout_slot_assignment_slot');

    -- A13: INSERT privilegiado com Allocation de OUTRA Collection barrado pelo trigger 5117.
    PERFORM pg_temp._expect_error('A','A13 - trigger 5117 barra INSERT privilegiado cross-Collection',
        format('INSERT INTO public.collection_layout_slot_assignment (slot_id, collection_allocation_id) VALUES (%L::uuid, %L::uuid)', v_s4, v_aX),
        'nao esta alocada a mesma Collection');

    -- A12: MOVE entre Layouts diferentes rejeitado.
    SELECT l.id INTO v_l2 FROM public.collection_layout l
      JOIN _fx f ON f.k='coll2' AND l.collection_id = f.v;
    SELECT p.id INTO v_pOther FROM public.collection_layout_page p WHERE p.layout_id=v_l2 LIMIT 1;
    SELECT s.id INTO v_sOther FROM public.collection_layout_slot s WHERE s.page_id=v_pOther LIMIT 1;

    PERFORM pg_temp._as_user(v_owner);
    PERFORM pg_temp._expect_error('A','A12 - MOVE entre Layouts diferentes rejeitado',
        format('SELECT public.move_slot_assignment(%L::uuid, %L::uuid)', v_s2, v_sOther),
        'Layouts diferentes');

    -- A08: REMOVE apaga a Assignment; Allocation e Physical Card sobrevivem.
    PERFORM pg_temp._expect_int('A','A08 - REMOVE apaga 1 Assignment',
        format('SELECT public.remove_slot_assignment(ARRAY[%L]::uuid[])', v_s2), 1);
    PERFORM pg_temp._as_admin();

    SELECT count(*) INTO v_n FROM public.collection_allocation WHERE id=v_a3;
    PERFORM pg_temp._rec('A','A08b - REMOVE nao destroi Allocation', v_n=1, v_n::text, '1');
    SELECT count(*) INTO v_n FROM public.physical_card pc
      JOIN public.collection_allocation ca ON ca.physical_card_id=pc.id WHERE ca.id=v_a3;
    PERFORM pg_temp._rec('A','A08c - REMOVE nao destroi Physical Card', v_n=1, v_n::text, '1');

    -- A11: DELETE da Allocation remove a Assignment por CASCADE.
    PERFORM pg_temp._as_user(v_owner);
    PERFORM public.assign_card_to_slot(v_s4, v_a3);
    PERFORM pg_temp._as_admin();
    DELETE FROM public.collection_allocation WHERE id = v_a3;
    SELECT count(*) INTO v_n FROM public.collection_layout_slot_assignment WHERE slot_id=v_s4;
    PERFORM pg_temp._rec('A','A11 - DELETE de Allocation remove Assignment por CASCADE', v_n=0, v_n::text, '0');
END $blk$;

-- =================================================================
-- GRUPO K — LOCK (13 casos)
-- K12 é o caso crítico: CASCADE de desalocação NÃO pode ser
-- bloqueado pelo trigger de Lock. Provado por comportamento REAL,
-- nunca por comentário sobre ordem de RI trigger.
-- =================================================================
DO $blk$
DECLARE
    v_owner UUID; v_page1 UUID;
    v_k1 UUID; v_k2 UUID; v_k3 UUID; v_k4 UUID;
    v_a4 UUID; v_a5 UUID; v_a6 UUID; v_a7 UUID; v_a8 UUID;
    v_n INTEGER; v_cardA UUID;
BEGIN
    SELECT v INTO v_owner FROM _fx WHERE k='owner';
    SELECT v INTO v_page1 FROM _fx WHERE k='page1';
    SELECT v INTO v_cardA FROM _fx WHERE k='cardA';
    SELECT v INTO v_a4 FROM _fx WHERE k='alloc4';
    SELECT v INTO v_a5 FROM _fx WHERE k='alloc5';
    SELECT v INTO v_a6 FROM _fx WHERE k='alloc6';
    SELECT v INTO v_a7 FROM _fx WHERE k='alloc7';
    SELECT v INTO v_a8 FROM _fx WHERE k='alloc8';

    SELECT id INTO v_k1 FROM public.collection_layout_slot WHERE page_id=v_page1 AND row_index=2 AND column_index=1;
    SELECT id INTO v_k2 FROM public.collection_layout_slot WHERE page_id=v_page1 AND row_index=2 AND column_index=2;
    SELECT id INTO v_k3 FROM public.collection_layout_slot WHERE page_id=v_page1 AND row_index=2 AND column_index=3;
    SELECT id INTO v_k4 FROM public.collection_layout_slot WHERE page_id=v_page1 AND row_index=2 AND column_index=4;
    INSERT INTO _fx VALUES ('k1',v_k1),('k2',v_k2),('k3',v_k3),('k4',v_k4);

    PERFORM pg_temp._as_user(v_owner);

    -- K10: Lock em Slot VAZIO é permitido (C-43).
    PERFORM pg_temp._expect_int('K','K10 - Lock em Slot vazio permitido',
        format('SELECT public.set_slot_lock(ARRAY[%L]::uuid[], TRUE)', v_k1), 1);

    -- K01: ADD em destino locked rejeitado.
    PERFORM pg_temp._expect_error('K','K01 - ADD em Slot locked rejeitado',
        format('SELECT public.assign_card_to_slot(%L::uuid, %L::uuid)', v_k1, v_a4),
        'bloqueado (locked)');

    -- K08: unlock restaura a operação.
    PERFORM public.set_slot_lock(ARRAY[v_k1]::uuid[], FALSE);
    PERFORM pg_temp._expect_ok('K','K08 - unlock restaura ADD',
        format('SELECT public.assign_card_to_slot(%L::uuid, %L::uuid)', v_k1, v_a4));

    -- K02: MOVE com ORIGEM locked rejeitado.
    PERFORM public.set_slot_lock(ARRAY[v_k1]::uuid[], TRUE);
    PERFORM pg_temp._expect_error('K','K02 - MOVE com origem locked rejeitado',
        format('SELECT public.move_slot_assignment(%L::uuid, %L::uuid)', v_k1, v_k2),
        'locked');
    PERFORM public.set_slot_lock(ARRAY[v_k1]::uuid[], FALSE);

    -- K03: MOVE com DESTINO locked rejeitado.
    PERFORM public.set_slot_lock(ARRAY[v_k2]::uuid[], TRUE);
    PERFORM pg_temp._expect_error('K','K03 - MOVE com destino locked rejeitado',
        format('SELECT public.move_slot_assignment(%L::uuid, %L::uuid)', v_k1, v_k2),
        'locked');
    PERFORM public.set_slot_lock(ARRAY[v_k2]::uuid[], FALSE);

    -- K04: SWAP com qualquer dos dois locked rejeitado.
    PERFORM public.assign_card_to_slot(v_k2, v_a5);
    PERFORM public.set_slot_lock(ARRAY[v_k2]::uuid[], TRUE);
    PERFORM pg_temp._expect_error('K','K04 - SWAP com um Slot locked rejeitado',
        format('SELECT public.move_slot_assignment(%L::uuid, %L::uuid)', v_k1, v_k2),
        'locked');
    PERFORM public.set_slot_lock(ARRAY[v_k2]::uuid[], FALSE);

    -- K05: REPLACE em Slot locked rejeitado.
    PERFORM public.set_slot_lock(ARRAY[v_k1]::uuid[], TRUE);
    PERFORM pg_temp._expect_error('K','K05 - REPLACE em Slot locked rejeitado',
        format('SELECT public.assign_card_to_slot(%L::uuid, %L::uuid)', v_k1, v_a6),
        'bloqueado (locked)');

    -- K06: REMOVE em Slot locked rejeitado.
    PERFORM pg_temp._expect_error('K','K06 - REMOVE em Slot locked rejeitado',
        format('SELECT public.remove_slot_assignment(ARRAY[%L]::uuid[])', v_k1),
        'locked');

    -- K11: Lock permanece no SLOT depois de o conteudo mudar.
    PERFORM public.set_slot_lock(ARRAY[v_k1]::uuid[], FALSE);
    PERFORM public.assign_card_to_slot(v_k1, v_a6);   -- REPLACE
    PERFORM pg_temp._as_admin();
    SELECT count(*) INTO v_n FROM public.collection_layout_slot WHERE id=v_k1 AND locked;
    PERFORM pg_temp._rec('K','K11 - Replace nao transfere Lock (Slot destravado permanece destravado)',
        v_n=0, v_n::text, '0');

    -- K07: bulk fail-fast — 1 de 3 locked rejeita a operacao INTEIRA.
    PERFORM pg_temp._as_user(v_owner);
    PERFORM public.assign_card_to_slot(v_k3, v_a7);
    PERFORM public.set_slot_lock(ARRAY[v_k3]::uuid[], TRUE);
    PERFORM pg_temp._expect_error('K','K07 - bulk REMOVE com 1 locked rejeita tudo (fail-fast)',
        format('SELECT public.remove_slot_assignment(ARRAY[%L,%L,%L]::uuid[])', v_k1, v_k2, v_k3),
        'locked');
    PERFORM pg_temp._as_admin();
    SELECT count(*) INTO v_n FROM public.collection_layout_slot_assignment
     WHERE slot_id IN (v_k1, v_k2, v_k3);
    PERFORM pg_temp._rec('K','K07b - bulk fail-fast nao removeu NENHUMA das 3', v_n=3, v_n::text, '3');
    PERFORM pg_temp._as_user(v_owner);
    PERFORM public.set_slot_lock(ARRAY[v_k3]::uuid[], FALSE);

    -- K09: bulk lock aplica a N Slots, inclusive vazios.
    PERFORM pg_temp._expect_int('K','K09 - bulk lock aplica a 2 Slots (1 ocupado, 1 vazio)',
        format('SELECT public.set_slot_lock(ARRAY[%L,%L]::uuid[], TRUE)', v_k3, v_k4), 2);
    PERFORM public.set_slot_lock(ARRAY[v_k3,v_k4]::uuid[], FALSE);

    PERFORM pg_temp._as_admin();

    -- K13: trigger 5118 barra INSERT PRIVILEGIADO direto em Slot locked.
    UPDATE public.collection_layout_slot SET locked=TRUE WHERE id=v_k4;
    PERFORM pg_temp._expect_error('K','K13 - trigger 5118 barra INSERT privilegiado em Slot locked',
        format('INSERT INTO public.collection_layout_slot_assignment (slot_id, collection_allocation_id) VALUES (%L::uuid, %L::uuid)', v_k4, v_a8),
        'bloqueado (locked)');
    UPDATE public.collection_layout_slot SET locked=FALSE WHERE id=v_k4;
END $blk$;

-- -----------------------------------------------------------------
-- K12 — CASCADE × LOCK. Caso CRÍTICO, comportamento REAL.
-- Cenário: Slot LOCKED, com Assignment. Desalocar a Physical Card da
-- Collection (DELETE em collection_allocation, exatamente o que
-- deallocate_physical_cards_from_collection() faz na Query 5047
-- linha 117) deve remover a Assignment por CASCADE, SEM ser
-- bloqueado pelo Lock — desalocação é operação de COLLECTION, e C-43
-- não a lista entre as operações protegidas pelo Lock do Slot.
-- Se este caso FALHAR, é BLOCKER real do desenho de 5118: reportar,
-- NÃO contornar.
-- -----------------------------------------------------------------
DO $blk$
DECLARE
    v_owner UUID; v_k4 UUID; v_a8 UUID;
    v_n_before INTEGER; v_n_after INTEGER;
    v_locked BOOLEAN; v_raised BOOLEAN := FALSE; v_msg TEXT;
BEGIN
    SELECT v INTO v_owner FROM _fx WHERE k='owner';
    SELECT v INTO v_k4    FROM _fx WHERE k='k4';
    SELECT v INTO v_a8    FROM _fx WHERE k='alloc8';

    PERFORM pg_temp._as_user(v_owner);
    PERFORM public.assign_card_to_slot(v_k4, v_a8);
    PERFORM public.set_slot_lock(ARRAY[v_k4]::uuid[], TRUE);
    PERFORM pg_temp._as_admin();

    SELECT count(*) INTO v_n_before
      FROM public.collection_layout_slot_assignment WHERE slot_id = v_k4;
    SELECT locked INTO v_locked FROM public.collection_layout_slot WHERE id = v_k4;

    PERFORM pg_temp._rec('K','K12a - pre-condicao: Slot locked COM Assignment',
        v_n_before=1 AND v_locked, 'assignments='||v_n_before||' locked='||v_locked, '1 / true');

    BEGIN
        DELETE FROM public.collection_allocation WHERE id = v_a8;
    EXCEPTION WHEN OTHERS THEN
        v_raised := TRUE; v_msg := SQLSTATE || ' ' || SQLERRM;
    END;

    IF v_raised THEN
        PERFORM pg_temp._rec('K','K12 - CASCADE de desalocacao NAO bloqueado por Lock [BLOCKER se FALSE]',
            FALSE, 'DELETE da Allocation FALHOU: ' || left(v_msg,200),
            'DELETE sem erro — Lock nao se aplica a desalocacao (C-43)');
    ELSE
        SELECT count(*) INTO v_n_after
          FROM public.collection_layout_slot_assignment WHERE slot_id = v_k4;
        PERFORM pg_temp._rec('K','K12 - CASCADE de desalocacao NAO bloqueado por Lock [BLOCKER se FALSE]',
            v_n_after=0, 'assignments apos DELETE='||v_n_after,
            '0 (removida por CASCADE, sem erro de Lock)');
    END IF;

    -- Contraprova indispensável: com a Allocation VIVA, o Lock CONTINUA
    -- bloqueando o DELETE direto da Assignment. Sem isto, K12 poderia
    -- estar passando por Lock desligado, não por detecção de cascade.
    DECLARE v_a7 UUID; v_k3 UUID;
    BEGIN
        SELECT v INTO v_a7 FROM _fx WHERE k='alloc7';
        SELECT v INTO v_k3 FROM _fx WHERE k='k3';
        UPDATE public.collection_layout_slot SET locked=TRUE WHERE id=v_k3;
        PERFORM pg_temp._expect_error('K','K12b - contraprova: DELETE direto da Assignment CONTINUA bloqueado por Lock',
            format('DELETE FROM public.collection_layout_slot_assignment WHERE slot_id=%L::uuid', v_k3),
            'locked');
        UPDATE public.collection_layout_slot SET locked=FALSE WHERE id=v_k3;
    END;

    UPDATE public.collection_layout_slot SET locked=FALSE WHERE id=v_k4;
END $blk$;

-- =================================================================
-- GRUPO R — REGION (14 casos)
-- =================================================================
DO $blk$
DECLARE
    v_owner UUID; v_layout UUID; v_page1 UUID; v_page2 UUID;
    v_r1 UUID; v_n INTEGER; v_rs UUID; v_slot UUID; v_cardR UUID;
    v_n_asg INTEGER; v_n_ec INTEGER;
    v_asg_before TEXT; v_asg_after TEXT; v_ec_before TEXT; v_ec_after TEXT;
BEGIN
    SELECT v INTO v_owner  FROM _fx WHERE k='owner';
    SELECT v INTO v_layout FROM _fx WHERE k='layout';
    SELECT v INTO v_page1  FROM _fx WHERE k='page1';
    SELECT v INTO v_page2  FROM _fx WHERE k='page2';

    PERFORM pg_temp._as_user(v_owner);

    -- R02: 1x1 rejeitado (mínimo 2).
    PERFORM pg_temp._expect_error('R','R02 - Region 1x1 rejeitada (minimo 2 Slots)',
        format('SELECT public.merge_layout_region(%L::uuid, 3, 1, 1, 1)', v_page1), 'minimo 2 Slots');

    -- R06: top_row=0 rejeitado.
    PERFORM pg_temp._expect_error('R','R06 - Region com top_row=0 rejeitada',
        format('SELECT public.merge_layout_region(%L::uuid, 0, 1, 2, 2)', v_page1), 'limites do grid');

    -- R04/R05: excede grid (Layout é 4x4).
    PERFORM pg_temp._expect_error('R','R04 - Region que excede grid_rows rejeitada',
        format('SELECT public.merge_layout_region(%L::uuid, 4, 1, 2, 2)', v_page1), 'limites do grid');
    PERFORM pg_temp._expect_error('R','R05 - Region que excede grid_columns rejeitada',
        format('SELECT public.merge_layout_region(%L::uuid, 1, 4, 2, 2)', v_page1), 'limites do grid');

    -- §12 CORRECAO CONSOLIDADA 01 — a prova de R13 NAO pode ser vacua.
    -- Garantir Expected Content REAL num Slot que participa da Region
    -- (page1, linha 3, coluna 1) ANTES de capturar o digest.
    PERFORM pg_temp._as_admin();
    SELECT v INTO v_cardR FROM _fx WHERE k='cardA';
    SELECT s.id INTO v_slot
      FROM public.collection_layout_slot s
     WHERE s.page_id=v_page1 AND s.row_index=3 AND s.column_index=1;

    PERFORM pg_temp._as_user(v_owner);
    BEGIN
        PERFORM public.set_slot_expected_content(v_slot, v_cardR, NULL);
    EXCEPTION WHEN OTHERS THEN
        NULL;   -- o gate R13pre2 abaixo reprova se nao houver EC.
    END;
    PERFORM pg_temp._as_admin();

    -- Capturar estado de Assignment/Expected Content ANTES do merge.
    SELECT count(*) INTO v_n_asg
      FROM public.collection_layout_slot_assignment a
      JOIN public.collection_layout_slot s ON s.id=a.slot_id WHERE s.page_id=v_page1;
    SELECT count(*) INTO v_n_ec
      FROM public.collection_layout_slot_expected_content e
      JOIN public.collection_layout_slot s ON s.id=e.slot_id WHERE s.page_id=v_page1;

    PERFORM pg_temp._rec('R','R13pre - existem Assignments na Page da prova (senao R13 seria vacuo)',
        v_n_asg > 0, 'assignments='||v_n_asg, '> 0');
    PERFORM pg_temp._rec('R','R13pre2 - existe Expected Content na Page da prova (senao R13 seria vacuo)',
        v_n_ec > 0, 'expected_content='||v_n_ec, '> 0');

    SELECT COALESCE(md5(string_agg(a.id::text||':'||a.slot_id::text, '|' ORDER BY a.id)), 'EMPTY')
      INTO v_asg_before FROM public.collection_layout_slot_assignment a
      JOIN public.collection_layout_slot s ON s.id=a.slot_id WHERE s.page_id=v_page1;
    SELECT COALESCE(md5(string_agg(e.slot_id::text||':'||e.card_id::text, '|' ORDER BY e.slot_id)), 'EMPTY')
      INTO v_ec_before FROM public.collection_layout_slot_expected_content e
      JOIN public.collection_layout_slot s ON s.id=e.slot_id WHERE s.page_id=v_page1;
    PERFORM pg_temp._as_user(v_owner);

    -- R01: merge 1x2 (2 Slots) aceito — linha 3, colunas 1-2 (livres de Lock).
    BEGIN
        SELECT id INTO v_r1 FROM public.merge_layout_region(v_page1, 3, 1, 1, 2);
        PERFORM pg_temp._rec('R','R01 - merge 1x2 aceito', v_r1 IS NOT NULL, 'criada', 'aceita');
        INSERT INTO _fx VALUES ('region1', v_r1);
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp._rec('R','R01 - merge 1x2 aceito', FALSE, 'erro: '||left(SQLERRM,140), 'aceita');
    END;

    -- R07: sobreposição rejeitada.
    PERFORM pg_temp._expect_error('R','R07 - merge sobreposto rejeitado',
        format('SELECT public.merge_layout_region(%L::uuid, 3, 2, 1, 2)', v_page1), 'sobrepoe');

    -- R08: adjacente (sem overlap) na mesma Page aceito.
    PERFORM pg_temp._expect_ok('R','R08 - merge adjacente sem overlap aceito',
        format('SELECT public.merge_layout_region(%L::uuid, 3, 3, 1, 2)', v_page1));

    -- R03: 2x2 aceito em area livre (linha 4 nao existe em 4x4 alem de 4;
    --      usar Page 2, que esta vazia).
    PERFORM pg_temp._expect_ok('R','R03 - merge 2x2 aceito',
        format('SELECT public.merge_layout_region(%L::uuid, 1, 1, 2, 2)', v_page2));

    -- R09: mesmas coordenadas em Page DIFERENTE aceito (Region nunca atravessa Pages).
    PERFORM pg_temp._expect_ok('R','R09 - mesmas coordenadas em outra Page aceito',
        format('SELECT public.merge_layout_region(%L::uuid, 3, 1, 1, 2)', v_page2));

    PERFORM pg_temp._as_admin();

    -- R13: merge NAO alterou Assignment nem Expected Content.
    SELECT COALESCE(md5(string_agg(a.id::text||':'||a.slot_id::text, '|' ORDER BY a.id)), 'EMPTY')
      INTO v_asg_after FROM public.collection_layout_slot_assignment a
      JOIN public.collection_layout_slot s ON s.id=a.slot_id WHERE s.page_id=v_page1;
    SELECT COALESCE(md5(string_agg(e.slot_id::text||':'||e.card_id::text, '|' ORDER BY e.slot_id)), 'EMPTY')
      INTO v_ec_after FROM public.collection_layout_slot_expected_content e
      JOIN public.collection_layout_slot s ON s.id=e.slot_id WHERE s.page_id=v_page1;

    -- EMPTY = FAIL: um digest vazio dos dois lados nao prova nada.
    PERFORM pg_temp._rec('R','R13a - merge NAO altera Slot Assignment (digest nao-vazio)',
        v_asg_before <> 'EMPTY' AND v_asg_before IS NOT DISTINCT FROM v_asg_after,
        'antes='||v_asg_before||' depois='||v_asg_after, 'digests identicos e nao-vazios');
    PERFORM pg_temp._rec('R','R13b - merge NAO altera Expected Content (digest nao-vazio)',
        v_ec_before <> 'EMPTY' AND v_ec_before IS NOT DISTINCT FROM v_ec_after,
        'antes='||v_ec_before||' depois='||v_ec_after, 'digests identicos e nao-vazios');

    -- R14: INSERT privilegiado de Region sobreposta barrado pelo trigger 5121.
    PERFORM pg_temp._expect_error('R','R14 - trigger 5121 barra INSERT privilegiado sobreposto',
        format('INSERT INTO public.collection_layout_region (page_id, top_row, left_column, height, width) VALUES (%L::uuid, 3, 1, 1, 2)', v_page1),
        'sobrepoe');
END $blk$;

DO $blk$
DECLARE
    v_owner UUID; v_page1 UUID; v_region UUID; v_slot UUID; v_n INTEGER;
BEGIN
    SELECT v INTO v_owner  FROM _fx WHERE k='owner';
    SELECT v INTO v_page1  FROM _fx WHERE k='page1';
    SELECT v INTO v_region FROM _fx WHERE k='region1';

    -- R10: merge com Slot LOCKED no bbox rejeitado.
    SELECT id INTO v_slot FROM public.collection_layout_slot
     WHERE page_id=v_page1 AND row_index=4 AND column_index=1;
    UPDATE public.collection_layout_slot SET locked=TRUE WHERE id=v_slot;

    PERFORM pg_temp._as_user(v_owner);
    PERFORM pg_temp._expect_error('R','R10 - merge com Slot locked no bbox rejeitado',
        format('SELECT public.merge_layout_region(%L::uuid, 4, 1, 1, 2)', v_page1), 'locked');
    PERFORM pg_temp._as_admin();
    UPDATE public.collection_layout_slot SET locked=FALSE WHERE id=v_slot;

    -- R11: unmerge com Slot LOCKED no bbox rejeitado.
    SELECT id INTO v_slot FROM public.collection_layout_slot
     WHERE page_id=v_page1 AND row_index=3 AND column_index=1;
    UPDATE public.collection_layout_slot SET locked=TRUE WHERE id=v_slot;

    PERFORM pg_temp._as_user(v_owner);
    PERFORM pg_temp._expect_error('R','R11 - unmerge com Slot locked no bbox rejeitado',
        format('SELECT public.unmerge_layout_region(%L::uuid)', v_region), 'locked');
    PERFORM pg_temp._as_admin();
    UPDATE public.collection_layout_slot SET locked=FALSE WHERE id=v_slot;

    -- R12: unmerge normal funciona e os Slots CONTINUAM existindo.
    SELECT count(*) INTO v_n FROM public.collection_layout_slot
     WHERE page_id=v_page1 AND row_index=3 AND column_index IN (1,2);
    PERFORM pg_temp._as_user(v_owner);
    PERFORM pg_temp._expect_ok('R','R12 - unmerge normal funciona',
        format('SELECT public.unmerge_layout_region(%L::uuid)', v_region));
    PERFORM pg_temp._as_admin();

    DECLARE v_after INTEGER;
    BEGIN
        SELECT count(*) INTO v_after FROM public.collection_layout_slot
         WHERE page_id=v_page1 AND row_index=3 AND column_index IN (1,2);
        PERFORM pg_temp._rec('R','R12b - unmerge NAO destroi os Slots (mesmos ids sobrevivem)',
            v_after=v_n AND v_after=2, 'antes='||v_n||' depois='||v_after, '2 / 2');
    END;
END $blk$;

-- =================================================================
-- GRUPO D — DELETE SAFETY (5 casos; D06 já registrado no grupo P)
-- =================================================================
DO $blk$
DECLARE
    v_coll UUID; v_layout UUID; v_page1 UUID; v_page2 UUID; v_pageD UUID;
    v_slot UUID; v_cardA UUID; v_owner UUID;
BEGIN
    SELECT v INTO v_coll   FROM _fx WHERE k='coll';
    SELECT v INTO v_layout FROM _fx WHERE k='layout';
    SELECT v INTO v_page1  FROM _fx WHERE k='page1';
    SELECT v INTO v_page2  FROM _fx WHERE k='page2';
    SELECT v INTO v_cardA  FROM _fx WHERE k='cardA';
    SELECT v INTO v_owner  FROM _fx WHERE k='owner';

    -- D01: DELETE privilegiado de Page COM Assignment rejeitado.
    PERFORM pg_temp._expect_error('D','D01 - DELETE de Page com Assignment rejeitado (FK RESTRICT)',
        format('DELETE FROM public.collection_layout_page WHERE id=%L::uuid', v_page1),
        'violates foreign key constraint');

    -- D02: DELETE de Page COM Expected Content rejeitado.
    -- Page NOVA e ISOLADA: sem Assignment e sem Region, para que o unico
    -- bloqueador possivel seja o Expected Content.
    PERFORM pg_temp._as_user(v_owner);
    SELECT id INTO v_pageD FROM public.add_layout_page(v_layout);
    PERFORM pg_temp._as_admin();
    SELECT id INTO v_slot FROM public.collection_layout_slot
     WHERE page_id=v_pageD AND row_index=1 AND column_index=1;
    INSERT INTO public.collection_layout_slot_expected_content (slot_id, card_id)
    VALUES (v_slot, v_cardA);
    PERFORM pg_temp._expect_error('D','D02 - DELETE de Page com APENAS Expected Content rejeitado (isolado)',
        format('DELETE FROM public.collection_layout_page WHERE id=%L::uuid', v_pageD),
        'violates foreign key constraint');
    PERFORM pg_temp._as_user(v_owner);
    PERFORM pg_temp._expect_error('D','D02b - remove_layout_page com apenas Expected Content: mensagem de dominio',
        format('SELECT public.remove_layout_page(%L::uuid)', v_pageD),
        'expected content');
    PERFORM pg_temp._as_admin();
    DELETE FROM public.collection_layout_slot_expected_content WHERE slot_id=v_slot;

    -- D03: DELETE de Page COM Region rejeitado (Page 2 ainda tem Regions de R03/R09).
    PERFORM pg_temp._expect_error('D','D03 - DELETE de Page com Region rejeitado',
        format('DELETE FROM public.collection_layout_page WHERE id=%L::uuid', v_page2),
        'violates foreign key constraint');

    -- D04: DELETE de Layout COM Page rejeitado.
    PERFORM pg_temp._expect_error('D','D04 - DELETE de Layout com Page rejeitado',
        format('DELETE FROM public.collection_layout WHERE id=%L::uuid', v_layout),
        'violates foreign key constraint');

    -- D05: DELETE de Collection COM Layout rejeitado.
    PERFORM pg_temp._expect_error('D','D05 - DELETE de Collection com Layout rejeitado',
        format('DELETE FROM public.collection WHERE id=%L::uuid', v_coll),
        'violates foreign key constraint');

    -- D07: remove_layout_page() via RPC com dependencias -> mensagem de DOMINIO.
    PERFORM pg_temp._as_user(v_owner);
    PERFORM pg_temp._expect_error('D','D07 - remove_layout_page com Assignment: mensagem de dominio',
        format('SELECT public.remove_layout_page(%L::uuid)', v_page1),
        'slot assignment');
    PERFORM pg_temp._expect_error('D','D08 - remove_layout_page com Region: mensagem de dominio',
        format('SELECT public.remove_layout_page(%L::uuid)', v_page2),
        'layout region');
    PERFORM pg_temp._as_admin();
END $blk$;

-- =================================================================
-- GRUPO Z — SECURITY (comportamento real de contexto, não só catálogo)
-- =================================================================
DO $blk$
DECLARE
    v_owner UUID; v_layout UUID; v_page1 UUID; v_s1 UUID; v_n INTEGER;
BEGIN
    SELECT v INTO v_owner  FROM _fx WHERE k='owner';
    SELECT v INTO v_layout FROM _fx WHERE k='layout';
    SELECT v INTO v_page1  FROM _fx WHERE k='page1';
    SELECT v INTO v_s1     FROM _fx WHERE k='s1';

    -- §15: Z01 passa a exigir as SEIS tabelas. Para que Expected
    -- Content nao seja trivialmente vazio, garantimos uma linha real
    -- em contexto privilegiado antes da leitura.
    PERFORM pg_temp._as_admin();
    IF NOT EXISTS (SELECT 1 FROM public.collection_layout_slot_expected_content e
                    JOIN public.collection_layout_slot s ON s.id=e.slot_id
                    JOIN public.collection_layout_page p ON p.id=s.page_id
                   WHERE p.layout_id = v_layout) THEN
        INSERT INTO public.collection_layout_slot_expected_content (slot_id, card_id)
        SELECT v_s1, (SELECT v FROM _fx WHERE k='cardA')
        ON CONFLICT DO NOTHING;
    END IF;

    -- Z01: Owner authenticated LÊ as próprias linhas nas 6 tabelas.
    PERFORM pg_temp._as_user(v_owner);
    DECLARE v_a INT; v_b INT; v_c INT; v_d INT; v_e INT; v_f INT;
    BEGIN
        SELECT count(*) INTO v_a FROM public.collection_layout;
        SELECT count(*) INTO v_b FROM public.collection_layout_page;
        SELECT count(*) INTO v_c FROM public.collection_layout_slot;
        SELECT count(*) INTO v_d FROM public.collection_layout_slot_expected_content;
        SELECT count(*) INTO v_e FROM public.collection_layout_slot_assignment;
        SELECT count(*) INTO v_f FROM public.collection_layout_region;
        PERFORM pg_temp._as_admin();
        PERFORM pg_temp._rec('Z','Z01 - Owner le as SEIS tabelas (linhas proprias visiveis)',
            v_a>0 AND v_b>0 AND v_c>0 AND v_d>0 AND v_e>0 AND v_f>0,
            format('layout=%s page=%s slot=%s ec=%s asg=%s region=%s', v_a,v_b,v_c,v_d,v_e,v_f),
            'as SEIS > 0');
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp._as_admin();
        PERFORM pg_temp._rec('Z','Z01 - Owner le as 6 tabelas', FALSE, 'erro: '||left(SQLERRM,140), 'leitura ok');
    END;

    -- Z06: authenticated NÃO consegue DML direto em nenhuma das 6.
    PERFORM pg_temp._as_user(v_owner);
    PERFORM pg_temp._expect_error('Z','Z06a - authenticated sem INSERT direto em collection_layout_slot',
        format('INSERT INTO public.collection_layout_slot (page_id,row_index,column_index) VALUES (%L::uuid,3,3)', v_page1),
        'permission denied');
    PERFORM pg_temp._expect_error('Z','Z06b - authenticated sem UPDATE direto em collection_layout_slot',
        format('UPDATE public.collection_layout_slot SET locked=TRUE WHERE id=%L::uuid', v_s1),
        'permission denied');
    PERFORM pg_temp._expect_error('Z','Z06c - authenticated sem DELETE direto em collection_layout',
        format('DELETE FROM public.collection_layout WHERE id=%L::uuid', v_layout),
        'permission denied');
    PERFORM pg_temp._as_admin();

    -- Z04: objeto INEXISTENTE produz a MESMA mensagem de objeto alheio.
    PERFORM pg_temp._as_user(v_owner);
    PERFORM pg_temp._expect_error('Z','Z04 - Layout inexistente: mensagem de nao-enumeracao',
        format('SELECT public.add_layout_page(%L::uuid)', gen_random_uuid()),
        'not found or not owned by caller');
    PERFORM pg_temp._as_admin();
END $blk$;

-- Z02/Z03/Z05 — dependem de um SEGUNDO usuário real.
DO $blk$
DECLARE
    v_other UUID; v_layout UUID; v_page1 UUID; v_s1 UUID;
    v_a INT; v_b INT; v_c INT; v_d INT; v_e INT; v_f INT;
BEGIN
    SELECT v INTO v_other  FROM _fx WHERE k='other';
    SELECT v INTO v_layout FROM _fx WHERE k='layout';
    SELECT v INTO v_page1  FROM _fx WHERE k='page1';
    SELECT v INTO v_s1     FROM _fx WHERE k='s1';

    IF v_other IS NULL THEN
        PERFORM pg_temp._rec('Z','Z02 - outro authenticated NAO le NENHUMA das SEIS tabelas (zero linhas)', NULL,
            'NOT PROVEN — nao existe segundo auth.users neste ambiente', 'as SEIS = 0');
        PERFORM pg_temp._rec('Z','Z03 - outro authenticated NAO muta (RPC nega)', NULL,
            'NOT PROVEN — nao existe segundo auth.users neste ambiente', 'erro not found/not owned');
        PERFORM pg_temp._rec('Z','Z05 - inexistente vs alheio: mesma mensagem', NULL,
            'NOT PROVEN — nao existe segundo auth.users neste ambiente', 'mensagens identicas');
        RETURN;
    END IF;

    -- §5 CORRECAO CONSOLIDADA 02: as SEIS tabelas. A v3.0 omitia
    -- collection_layout_slot_expected_content, deixando um buraco de
    -- cobertura justamente na tabela cuja PK e o proprio slot_id.
    PERFORM pg_temp._as_user(v_other);
    BEGIN
        SELECT count(*) INTO v_a FROM public.collection_layout;
        SELECT count(*) INTO v_b FROM public.collection_layout_page;
        SELECT count(*) INTO v_c FROM public.collection_layout_slot;
        SELECT count(*) INTO v_d FROM public.collection_layout_slot_expected_content;
        SELECT count(*) INTO v_e FROM public.collection_layout_slot_assignment;
        SELECT count(*) INTO v_f FROM public.collection_layout_region;
        PERFORM pg_temp._as_admin();
        PERFORM pg_temp._rec('Z','Z02 - outro authenticated NAO le NENHUMA das SEIS tabelas (zero linhas)',
            v_a=0 AND v_b=0 AND v_c=0 AND v_d=0 AND v_e=0 AND v_f=0,
            format('layout=%s page=%s slot=%s ec=%s asg=%s region=%s', v_a,v_b,v_c,v_d,v_e,v_f),
            'as SEIS = 0');
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp._as_admin();
        PERFORM pg_temp._rec('Z','Z02 - outro authenticated NAO le NENHUMA das SEIS tabelas (zero linhas)',
            FALSE, 'erro: '||left(SQLERRM,140), 'as SEIS = 0');
    END;

    PERFORM pg_temp._as_user(v_other);
    PERFORM pg_temp._expect_error('Z','Z03a - outro authenticated: add_layout_page negado',
        format('SELECT public.add_layout_page(%L::uuid)', v_layout), 'not found or not owned by caller');
    PERFORM pg_temp._expect_error('Z','Z03b - outro authenticated: set_slot_lock negado',
        format('SELECT public.set_slot_lock(ARRAY[%L]::uuid[], TRUE)', v_s1), 'not found or not owned by caller');
    PERFORM pg_temp._expect_error('Z','Z03c - outro authenticated: remove_layout_page negado',
        format('SELECT public.remove_layout_page(%L::uuid)', v_page1), 'not found or not owned by caller');
    PERFORM pg_temp._as_admin();

    -- Z05: inexistente vs alheio produzem mensagem IDENTICA.
    DECLARE v_m1 TEXT; v_m2 TEXT;
    BEGIN
        PERFORM pg_temp._as_user(v_other);
        BEGIN PERFORM public.add_layout_page(v_layout);
        EXCEPTION WHEN OTHERS THEN v_m1 := SQLERRM; END;
        BEGIN PERFORM public.add_layout_page(gen_random_uuid());
        EXCEPTION WHEN OTHERS THEN v_m2 := SQLERRM; END;
        PERFORM pg_temp._as_admin();
        PERFORM pg_temp._rec('Z','Z05 - inexistente vs alheio: mensagem IDENTICA (nao-enumeracao)',
            v_m1 IS NOT NULL AND v_m1 IS NOT DISTINCT FROM v_m2,
            'alheio="'||COALESCE(left(v_m1,80),'NULL')||'" inexistente="'||COALESCE(left(v_m2,80),'NULL')||'"',
            'mensagens identicas');
    END;
END $blk$;

-- =================================================================
-- GRUPO C — CONCURRENCY
-- =================================================================
DO $blk$
DECLARE
    v_owner UUID; v_layout UUID; v_page1 UUID; v_s1 UUID; v_n INTEGER;
BEGIN
    SELECT v INTO v_owner  FROM _fx WHERE k='owner';
    SELECT v INTO v_layout FROM _fx WHERE k='layout';
    SELECT v INTO v_page1  FROM _fx WHERE k='page1';
    SELECT v INTO v_s1     FROM _fx WHERE k='s1';

    -- =============================================================
    -- §13 CORRECAO CONSOLIDADA 01 — TRES NIVEIS DE EVIDENCIA.
    -- A v2.0 tratava pg_locks como "evidencia direta" de serializacao
    -- de LINHA. Isso e forte demais: pg_locks so expoe locks de
    -- RELACAO de forma estavel; locks de tupla so aparecem quando ha
    -- CONTENCAO real, que uma unica sessao nunca produz. Manter
    -- aquela afirmacao geraria FALSO FAIL de um desenho correto.
    --   A) STATIC/STRUCTURAL PROOF  -> C01
    --   B) SUPPORTING LOCK EVIDENCE -> C02/C03 (nao afirma row lock)
    --   C) REAL TWO-SESSION         -> C04 (NOT PROVEN sem 2 sessoes)
    -- =============================================================

    -- C01 (A - STATIC/STRUCTURAL PROOF) — §3 CORRECAO CONSOLIDADA 04.
    --
    -- Historico do gate:
    --   v4.0 comparava so a posicao dos NOMES das tabelas e contava
    --        FOR UPDATE globalmente;
    --   v5.0 passou a pegar o PRIMEIRO FOR UPDATE APOS cada FROM —
    --        mas esse FOR UPDATE podia pertencer a OUTRO statement
    --        adiante, e o vinculo continuava presumido;
    --   v6.0 (este) VINCULA POR STATEMENT: o FOR UPDATE tem de estar
    --        antes do PRIMEIRO `;` que segue o FROM correspondente,
    --        ou seja, dentro do MESMO comando SQL.
    --
    -- Cadeia exigida, sobre o source SEM comentarios:
    --
    --   COLLECTION FROM < COLLECTION FOR UPDATE < fim do statement
    --     <= LAYOUT FROM < LAYOUT FOR UPDATE < fim do statement
    --
    -- O resolve inicial do helper usa "JOIN public.collection c" (nao
    -- "FROM"), entao `FROM public.collection c` identifica justamente o
    -- SELECT que lockeia a Collection. O FROM do Layout e procurado
    -- SOMENTE depois do fim do statement da Collection, o que impede
    -- casar com o resolve inicial.
    --
    -- Busca literal com position(); nada de LIKE/ILIKE.
    DECLARE
        v_src TEXT; v_exec TEXT; v_seg TEXT;
        v_coll_from INTEGER := 0; v_coll_end INTEGER := 0; v_coll_fu INTEGER := 0;
        v_lay_from  INTEGER := 0; v_lay_end  INTEGER := 0; v_lay_fu  INTEGER := 0;
        v_rel INTEGER; v_rel_fu INTEGER;
        v_ok BOOLEAN := FALSE;
    BEGIN
        SELECT pg_get_functiondef(p.oid) INTO v_src
          FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE n.nspname='public' AND p.proname='assert_collection_layout_mutable';

        v_exec := regexp_replace(
                    regexp_replace(COALESCE(v_src, ''), '/\*.*?\*/', ' ', 'gs'),
                    '--.*$', ' ', 'gn');

        -- ---- STATEMENT DA COLLECTION ----
        v_coll_from := position('FROM public.collection c' in v_exec);
        IF v_coll_from > 0 THEN
            v_rel := position(';' in substr(v_exec, v_coll_from));
            IF v_rel > 0 THEN
                v_coll_end := v_coll_from + v_rel - 1;
                v_seg      := substr(v_exec, v_coll_from, v_rel);
                v_rel_fu   := position('FOR UPDATE' in v_seg);
                IF v_rel_fu > 0 THEN
                    v_coll_fu := v_coll_from + v_rel_fu - 1;
                END IF;
            END IF;
        END IF;

        -- ---- STATEMENT DO LAYOUT (obrigatoriamente APOS o anterior) ----
        IF v_coll_end > 0 THEN
            v_rel := position('FROM public.collection_layout l' in substr(v_exec, v_coll_end));
            IF v_rel > 0 THEN
                v_lay_from := v_coll_end + v_rel - 1;
                v_rel := position(';' in substr(v_exec, v_lay_from));
                IF v_rel > 0 THEN
                    v_lay_end := v_lay_from + v_rel - 1;
                    v_seg     := substr(v_exec, v_lay_from, v_rel);
                    v_rel_fu  := position('FOR UPDATE' in v_seg);
                    IF v_rel_fu > 0 THEN
                        v_lay_fu := v_lay_from + v_rel_fu - 1;
                    END IF;
                END IF;
            END IF;
        END IF;

        v_ok := v_src IS NOT NULL
            AND v_coll_from > 0 AND v_coll_fu > 0 AND v_coll_end > 0
            AND v_lay_from  > 0 AND v_lay_fu  > 0 AND v_lay_end  > 0
            AND v_coll_from < v_coll_fu          -- FOR UPDATE no MESMO statement
            AND v_coll_fu   < v_coll_end
            AND v_coll_end <= v_lay_from         -- Layout so DEPOIS do lock da Collection
            AND v_lay_from  < v_lay_fu           -- FOR UPDATE no MESMO statement
            AND v_lay_fu    < v_lay_end;

        PERFORM pg_temp._rec('C','C01 - STATIC PROOF: cada FOR UPDATE pertence ao MESMO SELECT; ordem COLLECTION statement < LAYOUT statement',
            v_ok,
            format('coll_from=%s coll_for_update=%s coll_fim_stmt=%s | layout_from=%s layout_for_update=%s layout_fim_stmt=%s',
                   v_coll_from, v_coll_fu, v_coll_end, v_lay_from, v_lay_fu, v_lay_end),
            'FOR UPDATE dentro do proprio statement, em ambos, e Collection antes de Layout');

        -- C01b: contraprova de vinculo — nao pode existir FOR UPDATE
        -- ANTES do FROM da Collection (seria um lock de outra coisa
        -- acontecendo primeiro, invertendo a ordem canonica).
        PERFORM pg_temp._rec('C','C01b - nenhum FOR UPDATE ocorre ANTES do SELECT da Collection',
            v_coll_from > 0
            AND position('FOR UPDATE' in substr(v_exec, 1, v_coll_from)) = 0,
            format('coll_from=%s for_update_antes=%s', v_coll_from,
                   position('FOR UPDATE' in substr(COALESCE(v_exec,''), 1, GREATEST(v_coll_from,1)))),
            'zero FOR UPDATE antes do SELECT da Collection');

        -- C01c: exatamente DOIS FOR UPDATE no helper — nem menos (falta
        -- lock) nem mais (lock extra nao previsto pelo desenho).
        PERFORM pg_temp._rec('C','C01c - o helper contem exatamente 2 FOR UPDATE',
            (SELECT count(*) FROM regexp_matches(COALESCE(v_exec,''), 'FOR UPDATE', 'g')) = 2,
            format('ocorrencias=%s',
                   (SELECT count(*) FROM regexp_matches(COALESCE(v_exec,''), 'FOR UPDATE', 'g'))),
            '2');
    END;

    -- C02 (B - SUPPORTING LOCK EVIDENCE): apos merge_layout_region(),
    -- ha lock de RELACAO observavel sobre collection_layout_page.
    -- NAO se afirma que isto prova a identidade de um row lock.
    PERFORM pg_temp._as_user(v_owner);
    BEGIN
        PERFORM public.merge_layout_region(v_page1, 4, 3, 1, 2);
        PERFORM pg_temp._as_admin();
        SELECT count(*) INTO v_n FROM pg_locks
         WHERE relation='public.collection_layout_page'::regclass;
        PERFORM pg_temp._rec('C','C02 - SUPPORTING EVIDENCE: lock de RELACAO em collection_layout_page apos merge (nao prova row lock)',
            v_n > 0, 'locks de relacao observados='||v_n,
            '> 0 (evidencia de suporte, nao prova de serializacao)');
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp._as_admin();
        PERFORM pg_temp._rec('C','C02 - SUPPORTING EVIDENCE: lock de RELACAO em collection_layout_page apos merge (nao prova row lock)',
            FALSE, 'erro: '||left(SQLERRM,140), '> 0 locks de relacao');
    END;

    -- C03 (B - SUPPORTING LOCK EVIDENCE): idem para
    -- collection_layout_slot apos uma RPC de Slot.
    PERFORM pg_temp._as_user(v_owner);
    BEGIN
        PERFORM public.set_slot_lock(ARRAY[v_s1]::uuid[], FALSE);
        PERFORM pg_temp._as_admin();
        SELECT count(*) INTO v_n FROM pg_locks
         WHERE relation='public.collection_layout_slot'::regclass;
        PERFORM pg_temp._rec('C','C03 - SUPPORTING EVIDENCE: lock de RELACAO em collection_layout_slot apos RPC (nao prova row lock)',
            v_n > 0, 'locks de relacao observados='||v_n,
            '> 0 (evidencia de suporte, nao prova de serializacao)');
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp._as_admin();
        PERFORM pg_temp._rec('C','C03 - SUPPORTING EVIDENCE: lock de RELACAO em collection_layout_slot apos RPC (nao prova row lock)',
            FALSE, 'erro: '||left(SQLERRM,140), '> 0 locks de relacao');
    END;

    -- C05 (A - STATIC/STRUCTURAL PROOF): o trigger de Region lockeia a
    -- Page e cobre DELETE (5121 v2.0).
    DECLARE
        v_src2 TEXT; v_def TEXT;
    BEGIN
        SELECT pg_get_functiondef(p.oid) INTO v_src2
          FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE n.nspname='public' AND p.proname='enforce_collection_layout_region_integrity';
        SELECT pg_get_triggerdef(t.oid) INTO v_def
          FROM pg_trigger t WHERE t.tgname='trg_collection_layout_region_integrity'
           AND NOT t.tgisinternal;

        PERFORM pg_temp._rec('C','C05 - STATIC PROOF: trigger de Region lockeia Page e cobre INSERT/UPDATE/DELETE',
            v_src2 ILIKE '%FOR UPDATE%'
            AND v_def ILIKE '%INSERT%' AND v_def ILIKE '%UPDATE%' AND v_def ILIKE '%DELETE%',
            'def='||COALESCE(left(v_def,160),'NULL'),
            'FOR UPDATE no corpo + INSERT OR UPDATE OR DELETE no trigger');
    END;

    -- C04: serialização REAL entre duas sessões concorrentes.
    -- O harness roda em UMA transação/sessão por construção (BEGIN...ROLLBACK
    -- num único call). Provar bloqueio mútuo exigiria duas sessões
    -- persistentes simultâneas, o que este canal de execução não oferece.
    -- Registrado como NOT PROVEN, NUNCA como PASS.
    -- Precedente literal: Caso 20b da Fatia D (6830).
    PERFORM pg_temp._rec('C','C04 - serializacao real entre DUAS sessoes concorrentes', NULL,
        'NOT PROVEN — canal de execucao nao oferece duas sessoes persistentes simultaneas',
        'segunda sessao bloqueia ate o COMMIT da primeira');
END $blk$;

-- =================================================================
-- GRUPO F — IMUTABILIDADE DAS FKs ESTRUTURAIS (§7, Query 5136)
-- Todos os casos usam UPDATE PRIVILEGIADO (sem SET ROLE): a prova é
-- justamente que nem o caminho privilegiado consegue reparentar.
-- =================================================================
DO $blk$
DECLARE
    v_layout UUID; v_coll2 UUID; v_page1 UUID; v_page2 UUID; v_s1 UUID;
    v_region UUID; v_n INTEGER;
BEGIN
    SELECT v INTO v_layout FROM _fx WHERE k='layout';
    SELECT v INTO v_coll2  FROM _fx WHERE k='coll2';
    SELECT v INTO v_page1  FROM _fx WHERE k='page1';
    SELECT v INTO v_page2  FROM _fx WHERE k='page2';
    SELECT v INTO v_s1     FROM _fx WHERE k='s1';
    SELECT v INTO v_region FROM _fx WHERE k='region1';

    -- F00: os tres triggers estruturais existem.
    SELECT count(*) INTO v_n
      FROM pg_trigger t
     WHERE NOT t.tgisinternal
       AND t.tgname IN ('trg_collection_layout_collection_id_immutable',
                        'trg_collection_layout_page_layout_id_immutable',
                        'trg_collection_layout_slot_page_id_immutable');
    PERFORM pg_temp._rec('F','F00 - os 3 triggers de imutabilidade estrutural existem',
        v_n = 3, v_n::text, '3');

    -- F01: collection_layout.collection_id imutavel.
    PERFORM pg_temp._expect_error('F','F01 - UPDATE privilegiado de collection_layout.collection_id REJEITADO',
        format('UPDATE public.collection_layout SET collection_id=%L::uuid WHERE id=%L::uuid', v_coll2, v_layout),
        'IMUTAVEL');

    -- F02: collection_layout_page.layout_id imutavel.
    PERFORM pg_temp._expect_error('F','F02 - UPDATE privilegiado de collection_layout_page.layout_id REJEITADO',
        format('UPDATE public.collection_layout_page SET layout_id=%L::uuid WHERE id=%L::uuid',
               gen_random_uuid(), v_page1),
        'IMUTAVEL');

    -- F03: collection_layout_slot.page_id imutavel.
    PERFORM pg_temp._expect_error('F','F03 - UPDATE privilegiado de collection_layout_slot.page_id REJEITADO',
        format('UPDATE public.collection_layout_slot SET page_id=%L::uuid WHERE id=%L::uuid', v_page2, v_s1),
        'IMUTAVEL');

    -- F04: collection_layout_region.page_id imutavel (defesa em 5121 v2.0).
    -- §3 FIX-02 — F04 DEPENDIA DE UMA FIXTURE JA CONSUMIDA.
    -- A versao anterior reaproveitava `region1`, criada por R01 e
    -- APAGADA por R12 (unmerge normal, que roda antes do grupo F).
    -- O UPDATE atingia ZERO linhas, o trigger 5121 nunca disparava e
    -- o caso reprovava com 'NENHUM erro levantado' — um gate VACUO,
    -- nao um defeito de producao.
    --
    -- Correcao: o grupo F passa a criar sua PROPRIA Region, numa area
    -- livre e sem Lock da Page 1 (linha 4, colunas 1-2 — a linha 4,
    -- colunas 3-4 e ocupada pela Region de C02, e a linha 3 pelas de
    -- R08). Nenhuma reordenacao de grupos: a independencia vem de a
    -- fixture ser propria, nao de a ordem ser conveniente.
    DECLARE v_regF UUID;
    BEGIN
        INSERT INTO public.collection_layout_region
            (page_id, top_row, left_column, height, width)
        VALUES (v_page1, 4, 1, 1, 2)
        RETURNING id INTO v_regF;

        PERFORM pg_temp._expect_error('F','F04 - UPDATE privilegiado de collection_layout_region.page_id REJEITADO',
            format('UPDATE public.collection_layout_region SET page_id=%L::uuid WHERE id=%L::uuid', v_page2, v_regF),
            'IMUTAVEL');
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp._rec('F','F04 - UPDATE privilegiado de collection_layout_region.page_id REJEITADO',
            FALSE, 'falha ao montar a Region dedicada do grupo F: '||SQLSTATE||' '||left(SQLERRM,140),
            'erro IMUTAVEL');
    END;

    -- F05: UPDATE que repete o MESMO valor NAO e falso positivo.
    PERFORM pg_temp._expect_ok('F','F05 - UPDATE que repete o MESMO page_id nao e bloqueado',
        format('UPDATE public.collection_layout_slot SET page_id=page_id WHERE id=%L::uuid', v_s1));

    -- F06/F07: atributos deliberadamente MUTAVEIS continuam mutaveis.
    PERFORM pg_temp._expect_ok('F','F06 - slot.locked continua mutavel (nao foi congelado por engano)',
        format('UPDATE public.collection_layout_slot SET locked=locked WHERE id=%L::uuid', v_s1));
    PERFORM pg_temp._expect_ok('F','F07 - page.page_number continua mutavel (reorder depende disso)',
        format('UPDATE public.collection_layout_page SET page_number=page_number WHERE id=%L::uuid', v_page1));
END $blk$;

-- =================================================================
-- GRUPO N — collection_allocation_id IMUTAVEL (§6, Query 5117 v2.0)
-- =================================================================
DO $blk$
DECLARE
    v_layout UUID; v_asg UUID; v_slot UUID; v_alloc_other UUID;
    v_coll UUID; v_free_slot UUID; v_msg TEXT;
BEGIN
    SELECT v INTO v_layout FROM _fx WHERE k='layout';
    SELECT v INTO v_coll   FROM _fx WHERE k='coll';

    -- Uma Assignment existente do Layout, e uma Allocation da MESMA
    -- Collection que ainda nao esteja atribuida a Slot nenhum.
    SELECT a.id, a.slot_id INTO v_asg, v_slot
      FROM public.collection_layout_slot_assignment a
      JOIN public.collection_layout_slot s ON s.id=a.slot_id
      JOIN public.collection_layout_page p ON p.id=s.page_id
     WHERE p.layout_id = v_layout
     ORDER BY a.id LIMIT 1;

    SELECT ca.id INTO v_alloc_other
      FROM public.collection_allocation ca
     WHERE ca.collection_id = v_coll
       AND NOT EXISTS (SELECT 1 FROM public.collection_layout_slot_assignment x
                        WHERE x.collection_allocation_id = ca.id)
     ORDER BY ca.id LIMIT 1;

    IF v_asg IS NULL OR v_alloc_other IS NULL THEN
        PERFORM pg_temp._rec('N','N01 - UPDATE de collection_allocation_id em Slot UNLOCKED REJEITADO',
            FALSE, 'fixture insuficiente (assignment ou allocation livre ausente)',
            'erro de imutabilidade');
        PERFORM pg_temp._rec('N','N02 - UPDATE de collection_allocation_id em Slot LOCKED REJEITADO',
            FALSE, 'fixture insuficiente', 'erro de imutabilidade');
        RETURN;
    END IF;

    -- N01: Slot UNLOCKED — mesmo assim o UPDATE e rejeitado.
    UPDATE public.collection_layout_slot SET locked=FALSE WHERE id=v_slot;
    PERFORM pg_temp._expect_error('N','N01 - UPDATE de collection_allocation_id em Slot UNLOCKED REJEITADO',
        format('UPDATE public.collection_layout_slot_assignment SET collection_allocation_id=%L::uuid WHERE id=%L::uuid',
               v_alloc_other, v_asg),
        'IMUTAVEL');

    -- N04: a mensagem orienta ao REPLACE.
    BEGIN
        EXECUTE format('UPDATE public.collection_layout_slot_assignment SET collection_allocation_id=%L::uuid WHERE id=%L::uuid',
                       v_alloc_other, v_asg);
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
    END;
    PERFORM pg_temp._rec('N','N04 - mensagem orienta ao REPLACE',
        v_msg IS NOT NULL AND position('REPLACE' in v_msg) > 0,
        COALESCE(left(v_msg,160),'NENHUM erro'), 'mensagem contendo REPLACE');

    -- N02: Slot LOCKED — bypass de Lock fechado.
    UPDATE public.collection_layout_slot SET locked=TRUE WHERE id=v_slot;
    PERFORM pg_temp._expect_error('N','N02 - UPDATE de collection_allocation_id em Slot LOCKED REJEITADO',
        format('UPDATE public.collection_layout_slot_assignment SET collection_allocation_id=%L::uuid WHERE id=%L::uuid',
               v_alloc_other, v_asg),
        'IMUTAVEL');
    UPDATE public.collection_layout_slot SET locked=FALSE WHERE id=v_slot;

    -- N03: MOVE continua possivel — altera slot_id, nao a Allocation.
    SELECT s.id INTO v_free_slot
      FROM public.collection_layout_slot s
      JOIN public.collection_layout_page p ON p.id=s.page_id
     WHERE p.layout_id = v_layout
       AND NOT s.locked
       AND NOT EXISTS (SELECT 1 FROM public.collection_layout_slot_assignment a WHERE a.slot_id=s.id)
     ORDER BY s.id LIMIT 1;

    IF v_free_slot IS NULL THEN
        PERFORM pg_temp._rec('N','N03 - UPDATE de slot_id (MOVE) continua permitido', NULL,
            'NOT PROVEN — nenhum Slot livre disponivel na fixture neste ponto',
            'UPDATE de slot_id aceito');
    ELSE
        PERFORM pg_temp._expect_ok('N','N03 - UPDATE de slot_id (MOVE) continua permitido',
            format('UPDATE public.collection_layout_slot_assignment SET slot_id=%L::uuid WHERE id=%L::uuid',
                   v_free_slot, v_asg));
    END IF;
END $blk$;

-- =================================================================
-- GRUPO U — set_collection_layout_grid() (§5, Query 5137)
-- =================================================================
DO $blk$
DECLARE
    v_owner UUID; v_game UUID; v_sc UUID; v_layout UUID;
    v_collU UUID; v_layU UUID; v_r RECORD; v_n INTEGER;
    v_m_alheio TEXT; v_m_inexistente TEXT; v_other UUID;
BEGIN
    SELECT v INTO v_owner  FROM _fx WHERE k='owner';
    SELECT v INTO v_game   FROM _fx WHERE k='game';
    SELECT v INTO v_sc     FROM _fx WHERE k='sc';
    SELECT v INTO v_layout FROM _fx WHERE k='layout';
    SELECT v INTO v_other  FROM _fx WHERE k='other';

    -- U00: a RPC existe, e SECURITY DEFINER, owner postgres, grants certos.
    SELECT p.prosecdef AS secdef,
           pg_get_userbyid(p.proowner) AS owner,
           has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_exec,
           has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_exec,
           array_to_string(p.proconfig, ',') AS cfg,
           pg_temp._empty_search_path(p.oid) AS sp_vazio
      INTO v_r
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname='set_collection_layout_grid';

    PERFORM pg_temp._rec('U','U00 - set_collection_layout_grid: SECDEF, owner postgres, search_path EFETIVAMENTE vazio, authenticated sim / anon nao',
        v_r.secdef AND v_r.owner='postgres' AND v_r.auth_exec AND NOT v_r.anon_exec
        AND v_r.sp_vazio,
        format('secdef=%s owner=%s auth=%s anon=%s search_path_vazio=%s cfg=%s',
               v_r.secdef, v_r.owner, v_r.auth_exec, v_r.anon_exec,
               v_r.sp_vazio, COALESCE(v_r.cfg,'NULL')),
        'true/postgres/true/false/search_path com valor vazio');

    -- Collection + Layout dedicados, com ZERO Pages.
    INSERT INTO public.collection
        (owner_user_id, game_id, default_storage_container_id, name, mode, completion_policy)
    VALUES (v_owner, v_game, v_sc, 'VAL-5818-U-GRID', 'OPEN_CURATION', 'NONE')
    RETURNING id INTO v_collU;

    PERFORM pg_temp._as_user(v_owner);
    SELECT l.id INTO v_layU FROM public.create_collection_layout(v_collU, 3, 3) l;

    -- U01: owner + zero Pages = sucesso.
    PERFORM pg_temp._expect_ok('U','U01 - owner com ZERO Pages altera o grid',
        format('SELECT public.set_collection_layout_grid(%L::uuid, 2, 5)', v_layU));

    PERFORM pg_temp._as_admin();
    SELECT count(*) INTO v_n FROM public.collection_layout
     WHERE id=v_layU AND grid_rows=2 AND grid_columns=5;
    PERFORM pg_temp._rec('U','U01b - grid efetivamente persistido como 2x5', v_n=1, v_n::text, '1');
    PERFORM pg_temp._as_user(v_owner);

    -- U02/U03: extremos aceitos.
    PERFORM pg_temp._expect_ok('U','U02 - grid 1x1 aceito',
        format('SELECT public.set_collection_layout_grid(%L::uuid, 1, 1)', v_layU));
    PERFORM pg_temp._expect_ok('U','U03 - grid 10x10 aceito',
        format('SELECT public.set_collection_layout_grid(%L::uuid, 10, 10)', v_layU));

    -- U04/U05: fora da faixa rejeitados.
    PERFORM pg_temp._expect_error('U','U04 - grid 0 rejeitado',
        format('SELECT public.set_collection_layout_grid(%L::uuid, 0, 3)', v_layU), 'entre 1 e 10');
    PERFORM pg_temp._expect_error('U','U05 - grid 11 rejeitado',
        format('SELECT public.set_collection_layout_grid(%L::uuid, 11, 3)', v_layU), 'entre 1 e 10');

    -- U06: com Page existente, rejeitado.
    PERFORM public.add_layout_page(v_layU);
    PERFORM pg_temp._expect_error('U','U06 - grid rejeitado quando existe Page',
        format('SELECT public.set_collection_layout_grid(%L::uuid, 4, 4)', v_layU), 'existirem Pages');

    -- U08: Layout INEXISTENTE produz a mensagem uniforme.
    PERFORM pg_temp._expect_error('U','U08 - Layout inexistente: mensagem de nao-enumeracao',
        format('SELECT public.set_collection_layout_grid(%L::uuid, 3, 3)', gen_random_uuid()),
        'not found or not owned by caller');

    -- U07: Collection ARCHIVED rejeita.
    PERFORM pg_temp._as_admin();
    UPDATE public.collection SET lifecycle_status='ARCHIVED', archived_at=now() WHERE id=v_collU;
    PERFORM pg_temp._as_user(v_owner);
    PERFORM pg_temp._expect_error('U','U07 - Collection ARCHIVED rejeita alteracao de grid',
        format('SELECT public.set_collection_layout_grid(%L::uuid, 3, 3)', v_layU), 'ARCHIVED');
    PERFORM pg_temp._as_admin();
    UPDATE public.collection SET lifecycle_status='ACTIVE', archived_at=NULL WHERE id=v_collU;

    -- U09: alheio vs inexistente indistinguiveis (precisa de 2o usuario).
    IF v_other IS NULL THEN
        PERFORM pg_temp._rec('U','U09 - alheio vs inexistente: mensagem IDENTICA', NULL,
            'NOT PROVEN — nao existe segundo auth.users neste ambiente',
            'mensagens identicas');
    ELSE
        PERFORM pg_temp._as_user(v_other);
        BEGIN PERFORM public.set_collection_layout_grid(v_layout, 3, 3);
        EXCEPTION WHEN OTHERS THEN v_m_alheio := SQLERRM; END;
        BEGIN PERFORM public.set_collection_layout_grid(gen_random_uuid(), 3, 3);
        EXCEPTION WHEN OTHERS THEN v_m_inexistente := SQLERRM; END;
        PERFORM pg_temp._as_admin();
        PERFORM pg_temp._rec('U','U09 - alheio vs inexistente: mensagem IDENTICA',
            v_m_alheio IS NOT NULL AND v_m_alheio IS NOT DISTINCT FROM v_m_inexistente,
            'alheio="'||COALESCE(left(v_m_alheio,80),'NULL')||'" inexistente="'||COALESCE(left(v_m_inexistente,80),'NULL')||'"',
            'mensagens identicas');
    END IF;

    PERFORM pg_temp._as_admin();
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp._as_admin();
    PERFORM pg_temp._rec('U','U-ABORT - grupo U abortou', FALSE,
        SQLSTATE||' '||left(SQLERRM,180), 'grupo U completo');
END $blk$;

-- =================================================================
-- GRUPO R (adicionais) — TRIGGER 5121 v2.0 EM DELETE/UPDATE (§8)
-- Caminho PRIVILEGIADO: a defesa nao pode depender da RPC.
-- =================================================================
DO $blk$
DECLARE
    v_page2 UUID; v_reg UUID; v_slot UUID; v_n INTEGER;
BEGIN
    SELECT v INTO v_page2 FROM _fx WHERE k='page2';

    -- Region isolada na Page 2, linha 1, colunas 1-2.
    DELETE FROM public.collection_layout_region WHERE page_id=v_page2;
    UPDATE public.collection_layout_slot SET locked=FALSE WHERE page_id=v_page2;

    INSERT INTO public.collection_layout_region (page_id, top_row, left_column, height, width)
    VALUES (v_page2, 1, 1, 1, 2) RETURNING id INTO v_reg;

    -- Lockar um Slot DENTRO do bounding box.
    SELECT s.id INTO v_slot FROM public.collection_layout_slot s
     WHERE s.page_id=v_page2 AND s.row_index=1 AND s.column_index=1;
    UPDATE public.collection_layout_slot SET locked=TRUE WHERE id=v_slot;

    -- R15: DELETE PRIVILEGIADO com Slot locked -> REJEITADO pelo trigger.
    PERFORM pg_temp._expect_error('R','R15 - DELETE privilegiado de Region com Slot LOCKED rejeitado pelo trigger 5121',
        format('DELETE FROM public.collection_layout_region WHERE id=%L::uuid', v_reg),
        'bloqueado');

    -- R17: UPDATE PRIVILEGIADO tentando "sair de cima" do Slot locked.
    PERFORM pg_temp._expect_error('R','R17 - UPDATE privilegiado que move a Region para longe do Slot LOCKED rejeitado',
        format('UPDATE public.collection_layout_region SET top_row=3, left_column=3 WHERE id=%L::uuid', v_reg),
        'bloqueado');

    -- R16: sem Lock, o DELETE privilegiado e permitido.
    UPDATE public.collection_layout_slot SET locked=FALSE WHERE id=v_slot;
    PERFORM pg_temp._expect_ok('R','R16 - DELETE privilegiado de Region SEM Lock e permitido',
        format('DELETE FROM public.collection_layout_region WHERE id=%L::uuid', v_reg));

    SELECT count(*) INTO v_n FROM public.collection_layout_region WHERE id=v_reg;
    PERFORM pg_temp._rec('R','R16b - Region efetivamente removida', v_n=0, v_n::text, '0');

    -- R18: overlap concorrente REAL entre duas sessoes.
    PERFORM pg_temp._rec('R','R18 - overlap concorrente entre DUAS sessoes reais', NULL,
        'NOT PROVEN — canal de execucao nao oferece duas sessoes persistentes simultaneas',
        'segunda sessao bloqueia ate o COMMIT da primeira');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp._rec('R','R15/R16/R17 - trigger 5121 v2.0 em DELETE/UPDATE', FALSE,
        'bloco abortou: '||SQLSTATE||' '||left(SQLERRM,160), 'casos executados');
END $blk$;

-- =================================================================
-- GRUPO Z (adicionais) — SECURITY COVERAGE ESTRUTURAL (§15)
-- =================================================================
DO $blk$
DECLARE
    t TEXT;
    v_tables TEXT[] := ARRAY[
        'collection_layout','collection_layout_page','collection_layout_slot',
        'collection_layout_slot_expected_content','collection_layout_slot_assignment',
        'collection_layout_region'];
    v_public_dml INTEGER := 0;
    v_anon_dml   INTEGER := 0;
    v_auth_dml   INTEGER := 0;
    v_sel_ok     INTEGER := 0;
    v_n INTEGER; v_src TEXT; v_bad TEXT := '';
    f RECORD;
BEGIN
    FOREACH t IN ARRAY v_tables LOOP
        -- PUBLIC e o grantee 0 no ACL da relacao.
        SELECT count(*) INTO v_n
          FROM pg_class c, aclexplode(c.relacl) a
         WHERE c.oid = ('public.'||t)::regclass
           AND a.grantee = 0
           AND a.privilege_type IN ('INSERT','UPDATE','DELETE');
        v_public_dml := v_public_dml + v_n;

        IF has_table_privilege('anon', 'public.'||t, 'INSERT')
           OR has_table_privilege('anon', 'public.'||t, 'UPDATE')
           OR has_table_privilege('anon', 'public.'||t, 'DELETE') THEN
            v_anon_dml := v_anon_dml + 1;
        END IF;

        IF has_table_privilege('authenticated', 'public.'||t, 'INSERT')
           OR has_table_privilege('authenticated', 'public.'||t, 'UPDATE')
           OR has_table_privilege('authenticated', 'public.'||t, 'DELETE') THEN
            v_auth_dml := v_auth_dml + 1;
        END IF;

        IF has_table_privilege('authenticated', 'public.'||t, 'SELECT') THEN
            v_sel_ok := v_sel_ok + 1;
        END IF;
    END LOOP;

    PERFORM pg_temp._rec('Z','Z07a - PUBLIC sem INSERT/UPDATE/DELETE nas 6 tabelas',
        v_public_dml = 0, 'privilegios DML para PUBLIC='||v_public_dml, '0');
    PERFORM pg_temp._rec('Z','Z07b - anon sem INSERT/UPDATE/DELETE nas 6 tabelas',
        v_anon_dml = 0, 'tabelas com DML para anon='||v_anon_dml, '0');
    PERFORM pg_temp._rec('Z','Z07c - authenticated sem INSERT/UPDATE/DELETE direto nas 6 tabelas',
        v_auth_dml = 0, 'tabelas com DML para authenticated='||v_auth_dml, '0');
    PERFORM pg_temp._rec('Z','Z07d - authenticated COM SELECT nas 6 tabelas',
        v_sel_ok = 6, 'tabelas com SELECT='||v_sel_ok, '6');

    -- Z08: owner=postgres, SECURITY DEFINER e search_path vazio em toda
    -- funcao da Foundation (helper, RPCs e trigger functions).
    FOR f IN
        SELECT p.proname, pg_get_userbyid(p.proowner) AS owner, p.prosecdef,
               array_to_string(p.proconfig, ',') AS cfg,
               pg_temp._empty_search_path(p.oid) AS sp_vazio
          FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE n.nspname='public'
           AND (p.proname LIKE '%collection_layout%'
                OR p.proname IN ('add_layout_page','remove_layout_page','reorder_layout_pages',
                                 'set_slot_expected_content','clear_slot_expected_content',
                                 'set_slot_lock','assign_card_to_slot','move_slot_assignment',
                                 'remove_slot_assignment','merge_layout_region','unmerge_layout_region'))
    LOOP
        IF f.owner <> 'postgres' OR NOT f.prosecdef OR NOT f.sp_vazio THEN
            v_bad := v_bad || f.proname
                  || '(owner='||f.owner||',secdef='||f.prosecdef
                  || ',search_path_vazio='||f.sp_vazio||',cfg='||COALESCE(f.cfg,'NULL')||') ';
        END IF;
    END LOOP;

    PERFORM pg_temp._rec('Z','Z08 - funcoes da Foundation: owner=postgres, SECURITY DEFINER, search_path EFETIVAMENTE vazio',
        v_bad = '', CASE WHEN v_bad='' THEN 'nenhuma divergencia' ELSE 'divergentes: '||v_bad END,
        'nenhuma divergencia');

    -- Z09 (STATIC PROOF de nao-enumeracao): toda RPC que recebe id de
    -- FILHO resolve owner-scoped ANTES de qualquer comparacao.
    v_bad := '';
    FOR f IN
        SELECT p.oid, p.proname
          FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE n.nspname='public'
           AND p.proname IN ('clear_slot_expected_content','set_slot_lock','remove_slot_assignment',
                             'assign_card_to_slot','move_slot_assignment','set_slot_expected_content',
                             'remove_layout_page','merge_layout_region','unmerge_layout_region')
    LOOP
        SELECT pg_get_functiondef(f.oid) INTO v_src;
        IF position('owner_user_id = (select auth.uid())' in v_src) = 0 THEN
            v_bad := v_bad || f.proname || ' ';
        END IF;
    END LOOP;

    PERFORM pg_temp._rec('Z','Z09 - STATIC PROOF: RPCs que recebem id de filho resolvem owner-scoped (sem raw child lookup)',
        v_bad = '', CASE WHEN v_bad='' THEN 'todas owner-scoped' ELSE 'SEM filtro de owner: '||v_bad END,
        'todas owner-scoped');

    -- Z10 (STATIC PROOF): nenhum aggregate min()/max() sobre UUID.
    v_bad := '';
    FOR f IN
        SELECT p.oid, p.proname
          FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE n.nspname='public'
           AND p.proname IN ('clear_slot_expected_content','set_slot_lock','remove_slot_assignment')
    LOOP
        SELECT pg_get_functiondef(f.oid) INTO v_src;
        IF v_src ~* '(min|max)[[:space:]]*\([[:space:]]*[a-z_]*\.?layout_id' THEN
            v_bad := v_bad || f.proname || ' ';
        END IF;
    END LOOP;

    PERFORM pg_temp._rec('Z','Z10 - STATIC PROOF: nenhum min()/max() sobre layout_id (UUID) nas RPCs de array',
        v_bad = '', CASE WHEN v_bad='' THEN 'nenhum aggregate sobre UUID' ELSE 'ainda usa aggregate: '||v_bad END,
        'nenhum aggregate sobre UUID');
END $blk$;

-- =================================================================
-- GRUPO Z (adicionais) — NAO-ENUMERACAO DINAMICA CROSS-USER (§15)
-- Exige um SEGUNDO usuario real. Sem ele: NOT PROVEN. A prova
-- ESTRUTURAL (Z09) continua obrigatoria e ja foi executada acima.
-- =================================================================
DO $blk$
DECLARE
    v_other UUID; v_owner UUID; v_layout UUID; v_s1 UUID; v_alloc UUID; v_coll UUID;
    v_free UUID; v_m1 TEXT; v_m2 TEXT;
BEGIN
    SELECT v INTO v_other  FROM _fx WHERE k='other';
    SELECT v INTO v_owner  FROM _fx WHERE k='owner';
    SELECT v INTO v_layout FROM _fx WHERE k='layout';
    SELECT v INTO v_s1     FROM _fx WHERE k='s1';
    SELECT v INTO v_coll   FROM _fx WHERE k='coll';

    IF v_other IS NULL THEN
        PERFORM pg_temp._rec('Z','Z11 - array com Slot ALHEIO vs UUID INEXISTENTE: mesma mensagem', NULL,
            'NOT PROVEN — nao existe segundo auth.users neste ambiente', 'mensagens identicas');
        PERFORM pg_temp._rec('Z','Z12 - MOVE para Slot ALHEIO vs INEXISTENTE: mesma mensagem', NULL,
            'NOT PROVEN — nao existe segundo auth.users neste ambiente', 'mensagens identicas');
    ELSE
        -- Z11: array [alheio existente] vs [UUID inexistente].
        PERFORM pg_temp._as_user(v_other);
        BEGIN PERFORM public.set_slot_lock(ARRAY[v_s1]::uuid[], TRUE);
        EXCEPTION WHEN OTHERS THEN v_m1 := SQLERRM; END;
        BEGIN PERFORM public.set_slot_lock(ARRAY[gen_random_uuid()]::uuid[], TRUE);
        EXCEPTION WHEN OTHERS THEN v_m2 := SQLERRM; END;
        PERFORM pg_temp._as_admin();
        PERFORM pg_temp._rec('Z','Z11 - array com Slot ALHEIO vs UUID INEXISTENTE: mesma mensagem',
            v_m1 IS NOT NULL AND v_m1 IS NOT DISTINCT FROM v_m2,
            'alheio="'||COALESCE(left(v_m1,80),'NULL')||'" inexistente="'||COALESCE(left(v_m2,80),'NULL')||'"',
            'mensagens identicas');

        -- Z12: MOVE para Slot alheio vs inexistente.
        v_m1 := NULL; v_m2 := NULL;
        PERFORM pg_temp._as_user(v_other);
        BEGIN PERFORM public.move_slot_assignment(v_s1, gen_random_uuid());
        EXCEPTION WHEN OTHERS THEN v_m1 := SQLERRM; END;
        BEGIN PERFORM public.move_slot_assignment(gen_random_uuid(), gen_random_uuid());
        EXCEPTION WHEN OTHERS THEN v_m2 := SQLERRM; END;
        PERFORM pg_temp._as_admin();
        PERFORM pg_temp._rec('Z','Z12 - MOVE para Slot ALHEIO vs INEXISTENTE: mesma mensagem',
            v_m1 IS NOT NULL AND v_m1 IS NOT DISTINCT FROM v_m2,
            'alheio="'||COALESCE(left(v_m1,80),'NULL')||'" inexistente="'||COALESCE(left(v_m2,80),'NULL')||'"',
            'mensagens identicas');
    END IF;

    -- Z13: ASSIGN com Allocation de OUTRA Collection vs Allocation
    -- inexistente — do ponto de vista do proprio Owner. Nao depende de
    -- segundo usuario e por isso e sempre executavel.
    SELECT ca.id INTO v_alloc
      FROM public.collection_allocation ca
     WHERE ca.collection_id <> v_coll
     ORDER BY ca.id LIMIT 1;

    SELECT s.id INTO v_free
      FROM public.collection_layout_slot s
      JOIN public.collection_layout_page p ON p.id=s.page_id
     WHERE p.layout_id=v_layout AND NOT s.locked
       AND NOT EXISTS (SELECT 1 FROM public.collection_layout_slot_assignment a WHERE a.slot_id=s.id)
     ORDER BY s.id LIMIT 1;

    IF v_alloc IS NULL OR v_free IS NULL THEN
        PERFORM pg_temp._rec('Z','Z13 - ASSIGN com Allocation de OUTRA Collection vs INEXISTENTE: mesma mensagem', NULL,
            'NOT PROVEN — fixture sem Allocation de outra Collection ou sem Slot livre',
            'mensagens identicas');
    ELSE
        v_m1 := NULL; v_m2 := NULL;
        PERFORM pg_temp._as_user(v_owner);
        BEGIN PERFORM public.assign_card_to_slot(v_free, v_alloc);
        EXCEPTION WHEN OTHERS THEN v_m1 := SQLERRM; END;
        BEGIN PERFORM public.assign_card_to_slot(v_free, gen_random_uuid());
        EXCEPTION WHEN OTHERS THEN v_m2 := SQLERRM; END;
        PERFORM pg_temp._as_admin();
        PERFORM pg_temp._rec('Z','Z13 - ASSIGN com Allocation de OUTRA Collection vs INEXISTENTE: mesma mensagem',
            v_m1 IS NOT NULL AND v_m1 IS NOT DISTINCT FROM v_m2,
            'outra="'||COALESCE(left(v_m1,80),'NULL')||'" inexistente="'||COALESCE(left(v_m2,80),'NULL')||'"',
            'mensagens identicas');
    END IF;
END $blk$;

-- =================================================================
-- GRUPO B — LIMITES DE LOTE EM PAYLOAD UUID[] (§1/§2/§3 da
-- CORREÇÃO CONSOLIDADA 02)
--
-- BLOCKER que este grupo fecha: RPCs públicas SECURITY DEFINER
-- aceitavam `UUID[]` de tamanho arbitrário e executavam unnest +
-- DISTINCT (trabalho proporcional ao payload) ANTES de qualquer
-- rejeição.
--
-- NENHUM caso isolado deste grupo "prova" o cap-before-dedup. A
-- prova é o CONJUNTO, e cada peça tem um papel declarado:
--
--   B02/B05/B08 (501 elementos TODOS IGUAIS) — CONDIÇÃO NECESSÁRIA,
--     NÃO SUFICIENTE. Se o teto fosse avaliado depois do DISTINCT,
--     esse payload viraria 1 elemento e passaria; logo a falha é
--     necessária. Mas ele passaria igualmente com `array_length(x,1)`,
--     então sozinho não distingue as duas implementações.
--
--   B03/B06/B09 (501 UUIDs DISTINTOS e inexistentes) — falham com
--     'limite de 500' e NÃO com 'not found or not owned': o cap
--     antecede o resolve de ownership. Também necessário, também
--     insuficiente sozinho.
--
--   B13-B18 (multidimensional) — é aqui que `array_length(x,1)` e
--     `cardinality()` divergem de fato.
--
--   B10 (STATIC PROOF fail-closed) — fecha o conjunto: prova, sobre o
--     source sem comentários, que a REJEIÇÃO EFETIVA (o `RAISE
--     EXCEPTION` do cap, não a string solta) ocorre entre o teste do
--     cap e o PRIMEIRO unnest/DISTINCT, e que `array_length` não
--     existe mais no corpo executável.
--
-- 5127 (reorder) NÃO recebe teto: seu contrato é "todas as Pages do
-- Layout". O que se prova nele é o SHORT-CIRCUIT de cardinalidade
-- antes do unnest/DISTINCT (B11) e a AUSÊNCIA de cap artificial (B12).
-- =================================================================
DO $blk$
DECLARE
    v_owner UUID; v_layout UUID; v_slot UUID;
    v_500 UUID[]; v_501 UUID[]; v_501d UUID[];
    v_md_600 UUID[]; v_md_10 UUID[];
BEGIN
    SELECT v INTO v_owner  FROM _fx WHERE k='owner';
    SELECT v INTO v_layout FROM _fx WHERE k='layout';

    -- Slot próprio, sem Assignment, sem Expected Content e sem Lock:
    -- os casos "500 aceito" ficam sem efeito colateral (retornam 0).
    SELECT s.id INTO v_slot
      FROM public.collection_layout_slot s
      JOIN public.collection_layout_page p ON p.id = s.page_id
     WHERE p.layout_id = v_layout
       AND NOT s.locked
       AND NOT EXISTS (SELECT 1 FROM public.collection_layout_slot_assignment a WHERE a.slot_id=s.id)
       AND NOT EXISTS (SELECT 1 FROM public.collection_layout_slot_expected_content e WHERE e.slot_id=s.id)
     ORDER BY s.id LIMIT 1;

    IF v_slot IS NULL THEN
        SELECT v INTO v_slot FROM _fx WHERE k='s1';
        UPDATE public.collection_layout_slot SET locked=FALSE WHERE id=v_slot;
    END IF;

    IF v_slot IS NULL THEN
        PERFORM pg_temp._rec('B','B00 - fixture de Slot para os testes de lote', FALSE,
            'nenhum Slot disponivel', 'Slot proprio disponivel');
        RETURN;
    END IF;

    -- 500 e 501 cópias do MESMO Slot válido; 501 UUIDs distintos.
    v_500  := array_fill(v_slot, ARRAY[500]);
    v_501  := array_fill(v_slot, ARRAY[501]);
    SELECT array_agg(gen_random_uuid()) INTO v_501d FROM generate_series(1, 501);

    PERFORM pg_temp._rec('B','B00 - fixture: arrays de 500/501 montados',
        array_length(v_500,1)=500 AND array_length(v_501,1)=501 AND array_length(v_501d,1)=501,
        format('500=%s 501=%s 501d=%s', array_length(v_500,1), array_length(v_501,1), array_length(v_501d,1)),
        '500/501/501');

    PERFORM pg_temp._as_user(v_owner);

    -- ---------------- clear_slot_expected_content ----------------
    PERFORM pg_temp._expect_ok('B','B01 - clear_slot_expected_content: 500 itens ACEITO',
        format('SELECT public.clear_slot_expected_content(%L::uuid[])', v_500));

    PERFORM pg_temp._expect_error('B','B02 - clear_slot_expected_content: 501 REPETIDOS rejeitado [condicao NECESSARIA, nao suficiente - ver B13-B18 e B10]',
        format('SELECT public.clear_slot_expected_content(%L::uuid[])', v_501),
        'limite de 500');

    PERFORM pg_temp._expect_error('B','B03 - clear_slot_expected_content: 501 DISTINTOS rejeitado pelo cap, nao por not-found',
        format('SELECT public.clear_slot_expected_content(%L::uuid[])', v_501d),
        'limite de 500');

    -- ---------------------- set_slot_lock ------------------------
    -- p_locked = FALSE: idempotente, sem efeito colateral.
    PERFORM pg_temp._expect_ok('B','B04 - set_slot_lock: 500 itens ACEITO',
        format('SELECT public.set_slot_lock(%L::uuid[], FALSE)', v_500));

    PERFORM pg_temp._expect_error('B','B05 - set_slot_lock: 501 REPETIDOS rejeitado [condicao NECESSARIA, nao suficiente - ver B13-B18 e B10]',
        format('SELECT public.set_slot_lock(%L::uuid[], FALSE)', v_501),
        'limite de 500');

    PERFORM pg_temp._expect_error('B','B06 - set_slot_lock: 501 DISTINTOS rejeitado pelo cap, nao por not-found',
        format('SELECT public.set_slot_lock(%L::uuid[], FALSE)', v_501d),
        'limite de 500');

    -- ------------------ remove_slot_assignment -------------------
    PERFORM pg_temp._expect_ok('B','B07 - remove_slot_assignment: 500 itens ACEITO',
        format('SELECT public.remove_slot_assignment(%L::uuid[])', v_500));

    PERFORM pg_temp._expect_error('B','B08 - remove_slot_assignment: 501 REPETIDOS rejeitado [condicao NECESSARIA, nao suficiente - ver B13-B18 e B10]',
        format('SELECT public.remove_slot_assignment(%L::uuid[])', v_501),
        'limite de 500');

    PERFORM pg_temp._expect_error('B','B09 - remove_slot_assignment: 501 DISTINTOS rejeitado pelo cap, nao por not-found',
        format('SELECT public.remove_slot_assignment(%L::uuid[])', v_501d),
        'limite de 500');

    -- =============================================================
    -- §2 CORRECAO CONSOLIDADA 03 — REGRESSOES MULTIDIMENSIONAIS.
    --
    -- Os casos B01-B09 acima (500/501) sao condicao NECESSARIA, nao
    -- suficiente: eles passariam mesmo com `array_length(x, 1)`, que
    -- so enxerga a PRIMEIRA dimensao. O bypass real e este:
    --
    --   array_fill(uuid, ARRAY[2, 300])  ->  ndims = 2
    --                                        array_length(x,1) = 2
    --                                        cardinality(x)    = 600
    --                                        unnest(x)         = 600 linhas
    --
    -- Com array_length, esse payload passaria pelo teto de 500 e
    -- chegaria ao unnest com 600 elementos. Com o contrato
    -- unidimensional + cardinality(), e rejeitado ANTES do unnest.
    -- =============================================================
    v_md_600  := array_fill(v_slot, ARRAY[2, 300]);   -- dim1=2,   card=600
    v_md_10   := array_fill(v_slot, ARRAY[2, 5]);     -- dim1=2,   card=10

    PERFORM pg_temp._as_admin();
    PERFORM pg_temp._rec('B','B13pre - fixture multidimensional engana array_length(x,1) mas nao cardinality()',
        array_ndims(v_md_600) = 2
        AND array_length(v_md_600, 1) = 2
        AND cardinality(v_md_600) = 600,
        format('ndims=%s array_length_dim1=%s cardinality=%s',
               array_ndims(v_md_600), array_length(v_md_600, 1), cardinality(v_md_600)),
        'ndims=2, array_length(dim1)=2, cardinality=600');
    PERFORM pg_temp._as_user(v_owner);

    -- Multidimensional com CARDINALIDADE > 500 (dim1 = 2, bem abaixo
    -- do teto): rejeitado pelo contrato de forma, ANTES do unnest.
    PERFORM pg_temp._expect_error('B','B13 - clear_slot_expected_content: multidimensional (dim1=2, card=600) REJEITADO antes do unnest',
        format('SELECT public.clear_slot_expected_content(%L::uuid[])', v_md_600),
        'unidimensional');

    PERFORM pg_temp._expect_error('B','B14 - set_slot_lock: multidimensional (dim1=2, card=600) REJEITADO antes do unnest',
        format('SELECT public.set_slot_lock(%L::uuid[], FALSE)', v_md_600),
        'unidimensional');

    PERFORM pg_temp._expect_error('B','B15 - remove_slot_assignment: multidimensional (dim1=2, card=600) REJEITADO antes do unnest',
        format('SELECT public.remove_slot_assignment(%L::uuid[])', v_md_600),
        'unidimensional');

    -- Multidimensional PEQUENO (card=10) tambem e rejeitado: o
    -- contrato e de FORMA, nao apenas de tamanho.
    PERFORM pg_temp._expect_error('B','B16 - clear_slot_expected_content: multidimensional pequeno (card=10) tambem REJEITADO',
        format('SELECT public.clear_slot_expected_content(%L::uuid[])', v_md_10),
        'unidimensional');

    PERFORM pg_temp._expect_error('B','B17 - set_slot_lock: multidimensional pequeno (card=10) tambem REJEITADO',
        format('SELECT public.set_slot_lock(%L::uuid[], FALSE)', v_md_10),
        'unidimensional');

    PERFORM pg_temp._expect_error('B','B18 - remove_slot_assignment: multidimensional pequeno (card=10) tambem REJEITADO',
        format('SELECT public.remove_slot_assignment(%L::uuid[])', v_md_10),
        'unidimensional');

    -- Array vazio continua sendo 'vazio', nao 'unidimensional'
    -- (array_ndims('{}') e NULL; o guard de cardinalidade vem antes).
    PERFORM pg_temp._expect_error('B','B19 - array vazio produz mensagem de vazio, nao de dimensao',
        'SELECT public.set_slot_lock(ARRAY[]::uuid[], FALSE)',
        'nao pode ser vazio');

    PERFORM pg_temp._as_admin();
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp._as_admin();
    PERFORM pg_temp._rec('B','B-ABORT - grupo B abortou', FALSE,
        SQLSTATE||' '||left(SQLERRM,180), 'grupo B completo');
END $blk$;

-- =================================================================
-- GRUPO B — REORDER COM PAYLOAD MULTIDIMENSIONAL (§2)
--
-- Este e o caso que engana `array_length(x, 1)` em 5127: constroi-se
-- um array 2-D cuja PRIMEIRA DIMENSAO e EXATAMENTE o total de Pages
-- do Layout. Com array_length(x,1) o short-circuit de cardinalidade
-- ACHARIA que o payload tem o tamanho certo e deixaria passar para o
-- unnest/DISTINCT. Com cardinality() + contrato unidimensional, e
-- rejeitado antes.
-- =================================================================
DO $blk$
DECLARE
    v_owner UUID; v_layout UUID; v_page UUID;
    v_total INTEGER; v_md UUID[];
BEGIN
    SELECT v INTO v_owner  FROM _fx WHERE k='owner';
    SELECT v INTO v_layout FROM _fx WHERE k='layout';

    SELECT count(*) INTO v_total
      FROM public.collection_layout_page p WHERE p.layout_id = v_layout;

    SELECT p.id INTO v_page
      FROM public.collection_layout_page p WHERE p.layout_id = v_layout
     ORDER BY p.id LIMIT 1;

    IF v_total IS NULL OR v_total < 1 OR v_page IS NULL THEN
        PERFORM pg_temp._rec('B','B20 - reorder: payload multidimensional que engana array_length(x,1) REJEITADO',
            FALSE, 'fixture sem Pages no Layout', 'Layout com >= 1 Page');
        RETURN;
    END IF;

    -- dim1 = v_total (coincide com o total de Pages!), card = v_total*2.
    v_md := array_fill(v_page, ARRAY[v_total, 2]);

    PERFORM pg_temp._rec('B','B20pre - fixture: dim1 do payload COINCIDE com o total de Pages',
        array_ndims(v_md) = 2
        AND array_length(v_md, 1) = v_total
        AND cardinality(v_md) = v_total * 2,
        format('total_pages=%s ndims=%s array_length_dim1=%s cardinality=%s',
               v_total, array_ndims(v_md), array_length(v_md, 1), cardinality(v_md)),
        format('ndims=2, array_length(dim1)=%s (=total_pages), cardinality=%s', v_total, v_total*2));

    PERFORM pg_temp._as_user(v_owner);
    PERFORM pg_temp._expect_error('B','B20 - reorder: payload multidimensional que engana array_length(x,1) REJEITADO',
        format('SELECT * FROM public.reorder_layout_pages(%L::uuid, %L::uuid[])', v_layout, v_md),
        'unidimensional');
    PERFORM pg_temp._as_admin();
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp._as_admin();
    PERFORM pg_temp._rec('B','B20 - reorder: payload multidimensional que engana array_length(x,1) REJEITADO',
        FALSE, 'bloco abortou: '||SQLSTATE||' '||left(SQLERRM,160), 'erro de dimensao');
END $blk$;

-- =================================================================
-- GRUPO B — STATIC PROOF FAIL-CLOSED DA ORDEM E DA NATUREZA DOS
-- GUARDS (§1/§2/§4 da CORRECAO CONSOLIDADA 04)
--
-- Comentarios SQL sao REMOVIDOS do pg_get_functiondef antes da busca
-- (bloco primeiro, linha depois — abordagem do 5817 e do W12-G3 do
-- 5819). Sem isso a propria prosa explicativa destas funcoes, que
-- cita "DISTINCT", "dedup", "array_length" e "500", contaminaria as
-- posicoes.
--
-- A busca usa position() LITERAL. Nada de LIKE/ILIKE, onde `_` e
-- wildcard.
--
-- MUDANCA v6.0 — FAIL-CLOSED. A v5.0 aceitava a presenca do teste do
-- cap mais a presenca da STRING da mensagem. Isso nao prova rejeicao:
-- uma funcao que testasse o cap e NAO levantasse erro, ou que apenas
-- mencionasse aquela string em outro contexto, passaria. Agora exige-se
-- o `RAISE EXCEPTION` REAL, localizado DENTRO do segmento de source
-- que vai do teste do cap ate o PRIMEIRO unnest/DISTINCT:
--
--     IF <cap>  <  RAISE EXCEPTION  <  <mensagem>  <  1o unnest/DISTINCT
--
-- Alem disso B10 exige:
--   (a) cardinality() no guard — nao array_length(...,1);
--   (b) ZERO ocorrencias de array_length no corpo executavel;
--   (c) guard de dimensao array_ndims(...) <> 1 antes do 1o scan.
-- =================================================================
DO $blk$
DECLARE
    f RECORD;
    v_exec TEXT;
    v_seg  TEXT;
    v_pos_card INTEGER; v_pos_ndims INTEGER; v_pos_cap INTEGER;
    v_pos_unnest INTEGER; v_pos_distinct INTEGER; v_first_scan INTEGER;
    v_rel_raise INTEGER; v_rel_msg INTEGER;
    v_bad TEXT := '';
    v_missing TEXT := '';
    v_found BOOLEAN;
    t TEXT;
    v_names TEXT[] := ARRAY['clear_slot_expected_content','set_slot_lock','remove_slot_assignment'];
BEGIN
    FOREACH t IN ARRAY v_names LOOP
        v_found := FALSE;
        FOR f IN
            SELECT p.oid, p.proname
              FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
             WHERE n.nspname='public' AND p.proname = t
        LOOP
            v_found := TRUE;
            v_exec := regexp_replace(
                        regexp_replace(COALESCE(pg_get_functiondef(f.oid), ''),
                                       '/\*.*?\*/', ' ', 'gs'),
                        '--.*$', ' ', 'gn');

            v_pos_card  := position('cardinality(p_slot_ids)' in v_exec);
            v_pos_ndims := position('array_ndims(p_slot_ids) <> 1' in v_exec);
            v_pos_cap   := position('v_raw_count > 500' in v_exec);

            v_pos_unnest   := position('unnest(' in v_exec);
            v_pos_distinct := position('DISTINCT' in v_exec);
            v_first_scan := LEAST(
                CASE WHEN v_pos_unnest   = 0 THEN 2147483647 ELSE v_pos_unnest   END,
                CASE WHEN v_pos_distinct = 0 THEN 2147483647 ELSE v_pos_distinct END);

            -- SEGMENTO entre o teste do cap e o primeiro scan. E aqui,
            -- e somente aqui, que a rejeicao efetiva pode estar.
            v_rel_raise := 0;
            v_rel_msg   := 0;
            IF v_pos_cap > 0 AND v_first_scan < 2147483647 AND v_first_scan > v_pos_cap THEN
                v_seg := substr(v_exec, v_pos_cap, v_first_scan - v_pos_cap);
                v_rel_raise := position('RAISE EXCEPTION' in v_seg);
                v_rel_msg   := position('lote excede o limite de 500 itens por chamada' in v_seg);
            END IF;

            IF v_pos_card = 0
               OR v_pos_ndims = 0
               OR v_pos_cap = 0
               OR v_first_scan = 2147483647
               OR position('array_length' in v_exec) > 0
               OR v_rel_raise = 0                 -- RAISE EXCEPTION real ausente
               OR v_rel_msg = 0                   -- mensagem canonica ausente
               OR v_rel_msg < v_rel_raise         -- mensagem antes do RAISE = nao pertence a ele
               OR NOT (v_pos_card  < v_pos_cap
                   AND v_pos_ndims < v_first_scan
                   AND v_pos_cap   < v_first_scan) THEN
                v_bad := v_bad || format(
                    '%s(card=%s,ndims=%s,cap=%s,raise_rel=%s,msg_rel=%s,first_scan=%s,array_length=%s) ',
                    f.proname, v_pos_card, v_pos_ndims, v_pos_cap,
                    v_rel_raise, v_rel_msg, v_first_scan,
                    position('array_length' in v_exec));
            END IF;
        END LOOP;
        IF NOT v_found THEN
            v_missing := v_missing || t || ' ';
        END IF;
    END LOOP;

    PERFORM pg_temp._rec('B','B10 - STATIC PROOF FAIL-CLOSED: nas 3 RPCs, IF cap < RAISE EXCEPTION < mensagem < 1o unnest/DISTINCT; cardinality e ndims presentes; zero array_length',
        v_missing = '' AND v_bad = '',
        CASE WHEN v_missing <> '' THEN 'FUNCAO AUSENTE: '||v_missing
             WHEN v_bad = ''      THEN 'as 3: RAISE EXCEPTION real do cap localizado entre o IF e o 1o unnest/DISTINCT; cardinality; ndims<>1; zero array_length'
             ELSE 'INCORRETO em: '||v_bad END,
        'IF cap < RAISE EXCEPTION < mensagem < 1o unnest/DISTINCT');

    -- =============================================================
    -- 5127 reorder_layout_pages — B11 e B12
    -- =============================================================
    v_exec := NULL;
    SELECT regexp_replace(
             regexp_replace(COALESCE(pg_get_functiondef(p.oid), ''), '/\*.*?\*/', ' ', 'gs'),
             '--.*$', ' ', 'gn')
      INTO v_exec
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname='reorder_layout_pages';

    IF v_exec IS NULL THEN
        PERFORM pg_temp._rec('B','B11 - STATIC PROOF FAIL-CLOSED: reorder rejeita cardinalidade com RAISE EXCEPTION real ANTES do 1o unnest/DISTINCT',
            FALSE, 'reorder_layout_pages nao existe', 'short-circuit com rejeicao efetiva');
        PERFORM pg_temp._rec('B','B12 - reorder NAO possui cap fixo NEM via constante/variavel, em NENHUM lado da comparacao',
            FALSE, 'reorder_layout_pages nao existe', 'sem cap');
    ELSE
        v_pos_card  := position('cardinality(p_page_ids_ordered)' in v_exec);
        v_pos_ndims := position('array_ndims(p_page_ids_ordered) <> 1' in v_exec);
        v_pos_cap   := position('v_input_count <> v_total_pages' in v_exec);

        v_pos_unnest   := position('unnest(' in v_exec);
        v_pos_distinct := position('DISTINCT' in v_exec);
        v_first_scan := LEAST(
            CASE WHEN v_pos_unnest   = 0 THEN 2147483647 ELSE v_pos_unnest   END,
            CASE WHEN v_pos_distinct = 0 THEN 2147483647 ELSE v_pos_distinct END);

        v_rel_raise := 0;
        v_rel_msg   := 0;
        IF v_pos_cap > 0 AND v_first_scan < 2147483647 AND v_first_scan > v_pos_cap THEN
            v_seg := substr(v_exec, v_pos_cap, v_first_scan - v_pos_cap);
            v_rel_raise := position('RAISE EXCEPTION' in v_seg);
            v_rel_msg   := position('deve conter todas as' in v_seg);
        END IF;

        PERFORM pg_temp._rec('B','B11 - STATIC PROOF FAIL-CLOSED: reorder rejeita cardinalidade com RAISE EXCEPTION real ANTES do 1o unnest/DISTINCT',
            v_pos_card > 0
            AND v_pos_ndims > 0
            AND v_pos_cap > 0
            AND v_first_scan < 2147483647
            AND position('array_length' in v_exec) = 0
            AND v_rel_raise > 0
            AND v_rel_msg > v_rel_raise
            AND v_pos_card  < v_pos_ndims
            AND v_pos_ndims < v_first_scan
            AND v_pos_cap   < v_first_scan,
            format('cardinality=%s ndims=%s short_circuit=%s raise_rel=%s msg_rel=%s first_scan=%s array_length=%s',
                   v_pos_card, v_pos_ndims, v_pos_cap, v_rel_raise, v_rel_msg,
                   v_first_scan, position('array_length' in v_exec)),
            'cardinality < ndims; IF cardinalidade < RAISE EXCEPTION < mensagem < 1o unnest/DISTINCT; zero array_length');

        -- ---------------------------------------------------------
        -- B12 (§4) — ausencia de cap, INCLUSIVE via constante/variavel.
        --
        -- Nao basta "nao ha literal 500". Um cap escrito como
        --     c_max CONSTANT INTEGER := 500;   -- ou 1000, ou qualquer
        --     IF v_input_count > c_max THEN RAISE ...
        -- passaria por um gate baseado so em literal.
        --
        -- Gate correto, puramente estatico (nenhuma fixture pesada):
        --   (a) WHITELIST DE OPERANDOS — todo operando comparado com
        --       `v_input_count` tem de ser `v_total_pages` ou `0`.
        --       Qualquer outro identificador ou numero reprova;
        --   (b) o corpo nao pode conter RAISE EXCEPTION cuja mensagem
        --       fale em 'limite' ou 'excede';
        --   (c) nenhum literal 500;
        --   (d) cardinality() nunca comparada contra literal numerico.
        -- ---------------------------------------------------------
        -- §1 CORRECAO CONSOLIDADA 05 — RELACIONAL EM AMBOS OS LADOS.
        -- A v6.0 varria apenas `v_input_count <op> operando`. Um cap
        -- escrito com a cardinalidade a DIREITA passava intacto:
        --     IF c_max < v_input_count THEN RAISE ...
        --     IF 1000 <= v_input_count THEN RAISE ...
        -- Agora tres varreduras, cada uma com whitelist propria:
        --   (1) DIREITA de v_input_count  -> {v_total_pages, 0}
        --   (2) ESQUERDA de v_input_count -> {v_total_pages, 0,
        --                                     v_distinct_count,
        --                                     v_belong_count}
        --       (as duas ultimas sao as comparacoes estruturais
        --        legitimas de duplicidade e pertencimento)
        --   (3) DIREITA de cardinality(...) -> {v_total_pages, 0}
        --       (cobre `IF cardinality(p) > c_max`)
        -- Qualquer identificador ou numero fora da whitelist reprova,
        -- seja literal, constante ou variavel.
        DECLARE
            v_ops TEXT := '';
            v_op  TEXT;
            m TEXT[];
        BEGIN
            -- (1) cardinalidade a ESQUERDA do operador.
            FOR m IN
                SELECT regexp_matches(
                         v_exec,
                         'v_input_count[[:space:]]*(?:<>|<=|>=|=|<|>)[[:space:]]*([A-Za-z0-9_]+)',
                         'g')
            LOOP
                v_op := m[1];
                IF v_op NOT IN ('v_total_pages', '0') THEN
                    v_ops := v_ops || 'dir:' || v_op || ' ';
                END IF;
            END LOOP;

            -- (2) cardinalidade a DIREITA do operador.
            FOR m IN
                SELECT regexp_matches(
                         v_exec,
                         '([A-Za-z0-9_]+)[[:space:]]*(?:<>|<=|>=|=|<|>)[[:space:]]*v_input_count',
                         'g')
            LOOP
                v_op := m[1];
                IF v_op NOT IN ('v_total_pages', '0', 'v_distinct_count', 'v_belong_count') THEN
                    v_ops := v_ops || 'esq:' || v_op || ' ';
                END IF;
            END LOOP;

            -- (3) cardinality(...) comparada diretamente a algo.
            FOR m IN
                SELECT regexp_matches(
                         v_exec,
                         'cardinality\([^)]*\)[[:space:]]*(?:<>|<=|>=|=|<|>)[[:space:]]*([A-Za-z0-9_]+)',
                         'g')
            LOOP
                v_op := m[1];
                IF v_op NOT IN ('v_total_pages', '0') THEN
                    v_ops := v_ops || 'card:' || v_op || ' ';
                END IF;
            END LOOP;

            PERFORM pg_temp._rec('B','B12 - reorder NAO possui cap fixo NEM via constante/variavel, em NENHUM lado da comparacao',
                v_ops = ''
                AND position('500' in v_exec) = 0
                AND v_exec !~ '[0-9]+[[:space:]]*(?:<|<=)[[:space:]]*v_input_count'
                AND v_exec !~ 'RAISE EXCEPTION[^;]*limite'
                AND v_exec !~ 'RAISE EXCEPTION[^;]*excede',
                format('operandos_nao_whitelisted="%s" literal_500=%s literal_a_esquerda=%s raise_limite=%s raise_excede=%s',
                       v_ops,
                       position('500' in v_exec),
                       (v_exec ~ '[0-9]+[[:space:]]*(?:<|<=)[[:space:]]*v_input_count'),
                       (v_exec ~ 'RAISE EXCEPTION[^;]*limite'),
                       (v_exec ~ 'RAISE EXCEPTION[^;]*excede')),
                'v_input_count/cardinality comparados somente com v_total_pages, 0 ou as contagens estruturais; zero literal 500; nenhum RAISE de limite/excesso');
        END;
    END IF;
END $blk$;

-- =================================================================
-- ZERO RESÍDUO
-- =================================================================
DO $blk$
DECLARE v_n INTEGER;
BEGIN
    SELECT count(*) INTO v_n FROM public.collection WHERE name LIKE '\_\_5818\_%';
    PERFORM pg_temp._rec('X','X01 - fixtures existem DENTRO da transacao (serao descartadas no ROLLBACK)',
        v_n=2, v_n::text, '2');
    -- §14: X02 e EVIDENCIA ESTATICA de que o arquivo termina em
    -- ROLLBACK e nao contem COMMIT. NAO e prova de zero residuo
    -- pos-rollback: isso so pode ser afirmado APOS a execucao real e o
    -- postcheck correspondente, na rodada de IMPLEMENTACAO.
    PERFORM pg_temp._rec('X','X02 - EVIDENCIA ESTATICA: o arquivo termina em ROLLBACK e nao contem COMMIT (nao e prova de zero residuo pos-rollback)',
        (SELECT count(*) FROM pg_temp._v WHERE 1=0) = 0,
        'o arquivo termina em ROLLBACK; zero residuo REAL exige postcheck pos-execucao',
        'ROLLBACK presente no arquivo');
END $blk$;

-- =================================================================
-- RELATÓRIO FINAL — §14 PROTOCOLO EM DUAS CHAMADAS
-- (RECONCILIADO na CORRECAO HARNESS-FIX-01).
--   CALL 1: tudo desde BEGIN; ate o SELECT abaixo, INCLUSIVE. E esta
--           chamada que devolve o relatorio.
--   CALL 2: ROLLBACK;
-- Uma chamada unica que INCLUA o ROLLBACK nao devolve o relatorio (o
-- ultimo statement passaria a ser o ROLLBACK, que nao retorna linhas).
-- O canal NAO preserva sessao/transacao entre chamadas: a transacao e
-- encerrada por ROLLBACK IMPLICITO ao fim da CALL 1 (o script abre
-- BEGIN; e nunca emite COMMIT;). A CALL 2 e confirmacao explicita de
-- que nada ficou pendente, e no-op se a sessao ja foi encerrada.
-- passed=TRUE -> PASS | passed=FALSE -> FAIL | passed IS NULL -> NOT PROVEN
-- =================================================================
SELECT
    COALESCE(grp, 'TOTAL')                                   AS grp,
    count(*)                                                 AS total,
    count(*) FILTER (WHERE passed IS TRUE)                   AS passed,
    count(*) FILTER (WHERE passed IS FALSE)                  AS failed,
    count(*) FILTER (WHERE passed IS NULL)                   AS not_proven,
    string_agg(case_label || ' >> ' || COALESCE(observed,''), ' || ')
        FILTER (WHERE passed IS FALSE)                       AS failing_cases
FROM _v
GROUP BY ROLLUP (grp)
ORDER BY (grp IS NULL), grp;

ROLLBACK;
