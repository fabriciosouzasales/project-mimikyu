# L10 — Seção B (V1–V14), reempacotamento da 2832 v3.1 no envelope P2.
# E12 (envelope, zero escrita) + E12P (precheck). Sem TEMP: o recomputo é UMA
# consulta agregada (VREC) executada uma vez, antes dos casos, dentro de
# subtransação própria; cada caso só lê o jsonb v_agg.
#
# P13 — cada predicado é UMA expressão Python aplicada, no mesmo FILTER, às
# rows REAIS e a rows de CONTROLE (VALUES, em memória, sem escrita) que violam
# exatamente aquele predicado: real = 0 E controle = 1. Universo vazio sob
# FREEZE deixa de ser PASS vácuo: o controle prova que o predicado detecta.
#
# Desempenho (AD-2/P9a) — a 2211 só é chamada para o universo que algum
# predicado lê com "esperado": op ∪ (NOT op ∧ observado ≠ ABSENT). Prova de
# equivalência: todo predicado com `exp` exige op (V1–V3, V6, V9) ou
# observado ≠ ABSENT (V13: 'NULL'; V14c: ≠ 'ABSENT'); V1_NO_OCCURRENCE conta
# esperado = UUID nesse universo (ver D-V1 na auditoria).
from lib import *
import pre, jr

OPS = "('RECEIVED','PROCESSING','STAGED','CONFIRMING')"

# predicados — texto ÚNICO usado para REAL e CONTROLE
P = {
    'v1_div': "op AND exp = 'UUID' AND obs_uuid IS DISTINCT FROM exp_uuid",
    'v2':     "op AND obs = 'NULL' AND exp <> 'NULL'",
    'v3':     "op AND exp = 'ABSENT' AND obs <> 'ABSENT'",
    'v4':     "op AND val = 'VALID' AND obs = 'ABSENT'",
    'v6':     "op AND obs <> exp",
    'v7a':    "per = 'INSERTED' AND res IS NULL",
    'v7b':    "per = 'UNCHANGED' AND dec <> 'SKIPPED' AND res IS NULL AND mat IS NULL",
    'v7c':    "per = 'PENDING' AND res IS NOT NULL",
    'v9':     "op AND obs = 'ABSENT' AND exp IN ('UUID','NULL')",
    'v13':    "NOT op AND obs = 'NULL' AND exp = 'ABSENT'",
    'v14c':   "job_status = 'CANCELLED' AND obs <> 'ABSENT' AND exp = 'ABSENT'",
}
# universos / existência (REAL apenas)
U = {
    'u_total':      "true",
    'u_op':         "op",
    'u_rechecked':  "rechecked",
    'u_v1_occ':     "rechecked AND exp = 'UUID'",
    'u_v5':         "NOT op AND val = 'VALID' AND obs = 'ABSENT'",
    'u_hist_null':  "NOT op AND obs = 'NULL'",
    'u_cancel_vp':  "job_status = 'CANCELLED' AND val = 'VALID' AND per = 'PENDING'",
    'u_v14b':       "job_status = 'CANCELLED' AND op",
    'u_v7_skip':    "per = 'UNCHANGED' AND dec = 'SKIPPED' AND res IS NULL AND mat IS NULL",
    'u_op_missing': "op AND NOT rechecked",
    'u_exp_null':   "rechecked AND exp IS NULL",
}
# controles: (tag, job_status, per, val, dec, obs, obs_uuid, exp, exp_uuid, res, mat)
N = 'NULL'
U1, U2 = "'00000000-0000-4000-8000-0000000000c1'", "'00000000-0000-4000-8000-0000000000c2'"
CTRL = [
    ('v1_div', 'STAGED', 'PENDING', 'VALID', 'APPROVED', 'UUID', U1, 'UUID', U2, N, N),
    ('v2', 'STAGED', 'PENDING', 'VALID', 'PENDING', 'NULL', N, 'ABSENT', N, N, N),
    ('v3', 'STAGED', 'PENDING', 'NEEDS_REVIEW', 'PENDING', 'UUID', U1, 'ABSENT', N, N, N),
    ('v4', 'STAGED', 'PENDING', 'VALID', 'PENDING', 'ABSENT', N, 'ABSENT', N, N, N),
    ('v6', 'CONFIRMING', 'PENDING', 'VALID', 'APPROVED', 'NULL', N, 'UUID', U2, N, N),
    ('v7a', 'COMPLETED', 'INSERTED', 'VALID', 'APPROVED', 'UUID', U1, 'UUID', U1, N, N),
    ('v7b', 'COMPLETED', 'UNCHANGED', 'VALID', 'APPROVED', 'UUID', U1, 'UUID', U1, N, N),
    ('v7c', 'STAGED', 'PENDING', 'VALID', 'APPROVED', 'UUID', U1, 'UUID', U1, U2, N),
    ('v9', 'RECEIVED', 'PENDING', 'NEEDS_REVIEW', 'PENDING', 'ABSENT', N, 'NULL', N, N, N),
    ('v13', 'COMPLETED', 'INSERTED', 'VALID', 'APPROVED', 'NULL', N, 'ABSENT', N, U2, N),
    ('v14c', 'CANCELLED', 'PENDING', 'VALID', 'PENDING', 'UUID', U1, 'ABSENT', N, N, N),
]


