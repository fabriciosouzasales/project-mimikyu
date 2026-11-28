#!/usr/bin/env python3
"""V1-13 · E4 — verificação estática dos artefatos de ativação/encerramento do TEST (com testes de mutação).

Executar: python3 static_check_e4.py   (a partir desta pasta). Nada se conecta ao banco.
"""
import hashlib
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import build_e4 as B  # noqa: E402

KW = re.compile(r"(?i)\b(insert|update|delete|merge|drop|alter|create|grant|revoke|truncate|lock|comment|copy|call|do|execute|vacuum|analyze|refresh|reindex|cluster|set_config|nextval|setval|pg_terminate_backend|pg_cancel_backend|dblink)\b")


def read_only_ok(sql: str) -> bool:
    """Emulação do Test-ReadOnlySql do executor v1.4."""
    s = re.sub(r"/\*[\s\S]*?\*/", " ", sql)
    s = re.sub(r"--[^\r\n]*", " ", s)
    s = re.sub(r"'(?:[^']|'')*'", "''", s).strip()
    return bool(re.match(r"(?i)^select\b", s)) and s.count(";") == 1 and s.endswith(";") and "$" not in s and not KW.search(s)


def keys_of(gate: str) -> list[str]:
    return re.findall(r"^  '([a-z_0-9]+)',", gate, re.M)


def writes_of(sql: str) -> list[str]:
    body = re.sub(r"\$(pre|post)\$[\s\S]*?\$\1\$", "", sql)
    body = re.sub(r"/\*[\s\S]*?\*/", "", body)
    return re.findall(r"(?i)\b(insert\s+into|update|delete\s+from)\s+(public\.[a-z_0-9]+)", body)


