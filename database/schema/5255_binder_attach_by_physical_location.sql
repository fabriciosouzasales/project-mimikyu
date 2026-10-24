/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5255 - Associação de convidadas pelo local físico do fichário
              attach_my_collection_to_binder(uuid, uuid)      — CREATE OR REPLACE (5229)
              list_my_binder_join_candidates(uuid)            — CREATE OR REPLACE (5230)
Versão......: 1.0 (2026-10-24, BINDER-PHYSICAL-LOCATION-IMPLEMENTATION-READINESS-01)
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core em 2026-10-24
              (Fase A, autorização expressa de Fabrício; ledger
              20261024121921 `5255_binder_attach_by_physical_location`). Do `begin;` ao `commit;`
              idêntica ao arquivo de database/proposals/2026-10-24-binder-
              physical-location/ (só este bloco Status difere); enviada via
              apply_migration sem as linhas `begin;`/`commit;` externas — o texto
              gravado no ledger é igual ao corpo do arquivo (md5). LIVE_90 7/7 PASS.
              Ver LIVE-PHASE-A-2026-10-24.md da proposta.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-24

D2 (Fabrício): a compatibilidade da convidada passa a ser validada pelo
local físico PRÓPRIO do fichário (collection_layout.storage_container_id,
5247) — elimina a dependência do local padrão da proprietária (que pode
mudar, e que muda de coleção numa transferência, 5254).
Regra nova (as duas funções, mesma regra): o local padrão da coleção que
quer se associar é do tipo Fichário e É o local físico do fichário.
Mesmos parâmetros, mesmo retorno, mesmas mensagens (NOT_SAME_LOCATION);
o resto do corpo é o canônico (5229/5230), conferido pelo static check.
No LIVE de hoje o resultado é idêntico: F001 é o local padrão da
proprietária e o local do fichário (backfill 5247).
Dependências: 5229, 5230, 5247.
================================================================
*/

begin;

set local lock_timeout = '5s';

do $pre$
begin
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'collection_layout'
                   and column_name = 'storage_container_id') then
    raise exception 'PRECHECK 5255: aplique a 5247 antes';
  end if;
  if to_regprocedure('public.attach_my_collection_to_binder(uuid, uuid)') is null
     or to_regprocedure('public.list_my_binder_join_candidates(uuid)') is null then
    raise exception 'PRECHECK 5255: 5229/5230 ausentes';
  end if;
end;
$pre$;

create or replace function public.attach_my_collection_to_binder(
  p_collection_id uuid,
  p_layout_id     uuid
)
returns table (
  outcome             text,    -- ATTACHED | ALREADY_ATTACHED
  layout_id           uuid,
  owner_collection_id uuid
)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
#variable_conflict use_column
declare
  v_uid        uuid := auth.uid();
  v_owner_coll uuid;
  v_status     text;
  v_default    uuid;
  v_kind       text;
  v_current    uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null or p_layout_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  -- 1. Fichário pelo dono (sem trava): inexistente e alheio no mesmo ramo.
  select l.collection_id into v_owner_coll
  from public.collection_layout l
  join public.collection c on c.id = l.collection_id
  where l.id = p_layout_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_owner_coll = p_collection_id then
    raise exception 'BINDER_SELF' using errcode = '22023';
  end if;

  -- 2. Proprietária → layout (trava + ACTIVE), ordem canônica (5122).
  begin
    perform public.assert_collection_layout_mutable(p_layout_id);
  exception
    when others then
      if sqlerrm like 'collection layout not found%' then
        raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
      end if;
      if sqlerrm like 'collection is ARCHIVED%' then
        raise exception 'BINDER_ARCHIVED';
      end if;
      raise;
  end;

  -- 3. Convidada (trava).
  select c.lifecycle_status, c.default_storage_container_id into v_status, v_default
  from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_uid
  for update;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_status <> 'ACTIVE' then
    raise exception 'COLLECTION_ARCHIVED';
  end if;

  -- 4. Idempotência e participação única (D-única).
  select g.layout_id into v_current
  from public.collection_layout_guest g where g.collection_id = p_collection_id;
  if v_current is not null then
    if v_current = p_layout_id then
      outcome := 'ALREADY_ATTACHED'; layout_id := p_layout_id; owner_collection_id := v_owner_coll;
      return next;
      return;
    end if;
    raise exception 'COLLECTION_ALREADY_IN_BINDER';
  end if;
  if exists (select 1 from public.collection_layout l where l.collection_id = p_collection_id) then
    raise exception 'COLLECTION_HAS_OWN_BINDER';
  end if;

  -- 5. Local físico (D9): o local padrão da convidada é um fichário e é o
  --    local padrão de algum participante deste fichário.
  if v_default is not null then
    select sc.kind_code::text into v_kind
    from public.storage_container sc
    join public.inventory i on i.id = sc.inventory_id
    where sc.id = v_default and i.owner_user_id = v_uid;
  end if;
  -- 5255 (D2 da rodada READINESS): compatibilidade pelo local físico PRÓPRIO
  -- do fichário (5247), não pelo local padrão da proprietária/participantes.
  if v_kind is distinct from 'BINDER'
     or v_default is distinct from (select l.storage_container_id from public.collection_layout l where l.id = p_layout_id) then
    raise exception 'NOT_SAME_LOCATION'
      using hint = 'escolha como local padrão o mesmo fichário físico das coleções deste fichário';
  end if;

  -- 6. Associação: nenhum bolso, reserva ou carta é tocado (D3).
  insert into public.collection_layout_guest (collection_id, layout_id)
  values (p_collection_id, p_layout_id);

  outcome := 'ATTACHED'; layout_id := p_layout_id; owner_collection_id := v_owner_coll;
  return next;
