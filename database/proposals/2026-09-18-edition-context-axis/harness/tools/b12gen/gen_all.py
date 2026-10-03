# Gerador único do pacote integrado do Batch 12 (L5–L13 + E98 + P9A).
# Uso: python3 gen_all.py <dir_harness>  — escreve os .sql e o manifesto JSON.
# Determinístico: a mesma entrada produz os mesmos bytes (verificado pelo
# static_check, que regenera em memória e compara md5).
import sys, json, hashlib, re, pathlib
import lib, l5, l6, l7, l8, l9, l10, l11, l12, l13, e98

ENVELOPES = [
    ('E07', '2830H_E07_game_sentinel_2_6_3_3.sql', l5.e07, 'L5'),
    ('E08', '2830H_E08_section4_card_variant_identity.sql', l6.e08, 'L6'),
    ('E09', '2830H_E09_section_s_staging.sql', l7.e09, 'L7'),
    ('E10', '2830H_E10_section_r_routing_2211.sql', l8.e10, 'L8'),
    ('E11', '2830H_E11_section_k_confirm_static.sql', l9.e11, 'L9'),
    ('E12', '2830H_E12_section_b_backfill_semantic.sql', l10.e12, 'L10'),
    ('E13', '2830H_E13_section_m_state_machine.sql', l11.e13, 'L11'),
    ('E14', '2830H_E14_section_g_guard_2214.sql', l12.e14, 'L12'),
    ('E15', '2830H_E15_section5_legacy_hold.sql', l13.e15, 'L13'),
]
PRECHECKS = [
    ('E07P', '2830H_E07P_precheck_game_sentinel.sql', l5.e07p, 'L5'),
    ('E08P', '2830H_E08P_precheck_section4.sql', l6.e08p, 'L6'),
    ('E09P', '2830H_E09P_precheck_section_s.sql', l7.e09p, 'L7'),
    ('E10P', '2830H_E10P_precheck_section_r.sql', l8.e10p, 'L8'),
    ('E12P', '2830H_E12P_precheck_section_b.sql', l10.e12p, 'L10'),
    ('E13P', '2830H_E13P_precheck_section_m.sql', l11.e13p, 'L11'),
    ('E14P', '2830H_E14P_precheck_section_g.sql', l12.e14p, 'L12'),
    ('E15P', '2830H_E15P_measure_section5.sql', l13.e15p, 'L13'),
]
OTHER = [
    ('E98', '2830H_E98_postcheck_extended_residue.sql', e98.e98, '*'),
]

GAME = "(SELECT id FROM public.game WHERE code = 'POKEMON')"
SRC = "(SELECT id FROM public.asset_source WHERE code = 'TCGDEX')"


def p9a():
    head = lib.header(['2830H · P9A — FORMA DO PLANO DAS SEÇÕES PESADAS (B, M, 5.x) · EXPLAIN (COSTS OFF), sem ANALYZE'], [
        'Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO. 4 statements independentes.',
        'Origem ........ P9(a)/AD-2: seções pesadas B, M e 5.2/5.3/5.7. Cada consulta é o',
        '                texto GERADO pela mesma função que produz o envelope (VREC, SMREC,',
        '                DERIV-5X, DERIV-D1X); as variáveis PL/pgSQL são trocadas por',
        '                subconsultas por code. DERIV-D1X (l13.d1x_select) é a base dos',
        '                casos 5.3/5.7 do E15. EXPLAIN não executa: nenhum gate, nenhuma',
        '                prova de resíduo.',
        'Registro ...... saída integral + md5 de cada plano; nós de acesso por relação.',
        'Limite ........ não mede tempo; P9(b)′ já está CLOSED pela v7.2; A2′ aguarda P9(a).',
    ])
    vrec = l10.vrec(GAME, SRC)
    smrec = l11.smrec()
    deriv = l13.deriv_select()
    d1x = l13.d1x_select()
    out = [head,
           '-- P9A-B  (E12 · VREC)\nEXPLAIN (COSTS OFF)\n' + vrec + ';\n',
           '-- P9A-M  (E13 · SMREC)\nEXPLAIN (COSTS OFF)\n' + smrec + ';\n',
           '-- P9A-5X (E15/E15P · DERIV-5X)\nEXPLAIN (COSTS OFF)\n' + deriv + ';\n',
           '-- P9A-D1X (E15 · DERIV-D1X · casos 5.3/5.7)\nEXPLAIN (COSTS OFF)\n' + d1x + ';\n']
    return '\n'.join(out)