def checks(a: dict) -> list[tuple[str, bool, str]]:
    R = []
    ck = lambda i, ok, d: R.append((i, bool(ok), d))
    ck("U1", bool(B.CONTAS) and B.LIST == ", ".join(f"'{B.CONTAS[r]}'" for r in B.ROLES)
       and not re.search(r"(?i)username in \(|username = '", "".join(a[n] for n in a if n.endswith(".sql"))),
       "conjunto E4 configurado: 4 contas distintas (T, E, E2, V) só por md5 do username; nenhum username no repositório")
    for n in ("E4_OPEN_PRE_readonly.sql", "E4_OPEN_POST_readonly.sql", "E4_CLOSE_POST_readonly.sql", "E4_TEST_OPEN.sql"):
        lists = re.findall(r"md5\(up\.username\) in \(([^)]*)\)", a[n])
        ck("U2", lists and all(x == B.LIST for x in lists), f"{n}: toda lista de contas é exatamente a do conjunto E4")
    for n in ("E4_OPEN_PRE_readonly.sql", "E4_OPEN_POST_readonly.sql", "E4_CLOSE_PRE_readonly.sql", "E4_CLOSE_POST_readonly.sql"):
        ck("K1", read_only_ok(a[n]), f"{n}: SELECT único sem escrita (validador do executor)")
    pre, post, cpost = (keys_of(a[n]) for n in ("E4_OPEN_PRE_readonly.sql", "E4_OPEN_POST_readonly.sql", "E4_CLOSE_POST_readonly.sql"))
    iso = set(B.ISOLATION)
    ck("K2", {"executor", "barreira", "identidades_teste", "funcoes_barreira_canonicas", "eventos_editor_externos_n"} <= set(pre) and iso <= set(pre),
       "PRE da abertura: barreira CLOSED, 0 identidades, porta canônica, isolamento completo")
    ck("K3", "barreira" not in post and "identidades_teste" not in post and {"modo_teste", "registro_igual_contas", "executor"} <= set(post)
       and (iso <= set(post)), "POST da abertura: TEST e registro por booleanos próprios; isolamento")
    ck("K4", {"executor", "barreira", "identidades_teste", "funcoes_barreira_canonicas", "eventos_editor_externos_n"} <= set(cpost)
       and (iso - {"contas_conjunto_4", "titular_com_colecoes"}) <= set(cpost), "POST do encerramento: CLOSED, 0 identidades, isolamento")
    fps = {k for k, _ in B.FINGERPRINTS}
    base = {k for k, _ in B.BASELINE}
    ck("B1", fps <= set(pre) and fps <= set(cpost) and base <= set(pre) and not (base & set(cpost)) and {"alocacoes_fp", "exemplares_fp", "condicao_fp"} <= fps,
       "estado anterior do titular no PRE da abertura; impressões digitais (patrimônio incluído) no PRE da abertura e no POST do encerramento")
    ck("B2", set(B.INFO) <= set(pre) and all(k.endswith("_n") for k in B.INFO) and not (set(B.INFO) & iso),
       "admin e compartilhamentos V1-12 do conjunto são informativos (contas reais), nunca critério de acesso")
    ck("K5", not any(k.startswith("escritores_") or k.endswith("_md5") for k in pre + post + cpost), "sem chaves de inventário/md5 do executor")
    ck("K6", all(B.MD5_ASSERT in a[n] and B.MD5_OPEN in a[n] for n in ("E4_OPEN_PRE_readonly.sql", "E4_OPEN_POST_readonly.sql", "E4_CLOSE_POST_readonly.sql", "E4_TEST_OPEN.sql")),
       "md5 canônicos da porta (5389) nos gates e no precheck")
    cpre = a["E4_CLOSE_PRE_readonly.sql"]
    ck("K7", keys_of(cpre) == ["executor", "estado_barreira_presente", "modo_atual", "identidades_n", "identidades_fora_do_conjunto_n", "eventos_editor_externos_n"]
       and len(re.findall(r"= 4|= 'TEST'|not exists|<> 0|= 0", re.sub(r"/\*[\s\S]*?\*/", "", cpre))) == 0,
       "PRE do encerramento: só registra (modo, registro, eventos); único critério = linha de estado; nada que impeça fechar")
    lists = re.findall(r"md5\(up\.username\) in \(([^)]*)\)", cpre)
    ck("U3", lists and all(x == B.LIST for x in lists), "PRE do encerramento: mesma lista do conjunto E4")
    o, c = a["E4_TEST_OPEN.sql"], a["E4_TEST_CLOSE.sql"]
    ck("W1", sorted((w.split()[0].lower(), t) for w, t in writes_of(o)) == [("insert", "public.v1_13_barrier_identity"), ("update", "public.v1_13_barrier_state")],
       "abertura escreve só o registro e o estado da barreira")
    ck("W2", re.search(r"set mode = 'TEST'", o) and "'OPEN'" not in o and re.search(r"insert into public\.v1_13_barrier_identity \(user_id, note\)\nselect up\.id, 'E4: conjunto de homologação'\nfrom public\.user_profile up\nwhere md5\(up\.username\) in \(" + re.escape(B.LIST) + r"\);", o)
       and o.count("begin;") == 1 and o.count("commit;") == 1, "abertura: só TEST (nunca OPEN), só as 4 contas, transação única")
    ck("W3", re.search(r"is distinct from 'CLOSED'\s+or \(select count\(\*\) from public\.v1_13_barrier_identity\) <> 0", o)
       and "lifecycle_status = 'ACTIVE'" in o and "collection_activity_event" in o and "m.role = 'EDITOR'" in o and "public.admin_user" not in o,
       "abertura exige CLOSED vazio, conjunto completo, titular com coleções e isolamento de EDITOR/auditoria antes de escrever")
    ck("W4", sorted((w.split()[0].lower(), t) for w, t in writes_of(c)) == [("delete", "public.v1_13_barrier_identity"), ("update", "public.v1_13_barrier_state")]
       and re.search(r"set mode = 'CLOSED'", c) and "'TEST'" not in c and "'OPEN'" not in c and "$pre$" not in c
       and re.search(r"delete from public\.v1_13_barrier_identity;", c), "encerramento: CLOSED e registro vazio, sem pré-condição que impeça fechar")
    ck("W5", all(re.search(r"\$post\$[\s\S]*raise exception[\s\S]*\$post\$", x) for x in (o, c)), "pós-verificação interna nas duas escritas")
    live = re.compile(r"qjfutqujxrbzgrtkpgkg|supabase\.co|eyJ|sbp_|@[a-z0-9.-]+\.[a-z]{2,}|[A-Za-z]:\\\\Users", re.I)
    ck("X1", not any(live.search(re.sub(r"(?m)^#.*$", "", a[n])) for n in a if n.endswith((".sql", ".txt"))), "sem projeto, URL, e-mail, credencial ou caminho privado")
    for m, steps in (("E4_OPEN_MANIFEST.txt", [("E4_OPEN_PRE_readonly.sql", "gate"), ("E4_TEST_OPEN.sql", "write"), ("E4_OPEN_POST_readonly.sql", "gate")]),
                     ("E4_CLOSE_MANIFEST.txt", [("E4_CLOSE_PRE_readonly.sql", "gate"), ("E4_TEST_CLOSE.sql", "write"), ("E4_CLOSE_POST_readonly.sql", "gate")])):
        rows = [l.split("|") for l in a[m].splitlines() if l and not l.startswith("#")]
        ok = [(r[1].split("\\")[-1], r[3]) for r in rows] == steps and all(
            r[2] == hashlib.sha256(a[r[1].split("\\")[-1]].encode()).hexdigest() and r[1].startswith(B.PKG + "\\") for r in rows)
        ck("X2", ok, f"{m}: passos, modos e sha256 dos arquivos")
        # Regra do executor v1.4 (Invoke-ReviewedSql.ps1): toda escrita precisa de um gate (PRE) antes.
        modes = [r[3] for r in rows]
        ck("X3", "write" in modes and "gate" in modes[: modes.index("write")], f"{m}: gate antes da primeira escrita (regra do executor v1.4)")
    return R


def load() -> dict:
    return {p.name: p.read_text(encoding="utf-8") for p in HERE.iterdir() if p.suffix in (".sql", ".txt")}


