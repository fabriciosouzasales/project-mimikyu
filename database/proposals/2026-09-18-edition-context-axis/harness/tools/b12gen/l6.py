# L6 — Seção 4, identidade card_variant (4.1–4.8). E08 + E08P.
from lib import *
import pre

CV = 'public.card_variant'
UQ = ('23505', 'uq_card_variant_identity', 'card_variant')


def pick(n_ec=1):
    """Card real + Variant Type do mesmo Game SEM nenhuma Variant no par
    (ORDER BY id, determinístico); variant_order sintético fora da faixa da
    Card; profiles de Printing/EC ativos do MESMO Game (triggers 161/2170/2224)."""
    s = sql("SELECT c.id, t.id INTO v_card, v_vt\n"
            "  FROM public.card c\n"
            "  JOIN public.card_set cs ON cs.id = c.card_set_id\n"
            "  JOIN public.expansion e ON e.id = cs.expansion_id\n"
            "  JOIN public.card_variant_type t ON t.game_id = e.game_id\n"
            " WHERE e.game_id = v_game\n"
            f"   AND NOT EXISTS (SELECT 1 FROM {CV} cv WHERE cv.card_id = c.id AND cv.variant_type_id = t.id)\n"
            " ORDER BY c.id, t.id\n"
            " LIMIT 1;")
    s += iff('v_card IS NULL OR v_vt IS NULL', 'sem par (Card, Variant Type) livre no Game real (STOP; ver E08P)')
    s += sql(f"SELECT COALESCE(max(variant_order), 0) INTO v_ord FROM {CV} WHERE card_id = v_card;\n"
             "SELECT p.id INTO v_pp FROM public.card_printing_profile p\n"
             " WHERE p.game_id = v_game AND p.is_active ORDER BY p.id LIMIT 1;\n"
             "SELECT array_agg(x.id ORDER BY x.id) INTO v_eca\n"
             "  FROM (SELECT p.id FROM public.card_edition_context_profile p\n"
             f"         WHERE p.game_id = v_game AND p.is_active ORDER BY p.id LIMIT {n_ec}) x;")
    s += iff(f'v_pp IS NULL OR cardinality(v_eca) IS DISTINCT FROM {n_ec}', 'profiles de Printing/EC do Game real ausentes (STOP; ver E08P)')
    return s


def ins(k, pp, ec, into='v_cv1'):
    return sql(f"INSERT INTO {CV} (card_id, variant_type_id, variant_order, printing_profile_id, edition_context_profile_id)\n"
               f"VALUES (v_card, v_vt, v_ord + {1000 + k}, {pp}, {ec})\n"
               f"RETURNING id INTO {into};")


def dup(pp, ec, label):
    b = pick()
    b += ins(1, pp, ec)
    b += iff('v_cv1 IS NULL', 'primeira Variant de fixture não criada')
    b += neg(f"INSERT INTO {CV} (card_id, variant_type_id, variant_order, printing_profile_id, edition_context_profile_id)\n"
             f"VALUES (v_card, v_vt, v_ord + 1002, {pp}, {ec})\nRETURNING id INTO v_cv2;", UQ, f'duplicata {label}')
    b += sql(f"SELECT count(*) INTO v_n FROM {CV}\n WHERE card_id = v_card AND variant_type_id = v_vt;")
    b += iff('v_n <> 1 OR v_cv2 IS NOT NULL', 'depois do negativo: %s Variant(s) no par de fixture (esperado 1)', 'v_n')
    return b


def c41():
    b = sql("SELECT count(*) INTO v_n FROM pg_constraint c\n"
            " WHERE c.conrelid = to_regclass('public.card_variant') AND c.conname = 'uq_card_variant_identity'\n"
            "   AND c.contype = 'u' AND c.convalidated\n"
            "   AND c.conindid = to_regclass('public.uq_card_variant_identity');")
    b += iff('v_n <> 1', "constraint 'u' validada uq_card_variant_identity ausente ou não ligada ao índice (%s)", 'v_n')
    b += sql("SELECT i.indisunique AND i.indisvalid AND i.indisready AND i.indnullsnotdistinct AND i.indpred IS NULL\n"
             "       AND i.indexprs IS NULL AND i.indnkeyatts = 4,\n"
             "       (SELECT array_agg(a.attname::text ORDER BY k.ord)\n"
             "          FROM unnest(i.indkey::int2[]) WITH ORDINALITY AS k(attnum, ord)\n"
             "          JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.attnum)\n"
             "  INTO STRICT v_b, v_arr\n"
             "  FROM pg_index i\n"
             " WHERE i.indexrelid = to_regclass('public.uq_card_variant_identity')\n"
             "   AND i.indrelid = to_regclass('public.card_variant');")
    b += iff("NOT v_b OR v_arr IS DISTINCT FROM ARRAY['card_id','variant_type_id','printing_profile_id','edition_context_profile_id']",
             'índice uq_card_variant_identity divergente: flags=%s colunas=%s (esperado UNIQUE NULLS NOT DISTINCT total nas 4 colunas)', 'v_b, v_arr')
    return b


