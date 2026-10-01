-- ============================================================================
-- 2830H · E00 — PRECHECK JIT + INVENTÁRIOS (P6, P7, P8, P10, P11)
-- ============================================================================
-- Status ........ versão CORRIGIDA (BATCH12-2830-STOP-ADJUDICATION-CORRECTION-01)
--                 — NÃO EXECUTADA, NÃO COMPILADA no PostgreSQL. A versão
--                 anterior (blob 97410c3a…) foi executada na Tentativa 03
--                 (STOP em S1.3). Somente SELECT: um único statement, sem
--                 DML, sem DDL, sem set_config, sem TEMP.
-- Uso ........... rodado IMEDIATAMENTE antes de cada envelope autorizado. O
--                 resultado jsonb é registrado INTEGRALMENTE; os campos
--                 d_baseline e d_baseline_md5 alimentam o E99 da MESMA rodada.
-- gate_pass ..... TRUE só se TODOS os g_* forem TRUE. Qualquer FALSE ou NULL
--                 = STOP antes do envelope.
--
-- DOIS BASELINES — NÃO CONFUNDIR (correção BATCH12-2830-HARNESS-FOUNDATION-
-- CORRECTION-01):
--   (1) BASELINE CANÔNICO DO FREEZE — constantes FIXAS no bloco CANON abaixo,
--       medidas e registradas antes do Batch 12 (fonte por chave no bloco).
--       Gate g_freeze_canonical_equal: o LIVE de AGORA precisa ser IGUAL a
--       elas. Diferença = o FREEZE foi violado ou o estado derivou ⇒ STOP.
--       Nunca se "atualiza" uma constante para fazer o gate passar.
--   (2) BASELINE DA RODADA — d_baseline, capturado AGORA por este E00 com o
--       BASELINE-BUILDER. É o que o E99 da mesma rodada compara, campo a
--       campo, depois do envelope. Inclui chaves que não têm valor canônico
--       (ex.: action_log, mapping_trait), por isso não substitui o (1).
--
-- P7 — INVENTÁRIO DE TRIGGERS E EFEITOS EXTERNOS, COM CHAMADAS INDIRETAS
-- (v3 — BATCH12-2830-HARNESS-FOUNDATION-CORRECTION-02):
--   Raízes: todo trigger não interno + toda função referenciada por CHECK,
--   DEFAULT ou expressão de índice (pg_depend) das tabelas do escopo.
--   Análise LÉXICA do corpo (prosrc) de cada função alcançada, depois de
--   remover comentários e literais de string (padrão p7_re.lex), para que
--   texto de comentário/mensagem não gere nem esconda dependência:
--     · chamada QUALIFICADA schema.f(    → resolvida em pg_proc; seguida no
--       fecho transitivo (plpgsql não registra função→função em pg_depend);
--     · chamada NÃO QUALIFICADA f(       → só é aceita se for palavra-chave
--       sintática listada, ou função/tipo de pg_catalog (com search_path=""
--       é o único lugar onde ela pode resolver); lista negra ⇒ DENIED;
--       qualquer outra ⇒ NÃO RESOLVIDA;
--     · DML QUALIFICADO  (INSERT INTO / UPDATE / DELETE FROM / MERGE INTO /
--       TRUNCATE schema.t) → o alvo precisa existir em pg_class E estar no
--       escopo;
--     · DML NÃO QUALIFICADO → sempre STOP (com search_path="" o alvo só
--       resolveria em pg_temp/pg_catalog — nunca é um alvo legítimo aqui);
--     · construções que a análise léxica não modela com segurança —
--       E-string, dollar-quote interno, identificador entre aspas duplas,
--       nome em três partes — ⇒ STOP (não interpretável = não classificado).
--   Cada função alcançada é CLASSIFICADA:
--     BUILTIN ............ pg_catalog, fora da lista negra
--     <classe>  .......... entrada da p7_allowlist COM IDENTIDADE CONFERIDA:
--                          schema + nome + argumentos de identidade +
--                          linguagem + SECURITY DEFINER + volatilidade +
--                          proconfig exato + md5 do corpo com EOL
--                          normalizado (ou símbolo C e pertença à
--                          extensão, para funções C)
--     ALLOWLIST_MISMATCH . nome/assinatura listados, mas qualquer pino
--                          divergente ⇒ STOP (identidade, não nome)
--     DENIED / UNCLASSIFIED ⇒ STOP
--   search_path seguro: toda função alcançada fora de pg_catalog e não-C
--   precisa ter EXATAMENTE uma entrada search_path em proconfig, igual a
--   search_path="" ⇒ senão STOP.
--   Também ⇒ STOP: sinal de efeito externo no corpo BRUTO (conservador);
--   EXECUTE dinâmico; comando DDL no corpo (g_p7_no_ddl — um DDL no fecho
--   dispararia event triggers); fecho atingindo a profundidade 8; regra
--   pg_rewrite não-SELECT.
--   EOL (D-6, BATCH12-2830-LIVE-STAGE1-STOP-ADJUDICATION-01): o pino é
--   md5(replace(prosrc, CRLF, LF)) — normalização determinística e só de
--   CRLF (CR isolado NÃO é normalizado ⇒ ALLOWLIST_MISMATCH). O md5 BRUTO
--   continua exportado em d_p7_functions.body_md5, com body_md5_lf,
--   cr_count e crlf_count; toda função cujo bruto ≠ normalizado é listada
--   em d_p7_eol_normalized. Nada é aceito em silêncio.
--   EVENT TRIGGERS (P7-EVT): inventário integral em d_event_triggers
--   (nome, evento, tags, estado, dono, função, linguagem, dono da função,
--   SECURITY DEFINER, proconfig, extensão, md5 bruto e LF).
--   g_evt_inventory_complete: count(pg_event_trigger) lido DIRETO do
--   catálogo = linhas efetivamente produzidas em evt (G-3: nenhum trigger
--   some do inventário por JOIN); senão STOP.
--   g_evt_ddl_only: habilitado com evento fora de ddl_command_start /
--   ddl_command_end / sql_drop / table_rewrite (ex.: login) ⇒ STOP, sem
--   exceção possível. g_evt_all_adjudicated: todo event trigger habilitado
--   precisa casar, por IDENTIDADE COMPLETA de 12 atributos (G-4), com uma
--   linha de evt_allowlist que tenha justificativa não vazia; exceção só
--   para evento DDL; senão STOP. Semântica de NULL: '=' (NULL nunca casa)
--   em name, event, enabled, owner, fn, fn_language, fn_owner, fn_secdef e
--   fn_md5_lf; IS NOT DISTINCT FROM em tags, fn_config e fn_extension, onde
--   NULL é um estado real pinado (sem filtro de tag / sem proconfig / sem
--   extensão), nunca curinga.
--   evt_allowlist: as 6 exceções aprovadas em D-9 (BATCH12-2830-D9-EVENT-
--   TRIGGER-ALLOWLIST-01), identidades copiadas literalmente da L4
--   (BATCH12-2830-LIVE-L4-EVENT-TRIGGER-INVENTORY-01), cada uma com
--   justificativa (a)-(f). Aceite RESTRITO aos envelopes atuais; nova linha
--   só por nova L4 + nova decisão + mandato de correção — nunca por nome.
--   Os pinos md5 foram calculados sobre o corpo das definições no
--   repositório (2206, 2207 e schema/2095). Se o LIVE divergir do
--   repositório, o resultado é ALLOWLIST_MISMATCH ⇒ STOP para adjudicação —
--   nunca PASS.
--   Escopo do gate nesta rodada: as 5 tabelas EC. card_variant, staging, job,
--   game e action log são inventariados em d_p7_*, sem bloquear E01/E02.
-- ============================================================================
WITH
tbl(name, touched_now, gate_scope) AS (
    VALUES ('card_edition_context_trait',                  true,  true),
           ('card_edition_context_profile',                true,  true),
           ('card_edition_context_profile_trait',          false, true),
           ('card_edition_context_external_mapping',       true,  true),
           ('card_edition_context_external_mapping_trait', false, true),
           ('card_variant',                                false, false),
           ('catalog_variant_import_job',                  false, false),
           ('catalog_variant_import_row',                  false, false),
           ('catalog_admin_action_log',                    false, false),
           ('game',                                        false, false)
),
rel AS (
    SELECT t.name, t.touched_now, t.gate_scope, to_regclass('public.' || t.name) AS oid FROM tbl t
),
-- ------------------------------------------------------------------------
-- P6 — sequences ligadas às tabelas (OWNED BY / identity ou default nextval)
-- ------------------------------------------------------------------------
seq AS (
    SELECT r.name AS table_name, s.oid::regclass::text AS sequence_name, 'owned_by' AS link
      FROM rel r
      JOIN pg_depend d ON d.refobjid = r.oid AND d.classid = 'pg_class'::regclass AND d.deptype IN ('a','i')
      JOIN pg_class s ON s.oid = d.objid AND s.relkind = 'S'
    UNION
    SELECT r.name, NULL, 'default:' || a.attname || '=' || pg_get_expr(ad.adbin, ad.adrelid)
      FROM rel r
      JOIN pg_attrdef ad ON ad.adrelid = r.oid
      JOIN pg_attribute a ON a.attrelid = ad.adrelid AND a.attnum = ad.adnum
     WHERE pg_get_expr(ad.adbin, ad.adrelid) ILIKE '%nextval(%'
),
-- ------------------------------------------------------------------------
-- P7 v3 — padrões léxicos (um único lugar; tools/static_check.py os extrai
-- daqui para o modelo de controles negativos)
-- ------------------------------------------------------------------------
p7_re AS (
    SELECT
        $re$--[^\n]*|/\*([^*]|\*+[^*/])*\*+/|'([^']|'')*'$re$                                         AS lex,
        $re$(^|[^A-Za-z0-9_])[eE]'|\$[A-Za-z0-9_]*\$$re$                                               AS unsupported_raw,
        $re$"|[A-Za-z_][A-Za-z0-9_]*\s*\.\s*[A-Za-z_][A-Za-z0-9_]*\s*\.\s*[A-Za-z_][A-Za-z0-9_]*\s*\($re$ AS unsupported_lexed,
        $re$\mfor\s+(no\s+key\s+)?update\M|\mdo\s+update\M$re$                                        AS lock_or_upsert,
        $re$(?<![A-Za-z0-9_.$])([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)\s*\($re$             AS qcall,
        $re$(?<![A-Za-z0-9_.$])([A-Za-z_][A-Za-z0-9_]*)\s*\($re$                                       AS ucall,
        $re$\m(insert\s+into|update|delete\s+from|merge\s+into|truncate(\s+table)?)\s+(only\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*([A-Za-z_][A-Za-z0-9_]*)$re$ AS qdml,
        $re$\m(insert\s+into|update|delete\s+from|merge\s+into|truncate(\s+table)?)\s+(only\s+)?([A-Za-z_][A-Za-z0-9_]*)\M(?!\s*\.)$re$ AS udml,
        $re$(\mnet\.|\mhttp|pg_notify|dblink|pg_net|\mcopy\M|lo_import|lo_export|pg_read_|pg_ls_dir|set_config|pg_sleep|pg_terminate_backend|pg_cancel_backend)$re$ AS signal_raw,
        $re$\mexecute\M$re$                                                                             AS dynamic_lexed,
        $re$\m(create|alter|drop|grant|revoke|reindex|comment\s+on|security\s+label|refresh\s+materialized|import\s+foreign)\M$re$ AS ddl_lexed,
        $re$\minto\M$re$                                                                                AS sql_into_lexed
),
-- palavras sintáticas que podem preceder "(" sem serem chamadas de função
p7_keywords(word) AS (
    SELECT unnest(ARRAY[
        'if','elsif','while','exists','in','any','all','some','array','values','row','cast',
        'coalesce','nullif','greatest','least','extract','position','substring','trim','overlay',
        'and','or','not','on','using','into','as','from','select','where','returning','return',
        'query','then','else','when','case','over','filter','within','partition','table','set',
        'by','join','lateral','variadic','default','check','interval','timestamp','time','decimal',
        'numeric','char','character','varchar','bit','float','precision','is','distinct','like',
        'ilike','similar','between','loop','foreach','for','raise','exception','end','begin',
        'order','group','having','limit','offset','union','intersect','except','with','recursive',
        'returns','language','perform','strict','by','of','do'])
),
-- ------------------------------------------------------------------------
-- p7_allowlist — CLASSIFICAÇÃO COM IDENTIDADE (não por nome). Pinos:
-- identity_args = pg_get_function_identity_arguments(oid); lang = lanname;
-- secdef = prosecdef; vol = provolatile (NULL = não pinado); config =
-- proconfig exato; body_md5 = md5(prosrc com CRLF→LF) (calculado do
-- repositório, que é LF: o valor é o mesmo md5 do corpo do repositório);
-- c_symbol / extension para funções C de extensão.
-- ------------------------------------------------------------------------
p7_allowlist(nsp, proname, identity_args, lang, secdef, vol, config, body_md5, c_symbol, extension, class, justification) AS (
    VALUES
    ('internal','seal_edition_context_composition',                  '', 'plpgsql', true,  'v', ARRAY['search_path=""'], '6077409ac2b5de7f788076e3b4b3f0c0', NULL, NULL, 'SEAL',      '2206: sela traits_signature do próprio profile'),
    ('internal','guard_edition_context_composition_immutable',       '', 'plpgsql', true,  'v', ARRAY['search_path=""'], 'cfdcb500bb1090cd44c0e73d94c3f72e', NULL, NULL, 'GUARD',     '2206: N:N de profile selado é imutável'),
    ('internal','enforce_edition_context_signature_write',           '', 'plpgsql', true,  'v', ARRAY['search_path=""'], 'caa2e4d40d8e4995e217d7284f9d6c3b', NULL, NULL, 'GUARD',     '2206: selo divergente/imutável'),
    ('internal','guard_edition_context_trait_active',                '', 'plpgsql', true,  'v', ARRAY['search_path=""'], '68fb05f1c23db63a59611b0a12f79edd', NULL, NULL, 'GUARD',     '2206: trait inativo'),
    ('internal','normalize_edition_context_external_mapping',        '', 'plpgsql', true,  'v', ARRAY['search_path=""'], '15ea6245b8b8ce2173abb3d6b72c6736', NULL, NULL, 'NORMALIZE', '2207: normaliza token/escopo'),
    ('internal','enforce_edition_context_mapping_header',            '', 'plpgsql', true,  'v', ARRAY['search_path=""'], '9e5fba31721c5e84212bd2116d3fa214', NULL, NULL, 'GUARD',     '2207: identidade imutável + lifecycle'),
    ('internal','seal_edition_context_external_mapping',             '', 'plpgsql', true,  'v', ARRAY['search_path=""'], '49a4ea4b34ccf06a4efdcf06270c52eb', NULL, NULL, 'SEAL',      '2207: sela traits_signature do próprio mapping'),
    ('internal','guard_edition_context_mapping_composition_immutable','', 'plpgsql', true,  'v', ARRAY['search_path=""'], 'ad0c472cfa82c71ee955d9b653755bdc', NULL, NULL, 'GUARD',     '2207: N:N de mapping selado é imutável'),
    ('internal','enforce_edition_context_mapping_signature_write',   '', 'plpgsql', true,  'v', ARRAY['search_path=""'], '28084443cf6f32f9336d470ca16b7e72', NULL, NULL, 'GUARD',     '2207: selo divergente/imutável'),
    ('public',  'normalize_external_catalog_value',                  'p_value text', 'sql', false, 's', ARRAY['search_path=""'], '1fdc2e7ebe2297f8db85be4aad2e5d33', NULL, NULL, 'PURE', '2095: upper/unaccent/trim/regexp_replace'),
    ('extensions','unaccent',                                         'text',               'c', false, NULL, NULL::text[], NULL, 'unaccent_dict', 'unaccent', 'PURE_EXT', 'extensão unaccent (C)'),
    ('extensions','unaccent',                                         'regdictionary, text','c', false, NULL, NULL::text[], NULL, 'unaccent_dict', 'unaccent', 'PURE_EXT', 'extensão unaccent (C), sobrecarga alcançada por nome')
),
-- nomes de pg_catalog que NUNCA podem aparecer (qualificados ou não)
p7_denylist(proname) AS (
    VALUES ('pg_notify'),('set_config'),('pg_sleep'),('pg_sleep_for'),('pg_sleep_until'),
           ('pg_terminate_backend'),('pg_cancel_backend'),('lo_import'),('lo_export'),
           ('pg_read_file'),('pg_read_binary_file'),('pg_ls_dir'),('pg_stat_file'),
           ('pg_advisory_lock'),('pg_advisory_xact_lock'),('pg_reload_conf'),('pg_rotate_logfile'),
           ('pg_switch_wal'),('pg_create_restore_point'),('txid_current'),('pg_current_xact_id'),
           ('dblink'),('dblink_exec')
),
p7_roots AS (
    SELECT tg.tgfoid AS fn, r.name AS table_name, r.gate_scope, 'trigger ' || tg.tgname AS via
      FROM rel r JOIN pg_trigger tg ON tg.tgrelid = r.oid AND NOT tg.tgisinternal
    UNION
    SELECT d.refobjid, r.name, r.gate_scope, 'check ' || c.conname
      FROM rel r JOIN pg_constraint c ON c.conrelid = r.oid
      JOIN pg_depend d ON d.classid = 'pg_constraint'::regclass AND d.objid = c.oid
                      AND d.refclassid = 'pg_proc'::regclass
    UNION
    SELECT d.refobjid, r.name, r.gate_scope, 'default ' || a.attname
      FROM rel r JOIN pg_attrdef ad ON ad.adrelid = r.oid
      JOIN pg_attribute a ON a.attrelid = ad.adrelid AND a.attnum = ad.adnum
      JOIN pg_depend d ON d.classid = 'pg_attrdef'::regclass AND d.objid = ad.oid
                      AND d.refclassid = 'pg_proc'::regclass
    UNION
    SELECT d.refobjid, r.name, r.gate_scope, 'index ' || i.indexrelid::regclass::text
      FROM rel r JOIN pg_index i ON i.indrelid = r.oid
      JOIN pg_depend d ON d.classid = 'pg_class'::regclass AND d.objid = i.indexrelid
                      AND d.refclassid = 'pg_proc'::regclass
),
p7_reach AS (
    WITH RECURSIVE walk(fn, table_name, gate_scope, via, depth, path) AS (
        SELECT fn, table_name, gate_scope, via, 1, ARRAY[fn] FROM p7_roots
        UNION ALL
        SELECT callee.oid, w.table_name, w.gate_scope, w.via, w.depth + 1, w.path || callee.oid
          FROM walk w
          JOIN pg_proc caller ON caller.oid = w.fn
          CROSS JOIN p7_re re
          CROSS JOIN LATERAL regexp_matches(regexp_replace(caller.prosrc, re.lex, ' ', 'g'), re.qcall, 'g') AS m
          JOIN pg_namespace ns ON ns.nspname = lower(m[1])
          JOIN pg_proc callee ON callee.pronamespace = ns.oid AND callee.proname = lower(m[2])
         WHERE w.depth < 8 AND NOT callee.oid = ANY (w.path)
    )
    SELECT * FROM walk
),
p7_fn AS (
    SELECT DISTINCT ON (x.fn, x.gate_scope)
           x.fn, x.gate_scope, x.table_name, x.via, x.depth,
           n.nspname, p.proname, n.nspname || '.' || p.proname AS fqname,
           pg_get_function_identity_arguments(p.oid) AS identity_args,
           l.lanname AS language, p.prosecdef, p.provolatile::text AS vol, p.proconfig, p.prosrc,
           regexp_replace(p.prosrc, (SELECT lex FROM p7_re), ' ', 'g') AS lexed
      FROM p7_reach x
      JOIN pg_proc p ON p.oid = x.fn
      JOIN pg_namespace n ON n.oid = p.pronamespace
      JOIN pg_language l ON l.oid = p.prolang
     ORDER BY x.fn, x.gate_scope, x.depth
),
p7_class AS (
    SELECT f.*,
           a.class AS allow_class,
           CASE
             WHEN f.nspname = 'pg_catalog' AND f.proname IN (SELECT proname FROM p7_denylist) THEN 'DENIED'
             WHEN f.nspname = 'pg_catalog' THEN 'BUILTIN'
             WHEN a.nsp IS NULL THEN 'UNCLASSIFIED'
             WHEN f.language IS DISTINCT FROM a.lang
               OR f.prosecdef IS DISTINCT FROM a.secdef
               OR (a.vol IS NOT NULL AND f.vol IS DISTINCT FROM a.vol)
               OR (a.config IS NOT NULL AND f.proconfig IS DISTINCT FROM a.config)
               OR (a.body_md5 IS NOT NULL
                   AND md5(replace(f.prosrc, chr(13) || chr(10), chr(10))) IS DISTINCT FROM a.body_md5)
               OR (a.c_symbol IS NOT NULL AND f.prosrc IS DISTINCT FROM a.c_symbol)
               OR (a.extension IS NOT NULL AND NOT EXISTS (
                     SELECT 1 FROM pg_depend d JOIN pg_extension e ON e.oid = d.refobjid
                      WHERE d.classid = 'pg_proc'::regclass AND d.objid = f.fn
                        AND d.refclassid = 'pg_extension'::regclass AND d.deptype = 'e'
                        AND e.extname = a.extension))
               THEN 'ALLOWLIST_MISMATCH'
             ELSE a.class
           END AS class
      FROM p7_fn f
      LEFT JOIN p7_allowlist a
             ON a.nsp = f.nspname AND a.proname = f.proname AND a.identity_args = f.identity_args
),
p7_flags AS (
    SELECT c.*,
           (c.language NOT IN ('c','internal') AND c.prosrc ~* (SELECT signal_raw FROM p7_re))      AS external_signal,
           (c.language = 'plpgsql'            AND c.lexed  ~* (SELECT dynamic_lexed FROM p7_re))   AS dynamic_sql,
           (c.language NOT IN ('c','internal')
            AND (c.prosrc ~ (SELECT unsupported_raw FROM p7_re)
                 OR c.lexed ~ (SELECT unsupported_lexed FROM p7_re)))                                AS unsupported_lexeme,
           (c.nspname <> 'pg_catalog' AND c.language NOT IN ('c','internal')
            AND NOT (c.proconfig IS NOT NULL
                     AND (SELECT count(*) FROM unnest(c.proconfig) AS e(v) WHERE e.v LIKE 'search_path=%') = 1
                     AND 'search_path=""' = ANY (c.proconfig)))                                      AS search_path_unsafe,
           (c.language NOT IN ('c','internal')
            AND (c.lexed ~* (SELECT ddl_lexed FROM p7_re)
                 OR (c.language = 'sql' AND c.lexed ~* (SELECT sql_into_lexed FROM p7_re))))        AS ddl_statement
      FROM p7_class c
),
-- texto analisável: sem comentários/literais e com FOR UPDATE / DO UPDATE
-- neutralizados (não são DML)
p7_text AS (
    SELECT f.fn, f.fqname, f.gate_scope, f.language,
           regexp_replace(f.lexed, (SELECT lock_or_upsert FROM p7_re), ' ', 'gi') AS t
      FROM p7_flags f
     WHERE f.language NOT IN ('c','internal')
),
-- chamadas qualificadas que não resolvem para função nem relação
p7_unresolved_qualified AS (
    SELECT DISTINCT t.fqname AS caller, t.gate_scope, lower(m[1]) || '.' || lower(m[2]) AS reference,
           'QUALIFIED_CALL_UNRESOLVED' AS kind
      FROM p7_text t
      CROSS JOIN LATERAL regexp_matches(t.t, (SELECT qcall FROM p7_re), 'g') AS m
     WHERE NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                        WHERE n.nspname = lower(m[1]) AND p.proname = lower(m[2]))
       AND NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                        WHERE n.nspname = lower(m[1]) AND c.relname = lower(m[2]))
),
-- chamadas NÃO qualificadas: palavra-chave, função/tipo de pg_catalog, ou STOP
p7_unqualified_calls AS (
    SELECT DISTINCT t.fqname AS caller, t.gate_scope, lower(m[1]) AS name,
           CASE
             WHEN lower(m[1]) IN (SELECT word FROM p7_keywords) THEN 'KEYWORD'
             WHEN lower(m[1]) IN (SELECT proname FROM p7_denylist) THEN 'DENIED'
             WHEN EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace = 'pg_catalog'::regnamespace
                            AND p.proname = lower(m[1])) THEN 'BUILTIN'
             WHEN EXISTS (SELECT 1 FROM pg_type ty WHERE ty.typnamespace = 'pg_catalog'::regnamespace
                            AND ty.typname = lower(m[1])) THEN 'BUILTIN_TYPE'
             ELSE 'UNRESOLVED'
           END AS resolution
      FROM p7_text t
      CROSS JOIN LATERAL regexp_matches(t.t, (SELECT ucall FROM p7_re), 'g') AS m
),
-- DML com alvo qualificado: precisa existir e estar no escopo
p7_writes AS (
    SELECT DISTINCT t.fqname AS writer, t.gate_scope,
           lower(w[4]) || '.' || lower(w[5]) AS target,
           to_regclass(lower(w[4]) || '.' || lower(w[5])) IS NOT NULL AS target_exists
      FROM p7_text t
      CROSS JOIN LATERAL regexp_matches(t.t, (SELECT qdml FROM p7_re), 'gi') AS w
),
-- DML com alvo NÃO qualificado: sempre STOP
p7_unqualified_writes AS (
    SELECT DISTINCT t.fqname AS writer, t.gate_scope, lower(w[1]) AS verb, lower(w[4]) AS target
      FROM p7_text t
      CROSS JOIN LATERAL regexp_matches(t.t, (SELECT udml FROM p7_re), 'gi') AS w
),
p7_rules AS (
    SELECT r.name AS table_name, rw.rulename::text AS rule, rw.ev_type::text AS event
      FROM rel r JOIN pg_rewrite rw ON rw.ev_class = r.oid
     WHERE rw.rulename <> '_RETURN'
),
-- ------------------------------------------------------------------------
-- P7-EVT — event triggers: inventário integral (identidade completa)
-- ------------------------------------------------------------------------
evt AS (
    SELECT e.evtname::text                                                       AS name,
           e.evtevent::text                                                      AS event,
           e.evtenabled::text                                                    AS enabled,
           e.evttags                                                             AS tags,
           pg_get_userbyid(e.evtowner)                                           AS owner,
           n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS fn,
           l.lanname                                                             AS fn_language,
           pg_get_userbyid(p.proowner)                                           AS fn_owner,
           p.prosecdef                                                           AS fn_secdef,
           p.proconfig                                                           AS fn_config,
           (SELECT x.extname::text
              FROM pg_depend d
              JOIN pg_extension x ON x.oid = d.refobjid
             WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid
               AND d.refclassid = 'pg_extension'::regclass AND d.deptype = 'e') AS fn_extension,
           md5(p.prosrc)                                                         AS fn_md5_raw,
           md5(replace(p.prosrc, chr(13) || chr(10), chr(10)))                   AS fn_md5_lf
      FROM pg_event_trigger e
      JOIN pg_proc p      ON p.oid = e.evtfoid
      JOIN pg_namespace n ON n.oid = p.pronamespace
      JOIN pg_language l  ON l.oid = p.prolang
),
-- EVT-ALLOWLIST — exceção INDIVIDUAL por identidade completa (12 atributos),
-- só para evento exclusivamente DDL, cada uma com justificativa própria e
-- não vazia. Conteúdo: EXATAMENTE as 6 identidades aprovadas em D-9, copiadas
-- literalmente da saída da L4 (LIVE-STAGE1-EXECUTION-RECORD.md rev. 1.5,
-- md5 da saída fc0d8cf7…). Qualquer alteração de atributo no LIVE, trigger
-- adicional ou linha nova sem nova L4/decisão/mandato ⇒ STOP.
evt_allowlist(name, event, tags, enabled, owner, fn, fn_language, fn_owner, fn_secdef, fn_config, fn_extension, fn_md5_lf, justification) AS (
    VALUES
    ('issue_graphql_placeholder', 'sql_drop', ARRAY['DROP EXTENSION']::text[], 'O', 'supabase_admin', 'extensions.set_graphql_placeholder()', 'plpgsql', 'supabase_admin', false, ARRAY['search_path=""']::text[], NULL::text, 'a2bc2d00b2cc2f5e8d2d6b8d73e2c360', 'D-9 APROVADA, ACEITE EXCEPCIONAL. (a) Evidência L4 BATCH12-2830-LIVE-L4-EVENT-TRIGGER-INVENTORY-01 (2026-09-27T02:08:42Z, HEAD 9a4cff16, L4 md5 f3670eb8, triggers_md5 3b42b3148691f7cf68bae72733739308, inventário 6 = catálogo 6), identidade de 12 atributos copiada literalmente, fn_md5_lf a2bc2d00b2cc2f5e8d2d6b8d73e2c360. (b) Origem: event trigger da plataforma Supabase (supabase/postgres), dono supabase_admin, função em extensions, SECURITY INVOKER, search_path vazio, sem extensão. (c) Evento sql_drop, tags {DROP EXTENSION}, e age só se objetos do schema graphql_public forem removidos. (d) Efeito real: CREATE OR REPLACE FUNCTION graphql_public.graphql (função placeholder que devolve erro pg_graphql não habilitado). Aceite excepcional pela criação da função placeholder. Não toca public nem as tabelas EC. (e) Os envelopes atuais (L1, L2, L3, L4, E00, E01, E02, E99) não emitem comando da matriz de disparo de event triggers e o fecho P7 não contém DDL (g_p7_no_ddl), portanto não há caminho de disparo pelos envelopes atuais. Aceite restrito aos envelopes atuais: não autoriza novas operações, migrations nem DDL. (f) Reavaliar se qualquer dos 12 atributos mudar (o gate g_evt_all_adjudicated reprova sozinho), se um envelope passar a emitir DDL ou comando de extensão, ou antes de qualquer nova operação ou migration.'),
    ('issue_pg_cron_access', 'ddl_command_end', ARRAY['CREATE EXTENSION']::text[], 'O', 'supabase_admin', 'extensions.grant_pg_cron_access()', 'plpgsql', 'supabase_admin', false, ARRAY['search_path=""']::text[], NULL::text, '3a3917aad6ddd66182bf45b7490c3029', 'D-9 APROVADA, ACEITE EXCEPCIONAL. (a) Evidência L4 BATCH12-2830-LIVE-L4-EVENT-TRIGGER-INVENTORY-01 (2026-09-27T02:08:42Z, HEAD 9a4cff16, L4 md5 f3670eb8, triggers_md5 3b42b3148691f7cf68bae72733739308, inventário 6 = catálogo 6), identidade de 12 atributos copiada literalmente, fn_md5_lf 3a3917aad6ddd66182bf45b7490c3029. (b) Origem: event trigger da plataforma Supabase (supabase/postgres), dono supabase_admin, função em extensions, SECURITY INVOKER, search_path vazio, sem extensão. (c) Evento ddl_command_end, tags {CREATE EXTENSION}, e age só se a extensão criada for pg_cron. (d) Efeito real: GRANT USAGE no schema cron, ALTER DEFAULT PRIVILEGES no schema cron (inclusive FOR USER supabase_admin), GRANT ALL nas tabelas de cron, REVOKE e GRANT SELECT em cron.job e REVOKE TRIGGER em cron.job_run_details, tudo para postgres. Aceite excepcional incluindo ALTER DEFAULT PRIVILEGES. (e) Os envelopes atuais (L1, L2, L3, L4, E00, E01, E02, E99) não emitem comando da matriz de disparo de event triggers e o fecho P7 não contém DDL (g_p7_no_ddl), portanto não há caminho de disparo pelos envelopes atuais. Aceite restrito aos envelopes atuais: não autoriza novas operações, migrations nem DDL. (f) Reavaliar se qualquer dos 12 atributos mudar (o gate g_evt_all_adjudicated reprova sozinho), se um envelope passar a emitir DDL ou comando de extensão, ou antes de qualquer nova operação ou migration.'),
    ('issue_pg_graphql_access', 'ddl_command_end', ARRAY['CREATE EXTENSION']::text[], 'O', 'supabase_admin', 'extensions.grant_pg_graphql_access()', 'plpgsql', 'supabase_admin', false, ARRAY['search_path=""']::text[], NULL::text, 'dd3f3e2bb94cff45ef24b9cecb6af1c8', 'D-9 APROVADA, ACEITE EXCEPCIONAL. (a) Evidência L4 BATCH12-2830-LIVE-L4-EVENT-TRIGGER-INVENTORY-01 (2026-09-27T02:08:42Z, HEAD 9a4cff16, L4 md5 f3670eb8, triggers_md5 3b42b3148691f7cf68bae72733739308, inventário 6 = catálogo 6), identidade de 12 atributos copiada literalmente, fn_md5_lf dd3f3e2bb94cff45ef24b9cecb6af1c8. (b) Origem: event trigger da plataforma Supabase (supabase/postgres), dono supabase_admin, função em extensions, SECURITY INVOKER, search_path vazio, sem extensão. (c) Evento ddl_command_end, tags {CREATE EXTENSION}, e age só se a extensão criada for pg_graphql. (d) Efeito real: DROP FUNCTION IF EXISTS e CREATE OR REPLACE FUNCTION graphql_public.graphql, ALTER EXTENSION pg_graphql ADD FUNCTION, GRANT USAGE nos schemas graphql e graphql_public e GRANT EXECUTE em graphql.resolve para postgres, anon, authenticated e service_role. Aceite excepcional pelos DDLs e pelas concessões de privilégios. (e) Os envelopes atuais (L1, L2, L3, L4, E00, E01, E02, E99) não emitem comando da matriz de disparo de event triggers e o fecho P7 não contém DDL (g_p7_no_ddl), portanto não há caminho de disparo pelos envelopes atuais. Aceite restrito aos envelopes atuais: não autoriza novas operações, migrations nem DDL. (f) Reavaliar se qualquer dos 12 atributos mudar (o gate g_evt_all_adjudicated reprova sozinho), se um envelope passar a emitir DDL ou comando de extensão, ou antes de qualquer nova operação ou migration.'),
    ('issue_pg_net_access', 'ddl_command_end', ARRAY['CREATE EXTENSION']::text[], 'O', 'supabase_admin', 'extensions.grant_pg_net_access()', 'plpgsql', 'supabase_admin', false, ARRAY['search_path=""']::text[], NULL::text, '2ee4e6920eeba3068bcfa838105352e2', 'D-9 APROVADA, ACEITE EXCEPCIONAL. (a) Evidência L4 BATCH12-2830-LIVE-L4-EVENT-TRIGGER-INVENTORY-01 (2026-09-27T02:08:42Z, HEAD 9a4cff16, L4 md5 f3670eb8, triggers_md5 3b42b3148691f7cf68bae72733739308, inventário 6 = catálogo 6), identidade de 12 atributos copiada literalmente, fn_md5_lf 2ee4e6920eeba3068bcfa838105352e2. (b) Origem: event trigger da plataforma Supabase (supabase/postgres), dono supabase_admin, função em extensions, SECURITY INVOKER, search_path vazio, sem extensão. (c) Evento ddl_command_end, tags {CREATE EXTENSION}, e age só se a extensão criada for pg_net. (d) Efeito real: pode executar CREATE USER supabase_functions_admin, GRANT USAGE no schema net para supabase_functions_admin, postgres, anon, authenticated e service_role e, nas versões antigas do pg_net, ALTER FUNCTION net.http_get e net.http_post SECURITY DEFINER com search_path net, REVOKE de PUBLIC e GRANT EXECUTE aos mesmos papéis. Aceite excepcional incluindo CREATE USER e as concessões de acesso à rede. (e) Os envelopes atuais (L1, L2, L3, L4, E00, E01, E02, E99) não emitem comando da matriz de disparo de event triggers e o fecho P7 não contém DDL (g_p7_no_ddl), portanto não há caminho de disparo pelos envelopes atuais. Aceite restrito aos envelopes atuais: não autoriza novas operações, migrations nem DDL. (f) Reavaliar se qualquer dos 12 atributos mudar (o gate g_evt_all_adjudicated reprova sozinho), se um envelope passar a emitir DDL ou comando de extensão, ou antes de qualquer nova operação ou migration.'),
    ('pgrst_ddl_watch', 'ddl_command_end', NULL::text[], 'O', 'supabase_admin', 'extensions.pgrst_ddl_watch()', 'plpgsql', 'supabase_admin', false, ARRAY['search_path=""']::text[], NULL::text, '7f27b8118fea5c88b0164331292859e3', 'D-9 APROVADA, ACEITE ORDINÁRIO. (a) Evidência L4 BATCH12-2830-LIVE-L4-EVENT-TRIGGER-INVENTORY-01 (2026-09-27T02:08:42Z, HEAD 9a4cff16, L4 md5 f3670eb8, triggers_md5 3b42b3148691f7cf68bae72733739308, inventário 6 = catálogo 6), identidade de 12 atributos copiada literalmente, fn_md5_lf 7f27b8118fea5c88b0164331292859e3. (b) Origem: event trigger da plataforma Supabase (supabase/postgres), dono supabase_admin, função em extensions, SECURITY INVOKER, search_path vazio, sem extensão. (c) Evento ddl_command_end, tags NULL: dispara em qualquer DDL (superfície ampla, aceita expressamente). (d) Efeito real: NOTIFY pgrst reload schema para os command tags de schema, tabela, tabela estrangeira, view, view materializada, função, trigger, tipo, regra e COMMENT fora de pg_temp. Sem escrita em tabela, sem SQL dinâmico, sem rede. (e) Os envelopes atuais (L1, L2, L3, L4, E00, E01, E02, E99) não emitem comando da matriz de disparo de event triggers e o fecho P7 não contém DDL (g_p7_no_ddl), portanto não há caminho de disparo pelos envelopes atuais. Aceite restrito aos envelopes atuais: não autoriza novas operações, migrations nem DDL. (f) Reavaliar se qualquer dos 12 atributos mudar (o gate g_evt_all_adjudicated reprova sozinho), se um envelope passar a emitir DDL ou comando de extensão, ou antes de qualquer nova operação ou migration.'),
    ('pgrst_drop_watch', 'sql_drop', NULL::text[], 'O', 'supabase_admin', 'extensions.pgrst_drop_watch()', 'plpgsql', 'supabase_admin', false, ARRAY['search_path=""']::text[], NULL::text, 'bc09cc3003d66f91844af4cb05e203b7', 'D-9 APROVADA, ACEITE ORDINÁRIO. (a) Evidência L4 BATCH12-2830-LIVE-L4-EVENT-TRIGGER-INVENTORY-01 (2026-09-27T02:08:42Z, HEAD 9a4cff16, L4 md5 f3670eb8, triggers_md5 3b42b3148691f7cf68bae72733739308, inventário 6 = catálogo 6), identidade de 12 atributos copiada literalmente, fn_md5_lf bc09cc3003d66f91844af4cb05e203b7. (b) Origem: event trigger da plataforma Supabase (supabase/postgres), dono supabase_admin, função em extensions, SECURITY INVOKER, search_path vazio, sem extensão. (c) Evento sql_drop, tags NULL: dispara em qualquer drop (superfície ampla, aceita expressamente). (d) Efeito real: NOTIFY pgrst reload schema para drops não temporários de schema, tabela, tabela estrangeira, view, view materializada, função, trigger, tipo e regra. Sem escrita em tabela, sem SQL dinâmico, sem rede. (e) Os envelopes atuais (L1, L2, L3, L4, E00, E01, E02, E99) não emitem comando da matriz de disparo de event triggers e o fecho P7 não contém DDL (g_p7_no_ddl), portanto não há caminho de disparo pelos envelopes atuais. Aceite restrito aos envelopes atuais: não autoriza novas operações, migrations nem DDL. (f) Reavaliar se qualquer dos 12 atributos mudar (o gate g_evt_all_adjudicated reprova sozinho), se um envelope passar a emitir DDL ou comando de extensão, ou antes de qualquer nova operação ou migration.')
),
evt_unadjudicated AS (
    SELECT e.*
      FROM evt e
     WHERE e.enabled <> 'D'
       AND NOT EXISTS (SELECT 1 FROM evt_allowlist a
                        WHERE a.event IN ('ddl_command_start','ddl_command_end','sql_drop','table_rewrite')
                          AND a.name = e.name AND a.event = e.event
                          AND a.tags IS NOT DISTINCT FROM e.tags
                          AND a.enabled = e.enabled AND a.owner = e.owner
                          AND a.fn = e.fn AND a.fn_language = e.fn_language
                          AND a.fn_owner = e.fn_owner AND a.fn_md5_lf = e.fn_md5_lf
                          AND a.fn_secdef = e.fn_secdef
                          AND a.fn_config IS NOT DISTINCT FROM e.fn_config
                          AND a.fn_extension IS NOT DISTINCT FROM e.fn_extension
                          AND NULLIF(btrim(a.justification), '') IS NOT NULL)
),
pub AS (
    SELECT pt.pubname::text AS publication, pt.tablename::text AS table_name
      FROM pg_publication_tables pt JOIN rel r ON r.name = pt.tablename AND pt.schemaname = 'public'
),
-- RLS / dono (o harness assume bypass por ser dono ou superusuário, sem FORCE)
own AS (
    SELECT r.name, c.relrowsecurity AS rls, c.relforcerowsecurity AS force_rls,
           pg_get_userbyid(c.relowner) AS owner
      FROM rel r JOIN pg_class c ON c.oid = r.oid
),
-- ------------------------------------------------------------------------
-- P10 — BASELINE DA RODADA (bloco idêntico em E00 e E99; verificado pelo
-- tools/static_check.py). Timestamps em UTC com formato fixo: independem do
-- TimeZone da sessão.
-- ------------------------------------------------------------------------
base AS (
    -- BASELINE-BUILDER:BEGIN
    SELECT jsonb_build_object(
        'trait',                  (SELECT count(*) FROM public.card_edition_context_trait),
        'profile',                (SELECT count(*) FROM public.card_edition_context_profile),
        'profile_trait',          (SELECT count(*) FROM public.card_edition_context_profile_trait),
        'mapping',                (SELECT count(*) FROM public.card_edition_context_external_mapping),
        'mapping_trait',          (SELECT count(*) FROM public.card_edition_context_external_mapping_trait),
        'mapping_null_signature', (SELECT count(*) FROM public.card_edition_context_external_mapping WHERE traits_signature IS NULL),
        'card_variant',           (SELECT count(*) FROM public.card_variant),
        'card_variant_ec_nonnull',(SELECT count(*) FROM public.card_variant WHERE edition_context_profile_id IS NOT NULL),
        'staging_rows',           (SELECT count(*) FROM public.catalog_variant_import_row),
        'staging_max_upd_utc',    (SELECT to_char(max(updated_at) AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') FROM public.catalog_variant_import_row),
        'staging_status',         (SELECT jsonb_object_agg(k, n) FROM (SELECT validation_status || '/' || persistence_status AS k, count(*) AS n
                                     FROM public.catalog_variant_import_row GROUP BY 1) s),
        'operational_tristate',   (SELECT jsonb_build_object(
                                        'U', count(*) FILTER (WHERE jsonb_typeof(r.normalized_data -> 'edition_context_profile_id') = 'string'),
                                        'N', count(*) FILTER (WHERE jsonb_typeof(r.normalized_data -> 'edition_context_profile_id') = 'null'),
                                        'A', count(*) FILTER (WHERE NOT jsonb_exists(r.normalized_data, 'edition_context_profile_id')))
                                     FROM public.catalog_variant_import_row r
                                     JOIN public.catalog_variant_import_job j ON j.id = r.job_id
                                    WHERE j.status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING')
                                      AND r.persistence_status = 'PENDING'),
        'cancelled_without_key',  (SELECT jsonb_build_object(
                                        'total', count(*),
                                        'valid_pending', count(*) FILTER (WHERE r.validation_status = 'VALID' AND r.persistence_status = 'PENDING'))
                                     FROM public.catalog_variant_import_row r
                                     JOIN public.catalog_variant_import_job j ON j.id = r.job_id
                                    WHERE j.status = 'CANCELLED'
                                      AND NOT jsonb_exists(r.normalized_data, 'edition_context_profile_id')),
        'lineage',                (SELECT jsonb_build_object('resulting', count(resulting_variant_id), 'matched', count(matched_variant_id))
                                     FROM public.catalog_variant_import_row),
        'jobs',                   (SELECT count(*) FROM public.catalog_variant_import_job),
        'jobs_by_status',         (SELECT jsonb_object_agg(status, n) FROM (SELECT status, count(*) AS n
                                     FROM public.catalog_variant_import_job GROUP BY 1) s),
        'jobs_max_upd_utc',       (SELECT to_char(max(updated_at) AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') FROM public.catalog_variant_import_job),
        'jobs_in_flight',         (SELECT count(*) FROM public.catalog_variant_import_job WHERE status IN ('RECEIVED','PROCESSING','CONFIRMING')),
        'marker_trait',           (SELECT count(*) FROM public.card_edition_context_trait WHERE code LIKE '%H2830%'),
        'marker_profile',         (SELECT count(*) FROM public.card_edition_context_profile WHERE code LIKE '%H2830%'),
        'marker_mapping',         (SELECT count(*) FROM public.card_edition_context_external_mapping WHERE normalized_token LIKE '%H2830%')
    ) AS b
    -- BASELINE-BUILDER:END
),
-- ------------------------------------------------------------------------
-- BASELINE CANÔNICO DO FREEZE (constantes; bloco idêntico em E00 e E99)
-- Fontes: EXECUTION-BATCHES.md Batch 11 (postcheck 2216, 2026-09-26:
-- staging 26.127 e max(updated_at); jobs 145 = 63/71/8/3, 0 em voo, max;
-- card_variant 24.893, EC 0) · Batch 6 (847 / 415; 1.092 / 550 / 0) · Batch 2
-- (115 / 144 / 196 / 122; mappings sem selo 0) · BATCH12-2830-READINESS-
-- AUDIT-01 (SELECT LIVE 2026-09-26: distribuição staging_status; lineage
-- 23.955 / 1.129). Chaves SEM valor canônico registrado (mapping_trait,
-- action_log) ficam FORA daqui de propósito.
-- ------------------------------------------------------------------------
canon AS (
    -- FREEZE-CANON:BEGIN
    SELECT '{
        "trait": 115,
        "profile": 144,
        "profile_trait": 196,
        "mapping": 122,
        "mapping_null_signature": 0,
        "card_variant": 24893,
        "card_variant_ec_nonnull": 0,
        "staging_rows": 26127,
        "staging_max_upd_utc": "2026-09-20T19:57:04.771758Z",
        "staging_status": {"VALID/INSERTED": 23240, "VALID/UNCHANGED": 717, "VALID/PENDING": 415,
                           "NEEDS_REVIEW/PENDING": 1656, "NEEDS_REVIEW/UNCHANGED": 13,
                           "INVALID/UNCHANGED": 80, "INVALID/PENDING": 6},
        "operational_tristate": {"U": 1092, "N": 550, "A": 0},
        "cancelled_without_key": {"total": 847, "valid_pending": 415},
        "lineage": {"resulting": 23955, "matched": 1129},
        "jobs": 145,
        "jobs_by_status": {"STAGED": 63, "COMPLETED": 71, "FAILED": 8, "CANCELLED": 3},
        "jobs_max_upd_utc": "2026-09-19T00:48:41.964146Z",
        "jobs_in_flight": 0
    }'::jsonb AS c
    -- FREEZE-CANON:END
),
canon_diff AS (
    SELECT e.key, e.value AS canonical, (SELECT b FROM base) -> e.key AS live
      FROM canon, jsonb_each(canon.c) AS e
     WHERE (SELECT b FROM base) -> e.key IS DISTINCT FROM e.value
),
-- P11 — objetos citados pelos contratos de E01/E02
obj AS (
    SELECT jsonb_build_object(
        'constraints_1x', (SELECT count(*) FROM pg_constraint WHERE conname IN
            ('ck_cect_code_family_prefix','uq_cect_game_family_order','ck_cecp_signature_not_empty',
             'ck_cecp_signature_shape','ck_cecem_raw_field','fk_cecpt_profile','fk_cecpt_trait')),
        'indexes_1x',     (SELECT count(*) FROM unnest(ARRAY['uq_cecp_game_signature','uq_cecem_active_global',
            'uq_cecem_active_scoped','ix_cecem_token']) x(n) WHERE to_regclass('public.' || x.n) IS NOT NULL),
        'indexes_D',      (SELECT count(*) FROM unnest(ARRAY['uq_card_variant_identity','uq_cvir_row_identity',
            'uq_card_variant_card_order','uq_card_variant_one_default_per_card','uq_card_variant_id_card']) x(n)
            WHERE to_regclass('public.' || x.n) IS NOT NULL),
        'roles_anon_authenticated', (SELECT count(*) FROM pg_roles WHERE rolname IN ('anon','authenticated')),
        'game_pokemon',   (SELECT count(*) FROM public.game WHERE code = 'POKEMON'),
        'source_tcgdex',  (SELECT count(*) FROM public.asset_source WHERE code = 'TCGDEX')
    ) AS o
),
conc AS (
    SELECT jsonb_build_object(
        'other_sessions_in_txn', (SELECT count(*) FROM pg_stat_activity
                                   WHERE pid <> pg_backend_pid() AND datname = current_database()
                                     AND state IN ('active','idle in transaction','idle in transaction (aborted)')
                                     AND backend_type = 'client backend')
    ) AS c
),
sess AS (
    SELECT jsonb_build_object(
        'current_user',         current_user,
        'is_superuser',         (SELECT rolsuper FROM pg_roles WHERE rolname = current_user),
        'lock_timeout',         current_setting('lock_timeout'),
        'statement_timeout',    current_setting('statement_timeout'),
        'db_role_setting_rows', (SELECT count(*) FROM pg_db_role_setting),
        'server_version_num',   current_setting('server_version_num'),
        'session_replication_role', current_setting('session_replication_role'),
        'backend_pid',          pg_backend_pid(),
        'checked_at',           clock_timestamp()
    ) AS s
),
gates AS (
    SELECT
        ((SELECT o->>'constraints_1x' FROM obj)::int = 7
         AND (SELECT o->>'indexes_1x' FROM obj)::int = 4)                             AS g_objects_1x,
        (SELECT o->>'indexes_D' FROM obj)::int = 5                                    AS g_objects_D,
        (SELECT o->>'roles_anon_authenticated' FROM obj)::int = 2                     AS g_roles_1_12,
        (SELECT (s->>'server_version_num')::int >= 170000 FROM sess)                  AS g_pg17_maintain_privilege,
        ((SELECT o->>'game_pokemon' FROM obj)::int = 1
         AND (SELECT o->>'source_tcgdex' FROM obj)::int = 1)                          AS g_game_source,
        NOT EXISTS (SELECT 1 FROM canon_diff)                                         AS g_freeze_canonical_equal,
        NOT EXISTS (SELECT 1 FROM seq s JOIN rel r ON r.name = s.table_name
                     WHERE r.touched_now)                                             AS g_no_sequences_touched_now,
        NOT EXISTS (SELECT 1 FROM p7_flags WHERE gate_scope AND class IN ('UNCLASSIFIED','DENIED'))
                                                                                      AS g_p7_all_classified,
        NOT EXISTS (SELECT 1 FROM p7_flags WHERE gate_scope AND class = 'ALLOWLIST_MISMATCH')
                                                                                      AS g_p7_identity_pinned,
        NOT EXISTS (SELECT 1 FROM p7_flags WHERE gate_scope AND search_path_unsafe)   AS g_p7_search_path_safe,
        NOT EXISTS (SELECT 1 FROM p7_flags WHERE gate_scope AND (external_signal OR dynamic_sql))
                                                                                      AS g_p7_no_external_or_dynamic,
        NOT EXISTS (SELECT 1 FROM p7_flags WHERE gate_scope AND ddl_statement)        AS g_p7_no_ddl,
        NOT EXISTS (SELECT 1 FROM p7_flags WHERE gate_scope AND unsupported_lexeme)   AS g_p7_lexically_supported,
        (NOT EXISTS (SELECT 1 FROM p7_unresolved_qualified WHERE gate_scope)
         AND NOT EXISTS (SELECT 1 FROM p7_unqualified_calls WHERE gate_scope
                          AND resolution IN ('UNRESOLVED','DENIED')))                 AS g_p7_no_unresolved,
        NOT EXISTS (SELECT 1 FROM p7_unqualified_writes WHERE gate_scope)             AS g_p7_no_unqualified_dml,
        NOT EXISTS (SELECT 1 FROM p7_writes w WHERE w.gate_scope
                     AND (NOT w.target_exists
                          OR w.target NOT IN (SELECT 'public.' || name FROM rel WHERE gate_scope)))
                                                                                      AS g_p7_writes_in_scope,
        NOT EXISTS (SELECT 1 FROM p7_reach WHERE gate_scope AND depth >= 8)           AS g_p7_closure_complete,
        NOT EXISTS (SELECT 1 FROM p7_rules r JOIN rel ON rel.name = r.table_name
                     WHERE rel.gate_scope)                                            AS g_no_rules,
        NOT EXISTS (SELECT 1 FROM evt WHERE enabled <> 'D'
                     AND event NOT IN ('ddl_command_start','ddl_command_end','sql_drop','table_rewrite'))
                                                                                      AS g_evt_ddl_only,
        NOT EXISTS (SELECT 1 FROM evt_unadjudicated)                                  AS g_evt_all_adjudicated,
        (SELECT count(*) FROM pg_catalog.pg_event_trigger) = (SELECT count(*) FROM evt)
                                                                                      AS g_evt_inventory_complete,
        (NOT EXISTS (SELECT 1 FROM own o JOIN rel r ON r.name = o.name WHERE r.touched_now AND o.force_rls)
         AND ((SELECT s->>'is_superuser' FROM sess)::boolean
              OR NOT EXISTS (SELECT 1 FROM own o JOIN rel r ON r.name = o.name
                              WHERE r.touched_now AND o.owner <> current_user)))       AS g_rls_bypass,
        ((SELECT b->>'marker_trait' FROM base)::int = 0
         AND (SELECT b->>'marker_profile' FROM base)::int = 0
         AND (SELECT b->>'marker_mapping' FROM base)::int = 0)                        AS g_no_residue,
        (SELECT c->>'other_sessions_in_txn' FROM conc)::int = 0                       AS g_no_concurrency
)
SELECT to_jsonb(g)
    || jsonb_build_object(
        'gate_pass', (SELECT bool_and(v::boolean) FROM jsonb_each_text(to_jsonb(g)) AS e(k, v))
                     AND NOT EXISTS (SELECT 1 FROM jsonb_each_text(to_jsonb(g)) AS e(k, v) WHERE v IS NULL),
        'd_canon_diff',       COALESCE((SELECT jsonb_agg(to_jsonb(cd) ORDER BY cd.key) FROM canon_diff cd), '[]'::jsonb),
        'd_baseline',         (SELECT b FROM base),
        'd_baseline_md5',     (SELECT md5(b::text) FROM base),
        'd_sequences',        COALESCE((SELECT jsonb_agg(to_jsonb(s)) FROM seq s), '[]'::jsonb),
        'd_p7_functions',     COALESCE((SELECT jsonb_agg(jsonb_build_object(
                                  'fn', f.fqname || '(' || f.identity_args || ')', 'class', f.class,
                                  'language', f.language, 'root_table', f.table_name, 'via', f.via,
                                  'depth', f.depth, 'gate_scope', f.gate_scope,
                                  'body_md5', CASE WHEN f.language NOT IN ('c','internal') THEN md5(f.prosrc) END,
                                  'body_md5_lf', CASE WHEN f.language NOT IN ('c','internal')
                                                      THEN md5(replace(f.prosrc, chr(13) || chr(10), chr(10))) END,
                                  'cr_count', length(f.prosrc) - length(replace(f.prosrc, chr(13), '')),
                                  'crlf_count', (length(f.prosrc) - length(replace(f.prosrc, chr(13) || chr(10), ''))) / 2,
                                  'proconfig', f.proconfig, 'external_signal', f.external_signal,
                                  'dynamic_sql', f.dynamic_sql, 'unsupported_lexeme', f.unsupported_lexeme,
                                  'search_path_unsafe', f.search_path_unsafe, 'ddl_statement', f.ddl_statement)
                                  ORDER BY f.gate_scope DESC, f.class, f.fqname) FROM p7_flags f), '[]'::jsonb),
        'd_p7_eol_normalized', COALESCE((SELECT jsonb_agg(f.fqname || '(' || f.identity_args || ')' ORDER BY f.fqname)
                                  FROM p7_flags f
                                 WHERE f.gate_scope AND f.language NOT IN ('c','internal')
                                   AND md5(f.prosrc) <> md5(replace(f.prosrc, chr(13) || chr(10), chr(10)))), '[]'::jsonb),
        'd_p7_unresolved_qualified', COALESCE((SELECT jsonb_agg(to_jsonb(u)) FROM p7_unresolved_qualified u), '[]'::jsonb),
        'd_p7_unqualified_calls',    COALESCE((SELECT jsonb_agg(to_jsonb(u) ORDER BY u.caller, u.name) FROM p7_unqualified_calls u), '[]'::jsonb),
        'd_p7_writes',               COALESCE((SELECT jsonb_agg(to_jsonb(w) ORDER BY w.writer, w.target) FROM p7_writes w), '[]'::jsonb),
        'd_p7_unqualified_writes',   COALESCE((SELECT jsonb_agg(to_jsonb(w)) FROM p7_unqualified_writes w), '[]'::jsonb),
        'd_p7_rules',         COALESCE((SELECT jsonb_agg(to_jsonb(r)) FROM p7_rules r), '[]'::jsonb),
        'd_event_triggers',   COALESCE((SELECT jsonb_agg(to_jsonb(e) ORDER BY e.name) FROM evt e), '[]'::jsonb),
        'd_evt_catalog_count', (SELECT count(*) FROM pg_catalog.pg_event_trigger),
        'd_evt_unadjudicated', COALESCE((SELECT jsonb_agg(u.name ORDER BY u.name) FROM evt_unadjudicated u), '[]'::jsonb),
        'd_evt_allowlist_absent', COALESCE((SELECT jsonb_agg(a.name ORDER BY a.name) FROM evt_allowlist a
                                  WHERE NOT EXISTS (SELECT 1 FROM evt e WHERE e.name = a.name)), '[]'::jsonb),
        'd_publications',     COALESCE((SELECT jsonb_agg(to_jsonb(p)) FROM pub p), '[]'::jsonb),
        'd_ownership_rls',    COALESCE((SELECT jsonb_agg(to_jsonb(o)) FROM own o), '[]'::jsonb),
        'd_objects',          (SELECT o FROM obj),
        'd_concurrency',      (SELECT c FROM conc),
        'd_session',          (SELECT s FROM sess)
    ) AS e00_precheck
  FROM gates g;
