/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2828 - Validate SIZE_OUT_OF_SCOPE Decision Immutability
Versão......: 2.0
Status......: CONFIRMADO EXECUTADO — gate_state = COMPLETE (2026-09-16)
              Fechamento documental: DOCUMENTATION-CLOSEOUT-01 (2026-09-16).
              structural_pass 18 / structural_fail 0
              authenticated_e2e_pass 5 / pending 0 / fail 0
              Seção 1 executada em SIZE-SCOPE-DECISION-GUARD-2828-STRUCTURAL-GATE-01
              (18/0, gate PENDING AUTHENTICATED E2E, S1.15 ainda VÁCUO).
              B1–B5 executados em sessão administrativa REAL no navegador
              (SIZE-SCOPE-DECISION-GUARD-E2E-* ) e promovidos por _e2e2828()
              em SIZE-SCOPE-DECISION-GUARD-2828-E2E-COMPLETE-01 — nenhuma RPC
              foi chamada pelo harness; a promoção registra evidência externa.
              S1.15 teve prova NÃO-VÁCUA (linhas_marcadas >= 1, divergentes = 0)
              primeiro com a fixture E2E e depois com a população produtiva do
              rerun real de BASE1.
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-16
Mandato.....: CARD-VARIANTS — JUMBO INCIDENT /
               SIZE-SCOPE-DECISION-GUARD-HARNESS-CORRECTION-01
Diagnóstico.: SIZE-SCOPE-DECISION-GUARD-GATE-AUDIT-01 —
               FINDINGS 2828-A / 2828-B / 2828-C / 2828-D
Valida......: Query 2199 - Guard SIZE_OUT_OF_SCOPE Decision Immutability

*** A fixture E2E usada por B1–B5 foi REMOVIDA com zero resíduo em ***
*** SIZE-SCOPE-DECISION-GUARD-E2E-CLEANUP-01 (2 rows + 1 job).      ***

-------------------------------------------------------------------------------
REVISION HISTORY
-------------------------------------------------------------------------------
| 1.0 | **Primeira versao (2026-09-16).** Secao 1 estrutural + B1-B5 como
|       placeholders de uma linha.
| 2.0 | **Correcao dos tres defeitos da auditoria de gate (2026-09-16).**
|       A) S1.13 reescrita: `COALESCE(proacl,'')` fazia a assercao PASSAR
|          exatamente no caso perigoso (proacl NULL => default concede
|          EXECUTE a PUBLIC), e o primeiro disjunto do OR era codigo morto.
|          Agora usa aclexplode(COALESCE(proacl, acldefault('f', proowner)))
|          e prova PUBLIC/anon/authenticated/outros separadamente.
|       B) Gate passou a emitir uma LINHA legivel por maquina
|          (gate_state + 5 contadores). RAISE NOTICE deixou de ser a unica
|          evidencia; o harness nao pode mais terminar silenciosamente verde
|          com B1-B5 por executar.
|       C) B1-B5 passaram a carregar, no proprio arquivo, a especificacao
|          operacional completa: fixture, chamada, estado inicial, resultado
|          esperado, writes possiveis, postcheck, cleanup e STOP condition.
|          Corrigida tambem a contagem da fixture: sao 3 REGISTROS
|          (1 job + 2 rows), nao "2 INSERTs".
|       D) S1.15 rotulada como BASELINE INTEGRITY CHECK / VACUOUS BEFORE
|          EDGE RERUN — hoje ela e verdadeira por vacuidade.

-------------------------------------------------------------------------------
O QUE ESTE HARNESS PROVA — E O QUE ELE HONESTAMENTE NÃO PROVA
-------------------------------------------------------------------------------
`admin_decide_catalog_variant_import_row` é SECURITY DEFINER com GUARD 1 =
`public.is_admin()`. Sob `execute_sql` do MCP Supabase, `auth.uid()` é NULL e
`public.is_admin()` devolve FALSE — a função é INALCANÇÁVEL por esse caminho.
Mesmo limite já enfrentado na Query 2827 (casos E_CONTRATO e F1_CONTRATO), e
a lição de lá vale inteira: um teste que "passa" porque bateu no guard de
autorização NÃO testou a regra de negócio.

  SEÇÃO 1 — ESTRUTURAL. Executável por `execute_sql`. 18 asserções.
  SEÇÃO 2 — COMPORTAMENTAL. Exige SESSÃO ADMINISTRATIVA REAL. 5 casos,
            registrados como PENDING enquanto não executados.