def _lit(v):
    return v if v in (N,) or v.startswith("'") else q(v)


def vrec(game, src):
    """consulta agregada única (V1–V9, V13, V14): devolve 1 jsonb"""
    ctrl_rows = ',\n           '.join(
        '(' + ', '.join([q('CTRL_' + t), q(js), q(per), q(val), q(dec), q(obs), f'{_lit(ou)}::text', q(ex),
                          f'{_lit(eu)}::text', f'{_lit(rs)}::uuid', f'{_lit(mt)}::uuid']) + ')'
        for (t, js, per, val, dec, obs, ou, ex, eu, rs, mt) in CTRL)
    base = f"""WITH base AS (
    SELECT r.id, j.status AS job_status,
           (j.status IN {OPS} AND r.persistence_status = 'PENDING') AS op,
           r.validation_status AS val, r.persistence_status AS per, r.decision_status AS dec,
           CASE WHEN NOT jsonb_exists(r.normalized_data, 'edition_context_profile_id') THEN 'ABSENT'
                WHEN jsonb_typeof(r.normalized_data -> 'edition_context_profile_id') = 'null' THEN 'NULL'
                ELSE 'UUID' END AS obs,
           r.normalized_data ->> 'edition_context_profile_id' AS obs_uuid,
           r.resulting_variant_id AS res, r.matched_variant_id AS mat, r.raw_data, c.card_set_id
      FROM public.catalog_variant_import_row r
      JOIN public.catalog_variant_import_job j ON j.id = r.job_id
      JOIN public.card c ON c.id = r.card_id
),
rc AS (
    SELECT b.id,
           CASE ax.edition_context_state
                WHEN 'RESOLVED_WITH_EC_PROFILE'    THEN 'UUID'
                WHEN 'RESOLVED_NO_EDITION_CONTEXT' THEN 'NULL'
                ELSE 'ABSENT' END AS exp,
           ax.edition_context_profile_id::text AS exp_uuid
      FROM base b
      LEFT JOIN LATERAL internal.resolve_variant_mapping_scope(b.card_set_id, {src}) sc ON true
     CROSS JOIN LATERAL internal.resolve_variant_row_axes(b.raw_data, {game}, {src}, sc.external_set_id) ax
     WHERE b.op OR b.obs <> 'ABSENT'
),
ctrl(src, job_status, per, val, dec, obs, obs_uuid, exp, exp_uuid, res, mat) AS (
    VALUES {ctrl_rows}
),
x AS (
    SELECT 'REAL'::text AS src, b.job_status, b.op, b.val, b.per, b.dec, b.obs, b.obs_uuid,
           r.exp, r.exp_uuid, b.res, b.mat, (r.id IS NOT NULL) AS rechecked
      FROM base b LEFT JOIN rc r ON r.id = b.id
    UNION ALL
    SELECT c.src, c.job_status, (c.job_status IN {OPS} AND c.per = 'PENDING'), c.val, c.per, c.dec, c.obs, c.obs_uuid,
           c.exp, c.exp_uuid, c.res, c.mat, true
      FROM ctrl c
)
SELECT jsonb_build_object(
"""
    items = []
    for k, p in P.items():
        items.append(f"    '{k}', count(*) FILTER (WHERE src = 'REAL' AND ({p}))")
        items.append(f"    '{k}_ctrl', count(*) FILTER (WHERE src = 'CTRL_{k}' AND ({p}))")
    for k, p in U.items():
        items.append(f"    '{k}', count(*) FILTER (WHERE src = 'REAL' AND ({p}))")
    items.append("    'rc_rows', (SELECT count(*) FROM rc)")
    items.append("    'rc_ids', (SELECT count(DISTINCT id) FROM rc)")
    return base + ',\n'.join(items) + ')\n  FROM x'


