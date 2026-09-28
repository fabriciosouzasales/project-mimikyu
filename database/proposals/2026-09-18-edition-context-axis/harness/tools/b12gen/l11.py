# L11 — Seção M (SM1–SM11), reempacotamento da 2833 v2.0. E13 + E13P.
# Sem TEMP: SMREC é UMA consulta agregada (rows reais + controles em memória,
# mesmo texto de predicado). SM4/SM6/SM10(i)/SM11 ganham fixture (P5): jobs e
# rows sentinela, predicado idêntico aplicado ao escopo do marcador.
from lib import *
import pre, jr
from jr import PICK, job, row, nd, ROW, JOB

OPS = "('RECEIVED','PROCESSING','STAGED','CONFIRMING')"
ST8 = "('RECEIVED','PROCESSING','STAGED','CONFIRMING','COMPLETED','COMPLETED_WITH_ERRORS','FAILED','CANCELLED')"
# classificadores da 2833 (2145:270/286/307/314/324) — texto ÚNICO
MUT = f"(job_status IN {OPS} AND per = 'PENDING')"
CONF = "(job_status IN ('STAGED','CONFIRMING') AND per = 'PENDING' AND dec = 'APPROVED' AND val = 'VALID')"

P = {
    'sm1':    f"job_status NOT IN {ST8}",
    'sm2':    "per NOT IN ('PENDING','INSERTED','UNCHANGED','FAILED','SKIPPED')",
    'sm3a':   "per = 'INSERTED' AND res IS NULL",
    'sm3b':   "per = 'UNCHANGED' AND dec <> 'SKIPPED' AND res IS NULL AND mat IS NULL",
    'sm4':    f"{CONF} AND res IS NOT NULL",
    'sm7':    f"{MUT} AND val = 'VALID' AND NOT has_key",
    'sm10ii': f"{CONF} AND (vt IS NULL OR NOT has_pp OR NOT has_key)",
}
# SM8 é, por declaração do contrato, a MESMA consulta do SM7 (não é prova independente)
P['sm8'] = P['sm7']
U = {
    'u_rows':        'true',
    'u_mut':         MUT,
    'u_conf':        CONF,
    'u_lineage':     "per IN ('INSERTED','UNCHANGED')",
    'u_sm5_term_vp': f"val = 'VALID' AND per = 'PENDING' AND job_status NOT IN {OPS}",
    'u_sm5':         f"{MUT} AND job_status NOT IN {OPS}",
    'u_sm6':         f"{CONF} AND NOT {MUT}",
    'u_mut_valid':   f"{MUT} AND val = 'VALID'",
    'u_cancel':      "job_status = 'CANCELLED'",
    'u_sm9':         f"job_status = 'CANCELLED' AND ({MUT} OR {CONF})",
    'u_hist_nokey':  f"NOT {MUT} AND NOT has_key",
    'u_sm11':        f"NOT {MUT} AND NOT has_key AND {CONF}",
    'u_nr_mut':      f"{MUT} AND val = 'NEEDS_REVIEW'",
}
N = 'NULL'
U1 = "'00000000-0000-4000-8000-0000000000c1'"
# controles em memória: (tag, job_status, val, dec, per, has_key, has_pp, vt, res, mat)
CTRL = [
    ('sm1', 'H2830_DESCONHECIDO', 'VALID', 'APPROVED', 'INSERTED', 'true', 'true', "'vt'", U1, N),
    ('sm2', 'COMPLETED', 'VALID', 'APPROVED', 'H2830_DESCONHECIDO', 'true', 'true', "'vt'", U1, N),
    ('sm3a', 'COMPLETED', 'VALID', 'APPROVED', 'INSERTED', 'true', 'true', "'vt'", N, N),
    ('sm3b', 'COMPLETED', 'VALID', 'APPROVED', 'UNCHANGED', 'true', 'true', "'vt'", N, N),
    ('sm4', 'STAGED', 'VALID', 'APPROVED', 'PENDING', 'true', 'true', "'vt'", U1, N),
    ('sm7', 'STAGED', 'VALID', 'PENDING', 'PENDING', 'false', 'true', "'vt'", N, N),
    ('sm8', 'CONFIRMING', 'VALID', 'PENDING', 'PENDING', 'false', 'true', "'vt'", N, N),
    ('sm10ii', 'STAGED', 'VALID', 'APPROVED', 'PENDING', 'false', 'true', "'vt'", N, N),
]

