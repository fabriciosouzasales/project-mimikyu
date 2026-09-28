# L13 — Seção 5 (5.1, 5.2, 5.3, 5.6, 5.7). E15 (asserção) + E15P (medição A4).
# Derivação = 2831 v2.0 PASSO 0 / 0B / 1, reescrita read-only e sem TEMP num
# bloco ÚNICO (DERIV-5X) usado LITERALMENTE pelos dois arquivos.
#
# B-5X (INTEGRATED TECHNICAL RESOLUTION). READY_STRUCTURAL não tem predicado
# executável em nenhuma autoridade:
#   · 2830 v7.0 5.2 declara 365/285/80 "números de documento, NÃO medidos" e
#     exige a "mesma derivação da 2831";
#   · 2831 v2.0 não define READY_STRUCTURAL: o plano é lineage ∖ HOLD ∖
#     PRICING_CONDITIONED, sem filtro de tipo (a própria 2831 aborta com
#     PLAN_COVERAGE_MISMATCH se o resultado ≠ 285);
#   · README §5 define a classe como partição POR TIPO (63 tipos
#     READY_TO_DECOMPOSE = 365) ao lado de FINISH_PURO (26 tipos, 23.866),
#     NÃO_CONTAMINADO_FINISH, ZERO e HOLD — Σ 24.893 —, mas a lista dos 63
#     tipos não existe no repositório (MIGRATION-MAP-365 nomeia 23 tipos e
#     agrega o resto em "21× STANDARDS_WORLDS_*" e "Demais (24 tipos)").
# Nenhum predicado é aprovado aqui. O E15P MEDE as duas leituras
# fundamentadas e o E15 fica fail-closed até a adjudicação:
#   C1 (estrutura literal da 2831) = lineage ∖ HOLD. Refutada por
#      construção pelo README §5 (inclui FINISH_PURO); medida só como
#      contraprova.
#   C2 (semântica) = lineage ∖ HOLD cuja row de evidência (a mesma da 2831:
#      DISTINCT ON (cv.id) ORDER BY r.created_at, r.id) resolve Contexto de
#      Edição pela 2211 (RESOLVED_WITH_EC_PROFILE) — o gate
#      PLAN_NON_DETERMINISTIC_CONTEXT da 2831 e a regra do MIGRATION-MAP
#      ("Edition Context target = tokens de contexto da própria raw_data").
#      Pré-filtro exato: a 2211 só consome subtype/stamp; sem essas chaves o
#      eixo 3 é RESOLVED_NO_EDITION_CONTEXT.
#   A (lista de tipos) = exige extrair e aprovar a lista dos 63 tipos (LIVE
#      read-only + decisão editorial); não implementável sem ela.
from lib import *
import pre

C = dict(hold=107, structural=365, unconditioned=285, conditioned=80, staff=40, slr=40, resulting=23955, matched=1129)
READY_DEF = None      # 'C0' | 'C1' | 'C2' — pendente (B-5X); só o candidato ≡ A no LIVE. None ⇒ E15 fail-closed.

GAME = "(SELECT id FROM public.game WHERE code = 'POKEMON')"
SRC = "(SELECT id FROM public.asset_source WHERE code = 'TCGDEX')"

