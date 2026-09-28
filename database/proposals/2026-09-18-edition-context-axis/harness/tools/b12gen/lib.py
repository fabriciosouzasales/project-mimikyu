# Biblioteca comum dos geradores do Batch 12 (L5–L13). Não conecta a banco.
# Um único lugar para: preâmbulo P8, PREFLIGHT, abertura/fechamento de caso,
# negativos (SQLSTATE+constraint+tabela ou P0001+prefixo), chamada da 2211 e
# terminal H283P. Todos os envelopes E07–E15 saem daqui (sem cópia manual).
import re

I8 = ' ' * 8


def ind(text, n=8):
    p = ' ' * n
    return '\n'.join((p + l) if l else '' for l in text.split('\n'))


def q(s):
    """literal SQL com aspas internas escapadas"""
    return "'" + s.replace("'", "''") + "'"


def fail(msg, args='', n=8):
    a = (', ' + args) if args else ''
    return ind(f"RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(\n    "
               f"{q('H2830_FAIL: envelope=%s caso=%s ' + msg)}, c_env, v_case{a});", n)


def iff(cond, msg, args='', n=8):
    return ' ' * n + f'IF {cond} THEN\n' + fail(msg, args, n + 4) + '\n' + ' ' * n + 'END IF;\n'


def sql(text, n=8):
    return ind(text.strip('\n'), n) + '\n'


def neg(stmt, expect, what, extra_msg_token=None):
    """bloco negativo: a instrução DEVE falhar com a identidade exata.
    expect = ('23505', constraint, tabela) | ('P0001', prefixo)"""
    s = sql("v_got := false; v_state := NULL; v_con := NULL; v_tab := NULL; v_msg := NULL;\nBEGIN")
    s += sql(stmt, 12)
    s += """        EXCEPTION WHEN OTHERS THEN
            v_got := true;
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME,
                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;
        END;
"""
    s += iff('NOT v_got', f'{what} foi ACEITO(A)')
    if expect[0] == 'P0001':
        cond = f"v_state IS NULL OR v_msg IS NULL OR v_state <> 'P0001' OR NOT starts_with(v_msg, {q(expect[1])})"
        if extra_msg_token:
            cond += f' OR strpos(v_msg, {q(extra_msg_token)}) = 0'
        s += iff(cond, f'{what}: rejeição errada sqlstate=%s msg=%s', 'v_state, v_msg')
    else:
        st, con, tab = expect
        s += iff(f"v_state IS NULL OR v_state <> '{st}' OR v_con IS DISTINCT FROM '{con}' OR v_tab IS DISTINCT FROM '{tab}'",
                 f'{what}: rejeição errada sqlstate=%s constraint=%s tabela=%s msg=%s', 'v_state, v_con, v_tab, v_msg')
    return s


CASE_CLOSE = """
        RAISE EXCEPTION USING ERRCODE = 'H283C', MESSAGE = v_case;
    EXCEPTION
        WHEN SQLSTATE 'H283C' THEN
            GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
            IF v_msg IS DISTINCT FROM v_case THEN
                RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                    'H2830_FAIL: envelope=%s caso=%s sinal de fim trocado (%s)', c_env, v_case, v_msg);
            END IF;
            v_done := v_done || v_case;
        WHEN SQLSTATE 'H283F' THEN RAISE;
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s erro inesperado sqlstate=%s msg=%s', c_env, v_case, v_state, v_msg);
    END;

"""

LT_PRE = """    -- ------------------------------------------------------------------ --
    -- P8 / DP-4 = A: lock_timeout transacional, primeira instrução executável
    -- ------------------------------------------------------------------ --
    SET LOCAL lock_timeout = '5s';
    IF current_setting('lock_timeout') IS DISTINCT FROM '5s' THEN
        RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
            'H2830_FAIL: envelope=%s caso=PREFLIGHT lock_timeout=%s (esperado 5s)', c_env, current_setting('lock_timeout'));
    END IF;
"""