SRC_COLS = """j.status AS job_status, r.validation_status AS val, r.decision_status AS dec, r.persistence_status AS per,
           jsonb_exists(r.normalized_data, 'edition_context_profile_id') AS has_key,
           jsonb_exists(r.normalized_data, 'printing_profile_id') AS has_pp,
           r.normalized_data ->> 'variant_type_id' AS vt,
           r.resulting_variant_id AS res, r.matched_variant_id AS mat"""
SRC_FROM = """  FROM public.catalog_variant_import_row r
  JOIN public.catalog_variant_import_job j ON j.id = r.job_id"""
FX_WHERE = " WHERE j.external_set_id LIKE v_marker || '\\_J%'"


def smrec():
    ctrl = ',\n           '.join('(' + ', '.join([q('CTRL_' + t), q(js), q(v), q(d), q(p), f'{hk}', f'{hp}', f'{vt}::text',
                                                  f'{rs}::uuid', f'{mt}::uuid']) + ')'
                                  for (t, js, v, d, p, hk, hp, vt, rs, mt) in CTRL)
    s = f"""WITH x AS (
    SELECT 'REAL'::text AS src, {SRC_COLS}
    {SRC_FROM.strip()}
    UNION ALL
    SELECT * FROM (VALUES {ctrl}) AS c(src, job_status, val, dec, per, has_key, has_pp, vt, res, mat)
)
SELECT jsonb_build_object(
"""
    it = []
    for k, p in P.items():
        it.append(f"    '{k}', count(*) FILTER (WHERE src = 'REAL' AND ({p}))")
        it.append(f"    '{k}_ctrl', count(*) FILTER (WHERE src = 'CTRL_{k}' AND ({p}))")
    for k, p in U.items():
        it.append(f"    '{k}', count(*) FILTER (WHERE src = 'REAL' AND ({p}))")
    it.append("    'st_distinct', count(DISTINCT job_status) FILTER (WHERE src = 'REAL')")
    it.append("    'per_distinct', count(DISTINCT per) FILTER (WHERE src = 'REAL')")
    return s + ',\n'.join(it) + ')\n  FROM x'


PRE = """
    -- ------------------------------------------------------------------ --
    -- MATRIZ ÚNICA (SMREC) — rows reais + controles em memória; erro = FAIL
    -- ------------------------------------------------------------------ --
    v_case := 'SMREC';
    BEGIN
""" + ind(smrec(), 8) + """
          INTO STRICT v_agg;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
        RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
            'H2830_FAIL: envelope=%s caso=SMREC matriz falhou sqlstate=%s msg=%s', c_env, v_state, v_msg);
    END;
    SELECT ARRAY(SELECT c.id FROM public.card c
                   JOIN public.card_set cs ON cs.id = c.card_set_id
                   JOIN public.expansion e ON e.id = cs.expansion_id
                  WHERE e.game_id = v_game ORDER BY c.id LIMIT 16) INTO v_cards;
    IF cardinality(v_cards) <> 16 THEN
        RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
            'H2830_FAIL: envelope=%s caso=PREFLIGHT fixture de 16 Cards indisponível (%s)', c_env, cardinality(v_cards));
    END IF;
"""


def g(k):
    return f"(v_agg->>'{k}')::bigint"


def pc(keys):
    b = ''
    for k in keys:
        b += iff(f"{g(k)} <> 0", f'{k}: %s row(s) REAIS violam o predicado', g(k))
        b += iff(f"{g(k + '_ctrl')} <> 1", f'{k}: controle negativo NÃO detectado (%s, esperado 1)', g(k + '_ctrl'))
    return b


def uni(k, what):
    return iff(f"{g(k)} = 0", f'{what}: universo vazio (P13)')