def vrec_stmt():
    return vrec('v_game', 'v_src')


PRE = """
    -- ------------------------------------------------------------------ --
    -- RECOMPUTO ÚNICO (VREC) — subtransação própria; erro = H2830_FAIL
    -- ------------------------------------------------------------------ --
    v_case := 'VREC';
    BEGIN
""" + ind(vrec_stmt(), 8) + """
          INTO STRICT v_agg;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
        RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
            'H2830_FAIL: envelope=%s caso=VREC recomputo falhou sqlstate=%s msg=%s', c_env, v_state, v_msg);
    END;
    IF (v_agg->>'rc_rows')::bigint IS DISTINCT FROM (v_agg->>'rc_ids')::bigint
       OR (v_agg->>'u_op_missing')::bigint <> 0 OR (v_agg->>'u_exp_null')::bigint <> 0 THEN
        RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
            'H2830_FAIL: envelope=%s caso=VREC recomputo não é 1:1 rc_rows=%s rc_ids=%s op_sem_recheck=%s exp_nulo=%s',
            c_env, v_agg->>'rc_rows', v_agg->>'rc_ids', v_agg->>'u_op_missing', v_agg->>'u_exp_null');
    END IF;
"""


def g(k):
    return f"(v_agg->>'{k}')::bigint"


def pc(keys, extra=''):
    """real = 0 e controle próprio = 1 (e nenhum outro controle dispara além do esperado)"""
    b = ''
    for k in keys:
        b += iff(f"{g(k)} <> 0", f'{k}: %s row(s) REAIS violam o predicado', g(k))
        b += iff(f"{g(k + '_ctrl')} <> 1", f'{k}: controle negativo NÃO detectado (%s, esperado 1) — predicado vácuo', g(k + '_ctrl'))
    return b + extra


def case_v1():
    """D-V1: a existência (">= 1 ocorrência") é medida, como na 2832, sobre a
    TABELA INTEIRA. O VREC já cobre op ∪ (histórico com chave); só se ali não
    houver ocorrência o complemento (histórico SEM chave) é recomputado, com
    EXISTS (para na primeira) — mesmo resultado lógico, custo proporcional."""
    b = pc(['v1_div'])
    b += sql(f"""v_occ := {g('u_v1_occ')};
IF v_occ = 0 THEN
    SELECT count(*) INTO v_occ
      FROM (SELECT 1
              FROM public.catalog_variant_import_row r
              JOIN public.catalog_variant_import_job j ON j.id = r.job_id
              JOIN public.card c ON c.id = r.card_id
              LEFT JOIN LATERAL internal.resolve_variant_mapping_scope(c.card_set_id, v_src) sc ON true
             CROSS JOIN LATERAL internal.resolve_variant_row_axes(r.raw_data, v_game, v_src, sc.external_set_id) ax
             WHERE NOT (j.status IN {OPS} AND r.persistence_status = 'PENDING')
               AND NOT jsonb_exists(r.normalized_data, 'edition_context_profile_id')
               AND ax.edition_context_state = 'RESOLVED_WITH_EC_PROFILE'
             LIMIT 1) z;
END IF;""")
    b += iff('v_occ = 0', 'V1_NO_OCCURRENCE: nenhuma row da staging resolve para profile (tabela inteira)')
    return b