# Impressão digital de A (população original de 63 tipos / 365), tal como
# publicada em MIGRATION-MAP-365.md: 23 tipos nomeados com contagem exata
# (Σ 320) + 16 tipos WORLDS/ASIA (Σ 21) + 24 tipos singletons (Σ 24) = 63
# tipos / 365, e as restrições por Set SET_LOGO_REVERSE = SVP 38 + DP1 2,
# SET_LOGO_STANDARDS = DP1 4. Um candidato só é equivalente a A se reproduzir
# TODA a impressão digital no LIVE (medida pelo E15P, nunca presumida).
MAP_NAMED = [('SATANDARD_REWARDS', 51), ('STAFF_HOLO', 40), ('SET_LOGO_REVERSE', 40), ('REWARDS_HOLO', 30),
             ('POKEMON_CENTER_HOLO', 19), ('COSMOS_REWARDS_HOLO', 18), ('COSMOS_REWARDS_REVERSE', 17),
             ('COSMOS_PROFESSOR_REVERSE', 16), ('STANDARDS_TEACHER_PROGRAM', 14), ('STANDARD_GYM_CHALLENGE', 9),
             ('GAMESTOP_HOLO', 9), ('STANDARD_REGIONAL_CHAMPIONSHIPS', 8), ('EBGAMES_HOLO', 8),
             ('STANDARD_PIKACHU_WORLD_2000', 6), ('W_PROMO_STAMPED', 6), ('SET_LOGO_STANDARDS', 4),
             ('STANDARD_FIRST_MOVIE', 4), ('STANDARD_FIRST_MOVIE_INVERTED', 4), ('STANDARD_REGIONAL_CHAMPIONSHIPS_STAFF', 4),
             ('STANDARDS_LEAGUE', 4), ('STANDARD_WORLDS_2024', 3), ('STANDARDS_HORIZONS', 3), ('GYM_CHALLENGE_HOLO', 3)]
MAP_FP = dict(named_sum=320, worlds_types=16, worlds_n=21, single_types=24, n_types=63,
              slr_svp=38, slr_dp1=2, sls_dp1=4)
CANDS = ['c0', 'c1', 'c2']

_map_values = ',\n           '.join(f"('{c}', {n})" for c, n in MAP_NAMED)


def _fp(c):
    s = f"""d5_{c}_bt AS (
    SELECT vt.code, count(*) AS n FROM d5_{c} s JOIN public.card_variant_type vt ON vt.id = s.variant_type_id GROUP BY vt.code
),"""
    return s


def _m(c):
    bt = f'd5_{c}_bt'
    return f"""           (SELECT count(*) FROM d5_{c}) AS {c}_structural,
           (SELECT count(*) FROM d5_{c} s WHERE s.id NOT IN (SELECT id FROM d5_pricing)) AS {c}_unconditioned,
           (SELECT count(*) FROM d5_{c} s WHERE s.id IN (SELECT id FROM d5_pricing)) AS {c}_conditioned,
           (SELECT count(*) FROM d5_{c} s WHERE s.id NOT IN (SELECT id FROM d5_pricing) AND s.id IN (SELECT id FROM d5_hold)) AS {c}_plan_x_hold,
           (SELECT count(*) FROM d5_{c} s WHERE s.id NOT IN (SELECT id FROM d5_pricing) AND s.id IN (SELECT id FROM d5_pricing)) AS {c}_plan_x_pricing,
           (SELECT count(*) FROM d5_{c} s JOIN public.card_variant_type vt ON vt.id = s.variant_type_id
             WHERE s.id IN (SELECT id FROM d5_pricing) AND vt.code = 'STAFF_HOLO') AS {c}_cond_staff_holo,
           (SELECT count(*) FROM d5_{c} s JOIN public.card_variant_type vt ON vt.id = s.variant_type_id
             WHERE s.id IN (SELECT id FROM d5_pricing) AND vt.code = 'SET_LOGO_REVERSE') AS {c}_cond_set_logo_reverse,
           (SELECT count(*) FROM d5_{c} s WHERE s.id IN (SELECT id FROM d5_pscid)) AS {c}_cond_by_pscid,
           (SELECT count(*) FROM d5_{c} s WHERE s.id IN (SELECT id FROM d5_psvm)) AS {c}_cond_by_psvm,
           (SELECT count(*) FROM {bt}) AS {c}_fp_n_types,
           (SELECT count(*) FROM d5_map m LEFT JOIN {bt} b ON b.code = m.code WHERE COALESCE(b.n, 0) <> m.n) AS {c}_fp_named_bad,
           (SELECT count(*) FROM {bt} b WHERE b.code NOT IN (SELECT code FROM d5_map) AND b.code ~ '(WORLDS|ASIA)') AS {c}_fp_worlds_types,
           (SELECT COALESCE(sum(n), 0) FROM {bt} b WHERE b.code NOT IN (SELECT code FROM d5_map) AND b.code ~ '(WORLDS|ASIA)') AS {c}_fp_worlds_n,
           (SELECT count(*) FROM {bt} b WHERE b.code NOT IN (SELECT code FROM d5_map) AND b.code !~ '(WORLDS|ASIA)') AS {c}_fp_single_types,
           (SELECT count(*) FROM {bt} b WHERE b.code NOT IN (SELECT code FROM d5_map) AND b.code !~ '(WORLDS|ASIA)' AND b.n <> 1) AS {c}_fp_single_non1,
           (SELECT count(*) FROM d5_{c} s JOIN public.card_variant_type vt ON vt.id = s.variant_type_id
              JOIN public.card_set cs ON cs.id = s.card_set_id WHERE vt.code = 'SET_LOGO_REVERSE' AND cs.code = 'SVP') AS {c}_fp_slr_svp,
           (SELECT count(*) FROM d5_{c} s JOIN public.card_variant_type vt ON vt.id = s.variant_type_id
              JOIN public.card_set cs ON cs.id = s.card_set_id WHERE vt.code = 'SET_LOGO_REVERSE' AND cs.code = 'DP1') AS {c}_fp_slr_dp1,
           (SELECT count(*) FROM d5_{c} s JOIN public.card_variant_type vt ON vt.id = s.variant_type_id
              JOIN public.card_set cs ON cs.id = s.card_set_id WHERE vt.code = 'SET_LOGO_STANDARDS' AND cs.code = 'DP1') AS {c}_fp_sls_dp1,
"""


