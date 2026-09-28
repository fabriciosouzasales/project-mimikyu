# L7 — Seção S (staging): S1–S11 com S2-BIS. E09 + E09P.
from lib import *
import pre, jr
from jr import PICK, job, row, row_stmt, nd, ROW

UQR = ('23505', 'uq_cvir_row_identity', 'catalog_variant_import_row')
TOK = "internal.axis_identity_token"


def s1():
    b = sql("v_u := gen_random_uuid();\n"
            f"v_a := {TOK}('{{}}'::jsonb, 'edition_context_profile_id');\n"
            f"v_nn := {TOK}(jsonb_build_object('edition_context_profile_id', NULL), 'edition_context_profile_id');\n"
            f"v_uu := {TOK}(jsonb_build_object('edition_context_profile_id', v_u), 'edition_context_profile_id');")
    b += iff("v_a IS DISTINCT FROM 'A' OR v_nn IS DISTINCT FROM 'N' OR v_uu IS DISTINCT FROM 'U:' || v_u::text",
             'tokens divergentes: ausente=%s null=%s uuid=%s (esperado A, N, U:<uuid>)', 'v_a, v_nn, v_uu')
    b += iff("('{}'::jsonb ->> 'edition_context_profile_id') IS NOT NULL\n"
             "           OR (jsonb_build_object('edition_context_profile_id', NULL) ->> 'edition_context_profile_id') IS NOT NULL",
             '->> não colapsa A e N em SQL NULL')
    b += iff(f"{TOK}('{{}}'::jsonb, 'edition_context_profile_id') IS NULL OR {TOK}(jsonb_build_object('edition_context_profile_id', NULL), 'edition_context_profile_id') IS NULL",
             'token nulo para entrada A ou N (função deixou de ser total)')
    return b


def s2():
    b = sql("SELECT p.provolatile::text, p.proparallel::text, p.proisstrict, p.proconfig::text[],\n"
            "       md5(replace(p.prosrc, chr(13) || chr(10), chr(10)))\n"
            "  INTO STRICT v_c1, v_c2, v_b, v_cfg, v_txt\n"
            "  FROM pg_proc p WHERE p.oid = to_regprocedure('internal.axis_identity_token(jsonb,text)');")
    b += iff("v_c1 IS DISTINCT FROM 'i' OR v_c2 IS DISTINCT FROM 's' OR v_b IS DISTINCT FROM false\n"
             "           OR v_cfg IS DISTINCT FROM ARRAY['search_path=\"\"'] OR v_txt IS DISTINCT FROM '18682dce935281b0a4437628a6e8309a'",
             'axis_identity_token divergente: vol=%s parallel=%s strict=%s config=%s md5=%s', 'v_c1, v_c2, v_b, v_cfg, v_txt')
    return b


def s2bis():
    b = sql("v_txt := obj_description(to_regprocedure('internal.axis_identity_token(jsonb,text)'), 'pg_proc');")
    b += iff("v_txt IS NULL OR strpos(v_txt, 'REINDEX') = 0 OR strpos(v_txt, 'NAO adicionar STRICT') = 0",
             "COMMENT sem 'REINDEX' e/ou sem a proibição de STRICT: %s", 'v_txt')
    return b


