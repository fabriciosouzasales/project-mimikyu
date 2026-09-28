# L9 — K3, K4, K8 (prova ESTÁTICA do confirm 2218, declarada). E11, sem DML.
# Nenhuma chamada ao confirm (P7, decisão 3). O corpo LIVE é fixado por md5 LF;
# os predicados são de posição/contenção (strpos) sobre o prosrc com espaços
# normalizados, espelhados 1:1 pelo verificador offline (static_check) sobre o
# corpo do repositório e sobre mutações.
from lib import *

CONFIRM_SIG = 'public.admin_confirm_catalog_variant_import(uuid,uuid[])'
CONFIRM_PIN = 'b83f7708ca2b7498b753b394d768f66e'

# fragmentos exigidos (já com espaço normalizado: '\s+' -> ' ')
K_TOKENS = {
    'h_open': 'WHEN unique_violation THEN',
    'h_other': 'WHEN OTHERS THEN',
    'loop': 'FOR v_row IN',
    'lock': 'PERFORM 1 FROM public.card c WHERE c.id IN (',
    'lock_end': 'ORDER BY c.id FOR UPDATE;',
    'gsd': 'GET STACKED DIAGNOSTICS',
    'con': '= CONSTRAINT_NAME',
    'match_sel': 'SELECT cv.* INTO v_existing_variant FROM public.card_variant cv',
    'reread_sel': 'SELECT cv.id INTO v_race_variant_id FROM public.card_variant cv',
    'k_card': 'WHERE cv.card_id = v_row.card_id AND cv.variant_type_id = v_variant_type_id',
    'k_pp': 'AND cv.printing_profile_id IS NOT DISTINCT FROM v_printing_profile_id',
    'k_ec': 'AND cv.edition_context_profile_id IS NOT DISTINCT FROM v_edition_context_profile_id',
    'unres': "error_detail = 'CARD_VARIANT_UNIQUE_VIOLATION_UNRESOLVED:",
}

LOAD = sql(f"SELECT count(*) INTO v_n FROM pg_proc p WHERE p.oid = to_regprocedure({q(CONFIRM_SIG)});") \
    + iff('v_n <> 1', 'confirm ausente: %s', 'v_n') \
    + sql(f"SELECT replace(p.prosrc, chr(13) || chr(10), chr(10)) INTO v_body\n"
          f"  FROM pg_proc p WHERE p.oid = to_regprocedure({q(CONFIRM_SIG)});\n"
          f"v_txt := md5(v_body);") \
    + iff(f"v_txt IS DISTINCT FROM {q(CONFIRM_PIN)}", 'corpo LIVE do confirm fora do pino: md5_lf=%s', 'v_txt') \
    + sql("v_nrm := regexp_replace(v_body, '\\s+', ' ', 'g');\n"
          f"v_ho := strpos(v_nrm, {q(K_TOKENS['h_open'])});\n"
          f"v_hx := strpos(v_nrm, {q(K_TOKENS['h_other'])});\n"
          f"v_lp := strpos(v_nrm, {q(K_TOKENS['loop'])});") \
    + iff("v_ho = 0 OR v_hx = 0 OR v_lp = 0 OR NOT (v_lp < v_ho AND v_ho < v_hx)",
          'marcos do confirm fora de ordem: loop=%s unique_violation=%s others=%s', 'v_lp, v_ho, v_hx') \
    + iff(f"strpos(substr(v_nrm, v_ho + 1), {q(K_TOKENS['h_open'])}) <> 0 OR strpos(substr(v_nrm, v_hx + 1), {q(K_TOKENS['h_other'])}) <> 0",
          'mais de um handler unique_violation/OTHERS no corpo (leitura ambígua)') \
    + sql("v_hnd := substr(v_nrm, v_ho, v_hx - v_ho);\n"
          "v_mat := substr(v_nrm, v_lp, v_ho - v_lp);")


def has(var, key):
    return f"strpos({var}, {q(K_TOKENS[key])}) > 0"


def k3():
    b = LOAD
    b += iff(f"NOT ({has('v_hnd', 'gsd')} AND {has('v_hnd', 'con')})",
             'handler unique_violation não lê CONSTRAINT_NAME por GET STACKED DIAGNOSTICS')
    b += iff(f"NOT ({has('v_hnd', 'reread_sel')} AND {has('v_hnd', 'k_card')} AND {has('v_hnd', 'k_pp')} AND {has('v_hnd', 'k_ec')})",
             'releitura do handler não usa a identidade de 4 componentes com IS NOT DISTINCT FROM')
    b += iff(f"NOT {has('v_hnd', 'unres')}", 'handler não grava CARD_VARIANT_UNIQUE_VIOLATION_UNRESOLVED: em error_detail')
    b += iff("strpos(upper(v_hnd), 'RAISE') <> 0", 'handler unique_violation re-levanta (RAISE presente)')
    return b


def k4():
    b = LOAD
    b += iff(f"NOT ({has('v_mat', 'match_sel')} AND {has('v_mat', 'k_card')} AND {has('v_mat', 'k_pp')} AND {has('v_mat', 'k_ec')})",
             'matching do confirm não usa IS NOT DISTINCT FROM nos dois eixos nuláveis')
    b += iff(f"NOT ({has('v_hnd', 'k_pp')} AND {has('v_hnd', 'k_ec')})",
             'releitura do confirm não usa IS NOT DISTINCT FROM nos dois eixos nuláveis')
    b += iff("strpos(v_nrm, 'printing_profile_id = v_printing_profile_id') <> 0"
             " OR strpos(v_nrm, 'edition_context_profile_id = v_edition_context_profile_id') <> 0",
             'igualdade simples (=) num eixo nulável da identidade')
    return b