end;
$$;

create or replace function public.list_my_binder_join_candidates(p_collection_id uuid)
returns table (
  layout_id             uuid,
  owner_collection_id   uuid,
  owner_collection_name text,
  grid_columns          integer,
  grid_rows             integer,
  page_count            integer,
  free_slot_count       integer,
  participant_count     integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid     uuid := auth.uid();
  v_status  text;
  v_default uuid;
  v_kind    text;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  select c.lifecycle_status, c.default_storage_container_id into v_status, v_default
  from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- Só faz sentido para coleção ativa, sem fichário próprio nem associação,
  -- guardada num fichário físico (mesma regra da 5229 §8).
  if v_status <> 'ACTIVE' or v_default is null
     or exists (select 1 from public.collection_layout l where l.collection_id = p_collection_id)
     or exists (select 1 from public.collection_layout_guest g where g.collection_id = p_collection_id) then
    return;
  end if;
  select sc.kind_code::text into v_kind
  from public.storage_container sc
  join public.inventory i on i.id = sc.inventory_id
  where sc.id = v_default and i.owner_user_id = v_uid;
  if v_kind is distinct from 'BINDER' then
    return;
  end if;

  return query
  with cand as (
    select l.id, l.collection_id, l.grid_columns, l.grid_rows
    from public.collection_layout l
    join public.collection oc on oc.id = l.collection_id
    where oc.owner_user_id = v_uid
      and oc.lifecycle_status = 'ACTIVE'
      and oc.id <> p_collection_id
      -- 5255: mesmo fichário físico = local próprio do fichário (5247).
      and l.storage_container_id = v_default
  )
  select cand.id,
         cand.collection_id,
         oc.name::text,
         cand.grid_columns,
         cand.grid_rows,
         (select count(*) from public.collection_layout_page p where p.layout_id = cand.id)::integer,
         (select count(*)
            from public.collection_layout_page p
            join public.collection_layout_slot s on s.page_id = p.id
           where p.layout_id = cand.id
             and not exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = s.id)
             and not exists (select 1 from public.collection_layout_slot_expected_content e where e.slot_id = s.id)
         )::integer,
         1 + (select count(*) from public.collection_layout_guest g where g.layout_id = cand.id)::integer
  from cand
  join public.collection oc on oc.id = cand.collection_id
  order by oc.name, cand.id;
end;
$$;

revoke all on function public.attach_my_collection_to_binder(uuid, uuid) from public;
revoke all on function public.attach_my_collection_to_binder(uuid, uuid) from anon;
grant execute on function public.attach_my_collection_to_binder(uuid, uuid) to authenticated;
revoke all on function public.list_my_binder_join_candidates(uuid) from public;
revoke all on function public.list_my_binder_join_candidates(uuid) from anon;
grant execute on function public.list_my_binder_join_candidates(uuid) to authenticated;

notify pgrst, 'reload schema';

commit;

/*
Como validar (só leitura): position('storage_container_id' in pg_get_functiondef(
  'public.attach_my_collection_to_binder(uuid, uuid)'::regprocedure)) > 0
*/
