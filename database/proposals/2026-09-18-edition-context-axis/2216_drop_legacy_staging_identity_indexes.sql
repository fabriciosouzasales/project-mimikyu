-- ============================================================================
-- Query 2216 — REMOÇÃO das identidades antigas de catalog_variant_import_row
-- Status: PROPOSTA — NÃO EXECUTADA · Versão 4.1
--
-- v4.1 (BATCH11-2216-V4.1-CORRECTION-01, 2026-09-26) — tres achados da
-- BATCH11-2216-V4.0-READINESS-RE-AUDIT-01, e somente eles:
--   R1  OID fixo removido. A funcao de token e resolvida EXCLUSIVAMENTE por
--       to_regprocedure('internal.axis_identity_token(jsonb,text)'). O OID
--       observado no LIVE (192898) e apenas observacao, nao autoridade.
--   R2  Canonicalizacao independente de search_path. pg_get_indexdef /
--       pg_get_expr renderizam a funcao como internal.axis_identity_token(...)
--       quando ela NAO esta visivel no search_path e como
--       axis_identity_token(...) quando esta — o estado fisico e o mesmo.
--       Os literais canonicos (forma nao-visivel) sao adaptados ao contexto
--       por pg_function_is_visible(v_fn); pelo mesmo principio, o tipo
--       pg_catalog.text, pg_catalog.jsonb_typeof(jsonb) e os operadores
--       pg_catalog.->>/->(jsonb,text) tambem sao renderizados conforme a
--       visibilidade real. Sem set_config, sem search_path fixo.
--       A comparacao textual e defesa ADICIONAL. A autoridade estrutural
--       obrigatoria: as dependencias do indice novo para pg_proc sao
--       EXATAMENTE {v_fn} (1 linha, refobjid = v_fn, deptype 'n'). Assim a
--       adaptacao textual nao pode aceitar outra funcao.
--   R3  $residue2216$ prova, apos o ROLLBACK TO SAVEPOINT, zero residuo E a
--       topologia terminal COMPLETA (antigas ausentes; identidade nova e
--       funcao integralmente exatas; 8 indices, nomes exatos, 0 unhealthy;
--       UNIQUE exatamente {pkey, uq_cvir_row_identity}).
--   Qualificacao pg_catalog nos literais sensiveis a resolucao
--   ('pg_catalog.pg_class'/'pg_catalog.pg_proc'::regclass,
--   'pg_catalog.text'::regtype). Todas as demais decisoes da v4.0 preservadas.
--
-- v4.0 (BATCH11-2216-READINESS-CORRECTION-01, 2026-09-26) — hardening
-- fail-closed adjudicado sobre os achados C1–C8 da
-- BATCH11-2216-READINESS-AUDIT-01 (mesmo padrao da 2215 v1.1):
--   C1  PRE prova a assinatura fisica COMPLETA de public.uq_cvir_row_identity:
--       tabela exata, unique/valid/ready/live/immediate, 5/5 chaves,
--       pg_get_indexdef + predicado + expressoes exatos, chaves em ordem,
--       zero pg_constraint, dependencia 'n' para a funcao de token.
--   C1-BIS  internal.axis_identity_token(jsonb,text) exata: 1 overload,
--       IMMUTABLE, SECURITY INVOKER, owner postgres, search_path="",
--       LANGUAGE sql, RETURNS text, md5 LF 18682dce…. (O pino de OID da
--       v4.0 foi removido na v4.1 — ver R1.)
--       ACL NAO alterada. Gate de seguranca: USAGE do schema internal =
--       false para authenticated e anon (o EXECUTE concedido a authenticated
--       nao e exposicao efetiva sem USAGE do schema).
--   C2  Estado previo EXATO das duas antigas (definicao, predicado,
--       expressoes, chaves, flags, zero constraint por conindid, zero
--       dependente de ENTRADA deptype <> 'i') antes de qualquer DROP.
--       Divergencia = PRE_LEGACY_STAGING_STATE_DIVERGENT.
--   C3  DROP INDEX public.… RESTRICT, sem IF EXISTS, sem CASCADE, sem
--       CONCURRENTLY. Deliberadamente NAO idempotente: antiga ausente antes,
--       ou segunda execucao = STOP. Nunca NO-OP.
--   C4  Nenhum pg_class.relname global como autoridade: to_regclass
--       ('public.…') + indrelid da tabela exata. Homonimo em outro schema NAO
--       e blocker.
--   C5  Gate MID entre os DROPs (antiga 1 ausente; antiga 2, identidade nova
--       e funcao integralmente exatas).
--   C6  POST por TOPOLOGIA EXATA: 8 indices nomeados, todos saudaveis, UNIQUE
--       exatamente {pkey, uq_cvir_row_identity}, definicoes exatas. Removida a
--       autoridade generica "UNIQUE contendo job_id = 1".
--   C7  S4 deterministico: job TERMINAL por ORDER BY; tupla (job, card, vt)
--       comprovadamente ausente; IDs, marcador e Edition Context sentinelas
--       literais; α/β provados por RETURNING (exatamente 2 IDs) e pelos
--       tokens de identidade; γ negativo exige unique_violation reportada
--       por uq_cvir_row_identity (GET STACKED DIAGNOSTICS); prova de
--       residuo zero APOS o ROLLBACK TO SAVEPOINT.
--   C8  Dollar-tags exclusivas por bloco.
--   Fronteira JOB-AWARE da v3.0 PRESERVADA sem alteracao semantica.
--
-- v3.0 (OPERATIONAL-BOUNDARY-CORRECTION-01): a pre-condicao B passa a ser
-- JOB-AWARE. "VALID + PENDING" (row-local) atingia 415 rows de jobs
-- CANCELLED e zero operacionais — teria bloqueado o DROP por um universo
-- que e historico terminal.
--
-- v2.0 (BACKFILL-SEMANTICS-CORRECTION-01): a pre-condicao B deixou de ser
-- "toda VALID tem a chave" (regra global, semanticamente falsa) e passou a
-- ser o universo OPERACIONAL — VALID + PENDING. Rows terminais em HOLD
-- permanecem legitimamente com a chave AUSENTE, e isso NAO bloqueia o DROP.
-- CORREÇÃO 1 da GATE-A-FINAL-CORRECTION-01
--
-- O DEFEITO QUE ESTA QUERY CORRIGE
--   Os dois DROPs viviam COMENTADOS no corpo da Query 2210. Os índices
--   medidos no LIVE:
--
--     uq_cvir_job_card_type_no_printing
--         (job_id, card_id, (normalized_data->>'variant_type_id'))
--       WHERE variant_type_id IS NOT NULL
--         AND jsonb_typeof(normalized_data->'printing_profile_id') = 'null'
--     uq_cvir_job_card_type_printing
--         (job_id, card_id, (normalized_data->>'variant_type_id'),
--                           (normalized_data->>'printing_profile_id'))
--       WHERE variant_type_id IS NOT NULL
--         AND jsonb_typeof(normalized_data->'printing_profile_id') = 'string'
--
--   Nenhum dos dois considera edition_context_profile_id. Enquanto viverem,
--   duas rows do MESMO job, MESMA Card, MESMO acabamento e MESMA tiragem que
--   difiram SOMENTE em contexto de edição continuam colidindo — a própria
--   prova S4 do harness falharia. **2210 sem 2216 não entrega o eixo.**
--
-- POR QUE DERRUBAR NAO ABRE LACUNA DE IDENTIDADE
--   Universo da nova = normalized_data->>'variant_type_id' IS NOT NULL, que
--   CONTEM a uniao dos dois universos antigos (mesmo predicado de vt, sem o
--   filtro de tipo do printing). Nos eixos comuns a nova e equivalente:
--   token pp 'U:x' <-> ->>'printing_profile_id' = x; token 'N' <-> tipo
--   'null'. O unico relaxamento e o eixo Edition Context — o objetivo.
--   Rows com variant_type_id NULL estao fora dos indices novo E antigos
--   (nenhuma e VALID: o guard 2214 exige vt para VALID).
--
-- PRÉ-REQUISITO DE ORDEM (não negociável)
--   2210 (índice novo + shape permissivo)
--     -> 2212 (backfill)  -> 2832 (prova)  -> 2214 (guard estrito)
--     -> **2216 (esta)**
--   Remover os antigos ANTES do backfill não causaria erro, mas deixaria o
--   staging sem nenhuma proteção contra duplicata durante a janela em que o
--   índice novo ainda não cobre todas as rows (rows sem a chave produzem o
--   token 'A' e continuariam distintas entre si — ver 2210).
--
-- CANONICALIZACAO (v4.1)
--   Os literais de definicao abaixo estao na forma CANONICA (funcao, tipo,
--   jsonb_typeof e operadores nao-visiveis => qualificados; e a forma
--   renderizada quando search_path = "$user", public, extensions). Cada
--   bloco que compara texto calcula, UMA vez, a renderizacao esperada:
--     r_fn  : 'axis_identity_token'  se pg_function_is_visible(v_fn),
--             senao 'internal.axis_identity_token'
--     r_txt : 'text' se pg_type_is_visible(pg_catalog.text), senao 'pg_catalog.text'
--     r_jt  : 'jsonb_typeof' se visivel, senao 'pg_catalog.jsonb_typeof'
--     r_op2 : '->>' se visivel, senao 'OPERATOR(pg_catalog.->>)'
--     r_op1 : '->'  se visivel, senao 'OPERATOR(pg_catalog.->)'
--   e aplica replace() nos literais canonicos. A tabela e SEMPRE
--   renderizada qualificada (public.catalog_variant_import_row) por
--   pg_get_indexdef, independentemente do search_path.
--
-- LOCKS (sem CONCURRENTLY)
--   Cada DROP INDEX normal toma AccessExclusiveLock na tabela
--   public.catalog_variant_import_row e no indice removido, MANTIDO ATE O
--   COMMIT. Bloqueia leitura E escrita da tabela durante o restante da
--   transacao (gates POST, S4 e residuo inclusos). DROP INDEX CONCURRENTLY
--   nao roda em transacao e quebraria a atomicidade. Nenhuma alteracao de
--   lock_timeout aqui: a barreira operacional e o FREEZE + o LIVE PRECHECK
--   (concorrencia zero) imediatamente antes da execucao.
--
-- ATOMICIDADE
--   Um unico BEGIN ... COMMIT. Qualquer RAISE/erro apos o DROP 1 desfaz o
--   DROP 1; apos o DROP 2, desfaz os dois; erro no S4 ou na prova de residuo
--   aborta TUDO (inclusive os DROPs). O S4 roda em SAVEPOINT proprio, aberto
--   DEPOIS do POST, e e sempre desfeito por ROLLBACK TO SAVEPOINT; a prova de
--   residuo zero + topologia terminal roda depois disso, ainda na transacao.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------- PASSO 1 ---
-- PRE-CONDICAO FAIL-CLOSED: estado EXATO esperado apos 2210/2212/2214.
DO $pre2216$
DECLARE
    v_tbl  oid := to_regclass('public.catalog_variant_import_row');
    v_new  oid := to_regclass('public.uq_cvir_row_identity');
    v_np   oid := to_regclass('public.uq_cvir_job_card_type_no_printing');
    v_p    oid := to_regclass('public.uq_cvir_job_card_type_printing');
    v_fn   oid := to_regprocedure('internal.axis_identity_token(jsonb,text)');
    v_n    int;
    v_set  text[];
    r_fn   text; r_txt text; r_jt text; r_op2 text; r_op1 text;
    e      text[];  -- [1..3] nova def/pred/exprs; [4..6] no_printing; [7..9] printing
