#!/usr/bin/env python3
"""Gera LIVE_DRYRUN_S1_rollback_v2.3.sql (v2.3) a partir das migrations 5267–5270.

v2.3: o precheck T6 exige o baseline do ledger LEDGER_BASELINE (versão e nome da última
migration do LIVE — correção MEP de 2026-10-26); fonte única, conferida contra LIVE_00 v1.1
e gate v1.2 pelo static_check (S.20). v2.2 e v2.1 ficam preservadas sem alteração.

v2.2: o conjunto das funções da S1 usado no postcheck (90.3, 90.4, 90.10) vem do
LIVE_90 (CTE `fns`, lista explícita e canônica) — lido por canonical_functions(), nunca
redigitado aqui. A v2.1 (LIVE_DRYRUN_S1_rollback.sql) fica preservada sem alteração.

Não conecta em banco e não executa nada. Estrutura (README §21):
  · as migrations ficam no NÍVEL SUPERIOR do script, statement a statement, com o
    texto exato dos arquivos aprovados — só o `begin;` inicial e o `commit;` final
    de cada uma são retirados (a transação é a do ensaio);
  · blocos DO só para verificação (precheck, postcheck, sondas, sentinela final),
    sem DDL;
  · uma única transação explícita, aberta por BEGIN e encerrada por ROLLBACK, com
    trava de COMMIT (FK temporária DEFERRABLE violada) e guarda de autocommit
    (default_transaction_read_only na sessão + SET TRANSACTION READ WRITE).

Uso:
  python3 build_live_dryrun_s1.py            # (re)gera o arquivo
  python3 build_live_dryrun_s1.py --check    # só confere se o arquivo está em dia (exit 1 se não)
"""
import hashlib
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import sql_lexer_p3b as lex  # noqa: E402

OUT = HERE / "LIVE_DRYRUN_S1_rollback_v2.3.sql"
# baseline do ledger LIVE (última migration) desde 2026-10-26 — correção MEP, autorizada por Fabrício
LEDGER_BASELINE = ("20261026124224", "fix_mep_bootstrap_preserve_confirmed_primary_identity")
LIVE90 = HERE / "LIVE_90_postcheck_readonly.sql"
SOURCES = ["5267_create_binder_activity_structures.sql",
           "5268_create_binder_activity_recording_functions.sql",
           "5269_create_binder_activity_reads.sql",
           "5270_create_binder_activity_purge_and_legacy.sql"]

