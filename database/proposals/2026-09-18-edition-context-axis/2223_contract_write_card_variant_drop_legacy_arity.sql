-- ============================================================================
-- Query 2223 — CONTRACT: DROP de internal.write_card_variant(6 args)
-- Status: PROPOSTA — NÃO EXECUTADA · Versão 1.1
-- Mandato: EDITION-CONTEXT-AXIS-WRITER-EXPAND-CONTRACT-CORRECTION-01
-- v1.1: BATCH9-2223-CONTRACT-HARDENING-01 — gates por ASSINATURA EXATA,
--       hash físico EXATO do confirm instalado (2218), caller database-wide
--       por identidade (não por ausência textual), dependências formais
--       fail-closed sem exclusão de pg_proc, DROP exato e SEM CASCADE,
--       postcheck com fingerprint do writer7 e ACL owner-only.
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
--   O levantamento estático é EVIDÊNCIA, não garantia. A garantia são os
--   gates abaixo, que rodam contra o catálogo do banco no momento da execução.
--
-- ----------------------------------------------------------------------------
-- AUTORIDADES (v1.1)
-- ----------------------------------------------------------------------------
--   * Assinaturas por to_regprocedure() EXATO — nunca por pronargs.
--   * Confirm instalado por HASH do prosrc normalizado (CRLF → LF), bytes e
--     contagem de LF — o mesmo método da 2218 (STD-001 v1.45). Nenhum LIKE
--     sobre o corpo é autoridade; LIKE fica, no máximo, como diagnóstico.
--   * Caller = qualquer rotina do banco cujo prosrc case com a regex
--     write_card_variant"?\s*\( (case-insensitive), exceto as próprias
--     overloads internal.write_card_variant. Exatamente 1 caller é aceito, e
--     ele precisa ser o confirm com o hash auditado. A decisão NÃO depende de
--     presença/ausência de 'edition_context_profile_id' no texto.
--   * Dependências formais da de seis via pg_depend, com refclassid = pg_proc,
--     SEM excluir classid = pg_proc; qualquer deptype diferente de 'i' = STOP.
--     Isso também cobre rotinas com corpo SQL-standard (BEGIN ATOMIC), cujas
--     referências ficam em pg_depend e não em prosrc.
--
--   Idempotência: REMOVIDA de propósito na v1.1. A v1.0 virava NO-OP se a de
--   seis já não existisse; agora a ausência da de seis é STOP (P1.1). Rodar o
--   CONTRACT duas vezes é erro de governança, não caso a absorver.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------- PASSO 1 ---
-- PRÉ-CONDIÇÃO POR ASSINATURA EXATA: writer6 E writer7 existem, e são as
-- DUAS ÚNICAS overloads de internal.write_card_variant.
DO $$
DECLARE
    c_sig6 CONSTANT TEXT := 'internal.write_card_variant(text,uuid,uuid,uuid,integer,uuid)';
    c_sig7 CONSTANT TEXT := 'internal.write_card_variant(text,uuid,uuid,uuid,integer,uuid,uuid)';
    v_oid6 OID;
    v_oid7 OID;
    v_n    INT;
    v_sigs TEXT;
BEGIN
    v_oid6 := to_regprocedure(c_sig6)::OID;
    v_oid7 := to_regprocedure(c_sig7)::OID;

    -- P1.1 — a de seis existe (senão não há o que contratar: STOP, não NO-OP).
    IF v_oid6 IS NULL THEN
        RAISE EXCEPTION 'CONTRACT_WRITER6_ABSENT: % não existe. O CONTRACT já rodou ou o estado é inesperado — investigar, não repetir.', c_sig6;
    END IF;

    -- P1.2 — a de sete existe (EXPAND 2217 aplicado).
    IF v_oid7 IS NULL THEN
        RAISE EXCEPTION 'CONTRACT_BLOCKED_NO_WRITER7: % não existe. Rode a Query 2217 (EXPAND) antes.', c_sig7;
    END IF;

    -- P1.3 — exatamente DUAS overloads; qualquer terceira assinatura = STOP.
    SELECT count(*),
           string_agg(p.oid::REGPROCEDURE::TEXT, ', ' ORDER BY p.oid::REGPROCEDURE::TEXT)
      INTO v_n, v_sigs
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'internal' AND p.proname = 'write_card_variant';
    IF v_n <> 2 THEN
        RAISE EXCEPTION 'CONTRACT_WRITER_OVERLOADS: esperadas exatamente 2 overloads de internal.write_card_variant (writer6 + writer7), encontradas %: %.', v_n, v_sigs;
    END IF;

    RAISE NOTICE 'CONTRACT PASSO 1 OK — writer6 (oid %) e writer7 (oid %) presentes; 2 overloads exatas.', v_oid6, v_oid7;
