/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5204 - get_my_pokedex_positions(): grade paginada de uma
              coleção Pokédex — arte da espécie, carta representante e
              estado da espécie no acervo
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-19 (autorização de
              Fabrício, PKX-01 LIVE EXECUTION GATE-01) — ledger
              20261019012808; 5844 v1.0 37/37 PASS (GATE PASS, 99.1
              resíduo zero, conferido também fora do harness).
              CANÔNICA em database/schema/. Corpo = LIVE (md5 de prosrc 79d2cd331031b5c98c64f2c43ecb077f).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-19 (POKEDEX-PKX-01-IMPLEMENTATION-01)

Contrato:
  get_my_pokedex_positions(p_collection_id uuid,
                           p_filter text default 'ALL',        -- ALL | OWNED | MISSING
                           p_generation_code text default null,
                           p_limit integer default 120,        -- 1..500
                           p_offset integer default 0)         -- 0..100000
  → pokedex_position_id, position_number, species_id, species_name,
    generation_code, generation_ordinal, species_artwork_path,
    is_satisfied, copies_in_collection, copies_available,
    copies_elsewhere, acervo_state,
    representative_card_name, representative_collector_number,
    representative_set_code, representative_image_path, total_count

  - Universo: posições do escopo vigente (mesma regra da 5103: escopo por
    gerações, ou todas em FULL_REFERENCE legado), ordem pelo número
    nacional. Filtro opcional por geração (fora do escopo → zero linhas).
  - Conquista (mesma semântica da 5103/5102): posição com ≥ 1 vínculo de
    carta desta coleção (SPECIES_MATCH ou USER_OVERRIDE). Repetidas não
    multiplicam posição; copies_in_collection = cartas vinculadas a ela.
  - Estado no acervo (acervo_state), em ordem de precedência:
      OWNED      — conquistada por vínculo válido;
      AVAILABLE  — há carta LIVRE (sem coleção) no acervo cuja espécie
                   principal é a da posição (copies_available > 0);
      ELSEWHERE  — há carta da espécie no acervo, mas todas em OUTRAS
                   coleções (copies_elsewhere > 0);
      NOT_FOUND  — nenhuma carta da espécie no acervo.
    Espécie da carta = card_primary_species (cartas sem espécie resolvida
    não contam). Cartas da espécie nesta mesma coleção sem vínculo (só
    possível após remover o vínculo explicitamente, 6124) não entram em
    nenhuma das contagens.
  - Representante (só posições conquistadas): o representante principal
    escolhido (6125), senão o vínculo mais antigo (assigned_at, id).
    Devolve nome, número, código do Set e arte da carta — nunca ids de
    acervo.
  - species_artwork_path: arte oficial importada da espécie (mesma fonte
    da Pokédex editorial).
  - total_count: total do filtro antes da paginação. O progresso NÃO é
    calculado aqui: vem de collection_completion_summary (5102).
  - Coleção inexistente, de outro usuário ou que não é Pokédex → zero
    linhas. Coleção arquivada continua legível (como 5103).

Erros: 28000; 22023 INVALID_FILTER / INVALID_PAGE.
Segurança: SECURITY DEFINER, STABLE, search_path '', dono por auth.uid()
antes de qualquer tabela de catálogo/acervo; EXECUTE só authenticated.
Desempenho: escopo ≤ 1.025 posições; vínculos lidos uma vez por
collection_id; acervo agregado só para as espécies da página; arte e
representante só nas linhas da página.
Como validar: 5844 v1.0.
Recuperação: drop function if exists public.get_my_pokedex_positions(uuid, text, text, integer, integer);
================================================================
*/

begin;

