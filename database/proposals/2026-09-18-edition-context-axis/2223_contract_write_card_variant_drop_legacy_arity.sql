-- ============================================================================
-- Query 2223 — CONTRACT: DROP de internal.write_card_variant(6 args)
-- Status: PROPOSTA — NÃO EXECUTADA · Versão 1.0
-- Mandato: EDITION-CONTEXT-AXIS-WRITER-EXPAND-CONTRACT-CORRECTION-01
--
-- ----------------------------------------------------------------------------
-- RESPONSABILIDADE ÚNICA
-- ----------------------------------------------------------------------------
--   Terceira e última etapa da troca do writer:
--
--     2217 (EXPAND)   cria a de SETE · preserva a de SEIS
--     2218 (SWITCH)   confirm passa a chamar SOMENTE a de sete
--     2223 (CONTRACT) ESTA QUERY — prova que ninguém usa a de seis, e dropa
--
--   Esta Query NÃO cria, NÃO altera e NÃO substitui nada. Ela prova e remove.
--
-- ----------------------------------------------------------------------------
-- POR QUE UM ARQUIVO PRÓPRIO
-- ----------------------------------------------------------------------------
--   Na v1.0 da 2217 o DROP morava dentro do EXPAND, com um guard que exigia a
--   2218 já aplicada. Isso invertia a ordem natural (2218 → 2217) e criava uma
--   janela em que o confirm chamava um writer de sete argumentos inexistente.
--   Separar o CONTRACT elimina a janela: entre 2217 e 2223 as duas assinaturas
--   coexistem e o sistema é sempre executável.
--
-- ----------------------------------------------------------------------------
-- SEM WRAPPER DE COMPATIBILIDADE — DECISÃO EXPLÍCITA
-- ----------------------------------------------------------------------------
--   Não se cria uma de seis argumentos que delegue à de sete passando NULL no
--   eixo de contexto. NULL aqui NÃO é placeholder: é o valor semanticamente
--   carregado "sem contexto de edição". Um wrapper faria qualquer caller
--   esquecido gravar esse valor SILENCIOSAMENTE — exatamente a falha que a
--   identidade de quatro componentes existe para eliminar. Sem wrapper, um
--   caller esquecido vira erro de compilação. É a mesma disciplina que a v2.0
--   adotou ao remover o DEFAULT de Printing (Query 2187).
--
-- ----------------------------------------------------------------------------
-- PROVA NEGATIVA DE CALLERS — LEVANTAMENTO ESTÁTICO DO REPOSITÓRIO
-- ----------------------------------------------------------------------------
--   Varredura de `write_card_variant` em *.sql, *.ts, *.tsx, *.js:
--
--     EXECUTÁVEL E CANÔNICO ... 1 caller
--       database/schema/2145_create_admin_confirm_catalog_variant_import_function.sql:395
--         v_result_variant_id := internal.write_card_variant(
--       → é exatamente a função que a Query 2218 redefine.
--
--     NÃO-EXECUTÁVEIS (nenhum é caller vivo):
--       database/schema/2143_…          definição + REVOKEs da própria de seis
--       database/proposals/2026-09-12-…/2164_…:409   staging histórico, superado
--       database/proposals/2026-09-12-…/2179_…:376   staging histórico, superado
--       web/lib/catalogo/queries.ts:1929             COMENTÁRIO, não chamada
--       docs/05b-…, docs/log.md                      documentação
--
--     FRONTEND / EDGE ......... 0 chamadas. A função é `internal.` e nunca teve
--       grant para anon/authenticated — inalcançável por PostgREST por
--       construção.
--
--   O levantamento estático é EVIDÊNCIA, não garantia. A garantia é o gate
--   C2 abaixo, que roda contra o catálogo do banco no momento da execução.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------- PASSO 1 ---
-- PRÉ-CONDIÇÃO: o EXPAND (2217) e o SWITCH (2218) já rodaram.
DO $$
DECLARE v_n6 INT; v_n7 INT;
BEGIN
    SELECT COUNT(*) FILTER (WHERE p.pronargs = 6),
           COUNT(*) FILTER (WHERE p.pronargs = 7)
      INTO v_n6, v_n7
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'internal' AND p.proname = 'write_card_variant';

    IF v_n7 <> 1 THEN
        RAISE EXCEPTION 'CONTRACT_BLOCKED_NO_V3: a assinatura de 7 args nao existe (encontradas %). Rode a Query 2217 (EXPAND) antes.', v_n7;
    END IF;

    -- Idempotência: se a de seis ja sumiu, nao ha o que contratar.
    IF v_n6 = 0 THEN
        RAISE NOTICE 'CONTRACT NO-OP: a assinatura de 6 args ja nao existe. Nada a fazer.';
    END IF;
END $$;

-- ---------------------------------------------------------------- PASSO 2 ---
-- C1 — O CONFIRM JÁ USA SETE ARGUMENTOS.
-- Testa o corpo real instalado, não o arquivo em disco.
DO $$
DECLARE v_src TEXT; v_n INT;
BEGIN
    SELECT COUNT(*) INTO v_n
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'admin_confirm_catalog_variant_import';
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'CONTRACT_CONFIRM_AMBIGUOUS: esperada 1 definicao de admin_confirm_catalog_variant_import, encontrada %.', v_n;
    END IF;

    SELECT p.prosrc INTO v_src
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'admin_confirm_catalog_variant_import';

    IF v_src NOT LIKE '%write_card_variant(%' THEN
        RAISE EXCEPTION 'CONTRACT_CONFIRM_NO_WRITER_CALL: o confirm instalado nao chama write_card_variant. Estado inesperado — investigar antes de dropar.';
    END IF;

    -- O SWITCH (2218) introduz o sétimo argumento nomeado. Sua ausência prova
    -- que a 2218 ainda nao rodou.
    IF v_src NOT LIKE '%edition_context_profile_id%' THEN
        RAISE EXCEPTION 'CONTRACT_BLOCKED_SWITCH_PENDING: admin_confirm_catalog_variant_import ainda nao passa o eixo de Edition Context ao writer. Rode a Query 2218 (SWITCH) antes.';
    END IF;
END $$;

-- ---------------------------------------------------------------- PASSO 3 ---
-- C2 — PROVA NEGATIVA DATABASE-WIDE: nenhuma função do banco menciona o
-- writer sem o sétimo argumento. Varre TODO o catálogo, não uma lista.
--
-- Critério: qualquer rotina (exceto a própria write_card_variant) cujo corpo
-- chame `write_card_variant(` E NAO mencione `edition_context_profile_id` é
-- um caller legado presumido. Fail-loud com o nome de cada uma.
DO $$
DECLARE v_legacy TEXT;
BEGIN
    SELECT string_agg(n.nspname || '.' || p.proname, ', ' ORDER BY n.nspname, p.proname)
      INTO v_legacy
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname NOT IN ('pg_catalog','information_schema')
       AND p.proname <> 'write_card_variant'
       AND p.prosrc LIKE '%write_card_variant(%'
       AND p.prosrc NOT LIKE '%edition_context_profile_id%';

    IF v_legacy IS NOT NULL THEN
        RAISE EXCEPTION 'CONTRACT_LEGACY_CALLERS_PRESENT: ainda existem callers da assinatura de 6 args: %. Corrija-os antes do DROP.', v_legacy;
    END IF;
END $$;

-- ---------------------------------------------------------------- PASSO 4 ---
-- C3 — PROVA NEGATIVA DE DEPENDÊNCIA FORMAL. Se qualquer objeto do banco
-- depende da de seis pelo catálogo (view, default, trigger), o DROP falharia
-- ou cascatearia. Aqui a checagem é explícita e ANTES, nunca por CASCADE.
DO $$
DECLARE v_dep TEXT; v_oid OID;
BEGIN
    SELECT p.oid INTO v_oid
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'internal' AND p.proname = 'write_card_variant'
       AND p.pronargs = 6;

    IF v_oid IS NOT NULL THEN
        SELECT string_agg(DISTINCT d.classid::regclass::TEXT || '#' || d.objid::TEXT, ', ')
          INTO v_dep
          FROM pg_depend d
         WHERE d.refobjid = v_oid
           AND d.deptype <> 'i'
           AND d.classid <> 'pg_proc'::regclass;

        IF v_dep IS NOT NULL THEN
            RAISE EXCEPTION 'CONTRACT_HARD_DEPENDENCY: objetos dependem formalmente da assinatura de 6 args: %.', v_dep;
        END IF;
    END IF;
END $$;

-- ---------------------------------------------------------------- PASSO 5 ---
-- DROP. Sem CASCADE — se algo escapou dos gates, que falhe aqui.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'internal' AND p.proname = 'write_card_variant'
           AND p.pronargs = 6
    ) THEN
        DROP FUNCTION internal.write_card_variant(TEXT, UUID, UUID, UUID, INTEGER, UUID);
    END IF;