BEGIN
    IF v_tbl IS NULL THEN
        RAISE EXCEPTION 'PRE_TABLE_MISSING: public.catalog_variant_import_row ausente.';
    END IF;

    -- (a) funcao de token: identidade exata, resolvida SO pela assinatura
    IF v_fn IS NULL THEN
        RAISE EXCEPTION 'PRE_TOKEN_FUNCTION_DIVERGENT: internal.axis_identity_token(jsonb,text) ausente.';
    END IF;
    SELECT count(*) INTO v_n
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'internal' AND p.proname = 'axis_identity_token';
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'PRE_TOKEN_FUNCTION_DIVERGENT: esperado 1 overload de internal.axis_identity_token; encontrado %.', v_n;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_language l ON l.oid = p.prolang
         WHERE p.oid = v_fn
           AND p.provolatile = 'i' AND NOT p.prosecdef
           AND pg_get_userbyid(p.proowner) = 'postgres'
           AND p.proconfig = ARRAY['search_path=""']
           AND l.lanname = 'sql' AND p.prorettype = 'pg_catalog.text'::regtype
           AND md5(replace(p.prosrc, E'\r\n', E'\n')) = '18682dce935281b0a4437628a6e8309a'
    ) THEN
        RAISE EXCEPTION 'PRE_TOKEN_FUNCTION_DIVERGENT: volatilidade/security/owner/search_path/linguagem/retorno/corpo divergentes.';
    END IF;

    -- (b) fronteira de seguranca do schema internal (ACL NAO alterada aqui)
    IF has_schema_privilege('authenticated', 'internal', 'USAGE')
       OR has_schema_privilege('anon', 'internal', 'USAGE') THEN
        RAISE EXCEPTION 'PRE_SECURITY_BOUNDARY_DIVERGENT: authenticated/anon com USAGE no schema internal.';
    END IF;

    -- renderizacao esperada, derivada da visibilidade REAL (sem set_config)
    r_fn  := CASE WHEN pg_function_is_visible(v_fn) THEN 'axis_identity_token' ELSE 'internal.axis_identity_token' END;
    r_txt := CASE WHEN pg_type_is_visible('pg_catalog.text'::regtype) THEN 'text' ELSE 'pg_catalog.text' END;
    r_jt  := CASE WHEN pg_function_is_visible('pg_catalog.jsonb_typeof(jsonb)'::regprocedure) THEN 'jsonb_typeof' ELSE 'pg_catalog.jsonb_typeof' END;
    r_op2 := CASE WHEN pg_operator_is_visible('pg_catalog.->>(jsonb,text)'::regoperator) THEN '->>' ELSE 'OPERATOR(pg_catalog.->>)' END;
    r_op1 := CASE WHEN pg_operator_is_visible('pg_catalog.->(jsonb,text)'::regoperator) THEN '->' ELSE 'OPERATOR(pg_catalog.->)' END;
    SELECT array_agg(
             replace(replace(replace(replace(replace(u.x,
               'internal.axis_identity_token(', r_fn || '('),
               '::text', '::' || r_txt),
               'jsonb_typeof(', r_jt || '('),
               ' ->> ', ' ' || r_op2 || ' '),
               ' -> ', ' ' || r_op1 || ' ')
             ORDER BY u.o)
      INTO e
      FROM unnest(ARRAY[
        -- [1] nova: pg_get_indexdef
        'CREATE UNIQUE INDEX uq_cvir_row_identity ON public.catalog_variant_import_row USING btree (job_id, card_id, ((normalized_data ->> ''variant_type_id''::text)), internal.axis_identity_token(normalized_data, ''printing_profile_id''::text), internal.axis_identity_token(normalized_data, ''edition_context_profile_id''::text)) WHERE ((normalized_data ->> ''variant_type_id''::text) IS NOT NULL)',
        -- [2] nova: predicado
        '((normalized_data ->> ''variant_type_id''::text) IS NOT NULL)',
        -- [3] nova: expressoes
        '(normalized_data ->> ''variant_type_id''::text), internal.axis_identity_token(normalized_data, ''printing_profile_id''::text), internal.axis_identity_token(normalized_data, ''edition_context_profile_id''::text)',
        -- [4] no_printing: pg_get_indexdef
        'CREATE UNIQUE INDEX uq_cvir_job_card_type_no_printing ON public.catalog_variant_import_row USING btree (job_id, card_id, ((normalized_data ->> ''variant_type_id''::text))) WHERE (((normalized_data ->> ''variant_type_id''::text) IS NOT NULL) AND (jsonb_typeof((normalized_data -> ''printing_profile_id''::text)) = ''null''::text))',
        -- [5] no_printing: predicado
        '(((normalized_data ->> ''variant_type_id''::text) IS NOT NULL) AND (jsonb_typeof((normalized_data -> ''printing_profile_id''::text)) = ''null''::text))',
        -- [6] no_printing: expressoes
        '(normalized_data ->> ''variant_type_id''::text)',
        -- [7] printing: pg_get_indexdef
        'CREATE UNIQUE INDEX uq_cvir_job_card_type_printing ON public.catalog_variant_import_row USING btree (job_id, card_id, ((normalized_data ->> ''variant_type_id''::text)), ((normalized_data ->> ''printing_profile_id''::text))) WHERE (((normalized_data ->> ''variant_type_id''::text) IS NOT NULL) AND (jsonb_typeof((normalized_data -> ''printing_profile_id''::text)) = ''string''::text))',
        -- [8] printing: predicado
        '(((normalized_data ->> ''variant_type_id''::text) IS NOT NULL) AND (jsonb_typeof((normalized_data -> ''printing_profile_id''::text)) = ''string''::text))',
        -- [9] printing: expressoes
        '(normalized_data ->> ''variant_type_id''::text), (normalized_data ->> ''printing_profile_id''::text)'
      ]) WITH ORDINALITY u(x, o);

    -- (c) identidade nova: assinatura fisica completa (C1)
    IF v_new IS NULL OR NOT EXISTS (
        SELECT 1 FROM pg_index i
         WHERE i.indexrelid = v_new AND i.indrelid = v_tbl
           AND i.indisunique AND NOT i.indisprimary AND NOT i.indnullsnotdistinct
           AND i.indimmediate
           AND i.indisvalid AND i.indisready AND i.indislive
           AND i.indnatts = 5 AND i.indnkeyatts = 5
           AND pg_get_indexdef(i.indexrelid) = e[1]
           AND pg_get_expr(i.indpred, i.indrelid) = e[2]
           AND pg_get_expr(i.indexprs, i.indrelid) = e[3]
           AND (SELECT array_agg(coalesce(a.attname::text, '<expr>') ORDER BY k.o)
                  FROM unnest(i.indkey) WITH ORDINALITY k(att, o)
                  LEFT JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.att)
               = ARRAY['job_id','card_id','<expr>','<expr>','<expr>']
           AND NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conindid = i.indexrelid)
    ) THEN
        RAISE EXCEPTION 'PRE_NEW_STAGING_IDENTITY_INVALID: public.uq_cvir_row_identity ausente ou com assinatura divergente. Rode/valide a 2210.';
    END IF;
    -- autoridade ESTRUTURAL: dependencias do indice para pg_proc = EXATAMENTE {v_fn}
    IF (SELECT count(*) FROM pg_depend d
         WHERE d.classid = 'pg_catalog.pg_class'::regclass AND d.objid = v_new
           AND d.refclassid = 'pg_catalog.pg_proc'::regclass) <> 1
       OR NOT EXISTS (SELECT 1 FROM pg_depend d
         WHERE d.classid = 'pg_catalog.pg_class'::regclass AND d.objid = v_new
           AND d.refclassid = 'pg_catalog.pg_proc'::regclass
           AND d.refobjid = v_fn AND d.deptype = 'n') THEN
        RAISE EXCEPTION 'PRE_NEW_STAGING_IDENTITY_TOKEN_DEPENDENCY_DIVERGENT: dependencias pg_proc de uq_cvir_row_identity diferentes de {internal.axis_identity_token(jsonb,text)}.';
    END IF;

    -- (d) as duas antigas: estado previo EXATO (C2). Ausencia = ja executada
    --     ou divergente -> STOP, nunca NO-OP.
    IF v_np IS NULL OR v_p IS NULL THEN
        RAISE EXCEPTION 'PRE_LEGACY_STAGING_STATE_DIVERGENT: identidade antiga ausente (no_printing presente=%, printing presente=%). 2216 ja executada ou estado divergente — STOP, nunca NO-OP.',
              v_np IS NOT NULL, v_p IS NOT NULL;
    END IF;
    SELECT count(*) INTO v_n FROM pg_index i
     WHERE i.indrelid = v_tbl
       AND i.indisunique AND NOT i.indisprimary AND NOT i.indnullsnotdistinct
       AND i.indimmediate
       AND i.indisvalid AND i.indisready AND i.indislive
       AND (   (i.indexrelid = v_np
                AND i.indnatts = 3 AND i.indnkeyatts = 3
                AND pg_get_indexdef(i.indexrelid) = e[4]
                AND pg_get_expr(i.indpred, i.indrelid) = e[5]
                AND pg_get_expr(i.indexprs, i.indrelid) = e[6]
                AND (SELECT array_agg(coalesce(a.attname::text, '<expr>') ORDER BY k.o)
                       FROM unnest(i.indkey) WITH ORDINALITY k(att, o)
                       LEFT JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.att)
                    = ARRAY['job_id','card_id','<expr>'])
            OR (i.indexrelid = v_p
                AND i.indnatts = 4 AND i.indnkeyatts = 4
                AND pg_get_indexdef(i.indexrelid) = e[7]
                AND pg_get_expr(i.indpred, i.indrelid) = e[8]
                AND pg_get_expr(i.indexprs, i.indrelid) = e[9]
                AND (SELECT array_agg(coalesce(a.attname::text, '<expr>') ORDER BY k.o)
                       FROM unnest(i.indkey) WITH ORDINALITY k(att, o)
                       LEFT JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.att)
                    = ARRAY['job_id','card_id','<expr>','<expr>']));
    IF v_n <> 2 THEN
        RAISE EXCEPTION 'PRE_LEGACY_STAGING_STATE_DIVERGENT: % de 2 identidades antigas com tabela/definicao/predicado/expressoes/chaves/flags exatos.', v_n;
    END IF;
    IF (SELECT count(*) FROM pg_constraint WHERE conindid IN (v_np, v_p)) <> 0 THEN
        RAISE EXCEPTION 'PRE_LEGACY_STAGING_STATE_DIVERGENT: identidade antiga vinculada a pg_constraint.';
    END IF;
    IF (SELECT count(*) FROM pg_depend d
         WHERE d.refclassid = 'pg_catalog.pg_class'::regclass
           AND d.refobjid IN (v_np, v_p)
           AND d.deptype <> 'i') <> 0 THEN
        RAISE EXCEPTION 'PRE_LEGACY_STAGING_STATE_DIVERGENT: dependente formal nao-interno sobre identidade antiga.';
    END IF;

    -- (e) topologia PRE: exatamente 10 indices saudaveis, conjunto exato
    IF (SELECT count(*) FROM pg_index WHERE indrelid = v_tbl) <> 10
       OR EXISTS (SELECT 1 FROM pg_index WHERE indrelid = v_tbl
                   AND NOT (indisvalid AND indisready AND indislive)) THEN
        RAISE EXCEPTION 'PRE_INDEX_TOPOLOGY_DIVERGENT: esperado exatamente 10 indices saudaveis em public.catalog_variant_import_row.';
    END IF;
    SELECT array_agg(c.relname::text ORDER BY c.relname::text COLLATE "C") INTO v_set
      FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
     WHERE i.indrelid = v_tbl;
    IF v_set IS DISTINCT FROM ARRAY['catalog_variant_import_row_pkey',
                                    'ix_catalog_variant_import_row_card',
                                    'ix_catalog_variant_import_row_job',
                                    'ix_catalog_variant_import_row_job_decision',
                                    'ix_catalog_variant_import_row_job_persistence',
                                    'ix_catalog_variant_import_row_job_validation',
                                    'ix_catalog_variant_import_row_matched_variant',
                                    'uq_cvir_job_card_type_no_printing',
                                    'uq_cvir_job_card_type_printing',
                                    'uq_cvir_row_identity'] THEN
        RAISE EXCEPTION 'PRE_INDEX_TOPOLOGY_DIVERGENT: %', v_set;
    END IF;