HEADER = r"""/*
================================================================
Projeto.....: Project Mimikyu
Arquivo.....: LIVE_DRYRUN_S1_rollback_v2.3.sql — ensaio da P3-B S1 no LIVE com reversão total
Versão......: 2.3 (2026-10-27, E3 BASELINE RECONCILIATION — MEP-01: precheck T6 exige o último ledger
              @@LEDGER_V@@ @@LEDGER_N@@ (versão e nome); nada mais muda)
              2.2 (2026-10-26, P3-B S1 E3 DRY-RUN v2.2: T8a identifica as 10 funções da S1
              pela lista canônica do LIVE_90 (90.3, 90.4, 90.10); v2.1 falhou nesses itens
              porque usava like '%binder_activity%' e omitia list_my_closed_binder_histories)
              2.1 (2026-10-25, P3-B-S1-FINAL-READINESS-03: só cabeçalho — locks,
              lock_timeout, contrato do executor, restauração da sessão; SQL inalterado)
              2.0 (P3-B-S1-LIVE-DRYRUN-STRUCTURAL-CORRECTION-02)
              1.0 (P3-B-S1-SECURITY-CORRECTION-01) SUBSTITUÍDA: embutia as migrations
              num único bloco DO PL/pgSQL (defeito apontado pela auditoria).
Status......: PROPOSTA — NÃO EXECUTADO. GERADO por build_live_dryrun_s1.py; não editar à
              mão (S.18 recusa divergência). Execução só com autorização expressa e
              específica de Fabrício para o ENSAIO (não abre G8).
Fontes......: {sources}

----------------------------------------------------------------
A. Estrutura transacional (ordem exata dos statements)
----------------------------------------------------------------
  T0  SET SESSION default_transaction_read_only = on      guarda de autocommit
  T1  BEGIN                                                 única abertura
  T2  SET TRANSACTION READ WRITE                            só esta transação escreve
  T3  SET LOCAL statement_timeout / lock_timeout /
      idle_in_transaction_session_timeout / transaction_timeout
  T4  trava de COMMIT: 2 tabelas temporárias + 1 linha que viola uma FK
      DEFERRABLE INITIALLY DEFERRED → qualquer COMMIT desta transação falha
  T5  tabela temporária de evidência
  T6  DO precheck (só leitura + evidência)
  T7  5267 → 5270, statement a statement, texto idêntico ao aprovado, no nível
      superior (sem os `begin;`/`commit;` próprios)
  T8  DO postcheck, DO sondas (só verificação; nenhuma DDL)
  T9  DO sentinela: RAISE EXCEPTION 'MSDRYRUN {{json}}' — SEMPRE
  T10 ROLLBACK
  T11 RESET default_transaction_read_only
  Não há COMMIT, END, SAVEPOINT nem SET CONSTRAINTS em nenhum ponto (S.18c/S.18h).

----------------------------------------------------------------
B. Por que o ensaio não pode confirmar alterações
----------------------------------------------------------------
  1. Caminho normal termina em ERRO (T9): a transação aborta e tudo é desfeito.
  2. COMMIT enviado por engano com a transação abortada: o PostgreSQL responde
     ROLLBACK (comportamento padrão de COMMIT em bloco abortado).
  3. COMMIT enviado com a transação ainda ativa (ex.: alguém remove T9): a
     verificação adiada da FK de T4 falha no COMMIT e a transação é desfeita.
  4. Executor que ignora o BEGIN e confirma statement a statement: T0 deixou a
     sessão em somente leitura; T2 vira só um aviso; todo CREATE/INSERT em
     public falha com 25006 (read-only transaction). Nada persiste; a sessão
     fica em somente leitura até RESET/reconexão (falha segura).
  5. Envio do script inteiro numa só mensagem (Supabase SQL Editor, execute_sql):
     T0 roda dentro do bloco convertido pelo BEGIN e é desfeito pelo
     ROLLBACK/aborto; qualquer erro descarta o resto da mensagem.
  Única forma de confirmar algo: editar o arquivo (remover T0/T4/T9 e incluir
  COMMIT) — bloqueado pelo S.18 e fora de qualquer autorização.

----------------------------------------------------------------
C. Comportamento diante de erros
----------------------------------------------------------------
  | Momento                          | Efeito                                         |
  | T0–T5 (antes da aplicação)       | transação abortada; nada criado; STOP          |
  | T6 precheck falha                | 'DRYRUN PRECHECK FALHOU' → abortada; STOP      |
  | T7 statement de migration falha  | abortada; DDL parcial descartada; STOP         |
  |  (inclui lock_timeout/statement) |                                                |
  | T8 postcheck/sonda diverge       | 'DRYRUN POSTCHECK FALHOU {{json}}' → abortada; |
  |                                  | STOP                                           |
  | T9 caminho normal                | 'MSDRYRUN {{"ok":true,…}}' → abortada (esperado)|
  Em qualquer aborto, o PostgreSQL libera locks e reverte SET LOCAL na hora do
  erro; a sessão fica em "idle in transaction (aborted)" até ROLLBACK ou fim da
  conexão, sem segurar locks.

----------------------------------------------------------------
D. Contrato do executor (obrigatório; README §23)
----------------------------------------------------------------
  D1 Conexão única: todo o script na MESMA conexão, do T0 ao T11. Proibido
     pooler em modo transação/statement que troque de backend entre comandos.
  D2 Execução integral: o arquivo inteiro, na ordem, sem edição, sem seleção de
     trechos, sem acrescentar comandos. Hash do arquivo conferido antes (S.18a).
  D3 Formas aceitas (uma só):
     E1 script inteiro numa única mensagem simple-query (SQL Editor do Supabase;
        execute_sql), sem parâmetros;
     E2 psql NÃO interativo: psql -X -v ON_ERROR_STOP=1 -f LIVE_DRYRUN_S1_rollback_v2.3.sql
        (sem -1/--single-transaction, sem \i dentro de sessão interativa).
  D4 Tratamento de erros: parar no primeiro erro. O erro esperado é o da T9
     ('MSDRYRUN …'); qualquer outro é STOP. Não reexecutar, não completar à mão,
     não enviar COMMIT.
  D5 Recuperação da sessão, sempre, no fim, qualquer que seja o resultado:
     fechar a conexão. Se a conexão precisar continuar aberta (ferramenta que
     reaproveita a sessão): enviar ROLLBACK; e depois
     RESET default_transaction_read_only; e conferir
     SHOW default_transaction_read_only = off antes de qualquer outro uso.
  D6 Interrupção / perda de conexão: o servidor desfaz a transação ao perceber a
     queda (ao fim do statement corrente, limitado por statement_timeout);
     ocioso em transação ativa → idle_in_transaction_session_timeout (15 s)
     encerra a sessão. Depois, conferir o pós-estado (item 8). Não repetir.

----------------------------------------------------------------
E. Restauração de default_transaction_read_only por caminho
----------------------------------------------------------------
  T0 é SET de sessão. Se ele é desfeito depende de ter rodado dentro ou fora da
  transação do ensaio (por inspeção do código do PostgreSQL; não exercitado):
  | Caminho                                   | T0 fica na sessão?          |
  | E1 mensagem única (T0 no bloco implícito  | não: o BEGIN converte o     |
  |    convertido pelo BEGIN)                 | bloco; o aborto desfaz T0   |
  | E2 psql -f, para no erro da T9            | sim, mas a conexão fecha    |
  |                                           | ao sair → sem resíduo       |
  | executor que continua após erro           | não: T10 ROLLBACK + T11     |
  |                                           | RESET restauram             |
  | \i interativo / ferramenta que para no    | SIM — resíduo: sessão em    |
  |    erro e mantém a sessão aberta          | somente leitura até D5      |
  | executor que ignora o BEGIN e para no erro| SIM — idem (falha segura)   |
  O resíduo nunca permite escrita: só deixa a sessão em somente leitura. Por
  isso D5 (fechar a conexão ou RESET + SHOW) é parte obrigatória do contrato e
  item do pós-estado (8). SET LOCAL, papel (SET ROLE), claims, tabelas
  temporárias e locks não deixam resíduo em nenhum caminho: são desfeitos no
  aborto ou no ROLLBACK.

----------------------------------------------------------------
1. SQL exato           → corpos das 5267–5270 em T7, statement a statement,
                         idênticos aos arquivos (hash acima; S.18e compara
                         statement por statement com o lexer).
2. Objetos temporários → 4 tabelas, sequência da identidade, 1 índice, 4
                         gatilhos, 10 funções, 1 linha em _setting, 1 evento
                         LEGADO + 1 item (cópia real da Chi-Yu); 3 tabelas
                         temporárias do ensaio. Nada existente é alterado.
3. Locks               → auth.users: SHARE ROW EXCLUSIVE, pedido pela primeira
                         FK da 5267 e mantido até o fim da transação (aborto ou
                         ROLLBACK). Compatível com SELECT comum (ACCESS SHARE) e
                         com SELECT … FOR UPDATE/SHARE e verificações de FK de
                         outras tabelas (ROW SHARE). Conflita com INSERT/UPDATE/
                         DELETE em auth.users (ROW EXCLUSIVE) e com VACUUM/
                         ANALYZE dela. Autenticação: a validação do JWT nas
                         requisições não lê auth.users no banco; leituras de
                         login seguem; o que ESCREVE em auth.users (cadastro,
                         gravação de last_sign_in_at no login, confirmação de
                         e-mail, alteração de dados/senha, exclusão) espera até
                         o fim do ensaio. Ao pedir o lock, a 5267 espera
                         escritores já em curso em auth.users (até 2 s) e, nessa
                         espera, novos escritores entram na fila atrás dela;
                         leitores não. Tabelas novas: locks invisíveis a outras
                         sessões. Leituras (ACCESS SHARE) em collection_layout,
                         collection, *_catalog_incorporation, card, card_set,
                         card_variant_type.
4. Não revertido       → xid e OIDs consumidos; WAL; tuplas mortas no catálogo
                         (autovacuum); pg_stat_* e pg_stat_statements; logs.
                         Sem resíduo de sequência, ledger, NOTIFY (pgrst_ddl_watch
                         só entrega em COMMIT), grants, GUCs ou dados.
5. Tempo e recursos    → lock_timeout 2 s limita só a ESPERA para obter cada
                         lock; não limita quanto tempo o lock obtido fica
                         mantido. A duração do lock em auth.users = do statement
                         da 5267 até o fim da transação, limitada por: statement
                         20 s (cada statement); ocioso 15 s; transação 60 s
                         (transaction_timeout definido dentro da transação:
                         conforme o PG 17 passa a contar a partir do SET — não
                         comprovado por execução). Esperado < 2 s no total.
                         Janela fora de uso (item 3).
6. STOP                → qualquer erro que não comece com 'MSDRYRUN'; 'ok':false;
                         duration_ms > 5000; pós-estado (item 8) divergente. Não
                         repetir sem nova autorização.
7. Evidência           → erro P0001 'MSDRYRUN {{json}}' com precheck, 90.2–90.12,
                         sondas, contagens, txid e duration_ms; em E2 também as
                         linhas de evidência impressas antes do erro (NOTICE).
8. Pós-estado          → LIVE_00 inteiro true (ledger @@LEDGER_V@@, nenhum objeto
                         binder_activity_*, 5267–5270 livres, 1 incorporação);
                         nenhuma sessão do ensaio em pg_stat_activity;
                         nenhum lock em auth.users vindo dela (pg_locks);
                         conexão fechada, ou SHOW default_transaction_read_only
                         = off na sessão reaproveitada (D5, seção E).
9. Limitações          → NÃO prova: sintaxe por parser antes da execução, concorrência,
                         desempenho, gravação real, exclusões com dados,
                         apply_migration/ledger. Sondas rodam como postgres com
                         SET ROLE (não exercitam PostgREST/JWT). O lexer do S.18
                         valida estrutura léxica, não gramática.
================================================================
*/
"""

