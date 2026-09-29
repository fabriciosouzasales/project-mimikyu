# Gera o instrumento D1 (SELECT único, só leitura) a partir da evidência de 19/09.
# Uso: python3 gen_d1.py <dir_evidence> <saida.sql>
import json, sys, hashlib, pathlib
EV = pathlib.Path(sys.argv[1]); OUT = pathlib.Path(sys.argv[2])
def rows(p):
    o = json.loads(p.read_text())['result']; a = o.index('\n[{'); b = o.rindex('}]') + 2
    return json.loads(o[a + 1:b])
cen = rows(EV / 'census_19-09_original/census_raw_response_2026-09-19T01-27-53Z.txt')
sl = {x['code']: dict((q.split(':')[0], int(q.split(':')[1])) for q in x['por_set'].split())
      for x in rows(EV / 'census_19-09_original/setlogo_by_set_raw_response_2026-09-19T01-37-39Z.txt')}
ready = {k: v for k, v in json.loads((EV / 'c3_expected_from_raw_19-09.json').read_text()).items() if v > 0}
FIN = ['STANDARD', 'HOLO', 'COSMOS_HOLO', 'REVERSE_HOLO', 'ENERGY_REVERSE', 'POKE_BALL_REVERSE', 'LOVE_BALL_REVERSE',
       'FRIEND_BALL_REVERSE', 'QUICK_BALL_REVERSE', 'DUSK_BALL_REVERSE', 'ROCKET_REVERSE', 'MASTER_BALL_REVERSE',
       'GOLD_HOLO', 'TINSEL_HOLO', 'TINSEL_REVERSE', 'CRACKED_ICE_HOLO', 'GALAXY_HOLO', 'RAINBOW_HOLO', 'METAL',
       'METAL_GOLD', 'LENTICULAR', 'COSMOS_REVERSE', 'MASTER_BALL_PATTERN', 'POKE_BALL_PATTERN', 'MASTER_BALL_HOLO',
       'SNOWFLAKE_COSMOS_HOLO', 'STANDARDS_SNOWFLAKE', 'SHOWFLAKE_HOLO']
EX = {f'EX{i}' for i in range(7, 17)}; OK = {'DP1', 'SWSH9', 'SVP'}
cmap = {r['code']: r for r in cen}
hold = {'PROMO_STAMPED': cmap['PROMO_STAMPED']['variants']}
nc = {}
for c, d in sorted(sl.items()):
    for s, n in sorted(d.items()):
        if s in EX: nc[f'{c}@{s}'] = n
        elif s not in OK: hold[f'{c}@{s}'] = n
