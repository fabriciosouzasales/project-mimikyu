#!/usr/bin/env python3
"""
V1-13 · E1-E2 — varredura estática de colisões entre aliases SQL e variáveis PL/pgSQL.

Origem: G2_B LIVE STOP 12 / SQLSTATE 55000 (S.4 da 5863 v1.2-E1E): `from pg_policies p`
dentro de uma função que declara `p record`. Em PL/pgSQL, uma referência qualificada
`p.col` numa consulta embutida também casa com o campo `col` da variável record `p`; sem
`#variable_conflict use_column`, o PL/pgSQL tenta resolver a variável e falha
(55000 se `p` ainda não foi atribuída; 42703 se não tem o campo; 42702 se tem — ambígua).
Variável escalar NÃO é resolvida como `nome.campo` (só record/row), então não colide.

Não conecta em banco e não executa SQL. Lê os arquivos passados (ou, sem argumentos, os
quatro ensaios G2_B/G2_C) e lista, por corpo PL/pgSQL ($tag$…$tag$ com DECLARE):
arquivo, linha do alias, nome, tipo declarado, modo #variable_conflict, número de
referências qualificadas fora de literais e a classificação:

  DEFEITO   variável record/row + alias homônimo com referência qualificada, sem use_column
  NEUTRA    mesma situação, mas o corpo declara #variable_conflict use_column
  ESCALAR   variável escalar homônima do alias (não resolvida como nome.campo)
  REVISAR   tipo não reconhecido como escalar nem record (possível composto)

Uso:  python3 -I -B scan_alias_collisions.py [arquivo.sql ...]
Saída: código 0 se não houver DEFEITO nem REVISAR; 1 caso contrário.
"""
from __future__ import annotations

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT = ["G2_B_CHAIN_STORAGE_LAST_rollback.sql", "G2_B_CHAIN_STORAGE_LAST_rollback_MGMTAPI.sql",
           "G2_C_CHAIN_FULL_FINAL_rollback.sql", "G2_C_CHAIN_FULL_FINAL_rollback_MGMTAPI.sql"]

SCALAR = {"integer", "int", "int4", "int8", "bigint", "smallint", "numeric", "text", "varchar", "boolean",
          "bool", "uuid", "jsonb", "json", "oid", "name", "timestamptz", "timestamp", "date", "bytea",
          "regclass", "regprocedure", "double", "real", "char", "character", "interval", "xid8", "xid",
          "bit", "inet", "regrole", "regnamespace", "regtype", "tsvector"}
KW = {"on", "where", "and", "or", "join", "left", "inner", "right", "full", "cross", "select", "from",
      "as", "group", "order", "limit", "lateral", "using", "natural", "with", "set", "values", "not",
      "exists", "union", "except", "intersect", "having", "offset", "for", "into", "returning", "then",
      "else", "end", "loop", "when", "is", "in", "like", "between"}


def mask(code: str) -> str:
    """Troca comentários de linha e literais '...' por espaços (preserva posições/linhas)."""
    out, i, n = [], 0, len(code)
    while i < n:
        c = code[i]
        if c == "-" and code.startswith("--", i):
            j = code.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i)); i = j
        elif c == "'":
            j = i + 1
            while j < n:
                if code[j] == "'" and code.startswith("''", j):
                    j += 2; continue
                if code[j] == "'":
                    break
                j += 1
            seg = code[i:j + 1]
            out.append(re.sub(r"[^\n]", " ", seg)); i = j + 1
        else:
            out.append(c); i += 1
    return "".join(out)


def declared(body_m: str) -> dict[str, str]:
    vars_: dict[str, str] = {}
    for dm in re.finditer(r"(?is)\bdeclare\b(.*?)\bbegin\b", body_m):
        for d in dm.group(1).split(";"):
            mm = re.match(r"\s*([a-z_][a-z0-9_]*)\s+(?:constant\s+)?([a-z_][a-z0-9_.]*(?:%rowtype|%type)?)", d, re.I)
            if mm:
                vars_[mm.group(1).lower()] = mm.group(2).lower()
    return vars_


def aliases(body_m: str):
    pats = [
        r"\b(?:from|join)\s+(?:[a-z_][a-z0-9_]*\.)?[a-z_][a-z0-9_]*(?:\s*\([^()]*(?:\([^()]*\)[^()]*)*\))?\s+(?:as\s+)?([a-z_][a-z0-9_]*)",
        r",\s*(?:[a-z_][a-z0-9_]*\.)?[a-z_][a-z0-9_]*(?:\s*\([^()]*(?:\([^()]*\)[^()]*)*\))?\s+(?:as\s+)?([a-z_][a-z0-9_]*)\s*(?=\(|,|\bwhere\b|\bon\b|\bjoin\b|\))",
        r"\)\s+(?:as\s+)?([a-z_][a-z0-9_]*)\s*\(",
    ]
    for p in pats:
        for m in re.finditer(p, body_m, re.I):
            a = m.group(1).lower()
            if a not in KW:
                yield a, m.start(1)


def scan(path: str):
    text = open(path, encoding="utf-8").read()
    rows = []
    for m in re.finditer(r"\$([a-z_]*)\$(.*?)\$\1\$", text, re.S | re.I):
        body = m.group(2)
        bm = mask(body)
        if not re.search(r"(?i)\bdeclare\b", bm):
            continue
        mode = "use_column" if re.search(r"#variable_conflict\s+use_column", body) else (
            "use_variable" if re.search(r"#variable_conflict\s+use_variable", body) else "error (padrão)")
        vars_ = declared(bm)
        seen = {}
        for a, pos in aliases(bm):
            if a in vars_ and a not in seen:
                seen[a] = pos
        for a, pos in seen.items():
            typ = vars_[a]
            q = len(re.findall(r"(?<![a-z0-9_.])%s\.[a-z_]" % re.escape(a), bm, re.I))
            line = text.count("\n", 0, m.start(2) + pos) + 1
            if typ == "record" or typ.endswith("%rowtype"):
                cls = "NEUTRA" if mode == "use_column" else ("DEFEITO" if q else "SEM-REF")
            elif typ.split("%")[0].split("(")[0] in SCALAR or typ.endswith("%type"):
                cls = "ESCALAR"
            else:
                cls = "REVISAR"
            rows.append((os.path.basename(path), line, a, typ, mode, q, cls))
    return rows


def main(argv: list[str]) -> int:
    files = argv or [os.path.join(HERE, f) for f in DEFAULT]
    bad = 0
    for f in files:
        rows = scan(f)
        print(f"# {os.path.basename(f)}: {len(rows)} homônimo(s) alias/variável")
        for r in rows:
            print("  linha %d | alias/variável %s | tipo %s | #variable_conflict %s | refs qualificadas %d | %s" % r[1:])
            bad += r[6] in ("DEFEITO", "REVISAR")
    print("RESULTADO:", "SEM DEFEITO" if not bad else f"{bad} DEFEITO/REVISAR")
    return 0 if not bad else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