END $$;

-- ---------------------------------------------------------------- PASSO 2 ---
-- C1 — O SWITCH (2218) ESTÁ INSTALADO: prova pelo CORPO FÍSICO EXATO do
-- confirm, não por texto. Testa o catálogo, não o arquivo em disco.
DO $$
DECLARE
    c_sig_confirm CONSTANT TEXT := 'public.admin_confirm_catalog_variant_import(uuid,uuid[])';
    c_md5         CONSTANT TEXT := 'b83f7708ca2b7498b753b394d768f66e';
    c_bytes       CONSTANT INT  := 20095;
    c_lf          CONSTANT INT  := 389;
    v_confirm OID;
    v_n       INT;
    v_norm    TEXT;
    v_md5     TEXT;
    v_bytes   INT;
    v_lf      INT;
BEGIN
    v_confirm := to_regprocedure(c_sig_confirm)::OID;
    IF v_confirm IS NULL THEN
        RAISE EXCEPTION 'CONTRACT_CONFIRM_MISSING: % não existe.', c_sig_confirm;
    END IF;
    SELECT count(*) INTO v_n
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'admin_confirm_catalog_variant_import';
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'CONTRACT_CONFIRM_AMBIGUOUS: esperada 1 definição de admin_confirm_catalog_variant_import, encontradas %.', v_n;
    END IF;

    SELECT replace(p.prosrc, E'\r\n', E'\n') INTO v_norm FROM pg_proc p WHERE p.oid = v_confirm;
    v_md5   := md5(v_norm);
    v_bytes := octet_length(v_norm);
    v_lf    := length(v_norm) - length(replace(v_norm, E'\n', ''));

    IF v_md5 IS DISTINCT FROM c_md5 OR v_bytes IS DISTINCT FROM c_bytes OR v_lf IS DISTINCT FROM c_lf THEN
        RAISE EXCEPTION 'CONTRACT_BLOCKED_SWITCH_NOT_VERIFIED: corpo instalado de % difere do SWITCH auditado (2218). Obtido md5=% bytes=% lf=% · esperado md5=% bytes=% lf=%.',
            c_sig_confirm, v_md5, v_bytes, v_lf, c_md5, c_bytes, c_lf;
    END IF;

    -- Diagnóstico apenas (NÃO é autoridade):
    RAISE NOTICE 'CONTRACT PASSO 2 OK — confirm = SWITCH auditado (md5 % · % bytes · % LF). diag: menciona_eixo3=%',
        v_md5, v_bytes, v_lf, strpos(v_norm, 'edition_context_profile_id') > 0;
END $$;

-- ---------------------------------------------------------------- PASSO 3 ---
-- C2 — CALLERS DATABASE-WIDE POR IDENTIDADE. Varre TODO o pg_proc (nenhum
-- schema excluído); exclui SOMENTE as próprias overloads do writer. Exige
-- EXATAMENTE 1 caller, e esse caller tem de ser o confirm com o hash
-- auditado. Segundo caller, caller diferente ou hash divergente = STOP.
DO $$
DECLARE
    c_sig_confirm CONSTANT TEXT := 'public.admin_confirm_catalog_variant_import(uuid,uuid[])';
    c_md5         CONSTANT TEXT := 'b83f7708ca2b7498b753b394d768f66e';
    v_confirm OID;
    v_n       INT;
    v_oid     OID;
    v_md5     TEXT;
    v_lista   TEXT;
