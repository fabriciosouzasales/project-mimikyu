#!/usr/bin/env python3
"""Verificação estática da P3-B S1 (5267–5270, R0, LIVE_00/90, 5860).

Não conecta em banco. Prova o gate G4: a S1 só cria objetos novos e não
recria nem altera nenhuma função ou tabela existente.

Uso: python3 static_check_p3b_s1.py   (a partir desta pasta)
Saída: uma linha por checagem e um GATE final; código de saída 0 = PASS.
"""
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
SCHEMA = HERE.parents[1] / "schema"
MIGRATIONS = ["5267_create_binder_activity_structures.sql",
              "5268_create_binder_activity_recording_functions.sql",
              "5269_create_binder_activity_reads.sql",
              "5270_create_binder_activity_purge_and_legacy.sql"]
NEW_FUNCTIONS = {"binder_activity_event_guard", "binder_activity_item_guard", "binder_activity_begin",
                 "binder_activity_add_item", "binder_activity_end", "binder_activity_category",
                 "get_my_binder_activity", "get_my_binder_activity_coverage",
                 "list_my_closed_binder_histories", "purge_my_binder_activity"}
CLIENT_READS = {"get_my_binder_activity", "get_my_binder_activity_coverage", "list_my_closed_binder_histories"}
NEW_TABLES = {"binder_activity_event", "binder_activity_item", "binder_activity_coverage", "binder_activity_setting"}

results = []


def check(cid, ok, detail):
    results.append((cid, bool(ok), detail))


def strip_comments(sql):
    sql = re.sub(r"/\*.*?\*/", "", sql, flags=re.S)
    return re.sub(r"--[^\n]*", "", sql)


texts = {m: (HERE / m).read_text(encoding="utf-8") for m in MIGRATIONS}
code = {m: strip_comments(t) for m, t in texts.items()}

# S.1 begin/commit e $-quotes balanceados
for m in MIGRATIONS:
    c = code[m]
    tags = re.findall(r"\$[a-z_]*\$", c)
    check("S.1/" + m[:4], c.strip().lower().startswith("begin;") and c.strip().lower().endswith("commit;")
          and len(tags) % 2 == 0, "begin;…commit; e delimitadores $…$ pareados")

# S.2 nenhuma recriação: sem CREATE OR REPLACE e nomes novos inexistentes no canônico
existing_fns = set()
for f in SCHEMA.glob("*.sql"):
    if f.name in MIGRATIONS:  # 5267–5270 promovidas em 2026-10-27 (README §28.35): não contam como "existentes"
        continue
    for name in re.findall(r"create\s+(?:or\s+replace\s+)?function\s+public\.([a-z0-9_]+)", f.read_text(encoding="utf-8"), flags=re.I):
        existing_fns.add(name.lower())
created = set()
for m in MIGRATIONS:
    created |= {n.lower() for n in re.findall(r"create\s+function\s+public\.([a-z0-9_]+)", code[m], flags=re.I)}
any_replace = any(re.search(r"create\s+or\s+replace", code[m], flags=re.I) for m in MIGRATIONS)
check("S.2", not any_replace and created == NEW_FUNCTIONS and not (created & existing_fns),
      f"{len(created)} funções novas, nenhuma existente no canônico, zero CREATE OR REPLACE")

# S.3 DDL só sobre tabelas novas
ddl_targets = set()
for m in MIGRATIONS:
    for kind, name in re.findall(r"(create\s+table|alter\s+table|drop\s+table|create\s+index[^\n]*?\bon|create\s+trigger[^\n]*?\bon|truncate)\s+(?:if\s+exists\s+)?(?:only\s+)?public\.([a-z0-9_]+)", code[m], flags=re.I):
        ddl_targets.add(name.lower())
check("S.3", ddl_targets and ddl_targets <= NEW_TABLES, "DDL/índices/gatilhos só nas 4 tabelas novas: " + ", ".join(sorted(ddl_targets)))

# S.4 nenhuma escrita em tabela existente (DML só em tabelas novas)
dml_targets = set()
for m in MIGRATIONS:
    for name in re.findall(r"(?:insert\s+into|update|delete\s+from)\s+public\.([a-z0-9_]+)", code[m], flags=re.I):
        dml_targets.add(name.lower())
check("S.4", dml_targets <= NEW_TABLES, "DML só nas tabelas novas: " + ", ".join(sorted(dml_targets)))

# S.5 toda função DEFINER tem search_path vazio
blocks = []
for m in MIGRATIONS:
    blocks += re.findall(r"create\s+function\s+public\.([a-z0-9_]+)\s*\((.*?)\$fn\$", code[m], flags=re.I | re.S)
ok5 = all(("set search_path = ''" in body.lower())
          and (("security definer" in body.lower()) == (name.lower() != "binder_activity_category"))
          for name, body in blocks)
check("S.5", ok5 and len(blocks) == len(NEW_FUNCTIONS),
      f"{len(blocks)} funções com search_path vazio; 9 SECURITY DEFINER; binder_activity_category é SQL pura (INVOKER)")

