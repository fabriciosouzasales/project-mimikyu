/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5396 - Auditoria das referências de espécie no histórico do fichário
              (V1-13 · E3-6 / S4-c, D-E3-8, D-5395-1, D-5396-1, D-5396-2)
Versão......: 1.2 (2026-11-27, `S4-c/5396 SQLSTATE 22P02 ROOT CAUSE & CORRECTION-01`: postcheck com
              pertencimento tipado ao proconfig); 1.1: HISTORY VISIBILITY & CONTRACT CORRECTION-01;
              1.0: PREPARATION-01. Tentativa 1.1 → STOP-LIVE (run-20261127T151841Z).
Status......: PROPOSTA — NÃO EXECUTADA. GERADA por build_5396.py a partir do texto canônico
              implantado. Execução só com PRE aprovado, expectativas de escritores,
              auditoria independente e autorização expressa, pelo executor por arquivo.
Autor.......: Fabrício Sales / Claude
Altera......: CREATE OR REPLACE de 10 funções, com o texto implantado + blocos [5396+]…[5396-]
              (inserções) e linhas marcadas [5396~] (substituições declaradas no gerador):
              - 3 do titular (5258) e 3 do EDITOR (5383 G1) — aplicar, remover, mostrar/ocultar:
                chamam binder_activity_record_species depois da escrita efetiva; titular só com
                v1_13_capability_open() (CLOSED → caminho de hoje); EDITOR sempre (barreira já
                exigida no início da função);
              - binder_activity_category (5341): + categoria SPECIES;
              - binder_activity_event_editor_type_guard (5384): o EDITOR pode gravar os 4 tipos;
              - get_my_binder_activity (5269): filtro aceita SPECIES (D-5396-2);
              - get_shared_binder_activity (5388 R1): eventos SPECIES de X para titular e
                participantes ACTIVE, sem itens e sem summary (D-5396-1).
              chk_bae_event_type (5267/5341): + 4 tipos — por ÚLTIMO, para o ACCESS EXCLUSIVE
              ficar o menor tempo possível antes do commit.
Cria........: binder_activity_record_species(uuid, uuid, text, integer) — interna, sem EXECUTE
              para a API: um evento por operação efetiva, sem itens, autor e resumo derivados.
Não altera..: get_shared_binder_activity_status, demais funções 5258/5269/5383, 5394/5395.
Reversão....: ROLLBACK_5396.sql (restaura o canônico; nunca apaga eventos; mantém o CHECK
              ampliado se já houver eventos SPECIES_*).
================================================================
*/

begin;
set local lock_timeout = '3s';

