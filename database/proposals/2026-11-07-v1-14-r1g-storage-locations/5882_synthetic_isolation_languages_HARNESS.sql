/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5882 - HARNESS sintético da 5354: dois titulares com a mesma variante e mesma variante
              em dois idiomas (QUERY 5354 FINAL SECURITY GATE-01) — termina em ROLLBACK
Status......: PROPOSTO — NÃO EXECUTADO (autorizado só com ROLLBACK)
Data........: 2026-11-07

Cenário sintético (criado e descartado na transação):
  - Variante V = uma variante pt-BR do titular A (maior acervo) com exemplar posicionado em página de
    fichário (dado real de A, só lido).
  - A ganha 2 exemplares sintéticos de V em inglês: 1 num recipiente ETB real de A, 1 sem local.
  - B (2º titular, inventário real vazio) ganha: recipientes "Q5882 B ETB" (ETB) e "Q5882 B Fichário"
    (BINDER); coleção livre "Q5882 B" com fichário digital 3x3 vinculado ao recipiente BINDER, página 7,
    bolso (1,1); 3 exemplares de V pt-BR (2 no ETB, 1 no fichário posicionado na página 7) e 2 de V em
    inglês (1 no ETB, 1 sem local).
Asserções
  T1a A: somente recipientes de A; nenhum recipiente/nome "Q5882 B"/página de B; contagens = físicos de A.
  T1b B: exatamente o cenário de B (pt-BR 3 = ETB 2 + Fichário 1 p.7; en 2 = ETB 1 + sem local 1);
      nenhum recipiente nem página de A.
  T1c Σ locais = exemplares em todas as linhas de A e de B.
  T2  uma linha por (V, idioma) para cada titular; contagens e locais independentes por idioma; sem
      duplicação por junção (copies = count(physical_card) por idioma); Σ linhas = físicos de V.
================================================================
*/
begin;
set local statement_timeout = '60s';
set local lock_timeout = '5s';

