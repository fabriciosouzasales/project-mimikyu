# L5 — 2.6 e 3.3 (Game sentinela). E07 (envelope) + E07P (precheck).
from lib import *
import pre

TR = 'public.card_edition_context_trait'
PR = 'public.card_edition_context_profile'
PT = 'public.card_edition_context_profile_trait'
MAP = 'public.card_edition_context_external_mapping'
NN = 'public.card_edition_context_external_mapping_trait'

GAME_INS = sql("INSERT INTO public.game (code, name)\nVALUES (v_marker, 'H2830 fixture Game ' || v_marker)\nRETURNING id INTO v_g2;")
GAME_CHK = iff("v_g2 IS NULL OR v_g2 = v_game", 'Game sentinela não criado ou igual ao Game real')


def c26():
    b = GAME_INS + GAME_CHK
    b += sql(f"INSERT INTO {TR} (game_id, family, code, name, display_order)\n"
             f"VALUES (v_g2, 'EVENT', v_marker || '_T2', 'H2830 fixture 2.6 T2 ' || v_marker, 1001)\n"
             f"RETURNING id INTO v_t2;")
    b += sql(f"SELECT COALESCE(max(display_order), 0) INTO v_ord_p FROM {PR} WHERE game_id = v_game;\n"
             f"INSERT INTO {PR} (game_id, code, name, display_order)\n"
             f"VALUES (v_game, v_marker || '_P', 'H2830 fixture 2.6 P ' || v_marker, v_ord_p + 1001)\n"
             f"RETURNING id INTO v_p;")
    b += iff('v_t2 IS NULL OR v_p IS NULL', 'fixture incompleta (trait do Game sentinela ou profile)')
    b += neg(f"INSERT INTO {PT} (profile_id, trait_id, game_id)\nVALUES (v_p, v_t2, v_game);",
             ('23503', 'fk_cecpt_trait', 'card_edition_context_profile_trait'),
             'N:N com trait de outro Game (FK composta)')
    b += sql(f"SELECT count(*) INTO v_n FROM {PT} WHERE profile_id = v_p;")
    b += iff('v_n <> 0', 'depois do negativo: %s linha(s) na N:N do profile de fixture (esperado 0)', 'v_n')
    return b


def c33():
    b = GAME_INS + GAME_CHK
    b += sql(f"INSERT INTO {TR} (game_id, family, code, name, display_order)\n"
             f"VALUES (v_g2, 'EVENT', v_marker || '_T1', 'H2830 fixture 3.3 T1 ' || v_marker, 1001)\n"
             f"RETURNING id INTO v_t1;\n"
             f"v_tok := v_marker || '_K';")
    b += sql(f"SELECT count(*) INTO v_n FROM {MAP} WHERE normalized_token = v_tok;")
    b += iff('v_n <> 0', 'pré-condição: token de fixture já tem mapping de EC (%s)', 'v_n')
    b += sql(f"SELECT count(*) INTO v_n FROM public.card_printing_external_mapping WHERE normalized_token = v_tok;")
    b += iff('v_n <> 0', 'pré-condição: token de fixture já tem mapping de Printing (%s)', 'v_n')
    b += sql(f"INSERT INTO {MAP} (game_id, asset_source_id, external_set_id, raw_field, normalized_token)\n"
             f"VALUES (v_g2, v_src, NULL, 'subtype', v_tok)\n"
             f"RETURNING id INTO v_m1;\n"
             f"INSERT INTO {NN} (mapping_id, trait_id, game_id)\n"
             f"VALUES (v_m1, v_t1, v_g2);")
    b += sql(f"SELECT normalized_token INTO v_txt FROM {MAP} WHERE id = v_m1 AND game_id = v_g2 AND is_active;")
    b += iff('v_txt IS DISTINCT FROM v_tok', 'mapping de fixture divergente no Game sentinela: %s (esperado %s)', 'v_txt, v_tok')
    b += sql("v_raw := jsonb_build_object('type', 'H2830 TIPO', 'subtype', v_tok);")
    # controle positivo: no próprio Game sentinela o mapping resolve
    b += rc('v_g2', 'NULL')
    b += expect('controle: Game sentinela', "'RESOLVED_NO_PRINTING'", 'NULL', EMPTY_U,
                "'NEEDS_REVIEW_NO_EC_PROFILE'", 'NULL', 'ARRAY[v_t1]', 'NULL', EMPTY_T)
    # o mesmo token no Game real: o mapping de OUTRO Game não resolve
    b += rc('v_game', 'NULL')
    b += expect('Game real, sem escopo', "'RESOLVED_NO_PRINTING'", 'NULL', EMPTY_U,
                "'RESOLVED_NO_EDITION_CONTEXT'", 'NULL', EMPTY_U, 'v_tok', EMPTY_T)
    return b