END $pre2216$;

-- PRÉ-CONDIÇÃO B (preservada da v3.0 sem alteracao semantica): o backfill
-- semântico já cobriu o universo OPERACIONAL. Escopo job vivo + VALID +
-- PENDING, não "toda VALID": rows terminais cuja resolução permanece
-- indeterminada mantêm a chave AUSENTE por design (token 'A'), e isso é
-- correto — não é backfill pendente.
DO $boundary2216$
DECLARE v_falta INT; v_hist INT; v_canc INT;
BEGIN
    -- OPERACIONAL = job vivo E row pendente. job_status e obrigatorio aqui.
    SELECT COUNT(*) INTO v_falta
      FROM public.catalog_variant_import_row r
      JOIN public.catalog_variant_import_job j ON j.id = r.job_id
     WHERE j.status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING')
       AND r.persistence_status = 'PENDING'
       AND r.validation_status  = 'VALID'
       AND NOT jsonb_exists(r.normalized_data, 'edition_context_profile_id');
    IF v_falta <> 0 THEN
        RAISE EXCEPTION 'OPERATIONAL_NOT_RESOLVED: % rows OPERACIONAIS VALID sem a chave. Rode a Query 2212 antes.', v_falta;
    END IF;

    SELECT COUNT(*) INTO v_hist
      FROM public.catalog_variant_import_row r
      JOIN public.catalog_variant_import_job j ON j.id = r.job_id
     WHERE NOT jsonb_exists(r.normalized_data, 'edition_context_profile_id')
       AND (j.status NOT IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING')
            OR r.persistence_status <> 'PENDING');

    SELECT COUNT(*) INTO v_canc
      FROM public.catalog_variant_import_row r
      JOIN public.catalog_variant_import_job j ON j.id = r.job_id
     WHERE j.status = 'CANCELLED' AND r.validation_status = 'VALID'
       AND r.persistence_status = 'PENDING';

    RAISE NOTICE 'HISTORICO: % rows sem chave (legitimo). Destas, % sao VALID+PENDING em job CANCELLED — terminal, nao backlog.', v_hist, v_canc;
