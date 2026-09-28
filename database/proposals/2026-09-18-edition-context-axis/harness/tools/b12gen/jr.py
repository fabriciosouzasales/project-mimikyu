# Infra compartilhada de fixtures job/row (L7, L11, L12): escolha determinística
# de Card/Set/Variant Type/profiles, criação de job sentinela e de row, e o
# bloco de gates JOB/ROW dos prechecks. Um só lugar (I-3c/I-4c).
from lib import *

JOB = 'public.catalog_variant_import_job'
ROW = 'public.catalog_variant_import_row'

PICK = sql("SELECT c.id, c.card_set_id INTO v_card, v_cs\n"
           "  FROM public.card c\n"
           "  JOIN public.card_set cs ON cs.id = c.card_set_id\n"
           "  JOIN public.expansion e ON e.id = cs.expansion_id\n"
           " WHERE e.game_id = v_game\n"
           " ORDER BY c.id\n"
           " LIMIT 1;\n"
           "SELECT t.id INTO v_vt FROM public.card_variant_type t WHERE t.game_id = v_game ORDER BY t.id LIMIT 1;\n"
           "SELECT p.id INTO v_pp FROM public.card_printing_profile p WHERE p.game_id = v_game AND p.is_active ORDER BY p.id LIMIT 1;\n"
           "SELECT p.id INTO v_ec FROM public.card_edition_context_profile p WHERE p.game_id = v_game AND p.is_active ORDER BY p.id LIMIT 1;") \
    + iff('v_card IS NULL OR v_cs IS NULL OR v_vt IS NULL OR v_pp IS NULL OR v_ec IS NULL',
          'fixture de catálogo indisponível (Card/Set/Variant Type/profiles; STOP, ver precheck)')

PICK_DECL = [('v_card', 'uuid', None), ('v_cs', 'uuid', None), ('v_vt', 'uuid', None), ('v_pp', 'uuid', None), ('v_ec', 'uuid', None)]


def job(var, status, suffix):
    """job sentinela: source TCGDEX, external_set_id marcado e distinto por job
    (índice parcial uq_catalog_variant_import_job_fingerprint_active)"""
    return sql(f"INSERT INTO {JOB} (card_set_id, source, external_set_id, status)\n"
               f"VALUES (v_cs, 'TCGDEX', v_marker || '_J{suffix}', '{status}')\n"
               f"RETURNING id INTO {var};") + iff(f'{var} IS NULL', f'job sentinela {status} não criado')


def row(var, jobvar, nd, validation, persistence='PENDING', decision=None, card='v_card', extra_cols='', extra_vals=''):
    cols = 'job_id, card_id, raw_data, normalized_data, validation_status, persistence_status'
    vals = f"{jobvar}, {card}, '{{}}'::jsonb, {nd}, '{validation}', '{persistence}'"
    if decision:
        cols += ', decision_status'
        vals += f", '{decision}'"
    if extra_cols:
        cols += ', ' + extra_cols
        vals += ', ' + extra_vals
    return sql(f"INSERT INTO {ROW} ({cols})\nVALUES ({vals})\nRETURNING id INTO {var};")


def row_stmt(jobvar, nd, validation, persistence='PENDING', into=None):
    """INSERT de row para bloco negativo (termina em ;)"""
    return (f"INSERT INTO {ROW} (job_id, card_id, raw_data, normalized_data, validation_status, persistence_status)\n"
            f"VALUES ({jobvar}, v_card, '{{}}'::jsonb, {nd}, '{validation}', '{persistence}')"
            + (f"\nRETURNING id INTO {into};" if into else ';'))


def nd(**kw):
    """jsonb_build_object com as chaves pedidas; valor 'NULL' ⇒ JSON null"""
    parts = []
    for k, v in kw.items():
        key = {'vt': 'variant_type_id', 'pp': 'printing_profile_id', 'ec': 'edition_context_profile_id'}[k]
        parts.append(f"'{key}', {v}")
    return 'jsonb_build_object(' + ', '.join(parts) + ')' if parts else "'{}'::jsonb"


