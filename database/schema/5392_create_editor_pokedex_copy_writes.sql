/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5392 - Escritas colaborativas da Pokédex pelo EDITOR, por identificador
              opaco, com estado esperado e auditoria transacional (V1-13 · E3-6 / S2)
Versão......: 1.1 (2026-11-27, `FINAL CONTRACT CORRECTIONS & DEPLOYMENT READINESS-01`:
              posição restrita ao escopo de gerações da coleção, como a leitura 5391;
              rollback seguro sem reativar a 5380)
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core (qjfutqujxrbzgrtkpgkg)
              em 2026-11-27 14:02:33Z pelo executor por arquivo v1.4, papel postgres,
              manifesto 88bc2562…5a07, expectativas por assinatura 10d2f706…7c68:
              PRE PASS (inventário igual ao esperado), migration exit 0 (transação única),
              POST PASS (4 RPCs, 2 ajudantes internos, 5380 revogada, inventário pós-5392
              exato, sem eventos). Do `begin;` ao `commit;` idêntica à proposta (só este
              bloco difere). Barreira CLOSED: escritas inertes para clientes. Provas
              funcionais, de concorrência e de desempenho NÃO executadas (TEST/E4).
Autor.......: Fabrício Sales / Claude
Contrato....: README do pacote S2 §3.3–§3.6 e §11 (D1–D4); S4 §9.4 (open antes,
              record depois, um evento por operação efetiva).
Cria........: ajudantes internos v1_13_resolve_pokedex_copy(uuid, text, uuid, bigint, uuid) e
              v1_13_pokedex_position_in_scope(uuid, uuid);
              RPCs editor_move_pokedex_copy, editor_unassign_pokedex_copy,
              editor_choose_pokedex_representative,
              editor_restore_pokedex_automatic_representative.
Revoga......: EXECUTE de authenticated nas 4 escritas da 5380 (aceitam physical_card_id,
              sem estado esperado nem auditoria). As funções ficam (EMERGENCY_STOP_V1_13
              as revoga sem guarda). Nenhuma outra função existente muda.
Depende.....: 5389 (barreira), 5376 (assert_collection_editor), 5380
              (editor_pokedex_of_collection), 5391 (época, identificador), 5394
              (collection_activity_open/record_pokedex) — md5 conferidos.
Ordem.......: barreira → sessão → assert_collection_editor (coleção FOR UPDATE,
              participação FOR SHARE) → época vigente → identificador → alocação FOR
              UPDATE → representante FOR UPDATE → comparação com o estado esperado →
              collection_activity_open → escrita → collection_activity_record_pokedex.
Reversão....: ROLLBACK_5392.sql (remove as 6 funções; a 5380 CONTINUA revogada — o EDITOR
              fica sem escrita de Pokédex). Restaurar a 5380 é excepcional:
              RESTORE_5380_EXCECAO_5392.sql, só com autorização específica.
================================================================
*/

begin;
set local lock_timeout = '3s';

