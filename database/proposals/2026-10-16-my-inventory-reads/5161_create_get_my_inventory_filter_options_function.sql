/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5161 - get_my_inventory_filter_options(): opções dos
              filtros de Meu acervo (MY-INVENTORY-IMPLEMENTATION-01,
              Etapa A)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-17
              (MY-INVENTORY-LIVE-DEPLOYMENT-01); validado pelo 5827 (52/52 PASS)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-16

Descrição...:
Opções derivadas SOMENTE do acervo do usuário da sessão — um filtro
nunca oferece um Set, idioma ou coleção sem exemplares dele:

  kind = 'SET'        value = card_set.code   label = card_set.name
  kind = 'LANGUAGE'   value = language.code   label = language.name
  kind = 'COLLECTION' value = collection.id   label = collection.name
                      (só coleções do próprio usuário com ao menos
                       um exemplar alocado)

item_count = número de exemplares naquela opção. sort_order define a
ordem de exibição dentro de cada kind (Sets: lançamento mais recente
primeiro; idiomas: language_order; coleções: nome).

O valor 'Sem coleção' não é uma linha: é um estado fixo da interface
(p_without_collection em 5159).

Segurança: SECURITY DEFINER, STABLE, search_path '', auth.uid()
obrigatório (28000), dono resolvido no servidor (inventory e
collection por owner_user_id), EXECUTE só para authenticated.

Performance: um agrupamento sobre os exemplares do usuário; catálogo
por PK. B4: p95 ≤ 150 ms em VR (5827, Seção P).

Como validar: Query 5827.
================================================================
*/

begin;

create or replace function public.get_my_inventory_filter_options()
returns table (
  kind       text,
  value      text,
  label      text,
  item_count bigint,
  sort_order integer
)
language plpgsql
security definer
stable
set search_path = ''
as $$
declare
  v_user      uuid := auth.uid();
  v_inventory uuid;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select i.id into v_inventory
  from public.inventory i
  where i.owner_user_id = v_user;

  if v_inventory is null then
    return;
  end if;

  return query
  with by_variant_language as (
    select pc.card_variant_id, pc.language_id, count(*) as n
    from public.physical_card pc
    where pc.inventory_id = v_inventory
    group by pc.card_variant_id, pc.language_id
  ),
  sets as (
    select cs.code::text as code, cs.name::text as name,
           sum(b.n)::bigint as n,
           (row_number() over (order by cs.release_date desc nulls last,
                                        cs.release_order desc nulls last,
                                        cs.code))::integer as ord
    from by_variant_language b
    join public.card_variant cv on cv.id = b.card_variant_id
    join public.card c          on c.id = cv.card_id
    join public.card_set cs     on cs.id = c.card_set_id
    group by cs.id, cs.code, cs.name, cs.release_date, cs.release_order
  ),
  langs as (
    select l.code, l.name, sum(b.n)::bigint as n,
           (row_number() over (order by l.language_order, l.code))::integer as ord
    from by_variant_language b
    join public.language l on l.id = b.language_id
    group by l.id, l.code, l.name, l.language_order
  ),
  cols as (
    select co.id::text as id, co.name, count(*)::bigint as n,
           (row_number() over (order by lower(co.name), co.id))::integer as ord
    from public.collection co
    join public.collection_allocation ca on ca.collection_id = co.id
    join public.physical_card pc         on pc.id = ca.physical_card_id
                                        and pc.inventory_id = v_inventory
    where co.owner_user_id = v_user
    group by co.id, co.name
  )
  select 'SET'::text, s.code, s.name, s.n, s.ord from sets s
  union all
  select 'LANGUAGE'::text, l.code, l.name, l.n, l.ord from langs l
  union all
  select 'COLLECTION'::text, c.id, c.name, c.n, c.ord from cols c
  order by 1, 5;
end;
$$;

comment on function public.get_my_inventory_filter_options() is
  'Meu acervo (Query 5161): Sets, idiomas e coleções presentes no acervo do usuário da sessão, com contagem de exemplares e ordem de exibição. Exige auth.uid().';

revoke all on function public.get_my_inventory_filter_options() from public;
revoke all on function public.get_my_inventory_filter_options() from anon;
grant execute on function public.get_my_inventory_filter_options() to authenticated;

commit;
