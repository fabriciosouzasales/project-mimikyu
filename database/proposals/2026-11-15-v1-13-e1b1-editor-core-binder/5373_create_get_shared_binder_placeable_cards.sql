/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5373 - get_shared_binder_placeable_cards() — exemplares que o EDITOR
              pode colocar no fichário (V1-13 · E1-B1)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA. Preparada em
              `V1-13 / E1-B1 | EDITOR AUTHORIZATION AND CORE BINDER OPERATIONS-01`
              (2026-11-15). Execução só com prova dinâmica sob protocolo
              controlado (C-244) e autorização expressa e específica.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-15
Contrato....: C-235 + DR-1 (só exemplares alocados pelo titular à coleção E
              guardados no local físico do próprio fichário), C-243 (nenhum
              dado patrimonial a mais), C-157–C-161.
Depende de..: E1-A (5366).

Assinatura..: get_shared_binder_placeable_cards(p_collection_id uuid,
                                               p_limit integer default 96,
                                               p_offset integer default 0)
Regras:
- Só EDITOR ACTIVE da coleção X (o titular usa get_my_collection_binder_unplaced,
  5252). VIEWER, convite pendente/recusado, ex-participante, estranho, sem
  sessão ou X sem fichário → ZERO linhas, indistinguível de lista vazia
  (mesma regra de não enumeração das leituras 5313/5320).
- Coleção X ou proprietária do fichário arquivadas → zero linhas (não há escrita
  possível).
- Lista só os exemplares que cumprem as TRÊS condições, nesta leitura:
    (1) alocados a X (collection_allocation.collection_id = X);
    (2) guardados no local físico do fichário (physical_card.storage_container_id
        = collection_layout.storage_container_id);
    (3) ainda fora de qualquer bolso (sem collection_layout_slot_assignment).
  A escrita (5374) revalida tudo no momento da colocação: esta lista é só
  apresentação.
- Colunas: physical_card_id (necessário para a escrita; identificador opaco),
  e os mesmos campos de exibição da leitura compartilhada 5315 (carta, número,
  Set, acabamento, idioma, imagem), mais total_count para paginação.
  NUNCA: nome ou id de local, outros exemplares do acervo, contagens fora da
  lista, condição (C-233), proveniência, valores, notas, Favoritos, Lista de
  desejos, ids do titular.
- Paginação: p_limit 1..96 (padrão 96, o teto da 5252), p_offset 0..100000.
  Ordem total determinística: Set, número de coleção, idioma, exemplar.
- STABLE, SECURITY DEFINER, search_path vazio; EXECUTE só authenticated.
Canal.......: psql. Idempotência: função já presente → 'JÁ APLICADA ou
              DIVERGENTE'. Reversão: R5373 em ROLLBACK_E1B1.sql.
Como validar: harness 5889, seção 2.
================================================================
*/

begin;

set local lock_timeout = '5s';

do $pre$
begin
  if (select pg_catalog.pg_get_constraintdef(k.oid) from pg_catalog.pg_constraint k
       where k.conrelid = 'public.collection_membership'::regclass
         and k.conname = 'chk_collection_membership_role')
     is distinct from 'CHECK ((role = ANY (ARRAY[''VIEWER''::text, ''EDITOR''::text])))' then
    raise exception 'PRECHECK 5373: E1-A (5366) não aplicada';
  end if;
  if exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname = 'get_shared_binder_placeable_cards') then
    raise exception 'PRECHECK 5373: função já existe — JÁ APLICADA ou ESTADO DIVERGENTE';
  end if;
end;
$pre$;

create function public.get_shared_binder_placeable_cards(
  p_collection_id uuid,
  p_limit         integer default 96,
  p_offset        integer default 0
)
returns table (
  physical_card_id uuid,
  card_name        text,
  collector_number text,
  collector_total  integer,
  card_set_code    text,
  variant_label    text,
  language_code    text,
  image_path       text,
  total_count      integer
)
language plpgsql
stable
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_uid       uuid := (select auth.uid());
  v_owner     uuid;
  v_layout    uuid;
  v_anchor    uuid;
  v_container uuid;