END $boundary2216$;

-- ---------------------------------------------------------------- PASSO 2 ---
-- Remocao da PRIMEIRA antiga. A segunda e a nova ainda protegem.
DROP INDEX public.uq_cvir_job_card_type_no_printing RESTRICT;

DO $mid2216$
DECLARE
    v_tbl oid := to_regclass('public.catalog_variant_import_row');
    v_new oid := to_regclass('public.uq_cvir_row_identity');
    v_p   oid := to_regclass('public.uq_cvir_job_card_type_printing');
    v_fn  oid := to_regprocedure('internal.axis_identity_token(jsonb,text)');
    r_fn  text; r_txt text; r_jt text; r_op2 text; r_op1 text;
    e     text[];  -- [1..3] nova def/pred/exprs; [4..6] printing def/pred/exprs
BEGIN
    IF to_regclass('public.uq_cvir_job_card_type_no_printing') IS NOT NULL THEN
        RAISE EXCEPTION 'DROP_FAILED_1: public.uq_cvir_job_card_type_no_printing ainda existe.';
    END IF;

    -- funcao de token: integralmente exata (resolvida SO pela assinatura)
    IF v_fn IS NULL
       OR (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'internal' AND p.proname = 'axis_identity_token') <> 1
       OR NOT EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_language l ON l.oid = p.prolang
         WHERE p.oid = v_fn
           AND p.provolatile = 'i' AND NOT p.prosecdef
           AND pg_get_userbyid(p.proowner) = 'postgres'
           AND p.proconfig = ARRAY['search_path=""']
           AND l.lanname = 'sql' AND p.prorettype = 'pg_catalog.text'::regtype
           AND md5(replace(p.prosrc, E'\r\n', E'\n')) = '18682dce935281b0a4437628a6e8309a') THEN
        RAISE EXCEPTION 'MID_TOKEN_FUNCTION_DIVERGENT: internal.axis_identity_token perdida ou alterada apos o DROP 1.';
    END IF;

    r_fn  := CASE WHEN pg_function_is_visible(v_fn) THEN 'axis_identity_token' ELSE 'internal.axis_identity_token' END;
    r_txt := CASE WHEN pg_type_is_visible('pg_catalog.text'::regtype) THEN 'text' ELSE 'pg_catalog.text' END;
    r_jt  := CASE WHEN pg_function_is_visible('pg_catalog.jsonb_typeof(jsonb)'::regprocedure) THEN 'jsonb_typeof' ELSE 'pg_catalog.jsonb_typeof' END;
    r_op2 := CASE WHEN pg_operator_is_visible('pg_catalog.->>(jsonb,text)'::regoperator) THEN '->>' ELSE 'OPERATOR(pg_catalog.->>)' END;
    r_op1 := CASE WHEN pg_operator_is_visible('pg_catalog.->(jsonb,text)'::regoperator) THEN '->' ELSE 'OPERATOR(pg_catalog.->)' END;
    SELECT array_agg(
             replace(replace(replace(replace(replace(u.x,
               'internal.axis_identity_token(', r_fn || '('),
               '::text', '::' || r_txt),
               'jsonb_typeof(', r_jt || '('),
               ' ->> ', ' ' || r_op2 || ' '),
               ' -> ', ' ' || r_op1 || ' ')
             ORDER BY u.o)
      INTO e
      FROM unnest(ARRAY[
        'CREATE UNIQUE INDEX uq_cvir_row_identity ON public.catalog_variant_import_row USING btree (job_id, card_id, ((normalized_data ->> ''variant_type_id''::text)), internal.axis_identity_token(normalized_data, ''printing_profile_id''::text), internal.axis_identity_token(normalized_data, ''edition_context_profile_id''::text)) WHERE ((normalized_data ->> ''variant_type_id''::text) IS NOT NULL)',
        '((normalized_data ->> ''variant_type_id''::text) IS NOT NULL)',
        '(normalized_data ->> ''variant_type_id''::text), internal.axis_identity_token(normalized_data, ''printing_profile_id''::text), internal.axis_identity_token(normalized_data, ''edition_context_profile_id''::text)',
        'CREATE UNIQUE INDEX uq_cvir_job_card_type_printing ON public.catalog_variant_import_row USING btree (job_id, card_id, ((normalized_data ->> ''variant_type_id''::text)), ((normalized_data ->> ''printing_profile_id''::text))) WHERE (((normalized_data ->> ''variant_type_id''::text) IS NOT NULL) AND (jsonb_typeof((normalized_data -> ''printing_profile_id''::text)) = ''string''::text))',
        '(((normalized_data ->> ''variant_type_id''::text) IS NOT NULL) AND (jsonb_typeof((normalized_data -> ''printing_profile_id''::text)) = ''string''::text))',
        '(normalized_data ->> ''variant_type_id''::text), (normalized_data ->> ''printing_profile_id''::text)'
      ]) WITH ORDINALITY u(x, o);

    -- antiga 2: presente e integralmente exata
    IF v_p IS NULL OR NOT EXISTS (
        SELECT 1 FROM pg_index i
         WHERE i.indexrelid = v_p AND i.indrelid = v_tbl
           AND i.indisunique AND NOT i.indisprimary AND NOT i.indnullsnotdistinct
           AND i.indimmediate
           AND i.indisvalid AND i.indisready AND i.indislive
           AND i.indnatts = 4 AND i.indnkeyatts = 4
           AND pg_get_indexdef(i.indexrelid) = e[4]
           AND pg_get_expr(i.indpred, i.indrelid) = e[5]
           AND pg_get_expr(i.indexprs, i.indrelid) = e[6]
           AND (SELECT array_agg(coalesce(a.attname::text, '<expr>') ORDER BY k.o)
                  FROM unnest(i.indkey) WITH ORDINALITY k(att, o)
                  LEFT JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.att)
               = ARRAY['job_id','card_id','<expr>','<expr>']
           AND NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conindid = i.indexrelid)
           AND NOT EXISTS (SELECT 1 FROM pg_depend d
                            WHERE d.refclassid = 'pg_catalog.pg_class'::regclass
                              AND d.refobjid = i.indexrelid AND d.deptype <> 'i')
    ) THEN
        RAISE EXCEPTION 'MID_LEGACY_2_DIVERGENT: public.uq_cvir_job_card_type_printing perdida ou alterada apos o DROP 1.';
    END IF;

    -- identidade nova: integralmente exata
    IF v_new IS NULL OR NOT EXISTS (
        SELECT 1 FROM pg_index i
         WHERE i.indexrelid = v_new AND i.indrelid = v_tbl
           AND i.indisunique AND NOT i.indisprimary AND NOT i.indnullsnotdistinct
           AND i.indimmediate
           AND i.indisvalid AND i.indisready AND i.indislive
           AND i.indnatts = 5 AND i.indnkeyatts = 5
           AND pg_get_indexdef(i.indexrelid) = e[1]
           AND pg_get_expr(i.indpred, i.indrelid) = e[2]
           AND pg_get_expr(i.indexprs, i.indrelid) = e[3]
           AND (SELECT array_agg(coalesce(a.attname::text, '<expr>') ORDER BY k.o)
                  FROM unnest(i.indkey) WITH ORDINALITY k(att, o)
                  LEFT JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.att)
               = ARRAY['job_id','card_id','<expr>','<expr>','<expr>']
           AND NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conindid = i.indexrelid)
    ) THEN
        RAISE EXCEPTION 'MID_NEW_STAGING_IDENTITY_INVALID: uq_cvir_row_identity perdida ou alterada apos o DROP 1.';
    END IF;
    IF (SELECT count(*) FROM pg_depend d
         WHERE d.classid = 'pg_catalog.pg_class'::regclass AND d.objid = v_new
           AND d.refclassid = 'pg_catalog.pg_proc'::regclass) <> 1
       OR NOT EXISTS (SELECT 1 FROM pg_depend d
         WHERE d.classid = 'pg_catalog.pg_class'::regclass AND d.objid = v_new
           AND d.refclassid = 'pg_catalog.pg_proc'::regclass
           AND d.refobjid = v_fn AND d.deptype = 'n') THEN
        RAISE EXCEPTION 'MID_NEW_STAGING_IDENTITY_TOKEN_DEPENDENCY_DIVERGENT: dependencias pg_proc de uq_cvir_row_identity diferentes de {v_fn}.';
    END IF;
