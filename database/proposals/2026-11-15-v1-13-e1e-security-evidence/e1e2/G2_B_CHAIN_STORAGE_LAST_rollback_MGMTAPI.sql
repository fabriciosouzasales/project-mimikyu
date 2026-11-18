/*
================================================================
Projeto.....: Project Mimikyu
Arquivo.....: G2_B_CHAIN_STORAGE_LAST_rollback_MGMTAPI.sql — ensaio G2 (cadeia protegida completa, 5377 por último)
Status......: GERADO por e1e2/build_g2_chain.py — NÃO EDITAR À MÃO. NÃO EXECUTADO.
              EXECUÇÃO BLOQUEADA até: S0 ampliada (S0_G2_readonly.sql) executada e
              aprovada; revisão independente; autorização expressa e específica do
              proprietário (hash, executor, canal, janela). 5888–5894 rodam ANTES da 5377 (independência por argumento estático); 5863/5890/5895 no estado final.
              Mecanismo da barreira (G1) não homologado; G2 não iniciado.
Canal.......: Supabase Management API (MCP execute_sql) — UMA chamada com o texto
              INTEGRAL, sem dividir nem acrescentar instruções. Variante de canal de G2_B_CHAIN_STORAGE_LAST_rollback.sql
              (blocos funcionais idênticos; só a moldura muda): protocolo simples = UMA
              transação IMPLÍCITA (prova G2A-PROOF-01 PASS). Sem metacomandos do psql, sem
              BEGIN (T1), ROLLBACK (T10), RESET (T11) nem SET SESSION (T0). Trava de COMMIT
              (T4) faz falhar qualquer confirmação implícita; LOCK NOWAIT antes do DDL (T6);
              sentinela que SEMPRE aborta (T9) com SQLSTATE E2BOK/E2BNO; ausência de
              persistência conferida depois por txid_status(<txid da sentinela>) = aborted.
Sequência...: 5389 → 5366 → 5367 → 5368 → 5369 → 5370 → 5371 → 5372 → 5373 → 5374 → 5375 → 5376 → 5378 → 5379 → 5380 → 5381 → 5382 → 5383 → 5384 → 5385 → 5386 → 5387 → 5323 → 5324 → 5388 → 5377
Harnesses...: 5861[CLOSED], 5862[CLOSED], 5864[CLOSED], 5888[OPEN], 5889[OPEN], 5891[OPEN], 5892[OPEN], 5893[OPEN], 5894[OPEN], 5863[CLOSED], 5890[OPEN], 5895[CLOSED]
Total.......: 417 verificações (soma dos GATEs esperados)
Limites.....: statement_timeout 60s; lock_timeout 2s (cada migration redefine 5s);
              idle_in_transaction 15s; transaction_timeout 300s só se PG >= 17;
              aprovado só com duração <= 240000 ms (limite proposto, não medição).
Provas......: só o banco (SET LOCAL ROLE); JWT real, PostgREST, Storage pela API,
              concorrência e medições ficam para G3/G4.
Fontes......: 5389@b8c60c6c425f2110, 5366@bc1ff1109fee3a6c, 5367@92c8b4d71e96245c, 5368@27dff7273fbbaed0, 5369@0a9c4844f35128cb, 5370@c0df38050a8bff24, 5371@b2a09041e5778fe3, 5372@ff9d9c80607717db, 5373@0fd5e30dc914ac0c, 5374@250747ce33af34b0, 5375@2cf3a8d26bae2b72, 5376@8cae24afc9232d33, 5378@828fa3d54543c31e, 5379@7eed93c01db7ab5a, 5380@5b9a1a09a51c9f47, 5381@f48421892a73d4ce, 5382@57799a0a86f6a9de, 5383@b7c5d9c51fd03c88, 5384@9b944466cb7c7eca, 5385@ec7c3150cad646a4, 5386@439fa23e23b5966c, 5387@d601b8f99c2423ab, 5323@3d4bac2223d54309, 5324@41134dfc643d89e7, 5388@e0600cf31ad8783b, 5377@badd1f543f3436c6, H5861@d086fa66375253d5, H5862@f6f7dd4e6c3184a8, H5864@47e96959e15447dc, H5888@50aa49beb5c06d0c, H5889@7502a8eb7a9ed69f, H5891@74c9c1fb26da4833, H5892@f5ad58f5e4eb33ee, H5893@798ceb753c22cc68, H5894@31c76996533d7b3e, H5863@ab3444f64d3e9b60, H5890@0cb84f973d22995b, H5895@f7025b7a609912e4
================================================================
*/

-- [MGMTAPI] T0/T1 omitidos: o texto inteiro é UMA transação implícita (sem BEGIN, sem SET SESSION).

-- @@T2 esta transação escreve
SET TRANSACTION READ WRITE;

-- @@T3 limites
SET LOCAL lock_timeout = '2s';
SET LOCAL statement_timeout = '60s';
SET LOCAL idle_in_transaction_session_timeout = '15s';
do $t3$
begin
  if pg_catalog.current_setting('server_version_num')::int < 140000 then
    raise exception 'G2 T3: PostgreSQL < 14 — ensaio RECUSADO';
  end if;
  perform pg_catalog.set_config('client_connection_check_interval', '1s', true);
  if pg_catalog.current_setting('server_version_num')::int >= 170000 then
    perform pg_catalog.set_config('transaction_timeout', '300s', true);
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
  -- [MGMTAPI] default_transaction_read_only não exigido: sem T0; transação implícita única (G2A-PROOF-01).
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
  where e.evtenabled <> 'D' and p.prosrc ~* '(net\.|http_|pg_net|dblink)'
    -- [MGMTAPI] exceção única: gatilho padrão do Supabase, só em CREATE EXTENSION (o ensaio não cria extensão)
    and (e.evtname = 'issue_pg_net_access' and e.evtevent = 'ddl_command_end'
             and e.evttags = array['CREATE EXTENSION']::text[]
             and p.proname = 'grant_pg_net_access'
             and (select x.nspname from pg_catalog.pg_namespace x where x.oid = p.pronamespace) = 'extensions') is not true;
  if jsonb_array_length(v_evt) > 0 then
    raise exception 'G2 T6: gatilho de evento com possível efeito externo: % — RECUSAR', v_evt;
  end if;
  select count(*) into v_long
  from pg_catalog.pg_locks l
  join pg_catalog.pg_stat_activity a on a.pid = l.pid
  where l.relation in (to_regclass('public.collection_membership'), to_regclass('public.binder_activity_event'), to_regclass('public.binder_activity_item'), to_regclass('storage.objects'))
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

-- @@T6 lock imediato ou recusa (NOWAIT): public.binder_activity_event
LOCK TABLE public.binder_activity_event IN ACCESS EXCLUSIVE MODE NOWAIT;
insert into pg_temp.g2_meta (k, v) values ('t_lock_bae', to_jsonb(pg_catalog.clock_timestamp()));

-- @@T6 lock imediato ou recusa (NOWAIT): public.binder_activity_item
LOCK TABLE public.binder_activity_item IN ACCESS EXCLUSIVE MODE NOWAIT;
insert into pg_temp.g2_meta (k, v) values ('t_lock_bai', to_jsonb(pg_catalog.clock_timestamp()));

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

-- @@T7 5371 (auditada) sha256=b2a09041e5778fe33a358b4dcf3aaea06adbde970753b8abe4ecf5a888cce107
set local lock_timeout = '5s';

do $pre$
begin
  if (select pg_catalog.pg_get_constraintdef(k.oid) from pg_catalog.pg_constraint k
       where k.conrelid = 'public.collection_membership'::regclass
         and k.conname = 'chk_collection_membership_role')
     is distinct from 'CHECK ((role = ANY (ARRAY[''VIEWER''::text, ''EDITOR''::text])))' then
    raise exception 'PRECHECK 5371: E1-A (5366) não aplicada';
  end if;
  if to_regprocedure('public.assert_collection_layout_mutable(uuid)') is null
     or to_regclass('public.collection_layout_guest') is null
     or to_regclass('public.collection_layout_slot_image') is null
     or to_regclass('public.collection_layout_region') is null
     or to_regclass('public.collection_layout_slot_species_reference') is null then
    raise exception 'PRECHECK 5371: ESTADO DIVERGENTE — objetos do fichário ausentes';
  end if;
  -- md5 da 5122 já conferido no LIVE em 2026-10-23 (P2 LIVE_00, item 5122).
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.assert_collection_layout_mutable(uuid)'))
     is distinct from 'd600f36fade0b67c0fd5af33e9965070' then
    raise exception 'PRECHECK 5371: ESTADO DIVERGENTE — 5122 difere da canônica';
  end if;
  if exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public'
               and p.proname in ('assert_collection_binder_editor', 'binder_slot_editor_scope', 'binder_slot_at')) then
    raise exception 'PRECHECK 5371: funções já existem — JÁ APLICADA ou ESTADO DIVERGENTE (conferir 5889 seção 0)';
  end if;
end;
$pre$;

-- 1 -----------------------------------------------------------------------------------------
create function public.assert_collection_binder_editor(p_collection_id uuid)
returns table (layout_id uuid, anchor_collection_id uuid, owner_user_id uuid, container_id uuid)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_uid       uuid := (select auth.uid());
  v_owner     uuid;
  v_layout    uuid;
  v_anchor    uuid;
  v_container uuid;
  v_status    text;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  -- 1. Sem trava: X existe e o usuário é EDITOR ACTIVE dela. Titular nunca tem
  --    participação (C-141/C-156) e cai aqui também.
  select c.owner_user_id into v_owner
  from public.collection c
  join public.collection_membership m
    on m.collection_id = c.id and m.user_id = v_uid and m.status = 'ACTIVE' and m.role = 'EDITOR'
  where c.id = p_collection_id
    and c.owner_user_id <> v_uid;
  if v_owner is null then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- 2. Fichário de que X participa (proprietária ou convidada).
  select l.id, l.collection_id into v_layout, v_anchor
  from public.collection_layout l where l.collection_id = p_collection_id;
  if v_layout is null then
    select g.layout_id, l.collection_id into v_layout, v_anchor
    from public.collection_layout_guest g
    join public.collection_layout l on l.id = g.layout_id
    where g.collection_id = p_collection_id;
  end if;
  if v_layout is null then
    raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- 3. Proprietária (FOR UPDATE), do MESMO titular — mesma trava da 5122.
  select c.lifecycle_status into v_status
  from public.collection c
  where c.id = v_anchor and c.owner_user_id = v_owner
  for update;
  if not found then
    raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_status <> 'ACTIVE' then
    raise exception 'COLLECTION_ARCHIVED' using errcode = '55000';
  end if;

  -- 4. Layout (FOR UPDATE), ainda da proprietária.
  select l.storage_container_id into v_container
  from public.collection_layout l
  where l.id = v_layout and l.collection_id = v_anchor
  for update;
  if not found then
    raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- 5. X convidada (FOR SHARE) depois da proprietária e do layout (ordem da 5272).
  if p_collection_id <> v_anchor then
    select c.lifecycle_status into v_status
    from public.collection c
    where c.id = p_collection_id and c.owner_user_id = v_owner
    for share;
    if not found then
      raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
    end if;
    if v_status <> 'ACTIVE' then
      raise exception 'COLLECTION_ARCHIVED' using errcode = '55000';
    end if;
    if not exists (select 1 from public.collection_layout_guest g
                   where g.layout_id = v_layout and g.collection_id = p_collection_id) then
      raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
    end if;
  end if;

  -- 6. Participação (FOR SHARE), por último; papel e estado relidos sob a trava.
  perform 1
  from public.collection_membership m
  where m.collection_id = p_collection_id and m.user_id = v_uid
    and m.status = 'ACTIVE' and m.role = 'EDITOR'
  for share;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  return query select v_layout, v_anchor, v_owner, v_container;
end;
$fn$;

-- 2 -----------------------------------------------------------------------------------------
create function public.binder_slot_editor_scope(
  p_layout_id            uuid,
  p_anchor_collection_id uuid,
  p_collection_id        uuid,
  p_slot_id              uuid
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_page    uuid;
  v_row     integer;
  v_col     integer;
  v_locked  boolean;
  v_card    uuid;
  v_card_cl uuid;
  v_res_cl  uuid;
  v_res     boolean;
  v_spc_cl  uuid;
  v_own     boolean := false;
begin
  select s.page_id, s.row_index, s.column_index, s.locked
    into v_page, v_row, v_col, v_locked
  from public.collection_layout_slot s
  join public.collection_layout_page p on p.id = s.page_id
  where s.id = p_slot_id and p.layout_id = p_layout_id;
  if v_page is null then
    return 'FOREIGN';
  end if;

  -- Carta: só é de X se o exemplar estiver alocado a X.
  select a.physical_card_id, ca.collection_id into v_card, v_card_cl
  from public.collection_layout_slot_assignment a
  left join public.collection_allocation ca on ca.physical_card_id = a.physical_card_id
  where a.slot_id = p_slot_id;
  if v_card is not null then
    if v_card_cl is distinct from p_collection_id then
      return 'FOREIGN';
    end if;
    v_own := true;
  end if;

  -- Reserva: sem coleção registrada = da proprietária (C-196).
  select true, coalesce(e.collection_id, p_anchor_collection_id) into v_res, v_res_cl
  from public.collection_layout_slot_expected_content e
  where e.slot_id = p_slot_id;
  if v_res then
    if v_res_cl is distinct from p_collection_id then
      return 'FOREIGN';
    end if;
    v_own := true;
  end if;

  -- Imagem personalizada e região mesclada: sempre do titular / fora da E1-B1.
  if exists (select 1 from public.collection_layout_slot_image i where i.slot_id = p_slot_id) then
    return 'FOREIGN';
  end if;
  if exists (select 1 from public.collection_layout_region r
             where r.page_id = v_page
               and v_row between r.top_row and r.top_row + r.height - 1
               and v_col between r.left_column and r.left_column + r.width - 1) then
    return 'FOREIGN';
  end if;

  -- Referência de espécie: só é de X se registrada para X.
  select sr.collection_id into v_spc_cl
  from public.collection_layout_slot_species_reference sr
  where sr.slot_id = p_slot_id;
  if found then
    if v_spc_cl is distinct from p_collection_id then
      return 'FOREIGN';
    end if;
  end if;

  -- Trava: sem carta nem reserva de X, o bolso fixado é do titular.
  if v_locked and not v_own then
    return 'FOREIGN';
  end if;

  return case when v_own then 'OWN' else 'FREE' end;
end;
$fn$;

-- 3 -----------------------------------------------------------------------------------------
create function public.binder_slot_at(
  p_layout_id    uuid,
  p_page_number  integer,
  p_row_index    integer,
  p_column_index integer
)
returns uuid
language sql
stable
security definer
set search_path = ''
as $fn$
  select s.id
  from public.collection_layout_page p
  join public.collection_layout_slot s on s.page_id = p.id
  where p.layout_id = p_layout_id
    and p.page_number = p_page_number
    and s.row_index = p_row_index
    and s.column_index = p_column_index;
$fn$;

comment on function public.assert_collection_binder_editor(uuid) is
  'V1-13 E1-B1 (5371, interna): autoriza o usuário da sessão como EDITOR ACTIVE da coleção e trava proprietária → layout → convidada → participação. Não amplia a 5122.';
comment on function public.binder_slot_editor_scope(uuid, uuid, uuid, uuid) is
  'V1-13 E1-B1 (5371, interna): classificação C-237 do bolso para a coleção autorizada — OWN | FREE | FOREIGN. Só lê.';
comment on function public.binder_slot_at(uuid, integer, integer, integer) is
  'V1-13 E1-B1 (5371, interna): bolso pela posição visível (página, linha, coluna) do fichário.';

revoke all on function public.assert_collection_binder_editor(uuid) from public, anon, authenticated, service_role;
revoke all on function public.binder_slot_editor_scope(uuid, uuid, uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function public.binder_slot_at(uuid, integer, integer, integer) from public, anon, authenticated, service_role;

do $post$
declare
  f oid;
begin
  foreach f in array array[to_regprocedure('public.assert_collection_binder_editor(uuid)'),
                           to_regprocedure('public.binder_slot_editor_scope(uuid, uuid, uuid, uuid)'),
                           to_regprocedure('public.binder_slot_at(uuid, integer, integer, integer)')] loop
    if f is null
       or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
       or (select p.proconfig from pg_catalog.pg_proc p where p.oid = f) is distinct from array['search_path=""']
       or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not false
       or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false
       or pg_catalog.has_function_privilege('service_role', f, 'EXECUTE') is not false then
      raise exception 'POSTCHECK 5371: função interna fora do estado esperado (%)', f;
    end if;
  end loop;
  -- A 5122 (ajudante do titular) continua exatamente a canônica: nada aqui a amplia.
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.assert_collection_layout_mutable(uuid)'))
     is distinct from 'd600f36fade0b67c0fd5af33e9965070' then
    raise exception 'POSTCHECK 5371: 5122 difere da canônica';
  end if;
end;
$post$;

-- @@T7 5372 (auditada) sha256=ff9d9c80607717db4d4a0eaebde1687e68df42bdefe41e9c3b7e06c13cbe35ba
set local lock_timeout = '5s';

do $pre$
declare
  v_m text := (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
               where p.oid = to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)'));
begin
  if v_m = '59ec5791e514026b7a8340e104d66f30' then
    raise exception 'PRECHECK 5372: JÁ APLICADA — não reaplicar';
  end if;
  if v_m is distinct from '5ac90272cf7bc203e5d2316ea4eba7d4' then
    raise exception 'PRECHECK 5372: ESTADO DIVERGENTE — corpo vigente difere da 5268 canônica (%)', v_m;
  end if;
  if to_regclass('public.collection_membership') is null then
    raise exception 'PRECHECK 5372: E1-A não aplicada';
  end if;
end;
$pre$;

create or replace function public.binder_activity_add_item(
  p_kind            text,
  p_effect          text,
  p_card_id         uuid    default null,
  p_variant_type_id uuid    default null,
  p_from_slot_id    uuid    default null,
  p_to_slot_id      uuid    default null,
  p_from_page       integer default null,
  p_to_page         integer default null,
  p_detail          jsonb   default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_ctx      jsonb := nullif(current_setting('mmkyu.binder_activity_ctx', true), '')::jsonb;
  v_uid      uuid  := (select auth.uid());
  v_layout   uuid;
  v_event    bigint;
  v_n        integer;
  v_cap      bigint;
  v_cap_now  bigint;
  c_repeat_slack constant integer := 600;   -- ≥ 5264 c_row_limit (500) + c_item_limit (100); ≥ 5243 c_row_limit (500)
  v_owner    uuid;
  v_binder   text;
  v_coll     uuid;
  v_collname text;
  f_page int; f_row int; f_col int;
  t_page int; t_row int; t_col int;
  c_name text; c_num text; c_set text; vt_code text; vt_name text;
begin
  if v_ctx is null or (v_ctx ->> 'depth')::integer < 1 then
    raise exception 'binder activity: no open operation' using errcode = 'P0001', hint = 'BINDER_ACTIVITY_NO_CONTEXT';
  end if;
  if v_uid is null then
    raise exception 'binder activity requires an authenticated actor' using errcode = '28000';
  end if;
  v_layout := (v_ctx ->> 'layout')::uuid;
  v_event  := (v_ctx ->> 'event_id')::bigint;
  v_n      := (v_ctx ->> 'n')::integer + 1;
  v_cap    := coalesce((v_ctx ->> 'cap')::bigint, 0);

  -- W1: teto derivado da capacidade + folga de repetição (ver cabeçalho). Calculado no
  -- primeiro item (cap = 0), em todo PAGE_ADDED e quando excedido; guarda o máximo observado.
  if v_n > v_cap or (p_kind = 'PAGE' and p_effect = 'PAGE_ADDED') then
    select count(p.id) * (8::bigint * l.grid_rows * l.grid_columns + 2) + 8 + c_repeat_slack
      into v_cap_now
    from public.collection_layout l
    left join public.collection_layout_page p on p.layout_id = l.id
    where l.id = v_layout
    group by l.grid_rows, l.grid_columns;
    v_cap := greatest(v_cap, coalesce(v_cap_now, 8 + c_repeat_slack));
    if v_n > v_cap then
      raise exception 'binder activity: item limit exceeded (% > %)', v_n, v_cap using errcode = 'P0001',
        hint = 'BINDER_ACTIVITY_ITEM_LIMIT';
    end if;
    v_ctx := jsonb_set(v_ctx, '{cap}', to_jsonb(v_cap));
  end if;

  if v_event is null then
    -- Cabeçalho no primeiro item: titular e nomes copiados agora.
    select c.owner_user_id, coalesce(nullif(l.display_name, ''), c.name)
      into v_owner, v_binder
    from public.collection_layout l
    join public.collection c on c.id = l.collection_id
    where l.id = v_layout;
    if v_owner is null then
      raise exception 'binder activity: binder not found' using errcode = 'P0002', hint = 'BINDER_ACTIVITY_LAYOUT_NOT_FOUND';
    end if;
    v_coll := nullif(v_ctx ->> 'collection', '')::uuid;
    if v_owner <> v_uid then
      -- V1-13 E1-B1 (5372): ator diferente do titular só como EDITOR ACTIVE da coleção
      -- do evento, coleção do mesmo titular e participante deste fichário (C-241).
      -- Defesa em profundidade: a função de escrita já autorizou e travou (5371).
      if v_coll is null
         or not exists (select 1 from public.collection_membership m
                        where m.collection_id = v_coll and m.user_id = v_uid
                          and m.status = 'ACTIVE' and m.role = 'EDITOR')
         or not exists (select 1 from public.collection c
                        where c.id = v_coll and c.owner_user_id = v_owner)
         or not (exists (select 1 from public.collection_layout l
                         where l.id = v_layout and l.collection_id = v_coll)
                 or exists (select 1 from public.collection_layout_guest g
                            where g.layout_id = v_layout and g.collection_id = v_coll)) then
        raise exception 'binder activity: actor is not the binder owner' using errcode = '42501',
          hint = 'BINDER_ACTIVITY_NOT_OWNER';
      end if;
    end if;
    if v_coll is not null then
      select c.name into v_collname from public.collection c where c.id = v_coll and c.owner_user_id = v_owner;
    end if;
    insert into public.binder_activity_event
      (owner_user_id, layout_key, actor_user_id, event_type, source,
       collection_id, collection_name, binder_name, summary)
    values
      (v_owner, v_layout, v_uid, v_ctx ->> 'type', v_ctx ->> 'source',
       case when v_collname is not null then v_coll end, left(v_collname, 200), left(v_binder, 200),
       coalesce(v_ctx -> 'summary', '{}'::jsonb))
    returning id into v_event;
    v_ctx := jsonb_set(v_ctx, '{event_id}', to_jsonb(v_event));
  end if;

  -- Posições copiadas agora (R3); bolso de outro fichário → erro.
  if p_from_slot_id is not null then
    select p.page_number, s.row_index, s.column_index into f_page, f_row, f_col
    from public.collection_layout_slot s join public.collection_layout_page p on p.id = s.page_id
    where s.id = p_from_slot_id and p.layout_id = v_layout;
    if f_page is null then
      raise exception 'binder activity: origin pocket not in binder' using errcode = 'P0001', hint = 'BINDER_ACTIVITY_SLOT';
    end if;
  else
    f_page := p_from_page;
  end if;
  if p_to_slot_id is not null then
    select p.page_number, s.row_index, s.column_index into t_page, t_row, t_col
    from public.collection_layout_slot s join public.collection_layout_page p on p.id = s.page_id
    where s.id = p_to_slot_id and p.layout_id = v_layout;
    if t_page is null then
      raise exception 'binder activity: target pocket not in binder' using errcode = 'P0001', hint = 'BINDER_ACTIVITY_SLOT';
    end if;
  else
    t_page := p_to_page;
  end if;

  -- Cópia da carta e do acabamento.
  if p_card_id is not null then
    select k.name, k.collector_number, cs.code into c_name, c_num, c_set
    from public.card k join public.card_set cs on cs.id = k.card_set_id
    where k.id = p_card_id;
    if c_name is null then
      raise exception 'binder activity: card not found' using errcode = 'P0002', hint = 'BINDER_ACTIVITY_CARD';
    end if;
  end if;
  if p_variant_type_id is not null then
    select t.code, t.name into vt_code, vt_name from public.card_variant_type t where t.id = p_variant_type_id;
  end if;

  insert into public.binder_activity_item
    (event_id, ordinal, item_kind, effect, card_id, card_name, collector_number, card_set_code,
     variant_type_code, variant_type_name, from_page, from_row, from_col, to_page, to_row, to_col, detail)
  values
    (v_event, v_n, p_kind, p_effect, p_card_id, left(c_name, 200), left(c_num, 40), left(c_set, 40),
     left(vt_code, 60), left(vt_name, 120), f_page, f_row, f_col, t_page, t_row, t_col, p_detail);

  v_ctx := jsonb_set(v_ctx, '{n}', to_jsonb(v_n));
  perform set_config('mmkyu.binder_activity_ctx', v_ctx::text, true);
end;
$fn$;

do $post$
declare
  f oid := to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)');
begin
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = f) is distinct from '59ec5791e514026b7a8340e104d66f30'
     or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
     or (select p.proconfig from pg_catalog.pg_proc p where p.oid = f) is distinct from array['search_path=""']
     or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not false
     or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false
     or pg_catalog.has_function_privilege('service_role', f, 'EXECUTE') is not false then
    raise exception 'POSTCHECK 5372: binder_activity_add_item fora do estado esperado';
  end if;
end;
$post$;

-- @@T7 5373 (protegida) sha256=0fd5e30dc914ac0c4d3035814b7cd86966704422b4426fa41a89b7ef69a99ee1
set local lock_timeout = '5s';

do $pre$
begin
  if to_regprocedure('public.v1_13_assert_capability()') is null or to_regprocedure('public.v1_13_capability_open()') is null then raise exception 'PRECHECK G1: barreira 5389 ausente'; end if;  -- G1 (D-E1)
  if (select pg_catalog.pg_get_constraintdef(k.oid) from pg_catalog.pg_constraint k
       where k.conrelid = 'public.collection_membership'::regclass
         and k.conname = 'chk_collection_membership_role')
     is distinct from 'CHECK ((role = ANY (ARRAY[''VIEWER''::text, ''EDITOR''::text])))' then
    raise exception 'PRECHECK 5373: E1-A (5366) não aplicada';
  end if;
  if exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname = 'get_shared_binder_placeable_cards') then
    raise exception 'PRECHECK 5373: função já existe — JÁ APLICADA ou ESTADO DIVERGENTE';
  end if;
end;
$pre$;

create function public.get_shared_binder_placeable_cards(
  p_collection_id uuid,
  p_limit         integer default 96,
  p_offset        integer default 0
)
returns table (
  physical_card_id uuid,
  card_name        text,
  collector_number text,
  collector_total  integer,
  card_set_code    text,
  variant_label    text,
  language_code    text,
  image_path       text,
  total_count      integer
)
language plpgsql
stable
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_uid       uuid := (select auth.uid());
  v_owner     uuid;
  v_layout    uuid;
  v_anchor    uuid;
  v_container uuid;
begin
  if not public.v1_13_capability_open() then return; end if;  -- G1 (D-E1)
  if p_limit is null or p_limit < 1 or p_limit > 96 or p_offset is null or p_offset < 0 or p_offset > 100000 then
    raise exception 'INVALID_PAGE' using errcode = '22023';
  end if;
  if v_uid is null or p_collection_id is null then
    return;
  end if;

  -- EDITOR ACTIVE de X, coleção ativa, de outro titular.
  select c.owner_user_id into v_owner
  from public.collection c
  join public.collection_membership m
    on m.collection_id = c.id and m.user_id = v_uid and m.status = 'ACTIVE' and m.role = 'EDITOR'
  where c.id = p_collection_id
    and c.owner_user_id <> v_uid
    and c.lifecycle_status = 'ACTIVE';
  if v_owner is null then
    return;
  end if;

  select l.id, l.collection_id, l.storage_container_id into v_layout, v_anchor, v_container
  from public.collection_layout l where l.collection_id = p_collection_id;
  if v_layout is null then
    select l.id, l.collection_id, l.storage_container_id into v_layout, v_anchor, v_container
    from public.collection_layout_guest g
    join public.collection_layout l on l.id = g.layout_id
    where g.collection_id = p_collection_id;
  end if;
  if v_layout is null or v_container is null then
    return;
  end if;
  if not exists (select 1 from public.collection c
                 where c.id = v_anchor and c.owner_user_id = v_owner and c.lifecycle_status = 'ACTIVE') then
    return;
  end if;

  return query
  with el as (
    select pc.id as pcid, pc.card_variant_id, pc.language_id
    from public.collection_allocation ca
    join public.physical_card pc on pc.id = ca.physical_card_id
    join public.inventory i      on i.id = pc.inventory_id
    where ca.collection_id = p_collection_id
      and i.owner_user_id = v_owner
      and pc.storage_container_id = v_container
      and not exists (select 1 from public.collection_layout_slot_assignment a where a.physical_card_id = pc.id)
  ),
  tot as (select count(*)::integer as n from el)
  select
    el.pcid,
    c.name::text,
    c.collector_number::text,
    c.collector_total,
    cs.code::text,
    nullif(concat_ws(' · ', vt.name, pp.name, ecx.name), '')::text,
    l.code::text,
    img.storage_path::text,
    tot.n
  from el
  cross join tot
  join public.card_variant cv                       on cv.id = el.card_variant_id
  join public.card c                                on c.id = cv.card_id
  join public.card_set cs                           on cs.id = c.card_set_id
  left join public.card_variant_type vt             on vt.id = cv.variant_type_id
  left join public.card_printing_profile pp         on pp.id = cv.printing_profile_id
  left join public.card_edition_context_profile ecx on ecx.id = cv.edition_context_profile_id
  left join public.language l                       on l.id = el.language_id
  left join lateral (
    select ast.storage_path
    from public.card_asset ast
    join public.card_asset_type cat on cat.id = ast.asset_type_id and cat.code = 'CARD_FRONT'
    join public.language al         on al.id = ast.language_id
    where ast.card_id = c.id
      and ast.is_primary
      and ast.is_active
      and ast.storage_path is not null
    order by (ast.language_id = el.language_id) desc nulls last,
             (al.code = 'pt-BR') desc,
             (al.code = 'en') desc,
             al.language_order asc
    limit 1
  ) img on true
  order by cs.code, c.collector_order, c.collector_number, l.code, el.pcid
  limit p_limit offset p_offset;
end;
$fn$;

comment on function public.get_shared_binder_placeable_cards(uuid, integer, integer) is
  'V1-13 E1-B1 (5373): exemplares que o EDITOR pode colocar no fichário — alocados à coleção, guardados no local do fichário e fora de bolso (C-235/DR-1). Sem local, condição, valores ou acervo. Não EDITOR → zero linhas.';

revoke all on function public.get_shared_binder_placeable_cards(uuid, integer, integer) from public, anon;
grant execute on function public.get_shared_binder_placeable_cards(uuid, integer, integer) to authenticated;

do $post$
declare
  f oid := to_regprocedure('public.get_shared_binder_placeable_cards(uuid, integer, integer)');
begin
  if f is null
     or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
     or (select p.provolatile from pg_catalog.pg_proc p where p.oid = f) is distinct from 's'
     or (select p.proconfig from pg_catalog.pg_proc p where p.oid = f) is distinct from array['search_path=""']
     or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not true
     or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false then
    raise exception 'POSTCHECK 5373: leitura fora do estado esperado';
  end if;
  if exists (select 1 from pg_catalog.pg_proc q, unnest(q.proargnames, q.proargmodes) a(name, mode)
             where q.oid = f and a.mode = 't'
               and a.name ~ '(storage|location|local|condition|price|value|paid|acqui|note|favorite|wish|owner|collection_id|allocation)') then
    raise exception 'POSTCHECK 5373: coluna privada na saída';
  end if;
end;
$post$;

-- @@T7 5374 (protegida) sha256=250747ce33af34b09167a8296262ddbef4d6ada5ebf6d3589b5f1452e568c61b
set local lock_timeout = '5s';

do $pre$
begin
  if to_regprocedure('public.v1_13_assert_capability()') is null or to_regprocedure('public.v1_13_capability_open()') is null then raise exception 'PRECHECK G1: barreira 5389 ausente'; end if;  -- G1 (D-E1)
  if to_regprocedure('public.assert_collection_binder_editor(uuid)') is null
     or to_regprocedure('public.binder_slot_editor_scope(uuid, uuid, uuid, uuid)') is null
     or to_regprocedure('public.binder_slot_at(uuid, integer, integer, integer)') is null then
    raise exception 'PRECHECK 5374: 5371 não aplicada';
  end if;
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)'))
     is distinct from '59ec5791e514026b7a8340e104d66f30' then
    raise exception 'PRECHECK 5374: 5372 não aplicada';
  end if;
  -- Funções do titular: canônicas (md5 conferido no LIVE em 2026-10-27, LIVE_S2_90).
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.place_my_physical_card_in_slot(uuid, uuid, uuid)')) is distinct from '2672da179d73797ec5329c649b594202'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.move_slot_assignment(uuid, uuid)')) is distinct from 'fe149c755b5f3b9181172e600c2238a3'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.remove_slot_assignment(uuid[])')) is distinct from 'e4b6c8cd8e8c61554ddc92304d602a73' then
    raise exception 'PRECHECK 5374: ESTADO DIVERGENTE — funções do titular (5272–5274) diferem das canônicas';
  end if;
  if exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public'
               and p.proname in ('editor_place_card_in_binder', 'editor_move_binder_card', 'editor_remove_binder_card')) then
    raise exception 'PRECHECK 5374: funções já existem — JÁ APLICADA ou ESTADO DIVERGENTE';
  end if;
end;
$pre$;

-- Colocar -------------------------------------------------------------------------------------
create function public.editor_place_card_in_binder(
  p_collection_id    uuid,
  p_page             integer,
  p_row              integer,
  p_column           integer,
  p_physical_card_id uuid
)
returns table (operation text)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $fn$
#variable_conflict use_column
declare
  v_layout    uuid;
  v_anchor    uuid;
  v_owner     uuid;
  v_container uuid;
  v_slot      uuid;
  v_scope     text;
  v_locked    boolean;
  v_card_cont uuid;
  v_here      uuid;
  v_here_slot uuid;
  v_old_asg   uuid;
  v_old_card  uuid;
  v_op        text;
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  if (select auth.uid()) is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null or p_page is null or p_row is null or p_column is null or p_physical_card_id is null
     or p_page < 1 or p_row < 1 or p_column < 1 then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  -- 1. Autorização EDITOR + travas proprietária → layout → convidada → participação.
  select x.layout_id, x.anchor_collection_id, x.owner_user_id, x.container_id
    into v_layout, v_anchor, v_owner, v_container
  from public.assert_collection_binder_editor(p_collection_id) x;

  -- 2. Bolso pela posição, travado; classificação sob a trava.
  v_slot := public.binder_slot_at(v_layout, p_page, p_row, p_column);
  if v_slot is null then
    raise exception 'SLOT_NOT_EDITABLE' using errcode = '42501';
  end if;
  select s.locked into v_locked from public.collection_layout_slot s where s.id = v_slot for update;
  v_scope := public.binder_slot_editor_scope(v_layout, v_anchor, p_collection_id, v_slot);
  if v_scope not in ('OWN', 'FREE') then
    raise exception 'SLOT_NOT_EDITABLE' using errcode = '42501';
  end if;
  if v_locked then
    raise exception 'SLOT_LOCKED' using errcode = '55000';
  end if;

  -- 3. Exemplar elegível (C-235 + DR-1), relido sob trava: do titular, alocado a X,
  --    guardado no local do fichário. Uma só recusa para qualquer falha.
  select pc.storage_container_id into v_card_cont
  from public.physical_card pc
  join public.inventory i            on i.id = pc.inventory_id
  join public.collection_allocation ca on ca.physical_card_id = pc.id
  where pc.id = p_physical_card_id
    and i.owner_user_id = v_owner
    and ca.collection_id = p_collection_id
  for update of pc for share of ca;
  if not found or v_container is null or v_card_cont is distinct from v_container then
    raise exception 'PHYSICAL_CARD_NOT_ELIGIBLE' using errcode = 'P0002';
  end if;

  -- 4. Já posicionado? (igual ao titular)
  select a.id, a.slot_id into v_here, v_here_slot
  from public.collection_layout_slot_assignment a
  where a.physical_card_id = p_physical_card_id
  for update;
  if v_here is not null then
    if v_here_slot = v_slot then
      return query select 'UNCHANGED'::text;
      return;
    end if;
    raise exception 'CARD_ALREADY_PLACED' using errcode = '23505',
      hint = 'o exemplar já está em outro bolso — mova-o em vez de posicioná-lo de novo';
  end if;

  -- 5. Escrita (espelho da 5272): evento com a coleção X; REPLACE só de exemplar de X.
  perform public.binder_activity_begin(v_layout, 'CARD_PLACED', 'FICHARIO', p_collection_id);
  select a.id, a.physical_card_id into v_old_asg, v_old_card
  from public.collection_layout_slot_assignment a
  where a.slot_id = v_slot
  for update;
  if v_old_asg is not null then
    if not exists (select 1 from public.collection_allocation ca
                   where ca.physical_card_id = v_old_card and ca.collection_id = p_collection_id) then
      raise exception 'SLOT_NOT_EDITABLE' using errcode = '42501';
    end if;
    perform public.binder_activity_add_card_item('REMOVED', v_old_card, v_slot, null);
    delete from public.collection_layout_slot_assignment where id = v_old_asg;
    v_op := 'REPLACE';
  else
    v_op := 'ADD';
  end if;

  begin
    insert into public.collection_layout_slot_assignment (slot_id, physical_card_id)
    values (v_slot, p_physical_card_id);
  exception
    when unique_violation then
      raise exception 'CARD_ALREADY_PLACED' using errcode = '23505';
  end;

  perform public.binder_activity_add_card_item('PLACED', p_physical_card_id, null, v_slot);
  return query select v_op;
  perform public.binder_activity_end();
end;
$fn$;

-- Mover / trocar --------------------------------------------------------------------------------
create function public.editor_move_binder_card(
  p_collection_id uuid,
  p_from_page     integer,
  p_from_row      integer,
  p_from_column   integer,
  p_to_page       integer,
  p_to_row        integer,
  p_to_column     integer
)
returns table (operation text)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $fn$
#variable_conflict use_column
declare
  v_layout     uuid;
  v_anchor     uuid;
  v_owner      uuid;
  v_container  uuid;
  v_from       uuid;
  v_to         uuid;
  v_scope_from text;
  v_scope_to   text;
  v_locked     integer;
  v_from_asg   uuid;
  v_from_card  uuid;
  v_to_asg     uuid;
  v_to_card    uuid;
  v_op         text;
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  if (select auth.uid()) is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null or p_from_page is null or p_from_row is null or p_from_column is null
     or p_to_page is null or p_to_row is null or p_to_column is null
     or least(p_from_page, p_from_row, p_from_column, p_to_page, p_to_row, p_to_column) < 1 then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  if (p_from_page, p_from_row, p_from_column) = (p_to_page, p_to_row, p_to_column) then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023', hint = 'origem e destino são o mesmo bolso';
  end if;

  select x.layout_id, x.anchor_collection_id, x.owner_user_id, x.container_id
    into v_layout, v_anchor, v_owner, v_container
  from public.assert_collection_binder_editor(p_collection_id) x;

  v_from := public.binder_slot_at(v_layout, p_from_page, p_from_row, p_from_column);
  v_to   := public.binder_slot_at(v_layout, p_to_page, p_to_row, p_to_column);
  if v_from is null or v_to is null then
    raise exception 'SLOT_NOT_EDITABLE' using errcode = '42501';
  end if;

  -- Bolsos em ordem determinística (igual à 5273), depois classificação sob trava.
  perform 1 from public.collection_layout_slot s
  where s.id in (v_from, v_to) order by s.id for update;
  v_scope_from := public.binder_slot_editor_scope(v_layout, v_anchor, p_collection_id, v_from);
  v_scope_to   := public.binder_slot_editor_scope(v_layout, v_anchor, p_collection_id, v_to);
  if v_scope_from <> 'OWN' or v_scope_to not in ('OWN', 'FREE') then
    raise exception 'SLOT_NOT_EDITABLE' using errcode = '42501';
  end if;
  select count(*) into v_locked from public.collection_layout_slot s where s.id in (v_from, v_to) and s.locked;
  if v_locked > 0 then
    raise exception 'SLOT_LOCKED' using errcode = '55000';
  end if;

  -- Posições envolvidas em ordem determinística (igual à 5273).
  perform 1 from public.collection_layout_slot_assignment a
  where a.slot_id in (v_from, v_to) order by a.id for update;
  select a.id, a.physical_card_id into v_from_asg, v_from_card
  from public.collection_layout_slot_assignment a where a.slot_id = v_from;
  if v_from_asg is null
     or not exists (select 1 from public.collection_allocation ca
                    where ca.physical_card_id = v_from_card and ca.collection_id = p_collection_id) then
    raise exception 'SLOT_EMPTY' using errcode = 'P0002', hint = 'não há carta desta coleção no bolso de origem';
  end if;
  select a.id, a.physical_card_id into v_to_asg, v_to_card
  from public.collection_layout_slot_assignment a where a.slot_id = v_to;
  if v_to_asg is not null
     and not exists (select 1 from public.collection_allocation ca
                     where ca.physical_card_id = v_to_card and ca.collection_id = p_collection_id) then
    raise exception 'SLOT_NOT_EDITABLE' using errcode = '42501';
  end if;

  -- Escrita (espelho da 5273).
  if v_to_asg is not null then
    v_op := 'SWAP';
    update public.collection_layout_slot_assignment set slot_id = v_to   where id = v_from_asg;
    update public.collection_layout_slot_assignment set slot_id = v_from where id = v_to_asg;
  else
    v_op := 'MOVE';
    update public.collection_layout_slot_assignment set slot_id = v_to where id = v_from_asg;
  end if;

  perform public.binder_activity_begin(v_layout, case v_op when 'SWAP' then 'CARDS_SWAPPED' else 'CARD_MOVED' end,
                                       'FICHARIO', p_collection_id);
  perform public.binder_activity_add_card_item(case v_op when 'SWAP' then 'SWAPPED' else 'MOVED' end,
                                               v_from_card, v_from, v_to);
  if v_op = 'SWAP' then
    perform public.binder_activity_add_card_item('SWAPPED', v_to_card, v_to, v_from);
  end if;
  return query select v_op;
  perform public.binder_activity_end();
end;
$fn$;

-- Retirar ----------------------------------------------------------------------------------------
create function public.editor_remove_binder_card(
  p_collection_id uuid,
  p_page          integer,
  p_row           integer,
  p_column        integer
)
returns table (operation text)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $fn$
#variable_conflict use_column
declare
  v_layout    uuid;
  v_anchor    uuid;
  v_owner     uuid;
  v_container uuid;
  v_slot      uuid;
  v_scope     text;
  v_locked    boolean;
  v_asg       uuid;
  v_card      uuid;
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  if (select auth.uid()) is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null or p_page is null or p_row is null or p_column is null
     or p_page < 1 or p_row < 1 or p_column < 1 then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  select x.layout_id, x.anchor_collection_id, x.owner_user_id, x.container_id
    into v_layout, v_anchor, v_owner, v_container
  from public.assert_collection_binder_editor(p_collection_id) x;

  v_slot := public.binder_slot_at(v_layout, p_page, p_row, p_column);
  if v_slot is null then
    raise exception 'SLOT_NOT_EDITABLE' using errcode = '42501';
  end if;
  select s.locked into v_locked from public.collection_layout_slot s where s.id = v_slot for update;
  v_scope := public.binder_slot_editor_scope(v_layout, v_anchor, p_collection_id, v_slot);
  if v_scope <> 'OWN' then
    raise exception 'SLOT_NOT_EDITABLE' using errcode = '42501';
  end if;
  if v_locked then
    raise exception 'SLOT_LOCKED' using errcode = '55000';
  end if;

  select a.id, a.physical_card_id into v_asg, v_card
  from public.collection_layout_slot_assignment a where a.slot_id = v_slot for update;
  if v_asg is null
     or not exists (select 1 from public.collection_allocation ca
                    where ca.physical_card_id = v_card and ca.collection_id = p_collection_id) then
    raise exception 'SLOT_EMPTY' using errcode = 'P0002', hint = 'não há carta desta coleção neste bolso';
  end if;

  -- Escrita (espelho da 5274, um bolso): item antes do DELETE; só a posição sai.
  perform public.binder_activity_begin(v_layout, 'CARDS_REMOVED', 'FICHARIO', p_collection_id);
  perform public.binder_activity_add_card_item('REMOVED', v_card, v_slot, null);
  delete from public.collection_layout_slot_assignment where id = v_asg;
  return query select 'REMOVED'::text;
  perform public.binder_activity_end();
end;
$fn$;

comment on function public.editor_place_card_in_binder(uuid, integer, integer, integer, uuid) is
  'V1-13 E1-B1 (5374): EDITOR coloca no bolso (posição visível) um exemplar alocado à coleção e guardado no fichário (C-235/DR-1). Bolso de terceiros → SLOT_NOT_EDITABLE.';
comment on function public.editor_move_binder_card(uuid, integer, integer, integer, integer, integer, integer) is
  'V1-13 E1-B1 (5374): EDITOR move ou troca cartas da coleção entre bolsos permitidos (C-237).';
comment on function public.editor_remove_binder_card(uuid, integer, integer, integer) is
  'V1-13 E1-B1 (5374): EDITOR retira do bolso uma carta da coleção; alocação, local e acervo intactos (C-236).';

revoke all on function public.editor_place_card_in_binder(uuid, integer, integer, integer, uuid) from public, anon;
revoke all on function public.editor_move_binder_card(uuid, integer, integer, integer, integer, integer, integer) from public, anon;
revoke all on function public.editor_remove_binder_card(uuid, integer, integer, integer) from public, anon;
grant execute on function public.editor_place_card_in_binder(uuid, integer, integer, integer, uuid) to authenticated;
grant execute on function public.editor_move_binder_card(uuid, integer, integer, integer, integer, integer, integer) to authenticated;
grant execute on function public.editor_remove_binder_card(uuid, integer, integer, integer) to authenticated;

do $post$
declare
  f oid;
begin
  foreach f in array array[
      to_regprocedure('public.editor_place_card_in_binder(uuid, integer, integer, integer, uuid)'),
      to_regprocedure('public.editor_move_binder_card(uuid, integer, integer, integer, integer, integer, integer)'),
      to_regprocedure('public.editor_remove_binder_card(uuid, integer, integer, integer)')] loop
    if f is null
       or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
       or not ((select p.proconfig from pg_catalog.pg_proc p where p.oid = f) @> array['search_path=""'])
       or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not true
       or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false then
      raise exception 'POSTCHECK 5374: escrita do EDITOR fora do estado esperado (%)', f;
    end if;
  end loop;
  -- ACL das novas igual à do titular correspondente (paridade, inclusive service_role).
  if (select coalesce(string_agg(a::text, ',' order by a::text), '<NULL>') from pg_catalog.pg_proc p cross join lateral unnest(p.proacl) a
       where p.oid = to_regprocedure('public.editor_place_card_in_binder(uuid, integer, integer, integer, uuid)'))
     is distinct from (select coalesce(string_agg(a::text, ',' order by a::text), '<NULL>') from pg_catalog.pg_proc p cross join lateral unnest(p.proacl) a
       where p.oid = to_regprocedure('public.place_my_physical_card_in_slot(uuid, uuid, uuid)')) then
    raise exception 'POSTCHECK 5374: ACL difere da 5272';
  end if;
  -- Titular intocado.
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.place_my_physical_card_in_slot(uuid, uuid, uuid)')) is distinct from '2672da179d73797ec5329c649b594202'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.move_slot_assignment(uuid, uuid)')) is distinct from 'fe149c755b5f3b9181172e600c2238a3'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.remove_slot_assignment(uuid[])')) is distinct from 'e4b6c8cd8e8c61554ddc92304d602a73' then
    raise exception 'POSTCHECK 5374: funções do titular mudaram';
  end if;
end;
$post$;

-- @@T7 5375 (protegida) sha256=2cf3a8d26bae2b7220779a79b673bf49caa3c4ee8ccfeb42f3ac905af547da2d
set local lock_timeout = '5s';

do $pre$
begin
  if to_regprocedure('public.v1_13_assert_capability()') is null or to_regprocedure('public.v1_13_capability_open()') is null then raise exception 'PRECHECK G1: barreira 5389 ausente'; end if;  -- G1 (D-E1)
  if to_regprocedure('public.assert_collection_binder_editor(uuid)') is null
     or to_regprocedure('public.binder_slot_editor_scope(uuid, uuid, uuid, uuid)') is null
     or to_regprocedure('public.binder_slot_at(uuid, integer, integer, integer)') is null then
    raise exception 'PRECHECK 5375: E1-B1 (5371) não aplicada';
  end if;
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)'))
     is distinct from '59ec5791e514026b7a8340e104d66f30' then
    raise exception 'PRECHECK 5375: E1-B1 (5372) não aplicada';
  end if;
  if to_regprocedure('public.binder_activity_add_reservation_item(text, uuid)') is null then
    raise exception 'PRECHECK 5375: ESTADO DIVERGENTE — 5275 ausente';
  end if;
  -- Funções do titular: canônicas (md5 lido no LIVE em LIVE_S3_90, 2026-10-27).
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.set_slot_expected_content(uuid, uuid, uuid, uuid, uuid)')) is distinct from '33dde5013dbb491bd4a0452ab7ce8132'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.clear_slot_expected_content(uuid[])')) is distinct from '0b8f26825ff713a24226548ffe3a63b7'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.set_slot_lock(uuid[], boolean)')) is distinct from '651048a4bf7d3229904ef2a073c509c5' then
    raise exception 'PRECHECK 5375: ESTADO DIVERGENTE — funções do titular (5276–5278) diferem das canônicas';
  end if;
  if exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public'
               and p.proname in ('editor_set_binder_reservation', 'editor_clear_binder_reservation', 'editor_set_binder_lock')) then
    raise exception 'PRECHECK 5375: funções já existem — JÁ APLICADA ou ESTADO DIVERGENTE';
  end if;
end;
$pre$;

-- Reservar -------------------------------------------------------------------------------------
create function public.editor_set_binder_reservation(
  p_collection_id            uuid,
  p_page                     integer,
  p_row                      integer,
  p_column                   integer,
  p_card_id                  uuid,
  p_card_variant_id          uuid default null,
  p_expected_variant_type_id uuid default null
)
returns table (operation text)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $fn$
#variable_conflict use_column
declare
  v_layout    uuid;
  v_anchor    uuid;
  v_owner     uuid;
  v_container uuid;
  v_slot      uuid;
  v_scope     text;
  v_prev_coll uuid;
  v_had       boolean := false;
  v_same      boolean;
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  if (select auth.uid()) is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null or p_page is null or p_row is null or p_column is null
     or p_page < 1 or p_row < 1 or p_column < 1 then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  if p_card_id is null then
    raise exception 'p_card_id é obrigatório' using errcode = '22023';
  end if;
  if p_card_variant_id is not null and p_expected_variant_type_id is not null then
    raise exception 'EXPECTED_CONTENT_VARIANT_AND_TYPE_EXCLUSIVE: informe a variante específica OU o acabamento, não os dois'
      using errcode = '22023';
  end if;

  select x.layout_id, x.anchor_collection_id, x.owner_user_id, x.container_id
    into v_layout, v_anchor, v_owner, v_container
  from public.assert_collection_binder_editor(p_collection_id) x;

  v_slot := public.binder_slot_at(v_layout, p_page, p_row, p_column);
  if v_slot is null then
    raise exception 'SLOT_NOT_EDITABLE' using errcode = '42501';
  end if;
  perform 1 from public.collection_layout_slot s where s.id = v_slot for update;
  v_scope := public.binder_slot_editor_scope(v_layout, v_anchor, p_collection_id, v_slot);
  if v_scope not in ('OWN', 'FREE') then
    raise exception 'SLOT_NOT_EDITABLE' using errcode = '42501';
  end if;

  -- Reserva existente (já travada pelo bolso): só pode ser de X.
  select true, coalesce(e.collection_id, v_anchor),
         (e.card_id, e.card_variant_id, e.expected_variant_type_id, e.collection_id)
           is not distinct from (p_card_id, p_card_variant_id, p_expected_variant_type_id, p_collection_id)
    into v_had, v_prev_coll, v_same
  from public.collection_layout_slot_expected_content e
  where e.slot_id = v_slot;
  if v_had is true and v_prev_coll is distinct from p_collection_id then   -- SELECT INTO sem linha deixa NULL
    raise exception 'SLOT_NOT_EDITABLE' using errcode = '42501';
  end if;
  if v_had is true and v_same is true then
    return query select 'UNCHANGED'::text;
    return;
  end if;

  -- Escrita (espelho da 5276), sempre registrada para X.
  perform public.binder_activity_begin(v_layout, 'POCKET_RESERVED', 'FICHARIO', p_collection_id);
  if v_had is true then
    perform public.binder_activity_add_reservation_item('RELEASED', v_slot);
  end if;
  begin
    insert into public.collection_layout_slot_expected_content as ec
      (slot_id, card_id, card_variant_id, expected_variant_type_id, collection_id)
    values
      (v_slot, p_card_id, p_card_variant_id, p_expected_variant_type_id, p_collection_id)
    on conflict on constraint collection_layout_slot_expected_content_pkey
    do update set card_id                  = excluded.card_id,
                  card_variant_id          = excluded.card_variant_id,
                  expected_variant_type_id = excluded.expected_variant_type_id,
                  collection_id            = excluded.collection_id;
  exception
    when foreign_key_violation then
      raise exception
        'Card/Card Variant/acabamento inválido — quando informada, a Card Variant deve pertencer à Card indicada e o acabamento deve existir';
  end;
  perform public.binder_activity_add_reservation_item('RESERVED', v_slot);
  return query select case when v_had is true then 'REPLACED' else 'RESERVED' end;
  perform public.binder_activity_end();
end;
$fn$;

-- Liberar reserva ------------------------------------------------------------------------------
create function public.editor_clear_binder_reservation(
  p_collection_id uuid,
  p_page          integer,
  p_row           integer,
  p_column        integer
)
returns table (operation text)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $fn$
#variable_conflict use_column
declare
  v_layout    uuid;
  v_anchor    uuid;
  v_owner     uuid;
  v_container uuid;
  v_slot      uuid;
  v_scope     text;
  v_had       boolean := false;
  v_coll      uuid;
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  if (select auth.uid()) is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null or p_page is null or p_row is null or p_column is null
     or p_page < 1 or p_row < 1 or p_column < 1 then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  select x.layout_id, x.anchor_collection_id, x.owner_user_id, x.container_id
    into v_layout, v_anchor, v_owner, v_container
  from public.assert_collection_binder_editor(p_collection_id) x;

  v_slot := public.binder_slot_at(v_layout, p_page, p_row, p_column);
  if v_slot is null then
    raise exception 'SLOT_NOT_EDITABLE' using errcode = '42501';
  end if;
  perform 1 from public.collection_layout_slot s where s.id = v_slot for update;
  v_scope := public.binder_slot_editor_scope(v_layout, v_anchor, p_collection_id, v_slot);
  if v_scope = 'FREE' then
    return query select 'UNCHANGED'::text;
    return;
  end if;
  if v_scope <> 'OWN' then
    raise exception 'SLOT_NOT_EDITABLE' using errcode = '42501';
  end if;

  select true, coalesce(e.collection_id, v_anchor) into v_had, v_coll
  from public.collection_layout_slot_expected_content e
  where e.slot_id = v_slot;
  if v_had is not true then   -- SELECT INTO sem linha deixa NULL
    return query select 'UNCHANGED'::text;
    return;
  end if;
  if v_coll is distinct from p_collection_id then
    raise exception 'SLOT_NOT_EDITABLE' using errcode = '42501';
  end if;

  -- Escrita (espelho da 5277, um bolso): item antes do DELETE.
  perform public.binder_activity_begin(v_layout, 'RESERVATIONS_RELEASED', 'FICHARIO', p_collection_id);
  perform public.binder_activity_add_reservation_item('RELEASED', v_slot);
  delete from public.collection_layout_slot_expected_content where slot_id = v_slot;
  return query select 'RELEASED'::text;
  perform public.binder_activity_end();
end;
$fn$;

-- Fixar / soltar -------------------------------------------------------------------------------
create function public.editor_set_binder_lock(
  p_collection_id uuid,
  p_page          integer,
  p_row           integer,
  p_column        integer,
  p_locked        boolean
)
returns table (operation text)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $fn$
#variable_conflict use_column
declare
  v_layout    uuid;
  v_anchor    uuid;
  v_owner     uuid;
  v_container uuid;
  v_slot      uuid;
  v_scope     text;
  v_locked    boolean;
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  if (select auth.uid()) is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null or p_page is null or p_row is null or p_column is null or p_locked is null
     or p_page < 1 or p_row < 1 or p_column < 1 then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  select x.layout_id, x.anchor_collection_id, x.owner_user_id, x.container_id
    into v_layout, v_anchor, v_owner, v_container
  from public.assert_collection_binder_editor(p_collection_id) x;

  v_slot := public.binder_slot_at(v_layout, p_page, p_row, p_column);
  if v_slot is null then
    raise exception 'SLOT_NOT_EDITABLE' using errcode = '42501';
  end if;
  select s.locked into v_locked from public.collection_layout_slot s where s.id = v_slot for update;
  v_scope := public.binder_slot_editor_scope(v_layout, v_anchor, p_collection_id, v_slot);
  -- Fixar e soltar: só bolso OWN (com carta ou reserva de X). FREE e FOREIGN → mesma recusa.
  if v_scope <> 'OWN' then
    raise exception 'SLOT_NOT_EDITABLE' using errcode = '42501';
  end if;
  if v_locked is not distinct from p_locked then
    return query select 'UNCHANGED'::text;
    return;
  end if;

  -- Escrita (espelho da 5278, um bolso).
  perform public.binder_activity_begin(v_layout, case when p_locked then 'POCKETS_LOCKED' else 'POCKETS_UNLOCKED' end,
                                       'FICHARIO', p_collection_id);
  perform public.binder_activity_add_item('POCKET', case when p_locked then 'LOCKED' else 'UNLOCKED' end, null, null,
                                          case when p_locked then null else v_slot end, case when p_locked then v_slot end);
  update public.collection_layout_slot set locked = p_locked
  where id = v_slot and locked is distinct from p_locked;
  return query select case when p_locked then 'LOCKED' else 'UNLOCKED' end;
  perform public.binder_activity_end();
end;
$fn$;

comment on function public.editor_set_binder_reservation(uuid, integer, integer, integer, uuid, uuid, uuid) is
  'V1-13 E1-B2 (5375): EDITOR reserva um bolso livre ou da coleção (posição visível) para uma carta; a reserva fica registrada para a coleção (C-196/C-237). Não aloca nada.';
comment on function public.editor_clear_binder_reservation(uuid, integer, integer, integer) is
  'V1-13 E1-B2 (5375): EDITOR libera uma reserva da coleção (C-237). Reserva de outra coleção → SLOT_NOT_EDITABLE.';
comment on function public.editor_set_binder_lock(uuid, integer, integer, integer, boolean) is
  'V1-13 E1-B2 (5375): EDITOR fixa ou solta um bolso da coleção (com carta ou reserva dela). Bolso livre ou de terceiros → SLOT_NOT_EDITABLE (C-237).';

revoke all on function public.editor_set_binder_reservation(uuid, integer, integer, integer, uuid, uuid, uuid) from public, anon;
revoke all on function public.editor_clear_binder_reservation(uuid, integer, integer, integer) from public, anon;
revoke all on function public.editor_set_binder_lock(uuid, integer, integer, integer, boolean) from public, anon;
grant execute on function public.editor_set_binder_reservation(uuid, integer, integer, integer, uuid, uuid, uuid) to authenticated;
grant execute on function public.editor_clear_binder_reservation(uuid, integer, integer, integer) to authenticated;
grant execute on function public.editor_set_binder_lock(uuid, integer, integer, integer, boolean) to authenticated;

do $post$
declare
  f oid;
begin
  foreach f in array array[
      to_regprocedure('public.editor_set_binder_reservation(uuid, integer, integer, integer, uuid, uuid, uuid)'),
      to_regprocedure('public.editor_clear_binder_reservation(uuid, integer, integer, integer)'),
      to_regprocedure('public.editor_set_binder_lock(uuid, integer, integer, integer, boolean)')] loop
    if f is null
       or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
       or not ((select p.proconfig from pg_catalog.pg_proc p where p.oid = f) @> array['search_path=""'])
       or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not true
       or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false then
      raise exception 'POSTCHECK 5375: escrita do EDITOR fora do estado esperado (%)', f;
    end if;
    if (select coalesce(string_agg(a::text, ',' order by a::text), '<NULL>') from pg_catalog.pg_proc p cross join lateral unnest(p.proacl) a where p.oid = f)
       is distinct from (select coalesce(string_agg(a::text, ',' order by a::text), '<NULL>') from pg_catalog.pg_proc p cross join lateral unnest(p.proacl) a
                         where p.oid = to_regprocedure('public.set_slot_expected_content(uuid, uuid, uuid, uuid, uuid)')) then
      raise exception 'POSTCHECK 5375: ACL difere da 5276 (%)', f;
    end if;
  end loop;
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.set_slot_expected_content(uuid, uuid, uuid, uuid, uuid)')) is distinct from '33dde5013dbb491bd4a0452ab7ce8132'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.clear_slot_expected_content(uuid[])')) is distinct from '0b8f26825ff713a24226548ffe3a63b7'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.set_slot_lock(uuid[], boolean)')) is distinct from '651048a4bf7d3229904ef2a073c509c5' then
    raise exception 'POSTCHECK 5375: funções do titular mudaram';
  end if;
end;
$post$;

-- @@T7 5376 (protegida) sha256=8cae24afc9232d3333bf4621fad1aad09e436bfc18155ef172b08ef59e1fbcfe
set local lock_timeout = '5s';

do $pre$
begin
  if to_regprocedure('public.v1_13_assert_capability()') is null or to_regprocedure('public.v1_13_capability_open()') is null then raise exception 'PRECHECK G1: barreira 5389 ausente'; end if;  -- G1 (D-E1)
  if (select pg_catalog.pg_get_constraintdef(k.oid) from pg_catalog.pg_constraint k
       where k.conrelid = 'public.collection_membership'::regclass
         and k.conname = 'chk_collection_membership_role')
     is distinct from 'CHECK ((role = ANY (ARRAY[''VIEWER''::text, ''EDITOR''::text])))' then
    raise exception 'PRECHECK 5376: E1-A (5366) não aplicada';
  end if;
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.update_collection_metadata(uuid, text, text)')) is distinct from 'a581235db9cabaf7043707a290f963b7'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.set_my_collection_cover_finish(uuid, text)')) is distinct from '4f48d9161b4a29ecb23e7443e31d1806'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.set_my_collection_cover_code(uuid, text)')) is distinct from 'd0d8cbfa517b9da3728a55af47de21cb'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.set_my_collection_cover_logo(uuid, text)')) is distinct from '5868fb1c8de760787d1128ac20a09507' then
    raise exception 'PRECHECK 5376: ESTADO DIVERGENTE — funções do titular (5035/5172/5178/5180) diferem das canônicas';
  end if;
  if exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public'
               and p.proname in ('assert_collection_editor', 'editor_update_collection_metadata', 'editor_set_collection_cover_finish',
                                 'editor_set_collection_cover_code', 'editor_set_collection_cover_logo')) then
    raise exception 'PRECHECK 5376: funções já existem — JÁ APLICADA ou ESTADO DIVERGENTE';
  end if;
end;
$pre$;

-- Ajudante interno ------------------------------------------------------------------------------
create function public.assert_collection_editor(p_collection_id uuid)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_uid    uuid := (select auth.uid());
  v_owner  uuid;
  v_status text;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  select c.owner_user_id into v_owner
  from public.collection c
  join public.collection_membership m
    on m.collection_id = c.id and m.user_id = v_uid and m.status = 'ACTIVE' and m.role = 'EDITOR'
  where c.id = p_collection_id
    and c.owner_user_id <> v_uid;
  if v_owner is null then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- Coleção (FOR UPDATE) antes da participação (FOR SHARE).
  select c.lifecycle_status into v_status
  from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_owner
  for update;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  perform 1
  from public.collection_membership m
  where m.collection_id = p_collection_id and m.user_id = v_uid
    and m.status = 'ACTIVE' and m.role = 'EDITOR'
  for share;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  if v_status <> 'ACTIVE' then
    raise exception 'COLLECTION_ARCHIVED' using errcode = '55000';
  end if;
  return v_owner;
end;
$fn$;

-- Nome e descrição ------------------------------------------------------------------------------
create function public.editor_update_collection_metadata(
  p_collection_id uuid,
  p_name          text,
  p_description   text
)
returns table (name text, description text)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_owner uuid;
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  if (select auth.uid()) is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_name is null or btrim(p_name) = '' then
    raise exception 'p_name não pode ser vazio' using errcode = '22023';
  end if;
  v_owner := public.assert_collection_editor(p_collection_id);

  return query
  update public.collection c
  set name = btrim(p_name), description = p_description
  where c.id = p_collection_id and c.owner_user_id = v_owner
  returning c.name::text, c.description::text;
end;
$fn$;

-- Acabamento da capa da coleção ------------------------------------------------------------------
create function public.editor_set_collection_cover_finish(
  p_collection_id uuid,
  p_finish        text
)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_owner  uuid;
  v_finish text := lower(btrim(coalesce(p_finish, '')));
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  if (select auth.uid()) is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if v_finish not in ('onix', 'vinho', 'floresta', 'marinho', 'caramelo', 'perola') then
    raise exception 'INVALID_FINISH' using errcode = '22023';
  end if;
  v_owner := public.assert_collection_editor(p_collection_id);

  update public.collection c
  set cover_finish = v_finish
  where c.id = p_collection_id and c.owner_user_id = v_owner;
  return v_finish;
end;
$fn$;

-- Código da placa (coleção livre ou Pokédex) --------------------------------------------------------
create function public.editor_set_collection_cover_code(
  p_collection_id uuid,
  p_code          text
)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_owner uuid;
  v_code  text := nullif(upper(btrim(coalesce(p_code, ''))), '');
  v_free  boolean;
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  if (select auth.uid()) is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if v_code is not null and v_code !~ '^[A-Z0-9]{2,6}$' then
    raise exception 'INVALID_COVER_CODE' using errcode = '22023';
  end if;
  v_owner := public.assert_collection_editor(p_collection_id);

  select ((c.completion_policy = 'NONE'
           and not exists (select 1 from public.collection_reference cr where cr.collection_id = c.id))
          or (c.completion_policy = 'REFERENCE_POSITION'
              and exists (select 1 from public.collection_reference cr
                          where cr.collection_id = c.id and cr.reference_kind = 'POKEDEX')))
    into v_free
  from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_owner;
  if v_free is not true then
    raise exception 'NOT_FREE_COLLECTION' using errcode = '55000';
  end if;

  update public.collection c
  set cover_code = v_code
  where c.id = p_collection_id and c.owner_user_id = v_owner;
  return v_code;
end;
$fn$;

-- Imagem da placa (arquivo na pasta do titular) ------------------------------------------------------
create function public.editor_set_collection_cover_logo(
  p_collection_id uuid,
  p_path          text
)
returns table (cover_logo_path text, removable_previous_path text)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_uid       uuid := (select auth.uid());
  v_owner     uuid;
  v_path      text := nullif(btrim(coalesce(p_path, '')), '');
  v_prev      text;
  v_prev_mine boolean;
  v_free      boolean;
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null then
    raise exception 'INVALID_COVER_PATH' using errcode = '22023';
  end if;
  v_owner := public.assert_collection_editor(p_collection_id);

  select c.cover_logo_path,
         ((c.completion_policy = 'NONE'
           and not exists (select 1 from public.collection_reference cr where cr.collection_id = c.id))
          or (c.completion_policy = 'REFERENCE_POSITION'
              and exists (select 1 from public.collection_reference cr
                          where cr.collection_id = c.id and cr.reference_kind = 'POKEDEX')))
    into v_prev, v_free
  from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_owner;
  if v_free is not true then
    raise exception 'NOT_FREE_COLLECTION' using errcode = '55000';
  end if;

  if v_path is not null then
    -- Pasta do TITULAR desta coleção, nome no formato do 5178.
    if left(v_path, 74) <> v_owner::text || '/' || p_collection_id::text || '/'
       or v_path !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(png|jpg|webp)$' then
      raise exception 'INVALID_COVER_PATH' using errcode = '22023';
    end if;
    -- Arquivo existe e foi enviado pelo EDITOR chamador ou pelo titular.
    if not exists (
      select 1
      from storage.objects o
      where o.bucket_id = 'collection-cover'
        and o.name = v_path
        and (o.owner_id in (v_uid::text, v_owner::text) or o.owner in (v_uid, v_owner))
    ) then
      raise exception 'COVER_FILE_NOT_FOUND' using errcode = 'P0002';
    end if;
  end if;

  -- O arquivo anterior só é oferecido para exclusão se foi enviado pelo próprio EDITOR.
  select exists (select 1 from storage.objects o
                 where o.bucket_id = 'collection-cover' and o.name = v_prev
                   and (o.owner_id = v_uid::text or o.owner = v_uid))
    into v_prev_mine;

  update public.collection c
  set cover_logo_path = v_path
  where c.id = p_collection_id and c.owner_user_id = v_owner;

  return query
  select v_path,
         case when v_prev is distinct from v_path and v_prev_mine then v_prev end;
end;
$fn$;

comment on function public.assert_collection_editor(uuid) is
  'V1-13 E1-B2 (5376, interna): autoriza o usuário da sessão como EDITOR ACTIVE da coleção; trava coleção → participação. Devolve o titular.';
comment on function public.editor_update_collection_metadata(uuid, text, text) is
  'V1-13 E1-B2 (5376): EDITOR altera nome e descrição da coleção (C-239). Nada estrutural.';
comment on function public.editor_set_collection_cover_finish(uuid, text) is
  'V1-13 E1-B2 (5376): EDITOR altera o acabamento da capa da coleção (não do fichário).';
comment on function public.editor_set_collection_cover_code(uuid, text) is
  'V1-13 E1-B2 (5376): EDITOR altera o código da placa de coleção livre ou Pokédex.';
comment on function public.editor_set_collection_cover_logo(uuid, text) is
  'V1-13 E1-B2 (5376): EDITOR define ou remove a imagem da placa com arquivo da pasta do titular enviado por ele ou pelo titular; só arquivo dele é devolvido para exclusão.';

revoke all on function public.assert_collection_editor(uuid) from public, anon, authenticated, service_role;
revoke all on function public.editor_update_collection_metadata(uuid, text, text) from public, anon;
revoke all on function public.editor_set_collection_cover_finish(uuid, text) from public, anon;
revoke all on function public.editor_set_collection_cover_code(uuid, text) from public, anon;
revoke all on function public.editor_set_collection_cover_logo(uuid, text) from public, anon;
grant execute on function public.editor_update_collection_metadata(uuid, text, text) to authenticated;
grant execute on function public.editor_set_collection_cover_finish(uuid, text) to authenticated;
grant execute on function public.editor_set_collection_cover_code(uuid, text) to authenticated;
grant execute on function public.editor_set_collection_cover_logo(uuid, text) to authenticated;

do $post$
declare
  f oid;
begin
  f := to_regprocedure('public.assert_collection_editor(uuid)');
  if f is null
     or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
     or (select p.proconfig from pg_catalog.pg_proc p where p.oid = f) is distinct from array['search_path=""']
     or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not false
     or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false
     or pg_catalog.has_function_privilege('service_role', f, 'EXECUTE') is not false then
    raise exception 'POSTCHECK 5376: ajudante interno fora do estado esperado';
  end if;
  foreach f in array array[
      to_regprocedure('public.editor_update_collection_metadata(uuid, text, text)'),
      to_regprocedure('public.editor_set_collection_cover_finish(uuid, text)'),
      to_regprocedure('public.editor_set_collection_cover_code(uuid, text)'),
      to_regprocedure('public.editor_set_collection_cover_logo(uuid, text)')] loop
    if f is null
       or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
       or (select p.proconfig from pg_catalog.pg_proc p where p.oid = f) is distinct from array['search_path=""']
       or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not true
       or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false then
      raise exception 'POSTCHECK 5376: escrita do EDITOR fora do estado esperado (%)', f;
    end if;
    if (select coalesce(string_agg(a::text, ',' order by a::text), '<NULL>') from pg_catalog.pg_proc p cross join lateral unnest(p.proacl) a where p.oid = f)
       is distinct from (select coalesce(string_agg(a::text, ',' order by a::text), '<NULL>') from pg_catalog.pg_proc p cross join lateral unnest(p.proacl) a
                         where p.oid = to_regprocedure('public.set_my_collection_cover_finish(uuid, text)')) then
      raise exception 'POSTCHECK 5376: ACL difere da 5172 (%)', f;
    end if;
  end loop;
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.update_collection_metadata(uuid, text, text)')) is distinct from 'a581235db9cabaf7043707a290f963b7'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.set_my_collection_cover_finish(uuid, text)')) is distinct from '4f48d9161b4a29ecb23e7443e31d1806'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.set_my_collection_cover_code(uuid, text)')) is distinct from 'd0d8cbfa517b9da3728a55af47de21cb'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.set_my_collection_cover_logo(uuid, text)')) is distinct from '5868fb1c8de760787d1128ac20a09507' then
    raise exception 'POSTCHECK 5376: funções do titular mudaram';
  end if;
end;
$post$;

-- @@T7 5378 (auditada) sha256=828fa3d54543c31e845aa9ef7c56ba1721fbf30679dc2af91bac5f483c7c0e5d
set local lock_timeout = '5s';

do $pre$
declare
  v_m text := (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
               where p.oid = to_regprocedure('public.binder_slot_editor_scope(uuid, uuid, uuid, uuid)'));
begin
  if v_m = '21f1b51a3a0f6c80337c2c593cc6054f' then
    raise exception 'PRECHECK 5378: JÁ APLICADA — não reaplicar';
  end if;
  if v_m is distinct from '3086014a164704f309c7051419df3f23' then
    raise exception 'PRECHECK 5378: ESTADO DIVERGENTE — corpo vigente difere da 5371 (%)', v_m;
  end if;
end;
$pre$;

create or replace function public.binder_slot_editor_scope(
  p_layout_id            uuid,
  p_anchor_collection_id uuid,
  p_collection_id        uuid,
  p_slot_id              uuid
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_page    uuid;
  v_row     integer;
  v_col     integer;
  v_locked  boolean;
  v_card    uuid;
  v_card_cl uuid;
  v_res_cl  uuid;
  v_res     boolean;
  v_spc_cl  uuid;
  v_own     boolean := false;
begin
  select s.page_id, s.row_index, s.column_index, s.locked
    into v_page, v_row, v_col, v_locked
  from public.collection_layout_slot s
  join public.collection_layout_page p on p.id = s.page_id
  where s.id = p_slot_id and p.layout_id = p_layout_id;
  if v_page is null then
    return 'FOREIGN';
  end if;

  -- Carta: só é de X se o exemplar estiver alocado a X.
  select a.physical_card_id, ca.collection_id into v_card, v_card_cl
  from public.collection_layout_slot_assignment a
  left join public.collection_allocation ca on ca.physical_card_id = a.physical_card_id
  where a.slot_id = p_slot_id;
  if v_card is not null then
    if v_card_cl is distinct from p_collection_id then
      return 'FOREIGN';
    end if;
    v_own := true;
  end if;

  -- Reserva: sem coleção registrada = da proprietária (C-196).
  select true, coalesce(e.collection_id, p_anchor_collection_id) into v_res, v_res_cl
  from public.collection_layout_slot_expected_content e
  where e.slot_id = p_slot_id;
  if v_res then
    if v_res_cl is distinct from p_collection_id then
      return 'FOREIGN';
    end if;
    v_own := true;
  end if;

  -- Imagem personalizada e região mesclada: sempre do titular / fora da E1-B1.
  if exists (select 1 from public.collection_layout_slot_image i where i.slot_id = p_slot_id) then
    return 'FOREIGN';
  end if;
  if exists (select 1 from public.collection_layout_region r
             where r.page_id = v_page
               and v_row between r.top_row and r.top_row + r.height - 1
               and v_col between r.left_column and r.left_column + r.width - 1) then
    return 'FOREIGN';
  end if;

  -- Referência de espécie: só é de X se registrada para X.
  select sr.collection_id into v_spc_cl
  from public.collection_layout_slot_species_reference sr
  where sr.slot_id = p_slot_id;
  if found then
    if v_spc_cl is distinct from p_collection_id then
      return 'FOREIGN';
    end if;
    v_own := true;   -- E1-B3 (5378): referência de espécie de X = bolso de X (C-237)
  end if;

  -- Trava: sem carta nem reserva de X, o bolso fixado é do titular.
  if v_locked and not v_own then
    return 'FOREIGN';
  end if;

  return case when v_own then 'OWN' else 'FREE' end;
end;
$fn$;

do $post$
declare
  f oid := to_regprocedure('public.binder_slot_editor_scope(uuid, uuid, uuid, uuid)');
begin
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = f) is distinct from '21f1b51a3a0f6c80337c2c593cc6054f'
     or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
     or (select p.provolatile from pg_catalog.pg_proc p where p.oid = f) <> 's'
     or (select p.proconfig from pg_catalog.pg_proc p where p.oid = f) is distinct from array['search_path=""']
     or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not false
     or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false
     or pg_catalog.has_function_privilege('service_role', f, 'EXECUTE') is not false then
    raise exception 'POSTCHECK 5378: binder_slot_editor_scope fora do estado esperado';
  end if;
end;
$post$;

-- @@T7 5379 (auditada) sha256=7eed93c01db7ab5aacbf4193af06d5cfd6bd92f3102abe21b67d9727af22534c
set local lock_timeout = '5s';

do $pre$
declare
  v_m text := (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
               where p.oid = to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)'));
  v_ci boolean := exists (select 1 from information_schema.columns c
                          where c.table_schema = 'public' and c.table_name = 'binder_activity_item' and c.column_name = 'collection_id');
  v_ce boolean := exists (select 1 from information_schema.columns c
                          where c.table_schema = 'public' and c.table_name = 'binder_activity_event' and c.column_name = 'item_collection_recorded');
  v_ci_ok boolean := exists (select 1 from information_schema.columns c
                             where c.table_schema = 'public' and c.table_name = 'binder_activity_item'
                               and c.column_name = 'collection_id' and c.data_type = 'uuid'
                               and c.is_nullable = 'YES' and c.column_default is null);
  v_ce_ok boolean := exists (select 1 from information_schema.columns c
                             where c.table_schema = 'public' and c.table_name = 'binder_activity_event'
                               and c.column_name = 'item_collection_recorded' and c.data_type = 'boolean'
                               and c.is_nullable = 'NO' and c.column_default = 'false');
begin
  if v_m = 'f8cfba40e442e85056e7c8ce7954d4f4' and v_ci and v_ce then
    raise exception 'PRECHECK 5379: JÁ APLICADA — não reaplicar';
  end if;
  if v_m is distinct from '59ec5791e514026b7a8340e104d66f30' then
    raise exception 'PRECHECK 5379: ESTADO DIVERGENTE — corpo vigente difere da 5372 (%)', v_m;
  end if;
  if (v_ci and not v_ci_ok) or (v_ce and not v_ce_ok) or (v_ci <> v_ce) then
    raise exception 'PRECHECK 5379: ESTADO DIVERGENTE — colunas de atribuição presentes com forma diferente';
  end if;
  if to_regclass('public.collection_layout_slot_species_reference') is null then
    raise exception 'PRECHECK 5379: 5257 ausente';
  end if;
end;
$pre$;

-- IF NOT EXISTS: na reaplicação depois de uma reversão conservadora as colunas (e os
-- dados) já estão lá, com a forma conferida no precheck.
alter table public.binder_activity_item add column if not exists collection_id uuid null;
alter table public.binder_activity_event add column if not exists item_collection_recorded boolean not null default false;

comment on column public.binder_activity_item.collection_id is
  'V1-13 E1-B3 (5379): coleção do item, derivada no servidor no instante da gravação (exemplar → alocação; reserva → coleção registrada ou proprietária; bolso → conteúdo). Valor sem FK, nunca reescrito. NULL = item sem coleção (estrutura, imagem do titular, exemplar sem coleção) ou evento não atribuído (ver item_collection_recorded). Não concede visibilidade: a leitura de membros filtra antes pelo tipo de evento (C-241).';
comment on column public.binder_activity_event.item_collection_recorded is
  'V1-13 E1-B3 (5379): true = os itens deste evento passaram pela atribuição de coleção da 5379. false = evento não atribuído (anterior à 5379 ou gravado com a 5379 revertida): itens sem coleção registrada, nunca atribuídos retroativamente.';

create or replace function public.binder_activity_add_item(
  p_kind            text,
  p_effect          text,
  p_card_id         uuid    default null,
  p_variant_type_id uuid    default null,
  p_from_slot_id    uuid    default null,
  p_to_slot_id      uuid    default null,
  p_from_page       integer default null,
  p_to_page         integer default null,
  p_detail          jsonb   default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_ctx      jsonb := nullif(current_setting('mmkyu.binder_activity_ctx', true), '')::jsonb;
  v_uid      uuid  := (select auth.uid());
  v_layout   uuid;
  v_event    bigint;
  v_n        integer;
  v_cap      bigint;
  v_cap_now  bigint;
  c_repeat_slack constant integer := 600;   -- ≥ 5264 c_row_limit (500) + c_item_limit (100); ≥ 5243 c_row_limit (500)
  v_owner    uuid;
  v_binder   text;
  v_coll     uuid;
  v_collname text;
  f_page int; f_row int; f_col int;
  t_page int; t_row int; t_col int;
  c_name text; c_num text; c_set text; vt_code text; vt_name text;
  v_ev_owner uuid;   -- E1-B3 (5379)
  v_ev_coll  uuid;
  v_ev_lay   uuid;
  v_ev_actor uuid;
  v_ev_xact  xid8;
  v_islot    uuid;
  v_icoll    uuid;
begin
  if v_ctx is null or (v_ctx ->> 'depth')::integer < 1 then
    raise exception 'binder activity: no open operation' using errcode = 'P0001', hint = 'BINDER_ACTIVITY_NO_CONTEXT';
  end if;
  if v_uid is null then
    raise exception 'binder activity requires an authenticated actor' using errcode = '28000';
  end if;
  v_layout := (v_ctx ->> 'layout')::uuid;
  v_event  := (v_ctx ->> 'event_id')::bigint;
  v_n      := (v_ctx ->> 'n')::integer + 1;
  v_cap    := coalesce((v_ctx ->> 'cap')::bigint, 0);

  -- W1: teto derivado da capacidade + folga de repetição (ver cabeçalho). Calculado no
  -- primeiro item (cap = 0), em todo PAGE_ADDED e quando excedido; guarda o máximo observado.
  if v_n > v_cap or (p_kind = 'PAGE' and p_effect = 'PAGE_ADDED') then
    select count(p.id) * (8::bigint * l.grid_rows * l.grid_columns + 2) + 8 + c_repeat_slack
      into v_cap_now
    from public.collection_layout l
    left join public.collection_layout_page p on p.layout_id = l.id
    where l.id = v_layout
    group by l.grid_rows, l.grid_columns;
    v_cap := greatest(v_cap, coalesce(v_cap_now, 8 + c_repeat_slack));
    if v_n > v_cap then
      raise exception 'binder activity: item limit exceeded (% > %)', v_n, v_cap using errcode = 'P0001',
        hint = 'BINDER_ACTIVITY_ITEM_LIMIT';
    end if;
    v_ctx := jsonb_set(v_ctx, '{cap}', to_jsonb(v_cap));
  end if;

  if v_event is null then
    -- Cabeçalho no primeiro item: titular e nomes copiados agora.
    select c.owner_user_id, coalesce(nullif(l.display_name, ''), c.name)
      into v_owner, v_binder
    from public.collection_layout l
    join public.collection c on c.id = l.collection_id
    where l.id = v_layout;
    if v_owner is null then
      raise exception 'binder activity: binder not found' using errcode = 'P0002', hint = 'BINDER_ACTIVITY_LAYOUT_NOT_FOUND';
    end if;
    v_coll := nullif(v_ctx ->> 'collection', '')::uuid;
    if v_owner <> v_uid then
      -- V1-13 E1-B1 (5372): ator diferente do titular só como EDITOR ACTIVE da coleção
      -- do evento, coleção do mesmo titular e participante deste fichário (C-241).
      -- Defesa em profundidade: a função de escrita já autorizou e travou (5371).
      if v_coll is null
         or not exists (select 1 from public.collection_membership m
                        where m.collection_id = v_coll and m.user_id = v_uid
                          and m.status = 'ACTIVE' and m.role = 'EDITOR')
         or not exists (select 1 from public.collection c
                        where c.id = v_coll and c.owner_user_id = v_owner)
         or not (exists (select 1 from public.collection_layout l
                         where l.id = v_layout and l.collection_id = v_coll)
                 or exists (select 1 from public.collection_layout_guest g
                            where g.layout_id = v_layout and g.collection_id = v_coll)) then
        raise exception 'binder activity: actor is not the binder owner' using errcode = '42501',
          hint = 'BINDER_ACTIVITY_NOT_OWNER';
      end if;
    end if;
    if v_coll is not null then
      select c.name into v_collname from public.collection c where c.id = v_coll and c.owner_user_id = v_owner;
    end if;
    insert into public.binder_activity_event
      (owner_user_id, layout_key, actor_user_id, event_type, source,
       collection_id, collection_name, binder_name, summary, item_collection_recorded)
    values
      (v_owner, v_layout, v_uid, v_ctx ->> 'type', v_ctx ->> 'source',
       case when v_collname is not null then v_coll end, left(v_collname, 200), left(v_binder, 200),
       coalesce(v_ctx -> 'summary', '{}'::jsonb), true)
    returning id into v_event;
    v_ctx := jsonb_set(v_ctx, '{event_id}', to_jsonb(v_event));
  end if;

  -- Posições copiadas agora (R3); bolso de outro fichário → erro.
  if p_from_slot_id is not null then
    select p.page_number, s.row_index, s.column_index into f_page, f_row, f_col
    from public.collection_layout_slot s join public.collection_layout_page p on p.id = s.page_id
    where s.id = p_from_slot_id and p.layout_id = v_layout;
    if f_page is null then
      raise exception 'binder activity: origin pocket not in binder' using errcode = 'P0001', hint = 'BINDER_ACTIVITY_SLOT';
    end if;
  else
    f_page := p_from_page;
  end if;
  if p_to_slot_id is not null then
    select p.page_number, s.row_index, s.column_index into t_page, t_row, t_col
    from public.collection_layout_slot s join public.collection_layout_page p on p.id = s.page_id
    where s.id = p_to_slot_id and p.layout_id = v_layout;
    if t_page is null then
      raise exception 'binder activity: target pocket not in binder' using errcode = 'P0001', hint = 'BINDER_ACTIVITY_SLOT';
    end if;
  else
    t_page := p_to_page;
  end if;

  -- Cópia da carta e do acabamento.
  if p_card_id is not null then
    select k.name, k.collector_number, cs.code into c_name, c_num, c_set
    from public.card k join public.card_set cs on cs.id = k.card_set_id
    where k.id = p_card_id;
    if c_name is null then
      raise exception 'binder activity: card not found' using errcode = 'P0002', hint = 'BINDER_ACTIVITY_CARD';
    end if;
  end if;
  if p_variant_type_id is not null then
    select t.code, t.name into vt_code, vt_name from public.card_variant_type t where t.id = p_variant_type_id;
  end if;

  -- V1-13 E1-B3 (5379): coleção do item, derivada no servidor no instante da gravação e
  -- só do conteúdo real do fichário (nunca de parâmetro do cliente). NULL = item sem
  -- coleção: estrutura do fichário (PAGE, COLLECTION, BINDER), imagem do titular,
  -- exemplar sem coleção, bolso sem conteúdo.
  select e.owner_user_id, e.collection_id, e.layout_key, e.actor_user_id, e.created_xact
    into v_ev_owner, v_ev_coll, v_ev_lay, v_ev_actor, v_ev_xact
  from public.binder_activity_event e where e.id = v_event;
  -- O evento do contexto precisa ser o desta operação: mesmo fichário, mesmo ator e
  -- gravado nesta transação. Contexto forjado (event_id de outro evento) → recusa.
  if v_ev_lay is distinct from v_layout or v_ev_actor is distinct from v_uid
     or v_ev_xact is distinct from pg_catalog.pg_current_xact_id() then
    raise exception 'binder activity: event context does not belong to this operation' using errcode = '42501',
      hint = 'BINDER_ACTIVITY_FORGED_CONTEXT';
  end if;
  v_islot := coalesce(p_to_slot_id, p_from_slot_id);
  if p_kind = 'CARD' then
    -- Exemplar: a alocação vigente (uma por exemplar).
    if p_detail ? 'physical_card_id' then
      select ca.collection_id into v_icoll
      from public.collection_allocation ca
      where ca.physical_card_id = (p_detail ->> 'physical_card_id')::uuid;
    end if;
  elsif p_kind = 'RESERVATION' then
    -- Reserva: a coleção registrada (5275/5279 copiam no detalhe); sem coleção
    -- registrada = proprietária do fichário (C-196).
    if p_detail ? 'collection_id' then
      v_icoll := (p_detail ->> 'collection_id')::uuid;
    elsif v_islot is not null then
      select coalesce(x.collection_id, l.collection_id) into v_icoll
      from public.collection_layout_slot_expected_content x
      join public.collection_layout l on l.id = v_layout
      where x.slot_id = v_islot;
    end if;
  elsif p_kind = 'POCKET' and v_islot is not null and coalesce(p_detail ->> 'content', '') <> 'IMAGE' then
    -- Bolso (fixar/soltar): o conteúdo que o classifica, na mesma ordem da 5371/5378 —
    -- carta (a alocação dela, ou nenhuma), senão reserva, senão referência de espécie.
    perform 1 from public.collection_layout_slot_assignment a where a.slot_id = v_islot;
    if found then
      select ca.collection_id into v_icoll
      from public.collection_layout_slot_assignment a
      join public.collection_allocation ca on ca.physical_card_id = a.physical_card_id
      where a.slot_id = v_islot;
    else
      select coalesce(x.collection_id, l.collection_id) into v_icoll
      from public.collection_layout_slot_expected_content x
      join public.collection_layout l on l.id = v_layout
      where x.slot_id = v_islot;
      if not found then
        select sr.collection_id into v_icoll
        from public.collection_layout_slot_species_reference sr
        where sr.slot_id = v_islot;
      end if;
    end if;
  end if;
  if v_icoll is not null
     and not exists (select 1 from public.collection c where c.id = v_icoll and c.owner_user_id = v_ev_owner) then
    v_icoll := null;   -- nunca atribui a coleção de outro titular
  end if;
  -- Ator que não é o titular (EDITOR, 5372): todo item de conteúdo precisa ser da
  -- coleção do evento; itens estruturais (COLLECTION, BINDER) nunca são dele.
  if v_uid is distinct from v_ev_owner
     and (p_kind in ('COLLECTION', 'BINDER')
          or (p_kind in ('CARD', 'RESERVATION', 'POCKET') and v_icoll is distinct from v_ev_coll)) then
    raise exception 'binder activity: item outside the authorized collection' using errcode = '42501',
      hint = 'BINDER_ACTIVITY_CROSS_COLLECTION';
  end if;

  insert into public.binder_activity_item
    (event_id, ordinal, item_kind, effect, card_id, card_name, collector_number, card_set_code,
     variant_type_code, variant_type_name, from_page, from_row, from_col, to_page, to_row, to_col, detail,
     collection_id)
  values
    (v_event, v_n, p_kind, p_effect, p_card_id, left(c_name, 200), left(c_num, 40), left(c_set, 40),
     left(vt_code, 60), left(vt_name, 120), f_page, f_row, f_col, t_page, t_row, t_col, p_detail,
     v_icoll);

  v_ctx := jsonb_set(v_ctx, '{n}', to_jsonb(v_n));
  perform set_config('mmkyu.binder_activity_ctx', v_ctx::text, true);
end;
$fn$;

do $post$
declare
  f oid := to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)');
begin
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = f) is distinct from 'f8cfba40e442e85056e7c8ce7954d4f4'
     or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
     or (select p.proconfig from pg_catalog.pg_proc p where p.oid = f) is distinct from array['search_path=""']
     or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not false
     or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false
     or pg_catalog.has_function_privilege('service_role', f, 'EXECUTE') is not false then
    raise exception 'POSTCHECK 5379: binder_activity_add_item fora do estado esperado';
  end if;
  if (select c.is_nullable from information_schema.columns c
       where c.table_schema = 'public' and c.table_name = 'binder_activity_item' and c.column_name = 'collection_id') <> 'YES'
     or (select c.is_nullable || ':' || c.column_default from information_schema.columns c
          where c.table_schema = 'public' and c.table_name = 'binder_activity_event' and c.column_name = 'item_collection_recorded') <> 'NO:false' then
    raise exception 'POSTCHECK 5379: colunas fora do estado esperado';
  end if;
  if exists (select 1 from pg_catalog.pg_trigger t
             where t.tgrelid in ('public.binder_activity_event'::regclass, 'public.binder_activity_item'::regclass)
               and not t.tgisinternal and t.tgenabled <> 'O') then
    raise exception 'POSTCHECK 5379: gatilhos de imutabilidade fora do estado esperado';
  end if;
end;
$post$;

-- @@T7 5380 (protegida) sha256=5b9a1a09a51c9f4763833edefb4f84355d252b1dc0bbc20518ee9f0fe22f8f72
set local lock_timeout = '5s';

do $pre$
begin
  if to_regprocedure('public.v1_13_assert_capability()') is null or to_regprocedure('public.v1_13_capability_open()') is null then raise exception 'PRECHECK G1: barreira 5389 ausente'; end if;  -- G1 (D-E1)
  if to_regprocedure('public.assert_collection_editor(uuid)') is null then
    raise exception 'PRECHECK 5380: E1-B2 (5376) não aplicada';
  end if;
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.set_pokedex_position_assignment(uuid, uuid, boolean)')) is distinct from '8c572182a03025503e993e5ecc25e07a'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
          where p.oid = to_regprocedure('public.remove_pokedex_position_assignment(uuid)')) is distinct from '26ef2d5da3312661111df0194dfc8ba2'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
          where p.oid = to_regprocedure('public.set_pokedex_position_primary_representative(uuid)')) is distinct from '6353dffe6c3877967997033dcc2bfd4c'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
          where p.oid = to_regprocedure('public.clear_pokedex_position_primary_representative(uuid, uuid)')) is distinct from 'eeede3a5b871fbf07f81eb59ecea932f' then
    raise exception 'PRECHECK 5380: ESTADO DIVERGENTE — funções do titular da Pokédex diferem de 6123/6124/6126/6125';
  end if;
  if to_regprocedure('public.editor_set_pokedex_position_assignment(uuid, uuid, uuid, boolean)') is not null
     or to_regprocedure('public.editor_remove_pokedex_position_assignment(uuid, uuid)') is not null
     or to_regprocedure('public.editor_set_pokedex_position_primary_representative(uuid, uuid)') is not null
     or to_regprocedure('public.editor_clear_pokedex_position_primary_representative(uuid, uuid)') is not null then
    raise exception 'PRECHECK 5380: JÁ APLICADA ou ESTADO DIVERGENTE';
  end if;
end;
$pre$;

-- Ajudante interno: Pokédex da coleção autorizada (sem EXECUTE para a API) -----------------
create function public.editor_pokedex_of_collection(p_collection_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_dex uuid;
begin
  select cpr.pokedex_id into v_dex
  from public.collection c
  join public.collection_reference cr on cr.collection_id = c.id and cr.reference_kind = 'POKEDEX'
  join public.collection_pokedex_reference cpr on cpr.collection_reference_id = cr.id
  where c.id = p_collection_id
    and c.mode = 'REFERENCE_BASED'
    and c.completion_policy = 'REFERENCE_POSITION';
  if v_dex is null then
    raise exception 'NOT_POKEDEX_COLLECTION' using errcode = '22023';
  end if;
  return v_dex;
end;
$fn$;

-- Posição: criar ou mover -----------------------------------------------------------------
create function public.editor_set_pokedex_position_assignment(
  p_collection_id       uuid,
  p_physical_card_id    uuid,
  p_pokedex_position_id uuid,
  p_confirm_override    boolean default false
)
returns table (pokedex_position_id uuid, assignment_basis text, operation text)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_uid      uuid := (select auth.uid());
  v_owner    uuid;
  v_dex      uuid;
  v_alloc    uuid;
  v_cur      uuid;
  v_cur_base text;
  v_pos_dex  uuid;
  v_pos_spc  uuid;
  v_cat      text;
  v_spc      uuid;
  v_base     text;
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_physical_card_id is null or p_pokedex_position_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  v_owner := public.assert_collection_editor(p_collection_id);
  v_dex := public.editor_pokedex_of_collection(p_collection_id);

  -- Coleção já travada (assert) → alocação de X, travada.
  select ca.id into v_alloc
  from public.collection_allocation ca
  where ca.physical_card_id = p_physical_card_id and ca.collection_id = p_collection_id
  for update;
  if v_alloc is null then
    raise exception 'PHYSICAL_CARD_NOT_ELIGIBLE' using errcode = 'P0002';
  end if;

  select a.pokedex_position_id, a.assignment_basis into v_cur, v_cur_base
  from public.collection_pokedex_position_assignment a
  where a.collection_allocation_id = v_alloc;
  if v_cur = p_pokedex_position_id then
    return query select v_cur, v_cur_base, 'UNCHANGED'::text;
    return;
  end if;

  select pp.pokedex_id, pp.species_id into v_pos_dex, v_pos_spc
  from public.pokedex_position pp
  where pp.id = p_pokedex_position_id;
  if v_pos_dex is distinct from v_dex then
    raise exception 'POKEDEX_POSITION_NOT_FOUND' using errcode = '22023';
  end if;

  select cc.code, cps.pokemon_species_id into v_cat, v_spc
  from public.physical_card pc
  join public.card_variant cv on cv.id = pc.card_variant_id
  join public.card k on k.id = cv.card_id
  join public.card_category cc on cc.id = k.category_id
  left join public.card_primary_species cps on cps.card_id = k.id
  where pc.id = p_physical_card_id;
  if v_cat = 'POKEMON' and v_spc is not null and v_spc = v_pos_spc then
    v_base := 'SPECIES_MATCH';
  elsif coalesce(p_confirm_override, false) then
    v_base := 'USER_OVERRIDE';
  else
    raise exception 'CONFIRMATION_REQUIRED' using errcode = '22023',
      hint = 'a carta não corresponde à espécie da posição; confirme para posicionar mesmo assim';
  end if;

  if v_cur is not null then
    delete from public.collection_pokedex_position_assignment a
    where a.collection_allocation_id = v_alloc;
  end if;
  insert into public.collection_pokedex_position_assignment
    (collection_allocation_id, pokedex_position_id, assignment_basis, assigned_at, assigned_by_user_id)
  values (v_alloc, p_pokedex_position_id, v_base, now(),
          case when v_base = 'USER_OVERRIDE' then v_uid end);

  return query select p_pokedex_position_id, v_base,
                      case when v_cur is null then 'CREATED' else 'MOVED' end::text;
end;
$fn$;

-- Posição: retirar (sem desalocar) ------------------------------------------------------------
create function public.editor_remove_pokedex_position_assignment(
  p_collection_id    uuid,
  p_physical_card_id uuid
)
returns table (pokedex_position_id uuid, operation text)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_uid   uuid := (select auth.uid());
  v_owner uuid;
  v_alloc uuid;
  v_cur   uuid;
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_physical_card_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  v_owner := public.assert_collection_editor(p_collection_id);
  perform public.editor_pokedex_of_collection(p_collection_id);

  select ca.id into v_alloc
  from public.collection_allocation ca
  where ca.physical_card_id = p_physical_card_id and ca.collection_id = p_collection_id
  for update;
  if v_alloc is null then
    raise exception 'PHYSICAL_CARD_NOT_ELIGIBLE' using errcode = 'P0002';
  end if;

  delete from public.collection_pokedex_position_assignment a
  where a.collection_allocation_id = v_alloc
  returning a.pokedex_position_id into v_cur;
  return query select v_cur, case when v_cur is null then 'UNCHANGED' else 'REMOVED' end::text;
end;
$fn$;

-- Representante: escolher entre exemplares de X com posição ------------------------------------
create function public.editor_set_pokedex_position_primary_representative(
  p_collection_id    uuid,
  p_physical_card_id uuid
)
returns table (pokedex_position_id uuid, operation text)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_uid   uuid := (select auth.uid());
  v_owner uuid;
  v_alloc uuid;
  v_pos   uuid;
  v_prev  uuid;
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_physical_card_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  v_owner := public.assert_collection_editor(p_collection_id);
  perform public.editor_pokedex_of_collection(p_collection_id);

  select ca.id into v_alloc
  from public.collection_allocation ca
  where ca.physical_card_id = p_physical_card_id and ca.collection_id = p_collection_id
  for update;
  if v_alloc is null then
    raise exception 'PHYSICAL_CARD_NOT_ELIGIBLE' using errcode = 'P0002';
  end if;

  select a.pokedex_position_id into v_pos
  from public.collection_pokedex_position_assignment a
  where a.collection_allocation_id = v_alloc;
  if v_pos is null then
    raise exception 'POKEDEX_ASSIGNMENT_NOT_FOUND' using errcode = '22023';
  end if;

  select r.collection_allocation_id into v_prev
  from public.collection_pokedex_position_primary_representative r
  where r.collection_id = p_collection_id and r.pokedex_position_id = v_pos
  for update;
  if v_prev = v_alloc then
    return query select v_pos, 'UNCHANGED'::text;
    return;
  end if;

  insert into public.collection_pokedex_position_primary_representative
    (collection_id, pokedex_position_id, collection_allocation_id)
  values (p_collection_id, v_pos, v_alloc)
  on conflict on constraint pk_collection_pokedex_position_primary_representative
  do update set collection_allocation_id = excluded.collection_allocation_id;

  return query select v_pos, case when v_prev is null then 'SET' else 'REPLACED' end::text;
end;
$fn$;

-- Representante: limpar ------------------------------------------------------------------------
create function public.editor_clear_pokedex_position_primary_representative(
  p_collection_id       uuid,
  p_pokedex_position_id uuid
)
returns table (pokedex_position_id uuid, operation text)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_uid   uuid := (select auth.uid());
  v_owner uuid;
  v_n     integer;
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_pokedex_position_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  v_owner := public.assert_collection_editor(p_collection_id);
  perform public.editor_pokedex_of_collection(p_collection_id);

  delete from public.collection_pokedex_position_primary_representative r
  where r.collection_id = p_collection_id and r.pokedex_position_id = p_pokedex_position_id;
  get diagnostics v_n = row_count;
  return query select p_pokedex_position_id, case when v_n = 0 then 'UNCHANGED' else 'CLEARED' end::text;
end;
$fn$;

comment on function public.editor_pokedex_of_collection(uuid) is
  'V1-13 E1-B3 (5380, interna): Pokédex referenciada pela coleção; NOT_POKEDEX_COLLECTION (22023) se a coleção não for Pokédex.';
comment on function public.editor_set_pokedex_position_assignment(uuid, uuid, uuid, boolean) is
  'V1-13 E1-B3 (5380): EDITOR cria ou move a posição Pokédex de um exemplar já alocado à coleção (espelho da 6122). Não aloca nem desaloca.';
comment on function public.editor_remove_pokedex_position_assignment(uuid, uuid) is
  'V1-13 E1-B3 (5380): EDITOR retira a posição Pokédex de um exemplar da coleção, sem desalocar (espelho da 6124). Sem posição → UNCHANGED.';
comment on function public.editor_set_pokedex_position_primary_representative(uuid, uuid) is
  'V1-13 E1-B3 (5380): EDITOR escolhe o representante da posição entre exemplares da coleção com posição (espelho da 6125/6126).';
comment on function public.editor_clear_pokedex_position_primary_representative(uuid, uuid) is
  'V1-13 E1-B3 (5380): EDITOR remove o representante de uma posição da coleção (espelho do clear da 6125). Sem representante → UNCHANGED.';

revoke all on function public.editor_pokedex_of_collection(uuid) from public, anon, authenticated, service_role;
revoke all on function public.editor_set_pokedex_position_assignment(uuid, uuid, uuid, boolean) from public, anon;
revoke all on function public.editor_remove_pokedex_position_assignment(uuid, uuid) from public, anon;
revoke all on function public.editor_set_pokedex_position_primary_representative(uuid, uuid) from public, anon;
revoke all on function public.editor_clear_pokedex_position_primary_representative(uuid, uuid) from public, anon;
grant execute on function public.editor_set_pokedex_position_assignment(uuid, uuid, uuid, boolean) to authenticated;
grant execute on function public.editor_remove_pokedex_position_assignment(uuid, uuid) to authenticated;
grant execute on function public.editor_set_pokedex_position_primary_representative(uuid, uuid) to authenticated;
grant execute on function public.editor_clear_pokedex_position_primary_representative(uuid, uuid) to authenticated;

do $post$
declare
  f oid;
begin
  foreach f in array array[to_regprocedure('public.editor_set_pokedex_position_assignment(uuid, uuid, uuid, boolean)'),
                           to_regprocedure('public.editor_remove_pokedex_position_assignment(uuid, uuid)'),
                           to_regprocedure('public.editor_set_pokedex_position_primary_representative(uuid, uuid)'),
                           to_regprocedure('public.editor_clear_pokedex_position_primary_representative(uuid, uuid)')] loop
    if f is null
       or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
       or (select p.proconfig from pg_catalog.pg_proc p where p.oid = f) is distinct from array['search_path=""']
       or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not true
       or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false then
      raise exception 'POSTCHECK 5380: RPC do EDITOR fora do estado esperado (%)', f;
    end if;
  end loop;
  f := to_regprocedure('public.editor_pokedex_of_collection(uuid)');
  if f is null
     or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not false
     or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false
     or pg_catalog.has_function_privilege('service_role', f, 'EXECUTE') is not false then
    raise exception 'POSTCHECK 5380: ajudante interno fora do estado esperado';
  end if;
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.set_pokedex_position_assignment(uuid, uuid, boolean)')) is distinct from '8c572182a03025503e993e5ecc25e07a'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
          where p.oid = to_regprocedure('public.remove_pokedex_position_assignment(uuid)')) is distinct from '26ef2d5da3312661111df0194dfc8ba2'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
          where p.oid = to_regprocedure('public.set_pokedex_position_primary_representative(uuid)')) is distinct from '6353dffe6c3877967997033dcc2bfd4c'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
          where p.oid = to_regprocedure('public.clear_pokedex_position_primary_representative(uuid, uuid)')) is distinct from 'eeede3a5b871fbf07f81eb59ecea932f' then
    raise exception 'POSTCHECK 5380: funções do titular da Pokédex mudaram';
  end if;
end;
$post$;

-- @@T7 5381 (auditada) sha256=f48421892a73d4ce37c8b575ee003a74abca385fe3f18edbff93c3b437d8e3d6
set local lock_timeout = '5s';

do $pre$
begin
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)'))
     is distinct from 'f8cfba40e442e85056e7c8ce7954d4f4' then
    raise exception 'PRECHECK 5381: E1-B3 (5379) não aplicada';
  end if;
  if exists (select 1 from pg_catalog.pg_trigger t
             where t.tgrelid = 'public.binder_activity_event'::regclass and t.tgname = 'trg_bae_editor_event_type')
     or to_regprocedure('public.binder_activity_event_editor_type_guard()') is not null then
    raise exception 'PRECHECK 5381: JÁ APLICADA ou ESTADO DIVERGENTE';
  end if;
end;
$pre$;

create function public.binder_activity_event_editor_type_guard()
returns trigger
language plpgsql
set search_path = ''
as $fn$
begin
  if new.actor_user_id is not null and new.actor_user_id is distinct from new.owner_user_id then
    if new.event_type not in ('CARD_PLACED', 'CARD_MOVED', 'CARDS_SWAPPED', 'CARDS_REMOVED',
                              'POCKET_RESERVED', 'RESERVATIONS_RELEASED', 'POCKETS_LOCKED', 'POCKETS_UNLOCKED',
                              'PAGES_ADDED', 'PAGE_REMOVED', 'PAGES_REORDERED')
       or new.source is distinct from 'FICHARIO'
       or new.collection_id is null then
      raise exception 'binder activity: event type not allowed for this actor' using errcode = '42501',
        hint = 'BINDER_ACTIVITY_EVENT_TYPE';
    end if;
  end if;
  return new;
end;
$fn$;

comment on function public.binder_activity_event_editor_type_guard() is
  'V1-13 E1-C (5381): evento novo com ator diferente do titular só com tipo de curadoria da lista fechada, origem FICHARIO e coleção registrada. Titular e legado sem mudança.';

revoke all on function public.binder_activity_event_editor_type_guard() from public, anon, authenticated, service_role;

create trigger trg_bae_editor_event_type
  before insert on public.binder_activity_event
  for each row execute function public.binder_activity_event_editor_type_guard();

do $post$
begin
  if not exists (select 1 from pg_catalog.pg_trigger t
                 where t.tgrelid = 'public.binder_activity_event'::regclass and t.tgname = 'trg_bae_editor_event_type'
                   and t.tgenabled = 'O')
     or pg_catalog.has_function_privilege('authenticated', to_regprocedure('public.binder_activity_event_editor_type_guard()'), 'EXECUTE')
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
          where p.oid = to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)'))
        is distinct from 'f8cfba40e442e85056e7c8ce7954d4f4' then
    raise exception 'POSTCHECK 5381: gatilho fora do estado esperado';
  end if;
end;
$post$;

-- @@T7 5382 (protegida) sha256=57799a0a86f6a9dea03837aaf52fda9c2555c02f122a1088ca80976f6ab4e94c
set local lock_timeout = '5s';

do $pre$
begin
  if to_regprocedure('public.v1_13_assert_capability()') is null or to_regprocedure('public.v1_13_capability_open()') is null then raise exception 'PRECHECK G1: barreira 5389 ausente'; end if;  -- G1 (D-E1)
  if to_regprocedure('public.assert_collection_binder_editor(uuid)') is null
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
          where p.oid = to_regprocedure('public.binder_slot_editor_scope(uuid, uuid, uuid, uuid)'))
        is distinct from '21f1b51a3a0f6c80337c2c593cc6054f'
     or not exists (select 1 from pg_catalog.pg_trigger t
                    where t.tgrelid = 'public.binder_activity_event'::regclass and t.tgname = 'trg_bae_editor_event_type') then
    raise exception 'PRECHECK 5382: E1-B1, E1-B3 (5378) ou 5381 não aplicadas';
  end if;
  if to_regprocedure('public.assert_collection_binder_editor_exclusive(uuid)') is not null
     or to_regprocedure('public.editor_add_binder_page(uuid)') is not null
     or to_regprocedure('public.editor_remove_binder_page(uuid, integer, integer)') is not null
     or to_regprocedure('public.editor_reorder_binder_pages(uuid, integer[])') is not null then
    raise exception 'PRECHECK 5382: JÁ APLICADA ou ESTADO DIVERGENTE';
  end if;
end;
$pre$;

-- Ajudante interno: fichário exclusivo da coleção autorizada ---------------------------------
create function public.assert_collection_binder_editor_exclusive(p_collection_id uuid)
returns table (layout_id uuid, owner_user_id uuid, container_id uuid)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  r record;
begin
  select * into r from public.assert_collection_binder_editor(p_collection_id) a;
  if r.anchor_collection_id is distinct from p_collection_id
     or exists (select 1 from public.collection_layout_guest g where g.layout_id = r.layout_id) then
    raise exception 'OPERATION_RESERVED_TO_OWNER' using errcode = '42501',
      hint = 'num fichário com mais de uma coleção, esta operação é do titular';
  end if;
  return query select r.layout_id, r.owner_user_id, r.container_id;
end;
$fn$;

-- Adicionar página --------------------------------------------------------------------------
create function public.editor_add_binder_page(p_collection_id uuid)
returns table (page_number integer, slots_created integer)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_layout uuid;
  v_rows   integer;
  v_cols   integer;
  v_next   integer;
  v_page   uuid;
  v_n      integer;
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  select x.layout_id into v_layout from public.assert_collection_binder_editor_exclusive(p_collection_id) x;

  select l.grid_rows, l.grid_columns into v_rows, v_cols
  from public.collection_layout l where l.id = v_layout;
  select coalesce(max(p.page_number), 0) + 1 into v_next
  from public.collection_layout_page p where p.layout_id = v_layout;

  perform public.binder_activity_begin(v_layout, 'PAGES_ADDED', 'FICHARIO', p_collection_id);
  insert into public.collection_layout_page as clp (layout_id, page_number)
  values (v_layout, v_next)
  returning clp.id into v_page;
  insert into public.collection_layout_slot (page_id, row_index, column_index)
  select v_page, r, c
  from generate_series(1, v_rows) as r
  cross join generate_series(1, v_cols) as c;
  get diagnostics v_n = row_count;
  if v_n <> v_rows * v_cols then
    raise exception 'inconsistência estrutural: % bolsos criados, esperado %', v_n, v_rows * v_cols;
  end if;
  perform public.binder_activity_add_item('PAGE', 'PAGE_ADDED', null, null, null, null, null, v_next);
  perform public.binder_activity_end();

  return query select v_next, v_n;
end;
$fn$;

-- Remover página vazia ------------------------------------------------------------------------
create function public.editor_remove_binder_page(
  p_collection_id              uuid,
  p_page_number                integer,
  p_confirm_species_references integer default null
)
returns table (removed_page_number integer, species_references_removed integer)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_layout uuid;
  v_page   uuid;
  v_n      integer;
  v_refs   integer;
  v_renum  record;
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  if p_page_number is null or p_page_number < 1 then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  select x.layout_id into v_layout from public.assert_collection_binder_editor_exclusive(p_collection_id) x;

  select p.id into v_page
  from public.collection_layout_page p
  where p.layout_id = v_layout and p.page_number = p_page_number
  for update;
  if v_page is null then
    raise exception 'PAGE_NOT_FOUND' using errcode = 'P0002';
  end if;

  select count(*) into v_n from public.collection_layout_page p where p.layout_id = v_layout;
  if v_n <= 1 then
    raise exception 'BINDER_MUST_KEEP_ONE_PAGE' using errcode = '55000';
  end if;

  -- Conteúdo que não é de X em qualquer bolso da página (carta de outra coleção ou
  -- sem coleção — inclusive de convidada já desassociada, cujas posições ficam (5253) —,
  -- reserva de outra coleção, imagem ou mesclagem do titular, trava sem conteúdo de X,
  -- referência de outra coleção): recusa da C-237, "reservada ao titular", sem dizer o quê.
  if exists (select 1 from public.collection_layout_slot s
             where s.page_id = v_page
               and public.binder_slot_editor_scope(v_layout, p_collection_id, p_collection_id, s.id) = 'FOREIGN') then
    raise exception 'OPERATION_RESERVED_TO_OWNER' using errcode = '42501',
      hint = 'esta página tem conteúdo que só o titular pode retirar';
  end if;
  -- Conteúdo de X (carta, reserva, trava): o EDITOR pode esvaziar antes.
  if exists (select 1 from public.collection_layout_slot_assignment a
             join public.collection_layout_slot s on s.id = a.slot_id where s.page_id = v_page)
     or exists (select 1 from public.collection_layout_slot_expected_content e
                join public.collection_layout_slot s on s.id = e.slot_id where s.page_id = v_page)
     or exists (select 1 from public.collection_layout_region rg where rg.page_id = v_page)
     or exists (select 1 from public.collection_layout_slot_image i
                join public.collection_layout_slot s on s.id = i.slot_id where s.page_id = v_page)
     or exists (select 1 from public.collection_layout_slot s where s.page_id = v_page and s.locked) then
    raise exception 'PAGE_NOT_EMPTY' using errcode = '55000',
      hint = 'esvazie a página antes de removê-la';
  end if;

  -- Referências de espécie: só da Pokédex proprietária (= X, 5257); confirmar a contagem.
  select count(*)::integer into v_refs
  from public.collection_layout_slot_species_reference sr
  join public.collection_layout_slot s on s.id = sr.slot_id
  where s.page_id = v_page and sr.layout_id = v_layout and sr.collection_id = p_collection_id;
  if v_refs > 0 and p_confirm_species_references is distinct from v_refs then
    raise exception 'SPECIES_REFERENCES_ON_PAGE' using errcode = 'P0001',
      hint = 'SPECIES_REFERENCES_ON_PAGE:' || v_refs;
  end if;

  perform public.binder_activity_begin(v_layout, 'PAGE_REMOVED', 'FICHARIO', p_collection_id);
  perform public.binder_activity_add_item('PAGE', 'PAGE_REMOVED', null, null, null, null, p_page_number, null,
                                          case when v_refs > 0 then jsonb_build_object('species_references_removed', v_refs) end);
  for v_renum in
    select p.page_number as n from public.collection_layout_page p
    where p.layout_id = v_layout and p.page_number > p_page_number
    order by p.page_number
  loop
    perform public.binder_activity_add_item('PAGE', 'PAGE_RENUMBERED', null, null, null, null, v_renum.n, v_renum.n - 1);
  end loop;
  delete from public.collection_layout_slot_species_reference sr
  using public.collection_layout_slot s
  where s.id = sr.slot_id and s.page_id = v_page;
  delete from public.collection_layout_page p where p.id = v_page;
  update public.collection_layout_page p
     set page_number = p.page_number - 1
   where p.layout_id = v_layout and p.page_number > p_page_number;
  perform public.binder_activity_end();

  return query select p_page_number, v_refs;
end;
$fn$;

-- Reordenar páginas ---------------------------------------------------------------------------
create function public.editor_reorder_binder_pages(
  p_collection_id         uuid,
  p_page_numbers_ordered  integer[]
)
returns table (page_number integer, previous_page_number integer)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_layout uuid;
  v_total  integer;
  r        record;
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  if p_page_numbers_ordered is null or cardinality(p_page_numbers_ordered) = 0
     or array_ndims(p_page_numbers_ordered) <> 1 then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  select x.layout_id into v_layout from public.assert_collection_binder_editor_exclusive(p_collection_id) x;

  -- Todas as páginas, em ordem determinística (igual à 5282), antes de validar.
  perform 1 from public.collection_layout_page p where p.layout_id = v_layout order by p.id for update;
  select count(*) into v_total from public.collection_layout_page p where p.layout_id = v_layout;
  if cardinality(p_page_numbers_ordered) <> v_total
     or (select count(distinct x) from unnest(p_page_numbers_ordered) x) <> v_total
     or exists (select 1 from unnest(p_page_numbers_ordered) x where x is null or x < 1 or x > v_total) then
    raise exception 'INVALID_PAGE_ORDER' using errcode = '22023',
      hint = 'informe cada página atual do fichário exatamente uma vez';
  end if;

  if exists (select 1 from unnest(p_page_numbers_ordered) with ordinality u(old_n, ord) where u.old_n <> u.ord) then
    perform public.binder_activity_begin(v_layout, 'PAGES_REORDERED', 'FICHARIO', p_collection_id);
    for r in
      select u.old_n, u.ord::integer as new_n
      from unnest(p_page_numbers_ordered) with ordinality u(old_n, ord)
      where u.old_n <> u.ord
      order by u.ord
    loop
      perform public.binder_activity_add_item('PAGE', 'PAGE_RENUMBERED', null, null, null, null, r.old_n, r.new_n);
    end loop;
    update public.collection_layout_page p
       set page_number = src.new_n
      from (select u.old_n, u.ord::integer as new_n
              from unnest(p_page_numbers_ordered) with ordinality u(old_n, ord)) src
     where p.layout_id = v_layout and p.page_number = src.old_n;
    perform public.binder_activity_end();
  end if;

  return query
  select src.new_n, src.old_n
  from (select u.old_n, u.ord::integer as new_n
          from unnest(p_page_numbers_ordered) with ordinality u(old_n, ord)) src
  order by src.new_n;
end;
$fn$;

comment on function public.assert_collection_binder_editor_exclusive(uuid) is
  'V1-13 E1-C (5382, interna): autoriza o EDITOR como a 5371 e exige fichário exclusivo da coleção (proprietária, sem convidadas); senão OPERATION_RESERVED_TO_OWNER.';
comment on function public.editor_add_binder_page(uuid) is
  'V1-13 E1-C (5382): EDITOR adiciona página vazia no fim do fichário exclusivo da coleção (espelho da 5280).';
comment on function public.editor_remove_binder_page(uuid, integer, integer) is
  'V1-13 E1-C (5382): EDITOR remove página totalmente vazia do fichário exclusivo da coleção (espelho da 5286); referências de espécie de X exigem a contagem.';
comment on function public.editor_reorder_binder_pages(uuid, integer[]) is
  'V1-13 E1-C (5382): EDITOR reordena páginas inteiras do fichário exclusivo da coleção, por número (espelho da 5282).';

revoke all on function public.assert_collection_binder_editor_exclusive(uuid) from public, anon, authenticated, service_role;
revoke all on function public.editor_add_binder_page(uuid) from public, anon;
revoke all on function public.editor_remove_binder_page(uuid, integer, integer) from public, anon;
revoke all on function public.editor_reorder_binder_pages(uuid, integer[]) from public, anon;
grant execute on function public.editor_add_binder_page(uuid) to authenticated;
grant execute on function public.editor_remove_binder_page(uuid, integer, integer) to authenticated;
grant execute on function public.editor_reorder_binder_pages(uuid, integer[]) to authenticated;

do $post$
declare
  f oid;
begin
  foreach f in array array[to_regprocedure('public.editor_add_binder_page(uuid)'),
                           to_regprocedure('public.editor_remove_binder_page(uuid, integer, integer)'),
                           to_regprocedure('public.editor_reorder_binder_pages(uuid, integer[])')] loop
    if f is null
       or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
       or (select p.proconfig from pg_catalog.pg_proc p where p.oid = f) is distinct from array['search_path=""']
       or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not true
       or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false then
      raise exception 'POSTCHECK 5382: RPC fora do estado esperado (%)', f;
    end if;
  end loop;
  f := to_regprocedure('public.assert_collection_binder_editor_exclusive(uuid)');
  if f is null
     or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not false
     or pg_catalog.has_function_privilege('service_role', f, 'EXECUTE') is not false then
    raise exception 'POSTCHECK 5382: ajudante interno fora do estado esperado';
  end if;
end;
$post$;

-- @@T7 5383 (protegida) sha256=b7c5d9c51fd03c8872f42a21bd998c539456f633e7b814e5809c1a763fd11245
set local lock_timeout = '5s';

do $pre$
begin
  if to_regprocedure('public.v1_13_assert_capability()') is null or to_regprocedure('public.v1_13_capability_open()') is null then raise exception 'PRECHECK G1: barreira 5389 ausente'; end if;  -- G1 (D-E1)
  if to_regprocedure('public.binder_species_reference_plan(uuid, uuid, uuid, text)') is null
     or to_regprocedure('public.assert_collection_binder_editor_exclusive(uuid)') is null then
    raise exception 'PRECHECK 5383: 5258 ou 5382 ausentes';
  end if;
  if to_regprocedure('public.editor_species_reference_summary(uuid, uuid, uuid, text, uuid)') is not null
     or to_regprocedure('public.editor_preview_binder_species_references(uuid)') is not null
     or to_regprocedure('public.editor_apply_binder_species_references(uuid, text)') is not null
     or to_regprocedure('public.editor_clear_binder_species_references(uuid, integer)') is not null
     or to_regprocedure('public.editor_set_binder_species_reference_visibility(uuid, boolean)') is not null then
    raise exception 'PRECHECK 5383: JÁ APLICADA ou ESTADO DIVERGENTE';
  end if;
end;
$pre$;

-- Ajudante interno: resumo do plano canônico (mesma fórmula de token da 5258) ---------------
create function public.editor_species_reference_summary(
  p_layout_id               uuid,
  p_pokedex_id              uuid,
  p_collection_reference_id uuid,
  p_scope_kind              text,
  p_collection_id           uuid
)
returns table (
  positions_in_scope integer, slots_total integer, pair_count integer,
  first_page integer, last_page integer, first_number integer, last_number integer,
  existing_count integer, already_applied boolean, plan_token text
)
language plpgsql
stable
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_pos integer; v_slots integer; v_pairs integer; v_fp integer; v_lp integer;
  v_fn integer; v_ln integer; v_existing integer; v_token text;
begin
  select count(*)::integer into v_pos
  from public.pokedex_position pp
  join public.pokemon_species sp on sp.id = pp.species_id
  where pp.pokedex_id = p_pokedex_id
    and (p_scope_kind = 'FULL_REFERENCE'
         or exists (select 1 from public.collection_pokedex_scope_generation sg
                    where sg.collection_reference_id = p_collection_reference_id
                      and sg.generation_id = sp.generation_id));
  select count(*)::integer into v_slots
  from public.collection_layout_page pg
  join public.collection_layout_slot s on s.page_id = pg.id
  where pg.layout_id = p_layout_id;
  select count(*)::integer, min(p.page_number), max(p.page_number), min(p.position_number), max(p.position_number),
         encode(sha256(convert_to(p_layout_id::text || '|' ||
                coalesce(string_agg(p.slot_id::text || ':' || p.pokedex_position_id::text, ',' order by p.ord), ''), 'UTF8')), 'hex')
    into v_pairs, v_fp, v_lp, v_fn, v_ln, v_token
  from public.binder_species_reference_plan(p_layout_id, p_pokedex_id, p_collection_reference_id, p_scope_kind) p;
  select count(*)::integer into v_existing
  from public.collection_layout_slot_species_reference r where r.layout_id = p_layout_id;

  return query select v_pos, v_slots, v_pairs, v_fp, v_lp, v_fn, v_ln, v_existing,
    (v_existing = v_pairs and v_pairs > 0 and not exists (
       select 1 from public.binder_species_reference_plan(p_layout_id, p_pokedex_id, p_collection_reference_id, p_scope_kind) p
       where not exists (select 1 from public.collection_layout_slot_species_reference r
                         where r.slot_id = p.slot_id and r.pokedex_position_id = p.pokedex_position_id
                           and r.collection_id = p_collection_id))),
    v_token;
end;
$fn$;

-- Prévia (leitura, sem trava) ----------------------------------------------------------------
create function public.editor_preview_binder_species_references(p_collection_id uuid)
returns table (
  positions_in_scope integer, slots_total integer, pair_count integer, slots_left_free integer,
  positions_unplaced integer, first_page integer, last_page integer, first_number integer,
  last_number integer, existing_count integer, already_applied boolean, plan_token text
)
language plpgsql
stable
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_uid    uuid := (select auth.uid());
  v_status text;
  v_layout uuid;
  t        record;
  s        record;
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  select c.lifecycle_status into v_status
  from public.collection c
  join public.collection_membership m
    on m.collection_id = c.id and m.user_id = v_uid and m.status = 'ACTIVE' and m.role = 'EDITOR'
  where c.id = p_collection_id and c.owner_user_id <> v_uid;
  if v_status is null then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;
  select l.id into v_layout from public.collection_layout l where l.collection_id = p_collection_id;
  if v_layout is null then
    if exists (select 1 from public.collection_layout_guest g where g.collection_id = p_collection_id) then
      raise exception 'OPERATION_RESERVED_TO_OWNER' using errcode = '42501',
        hint = 'num fichário com mais de uma coleção, esta operação é do titular';
    end if;
    raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
  end if;
  if exists (select 1 from public.collection_layout_guest g where g.layout_id = v_layout)
     or exists (select 1 from public.collection_layout_slot_species_reference r
                where r.layout_id = v_layout and r.collection_id <> p_collection_id) then
    raise exception 'OPERATION_RESERVED_TO_OWNER' using errcode = '42501',
      hint = 'num fichário com mais de uma coleção, esta operação é do titular';
  end if;
  if v_status <> 'ACTIVE' then
    raise exception 'COLLECTION_ARCHIVED' using errcode = '55000';
  end if;
  select cpr.pokedex_id, cr.id as ref_id, cpr.scope_kind::text as scope_kind into t
  from public.collection c
  join public.collection_reference cr on cr.collection_id = c.id and cr.reference_kind = 'POKEDEX'
  join public.collection_pokedex_reference cpr on cpr.collection_reference_id = cr.id
  where c.id = p_collection_id and c.mode = 'REFERENCE_BASED' and c.completion_policy = 'REFERENCE_POSITION';
  if t.pokedex_id is null then
    raise exception 'NOT_POKEDEX_COLLECTION' using errcode = '22023';
  end if;

  select * into s from public.editor_species_reference_summary(v_layout, t.pokedex_id, t.ref_id, t.scope_kind, p_collection_id);
  return query select s.positions_in_scope, s.slots_total, s.pair_count, s.slots_total - s.pair_count,
                      s.positions_in_scope - s.pair_count, s.first_page, s.last_page, s.first_number, s.last_number,
                      s.existing_count, s.already_applied, s.plan_token;
end;
$fn$;

-- Ajudante interno de escrita: trava (5382) + Pokédex ----------------------------------------
create function public.editor_species_reference_target_locked(p_collection_id uuid)
returns table (layout_id uuid, pokedex_id uuid, collection_reference_id uuid, scope_kind text)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_layout uuid;
begin
  select x.layout_id into v_layout from public.assert_collection_binder_editor_exclusive(p_collection_id) x;
  -- Referências registradas para OUTRA coleção (proprietária anterior: a 5254 não as
  -- move) são de terceiros: o EDITOR não as apaga, não as esconde e não aplica sobre elas.
  if exists (select 1 from public.collection_layout_slot_species_reference r
             where r.layout_id = v_layout and r.collection_id <> p_collection_id) then
    raise exception 'OPERATION_RESERVED_TO_OWNER' using errcode = '42501',
      hint = 'este fichário tem referências que só o titular pode alterar';
  end if;
  return query
  select v_layout, cpr.pokedex_id, cr.id, cpr.scope_kind::text
  from public.collection c
  join public.collection_reference cr on cr.collection_id = c.id and cr.reference_kind = 'POKEDEX'
  join public.collection_pokedex_reference cpr on cpr.collection_reference_id = cr.id
  where c.id = p_collection_id and c.mode = 'REFERENCE_BASED' and c.completion_policy = 'REFERENCE_POSITION';
  if not found then
    raise exception 'NOT_POKEDEX_COLLECTION' using errcode = '22023';
  end if;
end;
$fn$;

-- Aplicar ---------------------------------------------------------------------------------------
create function public.editor_apply_binder_species_references(p_collection_id uuid, p_plan_token text)
returns table (operation text, reference_count integer, references_visible boolean)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  t       record;
  s       record;
  v_op    text;
  v_count integer;
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  if p_plan_token is null or p_plan_token !~ '^[0-9a-f]{64}$' then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  select * into t from public.editor_species_reference_target_locked(p_collection_id);
  select * into s from public.editor_species_reference_summary(t.layout_id, t.pokedex_id, t.collection_reference_id, t.scope_kind, p_collection_id);
  if s.plan_token <> p_plan_token then
    raise exception 'PLAN_CHANGED' using errcode = 'P0001',
      hint = 'o fichário mudou desde a prévia; revise e confirme de novo';
  end if;
  if s.already_applied then
    v_op := 'ALREADY_APPLIED';
  else
    if s.existing_count > 0 then
      raise exception 'SPECIES_REFERENCES_PRESENT' using errcode = 'P0001',
        hint = 'este fichário já tem referências; remova-as antes de aplicar de novo';
    end if;
    if s.pair_count = 0 then
      raise exception 'NOTHING_TO_APPLY' using errcode = 'P0001';
    end if;
    insert into public.collection_layout_slot_species_reference
      (slot_id, layout_id, collection_id, pokedex_position_id, source)
    select p.slot_id, t.layout_id, p_collection_id, p.pokedex_position_id, 'NATIONAL_ORDER'
    from public.binder_species_reference_plan(t.layout_id, t.pokedex_id, t.collection_reference_id, t.scope_kind) p;
    v_op := 'APPLIED';
  end if;
  insert into public.collection_layout_species_reference_setting as st (layout_id, references_visible, updated_at)
  values (t.layout_id, true, now())
  on conflict on constraint pk_cl_species_reference_setting
  do update set references_visible = true, updated_at = now()
  where st.references_visible is distinct from true;
  select count(*)::integer into v_count
  from public.collection_layout_slot_species_reference r where r.layout_id = t.layout_id;
  return query select v_op, v_count, true;
end;
$fn$;

-- Remover ---------------------------------------------------------------------------------------
create function public.editor_clear_binder_species_references(p_collection_id uuid, p_expected_count integer)
returns table (operation text, removed_count integer)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  t         record;
  v_current integer;
  v_removed integer;
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  if p_expected_count is null or p_expected_count < 0 then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  select * into t from public.editor_species_reference_target_locked(p_collection_id);
  select count(*)::integer into v_current
  from public.collection_layout_slot_species_reference r
  where r.layout_id = t.layout_id and r.collection_id = p_collection_id;
  if v_current <> p_expected_count then
    raise exception 'COUNT_MISMATCH' using errcode = 'P0001',
      hint = format('o fichário tem %s referências; revise antes de remover', v_current);
  end if;
  delete from public.collection_layout_slot_species_reference r
  where r.layout_id = t.layout_id and r.collection_id = p_collection_id;
  get diagnostics v_removed = row_count;
  return query select 'REMOVED'::text, v_removed;
end;
$fn$;

-- Mostrar / ocultar -----------------------------------------------------------------------------
create function public.editor_set_binder_species_reference_visibility(p_collection_id uuid, p_visible boolean)
returns table (references_visible boolean, operation text)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  t         record;
  v_current boolean;
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  if p_visible is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  select * into t from public.editor_species_reference_target_locked(p_collection_id);
  select st.references_visible into v_current
  from public.collection_layout_species_reference_setting st
  where st.layout_id = t.layout_id
  for update;
  if coalesce(v_current, true) = p_visible then
    return query select p_visible, 'UNCHANGED'::text;
    return;
  end if;
  insert into public.collection_layout_species_reference_setting (layout_id, references_visible, updated_at)
  values (t.layout_id, p_visible, now())
  on conflict on constraint pk_cl_species_reference_setting
  do update set references_visible = excluded.references_visible, updated_at = now();
  return query select p_visible, 'UPDATED'::text;
end;
$fn$;

comment on function public.editor_species_reference_summary(uuid, uuid, uuid, text, uuid) is
  'V1-13 E1-C (5383, interna): resumo do plano canônico de referências de espécie (5258) para o EDITOR, com o mesmo token.';
comment on function public.editor_species_reference_target_locked(uuid) is
  'V1-13 E1-C (5383, interna): trava como a 5382 (fichário exclusivo) e devolve a Pokédex de X; NOT_POKEDEX_COLLECTION se não for.';
comment on function public.editor_preview_binder_species_references(uuid) is
  'V1-13 E1-C (5383): prévia das referências de espécie para o EDITOR do fichário exclusivo da Pokédex; sem contagem de bolsos ocupados.';
comment on function public.editor_apply_binder_species_references(uuid, text) is
  'V1-13 E1-C (5383): EDITOR aplica as referências de espécie no fichário exclusivo da Pokédex (espelho da 5258).';
comment on function public.editor_clear_binder_species_references(uuid, integer) is
  'V1-13 E1-C (5383): EDITOR remove as referências de espécie do fichário exclusivo da Pokédex, com a contagem atual (espelho da 5258).';
comment on function public.editor_set_binder_species_reference_visibility(uuid, boolean) is
  'V1-13 E1-C (5383): EDITOR mostra/oculta as referências no fichário exclusivo da Pokédex (espelho da 5258); nunca apaga vínculos.';

revoke all on function public.editor_species_reference_summary(uuid, uuid, uuid, text, uuid) from public, anon, authenticated, service_role;
revoke all on function public.editor_species_reference_target_locked(uuid) from public, anon, authenticated, service_role;
revoke all on function public.editor_preview_binder_species_references(uuid) from public, anon;
revoke all on function public.editor_apply_binder_species_references(uuid, text) from public, anon;
revoke all on function public.editor_clear_binder_species_references(uuid, integer) from public, anon;
revoke all on function public.editor_set_binder_species_reference_visibility(uuid, boolean) from public, anon;
grant execute on function public.editor_preview_binder_species_references(uuid) to authenticated;
grant execute on function public.editor_apply_binder_species_references(uuid, text) to authenticated;
grant execute on function public.editor_clear_binder_species_references(uuid, integer) to authenticated;
grant execute on function public.editor_set_binder_species_reference_visibility(uuid, boolean) to authenticated;

do $post$
declare
  f oid;
begin
  foreach f in array array[to_regprocedure('public.editor_preview_binder_species_references(uuid)'),
                           to_regprocedure('public.editor_apply_binder_species_references(uuid, text)'),
                           to_regprocedure('public.editor_clear_binder_species_references(uuid, integer)'),
                           to_regprocedure('public.editor_set_binder_species_reference_visibility(uuid, boolean)')] loop
    if f is null
       or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
       or (select p.proconfig from pg_catalog.pg_proc p where p.oid = f) is distinct from array['search_path=""']
       or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not true
       or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false then
      raise exception 'POSTCHECK 5383: RPC fora do estado esperado (%)', f;
    end if;
  end loop;
  foreach f in array array[to_regprocedure('public.editor_species_reference_summary(uuid, uuid, uuid, text, uuid)'),
                           to_regprocedure('public.editor_species_reference_target_locked(uuid)')] loop
    if f is null
       or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not false
       or pg_catalog.has_function_privilege('service_role', f, 'EXECUTE') is not false then
      raise exception 'POSTCHECK 5383: ajudante interno fora do estado esperado (%)', f;
    end if;
  end loop;
end;
$post$;

-- @@T7 5384 (auditada) sha256=9b944466cb7c7eca95c582ac1214e171ce0511ea4a069f28934b45c9e60d1549
set local lock_timeout = '5s';

do $pre$
declare
  v_m text := (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
               where p.oid = to_regprocedure('public.binder_activity_event_editor_type_guard()'));
begin
  if v_m = '78fa0d34dad161eac1165f3143874260' then
    raise exception 'PRECHECK 5384: JÁ APLICADA — não reaplicar';
  end if;
  if v_m is distinct from 'b5da9a1258f26e53f31c206c5d5c442b' then
    raise exception 'PRECHECK 5384: ESTADO DIVERGENTE — corpo vigente difere da 5381 (%)', v_m;
  end if;
end;
$pre$;

create or replace function public.binder_activity_event_editor_type_guard()
returns trigger
language plpgsql
set search_path = ''
as $fn$
begin
  if new.actor_user_id is not null and new.actor_user_id is distinct from new.owner_user_id then
    if new.collection_id is null
       or not (
         (new.event_type in ('CARD_PLACED', 'CARD_MOVED', 'CARDS_SWAPPED', 'CARDS_REMOVED',
                             'POCKET_RESERVED', 'RESERVATIONS_RELEASED', 'POCKETS_LOCKED', 'POCKETS_UNLOCKED',
                             'PAGES_ADDED', 'PAGE_REMOVED', 'PAGES_REORDERED',
                             'GAP_OPENED', 'GAP_CLOSED', 'CARDS_AUTO_ARRANGED')
          and new.source = 'FICHARIO')
         or (new.event_type = 'CATALOG_NOVELTIES_INCORPORATED' and new.source = 'CATALOGO')) then
      raise exception 'binder activity: event type not allowed for this actor' using errcode = '42501',
        hint = 'BINDER_ACTIVITY_EVENT_TYPE';
    end if;
  end if;
  return new;
end;
$fn$;

do $post$
begin
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.binder_activity_event_editor_type_guard()')) is distinct from '78fa0d34dad161eac1165f3143874260'
     or not exists (select 1 from pg_catalog.pg_trigger t
                    where t.tgrelid = 'public.binder_activity_event'::regclass and t.tgname = 'trg_bae_editor_event_type'
                      and t.tgenabled = 'O')
     or pg_catalog.has_function_privilege('authenticated', to_regprocedure('public.binder_activity_event_editor_type_guard()'), 'EXECUTE') then
    raise exception 'POSTCHECK 5384: gatilho fora do estado esperado';
  end if;
end;
$post$;

-- @@T7 5385 (protegida) sha256=ec7c3150cad646a4734d3d9d10c644f19a3291c71c49cceac00dbeadc4531add
set local lock_timeout = '5s';

do $pre$
begin
  if to_regprocedure('public.v1_13_assert_capability()') is null or to_regprocedure('public.v1_13_capability_open()') is null then raise exception 'PRECHECK G1: barreira 5389 ausente'; end if;  -- G1 (D-E1)
  if to_regprocedure('public.binder_gap_chain(uuid, uuid)') is null
     or to_regprocedure('public.binder_gap_evaluate(uuid, uuid)') is null
     or to_regprocedure('public.binder_gap_move_pocket(uuid, uuid)') is null
     or to_regprocedure('public.binder_gap_undo_token(uuid, uuid, uuid, uuid)') is null
     or to_regprocedure('public.binder_activity_add_pocket_shift_items(uuid, uuid)') is null
     or to_regprocedure('public.assert_collection_binder_editor_exclusive(uuid)') is null
     or to_regprocedure('public.binder_slot_at(uuid, integer, integer, integer)') is null
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
          where p.oid = to_regprocedure('public.binder_slot_editor_scope(uuid, uuid, uuid, uuid)'))
        is distinct from '21f1b51a3a0f6c80337c2c593cc6054f' then
    raise exception 'PRECHECK 5385: 5243, 5279, E1-B1, 5378 ou E1-C1 (5382) ausentes';
  end if;
  if to_regprocedure('public.editor_binder_exclusive_read(uuid)') is not null
     or to_regprocedure('public.binder_editor_any_foreign(uuid, uuid, uuid[])') is not null
     or to_regprocedure('public.binder_editor_append_page(uuid)') is not null
     or to_regprocedure('public.editor_preview_binder_insert_gap(uuid, integer, integer, integer)') is not null
     or to_regprocedure('public.editor_insert_binder_gap(uuid, integer, integer, integer, text, boolean, boolean)') is not null
     or to_regprocedure('public.editor_close_binder_gap(uuid, integer, integer, integer, integer, integer, integer, text, integer)') is not null then
    raise exception 'PRECHECK 5385: JÁ APLICADA ou ESTADO DIVERGENTE';
  end if;
end;
$pre$;

-- Ajudante: autorização sem trava para as prévias ------------------------------------------
create function public.editor_binder_exclusive_read(p_collection_id uuid)
returns table (layout_id uuid, owner_user_id uuid, container_id uuid)
language plpgsql
stable
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_uid    uuid := (select auth.uid());
  v_owner  uuid;
  v_status text;
  v_layout uuid;
  v_cont   uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  select c.owner_user_id, c.lifecycle_status into v_owner, v_status
  from public.collection c
  join public.collection_membership m
    on m.collection_id = c.id and m.user_id = v_uid and m.status = 'ACTIVE' and m.role = 'EDITOR'
  where c.id = p_collection_id and c.owner_user_id <> v_uid;
  if v_owner is null then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;
  select l.id, l.storage_container_id into v_layout, v_cont
  from public.collection_layout l where l.collection_id = p_collection_id;
  if v_layout is null then
    if exists (select 1 from public.collection_layout_guest g where g.collection_id = p_collection_id) then
      raise exception 'OPERATION_RESERVED_TO_OWNER' using errcode = '42501',
        hint = 'num fichário com mais de uma coleção, esta operação é do titular';
    end if;
    raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
  end if;
  if exists (select 1 from public.collection_layout_guest g where g.layout_id = v_layout) then
    raise exception 'OPERATION_RESERVED_TO_OWNER' using errcode = '42501',
      hint = 'num fichário com mais de uma coleção, esta operação é do titular';
  end if;
  if v_status <> 'ACTIVE' then
    raise exception 'COLLECTION_ARCHIVED' using errcode = '55000';
  end if;
  return query select v_layout, v_owner, v_cont;
end;
$fn$;

-- Ajudante: algum bolso do conjunto é de terceiros? -------------------------------------------
create function public.binder_editor_any_foreign(p_layout_id uuid, p_collection_id uuid, p_slot_ids uuid[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select exists (
    select 1 from unnest(coalesce(p_slot_ids, '{}'::uuid[])) u(sid)
    where u.sid is null
       or public.binder_slot_editor_scope(p_layout_id, p_collection_id, p_collection_id, u.sid) = 'FOREIGN');
$fn$;

-- Ajudante: página nova no fim, dentro do evento aberto --------------------------------------
create function public.binder_editor_append_page(p_layout_id uuid)
returns table (page_id uuid, page_number integer)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_rows integer;
  v_cols integer;
  v_next integer;
  v_page uuid;
  v_n    integer;
begin
  select l.grid_rows, l.grid_columns into v_rows, v_cols
  from public.collection_layout l where l.id = p_layout_id;
  select coalesce(max(p.page_number), 0) + 1 into v_next
  from public.collection_layout_page p where p.layout_id = p_layout_id;
  insert into public.collection_layout_page as clp (layout_id, page_number)
  values (p_layout_id, v_next)
  returning clp.id into v_page;
  insert into public.collection_layout_slot (page_id, row_index, column_index)
  select v_page, r, c
  from generate_series(1, v_rows) as r
  cross join generate_series(1, v_cols) as c;
  get diagnostics v_n = row_count;
  if v_n <> v_rows * v_cols then
    raise exception 'inconsistência estrutural: % bolsos criados, esperado %', v_n, v_rows * v_cols;
  end if;
  perform public.binder_activity_add_item('PAGE', 'PAGE_ADDED', null, null, null, null, null, v_next);
  return query select v_page, v_next;
end;
$fn$;

-- Prévia de inserir espaço ---------------------------------------------------------------------
create function public.editor_preview_binder_insert_gap(
  p_collection_id uuid,
  p_page          integer,
  p_row           integer,
  p_column        integer
)
returns table (
  outcome text, moved_pockets integer, moved_cards integer, moved_reserves integer,
  rows_moved integer, row_limit integer, pages integer[],
  target_page integer, target_row integer, target_column integer, plan_token text
)
language plpgsql
stable
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_layout uuid;
  v_slot   uuid;
  e        record;
  v_set    uuid[];
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  select x.layout_id into v_layout from public.editor_binder_exclusive_read(p_collection_id) x;
  v_slot := public.binder_slot_at(v_layout, p_page, p_row, p_column);
  if v_slot is null then
    raise exception 'SLOT_NOT_FOUND' using errcode = 'P0002';
  end if;
  select * into e from public.binder_gap_evaluate(v_layout, v_slot);
  if e.outcome in ('SAME_PAGE', 'CROSS_PAGE', 'NEEDS_PAGE', 'OVER_LIMIT', 'BLOCKED') then
    select array_agg(c.slot_id) into v_set
    from public.binder_gap_chain(v_layout, v_slot) c
    where c.ord < (select min(c0.ord) from public.binder_gap_chain(v_layout, v_slot) c0) + e.moved_pockets;
    if public.binder_editor_any_foreign(v_layout, p_collection_id,
                                        v_set || case when e.target_slot_id is null then '{}'::uuid[] else array[e.target_slot_id] end) then
      raise exception 'OPERATION_RESERVED_TO_OWNER' using errcode = '42501',
        hint = 'o espaço deslocaria conteúdo que só o titular pode mover';
    end if;
  end if;
  return query
  select e.outcome, e.moved_pockets, e.moved_cards, e.moved_reserves, e.rows_moved, e.row_limit, e.pages,
         tp.page_number, ts.row_index, ts.column_index, e.plan_token
  from (select 1) z
  left join public.collection_layout_slot ts on ts.id = e.target_slot_id
  left join public.collection_layout_page tp on tp.id = ts.page_id;
end;
$fn$;

-- Inserir espaço -------------------------------------------------------------------------------
create function public.editor_insert_binder_gap(
  p_collection_id      uuid,
  p_page               integer,
  p_row                integer,
  p_column             integer,
  p_plan_token         text,
  p_confirm_cross_page boolean default false,
  p_confirm_add_page   boolean default false
)
returns table (
  outcome text, end_page integer, end_row integer, end_column integer, added_page_number integer,
  moved_pockets integer, rows_moved integer, pages integer[], undo_token text
)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_layout uuid;
  v_slot   uuid;
  e        record;
  v_chain  uuid[];
  v_dest   uuid[];
  v_target uuid;
  v_added  uuid;
  v_addn   integer;
  v_rows   integer := 0;
  i        integer;
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  if p_plan_token is null or p_plan_token !~ '^g1:[0-9a-f]{64}$' then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  select x.layout_id into v_layout from public.assert_collection_binder_editor_exclusive(p_collection_id) x;
  v_slot := public.binder_slot_at(v_layout, p_page, p_row, p_column);
  if v_slot is null then
    raise exception 'SLOT_NOT_FOUND' using errcode = 'P0002';
  end if;
  select * into e from public.binder_gap_evaluate(v_layout, v_slot);

  if e.outcome = 'ALREADY_FREE' then
    return query select 'ALREADY_FREE'::text, null::integer, null::integer, null::integer, null::integer,
                        0, 0, null::integer[], null::text;
    return;
  end if;
  if e.outcome = 'NOT_FOUND' then
    raise exception 'SLOT_NOT_FOUND' using errcode = 'P0002';
  end if;
  if e.plan_token is distinct from p_plan_token then
    raise exception 'GAP_PLAN_CHANGED' using errcode = '40001',
      hint = 'o fichário mudou desde a prévia — veja a prévia de novo';
  end if;
  if e.outcome in ('AT_BARRIER', 'BLOCKED') then
    raise exception 'GAP_BLOCKED' using errcode = '55000', hint = 'há um bolso fixado ou mesclado no caminho';
  end if;
  if e.outcome = 'OVER_LIMIT' then
    raise exception 'GAP_OVER_LIMIT' using errcode = '54000',
      hint = format('%s itens excedem o limite de %s por operação', e.rows_moved, e.row_limit);
  end if;
  if e.outcome = 'CROSS_PAGE' and not coalesce(p_confirm_cross_page, false) then
    raise exception 'GAP_CONFIRMATION_REQUIRED' using errcode = '55000', hint = 'CROSS_PAGE';
  end if;
  if e.outcome = 'NEEDS_PAGE' and not coalesce(p_confirm_add_page, false) then
    raise exception 'GAP_CONFIRMATION_REQUIRED' using errcode = '55000', hint = 'ADD_PAGE';
  end if;

  select array_agg(c.slot_id order by c.ord) into v_chain
  from public.binder_gap_chain(v_layout, v_slot) c
  where c.ord < (select min(c0.ord) from public.binder_gap_chain(v_layout, v_slot) c0) + e.moved_pockets;
  if v_chain is null or cardinality(v_chain) <> e.moved_pockets then
    raise exception 'GAP_INCONSISTENT';
  end if;

  -- Conjunto afetado inteiro, sob as travas, antes de qualquer escrita.
  if public.binder_editor_any_foreign(v_layout, p_collection_id,
                                      v_chain || case when e.target_slot_id is null then '{}'::uuid[] else array[e.target_slot_id] end) then
    raise exception 'OPERATION_RESERVED_TO_OWNER' using errcode = '42501',
      hint = 'o espaço deslocaria conteúdo que só o titular pode mover';
  end if;

  perform public.binder_activity_begin(v_layout, 'GAP_OPENED', 'FICHARIO', p_collection_id);
  if e.outcome = 'NEEDS_PAGE' then
    select ap.page_id, ap.page_number into v_added, v_addn from public.binder_editor_append_page(v_layout) ap;
    v_target := public.binder_slot_at(v_layout, v_addn, 1, 1);
  else
    v_target := e.target_slot_id;
  end if;
  if v_target is null then
    raise exception 'GAP_INCONSISTENT';
  end if;
  v_dest := v_chain[2:] || v_target;

  perform 1 from public.collection_layout_slot s
  where s.id = any (v_chain || v_target)
  order by s.id
  for update;
  for i in reverse cardinality(v_chain)..1 loop
    v_rows := v_rows + public.binder_gap_move_pocket(v_chain[i], v_dest[i]);
  end loop;
  if v_rows <> e.rows_moved
     or exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = v_slot)
     or exists (select 1 from public.collection_layout_slot_expected_content x where x.slot_id = v_slot)
     or exists (select 1 from public.collection_layout_slot_image im where im.slot_id = v_slot) then
    raise exception 'GAP_INCONSISTENT';
  end if;
  for i in 1..cardinality(v_chain) loop
    perform public.binder_activity_add_pocket_shift_items(v_chain[i], v_dest[i]);
  end loop;
  perform public.binder_activity_end();

  return query
  select 'INSERTED'::text, tp.page_number, ts.row_index, ts.column_index, v_addn,
         e.moved_pockets, v_rows, e.pages, public.binder_gap_undo_token(v_layout, v_slot, v_target, v_added)
  from public.collection_layout_slot ts
  join public.collection_layout_page tp on tp.id = ts.page_id
  where ts.id = v_target;
end;
$fn$;

-- Fechar espaço (desfazer) ---------------------------------------------------------------------
create function public.editor_close_binder_gap(
  p_collection_id     uuid,
  p_gap_page          integer,
  p_gap_row           integer,
  p_gap_column        integer,
  p_end_page          integer,
  p_end_row           integer,
  p_end_column        integer,
  p_undo_token        text,
  p_added_page_number integer default null
)
returns table (outcome text, moved_pockets integer, rows_moved integer, page_removed boolean)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  c_row_limit constant integer := 500;
  v_layout uuid;
  v_gap    uuid;
  v_end    uuid;
  v_added  uuid;
  v_chain  uuid[];
  v_count  integer;
  v_rows   integer := 0;
  v_removed boolean := false;
  i        integer;
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  if p_undo_token is null or p_undo_token !~ '^u1:[0-9a-f]{64}$' then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  select x.layout_id into v_layout from public.assert_collection_binder_editor_exclusive(p_collection_id) x;
  v_gap := public.binder_slot_at(v_layout, p_gap_page, p_gap_row, p_gap_column);
  v_end := public.binder_slot_at(v_layout, p_end_page, p_end_row, p_end_column);
  if p_added_page_number is not null then
    select p.id into v_added from public.collection_layout_page p
    where p.layout_id = v_layout and p.page_number = p_added_page_number;
  end if;
  if v_gap is null or v_end is null or (p_added_page_number is not null and v_added is null)
     or public.binder_gap_undo_token(v_layout, v_gap, v_end, v_added) is distinct from p_undo_token then
    raise exception 'GAP_UNDO_EXPIRED' using errcode = '40001',
      hint = 'o fichário mudou desde que o espaço foi aberto';
  end if;

  with s as (
    select sl.id, sl.locked,
           (row_number() over (order by p.page_number, sl.row_index, sl.column_index))::integer as ord,
           exists (select 1 from public.collection_layout_region r
                   where r.page_id = sl.page_id
                     and sl.row_index    between r.top_row     and r.top_row     + r.height - 1
                     and sl.column_index between r.left_column and r.left_column + r.width  - 1) as in_region
    from public.collection_layout_slot sl
    join public.collection_layout_page p on p.id = sl.page_id
    where p.layout_id = v_layout
  ), c as (
    select s.* from s
    where s.ord between (select s1.ord from s s1 where s1.id = v_gap)
                    and (select s2.ord from s s2 where s2.id = v_end)
  )
  select array_agg(c.id order by c.ord), count(*) filter (where c.locked or c.in_region)
    into v_chain, v_count
  from c;
  if v_chain is null or cardinality(v_chain) < 2 or v_count > 0 then
    raise exception 'GAP_UNDO_EXPIRED' using errcode = '40001';
  end if;

  -- Trecho inteiro de X ou livre, antes de qualquer escrita.
  if public.binder_editor_any_foreign(v_layout, p_collection_id, v_chain) then
    raise exception 'OPERATION_RESERVED_TO_OWNER' using errcode = '42501',
      hint = 'fechar o espaço deslocaria conteúdo que só o titular pode mover';
  end if;

  perform 1 from public.collection_layout_slot s where s.id = any (v_chain) order by s.id for update;
  perform public.binder_activity_begin(v_layout, 'GAP_CLOSED', 'FICHARIO', p_collection_id);
  for i in 2..cardinality(v_chain) loop
    v_rows := v_rows + public.binder_gap_move_pocket(v_chain[i], v_chain[i - 1]);
    if v_rows > c_row_limit then
      raise exception 'GAP_OVER_LIMIT' using errcode = '54000';
    end if;
  end loop;
  for i in 2..cardinality(v_chain) loop
    perform public.binder_activity_add_pocket_shift_items(v_chain[i], v_chain[i - 1]);
  end loop;

  -- Página criada pela inserção: só sai se for a última e estiver vazia de TUDO,
  -- inclusive referência de espécie (nada é descartado; senão fica).
  if v_added is not null
     and p_added_page_number = (select max(p2.page_number) from public.collection_layout_page p2 where p2.layout_id = v_layout)
     and (select count(*) from public.collection_layout_page p3 where p3.layout_id = v_layout) > 1
     and not exists (
       select 1 from public.collection_layout_slot s
       where s.page_id = v_added
         and (s.locked
              or exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = s.id)
              or exists (select 1 from public.collection_layout_slot_expected_content x where x.slot_id = s.id)
              or exists (select 1 from public.collection_layout_slot_image im where im.slot_id = s.id)
              or exists (select 1 from public.collection_layout_slot_species_reference sr where sr.slot_id = s.id)))
     and not exists (select 1 from public.collection_layout_region r where r.page_id = v_added) then
    perform public.binder_activity_add_item('PAGE', 'PAGE_REMOVED', null, null, null, null, p_added_page_number, null);
    delete from public.collection_layout_page p where p.id = v_added;
    v_removed := true;
  end if;
  perform public.binder_activity_end();

  return query select 'CLOSED'::text, cardinality(v_chain) - 1, v_rows, v_removed;
end;
$fn$;

comment on function public.editor_binder_exclusive_read(uuid) is
  'V1-13 E1-C2 (5385, interna): autorização SEM trava das prévias do EDITOR — EDITOR ACTIVE, coleção proprietária do fichário, sem convidadas, ativa.';
comment on function public.binder_editor_any_foreign(uuid, uuid, uuid[]) is
  'V1-13 E1-C2 (5385, interna): verdadeiro se algum bolso do conjunto for FOREIGN para a coleção (5371/5378).';
comment on function public.binder_editor_append_page(uuid) is
  'V1-13 E1-C2 (5385, interna): página vazia no fim do fichário com item PAGE_ADDED no evento aberto.';
comment on function public.editor_preview_binder_insert_gap(uuid, integer, integer, integer) is
  'V1-13 E1-C2 (5385): prévia de inserir espaço para o EDITOR (5243), só no fichário exclusivo e com cadeia de X; sem barreira, imagens ou ids.';
comment on function public.editor_insert_binder_gap(uuid, integer, integer, integer, text, boolean, boolean) is
  'V1-13 E1-C2 (5385): EDITOR insere espaço (espelho da 5283) só se todos os bolsos que andam e o destino forem de X ou livres.';
comment on function public.editor_close_binder_gap(uuid, integer, integer, integer, integer, integer, integer, text, integer) is
  'V1-13 E1-C2 (5385): EDITOR fecha o espaço (espelho da 5284) com o token de desfazer, só com trecho de X ou livre.';

revoke all on function public.editor_binder_exclusive_read(uuid) from public, anon, authenticated, service_role;
revoke all on function public.binder_editor_any_foreign(uuid, uuid, uuid[]) from public, anon, authenticated, service_role;
revoke all on function public.binder_editor_append_page(uuid) from public, anon, authenticated, service_role;
revoke all on function public.editor_preview_binder_insert_gap(uuid, integer, integer, integer) from public, anon;
revoke all on function public.editor_insert_binder_gap(uuid, integer, integer, integer, text, boolean, boolean) from public, anon;
revoke all on function public.editor_close_binder_gap(uuid, integer, integer, integer, integer, integer, integer, text, integer) from public, anon;
grant execute on function public.editor_preview_binder_insert_gap(uuid, integer, integer, integer) to authenticated;
grant execute on function public.editor_insert_binder_gap(uuid, integer, integer, integer, text, boolean, boolean) to authenticated;
grant execute on function public.editor_close_binder_gap(uuid, integer, integer, integer, integer, integer, integer, text, integer) to authenticated;

do $post$
declare
  f oid;
begin
  foreach f in array array[to_regprocedure('public.editor_preview_binder_insert_gap(uuid, integer, integer, integer)'),
                           to_regprocedure('public.editor_insert_binder_gap(uuid, integer, integer, integer, text, boolean, boolean)'),
                           to_regprocedure('public.editor_close_binder_gap(uuid, integer, integer, integer, integer, integer, integer, text, integer)')] loop
    if f is null
       or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
       or (select p.proconfig from pg_catalog.pg_proc p where p.oid = f) is distinct from array['search_path=""']
       or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not true
       or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false then
      raise exception 'POSTCHECK 5385: RPC fora do estado esperado (%)', f;
    end if;
  end loop;
  foreach f in array array[to_regprocedure('public.editor_binder_exclusive_read(uuid)'),
                           to_regprocedure('public.binder_editor_any_foreign(uuid, uuid, uuid[])'),
                           to_regprocedure('public.binder_editor_append_page(uuid)')] loop
    if f is null
       or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not false
       or pg_catalog.has_function_privilege('service_role', f, 'EXECUTE') is not false then
      raise exception 'POSTCHECK 5385: ajudante interno fora do estado esperado (%)', f;
    end if;
  end loop;
end;
$post$;

-- @@T7 5386 (protegida) sha256=439fa23e23b5966c3796e0542ba8c79efe61148c408fdde6806825bd75ee00cd
set local lock_timeout = '5s';

do $pre$
begin
  if to_regprocedure('public.v1_13_assert_capability()') is null or to_regprocedure('public.v1_13_capability_open()') is null then raise exception 'PRECHECK G1: barreira 5389 ausente'; end if;  -- G1 (D-E1)
  if to_regprocedure('public.binder_auto_arrange_plan(uuid, uuid, uuid)') is null
     or to_regprocedure('public.editor_binder_exclusive_read(uuid)') is null
     or to_regprocedure('public.binder_editor_any_foreign(uuid, uuid, uuid[])') is null then
    raise exception 'PRECHECK 5386: 5360 ou 5385 ausentes';
  end if;
  if to_regprocedure('public.editor_preview_binder_auto_arrange(uuid)') is not null
     or to_regprocedure('public.editor_apply_binder_auto_arrange(uuid, text)') is not null then
    raise exception 'PRECHECK 5386: JÁ APLICADA ou ESTADO DIVERGENTE';
  end if;
end;
$pre$;

-- Prévia ---------------------------------------------------------------------------------------
create function public.editor_preview_binder_auto_arrange(p_collection_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  c_limit  constant integer := 500;
  r        record;
  v_mode   text;
  v_policy text;
  v_slots  uuid[];
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  select * into r from public.editor_binder_exclusive_read(p_collection_id) x;
  select c.mode, c.completion_policy into v_mode, v_policy from public.collection c where c.id = p_collection_id;
  if v_mode is distinct from 'REFERENCE_BASED'
     or v_policy is null or v_policy not in ('STANDARD_SET', 'MASTER_SET', 'REFERENCE_POSITION') then
    raise exception 'AUTO_ARRANGE_UNSUPPORTED_COLLECTION' using errcode = '22023';
  end if;

  select array_agg(h.slot_id) filter (where h.item_kind = 'INSERT') into v_slots
  from public.binder_auto_arrange_plan(p_collection_id, r.layout_id, r.container_id) h;
  if public.binder_editor_any_foreign(r.layout_id, p_collection_id, v_slots) then
    raise exception 'OPERATION_RESERVED_TO_OWNER' using errcode = '42501',
      hint = 'a organização alcançaria bolsos que só o titular pode alterar';
  end if;

  return (
    with plan as materialized (
      select * from public.binder_auto_arrange_plan(p_collection_id, r.layout_id, r.container_id)
    ),
    h as (
      select p.insert_count as n, p.plan_token as t,
             case when p.insert_count = 0 then 'EMPTY'
                  when p.insert_count > c_limit then 'LIMIT_EXCEEDED'
                  else 'READY' end as st
      from plan p where p.item_kind = 'HEADER'
    )
    select jsonb_build_object(
      'status',         h.st,
      'insert_count',   h.n,
      'limit',          c_limit,
      'plan_token',     h.t,
      'excluded_cards', coalesce((select jsonb_object_agg(x.reason, x.n)
                                  from (select p.reason, count(*) as n from plan p
                                        where p.item_kind = 'EXCLUDED_CARD' group by p.reason) x), '{}'::jsonb),
      'unfilled_slots', coalesce((select jsonb_object_agg(x.reason, x.n)
                                  from (select p.reason, count(*) as n from plan p
                                        where p.item_kind = 'UNFILLED_SLOT' group by p.reason) x), '{}'::jsonb),
      'unfilled_count', (select count(*) from plan p where p.item_kind = 'UNFILLED_SLOT'),
      'pages',          coalesce((select jsonb_agg(distinct p.page_number order by p.page_number)
                                  from plan p where p.item_kind = 'INSERT'), '[]'::jsonb),
      'items',          case when h.st = 'LIMIT_EXCEEDED' then '[]'::jsonb
                             else coalesce((select jsonb_agg(jsonb_build_object(
                                     'ord', p.ord, 'physical_card_id', p.physical_card_id,
                                     'page_number', p.page_number, 'row_index', p.row_index,
                                     'column_index', p.column_index, 'card_id', p.card_id,
                                     'card_variant_id', p.card_variant_id) order by p.ord)
                                  from plan p where p.item_kind = 'INSERT'), '[]'::jsonb) end
    )
    from h
  );
end;
$fn$;

-- Aplicar --------------------------------------------------------------------------------------
create function public.editor_apply_binder_auto_arrange(p_collection_id uuid, p_plan_token text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  c_limit  constant integer := 500;
  r        record;
  v_mode   text;
  v_policy text;
  v_n      integer;
  v_token  text;
  v_event  bigint;
  v_rows   integer;
  v_slots  uuid[];
  v_cards  uuid[];
  v_pages  jsonb;
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  if p_collection_id is null or p_plan_token is null or p_plan_token !~ '^aa1:[0-9a-f]{64}$' then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  select * into r from public.assert_collection_binder_editor_exclusive(p_collection_id) x;
  select c.mode, c.completion_policy into v_mode, v_policy from public.collection c where c.id = p_collection_id;
  if v_mode is distinct from 'REFERENCE_BASED'
     or v_policy is null or v_policy not in ('STANDARD_SET', 'MASTER_SET', 'REFERENCE_POSITION') then
    raise exception 'AUTO_ARRANGE_UNSUPPORTED_COLLECTION' using errcode = '22023';
  end if;

  select max(h.plan_token), max(h.insert_count),
         array_agg(h.slot_id order by h.slot_id) filter (where h.item_kind = 'INSERT'),
         array_agg(h.physical_card_id order by h.physical_card_id) filter (where h.item_kind = 'INSERT')
    into v_token, v_n, v_slots, v_cards
  from public.binder_auto_arrange_plan(p_collection_id, r.layout_id, r.container_id) h;

  if v_token is distinct from p_plan_token then
    select e.id into v_event
    from public.binder_activity_event e
    where e.layout_key = r.layout_id
      and e.owner_user_id = r.owner_user_id
      and e.event_type = 'CARDS_AUTO_ARRANGED'
      and e.summary ->> 'plan_token' = p_plan_token
    order by e.id desc
    limit 1;
    if v_event is not null then
      return jsonb_build_object('status', 'ALREADY_APPLIED', 'inserted', 0, 'event_id', v_event);
    end if;
    raise exception 'AUTO_ARRANGE_PLAN_CHANGED' using errcode = '40001',
      hint = 'o fichário mudou desde a prévia — gere uma nova prévia';
  end if;
  if v_n = 0 then
    return jsonb_build_object('status', 'NOTHING_TO_DO', 'inserted', 0);
  end if;
  if v_n > c_limit then
    raise exception 'AUTO_ARRANGE_LIMIT_EXCEEDED' using errcode = '54000',
      detail = format('%s inserções planejadas; limite %s por confirmação', v_n, c_limit);
  end if;
  if public.binder_editor_any_foreign(r.layout_id, p_collection_id, v_slots) then
    raise exception 'OPERATION_RESERVED_TO_OWNER' using errcode = '42501',
      hint = 'a organização alcançaria bolsos que só o titular pode alterar';
  end if;

  perform 1 from public.collection_layout_slot s where s.id = any (v_slots) order by s.id for update of s;
  perform 1 from public.physical_card pc where pc.id = any (v_cards) order by pc.id for update of pc;

  select max(h.plan_token),
         array_agg(h.slot_id order by h.ord) filter (where h.item_kind = 'INSERT'),
         array_agg(h.physical_card_id order by h.ord) filter (where h.item_kind = 'INSERT'),
         coalesce(jsonb_agg(distinct h.page_number order by h.page_number) filter (where h.item_kind = 'INSERT'), '[]'::jsonb)
    into v_token, v_slots, v_cards, v_pages
  from public.binder_auto_arrange_plan(p_collection_id, r.layout_id, r.container_id) h;
  if v_token is distinct from p_plan_token then
    raise exception 'AUTO_ARRANGE_PLAN_CHANGED' using errcode = '40001',
      hint = 'o fichário mudou desde a prévia — gere uma nova prévia';
  end if;

  perform public.binder_activity_begin(r.layout_id, 'CARDS_AUTO_ARRANGED', 'FICHARIO', p_collection_id,
                                       jsonb_build_object('plan_token', p_plan_token, 'inserted', v_n));
  v_rows := 0;
  for i in 1 .. coalesce(array_length(v_slots, 1), 0) loop
    begin
      insert into public.collection_layout_slot_assignment (slot_id, physical_card_id)
      values (v_slots[i], v_cards[i]);
    exception
      when unique_violation then
        raise exception 'AUTO_ARRANGE_PLAN_CHANGED' using errcode = '40001',
          hint = 'o fichário mudou desde a prévia — gere uma nova prévia';
    end;
    perform public.binder_activity_add_card_item('PLACED', v_cards[i], null, v_slots[i]);
    v_rows := v_rows + 1;
  end loop;
  if v_rows <> v_n then
    raise exception 'AUTO_ARRANGE_PLAN_CHANGED' using errcode = '40001';
  end if;
  v_event := (nullif(current_setting('mmkyu.binder_activity_ctx', true), '')::jsonb ->> 'event_id')::bigint;
  perform public.binder_activity_end();

  return jsonb_build_object('status', 'APPLIED', 'inserted', v_rows, 'event_id', v_event, 'pages', v_pages);
end;
$fn$;

comment on function public.editor_preview_binder_auto_arrange(uuid) is
  'V1-13 E1-C2 (5386): prévia da organização automática para o EDITOR do fichário exclusivo (mesmo plano e token da 5360; sem ids de bolso).';
comment on function public.editor_apply_binder_auto_arrange(uuid, text) is
  'V1-13 E1-C2 (5386): EDITOR confirma a organização automática do fichário exclusivo (espelho da 5360): só posiciona exemplares de X em bolsos vazios de X.';

revoke all on function public.editor_preview_binder_auto_arrange(uuid) from public, anon;
revoke all on function public.editor_apply_binder_auto_arrange(uuid, text) from public, anon;
grant execute on function public.editor_preview_binder_auto_arrange(uuid) to authenticated;
grant execute on function public.editor_apply_binder_auto_arrange(uuid, text) to authenticated;

do $post$
declare
  f oid;
begin
  foreach f in array array[to_regprocedure('public.editor_preview_binder_auto_arrange(uuid)'),
                           to_regprocedure('public.editor_apply_binder_auto_arrange(uuid, text)')] loop
    if f is null
       or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
       or (select p.proconfig from pg_catalog.pg_proc p where p.oid = f) is distinct from array['search_path=""']
       or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not true
       or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false then
      raise exception 'POSTCHECK 5386: RPC fora do estado esperado (%)', f;
    end if;
  end loop;
end;
$post$;

-- @@T7 5387 (protegida) sha256=d601b8f99c2423ab4b704cf5fc1ce655e62456896fb9256cbc9658be080bd714
set local lock_timeout = '5s';

do $pre$
begin
  if to_regprocedure('public.v1_13_assert_capability()') is null or to_regprocedure('public.v1_13_capability_open()') is null then raise exception 'PRECHECK G1: barreira 5389 ausente'; end if;  -- G1 (D-E1)
  if to_regprocedure('public.binder_catalog_assert_eligible(uuid)') is null
     or to_regprocedure('public.binder_catalog_novelties(uuid)') is null
     or to_regprocedure('public.binder_catalog_plan(uuid, text[])') is null
     or to_regprocedure('public.binder_gap_move_pocket(uuid, uuid)') is null
     or to_regprocedure('public.binder_editor_append_page(uuid)') is null
     or to_regprocedure('public.editor_binder_exclusive_read(uuid)') is null then
    raise exception 'PRECHECK 5387: 5264, 5243 ou 5385 ausentes';
  end if;
  if to_regprocedure('public.binder_editor_catalog_affected(uuid, uuid, text[])') is not null
     or to_regprocedure('public.editor_preview_binder_catalog_reconciliation(uuid, text[])') is not null
     or to_regprocedure('public.editor_apply_binder_catalog_reconciliation(uuid, text[], text, boolean, boolean)') is not null then
    raise exception 'PRECHECK 5387: JÁ APLICADA ou ESTADO DIVERGENTE';
  end if;
end;
$pre$;

-- Ajudante interno: bolsos existentes alcançados pelo plano --------------------------------------
create function public.binder_editor_catalog_affected(p_layout_id uuid, p_collection_id uuid, p_keys text[])
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $fn$
  with st as (
    select * from public.binder_catalog_plan(p_collection_id, p_keys) p
    where p.row_kind = 'ITEM' and p.kind in ('IN_PLACE', 'RESERVE_PLACED', 'UPGRADE_RESERVATION', 'SHIFT')
  ),
  pos as (
    select s.id, pg.page_number, s.row_index, s.column_index
    from public.collection_layout_page pg
    join public.collection_layout_slot s on s.page_id = pg.id
    where pg.layout_id = p_layout_id
  )
  select coalesce(array_agg(distinct pos.id), '{}'::uuid[])
  from st
  join pos
    on (st.kind <> 'SHIFT'
        and (pos.page_number, pos.row_index, pos.column_index) = (st.target_page, st.target_row, st.target_column))
    or (st.kind = 'SHIFT'
        and (pos.page_number, pos.row_index, pos.column_index) >= (st.target_page, st.target_row, st.target_column)
        and (pos.page_number, pos.row_index, pos.column_index) <= (st.end_page, st.end_row, st.end_column));
$fn$;

-- Prévia ------------------------------------------------------------------------------------------
create function public.editor_preview_binder_catalog_reconciliation(p_collection_id uuid, p_keys text[] default null)
returns table (
  row_kind text, step_no integer, item_key text, card_id uuid, variant_type_id uuid, pos_ord integer, kind text,
  target_page integer, target_row integer, target_column integer, end_page integer, end_row integer, end_column integer,
  anchor_page integer, anchor_row integer, anchor_column integer, pockets_moved integer, rows_moved integer,
  other_reserves_moved integer, crosses_page boolean, adds_page boolean, barrier_page integer, barrier_row integer,
  barrier_column integer, barrier_kind text, outcome text, reason text, layout_id uuid, total_items integer,
  total_rows_moved integer, row_limit integer, item_limit integer, requires_cross_page boolean,
  requires_add_page boolean, pages_added integer, added_page_numbers integer[], capacity_before integer,
  capacity_after integer, free_pockets_after integer, plan_token text
)
language plpgsql
stable
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  r record;
  x record;
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  select * into r from public.editor_binder_exclusive_read(p_collection_id) e;
  if exists (select 1 from public.collection_layout_slot_species_reference sr
             where sr.layout_id = r.layout_id and sr.collection_id <> p_collection_id) then
    raise exception 'OPERATION_RESERVED_TO_OWNER' using errcode = '42501',
      hint = 'este fichário tem referências que só o titular pode alterar';
  end if;
  select * into x from public.binder_catalog_assert_eligible(p_collection_id) a;
  if x.layout_id is distinct from r.layout_id or x.is_guest then
    raise exception 'OPERATION_RESERVED_TO_OWNER' using errcode = '42501';
  end if;
  if public.binder_editor_any_foreign(r.layout_id, p_collection_id,
                                      public.binder_editor_catalog_affected(r.layout_id, p_collection_id, p_keys)) then
    raise exception 'OPERATION_RESERVED_TO_OWNER' using errcode = '42501',
      hint = 'a incorporação deslocaria conteúdo que só o titular pode mover';
  end if;
  return query
  select p.row_kind, p.step_no, p.item_key, p.card_id, p.variant_type_id, p.pos_ord, p.kind,
         p.target_page, p.target_row, p.target_column, p.end_page, p.end_row, p.end_column,
         p.anchor_page, p.anchor_row, p.anchor_column, p.pockets_moved, p.rows_moved,
         p.other_reserves_moved, p.crosses_page, p.adds_page,
         case when bf.foreign_ then null else p.barrier_page end,
         case when bf.foreign_ then null else p.barrier_row end,
         case when bf.foreign_ then null else p.barrier_column end,
         p.barrier_kind, p.outcome, p.reason, null::uuid, p.total_items,
         p.total_rows_moved, p.row_limit, p.item_limit, p.requires_cross_page,
         p.requires_add_page, p.pages_added, p.added_page_numbers, null::integer,
         null::integer, null::integer, p.plan_token
  from public.binder_catalog_plan(p_collection_id, p_keys) p
  cross join lateral (
    select p.barrier_page is not null
           and public.binder_editor_any_foreign(r.layout_id, p_collection_id,
                 array[public.binder_slot_at(r.layout_id, p.barrier_page, p.barrier_row, p.barrier_column)]) as foreign_
  ) bf;
end;
$fn$;

-- Aplicar -----------------------------------------------------------------------------------------
create function public.editor_apply_binder_catalog_reconciliation(
  p_collection_id      uuid,
  p_keys               text[],
  p_plan_token         text,
  p_confirm_cross_page boolean default false,
  p_confirm_add_page   boolean default false
)
returns table (
  outcome text, items_applied integer, reservations_created integer, reservations_upgraded integer,
  pockets_moved integer, rows_moved integer, pages_added integer, added_page_numbers integer[]
)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  r          record;
  x          record;
  st         record;
  h          record;
  v_layout   uuid;
  v_pending  text[];
  v_invalid  integer;
  v_chain    uuid[];
  v_target   uuid;
  v_page_no  integer;
  v_expect   integer;
  v_rows     integer := 0;
  v_pm       integer := 0;
  v_res      integer := 0;
  v_upg      integer := 0;
  v_added    integer[] := '{}';
  k          integer;
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  if p_collection_id is null or p_plan_token is null or p_plan_token !~ '^rc1:[0-9a-f]{64}$'
     or (p_keys is not null and (cardinality(p_keys) = 0 or array_position(p_keys, null) is not null)) then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  select * into r from public.assert_collection_binder_editor_exclusive(p_collection_id) e;
  v_layout := r.layout_id;
  if exists (select 1 from public.collection_layout_slot_species_reference sr
             where sr.layout_id = v_layout and sr.collection_id <> p_collection_id) then
    raise exception 'OPERATION_RESERVED_TO_OWNER' using errcode = '42501',
      hint = 'este fichário tem referências que só o titular pode alterar';
  end if;
  select * into x from public.binder_catalog_assert_eligible(p_collection_id) a;
  if x.layout_id is distinct from v_layout or x.owner_user_id is distinct from r.owner_user_id or x.is_guest then
    raise exception 'RECONCILE_INCONSISTENT' using errcode = 'P0001';
  end if;

  if p_keys is null then
    select array_agg(nv.item_key order by nv.pos_ord) into v_pending
    from public.binder_catalog_novelties(p_collection_id) nv where nv.is_novelty;
    if v_pending is null then
      return query select 'NOTHING_TO_DO'::text, 0, 0, 0, 0, 0, 0, '{}'::integer[];
      return;
    end if;
  else
    select count(*) filter (where nv.item_key is null)::integer,
           array_agg(d.k order by nv.pos_ord) filter (where nv.is_novelty)
      into v_invalid, v_pending
    from (select distinct u.k from unnest(p_keys) u(k)) d
    left join public.binder_catalog_novelties(p_collection_id) nv on nv.item_key = d.k;
    if v_invalid > 0 then
      raise exception 'SELECTION_INVALID' using errcode = '22023',
        hint = 'há itens que não são novidades desta coleção';
    end if;
    if v_pending is null then
      return query select 'ALREADY_APPLIED'::text, 0, 0, 0, 0, 0, 0, '{}'::integer[];
      return;
    end if;
  end if;

  -- Cabeçalho do plano: as mesmas recusas da 5296, antes de qualquer escrita.
  select * into h from public.binder_catalog_plan(p_collection_id, v_pending) p where p.row_kind = 'HEADER';
  if h.outcome = 'OVER_LIMIT' then
    raise exception 'RECONCILE_OVER_LIMIT' using errcode = '54000',
      hint = format('%s (limites: %s itens, %s linhas movidas)', h.reason, h.item_limit, h.row_limit);
  end if;
  if h.plan_token is distinct from p_plan_token then
    raise exception 'RECONCILE_PLAN_CHANGED' using errcode = '40001',
      hint = 'o fichário ou o Catálogo mudou desde a prévia — veja a prévia de novo';
  end if;
  if h.outcome = 'BLOCKED' then
    raise exception 'RECONCILE_BLOCKED' using errcode = '55000', hint = 'há um bolso fixado ou mesclado no caminho';
  elsif h.outcome = 'NEEDS_REVIEW' then
    raise exception 'RECONCILE_NEEDS_REVIEW' using errcode = '55000',
      hint = 'há novidade com carta fora da ordem ou reserva genérica ambígua — desmarque-a e resolva separadamente';
  elsif h.outcome = 'NO_ANCHOR' then
    raise exception 'RECONCILE_NO_ANCHOR' using errcode = '55000',
      hint = 'há novidade sem posição vizinha no fichário — desmarque-a';
  elsif h.outcome is distinct from 'READY' then
    raise exception 'RECONCILE_INCONSISTENT' using errcode = 'P0001';
  end if;
  if h.requires_cross_page and not coalesce(p_confirm_cross_page, false) then
    raise exception 'RECONCILE_CONFIRMATION_REQUIRED' using errcode = '55000', hint = 'CROSS_PAGE';
  end if;
  if h.requires_add_page and not coalesce(p_confirm_add_page, false) then
    raise exception 'RECONCILE_CONFIRMATION_REQUIRED' using errcode = '55000', hint = 'ADD_PAGE';
  end if;

  -- Conjunto afetado inteiro, sob as travas.
  if public.binder_editor_any_foreign(v_layout, p_collection_id,
                                      public.binder_editor_catalog_affected(v_layout, p_collection_id, v_pending)) then
    raise exception 'OPERATION_RESERVED_TO_OWNER' using errcode = '42501',
      hint = 'a incorporação deslocaria conteúdo que só o titular pode mover';
  end if;

  perform public.binder_activity_begin(v_layout, 'CATALOG_NOVELTIES_INCORPORATED', 'CATALOGO', p_collection_id);
  for st in
    select * from public.binder_catalog_plan(p_collection_id, v_pending) p
    where p.row_kind = 'ITEM'
    order by p.step_no
  loop
    if st.kind not in ('IN_PLACE', 'RESERVE_PLACED', 'SHIFT', 'UPGRADE_RESERVATION') then
      raise exception 'RECONCILE_INCONSISTENT' using errcode = 'P0001';
    end if;

    if st.kind = 'UPGRADE_RESERVATION' then
      v_target := public.binder_slot_at(v_layout, st.target_page, st.target_row, st.target_column);
      perform 1 from public.collection_layout_slot s where s.id = v_target for update;
      update public.collection_layout_slot_expected_content e
         set expected_variant_type_id = st.variant_type_id
       where e.slot_id = v_target
         and e.card_id = st.card_id
         and e.card_variant_id is null
         and e.expected_variant_type_id is null
         and coalesce(e.collection_id, x.owner_collection_id) = p_collection_id;
      get diagnostics k = row_count;
      if k <> 1 then
        raise exception 'RECONCILE_INCONSISTENT' using errcode = 'P0001';
      end if;
      v_upg := v_upg + 1;
      perform public.binder_activity_add_item('RESERVATION', 'INCORPORATED', st.card_id, st.variant_type_id,
                                              null, v_target, null, null, jsonb_build_object('upgrade', true));
      continue;
    end if;

    if st.adds_page then
      v_expect := case when st.kind = 'SHIFT' then st.end_page else st.target_page end;
      select ap.page_number into v_page_no from public.binder_editor_append_page(v_layout) ap;
      if v_page_no is distinct from v_expect then
        raise exception 'RECONCILE_INCONSISTENT' using errcode = 'P0001';
      end if;
      v_added := v_added || v_page_no;
    end if;

    if st.kind = 'SHIFT' then
      select array_agg(s.id order by p.page_number, s.row_index, s.column_index) into v_chain
      from public.collection_layout_slot s
      join public.collection_layout_page p on p.id = s.page_id
      where p.layout_id = v_layout
        and (p.page_number, s.row_index, s.column_index) >= (st.target_page, st.target_row, st.target_column)
        and (p.page_number, s.row_index, s.column_index) <= (st.end_page, st.end_row, st.end_column);
      if v_chain is null or cardinality(v_chain) <> st.pockets_moved + 1 then
        raise exception 'RECONCILE_INCONSISTENT' using errcode = 'P0001';
      end if;
      perform 1 from public.collection_layout_slot s where s.id = any (v_chain) order by s.id for update;
      if exists (select 1 from public.collection_layout_slot s where s.id = any (v_chain) and s.locked) then
        raise exception 'RECONCILE_INCONSISTENT' using errcode = 'P0001';
      end if;
      for k in reverse cardinality(v_chain) - 1 .. 1 loop
        v_rows := v_rows + public.binder_gap_move_pocket(v_chain[k], v_chain[k + 1]);
        perform public.binder_activity_add_pocket_shift_items(v_chain[k], v_chain[k + 1]);
      end loop;
      v_pm := v_pm + st.pockets_moved;
      v_target := v_chain[1];
    else
      v_target := public.binder_slot_at(v_layout, st.target_page, st.target_row, st.target_column);
      if v_target is null then
        raise exception 'RECONCILE_INCONSISTENT' using errcode = 'P0001';
      end if;
      perform 1 from public.collection_layout_slot s where s.id = v_target for update;
    end if;

    if exists (select 1 from public.collection_layout_slot_expected_content e where e.slot_id = v_target)
       or (st.kind <> 'RESERVE_PLACED'
           and (exists (select 1 from public.collection_layout_slot_assignment a0 where a0.slot_id = v_target)
                or exists (select 1 from public.collection_layout_slot_image im where im.slot_id = v_target)
                or exists (select 1 from public.collection_layout_slot s where s.id = v_target and s.locked)))
       or (st.kind = 'RESERVE_PLACED'
           and not exists (select 1 from public.collection_layout_slot_assignment a0 where a0.slot_id = v_target)) then
      raise exception 'RECONCILE_INCONSISTENT' using errcode = 'P0001';
    end if;

    -- Fichário exclusivo: X é a proprietária → reserva sem coleção explícita, como no titular.
    insert into public.collection_layout_slot_expected_content
      (slot_id, card_id, card_variant_id, expected_variant_type_id, collection_id)
    values (v_target, st.card_id, null, st.variant_type_id, null);
    v_res := v_res + 1;
    perform public.binder_activity_add_reservation_item('RESERVED', v_target);
  end loop;

  if v_rows <> h.total_rows_moved or v_res + v_upg <> cardinality(v_pending)
     or exists (select 1
                from unnest(v_pending) u(k)
                left join public.binder_catalog_novelties(p_collection_id) nv on nv.item_key = u.k
                where nv.is_reserved is distinct from true) then
    raise exception 'RECONCILE_INCONSISTENT' using errcode = 'P0001';
  end if;

  insert into public.collection_layout_catalog_incorporation (layout_id, collection_id, item_key)
  select v_layout, p_collection_id, u.k
  from unnest(v_pending) u(k)
  on conflict (layout_id, collection_id, item_key) do nothing;
  get diagnostics k = row_count;
  if k <> cardinality(v_pending) then
    raise exception 'RECONCILE_INCONSISTENT' using errcode = 'P0001';
  end if;
  perform public.binder_activity_end();

  return query select 'APPLIED'::text, cardinality(v_pending), v_res, v_upg, v_pm, v_rows,
                      cardinality(v_added), v_added;
end;
$fn$;

comment on function public.binder_editor_catalog_affected(uuid, uuid, text[]) is
  'V1-13 E1-C2 (5387, interna): bolsos existentes alcançados pelo plano de novidades (destinos e trechos deslocados).';
comment on function public.editor_preview_binder_catalog_reconciliation(uuid, text[]) is
  'V1-13 E1-C2 (5387): prévia das novidades do Catálogo para o EDITOR do fichário exclusivo (plano e token da 5264); sem capacidade, layout ou barreira de terceiros.';
comment on function public.editor_apply_binder_catalog_reconciliation(uuid, text[], text, boolean, boolean) is
  'V1-13 E1-C2 (5387): EDITOR incorpora novidades do Catálogo no fichário exclusivo (espelho da 5296) só se o conjunto afetado for de X ou livre.';

revoke all on function public.binder_editor_catalog_affected(uuid, uuid, text[]) from public, anon, authenticated, service_role;
revoke all on function public.editor_preview_binder_catalog_reconciliation(uuid, text[]) from public, anon;
revoke all on function public.editor_apply_binder_catalog_reconciliation(uuid, text[], text, boolean, boolean) from public, anon;
grant execute on function public.editor_preview_binder_catalog_reconciliation(uuid, text[]) to authenticated;
grant execute on function public.editor_apply_binder_catalog_reconciliation(uuid, text[], text, boolean, boolean) to authenticated;

do $post$
declare
  f oid;
begin
  foreach f in array array[to_regprocedure('public.editor_preview_binder_catalog_reconciliation(uuid, text[])'),
                           to_regprocedure('public.editor_apply_binder_catalog_reconciliation(uuid, text[], text, boolean, boolean)')] loop
    if f is null
       or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
       or (select p.proconfig from pg_catalog.pg_proc p where p.oid = f) is distinct from array['search_path=""']
       or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not true
       or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false then
      raise exception 'POSTCHECK 5387: RPC fora do estado esperado (%)', f;
    end if;
  end loop;
  f := to_regprocedure('public.binder_editor_catalog_affected(uuid, uuid, text[])');
  if f is null or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not false then
    raise exception 'POSTCHECK 5387: ajudante interno fora do estado esperado';
  end if;
end;
$post$;

-- @@T7 5323 (protegida) sha256=3d4bac2223d54309b5a3b591e377ddb34828a598687d79db5d1c65cd61e72990
set local lock_timeout = '5s';

do $pre$
begin
  if to_regprocedure('public.v1_13_assert_capability()') is null or to_regprocedure('public.v1_13_capability_open()') is null then raise exception 'PRECHECK G1: barreira 5389 ausente'; end if;  -- G1 (D-E1)
  if to_regprocedure('public.collection_share_role(uuid)') is null
     or to_regprocedure('public.master_set_positions(uuid, uuid[])') is null
     or to_regprocedure('public.get_my_master_set_positions(uuid, text, integer, integer)') is null then
    raise exception 'PRECHECK 5323: dependências ausentes (5302, 5187, 5198)';
  end if;
  if exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname = 'get_shared_master_set_positions') then
    raise exception 'PRECHECK 5323: JÁ APLICADA ou ESTADO DIVERGENTE — get_shared_master_set_positions já existe';
  end if;
end;
$pre$;

create function public.get_shared_master_set_positions(
  p_collection_id uuid,
  p_filter        text    default 'ALL',
  p_limit         integer default 200,
  p_offset        integer default 0
)
returns table (
  card_id              uuid,
  collector_number     text,
  collector_total      integer,
  card_name            text,
  variant_type_id      uuid,
  variant_type_code    text,
  variant_type_name    text,
  is_secret            boolean,
  image_path           text,
  is_satisfied         boolean,
  copies_in_collection integer,
  total_count          bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_filter text := upper(btrim(coalesce(p_filter, 'ALL')));
  v_role   text;
  v_set    uuid;
  v_types  uuid[];
begin
  if not public.v1_13_capability_open() then return; end if;  -- G1 (D-E1)
  if v_filter not in ('ALL', 'OWNED', 'MISSING') then
    raise exception 'INVALID_FILTER' using errcode = '22023';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 500 or p_offset is null or p_offset < 0 or p_offset > 100000 then
    raise exception 'INVALID_PAGE' using errcode = '22023';
  end if;
  if p_collection_id is null then
    return;
  end if;

  -- Fronteira de autorização antes de qualquer tabela de catálogo (padrão 5320).
  v_role := public.collection_share_role(p_collection_id);
  if v_role is null or v_role not in ('OWNER', 'VIEWER') then
    return;
  end if;

  select ccsr.card_set_id into v_set
  from public.collection c
  join public.collection_reference cr            on cr.collection_id = c.id
  join public.collection_card_set_reference ccsr on ccsr.collection_reference_id = cr.id
  where c.id = p_collection_id
    and c.mode = 'REFERENCE_BASED'
    and c.completion_policy = 'MASTER_SET';
  if v_set is null then
    return;
  end if;

  select array_agg(f.variant_type_id) into v_types
  from public.collection_master_set_finish f
  where f.collection_id = p_collection_id;

  return query
  with positions as (
    select p.card_id, p.variant_type_id, p.is_secret
    from public.master_set_positions(v_set, v_types) p
  ),
  in_collection as (
    -- só as alocações DESTA coleção (nenhuma leitura do acervo livre)
    select cv.card_id, cv.variant_type_id, count(*)::integer as copies,
           min(pc.language_id::text)::uuid as lang
    from public.collection_allocation ca
    join public.physical_card pc on pc.id = ca.physical_card_id
    join public.card_variant cv  on cv.id = pc.card_variant_id
    where ca.collection_id = p_collection_id
    group by cv.card_id, cv.variant_type_id
  ),
  in_by_card as (
    select ic.card_id, sum(ic.copies)::integer as copies, min(ic.lang::text) as lang
    from in_collection ic
    group by ic.card_id
  ),
  pos_rows as (
    select
      c.id                         as card_id,
      c.collector_number::text     as number,
      c.collector_total            as collector_total,
      c.name::text                 as card_name,
      c.collector_order            as collector_order,
      p.variant_type_id            as variant_type_id,
      t.code::text                 as type_code,
      t.name::text                 as type_name,
      coalesce(t.display_order, 2147483647) as type_order,
      p.is_secret                  as is_secret,
      case when p.variant_type_id is null then icc.copies else icp.copies end as in_copies,
      (case when p.variant_type_id is null then icc.lang else icp.lang::text end)::uuid as lang
    from positions p
    join public.card c                    on c.id = p.card_id
    left join public.card_variant_type t  on t.id = p.variant_type_id
    left join in_collection icp           on icp.card_id = p.card_id and icp.variant_type_id = p.variant_type_id
    left join in_by_card icc              on icc.card_id = p.card_id
  ),
  filtered as (
    select r.*, (coalesce(r.in_copies, 0) > 0) as satisfied, count(*) over () as total
    from pos_rows r
    where v_filter = 'ALL'
       or (v_filter = 'OWNED'   and coalesce(r.in_copies, 0) > 0)
       or (v_filter = 'MISSING' and coalesce(r.in_copies, 0) = 0)
    order by r.collector_order, r.number, r.type_order, r.card_id
    limit p_limit offset p_offset
  )
  select f.card_id, f.number, f.collector_total, f.card_name,
         f.variant_type_id, f.type_code, f.type_name, f.is_secret,
         img.storage_path::text,
         f.satisfied,
         coalesce(f.in_copies, 0),
         f.total
  from filtered f
  left join lateral (
    select ast.storage_path
    from public.card_asset ast
    join public.card_asset_type cat on cat.id = ast.asset_type_id and cat.code = 'CARD_FRONT'
    join public.language al         on al.id = ast.language_id
    where ast.card_id = f.card_id
      and ast.is_primary
      and ast.is_active
      and ast.storage_path is not null
    order by (ast.language_id = f.lang) desc nulls last,
             (al.code = 'pt-BR') desc,
             (al.code = 'en') desc,
             al.language_order asc
    limit 1
  ) img on true
  order by f.collector_order, f.number, f.type_order, f.card_id;
end;
$$;

comment on function public.get_shared_master_set_positions(uuid, text, integer, integer) is
  'V1-13 E1-D (5323): grade Master Set do participante (OWNER/VIEWER pela 5302; EDITOR lê como VIEWER) — posições por acabamento, arte, satisfação e exemplares desta coleção. Sem copies_available e sem leitura do acervo (C-243). Mesmo filtro, paginação e ordem da 5198. Sem acesso → zero linhas.';

revoke all on function public.get_shared_master_set_positions(uuid, text, integer, integer) from public, anon;
grant execute on function public.get_shared_master_set_positions(uuid, text, integer, integer) to authenticated;

do $post$
declare
  v_oid oid := to_regprocedure('public.get_shared_master_set_positions(uuid, text, integer, integer)');
begin
  if v_oid is null
     or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = v_oid) is not true
     or (select p.proconfig from pg_catalog.pg_proc p where p.oid = v_oid) is distinct from array['search_path=""']
     or (select p.provolatile from pg_catalog.pg_proc p where p.oid = v_oid) is distinct from 's'
     or pg_catalog.has_function_privilege('authenticated', v_oid, 'EXECUTE') is not true
     or pg_catalog.has_function_privilege('anon', v_oid, 'EXECUTE') is not false
     or exists (select 1 from pg_catalog.pg_proc p cross join lateral pg_catalog.aclexplode(p.proacl) a
                where p.oid = v_oid and a.grantee = 0 and a.privilege_type = 'EXECUTE') then
    raise exception 'POSTCHECK 5323: get_shared_master_set_positions fora do estado esperado';
  end if;
end;
$post$;

-- @@T7 5324 (protegida) sha256=41134dfc643d89e70ff04d969f1835c2c81527c2d07e2ca10f62549ee23a5157
set local lock_timeout = '5s';

do $pre$
begin
  if to_regprocedure('public.v1_13_assert_capability()') is null or to_regprocedure('public.v1_13_capability_open()') is null then raise exception 'PRECHECK G1: barreira 5389 ausente'; end if;  -- G1 (D-E1)
  if to_regprocedure('public.collection_share_role(uuid)') is null
     or to_regprocedure('public.get_my_pokedex_positions(uuid, text, text, integer, integer)') is null
     or to_regclass('public.collection_pokedex_position_assignment') is null
     or to_regclass('public.collection_pokedex_position_primary_representative') is null then
    raise exception 'PRECHECK 5324: dependências ausentes (5302, 5204 e estruturas da Pokédex)';
  end if;
  if exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname = 'get_shared_pokedex_positions') then
    raise exception 'PRECHECK 5324: JÁ APLICADA ou ESTADO DIVERGENTE — get_shared_pokedex_positions já existe';
  end if;
end;
$pre$;

create function public.get_shared_pokedex_positions(
  p_collection_id   uuid,
  p_filter          text    default 'ALL',
  p_generation_code text    default null,
  p_limit           integer default 120,
  p_offset          integer default 0
)
returns table (
  pokedex_position_id             uuid,
  position_number                 integer,
  species_id                      uuid,
  species_name                    text,
  generation_code                 text,
  generation_ordinal              integer,
  species_artwork_path            text,
  is_satisfied                    boolean,
  copies_in_collection            integer,
  representative_card_name        text,
  representative_collector_number text,
  representative_set_code         text,
  representative_image_path       text,
  total_count                     bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_filter text := upper(btrim(coalesce(p_filter, 'ALL')));
  v_role   text;
  v_ref    uuid;
  v_dex    uuid;
  v_scope  text;
begin
  if not public.v1_13_capability_open() then return; end if;  -- G1 (D-E1)
  if v_filter not in ('ALL', 'OWNED', 'MISSING') then
    raise exception 'INVALID_FILTER' using errcode = '22023';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 500
     or p_offset is null or p_offset < 0 or p_offset > 100000 then
    raise exception 'INVALID_PAGE' using errcode = '22023';
  end if;
  if p_collection_id is null then
    return;
  end if;

  -- Fronteira de autorização antes de qualquer tabela de catálogo (padrão 5320).
  v_role := public.collection_share_role(p_collection_id);
  if v_role is null or v_role not in ('OWNER', 'VIEWER') then
    return;
  end if;

  select cr.id, cpr.pokedex_id, cpr.scope_kind into v_ref, v_dex, v_scope
  from public.collection c
  join public.collection_reference cr
    on cr.collection_id = c.id and cr.reference_kind = 'POKEDEX'
  join public.collection_pokedex_reference cpr
    on cpr.collection_reference_id = cr.id
  where c.id = p_collection_id
    and c.mode = 'REFERENCE_BASED'
    and c.completion_policy = 'REFERENCE_POSITION';
  if v_ref is null then
    return;
  end if;

  return query
  with scope as (
    select pp.id as pos_id, pp.position_number as pnum, s.id as sp_id,
           s.canonical_name::text as sp_name, g.code::text as gcode, g.ordinal_number as gord
    from public.pokedex_position pp
    join public.pokemon_species s    on s.id = pp.species_id
    join public.pokemon_generation g on g.id = s.generation_id
    where pp.pokedex_id = v_dex
      and (v_scope = 'FULL_REFERENCE'
           or exists (select 1 from public.collection_pokedex_scope_generation sg
                      where sg.collection_reference_id = v_ref and sg.generation_id = s.generation_id))
      and (p_generation_code is null or g.code = p_generation_code)
  ),
  links as (
    -- só exemplares alocados a ESTA coleção e atribuídos a uma posição
    select a.pokedex_position_id as pos_id, ca.id as alloc_id, ca.physical_card_id as pc_id,
           a.assigned_at, (pr.collection_allocation_id is not null) as is_rep
    from public.collection_allocation ca
    join public.collection_pokedex_position_assignment a on a.collection_allocation_id = ca.id
    left join public.collection_pokedex_position_primary_representative pr
      on pr.collection_allocation_id = ca.id and pr.collection_id = p_collection_id
    where ca.collection_id = p_collection_id
  ),
  assigned as (
    select l.pos_id, count(*)::integer as n
    from links l
    group by l.pos_id
  ),
  page as (
    select sc.pos_id, sc.pnum, sc.sp_id, sc.sp_name, sc.gcode, sc.gord,
           coalesce(asg.n, 0) as n_in, (asg.pos_id is not null) as sat,
           count(*) over () as total
    from scope sc
    left join assigned asg on asg.pos_id = sc.pos_id
    where v_filter = 'ALL'
       or (v_filter = 'OWNED'   and asg.pos_id is not null)
       or (v_filter = 'MISSING' and asg.pos_id is null)
    order by sc.pnum, sc.pos_id
    limit p_limit offset p_offset
  ),
  rep as (
    select distinct on (l.pos_id) l.pos_id, l.pc_id
    from links l
    where l.pos_id in (select pg.pos_id from page pg where pg.sat)
    order by l.pos_id, l.is_rep desc, l.assigned_at, l.alloc_id
  )
  select p.pos_id, p.pnum, p.sp_id, p.sp_name, p.gcode, p.gord,
         art.path,
         p.sat, p.n_in,
         rc.card_name, rc.number, rc.set_code, rc.image_path,
         p.total
  from page p
  left join lateral (
    select w.display_storage_path::text as path
    from public.pokemon_species_artwork w
    where w.pokemon_species_id = p.sp_id
      and w.status = 'IMPORTED'
      and w.display_storage_path is not null
    order by w.created_at, w.id
    limit 1
  ) art on true
  left join lateral (
    select c.name::text as card_name, c.collector_number::text as number, cs.code::text as set_code,
           img.storage_path::text as image_path
    from rep r
    join public.physical_card pc on pc.id = r.pc_id
    join public.card_variant cv  on cv.id = pc.card_variant_id
    join public.card c           on c.id = cv.card_id
    join public.card_set cs      on cs.id = c.card_set_id
    left join lateral (
      select ast.storage_path
      from public.card_asset ast
      join public.card_asset_type cat on cat.id = ast.asset_type_id and cat.code = 'CARD_FRONT'
      join public.language al         on al.id = ast.language_id
      where ast.card_id = c.id
        and ast.is_primary
        and ast.is_active
        and ast.storage_path is not null
      order by (ast.language_id = pc.language_id) desc nulls last,
               (al.code = 'pt-BR') desc,
               (al.code = 'en') desc,
               al.language_order asc
      limit 1
    ) img on true
    where r.pos_id = p.pos_id
  ) rc on true
  order by p.pnum, p.pos_id;
end;
$$;

comment on function public.get_shared_pokedex_positions(uuid, text, text, integer, integer) is
  'V1-13 E1-D (5324): grade Pokédex do participante (OWNER/VIEWER pela 5302; EDITOR lê como VIEWER) — espécies do escopo, arte, satisfação, exemplares e representante desta coleção. Sem copies_available, copies_elsewhere nem acervo_state; nenhuma leitura do acervo (C-243). Mesmo filtro, geração, paginação e ordem da 5204. Sem acesso → zero linhas.';

revoke all on function public.get_shared_pokedex_positions(uuid, text, text, integer, integer) from public, anon;
grant execute on function public.get_shared_pokedex_positions(uuid, text, text, integer, integer) to authenticated;

do $post$
declare
  v_oid oid := to_regprocedure('public.get_shared_pokedex_positions(uuid, text, text, integer, integer)');
begin
  if v_oid is null
     or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = v_oid) is not true
     or (select p.proconfig from pg_catalog.pg_proc p where p.oid = v_oid) is distinct from array['search_path=""']
     or (select p.provolatile from pg_catalog.pg_proc p where p.oid = v_oid) is distinct from 's'
     or pg_catalog.has_function_privilege('authenticated', v_oid, 'EXECUTE') is not true
     or pg_catalog.has_function_privilege('anon', v_oid, 'EXECUTE') is not false
     or exists (select 1 from pg_catalog.pg_proc p cross join lateral pg_catalog.aclexplode(p.proacl) a
                where p.oid = v_oid and a.grantee = 0 and a.privilege_type = 'EXECUTE') then
    raise exception 'POSTCHECK 5324: get_shared_pokedex_positions fora do estado esperado';
  end if;
end;
$post$;

-- @@T7 5388 (protegida) sha256=e0600cf31ad8783bf455d81ee246f56bb44134bbe6ffb1757986ece5af522b59
set local lock_timeout = '5s';

do $pre$
begin
  if to_regprocedure('public.v1_13_assert_capability()') is null or to_regprocedure('public.v1_13_capability_open()') is null then raise exception 'PRECHECK G1: barreira 5389 ausente'; end if;  -- G1 (D-E1)
  if to_regprocedure('public.collection_share_role(uuid)') is null
     or to_regprocedure('public.binder_activity_category(text)') is null
     or to_regclass('public.binder_activity_event') is null
     or to_regclass('public.binder_activity_item') is null
     or to_regclass('public.collection_layout_guest') is null
     or to_regclass('public.collection_layout_catalog_incorporation') is null
     or to_regclass('public.user_profile') is null then
    raise exception 'PRECHECK 5388: dependências ausentes (5302, 5267/5341, 5229, 5263, 1000)';
  end if;
  if not exists (select 1 from information_schema.columns c
                 where c.table_schema = 'public' and c.table_name = 'binder_activity_item'
                   and c.column_name = 'collection_id' and c.data_type = 'uuid')
     or not exists (select 1 from information_schema.columns c
                    where c.table_schema = 'public' and c.table_name = 'binder_activity_event'
                      and c.column_name = 'item_collection_recorded' and c.data_type = 'boolean') then
    raise exception 'PRECHECK 5388: colunas da 5379 (E1-B3) ausentes';
  end if;
  if public.binder_activity_category('CARDS_AUTO_ARRANGED') is distinct from 'CARDS' then
    raise exception 'PRECHECK 5388: categoria de CARDS_AUTO_ARRANGED (5341) ausente';
  end if;
  if exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public'
               and p.proname in ('get_shared_binder_activity', 'get_shared_binder_activity_status')) then
    raise exception 'PRECHECK 5388: JÁ APLICADA ou ESTADO DIVERGENTE — leitura compartilhada do histórico já existe';
  end if;
end;
$pre$;

create function public.get_shared_binder_activity(
  p_collection_id      uuid,
  p_categories         text[]      default null,
  p_before_occurred_at timestamptz default null,
  p_before_id          bigint      default null,
  p_limit              integer     default 20
)
returns table (
  event_id           bigint,
  occurred_at        timestamptz,
  event_type         text,
  category           text,
  source             text,
  is_legacy          boolean,
  actor_role         text,
  actor_display_name text,
  item_count         integer,
  items              jsonb,
  items_truncated    boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_limit  integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_role   text;
  v_owner  uuid;
  v_layout uuid;
begin
  if not public.v1_13_capability_open() then return; end if;  -- G1 (D-E1)
  if (p_before_occurred_at is null) <> (p_before_id is null) then
    raise exception 'cursor must have occurred_at and id together' using errcode = '22023', hint = 'BINDER_ACTIVITY_CURSOR';
  end if;
  if p_categories is not null and not (p_categories <@ array['CARDS','RESERVATIONS','LOCKS','PAGES','CATALOG','BINDER']) then
    raise exception 'unknown category' using errcode = '22023', hint = 'BINDER_ACTIVITY_CATEGORY';
  end if;
  if p_collection_id is null then
    return;
  end if;

  -- Fronteira de autorização antes de qualquer leitura do histórico (padrão 5320/5321).
  v_role := public.collection_share_role(p_collection_id);
  if v_role is null or v_role not in ('OWNER', 'VIEWER') then
    return;
  end if;

  select c.owner_user_id into v_owner from public.collection c where c.id = p_collection_id;
  -- Fichário ATUAL de X: o que ela ancora, senão o do qual é convidada (5321).
  select l.id into v_layout from public.collection_layout l where l.collection_id = p_collection_id;
  if v_layout is null then
    select g.layout_id into v_layout from public.collection_layout_guest g where g.collection_id = p_collection_id;
  end if;
  if v_owner is null or v_layout is null then
    return;
  end if;

  return query
  with page as (
    select e.id, e.occurred_at, e.event_type, e.source, e.actor_user_id, e.collection_id,
           (e.source = 'LEGADO') as legacy
    from public.binder_activity_event e
    where e.owner_user_id = v_owner
      and e.layout_key = v_layout
      -- Categoria A: evento registrado para X. Categoria B (D14): evento SEM coleção
      -- registrada, produzido pelo titular do evento (ator gravado = titular gravado).
      -- Evento registrado para outra coleção nunca entra.
      and (e.collection_id = p_collection_id
           or (e.collection_id is null and e.actor_user_id = e.owner_user_id))
      and (
        -- C-241 + D13: lista de permissão por par tipo/origem, só com atribuição confiável (D12)
        (e.item_collection_recorded
         and ((e.source = 'FICHARIO'
               and e.event_type in ('CARD_PLACED','CARD_MOVED','CARDS_SWAPPED','CARDS_REMOVED',
                                    'POCKET_RESERVED','RESERVATIONS_RELEASED','POCKETS_LOCKED','POCKETS_UNLOCKED',
                                    'GAP_OPENED','GAP_CLOSED','PAGES_ADDED','PAGE_REMOVED','PAGES_REORDERED',
                                    'CARDS_AUTO_ARRANGED'))
              or (e.source = 'CATALOGO' and e.event_type = 'CATALOG_NOVELTIES_INCORPORATED')))
        -- D12: L01 só com a origem comprovada (linha de origem desta coleção neste fichário)
        or (e.collection_id = p_collection_id
            and e.event_type = 'LEGACY_CATALOG_INCORPORATION' and e.source = 'LEGADO' and e.actor_user_id is null
            and exists (select 1 from public.collection_layout_catalog_incorporation ci
                        where ci.layout_id = e.layout_key
                          and ci.collection_id = p_collection_id
                          and ci.item_key = e.summary ->> 'item_key'))
      )
      and (p_categories is null or public.binder_activity_category(e.event_type) = any (p_categories))
      and (p_before_id is null or (e.occurred_at, e.id) < (p_before_occurred_at, p_before_id))
      and exists (
        select 1 from public.binder_activity_item i
        where i.event_id = e.id
          -- VISIBLE-ITEM-RULE (idêntica abaixo)
          and (case
                 when e.source = 'LEGADO' then i.item_kind = 'CARD' and i.effect = 'INCORPORATED'
                 when i.item_kind in ('CARD','RESERVATION','POCKET') then i.collection_id is not distinct from p_collection_id
                 when i.item_kind = 'PAGE' then e.collection_id is not distinct from p_collection_id
                                               and e.event_type in ('GAP_OPENED','GAP_CLOSED','PAGES_ADDED','PAGE_REMOVED','PAGES_REORDERED')
                 else false
               end))
    order by e.occurred_at desc, e.id desc
    limit v_limit
  ),
  vis as (
    select i.event_id, i.ordinal, i.item_kind, i.effect, i.card_id, i.card_name, i.collector_number,
           i.card_set_code, i.variant_type_code, i.variant_type_name,
           i.from_page, i.from_row, i.from_col, i.to_page, i.to_row, i.to_col,
           row_number() over (partition by i.event_id order by i.ordinal) as rn
    from page e
    join public.binder_activity_item i on i.event_id = e.id
    where
      -- VISIBLE-ITEM-RULE (idêntica acima)
      (case
         when e.source = 'LEGADO' then i.item_kind = 'CARD' and i.effect = 'INCORPORATED'
         when i.item_kind in ('CARD','RESERVATION','POCKET') then i.collection_id is not distinct from p_collection_id
         when i.item_kind = 'PAGE' then e.collection_id is not distinct from p_collection_id
                                               and e.event_type in ('GAP_OPENED','GAP_CLOSED','PAGES_ADDED','PAGE_REMOVED','PAGES_REORDERED')
         else false
       end)
  ),
  agg as (
    select v.event_id,
           count(*)::integer as n,
           jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
             'ordinal', v.rn, 'kind', v.item_kind, 'effect', v.effect,
             'card_id', v.card_id, 'card_name', v.card_name, 'collector_number', v.collector_number,
             'card_set_code', v.card_set_code, 'variant_type_code', v.variant_type_code,
             'variant_type_name', v.variant_type_name,
             'from_page', v.from_page, 'from_row', v.from_row, 'from_col', v.from_col,
             'to_page', v.to_page, 'to_row', v.to_row, 'to_col', v.to_col))
             order by v.rn) filter (where v.rn <= 50) as items
    from vis v
    group by v.event_id
  )
  select pg.id, pg.occurred_at, pg.event_type, public.binder_activity_category(pg.event_type), pg.source,
         pg.legacy,
         case when pg.actor_user_id is null then null
              when pg.actor_user_id = v_owner then 'OWNER'
              else 'PARTICIPANT' end,
         case when pg.actor_user_id is null then null
              else (select up.display_name::text from public.user_profile up where up.id = pg.actor_user_id) end,
         a.n,
         coalesce(a.items, '[]'::jsonb),
         a.n > 50
  from page pg
  join agg a on a.event_id = pg.id
  order by pg.occurred_at desc, pg.id desc;
end;
$fn$;

comment on function public.get_shared_binder_activity(uuid, text[], timestamptz, bigint, integer) is
  'V1-13 E1-D (5388): histórico do fichário atual da coleção para participantes (OWNER/VIEWER pela 5302; EDITOR lê como VIEWER). C-241 + D12 + D13 + D14: só eventos atribuídos, registrados para X ou (D14) sem coleção e do titular com item de X, na lista de permissão (E02–E05, E08–E16, E21; L01 só com origem comprovada), só itens de X, contagem recalculada, ordinal renumerado, sem summary/detail/ids/nomes gravados. Ator: papel e nome de exibição público. Histórico integral do titular segue na 5269.';

revoke all on function public.get_shared_binder_activity(uuid, text[], timestamptz, bigint, integer) from public, anon;
grant execute on function public.get_shared_binder_activity(uuid, text[], timestamptz, bigint, integer) to authenticated;

create function public.get_shared_binder_activity_status(p_collection_id uuid)
returns table (
  has_binder             boolean,
  history_may_be_partial boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_role   text;
  v_owner  uuid;
  v_layout uuid;
begin
  if not public.v1_13_capability_open() then return; end if;  -- G1 (D-E1)
  if p_collection_id is null then
    return;
  end if;
  v_role := public.collection_share_role(p_collection_id);
  if v_role is null or v_role not in ('OWNER', 'VIEWER') then
    return;
  end if;

  select c.owner_user_id into v_owner from public.collection c where c.id = p_collection_id;
  select l.id into v_layout from public.collection_layout l where l.collection_id = p_collection_id;
  if v_layout is null then
    select g.layout_id into v_layout from public.collection_layout_guest g where g.collection_id = p_collection_id;
  end if;
  if v_owner is null or v_layout is null then
    return query select false, false;
    return;
  end if;

  return query
  select true,
         exists (
           select 1 from public.binder_activity_event e
           where e.owner_user_id = v_owner
             and e.layout_key = v_layout
             -- mesmas categorias da leitura: registrado para X, ou sem coleção e do
             -- titular (D14). Evento de outra coleção nunca acende o sinal.
             and (e.collection_id = p_collection_id
                  or (e.collection_id is null and e.actor_user_id = e.owner_user_id))
             -- só eventos que a leitura MOSTRARIA se estivessem atribuídos (mesma lista de
             -- permissão): estrutura, acervo e tipos ocultos nunca acendem o aviso
             and ((not e.item_collection_recorded
                   and ((e.source = 'FICHARIO'
                         and e.event_type in ('CARD_PLACED','CARD_MOVED','CARDS_SWAPPED','CARDS_REMOVED',
                                              'POCKET_RESERVED','RESERVATIONS_RELEASED','POCKETS_LOCKED','POCKETS_UNLOCKED',
                                              'GAP_OPENED','GAP_CLOSED','PAGES_ADDED','PAGE_REMOVED','PAGES_REORDERED',
                                              'CARDS_AUTO_ARRANGED'))
                        or (e.source = 'CATALOGO' and e.event_type = 'CATALOG_NOVELTIES_INCORPORATED')))
                  or (e.collection_id = p_collection_id
                      and e.event_type = 'LEGACY_CATALOG_INCORPORATION' and e.source = 'LEGADO'
                      and not exists (select 1 from public.collection_layout_catalog_incorporation ci
                                      where ci.layout_id = e.layout_key
                                        and ci.collection_id = p_collection_id
                                        and ci.item_key = e.summary ->> 'item_key'))));
end;
$fn$;

comment on function public.get_shared_binder_activity_status(uuid) is
  'V1-13 E1-D (5388): estado do histórico compartilhado da coleção (mesmo acesso da get_shared_binder_activity). has_binder; history_may_be_partial = há evento de X, de tipo da lista de permissão, omitido só por falta de atribuição ou de origem (D12) — sinal conservador, não contagem. Só booleanos; nada de outras coleções.';

revoke all on function public.get_shared_binder_activity_status(uuid) from public, anon;
grant execute on function public.get_shared_binder_activity_status(uuid) to authenticated;

do $post$
declare
  f oid;
begin
  foreach f in array array[
    to_regprocedure('public.get_shared_binder_activity(uuid, text[], timestamptz, bigint, integer)'),
    to_regprocedure('public.get_shared_binder_activity_status(uuid)')]
  loop
    if f is null
       or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
       or (select p.proconfig from pg_catalog.pg_proc p where p.oid = f) is distinct from array['search_path=""']
       or (select p.provolatile from pg_catalog.pg_proc p where p.oid = f) is distinct from 's'
       or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not true
       or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false
       or exists (select 1 from pg_catalog.pg_proc p cross join lateral pg_catalog.aclexplode(p.proacl) a
                  where p.oid = f and a.grantee = 0 and a.privilege_type = 'EXECUTE') then
      raise exception 'POSTCHECK 5388: leitura compartilhada do histórico fora do estado esperado (%)', f;
    end if;
  end loop;
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

-- @@T8 harness 5862 [CLOSED] sha256=f6f7dd4e6c3184a861dbf05785c0dc003324c68cde8fabd95668645b0108a260
create or replace function pg_temp.wh_5862_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
as $fn$
declare
  f_pos oid := to_regprocedure('public.get_shared_collection_positions(uuid,text,integer,integer)');
  f_bin oid := to_regprocedure('public.get_shared_collection_binder(uuid)');
  f_pub oid := to_regprocedure('public.get_public_collection_binder(uuid)');
  v_slot uuid; v_real_brand boolean; n3 integer;
  u_a uuid := gen_random_uuid(); u_b uuid := gen_random_uuid(); u_c uuid := gen_random_uuid();
  u_d uuid := gen_random_uuid(); u_e uuid := gen_random_uuid(); u_f uuid := gen_random_uuid();
  v_sfx text := lower(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  v_game uuid; v_pt uuid; v_rar uuid; v_cat uuid; v_std uuid; v_alt uuid;
  v_exp uuid; v_set uuid; k1 uuid; k2 uuid; k3 uuid; k1s uuid; k1a uuid; k2s uuid; k3s uuid;
  v_inv_a uuid; a1 uuid; a2 uuid; a3 uuid; x1 uuid;
  v_bin uuid; v_co uuid; v_cx uuid; v_layout uuid; p record;
  m_b uuid; m_c uuid; m_d uuid; m_f uuid; m_bx uuid;
  j jsonb; v_err text; n integer; n2 integer;
  b_counts bigint[]; e_counts bigint[];
  res jsonb := '[]'::jsonb; r jsonb; cnt integer := 0; passes integer := 0;
  v_expected integer := 33;
begin
  -- S. Estrutura ------------------------------------------------------------------------
  res := res || jsonb_build_object('id','S.1','ok', f_pos is not null and f_bin is not null, 'detail','5320 e 5321 presentes');
  res := res || jsonb_build_object('id','S.2','ok',
    (select bool_and(q.prosecdef and q.proconfig @> array['search_path=""']) from pg_proc q where q.oid in (f_pos, f_bin)),
    'detail','security definer + search_path vazio');
  res := res || jsonb_build_object('id','S.3','ok',
    (select bool_and(has_function_privilege('authenticated', q.oid, 'EXECUTE') and not has_function_privilege('anon', q.oid, 'EXECUTE'))
       from pg_proc q where q.oid in (f_pos, f_bin))
    and not exists (select 1 from pg_proc q, aclexplode(coalesce(q.proacl, '{}')) a where q.oid in (f_pos, f_bin) and a.grantee = 0),
    'detail','EXECUTE só authenticated; nada para anon/PUBLIC');
  res := res || jsonb_build_object('id','S.4','ok',
    not exists (select 1 from pg_proc q, unnest(q.proargnames, q.proargmodes) a(name, mode)
                where q.oid = f_pos and a.mode in ('o','t')
                  and a.name ~* '(available|elsewhere|acervo|inventory|storage|location|price|value|acquired|condition|physical)'),
    'detail','5320 sem colunas de acervo/patrimônio');
  res := res || jsonb_build_object('id','S.5','ok',
    f_pub is not null
    and (select q.prosecdef and q.proconfig @> array['search_path=""'] from pg_proc q where q.oid = f_pub)
    and has_function_privilege('anon', f_pub, 'EXECUTE') and has_function_privilege('authenticated', f_pub, 'EXECUTE')
    and position('true AS show_brand_mark' in pg_get_functiondef(f_pub)) > 0,
    'detail','5322 aplicada: vitrine definer, anon+authenticated, convidada com logomarca padrão');

  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.collection_membership), (select count(*) from public.card),
               (select count(*) from public.collection_layout)]
    into b_counts;

  begin
    -- F. Fixture --------------------------------------------------------------------------
    select g.id into v_game from public.game g where g.code = 'POKEMON';
    select l.id into v_pt from public.language l where l.code = 'pt-BR';
    select t.id into v_std from public.card_variant_type t where t.game_id = v_game and t.code = 'STANDARD';
    select t.id into v_alt from public.card_variant_type t where t.game_id = v_game and t.id <> v_std order by t.code limit 1;
    select c0.rarity_id, c0.category_id into v_rar, v_cat
    from public.card c0 join public.card_set cs0 on cs0.id = c0.card_set_id
    join public.expansion e0 on e0.id = cs0.expansion_id where e0.game_id = v_game limit 1;
    if v_game is null or v_pt is null or v_std is null or v_alt is null or v_rar is null then
      res := res || jsonb_build_object('id','F.0','ok', false, 'detail','pré-requisitos de catálogo ausentes (inclui 2º tipo de variante)');
      raise exception 'MS862' using errcode = 'P0001';
    end if;
    insert into public.expansion (game_id, code, name, release_order)
    values (v_game, 'SHV_' || upper(v_sfx), 'SHV Harness ' || v_sfx,
            (select coalesce(max(x.release_order), 0) + 1000 from public.expansion x where x.game_id = v_game))
    returning id into v_exp;
    insert into public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_exp, 'SHV' || upper(v_sfx), 'SHV Set ' || v_sfx, 'REGULAR', 1, 3, 3) returning id into v_set;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '1', 1, 'SHV K1', true) returning id into k1;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '2', 2, 'SHV K2', true) returning id into k2;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '3', 3, 'SHV K3', true) returning id into k3;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k1, v_std, 1, true) returning id into k1s;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k1, v_alt, 2, false) returning id into k1a;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k2, v_std, 1, true) returning id into k2s;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k3, v_std, 1, true) returning id into k3s;

    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    select x.id, 'authenticated', 'authenticated', x.u || '@example.invalid', jsonb_build_object('username', x.u, 'display_name', 'WH 5862 ' || x.t), now(), now()
    from (values (u_a, 'wh862a_' || v_sfx, 'A'), (u_b, 'wh862b_' || v_sfx, 'B'), (u_c, 'wh862c_' || v_sfx, 'C'),
                 (u_d, 'wh862d_' || v_sfx, 'D'), (u_e, 'wh862e_' || v_sfx, 'E'), (u_f, 'wh862f_' || v_sfx, 'F')) x(id, u, t);
    select i.id into v_inv_a from public.inventory i where i.owner_user_id = u_a;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (k1a, v_pt, v_inv_a) returning id into a1;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (k2s, v_pt, v_inv_a) returning id into a2;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (k3s, v_pt, v_inv_a) returning id into a3;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (k1s, v_pt, v_inv_a) returning id into x1;

    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select x.storage_container_id into v_bin from public.create_my_storage_container(gen_random_uuid(), 'BIN 5862', 'BINDER') x;
    select x.collection_id into v_co from public.create_my_card_set_collection(gen_random_uuid(), v_set, 'CO 5862', v_bin) x;
    select x.collection_id into v_cx from public.create_my_free_collection(gen_random_uuid(), 'CX 5862', v_bin) x;
    perform public.allocate_physical_cards_to_collection(v_co, array[a1, a2]);
    perform public.allocate_physical_cards_to_collection(v_cx, array[x1]);
    select * into p from public.preview_my_collection_binder(v_co, 3, 3, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_co, 3, 3, 'PRINCIPAL_ONLY', p.plan_token);
    perform public.set_my_binder_identity(v_co, 'WH 5862 Fichário', false);
    execute 'reset role';
    select l.id into v_layout from public.collection_layout l where l.collection_id = v_co;
    execute 'set local role authenticated';
    perform public.attach_my_collection_to_binder(v_cx, v_layout);
    -- K2 (a2, só de CO) num bolso: base das provas de mascaramento M.1/M.2.
    execute 'reset role';
    update public.physical_card pc
       set storage_container_id = (select l.storage_container_id from public.collection_layout l where l.id = v_layout)
     where pc.id in (a1, a2, x1);
    select l.show_brand_mark into v_real_brand from public.collection_layout l where l.id = v_layout;
    execute 'set local role authenticated';
    if not exists (select 1 from public.collection_layout_slot_assignment a where a.physical_card_id = a2) then
      select s.id into v_slot
      from public.collection_layout_slot s join public.collection_layout_page pg on pg.id = s.page_id
      where pg.layout_id = v_layout
        and not exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = s.id)
        and not exists (select 1 from public.collection_layout_slot_expected_content e where e.slot_id = s.id)
      order by pg.page_number, s.row_index, s.column_index limit 1;
      perform public.place_my_physical_card_in_slot(v_co, v_slot, a2);
    end if;
    m_b  := (public.invite_collection_member(v_co, 'wh862b_' || v_sfx) ->> 'membership_id')::uuid;
    m_c  := (public.invite_collection_member(v_co, 'wh862c_' || v_sfx) ->> 'membership_id')::uuid;
    m_d  := (public.invite_collection_member(v_co, 'wh862d_' || v_sfx) ->> 'membership_id')::uuid;
    m_f  := (public.invite_collection_member(v_co, 'wh862f_' || v_sfx) ->> 'membership_id')::uuid;
    m_bx := (public.invite_collection_member(v_cx, 'wh862b_' || v_sfx) ->> 'membership_id')::uuid;
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.respond_collection_invite(m_b, true);
    perform public.respond_collection_invite(m_bx, true);
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', u_d::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_d, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.respond_collection_invite(m_d, false);
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', u_f::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_f, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.respond_collection_invite(m_f, true);
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.remove_collection_member(v_co, m_f);
    execute 'reset role';

    res := res || jsonb_build_object('id','F.1','ok',
      v_co is not null and v_cx is not null and v_layout is not null
      and (select count(*) from public.collection_allocation ca where ca.collection_id = v_co) = 2
      and exists (select 1 from public.collection_layout_guest g where g.layout_id = v_layout and g.collection_id = v_cx)
      and (select m.status from public.collection_membership m where m.id = m_b) = 'ACTIVE'
      and (select m.status from public.collection_membership m where m.id = m_c) = 'PENDING'
      and (select m.status from public.collection_membership m where m.id = m_d) = 'DECLINED'
      and not exists (select 1 from public.collection_membership m where m.id = m_f)
      and not exists (select 1 from public.collection_allocation ca where ca.physical_card_id = a3),
      'detail','CO (STANDARD_SET, 2 alocadas, K1 por variante não padrão), CX convidada, B ativo, C pendente, D recusado, F removido, a3 só no acervo');
    res := res || jsonb_build_object('id','F.2','ok',
      exists (select 1 from public.collection_layout_slot_assignment a
              join public.collection_layout_slot s on s.id = a.slot_id
              join public.collection_layout_page pg on pg.id = s.page_id
              where a.physical_card_id = a2 and pg.layout_id = v_layout)
      and v_real_brand = false,
      'detail','K2 (a2, de CO) num bolso do fichário; preferência real de logomarca do fichário dono = ' || coalesce(v_real_brand::text, 'null'));

    -- P. Posições (5320) -------------------------------------------------------------------
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select count(*) into n from (
      (select card_id, collector_number, is_satisfied, copies_in_collection, image_path, total_count, o
         from public.get_my_collection_positions(v_co, 'ALL', 500, 0) with ordinality t(card_id, collector_number, collector_total, card_name, image_path, is_satisfied, copies_in_collection, copies_available, total_count, o)
       except
       select card_id, collector_number, is_satisfied, copies_in_collection, image_path, total_count, o
         from public.get_shared_collection_positions(v_co, 'ALL', 500, 0) with ordinality s(card_id, collector_number, collector_total, card_name, image_path, is_satisfied, copies_in_collection, total_count, o))
      union all
      (select card_id, collector_number, is_satisfied, copies_in_collection, image_path, total_count, o
         from public.get_shared_collection_positions(v_co, 'ALL', 500, 0) with ordinality s(card_id, collector_number, collector_total, card_name, image_path, is_satisfied, copies_in_collection, total_count, o)
       except
       select card_id, collector_number, is_satisfied, copies_in_collection, image_path, total_count, o
         from public.get_my_collection_positions(v_co, 'ALL', 500, 0) with ordinality t(card_id, collector_number, collector_total, card_name, image_path, is_satisfied, copies_in_collection, copies_available, total_count, o))
    ) d;
    select count(*) into n2 from public.get_my_collection_positions(v_co, 'ALL', 500, 0) x where x.card_id = k3 and x.copies_available = 1;
    execute 'reset role';
    res := res || jsonb_build_object('id','P.1','ok', n = 0 and n2 = 1,
      'detail','titular: 5320 ≡ 5169 em carta, ordem, satisfação, cópias, arte e total (' || n || ' divergências); 5169 do titular vê a3 disponível');

    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select string_agg(x.collector_number || ':' || x.is_satisfied || ':' || x.copies_in_collection || ':' || x.total_count, ',' order by o)
      into v_err from public.get_shared_collection_positions(v_co, 'ALL', 500, 0) with ordinality x(card_id, collector_number, collector_total, card_name, image_path, is_satisfied, copies_in_collection, total_count, o);
    res := res || jsonb_build_object('id','P.2','ok', v_err = '1:true:1:3,2:true:1:3,3:false:0:3',
      'detail','VIEWER, Todas, ordem do Set: ' || coalesce(v_err, '(vazio)') || ' — K1 satisfeita por variante não padrão');
    select string_agg(x.collector_number, ',' order by o) into v_err
      from public.get_shared_collection_positions(v_co, 'OWNED', 500, 0) with ordinality x(card_id, collector_number, collector_total, card_name, image_path, is_satisfied, copies_in_collection, total_count, o);
    res := res || jsonb_build_object('id','P.3','ok', v_err = '1,2', 'detail','VIEWER, Tenho: ' || coalesce(v_err, '(vazio)'));
    select string_agg(x.collector_number || ':' || x.copies_in_collection || ':' || x.total_count, ',' order by o) into v_err
      from public.get_shared_collection_positions(v_co, 'MISSING', 500, 0) with ordinality x(card_id, collector_number, collector_total, card_name, image_path, is_satisfied, copies_in_collection, total_count, o);
    res := res || jsonb_build_object('id','P.4','ok', v_err = '3:0:1',
      'detail','VIEWER, Faltam: ' || coalesce(v_err, '(vazio)') || ' — K3 falta embora o titular a tenha no acervo (nada vaza)');
    select count(*) into n from public.get_shared_collection_positions(v_co, 'ALL', 1, 1);
    select count(*) into n2 from public.get_shared_collection_positions(v_cx, 'ALL', 500, 0);
    res := res || jsonb_build_object('id','P.5','ok', n = 1 and n2 = 0, 'detail','paginação (1 linha no offset 1) e coleção livre → zero linhas');
    v_err := null; begin perform count(*) from public.get_shared_collection_positions(v_co, 'XYZ', 10, 0); exception when others then v_err := sqlstate || ' ' || sqlerrm; end;
    res := res || jsonb_build_object('id','P.6','ok', v_err like '22023%INVALID_FILTER%', 'detail', coalesce(v_err, 'aceitou filtro inválido'));
    v_err := null; begin perform count(*) from public.get_shared_collection_positions(v_co, 'ALL', 501, 0); exception when others then v_err := sqlstate || ' ' || sqlerrm; end;
    res := res || jsonb_build_object('id','P.7','ok', v_err like '22023%INVALID_PAGE%', 'detail', coalesce(v_err, 'aceitou p_limit 501'));

    -- B (VIEWER) --------------------------------------------------------------------------
    j := public.get_shared_collection_binder(v_co);
    res := res || jsonb_build_object('id','B.1','ok',
      j ?& array['has_binder','grid_columns','grid_rows','page_count','own_filled_count']
      and (j ->> 'has_binder')::boolean and (j ->> 'grid_columns')::int = 3,
      'detail','chaves da 5314 preservadas');
    res := res || jsonb_build_object('id','B.2','ok',
      j ->> 'binder_name' = 'WH 5862 Fichário' and jsonb_typeof(j -> 'show_brand_mark') = 'boolean' and (j ->> 'show_brand_mark')::boolean = false,
      'detail','coleção dona: nome próprio e logomarca do titular (' || coalesce(j ->> 'binder_name', 'null') || ')');
    res := res || jsonb_build_object('id','B.3','ok',
      not (j ?| array['layout_id','owner_collection_id','owner_collection_name','storage_container_id','storage_name','display_name']),
      'detail','sem chaves privadas');
    j := public.get_shared_collection_binder(v_cx);
    res := res || jsonb_build_object('id','B.4','ok',
      j is not null and (j ->> 'has_binder')::boolean and (j -> 'binder_name') = 'null'::jsonb,
      'detail','coleção convidada: fichário visível, nome do fichário de OUTRA coleção NÃO exposto');
    res := res || jsonb_build_object('id','B.5','ok',
      jsonb_typeof(j -> 'show_brand_mark') = 'boolean' and (j ->> 'show_brand_mark')::boolean = true and v_real_brand = false,
      'detail','coleção convidada: logomarca padrão true; a preferência real do fichário dono (false) não é inferível');
    select count(*) into n from public.get_shared_collection_binder_pages(v_cx, 1, 4) x where x.card_name = 'SHV K2';
    select count(*) into n2 from public.get_shared_collection_binder_pages(v_co, 1, 4) x where x.card_name = 'SHV K2' and x.pocket_state = 'CARD';
    res := res || jsonb_build_object('id','M.1','ok', n = 0 and n2 >= 1,
      'detail','VIEWER: K2 visível nas páginas de CO (' || n2 || ') e ausente nas de CX (' || n || ') — carta de outra coleção mascarada');
    execute 'reset role';

    -- PB. Vitrine pública (5322) -----------------------------------------------------------
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.set_collection_visibility(v_co, 'PUBLIC');
    perform public.set_collection_visibility(v_cx, 'PUBLIC');
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    j := public.get_public_collection_binder(v_co);
    res := res || jsonb_build_object('id','PB.1','ok',
      j is not null and j ->> 'binder_name' = 'WH 5862 Fichário' and (j ->> 'show_brand_mark')::boolean = false,
      'detail','vitrine da coleção dona: nome próprio e preferência real (' || coalesce(j ->> 'binder_name', 'null') || ', ' || coalesce(j ->> 'show_brand_mark', 'null') || ')');
    j := public.get_public_collection_binder(v_cx);
    res := res || jsonb_build_object('id','PB.2','ok',
      j is not null and (j ->> 'has_binder')::boolean and (j -> 'binder_name') = 'null'::jsonb
      and jsonb_typeof(j -> 'show_brand_mark') = 'boolean' and (j ->> 'show_brand_mark')::boolean = true,
      'detail','vitrine da coleção convidada: nome NULL e logomarca padrão true (real do dono = false)');
    select count(*) into n3 from public.get_public_collection_binder_pages(v_cx, 1, 4) x where x.card_name = 'SHV K2';
    res := res || jsonb_build_object('id','M.2','ok', n3 = 0,
      'detail','visitante: K2 (de CO) ausente nas páginas públicas de CX (' || n3 || ')');
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.set_collection_visibility(v_cx, 'PRIVATE');
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    j := public.get_public_collection_binder(v_cx);
    execute 'reset role';
    res := res || jsonb_build_object('id','PB.3','ok', j is null, 'detail','CX privatizada: vitrine NULL na hora');

    -- N. Negação ---------------------------------------------------------------------------
    for p in select * from (values ('C pendente', u_c), ('D recusado', u_d), ('E estranho', u_e), ('F removido', u_f)) v(label, uid) loop
      perform set_config('request.jwt.claim.sub', p.uid::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', p.uid, 'role', 'authenticated')::text, true);
      execute 'set local role authenticated';
      select count(*) into n from public.get_shared_collection_positions(v_co, 'ALL', 500, 0);
      j := public.get_shared_collection_binder(v_co);
      execute 'reset role';
      res := res || jsonb_build_object('id','N.' || p.label,'ok', n = 0 and j is null, 'detail', p.label || ': 5320 = ' || n || ' linhas, 5321 = ' || coalesce(j::text, 'NULL'));
    end loop;
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    v_err := null; begin perform count(*) from public.get_shared_collection_positions(v_co, 'ALL', 10, 0); exception when others then v_err := sqlstate; end;
    res := res || jsonb_build_object('id','N.anon 5320','ok', v_err = '42501', 'detail', coalesce(v_err, 'executou'));
    v_err := null; begin perform public.get_shared_collection_binder(v_co); exception when others then v_err := sqlstate; end;
    res := res || jsonb_build_object('id','N.anon 5321','ok', v_err = '42501', 'detail', coalesce(v_err, 'executou'));
    execute 'reset role';

    -- R. Revogação ao vivo ---------------------------------------------------------------------
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.remove_collection_member(v_co, m_b);
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select count(*) into n from public.get_shared_collection_positions(v_co, 'ALL', 500, 0);
    j := public.get_shared_collection_binder(v_co);
    select count(*) into n2 from public.get_shared_collection_positions(v_cx, 'ALL', 500, 0);
    execute 'reset role';
    res := res || jsonb_build_object('id','R.1','ok', n = 0 and j is null,
      'detail','B removido de CO: 5320 = ' || n || ' linhas, 5321 = ' || coalesce(j::text, 'NULL') || ' (na mesma transação, sem cache)');
    res := res || jsonb_build_object('id','R.2','ok', n2 = 0,
      'detail','participação em CX não abre CO (e CX, livre, não tem grade de Set)');

    raise exception 'MS862' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MS862' then
      res := res || jsonb_build_object('id','X.1','ok', false, 'detail','erro inesperado: ' || sqlstate || ' ' || sqlerrm);
    end if;
  end;

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.collection_membership), (select count(*) from public.card),
               (select count(*) from public.collection_layout)]
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
  select '5862', seq, check_id, status, detail from pg_temp.wh_5862_validate();

-- @@T8 harness 5864 [CLOSED] sha256=47e96959e15447dcd3821ea2f1a887f07be99fff4b057eda53370f57c65a449e
create or replace function pg_temp.wh_5864_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
as $fn$
declare
  f_cur oid := to_regprocedure('public.card_set_logo_is_current(text)');
  v_current bigint; v_orphans bigint; v_anon bigint; v_anon_orphans bigint; v_anon_other bigint;
  v_sample text; v_orphan text; b1 boolean; b2 boolean; b3 boolean; b4 boolean;
  res jsonb := '[]'::jsonb; r jsonb; cnt integer := 0; passes integer := 0;
  v_expected integer := 7;
begin
  res := res || jsonb_build_object('id','S.1','ok',
    f_cur is not null
    and (select q.prosecdef and q.proconfig @> array['search_path=""'] from pg_proc q where q.oid = f_cur)
    and has_function_privilege('anon', f_cur, 'EXECUTE')
    and not exists (select 1 from pg_proc q, aclexplode(coalesce(q.proacl, '{}')) a where q.oid = f_cur and a.grantee = 0),
    'detail','função definer, search_path vazio, EXECUTE anon, nada para PUBLIC');
  res := res || jsonb_build_object('id','S.2','ok',
    (select count(*) from pg_policies where schemaname = 'storage' and tablename = 'objects'
       and policyname = 'card_set_logo_public_current_select' and cmd = 'SELECT'
       and roles = array['anon']::name[] and qual like '%card_set_logo_is_current%' and qual like '%card-set-logo%') = 1
    and not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
       and 'anon' = any(roles) and cmd <> 'SELECT'
       and (coalesce(qual, '') || coalesce(with_check, '')) like '%card-set-logo%'),
    'detail','uma política SELECT só anon, só card-set-logo, delegando à função; nenhuma escrita anon');
  res := res || jsonb_build_object('id','S.3','ok',
    (select count(*) from pg_policies where schemaname = 'storage' and tablename = 'objects'
       and policyname in ('card_set_logo_authenticated_select','card_set_logo_admin_select','card_set_logo_admin_insert',
                          'card_set_logo_admin_update','card_set_logo_admin_delete')) = 5,
    'detail','políticas existentes do bucket intactas (5174 + admin)');

  select count(*) into v_current from storage.objects o
   where o.bucket_id = 'card-set-logo' and exists (select 1 from public.card_set cs where cs.logo_storage_path = o.name);
  select count(*) into v_orphans from storage.objects o
   where o.bucket_id = 'card-set-logo' and not exists (select 1 from public.card_set cs where cs.logo_storage_path = o.name);
  select min(cs.logo_storage_path) into v_sample from public.card_set cs
   where exists (select 1 from storage.objects o where o.bucket_id = 'card-set-logo' and o.name = cs.logo_storage_path);
  select min(o.name) into v_orphan from storage.objects o
   where o.bucket_id = 'card-set-logo' and not exists (select 1 from public.card_set cs where cs.logo_storage_path = o.name);

  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  execute 'set local role anon';
  select count(*) into v_anon from storage.objects o where o.bucket_id = 'card-set-logo';
  select count(*) into v_anon_orphans from storage.objects o
   where o.bucket_id = 'card-set-logo' and o.name = coalesce(v_orphan, '-');
  select count(*) into v_anon_other from storage.objects o
   where o.bucket_id = 'expansion-logo';
  b1 := public.card_set_logo_is_current(coalesce(v_sample, '-'));
  b2 := public.card_set_logo_is_current(coalesce(v_orphan, '-'));
  b3 := public.card_set_logo_is_current('00000000-0000-0000-0000-000000000000/inventado.png');
  b4 := exists (select 1 from storage.objects o where o.bucket_id = 'card-set-logo' and o.name = coalesce(v_sample, '-'));
  execute 'reset role';

  res := res || jsonb_build_object('id','A.1','ok', v_sample is not null and b1 and b4,
    'detail','anon lê o logo atual de um Set (função e RLS real)');
  res := res || jsonb_build_object('id','A.2','ok', v_anon = v_current,
    'detail','anon lista exatamente os logos atuais: ' || v_anon || ' de ' || v_current || ' (objetos no bucket: ' || (v_current + v_orphans) || ')');
  res := res || jsonb_build_object('id','A.3','ok', not b2 and not b3 and v_anon_orphans = 0,
    'detail','logo antigo/substituído (' || v_orphans || ' no bucket) e caminho inventado negados');
  res := res || jsonb_build_object('id','A.4','ok', v_anon_other = 0 and current_user = session_user,
    'detail','anon continua sem nada em expansion-logo (bucket vizinho, sem mudança); papel restaurado');

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
  select '5864', seq, check_id, status, detail from pg_temp.wh_5864_validate();

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

-- @@T8 harness 5889 [OPEN] sha256=7502a8eb7a9ed69ff7e9f72a8eb54d6d126a6fd2eb78c49125b618adf5c7606c
create or replace function pg_temp.wh_5889_as(p_user uuid)
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

create or replace function pg_temp.wh_5889_slot(p_layout uuid, p_row integer, p_col integer)
returns uuid language sql stable as $sl$
  select s.id from public.collection_layout_slot s
  join public.collection_layout_page p on p.id = s.page_id
  where p.layout_id = p_layout and p.page_number = 1 and s.row_index = p_row and s.column_index = p_col;
$sl$;

create or replace function pg_temp.wh_5889_at(p_layout uuid, p_row integer, p_col integer)
returns uuid language sql stable as $at$
  -- exemplar no bolso (page 1, row, col), ou NULL
  select a.physical_card_id from public.collection_layout_slot_assignment a
  where a.slot_id = pg_temp.wh_5889_slot(p_layout, p_row, p_col);
$at$;

create or replace function pg_temp.wh_5889_slotp(p_layout uuid, p_page integer, p_row integer, p_col integer)
returns uuid language sql stable as $sp$
  select s.id from public.collection_layout_slot s
  join public.collection_layout_page p on p.id = s.page_id
  where p.layout_id = p_layout and p.page_number = p_page and s.row_index = p_row and s.column_index = p_col;
$sp$;

create or replace function pg_temp.wh_5889_try(p_sql text)
returns text language plpgsql volatile as $try$
begin
  execute p_sql;
  return 'OK';
exception when others then
  return sqlerrm;
end;
$try$;

create or replace function pg_temp.wh_5889_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  f_auth oid := to_regprocedure('public.assert_collection_binder_editor(uuid)');
  f_scp  oid := to_regprocedure('public.binder_slot_editor_scope(uuid, uuid, uuid, uuid)');
  f_at   oid := to_regprocedure('public.binder_slot_at(uuid, integer, integer, integer)');
  f_rd   oid := to_regprocedure('public.get_shared_binder_placeable_cards(uuid, integer, integer)');
  f_pl   oid := to_regprocedure('public.editor_place_card_in_binder(uuid, integer, integer, integer, uuid)');
  f_mv   oid := to_regprocedure('public.editor_move_binder_card(uuid, integer, integer, integer, integer, integer, integer)');
  f_rm   oid := to_regprocedure('public.editor_remove_binder_card(uuid, integer, integer, integer)');
  u_a uuid := gen_random_uuid(); u_b uuid := gen_random_uuid(); u_v uuid := gen_random_uuid();
  u_e uuid := gen_random_uuid(); u_r uuid := gen_random_uuid(); u_c uuid := gen_random_uuid();
  v_sfx text := lower(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  v_game uuid; v_pt uuid; v_rar uuid; v_cat uuid; v_std uuid; v_exp uuid; v_set uuid;
  k1 uuid; k1s uuid; k2 uuid; k2s uuid; k3 uuid; k3s uuid;
  v_inv_a uuid; v_inv_c uuid;
  a1 uuid; a2 uuid; a3 uuid; a4 uuid; a5 uuid; x1 uuid; x2 uuid; b1 uuid;
  v_bin uuid; v_other uuid; v_co uuid; v_cx uuid; v_layout uuid; v_lc uuid;
  m_b uuid; m_v uuid; m_e uuid; m_r uuid; v_pc uuid;
  p record; j jsonb; v_err text; v_ok boolean; n integer; n2 integer; v_ids uuid[];
  alloc0 text; stor0 text; pc0 bigint; mem0 text; ev0 bigint;
  b_counts bigint[]; e_counts bigint[];
  res jsonb := '[]'::jsonb; r jsonb; cnt integer := 0; passes integer := 0;
  v_expected integer := 56;
begin
  -- 0. Estrutura -------------------------------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    f_auth is not null and f_scp is not null and f_at is not null
    and (select bool_and(q.prosecdef and q.proconfig @> array['search_path=""']
                         and not has_function_privilege('authenticated', q.oid, 'EXECUTE')
                         and not has_function_privilege('anon', q.oid, 'EXECUTE')
                         and not has_function_privilege('service_role', q.oid, 'EXECUTE'))
           from pg_proc q where q.oid in (f_auth, f_scp, f_at)),
    'detail','5371: três funções internas, definer, search_path vazio, sem EXECUTE para API nem service_role');
  res := res || jsonb_build_object('id','0.2','ok',
    f_rd is not null and f_pl is not null and f_mv is not null and f_rm is not null
    and (select bool_and(q.prosecdef and q.proconfig @> array['search_path=""']
                         and has_function_privilege('authenticated', q.oid, 'EXECUTE')
                         and not has_function_privilege('anon', q.oid, 'EXECUTE'))
           from pg_proc q where q.oid in (f_rd, f_pl, f_mv, f_rm)),
    'detail','5373/5374: leitura e três escritas do EDITOR, definer, search_path vazio, só authenticated');
  res := res || jsonb_build_object('id','0.3','ok',
    (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.assert_collection_layout_mutable(uuid)')) = 'd600f36fade0b67c0fd5af33e9965070'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.place_my_physical_card_in_slot(uuid, uuid, uuid)')) = '2672da179d73797ec5329c649b594202'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.move_slot_assignment(uuid, uuid)')) = 'fe149c755b5f3b9181172e600c2238a3'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.remove_slot_assignment(uuid[])')) = 'e4b6c8cd8e8c61554ddc92304d602a73',
    'detail','5122 e funções do titular 5272–5274 byte a byte canônicas');
  res := res || jsonb_build_object('id','0.4','ok',
    (select md5(q.prosrc) from pg_proc q
      where q.oid = to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)'))
        in ('59ec5791e514026b7a8340e104d66f30',   -- 5372 (estágio E1-B1/E1-B2)
            'f8cfba40e442e85056e7c8ce7954d4f4')   -- 5379 (E1-B3: mesma regra do ator + coleção por item)
    and not has_function_privilege('authenticated', to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)'), 'EXECUTE')
    and not has_function_privilege('authenticated', to_regprocedure('public.binder_activity_begin(uuid, text, text, uuid, jsonb)'), 'EXECUTE'),
    'detail','gravação do histórico da 5372 (ou da 5379, que a estende); continua sem EXECUTE para a API');

  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.collection_membership), (select count(*) from public.card),
               (select count(*) from public.collection_layout_slot_assignment), (select count(*) from public.binder_activity_event)]
    into b_counts;

  begin
    -- F. Fixture -------------------------------------------------------------------------
    select g.id into v_game from public.game g where g.code = 'POKEMON';
    select l.id into v_pt from public.language l where l.code = 'pt-BR';
    select t.id into v_std from public.card_variant_type t where t.game_id = v_game and t.code = 'STANDARD';
    select c0.rarity_id, c0.category_id into v_rar, v_cat
    from public.card c0 join public.card_set cs0 on cs0.id = c0.card_set_id
    join public.expansion e0 on e0.id = cs0.expansion_id where e0.game_id = v_game limit 1;
    if v_game is null or v_pt is null or v_std is null or v_rar is null then
      res := res || jsonb_build_object('id','F.1','ok', false, 'detail','pré-requisitos de catálogo ausentes');
      raise exception 'MS889' using errcode = 'P0001';
    end if;
    insert into public.expansion (game_id, code, name, release_order)
    values (v_game, 'EB1_' || upper(v_sfx), 'EB1 Harness ' || v_sfx,
            (select coalesce(max(x.release_order), 0) + 1000 from public.expansion x where x.game_id = v_game))
    returning id into v_exp;
    insert into public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_exp, 'EB1' || upper(v_sfx), 'EB1 Set ' || v_sfx, 'REGULAR', 1, 3, 3) returning id into v_set;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '1', 1, 'EB1 K1', true) returning id into k1;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '2', 2, 'EB1 K2', true) returning id into k2;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '3', 3, 'EB1 K3', true) returning id into k3;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k1, v_std, 1, true) returning id into k1s;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k2, v_std, 1, true) returning id into k2s;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k3, v_std, 1, true) returning id into k3s;

    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    select u.id, 'authenticated', 'authenticated', 'wh889' || u.t || '_' || v_sfx || '@example.invalid',
           jsonb_build_object('username', 'wh889' || u.t || '_' || v_sfx, 'display_name', 'WH 5889 ' || upper(u.t)), now(), now()
    from (values (u_a, 'a'), (u_b, 'b'), (u_v, 'v'), (u_e, 'e'), (u_r, 'r'), (u_c, 'c')) u(id, t);
    select i.id into v_inv_a from public.inventory i where i.owner_user_id = u_a;
    select i.id into v_inv_c from public.inventory i where i.owner_user_id = u_c;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, created_at)
    select v.cv, v_pt, v_inv_a, now() - (v.o || ' min')::interval
    from (values (k1s, 7), (k1s, 6), (k1s, 5), (k2s, 4), (k1s, 3), (k3s, 2), (k3s, 1)) v(cv, o);
    select array_agg(pc.id order by pc.created_at) into v_ids from public.physical_card pc where pc.inventory_id = v_inv_a;
    a1 := v_ids[1]; a2 := v_ids[2]; a3 := v_ids[3]; a4 := v_ids[4]; a5 := v_ids[5]; x1 := v_ids[6]; x2 := v_ids[7];
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (k1s, v_pt, v_inv_c) returning id into b1;

    perform pg_temp.wh_5889_as(u_a);
    select x.storage_container_id into v_bin from public.create_my_storage_container(gen_random_uuid(), 'BIN 5889', 'BINDER') x;
    select x.storage_container_id into v_other from public.create_my_storage_container(gen_random_uuid(), 'BOX 5889', 'BOX') x;
    select x.collection_id into v_co from public.create_my_free_collection(gen_random_uuid(), 'CO 5889', v_bin) x;
    perform public.allocate_physical_cards_to_collection(v_co, array[a1, a2, a3, a5]);
    select * into p from public.preview_my_collection_binder(v_co, 3, 3, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_co, 3, 3, 'PRINCIPAL_ONLY', p.plan_token);
    execute 'reset role';
    select l.id, l.storage_container_id into v_layout, v_lc from public.collection_layout l where l.collection_id = v_co;
    -- CX nasce com o local físico do fichário como padrão (exigência da associação, 5255).
    perform pg_temp.wh_5889_as(u_a);
    select x.collection_id into v_cx from public.create_my_free_collection(gen_random_uuid(), 'CX 5889', v_lc) x;
    perform public.allocate_physical_cards_to_collection(v_cx, array[x1, x2]);
    execute 'reset role';
    -- Normaliza o fichário (passo privilegiado, como o catálogo): sem posições/reservas da montagem.
    delete from public.collection_layout_slot_assignment a using public.collection_layout_slot s, public.collection_layout_page p2
     where a.slot_id = s.id and s.page_id = p2.id and p2.layout_id = v_layout;
    delete from public.collection_layout_slot_expected_content e using public.collection_layout_slot s, public.collection_layout_page p2
     where e.slot_id = s.id and s.page_id = p2.id and p2.layout_id = v_layout;
    update public.physical_card pc set storage_container_id = v_lc where pc.id in (a1, a2, a4, a5, x1, x2);
    update public.physical_card pc set storage_container_id = v_other where pc.id = a3;
    perform pg_temp.wh_5889_as(u_a);
    perform public.attach_my_collection_to_binder(v_cx, v_layout);
    perform public.place_my_physical_card_in_slot(v_co, pg_temp.wh_5889_slot(v_layout, 1, 1), a1);
    perform public.place_my_physical_card_in_slot(v_cx, pg_temp.wh_5889_slot(v_layout, 1, 2), x1);
    perform public.set_slot_expected_content(pg_temp.wh_5889_slot(v_layout, 1, 3), k3, null, null, v_cx);
    perform public.set_slot_expected_content(pg_temp.wh_5889_slot(v_layout, 2, 1), k1, null, null, v_co);
    perform public.set_slot_lock(array[pg_temp.wh_5889_slot(v_layout, 2, 2)], true);
    m_b := (public.invite_collection_member(v_co, 'wh889b_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_v := (public.invite_collection_member(v_co, 'wh889v_' || v_sfx) ->> 'membership_id')::uuid;
    m_r := (public.invite_collection_member(v_co, 'wh889r_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_e := (public.invite_collection_member(v_cx, 'wh889e_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    perform pg_temp.wh_5889_as(u_b); perform public.respond_collection_invite(m_b, true);
    perform pg_temp.wh_5889_as(u_v); perform public.respond_collection_invite(m_v, true);
    perform pg_temp.wh_5889_as(u_r); perform public.respond_collection_invite(m_r, true);
    perform pg_temp.wh_5889_as(u_e); perform public.respond_collection_invite(m_e, true);
    perform pg_temp.wh_5889_as(u_a); perform public.remove_collection_member(v_co, m_r);
    execute 'reset role';
    select string_agg(ca.physical_card_id::text || ':' || ca.collection_id::text, ',' order by ca.physical_card_id) into alloc0
      from public.collection_allocation ca where ca.physical_card_id in (a1, a2, a3, a4, a5, x1, x2, b1);
    select string_agg(pc.id::text || ':' || coalesce(pc.storage_container_id::text, '-'), ',' order by pc.id) into stor0
      from public.physical_card pc where pc.id in (a1, a2, a3, a4, a5, x1, x2, b1);
    select count(*) into pc0 from public.physical_card pc where pc.inventory_id in (v_inv_a, v_inv_c);
    select string_agg(m.id::text || ':' || m.role || ':' || m.status, ',' order by m.id) into mem0
      from public.collection_membership m where m.collection_id in (v_co, v_cx);
    select count(*) into ev0 from public.binder_activity_event e where e.layout_key = v_layout;
    res := res || jsonb_build_object('id','F.2','ok',
      v_lc is not null and pg_temp.wh_5889_at(v_layout, 1, 1) = a1 and pg_temp.wh_5889_at(v_layout, 1, 2) = x1
      and (select count(*) from public.collection_layout_slot s join public.collection_layout_page p2 on p2.id = s.page_id
            where p2.layout_id = v_layout and p2.page_number = 1) = 9
      and exists (select 1 from public.collection_layout_guest g where g.layout_id = v_layout and g.collection_id = v_cx),
      'detail','fixture: fichário 3×3 de CO com CX convidada; carta, reserva e trava nos bolsos previstos');

    -- 1. Autorização -----------------------------------------------------------------------
    perform pg_temp.wh_5889_as(u_v);
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_place_card_in_binder(%L, 1, 3, 1, %L)', v_co, a2));
    res := res || jsonb_build_object('id','1.1','ok', v_err = 'COLLECTION_NOT_FOUND', 'detail','VIEWER não escreve: ' || v_err);
    perform pg_temp.wh_5889_as(u_c);
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_place_card_in_binder(%L, 1, 3, 1, %L)', v_co, a2));
    res := res || jsonb_build_object('id','1.2','ok', v_err = 'COLLECTION_NOT_FOUND', 'detail','estranho não escreve: ' || v_err);
    perform pg_temp.wh_5889_as(u_a);
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_place_card_in_binder(%L, 1, 3, 1, %L)', v_co, a2));
    res := res || jsonb_build_object('id','1.3','ok', v_err = 'COLLECTION_NOT_FOUND', 'detail','titular não usa o caminho do EDITOR: ' || v_err);
    perform pg_temp.wh_5889_as(u_r);
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_place_card_in_binder(%L, 1, 3, 1, %L)', v_co, a2));
    res := res || jsonb_build_object('id','1.4','ok', v_err = 'COLLECTION_NOT_FOUND', 'detail','EDITOR removido não escreve: ' || v_err);
    perform pg_temp.wh_5889_as(u_e);
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_place_card_in_binder(%L, 1, 3, 1, %L)', v_co, a2));
    res := res || jsonb_build_object('id','1.5','ok', v_err = 'COLLECTION_NOT_FOUND', 'detail','EDITOR de CX não escreve em CO, mesmo fichário: ' || v_err);
    perform pg_temp.wh_5889_as(null);
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_place_card_in_binder(%L, 1, 3, 1, %L)', v_co, a2));
    res := res || jsonb_build_object('id','1.6','ok', v_err like 'permission denied%', 'detail','anon sem EXECUTE: ' || v_err);
    perform pg_temp.wh_5889_as(u_a); perform public.set_collection_member_role(v_co, m_b, 'VIEWER');
    perform pg_temp.wh_5889_as(u_b);
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_place_card_in_binder(%L, 1, 3, 1, %L)', v_co, a2));
    perform pg_temp.wh_5889_as(u_a); perform public.set_collection_member_role(v_co, m_b, 'EDITOR');
    res := res || jsonb_build_object('id','1.7','ok', v_err = 'COLLECTION_NOT_FOUND' and pg_temp.wh_5889_at(v_layout, 3, 1) is null,
      'detail','EDITOR rebaixado a VIEWER perde a escrita na hora: ' || v_err);

    -- 2. Exemplares elegíveis ----------------------------------------------------------------
    perform pg_temp.wh_5889_as(u_b);
    select array_agg(x.physical_card_id order by x.physical_card_id), max(x.total_count) into v_ids, n
      from public.get_shared_binder_placeable_cards(v_co, 96, 0) x;
    res := res || jsonb_build_object('id','2.1','ok',
      v_ids = (select array_agg(y order by y) from unnest(array[a2, a5]) y) and n = 2,
      'detail','lista do EDITOR = a2 e a5 (alocados a CO, no fichário, fora de bolso); nunca a1 (no bolso), a3 (outro local), a4 (sem coleção), x1/x2 (CX)');
    res := res || jsonb_build_object('id','2.2','ok',
      not exists (select 1 from pg_proc q, unnest(q.proargnames, q.proargmodes) a(name, mode)
                  where q.oid = f_rd and a.mode = 't'
                    and a.name ~ '(storage|location|condition|price|value|paid|acqui|note|favorite|wish|owner|collection|allocation)'),
      'detail','leitura sem colunas de local, condição, valores, aquisição, favoritos, wishlist, titular ou alocação');
    perform pg_temp.wh_5889_as(u_v); n := (select count(*) from public.get_shared_binder_placeable_cards(v_co, 96, 0));
    perform pg_temp.wh_5889_as(u_c); n := n + (select count(*) from public.get_shared_binder_placeable_cards(v_co, 96, 0));
    perform pg_temp.wh_5889_as(u_a); n := n + (select count(*) from public.get_shared_binder_placeable_cards(v_co, 96, 0));
    perform pg_temp.wh_5889_as(u_r); n := n + (select count(*) from public.get_shared_binder_placeable_cards(v_co, 96, 0));
    perform pg_temp.wh_5889_as(u_e); n := n + (select count(*) from public.get_shared_binder_placeable_cards(v_co, 96, 0));
    res := res || jsonb_build_object('id','2.3','ok', n = 0,
      'detail','VIEWER, estranho, titular, ex-EDITOR e EDITOR de outra coleção recebem zero linhas');
    perform pg_temp.wh_5889_as(u_e);
    select array_agg(x.physical_card_id) into v_ids from public.get_shared_binder_placeable_cards(v_cx, 96, 0) x;
    res := res || jsonb_build_object('id','2.4','ok', v_ids = array[x2],
      'detail','EDITOR de CX vê só x2 (de CX, no fichário, fora de bolso)');

    -- 3. Colocar --------------------------------------------------------------------------------
    perform pg_temp.wh_5889_as(u_b);
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_place_card_in_binder(%L, 1, 1, 2, %L)', v_co, a2));
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    res := res || jsonb_build_object('id','3.1','ok', v_err = 'SLOT_NOT_EDITABLE' and pg_temp.wh_5889_at(v_layout, 1, 2) = x1,
      'detail','bolso com carta de CX → SLOT_NOT_EDITABLE; x1 intacto');
    perform pg_temp.wh_5889_as(u_b);  -- E1E: volta ao mesmo cliente
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_place_card_in_binder(%L, 1, 1, 3, %L)', v_co, a2));
    res := res || jsonb_build_object('id','3.2','ok', v_err = 'SLOT_NOT_EDITABLE', 'detail','bolso "vazio" com reserva de CX → mesma recusa');
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_place_card_in_binder(%L, 1, 2, 2, %L)', v_co, a2));
    res := res || jsonb_build_object('id','3.3','ok', v_err = 'SLOT_NOT_EDITABLE', 'detail','bolso fixado e vazio → mesma recusa (não revela a trava)');
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_place_card_in_binder(%L, 99, 1, 1, %L)', v_co, a2));
    res := res || jsonb_build_object('id','3.4','ok', v_err = 'SLOT_NOT_EDITABLE', 'detail','posição inexistente → mesma recusa');
    v_err := '';
    foreach v_pc in array array[a3, a4, x2, b1, gen_random_uuid()] loop
      v_err := v_err || pg_temp.wh_5889_try(format('select * from public.editor_place_card_in_binder(%L, 1, 3, 1, %L)', v_co, v_pc)) || ';';
    end loop;
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    res := res || jsonb_build_object('id','3.5','ok',
      v_err = repeat('PHYSICAL_CARD_NOT_ELIGIBLE;', 5) and pg_temp.wh_5889_at(v_layout, 3, 1) is null,
      'detail','outro local, sem coleção, de CX, de outro titular e forjado → a MESMA recusa; nada posicionado');
    perform pg_temp.wh_5889_as(u_b);  -- E1E: volta ao mesmo cliente
    select x.operation into v_err from public.editor_place_card_in_binder(v_co, 1, 3, 1, a2) x;
    execute 'reset role';
    res := res || jsonb_build_object('id','3.6','ok', v_err = 'ADD' and pg_temp.wh_5889_at(v_layout, 3, 1) = a2,
      'detail','a2 colocado num bolso livre (ADD)');
    perform pg_temp.wh_5889_as(u_b);
    select x.operation into v_err from public.editor_place_card_in_binder(v_co, 1, 3, 1, a2) x;
    res := res || jsonb_build_object('id','3.7','ok', v_err = 'UNCHANGED', 'detail','mesmo bolso → UNCHANGED');
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_place_card_in_binder(%L, 1, 3, 2, %L)', v_co, a2));
    res := res || jsonb_build_object('id','3.8','ok', v_err = 'CARD_ALREADY_PLACED', 'detail','exemplar já em outro bolso → CARD_ALREADY_PLACED');
    select x.operation into v_err from public.editor_place_card_in_binder(v_co, 1, 2, 1, a5) x;
    execute 'reset role';
    res := res || jsonb_build_object('id','3.9','ok', v_err = 'ADD' and pg_temp.wh_5889_at(v_layout, 2, 1) = a5
      and exists (select 1 from public.collection_layout_slot_expected_content e where e.slot_id = pg_temp.wh_5889_slot(v_layout, 2, 1)),
      'detail','bolso com reserva de CO aceita a carta; a reserva continua no bolso');
    perform pg_temp.wh_5889_as(u_b);
    perform public.editor_remove_binder_card(v_co, 1, 2, 1);
    select x.operation into v_err from public.editor_place_card_in_binder(v_co, 1, 1, 1, a5) x;
    execute 'reset role';
    res := res || jsonb_build_object('id','3.10','ok', v_err = 'REPLACE' and pg_temp.wh_5889_at(v_layout, 1, 1) = a5
      and not exists (select 1 from public.collection_layout_slot_assignment a where a.physical_card_id = a1),
      'detail','REPLACE de carta de CO: a1 sai do bolso, a5 entra');

    -- 4. Mover / trocar ---------------------------------------------------------------------------
    perform pg_temp.wh_5889_as(u_b);
    select x.operation into v_err from public.editor_move_binder_card(v_co, 1, 3, 1, 1, 3, 2) x;
    execute 'reset role';
    res := res || jsonb_build_object('id','4.1','ok', v_err = 'MOVE' and pg_temp.wh_5889_at(v_layout, 3, 2) = a2 and pg_temp.wh_5889_at(v_layout, 3, 1) is null,
      'detail','MOVE de a2 entre bolsos livres/próprios');
    perform pg_temp.wh_5889_as(u_b);
    select x.operation into v_err from public.editor_move_binder_card(v_co, 1, 3, 2, 1, 1, 1) x;
    execute 'reset role';
    res := res || jsonb_build_object('id','4.2','ok', v_err = 'SWAP' and pg_temp.wh_5889_at(v_layout, 1, 1) = a2 and pg_temp.wh_5889_at(v_layout, 3, 2) = a5,
      'detail','SWAP entre duas cartas de CO');
    perform pg_temp.wh_5889_as(u_b);
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_move_binder_card(%L, 1, 1, 1, 1, 1, 2)', v_co));
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    res := res || jsonb_build_object('id','4.3','ok', v_err = 'SLOT_NOT_EDITABLE' and pg_temp.wh_5889_at(v_layout, 1, 2) = x1 and pg_temp.wh_5889_at(v_layout, 1, 1) = a2,
      'detail','trocar com carta de CX → SLOT_NOT_EDITABLE; nada muda');
    perform pg_temp.wh_5889_as(u_b);  -- E1E: volta ao mesmo cliente
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_move_binder_card(%L, 1, 1, 2, 1, 3, 3)', v_co));
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    res := res || jsonb_build_object('id','4.4','ok', v_err = 'SLOT_NOT_EDITABLE' and pg_temp.wh_5889_at(v_layout, 1, 2) = x1,
      'detail','mover carta de CX → SLOT_NOT_EDITABLE');
    perform pg_temp.wh_5889_as(u_b);  -- E1E: volta ao mesmo cliente
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_move_binder_card(%L, 1, 1, 1, 1, 1, 3)', v_co));
    res := res || jsonb_build_object('id','4.5','ok', v_err = 'SLOT_NOT_EDITABLE', 'detail','mover para bolso com reserva de CX → SLOT_NOT_EDITABLE');
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_move_binder_card(%L, 1, 1, 1, 1, 2, 2)', v_co));
    res := res || jsonb_build_object('id','4.6','ok', v_err = 'SLOT_NOT_EDITABLE', 'detail','mover para bolso fixado vazio → SLOT_NOT_EDITABLE');
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_move_binder_card(%L, 1, 2, 1, 1, 3, 3)', v_co));
    res := res || jsonb_build_object('id','4.7','ok', v_err = 'SLOT_EMPTY', 'detail','origem só com reserva de CO → SLOT_EMPTY');
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_move_binder_card(%L, 1, 3, 3, 1, 3, 1)', v_co));
    res := res || jsonb_build_object('id','4.8','ok', v_err = 'SLOT_NOT_EDITABLE', 'detail','origem livre (sem nada) → SLOT_NOT_EDITABLE');
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_move_binder_card(%L, 1, 1, 1, 1, 1, 1)', v_co));
    res := res || jsonb_build_object('id','4.9','ok', v_err = 'INVALID_ARGUMENT', 'detail','origem = destino → INVALID_ARGUMENT');

    -- 5. Retirar ----------------------------------------------------------------------------------
    select x.operation into v_err from public.editor_remove_binder_card(v_co, 1, 3, 2) x;
    execute 'reset role';
    res := res || jsonb_build_object('id','5.1','ok', v_err = 'REMOVED' and pg_temp.wh_5889_at(v_layout, 3, 2) is null
      and exists (select 1 from public.collection_allocation ca where ca.physical_card_id = a5 and ca.collection_id = v_co)
      and (select pc.storage_container_id from public.physical_card pc where pc.id = a5) = v_lc,
      'detail','retirar a5: posição sai; alocação a CO e local do fichário ficam');
    perform pg_temp.wh_5889_as(u_b);
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_remove_binder_card(%L, 1, 1, 2)', v_co));
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    res := res || jsonb_build_object('id','5.2','ok', v_err = 'SLOT_NOT_EDITABLE' and pg_temp.wh_5889_at(v_layout, 1, 2) = x1,
      'detail','retirar carta de CX → SLOT_NOT_EDITABLE; x1 fica');
    perform pg_temp.wh_5889_as(u_b);  -- E1E: volta ao mesmo cliente
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_remove_binder_card(%L, 1, 2, 1)', v_co));
    n := 0; if v_err = 'SLOT_EMPTY' then n := 1; end if;
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_remove_binder_card(%L, 1, 3, 3)', v_co));
    res := res || jsonb_build_object('id','5.3','ok', n = 1 and v_err = 'SLOT_NOT_EDITABLE',
      'detail','retirar de bolso só com reserva de CO → SLOT_EMPTY; de bolso livre → SLOT_NOT_EDITABLE');
    perform pg_temp.wh_5889_as(u_v);
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_remove_binder_card(%L, 1, 1, 1)', v_co));
    res := res || jsonb_build_object('id','5.4','ok', v_err = 'COLLECTION_NOT_FOUND', 'detail','VIEWER não retira');

    -- 6. Várias coleções: EDITOR de CX --------------------------------------------------------------
    perform pg_temp.wh_5889_as(u_e);
    select x.operation into v_err from public.editor_place_card_in_binder(v_cx, 1, 3, 3, x2) x;
    execute 'reset role';
    res := res || jsonb_build_object('id','6.1','ok', v_err = 'ADD' and pg_temp.wh_5889_at(v_layout, 3, 3) = x2,
      'detail','EDITOR de CX (convidada) coloca x2 num bolso livre do fichário compartilhado');
    perform pg_temp.wh_5889_as(u_e);
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_remove_binder_card(%L, 1, 1, 1)', v_cx))
          || ';' || pg_temp.wh_5889_try(format('select * from public.editor_move_binder_card(%L, 1, 3, 3, 1, 2, 1)', v_cx));
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    res := res || jsonb_build_object('id','6.2','ok', v_err = 'SLOT_NOT_EDITABLE;SLOT_NOT_EDITABLE' and pg_temp.wh_5889_at(v_layout, 1, 1) = a2,
      'detail','EDITOR de CX não retira carta de CO nem move para bolso com reserva de CO');
    perform pg_temp.wh_5889_as(u_e);  -- E1E: volta ao mesmo cliente
    select x.operation into v_err from public.editor_move_binder_card(v_cx, 1, 1, 2, 1, 1, 3) x;
    execute 'reset role';
    res := res || jsonb_build_object('id','6.3','ok', v_err = 'MOVE' and pg_temp.wh_5889_at(v_layout, 1, 3) = x1
      and exists (select 1 from public.collection_layout_slot_expected_content e
                  where e.slot_id = pg_temp.wh_5889_slot(v_layout, 1, 3) and e.collection_id = v_cx),
      'detail','EDITOR de CX move x1 para o bolso reservado para CX; a reserva fica');

    -- 7. Histórico ------------------------------------------------------------------------------------
    res := res || jsonb_build_object('id','7.1','ok',
      (select count(*) from public.binder_activity_event e where e.layout_key = v_layout and e.actor_user_id = u_b) >= 6
      and not exists (select 1 from public.binder_activity_event e
                      where e.layout_key = v_layout and e.actor_user_id = u_b
                        and (e.owner_user_id <> u_a or e.collection_id is distinct from v_co))
      and not exists (select 1 from public.binder_activity_event e
                      where e.layout_key = v_layout and e.actor_user_id = u_e
                        and (e.owner_user_id <> u_a or e.collection_id is distinct from v_cx)),
      'detail','eventos do EDITOR: titular A como dono do evento, ator EDITOR, coleção autorizada registrada');
    res := res || jsonb_build_object('id','7.2','ok',
      not exists (select 1 from public.binder_activity_event e
                  where e.layout_key = v_layout and e.actor_user_id in (u_v, u_c, u_r)),
      'detail','nenhuma tentativa recusada gerou evento');
    perform pg_temp.wh_5889_as(u_b);
    v_err := pg_temp.wh_5889_try(format('select public.binder_activity_begin(%L, %L, %L, %L)', v_layout, 'CARD_PLACED', 'FICHARIO', v_co))
          || ';' || pg_temp.wh_5889_try(format('select public.assert_collection_binder_editor(%L)', v_co))
          || ';' || pg_temp.wh_5889_try(format('select public.binder_slot_editor_scope(%L, %L, %L, %L)', v_layout, v_co, v_co, gen_random_uuid()));
    res := res || jsonb_build_object('id','7.3','ok', v_err ~ '^permission denied.*;permission denied.*;permission denied',
      'detail','internas (histórico, autorização, classificação) fora do alcance direto do EDITOR');

    -- 8. Titular intocado ------------------------------------------------------------------------------
    perform pg_temp.wh_5889_as(u_a);
    perform public.move_slot_assignment(pg_temp.wh_5889_slot(v_layout, 1, 3), pg_temp.wh_5889_slot(v_layout, 2, 3));
    perform public.remove_slot_assignment(array[pg_temp.wh_5889_slot(v_layout, 2, 3)]);
    perform public.place_my_physical_card_in_slot(v_co, pg_temp.wh_5889_slot(v_layout, 3, 1), a1);
    execute 'reset role';
    res := res || jsonb_build_object('id','8.1','ok',
      pg_temp.wh_5889_at(v_layout, 2, 3) is null and pg_temp.wh_5889_at(v_layout, 3, 1) = a1
      and not exists (select 1 from public.collection_layout_slot_assignment a where a.physical_card_id = x1),
      'detail','titular continua movendo e retirando carta de CX e colocando carta de CO (5272–5274)');
    res := res || jsonb_build_object('id','8.2','ok',
      exists (select 1 from public.binder_activity_event e where e.layout_key = v_layout and e.actor_user_id = u_a
              and e.event_type = 'CARD_PLACED' and e.collection_id = v_co),
      'detail','eventos do titular seguem com o titular como ator');

    -- 9. Patrimônio ------------------------------------------------------------------------------------
    res := res || jsonb_build_object('id','9.1','ok',
      (select string_agg(ca.physical_card_id::text || ':' || ca.collection_id::text, ',' order by ca.physical_card_id)
         from public.collection_allocation ca where ca.physical_card_id in (a1, a2, a3, a4, a5, x1, x2, b1)) = alloc0,
      'detail','alocações intactas');
    res := res || jsonb_build_object('id','9.2','ok',
      (select string_agg(pc.id::text || ':' || coalesce(pc.storage_container_id::text, '-'), ',' order by pc.id)
         from public.physical_card pc where pc.id in (a1, a2, a3, a4, a5, x1, x2, b1)) = stor0
      and (select count(*) from public.physical_card pc where pc.inventory_id in (v_inv_a, v_inv_c)) = pc0,
      'detail','locais físicos e exemplares intactos (nada excluído, nada movido de local)');
    res := res || jsonb_build_object('id','9.3','ok',
      (select string_agg(m.id::text || ':' || m.role || ':' || m.status, ',' order by m.id)
         from public.collection_membership m where m.collection_id in (v_co, v_cx)) = mem0
      and (select c.owner_user_id from public.collection c where c.id = v_co) = u_a,
      'detail','participações e titularidade intactas');
    res := res || jsonb_build_object('id','9.4','ok',
      not exists (select 1 from public.collection_layout_slot_assignment a where a.physical_card_id in (a3, a4, b1)),
      'detail','nenhum exemplar inelegível chegou a um bolso');

    -- 10. Estados compostos e coleção arquivada (REVIEW-02) ------------------------------------------
    -- Página 2 (titular). Imagem e região inseridas por passo privilegiado, como o catálogo:
    -- os gatilhos de integridade (5232/5238) continuam valendo; o caminho de escrita delas
    -- (imagens do titular, mesclagem) não é objeto da E1-B1.
    v_err := 'OK';
    begin
      perform pg_temp.wh_5889_as(u_a);
      perform public.add_layout_page(v_layout);
      execute 'reset role';
      insert into public.collection_layout_slot_image (slot_id, owner_user_id, storage_path)
      values (pg_temp.wh_5889_slotp(v_layout, 2, 1, 1), u_a, u_a::text || '/' || v_layout::text || '/' || gen_random_uuid()::text || '.webp');  -- E1E: C1 — caminho canônico (uuid), atende aos CHECKs 5232
      insert into public.collection_layout_region (page_id, top_row, left_column, height, width)
      values ((select p2.id from public.collection_layout_page p2 where p2.layout_id = v_layout and p2.page_number = 2), 2, 1, 1, 2);
    exception when others then
      v_err := sqlerrm;
    end;
    execute 'reset role';
    perform pg_temp.wh_5889_as(u_b);
    select count(*) filter (where x.pocket_state = 'EMPTY'
                              and (x.row_index, x.column_index) in ((1, 1), (2, 1), (2, 2))) into n
      from public.get_shared_collection_binder_pages(v_co, 2, 1) x;
    res := res || jsonb_build_object('id','10.1','ok', v_err = 'OK' and n = 3,
      'detail','fixture página 2 (' || v_err || '): para o EDITOR, os bolsos com imagem (r1c1) e com mesclagem (r2c1–r2c2) aparecem como vazios');
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_place_card_in_binder(%L, 2, 1, 1, %L)', v_co, a5))
          || ';' || pg_temp.wh_5889_try(format('select * from public.editor_place_card_in_binder(%L, 2, 2, 2, %L)', v_co, a5))
          || ';' || pg_temp.wh_5889_try(format('select * from public.editor_move_binder_card(%L, 1, 1, 1, 2, 1, 1)', v_co))
          || ';' || pg_temp.wh_5889_try(format('select * from public.editor_move_binder_card(%L, 1, 1, 1, 2, 2, 1)', v_co));
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    res := res || jsonb_build_object('id','10.2','ok',
      v_err = 'SLOT_NOT_EDITABLE;SLOT_NOT_EDITABLE;SLOT_NOT_EDITABLE;SLOT_NOT_EDITABLE'
      and pg_temp.wh_5889_at(v_layout, 1, 1) = a2
      and exists (select 1 from public.collection_layout_slot_image ximg  -- E1E: pré-condição — a fixture existe: página 2 com imagem em r1c1
                  where ximg.slot_id = pg_temp.wh_5889_slotp(v_layout, 2, 1, 1))  -- E1E
      and exists (select 1 from public.collection_layout_region xreg join public.collection_layout_page xpg on xpg.id = xreg.page_id  -- E1E: e mesclagem r2c1–r2c2
                  where xpg.layout_id = v_layout and xpg.page_number = 2 and xreg.top_row = 2 and xreg.left_column = 1  -- E1E
                    and xreg.height = 1 and xreg.width = 2)  -- E1E
      and not exists (select 1 from public.collection_layout_slot_assignment a where a.physical_card_id = a5),
      'detail','bolso "vazio" com imagem ou em mesclagem: colocar e mover recusam com a mesma SLOT_NOT_EDITABLE; nada muda');
    perform pg_temp.wh_5889_as(u_b);  -- E1E: volta ao mesmo cliente
    -- Estado composto: carta de CO + reserva de CX no mesmo bolso (titular monta).
    v_err := 'OK';
    begin
      perform pg_temp.wh_5889_as(u_a);
      perform public.set_slot_expected_content(pg_temp.wh_5889_slotp(v_layout, 2, 3, 1), k3, null, null, v_cx);
      perform public.place_my_physical_card_in_slot(v_co, pg_temp.wh_5889_slotp(v_layout, 2, 3, 1), a5);
    exception when others then
      v_err := sqlerrm;
    end;
    perform pg_temp.wh_5889_as(u_b);
    v_err := v_err || ';' || pg_temp.wh_5889_try(format('select * from public.editor_remove_binder_card(%L, 2, 3, 1)', v_co))
          || ';' || pg_temp.wh_5889_try(format('select * from public.editor_move_binder_card(%L, 2, 3, 1, 1, 3, 1)', v_co));
    perform pg_temp.wh_5889_as(u_e);
    v_err := v_err || ';' || pg_temp.wh_5889_try(format('select * from public.editor_place_card_in_binder(%L, 2, 3, 1, %L)', v_cx, x1))
          || ';' || pg_temp.wh_5889_try(format('select * from public.editor_remove_binder_card(%L, 2, 3, 1)', v_cx));
    execute 'reset role';
    res := res || jsonb_build_object('id','10.3','ok',
      v_err = 'OK;SLOT_NOT_EDITABLE;SLOT_NOT_EDITABLE;SLOT_NOT_EDITABLE;SLOT_NOT_EDITABLE'
      and (select a.physical_card_id from public.collection_layout_slot_assignment a
            where a.slot_id = pg_temp.wh_5889_slotp(v_layout, 2, 3, 1)) = a5,
      'detail','carta de CO + reserva de CX no mesmo bolso: nem o EDITOR de CO nem o de CX alteram (' || v_err || ')');
    -- Coleção arquivada (convidada CX).
    v_err := 'OK';
    begin
      perform pg_temp.wh_5889_as(u_a);
      perform public.archive_collection(v_cx);
    exception when others then
      v_err := sqlerrm;
    end;
    perform pg_temp.wh_5889_as(u_e);
    v_err := v_err || ';' || pg_temp.wh_5889_try(format('select * from public.editor_remove_binder_card(%L, 1, 3, 3)', v_cx));
    n := (select count(*) from public.get_shared_binder_placeable_cards(v_cx, 96, 0));
    execute 'reset role';
    res := res || jsonb_build_object('id','10.4','ok', v_err = 'OK;COLLECTION_ARCHIVED' and n = 0
      and pg_temp.wh_5889_at(v_layout, 3, 3) = x2,
      'detail','convidada arquivada: EDITOR de CX recebe COLLECTION_ARCHIVED e lista vazia; x2 fica (' || v_err || ')');

    execute 'reset role';
    raise exception 'MS889' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MS889' then
      res := res || jsonb_build_object('id','X.1','ok', false, 'detail','erro inesperado: '||sqlstate||' '||sqlerrm);
    end if;
  end;

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.collection_membership), (select count(*) from public.card),
               (select count(*) from public.collection_layout_slot_assignment), (select count(*) from public.binder_activity_event)]
    into e_counts;
  res := res || jsonb_build_object('id','99.1','ok', b_counts = e_counts and current_user = session_user,
    'detail','resíduo zero (8 contagens) e papel restaurado');

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
  select '5889', seq, check_id, status, detail from pg_temp.wh_5889_validate();

-- @@T8 harness 5891 [OPEN] sha256=74c9c1fb26da483367de0365e2ccc6d2f67465f86d425ecf2d000cb38dbf35b9
create or replace function pg_temp.wh_5891_as(p_user uuid)
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

create or replace function pg_temp.wh_5891_slot(p_layout uuid, p_row integer, p_col integer)
returns uuid language sql stable as $sl$
  select s.id from public.collection_layout_slot s
  join public.collection_layout_page p on p.id = s.page_id
  where p.layout_id = p_layout and p.page_number = 1 and s.row_index = p_row and s.column_index = p_col;
$sl$;

create or replace function pg_temp.wh_5891_try(p_sql text)
returns text language plpgsql volatile as $try$
begin
  execute p_sql;
  return 'OK';
exception when others then
  return sqlerrm;
end;
$try$;

create or replace function pg_temp.wh_5891_last_event(p_layout uuid, p_actor uuid, p_type text)
returns bigint language sql stable as $le$
  select max(e.id) from public.binder_activity_event e
  where e.layout_key = p_layout and e.actor_user_id = p_actor and e.event_type = p_type;
$le$;

create or replace function pg_temp.wh_5891_item_colls(p_event bigint)
returns text language sql stable as $ic$
  -- "<kind>:<coleção ou ->" de cada item, em ordem
  select string_agg(i.item_kind || ':' || coalesce(i.collection_id::text, '-'), ',' order by i.ordinal)
  from public.binder_activity_item i where i.event_id = p_event;
$ic$;

create or replace function pg_temp.wh_5891_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
as $fn$
#variable_conflict use_column
declare
  f_set oid := to_regprocedure('public.editor_set_pokedex_position_assignment(uuid, uuid, uuid, boolean)');
  f_rem oid := to_regprocedure('public.editor_remove_pokedex_position_assignment(uuid, uuid)');
  f_rep oid := to_regprocedure('public.editor_set_pokedex_position_primary_representative(uuid, uuid)');
  f_clr oid := to_regprocedure('public.editor_clear_pokedex_position_primary_representative(uuid, uuid)');
  f_dex oid := to_regprocedure('public.editor_pokedex_of_collection(uuid)');
  f_add oid := to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)');
  f_scp oid := to_regprocedure('public.binder_slot_editor_scope(uuid, uuid, uuid, uuid)');
  u_a uuid := gen_random_uuid(); u_b uuid := gen_random_uuid(); u_v uuid := gen_random_uuid();
  u_r uuid := gen_random_uuid(); u_e uuid := gen_random_uuid(); u_c uuid := gen_random_uuid();
  u_d uuid := gen_random_uuid();
  v_sfx text := lower(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  v_game uuid; v_pt uuid; v_rar uuid; v_cat uuid; v_std uuid; v_exp uuid; v_set uuid;
  v_gen text; v_pos uuid[]; p1 uuid; p2 uuid; p3 uuid; s1 uuid;
  k1 uuid; k1s uuid; k2 uuid; k2s uuid; k3 uuid; k3s uuid;
  v_inv_a uuid; v_inv_d uuid; a1 uuid; a2 uuid; a3 uuid; x1 uuid; n1 uuid; d1 uuid;
  v_bin uuid; v_bind uuid; v_cp uuid; v_cx uuid; v_dx uuid; v_layout uuid; v_lc uuid;
  m_b uuid; m_v uuid; m_r uuid; m_e uuid;
  p record; v_err text; v_txt text; v_txt2 text; v_txt3 text; v_u uuid; n integer; n2 integer; v_ev bigint; v_ev2 bigint;
  alloc0 text; pc0 text;
  b_counts bigint[]; e_counts bigint[];
  res jsonb := '[]'::jsonb; r jsonb; cnt integer := 0; passes integer := 0;
  v_expected integer := 0;
begin
  -- 0. Estrutura ---------------------------------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    (select count(*) from pg_proc q where q.oid in (f_set, f_rem, f_rep, f_clr)
       and q.prosecdef and q.proconfig @> array['search_path=""']
       and has_function_privilege('authenticated', q.oid, 'EXECUTE')
       and not has_function_privilege('anon', q.oid, 'EXECUTE')) = 4
    and f_dex is not null and not has_function_privilege('authenticated', f_dex, 'EXECUTE')
    and not has_function_privilege('service_role', f_dex, 'EXECUTE'),
    'detail','4 RPCs de Pokédex do EDITOR: definer, search_path vazio, só authenticated; ajudante interno');
  res := res || jsonb_build_object('id','0.2','ok',
    (select md5(q.prosrc) from pg_proc q where q.oid = f_scp) = '21f1b51a3a0f6c80337c2c593cc6054f'
    and (select md5(q.prosrc) from pg_proc q where q.oid = f_add) = 'f8cfba40e442e85056e7c8ce7954d4f4'
    and not has_function_privilege('authenticated', f_add, 'EXECUTE')
    and not has_function_privilege('authenticated', to_regprocedure('public.binder_activity_begin(uuid, text, text, uuid, jsonb)'), 'EXECUTE')
    and (select c.is_nullable from information_schema.columns c where c.table_schema = 'public'
          and c.table_name = 'binder_activity_item' and c.column_name = 'collection_id') = 'YES'
    and (select c.is_nullable || ':' || c.column_default from information_schema.columns c where c.table_schema = 'public'
          and c.table_name = 'binder_activity_event' and c.column_name = 'item_collection_recorded') = 'NO:false',
    'detail','5378 e 5379 no lugar; histórico sem EXECUTE para a API; colunas de atribuição como esperado');
  res := res || jsonb_build_object('id','0.3','ok',
    (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.set_pokedex_position_assignment(uuid, uuid, boolean)')) = '8c572182a03025503e993e5ecc25e07a'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.remove_pokedex_position_assignment(uuid)')) = '26ef2d5da3312661111df0194dfc8ba2'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.set_pokedex_position_primary_representative(uuid)')) = '6353dffe6c3877967997033dcc2bfd4c'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.clear_pokedex_position_primary_representative(uuid, uuid)')) = 'eeede3a5b871fbf07f81eb59ecea932f'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.place_my_physical_card_in_slot(uuid, uuid, uuid)')) = '2672da179d73797ec5329c649b594202'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.move_slot_assignment(uuid, uuid)')) = 'fe149c755b5f3b9181172e600c2238a3'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.set_slot_expected_content(uuid, uuid, uuid, uuid, uuid)')) = '33dde5013dbb491bd4a0452ab7ce8132'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.set_slot_lock(uuid[], boolean)')) = '651048a4bf7d3229904ef2a073c509c5'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.assert_collection_layout_mutable(uuid)')) = 'd600f36fade0b67c0fd5af33e9965070',
    'detail','titular: Pokédex (6123, 6124, 6126, 6125) e fichário (5272, 5273, 5276, 5278, 5122) byte a byte canônicos');
  res := res || jsonb_build_object('id','0.4','ok',
    not exists (select 1 from public.binder_activity_event e
                join public.binder_activity_item i on i.event_id = e.id
                where not e.item_collection_recorded and i.collection_id is not null)
    and not exists (select 1 from public.binder_activity_event e
                    where e.source = 'LEGADO' and e.item_collection_recorded),
    'detail','histórico anterior (e legado L01) nunca tem item atribuído: nenhuma atribuição retroativa');

  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.collection_membership), (select count(*) from public.binder_activity_event),
               (select count(*) from public.binder_activity_item), (select count(*) from public.collection_pokedex_position_assignment),
               (select count(*) from public.collection_pokedex_position_primary_representative),
               (select count(*) from public.collection_layout_slot_species_reference), (select count(*) from public.card_primary_species)]
    into b_counts;

  begin
    -- F. Fixture ---------------------------------------------------------------------------
    select g.id into v_game from public.game g where g.code = 'POKEMON';
    select l.id into v_pt from public.language l where l.code = 'pt-BR';
    select t.id into v_std from public.card_variant_type t where t.game_id = v_game and t.code = 'STANDARD';
    select c.id into v_cat from public.card_category c where c.game_id = v_game and c.code = 'POKEMON';
    select c0.rarity_id into v_rar
    from public.card c0 join public.card_set cs0 on cs0.id = c0.card_set_id
    join public.expansion e0 on e0.id = cs0.expansion_id where e0.game_id = v_game limit 1;
    select g.code, array_agg(pp.id order by pp.position_number)
      into v_gen, v_pos
    from public.pokedex dx
    join public.pokedex_position pp on pp.pokedex_id = dx.id
    join public.pokemon_species sp on sp.id = pp.species_id
    join public.pokemon_generation g on g.id = sp.generation_id
    where dx.code = 'NATIONAL'
      and g.id = (select sp2.generation_id from public.pokedex_position pp2
                  join public.pokemon_species sp2 on sp2.id = pp2.species_id
                  where pp2.pokedex_id = dx.id order by pp2.position_number limit 1)
    group by g.code;
    p1 := v_pos[1]; p2 := v_pos[2]; p3 := v_pos[3];
    select pp.species_id into s1 from public.pokedex_position pp where pp.id = p1;
    if v_game is null or v_pt is null or v_std is null or v_cat is null or v_rar is null or p3 is null then
      res := res || jsonb_build_object('id','F.1','ok', false, 'detail','pré-requisitos de catálogo ou Pokédex NATIONAL ausentes');
      raise exception 'MS891' using errcode = 'P0001';
    end if;
    insert into public.expansion (game_id, code, name, release_order)
    values (v_game, 'EB3_' || upper(v_sfx), 'EB3 Harness ' || v_sfx,
            (select coalesce(max(x.release_order), 0) + 1000 from public.expansion x where x.game_id = v_game))
    returning id into v_exp;
    insert into public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_exp, 'EB3' || upper(v_sfx), 'EB3 Set ' || v_sfx, 'REGULAR', 1, 3, 3) returning id into v_set;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '1', 1, 'EB3 K1', true) returning id into k1;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '2', 2, 'EB3 K2', true) returning id into k2;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '3', 3, 'EB3 K3', true) returning id into k3;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k1, v_std, 1, true) returning id into k1s;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k2, v_std, 1, true) returning id into k2s;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k3, v_std, 1, true) returning id into k3s;

    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    select u.id, 'authenticated', 'authenticated', 'wh891' || u.t || '_' || v_sfx || '@example.invalid',
           jsonb_build_object('username', 'wh891' || u.t || '_' || v_sfx, 'display_name', 'WH 5891 ' || upper(u.t)), now(), now()
    from (values (u_a, 'a'), (u_b, 'b'), (u_v, 'v'), (u_r, 'r'), (u_e, 'e'), (u_c, 'c'), (u_d, 'd')) u(id, t);
    insert into public.card_primary_species (card_id, pokemon_species_id, resolution_basis, resolved_by_user_id)
    values (k1, s1, 'EDITORIAL_RECONCILIATION', u_a);
    select i.id into v_inv_a from public.inventory i where i.owner_user_id = u_a;
    select i.id into v_inv_d from public.inventory i where i.owner_user_id = u_d;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, created_at)
    select v.cv, v_pt, v_inv_a, now() - (v.o || ' min')::interval
    from (values (k1s, 5), (k2s, 4), (k1s, 3), (k3s, 2), (k2s, 1)) v(cv, o);
    select array_agg(pc.id order by pc.created_at) into v_pos from public.physical_card pc where pc.inventory_id = v_inv_a;
    a1 := v_pos[1]; a2 := v_pos[2]; a3 := v_pos[3]; x1 := v_pos[4]; n1 := v_pos[5];
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (k2s, v_pt, v_inv_d) returning id into d1;

    perform pg_temp.wh_5891_as(u_d);
    select x.storage_container_id into v_bind from public.create_my_storage_container(gen_random_uuid(), 'BIN D 5891', 'BINDER') x;
    select x.collection_id into v_dx from public.create_my_free_collection(gen_random_uuid(), 'DX 5891', v_bind) x;
    perform public.allocate_physical_cards_to_collection(v_dx, array[d1]);

    perform pg_temp.wh_5891_as(u_a);
    select x.storage_container_id into v_bin from public.create_my_storage_container(gen_random_uuid(), 'BIN 5891', 'BINDER') x;
    select x.collection_id into v_cp from public.create_my_pokedex_collection(gen_random_uuid(), 'CP 5891', array[v_gen], v_bin) x;
    perform public.allocate_physical_cards_to_collection(v_cp, array[a1, a2, a3]);
    select * into p from public.preview_my_collection_binder(v_cp, 3, 3, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_cp, 3, 3, 'PRINCIPAL_ONLY', p.plan_token);
    execute 'reset role';
    select l.id, l.storage_container_id into v_layout, v_lc from public.collection_layout l where l.collection_id = v_cp;
    delete from public.collection_layout_slot_assignment a using public.collection_layout_slot s, public.collection_layout_page p2
     where a.slot_id = s.id and s.page_id = p2.id and p2.layout_id = v_layout;
    delete from public.collection_layout_slot_expected_content e using public.collection_layout_slot s, public.collection_layout_page p2
     where e.slot_id = s.id and s.page_id = p2.id and p2.layout_id = v_layout;
    update public.physical_card pc set storage_container_id = v_lc where pc.id in (a1, a2, a3, x1, n1);
    delete from public.collection_layout_slot_species_reference sr where sr.layout_id = v_layout;
    insert into public.collection_layout_slot_species_reference (slot_id, layout_id, collection_id, pokedex_position_id)
    values (pg_temp.wh_5891_slot(v_layout, 1, 1), v_layout, v_cp, p1),
           (pg_temp.wh_5891_slot(v_layout, 1, 2), v_layout, v_cp, p2),
           (pg_temp.wh_5891_slot(v_layout, 1, 3), v_layout, v_cp, p3);
    perform pg_temp.wh_5891_as(u_a);
    select x.collection_id into v_cx from public.create_my_free_collection(gen_random_uuid(), 'CX 5891', v_lc) x;
    perform public.allocate_physical_cards_to_collection(v_cx, array[x1]);
    perform public.attach_my_collection_to_binder(v_cx, v_layout);
    m_b := (public.invite_collection_member(v_cp, 'wh891b_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_v := (public.invite_collection_member(v_cp, 'wh891v_' || v_sfx) ->> 'membership_id')::uuid;
    m_r := (public.invite_collection_member(v_cp, 'wh891r_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_e := (public.invite_collection_member(v_cx, 'wh891e_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    perform pg_temp.wh_5891_as(u_b); perform public.respond_collection_invite(m_b, true);
    perform pg_temp.wh_5891_as(u_v); perform public.respond_collection_invite(m_v, true);
    perform pg_temp.wh_5891_as(u_r); perform public.respond_collection_invite(m_r, true);
    perform pg_temp.wh_5891_as(u_e); perform public.respond_collection_invite(m_e, true);
    perform pg_temp.wh_5891_as(u_a); perform public.remove_collection_member(v_cp, m_r);
    execute 'reset role';
    select string_agg(ca.physical_card_id::text || ':' || ca.collection_id::text, ',' order by ca.physical_card_id) into alloc0
      from public.collection_allocation ca where ca.physical_card_id in (a1, a2, a3, x1, n1, d1);
    select string_agg(md5((to_jsonb(pc) - 'updated_at')::text), ',' order by pc.id) into pc0
      from public.physical_card pc where pc.id in (a1, a2, a3, x1, n1, d1);
    res := res || jsonb_build_object('id','F.2','ok',
      v_layout is not null
      and (select string_agg(a.collection_allocation_id::text || ':' || a.pokedex_position_id::text || ':' || a.assignment_basis, ',')
             from public.collection_pokedex_position_assignment a join public.collection_allocation ca on ca.id = a.collection_allocation_id
            where ca.collection_id = v_cp) is not null
      and (select count(*) from public.collection_pokedex_position_assignment a join public.collection_allocation ca on ca.id = a.collection_allocation_id
            where ca.collection_id = v_cp and a.pokedex_position_id = p1 and a.assignment_basis = 'SPECIES_MATCH') = 2
      and (select count(*) from public.collection_layout_slot_species_reference sr where sr.layout_id = v_layout) = 3
      and exists (select 1 from public.collection_layout_guest g where g.layout_id = v_layout and g.collection_id = v_cx),
      'detail','fixture: CP Pokédex com fichário 3×3 e 3 referências de espécie; a1/a3 em P1 pela 6119; CX convidada');

    -- 1. Posição Pokédex pelo EDITOR --------------------------------------------------------------
    perform pg_temp.wh_5891_as(u_b);
    v_err := pg_temp.wh_5891_try(format('select * from public.editor_set_pokedex_position_assignment(%L, %L, %L)', v_cp, a2, p2));
    select x.operation || ':' || x.assignment_basis into v_txt
      from public.editor_set_pokedex_position_assignment(v_cp, a2, p2, true) x;
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    res := res || jsonb_build_object('id','1.1','ok', v_err = 'CONFIRMATION_REQUIRED' and v_txt = 'CREATED:USER_OVERRIDE'
      and (select a.assigned_by_user_id from public.collection_pokedex_position_assignment a
             join public.collection_allocation ca on ca.id = a.collection_allocation_id where ca.physical_card_id = a2) = u_b,
      'detail','sem espécie correspondente exige confirmação; confirmado → CREATED/USER_OVERRIDE com o EDITOR registrado');
    perform pg_temp.wh_5891_as(u_b);  -- E1E: volta ao mesmo cliente
    select x.operation || ':' || x.assignment_basis into v_txt
      from public.editor_set_pokedex_position_assignment(v_cp, a1, p2, true) x;
    select x.operation || ':' || x.assignment_basis into v_txt2
      from public.editor_set_pokedex_position_assignment(v_cp, a1, p1) x;
    select x.operation into v_txt3 from public.editor_set_pokedex_position_assignment(v_cp, a1, p1) x;
    res := res || jsonb_build_object('id','1.2','ok', v_txt = 'MOVED:USER_OVERRIDE' and v_txt2 = 'MOVED:SPECIES_MATCH' and v_txt3 = 'UNCHANGED',
      'detail','mover para outra posição (confirmado), voltar por espécie (SPECIES_MATCH) e repetir → UNCHANGED');
    select x.operation into v_txt from public.editor_remove_pokedex_position_assignment(v_cp, a2) x;
    select x.operation into v_txt2 from public.editor_remove_pokedex_position_assignment(v_cp, a2) x;
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    res := res || jsonb_build_object('id','1.3','ok', v_txt = 'REMOVED' and v_txt2 = 'UNCHANGED'
      and exists (select 1 from public.collection_allocation ca where ca.physical_card_id = a2 and ca.collection_id = v_cp),
      'detail','retirar a posição não desaloca; repetir → UNCHANGED');
    perform pg_temp.wh_5891_as(u_b);  -- E1E: volta ao mesmo cliente
    v_err := pg_temp.wh_5891_try(format('select * from public.editor_set_pokedex_position_assignment(%L, %L, %L, true)', v_cp, a2, gen_random_uuid()));
    res := res || jsonb_build_object('id','1.4','ok', v_err = 'POKEDEX_POSITION_NOT_FOUND',
      'detail','posição inexistente ou de outra Pokédex → POKEDEX_POSITION_NOT_FOUND');

    -- 2. Representante pelo EDITOR ----------------------------------------------------------------
    select x.operation into v_txt from public.editor_set_pokedex_position_primary_representative(v_cp, a1) x;
    select x.operation into v_txt2 from public.editor_set_pokedex_position_primary_representative(v_cp, a3) x;
    select x.operation into v_txt3 from public.editor_set_pokedex_position_primary_representative(v_cp, a3) x;
    res := res || jsonb_build_object('id','2.1','ok', v_txt = 'SET' and v_txt2 = 'REPLACED' and v_txt3 = 'UNCHANGED',
      'detail','escolher, trocar e repetir o representante entre exemplares de CP na mesma posição');
    v_err := pg_temp.wh_5891_try(format('select * from public.editor_set_pokedex_position_primary_representative(%L, %L)', v_cp, a2));
    res := res || jsonb_build_object('id','2.2','ok', v_err = 'POKEDEX_ASSIGNMENT_NOT_FOUND',
      'detail','exemplar de CP sem posição não pode ser representante');
    select x.operation into v_txt from public.editor_clear_pokedex_position_primary_representative(v_cp, p1) x;
    select x.operation into v_txt2 from public.editor_clear_pokedex_position_primary_representative(v_cp, p1) x;
    res := res || jsonb_build_object('id','2.3','ok', v_txt = 'CLEARED' and v_txt2 = 'UNCHANGED',
      'detail','limpar o representante; repetir → UNCHANGED');
    perform public.editor_set_pokedex_position_primary_representative(v_cp, a3);
    perform public.editor_set_pokedex_position_assignment(v_cp, a3, p3, true);
    execute 'reset role';
    res := res || jsonb_build_object('id','2.4','ok',
      not exists (select 1 from public.collection_pokedex_position_primary_representative r
                  where r.collection_id = v_cp and r.pokedex_position_id = p1),
      'detail','mover o representante para outra posição remove o representante antigo em cascata (6120), como no titular');

    -- 3. Recusas da Pokédex -------------------------------------------------------------------------
    perform pg_temp.wh_5891_as(u_b);
    v_err := pg_temp.wh_5891_try(format('select * from public.editor_set_pokedex_position_assignment(%L, %L, %L, true)', v_cp, n1, p2))
          || ';' || pg_temp.wh_5891_try(format('select * from public.editor_set_pokedex_position_assignment(%L, %L, %L, true)', v_cp, x1, p2))
          || ';' || pg_temp.wh_5891_try(format('select * from public.editor_set_pokedex_position_assignment(%L, %L, %L, true)', v_cp, d1, p2))
          || ';' || pg_temp.wh_5891_try(format('select * from public.editor_set_pokedex_position_assignment(%L, %L, %L, true)', v_cp, gen_random_uuid(), p2))
          || ';' || pg_temp.wh_5891_try(format('select * from public.editor_set_pokedex_position_primary_representative(%L, %L)', v_cp, x1))
          || ';' || pg_temp.wh_5891_try(format('select * from public.editor_remove_pokedex_position_assignment(%L, %L)', v_cp, d1));
    res := res || jsonb_build_object('id','3.1','ok',
      v_err = 'PHYSICAL_CARD_NOT_ELIGIBLE;PHYSICAL_CARD_NOT_ELIGIBLE;PHYSICAL_CARD_NOT_ELIGIBLE;PHYSICAL_CARD_NOT_ELIGIBLE;PHYSICAL_CARD_NOT_ELIGIBLE;PHYSICAL_CARD_NOT_ELIGIBLE',
      'detail','sem alocação, de outra coleção, de outra conta ou inexistente → a mesma recusa, nos três caminhos');
    v_err := '';
    foreach v_u in array array[u_v, u_c, u_r, u_a] loop
      perform pg_temp.wh_5891_as(v_u);
      v_err := v_err || pg_temp.wh_5891_try(format('select * from public.editor_set_pokedex_position_assignment(%L, %L, %L, true)', v_cp, a2, p2)) || ';';
    end loop;
    perform pg_temp.wh_5891_as(null);
    v_err := v_err || pg_temp.wh_5891_try(format('select * from public.editor_clear_pokedex_position_primary_representative(%L, %L)', v_cp, p1));
    res := res || jsonb_build_object('id','3.2','ok',
      v_err ~ '^COLLECTION_NOT_FOUND;COLLECTION_NOT_FOUND;COLLECTION_NOT_FOUND;COLLECTION_NOT_FOUND;permission denied',
      'detail','VIEWER, estranho, ex-membro e titular pelo caminho do EDITOR → COLLECTION_NOT_FOUND; anon sem EXECUTE');
    perform pg_temp.wh_5891_as(u_e);
    v_err := pg_temp.wh_5891_try(format('select * from public.editor_set_pokedex_position_assignment(%L, %L, %L, true)', v_cx, x1, p2));
    perform pg_temp.wh_5891_as(u_b);
    v_err := v_err || ';' || pg_temp.wh_5891_try(format('select * from public.editor_set_pokedex_position_assignment(%L, %L, %L, true)', v_cx, x1, p2));
    execute 'reset role';
    res := res || jsonb_build_object('id','3.3','ok', v_err = 'NOT_POKEDEX_COLLECTION;COLLECTION_NOT_FOUND'
      and not exists (select 1 from public.collection_pokedex_position_assignment a join public.collection_allocation ca on ca.id = a.collection_allocation_id
                      where ca.physical_card_id in (n1, x1, d1))
      and not exists (select 1 from public.collection_pokedex_position_assignment a join public.collection_allocation ca on ca.id = a.collection_allocation_id
                      where ca.physical_card_id = a2),
      'detail','EDITOR de coleção livre → NOT_POKEDEX_COLLECTION; EDITOR de CP em CX → COLLECTION_NOT_FOUND; recusas sem efeito');

    -- 4. Referência de espécie no bolso (5378) ------------------------------------------------------
    res := res || jsonb_build_object('id','4.1','ok',
      public.binder_slot_editor_scope(v_layout, v_cp, v_cp, pg_temp.wh_5891_slot(v_layout, 1, 3)) = 'OWN'
      and public.binder_slot_editor_scope(v_layout, v_cp, v_cx, pg_temp.wh_5891_slot(v_layout, 1, 3)) = 'FOREIGN'
      and public.binder_slot_editor_scope(v_layout, v_cp, v_cp, pg_temp.wh_5891_slot(v_layout, 3, 3)) = 'FREE'
      and public.binder_slot_editor_scope(v_layout, v_cp, v_cx, pg_temp.wh_5891_slot(v_layout, 3, 3)) = 'FREE',
      'detail','bolso só com referência de CP: OWN para CP, FOREIGN para a convidada; bolso vazio: FREE para ambas');
    perform pg_temp.wh_5891_as(u_b);
    select x.operation into v_txt from public.editor_set_binder_lock(v_cp, 1, 1, 3, true) x;
    select x.operation into v_txt2 from public.editor_set_binder_lock(v_cp, 1, 1, 3, false) x;
    v_err := pg_temp.wh_5891_try(format('select * from public.editor_place_card_in_binder(%L, 1, 1, 1, %L)', v_cp, a1));
    res := res || jsonb_build_object('id','4.2','ok', v_txt = 'LOCKED' and v_txt2 = 'UNLOCKED' and v_err = 'OK',
      'detail','EDITOR da Pokédex fixa e solta bolso com referência de CP (C-237) e coloca carta nele');
    perform pg_temp.wh_5891_as(u_e);
    v_err := pg_temp.wh_5891_try(format('select * from public.editor_set_binder_reservation(%L, 1, 1, 2, %L)', v_cx, k3))
          || ';' || pg_temp.wh_5891_try(format('select * from public.editor_set_binder_lock(%L, 1, 1, 2, true)', v_cx))
          || ';' || pg_temp.wh_5891_try(format('select * from public.editor_place_card_in_binder(%L, 1, 1, 2, %L)', v_cx, x1))
          || ';' || pg_temp.wh_5891_try(format('select * from public.editor_place_card_in_binder(%L, 1, 2, 1, %L)', v_cx, x1));
    execute 'reset role';
    res := res || jsonb_build_object('id','4.3','ok', v_err = 'SLOT_NOT_EDITABLE;SLOT_NOT_EDITABLE;SLOT_NOT_EDITABLE;OK'
      and not exists (select 1 from public.collection_layout_slot_expected_content e where e.slot_id = pg_temp.wh_5891_slot(v_layout, 1, 2))
      and not (select s.locked from public.collection_layout_slot s where s.id = pg_temp.wh_5891_slot(v_layout, 1, 2)),
      'detail','EDITOR da convidada não reserva, não fixa e não coloca em bolso com referência de CP; bolso livre funciona');

    -- 5. Coleção por item ------------------------------------------------------------------------------
    v_ev := pg_temp.wh_5891_last_event(v_layout, u_b, 'POCKETS_LOCKED');
    v_ev2 := pg_temp.wh_5891_last_event(v_layout, u_b, 'CARD_PLACED');
    res := res || jsonb_build_object('id','5.1','ok',
      pg_temp.wh_5891_item_colls(v_ev) = 'POCKET:' || v_cp::text
      and pg_temp.wh_5891_item_colls(v_ev2) = 'CARD:' || v_cp::text
      and (select bool_and(e.item_collection_recorded and e.collection_id = v_cp and e.owner_user_id = u_a)
             from public.binder_activity_event e where e.id in (v_ev, v_ev2)),
      'detail','eventos do EDITOR de CP: itens de bolso e de carta atribuídos a CP; titular do evento = A; evento marcado');
    v_ev := pg_temp.wh_5891_last_event(v_layout, u_e, 'CARD_PLACED');
    res := res || jsonb_build_object('id','5.2','ok',
      pg_temp.wh_5891_item_colls(v_ev) = 'CARD:' || v_cx::text
      and (select e.collection_id from public.binder_activity_event e where e.id = v_ev) = v_cx,
      'detail','evento do EDITOR da convidada: coleção CX no evento e no item');
    perform pg_temp.wh_5891_as(u_a);
    perform public.move_slot_assignment(pg_temp.wh_5891_slot(v_layout, 1, 1), pg_temp.wh_5891_slot(v_layout, 2, 1));
    perform public.set_slot_expected_content(pg_temp.wh_5891_slot(v_layout, 3, 1), k2, null, null, null);
    perform public.set_slot_expected_content(pg_temp.wh_5891_slot(v_layout, 3, 2), k3, null, null, v_cx);
    perform public.set_slot_lock(array[pg_temp.wh_5891_slot(v_layout, 3, 3)], true);
    perform public.set_slot_lock(array[pg_temp.wh_5891_slot(v_layout, 1, 2)], true);
    execute 'reset role';
    v_ev := pg_temp.wh_5891_last_event(v_layout, u_a, 'CARDS_SWAPPED');
    res := res || jsonb_build_object('id','5.3','ok',
      (select string_agg(coalesce(i.collection_id::text, '-'), ',' order by i.collection_id::text)
         from public.binder_activity_item i where i.event_id = v_ev)
      = (select string_agg(x, ',' order by x) from unnest(array[v_cp::text, v_cx::text]) x),
      'detail','evento do titular com cartas de duas coleções (troca a1 ↔ x1): cada item com a própria coleção');
    res := res || jsonb_build_object('id','5.4','ok',
      exists (select 1 from public.binder_activity_item i join public.binder_activity_event e on e.id = i.event_id
              where e.layout_key = v_layout and e.actor_user_id = u_a and i.item_kind = 'RESERVATION'
                and i.to_row = 3 and i.to_col = 1 and i.collection_id = v_cp)
      and exists (select 1 from public.binder_activity_item i join public.binder_activity_event e on e.id = i.event_id
                  where e.layout_key = v_layout and e.actor_user_id = u_a and i.item_kind = 'RESERVATION'
                    and i.to_row = 3 and i.to_col = 2 and i.collection_id = v_cx),
      'detail','reserva sem coleção registrada → proprietária CP (C-196); reserva para CX → CX');
    res := res || jsonb_build_object('id','5.5','ok',
      exists (select 1 from public.binder_activity_item i join public.binder_activity_event e on e.id = i.event_id
              where e.layout_key = v_layout and e.actor_user_id = u_a and i.item_kind = 'POCKET' and i.effect = 'LOCKED'
                and i.to_row = 3 and i.to_col = 3 and i.collection_id is null)
      and exists (select 1 from public.binder_activity_item i join public.binder_activity_event e on e.id = i.event_id
                  where e.layout_key = v_layout and e.actor_user_id = u_a and i.item_kind = 'POCKET' and i.effect = 'LOCKED'
                    and i.to_row = 1 and i.to_col = 2 and i.collection_id = v_cp),
      'detail','fixar bolso vazio → item sem coleção (nunca atribuído a um membro); bolso com referência de CP → CP');
    res := res || jsonb_build_object('id','5.6','ok',
      not exists (select 1 from public.binder_activity_event e where e.layout_key = v_layout
                  and e.created_xact = pg_current_xact_id() and not e.item_collection_recorded)
      and not exists (select 1 from public.binder_activity_event e join public.binder_activity_item i on i.event_id = e.id
                      where e.layout_key = v_layout and e.actor_user_id <> e.owner_user_id
                        and (i.collection_id is distinct from e.collection_id or i.item_kind in ('COLLECTION', 'BINDER'))),
      'detail','todo evento novo marcado; nenhum evento de EDITOR com item de outra coleção, sem coleção ou estrutural');

    -- 6. Contexto forjado -----------------------------------------------------------------------------
    perform pg_temp.wh_5891_as(u_b);
    v_err := pg_temp.wh_5891_try(format('select public.binder_activity_add_item(%L, %L)', 'CARD', 'PLACED'))
          || ';' || pg_temp.wh_5891_try(format('select public.binder_activity_begin(%L, %L, %L, %L)', v_layout, 'CARD_PLACED', 'FICHARIO', v_cp));
    res := res || jsonb_build_object('id','6.1','ok', v_err ~ '^permission denied.*;permission denied',
      'detail','gravação e abertura do histórico sem EXECUTE para a API');
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    v_ev := pg_temp.wh_5891_last_event(v_layout, u_a, 'CARDS_SWAPPED');
    select count(*) into n from public.binder_activity_item i where i.event_id = v_ev;
    perform pg_temp.wh_5891_as(u_b);  -- E1E: volta ao mesmo cliente
    perform set_config('mmkyu.binder_activity_ctx', jsonb_build_object('depth', 1, 'layout', v_layout, 'type', 'CARDS_SWAPPED',
      'source', 'FICHARIO', 'collection', v_cp, 'summary', '{}'::jsonb, 'event_id', v_ev, 'n', n, 'cap', 0)::text, true);
    v_err := pg_temp.wh_5891_try(format('select * from public.editor_set_binder_lock(%L, 1, 1, 3, true)', v_cp));
    perform set_config('mmkyu.binder_activity_ctx', '', true);
    perform set_config('mmkyu.binder_activity_ctx', jsonb_build_object('depth', 1, 'layout', v_layout, 'type', 'POCKETS_LOCKED',
      'source', 'FICHARIO', 'collection', v_cx, 'summary', '{}'::jsonb, 'event_id', null, 'n', 0, 'cap', 0)::text, true);
    v_err := v_err || ';' || pg_temp.wh_5891_try(format('select * from public.editor_set_binder_lock(%L, 1, 1, 3, true)', v_cp));
    perform set_config('mmkyu.binder_activity_ctx', '', true);
    execute 'reset role';
    select count(*) into n2 from public.binder_activity_item i where i.event_id = v_ev;
    res := res || jsonb_build_object('id','6.2','ok',
      v_err = 'binder activity: event context does not belong to this operation;binder activity: actor is not the binder owner'
      and n2 = n and not (select s.locked from public.collection_layout_slot s where s.id = pg_temp.wh_5891_slot(v_layout, 1, 3)),
      'detail','contexto forjado com evento do titular → recusa (5379); com coleção de que não é EDITOR → recusa (5372); nada gravado');

    -- 7. Revogação -------------------------------------------------------------------------------------
    select count(*) into n from public.binder_activity_event e where e.layout_key = v_layout and e.actor_user_id = u_b;
    perform pg_temp.wh_5891_as(u_a); perform public.set_collection_member_role(v_cp, m_b, 'VIEWER');
    perform pg_temp.wh_5891_as(u_b);
    v_err := pg_temp.wh_5891_try(format('select * from public.editor_set_pokedex_position_assignment(%L, %L, %L, true)', v_cp, a2, p2))
          || ';' || pg_temp.wh_5891_try(format('select * from public.editor_set_pokedex_position_primary_representative(%L, %L)', v_cp, a1))
          || ';' || pg_temp.wh_5891_try(format('select * from public.editor_set_binder_lock(%L, 1, 1, 3, true)', v_cp));
    perform pg_temp.wh_5891_as(u_a); perform public.set_collection_member_role(v_cp, m_b, 'EDITOR');
    execute 'reset role';
    select count(*) into n2 from public.binder_activity_event e where e.layout_key = v_layout and e.actor_user_id = u_b;
    res := res || jsonb_build_object('id','7.1','ok', v_err = 'COLLECTION_NOT_FOUND;COLLECTION_NOT_FOUND;COLLECTION_NOT_FOUND' and n2 = n,
      'detail','EDITOR rebaixado perde Pokédex e fichário na hora; nenhum evento gravado depois da revogação');

    -- 8. Titular intocado --------------------------------------------------------------------------------
    perform pg_temp.wh_5891_as(u_a);
    perform public.set_pokedex_position_assignment(a2, p2, true);
    perform public.set_pokedex_position_primary_representative(
      (select ca.id from public.collection_allocation ca where ca.physical_card_id = a2));
    perform public.clear_pokedex_position_primary_representative(v_cp, p2);
    perform public.remove_pokedex_position_assignment(a2);
    execute 'reset role';
    res := res || jsonb_build_object('id','8.1','ok',
      not exists (select 1 from public.collection_pokedex_position_assignment a join public.collection_allocation ca on ca.id = a.collection_allocation_id
                  where ca.physical_card_id = a2)
      and not exists (select 1 from public.collection_pokedex_position_primary_representative r where r.collection_id = v_cp and r.pokedex_position_id = p2),
      'detail','titular continua posicionando, escolhendo e limpando representante e retirando posição (6122/6124/6126/6125)');
    res := res || jsonb_build_object('id','8.2','ok',
      exists (select 1 from public.binder_activity_event e where e.layout_key = v_layout and e.actor_user_id = u_a
              and e.event_type = 'CARDS_SWAPPED' and e.item_collection_recorded),
      'detail','titular continua gravando histórico pelas funções instrumentadas, agora com coleção por item');

    -- 9. Patrimônio ----------------------------------------------------------------------------------------
    res := res || jsonb_build_object('id','9.1','ok',
      (select string_agg(ca.physical_card_id::text || ':' || ca.collection_id::text, ',' order by ca.physical_card_id)
         from public.collection_allocation ca where ca.physical_card_id in (a1, a2, a3, x1, n1, d1)) = alloc0
      and (select string_agg(md5((to_jsonb(pc) - 'updated_at')::text), ',' order by pc.id)
             from public.physical_card pc where pc.id in (a1, a2, a3, x1, n1, d1)) = pc0,
      'detail','nenhuma alocação, local, condição ou outro campo de exemplar mudou (Pokédex e fichário não são patrimônio)');

    -- 10. Coleção arquivada --------------------------------------------------------------------------------
    perform pg_temp.wh_5891_as(u_a); perform public.archive_collection(v_cp);
    perform pg_temp.wh_5891_as(u_b);
    v_err := pg_temp.wh_5891_try(format('select * from public.editor_set_pokedex_position_assignment(%L, %L, %L, true)', v_cp, a2, p2))
          || ';' || pg_temp.wh_5891_try(format('select * from public.editor_clear_pokedex_position_primary_representative(%L, %L)', v_cp, p1))
          || ';' || pg_temp.wh_5891_try(format('select * from public.editor_remove_pokedex_position_assignment(%L, %L)', v_cp, a1));
    execute 'reset role';
    res := res || jsonb_build_object('id','10.1','ok', v_err = 'COLLECTION_ARCHIVED;COLLECTION_ARCHIVED;COLLECTION_ARCHIVED',
      'detail','Pokédex arquivada: EDITOR recusado só depois de autorizado');

    execute 'reset role';
    raise exception 'MS891' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MS891' then
      res := res || jsonb_build_object('id','X.1','ok', false, 'detail','erro inesperado: '||sqlstate||' '||sqlerrm);
    end if;
  end;

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('mmkyu.binder_activity_ctx', '', true);
  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.collection_membership), (select count(*) from public.binder_activity_event),
               (select count(*) from public.binder_activity_item), (select count(*) from public.collection_pokedex_position_assignment),
               (select count(*) from public.collection_pokedex_position_primary_representative),
               (select count(*) from public.collection_layout_slot_species_reference), (select count(*) from public.card_primary_species)]
    into e_counts;
  res := res || jsonb_build_object('id','99.1','ok', b_counts = e_counts and current_user = session_user,
    'detail','resíduo zero (11 contagens, inclusive histórico, posições, representantes e referências) e papel restaurado');

  v_expected := 33;
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
  select '5891', seq, check_id, status, detail from pg_temp.wh_5891_validate();

-- @@T8 harness 5892 [OPEN] sha256=f5ad58f5e4eb33eef6c82b4ad63b8ab875398d9b240325547c4a9af89c6b0da8
create or replace function pg_temp.wh_5892_as(p_user uuid)
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

create or replace function pg_temp.wh_5892_try(p_sql text)
returns text language plpgsql volatile as $try$
begin
  execute p_sql;
  return 'OK';
exception when others then
  return sqlerrm;
end;
$try$;

create or replace function pg_temp.wh_5892_slot(p_layout uuid, p_page integer, p_row integer, p_col integer)
returns uuid language sql stable as $sl$
  select s.id from public.collection_layout_slot s
  join public.collection_layout_page p on p.id = s.page_id
  where p.layout_id = p_layout and p.page_number = p_page and s.row_index = p_row and s.column_index = p_col;
$sl$;

create or replace function pg_temp.wh_5892_pages(p_layout uuid)
returns integer language sql stable as $pg$
  select count(*)::integer from public.collection_layout_page p where p.layout_id = p_layout;
$pg$;

create or replace function pg_temp.wh_5892_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
as $fn$
#variable_conflict use_column
declare
  v_e1e_np integer;  -- E1E: contagem de páginas lida no contexto do dono
  u_a uuid := gen_random_uuid(); u_b uuid := gen_random_uuid(); u_v uuid := gen_random_uuid();
  u_r uuid := gen_random_uuid(); u_e uuid := gen_random_uuid(); u_c uuid := gen_random_uuid();
  v_sfx text := lower(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  v_game uuid; v_pt uuid; v_rar uuid; v_cat uuid; v_std uuid; v_exp uuid; v_set uuid; v_gen text;
  k1 uuid; k1s uuid;
  v_inv_a uuid; v_ids uuid[]; a1 uuid; s1 uuid; f1 uuid;
  v_bp uuid; v_bs uuid; v_bf uuid;
  v_cp uuid; v_cs uuid; v_cf uuid; v_cg uuid; v_cq uuid; m_bq uuid;
  l_p uuid; l_s uuid; l_f uuid; c_p uuid; c_s uuid; c_f uuid;
  m_b uuid; m_bs uuid; m_bf uuid; m_v uuid; m_r uuid; m_e uuid;
  p record; v_err text; v_txt text; v_tok text; v_u uuid; n integer; n2 integer; np integer; v_page_img uuid;
  v_new integer; v_ord integer[];
  alloc0 text; pc0 text;
  b_counts bigint[]; e_counts bigint[];
  res jsonb := '[]'::jsonb; r jsonb; cnt integer := 0; passes integer := 0;
  v_expected integer := 0;
begin
  -- 0. Estrutura ---------------------------------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    (select count(*) from pg_proc q
      where q.oid in (to_regprocedure('public.editor_add_binder_page(uuid)'),
                      to_regprocedure('public.editor_remove_binder_page(uuid, integer, integer)'),
                      to_regprocedure('public.editor_reorder_binder_pages(uuid, integer[])'),
                      to_regprocedure('public.editor_preview_binder_species_references(uuid)'),
                      to_regprocedure('public.editor_apply_binder_species_references(uuid, text)'),
                      to_regprocedure('public.editor_clear_binder_species_references(uuid, integer)'),
                      to_regprocedure('public.editor_set_binder_species_reference_visibility(uuid, boolean)'))
        and q.prosecdef and q.proconfig @> array['search_path=""']
        and has_function_privilege('authenticated', q.oid, 'EXECUTE')
        and not has_function_privilege('anon', q.oid, 'EXECUTE')) = 7
    and not has_function_privilege('authenticated', to_regprocedure('public.assert_collection_binder_editor_exclusive(uuid)'), 'EXECUTE')
    and not has_function_privilege('authenticated', to_regprocedure('public.editor_species_reference_target_locked(uuid)'), 'EXECUTE')
    and not has_function_privilege('authenticated', to_regprocedure('public.editor_species_reference_summary(uuid, uuid, uuid, text, uuid)'), 'EXECUTE'),
    'detail','7 RPCs do EDITOR: definer, search_path vazio, só authenticated; 3 ajudantes internos');
  res := res || jsonb_build_object('id','0.2','ok',
    exists (select 1 from pg_trigger t where t.tgrelid = 'public.binder_activity_event'::regclass
            and t.tgname = 'trg_bae_editor_event_type' and t.tgenabled = 'O')
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)')) = 'f8cfba40e442e85056e7c8ce7954d4f4'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.binder_slot_editor_scope(uuid, uuid, uuid, uuid)')) = '21f1b51a3a0f6c80337c2c593cc6054f'
    and not exists (select 1 from unnest((select q.proargnames from pg_proc q
                     where q.oid = to_regprocedure('public.editor_preview_binder_species_references(uuid)'))) a(nm)
                    where a.nm = 'slots_with_content'),
    'detail','gatilho de tipos ativo; gravação (5379) e classificação (5378) inalteradas; prévia sem contagem de bolsos ocupados');

  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.collection_membership), (select count(*) from public.collection_layout_page),
               (select count(*) from public.collection_layout_slot), (select count(*) from public.collection_layout_slot_species_reference),
               (select count(*) from public.collection_layout_species_reference_setting),
               (select count(*) from public.binder_activity_event), (select count(*) from public.binder_activity_item)]
    into b_counts;

  begin
    -- F. Fixture ---------------------------------------------------------------------------
    select g.id into v_game from public.game g where g.code = 'POKEMON';
    select l.id into v_pt from public.language l where l.code = 'pt-BR';
    select t.id into v_std from public.card_variant_type t where t.game_id = v_game and t.code = 'STANDARD';
    select c.id into v_cat from public.card_category c where c.game_id = v_game and c.code = 'POKEMON';
    select c0.rarity_id into v_rar
    from public.card c0 join public.card_set cs0 on cs0.id = c0.card_set_id
    join public.expansion e0 on e0.id = cs0.expansion_id where e0.game_id = v_game limit 1;
    select g.code into v_gen
    from public.pokedex dx
    join public.pokedex_position pp on pp.pokedex_id = dx.id
    join public.pokemon_species sp on sp.id = pp.species_id
    join public.pokemon_generation g on g.id = sp.generation_id
    where dx.code = 'NATIONAL' order by pp.position_number limit 1;
    if v_game is null or v_pt is null or v_std is null or v_cat is null or v_rar is null or v_gen is null then
      res := res || jsonb_build_object('id','F.1','ok', false, 'detail','pré-requisitos de catálogo ou Pokédex NATIONAL ausentes');
      raise exception 'MS892' using errcode = 'P0001';
    end if;
    insert into public.expansion (game_id, code, name, release_order)
    values (v_game, 'EC_' || upper(v_sfx), 'EC Harness ' || v_sfx,
            (select coalesce(max(x.release_order), 0) + 1000 from public.expansion x where x.game_id = v_game))
    returning id into v_exp;
    insert into public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_exp, 'EC' || upper(v_sfx), 'EC Set ' || v_sfx, 'REGULAR', 1, 1, 1) returning id into v_set;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '1', 1, 'EC K1', true) returning id into k1;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k1, v_std, 1, true) returning id into k1s;

    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    select u.id, 'authenticated', 'authenticated', 'wh892' || u.t || '_' || v_sfx || '@example.invalid',
           jsonb_build_object('username', 'wh892' || u.t || '_' || v_sfx, 'display_name', 'WH 5892 ' || upper(u.t)), now(), now()
    from (values (u_a, 'a'), (u_b, 'b'), (u_v, 'v'), (u_r, 'r'), (u_e, 'e'), (u_c, 'c')) u(id, t);
    select i.id into v_inv_a from public.inventory i where i.owner_user_id = u_a;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, created_at)
    select k1s, v_pt, v_inv_a, now() - (v.o || ' min')::interval from (values (3), (2), (1)) v(o);
    select array_agg(pc.id order by pc.created_at) into v_ids from public.physical_card pc where pc.inventory_id = v_inv_a;
    a1 := v_ids[1]; s1 := v_ids[2]; f1 := v_ids[3];

    perform pg_temp.wh_5892_as(u_a);
    select x.storage_container_id into v_bp from public.create_my_storage_container(gen_random_uuid(), 'BIN P 5892', 'BINDER') x;
    select x.storage_container_id into v_bs from public.create_my_storage_container(gen_random_uuid(), 'BIN S 5892', 'BINDER') x;
    select x.storage_container_id into v_bf from public.create_my_storage_container(gen_random_uuid(), 'BIN F 5892', 'BINDER') x;
    select x.collection_id into v_cp from public.create_my_pokedex_collection(gen_random_uuid(), 'CP 5892', array[v_gen], v_bp) x;
    select x.collection_id into v_cs from public.create_my_free_collection(gen_random_uuid(), 'CS 5892', v_bs) x;
    select x.collection_id into v_cf from public.create_my_free_collection(gen_random_uuid(), 'CF 5892', v_bf) x;
    perform public.allocate_physical_cards_to_collection(v_cp, array[a1]);
    perform public.allocate_physical_cards_to_collection(v_cs, array[s1]);
    perform public.allocate_physical_cards_to_collection(v_cf, array[f1]);
    select * into p from public.preview_my_collection_binder(v_cp, 2, 2, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_cp, 2, 2, 'PRINCIPAL_ONLY', p.plan_token);
    select * into p from public.preview_my_collection_binder(v_cs, 2, 2, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_cs, 2, 2, 'PRINCIPAL_ONLY', p.plan_token);
    select * into p from public.preview_my_collection_binder(v_cf, 2, 2, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_cf, 2, 2, 'PRINCIPAL_ONLY', p.plan_token);
    execute 'reset role';
    select l.id, l.storage_container_id into l_p, c_p from public.collection_layout l where l.collection_id = v_cp;
    select l.id, l.storage_container_id into l_s, c_s from public.collection_layout l where l.collection_id = v_cs;
    select l.id, l.storage_container_id into l_f, c_f from public.collection_layout l where l.collection_id = v_cf;
    delete from public.collection_layout_slot_assignment a using public.collection_layout_slot s, public.collection_layout_page p2
     where a.slot_id = s.id and s.page_id = p2.id and p2.layout_id in (l_p, l_s, l_f);
    delete from public.collection_layout_slot_expected_content e using public.collection_layout_slot s, public.collection_layout_page p2
     where e.slot_id = s.id and s.page_id = p2.id and p2.layout_id in (l_p, l_s, l_f);
    delete from public.collection_layout_slot_species_reference sr where sr.layout_id in (l_p, l_s, l_f);
    update public.physical_card pc set storage_container_id = c_p where pc.id = a1;
    update public.physical_card pc set storage_container_id = c_s where pc.id = s1;
    update public.physical_card pc set storage_container_id = c_f where pc.id = f1;
    insert into public.collection_layout_slot_image (slot_id, owner_user_id, storage_path)
    values (pg_temp.wh_5892_slot(l_p, 1, 2, 2), u_a, u_a::text || '/' || l_p::text || '/' || gen_random_uuid()::text || '.webp');  -- E1E: C1 — caminho canônico (uuid), atende aos CHECKs 5232
    select s.page_id into v_page_img from public.collection_layout_slot s where s.id = pg_temp.wh_5892_slot(l_p, 1, 2, 2);
    perform pg_temp.wh_5892_as(u_a);
    select x.collection_id into v_cg from public.create_my_free_collection(gen_random_uuid(), 'CG 5892', c_f) x;
    perform public.attach_my_collection_to_binder(v_cg, l_f);
    m_b  := (public.invite_collection_member(v_cp, 'wh892b_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_bs := (public.invite_collection_member(v_cs, 'wh892b_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_bf := (public.invite_collection_member(v_cf, 'wh892b_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_v  := (public.invite_collection_member(v_cp, 'wh892v_' || v_sfx) ->> 'membership_id')::uuid;
    m_r  := (public.invite_collection_member(v_cp, 'wh892r_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_e  := (public.invite_collection_member(v_cg, 'wh892e_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    perform pg_temp.wh_5892_as(u_b);
    perform public.respond_collection_invite(m_b, true);
    perform public.respond_collection_invite(m_bs, true);
    perform public.respond_collection_invite(m_bf, true);
    perform pg_temp.wh_5892_as(u_v); perform public.respond_collection_invite(m_v, true);
    perform pg_temp.wh_5892_as(u_r); perform public.respond_collection_invite(m_r, true);
    perform pg_temp.wh_5892_as(u_e); perform public.respond_collection_invite(m_e, true);
    perform pg_temp.wh_5892_as(u_a); perform public.remove_collection_member(v_cp, m_r);
    execute 'reset role';
    np := pg_temp.wh_5892_pages(l_p);
    select string_agg(ca.physical_card_id::text || ':' || ca.collection_id::text, ',' order by ca.physical_card_id) into alloc0
      from public.collection_allocation ca where ca.physical_card_id in (a1, s1, f1);
    select string_agg(md5((to_jsonb(pc) - 'updated_at')::text), ',' order by pc.id) into pc0
      from public.physical_card pc where pc.id in (a1, s1, f1);
    res := res || jsonb_build_object('id','F.2','ok',
      l_p is not null and l_s is not null and l_f is not null and np between 1 and 30
      and not exists (select 1 from public.collection_layout_guest g where g.layout_id in (l_p, l_s))
      and exists (select 1 from public.collection_layout_guest g where g.layout_id = l_f and g.collection_id = v_cg)
      and exists (select 1 from public.collection_layout_slot_image i where i.slot_id = pg_temp.wh_5892_slot(l_p, 1, 2, 2)),
      'detail','fixture: CP e CS com fichário exclusivo, CF com convidada CG, imagem do titular em CP p1 r2c2');

    -- 1. Páginas no fichário exclusivo -----------------------------------------------------------
    perform pg_temp.wh_5892_as(u_b);
    select x.page_number || ':' || x.slots_created into v_txt from public.editor_add_binder_page(v_cp) x;
    v_new := np + 1;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.1','ok', v_txt = v_new || ':4' and pg_temp.wh_5892_pages(l_p) = v_new
      and exists (select 1 from public.binder_activity_event e where e.layout_key = l_p and e.actor_user_id = u_b
                  and e.event_type = 'PAGES_ADDED' and e.collection_id = v_cp),
      'detail','EDITOR adiciona página vazia no fim (4 bolsos); evento PAGES_ADDED com o EDITOR e CP');
    perform pg_temp.wh_5892_as(u_b);
    select array_agg(g order by g desc) into v_ord from generate_series(1, v_new) g;
    perform count(*) from public.editor_reorder_binder_pages(v_cp, v_ord);
    execute 'reset role';
    res := res || jsonb_build_object('id','1.2','ok',
      (select p2.page_number from public.collection_layout_page p2 where p2.id = v_page_img) = v_new
      and exists (select 1 from public.collection_layout_slot_image i join public.collection_layout_slot s on s.id = i.slot_id
                  where s.page_id = v_page_img and s.row_index = 2 and s.column_index = 2)
      and exists (select 1 from public.binder_activity_event e where e.layout_key = l_p and e.actor_user_id = u_b
                  and e.event_type = 'PAGES_REORDERED'),
      'detail','reordenar move páginas inteiras: a imagem do titular continua no mesmo bolso da mesma página');
    perform pg_temp.wh_5892_as(u_b);
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    select count(*) into n from public.binder_activity_event e where e.layout_key = l_p;
    perform pg_temp.wh_5892_as(u_b);  -- E1E: volta ao mesmo cliente
    v_err := pg_temp.wh_5892_try(format('select * from public.editor_reorder_binder_pages(%L, %L)', v_cp, array[1, 1]::integer[]))
          || ';' || pg_temp.wh_5892_try(format('select * from public.editor_reorder_binder_pages(%L, %L)', v_cp,
                     (select array_agg(g order by g) from generate_series(1, v_new) g)));
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    select count(*) into n2 from public.binder_activity_event e where e.layout_key = l_p;
    perform pg_temp.wh_5892_as(u_b);  -- E1E: volta ao mesmo cliente
    res := res || jsonb_build_object('id','1.3','ok', v_err = 'INVALID_PAGE_ORDER;OK' and n2 = n,
      'detail','ordem inválida recusada; ordem igual à atual → sem evento');
    -- a página nova é agora a página 1 (ordem invertida)
    v_err := pg_temp.wh_5892_try(format('select * from public.editor_remove_binder_page(%L, %s)', v_cp, v_new));
    perform public.editor_place_card_in_binder(v_cp, 1, 1, 1, a1);
    v_err := v_err || ';' || pg_temp.wh_5892_try(format('select * from public.editor_remove_binder_page(%L, 1)', v_cp));
    perform public.editor_remove_binder_card(v_cp, 1, 1, 1);
    perform pg_temp.wh_5892_as(u_a); perform public.set_slot_lock(array[pg_temp.wh_5892_slot(l_p, 1, 2, 1)], true);
    perform pg_temp.wh_5892_as(u_b);
    v_err := v_err || ';' || pg_temp.wh_5892_try(format('select * from public.editor_remove_binder_page(%L, 1)', v_cp));
    perform pg_temp.wh_5892_as(u_a); perform public.set_slot_lock(array[pg_temp.wh_5892_slot(l_p, 1, 2, 1)], false);
    execute 'reset role';
    res := res || jsonb_build_object('id','1.4','ok', v_err = 'OPERATION_RESERVED_TO_OWNER;PAGE_NOT_EMPTY;OPERATION_RESERVED_TO_OWNER'
      and pg_temp.wh_5892_pages(l_p) = v_new,
      'detail','página com imagem do titular ou com bolso vazio fixado pelo titular → reservada ao titular; com carta da coleção → PAGE_NOT_EMPTY; sem contagens');

    -- 2. Fichário de várias coleções ---------------------------------------------------------------
    perform pg_temp.wh_5892_as(u_b);
    v_err := pg_temp.wh_5892_try(format('select * from public.editor_add_binder_page(%L)', v_cf))
          || ';' || pg_temp.wh_5892_try(format('select * from public.editor_reorder_binder_pages(%L, %L)', v_cf, array[1]::integer[]))
          || ';' || pg_temp.wh_5892_try(format('select * from public.editor_remove_binder_page(%L, 1)', v_cf))
          || ';' || pg_temp.wh_5892_try(format('select * from public.editor_set_binder_species_reference_visibility(%L, false)', v_cf))
          || ';' || pg_temp.wh_5892_try(format('select * from public.editor_preview_binder_species_references(%L)', v_cf));
    perform pg_temp.wh_5892_as(u_e);
    v_err := v_err || ';' || pg_temp.wh_5892_try(format('select * from public.editor_add_binder_page(%L)', v_cg))
          || ';' || pg_temp.wh_5892_try(format('select * from public.editor_set_binder_species_reference_visibility(%L, false)', v_cg))
          || ';' || pg_temp.wh_5892_try(format('select * from public.editor_preview_binder_species_references(%L)', v_cg));
    execute 'reset role';
    res := res || jsonb_build_object('id','2.1','ok',
      v_err = 'OPERATION_RESERVED_TO_OWNER;OPERATION_RESERVED_TO_OWNER;OPERATION_RESERVED_TO_OWNER;OPERATION_RESERVED_TO_OWNER;OPERATION_RESERVED_TO_OWNER;OPERATION_RESERVED_TO_OWNER;OPERATION_RESERVED_TO_OWNER;OPERATION_RESERVED_TO_OWNER',
      'detail','fichário com convidada: EDITOR da proprietária e da convidada recusados em páginas e referências (C-237)');
    res := res || jsonb_build_object('id','2.2','ok',
      not exists (select 1 from public.binder_activity_event e where e.layout_key = l_f and e.actor_user_id in (u_b, u_e))
      and not exists (select 1 from public.collection_layout_species_reference_setting st where st.layout_id = l_f),
      'detail','recusas em fichário de várias coleções não gravam nada');

    -- 3. Referências de espécie (Pokédex exclusiva) ------------------------------------------------
    perform pg_temp.wh_5892_as(u_b);
    select * into p from public.editor_preview_binder_species_references(v_cp);
    v_tok := p.plan_token;
    v_err := pg_temp.wh_5892_try(format('select * from public.editor_apply_binder_species_references(%L, %L)', v_cp, repeat('a', 64)));
    select x.operation || ':' || x.reference_count into v_txt from public.editor_apply_binder_species_references(v_cp, v_tok) x;
    execute 'reset role';
    res := res || jsonb_build_object('id','3.1','ok', v_err = 'PLAN_CHANGED' and p.pair_count > 0
      and p.pair_count = least(p.slots_total, p.positions_in_scope) and v_txt = 'APPLIED:' || p.pair_count
      and (select count(*) from public.collection_layout_slot_species_reference sr where sr.layout_id = l_p and sr.collection_id = v_cp) = p.pair_count,
      'detail','prévia com token; token antigo → PLAN_CHANGED; aplicar grava a camada de CP inteira');
    perform pg_temp.wh_5892_as(u_b);
    select * into p from public.editor_preview_binder_species_references(v_cp);
    select x.operation into v_txt from public.editor_apply_binder_species_references(v_cp, p.plan_token) x;
    execute 'reset role';
    res := res || jsonb_build_object('id','3.2','ok', p.already_applied and v_txt = 'ALREADY_APPLIED',
      'detail','aplicar de novo o mesmo plano → ALREADY_APPLIED');
    res := res || jsonb_build_object('id','3.3','ok',
      exists (select 1 from public.collection_layout_slot_image i where i.slot_id = pg_temp.wh_5892_slot(l_p, v_new, 2, 2))
      and public.binder_slot_editor_scope(l_p, v_cp, v_cp, pg_temp.wh_5892_slot(l_p, v_new, 2, 2)) = 'FOREIGN'
      and public.binder_slot_editor_scope(l_p, v_cp, v_cp, pg_temp.wh_5892_slot(l_p, v_new, 1, 1)) = 'OWN',
      'detail','bolso com imagem do titular recebe o rótulo, a imagem fica e o bolso continua FOREIGN; bolso só com referência de CP = OWN');
    perform pg_temp.wh_5892_as(u_b);
    select x.operation into v_txt from public.editor_set_binder_species_reference_visibility(v_cp, false) x;
    select v_txt || ';' || x.operation into v_txt from public.editor_set_binder_species_reference_visibility(v_cp, false) x;
    select v_txt || ';' || x.operation into v_txt from public.editor_set_binder_species_reference_visibility(v_cp, true) x;
    execute 'reset role';
    res := res || jsonb_build_object('id','3.4','ok', v_txt = 'UPDATED;UNCHANGED;UPDATED'
      and (select st.references_visible from public.collection_layout_species_reference_setting st where st.layout_id = l_p),
      'detail','ocultar, repetir (UNCHANGED) e mostrar; nenhum vínculo apagado');
    -- remover página vazia com referências de CP (a página 1, que era a nova)
    perform pg_temp.wh_5892_as(u_b);
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    select count(*)::integer into n from public.collection_layout_slot_species_reference sr
      join public.collection_layout_slot s on s.id = sr.slot_id
      join public.collection_layout_page p2 on p2.id = s.page_id where p2.layout_id = l_p and p2.page_number = 1;
    perform pg_temp.wh_5892_as(u_b);  -- E1E: volta ao mesmo cliente
    v_err := pg_temp.wh_5892_try(format('select * from public.editor_remove_binder_page(%L, 1)', v_cp));
    select x.removed_page_number || ':' || x.species_references_removed into v_txt from public.editor_remove_binder_page(v_cp, 1, n) x;
    execute 'reset role';
    res := res || jsonb_build_object('id','3.5','ok', n = 4 and v_err = 'SPECIES_REFERENCES_ON_PAGE' and v_txt = '1:4'
      and pg_temp.wh_5892_pages(l_p) = np
      and (select p2.page_number from public.collection_layout_page p2 where p2.id = v_page_img) = np
      and exists (select 1 from public.binder_activity_event e where e.layout_key = l_p and e.actor_user_id = u_b
                  and e.event_type = 'PAGE_REMOVED'),
      'detail','página vazia com referências de CP exige a contagem; removida, as demais são renumeradas; evento PAGE_REMOVED');
    perform pg_temp.wh_5892_as(u_b);
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    select count(*)::integer into n from public.collection_layout_slot_species_reference sr where sr.layout_id = l_p;
    perform pg_temp.wh_5892_as(u_b);  -- E1E: volta ao mesmo cliente
    v_err := pg_temp.wh_5892_try(format('select * from public.editor_clear_binder_species_references(%L, %s)', v_cp, n + 1));
    select x.operation || ':' || x.removed_count into v_txt from public.editor_clear_binder_species_references(v_cp, n) x;
    v_err := v_err || ';' || pg_temp.wh_5892_try(format('select * from public.editor_preview_binder_species_references(%L)', v_cs));
    execute 'reset role';
    res := res || jsonb_build_object('id','3.6','ok', v_err = 'COUNT_MISMATCH;NOT_POKEDEX_COLLECTION' and v_txt = 'REMOVED:' || n
      and not exists (select 1 from public.collection_layout_slot_species_reference sr where sr.layout_id = l_p),
      'detail','remover exige a contagem atual; remove a camada inteira; coleção livre → NOT_POKEDEX_COLLECTION');

    -- 4. Recusas de autorização ----------------------------------------------------------------------
    v_err := '';
    foreach v_u in array array[u_v, u_c, u_r, u_a] loop
      perform pg_temp.wh_5892_as(v_u);
      v_err := v_err || pg_temp.wh_5892_try(format('select * from public.editor_add_binder_page(%L)', v_cp)) || ';'
                     || pg_temp.wh_5892_try(format('select * from public.editor_preview_binder_species_references(%L)', v_cp)) || ';';
    end loop;
    perform pg_temp.wh_5892_as(null);
    v_err := v_err || pg_temp.wh_5892_try(format('select * from public.editor_add_binder_page(%L)', v_cp));
    execute 'reset role';
    res := res || jsonb_build_object('id','4.1','ok',
      v_err ~ ('^' || repeat('COLLECTION_NOT_FOUND;', 8) || 'permission denied')
      and pg_temp.wh_5892_pages(l_p) = np,
      'detail','VIEWER, estranho, ex-membro e titular pelo caminho do EDITOR → COLLECTION_NOT_FOUND; anon sem EXECUTE; nada gravado');
    perform pg_temp.wh_5892_as(u_b);
    select x.page_number into n from public.editor_add_binder_page(v_cs) x;
    execute 'reset role';
    res := res || jsonb_build_object('id','4.2','ok', n = pg_temp.wh_5892_pages(l_s),
      'detail','coleção livre com fichário exclusivo: EDITOR também gerencia páginas');

    -- 5. Tipos de evento do EDITOR (5381) --------------------------------------------------------------
    res := res || jsonb_build_object('id','5.1','ok',
      not exists (select 1 from public.binder_activity_event e
                  where e.layout_key in (l_p, l_s, l_f) and e.actor_user_id in (u_b, u_e)
                    and (e.event_type not in ('CARD_PLACED', 'CARD_MOVED', 'CARDS_SWAPPED', 'CARDS_REMOVED',
                                              'POCKET_RESERVED', 'RESERVATIONS_RELEASED', 'POCKETS_LOCKED', 'POCKETS_UNLOCKED',
                                              'PAGES_ADDED', 'PAGE_REMOVED', 'PAGES_REORDERED')
                         or e.source <> 'FICHARIO' or e.collection_id is null)),
      'detail','todo evento do EDITOR é de curadoria, de origem FICHARIO e com coleção');
    perform pg_temp.wh_5892_as(u_b);
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    n := pg_temp.wh_5892_pages(l_p);
    perform pg_temp.wh_5892_as(u_b);  -- E1E: volta ao mesmo cliente
    perform set_config('mmkyu.binder_activity_ctx', jsonb_build_object('depth', 1, 'layout', l_p, 'type', 'BINDER_DISMANTLED',
      'source', 'FICHARIO', 'collection', v_cp, 'summary', '{}'::jsonb, 'event_id', null, 'n', 0, 'cap', 0)::text, true);
    v_err := pg_temp.wh_5892_try(format('select * from public.editor_add_binder_page(%L)', v_cp));
    perform set_config('mmkyu.binder_activity_ctx', jsonb_build_object('depth', 1, 'layout', l_p, 'type', 'PAGES_ADDED',
      'source', 'ACERVO', 'collection', v_cp, 'summary', '{}'::jsonb, 'event_id', null, 'n', 0, 'cap', 0)::text, true);
    v_err := v_err || ';' || pg_temp.wh_5892_try(format('select * from public.editor_add_binder_page(%L)', v_cp));
    perform set_config('mmkyu.binder_activity_ctx', '', true);
    execute 'reset role';
    res := res || jsonb_build_object('id','5.2','ok',
      v_err = 'binder activity: event type not allowed for this actor;binder activity: event type not allowed for this actor'
      and pg_temp.wh_5892_pages(l_p) = n,
      'detail','contexto forjado com tipo estrutural ou origem de acervo → recusa (5381) e a operação inteira é desfeita');
    res := res || jsonb_build_object('id','5.3','ok',
      exists (select 1 from public.binder_activity_event e where e.layout_key = l_f and e.actor_user_id = u_a
              and e.event_type = 'COLLECTION_ATTACHED')
      and exists (select 1 from public.binder_activity_event e where e.layout_key = l_p and e.actor_user_id = u_a
                  and e.event_type = 'BINDER_ASSEMBLED'),
      'detail','eventos estruturais do titular (montagem, associação) continuam gravados');

    -- 6. Revogação ---------------------------------------------------------------------------------------
    select count(*) into n from public.binder_activity_event e where e.actor_user_id = u_b;
    perform pg_temp.wh_5892_as(u_a); perform public.set_collection_member_role(v_cp, m_b, 'VIEWER');
    perform pg_temp.wh_5892_as(u_b);
    v_err := pg_temp.wh_5892_try(format('select * from public.editor_add_binder_page(%L)', v_cp))
          || ';' || pg_temp.wh_5892_try(format('select * from public.editor_set_binder_species_reference_visibility(%L, false)', v_cp));
    perform pg_temp.wh_5892_as(u_a); perform public.set_collection_member_role(v_cp, m_b, 'EDITOR');
    execute 'reset role';
    select count(*) into n2 from public.binder_activity_event e where e.actor_user_id = u_b;
    res := res || jsonb_build_object('id','6.1','ok', v_err = 'COLLECTION_NOT_FOUND;COLLECTION_NOT_FOUND' and n2 = n,
      'detail','EDITOR rebaixado perde páginas e referências na hora; nenhum evento depois');

    -- 7. Titular intocado ---------------------------------------------------------------------------------
    perform pg_temp.wh_5892_as(u_a);
    select x.id into v_u from public.add_layout_page(l_f) x;
    perform public.reorder_layout_pages(l_f, (select array_agg(p2.id order by p2.page_number desc)
                                               from public.collection_layout_page p2 where p2.layout_id = l_f));
    perform public.remove_layout_page(v_u, 0);
    select x.operation into v_txt from public.set_my_binder_species_reference_visibility(v_cp, false) x;
    execute 'reset role';
    res := res || jsonb_build_object('id','7.1','ok', v_txt = 'UPDATED'
      and exists (select 1 from public.binder_activity_event e where e.layout_key = l_f and e.actor_user_id = u_a
                  and e.event_type in ('PAGES_ADDED', 'PAGES_REORDERED', 'PAGE_REMOVED')),
      'detail','titular continua com páginas no fichário de várias coleções e com a exibição das referências (5280/5282/5286/5258)');

    -- 7b. Fichário exclusivo com conteúdo de terceiros (proprietária anterior) ------------------------
    -- O titular aplica referências em CP, posiciona a1, transfere a âncora para CQ (5254) e
    -- desassocia CP (posições ficam, 5253): o fichário passa a ser EXCLUSIVO de CQ, com a
    -- carta e as referências de CP — conteúdo de terceiros para o EDITOR de CQ.
    perform pg_temp.wh_5892_as(u_a);
    perform count(*) from public.add_layout_page(l_p);
    select * into p from public.preview_my_binder_species_references(v_cp);
    perform count(*) from public.apply_my_binder_species_references(v_cp, p.plan_token);
    perform public.place_my_physical_card_in_slot(v_cp, pg_temp.wh_5892_slot(l_p, np + 1, 1, 1), a1);
    select x.collection_id into v_cq from public.create_my_free_collection(gen_random_uuid(), 'CQ 5892', c_p) x;
    perform count(*) from public.transfer_my_binder_ownership(v_cp, v_cq);
    select * into p from public.preview_my_collection_binder_detach(v_cp);
    perform count(*) from public.detach_my_collection_from_binder(v_cp, p.detach_token, false);
    m_bq := (public.invite_collection_member(v_cq, 'wh892b_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    perform pg_temp.wh_5892_as(u_b); perform public.respond_collection_invite(m_bq, true);
    execute 'reset role';
    select count(*)::integer into n from public.collection_layout_slot_species_reference sr where sr.layout_id = l_p and sr.collection_id = v_cp;
    select a.slot_id into v_u from public.collection_layout_slot_assignment a where a.physical_card_id = a1;
    perform pg_temp.wh_5892_as(u_b);
    v_err := pg_temp.wh_5892_try(format('select * from public.editor_remove_binder_page(%L, %s, %s)', v_cq, np + 1, 4))
          || ';' || pg_temp.wh_5892_try(format('select * from public.editor_clear_binder_species_references(%L, %s)', v_cq, n))
          || ';' || pg_temp.wh_5892_try(format('select * from public.editor_set_binder_species_reference_visibility(%L, false)', v_cq))
          || ';' || pg_temp.wh_5892_try(format('select * from public.editor_preview_binder_species_references(%L)', v_cq));
    execute 'reset role';
    res := res || jsonb_build_object('id','7.2','ok',
      (select l.collection_id from public.collection_layout l where l.id = l_p) = v_cq
      and not exists (select 1 from public.collection_layout_guest g where g.layout_id = l_p) and n > 0 and v_u is not null
      and v_err = 'OPERATION_RESERVED_TO_OWNER;OPERATION_RESERVED_TO_OWNER;OPERATION_RESERVED_TO_OWNER;OPERATION_RESERVED_TO_OWNER',
      'detail','fichário exclusivo de CQ com carta e referências da antiga proprietária: remover página, remover/esconder referências e prévia → reservadas ao titular');
    perform pg_temp.wh_5892_as(u_b);
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    v_e1e_np := pg_temp.wh_5892_pages(l_p);  -- E1E
    perform pg_temp.wh_5892_as(u_b);  -- E1E: volta ao mesmo cliente
    perform count(*) from public.editor_reorder_binder_pages(v_cq,
      (select array_agg(g order by g desc) from generate_series(1, v_e1e_np) g));  -- E1E
    perform count(*) from public.editor_add_binder_page(v_cq);
    execute 'reset role';
    res := res || jsonb_build_object('id','7.3','ok',
      (select count(*)::integer from public.collection_layout_slot_species_reference sr where sr.layout_id = l_p and sr.collection_id = v_cp) = n
      and (select a.slot_id from public.collection_layout_slot_assignment a where a.physical_card_id = a1) = v_u
      and exists (select 1 from public.collection_layout_slot_image i join public.collection_layout_slot s on s.id = i.slot_id
                  where s.page_id = v_page_img)
      and (select st.references_visible from public.collection_layout_species_reference_setting st where st.layout_id = l_p),
      'detail','reordenar e adicionar página no mesmo fichário não tocam a carta (mesmo bolso), as referências de CP, a imagem nem a exibição');

    -- 8. Patrimônio ----------------------------------------------------------------------------------------
    res := res || jsonb_build_object('id','8.1','ok',
      (select string_agg(ca.physical_card_id::text || ':' || ca.collection_id::text, ',' order by ca.physical_card_id)
         from public.collection_allocation ca where ca.physical_card_id in (a1, s1, f1)) = alloc0
      and (select string_agg(md5((to_jsonb(pc) - 'updated_at')::text), ',' order by pc.id)
             from public.physical_card pc where pc.id in (a1, s1, f1)) = pc0,
      'detail','nenhuma alocação, local, condição ou outro campo de exemplar mudou');

    -- 9. Coleção arquivada ----------------------------------------------------------------------------------
    perform pg_temp.wh_5892_as(u_a); perform public.archive_collection(v_cs);
    perform pg_temp.wh_5892_as(u_b);
    v_err := pg_temp.wh_5892_try(format('select * from public.editor_add_binder_page(%L)', v_cs))
          || ';' || pg_temp.wh_5892_try(format('select * from public.editor_reorder_binder_pages(%L, %L)', v_cs, array[1]::integer[]));
    execute 'reset role';
    res := res || jsonb_build_object('id','9.1','ok', v_err = 'COLLECTION_ARCHIVED;COLLECTION_ARCHIVED',
      'detail','coleção arquivada: EDITOR recusado só depois de autorizado');

    execute 'reset role';
    raise exception 'MS892' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MS892' then
      res := res || jsonb_build_object('id','X.1','ok', false, 'detail','erro inesperado: '||sqlstate||' '||sqlerrm);
    end if;
  end;

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('mmkyu.binder_activity_ctx', '', true);
  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.collection_membership), (select count(*) from public.collection_layout_page),
               (select count(*) from public.collection_layout_slot), (select count(*) from public.collection_layout_slot_species_reference),
               (select count(*) from public.collection_layout_species_reference_setting),
               (select count(*) from public.binder_activity_event), (select count(*) from public.binder_activity_item)]
    into e_counts;
  res := res || jsonb_build_object('id','99.1','ok', b_counts = e_counts and current_user = session_user,
    'detail','resíduo zero (11 contagens, inclusive páginas, bolsos, referências e histórico) e papel restaurado');

  v_expected := 27;
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
  select '5892', seq, check_id, status, detail from pg_temp.wh_5892_validate();

-- @@T8 harness 5893 [OPEN] sha256=798ceb753c22cc68fb83807d45a94e67c19535b3d1cca5d41c81c101788e471d
create or replace function pg_temp.wh_5893_as(p_user uuid)
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

create or replace function pg_temp.wh_5893_try(p_sql text)
returns text language plpgsql volatile as $try$
begin
  execute p_sql;
  return 'OK';
exception when others then
  return sqlerrm;
end;
$try$;

create or replace function pg_temp.wh_5893_slot(p_layout uuid, p_page integer, p_row integer, p_col integer)
returns uuid language sql stable as $sl$
  select s.id from public.collection_layout_slot s
  join public.collection_layout_page p on p.id = s.page_id
  where p.layout_id = p_layout and p.page_number = p_page and s.row_index = p_row and s.column_index = p_col;
$sl$;

create or replace function pg_temp.wh_5893_at(p_layout uuid, p_card uuid)
returns text language sql stable as $at$
  -- "<página>:<linha>:<coluna>" do exemplar no fichário, ou NULL
  select p.page_number || ':' || s.row_index || ':' || s.column_index
  from public.collection_layout_slot_assignment a
  join public.collection_layout_slot s on s.id = a.slot_id
  join public.collection_layout_page p on p.id = s.page_id
  where p.layout_id = p_layout and a.physical_card_id = p_card;
$at$;

create or replace function pg_temp.wh_5893_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
as $fn$
#variable_conflict use_column
declare
  u_a uuid := gen_random_uuid(); u_b uuid := gen_random_uuid(); u_v uuid := gen_random_uuid();
  u_r uuid := gen_random_uuid(); u_e uuid := gen_random_uuid(); u_c uuid := gen_random_uuid();
  v_sfx text := lower(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  v_game uuid; v_pt uuid; v_rar uuid; v_cat uuid; v_std uuid; v_exp uuid; v_set uuid; v_sm uuid; v_gen text;
  v_old timestamptz := now() - interval '2 days';
  k1 uuid; k1s uuid; k2 uuid; k2s uuid; m1 uuid; m2 uuid; m3 uuid; m4 uuid; v_pos uuid; v_spc uuid;
  v_inv_a uuid; v_ids uuid[]; f1 uuid; f2 uuid; g1 uuid; d1 uuid;
  v_bf uuid; v_bd uuid; v_bm uuid;
  v_cf uuid; v_cg uuid; v_cd uuid; v_cm uuid;
  l_f uuid; l_d uuid; l_m uuid; c_f uuid; c_d uuid;
  m_b uuid; m_bd uuid; m_bm uuid; m_v uuid; m_r uuid; m_e uuid;
  p record; q record; v_err text; v_err2 text; v_txt text; v_s1 text; v_s2 text; n3 integer; v_ep integer; v_er integer; v_ec integer; v_tok text; v_key3 text; v_key4 text; v_j jsonb;
  v_u uuid; n integer; n2 integer;
  alloc0 text; pc0 text;
  b_counts bigint[]; e_counts bigint[];
  res jsonb := '[]'::jsonb; r jsonb; cnt integer := 0; passes integer := 0;
  v_expected integer := 0;
begin
  -- 0. Estrutura ---------------------------------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    (select count(*) from pg_proc q
      where q.oid in (to_regprocedure('public.editor_preview_binder_insert_gap(uuid, integer, integer, integer)'),
                      to_regprocedure('public.editor_insert_binder_gap(uuid, integer, integer, integer, text, boolean, boolean)'),
                      to_regprocedure('public.editor_close_binder_gap(uuid, integer, integer, integer, integer, integer, integer, text, integer)'),
                      to_regprocedure('public.editor_preview_binder_auto_arrange(uuid)'),
                      to_regprocedure('public.editor_apply_binder_auto_arrange(uuid, text)'),
                      to_regprocedure('public.editor_preview_binder_catalog_reconciliation(uuid, text[])'),
                      to_regprocedure('public.editor_apply_binder_catalog_reconciliation(uuid, text[], text, boolean, boolean)'))
        and q.prosecdef and q.proconfig @> array['search_path=""']
        and has_function_privilege('authenticated', q.oid, 'EXECUTE')
        and not has_function_privilege('anon', q.oid, 'EXECUTE')) = 7
    and (select count(*) from pg_proc q
          where q.oid in (to_regprocedure('public.editor_binder_exclusive_read(uuid)'),
                          to_regprocedure('public.binder_editor_any_foreign(uuid, uuid, uuid[])'),
                          to_regprocedure('public.binder_editor_append_page(uuid)'),
                          to_regprocedure('public.binder_editor_catalog_affected(uuid, uuid, text[])'))
            and not has_function_privilege('authenticated', q.oid, 'EXECUTE')) = 4,
    'detail','7 RPCs do EDITOR: definer, search_path vazio, só authenticated; 4 ajudantes internos');
  res := res || jsonb_build_object('id','0.2','ok',
    (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.binder_activity_event_editor_type_guard()')) = '78fa0d34dad161eac1165f3143874260'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)')) = 'f8cfba40e442e85056e7c8ce7954d4f4'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.binder_slot_editor_scope(uuid, uuid, uuid, uuid)')) = '21f1b51a3a0f6c80337c2c593cc6054f',
    'detail','lista de tipos estendida (5384); gravação (5379) e classificação (5378) inalteradas');

  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.collection_membership), (select count(*) from public.collection_layout_page),
               (select count(*) from public.collection_layout_slot), (select count(*) from public.collection_layout_slot_assignment),
               (select count(*) from public.collection_layout_slot_expected_content),
               (select count(*) from public.collection_layout_catalog_incorporation),
               (select count(*) from public.binder_activity_event), (select count(*) from public.binder_activity_item),
               (select count(*) from public.card)]
    into b_counts;

  begin
    -- F. Fixture ---------------------------------------------------------------------------
    select g.id into v_game from public.game g where g.code = 'POKEMON';
    select l.id into v_pt from public.language l where l.code = 'pt-BR';
    select t.id into v_std from public.card_variant_type t where t.game_id = v_game and t.code = 'STANDARD';
    select c.id into v_cat from public.card_category c where c.game_id = v_game and c.code = 'POKEMON';
    select c0.rarity_id into v_rar
    from public.card c0 join public.card_set cs0 on cs0.id = c0.card_set_id
    join public.expansion e0 on e0.id = cs0.expansion_id where e0.game_id = v_game limit 1;
    select g.code, pp.id, pp.species_id into v_gen, v_pos, v_spc
    from public.pokedex dx
    join public.pokedex_position pp on pp.pokedex_id = dx.id
    join public.pokemon_species sp on sp.id = pp.species_id
    join public.pokemon_generation g on g.id = sp.generation_id
    where dx.code = 'NATIONAL' order by pp.position_number limit 1;
    if v_game is null or v_pt is null or v_std is null or v_cat is null or v_rar is null or v_pos is null then
      res := res || jsonb_build_object('id','F.1','ok', false, 'detail','pré-requisitos de catálogo ou Pokédex NATIONAL ausentes');
      raise exception 'MS893' using errcode = 'P0001';
    end if;
    insert into public.expansion (game_id, code, name, release_order)
    values (v_game, 'ED_' || upper(v_sfx), 'ED Harness ' || v_sfx,
            (select coalesce(max(x.release_order), 0) + 1000 from public.expansion x where x.game_id = v_game))
    returning id into v_exp;
    insert into public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_exp, 'ED' || upper(v_sfx), 'ED Set ' || v_sfx, 'REGULAR', 1, 2, 2) returning id into v_set;
    insert into public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_exp, 'EM' || upper(v_sfx), 'EM Set ' || v_sfx, 'REGULAR', 2, 4, 4) returning id into v_sm;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '1', 1, 'ED K1', true) returning id into k1;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '2', 2, 'ED K2', true) returning id into k2;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k1, v_std, 1, true) returning id into k1s;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k2, v_std, 1, true) returning id into k2s;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active, created_at)
    values (v_sm, v_rar, v_cat, '1', 1, 'EM 1', true, v_old) returning id into m1;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active, created_at)
    values (v_sm, v_rar, v_cat, '2', 2, 'EM 2', true, v_old) returning id into m2;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default, created_at)
    values (m1, v_std, 1, true, v_old), (m2, v_std, 1, true, v_old);

    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    select u.id, 'authenticated', 'authenticated', 'wh893' || u.t || '_' || v_sfx || '@example.invalid',
           jsonb_build_object('username', 'wh893' || u.t || '_' || v_sfx, 'display_name', 'WH 5893 ' || upper(u.t)), now(), now()
    from (values (u_a, 'a'), (u_b, 'b'), (u_v, 'v'), (u_r, 'r'), (u_e, 'e'), (u_c, 'c')) u(id, t);
    insert into public.card_primary_species (card_id, pokemon_species_id, resolution_basis, resolved_by_user_id)
    values (k1, v_spc, 'EDITORIAL_RECONCILIATION', u_a);
    select i.id into v_inv_a from public.inventory i where i.owner_user_id = u_a;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, created_at)
    select v.cv, v_pt, v_inv_a, now() - (v.o || ' min')::interval from (values (k2s, 4), (k2s, 3), (k2s, 2), (k1s, 1)) v(cv, o);
    select array_agg(pc.id order by pc.created_at) into v_ids from public.physical_card pc where pc.inventory_id = v_inv_a;
    f1 := v_ids[1]; f2 := v_ids[2]; g1 := v_ids[3]; d1 := v_ids[4];

    perform pg_temp.wh_5893_as(u_a);
    select x.storage_container_id into v_bf from public.create_my_storage_container(gen_random_uuid(), 'BIN F 5893', 'BINDER') x;
    select x.storage_container_id into v_bd from public.create_my_storage_container(gen_random_uuid(), 'BIN D 5893', 'BINDER') x;
    select x.storage_container_id into v_bm from public.create_my_storage_container(gen_random_uuid(), 'BIN M 5893', 'BINDER') x;
    select x.collection_id into v_cf from public.create_my_free_collection(gen_random_uuid(), 'CF 5893', v_bf) x;
    select x.collection_id into v_cd from public.create_my_pokedex_collection(gen_random_uuid(), 'CD 5893', array[v_gen], v_bd) x;
    select x.collection_id into v_cm from public.create_my_card_set_collection(gen_random_uuid(), v_sm, 'CM 5893', v_bm) x;
    perform count(*) from public.set_collection_completion_policy_to_master_set(v_cm, array[v_std]);
    perform public.allocate_physical_cards_to_collection(v_cf, array[f1, f2]);
    perform public.allocate_physical_cards_to_collection(v_cd, array[d1]);
    select * into p from public.preview_my_collection_binder(v_cf, 3, 3, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_cf, 3, 3, 'PRINCIPAL_ONLY', p.plan_token);
    select * into p from public.preview_my_collection_binder(v_cd, 2, 2, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_cd, 2, 2, 'PRINCIPAL_ONLY', p.plan_token);
    select * into p from public.preview_my_collection_binder(v_cm, 3, 3, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_cm, 3, 3, 'PRINCIPAL_ONLY', p.plan_token);
    execute 'reset role';
    select l.id, l.storage_container_id into l_f, c_f from public.collection_layout l where l.collection_id = v_cf;
    select l.id, l.storage_container_id into l_d, c_d from public.collection_layout l where l.collection_id = v_cd;
    select l.id into l_m from public.collection_layout l where l.collection_id = v_cm;
    delete from public.collection_layout_slot_assignment a using public.collection_layout_slot s, public.collection_layout_page p2
     where a.slot_id = s.id and s.page_id = p2.id and p2.layout_id in (l_f, l_d);
    delete from public.collection_layout_slot_expected_content e using public.collection_layout_slot s, public.collection_layout_page p2
     where e.slot_id = s.id and s.page_id = p2.id and p2.layout_id in (l_f, l_d);
    delete from public.collection_layout_slot_species_reference sr where sr.layout_id in (l_f, l_d);
    update public.physical_card pc set storage_container_id = c_f where pc.id in (f1, f2, g1);
    update public.physical_card pc set storage_container_id = c_d where pc.id = d1;
    -- Catálogo de CM: marco recuado e duas cartas novas depois dele (L3).
    update public.collection_layout_catalog_marker mk set marker_at = now() - interval '1 day'
     where mk.layout_id = l_m and mk.collection_id = v_cm;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_sm, v_rar, v_cat, '3', 3, 'EM 3', true) returning id into m3;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_sm, v_rar, v_cat, '4', 4, 'EM 4', true) returning id into m4;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (m3, v_std, 1, true), (m4, v_std, 1, true);
    select nv.item_key into v_key3 from public.binder_catalog_novelties(v_cm) nv where nv.is_novelty and nv.item_key like m3::text || ':%';
    select nv.item_key into v_key4 from public.binder_catalog_novelties(v_cm) nv where nv.is_novelty and nv.item_key like m4::text || ':%';

    perform pg_temp.wh_5893_as(u_a);
    select x.collection_id into v_cg from public.create_my_free_collection(gen_random_uuid(), 'CG 5893', c_f) x;
    perform public.allocate_physical_cards_to_collection(v_cg, array[g1]);
    perform public.attach_my_collection_to_binder(v_cg, l_f);
    perform public.place_my_physical_card_in_slot(v_cf, pg_temp.wh_5893_slot(l_f, 1, 1, 1), f1);
    perform public.place_my_physical_card_in_slot(v_cf, pg_temp.wh_5893_slot(l_f, 1, 1, 2), f2);
    perform public.place_my_physical_card_in_slot(v_cg, pg_temp.wh_5893_slot(l_f, 1, 1, 3), g1);
    select * into p from public.preview_my_binder_species_references(v_cd);
    perform count(*) from public.apply_my_binder_species_references(v_cd, p.plan_token);
    m_b  := (public.invite_collection_member(v_cf, 'wh893b_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_bd := (public.invite_collection_member(v_cd, 'wh893b_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_bm := (public.invite_collection_member(v_cm, 'wh893b_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_v  := (public.invite_collection_member(v_cf, 'wh893v_' || v_sfx) ->> 'membership_id')::uuid;
    m_r  := (public.invite_collection_member(v_cf, 'wh893r_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_e  := (public.invite_collection_member(v_cg, 'wh893e_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    perform pg_temp.wh_5893_as(u_b);
    perform public.respond_collection_invite(m_b, true);
    perform public.respond_collection_invite(m_bd, true);
    perform public.respond_collection_invite(m_bm, true);
    perform pg_temp.wh_5893_as(u_v); perform public.respond_collection_invite(m_v, true);
    perform pg_temp.wh_5893_as(u_r); perform public.respond_collection_invite(m_r, true);
    perform pg_temp.wh_5893_as(u_e); perform public.respond_collection_invite(m_e, true);
    perform pg_temp.wh_5893_as(u_a); perform public.remove_collection_member(v_cf, m_r);
    execute 'reset role';
    select string_agg(ca.physical_card_id::text || ':' || ca.collection_id::text, ',' order by ca.physical_card_id) into alloc0
      from public.collection_allocation ca where ca.physical_card_id in (f1, f2, g1, d1);
    select string_agg(md5((to_jsonb(pc) - 'updated_at')::text), ',' order by pc.id) into pc0
      from public.physical_card pc where pc.id in (f1, f2, g1, d1);
    res := res || jsonb_build_object('id','F.2','ok',
      pg_temp.wh_5893_at(l_f, f1) = '1:1:1' and pg_temp.wh_5893_at(l_f, f2) = '1:1:2' and pg_temp.wh_5893_at(l_f, g1) = '1:1:3'
      and exists (select 1 from public.collection_layout_guest g where g.layout_id = l_f and g.collection_id = v_cg)
      and exists (select 1 from public.collection_layout_slot_species_reference sr where sr.layout_id = l_d and sr.pokedex_position_id = v_pos)
      and v_key3 is not null and v_key4 is not null,
      'detail','fixture: CF com carta de CG na cadeia; CD com referências; CM com duas novidades');

    -- 1. Inserir e fechar espaço ---------------------------------------------------------------
    perform pg_temp.wh_5893_as(u_b);
    v_err := pg_temp.wh_5893_try(format('select * from public.editor_preview_binder_insert_gap(%L, 1, 1, 1)', v_cf));
    perform pg_temp.wh_5893_as(u_e);
    v_err := v_err || ';' || pg_temp.wh_5893_try(format('select * from public.editor_preview_binder_insert_gap(%L, 1, 1, 1)', v_cg));
    execute 'reset role';
    res := res || jsonb_build_object('id','1.1','ok', v_err = 'OPERATION_RESERVED_TO_OWNER;OPERATION_RESERVED_TO_OWNER',
      'detail','fichário com convidada: EDITOR da proprietária e da convidada não inserem espaço');
    perform pg_temp.wh_5893_as(u_a);
    select * into p from public.preview_my_collection_binder_detach(v_cg);
    perform count(*) from public.detach_my_collection_from_binder(v_cg, p.detach_token, false);
    execute 'reset role';
    select e.plan_token into v_tok from public.binder_gap_evaluate(l_f, pg_temp.wh_5893_slot(l_f, 1, 1, 1)) e;
    perform pg_temp.wh_5893_as(u_b);
    v_err := pg_temp.wh_5893_try(format('select * from public.editor_preview_binder_insert_gap(%L, 1, 1, 1)', v_cf))
          || ';' || pg_temp.wh_5893_try(format('select * from public.editor_insert_binder_gap(%L, 1, 1, 1, %L, true, true)', v_cf, v_tok));
    execute 'reset role';
    res := res || jsonb_build_object('id','1.2','ok', v_err = 'OPERATION_RESERVED_TO_OWNER;OPERATION_RESERVED_TO_OWNER'
      and pg_temp.wh_5893_at(l_f, g1) = '1:1:3' and pg_temp.wh_5893_at(l_f, f1) = '1:1:1'
      and not exists (select 1 from public.collection_layout_guest g where g.layout_id = l_f),
      'detail','fichário exclusivo com carta da convidada desassociada na cadeia: prévia e inserção (mesmo com token válido) recusadas; nada anda');
    perform pg_temp.wh_5893_as(u_a); perform public.remove_slot_assignment(array[pg_temp.wh_5893_slot(l_f, 1, 1, 3)]);
    perform pg_temp.wh_5893_as(u_b);
    select * into p from public.editor_preview_binder_insert_gap(v_cf, 1, 1, 1);
    -- plano válido que deixou de representar o estado: o titular reserva o bolso de destino
    perform pg_temp.wh_5893_as(u_a);
    perform public.set_slot_expected_content(pg_temp.wh_5893_slot(l_f, 1, 1, 3), k2, null, null, null);
    perform pg_temp.wh_5893_as(u_b);
    v_err2 := pg_temp.wh_5893_try(format('select * from public.editor_insert_binder_gap(%L, 1, 1, 1, %L)', v_cf, p.plan_token));
    perform pg_temp.wh_5893_as(u_a);
    perform public.clear_slot_expected_content(array[pg_temp.wh_5893_slot(l_f, 1, 1, 3)]);
    perform pg_temp.wh_5893_as(u_b);
    select * into q from public.editor_insert_binder_gap(v_cf, 1, 1, 1, p.plan_token);
    execute 'reset role';
    res := res || jsonb_build_object('id','1.3','ok', p.outcome = 'SAME_PAGE' and p.moved_pockets = 2 and v_err2 = 'GAP_PLAN_CHANGED'
      and q.outcome = 'INSERTED' and q.end_page = 1 and q.end_row = 1 and q.end_column = 3
      and pg_temp.wh_5893_at(l_f, f1) = '1:1:2' and pg_temp.wh_5893_at(l_f, f2) = '1:1:3'
      and exists (select 1 from public.binder_activity_event e where e.layout_key = l_f and e.actor_user_id = u_b
                  and e.event_type = 'GAP_OPENED' and e.collection_id = v_cf and e.source = 'FICHARIO')
      and not exists (select 1 from public.binder_activity_item i join public.binder_activity_event e on e.id = i.event_id
                      where e.layout_key = l_f and e.actor_user_id = u_b and e.event_type = 'GAP_OPENED'
                        and i.collection_id is distinct from v_cf),
      'detail','token de prévia vencido pela mudança do destino → GAP_PLAN_CHANGED; estado de volta: espaço aberto, ordem preservada, GAP_OPENED com itens de CF');
    perform pg_temp.wh_5893_as(u_b);
    select * into p from public.editor_close_binder_gap(v_cf, 1, 1, 1, q.end_page, q.end_row, q.end_column, q.undo_token);
    v_err := pg_temp.wh_5893_try(format('select * from public.editor_close_binder_gap(%L, 1, 1, 1, 1, 1, 3, %L)', v_cf, q.undo_token));
    execute 'reset role';
    res := res || jsonb_build_object('id','1.4','ok', p.outcome = 'CLOSED' and p.moved_pockets = 2
      and pg_temp.wh_5893_at(l_f, f1) = '1:1:1' and pg_temp.wh_5893_at(l_f, f2) = '1:1:2' and v_err = 'GAP_UNDO_EXPIRED'
      and exists (select 1 from public.binder_activity_event e where e.layout_key = l_f and e.actor_user_id = u_b
                  and e.event_type = 'GAP_CLOSED'),
      'detail','fechar com o token de desfazer devolve as cartas; repetir → GAP_UNDO_EXPIRED');
    -- token u1 de OUTRO usuário (o titular abre, o EDITOR fecha): o token só confere o estado.
    perform pg_temp.wh_5893_as(u_a);
    select * into p from public.preview_my_binder_insert_gap(v_cf, pg_temp.wh_5893_slot(l_f, 1, 1, 1));
    select * into q from public.insert_my_binder_gap(v_cf, pg_temp.wh_5893_slot(l_f, 1, 1, 1), p.plan_token, true, true);
    execute 'reset role';
    select pg.page_number, s.row_index, s.column_index into v_ep, v_er, v_ec
      from public.collection_layout_slot s join public.collection_layout_page pg on pg.id = s.page_id where s.id = q.end_slot_id;
    perform pg_temp.wh_5893_as(u_b);
    select * into p from public.editor_close_binder_gap(v_cf, 1, 1, 1, v_ep, v_er, v_ec, q.undo_token);
    execute 'reset role';
    res := res || jsonb_build_object('id','1.5','ok', p.outcome = 'CLOSED'
      and pg_temp.wh_5893_at(l_f, f1) = '1:1:1' and pg_temp.wh_5893_at(l_f, f2) = '1:1:2',
      'detail','espaço aberto pelo titular só sobre cartas de CF: o EDITOR que recebe o token pode fechá-lo (mesmo efeito que mover cartas de CF)');
    insert into public.collection_layout_slot_image (slot_id, owner_user_id, storage_path)
    values (pg_temp.wh_5893_slot(l_f, 1, 1, 3), u_a, u_a::text || '/' || l_f::text || '/' || gen_random_uuid()::text || '.webp');  -- E1E: C1 — caminho canônico (uuid), atende aos CHECKs 5232
    perform pg_temp.wh_5893_as(u_b);
    v_err := pg_temp.wh_5893_try(format('select * from public.editor_preview_binder_insert_gap(%L, 1, 1, 1)', v_cf));
    execute 'reset role';
    res := res || jsonb_build_object('id','1.6','ok', v_err = 'OPERATION_RESERVED_TO_OWNER'
      and exists (select 1 from public.collection_layout_slot_image i where i.slot_id = pg_temp.wh_5893_slot(l_f, 1, 1, 3)),
      'detail','imagem do titular na cadeia → recusa; a imagem não anda');
    perform pg_temp.wh_5893_as(u_a);
    select * into p from public.preview_my_binder_insert_gap(v_cf, pg_temp.wh_5893_slot(l_f, 1, 1, 1));
    select * into q from public.insert_my_binder_gap(v_cf, pg_temp.wh_5893_slot(l_f, 1, 1, 1), p.plan_token, true, true);
    execute 'reset role';
    select pg.page_number, s.row_index, s.column_index into v_ep, v_er, v_ec
      from public.collection_layout_slot s join public.collection_layout_page pg on pg.id = s.page_id where s.id = q.end_slot_id;
    perform pg_temp.wh_5893_as(u_b);
    v_err := pg_temp.wh_5893_try(format('select * from public.editor_close_binder_gap(%L, 1, 1, 1, %s, %s, %s, %L)', v_cf, v_ep, v_er, v_ec, q.undo_token));
    perform pg_temp.wh_5893_as(u_a);
    perform count(*) from public.close_my_binder_gap(v_cf, q.gap_slot_id, q.end_slot_id, q.undo_token, q.added_page_id);
    execute 'reset role';
    res := res || jsonb_build_object('id','1.7','ok', v_err = 'OPERATION_RESERVED_TO_OWNER'
      and pg_temp.wh_5893_at(l_f, f1) = '1:1:1'
      and exists (select 1 from public.collection_layout_slot_image i where i.slot_id = pg_temp.wh_5893_slot(l_f, 1, 1, 3)),
      'detail','espaço do titular que deslocou a imagem dele: o EDITOR não desfaz (trecho com terceiros), mesmo com o token; o titular desfaz');

    -- 2. Organização automática (Pokédex exclusiva) -----------------------------------------------
    perform pg_temp.wh_5893_as(u_b);
    v_j := public.editor_preview_binder_auto_arrange(v_cd);
    v_tok := v_j ->> 'plan_token';
    -- elegibilidade muda entre a prévia e a confirmação: o titular posiciona d1
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    select sr.slot_id into v_u from public.collection_layout_slot_species_reference sr
     where sr.layout_id = l_d and sr.pokedex_position_id = v_pos;
    perform pg_temp.wh_5893_as(u_b);  -- E1E: volta ao mesmo cliente
    perform pg_temp.wh_5893_as(u_a); perform public.place_my_physical_card_in_slot(v_cd, v_u, d1);
    perform pg_temp.wh_5893_as(u_b);
    v_err2 := pg_temp.wh_5893_try(format('select public.editor_apply_binder_auto_arrange(%L, %L)', v_cd, v_tok));
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    select count(*) into n3 from public.binder_activity_event e where e.layout_key = l_d and e.event_type = 'CARDS_AUTO_ARRANGED';
    perform pg_temp.wh_5893_as(u_b);  -- E1E: volta ao mesmo cliente
    perform pg_temp.wh_5893_as(u_a); perform public.remove_slot_assignment(array[v_u]);
    perform pg_temp.wh_5893_as(u_b);
    v_txt := public.editor_apply_binder_auto_arrange(v_cd, v_tok) ->> 'status';
    v_txt := v_txt || ';' || (public.editor_apply_binder_auto_arrange(v_cd, v_tok) ->> 'status');
    v_err := pg_temp.wh_5893_try(format('select public.editor_preview_binder_auto_arrange(%L)', v_cf));
    execute 'reset role';
    res := res || jsonb_build_object('id','2.1','ok', v_j ->> 'status' = 'READY' and (v_j ->> 'insert_count')::integer = 1
      and not (v_j -> 'items' -> 0 ? 'slot_id') and (v_j -> 'items' -> 0 ->> 'physical_card_id')::uuid = d1
      and v_txt = 'APPLIED;ALREADY_APPLIED'
      and exists (select 1 from public.collection_layout_slot_assignment a
                  join public.collection_layout_slot_species_reference sr on sr.slot_id = a.slot_id
                  where a.physical_card_id = d1 and sr.pokedex_position_id = v_pos)
      and v_err = 'AUTO_ARRANGE_UNSUPPORTED_COLLECTION',
      'detail','prévia sem ids de bolso; a representante vai para o bolso da espécie; repetir → ALREADY_APPLIED; coleção livre não organiza');
    res := res || jsonb_build_object('id','2.2','ok',
      exists (select 1 from public.binder_activity_event e where e.layout_key = l_d and e.actor_user_id = u_b
              and e.event_type = 'CARDS_AUTO_ARRANGED' and e.collection_id = v_cd and e.source = 'FICHARIO')
      and not exists (select 1 from public.binder_activity_item i join public.binder_activity_event e on e.id = i.event_id
                      where e.layout_key = l_d and e.actor_user_id = u_b and i.collection_id is distinct from v_cd),
      'detail','evento CARDS_AUTO_ARRANGED com o EDITOR e CD; itens só de CD');
    res := res || jsonb_build_object('id','2.3','ok', v_err2 = 'AUTO_ARRANGE_PLAN_CHANGED' and n3 = 0,
      'detail','exemplar posicionado entre prévia e confirmação → AUTO_ARRANGE_PLAN_CHANGED, nada gravado; com o estado de volta, o mesmo token aplica');

    -- 3. Novidades do Catálogo (Master Set exclusivo) ---------------------------------------------
    select string_agg(md5((to_jsonb(e) - 'updated_at')::text), ',' order by e.slot_id) into v_s1
      from public.collection_layout_slot_expected_content e
      join public.collection_layout_slot s on s.id = e.slot_id join public.collection_layout_page pg on pg.id = s.page_id
     where pg.layout_id = l_m;
    select count(*) into n3 from public.collection_layout_slot_expected_content;
    select md5((to_jsonb(c) - 'updated_at')::text)
           || ':' || coalesce((select string_agg(f.variant_type_id::text, ',' order by f.variant_type_id)
                               from public.collection_master_set_finish f where f.collection_id = v_cm), '-')
      into v_s2 from public.collection c where c.id = v_cm;
    perform pg_temp.wh_5893_as(u_b);
    select pv.plan_token into v_tok from public.editor_preview_binder_catalog_reconciliation(v_cm, array[v_key3]) pv
     where pv.row_kind = 'HEADER';
    select * into p from public.editor_apply_binder_catalog_reconciliation(v_cm, array[v_key3], v_tok);
    execute 'reset role';
    res := res || jsonb_build_object('id','3.1','ok', p.outcome = 'APPLIED' and p.reservations_created = 1
      and exists (select 1 from public.collection_layout_catalog_incorporation ci
                  where ci.layout_id = l_m and ci.collection_id = v_cm and ci.item_key = v_key3)
      and exists (select 1 from public.binder_activity_event e where e.layout_key = l_m and e.actor_user_id = u_b
                  and e.event_type = 'CATALOG_NOVELTIES_INCORPORATED' and e.source = 'CATALOGO' and e.collection_id = v_cm),
      'detail','novidade incorporada pelo EDITOR: reserva criada, registro de incorporação, evento com origem CATALOGO');
    res := res || jsonb_build_object('id','3.3','ok',
      (select string_agg(md5((to_jsonb(e) - 'updated_at')::text), ',' order by e.slot_id)
         from public.collection_layout_slot_expected_content e
         join public.collection_layout_slot s on s.id = e.slot_id join public.collection_layout_page pg on pg.id = s.page_id
        where pg.layout_id = l_m and e.card_id <> m3) = v_s1
      and (select count(*) from public.collection_layout_slot_expected_content) = n3 + 1
      and (select count(*) from public.collection_layout_slot_expected_content e where e.card_id = m3 and e.collection_id is null) = 1
      and (select array_agg(ci.item_key) from public.collection_layout_catalog_incorporation ci where ci.layout_id = l_m) = array[v_key3]
      and (select md5((to_jsonb(c) - 'updated_at')::text)
                  || ':' || coalesce((select string_agg(f.variant_type_id::text, ',' order by f.variant_type_id)
                                      from public.collection_master_set_finish f where f.collection_id = v_cm), '-')
             from public.collection c where c.id = v_cm) = v_s2,
      'detail','efeitos da incorporação: só uma reserva nova (de CM) e um registro; reservas existentes, coleção, Set e acabamentos intactos');
    select * into q from public.binder_catalog_plan(v_cm, array[v_key4]) pl where pl.row_kind = 'ITEM';
    insert into public.collection_layout_slot_image (slot_id, owner_user_id, storage_path)
    values (pg_temp.wh_5893_slot(l_m, q.target_page, q.target_row, q.target_column), u_a, u_a::text || '/' || l_m::text || '/' || gen_random_uuid()::text || '.webp');  -- E1E: C1 — caminho canônico (uuid), atende aos CHECKs 5232
    select pl.plan_token into v_tok from public.binder_catalog_plan(v_cm, array[v_key4]) pl where pl.row_kind = 'HEADER';
    perform pg_temp.wh_5893_as(u_b);
    v_err := pg_temp.wh_5893_try(format('select * from public.editor_preview_binder_catalog_reconciliation(%L, %L)', v_cm, array[v_key4]))
          || ';' || pg_temp.wh_5893_try(format('select * from public.editor_apply_binder_catalog_reconciliation(%L, %L, %L, true, true)',
                                               v_cm, array[v_key4], v_tok))
          || ';' || pg_temp.wh_5893_try(format('select * from public.editor_preview_binder_catalog_reconciliation(%L)', v_cd));
    execute 'reset role';
    res := res || jsonb_build_object('id','3.2','ok',
      v_err ~ '^OPERATION_RESERVED_TO_OWNER;OPERATION_RESERVED_TO_OWNER;(NOT_MASTER_SET|BINDER_NOT_ELIGIBLE)'
      and not exists (select 1 from public.collection_layout_slot_expected_content e
                      join public.collection_layout_slot s on s.id = e.slot_id
                      join public.collection_layout_page pg on pg.id = s.page_id
                      where pg.layout_id = l_m and e.card_id = m4),
      'detail','imagem do titular no bolso natural: prévia e aplicação (com token válido) recusadas, nada criado; Pokédex não incorpora');

    -- 4. Tipos de evento e recusas ------------------------------------------------------------------
    res := res || jsonb_build_object('id','4.1','ok',
      not exists (select 1 from public.binder_activity_event e
                  where e.layout_key in (l_f, l_d, l_m) and e.actor_user_id in (u_b, u_e)
                    and not ((e.event_type in ('CARD_PLACED', 'CARD_MOVED', 'CARDS_SWAPPED', 'CARDS_REMOVED',
                                               'POCKET_RESERVED', 'RESERVATIONS_RELEASED', 'POCKETS_LOCKED', 'POCKETS_UNLOCKED',
                                               'PAGES_ADDED', 'PAGE_REMOVED', 'PAGES_REORDERED',
                                               'GAP_OPENED', 'GAP_CLOSED', 'CARDS_AUTO_ARRANGED') and e.source = 'FICHARIO')
                             or (e.event_type = 'CATALOG_NOVELTIES_INCORPORATED' and e.source = 'CATALOGO'))),
      'detail','todo evento do EDITOR tem par (tipo, origem) da lista fechada');
    perform pg_temp.wh_5893_as(u_b);
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    n := (select count(*) from public.collection_layout_page p2 where p2.layout_id = l_f);
    perform pg_temp.wh_5893_as(u_b);  -- E1E: volta ao mesmo cliente
    perform set_config('mmkyu.binder_activity_ctx', jsonb_build_object('depth', 1, 'layout', l_f, 'type', 'GAP_OPENED',
      'source', 'CATALOGO', 'collection', v_cf, 'summary', '{}'::jsonb, 'event_id', null, 'n', 0, 'cap', 0)::text, true);
    v_err := pg_temp.wh_5893_try(format('select * from public.editor_add_binder_page(%L)', v_cf));
    perform set_config('mmkyu.binder_activity_ctx', jsonb_build_object('depth', 1, 'layout', l_f, 'type', 'CATALOG_NOVELTIES_INCORPORATED',
      'source', 'FICHARIO', 'collection', v_cf, 'summary', '{}'::jsonb, 'event_id', null, 'n', 0, 'cap', 0)::text, true);
    v_err := v_err || ';' || pg_temp.wh_5893_try(format('select * from public.editor_add_binder_page(%L)', v_cf));
    perform set_config('mmkyu.binder_activity_ctx', '', true);
    execute 'reset role';
    res := res || jsonb_build_object('id','4.2','ok',
      v_err = 'binder activity: event type not allowed for this actor;binder activity: event type not allowed for this actor'
      and (select count(*) from public.collection_layout_page p2 where p2.layout_id = l_f) = n,
      'detail','tipo novo com origem trocada (forjado) → recusa; a operação inteira é desfeita');
    v_err := '';
    foreach v_u in array array[u_v, u_c, u_r, u_a] loop
      perform pg_temp.wh_5893_as(v_u);
      v_err := v_err || pg_temp.wh_5893_try(format('select * from public.editor_preview_binder_insert_gap(%L, 1, 1, 1)', v_cf)) || ';';
    end loop;
    perform pg_temp.wh_5893_as(null);
    v_err := v_err || pg_temp.wh_5893_try(format('select public.editor_apply_binder_auto_arrange(%L, %L)', v_cd, 'aa1:' || repeat('0', 64)));
    execute 'reset role';
    res := res || jsonb_build_object('id','4.3','ok',
      v_err ~ ('^' || repeat('COLLECTION_NOT_FOUND;', 4) || 'permission denied'),
      'detail','VIEWER, estranho, ex-membro e titular pelo caminho do EDITOR → COLLECTION_NOT_FOUND; anon sem EXECUTE');
    select count(*) into n from public.binder_activity_event e where e.actor_user_id = u_b;
    perform pg_temp.wh_5893_as(u_a); perform public.set_collection_member_role(v_cf, m_b, 'VIEWER');
    perform pg_temp.wh_5893_as(u_b);
    v_err := pg_temp.wh_5893_try(format('select * from public.editor_close_binder_gap(%L, 1, 1, 1, 1, 1, 3, %L)', v_cf, 'u1:' || repeat('0', 64)));
    perform pg_temp.wh_5893_as(u_a); perform public.set_collection_member_role(v_cf, m_b, 'EDITOR');
    execute 'reset role';
    select count(*) into n2 from public.binder_activity_event e where e.actor_user_id = u_b;
    res := res || jsonb_build_object('id','4.4','ok', v_err = 'COLLECTION_NOT_FOUND' and n2 = n,
      'detail','EDITOR rebaixado perde as operações em massa na hora; nenhum evento depois');

    -- 5. Titular intocado ----------------------------------------------------------------------------
    perform pg_temp.wh_5893_as(u_a);
    select * into p from public.preview_my_binder_insert_gap(v_cf, pg_temp.wh_5893_slot(l_f, 1, 1, 1));
    select * into q from public.insert_my_binder_gap(v_cf, pg_temp.wh_5893_slot(l_f, 1, 1, 1), p.plan_token, true, true);
    perform count(*) from public.close_my_binder_gap(v_cf, q.gap_slot_id, q.end_slot_id, q.undo_token, q.added_page_id);
    execute 'reset role';
    res := res || jsonb_build_object('id','5.1','ok', q.outcome = 'INSERTED'
      and pg_temp.wh_5893_at(l_f, f1) = '1:1:1' and pg_temp.wh_5893_at(l_f, f2) = '1:1:2'
      and exists (select 1 from public.binder_activity_event e where e.layout_key = l_f and e.actor_user_id = u_a
                  and e.event_type = 'GAP_OPENED'),
      'detail','titular continua inserindo espaço sobre a imagem dele e fechando (5283/5284); evento do titular gravado');

    -- 6. Patrimônio -----------------------------------------------------------------------------------
    res := res || jsonb_build_object('id','6.1','ok',
      (select string_agg(ca.physical_card_id::text || ':' || ca.collection_id::text, ',' order by ca.physical_card_id)
         from public.collection_allocation ca where ca.physical_card_id in (f1, f2, g1, d1)) = alloc0
      and (select string_agg(md5((to_jsonb(pc) - 'updated_at')::text), ',' order by pc.id)
             from public.physical_card pc where pc.id in (f1, f2, g1, d1)) = pc0,
      'detail','nenhuma alocação, local, condição ou outro campo de exemplar mudou');

    -- 7. Coleção arquivada -----------------------------------------------------------------------------
    perform pg_temp.wh_5893_as(u_a); perform public.archive_collection(v_cd);
    perform pg_temp.wh_5893_as(u_b);
    v_err := pg_temp.wh_5893_try(format('select public.editor_preview_binder_auto_arrange(%L)', v_cd))
          || ';' || pg_temp.wh_5893_try(format('select public.editor_apply_binder_auto_arrange(%L, %L)', v_cd, 'aa1:' || repeat('0', 64)));
    execute 'reset role';
    res := res || jsonb_build_object('id','7.1','ok', v_err = 'COLLECTION_ARCHIVED;COLLECTION_ARCHIVED',
      'detail','coleção arquivada: EDITOR recusado só depois de autorizado');

    execute 'reset role';
    raise exception 'MS893' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MS893' then
      res := res || jsonb_build_object('id','X.1','ok', false, 'detail','erro inesperado: '||sqlstate||' '||sqlerrm);
    end if;
  end;

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('mmkyu.binder_activity_ctx', '', true);
  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.collection_membership), (select count(*) from public.collection_layout_page),
               (select count(*) from public.collection_layout_slot), (select count(*) from public.collection_layout_slot_assignment),
               (select count(*) from public.collection_layout_slot_expected_content),
               (select count(*) from public.collection_layout_catalog_incorporation),
               (select count(*) from public.binder_activity_event), (select count(*) from public.binder_activity_item),
               (select count(*) from public.card)]
    into e_counts;
  res := res || jsonb_build_object('id','99.1','ok', b_counts = e_counts and current_user = session_user,
    'detail','resíduo zero (13 contagens, inclusive posições, reservas, incorporações e histórico) e papel restaurado');

  v_expected := 24;
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
  select '5893', seq, check_id, status, detail from pg_temp.wh_5893_validate();

-- @@T8 harness 5894 [OPEN] sha256=31c76996533d7b3edcdd48be2e4c5ab02b0dc50ff57f53974769f2acda381b7c
create or replace function pg_temp.wh_5894_as(p_user uuid)
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

create or replace function pg_temp.wh_5894_try(p_sql text)
returns text language plpgsql volatile as $try$
begin
  execute p_sql;
  return 'OK';
exception when others then
  return sqlerrm;
end;
$try$;

-- Assinatura comparável da grade Master Set (colunas comuns às leituras do titular e do participante).
create or replace function pg_temp.wh_5894_ms(p_coll uuid, p_filter text, p_shared boolean)
returns text language plpgsql volatile as $ms$
declare v text;
begin
  if p_shared then
    select coalesce(string_agg(concat_ws('|', x.card_id, x.variant_type_id, x.is_secret, x.image_path,
                                         x.is_satisfied, x.copies_in_collection, x.total_count), ',' order by x.card_id, x.variant_type_id), '<vazio>')
      into v from public.get_shared_master_set_positions(p_coll, p_filter, 500, 0) x;
  else
    select coalesce(string_agg(concat_ws('|', x.card_id, x.variant_type_id, x.is_secret, x.image_path,
                                         x.is_satisfied, x.copies_in_collection, x.total_count), ',' order by x.card_id, x.variant_type_id), '<vazio>')
      into v from public.get_my_master_set_positions(p_coll, p_filter, 500, 0) x;
  end if;
  return v;
end;
$ms$;

-- Assinatura comparável da grade Pokédex (colunas comuns).
create or replace function pg_temp.wh_5894_pd(p_coll uuid, p_filter text, p_gen text, p_shared boolean)
returns text language plpgsql volatile as $pd$
declare v text;
begin
  if p_shared then
    select coalesce(string_agg(concat_ws('|', x.pokedex_position_id, x.position_number, x.species_id, x.generation_code,
                                         x.species_artwork_path, x.is_satisfied, x.copies_in_collection,
                                         x.representative_card_name, x.representative_collector_number,
                                         x.representative_set_code, x.representative_image_path, x.total_count),
                               ',' order by x.position_number, x.pokedex_position_id), '<vazio>')
      into v from public.get_shared_pokedex_positions(p_coll, p_filter, p_gen, 500, 0) x;
  else
    select coalesce(string_agg(concat_ws('|', x.pokedex_position_id, x.position_number, x.species_id, x.generation_code,
                                         x.species_artwork_path, x.is_satisfied, x.copies_in_collection,
                                         x.representative_card_name, x.representative_collector_number,
                                         x.representative_set_code, x.representative_image_path, x.total_count),
                               ',' order by x.position_number, x.pokedex_position_id), '<vazio>')
      into v from public.get_my_pokedex_positions(p_coll, p_filter, p_gen, 500, 0) x;
  end if;
  return v;
end;
$pd$;

-- Histórico compartilhado inteiro (todas as páginas de 50) como texto: ids na ordem + JSON das linhas.
create or replace function pg_temp.wh_5894_hist(p_coll uuid)
returns text language plpgsql volatile as $hi$
declare v text;
begin
  select coalesce(string_agg(to_jsonb(x)::text, E'\n' order by x.occurred_at desc, x.event_id desc), '<vazio>')
    into v from public.get_shared_binder_activity(p_coll, null, null, null, 50) x;
  return v;
end;
$hi$;

create or replace function pg_temp.wh_5894_ids(p_coll uuid, p_categories text[] default null)
returns bigint[] language sql volatile as $ids$
  select coalesce(array_agg(x.event_id order by x.occurred_at desc, x.event_id desc), '{}')
  from public.get_shared_binder_activity(p_coll, p_categories, null, null, 50) x;
$ids$;

create or replace function pg_temp.wh_5894_ev(p_owner uuid, p_layout uuid, p_min integer, p_actor uuid, p_type text,
                                              p_source text, p_coll uuid, p_recorded boolean, p_summary jsonb default '{}'::jsonb)
returns bigint language sql volatile as $ev$
  insert into public.binder_activity_event
    (owner_user_id, layout_key, occurred_at, actor_user_id, event_type, source, collection_id, collection_name,
     binder_name, summary, item_collection_recorded)
  values (p_owner, p_layout, now() - (p_min || ' min')::interval, p_actor, p_type, p_source, p_coll,
          case when p_coll is null then null else 'NOME GRAVADO ' || p_type end, 'FICHARIO GRAVADO',
          p_summary, p_recorded)
  returning id;
$ev$;

create or replace function pg_temp.wh_5894_it(p_event bigint, p_ord integer, p_kind text, p_effect text, p_card uuid,
                                              p_name text, p_coll uuid, p_detail jsonb default null,
                                              p_page integer default null, p_row integer default null, p_col integer default null)
returns void language sql volatile as $it$
  insert into public.binder_activity_item
    (event_id, ordinal, item_kind, effect, card_id, card_name, collector_number, card_set_code,
     to_page, to_row, to_col, detail, collection_id)
  values (p_event, p_ord, p_kind, p_effect, p_card, p_name, case when p_card is null then null else '1' end,
          case when p_card is null then null else 'WHSET' end, p_page, p_row, p_col, p_detail, p_coll);
$it$;

create or replace function pg_temp.wh_5894_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
as $fn$
#variable_conflict use_column
declare
  u_a uuid := gen_random_uuid(); u_b uuid := gen_random_uuid(); u_v uuid := gen_random_uuid();
  u_r uuid := gen_random_uuid(); u_p uuid := gen_random_uuid(); u_e uuid := gen_random_uuid();
  u_c uuid := gen_random_uuid();
  v_sfx text := lower(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  v_game uuid; v_pt uuid; v_rar uuid; v_cat uuid; v_std uuid; v_exp uuid; v_set uuid; v_sm uuid; v_gen text;
  k1 uuid; k1s uuid; k2 uuid; k2s uuid; m1 uuid; m1s uuid; m2 uuid; v_pos uuid; v_spc uuid;
  v_inv_a uuid; v_ids uuid[]; f1 uuid; g1 uuid; ma1 uuid; ma2 uuid; d1 uuid; d2 uuid;
  v_bf uuid; v_bm uuid; v_bd uuid; v_bx uuid;
  v_cf uuid; v_cg uuid; v_cm uuid; v_cd uuid; v_x2 uuid;
  l_f uuid; l_m uuid; c_f uuid;
  m_b uuid; m_bm uuid; m_bd uuid; m_v uuid; m_vm uuid; m_vd uuid; m_r uuid; m_p uuid; m_e uuid;
  h1 bigint; h2 bigint; h3 bigint; h4 bigint; h5 bigint; h6 bigint; h7 bigint; h8 bigint; h9 bigint;
  h10 bigint; h12 bigint; h13 bigint; h14 bigint; h15 bigint; h16 bigint; h17 bigint; h18 bigint; h19 bigint; h20 bigint; h21 bigint; l1 bigint; l2 bigint; l3 bigint; l4 bigint;
  p record; q record; v_err text; v_txt text; v_txt2 text; v_s1 text; v_s2 text; v_s3 text; v_o1 text; v_o2 text;
  v_a bigint[]; v_b bigint[]; v_j jsonb; v_ok boolean; n integer; n2 integer; v_cnt_owner integer;
  pc0 text; alloc0 text;
  b_counts bigint[]; e_counts bigint[];
  res jsonb := '[]'::jsonb; r jsonb; cnt integer := 0; passes integer := 0;
  v_expected integer := 0;
begin
  -- 0. Estrutura ---------------------------------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    (select count(*) from pg_proc q
      where q.oid in (to_regprocedure('public.get_shared_master_set_positions(uuid, text, integer, integer)'),
                      to_regprocedure('public.get_shared_pokedex_positions(uuid, text, text, integer, integer)'),
                      to_regprocedure('public.get_shared_binder_activity(uuid, text[], timestamptz, bigint, integer)'),
                      to_regprocedure('public.get_shared_binder_activity_status(uuid)'))
        and q.prosecdef and q.proconfig = array['search_path=""'] and q.provolatile = 's'
        and has_function_privilege('authenticated', q.oid, 'EXECUTE')
        and not has_function_privilege('anon', q.oid, 'EXECUTE')
        and pg_get_function_result(q.oid) !~* '(copies_available|copies_elsewhere|acervo_state|summary|detail|collection_name|binder_name|actor_user_id|owner_user_id|layout_key|physical_card|storage|condition|email|username)') = 4,
    'detail','4 leituras novas: definer, search_path vazio, STABLE, só authenticated; nenhuma coluna de acervo, resumo, detalhe, nome gravado ou id interno no retorno');
  res := res || jsonb_build_object('id','0.2','ok',
    (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.collection_share_role(uuid)')) = 'efdb495b5b703e9f093eb0f49a1d0a5d'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.get_my_master_set_positions(uuid, text, integer, integer)')) = '8b85264a6c7224a6fde9c9bffb723335'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.get_my_pokedex_positions(uuid, text, text, integer, integer)')) = '79d2cd331031b5c98c64f2c43ecb077f'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.get_my_binder_activity(uuid, text[], timestamptz, bigint, integer)')) = 'fab40eb28280d7c62ca207642b35ff65'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)')) = 'f8cfba40e442e85056e7c8ce7954d4f4',
    'detail','5302, leituras do titular (5198, 5204, 5269) e gravação do histórico (5379) inalteradas');

  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.collection_membership), (select count(*) from public.collection_layout_page),
               (select count(*) from public.collection_layout_slot_assignment),
               (select count(*) from public.collection_layout_catalog_incorporation),
               (select count(*) from public.collection_pokedex_position_assignment),
               (select count(*) from public.binder_activity_event), (select count(*) from public.binder_activity_item),
               (select count(*) from public.card)]
    into b_counts;

  begin
    -- F. Fixture ---------------------------------------------------------------------------
    select g.id into v_game from public.game g where g.code = 'POKEMON';
    select l.id into v_pt from public.language l where l.code = 'pt-BR';
    select t.id into v_std from public.card_variant_type t where t.game_id = v_game and t.code = 'STANDARD';
    select c.id into v_cat from public.card_category c where c.game_id = v_game and c.code = 'POKEMON';
    select c0.rarity_id into v_rar
    from public.card c0 join public.card_set cs0 on cs0.id = c0.card_set_id
    join public.expansion e0 on e0.id = cs0.expansion_id where e0.game_id = v_game limit 1;
    select g.code, pp.id, pp.species_id into v_gen, v_pos, v_spc
    from public.pokedex dx
    join public.pokedex_position pp on pp.pokedex_id = dx.id
    join public.pokemon_species sp on sp.id = pp.species_id
    join public.pokemon_generation g on g.id = sp.generation_id
    where dx.code = 'NATIONAL' order by pp.position_number limit 1;
    if v_game is null or v_pt is null or v_std is null or v_cat is null or v_rar is null or v_pos is null then
      res := res || jsonb_build_object('id','F.1','ok', false, 'detail','pré-requisitos de catálogo ou Pokédex NATIONAL ausentes');
      raise exception 'MS894' using errcode = 'P0001';
    end if;
    insert into public.expansion (game_id, code, name, release_order)
    values (v_game, 'SR_' || upper(v_sfx), 'SR Harness ' || v_sfx,
            (select coalesce(max(x.release_order), 0) + 1000 from public.expansion x where x.game_id = v_game))
    returning id into v_exp;
    insert into public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_exp, 'SR' || upper(v_sfx), 'SR Set ' || v_sfx, 'REGULAR', 1, 2, 2) returning id into v_set;
    insert into public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_exp, 'SM' || upper(v_sfx), 'SM Set ' || v_sfx, 'REGULAR', 2, 2, 2) returning id into v_sm;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '1', 1, 'SR K1', true) returning id into k1;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '2', 2, 'SR K2 SEGREDO DE CG', true) returning id into k2;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_sm, v_rar, v_cat, '1', 1, 'SM 1', true) returning id into m1;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_sm, v_rar, v_cat, '2', 2, 'SM 2', true) returning id into m2;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k1, v_std, 1, true) returning id into k1s;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k2, v_std, 1, true) returning id into k2s;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (m1, v_std, 1, true) returning id into m1s;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (m2, v_std, 1, true);

    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    select u.id, 'authenticated', 'authenticated', 'wh894' || u.t || '_' || v_sfx || '@example.invalid',
           jsonb_build_object('username', 'wh894' || u.t || '_' || v_sfx, 'display_name', 'WH 5894 ' || upper(u.t)), now(), now()
    from (values (u_a, 'a'), (u_b, 'b'), (u_v, 'v'), (u_r, 'r'), (u_p, 'p'), (u_e, 'e'), (u_c, 'c')) u(id, t);
    insert into public.card_primary_species (card_id, pokemon_species_id, resolution_basis, resolved_by_user_id)
    values (k1, v_spc, 'EDITORIAL_RECONCILIATION', u_a);
    select i.id into v_inv_a from public.inventory i where i.owner_user_id = u_a;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, created_at)
    select v.cv, v_pt, v_inv_a, now() - (v.o || ' min')::interval
    from (values (k1s, 6), (k2s, 5), (m1s, 4), (m1s, 3), (k1s, 2), (k1s, 1)) v(cv, o);
    select array_agg(pc.id order by pc.created_at) into v_ids from public.physical_card pc where pc.inventory_id = v_inv_a;
    f1 := v_ids[1]; g1 := v_ids[2]; ma1 := v_ids[3]; ma2 := v_ids[4]; d1 := v_ids[5]; d2 := v_ids[6];

    perform pg_temp.wh_5894_as(u_a);
    select x.storage_container_id into v_bf from public.create_my_storage_container(gen_random_uuid(), 'BIN F 5894', 'BINDER') x;
    select x.storage_container_id into v_bm from public.create_my_storage_container(gen_random_uuid(), 'BIN M 5894', 'BINDER') x;
    select x.storage_container_id into v_bd from public.create_my_storage_container(gen_random_uuid(), 'BIN D 5894', 'BINDER') x;
    select x.collection_id into v_cf from public.create_my_free_collection(gen_random_uuid(), 'CF 5894', v_bf) x;
    select x.collection_id into v_cm from public.create_my_card_set_collection(gen_random_uuid(), v_sm, 'CM 5894', v_bm) x;
    select x.collection_id into v_cd from public.create_my_pokedex_collection(gen_random_uuid(), 'CD 5894', array[v_gen], v_bd) x;
    perform count(*) from public.set_collection_completion_policy_to_master_set(v_cm, array[v_std]);
    perform public.allocate_physical_cards_to_collection(v_cf, array[f1]);
    perform public.allocate_physical_cards_to_collection(v_cm, array[ma1]);
    -- Fichários montados como na 5893; a montagem (E01) é oculta aos membros e os bolsos são
    -- esvaziados em seguida (o histórico desta prova é o gravado abaixo).
    select * into p from public.preview_my_collection_binder(v_cf, 3, 3, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_cf, 3, 3, 'PRINCIPAL_ONLY', p.plan_token);
    select * into p from public.preview_my_collection_binder(v_cm, 3, 3, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_cm, 3, 3, 'PRINCIPAL_ONLY', p.plan_token);
    execute 'reset role';
    select l.id, l.storage_container_id into l_f, c_f from public.collection_layout l where l.collection_id = v_cf;
    select l.id into l_m from public.collection_layout l where l.collection_id = v_cm;
    delete from public.collection_layout_slot_assignment a using public.collection_layout_slot s, public.collection_layout_page p2
     where a.slot_id = s.id and s.page_id = p2.id and p2.layout_id in (l_f, l_m);
    perform pg_temp.wh_5894_as(u_a);
    select x.collection_id into v_cg from public.create_my_free_collection(gen_random_uuid(), 'CG 5894 SEGREDO', c_f) x;
    perform public.attach_my_collection_to_binder(v_cg, l_f);
    perform public.allocate_physical_cards_to_collection(v_cg, array[g1]);
    perform public.allocate_physical_cards_to_collection(v_cd, array[d1]);
    if not exists (select 1 from public.collection_pokedex_position_assignment a
                   join public.collection_allocation ca on ca.id = a.collection_allocation_id
                   where ca.physical_card_id = d1) then
      perform count(*) from public.set_pokedex_position_assignment(d1, v_pos, false);
    end if;
    m_b  := (public.invite_collection_member(v_cf, 'wh894b_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_bm := (public.invite_collection_member(v_cm, 'wh894b_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_bd := (public.invite_collection_member(v_cd, 'wh894b_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_v  := (public.invite_collection_member(v_cf, 'wh894v_' || v_sfx) ->> 'membership_id')::uuid;
    m_vm := (public.invite_collection_member(v_cm, 'wh894v_' || v_sfx) ->> 'membership_id')::uuid;
    m_vd := (public.invite_collection_member(v_cd, 'wh894v_' || v_sfx) ->> 'membership_id')::uuid;
    m_r  := (public.invite_collection_member(v_cf, 'wh894r_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_p  := (public.invite_collection_member(v_cf, 'wh894p_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_e  := (public.invite_collection_member(v_cg, 'wh894e_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    perform pg_temp.wh_5894_as(u_b);
    perform public.respond_collection_invite(m_b, true);
    perform public.respond_collection_invite(m_bm, true);
    perform public.respond_collection_invite(m_bd, true);
    perform pg_temp.wh_5894_as(u_v);
    perform public.respond_collection_invite(m_v, true);
    perform public.respond_collection_invite(m_vm, true);
    perform public.respond_collection_invite(m_vd, true);
    perform pg_temp.wh_5894_as(u_r); perform public.respond_collection_invite(m_r, true);
    perform pg_temp.wh_5894_as(u_e); perform public.respond_collection_invite(m_e, true);
    perform pg_temp.wh_5894_as(u_a); perform public.remove_collection_member(v_cf, m_r);
    perform pg_temp.wh_5894_as(u_c);
    select x.storage_container_id into v_bx from public.create_my_storage_container(gen_random_uuid(), 'BIN X 5894', 'BINDER') x;
    select x.collection_id into v_x2 from public.create_my_free_collection(gen_random_uuid(), 'X2 5894', v_bx) x;
    execute 'reset role';

    -- Histórico (gravação direta, forma da 5379; minutos atrás definem a ordem).
    h1  := pg_temp.wh_5894_ev(u_a, l_f, 100, u_a, 'CARD_PLACED', 'FICHARIO', v_cf, true, '{"cards":1}');
    perform pg_temp.wh_5894_it(h1, 1, 'CARD', 'PLACED', k1, 'SR K1', v_cf,
      jsonb_build_object('physical_card_id', f1, 'condition_code', 'NM', 'storage_container_id', c_f), 1, 1, 1);
    h2  := pg_temp.wh_5894_ev(u_a, l_f, 90, u_a, 'CARDS_AUTO_ARRANGED', 'FICHARIO', v_cf, true,
      jsonb_build_object('moved', 3, 'collections', 2, 'other_collection', v_cg));
    perform pg_temp.wh_5894_it(h2, 1, 'CARD', 'MOVED', k2, 'SR K2 SEGREDO DE CG', v_cg, jsonb_build_object('physical_card_id', g1), 1, 2, 1);
    perform pg_temp.wh_5894_it(h2, 2, 'CARD', 'MOVED', k1, 'SR K1', v_cf, jsonb_build_object('physical_card_id', f1), 1, 1, 2);
    perform pg_temp.wh_5894_it(h2, 3, 'PAGE', 'PAGE_ADDED', null, null, null, null, 2);
    perform pg_temp.wh_5894_it(h2, 4, 'CARD', 'MOVED', k2, 'SR K2 SEGREDO DE CG', v_cg, null, 1, 3, 1);
    h3  := pg_temp.wh_5894_ev(u_a, l_f, 85, u_a, 'CARDS_AUTO_ARRANGED', 'FICHARIO', v_cf, true);
    perform pg_temp.wh_5894_it(h3, 1, 'CARD', 'MOVED', k2, 'SR K2 SEGREDO DE CG', v_cg, null, 1, 2, 2);
    h4  := pg_temp.wh_5894_ev(u_a, l_f, 80, u_a, 'CARD_MOVED', 'FICHARIO', v_cg, true);
    perform pg_temp.wh_5894_it(h4, 1, 'CARD', 'MOVED', k2, 'SR K2 SEGREDO DE CG', v_cg, null, 1, 1, 3);
    h5  := pg_temp.wh_5894_ev(u_a, l_f, 75, u_a, 'CARD_LEFT_BY_INVENTORY_EXIT', 'ACERVO', v_cf, true);
    perform pg_temp.wh_5894_it(h5, 1, 'CARD', 'LEFT', k1, 'SR K1', v_cf);
    h6  := pg_temp.wh_5894_ev(u_a, l_f, 70, u_a, 'COLLECTION_ATTACHED', 'FICHARIO', v_cf, true);
    perform pg_temp.wh_5894_it(h6, 1, 'COLLECTION', 'ATTACHED', null, null, null);
    h7  := pg_temp.wh_5894_ev(u_a, l_f, 65, u_a, 'CARD_PLACED', 'FICHARIO', v_cf, false);
    perform pg_temp.wh_5894_it(h7, 1, 'CARD', 'PLACED', k1, 'SR K1', null, null, 1, 1, 1);
    h8  := pg_temp.wh_5894_ev(u_a, l_f, 60, u_a, 'PAGES_ADDED', 'FICHARIO', v_cf, true);
    perform pg_temp.wh_5894_it(h8, 1, 'PAGE', 'PAGE_ADDED', null, null, null, null, 2);
    h9  := pg_temp.wh_5894_ev(u_a, l_f, 50, u_b, 'CARD_PLACED', 'FICHARIO', v_cf, true);
    perform pg_temp.wh_5894_it(h9, 1, 'CARD', 'PLACED', k1, 'SR K1', v_cf, null, 1, 2, 2);
    h10 := pg_temp.wh_5894_ev(u_a, gen_random_uuid(), 45, u_a, 'CARD_PLACED', 'FICHARIO', v_cf, true);
    perform pg_temp.wh_5894_it(h10, 1, 'CARD', 'PLACED', k1, 'SR K1', v_cf, null, 1, 1, 1);
    h12 := pg_temp.wh_5894_ev(u_a, l_f, 40, u_a, 'CATALOG_NOVELTIES_INCORPORATED', 'FICHARIO', v_cf, true);
    perform pg_temp.wh_5894_it(h12, 1, 'RESERVATION', 'INCORPORATED', k1, 'SR K1', v_cf, null, 1, 3, 3);
    h13 := pg_temp.wh_5894_ev(u_c, l_f, 35, u_c, 'CARD_PLACED', 'FICHARIO', v_cf, true);
    perform pg_temp.wh_5894_it(h13, 1, 'CARD', 'PLACED', k1, 'SR K1', v_cf, null, 1, 1, 1);
    insert into public.collection_layout_catalog_incorporation (layout_id, collection_id, item_key)
    values (l_m, v_cm, m1::text || ':*');
    l1 := pg_temp.wh_5894_ev(u_a, l_m, 30, null, 'LEGACY_CATALOG_INCORPORATION', 'LEGADO', v_cm, false,
      jsonb_build_object('item_key', m1::text || ':*'));
    perform pg_temp.wh_5894_it(l1, 1, 'CARD', 'INCORPORATED', m1, 'SM 1', null);
    l2 := pg_temp.wh_5894_ev(u_a, l_m, 25, null, 'LEGACY_CATALOG_INCORPORATION', 'LEGADO', v_cm, false,
      jsonb_build_object('item_key', m2::text || ':*'));
    perform pg_temp.wh_5894_it(l2, 1, 'CARD', 'INCORPORATED', m2, 'SM 2', null);
    h14 := pg_temp.wh_5894_ev(u_a, l_f, 33, u_a, 'CARD_MOVED', 'FICHARIO', null, true);
    perform pg_temp.wh_5894_it(h14, 1, 'CARD', 'MOVED', k1, 'SR K1', v_cf, null, 1, 3, 3);
    h17 := pg_temp.wh_5894_ev(u_a, l_f, 31, u_a, 'CARD_MOVED', 'FICHARIO', null, true);
    perform pg_temp.wh_5894_it(h17, 1, 'CARD', 'MOVED', k2, 'SR K2 SEGREDO DE CG', v_cg, null, 2, 1, 1);
    h18 := pg_temp.wh_5894_ev(u_a, l_f, 29, u_a, 'CARDS_REMOVED', 'FICHARIO', null, true, '{"cards":2}');
    perform pg_temp.wh_5894_it(h18, 1, 'CARD', 'REMOVED', k2, 'SR K2 SEGREDO DE CG', v_cg, jsonb_build_object('physical_card_id', g1));
    perform pg_temp.wh_5894_it(h18, 2, 'CARD', 'REMOVED', k1, 'SR K1', v_cf, jsonb_build_object('physical_card_id', f1));
    h19 := pg_temp.wh_5894_ev(u_a, l_f, 28, u_a, 'PAGES_ADDED', 'FICHARIO', null, true);
    perform pg_temp.wh_5894_it(h19, 1, 'PAGE', 'PAGE_ADDED', null, null, null, null, 3);
    h20 := pg_temp.wh_5894_ev(u_a, l_f, 27, null, 'CARD_MOVED', 'FICHARIO', null, true);
    perform pg_temp.wh_5894_it(h20, 1, 'CARD', 'MOVED', k1, 'SR K1', v_cf, null, 1, 2, 3);
    h21 := pg_temp.wh_5894_ev(u_c, l_f, 34, u_c, 'CARD_MOVED', 'FICHARIO', null, true);
    perform pg_temp.wh_5894_it(h21, 1, 'CARD', 'MOVED', k1, 'SR K1', v_cf, null, 1, 1, 2);
    h16 := pg_temp.wh_5894_ev(u_a, l_m, 26, u_a, 'CARD_MOVED', 'FICHARIO', null, false);
    perform pg_temp.wh_5894_it(h16, 1, 'CARD', 'MOVED', m1, 'SM 1', null, null, 1, 1, 2);
    h15 := pg_temp.wh_5894_ev(u_a, l_f, 32, u_a, 'COLLECTION_ATTACHED', 'FICHARIO', v_cg, false);
    perform pg_temp.wh_5894_it(h15, 1, 'COLLECTION', 'ATTACHED', null, null, null);
    insert into public.collection_layout_catalog_incorporation (layout_id, collection_id, item_key)
    values (l_m, v_cf, k1::text || ':*'), (l_f, v_cm, k2::text || ':*');
    l3 := pg_temp.wh_5894_ev(u_a, l_m, 24, null, 'LEGACY_CATALOG_INCORPORATION', 'LEGADO', v_cm, false,
      jsonb_build_object('item_key', k1::text || ':*'));
    perform pg_temp.wh_5894_it(l3, 1, 'CARD', 'INCORPORATED', k1, 'SR K1', null);
    l4 := pg_temp.wh_5894_ev(u_a, l_m, 23, null, 'LEGACY_CATALOG_INCORPORATION', 'LEGADO', v_cm, false,
      jsonb_build_object('item_key', k2::text || ':*'));
    perform pg_temp.wh_5894_it(l4, 1, 'CARD', 'INCORPORATED', k2, 'SR K2 SEGREDO DE CG', null);

    select string_agg(ca.physical_card_id::text || ':' || ca.collection_id::text, ',' order by ca.physical_card_id) into alloc0
      from public.collection_allocation ca where ca.physical_card_id in (f1, g1, ma1, ma2, d1, d2);
    select string_agg(md5((to_jsonb(pc) - 'updated_at')::text), ',' order by pc.id) into pc0
      from public.physical_card pc where pc.id in (f1, g1, ma1, ma2, d1, d2);
    res := res || jsonb_build_object('id','F.2','ok',
      exists (select 1 from public.collection_layout_guest g where g.layout_id = l_f and g.collection_id = v_cg)
      and exists (select 1 from public.collection_pokedex_position_assignment a join public.collection_allocation ca
                  on ca.id = a.collection_allocation_id where ca.physical_card_id = d1 and a.pokedex_position_id = v_pos)
      and (select count(*) from public.collection_membership m where m.collection_id = v_cf and m.status = 'ACTIVE') = 2
      and exists (select 1 from public.collection_membership m where m.id = m_p and m.status = 'PENDING')
      and not exists (select 1 from public.collection_layout_slot_assignment a join public.collection_layout_slot s on s.id = a.slot_id
                      join public.collection_layout_page pg on pg.id = s.page_id where pg.layout_id in (l_f, l_m)),
      'detail','fixture: CF com convidada CG; CD com d1 na posição P1; B e V ativos em CF; P pendente; bolsos dos fichários vazios');

    -- 1. Matriz de acesso --------------------------------------------------------------------
    perform pg_temp.wh_5894_as(u_b);
    v_j := public.get_shared_collection(v_cf);
    select count(*) into n from public.get_shared_collection_cards(v_cf, 50, 0);
    execute 'reset role';
    res := res || jsonb_build_object('id','1.1','ok', v_j ->> 'access' = 'VIEWER' and v_j ->> 'role' = 'EDITOR' and n >= 1,
      'detail','EDITOR continua com as leituras da V1-12 (nível VIEWER pela 5302, papel EDITOR na 5312)');

    v_ok := true;
    foreach v_txt in array array[u_c::text, u_p::text, u_r::text] loop
      perform pg_temp.wh_5894_as(v_txt::uuid);
      if exists (select 1 from public.get_shared_master_set_positions(v_cm, 'ALL', 500, 0))
         or exists (select 1 from public.get_shared_pokedex_positions(v_cd, 'ALL', null, 500, 0))
         or exists (select 1 from public.get_shared_binder_activity(v_cf, null, null, null, 50))
         or exists (select 1 from public.get_shared_binder_activity(v_cm, null, null, null, 50))
         or exists (select 1 from public.get_shared_binder_activity_status(v_cf)) then
        v_ok := false;
      end if;
    end loop;
    perform pg_temp.wh_5894_as(u_b);
    if exists (select 1 from public.get_shared_binder_activity(v_x2, null, null, null, 50))
       or exists (select 1 from public.get_shared_binder_activity_status(v_x2)) then
      v_ok := false;
    end if;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.2','ok', v_ok,
      'detail','estranho, convite pendente e membro removido: zero linhas nas 4 leituras; EDITOR de A não lê coleção de outro titular');

    perform pg_temp.wh_5894_as(null);
    v_err := pg_temp.wh_5894_try(format('select * from public.get_shared_master_set_positions(%L)', v_cm))
      || ';' || pg_temp.wh_5894_try(format('select * from public.get_shared_pokedex_positions(%L)', v_cd))
      || ';' || pg_temp.wh_5894_try(format('select * from public.get_shared_binder_activity(%L)', v_cf))
      || ';' || pg_temp.wh_5894_try(format('select * from public.get_shared_binder_activity_status(%L)', v_cf));
    execute 'reset role';
    res := res || jsonb_build_object('id','1.3','ok',
      (select count(*) from regexp_matches(v_err, 'permission denied', 'g')) = 4,
      'detail','sessão anônima: sem EXECUTE nas 4 leituras');

    -- 2. Master Set (5323) --------------------------------------------------------------------
    perform pg_temp.wh_5894_as(u_a);
    v_o1 := pg_temp.wh_5894_ms(v_cm, 'ALL', false);
    v_s3 := pg_temp.wh_5894_ms(v_cm, 'ALL', true);
    select x.copies_available into n from public.get_my_master_set_positions(v_cm, 'ALL', 500, 0) x where x.card_id = m1;
    perform pg_temp.wh_5894_as(u_b); v_s1 := pg_temp.wh_5894_ms(v_cm, 'ALL', true);
    perform pg_temp.wh_5894_as(u_v); v_s2 := pg_temp.wh_5894_ms(v_cm, 'ALL', true);
    execute 'reset role';
    res := res || jsonb_build_object('id','2.1','ok', v_o1 <> '<vazio>' and v_s1 = v_o1 and v_s2 = v_o1 and v_s3 = v_o1 and n = 1,
      'detail','Master Set: EDITOR, VIEWER e titular pela leitura compartilhada = colunas comuns da grade do titular (posições, satisfação, exemplares da coleção, imagem); o titular tem 1 exemplar livre que a leitura compartilhada não devolve');

    perform pg_temp.wh_5894_as(u_a);
    v_o1 := pg_temp.wh_5894_ms(v_cm, 'OWNED', false) || '#' || pg_temp.wh_5894_ms(v_cm, 'MISSING', false);
    perform pg_temp.wh_5894_as(u_b);
    v_s1 := pg_temp.wh_5894_ms(v_cm, 'OWNED', true) || '#' || pg_temp.wh_5894_ms(v_cm, 'MISSING', true);
    v_err := pg_temp.wh_5894_try(format('select * from public.get_shared_master_set_positions(%L, %L)', v_cm, 'X'))
      || ';' || pg_temp.wh_5894_try(format('select * from public.get_shared_master_set_positions(%L, %L, 501)', v_cm, 'ALL'));
    select count(*) into n from public.get_shared_master_set_positions(v_cf, 'ALL', 500, 0);
    execute 'reset role';
    res := res || jsonb_build_object('id','2.2','ok', v_s1 = v_o1 and v_err = 'INVALID_FILTER;INVALID_PAGE' and n = 0,
      'detail','filtros Tenho/Faltam iguais aos do titular; filtro e página inválidos recusados; coleção que não é Master Set → zero linhas');

    perform pg_temp.wh_5894_as(u_b); v_s1 := pg_temp.wh_5894_ms(v_cm, 'ALL', true);
    execute 'reset role';
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (m1s, v_pt, v_inv_a);
    perform pg_temp.wh_5894_as(u_a);
    select x.copies_available into n2 from public.get_my_master_set_positions(v_cm, 'ALL', 500, 0) x where x.card_id = m1;
    perform pg_temp.wh_5894_as(u_b); v_s2 := pg_temp.wh_5894_ms(v_cm, 'ALL', true);
    execute 'reset role';
    res := res || jsonb_build_object('id','2.3','ok', n2 = 2 and v_s2 = v_s1,
      'detail','novo exemplar livre no acervo: muda a grade do titular (disponíveis 1→2) e NÃO muda a do participante (sem inferência do acervo)');

    -- 3. Pokédex (5324) ------------------------------------------------------------------------
    perform pg_temp.wh_5894_as(u_a);
    v_o1 := pg_temp.wh_5894_pd(v_cd, 'ALL', null, false);
    v_s3 := pg_temp.wh_5894_pd(v_cd, 'ALL', null, true);
    select * into q from public.get_my_pokedex_positions(v_cd, 'ALL', null, 500, 0) x where x.pokedex_position_id = v_pos;
    perform pg_temp.wh_5894_as(u_b); v_s1 := pg_temp.wh_5894_pd(v_cd, 'ALL', null, true);
    perform pg_temp.wh_5894_as(u_v); v_s2 := pg_temp.wh_5894_pd(v_cd, 'ALL', null, true);
    execute 'reset role';
    res := res || jsonb_build_object('id','3.1','ok', v_o1 <> '<vazio>' and v_s1 = v_o1 and v_s2 = v_o1 and v_s3 = v_o1
      and q.is_satisfied and q.copies_in_collection = 1 and q.copies_available = 1 and q.copies_elsewhere = 1
      and q.representative_card_name = 'SR K1',
      'detail','Pokédex: EDITOR, VIEWER e titular pela leitura compartilhada = colunas comuns (escopo, satisfação, representante da coleção); disponíveis e em outra coleção existem para o titular e não saem para o participante');

    perform pg_temp.wh_5894_as(u_b); v_s1 := pg_temp.wh_5894_pd(v_cd, 'ALL', null, true);
    execute 'reset role';
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (k1s, v_pt, v_inv_a), (k1s, v_pt, v_inv_a);
    perform pg_temp.wh_5894_as(u_a);
    perform public.allocate_physical_cards_to_collection(v_cf,
      array[(select pc.id from public.physical_card pc where pc.inventory_id = v_inv_a and pc.card_variant_id = k1s
               and not exists (select 1 from public.collection_allocation ca where ca.physical_card_id = pc.id)
             order by pc.created_at desc, pc.id limit 1)]);
    select * into q from public.get_my_pokedex_positions(v_cd, 'ALL', null, 500, 0) x where x.pokedex_position_id = v_pos;
    perform pg_temp.wh_5894_as(u_b); v_s2 := pg_temp.wh_5894_pd(v_cd, 'ALL', null, true);
    execute 'reset role';
    res := res || jsonb_build_object('id','3.2','ok', q.copies_available = 2 and q.copies_elsewhere = 2 and v_s2 = v_s1,
      'detail','novos exemplares livres e em outra coleção: mudam a grade do titular e NÃO mudam a do participante');

    perform pg_temp.wh_5894_as(u_a);
    v_o1 := pg_temp.wh_5894_pd(v_cd, 'MISSING', v_gen, false) || '#' || pg_temp.wh_5894_pd(v_cd, 'OWNED', null, false);
    perform pg_temp.wh_5894_as(u_b);
    v_s1 := pg_temp.wh_5894_pd(v_cd, 'MISSING', v_gen, true) || '#' || pg_temp.wh_5894_pd(v_cd, 'OWNED', null, true);
    v_err := pg_temp.wh_5894_try(format('select * from public.get_shared_pokedex_positions(%L, %L)', v_cd, 'X'));
    select count(*) into n from public.get_shared_pokedex_positions(v_cm, 'ALL', null, 500, 0);
    execute 'reset role';
    res := res || jsonb_build_object('id','3.3','ok', v_s1 = v_o1 and v_err = 'INVALID_FILTER' and n = 0,
      'detail','filtro de geração e Tenho/Faltam iguais aos do titular; filtro inválido recusado; coleção que não é Pokédex → zero linhas');

    perform pg_temp.wh_5894_as(u_b);
    v_j := public.get_shared_collection(v_cm);  -- E1E: C2 — progresso pela leitura pública 5312 (repassa a 5310 da mesma coleção; a 5310 é interna, sem EXECUTE)
    v_ok := (v_j ->> 'satisfied_positions')::bigint = (select count(*) filter (where x.is_satisfied) from public.get_shared_master_set_positions(v_cm, 'ALL', 500, 0) x)  -- E1E
            and (v_j ->> 'total_positions')::bigint = (select max(x.total_count) from public.get_shared_master_set_positions(v_cm, 'ALL', 500, 0) x);  -- E1E
    v_j := public.get_shared_collection(v_cd);  -- E1E: C2 — idem para a Pokédex
    v_ok := v_ok and ((v_j ->> 'satisfied_positions')::bigint = (select count(*) filter (where x.is_satisfied) from public.get_shared_pokedex_positions(v_cd, 'ALL', null, 500, 0) x)  -- E1E
            and (v_j ->> 'total_positions')::bigint = (select max(x.total_count) from public.get_shared_pokedex_positions(v_cd, 'ALL', null, 500, 0) x));  -- E1E
    select sum(x.copies_in_collection) into n from public.get_shared_master_set_positions(v_cm, 'ALL', 500, 0) x;
    select sum(x.copies_in_collection) into n2 from public.get_shared_pokedex_positions(v_cd, 'ALL', null, 500, 0) x;
    execute 'reset role';
    res := res || jsonb_build_object('id','3.4','ok', coalesce(v_ok, false)
      and n = (select count(*) from public.collection_allocation ca where ca.collection_id = v_cm)
      and n2 = (select count(*) from public.collection_allocation ca join public.collection_pokedex_position_assignment a
                 on a.collection_allocation_id = ca.id where ca.collection_id = v_cd),
      'detail','agregados: progresso compartilhado (5310, lido pela 5312) = satisfeitas/total das grades 5323/5324; soma de exemplares = alocações da coleção (nada do acervo entra na soma)');  -- E1E: detalhe cita a leitura pública

    -- 4. Histórico compartilhado (5388) --------------------------------------------------------
    perform pg_temp.wh_5894_as(u_b);
    v_a := pg_temp.wh_5894_ids(v_cf);
    v_txt := pg_temp.wh_5894_hist(v_cf);
    execute 'reset role';
    res := res || jsonb_build_object('id','4.1','ok', v_a = array[h18, h14, h9, h8, h2, h1],
      'detail','EDITOR em CF vê exatamente h18, h14, h9, h8, h2, h1 (ordem occurred_at desc, id desc); ocultos: só de CG (h3), registrado para CG (h4), E07 (h5), E17 (h6), não atribuído (h7), outro fichário (h10), par tipo/origem inválido (h12), outro titular (h13), sem coleção só com item de CG (h17), sem coleção só estrutural (h19), sem coleção e sem autoria (h20), sem coleção de outro titular (h21)');

    perform pg_temp.wh_5894_as(u_b);
    select * into p from public.get_shared_binder_activity(v_cf, null, null, null, 50) x where x.event_id = h2;
    execute 'reset role';
    res := res || jsonb_build_object('id','4.2','ok', p.item_count = 1 and not p.items_truncated
      and jsonb_array_length(p.items) = 1 and (p.items -> 0 ->> 'ordinal')::integer = 1
      and p.items -> 0 ->> 'card_name' = 'SR K1' and p.items -> 0 ->> 'kind' = 'CARD' and p.category = 'CARDS',
      'detail','organização automática (D13): só o item de CF, contagem 1, ordinal renumerado; cartas de CG e página fora');

    res := res || jsonb_build_object('id','4.3','ok',
      position('SEGREDO' in v_txt) = 0 and position('GRAVADO' in v_txt) = 0 and position('"detail"' in v_txt) = 0
      and position('summary' in v_txt) = 0 and position('NM' in v_txt) = 0 and position('example.invalid' in v_txt) = 0
      and position('wh894' in v_txt) = 0 and position(f1::text in v_txt) = 0 and position(c_f::text in v_txt) = 0
      and position(v_cg::text in v_txt) = 0 and position(v_cf::text in v_txt) = 0 and position(u_a::text in v_txt) = 0
      and position(u_b::text in v_txt) = 0 and position(l_f::text in v_txt) = 0,
      'detail','saída sem nome de outra coleção ou carta dela, nome de coleção/fichário gravado, detalhe (exemplar, condição, local), resumo, e-mail, nome de usuário e ids de coleção, fichário ou usuário');

    perform pg_temp.wh_5894_as(u_b);
    select * into p from public.get_shared_binder_activity(v_cf, null, null, null, 50) x where x.event_id = h9;
    select * into q from public.get_shared_binder_activity(v_cf, null, null, null, 50) x where x.event_id = h1;
    execute 'reset role';
    res := res || jsonb_build_object('id','4.4','ok', p.actor_role = 'PARTICIPANT' and p.actor_display_name = 'WH 5894 B'
      and q.actor_role = 'OWNER' and q.actor_display_name = 'WH 5894 A',
      'detail','ator: papel e nome de exibição público (EDITOR → Participante; titular → Titular)');

    perform pg_temp.wh_5894_as(u_v); v_txt2 := pg_temp.wh_5894_hist(v_cf);
    perform pg_temp.wh_5894_as(u_a); v_s1 := pg_temp.wh_5894_hist(v_cf);
    select count(*) into v_cnt_owner from public.get_my_binder_activity(l_f, null, null, null, 50);
    execute 'reset role';
    res := res || jsonb_build_object('id','4.5','ok', v_txt2 = v_txt and v_s1 = v_txt
      and v_cnt_owner = (select count(*) from public.binder_activity_event e where e.owner_user_id = u_a and e.layout_key = l_f),
      'detail','VIEWER e titular pela leitura compartilhada veem o mesmo que o EDITOR; leitura integral do titular (5269) inalterada');

    perform pg_temp.wh_5894_as(u_e); v_b := pg_temp.wh_5894_ids(v_cg);
    execute 'reset role';
    res := res || jsonb_build_object('id','4.6','ok', v_b = array[h18, h17, h4],
      'detail','EDITOR da convidada CG vê o evento registrado para CG (h4) e os do titular sem coleção com item de CG (h17, h18); evento registrado para CF com cartas de CG (h2) não aparece');

    -- D14: evento do titular sem coleção registrada, itens filtrados por coleção.
    perform pg_temp.wh_5894_as(u_b);
    select * into p from public.get_shared_binder_activity(v_cf, null, null, null, 50) x where x.event_id = h18;
    select * into q from public.get_shared_binder_activity(v_cf, null, null, null, 50) x where x.event_id = h14;
    perform pg_temp.wh_5894_as(u_e);
    select x.item_count::text || ':' || (x.items -> 0 ->> 'card_name') || ':' || (x.items -> 0 ->> 'ordinal') into v_s1
      from public.get_shared_binder_activity(v_cg, null, null, null, 50) x where x.event_id = h18;
    v_ok := not exists (select 1 from public.get_shared_binder_activity(v_cg, null, null, null, 50) x
                        where x.event_id in (h14, h19, h20));
    execute 'reset role';
    res := res || jsonb_build_object('id','4.9','ok', p.item_count = 1 and jsonb_array_length(p.items) = 1
      and p.items -> 0 ->> 'card_name' = 'SR K1' and (p.items -> 0 ->> 'ordinal')::integer = 1
      and p.actor_role = 'OWNER' and p.category = 'CARDS'
      and q.item_count = 1 and q.actor_role = 'OWNER' and q.actor_display_name = 'WH 5894 A'
      and v_s1 = '1:SR K2 SEGREDO DE CG:1' and v_ok,
      'detail','D14: evento do titular sem coleção com itens de CF e CG — CF vê só o seu item (contagem 1, ordinal 1) e CG só o dele; h14 visível a CF com autor Titular; h14/h19/h20 não aparecem a CG');

    perform pg_temp.wh_5894_as(u_b);
    v_b := pg_temp.wh_5894_ids(v_cf, array['PAGES']);
    select array_agg(x.event_id order by x.occurred_at desc, x.event_id desc) into v_a
      from public.get_shared_binder_activity(v_cf, null, null, null, 2) x;
    select * into p from public.get_shared_binder_activity(v_cf, null, null, null, 2) x order by x.occurred_at, x.event_id limit 1;
    select v_a || array_agg(x.event_id order by x.occurred_at desc, x.event_id desc) into v_a
      from public.get_shared_binder_activity(v_cf, null, p.occurred_at, p.event_id, 50) x;
    v_err := pg_temp.wh_5894_try(format('select * from public.get_shared_binder_activity(%L, null, now(), null)', v_cf))
      || ';' || pg_temp.wh_5894_try(format('select * from public.get_shared_binder_activity(%L, array[%L])', v_cf, 'NADA'));
    execute 'reset role';
    res := res || jsonb_build_object('id','4.7','ok', v_b = array[h8] and v_a = array[h18, h14, h9, h8, h2, h1]
      and v_err = 'cursor must have occurred_at and id together;unknown category',
      'detail','categoria Páginas → só h8; paginação por cursor (2 + resto) reconstitui a lista sem repetir; cursor incompleto e categoria desconhecida recusados');

    perform pg_temp.wh_5894_as(u_b);
    v_a := pg_temp.wh_5894_ids(v_cm);
    select * into p from public.get_shared_binder_activity(v_cm, null, null, null, 50) x where x.event_id = l1;
    execute 'reset role';
    res := res || jsonb_build_object('id','4.8','ok', v_a = array[l1] and p.is_legacy and p.actor_role is null
      and p.actor_display_name is null and p.category = 'CATALOG' and p.item_count = 1
      and p.items -> 0 ->> 'effect' = 'INCORPORATED' and p.items -> 0 ->> 'card_name' = 'SM 1',
      'detail','L01 (D12): visível só com a linha de origem de CM neste fichário (l1); sem origem (l2), origem de outra coleção (l3) ou de outro fichário (l4) oculto; sem ator; evento do titular sem coleção não atribuído (h16) oculto');

    -- 5. Estado do histórico e fichário encerrado ----------------------------------------------
    perform pg_temp.wh_5894_as(u_b);
    select * into p from public.get_shared_binder_activity_status(v_cf);
    select * into q from public.get_shared_binder_activity_status(v_cd);
    select count(*) into n from public.get_shared_binder_activity(v_cd, null, null, null, 50);
    v_txt := (select s.has_binder::text || '/' || s.history_may_be_partial::text from public.get_shared_binder_activity_status(v_cm) s);
    perform pg_temp.wh_5894_as(u_e);
    v_txt2 := (select s.has_binder::text || '/' || s.history_may_be_partial::text from public.get_shared_binder_activity_status(v_cg) s);
    execute 'reset role';
    res := res || jsonb_build_object('id','5.1','ok', p.has_binder and p.history_may_be_partial
      and not q.has_binder and not q.history_may_be_partial and n = 0 and v_txt = 'true/true' and v_txt2 = 'true/false',
      'detail','histórico parcial (D12): CF (h7 não atribuído) e CM (l2 sem origem, h16 sem coleção não atribuído) → true; CG → false apesar de h7 (registrado para outra coleção), h15 (estrutura não atribuída de CG) e eventos D14 atribuídos; CD sem fichário → false/false e nenhum evento');

    perform pg_temp.wh_5894_as(u_a);
    perform count(*) from public.transfer_my_binder_ownership(v_cf, v_cg);
    perform pg_temp.wh_5894_as(u_b); v_a := pg_temp.wh_5894_ids(v_cf);
    v_txt := (select s.has_binder::text from public.get_shared_binder_activity_status(v_cf) s);
    perform pg_temp.wh_5894_as(u_e); v_b := pg_temp.wh_5894_ids(v_cg);
    execute 'reset role';
    v_ok := exists (select 1 from public.collection_layout l where l.id = l_f and l.collection_id = v_cg)
        and exists (select 1 from public.collection_layout_guest g where g.layout_id = l_f and g.collection_id = v_cf);
    perform pg_temp.wh_5894_as(u_a);
    perform count(*) from public.transfer_my_binder_ownership(v_cg, v_cf);
    execute 'reset role';
    res := res || jsonb_build_object('id','5.3','ok', v_ok and v_a = array[h18, h14, h9, h8, h2, h1] and v_txt = 'true' and v_b = array[h18, h17, h4]
      and exists (select 1 from public.collection_layout l where l.id = l_f and l.collection_id = v_cf),
      'detail','transferência de âncora CF→CG (chave do fichário preservada, CF vira convidada): membros de CF seguem vendo os eventos de CF anteriores; membros de CG não ganham eventos de CF; E20 oculto; âncora devolvida');

    perform pg_temp.wh_5894_as(u_a);
    select * into p from public.preview_my_collection_binder_detach(v_cg);
    perform count(*) from public.detach_my_collection_from_binder(v_cg, p.detach_token, false);
    perform pg_temp.wh_5894_as(u_e);
    select count(*) into n from public.get_shared_binder_activity(v_cg, null, null, null, 50);
    select * into q from public.get_shared_binder_activity_status(v_cg);
    execute 'reset role';
    res := res || jsonb_build_object('id','5.2','ok', n = 0 and not q.has_binder and not q.history_may_be_partial,
      'detail','convidada desassociada: o histórico do fichário deixa de ser legível pelos membros dela (C-208); evento h4 continua gravado');

    -- 6. Revogação e estado da coleção ---------------------------------------------------------
    perform pg_temp.wh_5894_as(u_a);
    perform public.set_collection_member_role(v_cf, m_b, 'VIEWER');
    perform pg_temp.wh_5894_as(u_b); v_a := pg_temp.wh_5894_ids(v_cf);
    perform pg_temp.wh_5894_as(u_a);
    perform public.remove_collection_member(v_cf, m_b);
    perform public.remove_collection_member(v_cm, m_bm);
    perform public.remove_collection_member(v_cd, m_bd);
    perform pg_temp.wh_5894_as(u_b);
    v_ok := not exists (select 1 from public.get_shared_binder_activity(v_cf, null, null, null, 50))
        and not exists (select 1 from public.get_shared_binder_activity_status(v_cf))
        and not exists (select 1 from public.get_shared_master_set_positions(v_cm, 'ALL', 500, 0))
        and not exists (select 1 from public.get_shared_pokedex_positions(v_cd, 'ALL', null, 500, 0));
    execute 'reset role';
    res := res || jsonb_build_object('id','6.1','ok', v_a = array[h18, h14, h9, h8, h2, h1] and v_ok,
      'detail','troca EDITOR→VIEWER mantém a mesma leitura; remoção encerra as 4 leituras na chamada seguinte');

    -- 7. Sem efeito patrimonial ----------------------------------------------------------------
    res := res || jsonb_build_object('id','7.1','ok',
      (select string_agg(ca.physical_card_id::text || ':' || ca.collection_id::text, ',' order by ca.physical_card_id)
         from public.collection_allocation ca where ca.physical_card_id in (f1, g1, ma1, ma2, d1, d2)) = alloc0
      and (select string_agg(md5((to_jsonb(pc) - 'updated_at')::text), ',' order by pc.id)
             from public.physical_card pc where pc.id in (f1, g1, ma1, ma2, d1, d2)) = pc0
      and not exists (select 1 from public.binder_activity_event e where e.owner_user_id = u_a and e.actor_user_id in (u_b, u_v, u_e)
                        and e.id not in (h9)),
      'detail','leituras não gravam nada: alocações e exemplares da fixture intactos; nenhum evento de membro além do gravado na fixture (C-171)');

    perform pg_temp.wh_5894_as(u_a); perform public.archive_collection(v_cm);
    perform pg_temp.wh_5894_as(u_v);
    v_ok := ((public.get_shared_collection(v_cm)) is not null)
            = exists (select 1 from public.get_shared_master_set_positions(v_cm, 'ALL', 500, 0))
        and ((public.get_shared_collection(v_cm)) is not null)
            = exists (select 1 from public.get_shared_binder_activity(v_cm, null, null, null, 50));
    execute 'reset role';
    res := res || jsonb_build_object('id','6.2','ok', v_ok,
      'detail','coleção arquivada: as leituras novas seguem exatamente a regra vigente da 5312 (mesmo acesso de leitura)');

    execute 'reset role';
    raise exception 'MS894' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MS894' then
      res := res || jsonb_build_object('id','X.1','ok', false, 'detail','erro inesperado: '||sqlstate||' '||sqlerrm);
    end if;
  end;

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('mmkyu.binder_activity_ctx', '', true);
  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.collection_membership), (select count(*) from public.collection_layout_page),
               (select count(*) from public.collection_layout_slot_assignment),
               (select count(*) from public.collection_layout_catalog_incorporation),
               (select count(*) from public.collection_pokedex_position_assignment),
               (select count(*) from public.binder_activity_event), (select count(*) from public.binder_activity_item),
               (select count(*) from public.card)]
    into e_counts;
  res := res || jsonb_build_object('id','99.1','ok', b_counts = e_counts and current_user = session_user,
    'detail','resíduo zero (12 contagens, inclusive atribuições Pokédex, incorporações e histórico) e papel restaurado');

  v_expected := 29;
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
  select '5894', seq, check_id, status, detail from pg_temp.wh_5894_validate();

-- @@T8 modo da barreira CLOSED (só nesta transação)
update public.v1_13_barrier_state set mode = 'CLOSED', change_note = 'G2 ensaio' where id = 1;

-- @@T7 lock imediato ou recusa (NOWAIT) antes da 5377: storage.objects (O2)
LOCK TABLE storage.objects IN ACCESS EXCLUSIVE MODE NOWAIT;
insert into pg_temp.g2_meta (k, v) values ('t_lock_storage', to_jsonb(pg_catalog.clock_timestamp()));

-- @@T7 5377 (protegida) sha256=badd1f543f3436c6cc0650b7e699445d6989fbee6ece80553f77ee4d8f92467e
set local lock_timeout = '5s';

do $pre$
begin
  if to_regprocedure('public.v1_13_assert_capability()') is null or to_regprocedure('public.v1_13_capability_open()') is null then raise exception 'PRECHECK G1: barreira 5389 ausente'; end if;  -- G1 (D-E1)
  if not exists (select 1 from storage.buckets b where b.id = 'collection-cover' and b.public is false) then
    raise exception 'PRECHECK 5377: ESTADO DIVERGENTE — bucket collection-cover ausente ou público';
  end if;
  if (select count(*) from pg_catalog.pg_policies p
       where p.schemaname = 'storage' and p.tablename = 'objects'
         and p.policyname in ('collection_cover_select_own', 'collection_cover_insert_own',
                              'collection_cover_update_own', 'collection_cover_delete_own')) <> 4 then
    raise exception 'PRECHECK 5377: ESTADO DIVERGENTE — políticas do dono (5176) ausentes';
  end if;
  if exists (select 1 from pg_catalog.pg_policies p
             where p.schemaname = 'storage' and p.tablename = 'objects'
               and p.policyname like 'collection_cover_%_editor')
     or to_regprocedure('public.collection_cover_editor_folder_ok(text)') is not null
     or to_regprocedure('public.collection_cover_editor_folder_ok(text, boolean)') is not null
     or to_regprocedure('public.collection_cover_editor_can_upload(text)') is not null then
    raise exception 'PRECHECK 5377: JÁ APLICADA ou ESTADO DIVERGENTE';
  end if;
  if (select pg_catalog.pg_get_constraintdef(k.oid) from pg_catalog.pg_constraint k
       where k.conrelid = 'public.collection_membership'::regclass
         and k.conname = 'chk_collection_membership_role')
     is distinct from 'CHECK ((role = ANY (ARRAY[''VIEWER''::text, ''EDITOR''::text])))' then
    raise exception 'PRECHECK 5377: E1-A (5366) não aplicada';
  end if;
end;
$pre$;

create function public.collection_cover_editor_folder_ok(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_uid   uuid := (select auth.uid());
  v_parts text[];
  v_owner uuid;
  v_coll  uuid;
  v_cur   text;
begin
  if not public.v1_13_capability_open() then return false; end if;  -- G1 (D-E1)
  if v_uid is null or p_name is null
     or p_name !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(png|jpg|webp)$' then
    return false;
  end if;
  v_parts := storage.foldername(p_name);
  begin
    v_owner := v_parts[1]::uuid;
    v_coll  := v_parts[2]::uuid;
  exception when invalid_text_representation then
    return false;
  end;
  if v_owner = v_uid then
    return false;   -- pasta do próprio usuário: regida pelas políticas do dono (5176)
  end if;

  select c.cover_logo_path into v_cur
  from public.collection c
  join public.collection_membership m
    on m.collection_id = c.id and m.user_id = v_uid and m.status = 'ACTIVE' and m.role = 'EDITOR'
  where c.id = v_coll
    and c.owner_user_id = v_owner
    and c.lifecycle_status = 'ACTIVE'
    and ((c.completion_policy = 'NONE'
          and not exists (select 1 from public.collection_reference cr where cr.collection_id = c.id))
         or (c.completion_policy = 'REFERENCE_POSITION'
             and exists (select 1 from public.collection_reference cr
                         where cr.collection_id = c.id and cr.reference_kind = 'POKEDEX')));
  if not found then
    return false;
  end if;
  -- Nunca a capa atual por este caminho (a leitura da capa atual por participantes
  -- é da 5329; a exclusão dela só pelo titular, 5176).
  return p_name is distinct from v_cur;
end;
$fn$;

comment on function public.collection_cover_editor_folder_ok(text) is
  'V1-13 E1-B2 (5377 v1.1): usada pelas políticas collection_cover_select_editor e collection_cover_delete_editor (e pelo envio). Verdadeiro só se o usuário da sessão é EDITOR ACTIVE da coleção da pasta <titular>/<coleção>/, coleção ativa com imagem de placa, e o arquivo não é a capa atual.';

revoke all on function public.collection_cover_editor_folder_ok(text) from public, anon, service_role;
grant execute on function public.collection_cover_editor_folder_ok(text) to authenticated;

create function public.collection_cover_editor_can_upload(p_name text)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_uid   uuid := (select auth.uid());
  v_parts text[];
  v_owner uuid;
  v_coll  uuid;
  v_cur   text;
  v_n     integer;
begin
  if not public.v1_13_capability_open() then return false; end if;  -- G1 (D-E1)
  if v_uid is null or p_name is null
     or p_name !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(png|jpg|webp)$' then
    return false;
  end if;
  v_parts := storage.foldername(p_name);
  begin
    v_owner := v_parts[1]::uuid;
    v_coll  := v_parts[2]::uuid;
  exception when invalid_text_representation then
    return false;
  end;
  if v_owner = v_uid then
    return false;
  end if;

  -- Serializa os envios do MESMO EDITOR na MESMA coleção até o fim da transação.
  -- Cada comando seguinte desta função VOLÁTIL usa snapshot novo (READ COMMITTED):
  -- depois da espera, o envio concorrente já confirmado entra na contagem.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('mmkyu:collection-cover-editor:' || v_uid::text || ':' || v_coll::text, 5377));

  if public.collection_cover_editor_folder_ok(p_name) is not true then
    return false;
  end if;

  select c.cover_logo_path into v_cur from public.collection c where c.id = v_coll;
  select count(*) into v_n
  from storage.objects o
  where o.bucket_id = 'collection-cover'
    and o.name like v_owner::text || '/' || v_coll::text || '/%'
    and (o.owner_id = v_uid::text or o.owner = v_uid)
    and o.name is distinct from v_cur;
  return v_n < 3;
end;
$fn$;

comment on function public.collection_cover_editor_can_upload(text) is
  'V1-13 E1-B2 (5377 v1.1): usada só pela política collection_cover_insert_editor. Trava (EDITOR, coleção) até o fim da transação, reavalia collection_cover_editor_folder_ok e permite o envio só com menos de 3 arquivos dele ainda não usados na pasta. Proteção contra corrida depende de READ COMMITTED e de a API do Storage gravar sob esta política; sem prova real.';

revoke all on function public.collection_cover_editor_can_upload(text) from public, anon, service_role;
grant execute on function public.collection_cover_editor_can_upload(text) to authenticated;

create policy collection_cover_insert_editor
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'collection-cover'
    and public.collection_cover_editor_can_upload(name)
  );

create policy collection_cover_select_editor
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'collection-cover'
    and owner_id = (select auth.uid())::text
    and public.collection_cover_editor_folder_ok(name)
  );

create policy collection_cover_delete_editor
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'collection-cover'
    and owner_id = (select auth.uid())::text
    and public.collection_cover_editor_folder_ok(name)
  );

do $post$
declare
  f oid := to_regprocedure('public.collection_cover_editor_folder_ok(text)');
  g oid := to_regprocedure('public.collection_cover_editor_can_upload(text)');
begin
  if f is null or g is null
     or (select count(*) from pg_catalog.pg_proc p
          where p.oid in (f, g) and p.prosecdef and p.proconfig = array['search_path=""']) <> 2
     or (select p.provolatile from pg_catalog.pg_proc p where p.oid = f) <> 's'
     or (select p.provolatile from pg_catalog.pg_proc p where p.oid = g) <> 'v'
     or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not true
     or pg_catalog.has_function_privilege('authenticated', g, 'EXECUTE') is not true
     or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false
     or pg_catalog.has_function_privilege('anon', g, 'EXECUTE') is not false then
    raise exception 'POSTCHECK 5377: ajudantes fora do estado esperado';
  end if;
  if (select count(*) from pg_catalog.pg_policies p
       where p.schemaname = 'storage' and p.tablename = 'objects'
         and p.policyname in ('collection_cover_insert_editor', 'collection_cover_select_editor', 'collection_cover_delete_editor')
         and p.roles = array['authenticated']::name[]) <> 3 then
    raise exception 'POSTCHECK 5377: políticas do EDITOR fora do estado esperado';
  end if;
  if exists (select 1 from pg_catalog.pg_policies p
             where p.schemaname = 'storage' and p.tablename = 'objects'
               and p.policyname like 'collection_cover_%_editor' and p.cmd = 'UPDATE') then
    raise exception 'POSTCHECK 5377: política de UPDATE para o EDITOR não deveria existir';
  end if;
  if (select count(*) from pg_catalog.pg_policies p
       where p.schemaname = 'storage' and p.tablename = 'objects'
         and p.policyname in ('collection_cover_select_own', 'collection_cover_insert_own',
                              'collection_cover_update_own', 'collection_cover_delete_own')) <> 4 then
    raise exception 'POSTCHECK 5377: políticas do dono mudaram';
  end if;
end;
$post$;

-- @@T8 harness 5863 [CLOSED] sha256=ab3444f64d3e9b6085aeb3ed237c5cf7b4592ff76f5c0b52b61a3d58f87fbf8b
create or replace function pg_temp.wh_5863_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
as $fn$
declare
  f_core oid := to_regprocedure('public.collection_binder_shared_images(uuid,integer,integer)');
  f_shr  oid := to_regprocedure('public.get_shared_collection_binder_images(uuid,integer,integer)');
  f_pub  oid := to_regprocedure('public.get_public_collection_binder_images(uuid,integer,integer)');
  f_cov  oid := to_regprocedure('public.get_shared_collection_cover(uuid)');
  f_rd   oid := to_regprocedure('public.shared_visual_asset_readable(text,text)');
  u_a uuid := gen_random_uuid(); u_b uuid := gen_random_uuid(); u_c uuid := gen_random_uuid();
  u_d uuid := gen_random_uuid(); u_e uuid := gen_random_uuid(); u_f uuid := gen_random_uuid();
  v_sfx text := lower(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  v_game uuid; v_pt uuid; v_rar uuid; v_cat uuid; v_std uuid;
  v_exp uuid; v_set uuid; k1 uuid; k2 uuid; k3 uuid; k1s uuid; k2s uuid; k3s uuid;
  v_inv_a uuid; a1 uuid; a2 uuid; x1 uuid;
  v_bin uuid; v_co uuid; v_cx uuid; v_layout uuid; v_page uuid; p record;
  m_b uuid; m_c uuid; m_d uuid; m_f uuid; m_bx uuid;
  v_reg_row int; v_reg_col int; v_slot uuid; v_slot_row int; v_slot_col int; v_region uuid;
  p_slot text; p_reg text; p_loose text; p_cover text; p_old text;
  j jsonb; v_err text; v_txt text; n integer; n2 integer; b1 boolean; b2 boolean; b3 boolean;
  b_counts bigint[]; e_counts bigint[];
  res jsonb := '[]'::jsonb; r jsonb; cnt integer := 0; passes integer := 0;
  v_expected integer := 37;
  v_names text;
begin
  -- S. Estrutura -------------------------------------------------------------------------
  res := res || jsonb_build_object('id','S.1','ok',
    f_core is not null and f_shr is not null and f_pub is not null and f_cov is not null and f_rd is not null
    and (select bool_and(q.prosecdef and q.proconfig @> array['search_path=""']) from pg_proc q where q.oid in (f_core, f_shr, f_pub, f_cov, f_rd)),
    'detail','5325–5329 presentes, definer, search_path vazio');
  res := res || jsonb_build_object('id','S.2','ok',
    not has_function_privilege('anon', f_core, 'EXECUTE') and not has_function_privilege('authenticated', f_core, 'EXECUTE')
    and has_function_privilege('authenticated', f_shr, 'EXECUTE') and not has_function_privilege('anon', f_shr, 'EXECUTE')
    and has_function_privilege('anon', f_pub, 'EXECUTE') and has_function_privilege('authenticated', f_pub, 'EXECUTE')
    and has_function_privilege('anon', f_cov, 'EXECUTE') and has_function_privilege('anon', f_rd, 'EXECUTE')
    and not exists (select 1 from pg_proc q, aclexplode(coalesce(q.proacl, '{}')) a where q.oid in (f_core, f_shr, f_pub, f_cov, f_rd) and a.grantee = 0),
    'detail','núcleo sem EXECUTE; participante só authenticated; vitrine/capa/decisão anon+authenticated; nada para PUBLIC');
  res := res || jsonb_build_object('id','S.3','ok',
    (select count(*) from pg_policies where schemaname = 'storage' and tablename = 'objects'
       and policyname in ('binder_slot_image_select_shared','collection_cover_select_shared')
       and cmd = 'SELECT' and roles @> array['anon','authenticated']::name[] and array_length(roles, 1) = 2
       and qual like '%shared_visual_asset_readable%') = 2
    and not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
       and policyname in ('binder_slot_image_select_shared','collection_cover_select_shared') and cmd <> 'SELECT'),
    'detail','duas políticas SELECT escopadas (anon, authenticated) delegando à função de decisão; nenhuma escrita');
  res := res || jsonb_build_object('id','S.4','ok',
    (select count(*) from pg_policies where schemaname = 'storage' and tablename = 'objects'
       and policyname in ('binder_slot_image_select_own','binder_slot_image_insert_own','binder_slot_image_delete_own',
                          'collection_cover_select_own','collection_cover_insert_own','collection_cover_update_own','collection_cover_delete_own')) = 7
    and (select count(*) from pg_policies pol  -- E1E
         join (values ('binder_slot_image_select_own','SELECT','binder-slot-image'),  -- E1E
                      ('binder_slot_image_insert_own','INSERT','binder-slot-image'),  -- E1E
                      ('binder_slot_image_delete_own','DELETE','binder-slot-image'),  -- E1E
                      ('collection_cover_select_own','SELECT','collection-cover'),  -- E1E
                      ('collection_cover_insert_own','INSERT','collection-cover'),  -- E1E
                      ('collection_cover_update_own','UPDATE','collection-cover'),  -- E1E
                      ('collection_cover_delete_own','DELETE','collection-cover')) e(n, c, b)  -- E1E
           on pol.policyname = e.n and pol.cmd = e.c  -- E1E
        where pol.schemaname = 'storage' and pol.tablename = 'objects'  -- E1E
          and pol.permissive = 'PERMISSIVE' and pol.roles = array['authenticated']::name[]  -- E1E
          and (coalesce(pol.qual, '') || coalesce(pol.with_check, '')) like '%' || e.b || '%'  -- E1E
          and (pol.qual is null or (pol.qual like '%foldername(name))[1]%' and pol.qual like '%auth.uid()%'))  -- E1E
          and (pol.with_check is null or (pol.with_check like '%foldername(name))[1]%' and pol.with_check like '%auth.uid()%'))  -- E1E
          and (pol.cmd <> 'UPDATE' or (pol.qual is not null and pol.with_check is not null))) = 7  -- E1E
    and (select count(*) from pg_policies pol  -- E1E
        where pol.schemaname = 'storage' and pol.tablename = 'objects'  -- E1E
          and pol.policyname in ('binder_slot_image_select_shared','collection_cover_select_shared')  -- E1E
          and pol.cmd = 'SELECT' and pol.permissive = 'PERMISSIVE'  -- E1E
          and pol.roles @> array['anon','authenticated']::name[] and cardinality(pol.roles) = 2  -- E1E
          and pol.qual like '%shared_visual_asset_readable%' and pol.with_check is null) = 2  -- E1E
    and (select count(*) from pg_policies pol  -- E1E
         join (values ('collection_cover_insert_editor','INSERT'),  -- E1E
                      ('collection_cover_select_editor','SELECT'),  -- E1E
                      ('collection_cover_delete_editor','DELETE')) e(n, c)  -- E1E
           on pol.policyname = e.n and pol.cmd = e.c  -- E1E
        where pol.schemaname = 'storage' and pol.tablename = 'objects'  -- E1E
          and pol.permissive = 'PERMISSIVE' and pol.roles = array['authenticated']::name[]  -- E1E
          and ((e.c = 'INSERT' and pol.qual is null and pol.with_check like '%collection-cover%'  -- E1E
                and pol.with_check like '%collection_cover_editor_can_upload(name)%')  -- E1E
               or (e.c <> 'INSERT' and pol.with_check is null and pol.qual like '%collection-cover%'  -- E1E
                   and pol.qual like '%owner_id%' and pol.qual like '%auth.uid()%'  -- E1E
                   and pol.qual like '%collection_cover_editor_folder_ok(name)%'))) = 3  -- E1E
    and (select count(*) from pg_policies pol  -- E1E
        where pol.schemaname = 'storage' and pol.tablename = 'objects'  -- E1E
          and (coalesce(pol.qual, '') || coalesce(pol.with_check, '')) ~ '(binder-slot-image|collection-cover)') = 12  -- E1E
    and not exists (select 1 from pg_policies pol  -- E1E
        where pol.schemaname = 'storage' and pol.tablename = 'objects'  -- E1E
          and (coalesce(pol.qual, '') || coalesce(pol.with_check, '')) ~ '(binder-slot-image|collection-cover)'  -- E1E
          and (pol.policyname not in ('binder_slot_image_select_own','binder_slot_image_insert_own','binder_slot_image_delete_own',  -- E1E
                                    'collection_cover_select_own','collection_cover_insert_own','collection_cover_update_own',  -- E1E
                                    'collection_cover_delete_own','binder_slot_image_select_shared','collection_cover_select_shared',  -- E1E
                                    'collection_cover_insert_editor','collection_cover_select_editor','collection_cover_delete_editor')  -- E1E
               or pol.permissive <> 'PERMISSIVE'  -- E1E
               or ('anon' = any(pol.roles) and pol.cmd <> 'SELECT')  -- E1E
               or 'public' = any(pol.roles)))  -- E1E
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
    'detail','conjunto fechado de 12 políticas nos dois buckets, cada uma por nome, comando, papéis e predicado: 7 do dono (pasta do próprio usuário por auth.uid(), só authenticated; UPDATE com as duas expressões), 2 de leitura compartilhada (anon e authenticated, decisão delegada), 3 do EDITOR (5377: só authenticated; inserção pelo ajudante; leitura e exclusão só do próprio envio por owner_id = auth.uid() e pelo ajudante); nenhuma política inesperada, restritiva, de escrita para anon ou para PUBLIC; ajudantes definer, sem EXECUTE para anon, presos à identidade autenticada, à participação EDITOR ativa e à barreira; a pasta do próprio titular fica só com as políticas do dono');  -- E1E
  res := res || jsonb_build_object('id','S.5','ok',
    not exists (select 1 from pg_proc q, unnest(q.proargnames, q.proargmodes) a(name, mode)
                where q.oid in (f_shr, f_pub) and a.mode in ('o','t') and a.name ~* '(_id$|slot|region_id|layout|owner)'),
    'detail','portas sem ids internos (bolso, região, fichário, dono) no retorno');

  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.collection_membership), (select count(*) from public.card),
               (select count(*) from public.collection_layout), (select count(*) from public.collection_layout_slot_image),
               (select count(*) from public.collection_layout_region_image),
               (select count(*) from storage.objects where bucket_id in ('binder-slot-image','collection-cover'))]
    into b_counts;

  begin
    -- F. Fixture -----------------------------------------------------------------------------
    select g.id into v_game from public.game g where g.code = 'POKEMON';
    select l.id into v_pt from public.language l where l.code = 'pt-BR';
    select t.id into v_std from public.card_variant_type t where t.game_id = v_game and t.code = 'STANDARD';
    select c0.rarity_id, c0.category_id into v_rar, v_cat
    from public.card c0 join public.card_set cs0 on cs0.id = c0.card_set_id
    join public.expansion e0 on e0.id = cs0.expansion_id where e0.game_id = v_game limit 1;
    if v_game is null or v_pt is null or v_std is null or v_rar is null then
      res := res || jsonb_build_object('id','F.0','ok', false, 'detail','pré-requisitos de catálogo ausentes');
      raise exception 'MS863' using errcode = 'P0001';
    end if;
    insert into public.expansion (game_id, code, name, release_order)
    values (v_game, 'SHV_' || upper(v_sfx), 'SHV Harness ' || v_sfx,
            (select coalesce(max(x.release_order), 0) + 1000 from public.expansion x where x.game_id = v_game))
    returning id into v_exp;
    insert into public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_exp, 'SHV' || upper(v_sfx), 'SHV Set ' || v_sfx, 'REGULAR', 1, 3, 3) returning id into v_set;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '1', 1, 'SHV K1', true) returning id into k1;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '2', 2, 'SHV K2', true) returning id into k2;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '3', 3, 'SHV K3', true) returning id into k3;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k1, v_std, 1, true) returning id into k1s;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k2, v_std, 1, true) returning id into k2s;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k3, v_std, 1, true) returning id into k3s;

    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    select x.id, 'authenticated', 'authenticated', x.u || '@example.invalid', jsonb_build_object('username', x.u, 'display_name', 'WH 5863 ' || x.t), now(), now()
    from (values (u_a, 'wh863a_' || v_sfx, 'A'), (u_b, 'wh863b_' || v_sfx, 'B'), (u_c, 'wh863c_' || v_sfx, 'C'),
                 (u_d, 'wh863d_' || v_sfx, 'D'), (u_e, 'wh863e_' || v_sfx, 'E'), (u_f, 'wh863f_' || v_sfx, 'F')) x(id, u, t);
    select i.id into v_inv_a from public.inventory i where i.owner_user_id = u_a;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (k1s, v_pt, v_inv_a) returning id into a1;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (k2s, v_pt, v_inv_a) returning id into a2;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (k1s, v_pt, v_inv_a) returning id into x1;

    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select x.storage_container_id into v_bin from public.create_my_storage_container(gen_random_uuid(), 'BIN 5863', 'BINDER') x;
    select x.collection_id into v_co from public.create_my_card_set_collection(gen_random_uuid(), v_set, 'CO 5863', v_bin) x;
    select x.collection_id into v_cx from public.create_my_free_collection(gen_random_uuid(), 'CX 5863', v_bin) x;
    perform public.allocate_physical_cards_to_collection(v_co, array[a1, a2]);
    perform public.allocate_physical_cards_to_collection(v_cx, array[x1]);
    select * into p from public.preview_my_collection_binder(v_co, 3, 3, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_co, 3, 3, 'PRINCIPAL_ONLY', p.plan_token);
    execute 'reset role';
    select l.id into v_layout from public.collection_layout l where l.collection_id = v_co;
    execute 'set local role authenticated';
    perform public.attach_my_collection_to_binder(v_cx, v_layout);
    m_b  := (public.invite_collection_member(v_co, 'wh863b_' || v_sfx) ->> 'membership_id')::uuid;
    m_c  := (public.invite_collection_member(v_co, 'wh863c_' || v_sfx) ->> 'membership_id')::uuid;
    m_d  := (public.invite_collection_member(v_co, 'wh863d_' || v_sfx) ->> 'membership_id')::uuid;
    m_f  := (public.invite_collection_member(v_co, 'wh863f_' || v_sfx) ->> 'membership_id')::uuid;
    m_bx := (public.invite_collection_member(v_cx, 'wh863b_' || v_sfx) ->> 'membership_id')::uuid;
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.respond_collection_invite(m_b, true);
    perform public.respond_collection_invite(m_bx, true);
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', u_d::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_d, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.respond_collection_invite(m_d, false);
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', u_f::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_f, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.respond_collection_invite(m_f, true);
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.remove_collection_member(v_co, m_f);
    execute 'reset role';

    -- Personalizações (privilegiado; gatilhos de integridade 5232/5239 continuam valendo).
    select pg.id into v_page from public.collection_layout_page pg where pg.layout_id = v_layout and pg.page_number = 1;
    select s1.row_index, s1.column_index into v_reg_row, v_reg_col
    from public.collection_layout_slot s1
    join public.collection_layout_slot s2 on s2.page_id = s1.page_id and s2.row_index = s1.row_index and s2.column_index = s1.column_index + 1
    where s1.page_id = v_page
      and not exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id in (s1.id, s2.id))
      and not exists (select 1 from public.collection_layout_slot_expected_content e where e.slot_id in (s1.id, s2.id))
      and not s1.locked and not s2.locked
    order by s1.row_index desc, s1.column_index limit 1;
    insert into public.collection_layout_region (page_id, top_row, left_column, height, width)
    values (v_page, v_reg_row, v_reg_col, 1, 2) returning id into v_region;
    p_reg   := u_a || '/' || v_layout || '/' || gen_random_uuid() || '.webp';
    insert into public.collection_layout_region_image (region_id, owner_user_id, storage_path, focal_x, focal_y)
    values (v_region, u_a, p_reg, 30, 70);
    select s.id, s.row_index, s.column_index into v_slot, v_slot_row, v_slot_col
    from public.collection_layout_slot s
    where s.page_id = v_page and not s.locked
      and not (s.row_index = v_reg_row and s.column_index between v_reg_col and v_reg_col + 1)
      and not exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = s.id)
      and not exists (select 1 from public.collection_layout_slot_expected_content e where e.slot_id = s.id)
    order by s.row_index desc, s.column_index desc limit 1;
    p_slot  := u_a || '/' || v_layout || '/' || gen_random_uuid() || '.webp';
    insert into public.collection_layout_slot_image (slot_id, owner_user_id, storage_path, focal_y)
    values (v_slot, u_a, p_slot, 20);
    p_loose := u_a || '/' || v_layout || '/' || gen_random_uuid() || '.webp';
    p_cover := u_a || '/' || v_cx || '/' || gen_random_uuid() || '.webp';
    p_old   := u_a || '/' || v_cx || '/' || gen_random_uuid() || '.webp';
    update public.collection set cover_logo_path = p_cover, cover_code = 'WH863' where id = v_cx;
    -- Objetos de Storage da fixture (só linhas; desfeitas pela sentinela).
    insert into storage.objects (bucket_id, name, metadata) values
      ('binder-slot-image', p_slot,  '{"mimetype":"image/webp"}'),
      ('binder-slot-image', p_reg,   '{"mimetype":"image/webp"}'),
      ('binder-slot-image', p_loose, '{"mimetype":"image/webp"}'),
      ('collection-cover',  p_cover, '{"mimetype":"image/webp"}'),
      ('collection-cover',  p_old,   '{"mimetype":"image/webp"}');

    res := res || jsonb_build_object('id','F.1','ok',
      v_co is not null and v_cx is not null and v_layout is not null and v_region is not null and v_slot is not null
      and exists (select 1 from public.collection_layout_guest g where g.layout_id = v_layout and g.collection_id = v_cx)
      and (select m.status from public.collection_membership m where m.id = m_b) = 'ACTIVE'
      and (select m.status from public.collection_membership m where m.id = m_bx) = 'ACTIVE'
      and (select m.status from public.collection_membership m where m.id = m_c) = 'PENDING'
      and (select m.status from public.collection_membership m where m.id = m_d) = 'DECLINED'
      and not exists (select 1 from public.collection_membership m where m.id = m_f),
      'detail','CO dona com imagem de bolso (' || v_slot_row || ',' || v_slot_col || ') e mesclagem (' || v_reg_row || ',' || v_reg_col || ' 1×2); CX convidada com capa; B ativo em CO e CX; C pendente; D recusado; F removido');

    -- I. Porta do participante (5326) --------------------------------------------------------
    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select string_agg(x.page_number || ':' || x.row_index || ':' || x.column_index || ':' || x.height || 'x' || x.width || ':' || x.is_region || ':' || x.focal_x || '/' || x.focal_y, ',' order by x.row_index, x.column_index),
           count(*) filter (where x.storage_path in (p_slot, p_reg))
      into v_txt, n
      from public.get_shared_collection_binder_images(v_co, 1, 4) x;
    res := res || jsonb_build_object('id','I.1','ok', n = 2
      and v_txt like '%1:' || v_slot_row || ':' || v_slot_col || ':1x1:false:50/20%'
      and v_txt like '%1:' || v_reg_row || ':' || v_reg_col || ':1x2:true:30/70%',
      'detail','VIEWER em CO (dona): ' || coalesce(v_txt, '(vazio)') || ' — bolso e mesclagem com posição, recorte e enquadramento');
    select count(*) into n from public.get_shared_collection_binder_images(v_cx, 1, 4);
    res := res || jsonb_build_object('id','I.2','ok', n = 0, 'detail','VIEWER em CX (convidada do mesmo fichário): ' || n || ' imagens — sem propriedade determinável, nada atravessa');
    select count(*) into n from public.get_shared_collection_binder_images(v_co, 2, 4);
    v_err := null; begin perform count(*) from public.get_shared_collection_binder_images(v_co, 1, 5); exception when others then v_err := sqlstate || ' ' || sqlerrm; end;
    res := res || jsonb_build_object('id','I.3','ok', n = 0 and v_err like '22023%INVALID_PAGE%', 'detail','páginas fora do intervalo → 0; lote de 5 → ' || coalesce(v_err, 'aceitou'));
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select count(*) into n from public.get_shared_collection_binder_images(v_co, 1, 4);
    select count(*) into n2 from public.get_shared_collection_binder_images(v_cx, 1, 4);
    execute 'reset role';
    res := res || jsonb_build_object('id','I.4','ok', n = 2 and n2 = 0, 'detail','titular pela mesma porta: CO ' || n || ', CX ' || n2 || ' (mesma regra; o titular segue usando 5234/5241 no próprio fichário)');

    -- ST. Decisão de Storage no papel do VIEWER (5329) -----------------------------------------
    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    res := res || jsonb_build_object('id','ST.1','ok',
      public.shared_visual_asset_readable('binder-slot-image', p_slot) and public.shared_visual_asset_readable('binder-slot-image', p_reg),
      'detail','VIEWER lê imagem de bolso e de mesclagem vinculadas ao fichário da coleção autorizada');
    res := res || jsonb_build_object('id','ST.2','ok',
      not public.shared_visual_asset_readable('binder-slot-image', p_loose)
      and not public.shared_visual_asset_readable('binder-slot-image', u_a || '/' || gen_random_uuid() || '/' || gen_random_uuid() || '.webp')
      and not public.shared_visual_asset_readable('binder-slot-image', 'qualquer/coisa.webp'),
      'detail','arquivo solto na pasta do fichário, caminho inexistente e lixo → negados');
    res := res || jsonb_build_object('id','ST.3','ok',
      not public.shared_visual_asset_readable('collection-cover', p_slot)
      and not public.shared_visual_asset_readable('binder-slot-image', p_cover)
      and not public.shared_visual_asset_readable('card-set-logo', p_slot),
      'detail','bucket trocado → negado (decisão por bucket)');
    res := res || jsonb_build_object('id','ST.4','ok',
      public.shared_visual_asset_readable('collection-cover', p_cover)
      and not public.shared_visual_asset_readable('collection-cover', p_old),
      'detail','capa atual da coleção autorizada (CX) liberada; outra capa da mesma pasta (não atual) negada');

    -- SO. RLS real de storage.objects no papel do VIEWER --------------------------------------
    select string_agg(o.name, ',' order by o.name) into v_names
    from storage.objects o
    where o.bucket_id in ('binder-slot-image','collection-cover') and o.name like u_a || '/%';
    res := res || jsonb_build_object('id','SO.1','ok',
      v_names = (select string_agg(x, ',' order by x) from unnest(array[p_slot, p_reg, p_cover]) x),
      'detail','VIEWER lista/lê na pasta da titular exatamente bolso + mesclagem + capa atual (3); solto e capa antiga invisíveis');
    begin
      update storage.objects set metadata = '{"x":1}' where bucket_id = 'binder-slot-image' and name in (p_slot, p_reg);
      get diagnostics n = row_count;
      perform set_config('storage.allow_delete_query', 'true', true);
      delete from storage.objects where bucket_id in ('binder-slot-image','collection-cover') and name like u_a || '/%';
      get diagnostics n2 = row_count;
      perform set_config('storage.allow_delete_query', 'false', true);
      v_err := null;
      begin
        insert into storage.objects (bucket_id, name) values ('binder-slot-image', u_a || '/' || v_layout || '/' || gen_random_uuid() || '.webp');
      exception when others then v_err := sqlstate;
      end;
    end;
    res := res || jsonb_build_object('id','SO.3','ok', n = 0 and n2 = 0 and v_err = '42501',
      'detail','VIEWER: UPDATE ' || n || ' linhas, DELETE ' || n2 || ' linhas (trava de exclusão desligada para provar a RLS), INSERT na pasta da titular = ' || coalesce(v_err, 'aceito'));

    -- C. Capa (5328) -----------------------------------------------------------------------------
    select count(*) filter (where x.cover_logo_path = p_cover and x.cover_code = 'WH863') into n from public.get_shared_collection_cover(v_cx) x;
    select count(*) into n2 from public.get_shared_collection_cover(v_co) x;
    execute 'reset role';
    res := res || jsonb_build_object('id','C.1','ok', n = 1 and n2 = 1, 'detail','VIEWER: capa e código da CX (' || n || '); CO responde a própria linha (' || n2 || ')');
    perform set_config('request.jwt.claim.sub', u_e::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_e, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select count(*) into n from public.get_shared_collection_cover(v_cx);
    b1 := public.shared_visual_asset_readable('collection-cover', p_cover);
    execute 'reset role';
    res := res || jsonb_build_object('id','C.2','ok', n = 0 and not b1, 'detail','estranho: capa 0 linhas e arquivo negado');
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    select count(*) into n from public.get_shared_collection_cover(v_cx);
    b1 := public.shared_visual_asset_readable('collection-cover', p_cover);
    b2 := public.shared_visual_asset_readable('binder-slot-image', p_slot);
    execute 'reset role';
    res := res || jsonb_build_object('id','C.3','ok', n = 0 and not b1 and not b2, 'detail','anon com coleções privadas: capa 0 linhas, capa e imagem negadas');
    perform set_config('request.jwt.claim.sub', u_e::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_e, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select count(*) into n from storage.objects o where o.bucket_id in ('binder-slot-image','collection-cover') and o.name like u_a || '/%';
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    select count(*) into n2 from storage.objects o where o.bucket_id in ('binder-slot-image','collection-cover') and o.name like u_a || '/%';
    execute 'reset role';
    res := res || jsonb_build_object('id','SO.2','ok', n = 0 and n2 = 0, 'detail','estranho lista ' || n || ' e anon lista ' || n2 || ' objetos na pasta da titular (coleções privadas)');

    -- N. Negação ----------------------------------------------------------------------------------
    for p in select * from (values ('C pendente', u_c), ('D recusado', u_d), ('E estranho', u_e), ('F removido', u_f)) v(label, uid) loop
      perform set_config('request.jwt.claim.sub', p.uid::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', p.uid, 'role', 'authenticated')::text, true);
      execute 'set local role authenticated';
      v_err := null; begin perform count(*) from public.get_shared_collection_binder_images(v_co, 1, 4); exception when others then v_err := sqlstate; end;
      b1 := public.shared_visual_asset_readable('binder-slot-image', p_slot);
      b2 := public.shared_visual_asset_readable('binder-slot-image', p_reg);
      execute 'reset role';
      res := res || jsonb_build_object('id','N.' || p.label,'ok', v_err = 'P0002' and not b1 and not b2,
        'detail', p.label || ': 5326 = ' || coalesce(v_err, 'executou') || '; Storage bolso/mesclagem = ' || b1 || '/' || b2);
    end loop;
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    v_err := null; begin perform count(*) from public.get_shared_collection_binder_images(v_co, 1, 4); exception when others then v_err := sqlstate; end;
    res := res || jsonb_build_object('id','N.anon 5326','ok', v_err = '42501', 'detail', coalesce(v_err, 'executou'));
    v_err := null; begin perform count(*) from public.get_public_collection_binder_images(v_co, 1, 4); exception when others then v_err := sqlstate; end;
    res := res || jsonb_build_object('id','N.anon 5327 privada','ok', v_err = 'P0002', 'detail', coalesce(v_err, 'executou'));
    v_err := null; begin perform count(*) from public.collection_binder_shared_images(v_co, 1, 4); exception when others then v_err := sqlstate; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','N.anon núcleo','ok', v_err = '42501', 'detail','5325 interna: ' || coalesce(v_err, 'executou'));
    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    v_err := null; begin perform count(*) from public.collection_binder_shared_images(v_co, 1, 4); exception when others then v_err := sqlstate; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','N.auth núcleo','ok', v_err = '42501', 'detail','5325 interna para authenticated: ' || coalesce(v_err, 'executou'));

    -- PB. Vitrine pública ---------------------------------------------------------------------------
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.set_collection_visibility(v_co, 'PUBLIC');
    perform public.set_collection_visibility(v_cx, 'PUBLIC');
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    select count(*) into n from public.get_public_collection_binder_images(v_co, 1, 4) x where x.storage_path in (p_slot, p_reg);
    b1 := public.shared_visual_asset_readable('binder-slot-image', p_slot);
    b2 := public.shared_visual_asset_readable('binder-slot-image', p_reg);
    b3 := public.shared_visual_asset_readable('binder-slot-image', p_loose);
    res := res || jsonb_build_object('id','PB.1','ok', n = 2 and b1 and b2 and not b3,
      'detail','CO pública: visitante recebe as 2 imagens e pode assiná-las; arquivo solto continua negado');
    select count(*) into n from public.get_public_collection_binder_images(v_cx, 1, 4);
    select count(*) filter (where x.cover_logo_path = p_cover) into n2 from public.get_shared_collection_cover(v_cx) x;
    b1 := public.shared_visual_asset_readable('collection-cover', p_cover);
    res := res || jsonb_build_object('id','PB.2','ok', n = 0 and n2 = 1 and b1,
      'detail','CX pública (convidada): 0 imagens do fichário alheio; capa própria liberada');
    select string_agg(o.name, ',' order by o.name) into v_names
    from storage.objects o
    where o.bucket_id in ('binder-slot-image','collection-cover') and o.name like u_a || '/%';
    res := res || jsonb_build_object('id','SO.4','ok',
      v_names = (select string_agg(x, ',' order by x) from unnest(array[p_slot, p_reg, p_cover]) x),
      'detail','visitante (CO e CX públicas) lista exatamente bolso + mesclagem + capa atual; solto e capa antiga invisíveis');
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.set_collection_visibility(v_co, 'PRIVATE');
    perform public.set_collection_visibility(v_cx, 'PRIVATE');
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    v_err := null; begin perform count(*) from public.get_public_collection_binder_images(v_co, 1, 4); exception when others then v_err := sqlstate; end;
    b1 := public.shared_visual_asset_readable('binder-slot-image', p_slot);
    b2 := public.shared_visual_asset_readable('collection-cover', p_cover);
    execute 'reset role';
    res := res || jsonb_build_object('id','PB.3','ok', v_err = 'P0002' and not b1 and not b2,
      'detail','despublicar: 5327 = ' || coalesce(v_err, 'executou') || '; novas assinaturas negadas na hora');

    -- PB.4 troca de capa: a antiga deixa de ser legível --------------------------------------------
    update public.collection set cover_logo_path = p_old where id = v_cx;
    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    b1 := public.shared_visual_asset_readable('collection-cover', p_cover);
    b2 := public.shared_visual_asset_readable('collection-cover', p_old);
    execute 'reset role';
    res := res || jsonb_build_object('id','PB.4','ok', not b1 and b2, 'detail','capa trocada: arquivo anterior negado, novo liberado ao VIEWER');

    -- R. Revogação ------------------------------------------------------------------------------------
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.remove_collection_member(v_co, m_b);
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    v_err := null; begin perform count(*) from public.get_shared_collection_binder_images(v_co, 1, 4); exception when others then v_err := sqlstate; end;
    b1 := public.shared_visual_asset_readable('binder-slot-image', p_slot);
    b2 := public.shared_visual_asset_readable('binder-slot-image', p_reg);
    select count(*) into n from public.get_shared_collection_binder_images(v_cx, 1, 4);
    b3 := public.shared_visual_asset_readable('collection-cover', p_old);
    execute 'reset role';
    res := res || jsonb_build_object('id','R.1','ok', v_err = 'P0002' and not b1 and not b2,
      'detail','B removido de CO: 5326 = ' || coalesce(v_err, 'executou') || '; Storage bolso/mesclagem negados na mesma transação');
    res := res || jsonb_build_object('id','R.2','ok', n = 0 and b3,
      'detail','B segue VIEWER de CX (convidada do MESMO fichário): continua sem imagens do fichário (' || n || ') e mantém só a capa da CX');

    -- RM. Imagem retirada do layout -------------------------------------------------------------
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.set_collection_visibility(v_co, 'PUBLIC');
    execute 'reset role';
    delete from public.collection_layout_region_image where region_id = v_region;
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    b1 := public.shared_visual_asset_readable('binder-slot-image', p_reg);
    b2 := public.shared_visual_asset_readable('binder-slot-image', p_slot);
    select count(*) into n from storage.objects o where o.bucket_id = 'binder-slot-image' and o.name = p_reg;
    select count(*) into n2 from public.get_public_collection_binder_images(v_co, 1, 4);
    execute 'reset role';
    res := res || jsonb_build_object('id','RM.1','ok', not b1 and b2 and n = 0 and n2 = 1,
      'detail','mesclagem retirada (CO pública): arquivo dela negado e invisível; imagem de bolso restante segue liberada; 5327 = ' || n2 || ' imagem');

    raise exception 'MS863' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MS863' then
      res := res || jsonb_build_object('id','X.1','ok', false, 'detail','erro inesperado: ' || sqlstate || ' ' || sqlerrm);
    end if;
  end;

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.collection_membership), (select count(*) from public.card),
               (select count(*) from public.collection_layout), (select count(*) from public.collection_layout_slot_image),
               (select count(*) from public.collection_layout_region_image),
               (select count(*) from storage.objects where bucket_id in ('binder-slot-image','collection-cover'))]
    into e_counts;
  res := res || jsonb_build_object('id','99.1','ok', b_counts = e_counts and current_user = session_user,
    'detail','resíduo zero (10 contagens) e papel restaurado');

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
  select '5863', seq, check_id, status, detail from pg_temp.wh_5863_validate();

-- @@T8 modo da barreira OPEN (só nesta transação)
update public.v1_13_barrier_state set mode = 'OPEN', change_note = 'G2 ensaio' where id = 1;

-- @@T8 harness 5890 [OPEN] sha256=0cb84f973d22995b25988cbc5be5540df2799ee1e5de0832158bd8bef0775aba
create or replace function pg_temp.wh_5890_as(p_user uuid)
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

create or replace function pg_temp.wh_5890_slot(p_layout uuid, p_row integer, p_col integer)
returns uuid language sql stable as $sl$
  select s.id from public.collection_layout_slot s
  join public.collection_layout_page p on p.id = s.page_id
  where p.layout_id = p_layout and p.page_number = 1 and s.row_index = p_row and s.column_index = p_col;
$sl$;

create or replace function pg_temp.wh_5890_res(p_layout uuid, p_row integer, p_col integer)
returns text language sql stable as $rs$
  -- reserva do bolso: "<card_id>:<collection_id>" ou NULL
  select e.card_id::text || ':' || coalesce(e.collection_id::text, '-')
  from public.collection_layout_slot_expected_content e
  where e.slot_id = pg_temp.wh_5890_slot(p_layout, p_row, p_col);
$rs$;

create or replace function pg_temp.wh_5890_locked(p_layout uuid, p_row integer, p_col integer)
returns boolean language sql stable as $lk$
  select s.locked from public.collection_layout_slot s where s.id = pg_temp.wh_5890_slot(p_layout, p_row, p_col);
$lk$;

create or replace function pg_temp.wh_5890_try(p_sql text)
returns text language plpgsql volatile as $try$
begin
  execute p_sql;
  return 'OK';
exception when others then
  return sqlerrm;
end;
$try$;

create or replace function pg_temp.wh_5890_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  f_res oid := to_regprocedure('public.editor_set_binder_reservation(uuid, integer, integer, integer, uuid, uuid, uuid)');
  f_clr oid := to_regprocedure('public.editor_clear_binder_reservation(uuid, integer, integer, integer)');
  f_lck oid := to_regprocedure('public.editor_set_binder_lock(uuid, integer, integer, integer, boolean)');
  f_ace oid := to_regprocedure('public.assert_collection_editor(uuid)');
  f_md  oid := to_regprocedure('public.editor_update_collection_metadata(uuid, text, text)');
  f_fin oid := to_regprocedure('public.editor_set_collection_cover_finish(uuid, text)');
  f_cod oid := to_regprocedure('public.editor_set_collection_cover_code(uuid, text)');
  f_logo oid := to_regprocedure('public.editor_set_collection_cover_logo(uuid, text)');
  f_fok oid := to_regprocedure('public.collection_cover_editor_folder_ok(text)');
  f_upl oid := to_regprocedure('public.collection_cover_editor_can_upload(text)');
  u_a uuid := gen_random_uuid(); u_b uuid := gen_random_uuid(); u_v uuid := gen_random_uuid();
  u_e uuid := gen_random_uuid(); u_r uuid := gen_random_uuid(); u_c uuid := gen_random_uuid();
  v_sfx text := lower(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  v_game uuid; v_pt uuid; v_rar uuid; v_cat uuid; v_std uuid; v_exp uuid; v_set uuid;
  k1 uuid; k1s uuid; k2 uuid; k2s uuid; k3 uuid; k3s uuid;
  v_inv_a uuid; a1 uuid; x1 uuid; v_ids uuid[];
  v_bin uuid; v_co uuid; v_cx uuid; v_layout uuid; v_lc uuid;
  m_b uuid; m_v uuid; m_e uuid; m_r uuid;
  p record; v_err text; v_ok boolean; n integer;
  f1 text; f2 text; f3 text; f4 text; fa text; fx text;
  alloc0 text; stor0 text;
  b_counts bigint[]; e_counts bigint[];
  res jsonb := '[]'::jsonb; r jsonb; cnt integer := 0; passes integer := 0;
  v_expected integer := 0;
begin
  -- 0. Estrutura ---------------------------------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    (select bool_and(q.prosecdef and q.proconfig @> array['search_path=""']
                     and has_function_privilege('authenticated', q.oid, 'EXECUTE')
                     and not has_function_privilege('anon', q.oid, 'EXECUTE'))
       from pg_proc q where q.oid in (f_res, f_clr, f_lck, f_md, f_fin, f_cod, f_logo))
    and (select count(*) from pg_proc q where q.oid in (f_res, f_clr, f_lck, f_md, f_fin, f_cod, f_logo)) = 7,
    'detail','7 RPCs do EDITOR: definer, search_path vazio, só authenticated');
  res := res || jsonb_build_object('id','0.2','ok',
    f_ace is not null and not has_function_privilege('authenticated', f_ace, 'EXECUTE')
    and not has_function_privilege('service_role', f_ace, 'EXECUTE')
    and f_fok is not null and has_function_privilege('authenticated', f_fok, 'EXECUTE')
    and not has_function_privilege('anon', f_fok, 'EXECUTE')
    and f_upl is not null and has_function_privilege('authenticated', f_upl, 'EXECUTE')
    and not has_function_privilege('anon', f_upl, 'EXECUTE')
    and to_regprocedure('public.collection_cover_editor_folder_ok(text, boolean)') is null,
    'detail','assert_collection_editor interna; os dois ajudantes das políticas só para authenticated');
  res := res || jsonb_build_object('id','0.3','ok',
    (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.set_slot_expected_content(uuid, uuid, uuid, uuid, uuid)')) = '33dde5013dbb491bd4a0452ab7ce8132'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.clear_slot_expected_content(uuid[])')) = '0b8f26825ff713a24226548ffe3a63b7'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.set_slot_lock(uuid[], boolean)')) = '651048a4bf7d3229904ef2a073c509c5'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.update_collection_metadata(uuid, text, text)')) = 'a581235db9cabaf7043707a290f963b7'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.set_my_collection_cover_finish(uuid, text)')) = '4f48d9161b4a29ecb23e7443e31d1806'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.set_my_collection_cover_code(uuid, text)')) = 'd0d8cbfa517b9da3728a55af47de21cb'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.set_my_collection_cover_logo(uuid, text)')) = '5868fb1c8de760787d1128ac20a09507'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.assert_collection_layout_mutable(uuid)')) = 'd600f36fade0b67c0fd5af33e9965070',
    'detail','titular: 5276–5278, 5035, 5172, 5178, 5180 e 5122 byte a byte canônicas');
  res := res || jsonb_build_object('id','0.4','ok',
    (select count(*) from pg_policies pp where pp.schemaname = 'storage' and pp.tablename = 'objects'
      and pp.policyname in ('collection_cover_insert_editor', 'collection_cover_select_editor', 'collection_cover_delete_editor')
      and pp.roles = array['authenticated']::name[]) = 3
    and not exists (select 1 from pg_policies pp where pp.schemaname = 'storage' and pp.tablename = 'objects'
                    and pp.policyname like 'collection_cover_%_editor' and pp.cmd = 'UPDATE')
    and (select count(*) from pg_policies pp where pp.schemaname = 'storage' and pp.tablename = 'objects'
          and pp.policyname like 'collection_cover_%_own') = 4,
    'detail','Storage: 3 políticas do EDITOR só para authenticated, nenhuma de UPDATE; as 4 do dono intactas');
  res := res || jsonb_build_object('id','0.5','ok',
    (select q.provolatile from pg_proc q where q.oid = f_upl) = 'v'
    and (select q.provolatile from pg_proc q where q.oid = f_fok) = 's'
    and position('pg_advisory_xact_lock' in (select q.prosrc from pg_proc q where q.oid = f_upl))
        between 1 and position('count(*)' in (select q.prosrc from pg_proc q where q.oid = f_upl))
    and (select pp.with_check from pg_policies pp where pp.schemaname = 'storage' and pp.tablename = 'objects'
          and pp.policyname = 'collection_cover_insert_editor') like '%collection_cover_editor_can_upload(name)%'
    and (select string_agg(pp.qual, '|' order by pp.policyname) from pg_policies pp where pp.schemaname = 'storage'
          and pp.tablename = 'objects' and pp.policyname in ('collection_cover_select_editor', 'collection_cover_delete_editor'))
        ~ '^[^|]*collection_cover_editor_folder_ok\(name\)[^|]*\|[^|]*collection_cover_editor_folder_ok\(name\)[^|]*$',
    'detail','envio por ajudante VOLÁTIL com trava (EDITOR, coleção) antes da contagem; ver/apagar pelo ajudante STABLE (prova estrutural, não de corrida)');

  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.collection_membership), (select count(*) from public.collection_layout_slot_expected_content),
               (select count(*) from public.binder_activity_event), (select count(*) from storage.objects)]
    into b_counts;

  begin
    -- F. Fixture ---------------------------------------------------------------------------
    select g.id into v_game from public.game g where g.code = 'POKEMON';
    select l.id into v_pt from public.language l where l.code = 'pt-BR';
    select t.id into v_std from public.card_variant_type t where t.game_id = v_game and t.code = 'STANDARD';
    select c0.rarity_id, c0.category_id into v_rar, v_cat
    from public.card c0 join public.card_set cs0 on cs0.id = c0.card_set_id
    join public.expansion e0 on e0.id = cs0.expansion_id where e0.game_id = v_game limit 1;
    if v_game is null or v_pt is null or v_std is null or v_rar is null then
      res := res || jsonb_build_object('id','F.1','ok', false, 'detail','pré-requisitos de catálogo ausentes');
      raise exception 'MS890' using errcode = 'P0001';
    end if;
    insert into public.expansion (game_id, code, name, release_order)
    values (v_game, 'EB2_' || upper(v_sfx), 'EB2 Harness ' || v_sfx,
            (select coalesce(max(x.release_order), 0) + 1000 from public.expansion x where x.game_id = v_game))
    returning id into v_exp;
    insert into public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_exp, 'EB2' || upper(v_sfx), 'EB2 Set ' || v_sfx, 'REGULAR', 1, 3, 3) returning id into v_set;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '1', 1, 'EB2 K1', true) returning id into k1;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '2', 2, 'EB2 K2', true) returning id into k2;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '3', 3, 'EB2 K3', true) returning id into k3;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k1, v_std, 1, true) returning id into k1s;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k2, v_std, 1, true) returning id into k2s;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k3, v_std, 1, true) returning id into k3s;

    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    select u.id, 'authenticated', 'authenticated', 'wh890' || u.t || '_' || v_sfx || '@example.invalid',
           jsonb_build_object('username', 'wh890' || u.t || '_' || v_sfx, 'display_name', 'WH 5890 ' || upper(u.t)), now(), now()
    from (values (u_a, 'a'), (u_b, 'b'), (u_v, 'v'), (u_e, 'e'), (u_r, 'r'), (u_c, 'c')) u(id, t);
    select i.id into v_inv_a from public.inventory i where i.owner_user_id = u_a;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, created_at)
    select v.cv, v_pt, v_inv_a, now() - (v.o || ' min')::interval from (values (k1s, 2), (k3s, 1)) v(cv, o);
    select array_agg(pc.id order by pc.created_at) into v_ids from public.physical_card pc where pc.inventory_id = v_inv_a;
    a1 := v_ids[1]; x1 := v_ids[2];

    perform pg_temp.wh_5890_as(u_a);
    select x.storage_container_id into v_bin from public.create_my_storage_container(gen_random_uuid(), 'BIN 5890', 'BINDER') x;
    select x.collection_id into v_co from public.create_my_free_collection(gen_random_uuid(), 'CO 5890', v_bin) x;
    perform public.allocate_physical_cards_to_collection(v_co, array[a1]);
    select * into p from public.preview_my_collection_binder(v_co, 3, 3, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_co, 3, 3, 'PRINCIPAL_ONLY', p.plan_token);
    execute 'reset role';
    select l.id, l.storage_container_id into v_layout, v_lc from public.collection_layout l where l.collection_id = v_co;
    delete from public.collection_layout_slot_assignment a using public.collection_layout_slot s, public.collection_layout_page p2
     where a.slot_id = s.id and s.page_id = p2.id and p2.layout_id = v_layout;
    delete from public.collection_layout_slot_expected_content e using public.collection_layout_slot s, public.collection_layout_page p2
     where e.slot_id = s.id and s.page_id = p2.id and p2.layout_id = v_layout;
    update public.physical_card pc set storage_container_id = v_lc where pc.id in (a1, x1);
    perform pg_temp.wh_5890_as(u_a);
    select x.collection_id into v_cx from public.create_my_free_collection(gen_random_uuid(), 'CX 5890', v_lc) x;
    perform public.allocate_physical_cards_to_collection(v_cx, array[x1]);
    perform public.attach_my_collection_to_binder(v_cx, v_layout);
    perform public.place_my_physical_card_in_slot(v_co, pg_temp.wh_5890_slot(v_layout, 1, 1), a1);
    perform public.place_my_physical_card_in_slot(v_cx, pg_temp.wh_5890_slot(v_layout, 1, 2), x1);
    perform public.set_slot_expected_content(pg_temp.wh_5890_slot(v_layout, 1, 3), k3, null, null, v_cx);
    perform public.set_slot_lock(array[pg_temp.wh_5890_slot(v_layout, 2, 2)], true);
    m_b := (public.invite_collection_member(v_co, 'wh890b_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_v := (public.invite_collection_member(v_co, 'wh890v_' || v_sfx) ->> 'membership_id')::uuid;
    m_r := (public.invite_collection_member(v_co, 'wh890r_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_e := (public.invite_collection_member(v_cx, 'wh890e_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    perform pg_temp.wh_5890_as(u_b); perform public.respond_collection_invite(m_b, true);
    perform pg_temp.wh_5890_as(u_v); perform public.respond_collection_invite(m_v, true);
    perform pg_temp.wh_5890_as(u_r); perform public.respond_collection_invite(m_r, true);
    perform pg_temp.wh_5890_as(u_e); perform public.respond_collection_invite(m_e, true);
    perform pg_temp.wh_5890_as(u_a); perform public.remove_collection_member(v_co, m_r);
    execute 'reset role';
    -- Mesclagem e imagem do titular (passo privilegiado; gatilhos 5232/5238 ativos).
    insert into public.collection_layout_region (page_id, top_row, left_column, height, width)
    values ((select p2.id from public.collection_layout_page p2 where p2.layout_id = v_layout and p2.page_number = 1), 3, 1, 1, 2);
    insert into public.collection_layout_slot_image (slot_id, owner_user_id, storage_path)
    values (pg_temp.wh_5890_slot(v_layout, 3, 3), u_a, u_a::text || '/' || v_layout::text || '/' || gen_random_uuid()::text || '.webp');  -- E1E: C1 — caminho canônico (uuid), atende aos CHECKs 5232
    select string_agg(ca.physical_card_id::text || ':' || ca.collection_id::text, ',' order by ca.physical_card_id) into alloc0
      from public.collection_allocation ca where ca.physical_card_id in (a1, x1);
    select string_agg(pc.id::text || ':' || coalesce(pc.storage_container_id::text, '-'), ',' order by pc.id) into stor0
      from public.physical_card pc where pc.id in (a1, x1);
    res := res || jsonb_build_object('id','F.2','ok',
      v_lc is not null and (select count(*) from public.collection_layout_slot s join public.collection_layout_page p2 on p2.id = s.page_id
                             where p2.layout_id = v_layout and p2.page_number = 1) = 9
      and pg_temp.wh_5890_locked(v_layout, 2, 2) and pg_temp.wh_5890_res(v_layout, 1, 3) = k3::text || ':' || v_cx::text,
      'detail','fixture: fichário 3×3, CX convidada, carta/reserva de CX, fixado vazio, mesclagem e imagem do titular');

    -- 1. Reservar --------------------------------------------------------------------------------
    perform pg_temp.wh_5890_as(u_b);
    select x.operation into v_err from public.editor_set_binder_reservation(v_co, 1, 2, 1, k1) x;
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    res := res || jsonb_build_object('id','1.1','ok', v_err = 'RESERVED' and pg_temp.wh_5890_res(v_layout, 2, 1) = k1::text || ':' || v_co::text,
      'detail','bolso livre: reserva criada e registrada para CO');
    perform pg_temp.wh_5890_as(u_b);  -- E1E: volta ao mesmo cliente
    select x.operation into v_err from public.editor_set_binder_reservation(v_co, 1, 2, 1, k1) x;
    res := res || jsonb_build_object('id','1.2','ok', v_err = 'UNCHANGED', 'detail','mesma reserva → UNCHANGED (sem evento)');
    select x.operation into v_err from public.editor_set_binder_reservation(v_co, 1, 2, 1, k2) x;
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    res := res || jsonb_build_object('id','1.3','ok', v_err = 'REPLACED' and pg_temp.wh_5890_res(v_layout, 2, 1) = k2::text || ':' || v_co::text,
      'detail','reserva de CO trocada por outra carta → REPLACED, continua de CO');
    perform pg_temp.wh_5890_as(u_b);  -- E1E: volta ao mesmo cliente
    select x.operation into v_err from public.editor_set_binder_reservation(v_co, 1, 1, 1, k1) x;
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    res := res || jsonb_build_object('id','1.4','ok', v_err = 'RESERVED' and pg_temp.wh_5890_res(v_layout, 1, 1) = k1::text || ':' || v_co::text,
      'detail','bolso com carta de CO aceita reserva da própria carta');
    perform pg_temp.wh_5890_as(u_b);  -- E1E: volta ao mesmo cliente
    v_err := pg_temp.wh_5890_try(format('select * from public.editor_set_binder_reservation(%L, 1, 1, 3, %L)', v_co, k1))
          || ';' || pg_temp.wh_5890_try(format('select * from public.editor_set_binder_reservation(%L, 1, 1, 2, %L)', v_co, k1))
          || ';' || pg_temp.wh_5890_try(format('select * from public.editor_set_binder_reservation(%L, 1, 2, 2, %L)', v_co, k1))
          || ';' || pg_temp.wh_5890_try(format('select * from public.editor_set_binder_reservation(%L, 1, 3, 1, %L)', v_co, k1))
          || ';' || pg_temp.wh_5890_try(format('select * from public.editor_set_binder_reservation(%L, 1, 3, 3, %L)', v_co, k1))
          || ';' || pg_temp.wh_5890_try(format('select * from public.editor_set_binder_reservation(%L, 9, 1, 1, %L)', v_co, k1));
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    res := res || jsonb_build_object('id','1.5','ok',
      v_err = repeat('SLOT_NOT_EDITABLE;', 5) || 'SLOT_NOT_EDITABLE'
      and pg_temp.wh_5890_res(v_layout, 1, 3) = k3::text || ':' || v_cx::text
      and pg_temp.wh_5890_res(v_layout, 2, 2) is null and pg_temp.wh_5890_res(v_layout, 3, 1) is null,
      'detail','reserva de CX, carta de CX, fixado vazio, mesclagem, imagem e posição inexistente → a MESMA recusa; nada muda');
    perform pg_temp.wh_5890_as(u_b);  -- E1E: volta ao mesmo cliente
    v_err := pg_temp.wh_5890_try(format('select * from public.editor_set_binder_reservation(%L, 1, 2, 3, %L, %L, %L)', v_co, k1, k1s, v_std));
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    res := res || jsonb_build_object('id','1.6','ok', v_err like 'EXPECTED_CONTENT_VARIANT_AND_TYPE_EXCLUSIVE%' and pg_temp.wh_5890_res(v_layout, 2, 3) is null,
      'detail','variante e acabamento ao mesmo tempo → recusa (mesma regra do titular)');
    perform pg_temp.wh_5890_as(u_b);  -- E1E: volta ao mesmo cliente
    perform pg_temp.wh_5890_as(u_v); v_err := pg_temp.wh_5890_try(format('select * from public.editor_set_binder_reservation(%L, 1, 2, 3, %L)', v_co, k1));
    perform pg_temp.wh_5890_as(u_c); v_err := v_err || ';' || pg_temp.wh_5890_try(format('select * from public.editor_set_binder_reservation(%L, 1, 2, 3, %L)', v_co, k1));
    perform pg_temp.wh_5890_as(u_r); v_err := v_err || ';' || pg_temp.wh_5890_try(format('select * from public.editor_set_binder_reservation(%L, 1, 2, 3, %L)', v_co, k1));
    perform pg_temp.wh_5890_as(u_a); v_err := v_err || ';' || pg_temp.wh_5890_try(format('select * from public.editor_set_binder_reservation(%L, 1, 2, 3, %L)', v_co, k1));
    perform pg_temp.wh_5890_as(u_e); v_err := v_err || ';' || pg_temp.wh_5890_try(format('select * from public.editor_set_binder_reservation(%L, 1, 2, 3, %L)', v_co, k1));
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    res := res || jsonb_build_object('id','1.7','ok', v_err = 'COLLECTION_NOT_FOUND;COLLECTION_NOT_FOUND;COLLECTION_NOT_FOUND;COLLECTION_NOT_FOUND;COLLECTION_NOT_FOUND'
      and pg_temp.wh_5890_res(v_layout, 2, 3) is null,
      'detail','VIEWER, estranho, ex-EDITOR, titular e EDITOR de CX em CO → COLLECTION_NOT_FOUND');
    perform pg_temp.wh_5890_as(u_e);  -- E1E: volta ao mesmo cliente
    execute 'reset role';
    res := res || jsonb_build_object('id','1.8','ok',
      (select string_agg(ca.physical_card_id::text || ':' || ca.collection_id::text, ',' order by ca.physical_card_id)
         from public.collection_allocation ca where ca.physical_card_id in (a1, x1)) = alloc0
      and (select count(*) from public.collection_allocation ca where ca.collection_id = v_co) = 1,
      'detail','reservar não aloca nada');

    -- 2. Liberar ---------------------------------------------------------------------------------
    perform pg_temp.wh_5890_as(u_b);
    select x.operation into v_err from public.editor_clear_binder_reservation(v_co, 1, 2, 1) x;
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    res := res || jsonb_build_object('id','2.1','ok', v_err = 'RELEASED' and pg_temp.wh_5890_res(v_layout, 2, 1) is null,
      'detail','reserva de CO liberada');
    perform pg_temp.wh_5890_as(u_b);  -- E1E: volta ao mesmo cliente
    select x.operation into v_err from public.editor_clear_binder_reservation(v_co, 1, 2, 1) x;
    res := res || jsonb_build_object('id','2.2','ok', v_err = 'UNCHANGED', 'detail','sem reserva → UNCHANGED (sem evento)');
    v_err := pg_temp.wh_5890_try(format('select * from public.editor_clear_binder_reservation(%L, 1, 1, 3)', v_co))
          || ';' || pg_temp.wh_5890_try(format('select * from public.editor_clear_binder_reservation(%L, 1, 2, 2)', v_co));
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    res := res || jsonb_build_object('id','2.3','ok', v_err = 'SLOT_NOT_EDITABLE;SLOT_NOT_EDITABLE'
      and pg_temp.wh_5890_res(v_layout, 1, 3) = k3::text || ':' || v_cx::text,
      'detail','liberar reserva de CX ou mexer em bolso fixado vazio → recusa; reserva de CX intacta');
    perform pg_temp.wh_5890_as(u_b);  -- E1E: volta ao mesmo cliente
    perform pg_temp.wh_5890_as(u_e);
    v_err := pg_temp.wh_5890_try(format('select * from public.editor_clear_binder_reservation(%L, 1, 1, 1)', v_cx));
    select x.operation into fx from public.editor_set_binder_reservation(v_cx, 1, 2, 3, k3) x;
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    res := res || jsonb_build_object('id','2.4','ok', v_err = 'SLOT_NOT_EDITABLE' and fx = 'RESERVED'
      and pg_temp.wh_5890_res(v_layout, 1, 1) = k1::text || ':' || v_co::text
      and pg_temp.wh_5890_res(v_layout, 2, 3) = k3::text || ':' || v_cx::text,
      'detail','EDITOR de CX não libera reserva de CO; reserva dele fica registrada para CX');
    perform pg_temp.wh_5890_as(u_e);  -- E1E: volta ao mesmo cliente

    -- 3. Fixar / soltar -------------------------------------------------------------------------
    perform pg_temp.wh_5890_as(u_b);
    select x.operation into v_err from public.editor_set_binder_lock(v_co, 1, 1, 1, true) x;
    select x.operation into fx from public.editor_set_binder_lock(v_co, 1, 1, 1, true) x;
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    res := res || jsonb_build_object('id','3.1','ok', v_err = 'LOCKED' and fx = 'UNCHANGED' and pg_temp.wh_5890_locked(v_layout, 1, 1),
      'detail','fixar bolso de CO → LOCKED; repetir → UNCHANGED');
    perform pg_temp.wh_5890_as(u_b);  -- E1E: volta ao mesmo cliente
    select x.operation into v_err from public.editor_set_binder_lock(v_co, 1, 1, 1, false) x;
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    res := res || jsonb_build_object('id','3.2','ok', v_err = 'UNLOCKED' and not pg_temp.wh_5890_locked(v_layout, 1, 1),
      'detail','soltar bolso de CO → UNLOCKED');
    perform pg_temp.wh_5890_as(u_b);  -- E1E: volta ao mesmo cliente
    v_err := pg_temp.wh_5890_try(format('select * from public.editor_set_binder_lock(%L, 1, 2, 1, true)', v_co))
          || ';' || pg_temp.wh_5890_try(format('select * from public.editor_set_binder_lock(%L, 1, 2, 2, false)', v_co))
          || ';' || pg_temp.wh_5890_try(format('select * from public.editor_set_binder_lock(%L, 1, 1, 2, true)', v_co))
          || ';' || pg_temp.wh_5890_try(format('select * from public.editor_set_binder_lock(%L, 1, 2, 3, true)', v_co))
          || ';' || pg_temp.wh_5890_try(format('select * from public.editor_set_binder_lock(%L, 1, 3, 1, true)', v_co));
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    res := res || jsonb_build_object('id','3.3','ok', v_err = repeat('SLOT_NOT_EDITABLE;', 4) || 'SLOT_NOT_EDITABLE'
      and not pg_temp.wh_5890_locked(v_layout, 2, 1) and pg_temp.wh_5890_locked(v_layout, 2, 2)
      and not pg_temp.wh_5890_locked(v_layout, 1, 2) and not pg_temp.wh_5890_locked(v_layout, 2, 3),
      'detail','fixar livre, soltar fixado vazio do titular, fixar carta/reserva de CX e mesclagem → a MESMA recusa; travas intactas');
    perform pg_temp.wh_5890_as(u_b);  -- E1E: volta ao mesmo cliente
    perform pg_temp.wh_5890_as(u_e);
    select x.operation into v_err from public.editor_set_binder_lock(v_cx, 1, 1, 2, true) x;
    select x.operation into fx from public.editor_set_binder_lock(v_cx, 1, 1, 2, false) x;
    res := res || jsonb_build_object('id','3.4','ok', v_err = 'LOCKED' and fx = 'UNLOCKED',
      'detail','EDITOR de CX fixa e solta o bolso com carta de CX');

    -- 4. Metadados ------------------------------------------------------------------------------
    perform pg_temp.wh_5890_as(u_b);
    select x.name || '|' || coalesce(x.description, '') into v_err from public.editor_update_collection_metadata(v_co, '  Nova CO 5890  ', 'descrição B') x;
    res := res || jsonb_build_object('id','4.1','ok', v_err = 'Nova CO 5890|descrição B',
      'detail','EDITOR altera nome (sem brancos nas pontas) e descrição');
    v_err := pg_temp.wh_5890_try(format('select * from public.editor_update_collection_metadata(%L, %L, null)', v_co, '   '));
    res := res || jsonb_build_object('id','4.2','ok', v_err like 'p_name não pode ser vazio%', 'detail','nome vazio recusado');
    v_err := pg_temp.wh_5890_try(format('select * from public.update_collection_metadata(%L, %L, null)', v_co, 'X'))
          || ';' || pg_temp.wh_5890_try(format('select public.set_collection_visibility(%L, %L)', v_co, 'PUBLIC'))
          || ';' || pg_temp.wh_5890_try(format('select public.archive_collection(%L)', v_co))
          || ';' || pg_temp.wh_5890_try(format('select * from public.set_my_collection_cover_finish(%L, %L)', v_co, 'vinho'));
    execute 'reset role';
    res := res || jsonb_build_object('id','4.3','ok', v_err !~ '(^|;)OK(;|$)'
      and (select c.name || ':' || c.visibility || ':' || c.lifecycle_status from public.collection c where c.id = v_co) = 'Nova CO 5890:PRIVATE:ACTIVE',
      'detail','caminhos do titular (metadados, visibilidade, arquivar, capa) recusam o EDITOR: ' || v_err);
    res := res || jsonb_build_object('id','4.4','ok',
      not exists (select 1 from pg_proc q, unnest(q.proargnames) a(name)
                  where q.oid in (f_md, f_fin, f_cod, f_logo)
                    and a.name ~ '(visib|policy|reference|card_set|scope|finish_scope|archive|member|owner|mode)'),
      'detail','RPCs de metadados sem parâmetro para Set, escopo, política, modalidade, visibilidade, arquivamento, membros ou titular');
    perform pg_temp.wh_5890_as(u_v);
    v_err := pg_temp.wh_5890_try(format('select * from public.editor_update_collection_metadata(%L, %L, null)', v_co, 'V'));
    perform pg_temp.wh_5890_as(u_c);
    v_err := v_err || ';' || pg_temp.wh_5890_try(format('select * from public.editor_update_collection_metadata(%L, %L, null)', v_co, 'C'));
    perform pg_temp.wh_5890_as(u_e);
    v_err := v_err || ';' || pg_temp.wh_5890_try(format('select * from public.editor_update_collection_metadata(%L, %L, null)', v_co, 'E'));
    perform pg_temp.wh_5890_as(null);
    v_err := v_err || ';' || pg_temp.wh_5890_try(format('select * from public.editor_update_collection_metadata(%L, %L, null)', v_co, 'anon'));
    execute 'reset role';
    res := res || jsonb_build_object('id','4.5','ok', v_err ~ '^COLLECTION_NOT_FOUND;COLLECTION_NOT_FOUND;COLLECTION_NOT_FOUND;permission denied'
      and (select c.name from public.collection c where c.id = v_co) = 'Nova CO 5890',
      'detail','VIEWER, estranho, EDITOR de outra coleção e anon não alteram metadados');

    -- 5. Capa (acabamento e código) --------------------------------------------------------------
    perform pg_temp.wh_5890_as(u_b);
    v_err := pg_temp.wh_5890_try(format('select public.editor_set_collection_cover_finish(%L, %L)', v_co, 'floresta'))
          || ';' || pg_temp.wh_5890_try(format('select public.editor_set_collection_cover_finish(%L, %L)', v_co, 'neon'))
          || ';' || pg_temp.wh_5890_try(format('select public.editor_set_collection_cover_code(%L, %L)', v_co, 'cob2'));
    execute 'reset role';
    res := res || jsonb_build_object('id','5.1','ok', v_err = 'OK;INVALID_FINISH;OK'
      and (select c.cover_finish || ':' || c.cover_code from public.collection c where c.id = v_co) = 'floresta:COB2',
      'detail','acabamento e código da capa da coleção pelo EDITOR; acabamento inválido recusado');
    res := res || jsonb_build_object('id','5.2','ok',
      (select l.storage_container_id from public.collection_layout l where l.id = v_layout) = v_lc
      and not exists (select 1 from pg_proc q where q.oid in (f_md, f_fin, f_cod, f_logo)
                      and q.prosrc ~* '(collection_layout|slot_image|region_image)'),
      'detail','metadados e capa não tocam identidade, acabamento, âncora nem imagens do fichário');

    -- 6. Storage e imagem da placa --------------------------------------------------------------
    f1 := u_a::text || '/' || v_co::text || '/' || gen_random_uuid()::text || '.webp';
    f2 := u_a::text || '/' || v_co::text || '/' || gen_random_uuid()::text || '.webp';
    f3 := u_a::text || '/' || v_co::text || '/' || gen_random_uuid()::text || '.webp';
    f4 := u_a::text || '/' || v_co::text || '/' || gen_random_uuid()::text || '.webp';
    fa := u_a::text || '/' || v_co::text || '/' || gen_random_uuid()::text || '.webp';
    fx := u_a::text || '/' || v_cx::text || '/' || gen_random_uuid()::text || '.webp';
    insert into storage.objects (bucket_id, name, owner_id) values ('collection-cover', fa, u_a::text);   -- arquivo do titular
    perform pg_temp.wh_5890_as(u_b);
    v_err := pg_temp.wh_5890_try(format('insert into storage.objects (bucket_id, name, owner_id) values (%L, %L, %L)', 'collection-cover', f1, u_b))
          || ';' || pg_temp.wh_5890_try(format('insert into storage.objects (bucket_id, name, owner_id) values (%L, %L, %L)', 'collection-cover', f2, u_b))
          || ';' || pg_temp.wh_5890_try(format('insert into storage.objects (bucket_id, name, owner_id) values (%L, %L, %L)', 'collection-cover', f3, u_b))
          || ';' || pg_temp.wh_5890_try(format('insert into storage.objects (bucket_id, name, owner_id) values (%L, %L, %L)', 'collection-cover', f4, u_b));
    res := res || jsonb_build_object('id','6.1','ok', v_err ~ '^OK;OK;OK;new row violates row-level security',
      'detail','EDITOR envia até 3 arquivos ainda não usados na pasta do titular da coleção autorizada; o 4º é recusado pela política');
    v_err := pg_temp.wh_5890_try(format('insert into storage.objects (bucket_id, name, owner_id) values (%L, %L, %L)', 'collection-cover', fx, u_b))
          || ';' || pg_temp.wh_5890_try(format('insert into storage.objects (bucket_id, name, owner_id) values (%L, %L, %L)', 'collection-cover',
                                               u_a::text || '/' || v_co::text || '/x.webp', u_b));
    res := res || jsonb_build_object('id','6.2','ok', v_err ~ '^new row violates row-level security.*;new row violates row-level security',
      'detail','pasta de outra coleção do titular e nome fora do formato → recusados');
    perform pg_temp.wh_5890_as(u_v);
    v_err := pg_temp.wh_5890_try(format('insert into storage.objects (bucket_id, name, owner_id) values (%L, %L, %L)', 'collection-cover', f4, u_v));
    perform pg_temp.wh_5890_as(null);
    v_err := v_err || ';' || pg_temp.wh_5890_try(format('insert into storage.objects (bucket_id, name, owner_id) values (%L, %L, null)', 'collection-cover', f4));
    res := res || jsonb_build_object('id','6.3','ok', v_err ~ '^new row violates row-level security.*;(new row violates|permission denied)',
      'detail','VIEWER e anon não enviam para a pasta do titular');
    perform pg_temp.wh_5890_as(u_b);
    select count(*) into n from storage.objects o where o.bucket_id = 'collection-cover' and o.name in (f1, f2, f3, fa);
    res := res || jsonb_build_object('id','6.4','ok', n = 3,
      'detail','EDITOR vê só os 3 arquivos dele; o arquivo do titular não aparece');
    select x.cover_logo_path || '|' || coalesce(x.removable_previous_path, '-') into v_err from public.editor_set_collection_cover_logo(v_co, f1) x;
    select x.cover_logo_path || '|' || coalesce(x.removable_previous_path, '-') into fx from public.editor_set_collection_cover_logo(v_co, f2) x;
    res := res || jsonb_build_object('id','6.5','ok', v_err = f1 || '|-' and fx = f2 || '|' || f1,
      'detail','capa com arquivo do EDITOR; trocar devolve o anterior (dele) para exclusão');
    select x.cover_logo_path || '|' || coalesce(x.removable_previous_path, '-') into v_err from public.editor_set_collection_cover_logo(v_co, fa) x;
    select x.cover_logo_path || '|' || coalesce(x.removable_previous_path, '-') into fx from public.editor_set_collection_cover_logo(v_co, f3) x;
    res := res || jsonb_build_object('id','6.6','ok', v_err = fa || '|' || f2 and fx = f3 || '|-',
      'detail','arquivo do titular pode ser usado, mas nunca é oferecido para exclusão');
    v_err := pg_temp.wh_5890_try(format('select * from public.editor_set_collection_cover_logo(%L, %L)', v_co, u_b::text || '/' || v_co::text || '/' || gen_random_uuid()::text || '.webp'))
          || ';' || pg_temp.wh_5890_try(format('select * from public.editor_set_collection_cover_logo(%L, %L)', v_co, u_a::text || '/' || v_co::text || '/' || gen_random_uuid()::text || '.webp'));
    res := res || jsonb_build_object('id','6.7','ok', v_err = 'INVALID_COVER_PATH;COVER_FILE_NOT_FOUND',
      'detail','arquivo na pasta do próprio EDITOR → INVALID_COVER_PATH; arquivo inexistente → COVER_FILE_NOT_FOUND');
    res := res || jsonb_build_object('id','6.8','ok',
      public.collection_cover_editor_folder_ok(f1) and not public.collection_cover_editor_folder_ok(f3)
      and not public.collection_cover_editor_folder_ok(fx),
      'detail','exclusão: arquivo antigo dele permitido; a capa atual e outra coleção, não (a política também exige owner_id = EDITOR)');
    perform set_config('storage.allow_delete_query', 'true', true);
    v_err := '';
    for fx in select unnest(array[fa, f3, f1]) loop
      execute 'with d as (delete from storage.objects o where o.bucket_id = ''collection-cover'' and o.name = $1 returning 1) select count(*)::int from d'
        into n using fx;
      v_err := v_err || n::text;
    end loop;
    res := res || jsonb_build_object('id','6.9','ok', v_err = '001',
      'detail','DELETE direto como EDITOR: arquivo do titular 0 linhas, capa atual 0 linhas, arquivo antigo dele 1 linha');
    execute 'reset role';
    res := res || jsonb_build_object('id','6.10','ok',
      (select c.cover_logo_path from public.collection c where c.id = v_co) = f3
      and exists (select 1 from storage.objects o where o.name = fa and o.owner_id = u_a::text)
      and exists (select 1 from storage.objects o where o.name = f3)
      and not exists (select 1 from storage.objects o where o.name = f1),
      'detail','capa final = arquivo do EDITOR e continua no Storage; arquivo do titular continua com o titular; o antigo dele saiu');

    -- 7. Troca de papel ------------------------------------------------------------------------
    perform pg_temp.wh_5890_as(u_a); perform public.set_collection_member_role(v_co, m_b, 'VIEWER');
    perform pg_temp.wh_5890_as(u_b);
    v_err := pg_temp.wh_5890_try(format('select * from public.editor_set_binder_reservation(%L, 1, 2, 1, %L)', v_co, k1))
          || ';' || pg_temp.wh_5890_try(format('select * from public.editor_set_binder_lock(%L, 1, 1, 1, true)', v_co))
          || ';' || pg_temp.wh_5890_try(format('select * from public.editor_update_collection_metadata(%L, %L, null)', v_co, 'Z'));
    n := case when public.collection_cover_editor_can_upload(f1) then 1 else 0 end;
    perform pg_temp.wh_5890_as(u_a); perform public.set_collection_member_role(v_co, m_b, 'EDITOR');
    execute 'reset role';
    res := res || jsonb_build_object('id','7.1','ok', v_err = 'COLLECTION_NOT_FOUND;COLLECTION_NOT_FOUND;COLLECTION_NOT_FOUND' and n = 0,
      'detail','EDITOR rebaixado a VIEWER perde reservar, fixar, metadados e envio na hora');

    -- 8. Histórico ------------------------------------------------------------------------------
    res := res || jsonb_build_object('id','8.1','ok',
      exists (select 1 from public.binder_activity_event e where e.layout_key = v_layout and e.actor_user_id = u_b
              and e.event_type = 'POCKET_RESERVED' and e.collection_id = v_co and e.owner_user_id = u_a)
      and exists (select 1 from public.binder_activity_event e where e.layout_key = v_layout and e.actor_user_id = u_b
                  and e.event_type = 'RESERVATIONS_RELEASED' and e.collection_id = v_co)
      and exists (select 1 from public.binder_activity_event e where e.layout_key = v_layout and e.actor_user_id = u_b
                  and e.event_type in ('POCKETS_LOCKED', 'POCKETS_UNLOCKED') and e.collection_id = v_co)
      and exists (select 1 from public.binder_activity_event e where e.layout_key = v_layout and e.actor_user_id = u_e
                  and e.collection_id = v_cx)
      and not exists (select 1 from public.binder_activity_event e where e.layout_key = v_layout and e.actor_user_id in (u_v, u_c, u_r)),
      'detail','reservar, liberar, fixar e soltar geram eventos com o EDITOR como ator e a coleção autorizada; recusas não geram evento');

    -- 9. Titular intocado ------------------------------------------------------------------------
    perform pg_temp.wh_5890_as(u_a);
    perform public.set_slot_expected_content(pg_temp.wh_5890_slot(v_layout, 2, 1), k2, null, null, v_cx);
    perform public.clear_slot_expected_content(array[pg_temp.wh_5890_slot(v_layout, 1, 3)]);
    perform public.set_slot_lock(array[pg_temp.wh_5890_slot(v_layout, 2, 2)], false);
    perform public.update_collection_metadata(v_co, 'CO 5890', null);
    execute 'reset role';
    res := res || jsonb_build_object('id','9.1','ok',
      pg_temp.wh_5890_res(v_layout, 2, 1) = k2::text || ':' || v_cx::text and pg_temp.wh_5890_res(v_layout, 1, 3) is null
      and not pg_temp.wh_5890_locked(v_layout, 2, 2) and (select c.name from public.collection c where c.id = v_co) = 'CO 5890',
      'detail','titular continua reservando para CX, liberando, soltando e editando metadados (5276–5278, 5035)');

    -- 10. Patrimônio ------------------------------------------------------------------------------
    res := res || jsonb_build_object('id','10.1','ok',
      (select string_agg(ca.physical_card_id::text || ':' || ca.collection_id::text, ',' order by ca.physical_card_id)
         from public.collection_allocation ca where ca.physical_card_id in (a1, x1)) = alloc0
      and (select string_agg(pc.id::text || ':' || coalesce(pc.storage_container_id::text, '-'), ',' order by pc.id)
             from public.physical_card pc where pc.id in (a1, x1)) = stor0
      and (select c.owner_user_id from public.collection c where c.id = v_co) = u_a,
      'detail','alocações, locais físicos e titularidade intactos');

    -- 11. Coleção arquivada ------------------------------------------------------------------------
    perform pg_temp.wh_5890_as(u_a); perform public.archive_collection(v_cx);
    perform pg_temp.wh_5890_as(u_e);
    v_err := pg_temp.wh_5890_try(format('select * from public.editor_set_binder_reservation(%L, 1, 2, 3, %L)', v_cx, k1))
          || ';' || pg_temp.wh_5890_try(format('select * from public.editor_set_binder_lock(%L, 1, 1, 2, true)', v_cx))
          || ';' || pg_temp.wh_5890_try(format('select * from public.editor_update_collection_metadata(%L, %L, null)', v_cx, 'E'));
    execute 'reset role';
    res := res || jsonb_build_object('id','11.1','ok', v_err = 'COLLECTION_ARCHIVED;COLLECTION_ARCHIVED;COLLECTION_ARCHIVED',
      'detail','convidada arquivada: EDITOR de CX não reserva, não fixa, não edita metadados');

    execute 'reset role';
    raise exception 'MS890' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MS890' then
      res := res || jsonb_build_object('id','X.1','ok', false, 'detail','erro inesperado: '||sqlstate||' '||sqlerrm);
    end if;
  end;

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.collection_membership), (select count(*) from public.collection_layout_slot_expected_content),
               (select count(*) from public.binder_activity_event), (select count(*) from storage.objects)]
    into e_counts;
  res := res || jsonb_build_object('id','99.1','ok', b_counts = e_counts and current_user = session_user,
    'detail','resíduo zero (8 contagens, inclusive storage.objects) e papel restaurado');

  v_expected := 45;
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
  select '5890', seq, check_id, status, detail from pg_temp.wh_5890_validate();

-- @@T8 modo da barreira CLOSED (só nesta transação)
update public.v1_13_barrier_state set mode = 'CLOSED', change_note = 'G2 ensaio' where id = 1;

-- @@T8 harness 5895 [CLOSED] sha256=f7025b7a609912e43369c593e4dcd4f8352aa2433dafc2a8a8fca4677550bda6
create or replace function pg_temp.wh_5895_as(p_user uuid)
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

create or replace function pg_temp.wh_5895_try(p_sql text)
returns text language plpgsql volatile as $try$
begin
  execute p_sql;
  return 'OK';
exception when others then
  return sqlerrm;
end;
$try$;

-- Chama a função pela assinatura com argumentos nulos tipados; devolve 'OK' ou a mensagem.
create or replace function pg_temp.wh_5895_null_call(p_sig text)
returns text language plpgsql volatile as $nc$
declare
  v_oid  oid := to_regprocedure(p_sig);
  v_args text;
  v_sql  text;
begin
  if v_oid is null then
    return 'MISSING';
  end if;
  select coalesce(string_agg('NULL::' || format_type(t, null), ', ' order by o), '')
    into v_args
  from unnest((select p.proargtypes::oid[] from pg_proc p where p.oid = v_oid)) with ordinality u(t, o);
  select format('select count(*) from %I.%I(%s)', n.nspname, p.proname, v_args) into v_sql
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace where p.oid = v_oid;
  execute v_sql;
  return 'OK';
exception when others then
  return sqlerrm;
end;
$nc$;

-- Quantas das assinaturas devolveram exatamente a recusa da barreira.
create or replace function pg_temp.wh_5895_barrier_count(p_sigs text[])
returns integer language plpgsql volatile as $bc$
declare s text; n integer := 0;
begin
  foreach s in array p_sigs loop
    if pg_temp.wh_5895_null_call(s) = 'CAPABILITY_NOT_ENABLED' then n := n + 1; end if;
  end loop;
  return n;
end;
$bc$;

create or replace function pg_temp.wh_5895_reads(p_cf uuid, p_cd uuid, p_cm uuid)
returns text language plpgsql volatile as $rd$
begin
  return (select count(*) from public.get_shared_master_set_positions(p_cm, 'ALL', 500, 0))::text
    || '/' || (select count(*) from public.get_shared_pokedex_positions(p_cd, 'ALL', null, 500, 0))::text
    || '/' || (select count(*) from public.get_shared_binder_activity_status(p_cf))::text
    || '/' || (select count(*) from public.get_shared_binder_activity(p_cf, null, null, null, 50))::text
    || '/' || (select count(*) from public.get_shared_binder_placeable_cards(p_cf, 96, 0))::text;
end;
$rd$;

create or replace function pg_temp.wh_5895_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
as $fn$
#variable_conflict use_column
declare
  c_w text[] := array[
      'public.set_collection_member_role(UUID, UUID, TEXT)',
      'public.editor_place_card_in_binder(uuid, integer, integer, integer, uuid)',
      'public.editor_move_binder_card(uuid, integer, integer, integer, integer, integer, integer)',
      'public.editor_remove_binder_card(uuid, integer, integer, integer)',
      'public.editor_set_binder_reservation(uuid, integer, integer, integer, uuid, uuid, uuid)',
      'public.editor_clear_binder_reservation(uuid, integer, integer, integer)',
      'public.editor_set_binder_lock(uuid, integer, integer, integer, boolean)',
      'public.editor_update_collection_metadata(uuid, text, text)',
      'public.editor_set_collection_cover_finish(uuid, text)',
      'public.editor_set_collection_cover_code(uuid, text)',
      'public.editor_set_collection_cover_logo(uuid, text)',
      'public.editor_set_pokedex_position_assignment(uuid, uuid, uuid, boolean)',
      'public.editor_remove_pokedex_position_assignment(uuid, uuid)',
      'public.editor_set_pokedex_position_primary_representative(uuid, uuid)',
      'public.editor_clear_pokedex_position_primary_representative(uuid, uuid)',
      'public.editor_add_binder_page(uuid)',
      'public.editor_remove_binder_page(uuid, integer, integer)',
      'public.editor_reorder_binder_pages(uuid, integer[])',
      'public.editor_preview_binder_species_references(uuid)',
      'public.editor_apply_binder_species_references(uuid, text)',
      'public.editor_clear_binder_species_references(uuid, integer)',
      'public.editor_set_binder_species_reference_visibility(uuid, boolean)',
      'public.editor_preview_binder_insert_gap(uuid, integer, integer, integer)',
      'public.editor_insert_binder_gap(uuid, integer, integer, integer, text, boolean, boolean)',
      'public.editor_close_binder_gap(uuid, integer, integer, integer, integer, integer, integer, text, integer)',
      'public.editor_preview_binder_auto_arrange(uuid)',
      'public.editor_apply_binder_auto_arrange(uuid, text)',
      'public.editor_preview_binder_catalog_reconciliation(uuid, text[])',
      'public.editor_apply_binder_catalog_reconciliation(uuid, text[], text, boolean, boolean)'];
  c_r text[] := array[
      'public.get_shared_binder_placeable_cards(uuid, integer, integer)',
      'public.get_shared_master_set_positions(uuid, text, integer, integer)',
      'public.get_shared_pokedex_positions(uuid, text, text, integer, integer)',
      'public.get_shared_binder_activity(uuid, text[], timestamptz, bigint, integer)',
      'public.get_shared_binder_activity_status(uuid)'];
  c_h text[] := array[
      'public.collection_cover_editor_folder_ok(text)',
      'public.collection_cover_editor_can_upload(text)'];
  c_inv text := 'public.invite_collection_member(UUID, TEXT, TEXT)';
  c_gate text[] := array['public.v1_13_capability_open()', 'public.v1_13_assert_capability()'];
  u_a uuid := gen_random_uuid(); u_b uuid := gen_random_uuid(); u_u uuid := gen_random_uuid();
  u_v uuid := gen_random_uuid(); u_w uuid := gen_random_uuid(); u_r uuid := gen_random_uuid();
  u_p uuid := gen_random_uuid(); u_s uuid := gen_random_uuid(); u_x uuid := gen_random_uuid();
  u_q uuid := gen_random_uuid(); u_o uuid := gen_random_uuid(); u_t uuid := gen_random_uuid();
  v_sfx text := lower(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  v_game uuid; v_pt uuid; v_rar uuid; v_cat uuid; v_std uuid; v_exp uuid; v_sm uuid; v_gen text; m1 uuid;
  v_bf uuid; v_bd uuid; v_bm uuid; v_bo uuid; v_cf uuid; v_cd uuid; v_cm uuid; v_co uuid;
  m_b uuid; m_u uuid; m_v uuid; m_w uuid; m_r uuid; m_p uuid; m_q uuid; m_x uuid;
  m_vd uuid; m_wd uuid; m_vm uuid; m_wm uuid;
  f_ok text; f_own text; f_u text; f_b2 text;
  v_txt text; v_txt2 text; v_err text; v_j jsonb; v_ok boolean; n integer; n2 integer; s text;
  b_counts bigint[]; e_counts bigint[];
  res jsonb := '[]'::jsonb; r jsonb; cnt integer := 0; passes integer := 0;
  v_expected integer := 0;
begin
  -- 0. Estrutura e estado inicial ---------------------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    (select count(*) from pg_class c where c.oid in (to_regclass('public.v1_13_barrier_state'), to_regclass('public.v1_13_barrier_identity'))
       and c.relrowsecurity
       and not exists (select 1 from pg_policy p where p.polrelid = c.oid)
       and not has_table_privilege('anon', c.oid, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
       and not has_table_privilege('authenticated', c.oid, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
       and not has_table_privilege('service_role', c.oid, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')) = 2
    and (select count(*) from pg_proc q where q.oid in (to_regprocedure(c_gate[1]), to_regprocedure(c_gate[2]))
           and q.prosecdef and q.proconfig = array['search_path=""']
           and not has_function_privilege('anon', q.oid, 'EXECUTE')
           and not has_function_privilege('authenticated', q.oid, 'EXECUTE')
           and not has_function_privilege('service_role', q.oid, 'EXECUTE')) = 2,
    'detail','tabelas da barreira com RLS sem política e sem privilégio de cliente; porta definer, search_path vazio, sem EXECUTE para anon/authenticated/service_role');
  res := res || jsonb_build_object('id','0.2','ok',
    (select count(*) from unnest(c_w || c_r || c_h || array[c_inv]) s0(sig)
       join pg_proc q on q.oid = to_regprocedure(s0.sig)
      where q.prosecdef and has_function_privilege('authenticated', q.oid, 'EXECUTE')
        and not has_function_privilege('anon', q.oid, 'EXECUTE')
        and position('public.v1_13_' in q.prosrc) > 0) = 37
    and not exists (select 1 from pg_proc q join pg_namespace ns on ns.oid = q.pronamespace
                    where ns.nspname = 'public' and q.proname like 'editor\_%'
                      and has_function_privilege('authenticated', q.oid, 'EXECUTE')
                      and position('public.v1_13_' in q.prosrc) = 0),
    'detail','as 37 capacidades existem, são definer, só authenticated e chamam a porta; nenhuma RPC editor_* exposta sem porta');
  res := res || jsonb_build_object('id','0.3','ok',
    (select s1.mode from public.v1_13_barrier_state s1 where s1.id = 1) = 'CLOSED'
    and (select count(*) from public.v1_13_barrier_state) = 1
    and not exists (select 1 from public.v1_13_barrier_identity),
    'detail','estado ao fim da aplicação: CLOSED, uma linha, registro vazio');
  res := res || jsonb_build_object('id','0.4','ok',
    (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.collection_share_role(uuid)')) = 'efdb495b5b703e9f093eb0f49a1d0a5d'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.get_shared_collection(uuid)')) = '69d69fd11dddcaedabe7368a3e038368'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.get_my_collection_sharing(uuid)')) = 'e36aa9c675f6b8097b6a43292b62603f'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)')) = 'f8cfba40e442e85056e7c8ce7954d4f4'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.binder_slot_editor_scope(uuid, uuid, uuid, uuid)')) = '21f1b51a3a0f6c80337c2c593cc6054f'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.binder_activity_event_editor_type_guard()')) = '78fa0d34dad161eac1165f3143874260',
    'detail','funções compartilhadas sem porta e iguais às auditadas: 5302, leitura V1-12 substituída pela 5368 (get_shared_collection) e 5308 inalterada, gravação do histórico (5379), classificação (5378), gatilho (5384)');

  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_membership), (select count(*) from public.collection_allocation),
               (select count(*) from public.physical_card), (select count(*) from public.card),
               (select count(*) from storage.objects),
               (select count(*) from public.v1_13_barrier_state), (select count(*) from public.v1_13_barrier_identity),
               (select count(*) from public.binder_activity_event)]
    into b_counts;

  begin
    -- F. Fixture (modo TEST para os convites EDITOR) ---------------------------------------------
    select g.id into v_game from public.game g where g.code = 'POKEMON';
    select l.id into v_pt from public.language l where l.code = 'pt-BR';
    select t.id into v_std from public.card_variant_type t where t.game_id = v_game and t.code = 'STANDARD';
    select c.id into v_cat from public.card_category c where c.game_id = v_game and c.code = 'POKEMON';
    select c0.rarity_id into v_rar
    from public.card c0 join public.card_set cs0 on cs0.id = c0.card_set_id
    join public.expansion e0 on e0.id = cs0.expansion_id where e0.game_id = v_game limit 1;
    select g.code into v_gen
    from public.pokedex dx join public.pokedex_position pp on pp.pokedex_id = dx.id
    join public.pokemon_species sp on sp.id = pp.species_id join public.pokemon_generation g on g.id = sp.generation_id
    where dx.code = 'NATIONAL' order by pp.position_number limit 1;
    if v_game is null or v_pt is null or v_std is null or v_cat is null or v_rar is null or v_gen is null then
      res := res || jsonb_build_object('id','F.1','ok', false, 'detail','pré-requisitos de catálogo ou Pokédex NATIONAL ausentes');
      raise exception 'MS895' using errcode = 'P0001';
    end if;
    insert into public.expansion (game_id, code, name, release_order)
    values (v_game, 'BR_' || upper(v_sfx), 'BR Harness ' || v_sfx,
            (select coalesce(max(x.release_order), 0) + 1000 from public.expansion x where x.game_id = v_game))
    returning id into v_exp;
    insert into public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_exp, 'BR' || upper(v_sfx), 'BR Set ' || v_sfx, 'REGULAR', 1, 1, 1) returning id into v_sm;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_sm, v_rar, v_cat, '1', 1, 'BR 1', true) returning id into m1;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (m1, v_std, 1, true);

    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    select u.id, 'authenticated', 'authenticated', 'wh895' || u.t || '_' || v_sfx || '@example.invalid',
           jsonb_build_object('username', 'wh895' || u.t || '_' || v_sfx, 'display_name', 'WH 5895 ' || upper(u.t)), now(), now()
    from (values (u_a,'a'),(u_b,'b'),(u_u,'u'),(u_v,'v'),(u_w,'w'),(u_r,'r'),(u_p,'p'),(u_s,'s'),
                 (u_x,'x'),(u_q,'q'),(u_o,'o'),(u_t,'t')) u(id, t);
    update public.v1_13_barrier_state set mode = 'TEST' where id = 1;
    insert into public.v1_13_barrier_identity (user_id, note)
    select x, 'wh895' from unnest(array[u_a, u_b, u_v, u_r, u_p, u_s]) x;

    perform pg_temp.wh_5895_as(u_a);
    select x.storage_container_id into v_bf from public.create_my_storage_container(gen_random_uuid(), 'BIN F 5895', 'BINDER') x;
    select x.storage_container_id into v_bd from public.create_my_storage_container(gen_random_uuid(), 'BIN D 5895', 'BINDER') x;
    select x.storage_container_id into v_bm from public.create_my_storage_container(gen_random_uuid(), 'BIN M 5895', 'BINDER') x;
    select x.collection_id into v_cf from public.create_my_free_collection(gen_random_uuid(), 'CF 5895', v_bf) x;
    select x.collection_id into v_cd from public.create_my_pokedex_collection(gen_random_uuid(), 'CD 5895', array[v_gen], v_bd) x;
    select x.collection_id into v_cm from public.create_my_card_set_collection(gen_random_uuid(), v_sm, 'CM 5895', v_bm) x;
    perform count(*) from public.set_collection_completion_policy_to_master_set(v_cm, array[v_std]);
    m_b := (public.invite_collection_member(v_cf, 'wh895b_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_u := (public.invite_collection_member(v_cf, 'wh895u_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_r := (public.invite_collection_member(v_cf, 'wh895r_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_p := (public.invite_collection_member(v_cf, 'wh895p_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_q := (public.invite_collection_member(v_cf, 'wh895q_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_v := (public.invite_collection_member(v_cf, 'wh895v_' || v_sfx) ->> 'membership_id')::uuid;
    m_w := (public.invite_collection_member(v_cf, 'wh895w_' || v_sfx) ->> 'membership_id')::uuid;
    m_vd := (public.invite_collection_member(v_cd, 'wh895v_' || v_sfx) ->> 'membership_id')::uuid;
    m_wd := (public.invite_collection_member(v_cd, 'wh895w_' || v_sfx) ->> 'membership_id')::uuid;
    m_vm := (public.invite_collection_member(v_cm, 'wh895v_' || v_sfx) ->> 'membership_id')::uuid;
    m_wm := (public.invite_collection_member(v_cm, 'wh895w_' || v_sfx) ->> 'membership_id')::uuid;
    perform pg_temp.wh_5895_as(u_b); perform public.respond_collection_invite(m_b, true);
    perform pg_temp.wh_5895_as(u_u); perform public.respond_collection_invite(m_u, true);
    perform pg_temp.wh_5895_as(u_r); perform public.respond_collection_invite(m_r, true);
    perform pg_temp.wh_5895_as(u_v);
    perform public.respond_collection_invite(m_v, true); perform public.respond_collection_invite(m_vd, true);
    perform public.respond_collection_invite(m_vm, true);
    perform pg_temp.wh_5895_as(u_w);
    perform public.respond_collection_invite(m_w, true); perform public.respond_collection_invite(m_wd, true);
    perform public.respond_collection_invite(m_wm, true);
    perform pg_temp.wh_5895_as(u_a); perform public.remove_collection_member(v_cf, m_r);
    perform pg_temp.wh_5895_as(u_o);
    select x.storage_container_id into v_bo from public.create_my_storage_container(gen_random_uuid(), 'BIN O 5895', 'BINDER') x;
    select x.collection_id into v_co from public.create_my_pokedex_collection(gen_random_uuid(), 'CO 5895', array[v_gen], v_bo) x;
    execute 'reset role';
    f_ok  := u_a::text || '/' || v_cf::text || '/' || gen_random_uuid()::text || '.webp';
    f_b2  := u_a::text || '/' || v_cf::text || '/' || gen_random_uuid()::text || '.webp';
    f_u   := u_a::text || '/' || v_cf::text || '/' || gen_random_uuid()::text || '.webp';
    f_own := u_a::text || '/' || v_cf::text || '/' || gen_random_uuid()::text || '.webp';
    res := res || jsonb_build_object('id','F.2','ok',
      (select count(*) from public.collection_membership m where m.collection_id = v_cf and m.status = 'ACTIVE' and m.role = 'EDITOR') = 2
      and exists (select 1 from public.collection_membership m where m.id = m_p and m.status = 'PENDING' and m.role = 'EDITOR')
      and exists (select 1 from public.collection_membership m where m.id = m_q and m.status = 'PENDING' and m.role = 'EDITOR')
      and (select count(*) from public.v1_13_barrier_identity) = 6,
      'detail','fixture: B e U EDITOR ativos de CF; P e Q com convite EDITOR pendente; 6 identidades registradas');

    -- 1. CLOSED ---------------------------------------------------------------------------------
    update public.v1_13_barrier_state set mode = 'CLOSED' where id = 1;
    perform pg_temp.wh_5895_as(u_b);
    n := pg_temp.wh_5895_barrier_count(c_w);
    v_txt := public.collection_cover_editor_folder_ok(f_ok)::text || '/' || public.collection_cover_editor_can_upload(f_ok)::text;
    v_txt2 := (select count(*) from public.get_shared_binder_placeable_cards(v_cf, 96, 0))::text;
    perform pg_temp.wh_5895_as(u_a);
    v_err := pg_temp.wh_5895_try(format('select public.invite_collection_member(%L, %L, %L)', v_cf, 'wh895s_' || v_sfx, 'EDITOR'));
    perform pg_temp.wh_5895_as(u_v);
    s := pg_temp.wh_5895_reads(v_cf, v_cd, v_cm);
    execute 'reset role';
    res := res || jsonb_build_object('id','1.1','ok', n = 29 and v_err = 'CAPABILITY_NOT_ENABLED'
      and v_txt = 'false/false' and v_txt2 = '0' and s = '0/0/0/0/0',
      'detail','CLOSED: as 29 escritas recusadas pela barreira para EDITOR registrado; convite EDITOR recusado; ajudantes do Storage falsos; 5 leituras com zero linhas para VIEWER registrado');

    perform pg_temp.wh_5895_as(u_b);
    v_err := pg_temp.wh_5895_try(format('insert into storage.objects (bucket_id, name, owner_id) values (%L, %L, %L)', 'collection-cover', f_ok, u_b));
    perform pg_temp.wh_5895_as(u_a);
    v_txt := pg_temp.wh_5895_try(format('insert into storage.objects (bucket_id, name, owner_id) values (%L, %L, %L)', 'collection-cover', f_own, u_a));
    execute 'reset role';
    res := res || jsonb_build_object('id','1.2','ok', v_err ~ 'row-level security' and v_txt = 'OK',
      'detail','CLOSED: envio do EDITOR na pasta do titular recusado pela política; envio do titular na própria pasta (5176, V1-12) aceito');

    perform pg_temp.wh_5895_as(u_a);
    m_x := (public.invite_collection_member(v_cf, 'wh895x_' || v_sfx) ->> 'membership_id')::uuid;
    perform pg_temp.wh_5895_as(u_x); perform public.respond_collection_invite(m_x, true);
    perform pg_temp.wh_5895_as(u_v);
    v_j := public.get_shared_collection(v_cf);
    select count(*) into n from jsonb_array_elements(public.get_collections_shared_with_me()) e where (e ->> 'collection_id')::uuid = v_cf;
    perform pg_temp.wh_5895_as(u_b);
    v_txt := public.get_shared_collection(v_cf) ->> 'role';
    execute 'reset role';
    res := res || jsonb_build_object('id','1.3','ok', m_x is not null
      and exists (select 1 from public.collection_membership m where m.id = m_x and m.status = 'ACTIVE' and m.role = 'VIEWER')
      and v_j ->> 'access' = 'VIEWER' and n = 1 and v_txt = 'EDITOR',
      'detail','CLOSED preserva a V1-12: convite VIEWER de 2 argumentos e aceite; leitura da coleção e "compartilhadas comigo"; a 5368 continua devolvendo o papel');

    -- 2. TEST -----------------------------------------------------------------------------------
    update public.v1_13_barrier_state set mode = 'TEST' where id = 1;
    perform pg_temp.wh_5895_as(u_u);
    n := pg_temp.wh_5895_barrier_count(c_w);
    v_txt := public.collection_cover_editor_folder_ok(f_u)::text;
    v_err := pg_temp.wh_5895_try(format('insert into storage.objects (bucket_id, name, owner_id) values (%L, %L, %L)', 'collection-cover', f_u, u_u));
    perform pg_temp.wh_5895_as(u_w);
    s := pg_temp.wh_5895_reads(v_cf, v_cd, v_cm);
    execute 'reset role';
    res := res || jsonb_build_object('id','2.1','ok', n = 29 and v_txt = 'false' and v_err ~ 'row-level security' and s = '0/0/0/0/0',
      'detail','TEST, não registrados com papel válido: EDITOR U recusado pela barreira nas 29 escritas e no Storage; VIEWER W com zero linhas nas 5 leituras');

    perform pg_temp.wh_5895_as(u_b);
    n := pg_temp.wh_5895_barrier_count(c_w);
    v_txt := public.collection_cover_editor_folder_ok(f_b2)::text;
    v_err := pg_temp.wh_5895_try(format('insert into storage.objects (bucket_id, name, owner_id) values (%L, %L, %L)', 'collection-cover', f_b2, u_b));
    execute 'reset role';
    res := res || jsonb_build_object('id','2.2','ok', n = 0 and v_txt = 'true' and v_err = 'OK',
      'detail','TEST, EDITOR registrado: a barreira não recusa nenhuma das 29 escritas (as respostas são do produto); ajudante verdadeiro e envio aceito');

    perform pg_temp.wh_5895_as(u_b);
    v_err := pg_temp.wh_5895_try(format('select count(*) from public.editor_update_collection_metadata(%L, %L, null)', v_cf, 'CF 5895 B'));
    v_txt := '';
    foreach s in array array[u_v::text, u_s::text, u_r::text, u_p::text] loop
      perform pg_temp.wh_5895_as(s::uuid);
      v_txt := v_txt || pg_temp.wh_5895_try(format('select count(*) from public.editor_update_collection_metadata(%L, %L, null)', v_cf, 'CF 5895 X')) || ';';
    end loop;
    execute 'reset role';
    res := res || jsonb_build_object('id','2.3','ok', v_err = 'OK'
      and (select c.name from public.collection c where c.id = v_cf) = 'CF 5895 B'
      and position('CAPABILITY_NOT_ENABLED' in v_txt) = 0 and position('OK;' in v_txt) = 0,
      'detail','TEST: a barreira não mascara a autorização funcional — VIEWER, estranho, removido e pendente, todos registrados, recusados pelo produto (nunca pela barreira); EDITOR registrado grava');

    perform pg_temp.wh_5895_as(u_v); s := pg_temp.wh_5895_reads(v_cf, v_cd, v_cm);
    perform pg_temp.wh_5895_as(u_a);
    select count(*) into n from public.get_shared_pokedex_positions(v_cd, 'ALL', null, 500, 0);
    perform pg_temp.wh_5895_as(u_o);
    select count(*) into n2 from public.get_shared_pokedex_positions(v_co, 'ALL', null, 500, 0);
    execute 'reset role';
    res := res || jsonb_build_object('id','2.4','ok', split_part(s, '/', 1)::integer > 0 and split_part(s, '/', 2)::integer > 0
      and split_part(s, '/', 3) = '1' and n > 0 and n2 = 0,
      'detail','TEST: VIEWER registrado lê Master Set, Pokédex e estado do histórico; titular registrado lê a própria Pokédex; titular não registrado recebe zero linhas');

    perform pg_temp.wh_5895_as(u_o);
    v_err := pg_temp.wh_5895_try(format('select public.invite_collection_member(%L, %L, %L)', v_co, 'wh895t_' || v_sfx, 'EDITOR'))
          || ';' || pg_temp.wh_5895_try(format('select public.invite_collection_member(%L, %L)', v_co, 'wh895t_' || v_sfx));
    execute 'reset role';
    res := res || jsonb_build_object('id','2.5','ok', v_err = 'CAPABILITY_NOT_ENABLED;OK',
      'detail','TEST: titular não registrado não convida EDITOR; convite VIEWER legado continua');

    delete from public.v1_13_barrier_identity where user_id = u_b;
    perform pg_temp.wh_5895_as(u_b);
    v_err := pg_temp.wh_5895_null_call('public.editor_add_binder_page(uuid)');
    execute 'reset role';
    insert into public.v1_13_barrier_identity (user_id, note) values (u_b, 'wh895');
    perform pg_temp.wh_5895_as(u_b);
    v_txt := pg_temp.wh_5895_null_call('public.editor_add_binder_page(uuid)');
    perform pg_temp.wh_5895_as(u_a);
    perform public.set_collection_member_role(v_cf, m_b, 'VIEWER');
    perform pg_temp.wh_5895_as(u_b);
    v_txt2 := pg_temp.wh_5895_try(format('select count(*) from public.editor_update_collection_metadata(%L, %L, null)', v_cf, 'CF 5895 V'));
    perform pg_temp.wh_5895_as(u_a);
    perform public.set_collection_member_role(v_cf, m_b, 'EDITOR');
    execute 'reset role';
    res := res || jsonb_build_object('id','2.6','ok', v_err = 'CAPABILITY_NOT_ENABLED' and v_txt <> 'CAPABILITY_NOT_ENABLED'
      and v_txt2 <> 'OK' and v_txt2 <> 'CAPABILITY_NOT_ENABLED',
      'detail','revogação: retirar do registro fecha na chamada seguinte e recolocar reabre; troca de papel para VIEWER recusa pelo produto (não pela barreira)');

    -- 3. OPEN, configuração ausente, anon, tabelas administrativas, convite aceito em CLOSED -----
    update public.v1_13_barrier_state set mode = 'OPEN' where id = 1;
    perform pg_temp.wh_5895_as(u_u); n := pg_temp.wh_5895_barrier_count(c_w);
    perform pg_temp.wh_5895_as(u_w); s := pg_temp.wh_5895_reads(v_cf, v_cd, v_cm);
    execute 'reset role';
    res := res || jsonb_build_object('id','3.1','ok', n = 0 and split_part(s, '/', 2)::integer > 0,
      'detail','OPEN (estado futuro, só nesta transação): não registrados passam pela barreira e caem na autorização do produto');

    delete from public.v1_13_barrier_state where id = 1;
    perform pg_temp.wh_5895_as(u_b); n := pg_temp.wh_5895_barrier_count(c_w);
    v_txt := public.collection_cover_editor_folder_ok(f_ok)::text;
    perform pg_temp.wh_5895_as(u_v); s := pg_temp.wh_5895_reads(v_cf, v_cd, v_cm);
    execute 'reset role';
    insert into public.v1_13_barrier_state (id, mode) values (1, 'TEST');
    res := res || jsonb_build_object('id','3.2','ok', n = 29 and v_txt = 'false' and s = '0/0/0/0/0',
      'detail','configuração ausente (sem linha de estado): negação total, inclusive para registrados');

    res := res || jsonb_build_object('id','3.3','ok',
      (select count(*) from unnest(c_w || c_r || c_h || array[c_inv] || c_gate) s0(sig)
        where has_function_privilege('anon', to_regprocedure(s0.sig), 'EXECUTE')) = 0,
      'detail','anon sem EXECUTE nas 37 capacidades e na porta');
    perform pg_temp.wh_5895_as(null);
    v_err := pg_temp.wh_5895_try(format('select count(*) from public.get_shared_binder_activity_status(%L)', v_cf));
    execute 'reset role';
    res := res || jsonb_build_object('id','3.4','ok', v_err ~ 'permission denied',
      'detail','sessão anônima recusada pelo privilégio (antes da porta)');

    perform pg_temp.wh_5895_as(u_b);
    v_txt := pg_temp.wh_5895_try('select count(*) from public.v1_13_barrier_state')
      || ';' || pg_temp.wh_5895_try('select count(*) from public.v1_13_barrier_identity')
      || ';' || pg_temp.wh_5895_try(format('insert into public.v1_13_barrier_identity (user_id) values (%L)', u_u))
      || ';' || pg_temp.wh_5895_try('update public.v1_13_barrier_state set mode = ''OPEN''')
      || ';' || pg_temp.wh_5895_try('delete from public.v1_13_barrier_identity')
      || ';' || pg_temp.wh_5895_try('select public.v1_13_capability_open()')
      || ';' || pg_temp.wh_5895_try('select public.v1_13_assert_capability()');
    execute 'reset role';
    res := res || jsonb_build_object('id','3.5','ok',
      (select count(*) from regexp_matches(v_txt, 'permission denied', 'g')) = 7
      and (select s1.mode from public.v1_13_barrier_state s1 where s1.id = 1) = 'TEST'
      and not exists (select 1 from public.v1_13_barrier_identity i where i.user_id = u_u),
      'detail','authenticated não lê, não se inscreve, não muda o modo, não apaga o registro e não executa a porta');

    update public.v1_13_barrier_state set mode = 'CLOSED' where id = 1;
    perform pg_temp.wh_5895_as(u_q);
    v_err := pg_temp.wh_5895_try(format('select public.respond_collection_invite(%L, true)', m_q));
    v_txt := pg_temp.wh_5895_null_call('public.editor_add_binder_page(uuid)');
    v_txt2 := public.get_shared_collection(v_cf) ->> 'access';
    execute 'reset role';
    res := res || jsonb_build_object('id','3.6','ok', v_err = 'OK' and v_txt = 'CAPABILITY_NOT_ENABLED' and v_txt2 = 'VIEWER',
      'detail','convite EDITOR criado em TEST e aceito em CLOSED (5304, V1-12): a participação existe, mas toda capacidade do EDITOR fica fechada; a leitura V1-12 continua no nível VIEWER (5302)');

    execute 'reset role';
    raise exception 'MS895' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MS895' then
      res := res || jsonb_build_object('id','X.1','ok', false, 'detail','erro inesperado: '||sqlstate||' '||sqlerrm);
    end if;
  end;

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_membership), (select count(*) from public.collection_allocation),
               (select count(*) from public.physical_card), (select count(*) from public.card),
               (select count(*) from storage.objects),
               (select count(*) from public.v1_13_barrier_state), (select count(*) from public.v1_13_barrier_identity),
               (select count(*) from public.binder_activity_event)]
    into e_counts;
  res := res || jsonb_build_object('id','99.1','ok', b_counts = e_counts and current_user = session_user
    and (select s1.mode from public.v1_13_barrier_state s1 where s1.id = 1) = 'CLOSED'
    and not exists (select 1 from public.v1_13_barrier_identity),
    'detail','resíduo zero (10 contagens, inclusive Storage e as tabelas da barreira), modo de volta a CLOSED com registro vazio e papel restaurado');

  v_expected := 21;
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
  select '5895', seq, check_id, status, detail from pg_temp.wh_5895_validate();

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
  v_ok := coalesce(v_total = 417 and v_passes = 417 and v_trap and v_ms <= 240000
                   and (select count(*) from jsonb_each_text(v_gates) g where g.value = 'PASS') = 12, false);
  v_code := case when v_ok then 'E2BOK' else 'E2BNO' end;
  -- [MGMTAPI] mensagem compacta (limite de 1.024 caracteres da CLI): sem textos de fixture nem horários de travas;
  -- falhas (até 8) e erros inesperados (até 2, 70 caracteres, sem aspas/barras) limitados, com contagem total
  -- e indicação explícita de truncamento: lista parcial NUNCA é a lista completa (ver failed_count/x1_count).
  v_msg := 'MS_G2B ' || case when v_ok then 'APROVADO ' else 'REPROVADO ' end || jsonb_build_object(
    'ok', v_ok, 'txid', pg_catalog.txid_current_if_assigned(), 'total', v_total, 'passes', v_passes,
    'gates', v_gates,
    'failed_count', jsonb_array_length(v_failed),
    'failed', coalesce((select jsonb_agg(e.value order by e.ordinality) from jsonb_array_elements(v_failed) with ordinality e
                         where e.ordinality <= 8), '[]'::jsonb),
    'failed_truncated', jsonb_array_length(v_failed) > 8,
    'x1_count', (select count(*) from jsonb_array_elements_text(v_fixture) x where x.value ~ '^[0-9]{4}:erro inesperado'),
    'x1', coalesce((select jsonb_agg(translate(left(q.value, 70), '"\', '') order by q.ordinality)
                     from (select x.value, x.ordinality from jsonb_array_elements_text(v_fixture) with ordinality x
                           where x.value ~ '^[0-9]{4}:erro inesperado' order by x.ordinality limit 2) q), '[]'::jsonb),
    'trap_intact', v_trap, 'duration_ms', v_ms,
    'locks', (select count(*) from pg_temp.g2_meta where k like 't_lock%'),
    'server_version_num', (select v from pg_temp.g2_meta where k = 'server_version_num'))::text;
  raise exception using message = v_msg, errcode = v_code;
end;
$t9sentinel$;

-- [MGMTAPI] T10/T11 omitidos: a sentinela aborta a transação implícita; nada é executado depois dela.
