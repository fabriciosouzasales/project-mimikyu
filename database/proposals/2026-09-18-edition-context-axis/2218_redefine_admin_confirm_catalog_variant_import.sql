-- ============================================================================
-- Query 2218 — public.admin_confirm_catalog_variant_import() v3.0
-- Status: EXECUTADA / LIVE VALIDATED / CLOSED · Versão 1.3 (a executada)
-- WRITE-PATH-STAGING-01 · itens 1, 2, 4, 5, 8
--
-- CLOSEOUT (BATCH9-EDITION-CONTEXT-WRITER-CLOSEOUT-01, 2026-09-25):
--   Executada 1x via Supabase MCP execute_sql em 2026-09-25 (~03:30Z),
--   retorno sem erro; POSTCHECK independente = LIVE VALIDATED.
--   Artefato EFETIVAMENTE executado (anterior a este bloco de comentário):
--     git hash-object 6f4dbd9c5ffe15bbf093a0747b7e77e8cc525553
--     md5 bedb5e32b3a86853482ea7c6754cab9e · 49403 bytes · 0 CR · 917 LF
--     corpo LF md5 b83f7708ca2b7498b753b394d768f66e · 20095 bytes · 389 LF
--   Naquele artefato o cabeçalho ainda dizia "Versão 1.2 / NÃO EXECUTADA";
--   a v1.3 (PARSE-CORRECTION-01) só trocou os delimitadores dos dois blocos
--   DO do PASSO 1/PASSO 3 por tags nomeadas. 1ª tentativa (v1.2, blob
--   983dbb63) falhou no parse com 42601 e não deixou efeito físico
--   (LIVE-STATE-PROBE-01). Este bloco é o ÚNICO acréscimo do closeout:
--   nenhuma linha executável foi alterada.
-- v1.1: BATCH9-2218-SWITCH-CORRECTION-01 (fecha B1/B2/B3 e H1-H4 da
--       BATCH9-2218-SWITCH-READINESS-AUDIT-01)
-- v1.2: BATCH9-2218-SWITCH-CORRECTION-02 — ACL de authenticated provada
--       SEM GRANT OPTION, entrada única e grantor = owner (P1.4 e Q6).
--       Corpo da função inalterado (mesmo hash LF).
--
-- BASE: database/schema/2145_..._function.sql v2.0 (CANÔNICA, 519 li).
-- Este arquivo é o ESTADO FINAL — corpo inteiro, não patch.
--
-- ----------------------------------------------------------------------------
-- O QUE MUDA frente à 2145 canônica
-- ----------------------------------------------------------------------------
--   (a) EIXO 3 tri-state: edition_context_profile_id lido com a MESMA
--       disciplina de jsonb_typeof já usada para printing (2145:333-356);
--   (b) MATCHING QUÁDRUPLO com IS NOT DISTINCT FROM nos dois eixos nuláveis;
--   (c) LOCK determinístico: todas as Cards do lote travadas ANTES do loop,
--       em ORDER BY id — elimina deadlock por ordem de aquisição;
--   (d) handler ESPECÍFICO de unique_violation, antes de WHEN OTHERS,
--       DISCRIMINADO por flag de tentativa do writer + tabela + constraint
--       (v1.1) — ver "EXCEPTION" abaixo;
--   (e) writer chamado com SETE argumentos (Query 2217).
--
-- O QUE MUDA frente ao LIVE (2164 v1.1 + 2179 v1.1) — além de (a)-(e):
--   (f) ELIMINA o RAMO LEGADO DE COMPATIBILIDADE DE PRINTING que a função
--       LIVE ainda carrega: v_bridge_present, leitura de pg_indexes por
--       uq_cvir_job_card_type_bridge_legacy, resolução de v_game_id /
--       v_asset_source_id e chamada a
--       internal.compute_variant_residual_signature(). É a mesma diferença
--       intencional já documentada na 2145 v2.0 ("O QUE NÃO VEIO").
--       A remoção só é neutra se, no LIVE:
--         · o índice-ponte uq_cvir_job_card_type_bridge_legacy NÃO existe
--           (removido pela 2184 — PHASE E); e
--         · existem ZERO linhas VALID operacionais sem a chave
--           printing_profile_id.
--       As DUAS provas são OBRIGATÓRIAS no LIVE PRECHECK desta Query. Com
--       elas, o ramo é inalcançável e a chave ausente é fail-closed nas duas
--       formas (mesmo código PRINTING_NOT_RESOLVED; muda só o texto).
--
-- PRESERVADO — nada aqui regride:
--   SECURITY DEFINER · search_path='' · REVOKE de PUBLIC · GRANT EXECUTE a
--   authenticated (reafirmado, idempotente) · is_admin()
--   c_max_rows = 1000 · GUARDs 1-7 · congelamento do conjunto efetivo
--   STAGED -> CONFIRMING · SKIPPED -> UNCHANGED sem escrita
--   variant_order = MAX+1 por Card · is_default nunca informado
--   recálculo de counters por agregação · audit log condicional
--   assinatura e RETURNS TABLE idênticos · todos os códigos de erro
--
-- ----------------------------------------------------------------------------
-- CONCORRÊNCIA — o desenho aprovado, implementado (INALTERADO na v1.1)
-- ----------------------------------------------------------------------------
--   LOCK ......... public.card ... FOR UPDATE, todas as Cards do lote,
--                  ORDER BY id, ANTES do loop.
--   ORDEM ........ id crescente. Dois lotes que se cruzam adquirem na MESMA
--                  ordem ⇒ deadlock impossível por ESTE caminho.
--   RECHECK ...... o matching quádruplo roda DEPOIS do lock. Uma T2 que
--                  esperou T1 enxerga a Variant criada e sai por MATCHED.
--   SERIALIZAÇÃO . FOR UPDATE na Card conflita com o FOR KEY SHARE que o FK
--                  card_variant.card_id toma em QUALQUER INSERT concorrente
--                  para a mesma Card. Enquanto o lock é mantido, nenhuma
--                  outra transação consegue inserir Variant para essas Cards;
--                  por isso uma corrida de criação DEPOIS do matching NÃO é
--                  esperada neste caminho (READ COMMITTED). O ramo de corrida
--                  benigna do handler é DEFENSIVO, não um fluxo previsto.
--   EXCEPTION .... WHEN unique_violation vem ANTES de WHEN OTHERS. Um 23505
--                  só é tratado como corrida benigna se TODAS forem verdade:
--                    A. o writer estava em execução (v_writer_attempted);
--                    B. a tabela é public.card_variant;
--                    C. a constraint pertence ao conjunto de IDENTIDADE:
--                         uq_card_variant_card_type_no_printing  (2171)
--                         uq_card_variant_card_type_printing     (2171)
--                         uq_card_variant_identity               (2209)
--                    D. a releitura pela identidade EXATA de 4 componentes
--                       encontra a Variant.
--                  Qualquer outro 23505 ⇒ FAILED, fail-closed, com código de
--                  negócio CARD_VARIANT_UNIQUE_VIOLATION_UNRESOLVED e
--                  schema/tabela/constraint/mensagem no error_detail.
--                  Nenhuma subtransação adicional: continua UM bloco
--                  EXCEPTION por row.
--   JANELA 2218 → 2209/2215: as UNIQUE antigas de card_variant são MAIS
--   restritivas que a identidade de 4 componentes. Duas Variants que diferem
--   SÓ em Contexto de Edição colidem nelas; a releitura quádrupla não acha
--   nada e a row vira FAILED (fail-closed, sem colapso silencioso). A
--   identidade física de 4 componentes NÃO está ativa antes da 2209 — o
--   FREEZE é parte da segurança desta janela.
--
-- ----------------------------------------------------------------------------
-- FRONTEIRA (item 8) — nenhum writer novo reativa histórico
-- ----------------------------------------------------------------------------
--   GUARD 5 (linha 270 da canônica) já recusa job fora de STAGED/CONFIRMING.
--   Nada nesta versão o afrouxa: rows de job CANCELLED/COMPLETED continuam
--   inalcançáveis por este caminho. CONFIRMÁVEL permanece
--   job ∈ (STAGED,CONFIRMING) + PENDING + APPROVED + VALID.
--
-- ----------------------------------------------------------------------------
-- AUTORIDADE DO POSTCHECK (v1.1)
-- ----------------------------------------------------------------------------
--   Nenhum gate textual (LIKE/position) sobre o corpo. A autoridade sobre o
--   corpo instalado é o HASH do prosrc normalizado por EOL (CRLF → LF),
--   comparado ao hash LF desta versão do arquivo (STD-001 v1.45). As demais
--   provas são estruturais, por pg_catalog.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------- PASSO 1 ---
-- PRÉ-CONDIÇÕES FAIL-CLOSED. A 2218 é SWITCH: não pode instalar um caller
-- para assinatura ausente, nem trocar a função sob um contrato de ACL
-- diferente do autorizado. Tudo provado por assinatura EXATA / OID.
DO $pre2218$
DECLARE
    c_sig_confirm CONSTANT TEXT := 'public.admin_confirm_catalog_variant_import(uuid,uuid[])';
    c_sig6        CONSTANT TEXT := 'internal.write_card_variant(text,uuid,uuid,uuid,integer,uuid)';
    c_sig7        CONSTANT TEXT := 'internal.write_card_variant(text,uuid,uuid,uuid,integer,uuid,uuid)';
    c_sig_guard   CONSTANT TEXT := 'internal.enforce_card_variant_edition_context_profile_game()';
    v_confirm   OID;
    v_oid6      OID;
    v_oid7      OID;
    v_guard     OID;
    v_owner     OID;
    v_auth      OID;
    v_cur       OID;
    v_n         INT;
    v_n_grantee INT;
    v_own_tem   BOOLEAN;
    v_auth_tem  BOOLEAN;
    v_estranho  INT;
    v_quem      TEXT;
    v_auth_rows INT;
    v_auth_go   BOOLEAN;
    v_auth_gtor BOOLEAN;
    v_rec       RECORD;
    v_t_foid    BOOLEAN;
    v_t_type    BOOLEAN;
    v_t_enabled BOOLEAN;
    v_t_intern  BOOLEAN;