-- ===== Corpo da 5354 (idêntico ao arquivo da proposta) =====
create or replace function public.get_my_inventory_group_locations(p_card_variant_ids uuid[])
returns table (
  card_variant_id uuid,
  language_code   text,
  copies          integer,
  locations       jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user uuid := auth.uid();
  v_inventory uuid;
  v_count integer;
begin
  if v_user is null then
    raise exception 'INVENTORY_LOCATIONS_REQUIRES_AUTHENTICATION' using errcode = '28000';
  end if;
  if p_card_variant_ids is null then
    raise exception 'INVENTORY_LOCATIONS_EMPTY_INPUT' using errcode = '22023';
  end if;
  v_count := cardinality(p_card_variant_ids);
  if v_count = 0 then
    raise exception 'INVENTORY_LOCATIONS_EMPTY_INPUT' using errcode = '22023';
  end if;
  if array_ndims(p_card_variant_ids) <> 1 then
    raise exception 'INVENTORY_LOCATIONS_INVALID_PAYLOAD_SHAPE' using errcode = '22023';
  end if;
  if v_count > 500 then
    raise exception 'INVENTORY_LOCATIONS_TOO_MANY_IDS' using errcode = '22023';
  end if;

  select i.id into v_inventory from public.inventory i where i.owner_user_id = v_user;
  if v_inventory is null then
    return; -- titular sem acervo: nenhuma linha
  end if;

  return query
  with ids as (
    select distinct x as id from unnest(p_card_variant_ids) as x where x is not null
  ),
  cards as (
    select pc.id, pc.card_variant_id, l.code as language_code, pc.storage_container_id
    from public.physical_card pc
    join ids on ids.id = pc.card_variant_id
    join public.language l on l.id = pc.language_id
    where pc.inventory_id = v_inventory
  ),
  placed as (
    -- Página do fichário: só quando o exemplar está num slot do layout vinculado ao MESMO
    -- recipiente físico do exemplar (e o recipiente é do mesmo inventário).
    select c.id as physical_card_id, p.page_number
    from cards c
    join public.collection_layout_slot_assignment a on a.physical_card_id = c.id
    join public.collection_layout_slot s on s.id = a.slot_id
    join public.collection_layout_page p on p.id = s.page_id
    join public.collection_layout lay on lay.id = p.layout_id and lay.storage_container_id = c.storage_container_id
  ),
  per_place as (
    select c.card_variant_id, c.language_code, c.storage_container_id,
           sc.name, sc.kind_code, k.label as kind_label,
           count(*)::integer as copies,
           coalesce(array_agg(distinct pl.page_number order by pl.page_number) filter (where pl.page_number is not null), '{}') as pages
    from cards c
    left join public.storage_container sc on sc.id = c.storage_container_id and sc.inventory_id = v_inventory
    left join public.storage_container_kind k on k.code = sc.kind_code
    left join placed pl on pl.physical_card_id = c.id
    group by c.card_variant_id, c.language_code, c.storage_container_id, sc.name, sc.kind_code, k.label
  )
  select pp.card_variant_id, pp.language_code, sum(pp.copies)::integer,
         jsonb_agg(jsonb_build_object(
           'storage_container_id', pp.storage_container_id, 'name', pp.name, 'kind_code', pp.kind_code,
           'kind_label', pp.kind_label, 'copies', pp.copies, 'pages', to_jsonb(pp.pages))
           order by (pp.storage_container_id is null), pp.copies desc, pp.name, pp.storage_container_id)
  from per_place pp
  group by pp.card_variant_id, pp.language_code;
end;
$$;

revoke all on function public.get_my_inventory_group_locations(uuid[]) from public;
revoke all on function public.get_my_inventory_group_locations(uuid[]) from anon;
grant execute on function public.get_my_inventory_group_locations(uuid[]) to authenticated;

comment on function public.get_my_inventory_group_locations(uuid[]) is
  'V1-14 R1-G (Query 5354): localização física dos exemplares do titular por grupo variante + idioma (recipiente, quantidade, páginas do fichário vinculado). Somente leitura; titular por auth.uid(); 1..500 variantes; uma linha por grupo.';

create temp table _q5882 on commit drop as
with u as (
  select i.owner_user_id user_id, i.id inventory_id,
         row_number() over (order by (select count(*) from public.physical_card pc where pc.inventory_id = i.id) desc) rk
  from public.inventory i),
v as (
  select pc.card_variant_id
  from public.physical_card pc
  join public.collection_layout_slot_assignment a on a.physical_card_id = pc.id
  join public.language l on l.id = pc.language_id and l.code = 'pt-BR'
  where pc.inventory_id = (select inventory_id from u where rk = 1)
  order by pc.card_variant_id limit 1)
select (select user_id from u where rk = 1) a_user, (select inventory_id from u where rk = 1) a_inv,
       (select user_id from u where rk = 2) b_user, (select inventory_id from u where rk = 2) b_inv,
       (select card_variant_id from v) v,
       (select id from public.language where code = 'pt-BR') lang_pt, (select id from public.language where code = 'en') lang_en,
       (select sc.id from public.storage_container sc where sc.inventory_id = (select inventory_id from u where rk = 1) and sc.kind_code = 'ETB' order by sc.id limit 1) a_etb,
       (select c.game_id from public.collection c limit 1) game_id,
       null::uuid b_etb, null::uuid b_binder, null::uuid b_collection, null::uuid b_slot, null::uuid b_card_binder;

do $$
declare r record; v_col uuid; v_layout uuid; v_page uuid; v_slot uuid; v_etb uuid; v_bind uuid; v_card uuid; v_alloc uuid;
begin
  select * into r from _q5882;
  if r.v is null or r.a_etb is null or r.b_inv is null or r.lang_en is null then raise exception 'Q5882_PRE: cenário indisponível'; end if;
  if (select count(*) from public.physical_card where inventory_id = r.b_inv) <> 0 then raise exception 'Q5882_PRE: inventário B não está vazio'; end if;

  -- A: 2 exemplares sintéticos de V em inglês (1 no ETB real de A, 1 sem local)
  insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id) values
    (r.v, r.lang_en, r.a_inv, r.a_etb), (r.v, r.lang_en, r.a_inv, null);

  -- B: recipientes, coleção livre com fichário (página 7, bolso 1,1) e exemplares
  insert into public.storage_container (inventory_id, name, kind_code) values (r.b_inv, 'Q5882 B ETB', 'ETB') returning id into v_etb;
  insert into public.storage_container (inventory_id, name, kind_code) values (r.b_inv, 'Q5882 B Fichário', 'BINDER') returning id into v_bind;
  insert into public.collection (owner_user_id, game_id, default_storage_container_id, name, mode, completion_policy)
    values (r.b_user, r.game_id, v_bind, 'Q5882 B', 'OPEN_CURATION', 'NONE') returning id into v_col;
  insert into public.collection_layout (collection_id, grid_rows, grid_columns, storage_container_id) values (v_col, 3, 3, v_bind) returning id into v_layout;
  insert into public.collection_layout_page (layout_id, page_number) values (v_layout, 7) returning id into v_page;
  insert into public.collection_layout_slot (page_id, row_index, column_index) values (v_page, 1, 1) returning id into v_slot;
  insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id) values
    (r.v, r.lang_pt, r.b_inv, v_etb), (r.v, r.lang_pt, r.b_inv, v_etb),
    (r.v, r.lang_en, r.b_inv, v_etb), (r.v, r.lang_en, r.b_inv, null);
  insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id) values (r.v, r.lang_pt, r.b_inv, v_bind) returning id into v_card;
  insert into public.collection_allocation (physical_card_id, collection_id) values (v_card, v_col) returning id into v_alloc;
  insert into public.collection_layout_slot_assignment (slot_id, collection_allocation_id, physical_card_id) values (v_slot, v_alloc, v_card);

  update _q5882 set b_etb = v_etb, b_binder = v_bind, b_collection = v_col, b_slot = v_slot, b_card_binder = v_card;
  raise notice 'Q5882 cenário sintético criado';
