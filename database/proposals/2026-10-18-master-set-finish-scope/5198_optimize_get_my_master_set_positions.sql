/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5198 - get_my_master_set_positions(): desempenho da grade
              (agregação única no lugar de subconsultas por posição)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO — LIVE 2026-10-18, ledger 20261018193302
              (autorização de Fabrício); corpo md5 553272f5… = arquivo.
              Validado: 5836 v1.3 74/74 PASS, 5837 v1.2 10/10 PASS.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-18 (MASTER-SET LIVE-EXECUTION, após 5837 v1.1 e 5841)

Por quê: no LIVE a grade (5189) levou 1.241–1.877 ms por página no maior
Set (2.492 exemplares, 336 posições; limite 300 ms). O 5841 mostrou o plano
real: a CTE "available" é usada uma única vez, então o PostgreSQL a
incorpora na subconsulta correlacionada e varre os 2.492 exemplares do
acervo para cada uma das 336 posições (SubPlan 4: 336 loops × 6,18 ms,
837.312 laços internos, 3,39 milhões de buffers). As subconsultas sobre
in_collection também releem a CTE inteira por posição.

O que muda (só o cálculo por posição, dentro de pos_rows):
  - exemplares na coleção, idioma e exemplares disponíveis passam a vir de
    junções com agregações feitas UMA vez: por par (carta, acabamento) —
    in_collection e available, como já existiam — e por carta
    (in_by_card, available_by_card), esta última para a posição de carta
    secreta, que aceita qualquer acabamento da carta;
  - regra inalterada: posição com acabamento soma só o par exato; posição
    de carta secreta (acabamento nulo) soma todos os acabamentos da carta;
    idioma = menor language_id em texto, como antes.

O que NÃO muda: assinatura, colunas de retorno, filtro, paginação,
ordenação, total_count, imagem, autorização (auth.uid() + dono +
MASTER_SET), SECURITY DEFINER, STABLE, search_path '' e grants.

Evidência (5841, LIVE, escrita revertida): forma atual 1.876,5 ms; forma
nova 33,1 ms; resultado IGUAL (336 linhas, md5 9a4113f1cc1d9a2ca4aab122ac329d51).
Como validar: 5836 (74 casos, inclui exemplares disponíveis e carta
secreta) e 5837 P1.2 (grade < 300 ms).
================================================================
*/

begin;

