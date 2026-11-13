#!/usr/bin/env python3
"""
V1-16 · CONTROLLED EXECUTION READINESS-01 — derivação dos harnesses de chamada única.

Não altera nenhum arquivo de origem. Gera, a partir de 5887 / 5822 / 5826, cópias
de CHAMADA ÚNICA cujo relatório final sai por RAISE EXCEPTION (ERRCODE 55000):
a transação é abortada por construção e nenhum COMMIT existe no arquivo.

Transformações permitidas (e só estas):
  1. remover grupos inteiros do 5887 ainda não aplicáveis (recortes S1/S2/S3);
  2. substituir o bloco "RELATÓRIO FINAL ... ROLLBACK;" por um DO que levanta
     o relatório com o MESMO gate (count(*) = N AND fail = 0);
  3. substituir o cabeçalho por um cabeçalho de derivação com o SHA-256 da origem.
Todo o restante é copiado byte a byte; o script verifica isso e falha se não for.

Uso: python3 derive_singlecall.py          (gera e imprime o manifesto)
     python3 derive_singlecall.py --check  (só confere que os derivados batem)
"""
import hashlib, pathlib, re, sys

HERE = pathlib.Path(__file__).resolve().parent
PROP = HERE.parent
ROOT = PROP.parent
SRC_5887 = PROP / "5887_validate_physical_card_condition_HARNESS.sql"
SRC_5822 = ROOT / "2026-09-08-bulk-02-register-physical-cards" / "5822_validate_register_physical_cards_bulk.sql"
SRC_5826 = ROOT / "2026-10-16-bulk-04-register-card-set" / "5826_validate_register_card_set_bulk.sql"

def sha(b): return hashlib.sha256(b).hexdigest()

def read(p):
    b = p.read_bytes()
    t = b.decode("utf-8")
    nl = "\r\n" if "\r\n" in t else "\n"
    return b, t.split(nl), nl

def find(lines, pat, start=0, last=False):
    idx = [i for i, l in enumerate(lines) if re.match(pat, l) and i >= start]
    if not idx: raise SystemExit(f"marcador não encontrado: {pat}")
    return idx[-1] if last else idx[0]

def report_block(tag, gate):
    return f"""-- ================================================================
-- RELATÓRIO FINAL — CHAMADA ÚNICA (derivado): RAISE EXCEPTION aborta a
-- transação por construção. Gate idêntico ao da origem: count(*) = {gate} AND fail = 0.
-- ================================================================
DO $REPORT$
DECLARE v_total INT; v_pass INT; v_fail INT; v_gate BOOLEAN; v_bl TEXT; v_failing TEXT;
BEGIN
    SELECT count(*), count(*) FILTER (WHERE passed), count(*) FILTER (WHERE NOT passed)
      INTO v_total, v_pass, v_fail FROM _r;
    v_gate := (v_total = {gate} AND v_fail = 0);
    SELECT string_agg(k || '=' || n, ' ' ORDER BY k) INTO v_bl FROM _bl;
    SELECT string_agg(format('%s | %s' || E'\\n      got : %s' || E'\\n      want: %s',
                             grp, label, coalesce(got, '<null>'), coalesce(want, '<null>')),
                      E'\\n' ORDER BY grp, label)
      INTO v_failing FROM _r WHERE NOT passed;
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = format(
        E'\\n============== {tag} — CHAMADA ÚNICA ==============\\n'
        'TOTAL=%s  PASS=%s  FAIL=%s  NOT PROVEN=0\\n'
        'GATE ESPERADO: {gate}/{gate}/0/0   ->   GATE_OK = %s\\n'
        'BASELINE: %s\\n'
        'FALHAS:\\n%s\\n'
        'ROLLBACK GARANTIDO POR CONSTRUÇÃO (esta exceção aborta a transação).\\n'
        '==============================================================',
        v_total, v_pass, v_fail, v_gate, v_bl, coalesce(v_failing, '(nenhuma)'));
END;
$REPORT$;

ROLLBACK;"""