def fx_count(pred, into, extra_where=''):
    return sql(f"SELECT count(*) FILTER (WHERE {pred}) INTO {into}\n"
               f"  FROM (SELECT {SRC_COLS}, r.id\n        {SRC_FROM.strip()}\n       {FX_WHERE.strip()}{extra_where}) z;")


def sm4():
    b = pc(['sm4'])
    b += PICK
    b += sql("SELECT cv.id INTO v_cv FROM public.card_variant cv ORDER BY cv.id LIMIT 1;")
    b += iff('v_cv IS NULL', 'nenhuma card_variant para o controle (STOP, ver precheck)')
    b += job('v_job1', 'STAGED', '1')
    b += row('v_r1', 'v_job1', nd(vt='v_vt', pp='NULL', ec='NULL'), 'VALID', 'PENDING', 'APPROVED',
             extra_cols='resulting_variant_id', extra_vals='v_cv')
    b += fx_count(P['sm4'], 'v_n')
    b += iff('v_n <> 1', 'SM4 fixture: row confirmável com resulting_variant_id NÃO detectada (%s, esperado 1)', 'v_n')
    return b


def sm6():
    b = PICK
    b += sql("v_jobs := ARRAY[]::uuid[];")
    for i, st in enumerate(['RECEIVED', 'PROCESSING', 'STAGED', 'CONFIRMING', 'COMPLETED', 'COMPLETED_WITH_ERRORS', 'FAILED', 'CANCELLED'], 1):
        b += job('v_job1', st, str(i)) + sql("v_jobs := v_jobs || v_job1;")
    b += sql(f"""INSERT INTO {ROW} (job_id, card_id, raw_data, normalized_data, validation_status, decision_status, persistence_status)
SELECT jb.id, v_cards[(k.i / 4) + 1], '{{}}'::jsonb,
       jsonb_build_object('variant_type_id', v_vt,
                          'printing_profile_id', CASE WHEN k.i % 2 = 1 THEN v_pp END,
                          'edition_context_profile_id', CASE WHEN (k.i / 2) % 2 = 1 THEN v_ec END),
       k.v, k.d, k.p
  FROM unnest(v_jobs) AS jb(id)
 CROSS JOIN (SELECT p, d, v, (row_number() OVER (ORDER BY p, d, v) - 1)::int AS i
               FROM unnest(ARRAY['PENDING','INSERTED','UNCHANGED','FAILED']) AS p
              CROSS JOIN unnest(ARRAY['PENDING','APPROVED','REJECTED','SKIPPED']) AS d
              CROSS JOIN unnest(ARRAY['PENDING','VALID','NEEDS_REVIEW','INVALID']) AS v) AS k;
GET DIAGNOSTICS v_m = ROW_COUNT;""")
    b += iff('v_m <> 512', 'SM6 fixture: %s rows enumeradas (esperado 8 × 4 × 4 × 4 = 512)', 'v_m')
    b += fx_count(f"{CONF} AND NOT {MUT}", 'v_n')
    b += iff('v_n <> 0', 'SM6: %s combinação(ões) confirmável(is) fora do universo mutável', 'v_n')
    b += fx_count(CONF, 'v_k')
    b += iff('v_k <> 2', 'SM6: classificador confirmável marcou %s combinação(ões) (esperado 2: STAGED e CONFIRMING × PENDING/APPROVED/VALID)', 'v_k')
    b += fx_count(MUT, 'v_k')
    b += iff('v_k <> 64', 'SM6: classificador mutável marcou %s (esperado 4 status × PENDING × 16 = 64)', 'v_k')
    b += iff(f"{g('u_sm6')} <> 0", 'SM6 real: %s row(s) confirmáveis fora do mutável', g('u_sm6'))
    return b


