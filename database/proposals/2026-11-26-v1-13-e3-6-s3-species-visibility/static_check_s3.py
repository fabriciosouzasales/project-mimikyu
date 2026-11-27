#!/usr/bin/env python3
"""
V1-13 · E3-6 / S3 — verificação ESTÁTICA da 5393, ROLLBACK_S3 e harness 5897.

Sem banco. Comprova só propriedades do TEXTO: forma da migration, assinatura e
retorno (11 colunas da 5316 + 4), STABLE/definer/search_path, porta 5389 antes de
tudo, autorização pela 5302 com P0002, núcleo 5315 numa única consulta, regra da
espécie só pelo estado mascarado, ausência de SQL dinâmico e de tabelas
patrimoniais na parte nova, constantes md5 do precheck iguais aos corpos
canônicos dos arquivos, reversão literal, cobertura do harness e que 5315/5316/5318
não foram tocadas. NÃO comprova compilação, comportamento, concorrência nem
desempenho.

    python3 -I -B database/proposals/2026-11-26-v1-13-e3-6-s3-species-visibility/static_check_s3.py
"""
from __future__ import annotations

import hashlib
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
SCHEMA = os.path.join(ROOT, "database", "schema")
G1 = os.path.join(ROOT, "database", "proposals", "2026-11-15-v1-13-e1e-security-evidence", "g1")
MIG = os.path.join(HERE, "5393_create_get_shared_collection_binder_pages_with_species.sql")
RB = os.path.join(HERE, "ROLLBACK_S3.sql")
HAR = os.path.join(HERE, "5897_validate_shared_binder_species_HARNESS.sql")
CONC = os.path.join(HERE, "5897_C_concurrency_LOCAL_TWO_SESSIONS.sql")
PERF = os.path.join(HERE, "5897_P_performance_LOCAL.sql")
FN = "get_shared_collection_binder_pages_with_species"

R: list[tuple[str, bool, str]] = []


def check(cid, ok, detail):
    R.append((cid, bool(ok), detail))


def rd(p):
    with open(p, encoding="utf-8") as fh:
        return fh.read()


def prosrc(text, fname):
    i = text.lower().index("function public." + fname + "(")
    m = re.search(r"\bas\s+(\$[A-Za-z0-9_]*\$)", text[i:], re.I)
    a = i + m.end()
    return text[a:text.index(m.group(1), a)]


def header(text, fname):
    i = text.lower().index("function public." + fname + "(")
    return text[i:i + re.search(r"\bas\s+\$", text[i:], re.I).start()]


def nc(t):
    t = re.sub(r"/\*.*?\*/", "", t, flags=re.S)
    return re.sub(r"--[^\n]*", "", t)


def md5(t):
    return hashlib.md5(t.encode("utf-8")).hexdigest()


mig = rd(MIG)
rb = rd(RB)
har = rd(HAR)
conc = rd(CONC)
perf = rd(PERF)
body = prosrc(mig, FN)
code = nc(body)
head = header(mig, FN).lower()

# 1. Forma da migration
check("M1", nc(mig).strip().lower().startswith("begin;") and nc(mig).strip().lower().endswith("commit;"), "uma transação: begin; … commit;")
check("M2", mig.count("create function public." + FN + "(") == 1 and "create or replace" not in nc(mig).lower(), "cria uma função nova (sem CREATE OR REPLACE)")
check("M3", re.search(r"language plpgsql\s+stable\s+security definer\s+set search_path = ''", head) is not None, "plpgsql STABLE SECURITY DEFINER, search_path vazio")
sig = re.search(r"\(\s*p_collection_id uuid,\s*p_first_page\s+integer,\s*p_page_count\s+integer\s*\)", head)
check("M4", sig is not None, "assinatura (uuid, integer, integer) com os nomes da 5316")
s16 = rd(os.path.join(SCHEMA, "5316_create_get_shared_collection_binder_pages_function.sql"))
cols16 = re.findall(r"^\s+([a-z_]+)\s+(INTEGER|TEXT)\b", re.split(r"RETURNS TABLE", header(s16, "get_shared_collection_binder_pages"), flags=re.I)[1], re.M)
cols93 = re.findall(r"^\s+([a-z_]+)\s+(integer|text|boolean)\b", head.split("returns table", 1)[1], re.M)
want = [(c.lower(), t.lower()) for c, t in cols16] + [("species_national_number", "integer"), ("species_name", "text"), ("species_artwork_path", "text"), ("references_visible", "boolean")]
check("M5", len(cols16) == 11 and cols93 == want, "retorno = as 11 colunas da 5316 (mesma ordem e tipos) + 4 novas")
check("M6", re.search(r"revoke all on function public\." + FN + r"\(uuid, integer, integer\) from public, anon;", mig) is not None
      and re.search(r"grant execute on function public\." + FN + r"\(uuid, integer, integer\) to authenticated;", mig) is not None
      and "service_role" not in nc(mig), "EXECUTE só authenticated; revogado de PUBLIC e anon")