# S.6 revoke para todas; grant só nas 3 leituras e só para authenticated; nada para anon
all_code = "\n".join(code.values())
revoked = {n.lower() for n in re.findall(r"revoke\s+all\s+on\s+function\s+public\.([a-z0-9_]+)", all_code, flags=re.I)}
grants = re.findall(r"grant\s+execute\s+on\s+function\s+public\.([a-z0-9_]+)\([^)]*\)\s+to\s+([a-z_ ,]+);", all_code, flags=re.I)
granted = {g[0].lower() for g in grants}
check("S.6", revoked == NEW_FUNCTIONS and granted == CLIENT_READS
      and all(g[1].strip().lower() == "authenticated" for g in grants)
      and not re.search(r"grant[^;]*\banon\b", all_code, flags=re.I),
      "REVOKE nas 10; GRANT EXECUTE só nas 3 leituras e só para authenticated")

# S.7 tabelas: RLS + revoke total
for t in NEW_TABLES:
    check("S.7/" + t, re.search(rf"alter\s+table\s+public\.{t}\s+enable\s+row\s+level\s+security", all_code, flags=re.I)
          and re.search(rf"revoke\s+all\s+on\s+table\s+public\.{t}\s+from\s+public,\s*anon,\s*authenticated,\s*service_role", all_code, flags=re.I),
          "RLS ativo e REVOKE total")

# S.8 purge não liberada a clientes (O2) e porta da imutabilidade
check("S.8", re.search(r"revoke\s+all\s+on\s+function\s+public\.purge_my_binder_activity\(uuid, uuid\)\s+from\s+public,\s*anon,\s*authenticated,\s*service_role", all_code, flags=re.I)
      and "purge_my_binder_activity" not in granted
      and "mmkyu.binder_activity_purge" in code[MIGRATIONS[0]] and "mmkyu.binder_activity_purge" in code[MIGRATIONS[3]],
      "exclusão definitiva sem EXECUTE de cliente; porta do gatilho só via configuração da 5270")

# S.9 harness: nunca no LIVE + sentinela + resíduo
h = (HERE / "5860_validate_binder_activity_foundation.sql").read_text(encoding="utf-8")
check("S.9", "NUNCA executar no LIVE" in h and "MS860" in h and "'99.1'" in h and "v_expected integer := 47" in h
      and "OFICIALMENTE NÃO EXECUTADO" in h
      and all(f"'id','{i}'" in h for i in ("0.6", "0.7", "2.11", "2.12", "9.2")),
      "harness 5860 v1.1: nunca-LIVE, NÃO EXECUTADO, sentinela, resíduo zero, GATE 47 (+0.6 W8, +0.7 B1, +2.11/2.12 W1)")

# S.10 LIVE_00/90 só leitura
for f in ["LIVE_00_precheck_readonly.sql", "LIVE_90_postcheck_readonly.sql",
          "LIVE_00_precheck_readonly_v1.1.sql", "LIVE_DRYRUN_S1_gate_readonly_v1.2.sql"]:
    t = re.sub(r"'[^']*'", "''", strip_comments((HERE / f).read_text(encoding="utf-8")))
    check("S.10/" + f[:7], not re.search(r"\b(insert|update|delete|create|alter|drop|truncate|grant|revoke)\b", t, flags=re.I),
          "somente SELECT")

# S.11 reversão: só objetos novos
r0 = strip_comments((HERE / "R0_rollback_s1.sql").read_text(encoding="utf-8"))
dropped = {n.lower() for n in re.findall(r"drop\s+(?:function|table)\s+if\s+exists\s+public\.([a-z0-9_]+)", r0, flags=re.I)}
check("S.11", dropped == NEW_FUNCTIONS | NEW_TABLES, f"R0 remove exatamente os {len(dropped)} objetos novos")

# ---------------------------------------------------------------------------------------------
# v1.1 — P3-B-S1-SECURITY-CORRECTION-01
# ---------------------------------------------------------------------------------------------
c5267 = code[MIGRATIONS[0]]
c5268 = code[MIGRATIONS[1]]

# S.12 (W8) REVOKE explícito na sequência da identidade, para os 4 papéis, e conferência do nome
check("S.12", re.search(r"revoke\s+all\s+on\s+sequence\s+public\.binder_activity_event_id_seq\s+from\s+public,\s*anon,\s*authenticated,\s*service_role", c5267, flags=re.I)
      and "pg_get_serial_sequence('public.binder_activity_event', 'id')" in c5267
      and not re.search(r"grant[^;]*\bsequence\b", all_code, flags=re.I),
      "W8: REVOKE ALL na sequência da identidade (PUBLIC/anon/authenticated/service_role), nome conferido, nenhum GRANT de sequência")

# S.13 (B1) ator sem FK, sem índice próprio; guarda continua recusando todo UPDATE
actor_def = re.search(r"\bactor_user_id\s+uuid[^,]*,", c5267, flags=re.I)
guard = re.search(r"create\s+function\s+public\.binder_activity_event_guard\(\).*?\$fn\$(.*?)\$fn\$", c5267, flags=re.I | re.S)
guard_body = guard.group(1).lower() if guard else ""
check("S.13", actor_def and "references" not in actor_def.group(0).lower()
      and "ix_bae_actor" not in c5267 and "on delete set null" not in c5267.lower()
      and re.search(r"if\s+tg_op\s*=\s*'update'\s+then\s+raise", guard_body)
      and "return new" not in guard_body
      and len(re.findall(r"\breferences\s+auth\.users", c5267, flags=re.I)) == 2,
      "B1: actor_user_id sem FK nem índice; nenhuma ação SET NULL; guarda recusa todo UPDATE (sem RETURN NEW); só 2 FKs para auth.users (titular do evento e do marco)")

