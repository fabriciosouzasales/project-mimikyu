#!/usr/bin/env python3
"""
V1-13 · E1-A — verificador ESTÁTICO e INDEPENDENTE do ensaio P1.

Independência: não importa nem executa o gerador (build_p1_dryrun_e1a.py). Tem
lexer próprio e rederiva, a partir dos arquivos aprovados, o que o artefato
precisa conter. Não conecta em banco, não executa SQL.

Uso:
    python3 -I verify_p1_dryrun_e1a.py            # verifica o artefato
    python3 -I verify_p1_dryrun_e1a.py --no-selftest

Saída: PASS/FAIL por verificação, a lista do que NÃO pode ser provado sem
execução, o resultado do autoteste de mutações e o GATE. Código 0 só com tudo PASS.

Limite declarado: análise estática NÃO comprova atomicidade, isolamento,
ausência de efeitos externos, duração de locks nem comportamento do servidor.
Ela comprova apenas propriedades do TEXTO: o que está escrito, em que ordem,
e que não mudou em relação aos arquivos aprovados.
"""
from __future__ import annotations

import hashlib
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.dirname(HERE)
ARTIFACT = os.path.join(HERE, "P1_DRYRUN_E1A_rollback.sql")
S0 = os.path.join(HERE, "P1_S0_POST_readonly.sql")
TXID = os.path.join(HERE, "P1_POST_txid_readonly.sql")
MANIFEST = os.path.join(HERE, "MANIFEST.sha256")
MIGRATIONS = ["5366", "5367", "5368", "5369", "5370"]
HARNESS = "5888_validate_editor_role_foundation_HARNESS.sql"
EXPECTED_CHECKS = 54


# --------------------------------------------------------------------------- lexer próprio
class Tok:
    __slots__ = ("kind", "text", "line")

    def __init__(self, kind: str, text: str, line: int):
        self.kind, self.text, self.line = kind, text, line


def lex(sql: str) -> list[Tok]:
    """Tokens: comment, string, ident, dollar, word, punct, semi, meta (linha psql \\...)."""
    toks: list[Tok] = []
    i, n, line = 0, len(sql), 1
    at_stmt_start = True
    while i < n:
        c = sql[i]
        if c == "\n":
            line += 1
            i += 1
            continue
        if c in " \t\r":
            i += 1
            continue
        if at_stmt_start and c == "\\":
            j = sql.find("\n", i)
            j = n if j < 0 else j
            toks.append(Tok("meta", sql[i:j], line))
            i = j
            continue
        if sql.startswith("--", i):
            j = sql.find("\n", i)
            j = n if j < 0 else j
            toks.append(Tok("comment", sql[i:j], line))
            i = j
            continue
        if sql.startswith("/*", i):
            depth, j = 1, i + 2
            while j < n and depth:
                if sql.startswith("/*", j):
                    depth, j = depth + 1, j + 2
                elif sql.startswith("*/", j):
                    depth, j = depth - 1, j + 2
                else:
                    j += 1
            if depth:
                raise ValueError(f"comentário de bloco não fechado na linha {line}")
            toks.append(Tok("comment", sql[i:j], line))
            line += sql.count("\n", i, j)
            i = j
            continue
        if c == "'" or (c in "eE" and i + 1 < n and sql[i + 1] == "'"):
            j = i + (2 if c != "'" else 1)
            esc = c != "'"
            while j < n:
                if esc and sql[j] == "\\":
                    j += 2
                    continue
                if sql[j] == "'":
                    if j + 1 < n and sql[j + 1] == "'":
                        j += 2
                        continue
                    break
                j += 1
            if j >= n:
                raise ValueError(f"string não fechada na linha {line}")
            toks.append(Tok("string", sql[i : j + 1], line))
            line += sql.count("\n", i, j)
            i = j + 1
            at_stmt_start = False
            continue
        if c == '"':
            j = sql.index('"', i + 1)
            while j + 1 < n and sql[j + 1] == '"':
                j = sql.index('"', j + 2)
            toks.append(Tok("ident", sql[i : j + 1], line))
            i = j + 1
            at_stmt_start = False
            continue
        m = re.match(r"\$([A-Za-z_][A-Za-z0-9_]*)?\$", sql[i:])
        if m:
            tag = m.group(0)
            j = sql.find(tag, i + len(tag))
            if j < 0:
                raise ValueError(f"delimitador {tag} não fechado na linha {line}")
            toks.append(Tok("dollar", sql[i : j + len(tag)], line))
            line += sql.count("\n", i, j)
            i = j + len(tag)
            at_stmt_start = False
            continue
        if c == ";":
            toks.append(Tok("semi", ";", line))
            i += 1
            at_stmt_start = True
            continue
        m = re.match(r"[A-Za-z_][A-Za-z0-9_$]*", sql[i:])
        if m:
            toks.append(Tok("word", m.group(0), line))
            i += len(m.group(0))
            at_stmt_start = False
            continue
        toks.append(Tok("punct", c, line))
        i += 1
        at_stmt_start = False
    return toks


