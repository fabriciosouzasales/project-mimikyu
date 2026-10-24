/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5251 - Montagem do fichário só com exemplares do local físico
              collection_binder_plan(uuid, int, int, text) — CREATE OR REPLACE
Versão......: 1.0 (2026-10-24, BINDER-PHYSICAL-LOCATION-ELIGIBILITY-DECISIONS-01)
Status......: PROPOSTA — NÃO EXECUTADA. Depois da 5248 (README §6).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-24

Por quê: com a 5248, um bolso só aceita exemplar guardado no local físico
do fichário. A montagem automática (5224) posicionava TODAS as cartas da
coleção, estivessem onde estivessem; um exemplar guardado em outro lugar
faria a montagem inteira falhar no gatilho de integridade.
O que muda (só isto; o resto do corpo é byte a byte o canônico
database/schema/5224, conferido pelo static_check S6):
  1. alloc considera só exemplares guardados no local padrão da coleção
     (BINDER — a 5224 já exige), que é o local que a 5247 grava no fichário;
  2. c_version 'p2a1-plan-v1' → 'p2a1-plan-v2' (prévias anteriores à
     aplicação recebem PLAN_CHANGED e pedem nova prévia).
Efeito: cartas da coleção guardadas em outro lugar não ganham bolso na
montagem (no Set/Master Set/Pokédex o bolso fica com a reserva, vazio);
quando forem guardadas no fichário, aparecem em "Cartas disponíveis".
Assinatura, retorno, SECURITY INVOKER e ACL inalterados.
Dependências: 5224, 5247, 5248.
================================================================
*/

begin;

do $pre$
begin
  if to_regprocedure('public.collection_binder_plan(uuid, integer, integer, text)') is null then
    raise exception 'PRECHECK 5251: collection_binder_plan (5224) ausente';
  end if;
  if (select position('p2a1-plan-v1' in p.prosrc) = 0 from pg_proc p
      where p.oid = 'public.collection_binder_plan(uuid, integer, integer, text)'::regprocedure) then
    raise exception 'PRECHECK 5251: corpo vivo não é o canônico v1 da 5224';
  end if;
end;
$pre$;

create or replace function public.collection_binder_plan(
  p_collection_id uuid,
  p_grid_columns  integer,
  p_grid_rows     integer,
  p_extra_policy  text
)
returns table (
  item_kind                text,     -- HEADER | POSITION | EXTRA
  item_ord                 integer,  -- 0 no HEADER; 1.. por tipo
  page_number              integer,  -- null: adicional sem bolso
  row_index                integer,
  column_index             integer,
  expected_card_id         uuid,
  expected_variant_type_id uuid,
  collection_allocation_id uuid,
  extra_category           text,
  main_count               integer,
  extra_count              integer,
  pages_total              integer,
  plan_token               text
)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  c_version  constant text := 'p2a1-plan-v2';
  v_cap      integer;
  v_mode     text;
  v_policy   text;
  v_kind     text;
  v_set      uuid;
  v_types    uuid[] := '{}';
  v_types_k  text := '';
  v_ref      uuid;
  v_dex      uuid;
  v_scope    text;