def s3():
    def san(e):
        return f"regexp_replace(regexp_replace(lower({e}), '[[:space:]()]|::text', '', 'g'), 'internal[.]', '', 'g')"
    b = sql("SELECT i.indisunique AND i.indisvalid AND i.indisready AND i.indnkeyatts = 5\n"
            "       AND (SELECT array_agg(a.attname::text ORDER BY k.ord)\n"
            "              FROM unnest(i.indkey::int2[]) WITH ORDINALITY AS k(attnum, ord)\n"
            "              JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.attnum\n"
            "             WHERE k.attnum <> 0) = ARRAY['job_id', 'card_id'],\n"
            f"       ARRAY[{san('pg_get_indexdef(i.indexrelid, 3, true)')},\n"
            f"             {san('pg_get_indexdef(i.indexrelid, 4, true)')},\n"
            f"             {san('pg_get_indexdef(i.indexrelid, 5, true)')},\n"
            f"             {san('pg_get_expr(i.indpred, i.indrelid)')}]\n"
            "  INTO STRICT v_b, v_arr\n"
            "  FROM pg_index i\n"
            " WHERE i.indexrelid = to_regclass('public.uq_cvir_row_identity')\n"
            "   AND i.indrelid = to_regclass('public.catalog_variant_import_row');")
    b += iff("NOT v_b OR v_arr IS DISTINCT FROM ARRAY['normalized_data->>''variant_type_id''',\n"
             "                                              'axis_identity_tokennormalized_data,''printing_profile_id''',\n"
             "                                              'axis_identity_tokennormalized_data,''edition_context_profile_id''',\n"
             "                                              'normalized_data->>''variant_type_id''isnotnull']",
             'uq_cvir_row_identity divergente: estrutura=%s expressões=%s', 'v_b, v_arr')
    b += sql("SELECT count(*) INTO v_n FROM unnest(ARRAY['uq_cvir_job_card_type_no_printing', 'uq_cvir_job_card_type_printing',\n"
             "                                        'uq_catalog_variant_import_row_job_card_variant_type']) AS x(n)\n"
             " WHERE to_regclass('public.' || x.n) IS NOT NULL;\n"
             "SELECT array_agg(c.relname::text ORDER BY c.relname::text) INTO v_arr\n"
             "  FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid\n"
             " WHERE i.indrelid = to_regclass('public.catalog_variant_import_row') AND i.indisunique;")
    b += iff("v_n <> 0 OR v_arr IS DISTINCT FROM ARRAY['catalog_variant_import_row_pkey', 'uq_cvir_row_identity']",
             'nomes antigos presentes=%s ou UNIQUE da tabela=%s (esperado {pkey, uq_cvir_row_identity})', 'v_n, v_arr')
    return b


def pair_count(expect, label):
    return (sql(f"SELECT count(*), count(DISTINCT {TOK}(normalized_data, 'edition_context_profile_id')),\n"
                f"       count(DISTINCT {TOK}(normalized_data, 'printing_profile_id'))\n"
                f"  INTO v_n, v_m, v_k FROM {ROW} WHERE job_id = v_job1;")
            + iff(f'NOT ({expect})', f'{label}: linhas=%s tokens_ec=%s tokens_pp=%s', 'v_n, v_m, v_k'))


def s4():
    b = PICK + job('v_job1', 'STAGED', '1')
    b += row('v_r1', 'v_job1', nd(vt='v_vt', pp='NULL', ec='NULL'), 'NEEDS_REVIEW')
    b += row('v_r2', 'v_job1', nd(vt='v_vt', pp='NULL', ec='v_ec'), 'NEEDS_REVIEW')
    b += pair_count('v_n = 2 AND v_m = 2 AND v_k = 1', 'coexistência N × U no eixo EC')
    b += sql(f"SELECT count(DISTINCT (job_id, card_id, normalized_data ->> 'variant_type_id', {TOK}(normalized_data, 'printing_profile_id'))),\n"
             f"       count(DISTINCT (job_id, card_id, normalized_data ->> 'variant_type_id', {TOK}(normalized_data, 'printing_profile_id'),\n"
             f"                       {TOK}(normalized_data, 'edition_context_profile_id')))\n"
             f"  INTO v_n, v_m FROM {ROW} WHERE job_id = v_job1;")
    b += iff('v_n <> 1 OR v_m <> 2', 'contraprova: chave de 3 componentes=%s (esperado 1, colidiriam) · chave de 5=%s (esperado 2)', 'v_n, v_m')
    b += sql(f"SELECT array_agg({TOK}(normalized_data, 'edition_context_profile_id') ORDER BY 1) INTO v_arr FROM {ROW} WHERE job_id = v_job1;")
    b += iff("v_arr IS DISTINCT FROM ARRAY['N', 'U:' || v_ec::text]", "tokens EC divergentes: %s", 'v_arr')
    return b


