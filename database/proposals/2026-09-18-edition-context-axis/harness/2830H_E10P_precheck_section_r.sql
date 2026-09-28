-- ============================================================================
-- 2830H · E10P — PRECHECK DO LOTE L8 (Seção R)
-- ============================================================================
-- Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO. SELECT único.
-- Cobre ......... identidade da RC (2211/2176/2095/2192, bloco = E06P), candidato de
--                 Printing (núcleo = E06P), escopo real de dp1 e profile de
--                 SET-LOGO, triggers/constraints da 2207 (blocos = E06P via
--                 static_check), marcador, P6/RLS das 3 tabelas EC escritas.
-- ============================================================================
WITH
gs AS (
    SELECT (SELECT id FROM public.game WHERE code = 'POKEMON') AS game_id,
           (SELECT id FROM public.asset_source WHERE code = 'TCGDEX') AS src_id
),
rc_exp(sig, pin, lang, vol, secdef, cfg, result) AS (
    VALUES ('internal.resolve_variant_row_axes(jsonb,uuid,uuid,text)', 'f10af378c2d5d9fdfd207d9c7d9ff046', 'plpgsql', 's', true,
            ARRAY['search_path=""'],
            'TABLE(printing_state text, printing_profile_id uuid, printing_trait_ids uuid[], edition_context_state text, edition_context_profile_id uuid, edition_context_trait_ids uuid[], residual_type text, residual_foil text, residual_subtype text, residual_stamp text[])'),
           ('internal.compute_variant_residual_signature(jsonb,uuid,uuid)', 'b15a527d3b6adb1e50cbaafae22431bc', 'plpgsql', 's', true,
            ARRAY['search_path=""'],
            'TABLE(residual_type text, residual_foil text, residual_subtype text, residual_stamp text[], printing_state text, trait_ids uuid[], printing_profile_id uuid)'),
           ('public.normalize_external_catalog_value(text)', '1fdc2e7ebe2297f8db85be4aad2e5d33', 'sql', 's', false,
            ARRAY['search_path=""'],
            'text'),
           ('internal.resolve_variant_mapping_scope(uuid,uuid)', '21a57ebf7e0d15fc14e576999523cd51', 'sql', 's', true,
            ARRAY['search_path=""'],
            'TABLE(external_set_id text, reference_id uuid)')
),
rc AS (
    SELECT e.sig, e.pin, p.oid AS fn_oid,
           md5(replace(p.prosrc, chr(13) || chr(10), chr(10))) AS body_md5_lf,
           l.lanname::text AS lang, p.provolatile::text AS vol, p.prosecdef AS secdef,
           p.proconfig::text[] AS cfg, pg_get_function_result(p.oid) AS result,
           (p.oid IS NOT NULL AND l.lanname = e.lang AND p.provolatile = e.vol AND p.prosecdef = e.secdef
            AND p.proconfig::text[] = e.cfg AND pg_get_function_result(p.oid) = e.result
            AND md5(replace(p.prosrc, chr(13) || chr(10), chr(10))) = e.pin) AS ok
      FROM rc_exp e
      LEFT JOIN pg_proc p ON p.oid = to_regprocedure(e.sig)
      LEFT JOIN pg_language l ON l.oid = p.prolang
),
c35 AS (
    SELECT m.id, m.raw_field::text AS raw_field, m.normalized_token,
           COALESCE(m.traits_signature,
                    ARRAY(SELECT mt.trait_id FROM public.card_printing_external_mapping_trait mt
                           WHERE mt.mapping_id = m.id ORDER BY mt.trait_id)) AS sig
      FROM public.card_printing_external_mapping m, gs
     WHERE m.game_id = gs.game_id AND m.asset_source_id = gs.src_id AND m.is_active
       AND m.raw_field IN ('subtype', 'stamp')
),
cand35 AS (
    SELECT c.id, c.raw_field, c.normalized_token, c.sig, pp.id AS profile_id,
           EXISTS (SELECT 1 FROM public.card_edition_context_external_mapping e
                    WHERE e.game_id = gs.game_id AND e.asset_source_id = gs.src_id AND e.raw_field = c.raw_field
                      AND e.normalized_token = c.normalized_token AND e.is_active AND e.external_set_id IS NULL) AS ec_overlap
      FROM c35 c
     CROSS JOIN gs
      JOIN public.card_printing_profile pp ON pp.game_id = gs.game_id AND pp.is_active AND pp.traits_signature = c.sig
     WHERE cardinality(c.sig) > 0
       AND NOT EXISTS (SELECT 1 FROM public.card_printing_trait t WHERE t.id = ANY (c.sig) AND NOT t.is_active)
       AND public.normalize_external_catalog_value(c.normalized_token) = c.normalized_token
     ORDER BY 6 DESC, c.id
     LIMIT 1
),
tbl(name) AS (
    VALUES ('card_edition_context_trait'),
           ('card_edition_context_external_mapping'),
           ('card_edition_context_external_mapping_trait')
),
rel AS (
    SELECT t.name, to_regclass('public.' || t.name) AS oid FROM tbl t
),
trg_exp(tgname, relname, tgtype, fn, is_constraint, attrs) AS (
    VALUES ('trg_cecem_normalize',       'card_edition_context_external_mapping',       7,  'internal.normalize_edition_context_external_mapping()',          false, ARRAY[]::text[]),
           ('trg_cecem_header',          'card_edition_context_external_mapping',       19, 'internal.enforce_edition_context_mapping_header()',              false, ARRAY[]::text[]),
           ('trg_cecem_seal',            'card_edition_context_external_mapping',       5,  'internal.seal_edition_context_external_mapping()',               true,  ARRAY[]::text[]),
           ('trg_cecem_signature_write', 'card_edition_context_external_mapping',       19, 'internal.enforce_edition_context_mapping_signature_write()',     false, ARRAY['traits_signature']),
           ('trg_cecemt_immutable',      'card_edition_context_external_mapping_trait', 31, 'internal.guard_edition_context_mapping_composition_immutable()', false, ARRAY[]::text[])
),
trg AS (
    SELECT tg.tgname::text AS tgname, r.name AS relname, tg.tgtype::int AS tgtype,
           tg.tgenabled::text AS enabled, tg.tgfoid AS fn_oid, tg.tgfoid::regprocedure::text AS fn,
           (tg.tgconstraint <> 0) AS is_constraint, tg.tgdeferrable AS deferrable,
           tg.tginitdeferred AS initdeferred,
           COALESCE((SELECT array_agg(a.attname::text ORDER BY k.ord)
                       FROM unnest(tg.tgattr::int2[]) WITH ORDINALITY AS k(attnum, ord)
                       JOIN pg_attribute a ON a.attrelid = tg.tgrelid AND a.attnum = k.attnum),
                    ARRAY[]::text[]) AS attrs
      FROM rel r JOIN pg_trigger tg ON tg.tgrelid = r.oid AND NOT tg.tgisinternal
),
con AS (
    SELECT c.conname::text AS conname, r.name AS relname, c.contype::text AS contype,
           c.convalidated, c.condeferrable, c.condeferred
      FROM rel r JOIN pg_constraint c ON c.conrelid = r.oid
),
con_exp(conname, relname, contype) AS (
    VALUES ('ck_cecem_raw_field',              'card_edition_context_external_mapping',       'c'),
           ('ck_cecem_token_not_blank',        'card_edition_context_external_mapping',       'c'),
           ('ck_cecem_external_set_not_blank', 'card_edition_context_external_mapping',       'c'),
           ('ck_cecem_signature_not_empty',    'card_edition_context_external_mapping',       'c'),
           ('ck_cecem_signature_shape',        'card_edition_context_external_mapping',       'c'),
           ('uq_cecem_id_game',                'card_edition_context_external_mapping',       'u'),
           ('pk_cecemt',                       'card_edition_context_external_mapping_trait', 'p'),
           ('fk_cecemt_mapping',               'card_edition_context_external_mapping_trait', 'f'),
           ('fk_cecemt_trait',                 'card_edition_context_external_mapping_trait', 'f'),
           ('uq_cect_game_code',               'card_edition_context_trait',                  'u'),
           ('uq_cect_game_family_order',       'card_edition_context_trait',                  'u'),
           ('uq_cect_id_game',                 'card_edition_context_trait',                  'u'),
           ('ck_cect_code_format',             'card_edition_context_trait',                  'c'),
           ('ck_cect_family',                  'card_edition_context_trait',                  'c'),
           ('ck_cect_display_order_positive',  'card_edition_context_trait',                  'c')
),
act_idx(idxname, pred, cols) AS (
    VALUES ('uq_cecem_active_global', 'external_set_id IS NULL AND is_active',
            ARRAY['game_id','asset_source_id','raw_field','normalized_token']),
           ('uq_cecem_active_scoped', 'external_set_id IS NOT NULL AND is_active',
            ARRAY['game_id','asset_source_id','external_set_id','raw_field','normalized_token'])
),
idx AS (
    SELECT e.idxname, i.indrelid, i.indisunique, i.indisvalid, i.indisready,
           regexp_replace(pg_get_expr(i.indpred, i.indrelid), '[()]', '', 'g') AS pred_np,
           e.pred AS pred_exp, e.cols AS cols_exp,
           (SELECT array_agg(a.attname::text ORDER BY k.ord)
              FROM unnest(i.indkey::int2[]) WITH ORDINALITY AS k(attnum, ord)
              JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.attnum
             WHERE k.ord <= i.indnkeyatts) AS cols
      FROM act_idx e
      LEFT JOIN pg_index i ON i.indexrelid = to_regclass('public.' || e.idxname)
),
seal_con AS (
    SELECT c.conname::text AS conname, c.contype::text AS contype, c.condeferrable, c.condeferred,
           c.conrelid::regclass::text AS relation
      FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace
     WHERE n.nspname = 'public' AND c.conname IN ('trg_cecp_seal', 'trg_cecem_seal')
),
l3_seq AS (
    SELECT r.name AS relname, s.oid::regclass::text AS sequence_name, 'owned_by' AS link
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
l3_own AS (
    SELECT r.name AS relname, c.relrowsecurity AS rls, c.relforcerowsecurity AS force_rls,
           pg_get_userbyid(c.relowner) AS owner
      FROM rel r JOIN pg_class c ON c.oid = r.oid
),
dp1 AS (
    SELECT (SELECT count(*) FROM public.card_set_external_reference r, gs
             WHERE r.asset_source_id = gs.src_id AND r.external_set_id = 'dp1' AND r.is_active) AS refs,
           (SELECT count(*) FROM public.card_edition_context_external_mapping m, gs
             WHERE m.game_id = gs.game_id AND m.asset_source_id = gs.src_id AND m.raw_field = 'stamp'
               AND m.normalized_token = 'SET-LOGO' AND m.external_set_id = 'dp1' AND m.is_active
               AND cardinality(m.traits_signature) >= 1
               AND (SELECT count(*) FROM public.card_edition_context_profile p
                     WHERE p.game_id = gs.game_id AND p.traits_signature = m.traits_signature AND p.is_active) = 1) AS mapped
),
gates AS (
    SELECT
        ((SELECT count(*) FROM public.game WHERE code = 'POKEMON') = 1
         AND (SELECT count(*) FROM public.asset_source WHERE code = 'TCGDEX') = 1)    AS g_game_source_one,
        ((SELECT count(*) FROM rc WHERE ok) = 4
         AND has_function_privilege(current_user, to_regprocedure('internal.resolve_variant_row_axes(jsonb,uuid,uuid,text)'), 'EXECUTE')
         AND has_function_privilege(current_user, to_regprocedure('internal.resolve_variant_mapping_scope(uuid,uuid)'), 'EXECUTE')) AS g_rc_identity,
        ((SELECT count(*) FROM public.card_edition_context_trait WHERE strpos(code, 'H2830') > 0) = 0
         AND (SELECT count(*) FROM public.card_edition_context_profile WHERE strpos(code, 'H2830') > 0) = 0
         AND (SELECT count(*) FROM public.card_edition_context_external_mapping WHERE strpos(normalized_token, 'H2830') > 0) = 0
         AND (SELECT count(*) FROM public.card_printing_external_mapping WHERE strpos(normalized_token, 'H2830') > 0) = 0) AS g_marker_absent_now,
        ((SELECT count(*) FROM trg_exp e JOIN trg t ON t.tgname = e.tgname AND t.relname = e.relname
           WHERE t.tgtype = e.tgtype AND t.enabled = 'O'
             AND t.fn_oid = to_regprocedure(e.fn)
             AND t.is_constraint = e.is_constraint
             AND t.deferrable = e.is_constraint AND t.initdeferred = e.is_constraint
             AND t.attrs = e.attrs) = 5
         AND (SELECT count(*) FROM trg t JOIN trg_exp e ON e.tgname = t.tgname) = 5)  AS g_l4_triggers,
        NOT EXISTS (SELECT 1 FROM trg t
                     WHERE NOT EXISTS (SELECT 1 FROM trg_exp e
                                        WHERE e.tgname = t.tgname AND e.relname = t.relname)) AS g_no_other_triggers_l4,
        ((SELECT count(*) FROM seal_con WHERE conname = 'trg_cecp_seal') = 1
         AND (SELECT count(*) FROM seal_con WHERE conname = 'trg_cecem_seal') = 1
         AND NOT EXISTS (SELECT 1 FROM seal_con
                          WHERE contype <> 't' OR NOT condeferrable OR NOT condeferred)) AS g_seal_constraint_names_unique,
        (NOT EXISTS (SELECT 1 FROM con
                      WHERE condeferrable
                        AND NOT (conname = 'trg_cecem_seal' AND relname = 'card_edition_context_external_mapping'))
         AND (SELECT count(*) FROM con
               WHERE condeferrable AND conname = 'trg_cecem_seal'
                 AND relname = 'card_edition_context_external_mapping') = 1)          AS g_deferrable_only_seal_l4,
        ((SELECT count(*) FROM con_exp e JOIN con c ON c.conname = e.conname AND c.relname = e.relname
           WHERE c.contype = e.contype AND c.convalidated) = 15
         AND (SELECT count(*) FROM idx
               WHERE indrelid = to_regclass('public.card_edition_context_external_mapping')
                 AND indisunique AND indisvalid AND indisready
                 AND pred_np = pred_exp AND cols = cols_exp) = 2)                     AS g_l4_constraints,
        NOT EXISTS (SELECT 1 FROM l3_seq)                                             AS g_l4_no_sequence,
        (SELECT count(*) FROM l3_own WHERE NOT force_rls AND owner = current_user) = 3 AS g_l4_rls_bypass,
        (SELECT count(*) FROM public.card_printing_external_mapping m, gs
          WHERE m.game_id = gs.game_id AND m.asset_source_id = gs.src_id
            AND m.raw_field = 'stamp' AND m.normalized_token = 'SET-LOGO') = 0        AS g_37_no_printing,
        (SELECT count(*) FROM cand35) = 1                                             AS g_35_candidate,
        ((SELECT refs FROM dp1) = 1 AND (SELECT mapped FROM dp1) = 1
         AND (SELECT count(*) FROM internal.resolve_variant_mapping_scope(
                (SELECT r.card_set_id FROM public.card_set_external_reference r, gs
                  WHERE r.asset_source_id = gs.src_id AND r.external_set_id = 'dp1' AND r.is_active),
                (SELECT src_id FROM gs)) x WHERE x.external_set_id = 'dp1') = 1)     AS g_dp1_scope,
        ((SELECT public.normalize_external_catalog_value('set-logo')) = 'SET-LOGO'
         AND (SELECT public.normalize_external_catalog_value('oversized')) = 'OVERSIZED'
         AND (SELECT public.normalize_external_catalog_value('standard')) = 'STANDARD') AS g_normalization
)
SELECT to_jsonb(g)
    || jsonb_build_object(
        'gate_pass', (SELECT bool_and(v::boolean) FROM jsonb_each_text(to_jsonb(g)) AS e(k, v))
                     AND NOT EXISTS (SELECT 1 FROM jsonb_each_text(to_jsonb(g)) AS e(k, v) WHERE v IS NULL),
        'd_rc_identity',    COALESCE((SELECT jsonb_agg(to_jsonb(r) - 'fn_oid' ORDER BY r.sig) FROM rc r), '[]'::jsonb),
        'd_35_candidate',   COALESCE((SELECT jsonb_agg(to_jsonb(c)) FROM cand35 c), '[]'::jsonb),
        'd_dp1',            (SELECT to_jsonb(d) FROM dp1 d),
        'd_triggers',       COALESCE((SELECT jsonb_agg(to_jsonb(t) - 'fn_oid' ORDER BY t.relname, t.tgname) FROM trg t), '[]'::jsonb),
        'd_session',        jsonb_build_object(
                                'current_user',       current_user,
                                'server_version_num', current_setting('server_version_num'),
                                'lock_timeout',       current_setting('lock_timeout'),
                                'search_path',        current_setting('search_path'),
                                'backend_pid',        pg_backend_pid(),
                                'checked_at',         clock_timestamp())
    ) AS e10p_precheck
  FROM gates g;