def sm10():
    b = pc(['sm10ii'])
    b += PICK
    b += job('v_job1', 'STAGED', '1') + job('v_job2', 'CANCELLED', '2')
    full = nd(vt='v_vt', pp='NULL', ec='NULL')
    b += row('v_r1', 'v_job1', full, 'VALID', 'PENDING', 'APPROVED', card='v_cards[1]')
    b += row('v_r2', 'v_job2', full, 'VALID', 'PENDING', 'APPROVED', card='v_cards[1]')
    b += row('v_r3', 'v_job1', full, 'VALID', 'FAILED', 'APPROVED', card='v_cards[2]')
    b += row('v_r4', 'v_job1', full, 'VALID', 'PENDING', 'REJECTED', card='v_cards[3]')
    b += row('v_r5', 'v_job1', full, 'NEEDS_REVIEW', 'PENDING', 'APPROVED', card='v_cards[4]')
    b += sql(f"SELECT array_agg(({CONF}) ORDER BY z.ord)\n"
             f"  INTO v_barr\n"
             f"  FROM (SELECT {SRC_COLS}, array_position(ARRAY[v_r1, v_r2, v_r3, v_r4, v_r5], r.id) AS ord\n"
             f"        {SRC_FROM.strip()}\n"
             f"         WHERE r.id = ANY (ARRAY[v_r1, v_r2, v_r3, v_r4, v_r5])) z;")
    b += iff("v_barr IS DISTINCT FROM ARRAY[true, false, false, false, false]",
             'SM10(i): classificador pode_confirmar [base, CANCELLED, persistence≠PENDING, decision≠APPROVED, NEEDS_REVIEW] = %s (esperado [t,f,f,f,f])', 'v_barr')
    return b


def sm11():
    b = uni('u_hist_nokey', 'SM11')
    b += iff(f"{g('u_sm11')} <> 0", 'SM11 real: %s row(s) históricas sem chave classificadas como confirmáveis', g('u_sm11'))
    b += PICK
    b += job('v_job1', 'COMPLETED', '1') + job('v_job2', 'CANCELLED', '2')
    nokey = nd(vt='v_vt', pp='NULL')
    b += row('v_r1', 'v_job1', nokey, 'VALID', 'PENDING', 'APPROVED', card='v_cards[1]')
    b += row('v_r2', 'v_job2', nokey, 'VALID', 'PENDING', 'APPROVED', card='v_cards[1]')
    b += fx_count(f"NOT {MUT} AND NOT has_key", 'v_k')
    b += iff('v_k <> 2', 'SM11 fixture: universo histórico sem chave = %s (esperado 2)', 'v_k')
    b += fx_count(f"NOT {MUT} AND NOT has_key AND {CONF}", 'v_n')
    b += iff('v_n <> 0', 'SM11 fixture: %s row(s) históricas sem chave classificadas como confirmáveis', 'v_n')
    return b


CASES = [
    ('SM1', 'SM1 [AUTO EX] vocabulário de job.status (8 valores do CHECK)', pc(['sm1']) + uni('u_rows', 'SM1')),
    ('SM2', 'SM2 [AUTO EX] vocabulário de persistence_status', pc(['sm2']) + uni('u_rows', 'SM2')),
    ('SM3', 'SM3 [AUTO EX] nenhuma row terminal sem efeito, por classe (ROWS sem lineage)', pc(['sm3a', 'sm3b']) + uni('u_lineage', 'SM3')),
    ('SM4', 'SM4 [AUTO EX+FX] nenhuma row confirmável com resulting_variant_id; controle em fixture', sm4()),
    ('SM5', 'SM5 [AUTO EX] nenhuma row mutável em job terminal (interseção medida)',
     iff(f"{g('u_sm5')} <> 0", 'SM5: %s row(s) mutáveis em job terminal', g('u_sm5')) + uni('u_sm5_term_vp', 'SM5')),
    ('SM6', 'SM6 [AUTO EX+FX] todo confirmável está no mutável; enumeração 8×4×4×4 em fixture', sm6()),
    ('SM7', 'SM7 [AUTO EX] zero row mutável VALID sem a chave', pc(['sm7'])),
    ('SM8', 'SM8 [AUTO EX] toda row sem chave é histórica ou não-VALID (DECLARADO = SM7)', pc(['sm8'])),
    ('SM9', 'SM9 [AUTO EX] nenhuma row CANCELLED mutável ou confirmável',
     iff(f"{g('u_sm9')} <> 0", 'SM9: %s row(s) CANCELLED mutáveis/confirmáveis', g('u_sm9')) + uni('u_cancel', 'SM9')),
    ('SM10', 'SM10 [AUTO FX] (i) classificador em fixture + 4 negações; (ii) universo real + controle em memória', sm10()),
    ('SM11', 'SM11 [AUTO EX+FX] nenhuma row histórica sem chave é confirmável', sm11()),
]

