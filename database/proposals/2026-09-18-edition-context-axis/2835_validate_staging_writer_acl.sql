/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2835 - Regression gate: ACL do writer real do staging x funções do índice de identidade
Versão......: 1.0
Status......: PROPOSTA — read-only (um único SELECT). Não altera estado.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-04
Mandato.....: BATCH12-POST-UNFREEZE-CANARY-ACL-CORRECTION-01

Objetivo:
O primeiro canary real pós-UNFREEZE (SVE, job 3ec9c551-…) falhou com
"permission denied for function axis_identity_token". Os gates anteriores
provaram existência, integridade e semântica de uq_cvir_row_identity, mas
nunca confrontaram o PAPEL EFETIVO do writer (service_role, client da Edge
import-card-variants) com a ACL das funções chamadas pelas expressões dos
índices da tabela. Este gate fecha essa lacuna de forma direcionada: não
reabre nem reroda a 2830.

Gates (todos precisam ser true; gate_pass = AND de todos):
  g_sr_insert_row          service_role tem INSERT em catalog_variant_import_row
  g_sr_exec_token          service_role tem EXECUTE em axis_identity_token
  g_anon_no_exec_token     anon NÃO tem EXECUTE em axis_identity_token
  g_public_no_exec_token   PUBLIC sem entrada de EXECUTE na ACL da função
  g_auth_exec_preserved    authenticated mantém EXECUTE (estado vigente preservado)
  g_writer_execs_all_index_fns
                           CLASSE: service_role tem EXECUTE em TODA função
                           referenciada por índice/constraint/default de
                           catalog_variant_import_row (pg_depend). Pega qualquer
                           função futura no mesmo caminho, não só esta.
  g_fn_body_pinned         md5(prosrc) = 18682dce… (corpo da 2210, inalterado)
  g_fn_contract            IMMUTABLE, não-STRICT, SECURITY INVOKER, search_path=""
  g_idx_unique_valid_ready uq_cvir_row_identity unique/valid/ready
  g_idx_uses_token_both_axes
                           definição usa axis_identity_token para
                           printing_profile_id E edition_context_profile_id
  g_idx_dep_only_token     dependências pg_proc do índice = {axis_identity_token}
  g_guards_enabled         trg_cvir_normalized_shape (2214) e
                           trg_card_variant_edition_context_profile_game (2224)
                           habilitados (tgenabled = 'O')

Resultado esperado:
  ANTES da 2235 (estado do incidente): gate_pass = false, com
    g_sr_exec_token = false e g_writer_execs_all_index_fns = false
    (controle negativo: o gate detecta exatamente o defeito do canary).
  DEPOIS da 2235: gate_pass = true.

Fora do escopo SQL (verificar à parte, metadados Supabase, read-only):
  Edge import-card-variants inalterada — version = 15, verify_jwt = true,
  ezbr_sha256 = e60203f688ea7d99ddec36476f425a4a5e552d029984776c100194738ce59382.

Execução: MCP execute_sql, uma chamada, só SELECT.
================================================================
*/

