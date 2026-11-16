#!/usr/bin/env python3
"""
V1-13 · E1-E2 — gerador dos ensaios G2 da cadeia PROTEGIDA (D-E1, Alternativa C).

Não conecta em banco e não executa SQL. Lê SÓ entradas com sha256 fixado neste
arquivo (ou no G1_MANIFEST.json, ele próprio fixado), recusa qualquer divergência,
valida a ordem de dependências e gera três ensaios em transação abortada, todos
com a moldura T0–T11 do P1 da E1-A:

  G2_A_E1A_PROTECTED_rollback.sql      P1-G: 5389 + E1-A protegida; 5861 (CLOSED), 5888 (OPEN)
  G2_B_CHAIN_STORAGE_LAST_rollback.sql cadeia completa, 5377 por último (retenção mínima
                                       de storage.objects); harnesses sem 5377 antes dela
  G2_C_CHAIN_FULL_FINAL_rollback.sql   cadeia completa; TODOS os harnesses no estado final
                                       (retenção de storage.objects durante todos eles)

e o harness 5863 v1.2-E1E (S.4 adaptada ao contrato da 5377; PROPOSTA, depende de
aprovação) e o G2_MANIFEST.sha256.

    python3 -I -B .../e1e2/build_g2_chain.py           # gera
    python3 -I -B .../e1e2/build_g2_chain.py --check   # confere (código 0 = EM DIA)
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
EVID = os.path.dirname(HERE)
PROP = os.path.dirname(EVID)
G1 = os.path.join(EVID, "g1")

A = "2026-11-14-v1-13-e1a-editor-role"
B1 = "2026-11-15-v1-13-e1b1-editor-core-binder"
B2 = "2026-11-15-v1-13-e1b2-editor-curation"
B3 = "2026-11-15-v1-13-e1b3-pokedex-history"
C1 = "2026-11-15-v1-13-e1c-bulk-operations"
C2 = "2026-11-15-v1-13-e1c2-remaining-bulk-operations"
D = "2026-11-15-v1-13-e1d-shared-reads"
V12P = "2026-10-30-v1-12-viewer-parity"
V12V = "2026-10-30-v1-12-shared-binder-visual-assets"
V12L = "2026-10-30-card-set-logo-public-read"

G1_MANIFEST_SHA = "03823d13e25978af2616d80df737b67017bfbd9995640042eed1d1f78cba7306"

# Migrations NÃO protegidas (aplicadas como auditadas) e a 5389: sha256 fixado.
PLAIN = {
    "5389": (os.path.join(G1, "5389_create_v1_13_capability_barrier.sql"),
             "b8c60c6c425f21109e8564e69af48bee69447fee650a8aae9a1ba28c431999b5"),
    "5366": (os.path.join(PROP, A, "5366_widen_collection_membership_role_editor.sql"),
             "bc1ff1109fee3a6c72b58f6537c57c713b1727b51f2662da4cad9600bc963aaa"),
    "5367": (os.path.join(PROP, A, "5367_create_collection_member_role_function.sql"),
             "92c8b4d71e96245c7228f9fa262d795431188c39873537a453961a088b77b5fb"),
    "5368": (os.path.join(PROP, A, "5368_expose_member_role_in_sharing_reads.sql"),
             "27dff7273fbbaed0864096dfd9a3fc46189220bfd6f2e87ff62032fba32655ea"),
    "5371": (os.path.join(PROP, B1, "5371_create_binder_editor_authorization.sql"),
             "b2a09041e5778fe33a358b4dcf3aaea06adbde970753b8abe4ecf5a888cce107"),
    "5372": (os.path.join(PROP, B1, "5372_allow_editor_actor_in_binder_activity.sql"),
             "ff9d9c80607717db4d4a0eaebde1687e68df42bdefe41e9c3b7e06c13cbe35ba"),
    "5378": (os.path.join(PROP, B3, "5378_fix_binder_slot_editor_scope_species_reference.sql"),
             "828fa3d54543c31e845aa9ef7c56ba1721fbf30679dc2af91bac5f483c7c0e5d"),
    "5379": (os.path.join(PROP, B3, "5379_attribute_binder_activity_items_to_collection.sql"),
             "7eed93c01db7ab5aacbf4193af06d5cfd6bd92f3102abe21b67d9727af22534c"),
    "5381": (os.path.join(PROP, C1, "5381_restrict_editor_binder_activity_event_types.sql"),
             "f48421892a73d4ce37c8b575ee003a74abca385fe3f18edbff93c3b437d8e3d6"),
    "5384": (os.path.join(PROP, C2, "5384_extend_editor_binder_activity_event_types.sql"),
             "9b944466cb7c7eca95c582ac1214e171ce0511ea4a069f28934b45c9e60d1549"),
}
PROTECTED = ["5369", "5370", "5373", "5374", "5375", "5376", "5377", "5380", "5382", "5383",
             "5385", "5386", "5387", "5323", "5324", "5388"]

# Dependências (dos prechecks e da dependência funcional 5384 → 5385–5387).
DEPS = {
    "5389": [], "5366": ["5389"], "5367": ["5366"], "5368": ["5367"], "5369": ["5389", "5366"],
    "5370": ["5389", "5366"], "5371": ["5366"], "5372": ["5366"], "5373": ["5389", "5366"],
    "5374": ["5389", "5371", "5372"], "5375": ["5389", "5371", "5372"], "5376": ["5389", "5366"],
    "5377": ["5389", "5366"], "5378": ["5371"], "5379": ["5372"], "5380": ["5389", "5376"],
    "5381": ["5379"], "5382": ["5389", "5371", "5378", "5381"], "5383": ["5389", "5382"], "5384": ["5381"],
    "5385": ["5389", "5371", "5378", "5382", "5384"], "5386": ["5389", "5385", "5384"],
    "5387": ["5389", "5385", "5384"], "5323": ["5389"], "5324": ["5389"], "5388": ["5389", "5379"],
}
E1A = ["5389", "5366", "5367", "5368", "5369", "5370"]
CHAIN_NO_5377 = E1A + ["5371", "5372", "5373", "5374", "5375", "5376", "5378", "5379", "5380", "5381",
                       "5382", "5383", "5384", "5385", "5386", "5387", "5323", "5324", "5388"]

# Harnesses: (pasta, arquivo, sha256, prefixo, verificações esperadas).
HARN = {
    "5861": (A, "5861_validate_collection_sharing_v1.4.sql", "9135bd0b8ab0dc7cd0d25bb630bf45cce0b835f66bd381544b33a55ee64bf146", 51),
    "5862": (V12P, "5862_validate_viewer_parity.sql", "f6f7dd4e6c3184a861dbf05785c0dc003324c68cde8fabd95668645b0108a260", 33),
    "5863": (V12V, "5863_validate_shared_binder_visual_assets.sql", "ec5e8da7064385ac219310c906a700dbf7156893b4600f0e302e8b3a9819f170", 37),
    "5864": (V12L, "5864_validate_card_set_logo_public_read.sql", "47e96959e15447dcd3821ea2f1a887f07be99fff4b057eda53370f57c65a449e", 7),
    "5888": (A, "5888_validate_editor_role_foundation_HARNESS.sql", "c6e336396ba57fdcfddc849ee99f6f65a8cf4b688a32bd5efd9db0bdf70a8e48", 54),
    "5889": (B1, "5889_validate_editor_core_binder_HARNESS.sql", "4982135d5b3f0b859a78755b1979342ef54032f563635fb7c76a152e38d0095d", 56),
    "5890": (B2, "5890_validate_editor_curation_HARNESS.sql", "ae57e56a8cfba9608b7bf654bf5e9cfc45e6ebf9ed5125498e5acec225bc03ec", 45),
    "5891": (B3, "5891_validate_editor_pokedex_history_HARNESS.sql", "133d0cc534fdfc82976f016bac341a3045fab54ece4d6a337c96af188ff53a77", 33),
    "5892": (C1, "5892_validate_editor_bulk_operations_HARNESS.sql", "a3169b24312f702745529170b2a3e684b09573132c74b3e5859039cd4d70bc7d", 27),
    "5893": (C2, "5893_validate_editor_remaining_bulk_operations_HARNESS.sql", "10619cd07d9a63369c640b59008004bc08863122c77627e913a0eec795d176a7", 24),
    "5894": (D, "5894_validate_shared_reads_HARNESS.sql", "db567e0b7bca3ab81169969fd113992c67fff3b5877ee3d99475f9add8e1b869", 29),
    "5895": (os.path.relpath(G1, PROP), "5895_validate_v1_13_barrier_HARNESS.sql", "f7025b7a609912e43369c593e4dcd4f8352aa2433dafc2a8a8fca4677550bda6", 21),
}
# Pré-requisitos de cada harness e modo da barreira em que roda.
HREQ = {"5861": E1A, "5862": E1A, "5863": E1A + ["5377"], "5864": [], "5888": E1A,
        "5889": E1A + ["5371", "5372", "5373", "5374"], "5890": E1A + ["5371", "5372", "5373", "5374", "5375", "5376", "5377"],
        "5891": CHAIN_NO_5377[:15], "5892": CHAIN_NO_5377[:18], "5893": CHAIN_NO_5377[:22],
        "5894": CHAIN_NO_5377, "5895": CHAIN_NO_5377 + ["5377"]}
MODE = {"5861": "CLOSED", "5862": "CLOSED", "5863": "CLOSED", "5864": "CLOSED", "5888": "OPEN", "5889": "OPEN",
        "5890": "OPEN", "5891": "OPEN", "5892": "OPEN", "5893": "OPEN", "5894": "OPEN", "5895": "CLOSED"}

# Adaptação PROPOSTA da 5863 (S.4): a 5377 acrescenta 3 políticas do EDITOR em collection-cover.
S4_OLD = """    and (select count(*) from pg_policies where schemaname = 'storage' and tablename = 'objects'
       and (qual like '%binder-slot-image%' or qual like '%collection-cover%' or with_check like '%binder-slot-image%' or with_check like '%collection-cover%')) = 9
    and not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
       and cmd <> 'SELECT'
       and (qual like '%binder-slot-image%' or qual like '%collection-cover%' or with_check like '%binder-slot-image%' or with_check like '%collection-cover%')
       and (coalesce(qual, '') || coalesce(with_check, '')) not like '%auth.uid()%'),
    'detail','7 políticas do dono intactas; total nos dois buckets = 9; toda política de escrita exige a pasta do próprio usuário');"""
S4_NEW = """    and (select count(*) from pg_policies p  -- E1E
         join (values ('binder_slot_image_select_own','SELECT','binder-slot-image'),  -- E1E
                      ('binder_slot_image_insert_own','INSERT','binder-slot-image'),  -- E1E
                      ('binder_slot_image_delete_own','DELETE','binder-slot-image'),  -- E1E
                      ('collection_cover_select_own','SELECT','collection-cover'),  -- E1E
                      ('collection_cover_insert_own','INSERT','collection-cover'),  -- E1E
                      ('collection_cover_update_own','UPDATE','collection-cover'),  -- E1E
                      ('collection_cover_delete_own','DELETE','collection-cover')) e(n, c, b)  -- E1E
           on p.policyname = e.n and p.cmd = e.c  -- E1E
        where p.schemaname = 'storage' and p.tablename = 'objects'  -- E1E
          and p.permissive = 'PERMISSIVE' and p.roles = array['authenticated']::name[]  -- E1E
          and (coalesce(p.qual, '') || coalesce(p.with_check, '')) like '%' || e.b || '%'  -- E1E
          and (p.qual is null or (p.qual like '%foldername(name))[1]%' and p.qual like '%auth.uid()%'))  -- E1E
          and (p.with_check is null or (p.with_check like '%foldername(name))[1]%' and p.with_check like '%auth.uid()%'))  -- E1E
          and (p.cmd <> 'UPDATE' or (p.qual is not null and p.with_check is not null))) = 7  -- E1E
    and (select count(*) from pg_policies p  -- E1E
        where p.schemaname = 'storage' and p.tablename = 'objects'  -- E1E
          and p.policyname in ('binder_slot_image_select_shared','collection_cover_select_shared')  -- E1E
          and p.cmd = 'SELECT' and p.permissive = 'PERMISSIVE'  -- E1E
          and p.roles @> array['anon','authenticated']::name[] and cardinality(p.roles) = 2  -- E1E
          and p.qual like '%shared_visual_asset_readable%' and p.with_check is null) = 2  -- E1E
    and (select count(*) from pg_policies p  -- E1E
         join (values ('collection_cover_insert_editor','INSERT'),  -- E1E
                      ('collection_cover_select_editor','SELECT'),  -- E1E
                      ('collection_cover_delete_editor','DELETE')) e(n, c)  -- E1E
           on p.policyname = e.n and p.cmd = e.c  -- E1E
        where p.schemaname = 'storage' and p.tablename = 'objects'  -- E1E
          and p.permissive = 'PERMISSIVE' and p.roles = array['authenticated']::name[]  -- E1E
          and ((e.c = 'INSERT' and p.qual is null and p.with_check like '%collection-cover%'  -- E1E
                and p.with_check like '%collection_cover_editor_can_upload(name)%')  -- E1E
               or (e.c <> 'INSERT' and p.with_check is null and p.qual like '%collection-cover%'  -- E1E
                   and p.qual like '%owner_id%' and p.qual like '%auth.uid()%'  -- E1E
                   and p.qual like '%collection_cover_editor_folder_ok(name)%'))) = 3  -- E1E
    and (select count(*) from pg_policies p  -- E1E
        where p.schemaname = 'storage' and p.tablename = 'objects'  -- E1E
          and (coalesce(p.qual, '') || coalesce(p.with_check, '')) ~ '(binder-slot-image|collection-cover)') = 12  -- E1E
    and not exists (select 1 from pg_policies p  -- E1E
        where p.schemaname = 'storage' and p.tablename = 'objects'  -- E1E
          and (coalesce(p.qual, '') || coalesce(p.with_check, '')) ~ '(binder-slot-image|collection-cover)'  -- E1E
          and (p.policyname not in ('binder_slot_image_select_own','binder_slot_image_insert_own','binder_slot_image_delete_own',  -- E1E
                                    'collection_cover_select_own','collection_cover_insert_own','collection_cover_update_own',  -- E1E
                                    'collection_cover_delete_own','binder_slot_image_select_shared','collection_cover_select_shared',  -- E1E
                                    'collection_cover_insert_editor','collection_cover_select_editor','collection_cover_delete_editor')  -- E1E
               or p.permissive <> 'PERMISSIVE'  -- E1E
               or ('anon' = any(p.roles) and p.cmd <> 'SELECT')  -- E1E
               or 'public' = any(p.roles)))  -- E1E
    and (select count(*) from pg_proc q  -- E1E
        where q.oid in (to_regprocedure('public.collection_cover_editor_folder_ok(text)'),  -- E1E
                        to_regprocedure('public.collection_cover_editor_can_upload(text)'))  -- E1E
          and q.prosecdef and q.proconfig = array['search_path=""']  -- E1E
          and not has_function_privilege('anon', q.oid, 'EXECUTE')  -- E1E
          and q.prosrc like '%public.v1_13_capability_open()%'  -- E1E
          and q.prosrc like '%(select auth.uid())%') = 2  -- E1E
    and (select q.prosrc from pg_proc q where q.oid = to_regprocedure('public.collection_cover_editor_folder_ok(text)'))  -- E1E
          like '%m.user_id = v_uid and m.status = ''ACTIVE'' and m.role = ''EDITOR''%'  -- E1E
    and (select q.prosrc from pg_proc q where q.oid = to_regprocedure('public.collection_cover_editor_folder_ok(text)'))  -- E1E
          like '%if v_owner = v_uid then%return false;%'  -- E1E
    and (select q.prosrc from pg_proc q where q.oid = to_regprocedure('public.collection_cover_editor_can_upload(text)'))  -- E1E
          like '%public.collection_cover_editor_folder_ok(%',  -- E1E
    'detail','conjunto fechado de 12 políticas nos dois buckets, cada uma por nome, comando, papéis e predicado: 7 do dono (pasta do próprio usuário por auth.uid(), só authenticated; UPDATE com as duas expressões), 2 de leitura compartilhada (anon e authenticated, decisão delegada), 3 do EDITOR (5377: só authenticated; inserção pelo ajudante; leitura e exclusão só do próprio envio por owner_id = auth.uid() e pelo ajudante); nenhuma política inesperada, restritiva, de escrita para anon ou para PUBLIC; ajudantes definer, sem EXECUTE para anon, presos à identidade autenticada, à participação EDITOR ativa e à barreira; a pasta do próprio titular fica só com as políticas do dono');  -- E1E"""
H5863 = "5863_validate_shared_binder_visual_assets_v1.2-E1E.sql"


def sha256(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def rd(path: str) -> bytes:
    if not os.path.exists(path):
        raise SystemExit(f"ERRO: entrada ausente: {path}")
    b = open(path, "rb").read()
    if b"\r" in b:
        raise SystemExit(f"ERRO: CRLF em {path}")
    return b


def load_inputs() -> dict:
    man_path = os.path.join(G1, "G1_MANIFEST.json")
    mb = rd(man_path)
    if sha256(mb) != G1_MANIFEST_SHA:
        raise SystemExit("ERRO: G1_MANIFEST.json diverge do sha256 fixado")
    man = json.loads(mb.decode("utf-8"))
    files = {}
    for num, (path, h) in PLAIN.items():
        b = rd(path)
        if sha256(b) != h:
            raise SystemExit(f"ERRO: sha256 divergente em {num} ({path})")
        files[num] = (path, b.decode("utf-8"), h, "auditada" if num != "5389" else "G1")
    for f in man["files"]:
        num = os.path.basename(f["protected"])[:4]
        b = rd(os.path.join(EVID, f["protected"]))
        if sha256(b) != f["protected_sha256"] or sha256(rd(os.path.join(PROP, f["base"]))) != f["base_sha256"]:
            raise SystemExit(f"ERRO: protegida/base divergente do manifesto G1 em {num}")
        if num in files:
            raise SystemExit(f"ERRO: migration duplicada {num}")
        files[num] = (os.path.join(EVID, f["protected"]), b.decode("utf-8"), f["protected_sha256"], "protegida")
    if sorted(n for n, v in files.items() if v[3] == "protegida") != sorted(PROTECTED):
        raise SystemExit("ERRO: conjunto de protegidas diverge do esperado")
    caps = {fn for f in man["files"] for fn in f["functions"]}
    return {"files": files, "caps": caps, "manifest": man}


def migration_body(num: str, text: str) -> str:
    lines = text.split("\n")
    b = [i for i, l in enumerate(lines) if l == "begin;"]
    c = [i for i, l in enumerate(lines) if l == "commit;"]
    if len(b) != 1 or len(c) != 1 or not b[0] < c[0]:
        raise SystemExit(f"ERRO: {num} precisa ter exatamente um 'begin;' e um 'commit;' em linha própria")
    inner = "\n".join(lines[b[0] + 1: c[0]]).strip("\n")
    if re.search(r"(?im)^\s*(begin|commit|rollback|savepoint\s+\w+|release\s+\w+|start\s+transaction)\s*;", inner) \
            or re.search(r"(?im)^\s*end\s+transaction\b", inner):
        raise SystemExit(f"ERRO: controle de transação dentro de {num}")
    return inner


def harness_body(num: str, text: str) -> str:
    i = text.index(f"create or replace function pg_temp.wh_{num}_")
    v = text.index(f"create or replace function pg_temp.wh_{num}_validate()")
    j = text.index("$fn$;", v) + len("$fn$;")
    body = text[i:j]
    if re.search(r"(?im)^\s*(begin|commit|rollback)\s*;", body):
        raise SystemExit(f"ERRO: controle de transação no harness {num}")
    return body


def harness_text(num: str) -> tuple[str, str]:
    folder, fname, h, _ = HARN[num]
    b = rd(os.path.join(PROP, folder, fname))
    if sha256(b) != h:
        raise SystemExit(f"ERRO: sha256 divergente no harness {num}")
    t = b.decode("utf-8")
    if num == "5863":
        if t.count(S4_OLD) != 1:
            raise SystemExit("ERRO: S.4 da 5863 não encontrada")
        t = t.replace(S4_OLD, S4_NEW)
        t = ("/* E1-E2 — VARIANTE 5863 v1.2-E1E GERADA por e1e2/build_g2_chain.py. AUTORIZADA (CANONICAL BASELINE\n"
             "   RECONCILIATION AND G2 CORRECTION-02): S.4 com conjunto fechado das 12 políticas e prova dos ajudantes da 5377.\n"
             f"   Base: database/proposals/{folder}/{fname} sha256 {h}. Linhas mudadas marcadas \"-- E1E\". */\n") + t
    return t, sha256(t.encode("utf-8"))


def check_order(seq: list[str], inp: dict) -> None:
    seen = set()
    for num in seq:
        if num in seen:
            raise SystemExit(f"ERRO: {num} repetida na sequência")
        for d in DEPS[num]:
            if d not in seen:
                raise SystemExit(f"ERRO: {num} antes de sua dependência {d}")
        seen.add(num)
    if seq[0] != "5389":
        raise SystemExit("ERRO: 5389 precisa ser a primeira")
    # nenhuma redefinição desprotegida de capacidade depois da protegida
    owner = {}
    for num in seq:
        text = inp["files"][num][1]
        for fn in re.findall(r"(?i)create (?:or replace )?function\s+public\.([a-z_0-9]+)", text):
            if fn in inp["caps"]:
                if inp["files"][num][3] != "protegida" or fn in owner:
                    raise SystemExit(f"ERRO: capacidade {fn} definida fora da protegida ou redefinida em {num}")
                owner[fn] = num
    if len(seq) > 6 and set(owner) != inp["caps"]:
        missing = sorted(inp["caps"] - set(owner))
        raise SystemExit(f"ERRO: capacidades sem definição protegida na cadeia: {missing}")


HEADER = """/*
================================================================
Projeto.....: Project Mimikyu
Arquivo.....: {name} — ensaio G2 ({title})
Status......: GERADO por e1e2/build_g2_chain.py — NÃO EDITAR À MÃO. NÃO EXECUTADO.
              EXECUÇÃO BLOQUEADA até: S0 ampliada (S0_G2_readonly.sql) executada e
              aprovada; revisão independente; autorização expressa e específica do
              proprietário (hash, executor, canal, janela). {extra}
              Mecanismo da barreira (G1) não homologado; G2 não iniciado.
Canal.......: psql -X -v ON_ERROR_STOP=1 -f {name}  — conexão DIRETA única, não
              interativo, sem -1. Mesma moldura T0–T11 do P1 da E1-A
              (VALIDATION-STRATEGY-E1A.md §2): sessão somente leitura por padrão (T0),
              trava de COMMIT (T4), LOCK NOWAIT antes do DDL (T6), sentinela que SEMPRE
              aborta (T9) com SQLSTATE {ok}/{no}.
Sequência...: {seq}
Harnesses...: {harn}
Total.......: {total} verificações (soma dos GATEs esperados)
Limites.....: statement_timeout {stmt}; lock_timeout 2s (cada migration redefine 5s);
              idle_in_transaction 15s; transaction_timeout {txn} só se PG >= 17;
              aprovado só com duração <= {cap} ms (limite proposto, não medição).
Provas......: só o banco (SET LOCAL ROLE); JWT real, PostgREST, Storage pela API,
              concorrência e medições ficam para G3/G4.
Fontes......: {sources}
================================================================
*/
"""

T3 = """SET LOCAL lock_timeout = '2s';
SET LOCAL statement_timeout = '{stmt}';
SET LOCAL idle_in_transaction_session_timeout = '15s';
do $t3$
begin
  if pg_catalog.current_setting('server_version_num')::int < 140000 then
    raise exception 'G2 T3: PostgreSQL < 14 — ensaio RECUSADO';
  end if;
  perform pg_catalog.set_config('client_connection_check_interval', '1s', true);
  if pg_catalog.current_setting('server_version_num')::int >= 170000 then
    perform pg_catalog.set_config('transaction_timeout', '{txn}', true);
  end if;
