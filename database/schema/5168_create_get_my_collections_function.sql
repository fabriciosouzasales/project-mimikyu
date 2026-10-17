/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5168 - get_my_collections(): Biblioteca "Minhas
              coleções" (R1, MY-COLLECTIONS-FOUNDATION-01)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-17 (autorização
              condicionada de Fabrício) — ledger 20261017152431; 5830 v1.1 35/35 PASS
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-17

Contexto:
A Biblioteca (N2, três modos — Lista/Cards/Carrossel, mesmo núcleo de
dados) precisa, numa única chamada: nome, tipo, Set de referência
(código, nome, logo), progresso, nº de cartas na coleção e uma imagem
de capa. O catálogo é admin-only (ADR-022), então a leitura direta via
RLS não basta.

Contrato:
  get_my_collections(p_include_archived boolean default false,
                     p_limit integer default 48, p_offset integer default 0)
  Uma linha por coleção do usuário, ativas antes de arquivadas, mais
  recentes primeiro. total_count = total antes da paginação.
  Progresso: reutiliza public.collection_completion_summary (5070/5083/
  5100) por linha da página — mesma semântica canônica, sem reimplementar.
  Coleção livre (OPEN_CURATION) → progresso nulo (C-20).
  Capa: arte CARD_FRONT da carta alocada mais recentemente (idioma do
  exemplar, depois pt-BR, depois en); nula se a coleção está vazia
  (a interface usa a capa Binder MMKYU + logo do Set).

Segurança: SECURITY DEFINER, STABLE, search_path '', dono por
auth.uid(), EXECUTE só authenticated. Nada de outro usuário aparece.
Performance: entrada por ix_collection_owner_lifecycle; agregados só
para as linhas da página (≤ 100).

Erros: 28000 not_authenticated; 22023 INVALID_PAGE.
Como validar: Query 5830.
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
    select c.id, c.name, c.mode, c.completion_policy, c.lifecycle_status,
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
  'Minhas coleções (Query 5168): Biblioteca do usuário da sessão — Set de referência, progresso canônico (5070/5083/5100), nº de cartas e capa. Paginada (≤ 100). Só coleções próprias.';

revoke all on function public.get_my_collections(boolean, integer, integer) from public;
revoke all on function public.get_my_collections(boolean, integer, integer) from anon;
grant execute on function public.get_my_collections(boolean, integer, integer) to authenticated;

commit;
