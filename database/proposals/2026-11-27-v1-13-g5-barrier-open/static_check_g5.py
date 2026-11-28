"""V1-13 · Etapa 7 — verificação estática do pacote de abertura/fechamento da barreira (sem banco).

Emula as regras do executor v1.4 (Invoke-ReviewedSql.ps1) e confere o contrato da abertura e do fechamento.
Depois aplica mutações nos controles críticos: cada mutação precisa ser detectada.

Executar a partir desta pasta: python static_check_g5.py
"""
import hashlib
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
MD5_ASSERT = "e4f710904f50e6e8c3f1d8e2337639e0"
MD5_OPEN = "32e2f636361732b497e8401e50f0bbe0"
BANNED = r"(?i)\b(insert|update|delete|merge|drop|alter|create|grant|revoke|truncate|lock|comment|copy|call|do|execute|vacuum|analyze|refresh|reindex|cluster|set_config|nextval|setval|pg_terminate_backend|pg_cancel_backend|dblink)\b"


def strip_sql(s: str) -> str:
    s = re.sub(r"/\*[\s\S]*?\*/", " ", s)
    s = re.sub(r"--[^\r\n]*", " ", s)
    return s


def read_only_ok(s: str) -> bool:
    """Mesma regra do Test-ReadOnlySql do executor."""
    s = re.sub(r"'(?:[^']|'')*'", "''", strip_sql(s)).strip()
    if not re.match(r"(?i)^select\b", s):
        return False
    if s.count(";") != 1 or not s.endswith(";"):
        return False
    if "$" in s:
        return False
    return re.search(BANNED, s) is None


def keys(s: str) -> set:
    return set(re.findall(r"'([a-z_0-9]+)',\s", strip_sql(s)))


def load(files: dict) -> dict:
    return {name: (HERE / name).read_text(encoding="utf-8") for name in files}


FILES = [
    "G5_OPEN_PRE_readonly.sql", "G5_BARRIER_OPEN.sql", "G5_OPEN_POST_readonly.sql",
    "G5_CLOSE_PRE_readonly.sql", "G5_BARRIER_CLOSE.sql", "G5_CLOSE_POST_readonly.sql",
    "G5_OPEN_MANIFEST.txt", "G5_CLOSE_MANIFEST.txt",
]


def manifest_ok(text: str, expected: list, f: dict) -> bool:
    rows = [l for l in text.splitlines() if l and not l.startswith("#")]
    if len(rows) != len(expected):
        return False
    for i, (row, (name, mode)) in enumerate(zip(rows, expected), start=1):
        parts = row.split("|")
        if len(parts) != 4 or parts[0] != str(i) or not parts[1].endswith("\\" + name) or parts[3] != mode:
            return False
        if parts[2] != hashlib.sha256(f[name].encode("utf-8")).hexdigest():
            return False
    # Executor v1.4: gate antes da primeira escrita e gate depois da última.
    modes = [m for _, m in expected]
    return modes[0] == "gate" and modes[-1] == "gate" and "write" in modes


def checks(f: dict) -> list:
    op, ow, opo = f["G5_OPEN_PRE_readonly.sql"], strip_sql(f["G5_BARRIER_OPEN.sql"]), f["G5_OPEN_POST_readonly.sql"]
    cp, cw, cpo = f["G5_CLOSE_PRE_readonly.sql"], strip_sql(f["G5_BARRIER_CLOSE.sql"]), f["G5_CLOSE_POST_readonly.sql"]
    sets = re.findall(r"set\s+mode\s*=\s*'([A-Z]+)'", ow)
    csets = re.findall(r"set\s+mode\s*=\s*'([A-Z]+)'", cw)
    return [
        ("G01 gates são um SELECT só leitura (regra do executor)", all(read_only_ok(x) for x in (op, opo, cp, cpo))),
        ("G02 PRE da abertura exige barreira CLOSED e identidades 0 (chaves do executor)", {"barreira", "identidades_teste", "executor"} <= keys(op)),
        ("G03 POST da abertura sem 'barreira' e com 'modo_aberto' e 'identidades_teste'", "barreira" not in keys(opo) and {"modo_aberto", "identidades_teste", "executor"} <= keys(opo)),
        ("G04 PRE do fechamento não bloqueia (sem 'barreira' nem 'identidades_teste')", not ({"barreira", "identidades_teste"} & keys(cp)) and "executor" in keys(cp)),
        ("G05 POST do fechamento exige barreira CLOSED e identidades 0", {"barreira", "identidades_teste", "executor"} <= keys(cpo)),
        ("G06 abertura: uma única mudança de modo, para OPEN", sets == ["OPEN"]),
        ("G07 abertura: pré-condição CLOSED + registro vazio dentro da transação", re.search(r"is distinct from 'CLOSED'\s+or \(select count\(\*\) from public\.v1_13_barrier_identity\) <> 0", ow) is not None),
        ("G08 abertura: pós-condição OPEN + registro vazio", re.search(r"is distinct from 'OPEN'\s+or \(select count\(\*\) from public\.v1_13_barrier_identity\) <> 0", ow) is not None),
        ("G09 abertura: não registra identidade nem mexe em outra tabela", not re.search(r"(?i)\binsert\b|\bdelete\b|\balter\b|\bcreate\b|\bgrant\b|\bdrop\b", ow) and ow.count("update ") == 1),
        ("G10 abertura e fechamento em transação única (begin … commit)", all(re.search(r"(?s)^\s*begin;.*commit;\s*$", x) for x in (ow, cw))),
        ("G11 fechamento: CLOSED, registro esvaziado e pós-condição", csets == ["CLOSED"] and "delete from public.v1_13_barrier_identity" in cw and "is distinct from 'CLOSED'" in cw and "raise exception 'POSTCHECK G5-CLOSE" in cw),
        ("G12 funções da porta conferidas pelo md5 canônico (PRE, escrita, POSTs); escrita recusa md5 diferente", all(MD5_ASSERT in x and MD5_OPEN in x for x in (op, ow, opo, cpo)) and f"is distinct from '{MD5_ASSERT}'" in ow and f"is distinct from '{MD5_OPEN}'" in ow),
        ("G17 booleanos dos gates nunca nulos (coalesce)", all(x.count("coalesce(") >= 1 for x in (op, opo, cpo)) and "coalesce((select s.mode" in opo),
        ("G13 manifesto de abertura: PRE → escrita → POST com sha256 corretos", manifest_ok(f["G5_OPEN_MANIFEST.txt"], [("G5_OPEN_PRE_readonly.sql", "gate"), ("G5_BARRIER_OPEN.sql", "write"), ("G5_OPEN_POST_readonly.sql", "gate")], f)),
        ("G14 manifesto de fechamento: PRE → escrita → POST com sha256 corretos", manifest_ok(f["G5_CLOSE_MANIFEST.txt"], [("G5_CLOSE_PRE_readonly.sql", "gate"), ("G5_BARRIER_CLOSE.sql", "write"), ("G5_CLOSE_POST_readonly.sql", "gate")], f)),
        ("G15 PRE da abertura confere as entregas 5397 e 5398", {"entrega_5397_presente", "entrega_5398_presente"} <= keys(op)),
        ("G16 lock_timeout local nas escritas", all("set local lock_timeout" in x for x in (ow, cw))),
    ]