h6 = {c: (cmap[c]['pscid'], cmap[c]['psvm']) for c in ready if cmap[c]['pscid'] or cmap[c]['psvm']}
assert sum(ready.values()) == 365 and len(ready) == 63
assert sum(hold.values()) == 107 and len(hold) == 30
assert sum(nc.values()) == 555 and len(nc) == 12
assert h6 == {'SET_LOGO_REVERSE': (1, 0), 'STAFF_HOLO': (17, 1)}, h6
assert sum(r['variants'] for r in cen) == 24893 and sum(cmap[c]['variants'] for c in FIN) == 23866
SEP = ',\n           '
FIN_V = SEP.join(f"('{c}')" for c in FIN)
H6_V = SEP.join(f"('{c}', {p}, {v})" for c, (p, v) in sorted(h6.items()))
def vals(d): return SEP.join(f"('{k}', {v})" for k, v in sorted(d.items()))
EXRE = "'^EX(7|8|9|10|11|12|13|14|15|16)$'"
sql = f"""-- ============================================================================
-- 2830H · D1 — MEDIÇÃO DE IDENTIDADE POR ID (HOLD 107 · PLANO 285) · SELECT único, read-only
-- ============================================================================
-- Status ........ PREPARADO — NÃO EXECUTADO. Mandato de execução próprio.
-- Origem ........ BATCH12-E15-D1-MEASUREMENT-READINESS-01 (D1 aprovada; D2: HOLD
--                 de referência = SET_LOGO_STANDARDS 11 / SET_LOGO_REVERSE 59, LIVE 19/09).
-- Snapshot ...... um único statement = um único snapshot MVCC (READ COMMITTED).
-- Escopo ........ card_variant × card_variant_type × card × card_set + tabelas de
--                 Pricing. NÃO executa o DERIV-5X; NÃO chama 2211/2192; sem lineage.
-- Predicados .... HOLD = 2831 PASSO 0 (verbatim); READY = d5_c3 (C3 adjudicado,
--                 verbatim); NÃO_CONT = SET_LOGO% em EX7–16; FINISH = lista de 28.
--                 Cada classe tem o próprio predicado; a partição é CONFERIDA.
-- Referência .... composições de 19/09 (evidence/B5X-E15P-2026-09-28): READY por
--                 tipo (63), HOLD por tipo@Set (30), NÃO_CONT por tipo@Set (12),
--                 Pricing por tipo READY (H6). A identidade por id (digests) é NOVA:
--                 não existe digest em 19/09; a 1ª medição apenas o CAPTURA.
-- ============================================================================
WITH
h_finish(code) AS (
    VALUES {FIN_V}
),
h_ready(code, n) AS (
    VALUES {vals(ready)}
),
h_hold(k, n) AS (
    VALUES {vals(hold)}
),
h_nc(k, n) AS (
    VALUES {vals(nc)}
),
h_h6(code, pscid, psvm) AS (
    VALUES {H6_V}
),
d1_cv AS MATERIALIZED (
    SELECT cv.id, vt.id AS type_id, vt.code, cs.code AS set_code,
           (vt.code IN (SELECT code FROM h_finish)) AS is_finish,
           (vt.code = 'PROMO_STAMPED'
            OR (vt.code LIKE 'SET_LOGO%'
                AND cs.code !~ {EXRE}
                AND cs.code NOT IN ('DP1','SWSH9','SVP'))) AS is_hold,
           (vt.code LIKE 'SET_LOGO%' AND cs.code ~ {EXRE}) AS is_nc,
           (vt.code NOT IN (SELECT code FROM h_finish)
            AND NOT (vt.code LIKE 'SET_LOGO%' AND cs.code ~ {EXRE})
            AND NOT (vt.code LIKE 'SET_LOGO%' AND cs.code NOT IN ('DP1','SWSH9','SVP'))
            AND vt.code <> 'PROMO_STAMPED') AS is_ready
      FROM public.card_variant cv
      JOIN public.card_variant_type vt ON vt.id = cv.variant_type_id
      JOIN public.card c  ON c.id  = cv.card_id
      JOIN public.card_set cs ON cs.id = c.card_set_id
),
d1_cls AS (
    SELECT d.*,
           COALESCE(d.is_finish::int, 0) + COALESCE(d.is_hold::int, 0)
           + COALESCE(d.is_nc::int, 0) + COALESCE(d.is_ready::int, 0) AS n_cls
      FROM d1_cv d
),
d1_pscid AS (
    SELECT x.card_variant_type_id AS type_id, count(*) AS n FROM public.pricing_source_card_identity x GROUP BY 1
),
d1_psvm AS (
    SELECT x.variant_type_id AS type_id, count(*) AS n FROM public.pricing_source_variant_mapping x GROUP BY 1
),
d1_ready AS (SELECT id, type_id, code FROM d1_cls WHERE is_ready),
d1_hold AS (SELECT id, code, set_code FROM d1_cls WHERE is_hold),
d1_plan_contract AS (
    SELECT id FROM d1_ready WHERE code NOT IN ('STAFF_HOLO', 'SET_LOGO_REVERSE')
),
d1_plan_derived AS (
    SELECT r.id FROM d1_ready r
     WHERE NOT EXISTS (SELECT 1 FROM d1_pscid s WHERE s.type_id = r.type_id)
       AND NOT EXISTS (SELECT 1 FROM d1_psvm v WHERE v.type_id = r.type_id)
),
d1_cond AS (
    SELECT r.id, r.code FROM d1_ready r
     WHERE EXISTS (SELECT 1 FROM d1_pscid s WHERE s.type_id = r.type_id)
        OR EXISTS (SELECT 1 FROM d1_psvm v WHERE v.type_id = r.type_id)
),
d1_ready_pr AS (
    SELECT r.code, max(s.n) AS pscid, max(v.n) AS psvm
      FROM d1_ready r
      LEFT JOIN d1_pscid s ON s.type_id = r.type_id
      LEFT JOIN d1_psvm  v ON v.type_id = r.type_id
     GROUP BY r.code
    HAVING COALESCE(max(s.n), 0) + COALESCE(max(v.n), 0) > 0
),
d1_ready_bt AS (SELECT code, count(*) AS n FROM d1_ready GROUP BY code),
d1_hold_bk AS (
    SELECT CASE WHEN code = 'PROMO_STAMPED' THEN code ELSE code || '@' || set_code END AS k, count(*) AS n
      FROM d1_hold GROUP BY 1
),
d1_nc_bk AS (SELECT code || '@' || set_code AS k, count(*) AS n FROM d1_cls WHERE is_nc GROUP BY 1),
d1_m AS (
    SELECT (SELECT count(*) FROM public.card_variant) AS cv_total,
           (SELECT count(*) FROM d1_cls) AS cv_joined,
           (SELECT count(*) FROM (SELECT code FROM public.card_variant_type GROUP BY code HAVING count(*) > 1) z) AS type_code_dup,
           (SELECT count(*) FROM d1_cls WHERE is_finish) AS n_finish,
           (SELECT count(*) FROM d1_cls WHERE NOT COALESCE(is_finish, false)) AS n_uraw,
           (SELECT count(*) FROM d1_cls WHERE is_ready) AS n_ready,
           (SELECT count(*) FROM d1_cls WHERE is_hold) AS n_hold,
           (SELECT count(*) FROM d1_cls WHERE is_nc) AS n_nc,
           (SELECT count(*) FROM d1_cls WHERE n_cls <> 1) AS n_bad_partition,
           (SELECT count(*) FROM (((SELECT code, n FROM d1_ready_bt) EXCEPT (SELECT code, n FROM h_ready))
                                  UNION ALL
                                  ((SELECT code, n FROM h_ready) EXCEPT (SELECT code, n FROM d1_ready_bt))) z) AS ready_bt_diff,
           (SELECT count(*) FROM (((SELECT k, n FROM d1_hold_bk) EXCEPT (SELECT k, n FROM h_hold))
                                  UNION ALL
                                  ((SELECT k, n FROM h_hold) EXCEPT (SELECT k, n FROM d1_hold_bk))) z) AS hold_bk_diff,
           (SELECT count(*) FROM (((SELECT k, n FROM d1_nc_bk) EXCEPT (SELECT k, n FROM h_nc))
                                  UNION ALL
                                  ((SELECT k, n FROM h_nc) EXCEPT (SELECT k, n FROM d1_nc_bk))) z) AS nc_bk_diff,
           (SELECT count(*) FROM (((SELECT code, (pscid IS NOT NULL), (psvm IS NOT NULL) FROM d1_ready_pr
                                 ) EXCEPT (SELECT code, pscid > 0, psvm > 0 FROM h_h6))
                                  UNION ALL
                                  ((SELECT code, pscid > 0, psvm > 0 FROM h_h6) EXCEPT (SELECT code, (pscid IS NOT NULL), (psvm IS NOT NULL) FROM d1_ready_pr))) z) AS h6_type_diff,
           (SELECT count(*) FROM d1_cond) AS n_cond,
           (SELECT count(*) FROM d1_cond WHERE code = 'STAFF_HOLO') AS n_cond_staff_holo,
           (SELECT count(*) FROM d1_cond WHERE code = 'SET_LOGO_REVERSE') AS n_cond_set_logo_reverse,
           (SELECT count(*) FROM d1_plan_contract) AS n_plan_contract,
           (SELECT count(*) FROM d1_plan_derived) AS n_plan_derived,
           (SELECT count(*) FROM d1_plan_contract p JOIN d1_ready r ON r.id = p.id
             WHERE EXISTS (SELECT 1 FROM d1_pscid s WHERE s.type_id = r.type_id)) AS plan_x_pscid,
           (SELECT count(*) FROM d1_plan_contract p JOIN d1_ready r ON r.id = p.id
             WHERE EXISTS (SELECT 1 FROM d1_psvm v WHERE v.type_id = r.type_id)) AS plan_x_psvm,
           (SELECT count(*) FROM (((SELECT id FROM d1_plan_contract) EXCEPT (SELECT id FROM d1_plan_derived))
                                  UNION ALL
                                  ((SELECT id FROM d1_plan_derived) EXCEPT (SELECT id FROM d1_plan_contract))) z) AS plan_symdiff,
           (SELECT count(*) FROM d1_plan_contract p JOIN d1_hold h ON h.id = p.id) AS plan_x_hold,
           (SELECT pg_catalog.md5(COALESCE(pg_catalog.string_agg(id::text, ',' ORDER BY id), '')) FROM d1_hold) AS md5_hold,
           (SELECT pg_catalog.md5(COALESCE(pg_catalog.string_agg(id::text, ',' ORDER BY id), '')) FROM d1_plan_contract) AS md5_plan,
           (SELECT pg_catalog.md5(COALESCE(pg_catalog.string_agg(id::text, ',' ORDER BY id), '')) FROM d1_plan_derived) AS md5_plan_derived,
           (SELECT pg_catalog.md5(COALESCE(pg_catalog.string_agg(id::text, ',' ORDER BY id), '')) FROM d1_ready) AS md5_ready,
           (SELECT pg_catalog.md5(COALESCE(pg_catalog.string_agg(id::text, ',' ORDER BY id), '')) FROM d1_cond) AS md5_cond
),
gates AS (
    SELECT (m.cv_joined = m.cv_total)                                   AS g_join_complete,
           (m.type_code_dup = 0)                                        AS g_type_code_unique,
           (m.cv_total = 24893 AND m.n_finish = 23866)                  AS g_universe_19_09,
           (m.n_uraw = 1027)                                            AS g_uraw_1027,
           (m.n_ready = 365 AND m.n_hold = 107 AND m.n_nc = 555
            AND m.n_ready + m.n_hold + m.n_nc = m.n_uraw)               AS g_partition_counts,
           (m.n_bad_partition = 0)                                      AS g_partition_exact,
           (m.ready_bt_diff = 0)                                        AS g_ready_by_type_19_09,
           (m.hold_bk_diff = 0)                                         AS g_hold_by_type_set_19_09,
           (m.nc_bk_diff = 0)                                           AS g_nc_by_type_set_19_09,
           (m.h6_type_diff = 0)                                         AS g_h6_types,
           (m.n_cond = 80 AND m.n_cond_staff_holo = 40
            AND m.n_cond_set_logo_reverse = 40)                         AS g_conditioned_80_40_40,
           (m.n_plan_contract = 285)                                    AS g_plan_contract_285,
           (m.plan_x_pscid = 0)                                         AS g_plan_x_pscid_zero,
           (m.plan_x_psvm = 0)                                          AS g_plan_x_psvm_zero,
           (m.plan_symdiff = 0 AND m.md5_plan = m.md5_plan_derived)     AS g_plan_equivalence,
           (m.plan_x_hold = 0)                                          AS g_plan_x_hold_zero
      FROM d1_m m
)
SELECT pg_catalog.jsonb_build_object(
    'instrument', 'D1-ID-IDENTITY',
    'gates', pg_catalog.to_jsonb(g),
    'gate_pass', (SELECT bool_and(v::boolean) FROM pg_catalog.jsonb_each_text(pg_catalog.to_jsonb(g)) AS e(k, v))
                 AND NOT EXISTS (SELECT 1 FROM pg_catalog.jsonb_each_text(pg_catalog.to_jsonb(g)) AS e(k, v) WHERE v IS NULL),
    'd1_identity', (SELECT pg_catalog.jsonb_build_object(
                        'hold', pg_catalog.jsonb_build_object('n', m.n_hold, 'md5', m.md5_hold),
                        'plan', pg_catalog.jsonb_build_object('n', m.n_plan_contract, 'md5', m.md5_plan),
                        'ready', pg_catalog.jsonb_build_object('n', m.n_ready, 'md5', m.md5_ready),
                        'conditioned', pg_catalog.jsonb_build_object('n', m.n_cond, 'md5', m.md5_cond)) FROM d1_m m),
    'd1_measured', (SELECT pg_catalog.to_jsonb(m) FROM d1_m m),
    'd1_ready_pricing_rows', COALESCE((SELECT pg_catalog.jsonb_object_agg(code, pg_catalog.jsonb_build_object('pscid', pscid, 'psvm', psvm)) FROM d1_ready_pr), '{{}}'::jsonb),
    'd1_hold_by_key', COALESCE((SELECT pg_catalog.jsonb_object_agg(k, n) FROM d1_hold_bk), '{{}}'::jsonb),
    'd_session', pg_catalog.jsonb_build_object(
        'current_user', current_user,
        'server_version_num', pg_catalog.current_setting('server_version_num'),
        'transaction_read_only', pg_catalog.current_setting('transaction_read_only'),
        'snapshot', pg_catalog.pg_current_snapshot()::text,
        'backend_pid', pg_catalog.pg_backend_pid(),
        'checked_at', pg_catalog.clock_timestamp())
) AS d1_identity
  FROM gates g;
"""
OUT.write_text(sql)
print('md5', hashlib.md5(sql.encode()).hexdigest(), 'bytes', len(sql.encode()))