do $pre$
begin
  if (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'CLOSED'
     or (select count(*) from public.v1_13_barrier_identity) <> 0 then
    raise exception 'PRECHECK 5396: barreira não está CLOSED';
  end if;
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.apply_my_binder_species_references(uuid, text)')) is distinct from '1fc0bbcbb88ef4722478cbd74db996c2'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.clear_my_binder_species_references(uuid, integer)')) is distinct from '723724fb7d47c135021ffe3c2cac3d1c'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_my_binder_species_reference_visibility(uuid, boolean)')) is distinct from 'bf3385f8ddb943581a19a0502b40b8c7'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_apply_binder_species_references(uuid, text)')) is distinct from '54d14043bc2826f687867c60c241db1f'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_clear_binder_species_references(uuid, integer)')) is distinct from 'dcc32db55aef7978b37c4ba1dc55f44b'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_set_binder_species_reference_visibility(uuid, boolean)')) is distinct from '0a1955ff43cdc3a3b23f87bf38efa42d'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.binder_activity_event_editor_type_guard()')) is distinct from '78fa0d34dad161eac1165f3143874260'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.binder_activity_category(text)')) is distinct from 'a7f9f99fa1f98171897904ed6d380bc4'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.get_my_binder_activity(uuid, text[], timestamptz, bigint, integer)')) is distinct from 'fab40eb28280d7c62ca207642b35ff65'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.get_shared_binder_activity(uuid, text[], timestamptz, bigint, integer)')) is distinct from '5b2887919ed00aca98b20d048f10722b' then
    raise exception 'PRECHECK 5396: ESTADO DIVERGENTE — funções diferem do canônico (5258/5383/5384/5341/5269/5388)';
  end if;
  if (select array_agg(m.v[1] order by m.v[1] collate "C") from pg_catalog.pg_constraint k cross join lateral regexp_matches(pg_catalog.pg_get_constraintdef(k.oid), '''([A-Z0-9_]+)''', 'g') as m(v) where k.conrelid = 'public.binder_activity_event'::regclass and k.conname = 'chk_bae_event_type') is distinct from array['BINDER_ASSEMBLED', 'BINDER_DELETED_EMPTY', 'BINDER_DISMANTLED', 'BINDER_OWNERSHIP_TRANSFERRED', 'CARDS_AUTO_ARRANGED', 'CARDS_LEFT_BY_COLLECTION_STORAGE', 'CARDS_LEFT_BY_STORAGE', 'CARDS_REMOVED', 'CARDS_SWAPPED', 'CARD_LEFT_BY_INVENTORY_EXIT', 'CARD_MOVED', 'CARD_PLACED', 'CATALOG_NOVELTIES_INCORPORATED', 'COLLECTION_ATTACHED', 'COLLECTION_DETACHED', 'GAP_CLOSED', 'GAP_OPENED', 'LEGACY_CATALOG_INCORPORATION', 'PAGES_ADDED', 'PAGES_REORDERED', 'PAGE_REMOVED', 'POCKETS_LOCKED', 'POCKETS_UNLOCKED', 'POCKET_RESERVED', 'RESERVATIONS_RELEASED']::text[] then
    raise exception 'PRECHECK 5396: chk_bae_event_type difere da 5341';
  end if;
  if not pg_catalog.pg_has_role(current_user, (select c.relowner from pg_catalog.pg_class c where c.oid = 'public.binder_activity_event'::regclass), 'USAGE') then
    raise exception 'PRECHECK 5396: executor não é dono de binder_activity_event';
  end if;
  if to_regprocedure('public.binder_activity_record_species(uuid, uuid, text, integer)') is not null then
    raise exception 'PRECHECK 5396: JÁ APLICADA ou ESTADO DIVERGENTE';
  end if;
end;
$pre$;

create function public.binder_activity_record_species(
  p_layout_id     uuid,
  p_collection_id uuid,
  p_event_type    text,
  p_removed_count integer
)
returns bigint
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_uid      uuid := (select auth.uid());
  v_ctx      jsonb := nullif(current_setting('mmkyu.binder_activity_ctx', true), '')::jsonb;
  v_owner    uuid;
  v_main     uuid;
  v_binder   text;
  v_collname text;
  v_visible  boolean;
  v_n        integer;
  v_first    integer;
  v_last     integer;
  v_sum      jsonb;
  v_id       bigint;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_layout_id is null or p_collection_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  -- Operação de referências nunca é aninhada numa operação de fichário aberta (5268).
  if v_ctx is not null and (v_ctx ->> 'depth')::integer > 0 then
    raise exception 'binder activity: species event inside an open operation' using errcode = 'P0001',
      hint = 'BINDER_ACTIVITY_NESTED_SPECIES';
  end if;

  -- Titular = dono do fichário agora; coleção = a dona do fichário ou convidada do mesmo titular.
  select c.owner_user_id, l.collection_id, coalesce(nullif(l.display_name, ''), c.name)
    into v_owner, v_main, v_binder
  from public.collection_layout l
  join public.collection c on c.id = l.collection_id
  where l.id = p_layout_id;
  if v_owner is null then
    raise exception 'binder activity: binder not found' using errcode = 'P0002', hint = 'BINDER_ACTIVITY_LAYOUT_NOT_FOUND';
  end if;
  select c.name into v_collname
  from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_owner
    and (c.id = v_main or exists (select 1 from public.collection_layout_guest g
                                  where g.layout_id = p_layout_id and g.collection_id = c.id));
  if v_collname is null then
    raise exception 'binder activity: collection not in binder' using errcode = '42501', hint = 'BINDER_ACTIVITY_SPECIES_COLLECTION';
  end if;
  -- Autor derivado no servidor: o titular, ou EDITOR ativo da coleção dona do fichário.
  if v_uid <> v_owner
     and not (p_collection_id = v_main
              and exists (select 1 from public.collection_membership m
                          where m.collection_id = p_collection_id and m.user_id = v_uid
                            and m.status = 'ACTIVE' and m.role = 'EDITOR')) then
    raise exception 'binder activity: actor not authorized' using errcode = '42501', hint = 'BINDER_ACTIVITY_NOT_OWNER';
  end if;

  select st.references_visible into v_visible
  from public.collection_layout_species_reference_setting st where st.layout_id = p_layout_id;
  v_visible := coalesce(v_visible, true);

  -- Resumo montado aqui, a partir do estado gravado: só contagens e números nacionais.
  if p_event_type = 'SPECIES_REFERENCES_APPLIED' and p_removed_count is null then
    select count(*)::integer, min(pp.position_number), max(pp.position_number) into v_n, v_first, v_last
    from public.collection_layout_slot_species_reference r
    join public.pokedex_position pp on pp.id = r.pokedex_position_id
    where r.layout_id = p_layout_id and r.collection_id = p_collection_id;
    if v_n > 0 and v_visible then
      v_sum := jsonb_build_object('reference_count', v_n, 'first_number', v_first, 'last_number', v_last, 'visible', true);
    end if;
  elsif p_event_type = 'SPECIES_REFERENCES_CLEARED' and p_removed_count > 0 then
    if not exists (select 1 from public.collection_layout_slot_species_reference r
                   where r.layout_id = p_layout_id and r.collection_id = p_collection_id) then
      v_sum := jsonb_build_object('removed_count', p_removed_count);
    end if;
  elsif p_event_type = 'SPECIES_REFERENCES_SHOWN' and p_removed_count is null and v_visible then
    v_sum := '{}'::jsonb;
  elsif p_event_type = 'SPECIES_REFERENCES_HIDDEN' and p_removed_count is null and not v_visible then
    v_sum := '{}'::jsonb;
  end if;
  if v_sum is null then
    raise exception 'binder activity: invalid species event' using errcode = '22023', hint = 'BINDER_ACTIVITY_SPECIES_EVENT';
  end if;

  insert into public.binder_activity_event
    (owner_user_id, layout_key, actor_user_id, event_type, source,
     collection_id, collection_name, binder_name, summary, item_collection_recorded)
  values
    (v_owner, p_layout_id, v_uid, p_event_type, 'FICHARIO',
     p_collection_id, left(v_collname, 200), left(v_binder, 200), v_sum, true)
  returning id into v_id;
  return v_id;
