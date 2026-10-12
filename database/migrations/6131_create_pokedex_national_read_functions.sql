-- Query 6131 | Pokédex P1 — leitura da Pokédex Nacional para usuários autenticados
--
-- Status: CONFIRMADO EXECUTADO em 2026-10-12 via Supabase MCP (apply_migration
-- "6131_create_pokedex_national_read_functions"), versão de execução v1.0 — conteúdo
-- idêntico à proposta preparada (sha256 do arquivo de proposta 72ee70ed…d9531f2).
-- Validação: Query 6841 v1.1 = "6841 PASS" (anon, sem sessão, usuário autenticado e
-- administrador; tabelas do catálogo Pokémon sem leitura direta). Postcheck: contagens,
-- hash das 1.025 espécies, ACLs e policies de public idênticos ao baseline pré-execução.
--
-- Objetivo
-- Disponibilizar a Pokédex Nacional (1.025 espécies, 9 gerações) a qualquer usuário
-- autenticado SEM abrir as tabelas do catálogo Pokémon. Hoje pokemon_species,
-- pokemon_generation e pokemon_region têm RLS ligada, nenhuma policy e nenhum GRANT para
-- authenticated — só o backend administrativo lê. Em vez de criar policies/GRANTs amplos
-- (que exporiam colunas internas como id, is_active, created_at/updated_at e as tabelas de
-- referência externa), esta Query cria duas funções de leitura com contrato fechado,
-- mesmo padrão já usado em produção por public.search_cards() (Query 4032):
--   SECURITY DEFINER STABLE, SET search_path = '', objetos qualificados, auth.uid()
--   obrigatório (erro 28000), REVOKE de PUBLIC/anon, GRANT EXECUTE só a authenticated.
--
-- Contrato exposto (somente o necessário à experiência do colecionador)
--   get_pokedex_generations()            -> 9 linhas: código, ordinal, região, contagem,
--                                           primeiro e último número nacional.
--   get_pokedex_national_species(q, g)   -> número nacional, nome oficial, código e ordinal
--                                           da geração. Nenhum UUID, nenhuma coluna
--                                           administrativa, nenhum dado pessoal.
--
-- Busca (p_query, até 64 caracteres)
--   - Só dígitos (aceita "#" e espaços: "25", "#025", "0025") -> número nacional exato.
--   - Caso contrário -> nome, sem acento/caixa e ignorando espaço, ponto, apóstrofos, dois-
--     pontos, hífen e ♀/♂ ("flabebe" encontra Flabébé; "mr mime" encontra Mr. Mime;
--     "farfetchd" encontra Farfetch’d; "nidoran" encontra os dois Nidoran).
--   - p_generation (ordinal 1..9) filtra por geração; NULL = todas.
--
-- Performance
-- Universo fixo e pequeno (1.025 linhas, 9 gerações). Os filtros são avaliados sobre
-- pokemon_species inteira com join por PK/UNIQUE já existentes (ix_pokemon_species_
-- generation_id, uq_pokemon_generation_ordinal_number); nenhum índice novo é necessário
-- (custo medido no LIVE com a mesma expressão, ver "Como validar"). Quando o catálogo
-- crescer para formas/idiomas, a busca por nome migra para uma coluna normalizada indexada
-- (pg_trgm já instalado) sem mudar o contrato.
--
-- Internacionalização
-- species_name devolve o nome oficial (canonical_name), que é o mesmo em pt-BR. Rótulos de
-- geração/região são localizados na interface a partir dos códigos estáveis
-- (generation_code/region_code) — novos idiomas não exigem mudança neste contrato; nomes
-- de espécie traduzidos (ja, fr...) entram depois como uma tabela de nomes por idioma.
--
-- Escopo: nenhuma tabela, policy, GRANT de tabela ou dado é alterado. Só cria 2 funções.