END $mid2216$;

-- ---------------------------------------------------------------- PASSO 3 ---
DROP INDEX public.uq_cvir_job_card_type_printing RESTRICT;

-- ---------------------------------------------------------------- PASSO 4 ---
-- PROVA TERMINAL por topologia exata (schema + relacao), nao por contagem
-- generica. Somente a identidade nova permanece; ortogonais intactas.
DO $post2216$
DECLARE
    v_tbl oid := to_regclass('public.catalog_variant_import_row');
    v_new oid := to_regclass('public.uq_cvir_row_identity');
    v_fn  oid := to_regprocedure('internal.axis_identity_token(jsonb,text)');
    v_set text[];
    r_fn  text; r_txt text; r_jt text; r_op2 text; r_op1 text;
    e     text[];  -- [1..3] nova def/pred/exprs
BEGIN
    IF to_regclass('public.uq_cvir_job_card_type_no_printing') IS NOT NULL
       OR to_regclass('public.uq_cvir_job_card_type_printing') IS NOT NULL THEN
        RAISE EXCEPTION 'POST_LEGACY_SURVIVED: identidade antiga ainda existe.';
    END IF;

    -- funcao de token: integralmente exata (resolvida SO pela assinatura)
    IF v_fn IS NULL
       OR (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'internal' AND p.proname = 'axis_identity_token') <> 1
       OR NOT EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_language l ON l.oid = p.prolang
         WHERE p.oid = v_fn
           AND p.provolatile = 'i' AND NOT p.prosecdef
           AND pg_get_userbyid(p.proowner) = 'postgres'
           AND p.proconfig = ARRAY['search_path=""']
           AND l.lanname = 'sql' AND p.prorettype = 'pg_catalog.text'::regtype
           AND md5(replace(p.prosrc, E'\r\n', E'\n')) = '18682dce935281b0a4437628a6e8309a') THEN
        RAISE EXCEPTION 'POST_TOKEN_FUNCTION_DIVERGENT: internal.axis_identity_token perdida ou alterada.';
    END IF;

    r_fn  := CASE WHEN pg_function_is_visible(v_fn) THEN 'axis_identity_token' ELSE 'internal.axis_identity_token' END;
    r_txt := CASE WHEN pg_type_is_visible('pg_catalog.text'::regtype) THEN 'text' ELSE 'pg_catalog.text' END;
    r_jt  := CASE WHEN pg_function_is_visible('pg_catalog.jsonb_typeof(jsonb)'::regprocedure) THEN 'jsonb_typeof' ELSE 'pg_catalog.jsonb_typeof' END;
    r_op2 := CASE WHEN pg_operator_is_visible('pg_catalog.->>(jsonb,text)'::regoperator) THEN '->>' ELSE 'OPERATOR(pg_catalog.->>)' END;
    r_op1 := CASE WHEN pg_operator_is_visible('pg_catalog.->(jsonb,text)'::regoperator) THEN '->' ELSE 'OPERATOR(pg_catalog.->)' END;
    SELECT array_agg(
             replace(replace(replace(replace(replace(u.x,
               'internal.axis_identity_token(', r_fn || '('),
               '::text', '::' || r_txt),
               'jsonb_typeof(', r_jt || '('),
               ' ->> ', ' ' || r_op2 || ' '),
               ' -> ', ' ' || r_op1 || ' ')
             ORDER BY u.o)
      INTO e
      FROM unnest(ARRAY[
        'CREATE UNIQUE INDEX uq_cvir_row_identity ON public.catalog_variant_import_row USING btree (job_id, card_id, ((normalized_data ->> ''variant_type_id''::text)), internal.axis_identity_token(normalized_data, ''printing_profile_id''::text), internal.axis_identity_token(normalized_data, ''edition_context_profile_id''::text)) WHERE ((normalized_data ->> ''variant_type_id''::text) IS NOT NULL)',
        '((normalized_data ->> ''variant_type_id''::text) IS NOT NULL)',
        '(normalized_data ->> ''variant_type_id''::text), internal.axis_identity_token(normalized_data, ''printing_profile_id''::text), internal.axis_identity_token(normalized_data, ''edition_context_profile_id''::text)'
      ]) WITH ORDINALITY u(x, o);

    -- identidade nova: integralmente exata
    IF v_new IS NULL OR NOT EXISTS (
        SELECT 1 FROM pg_index i
         WHERE i.indexrelid = v_new AND i.indrelid = v_tbl
           AND i.indisunique AND NOT i.indisprimary AND NOT i.indnullsnotdistinct
           AND i.indimmediate
           AND i.indisvalid AND i.indisready AND i.indislive
           AND i.indnatts = 5 AND i.indnkeyatts = 5
           AND pg_get_indexdef(i.indexrelid) = e[1]
           AND pg_get_expr(i.indpred, i.indrelid) = e[2]
           AND pg_get_expr(i.indexprs, i.indrelid) = e[3]
           AND (SELECT array_agg(coalesce(a.attname::text, '<expr>') ORDER BY k.o)
                  FROM unnest(i.indkey) WITH ORDINALITY k(att, o)
                  LEFT JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.att)
               = ARRAY['job_id','card_id','<expr>','<expr>','<expr>']
           AND NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conindid = i.indexrelid)
    ) THEN
        RAISE EXCEPTION 'POST_NEW_STAGING_IDENTITY_INVALID: uq_cvir_row_identity perdida ou alterada.';
    END IF;
    IF (SELECT count(*) FROM pg_depend d
         WHERE d.classid = 'pg_catalog.pg_class'::regclass AND d.objid = v_new
           AND d.refclassid = 'pg_catalog.pg_proc'::regclass) <> 1
       OR NOT EXISTS (SELECT 1 FROM pg_depend d
         WHERE d.classid = 'pg_catalog.pg_class'::regclass AND d.objid = v_new
           AND d.refclassid = 'pg_catalog.pg_proc'::regclass
           AND d.refobjid = v_fn AND d.deptype = 'n') THEN
        RAISE EXCEPTION 'POST_NEW_STAGING_IDENTITY_TOKEN_DEPENDENCY_DIVERGENT: dependencias pg_proc de uq_cvir_row_identity diferentes de {v_fn}.';
    END IF;

    -- topologia: exatamente 8 indices em public.catalog_variant_import_row,
    -- todos saudaveis, conjunto exato
    IF (SELECT count(*) FROM pg_index WHERE indrelid = v_tbl) <> 8
       OR EXISTS (SELECT 1 FROM pg_index WHERE indrelid = v_tbl
                   AND NOT (indisvalid AND indisready AND indislive)) THEN
        RAISE EXCEPTION 'POST_INDEX_TOPOLOGY_DIVERGENT: esperado exatamente 8 indices saudaveis em public.catalog_variant_import_row.';
    END IF;
    SELECT array_agg(c.relname::text ORDER BY c.relname::text COLLATE "C") INTO v_set
      FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
     WHERE i.indrelid = v_tbl;
    IF v_set IS DISTINCT FROM ARRAY['catalog_variant_import_row_pkey',
                                    'ix_catalog_variant_import_row_card',
                                    'ix_catalog_variant_import_row_job',
                                    'ix_catalog_variant_import_row_job_decision',
                                    'ix_catalog_variant_import_row_job_persistence',
                                    'ix_catalog_variant_import_row_job_validation',
                                    'ix_catalog_variant_import_row_matched_variant',
                                    'uq_cvir_row_identity'] THEN
        RAISE EXCEPTION 'POST_INDEX_TOPOLOGY_DIVERGENT: %', v_set;
    END IF;

    -- conjunto EXATO de indices UNIQUE
    SELECT array_agg(c.relname::text ORDER BY c.relname::text COLLATE "C") INTO v_set
      FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
     WHERE i.indrelid = v_tbl AND i.indisunique;
    IF v_set IS DISTINCT FROM ARRAY['catalog_variant_import_row_pkey','uq_cvir_row_identity'] THEN
        RAISE EXCEPTION 'POST_UNIQUE_TOPOLOGY_DIVERGENT: %', v_set;
    END IF;

    -- PK: indice + constraint exatos
    IF NOT EXISTS (
        SELECT 1 FROM pg_index i JOIN pg_constraint c ON c.conindid = i.indexrelid
         WHERE i.indexrelid = to_regclass('public.catalog_variant_import_row_pkey')
           AND i.indrelid = v_tbl AND i.indisprimary AND i.indisunique
           AND pg_get_indexdef(i.indexrelid) = 'CREATE UNIQUE INDEX catalog_variant_import_row_pkey ON public.catalog_variant_import_row USING btree (id)'
           AND c.conrelid = v_tbl AND c.conname = 'catalog_variant_import_row_pkey'
           AND c.contype = 'p' AND c.convalidated
    ) THEN
        RAISE EXCEPTION 'POST_PKEY_DIVERGENT: catalog_variant_import_row_pkey perdida ou alterada.';
    END IF;

    -- ortogonais nao-unicos: definicao exata + pertencem a tabela exata
    IF (SELECT count(*) FROM pg_index i
         WHERE i.indrelid = v_tbl AND NOT i.indisunique
           AND (   (i.indexrelid = to_regclass('public.ix_catalog_variant_import_row_card')
                    AND pg_get_indexdef(i.indexrelid) = 'CREATE INDEX ix_catalog_variant_import_row_card ON public.catalog_variant_import_row USING btree (card_id)')
                OR (i.indexrelid = to_regclass('public.ix_catalog_variant_import_row_job')
                    AND pg_get_indexdef(i.indexrelid) = 'CREATE INDEX ix_catalog_variant_import_row_job ON public.catalog_variant_import_row USING btree (job_id)')
                OR (i.indexrelid = to_regclass('public.ix_catalog_variant_import_row_job_decision')
                    AND pg_get_indexdef(i.indexrelid) = 'CREATE INDEX ix_catalog_variant_import_row_job_decision ON public.catalog_variant_import_row USING btree (job_id, decision_status)')
                OR (i.indexrelid = to_regclass('public.ix_catalog_variant_import_row_job_persistence')
                    AND pg_get_indexdef(i.indexrelid) = 'CREATE INDEX ix_catalog_variant_import_row_job_persistence ON public.catalog_variant_import_row USING btree (job_id, persistence_status)')
                OR (i.indexrelid = to_regclass('public.ix_catalog_variant_import_row_job_validation')
                    AND pg_get_indexdef(i.indexrelid) = 'CREATE INDEX ix_catalog_variant_import_row_job_validation ON public.catalog_variant_import_row USING btree (job_id, validation_status)')
                OR (i.indexrelid = to_regclass('public.ix_catalog_variant_import_row_matched_variant')
                    AND pg_get_indexdef(i.indexrelid) = 'CREATE INDEX ix_catalog_variant_import_row_matched_variant ON public.catalog_variant_import_row USING btree (matched_variant_id) WHERE (matched_variant_id IS NOT NULL)'))) <> 6 THEN
        RAISE EXCEPTION 'POST_ORTHOGONAL_DIVERGENT: indice ortogonal perdido ou alterado.';
    END IF;