BEGIN
    v_confirm := to_regprocedure(c_sig_confirm)::OID;

    SELECT count(*),
           min(p.oid),
           string_agg(p.oid::REGPROCEDURE::TEXT
                      || ' md5=' || md5(replace(p.prosrc, E'\r\n', E'\n')),
                      ', ' ORDER BY p.oid::REGPROCEDURE::TEXT)
      INTO v_n, v_oid, v_lista
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE NOT (n.nspname = 'internal' AND p.proname = 'write_card_variant')
       AND p.prosrc ~* 'write_card_variant"?\s*\(';

    IF v_n <> 1 THEN
        RAISE EXCEPTION 'CONTRACT_CALLERS_NOT_EXACTLY_ONE: esperado exatamente 1 caller de write_card_variant (o confirm), encontrados %: %.', v_n, COALESCE(v_lista, '(nenhum)');
    END IF;
    IF v_oid IS DISTINCT FROM v_confirm THEN
        RAISE EXCEPTION 'CONTRACT_CALLER_UNEXPECTED: o único caller não é %: %.', c_sig_confirm, v_lista;
    END IF;
    SELECT md5(replace(p.prosrc, E'\r\n', E'\n')) INTO v_md5 FROM pg_proc p WHERE p.oid = v_oid;
    IF v_md5 IS DISTINCT FROM c_md5 THEN
        RAISE EXCEPTION 'CONTRACT_CALLER_HASH: o caller % tem md5=% (esperado %).', c_sig_confirm, v_md5, c_md5;
    END IF;

    RAISE NOTICE 'CONTRACT PASSO 3 OK — exatamente 1 caller: %.', v_lista;
END $$;

-- ---------------------------------------------------------------- PASSO 4 ---
-- C3 — DEPENDÊNCIAS FORMAIS DA DE SEIS, FAIL-CLOSED. Resolve o OID pela
-- assinatura exata e procura QUALQUER objeto que dependa dela em pg_depend
-- (refclassid = pg_proc), SEM excluir classid = pg_proc. Qualquer deptype
-- diferente de 'i' = STOP, listando classid/objid/objsubid/deptype.
DO $$
DECLARE
    c_sig6 CONSTANT TEXT := 'internal.write_card_variant(text,uuid,uuid,uuid,integer,uuid)';
    v_oid6 OID;
    v_n    INT;
    v_dep  TEXT;
BEGIN
    v_oid6 := to_regprocedure(c_sig6)::OID;
    IF v_oid6 IS NULL THEN
        RAISE EXCEPTION 'CONTRACT_WRITER6_ABSENT_AT_DEPCHECK: % não existe.', c_sig6;
    END IF;

    SELECT count(*),
           string_agg('classid=' || d.classid::REGCLASS::TEXT
                      || ' objid=' || d.objid::TEXT
                      || ' objsubid=' || d.objsubid::TEXT
                      || ' deptype=' || d.deptype::TEXT,
                      '; ' ORDER BY d.classid, d.objid, d.objsubid)
      INTO v_n, v_dep
      FROM pg_depend d
     WHERE d.refclassid = 'pg_catalog.pg_proc'::REGCLASS
       AND d.refobjid = v_oid6
       AND d.deptype <> 'i';

    IF v_n <> 0 THEN
        RAISE EXCEPTION 'CONTRACT_HARD_DEPENDENCY: % dependência(s) formal(is) não-interna(s) de %: %.', v_n, c_sig6, v_dep;
    END IF;

    RAISE NOTICE 'CONTRACT PASSO 4 OK — 0 dependências formais não-internas de writer6.';
END $$;

-- ---------------------------------------------------------------- PASSO 5 ---
-- DROP da assinatura EXATA da de seis. Incondicional (os PASSOS 1-4 provaram
-- que ela existe e é segura) e SEM CASCADE — RESTRICT explícito: se algo
-- escapou dos gates, que falhe aqui.
DROP FUNCTION internal.write_card_variant(TEXT, UUID, UUID, UUID, INTEGER, UUID) RESTRICT;