end;
$t3$;"""

T4 = """create temp table g2_trap_parent (id integer primary key) on commit drop;
create temp table g2_trap_child (
  parent_id integer not null
    constraint g2_trap_fk references g2_trap_parent (id) deferrable initially deferred
) on commit drop;
insert into g2_trap_child (parent_id) values (1);"""

T5 = """create temp table g2_evidence (harness text, seq integer, check_id text, status text, detail text) on commit drop;
create temp table g2_meta (k text primary key, v jsonb not null) on commit drop;"""

T6 = r"""do $t6$
declare
  v_ext jsonb;
  v_evt jsonb;
  v_long integer;
begin
  if pg_catalog.current_setting('transaction_read_only') <> 'off' then
    raise exception 'G2 T6: transação não está READ WRITE';
  end if;
  if pg_catalog.current_setting('default_transaction_read_only') <> 'on' then
    raise exception 'G2 T6: T0 não vigora nesta sessão (pooler/troca de backend?) — RECUSAR';
  end if;
  if pg_catalog.current_setting('session_replication_role') <> 'origin' then
    raise exception 'G2 T6: session_replication_role <> origin';
  end if;
  if pg_catalog.pg_is_in_recovery() then
    raise exception 'G2 T6: servidor em recuperação';
  end if;
  if current_user <> 'postgres' or session_user <> 'postgres' then
    raise exception 'G2 T6: executor deve ser postgres, sem SET ROLE';
  end if;
  if (select count(*) from pg_temp.g2_trap_child) <> 1
     or not exists (select 1 from pg_catalog.pg_constraint k
                    where k.conname = 'g2_trap_fk' and k.contype = 'f' and k.condeferrable and k.condeferred
                      and k.conrelid = 'pg_temp.g2_trap_child'::regclass) then
    raise exception 'G2 T6: trava de COMMIT ausente ou não adiada';
  end if;
  -- Nada da V1-13 pode existir antes do ensaio (estado = S0).
  if to_regclass('public.v1_13_barrier_state') is not null
     or to_regprocedure('public.collection_member_role(uuid)') is not null
     or to_regprocedure('public.invite_collection_member(uuid, text, text)') is not null then
    raise exception 'G2 T6: objetos da V1-13 já existem — estado diverge da S0, RECUSAR';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('tabela', n.nspname || '.' || c.relname, 'gatilho', t.tgname, 'funcao', p.proname)), '[]'::jsonb)
    into v_ext
  from pg_catalog.pg_trigger t
  join pg_catalog.pg_class c on c.oid = t.tgrelid
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  join pg_catalog.pg_proc p on p.oid = t.tgfoid
  where not t.tgisinternal
    and n.nspname in ('public', 'auth', 'storage')
    and p.prosrc ~* '(net\.|http_|pg_net|dblink|pg_notify|notify\s)';
  if jsonb_array_length(v_ext) > 0 then
    raise exception 'G2 T6: gatilho com possível efeito externo: % — RECUSAR', v_ext;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('evento', e.evtname, 'funcao', p.proname)), '[]'::jsonb)
    into v_evt
  from pg_catalog.pg_event_trigger e
  join pg_catalog.pg_proc p on p.oid = e.evtfoid
  where e.evtenabled <> 'D' and p.prosrc ~* '(net\.|http_|pg_net|dblink)';
  if jsonb_array_length(v_evt) > 0 then
    raise exception 'G2 T6: gatilho de evento com possível efeito externo: % — RECUSAR', v_evt;
  end if;
  select count(*) into v_long
  from pg_catalog.pg_locks l
  join pg_catalog.pg_stat_activity a on a.pid = l.pid
  where l.relation in ({lock_rels})
    and l.pid <> pg_catalog.pg_backend_pid()
    and (a.xact_start is null or a.xact_start < pg_catalog.clock_timestamp() - interval '1 second');
  if v_long > 0 then
    raise exception 'G2 T6: % sessão(ões) com lock antigo nas tabelas do ensaio — RECUSAR', v_long;
  end if;
  insert into pg_temp.g2_meta (k, v) values
    ('t_start', to_jsonb(pg_catalog.clock_timestamp())),
    ('server_version_num', to_jsonb(pg_catalog.current_setting('server_version_num')::int)),
    ('event_triggers', (select coalesce(jsonb_agg(e.evtname order by e.evtname), '[]'::jsonb)
                          from pg_catalog.pg_event_trigger e where e.evtenabled <> 'D'));