end;
$fn$;

comment on function public.binder_activity_record_species(uuid, uuid, text, integer) is
  'V1-13 E3-6/S4-c (5396, interna): um evento SPECIES_REFERENCES_* no histórico do fichário por operação efetiva de referências de espécie; autor (titular ou EDITOR ativo da dona do fichário) e resumo (contagens e números nacionais) derivados no servidor; sem itens.';
revoke all on function public.binder_activity_record_species(uuid, uuid, text, integer) from public, anon, authenticated, service_role;

create or replace function public.binder_activity_category(p_event_type text)
returns text
language sql
immutable
set search_path = ''
as $fn$
  select case
    when p_event_type in ('CARD_PLACED','CARD_MOVED','CARDS_SWAPPED','CARDS_REMOVED',
                          'CARDS_LEFT_BY_STORAGE','CARDS_LEFT_BY_COLLECTION_STORAGE','CARD_LEFT_BY_INVENTORY_EXIT',
                          'CARDS_AUTO_ARRANGED') then 'CARDS'
    when p_event_type in ('POCKET_RESERVED','RESERVATIONS_RELEASED') then 'RESERVATIONS'
    when p_event_type in ('POCKETS_LOCKED','POCKETS_UNLOCKED') then 'LOCKS'
    when p_event_type in ('GAP_OPENED','GAP_CLOSED','PAGES_ADDED','PAGE_REMOVED','PAGES_REORDERED') then 'PAGES'
    when p_event_type in ('CATALOG_NOVELTIES_INCORPORATED','LEGACY_CATALOG_INCORPORATION') then 'CATALOG'
    when p_event_type in ('BINDER_ASSEMBLED','COLLECTION_ATTACHED','COLLECTION_DETACHED',
                          'BINDER_DISMANTLED','BINDER_DELETED_EMPTY','BINDER_OWNERSHIP_TRANSFERRED') then 'BINDER'
-- [5396+]
    when p_event_type in ('SPECIES_REFERENCES_APPLIED','SPECIES_REFERENCES_CLEARED','SPECIES_REFERENCES_SHOWN','SPECIES_REFERENCES_HIDDEN') then 'SPECIES'
-- [5396-]
  end
$fn$;

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
-- [5396+]
         or (new.event_type in ('SPECIES_REFERENCES_APPLIED', 'SPECIES_REFERENCES_CLEARED', 'SPECIES_REFERENCES_SHOWN', 'SPECIES_REFERENCES_HIDDEN') and new.source = 'FICHARIO')
