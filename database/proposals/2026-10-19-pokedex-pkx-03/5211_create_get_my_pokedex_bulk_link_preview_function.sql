/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5211 - get_my_pokedex_bulk_link_preview(): prévia da
              inclusão em lote — um exemplar livre sugerido para cada
              Pokémon que falta
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-19 (autorização de
              Fabrício, PKX-03 LIVE) — ledger 20261019033827; 5846 v1.0
              27/27 PASS (GATE PASS, 99.1 resíduo zero).
              CANÔNICA em database/schema/. Corpo = LIVE (md5 de prosrc 2bdd2a7513f91f0055c4609ba3113aa4).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-19 (POKEDEX-PKX-03-IMPLEMENTATION-01)

Contrato:
  get_my_pokedex_bulk_link_preview(p_collection_id uuid,
                                   p_generation_code text default null)
  → pokedex_position_id, position_number, species_name,
    species_artwork_path, eligible_count, physical_card_id, card_name,
    collector_number, card_set_code, variant_label, language_code,
    language_name, storage_name, image_path, missing_total, total_count

  - Uma linha por posição do escopo vigente (filtro opcional por
    geração) que ainda NÃO está conquistada e para a qual o acervo tem
    ao menos um exemplar LIVRE (em nenhuma coleção) de carta Pokémon
    com a espécie principal da posição — a mesma regra de SPECIES_MATCH
    da 6119/6122. Nunca sugere vínculo excepcional.
  - physical_card_id é a sugestão determinística (variante padrão,
    idioma, mais antigo); eligible_count, quantos exemplares livres
    servem. Um exemplar nunca aparece em duas linhas (cada carta tem uma
    única espécie principal → uma única posição).
  - Confirmação: o cliente envia os ids escolhidos à 5046 (até 500, tudo
    ou nada); a 6119 cria os vínculos SPECIES_MATCH na mesma transação.
    Nenhum contrato novo de escrita.
  - missing_total: posições do filtro ainda não conquistadas (com ou sem
    exemplar), para a interface dizer o que fica de fora. total_count:
    linhas devolvidas antes do teto.
  - Teto: 500 linhas (o limite da 5046), em ordem nacional.
  - Coleção inexistente, alheia, arquivada ou que não é Pokédex → zero
    linhas.

Erros: 28000.
Segurança: SECURITY DEFINER, STABLE, search_path '', dono por auth.uid()
antes de qualquer tabela de acervo/catálogo; EXECUTE só authenticated.
Desempenho: escopo ≤ 1.025 posições; acervo livre do usuário agregado
uma vez por espécie; arte e carta só nas linhas devolvidas.
Como validar: 5846 v1.0.
Recuperação: drop function if exists public.get_my_pokedex_bulk_link_preview(uuid, text);
================================================================
*/

begin;

