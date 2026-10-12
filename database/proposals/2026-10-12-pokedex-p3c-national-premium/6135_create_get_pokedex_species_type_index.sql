-- Query 6135 | Pokédex P3c — índice de tipos da Pokédex Nacional
--
-- Status: PROPOSTA (não executada). Aplicar no LIVE só com autorização específica.
--
-- Objetivo
-- Entregar à galeria /pokedex, numa única leitura em lote, o tipo primário e o secundário
-- (código + rótulo no idioma pedido) de todas as espécies com perfil importado, para a
-- ambientação dos cards e os chips de tipo. Sem consulta por espécie (sem N+1).
--
-- Por que uma função nova e não alterar a 6131/6132
-- - get_pokedex_national_species (6131, ampliada pela 6132) é contrato aprovado da galeria;
--   mudar o tipo de retorno exigiria DROP + CREATE. A função nova é aditiva: sem ela, a
--   galeria funciona igual, com os cards no tom neutro (degradação prevista no front).
-- - Mesma regra de tipos da ficha (get_pokedex_species_detail, 6133): forma padrão do
--   perfil IMPORTED, slot 1 = primário, slot 2 = secundário, rótulo labels->>idioma com
--   recuo para 'en'. A galeria e a ficha nunca divergem sobre o tipo de uma espécie.
--
-- Contrato
--   get_pokedex_species_type_index(p_language text default 'pt-BR')
--   -> uma linha por espécie ativa com perfil IMPORTED e tipo primário:
--      national_dex_number, primary_type_code, primary_type_label,
--      secondary_type_code, secondary_type_label (os dois últimos podem ser null)
--   - Espécie sem perfil importado não aparece (o card usa o tom neutro).
--   - Exige sessão (auth.uid()); recusa anônimo com 28000, como as demais funções da Pokédex.
--   - Idioma inválido -> 22023 (mesma validação da 6133).
--   - Nenhum UUID, fonte, hash, status ou campo administrativo é exposto.
--   - SECURITY DEFINER com search_path vazio e nomes qualificados; EXECUTE só para
--     authenticated (revogado de public e anon). As tabelas continuam fechadas.
--   - Ordenada pelo número nacional; ~1.025 linhas. O leitor do front pagina pelo teto do
--     PostgREST (1.000), como já faz com a galeria.
--
-- Custo: varredura das espécies ativas com joins por chave (perfil -> forma padrão -> dois
-- slots de tipo -> vocabulário de 18 tipos); todas as junções usam PK/UNIQUE existentes
-- (pk_pokemon_form_type (pokemon_form_id, slot), uq_pokemon_species_profile_form, PKs).
--
-- Escopo: nenhuma tabela, policy, bucket, dado ou função existente alterados.

create or replace function public.get_pokedex_species_type_index(
  p_language text default 'pt-BR'
)
returns table (
  national_dex_number integer,
  primary_type_code text,
  primary_type_label text,
  secondary_type_code text,
  secondary_type_label text
)
language plpgsql security definer stable set search_path = ''
as $$
declare
  v_lang text;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  v_lang := coalesce(nullif(btrim(p_language), ''), 'pt-BR');
  if v_lang !~ '^[a-z]{2,3}(-[A-Z][a-z]{3})?(-([A-Z]{2}|[0-9]{3}))?$' then
    raise exception 'INVALID_LANGUAGE: %', left(v_lang, 20) using errcode = '22023';
  end if;

  return query
  select
    s.national_dex_number,
    t1.code,
    coalesce(t1.labels ->> v_lang, t1.labels ->> 'en'),
    t2.code,
    coalesce(t2.labels ->> v_lang, t2.labels ->> 'en')
  from public.pokemon_species s
  join public.pokemon_species_profile p on p.pokemon_species_id = s.id and p.status = 'IMPORTED'
  join public.pokemon_form f on f.id = p.default_form_id
  join public.pokemon_form_type ft1 on ft1.pokemon_form_id = f.id and ft1.slot = 1
  join public.pokemon_type t1 on t1.id = ft1.pokemon_type_id
  left join public.pokemon_form_type ft2 on ft2.pokemon_form_id = f.id and ft2.slot = 2
  left join public.pokemon_type t2 on t2.id = ft2.pokemon_type_id
  where s.is_active
  order by s.national_dex_number;
end;
$$;

comment on function public.get_pokedex_species_type_index(text) is
  'Pokédex P3c (Query 6135): tipo primário e secundário (código + rótulo no idioma) de todas as espécies com perfil importado, numa leitura em lote para a galeria. Mesma regra de tipos de get_pokedex_species_detail. Leitura para usuários autenticados; sem colunas administrativas.';

revoke all on function public.get_pokedex_species_type_index(text) from public;
revoke all on function public.get_pokedex_species_type_index(text) from anon;
grant execute on function public.get_pokedex_species_type_index(text) to authenticated;

-- Resultado esperado: função criada; EXECUTE só para authenticated.
-- Como validar: executar a Query 6846 (BEGIN/ROLLBACK) e esperar "6846 PASS".