def header(tag, src, src_sha, gate, groups, origin_header_end):
    return f"""/*
================================================================
DERIVADO — NÃO EDITAR À MÃO (gerado por controlled-execution/derive_singlecall.py)
Harness....: {tag}
Origem.....: {src.relative_to(ROOT.parent).as_posix()}
SHA-256 origem: {src_sha}
Grupos.....: {groups}
Gate.......: TOTAL {gate} / PASS {gate} / FAIL 0 / NOT PROVEN 0
Transporte.: CHAMADA ÚNICA. O relatório chega como ERRO 55000 (RAISE
             EXCEPTION). Erro 55000 com GATE_OK = true é o resultado de
             SUCESSO. Não existe COMMIT neste arquivo.
Canal......: psql -X -v ON_ERROR_STOP=1 -f <arquivo>  (ver
             CONTROLLED-EXECUTION-PROTOCOL.md). NUNCA apply_migration.
             NUNCA SQL Editor do Supabase.
Cabeçalho original (linhas 1–{origin_header_end + 1}) omitido; leia-o na origem.
================================================================
*/"""

def check_no_commit(lines, name):
    for l in lines:
        if re.match(r"^\s*COMMIT\s*;", l, re.I) or re.match(r"^\s*END\s+TRANSACTION", l, re.I):
            raise SystemExit(f"{name}: COMMIT encontrado — abortado")
    tops = [l for l in lines if re.match(r"^(BEGIN|ROLLBACK)\s*;\s*$", l)]
    if tops != ["BEGIN;", "ROLLBACK;"]:
        raise SystemExit(f"{name}: controle de transação inesperado: {tops}")

def derive_5887():
    b, L, nl = read(SRC_5887)
    s = sha(b)
    hdr_end = find(L, r"^\*/\s*$")
    begin = find(L, r"^BEGIN;\s*$")
    gB = find(L, r"^-- GRUPO B ") - 1
    gC = find(L, r"^-- GRUPO C ") - 1
    gD = find(L, r"^-- GRUPO D ") - 1
    x2 = find(L, r"^-- X02 ") - 1
    rep = find(L, r"^-- RELATORIO FINAL") - 1
    rb = find(L, r"^ROLLBACK;\s*$", last=True)
    for i in (gB, gC, gD, x2, rep):
        assert re.match(r"^-- =+$", L[i]), (i, L[i])
    infra = L[begin:gB]          # BEGIN, infraestrutura, X01, F, A
    B, C, D, X2 = L[gB:gC], L[gC:gD], L[gD:x2], L[x2:rep]
    tail = L[rb + 1:]           # comentário da CALL 3
    cuts = {
        "S1": (9,  "X01 + F + A",            infra),
        "S2": (34, "X01 + F + A + B + X02",  infra + B + X2),
        "S3": (41, "X01 + F + A + B + C + X02", infra + B + C + X2),
        "S4": (66, "completo (X + F + A + B + C + D)", infra + B + C + D + X2),
    }
    out = {}
    for k, (gate, groups, body) in cuts.items():
        # verificação byte a byte: cada linha do corpo existe na origem, na mesma ordem
        it = iter(L)
        assert all(any(line == x for x in it) for line in body), f"5887 {k}: corpo não é subsequência da origem"
        lines = header(f"5887 recorte {k}", SRC_5887, s, gate, groups, hdr_end).split("\n") + [""] + body + \
                report_block(f"5887 {k}", gate).split("\n") + tail
        check_no_commit(lines, f"5887_{k}")
        out[f"5887_{k}_singlecall.sql"] = nl.join(lines)
    return out

def derive_legacy(src, tag, gate):
    b, L, nl = read(src)
    s = sha(b)
    hdr_end = find(L, r"^\*/\s*$")
    begin = find(L, r"^BEGIN;\s*$")
    rep = find(L, r"^-- RELAT(Ó|O)RIO FINAL") - 1
    rb = find(L, r"^ROLLBACK;\s*$", last=True)
    assert re.match(r"^-- =+$", L[rep]), L[rep]
    body = L[begin:rep]
    # o SELECT final da origem precisa ter exatamente este gate
    final = "\n".join(L[rep:rb + 1])
    assert re.search(rf"count\(\*\)\s*=\s*{gate}\s+AND", final), f"{tag}: gate {gate} não encontrado no relatório da origem"
    lines = header(tag, src, s, gate, "todos (sem recorte)", hdr_end).split("\n") + [""] + L[begin:rep] + \
            report_block(tag, gate).split("\n") + L[rb + 1:]
    check_no_commit(lines, tag)
    return {f"{tag}_singlecall.sql": nl.join(lines)}


