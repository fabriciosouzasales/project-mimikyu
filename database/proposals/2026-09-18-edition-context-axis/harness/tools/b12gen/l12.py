# L12 — Seção G (G1–G8): guard 2214 v3.1 exercido DIRETAMENTE (padrão PASSO 4
# da 2214), jobs/rows de fixture (P5). Nenhuma RPC, claim ou set_config.
# E14 + E14P.
from lib import *
import pre, jr
from jr import PICK, job, row, row_stmt, nd, ROW, JOB

OPK = ('P0001', 'CVIR_OPERATIONAL_VALID_REQUIRES_EDITION_CONTEXT_KEY:')
RMV = ('P0001', 'CVIR_EDITION_CONTEXT_KEY_REMOVAL_FORBIDDEN:')
NOKEY = nd(vt='v_vt', pp='NULL')                  # VALID sem a chave EC
NULLKEY = nd(vt='v_vt', pp='NULL', ec='NULL')     # chave EC = JSON null


def exists(var, what):
    return sql(f"SELECT count(*) INTO v_n FROM {ROW} WHERE id = {var};") + iff(f'{var} IS NULL OR v_n <> 1', f'{what}: row não persistida')


def g1():
    b = PICK + job('v_job1', 'STAGED', '1')
    b += row('v_r1', 'v_job1', "'{}'::jsonb", 'NEEDS_REVIEW')
    return b + exists('v_r1', 'G1 STAGED·PENDING·NEEDS_REVIEW·ausente')


def g2():
    b = PICK + job('v_job1', 'STAGED', '1')
    b += neg(row_stmt('v_job1', NOKEY, 'VALID'), OPK, 'G2 STAGED·PENDING·VALID·ausente')
    return b


def g3():
    b = PICK + job('v_job1', 'STAGED', '1')
    b += row('v_r1', 'v_job1', NULLKEY, 'VALID') + exists('v_r1', 'G3 JSON null')
    b += row('v_r2', 'v_job1', nd(vt='v_vt', pp='NULL', ec='v_ec'), 'VALID') + exists('v_r2', 'G3 UUID de profile existente')
    b += sql("SELECT count(*) INTO v_n FROM public.card_edition_context_profile WHERE id = v_ec;")
    b += iff('v_n <> 1', 'G3: profile usado não existe')
    return b


def g4():
    b = PICK
    for i, st in enumerate(['CONFIRMING', 'RECEIVED', 'PROCESSING'], 1):
        b += job('v_job1', st, str(i))
        b += neg(row_stmt('v_job1', NOKEY, 'VALID'), OPK, f'G4 {st}·PENDING·VALID·ausente')
    return b


def g5():
    b = PICK
    for i, st in enumerate(['COMPLETED', 'COMPLETED_WITH_ERRORS', 'FAILED'], 1):
        b += job('v_job1', st, str(i))
        b += row('v_r1', 'v_job1', NOKEY, 'VALID') + exists('v_r1', f'G5 {st}·VALID·PENDING·ausente')
    return b


def g6():
    b = PICK + job('v_job1', 'CANCELLED', '1')
    return b + row('v_r1', 'v_job1', NOKEY, 'VALID') + exists('v_r1', 'G6 CANCELLED·VALID·PENDING·ausente')


def g7():
    b = PICK + job('v_job1', 'CANCELLED', '1')
    b += row('v_r1', 'v_job1', NOKEY, 'VALID', 'PENDING', 'SKIPPED') + exists('v_r1', 'G7 row histórica')
    b += sql(f"UPDATE {JOB} SET status = 'STAGED' WHERE id = v_job1;\nGET DIAGNOSTICS v_m = ROW_COUNT;\n"
             f"SELECT status INTO v_txt FROM {JOB} WHERE id = v_job1;")
    b += iff("v_m <> 1 OR v_txt IS DISTINCT FROM 'STAGED'", 'G7: reativação CANCELLED→STAGED barrada ou não aplicada (rows=%s status=%s)', 'v_m, v_txt')
    b += neg(f"UPDATE {ROW} SET normalized_data = normalized_data WHERE id = v_r1;", OPK, 'G7 1ª escrita na row reativada sem a chave')
    # G-BIS (no-lockout): sair de PENDING sem a chave é sempre permitido
    b += sql(f"UPDATE {ROW} SET persistence_status = 'FAILED' WHERE id = v_r1;\nGET DIAGNOSTICS v_m = ROW_COUNT;\n"
             f"SELECT persistence_status INTO v_txt FROM {ROW} WHERE id = v_r1;")
    b += iff("v_m <> 1 OR v_txt IS DISTINCT FROM 'FAILED'", 'G-BIS: saída de PENDING sem a chave barrada (rows=%s persistence=%s)', 'v_m, v_txt')
    return b