MUTATIONS = [
    ("abertura usa OPEN", "E4_TEST_OPEN.sql", "set mode = 'TEST'", "set mode = 'OPEN'", "W2"),
    ("abertura registra todos os perfis", "E4_TEST_OPEN.sql", f"from public.user_profile up\nwhere md5(up.username) in ({B.LIST});", "from public.user_profile up;", "W2"),
    ("abertura escreve outra tabela", "E4_TEST_OPEN.sql", "\ndo $post$", "\nupdate public.collection set name = name where false;\n\ndo $post$", "W1"),
    ("abertura sem exigir CLOSED", "E4_TEST_OPEN.sql", "is distinct from 'CLOSED'", "is distinct from 'TEST'", "W3"),
    ("abertura sem exigir titular com coleções", "E4_TEST_OPEN.sql", "lifecycle_status = 'ACTIVE'", "lifecycle_status is not null", "W3"),
    ("abertura sem isolamento de EDITOR", "E4_TEST_OPEN.sql", "m.role = 'EDITOR'", "m.role = 'VIEWER'", "W3"),
    ("encerramento sem esvaziar o registro", "E4_TEST_CLOSE.sql", "delete from public.v1_13_barrier_identity;", "", "W4"),
    ("encerramento volta para TEST", "E4_TEST_CLOSE.sql", "set mode = 'CLOSED'", "set mode = 'TEST'", "W4"),
    ("encerramento com pré-condição", "E4_TEST_CLOSE.sql", "begin;\n", "begin;\ndo $pre$ begin if false then raise exception 'x'; end if; end; $pre$;\n", "W4"),
    ("POST da abertura com chave barreira", "E4_OPEN_POST_readonly.sql", "'modo_teste',", "'barreira',", "K3"),
    ("POST do encerramento sem identidades", "E4_CLOSE_POST_readonly.sql", "'identidades_teste',", "'identidades_n',", "K4"),
    ("PRE sem isolamento de EDITOR", "E4_OPEN_PRE_readonly.sql", "'sem_editor_fora_do_conjunto',", "'sem_editor',", "K2"),
    ("POST do encerramento sem impressão do patrimônio", "E4_CLOSE_POST_readonly.sql", "'alocacoes_fp',", "'alocacoes',", "B1"),
    ("admin vira critério bloqueante", "E4_OPEN_PRE_readonly.sql", "'admins_no_conjunto_n',", "'admins_no_conjunto',", "B2"),
    ("username em texto no artefato", "E4_TEST_OPEN.sql", "where md5(up.username) in (", "where up.username in ('alguem') or md5(up.username) in (", "U1"),
    ("gate com escrita", "E4_CLOSE_POST_readonly.sql", "select jsonb_build_object(", "select jsonb_build_object( 'x', (select nextval('s')),", "K1"),
    ("lista de contas divergente", "E4_OPEN_POST_readonly.sql", B.LIST, B.LIST.replace(B.CONTAS.get("V", "x"), "0" * 32), "U2"),
    ("md5 da porta alterado", "E4_OPEN_PRE_readonly.sql", B.MD5_OPEN, "0" * 32, "K6"),
    ("manifesto com hash errado", "E4_CLOSE_MANIFEST.txt", "|write", "0|write", "X2"),
    ("manifesto CLOSE sem PRE (passo 1 deixa de ser gate)", "E4_CLOSE_MANIFEST.txt", "|gate\n2|", "|read\n2|", "X3"),
    ("PRE do encerramento com chave barreira", "E4_CLOSE_PRE_readonly.sql", "'modo_atual',", "'barreira',", "K7"),
    ("PRE do encerramento bloqueia fora do TEST", "E4_CLOSE_PRE_readonly.sql", "(select s.mode from public.v1_13_barrier_state s where s.id = 1),\n", "(select s.mode from public.v1_13_barrier_state s where s.id = 1) = 'TEST',\n", "K7"),
    ("PRE do encerramento exige registro de 4", "E4_CLOSE_PRE_readonly.sql", "(select count(*) from public.v1_13_barrier_identity),\n", "(select count(*) from public.v1_13_barrier_identity) = 4,\n", "K7"),
    ("e-mail no artefato", "E4_TEST_OPEN.sql", "Reversão....:", "Contato....: alguem@exemplo.com\nReversão....:", "X1"),
]


def main() -> int:
    a = load()
    res = checks(a)
    for i, ok, d in res:
        print(f"{'PASS' if ok else 'FAIL'}  {i:<4} {d}")
    killed = 0
    lines = []
    for name, f, old, new, target in MUTATIONS:
        m = dict(a)
        assert m[f].count(old) >= 1, (name, old)
        m[f] = m[f].replace(old, new, 1)
        dead = any(i == target and not ok for i, ok, _ in checks(m))
        killed += dead
        lines.append(f"      {'morta' if dead else 'VIVA '}  [{target}] {name}")
    mut_ok = killed == len(MUTATIONS)
    print(f"{'PASS' if mut_ok else 'FAIL'}  MUT  {killed}/{len(MUTATIONS)} mutações reprovadas pelo controle-alvo")
    print("\n".join(lines))
    total = len(res) + 1
    passed = sum(ok for _, ok, _ in res) + mut_ok
    print(f"\nSTATIC CHECK E4: {passed}/{total} {'PASS' if passed == total else 'FAIL'}")
    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main())