def s5():
    b = PICK + job('v_job1', 'STAGED', '1')
    b += row('v_r1', 'v_job1', nd(vt='v_vt', pp='NULL', ec='NULL'), 'NEEDS_REVIEW')
    b += neg(row_stmt('v_job1', nd(vt='v_vt', pp='NULL', ec='NULL'), 'NEEDS_REVIEW', into='v_r2'), UQR,
             'duplicata real nos 5 componentes')
    b += pair_count('v_n = 1', 'depois do negativo')
    return b


def s6():
    b = PICK + job('v_job1', 'STAGED', '1')
    b += row('v_r1', 'v_job1', nd(vt='v_vt', pp='NULL'), 'NEEDS_REVIEW')
    b += row('v_r2', 'v_job1', nd(vt='v_vt', pp='NULL', ec='NULL'), 'NEEDS_REVIEW')
    b += pair_count('v_n = 2 AND v_m = 2 AND v_k = 1', "coexistência A × N no eixo EC")
    b += sql(f"SELECT array_agg({TOK}(normalized_data, 'edition_context_profile_id') ORDER BY 1) INTO v_arr FROM {ROW} WHERE job_id = v_job1;")
    b += iff("v_arr IS DISTINCT FROM ARRAY['A', 'N']", 'tokens EC divergentes: %s', 'v_arr')
    return b


def s7():
    b = PICK + job('v_job1', 'STAGED', '1')
    b += row('v_r1', 'v_job1', nd(vt='v_vt', pp='NULL', ec='NULL'), 'NEEDS_REVIEW')
    b += row('v_r2', 'v_job1', nd(vt='v_vt', pp='v_pp', ec='NULL'), 'NEEDS_REVIEW')
    b += pair_count('v_n = 2 AND v_m = 1 AND v_k = 2', "coexistência N × U no eixo Printing")
    b += sql(f"SELECT array_agg({TOK}(normalized_data, 'printing_profile_id') ORDER BY 1) INTO v_arr FROM {ROW} WHERE job_id = v_job1;")
    b += iff("v_arr IS DISTINCT FROM ARRAY['N', 'U:' || v_pp::text]", 'tokens Printing divergentes: %s', 'v_arr')
    return b


def s8():
    b = PICK + job('v_job1', 'STAGED', '1')
    for key, pfx in [('edition_context_profile_id', 'CVIR_SHAPE_INVALID_EDITION_CONTEXT:'), ('printing_profile_id', 'CVIR_SHAPE_INVALID_PRINTING:')]:
        for label, val in [('número', '1'), ('array', "jsonb_build_array('x')"), ('objeto', "jsonb_build_object('x', 1)")]:
            b += neg(row_stmt('v_job1', f"jsonb_build_object('{key}', {val})", 'NEEDS_REVIEW'), ('P0001', pfx), f'{key} {label}')
    b += sql(f"SELECT count(*) INTO v_n FROM {ROW} WHERE job_id = v_job1;")
    b += iff('v_n <> 0', 'depois dos negativos: %s row(s) no job de fixture (esperado 0)', 'v_n')
    return b


def s9():
    b = PICK + job('v_job1', 'STAGED', '1')
    b += neg(row_stmt('v_job1', "jsonb_build_object('edition_context_profile_id', 'banana')", 'NEEDS_REVIEW'),
             ('P0001', 'CVIR_SHAPE_INVALID_EDITION_CONTEXT:'), "edition_context_profile_id 'banana'", 'nao e UUID valido')
    b += neg(row_stmt('v_job1', "jsonb_build_object('printing_profile_id', 'banana')", 'NEEDS_REVIEW'),
             ('P0001', 'CVIR_SHAPE_INVALID_PRINTING:'), "printing_profile_id 'banana'", 'nao e UUID valido')
    b += sql(f"SELECT count(*) INTO v_n FROM {ROW} WHERE job_id = v_job1;")
    b += iff('v_n <> 0', 'depois dos negativos: %s row(s) no job de fixture (esperado 0)', 'v_n')
    return b