create or replace function public.get_pokedex_generations()
returns table (
  generation_code text,
  generation_ordinal integer,
  region_code text,
  region_name text,
  species_count bigint,
  first_number integer,
  last_number integer
)
language plpgsql security definer stable set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  return query
  select
    g.code::text,
    g.ordinal_number,
    r.code::text,
    r.canonical_name::text,
    count(s.id),
    min(s.national_dex_number),
    max(s.national_dex_number)
  from public.pokemon_generation g
  left join public.pokemon_region r on r.id = g.main_region_id and r.is_active
  left join public.pokemon_species s on s.generation_id = g.id and s.is_active
  where g.is_active
  group by g.code, g.ordinal_number, r.code, r.canonical_name
  order by g.ordinal_number;
end;
$$;

comment on function public.get_pokedex_generations() is
  'Pokédex P1 (Query 6131): gerações ativas com região principal e contagem de espécies. Leitura para usuários autenticados; sem colunas administrativas.';

create or replace function public.get_pokedex_national_species(
  p_query text default null,
  p_generation integer default null
)
returns table (
  national_dex_number integer,
  species_name text,
  generation_code text,
  generation_ordinal integer
)
language plpgsql security definer stable set search_path = ''
as $$
declare
  v_query text;
  v_digits text;
  v_number integer;
  v_name_key text;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  v_query := nullif(btrim(left(coalesce(p_query, ''), 64)), '');

  if v_query is not null then
    v_digits := replace(replace(v_query, '#', ''), ' ', '');
    if v_digits <> '' and length(v_digits) <= 5 and translate(v_digits, '0123456789', '') = '' then
      v_number := v_digits::integer;
    else
      v_name_key := translate(lower(extensions.unaccent(v_query)), ' .''’:-♀♂', '');
    end if;
  end if;

  return query
  select
    s.national_dex_number,
    s.canonical_name::text,
    g.code::text,
    g.ordinal_number
  from public.pokemon_species s
  join public.pokemon_generation g on g.id = s.generation_id and g.is_active
  where s.is_active
    and (p_generation is null or g.ordinal_number = p_generation)
    and (
      v_query is null
      or (v_number is not null and s.national_dex_number = v_number)
      or (
        v_number is null
        and v_name_key <> ''
        and strpos(translate(lower(extensions.unaccent(s.canonical_name::text)), ' .''’:-♀♂', ''), v_name_key) > 0
      )
    )
  order by s.national_dex_number;
end;
$$;

comment on function public.get_pokedex_national_species(text, integer) is
  'Pokédex P1 (Query 6131): espécies da Pokédex Nacional (número, nome oficial, geração), com busca por número ou nome e filtro por geração. Leitura para usuários autenticados; sem colunas administrativas.';

revoke all on function public.get_pokedex_generations() from public;
revoke all on function public.get_pokedex_generations() from anon;
grant execute on function public.get_pokedex_generations() to authenticated;

revoke all on function public.get_pokedex_national_species(text, integer) from public;
revoke all on function public.get_pokedex_national_species(text, integer) from anon;
grant execute on function public.get_pokedex_national_species(text, integer) to authenticated;

-- Resultado esperado
-- Duas funções novas em public, SECURITY DEFINER, search_path vazio, EXECUTE apenas para
-- authenticated (e owner/service_role). Nenhuma alteração em tabelas, RLS ou GRANTs de
-- tabela: pokemon_species/pokemon_generation/pokemon_region continuam ilegíveis
-- diretamente por anon/authenticated.
--
-- Como validar (ver também 6841_validate_pokedex_national_read_functions.sql)
-- select p.proname, p.prosecdef, p.proconfig,
--        has_function_privilege('anon', p.oid, 'execute') as anon_exec,
--        has_function_privilege('authenticated', p.oid, 'execute') as auth_exec
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--  where n.nspname = 'public'
--    and p.proname in ('get_pokedex_generations', 'get_pokedex_national_species');
-- -- esperado: 2 linhas, prosecdef = true, proconfig = {search_path=""},
-- --           anon_exec = false, auth_exec = true.