def case_v5():
    return iff(f"{g('u_v5')} = 0", 'V5: nenhuma row HISTÓRICA VALID sem chave (escopo vazou ou HOLD recebeu null)')


def case_v7():
    return pc(['v7a', 'v7b', 'v7c'])


def case_v8():
    b = sql(f"""WITH l AS (
    SELECT 'REAL'::text AS src, r.resulting_variant_id AS res, r.raw_data,
           CASE WHEN NOT jsonb_exists(r.normalized_data, 'edition_context_profile_id') THEN 'ABSENT'
                WHEN jsonb_typeof(r.normalized_data -> 'edition_context_profile_id') = 'null' THEN 'NULL'
                ELSE 'UUID' END AS obs
      FROM public.catalog_variant_import_row r
     WHERE r.resulting_variant_id IS NOT NULL
    UNION ALL
    SELECT 'CTRL', {U1}::uuid, '{{}}'::jsonb, 'UUID'
    UNION ALL
    SELECT 'CTRL', {U1}::uuid, '{{}}'::jsonb, 'NULL'
), d AS (
    SELECT src, res FROM l GROUP BY src, res
    HAVING count(DISTINCT obs) > 1 AND count(DISTINCT raw_data) = 1
)
SELECT count(*) FILTER (WHERE src = 'REAL'), count(*) FILTER (WHERE src = 'CTRL'),
       (SELECT count(DISTINCT res) FROM l WHERE src = 'REAL')
  INTO v_n, v_m, v_u8
  FROM d;""")
    b += iff('v_n <> 0', 'V8: %s Variant(s) com rows de mesmo raw_data e destinos diferentes', 'v_n')
    b += iff('v_m <> 1', 'V8: controle negativo NÃO detectado (%s, esperado 1)', 'v_m')
    b += iff('v_u8 = 0', 'V8: universo de lineage vazio (nenhuma Variant com row)')
    return b


def case_v10():
    b = sql("SELECT count(*) INTO v_n\n"
            "  FROM pg_trigger t\n"
            " WHERE t.tgrelid = to_regclass('public.catalog_variant_import_row')\n"
            "   AND t.tgname = 'trg_cvir_normalized_shape' AND NOT t.tgisinternal AND t.tgenabled = 'O'\n"
            "   AND t.tgfoid = to_regprocedure('internal.guard_cvir_normalized_shape()');\n"
            "SELECT p.prosrc INTO v_txt FROM pg_proc p WHERE p.oid = to_regprocedure('internal.guard_cvir_normalized_shape()');")
    b += iff('v_n <> 1', 'V10: trg_cvir_normalized_shape ausente, desabilitado ou com tgfoid divergente (%s)', 'v_n')
    b += iff("v_txt IS NULL OR strpos(v_txt, 'CVIR_OPERATIONAL_VALID_REQUIRES_EDITION_CONTEXT_KEY') = 0\n"
             "           OR strpos(v_txt, 'CVIR_EDITION_CONTEXT_KEY_REMOVAL_FORBIDDEN') = 0\n"
             "           OR strpos(v_txt, 'CVIR_PENDING_VALID_REQUIRES_EDITION_CONTEXT_KEY') <> 0",
             'V10: guard não é o ESTRITO da 2214 v3.1 (tokens exigidos ausentes ou token obsoleto presente)')
    return b