end $$;

-- ---------- Titular A ----------
select set_config('request.jwt.claims', json_build_object('sub', (select a_user from _q5882), 'role', 'authenticated')::text, true);
create temp table _q5882_a on commit drop as select * from public.get_my_inventory_group_locations(array[(select v from _q5882)]);

-- ---------- Titular B ----------
select set_config('request.jwt.claims', json_build_object('sub', (select b_user from _q5882), 'role', 'authenticated')::text, true);
create temp table _q5882_b on commit drop as select * from public.get_my_inventory_group_locations(array[(select v from _q5882)]);

do $$
declare r record; v_n integer; v_a_containers uuid[]; v_a_pages int[]; v_b_pages int[];
begin
  select * into r from _q5882;
  select array_agg(id) into v_a_containers from public.storage_container where inventory_id = r.a_inv;
  -- páginas reais de A para V (via fichários de A)
  select coalesce(array_agg(distinct p.page_number), '{}') into v_a_pages
  from public.physical_card pc
  join public.collection_layout_slot_assignment a on a.physical_card_id = pc.id
  join public.collection_layout_slot s on s.id = a.slot_id
  join public.collection_layout_page p on p.id = s.page_id
  where pc.inventory_id = r.a_inv and pc.card_variant_id = r.v;

  -- T1a: A só vê o que é de A
  select count(*) into v_n from _q5882_a t, jsonb_array_elements(t.locations) e
  where (e ->> 'storage_container_id') is not null and not ((e ->> 'storage_container_id')::uuid = any (v_a_containers));
  if v_n <> 0 then raise exception 'Q5882_T1a_FOREIGN_CONTAINER: %', v_n; end if;
  select count(*) into v_n from _q5882_a t, jsonb_array_elements(t.locations) e where coalesce(e ->> 'name', '') like 'Q5882 B%';
  if v_n <> 0 then raise exception 'Q5882_T1a_FOREIGN_NAME: %', v_n; end if;
  select count(*) into v_n from _q5882_a t, jsonb_array_elements(t.locations) e, jsonb_array_elements_text(e -> 'pages') pg
  where not (pg::int = any (v_a_pages));
  if v_n <> 0 then raise exception 'Q5882_T1a_FOREIGN_PAGE: %', v_n; end if;
  select count(*) into v_n from _q5882_a t
  full join (select l.code language_code, count(*)::int copies from public.physical_card pc join public.language l on l.id = pc.language_id
             where pc.inventory_id = r.a_inv and pc.card_variant_id = r.v group by 1) e on e.language_code = t.language_code
  where t.copies is distinct from e.copies;
  if v_n <> 0 then raise exception 'Q5882_T1a_COUNTS: %', v_n; end if;

  -- T1b: B vê exatamente o cenário de B
  select count(*) into v_n from _q5882_b t, jsonb_array_elements(t.locations) e
  where (e ->> 'storage_container_id') is not null and (e ->> 'storage_container_id')::uuid = any (v_a_containers);
  if v_n <> 0 then raise exception 'Q5882_T1b_A_CONTAINER: %', v_n; end if;
  select array_agg(distinct pg::int) into v_b_pages from _q5882_b t, jsonb_array_elements(t.locations) e, jsonb_array_elements_text(e -> 'pages') pg;
  if v_b_pages is distinct from array[7] then raise exception 'Q5882_T1b_PAGES: %', v_b_pages; end if;
  if (select copies from _q5882_b where language_code = 'pt-BR') is distinct from 3 then raise exception 'Q5882_T1b_PT_COUNT'; end if;
  if (select copies from _q5882_b where language_code = 'en') is distinct from 2 then raise exception 'Q5882_T1b_EN_COUNT'; end if;
  if (select locations from _q5882_b where language_code = 'pt-BR') is distinct from jsonb_build_array(
        jsonb_build_object('storage_container_id', r.b_etb, 'name', 'Q5882 B ETB', 'kind_code', 'ETB', 'kind_label', (select label from public.storage_container_kind where code = 'ETB'), 'copies', 2, 'pages', '[]'::jsonb),
        jsonb_build_object('storage_container_id', r.b_binder, 'name', 'Q5882 B Fichário', 'kind_code', 'BINDER', 'kind_label', (select label from public.storage_container_kind where code = 'BINDER'), 'copies', 1, 'pages', '[7]'::jsonb))
  then raise exception 'Q5882_T1b_PT_LOCATIONS: %', (select locations from _q5882_b where language_code = 'pt-BR'); end if;
  if (select locations from _q5882_b where language_code = 'en') is distinct from jsonb_build_array(
        jsonb_build_object('storage_container_id', r.b_etb, 'name', 'Q5882 B ETB', 'kind_code', 'ETB', 'kind_label', (select label from public.storage_container_kind where code = 'ETB'), 'copies', 1, 'pages', '[]'::jsonb),
        jsonb_build_object('storage_container_id', null, 'name', null, 'kind_code', null, 'kind_label', null, 'copies', 1, 'pages', '[]'::jsonb))
  then raise exception 'Q5882_T1b_EN_LOCATIONS: %', (select locations from _q5882_b where language_code = 'en'); end if;

  -- T1c: Σ locais = exemplares (A e B)
  select count(*) into v_n from (select * from _q5882_a union all select * from _q5882_b) t
  where t.copies <> (select sum((e ->> 'copies')::int) from jsonb_array_elements(t.locations) e);
  if v_n <> 0 then raise exception 'Q5882_T1c_SUM: %', v_n; end if;

  -- T2: uma linha por (V, idioma) por titular; sem duplicação; total = físicos
  if (select count(*) from _q5882_a) <> 2 or (select count(distinct language_code) from _q5882_a) <> 2 then raise exception 'Q5882_T2_A_ROWS'; end if;
  if (select count(*) from _q5882_b) <> 2 or (select count(distinct language_code) from _q5882_b) <> 2 then raise exception 'Q5882_T2_B_ROWS'; end if;
  if (select sum(copies) from _q5882_a) <> (select count(*) from public.physical_card where inventory_id = r.a_inv and card_variant_id = r.v) then raise exception 'Q5882_T2_A_TOTAL'; end if;
  if (select sum(copies) from _q5882_b) <> 5 then raise exception 'Q5882_T2_B_TOTAL'; end if;
  if (select copies from _q5882_a where language_code = 'en') <> 2 then raise exception 'Q5882_T2_A_EN'; end if;
  raise notice 'Q5882 T1a T1b T1c T2 PASS';
end $$;

-- Evidência (somente leitura; sem identificadores reais)
select jsonb_build_object(
  'variant_pages_of_A', (select coalesce(jsonb_agg(distinct pg), '[]') from _q5882_a t, jsonb_array_elements(t.locations) e, jsonb_array_elements_text(e -> 'pages') pg),
  'A', (select jsonb_agg(jsonb_build_object('lang', language_code, 'copies', copies,
          'locations', (select jsonb_agg(jsonb_build_object('kind', e ->> 'kind_code', 'copies', e -> 'copies', 'pages', e -> 'pages', 'synthetic_B', coalesce(e ->> 'name', '') like 'Q5882 B%')) from jsonb_array_elements(locations) e)) order by language_code) from _q5882_a),
  'B', (select jsonb_agg(jsonb_build_object('lang', language_code, 'copies', copies,
          'locations', (select jsonb_agg(jsonb_build_object('name', e ->> 'name', 'kind', e ->> 'kind_code', 'copies', e -> 'copies', 'pages', e -> 'pages')) from jsonb_array_elements(locations) e)) order by language_code) from _q5882_b)
) evidence;

rollback;