do $pre$
begin
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_assert_capability()')) is distinct from 'e4f710904f50e6e8c3f1d8e2337639e0'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_capability_open()')) is distinct from '32e2f636361732b497e8401e50f0bbe0'
     or (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'CLOSED'
     or (select count(*) from public.v1_13_barrier_identity) <> 0 then
    raise exception 'PRECHECK 5392: barreira ausente, divergente ou não CLOSED';
  end if;
  -- Dependências implantadas, com o corpo canônico.
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.assert_collection_editor(uuid)')) is distinct from '9a7482588b5c7995f40a5d945c957f31'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_pokedex_of_collection(uuid)')) is distinct from '6342e8fea261c62487c7ebf5f2b66829'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_pokedex_copy_token(uuid, uuid, bigint)')) is distinct from '64fa85659b6b999796deeef94dad4e4c'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_editor_membership(uuid)')) is distinct from '856ddff63fd4946f712bca1deeaa7a6c'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.collection_activity_open(uuid)')) is distinct from 'd5f52bf5a2a29f1a4d8279c560b97043'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.collection_activity_record_pokedex(uuid, text, uuid, uuid, uuid, uuid, text, boolean)')) is distinct from 'c7245940a39d7c2a3d0674deb3be06dd' then
    raise exception 'PRECHECK 5392: ESTADO DIVERGENTE — dependência (5376/5380/5391/5394) ausente ou diferente do canônico';
  end if;
  -- Escritas da 5380: presentes, canônicas, ainda executáveis por authenticated (estado a revogar).
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_set_pokedex_position_assignment(uuid, uuid, uuid, boolean)')) is distinct from '90ee1b0594ffe8cf7a3bf6c54549e5ef'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_remove_pokedex_position_assignment(uuid, uuid)')) is distinct from '3cef5f640a60b2ad290c9420cc71a596'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_set_pokedex_position_primary_representative(uuid, uuid)')) is distinct from '2882df84eb882648552c3350bda3876d'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_clear_pokedex_position_primary_representative(uuid, uuid)')) is distinct from 'b8d4408299e90de6258dcc0c7c2a1b75' then
    raise exception 'PRECHECK 5392: ESTADO DIVERGENTE — escritas da 5380 diferem do canônico';
  end if;
  -- Funções do titular intocadas.
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_pokedex_position_assignment(uuid, uuid, boolean)')) is distinct from '8c572182a03025503e993e5ecc25e07a'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.remove_pokedex_position_assignment(uuid)')) is distinct from '26ef2d5da3312661111df0194dfc8ba2'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_pokedex_position_primary_representative(uuid)')) is distinct from '6353dffe6c3877967997033dcc2bfd4c'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.clear_pokedex_position_primary_representative(uuid, uuid)')) is distinct from 'eeede3a5b871fbf07f81eb59ecea932f' then
    raise exception 'PRECHECK 5392: ESTADO DIVERGENTE — funções do titular da Pokédex diferem de 6123/6124/6126/6125';
  end if;
  if to_regclass('public.collection_pokedex_scope_generation') is null then
    raise exception 'PRECHECK 5392: collection_pokedex_scope_generation ausente';
  end if;
  if exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public'
               and p.proname in ('v1_13_resolve_pokedex_copy', 'v1_13_pokedex_position_in_scope', 'editor_move_pokedex_copy', 'editor_unassign_pokedex_copy',
                                 'editor_choose_pokedex_representative', 'editor_restore_pokedex_automatic_representative')) then
    raise exception 'PRECHECK 5392: JÁ APLICADA ou ESTADO DIVERGENTE';
  end if;
end;
$pre$;

-- Resolve o identificador opaco para a alocação de X (época vigente). Primeiro no escopo
-- esperado (posição informada, ou exemplares sem posição); sem acerto, em toda a coleção.
-- NULL = inválido, obsoleto ou de outro contexto (a chamadora recusa com COPY_NOT_FOUND).
create function public.v1_13_resolve_pokedex_copy(
  p_collection_id uuid, p_token text, p_membership_id uuid, p_role_epoch bigint, p_hint_position_id uuid
)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_alloc uuid;
begin
  if p_collection_id is null or p_membership_id is null or p_role_epoch is null
     or p_token is null or p_token !~ '^pc1\.[0-9a-f]{64}$' then
    return null;
  end if;
  if p_hint_position_id is not null then
    select ca.id into v_alloc
    from public.collection_allocation ca
    join public.collection_pokedex_position_assignment a on a.collection_allocation_id = ca.id
    where ca.collection_id = p_collection_id and a.pokedex_position_id = p_hint_position_id
      and public.v1_13_pokedex_copy_token(ca.id, p_membership_id, p_role_epoch) = p_token
    limit 1;
  else
    select ca.id into v_alloc
    from public.collection_allocation ca
    where ca.collection_id = p_collection_id
      and not exists (select 1 from public.collection_pokedex_position_assignment a where a.collection_allocation_id = ca.id)
      and public.v1_13_pokedex_copy_token(ca.id, p_membership_id, p_role_epoch) = p_token
    limit 1;
  end if;
  if v_alloc is null then
    select ca.id into v_alloc
    from public.collection_allocation ca
    where ca.collection_id = p_collection_id
      and public.v1_13_pokedex_copy_token(ca.id, p_membership_id, p_role_epoch) = p_token
    limit 1;
  end if;
  return v_alloc;
end;
$fn$;

