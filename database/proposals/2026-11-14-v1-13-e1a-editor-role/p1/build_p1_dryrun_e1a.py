#!/usr/bin/env python3
"""
V1-13 · E1-A — gerador do ensaio transacional P1 (VALIDATION-STRATEGY-E1A.md v1.1 §2.2).

Gera P1_DRYRUN_E1A_rollback.sql a partir dos arquivos APROVADOS da pasta-mãe:
  5366–5370 (texto entre os próprios `begin;` e `commit;`, sem alteração) e
  5888 (as quatro funções pg_temp, sem alteração).
Não conecta em banco, não executa SQL.

Uso:
    python3 -I build_p1_dryrun_e1a.py           # gera/atualiza o arquivo e o MANIFEST
    python3 -I build_p1_dryrun_e1a.py --check   # só confere: arquivo e MANIFEST em dia (código 0) ou não (1)

O arquivo gerado NÃO está pronto para execução: depende da S0
(P1_S0_POST_readonly.sql) e de autorização expressa e específica do proprietário.
"""
from __future__ import annotations

import hashlib
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.dirname(HERE)
OUT = os.path.join(HERE, "P1_DRYRUN_E1A_rollback.sql")
S0 = os.path.join(HERE, "P1_S0_POST_readonly.sql")
MANIFEST = os.path.join(HERE, "MANIFEST.sha256")
TXID = os.path.join(HERE, "P1_POST_txid_readonly.sql")

MIGRATIONS = [
    "5366_widen_collection_membership_role_editor.sql",
    "5367_create_collection_member_role_function.sql",
    "5368_expose_member_role_in_sharing_reads.sql",
    "5369_replace_invite_collection_member_with_role.sql",
    "5370_create_set_collection_member_role_function.sql",
]
HARNESS = "5888_validate_editor_role_foundation_HARNESS.sql"
HARNESS_FIRST = "create or replace function pg_temp.wh_5888_as(p_user uuid)"
HARNESS_LAST = "$fn$;"
EXPECTED_CHECKS = 54


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_bytes(path: str) -> bytes:
    with open(path, "rb") as fh:
        data = fh.read()
    if b"\r" in data:
        raise SystemExit(f"ERRO: CRLF em {path}")
    return data


def migration_body(name: str) -> str:
    text = read_bytes(os.path.join(SRC, name)).decode("utf-8")
    lines = text.split("\n")
    b = [i for i, l in enumerate(lines) if l == "begin;"]
    c = [i for i, l in enumerate(lines) if l == "commit;"]
    if len(b) != 1 or len(c) != 1 or not b[0] < c[0]:
        raise SystemExit(f"ERRO: {name} precisa ter exatamente um 'begin;' e um 'commit;' em linha própria")
    return "\n".join(lines[b[0] + 1 : c[0]]).strip("\n")


def harness_body() -> str:
    text = read_bytes(os.path.join(SRC, HARNESS)).decode("utf-8")
    i = text.index(HARNESS_FIRST)
    j = text.index(HARNESS_LAST, text.index("create or replace function pg_temp.wh_5888_validate()")) + len(HARNESS_LAST)
    return text[i:j]


