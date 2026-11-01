/*
================================================================
Projeto.....: Project Mimikyu
Query.......: LIVE_70 - Medição somente leitura do plano no fichário ME3
Versão......: 1.0
Status......: PREPARADO — NÃO EXECUTADO (P2 OPERATIONAL ROUTE CORRECTION-11, 2026-11-01)
Classe......: R1 (somente leitura). Não depende de 5341–5344 aplicadas.

Objetivo
  Medir o custo real do plano (5342) sobre os dados do fichário ME3 sem
  chamar prévia nem aplicação e sem escrever nada: o corpo SQL da 5342 v1.2
  (sha256 do arquivo eb319634b8f0f4cc8900263a72aaff28d88a0869d8bd72c021625a4a4eab27b6) é executado como SELECT puro, com os
  parâmetros resolvidos por um CTE (km_params) em vez de literais — nenhum
  UUID aparece no comando nem na saída.

Uso (uma chamada execute_sql por bloco)
  M2.0  conferência: o CTE km_params resolve exatamente 1 fichário.
  M2.1  EXPLAIN (ANALYZE, BUFFERS) do corpo, em transação somente leitura.
  M2.2  resumo agregado do resultado (contagens por tipo/motivo; sem ids).
Se a 5342 mudar, regerar este arquivo a partir do novo corpo.
================================================================
*/

-- M2.0 — deve devolver binders = 1
select count(*) as binders
from public.collection_layout l
join public.collection_reference r on r.collection_id = l.collection_id
join public.collection_card_set_reference s on s.collection_reference_id = r.id
join public.card_set cs on cs.id = s.card_set_id
where cs.code = 'ME3';

-- M2.1 — custo real (somente leitura)
set transaction read only;
explain (analyze, buffers, timing, verbose off, costs on)
with
  km_params as (
    select l.collection_id as pc, l.id as pl, l.storage_container_id as pb
    from public.collection_layout l
    join public.collection_reference r on r.collection_id = l.collection_id
    join public.collection_card_set_reference s on s.collection_reference_id = r.id
    join public.card_set cs on cs.id = s.card_set_id
    where cs.code = 'ME3'
  ),
  owner_ as (
    select c.owner_user_id as uid
    from public.collection c
    where c.id = (select pc from km_params)
  ),
  slots as (
    select s.id as sid, p.page_number as pg, s.row_index as rw, s.column_index as cl,
           e.card_id as e_card, e.card_variant_id as e_var, e.expected_variant_type_id as e_vt
    from public.collection_layout_page p
    join public.collection_layout_slot s on s.page_id = p.id
    join public.collection_layout_slot_expected_content e on e.slot_id = s.id
    where p.layout_id = (select pl from km_params)
      and (e.collection_id is null or e.collection_id = (select pc from km_params))
      and not s.locked
      and not exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = s.id)
      and not exists (select 1 from public.collection_layout_slot_image im where im.slot_id = s.id)
      and not exists (
        select 1 from public.collection_layout_region r
        where r.page_id = p.id
          and s.row_index    between r.top_row     and r.top_row     + r.height - 1
          and s.column_index between r.left_column and r.left_column + r.width  - 1)
  ),
  cands as (
    select pc.id as pid, pc.card_variant_id as var, cv.card_id as card, cv.variant_type_id as vt,
           cv.is_active as active
    from public.collection_allocation ca
    join public.physical_card pc on pc.id = ca.physical_card_id
    join public.inventory i on i.id = pc.inventory_id
    join owner_ o on o.uid = i.owner_user_id
    join public.card_variant cv on cv.id = pc.card_variant_id
    where ca.collection_id = (select pc from km_params)
      and pc.storage_container_id = (select pb from km_params)
      and not exists (select 1 from public.collection_layout_slot_assignment a where a.physical_card_id = pc.id)
  ),
  pairs as (
    select s.sid, c.pid, c.active
    from slots s
    join cands c
      on c.card = s.e_card
     and (s.e_var is null or s.e_var = c.var)
     and (s.e_vt  is null or s.e_vt  = c.vt)
  ),
  sdeg as (select pr.sid, count(*) as n from pairs pr group by pr.sid),
  cdeg as (select pr.pid, count(*) as n from pairs pr group by pr.pid),
  ins as (
    select s.sid, c.pid, s.pg, s.rw, s.cl, c.card, c.var,
           row_number() over (order by s.pg, s.rw, s.cl, s.sid)::integer as o
    from pairs pr
    join sdeg sd on sd.sid = pr.sid and sd.n = 1
    join cdeg cd on cd.pid = pr.pid and cd.n = 1
    join slots s on s.sid = pr.sid
    join cands c on c.pid = pr.pid
    where pr.active
  ),
  slot_peer as (   -- maior grau entre os exemplares compatíveis com cada bolso
    select pr.sid, max(cd.n) as mx from pairs pr join cdeg cd on cd.pid = pr.pid group by pr.sid
  ),
  card_reason as (
    select c.pid, c.card, c.var,
           case
             when not c.active then 'INACTIVE_VARIANT'
             when cd.n is null then 'NO_COMPATIBLE_RESERVATION'
             when cd.n > 1     then 'MULTIPLE_DESTINATIONS'
             else 'COMPETING_CANDIDATES'
           end as why
    from cands c
    left join cdeg cd on cd.pid = c.pid
    where not exists (select 1 from ins x where x.pid = c.pid)
  ),
  slot_reason as (
    select s.sid, s.pg, s.rw, s.cl, s.e_card, s.e_var,
           case
             when sd.n is null then 'NO_CANDIDATE'
             when sd.n > 1     then 'COMPETING_CANDIDATES'
             when sp.mx > 1    then 'MULTIPLE_DESTINATIONS'
             else 'INACTIVE_VARIANT'
           end as why
    from slots s
    left join sdeg sd on sd.sid = s.sid
    left join slot_peer sp on sp.sid = s.sid
    where not exists (select 1 from ins x where x.sid = s.sid)
  ),
  epoch as (
    select coalesce((select max(e.id)
                     from public.binder_activity_event e
                     join owner_ o on o.uid = e.owner_user_id
                     where e.layout_key = (select pl from km_params)
                       and e.event_type = 'CARDS_AUTO_ARRANGED'), 0)::text
           || '/'
           || coalesce((select cv.reason || '@' || (extract(epoch from cv.updated_at) * 1000000)::bigint::text
                        from public.binder_activity_coverage cv
                        join owner_ o on o.uid = cv.owner_user_id
                        where cv.layout_key = (select pl from km_params)), '-') as v
  ),
  tok as (
    select (select count(*) from ins)::integer as n,
           'aa1:' || encode(sha256(convert_to(
             'aa1.2|' || (select pc from km_params)::text || '|' || (select pl from km_params)::text || '|'
             || coalesce((select pb from km_params)::text, '-') || '|e=' || (select v from epoch)
             || '|' || (select count(*) from ins)::text
             || E'\n'
             || coalesce((select string_agg(x.sid::text || '|' || x.pid::text, E'\n' order by x.o) from ins x), ''),
             'UTF8')), 'hex') as t
  )
  select 'HEADER'::text, 0, null::uuid, null::uuid, null::integer, null::integer, null::integer,
         null::uuid, null::uuid, null::text, t.n, t.t
  from tok t
  union all
  select 'INSERT', x.o, x.sid, x.pid, x.pg, x.rw, x.cl, x.card, x.var, null, t.n, t.t
  from ins x cross join tok t
  union all
  select 'EXCLUDED_CARD', (row_number() over (order by r.why, r.pid))::integer, null, r.pid,
         null, null, null, r.card, r.var, r.why, t.n, t.t
  from card_reason r cross join tok t
  union all
  select 'UNFILLED_SLOT', (row_number() over (order by r.pg, r.rw, r.cl, r.sid))::integer, r.sid, null,
         r.pg, r.rw, r.cl, r.e_card, r.e_var, r.why, t.n, t.t
  from slot_reason r cross join tok t;