-- [5396-]
         or (new.event_type = 'CATALOG_NOVELTIES_INCORPORATED' and new.source = 'CATALOGO')) then
      raise exception 'binder activity: event type not allowed for this actor' using errcode = '42501',
        hint = 'BINDER_ACTIVITY_EVENT_TYPE';
    end if;
  end if;
  return new;
end;
$fn$;

create or replace function public.apply_my_binder_species_references(p_collection_id uuid, p_plan_token text)
returns table (
  layout_id          uuid,
  operation          text,
  reference_count    integer,
  references_visible boolean
)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
#variable_conflict use_column
declare
  t  record;
  pv record;
  v_count integer;
-- [5396+]
  v_audit        boolean := false;
  v_prev_visible boolean;
-- [5396-]
begin
  if p_plan_token is null or p_plan_token !~ '^[0-9a-f]{64}$' then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  select * into t from public.binder_species_reference_target(p_collection_id);

  -- Trava canônica COLLECTION → LAYOUT e ACTIVE lido sob a trava (5122).
  begin
    perform public.assert_collection_layout_mutable(t.layout_id);
  exception
    when others then
      if sqlerrm like 'collection layout not found%' then
        raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
      elsif sqlerrm like 'collection is ARCHIVED%' then
        raise exception 'COLLECTION_ARCHIVED' using errcode = '55000',
          hint = 'reative a coleção para editar o fichário';
      end if;
      raise;
  end;

  -- Plano recalculado SOB a trava.
  select * into pv from public.preview_my_binder_species_references(p_collection_id);
  if pv.plan_token <> p_plan_token then
    raise exception 'PLAN_CHANGED' using errcode = 'P0001',
      hint = 'o fichário mudou desde a prévia; revise e confirme de novo';
  end if;

-- [5396+]
  v_audit := public.v1_13_capability_open();
  if v_audit then
    select st.references_visible into v_prev_visible
    from public.collection_layout_species_reference_setting st
    where st.layout_id = t.layout_id
    for update;
    v_prev_visible := coalesce(v_prev_visible, true);
  end if;
-- [5396-]
  if pv.already_applied then
    operation := 'ALREADY_APPLIED';
  else
    if pv.existing_count > 0 then
      raise exception 'SPECIES_REFERENCES_PRESENT' using errcode = 'P0001',
        hint = 'este fichário já tem referências; remova-as antes de aplicar de novo';
    end if;
    if pv.pair_count = 0 then
      raise exception 'NOTHING_TO_APPLY' using errcode = 'P0001',
        hint = 'o fichário não tem bolsos ou a coleção não tem Pokémon no escopo';
    end if;

    insert into public.collection_layout_slot_species_reference
      (slot_id, layout_id, collection_id, pokedex_position_id, source)
    select p.slot_id, t.layout_id, p_collection_id, p.pokedex_position_id, 'NATIONAL_ORDER'
    from public.binder_species_reference_plan(t.layout_id, t.pokedex_id, t.collection_reference_id, t.scope_kind) p;

    operation := 'APPLIED';
  end if;

  insert into public.collection_layout_species_reference_setting as st (layout_id, references_visible, updated_at)
  values (t.layout_id, true, now())
  on conflict on constraint pk_cl_species_reference_setting
  do update set references_visible = true, updated_at = now()
  where st.references_visible is distinct from true;

  select count(*)::integer into v_count
  from public.collection_layout_slot_species_reference r where r.layout_id = t.layout_id;
-- [5396+]
  if v_audit then
    if operation = 'APPLIED' then
      perform public.binder_activity_record_species(t.layout_id, p_collection_id, 'SPECIES_REFERENCES_APPLIED', null);
    elsif not v_prev_visible then
      perform public.binder_activity_record_species(t.layout_id, p_collection_id, 'SPECIES_REFERENCES_SHOWN', null);
    end if;
  end if;
-- [5396-]

  layout_id          := t.layout_id;
  reference_count    := v_count;
  references_visible := true;
  return next;
end;
$$;

create or replace function public.clear_my_binder_species_references(p_collection_id uuid, p_expected_count integer)
returns table (layout_id uuid, operation text, removed_count integer)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
#variable_conflict use_column
declare
  t  record;
  v_current integer;
  v_removed integer;
