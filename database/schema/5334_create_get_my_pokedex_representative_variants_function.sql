/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5334 - get_my_pokedex_representative_variants(): variante
              do exemplar representante de cada posição da Pokédex
              (V1-09 Fase B — preço NM na coleção Pokédex)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-31 (autorização de
              Fabrício, PHASE B CONTROLLED LIVE EXECUTION-03) — ledger
              20261031182002; corpo md5 1b4d48b1… = arquivo; 5866 v1.1 12/12
              (4.2 sem dados: Pokédex do LIVE sem vínculos)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-31

Por que existe
  A grade da Pokédex (5204) mostra, em cada posição conquistada, a arte
  de UM exemplar físico — o representante principal (6120) ou, sem ele,
  o primeiro exemplar vinculado. A 5204 devolve nome, número, Set e
  imagem desse exemplar, mas não a variante. O preço NM é por variante
  (3983); sem esta leitura, a etiqueta poderia mostrar o preço de outro
  exemplar que não o da arte exibida.

Contrato
  get_my_pokedex_representative_variants(p_collection_id uuid,
                                          p_position_ids uuid[])
  Uma linha por posição pedida que tenha exemplar vinculado nesta coleção:
    pokedex_position_id — posição;
    card_variant_id     — variante do exemplar representante (preço);
    variant_label       — etiqueta de exibição (regra da 5159/5261);
    language_code       — idioma do exemplar representante;
    collector_number    — número da carta do representante;
    card_set_code       — Set da carta do representante.
  O representante é escolhido com a MESMA regra da 5204 (CTE rep):
  representante principal primeiro, depois assigned_at, depois o id da
  alocação. collector_number/card_set_code permitem ao frontend conferir
  que o preço corresponde à carta exibida pela 5204 (sem coincidência,
  nenhuma etiqueta). Coleção alheia ou inexistente → zero linhas.

Limites e erros
  p_position_ids: 1..500 ids (5204: até 151 por geração).
  28000 not_authenticated; 22023 INVALID_POSITION_IDS.

Desempenho
  collection_allocation pelo índice de collection_id, assignment pela PK
  (collection_allocation_id), representante pela PK/único; physical_card,
  card_variant, card, card_set por PK. Restrito às posições da página.

Segurança
  SECURITY DEFINER, STABLE, search_path '', objetos qualificados; dono
  verificado antes de ler exemplares; EXECUTE só authenticated. Somente
  leitura; 5204 não muda (espelhamento obrigatório da regra do
  representante: mudança em 5204/rep deve ser repetida aqui — o harness
  5866 compara as duas).

Como validar: Query 5866 (mesma pasta).
Como reverter: DROP FUNCTION public.get_my_pokedex_representative_variants(uuid, uuid[]);
================================================================
*/

begin;

create or replace function public.get_my_pokedex_representative_variants(
  p_collection_id uuid,
  p_position_ids  uuid[]
)
returns table (
  pokedex_position_id uuid,
  card_variant_id     uuid,
  variant_label       text,
  language_code       text,
  collector_number    text,
  card_set_code       text
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

  if p_position_ids is null or cardinality(p_position_ids) = 0 or cardinality(p_position_ids) > 500 then
    raise exception 'INVALID_POSITION_IDS' using errcode = '22023';
  end if;

  if p_collection_id is null or not exists (
    select 1 from public.collection c
    where c.id = p_collection_id and c.owner_user_id = v_user
  ) then
    return;
  end if;

  return query
  with links as (
    -- Mesma origem da CTE links da 5204, restrita às posições pedidas.
    select a.pokedex_position_id as pos_id, ca.id as alloc_id, ca.physical_card_id as pc_id,
           a.assigned_at, (pr.collection_allocation_id is not null) as is_rep
    from public.collection_allocation ca
    join public.collection_pokedex_position_assignment a on a.collection_allocation_id = ca.id
    left join public.collection_pokedex_position_primary_representative pr
      on pr.collection_allocation_id = ca.id and pr.collection_id = p_collection_id
    where ca.collection_id = p_collection_id
      and a.pokedex_position_id = any(p_position_ids)
  ),
  rep as (
    -- Mesma ordenação da CTE rep da 5204.
    select distinct on (l.pos_id) l.pos_id, l.pc_id
    from links l
    order by l.pos_id, l.is_rep desc, l.assigned_at, l.alloc_id
  )
  select
    r.pos_id,
    cv.id,
    nullif(concat_ws(' · ', vt.name, pp.name, ec.name), '')::text,
    l.code::text,
    c.collector_number::text,
    cs.code::text
  from rep r
  join public.physical_card pc on pc.id = r.pc_id
  join public.card_variant cv  on cv.id = pc.card_variant_id
  join public.card c           on c.id = cv.card_id
  join public.card_set cs      on cs.id = c.card_set_id
  join public.language l       on l.id = pc.language_id
  left join public.card_variant_type vt            on vt.id = cv.variant_type_id
  left join public.card_printing_profile pp        on pp.id = cv.printing_profile_id
  left join public.card_edition_context_profile ec on ec.id = cv.edition_context_profile_id
  order by r.pos_id;
end;
$$;

comment on function public.get_my_pokedex_representative_variants(uuid, uuid[]) is
  'V1-09 Fase B (Query 5334): variante, idioma e identificação da carta do exemplar representante de cada posição pedida (até 500) de uma coleção Pokédex do usuário — mesma regra de representante da 5204. Coleção alheia ou inexistente = zero linhas.';

revoke all on function public.get_my_pokedex_representative_variants(uuid, uuid[]) from public;
revoke all on function public.get_my_pokedex_representative_variants(uuid, uuid[]) from anon;
grant execute on function public.get_my_pokedex_representative_variants(uuid, uuid[]) to authenticated;

commit;

-- Como validar (rápido; completo na 5866):
-- select p.oid::regprocedure, p.prosecdef, p.proconfig, p.provolatile,
--        has_function_privilege('anon', p.oid, 'EXECUTE') as anon_exec,
--        has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_exec
-- from pg_proc p where p.oid = 'public.get_my_pokedex_representative_variants(uuid,uuid[])'::regprocedure;
-- Esperado: t | {search_path=""} | s | f | t
