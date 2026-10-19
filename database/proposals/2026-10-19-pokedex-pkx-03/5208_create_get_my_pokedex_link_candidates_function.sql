/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5208 - get_my_pokedex_link_candidates(): exemplares do
              acervo que podem ser vinculados a uma posição da Pokédex
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-19 (autorização de
              Fabrício, PKX-03 LIVE) — ledger 20261019033709; 5846 v1.0
              27/27 PASS (GATE PASS, 99.1 resíduo zero).
              CANÔNICA em database/schema/. Corpo = LIVE (md5 de prosrc 463f739213725b8ae8c02c92347416d6).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-19 (POKEDEX-PKX-03-IMPLEMENTATION-01)

Contrato:
  get_my_pokedex_link_candidates(p_collection_id uuid,
                                 p_pokedex_position_id uuid,
                                 p_scope text default 'SPECIES',   -- SPECIES | ACERVO
                                 p_query text default null,        -- só ACERVO; ≤ 100 caracteres
                                 p_limit integer default 48,       -- 1..100
                                 p_offset integer default 0)       -- 0..10000
  → physical_card_id, card_name, collector_number, card_set_code,
    card_set_name, variant_label, is_default_variant, language_code,
    language_name, storage_name, image_path, added_at,
    in_this_collection, card_species_name, card_species_number,
    species_match, total_count

  - Elegível = exemplar do próprio acervo que está LIVRE (em nenhuma
    coleção) ou NESTA coleção sem vínculo de posição (só acontece depois
    de "retirar o vínculo", 6124). Exemplar em outra coleção nunca é
    candidato (alocação única, 5046).
  - SPECIES: só exemplares cuja carta é Pokémon com espécie principal
    (card_primary_species) igual à da posição — a mesma regra de
    SPECIES_MATCH da 6119/6122. É a lista do vínculo normal.
  - ACERVO: só exemplares que NÃO correspondem à espécie da posição
    (outra espécie, carta sem espécie resolvida, Treinador/Energia), com
    busca opcional por nome da carta, código do Set ou número. É a lista
    do vínculo excepcional: a interface mostra card_species_* para o aviso
    de divergência; nenhuma associação automática por nome ou ilustração.
  - Atributos físicos preservados e visíveis: idioma, acabamento/edição
    (variant_label), local (storage_name). Nada é alterado aqui.
  - Posição de outra Pokédex ou fora do escopo vigente, coleção
    inexistente, alheia, arquivada ou que não é Pokédex → zero linhas.
  - Ordem: SPECIES — variante padrão, idioma, mais antigo; ACERVO — nome,
    Set, número, idioma, mais antigo. total_count antes da paginação.

Erros: 28000; 22023 INVALID_SCOPE / INVALID_PAGE / INVALID_POSITION.
Segurança: SECURITY DEFINER, STABLE, search_path '', dono por auth.uid()
antes de qualquer tabela de acervo/catálogo; EXECUTE só authenticated.
Desempenho: acervo do usuário filtrado por inventory_id; arte só nas
linhas da página; busca com ILIKE escapado (sem curingas do usuário).
Como validar: 5846 v1.0.
Recuperação: drop function if exists public.get_my_pokedex_link_candidates(uuid, uuid, text, text, integer, integer);
================================================================
*/

begin;