create or replace function public.get_my_pokedex_positions(
  p_collection_id   uuid,
  p_filter          text    default 'ALL',
  p_generation_code text    default null,
  p_limit           integer default 120,
  p_offset          integer default 0
)
returns table (
  pokedex_position_id             uuid,
  position_number                 integer,
  species_id                      uuid,
  species_name                    text,
  generation_code                 text,
  generation_ordinal              integer,
  species_artwork_path            text,
  is_satisfied                    boolean,
  copies_in_collection            integer,
  copies_available                integer,
  copies_elsewhere                integer,
  acervo_state                    text,
  representative_card_name        text,
  representative_collector_number text,
  representative_set_code         text,
  representative_image_path       text,
  total_count                     bigint
)
language plpgsql
security definer
stable
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user      uuid := auth.uid();
  v_filter    text := upper(btrim(coalesce(p_filter, '')));
  v_ref       uuid;
  v_dex       uuid;
  v_scope     text;
  v_inventory uuid;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if v_filter not in ('ALL', 'OWNED', 'MISSING') then
    raise exception 'INVALID_FILTER' using errcode = '22023';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 500
     or p_offset is null or p_offset < 0 or p_offset > 100000 then
    raise exception 'INVALID_PAGE' using errcode = '22023';
  end if;

  -- Fronteira de autorização antes de qualquer tabela de catálogo/acervo.
  select cr.id, cpr.pokedex_id, cpr.scope_kind into v_ref, v_dex, v_scope
  from public.collection c
  join public.collection_reference cr
    on cr.collection_id = c.id and cr.reference_kind = 'POKEDEX'
  join public.collection_pokedex_reference cpr
    on cpr.collection_reference_id = cr.id
  where c.id = p_collection_id
    and c.owner_user_id = v_user
    and c.mode = 'REFERENCE_BASED'
    and c.completion_policy = 'REFERENCE_POSITION';

  if v_ref is null then
    return;
  end if;

  select i.id into v_inventory
  from public.inventory i
  where i.owner_user_id = v_user;

  return query
  with scope as (
    select pp.id as pos_id, pp.position_number as pnum, s.id as sp_id,
           s.canonical_name::text as sp_name, g.code::text as gcode, g.ordinal_number as gord
    from public.pokedex_position pp
    join public.pokemon_species s    on s.id = pp.species_id
    join public.pokemon_generation g on g.id = s.generation_id
    where pp.pokedex_id = v_dex
      and (v_scope = 'FULL_REFERENCE'
           or exists (select 1 from public.collection_pokedex_scope_generation sg
                      where sg.collection_reference_id = v_ref and sg.generation_id = s.generation_id))
      and (p_generation_code is null or g.code = p_generation_code)
  ),
  links as (
    select a.pokedex_position_id as pos_id, ca.id as alloc_id, ca.physical_card_id as pc_id,
           a.assigned_at, (pr.collection_allocation_id is not null) as is_rep
    from public.collection_allocation ca
    join public.collection_pokedex_position_assignment a on a.collection_allocation_id = ca.id
    left join public.collection_pokedex_position_primary_representative pr
      on pr.collection_allocation_id = ca.id and pr.collection_id = p_collection_id
    where ca.collection_id = p_collection_id
  ),
  assigned as (
    select l.pos_id, count(*)::integer as n
    from links l
    group by l.pos_id
  ),
  page as (
    select sc.pos_id, sc.pnum, sc.sp_id, sc.sp_name, sc.gcode, sc.gord,
           coalesce(asg.n, 0) as n_in, (asg.pos_id is not null) as sat,
           count(*) over () as total
    from scope sc
    left join assigned asg on asg.pos_id = sc.pos_id
    where v_filter = 'ALL'
       or (v_filter = 'OWNED'   and asg.pos_id is not null)
       or (v_filter = 'MISSING' and asg.pos_id is null)
    order by sc.pnum, sc.pos_id
    limit p_limit offset p_offset
  ),
  inv as (
    select cps.pokemon_species_id as sp_id,
           count(*) filter (where ca.id is null)::integer as free_n,
           count(*) filter (where ca.id is not null and ca.collection_id <> p_collection_id)::integer as other_n
    from public.physical_card pc
    join public.card_variant cv          on cv.id = pc.card_variant_id
    join public.card_primary_species cps on cps.card_id = cv.card_id
    left join public.collection_allocation ca on ca.physical_card_id = pc.id
    where pc.inventory_id = v_inventory
      and cps.pokemon_species_id in (select pg.sp_id from page pg)
    group by cps.pokemon_species_id
  ),
  rep as (
    select distinct on (l.pos_id) l.pos_id, l.pc_id
    from links l
    where l.pos_id in (select pg.pos_id from page pg where pg.sat)
    order by l.pos_id, l.is_rep desc, l.assigned_at, l.alloc_id
  )
  select p.pos_id, p.pnum, p.sp_id, p.sp_name, p.gcode, p.gord,
         art.path,
         p.sat, p.n_in,
         coalesce(iv.free_n, 0), coalesce(iv.other_n, 0),
         case
           when p.sat then 'OWNED'
           when coalesce(iv.free_n, 0) > 0 then 'AVAILABLE'
           when coalesce(iv.other_n, 0) > 0 then 'ELSEWHERE'
           else 'NOT_FOUND'
         end,
         rc.card_name, rc.number, rc.set_code, rc.image_path,
         p.total
  from page p
  left join inv iv on iv.sp_id = p.sp_id
  left join lateral (
    select w.display_storage_path::text as path
    from public.pokemon_species_artwork w
    where w.pokemon_species_id = p.sp_id
      and w.status = 'IMPORTED'
      and w.display_storage_path is not null
    order by w.created_at, w.id
    limit 1
  ) art on true
  left join lateral (
    select c.name::text as card_name, c.collector_number::text as number, cs.code::text as set_code,
           img.storage_path::text as image_path
    from rep r
    join public.physical_card pc on pc.id = r.pc_id
    join public.card_variant cv  on cv.id = pc.card_variant_id
    join public.card c           on c.id = cv.card_id
    join public.card_set cs      on cs.id = c.card_set_id
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
    where r.pos_id = p.pos_id
  ) rc on true
  order by p.pnum, p.pos_id;
end;
$$;

comment on function public.get_my_pokedex_positions(uuid, text, text, integer, integer) is
  'Pokédex (Query 5204): grade paginada (Todas/Tenho/Faltam, filtro por geração, ordem nacional) de uma coleção Pokédex do usuário — arte da espécie, carta representante e estado no acervo (OWNED/AVAILABLE/ELSEWHERE/NOT_FOUND). total_count antes da paginação; progresso vem de collection_completion_summary.';

revoke all on function public.get_my_pokedex_positions(uuid, text, text, integer, integer) from public, anon;
grant execute on function public.get_my_pokedex_positions(uuid, text, text, integer, integer) to authenticated;

commit;