def g8():
    b = PICK + job('v_job1', 'STAGED', '1') + job('v_job2', 'COMPLETED', '2')
    b += row('v_r1', 'v_job1', NULLKEY, 'VALID') + exists('v_r1', 'G8 row operacional com chave')
    b += row('v_r2', 'v_job2', NULLKEY, 'VALID', 'INSERTED') + exists('v_r2', 'G8 row terminal com chave')
    for v, where in (('v_r1', 'operacional'), ('v_r2', 'terminal')):
        b += neg(f"UPDATE {ROW} SET normalized_data = normalized_data - 'edition_context_profile_id' WHERE id = {v};",
                 RMV, f'G8 remoção da chave em row VALID ({where})')
        b += sql(f"SELECT count(*) INTO v_n FROM {ROW} WHERE id = {v} AND jsonb_exists(normalized_data, 'edition_context_profile_id');")
        b += iff('v_n <> 1', f'G8: chave ausente depois da recusa ({where})')
    return b


CASES = [
    ('G1', 'G1 [AUTO FX] STAGED · PENDING · NEEDS_REVIEW · chave ausente ⇒ permitido', g1()),
    ('G2', 'G2 [AUTO FX] STAGED · PENDING · VALID · ausente ⇒ CVIR_OPERATIONAL_VALID_REQUIRES_EDITION_CONTEXT_KEY', g2()),
    ('G3', 'G3 [AUTO FX] STAGED · PENDING · VALID · JSON null ⇒ permitido; UUID de profile existente ⇒ permitido', g3()),
    ('G4', 'G4 [AUTO FX] CONFIRMING, RECEIVED, PROCESSING · PENDING · VALID · ausente ⇒ mesmo código', g4()),
    ('G5', 'G5 [AUTO FX] COMPLETED, COMPLETED_WITH_ERRORS, FAILED · VALID · PENDING · ausente ⇒ permitido', g5()),
    ('G6', 'G6 [AUTO FX] CANCELLED · VALID · PENDING · ausente ⇒ permitido', g6()),
    ('G7', 'G7 [AUTO FX] CANCELLED→STAGED não barrado; 1ª escrita na row sem chave recusada; G-BIS no-lockout', g7()),
    ('G8', 'G8 [AUTO FX] remover a chave de row VALID ⇒ CVIR_EDITION_CONTEXT_KEY_REMOVAL_FORBIDDEN, inclusive em job terminal', g8()),
]

HEAD = header(['2830H · ENVELOPE E14 — SEÇÃO G (GUARD 2214 v3.1, G1–G8) · lote L12, 8 casos'], [
    'Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO, NÃO COMPILADO no',
    '                PostgreSQL (BATCH12 — INTEGRATED COMPLETION, baseline 945caa32).',
    '                Execução exige E00 + E14P gate_pass = true e mandato próprio.',
    'Contrato ...... 2830 v7.0 Seção G. Padrão: 2214 v3.1 PASSO 4 (Card/Variant Type',
    '                por ORDER BY id; aqui do Game real, via bloco PICK compartilhado).',
    'Negativos ..... P0001 + prefixo exato com dois-pontos (starts_with).',
    'Escrita (R4) .. job 1–3 por caso (G7: 1 UPDATE de status no job de fixture) ·',
    '                row: G1 1, G3 2, G5 3, G6 1, G7 1 + 1 UPDATE recusado + 1 UPDATE',
    '                permitido, G8 2 + 2 UPDATE recusados; G2 1 e G4 3 recusadas.',
    '                Nenhum DELETE. Tudo desfeito pelo término em exceção.',
    'P8 ............ SET LOCAL lock_timeout = \'5s\' + asserção (DP-4 = A).',
])


def e14():
    spec = dict(tag='h2830_e14', env='E14_SECAO_G_GUARD_2214', header=HEAD,
                decl=jr.PICK_DECL + [('v_job1', 'uuid', None), ('v_job2', 'uuid', None), ('v_r1', 'uuid', None), ('v_r2', 'uuid', None)],
                reset=['v_card', 'v_cs', 'v_vt', 'v_pp', 'v_ec', 'v_job1', 'v_job2', 'v_r1', 'v_r2'],
                cases=CASES)
    return envelope(spec)


PHEAD = header(['2830H · E14P — PRECHECK DO LOTE L12 (Seção G)'], [
    'Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO. SELECT único.',
    'Cobre ......... P7X (job/row), bloco JOB/ROW (tokens do guard, CHECKs, índices,',
    '                fixture, jobs em voo = 0), XBASELINE, marcador.',
])


def e14p():
    ctes = [pre.GS, pre.P7X, pre.XBASE, jr.JR_CTES]
    gates = pre.GS_GATE + '\n' + pre.P7X_GATES + '\n' + pre.XBASE_GATE + '\n' + pre.MK_GATE + '\n' + jr.JR_GATES
    det = pre.P7X_DETAIL + '\n' + pre.XBASE_DETAIL + '\n' + jr.JR_DETAIL + '\n' + pre.SESSION_DETAIL
    return pre.precheck(PHEAD, ctes, gates, det, 'e14p_precheck')