PROLOGUE = r"""
-- T0 guarda de autocommit (falha segura se o executor ignorar o BEGIN)
set session default_transaction_read_only = on;

-- T1/T2 única transação do ensaio
begin;
set transaction read write;

-- T3 limites
set local statement_timeout = '20s';
set local lock_timeout = '2s';
set local idle_in_transaction_session_timeout = '15s';
set local transaction_timeout = '60s';

-- T4 trava de COMMIT: a linha abaixo viola a FK adiada; qualquer COMMIT falha
create temporary table mmkyu_dryrun_veto_parent (id integer primary key);
create temporary table mmkyu_dryrun_veto_child (
  parent_id integer not null
            references mmkyu_dryrun_veto_parent (id) deferrable initially deferred
);
insert into mmkyu_dryrun_veto_child (parent_id) values (1);

-- T5 evidência
create temporary table mmkyu_dryrun_evidence (k text primary key, v jsonb not null);

-- T6 precheck (só leitura)
do $dry_pre$
begin
  if current_setting('transaction_read_only') <> 'off'
     or not exists (select 1 from pg_temp.mmkyu_dryrun_veto_child)
     or current_setting('session_replication_role') <> 'origin'
     or coalesce(current_setting('mmkyu.binder_activity_purge', true), '') <> ''
     or coalesce(current_setting('mmkyu.binder_activity_ctx', true), '') <> ''
     or coalesce((select version || '|' || name from supabase_migrations.schema_migrations order by version desc limit 1), '')
          <> '@@LEDGER_BASELINE@@'
     or exists (select 1 from supabase_migrations.schema_migrations where name ~ '^(5267|5268|5269|5270)_')
     or exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                where n.nspname = 'public' and c.relname like 'binder_activity%')
     or exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                where n.nspname = 'public' and p.proname like '%binder_activity%')
     or (select count(*) from public.collection_layout_catalog_incorporation) <> 1 then
    raise exception 'DRYRUN PRECHECK FALHOU — STOP' using errcode = 'P0001';
  end if;
  insert into pg_temp.mmkyu_dryrun_evidence values
    ('precheck', 'true'::jsonb), ('txid', to_jsonb(pg_current_xact_id()::text));
end;
$dry_pre$;

-- T7 migrations 5267 → 5270 (texto aprovado, nível superior)
"""