-- ---------------------------------------------------------------- PASSO 6 ---
-- POSTCHECK. Qualquer divergência aborta a transação inteira e a de seis
-- continua existindo.
DO $$
DECLARE
    c_sig6        CONSTANT TEXT := 'internal.write_card_variant(text,uuid,uuid,uuid,integer,uuid)';
    c_sig7        CONSTANT TEXT := 'internal.write_card_variant(text,uuid,uuid,uuid,integer,uuid,uuid)';
    c_sig_confirm CONSTANT TEXT := 'public.admin_confirm_catalog_variant_import(uuid,uuid[])';
    c_w7_md5      CONSTANT TEXT := '478aada84470a7fba1c9b6d5254a40f1';
    c_w7_bytes    CONSTANT INT  := 2707;
    c_w7_lf       CONSTANT INT  := 54;
    c_cf_md5      CONSTANT TEXT := 'b83f7708ca2b7498b753b394d768f66e';
    c_cf_bytes    CONSTANT INT  := 20095;
    c_cf_lf       CONSTANT INT  := 389;
    v_oid7    OID;
    v_confirm OID;
    v_n       INT;
    v_p       RECORD;
    v_norm    TEXT;
    v_md5     TEXT;
    v_bytes   INT;
    v_lf      INT;
    v_own_x   BOOLEAN;
    v_outros  INT;
    v_quem    TEXT;
    v_oid     OID;
    v_lista   TEXT;