WITH fn AS (
    SELECT to_regprocedure('internal.axis_identity_token(jsonb,text)') AS oid
),
idx AS (
    SELECT to_regclass('public.uq_cvir_row_identity') AS oid
),
fnmeta AS (
    SELECT p.*
      FROM pg_proc p, fn
     WHERE p.oid = fn.oid
),
row_fns AS (
    -- Funções referenciadas por índices, constraints e defaults da tabela de
    -- staging: exatamente o que o INSERT do writer avalia com o papel efetivo.
    -- (Funções de trigger ficam de fora: o Postgres só verifica EXECUTE delas
    -- no CREATE TRIGGER, não no disparo.)
    SELECT DISTINCT d.refobjid AS fn_oid
      FROM pg_depend d
     WHERE d.refclassid = 'pg_proc'::regclass
       AND (   (d.classid = 'pg_class'::regclass
                AND d.objid IN (SELECT i.indexrelid FROM pg_index i
                                 WHERE i.indrelid = 'public.catalog_variant_import_row'::regclass))
            OR (d.classid = 'pg_constraint'::regclass
                AND d.objid IN (SELECT c.oid FROM pg_constraint c
                                 WHERE c.conrelid = 'public.catalog_variant_import_row'::regclass))
            OR (d.classid = 'pg_attrdef'::regclass
                AND d.objid IN (SELECT a.oid FROM pg_attrdef a
                                 WHERE a.adrelid = 'public.catalog_variant_import_row'::regclass)))
),
g AS (
    SELECT
        has_table_privilege('service_role', 'public.catalog_variant_import_row', 'INSERT')
            AS g_sr_insert_row,
        COALESCE(has_function_privilege('service_role', (SELECT oid FROM fn), 'EXECUTE'), false)
            AS g_sr_exec_token,
        NOT COALESCE(has_function_privilege('anon', (SELECT oid FROM fn), 'EXECUTE'), true)
            AS g_anon_no_exec_token,
        NOT EXISTS (SELECT 1 FROM fnmeta f, aclexplode(f.proacl) a
                     WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE')
            AND (SELECT proacl IS NOT NULL FROM fnmeta)
            AS g_public_no_exec_token,
        COALESCE(has_function_privilege('authenticated', (SELECT oid FROM fn), 'EXECUTE'), false)
            AS g_auth_exec_preserved,
        (SELECT count(*) > 0 AND bool_and(has_function_privilege('service_role', fn_oid, 'EXECUTE'))
           FROM row_fns)
            AS g_writer_execs_all_index_fns,
        COALESCE((SELECT md5(prosrc) = '18682dce935281b0a4437628a6e8309a' FROM fnmeta), false)
            AS g_fn_body_pinned,
        COALESCE((SELECT provolatile = 'i' AND NOT proisstrict AND NOT prosecdef
                         AND proconfig = ARRAY['search_path=""']
                    FROM fnmeta), false)
            AS g_fn_contract,
        EXISTS (SELECT 1 FROM pg_index i, idx
                 WHERE i.indexrelid = idx.oid
                   AND i.indrelid = 'public.catalog_variant_import_row'::regclass
                   AND i.indisunique AND i.indisvalid AND i.indisready)
            AS g_idx_unique_valid_ready,
        COALESCE((SELECT pg_get_indexdef(idx.oid) ~ 'axis_identity_token\(normalized_data, ''printing_profile_id''::text\)'
                     AND pg_get_indexdef(idx.oid) ~ 'axis_identity_token\(normalized_data, ''edition_context_profile_id''::text\)'
                    FROM idx), false)
            AS g_idx_uses_token_both_axes,
        COALESCE((SELECT array_agg(d.refobjid) = ARRAY[(SELECT oid FROM fn)]::oid[]
                    FROM pg_depend d, idx
                   WHERE d.classid = 'pg_class'::regclass AND d.objid = idx.oid
                     AND d.refclassid = 'pg_proc'::regclass), false)
            AS g_idx_dep_only_token,
        (SELECT count(*) = 2 FROM pg_trigger t
          WHERE NOT t.tgisinternal AND t.tgenabled = 'O'
            AND t.tgname IN ('trg_cvir_normalized_shape',
                             'trg_card_variant_edition_context_profile_game'))
            AS g_guards_enabled
)
SELECT jsonb_build_object(
    'gate_pass', (g_sr_insert_row AND g_sr_exec_token AND g_anon_no_exec_token
                  AND g_public_no_exec_token AND g_auth_exec_preserved
                  AND g_writer_execs_all_index_fns AND g_fn_body_pinned AND g_fn_contract
                  AND g_idx_unique_valid_ready AND g_idx_uses_token_both_axes
                  AND g_idx_dep_only_token AND g_guards_enabled),
    'gates', to_jsonb(g),
    'd_fn_acl', (SELECT proacl::text FROM fnmeta),
    'd_writer_fns', (SELECT jsonb_agg(jsonb_build_object(
                         'fn', fn_oid::regprocedure::text,
                         'service_role_execute', has_function_privilege('service_role', fn_oid, 'EXECUTE'))
                         ORDER BY fn_oid::regprocedure::text) FROM row_fns),
    'd_idx_def_md5', (SELECT md5(pg_get_indexdef(oid)) FROM idx),
    'checked_at', clock_timestamp()
) AS r2835_staging_writer_acl
FROM g;