EPILOGUE = r"""
-- T8a postcheck (LIVE_90 sem 90.1, que depende do ledger)
do $dry_post$
declare
  v_eval jsonb;
  v_fns  text[] := array[@@CANONICAL_FNS@@];  -- lista canônica do LIVE_90 (CTE fns), gerada pelo builder
begin
  v_eval := jsonb_build_object(
    '90.2', (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
             where n.nspname = 'public' and c.relname in ('binder_activity_event','binder_activity_item',
                   'binder_activity_coverage','binder_activity_setting') and c.relrowsecurity) = 4
            and not exists (select 1 from unnest(array['public.binder_activity_event','public.binder_activity_item',
                                    'public.binder_activity_coverage','public.binder_activity_setting']) t(tbl),
                                  unnest(array['anon','authenticated','service_role']) r(rol),
                                  unnest(array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE']) pv(priv)
                            where has_table_privilege(r.rol, t.tbl, pv.priv)),
    '90.3', (select count(*) = cardinality(v_fns) and bool_and(p.proconfig @> array['search_path=""']
                                    and p.prosecdef = (p.proname <> 'binder_activity_category'))
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname = any(v_fns)),
    '90.4', (select bool_and(has_function_privilege('authenticated', p.oid, 'EXECUTE')
                             = (p.proname in ('get_my_binder_activity','get_my_binder_activity_coverage','list_my_closed_binder_histories'))
                             and not has_function_privilege('anon', p.oid, 'EXECUTE'))
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname = any(v_fns)),
    '90.5', (select count(*) from pg_trigger t where not t.tgisinternal
               and t.tgname in ('trg_bae_immutable','trg_bae_no_truncate','trg_bai_immutable','trg_bai_no_truncate')) = 4,
    '90.6', (select count(*) from public.binder_activity_event where source = 'LEGADO') = 1
            and not exists (select 1 from public.binder_activity_event where source = 'LEGADO' and actor_user_id is not null)
            and (select count(*) from public.binder_activity_item) = 1,
    '90.7', not exists (select 1 from public.binder_activity_item where from_page is not null or to_page is not null),
    '90.8', not exists (select 1 from public.binder_activity_event where source <> 'LEGADO'),
    '90.9', (select full_coverage_from is null from public.binder_activity_setting where id = 1),
    '90.10', not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                         where n.nspname = 'public' and not (p.proname = any(v_fns))
                           and pg_get_functiondef(p.oid) ~* 'binder_activity_'),
    '90.11', not exists (select 1 from unnest(array['anon','authenticated','service_role']) r(rol),
                                       unnest(array['USAGE','SELECT','UPDATE']) pv(priv)
                         where has_sequence_privilege(r.rol, 'public.binder_activity_event_id_seq', pv.priv)),
    '90.12', (select count(*) from pg_constraint k where k.conrelid = 'public.binder_activity_event'::regclass and k.contype = 'f') = 1
             and to_regclass('public.ix_bae_actor') is null);
  insert into pg_temp.mmkyu_dryrun_evidence select e.key, e.value from jsonb_each(v_eval) e;
end;
$dry_post$;

-- T8b sondas (nenhuma escrita bem-sucedida; cada tentativa em subtransação)
do $dry_probe$
declare
  v_ok   boolean;
  v_hint text;
  v_n    integer;
  v_e    bigint;
  v_key  uuid;
begin
  select id, layout_key into v_e, v_key from public.binder_activity_event where source = 'LEGADO' limit 1;

  -- anon: EXECUTE revogado → 42501
  v_ok := false;
  execute 'set local role anon';
  begin
    perform count(*) from public.get_my_binder_activity(v_key);
  exception when insufficient_privilege then v_ok := true;
  end;
  execute 'reset role';
  insert into pg_temp.mmkyu_dryrun_evidence values ('probe_anon_42501', to_jsonb(v_ok));

  -- authenticated sem sessão: auth.uid() NULL → zero linhas
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  execute 'set local role authenticated';
  select count(*) into v_n from public.get_my_binder_activity(v_key);
  execute 'reset role';
  insert into pg_temp.mmkyu_dryrun_evidence values ('probe_no_session_zero_rows', to_jsonb(v_n = 0));

  -- imutabilidade (como postgres, dono das tabelas; gatilhos ativos: session_replication_role = origin)
  v_hint := null;
  begin update public.binder_activity_event set source = 'ACERVO' where id = v_e;
  exception when others then get stacked diagnostics v_hint = pg_exception_hint; end;
  insert into pg_temp.mmkyu_dryrun_evidence values ('probe_update_immutable', to_jsonb(v_hint = 'BINDER_ACTIVITY_IMMUTABLE'));
  v_hint := null;
  begin delete from public.binder_activity_event where id = v_e;
  exception when others then get stacked diagnostics v_hint = pg_exception_hint; end;
  insert into pg_temp.mmkyu_dryrun_evidence values ('probe_delete_immutable', to_jsonb(v_hint = 'BINDER_ACTIVITY_IMMUTABLE'));
  v_hint := null;
  begin truncate public.binder_activity_item;
  exception when others then get stacked diagnostics v_hint = pg_exception_hint; end;
  insert into pg_temp.mmkyu_dryrun_evidence values ('probe_truncate_immutable', to_jsonb(v_hint = 'BINDER_ACTIVITY_IMMUTABLE'));

  insert into pg_temp.mmkyu_dryrun_evidence values
    ('legacy_events', to_jsonb((select count(*) from public.binder_activity_event))),
    ('legacy_items', to_jsonb((select count(*) from public.binder_activity_item))),
    ('role_restored', to_jsonb(current_user = session_user));
end;
$dry_probe$;

-- T9 sentinela: o caminho normal SEMPRE termina em erro (nenhum COMMIT possível)
do $dry_end$
declare
  v_all jsonb;
begin
  select jsonb_object_agg(x.k, x.v) into v_all from pg_temp.mmkyu_dryrun_evidence x;
  v_all := v_all || jsonb_build_object('duration_ms',
         round(extract(epoch from (clock_timestamp() - now())) * 1000));
  v_all := jsonb_build_object('ok', not exists (
         select 1 from jsonb_each(v_all) e where jsonb_typeof(e.value) = 'boolean' and e.value = 'false'::jsonb)) || v_all;
  raise notice 'DRYRUN EVIDENCE %', v_all::text;
  if not (v_all ->> 'ok')::boolean then
    raise exception 'DRYRUN POSTCHECK FALHOU %', v_all::text using errcode = 'P0001';
  end if;
  raise exception 'MSDRYRUN %', v_all::text using errcode = 'P0001';
end;
$dry_end$;

-- T10 encerramento (alcançado só por executores que continuam após erro)
rollback;

-- T11 restaura a sessão (idem)
reset default_transaction_read_only;
"""