begin
  if p_collection_id is null or p_grid_columns is null or p_grid_rows is null
     or p_grid_columns < 1 or p_grid_rows < 1 then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  if p_extra_policy is null or p_extra_policy not in ('PRINCIPAL_ONLY', 'APPEND_PAGES') then
    raise exception 'INVALID_EXTRA_POLICY' using errcode = '22023';
  end if;
  v_cap := p_grid_columns * p_grid_rows;

  select c.mode, c.completion_policy into v_mode, v_policy
  from public.collection c where c.id = p_collection_id;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  v_kind := case
    when v_mode = 'OPEN_CURATION' then 'FREE'
    when v_policy = 'STANDARD_SET' then 'SET'
    when v_policy = 'MASTER_SET' then 'MASTER_SET'
    when v_policy = 'REFERENCE_POSITION' then 'POKEDEX'
    else null end;
  if v_kind is null then
    raise exception 'COLLECTION_KIND_UNSUPPORTED' using errcode = '22023';
  end if;

  if v_kind in ('SET', 'MASTER_SET') then
    select ccsr.card_set_id into v_set
    from public.collection_reference cr
    join public.collection_card_set_reference ccsr on ccsr.collection_reference_id = cr.id
    where cr.collection_id = p_collection_id;
    if v_set is null then
      raise exception 'COLLECTION_REFERENCE_MISSING' using errcode = 'P0001';
    end if;
  end if;

  if v_kind = 'MASTER_SET' then
    select coalesce(array_agg(f.variant_type_id order by f.variant_type_id), '{}')
      into v_types
    from public.collection_master_set_finish f
    where f.collection_id = p_collection_id;
    v_types_k := array_to_string(v_types, ',');
  end if;

  if v_kind = 'POKEDEX' then
    select cr.id, cpr.pokedex_id, cpr.scope_kind into v_ref, v_dex, v_scope
    from public.collection_reference cr
    join public.collection_pokedex_reference cpr on cpr.collection_reference_id = cr.id
    where cr.collection_id = p_collection_id and cr.reference_kind = 'POKEDEX';
    if v_ref is null then
      raise exception 'COLLECTION_REFERENCE_MISSING' using errcode = 'P0001';
    end if;
  end if;

  return query
  with
  alloc as (
    select ca.id                as alloc_id,
           ca.created_at        as alloc_created,
           pc.id                as pc_id,
           pc.created_at        as pc_created,
           pc.language_id       as lang_id,
           l.language_order     as lord,
           cv.id                as var_id,
           cv.card_id           as card_id,
           cv.variant_type_id   as vt_id,
           cv.variant_order     as vord,
           coalesce(vt.display_order, 2147483647) as vt_ord,
           c.collector_order    as c_ord,
           cs.code::text        as set_code,
           pa.pokedex_position_id as link_pos,
           pa.assigned_at       as assigned_at,
           (pr.collection_allocation_id is not null) as is_rep
    from public.collection_allocation ca
    join public.physical_card pc on pc.id = ca.physical_card_id
    join public.card_variant cv  on cv.id = pc.card_variant_id
    join public.card c           on c.id = cv.card_id
    join public.card_set cs      on cs.id = c.card_set_id
    join public.language l       on l.id = pc.language_id
    left join public.card_variant_type vt on vt.id = cv.variant_type_id
    left join public.collection_pokedex_position_assignment pa
           on v_kind = 'POKEDEX' and pa.collection_allocation_id = ca.id
    left join public.collection_pokedex_position_primary_representative pr
           on v_kind = 'POKEDEX' and pr.collection_allocation_id = ca.id
          and pr.collection_id = p_collection_id
    where ca.collection_id = p_collection_id
      -- 5251: só exemplares GUARDADOS no fichário físico (local padrão BINDER
      -- da coleção, que a montagem grava como local do fichário — 5247).
      and pc.storage_container_id is not distinct from
          (select c0.default_storage_container_id from public.collection c0 where c0.id = p_collection_id)
  ),
  dex_pos as (
    select pp.id as pos_id, pp.position_number as pnum
    from public.pokedex_position pp
    join public.pokemon_species s on s.id = pp.species_id
    where v_kind = 'POKEDEX'
      and pp.pokedex_id = v_dex
      and pp.id in (select a.link_pos from alloc a where a.link_pos is not null)
      and (v_scope = 'FULL_REFERENCE'
           or exists (select 1 from public.collection_pokedex_scope_generation sg
                      where sg.collection_reference_id = v_ref
                        and sg.generation_id = s.generation_id))
  ),
  pos as (
    select c.id::text as pos_key, c.id as exp_card, null::uuid as exp_vt,
           (row_number() over (order by c.collector_order, c.collector_number, c.id))::integer as pos_ord
    from public.card c
    where v_kind = 'SET' and c.card_set_id = v_set
    union all
    select m.card_id::text || ':' || coalesce(m.variant_type_id::text, '*'),
           m.card_id, m.variant_type_id,
           (row_number() over (order by c.collector_order, c.collector_number, c.id,
                                        (m.variant_type_id is null),
                                        coalesce(t.display_order, 2147483647),
                                        m.variant_type_id))::integer
    from public.master_set_positions(case when v_kind = 'MASTER_SET' then v_set end, v_types) m
    join public.card c on c.id = m.card_id
    left join public.card_variant_type t on t.id = m.variant_type_id
    where v_kind = 'MASTER_SET'
    union all
    select d.pos_id::text, null::uuid, null::uuid,
           (row_number() over (order by d.pnum, d.pos_id))::integer
    from dex_pos d
    union all
    select a.alloc_id::text, null::uuid, null::uuid,
           (row_number() over (order by a.alloc_created, a.set_code, a.c_ord, a.vt_ord,
                                        a.vord, a.lord, a.pc_created, a.pc_id))::integer
    from alloc a
    where v_kind = 'FREE'
  ),
  grouped as (
    select a.*,
           case v_kind
             when 'SET'        then p_card.pos_key
             when 'MASTER_SET' then coalesce(p_type.pos_key, p_star.pos_key)
             when 'POKEDEX'    then p_dex.pos_key
             when 'FREE'       then a.alloc_id::text
           end as grp,
           case when v_kind = 'POKEDEX' then (case when a.is_rep then 0 else 1 end) else 0 end as k_rep,
           case when v_kind = 'POKEDEX' then a.assigned_at end                               as k_assigned,
           case when v_kind = 'POKEDEX' then 0 else a.vt_ord end                             as k_vt,
           case when v_kind = 'POKEDEX' then 0 else a.vord end                               as k_vord,
           case when v_kind = 'POKEDEX' then 0 else a.lord end                               as k_lord,
           case when v_kind = 'POKEDEX'
                then (case when a.link_pos is null then a.alloc_created end)
                else a.pc_created end                                                        as k_created,
           case when v_kind = 'POKEDEX' then a.alloc_id else a.pc_id end                      as k_tie
    from alloc a
    left join pos p_card on v_kind = 'SET'        and p_card.pos_key = a.card_id::text
    left join pos p_type on v_kind = 'MASTER_SET' and p_type.pos_key = a.card_id::text || ':' || a.vt_id::text
    left join pos p_star on v_kind = 'MASTER_SET' and p_star.pos_key = a.card_id::text || ':*'
    left join pos p_dex  on v_kind = 'POKEDEX'    and p_dex.pos_key  = a.link_pos::text
  ),
  ranked as (
    select g.*,
           row_number() over (partition by g.grp
                              order by g.k_rep, g.k_assigned nulls last, g.k_vt, g.k_vord, g.k_lord,
                                       g.k_created nulls last, g.k_tie) as rk,
           row_number() over (partition by g.grp, g.var_id, g.lang_id
                              order by g.k_rep, g.k_assigned nulls last, g.k_vt, g.k_vord, g.k_lord,
                                       g.k_created nulls last, g.k_tie) as rk_vl,
           row_number() over (partition by g.grp, g.var_id
                              order by g.k_rep, g.k_assigned nulls last, g.k_vt, g.k_vord, g.k_lord,
                                       g.k_created nulls last, g.k_tie) as rk_v
    from grouped g
  ),
  main as (
    select p.pos_ord as m_ord, p.exp_card, p.exp_vt, r.alloc_id
    from pos p
    left join ranked r on r.grp = p.pos_key and r.rk = 1
  ),
  extras as (
    select r.alloc_id,
           case when r.grp is null then 'OUT_OF_OBJECTIVE'
                when r.rk_vl > 1  then 'IDENTICAL_COPY'
                when r.rk_v  > 1  then 'OTHER_LANGUAGE'
                else 'OTHER_VARIANT' end as category,
           (row_number() over (order by (r.grp is null), p.pos_ord nulls last,
                                        case when v_kind in ('SET', 'MASTER_SET') then r.c_ord else 0 end,
                                        case when v_kind in ('SET', 'MASTER_SET') then r.card_id end,
                                        r.k_rep, r.k_assigned nulls last, r.k_vt, r.k_vord, r.k_lord,
                                        r.k_created nulls last, r.k_tie))::integer as x_ord
    from ranked r
    left join pos p on p.pos_key = r.grp
    where r.grp is null or r.rk > 1
  ),
  geo as (
    select d.m_cnt, d.e_cnt,
           ((d.m_cnt + v_cap - 1) / v_cap)::integer as main_pages,
           (case when p_extra_policy = 'APPEND_PAGES' then (d.e_cnt + v_cap - 1) / v_cap else 0 end)::integer as extra_pages
    from (select (select count(*) from main)::integer as m_cnt,
                 (select count(*) from extras)::integer as e_cnt) d
  ),
  placed as (
    select 'POSITION'::text as k,
           m.m_ord as o,
           ((m.m_ord - 1) / v_cap + 1)::integer as pg,
           (((m.m_ord - 1) % v_cap) / p_grid_columns + 1)::integer as rw,
           (((m.m_ord - 1) % v_cap) % p_grid_columns + 1)::integer as cl,
           m.exp_card as ec, m.exp_vt as ev, m.alloc_id as al, null::text as cat
    from main m
    union all
    select 'EXTRA'::text,
           x.x_ord,
           case when p_extra_policy = 'APPEND_PAGES'
                then (g.main_pages + (x.x_ord - 1) / v_cap + 1)::integer end,
           case when p_extra_policy = 'APPEND_PAGES'
                then (((x.x_ord - 1) % v_cap) / p_grid_columns + 1)::integer end,
           case when p_extra_policy = 'APPEND_PAGES'
                then (((x.x_ord - 1) % v_cap) % p_grid_columns + 1)::integer end,
           null::uuid, null::uuid, x.alloc_id, x.category
    from extras x
    cross join geo g
  ),
  tok as (
    select 'v1:' || encode(sha256(convert_to(
             c_version || '|' || p_collection_id::text || '|' || v_kind || '|' || coalesce(v_policy, '') || '|'
             || p_grid_columns::text || 'x' || p_grid_rows::text || '|' || p_extra_policy || '|' || v_types_k || '|'
             || (select greatest(1, g.main_pages + g.extra_pages)::text from geo g)
             || E'\n'
             || coalesce(string_agg(
                  concat_ws('|', pl.k, pl.o,
                            coalesce(pl.pg::text, '-'), coalesce(pl.rw::text, '-'), coalesce(pl.cl::text, '-'),
                            coalesce(pl.ec::text, '-'), coalesce(pl.ev::text, '-'),
                            coalesce(pl.al::text, '-'), coalesce(pl.cat, '-')),
                  E'\n' order by pl.k, pl.o), ''),
             'UTF8')), 'hex') as t
    from placed pl
  )
  select 'HEADER'::text, 0, null::integer, null::integer, null::integer, null::uuid, null::uuid, null::uuid, null::text,
         g.m_cnt, g.e_cnt, greatest(1, g.main_pages + g.extra_pages)::integer, t.t
  from geo g cross join tok t
  union all
  select pl.k, pl.o, pl.pg, pl.rw, pl.cl, pl.ec, pl.ev, pl.al, pl.cat,
         g.m_cnt, g.e_cnt, greatest(1, g.main_pages + g.extra_pages)::integer, t.t
  from placed pl cross join geo g cross join tok t;
end;
$$;

revoke all on function public.collection_binder_plan(uuid, integer, integer, text) from public;
revoke all on function public.collection_binder_plan(uuid, integer, integer, text) from anon;
revoke all on function public.collection_binder_plan(uuid, integer, integer, text) from authenticated;
revoke all on function public.collection_binder_plan(uuid, integer, integer, text) from service_role;

commit;

/*
Como validar (só leitura):
select position('p2a1-plan-v2' in prosrc) > 0 and position('storage_container_id' in prosrc) > 0
from pg_proc where oid = 'public.collection_binder_plan(uuid, integer, integer, text)'::regprocedure;
*/
