/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5169 - get_my_collection_positions(): conteúdo de uma
              coleção de Set com arte e progresso por carta
              (R2, MY-COLLECTIONS-FOUNDATION-01)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-17 (autorização
              condicionada de Fabrício) — ledger 20261017152451; 5830 v1.1 35/35 PASS
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-17

Contexto:
Fluxo 3 (Ver progresso): grade de cartas do Set com "Tenho / Faltam",
arte real em 8:11, repetidas visíveis sem inflar o progresso (C-21) e
sugestão de cartas já possuídas fora da coleção (C-19 — nunca alocação
automática). collection_completion_positions (5071) tem a mesma
semântica de satisfação, mas não traz imagem nem contagens.

Contrato:
  get_my_collection_positions(p_collection_id uuid,
                              p_filter text default 'ALL',  -- ALL | OWNED | MISSING
                              p_limit integer default 200,
                              p_offset integer default 0)
  Uma linha por carta do Set referenciado, na ordem do Set:
    is_satisfied          — mesma regra de 5071 (qualquer variante da
                            carta alocada a esta coleção);
    copies_in_collection  — exemplares desta carta nesta coleção;
    copies_available      — exemplares desta carta no acervo do
                            usuário que não estão em nenhuma coleção;
    image_path            — CARD_FRONT da carta (idioma de um exemplar
                            alocado, depois pt-BR, depois en).
  Só coleções REFERENCE_BASED + STANDARD_SET com Set de referência;
  qualquer outra coleção, alheia ou inexistente → zero linhas (não
  enumera). total_count = total do filtro antes da paginação.

Segurança: SECURITY DEFINER, STABLE, search_path '', dono por
auth.uid() verificado antes de qualquer leitura de catálogo, EXECUTE
só authenticated.

Erros: 28000 not_authenticated; 22023 INVALID_FILTER / INVALID_PAGE.
Como validar: Query 5830.
================================================================
*/

begin;

create or replace function public.get_my_collection_positions(
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
    and c.completion_policy = 'STANDARD_SET';

  if v_set is null then
    return;
  end if;

  select i.id into v_inventory
  from public.inventory i
  where i.owner_user_id = v_user;

  return query
  with in_collection as (
    select cv.card_id, count(*)::integer as copies, min(pc.language_id::text)::uuid as lang
    from public.collection_allocation ca
    join public.physical_card pc on pc.id = ca.physical_card_id
    join public.card_variant cv  on cv.id = pc.card_variant_id
    where ca.collection_id = p_collection_id
    group by cv.card_id
  ),
  available as (
    select cv.card_id, count(*)::integer as copies
    from public.physical_card pc
    join public.card_variant cv on cv.id = pc.card_variant_id
    join public.card c          on c.id = cv.card_id and c.card_set_id = v_set
    where pc.inventory_id = v_inventory
      and not exists (select 1 from public.collection_allocation ca where ca.physical_card_id = pc.id)
    group by cv.card_id
  ),
  positions as (
    select c.id, c.collector_number::text as number, c.collector_total, c.name::text as card_name,
           c.collector_order,
           ic.copies as in_copies, ic.lang,
           av.copies as av_copies,
           (ic.card_id is not null) as satisfied
    from public.card c
    left join in_collection ic on ic.card_id = c.id
    left join available av     on av.card_id = c.id
    where c.card_set_id = v_set
  ),
  filtered as (
    select p.*, count(*) over () as total
    from positions p
    where v_filter = 'ALL'
       or (v_filter = 'OWNED' and p.satisfied)
       or (v_filter = 'MISSING' and not p.satisfied)
    order by p.collector_order, p.number, p.id
    limit p_limit offset p_offset
  )
  select f.id, f.number, f.collector_total, f.card_name,
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
    where ast.card_id = f.id
      and ast.is_primary
      and ast.is_active
      and ast.storage_path is not null
    order by (ast.language_id = f.lang) desc nulls last,
             (al.code = 'pt-BR') desc,
             (al.code = 'en') desc,
             al.language_order asc
    limit 1
  ) img on true
  order by f.collector_order, f.number, f.id;
end;
$$;

comment on function public.get_my_collection_positions(uuid, text, integer, integer) is
  'Minhas coleções (Query 5169): cartas do Set de uma coleção STANDARD_SET do usuário com arte, satisfação (mesma regra de 5071), exemplares na coleção e disponíveis no acervo. Filtro ALL/OWNED/MISSING, paginado (≤ 500). Coleção alheia → zero linhas.';

revoke all on function public.get_my_collection_positions(uuid, text, integer, integer) from public;
revoke all on function public.get_my_collection_positions(uuid, text, integer, integer) from anon;
grant execute on function public.get_my_collection_positions(uuid, text, integer, integer) to authenticated;

commit;