BEGIN
    -- P1.1 — a coluna do 3º eixo existe (Query 2208). pg_attribute, não
    -- information_schema (que filtra por privilégio).
    IF NOT EXISTS (
        SELECT 1 FROM pg_attribute a
         WHERE a.attrelid = to_regclass('public.card_variant')
           AND a.attname = 'edition_context_profile_id'
           AND a.attnum > 0 AND NOT a.attisdropped) THEN
        RAISE EXCEPTION 'CONFIRM_V3_BLOCKED: card_variant.edition_context_profile_id ausente. Rode a Query 2208 antes.';
    END IF;

    -- P1.2 — a função substituída existe, por assinatura exata, e é a ÚNICA
    -- com esse nome no schema.
    v_confirm := to_regprocedure(c_sig_confirm)::OID;
    IF v_confirm IS NULL THEN
        RAISE EXCEPTION 'CONFIRM_V3_TARGET_MISSING: % não existe.', c_sig_confirm;
    END IF;
    SELECT count(*) INTO v_n
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'admin_confirm_catalog_variant_import';
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'CONFIRM_V3_TARGET_OVERLOADED: esperada 1 função public.admin_confirm_catalog_variant_import, encontradas %.', v_n;
    END IF;

    SELECT p.proowner INTO v_owner FROM pg_proc p WHERE p.oid = v_confirm;

    -- P1.3 — quem executa É o owner. CREATE OR REPLACE exige isso e preserva
    -- owner/ACL; provar antes evita ambiguidade sobre quem ficaria dono.
    SELECT r.oid INTO v_cur FROM pg_roles r WHERE r.rolname = current_user;
    IF v_cur IS DISTINCT FROM v_owner THEN
        RAISE EXCEPTION 'CONFIRM_V3_NOT_OWNER: current_user=% mas owner(admin_confirm)=%.', current_user, pg_get_userbyid(v_owner);
    END IF;

    -- P1.4 — CONTRATO DE ACL da admin_confirm (PRE). Exatamente:
    --   A. proacl NOT NULL;
    --   B. owner com EXECUTE;
    --   C. authenticated com EXECUTE;
    --   D. EXATAMENTE UMA entrada EXECUTE de authenticated;
    --   E. nessa entrada, is_grantable = false (sem GRANT OPTION);
    --   F. grantor dessa entrada = owner da função;
    --   G. NENHUM grantee fora de {owner, authenticated} (PUBLIC incluso).
    -- Estado diferente = STOP para decisão explícita. Nada é "consertado".
    v_auth := to_regrole('authenticated')::OID;
    IF v_auth IS NULL THEN
        RAISE EXCEPTION 'CONFIRM_V3_ROLE_MISSING: role authenticated inexistente.';
    END IF;
    IF (SELECT p.proacl IS NULL FROM pg_proc p WHERE p.oid = v_confirm) THEN
        RAISE EXCEPTION 'CONFIRM_V3_PRE_ACL_DEFAULT: proacl NULL — ACL padrão concede EXECUTE a PUBLIC.';
    END IF;
    SELECT COALESCE(bool_or(a.grantee = v_owner AND a.privilege_type = 'EXECUTE'), false),
           COALESCE(bool_or(a.grantee = v_auth  AND a.privilege_type = 'EXECUTE'), false),
           count(*) FILTER (WHERE a.grantee = v_auth AND a.privilege_type = 'EXECUTE'),
           COALESCE(bool_or(a.is_grantable) FILTER (WHERE a.grantee = v_auth), false),
           COALESCE(bool_and(a.grantor = v_owner) FILTER (WHERE a.grantee = v_auth AND a.privilege_type = 'EXECUTE'), false),
           count(*) FILTER (WHERE a.grantee NOT IN (v_owner, v_auth)),
           COALESCE(string_agg(DISTINCT CASE WHEN a.grantee = 0 THEN 'PUBLIC'
                                             ELSE pg_get_userbyid(a.grantee) END
                                 || ':' || a.privilege_type
                                 || CASE WHEN a.is_grantable THEN '*' ELSE '' END
                                 || '/' || pg_get_userbyid(a.grantor), ', '), '(ninguem)')
      INTO v_own_tem, v_auth_tem, v_auth_rows, v_auth_go, v_auth_gtor, v_estranho, v_quem
      FROM pg_proc p, aclexplode(p.proacl) a
     WHERE p.oid = v_confirm;
    IF NOT v_own_tem OR NOT v_auth_tem OR v_auth_rows <> 1 OR v_auth_go
       OR NOT v_auth_gtor OR v_estranho <> 0 THEN
        RAISE EXCEPTION 'CONFIRM_V3_PRE_ACL_CONTRACT: esperado {owner % com EXECUTE; authenticated com EXATAMENTE 1 entrada EXECUTE, sem GRANT OPTION, grantor = owner} e nenhum outro grantee (PUBLIC incluso). Obtido: % · entradas authenticated=% · grant_option=% · grantor_ok=% · estranhos=%.',
            pg_get_userbyid(v_owner), v_quem, v_auth_rows, v_auth_go, v_auth_gtor, v_estranho;
    END IF;

    -- P1.5 — writer6 E writer7 existem, por assinatura EXATA, e são as DUAS
    -- únicas overloads (janela EXPAND → CONTRACT).
    v_oid6 := to_regprocedure(c_sig6)::OID;
    v_oid7 := to_regprocedure(c_sig7)::OID;
    IF v_oid7 IS NULL THEN
        RAISE EXCEPTION 'CONFIRM_V3_WRITER7_MISSING: % não existe. Rode a Query 2217 antes.', c_sig7;
    END IF;
    IF v_oid6 IS NULL THEN
        RAISE EXCEPTION 'CONFIRM_V3_WRITER6_MISSING: % não existe — deve coexistir até a Query 2223.', c_sig6;
    END IF;
    SELECT count(*) INTO v_n
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'internal' AND p.proname = 'write_card_variant';
    IF v_n <> 2 THEN
        RAISE EXCEPTION 'CONFIRM_V3_WRITER_OVERLOADS: esperadas exatamente 2 overloads de internal.write_card_variant, encontradas %.', v_n;
    END IF;

    -- P1.6 — contrato do writer7.
    SELECT p.prorettype, p.prosecdef, p.pronargdefaults, p.proconfig,
           p.proowner, p.proacl IS NULL AS acl_nula
      INTO v_rec
      FROM pg_proc p WHERE p.oid = v_oid7;
    IF v_rec.prorettype <> 'uuid'::REGTYPE::OID THEN
        RAISE EXCEPTION 'CONFIRM_V3_WRITER7_RETURNS: writer7 deve RETURNS uuid (obtido %).', v_rec.prorettype::REGTYPE;
    END IF;
    IF v_rec.prosecdef IS NOT TRUE THEN
        RAISE EXCEPTION 'CONFIRM_V3_WRITER7_NOT_SECDEF.';
    END IF;
    IF v_rec.pronargdefaults <> 0 THEN
        RAISE EXCEPTION 'CONFIRM_V3_WRITER7_HAS_DEFAULT: pronargdefaults=%.', v_rec.pronargdefaults;
    END IF;
    IF v_rec.proconfig IS DISTINCT FROM ARRAY['search_path=""']::TEXT[] THEN
        RAISE EXCEPTION 'CONFIRM_V3_WRITER7_SEARCH_PATH: proconfig=%.', COALESCE(v_rec.proconfig::TEXT, '(NULO)');
    END IF;
    IF v_rec.proowner <> v_owner THEN
        RAISE EXCEPTION 'CONFIRM_V3_WRITER7_OWNER: owner(writer7)=% difere de owner(admin_confirm)=%.', pg_get_userbyid(v_rec.proowner), pg_get_userbyid(v_owner);
    END IF;
    IF v_rec.acl_nula THEN
        RAISE EXCEPTION 'CONFIRM_V3_WRITER7_ACL_DEFAULT: proacl NULL — ACL padrão concede EXECUTE a PUBLIC.';
    END IF;
    SELECT count(DISTINCT a.grantee),
           COALESCE(bool_or(a.grantee = v_owner), false),
           COALESCE(string_agg(DISTINCT CASE WHEN a.grantee = 0 THEN 'PUBLIC'
                                             ELSE pg_get_userbyid(a.grantee) END, ', '), '(ninguem)')
      INTO v_n_grantee, v_own_tem, v_quem
      FROM pg_proc p, aclexplode(p.proacl) a
     WHERE p.oid = v_oid7 AND a.privilege_type = 'EXECUTE';
    IF NOT v_own_tem OR v_n_grantee <> 1 THEN
        RAISE EXCEPTION 'CONFIRM_V3_WRITER7_ACL_NOT_OWNER_ONLY: EXECUTE deve ser exclusivo do owner %. Obtido: %.', pg_get_userbyid(v_owner), v_quem;
    END IF;
    IF NOT has_function_privilege(v_owner, v_oid7, 'EXECUTE') THEN
        RAISE EXCEPTION 'CONFIRM_V3_WRITER7_OWNER_NO_EXECUTE: owner(admin_confirm) sem EXECUTE efetivo em writer7.';
    END IF;
    IF NOT has_schema_privilege(v_owner, 'internal', 'USAGE') THEN
        RAISE EXCEPTION 'CONFIRM_V3_OWNER_NO_USAGE_INTERNAL: owner(admin_confirm) sem USAGE no schema internal.';
    END IF;

    -- P1.7 — pré-requisito 2224 (autoridade same-Game do 3º eixo). A 2218
    -- NÃO duplica a regra; só prova que a autoridade está instalada e ativa.
    v_guard := to_regprocedure(c_sig_guard)::OID;
    IF v_guard IS NULL THEN
        RAISE EXCEPTION 'CONFIRM_V3_GUARD2224_MISSING: % não existe. Rode a Query 2224 antes.', c_sig_guard;
    END IF;
    SELECT count(*),
           bool_and(t.tgfoid = v_guard),
           bool_and(t.tgtype = 23),
           bool_and(t.tgenabled IN ('O', 'A')),
           bool_or(t.tgisinternal)
      INTO v_n, v_t_foid, v_t_type, v_t_enabled, v_t_intern
      FROM pg_trigger t
     WHERE t.tgrelid = to_regclass('public.card_variant')
       AND t.tgname = 'trg_card_variant_edition_context_profile_game';
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'CONFIRM_V3_GUARD2224_TRIGGER_COUNT: esperado 1 trigger trg_card_variant_edition_context_profile_game, encontrados %.', v_n;
    END IF;
    IF v_t_foid IS NOT TRUE THEN
        RAISE EXCEPTION 'CONFIRM_V3_GUARD2224_TGFOID: o trigger não aponta para a função canônica do guard.';
    END IF;
    IF v_t_type IS NOT TRUE THEN
        RAISE EXCEPTION 'CONFIRM_V3_GUARD2224_TGTYPE: tgtype diferente de 23 (BEFORE ROW INSERT OR UPDATE).';
    END IF;
    IF v_t_enabled IS NOT TRUE THEN
        RAISE EXCEPTION 'CONFIRM_V3_GUARD2224_DISABLED: trigger desabilitado (tgenabled fora de O/A).';
    END IF;
    IF v_t_intern IS NOT FALSE THEN
        RAISE EXCEPTION 'CONFIRM_V3_GUARD2224_INTERNAL: trigger inesperadamente interno.';
    END IF;

    RAISE NOTICE 'CONFIRM_V3 PASSO 1 OK — alvo, owner, ACL PRE, writer6+writer7, contrato writer7 e guard 2224 provados.';