begin
  if p_expected_count is null or p_expected_count < 0 then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  select * into t from public.binder_species_reference_target(p_collection_id);

  begin
    perform public.assert_collection_layout_mutable(t.layout_id);
  exception
    when others then
      if sqlerrm like 'collection layout not found%' then
        raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
      elsif sqlerrm like 'collection is ARCHIVED%' then
        raise exception 'COLLECTION_ARCHIVED' using errcode = '55000',
          hint = 'reative a coleção para editar o fichário';
      end if;
      raise;
  end;

  select count(*)::integer into v_current
  from public.collection_layout_slot_species_reference r where r.layout_id = t.layout_id;

  if v_current <> p_expected_count then
    raise exception 'COUNT_MISMATCH' using errcode = 'P0001',
      hint = format('o fichário tem %s referências; revise antes de remover', v_current);
  end if;

  delete from public.collection_layout_slot_species_reference r where r.layout_id = t.layout_id;
  get diagnostics v_removed = row_count;
-- [5396+]
  if v_removed > 0 and public.v1_13_capability_open() then
    perform public.binder_activity_record_species(t.layout_id, p_collection_id, 'SPECIES_REFERENCES_CLEARED', v_removed);
  end if;
-- [5396-]

  layout_id     := t.layout_id;
  operation     := 'REMOVED';
  removed_count := v_removed;
  return next;
end;
$$;

create or replace function public.set_my_binder_species_reference_visibility(p_collection_id uuid, p_visible boolean)
returns table (layout_id uuid, references_visible boolean, operation text)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
#variable_conflict use_column
declare
  v_layout  uuid;
  v_current boolean;
begin
  if p_visible is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  -- Proprietária OU convidada do mesmo dono (helper 5234; P0002 se alheia).
  v_layout := public.binder_slot_image_resolve_layout(p_collection_id);
  if v_layout is null then
    raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
  end if;

  select st.references_visible into v_current
  from public.collection_layout_species_reference_setting st
  where st.layout_id = v_layout
  for update;

  if coalesce(v_current, true) = p_visible then
    operation := 'UNCHANGED';
  else
    insert into public.collection_layout_species_reference_setting (layout_id, references_visible, updated_at)
    values (v_layout, p_visible, now())
    on conflict on constraint pk_cl_species_reference_setting
    do update set references_visible = excluded.references_visible, updated_at = now();
-- [5396+]
    if public.v1_13_capability_open() then
      perform public.binder_activity_record_species(v_layout, p_collection_id,
        case when p_visible then 'SPECIES_REFERENCES_SHOWN' else 'SPECIES_REFERENCES_HIDDEN' end, null);
    end if;
-- [5396-]
    operation := 'UPDATED';
  end if;

  layout_id          := v_layout;
  references_visible := p_visible;
  return next;
end;
$$;

create or replace function public.editor_apply_binder_species_references(p_collection_id uuid, p_plan_token text)
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
-- [5396+]
  v_prev_visible boolean;
-- [5396-]
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
-- [5396+]
  select st.references_visible into v_prev_visible
  from public.collection_layout_species_reference_setting st
  where st.layout_id = t.layout_id
  for update;
  v_prev_visible := coalesce(v_prev_visible, true);
-- [5396-]
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
-- [5396+]
  if v_op = 'APPLIED' then
    perform public.binder_activity_record_species(t.layout_id, p_collection_id, 'SPECIES_REFERENCES_APPLIED', null);
  elsif not v_prev_visible then
    perform public.binder_activity_record_species(t.layout_id, p_collection_id, 'SPECIES_REFERENCES_SHOWN', null);
  end if;
-- [5396-]
  return query select v_op, v_count, true;
end;
$fn$;

create or replace function public.editor_clear_binder_species_references(p_collection_id uuid, p_expected_count integer)
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
-- [5396+]
  if v_removed > 0 then
    perform public.binder_activity_record_species(t.layout_id, p_collection_id, 'SPECIES_REFERENCES_CLEARED', v_removed);
  end if;
-- [5396-]
  return query select 'REMOVED'::text, v_removed;
end;
$fn$;

create or replace function public.editor_set_binder_species_reference_visibility(p_collection_id uuid, p_visible boolean)
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
-- [5396+]
  perform public.binder_activity_record_species(t.layout_id, p_collection_id,
    case when p_visible then 'SPECIES_REFERENCES_SHOWN' else 'SPECIES_REFERENCES_HIDDEN' end, null);
-- [5396-]
  return query select p_visible, 'UPDATED'::text;
end;
$fn$;

