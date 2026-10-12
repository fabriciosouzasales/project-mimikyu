-- Query 6845 | Validação da Query 6134 (somente leitura, BEGIN/ROLLBACK)
--
-- Uso: executar inteira, depois da 6134. Não grava nada (a transação é desfeita no fim).
-- Resultado esperado: um único NOTICE "6845 PASS"; qualquer falha interrompe com
-- "6845 FAIL: <motivo>".

begin;

do $$
declare
  v_oid oid := to_regprocedure('public.get_pokedex_species_hero_artwork(integer)');
  v_def text;
  v_user uuid;
  v_row record;
  v_count integer;
begin
  if v_oid is null then raise exception '6845 FAIL: função ausente'; end if;

  select pg_get_functiondef(v_oid) into v_def;
  if position('SECURITY DEFINER' in upper(v_def)) = 0 then raise exception '6845 FAIL: não é SECURITY DEFINER'; end if;
  if not exists (select 1 from pg_proc where oid = v_oid and proconfig @> array['search_path=""']) then
    raise exception '6845 FAIL: search_path não está vazio';
  end if;
  if has_function_privilege('anon', v_oid, 'execute') then raise exception '6845 FAIL: anon pode executar'; end if;
  if not has_function_privilege('authenticated', v_oid, 'execute') then raise exception '6845 FAIL: authenticated não pode executar'; end if;

  -- Anônimo (sem claims) é recusado com 28000.
  perform set_config('request.jwt.claims', '{}', true);
  begin
    perform public.get_pokedex_species_hero_artwork(1);
    raise exception '6845 FAIL: chamada sem sessão foi aceita';
  exception when sqlstate '28000' then null;
  end;

  -- Sessão autenticada (qualquer usuário existente; nada é gravado).
  select id into v_user from auth.users order by created_at limit 1;
  if v_user is null then raise exception '6845 FAIL: nenhum usuário para simular sessão'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', v_user::text, 'role', 'authenticated')::text, true);

  select * into v_row from public.get_pokedex_species_hero_artwork(1);
  if v_row.national_dex_number is distinct from 1 then raise exception '6845 FAIL: #1 sem linha'; end if;
  if v_row.original_path !~ '^official-artwork/0001/original-[0-9a-f]{16}\.png$' then raise exception '6845 FAIL: caminho original inesperado: %', v_row.original_path; end if;
  if v_row.display_path !~ '^official-artwork/0001/w320-[0-9a-f]{16}\.webp$' then raise exception '6845 FAIL: caminho de exibição inesperado'; end if;
  if v_row.original_width is null or v_row.original_height is null then raise exception '6845 FAIL: dimensões ausentes'; end if;

  select count(*) into v_count from public.get_pokedex_species_hero_artwork(1025);
  if v_count <> 1 then raise exception '6845 FAIL: #1025 deveria ter 1 linha'; end if;
  select count(*) into v_count from public.get_pokedex_species_hero_artwork(0);
  if v_count <> 0 then raise exception '6845 FAIL: número 0 deveria ter 0 linhas'; end if;
  select count(*) into v_count from public.get_pokedex_species_hero_artwork(99999);
  if v_count <> 0 then raise exception '6845 FAIL: espécie inexistente deveria ter 0 linhas'; end if;
  select count(*) into v_count from public.get_pokedex_species_hero_artwork(null);
  if v_count <> 0 then raise exception '6845 FAIL: null deveria ter 0 linhas'; end if;

  -- Cobertura: todas as espécies com arte importada resolvem pela função.
  select count(*) into v_count
    from public.pokemon_species s
   where exists (select 1 from public.get_pokedex_species_hero_artwork(s.national_dex_number));
  if v_count <> (select count(*) from public.pokemon_species_artwork where status = 'IMPORTED') then
    raise exception '6845 FAIL: cobertura % diferente das artes importadas', v_count;
  end if;

  raise notice '6845 PASS (cobertura: % espécies)', v_count;
end
$$;

rollback;