END $$;

-- ---------------------------------------------------------------- PASSO 6 ---
-- POSTCHECK: exatamente UMA assinatura, a de SETE, íntegra.
DO $$
DECLARE v_n INT; v_args INT; v_def INT; v_sec BOOLEAN; v_cfg TEXT[];
BEGIN
    SELECT COUNT(*) INTO v_n
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'internal' AND p.proname = 'write_card_variant';
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'CONTRACT_POSTCHECK_SIGNATURES: esperada exatamente 1 assinatura, encontrada %.', v_n;
    END IF;

    SELECT p.pronargs, p.pronargdefaults, p.prosecdef, p.proconfig
      INTO v_args, v_def, v_sec, v_cfg
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'internal' AND p.proname = 'write_card_variant';

    IF v_args <> 7 THEN
        RAISE EXCEPTION 'CONTRACT_POSTCHECK_ARITY: a assinatura sobrevivente tem % args, esperado 7 (dropou a errada?).', v_args;
    END IF;
    IF v_def <> 0 THEN RAISE EXCEPTION 'CONTRACT_POSTCHECK_DEFAULT: nenhum argumento pode ter DEFAULT (obtido %).', v_def; END IF;
    IF v_sec IS NOT TRUE THEN RAISE EXCEPTION 'CONTRACT_POSTCHECK_SECDEF: SECURITY DEFINER perdido.'; END IF;
    IF NOT (v_cfg::TEXT LIKE '%search_path=%') THEN
        RAISE EXCEPTION 'CONTRACT_POSTCHECK_SEARCH_PATH: proconfig sem search_path.';
    END IF;

    IF EXISTS (
        SELECT 1 FROM information_schema.role_routine_grants
         WHERE routine_schema = 'internal' AND routine_name = 'write_card_variant'
           AND grantee IN ('anon','authenticated','PUBLIC')
    ) THEN
        RAISE EXCEPTION 'CONTRACT_POSTCHECK_GRANT_LEAK: grant indevido para anon/authenticated/PUBLIC.';
    END IF;

    RAISE NOTICE 'CONTRACT OK — internal.write_card_variant com 1 assinatura (7 args), 0 defaults, SECDEF, search_path, sem grants publicos. Troca do writer concluida.';
END $$;

-- ============================================================================
-- ESTADO APÓS ESTA QUERY:
--   internal.write_card_variant .......... 1 assinatura, 7 args
--   admin_confirm_catalog_variant_import ... chama a de sete
--   overload ............................... eliminado
--
-- ARMADO PARA ROLLOUT (ROLLOUT-EXECUTION-READINESS-01). Terminador COMMIT.
-- Corpo auditado PRESERVADO byte a byte; a unica alteracao de armamento foi
-- ROLLBACK; -> COMMIT;. A protecao contra execucao prematura e GOVERNANCA
-- (autorizacao de Fabricio + ordem de batches), nao o terminador — mesma
-- decisao ja aceita em R1 para 2203-2211.
-- ============================================================================
COMMIT;