begin
  if p_limit is null or p_limit < 1 or p_limit > 96 or p_offset is null or p_offset < 0 or p_offset > 100000 then
    raise exception 'INVALID_PAGE' using errcode = '22023';
  end if;
  if v_uid is null or p_collection_id is null then
    return;
  end if;

  -- EDITOR ACTIVE de X, coleção ativa, de outro titular.
  select c.owner_user_id into v_owner
  from public.collection c
  join public.collection_membership m
    on m.collection_id = c.id and m.user_id = v_uid and m.status = 'ACTIVE' and m.role = 'EDITOR'
  where c.id = p_collection_id
    and c.owner_user_id <> v_uid
    and c.lifecycle_status = 'ACTIVE';
  if v_owner is null then
    return;
  end if;

  select l.id, l.collection_id, l.storage_container_id into v_layout, v_anchor, v_container
  from public.collection_layout l where l.collection_id = p_collection_id;
  if v_layout is null then
    select l.id, l.collection_id, l.storage_container_id into v_layout, v_anchor, v_container
    from public.collection_layout_guest g
    join public.collection_layout l on l.id = g.layout_id
    where g.collection_id = p_collection_id;
  end if;
  if v_layout is null or v_container is null then
    return;
  end if;
  if not exists (select 1 from public.collection c
                 where c.id = v_anchor and c.owner_user_id = v_owner and c.lifecycle_status = 'ACTIVE') then
    return;
  end if;

  return query
  with el as (
    select pc.id as pcid, pc.card_variant_id, pc.language_id
    from public.collection_allocation ca
    join public.physical_card pc on pc.id = ca.physical_card_id
    join public.inventory i      on i.id = pc.inventory_id
    where ca.collection_id = p_collection_id
      and i.owner_user_id = v_owner
      and pc.storage_container_id = v_container
      and not exists (select 1 from public.collection_layout_slot_assignment a where a.physical_card_id = pc.id)
  ),
  tot as (select count(*)::integer as n from el)
  select
    el.pcid,
    c.name::text,
    c.collector_number::text,
    c.collector_total,
    cs.code::text,
    nullif(concat_ws(' · ', vt.name, pp.name, ecx.name), '')::text,
    l.code::text,
    img.storage_path::text,
    tot.n
  from el
  cross join tot
  join public.card_variant cv                       on cv.id = el.card_variant_id
  join public.card c                                on c.id = cv.card_id
  join public.card_set cs                           on cs.id = c.card_set_id
  left join public.card_variant_type vt             on vt.id = cv.variant_type_id
  left join public.card_printing_profile pp         on pp.id = cv.printing_profile_id
  left join public.card_edition_context_profile ecx on ecx.id = cv.edition_context_profile_id
  left join public.language l                       on l.id = el.language_id
  left join lateral (
    select ast.storage_path
    from public.card_asset ast
    join public.card_asset_type cat on cat.id = ast.asset_type_id and cat.code = 'CARD_FRONT'
    join public.language al         on al.id = ast.language_id
    where ast.card_id = c.id
      and ast.is_primary
      and ast.is_active
      and ast.storage_path is not null
    order by (ast.language_id = el.language_id) desc nulls last,
             (al.code = 'pt-BR') desc,
             (al.code = 'en') desc,
             al.language_order asc
    limit 1
  ) img on true
  order by cs.code, c.collector_order, c.collector_number, l.code, el.pcid
  limit p_limit offset p_offset;
end;
$fn$;

comment on function public.get_shared_binder_placeable_cards(uuid, integer, integer) is
  'V1-13 E1-B1 (5373): exemplares que o EDITOR pode colocar no fichário — alocados à coleção, guardados no local do fichário e fora de bolso (C-235/DR-1). Sem local, condição, valores ou acervo. Não EDITOR → zero linhas.';

revoke all on function public.get_shared_binder_placeable_cards(uuid, integer, integer) from public, anon;
grant execute on function public.get_shared_binder_placeable_cards(uuid, integer, integer) to authenticated;

do $post$
declare
  f oid := to_regprocedure('public.get_shared_binder_placeable_cards(uuid, integer, integer)');
begin
  if f is null
     or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
     or (select p.provolatile from pg_catalog.pg_proc p where p.oid = f) is distinct from 's'
     or (select p.proconfig from pg_catalog.pg_proc p where p.oid = f) is distinct from array['search_path=""']
     or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not true
     or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false then
    raise exception 'POSTCHECK 5373: leitura fora do estado esperado';
  end if;
  if exists (select 1 from pg_catalog.pg_proc q, unnest(q.proargnames, q.proargmodes) a(name, mode)
             where q.oid = f and a.mode = 't'
               and a.name ~ '(storage|location|local|condition|price|value|paid|acqui|note|favorite|wish|owner|collection_id|allocation)') then
    raise exception 'POSTCHECK 5373: coluna privada na saída';
  end if;
end;
$post$;

commit;
