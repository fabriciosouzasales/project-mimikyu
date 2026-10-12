-- Query 6134 | Pokédex P3b — arte original para a ficha da espécie
--
-- Status: PROPOSTA (não executada). Aplicar no LIVE só com autorização específica.
--
-- Objetivo
-- Expor, de forma controlada e somente leitura, o caminho do PNG original (475 px) da arte
-- oficial de UMA espécie, para o palco da página de detalhes (/pokedex/[numero]). A galeria
-- continua usando o WebP de 320 px devolvido por get_pokedex_national_species (6132) e
-- get_pokedex_species_detail (6133) — nenhuma das duas muda.
--
-- Por que uma função nova e não alterar a 6133
-- - Mudar o retorno de get_pokedex_species_detail exigiria DROP + CREATE da função da 6133
--   (o tipo de retorno de uma função não pode ser alterado com CREATE OR REPLACE).
-- - A função nova é aditiva: sem ela, a página funciona com o WebP de 320 px (fallback).
--
-- Contrato
--   get_pokedex_species_hero_artwork(p_national_dex_number integer)
--   -> 0 ou 1 linha: national_dex_number, original_path, original_width, original_height,
--      display_path
--   - Exige sessão (auth.uid()); recusa anônimo com 28000, como as demais funções da Pokédex.
--   - Só devolve arte com status IMPORTED. Espécie inexistente, número inválido ou arte
--     ausente -> nenhuma linha (a página usa o fallback).
--   - Nenhum UUID, checksum, fonte, URL externa ou campo administrativo é exposto.
--   - SECURITY DEFINER com search_path vazio e nomes qualificados; EXECUTE só para
--     authenticated (revogado de public e anon).
--
-- Escopo: nenhuma tabela, policy, bucket ou dado alterado.

create or replace function public.get_pokedex_species_hero_artwork(
  p_national_dex_number integer
)
returns table (
  national_dex_number integer,
  original_path text,
  original_width integer,
  original_height integer,
  display_path text
)
language plpgsql security definer stable set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if p_national_dex_number is null or p_national_dex_number < 1 then
    return;
  end if;

  return query
  select s.national_dex_number,
         a.original_storage_path,
         a.original_width,
         a.original_height,
         a.display_storage_path
    from public.pokemon_species s
    join public.pokemon_species_artwork a on a.pokemon_species_id = s.id
   where s.national_dex_number = p_national_dex_number
     and a.status = 'IMPORTED';
end;
$$;

comment on function public.get_pokedex_species_hero_artwork(integer) is
  'Pokédex P3b (Query 6134): caminho do PNG original (475 px) e do WebP de exibição da arte oficial de uma espécie, para o palco da página de detalhes. Somente leitura, exige sessão; 0 linhas quando não há arte importada.';

revoke all on function public.get_pokedex_species_hero_artwork(integer) from public;
revoke all on function public.get_pokedex_species_hero_artwork(integer) from anon;
grant execute on function public.get_pokedex_species_hero_artwork(integer) to authenticated;