HEAD = header(['2830H · ENVELOPE E13 — SEÇÃO M (STATE MACHINE job-aware, SM1–SM11) · lote L11, 11 casos'], [
    'Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO, NÃO COMPILADO no',
    '                PostgreSQL (BATCH12 — INTEGRATED COMPLETION, baseline 945caa32).',
    '                Execução exige E00 + E13P gate_pass = true e mandato próprio.',
    'Contrato ...... 2830 v7.0 Seção M; fonte lógica 2833 v2.0 (arquivo NÃO alterado).',
    'Classificador . pode_mutar / pode_confirmar = texto único (2145), usado em REAL,',
    '                controles em memória e fixtures.',
    'P13 ........... SM1–3, SM7, SM8, SM10(ii): real = 0 e controle = 1 (mesmo texto).',
    '                SM4, SM6, SM10(i), SM11: fixture. SM5/SM9: universo medido > 0',
    '                (propriedade da definição, declarada). SM8 = SM7 (declarado).',
    'Escrita (R4) .. job 1–8 por caso · row: SM4 1, SM6 512, SM10 5, SM11 2.',
    '                Nenhum UPDATE/DELETE. Tudo desfeito pelo término em exceção.',
    'P8 ............ SET LOCAL lock_timeout = \'5s\' + asserção (DP-4 = A).',
])


def e13():
    spec = dict(tag='h2830_e13', env='E13_SECAO_M_STATE_MACHINE', header=HEAD,
                decl=jr.PICK_DECL + [('v_agg', 'jsonb', None), ('v_cards', 'uuid[]', None), ('v_jobs', 'uuid[]', None),
                                     ('v_job1', 'uuid', None), ('v_job2', 'uuid', None), ('v_cv', 'uuid', None),
                                     ('v_r1', 'uuid', None), ('v_r2', 'uuid', None), ('v_r3', 'uuid', None),
                                     ('v_r4', 'uuid', None), ('v_r5', 'uuid', None), ('v_k', 'bigint', None),
                                     ('v_barr', 'boolean[]', None)],
                reset=['v_card', 'v_cs', 'v_vt', 'v_pp', 'v_ec', 'v_jobs', 'v_job1', 'v_job2', 'v_cv',
                       'v_r1', 'v_r2', 'v_r3', 'v_r4', 'v_r5', 'v_k', 'v_barr'],
                preflight_extra=PRE, cases=CASES,
                term_fields=[('u_rows', "v_agg->>'u_rows'"), ('u_mut', "v_agg->>'u_mut'"), ('u_conf', "v_agg->>'u_conf'"),
                             ('u_nr_mut', "v_agg->>'u_nr_mut'"), ('u_hist_nokey', "v_agg->>'u_hist_nokey'"),
                             ('u_cancel', "v_agg->>'u_cancel'")])
    return envelope(spec)


PHEAD = header(['2830H · E13P — PRECHECK DO LOTE L11 (Seção M)'], [
    'Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO. SELECT único.',
    'Cobre ......... P7X (job/row), bloco JOB/ROW (tokens do guard, CHECKs, índices,',
    '                fixture de 16 Cards, card_variant >= 1, jobs em voo = 0),',
    '                XBASELINE, marcador.',
])


def e13p():
    ctes = [pre.GS, pre.P7X, pre.XBASE, jr.JR_CTES]
    gates = pre.GS_GATE + '\n' + pre.P7X_GATES + '\n' + pre.XBASE_GATE + '\n' + pre.MK_GATE + '\n' + jr.JR_GATES
    det = pre.P7X_DETAIL + '\n' + pre.XBASE_DETAIL + '\n' + jr.JR_DETAIL + '\n' + pre.SESSION_DETAIL
    return pre.precheck(PHEAD, ctes, gates, det, 'e13p_precheck')
