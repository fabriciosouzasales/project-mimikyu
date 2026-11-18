/*
================================================================
Projeto.....: Project Mimikyu
Arquivo.....: G2_A_E1A_PROTECTED_rollback.sql — ensaio G2 (P1-G: barreira + E1-A protegida)
Status......: GERADO por e1e2/build_g2_chain.py — NÃO EDITAR À MÃO. NÃO EXECUTADO.
              EXECUÇÃO BLOQUEADA até: S0 ampliada (S0_G2_readonly.sql) executada e
              aprovada; revisão independente; autorização expressa e específica do
              proprietário (hash, executor, canal, janela). Substitui o P1 original APENAS para execução futura; o P1 original fica como evidência histórica.
              Mecanismo da barreira (G1) não homologado; G2 não iniciado.
Canal.......: psql -X -v ON_ERROR_STOP=1 -f G2_A_E1A_PROTECTED_rollback.sql  — conexão DIRETA única, não
              interativo, sem -1. Mesma moldura T0–T11 do P1 da E1-A
              (VALIDATION-STRATEGY-E1A.md §2): sessão somente leitura por padrão (T0),
              trava de COMMIT (T4), LOCK NOWAIT antes do DDL (T6), sentinela que SEMPRE
              aborta (T9) com SQLSTATE E2AOK/E2ANO.
Sequência...: 5389 → 5366 → 5367 → 5368 → 5369 → 5370
Harnesses...: 5861[CLOSED], 5888[OPEN]
Total.......: 105 verificações (soma dos GATEs esperados)
Limites.....: statement_timeout 20s; lock_timeout 2s (cada migration redefine 5s);
              idle_in_transaction 15s; transaction_timeout 60s só se PG >= 17;
              aprovado só com duração <= 20000 ms (limite proposto, não medição).
Provas......: só o banco (SET LOCAL ROLE); JWT real, PostgREST, Storage pela API,
              concorrência e medições ficam para G3/G4.
Fontes......: 5389@b8c60c6c425f2110, 5366@bc1ff1109fee3a6c, 5367@92c8b4d71e96245c, 5368@27dff7273fbbaed0, 5369@0a9c4844f35128cb, 5370@c0df38050a8bff24, H5861@d086fa66375253d5, H5888@50aa49beb5c06d0c
================================================================
*/

\set ON_ERROR_STOP on
\set VERBOSITY verbose

-- @@T0 padrão da sessão somente leitura
SET SESSION default_transaction_read_only = on;

-- @@T1 bloco explícito
BEGIN;

-- @@T2 esta transação escreve
SET TRANSACTION READ WRITE;

-- @@T3 limites
SET LOCAL lock_timeout = '2s';
SET LOCAL statement_timeout = '20s';
SET LOCAL idle_in_transaction_session_timeout = '15s';
do $t3$
begin
  if pg_catalog.current_setting('server_version_num')::int < 140000 then
    raise exception 'G2 T3: PostgreSQL < 14 — ensaio RECUSADO';
  end if;
  perform pg_catalog.set_config('client_connection_check_interval', '1s', true);
  if pg_catalog.current_setting('server_version_num')::int >= 170000 then
    perform pg_catalog.set_config('transaction_timeout', '60s', true);
  end if;
end;
$t3$;

-- @@T4 trava de COMMIT
create temp table g2_trap_parent (id integer primary key) on commit drop;
create temp table g2_trap_child (
  parent_id integer not null
    constraint g2_trap_fk references g2_trap_parent (id) deferrable initially deferred
) on commit drop;
insert into g2_trap_child (parent_id) values (1);

-- @@T5 evidência
create temp table g2_evidence (harness text, seq integer, check_id text, status text, detail text) on commit drop;
create temp table g2_meta (k text primary key, v jsonb not null) on commit drop;

-- @@T6 precheck
do $t6$
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
  where l.relation in (to_regclass('public.collection_membership'), to_regclass('storage.objects'))
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
$t6$;

-- @@T6 lock imediato ou recusa (NOWAIT): public.collection_membership
LOCK TABLE public.collection_membership IN ACCESS EXCLUSIVE MODE NOWAIT;
insert into pg_temp.g2_meta (k, v) values ('t_lock_membership', to_jsonb(pg_catalog.clock_timestamp()));

-- @@T7 5389 (G1) sha256=b8c60c6c425f21109e8564e69af48bee69447fee650a8aae9a1ba28c431999b5
set local lock_timeout = '5s';

do $pre$
begin
  if to_regclass('public.v1_13_barrier_state') is not null
     or to_regclass('public.v1_13_barrier_identity') is not null
     or to_regprocedure('public.v1_13_capability_open()') is not null
     or to_regprocedure('public.v1_13_assert_capability()') is not null then
    raise exception 'PRECHECK 5389: JÁ APLICADA ou ESTADO DIVERGENTE — barreira já existe';
  end if;
  if to_regprocedure('public.collection_member_role(uuid)') is not null
     or to_regprocedure('public.set_collection_member_role(uuid, uuid, text)') is not null then
    raise exception 'PRECHECK 5389: ORDEM — capacidades da V1-13 já existem; a barreira deve vir antes de 5366';
  end if;
end;
$pre$;

create table public.v1_13_barrier_state (
  id          smallint    primary key,
  mode        text        not null,
  changed_at  timestamptz not null default now(),
  change_note text        null,
  constraint chk_v113_barrier_singleton check (id = 1),
  constraint chk_v113_barrier_mode check (mode in ('CLOSED', 'TEST', 'OPEN')),
  constraint chk_v113_barrier_note check (change_note is null or char_length(change_note) <= 200)
);

create table public.v1_13_barrier_identity (
  user_id  uuid        primary key
           references auth.users (id) on update restrict on delete cascade,
  added_at timestamptz not null default now(),
  note     text        null,
  constraint chk_v113_identity_note check (note is null or char_length(note) <= 200)
);

alter table public.v1_13_barrier_state enable row level security;
alter table public.v1_13_barrier_identity enable row level security;
revoke all on table public.v1_13_barrier_state from public, anon, authenticated, service_role;
revoke all on table public.v1_13_barrier_identity from public, anon, authenticated, service_role;

insert into public.v1_13_barrier_state (id, mode, change_note)
values (1, 'CLOSED', '5389: criada fechada');

comment on table public.v1_13_barrier_state is
  'V1-13 D-E1 (5389): modo da barreira das capacidades novas — CLOSED (ninguém), TEST (só identidades do registro), OPEN (todos os autenticados; só depois de G5 e da etapa 7). Sem acesso de clientes; mudança só por SQL autorizado do proprietário.';
comment on table public.v1_13_barrier_identity is
  'V1-13 D-E1 (5389): identidades de teste autorizadas no modo TEST. Sem acesso de clientes. Exclusão da conta de teste remove a linha (cascata).';

create function public.v1_13_capability_open()
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select (select auth.uid()) is not null
     and coalesce((
           select case s.mode
                    when 'OPEN' then true
                    when 'TEST' then exists (select 1 from public.v1_13_barrier_identity i
                                             where i.user_id = (select auth.uid()))
                    else false
                  end
           from public.v1_13_barrier_state s
           where s.id = 1), false)
$fn$;

create function public.v1_13_assert_capability()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $fn$
begin
  if not public.v1_13_capability_open() then
    raise exception 'CAPABILITY_NOT_ENABLED' using errcode = '42501', hint = 'V1_13_BARRIER';
  end if;
end;
$fn$;

comment on function public.v1_13_capability_open() is
  'V1-13 D-E1 (5389): porta das capacidades novas. Interna (sem EXECUTE para a API). Negação por padrão: sem usuário, sem linha de estado ou modo CLOSED → falso.';
comment on function public.v1_13_assert_capability() is
  'V1-13 D-E1 (5389): levanta 42501 CAPABILITY_NOT_ENABLED (hint V1_13_BARRIER) quando a porta está fechada para o chamador. Interna.';

revoke all on function public.v1_13_capability_open() from public, anon, authenticated, service_role;
revoke all on function public.v1_13_assert_capability() from public, anon, authenticated, service_role;

do $post$
declare
  f oid;
  r text;