def c46():
    b = pick(2)
    b += ins(1, 'NULL', 'NULL', 'v_cv1')
    b += ins(2, 'NULL', 'v_eca[1]', 'v_cv2')
    b += ins(3, 'NULL', 'v_eca[2]', 'v_cv3')
    b += ins(4, 'v_pp', 'NULL', 'v_cv4')
    b += sql(f"SELECT count(*), count(DISTINCT edition_context_profile_id), count(*) FILTER (WHERE edition_context_profile_id IS NULL)\n"
             f"  INTO v_n, v_m, v_k\n  FROM {CV} WHERE card_id = v_card AND variant_type_id = v_vt;")
    b += iff('v_n <> 4 OR v_m <> 2 OR v_k <> 2 OR v_cv1 IS NULL OR v_cv2 IS NULL OR v_cv3 IS NULL OR v_cv4 IS NULL',
             'coexistência divergente: linhas=%s contextos_distintos=%s sem_contexto=%s (esperado 4/2/2)', 'v_n, v_m, v_k')
    return b


def c47():
    b = sql("SELECT count(*) INTO v_n FROM pg_constraint c\n"
            " WHERE c.conrelid = to_regclass('public.card_variant') AND c.conname = 'uq_card_variant_card_order'\n"
            "   AND c.contype = 'u' AND c.convalidated\n"
            "   AND (SELECT array_agg(a.attname::text ORDER BY k.ord)\n"
            "          FROM unnest(c.conkey) WITH ORDINALITY AS k(attnum, ord)\n"
            "          JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.attnum) = ARRAY['card_id','variant_order'];")
    b += iff('v_n <> 1', "uq_card_variant_card_order não preservado como UNIQUE (card_id, variant_order) validado (%s)", 'v_n')
    return b


def c48():
    b = sql("SELECT count(*) INTO v_n FROM pg_index i\n"
            " WHERE i.indexrelid = to_regclass('public.uq_card_variant_one_default_per_card')\n"
            "   AND i.indrelid = to_regclass('public.card_variant')\n"
            "   AND i.indisunique AND i.indisvalid AND i.indisready AND i.indnkeyatts = 1\n"
            "   AND (SELECT a.attname::text FROM pg_attribute a WHERE a.attrelid = i.indrelid AND a.attnum = i.indkey[0]) = 'card_id'\n"
            "   AND regexp_replace(pg_get_expr(i.indpred, i.indrelid), '[() ]', '', 'g') = 'is_default=true';")
    b += iff('v_n <> 1', "uq_card_variant_one_default_per_card não preservado como UNIQUE (card_id) WHERE is_default = true (%s)", 'v_n')
    return b


HEAD = header(['2830H · ENVELOPE E08 — SEÇÃO 4 (IDENTIDADE card_variant) · lote L6, 8 casos: 4.1–4.8'], [
    'Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO, NÃO COMPILADO no',
    '                PostgreSQL (BATCH12 — INTEGRATED COMPLETION, baseline 945caa32).',
    '                Execução exige E00 + E08P gate_pass = true e mandato próprio.',
    'Contrato ...... 2830 v7.0 · blob b4647dcb… (l. 553–568).',
    'Autoridades ... 2209 (uq_card_variant_identity UNIQUE NULLS NOT DISTINCT),',
    '                160 (uq_card_variant_card_order, one_default), 161/2170/2224',
    '                (triggers same-Game, pinados no E08P/P7X).',
    'Fixtures ...... Card real + Variant Type do mesmo Game SEM Variant no par, por',
    '                ORDER BY c.id, t.id; variant_order = max da Card + 1001..1004;',
    '                profiles ativos do Game real por ORDER BY id; is_default = false',
    '                (default). Nenhum UPDATE/DELETE; nenhuma linha pré-existente é',
    '                alvo de escrita (FK só toma KEY SHARE nas referenciadas).',
    'Escrita (R3) .. card_variant 12 tentativas de INSERT (4.2–4.5: 1 + 1 recusada',
    '                cada; 4.6: 4). Tudo desfeito pelo término em exceção.',
    'P8 ............ SET LOCAL lock_timeout = \'5s\' + asserção (DP-4 = A).',
])