# S.14 (W1 v1.2) teto = capacidade + folga de repetição; recálculo em PAGE_ADDED e no excesso;
#        folga ≥ limites reais das funções homologadas que deslocam em repetição (5264, 5243)
def _const(fname, name):
    m = re.search(rf"{name}\s+constant\s+integer\s*:=\s*(\d+)", (SCHEMA / fname).read_text(encoding="utf-8"))
    return int(m.group(1)) if m else None
_slack = re.search(r"c_repeat_slack\s+constant\s+integer\s*:=\s*(\d+)", c5268)
_slack = int(_slack.group(1)) if _slack else -1
_r5264 = _const("5264_create_binder_catalog_reconciliation_internals.sql", "c_row_limit")
_i5264 = _const("5264_create_binder_catalog_reconciliation_internals.sql", "c_item_limit")
_r5243 = _const("5243_create_binder_insert_gap_functions.sql", "c_row_limit")
check("S.14", not re.search(r"v_n\s*>\s*\d+", c5268)
      and re.search(r"count\(p\.id\)\s*\*\s*\(8::bigint\s*\*\s*l\.grid_rows\s*\*\s*l\.grid_columns\s*\+\s*2\)\s*\+\s*8\s*\+\s*c_repeat_slack", c5268)
      and re.search(r"if\s+v_n\s*>\s*v_cap\s+or\s+\(p_kind\s*=\s*'PAGE'\s+and\s+p_effect\s*=\s*'PAGE_ADDED'\)\s+then", c5268)
      and "greatest(v_cap, coalesce(v_cap_now, 8 + c_repeat_slack))" in c5268
      and None not in (_r5264, _i5264, _r5243) and _slack >= _r5264 + _i5264 and _slack >= _r5243
      and "BINDER_ACTIVITY_ITEM_LIMIT" in c5268 and "'cap', 0" in c5268,
      f"W1: teto = páginas×(8×L×C+2)+8+folga {_slack} (≥ 5264 {_r5264}+{_i5264}, ≥ 5243 {_r5243}); recálculo em PAGE_ADDED e no excesso; monotônico; erro explícito")

# S.15 (W2) R0 não toca o ledger e documenta a política
r0_raw = (HERE / "R0_rollback_s1.sql").read_text(encoding="utf-8")
check("S.15", not re.search(r"(insert\s+into|update|delete\s+from|truncate|alter\s+table|drop\s+table)\s+(if\s+exists\s+)?supabase_migrations", r0, flags=re.I)
      and all(k in r0_raw for k in ("PARTIAL", "COMPLETE", "ANOMALY", "NONE", "Ledger", "MESMA numeração",
                                     "Correção para frente", "autorização específica"))
      and "ANOMALY" in r0 and "raise notice" in r0.lower(),
      "W2: R0 só lê o ledger; estados NONE/PARTIAL/COMPLETE/ANOMALY; política de numeração, forward fix e intervenção autorizada")

# ---------------------------------------------------------------------------------------------
# W3 — verificador estático do contrato de instrumentação (S2–S6). Aplicado a toda função fora
# da 5268 que chame binder_activity_begin. Na S1 não há nenhuma (vacuamente PASS); o próprio
# verificador é provado por mutações (S.16/NEG e POS) para valer nas fatias seguintes.
# ---------------------------------------------------------------------------------------------
def _plpgsql_tokens(body):
    body = strip_comments(body)
    body = re.sub(r"'(?:[^']|'')*'", "''", body)
    return re.findall(r"[A-Za-z_][A-Za-z_0-9.]*|;|\(|\)", body)


def _blocks(t):
    """Classifica BEGIN/END de bloco PL/pgSQL (ignora END IF/LOOP/CASE e END de expressão CASE).
    Retorna (lista de (abre, exception_idx|None, fecha), profundidade por índice)."""
    n = len(t)
    openers, out, case_depth, depth, depth_at = [], [], 0, 0, [0] * n
    sep_before_begin = (";", "then", "else", "loop", "declare", "as", "begin")
    for j, x in enumerate(t):
        nxt = t[j + 1] if j + 1 < n else ""
        prv = t[j - 1] if j > 0 else ";"
        if x == "case" and prv != "end":
            case_depth += 1
        elif x == "begin" and prv in sep_before_begin:
            openers.append([j, None])
            depth += 1
        elif x == "exception" and openers and prv in (";", "begin"):
            openers[-1][1] = j
        elif x == "end":
            if nxt in ("if", "loop"):
                pass
            elif nxt == "case":
                case_depth -= 1
            elif case_depth > 0:
                case_depth -= 1
            elif openers:
                o, e = openers.pop()
                out.append((o, e, j))
                depth -= 1
        depth_at[j] = depth
    return out, depth_at