def fp_ok(c, ref='m.'):
    """predicado ÚNICO da impressão digital (E15P e E15)"""
    f = MAP_FP
    return (f"({ref}{c}_fp_named_bad = 0 AND {ref}{c}_fp_n_types = {f['n_types']} AND {ref}{c}_fp_worlds_types = {f['worlds_types']}"
            f" AND {ref}{c}_fp_worlds_n = {f['worlds_n']} AND {ref}{c}_fp_single_types = {f['single_types']} AND {ref}{c}_fp_single_non1 = 0"
            f" AND {ref}{c}_fp_slr_svp = {f['slr_svp']} AND {ref}{c}_fp_slr_dp1 = {f['slr_dp1']} AND {ref}{c}_fp_sls_dp1 = {f['sls_dp1']})")



def cand_ok(c, ref='m.'):
    """candidato ≡ A: impressão digital + constantes 365/285/80 + 40/40 + exclusões"""
    return (fp_ok(c, ref) + f" AND {ref}{c}_structural = {C['structural']} AND {ref}{c}_unconditioned = {C['unconditioned']}"
            f" AND {ref}{c}_conditioned = {C['conditioned']} AND {ref}{c}_cond_staff_holo = {C['staff']}"
            f" AND {ref}{c}_cond_set_logo_reverse = {C['slr']} AND {ref}{c}_plan_x_hold = 0 AND {ref}{c}_plan_x_pricing = 0")