HEADER = """/*
================================================================
Projeto.....: Project Mimikyu
Arquivo.....: P1_DRYRUN_E1A_rollback.sql — ensaio transacional P1 da E1-A (5366–5370 + 5888)
Versão......: 1.1 (2026-11-15, `V1-13 / E1-A | P1 INDEPENDENT ARTIFACT AUDIT-04`: desfecho
              inequívoco por SQLSTATE próprio; LOCK NOWAIT antes da T7; VERBOSITY verbose;
              sessão sem início visível conta como risco). 1.0 (`P1 ARTIFACT PREPARATION-03`)
Status......: GERADO por build_p1_dryrun_e1a.py — NÃO EDITAR À MÃO (o verificador recusa).
              NÃO EXECUTADO. EXECUÇÃO BLOQUEADA até: (1) S0 só leitura
              (P1_S0_POST_readonly.sql) executada e aprovada; (2) revisão
              independente deste arquivo e do verificador; (3) autorização
              expressa e específica do proprietário (hash, executor, canal,
              janela). C-244 (revisão 1.38): esta preparação não autoriza execução.
Fontes......: {sources}
Protocolo...: VALIDATION-STRATEGY-E1A.md v1.1 §2.

----------------------------------------------------------------
A. Canal (único aceito)
----------------------------------------------------------------
  psql -X -v ON_ERROR_STOP=1 -f P1_DRYRUN_E1A_rollback.sql
  em conexão DIRETA única (nunca pooler em modo transação/statement), não
  interativo, sem -1/--single-transaction. A linha `\\set ON_ERROR_STOP on`
  repete a proteção dentro do arquivo e faz qualquer canal que não seja o
  psql (SQL Editor, execute_sql, apply_migration) falhar na PRIMEIRA linha,
  antes de qualquer instrução SQL. `\\set VERBOSITY verbose` faz o psql
  mostrar o SQLSTATE de cada erro (necessário para classificar o desfecho).

----------------------------------------------------------------
B. Estrutura (ordem exata; marcadores "-- @@Tn" conferidos pelo verificador)
----------------------------------------------------------------
  T0  SET SESSION default_transaction_read_only = on   padrão da SESSÃO; guarda contra
                                                       instrução que escape do bloco
  T1  BEGIN                                            único bloco explícito
  T2  SET TRANSACTION READ WRITE                       só esta transação escreve
  T3  SET LOCAL lock_timeout 2s, statement_timeout 20s,
      idle_in_transaction_session_timeout 15s; DO: recusa PG < 14,
      client_connection_check_interval 1s, transaction_timeout 60s se PG >= 17
  T4  trava de COMMIT: FK temporária DEFERRABLE INITIALLY DEFERRED violada
  T5  tabelas temporárias de evidência
  T6  DO precheck (só leitura + evidência); LOCK TABLE collection_membership
      IN ACCESS EXCLUSIVE MODE NOWAIT (obtém na hora ou falha, sem entrar em fila)
  T7  5366 → 5370, texto aprovado, nível superior (cada uma com seus pre/postchecks;
      cada migration redefine lock_timeout para 5s — valor efetivo durante a T7)
  T8  5888: quatro funções pg_temp + INSERT do relatório na evidência
  T9  DO postcheck (só leitura) e DO sentinela: um único RAISE, sempre, com
      SQLSTATE E1AOK (aprovado) ou E1ANO (reprovado)
  T10 ROLLBACK                                         só alcançado fora do contrato
  T11 RESET default_transaction_read_only              idem
  Não há COMMIT, END, SAVEPOINT, RELEASE, PREPARE TRANSACTION nem SET CONSTRAINTS.

----------------------------------------------------------------
C. Por que não confirma (demonstrável × operacional: VALIDATION-STRATEGY §2.4)
----------------------------------------------------------------
  Caminho normal termina em erro (T9) → aborto; psql sai; conexão fecha.
  COMMIT após erro → ROLLBACK. COMMIT com T9 removido → FK adiada de T4 falha.
  BEGIN ignorado → T0 deixa cada instrução somente leitura → 25006 no 1º DDL.
  Operacional: arquivo íntegro (hash/verificador), conexão direta única, executor
  sob contrato. Nada disso é provado por análise estática.

----------------------------------------------------------------
D. Resultado esperado
----------------------------------------------------------------
  Classificação pelo ÚLTIMO erro que o psql mostra (VERBOSITY verbose: SQLSTATE
  e linha do arquivo) e pelo código de saída do psql (3 = parou em erro):
    E1AOK + 'MSDRYRUN_E1A APROVADO {{json}}'  → ensaio concluído e aprovado
                                               ({total}/{total}, trava intacta, ≤ 10 s)
    E1ANO + 'MSDRYRUN_E1A REPROVADO {{json}}' → harness rodou (ou a fixture falhou:
                                               "erro_na_fixture"); reprovado
    outro SQLSTATE/mensagem                    → falha ANTES da sentinela; a linha
                                               indica a fase (T3–T6 ambiente, T7
                                               migration, T8 harness, T9 postcheck)
    nenhum erro / código de saída 0            → anomalia grave: STOP
  Rollback efetivado: txid do JSON → P1_POST_txid_readonly.sql = 'aborted'.
  Estado posterior: P1_S0_POST_readonly.sql, chaves determinísticas iguais à S0.
  Nenhum desfecho é PASS só porque a transação terminou em rollback.
================================================================
*/
"""