check("M7", "has_function_privilege('anon', v_oid, 'EXECUTE') is not false" in mig and "proowner" in mig and "pg_get_function_result(v_oid)" in mig, "postcheck: definer, search_path, STABLE, dono = núcleo, grants, retorno exato")

# 2. Corpo
stmts = [s.strip() for s in code.split(";") if s.strip()]
first = next((s for s in stmts if not s.lower().startswith(("#variable_conflict", "declare", "v_role text", "begin"))), "")
check("B1", re.search(r"begin\s+perform public\.v1_13_assert_capability\(\)", code, re.I) is not None, "primeiro comando: porta 5389 (v1_13_assert_capability)")
check("B2", re.search(r"v_role := public\.collection_share_role\(p_collection_id\);\s*if v_role is null or v_role not in \('OWNER', 'VIEWER'\) then\s*raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';", code) is not None,
      "autorização pela 5302 ∈ {OWNER, VIEWER}, senão COLLECTION_NOT_FOUND (P0002), antes da leitura")
check("B3", code.lower().count("return query") == 1 and code.count("collection_binder_masked_pages(p_collection_id, p_first_page, p_page_count)") == 1,
      "uma única consulta de dados, com o núcleo 5315 chamado uma vez com os mesmos argumentos")
check("B4", not re.search(r"\bexecute\b", code, re.I) and "format(" not in code, "sem SQL dinâmico")
forbid = r"(slot_assignment|slot_image|layout_region|expected_content|physical_card|collection_allocation|storage_container|condition|inventory|price|valu|favorite|wishlist|email|username|grading|certif)"
check("B5", re.search(forbid, code, re.I) is None, "parte nova não lê exemplar, posição de exemplar, imagem, região, reserva, alocação, local, condição, valores")
check("B6", "m.pocket_state = 'EMPTY'" in code and "where lay.visible" in code and "r.collection_id = p_collection_id" in code and "l.collection_id = p_collection_id" in code,
      "espécie só com estado mascarado EMPTY, exibição ligada, referência de X e X proprietária")
check("B7", "c.completion_policy = 'REFERENCE_POSITION'" in code and "cr.reference_kind = 'POKEDEX'" in code and "c.mode = 'REFERENCE_BASED'" in code, "camada só para coleção Pokédex")
check("B8", re.search(r"coalesce\(\(select st\.references_visible[\s\S]*?\), true\)", code) is not None and "(select lay.visible from lay)" in code,
      "exibição: preferência do fichário (sem linha = true); NULL fora da camada")
sel = code[code.lower().index("select m.page_number"):code.lower().index("from m\n")]
check("B9", all(("m." + c) in sel for c, _ in want[:11]) and re.search(r"(slot_id|layout_id|collection_id|pokedex_position_id|species_id|card_id)\b", sel) is None,
      "as 11 colunas vêm do núcleo sem transformação; nenhum id na projeção")
check("B10", code.strip().endswith("order by m.page_number, m.row_index, m.column_index;\nend;") or re.search(r"order by m\.page_number, m\.row_index, m\.column_index;\s*end;\s*$", code) is not None,
      "ordem página → linha → coluna (a da 5316)")
check("B11", re.search(r"\b(volatile|pg_sleep|now\(\)|clock_timestamp|random\(|nextval)\b", code, re.I) is None, "C1: nenhuma chamada volátil no corpo")

# 3. Constantes do precheck/postcheck = corpos canônicos dos arquivos
canon = {
    "collection_share_role": md5(prosrc(rd(os.path.join(SCHEMA, "5302_create_collection_share_role_function.sql")), "collection_share_role")),
    "collection_binder_masked_pages": md5(prosrc(rd(os.path.join(SCHEMA, "5315_create_collection_binder_masked_pages_function.sql")), "collection_binder_masked_pages")),
    "get_shared_collection_binder_pages": md5(prosrc(s16, "get_shared_collection_binder_pages")),
    "get_public_collection_binder_pages": md5(prosrc(rd(os.path.join(SCHEMA, "5318_create_get_public_collection_binder_pages_function.sql")), "get_public_collection_binder_pages")),
    "v1_13_assert_capability": md5(prosrc(rd(os.path.join(G1, "5389_create_v1_13_capability_barrier.sql")), "v1_13_assert_capability")),
    "v1_13_capability_open": md5(prosrc(rd(os.path.join(G1, "5389_create_v1_13_capability_barrier.sql")), "v1_13_capability_open")),
}
ok_md5 = True
for fname, h in canon.items():
    pat = re.compile(r"to_regprocedure\('public\." + fname + r"\([^)]*\)'\)\)\s*is distinct from '([0-9a-f]{32})'")
    found = pat.findall(mig)
    if not found or any(f != h for f in found):
        ok_md5 = False
