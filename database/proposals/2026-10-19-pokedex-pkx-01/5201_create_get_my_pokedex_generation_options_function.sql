/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5201 - get_my_pokedex_generation_options(): gerações
              catalogadas da Pokédex Nacional, para a criação e para os
              Ajustes de uma coleção Pokédex
Versão......: 1.0
Status......: PROPOSTA — não executada no LIVE.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-19 (POKEDEX-PKX-01-IMPLEMENTATION-01)

Contrato:
  get_my_pokedex_generation_options(p_collection_id uuid default null)
  → generation_code, generation_ordinal, generation_name, region_name,
    species_count, first_number, last_number, is_selected, satisfied_count

  - "Catalogada" = geração ativa com ≥ 1 posição na Pokédex Nacional
    (code = 'NATIONAL', ativa). Geração lançada e catalogada aparece
    aqui sem nenhuma mudança de contrato; geração sem posições não aparece.
  - species_count / first_number / last_number = posições da geração na
    Pokédex Nacional (mesma contagem que entra no escopo da coleção —
    5103 não filtra espécie ativa, este contrato também não).
  - Sem coleção (criação): is_selected e satisfied_count = NULL.
    O padrão "todas selecionadas" é aplicado pela interface marcando
    todas as linhas devolvidas.
  - Com coleção: is_selected = geração gravada no escopo da coleção;
    satisfied_count = posições daquela geração já conquistadas por
    vínculo (5103: vínculo de qualquer base conta; selecionada ou não).
  - Coleção inexistente, de outro usuário ou que não é Pokédex → zero
    linhas (mesma resposta; não revela existência).

Segurança: SECURITY DEFINER, STABLE, search_path '', dono por
auth.uid(); EXECUTE só authenticated. Erros: 28000 not_authenticated.
Desempenho: 9 gerações × 1.025 posições; agregação única.
Como validar: 5844 v1.0.
Recuperação: drop function if exists public.get_my_pokedex_generation_options(uuid);
================================================================
*/

begin;

create or replace function public.get_my_pokedex_generation_options(
  p_collection_id uuid default null
)
returns table (
  generation_code    text,
  generation_ordinal integer,
  generation_name    text,
  region_name        text,
  species_count      bigint,
  first_number       integer,
  last_number        integer,
  is_selected        boolean,
  satisfied_count    bigint
)
language plpgsql
security definer
stable
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user  uuid := auth.uid();
  v_dex   uuid;
  v_ref   uuid;
  v_scope text;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select d.id into v_dex
  from public.pokedex d
  where d.code = 'NATIONAL' and d.is_active;

  if v_dex is null then
    return;
  end if;

  if p_collection_id is not null then
    -- Fronteira de autorização antes de qualquer leitura de vínculos.
    select cr.id, cpr.scope_kind into v_ref, v_scope
    from public.collection c
    join public.collection_reference cr
      on cr.collection_id = c.id and cr.reference_kind = 'POKEDEX'
    join public.collection_pokedex_reference cpr
      on cpr.collection_reference_id = cr.id and cpr.pokedex_id = v_dex
    where c.id = p_collection_id
      and c.owner_user_id = v_user
      and c.mode = 'REFERENCE_BASED'
      and c.completion_policy = 'REFERENCE_POSITION';

    if v_ref is null then
      return;
    end if;
  end if;

  return query
  with gens as (
    select g.id, g.code::text as code, g.ordinal_number, g.canonical_name::text as gname,
           r.canonical_name::text as rname,
           count(pp.id) as cnt, min(pp.position_number) as fnum, max(pp.position_number) as lnum
    from public.pokemon_generation g
    join public.pokemon_species s on s.generation_id = g.id
    join public.pokedex_position pp on pp.species_id = s.id and pp.pokedex_id = v_dex
    left join public.pokemon_region r on r.id = g.main_region_id and r.is_active
    where g.is_active
    group by g.id, g.code, g.ordinal_number, g.canonical_name, r.canonical_name
  ),
  sat as (
    select distinct a.pokedex_position_id
    from public.collection_allocation ca
    join public.collection_pokedex_position_assignment a on a.collection_allocation_id = ca.id
    where v_ref is not null
      and ca.collection_id = p_collection_id
  ),
  sat_gen as (
    select s.generation_id, count(*) as n
    from sat
    join public.pokedex_position pp on pp.id = sat.pokedex_position_id and pp.pokedex_id = v_dex
    join public.pokemon_species s on s.id = pp.species_id
    group by s.generation_id
  )
  select g.code, g.ordinal_number, g.gname, g.rname, g.cnt, g.fnum, g.lnum,
         case
           when v_ref is null then null
           when v_scope = 'FULL_REFERENCE' then true
           else exists (select 1 from public.collection_pokedex_scope_generation x
                        where x.collection_reference_id = v_ref and x.generation_id = g.id)
         end,
         case when v_ref is null then null else coalesce(sg.n, 0) end
  from gens g
  left join sat_gen sg on sg.generation_id = g.id
  order by g.ordinal_number;
end;
$$;

comment on function public.get_my_pokedex_generation_options(uuid) is
  'Pokédex (Query 5201): gerações catalogadas (ativas, com ≥ 1 posição na Pokédex Nacional), com contagem e intervalo. Com p_collection_id do usuário: também se a geração está no escopo e quantas posições dela estão conquistadas. Coleção alheia/inexistente → zero linhas.';

revoke all on function public.get_my_pokedex_generation_options(uuid) from public, anon;
grant execute on function public.get_my_pokedex_generation_options(uuid) to authenticated;

commit;
