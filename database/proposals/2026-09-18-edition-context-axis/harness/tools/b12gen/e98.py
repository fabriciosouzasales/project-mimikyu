# E98 — postcheck de resíduo ESTENDIDO (complementa o E99; não o substitui).
# Compara o XBASELINE capturado pelo precheck do lote (d_xbaseline /
# d_xbaseline_md5) com o estado de agora. Bloco XBASELINE-BUILDER idêntico ao
# de pre.XBASE (verificado pelo static_check).
from lib import header
import pre

HEAD = header(['2830H · E98 — POSTCHECK DE RESÍDUO ESTENDIDO (game, datas de criação, marcador nos campos de fixture)'], [
    'Status ........ IMPLEMENTADO LOCALMENTE — NÃO EXECUTADO. Somente SELECT, um statement.',
    'Uso ........... statement SEPARADO, logo DEPOIS do E99 (S6b), nos lotes que escrevem',
    '                fora das 3 tabelas EC: L5 (game), L6 (card_variant), L7/L11/L12',
    '                (job/row). Opcional nos demais (sem efeito se nada foi escrito).',
    '',
    'ANTES DE RODAR, o operador substitui EXATAMENTE DOIS marcadores, copiando da',
    'saída registrada do precheck DO LOTE da MESMA RODADA (colar, nunca redigitar):',
    '  __XP_D_XBASELINE__      ← o valor integral de d_xbaseline (JSON)',
    '  __XP_D_XBASELINE_MD5__  ← o valor de d_xbaseline_md5',
    'Marcador não substituído, JSON truncado ou alterado ⇒ gate falso.',
    '',
    'O md5 prova FIDELIDADE DA CÓPIA, não a origem da rodada; a vinculação',
    'precheck → envelope → E99 → E98 é documental, como no E99.',
    '',
    'Gates: g_captured_present · g_captured_integrity · g_keys_identical ·',
    '       g_xbaseline_equal (todas as chaves, uma a uma; d_diff) · g_xmarker_absent.',
])

BODY = """WITH
captured_raw AS (
    SELECT '__XP_D_XBASELINE__'::text     AS x_text,
           '__XP_D_XBASELINE_MD5__'::text AS x_md5
),
captured AS (
    SELECT CASE WHEN x_text LIKE '\\_\\_XP%' THEN NULL ELSE x_text::jsonb END AS c,
           CASE WHEN x_md5  LIKE '\\_\\_XP%' THEN NULL ELSE x_md5 END        AS md5_declared
      FROM captured_raw
),
""" + pre.XBASE.rstrip(',') + """,
diff AS (
    SELECT k AS key, captured.c -> k AS captured, xbase.x -> k AS now
      FROM captured, xbase, jsonb_object_keys(xbase.x) AS k
     WHERE captured.c IS NOT NULL AND (captured.c -> k) IS DISTINCT FROM (xbase.x -> k)
),
gates AS (
    SELECT
        ((SELECT c FROM captured) IS NOT NULL AND (SELECT md5_declared FROM captured) IS NOT NULL) AS g_captured_present,
        (SELECT md5(c::text) = md5_declared FROM captured)                                         AS g_captured_integrity,
        ((SELECT array_agg(k ORDER BY k) FROM captured, jsonb_object_keys(captured.c) AS k)
          = (SELECT array_agg(k ORDER BY k) FROM xbase, jsonb_object_keys(xbase.x) AS k))          AS g_keys_identical,
        ((SELECT c FROM captured) IS NOT NULL AND NOT EXISTS (SELECT 1 FROM diff))                  AS g_xbaseline_equal,
""" + pre.XBASE_GATE.rstrip(',') + """
)
SELECT to_jsonb(g)
    || jsonb_build_object(
        'gate_pass', (SELECT bool_and(v::boolean) FROM jsonb_each_text(to_jsonb(g)) AS e(k, v))
                     AND NOT EXISTS (SELECT 1 FROM jsonb_each_text(to_jsonb(g)) AS e(k, v) WHERE v IS NULL),
        'd_diff',             COALESCE((SELECT jsonb_agg(to_jsonb(d) ORDER BY d.key) FROM diff d), '[]'::jsonb),
        'd_xbaseline_now',    (SELECT x FROM xbase),
        'd_xbaseline_now_md5',(SELECT md5(x::text) FROM xbase),
        'd_session', jsonb_build_object('backend_pid', pg_backend_pid(), 'checked_at', clock_timestamp())
    ) AS e98_postcheck
  FROM gates g;
"""


def e98():
    return HEAD + BODY