def case_v11():
    tok = 'internal.axis_identity_token'
    b = sql(f"""WITH ids AS (
    SELECT 'REAL'::text AS src, r.job_id, r.card_id, (r.normalized_data ->> 'variant_type_id') AS vt,
           {tok}(r.normalized_data, 'printing_profile_id') AS tp,
           {tok}(r.normalized_data, 'edition_context_profile_id') AS te
      FROM public.catalog_variant_import_row r
     WHERE (r.normalized_data ->> 'variant_type_id') IS NOT NULL
    UNION ALL
    SELECT 'CTRL', {U1}::uuid, {U2}::uuid, 'vt',
           {tok}(jsonb_build_object('printing_profile_id', NULL), 'printing_profile_id'),
           {tok}('{{}}'::jsonb, 'edition_context_profile_id')
      FROM generate_series(1, 2)
), d AS (
    SELECT src FROM ids GROUP BY src, job_id, card_id, vt, tp, te HAVING count(*) > 1
)
SELECT count(*) FILTER (WHERE src = 'REAL'), count(*) FILTER (WHERE src = 'CTRL') INTO v_n, v_m FROM d;""")
    b += iff('v_n <> 0', 'V11: %s identidade(s) de staging duplicada(s)', 'v_n')
    b += iff('v_m <> 1', 'V11: controle negativo NÃO detectado (%s, esperado 1)', 'v_m')
    b += iff(f"{tok}('{{}}'::jsonb, 'k') IS DISTINCT FROM 'A'\n"
             f"           OR {tok}('{{\"k\":null}}'::jsonb, 'k') IS DISTINCT FROM 'N'\n"
             f"           OR {tok}('{{\"k\":\"11111111-1111-4111-8111-111111111111\"}}'::jsonb, 'k')\n"
             "              IS DISTINCT FROM 'U:11111111-1111-4111-8111-111111111111'",
             'V11: tri-estado A/N/U degradado')
    return b


def case_v12():
    b = sql(f"""WITH o AS (
    SELECT j.status AS job_status, r.validation_status AS val, r.persistence_status AS per,
           jsonb_typeof(r.normalized_data -> 'edition_context_profile_id') AS ty,
           jsonb_exists(r.normalized_data, 'edition_context_profile_id') AS has_key,
           r.normalized_data ->> 'edition_context_profile_id' AS uuid_txt
      FROM public.catalog_variant_import_row r
      JOIN public.catalog_variant_import_job j ON j.id = r.job_id
), cells AS (
    SELECT CASE WHEN NOT has_key THEN 'ABSENT' WHEN ty = 'null' THEN 'NULL' ELSE 'UUID' END AS obs,
           val, per, job_status, count(*) AS n
      FROM o GROUP BY 1, 2, 3, 4
), orf AS (
    SELECT 'REAL'::text AS src, uuid_txt FROM o WHERE ty = 'string'
    UNION ALL
    SELECT 'CTRL', gen_random_uuid()::text
)
SELECT (SELECT count(*) FROM o),
       (SELECT count(*) FROM o WHERE NOT has_key),
       (SELECT count(*) FROM o WHERE ty = 'null'),
       (SELECT count(*) FROM o WHERE ty = 'string'),
       (SELECT COALESCE(sum(n), 0) FROM cells),
       (SELECT count(*) FROM orf f WHERE f.src = 'REAL'
           AND NOT EXISTS (SELECT 1 FROM public.card_edition_context_profile p WHERE p.id::text = lower(f.uuid_txt))),
       (SELECT count(*) FROM orf f WHERE f.src = 'CTRL'
           AND NOT EXISTS (SELECT 1 FROM public.card_edition_context_profile p WHERE p.id::text = lower(f.uuid_txt)))
  INTO v_n, v_a1, v_a2, v_a3, v_a4, v_a5, v_a6;""")
    b += iff('v_a1 + v_a2 + v_a3 <> v_n OR v_a4 <> v_n',
             'V12(i): partição não fecha total=%s ausente=%s null=%s string=%s soma_células=%s', 'v_n, v_a1, v_a2, v_a3, v_a4')
    b += iff('v_a3 = 0', 'V12(ii): nenhum UUID gravado (universo vazio)')
    b += iff('v_a5 <> 0', 'V12(ii): %s UUID(s) órfão(s)', 'v_a5')
    b += iff('v_a6 <> 1', 'V12(ii): controle de órfão NÃO detectado (%s, esperado 1)', 'v_a6')
    return b