PREFLIGHT = """
    -- ------------------------------------------------------------------ --
    -- PREFLIGHT (não é caso; falha = H2830_FAIL, nunca PASS)
    -- ------------------------------------------------------------------ --
    SELECT count(*) INTO v_n FROM public.game WHERE code = 'POKEMON';
    IF v_n <> 1 THEN
        RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
            'H2830_FAIL: envelope=%s caso=PREFLIGHT game code=POKEMON count=%s (esperado 1)', c_env, v_n);
    END IF;
    SELECT id INTO v_game FROM public.game WHERE code = 'POKEMON';
    SELECT count(*) INTO v_n FROM public.asset_source WHERE code = 'TCGDEX';
    IF v_n <> 1 THEN
        RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
            'H2830_FAIL: envelope=%s caso=PREFLIGHT asset_source code=TCGDEX count=%s (esperado 1)', c_env, v_n);
    END IF;
    SELECT id INTO v_src FROM public.asset_source WHERE code = 'TCGDEX';
"""

BASE_DECL = [('v_marker', 'text', "'H2830_' || upper(replace(gen_random_uuid()::text, '-', ''))"),
             ('v_t0', 'timestamptz', 'clock_timestamp()'),
             ('v_done', 'text[]', 'ARRAY[]::text[]'),
             ('v_case', 'text', None), ('v_game', 'uuid', None), ('v_src', 'uuid', None),
             ('v_n', 'bigint', None), ('v_m', 'bigint', None), ('v_got', 'boolean', None),
             ('v_state', 'text', None), ('v_con', 'text', None), ('v_tab', 'text', None),
             ('v_msg', 'text', None), ('v_txt', 'text', None)]


def envelope(spec):
    """spec: tag, env, header(str), decl(list), reset(list), cases[(cid,title,body)],
    gate_extra(str|''), term_fields[(name, expr)], preflight_extra(str)"""
    cases = [c[0] for c in spec['cases']]
    out = [spec['header'].rstrip('\n') + '\n']
    out.append(f"DO ${spec['tag']}$\nDECLARE\n")
    out.append(f"    c_env      CONSTANT text   := '{spec['env']}';\n")
    out.append("    c_expected CONSTANT text[] := ARRAY[" + ','.join(q(c) for c in cases) + "];\n")
    decl = BASE_DECL + spec.get('decl', [])
    seen = set()
    for name, typ, init in decl:
        assert name not in seen, name
        seen.add(name)
        out.append(f"    {name:<10} {typ}" + (f" := {init};\n" if init else ';\n'))
    out.append('BEGIN\n')
    out.append(LT_PRE)
    out.append(PREFLIGHT)
    if spec.get('preflight_extra'):
        out.append(spec['preflight_extra'].rstrip('\n') + '\n')
    out.append('\n')
    for cid, title, body in spec['cases']:
        out.append('    -- ================================================================== --\n')
        for tl in title.split('\n'):
            out.append(f'    -- {tl}\n')
        out.append('    -- ================================================================== --\n')
        out.append(f"    v_case := '{cid}';\n")
        for v in spec.get('reset', []):
            out.append(f'    {v} := NULL;\n')
        out.append('    BEGIN\n')
        out.append(body.rstrip('\n') + '\n')
        out.append(CASE_CLOSE)
    out.append("""    -- ------------------------------------------------------------------ --
    -- GATE DO ENVELOPE: exatamente os casos esperados, na ordem, cada um uma vez
    -- ------------------------------------------------------------------ --
    IF v_done IS DISTINCT FROM c_expected THEN
        RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
            'H2830_FAIL: envelope=%s caso=GATE concluídos=%s esperados=%s', c_env, v_done, c_expected);
    END IF;
""")
    if spec.get('gate_extra'):
        out.append(spec['gate_extra'].rstrip('\n') + '\n')
    tf = spec.get('term_fields', [])
    fmt = 'H2830_ROLLBACK_PASS: envelope=%s pass=%s/%s casos=%s marker=%s elapsed_ms=%s' + ''.join(f' {n}=%s' for n, _ in tf)
    extra = ''.join(f', {e}' for _, e in tf)
    out.append("""
    -- ------------------------------------------------------------------ --
    -- TERMINAL: sucesso também é exceção — desfaz tudo (P2)
    -- ------------------------------------------------------------------ --
    RAISE EXCEPTION USING ERRCODE = 'H283P', MESSAGE = format(
        """ + q(fmt) + """,
        c_env, cardinality(v_done), cardinality(c_expected), array_to_string(v_done, ','),
        v_marker, round(extract(epoch FROM clock_timestamp() - v_t0) * 1000)""" + extra + """);
END
$""" + spec['tag'] + """$;
""")
    text = ''.join(out)
    lines = text.split('\n')
    do_line = next(i for i, l in enumerate(lines, 1) if l.startswith('DO $'))
    p_line = next(i for i, l in enumerate(lines, 1) if "ERRCODE = 'H283P'" in l)
    return text, p_line - do_line + 1