T3_DO = """do $t3$
begin
  if pg_catalog.current_setting('server_version_num')::int < 140000 then
    raise exception 'P1 T3: PostgreSQL < 14 — ensaio RECUSADO';
  end if;
  perform pg_catalog.set_config('client_connection_check_interval', '1s', true);
  if pg_catalog.current_setting('server_version_num')::int >= 170000 then
    perform pg_catalog.set_config('transaction_timeout', '60s', true);
  end if;
end;
$t3$;"""

T4 = """create temp table p1_e1a_trap_parent (id integer primary key) on commit drop;
create temp table p1_e1a_trap_child (
  parent_id integer not null
    constraint p1_e1a_trap_fk references p1_e1a_trap_parent (id) deferrable initially deferred
) on commit drop;
insert into p1_e1a_trap_child (parent_id) values (1);"""

T5 = """create temp table p1_e1a_evidence (seq integer, check_id text, status text, detail text) on commit drop;
create temp table p1_e1a_meta (k text primary key, v jsonb not null) on commit drop;"""

T6 = r"""do $t6$
declare
  v_ext jsonb;
  v_evt jsonb;
  v_long integer;
begin
  -- Ambiente da transação.
  if pg_catalog.current_setting('transaction_read_only') <> 'off' then
    raise exception 'P1 T6: transação não está READ WRITE';
  end if;
  if pg_catalog.current_setting('default_transaction_read_only') <> 'on' then
    raise exception 'P1 T6: T0 não vigora nesta sessão (pooler/troca de backend?) — RECUSAR';
  end if;
  if pg_catalog.current_setting('session_replication_role') <> 'origin' then
    raise exception 'P1 T6: session_replication_role <> origin (gatilhos não disparariam)';
  end if;
  if pg_catalog.pg_is_in_recovery() then
    raise exception 'P1 T6: servidor em recuperação';
  end if;
  if current_user <> 'postgres' or session_user <> 'postgres' then
    raise exception 'P1 T6: executor deve ser postgres (dono das funções), sem SET ROLE';
  end if;
  -- Trava de COMMIT presente e adiada.
  if (select count(*) from pg_temp.p1_e1a_trap_child) <> 1
     or not exists (select 1 from pg_catalog.pg_constraint k
                    where k.conname = 'p1_e1a_trap_fk' and k.contype = 'f'
                      and k.condeferrable and k.condeferred
                      and k.conrelid = 'pg_temp.p1_e1a_trap_child'::regclass) then
    raise exception 'P1 T6: trava de COMMIT ausente ou não adiada';
  end if;
  -- Efeitos externos: gatilhos das tabelas tocadas e gatilhos de evento.
  select coalesce(jsonb_agg(jsonb_build_object('tabela', c.relname, 'gatilho', t.tgname, 'funcao', p.proname)), '[]'::jsonb)
    into v_ext
  from pg_catalog.pg_trigger t
  join pg_catalog.pg_class c on c.oid = t.tgrelid
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  join pg_catalog.pg_proc p on p.oid = t.tgfoid
  where not t.tgisinternal
    and n.nspname in ('public', 'auth')
    and c.relname in ('users', 'collection_membership', 'collection', 'expansion', 'card_set', 'card',
                      'card_variant', 'physical_card', 'inventory', 'user_profile', 'collection_allocation',
                      'collection_layout', 'collection_layout_page', 'collection_layout_slot',
                      'collection_layout_slot_assignment', 'collection_layout_slot_expected_content',
                      'binder_activity_event', 'binder_activity_item')
    and p.prosrc ~* '(net\.|http_|pg_net|dblink|pg_notify|notify\s)';
  if jsonb_array_length(v_ext) > 0 then
    raise exception 'P1 T6: gatilho com possível efeito externo: % — RECUSAR', v_ext;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('evento', e.evtname, 'funcao', p.proname)), '[]'::jsonb)
    into v_evt
  from pg_catalog.pg_event_trigger e
  join pg_catalog.pg_proc p on p.oid = e.evtfoid
  where e.evtenabled <> 'D'
    and p.prosrc ~* '(net\.|http_|pg_net|dblink)';
  if jsonb_array_length(v_evt) > 0 then
    raise exception 'P1 T6: gatilho de evento com possível efeito externo: % — RECUSAR', v_evt;
  end if;
  -- Nenhuma outra sessão segurando collection_membership há mais de 1 s.
  select count(*) into v_long
  from pg_catalog.pg_locks l
  join pg_catalog.pg_stat_activity a on a.pid = l.pid
  where l.relation = 'public.collection_membership'::regclass
    and l.pid <> pg_catalog.pg_backend_pid()
    and (a.xact_start is null  -- sem pg_read_all_stats o início não é visível: conta como risco
         or a.xact_start < pg_catalog.clock_timestamp() - interval '1 second');
  if v_long > 0 then
    raise exception 'P1 T6: % sessão(ões) com lock antigo em collection_membership — RECUSAR', v_long;
  end if;
  insert into pg_temp.p1_e1a_meta (k, v) values
    ('t_start', to_jsonb(pg_catalog.clock_timestamp())),
    ('server_version_num', to_jsonb(pg_catalog.current_setting('server_version_num')::int)),
    ('event_triggers', (select coalesce(jsonb_agg(e.evtname order by e.evtname), '[]'::jsonb)
                          from pg_catalog.pg_event_trigger e where e.evtenabled <> 'D'));
end;
$t6$;"""