É PROIBIDO satisfazer a Seção 2 fabricando autenticação: nada de JWT forjado,
`request.jwt.claims`, `SET ROLE`, `service_role` manual, admin temporário ou
bypass de RLS.

Padrão de execução da casa (idêntico ao da 2827): sem BEGIN/COMMIT/ROLLBACK no
topo (execute_sql já envolve); veredictos em TEMP; gate final explícito.
================================================================
*/

-- ===========================================================================
-- SEÇÃO 0 — INFRAESTRUTURA DE VEREDICTO
--
-- `estado` é uma coluna de primeira classe (não mais um booleano + convenção
-- na string de detalhe): PASS / FAIL / PENDING. É o que torna o gate final
-- legível por máquina sem heurística de texto.
-- ===========================================================================

DROP TABLE IF EXISTS _r2828;
CREATE TEMP TABLE _r2828 (
    secao    TEXT NOT NULL CHECK (secao IN ('STRUCTURAL', 'E2E')),
    caso     TEXT NOT NULL,
    estado   TEXT NOT NULL CHECK (estado IN ('PASS', 'FAIL', 'PENDING')),
    detalhe  TEXT NOT NULL DEFAULT ''
);

/** Registra um caso ESTRUTURAL: PASS quando p_ok, FAIL caso contrário. */
CREATE OR REPLACE FUNCTION pg_temp._chk2828(p_caso TEXT, p_ok BOOLEAN, p_detalhe TEXT DEFAULT '')
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO _r2828 (secao, caso, estado, detalhe)
    VALUES ('STRUCTURAL', p_caso,
            CASE WHEN COALESCE(p_ok, FALSE) THEN 'PASS' ELSE 'FAIL' END,
            COALESCE(p_detalhe, ''));
END;
$$;