create or replace function public.get_my_master_set_positions(
  p_collection_id uuid,
  p_filter        text    default 'ALL',
  p_limit         integer default 200,
  p_offset        integer default 0
)
returns table (
  card_id              uuid,
  collector_number     text,
  collector_total      integer,
  card_name            text,
  variant_type_id      uuid,
  variant_type_code    text,
  variant_type_name    text,
  is_secret            boolean,
  image_path           text,
  is_satisfied         boolean,
  copies_in_collection integer,
  copies_available     integer,
  total_count          bigint
)
language plpgsql
security definer
stable
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user      uuid := auth.uid();
  v_filter    text := upper(btrim(coalesce(p_filter, 'ALL')));
  v_inventory uuid;
  v_set       uuid;
  v_types     uuid[];
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if v_filter not in ('ALL', 'OWNED', 'MISSING') then
    raise exception 'INVALID_FILTER' using errcode = '22023';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 500 or p_offset is null or p_offset < 0 then
    raise exception 'INVALID_PAGE' using errcode = '22023';
  end if;

  -- Fronteira de autorização antes de qualquer tabela de catálogo.
  select ccsr.card_set_id into v_set
  from public.collection c
  join public.collection_reference cr            on cr.collection_id = c.id
  join public.collection_card_set_reference ccsr on ccsr.collection_reference_id = cr.id
  where c.id = p_collection_id
    and c.owner_user_id = v_user
    and c.mode = 'REFERENCE_BASED'
    and c.completion_policy = 'MASTER_SET';

  if v_set is null then
    return;
  end if;

  select array_agg(f.variant_type_id) into v_types
  from public.collection_master_set_finish f
  where f.collection_id = p_collection_id;

  select i.id into v_inventory
  from public.inventory i
  where i.owner_user_id = v_user;

  return query
  with positions as (
    select p.card_id, p.variant_type_id, p.is_secret
    from public.master_set_positions(v_set, v_types) p
  ),
  in_collection as (
    select cv.card_id, cv.variant_type_id, count(*)::integer as copies,
           min(pc.language_id::text)::uuid as lang
    from public.collection_allocation ca
    join public.physical_card pc on pc.id = ca.physical_card_id
    join public.card_variant cv  on cv.id = pc.card_variant_id
    where ca.collection_id = p_collection_id
    group by cv.card_id, cv.variant_type_id
  ),
  available as (
    select cv.card_id, cv.variant_type_id, count(*)::integer as copies
    from public.physical_card pc
    join public.card_variant cv on cv.id = pc.card_variant_id
    join public.card c          on c.id = cv.card_id and c.card_set_id = v_set
    where pc.inventory_id = v_inventory
      and not exists (select 1 from public.collection_allocation ca where ca.physical_card_id = pc.id)
    group by cv.card_id, cv.variant_type_id
  ),
  -- 5198: totais por carta, para a posição de carta secreta (acabamento nulo)
  in_by_card as (
    select ic.card_id, sum(ic.copies)::integer as copies, min(ic.lang::text) as lang
    from in_collection ic
    group by ic.card_id
  ),
  available_by_card as (
    select av.card_id, sum(av.copies)::integer as copies
    from available av
    group by av.card_id
  ),
  pos_rows as (
    select
      c.id                         as card_id,
      c.collector_number::text     as number,
      c.collector_total            as collector_total,
      c.name::text                 as card_name,
      c.collector_order            as collector_order,
      p.variant_type_id            as variant_type_id,
      t.code::text                 as type_code,
      t.name::text                 as type_name,
      coalesce(t.display_order, 2147483647) as type_order,
      p.is_secret                  as is_secret,
      case when p.variant_type_id is null then icc.copies else icp.copies end as in_copies,
      (case when p.variant_type_id is null then icc.lang else icp.lang::text end)::uuid as lang,
      case when p.variant_type_id is null then avc.copies else avp.copies end as av_copies
    from positions p
    join public.card c                    on c.id = p.card_id
    left join public.card_variant_type t  on t.id = p.variant_type_id
    left join in_collection icp           on icp.card_id = p.card_id and icp.variant_type_id = p.variant_type_id
    left join in_by_card icc              on icc.card_id = p.card_id
    left join available avp               on avp.card_id = p.card_id and avp.variant_type_id = p.variant_type_id
    left join available_by_card avc       on avc.card_id = p.card_id
  ),
  filtered as (
    select r.*, (coalesce(r.in_copies, 0) > 0) as satisfied, count(*) over () as total
    from pos_rows r
    where v_filter = 'ALL'
       or (v_filter = 'OWNED'   and coalesce(r.in_copies, 0) > 0)
       or (v_filter = 'MISSING' and coalesce(r.in_copies, 0) = 0)
    order by r.collector_order, r.number, r.type_order, r.card_id
    limit p_limit offset p_offset
  )
  select f.card_id, f.number, f.collector_total, f.card_name,
         f.variant_type_id, f.type_code, f.type_name, f.is_secret,
         img.storage_path::text,
         f.satisfied,
         coalesce(f.in_copies, 0),
         coalesce(f.av_copies, 0),
         f.total
  from filtered f
  left join lateral (
    select ast.storage_path
    from public.card_asset ast
    join public.card_asset_type cat on cat.id = ast.asset_type_id and cat.code = 'CARD_FRONT'
    join public.language al         on al.id = ast.language_id
    where ast.card_id = f.card_id
      and ast.is_primary
      and ast.is_active
      and ast.storage_path is not null
    order by (ast.language_id = f.lang) desc nulls last,
             (al.code = 'pt-BR') desc,
             (al.code = 'en') desc,
             al.language_order asc
    limit 1
  ) img on true
  order by f.collector_order, f.number, f.type_order, f.card_id;
end;
$$;

comment on function public.get_my_master_set_positions(uuid, text, integer, integer) is
  'Master Set (Query 5189, desempenho revisto na 5198): posições (carta + acabamento, e carta secreta) de uma coleção MASTER_SET do usuário, com arte, satisfação (LDM-193), exemplares na coleção e disponíveis no acervo. Filtro ALL/OWNED/MISSING, paginado (≤ 500). Coleção alheia → zero linhas.';

revoke all on function public.get_my_master_set_positions(uuid, text, integer, integer) from public, anon;
grant execute on function public.get_my_master_set_positions(uuid, text, integer, integer) to authenticated;

commit;