END $post2216$;

-- ---------------------------------------------------------------- PASSO 5 ---
-- PROVA FUNCIONAL S4 (deterministica). SAVEPOINT proprio, aberto DEPOIS do
-- POST; sempre desfeito. Fixture: job TERMINAL (ORDER BY id), primeiro
-- Variant Type (ORDER BY id), primeira Card (ORDER BY id) cuja tupla
-- (job, card, vt) nao existe no staging. IDs, marcador e Edition Context
-- sentinelas literais, provados ausentes antes do probe.
--   α: pp JSON null, EC JSON null            -> tokens ('N','N')
--   β: pp JSON null, EC sentinela literal    -> tokens ('N','U:<sentinela>')
--   γ: duplicata exata de α (id proprio)     -> DEVE violar uq_cvir_row_identity
-- Todas NEEDS_REVIEW: fora de G1 do guard 2214; G3 (forma) aceita null e o
-- UUID sentinela; G2 so vale em UPDATE.
SAVEPOINT s4_probe_2216;

DO $s4_2216$
DECLARE
    c_id_a   CONSTANT uuid := '22160000-0000-4000-8000-0000000000a1';
    c_id_b   CONSTANT uuid := '22160000-0000-4000-8000-0000000000b2';
    c_id_g   CONSTANT uuid := '22160000-0000-4000-8000-0000000000c3';
    c_ec     CONSTANT uuid := '22160000-0000-4000-8000-00000000ec01';
    c_marker CONSTANT text := '2216-S4';
    v_job    uuid;
    v_card   uuid;
    v_vt     uuid;
    v_ids    uuid[];
    v_n      int;
    v_gamma_rejected boolean := false;
    v_con    text;
    v_tab    text;
    v_sch    text;