MUTATIONS = [
    ("abre para TEST em vez de OPEN", "G5_BARRIER_OPEN.sql", "set mode = 'OPEN'", "set mode = 'TEST'"),
    ("remove a pré-condição CLOSED", "G5_BARRIER_OPEN.sql", "is distinct from 'CLOSED'", "is distinct from 'OPEN'"),
    ("registra identidade na abertura", "G5_BARRIER_OPEN.sql", "update public.v1_13_barrier_state", "insert into public.v1_13_barrier_identity (user_id) select id from auth.users;\nupdate public.v1_13_barrier_state"),
    ("POST da abertura com chave 'barreira'", "G5_OPEN_POST_readonly.sql", "'modo_aberto',", "'barreira', 'x', 'modo_aberto',"),
    ("POST da abertura sem 'modo_aberto'", "G5_OPEN_POST_readonly.sql", "'modo_aberto',", "'modo_x',"),
    ("escrita dentro de um gate", "G5_OPEN_PRE_readonly.sql", "as g5_open_pre;", "as g5_open_pre; update public.v1_13_barrier_state set mode = 'OPEN';"),
    ("md5 da porta alterado", "G5_OPEN_PRE_readonly.sql", MD5_OPEN, "0" * 32),
    ("fechamento não esvazia o registro", "G5_BARRIER_CLOSE.sql", "delete from public.v1_13_barrier_identity;", ""),
    ("PRE do fechamento bloqueante (chave 'barreira')", "G5_CLOSE_PRE_readonly.sql", "'modo_atual',", "'barreira',"),
    ("arquivo alterado depois do manifesto", "G5_BARRIER_OPEN.sql", "commit;", "commit;\n-- alterado"),
    ("sem transação", "G5_BARRIER_OPEN.sql", "begin;", ""),
    ("abertura sem conferência final", "G5_BARRIER_OPEN.sql", "is distinct from 'OPEN'", "is distinct from 'CLOSED'"),
    ("fechamento sem conferência final", "G5_BARRIER_CLOSE.sql", "raise exception 'POSTCHECK G5-CLOSE", "raise notice 'POSTCHECK G5-CLOSE"),
    ("escrita aceita md5 diferente", "G5_BARRIER_OPEN.sql", "is distinct from '32e2f636361732b497e8401e50f0bbe0'", "= '32e2f636361732b497e8401e50f0bbe0'"),
    ("gate sem coalesce", "G5_OPEN_POST_readonly.sql", "coalesce((select s.mode", "((select s.mode"),
    ("PRE da abertura sem conferir a 5398", "G5_OPEN_PRE_readonly.sql", "'entrega_5398_presente',", "'entrega_x',"),
]


def main() -> int:
    f = load(FILES)
    results = checks(f)
    ok = 0
    for name, passed in results:
        print(("PASS " if passed else "FAIL ") + name)
        ok += passed
    print(f"\nSTATIC CHECK G5: {ok}/{len(results)} {'PASS' if ok == len(results) else 'FAIL'}")
    detected = 0
    for label, file, old, new in MUTATIONS:
        if old not in f[file]:
            print(f"MUTAÇÃO INVÁLIDA (trecho ausente): {label}")
            continue
        g = dict(f)
        g[file] = f[file].replace(old, new, 1)
        caught = not all(p for _, p in checks(g))
        detected += caught
        print(("DETECTADA " if caught else "NÃO DETECTADA ") + label)
    print(f"MUTAÇÕES: {detected}/{len(MUTATIONS)} detectadas")
    return 0 if ok == len(results) and detected == len(MUTATIONS) else 1


if __name__ == "__main__":
    sys.exit(main())