end;
$t6$;"""


def lock_stmt(rel: str, key: str) -> str:
    return (f"LOCK TABLE {rel} IN ACCESS EXCLUSIVE MODE NOWAIT;\n"
            f"insert into pg_temp.g2_meta (k, v) values ('{key}', to_jsonb(pg_catalog.clock_timestamp()));")


def mode_stmt(mode: str) -> str:
    return f"update public.v1_13_barrier_state set mode = '{mode}', change_note = 'G2 ensaio' where id = 1;"


T9_POST = """do $t9post$
begin
  if (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'CLOSED'
     or exists (select 1 from public.v1_13_barrier_identity) then
    raise exception 'G2 T9: barreira não voltou a CLOSED com registro vazio';
  end if;
  if (select count(*) from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
         and p.proname in ({caps}) and position('public.v1_13_' in p.prosrc) = 0) > 0 then
    raise exception 'G2 T9: capacidade exposta sem porta';
  end if;
  if current_user <> session_user then
    raise exception 'G2 T9: papel não restaurado';
  end if;
end;
$t9post$;"""

T9_SENTINEL = """do $t9sentinel$
declare
  v_total integer; v_passes integer; v_gates jsonb; v_failed jsonb; v_fixture jsonb;
  v_trap boolean; v_ms numeric; v_ok boolean; v_code text; v_msg text;
begin
  select count(*) filter (where check_id <> 'GATE'),
         count(*) filter (where check_id <> 'GATE' and status = 'PASS'),
         coalesce(jsonb_object_agg(harness, status) filter (where check_id = 'GATE'), '{{}}'::jsonb),
         coalesce(jsonb_agg(harness || ':' || check_id order by harness, seq) filter (where check_id <> 'GATE' and status <> 'PASS'), '[]'::jsonb),
         coalesce(jsonb_agg(harness || ':' || detail order by harness, seq) filter (where check_id in ('F.1', 'X.1')), '[]'::jsonb)
    into v_total, v_passes, v_gates, v_failed, v_fixture
  from pg_temp.g2_evidence;
  v_trap := (select count(*) from pg_temp.g2_trap_child) = 1;
  v_ms := round(extract(epoch from (pg_catalog.clock_timestamp()
           - (select (v #>> '{{}}')::timestamptz from pg_temp.g2_meta where k = 't_start'))) * 1000);
  v_ok := coalesce(v_total = {total} and v_passes = {total} and v_trap and v_ms <= {cap}
                   and (select count(*) from jsonb_each_text(v_gates) g where g.value = 'PASS') = {nharn}, false);
  v_code := case when v_ok then '{ok}' else '{no}' end;
  v_msg := 'MS_{tag} ' || case when v_ok then 'APROVADO ' else 'REPROVADO ' end || jsonb_build_object(
    'ok', v_ok, 'total', v_total, 'passes', v_passes, 'gates', v_gates, 'failed', v_failed,
    'erro_na_fixture', v_fixture, 'trap_intact', v_trap, 'duration_ms', v_ms,
    'locks', (select coalesce(jsonb_object_agg(k, v), '{{}}'::jsonb) from pg_temp.g2_meta where k like 't_lock%'),
    'server_version_num', (select v from pg_temp.g2_meta where k = 'server_version_num'),
    'txid', pg_catalog.txid_current_if_assigned())::text;
  raise exception using message = v_msg, errcode = v_code;
end;
$t9sentinel$;"""

VARIANTS = {
    "G2_A_E1A_PROTECTED_rollback.sql": dict(
        title="P1-G: barreira + E1-A protegida", tag="G2A", ok="E2AOK", no="E2ANO",
        stmt="20s", txn="60s", cap=20000, extra="Substitui o P1 original APENAS para execução futura; o P1 original fica como evidência histórica.",
        locks=[("public.collection_membership", "t_lock_membership")],
        plan=[("mig", n) for n in E1A] + [("mode", "CLOSED"), ("harn", "5861"), ("mode", "OPEN"),
                                           ("harn", "5888"), ("mode", "CLOSED")]),
    "G2_B_CHAIN_STORAGE_LAST_rollback.sql": dict(
        title="cadeia protegida completa, 5377 por último", tag="G2B", ok="E2BOK", no="E2BNO",
        stmt="60s", txn="300s", cap=240000,
        extra="5888–5894 rodam ANTES da 5377 (independência por argumento estático); 5863/5890/5895 no estado final.",
        locks=[("public.collection_membership", "t_lock_membership"), ("public.binder_activity_event", "t_lock_bae"),
               ("public.binder_activity_item", "t_lock_bai")],
        plan=[("mig", n) for n in CHAIN_NO_5377]
             + [("mode", "CLOSED"), ("harn", "5861"), ("harn", "5862"), ("harn", "5864"), ("mode", "OPEN")]
             + [("harn", h) for h in ("5888", "5889", "5891", "5892", "5893", "5894")]
             + [("mode", "CLOSED"), ("lock", "storage.objects"), ("mig", "5377"), ("harn", "5863"),
                ("mode", "OPEN"), ("harn", "5890"), ("mode", "CLOSED"), ("harn", "5895")]),
    "G2_C_CHAIN_FULL_FINAL_rollback.sql": dict(
        title="cadeia protegida completa, todos os harnesses no estado final", tag="G2C", ok="E2COK", no="E2CNO",
        stmt="60s", txn="300s", cap=240000,
        extra="storage.objects fica em ACCESS EXCLUSIVE durante TODOS os harnesses (risco O2 máximo).",
        locks=[("public.collection_membership", "t_lock_membership"), ("public.binder_activity_event", "t_lock_bae"),
               ("public.binder_activity_item", "t_lock_bai")],
        plan=[("mig", n) for n in CHAIN_NO_5377] + [("lock", "storage.objects"), ("mig", "5377")]
             + [("mode", "CLOSED"), ("harn", "5861"), ("harn", "5862"), ("harn", "5863"), ("harn", "5864"), ("mode", "OPEN")]
             + [("harn", h) for h in ("5888", "5889", "5890", "5891", "5892", "5893", "5894")]
             + [("mode", "CLOSED"), ("harn", "5895")]),
}


def build_variant(name: str, cfg: dict, inp: dict) -> str:
    seq = [x for k, x in cfg["plan"] if k == "mig"]
    check_order(seq, inp)
    applied, harns, mode = [], [], None
    for k, x in cfg["plan"]:
        if k == "mig":
            applied.append(x)
        elif k == "mode":
            mode = x
        elif k == "harn":
            missing = [r for r in HREQ[x] if r not in applied]
            if missing:
                raise SystemExit(f"ERRO: {name}: harness {x} antes de {missing}")
            if mode != MODE[x]:
                raise SystemExit(f"ERRO: {name}: harness {x} exige modo {MODE[x]}, está {mode}")
            harns.append(x)
        elif k == "lock" and x == "storage.objects":
            nxt = cfg["plan"][cfg["plan"].index((k, x)) + 1]
            if nxt != ("mig", "5377"):
                raise SystemExit("ERRO: LOCK de storage.objects precisa vir imediatamente antes da 5377")
    if mode != "CLOSED":
        raise SystemExit(f"ERRO: {name}: o ensaio precisa terminar em CLOSED")
    total = sum(HARN[h][3] for h in harns)
    srcs = [f"{n}@{inp['files'][n][2][:16]}" for n in seq] + [f"H{h}@{harness_text(h)[1][:16]}" for h in harns]
    caps = ", ".join(f"'{c}'" for c in sorted(inp["caps"]))
    parts = [HEADER.format(name=name, title=cfg["title"], extra=cfg["extra"], ok=cfg["ok"], no=cfg["no"],
                           seq=" → ".join(seq), harn=", ".join(f"{h}[{MODE[h]}]" for h in harns), total=total,
                           stmt=cfg["stmt"], txn=cfg["txn"], cap=cfg["cap"], sources=", ".join(srcs))]
    parts.append("\\set ON_ERROR_STOP on\n\\set VERBOSITY verbose\n")
    parts.append("-- @@T0 padrão da sessão somente leitura\nSET SESSION default_transaction_read_only = on;\n")
    parts.append("-- @@T1 bloco explícito\nBEGIN;\n")
    parts.append("-- @@T2 esta transação escreve\nSET TRANSACTION READ WRITE;\n")
    parts.append("-- @@T3 limites\n" + T3.format(stmt=cfg["stmt"], txn=cfg["txn"]) + "\n")
    parts.append("-- @@T4 trava de COMMIT\n" + T4 + "\n")
    parts.append("-- @@T5 evidência\n" + T5 + "\n")
    rels = ", ".join(f"to_regclass('{r}')" for r, _ in cfg["locks"]) + ", to_regclass('storage.objects')"
    parts.append("-- @@T6 precheck\n" + T6.replace("{lock_rels}", rels) + "\n")
    for rel, key in cfg["locks"]:
        parts.append(f"-- @@T6 lock imediato ou recusa (NOWAIT): {rel}\n" + lock_stmt(rel, key) + "\n")
    for k, x in cfg["plan"]:
        if k == "mig":
            path, text, h, kind = inp["files"][x]
            parts.append(f"-- @@T7 {x} ({kind}) sha256={h}\n" + migration_body(x, text) + "\n")
        elif k == "lock":
            parts.append("-- @@T7 lock imediato ou recusa (NOWAIT) antes da 5377: storage.objects (O2)\n"
                         + lock_stmt("storage.objects", "t_lock_storage") + "\n")
        elif k == "mode":
            parts.append(f"-- @@T8 modo da barreira {x} (só nesta transação)\n" + mode_stmt(x) + "\n")
        elif k == "harn":
            text, h = harness_text(x)
            parts.append(f"-- @@T8 harness {x} [{MODE[x]}] sha256={h}\n" + harness_body(x, text) + "\n"
                         + f"insert into pg_temp.g2_evidence (harness, seq, check_id, status, detail)\n"
                         + f"  select '{x}', seq, check_id, status, detail from pg_temp.wh_{x}_validate();\n")
    parts.append("-- @@T9 postcheck\n" + T9_POST.replace("{caps}", caps) + "\n")
    parts.append("-- @@T9 sentinela\n" + T9_SENTINEL.format(total=total, cap=cfg["cap"], nharn=len(harns),
                                                             ok=cfg["ok"], no=cfg["no"], tag=cfg["tag"]) + "\n")
    parts.append("-- @@T10 fora do contrato\nROLLBACK;\n")
    parts.append("-- @@T11 fora do contrato\nRESET default_transaction_read_only;\n")
    return "\n".join(parts)


def main() -> int:
    inp = load_inputs()
    out = {}
    t5863, _ = harness_text("5863")
    out[os.path.join(HERE, "harness", H5863)] = t5863.encode("utf-8")
    for name, cfg in VARIANTS.items():
        out[os.path.join(HERE, name)] = build_variant(name, cfg, inp).encode("utf-8")
    rows = [(sha256(rd(os.path.join(G1, "G1_MANIFEST.json"))), "../g1/G1_MANIFEST.json")]
    for num in sorted(inp["files"]):
        rows.append((inp["files"][num][2], os.path.relpath(inp["files"][num][0], HERE)))
    for h, (folder, fname, sh, _) in sorted(HARN.items()):
        rows.append((sh, os.path.relpath(os.path.join(PROP, folder, fname), HERE)))
    for p, b in sorted(out.items()):
        rows.append((sha256(b), os.path.relpath(p, HERE)))
    rows.append((sha256(rd(os.path.join(HERE, "S0_G2_readonly.sql"))), "S0_G2_readonly.sql"))
    rows.append((sha256(rd(os.path.abspath(__file__))), "build_g2_chain.py"))
    out[os.path.join(HERE, "G2_MANIFEST.sha256")] = "".join(f"{h}  {p}\n" for h, p in rows).encode("utf-8")
    if "--check" in sys.argv[1:]:
        bad = [os.path.relpath(p, HERE) for p, b in out.items() if not os.path.exists(p) or rd(p) != b]
        print("EM DIA" if not bad else "DESATUALIZADO: " + ", ".join(bad))
        return 1 if bad else 0
    for p, b in out.items():
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, "wb").write(b)
    print(f"gerado: {len(out)} arquivos")
    return 0


if __name__ == "__main__":
    sys.exit(main())