T6_LOCK = """LOCK TABLE public.collection_membership IN ACCESS EXCLUSIVE MODE NOWAIT;
insert into pg_temp.p1_e1a_meta (k, v) values ('t_lock', to_jsonb(pg_catalog.clock_timestamp()));"""

T8_RUN = "insert into pg_temp.p1_e1a_evidence (seq, check_id, status, detail)\n  select seq, check_id, status, detail from pg_temp.wh_5888_validate();"

T9_POST = """do $t9post$
begin
  -- Só leitura: estado transitório das migrations dentro da transação.
  if (select pg_catalog.pg_get_constraintdef(k.oid) from pg_catalog.pg_constraint k
       where k.conrelid = 'public.collection_membership'::regclass
         and k.conname = 'chk_collection_membership_role')
     is distinct from 'CHECK ((role = ANY (ARRAY[''VIEWER''::text, ''EDITOR''::text])))'
     or to_regprocedure('public.collection_member_role(uuid)') is null
     or to_regprocedure('public.set_collection_member_role(uuid, uuid, text)') is null
     or to_regprocedure('public.invite_collection_member(uuid, text, text)') is null
     or to_regprocedure('public.invite_collection_member(uuid, text)') is not null then
    raise exception 'P1 T9: estado transitório das migrations inesperado';
  end if;
  if current_user <> session_user then
    raise exception 'P1 T9: papel não restaurado depois da 5888';
  end if;
end;
$t9post$;"""

T9_SENTINEL = """do $t9sentinel$
declare
  v_total    integer;
  v_gate     text;
  v_passes   integer;
  v_failed   jsonb;
  v_fixture  jsonb;
  v_trap     boolean;
  v_ms       numeric;
  v_lock_ms  numeric;
  v_ok       boolean;
  v_code     text;
  v_msg      text;
begin
  select count(*) filter (where check_id <> 'GATE'),
         max(status) filter (where check_id = 'GATE'),
         count(*) filter (where check_id <> 'GATE' and status = 'PASS'),
         coalesce(jsonb_agg(check_id order by seq) filter (where check_id <> 'GATE' and status <> 'PASS'), '[]'::jsonb),
         coalesce(jsonb_agg(detail order by seq) filter (where check_id in ('F.1', 'X.1')), '[]'::jsonb)
    into v_total, v_gate, v_passes, v_failed, v_fixture
  from pg_temp.p1_e1a_evidence;
  v_trap := (select count(*) from pg_temp.p1_e1a_trap_child) = 1;
  v_ms := round(extract(epoch from (pg_catalog.clock_timestamp()
           - (select (v #>> '{}')::timestamptz from pg_temp.p1_e1a_meta where k = 't_start'))) * 1000);
  v_lock_ms := round(extract(epoch from (pg_catalog.clock_timestamp()
           - (select (v #>> '{}')::timestamptz from pg_temp.p1_e1a_meta where k = 't_lock'))) * 1000);
  v_ok := coalesce(v_gate = 'PASS' and v_total = {total} and v_passes = {total} and v_trap and v_ms <= 10000, false);
  -- Desfecho codificado em DOIS lugares, para não confundir com nenhum outro erro:
  -- SQLSTATE próprio (E1AOK aprovado / E1ANO reprovado; nenhuma outra instrução usa
  -- esses códigos) e prefixo da mensagem. Um único RAISE, incondicional.
  v_code := case when v_ok then 'E1AOK' else 'E1ANO' end;
  v_msg := 'MSDRYRUN_E1A ' || case when v_ok then 'APROVADO ' else 'REPROVADO ' end || jsonb_build_object(
    'ok', v_ok, 'fase', 'SENTINELA', 'gate', v_gate, 'total', v_total, 'passes', v_passes,
    'harness_concluido', v_gate is not null, 'failed', v_failed, 'erro_na_fixture', v_fixture,
    'trap_intact', v_trap, 'duration_ms', v_ms, 'lock_ms', v_lock_ms,
    'server_version_num', (select v from pg_temp.p1_e1a_meta where k = 'server_version_num'),
    'event_triggers', (select v from pg_temp.p1_e1a_meta where k = 'event_triggers'),
    'txid', pg_catalog.txid_current_if_assigned())::text;
  raise exception using message = v_msg, errcode = v_code;
end;
$t9sentinel$;"""