BEGIN
    -- fixture deterministica
    SELECT j.id INTO v_job
      FROM public.catalog_variant_import_job j
     WHERE j.status IN ('COMPLETED','COMPLETED_WITH_ERRORS','FAILED','CANCELLED')
     ORDER BY j.id
     LIMIT 1;
    SELECT t.id INTO v_vt
      FROM public.card_variant_type t
     ORDER BY t.id
     LIMIT 1;
    SELECT c.id INTO v_card
      FROM public.card c
     WHERE NOT EXISTS (
           SELECT 1 FROM public.catalog_variant_import_row r
            WHERE r.job_id = v_job AND r.card_id = c.id
              AND (r.normalized_data ->> 'variant_type_id') = v_vt::text)
     ORDER BY c.id
     LIMIT 1;
    IF v_job IS NULL OR v_card IS NULL OR v_vt IS NULL THEN
        RAISE EXCEPTION 'S4_PROBE_NO_FIXTURE: job terminal/card/variant_type indisponivel (job=%, card=%, vt=%).', v_job, v_card, v_vt;
    END IF;

    -- pre-estado do probe: tupla, IDs, marcador e sentinela AUSENTES
    SELECT count(*) INTO v_n FROM public.catalog_variant_import_row r
     WHERE r.job_id = v_job AND r.card_id = v_card
       AND (r.normalized_data ->> 'variant_type_id') = v_vt::text;
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'S4_PROBE_TUPLE_NOT_ABSENT: % rows ja existem para (job, card, vt).', v_n;
    END IF;
    SELECT count(*) INTO v_n FROM public.catalog_variant_import_row r
     WHERE r.id IN (c_id_a, c_id_b, c_id_g)
        OR (r.raw_data ->> 'mimikyu_probe') = c_marker
        OR (r.normalized_data ->> 'edition_context_profile_id') = c_ec::text;
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'S4_PROBE_SENTINEL_NOT_ABSENT: % rows com ID/marcador/Edition Context sentinela preexistentes.', v_n;
    END IF;

    -- α + β: exatamente 2 IDs retornados, exatamente os sentinelas
    WITH ins AS (
        INSERT INTO public.catalog_variant_import_row
            (id, job_id, card_id, raw_data, normalized_data, validation_status)
        VALUES
            (c_id_a, v_job, v_card,
             jsonb_build_object('mimikyu_probe', c_marker, 'case', 'alpha'),
             jsonb_build_object('variant_type_id', v_vt,
                                'printing_profile_id', NULL,
                                'edition_context_profile_id', NULL),
             'NEEDS_REVIEW'),
            (c_id_b, v_job, v_card,
             jsonb_build_object('mimikyu_probe', c_marker, 'case', 'beta'),
             jsonb_build_object('variant_type_id', v_vt,
                                'printing_profile_id', NULL,
                                'edition_context_profile_id', c_ec),
             'NEEDS_REVIEW')
        RETURNING id
    )
    SELECT array_agg(id ORDER BY id), count(*) INTO v_ids, v_n FROM ins;
    IF v_n <> 2 OR v_ids IS DISTINCT FROM ARRAY[c_id_a, c_id_b] THEN
        RAISE EXCEPTION 'S4_ALPHA_BETA_RETURNING_DIVERGENT: retornados % IDs (%).', v_n, v_ids;
    END IF;
    SELECT count(*) INTO v_n FROM public.catalog_variant_import_row r
     WHERE r.id = ANY (v_ids);
    IF v_n <> 2 THEN
        RAISE EXCEPTION 'S4_ALPHA_BETA_NOT_VISIBLE: esperado 2, obtido %.', v_n;
    END IF;

    -- identidade: iguais em job/card/vt/token_pp, diferentes SO no token_ec
    SELECT count(*) INTO v_n FROM public.catalog_variant_import_row r
     WHERE r.job_id = v_job AND r.card_id = v_card
       AND (r.normalized_data ->> 'variant_type_id') = v_vt::text
       AND r.validation_status = 'NEEDS_REVIEW'
       AND internal.axis_identity_token(r.normalized_data, 'printing_profile_id') = 'N'
       AND (   (r.id = c_id_a
                AND internal.axis_identity_token(r.normalized_data, 'edition_context_profile_id') = 'N')
            OR (r.id = c_id_b
                AND internal.axis_identity_token(r.normalized_data, 'edition_context_profile_id') = 'U:' || c_ec::text));
    IF v_n <> 2 THEN
        RAISE EXCEPTION 'S4_ALPHA_BETA_IDENTITY_DIVERGENT: esperado 2 rows diferindo so no token Edition Context; obtido %.', v_n;
    END IF;

    -- γ: duplicata exata de α (id proprio, para nao colidir na PK)
    BEGIN
        INSERT INTO public.catalog_variant_import_row
            (id, job_id, card_id, raw_data, normalized_data, validation_status)
        VALUES
            (c_id_g, v_job, v_card,
             jsonb_build_object('mimikyu_probe', c_marker, 'case', 'gamma'),
             jsonb_build_object('variant_type_id', v_vt,
                                'printing_profile_id', NULL,
                                'edition_context_profile_id', NULL),
             'NEEDS_REVIEW');
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS v_con = CONSTRAINT_NAME,
                                v_tab = TABLE_NAME,
                                v_sch = SCHEMA_NAME;
        v_gamma_rejected := true;
    END;
    IF NOT v_gamma_rejected THEN
        RAISE EXCEPTION 'S4_GAMMA_NOT_REJECTED: duplicata exata de α foi aceita — identidade nova nao impoe unicidade.';
    END IF;
    IF v_con IS DISTINCT FROM 'uq_cvir_row_identity'
       OR v_tab IS DISTINCT FROM 'catalog_variant_import_row'
       OR v_sch IS DISTINCT FROM 'public' THEN
        RAISE EXCEPTION 'S4_GAMMA_WRONG_OBJECT: unique_violation reportada por %.%/% (esperado public.catalog_variant_import_row/uq_cvir_row_identity).', v_sch, v_tab, v_con;
    END IF;

    RAISE NOTICE 'S4 OK — α/β coexistem diferindo so em Edition Context; γ rejeitada por uq_cvir_row_identity.';
END $s4_2216$;

ROLLBACK TO SAVEPOINT s4_probe_2216;

-- ---------------------------------------------------------------- PASSO 6 ---
-- PROVA DE RESIDUO ZERO + TOPOLOGIA TERMINAL COMPLETA (apos o ROLLBACK TO
-- SAVEPOINT, ainda na transacao).
DO $residue2216$
DECLARE
    v_tbl oid := to_regclass('public.catalog_variant_import_row');
    v_new oid := to_regclass('public.uq_cvir_row_identity');
    v_fn  oid := to_regprocedure('internal.axis_identity_token(jsonb,text)');
    v_n   int;
    v_set text[];
    r_fn  text; r_txt text; r_jt text; r_op2 text; r_op1 text;
    e     text[];  -- [1..3] nova def/pred/exprs