def case_v14():
    b = iff(f"{g('u_cancel_vp')} = 0", 'V14: universo CANCELLED VALID+PENDING vazio (P13)')
    b += iff(f"{g('u_v14b')} <> 0", 'V14: %s row(s) de job CANCELLED classificadas como operacionais', g('u_v14b'))
    b += pc(['v14c'])
    return b


CASES = [
    ('V1', 'V1 [AUTO EX] UUID gravado = UUID do routing (op); >=1 ocorrência é ASSERÇÃO', case_v1()),
    ('V2', 'V2 [AUTO EX] JSON null só onde o routing confirma RESOLVED_NO_EDITION_CONTEXT', pc(['v2'])),
    ('V3', 'V3 [AUTO EX] eixo EC não-terminal não recebeu chave', pc(['v3'])),
    ('V4', 'V4 [AUTO EX] zero row operacional VALID+PENDING sem chave', pc(['v4'])),
    ('V5', 'V5 [AUTO EX] >= 1 row histórica VALID legitimamente sem chave', case_v5()),
    ('V6', 'V6 [AUTO EX] destino observado = recomputado, row a row (op)', pc(['v6'])),
    ('V7', 'V7 [AUTO EX] estados e lineage por classe (INSERTED / UNCHANGED não-SKIPPED / PENDING)', case_v7()),
    ('V8', 'V8 [AUTO EX] lineage 1:N sem destinos divergentes para o mesmo raw_data', case_v8()),
    ('V9', 'V9 [AUTO EX] write-set operacional de uma reavaliação = 0 (sem escrita)', pc(['v9'])),
    ('V10', 'V10 [AUTO RO] guard ESTRITO presente (trigger, tgfoid, tokens; obsoleto ausente)', case_v10()),
    ('V11', 'V11 [AUTO EX] tri-estado não degradado; identidades de staging únicas', case_v11()),
    ('V12', 'V12 [AUTO RO] partição fechada + zero UUID órfão (>= 1 UUID)', case_v12()),
    ('V13', 'V13 [AUTO EX] histórico intocado: nenhum JSON null histórico onde o routing diz indeterminado', pc(['v13'])),
    ('V14', 'V14 [AUTO EX] CANCELLED terminal: universo > 0, nunca operacional, nenhuma indeterminada com chave', case_v14()),
]

HEAD = header(['2830H · ENVELOPE E12 — SEÇÃO B (BACKFILL SEMÂNTICO, V1–V14) · lote L10, 14 casos'], [
    'Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO, NÃO COMPILADO no',
    '                PostgreSQL (BATCH12 — INTEGRATED COMPLETION, baseline 945caa32).',
    '                Execução exige E00 + E12P gate_pass = true e mandato próprio.',
    'Contrato ...... 2830 v7.0 Seção B; fonte lógica 2832 v3.1 (arquivo NÃO alterado).',
    'Desvios v7.0 .. V1 existência = asserção; V10 invertido (guard estrito); V12',
    '                asserção; V13/V14 universo medido. Sem CREATE TEMP; sem NOTICE.',
    'P13 ........... cada predicado roda sobre rows REAIS e sobre 1 row de CONTROLE em',
    '                memória (VALUES) com o MESMO texto: real = 0 e controle = 1.',
    'Desempenho .... 2211 só no universo op ∪ (NOT op ∧ observado ≠ ABSENT) — prova de',
    '                equivalência no cabeçalho do gerador; plano em P9A (EXPLAIN).',
    'Escrita ....... NENHUMA (nem fixture). Término em exceção por uniformidade (P2).',
    'P8 ............ SET LOCAL lock_timeout = \'5s\' + asserção (DP-4 = A).',
])