def statements(sql: str):
    """Lista de (marcador vigente, texto sem comentários normalizado, tokens, linha)."""
    out, cur, marker, start = [], [], None, None
    for t in lex(sql):
        if t.kind == "comment":
            m = re.match(r"--\s*@@(T\d+)\b(.*)", t.text)
            if m and not cur:
                marker = (m.group(1), m.group(2).strip())
            continue
        if t.kind == "meta":
            out.append((marker, t.text.strip(), [t], t.line))
            continue
        if start is None:
            start = t.line
        cur.append(t)
        if t.kind == "semi":
            text = " ".join(x.text for x in cur[:-1])
            out.append((marker, re.sub(r"\s+", " ", text).strip(), cur, start))
            cur, start = [], None
    if cur:
        out.append((marker, " ".join(x.text for x in cur), cur, start))
    return out


def body_of(tok_text: str) -> str:
    m = re.match(r"(\$[A-Za-z0-9_]*\$)", tok_text)
    tag = m.group(1)
    return tok_text[len(tag) : -len(tag)]


def sha256b(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def rb(path: str) -> bytes:
    with open(path, "rb") as fh:
        return fh.read()


# --------------------------------------------------------------------------- verificação
TXN_WORDS = {"COMMIT", "END", "ABORT", "SAVEPOINT", "RELEASE", "PREPARE", "START"}
FORBIDDEN_CALLS = re.compile(
    r"\b(dblink\w*|net\.\w+|http_\w+|lo_import|lo_export|pg_read_file|pg_read_binary_file|pg_ls_dir|pg_stat_file|"
    r"pg_terminate_backend|pg_cancel_backend|pg_reload_conf|pg_notify|pg_sleep|pg_advisory\w*|setval|"
    r"pg_promote|pg_switch_wal|pg_create_restore_point|pg_rotate_logfile)\s*\(", re.I)
FORBIDDEN_STMT = re.compile(
    r"^(ALTER SYSTEM|ALTER DATABASE|ALTER ROLE|ALTER USER|CREATE ROLE|CREATE USER|DROP ROLE|DROP USER|"
    r"CREATE EXTENSION|DROP EXTENSION|ALTER EXTENSION|CREATE PUBLICATION|ALTER PUBLICATION|CREATE SUBSCRIPTION|"
    r"LISTEN|NOTIFY|UNLISTEN|COPY|VACUUM|CLUSTER|REINDEX|CHECKPOINT|LOAD|SECURITY LABEL|SET SESSION AUTHORIZATION|"
    r"SET ROLE|RESET ROLE|DISCARD|LOCK|CREATE DATABASE|DROP DATABASE|CREATE TABLESPACE|IMPORT FOREIGN|CREATE SERVER)\b", re.I)
ALLOWED_EXECUTE_STRINGS = {"'reset role'", "'set local role anon'", "'set local role authenticated'"}
# Únicos parâmetros que set_config pode tocar (todos locais à transação). Fora daqui ficam,
# entre outros, session_replication_role (desligaria a FK da trava), default_transaction_read_only,
# transaction_read_only, lock_timeout/statement_timeout (afrouxariam limites).
ALLOWED_SETCONFIG = {"'client_connection_check_interval'", "'transaction_timeout'", "'request.jwt.claims'",
                     "'request.jwt.claim.sub'", "'mmkyu.e1a_5368_acl'", "'mmkyu.e1a_5369_acl'"}
ALLOWED_SET_LOCAL = {"LOCK_TIMEOUT", "STATEMENT_TIMEOUT", "IDLE_IN_TRANSACTION_SESSION_TIMEOUT"}
BODY_SET = re.compile(r"(?:^|;|\bthen|\bbegin|\belse|\bloop)\s*(set|reset)\s+(?:local\s+|session\s+)?([a-z_.]+)", re.I)


def code_words(tokens):
    return [t for t in tokens if t.kind == "word"]


def verify(art: str, use_hashes: bool = True, s0_text: str | None = None) -> list[tuple[str, str, bool, str]]:
    """Devolve (id, tipo, ok, detalhe). tipo = INSPEÇÃO."""
    R: list[tuple[str, str, bool, str]] = []

    def chk(cid, ok, detail):
        R.append((cid, "INSPEÇÃO", bool(ok), detail))

    # H. Integridade ------------------------------------------------------------
    if use_hashes:
        man = {}
        for line in rb(MANIFEST).decode("utf-8").splitlines():
            h, p = line.split("  ", 1)
            man[p] = h
        bad = [p for p, h in man.items() if sha256b(rb(os.path.normpath(os.path.join(HERE, p)))) != h]
        chk("H1", not bad and len(man) == 10, f"MANIFEST: 10 arquivos com sha256 conferido (divergentes: {bad})")
        srcs = {os.path.basename(p)[:4]: h for p, h in man.items() if p.startswith("../")}
        hdr = re.search(r"Fontes\.\.\.\.\.\.: (.*)", art)
        pairs = dict(x.split("@") for x in hdr.group(1).split(", ")) if hdr else {}
        chk("H2", hdr and all(srcs.get(k, "").startswith(v) for k, v in pairs.items()) and len(pairs) == 6,
            "cabeçalho 'Fontes' = prefixos sha256 do MANIFEST para 5366–5370 e 5888")
    raw = art.encode("utf-8")
    chk("H3", b"\r" not in raw and art.endswith("\n"), "artefato sem CRLF e terminado em nova linha")

    try:
        st = statements(art)
    except ValueError as e:
        chk("L0", False, f"lexer: {e}")
        return R
    chk("L0", True, f"lexer: {len(st)} instruções de nível superior")

    # S. Estrutura ---------------------------------------------------------------
    metas = [s for s in st if s[2][0].kind == "meta"]
    chk("S1", [m[1] for m in metas] == ["\\set ON_ERROR_STOP on", "\\set VERBOSITY verbose"]
        and st[0] is metas[0] and st[1] is metas[1],
        "só duas linhas psql, nesta ordem e antes de qualquer SQL: '\\set ON_ERROR_STOP on' e '\\set VERBOSITY verbose'")
    sql_st = [s for s in st if s[2][0].kind != "meta"]
    seq = [s[0][0] if s[0] else None for s in sql_st]
    order = ["T0", "T1", "T2", "T3", "T4", "T5", "T6", "T7", "T8", "T9", "T10", "T11"]
    compressed = [x for i, x in enumerate(seq) if i == 0 or x != seq[i - 1]]
    chk("S2", compressed == order and None not in seq, f"marcadores na ordem T0…T11 sem instrução órfã ({compressed})")

    def first(mk):
        return next((s for s in sql_st if s[0] and s[0][0] == mk), None)

    def all_of(mk):
        return [s for s in sql_st if s[0] and s[0][0] == mk]

    t0 = all_of("T0")
    chk("S3", len(t0) == 1 and t0[0][1].upper() == "SET SESSION DEFAULT_TRANSACTION_READ_ONLY = ON",
        "T0 = SET SESSION default_transaction_read_only = on (padrão da sessão)")
    t1, t2 = all_of("T1"), all_of("T2")
    begins = [s for s in sql_st if code_words(s[2])[:1] and code_words(s[2])[0].text.upper() in ("BEGIN", "START")]
    chk("S4", len(t1) == 1 and t1[0][1].upper() == "BEGIN" and len(begins) == 1,
        "um único BEGIN de nível superior, em T1; nenhum START TRANSACTION")
    idx_b = sql_st.index(t1[0]) if t1 else -1
    chk("S5", len(t2) == 1 and t2[0][1].upper() == "SET TRANSACTION READ WRITE" and idx_b >= 0
        and sql_st[idx_b + 1] is t2[0], "T2 = SET TRANSACTION READ WRITE, imediatamente após o BEGIN")
    t3 = " | ".join(s[1] for s in all_of("T3"))
    chk("S6", "SET LOCAL lock_timeout = '2s'" in t3 and "SET LOCAL statement_timeout = '20s'" in t3
        and "SET LOCAL idle_in_transaction_session_timeout = '15s'" in t3
        and re.search(r"server_version_num.*< 140000.*raise exception", " ".join(
            body_of(t.text) for s in all_of("T3") for t in s[2] if t.kind == "dollar"), re.S | re.I),
        "T3: lock_timeout 2s, statement_timeout 20s, ociosidade 15s; recusa PG < 14")
    t4 = [s[1] for s in all_of("T4")]
    chk("S7", len(t4) == 3
        and re.match(r"create temp table p1_e1a_trap_parent \( id integer primary key \) on commit drop", t4[0], re.I)
        and re.search(r"references p1_e1a_trap_parent \( id \) deferrable initially deferred \) on commit drop", t4[1], re.I)
        and re.match(r"insert into p1_e1a_trap_child \( parent_id \) values \( 1 \)", t4[2], re.I),
        "T4: FK temporária DEFERRABLE INITIALLY DEFERRED + linha órfã (COMMIT falharia)")

    # Controle de transação em qualquer ponto
    tc = []
    for s in sql_st:
        w = code_words(s[2])
        if not w:
            continue
        head = w[0].text.upper()
        if head in TXN_WORDS or (head == "ROLLBACK" and s[0] and s[0][0] != "T10"):
            tc.append((s[3], s[1][:40]))
        if head == "ROLLBACK" and len(w) > 1:
            tc.append((s[3], "ROLLBACK com complemento"))
        if head == "SET" and len(w) > 1 and w[1].text.upper() == "CONSTRAINTS":
            tc.append((s[3], "SET CONSTRAINTS"))
    rbs = [s for s in sql_st if code_words(s[2])[:1] and code_words(s[2])[0].text.upper() == "ROLLBACK"]
    chk("S8", not tc and len(rbs) == 1, f"nenhum COMMIT/END/ABORT/SAVEPOINT/RELEASE/PREPARE/SET CONSTRAINTS; um só ROLLBACK, em T10 ({tc})")

    # Controle de transação escondido em corpos e EXECUTE
    hidden = []
    exec_bad = []
    setcfg_bad = []
    for s in sql_st:
        for t in s[2]:
            if t.kind != "dollar":
                continue
            inner = lex(body_of(t.text))
            for k, it in enumerate(inner):
                if it.kind == "word" and it.text.upper() in ("COMMIT", "ROLLBACK", "SAVEPOINT") \
                        and not (it.text.upper() == "ROLLBACK" and False):
                    hidden.append((s[3], it.text))
                if it.kind == "word" and it.text.upper() == "CONSTRAINTS" and k and inner[k - 1].text.upper() == "SET":
                    hidden.append((s[3], "SET CONSTRAINTS"))
                if it.kind == "string" and re.match(r"'\s*(commit|rollback|savepoint|release|begin|end|start|set\s+constraints|prepare)\b",
                                                    it.text, re.I):
                    hidden.append((s[3], it.text[:30]))
                if it.kind == "word" and it.text.upper() == "EXECUTE":
                    nxt = inner[k + 1] if k + 1 < len(inner) else None
                    if not nxt or nxt.kind != "string" or nxt.text.lower() not in ALLOWED_EXECUTE_STRINGS:
                        exec_bad.append((s[3], nxt.text[:30] if nxt else "?"))
            for k, it in enumerate(inner):
                if it.kind == "word" and it.text.lower() == "set_config" and k + 1 < len(inner) and inner[k + 1].text == "(":
                    depth, args, cur = 0, [], []
                    for x in inner[k + 1:]:
                        if x.text == "(":
                            depth += 1
                            if depth == 1:
                                continue
                        elif x.text == ")":
                            depth -= 1
                            if depth == 0:
                                args.append(cur)
                                break
                        elif x.text == "," and depth == 1:
                            args.append(cur)
                            cur = []
                            continue
                        cur.append(x.text)
                    if len(args) != 3 or [a.lower() for a in args[2]] != ["true"]:
                        setcfg_bad.append((s[3], " ".join(sum(args, []))[:50]))
                    elif not (len(args[0]) == 1 and args[0][0].lower() in ALLOWED_SETCONFIG):
                        setcfg_bad.append((s[3], "parâmetro não permitido: " + " ".join(args[0])[:40]))
    chk("S9", not hidden, f"nenhum controle de transação dentro de corpos ou strings executáveis ({hidden})")
    chk("S10", not exec_bad, f"EXECUTE só com 'reset role' / 'set local role anon|authenticated' ({exec_bad})")
    chk("S11", not setcfg_bad, f"set_config sempre local à transação (terceiro argumento true) ({setcfg_bad})")

    # Trava não é tocada depois de T4
    touch = [s[3] for s in sql_st if s[0] and s[0][0] != "T4"
             and re.search(r"\b(delete|update|truncate|drop|alter)\b[^;]*p1_e1a_trap", s[1], re.I)]
    touch += [s[3] for s in sql_st for t in s[2] if t.kind == "dollar"
              and re.search(r"\b(delete|update|truncate|drop|alter)\b[^;]*p1_e1a_trap", body_of(t.text), re.I)]
    chk("S12", not touch, f"trava de COMMIT nunca alterada, apagada ou removida depois de T4 ({touch})")

    # Sessão: só T0 muda parâmetro de sessão; RESET só em T11
    sess = []
    for s in sql_st:
        w = [x.text.upper() for x in code_words(s[2])]
        if not w:
            continue
        if w[0] == "SET" and not (len(w) > 1 and w[1] in ("LOCAL", "TRANSACTION")) and s[0][0] != "T0":
            sess.append((s[3], s[1][:40]))
        if w[0] == "RESET" and s[0][0] != "T11":
            sess.append((s[3], s[1][:40]))
    chk("S13", not sess, f"nenhum SET de sessão além de T0; RESET só em T11 ({sess})")
    loc = []
    for s in sql_st:
        w = [x.text.upper() for x in code_words(s[2])]
        if len(w) > 2 and w[0] == "SET" and w[1] == "LOCAL" and w[2] not in ALLOWED_SET_LOCAL:
            loc.append((s[3], s[1][:50]))
        for t in s[2]:
            if t.kind == "dollar":
                code = " ".join(x.text for x in lex(body_of(t.text)) if x.kind not in ("comment", "string"))
                for m in BODY_SET.finditer(code):
                    loc.append((s[3], m.group(0).strip()[:40]))
    chk("S21", not loc, f"SET LOCAL só de lock_timeout/statement_timeout/ociosidade; nenhum SET/RESET dentro de corpos ({loc})")

    # Sentinela incondicional
    sent = [s for s in all_of("T9") if "sentinela" in s[0][1]]
    ok_sent, why = False, "ausente"
    if len(sent) == 1:
        d = [t for t in sent[0][2] if t.kind == "dollar"]
        if d:
            body = body_of(d[0].text)
            low = body.lower()
            k = low.find("raise exception using message = v_msg, errcode = v_code;")
            pre = lex(body[:k]) if k >= 0 else []
            w = [t.text.lower() for t in pre if t.kind == "word"]
            opens = sum(1 for a in range(len(w)) if w[a] == "if" and (a == 0 or w[a - 1] != "end"))
            closes = sum(1 for a in range(1, len(w)) if w[a] == "if" and w[a - 1] == "end")
            loops = w.count("loop")
            ok_sent = (k >= 0 and opens == closes and loops % 2 == 0 and "return" not in w
                       and " exception when" not in low and low.count("raise ") == 1
                       and "v_code := case when v_ok then 'e1aok' else 'e1ano' end;" in low
                       and "v_msg := 'msdryrun_e1a ' || case when v_ok then 'aprovado ' else 'reprovado ' end" in low)
            why = f"raise={k >= 0} if-abertos={opens - closes} return={'return' in w}"
        nxt = sql_st[sql_st.index(sent[0]) + 1]
        ok_sent = ok_sent and code_words(nxt[2])[0].text.upper() == "ROLLBACK"
    chk("S14", ok_sent, f"sentinela T9: um único RAISE, incondicional, com SQLSTATE E1AOK/E1ANO e prefixo APROVADO/REPROVADO, sem handler nem return, imediatamente antes do ROLLBACK ({why})")
    sb = " ".join(body_of(t.text) for s in sent for t in s[2] if t.kind == "dollar")
    chk("S15", f"v_total = {EXPECTED_CHECKS}" in sb and f"v_passes = {EXPECTED_CHECKS}" in sb and "v_trap" in sb
        and "v_ms <= 10000" in sb, f"sentinela só aprova com {EXPECTED_CHECKS}/{EXPECTED_CHECKS}, trava intacta e duração ≤ 10 s")

    # Desfecho inequívoco: marcas da sentinela só existem na sentinela
    sent_ids = {id(x) for x in sent}
    leak = []
    for s in sql_st:
        if id(s) in sent_ids:
            continue
        txt = " ".join(t.text for t in s[2] if t.kind != "comment")
        for t in s[2]:
            if t.kind == "dollar":
                txt += " " + " ".join(x.text for x in lex(body_of(t.text)) if x.kind != "comment")
        if re.search(r"MSDRYRUN|E1AOK|E1ANO", txt, re.I):
            leak.append(s[3])
    chk("S25", not leak, f"marcas do desfecho (MSDRYRUN_E1A, E1AOK, E1ANO) só aparecem na sentinela ({leak})")

    # Inventário dos passos gerados (fora das fontes aprovadas): nada além do previsto
    def sig(s):
        w = [x.text.upper() for x in code_words(s[2])]
        return " ".join(w[:3])
    allowed = {
        "T0": ["SET SESSION DEFAULT_TRANSACTION_READ_ONLY"], "T1": ["BEGIN"], "T2": ["SET TRANSACTION READ"],
        "T3": ["SET LOCAL LOCK_TIMEOUT", "SET LOCAL STATEMENT_TIMEOUT", "SET LOCAL IDLE_IN_TRANSACTION_SESSION_TIMEOUT", "DO"],
        "T4": ["CREATE TEMP TABLE", "CREATE TEMP TABLE", "INSERT INTO P1_E1A_TRAP_CHILD"],
        "T5": ["CREATE TEMP TABLE", "CREATE TEMP TABLE"],
        "T6": ["DO", "LOCK TABLE PUBLIC", "INSERT INTO PG_TEMP"],
        "T9": ["DO", "DO"], "T10": ["ROLLBACK"], "T11": ["RESET DEFAULT_TRANSACTION_READ_ONLY"],
    }
    inv_bad = []
    for mk, exp in allowed.items():
        got = [sig(x) for x in all_of(mk)]
        if got != exp:
            inv_bad.append((mk, got))
    t8gen = [sig(x) for x in all_of("T8") if x[0][1] == "relatório"]
    if t8gen != ["INSERT INTO PG_TEMP"]:
        inv_bad.append(("T8 relatório", t8gen))
    lk = [x[1] for x in all_of("T6") if sig(x).startswith("LOCK")]
    if lk != ["LOCK TABLE public . collection_membership IN ACCESS EXCLUSIVE MODE NOWAIT"]:
        inv_bad.append(("T6 LOCK", lk))
    tt = [x[1].lower() for x in all_of("T4") + all_of("T5") if sig(x) == "CREATE TEMP TABLE"]
    if not all(re.match(r"create temp table p1_e1a_\w+ ", x) and x.endswith("on commit drop") for x in tt):
        inv_bad.append(("tabelas temporárias", tt))
    ins = [x[1].lower() for x in all_of("T6") + all_of("T8") if sig(x).startswith("INSERT")]
    if not all(re.match(r"insert into pg_temp \. p1_e1a_(meta|evidence) ", x) for x in ins):
        inv_bad.append(("INSERT", ins))
    chk("S23", not inv_bad, f"passos gerados só com as instruções previstas (LOCK único: collection_membership NOWAIT) ({inv_bad})")

    # DML nos corpos gerados (T3, T6, T9): só nas tabelas temporárias do ensaio; T9 sem DML
    dml_bad = []
    for mk in ("T3", "T6", "T9"):
        for x in all_of(mk):
            for t in x[2]:
                if t.kind != "dollar":
                    continue
                code = " ".join(y.text for y in lex(body_of(t.text)) if y.kind not in ("comment", "string")).lower()
                for m in re.finditer(r"\b(insert\s+into|update|delete\s+from|truncate|merge\s+into)\s+([a-z_.\s]+?)\s*(\(|\bset\b|\bvalues\b|\bwhere\b|;|$)", code):
                    tgt = m.group(2).replace(" ", "")
                    if mk == "T9" or not tgt.startswith("pg_temp.p1_e1a_"):
                        dml_bad.append((mk, m.group(1), tgt))
    chk("S24", not dml_bad, f"corpos gerados: escrita só em pg_temp.p1_e1a_*; T9 só lê ({dml_bad})")

    # Dependências de versão do PostgreSQL: só em T3, com guarda de versão
    t3body = " ".join(body_of(t.text) for s in all_of("T3") for t in s[2] if t.kind == "dollar")
    outside = [s[3] for s in sql_st if s[0] and s[0][0] != "T3"
               and re.search(r"transaction_timeout|client_connection_check_interval", " ".join(t.text for t in s[2]))]
    chk("S22", not outside
        and re.search(r">= 170000 then\s+perform pg_catalog\.set_config\('transaction_timeout'", t3body)
        and t3body.find("< 140000") < t3body.find("client_connection_check_interval"),
        "recursos dependentes de versão só em T3: transaction_timeout só com PG ≥ 17; client_connection_check_interval só depois da recusa de PG < 14 (versão real: S0)")

    # T6 precheck: proteções lidas no próprio servidor
    t6 = " ".join(body_of(t.text) for s in all_of("T6") for t in s[2] if t.kind == "dollar")
    need6 = ["current_setting('transaction_read_only') <> 'off'", "current_setting('default_transaction_read_only') <> 'on'",
             "session_replication_role", "pg_is_in_recovery()", "current_user <> 'postgres'", "condeferrable and k.condeferred",
             "pg_event_trigger", "pg_trigger", "collection_membership'::regclass"]
    miss6 = [x for x in need6 if x not in t6]
    chk("S16", not miss6, f"T6 confere no servidor: READ WRITE, T0 vigente, gatilhos ativos, sem recuperação, executor, trava adiada, gatilhos externos, locks antigos (faltando: {miss6})")

    # T7/T8 = arquivos aprovados, byte a byte
    t7_ok, t7_det = True, []
    t7_markers = [s for s in all_of("T7")]
    names_in_order = []
    for s in t7_markers:
        if s[0][1] not in names_in_order:
            names_in_order.append(s[0][1])
    srcfiles = sorted(f for f in os.listdir(SRC) if f[:4] in MIGRATIONS and f.endswith(".sql"))
    chk("S17", [x.split(" ")[0] for x in names_in_order] == srcfiles,
        f"T7 aplica 5366 → 5370 nesta ordem ({[x.split(' ')[0][:4] for x in names_in_order]})")
    for name in srcfiles:
        src = rb(os.path.join(SRC, name)).decode("utf-8").split("\n")
        b, c = src.index("begin;"), src.index("commit;")
        expected = "\n".join(src[b + 1 : c]).strip("\n")
        sha = sha256b(rb(os.path.join(SRC, name)))
        mk = f"-- @@T7 {name} sha256={sha}\n"
        i = art.find(mk)
        j = art.find("\n-- @@T", i + len(mk)) if i >= 0 else -1
        seg = art[i + len(mk) : j].strip("\n") if i >= 0 else None
        if seg != expected:
            t7_ok = False
            t7_det.append(name[:4])
    chk("S18", t7_ok, f"T7: cada migration idêntica ao arquivo aprovado entre 'begin;' e 'commit;', com sha256 no marcador (divergentes: {t7_det})")
    h = rb(os.path.join(SRC, HARNESS)).decode("utf-8")
    hi = h.index("create or replace function pg_temp.wh_5888_as(p_user uuid)")
    hj = h.index("$fn$;", h.index("pg_temp.wh_5888_validate()")) + 5
    mk = f"-- @@T8 {HARNESS} sha256={sha256b(rb(os.path.join(SRC, HARNESS)))}\n"
    i = art.find(mk)
    j = art.find("\n-- @@T", i + len(mk)) if i >= 0 else -1
    chk("S19", i >= 0 and art[i + len(mk) : j].strip("\n") == h[hi:hj],
        "T8: as quatro funções pg_temp da 5888 idênticas ao arquivo aprovado")
    t8 = [s[1] for s in all_of("T8") if code_words(s[2])[0].text.lower() == "insert"]
    chk("S20", len(t8) == 1 and "frompg_temp.wh_5888_validate()" in t8[0].lower().replace(" ", ""),
        "T8: relatório da 5888 gravado na evidência, uma vez, depois das funções")

    # E. Efeitos externos e comandos não previstos (texto) -----------------------
    ext = []
    for s in sql_st:
        if FORBIDDEN_STMT.match(s[1]) and not (s[0] and s[0][0] == "T6"
                                               and s[1] == "LOCK TABLE public . collection_membership IN ACCESS EXCLUSIVE MODE NOWAIT"):
            ext.append((s[3], s[1][:40]))
        code = " ".join(t.text for t in s[2] if t.kind in ("word", "punct"))
        for m in FORBIDDEN_CALLS.finditer(code.replace(" ( ", "(").replace(" (", "(")):
            ext.append((s[3], m.group(0)))
        for t in s[2]:
            if t.kind == "dollar":
                inner = lex(body_of(t.text))
                icode = " ".join(x.text for x in inner if x.kind in ("word", "punct"))
                for m in FORBIDDEN_CALLS.finditer(icode.replace(" ( ", "(").replace(" (", "(")):
                    ext.append((s[3], m.group(0)))
    chk("E1", not ext, f"nenhum comando ou função com efeito externo/administrativo no código (fora de strings/comentários) ({ext[:5]})")
    gr = [s[3] for s in sql_st if re.match(r"^(GRANT|REVOKE)\b", s[1], re.I) and s[0][0] != "T7"]
    chk("E2", not gr, f"GRANT/REVOKE só dentro das migrations aprovadas (T7) ({gr})")
    secrets = re.findall(r"(postgres(?:ql)?://\S+|password\s*=|eyJ[A-Za-z0-9_-]{10,}|sb_secret_\w+|service_role_key|"
                         r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})", art, re.I)
    emails = [e for e in re.findall(r"[\w.+-]+@[\w-]+\.[\w.]+", art) if not e.endswith("example.invalid")]
    chk("E3", not secrets and not emails, f"sem credencial, URI de conexão, token, UUID fixo ou e-mail real ({secrets[:3]} {emails[:3]})")

    # S0 só leitura --------------------------------------------------------------
    if s0_text is not None:
        s0st = [s for s in statements(s0_text)]
        w0 = code_words(s0st[0][2]) if s0st else []
        s0code = " ".join(t.text.lower() for s in s0st for t in s[2] if t.kind == "word")
        bad0 = [x for x in ("insert", "update", "delete", "create", "alter", "drop", "truncate", "do", "set_config",
                            "nextval", "setval", "pg_sleep", "lock", "copy", "grant", "revoke", "call", "execute")
                if re.search(rf"\b{x}\b", s0code)]
        chk("S0.1", len(s0st) == 1 and w0 and w0[0].text.lower() == "select" and not bad0 and " for update" not in s0code,
            f"S0/pós-estado: uma instrução SELECT, sem escrita, sem DO, sem set_config, sem trava ({bad0})")
        tx = rb(TXID).decode("utf-8")
        txst = statements(tx)
        chk("S0.2", len(txst) == 1 and re.sub(r"\s+", " ", txst[0][1]).lower()
            .replace(" ", "") == "selectpg_catalog.txid_status(:'txid'::bigint)asestado_transacao",
            "pós-estado: prova de rollback = um único SELECT txid_status(:'txid'), sem escrita")

    return R