def build() -> str:
    parts: list[str] = []
    srcs = []
    for name in MIGRATIONS + [HARNESS]:
        srcs.append(f"{name[:4]}@{sha256(read_bytes(os.path.join(SRC, name)))[:16]}")
    parts.append(HEADER.format(sources=", ".join(srcs), total=EXPECTED_CHECKS))
    parts.append("\\set ON_ERROR_STOP on\n\\set VERBOSITY verbose\n")
    parts.append("-- @@T0 padrão da sessão somente leitura\nSET SESSION default_transaction_read_only = on;\n")
    parts.append("-- @@T1 bloco explícito\nBEGIN;\n")
    parts.append("-- @@T2 esta transação escreve\nSET TRANSACTION READ WRITE;\n")
    parts.append("-- @@T3 limites\nSET LOCAL lock_timeout = '2s';\nSET LOCAL statement_timeout = '20s';\n"
                 "SET LOCAL idle_in_transaction_session_timeout = '15s';\n" + T3_DO + "\n")
    parts.append("-- @@T4 trava de COMMIT\n" + T4 + "\n")
    parts.append("-- @@T5 evidência\n" + T5 + "\n")
    parts.append("-- @@T6 precheck\n" + T6 + "\n")
    parts.append("-- @@T6 lock imediato ou recusa (NOWAIT: não entra em fila)\n" + T6_LOCK + "\n")
    for name in MIGRATIONS:
        sha = sha256(read_bytes(os.path.join(SRC, name)))
        parts.append(f"-- @@T7 {name} sha256={sha}\n" + migration_body(name) + "\n")
    sha = sha256(read_bytes(os.path.join(SRC, HARNESS)))
    parts.append(f"-- @@T8 {HARNESS} sha256={sha}\n" + harness_body() + "\n")
    parts.append("-- @@T8 relatório\n" + T8_RUN + "\n")
    parts.append("-- @@T9 postcheck\n" + T9_POST + "\n")
    parts.append("-- @@T9 sentinela\n" + T9_SENTINEL.replace("{total}", str(EXPECTED_CHECKS)) + "\n")
    parts.append("-- @@T10 fora do contrato\nROLLBACK;\n")
    parts.append("-- @@T11 fora do contrato\nRESET default_transaction_read_only;\n")
    return "\n".join(parts)


def manifest(artifact: bytes) -> str:
    rows = []
    for name in MIGRATIONS + [HARNESS]:
        rows.append((sha256(read_bytes(os.path.join(SRC, name))), f"../{name}"))
    rows.append((sha256(artifact), "P1_DRYRUN_E1A_rollback.sql"))
    rows.append((sha256(read_bytes(S0)), "P1_S0_POST_readonly.sql"))
    rows.append((sha256(read_bytes(TXID)), "P1_POST_txid_readonly.sql"))
    rows.append((sha256(read_bytes(os.path.abspath(__file__))), "build_p1_dryrun_e1a.py"))
    return "".join(f"{h}  {p}\n" for h, p in rows)


def main() -> int:
    artifact = build().encode("utf-8")
    man = manifest(artifact).encode("utf-8")
    if "--check" in sys.argv[1:]:
        ok = (os.path.exists(OUT) and read_bytes(OUT) == artifact
              and os.path.exists(MANIFEST) and read_bytes(MANIFEST) == man)
        print("EM DIA" if ok else "DESATUALIZADO")
        return 0 if ok else 1
    with open(OUT, "wb") as fh:
        fh.write(artifact)
    with open(MANIFEST, "wb") as fh:
        fh.write(man)
    print(f"gerado: {os.path.basename(OUT)} sha256={sha256(artifact)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
