/*
================================================================
Projeto.....: Project Mimikyu
Query.......: R1 - Recuperação da FASE B (desfaz a 5256)
Status......: PROPOSTA — NÃO EXECUTADA. Só com autorização de Fabrício.
Data........: 2026-10-24 (BINDER-PHYSICAL-LOCATION-IMPLEMENTATION-READINESS-01)

Quando usar: a 5256 foi aplicada e algo legítimo passou a falhar com
BINDER_POSITION_* (ex.: um caminho que ainda não usa a sobrecarga
confirmada), ou o frontend teve de voltar para a versão antiga.
Efeito: remove o gatilho de proteção e recria a leitura de 3 argumentos
(corpo canônico 5230, sem alteração). Não toca em dado algum.
Seguro a qualquer momento (só objetos; idempotente por IF EXISTS / precheck).
================================================================
*/

begin;

set local lock_timeout = '5s';

drop trigger if exists trg_physical_card_binder_position_guard on public.physical_card;
drop function if exists public.binder_position_guard_on_storage_change();

do $pre$
begin
  if to_regprocedure('public.get_my_collection_binder_unplaced(uuid, integer, integer)') is not null then
    raise exception 'R1: a leitura de 3 argumentos já existe — nada a recriar (rode só os DROPs acima, à parte)';
  end if;
end;
$pre$;

create function public.get_my_collection_binder_unplaced(
  p_collection_id uuid,
  p_limit         integer default 48,
  p_offset        integer default 0
)
returns table (
  collection_allocation_id uuid,
  physical_card_id         uuid,
  card_id                  uuid,
  card_variant_id          uuid,
  variant_type_id          uuid,
  card_name                text,
  collector_number         text,
  collector_total          integer,
  card_set_code            text,
  variant_label            text,
  language_code            text,
  image_path               text,
  total_count              integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  c_max_limit constant integer := 96;
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null or p_limit is null or p_offset is null
     or p_limit < 1 or p_limit > c_max_limit or p_offset < 0 or p_offset > 1000000 then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  perform 1 from public.collection c where c.id = p_collection_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;
  -- Sem fichário (próprio ou compartilhado) não há "fora do fichário".
  if not exists (select 1 from public.collection_layout l where l.collection_id = p_collection_id)
     and not exists (select 1 from public.collection_layout_guest g where g.collection_id = p_collection_id) then
    return;
  end if;

  return query
  with un as (
    select ca.id as allocation_id, ca.physical_card_id, ca.created_at
    from public.collection_allocation ca
    where ca.collection_id = p_collection_id
      and not exists (select 1 from public.collection_layout_slot_assignment a
                      where a.collection_allocation_id = ca.id)
  ),
  tot as (select count(*)::integer as n from un)
  select un.allocation_id,
         pc.id,
         c.id,
         cv.id,
         cv.variant_type_id,
         c.name::text,
         c.collector_number::text,
         c.collector_total,
         cs.code::text,
         nullif(concat_ws(' · ', vt.name, pp.name, ecx.name), '')::text,
         l.code::text,
         img.storage_path::text,
         tot.n
  from un
  cross join tot
  join public.physical_card pc on pc.id = un.physical_card_id
  join public.card_variant cv  on cv.id = pc.card_variant_id
  join public.card c           on c.id = cv.card_id
  join public.card_set cs      on cs.id = c.card_set_id
  left join public.language l  on l.id = pc.language_id
  left join public.card_variant_type vt            on vt.id = cv.variant_type_id
  left join public.card_printing_profile pp        on pp.id = cv.printing_profile_id
  left join public.card_edition_context_profile ecx on ecx.id = cv.edition_context_profile_id
  left join lateral (
    select ast.storage_path
    from public.card_asset ast
    join public.card_asset_type cat on cat.id = ast.asset_type_id and cat.code = 'CARD_FRONT'
    join public.language al         on al.id = ast.language_id
    where ast.card_id = c.id and ast.is_primary and ast.is_active and ast.storage_path is not null
    order by (ast.language_id = pc.language_id) desc nulls last,
             (al.code = 'pt-BR') desc, (al.code = 'en') desc, al.language_order asc
    limit 1
  ) img on true
  order by cs.code, c.collector_order nulls last, c.collector_number, cv.variant_order, un.created_at, un.allocation_id
  limit p_limit offset p_offset;
end;
$$;

revoke all on function public.get_my_collection_binder_unplaced(uuid, integer, integer) from public;
revoke all on function public.get_my_collection_binder_unplaced(uuid, integer, integer) from anon;
grant execute on function public.get_my_collection_binder_unplaced(uuid, integer, integer) to authenticated;

notify pgrst, 'reload schema';

commit;