def w3_violations(body):
    """Regras I-1..I-6 do contrato W3 (README §20). Retorna lista de violações."""
    t = [x.lower() for x in _plpgsql_tokens(body)]
    v = []
    blocks, depth_at = _blocks(t)
    regions = [(o, e, c) for (o, e, c) in blocks if e is not None]
    BEGIN = ("binder_activity_begin", "public.binder_activity_begin")
    ADD = ("binder_activity_add_item", "public.binder_activity_add_item")
    END = ("binder_activity_end", "public.binder_activity_end")

    begins = []
    for j, x in enumerate(t):
        prot = [r for r in regions if r[0] < j < r[1]]
        hand = [r for r in regions if r[1] < j < r[2]]
        if x in BEGIN:
            begins.append((j, depth_at[j], bool(hand)))
        if x in ADD:
            for r in prot + hand:
                if "raise" not in t[r[1]:r[2]]:
                    v.append("I-4 add_item em bloco cujo EXCEPTION engole o erro (sem RAISE)")
                    break
    # statements: separa em ';' e depois de then/else/loop/begin/declare
    stmts, cur = [], []
    for j, x in enumerate(t):
        cur.append((j, x))
        if x in (";", "then", "else", "loop", "begin", "declare"):
            stmts.append(cur)
            cur = []
    if cur:
        stmts.append(cur)

    # I-1: exatamente um begin, no bloco externo; I-3: nunca em handler
    if len(begins) != 1:
        v.append(f"I-1 esperado exatamente 1 binder_activity_begin, encontrado {len(begins)}")
    for (j, d, in_h) in begins:
        if d != 1:
            v.append("I-1 begin fora do bloco externo da função")
        if in_h:
            v.append("I-3 begin dentro de handler EXCEPTION")
    # I-2: toda saída depois do begin é precedida imediatamente por end
    if begins:
        bj = begins[0][0]
        prev = None
        for s in stmts:
            toks = [x for _, x in s]
            if toks[:1] == ["return"] and (len(toks) < 2 or toks[1] not in ("query", "next")) and s[0][0] > bj:
                if not prev or not any(x in END for x in prev):
                    v.append("I-2 RETURN depois do begin sem binder_activity_end imediatamente antes")
            prev = toks
        real = [[x for _, x in s] for s in stmts]
        real = [s for s in real if s not in (["end", ";"],) and s[-1:] != ["begin"] and s[-1:] != ["declare"]]
        tail = real[-1] if real else []
        if tail and tail[:1] != ["return"] and not any(x in END for x in tail):
            v.append("I-2 fim do corpo sem binder_activity_end (caminho de queda)")
        if not any(x in END for x in t):
            v.append("I-2 nenhum binder_activity_end")
    # I-5: gravação só via add_item
    if re.search(r"insert\s+into\s+public\.binder_activity_(event|item)", strip_comments(body), flags=re.I):
        v.append("I-5 INSERT direto em binder_activity_event/item")
    # I-6: contexto só pela 5268
    if re.search(r"mmkyu\.binder_activity_ctx", strip_comments(body), flags=re.I):
        v.append("I-6 acesso direto ao contexto mmkyu.binder_activity_ctx")
    return v


W3_POS = """
declare v int;
begin
  if p_noop then
    return;                                   -- caminho idempotente antes do begin: permitido
  end if;
  perform public.binder_activity_begin(p_layout, 'CARD_MOVED', 'FICHARIO');
  begin
    update public.collection_layout_slot set x = 1 where id = p_slot;
    perform public.binder_activity_add_item('CARD', 'MOVED', p_card, null, p_from, p_to);
  exception when unique_violation then
    raise;                                     -- re-lança: nada se perde
  end;
  if v is null then
    perform public.binder_activity_end();
    return;
  end if;
  for r in select 1 loop
    return next;
  end loop;
  perform public.binder_activity_end();
end;
"""
W3_NEG = {
    "sem end antes do return": W3_POS.replace("    perform public.binder_activity_end();\n    return;", "    return;"),
    "begin em handler": W3_POS.replace("    raise;", "    perform public.binder_activity_begin(p_layout, 'X', 'FICHARIO');"),
    "handler engole add_item": W3_POS.replace("    raise;", "    null;"),
    "dois begins": W3_POS.replace("  begin\n    update", "  perform public.binder_activity_begin(p_layout, 'X', 'FICHARIO');\n  begin\n    update"),
    "insert direto": W3_POS.replace("    update public.collection_layout_slot set x = 1 where id = p_slot;",
                                    "    insert into public.binder_activity_event (owner_user_id) values (p_owner);"),
    "contexto direto": W3_POS.replace("declare v int;", "declare v int := current_setting('mmkyu.binder_activity_ctx', true);"),
    "queda sem end": W3_POS.rstrip().removesuffix("perform public.binder_activity_end();\nend;") + "end;",
}
pos_v = w3_violations(W3_POS)
neg_ok = {k: bool(w3_violations(s)) for k, s in W3_NEG.items()}
check("S.16/POS", not pos_v, "W3: controle positivo (return antecipado, bloco com RAISE, RETURN NEXT, end antes de cada saída) sem violações" + (f" {pos_v}" if pos_v else ""))
for k, ok in neg_ok.items():
    check("S.16/NEG", ok, f"W3: mutação detectada — {k}")