create or replace function public.get_my_binder_activity(
  p_layout_key         uuid,
  p_categories         text[]      default null,
  p_before_occurred_at timestamptz default null,
  p_before_id          bigint      default null,
  p_limit              integer     default 20
)
returns table (
  event_id        bigint,
  occurred_at     timestamptz,
  event_type      text,
  category        text,
  source          text,
  is_legacy       boolean,
  collection_id   uuid,
  collection_name text,
  binder_name     text,
  summary         jsonb,
  item_count      integer,
  items           jsonb,
  items_truncated boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_uid   uuid    := (select auth.uid());
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
begin
  if v_uid is null or p_layout_key is null then
    return;
  end if;
  if (p_before_occurred_at is null) <> (p_before_id is null) then
    raise exception 'cursor must have occurred_at and id together' using errcode = '22023', hint = 'BINDER_ACTIVITY_CURSOR';
  end if;
  if p_categories is not null and not (p_categories <@ array['CARDS','RESERVATIONS','LOCKS','PAGES','CATALOG','BINDER','SPECIES']) then  -- [5396~]
    raise exception 'unknown category' using errcode = '22023', hint = 'BINDER_ACTIVITY_CATEGORY';
  end if;

  return query
  with page as (
    select e.*
    from public.binder_activity_event e
    where e.owner_user_id = v_uid
      and e.layout_key = p_layout_key
      and (p_categories is null or public.binder_activity_category(e.event_type) = any (p_categories))
      and (p_before_id is null or (e.occurred_at, e.id) < (p_before_occurred_at, p_before_id))
    order by e.occurred_at desc, e.id desc
    limit v_limit
  )
  select pg.id, pg.occurred_at, pg.event_type, public.binder_activity_category(pg.event_type), pg.source,
         pg.source = 'LEGADO',
         pg.collection_id,
         coalesce(pg.collection_name,
                  (select c.name from public.collection c where c.id = pg.collection_id and c.owner_user_id = v_uid)),
         pg.binder_name, pg.summary,
         ic.n::integer,
         coalesce(it.items, '[]'::jsonb),
         ic.n > 50
  from page pg
  cross join lateral (select count(*) as n from public.binder_activity_item i where i.event_id = pg.id) ic
  cross join lateral (
    select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
             'ordinal', i.ordinal, 'kind', i.item_kind, 'effect', i.effect,
             'card_id', i.card_id, 'card_name', i.card_name, 'collector_number', i.collector_number,
             'card_set_code', i.card_set_code, 'variant_type_code', i.variant_type_code,
             'variant_type_name', i.variant_type_name,
             'from_page', i.from_page, 'from_row', i.from_row, 'from_col', i.from_col,
             'to_page', i.to_page, 'to_row', i.to_row, 'to_col', i.to_col, 'detail', i.detail))
           order by i.ordinal) as items
    from (select * from public.binder_activity_item i0 where i0.event_id = pg.id order by i0.ordinal limit 50) i
  ) it
  order by pg.occurred_at desc, pg.id desc;
end;
$fn$;

