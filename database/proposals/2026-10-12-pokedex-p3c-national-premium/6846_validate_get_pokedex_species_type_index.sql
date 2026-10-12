-- Query 6846 | Validação da Query 6135 (somente leitura, BEGIN/ROLLBACK)
--
-- Uso: executar inteira, depois da 6135. Não grava nada (a transação é desfeita no fim).
-- Resultado esperado: um único NOTICE "6846 PASS (...)"; qualquer falha interrompe com
-- "6846 FAIL: <motivo>".

begin;

do $$
declare
  v_oid oid := to_regprocedure('public.get_pokedex_species_type_index(text)');
  v_def text;
  v_user uuid;
  v_rows integer;
  v_distinct integer;
  v_expected integer;
  v_bad integer;
  v_r record;
begin
  -- 1. Estrutura e permissões
  if v_oid is null then raise exception '6846 FAIL: função ausente'; end if;
  select pg_get_functiondef(v_oid) into v_def;
  if position('SECURITY DEFINER' in upper(v_def)) = 0 then raise exception '6846 FAIL: não é SECURITY DEFINER'; end if;
  if not exists (select 1 from pg_proc where oid = v_oid and proconfig @> array['search_path=""']) then
    raise exception '6846 FAIL: search_path não está vazio';
  end if;
  if has_function_privilege('anon', v_oid, 'execute') then raise exception '6846 FAIL: anon pode executar'; end if;
  if not has_function_privilege('authenticated', v_oid, 'execute') then raise exception '6846 FAIL: authenticated não pode executar'; end if;
  if exists (select 1 from pg_proc pr cross join lateral aclexplode(pr.proacl) a where pr.oid = v_oid and a.grantee = 0) then
    raise exception '6846 FAIL: EXECUTE concedido a PUBLIC';
  end if;

  -- 2. Sem sessão: recusado com 28000
  perform set_config('request.jwt.claims', '{}', true);
  begin
    perform public.get_pokedex_species_type_index();
    raise exception '6846 FAIL: chamada sem sessão foi aceita';
  exception when sqlstate '28000' then null;
  end;

  -- 3. Sessão autenticada (qualquer usuário existente; nada é gravado)
  select id into v_user from auth.users order by created_at limit 1;
  if v_user is null then raise exception '6846 FAIL: nenhum usuário para simular sessão'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', v_user::text, 'role', 'authenticated')::text, true);

  -- 4. Idioma inválido: 22023
  begin
    perform public.get_pokedex_species_type_index('pt_BR; drop');
    raise exception '6846 FAIL: idioma inválido aceito';
  exception when sqlstate '22023' then null;
  end;

  -- 5. Cobertura: uma linha por espécie ativa com perfil IMPORTED, sem duplicidade
  select count(*), count(distinct national_dex_number) into v_rows, v_distinct
    from public.get_pokedex_species_type_index();
  select count(*) into v_expected
    from public.pokemon_species s
    join public.pokemon_species_profile p on p.pokemon_species_id = s.id and p.status = 'IMPORTED'
   where s.is_active;
  if v_rows <> v_expected then raise exception '6846 FAIL: % linhas, esperado %', v_rows, v_expected; end if;
  if v_distinct <> v_rows then raise exception '6846 FAIL: números nacionais duplicados'; end if;

  -- 6. Forma dos dados: primário sempre presente; secundário par (código, rótulo) e diferente do primário
  select count(*) into v_bad from public.get_pokedex_species_type_index() t
   where t.primary_type_code is null or t.primary_type_label is null
      or (t.secondary_type_code is null) <> (t.secondary_type_label is null)
      or t.secondary_type_code = t.primary_type_code
      or t.primary_type_code !~ '^[A-Z][A-Z_]*$';
  if v_bad <> 0 then raise exception '6846 FAIL: % linhas com tipos malformados', v_bad; end if;

  -- 7. Casos conhecidos (rótulos pt-BR)
  select * into v_r from public.get_pokedex_species_type_index() t where t.national_dex_number = 1;
  if v_r.primary_type_code is distinct from 'GRASS' or v_r.secondary_type_code is distinct from 'POISON'
     or v_r.primary_type_label is distinct from 'Planta' then
    raise exception '6846 FAIL: #1 esperado GRASS/POISON (Planta), veio %/% (%)', v_r.primary_type_code, v_r.secondary_type_code, v_r.primary_type_label;
  end if;
  select * into v_r from public.get_pokedex_species_type_index() t where t.national_dex_number = 25;
  if v_r.primary_type_code is distinct from 'ELECTRIC' or v_r.secondary_type_code is not null then
    raise exception '6846 FAIL: #25 esperado ELECTRIC sem secundário';
  end if;
  select * into v_r from public.get_pokedex_species_type_index('en') t where t.national_dex_number = 1;
  if v_r.primary_type_label is distinct from 'Grass' then
    raise exception '6846 FAIL: rótulo en de #1 esperado Grass, veio %', v_r.primary_type_label;
  end if;

  -- 8. Coerência com a ficha (6133) em amostra de todas as gerações
  select count(*) into v_bad
    from unnest(array[1, 6, 25, 94, 150, 197, 249, 384, 445, 493, 649, 718, 721, 809, 890, 906, 1025]) n
    cross join lateral (select * from public.get_pokedex_species_detail(n)) d
    left join lateral (select * from public.get_pokedex_species_type_index() t where t.national_dex_number = n) i on true
   where d.primary_type_code is distinct from i.primary_type_code
      or d.secondary_type_code is distinct from i.secondary_type_code
      or d.primary_type_label is distinct from i.primary_type_label
      or d.secondary_type_label is distinct from i.secondary_type_label;
  if v_bad <> 0 then raise exception '6846 FAIL: % espécies divergem da ficha (6133)', v_bad; end if;

  raise notice '6846 PASS (linhas: %, com dois tipos: %)', v_rows,
    (select count(*) from public.get_pokedex_species_type_index() t where t.secondary_type_code is not null);
end
$$;

rollback;