def k8():
    b = LOAD
    b += sql(f"v_lk := strpos(v_nrm, {q(K_TOKENS['lock'])});\n"
             f"v_le := strpos(v_nrm, {q(K_TOKENS['lock_end'])});")
    b += iff('v_lk = 0 OR v_le = 0 OR NOT (v_lk < v_le AND v_le < v_lp)',
             'lock das Cards ausente, sem ORDER BY c.id FOR UPDATE, ou depois do loop: lock=%s fim=%s loop=%s', 'v_lk, v_le, v_lp')
    b += iff(f"strpos(substr(v_nrm, v_lk, v_le - v_lk), 'LIMIT') <> 0 OR strpos(substr(v_nrm, v_le + 1), {q(K_TOKENS['lock'])}) <> 0",
             'bloco de lock ambíguo (LIMIT ou lock repetido)')
    return b


HEAD = header(['2830H · ENVELOPE E11 — SEÇÃO K (PROVA ESTÁTICA DO CONFIRM) · lote L9, 3 casos: K3, K4, K8'], [
    'Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO, NÃO COMPILADO no',
    '                PostgreSQL (BATCH12 — INTEGRATED COMPLETION, baseline 945caa32).',
    'Contrato ...... 2830 v7.0 · K3-S, K4-S, K8a [AUTO ST]. Prova que o código DIZ',
    '                isso; não prova que ELE FAZ (K3-B/K4-B/K8b são MANUAIS, P14).',
    'Autoridade .... 2218 (confirm), corpo fixado: md5 LF ' + CONFIRM_PIN + '.',
    'Leitura ....... espaços normalizados (\\s+ -> \' \'); regiões: matching = [FOR v_row IN,',
    '                WHEN unique_violation); handler = [WHEN unique_violation, WHEN OTHERS).',
    'Escrita ....... NENHUMA. Nenhuma chamada ao confirm. Sem precheck próprio: o',
    '                gate de entrada é o E00 (inventário) + o pino do corpo aqui.',
    'P8 ............ SET LOCAL lock_timeout = \'5s\' + asserção (DP-4 = A).',
])


def e11():
    spec = dict(tag='h2830_e11', env='E11_SECAO_K_CONFIRM_ESTATICO', header=HEAD,
                decl=[('v_body', 'text', None), ('v_nrm', 'text', None), ('v_hnd', 'text', None), ('v_mat', 'text', None),
                      ('v_ho', 'integer', None), ('v_hx', 'integer', None), ('v_lp', 'integer', None),
                      ('v_lk', 'integer', None), ('v_le', 'integer', None)],
                reset=['v_body', 'v_nrm', 'v_hnd', 'v_mat'],
                cases=[('K3', 'K3-S [AUTO ST] handler unique_violation: antes de OTHERS, CONSTRAINT_NAME,\nreleitura 4 componentes IS NOT DISTINCT FROM, UNRESOLVED sem re-raise', k3()),
                       ('K4', 'K4-S [AUTO ST] matching e releitura com IS NOT DISTINCT FROM nos 2 eixos nuláveis', k4()),
                       ('K8', 'K8a [AUTO ST] FOR UPDATE das Cards do lote com ORDER BY c.id, antes do loop', k8())],
                term_fields=[('confirm_md5', q(CONFIRM_PIN))])
    return envelope(spec)


# ---------------------------------------------------------------------------
# espelho offline dos predicados (static_check): mesmo texto, mesma lógica
# ---------------------------------------------------------------------------
def k_eval(body):
    """devolve {'K3':bool,'K4':bool,'K8':bool} para um corpo (LF)"""
    import re as _re
    n = _re.sub(r'\s+', ' ', body)
    f = lambda s, t: s.find(t) + 1
    T = K_TOKENS
    ho, hx, lp = f(n, T['h_open']), f(n, T['h_other']), f(n, T['loop'])
    base = ho and hx and lp and lp < ho < hx and n[ho:].find(T['h_open']) < 0 and n[hx:].find(T['h_other']) < 0
    if not base:
        return {'K3': False, 'K4': False, 'K8': False}
    hnd = n[ho - 1:hx - 1]
    mat = n[lp - 1:ho - 1]
    h = lambda s, k: T[k] in s
    k3 = (h(hnd, 'gsd') and h(hnd, 'con') and h(hnd, 'reread_sel') and h(hnd, 'k_card') and h(hnd, 'k_pp')
          and h(hnd, 'k_ec') and h(hnd, 'unres') and 'RAISE' not in hnd.upper())
    k4 = (h(mat, 'match_sel') and h(mat, 'k_card') and h(mat, 'k_pp') and h(mat, 'k_ec') and h(hnd, 'k_pp') and h(hnd, 'k_ec')
          and 'printing_profile_id = v_printing_profile_id' not in n
          and 'edition_context_profile_id = v_edition_context_profile_id' not in n)
    lk, le = f(n, T['lock']), f(n, T['lock_end'])
    k8 = bool(lk and le and lk < le < lp and 'LIMIT' not in n[lk - 1:le - 1] and n[le:].find(T['lock']) < 0)
    return {'K3': k3, 'K4': bool(k4), 'K8': k8}