# ======================================================================
# RECUPERAÇÃO (R4 → R1) — derivada dos corpos CANÔNICOS de database/schema.
# Necessária porque a recuperação "reaplicar database/schema/…" do README
# não funciona: 5153/5157 usam CREATE FUNCTION (falharia: já existe) e o
# precheck da 5262 exige o corpo da 5162 (falharia: assinatura ausente).
# ======================================================================
SCHEMA = ROOT.parent / "schema"
OLD = {"5153": "a5fd5107cc008b68a6d598a1a0501a6e", "5155": "0b7221b6a2485ad75e2918365f515e0a",
       "5157": "1526fd4d633f29f91ddc5c49141eef59", "5158": "8dcf2656676739b5417b94b4882bd26c",
       "5262": "d8cce43b511856a5e25f061e75a7cede"}
NEW = {"5153": "86426fc066009400748cfccdf1fbf322", "5155": "d08dcc259222a286d99bcd53f9da7285",
       "5157": "83cd76fcb38a41a3a2c0a77d36fa4196", "5158": "99f7b2e2a723d599e06ef2e7ca9b1831",
       "5363": "77abbb9a33f2cb46280925bade22dee5", "5364": "b569ecdbe202428a6bdc9461c6d62e37"}
SIG = {"5153": "public.bulk_register_physical_card_items(jsonb,uuid,uuid,uuid,text,uuid,text,text,uuid,bigint)",
       "5155": "public.register_physical_cards_bulk(jsonb)",
       "5157": "public.register_card_set_bulk(jsonb)",
       "5158": "public.preview_bulk_operation(jsonb)"}
COLS20 = ("TABLE(card_variant_id uuid, language_code text, language_name text, card_name text, collector_number text, "
          "collector_total integer, card_set_code text, card_set_name text, is_default_variant boolean, variant_label text, "
          "image_path text, copies_total integer, physical_card_id uuid, copy_number integer, added_at timestamp with time zone, "
          "collection_id uuid, collection_name text, storage_name text, variant_type_code text, rarity_code text)")
COLS21 = COLS20[:-1] + ", condition_code text)"
GMIC = "public.get_my_inventory_item_copies(uuid,text)"
SCMC = "public.set_my_physical_cards_condition(uuid[],text)"
VAL = "public.physical_card_unknown_condition_codes(text[])"

def schema_file(prefix):
    f = sorted(SCHEMA.glob(prefix + "_*.sql"))
    assert len(f) == 1, prefix
    return f[0]

def between_tx(path):
    b, L, nl = read(path)
    i = find(L, r"^(BEGIN|begin);\s*$")
    j = find(L, r"^(COMMIT|commit);\s*$", last=True)
    return sha(b), L[i + 1:j]

def rhead(tag, what, sources):
    src = "\n".join(f"  {pth.relative_to(ROOT.parent.parent).as_posix()}  sha256 {h}" for pth, h in sources) or "  (nenhum corpo copiado)"
    return f"""/*
================================================================
RECUPERAÇÃO {tag} — DERIVADO, NÃO EDITAR À MÃO (controlled-execution/derive_singlecall.py)
Desfaz.....: {what}
Quando.....: SÓ com decisão explícita do proprietário (ver
             CONTROLLED-EXECUTION-PROTOCOL.md §7). Ordem obrigatória R4 → R1;
             cada R recusa rodar fora de ordem (PRECHECK).
Corpos copiados byte a byte de:
{src}
Status.....: PREPARADO, NÃO EXECUTADO.
================================================================
*/"""

