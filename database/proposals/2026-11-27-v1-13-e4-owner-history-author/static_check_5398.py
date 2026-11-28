#!/usr/bin/env python3
"""V1-13 · D-E3-2 — verificação estática da 5398 (com testes de mutação). Executar nesta pasta."""
import hashlib
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import build_5398 as B  # noqa: E402

KW = re.compile(r"(?i)\b(insert|update|delete|merge|drop|alter|create|grant|revoke|truncate|lock|comment|copy|call|do|execute|vacuum|analyze|refresh|reindex|cluster|set_config|nextval|setval|pg_terminate_backend|pg_cancel_backend|dblink)\b")


def ro(sql):
    s = re.sub(r"/\*[\s\S]*?\*/", " ", sql)
    s = re.sub(r"--[^\r\n]*", " ", s)
    s = re.sub(r"'(?:[^']|'')*'", "''", s).strip()
    return bool(re.match(r"(?i)^select\b", s)) and s.count(";") == 1 and s.endswith(";") and "$" not in s and not KW.search(s)


def body_of(mig):
    m = re.search(r"as \$fn\$([\s\S]*?)\$fn\$;", mig)
    return m.group(1) if m else ""


def checks(a):
    R = []
    ck = lambda i, ok, d: R.append((i, bool(ok), d))
    mig, pre, post, rb, man = (a[n] for n in ("5398_owner_binder_history_author.sql", "D_E3_2_5398_PRE_readonly.sql", "D_E3_2_5398_POST_readonly.sql", "ROLLBACK_5398.sql", "D_E3_2_5398_MANIFEST.txt"))
    body = body_of(mig)
    ck("C1", hashlib.md5(body.encode()).hexdigest() == B.MD5_BODY and B.MD5_BODY in mig and B.MD5_BODY in post, "corpo da função = md5 conferido no postcheck e no POST")
    ck("C2", re.search(r"if not public\.v1_13_capability_open\(\) then return; end if;", body) and body.index("v1_13_capability_open") < body.index("return query"),
       "barreira 5389 antes de qualquer leitura (fechada → nenhuma linha)")
    ck("C3", "e.owner_user_id = v_uid" in body and "e.layout_key = p_layout_key" in body and "e.id = any (p_event_ids)" in body,
       "só eventos do PRÓPRIO titular, deste fichário e dos ids pedidos")
    ck("C4", "cardinality(p_event_ids) > 50" in body and re.search(r"limit 50;", body), "limite de 50 ids e de 50 linhas")
    ck("C5", "display_name" in body and not re.search(r"(?i)email|username|physical|allocation|storage|condition|price", body),
       "só nome público (C-241): sem e-mail, username ou dado patrimonial")
    ck("C6", re.search(r"(?i)\b(insert|update|delete)\b", re.sub(r"'(?:[^']|'')*'", "''", body)) is None and "stable" in mig and "security definer" in mig and "set search_path = ''" in mig,
       "leitura pura: STABLE, definer, search_path vazio, sem escrita")
    ck("G1", re.search(r"revoke all on function public\.get_my_binder_activity_actors\(uuid, bigint\[\]\) from public, anon, service_role;", mig)
       and re.search(r"grant execute on function public\.get_my_binder_activity_actors\(uuid, bigint\[\]\) to authenticated;", mig)
       and not re.search(r"grant [^;]*to (anon|public|service_role)", mig), "EXECUTE só para authenticated")
    ck("G2", mig.count("begin;") == 1 and mig.count("commit;") == 1 and "get_my_binder_activity(" not in mig.replace("get_my_binder_activity_actors(", ""),
       "transação única; a 5269 não é tocada")
    for n, s in (("PRE", pre), ("POST", post)):
        ck("K1", ro(s), f"{n}: SELECT único sem escrita (validador do executor)")
    ck("K2", all(k in pre for k in ("'barreira'", "'identidades_teste'", "'ausente_5398'", "'funcoes_barreira_canonicas'"))
       and all(k in post for k in ("'barreira'", "'identidades_teste'", "'funcao_5398'", "'so_authenticated'")), "PRE e POST com barreira, 0 identidades e contrato")
    ck("R1", "drop function public.get_my_binder_activity_actors(uuid, bigint[]);" in rb and B.MD5_BODY in rb and rb.count("drop function") == 1, "reversão: só remove a função nova, conferida por md5")
    rows = [l.split("|") for l in man.splitlines() if l and not l.startswith("#")]
    ok = [(r[1].split("\\")[-1], r[3]) for r in rows] == [("D_E3_2_5398_PRE_readonly.sql", "gate"), ("5398_owner_binder_history_author.sql", "write"), ("D_E3_2_5398_POST_readonly.sql", "gate")] \
        and all(r[2] == hashlib.sha256(a[r[1].split("\\")[-1]].encode()).hexdigest() for r in rows)
    ck("X1", ok, "manifesto PRE → 5398 → POST com sha256 dos arquivos (gate antes da escrita)")
    live = re.compile(r"qjfutqujxrbzgrtkpgkg|supabase\.co|eyJ|sbp_|@[a-z0-9.-]+\.[a-z]{2,}|[A-Za-z]:\\\\Users", re.I)
    ck("X2", not any(live.search(re.sub(r"(?m)^#.*$", "", a[n])) for n in a), "sem projeto, URL, e-mail, credencial ou caminho privado")
    return R