check("C1", ok_md5, "md5 do precheck/postcheck = prosrc dos arquivos canônicos (5302, 5315, 5316, 5318, 5389 ×2): " + ", ".join(f"{k}={v[:8]}" for k, v in canon.items()))
check("C2", "provolatile not in ('s', 'i')" in mig and "to_regprocedure('auth.uid()')" in mig, "precheck C1: dependências STABLE/IMMUTABLE e auth.uid() presente")
for name, fn in [("5302", "5302_create_collection_share_role_function.sql"), ("5315", "5315_create_collection_binder_masked_pages_function.sql")]:
    t = rd(os.path.join(SCHEMA, fn))
    check("C3." + name, re.search(r"LANGUAGE (sql|plpgsql)\s+STABLE", t, re.I) is not None, f"{name} declarada STABLE no arquivo canônico")

# 4. Arquivos da V1-12 não tocados
try:
    out = subprocess.run(["git", "-C", ROOT, "status", "--porcelain", "--",
                          "database/schema/5315_create_collection_binder_masked_pages_function.sql",
                          "database/schema/5316_create_get_shared_collection_binder_pages_function.sql",
                          "database/schema/5318_create_get_public_collection_binder_pages_function.sql",
                          "database/schema/5302_create_collection_share_role_function.sql"],
                         capture_output=True, text=True, check=True).stdout.strip()
    check("V1", out == "", "5302/5315/5316/5318 sem alteração no repositório")
except Exception as exc:  # noqa: BLE001
    check("V1", False, f"git indisponível: {exc}")

# 5. Reversão
check("R1", re.search(r"drop function if exists public\." + FN + r"\(uuid, integer, integer\);", rb) is not None and nc(rb).count("drop ") == 1,
      "ROLLBACK_S3: só o drop da 5393 (assinatura exata)")
check("R2", all(canon[k] in rb for k in ("collection_binder_masked_pages", "get_shared_collection_binder_pages", "get_public_collection_binder_pages")), "rollback confere 5315/5316/5318 canônicas depois")

# 6. Harness
ids = re.findall(r"jsonb_build_object\('id','([0-9X.F]+)'", har)
need = ["0.1", "0.2", "0.3", "0.4", "F.2"] + [f"1.{i}" for i in range(1, 11)] + ["2.1", "3.1"] + [f"4.{i}" for i in range(1, 7)] + ["5.1"]
check("H1", all(i in ids for i in need) and len([i for i in ids if i in need]) == 24 and "esperado 24/24" in har, "harness: 24 verificações (estrutura, matriz, regressão, A–E, entre consultas, controles, reversão)")
check("H2", "begin;" not in nc(har).lower() and "commit" not in nc(har).lower(), "harness sem BEGIN/COMMIT próprios (transação revertida pelo operador)")
for tag, txt in [("B ", "values (s_t, pc_y)"), ("B′", "values (s_t, pc_free)"), ("C ", "collection_layout_slot_image (slot_id"), ("D ", "collection_layout_region (page_id"), ("E ", "values (s_t, k1, k1s, c_y)")]:
    check("H3." + tag.strip(), txt in har, f"cenário {tag.strip()} montado no bolso-alvo")
check("H4", "wh5897c_stable" in conc and "language plpgsql stable" in conc and "wh5897c_volatile" in conc and "language plpgsql volatile" in conc and "pg_sleep(8)" in conc,
      "concorrência: ajudantes STABLE e VOLATILE só do ensaio, com pausa para a outra sessão")
check("H5", "explain (analyze, buffers, timing)" in perf and "≤ 2 ×" in perf, "desempenho: medição separada (5316 × 5393), critérios declarados")
live = re.compile(r"qjfutqujxrbzgrtkpgkg|supabase\.co|service_role", re.I)
check("H6", not any(live.search(nc(x)) for x in (mig, rb, har, conc, perf)), "nenhuma referência ao projeto LIVE, URL ou service_role nos artefatos")

fails = [r for r in R if not r[1]]
for cid, ok, detail in R:
    print(f"{'PASS' if ok else 'FAIL'}  {cid:7} {detail}")
print(f"\nSTATIC CHECK S3: {len(R) - len(fails)}/{len(R)} PASS" + ("" if not fails else f" — {len(fails)} FAIL"))
sys.exit(1 if fails else 0)