def e12():
    spec = dict(tag='h2830_e12', env='E12_SECAO_B_BACKFILL_SEMANTICO', header=HEAD,
                decl=[('v_agg', 'jsonb', None), ('v_occ', 'bigint', None), ('v_u8', 'bigint', None), ('v_a1', 'bigint', None), ('v_a2', 'bigint', None),
                      ('v_a3', 'bigint', None), ('v_a4', 'bigint', None), ('v_a5', 'bigint', None), ('v_a6', 'bigint', None)],
                preflight_extra=PRE, cases=CASES,
                term_fields=[('u_total', "v_agg->>'u_total'"), ('u_op', "v_agg->>'u_op'"),
                             ('u_rechecked', "v_agg->>'u_rechecked'"), ('u_v1_occ', "v_agg->>'u_v1_occ'"), ('v1_occ_total', 'v_occ'),
                             ('u_v5', "v_agg->>'u_v5'"), ('u_hist_null', "v_agg->>'u_hist_null'"),
                             ('u_cancel_vp', "v_agg->>'u_cancel_vp'"), ('v7_skip', "v_agg->>'u_v7_skip'")])
    return envelope(spec)


PHEAD = header(['2830H · PRECHECK E12P — SEÇÃO B · lote L10 · SELECT único, read-only'], [
    'Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO.',
    'Gate .......... gate_pass = true exige: Game/fonte únicos; identidade pinada da',
    '                2211/2176/normalize/scope; guard 2214 estrito (tokens) e CHECKs;',
    '                nenhum job em voo; universos baratos medidos (sem 2211): total,',
    '                V5 e CANCELLED VALID+PENDING > 0; >= 1 UUID gravado.',
    'Evidência ..... distribuição observado × validation × persistence × job (V12),',
    '                sempre evidência, nunca gate.',
])


def e12p():
    ctes = [pre.GS, pre.RC, jr.JR_CTES, f"""vu AS (
    SELECT (j.status IN {OPS} AND r.persistence_status = 'PENDING') AS op, j.status AS job_status,
           r.validation_status AS val, r.persistence_status AS per,
           CASE WHEN NOT jsonb_exists(r.normalized_data, 'edition_context_profile_id') THEN 'ABSENT'
                WHEN jsonb_typeof(r.normalized_data -> 'edition_context_profile_id') = 'null' THEN 'NULL'
                ELSE 'UUID' END AS obs
      FROM public.catalog_variant_import_row r
      JOIN public.catalog_variant_import_job j ON j.id = r.job_id
),
vcell AS (
    SELECT obs, val, per, job_status, count(*) AS n FROM vu GROUP BY 1, 2, 3, 4
),"""]
    gates = pre.GS_GATE + '\n' + pre.RC_GATE + '\n' + jr.JR_GATES + """
        ((SELECT count(*) FROM vu) > 0
         AND (SELECT count(*) FROM vu WHERE NOT op AND val = 'VALID' AND obs = 'ABSENT') > 0
         AND (SELECT count(*) FROM vu WHERE job_status = 'CANCELLED' AND val = 'VALID' AND per = 'PENDING') > 0
         AND (SELECT count(*) FROM vu WHERE obs = 'UUID') > 0)                         AS g_v_universes,"""
    det = pre.RC_DETAIL + """
        'd_v_universes',    jsonb_build_object(
                                'total', (SELECT count(*) FROM vu),
                                'op', (SELECT count(*) FROM vu WHERE op),
                                'op_valid', (SELECT count(*) FROM vu WHERE op AND val = 'VALID'),
                                'hist_with_key', (SELECT count(*) FROM vu WHERE NOT op AND obs <> 'ABSENT'),
                                'recheck_universe', (SELECT count(*) FROM vu WHERE op OR obs <> 'ABSENT'),
                                'v5', (SELECT count(*) FROM vu WHERE NOT op AND val = 'VALID' AND obs = 'ABSENT'),
                                'cancel_vp', (SELECT count(*) FROM vu WHERE job_status = 'CANCELLED' AND val = 'VALID' AND per = 'PENDING')),
        'd_jr_checks',      COALESCE((SELECT jsonb_agg(to_jsonb(c) ORDER BY c.conname) FROM jr_ck c), '[]'::jsonb),
        'd_v12_cells',      COALESCE((SELECT jsonb_agg(to_jsonb(c) ORDER BY c.obs, c.val, c.per, c.job_status) FROM vcell c), '[]'::jsonb),
""" + pre.SESSION_DETAIL
    return pre.precheck(PHEAD, ctes, gates, det, 'e12p_precheck')