def s10():
    b = PICK + job('v_job1', 'STAGED', '1') + job('v_job2', 'COMPLETED', '2')
    for j, lbl in [('v_job1', 'STAGED'), ('v_job2', 'COMPLETED')]:
        b += neg(row_stmt(j, nd(pp='NULL', ec='NULL'), 'VALID'), ('P0001', 'CVIR_VALID_REQUIRES_VARIANT_TYPE:'),
                 f'(a) VALID sem variant_type_id em job {lbl}')
    b += neg(row_stmt('v_job1', nd(vt='v_vt', ec='NULL'), 'VALID'), ('P0001', 'CVIR_VALID_REQUIRES_PRINTING_KEY:'),
             '(b) VALID sem a chave printing_profile_id em job STAGED (operacional)')
    b += neg(row_stmt('v_job2', nd(vt='v_vt', ec='NULL'), 'VALID'), ('P0001', 'CVIR_VALID_REQUIRES_PRINTING_KEY:'),
             '(c) VALID sem a chave printing_profile_id em job COMPLETED (terminal)')
    b += neg(row_stmt('v_job1', nd(vt='v_vt', pp='NULL'), 'VALID'), ('P0001', 'CVIR_OPERATIONAL_VALID_REQUIRES_EDITION_CONTEXT_KEY:'),
             '(d) VALID+PENDING sem a chave edition_context_profile_id em job STAGED')
    b += row('v_r1', 'v_job2', nd(vt='v_vt', pp='NULL'), 'VALID')
    b += sql(f"SELECT count(*) INTO v_n FROM {ROW} WHERE job_id = v_job1;\n"
             f"SELECT count(*) INTO v_m FROM {ROW} WHERE job_id = v_job2 AND id = v_r1 AND validation_status = 'VALID'\n"
             f"   AND persistence_status = 'PENDING' AND NOT jsonb_exists(normalized_data, 'edition_context_profile_id');")
    b += iff('v_n <> 0 OR v_m <> 1', '(d) contraprova: rows no STAGED=%s (esperado 0) · mesmo payload aceito no COMPLETED=%s (esperado 1)', 'v_n, v_m')
    return b


def s11():
    b = PICK + job('v_job1', 'STAGED', '1')
    b += row('v_r1', 'v_job1', "'{}'::jsonb", 'NEEDS_REVIEW')
    b += row('v_r2', 'v_job1', nd(vt='v_vt'), 'NEEDS_REVIEW')
    b += sql(f"SELECT count(*) INTO v_n FROM {ROW}\n"
             f" WHERE job_id = v_job1 AND validation_status = 'NEEDS_REVIEW' AND persistence_status = 'PENDING'\n"
             f"   AND NOT jsonb_exists(normalized_data, 'printing_profile_id')\n"
             f"   AND NOT jsonb_exists(normalized_data, 'edition_context_profile_id');")
    b += iff('v_n <> 2', 'NEEDS_REVIEW sem as duas chaves em job operacional: %s row(s) (esperado 2)', 'v_n')
    return b


HEAD = header(['2830H · ENVELOPE E09 — SEÇÃO S (STAGING) · lote L7, 12 casos: S1–S11 com S2-BIS'], [
    'Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO, NÃO COMPILADO no',
    '                PostgreSQL (BATCH12 — INTEGRATED COMPLETION, baseline 945caa32).',
    '                Execução exige E00 + E09P gate_pass = true e mandato próprio.',
    'Contrato ...... 2830 v7.0 · blob b4647dcb… (l. 571–622). Contratos de erro =',
    '                LIVE (internal.guard_cvir_normalized_shape, 2214 v3.1, pinado).',
    'Autoridades ... 2210 (axis_identity_token, uq_cvir_row_identity), 2214 (guard',
    '                G1/G2/G3), 2136/2138 (job/row, CHECKs, fingerprint).',
    'Fixtures ...... Card real ORDER BY id do Game real e o seu Card Set; Variant Type',
    '                e profiles ORDER BY id. Jobs sentinela TCGDEX com',
    '                external_set_id = marcador || _J<n> (P5). Rows só em job de',
    '                fixture. Nenhum UPDATE/DELETE.',
    'S10 ........... 4 sub-asserções (a)–(d) do contrato v7.0, com (a) nos dois',
    '                regimes de job e contraprova de (d) no COMPLETED.',
    'Escrita (R4) .. job 1–2 por caso · row: S4 2, S5 1 + 1 recusada, S6 2, S7 2,',
    '                S8 6 recusadas, S9 2 recusadas, S10 1 + 5 recusadas, S11 2.',
    'P8 ............ SET LOCAL lock_timeout = \'5s\' + asserção (DP-4 = A).',
])

