#!/usr/bin/env python3
"""Verificação estática das migrations 5257–5260 (POKEDEX-BINDER-SPECIES-REFERENCE).

Não conecta em banco. Uso (a partir da raiz do repositório):
    python3 database/proposals/2026-10-24-pokedex-binder-species-reference/static_check_species_reference.py

Regras:
  S1  cada migration tem exatamente um BEGIN; e um COMMIT; (fora de comentários)
      e nenhum ROLLBACK;
  S2  toda função criada é SECURITY DEFINER com SET search_path = ''
  S3  toda função criada tem REVOKE de PUBLIC; RPCs públicas só GRANT a authenticated;
      helpers e função de gatilho sem GRANT
  S4  nenhuma migration canônica existente (database/schema) cita as tabelas novas
      — nenhuma função existente lê ou escreve referências (D1: vão, mover,
      imagens, mesclagens e montagem ficam intactos)
  S5  a única função existente substituída é remove_layout_page(uuid)
  S6  5260: o corpo de 2 argumentos preserva, na mesma ordem, todos os passos
      executáveis da 5235 (só acrescenta o bloco 5b)
  S7  o harness 5857 declara o mesmo total esperado que o número de checagens
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
MIGRATIONS = sorted(HERE.glob("525[7-9]_*.sql")) + sorted(HERE.glob("5260_*.sql"))
NEW_TABLES = ("collection_layout_slot_species_reference", "collection_layout_species_reference_setting")
PUBLIC_RPCS = {
    "preview_my_binder_species_references",
    "apply_my_binder_species_references",
    "set_my_binder_species_reference_visibility",
    "clear_my_binder_species_references",
    "get_my_binder_species_reference_state",
    "get_my_collection_binder_species_references",
    "remove_layout_page",
}
INTERNAL = {
    "binder_species_reference_target",
    "binder_species_reference_plan",
    "enforce_collection_layout_slot_species_reference_integrity",
}

failures: list[str] = []


def strip_comments(sql: str) -> str:
    sql = re.sub(r"/\*.*?\*/", "", sql, flags=re.S)
    return re.sub(r"--[^\n]*", "", sql)


def strip_bodies(sql: str) -> str:
    return re.sub(r"\$(\w*)\$.*?\$\1\$", "$$", sql, flags=re.S)


def check(rule: str, ok: bool, detail: str) -> None:
    print(f"{'PASS' if ok else 'FAIL'}  {rule}  {detail}")
    if not ok:
        failures.append(f"{rule}: {detail}")


if len(MIGRATIONS) != 4:
    check("S0", False, f"esperadas 4 migrations, encontradas {len(MIGRATIONS)}")

created: dict[str, str] = {}
for path in MIGRATIONS:
    raw = path.read_text(encoding="utf-8")
    code = strip_bodies(strip_comments(raw))
    begins = len(re.findall(r"^\s*begin\s*;", code, flags=re.I | re.M))
    commits = len(re.findall(r"^\s*commit\s*;", code, flags=re.I | re.M))
    rollbacks = len(re.findall(r"\brollback\s*;", code, flags=re.I))
    check("S1", begins == 1 and commits == 1 and rollbacks == 0, f"{path.name}: begin={begins} commit={commits} rollback={rollbacks}")

    no_comments = strip_comments(raw)
    for m in re.finditer(r"create\s+(?:or\s+replace\s+)?function\s+public\.(\w+)\s*\((.*?)\)\s*returns(.*?)\$\$", no_comments, flags=re.I | re.S):
        name, header = m.group(1), m.group(3)
        args = re.sub(r"\s+", " ", m.group(2).strip())
        key = f"{name}({args})"
        created[key] = path.name
        ok_def = re.search(r"security\s+definer", header, flags=re.I) is not None
        ok_sp = re.search(r"set\s+search_path\s*=\s*''", header, flags=re.I) is not None
        check("S2", ok_def and ok_sp, f"{path.name}: {name} definer={ok_def} search_path_vazio={ok_sp}")
        revoked = re.search(rf"revoke\s+(?:all|execute)\s+on\s+function\s+public\.{name}\b[^;]*from\s+public", no_comments, flags=re.I)
        granted = re.search(rf"grant\s+execute\s+on\s+function\s+public\.{name}\b[^;]*to\s+(\w+)", no_comments, flags=re.I)
        if name in PUBLIC_RPCS:
            check("S3", bool(revoked) and bool(granted) and granted.group(1).lower() == "authenticated",
                  f"{path.name}: {name} revoke PUBLIC e grant só authenticated")
        elif name in INTERNAL:
            check("S3", bool(revoked) and not granted, f"{path.name}: {name} interno sem grant")
        else:
            check("S3", False, f"{path.name}: função não classificada {name}")

schema_dir = ROOT / "database" / "schema"
hits = [p.name for p in schema_dir.glob("*.sql") if any(t in p.read_text(encoding="utf-8", errors="ignore") for t in NEW_TABLES)]
check("S4", not hits, f"migrations canônicas que citam as tabelas novas: {hits or 'nenhuma'}")

existing = set()
for p in schema_dir.glob("*.sql"):
    txt = strip_comments(p.read_text(encoding="utf-8", errors="ignore"))
    existing.update(m.group(1) for m in re.finditer(r"create\s+(?:or\s+replace\s+)?function\s+public\.(\w+)", txt, flags=re.I))
replaced = sorted({k.split("(")[0] for k in created} & existing)
check("S5", replaced == ["remove_layout_page"], f"funções existentes substituídas/sobrecarregadas: {replaced}")


def body_of(sql: str, signature_regex: str) -> str:
    m = re.search(signature_regex + r".*?AS\s+\$\$(.*?)\$\$", sql, flags=re.I | re.S)
    return m.group(1) if m else ""


def statements(body: str) -> list[str]:
    body = strip_comments(body)
    return [re.sub(r"\s+", " ", s).strip().lower() for s in body.split(";") if s.strip()]


src_5235 = (schema_dir / "5235_update_remove_layout_page_for_custom_images.sql").read_text(encoding="utf-8")
src_5260 = next(HERE.glob("5260_*.sql")).read_text(encoding="utf-8")
old = statements(body_of(src_5235, r"FUNCTION\s+public\.remove_layout_page\(\s*p_page_id\s+UUID\s*\)"))
new = statements(body_of(src_5260, r"CREATE\s+FUNCTION\s+public\.remove_layout_page\(\s*p_page_id\s+UUID\s*,"))
it = iter(new)
missing = [s for s in old if not any(s == n for n in it)]
check("S6", bool(old) and not missing, f"5235: {len(old)} instruções preservadas em ordem na 5260 (faltando {len(missing)})")

harness = next(HERE.glob("5857_*.sql")).read_text(encoding="utf-8")
ids = re.findall(r"jsonb_build_object\('id','([0-9A-Z.]+)'", harness)
real = sorted({i for i in ids if not i.startswith("X.")})
expected = int(re.search(r"v_expected integer := (\d+);", harness).group(1))
check("S7", len(real) == expected, f"harness: {len(real)} checagens distintas, esperado declarado {expected}")

print()
print("RESULTADO:", "PASS" if not failures else f"FAIL ({len(failures)})")
sys.exit(1 if failures else 0)