create or replace function public.get_my_pokedex_bulk_link_preview(
  p_collection_id   uuid,
  p_generation_code text default null
)
returns table (
  pokedex_position_id  uuid,
  position_number      integer,
  species_name         text,
  species_artwork_path text,
  eligible_count       integer,
  physical_card_id     uuid,
  card_name            text,
  collector_number     text,
  card_set_code        text,
  variant_label        text,
  language_code        text,
  language_name        text,
  storage_name         text,
  image_path           text,
  missing_total        bigint,
  total_count          bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user      uuid := auth.uid();
  v_ref       uuid;
  v_dex       uuid;
  v_kind      text;
  v_inventory uuid;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
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

  select i.id into v_inventory
  from public.inventory i
  where i.owner_user_id = v_user;

  if v_inventory is null then
    return;
  end if;

  return query
  with scope as (
    select pp.id as pos_id, pp.position_number as pnum, s.id as sp_id, s.canonical_name::text as sp_name
    from public.pokedex_position pp
    join public.pokemon_species s    on s.id = pp.species_id
    join public.pokemon_generation g on g.id = s.generation_id
    where pp.pokedex_id = v_dex
      and (v_kind = 'FULL_REFERENCE'
           or exists (select 1 from public.collection_pokedex_scope_generation sg
                      where sg.collection_reference_id = v_ref and sg.generation_id = s.generation_id))
      and (p_generation_code is null or g.code = p_generation_code)
  ),
  missing as (
    select sc.*
    from scope sc
    where not exists (
      select 1
      from public.collection_pokedex_position_assignment a
      join public.collection_allocation ca on ca.id = a.collection_allocation_id
      where a.pokedex_position_id = sc.pos_id
        and ca.collection_id = p_collection_id)
  ),
  free_copies as (
    select pc.id, pc.language_id, pc.storage_container_id, pc.created_at,
           cv.card_id, cv.is_default, cps.pokemon_species_id as sp_id,
           nullif(concat_ws(' · ', vt.name, prp.name, ec.name), '')::text as label,
           l.code::text as lcode, l.name::text as lname,
           row_number() over (partition by cps.pokemon_species_id
                              order by cv.is_default desc, l.language_order asc nulls last, pc.created_at asc, pc.id asc) as rn,
           count(*) over (partition by cps.pokemon_species_id) as n
    from public.physical_card pc
    join public.card_variant cv          on cv.id = pc.card_variant_id
    join public.card c                   on c.id = cv.card_id
    join public.card_category cc         on cc.id = c.category_id and cc.code = 'POKEMON'
    join public.card_primary_species cps on cps.card_id = c.id
    join public.language l               on l.id = pc.language_id
    left join public.card_variant_type vt            on vt.id = cv.variant_type_id
    left join public.card_printing_profile prp       on prp.id = cv.printing_profile_id
    left join public.card_edition_context_profile ec on ec.id = cv.edition_context_profile_id
    where pc.inventory_id = v_inventory
      and cps.pokemon_species_id in (select m.sp_id from missing m)
      and not exists (select 1 from public.collection_allocation ca where ca.physical_card_id = pc.id)
  ),
  rows_ as (
    select m.pos_id, m.pnum, m.sp_name, f.*,
           (select count(*) from missing) as miss,
           count(*) over () as total
    from missing m
    join free_copies f on f.sp_id = m.sp_id and f.rn = 1
    order by m.pnum, m.pos_id
    limit 500
  )
  select r.pos_id, r.pnum, r.sp_name,
         art.path,
         r.n::integer,
         r.id,
         c.name::text, c.collector_number::text, cs.code::text,
         r.label, r.lcode, r.lname,
         st.name::text,
         img.storage_path::text,
         r.miss, r.total
  from rows_ r
  join public.card c      on c.id = r.card_id
  join public.card_set cs on cs.id = c.card_set_id
  left join public.storage_container st on st.id = r.storage_container_id
                                       and st.inventory_id = v_inventory
  left join lateral (
    select w.display_storage_path::text as path
    from public.pokemon_species_artwork w
    where w.pokemon_species_id = r.sp_id
      and w.status = 'IMPORTED'
      and w.display_storage_path is not null
    order by w.created_at, w.id
    limit 1
  ) art on true
  left join lateral (
    select ast.storage_path
    from public.card_asset ast
    join public.card_asset_type cat on cat.id = ast.asset_type_id and cat.code = 'CARD_FRONT'
    join public.language al         on al.id = ast.language_id
    where ast.card_id = r.card_id
      and ast.is_primary
      and ast.is_active
      and ast.storage_path is not null
    order by (ast.language_id = r.language_id) desc nulls last,
             (al.code = 'pt-BR') desc,
             (al.code = 'en') desc,
             al.language_order asc
    limit 1
  ) img on true
  order by r.pnum, r.pos_id;
end;
$$;

comment on function public.get_my_pokedex_bulk_link_preview(uuid, text) is
  'Pokédex (Query 5211): prévia da inclusão em lote — para cada posição ainda não conquistada do escopo (filtro opcional por geração) com exemplar LIVRE da mesma espécie principal, um exemplar sugerido (até 500). A confirmação usa a 5046 + 6119 (SPECIES_MATCH); nunca sugere vínculo excepcional. Só leitura.';

revoke all on function public.get_my_pokedex_bulk_link_preview(uuid, text) from public, anon;
grant execute on function public.get_my_pokedex_bulk_link_preview(uuid, text) to authenticated;

commit;
