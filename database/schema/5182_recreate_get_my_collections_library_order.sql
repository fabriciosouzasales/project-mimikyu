/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5182 - get_my_collections() v3: ordem escolhida pelo
              colecionador (R1, LIBRARY-ORDER-01)
Versão......: 3.0 (sucede a 5173 v2.0; mesma assinatura, mesmas colunas)
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-18 (autorização
              de Fabrício) — ledger 20261018012446; 5835 v1.0 22/22 PASS
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-18

Única mudança em relação à 5173: a ordenação (CTE e resultado) passa a
ser `ativas primeiro → library_position ASC NULLS FIRST → created_at DESC
→ id`. Assinatura e tipo de retorno idênticos — CREATE OR REPLACE, sem
DROP; grants preservados (reaplicados por segurança). Sem nenhuma
reordenação (todas NULL) o resultado é idêntico ao da 5173.

Depende de: 5181.
Como validar: Query 5835 (Seção 3).
Como reverter: reexecutar 5173.
================================================================
*/

begin;

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
           c.library_position, c.created_at, c.updated_at,
           count(*) over () as total
    from public.collection c
    where c.owner_user_id = v_user
      and (coalesce(p_include_archived, false) or c.lifecycle_status = 'ACTIVE')
    order by (c.lifecycle_status = 'ACTIVE') desc, c.library_position asc nulls first, c.created_at desc, c.id
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
  order by (m.lifecycle_status = 'ACTIVE') desc, m.library_position asc nulls first, m.created_at desc, m.id;
end;
$$;

comment on function public.get_my_collections(boolean, integer, integer) is
  'Minhas coleções (Query 5182, v3 da 5168/5173): Biblioteca do usuário da sessão na ordem escolhida pelo colecionador (library_position, novas primeiro) — Set de referência, cor do fichário, progresso canônico (5070/5083/5100), nº de cartas e capa. Paginada (≤ 100). Só coleções próprias.';

revoke all on function public.get_my_collections(boolean, integer, integer) from public;
revoke all on function public.get_my_collections(boolean, integer, integer) from anon;
grant execute on function public.get_my_collections(boolean, integer, integer) to authenticated;

commit;
