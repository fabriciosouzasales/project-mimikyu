/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5394 - Histórico por coleção da Pokédex: estrutura, primitivas de
              registro explícito e captura derivada (V1-13 · E3-6 / S4-a, D-E3-8)
Versão......: 1.1 (2026-11-27, `FINAL EXECUTOR GATE & TRIGGER SAFETY REVIEW-01`:
              captura derivada inerte com a barreira CLOSED)
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core (qjfutqujxrbzgrtkpgkg)
              em 2026-11-27 13:35:15Z pelo executor por arquivo v1.4, papel postgres,
              manifesto 24d7d8a6…17ad, expectativas 6351fb71…dd13: PRE PASS (inventário
              e dependência da 5391 conferidos), migration exit 0 (transação única),
              POST PASS (9 funções, 7 gatilhos, sem eventos, escritores_md5 = PRE).
              Do `begin;` ao `commit;` idêntica à proposta (só este bloco difere).
              Barreira CLOSED: captura inerte. Provas funcionais e de desempenho
              NÃO executadas (TEST/E4).
Autor.......: Fabrício Sales / Claude
Cria........: tabela collection_activity_event (interna); primitivas internas
              collection_activity_open(uuid) e collection_activity_record_pokedex(...);
              ajudante interno collection_activity_derived_add(...); guarda de
              imutabilidade; 6 gatilhos de captura derivada (atribuição INSERT/DELETE,
              representante INSERT/UPDATE/DELETE, alocação BEFORE DELETE).
Inércia.....: a captura derivada só registra quando a capacidade está aberta para a
              sessão (v1_13_capability_open: OPEN, ou TEST com identidade registrada) ou,
              sem sessão, com a barreira OPEN. Com a barreira CLOSED nada é registrado (as
              funções do titular, alocar e desalocar seguem como hoje); o registro
              explícito só é alcançável pelas RPCs do EDITOR, recusadas pela barreira.
Regra.......: toda mudança de posição ou representante da Pokédex fica registrada
              na MESMA transação: (a) explicitamente, pelas escritas que chamam
              open() antes e record() depois (5392; titular a partir da 5395); ou
              (b) derivadamente, por gatilho, num único evento agregado
              POKEDEX_POSITIONS_CHANGED por coleção e transação (alocar, desalocar,
              funções do titular ainda não instrumentadas). Nunca as duas para a
              mesma mudança.
Não toca....: nenhuma função existente (titular 6122–6126, 5046, 5047, 6119, 5380):
              corpos conferidos antes e depois; nenhuma linha de dado existente.
Travas......: lock_timeout 3 s; LOCK … SHARE ROW EXCLUSIVE NOWAIT em
              collection_allocation, collection_pokedex_position_assignment e
              collection_pokedex_position_primary_representative antes dos gatilhos.
Reversão....: ROLLBACK_5394.sql (recusa com a 5392 presente ou com eventos gravados).
Como validar: static_check_5394.py; PRE/POST somente leitura; provas funcionais
              no TEST autorizado.
================================================================
*/

begin;
set local lock_timeout = '3s';