# S.17 aplicação do contrato W3 às migrations da S1 (e a futuras S2–S6 neste diretório)
instrumented = []
for f in sorted(HERE.glob("*.sql")):
    if f.name == MIGRATIONS[1]:
        continue
    for name, body in re.findall(r"create\s+(?:or\s+replace\s+)?function\s+public\.([a-z0-9_]+)\s*\(.*?\$fn\$(.*?)\$fn\$",
                                 strip_comments(f.read_text(encoding="utf-8")), flags=re.I | re.S):
        if re.search(r"binder_activity_begin\s*\(", body, flags=re.I):
            instrumented.append((f.name, name, w3_violations(body)))
ctx_outside = [m for m in MIGRATIONS if m != MIGRATIONS[1] and "mmkyu.binder_activity_ctx" in code[m]]
check("S.17", all(not vv for _, _, vv in instrumented) and not ctx_outside,
      f"W3 aplicado: {len(instrumented)} função(ões) instrumentada(s) na S1 (esperado 0); contexto só na 5268")

# S.18 ensaio LIVE v2.0 — estrutura transacional verificada com o lexer (NÃO é parser)
import importlib.util as _ilu
import sql_lexer_p3b as _lex
_spec = _ilu.spec_from_file_location("build_live_dryrun_s1", HERE / "build_live_dryrun_s1.py")
_bld = _ilu.module_from_spec(_spec)
_spec.loader.exec_module(_bld)

TX_WORDS = {"begin", "commit", "end", "rollback", "abort", "savepoint", "release", "start", "prepare"}
FORBIDDEN_IN_TX = re.compile(r"\bconcurrently\b|\bvacuum\b|\bcreate\s+database\b|\balter\s+system\b|\bcreate\s+tablespace\b|\bdrop\s+database\b", re.I)
DDL_IN_DO = re.compile(r"\b(create|alter|drop|grant|revoke|comment|commit|rollback|savepoint|vacuum)\b", re.I)


def dryrun_violations(text):
    """Regras D-1..D-9 do ensaio. Retorna lista de violações (vazia = conforme)."""
    v = []
    try:
        st = _lex.split_statements(text)
    except _lex.LexError as e:
        return [f"D-0 erro léxico: {e}"]
    heads = [x.words for x in st]
    # D-1 prólogo exato: SET SESSION read-only → BEGIN → SET TRANSACTION READ WRITE → 4 SET LOCAL
    exp = [["set", "session", "default_transaction_read_only"], ["begin"], ["set", "transaction", "read", "write"]]
    if [h[:len(e)] for h, e in zip(heads[:3], exp)] != exp or heads[1] != ["begin"]:
        v.append("D-1 prólogo fora da ordem (T0 SET SESSION read-only, T1 BEGIN, T2 SET TRANSACTION READ WRITE)")
    locals_ = [h[2] for h in heads[3:7] if h[:2] == ["set", "local"]]
    if sorted(locals_) != sorted(["statement_timeout", "lock_timeout", "idle_in_transaction_session_timeout", "transaction_timeout"]):
        v.append("D-1 limites SET LOCAL ausentes (statement/lock/idle/transaction)")
    # D-2 controle de transação: exatamente 1 BEGIN (posição 1) e 1 ROLLBACK (penúltimo); nenhum outro
    tx = [(i, h) for i, h in enumerate(heads) if h and h[0] in TX_WORDS and not (h[0] == "start" and h[1:2] != ["transaction"])]
    if [(i, h[0]) for i, h in tx] != [(1, "begin"), (len(st) - 2, "rollback")]:
        v.append(f"D-2 controle de transação inesperado: {[(i, ' '.join(h[:2])) for i, h in tx]}")
    if not (heads and heads[-1][:2] == ["reset", "default_transaction_read_only"]):
        v.append("D-2 último statement deve ser RESET default_transaction_read_only")
    if any(h[:2] == ["set", "constraints"] for h in heads):
        v.append("D-2 SET CONSTRAINTS proibido (desarmaria a trava)")
    # D-3 trava de COMMIT: FK DEFERRABLE INITIALLY DEFERRED violada antes de qualquer migration
    veto = [i for i, x in enumerate(st) if re.search(r"references\s+mmkyu_dryrun_veto_parent\s*\(id\)\s+deferrable\s+initially\s+deferred", x.code, re.I)]
    ins = [i for i, x in enumerate(st) if re.match(r"insert\s+into\s+mmkyu_dryrun_veto_child", x.text, re.I)]
    first_mig = next((i for i, x in enumerate(st) if x.text.lower().startswith("do $pre$")), None)
    if not veto or not ins or first_mig is None or not (veto[0] < ins[0] < first_mig):
        v.append("D-3 trava de COMMIT ausente ou depois da primeira migration")
    if any(re.search(r"\b(delete\s+from|truncate|drop\s+table|update)\s+(pg_temp\.)?mmkyu_dryrun_veto", x.code, re.I) for x in st):
        v.append("D-3 statement que remove/altera a trava")
    # D-4 migrations no nível superior, idênticas às aprovadas, em ordem, sem BEGIN/COMMIT próprios
    mig = []
    for src in _bld.SOURCES:
        ss = _lex.split_statements((HERE / src).read_text(encoding="utf-8"))
        mig += [x.text for x in ss[1:-1]]
    texts = [x.text for x in st]
    found = None
    for i in range(len(texts) - len(mig) + 1):
        if texts[i:i + len(mig)] == mig:
            found = i
            break
    if found is None:
        v.append("D-4 sequência das migrations 5267–5270 não aparece no nível superior, idêntica e em ordem")
    # D-5 DO do ensaio: só verificação (fora do trecho das migrations)
    mig_range = range(found, found + len(mig)) if found is not None else range(0)
    own_do = [i for i, x in enumerate(st) if x.words[:1] == ["do"] and i not in mig_range]
    for i in own_do:
        body = _lex.dollar_body(st[i].text) or ""
        body_code = re.sub(r"'(?:[^']|'')*'", "''", re.sub(r"--[^\n]*", "", body))
        if DDL_IN_DO.search(body_code):
            v.append(f"D-5 DO do ensaio (statement {i}) contém DDL/controle de transação")
    if found is not None and any(i > found and i < found + len(mig) for i in own_do):
        v.append("D-5 DO do ensaio intercalado nas migrations")
    # D-6 precheck antes, postcheck/sondas/sentinela depois das migrations; sentinela sempre levanta MSDRYRUN
    if found is not None:
        before = [i for i in own_do if i < found]
        after = [i for i in own_do if i >= found + len(mig)]
        if len(before) != 1 or len(after) != 3:
            v.append("D-6 esperado 1 DO antes (precheck) e 3 depois (postcheck, sondas, sentinela)")
        elif not re.search(r"raise\s+exception\s+'MSDRYRUN %'", _lex.dollar_body(st[after[-1]].text) or "", re.I) \
                or after[-1] != len(st) - 3:
            v.append("D-6 a sentinela MSDRYRUN deve ser o statement imediatamente anterior ao ROLLBACK")
    # D-7 nada proibido em bloco de transação
    if any(FORBIDDEN_IN_TX.search(x.code) for x in st):
        v.append("D-7 comando não permitido dentro de bloco de transação")
    # D-8 sem ledger, sem usuários/catálogo/eventos sintéticos
    if re.search(r"(insert\s+into|update|delete\s+from)\s+(supabase_migrations|auth\.users)|generate_series", "\n".join(x.code for x in st), re.I):
        v.append("D-8 escrita em ledger/auth.users ou geração sintética")
    # D-9 limites
    if not re.search(r"set\s+local\s+lock_timeout\s*=\s*'2s'", text, re.I):
        v.append("D-9 lock_timeout de 2 s ausente")
    return v