SPEC = dict(tag='h2830_e08', env='E08_SECAO4_IDENTIDADE_CARD_VARIANT', header=HEAD,
            decl=[('v_card', 'uuid', None), ('v_vt', 'uuid', None), ('v_pp', 'uuid', None), ('v_eca', 'uuid[]', None),
                  ('v_ord', 'integer', None), ('v_cv1', 'uuid', None), ('v_cv2', 'uuid', None), ('v_cv3', 'uuid', None),
                  ('v_cv4', 'uuid', None), ('v_k', 'bigint', None), ('v_b', 'boolean', None), ('v_arr', 'text[]', None)],
            reset=['v_card', 'v_vt', 'v_pp', 'v_eca', 'v_ord', 'v_cv1', 'v_cv2', 'v_cv3', 'v_cv4', 'v_k', 'v_b', 'v_arr'],
            cases=[('4.1', '4.1 — uq_card_variant_identity UNIQUE NULLS NOT DISTINCT (4 colunas), constraint u validada (RO)', c41()),
                   ('4.2', '4.2 — (card, vt, NULL, NULL) duplicado ⇒ 23505 uq_card_variant_identity (FX)', dup('NULL', 'NULL', '(card, vt, NULL, NULL)')),
                   ('4.3', '4.3 — (card, vt, pp, NULL) duplicado ⇒ 23505 (FX)', dup('v_pp', 'NULL', '(card, vt, pp, NULL)')),
                   ('4.4', '4.4 — (card, vt, NULL, ec) duplicado ⇒ 23505 (FX)', dup('NULL', 'v_eca[1]', '(card, vt, NULL, ec)')),
                   ('4.5', '4.5 — (card, vt, pp, ec) duplicado ⇒ 23505 (FX)', dup('v_pp', 'v_eca[1]', '(card, vt, pp, ec)')),
                   ('4.6', '4.6 — mesma Card, mesmo finish, contextos diferentes ⇒ coexistem (FX)', c46()),
                   ('4.7', '4.7 — uq_card_variant_card_order preservado (RO)', c47()),
                   ('4.8', '4.8 — uq_card_variant_one_default_per_card preservado (RO)', c48())])


def e08():
    return envelope(SPEC)


PHEAD = header(['2830H · E08P — PRECHECK DO LOTE L6 (Seção 4)'], [
    'Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO. SELECT único.',
    'Cobre ......... P7X (card_variant e demais), P6, RLS, fixture disponível (par',
    '                livre, profiles ativos), XBASELINE, marcador, 2 profiles EC.',
])


def e08p():
    ctes = [pre.GS, pre.P7X, pre.XBASE, """fx AS (
    SELECT (SELECT count(*) FROM (
               SELECT 1 FROM public.card c
                 JOIN public.card_set cs ON cs.id = c.card_set_id
                 JOIN public.expansion e ON e.id = cs.expansion_id
                 JOIN public.card_variant_type t ON t.game_id = e.game_id, gs
                WHERE e.game_id = gs.game_id
                  AND NOT EXISTS (SELECT 1 FROM public.card_variant cv WHERE cv.card_id = c.id AND cv.variant_type_id = t.id)
                LIMIT 1) z) AS free_pair,
           (SELECT count(*) FROM public.card_printing_profile p, gs WHERE p.game_id = gs.game_id AND p.is_active) AS pp_active,
           (SELECT count(*) FROM public.card_edition_context_profile p, gs WHERE p.game_id = gs.game_id AND p.is_active) AS ec_active
),"""]
    gates = pre.GS_GATE + '\n' + pre.P7X_GATES + '\n' + pre.XBASE_GATE + '\n' + pre.MK_GATE + """
        ((SELECT free_pair FROM fx) = 1 AND (SELECT pp_active FROM fx) >= 1 AND (SELECT ec_active FROM fx) >= 2) AS g_4x_fixture_available,
        (to_regclass('public.uq_card_variant_identity') IS NOT NULL
         AND to_regclass('public.uq_card_variant_card_order') IS NOT NULL
         AND to_regclass('public.uq_card_variant_one_default_per_card') IS NOT NULL)   AS g_4x_objects,"""
    det = pre.P7X_DETAIL + '\n' + pre.XBASE_DETAIL + """
        'd_4x_fixture',     (SELECT to_jsonb(f) FROM fx f),
""" + pre.SESSION_DETAIL
    return pre.precheck(PHEAD, ctes, gates, det, 'e08p_precheck')