def load():
    return {p.name: p.read_text(encoding="utf-8") for p in HERE.iterdir() if p.suffix in (".sql", ".txt")}


M = "5398_owner_binder_history_author.sql"
MUTATIONS = [
    ("sem barreira", M, "  if not public.v1_13_capability_open() then return; end if;  -- G1 (D-E1): fechada → nenhuma linha\n", "", "C2"),
    ("sem filtro do titular", M, "  where e.owner_user_id = v_uid\n    and", "  where", "C3"),
    ("sem limite de ids", M, "  if cardinality(p_event_ids) > 50 then", "  if false then", "C4"),
    ("expõe username", M, "select up.display_name::text from", "select up.username::text from", "C5"),
    ("grant para anon", M, "grant execute on function public.get_my_binder_activity_actors(uuid, bigint[]) to authenticated;", "grant execute on function public.get_my_binder_activity_actors(uuid, bigint[]) to authenticated, anon;", "G1"),
    ("toca a 5269", M, "\ncommit;", "\ncomment on function public.get_my_binder_activity(uuid, text[], timestamptz, bigint, integer) is 'x';\ncommit;", "G2"),
    ("POST com escrita", "D_E3_2_5398_POST_readonly.sql", "select jsonb_build_object(", "select jsonb_build_object( 'x', (select nextval('s')),", "K1"),
    ("reversão derruba outra", "ROLLBACK_5398.sql", "drop function public.get_my_binder_activity_actors(uuid, bigint[]);", "drop function public.get_my_binder_activity_actors(uuid, bigint[]);\ndrop function public.get_my_binder_activity(uuid, text[], timestamptz, bigint, integer);", "R1"),
    ("manifesto com hash errado", "D_E3_2_5398_MANIFEST.txt", "|write", "0|write", "X1"),
]


def main():
    a = load()
    res = checks(a)
    for i, ok, d in res:
        print(f"{'PASS' if ok else 'FAIL'}  {i:<3} {d}")
    killed, lines = 0, []
    for name, f, old, new, target in MUTATIONS:
        m = dict(a)
        assert m[f].count(old) >= 1, (name, old)
        m[f] = m[f].replace(old, new, 1)
        dead = any(i == target and not ok for i, ok, _ in checks(m))
        killed += dead
        lines.append(f"      {'morta' if dead else 'VIVA '}  [{target}] {name}")
    mut_ok = killed == len(MUTATIONS)
    print(f"{'PASS' if mut_ok else 'FAIL'}  MUT {killed}/{len(MUTATIONS)} mutações reprovadas pelo controle-alvo")
    print("\n".join(lines))
    total, passed = len(res) + 1, sum(ok for _, ok, _ in res) + mut_ok
    print(f"\nSTATIC CHECK 5398: {passed}/{total} {'PASS' if passed == total else 'FAIL'}")
    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main())