_dry = _bld.OUT.read_text(encoding="utf-8")
check("S.18a", _dry == _bld.build(), f"ensaio {_bld.OUT.name} gerado byte a byte das 5267–5270 e do LIVE_90 atuais (build_live_dryrun_s1.py --check)")
_dv = dryrun_violations(_dry)
check("S.18b", not _dv, "ensaio conforme D-0..D-9 (léxico, prólogo, 1 BEGIN/1 ROLLBACK, trava de COMMIT, migrations no nível superior e idênticas, DO só verificação, sentinela, sem ledger/sintéticos, lock 2 s)" + (f" {_dv}" if _dv else ""))
for _s in _bld.SOURCES:
    _ss = _lex.split_statements((HERE / _s).read_text(encoding="utf-8"))
    check("S.18c/" + _s[:4], _ss[0].words == ["begin"] and _ss[-1].words == ["commit"]
          and sum(1 for x in _ss if x.words[:1] and x.words[0] in TX_WORDS) == 2
          and not any(FORBIDDEN_IN_TX.search(x.code) for x in _ss),
          f"{_s[:4]}: {len(_ss)} statements; só BEGIN/COMMIT de borda; nada proibido em transação")

# S.18d mutações do verificador do ensaio (cada uma precisa ser detectada)
_MUT = {
    "COMMIT no lugar do ROLLBACK": _dry.replace("\nrollback;\n", "\ncommit;\n"),
    "COMMIT extra após a sentinela": _dry.replace("\nrollback;\n", "\ncommit;\nrollback;\n"),
    "sem a trava de COMMIT": _dry.replace("insert into mmkyu_dryrun_veto_child (parent_id) values (1);\n", ""),
    "SET CONSTRAINTS ALL IMMEDIATE": _dry.replace("-- T5 evidência", "set constraints all immediate;\n-- T5 evidência"),
    "sem guarda de autocommit": _dry.replace("set session default_transaction_read_only = on;\n", ""),
    "migrations dentro de DO (defeito v1.0)": None,
    "migration alterada": _dry.replace("revoke all on sequence public.binder_activity_event_id_seq", "grant all on sequence public.binder_activity_event_id_seq", 1),
    "sentinela removida": re.sub(r"do \$dry_end\$.*?\$dry_end\$;\n", "", _dry, flags=re.S),
    "delimitador dólar sem fechamento": _dry.replace("end;\n$dry_end$;", "end;\n$dry_ond$;", 1),
    "comentário fechado cedo no cabeçalho (*/)": _dry.replace("pg_stat_* e pg_stat_statements", "pg_stat_*/pg_stat_statements", 1),
}
_i0 = _dry.index("-- T7 migrations"); _i1 = _dry.index("-- T8a postcheck")
_MUT["migrations dentro de DO (defeito v1.0)"] = _dry[:_i0] + "do $wrap$ begin\n" + _dry[_i0:_i1] + "end $wrap$;\n" + _dry[_i1:]
for _k, _t in _MUT.items():
    check("S.18d", bool(dryrun_violations(_t)), f"mutação detectada — {_k}")