NEEDS_EXECUTION = [
    "Atomicidade: que o servidor desfaz DDL e fixture no aborto (semântica do PostgreSQL; só a execução demonstra neste banco).",
    "Que T0 vigora na MESMA sessão física (conexão direta; pooler em modo transação anula a guarda). T6 confere no servidor; o texto não prova.",
    "Que a FK adiada realmente veta um COMMIT (comportamento do servidor).",
    "Versão do PostgreSQL do LIVE (≥ 14; ≥ 17 para transaction_timeout) e suporte a client_connection_check_interval.",
    "Ausência de gatilhos/gatilhos de evento com efeito externo no LIVE (T6 e S0 consultam; o texto não sabe o que existe lá).",
    "Locks em collection_membership: o LOCK NOWAIT da T6 obtém na hora ou falha (55P03) sem formar fila; a DURAÇÃO depois de obtido (até o aborto, cobrindo T7–T9) só é medida na execução (lock_ms no JSON).",
    "Que o psql mostra o SQLSTATE (VERBOSITY verbose) e sai com código 3 no erro final (comportamento do cliente usado).",
    "Que txid_status do txid da sentinela é 'aborted' depois do ensaio (P1_POST_txid_readonly.sql).",
    "Que as 54 verificações da 5888 passam (resultado dinâmico).",
    "Que nada persiste além do previsto (sequências, estatísticas, log, WAL) — §2.7 da estratégia.",
    "md5 dos corpos vigentes no LIVE iguais aos canônicos (S0).",
    "Comportamento do executor e do canal (contrato; nenhuma análise de texto cobre).",
]