SPEC = dict(tag='h2830_e09', env='E09_SECAO_S_STAGING', header=HEAD,
            decl=jr.PICK_DECL + [('v_job1', 'uuid', None), ('v_job2', 'uuid', None), ('v_r1', 'uuid', None), ('v_r2', 'uuid', None),
                                 ('v_u', 'uuid', None), ('v_a', 'text', None), ('v_nn', 'text', None), ('v_uu', 'text', None),
                                 ('v_c1', 'text', None), ('v_c2', 'text', None), ('v_b', 'boolean', None), ('v_cfg', 'text[]', None),
                                 ('v_arr', 'text[]', None), ('v_k', 'bigint', None)],
            reset=['v_card', 'v_cs', 'v_vt', 'v_pp', 'v_ec', 'v_job1', 'v_job2', 'v_r1', 'v_r2', 'v_u', 'v_a', 'v_nn', 'v_uu',
                   'v_c1', 'v_c2', 'v_b', 'v_cfg', 'v_arr', 'v_k'],
            cases=[('S1', "S1 — axis_identity_token: ausente 'A'; JSON null 'N'; uuid 'U:<uuid>'; ->> SQL NULL em A e N (RC)", s1()),
                   ('S2', "S2 — axis_identity_token IMMUTABLE + PARALLEL SAFE + search_path='' e NÃO STRICT (RO)", s2()),
                   ('S2-BIS', "S2-BIS — COMMENT contém 'REINDEX' e a proibição de STRICT (RO)", s2bis()),
                   ('S3', 'S3 — uq_cvir_row_identity UNIQUE com 5 expressões; nomes antigos ausentes; UNIQUE = {pkey, uq_cvir_row_identity} (RO)', s3()),
                   ('S4', "S4 — mesmo job/card/vt/printing coexistem diferindo só em EC ('N' × 'U'); contraprova de 3 componentes (FX)", s4()),
                   ('S5', 'S5 — duplicata real nos 5 componentes ⇒ 23505 uq_cvir_row_identity (FX)', s5()),
                   ('S6', "S6 — 'A' × 'N' coexistem (FX)", s6()),
                   ('S7', "S7 — 'N' × 'U' coexistem no eixo printing_profile_id (FX)", s7()),
                   ('S8', 'S8 — tipo inválido no eixo ⇒ CVIR_SHAPE_INVALID_EDITION_CONTEXT / _PRINTING (FX)', s8()),
                   ('S9', "S9 — string não-UUID ('banana') ⇒ CVIR_SHAPE_INVALID_* 'nao e UUID valido' (FX)", s9()),
                   ('S10', 'S10 — VALID exige as chaves no seu escopo: (a) vt · (b)/(c) printing, não job-aware · (d) EC job-aware (FX)', s10()),
                   ('S11', 'S11 — row NEEDS_REVIEW em job operacional sem as duas chaves: permitido (FX)', s11())])


def e09():
    return envelope(SPEC)


PHEAD = header(['2830H · E09P — PRECHECK DO LOTE L7 (Seção S)'], [
    'Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO. SELECT único.',
    'Cobre ......... P7X (job/row/card_variant/game), bloco JOB/ROW (tokens do guard,',
    '                CHECKs, índices, fixture, jobs em voo = 0), XBASELINE, marcador.',
])


def e09p():
    ctes = [pre.GS, pre.P7X, pre.XBASE, jr.JR_CTES]
    gates = pre.GS_GATE + '\n' + pre.P7X_GATES + '\n' + pre.XBASE_GATE + '\n' + pre.MK_GATE + '\n' + jr.JR_GATES
    det = pre.P7X_DETAIL + '\n' + pre.XBASE_DETAIL + '\n' + jr.JR_DETAIL + '\n' + pre.SESSION_DETAIL
    return pre.precheck(PHEAD, ctes, gates, det, 'e09p_precheck')
