/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5389 - Barreira de acesso no servidor das capacidades da V1-13
              (D-E1, G1): estado CLOSED/TEST/OPEN, registro de identidades
              de teste e as duas funções internas da porta
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA. Preparada em
              `V1-13 / E1-E | G1 SERVER-SIDE BARRIER PREPARATION-01` (2026-11-15).
              Mecanismo NÃO homologado. Execução só depois de G2 (ensaio) e
              com autorização expressa e específica.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-15
Decisão.....: D-E1 (opção A, aprovada), Alternativa C (arquitetura candidata
              aprovada para o G1). Não altera C-234–C-244 nem D9–D14.
Ordem.......: PRIMEIRA migration da cadeia V1-13 (antes de 5366). A numeração
              não é a ordem: 5389 é o próximo número livre.

O que cria:
  1. public.v1_13_barrier_state — uma única linha (id = 1), modo
     CLOSED | TEST | OPEN. Criada em CLOSED.
  2. public.v1_13_barrier_identity — identidades de teste autorizadas
     (user_id → auth.users, ON DELETE CASCADE: excluir a conta de teste
     retira a autorização).
  3. public.v1_13_capability_open() — boolean. Verdadeiro só se há usuário
     autenticado (auth.uid() do JWT) E (modo = OPEN, ou modo = TEST e o
     usuário está no registro). Linha de estado ausente, modo desconhecido,
     sessão anônima → falso (negação por padrão).
  4. public.v1_13_assert_capability() — levanta 42501 CAPABILITY_NOT_ENABLED
     (hint V1_13_BARRIER) quando a porta está fechada para o chamador.

Controles:
  - Tabelas com RLS ativa e NENHUMA política; REVOKE ALL de PUBLIC, anon,
    authenticated e service_role (os privilégios padrão do Supabase concedem
    tudo a esses papéis em tabelas novas do schema public). Nenhum cliente lê,
    grava, se inscreve ou muda o modo; a mudança é só por SQL do proprietário
    (postgres), com autorização específica.
  - Funções SECURITY DEFINER, search_path vazio, objetos qualificados, sem
    EXECUTE para PUBLIC, anon, authenticated ou service_role: só as funções
    protegidas (SECURITY DEFINER do mesmo dono) as chamam. Nenhum valor vem do
    cliente: a identidade é auth.uid().
  - STABLE: dentro de uma chamada, a decisão é a mesma do início ao fim
    (mesmo instantâneo). CLOSED não cancela chamadas já iniciadas.

O que NÃO faz: não protege nada sozinha. A proteção existe quando cada
  capacidade nova consulta a porta (versões protegidas em g1/protected/).
Reversão....: ROLLBACK_G1.sql (só depois de remover todas as capacidades
              protegidas, que dependem da porta).
Como validar: harness 5895 (G2, em ensaio); prova com JWT real em G3/G4.
================================================================
*/

begin;
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

commit;