/** Registra um caso E2E ainda NÃO executado. Nunca é PASS por omissão. */
CREATE OR REPLACE FUNCTION pg_temp._pend2828(p_caso TEXT, p_detalhe TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO _r2828 (secao, caso, estado, detalhe)
    VALUES ('E2E', p_caso, 'PENDING', COALESCE(p_detalhe, ''));
END;
$$;

/**
 * Promove um caso E2E a PASS/FAIL. Chamada MANUALMENTE pelo operador que
 * executou B1-B5 na sessão administrativa real, colando a evidência
 * (SQLSTATE + mensagem + postcheck) em p_evidencia.
 *
 * Existe para que a transição PENDING -> COMPLETE seja um ATO REGISTRADO,
 * com evidência anexada, e não um efeito colateral de rodar o arquivo.
 */
CREATE OR REPLACE FUNCTION pg_temp._e2e2828(p_caso TEXT, p_ok BOOLEAN, p_evidencia TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    UPDATE _r2828
       SET estado = CASE WHEN COALESCE(p_ok, FALSE) THEN 'PASS' ELSE 'FAIL' END,
           detalhe = COALESCE(p_evidencia, '')
     WHERE secao = 'E2E' AND caso = p_caso;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'HARNESS_2828_CASO_E2E_DESCONHECIDO: %', p_caso;
    END IF;
END;
$$;

-- ===========================================================================
-- SEÇÃO 1 — ESTRUTURAL (executável por execute_sql, read-only)
-- ===========================================================================

DO $sec1$
DECLARE
    v_def TEXT;
    v_i_approved INTEGER;
    v_i_scope    INTEGER;
    v_i_update   INTEGER;
BEGIN
    SELECT pg_get_functiondef(p.oid)
      INTO v_def
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'admin_decide_catalog_variant_import_row'
       AND p.pronargs = 2;

    PERFORM pg_temp._chk2828('S1.1 funcao existe', v_def IS NOT NULL);

    PERFORM pg_temp._chk2828(
        'S1.2 GUARD 7 presente no corpo LIVE',
        v_def ILIKE '%ADMIN_DECIDE_CATALOG_VARIANT_IMPORT_ROW_SIZE_OUT_OF_SCOPE%');

    PERFORM pg_temp._chk2828(
        'S1.3 guard le normalized_data->>skip_reason',
        v_def ILIKE '%normalized_data ->> ''skip_reason''%'
        AND v_def ILIKE '%SIZE_OUT_OF_SCOPE%');

    PERFORM pg_temp._chk2828(
        'S1.4 guard so dispara para decisao <> SKIPPED (idempotencia preservada)',
        v_def ILIKE '%v_decision_status <> ''SKIPPED''%');

    -- Ordem: APPROVED-needs-review < SIZE_OUT_OF_SCOPE < UPDATE.
    v_i_approved := position('ADMIN_DECIDE_CATALOG_VARIANT_IMPORT_ROW_NEEDS_REVIEW' in v_def);
    v_i_scope    := position('ADMIN_DECIDE_CATALOG_VARIANT_IMPORT_ROW_SIZE_OUT_OF_SCOPE' in v_def);
    v_i_update   := position('UPDATE public.catalog_variant_import_row' in v_def);

    PERFORM pg_temp._chk2828(
        'S1.5 GUARD 7 vem ANTES do UPDATE',
        v_i_scope > 0 AND v_i_update > 0 AND v_i_scope < v_i_update,
        format('scope=%s update=%s', v_i_scope, v_i_update));

    PERFORM pg_temp._chk2828(
        'S1.6 GUARD 7 vem DEPOIS do guard de APPROVED (precedencia de mensagem preservada)',
        v_i_approved > 0 AND v_i_scope > v_i_approved,
        format('approved=%s scope=%s', v_i_approved, v_i_scope));

    -- Guards preexistentes intactos (regressao).
    PERFORM pg_temp._chk2828('S1.7 GUARD 1 is_admin intacto', v_def ILIKE '%public.is_admin()%');
    PERFORM pg_temp._chk2828('S1.8 GUARD 3 array_ndims intacto', v_def ILIKE '%array_ndims(p_row_ids)%');
    PERFORM pg_temp._chk2828('S1.9 GUARD 5 teto 10000 intacto', v_def ILIKE '%c_max_row_ids CONSTANT INTEGER := 10000%');
    PERFORM pg_temp._chk2828('S1.10 GUARD job STAGED intacto', v_def ILIKE '%JOB_NOT_STAGED%');
END;
$sec1$;

-- ---------------------------------------------------------------------------
-- S1.11 a S1.14 — SEGURANÇA E PRIVILÉGIO
--
-- FINDING 2828-A (corrigido aqui). A versao 1.0 fazia:
--
--     COALESCE(array_to_string(p.proacl, ','), '')   -- ACL NULL vira ''
--     ... v_acl NOT ILIKE '%=X/%' OR (...)           -- primeiro disjunto morto
--
-- Dois defeitos: (1) `proacl IS NULL` significa "sem ACL explicita", e o
-- DEFAULT do PostgreSQL para funcoes e `EXECUTE TO PUBLIC` — exatamente o
-- caso perigoso; com o COALESCE para '', a assercao PASSAVA. (2) qualquer
-- funcao com grant explicito contem '=X/', entao o primeiro operando do OR
-- era sempre falso e a assercao se reduzia ao segundo.
--
-- Agora: a ACL efetiva e `COALESCE(proacl, acldefault('f', proowner))`, o que
-- torna o caso NULL indistinguivel do caso "PUBLIC tem EXECUTE" — e portanto
-- FALHA, como deve. `aclexplode` da a lista real de (grantee, privilegio),
-- e cada afirmacao e provada isoladamente, sem OR permissivo.
-- ---------------------------------------------------------------------------
DO $sec1b$
DECLARE
    v_owner      OID;
    v_acl_raw    ACLITEM[];
    v_acl_eff    ACLITEM[];
    v_secdef     BOOLEAN;
    v_cfg        TEXT[];
    v_public     BOOLEAN;
    v_anon       BOOLEAN;
    v_auth       BOOLEAN;
    v_extras     TEXT;
BEGIN
    SELECT p.proowner, p.proacl, p.prosecdef, p.proconfig
      INTO v_owner, v_acl_raw, v_secdef, v_cfg
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'admin_decide_catalog_variant_import_row'
       AND p.pronargs = 2;

    v_acl_eff := COALESCE(v_acl_raw, acldefault('f'::"char", v_owner));

    PERFORM pg_temp._chk2828('S1.11 SECURITY DEFINER preservado', v_secdef IS TRUE);

    PERFORM pg_temp._chk2828(
        'S1.12 search_path="" preservado',
        v_cfg IS NOT NULL AND EXISTS (SELECT 1 FROM unnest(v_cfg) c WHERE c = 'search_path=""'),
        COALESCE(array_to_string(v_cfg, ','), '<NULL>'));

    SELECT EXISTS (
        SELECT 1 FROM aclexplode(v_acl_eff) a
         WHERE a.privilege_type = 'EXECUTE' AND a.grantee = 0
    ) INTO v_public;

    SELECT EXISTS (
        SELECT 1 FROM aclexplode(v_acl_eff) a
         WHERE a.privilege_type = 'EXECUTE'
           AND a.grantee = to_regrole('anon')::OID
    ) INTO v_anon;

    SELECT EXISTS (
        SELECT 1 FROM aclexplode(v_acl_eff) a
         WHERE a.privilege_type = 'EXECUTE'
           AND a.grantee = to_regrole('authenticated')::OID
    ) INTO v_auth;

    -- Qualquer grantee com EXECUTE que NAO seja o owner nem authenticated.
    -- O owner NAO e ampliacao indevida: e o default de toda funcao e nao
    -- concede nada a mais do que quem ja pode substituir a propria funcao.
    SELECT COALESCE(string_agg(DISTINCT g, ', '), '')
      INTO v_extras
      FROM (
        SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC'
                    ELSE COALESCE(a.grantee::regrole::TEXT, a.grantee::TEXT) END AS g
          FROM aclexplode(v_acl_eff) a
         WHERE a.privilege_type = 'EXECUTE'
           AND a.grantee <> v_owner
           AND a.grantee IS DISTINCT FROM to_regrole('authenticated')::OID
      ) s;

    PERFORM pg_temp._chk2828(
        'S1.13a PUBLIC NAO possui EXECUTE (ACL NULL falha aqui, por acldefault)',
        v_public IS FALSE,
        format('public_execute=%s acl_explicita=%s', v_public, v_acl_raw IS NOT NULL));

    PERFORM pg_temp._chk2828(
        'S1.13b anon NAO possui EXECUTE',
        v_anon IS FALSE,
        format('anon_execute=%s anon_existe=%s', v_anon, to_regrole('anon') IS NOT NULL));

    PERFORM pg_temp._chk2828(
        'S1.13c nenhum grantee alem de owner e authenticated',
        v_extras = '',
        format('extras=[%s]', v_extras));

    PERFORM pg_temp._chk2828(
        'S1.13d ACL e EXPLICITA (proacl NOT NULL) — REVOKE/GRANT da 2199 aplicados',
        v_acl_raw IS NOT NULL,
        COALESCE(array_to_string(v_acl_raw::TEXT[], ','), '<NULL>'));

    -- Prova POSITIVA, mantida: nao basta "ninguem indevido tem"; o caller
    -- legitimo precisa continuar podendo chamar.
    PERFORM pg_temp._chk2828(
        'S1.14 authenticated POSSUI EXECUTE (prova positiva)',
        v_auth IS TRUE,
        format('authenticated_execute=%s', v_auth));
END;
$sec1b$;

-- ---------------------------------------------------------------------------
-- S1.15 — BASELINE INTEGRITY CHECK / VACUOUS BEFORE EDGE RERUN
--
-- FINDING 2828-D. Este caso NAO prova a eficacia do guard. Ele afirma que o
-- ACERVO nao contem linha fora de escopo com decisao diferente de SKIPPED.
--
-- HOJE ele e verdadeiro POR VACUIDADE: a Edge com o gate de `size` ainda nao
-- foi deployada, entao NENHUMA linha LIVE tem `skip_reason`, e a contagem e
-- trivialmente zero. Nao interpretar como evidencia de que o guard funciona.
--
-- REEXECUTAR OBRIGATORIAMENTE depois do rerun de BASE1 com a Edge nova: so
-- entao existira populacao com SIZE_OUT_OF_SCOPE e a afirmacao passara a ter
-- poder de prova. O detalhe carrega a contagem de linhas marcadas justamente
-- para tornar a vacuidade visivel em vez de escondida.
-- ---------------------------------------------------------------------------
DO $sec1c$
DECLARE
    v_marcadas INTEGER;
    v_bad      INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_marcadas
      FROM public.catalog_variant_import_row r
     WHERE r.normalized_data ->> 'skip_reason' = 'SIZE_OUT_OF_SCOPE';

    SELECT COUNT(*) INTO v_bad
      FROM public.catalog_variant_import_row r
     WHERE r.normalized_data ->> 'skip_reason' = 'SIZE_OUT_OF_SCOPE'
       AND r.decision_status <> 'SKIPPED';

    PERFORM pg_temp._chk2828(
        'S1.15 BASELINE INTEGRITY CHECK (VACUOUS BEFORE EDGE RERUN)',
        v_bad = 0,
        format('linhas_marcadas=%s divergentes=%s%s',
               v_marcadas, v_bad,
               CASE WHEN v_marcadas = 0
                    THEN ' — VACUO: nenhuma linha SIZE_OUT_OF_SCOPE no acervo; reexecutar apos rerun BASE1'
                    ELSE '' END));
END;
$sec1c$;

-- ===========================================================================
-- SEÇÃO 2 — COMPORTAMENTAL: EXIGE SESSÃO ADMINISTRATIVA REAL
-- ===========================================================================
--
-- FIXTURE ÚNICA, COMPARTILHADA PELOS CINCO CASOS
-- ---------------------------------------------------------------------------
-- CONTAGEM EXATA (FINDING 2828-C — a v1.0 dizia "2 INSERTs", o que estava
-- errado e tornava a autorização ambígua):
--
--     REGISTROS INSERIDOS ....: 3
--         1 x catalog_variant_import_job
--         1 x catalog_variant_import_row  (JUMBO)
--         1 x catalog_variant_import_row  (COMUM)
--
--     COMANDOS SQL ...........: 2
--         INSERT #1 -> catalog_variant_import_job          (1 linha afetada)
--         INSERT #2 -> catalog_variant_import_row, 2 VALUES (2 linhas afetadas)
--
-- A autorização nominal do usuário deve cobrir 3 REGISTROS em 2 COMANDOS.
-- Não confundir os dois números.
--
-- JOB
--   status ............: 'STAGED'      (obrigatório: GUARD job STAGED)
--   source ............: 'TCGDEX'
--   card_set_id .......: Card Set real
--   external_set_id ...: a referência ATIVA canônica desse Card Set
--                        (card_set_external_reference.is_active = TRUE).
--                        Inventar um valor reproduz o defeito D1 do 2827
--                        (VARIANT_IMPORT_SCOPE_MISMATCH).
--
-- ROW "JUMBO" (a que o guard deve proteger)
--   raw_data ..........: {"type":"normal","foil":null,"subtype":null,
--                         "stamp":null,"size":"jumbo"}
--   normalized_data ...: {"size":"JUMBO","skip_reason":"SIZE_OUT_OF_SCOPE"}
--   validation_status .: 'INVALID'
--   decision_status ...: 'SKIPPED'
--   persistence_status : 'PENDING'   (default da tabela)
--
-- ROW "COMUM" (só usada por B5, para provar atomicidade do lote misto)
--   raw_data ..........: {"type":"normal","foil":null,"subtype":null,
--                         "stamp":null,"size":null}
--   normalized_data ...: {}
--   validation_status .: 'NEEDS_REVIEW'
--   decision_status ...: 'PENDING'
--
-- AUTENTICAÇÃO (todos os cinco)
--   Sessão administrativa REAL no navegador, via `window.__mmkyuRpc`.
--   Identidade confirmada por `public.is_admin()` (sem argumentos) = TRUE.
--   PROIBIDO: JWT fabricado, request.jwt.claims, SET ROLE, service_role
--   manual, admin temporário, bypass de RLS, expor access token no console.
--   Se o helper tiver sido perdido por refresh ou o token expirado: STOP.
--
-- CLEANUP (após os cinco casos, nesta ordem)
--   COMANDO #1: DELETE FROM public.catalog_variant_import_row
--                WHERE job_id = <job da fixture>;      -> DEVE afetar 2 linhas
--   COMANDO #2: DELETE FROM public.catalog_variant_import_job
--                WHERE id = <job da fixture>;          -> DEVE afetar 1 linha
--   Se qualquer comando afetar número diferente do declarado: STOP.
--   A ordem importa: a FK row -> job impede remover o job antes das rows.
--
-- POSTCHECK DE BASELINE (obrigatório, após o cleanup)
--   COUNT(*) de catalog_variant_import_row  == valor pré-fixture
--   COUNT(*) de catalog_variant_import_job  == valor pré-fixture
--   Divergência de qualquer um dos dois: STOP, há resíduo.
--
-- ---------------------------------------------------------------------------
-- B1 — APPROVED sobre linha JUMBO
-- ---------------------------------------------------------------------------
--   CHAMADA ..........: admin_decide_catalog_variant_import_row(
--                         p_row_ids := ARRAY[<row JUMBO>]::UUID[],
--                         p_decision_status := 'APPROVED')
--   ESTADO INICIAL ...: JUMBO = INVALID / SKIPPED
--   ESPERADO .........: FALHA. SQLSTATE P0001.
--                       Mensagem: ..._NEEDS_REVIEW
--   WRITES POSSÍVEIS .: NENHUM (a exceção precede o UPDATE)
--   POSTCHECK ........: decision_status do JUMBO ainda = 'SKIPPED'
--   STOP CONDITION ...: qualquer alteração na linha; SQLSTATE != P0001.
--
--   *** REGISTRO EXPLÍCITO DE ESCOPO DE PROVA ***
--   B1 prova a INVARIANTE FINAL (APPROVED nunca alcança o UPDATE), NÃO a
--   execução específica do GUARD 7. O GUARD 6c (`validation_status <>
--   'VALID'`) tem PRECEDÊNCIA e é ele quem dispara, porque a linha JUMBO
--   canônica é INVALID. Isso é aceitável e foi auditado: a invariante se
--   mantém, e REJECTED/PENDING — que o GUARD 6c NÃO cobre — são protegidos
--   especificamente por B2/B3. Não relatar B1 como "GUARD 7 funcionou".
--
-- ---------------------------------------------------------------------------
-- B2 — REJECTED sobre linha JUMBO   (prova direta do GUARD 7)
-- ---------------------------------------------------------------------------
--   CHAMADA ..........: mesma, p_decision_status := 'REJECTED'
--   ESTADO INICIAL ...: JUMBO = INVALID / SKIPPED
--   ESPERADO .........: FALHA. SQLSTATE P0001.
--                       Mensagem: ..._SIZE_OUT_OF_SCOPE
--                       contendo "1 linha(s)" e a palavra REJECTED.
--   WRITES POSSÍVEIS .: NENHUM
--   POSTCHECK ........: decision_status ainda = 'SKIPPED'
--   STOP CONDITION ...: mensagem diferente de ..._SIZE_OUT_OF_SCOPE
--                       (indicaria que outro guard interceptou e que o
--                       GUARD 7 continua sem prova); ou linha alterada.
--
-- ---------------------------------------------------------------------------
-- B3 — PENDING sobre linha JUMBO    (prova direta do GUARD 7)
-- ---------------------------------------------------------------------------
--   CHAMADA ..........: mesma, p_decision_status := 'PENDING'
--   ESTADO INICIAL ...: JUMBO = INVALID / SKIPPED
--   ESPERADO .........: FALHA. SQLSTATE P0001.
--                       Mensagem: ..._SIZE_OUT_OF_SCOPE com a palavra PENDING.
--   WRITES POSSÍVEIS .: NENHUM
--   POSTCHECK ........: decision_status ainda = 'SKIPPED'
--   STOP CONDITION ...: idem B2. Reverter para PENDING é o caminho que
--                       devolveria a linha à fila editorial — se passar,
--                       a invariante está aberta.
--
-- ---------------------------------------------------------------------------
-- B4 — SKIPPED sobre linha JUMBO    (idempotência preservada)
-- ---------------------------------------------------------------------------
--   CHAMADA ..........: mesma, p_decision_status := 'SKIPPED'
--   ESTADO INICIAL ...: JUMBO = INVALID / SKIPPED
--   ESPERADO .........: SUCESSO. Retorno = 1 (ROW_COUNT do UPDATE).
--   WRITES POSSÍVEIS .: 1 UPDATE semanticamente no-op — grava
--                       decision_status = 'SKIPPED' sobre 'SKIPPED'.
--   POSTCHECK ........: decision_status = 'SKIPPED'.
--                       AUDITAR `updated_at`: se a tabela tiver trigger de
--                       touch, o campo MUDA. Isso NÃO é violação, desde que
--                       seja o ÚNICO efeito. Registrar o valor antes/depois.
--   STOP CONDITION ...: retorno != 1; qualquer coluna de negócio alterada
--                       além de updated_at; erro de qualquer natureza.
--
-- ---------------------------------------------------------------------------
-- B5 — Lote MISTO [JUMBO, COMUM] com REJECTED   (atomicidade)
-- ---------------------------------------------------------------------------
--   CHAMADA ..........: p_row_ids := ARRAY[<JUMBO>, <COMUM>]::UUID[],
--                       p_decision_status := 'REJECTED'
--   ESTADO INICIAL ...: JUMBO = INVALID / SKIPPED
--                       COMUM = NEEDS_REVIEW / PENDING
--   ESPERADO .........: FALHA. SQLSTATE P0001, ..._SIZE_OUT_OF_SCOPE.
--   WRITES POSSÍVEIS .: NENHUM
--   POSTCHECK ........: AS DUAS linhas intactas —
--                       JUMBO.decision_status = 'SKIPPED'
--                       COMUM.decision_status = 'PENDING'
--   STOP CONDITION ...: a linha COMUM ter virado REJECTED. Isso significaria
--                       UPDATE PARCIAL, que é a falha mais grave possível
--                       aqui: o lote teria aplicado metade das decisões em
--                       silêncio. Se acontecer, STOP imediato e não seguir
--                       para deploy nem para rerun BASE1.
-- ===========================================================================

SELECT pg_temp._pend2828('B1 APPROVED em OUT_OF_SCOPE recusado',
    'PENDING AUTHENTICATED E2E — nao executavel por execute_sql (is_admin FALSE). Prova a invariante final; GUARD 6c tem precedencia.');
SELECT pg_temp._pend2828('B2 REJECTED em OUT_OF_SCOPE recusado',
    'PENDING AUTHENTICATED E2E — nao executavel por execute_sql (is_admin FALSE). Prova DIRETA do GUARD 7.');
SELECT pg_temp._pend2828('B3 PENDING em OUT_OF_SCOPE recusado',
    'PENDING AUTHENTICATED E2E — nao executavel por execute_sql (is_admin FALSE). Prova DIRETA do GUARD 7.');
SELECT pg_temp._pend2828('B4 SKIPPED idempotente preservado',
    'PENDING AUTHENTICATED E2E — nao executavel por execute_sql (is_admin FALSE). Unico caso que escreve (no-op).');
SELECT pg_temp._pend2828('B5 lote misto: tudo ou nada',
    'PENDING AUTHENTICATED E2E — nao executavel por execute_sql (is_admin FALSE). Prova de atomicidade.');

-- ---------------------------------------------------------------------------
-- Depois de executar B1-B5 na sessão administrativa real, o operador promove
-- cada caso com a evidência colhida. Exemplo (NÃO executar agora):
--
--   SELECT pg_temp._e2e2828('B2 REJECTED em OUT_OF_SCOPE recusado', TRUE,
--     'HTTP 400 P0001 ADMIN_DECIDE_CATALOG_VARIANT_IMPORT_ROW_SIZE_OUT_OF_SCOPE: '
--     '1 linha(s) ... nao pode virar REJECTED. postcheck: decision_status=SKIPPED');
--
-- Só então o gate abaixo pode chegar a COMPLETE.
-- ---------------------------------------------------------------------------

-- ===========================================================================
-- DETALHE POR CASO
-- ===========================================================================

SELECT secao, caso, estado, detalhe FROM _r2828 ORDER BY secao DESC, caso;

-- ===========================================================================
-- GATE FINAL — LINHA ÚNICA, LEGÍVEL POR MÁQUINA (FINDING 2828-B)
--
-- A v1.0 sinalizava o estado pendente apenas por RAISE NOTICE e terminava
-- com sucesso — um leitor podia interpretar "rodou sem erro" como verde.
-- Agora o estado é um DADO na saída, com domínio fechado:
--
--   'PENDING AUTHENTICATED E2E'  Seção 1 OK, B1-B5 ainda não comprovados
--   'COMPLETE'                   Seção 1 OK e os 5 casos E2E com PASS
--   'FAILED'                     qualquer falha real, ou roster incompleto
-- ===========================================================================

SELECT
    CASE
        WHEN (SELECT COUNT(*) FROM _r2828) <> 23                              THEN 'FAILED'
        WHEN (SELECT COUNT(*) FROM _r2828 WHERE estado = 'FAIL') > 0          THEN 'FAILED'
        WHEN (SELECT COUNT(*) FROM _r2828 WHERE estado = 'PENDING') > 0       THEN 'PENDING AUTHENTICATED E2E'
        WHEN (SELECT COUNT(*) FROM _r2828 WHERE secao = 'E2E' AND estado = 'PASS') = 5
         AND (SELECT COUNT(*) FROM _r2828 WHERE secao = 'STRUCTURAL' AND estado = 'PASS') = 18
                                                                              THEN 'COMPLETE'
        ELSE 'FAILED'
    END                                                                        AS gate_state,
    (SELECT COUNT(*) FROM _r2828 WHERE secao = 'STRUCTURAL' AND estado = 'PASS')    AS structural_pass,
    (SELECT COUNT(*) FROM _r2828 WHERE secao = 'STRUCTURAL' AND estado = 'FAIL')    AS structural_fail,
    (SELECT COUNT(*) FROM _r2828 WHERE secao = 'E2E' AND estado = 'PASS')           AS authenticated_e2e_pass,
    (SELECT COUNT(*) FROM _r2828 WHERE secao = 'E2E' AND estado = 'PENDING')        AS authenticated_e2e_pending,
    (SELECT COUNT(*) FROM _r2828 WHERE secao = 'E2E' AND estado = 'FAIL')           AS authenticated_e2e_fail;

-- ===========================================================================
-- GATE FINAL — EXCEÇÃO EXPLÍCITA
--
-- Falha real (estrutural ou E2E) e roster incompleto ABORTAM. Estado apenas
-- PENDENTE não aborta — é um resultado legítimo desta etapa —, mas já foi
-- reportado como dado na linha acima, e o NOTICE abaixo é reforço, nunca a
-- evidência única.
-- ===========================================================================

DO $gate$
DECLARE
    v_total  INTEGER;
    v_sfail  INTEGER;
    v_efail  INTEGER;
    v_epend  INTEGER;
    v_falt   TEXT;
    c_roster CONSTANT TEXT[] := ARRAY[
        'S1.1 funcao existe',
        'S1.2 GUARD 7 presente no corpo LIVE',
        'S1.3 guard le normalized_data->>skip_reason',
        'S1.4 guard so dispara para decisao <> SKIPPED (idempotencia preservada)',
        'S1.5 GUARD 7 vem ANTES do UPDATE',
        'S1.6 GUARD 7 vem DEPOIS do guard de APPROVED (precedencia de mensagem preservada)',
        'S1.7 GUARD 1 is_admin intacto',
        'S1.8 GUARD 3 array_ndims intacto',
        'S1.9 GUARD 5 teto 10000 intacto',
        'S1.10 GUARD job STAGED intacto',
        'S1.11 SECURITY DEFINER preservado',
        'S1.12 search_path="" preservado',
        'S1.13a PUBLIC NAO possui EXECUTE (ACL NULL falha aqui, por acldefault)',
        'S1.13b anon NAO possui EXECUTE',
        'S1.13c nenhum grantee alem de owner e authenticated',
        'S1.13d ACL e EXPLICITA (proacl NOT NULL) — REVOKE/GRANT da 2199 aplicados',
        'S1.14 authenticated POSSUI EXECUTE (prova positiva)',
        'S1.15 BASELINE INTEGRITY CHECK (VACUOUS BEFORE EDGE RERUN)',
        'B1 APPROVED em OUT_OF_SCOPE recusado',
        'B2 REJECTED em OUT_OF_SCOPE recusado',
        'B3 PENDING em OUT_OF_SCOPE recusado',
        'B4 SKIPPED idempotente preservado',
        'B5 lote misto: tudo ou nada'
    ];
BEGIN
    SELECT COUNT(*),
           COUNT(*) FILTER (WHERE secao = 'STRUCTURAL' AND estado = 'FAIL'),
           COUNT(*) FILTER (WHERE secao = 'E2E' AND estado = 'FAIL'),
           COUNT(*) FILTER (WHERE secao = 'E2E' AND estado = 'PENDING')
      INTO v_total, v_sfail, v_efail, v_epend
      FROM _r2828;

    SELECT string_agg(x, ', ')
      INTO v_falt
      FROM unnest(c_roster) AS x
     WHERE x NOT IN (SELECT caso FROM _r2828);

    IF v_falt IS NOT NULL THEN
        RAISE EXCEPTION 'HARNESS_2828_CASOS_AUSENTES: %', v_falt;
    END IF;

    IF v_total <> 23 THEN
        RAISE EXCEPTION 'HARNESS_2828_ROSTER_INESPERADO: % casos registrados, esperado 23.', v_total;
    END IF;

    IF v_sfail > 0 OR v_efail > 0 THEN
        RAISE EXCEPTION 'HARNESS_2828_FAILED: % falha(s) estrutural(is) e % falha(s) E2E.', v_sfail, v_efail;
    END IF;

    IF v_epend > 0 THEN
        RAISE NOTICE '2828: gate_state = PENDING AUTHENTICATED E2E (% de 5 casos E2E por executar). A Secao 1 passar NAO fecha o gate.', v_epend;
    ELSE
        RAISE NOTICE '2828: gate_state = COMPLETE.';
    END IF;
END;
$gate$;