create or replace function public.get_shared_binder_activity(
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
  if p_categories is not null and not (p_categories <@ array['CARDS','RESERVATIONS','LOCKS','PAGES','CATALOG','BINDER','SPECIES']) then  -- [5396~]
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
-- [5396+]
        or (e.item_collection_recorded and e.source = 'FICHARIO' and e.collection_id = p_collection_id
            and e.event_type in ('SPECIES_REFERENCES_APPLIED', 'SPECIES_REFERENCES_CLEARED', 'SPECIES_REFERENCES_SHOWN', 'SPECIES_REFERENCES_HIDDEN'))
-- [5396-]
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
      and (e.event_type in ('SPECIES_REFERENCES_APPLIED', 'SPECIES_REFERENCES_CLEARED', 'SPECIES_REFERENCES_SHOWN', 'SPECIES_REFERENCES_HIDDEN') or exists (  -- [5396~]
        select 1 from public.binder_activity_item i
        where i.event_id = e.id
          -- VISIBLE-ITEM-RULE (idêntica abaixo)
          and (case
                 when e.source = 'LEGADO' then i.item_kind = 'CARD' and i.effect = 'INCORPORATED'
                 when i.item_kind in ('CARD','RESERVATION','POCKET') then i.collection_id is not distinct from p_collection_id
                 when i.item_kind = 'PAGE' then e.collection_id is not distinct from p_collection_id
                                               and e.event_type in ('GAP_OPENED','GAP_CLOSED','PAGES_ADDED','PAGE_REMOVED','PAGES_REORDERED')
                 else false
               end)))  -- [5396~]
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
         coalesce(a.n, 0),  -- [5396~]
         coalesce(a.items, '[]'::jsonb),
         coalesce(a.n, 0) > 50  -- [5396~]
  from page pg
  left join agg a on a.event_id = pg.id  -- [5396~]
  order by pg.occurred_at desc, pg.id desc;
end;
$fn$;

-- Por último: ACCESS EXCLUSIVE em binder_activity_event até o commit (revalidação da tabela).
alter table public.binder_activity_event drop constraint chk_bae_event_type;
alter table public.binder_activity_event add constraint chk_bae_event_type check (event_type in (
    'BINDER_ASSEMBLED',
    'CARD_PLACED',
    'CARD_MOVED',
    'CARDS_SWAPPED',
    'CARDS_REMOVED',
    'CARDS_LEFT_BY_STORAGE',
    'CARDS_LEFT_BY_COLLECTION_STORAGE',
    'CARD_LEFT_BY_INVENTORY_EXIT',
    'POCKET_RESERVED',
    'RESERVATIONS_RELEASED',
    'POCKETS_LOCKED',
    'POCKETS_UNLOCKED',
    'GAP_OPENED',
    'GAP_CLOSED',
    'PAGES_ADDED',
    'PAGE_REMOVED',
    'PAGES_REORDERED',
    'CATALOG_NOVELTIES_INCORPORATED',
    'COLLECTION_ATTACHED',
    'COLLECTION_DETACHED',
    'BINDER_DISMANTLED',
    'BINDER_DELETED_EMPTY',
    'BINDER_OWNERSHIP_TRANSFERRED',
    'LEGACY_CATALOG_INCORPORATION',
    'CARDS_AUTO_ARRANGED',
    'SPECIES_REFERENCES_APPLIED',
    'SPECIES_REFERENCES_CLEARED',
    'SPECIES_REFERENCES_SHOWN',
    'SPECIES_REFERENCES_HIDDEN'
  ));

do $post$
declare
  f oid;
begin
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.apply_my_binder_species_references(uuid, text)')) is distinct from 'bc19e70ae2dd815dddaf03a47e989251'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.clear_my_binder_species_references(uuid, integer)')) is distinct from '82bd5d3f36f20ab77338c92fc2b1a916'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_my_binder_species_reference_visibility(uuid, boolean)')) is distinct from 'c5455b5cb3457d82c4231b90b54708d9'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_apply_binder_species_references(uuid, text)')) is distinct from '61e9a9785e72c19b5bacdc121bbb0e69'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_clear_binder_species_references(uuid, integer)')) is distinct from '86e9736fa756119f9d04f290b8c1c8a1'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_set_binder_species_reference_visibility(uuid, boolean)')) is distinct from 'd429cea12b4ad9b863bfb1b176f6a257'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.binder_activity_event_editor_type_guard()')) is distinct from '5ef790bd6c70c22efbe737f318d1ec21'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.binder_activity_category(text)')) is distinct from '0e25078ad9db87616f713edb66504c19'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.get_my_binder_activity(uuid, text[], timestamptz, bigint, integer)')) is distinct from 'e6e6d1a4102ab42253346f9ef0598d46'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.get_shared_binder_activity(uuid, text[], timestamptz, bigint, integer)')) is distinct from '4e8b83043b037feb6740132729c4f6d4' then
    raise exception 'POSTCHECK 5396: funções fora do texto instrumentado';
  end if;
  if (select array_agg(m.v[1] order by m.v[1] collate "C") from pg_catalog.pg_constraint k cross join lateral regexp_matches(pg_catalog.pg_get_constraintdef(k.oid), '''([A-Z0-9_]+)''', 'g') as m(v) where k.conrelid = 'public.binder_activity_event'::regclass and k.conname = 'chk_bae_event_type') is distinct from array['BINDER_ASSEMBLED', 'BINDER_DELETED_EMPTY', 'BINDER_DISMANTLED', 'BINDER_OWNERSHIP_TRANSFERRED', 'CARDS_AUTO_ARRANGED', 'CARDS_LEFT_BY_COLLECTION_STORAGE', 'CARDS_LEFT_BY_STORAGE', 'CARDS_REMOVED', 'CARDS_SWAPPED', 'CARD_LEFT_BY_INVENTORY_EXIT', 'CARD_MOVED', 'CARD_PLACED', 'CATALOG_NOVELTIES_INCORPORATED', 'COLLECTION_ATTACHED', 'COLLECTION_DETACHED', 'GAP_CLOSED', 'GAP_OPENED', 'LEGACY_CATALOG_INCORPORATION', 'PAGES_ADDED', 'PAGES_REORDERED', 'PAGE_REMOVED', 'POCKETS_LOCKED', 'POCKETS_UNLOCKED', 'POCKET_RESERVED', 'RESERVATIONS_RELEASED', 'SPECIES_REFERENCES_APPLIED', 'SPECIES_REFERENCES_CLEARED', 'SPECIES_REFERENCES_HIDDEN', 'SPECIES_REFERENCES_SHOWN']::text[] then
    raise exception 'POSTCHECK 5396: chk_bae_event_type fora do esperado';
  end if;
  foreach f in array array[to_regprocedure('public.apply_my_binder_species_references(uuid, text)'),
                           to_regprocedure('public.clear_my_binder_species_references(uuid, integer)'),
                           to_regprocedure('public.set_my_binder_species_reference_visibility(uuid, boolean)'),
                           to_regprocedure('public.editor_apply_binder_species_references(uuid, text)'),
                           to_regprocedure('public.editor_clear_binder_species_references(uuid, integer)'),
                           to_regprocedure('public.editor_set_binder_species_reference_visibility(uuid, boolean)'),
                           to_regprocedure('public.get_my_binder_activity(uuid, text[], timestamptz, bigint, integer)'),
                           to_regprocedure('public.get_shared_binder_activity(uuid, text[], timestamptz, bigint, integer)')] loop
    if (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
       or not (array['search_path=""'::text] <@ coalesce((select p.proconfig from pg_catalog.pg_proc p where p.oid = f), array[]::text[]))
       or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not true
       or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false then
      raise exception 'POSTCHECK 5396: segurança ou privilégios alterados (%)', f::regprocedure;
    end if;
  end loop;
  if (select bool_and(p.provolatile = 's') from pg_catalog.pg_proc p where p.oid in (to_regprocedure('public.get_my_binder_activity(uuid, text[], timestamptz, bigint, integer)'), to_regprocedure('public.get_shared_binder_activity(uuid, text[], timestamptz, bigint, integer)'))) is not true then
    raise exception 'POSTCHECK 5396: leituras deixaram de ser STABLE';
  end if;
  f := to_regprocedure('public.binder_activity_record_species(uuid, uuid, text, integer)');
  if f is null
     or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
     or (select p.proconfig from pg_catalog.pg_proc p where p.oid = f) is distinct from array['search_path=""']
     or exists (select 1 from pg_catalog.pg_roles x where x.rolname in ('anon', 'authenticated', 'service_role', 'authenticator')
                and pg_catalog.has_function_privilege(x.oid, f, 'EXECUTE'))
     or exists (select 1 from pg_catalog.pg_proc p cross join lateral pg_catalog.aclexplode(p.proacl) a where p.oid = f and a.grantee = 0) then
    raise exception 'POSTCHECK 5396: primitiva fora do estado esperado';
  end if;
  if (select p.provolatile from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.binder_activity_category(text)')) is distinct from 'i'
     or public.binder_activity_category('SPECIES_REFERENCES_HIDDEN') is distinct from 'SPECIES'
     or public.binder_activity_category('CARDS_AUTO_ARRANGED') is distinct from 'CARDS'
     or not exists (select 1 from pg_catalog.pg_trigger t where t.tgrelid = 'public.binder_activity_event'::regclass
                    and t.tgname = 'trg_bae_editor_event_type' and t.tgenabled = 'O') then
    raise exception 'POSTCHECK 5396: categoria ou gatilho do EDITOR fora do esperado';
  end if;
  if exists (select 1 from public.binder_activity_event e where e.event_type in ('SPECIES_REFERENCES_APPLIED', 'SPECIES_REFERENCES_CLEARED', 'SPECIES_REFERENCES_SHOWN', 'SPECIES_REFERENCES_HIDDEN')) then
    raise exception 'POSTCHECK 5396: a migration não deveria gerar eventos';
  end if;
  if (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'CLOSED'
     or (select count(*) from public.v1_13_barrier_identity) <> 0 then
    raise exception 'POSTCHECK 5396: barreira não está CLOSED';
  end if;
end;
$post$;

commit;