-- Posição da Pokédex de X e dentro do escopo de gerações configurado (mesmo critério da
-- leitura 5391 e das grades 5204/5324): FULL_REFERENCE, ou geração da espécie listada.
create function public.v1_13_pokedex_position_in_scope(p_collection_id uuid, p_pokedex_position_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select exists (
    select 1
    from public.collection c
    join public.collection_reference cr on cr.collection_id = c.id and cr.reference_kind = 'POKEDEX'
    join public.collection_pokedex_reference cpr on cpr.collection_reference_id = cr.id
    join public.pokedex_position pp on pp.pokedex_id = cpr.pokedex_id
    join public.pokemon_species s on s.id = pp.species_id
    where c.id = p_collection_id
      and c.mode = 'REFERENCE_BASED' and c.completion_policy = 'REFERENCE_POSITION'
      and pp.id = p_pokedex_position_id
      and (cpr.scope_kind = 'FULL_REFERENCE'
           or exists (select 1 from public.collection_pokedex_scope_generation sg
                      where sg.collection_reference_id = cr.id and sg.generation_id = s.generation_id)));
$fn$;

-- Atribuir (sem posição → posição) ou mover (posição → outra).
create function public.editor_move_pokedex_copy(
  p_collection_id        uuid,
  p_copy_token           text,
  p_target_position_id   uuid,
  p_expected_position_id uuid,
  p_confirm_override     boolean default false
)
returns table (operation text, pokedex_position_id uuid, previous_position_id uuid,
               assignment_basis text, representative_cleared boolean)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_uid     uuid := (select auth.uid());
  v_dex     uuid;
  v_mid     uuid;
  v_epoch   bigint;
  v_alloc   uuid;
  v_cur     uuid;
  v_cur_b   text;
  v_pos_dex uuid;
  v_pos_spc uuid;
  v_cat     text;
  v_spc     uuid;
  v_base    text;
  v_rep     boolean := false;
begin
  perform public.v1_13_assert_capability();
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_copy_token is null or p_target_position_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  perform public.assert_collection_editor(p_collection_id);   -- coleção FOR UPDATE, participação FOR SHARE, ACTIVE
  v_dex := public.editor_pokedex_of_collection(p_collection_id);
  select em.membership_id, em.role_epoch into v_mid, v_epoch from public.v1_13_editor_membership(p_collection_id) em;
  if v_mid is null then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  if not public.v1_13_pokedex_position_in_scope(p_collection_id, p_target_position_id) then
    raise exception 'POKEDEX_POSITION_NOT_FOUND' using errcode = '22023';
  end if;
  select pp.pokedex_id, pp.species_id into v_pos_dex, v_pos_spc
  from public.pokedex_position pp where pp.id = p_target_position_id;

  v_alloc := public.v1_13_resolve_pokedex_copy(p_collection_id, p_copy_token, v_mid, v_epoch, p_expected_position_id);
  if v_alloc is null then
    raise exception 'COPY_NOT_FOUND' using errcode = 'P0002';
  end if;
  perform 1 from public.collection_allocation ca where ca.id = v_alloc and ca.collection_id = p_collection_id for update;
  if not found then
    raise exception 'COPY_NOT_FOUND' using errcode = 'P0002';
  end if;

  select a.pokedex_position_id, a.assignment_basis into v_cur, v_cur_b
  from public.collection_pokedex_position_assignment a where a.collection_allocation_id = v_alloc;
  if v_cur is not distinct from p_target_position_id then
    return query select 'UNCHANGED'::text, v_cur, v_cur, v_cur_b, false;   -- idempotência: sem evento
    return;
  end if;
  if v_cur is distinct from p_expected_position_id then
    raise exception 'STATE_CHANGED' using errcode = '22023';
  end if;

  select cc.code, cps.pokemon_species_id into v_cat, v_spc
  from public.collection_allocation ca
  join public.physical_card pc on pc.id = ca.physical_card_id
  join public.card_variant cv on cv.id = pc.card_variant_id
  join public.card k on k.id = cv.card_id
  join public.card_category cc on cc.id = k.category_id
  left join public.card_primary_species cps on cps.card_id = k.id
  where ca.id = v_alloc;
  if v_cat = 'POKEMON' and v_spc is not null and v_spc = v_pos_spc then
    v_base := 'SPECIES_MATCH';
  elsif coalesce(p_confirm_override, false) then
    v_base := 'USER_OVERRIDE';
  else
    raise exception 'CONFIRMATION_REQUIRED' using errcode = '22023';
  end if;

  if v_cur is not null then
    select exists (select 1 from public.collection_pokedex_position_primary_representative r
                   where r.collection_allocation_id = v_alloc) into v_rep;
  end if;

  perform public.collection_activity_open(p_collection_id);
  if v_cur is not null then
    delete from public.collection_pokedex_position_assignment a where a.collection_allocation_id = v_alloc;
  end if;
  insert into public.collection_pokedex_position_assignment
    (collection_allocation_id, pokedex_position_id, assignment_basis, assigned_at, assigned_by_user_id)
  values (v_alloc, p_target_position_id, v_base, now(), case when v_base = 'USER_OVERRIDE' then v_uid end);

  if v_cur is null then
    perform public.collection_activity_record_pokedex(p_collection_id, 'POKEDEX_POSITION_ASSIGNED', v_alloc,
                                                      null, p_target_position_id, null, v_base, null);
    return query select 'CREATED'::text, p_target_position_id, null::uuid, v_base, false;
  else
    perform public.collection_activity_record_pokedex(p_collection_id, 'POKEDEX_POSITION_MOVED', v_alloc,
                                                      v_cur, p_target_position_id, null, v_base, v_rep);
    return query select 'MOVED'::text, p_target_position_id, v_cur, v_base, v_rep;
  end if;
end;
$fn$;

-- Retirar a posição (sem desalocar).
create function public.editor_unassign_pokedex_copy(
  p_collection_id        uuid,
  p_copy_token           text,
  p_expected_position_id uuid
)
returns table (operation text, previous_position_id uuid, representative_cleared boolean)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_uid   uuid := (select auth.uid());
  v_mid   uuid;
  v_epoch bigint;
  v_alloc uuid;
  v_cur   uuid;
  v_rep   boolean;
begin
  perform public.v1_13_assert_capability();
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_copy_token is null or p_expected_position_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  perform public.assert_collection_editor(p_collection_id);
  perform public.editor_pokedex_of_collection(p_collection_id);
  select em.membership_id, em.role_epoch into v_mid, v_epoch from public.v1_13_editor_membership(p_collection_id) em;
  if v_mid is null then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  v_alloc := public.v1_13_resolve_pokedex_copy(p_collection_id, p_copy_token, v_mid, v_epoch, p_expected_position_id);
  if v_alloc is null then
    raise exception 'COPY_NOT_FOUND' using errcode = 'P0002';
  end if;
  perform 1 from public.collection_allocation ca where ca.id = v_alloc and ca.collection_id = p_collection_id for update;
  if not found then
    raise exception 'COPY_NOT_FOUND' using errcode = 'P0002';
  end if;

  select a.pokedex_position_id into v_cur
  from public.collection_pokedex_position_assignment a where a.collection_allocation_id = v_alloc;
  if v_cur is null then
    return query select 'UNCHANGED'::text, null::uuid, false;   -- já sem posição: sem evento
    return;
  end if;
  if v_cur is distinct from p_expected_position_id then
    raise exception 'STATE_CHANGED' using errcode = '22023';
  end if;

  select exists (select 1 from public.collection_pokedex_position_primary_representative r
                 where r.collection_allocation_id = v_alloc) into v_rep;
  perform public.collection_activity_open(p_collection_id);
  delete from public.collection_pokedex_position_assignment a where a.collection_allocation_id = v_alloc;
  perform public.collection_activity_record_pokedex(p_collection_id, 'POKEDEX_POSITION_REMOVED', v_alloc,
                                                    v_cur, null, null, null, v_rep);
  return query select 'REMOVED'::text, v_cur, v_rep;
end;
$fn$;

-- Escolher (ou substituir) a representante da posição em que o exemplar está.
create function public.editor_choose_pokedex_representative(
  p_collection_id                 uuid,
  p_copy_token                    text,
  p_expected_position_id          uuid,
  p_expected_representative_token text default null   -- NULL = a tela viu a escolha automática
)
returns table (operation text, pokedex_position_id uuid)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_uid   uuid := (select auth.uid());
  v_mid   uuid;
  v_epoch bigint;
  v_alloc uuid;
  v_cur   uuid;
  v_prev  uuid;
  v_exp   uuid;
begin
  perform public.v1_13_assert_capability();
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_copy_token is null or p_expected_position_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  perform public.assert_collection_editor(p_collection_id);
  perform public.editor_pokedex_of_collection(p_collection_id);
  select em.membership_id, em.role_epoch into v_mid, v_epoch from public.v1_13_editor_membership(p_collection_id) em;
  if v_mid is null then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  v_alloc := public.v1_13_resolve_pokedex_copy(p_collection_id, p_copy_token, v_mid, v_epoch, p_expected_position_id);
  if v_alloc is null then
    raise exception 'COPY_NOT_FOUND' using errcode = 'P0002';
  end if;
  perform 1 from public.collection_allocation ca where ca.id = v_alloc and ca.collection_id = p_collection_id for update;
  if not found then
    raise exception 'COPY_NOT_FOUND' using errcode = 'P0002';
  end if;

  select a.pokedex_position_id into v_cur
  from public.collection_pokedex_position_assignment a where a.collection_allocation_id = v_alloc;
  if v_cur is distinct from p_expected_position_id then
    raise exception 'STATE_CHANGED' using errcode = '22023';
  end if;
  if not public.v1_13_pokedex_position_in_scope(p_collection_id, v_cur) then
    raise exception 'POKEDEX_POSITION_NOT_FOUND' using errcode = '22023';
  end if;

  select r.collection_allocation_id into v_prev
  from public.collection_pokedex_position_primary_representative r
  where r.collection_id = p_collection_id and r.pokedex_position_id = v_cur
  for update;
  if v_prev is not distinct from v_alloc then
    return query select 'UNCHANGED'::text, v_cur;   -- já é a escolhida: sem evento
    return;
  end if;
  if p_expected_representative_token is null then
    if v_prev is not null then
      raise exception 'STATE_CHANGED' using errcode = '22023';
    end if;
  else
    v_exp := public.v1_13_resolve_pokedex_copy(p_collection_id, p_expected_representative_token, v_mid, v_epoch, v_cur);
    if v_exp is null or v_exp is distinct from v_prev then
      raise exception 'STATE_CHANGED' using errcode = '22023';
    end if;
  end if;

  perform public.collection_activity_open(p_collection_id);
  insert into public.collection_pokedex_position_primary_representative
    (collection_id, pokedex_position_id, collection_allocation_id)
  values (p_collection_id, v_cur, v_alloc)
  on conflict on constraint pk_collection_pokedex_position_primary_representative
  do update set collection_allocation_id = excluded.collection_allocation_id;

  if v_prev is null then
    perform public.collection_activity_record_pokedex(p_collection_id, 'POKEDEX_REPRESENTATIVE_SET', v_alloc,
                                                      null, v_cur, null, null, null);
    return query select 'SET'::text, v_cur;
  else
    perform public.collection_activity_record_pokedex(p_collection_id, 'POKEDEX_REPRESENTATIVE_REPLACED', v_alloc,
                                                      null, v_cur, v_prev, null, null);
    return query select 'REPLACED'::text, v_cur;
  end if;
end;
$fn$;

-- Voltar à escolha automática (remove a representante escolhida).
create function public.editor_restore_pokedex_automatic_representative(
  p_collection_id                 uuid,
  p_pokedex_position_id           uuid,
  p_expected_representative_token text
)
returns table (operation text)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_uid     uuid := (select auth.uid());
  v_dex     uuid;
  v_mid     uuid;
  v_epoch   bigint;
  v_prev    uuid;
  v_exp     uuid;
begin
  perform public.v1_13_assert_capability();
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_pokedex_position_id is null or p_expected_representative_token is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  perform public.assert_collection_editor(p_collection_id);
  v_dex := public.editor_pokedex_of_collection(p_collection_id);
  select em.membership_id, em.role_epoch into v_mid, v_epoch from public.v1_13_editor_membership(p_collection_id) em;
  if v_mid is null then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;
  if not public.v1_13_pokedex_position_in_scope(p_collection_id, p_pokedex_position_id) then
    raise exception 'POKEDEX_POSITION_NOT_FOUND' using errcode = '22023';
  end if;

  select r.collection_allocation_id into v_prev
  from public.collection_pokedex_position_primary_representative r
  where r.collection_id = p_collection_id and r.pokedex_position_id = p_pokedex_position_id
  for update;
  if v_prev is null then
    return query select 'UNCHANGED'::text;   -- já automática: sem evento
    return;
  end if;
  v_exp := public.v1_13_resolve_pokedex_copy(p_collection_id, p_expected_representative_token, v_mid, v_epoch, p_pokedex_position_id);
  if v_exp is null or v_exp is distinct from v_prev then
    raise exception 'STATE_CHANGED' using errcode = '22023';
  end if;

  perform public.collection_activity_open(p_collection_id);
  delete from public.collection_pokedex_position_primary_representative r
  where r.collection_id = p_collection_id and r.pokedex_position_id = p_pokedex_position_id;
  perform public.collection_activity_record_pokedex(p_collection_id, 'POKEDEX_REPRESENTATIVE_RESTORED', null,
                                                    null, p_pokedex_position_id, v_prev, null, null);
  return query select 'CLEARED'::text;
end;
$fn$;

comment on function public.v1_13_resolve_pokedex_copy(uuid, text, uuid, bigint, uuid) is
  'V1-13 E3-6/S2 (5392, interna): identificador opaco (5391) → alocação da coleção na época vigente; primeiro no escopo esperado, depois na coleção. NULL = inválido, obsoleto ou de outro contexto.';
comment on function public.v1_13_pokedex_position_in_scope(uuid, uuid) is
  'V1-13 E3-6/S2 (5392, interna): posição da Pokédex da coleção dentro do escopo de gerações configurado (mesmo critério da leitura 5391).';
comment on function public.editor_move_pokedex_copy(uuid, text, uuid, uuid, boolean) is
  'V1-13 E3-6/S2 (5392): EDITOR atribui ou move a posição Pokédex de um exemplar da coleção (identificador opaco, estado esperado comparado após as travas). CREATED/MOVED gravam evento (5394); UNCHANGED não.';
comment on function public.editor_unassign_pokedex_copy(uuid, text, uuid) is
  'V1-13 E3-6/S2 (5392): EDITOR retira a posição Pokédex de um exemplar, sem desalocar. REMOVED grava evento; UNCHANGED não.';
comment on function public.editor_choose_pokedex_representative(uuid, text, uuid, text) is
  'V1-13 E3-6/S2 (5392): EDITOR escolhe ou substitui a representante da posição. SET/REPLACED gravam evento; UNCHANGED não.';
comment on function public.editor_restore_pokedex_automatic_representative(uuid, uuid, text) is
  'V1-13 E3-6/S2 (5392): EDITOR volta a posição à representante automática. CLEARED grava evento; UNCHANGED não.';

revoke all on function public.v1_13_resolve_pokedex_copy(uuid, text, uuid, bigint, uuid) from public, anon, authenticated, service_role;
revoke all on function public.v1_13_pokedex_position_in_scope(uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function public.editor_move_pokedex_copy(uuid, text, uuid, uuid, boolean) from public, anon, service_role;
revoke all on function public.editor_unassign_pokedex_copy(uuid, text, uuid) from public, anon, service_role;
revoke all on function public.editor_choose_pokedex_representative(uuid, text, uuid, text) from public, anon, service_role;
revoke all on function public.editor_restore_pokedex_automatic_representative(uuid, uuid, text) from public, anon, service_role;
grant execute on function public.editor_move_pokedex_copy(uuid, text, uuid, uuid, boolean) to authenticated;
grant execute on function public.editor_unassign_pokedex_copy(uuid, text, uuid) to authenticated;
grant execute on function public.editor_choose_pokedex_representative(uuid, text, uuid, text) to authenticated;
grant execute on function public.editor_restore_pokedex_automatic_representative(uuid, uuid, text) to authenticated;

-- Um único caminho de escrita do EDITOR: por identificador, com estado esperado e auditoria.
revoke execute on function public.editor_set_pokedex_position_assignment(uuid, uuid, uuid, boolean) from public, anon, authenticated, service_role;
revoke execute on function public.editor_remove_pokedex_position_assignment(uuid, uuid) from public, anon, authenticated, service_role;
revoke execute on function public.editor_set_pokedex_position_primary_representative(uuid, uuid) from public, anon, authenticated, service_role;
revoke execute on function public.editor_clear_pokedex_position_primary_representative(uuid, uuid) from public, anon, authenticated, service_role;

do $post$
declare
  f oid;
begin
  foreach f in array array[to_regprocedure('public.editor_move_pokedex_copy(uuid, text, uuid, uuid, boolean)'),
                           to_regprocedure('public.editor_unassign_pokedex_copy(uuid, text, uuid)'),
                           to_regprocedure('public.editor_choose_pokedex_representative(uuid, text, uuid, text)'),
                           to_regprocedure('public.editor_restore_pokedex_automatic_representative(uuid, uuid, text)')] loop
    if f is null
       or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
       or (select p.proconfig from pg_catalog.pg_proc p where p.oid = f) is distinct from array['search_path=""']
       or (select p.provolatile from pg_catalog.pg_proc p where p.oid = f) is distinct from 'v'
       or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not true
       or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false
       or pg_catalog.has_function_privilege('service_role', f, 'EXECUTE') is not false
       or exists (select 1 from pg_catalog.pg_proc p cross join lateral pg_catalog.aclexplode(p.proacl) a
                  where p.oid = f and a.grantee = 0) then
      raise exception 'POSTCHECK 5392: RPC fora do estado esperado (%)', f::regprocedure;
    end if;
  end loop;
  foreach f in array array[to_regprocedure('public.v1_13_resolve_pokedex_copy(uuid, text, uuid, bigint, uuid)'),
                           to_regprocedure('public.v1_13_pokedex_position_in_scope(uuid, uuid)')] loop
    if f is null
       or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
       or (select p.proconfig from pg_catalog.pg_proc p where p.oid = f) is distinct from array['search_path=""']
       or exists (select 1 from pg_catalog.pg_roles x where x.rolname in ('anon', 'authenticated', 'service_role', 'authenticator')
                  and pg_catalog.has_function_privilege(x.oid, f, 'EXECUTE')) then
      raise exception 'POSTCHECK 5392: ajudante interno fora do estado esperado (%)', f;
    end if;
  end loop;
  -- 5380: nenhuma escrita por physical_card_id executável por papel de cliente; corpos intactos.
  if exists (select 1 from pg_catalog.pg_roles x
             cross join unnest(array[to_regprocedure('public.editor_set_pokedex_position_assignment(uuid, uuid, uuid, boolean)'),
                                     to_regprocedure('public.editor_remove_pokedex_position_assignment(uuid, uuid)'),
                                     to_regprocedure('public.editor_set_pokedex_position_primary_representative(uuid, uuid)'),
                                     to_regprocedure('public.editor_clear_pokedex_position_primary_representative(uuid, uuid)')]) g(oid)
             where x.rolname in ('anon', 'authenticated', 'service_role', 'authenticator')
               and (g.oid is null or pg_catalog.has_function_privilege(x.oid, g.oid, 'EXECUTE'))) then
    raise exception 'POSTCHECK 5392: escrita da 5380 ainda executável por papel de cliente';
  end if;
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_set_pokedex_position_assignment(uuid, uuid, uuid, boolean)')) is distinct from '90ee1b0594ffe8cf7a3bf6c54549e5ef'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_pokedex_position_assignment(uuid, uuid, boolean)')) is distinct from '8c572182a03025503e993e5ecc25e07a'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.collection_activity_record_pokedex(uuid, text, uuid, uuid, uuid, uuid, text, boolean)')) is distinct from 'c7245940a39d7c2a3d0674deb3be06dd' then
    raise exception 'POSTCHECK 5392: função existente alterada';
  end if;
  if exists (select 1 from public.collection_activity_event) then
    raise exception 'POSTCHECK 5392: a migration não deveria gerar eventos';
  end if;
  if (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'CLOSED'
     or (select count(*) from public.v1_13_barrier_identity) <> 0 then
    raise exception 'POSTCHECK 5392: barreira não está CLOSED';
  end if;
end;
$post$;

commit;
