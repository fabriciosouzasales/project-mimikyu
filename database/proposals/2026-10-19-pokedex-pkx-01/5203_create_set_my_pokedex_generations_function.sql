/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5203 - set_my_pokedex_generations(): inclui/remove
              gerações do escopo de uma coleção Pokédex (Ajustes)
Versão......: 1.0
Status......: PROPOSTA — não executada no LIVE.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-19 (POKEDEX-PKX-01-IMPLEMENTATION-01)

Contrato:
  set_my_pokedex_generations(p_collection_id uuid, p_generation_codes text[])
  → collection_id, generation_codes, total_positions,
    satisfied_positions, changed

  - Substitui o escopo pela lista EXPLÍCITA recebida (GENERATION_FILTERED).
    Nunca grava FULL_REFERENCE. Uma coleção legada em FULL_REFERENCE (hoje
    não existe nenhuma) passa a lista explícita na primeira gravação.
  - Mesmas regras de geração da 5202: ativa, catalogada na Pokédex
    Nacional, 1..64 códigos, repetidos ignorados.
  - Idempotente: mesma lista já gravada → nada é escrito (changed = false).
  - Não exclui nem movimenta cartas: alocações e vínculos com posições
    ficam intactos (escrita delegada à 5099, que só troca as linhas de
    collection_pokedex_scope_generation). O progresso devolvido
    (collection_completion_summary) já é o do novo escopo; vínculos de
    gerações removidas voltam a contar se a geração voltar.
  - Coleção inexistente, de outro usuário ou que não é Pokédex → P0002
    COLLECTION_NOT_FOUND (mesma resposta). Arquivada → 55000
    COLLECTION_ARCHIVED.

Erros: 28000; 22023 INVALID_REQUEST / GENERATION_NOT_AVAILABLE;
P0002 COLLECTION_NOT_FOUND; 55000 COLLECTION_ARCHIVED.
Segurança: SECURITY DEFINER, VOLATILE, search_path '', trava a linha da
coleção (FOR UPDATE), EXECUTE só authenticated. Depende da 5099 ser
executável pelo dono das funções — continua após a 5205.
Como validar: 5844 v1.0.
Recuperação: drop function if exists public.set_my_pokedex_generations(uuid, text[]);
================================================================
*/

begin;

create or replace function public.set_my_pokedex_generations(
  p_collection_id    uuid,
  p_generation_codes text[]
)
returns table (
  collection_id       uuid,
  generation_codes    text[],
  total_positions     bigint,
  satisfied_positions bigint,
  changed             boolean
)
language plpgsql
security definer
volatile
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user      uuid := auth.uid();
  v_status    text;
  v_ref       uuid;
  v_dex       uuid;
  v_scope     text;
  v_codes     text[];
  v_gen_ids   uuid[];
  v_out_codes text[];
  v_current   uuid[];
  v_target    uuid[];
  v_changed   boolean := false;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if p_collection_id is null
     or p_generation_codes is null
     or coalesce(cardinality(p_generation_codes), 0) = 0
     or cardinality(p_generation_codes) > 64
     or exists (select 1 from unnest(p_generation_codes) x where x is null or btrim(x) = '') then
    raise exception 'INVALID_REQUEST' using errcode = '22023';
  end if;

  -- Fronteira de autorização + trava da coleção.
  select c.lifecycle_status, cr.id, cpr.pokedex_id, cpr.scope_kind
    into v_status, v_ref, v_dex, v_scope
  from public.collection c
  join public.collection_reference cr
    on cr.collection_id = c.id and cr.reference_kind = 'POKEDEX'
  join public.collection_pokedex_reference cpr
    on cpr.collection_reference_id = cr.id
  where c.id = p_collection_id
    and c.owner_user_id = v_user
    and c.mode = 'REFERENCE_BASED'
    and c.completion_policy = 'REFERENCE_POSITION'
  for update of c;

  if v_ref is null then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  if v_status <> 'ACTIVE' then
    raise exception 'COLLECTION_ARCHIVED' using errcode = '55000';
  end if;

  select array_agg(distinct btrim(x)) into v_codes
  from unnest(p_generation_codes) x;

  select array_agg(g.id order by g.ordinal_number), array_agg(g.code::text order by g.ordinal_number)
    into v_gen_ids, v_out_codes
  from public.pokemon_generation g
  where g.code = any(v_codes)
    and g.is_active
    and exists (
      select 1
      from public.pokemon_species s
      join public.pokedex_position pp on pp.species_id = s.id and pp.pokedex_id = v_dex
      where s.generation_id = g.id
    );

  if coalesce(cardinality(v_gen_ids), 0) <> cardinality(v_codes) then
    raise exception 'GENERATION_NOT_AVAILABLE' using errcode = '22023';
  end if;

  select array_agg(sg.generation_id order by sg.generation_id) into v_current
  from public.collection_pokedex_scope_generation sg
  where sg.collection_reference_id = v_ref;

  select array_agg(x order by x) into v_target from unnest(v_gen_ids) x;

  if v_scope <> 'GENERATION_FILTERED' or v_current is distinct from v_target then
    perform public.set_collection_pokedex_scope(p_collection_id, 'GENERATION_FILTERED', v_gen_ids);
    v_changed := true;
  end if;

  return query
  select p_collection_id, v_out_codes, s.total_positions, s.satisfied_positions, v_changed
  from public.collection_completion_summary(p_collection_id) s;
end;
$$;

comment on function public.set_my_pokedex_generations(uuid, text[]) is
  'Pokédex (Query 5203): substitui as gerações do escopo de uma coleção Pokédex ativa do usuário pela lista EXPLÍCITA recebida (nunca FULL_REFERENCE). Idempotente; não exclui nem movimenta cartas, alocações ou vínculos; devolve o progresso do novo escopo.';

revoke all on function public.set_my_pokedex_generations(uuid, text[]) from public, anon;
grant execute on function public.set_my_pokedex_generations(uuid, text[]) to authenticated;

commit;