create or replace function public.get_my_pokedex_link_candidates(
  p_collection_id       uuid,
  p_pokedex_position_id uuid,
  p_scope               text    default 'SPECIES',
  p_query               text    default null,
  p_limit               integer default 48,
  p_offset              integer default 0
)
returns table (
  physical_card_id    uuid,
  card_name           text,
  collector_number    text,
  card_set_code       text,
  card_set_name       text,
  variant_label       text,
  is_default_variant  boolean,
  language_code       text,
  language_name       text,
  storage_name        text,
  image_path          text,
  added_at            timestamptz,
  in_this_collection  boolean,
  card_species_name   text,
  card_species_number integer,
  species_match       boolean,
  total_count         bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user      uuid := auth.uid();
  v_scope     text := upper(btrim(coalesce(p_scope, '')));
  v_query     text := nullif(btrim(coalesce(p_query, '')), '');
  v_pattern   text;
  v_ref       uuid;
  v_dex       uuid;
  v_kind      text;
  v_species   uuid;
  v_inventory uuid;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if v_scope not in ('SPECIES', 'ACERVO') then
    raise exception 'INVALID_SCOPE' using errcode = '22023';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 100
     or p_offset is null or p_offset < 0 or p_offset > 10000
     or (v_query is not null and char_length(v_query) > 100) then
    raise exception 'INVALID_PAGE' using errcode = '22023';
  end if;

  if p_pokedex_position_id is null then
    raise exception 'INVALID_POSITION' using errcode = '22023';
  end if;

  -- Fronteira de autorização antes de qualquer tabela de acervo/catálogo.
  select cr.id, cpr.pokedex_id, cpr.scope_kind into v_ref, v_dex, v_kind
  from public.collection c
  join public.collection_reference cr
    on cr.collection_id = c.id and cr.reference_kind = 'POKEDEX'
  join public.collection_pokedex_reference cpr
    on cpr.collection_reference_id = cr.id
  where c.id = p_collection_id
    and c.owner_user_id = v_user
    and c.lifecycle_status = 'ACTIVE'
    and c.mode = 'REFERENCE_BASED'
    and c.completion_policy = 'REFERENCE_POSITION';

  if v_ref is null then
    return;
  end if;

  -- A posição precisa ser desta Pokédex e estar no escopo vigente.
  select pp.species_id into v_species
  from public.pokedex_position pp
  join public.pokemon_species s on s.id = pp.species_id
  where pp.id = p_pokedex_position_id
    and pp.pokedex_id = v_dex
    and (v_kind = 'FULL_REFERENCE'
         or exists (select 1 from public.collection_pokedex_scope_generation sg
                    where sg.collection_reference_id = v_ref and sg.generation_id = s.generation_id));

  if v_species is null then
    return;
  end if;

  select i.id into v_inventory
  from public.inventory i
  where i.owner_user_id = v_user;

  if v_inventory is null then
    return;
  end if;

  if v_query is not null then
    v_pattern := '%' || replace(replace(replace(v_query, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  end if;

  return query
  with pool as (
    select pc.id, pc.language_id, pc.storage_container_id, pc.created_at,
           cv.card_id, cv.is_default,
           (ca.id is not null) as in_here,
           (cc.code = 'POKEMON' and cps.pokemon_species_id = v_species) as is_match,
           cps.pokemon_species_id as card_sp,
           nullif(concat_ws(' · ', vt.name, prp.name, ec.name), '')::text as label
    from public.physical_card pc
    join public.card_variant cv  on cv.id = pc.card_variant_id
    join public.card c           on c.id = cv.card_id
    join public.card_category cc on cc.id = c.category_id
    left join public.card_primary_species cps on cps.card_id = c.id
    left join public.collection_allocation ca on ca.physical_card_id = pc.id
    left join public.collection_pokedex_position_assignment a on a.collection_allocation_id = ca.id
    left join public.card_variant_type vt            on vt.id = cv.variant_type_id
    left join public.card_printing_profile prp       on prp.id = cv.printing_profile_id
    left join public.card_edition_context_profile ec on ec.id = cv.edition_context_profile_id
    where pc.inventory_id = v_inventory
      and (ca.id is null or (ca.collection_id = p_collection_id and a.collection_allocation_id is null))
  ),
  picked as (
    select p.*, c.name::text as cname, c.collector_number::text as cnum, c.collector_order as corder,
           cs.code::text as scode, cs.name::text as sname,
           l.code::text as lcode, l.name::text as lname, l.language_order as lorder,
           count(*) over () as total
    from pool p
    join public.card c      on c.id = p.card_id
    join public.card_set cs on cs.id = c.card_set_id
    join public.language l  on l.id = p.language_id
    where (v_scope = 'SPECIES' and coalesce(p.is_match, false))
       or (v_scope = 'ACERVO' and not coalesce(p.is_match, false)
           and (v_pattern is null
                or c.name ilike v_pattern escape '\'
                or cs.code ilike v_pattern escape '\'
                or c.collector_number ilike v_pattern escape '\'))
    order by
      case when v_scope = 'SPECIES' then (not p.is_default) end asc nulls last,
      case when v_scope = 'ACERVO' then c.name end asc nulls last,
      case when v_scope = 'ACERVO' then cs.code end asc nulls last,
      case when v_scope = 'ACERVO' then c.collector_order end asc nulls last,
      l.language_order asc nulls last,
      p.created_at asc,
      p.id asc
    limit p_limit offset p_offset
  )
  select k.id, k.cname, k.cnum, k.scode, k.sname, k.label, k.is_default,
         k.lcode, k.lname,
         sc.name::text,
         img.storage_path::text,
         k.created_at,
         k.in_here,
         sp.canonical_name::text,
         sp.national_dex_number,
         coalesce(k.is_match, false),
         k.total
  from picked k
  left join public.storage_container sc on sc.id = k.storage_container_id
                                       and sc.inventory_id = v_inventory
  left join public.pokemon_species sp   on sp.id = k.card_sp
  left join lateral (
    select ast.storage_path
    from public.card_asset ast
    join public.card_asset_type cat on cat.id = ast.asset_type_id and cat.code = 'CARD_FRONT'
    join public.language al         on al.id = ast.language_id
    where ast.card_id = k.card_id
      and ast.is_primary
      and ast.is_active
      and ast.storage_path is not null
    order by (ast.language_id = k.language_id) desc nulls last,
             (al.code = 'pt-BR') desc,
             (al.code = 'en') desc,
             al.language_order asc
    limit 1
  ) img on true
  order by
    case when v_scope = 'SPECIES' then (not k.is_default) end asc nulls last,
    case when v_scope = 'ACERVO' then k.cname end asc nulls last,
    case when v_scope = 'ACERVO' then k.scode end asc nulls last,
    case when v_scope = 'ACERVO' then k.corder end asc nulls last,
    k.lorder asc nulls last,
    k.created_at asc,
    k.id asc;
end;
$$;

comment on function public.get_my_pokedex_link_candidates(uuid, uuid, text, text, integer, integer) is
  'Pokédex (Query 5208): exemplares do próprio acervo vinculáveis a uma posição — livres ou nesta coleção sem vínculo. SPECIES = espécie principal igual à da posição (vínculo normal); ACERVO = demais exemplares, com busca, para o vínculo excepcional (devolve a espécie da carta para o aviso). Só leitura.';

revoke all on function public.get_my_pokedex_link_candidates(uuid, uuid, text, text, integer, integer) from public, anon;
grant execute on function public.get_my_pokedex_link_candidates(uuid, uuid, text, text, integer, integer) to authenticated;

commit;