# ---------------------------------------------------------------------------
# chamada da 2211 (INTO STRICT: 0 ou >1 linha ⇒ erro ⇒ H283F), 10 colunas
# ---------------------------------------------------------------------------
RC_VARS = [('v_ps', 'text', None), ('v_pp', 'uuid', None), ('v_pt', 'uuid[]', None), ('v_ecs', 'text', None),
           ('v_ecp', 'uuid', None), ('v_ect', 'uuid[]', None), ('v_rty', 'text', None), ('v_rfo', 'text', None),
           ('v_rst', 'text', None), ('v_rsp', 'text[]', None)]


def rc(game, setexpr):
    return sql("v_ps := NULL; v_pp := NULL; v_pt := NULL; v_ecs := NULL; v_ecp := NULL; v_ect := NULL;\n"
               "v_rty := NULL; v_rfo := NULL; v_rst := NULL; v_rsp := NULL;\n"
               "SELECT r.printing_state, r.printing_profile_id, r.printing_trait_ids,\n"
               "       r.edition_context_state, r.edition_context_profile_id, r.edition_context_trait_ids,\n"
               "       r.residual_type, r.residual_foil, r.residual_subtype, r.residual_stamp\n"
               "  INTO STRICT v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp\n"
               f"  FROM internal.resolve_variant_row_axes(v_raw, {game}, v_src, {setexpr}) AS r;")


def expect(label, ps, pp, pt, ecs, ecp, ect, rst, rsp):
    """asserção integral das 10 colunas; 'NULL' ⇒ IS NOT NULL"""
    d = lambda v, e: f'{v} IS NOT NULL' if e == 'NULL' else f'{v} IS DISTINCT FROM {e}'
    cond = (f"v_ps IS DISTINCT FROM {ps} OR {d('v_pp', pp)} OR v_pt IS DISTINCT FROM {pt}\n"
            f"           OR v_ecs IS DISTINCT FROM {ecs} OR {d('v_ecp', ecp)} OR v_ect IS DISTINCT FROM {ect}\n"
            f"           OR v_rty IS DISTINCT FROM 'H2830 TIPO' OR v_rfo IS NOT NULL\n"
            f"           OR {d('v_rst', rst)} OR v_rsp IS DISTINCT FROM {rsp}")
    return iff(cond, f'2211 ({label}) divergente: printing=%s pp=%s pt=%s ec=%s ecp=%s ect=%s type=%s foil=%s subtype=%s stamp=%s',
               'v_ps, v_pp, v_pt, v_ecs, v_ecp, v_ect, v_rty, v_rfo, v_rst, v_rsp')


EMPTY_U = "'{}'::uuid[]"
EMPTY_T = "'{}'::text[]"


def header(title_lines, body_lines):
    bar = '-- ' + '=' * 76
    out = [bar]
    for t in title_lines:
        out.append('-- ' + t)
    out.append(bar)
    for b in body_lines:
        out.append(('-- ' + b) if b else '--')
    out.append(bar)
    return '\n'.join(out) + '\n'


def check_text(text):
    """higiene: LF, sem tab, sem espaço final, termina em LF, aspas pares"""
    assert '\r' not in text and '\t' not in text, 'CR/TAB'
    assert not re.search(r' +\n', text), 'espaço final'
    assert text.endswith('\n')
    return text
