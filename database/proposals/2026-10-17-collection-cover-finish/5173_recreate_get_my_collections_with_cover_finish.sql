/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5173 - get_my_collections() v2: devolve cover_finish
              (R1, MY-COLLECTIONS-LIBRARY-VISUAL-02)
Versão......: 2.0 (sucede a 5168 v1.0; corpo idêntico + 1 coluna)
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-17

Objetivo:
A Biblioteca precisa da cor do fichário. Única mudança em relação à 5168:
coluna `cover_finish` (após `card_set_logo_path`). Como o tipo de retorno
muda, a função é recriada (DROP + CREATE) na mesma transação, com os mesmos
grants. O frontend detecta a coluna: quando ela aparece, o seletor de cor
passa a ser oferecido (antes disso não aparece).

Depende de: 5171.
Resultado esperado: mesma saída da 5168 + cover_finish (nula até a escolha).
Como validar: Query 5831 (Seção 3).
================================================================
*/

begin;

drop function if exists public.get_my_collections(boolean, integer, integer);

create or replace function public.get_my_collections(
  p_include_archived boolean default false,
  p_limit            integer default 48,
  p_offset           integer default 0
)
returns table (
  collection_id        uuid,
  name                 text,
  mode                 text,
  completion_policy    text,
  lifecycle_status     text,
  card_set_id          uuid,
  card_set_code        text,
  card_set_name        text,
  card_set_logo_path   text,
  cover_finish         text,
  total_positions      bigint,
  satisfied_positions  bigint,
  progress_percentage  numeric,
  is_complete          boolean,
  copies_count         bigint,
  cover_image_path     text,
  created_at           timestamptz,
  updated_at           timestamptz,
  total_count          bigint
)
language plpgsql
security definer
stable
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 100 or p_offset is null or p_offset < 0 then
    raise exception 'INVALID_PAGE' using errcode = '22023';
  end if;

  return query
  with mine as (
    select c.id, c.name, c.mode, c.completion_policy, c.lifecycle_status, c.cover_finish,
           c.created_at, c.updated_at,
           count(*) over () as total
    from public.collection c
    where c.owner_user_id = v_user
      and (coalesce(p_include_archived, false) or c.lifecycle_status = 'ACTIVE')
    order by (c.lifecycle_status = 'ACTIVE') desc, c.created_at desc, c.id
    limit p_limit offset p_offset
  )
  select
    m.id, m.name, m.mode, m.completion_policy, m.lifecycle_status,
    cs.id, cs.code::text, cs.name::text, cs.logo_storage_path::text,
    m.cover_finish,
    s.total_positions, s.satisfied_positions, s.progress_percentage, s.is_complete,
    coalesce(alloc.copies, 0)::bigint,
    cover.storage_path::text,
    m.created_at, m.updated_at, m.total
  from mine m
  left join public.collection_reference cr         on cr.collection_id = m.id
  left join public.collection_card_set_reference ccsr on ccsr.collection_reference_id = cr.id
  left join public.card_set cs                     on cs.id = ccsr.card_set_id
  left join lateral (
    select sm.total_positions, sm.satisfied_positions, sm.progress_percentage, sm.is_complete
    from public.collection_completion_summary(m.id) sm
  ) s on true
  left join lateral (
    select count(*) as copies
    from public.collection_allocation ca
    where ca.collection_id = m.id
  ) alloc on true
  left join lateral (
    select ast.storage_path
    from public.collection_allocation ca
    join public.physical_card pc on pc.id = ca.physical_card_id
    join public.card_variant cv  on cv.id = pc.card_variant_id
    join public.card_asset ast   on ast.card_id = cv.card_id
    join public.card_asset_type cat on cat.id = ast.asset_type_id and cat.code = 'CARD_FRONT'
    join public.language al      on al.id = ast.language_id
    where ca.collection_id = m.id
      and ast.is_primary
      and ast.is_active
      and ast.storage_path is not null
    order by ca.created_at desc, ca.id,
             (ast.language_id = pc.language_id) desc,
             (al.code = 'pt-BR') desc,
             (al.code = 'en') desc,
             al.language_order asc
    limit 1
  ) cover on true
  order by (m.lifecycle_status = 'ACTIVE') desc, m.created_at desc, m.id;
end;
$$;

comment on function public.get_my_collections(boolean, integer, integer) is
  'Minhas coleções (Query 5173, v2 da 5168): Biblioteca do usuário da sessão — Set de referência, cor do fichário, progresso canônico (5070/5083/5100), nº de cartas e capa. Paginada (≤ 100). Só coleções próprias.';

revoke all on function public.get_my_collections(boolean, integer, integer) from public;
revoke all on function public.get_my_collections(boolean, integer, integer) from anon;
grant execute on function public.get_my_collections(boolean, integer, integer) to authenticated;

commit;