# ---------------------------------------------------------------------------
# gates JOB/ROW (prechecks E09P, E13P, E14P) — bloco idêntico
# ---------------------------------------------------------------------------
JR_CTES = """jr_guard AS (
    SELECT p.prosrc
      FROM pg_proc p WHERE p.oid = to_regprocedure('internal.guard_cvir_normalized_shape()')
),
jr_tok(tok) AS (
    VALUES ('CVIR_SHAPE_INVALID_PRINTING:'), ('CVIR_SHAPE_INVALID_EDITION_CONTEXT:'), ('nao e UUID valido'),
           ('CVIR_VALID_REQUIRES_VARIANT_TYPE:'), ('CVIR_VALID_REQUIRES_PRINTING_KEY:'),
           ('CVIR_OPERATIONAL_VALID_REQUIRES_EDITION_CONTEXT_KEY:'), ('CVIR_EDITION_CONTEXT_KEY_REMOVAL_FORBIDDEN:')
),
jr_ck AS (
    SELECT c.conrelid::regclass::text AS rel, c.conname::text AS conname, pg_get_constraintdef(c.oid) AS def
      FROM pg_constraint c
     WHERE c.conname IN ('ck_catalog_variant_import_job_status', 'ck_catalog_variant_import_job_source',
                         'ck_catalog_variant_import_row_validation_status', 'ck_catalog_variant_import_row_decision_status',
                         'ck_catalog_variant_import_row_persistence_status', 'ck_catalog_variant_import_row_printing_profile_shape',
                         'ck_catalog_variant_import_row_valid_requires_printing_key')
),
jr_fx AS (
    SELECT (SELECT count(*) FROM (SELECT 1 FROM public.card c JOIN public.card_set cs ON cs.id = c.card_set_id
                                   JOIN public.expansion e ON e.id = cs.expansion_id, gs
                                  WHERE e.game_id = gs.game_id LIMIT 16) z) AS cards,
           (SELECT count(*) FROM public.card_variant_type t, gs WHERE t.game_id = gs.game_id) AS vts,
           (SELECT count(*) FROM public.card_printing_profile p, gs WHERE p.game_id = gs.game_id AND p.is_active) AS pps,
           (SELECT count(*) FROM public.card_edition_context_profile p, gs WHERE p.game_id = gs.game_id AND p.is_active) AS ecs,
           (SELECT count(*) FROM public.card_variant) AS cvs
),"""

JR_GATES = """        (SELECT count(*) FROM jr_tok k, jr_guard g WHERE strpos(g.prosrc, k.tok) > 0) = 7
         AND NOT EXISTS (SELECT 1 FROM jr_guard g WHERE strpos(g.prosrc, 'CVIR_PENDING_VALID_REQUIRES_EDITION_CONTEXT_KEY') > 0)
                                                                                      AS g_jr_guard_tokens,
        ((SELECT count(*) FROM jr_ck) = 7
         AND (SELECT count(*) FROM jr_ck WHERE conname = 'ck_catalog_variant_import_job_status'
               AND strpos(def, '''RECEIVED''') > 0 AND strpos(def, '''PROCESSING''') > 0 AND strpos(def, '''STAGED''') > 0
               AND strpos(def, '''CONFIRMING''') > 0 AND strpos(def, '''COMPLETED''') > 0
               AND strpos(def, '''COMPLETED_WITH_ERRORS''') > 0 AND strpos(def, '''FAILED''') > 0
               AND strpos(def, '''CANCELLED''') > 0) = 1
         AND (SELECT count(*) FROM jr_ck WHERE conname = 'ck_catalog_variant_import_row_persistence_status'
               AND strpos(def, '''PENDING''') > 0 AND strpos(def, '''INSERTED''') > 0
               AND strpos(def, '''UNCHANGED''') > 0 AND strpos(def, '''FAILED''') > 0) = 1)     AS g_jr_checks,
        (SELECT count(*) FROM pg_index i
          WHERE i.indexrelid = to_regclass('public.uq_catalog_variant_import_job_fingerprint_active')
            AND i.indisunique AND i.indisvalid AND i.indpred IS NOT NULL) = 1
         AND (SELECT count(*) FROM pg_index i
          WHERE i.indexrelid = to_regclass('public.uq_cvir_row_identity') AND i.indisunique AND i.indisvalid) = 1
                                                                                      AS g_jr_indexes,
        ((SELECT cards FROM jr_fx) = 16 AND (SELECT vts FROM jr_fx) >= 1 AND (SELECT pps FROM jr_fx) >= 1
         AND (SELECT ecs FROM jr_fx) >= 1 AND (SELECT cvs FROM jr_fx) >= 1)          AS g_jr_fixture_available,
        (SELECT count(*) FROM public.catalog_variant_import_job
          WHERE status IN ('RECEIVED','PROCESSING','CONFIRMING')) = 0                 AS g_jr_no_job_in_flight,"""

JR_DETAIL = """        'd_jr_checks',      COALESCE((SELECT jsonb_agg(to_jsonb(c) ORDER BY c.conname) FROM jr_ck c), '[]'::jsonb),
        'd_jr_fixture',     (SELECT to_jsonb(f) FROM jr_fx f),"""