def derive_recovery():
    out = {}
    # R4
    r4 = [rhead("R4", "5364 (set_my_physical_cards_condition). Condições já gravadas permanecem.", []), "",
          "begin;", "set local lock_timeout = '5s';", "",
          "do $pre$", "declare v_oid oid := to_regprocedure('" + SCMC + "');", "begin",
          "  if v_oid is null then raise exception 'PRECHECK R4: 5364 ausente — nada a desfazer'; end if;",
          f"  if (select md5(prosrc) from pg_proc where oid = v_oid) <> '{NEW['5364']}' then",
          "    raise exception 'PRECHECK R4: ESTADO DIVERGENTE — corpo vigente difere da 5364 v1.1'; end if;",
          "  if exists (select 1 from pg_depend d where d.refclassid = 'pg_proc'::regclass and d.refobjid = v_oid and d.deptype = 'n') then",
          "    raise exception 'PRECHECK R4: há objetos dependentes'; end if;",
          "end;", "$pre$;", "",
          "drop function public.set_my_physical_cards_condition(uuid[], text);", "",
          "do $post$", "begin",
          "  if to_regprocedure('" + SCMC + "') is not null then raise exception 'POSTCHECK R4: função ainda existe'; end if;",
          "end;", "$post$;", "", "notify pgrst, 'reload schema';", "", "commit;", ""]
    out["R4_rollback_5364.sql"] = "\n".join(r4)
    # R3
    h262, body262 = between_tx(schema_file("5262"))
    k = find(body262, r"^drop function public\.get_my_inventory_item_copies")
    body262 = body262[k:]
    r3 = [rhead("R3", "5363 (volta get_my_inventory_item_copies ao corpo e às 20 colunas da 5262).", [(schema_file("5262"), h262)]), "",
          "begin;", "set local lock_timeout = '5s';", "",
          "do $pre$", "declare v_oid oid := to_regprocedure('" + GMIC + "');", "begin",
          "  if to_regprocedure('" + SCMC + "') is not null then raise exception 'PRECHECK R3: rode R4 antes'; end if;",
          "  if v_oid is null then raise exception 'PRECHECK R3: get_my_inventory_item_copies ausente — ESTADO DIVERGENTE'; end if;",
          "  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'get_my_inventory_item_copies') <> 1 then",
          "    raise exception 'PRECHECK R3: mais de uma sobrecarga'; end if;",
          f"  if (select md5(prosrc) from pg_proc where oid = v_oid) = '{OLD['5262']}' then raise exception 'PRECHECK R3: 5363 não está aplicada — nada a desfazer'; end if;",
          f"  if (select md5(prosrc) from pg_proc where oid = v_oid) <> '{NEW['5363']}' or pg_get_function_result(v_oid) <> '{COLS21}' then",
          "    raise exception 'PRECHECK R3: ESTADO DIVERGENTE — corpo/retorno vigente difere da 5363'; end if;",
          "  if exists (select 1 from pg_depend d where d.refclassid = 'pg_proc'::regclass and d.refobjid = v_oid and d.deptype = 'n') then",
          "    raise exception 'PRECHECK R3: há objetos dependentes'; end if;",
          "end;", "$pre$;", ""] + body262 + ["",
          "do $post$", "declare v_oid oid := to_regprocedure('" + GMIC + "');", "begin",
          f"  if v_oid is null or (select md5(prosrc) from pg_proc where oid = v_oid) <> '{OLD['5262']}' or pg_get_function_result(v_oid) <> '{COLS20}' then",
          "    raise exception 'POSTCHECK R3: corpo/retorno restaurado difere da 5262'; end if;",
          "  if not has_function_privilege('authenticated', '" + GMIC + "', 'EXECUTE') or has_function_privilege('anon', '" + GMIC + "', 'EXECUTE') then",
          "    raise exception 'POSTCHECK R3: ACL divergente'; end if;",
          "end;", "$post$;", "", "commit;", ""]
    out["R3_rollback_5363.sql"] = "\n".join(r3)
    # R2
    srcs, bodies = [], []
    for k2 in ("5153", "5155", "5157", "5158"):
        f = schema_file(k2); h, body = between_tx(f); srcs.append((f, h))
        body = list(body)
        idx = [i for i, l in enumerate(body) if re.match(r"^CREATE (OR REPLACE )?FUNCTION public\.", l)]
        assert len(idx) == 1, k2
        body[idx[0]] = re.sub(r"^CREATE FUNCTION ", "CREATE OR REPLACE FUNCTION ", body[idx[0]])
        bodies += [f"-- ---- corpo canônico {f.name} (entre BEGIN/COMMIT; CREATE → CREATE OR REPLACE) ----"] + body + [""]
    pre = ["do $pre$", "begin",
           "  if to_regprocedure('" + SCMC + "') is not null then raise exception 'PRECHECK R2: rode R4 antes (5364 usa a validação)'; end if;",
           "  if to_regprocedure('" + VAL + "') is null then raise exception 'PRECHECK R2: validação ausente — 5362 não aplicada ou ESTADO DIVERGENTE'; end if;"]
    for k2 in ("5153", "5155", "5157", "5158"):
        pre.append(f"  if (select md5(prosrc) from pg_proc where oid = to_regprocedure('{SIG[k2]}')) is distinct from '{NEW[k2]}' then raise exception 'PRECHECK R2: ESTADO DIVERGENTE em {k2}'; end if;")
    pre += ["end;", "$pre$;", ""]
    post = ["do $post$", "begin"]
    for k2 in ("5153", "5155", "5157", "5158"):
        post.append(f"  if (select md5(prosrc) from pg_proc where oid = to_regprocedure('{SIG[k2]}')) is distinct from '{OLD[k2]}' then raise exception 'POSTCHECK R2: corpo restaurado de {k2} difere do canônico'; end if;")
    post += ["  if to_regprocedure('" + VAL + "') is not null then raise exception 'POSTCHECK R2: validação ainda existe'; end if;",
             "  if has_function_privilege('authenticated', '" + SIG['5153'] + "', 'EXECUTE') then raise exception 'POSTCHECK R2: helper executável por cliente'; end if;",
             "  if not has_function_privilege('authenticated', '" + SIG['5155'] + "', 'EXECUTE') or not has_function_privilege('authenticated', '" + SIG['5157'] + "', 'EXECUTE')",
             "     or not has_function_privilege('authenticated', '" + SIG['5158'] + "', 'EXECUTE') then raise exception 'POSTCHECK R2: ACL das RPCs divergente'; end if;",
             "end;", "$post$;", ""]
    r2 = [rhead("R2", "5362 (volta 5153/5155/5157/5158 aos corpos canônicos e remove a validação).", srcs), "",
          "begin;", "set local lock_timeout = '5s';", ""] + pre + bodies + \
         ["drop function public.physical_card_unknown_condition_codes(text[]);", ""] + post + \
         ["notify pgrst, 'reload schema';", "", "commit;", ""]
    out["R2_rollback_5362.sql"] = "\n".join(r2)
    # R1
    r1 = [rhead("R1", "5361 (remove FK e coluna condition_code). APAGA as condições gravadas: o PRECHECK recusa se houver qualquer exemplar ≠ NM.", []), "",
          "begin;", "set local lock_timeout = '5s';", "set local statement_timeout = '120s';", "",
          "do $pre$", "declare v_non_nm bigint;", "begin",
          "  if to_regprocedure('" + SCMC + "') is not null or to_regprocedure('" + VAL + "') is not null then",
          "    raise exception 'PRECHECK R1: rode R4 e R2 antes'; end if;",
          f"  if (select md5(prosrc) from pg_proc where oid = to_regprocedure('{GMIC}')) is distinct from '{OLD['5262']}' then",
          "    raise exception 'PRECHECK R1: rode R3 antes'; end if;",
          "  if not exists (select 1 from pg_attribute where attrelid = 'public.physical_card'::regclass and attname = 'condition_code' and not attisdropped) then",
          "    raise exception 'PRECHECK R1: coluna ausente — nada a desfazer'; end if;",
          "  select count(*) into v_non_nm from public.physical_card where condition_code <> 'NM';",
          "  if v_non_nm > 0 then",
          "    raise exception 'PRECHECK R1: % exemplar(es) com condição declarada diferente de NM — desfazer apagaria dado do usuário; exige decisão explícita do proprietário', v_non_nm; end if;",
          "end;", "$pre$;", "",
          "alter table public.physical_card drop constraint fk_physical_card_condition_code;",
          "alter table public.physical_card drop column condition_code;", "",
          "do $post$", "begin",
          "  if exists (select 1 from pg_attribute where attrelid = 'public.physical_card'::regclass and attname = 'condition_code' and not attisdropped)",
          "     or exists (select 1 from pg_constraint where conname = 'fk_physical_card_condition_code') then",
          "    raise exception 'POSTCHECK R1: coluna ou FK ainda existem'; end if;",
          "end;", "$post$;", "", "notify pgrst, 'reload schema';", "", "commit;", ""]
    out["R1_rollback_5361.sql"] = "\n".join(r1)
    return out

def main():
    out = {}
    out.update(derive_5887())
    out.update(derive_legacy(SRC_5822, "5822", 64))
    out.update(derive_legacy(SRC_5826, "5826", 56))
    out.update(derive_recovery())
    check = "--check" in sys.argv
    bad = 0
    print("arquivo | sha256")
    for name, text in sorted(out.items()):
        p = HERE / name
        data = text.encode("utf-8")
        if check:
            ok = p.exists() and p.read_bytes() == data
            bad += not ok
            print(f"{name} | {sha(data)} | {'OK' if ok else 'DIVERGENTE'}")
        else:
            p.write_bytes(data)
            print(f"{name} | {sha(data)}")
    for src in (SRC_5887, SRC_5822, SRC_5826):
        print(f"origem {src.name} | {sha(src.read_bytes())}")
    sys.exit(1 if bad else 0)

if __name__ == "__main__":
    main()