begin
  foreach r in array array['public.v1_13_barrier_state', 'public.v1_13_barrier_identity'] loop
    if not (select c.relrowsecurity from pg_catalog.pg_class c where c.oid = to_regclass(r))
       or exists (select 1 from pg_catalog.pg_policy p where p.polrelid = to_regclass(r))
       or pg_catalog.has_table_privilege('anon', to_regclass(r), 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
       or pg_catalog.has_table_privilege('authenticated', to_regclass(r), 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
       or pg_catalog.has_table_privilege('service_role', to_regclass(r), 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
       or exists (select 1 from pg_catalog.pg_class c cross join lateral pg_catalog.aclexplode(c.relacl) a
                  where c.oid = to_regclass(r) and a.grantee = 0) then
      raise exception 'POSTCHECK 5389: % com RLS desligada, política ou privilégio de cliente', r;
    end if;
  end loop;
  foreach f in array array[to_regprocedure('public.v1_13_capability_open()'),
                           to_regprocedure('public.v1_13_assert_capability()')] loop
    if f is null
       or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
       or (select p.proconfig from pg_catalog.pg_proc p where p.oid = f) is distinct from array['search_path=""']
       or (select p.provolatile from pg_catalog.pg_proc p where p.oid = f) is distinct from 's'
       or pg_catalog.has_function_privilege('anon', f, 'EXECUTE')
       or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE')
       or pg_catalog.has_function_privilege('service_role', f, 'EXECUTE')
       or exists (select 1 from pg_catalog.pg_proc p cross join lateral pg_catalog.aclexplode(p.proacl) a
                  where p.oid = f and a.grantee = 0) then
      raise exception 'POSTCHECK 5389: função da porta fora do estado esperado (%)', f;
    end if;
  end loop;
  if (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'CLOSED'
     or (select count(*) from public.v1_13_barrier_state) <> 1
     or exists (select 1 from public.v1_13_barrier_identity) then
    raise exception 'POSTCHECK 5389: estado inicial diferente de CLOSED com registro vazio';
  end if;
end;
$post$;

-- @@T7 5366 (auditada) sha256=bc1ff1109fee3a6c72b58f6537c57c713b1727b51f2662da4cad9600bc963aaa
set local lock_timeout = '5s';

do $pre$
declare
  v_def text;
begin
  if to_regclass('public.collection_membership') is null then
    raise exception 'PRECHECK 5366: collection_membership ausente (5300 não aplicada)';
  end if;
  select pg_catalog.pg_get_constraintdef(k.oid) into v_def
  from pg_catalog.pg_constraint k
  where k.conrelid = 'public.collection_membership'::regclass
    and k.conname = 'chk_collection_membership_role';
  if v_def is null then
    raise exception 'PRECHECK 5366: ESTADO DIVERGENTE — chk_collection_membership_role ausente';
  end if;
  if v_def = 'CHECK ((role = ANY (ARRAY[''VIEWER''::text, ''EDITOR''::text])))' then
    raise exception 'PRECHECK 5366: JÁ APLICADA — não reaplicar';
  end if;
  if v_def not in ('CHECK ((role = ''VIEWER''::text))',
                   'CHECK ((role = ANY (ARRAY[''VIEWER''::text])))') then
    raise exception 'PRECHECK 5366: ESTADO DIVERGENTE — CHECK vigente inesperado: %', v_def;
  end if;
  if exists (select 1 from public.collection_membership m where m.role is distinct from 'VIEWER') then
    raise exception 'PRECHECK 5366: ESTADO DIVERGENTE — há papel diferente de VIEWER';
  end if;
end;
$pre$;

alter table public.collection_membership
  drop constraint chk_collection_membership_role;

alter table public.collection_membership
  add constraint chk_collection_membership_role check (role in ('VIEWER', 'EDITOR'));

comment on table public.collection_membership is
  'Collection Membership (C-142/C-143/C-153, V1-12; papel EDITOR desde a V1-13, C-234/C-240): participação de usuário não titular. Titular = collection.owner_user_id (C-141), nunca uma linha aqui. Acesso só por funções SECURITY DEFINER (5303–5313, 5367–5370).';

do $post$
begin
  if (select pg_catalog.pg_get_constraintdef(k.oid) from pg_catalog.pg_constraint k
       where k.conrelid = 'public.collection_membership'::regclass
         and k.conname = 'chk_collection_membership_role')
     is distinct from 'CHECK ((role = ANY (ARRAY[''VIEWER''::text, ''EDITOR''::text])))' then
    raise exception 'POSTCHECK 5366: CHECK de papel não ficou no estado esperado';
  end if;
  if (select column_default from information_schema.columns
       where table_schema = 'public' and table_name = 'collection_membership' and column_name = 'role')
     is distinct from '''VIEWER''::text' then
    raise exception 'POSTCHECK 5366: default do papel mudou';
  end if;
  if (select c.relrowsecurity from pg_catalog.pg_class c where c.oid = 'public.collection_membership'::regclass) is not true
     or exists (select 1 from pg_catalog.pg_policy p where p.polrelid = 'public.collection_membership'::regclass)
     or pg_catalog.has_table_privilege('authenticated', 'public.collection_membership', 'SELECT,INSERT,UPDATE,DELETE')
     or pg_catalog.has_table_privilege('anon', 'public.collection_membership', 'SELECT,INSERT,UPDATE,DELETE') then
    raise exception 'POSTCHECK 5366: RLS/privilégios da tabela mudaram';
  end if;
end;
$post$;

-- @@T7 5367 (auditada) sha256=92c8b4d71e96245c7228f9fa262d795431188c39873537a453961a088b77b5fb
set local lock_timeout = '5s';

do $pre$
begin
  if to_regclass('public.collection_membership') is null then
    raise exception 'PRECHECK 5367: collection_membership ausente';
  end if;
  if to_regprocedure('public.collection_member_role(uuid)') is not null
     and (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
           where p.oid = to_regprocedure('public.collection_member_role(uuid)')) = '1e90ce8a9f4d88c067e9125bf602eff8' then
    raise exception 'PRECHECK 5367: JÁ APLICADA — não reaplicar';
  end if;
  if exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname = 'collection_member_role') then
    raise exception 'PRECHECK 5367: ESTADO DIVERGENTE — já existe collection_member_role com outro corpo/assinatura';
  end if;
end;
$pre$;

CREATE FUNCTION public.collection_member_role(p_collection_id UUID)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT CASE
        WHEN (select auth.uid()) IS NULL THEN NULL
        WHEN c.owner_user_id = (select auth.uid()) THEN 'OWNER'
        ELSE (
            SELECT m.role
            FROM public.collection_membership m
            WHERE m.collection_id = c.id
              AND m.user_id = (select auth.uid())
              AND m.status = 'ACTIVE'
        )
    END
    FROM public.collection c
    WHERE c.id = p_collection_id;
$$;

COMMENT ON FUNCTION public.collection_member_role(UUID) IS
    'V1-13 E1-A (5367): papel real do usuário da sessão na coleção — OWNER | EDITOR | VIEWER | NULL. Interna (sem EXECUTE para API). Não substitui collection_share_role (5302), que segue sendo o nível de leitura.';

REVOKE ALL ON FUNCTION public.collection_member_role(UUID) FROM PUBLIC, anon, authenticated;

do $post$
declare
  v_oid oid := to_regprocedure('public.collection_member_role(uuid)');
  v_ref oid := to_regprocedure('public.collection_share_role(uuid)');
begin
  -- Paridade de ACL com a 5302 (mesma classe: interna). Inclui papéis fora de
  -- anon/authenticated (ex.: service_role por privilégio padrão). ACL nula = erro.
  if v_ref is null or (select p.proacl from pg_catalog.pg_proc p where p.oid = v_oid) is null or (select p.proacl from pg_catalog.pg_proc p where p.oid = v_ref) is null
     or (select coalesce(string_agg(a::text, ',' order by a::text), '<NULL>') from pg_catalog.pg_proc p cross join lateral unnest(p.proacl) a where p.oid = v_oid)
        is distinct from (select coalesce(string_agg(a::text, ',' order by a::text), '<NULL>') from pg_catalog.pg_proc p cross join lateral unnest(p.proacl) a where p.oid = v_ref) then
    raise exception 'POSTCHECK 5367: ACL difere da collection_share_role (5302)';
  end if;
  if v_oid is null
     or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = v_oid) is not true
     or (select p.proconfig from pg_catalog.pg_proc p where p.oid = v_oid) is distinct from array['search_path=""']
     or (select p.provolatile from pg_catalog.pg_proc p where p.oid = v_oid) is distinct from 's'
     or pg_catalog.has_function_privilege('authenticated', v_oid, 'EXECUTE') is not false
     or pg_catalog.has_function_privilege('anon', v_oid, 'EXECUTE') is not false
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_oid) is distinct from '1e90ce8a9f4d88c067e9125bf602eff8' then
    raise exception 'POSTCHECK 5367: collection_member_role fora do estado esperado';
  end if;
end;
$post$;

-- @@T7 5368 (auditada) sha256=27dff7273fbbaed0864096dfd9a3fc46189220bfd6f2e87ff62032fba32655ea
set local lock_timeout = '5s';

do $pre$
declare
  f9  oid := to_regprocedure('public.get_my_collection_invites()');
  f11 oid := to_regprocedure('public.get_collections_shared_with_me()');
  f12 oid := to_regprocedure('public.get_shared_collection(uuid)');
  m9 text; m11 text; m12 text;
begin
  if to_regprocedure('public.collection_member_role(uuid)') is null then
    raise exception 'PRECHECK 5368: 5367 não aplicada';
  end if;
  if f9 is null or f11 is null or f12 is null then
    raise exception 'PRECHECK 5368: ESTADO DIVERGENTE — leitura V1-12 ausente';
  end if;
  select pg_catalog.md5(p.prosrc) into m9  from pg_catalog.pg_proc p where p.oid = f9;
  select pg_catalog.md5(p.prosrc) into m11 from pg_catalog.pg_proc p where p.oid = f11;
  select pg_catalog.md5(p.prosrc) into m12 from pg_catalog.pg_proc p where p.oid = f12;
  if m9 = '5f38c1ec0471b07344aec5551292a392' and m11 = '5599f4f8ac5db1cfe893345d4884b244' and m12 = '69d69fd11dddcaedabe7368a3e038368' then
    raise exception 'PRECHECK 5368: JÁ APLICADA — não reaplicar';
  end if;
  if m9  is distinct from '74ea7dc1af9032e337b6c0e04ae7c478'
     or m11 is distinct from '67b4395f013a2591fcb1e1585ba53a16'
     or m12 is distinct from '254d56f3f9c8097ee3d36e580c851c29' then
    raise exception 'PRECHECK 5368: ESTADO DIVERGENTE — corpos vigentes diferem da V1-12 canônica (5309=% 5311=% 5312=%)', m9, m11, m12;
  end if;
  if (select p.proacl from pg_catalog.pg_proc p where p.oid = f9) is null or (select p.proacl from pg_catalog.pg_proc p where p.oid = f11) is null or (select p.proacl from pg_catalog.pg_proc p where p.oid = f12) is null then
    raise exception 'PRECHECK 5368: ESTADO DIVERGENTE — ACL nula (privilégio padrão, inclui PUBLIC)';
  end if;
  -- ACL vigente guardada na transação para o postcheck (preservação total de EXECUTE).
  perform pg_catalog.set_config('mmkyu.e1a_5368_acl',
    (select coalesce(string_agg(a::text, ',' order by a::text), '<NULL>') from pg_catalog.pg_proc p cross join lateral unnest(p.proacl) a where p.oid = f9) || '|' || (select coalesce(string_agg(a::text, ',' order by a::text), '<NULL>') from pg_catalog.pg_proc p cross join lateral unnest(p.proacl) a where p.oid = f11) || '|' || (select coalesce(string_agg(a::text, ',' order by a::text), '<NULL>') from pg_catalog.pg_proc p cross join lateral unnest(p.proacl) a where p.oid = f12), true);
end;
$pre$;

-- 5309 + role ------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_my_collection_invites()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT coalesce(jsonb_agg(row_to_json(x)::jsonb ORDER BY x.invited_at DESC, x.membership_id), '[]'::jsonb)
    FROM (
        SELECT m.id                 AS membership_id,
               m.role               AS role,
               c.id                 AS collection_id,
               c.name               AS collection_name,
               c.mode               AS mode,
               c.completion_policy  AS completion_policy,
               cs.name::text        AS card_set_name,
               owner.display_name   AS owner_display_name,
               owner.username       AS owner_username,
               m.invited_at         AS invited_at
        FROM public.collection_membership m
        JOIN public.collection c         ON c.id = m.collection_id
        JOIN public.user_profile owner   ON owner.id = c.owner_user_id
        LEFT JOIN public.collection_reference cr            ON cr.collection_id = c.id
        LEFT JOIN public.collection_card_set_reference ccsr ON ccsr.collection_reference_id = cr.id
        LEFT JOIN public.card_set cs                        ON cs.id = ccsr.card_set_id
        WHERE (select auth.uid()) IS NOT NULL
          AND m.user_id = (select auth.uid())
          AND m.status = 'PENDING'
        ORDER BY m.invited_at DESC, m.id
        LIMIT 50
    ) x;
$$;

REVOKE ALL ON FUNCTION public.get_my_collection_invites() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_collection_invites() TO authenticated;

-- 5311 + role ------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_collections_shared_with_me()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT coalesce(jsonb_agg(row_to_json(x)::jsonb ORDER BY x.accepted_at DESC, x.collection_id), '[]'::jsonb)
    FROM (
        SELECT c.id                AS collection_id,
               c.name              AS name,
               c.mode              AS mode,
               c.completion_policy AS completion_policy,
               c.lifecycle_status  AS lifecycle_status,
               c.cover_finish      AS cover_finish,
               cs.code::text       AS card_set_code,
               cs.name::text       AS card_set_name,
               owner.display_name  AS owner_display_name,
               m.responded_at      AS accepted_at,
               m.role              AS role,
               (SELECT count(*) FROM public.collection_allocation ca WHERE ca.collection_id = c.id) AS copies_count,
               s.total_positions, s.satisfied_positions, s.progress_percentage, s.is_complete
        FROM public.collection_membership m
        JOIN public.collection c       ON c.id = m.collection_id
        JOIN public.user_profile owner ON owner.id = c.owner_user_id
        LEFT JOIN public.collection_reference cr            ON cr.collection_id = c.id
        LEFT JOIN public.collection_card_set_reference ccsr ON ccsr.collection_reference_id = cr.id
        LEFT JOIN public.card_set cs                        ON cs.id = ccsr.card_set_id
        LEFT JOIN LATERAL public.collection_completion_summary_shared(c.id) s ON true
        WHERE (select auth.uid()) IS NOT NULL
          AND m.user_id = (select auth.uid())
          AND m.status = 'ACTIVE'
        ORDER BY m.responded_at DESC, c.id
        LIMIT 100
    ) x;
$$;

REVOKE ALL ON FUNCTION public.get_collections_shared_with_me() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_collections_shared_with_me() TO authenticated;

-- 5312 + role ------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_shared_collection(p_collection_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_role   TEXT;
    v_result JSONB;
BEGIN
    v_role := public.collection_share_role(p_collection_id);
    IF v_role IS NULL OR v_role NOT IN ('OWNER', 'VIEWER') THEN
        RETURN NULL;
    END IF;

    SELECT jsonb_build_object(
        'collection_id', c.id,
        'name', c.name,
        'description', c.description,
        'mode', c.mode,
        'completion_policy', c.completion_policy,
        'lifecycle_status', c.lifecycle_status,
        'visibility', c.visibility,
        'cover_finish', c.cover_finish,
        'card_set_code', cs.code,
        'card_set_name', cs.name,
        'card_set_logo_path', cs.logo_storage_path,
        'owner_display_name', owner.display_name,
        'access', v_role,
        'role', public.collection_member_role(c.id),
        'membership_id', CASE WHEN v_role = 'VIEWER' THEN (
            SELECT m.id FROM public.collection_membership m
            WHERE m.collection_id = c.id AND m.user_id = (select auth.uid()) AND m.status = 'ACTIVE'
        ) END,
        'copies_count', (SELECT count(*) FROM public.collection_allocation ca WHERE ca.collection_id = c.id),
        'total_positions', s.total_positions,
        'satisfied_positions', s.satisfied_positions,
        'progress_percentage', s.progress_percentage,
        'is_complete', s.is_complete
    )
    INTO v_result
    FROM public.collection c
    JOIN public.user_profile owner ON owner.id = c.owner_user_id
    LEFT JOIN public.collection_reference cr            ON cr.collection_id = c.id
    LEFT JOIN public.collection_card_set_reference ccsr ON ccsr.collection_reference_id = cr.id
    LEFT JOIN public.card_set cs                        ON cs.id = ccsr.card_set_id
    LEFT JOIN LATERAL public.collection_completion_summary_shared(c.id) s ON true
    WHERE c.id = p_collection_id;

    RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.get_shared_collection(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_shared_collection(uuid) TO authenticated;

do $post$
declare
  f oid;
  f9  oid := to_regprocedure('public.get_my_collection_invites()');
  f11 oid := to_regprocedure('public.get_collections_shared_with_me()');
  f12 oid := to_regprocedure('public.get_shared_collection(uuid)');
begin
  if (select coalesce(string_agg(a::text, ',' order by a::text), '<NULL>') from pg_catalog.pg_proc p cross join lateral unnest(p.proacl) a where p.oid = f9) || '|' || (select coalesce(string_agg(a::text, ',' order by a::text), '<NULL>') from pg_catalog.pg_proc p cross join lateral unnest(p.proacl) a where p.oid = f11) || '|' || (select coalesce(string_agg(a::text, ',' order by a::text), '<NULL>') from pg_catalog.pg_proc p cross join lateral unnest(p.proacl) a where p.oid = f12)
     is distinct from pg_catalog.current_setting('mmkyu.e1a_5368_acl', true) then
    raise exception 'POSTCHECK 5368: ACL das leituras mudou';
  end if;
  foreach f in array array[to_regprocedure('public.get_my_collection_invites()'),
                           to_regprocedure('public.get_collections_shared_with_me()'),
                           to_regprocedure('public.get_shared_collection(uuid)')] loop
    if f is null
       or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
       or (select p.proconfig from pg_catalog.pg_proc p where p.oid = f) is distinct from array['search_path=""']
       or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not true
       or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false then
      raise exception 'POSTCHECK 5368: leitura fora do estado esperado (%)', f::regprocedure;
    end if;
  end loop;
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.get_my_collection_invites()')) is distinct from '5f38c1ec0471b07344aec5551292a392'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.get_collections_shared_with_me()')) is distinct from '5599f4f8ac5db1cfe893345d4884b244'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.get_shared_collection(uuid)')) is distinct from '69d69fd11dddcaedabe7368a3e038368' then
    raise exception 'POSTCHECK 5368: corpo gravado difere do arquivo (fim de linha/canal?)';
  end if;
end;
$post$;

-- @@T7 5369 (protegida) sha256=0a9c4844f35128cb1c4e377cf4074b7d241fcf43ff4845fc54a2c61937794911
set local lock_timeout = '5s';

do $pre$
declare
  v_old oid := to_regprocedure('public.invite_collection_member(uuid, text)');
  v_new oid := to_regprocedure('public.invite_collection_member(uuid, text, text)');
begin
  if to_regprocedure('public.v1_13_assert_capability()') is null or to_regprocedure('public.v1_13_capability_open()') is null then raise exception 'PRECHECK G1: barreira 5389 ausente'; end if;  -- G1 (D-E1)
  if to_regclass('public.collection_membership') is null
     or (select pg_catalog.pg_get_constraintdef(k.oid) from pg_catalog.pg_constraint k
          where k.conrelid = 'public.collection_membership'::regclass
            and k.conname = 'chk_collection_membership_role')
        is distinct from 'CHECK ((role = ANY (ARRAY[''VIEWER''::text, ''EDITOR''::text])))' then
    raise exception 'PRECHECK 5369: 5366 não aplicada';
  end if;
  if v_old is null and v_new is not null
     and (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_new) = '5a5ea20616ded5b1a8e8bfe0487743ff' then
    raise exception 'PRECHECK 5369: JÁ APLICADA — não reaplicar';
  end if;
  if v_old is null or v_new is not null then
    raise exception 'PRECHECK 5369: ESTADO DIVERGENTE — assinaturas vigentes inesperadas (antiga=% nova=%)', v_old, v_new;
  end if;
  if (select count(*) from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'invite_collection_member') <> 1 then
    raise exception 'PRECHECK 5369: ESTADO DIVERGENTE — mais de uma sobrecarga de invite_collection_member';
  end if;
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_old)
     is distinct from 'ed7418f20c1004b23c58c68c84a6ae73' then
    raise exception 'PRECHECK 5369: ESTADO DIVERGENTE — corpo vigente difere da 5303 canônica';
  end if;
  if exists (select 1 from pg_catalog.pg_depend d
             where d.refclassid = 'pg_catalog.pg_proc'::regclass and d.refobjid = v_old and d.deptype = 'n') then
    raise exception 'PRECHECK 5369: há objetos dependentes da assinatura antiga';
  end if;
  if (select p.proacl from pg_catalog.pg_proc p where p.oid = v_old) is null then
    raise exception 'PRECHECK 5369: ESTADO DIVERGENTE — ACL nula na assinatura antiga';
  end if;
  -- ACL da assinatura antiga guardada para o postcheck: o DROP a apaga, e a nova
  -- função recebe privilégios padrão do esquema (podem incluir service_role/anon).
  perform pg_catalog.set_config('mmkyu.e1a_5369_acl', (select coalesce(string_agg(a::text, ',' order by a::text), '<NULL>') from pg_catalog.pg_proc p cross join lateral unnest(p.proacl) a where p.oid = v_old), true);
end;
$pre$;

DROP FUNCTION public.invite_collection_member(UUID, TEXT);

CREATE FUNCTION public.invite_collection_member(
    p_collection_id UUID,
    p_username TEXT,
    p_role TEXT DEFAULT 'VIEWER'
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_user        UUID := auth.uid();
    v_lifecycle   TEXT;
    v_username    TEXT := lower(btrim(coalesce(p_username, '')));
    v_role        TEXT := upper(btrim(coalesce(p_role, 'VIEWER')));
    v_target      UUID;
    v_display     TEXT;
    v_existing    public.collection_membership%ROWTYPE;
    v_count       INTEGER;
    v_id          UUID;
BEGIN
    IF v_user IS NULL THEN
        RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '28000';
    END IF;

    IF left(v_username, 1) = '@' THEN
        v_username := substr(v_username, 2);
    END IF;
    IF v_username !~ '^[a-z0-9_]{3,20}$' THEN
        RAISE EXCEPTION 'INVALID_USERNAME' USING ERRCODE = '22023';
    END IF;
    IF v_role NOT IN ('VIEWER', 'EDITOR') THEN
        RAISE EXCEPTION 'INVALID_ROLE' USING ERRCODE = '22023';
    END IF;
    IF v_role = 'EDITOR' THEN PERFORM public.v1_13_assert_capability(); END IF;  -- G1 (D-E1)

    SELECT c.lifecycle_status INTO v_lifecycle
    FROM public.collection c
    WHERE c.id = p_collection_id
      AND c.owner_user_id = v_user
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'COLLECTION_NOT_FOUND' USING ERRCODE = 'P0002';
    END IF;
    IF v_lifecycle <> 'ACTIVE' THEN
        RAISE EXCEPTION 'COLLECTION_ARCHIVED' USING ERRCODE = '55000';
    END IF;

    SELECT up.id, up.display_name INTO v_target, v_display
    FROM public.user_profile up
    WHERE up.username = v_username;

    IF v_target IS NULL THEN
        RAISE EXCEPTION 'USER_NOT_FOUND' USING ERRCODE = 'P0002';
    END IF;
    IF v_target = v_user THEN
        RAISE EXCEPTION 'CANNOT_INVITE_SELF' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_existing
    FROM public.collection_membership m
    WHERE m.collection_id = p_collection_id
      AND m.user_id = v_target
    FOR UPDATE;

    IF FOUND THEN
        IF v_existing.status = 'ACTIVE' THEN
            RAISE EXCEPTION 'ALREADY_MEMBER' USING ERRCODE = '23505';
        ELSIF v_existing.status = 'PENDING' THEN
            IF v_existing.role IS DISTINCT FROM v_role THEN
                RAISE EXCEPTION 'INVITE_PENDING_ROLE_IMMUTABLE' USING ERRCODE = '55000',
                    HINT = 'Cancele o convite pendente e convide novamente com o outro papel.';
            END IF;
            RETURN jsonb_build_object(
                'outcome', 'ALREADY_PENDING',
                'membership_id', v_existing.id,
                'username', v_username,
                'display_name', v_display,
                'status', 'PENDING',
                'role', v_existing.role
            );
        END IF;
    END IF;

    SELECT count(*) INTO v_count
    FROM public.collection_membership m
    WHERE m.collection_id = p_collection_id
      AND m.status IN ('PENDING', 'ACTIVE');
    IF v_count >= 50 THEN
        RAISE EXCEPTION 'MEMBER_LIMIT' USING ERRCODE = '54000';
    END IF;

    IF v_existing.id IS NOT NULL THEN
        IF v_existing.role IS NOT DISTINCT FROM v_role THEN
            -- DECLINED → PENDING, mesmo papel: mesma linha (V1-12).
            UPDATE public.collection_membership m
            SET status = 'PENDING',
                responded_at = NULL,
                invited_by = v_user,
                invited_at = now()
            WHERE m.id = v_existing.id
              AND m.status = 'DECLINED'
            RETURNING m.id INTO v_id;
        ELSE
            -- DECLINED → convite NOVO com outro papel: id novo, o antigo deixa de existir.
            DELETE FROM public.collection_membership m
            WHERE m.id = v_existing.id
              AND m.status = 'DECLINED';
            INSERT INTO public.collection_membership (collection_id, user_id, role, status, invited_by)
            VALUES (p_collection_id, v_target, v_role, 'PENDING', v_user)
            RETURNING id INTO v_id;
        END IF;
        IF v_id IS NULL THEN
            RAISE EXCEPTION 'INVITE_STATE_CHANGED' USING ERRCODE = '40001';
        END IF;
        RETURN jsonb_build_object(
            'outcome', 'REINVITED',
            'membership_id', v_id,
            'username', v_username,
            'display_name', v_display,
            'status', 'PENDING',
            'role', v_role
        );
    END IF;

    INSERT INTO public.collection_membership (collection_id, user_id, role, status, invited_by)
    VALUES (p_collection_id, v_target, v_role, 'PENDING', v_user)
    ON CONFLICT (collection_id, user_id) DO NOTHING
    RETURNING id INTO v_id;

    IF v_id IS NULL THEN
        -- Corrida residual (a trava da coleção já serializa convites): só
        -- devolve ALREADY_PENDING se o que ficou gravado for exatamente o pedido.
        SELECT * INTO v_existing FROM public.collection_membership m
        WHERE m.collection_id = p_collection_id AND m.user_id = v_target;
        IF v_existing.status = 'PENDING' AND v_existing.role = v_role THEN
            RETURN jsonb_build_object('outcome', 'ALREADY_PENDING', 'membership_id', v_existing.id,
                'username', v_username, 'display_name', v_display, 'status', 'PENDING', 'role', v_role);
        END IF;
        RAISE EXCEPTION 'INVITE_STATE_CHANGED' USING ERRCODE = '40001';
    END IF;

    RETURN jsonb_build_object(
        'outcome', 'INVITED',
        'membership_id', v_id,
        'username', v_username,
        'display_name', v_display,
        'status', 'PENDING',
        'role', v_role
    );
END;
$$;

COMMENT ON FUNCTION public.invite_collection_member(UUID, TEXT, TEXT) IS
    'V1-12 (5303) + V1-13 E1-A (5369): titular convida pelo username exato com papel VIEWER (padrão) ou EDITOR. Papel de convite PENDING é imutável (INVITE_PENDING_ROLE_IMMUTABLE); recusado com outro papel vira convite novo (id novo). Membro ativo: troca só pela set_collection_member_role (5370).';

REVOKE ALL ON FUNCTION public.invite_collection_member(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.invite_collection_member(UUID, TEXT, TEXT) TO authenticated;

do $post$
declare
  v_new oid := to_regprocedure('public.invite_collection_member(uuid, text, text)');
begin
  if to_regprocedure('public.invite_collection_member(uuid, text)') is not null then
    raise exception 'POSTCHECK 5369: assinatura antiga ainda existe';
  end if;
  if (select count(*) from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'invite_collection_member') <> 1 then
    raise exception 'POSTCHECK 5369: sobrecarga inesperada';
  end if;
  if (select coalesce(string_agg(a::text, ',' order by a::text), '<NULL>') from pg_catalog.pg_proc p cross join lateral unnest(p.proacl) a where p.oid = v_new)
     is distinct from pg_catalog.current_setting('mmkyu.e1a_5369_acl', true) then
    raise exception 'POSTCHECK 5369: ACL da nova assinatura difere da antiga (%)', (select coalesce(string_agg(a::text, ',' order by a::text), '<NULL>') from pg_catalog.pg_proc p cross join lateral unnest(p.proacl) a where p.oid = v_new);
  end if;
  if v_new is null
     or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = v_new) is not true
     or (select p.proconfig from pg_catalog.pg_proc p where p.oid = v_new) is distinct from array['search_path=""']
     or (select p.pronargdefaults from pg_catalog.pg_proc p where p.oid = v_new) is distinct from 1::int2
     or pg_catalog.has_function_privilege('authenticated', v_new, 'EXECUTE') is not true
     or pg_catalog.has_function_privilege('anon', v_new, 'EXECUTE') is not false
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_new) is distinct from '5a5ea20616ded5b1a8e8bfe0487743ff' then
    raise exception 'POSTCHECK 5369: invite_collection_member fora do estado esperado';
  end if;
end;
$post$;

-- @@T7 5370 (protegida) sha256=c0df38050a8bff24b9c5aa5d1cf9e928ed7f2ed7483050e8d4b97c3cabce3219
set local lock_timeout = '5s';

do $pre$
declare
  v_oid oid := to_regprocedure('public.set_collection_member_role(uuid, uuid, text)');
begin
  if to_regprocedure('public.v1_13_assert_capability()') is null or to_regprocedure('public.v1_13_capability_open()') is null then raise exception 'PRECHECK G1: barreira 5389 ausente'; end if;  -- G1 (D-E1)
  if (select pg_catalog.pg_get_constraintdef(k.oid) from pg_catalog.pg_constraint k
       where k.conrelid = 'public.collection_membership'::regclass
         and k.conname = 'chk_collection_membership_role')
     is distinct from 'CHECK ((role = ANY (ARRAY[''VIEWER''::text, ''EDITOR''::text])))' then
    raise exception 'PRECHECK 5370: 5366 não aplicada';
  end if;
  if v_oid is not null
     and (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_oid) = '840d1e5c3cc55f253a2579eda7b7703d' then
    raise exception 'PRECHECK 5370: JÁ APLICADA — não reaplicar';
  end if;
  if exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname = 'set_collection_member_role') then
    raise exception 'PRECHECK 5370: ESTADO DIVERGENTE — já existe set_collection_member_role com outro corpo/assinatura';
  end if;
end;
$pre$;

CREATE FUNCTION public.set_collection_member_role(
    p_collection_id UUID,
    p_membership_id UUID,
    p_role TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_user   UUID := auth.uid();
    v_role   TEXT := upper(btrim(p_role));
    v_row    public.collection_membership%ROWTYPE;
BEGIN
    perform public.v1_13_assert_capability();  -- G1 (D-E1)
    IF v_user IS NULL THEN
        RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '28000';
    END IF;
    IF v_role IS NULL OR v_role NOT IN ('VIEWER', 'EDITOR') THEN
        RAISE EXCEPTION 'INVALID_ROLE' USING ERRCODE = '22023';
    END IF;

    PERFORM 1
    FROM public.collection c
    WHERE c.id = p_collection_id
      AND c.owner_user_id = v_user
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'MEMBERSHIP_NOT_FOUND' USING ERRCODE = 'P0002';
    END IF;

    SELECT * INTO v_row
    FROM public.collection_membership m
    WHERE m.id = p_membership_id
      AND m.collection_id = p_collection_id
    FOR UPDATE;
    IF NOT FOUND OR v_row.user_id = v_user THEN
        RAISE EXCEPTION 'MEMBERSHIP_NOT_FOUND' USING ERRCODE = 'P0002';
    END IF;

    IF v_row.status = 'PENDING' THEN
        RAISE EXCEPTION 'INVITE_PENDING_ROLE_IMMUTABLE' USING ERRCODE = '55000',
            HINT = 'Cancele o convite pendente e convide novamente com o outro papel.';
    END IF;
    IF v_row.status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'MEMBER_NOT_ACTIVE' USING ERRCODE = '55000';
    END IF;

    IF v_row.role = v_role THEN
        RETURN jsonb_build_object('outcome', 'UNCHANGED', 'membership_id', v_row.id,
            'role', v_role, 'previous_role', v_row.role, 'status', 'ACTIVE');
    END IF;

    UPDATE public.collection_membership m
    SET role = v_role
    WHERE m.id = v_row.id
      AND m.status = 'ACTIVE';

    RETURN jsonb_build_object('outcome', 'CHANGED', 'membership_id', v_row.id,
        'role', v_role, 'previous_role', v_row.role, 'status', 'ACTIVE');
END;
$$;

COMMENT ON FUNCTION public.set_collection_member_role(UUID, UUID, TEXT) IS
    'V1-13 E1-A (5370): o titular troca diretamente o papel de um participante ACTIVE entre VIEWER e EDITOR (C-240), com efeito imediato. Convite PENDING é imutável; não altera titularidade.';

REVOKE ALL ON FUNCTION public.set_collection_member_role(UUID, UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_collection_member_role(UUID, UUID, TEXT) TO authenticated;

do $post$
declare
  v_oid oid := to_regprocedure('public.set_collection_member_role(uuid, uuid, text)');
  v_ref oid := to_regprocedure('public.remove_collection_member(uuid, uuid)');
begin
  -- Paridade de ACL com a 5305 (gestão de participação pelo titular). ACL nula = erro.
  if v_ref is null or (select p.proacl from pg_catalog.pg_proc p where p.oid = v_oid) is null or (select p.proacl from pg_catalog.pg_proc p where p.oid = v_ref) is null
     or (select coalesce(string_agg(a::text, ',' order by a::text), '<NULL>') from pg_catalog.pg_proc p cross join lateral unnest(p.proacl) a where p.oid = v_oid)
        is distinct from (select coalesce(string_agg(a::text, ',' order by a::text), '<NULL>') from pg_catalog.pg_proc p cross join lateral unnest(p.proacl) a where p.oid = v_ref) then
    raise exception 'POSTCHECK 5370: ACL difere da remove_collection_member (5305)';
  end if;
  if v_oid is null
     or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = v_oid) is not true
     or (select p.proconfig from pg_catalog.pg_proc p where p.oid = v_oid) is distinct from array['search_path=""']
     or pg_catalog.has_function_privilege('authenticated', v_oid, 'EXECUTE') is not true
     or pg_catalog.has_function_privilege('anon', v_oid, 'EXECUTE') is not false
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_oid) is distinct from '840d1e5c3cc55f253a2579eda7b7703d' then
    raise exception 'POSTCHECK 5370: set_collection_member_role fora do estado esperado';
  end if;
end;
$post$;

-- @@T8 modo da barreira CLOSED (só nesta transação)
update public.v1_13_barrier_state set mode = 'CLOSED', change_note = 'G2 ensaio' where id = 1;

-- @@T8 harness 5861 [CLOSED] sha256=d086fa66375253d565dbe0f396cae54d166197fd2a03e64a3a097e1a1adeaf6f
create or replace function pg_temp.wh_5861_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  f_inv  oid := coalesce(to_regprocedure('public.invite_collection_member(uuid, text, text)'),
                        to_regprocedure('public.invite_collection_member(uuid, text)'));
  f_rsp  oid := to_regprocedure('public.respond_collection_invite(uuid, boolean)');
  f_rem  oid := to_regprocedure('public.remove_collection_member(uuid, uuid)');
  f_lev  oid := to_regprocedure('public.leave_shared_collection(uuid)');
  f_vis  oid := to_regprocedure('public.set_collection_visibility(uuid, text)');
  f_shr  oid := to_regprocedure('public.get_my_collection_sharing(uuid)');
  f_box  oid := to_regprocedure('public.get_my_collection_invites()');
  f_swm  oid := to_regprocedure('public.get_collections_shared_with_me()');
  f_get  oid := to_regprocedure('public.get_shared_collection(uuid)');
  f_crd  oid := to_regprocedure('public.get_shared_collection_cards(uuid, integer, integer)');
  f_rol  oid := to_regprocedure('public.collection_share_role(uuid)');
  f_sum  oid := to_regprocedure('public.collection_completion_summary_shared(uuid)');
  f_bh   oid := to_regprocedure('public.get_shared_collection_binder(uuid)');
  f_bp   oid := to_regprocedure('public.get_shared_collection_binder_pages(uuid, integer, integer)');
  f_mp   oid := to_regprocedure('public.collection_binder_masked_pages(uuid, integer, integer)');
  f_pb   oid := to_regprocedure('public.get_public_collection_binder(uuid)');
  f_pp   oid := to_regprocedure('public.get_public_collection_binder_pages(uuid, integer, integer)');
  pub_allowed text[] := array['collection_id','name','completion_policy','cover_finish','owner_display_name','card_set_code',
    'card_set_name','card_set_logo_path','has_binder','binder_name','show_brand_mark','grid_columns','grid_rows','page_count'];
  v_layout uuid; v_slots uuid[]; v_sl uuid; v_res_cx boolean := false; v_res_co boolean := false;
  o_cards integer; o_res integer; o_pages integer;
  b_card integer; b_res integer; b_bad integer; b_leak integer; b_odd integer; b_total integer;
  asg0 integer; exp0 integer; v_ok2 boolean; v_closed boolean;
  u_a uuid := gen_random_uuid();
  u_b uuid := gen_random_uuid();
  u_c uuid := gen_random_uuid();
  v_sfx text := lower(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  n_a text; n_b text;
  v_game uuid; v_pt uuid; v_rar uuid; v_cat uuid; v_std uuid;
  v_exp uuid; v_set uuid; k1 uuid; k1s uuid; k2 uuid; k2s uuid;
  v_inv_a uuid; v_inv_b uuid; v_ids uuid[];
  a1 uuid; a2 uuid; x1 uuid; b1 uuid;
  v_bin uuid; v_co uuid; v_cx uuid; m_b uuid;
  p record; j jsonb; j2 jsonb; v_err text; v_ok boolean; n integer; c record;
  allowed text[] := array['collection_id','name','description','mode','completion_policy','lifecycle_status',
    'visibility','cover_finish','card_set_code','card_set_name','card_set_logo_path','owner_display_name',
    'access','membership_id','copies_count','total_positions','satisfied_positions','progress_percentage','is_complete',
    'role'];  -- v1.4: chave da 5368 (papel do próprio participante)
  b_counts bigint[]; e_counts bigint[];
  res jsonb := '[]'::jsonb; r jsonb; cnt integer := 0; passes integer := 0;
  v_expected integer := 51;
begin
  -- 0. Estrutura ---------------------------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    to_regclass('public.collection_membership') is not null
    and f_inv is not null and f_rsp is not null and f_rem is not null and f_lev is not null and f_vis is not null
    and f_shr is not null and f_box is not null and f_swm is not null and f_get is not null and f_crd is not null
    and f_rol is not null and f_sum is not null,
    'detail','tabela e 12 funções presentes');
  res := res || jsonb_build_object('id','0.2','ok',
    (select c2.relrowsecurity from pg_class c2 where c2.oid = 'public.collection_membership'::regclass)
    and not exists (select 1 from pg_policy pl where pl.polrelid = 'public.collection_membership'::regclass)
    and not has_table_privilege('authenticated', 'public.collection_membership', 'SELECT,INSERT,UPDATE,DELETE')
    and not has_table_privilege('anon', 'public.collection_membership', 'SELECT,INSERT,UPDATE,DELETE'),
    'detail','RLS ligada, nenhuma política, nenhum privilégio de tabela para anon/authenticated');
  res := res || jsonb_build_object('id','0.3','ok',
    (select bool_and(q.prosecdef and q.proconfig @> array['search_path=""'])
       from pg_proc q where q.oid in (f_inv, f_rsp, f_rem, f_lev, f_vis, f_shr, f_box, f_swm, f_get, f_crd, f_rol, f_sum))
    and (select bool_and(has_function_privilege('authenticated', q.oid, 'EXECUTE') and not has_function_privilege('anon', q.oid, 'EXECUTE'))
           from pg_proc q where q.oid in (f_inv, f_rsp, f_rem, f_lev, f_vis, f_shr, f_box, f_swm, f_get, f_crd))
    and (select bool_and(not has_function_privilege('authenticated', q.oid, 'EXECUTE') and not has_function_privilege('anon', q.oid, 'EXECUTE'))
           from pg_proc q where q.oid in (f_rol, f_sum)),
    'detail','definer + search_path vazio; convite, painel, cabeçalho e galeria do participante só authenticated; internas sem EXECUTE');
  res := res || jsonb_build_object('id','0.4','ok',
    (select pg_get_constraintdef(k.oid) from pg_constraint k where k.conname = 'chk_collection_visibility') like '%PUBLIC%'
    and (select column_default from information_schema.columns where table_schema='public' and table_name='collection' and column_name='visibility') like '%PRIVATE%',
    'detail','visibilidade aceita PUBLIC; default continua PRIVATE');
  res := res || jsonb_build_object('id','0.5','ok',
    not exists (select 1 from pg_proc q, unnest(q.proargnames) a(name)
                where q.oid = f_crd and (a.name ~ '(storage|price|paid|value|acqui|condition|certif|physical_card|owner)')),
    'detail','galeria compartilhada sem coluna de local, valor, aquisição, condição, exemplar ou titular');
  res := res || jsonb_build_object('id','0.6','ok',
    f_bh is not null and f_bp is not null
    and (select bool_and(q.prosecdef and q.proconfig @> array['search_path=""'] and q.provolatile = 's'
                         and has_function_privilege('authenticated', q.oid, 'EXECUTE')
                         and not has_function_privilege('anon', q.oid, 'EXECUTE'))
           from pg_proc q where q.oid in (f_bh, f_bp))
    and not exists (select 1 from pg_proc q, unnest(q.proargnames, q.proargmodes) a(name, mode)
                    where q.oid = f_bp and a.mode in ('o','t')
                      and a.name ~ '(_id$|^id$|storage|physical|allocation|assignment|locked|region|collection|owner|price|value)'),
    'detail','fichário compartilhado: definer STABLE, search_path vazio, só authenticated; páginas sem ids, local, fixação, mesclagem, coleção ou valor');
  res := res || jsonb_build_object('id','0.7','ok',
    f_mp is not null and f_pb is not null and f_pp is not null
    and (select bool_and(q.prosecdef and q.proconfig @> array['search_path=""'] and q.provolatile = 's')
           from pg_proc q where q.oid in (f_mp, f_pb, f_pp))
    and not has_function_privilege('anon', f_mp, 'EXECUTE') and not has_function_privilege('authenticated', f_mp, 'EXECUTE')
    and (select bool_and(has_function_privilege('anon', q.oid, 'EXECUTE') and has_function_privilege('authenticated', q.oid, 'EXECUTE'))
           from pg_proc q where q.oid in (f_pb, f_pp))
    and not exists (select 1 from pg_proc q, unnest(q.proargnames, q.proargmodes) a(name, mode)
                    where q.oid = f_pp and a.mode in ('o','t')
                      and a.name ~ '(_id$|^id$|storage|physical|allocation|assignment|locked|region|collection|owner|price|value)'),
    'detail','vitrine pública: núcleo 5315 interno (sem EXECUTE); 5317/5318 definer STABLE, anon+authenticated; páginas sem ids nem dados privados');
  res := res || jsonb_build_object('id','0.8','ok',
    (select count(*) from information_schema.role_table_grants g
      where g.table_schema = 'public' and g.grantee in ('anon','authenticated')
        and g.privilege_type in ('TRUNCATE','REFERENCES','TRIGGER')) = 0
    and has_table_privilege('authenticated', 'public.user_profile', 'SELECT')
    and has_table_privilege('authenticated', 'public.user_profile', 'UPDATE')
    and has_table_privilege('authenticated', 'public.catalog_card_set_metrics', 'SELECT')
    and has_table_privilege('authenticated', 'public.catalog_card_set_image_coverage', 'SELECT')
    and has_table_privilege('authenticated', 'public.catalog_card_set_variant_coverage', 'SELECT')
    and (select count(*) from pg_policy pl where pl.polrelid = 'public.user_profile'::regclass) = 2,
    'detail','5319: nenhum TRUNCATE/REFERENCES/TRIGGER para anon/authenticated no schema; SELECT/UPDATE do perfil e SELECT das views do catálogo preservados; políticas de user_profile intactas');

  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.collection_membership), (select count(*) from public.card),
               (select count(*) from public.collection where visibility = 'PUBLIC')]
    into b_counts;

  begin
    -- F. Catálogo sintético e usuários --------------------------------------------------
    select g.id into v_game from public.game g where g.code = 'POKEMON';
    select l.id into v_pt from public.language l where l.code = 'pt-BR';
    select t.id into v_std from public.card_variant_type t where t.game_id = v_game and t.code = 'STANDARD';
    select c0.rarity_id, c0.category_id into v_rar, v_cat
    from public.card c0 join public.card_set cs0 on cs0.id = c0.card_set_id
    join public.expansion e0 on e0.id = cs0.expansion_id
    where e0.game_id = v_game limit 1;
    if v_game is null or v_pt is null or v_std is null or v_rar is null then
      res := res || jsonb_build_object('id','F.1','ok', false, 'detail','pré-requisitos de catálogo ausentes');
      raise exception 'MS861' using errcode = 'P0001';
    end if;
    insert into public.expansion (game_id, code, name, release_order)
    values (v_game, 'SHR_' || upper(v_sfx), 'SHR Harness ' || v_sfx,
            (select coalesce(max(x.release_order), 0) + 1000 from public.expansion x where x.game_id = v_game))
    returning id into v_exp;
    insert into public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_exp, 'SHR' || upper(v_sfx), 'SHR Set ' || v_sfx, 'REGULAR', 1, 2, 2) returning id into v_set;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '1', 1, 'SHR K1', true) returning id into k1;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '2', 2, 'SHR K2', true) returning id into k2;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k1, v_std, 1, true) returning id into k1s;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k2, v_std, 1, true) returning id into k2s;

    n_a := 'wh861a_' || v_sfx; n_b := 'wh861b_' || v_sfx;
    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
      (u_a, 'authenticated', 'authenticated', n_a || '@example.invalid', jsonb_build_object('username', n_a, 'display_name', 'WH 5861 A'), now(), now()),
      (u_b, 'authenticated', 'authenticated', n_b || '@example.invalid', jsonb_build_object('username', n_b, 'display_name', 'WH 5861 B'), now(), now()),
      (u_c, 'authenticated', 'authenticated', 'wh861c_' || v_sfx || '@example.invalid', jsonb_build_object('username', 'wh861c_' || v_sfx, 'display_name', 'WH 5861 C'), now(), now());
    select i.id into v_inv_a from public.inventory i where i.owner_user_id = u_a;
    select i.id into v_inv_b from public.inventory i where i.owner_user_id = u_b;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, created_at) values
      (k1s, v_pt, v_inv_a, now() - interval '3 min'), (k1s, v_pt, v_inv_a, now() - interval '2 min'),
      (k2s, v_pt, v_inv_a, now() - interval '1 min');
    select array_agg(pc.id order by pc.created_at) into v_ids from public.physical_card pc where pc.inventory_id = v_inv_a;
    a1 := v_ids[1]; a2 := v_ids[2]; x1 := v_ids[3];
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (k1s, v_pt, v_inv_b) returning id into b1;

    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select x.storage_container_id into v_bin from public.create_my_storage_container(gen_random_uuid(), 'BIN 5861', 'BINDER') x;
    select x.collection_id into v_co from public.create_my_free_collection(gen_random_uuid(), 'CO 5861', v_bin) x;
    select x.collection_id into v_cx from public.create_my_free_collection(gen_random_uuid(), 'CX 5861', v_bin) x;
    perform public.allocate_physical_cards_to_collection(v_co, array[a1, a2]);
    perform public.allocate_physical_cards_to_collection(v_cx, array[x1]);
    select * into p from public.preview_my_collection_binder(v_co, 3, 3, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_co, 3, 3, 'PRINCIPAL_ONLY', p.plan_token);
    execute 'reset role';
    res := res || jsonb_build_object('id','F.1','ok',
      v_co is not null and v_cx is not null
      and (select count(*) from public.collection_allocation ca where ca.collection_id = v_co) = 2
      and exists (select 1 from public.collection_layout l where l.collection_id = v_co),
      'detail','fixture: CO (2 cópias de K1, com fichário) e CX (K2) de A; b1 no acervo de B');

    -- F.2 Fichário compartilhado entre CO (dona) e CX (convidada), com uma carta e uma
    -- reserva de cada coleção. Exemplares guardados no local do fichário (passo
    -- privilegiado, como o catálogo); o resto pelas RPCs canônicas de A.
    select l.id into v_layout from public.collection_layout l where l.collection_id = v_co;
    update public.physical_card pc set storage_container_id = (select l.storage_container_id from public.collection_layout l where l.id = v_layout)
    where pc.id in (a1, a2, x1);
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.attach_my_collection_to_binder(v_cx, v_layout);
    execute 'reset role';
    select array_agg(s.id order by p2.page_number, s.row_index, s.column_index) into v_slots
    from public.collection_layout_slot s join public.collection_layout_page p2 on p2.id = s.page_id
    where p2.layout_id = v_layout;
    execute 'set local role authenticated';
    if not exists (select 1 from public.collection_layout_slot_assignment a where a.physical_card_id = a1) then
      select sl into v_sl from unnest(v_slots) sl
      where not exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = sl)
        and not exists (select 1 from public.collection_layout_slot_expected_content e where e.slot_id = sl) limit 1;
      perform public.place_my_physical_card_in_slot(v_co, v_sl, a1);
    end if;
    select sl into v_sl from unnest(v_slots) sl
    where not exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = sl)
      and not exists (select 1 from public.collection_layout_slot_expected_content e where e.slot_id = sl) limit 1;
    perform public.place_my_physical_card_in_slot(v_cx, v_sl, x1);
    select sl into v_sl from unnest(v_slots) sl
    where not exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = sl)
      and not exists (select 1 from public.collection_layout_slot_expected_content e where e.slot_id = sl) limit 1;
    begin perform public.set_slot_expected_content(v_sl, k1, null, null, v_co); v_res_co := true; exception when others then v_res_co := false; end;
    select sl into v_sl from unnest(v_slots) sl
    where not exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = sl)
      and not exists (select 1 from public.collection_layout_slot_expected_content e where e.slot_id = sl) limit 1;
    begin perform public.set_slot_expected_content(v_sl, k2, null, null, v_cx); v_res_cx := true; exception when others then v_res_cx := false; end;
    -- Verdade do titular (contrato 5252), para comparar com a visão do VIEWER.
    select count(*) filter (where o.present_collection_id = v_co),
           count(*) filter (where o.slot_state = 'RESERVED_EMPTY' and o.expected_collection_id = v_co),
           count(distinct o.page_number)
      into o_cards, o_res, o_pages
    from public.get_my_collection_binder_pages(v_co, 1, 4) o;
    execute 'reset role';
    select count(*) into asg0 from public.collection_layout_slot_assignment a
    join public.collection_layout_slot s on s.id = a.slot_id join public.collection_layout_page p2 on p2.id = s.page_id
    where p2.layout_id = v_layout;
    select count(*) into exp0 from public.collection_layout_slot_expected_content e
    join public.collection_layout_slot s on s.id = e.slot_id join public.collection_layout_page p2 on p2.id = s.page_id
    where p2.layout_id = v_layout;
    res := res || jsonb_build_object('id','F.2','ok',
      exists (select 1 from public.collection_layout_guest g where g.layout_id = v_layout and g.collection_id = v_cx)
      and exists (select 1 from public.collection_layout_slot_assignment a where a.physical_card_id = a1)
      and exists (select 1 from public.collection_layout_slot_assignment a where a.physical_card_id = x1)
      and v_res_co and o_cards >= 1,
      'detail','fixture do fichário: CX convidada; a1 e x1 em bolsos; reserva de CO = ' || v_res_co
        || '; reserva de CX = ' || v_res_cx || ' (opcional); titular vê ' || coalesce(o_cards, 0) || ' carta(s) de CO e '
        || coalesce(o_res, 0) || ' reserva(s) de CO');

    -- 1. Estranho e anon -----------------------------------------------------------------
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    v_err := null; begin perform public.invite_collection_member(v_co, n_b); exception when others then v_err := sqlstate; end;
    v_ok := v_err = '42501';
    v_err := null; begin perform public.get_shared_collection(v_co); exception when others then v_err := sqlstate; end;
    v_ok := v_ok and v_err = '42501';
    v_err := null; begin perform count(*) from public.get_shared_collection_cards(v_co, 48, 0); exception when others then v_err := sqlstate; end;
    v_ok := v_ok and v_err = '42501';
    v_err := null; begin perform count(*) from public.get_public_collection_binder_pages(v_co, 1, 4); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','1.1','ok', v_ok and public.get_public_collection_binder(v_co) is null
      and public.get_public_collection_binder(gen_random_uuid()) is null and v_err = 'COLLECTION_NOT_FOUND',
      'detail','anon: convite, cabeçalho e galeria do participante 42501; vitrine de coleção PRIVATE ≡ inexistente (NULL / COLLECTION_NOT_FOUND)');
    v_err := null; begin perform public.get_shared_collection_binder(v_co); exception when others then v_err := sqlstate; end;
    v_ok := v_err = '42501';
    v_err := null; begin perform count(*) from public.get_shared_collection_binder_pages(v_co, 1, 4); exception when others then v_err := sqlstate; end;
    v_ok := v_ok and v_err = '42501';
    execute 'reset role';

    perform set_config('request.jwt.claim.sub', u_c::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_c, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    res := res || jsonb_build_object('id','1.2','ok',
      public.get_shared_collection(v_co) is null and public.get_shared_collection(gen_random_uuid()) is null
      and (select count(*) from public.get_shared_collection_cards(v_co, 48, 0)) = 0
      and public.get_my_collection_sharing(v_co) is null,
      'detail','estranho: privada alheia ≡ inexistente (NULL, zero linhas, sem painel)');
    v_err := null; begin perform count(*) from public.get_shared_collection_binder_pages(v_co, 1, 4); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','1.5','ok', v_ok and public.get_shared_collection_binder(v_co) is null
      and v_err = 'COLLECTION_NOT_FOUND',
      'detail','fichário: anon sem EXECUTE (42501); estranho → cabeçalho NULL e páginas COLLECTION_NOT_FOUND');
    v_err := null; begin perform public.invite_collection_member(v_co, n_b); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','1.3','ok', v_err = 'COLLECTION_NOT_FOUND',
      'detail','estranho não convida em coleção alheia (COLLECTION_NOT_FOUND)');
    v_err := null; begin perform public.set_collection_visibility(v_co, 'PUBLIC'); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','1.4','ok', v_err = 'COLLECTION_NOT_FOUND'
      and (select c3.visibility from public.collection c3 where c3.id = v_co) is null,
      'detail','estranho não publica (e nem lê a coleção pela tabela — RLS select-own)');
    execute 'reset role';

    -- 2. Convite -------------------------------------------------------------------------
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    j := public.invite_collection_member(v_co, '  @' || upper(n_b) || ' ');
    m_b := (j ->> 'membership_id')::uuid;
    res := res || jsonb_build_object('id','2.1','ok', j ->> 'outcome' = 'INVITED' and j ->> 'username' = n_b
      and j ->> 'display_name' = 'WH 5861 B' and not (j ? 'user_id'),
      'detail','convite por @USERNAME normalizado → INVITED; devolve só username e nome de exibição');
    j := public.invite_collection_member(v_co, n_b);
    v_err := null; begin perform count(*) from public.collection_membership; exception when others then v_err := sqlstate; end;
    res := res || jsonb_build_object('id','2.2','ok', j ->> 'outcome' = 'ALREADY_PENDING' and (j ->> 'membership_id')::uuid = m_b
      and v_err = '42501',
      'detail','repetição → ALREADY_PENDING, mesma participação; tabela inacessível direto (42501)');
    v_err := null; begin perform public.invite_collection_member(v_co, 'nao_existe_' || v_sfx); exception when others then v_err := sqlerrm; end;
    v_ok := v_err = 'USER_NOT_FOUND';
    v_err := null; begin perform public.invite_collection_member(v_co, n_a); exception when others then v_err := sqlerrm; end;
    v_ok := v_ok and v_err = 'CANNOT_INVITE_SELF';
    v_err := null; begin perform public.invite_collection_member(v_co, 'a b'); exception when others then v_err := sqlerrm; end;
    v_ok := v_ok and v_err = 'INVALID_USERNAME';
    res := res || jsonb_build_object('id','2.3','ok', v_ok, 'detail','USER_NOT_FOUND, CANNOT_INVITE_SELF, INVALID_USERNAME');
    execute 'reset role';

    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    res := res || jsonb_build_object('id','2.4','ok', public.get_shared_collection(v_co) is null
      and (select count(*) from public.get_shared_collection_cards(v_co, 48, 0)) = 0
      and jsonb_array_length(public.get_collections_shared_with_me()) = 0,
      'detail','convite PENDING não dá acesso antecipado (cabeçalho, cartas, lista)');
    v_err := null; begin perform count(*) from public.get_shared_collection_binder_pages(v_co, 1, 4); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','2.8','ok', public.get_shared_collection_binder(v_co) is null and v_err = 'COLLECTION_NOT_FOUND',
      'detail','convite PENDING não abre o fichário');
    j := public.get_my_collection_invites();
    res := res || jsonb_build_object('id','2.5','ok', jsonb_array_length(j) = 1
      and j -> 0 ->> 'collection_name' = 'CO 5861' and j -> 0 ->> 'owner_username' = n_a
      and (j -> 0 ->> 'membership_id')::uuid = m_b
      and not (j -> 0 ? 'copies_count') and not (j -> 0 ? 'owner_user_id'),
      'detail','caixa de convites: só o necessário para decidir (nome, titular) — sem cartas, sem ids de usuário');
    execute 'reset role';

    perform set_config('request.jwt.claim.sub', u_c::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_c, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    v_err := null; begin perform public.respond_collection_invite(m_b, true); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','2.6','ok', v_err = 'INVITE_NOT_FOUND' and jsonb_array_length(public.get_my_collection_invites()) = 0,
      'detail','estranho não aceita convite alheio nem o vê na caixa');
    execute 'reset role';

    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    j := public.respond_collection_invite(m_b, true);
    j2 := public.respond_collection_invite(m_b, true);
    res := res || jsonb_build_object('id','2.7','ok', j ->> 'outcome' = 'ACTIVE' and j2 ->> 'outcome' = 'UNCHANGED'
      and jsonb_array_length(public.get_my_collection_invites()) = 0,
      'detail','aceite → ACTIVE; segundo aceite → UNCHANGED; caixa vazia');

    -- 3. VIEWER ---------------------------------------------------------------------------
    j := public.get_shared_collection(v_co);
    res := res || jsonb_build_object('id','3.1','ok', j ->> 'access' = 'VIEWER' and (j ->> 'copies_count')::int = 2
      and (j ->> 'membership_id')::uuid = m_b and j ->> 'owner_display_name' = 'WH 5861 A'
      and (select bool_and(k = any(allowed)) from jsonb_object_keys(j) k),
      'detail','VIEWER lê o cabeçalho de CO; só chaves permitidas (sem username/id do titular, sem local, sem valor)');
    select count(*), bool_and(x.card_name = 'SHR K1' and x.copies_count = 2) into n, v_ok
    from public.get_shared_collection_cards(v_co, 48, 0) x;
    res := res || jsonb_build_object('id','3.2','ok', n = 1 and v_ok,
      'detail','galeria: só as cartas alocadas a CO (K1 ×2), nunca K2 de CX');
    res := res || jsonb_build_object('id','3.3','ok', public.get_shared_collection(v_cx) is null
      and (select count(*) from public.get_shared_collection_cards(v_cx, 48, 0)) = 0,
      'detail','outra coleção do mesmo titular continua invisível');
    j := public.get_collections_shared_with_me();
    res := res || jsonb_build_object('id','3.4','ok', jsonb_array_length(j) = 1 and (j -> 0 ->> 'collection_id')::uuid = v_co
      and not (j -> 0 ? 'owner_username'),
      'detail','"Compartilhadas comigo" lista só CO');
    -- get_my_collection_binder nega coleção alheia por exceção (COLLECTION_NOT_FOUND);
    -- zero linhas também é negação. Qualquer outro erro reprova.
    v_closed := null;
    begin
      v_closed := not exists (select 1 from public.get_my_collection_binder(v_co) bh where bh.has_binder);
    exception when others then
      v_closed := (sqlerrm = 'COLLECTION_NOT_FOUND');
    end;
    res := res || jsonb_build_object('id','3.5','ok',
      not exists (select 1 from public.get_my_collections(true, 100, 0) g where g.collection_id = v_co)
      and not exists (select 1 from public.get_my_inventory_items(null, null, null, v_co) i)
      and coalesce(v_closed, false)
      and public.get_my_collection_sharing(v_co) is null,
      'detail','contratos get_my_* não se abrem ao VIEWER: coleção, acervo do titular, fichário e painel ficam fechados');
    v_ok := true;
    v_err := null; begin perform public.allocate_physical_cards_to_collection(v_co, array[b1]); exception when others then v_err := sqlerrm; end;
    v_ok := v_ok and v_err is not null;
    v_err := null; begin perform public.update_collection_metadata(v_co, 'hack', null); exception when others then v_err := sqlerrm; end;
    v_ok := v_ok and v_err is not null;
    v_err := null; begin perform public.archive_collection(v_co); exception when others then v_err := sqlerrm; end;
    v_ok := v_ok and v_err is not null;
    v_err := null; begin perform public.invite_collection_member(v_co, 'wh861c_' || v_sfx); exception when others then v_err := sqlerrm; end;
    v_ok := v_ok and v_err = 'COLLECTION_NOT_FOUND';
    v_err := null; begin perform public.set_collection_visibility(v_co, 'PUBLIC'); exception when others then v_err := sqlerrm; end;
    v_ok := v_ok and v_err = 'COLLECTION_NOT_FOUND';
    v_err := null; begin perform public.remove_collection_member(v_co, m_b); exception when others then v_err := sqlerrm; end;
    v_ok := v_ok and v_err = 'MEMBERSHIP_NOT_FOUND';

    -- Fichário só leitura (5314/5315).
    j := public.get_shared_collection_binder(v_co);
    res := res || jsonb_build_object('id','3.8','ok', (j ->> 'has_binder')::boolean
      and (j ->> 'grid_columns')::int = 3 and (j ->> 'grid_rows')::int = 3
      and (j ->> 'page_count')::int = o_pages and (j ->> 'own_filled_count')::int = o_cards
      and (select bool_and(k = any(array['has_binder','grid_columns','grid_rows','page_count','own_filled_count',  -- E1E
                                          'binder_name','show_brand_mark'])) from jsonb_object_keys(j) k)  -- E1E: chaves da 5321
      and jsonb_typeof(j -> 'binder_name') in ('string', 'null') and jsonb_typeof(j -> 'show_brand_mark') = 'boolean'  -- E1E
      and public.get_shared_collection_binder(v_cx) is null,
      'detail','VIEWER: cabeçalho do fichário de CO (grade, páginas, cartas DE CO) sem local, participantes nem disponíveis; CX fechada');
    select count(*) filter (where b.pocket_state = 'CARD'),
           count(*) filter (where b.pocket_state = 'RESERVED'),
           count(*) filter (where b.pocket_state = 'CARD' and b.card_name is distinct from 'SHR K1'),
           count(*) filter (where b.pocket_state = 'EMPTY'
                              and (b.card_name is not null or b.image_path is not null or b.language_code is not null
                                   or b.collector_number is not null or b.variant_label is not null)),
           count(*) filter (where b.pocket_state not in ('CARD','RESERVED','EMPTY')),
           count(*)
      into b_card, b_res, b_bad, b_leak, b_odd, b_total
    from public.get_shared_collection_binder_pages(v_co, 1, 4) b;
    res := res || jsonb_build_object('id','3.9','ok', b_card = o_cards and b_bad = 0 and b_odd = 0 and b_total = 9,
      'detail','VIEWER: bolsos com carta = só os exemplares de CO (' || b_card || '/' || o_cards || '); x1 de CX nunca aparece; 9 bolsos, 3 estados');
    res := res || jsonb_build_object('id','3.10','ok', b_res = o_res and b_leak = 0
      and not exists (select 1 from public.get_shared_collection_binder_pages(v_co, 1, 4) b where b.card_name = 'SHR K2'),
      'detail','VIEWER: reservas = só as de CO (' || b_res || '/' || o_res || '); bolso vazio/de outra coleção não carrega texto nem imagem; K2 (CX) nunca aparece');
    -- Escrita no fichário pelo VIEWER: toda tentativa recusada (erro ou nenhum efeito);
    -- o estado, conferido como dono do banco logo abaixo, decide.
    v_ok2 := true;
    v_err := null; begin perform public.place_my_physical_card_in_slot(v_co, v_slots[9], b1); exception when others then v_err := sqlerrm; end;
    v_ok2 := v_ok2 and v_err is not null;
    begin perform public.move_slot_assignment(v_slots[1], v_slots[9]); exception when others then null; end;
    begin perform public.remove_slot_assignment(v_slots); exception when others then null; end;
    begin perform public.set_slot_lock(v_slots, true); exception when others then null; end;
    begin perform public.clear_slot_expected_content(v_slots); exception when others then null; end;
    begin perform public.set_slot_expected_content(v_slots[9], k1, null, null, v_co); exception when others then null; end;
    begin perform public.add_layout_page(v_layout); exception when others then null; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','3.11','ok', v_ok2
      and (select count(*) from public.collection_layout_slot_assignment a
           join public.collection_layout_slot s on s.id = a.slot_id join public.collection_layout_page p2 on p2.id = s.page_id
           where p2.layout_id = v_layout) = asg0
      and (select count(*) from public.collection_layout_slot_expected_content e
           join public.collection_layout_slot s on s.id = e.slot_id join public.collection_layout_page p2 on p2.id = s.page_id
           where p2.layout_id = v_layout) = exp0
      and not exists (select 1 from public.collection_layout_slot s join public.collection_layout_page p2 on p2.id = s.page_id
                      where p2.layout_id = v_layout and s.locked)
      and (select count(*) from public.collection_layout_page p2 where p2.layout_id = v_layout) = o_pages
      and not exists (select 1 from public.collection_layout_slot_assignment a where a.physical_card_id = b1),
      'detail','VIEWER no fichário: posicionar, mover, tirar, fixar, reservar, limpar reserva e criar página — nada mudou');
    res := res || jsonb_build_object('id','3.6','ok', v_ok
      and (select c3.name from public.collection c3 where c3.id = v_co) = 'CO 5861'
      and (select c3.lifecycle_status from public.collection c3 where c3.id = v_co) = 'ACTIVE'
      and (select count(*) from public.collection_allocation ca where ca.collection_id = v_co) = 2
      and not exists (select 1 from public.collection_allocation ca where ca.physical_card_id = b1),
      'detail','VIEWER: alocar, renomear, arquivar, convidar, publicar e remover recusados; nada mudou');

    -- S-PROG: para cada coleção com referência no banco, sob a identidade do titular.
    v_ok := true; n := 0;
    for c in select c4.id, c4.owner_user_id from public.collection c4 where c4.mode = 'REFERENCE_BASED' loop
      perform set_config('request.jwt.claim.sub', c.owner_user_id::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', c.owner_user_id, 'role', 'authenticated')::text, true);
      v_ok := v_ok and not exists (
        (select * from public.collection_completion_summary(c.id) except select * from public.collection_completion_summary_shared(c.id))
        union all
        (select * from public.collection_completion_summary_shared(c.id) except select * from public.collection_completion_summary(c.id)));
      n := n + 1;
    end loop;
    res := res || jsonb_build_object('id','3.7','ok', v_ok,
      'detail','S-PROG: progresso compartilhado idêntico ao do titular em ' || n || ' coleção(ões) com referência');

    -- 4. Revogação ------------------------------------------------------------------------
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    j := public.get_my_collection_sharing(v_co);
    res := res || jsonb_build_object('id','4.1','ok', j ->> 'visibility' = 'PRIVATE'
      and jsonb_array_length(j -> 'members') = 1 and j -> 'members' -> 0 ->> 'status' = 'ACTIVE'
      and j -> 'members' -> 0 ->> 'username' = n_b and not (j -> 'members' -> 0 ? 'user_id'),
      'detail','painel do titular: B participante, por username (sem id de usuário)');
    j := public.remove_collection_member(v_co, m_b);
    v_err := null; begin perform public.remove_collection_member(v_co, m_b); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','4.2','ok', j ->> 'outcome' = 'REMOVED' and v_err = 'MEMBERSHIP_NOT_FOUND',
      'detail','titular remove B; repetição → MEMBERSHIP_NOT_FOUND');
    execute 'reset role';

    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    res := res || jsonb_build_object('id','4.3','ok', public.get_shared_collection(v_co) is null
      and (select count(*) from public.get_shared_collection_cards(v_co, 48, 0)) = 0
      and jsonb_array_length(public.get_collections_shared_with_me()) = 0,
      'detail','remoção revoga na hora: cabeçalho, cartas e lista');
    v_err := null; begin perform count(*) from public.get_shared_collection_binder_pages(v_co, 1, 4); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','4.7','ok', public.get_shared_collection_binder(v_co) is null and v_err = 'COLLECTION_NOT_FOUND',
      'detail','remoção revoga o fichário na hora (cabeçalho NULL, páginas COLLECTION_NOT_FOUND)');
    execute 'reset role';

    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    m_b := (public.invite_collection_member(v_co, n_b) ->> 'membership_id')::uuid;
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    j := public.respond_collection_invite(m_b, false);
    v_err := null; begin perform public.respond_collection_invite(m_b, true); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','4.4','ok', j ->> 'outcome' = 'DECLINED' and v_err = 'INVITE_NOT_FOUND'
      and public.get_shared_collection(v_co) is null,
      'detail','recusa → DECLINED, sem acesso; aceitar depois de recusar não reabre');
    execute 'reset role';

    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    j := public.get_my_collection_sharing(v_co);
    j2 := public.invite_collection_member(v_co, n_b);
    res := res || jsonb_build_object('id','4.5','ok', j -> 'members' -> 0 ->> 'status' = 'DECLINED'
      and j2 ->> 'outcome' = 'REINVITED' and (j2 ->> 'membership_id')::uuid = m_b,
      'detail','titular vê "recusou" e pode convidar de novo (REINVITED, mesma linha)');
    execute 'reset role';

    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.respond_collection_invite(m_b, true);
    v_ok := public.get_shared_collection(v_co) ->> 'access' = 'VIEWER';
    j := public.leave_shared_collection(v_co);
    v_err := null; begin perform public.leave_shared_collection(v_co); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','4.6','ok', v_ok and j ->> 'outcome' = 'LEFT' and v_err = 'NOT_A_MEMBER'
      and public.get_shared_collection(v_co) is null,
      'detail','reaceite → VIEWER; sair → LEFT e acesso revogado; repetição → NOT_A_MEMBER');
    execute 'reset role';

    -- 5. Público ---------------------------------------------------------------------------
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    j := public.set_collection_visibility(v_co, 'public');
    j2 := public.set_collection_visibility(v_co, 'PUBLIC');
    res := res || jsonb_build_object('id','5.1','ok', j ->> 'outcome' = 'CHANGED' and j2 ->> 'outcome' = 'UNCHANGED'
      and jsonb_array_length(public.get_my_collection_sharing(v_co) -> 'members') = 0,
      'detail','titular publica (CHANGED, depois UNCHANGED); visibilidade não cria participação');
    execute 'reset role';

    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    j := public.get_public_collection_binder(v_co);
    res := res || jsonb_build_object('id','5.2','ok', (j ->> 'has_binder')::boolean
      and (j ->> 'grid_columns')::int = 3 and (j ->> 'grid_rows')::int = 3 and (j ->> 'page_count')::int = o_pages
      and j ->> 'owner_display_name' = 'WH 5861 A'
      and (select bool_and(k = any(pub_allowed)) from jsonb_object_keys(j) k)
      and public.get_public_collection_binder(v_cx) is null,
      'detail','sem sessão: vitrine de CO (capa, identidade, grade, páginas) só com chaves permitidas — sem progresso, contagem, descrição ou local; CX fechada');
    select count(*) filter (where b.pocket_state = 'CARD'),
           count(*) filter (where b.pocket_state = 'RESERVED'),
           count(*) filter (where b.pocket_state = 'EMPTY'
                              and (b.card_name is not null or b.image_path is not null or b.language_code is not null)),
           count(*)
      into b_card, b_res, b_leak, b_total
    from public.get_public_collection_binder_pages(v_co, 1, 4) b;
    res := res || jsonb_build_object('id','5.8','ok', b_card = o_cards and b_res = o_res and b_leak = 0 and b_total = 9
      and not exists (select 1 from public.get_public_collection_binder_pages(v_co, 1, 4) b where b.card_name = 'SHR K2'),
      'detail','sem sessão: bolsos da vitrine com o MESMO mascaramento do participante — x1 e a reserva de CX (outra coleção do fichário) nunca aparecem');
    v_err := null; begin perform public.get_collections_shared_with_me(); exception when others then v_err := sqlstate; end;
    v_ok := v_err = '42501';
    v_err := null; begin perform public.set_collection_visibility(v_co, 'PRIVATE'); exception when others then v_err := sqlstate; end;
    res := res || jsonb_build_object('id','5.3','ok', v_ok and v_err = '42501',
      'detail','sem sessão: listas pessoais e escrita recusadas (42501)');
    execute 'reset role';

    perform set_config('request.jwt.claim.sub', u_c::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_c, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    v_err := null; begin perform public.invite_collection_member(v_co, n_b); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','5.4','ok', public.get_shared_collection(v_co) is null
      and (select count(*) from public.get_shared_collection_cards(v_co, 48, 0)) = 0
      and public.get_public_collection_binder(v_co) is not null
      and v_err = 'COLLECTION_NOT_FOUND' and jsonb_array_length(public.get_collections_shared_with_me()) = 0,
      'detail','pública ≠ participação: estranho com sessão vê só a vitrine; cabeçalho/galeria do participante fechados; não vira membro, não convida');
    v_err := null; begin perform count(*) from public.get_shared_collection_binder_pages(v_co, 1, 4); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','5.7','ok', public.get_shared_collection_binder(v_co) is null and v_err = 'COLLECTION_NOT_FOUND',
      'detail','coleção PUBLIC não abre o fichário para quem não é participante (decisão conservadora; anon já sem EXECUTE em 1.5)');
    execute 'reset role';

    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.set_collection_visibility(v_co, 'PRIVATE');
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    v_err := null; begin perform count(*) from public.get_public_collection_binder_pages(v_co, 1, 4); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','5.5','ok', public.get_public_collection_binder(v_co) is null and v_err = 'COLLECTION_NOT_FOUND',
      'detail','despublicar (PRIVATE) revoga a vitrine na próxima leitura');
    execute 'reset role';

    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    m_b := (public.invite_collection_member(v_cx, n_b) ->> 'membership_id')::uuid;
    perform public.archive_collection(v_cx);
    v_ok := true;
    v_err := null; begin perform public.invite_collection_member(v_cx, 'wh861c_' || v_sfx); exception when others then v_err := sqlerrm; end;
    v_ok := v_ok and v_err = 'COLLECTION_ARCHIVED';
    v_err := null; begin perform public.set_collection_visibility(v_cx, 'PUBLIC'); exception when others then v_err := sqlerrm; end;
    v_ok := v_ok and v_err = 'COLLECTION_ARCHIVED';
    v_ok := v_ok and public.set_collection_visibility(v_cx, 'PRIVATE') ->> 'outcome' = 'UNCHANGED';
    v_ok := v_ok and public.remove_collection_member(v_cx, m_b) ->> 'outcome' = 'REMOVED';
    res := res || jsonb_build_object('id','5.6','ok', v_ok,
      'detail','arquivada: não convida nem publica; remover participação e manter privada seguem possíveis');
    -- 5.9 Arquivar uma coleção publicada tira a vitrine do ar (sem despublicar).
    perform public.set_collection_visibility(v_co, 'PUBLIC');
    v_sl := null; v_ok2 := true;
    begin perform public.archive_collection(v_co); exception when others then v_ok2 := false; end;
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    v_err := null; begin perform count(*) from public.get_public_collection_binder_pages(v_co, 1, 4); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','5.9','ok', v_ok2 and public.get_public_collection_binder(v_co) is null and v_err = 'COLLECTION_NOT_FOUND',
      'detail','coleção PUBLIC arquivada sai da vitrine na hora (arquivamento aceito = ' || v_ok2 || ')');
    execute 'reset role';

    raise exception 'MS861' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MS861' then
      res := res || jsonb_build_object('id','X.1','ok', false, 'detail','erro inesperado: '||sqlstate||' '||sqlerrm);
    end if;
  end;

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.collection_membership), (select count(*) from public.card),
               (select count(*) from public.collection where visibility = 'PUBLIC')]
    into e_counts;
  res := res || jsonb_build_object('id','99.1','ok', b_counts = e_counts and current_user = session_user,
    'detail','resíduo zero (7 contagens) e papel restaurado');

  for r in select * from jsonb_array_elements(res) loop
    cnt := cnt + 1;
    if (r ->> 'ok')::boolean then passes := passes + 1; end if;
    seq := cnt; check_id := r ->> 'id';
    status := case when (r ->> 'ok')::boolean then 'PASS' else 'FAIL' end;
    detail := r ->> 'detail';
    return next;
  end loop;
  seq := cnt + 1; check_id := 'GATE';
  status := case when passes = cnt and cnt = v_expected then 'PASS' else 'FAIL' end;
  detail := passes || '/' || cnt || ' PASS (esperado ' || v_expected || ')';
  return next;
end;
$fn$;
insert into pg_temp.g2_evidence (harness, seq, check_id, status, detail)
  select '5861', seq, check_id, status, detail from pg_temp.wh_5861_validate();

-- @@T8 modo da barreira OPEN (só nesta transação)
update public.v1_13_barrier_state set mode = 'OPEN', change_note = 'G2 ensaio' where id = 1;

-- @@T8 harness 5888 [OPEN] sha256=50aa49beb5c06d0c65720717e2fbfde16ee77a3506acf066a77d050a1c7087b6
create or replace function pg_temp.wh_5888_as(p_user uuid)
returns void language plpgsql volatile as $as$
begin
  execute 'reset role';
  if p_user is null then
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
  else
    perform set_config('request.jwt.claim.sub', p_user::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
  end if;
end;
$as$;

create or replace function pg_temp.wh_5888_claims(p_user uuid)
returns void language plpgsql volatile as $cl$
begin
  -- Só troca a identidade (auth.uid()); o papel de banco continua o da sessão (dono).
  if p_user is null then
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
  else
    perform set_config('request.jwt.claim.sub', p_user::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  end if;
end;
$cl$;

create or replace function pg_temp.wh_5888_reads(p_collection uuid)
returns jsonb language sql volatile as $rd$
  -- Tudo o que um participante lê da coleção, sem a chave 'role' (que é a única diferença esperada).
  select jsonb_build_object(
    'hdr', public.get_shared_collection(p_collection) - 'role',
    'crd', (select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text), '[]'::jsonb) from public.get_shared_collection_cards(p_collection, 48, 0) x),
    'bh',  public.get_shared_collection_binder(p_collection),
    'bp',  (select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text), '[]'::jsonb) from public.get_shared_collection_binder_pages(p_collection, 1, 4) x),
    'img', (select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text), '[]'::jsonb) from public.get_shared_collection_binder_images(p_collection, 1, 4) x),
    'cov', (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from public.get_shared_collection_cover(p_collection) x),
    'pos', (select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text), '[]'::jsonb) from public.get_shared_collection_positions(p_collection, 'ALL', 200, 0) x),
    'swm', (select coalesce(jsonb_agg(e - 'role'), '[]'::jsonb) from jsonb_array_elements(public.get_collections_shared_with_me()) e));
$rd$;

create or replace function pg_temp.wh_5888_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  f_inv  oid := to_regprocedure('public.invite_collection_member(uuid, text, text)');
  f_old  oid := to_regprocedure('public.invite_collection_member(uuid, text)');
  f_set  oid := to_regprocedure('public.set_collection_member_role(uuid, uuid, text)');
  f_mr   oid := to_regprocedure('public.collection_member_role(uuid)');
  f_rol  oid := to_regprocedure('public.collection_share_role(uuid)');
  f_box  oid := to_regprocedure('public.get_my_collection_invites()');
  f_swm  oid := to_regprocedure('public.get_collections_shared_with_me()');
  f_get  oid := to_regprocedure('public.get_shared_collection(uuid)');
  f_shr  oid := to_regprocedure('public.get_my_collection_sharing(uuid)');
  hdr_allowed text[] := array['collection_id','name','description','mode','completion_policy','lifecycle_status',
    'visibility','cover_finish','card_set_code','card_set_name','card_set_logo_path','owner_display_name',
    'access','membership_id','copies_count','total_positions','satisfied_positions','progress_percentage','is_complete','role'];
  swm_allowed text[] := array['collection_id','name','mode','completion_policy','lifecycle_status','cover_finish',
    'card_set_code','card_set_name','owner_display_name','accepted_at','copies_count','total_positions',
    'satisfied_positions','progress_percentage','is_complete','role'];
  box_allowed text[] := array['membership_id','role','collection_id','collection_name','mode','completion_policy',
    'card_set_name','owner_display_name','owner_username','invited_at'];
  inv_allowed text[] := array['outcome','membership_id','username','display_name','status','role'];
  u_a uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  u_c uuid := gen_random_uuid(); u_d uuid := gen_random_uuid();
  v_sfx text := lower(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  n_a text; n_b text; n_c text; n_d text;
  v_chk text; v_chkb boolean;  -- E1E: conferências internas lidas no contexto do dono
  v_game uuid; v_pt uuid; v_rar uuid; v_cat uuid; v_std uuid; v_exp uuid; v_set uuid; k1 uuid; k1s uuid;
  v_inv_a uuid; a1 uuid; v_bin uuid; v_co uuid; v_cx uuid; m_b uuid; m_d uuid; m_d2 uuid;
  p record; j jsonb; j2 jsonb; v_err text; v_ok boolean; n integer;
  r_viewer jsonb; r_editor jsonb;
  b_counts bigint[]; e_counts bigint[];
  res jsonb := '[]'::jsonb; r jsonb; cnt integer := 0; passes integer := 0;
  v_expected integer := 54;
begin
  -- 0. Estrutura ---------------------------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    (select pg_get_constraintdef(k.oid) from pg_constraint k
      where k.conrelid = 'public.collection_membership'::regclass and k.conname = 'chk_collection_membership_role')
      = 'CHECK ((role = ANY (ARRAY[''VIEWER''::text, ''EDITOR''::text])))'
    and (select column_default from information_schema.columns where table_schema='public'
          and table_name='collection_membership' and column_name='role') = '''VIEWER''::text'
    and (select c2.relrowsecurity from pg_class c2 where c2.oid = 'public.collection_membership'::regclass)
    and not exists (select 1 from pg_policy pl where pl.polrelid = 'public.collection_membership'::regclass)
    and not has_table_privilege('authenticated', 'public.collection_membership', 'SELECT,INSERT,UPDATE,DELETE')
    and not has_table_privilege('anon', 'public.collection_membership', 'SELECT,INSERT,UPDATE,DELETE'),
    'detail','5366: papel VIEWER|EDITOR, padrão VIEWER, RLS sem política, sem privilégio de tabela');
  res := res || jsonb_build_object('id','0.2','ok',
    f_mr is not null
    and coalesce((select q.prosecdef and q.proconfig = array['search_path=""'] and q.provolatile = 's' from pg_proc q where q.oid = f_mr), false)
    and not has_function_privilege('authenticated', f_mr, 'EXECUTE') and not has_function_privilege('anon', f_mr, 'EXECUTE'),
    'detail','5367: collection_member_role interna (definer STABLE, search_path vazio, sem EXECUTE para API)');
  res := res || jsonb_build_object('id','0.3','ok',
    f_inv is not null and f_old is null
    and (select count(*) from pg_proc q join pg_namespace s on s.oid = q.pronamespace
          where s.nspname = 'public' and q.proname = 'invite_collection_member') = 1
    and coalesce((select q.prosecdef and q.proconfig = array['search_path=""'] and q.pronargdefaults = 1 from pg_proc q where q.oid = f_inv), false)
    and has_function_privilege('authenticated', f_inv, 'EXECUTE') and not has_function_privilege('anon', f_inv, 'EXECUTE'),
    'detail','5369: uma única sobrecarga (uuid, text, text DEFAULT), antiga removida, só authenticated');
  res := res || jsonb_build_object('id','0.4','ok',
    f_set is not null
    and coalesce((select q.prosecdef and q.proconfig = array['search_path=""'] from pg_proc q where q.oid = f_set), false)
    and has_function_privilege('authenticated', f_set, 'EXECUTE') and not has_function_privilege('anon', f_set, 'EXECUTE'),
    'detail','5370: set_collection_member_role definer, search_path vazio, só authenticated');
  res := res || jsonb_build_object('id','0.5','ok',
    (select md5(q.prosrc) from pg_proc q where q.oid = f_rol) = 'efdb495b5b703e9f093eb0f49a1d0a5d'
    and not has_function_privilege('authenticated', f_rol, 'EXECUTE')
    and (select md5(q.prosrc) from pg_proc q where q.oid = f_shr) = 'e36aa9c675f6b8097b6a43292b62603f',
    'detail','5302 (nível de leitura) e 5308 (painel do titular) intocadas (md5 = canônica V1-12)');
  res := res || jsonb_build_object('id','0.6','ok',
    coalesce((select bool_and(q.prosecdef and q.proconfig = array['search_path=""']
                     and has_function_privilege('authenticated', q.oid, 'EXECUTE')
                     and not has_function_privilege('anon', q.oid, 'EXECUTE'))
       from pg_proc q where q.oid in (f_box, f_swm, f_get)), false),
    'detail','5368: leituras alteradas mantêm definer, search_path vazio e ACL');

  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.collection_membership), (select count(*) from public.card)]
    into b_counts;

  begin
    -- F. Catálogo sintético, usuários e fixture --------------------------------------
    select g.id into v_game from public.game g where g.code = 'POKEMON';
    select l.id into v_pt from public.language l where l.code = 'pt-BR';
    select t.id into v_std from public.card_variant_type t where t.game_id = v_game and t.code = 'STANDARD';
    select c0.rarity_id, c0.category_id into v_rar, v_cat
    from public.card c0 join public.card_set cs0 on cs0.id = c0.card_set_id
    join public.expansion e0 on e0.id = cs0.expansion_id where e0.game_id = v_game limit 1;
    if v_game is null or v_pt is null or v_std is null or v_rar is null then
      res := res || jsonb_build_object('id','F.1','ok', false, 'detail','pré-requisitos de catálogo ausentes');
      raise exception 'MS888' using errcode = 'P0001';
    end if;
    insert into public.expansion (game_id, code, name, release_order)
    values (v_game, 'EDR_' || upper(v_sfx), 'EDR Harness ' || v_sfx,
            (select coalesce(max(x.release_order), 0) + 1000 from public.expansion x where x.game_id = v_game))
    returning id into v_exp;
    insert into public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_exp, 'EDR' || upper(v_sfx), 'EDR Set ' || v_sfx, 'REGULAR', 1, 1, 1) returning id into v_set;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '1', 1, 'EDR K1', true) returning id into k1;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k1, v_std, 1, true) returning id into k1s;

    n_a := 'wh888a_' || v_sfx; n_b := 'wh888b_' || v_sfx; n_c := 'wh888c_' || v_sfx; n_d := 'wh888d_' || v_sfx;
    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
      (u_a, 'authenticated', 'authenticated', n_a || '@example.invalid', jsonb_build_object('username', n_a, 'display_name', 'WH 5888 A'), now(), now()),
      (u_b, 'authenticated', 'authenticated', n_b || '@example.invalid', jsonb_build_object('username', n_b, 'display_name', 'WH 5888 B'), now(), now()),
      (u_c, 'authenticated', 'authenticated', n_c || '@example.invalid', jsonb_build_object('username', n_c, 'display_name', 'WH 5888 C'), now(), now()),
      (u_d, 'authenticated', 'authenticated', n_d || '@example.invalid', jsonb_build_object('username', n_d, 'display_name', 'WH 5888 D'), now(), now());
    select i.id into v_inv_a from public.inventory i where i.owner_user_id = u_a;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (k1s, v_pt, v_inv_a) returning id into a1;

    perform pg_temp.wh_5888_as(u_a);
    select x.storage_container_id into v_bin from public.create_my_storage_container(gen_random_uuid(), 'BIN 5888', 'BINDER') x;
    select x.collection_id into v_co from public.create_my_free_collection(gen_random_uuid(), 'CO 5888', v_bin) x;
    select x.collection_id into v_cx from public.create_my_free_collection(gen_random_uuid(), 'CX 5888', v_bin) x;
    perform public.allocate_physical_cards_to_collection(v_co, array[a1]);
    select * into p from public.preview_my_collection_binder(v_co, 3, 3, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_co, 3, 3, 'PRINCIPAL_ONLY', p.plan_token);

    -- 1. Convite -----------------------------------------------------------------------
    perform pg_temp.wh_5888_as(u_a);
    j := public.invite_collection_member(v_co, n_b);                       -- 2 argumentos, como o frontend
    m_b := (j ->> 'membership_id')::uuid;
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    v_chk := (select m.role from public.collection_membership m where m.id = m_b);  -- E1E
    perform pg_temp.wh_5888_as(u_a);  -- E1E: volta ao mesmo cliente
    res := res || jsonb_build_object('id','1.1','ok',
      j ->> 'outcome' = 'INVITED' and j ->> 'role' = 'VIEWER'
      and v_chk = 'VIEWER',  -- E1E
      'detail','convite sem papel (chamada de 2 argumentos) grava VIEWER');
    j := public.invite_collection_member(v_co, '@' || upper(n_d), ' editor ');
    m_d := (j ->> 'membership_id')::uuid;
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    v_chk := (select m.role || '/' || m.status from public.collection_membership m where m.id = m_d);  -- E1E
    perform pg_temp.wh_5888_as(u_a);  -- E1E: volta ao mesmo cliente
    res := res || jsonb_build_object('id','1.2','ok',
      j ->> 'outcome' = 'INVITED' and j ->> 'role' = 'EDITOR'
      and v_chk = 'EDITOR/PENDING',  -- E1E
      'detail','convite EDITOR explícito (papel e username normalizados)');
    v_ok := true;
    foreach v_err in array array['OWNER','PUBLIC','ADMIN',''] loop
      j2 := null;
      begin j2 := public.invite_collection_member(v_cx, n_c, v_err); exception when others then j2 := jsonb_build_object('e', sqlerrm, 's', sqlstate); end;
      v_ok := v_ok and coalesce(j2 ->> 'e' = 'INVALID_ROLE' and j2 ->> 's' = '22023', false);
    end loop;
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    v_chkb := not exists (select 1 from public.collection_membership m where m.collection_id = v_cx);  -- E1E
    perform pg_temp.wh_5888_as(u_a);  -- E1E: volta ao mesmo cliente
    res := res || jsonb_build_object('id','1.3','ok', v_ok
      and v_chkb,  -- E1E
      'detail','OWNER/PUBLIC/ADMIN/vazio → INVALID_ROLE (22023), nada gravado');
    j := public.invite_collection_member(v_cx, n_c, null);
    res := res || jsonb_build_object('id','1.4','ok', j ->> 'role' = 'VIEWER' and j ->> 'outcome' = 'INVITED',
      'detail','p_role NULL explícito → VIEWER');
    v_err := null; begin perform public.invite_collection_member(v_co, n_a, 'EDITOR'); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','1.5','ok', v_err = 'CANNOT_INVITE_SELF',
      'detail','titular não se convida como EDITOR');

    -- 2. Convite pendente ----------------------------------------------------------------
    j := public.invite_collection_member(v_co, n_d, 'EDITOR');
    res := res || jsonb_build_object('id','2.1','ok', j ->> 'outcome' = 'ALREADY_PENDING' and (j ->> 'membership_id')::uuid = m_d and j ->> 'role' = 'EDITOR',
      'detail','pendente + mesmo papel → ALREADY_PENDING');
    v_err := null; begin perform public.invite_collection_member(v_co, n_d, 'VIEWER'); exception when others then v_err := sqlerrm || '/' || sqlstate; end;
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    v_chk := (select m.role || '/' || m.status from public.collection_membership m where m.id = m_d);  -- E1E
    perform pg_temp.wh_5888_as(u_a);  -- E1E: volta ao mesmo cliente
    res := res || jsonb_build_object('id','2.2','ok', v_err = 'INVITE_PENDING_ROLE_IMMUTABLE/55000'
      and v_chk = 'EDITOR/PENDING',  -- E1E
      'detail','pendente + outro papel → INVITE_PENDING_ROLE_IMMUTABLE, nada muda');
    v_err := null; begin perform public.invite_collection_member(v_co, n_d); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','2.3','ok', v_err = 'INVITE_PENDING_ROLE_IMMUTABLE',
      'detail','pendente EDITOR + chamada sem papel (VIEWER) também é recusada — sem conversão silenciosa');
    v_err := null; begin perform public.set_collection_member_role(v_co, m_d, 'VIEWER'); exception when others then v_err := sqlerrm; end;
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    v_chk := (select m.role from public.collection_membership m where m.id = m_d);  -- E1E
    perform pg_temp.wh_5888_as(u_a);  -- E1E: volta ao mesmo cliente
    res := res || jsonb_build_object('id','2.4','ok', v_err = 'INVITE_PENDING_ROLE_IMMUTABLE'
      and v_chk = 'EDITOR',  -- E1E
      'detail','troca de papel de convite pendente recusada');
    perform pg_temp.wh_5888_as(u_d);
    j := public.get_my_collection_invites();
    res := res || jsonb_build_object('id','2.5','ok',
      jsonb_array_length(j) = 1 and j -> 0 ->> 'role' = 'EDITOR'
      and not exists (select 1 from jsonb_object_keys(j -> 0) k where k <> all (box_allowed)),
      'detail','caixa de convites mostra o papel oferecido; nenhuma chave nova além de role');

    -- 3. Leitura VIEWER × EDITOR ---------------------------------------------------------
    perform pg_temp.wh_5888_as(u_b);
    perform public.respond_collection_invite(m_b, true);
    r_viewer := pg_temp.wh_5888_reads(v_co);
    j := public.get_shared_collection(v_co);
    res := res || jsonb_build_object('id','3.1','ok', j ->> 'access' = 'VIEWER' and j ->> 'role' = 'VIEWER' and j ->> 'membership_id' = m_b::text,
      'detail','VIEWER: access VIEWER, role VIEWER, membership_id presente');
    perform pg_temp.wh_5888_as(u_a);
    j := public.set_collection_member_role(v_co, m_b, 'EDITOR');
    perform pg_temp.wh_5888_as(u_b);
    r_editor := pg_temp.wh_5888_reads(v_co);
    res := res || jsonb_build_object('id','3.2','ok', r_editor = r_viewer and coalesce(r_editor -> 'hdr', 'null'::jsonb) <> 'null'::jsonb
      and jsonb_array_length(r_editor -> 'crd') = 1,
      'detail','EDITOR recebe exatamente o mesmo que o VIEWER: cabeçalho, galeria, fichário, páginas, imagens, capa, posições e lista (exceto role)');
    j := public.get_shared_collection(v_co);
    res := res || jsonb_build_object('id','3.3','ok', j ->> 'access' = 'VIEWER' and j ->> 'role' = 'EDITOR' and j ->> 'membership_id' = m_b::text,
      'detail','EDITOR: access continua VIEWER (rotas compartilhadas intactas), role EDITOR');
    j := public.get_collections_shared_with_me();
    res := res || jsonb_build_object('id','3.4','ok', jsonb_array_length(j) = 1 and j -> 0 ->> 'role' = 'EDITOR' and j -> 0 ->> 'collection_id' = v_co::text,
      'detail','"Compartilhadas com você" mostra o papel EDITOR');
    execute 'reset role';
    res := res || jsonb_build_object('id','3.5','ok',
      public.collection_share_role(v_co) = 'VIEWER' and public.collection_member_role(v_co) = 'EDITOR'
      and public.collection_share_role(v_cx) is null and public.collection_member_role(v_cx) is null,
      'detail','nível de leitura (5302) = VIEWER; papel real (5367) = EDITOR; outra coleção do titular → NULL nos dois');
    perform pg_temp.wh_5888_claims(u_a);
    res := res || jsonb_build_object('id','3.6','ok', public.collection_member_role(v_co) = 'OWNER' and public.collection_share_role(v_co) = 'OWNER',
      'detail','titular: OWNER nos dois');
    perform pg_temp.wh_5888_claims(u_c);
    res := res || jsonb_build_object('id','3.7','ok', public.collection_member_role(v_co) is null and public.collection_member_role(v_cx) is null,
      'detail','estranho em CO e convidado PENDING em CX → NULL');
    perform pg_temp.wh_5888_claims(u_d);
    res := res || jsonb_build_object('id','3.8','ok', public.collection_member_role(v_co) is null and public.collection_share_role(v_co) is null,
      'detail','convite EDITOR ainda PENDING não dá papel nem leitura');
    perform pg_temp.wh_5888_claims(null);
    update public.collection set visibility = 'PUBLIC' where id = v_co;
    res := res || jsonb_build_object('id','3.9','ok', public.collection_member_role(v_co) is null and public.collection_share_role(v_co) = 'PUBLIC',
      'detail','sem sessão em coleção PUBLIC: papel NULL (PUBLIC não é papel)');
    update public.collection set visibility = 'PRIVATE' where id = v_co;

    -- 4. Troca de papel --------------------------------------------------------------------
    perform pg_temp.wh_5888_as(u_a);
    j := public.set_collection_member_role(v_co, m_b, 'EDITOR');
    res := res || jsonb_build_object('id','4.1','ok', j ->> 'outcome' = 'UNCHANGED' and j ->> 'role' = 'EDITOR',
      'detail','mesmo papel → UNCHANGED (idempotente)');
    j := public.set_collection_member_role(v_co, m_b, ' viewer ');
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    v_chk := (select m.role || '/' || m.status from public.collection_membership m where m.id = m_b);  -- E1E
    perform pg_temp.wh_5888_as(u_a);  -- E1E: volta ao mesmo cliente
    res := res || jsonb_build_object('id','4.2','ok', j ->> 'outcome' = 'CHANGED' and j ->> 'previous_role' = 'EDITOR' and j ->> 'role' = 'VIEWER'
      and v_chk = 'VIEWER/ACTIVE',  -- E1E
      'detail','EDITOR → VIEWER (normalizado), continua ACTIVE');
    perform pg_temp.wh_5888_as(u_b);
    res := res || jsonb_build_object('id','4.3','ok', public.get_shared_collection(v_co) ->> 'role' = 'VIEWER',
      'detail','efeito imediato: a leitura seguinte do membro já vê VIEWER');
    perform pg_temp.wh_5888_as(u_a);
    j := public.set_collection_member_role(v_co, m_b, 'EDITOR');
    res := res || jsonb_build_object('id','4.4','ok', j ->> 'outcome' = 'CHANGED' and j ->> 'previous_role' = 'VIEWER',
      'detail','VIEWER → EDITOR');
    v_ok := true;
    foreach v_err in array array['OWNER','PUBLIC','x'] loop
      j2 := null;
      begin j2 := public.set_collection_member_role(v_co, m_b, v_err); exception when others then j2 := jsonb_build_object('e', sqlerrm); end;
      v_ok := v_ok and coalesce(j2 ->> 'e' = 'INVALID_ROLE', false);
    end loop;
    v_err := null; begin perform public.set_collection_member_role(v_co, m_b, null); exception when others then v_err := sqlerrm; end;
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    v_chk := (select m.role from public.collection_membership m where m.id = m_b);  -- E1E
    v_chkb := (select c.owner_user_id from public.collection c where c.id = v_co) = u_a;  -- E1E
    perform pg_temp.wh_5888_as(u_a);  -- E1E: volta ao mesmo cliente
    res := res || jsonb_build_object('id','4.5','ok', v_ok and v_err = 'INVALID_ROLE'
      and v_chk = 'EDITOR'  -- E1E
      and v_chkb,  -- E1E
      'detail','OWNER/PUBLIC/inválido/NULL → INVALID_ROLE; papel e titularidade intactos');
    v_err := null; begin perform public.set_collection_member_role(v_cx, m_b, 'VIEWER'); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','4.6','ok', v_err = 'MEMBERSHIP_NOT_FOUND',
      'detail','participação de outra coleção do mesmo titular (ids cruzados) → MEMBERSHIP_NOT_FOUND');
    v_err := null; begin perform public.set_collection_member_role(v_co, gen_random_uuid(), 'VIEWER'); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','4.7','ok', v_err = 'MEMBERSHIP_NOT_FOUND',
      'detail','participação inexistente → MEMBERSHIP_NOT_FOUND');
    v_err := null; begin perform public.invite_collection_member(v_co, n_b, 'VIEWER'); exception when others then v_err := sqlerrm; end;
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    v_chk := (select m.role from public.collection_membership m where m.id = m_b);  -- E1E
    perform pg_temp.wh_5888_as(u_a);  -- E1E: volta ao mesmo cliente
    res := res || jsonb_build_object('id','4.8','ok', v_err = 'ALREADY_MEMBER'
      and v_chk = 'EDITOR',  -- E1E
      'detail','convidar membro ativo com outro papel → ALREADY_MEMBER (troca só pela 5370)');

    -- 5. Segurança -------------------------------------------------------------------------
    perform pg_temp.wh_5888_as(u_b);   -- B é EDITOR de CO
    v_err := null; begin perform public.set_collection_member_role(v_co, m_b, 'VIEWER'); exception when others then v_err := sqlerrm; end;
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    v_chk := (select m.role from public.collection_membership m where m.id = m_b);  -- E1E
    perform pg_temp.wh_5888_as(u_b);  -- E1E: volta ao mesmo cliente
    res := res || jsonb_build_object('id','5.1','ok', v_err = 'MEMBERSHIP_NOT_FOUND'
      and v_chk = 'EDITOR',  -- E1E
      'detail','membro não altera o próprio papel');
    v_err := null; begin perform public.set_collection_member_role(v_co, m_d, 'VIEWER'); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','5.2','ok', v_err = 'MEMBERSHIP_NOT_FOUND',
      'detail','EDITOR não altera papel de outro participante');
    v_err := null; begin perform public.invite_collection_member(v_co, n_c, 'EDITOR'); exception when others then v_err := sqlerrm; end;
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    v_chkb := not exists (select 1 from public.collection_membership m where m.collection_id = v_co and m.user_id = u_c);  -- E1E
    perform pg_temp.wh_5888_as(u_b);  -- E1E: volta ao mesmo cliente
    res := res || jsonb_build_object('id','5.3','ok', v_err = 'COLLECTION_NOT_FOUND'
      and v_chkb,  -- E1E
      'detail','EDITOR não convida (C-154)');
    j := public.get_shared_collection(v_co);
    j2 := public.get_my_collection_sharing(v_co);
    res := res || jsonb_build_object('id','5.4','ok', j2 is null
      and not exists (select 1 from jsonb_object_keys(j) k where k <> all (hdr_allowed)),
      'detail','EDITOR não lê o painel do titular (papéis de outros membros); cabeçalho só com chaves do contrato + role');
    perform pg_temp.wh_5888_as(u_c);
    v_err := null; begin perform public.set_collection_member_role(v_co, m_b, 'VIEWER'); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','5.5','ok', v_err = 'MEMBERSHIP_NOT_FOUND',
      'detail','estranho → MEMBERSHIP_NOT_FOUND (não enumera)');
    perform pg_temp.wh_5888_as(null);
    v_err := null; begin perform public.set_collection_member_role(v_co, m_b, 'VIEWER'); exception when others then v_err := sqlstate; end;
    n := 0; begin perform public.invite_collection_member(v_co, n_c, 'EDITOR'); exception when others then if sqlstate = '42501' then n := 1; end if; end;
    res := res || jsonb_build_object('id','5.6','ok', v_err = '42501' and n = 1,
      'detail','anon sem EXECUTE na troca de papel e no convite');
    -- D recusa o convite EDITOR; titular reconvida como VIEWER → id novo; id antigo morto.
    perform pg_temp.wh_5888_as(u_d);
    perform public.respond_collection_invite(m_d, false);
    perform pg_temp.wh_5888_as(u_a);
    v_err := null; begin perform public.set_collection_member_role(v_co, m_d, 'VIEWER'); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','5.7','ok', v_err = 'MEMBER_NOT_ACTIVE',
      'detail','participação recusada não troca de papel');
    j := public.invite_collection_member(v_co, n_d, 'VIEWER');
    m_d2 := (j ->> 'membership_id')::uuid;
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    v_chkb := not exists (select 1 from public.collection_membership m where m.id = m_d);  -- E1E
    perform pg_temp.wh_5888_as(u_a);  -- E1E: volta ao mesmo cliente
    res := res || jsonb_build_object('id','5.8','ok', j ->> 'outcome' = 'REINVITED' and j ->> 'role' = 'VIEWER' and m_d2 <> m_d
      and v_chkb,  -- E1E
      'detail','recusado + outro papel → convite novo com id novo; linha antiga apagada');
    perform pg_temp.wh_5888_as(u_d);
    v_err := null; begin perform public.respond_collection_invite(m_d, true); exception when others then v_err := sqlerrm; end;
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    v_chk := (select m.status from public.collection_membership m where m.id = m_d2);  -- E1E
    perform pg_temp.wh_5888_as(u_d);  -- E1E: volta ao mesmo cliente
    res := res || jsonb_build_object('id','5.9','ok', v_err = 'INVITE_NOT_FOUND'
      and v_chk = 'PENDING',  -- E1E
      'detail','aba antiga não aceita o id anterior (papel não visto)');
    perform public.respond_collection_invite(m_d2, false);
    perform pg_temp.wh_5888_as(u_a);
    j := public.invite_collection_member(v_co, n_d, 'VIEWER');
    res := res || jsonb_build_object('id','5.10','ok', j ->> 'outcome' = 'REINVITED' and (j ->> 'membership_id')::uuid = m_d2,
      'detail','recusado + mesmo papel → mesma linha (comportamento V1-12)');
    j := public.remove_collection_member(v_co, m_b);
    v_err := null; begin perform public.set_collection_member_role(v_co, m_b, 'VIEWER'); exception when others then v_err := sqlerrm; end;
    perform pg_temp.wh_5888_as(u_b);
    res := res || jsonb_build_object('id','5.11','ok', v_err = 'MEMBERSHIP_NOT_FOUND' and public.get_shared_collection(v_co) is null
      and jsonb_array_length(public.get_collections_shared_with_me()) = 0,
      'detail','EDITOR removido: sem papel, sem leitura, sem troca');
    perform pg_temp.wh_5888_as(u_a);
    m_b := (public.invite_collection_member(v_co, n_b, 'EDITOR') ->> 'membership_id')::uuid;
    perform pg_temp.wh_5888_as(u_b);
    perform public.respond_collection_invite(m_b, true);
    j := public.leave_shared_collection(v_co);
    execute 'reset role';
    res := res || jsonb_build_object('id','5.12','ok', j ->> 'outcome' = 'LEFT' and public.collection_member_role(v_co) is null
      and not exists (select 1 from public.collection_membership m where m.id = m_b),
      'detail','EDITOR que saiu: sem papel na hora');

    -- 6. Privacidade das chaves --------------------------------------------------------------
    perform pg_temp.wh_5888_as(u_a);
    j := public.invite_collection_member(v_co, n_b, 'EDITOR');
    m_b := (j ->> 'membership_id')::uuid;
    res := res || jsonb_build_object('id','6.1','ok',
      not exists (select 1 from jsonb_object_keys(j) k where k <> all (inv_allowed)),
      'detail','retorno do convite: só outcome, membership_id, username, display_name, status, role');
    j := public.get_my_collection_sharing(v_co);
    res := res || jsonb_build_object('id','6.2','ok',
      exists (select 1 from jsonb_array_elements(j -> 'members') e where e ->> 'membership_id' = m_b::text and e ->> 'role' = 'EDITOR'),
      'detail','painel do titular (5308, inalterada) mostra o papel EDITOR');
    perform pg_temp.wh_5888_as(u_b);
    perform public.respond_collection_invite(m_b, true);
    j := public.get_collections_shared_with_me();
    res := res || jsonb_build_object('id','6.3','ok',
      not exists (select 1 from jsonb_array_elements(j) e, jsonb_object_keys(e) k where k <> all (swm_allowed)),
      'detail','"Compartilhadas com você": chaves do contrato V1-12 + role');
    j := public.get_shared_collection(v_co);
    res := res || jsonb_build_object('id','6.4','ok',
      j::text !~* '(@example\.invalid|wh888[a-d]_)' and strpos(j::text, u_a::text) = 0 and strpos(j::text, u_d::text) = 0,
      'detail','cabeçalho do EDITOR sem e-mail, username ou id de titular e de outros participantes');

    -- 7. Sem escrita na E1-A ------------------------------------------------------------------
    v_err := null; begin perform public.update_collection_metadata(v_co, 'Renomeada', null); exception when others then v_err := 'refused'; end;
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    v_chk := (select c.name from public.collection c where c.id = v_co);  -- E1E
    perform pg_temp.wh_5888_as(u_b);  -- E1E: volta ao mesmo cliente
    res := res || jsonb_build_object('id','7.1','ok', v_err = 'refused'
      and v_chk = 'CO 5888',  -- E1E
      'detail','EDITOR não edita metadados nesta etapa');
    v_err := null; begin perform public.set_collection_visibility(v_co, 'PUBLIC'); exception when others then v_err := 'refused'; end;
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    v_chk := (select c.visibility::text from public.collection c where c.id = v_co);  -- E1E
    perform pg_temp.wh_5888_as(u_b);  -- E1E: volta ao mesmo cliente
    res := res || jsonb_build_object('id','7.2','ok', v_err = 'refused'
      and v_chk = 'PRIVATE',  -- E1E
      'detail','EDITOR não altera visibilidade');
    v_err := null; begin perform public.remove_collection_member(v_co, m_b); exception when others then v_err := 'refused'; end;
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    v_chkb := exists (select 1 from public.collection_membership m where m.id = m_b);  -- E1E
    perform pg_temp.wh_5888_as(u_b);  -- E1E: volta ao mesmo cliente
    res := res || jsonb_build_object('id','7.3','ok', v_err = 'refused'
      and v_chkb,  -- E1E
      'detail','EDITOR não remove participações por esse caminho');
    v_err := null; begin perform count(*) from public.collection_membership; exception when others then v_err := sqlstate; end;
    res := res || jsonb_build_object('id','7.4','ok', v_err = '42501',
      'detail','EDITOR sem acesso direto à tabela de participações');

    execute 'reset role';
    raise exception 'MS888' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MS888' then
      res := res || jsonb_build_object('id','X.1','ok', false, 'detail','erro inesperado: '||sqlstate||' '||sqlerrm);
    end if;
  end;

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.collection_membership), (select count(*) from public.card)]
    into e_counts;
  res := res || jsonb_build_object('id','99.1','ok', b_counts = e_counts and current_user = session_user,
    'detail','resíduo zero (6 contagens) e papel restaurado');

  for r in select * from jsonb_array_elements(res) loop
    cnt := cnt + 1;
    if coalesce((r ->> 'ok')::boolean, false) then passes := passes + 1; end if;
    seq := cnt; check_id := r ->> 'id';
    status := case when coalesce((r ->> 'ok')::boolean, false) then 'PASS' else 'FAIL' end;
    detail := r ->> 'detail';
    return next;
  end loop;
  seq := cnt + 1; check_id := 'GATE';
  status := case when passes = cnt and cnt = v_expected then 'PASS' else 'FAIL' end;
  detail := passes || '/' || cnt || ' PASS (esperado ' || v_expected || ')';
  return next;