DERIV = f"""d5_hold AS (
    SELECT cv.id
      FROM public.card_variant cv
      JOIN public.card_variant_type vt ON vt.id = cv.variant_type_id
      JOIN public.card c  ON c.id  = cv.card_id
      JOIN public.card_set cs ON cs.id = c.card_set_id
     WHERE vt.code = 'PROMO_STAMPED'
        OR (vt.code LIKE 'SET_LOGO%'
            AND cs.code !~ '^EX(7|8|9|10|11|12|13|14|15|16)$'
            AND cs.code NOT IN ('DP1','SWSH9','SVP'))
),
d5_pscid AS (
    SELECT cv.id FROM public.card_variant cv
     WHERE EXISTS (SELECT 1 FROM public.pricing_source_card_identity x WHERE x.card_variant_type_id = cv.variant_type_id)
),
d5_psvm AS (
    SELECT cv.id FROM public.card_variant cv
     WHERE EXISTS (SELECT 1 FROM public.pricing_source_variant_mapping x WHERE x.variant_type_id = cv.variant_type_id)
),
d5_pricing AS (
    SELECT id FROM d5_pscid UNION SELECT id FROM d5_psvm
),
d5_map(code, n) AS (
    VALUES {_map_values}
),
d5_c0 AS (
    SELECT cv.id, cv.variant_type_id, c.card_set_id
      FROM public.card_variant cv
      JOIN public.card c ON c.id = cv.card_id
     WHERE cv.printing_profile_id IS NULL
       AND EXISTS (SELECT 1 FROM public.catalog_variant_import_row r WHERE r.resulting_variant_id = cv.id)
),
d5_ev AS (
    SELECT DISTINCT ON (cv.id) cv.id, cv.variant_type_id, c.card_set_id, r.raw_data
      FROM public.card_variant cv
      JOIN public.card c ON c.id = cv.card_id
      JOIN public.catalog_variant_import_row r ON r.resulting_variant_id = cv.id
     WHERE cv.id NOT IN (SELECT id FROM d5_hold)
     ORDER BY cv.id, r.created_at ASC, r.id ASC
),
d5_c1 AS (
    SELECT e.id, e.variant_type_id, e.card_set_id FROM d5_ev e
),
d5_c2 AS (
    SELECT e.id, e.variant_type_id, e.card_set_id
      FROM d5_ev e
      LEFT JOIN LATERAL internal.resolve_variant_mapping_scope(e.card_set_id, {SRC}) sc ON true
     CROSS JOIN LATERAL internal.resolve_variant_row_axes(e.raw_data, {GAME}, {SRC}, sc.external_set_id) ax
     WHERE (jsonb_exists(e.raw_data, 'subtype') OR jsonb_exists(e.raw_data, 'stamp'))
       AND ax.edition_context_state = 'RESOLVED_WITH_EC_PROFILE'
),
""" + ''.join(_fp(c) + '\n' for c in CANDS) + """d5_m AS (
    SELECT (SELECT count(*) FROM d5_hold) AS hold,
           (SELECT count(*) FROM d5_ev) AS lineage_not_hold,
""" + ''.join(_m(c) for c in CANDS) + """           (SELECT count(*) FROM public.catalog_variant_import_row WHERE resulting_variant_id IS NOT NULL) AS lineage_resulting,
           (SELECT count(*) FROM public.catalog_variant_import_row WHERE matched_variant_id IS NOT NULL) AS lineage_matched
),"""


def deriv_select():
    return 'WITH ' + DERIV.rstrip(',') + '\nSELECT to_jsonb(m) FROM d5_m m'


PRE = """
    -- ------------------------------------------------------------------ --
    -- B-5X: READY_STRUCTURAL não adjudicado ⇒ nenhum caso roda (fail-closed)
    -- ------------------------------------------------------------------ --
""" + ("""    RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
        'H2830_FAIL: envelope=%s caso=PREFLIGHT B-5X: READY_STRUCTURAL não adjudicado (C2 ou A); E15 bloqueado', c_env);
""" if READY_DEF is None else "") + """
    -- ------------------------------------------------------------------ --
    -- DERIV-5X (bloco idêntico ao E15P) — subtransação própria
    -- ------------------------------------------------------------------ --
    v_case := 'DERIV-5X';
    BEGIN
""" + ind(deriv_select(), 8) + """
          INTO STRICT v_agg;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
        RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
            'H2830_FAIL: envelope=%s caso=DERIV-5X derivação falhou sqlstate=%s msg=%s', c_env, v_state, v_msg);
    END;
"""

P = (READY_DEF or 'c2').lower()


def g(k):
    return f"(v_agg->>'{k}')::bigint"


def eq(k, v, label):
    return iff(f"{g(k)} IS DISTINCT FROM {v}", f'{label}: medido=%s esperado={v} (STOP e adjudicação; nunca reajuste)', g(k))