BEGIN
    -- (A) zero residuo do S4: por IDs, por marcador e por Edition Context sentinela
    SELECT count(*) INTO v_n FROM public.catalog_variant_import_row r
     WHERE r.id IN ('22160000-0000-4000-8000-0000000000a1'::uuid,
                    '22160000-0000-4000-8000-0000000000b2'::uuid,
                    '22160000-0000-4000-8000-0000000000c3'::uuid)
        OR (r.raw_data ->> 'mimikyu_probe') = '2216-S4'
        OR (r.normalized_data ->> 'edition_context_profile_id') = '22160000-0000-4000-8000-00000000ec01';
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'S4_PROBE_RESIDUE: % rows do probe sobreviveram ao ROLLBACK TO SAVEPOINT.', v_n;
    END IF;

    -- (B) as duas antigas continuam AUSENTES
    IF to_regclass('public.uq_cvir_job_card_type_no_printing') IS NOT NULL
       OR to_regclass('public.uq_cvir_job_card_type_printing') IS NOT NULL THEN
        RAISE EXCEPTION 'RESIDUE_LEGACY_REAPPEARED: identidade antiga presente apos o probe.';
    END IF;

    -- (D) funcao de token: integralmente exata (resolvida SO pela assinatura)
    IF v_fn IS NULL
       OR (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'internal' AND p.proname = 'axis_identity_token') <> 1
       OR NOT EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_language l ON l.oid = p.prolang
         WHERE p.oid = v_fn
           AND p.provolatile = 'i' AND NOT p.prosecdef
           AND pg_get_userbyid(p.proowner) = 'postgres'
           AND p.proconfig = ARRAY['search_path=""']
           AND l.lanname = 'sql' AND p.prorettype = 'pg_catalog.text'::regtype
           AND md5(replace(p.prosrc, E'\r\n', E'\n')) = '18682dce935281b0a4437628a6e8309a') THEN
        RAISE EXCEPTION 'RESIDUE_TOKEN_FUNCTION_DIVERGENT: internal.axis_identity_token perdida ou alterada apos o probe.';
    END IF;

    r_fn  := CASE WHEN pg_function_is_visible(v_fn) THEN 'axis_identity_token' ELSE 'internal.axis_identity_token' END;
    r_txt := CASE WHEN pg_type_is_visible('pg_catalog.text'::regtype) THEN 'text' ELSE 'pg_catalog.text' END;
    r_jt  := CASE WHEN pg_function_is_visible('pg_catalog.jsonb_typeof(jsonb)'::regprocedure) THEN 'jsonb_typeof' ELSE 'pg_catalog.jsonb_typeof' END;
    r_op2 := CASE WHEN pg_operator_is_visible('pg_catalog.->>(jsonb,text)'::regoperator) THEN '->>' ELSE 'OPERATOR(pg_catalog.->>)' END;
    r_op1 := CASE WHEN pg_operator_is_visible('pg_catalog.->(jsonb,text)'::regoperator) THEN '->' ELSE 'OPERATOR(pg_catalog.->)' END;
    SELECT array_agg(
             replace(replace(replace(replace(replace(u.x,
               'internal.axis_identity_token(', r_fn || '('),
               '::text', '::' || r_txt),
               'jsonb_typeof(', r_jt || '('),
               ' ->> ', ' ' || r_op2 || ' '),
               ' -> ', ' ' || r_op1 || ' ')
             ORDER BY u.o)
      INTO e
      FROM unnest(ARRAY[
        'CREATE UNIQUE INDEX uq_cvir_row_identity ON public.catalog_variant_import_row USING btree (job_id, card_id, ((normalized_data ->> ''variant_type_id''::text)), internal.axis_identity_token(normalized_data, ''printing_profile_id''::text), internal.axis_identity_token(normalized_data, ''edition_context_profile_id''::text)) WHERE ((normalized_data ->> ''variant_type_id''::text) IS NOT NULL)',
        '((normalized_data ->> ''variant_type_id''::text) IS NOT NULL)',
        '(normalized_data ->> ''variant_type_id''::text), internal.axis_identity_token(normalized_data, ''printing_profile_id''::text), internal.axis_identity_token(normalized_data, ''edition_context_profile_id''::text)'
      ]) WITH ORDINALITY u(x, o);

    -- (C) identidade nova: integralmente exata + dependencia estrutural {v_fn}
    IF v_new IS NULL OR NOT EXISTS (
        SELECT 1 FROM pg_index i
         WHERE i.indexrelid = v_new AND i.indrelid = v_tbl
           AND i.indisunique AND NOT i.indisprimary AND NOT i.indnullsnotdistinct
           AND i.indimmediate
           AND i.indisvalid AND i.indisready AND i.indislive
           AND i.indnatts = 5 AND i.indnkeyatts = 5
           AND pg_get_indexdef(i.indexrelid) = e[1]
           AND pg_get_expr(i.indpred, i.indrelid) = e[2]
           AND pg_get_expr(i.indexprs, i.indrelid) = e[3]
           AND (SELECT array_agg(coalesce(a.attname::text, '<expr>') ORDER BY k.o)
                  FROM unnest(i.indkey) WITH ORDINALITY k(att, o)
                  LEFT JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.att)
               = ARRAY['job_id','card_id','<expr>','<expr>','<expr>']
           AND NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conindid = i.indexrelid)
    ) THEN
        RAISE EXCEPTION 'RESIDUE_NEW_STAGING_IDENTITY_INVALID: uq_cvir_row_identity perdida ou alterada apos o probe.';
    END IF;
    IF (SELECT count(*) FROM pg_depend d
         WHERE d.classid = 'pg_catalog.pg_class'::regclass AND d.objid = v_new
           AND d.refclassid = 'pg_catalog.pg_proc'::regclass) <> 1
       OR NOT EXISTS (SELECT 1 FROM pg_depend d
         WHERE d.classid = 'pg_catalog.pg_class'::regclass AND d.objid = v_new
           AND d.refclassid = 'pg_catalog.pg_proc'::regclass
           AND d.refobjid = v_fn AND d.deptype = 'n') THEN
        RAISE EXCEPTION 'RESIDUE_NEW_STAGING_IDENTITY_TOKEN_DEPENDENCY_DIVERGENT: dependencias pg_proc de uq_cvir_row_identity diferentes de {v_fn}.';
    END IF;

    -- (E) topologia terminal EXATA: 8 indices, nomes exatos, 0 unhealthy
    IF (SELECT count(*) FROM pg_index WHERE indrelid = v_tbl) <> 8
       OR EXISTS (SELECT 1 FROM pg_index WHERE indrelid = v_tbl
                   AND NOT (indisvalid AND indisready AND indislive)) THEN
        RAISE EXCEPTION 'RESIDUE_INDEX_TOPOLOGY_DIVERGENT: esperado exatamente 8 indices saudaveis apos o probe.';
    END IF;
    SELECT array_agg(c.relname::text ORDER BY c.relname::text COLLATE "C") INTO v_set
      FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
     WHERE i.indrelid = v_tbl;
    IF v_set IS DISTINCT FROM ARRAY['catalog_variant_import_row_pkey',
                                    'ix_catalog_variant_import_row_card',
                                    'ix_catalog_variant_import_row_job',
                                    'ix_catalog_variant_import_row_job_decision',
                                    'ix_catalog_variant_import_row_job_persistence',
                                    'ix_catalog_variant_import_row_job_validation',
                                    'ix_catalog_variant_import_row_matched_variant',
                                    'uq_cvir_row_identity'] THEN
        RAISE EXCEPTION 'RESIDUE_INDEX_TOPOLOGY_DIVERGENT: %', v_set;
    END IF;
    --     UNIQUE exatamente {pkey, uq_cvir_row_identity}
    SELECT array_agg(c.relname::text ORDER BY c.relname::text COLLATE "C") INTO v_set
      FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
     WHERE i.indrelid = v_tbl AND i.indisunique;
    IF v_set IS DISTINCT FROM ARRAY['catalog_variant_import_row_pkey','uq_cvir_row_identity'] THEN
        RAISE EXCEPTION 'RESIDUE_UNIQUE_TOPOLOGY_DIVERGENT: %', v_set;
    END IF;

    RAISE NOTICE 'RESIDUO S4: 0 rows; topologia terminal 8/UNIQUE 2 intacta. 2216 pronta para COMMIT.';
END $residue2216$;

-- ============================================================================
-- ROLLBACK COMPLETO
--   Os dois índices antigos podem ser recriados enquanto os dados ainda os
--   satisfizerem — o que deixa de valer assim que a primeira dupla de rows
--   como a α/β do PASSO 5 for gravada de verdade. Isso é correto: é o sinal
--   de que o eixo passou a existir no staging.
--
--     CREATE UNIQUE INDEX uq_cvir_job_card_type_no_printing
--         ON public.catalog_variant_import_row
--            (job_id, card_id, (normalized_data ->> 'variant_type_id'))
--      WHERE (normalized_data ->> 'variant_type_id') IS NOT NULL
--        AND jsonb_typeof(normalized_data -> 'printing_profile_id') = 'null';
--     CREATE UNIQUE INDEX uq_cvir_job_card_type_printing
--         ON public.catalog_variant_import_row
--            (job_id, card_id, (normalized_data ->> 'variant_type_id'),
--             (normalized_data ->> 'printing_profile_id'))
--      WHERE (normalized_data ->> 'variant_type_id') IS NOT NULL
--        AND jsonb_typeof(normalized_data -> 'printing_profile_id') = 'string';
--
-- ARMADO PARA ROLLOUT (ROLLOUT-EXECUTION-READINESS-01). Terminador COMMIT.
-- (Historico v3.0: corpo auditado preservado byte a byte; a unica alteracao
-- de armamento foi ROLLBACK; -> COMMIT;. O corpo foi reescrito na v4.0 — ver
-- topo.) A protecao contra execucao prematura e GOVERNANCA (autorizacao de
-- Fabricio + ordem de batches), nao o terminador — mesma decisao ja aceita
-- em R1 para 2203-2211.
-- ============================================================================
COMMIT;