# S.18e v2.1 preservada como evidência histórica (executada em 2026-10-26; não aprovada)
import hashlib as _hl
_v21 = HERE / "LIVE_DRYRUN_S1_rollback.sql"
check("S.18e", _v21.exists() and _hl.sha256(_v21.read_bytes()).hexdigest()
      == "ddd0dbf2ef5346f5c3536d8b2d1d62ee3eab1cbc5ecc9d732d9a598e1322f74b" and _bld.OUT != _v21,
      "v2.1 intacta (SHA ddd0dbf2…) e distinta do arquivo gerado")

# S.19 (v2.2) conjunto canônico das funções da S1: migrations = NEW_FUNCTIONS = LIVE_90 (fns) = T8a do ensaio
_created = set()
for _m in MIGRATIONS:
    for _x in _lex.split_statements((HERE / _m).read_text(encoding="utf-8")):
        _mm = re.match(r"create\s+(?:or\s+replace\s+)?function\s+public\.([a-z0-9_]+)\s*\(", _x.text, re.I)
        if _mm:
            _created.add(_mm.group(1).lower())
_canon = _bld.canonical_functions()
check("S.19a", _created == NEW_FUNCTIONS == set(_canon) and len(_canon) == len(_created) == 10,
      f"conjunto único: {len(_created)} funções criadas = NEW_FUNCTIONS = lista fns do LIVE_90")


def postcheck_violations(text):
    """P-1..P-5 do T8a: identificação das funções só pela lista canônica do LIVE_90."""
    v = []
    try:
        st = _lex.split_statements(text)
    except _lex.LexError as e:
        return [f"P-0 erro léxico: {e}"]
    posts = [x for x in st if x.text.lower().startswith("do $dry_post$")]
    if len(posts) != 1:
        return ["P-0 bloco T8a ($dry_post$) ausente ou duplicado"]
    body = _lex.dollar_body(posts[0].text) or ""
    code = re.sub(r"--[^\n]*", "", body)
    decl = re.findall(r"v_fns\s+text\[\]\s*:=\s*array\[([^\]]*)\]", code, re.I)
    if len(decl) != 1:
        v.append("P-1 esperado exatamente uma declaração v_fns text[] := array[...]")
    elif set(re.findall(r"'([a-z0-9_]+)'", decl[0])) != set(_canon) or len(re.findall(r"'([a-z0-9_]+)'", decl[0])) != len(_canon):
        v.append("P-1 v_fns difere da lista fns do LIVE_90")
    if len(re.findall(r"array\[\s*'binder_activity_begin'", code)) > 1 or re.search(r"proname\s+in\s*\(\s*'binder_activity_begin'", code):
        v.append("P-2 lista de funções duplicada no T8a")
    if re.search(r"proname\s+(not\s+)?(i?like|~)", code, re.I):
        v.append("P-3 identificação por padrão de nome (like/~) no T8a")
    items = {k: m for k, m in re.findall(r"'(90\.\d+)',\s*(.*?)(?=,\s*'90\.\d+',|\);\s*insert)", code, re.S)}
    for k in ("90.3", "90.4"):
        if "p.proname = any(v_fns)" not in items.get(k, ""):
            v.append(f"P-4 {k} não restringe o conjunto por any(v_fns)")
    if "count(*) = cardinality(v_fns)" not in items.get("90.3", "") or re.search(r"count\(\*\)\s*=\s*\d", items.get("90.3", "")):
        v.append("P-4 90.3 deve comparar com cardinality(v_fns), sem contagem literal")
    if "not (p.proname = any(v_fns))" not in items.get("90.10", ""):
        v.append("P-5 90.10 não exclui exatamente o conjunto canônico")
    return v


_pv = postcheck_violations(_dry)
check("S.19b", not _pv, "T8a: 90.3/90.4/90.10 usam só a lista canônica (1 declaração, sem like, sem contagem literal)" + (f" {_pv}" if _pv else ""))
_one = "'list_my_closed_binder_histories', "
_PMUT = {
    "função omitida da lista (defeito v2.1)": _dry.replace(_one, "", 1),
    "função a mais na lista": _dry.replace("array['binder_activity_begin',", "array['binder_activity_begin', 'binder_activity_extra',", 1),
    "90.3 volta a like": _dry.replace("and p.proname = any(v_fns)),\n    '90.4'", "and p.proname like '%binder_activity%'),\n    '90.4'", 1),
    "90.3 com contagem literal": _dry.replace("count(*) = cardinality(v_fns)", "count(*) = 10", 1),
    "90.10 volta a not like": _dry.replace("not (p.proname = any(v_fns))", "p.proname not like '%binder_activity%'", 1),
    "lista duplicada no 90.4": _dry.replace("and p.proname = any(v_fns)),\n    '90.5'", "and p.proname in ('binder_activity_begin')),\n    '90.5'", 1),
}
for _k, _t in _PMUT.items():
    check("S.19c", _t != _dry and bool(postcheck_violations(_t)), f"mutação detectada — {_k}")