def mutations(art: str) -> list[tuple[str, str]]:
    def rep(a, b, count=1):
        assert a in art, a
        return art.replace(a, b, count)

    t8_anchor = "\n-- @@T9 postcheck\n"
    seg7 = art.index("-- @@T7 5366")
    return [
        ("ROLLBACK trocado por COMMIT", rep("\nROLLBACK;\n", "\nCOMMIT;\n")),
        ("COMMIT inserido depois da 5888", rep(t8_anchor, "\nCOMMIT;\n" + t8_anchor)),
        ("T0 removido", rep("SET SESSION default_transaction_read_only = on;\n", "")),
        ("T2 removido", rep("SET TRANSACTION READ WRITE;\n", "")),
        ("linha órfã da trava removida", rep("insert into p1_e1a_trap_child (parent_id) values (1);\n", "")),
        ("FK da trava não adiada", rep("deferrable initially deferred", "not deferrable")),
        ("SET CONSTRAINTS inserido", rep(t8_anchor, "\nSET CONSTRAINTS ALL IMMEDIATE;\n" + t8_anchor)),
        ("meta-comando de shell", rep(t8_anchor, "\n\\! echo x\n" + t8_anchor)),
        ("sentinela condicional", rep("  raise exception using message = v_msg, errcode = v_code;", "  if v_ok then return; end if;\n  raise exception using message = v_msg, errcode = v_code;")),
        ("sentinela com código fixo", rep("v_code := case when v_ok then 'E1AOK' else 'E1ANO' end;", "v_code := 'E1AOK';")),
        ("delete real em T5", rep("-- @@T6 precheck\n", "delete from public.collection_membership;\n-- @@T6 precheck\n")),
        ("update real em corpo da T9", rep("  if current_user <> session_user then", "  update public.collection set name = 'x';\n  if current_user <> session_user then")),
        ("insert real em corpo da T6", rep("  insert into pg_temp.p1_e1a_meta (k, v) values\n    ('t_start'", "  insert into public.expansion (code) values ('x');\n  insert into pg_temp.p1_e1a_meta (k, v) values\n    ('t_start'")),
        ("sentinela falsa antes da T7", rep("  insert into pg_temp.p1_e1a_meta (k, v) values\n    ('t_start'", "  raise exception 'MSDRYRUN_E1A APROVADO {}' using errcode = 'E1AOK';\n  insert into pg_temp.p1_e1a_meta (k, v) values\n    ('t_start'")),
        ("LOCK sem NOWAIT", rep("IN ACCESS EXCLUSIVE MODE NOWAIT;", "IN ACCESS EXCLUSIVE MODE;")),
        ("LOCK em outra tabela", rep(t8_anchor, "\nLOCK TABLE public.collection IN SHARE MODE;\n" + t8_anchor)),
        ("meta-comando extra", rep("\\set VERBOSITY verbose\n", "\\set VERBOSITY verbose\n\\o /tmp/saida\n")),
        ("byte alterado numa migration", art[:seg7 + 300] + art[seg7 + 300:].replace("'VIEWER'", "'VIEWERX'", 1)),
        ("chamada externa", rep(t8_anchor, "\nselect dblink_exec('x', 'y');\n" + t8_anchor)),
        ("COMMIT escondido em EXECUTE", rep(t8_anchor, "\ndo $x$ begin execute 'commit'; end $x$;\n" + t8_anchor)),
        ("SET de sessão extra", rep(t8_anchor, "\nset statement_timeout = 0;\n" + t8_anchor)),
        ("set_config não local", rep(t8_anchor, "\ndo $y$ begin perform pg_catalog.set_config('lock_timeout', '0', false); end $y$;\n" + t8_anchor)),
        ("ordem: sentinela antes da 5888", art.replace(t8_anchor, "\n-- @@T9 sentinela\ndo $z$ begin raise exception 'MSDRYRUN_E1A x' using errcode = 'P0001'; end $z$;\n" + t8_anchor, 1)),
        ("GRANT fora das migrations", rep(t8_anchor, "\ngrant execute on function public.collection_member_role(uuid) to anon;\n" + t8_anchor)),
        ("savepoint", rep(t8_anchor, "\nsavepoint s1;\n" + t8_anchor)),
        ("FK desligada por session_replication_role (SET LOCAL)", rep(t8_anchor, "\nSET LOCAL session_replication_role = replica;\n" + t8_anchor)),
        ("FK desligada por set_config local", rep(t8_anchor, "\ndo $r$ begin perform pg_catalog.set_config('session_replication_role', 'replica', true); end $r$;\n" + t8_anchor)),
        ("SET dentro de corpo", rep(t8_anchor, "\ndo $q$ begin set local statement_timeout = 0; end $q$;\n" + t8_anchor)),
        ("orfã apagada", rep(t8_anchor, "\ndelete from pg_temp.p1_e1a_trap_child;\n" + t8_anchor)),
        ("UUID fixo/credencial", rep(t8_anchor, "\n-- postgresql://postgres:pw@host/db\n" + t8_anchor)),
    ]