do $pre$
begin
  if to_regprocedure('public.v1_13_assert_capability()') is null
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_assert_capability()')) is distinct from 'e4f710904f50e6e8c3f1d8e2337639e0'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_capability_open()')) is distinct from '32e2f636361732b497e8401e50f0bbe0'
     or (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'CLOSED'
     or (select count(*) from public.v1_13_barrier_identity) <> 0 then
    raise exception 'PRECHECK 5394: barreira ausente, divergente ou não CLOSED';
  end if;
  -- Escritores conhecidos das tabelas da Pokédex com o corpo canônico (titular).
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_pokedex_position_assignment(uuid, uuid, boolean)')) is distinct from '8c572182a03025503e993e5ecc25e07a'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.remove_pokedex_position_assignment(uuid)')) is distinct from '26ef2d5da3312661111df0194dfc8ba2'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_pokedex_position_primary_representative(uuid)')) is distinct from '6353dffe6c3877967997033dcc2bfd4c'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.clear_pokedex_position_primary_representative(uuid, uuid)')) is distinct from 'eeede3a5b871fbf07f81eb59ecea932f' then
    raise exception 'PRECHECK 5394: ESTADO DIVERGENTE — funções do titular da Pokédex diferem de 6123/6124/6126/6125';
  end if;
  if to_regclass('public.collection_allocation') is null
     or to_regclass('public.collection_pokedex_position_assignment') is null
     or to_regclass('public.collection_pokedex_position_primary_representative') is null
     or to_regclass('public.collection_membership') is null then
    raise exception 'PRECHECK 5394: dependências ausentes';
  end if;
  if to_regclass('public.collection_activity_event') is not null
     or exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                where n.nspname = 'public' and p.proname like 'collection_activity\_%')
     or exists (select 1 from pg_catalog.pg_trigger t where not t.tgisinternal and t.tgname like 'trg\_9__\_collection\_activity\_%') then
    raise exception 'PRECHECK 5394: JÁ APLICADA ou ESTADO DIVERGENTE';
  end if;
  -- Retrato dos corpos das funções que escrevem nas tabelas envolvidas (comparado no postcheck).
  perform set_config('mmkyu.s4a_5394_writers',
    (select md5(string_agg(p.proname || ':' || md5(p.prosrc), ';' order by p.proname, p.oid))
     from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('allocate_physical_cards_to_collection', 'deallocate_physical_cards_from_collection',
                         'auto_assign_pokedex_position_species_match', 'set_pokedex_position_assignment',
                         'remove_pokedex_position_assignment', 'set_pokedex_position_primary_representative',
                         'clear_pokedex_position_primary_representative', 'editor_set_pokedex_position_assignment',
                         'editor_remove_pokedex_position_assignment', 'editor_set_pokedex_position_primary_representative',
                         'editor_clear_pokedex_position_primary_representative')), true);
end;
$pre$;

-- Ordem: alocação → atribuição → representante (mesma ordem das escritas existentes).
lock table public.collection_allocation in share row exclusive mode nowait;
lock table public.collection_pokedex_position_assignment in share row exclusive mode nowait;
lock table public.collection_pokedex_position_primary_representative in share row exclusive mode nowait;

create table public.collection_activity_event (
  id            bigint      generated always as identity primary key,
  collection_id uuid        not null references public.collection (id) on update restrict on delete cascade,
  owner_user_id uuid        not null references auth.users (id) on update restrict on delete cascade,
  occurred_at   timestamptz not null default now(),
  actor_user_id uuid        null,   -- valor, sem FK (padrão B1 da 5267); nome público resolvido na leitura (C-241)
  actor_role    text        not null,
  origin        text        not null,
  event_type    text        not null,
  summary       jsonb       not null default '{}'::jsonb,
  constraint chk_cae_actor_role check (actor_role in ('OWNER', 'EDITOR', 'SYSTEM')),
  constraint chk_cae_actor check ((actor_role = 'SYSTEM') = (actor_user_id is null)),
  constraint chk_cae_origin check (origin in ('EXPLICIT', 'DERIVED')),
  constraint chk_cae_event_type check (event_type in (
    'POKEDEX_POSITION_ASSIGNED', 'POKEDEX_POSITION_MOVED', 'POKEDEX_POSITION_REMOVED',
    'POKEDEX_REPRESENTATIVE_SET', 'POKEDEX_REPRESENTATIVE_REPLACED', 'POKEDEX_REPRESENTATIVE_RESTORED',
    'POKEDEX_POSITIONS_CHANGED')),
  constraint chk_cae_origin_type check ((origin = 'DERIVED') = (event_type = 'POKEDEX_POSITIONS_CHANGED')),
  constraint chk_cae_explicit_actor check (origin = 'DERIVED' or actor_role <> 'SYSTEM'),
  constraint chk_cae_summary check (jsonb_typeof(summary) = 'object' and octet_length(summary::text) <= 2048)
);
create index ix_cae_collection_time on public.collection_activity_event (collection_id, occurred_at desc, id desc);
create index ix_cae_owner on public.collection_activity_event (owner_user_id);
alter table public.collection_activity_event enable row level security;

