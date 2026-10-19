/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5209 - get_my_pokedex_position_copies(): exemplares
              vinculados a uma posição da Pokédex (gerenciar vínculos e
              representante)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-19 (autorização de
              Fabrício, PKX-03 LIVE) — ledger 20261019033730; 5846 v1.0
              27/27 PASS (GATE PASS, 99.1 resíduo zero).
              CANÔNICA em database/schema/. Corpo = LIVE (md5 de prosrc 280d0c96a93442e5a6d5f8e0f7e8e733).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-19 (POKEDEX-PKX-03-IMPLEMENTATION-01)

Contrato:
  get_my_pokedex_position_copies(p_collection_id uuid,
                                 p_pokedex_position_id uuid)
  → collection_allocation_id, physical_card_id, card_name,
    collector_number, card_set_code, card_set_name, variant_label,
    is_default_variant, language_code, language_name, storage_name,
    image_path, assignment_basis, assigned_at, is_representative,
    card_species_name, card_species_number, total_count

  - Lista os vínculos (6117) desta coleção para a posição, até 200, na
    ordem em que a grade escolhe o representante: o principal escolhido
    (6125) primeiro, depois o vínculo mais antigo.
  - assignment_basis: SPECIES_MATCH (espécie principal igual) ou
    USER_OVERRIDE (vínculo excepcional confirmado). card_species_* é a
    espécie principal da carta no catálogo — inalterada por qualquer
    vínculo — para a interface explicar a exceção.
  - collection_allocation_id é o argumento da 6125 (escolher
    representante); physical_card_id, o da 6124 (retirar o vínculo) e da
    5047 (tirar da coleção). Ids do próprio acervo, nunca de outro usuário.
  - Coleção inexistente, alheia ou que não é Pokédex → zero linhas.
    Coleção arquivada continua legível (como 5204).

Erros: 28000; 22023 INVALID_POSITION.
Segurança: SECURITY DEFINER, STABLE, search_path '', dono por auth.uid()
antes de qualquer tabela; EXECUTE só authenticated.
Desempenho: vínculos pelo índice de posição (6117) restritos à coleção;
arte por linha (≤ 200).
Como validar: 5846 v1.0.
Recuperação: drop function if exists public.get_my_pokedex_position_copies(uuid, uuid);
================================================================
*/

begin;

create or replace function public.get_my_pokedex_position_copies(
  p_collection_id       uuid,
  p_pokedex_position_id uuid
)
returns table (
  collection_allocation_id uuid,
  physical_card_id         uuid,
  card_name                text,
  collector_number         text,
  card_set_code            text,
  card_set_name            text,
  variant_label            text,
  is_default_variant       boolean,
  language_code            text,
  language_name            text,
  storage_name             text,
  image_path               text,
  assignment_basis         text,
  assigned_at              timestamptz,
  is_representative        boolean,
  card_species_name        text,
  card_species_number      integer,
  total_count              bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user      uuid := auth.uid();
  v_ok        boolean;
  v_inventory uuid;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if p_pokedex_position_id is null then
    raise exception 'INVALID_POSITION' using errcode = '22023';
  end if;

  -- Fronteira de autorização antes de qualquer outra tabela.
  select true into v_ok
  from public.collection c
  join public.collection_reference cr
    on cr.collection_id = c.id and cr.reference_kind = 'POKEDEX'
  where c.id = p_collection_id
    and c.owner_user_id = v_user
    and c.mode = 'REFERENCE_BASED'
    and c.completion_policy = 'REFERENCE_POSITION';

  if v_ok is null then
    return;
  end if;

  select i.id into v_inventory
  from public.inventory i
  where i.owner_user_id = v_user;

  return query
  with links as (
    select ca.id as alloc_id, ca.physical_card_id as pc_id,
           a.assignment_basis as basis, a.assigned_at as at,
           (pr.collection_allocation_id is not null) as is_rep,
           count(*) over () as total
    from public.collection_pokedex_position_assignment a
    join public.collection_allocation ca on ca.id = a.collection_allocation_id
    left join public.collection_pokedex_position_primary_representative pr
      on pr.collection_allocation_id = ca.id
     and pr.collection_id = p_collection_id
     and pr.pokedex_position_id = p_pokedex_position_id
    where a.pokedex_position_id = p_pokedex_position_id
      and ca.collection_id = p_collection_id
    order by (pr.collection_allocation_id is not null) desc, a.assigned_at asc, ca.id asc
    limit 200
  )
  select l.alloc_id, l.pc_id,
         c.name::text, c.collector_number::text, cs.code::text, cs.name::text,
         nullif(concat_ws(' · ', vt.name, prp.name, ec.name), '')::text,
         cv.is_default,
         lg.code::text, lg.name::text,
         sc.name::text,
         img.storage_path::text,
         l.basis, l.at, l.is_rep,
         sp.canonical_name::text, sp.national_dex_number,
         l.total
  from links l
  join public.physical_card pc on pc.id = l.pc_id
  join public.card_variant cv  on cv.id = pc.card_variant_id
  join public.card c           on c.id = cv.card_id
  join public.card_set cs      on cs.id = c.card_set_id
  join public.language lg      on lg.id = pc.language_id
  left join public.card_variant_type vt            on vt.id = cv.variant_type_id
  left join public.card_printing_profile prp       on prp.id = cv.printing_profile_id
  left join public.card_edition_context_profile ec on ec.id = cv.edition_context_profile_id
  left join public.storage_container sc            on sc.id = pc.storage_container_id
                                                  and sc.inventory_id = v_inventory
  left join public.card_primary_species cps        on cps.card_id = c.id
  left join public.pokemon_species sp              on sp.id = cps.pokemon_species_id
  left join lateral (
    select ast.storage_path
    from public.card_asset ast
    join public.card_asset_type cat on cat.id = ast.asset_type_id and cat.code = 'CARD_FRONT'
    join public.language al         on al.id = ast.language_id
    where ast.card_id = c.id
      and ast.is_primary
      and ast.is_active
      and ast.storage_path is not null
    order by (ast.language_id = pc.language_id) desc nulls last,
             (al.code = 'pt-BR') desc,
             (al.code = 'en') desc,
             al.language_order asc
    limit 1
  ) img on true
  order by l.is_rep desc, l.at asc, l.alloc_id asc;
end;
$$;

comment on function public.get_my_pokedex_position_copies(uuid, uuid) is
  'Pokédex (Query 5209): exemplares vinculados a uma posição de uma coleção Pokédex do usuário — base do vínculo (SPECIES_MATCH/USER_OVERRIDE), representante principal, atributos físicos e espécie principal da carta. Só leitura.';

revoke all on function public.get_my_pokedex_position_copies(uuid, uuid) from public, anon;
grant execute on function public.get_my_pokedex_position_copies(uuid, uuid) to authenticated;

commit;