end;
$fn$;
insert into pg_temp.g2_evidence (harness, seq, check_id, status, detail)
  select '5888', seq, check_id, status, detail from pg_temp.wh_5888_validate();

-- @@T8 modo da barreira CLOSED (só nesta transação)
update public.v1_13_barrier_state set mode = 'CLOSED', change_note = 'G2 ensaio' where id = 1;

-- @@T9 postcheck
do $t9post$
begin
  if (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'CLOSED'
     or exists (select 1 from public.v1_13_barrier_identity) then
    raise exception 'G2 T9: barreira não voltou a CLOSED com registro vazio';
  end if;
  if (select count(*) from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
         and p.proname in ('collection_cover_editor_can_upload', 'collection_cover_editor_folder_ok', 'editor_add_binder_page', 'editor_apply_binder_auto_arrange', 'editor_apply_binder_catalog_reconciliation', 'editor_apply_binder_species_references', 'editor_clear_binder_reservation', 'editor_clear_binder_species_references', 'editor_clear_pokedex_position_primary_representative', 'editor_close_binder_gap', 'editor_insert_binder_gap', 'editor_move_binder_card', 'editor_place_card_in_binder', 'editor_preview_binder_auto_arrange', 'editor_preview_binder_catalog_reconciliation', 'editor_preview_binder_insert_gap', 'editor_preview_binder_species_references', 'editor_remove_binder_card', 'editor_remove_binder_page', 'editor_remove_pokedex_position_assignment', 'editor_reorder_binder_pages', 'editor_set_binder_lock', 'editor_set_binder_reservation', 'editor_set_binder_species_reference_visibility', 'editor_set_collection_cover_code', 'editor_set_collection_cover_finish', 'editor_set_collection_cover_logo', 'editor_set_pokedex_position_assignment', 'editor_set_pokedex_position_primary_representative', 'editor_update_collection_metadata', 'get_shared_binder_activity', 'get_shared_binder_activity_status', 'get_shared_binder_placeable_cards', 'get_shared_master_set_positions', 'get_shared_pokedex_positions', 'invite_collection_member', 'set_collection_member_role') and position('public.v1_13_' in p.prosrc) = 0) > 0 then
    raise exception 'G2 T9: capacidade exposta sem porta';
  end if;
  if current_user <> session_user then
    raise exception 'G2 T9: papel não restaurado';
  end if;
end;
$t9post$;

-- @@T9 sentinela
do $t9sentinel$
declare
  v_total integer; v_passes integer; v_gates jsonb; v_failed jsonb; v_fixture jsonb;
  v_trap boolean; v_ms numeric; v_ok boolean; v_code text; v_msg text;
begin
  select count(*) filter (where check_id <> 'GATE'),
         count(*) filter (where check_id <> 'GATE' and status = 'PASS'),
         coalesce(jsonb_object_agg(harness, status) filter (where check_id = 'GATE'), '{}'::jsonb),
         coalesce(jsonb_agg(harness || ':' || check_id order by harness, seq) filter (where check_id <> 'GATE' and status <> 'PASS'), '[]'::jsonb),
         coalesce(jsonb_agg(harness || ':' || detail order by harness, seq) filter (where check_id in ('F.1', 'X.1')), '[]'::jsonb)
    into v_total, v_passes, v_gates, v_failed, v_fixture
  from pg_temp.g2_evidence;
  v_trap := (select count(*) from pg_temp.g2_trap_child) = 1;
  v_ms := round(extract(epoch from (pg_catalog.clock_timestamp()
           - (select (v #>> '{}')::timestamptz from pg_temp.g2_meta where k = 't_start'))) * 1000);
  v_ok := coalesce(v_total = 105 and v_passes = 105 and v_trap and v_ms <= 20000
                   and (select count(*) from jsonb_each_text(v_gates) g where g.value = 'PASS') = 2, false);
  v_code := case when v_ok then 'E2AOK' else 'E2ANO' end;
  v_msg := 'MS_G2A ' || case when v_ok then 'APROVADO ' else 'REPROVADO ' end || jsonb_build_object(
    'ok', v_ok, 'total', v_total, 'passes', v_passes, 'gates', v_gates, 'failed', v_failed,
    'erro_na_fixture', v_fixture, 'trap_intact', v_trap, 'duration_ms', v_ms,
    'locks', (select coalesce(jsonb_object_agg(k, v), '{}'::jsonb) from pg_temp.g2_meta where k like 't_lock%'),
    'server_version_num', (select v from pg_temp.g2_meta where k = 'server_version_num'),
    'txid', pg_catalog.txid_current_if_assigned())::text;
  raise exception using message = v_msg, errcode = v_code;
end;
$t9sentinel$;

-- @@T10 fora do contrato
ROLLBACK;

-- @@T11 fora do contrato
RESET default_transaction_read_only;