-- Imutável: só o evento derivado da PRÓPRIA transação pode ter as contagens acumuladas.
create function public.collection_activity_event_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_map jsonb := coalesce(nullif(current_setting('mmkyu.collection_activity_derived', true), '')::jsonb, '{}'::jsonb);
begin
  if old.origin = 'DERIVED'
     and (v_map ->> old.collection_id::text) = old.id::text
     and (new.id, new.collection_id, new.owner_user_id, new.occurred_at, new.actor_user_id, new.actor_role, new.origin, new.event_type)
         is not distinct from
         (old.id, old.collection_id, old.owner_user_id, old.occurred_at, old.actor_user_id, old.actor_role, old.origin, old.event_type) then
    return new;
  end if;
  raise exception 'COLLECTION_ACTIVITY_IMMUTABLE' using errcode = '55000';
end;
$fn$;

create trigger trg_900_collection_activity_event_guard
before update on public.collection_activity_event
for each row execute function public.collection_activity_event_guard();

-- Marca a transação ANTES de escrever (os gatilhos de instrução disparam ao fim de cada DELETE/INSERT).
create function public.collection_activity_open(p_collection_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_cur text := nullif(current_setting('mmkyu.collection_activity_explicit', true), '');
begin
  if p_collection_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  if v_cur is not null and v_cur <> p_collection_id::text then
    raise exception 'COLLECTION_ACTIVITY_NESTED' using errcode = '55000';
  end if;
  perform set_config('mmkyu.collection_activity_explicit', p_collection_id::text, true);
end;
$fn$;

-- Registro explícito de UMA operação efetiva. Autor e papel derivados no servidor;
-- resumo montado aqui, só com dados de catálogo e organização da coleção.
create function public.collection_activity_record_pokedex(
  p_collection_id          uuid,
  p_event_type             text,
  p_allocation_id          uuid,
  p_from_position_id       uuid,
  p_to_position_id         uuid,
  p_previous_allocation_id uuid,
  p_basis                  text,
  p_representative_cleared boolean
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_uid   uuid := (select auth.uid());
  v_owner uuid;
  v_role  text;
  v_dex   uuid;
  v_card  jsonb;
  v_prev  jsonb;
  v_from  jsonb;
  v_to    jsonb;
  v_sum   jsonb;
  v_id    bigint;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null
     or nullif(current_setting('mmkyu.collection_activity_explicit', true), '') is distinct from p_collection_id::text then
    raise exception 'COLLECTION_ACTIVITY_NOT_OPEN' using errcode = '55000';
  end if;

  select c.owner_user_id, cpr.pokedex_id into v_owner, v_dex
  from public.collection c
  join public.collection_reference cr on cr.collection_id = c.id and cr.reference_kind = 'POKEDEX'
  join public.collection_pokedex_reference cpr on cpr.collection_reference_id = cr.id
  where c.id = p_collection_id;
  if v_owner is null then
    raise exception 'COLLECTION_ACTIVITY_NOT_POKEDEX' using errcode = '22023';
  end if;
  if v_uid = v_owner then
    v_role := 'OWNER';
  elsif exists (select 1 from public.collection_membership m
                where m.collection_id = p_collection_id and m.user_id = v_uid
                  and m.status = 'ACTIVE' and m.role = 'EDITOR') then
    v_role := 'EDITOR';
  else
    raise exception 'COLLECTION_ACTIVITY_ACTOR_NOT_AUTHORIZED' using errcode = '42501';
  end if;

  if p_allocation_id is not null then
    select jsonb_strip_nulls(jsonb_build_object(
             'name', k.name, 'number', k.collector_number, 'set', cs.code,
             'variant', nullif(concat_ws(' · ', vt.name, ppf.name, ecx.name), '')))
      into v_card
    from public.collection_allocation ca
    join public.physical_card pc                      on pc.id = ca.physical_card_id
    join public.card_variant cv                       on cv.id = pc.card_variant_id
    join public.card k                                on k.id = cv.card_id
    join public.card_set cs                           on cs.id = k.card_set_id
    left join public.card_variant_type vt             on vt.id = cv.variant_type_id
    left join public.card_printing_profile ppf        on ppf.id = cv.printing_profile_id
    left join public.card_edition_context_profile ecx on ecx.id = cv.edition_context_profile_id
    where ca.id = p_allocation_id and ca.collection_id = p_collection_id;
    if v_card is null then
      raise exception 'COLLECTION_ACTIVITY_INVALID_EVENT' using errcode = '22023';
    end if;
  end if;
  if p_previous_allocation_id is not null then
    select jsonb_strip_nulls(jsonb_build_object(
             'name', k.name, 'number', k.collector_number, 'set', cs.code,
             'variant', nullif(concat_ws(' · ', vt.name, ppf.name, ecx.name), '')))
      into v_prev
    from public.collection_allocation ca
    join public.physical_card pc                      on pc.id = ca.physical_card_id
    join public.card_variant cv                       on cv.id = pc.card_variant_id
    join public.card k                                on k.id = cv.card_id
    join public.card_set cs                           on cs.id = k.card_set_id
    left join public.card_variant_type vt             on vt.id = cv.variant_type_id
    left join public.card_printing_profile ppf        on ppf.id = cv.printing_profile_id
    left join public.card_edition_context_profile ecx on ecx.id = cv.edition_context_profile_id
    where ca.id = p_previous_allocation_id and ca.collection_id = p_collection_id;
    if v_prev is null then
      raise exception 'COLLECTION_ACTIVITY_INVALID_EVENT' using errcode = '22023';
    end if;
  end if;
  if p_from_position_id is not null then
    select jsonb_build_object('number', pp.position_number, 'species', s.canonical_name) into v_from
    from public.pokedex_position pp join public.pokemon_species s on s.id = pp.species_id
    where pp.id = p_from_position_id and pp.pokedex_id = v_dex;
    if v_from is null then
      raise exception 'COLLECTION_ACTIVITY_INVALID_EVENT' using errcode = '22023';
    end if;
  end if;
  if p_to_position_id is not null then
    select jsonb_build_object('number', pp.position_number, 'species', s.canonical_name) into v_to
    from public.pokedex_position pp join public.pokemon_species s on s.id = pp.species_id
    where pp.id = p_to_position_id and pp.pokedex_id = v_dex;
    if v_to is null then
      raise exception 'COLLECTION_ACTIVITY_INVALID_EVENT' using errcode = '22023';
    end if;
  end if;
  if p_basis is not null and p_basis not in ('SPECIES_MATCH', 'USER_OVERRIDE') then
    raise exception 'COLLECTION_ACTIVITY_INVALID_EVENT' using errcode = '22023';
  end if;

  -- Parâmetros exigidos e proibidos por tipo (lista fechada de chaves no resumo).
  v_sum := case p_event_type
    when 'POKEDEX_POSITION_ASSIGNED' then
      case when v_card is not null and v_to is not null and v_from is null and v_prev is null and p_basis is not null
           then jsonb_build_object('to', v_to, 'card', v_card, 'basis', p_basis) end
    when 'POKEDEX_POSITION_MOVED' then
      case when v_card is not null and v_to is not null and v_from is not null and v_prev is null and p_basis is not null
                and p_representative_cleared is not null and p_from_position_id <> p_to_position_id
           then jsonb_build_object('from', v_from, 'to', v_to, 'card', v_card, 'basis', p_basis,
                                   'representative_cleared', p_representative_cleared) end
    when 'POKEDEX_POSITION_REMOVED' then
      case when v_card is not null and v_from is not null and v_to is null and v_prev is null and p_basis is null
                and p_representative_cleared is not null
           then jsonb_build_object('from', v_from, 'card', v_card, 'representative_cleared', p_representative_cleared) end
    when 'POKEDEX_REPRESENTATIVE_SET' then
      case when v_card is not null and v_to is not null and v_from is null and v_prev is null and p_basis is null
           then jsonb_build_object('position', v_to, 'card', v_card) end
    when 'POKEDEX_REPRESENTATIVE_REPLACED' then
      case when v_card is not null and v_to is not null and v_from is null and v_prev is not null and p_basis is null
                and p_allocation_id <> p_previous_allocation_id
           then jsonb_build_object('position', v_to, 'card', v_card, 'previous_card', v_prev) end
    when 'POKEDEX_REPRESENTATIVE_RESTORED' then
      case when v_card is null and v_to is not null and v_from is null and v_prev is not null and p_basis is null
           then jsonb_build_object('position', v_to, 'previous_card', v_prev) end
  end;
  if v_sum is null then
    raise exception 'COLLECTION_ACTIVITY_INVALID_EVENT' using errcode = '22023';
  end if;

  insert into public.collection_activity_event
    (collection_id, owner_user_id, actor_user_id, actor_role, origin, event_type, summary)
  values (p_collection_id, v_owner, v_uid, v_role, 'EXPLICIT', p_event_type, v_sum)
  returning id into v_id;
  -- Um evento por operação: a marcação é consumida.
  perform set_config('mmkyu.collection_activity_explicit', '', true);
  return v_id;
end;
$fn$;

-- Acumula contagens num único evento derivado por coleção e transação.
create function public.collection_activity_derived_add(
  p_collection_id uuid, p_assigned integer, p_removed integer, p_rep_set integer, p_rep_cleared integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_map   jsonb := coalesce(nullif(current_setting('mmkyu.collection_activity_derived', true), '')::jsonb, '{}'::jsonb);
  v_id    bigint;
  v_uid   uuid := (select auth.uid());
  v_owner uuid;
  v_role  text;
  v_actor uuid;
begin
  -- Inerte enquanto a capacidade estiver fechada para a sessão (barreira CLOSED, ou TEST sem
  -- identidade registrada); sem sessão, só com a barreira OPEN (eventos SYSTEM).
  if not public.v1_13_capability_open()
     and ((select auth.uid()) is not null
          or (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'OPEN') then
    return;
  end if;
  if p_collection_id is null or coalesce(p_assigned, 0) + coalesce(p_removed, 0) + coalesce(p_rep_set, 0) + coalesce(p_rep_cleared, 0) = 0 then
    return;
  end if;
  v_id := (v_map ->> p_collection_id::text)::bigint;
  if v_id is not null then
    update public.collection_activity_event e
    set summary = jsonb_build_object(
          'assigned',                coalesce((e.summary ->> 'assigned')::integer, 0) + coalesce(p_assigned, 0),
          'removed',                 coalesce((e.summary ->> 'removed')::integer, 0) + coalesce(p_removed, 0),
          'representatives_set',     coalesce((e.summary ->> 'representatives_set')::integer, 0) + coalesce(p_rep_set, 0),
          'representatives_cleared', coalesce((e.summary ->> 'representatives_cleared')::integer, 0) + coalesce(p_rep_cleared, 0))
    where e.id = v_id;
    return;
  end if;
  select c.owner_user_id into v_owner from public.collection c where c.id = p_collection_id;
  if v_owner is null then
    return;
  end if;
  if v_uid is not null and v_uid = v_owner then
    v_role := 'OWNER'; v_actor := v_uid;
  elsif v_uid is not null and exists (select 1 from public.collection_membership m
                                      where m.collection_id = p_collection_id and m.user_id = v_uid
                                        and m.status = 'ACTIVE' and m.role = 'EDITOR') then
    v_role := 'EDITOR'; v_actor := v_uid;
  else
    v_role := 'SYSTEM'; v_actor := null;
  end if;
  insert into public.collection_activity_event
    (collection_id, owner_user_id, actor_user_id, actor_role, origin, event_type, summary)
  values (p_collection_id, v_owner, v_actor, v_role, 'DERIVED', 'POKEDEX_POSITIONS_CHANGED',
          jsonb_build_object('assigned', coalesce(p_assigned, 0), 'removed', coalesce(p_removed, 0),
                             'representatives_set', coalesce(p_rep_set, 0), 'representatives_cleared', coalesce(p_rep_cleared, 0)))
  returning id into v_id;
  perform set_config('mmkyu.collection_activity_derived', (v_map || jsonb_build_object(p_collection_id::text, v_id))::text, true);
end;
$fn$;

-- Captura derivada (uma função por gatilho: cada uma lê só a própria tabela de transição).
create function public.collection_activity_capture_assignment_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_explicit text := nullif(current_setting('mmkyu.collection_activity_explicit', true), '');
  r record;
begin
  -- Inerte enquanto a capacidade estiver fechada para a sessão (barreira CLOSED, ou TEST sem
  -- identidade registrada); sem sessão, só com a barreira OPEN (eventos SYSTEM).
  if not public.v1_13_capability_open()
     and ((select auth.uid()) is not null
          or (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'OPEN') then
    return null;
  end if;
  for r in
    select ca.collection_id as cid, count(*)::integer as n
    from new_rows nr join public.collection_allocation ca on ca.id = nr.collection_allocation_id
    group by ca.collection_id
  loop
    if r.cid::text is distinct from v_explicit then
      perform public.collection_activity_derived_add(r.cid, r.n, 0, 0, 0);
    end if;
  end loop;
  return null;
end;
$fn$;

-- Remoções diretas (retirar/mover). Remoções em cascata da desalocação não acham a alocação
-- (já apagada) e são contadas pelo gatilho BEFORE DELETE da alocação.
create function public.collection_activity_capture_assignment_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_explicit text := nullif(current_setting('mmkyu.collection_activity_explicit', true), '');
  r record;
begin
  -- Inerte enquanto a capacidade estiver fechada para a sessão (barreira CLOSED, ou TEST sem
  -- identidade registrada); sem sessão, só com a barreira OPEN (eventos SYSTEM).
  if not public.v1_13_capability_open()
     and ((select auth.uid()) is not null
          or (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'OPEN') then
    return null;
  end if;
  for r in
    select ca.collection_id as cid, count(*)::integer as n
    from old_rows o join public.collection_allocation ca on ca.id = o.collection_allocation_id
    group by ca.collection_id
  loop
    if r.cid::text is distinct from v_explicit then
      perform public.collection_activity_derived_add(r.cid, 0, r.n, 0, 0);
    end if;
  end loop;
  return null;
end;
$fn$;

create function public.collection_activity_capture_representative_set()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_explicit text := nullif(current_setting('mmkyu.collection_activity_explicit', true), '');
  r record;
begin
  -- Inerte enquanto a capacidade estiver fechada para a sessão (barreira CLOSED, ou TEST sem
  -- identidade registrada); sem sessão, só com a barreira OPEN (eventos SYSTEM).
  if not public.v1_13_capability_open()
     and ((select auth.uid()) is not null
          or (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'OPEN') then
    return null;
  end if;
  for r in select nr.collection_id as cid, count(*)::integer as n from new_rows nr group by nr.collection_id loop
    if r.cid::text is distinct from v_explicit then
      perform public.collection_activity_derived_add(r.cid, 0, 0, r.n, 0);
    end if;
  end loop;
  return null;
end;
$fn$;

create function public.collection_activity_capture_representative_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_explicit text := nullif(current_setting('mmkyu.collection_activity_explicit', true), '');
  r record;
begin
  -- Inerte enquanto a capacidade estiver fechada para a sessão (barreira CLOSED, ou TEST sem
  -- identidade registrada); sem sessão, só com a barreira OPEN (eventos SYSTEM).
  if not public.v1_13_capability_open()
     and ((select auth.uid()) is not null
          or (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'OPEN') then
    return null;
  end if;
  for r in select o.collection_id as cid, count(*)::integer as n from old_rows o group by o.collection_id loop
    if r.cid::text is distinct from v_explicit then
      perform public.collection_activity_derived_add(r.cid, 0, 0, 0, r.n);
    end if;
  end loop;
  return null;
end;
$fn$;

-- Desalocação: conta a atribuição que vai cair em cascata (a representante é contada pelo
-- gatilho da própria tabela, que tem collection_id).
create function public.collection_activity_capture_deallocation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  -- Inerte enquanto a capacidade estiver fechada para a sessão (barreira CLOSED, ou TEST sem
  -- identidade registrada); sem sessão, só com a barreira OPEN (eventos SYSTEM).
  if not public.v1_13_capability_open()
     and ((select auth.uid()) is not null
          or (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'OPEN') then
    return old;
  end if;
  if exists (select 1 from public.collection_pokedex_position_assignment a where a.collection_allocation_id = old.id)
     and old.collection_id::text is distinct from nullif(current_setting('mmkyu.collection_activity_explicit', true), '') then
    perform public.collection_activity_derived_add(old.collection_id, 0, 1, 0, 0);
  end if;
  return old;
end;
$fn$;

create trigger trg_900_collection_activity_assignment_insert
after insert on public.collection_pokedex_position_assignment
referencing new table as new_rows
for each statement execute function public.collection_activity_capture_assignment_insert();

create trigger trg_900_collection_activity_assignment_delete
after delete on public.collection_pokedex_position_assignment
referencing old table as old_rows
for each statement execute function public.collection_activity_capture_assignment_delete();

create trigger trg_900_collection_activity_representative_insert
after insert on public.collection_pokedex_position_primary_representative
referencing new table as new_rows
for each statement execute function public.collection_activity_capture_representative_set();

create trigger trg_900_collection_activity_representative_update
after update on public.collection_pokedex_position_primary_representative
referencing new table as new_rows
for each statement execute function public.collection_activity_capture_representative_set();

create trigger trg_900_collection_activity_representative_delete
after delete on public.collection_pokedex_position_primary_representative
referencing old table as old_rows
for each statement execute function public.collection_activity_capture_representative_delete();

create trigger trg_900_collection_activity_deallocation
before delete on public.collection_allocation
for each row execute function public.collection_activity_capture_deallocation();

comment on table public.collection_activity_event is
  'V1-13 E3-6/S4-a (5394, interna): histórico por coleção da Pokédex (D-E3-8). EXPLICIT = uma operação efetiva registrada pela própria escrita; DERIVED = mudanças sem registro explícito, agregadas por coleção e transação. Só catálogo e organização; nunca exemplar, alocação, local, condição ou valores. Leitura só por funções.';
comment on function public.collection_activity_record_pokedex(uuid, text, uuid, uuid, uuid, uuid, text, boolean) is
  'V1-13 E3-6/S4-a (5394, interna): registra UMA operação efetiva de posição/representante da Pokédex, na transação da escrita, depois de collection_activity_open(). Autor = auth.uid(); papel derivado (titular ou EDITOR ACTIVE); resumo montado no servidor.';

revoke all on table public.collection_activity_event from public, anon, authenticated, service_role;
revoke all on function public.collection_activity_event_guard() from public, anon, authenticated, service_role;
revoke all on function public.collection_activity_open(uuid) from public, anon, authenticated, service_role;
revoke all on function public.collection_activity_record_pokedex(uuid, text, uuid, uuid, uuid, uuid, text, boolean) from public, anon, authenticated, service_role;
revoke all on function public.collection_activity_derived_add(uuid, integer, integer, integer, integer) from public, anon, authenticated, service_role;
revoke all on function public.collection_activity_capture_assignment_insert() from public, anon, authenticated, service_role;
revoke all on function public.collection_activity_capture_assignment_delete() from public, anon, authenticated, service_role;
revoke all on function public.collection_activity_capture_representative_set() from public, anon, authenticated, service_role;
revoke all on function public.collection_activity_capture_representative_delete() from public, anon, authenticated, service_role;
revoke all on function public.collection_activity_capture_deallocation() from public, anon, authenticated, service_role;

do $post$
declare
  f oid;
begin
  for f in select p.oid from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname like 'collection_activity\_%' loop
    if (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
       or (select p.proconfig from pg_catalog.pg_proc p where p.oid = f) is distinct from array['search_path=""']
       or exists (select 1 from pg_catalog.pg_roles x where x.rolname in ('anon', 'authenticated', 'service_role', 'authenticator')
                  and pg_catalog.has_function_privilege(x.oid, f, 'EXECUTE'))
       or exists (select 1 from pg_catalog.pg_proc p cross join lateral pg_catalog.aclexplode(p.proacl) a
                  where p.oid = f and a.grantee = 0) then
      raise exception 'POSTCHECK 5394: função fora do estado esperado (%)', f::regprocedure;
    end if;
  end loop;
  if (select count(*) from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname like 'collection_activity\_%') <> 9 then
    raise exception 'POSTCHECK 5394: conjunto de funções inesperado';
  end if;
  if (select c.relrowsecurity from pg_catalog.pg_class c where c.oid = 'public.collection_activity_event'::regclass) is not true
     or exists (select 1 from pg_catalog.pg_roles x where x.rolname in ('anon', 'authenticated', 'service_role', 'authenticator')
                and (pg_catalog.has_table_privilege(x.oid, 'public.collection_activity_event', 'SELECT')
                     or pg_catalog.has_table_privilege(x.oid, 'public.collection_activity_event', 'INSERT')
                     or pg_catalog.has_table_privilege(x.oid, 'public.collection_activity_event', 'UPDATE')
                     or pg_catalog.has_table_privilege(x.oid, 'public.collection_activity_event', 'DELETE'))) then
    raise exception 'POSTCHECK 5394: tabela exposta à API';
  end if;
  if (select count(*) from pg_catalog.pg_trigger t
      where not t.tgisinternal and t.tgenabled = 'O' and t.tgname like 'trg\_900\_collection\_activity\_%'
        and t.tgrelid in ('public.collection_activity_event'::regclass, 'public.collection_allocation'::regclass,
                          'public.collection_pokedex_position_assignment'::regclass,
                          'public.collection_pokedex_position_primary_representative'::regclass)) <> 7 then
    raise exception 'POSTCHECK 5394: gatilhos ausentes ou desabilitados';
  end if;
  if exists (select 1 from public.collection_activity_event) then
    raise exception 'POSTCHECK 5394: a migration não deveria gerar eventos';
  end if;
  if (select md5(string_agg(p.proname || ':' || md5(p.prosrc), ';' order by p.proname, p.oid))
      from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname in ('allocate_physical_cards_to_collection', 'deallocate_physical_cards_from_collection',
                          'auto_assign_pokedex_position_species_match', 'set_pokedex_position_assignment',
                          'remove_pokedex_position_assignment', 'set_pokedex_position_primary_representative',
                          'clear_pokedex_position_primary_representative', 'editor_set_pokedex_position_assignment',
                          'editor_remove_pokedex_position_assignment', 'editor_set_pokedex_position_primary_representative',
                          'editor_clear_pokedex_position_primary_representative'))
     is distinct from current_setting('mmkyu.s4a_5394_writers', true) then
    raise exception 'POSTCHECK 5394: funções escritoras alteradas';
  end if;
  if (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'CLOSED'
     or (select count(*) from public.v1_13_barrier_identity) <> 0 then
    raise exception 'POSTCHECK 5394: barreira não está CLOSED';
  end if;
end;
$post$;

commit;
