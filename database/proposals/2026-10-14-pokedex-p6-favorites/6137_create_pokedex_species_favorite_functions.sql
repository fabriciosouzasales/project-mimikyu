/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 6137 - Create Pokédex Species Favorite Functions
Versão......: 1.0
Status......: PROPOSTO — NÃO EXECUTADO (aguarda auditoria independente
              e autorização; quem executa é Fabrício)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-14 (Pokédex P6.1)
Descrição...:
Duas funções, únicas vias de acesso do produto à tabela da Query 6136:

1. get_my_pokedex_favorites()
   Números nacionais das espécies favoritas do usuário da sessão, em
   ordem. Uma leitura agregada por página (galeria, página Pokémons
   Favoritos, ficha) — nunca uma chamada por card. Sem UUIDs.

2. set_pokedex_species_favorite(p_national_dex_number, p_favorite)
   DEFINE o estado (não alterna): true → favorita; false → não
   favorita. Repetir a mesma chamada dá o mesmo resultado (idempotente);
   cliques duplos, retries e respostas fora de ordem nunca invertem o
   estado. Devolve o estado final.
   - Favoritar exige espécie ATIVA.
   - Desfavoritar aceita espécie inativa (o usuário nunca fica preso a
     um favorito que não consegue remover).
   - INSERT ... ON CONFLICT ON CONSTRAINT (nome explícito — evita a
     classe de ambiguidade corrigida em 6126) e DELETE restrito a
     user_id = auth.uid(): seguros sob concorrência.

Segurança (padrão 6131/6135 e 5034):
- SECURITY DEFINER, SET search_path = '', objetos qualificados.
- auth.uid() obrigatório: sem sessão → 'not_authenticated' (28000).
- user_id NUNCA é parâmetro — resolvido no servidor.
- Entradas validadas: número 1..9999 e não nulo; estado não nulo.
- EXECUTE: revogado de PUBLIC e anon; concedido só a authenticated.

Erros (SQLSTATE):
- 28000 not_authenticated
- 22023 INVALID_NATIONAL_DEX_NUMBER / INVALID_FAVORITE_STATE
- P0002 SPECIES_NOT_FOUND (inexistente; ou inativa ao favoritar)

Pré-requisitos:
- Query 6136 executada.

Resultado esperado:
- 2 funções criadas, prosecdef = true, proconfig com search_path="",
  EXECUTE somente para authenticated (e owner).

Como validar:
- Query 6849, Seções 1–3.
================================================================
*/

begin;

create or replace function public.get_my_pokedex_favorites()
returns table (national_dex_number integer)
language plpgsql
security definer
stable
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  return query
  select s.national_dex_number
  from public.pokedex_species_favorite f
  join public.pokemon_species s
    on s.id = f.pokemon_species_id
   and s.is_active
  where f.user_id = v_user
  order by s.national_dex_number;
end;
$$;

comment on function public.get_my_pokedex_favorites() is
  'Pokédex P6 (Query 6137): números nacionais das espécies favoritas do usuário da sessão, em ordem. Leitura agregada (uma por página); exige auth.uid(); sem UUIDs.';

create or replace function public.set_pokedex_species_favorite(
  p_national_dex_number integer,
  p_favorite boolean
)
returns boolean
language plpgsql
security definer
volatile
set search_path = ''
as $$
declare
  v_user      uuid := auth.uid();
  v_species   uuid;
  v_is_active boolean;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if p_favorite is null then
    raise exception 'INVALID_FAVORITE_STATE' using errcode = '22023';
  end if;

  if p_national_dex_number is null or p_national_dex_number not between 1 and 9999 then
    raise exception 'INVALID_NATIONAL_DEX_NUMBER' using errcode = '22023';
  end if;

  select s.id, s.is_active
    into v_species, v_is_active
  from public.pokemon_species s
  where s.national_dex_number = p_national_dex_number;

  if v_species is null or (p_favorite and not v_is_active) then
    raise exception 'SPECIES_NOT_FOUND' using errcode = 'P0002';
  end if;

  if p_favorite then
    insert into public.pokedex_species_favorite (user_id, pokemon_species_id)
    values (v_user, v_species)
    on conflict on constraint pk_pokedex_species_favorite do nothing;
  else
    delete from public.pokedex_species_favorite f
    where f.user_id = v_user
      and f.pokemon_species_id = v_species;
  end if;

  return p_favorite;
end;
$$;

comment on function public.set_pokedex_species_favorite(integer, boolean) is
  'Pokédex P6 (Query 6137): define (não alterna) se uma espécie é favorita do usuário da sessão; idempotente; devolve o estado final. Única via de escrita de pokedex_species_favorite.';

revoke all on function public.get_my_pokedex_favorites() from public;
revoke all on function public.get_my_pokedex_favorites() from anon;
grant execute on function public.get_my_pokedex_favorites() to authenticated;

revoke all on function public.set_pokedex_species_favorite(integer, boolean) from public;
revoke all on function public.set_pokedex_species_favorite(integer, boolean) from anon;
grant execute on function public.set_pokedex_species_favorite(integer, boolean) to authenticated;

commit;