def p9b():
    head = lib.header(['2830H · P9B — TEMPO REAL DAS SEÇÕES PESADAS · EXPLAIN (ANALYZE, BUFFERS) · SOMENTE AMBIENTE ISOLADO'], [
        'Status ........ PREPARADO — NÃO EXECUTADO. PROIBIDO no LIVE sem autorização',
        '                específica (ANALYZE executa a consulta). Clone isolado com',
        '                paridade de volume provada (P14a).',
        'Cenários ...... M1 VREC (E12): 2211 sobre op ∪ histórico com chave.',
        '                M2 V1-complemento (E12): 2211 sobre histórico SEM chave (pior caso',
        '                de V1 quando não há ocorrência no VREC).',
        '                M3 SMREC (E13): varredura agregada da staging.',
        '                M4 DERIV-5X (E15P/E15): HOLD, PRICING e C2 (2211 por variant).',
        '                M5 envelopes completos E12, E13, E15P: elapsed_ms do H283P /',
        '                tempo do statement; limite do protocolo 120 s por envelope.',
        'Critério ...... cada Mn < 60 s (metade do orçamento, margem para 2x); acima',
        '                disso a seção é dividida antes do LIVE (AD-2).',
    ])
    comp = f"""SELECT count(*) FROM (
    SELECT 1
      FROM public.catalog_variant_import_row r
      JOIN public.catalog_variant_import_job j ON j.id = r.job_id
      JOIN public.card c ON c.id = r.card_id
      LEFT JOIN LATERAL internal.resolve_variant_mapping_scope(c.card_set_id, {SRC}) sc ON true
     CROSS JOIN LATERAL internal.resolve_variant_row_axes(r.raw_data, {GAME}, {SRC}, sc.external_set_id) ax
     WHERE NOT (j.status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING') AND r.persistence_status = 'PENDING')
       AND NOT jsonb_exists(r.normalized_data, 'edition_context_profile_id')
       AND ax.edition_context_state = 'RESOLVED_WITH_EC_PROFILE') z"""
    out = [head,
           '-- M1  VREC (E12)\nEXPLAIN (ANALYZE, BUFFERS)\n' + l10.vrec(GAME, SRC) + ';\n',
           '-- M2  V1-complemento (E12, sem LIMIT: pior caso)\nEXPLAIN (ANALYZE, BUFFERS)\n' + comp + ';\n',
           '-- M3  SMREC (E13)\nEXPLAIN (ANALYZE, BUFFERS)\n' + l11.smrec() + ';\n',
           '-- M4  DERIV-5X (E15P/E15)\nEXPLAIN (ANALYZE, BUFFERS)\n' + l13.deriv_select() + ';\n']
    return '\n'.join(out)


def build():
    files = {}
    meta = []
    for eid, name, fn, lot in ENVELOPES:
        text, ctx = fn()
        cases = re.search(r"c_expected CONSTANT text\[\] := ARRAY\[(.*?)\];", text).group(1)
        cases = [c.strip("'") for c in cases.split(',')]
        files[name] = text
        meta.append(dict(id=eid, lot=lot, file=name, kind='envelope', context_line=ctx, cases=cases, n=len(cases)))
    for eid, name, fn, lot in PRECHECKS + OTHER:
        files[name] = fn()
        meta.append(dict(id=eid, lot=lot, file=name, kind='precheck' if eid.endswith('P') else 'postcheck'))
    files['2830H_P9A_heavy_sections_explain.sql'] = p9a()
    meta.append(dict(id='P9A', lot='L10/L11/L13', file='2830H_P9A_heavy_sections_explain.sql', kind='explain'))
    files['2830H_P9B_isolated_timing.sql'] = p9b()
    meta.append(dict(id='P9B', lot='L10/L11/L13', file='2830H_P9B_isolated_timing.sql', kind='timing-isolated'))
    for name, text in files.items():
        lib.check_text(text)
    for m in meta:
        m['md5'] = hashlib.md5(files[m['file']].encode()).hexdigest()
        m['bytes'] = len(files[m['file']].encode())
    total = sum(m.get('n', 0) for m in meta)
    return files, meta, total


if __name__ == '__main__':
    out = pathlib.Path(sys.argv[1])
    files, meta, total = build()
    assert total == 75, total
    for name, text in files.items():
        (out / name).write_bytes(text.encode())
    man = dict(package='BATCH12-INTEGRATED-COMPLETION', baseline_head='945caa32', status='IMPLEMENTADO LOCALMENTE - NAO EXECUTADO',
               automatic_cases_new=total, automatic_cases_prior=60, automatic_cases_total=135, artifacts=meta)
    (out / 'B12-INTEGRATED-MANIFEST.json').write_bytes((json.dumps(man, ensure_ascii=False, indent=2) + '\n').encode())
    for m in meta:
        print(m['id'], m['file'], m.get('n', ''), m.get('context_line', ''), m['md5'])
    print('TOTAL', total)