def main() -> int:
    art = rb(ARTIFACT).decode("utf-8")
    s0 = rb(S0).decode("utf-8")
    results = verify(art, use_hashes=True, s0_text=s0)
    for cid, kind, ok, det in results:
        print(f"{'PASS' if ok else 'FAIL'}  {cid:<5} [{kind}] {det}")
    allok = all(ok for _, _, ok, _ in results)
    print("\nNÃO VERIFICÁVEL SEM EXECUÇÃO (fica para a S0, o ensaio e o pós-estado):")
    for x in NEEDS_EXECUTION:
        print(f"  - {x}")
    if "--no-selftest" not in sys.argv[1:]:
        print("\nAUTOTESTE DE MUTAÇÕES (hash desligado: detecção só pela estrutura):")
        caught = 0
        muts = mutations(art)
        for name, mutated in muts:
            r = verify(mutated, use_hashes=False, s0_text=None)
            failed = [cid for cid, _, ok, _ in r if not ok]
            if failed:
                caught += 1
            print(f"  {'DETECTADA' if failed else 'NÃO DETECTADA'}  {name}  {failed[:4]}")
        clean = [cid for cid, _, ok, _ in verify(art, use_hashes=False) if not ok]
        print(f"  controle sem mutação: {'limpo' if not clean else clean}")
        allok = allok and caught == len(muts) and not clean
        print(f"  {caught}/{len(muts)} mutações detectadas")
    print(f"\nGATE  {'PASS' if allok else 'FAIL'}  {sum(1 for r in results if r[2])}/{len(results)} verificações de texto")
    return 0 if allok else 1


if __name__ == "__main__":
    sys.exit(main())