HEAD = header(['2830H · ENVELOPE E07 — SEÇÕES 2 e 3 (GAME SENTINELA) · lote L5, 2 casos: 2.6, 3.3'], [
    'Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO, NÃO COMPILADO no',
    '                PostgreSQL (BATCH12 — INTEGRATED COMPLETION, baseline 945caa32).',
    '                Execução exige E00 + E07P gate_pass = true e mandato próprio.',
    'Contrato ...... 2830 v7.0 · blob b4647dcb… (l. 463, 544; P5: Game de fixture',
    '                é linha sentinela NOVA, nunca um Game real alterado).',
    'Autoridades ... 2205 (fk_cecpt_trait, FK composta same-Game), 2207/2211 (routing',
    '                por game_id), 2206 (guards da N:N de profile).',
    'Leitura ....... 2.6 FX — trait de OUTRO Game na N:N de profile do Game real ⇒',
    '                23503 fk_cecpt_trait. Nenhum IMMEDIATE: o evento de selo do',
    '                profile de fixture fica pendente e é descartado pelo H283C.',
    '                3.3 FX+RC — mapping ativo de OUTRO Game (fixture) não resolve',
    '                no Game real: token no residual de Finish; controle positivo',
    '                no próprio Game sentinela (mesmo mapping ⇒ [T1]).',
    'Escrita (R2) .. game 2 INSERT (1 por caso) · trait 2 · profile 1 · N:N de',
    '                profile 1 tentativa recusada · mapping 1 · N:N de mapping 1.',
    '                Nenhum UPDATE/DELETE. Tudo desfeito pelo término em exceção.',
    'P8 ............ SET LOCAL lock_timeout = \'5s\' + asserção (DP-4 = A).',
])

SPEC = dict(tag='h2830_e07', env='E07_GAME_SENTINELA_2_6_3_3', header=HEAD,
            decl=[('v_g2', 'uuid', None), ('v_t1', 'uuid', None), ('v_t2', 'uuid', None), ('v_p', 'uuid', None),
                  ('v_m1', 'uuid', None), ('v_ord_p', 'integer', None), ('v_tok', 'text', None), ('v_raw', 'jsonb', None)] + RC_VARS,
            reset=['v_g2', 'v_t1', 'v_t2', 'v_p', 'v_m1', 'v_ord_p', 'v_tok', 'v_raw'],
            cases=[('2.6', '2.6 — trait de outro Game (Game sentinela) ⇒ 23503 FK composta fk_cecpt_trait', c26()),
                   ('3.3', '3.3 — mapping de outro Game (Game sentinela) não resolve no Game real (FX+RC)', c33())])


def e07():
    return envelope(SPEC)


PHEAD = header(['2830H · E07P — PRECHECK DO LOTE L5 (2.6, 3.3 · Game sentinela)'], [
    'Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO. SELECT único, sem DML,',
    '                sem DDL, sem set_config, sem TEMP.',
    'Ordem ......... depois do E00 (gate_pass = true), imediatamente antes do E07.',
    'Cobre ......... P7X (fecho de triggers de game/card_variant/job/row, identidade',
    '                por pino), P6, RLS, FK composta da N:N, forma de game.code,',
    '                identidade da RC, XBASELINE (para o E98) e marcador.',
])


def e07p():
    ctes = [pre.GS, pre.RC, pre.P7X, pre.XBASE, """fk AS (
    SELECT c.conname::text AS conname, c.contype::text AS contype, c.convalidated, c.confrelid,
           (SELECT array_agg(a.attname::text ORDER BY k.ord)
              FROM unnest(c.conkey) WITH ORDINALITY k(attnum, ord)
              JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.attnum) AS cols,
           (SELECT array_agg(a.attname::text ORDER BY k.ord)
              FROM unnest(c.confkey) WITH ORDINALITY k(attnum, ord)
              JOIN pg_attribute a ON a.attrelid = c.confrelid AND a.attnum = k.attnum) AS refcols
      FROM pg_constraint c
     WHERE c.conrelid = to_regclass('public.card_edition_context_profile_trait')
       AND c.conname IN ('fk_cecpt_profile', 'fk_cecpt_trait')
),
gck AS (
    SELECT c.conname::text AS conname, c.contype::text AS contype, pg_get_constraintdef(c.oid) AS def
      FROM pg_constraint c
     WHERE c.conrelid = to_regclass('public.game') AND c.conname IN ('ck_game_code_format', 'uq_game_code')
),"""]
    gates = pre.GS_GATE + '\n' + pre.RC_GATE + '\n' + pre.P7X_GATES + '\n' + pre.XBASE_GATE + '\n' + pre.MK_GATE + """
        ((SELECT count(*) FROM fk WHERE conname = 'fk_cecpt_trait' AND contype = 'f' AND convalidated
           AND confrelid = to_regclass('public.card_edition_context_trait')
           AND cols = ARRAY['trait_id','game_id'] AND refcols = ARRAY['id','game_id']) = 1
         AND (SELECT count(*) FROM fk WHERE conname = 'fk_cecpt_profile' AND contype = 'f' AND convalidated
           AND confrelid = to_regclass('public.card_edition_context_profile')
           AND cols = ARRAY['profile_id','game_id'] AND refcols = ARRAY['id','game_id']) = 1) AS g_26_fk_composite,
        ((SELECT count(*) FROM gck WHERE conname = 'uq_game_code' AND contype = 'u') = 1
         AND (SELECT count(*) FROM gck WHERE conname = 'ck_game_code_format' AND contype = 'c'
               AND strpos(def, '^[A-Z][A-Z0-9_]*$') > 0) = 1
         AND ('H2830_' || repeat('F', 32)) ~ '^[A-Z][A-Z0-9_]*$')                      AS g_game_code_domain,"""
    det = pre.RC_DETAIL + '\n' + pre.P7X_DETAIL + '\n' + pre.XBASE_DETAIL + """
        'd_fk',             COALESCE((SELECT jsonb_agg(to_jsonb(f) ORDER BY f.conname) FROM fk f), '[]'::jsonb),
        'd_game_checks',    COALESCE((SELECT jsonb_agg(to_jsonb(g) ORDER BY g.conname) FROM gck g), '[]'::jsonb),
""" + pre.SESSION_DETAIL
    return pre.precheck(PHEAD, ctes, gates, det, 'e07p_precheck')