# S.18f v2.2 preservada (preparada, nunca executada; substituída pela v2.3 — baseline MEP)
_v22 = HERE / "LIVE_DRYRUN_S1_rollback_v2.2.sql"
check("S.18f", _v22.exists() and _hl.sha256(_v22.read_bytes()).hexdigest()
      == "ece95392c0af14e35f690f544d8a3e524561d93a31f9c656a0653413c4757e40" and _bld.OUT != _v22,
      "v2.2 intacta (SHA ece95392…) e distinta do arquivo gerado")

# S.20 (MEP-01) baseline do ledger: builder (fonte) = LIVE_00 v1.1 (00.1) = T6 do ensaio = gate v1.2 (Q.02)
_BV, _BN = _bld.LEDGER_BASELINE
_BASE = f"{_BV}|{_BN}"
_OLD = "5266_create_binder_catalog_reconciliation_apply"
_CURRENT = {"LIVE_00 v1.1": "LIVE_00_precheck_readonly_v1.1.sql",
            "gate v1.2": "LIVE_DRYRUN_S1_gate_readonly_v1.2.sql"}


def _sql_code(text):
    """Remove comentários (-- e /* */); mantém literais."""
    return re.sub(r"--[^\n]*", "", re.sub(r"/\*.*?\*/", "", text, flags=re.S))


def baseline_violations(texts):
    """texts: {'LIVE_00 v1.1': sql, 'gate v1.2': sql, 'ensaio': sql}."""
    v = []
    if not re.fullmatch(r"\d{14}", _BV) or _BN != "fix_mep_bootstrap_preserve_confirmed_primary_identity" or _BV != "20261026124224":
        v.append("B-0 baseline do builder diferente do aprovado (20261026124224 / fix_mep_bootstrap_preserve_confirmed_primary_identity)")
    for k, t in texts.items():
        code = _sql_code(t)
        lits = re.findall(r"'(\d{14}\|[a-z0-9_]+)'", code)
        if lits != [_BASE]:
            v.append(f"B-1 {k}: esperado exatamente um literal de baseline '{_BASE}', encontrado {lits}")
        if _OLD in code:
            v.append(f"B-2 {k}: referência executável ao baseline antigo 5266")
        if "version || '|' || name from supabase_migrations.schema_migrations order by version desc limit 1" not in code:
            v.append(f"B-3 {k}: comparação não usa versão e nome da última migration")
        if "where name ~ '^(5267|5268|5269|5270)_'" not in code:
            v.append(f"B-4 {k}: controle de numeração 5267–5270 livre ausente")
        if re.search(r"version\s*[>]=?\s*'5266|name\s*>\s*'5266", code):
            v.append(f"B-5 {k}: comparação genérica de ordem em vez de igualdade exata")
    return v


_btexts = {k: (HERE / f).read_text(encoding="utf-8") for k, f in _CURRENT.items()}
_btexts["ensaio"] = _dry
_bv = baseline_violations(_btexts)
check("S.20a", not _bv, f"baseline único {_BASE} em LIVE_00 v1.1, T6 do ensaio e gate v1.2; sem 5266 executável; 5267–5270 livres preservado" + (f" {_bv}" if _bv else ""))
_l00 = _btexts["LIVE_00 v1.1"]
_BMUT = {
    "LIVE_00 com versão divergente": dict(_btexts, **{"LIVE_00 v1.1": _l00.replace("'20261026124224|", "'20261026124225|", 1)}),
    "gate volta ao 5266": dict(_btexts, **{"gate v1.2": _btexts["gate v1.2"].replace(f"'{_BASE}'", f"'{_OLD}'", 1)}),
    "T6 sem o nome (só versão)": dict(_btexts, ensaio=_dry.replace(f"'{_BASE}'", f"'{_BV}'", 1)),
    "LIVE_00 sem controle 5267–5270": dict(_btexts, **{"LIVE_00 v1.1": _l00.replace("where name ~ '^(5267|5268|5269|5270)_'", "where false", 1)}),
    "T6 genérico (versão > 5266)": dict(_btexts, ensaio=_dry.replace(f"<> '{_BASE}'", "<= '5266'", 1)),
}
for _k, _t in _BMUT.items():
    check("S.20b", bool(baseline_violations(_t)), f"mutação detectada — {_k}")
# Limite de S.20: coerência estática dos instrumentos; o estado real do ledger só é comprovado pelo LIVE_00 no LIVE.

width = max(len(c) for c, _, _ in results)
fails = 0
for cid, ok, detail in results:
    fails += 0 if ok else 1
    print(f"{cid:<{width}}  {'PASS' if ok else 'FAIL'}  {detail}")
print(f"{'GATE':<{width}}  {'PASS' if fails == 0 else 'FAIL'}  {len(results) - fails}/{len(results)} PASS")
sys.exit(0 if fails == 0 else 1)