-- M2.2 — resumo sem identificadores
set transaction read only;
select item_kind, reason, count(*) as n, max(insert_count) as insert_count
from (
with
  km_params as (
    select l.collection_id as pc, l.id as pl, l.storage_container_id as pb
    from public.collection_layout l
    join public.collection_reference r on r.collection_id = l.collection_id
    join public.collection_card_set_reference s on s.collection_reference_id = r.id
    join public.card_set cs on cs.id = s.card_set_id
    where cs.code = 'ME3'
  ),
  owner_ as (
    select c.owner_user_id as uid
    from public.collection c
    where c.id = (select pc from km_params)
  ),
  slots as (
    select s.id as sid, p.page_number as pg, s.row_index as rw, s.column_index as cl,
           e.card_id as e_card, e.card_variant_id as e_var, e.expected_variant_type_id as e_vt
    from public.collection_layout_page p
    join public.collection_layout_slot s on s.page_id = p.id
    join public.collection_layout_slot_expected_content e on e.slot_id = s.id
    where p.layout_id = (select pl from km_params)
      and (e.collection_id is null or e.collection_id = (select pc from km_params))
      and not s.locked
      and not exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = s.id)
      and not exists (select 1 from public.collection_layout_slot_image im where im.slot_id = s.id)
      and not exists (
        select 1 from public.collection_layout_region r
        where r.page_id = p.id
          and s.row_index    between r.top_row     and r.top_row     + r.height - 1
          and s.column_index between r.left_column and r.left_column + r.width  - 1)
  ),
  cands as (
    select pc.id as pid, pc.card_variant_id as var, cv.card_id as card, cv.variant_type_id as vt,
           cv.is_active as active
    from public.collection_allocation ca
    join public.physical_card pc on pc.id = ca.physical_card_id
    join public.inventory i on i.id = pc.inventory_id
    join owner_ o on o.uid = i.owner_user_id
    join public.card_variant cv on cv.id = pc.card_variant_id
    where ca.collection_id = (select pc from km_params)
      and pc.storage_container_id = (select pb from km_params)
      and not exists (select 1 from public.collection_layout_slot_assignment a where a.physical_card_id = pc.id)
  ),
  pairs as (
    select s.sid, c.pid, c.active
    from slots s
    join cands c
      on c.card = s.e_card
     and (s.e_var is null or s.e_var = c.var)
     and (s.e_vt  is null or s.e_vt  = c.vt)
  ),
  sdeg as (select pr.sid, count(*) as n from pairs pr group by pr.sid),
  cdeg as (select pr.pid, count(*) as n from pairs pr group by pr.pid),
  ins as (
    select s.sid, c.pid, s.pg, s.rw, s.cl, c.card, c.var,
           row_number() over (order by s.pg, s.rw, s.cl, s.sid)::integer as o
    from pairs pr
    join sdeg sd on sd.sid = pr.sid and sd.n = 1
    join cdeg cd on cd.pid = pr.pid and cd.n = 1
    join slots s on s.sid = pr.sid
    join cands c on c.pid = pr.pid
    where pr.active
  ),
  slot_peer as (   -- maior grau entre os exemplares compatíveis com cada bolso
    select pr.sid, max(cd.n) as mx from pairs pr join cdeg cd on cd.pid = pr.pid group by pr.sid
  ),
  card_reason as (
    select c.pid, c.card, c.var,
           case
             when not c.active then 'INACTIVE_VARIANT'
             when cd.n is null then 'NO_COMPATIBLE_RESERVATION'
             when cd.n > 1     then 'MULTIPLE_DESTINATIONS'
             else 'COMPETING_CANDIDATES'
           end as why
    from cands c
    left join cdeg cd on cd.pid = c.pid
    where not exists (select 1 from ins x where x.pid = c.pid)
  ),
  slot_reason as (
    select s.sid, s.pg, s.rw, s.cl, s.e_card, s.e_var,
           case
             when sd.n is null then 'NO_CANDIDATE'
             when sd.n > 1     then 'COMPETING_CANDIDATES'
             when sp.mx > 1    then 'MULTIPLE_DESTINATIONS'
             else 'INACTIVE_VARIANT'
           end as why
    from slots s
    left join sdeg sd on sd.sid = s.sid
    left join slot_peer sp on sp.sid = s.sid
    where not exists (select 1 from ins x where x.sid = s.sid)
  ),
  epoch as (
    select coalesce((select max(e.id)
                     from public.binder_activity_event e
                     join owner_ o on o.uid = e.owner_user_id
                     where e.layout_key = (select pl from km_params)
                       and e.event_type = 'CARDS_AUTO_ARRANGED'), 0)::text
           || '/'
           || coalesce((select cv.reason || '@' || (extract(epoch from cv.updated_at) * 1000000)::bigint::text
                        from public.binder_activity_coverage cv
                        join owner_ o on o.uid = cv.owner_user_id
                        where cv.layout_key = (select pl from km_params)), '-') as v
  ),
  tok as (
    select (select count(*) from ins)::integer as n,
           'aa1:' || encode(sha256(convert_to(
             'aa1.2|' || (select pc from km_params)::text || '|' || (select pl from km_params)::text || '|'
             || coalesce((select pb from km_params)::text, '-') || '|e=' || (select v from epoch)
             || '|' || (select count(*) from ins)::text
             || E'\n'
             || coalesce((select string_agg(x.sid::text || '|' || x.pid::text, E'\n' order by x.o) from ins x), ''),
             'UTF8')), 'hex') as t
  )
  select 'HEADER'::text, 0, null::uuid, null::uuid, null::integer, null::integer, null::integer,
         null::uuid, null::uuid, null::text, t.n, t.t
  from tok t
  union all
  select 'INSERT', x.o, x.sid, x.pid, x.pg, x.rw, x.cl, x.card, x.var, null, t.n, t.t
  from ins x cross join tok t
  union all
  select 'EXCLUDED_CARD', (row_number() over (order by r.why, r.pid))::integer, null, r.pid,
         null, null, null, r.card, r.var, r.why, t.n, t.t
  from card_reason r cross join tok t
  union all
  select 'UNFILLED_SLOT', (row_number() over (order by r.pg, r.rw, r.cl, r.sid))::integer, r.sid, null,
         r.pg, r.rw, r.cl, r.e_card, r.e_var, r.why, t.n, t.t
  from slot_reason r cross join tok t
) plan (item_kind, ord, slot_id, physical_card_id, page_number, row_index, column_index,
        card_id, card_variant_id, reason, insert_count, plan_token)
group by 1, 2
order by 1, 2;
