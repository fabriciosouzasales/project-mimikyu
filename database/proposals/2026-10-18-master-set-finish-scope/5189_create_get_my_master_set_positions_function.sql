/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5189 - get_my_master_set_positions(): grade de uma coleção
              Master Set (uma linha por posição) — substitui 5084
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-18 (MASTER-SET-DOCUMENTATION-AND-CONTRACT-PROPOSAL-01)

Autoridade: LDM-192/LDM-193. Mesmo formato e convenções de 5169 (R2 do
Set padrão), para a página da coleção reaproveitar a grade.

Remove collection_master_set_scope_positions(uuid, boolean) (5084),
que lia a tabela antiga por card_variant_id e não tinha arte nem
contagens. Nenhum consumidor no frontend (conferido em 2026-10-18:
grep em web/ e supabase/ sem ocorrências).

Contrato:
  get_my_master_set_positions(p_collection_id uuid,
                              p_filter text default 'ALL',  -- ALL | OWNED | MISSING
                              p_limit integer default 200,  -- 1..500
                              p_offset integer default 0)
  Uma linha por posição, na ordem do Set (collector_order, número,
  acabamento por display_order; posição de secreta depois dos acabamentos
  da mesma carta):
    variant_type_id/code/name — NULL na posição de carta secreta;
    is_secret                 — número além do Set base;
    is_satisfied              — LDM-193;
    copies_in_collection      — exemplares desta coleção que satisfazem
                                a posição (repetidas aparecem aqui, não
                                no progresso);
    copies_available          — exemplares do acervo do usuário, fora de
                                qualquer coleção, que satisfariam a posição;
    image_path                — CARD_FRONT da carta (mesma regra de 5169);
    total_count               — total do filtro antes da paginação.
  Só coleções do próprio usuário, REFERENCE_BASED + MASTER_SET; qualquer
  outra, alheia ou inexistente → zero linhas (não enumera).

Segurança: SECURITY DEFINER, STABLE, search_path '', dono por auth.uid()
antes de qualquer leitura de catálogo, EXECUTE só authenticated.
Erros: 28000 not_authenticated; 22023 INVALID_FILTER / INVALID_PAGE.
Como validar: 5836 casos 6.x e 9.x; 5837.
================================================================
*/

begin;

drop function if exists public.collection_master_set_scope_positions(uuid, boolean);

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
      (select sum(ic.copies) from in_collection ic
        where ic.card_id = p.card_id
          and (p.variant_type_id is null or ic.variant_type_id = p.variant_type_id))::integer as in_copies,
      (select min(ic.lang::text)::uuid from in_collection ic
        where ic.card_id = p.card_id
          and (p.variant_type_id is null or ic.variant_type_id = p.variant_type_id)) as lang,
      (select sum(av.copies) from available av
        where av.card_id = p.card_id
          and (p.variant_type_id is null or av.variant_type_id = p.variant_type_id))::integer as av_copies
    from positions p
    join public.card c                    on c.id = p.card_id
    left join public.card_variant_type t  on t.id = p.variant_type_id
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
  'Master Set (Query 5189): posições (carta + acabamento, e carta secreta) de uma coleção MASTER_SET do usuário, com arte, satisfação (LDM-193), exemplares na coleção e disponíveis no acervo. Filtro ALL/OWNED/MISSING, paginado (≤ 500). Coleção alheia → zero linhas.';

revoke all on function public.get_my_master_set_positions(uuid, text, integer, integer) from public, anon;
grant execute on function public.get_my_master_set_positions(uuid, text, integer, integer) to authenticated;

commit;
