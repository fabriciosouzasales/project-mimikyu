-- Query 6841 v1.1 | Validação da Query 6131 (Pokédex P1 — leitura da Pokédex Nacional)
--
-- Objetivo
-- Provar, depois de executar a 6131, que:
--   1. as duas funções existem com o endurecimento esperado e o contrato de saída exato
--      (nenhuma coluna administrativa ou pessoal);
--   2. sem sessão (auth.uid() nulo) a chamada é recusada (28000);
--   3. usuário autenticado comum lê a Pokédex (1.025 espécies, 9 gerações, busca e filtro);
--   4. administrador lê a Pokédex pelo mesmo contrato (sem privilégio extra);
--   5. anon não executa as funções;
--   6. as tabelas do catálogo Pokémon continuam sem leitura direta para anon, usuário
--      autenticado e administrador.
--
-- v1.1 (2026-10-12, antes da execução): acrescentado o perfil administrador (passo 4, usa o
-- id de um admin_user existente só como claim de sessão — nada é gravado), a checagem do
-- contrato de saída (passo 1c) e a cobertura de todas as tabelas do catálogo Pokémon
-- (pokemon_species, pokemon_generation, pokemon_region, pokemon_species_external_reference,
-- pokedex, pokedex_position) para anon/authenticated.
--
-- Execução: rodar o arquivo inteiro de uma vez. Tudo acontece dentro de BEGIN/ROLLBACK —
-- nenhuma escrita persiste. Qualquer falha interrompe com "6841 FAIL ...".
-- Resultado esperado: nenhuma exceção e a linha final "6841 PASS".

begin;

-- 1. Estrutura, privilégios e contrato
do $$
declare
  v_count integer;
  v_table text;
begin
  -- 1a. Endurecimento
  select count(*) into v_count
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('get_pokedex_generations', 'get_pokedex_national_species')
     and p.prosecdef
     and p.proconfig = array['search_path=""']
     and not has_function_privilege('anon', p.oid, 'execute')
     and has_function_privilege('authenticated', p.oid, 'execute');
  if v_count <> 2 then
    raise exception '6841 FAIL 1a: esperado 2 funções endurecidas, encontrado %', v_count;
  end if;

  -- 1b. Tabelas do catálogo Pokémon sem leitura direta para anon/authenticated
  foreach v_table in array array[
    'public.pokemon_species', 'public.pokemon_generation', 'public.pokemon_region',
    'public.pokemon_species_external_reference', 'public.pokedex', 'public.pokedex_position'
  ] loop
    if has_table_privilege('anon', v_table, 'select') or has_table_privilege('authenticated', v_table, 'select') then
      raise exception '6841 FAIL 1b: % legível diretamente', v_table;
    end if;
  end loop;

  -- 1c. Contrato de saída exato (nenhum UUID, nenhuma coluna administrativa/pessoal)
  if pg_get_function_result('public.get_pokedex_national_species(text, integer)'::regprocedure)
     <> 'TABLE(national_dex_number integer, species_name text, generation_code text, generation_ordinal integer)' then
    raise exception '6841 FAIL 1c: contrato de get_pokedex_national_species divergente';
  end if;
  if pg_get_function_result('public.get_pokedex_generations()'::regprocedure)
     <> 'TABLE(generation_code text, generation_ordinal integer, region_code text, region_name text, species_count bigint, first_number integer, last_number integer)' then
    raise exception '6841 FAIL 1c: contrato de get_pokedex_generations divergente';
  end if;
end;
$$;

-- 2. Sem sessão (auth.uid() nulo) -> 28000
set local role authenticated;
set local request.jwt.claims = '{"role":"authenticated"}';
do $$
begin
  perform public.get_pokedex_national_species();
  raise exception '6841 FAIL 2: chamada sem sub não foi recusada';
exception
  when sqlstate '28000' then null;
end;
$$;

-- 3. Usuário autenticado comum (uuid sintético, não é admin)
set local request.jwt.claims = '{"sub":"00000000-0000-4000-8000-000000006841","role":"authenticated"}';
do $$
declare
  v_total integer;
  v_gen integer;
  v_gen9 integer;
  v_name text;
  v_rows integer;
begin
  if public.is_admin() then raise exception '6841 FAIL 3: usuário sintético é admin'; end if;

  select count(*) into v_total from public.get_pokedex_national_species();
  if v_total <> 1025 then raise exception '6841 FAIL 3a: total %', v_total; end if;

  select count(*), sum(species_count) filter (where generation_ordinal = 9)
    into v_gen, v_gen9 from public.get_pokedex_generations();
  if v_gen <> 9 or v_gen9 <> 120 then raise exception '6841 FAIL 3b: gerações % / Gen IX %', v_gen, v_gen9; end if;

  select species_name into v_name from public.get_pokedex_national_species('#0025');
  if v_name is distinct from 'Pikachu' then raise exception '6841 FAIL 3c: #0025 -> %', v_name; end if;

  select species_name into v_name from public.get_pokedex_national_species('flabebe');
  if v_name is distinct from 'Flabébé' then raise exception '6841 FAIL 3d: flabebe -> %', v_name; end if;

  select count(*) into v_rows from public.get_pokedex_national_species('nidoran');
  if v_rows <> 2 then raise exception '6841 FAIL 3e: nidoran -> %', v_rows; end if;

  select count(*) into v_rows from public.get_pokedex_national_species('char', 1);
  if v_rows <> 3 then raise exception '6841 FAIL 3f: char/Gen I -> %', v_rows; end if;

  select count(*) into v_rows from public.get_pokedex_national_species(null, 9);
  if v_rows <> 120 then raise exception '6841 FAIL 3g: Gen IX -> %', v_rows; end if;

  select count(*) into v_rows from public.get_pokedex_national_species('zzz');
  if v_rows <> 0 then raise exception '6841 FAIL 3h: zzz -> %', v_rows; end if;

  begin
    perform 1 from public.pokemon_species limit 1;
    raise exception '6841 FAIL 3i: usuário comum leu pokemon_species diretamente';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

-- 4. Administrador (id real de admin_user, usado só como claim de sessão)
reset role;
select set_config(
  'request.jwt.claims',
  json_build_object('sub', (select id from public.admin_user order by granted_at limit 1), 'role', 'authenticated')::text,
  true
);
set local role authenticated;
do $$
declare
  v_total integer;
  v_gen integer;
begin
  if not public.is_admin() then raise exception '6841 FAIL 4: sessão de admin não reconhecida'; end if;

  select count(*) into v_total from public.get_pokedex_national_species();
  select count(*) into v_gen from public.get_pokedex_generations();
  if v_total <> 1025 or v_gen <> 9 then raise exception '6841 FAIL 4a: admin % espécies / % gerações', v_total, v_gen; end if;

  begin
    perform 1 from public.pokemon_species limit 1;
    raise exception '6841 FAIL 4b: admin leu pokemon_species diretamente (permissão não deveria ter mudado)';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

-- 5. anon não executa
reset role;
set local role anon;
do $$
begin
  perform public.get_pokedex_generations();
  raise exception '6841 FAIL 5: anon executou get_pokedex_generations';
exception
  when insufficient_privilege then null;
end;
$$;
do $$
begin
  perform public.get_pokedex_national_species();
  raise exception '6841 FAIL 5b: anon executou get_pokedex_national_species';
exception
  when insufficient_privilege then null;
end;
$$;

reset role;
select '6841 PASS' as resultado;

rollback;