CASES = [
    ('5.1', '5.1 [AUTO RO] hold_frozen = 107 exato (PASSO 0 da 2831)', eq('hold', C['hold'], 'hold_frozen')),
    ('5.2', '5.2 [AUTO RO] READY_STRUCTURAL 365 = UNCONDITIONED 285 + PRICING_CONDITIONED 80',
     eq(f'{P}_structural', C['structural'], 'READY_STRUCTURAL') + eq(f'{P}_unconditioned', C['unconditioned'], 'READY_UNCONDITIONED')
     + eq(f'{P}_conditioned', C['conditioned'], 'READY_PRICING_CONDITIONED')
     + iff('NOT COALESCE(' + fp_ok(P, '').replace(P + '_', "(v_agg->>'" + P + '_').replace(' =', "')::bigint =").replace(' <>', "')::bigint <>") + ', false)',
           'impressão digital de A (MIGRATION-MAP-365) não reproduzida pelo candidato ' + P)),
    ('5.3', '5.3 [AUTO RO] plano (285) ∩ HOLD (107) = 0 — prova de EXCLUSÃO do HOLD',
     eq(f'{P}_plan_x_hold', 0, 'plano ∩ HOLD') + eq(f'{P}_unconditioned', C['unconditioned'], 'universo do plano (P13)')),
    ('5.6', '5.6 [AUTO RO] lineage intacto: resulting 23.955 · matched 1.129 (baseline de FREEZE)',
     eq('lineage_resulting', C['resulting'], 'resulting_variant_id') + eq('lineage_matched', C['matched'], 'matched_variant_id')),
    ('5.7', '5.7 [AUTO RO] plano ∩ PRICING_CONDITIONED = 0; 80 = STAFF_HOLO 40 + SET_LOGO_REVERSE 40; conceitos separados',
     eq(f'{P}_plan_x_pricing', 0, 'plano ∩ PRICING_CONDITIONED') + eq(f'{P}_conditioned', C['conditioned'], 'PRICING_CONDITIONED em READY_STRUCTURAL')
     + eq(f'{P}_cond_staff_holo', C['staff'], 'STAFF_HOLO') + eq(f'{P}_cond_set_logo_reverse', C['slr'], 'SET_LOGO_REVERSE')),
]

HEAD = header(['2830H · ENVELOPE E15 — SEÇÃO 5 (LEGADO / HOLD / EXCLUSÃO) · lote L13, 5 casos: 5.1 5.2 5.3 5.6 5.7'], [
    'Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO, NÃO COMPILADO no',
    '                PostgreSQL. BLOQUEADO por B-5X: o PREFLIGHT levanta H2830_FAIL',
    '                enquanto READY_STRUCTURAL não for adjudicado (C0/C1/C2 ≡ A); o gerador',
    '                só remove o bloqueio com READY_DEF definido.',
    'Contrato ...... 2830 v7.0 Seção 5; derivação 2831 v2.0 PASSO 0/0B/1 (arquivo',
    '                NÃO alterado), sem TEMP, bloco DERIV-5X idêntico ao E15P.',
    'Escrita ....... NENHUMA. Término em exceção por uniformidade (P2).',
    'P8 ............ SET LOCAL lock_timeout = \'5s\' + asserção (DP-4 = A).',
])


def e15():
    spec = dict(tag='h2830_e15', env='E15_SECAO_5_LEGADO_HOLD', header=HEAD,
                decl=[('v_agg', 'jsonb', None)], preflight_extra=PRE, cases=CASES,
                term_fields=[('hold', "v_agg->>'hold'"), ('structural', f"v_agg->>'{P}_structural'"),
                             ('unconditioned', f"v_agg->>'{P}_unconditioned'"), ('conditioned', f"v_agg->>'{P}_conditioned'"),
                             ('by_pscid', f"v_agg->>'{P}_cond_by_pscid'"), ('by_psvm', f"v_agg->>'{P}_cond_by_psvm'")])
    return envelope(spec)