END $pre2218$;

-- ---------------------------------------------------------------- PASSO 2 ---
CREATE OR REPLACE FUNCTION public.admin_confirm_catalog_variant_import(
    p_job_id UUID,
    p_row_ids UUID[] DEFAULT NULL
)
RETURNS TABLE (
    inserted_count INTEGER,
    unchanged_count INTEGER,
    failed_count INTEGER,
    pending_count INTEGER,
    job_status TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    -- Teto de lote por chamada (Query 2164). INALTERADO.
    c_max_rows CONSTANT INTEGER := 1000;

    v_job public.catalog_variant_import_job%ROWTYPE;
    v_row public.catalog_variant_import_row%ROWTYPE;
    v_existing_variant public.card_variant%ROWTYPE;
    v_variant_type_id UUID;
    v_printing_profile_id UUID;
    v_printing_key_type TEXT;
    -- v3.0 — EIXO 3.
    v_edition_context_profile_id UUID;
    v_edition_context_key_type TEXT;
    v_race_variant_id UUID;
    -- v3.0 / v1.1 — discriminação do unique_violation.
    v_writer_attempted BOOLEAN;
    v_uv_schema TEXT;
    v_uv_table TEXT;
    v_uv_constraint TEXT;
    v_error_message TEXT;
    v_match_status TEXT;
    v_result_variant_id UUID;
    v_next_order INTEGER;
    v_pending_rows INTEGER;
    v_failed_rows INTEGER;
    v_decision_pending_rows INTEGER;
    v_final_status TEXT;
    v_card_set_name TEXT;
    v_card_set_code TEXT;
    v_id_count INTEGER;
    v_effective_row_ids UUID[];
BEGIN
    -- GUARD 1 — AUTORIZACAO.
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_VARIANT_IMPORT_FORBIDDEN: apenas administradores podem confirmar uma importação de variantes.';
    END IF;

    -- GUARD 2 — p_job_id obrigatorio.
    IF p_job_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_VARIANT_IMPORT_MISSING_JOB: p_job_id é obrigatório.';
    END IF;

    -- GUARD 3 — FORMA E TETO DE p_row_ids (Query 2164). Validacao pura
    -- de payload: nenhum acesso a tabela, nenhum lock ainda tomado.
    IF p_row_ids IS NOT NULL THEN
        IF array_ndims(p_row_ids) <> 1 THEN
            RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_VARIANT_IMPORT_INVALID_ARRAY_SHAPE: p_row_ids deve ser um array de uma única dimensão (recebido: % dimensões).', array_ndims(p_row_ids);
        END IF;

        v_id_count := cardinality(p_row_ids);

        IF v_id_count = 0 THEN
            RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_VARIANT_IMPORT_EMPTY_ROW_IDS: p_row_ids veio vazio. Envie NULL para confirmar todas as linhas elegíveis, ou pelo menos um id.';
        END IF;

        IF v_id_count > c_max_rows THEN
            RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_VARIANT_IMPORT_TOO_MANY_ROWS: p_row_ids tem % ids, acima do teto de % por chamada. Divida em lotes menores.', v_id_count, c_max_rows;
        END IF;
    END IF;

    -- GUARD 4/5/6 — job existe, está em estado confirmável, e fica
    -- travado para o resto da transação.
    SELECT * INTO v_job FROM public.catalog_variant_import_job WHERE id = p_job_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_VARIANT_IMPORT_JOB_NOT_FOUND: nenhum job encontrado para o id informado (%).', p_job_id;
    END IF;

    -- FRONTEIRA OPERACIONAL. Job terminal (CANCELLED/COMPLETED/
    -- COMPLETED_WITH_ERRORS/FAILED) nunca chega ao writer por aqui —
    -- e esta versao NAO afrouxa a regra.
    IF v_job.status NOT IN ('STAGED', 'CONFIRMING') THEN
        RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_VARIANT_IMPORT_INVALID_STATUS: o job está em % — só é possível confirmar a partir de STAGED ou CONFIRMING.', v_job.status;
    END IF;

    SELECT name, code INTO v_card_set_name, v_card_set_code
    FROM public.card_set WHERE id = v_job.card_set_id;

    -- GUARD 7 — CONJUNTO EFETIVO CONGELADO (Query 2164). Elimina o
    -- TOCTOU: o que foi contado é exatamente o que será processado.
    IF p_row_ids IS NULL THEN
        v_effective_row_ids := ARRAY(
            SELECT r.id
            FROM public.catalog_variant_import_row r
            WHERE r.job_id = p_job_id
              AND r.persistence_status = 'PENDING'
              AND r.decision_status IN ('APPROVED', 'SKIPPED')
            ORDER BY r.created_at, r.id
            LIMIT c_max_rows + 1
        );

        IF cardinality(v_effective_row_ids) > c_max_rows THEN
            RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_VARIANT_IMPORT_TOO_MANY_ROWS: o job tem mais de % linhas elegíveis. Informe p_row_ids em lotes menores.', c_max_rows;
        END IF;
    ELSE
        v_effective_row_ids := p_row_ids;
    END IF;

    -- =====================================================================
    -- v3.0 — LOCK DETERMINÍSTICO DAS CARDS DO LOTE
    -- ---------------------------------------------------------------------
    -- Travar aqui, em ORDER BY id, resolve duas coisas de uma vez:
    --   1. serializa matching + alocação de variant_order por Card, que é
    --      o par que realmente compete;
    --   2. fixa a ORDEM de aquisição. Dois lotes concorrentes cujas Cards
    --      se cruzam adquirem na mesma sequência — deadlock por ordem
    --      invertida deixa de ser possível por este caminho.
    -- Travar antes do loop (e não dentro) é o que dá a ordem global; dentro
    -- do loop a ordem seria a de created_at, que difere entre lotes.
    -- =====================================================================
    PERFORM 1
       FROM public.card c
      WHERE c.id IN (
            SELECT DISTINCT r.card_id
              FROM public.catalog_variant_import_row r
             WHERE r.job_id = p_job_id
               AND r.id = ANY(v_effective_row_ids))
      ORDER BY c.id
        FOR UPDATE;

    IF v_job.status = 'STAGED' THEN
        UPDATE public.catalog_variant_import_job SET status = 'CONFIRMING' WHERE id = p_job_id;
    END IF;

    FOR v_row IN
        SELECT r.*
        FROM public.catalog_variant_import_row r
        WHERE r.job_id = p_job_id
          AND r.persistence_status = 'PENDING'
          AND r.decision_status IN ('APPROVED', 'SKIPPED')
          AND r.id = ANY(v_effective_row_ids)
        ORDER BY r.created_at
        FOR UPDATE OF r
    LOOP
        -- v1.1 — ESTADO POR ITERAÇÃO. Nenhuma identidade da row anterior
        -- sobrevive: o handler nunca lê eixo "herdado".
        v_writer_attempted := false;
        v_variant_type_id := NULL;
        v_printing_profile_id := NULL;
        v_edition_context_profile_id := NULL;
        v_race_variant_id := NULL;

        BEGIN
            IF v_row.decision_status = 'SKIPPED' THEN
                UPDATE public.catalog_variant_import_row
                    SET persistence_status = 'UNCHANGED'
                    WHERE id = v_row.id;
                CONTINUE;
            END IF;

            -- decision_status = 'APPROVED' a partir daqui.
            -- Revalidação defensiva: o estado pode, em tese, ter mudado
            -- entre a decisão (Query 2144) e esta confirmação.
            IF v_row.validation_status <> 'VALID' THEN
                RAISE EXCEPTION 'NEEDS_REVIEW_CANNOT_BE_CONFIRMED: linha sem card_variant_type resolvido não pode ser confirmada.';
            END IF;

            v_variant_type_id := NULLIF(v_row.normalized_data->>'variant_type_id', '')::UUID;
            IF v_variant_type_id IS NULL THEN
                RAISE EXCEPTION 'MISSING_VARIANT_TYPE_ID: normalized_data não contém variant_type_id resolvido.';
            END IF;

            -- EIXO IMPRESSÃO — contrato TRI-ESTADO.
            --
            -- jsonb_typeof distingue os tres estados; `->>` nao:
            --   chave ausente -> SQL NULL   (Impressao NAO resolvida)
            --   JSON null     -> 'null'     (resolvido SEM perfil)
            --   string        -> 'string'   (resolvido COM perfil)
            v_printing_key_type := jsonb_typeof(v_row.normalized_data -> 'printing_profile_id');

            IF v_printing_key_type IS NULL THEN
                RAISE EXCEPTION 'PRINTING_NOT_RESOLVED: normalized_data não contém a chave printing_profile_id. Toda linha VALID precisa da chave — resolva o mapeamento de Impressão ou reprocesse a importação.';
            ELSIF v_printing_key_type = 'null' THEN
                v_printing_profile_id := NULL;      -- resolvido SEM perfil, explícito
            ELSIF v_printing_key_type = 'string' THEN
                v_printing_profile_id := (v_row.normalized_data->>'printing_profile_id')::UUID;
            ELSE
                RAISE EXCEPTION 'PRINTING_PROFILE_ID_INVALID_SHAPE: printing_profile_id tem tipo JSON % — esperado null ou string UUID.', v_printing_key_type;
            END IF;

            -- =============================================================
            -- v3.0 — EIXO CONTEXTO DE EDIÇÃO — MESMO contrato TRI-ESTADO.
            -- -------------------------------------------------------------
            -- Simetria deliberada com Impressão: mesma leitura por
            -- jsonb_typeof, mesmos três estados, mesma recusa fail-closed.
            -- Chave ausente é IMPOSSÍVEL para uma linha operacional VALID
            -- (guard trg_cvir_normalized_shape, Query 2214) e só seria
            -- alcançável por escrita direta fora do pipeline. Confirmar
            -- criaria uma Variant sem contexto que talvez devesse ter.
            -- =============================================================
            v_edition_context_key_type := jsonb_typeof(v_row.normalized_data -> 'edition_context_profile_id');

            IF v_edition_context_key_type IS NULL THEN
                RAISE EXCEPTION 'EDITION_CONTEXT_NOT_RESOLVED: normalized_data não contém a chave edition_context_profile_id. Toda linha VALID precisa da chave — resolva o eixo pelo routing (internal.resolve_variant_row_axes) ou reprocesse a importação.';
            ELSIF v_edition_context_key_type = 'null' THEN
                v_edition_context_profile_id := NULL;   -- resolvido SEM contexto
            ELSIF v_edition_context_key_type = 'string' THEN
                v_edition_context_profile_id := (v_row.normalized_data->>'edition_context_profile_id')::UUID;
            ELSE
                RAISE EXCEPTION 'EDITION_CONTEXT_PROFILE_ID_INVALID_SHAPE: edition_context_profile_id tem tipo JSON % — esperado null ou string UUID.', v_edition_context_key_type;
            END IF;

            -- =============================================================
            -- MATCHING QUÁDRUPLO. match_status recalculado contra o
            -- catálogo real — nunca herdado. IS NOT DISTINCT FROM nos DOIS
            -- eixos nuláveis, porque NULL faz parte da identidade:
            -- "sem tiragem" e "sem contexto" são VALORES, não desconhecidos.
            -- Roda DEPOIS do lock da Card — é o recheck da corrida.
            -- =============================================================
            SELECT cv.* INTO v_existing_variant
            FROM public.card_variant cv
            WHERE cv.card_id = v_row.card_id
              AND cv.variant_type_id = v_variant_type_id
              AND cv.printing_profile_id        IS NOT DISTINCT FROM v_printing_profile_id
              AND cv.edition_context_profile_id IS NOT DISTINCT FROM v_edition_context_profile_id
            LIMIT 1;

            IF v_existing_variant.id IS NULL THEN
                v_match_status := 'NEW';
            ELSE
                v_match_status := 'MATCHED';
            END IF;

            IF v_match_status = 'MATCHED' THEN
                -- Já existe: nenhuma escrita. Nunca sobrescreve silenciosamente.
                UPDATE public.catalog_variant_import_row
                    SET match_status = v_match_status,
                        persistence_status = 'UNCHANGED',
                        matched_variant_id = v_existing_variant.id,
                        resulting_variant_id = v_existing_variant.id,
                        error_detail = NULL
                    WHERE id = v_row.id;
                CONTINUE;
            END IF;

            -- NEW: variant_order é sempre o próximo inteiro livre para o
            -- card_id, calculado só a partir do que já existe em
            -- card_variant — nunca lido da fonte. is_default nunca é
            -- informado (nasce FALSE pelo default da coluna).
            SELECT COALESCE(MAX(variant_order), 0) + 1 INTO v_next_order
            FROM public.card_variant
            WHERE card_id = v_row.card_id;

            -- Writer com SETE argumentos (Query 2217). Identidade completa
            -- já resolvida — o writer não infere nada.
            -- v1.1 — a flag fica TRUE somente enquanto o writer executa:
            -- se ele lançar exceção, o handler a vê TRUE; se qualquer
            -- statement POSTERIOR falhar, ela já voltou a FALSE.
            v_writer_attempted := true;
            v_result_variant_id := internal.write_card_variant(
                'CREATE', NULL, v_row.card_id, v_variant_type_id, v_next_order,
                v_printing_profile_id, v_edition_context_profile_id
            );
            v_writer_attempted := false;

            UPDATE public.catalog_variant_import_row
                SET match_status = v_match_status,
                    persistence_status = 'INSERTED',
                    matched_variant_id = NULL,
                    resulting_variant_id = v_result_variant_id,
                    error_detail = NULL
                WHERE id = v_row.id;

        -- =================================================================
        -- v3.0 / v1.1 — HANDLER ESPECÍFICO, ANTES do genérico.
        -- Um 23505 só vira "corrida benigna" com as quatro condições
        -- A-D do cabeçalho. Qualquer outro 23505 é FAILED fail-closed,
        -- com schema/tabela/constraint/mensagem no error_detail.
        -- =================================================================
        EXCEPTION
            WHEN unique_violation THEN
                GET STACKED DIAGNOSTICS
                    v_uv_schema     = SCHEMA_NAME,
                    v_uv_table      = TABLE_NAME,
                    v_uv_constraint = CONSTRAINT_NAME,
                    v_error_message = MESSAGE_TEXT;

                -- v_race_variant_id é NULL desde o topo da iteração; só a
                -- releitura abaixo, sob A+B+C, pode preenchê-lo.
                IF v_writer_attempted IS TRUE
                   AND v_uv_schema = 'public'
                   AND v_uv_table = 'card_variant'
                   AND v_uv_constraint IN ('uq_card_variant_card_type_no_printing',
                                           'uq_card_variant_card_type_printing',
                                           'uq_card_variant_identity') THEN
                    -- D — releitura pela MESMA identidade de 4 componentes.
                    SELECT cv.id INTO v_race_variant_id
                    FROM public.card_variant cv
                    WHERE cv.card_id = v_row.card_id
                      AND cv.variant_type_id = v_variant_type_id
                      AND cv.printing_profile_id        IS NOT DISTINCT FROM v_printing_profile_id
                      AND cv.edition_context_profile_id IS NOT DISTINCT FROM v_edition_context_profile_id
                    LIMIT 1;
                END IF;

                IF v_race_variant_id IS NOT NULL THEN
                    -- CORRIDA BENIGNA (defensivo — ver SERIALIZAÇÃO no
                    -- cabeçalho). Resultado idêntico ao caminho MATCHED
                    -- normal — indistinguível para a UI, de propósito.
                    UPDATE public.catalog_variant_import_row
                        SET match_status = 'MATCHED',
                            persistence_status = 'UNCHANGED',
                            matched_variant_id = v_race_variant_id,
                            resulting_variant_id = v_race_variant_id,
                            error_detail = NULL
                        WHERE id = v_row.id;
                ELSE
                    -- FAIL-CLOSED. Inclui: violação fora do writer; tabela
                    -- ou constraint fora do conjunto de identidade (ex.:
                    -- uq_card_variant_card_order); e, antes da 2209,
                    -- colisão em UNIQUE antiga por Variants que diferem só
                    -- em Contexto de Edição (releitura quádrupla vazia).
                    UPDATE public.catalog_variant_import_row
                        SET persistence_status = 'FAILED',
                            error_detail = 'CARD_VARIANT_UNIQUE_VIOLATION_UNRESOLVED: violação de unicidade na Card '
                                           || v_row.card_id
                                           || ' não classificável como corrida benigna pela identidade de 4 componentes.'
                                           || ' writer_attempted=' || COALESCE(v_writer_attempted::TEXT, 'null')
                                           || ' schema=' || COALESCE(v_uv_schema, '(n/d)')
                                           || ' table=' || COALESCE(v_uv_table, '(n/d)')
                                           || ' constraint=' || COALESCE(v_uv_constraint, '(n/d)')
                                           || ' Detalhe: ' || COALESCE(v_error_message, '(n/d)')
                        WHERE id = v_row.id;
                END IF;

            WHEN OTHERS THEN
                -- Rede final: uma linha com defeito não derruba o lote.
                -- Inalterado frente à canônica.
                GET STACKED DIAGNOSTICS v_error_message = MESSAGE_TEXT;
                UPDATE public.catalog_variant_import_row
                    SET persistence_status = 'FAILED', error_detail = v_error_message
                    WHERE id = v_row.id;
        END;
    END LOOP;

    -- Recalcula os contadores do job inteiramente por agregação. INALTERADO.
    UPDATE public.catalog_variant_import_job j
        SET total_rows = (SELECT COUNT(*) FROM public.catalog_variant_import_row WHERE job_id = j.id),
            valid_rows = (SELECT COUNT(*) FROM public.catalog_variant_import_row WHERE job_id = j.id AND validation_status = 'VALID'),
            rejected_rows = (SELECT COUNT(*) FROM public.catalog_variant_import_row WHERE job_id = j.id AND decision_status = 'REJECTED'),
            inserted_rows = (SELECT COUNT(*) FROM public.catalog_variant_import_row WHERE job_id = j.id AND persistence_status = 'INSERTED'),
            unchanged_rows = (SELECT COUNT(*) FROM public.catalog_variant_import_row WHERE job_id = j.id AND persistence_status = 'UNCHANGED'),
            skipped_rows = (SELECT COUNT(*) FROM public.catalog_variant_import_row WHERE job_id = j.id AND decision_status = 'SKIPPED'),
            failed_rows = (SELECT COUNT(*) FROM public.catalog_variant_import_row WHERE job_id = j.id AND persistence_status = 'FAILED')
        WHERE j.id = p_job_id;

    SELECT COUNT(*)
    INTO v_decision_pending_rows
    FROM public.catalog_variant_import_row
    WHERE job_id = p_job_id
      AND decision_status = 'PENDING';

    SELECT
        COUNT(*) FILTER (WHERE persistence_status = 'PENDING'),
        COUNT(*) FILTER (WHERE persistence_status = 'FAILED')
    INTO v_pending_rows, v_failed_rows
    FROM public.catalog_variant_import_row
    WHERE job_id = p_job_id
      AND decision_status IN ('APPROVED', 'SKIPPED');

    IF v_decision_pending_rows > 0 THEN
        v_final_status := 'STAGED';
    ELSIF v_pending_rows > 0 THEN
        v_final_status := 'CONFIRMING';
    ELSIF v_failed_rows > 0 THEN
        v_final_status := 'COMPLETED_WITH_ERRORS';
    ELSE
        v_final_status := 'COMPLETED';
    END IF;

    UPDATE public.catalog_variant_import_job SET status = v_final_status WHERE id = p_job_id;

    IF v_final_status IN ('COMPLETED', 'COMPLETED_WITH_ERRORS') THEN
        INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
            VALUES (auth.uid(), 'CARD_VARIANT_IMPORT_CONFIRMED', 'CATALOG_VARIANT_IMPORT_JOB', p_job_id,
                    jsonb_build_object(
                        'card_set_id', v_job.card_set_id,
                        'card_set_name', v_card_set_name,
                        'card_set_code', v_card_set_code,
                        'final_status', v_final_status
                    ));
    END IF;

    RETURN QUERY
        SELECT j.inserted_rows, j.unchanged_rows, j.failed_rows, v_pending_rows, j.status
        FROM public.catalog_variant_import_job j
        WHERE j.id = p_job_id;
END;
$$;

-- Ambos idempotentes. CREATE OR REPLACE já preserva owner e ACL; reafirmar
-- aqui mantém o artefato fiel ao contrato da 2145 (REVOKE PUBLIC + GRANT
-- authenticated) e ao contrato provado no PASSO 1.
REVOKE ALL ON FUNCTION public.admin_confirm_catalog_variant_import(UUID, UUID[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_confirm_catalog_variant_import(UUID, UUID[]) TO authenticated;

-- ---------------------------------------------------------------- PASSO 3 ---
-- POSTCHECK. Autoridades: pg_catalog + hash do corpo. Nenhum LIKE/position
-- como gate. Qualquer divergência aborta a transação inteira e a função
-- anterior permanece ativa.
DO $post2218$
DECLARE
    c_sig_confirm CONSTANT TEXT := 'public.admin_confirm_catalog_variant_import(uuid,uuid[])';
    c_sig6        CONSTANT TEXT := 'internal.write_card_variant(text,uuid,uuid,uuid,integer,uuid)';
    c_sig7        CONSTANT TEXT := 'internal.write_card_variant(text,uuid,uuid,uuid,integer,uuid,uuid)';
    c_sig_guard   CONSTANT TEXT := 'internal.enforce_card_variant_edition_context_profile_game()';
    -- Hash MD5 do corpo (texto entre AS $$ e $$ do PASSO 2), em UTF-8,
    -- terminadores LF. Ver "MÉTODO DO HASH" no rodapé.
    c_body_md5_lf CONSTANT TEXT := 'b83f7708ca2b7498b753b394d768f66e';
    v_confirm   OID;
    v_guard     OID;
    v_owner     OID;
    v_auth      OID;
    v_cur       OID;
    v_n         INT;
    v_p         RECORD;
    v_ok        BOOLEAN;
    v_own_tem   BOOLEAN;
    v_auth_tem  BOOLEAN;
    v_estranho  INT;
    v_quem      TEXT;
    v_auth_rows INT;
    v_auth_go   BOOLEAN;
    v_auth_gtor BOOLEAN;
    v_raw_md5   TEXT;
    v_norm_md5  TEXT;
    v_raw_len   INT;
    v_norm_len  INT;
BEGIN
    -- Q1 — assinatura exata e unicidade.
    v_confirm := to_regprocedure(c_sig_confirm)::OID;
    IF v_confirm IS NULL THEN
        RAISE EXCEPTION 'CONFIRM_V3_POST_MISSING: % não existe.', c_sig_confirm;
    END IF;
    SELECT count(*) INTO v_n
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'admin_confirm_catalog_variant_import';
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'CONFIRM_V3_POST_OVERLOADED: esperada 1 função, encontradas %.', v_n;
    END IF;

    SELECT p.* INTO v_p FROM pg_proc p WHERE p.oid = v_confirm;
    v_owner := v_p.proowner;

    -- Q2 — linguagem, SECDEF, search_path por IGUALDADE.
    IF v_p.prolang <> (SELECT l.oid FROM pg_language l WHERE l.lanname = 'plpgsql') THEN
        RAISE EXCEPTION 'CONFIRM_V3_POST_LANG: linguagem diferente de plpgsql.';
    END IF;
    IF v_p.prosecdef IS NOT TRUE THEN
        RAISE EXCEPTION 'CONFIRM_V3_POST_NOT_SECDEF.';
    END IF;
    IF v_p.proconfig IS DISTINCT FROM ARRAY['search_path=""']::TEXT[] THEN
        RAISE EXCEPTION 'CONFIRM_V3_POST_SEARCH_PATH: proconfig=%.', COALESCE(v_p.proconfig::TEXT, '(NULO)');
    END IF;

    -- Q3 — argumentos de entrada e DEFAULT.
    IF v_p.pronargs <> 2 OR v_p.pronargdefaults <> 1 THEN
        RAISE EXCEPTION 'CONFIRM_V3_POST_ARGS: pronargs=% pronargdefaults=% (esperado 2/1).', v_p.pronargs, v_p.pronargdefaults;
    END IF;
    IF pg_get_expr(v_p.proargdefaults, 0) IS DISTINCT FROM 'NULL::uuid[]' THEN
        RAISE EXCEPTION 'CONFIRM_V3_POST_DEFAULT: DEFAULT de p_row_ids = % (esperado NULL::uuid[]).', COALESCE(pg_get_expr(v_p.proargdefaults, 0), '(nenhum)');
    END IF;

    -- Q4 — RETURNS TABLE, prova ESTRUTURAL (tipos, modos, nomes, retset).
    -- Arrays normalizados por ordinalidade: independe de limite inferior.
    IF v_p.proretset IS NOT TRUE OR v_p.prorettype <> 'record'::REGTYPE::OID THEN
        RAISE EXCEPTION 'CONFIRM_V3_POST_RETURNS: proretset=% prorettype=% (esperado true/record).', v_p.proretset, v_p.prorettype::REGTYPE;
    END IF;
    v_ok := ARRAY(SELECT t FROM unnest(v_p.proallargtypes) WITH ORDINALITY AS u(t, o) ORDER BY o)
            = ARRAY['uuid', 'uuid[]', 'integer', 'integer', 'integer', 'integer', 'text']::REGTYPE[]::OID[];
    IF v_ok IS NOT TRUE THEN
        RAISE EXCEPTION 'CONFIRM_V3_POST_ALLARGTYPES: %.', COALESCE(v_p.proallargtypes::REGTYPE[]::TEXT, '(NULO)');
    END IF;
    v_ok := ARRAY(SELECT m::TEXT FROM unnest(v_p.proargmodes) WITH ORDINALITY AS u(m, o) ORDER BY o)
            = ARRAY['i', 'i', 't', 't', 't', 't', 't'];
    IF v_ok IS NOT TRUE THEN
        RAISE EXCEPTION 'CONFIRM_V3_POST_ARGMODES: %.', COALESCE(v_p.proargmodes::TEXT, '(NULO)');
    END IF;
    v_ok := ARRAY(SELECT a FROM unnest(v_p.proargnames) WITH ORDINALITY AS u(a, o) ORDER BY o)
            = ARRAY['p_job_id', 'p_row_ids', 'inserted_count', 'unchanged_count',
                    'failed_count', 'pending_count', 'job_status'];
    IF v_ok IS NOT TRUE THEN
        RAISE EXCEPTION 'CONFIRM_V3_POST_ARGNAMES: %.', COALESCE(v_p.proargnames::TEXT, '(NULO)');
    END IF;
    -- Diagnóstico apenas (não é autoridade):
    RAISE NOTICE 'CONFIRM_V3 diag: pg_get_function_result = %', pg_get_function_result(v_confirm);

    -- Q5 — owner preservado: continua sendo o role que o PASSO 1 provou ser
    -- current_user, e o mesmo owner do writer7.
    SELECT r.oid INTO v_cur FROM pg_roles r WHERE r.rolname = current_user;
    IF v_owner IS DISTINCT FROM v_cur THEN
        RAISE EXCEPTION 'CONFIRM_V3_POST_OWNER: owner=% current_user=%.', pg_get_userbyid(v_owner), current_user;
    END IF;
    IF v_owner IS DISTINCT FROM (SELECT p.proowner FROM pg_proc p WHERE p.oid = to_regprocedure(c_sig7)::OID) THEN
        RAISE EXCEPTION 'CONFIRM_V3_POST_OWNER_WRITER7: owner(admin_confirm) difere de owner(writer7).';
    END IF;

    -- Q6 — ACL EXATA, MESMO contrato A-G do PRE (PASSO 1, P1.4).
    v_auth := to_regrole('authenticated')::OID;
    IF v_p.proacl IS NULL THEN
        RAISE EXCEPTION 'CONFIRM_V3_POST_ACL_DEFAULT: proacl NULL.';
    END IF;
    IF v_auth IS NULL THEN
        RAISE EXCEPTION 'CONFIRM_V3_POST_ROLE_MISSING: role authenticated inexistente.';
    END IF;
    SELECT COALESCE(bool_or(a.grantee = v_owner AND a.privilege_type = 'EXECUTE'), false),
           COALESCE(bool_or(a.grantee = v_auth  AND a.privilege_type = 'EXECUTE'), false),
           count(*) FILTER (WHERE a.grantee = v_auth AND a.privilege_type = 'EXECUTE'),
           COALESCE(bool_or(a.is_grantable) FILTER (WHERE a.grantee = v_auth), false),
           COALESCE(bool_and(a.grantor = v_owner) FILTER (WHERE a.grantee = v_auth AND a.privilege_type = 'EXECUTE'), false),
           count(*) FILTER (WHERE a.grantee NOT IN (v_owner, v_auth)),
           COALESCE(string_agg(DISTINCT CASE WHEN a.grantee = 0 THEN 'PUBLIC'
                                             ELSE pg_get_userbyid(a.grantee) END
                                 || ':' || a.privilege_type
                                 || CASE WHEN a.is_grantable THEN '*' ELSE '' END
                                 || '/' || pg_get_userbyid(a.grantor), ', '), '(ninguem)')
      INTO v_own_tem, v_auth_tem, v_auth_rows, v_auth_go, v_auth_gtor, v_estranho, v_quem
      FROM aclexplode(v_p.proacl) a;
    IF NOT v_own_tem OR NOT v_auth_tem OR v_auth_rows <> 1 OR v_auth_go
       OR NOT v_auth_gtor OR v_estranho <> 0 THEN
        RAISE EXCEPTION 'CONFIRM_V3_POST_ACL_CONTRACT: esperado {owner % com EXECUTE; authenticated com EXATAMENTE 1 entrada EXECUTE, sem GRANT OPTION, grantor = owner} e nenhum outro grantee (PUBLIC incluso). Obtido: % · entradas authenticated=% · grant_option=% · grantor_ok=% · estranhos=%.',
            pg_get_userbyid(v_owner), v_quem, v_auth_rows, v_auth_go, v_auth_gtor, v_estranho;
    END IF;

    -- Q7 — CORPO: hash do prosrc normalizado por EOL (CRLF → LF somente).
    -- raw e normalized são DIAGNÓSTICO; a autoridade é normalized = esperado.
    v_raw_md5  := md5(v_p.prosrc);
    v_norm_md5 := md5(replace(v_p.prosrc, E'\r\n', E'\n'));
    v_raw_len  := octet_length(v_p.prosrc);
    v_norm_len := octet_length(replace(v_p.prosrc, E'\r\n', E'\n'));
    RAISE NOTICE 'CONFIRM_V3 diag: raw_md5=% raw_bytes=% norm_md5=% norm_bytes=% esperado=%',
        v_raw_md5, v_raw_len, v_norm_md5, v_norm_len, c_body_md5_lf;
    IF v_norm_md5 IS DISTINCT FROM c_body_md5_lf THEN
        RAISE EXCEPTION 'CONFIRM_V3_POST_BODY_HASH: corpo instalado difere do auditado. norm_md5=% (esperado %) · raw_md5=% · raw_bytes=% · norm_bytes=%.',
            v_norm_md5, c_body_md5_lf, v_raw_md5, v_raw_len, v_norm_len;
    END IF;

    -- Q8 — writer6 + writer7 continuam presentes (SWITCH não contrai).
    IF to_regprocedure(c_sig6) IS NULL OR to_regprocedure(c_sig7) IS NULL THEN
        RAISE EXCEPTION 'CONFIRM_V3_POST_WRITERS: writer6=% writer7=% (ambos devem existir até a 2223).',
            to_regprocedure(c_sig6), to_regprocedure(c_sig7);
    END IF;
    SELECT count(*) INTO v_n
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'internal' AND p.proname = 'write_card_variant';
    IF v_n <> 2 THEN
        RAISE EXCEPTION 'CONFIRM_V3_POST_WRITER_OVERLOADS: esperadas 2, encontradas %.', v_n;
    END IF;

    -- Q9 — pré-requisito 2224 íntegro.
    v_guard := to_regprocedure(c_sig_guard)::OID;
    SELECT count(*) INTO v_n
      FROM pg_trigger t
     WHERE t.tgrelid = to_regclass('public.card_variant')
       AND t.tgname = 'trg_card_variant_edition_context_profile_game'
       AND NOT t.tgisinternal
       AND t.tgfoid = v_guard
       AND t.tgtype = 23
       AND t.tgenabled IN ('O', 'A');
    IF v_guard IS NULL OR v_n <> 1 THEN
        RAISE EXCEPTION 'CONFIRM_V3_POST_GUARD2224: guard same-Game do 3º eixo ausente ou alterado (função=%, triggers conformes=%).', v_guard, v_n;
    END IF;

    RAISE NOTICE 'admin_confirm_catalog_variant_import v3.0 OK — POSTCHECK Q1-Q9 (catálogo + hash do corpo).';
END $post2218$;

-- ============================================================================
-- PERFORMANCE
--   * Um único lock de Cards por chamada, set-based, em vez de N locks
--     dentro do loop. Menos round-trips e janela de lock mais curta.
--   * Nenhuma resolução de axes acontece aqui: o confirm LÊ normalized_data,
--     que já foi resolvido a montante por 2211/2219. Zero N+1 de trait.
--   * MATCHING QUÁDRUPLO — estado INTERMEDIÁRIO (2209 NÃO executada):
--     uq_card_variant_identity AINDA NÃO EXISTE. Os índices disponíveis que
--     começam por card_id são ix_card_variant_card_id e
--     uq_card_variant_card_order (card_id, variant_order); as UNIQUE
--     parciais antigas (uq_card_variant_card_type_no_printing /
--     _printing) seguem ativas. O predicado é o mesmo que a função LIVE já
--     usa para Impressão, acrescido do 3º eixo. NENHUM plano específico é
--     prometido aqui: o LIVE PRECHECK deve provar o plano do matching, do
--     MAX(variant_order) e do lock de Cards com EXPLAIN READ-ONLY (sem
--     ANALYZE). Performance continua requisito obrigatório.
--   * Teto de 1000 rows por chamada preservado: a janela de lock continua
--     limitada por construção.
--
-- MÉTODO DO HASH (c_body_md5_lf)
--   1. Ler este arquivo como UTF-8.
--   2. Localizar a 1ª ocorrência de 'CREATE OR REPLACE FUNCTION'; a partir
--      dela, a 1ª de 'AS $$'; o corpo começa no caractere seguinte.
--   3. O corpo termina no caractere '\n' imediatamente anterior à 1ª linha
--      '$$;' posterior (esse '\n' INCLUSO). É exatamente o prosrc.
--   4. Normalizar CRLF → LF (somente o par; CR isolado NÃO é removido).
--   5. MD5 dos bytes UTF-8.
--   Qualquer mudança no corpo exige recalcular e atualizar o hash.
--
-- ARMADO PARA ROLLOUT (ROLLOUT-EXECUTION-READINESS-01). Terminador COMMIT.
-- A protecao contra execucao prematura e GOVERNANCA (autorizacao de
-- Fabricio + ordem de batches), nao o terminador — mesma decisao ja aceita
-- em R1 para 2203-2211. Executar por MCP/CLI, não pelo Dashboard Query
-- Editor (STD-001 v1.45).
-- ============================================================================
COMMIT;