BEGIN
    -- Q1 — writer6 não existe mais.
    IF to_regprocedure(c_sig6) IS NOT NULL THEN
        RAISE EXCEPTION 'CONTRACT_POST_WRITER6_STILL_PRESENT: % ainda existe.', c_sig6;
    END IF;

    -- Q2 — writer7 existe.
    v_oid7 := to_regprocedure(c_sig7)::OID;
    IF v_oid7 IS NULL THEN
        RAISE EXCEPTION 'CONTRACT_POST_WRITER7_MISSING: % não existe (dropou a errada?).', c_sig7;
    END IF;

    -- Q3 — exatamente UMA internal.write_card_variant.
    SELECT count(*) INTO v_n
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'internal' AND p.proname = 'write_card_variant';
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'CONTRACT_POST_OVERLOADS: esperada exatamente 1 internal.write_card_variant, encontradas %.', v_n;
    END IF;

    -- Q4 — fingerprint do writer7 (corpo normalizado CRLF → LF).
    SELECT p.* INTO v_p FROM pg_proc p WHERE p.oid = v_oid7;
    v_norm  := replace(v_p.prosrc, E'\r\n', E'\n');
    v_md5   := md5(v_norm);
    v_bytes := octet_length(v_norm);
    v_lf    := length(v_norm) - length(replace(v_norm, E'\n', ''));
    IF v_md5 IS DISTINCT FROM c_w7_md5 OR v_bytes IS DISTINCT FROM c_w7_bytes OR v_lf IS DISTINCT FROM c_w7_lf THEN
        RAISE EXCEPTION 'CONTRACT_POST_WRITER7_BODY: md5=% bytes=% lf=% (esperado md5=% bytes=% lf=%).',
            v_md5, v_bytes, v_lf, c_w7_md5, c_w7_bytes, c_w7_lf;
    END IF;

    -- Q5 — contrato do writer7.
    IF v_p.pronargs <> 7 THEN
        RAISE EXCEPTION 'CONTRACT_POST_WRITER7_ARITY: pronargs=% (esperado 7).', v_p.pronargs;
    END IF;
    IF v_p.pronargdefaults <> 0 THEN
        RAISE EXCEPTION 'CONTRACT_POST_WRITER7_DEFAULT: pronargdefaults=% (esperado 0).', v_p.pronargdefaults;
    END IF;
    IF v_p.prosecdef IS NOT TRUE THEN
        RAISE EXCEPTION 'CONTRACT_POST_WRITER7_SECDEF: SECURITY DEFINER perdido.';
    END IF;
    IF v_p.proconfig IS DISTINCT FROM ARRAY['search_path=""']::TEXT[] THEN
        RAISE EXCEPTION 'CONTRACT_POST_WRITER7_SEARCH_PATH: proconfig=% (esperado {search_path=""}).', COALESCE(v_p.proconfig::TEXT, '(NULO)');
    END IF;
    IF pg_get_userbyid(v_p.proowner) IS DISTINCT FROM 'postgres' THEN
        RAISE EXCEPTION 'CONTRACT_POST_WRITER7_OWNER: owner=% (esperado postgres).', pg_get_userbyid(v_p.proowner);
    END IF;
    IF v_p.proacl IS NULL THEN
        RAISE EXCEPTION 'CONTRACT_POST_WRITER7_ACL_DEFAULT: proacl NULL — ACL padrão concede EXECUTE a PUBLIC.';
    END IF;
    SELECT COALESCE(bool_or(a.grantee = v_p.proowner AND a.privilege_type = 'EXECUTE'), false),
           count(*) FILTER (WHERE a.grantee IS DISTINCT FROM v_p.proowner),
           COALESCE(string_agg(CASE WHEN a.grantee = 0 THEN 'PUBLIC'
                                    ELSE pg_get_userbyid(a.grantee) END
                               || ':' || a.privilege_type
                               || CASE WHEN a.is_grantable THEN '*' ELSE '' END
                               || '/' || pg_get_userbyid(a.grantor), ', '), '(ninguem)')
      INTO v_own_x, v_outros, v_quem
      FROM aclexplode(v_p.proacl) a;
    IF NOT v_own_x OR v_outros <> 0 THEN
        RAISE EXCEPTION 'CONTRACT_POST_WRITER7_ACL_NOT_OWNER_ONLY: esperado somente o owner com EXECUTE. Obtido: %.', v_quem;
    END IF;

    -- Q6 — confirm inalterado.
    v_confirm := to_regprocedure(c_sig_confirm)::OID;
    IF v_confirm IS NULL THEN
        RAISE EXCEPTION 'CONTRACT_POST_CONFIRM_MISSING: % não existe.', c_sig_confirm;
    END IF;
    SELECT replace(p.prosrc, E'\r\n', E'\n') INTO v_norm FROM pg_proc p WHERE p.oid = v_confirm;
    v_md5   := md5(v_norm);
    v_bytes := octet_length(v_norm);
    v_lf    := length(v_norm) - length(replace(v_norm, E'\n', ''));
    IF v_md5 IS DISTINCT FROM c_cf_md5 OR v_bytes IS DISTINCT FROM c_cf_bytes OR v_lf IS DISTINCT FROM c_cf_lf THEN
        RAISE EXCEPTION 'CONTRACT_POST_CONFIRM_BODY: md5=% bytes=% lf=% (esperado md5=% bytes=% lf=%).',
            v_md5, v_bytes, v_lf, c_cf_md5, c_cf_bytes, c_cf_lf;
    END IF;

    -- Q7 — nenhum caller novo/inesperado: continua exatamente 1, o confirm.
    SELECT count(*), min(p.oid),
           string_agg(p.oid::REGPROCEDURE::TEXT, ', ' ORDER BY p.oid::REGPROCEDURE::TEXT)
      INTO v_n, v_oid, v_lista
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE NOT (n.nspname = 'internal' AND p.proname = 'write_card_variant')
       AND p.prosrc ~* 'write_card_variant"?\s*\(';
    IF v_n <> 1 OR v_oid IS DISTINCT FROM v_confirm THEN
        RAISE EXCEPTION 'CONTRACT_POST_CALLERS: esperado exatamente 1 caller (%), obtidos %: %.', c_sig_confirm, v_n, COALESCE(v_lista, '(nenhum)');
    END IF;

    RAISE NOTICE 'CONTRACT OK — writer6 removida; writer7 única (md5 % · % bytes · % LF), SECDEF, search_path fixo, owner-only; confirm intacto; 1 caller.',
        c_w7_md5, c_w7_bytes, c_w7_lf;
END $$;

-- ============================================================================
-- ESTADO APÓS ESTA QUERY:
--   internal.write_card_variant .......... 1 assinatura, 7 args
--   admin_confirm_catalog_variant_import ... chama a de sete
--   overload ............................... eliminado
--
-- ARMADO PARA ROLLOUT (ROLLOUT-EXECUTION-READINESS-01). Terminador COMMIT.
-- A protecao contra execucao prematura e GOVERNANCA (autorizacao de
-- Fabricio + ordem de batches), nao o terminador — mesma decisao ja aceita
-- em R1 para 2203-2211. Executar por MCP/CLI, não pelo Dashboard Query
-- Editor (STD-001 v1.45).
-- ============================================================================
COMMIT;