PHEAD = header(['2830H · E15P — MEDIÇÃO A4 + PRECHECK DO LOTE L13 (Seção 5) · SELECT único, read-only'], [
    'Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO.',
    'Função ........ instrumento de ADJUDICAÇÃO do B-5X: mede, com o bloco DERIV-5X',
    '                idêntico ao E15, HOLD, lineage e as duas leituras de',
    '                READY_STRUCTURAL (C0 predicado 2841, C1 literal-2831, C2 semântica)',
    '                contra a impressão digital MIGRATION-MAP-365 de A (63 tipos) e a',
    '                composição por tipo. gate_pass só é true com READY adjudicado',
    '                (g_5x_ready_adjudicated) e constantes medidas = contrato.',
    'Custo ......... C2 chama a 2211 por variant com lineage fora do HOLD e com',
    '                subtype/stamp na evidência (ver P9A-5X / P9B).',
])


def e15p():
    ctes = [pre.GS, DERIV, """d5_scope AS (
    SELECT e.card_set_id, count(sc.*) AS n
      FROM d5_ev e
      CROSS JOIN gs
      LEFT JOIN LATERAL internal.resolve_variant_mapping_scope(e.card_set_id, gs.src_id) sc ON true
     GROUP BY e.card_set_id
),"""]
    checks = "\n             AND ".join(f"m.{k} = {v}" for k, v in [
        ('hold', C['hold']), ('lineage_resulting', C['resulting']), ('lineage_matched', C['matched'])])
    uniq = ' + '.join(f"(CASE WHEN {cand_ok(c)} THEN 1 ELSE 0 END)" for c in CANDS)
    gates = pre.GS_GATE + f"""
        {'true' if READY_DEF else 'false'}                                                AS g_5x_ready_adjudicated,
        (SELECT {checks} FROM d5_m m)                                                   AS g_5x_constants_measured,
        (SELECT {uniq} FROM d5_m m) = 1                                                  AS g_5x_unique_candidate_equals_a,
        {('(SELECT ' + cand_ok(P) + ' FROM d5_m m)') if READY_DEF else 'false'}           AS g_5x_adjudicated_candidate_ok,
        (SELECT COALESCE(max(n), 0) <= 1 FROM d5_scope)                                 AS g_scope_unique,
        (to_regclass('public.pricing_source_card_identity') IS NOT NULL
         AND to_regclass('public.pricing_source_variant_mapping') IS NOT NULL)          AS g_pricing_tables,"""
    det = """        'd_5x_measured',    (SELECT to_jsonb(m) FROM d5_m m),
        'd_5x_expected',    """ + "jsonb_build_object(" + ', '.join(f"'{k}', {v}" for k, v in C.items()) + """),
        'd_5x_ready_def',   """ + (q(READY_DEF) if READY_DEF else 'NULL::text') + """,
        'd_5x_candidate_ok', (SELECT jsonb_build_object(""" + ', '.join(f"'{c}', ({cand_ok(c)})" for c in CANDS) + """) FROM d5_m m),
        'd_5x_c0_by_type',  COALESCE((SELECT jsonb_object_agg(code, n) FROM d5_c0_bt), '{}'::jsonb),
        'd_5x_c2_by_type',  COALESCE((SELECT jsonb_object_agg(code, n) FROM (SELECT vt.code, count(*) AS n FROM d5_c2 s
                                  JOIN public.card_variant_type vt ON vt.id = s.variant_type_id GROUP BY vt.code) z), '{}'::jsonb),
        'd_5x_c1_by_type',  COALESCE((SELECT jsonb_object_agg(code, n) FROM (SELECT vt.code, count(*) AS n FROM d5_c1 s
                                  JOIN public.card_variant_type vt ON vt.id = s.variant_type_id GROUP BY vt.code) z), '{}'::jsonb),
""" + pre.SESSION_DETAIL
    return pre.precheck(PHEAD, ctes, gates, det, 'e15p_precheck')