def migration_body(name):
    text = (HERE / name).read_text(encoding="utf-8")
    stmts = lex.split_statements(text)
    if not stmts or stmts[0].words != ["begin"] or stmts[-1].words != ["commit"]:
        raise SystemExit(f"{name}: o primeiro statement deve ser BEGIN e o último COMMIT")
    if sum(1 for s in stmts if s.words[:1] in (["begin"], ["commit"], ["rollback"], ["end"])) != 2:
        raise SystemExit(f"{name}: controle de transação além do BEGIN/COMMIT de borda")
    lines = text.split("\n")
    b = [i for i, l in enumerate(lines) if l.strip().lower() == "begin;"]
    c = [i for i, l in enumerate(lines) if l.strip().lower() == "commit;"]
    if len(b) != 1 or len(c) != 1 or b[0] > c[0]:
        raise SystemExit(f"{name}: esperado exatamente uma linha 'begin;' e uma 'commit;'")
    inner = lines[:b[0]] + lines[b[0] + 1:c[0]] + lines[c[0] + 1:]
    digest = hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]
    return f"-- ===== {name} (sha256 {digest}) — sem `begin;`/`commit;` próprios =====\n" + "\n".join(inner).strip() + "\n"


def canonical_functions():
    """Lista explícita das funções da S1 no LIVE_90 (CTE `fns`): fonte única do postcheck."""
    import re
    text = LIVE90.read_text(encoding="utf-8")
    m = re.search(r"with\s+fns\s+as\s*\(.*?p\.proname\s+in\s*\(([^)]*)\)", text, re.S | re.I)
    if not m:
        raise SystemExit("LIVE_90: CTE fns com 'p.proname in (...)' não encontrada")
    names = re.findall(r"'([a-z0-9_]+)'", m.group(1))
    if not names or len(names) != len(set(names)):
        raise SystemExit("LIVE_90: lista de funções vazia ou com repetição")
    return names


def build():
    fns = ", ".join(f"'{n}'" for n in canonical_functions())
    srcs = ", ".join(f"{s[:4]}@{hashlib.sha256((HERE / s).read_bytes()).hexdigest()[:16]}" for s in SOURCES)
    header = HEADER.replace("{sources}", srcs).replace("{{", "{").replace("}}", "}")
    epilogue = EPILOGUE.replace("@@CANONICAL_FNS@@", fns)
    v, n = LEDGER_BASELINE
    header = header.replace("@@LEDGER_V@@", v).replace("@@LEDGER_N@@", n)
    prologue = PROLOGUE.replace("@@LEDGER_BASELINE@@", f"{v}|{n}")
    return header + prologue + "\n".join(migration_body(s) for s in SOURCES) + epilogue


if __name__ == "__main__":
    out = build()
    if "--check" in sys.argv:
        ok = OUT.exists() and OUT.read_text(encoding="utf-8") == out
        print(OUT.name + " " + ("EM DIA" if ok else "DESATUALIZADO"))
        sys.exit(0 if ok else 1)
    OUT.write_text(out, encoding="utf-8")
    print(f"gerado {OUT.name} ({len(out)} bytes)")
