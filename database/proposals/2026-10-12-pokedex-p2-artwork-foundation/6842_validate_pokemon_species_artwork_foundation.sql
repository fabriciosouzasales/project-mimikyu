-- Query 6842 v1.1 | EXECUTADA 2026-10-12 → "6842 PASS" (após 6132 CONFIRMADO EXECUTADO)
-- Validação da Query 6132 (Pokédex P2 Lote A — fundação das imagens)
--
-- v1.1 (2026-10-12, durante a execução): a v1.0 lia pokemon_species_external_reference
-- dentro do bloco do admin, já no papel authenticated — tabela corretamente fechada
-- (42501). Defeito do fixture, não da 6132. A referência agora é lida antes da troca de
-- papel, como owner, e repassada por set_config (mmkyu.v6842_ref).
--
-- Objetivo
-- Provar, depois de executar a 6132:
--   1. estrutura, RLS, privilégios, bucket e policies como previsto;
--   2. contrato de leitura da Pokédex: 6131 + artwork_path, busca/filtros intactos,
--      1.025 espécies com artwork_path NULL (nenhuma imagem importada ainda);
--   3. colecionador não lê a tabela nem executa funções admin; anon não executa nada;
--   4. admin: cobertura (1.025 PENDING), falha, importação, idempotência, troca,
--      falha que preserva imagem válida, bloqueio de vínculo/caminho/objeto incorretos;
--   5. CHECKs de formato e status.
-- Tudo dentro de BEGIN/ROLLBACK (inclusive 2 objetos fictícios em storage.objects, só
-- metadados, nenhum arquivo real). Resultado esperado: linha final "6842 PASS".

begin;

-- 1. Estrutura e privilégios -----------------------------------------------------------
do $$
declare
  v_count integer;
begin
  if not (select relrowsecurity from pg_class where oid = 'public.pokemon_species_artwork'::regclass) then
    raise exception '6842 FAIL 1a: RLS desligada';
  end if;
  if has_table_privilege('anon', 'public.pokemon_species_artwork', 'select')
     or has_table_privilege('authenticated', 'public.pokemon_species_artwork', 'select')
     or has_table_privilege('authenticated', 'public.pokemon_species_artwork', 'insert')
     or has_table_privilege('authenticated', 'public.pokemon_species_artwork', 'update')
     or has_table_privilege('authenticated', 'public.pokemon_species_artwork', 'delete') then
    raise exception '6842 FAIL 1b: tabela acessível diretamente';
  end if;
  if (select count(*) from public.pokemon_species_artwork) <> 0 then
    raise exception '6842 FAIL 1c: tabela deveria nascer vazia';
  end if;

  select count(*) into v_count
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('admin_record_pokemon_species_artwork_import', 'admin_record_pokemon_species_artwork_failure',
                       'admin_list_pokemon_species_artwork_status', 'get_pokedex_national_species', 'get_pokedex_generations')
     and p.prosecdef and p.proconfig = array['search_path=""']
     and not has_function_privilege('anon', p.oid, 'execute')
     and has_function_privilege('authenticated', p.oid, 'execute');
  if v_count <> 5 then raise exception '6842 FAIL 1d: funções endurecidas = %', v_count; end if;

  if pg_get_function_result('public.get_pokedex_national_species(text, integer)'::regprocedure)
     <> 'TABLE(national_dex_number integer, species_name text, generation_code text, generation_ordinal integer, artwork_path text)' then
    raise exception '6842 FAIL 1e: contrato de get_pokedex_national_species divergente';
  end if;

  if not exists (select 1 from storage.buckets b
                  where b.id = 'pokemon-species-artwork' and b.public and b.file_size_limit = 1048576
                    and b.allowed_mime_types = array['image/png', 'image/webp']) then
    raise exception '6842 FAIL 1f: bucket ausente ou mal configurado';
  end if;
  select count(*) into v_count from pg_policies
   where schemaname = 'storage' and tablename = 'objects'
     and (coalesce(qual, '') || coalesce(with_check, '')) like '%pokemon-species-artwork%';
  if v_count <> 2 or exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
                              and policyname like 'pokemon_species_artwork%' and cmd not in ('INSERT', 'DELETE')) then
    raise exception '6842 FAIL 1g: policies do bucket = % (esperado INSERT + DELETE admin)', v_count;
  end if;

  if (select count(*) from public.pokemon_species) <> 1025 then
    raise exception '6842 FAIL 1h: espécies alteradas';
  end if;
end;
$$;

-- Objetos fictícios (só metadados, dentro da transação) para os testes de importação.
insert into storage.objects (bucket_id, name, metadata) values
  ('pokemon-species-artwork', 'official-artwork/0025/original-' || repeat('a', 16) || '.png', '{"mimetype":"image/png"}'),
  ('pokemon-species-artwork', 'official-artwork/0025/w320-' || repeat('b', 16) || '.webp', '{"mimetype":"image/webp"}'),
  ('pokemon-species-artwork', 'official-artwork/0025/original-' || repeat('c', 16) || '.png', '{"mimetype":"image/png"}'),
  ('pokemon-species-artwork', 'official-artwork/0025/w320-' || repeat('d', 16) || '.webp', '{"mimetype":"image/webp"}');

-- Referência oficial da espécie 25 lida como owner (vínculo por id, não por número).
select set_config('mmkyu.v6842_ref', (
  select r.external_species_id
    from public.pokemon_species_external_reference r
    join public.pokemon_species s on s.id = r.pokemon_species_id
    join public.asset_source a on a.id = r.asset_source_id and a.code = 'POKEAPI'
   where s.national_dex_number = 25), true);

-- 2. Usuário comum ----------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-4000-8000-000000006842","role":"authenticated"}';
do $$
declare
  v_total integer;
  v_with_art integer;
  v_name text;
  v_rows integer;
begin
  if public.is_admin() then raise exception '6842 FAIL 2: usuário sintético é admin'; end if;

  select count(*), count(artwork_path) into v_total, v_with_art from public.get_pokedex_national_species();
  if v_total <> 1025 or v_with_art <> 0 then raise exception '6842 FAIL 2a: % espécies / % com imagem', v_total, v_with_art; end if;

  select species_name into v_name from public.get_pokedex_national_species('#0025');
  if v_name is distinct from 'Pikachu' then raise exception '6842 FAIL 2b: #0025 -> %', v_name; end if;
  select count(*) into v_rows from public.get_pokedex_national_species('nidoran');
  if v_rows <> 2 then raise exception '6842 FAIL 2c: nidoran -> %', v_rows; end if;
  select count(*) into v_rows from public.get_pokedex_national_species(null, 9);
  if v_rows <> 120 then raise exception '6842 FAIL 2d: Gen IX -> %', v_rows; end if;
  select species_name into v_name from public.get_pokedex_national_species('1025');
  if v_name is distinct from 'Pecharunt' then raise exception '6842 FAIL 2e: 1025 -> %', v_name; end if;

  begin
    perform 1 from public.pokemon_species_artwork limit 1;
    raise exception '6842 FAIL 2f: usuário comum leu a tabela';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.admin_list_pokemon_species_artwork_status();
    raise exception '6842 FAIL 2g: usuário comum listou cobertura';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.admin_record_pokemon_species_artwork_failure(25, 'TEST_FAILURE', 'teste');
    raise exception '6842 FAIL 2h: usuário comum registrou falha';
  exception when insufficient_privilege then null;
  end;
end;
$$;

-- 3. Administrador ----------------------------------------------------------------------
reset role;
select set_config(
  'request.jwt.claims',
  json_build_object('sub', (select id from public.admin_user order by granted_at limit 1), 'role', 'authenticated')::text,
  true
);
set local role authenticated;
do $$
declare
  v_ref text;
  v_res jsonb;
  v_rows integer;
  v_total bigint;
  v_path text;
  v_sha_a text := repeat('a', 16) || repeat('0', 48);
  v_sha_b text := repeat('b', 16) || repeat('0', 48);
  v_sha_c text := repeat('c', 16) || repeat('0', 48);
  v_sha_d text := repeat('d', 16) || repeat('0', 48);
begin
  if not public.is_admin() then raise exception '6842 FAIL 3: sessão de admin não reconhecida'; end if;

  -- Cobertura inicial
  select count(*), max(total_count) into v_rows, v_total from public.admin_list_pokemon_species_artwork_status('PENDING', 1000, 0);
  if v_rows <> 1000 or v_total <> 1025 then raise exception '6842 FAIL 3a: pendentes % / total %', v_rows, v_total; end if;

  -- Falha em espécie sem imagem -> FAILED
  v_res := public.admin_record_pokemon_species_artwork_failure(25, 'DOWNLOAD_TIMEOUT', 'tempo esgotado', 'https://example.test/25.png');
  if v_res->>'status' <> 'FAILED' then raise exception '6842 FAIL 3b: %', v_res; end if;

  v_ref := nullif(current_setting('mmkyu.v6842_ref', true), '');
  if v_ref is null then raise exception '6842 FAIL 3: referência da espécie 25 ausente'; end if;

  -- Vínculo errado
  begin
    perform public.admin_record_pokemon_species_artwork_import(25, '26', '25', 'https://example.test/25.png', now(),
      'official-artwork/0025/original-' || repeat('a', 16) || '.png', 475, 475, 1000, v_sha_a,
      'official-artwork/0025/w320-' || repeat('b', 16) || '.webp', 320, 320, 500, v_sha_b);
    raise exception '6842 FAIL 3c: vínculo errado aceito';
  exception when raise_exception then
    if sqlerrm not like 'SOURCE_SPECIES_MISMATCH%' then raise; end if;
  end;

  -- Caminho de outra espécie
  begin
    perform public.admin_record_pokemon_species_artwork_import(25, v_ref, '25', 'https://example.test/25.png', now(),
      'official-artwork/0026/original-' || repeat('a', 16) || '.png', 475, 475, 1000, v_sha_a,
      'official-artwork/0025/w320-' || repeat('b', 16) || '.webp', 320, 320, 500, v_sha_b);
    raise exception '6842 FAIL 3d: caminho errado aceito';
  exception when raise_exception then
    if sqlerrm not like 'STORAGE_PATH_MISMATCH%' then raise; end if;
  end;

  -- Arquivo inexistente no bucket
  begin
    perform public.admin_record_pokemon_species_artwork_import(25, v_ref, '25', 'https://example.test/25.png', now(),
      'official-artwork/0025/original-' || repeat('e', 16) || '.png', 475, 475, 1000, repeat('e', 16) || repeat('0', 48),
      'official-artwork/0025/w320-' || repeat('b', 16) || '.webp', 320, 320, 500, v_sha_b);
    raise exception '6842 FAIL 3e: objeto ausente aceito';
  exception when raise_exception then
    if sqlerrm not like 'STORAGE_OBJECT_MISSING%' then raise; end if;
  end;

  -- Formato inválido (WebP maior que o original) -> CHECK
  begin
    perform public.admin_record_pokemon_species_artwork_import(25, v_ref, '25', 'https://example.test/25.png', now(),
      'official-artwork/0025/original-' || repeat('a', 16) || '.png', 300, 300, 1000, v_sha_a,
      'official-artwork/0025/w320-' || repeat('b', 16) || '.webp', 320, 320, 500, v_sha_b);
    raise exception '6842 FAIL 3f: dimensões inválidas aceitas';
  exception when check_violation then null;
  end;

  -- Importação válida (recupera a espécie que estava FAILED)
  v_res := public.admin_record_pokemon_species_artwork_import(25, v_ref, '25', 'https://example.test/25.png', now(),
    'official-artwork/0025/original-' || repeat('a', 16) || '.png', 475, 475, 1000, v_sha_a,
    'official-artwork/0025/w320-' || repeat('b', 16) || '.webp', 320, 320, 500, v_sha_b);
  if v_res->>'action' <> 'RECOVERED' then raise exception '6842 FAIL 3g: %', v_res; end if;

  -- Idempotência
  v_res := public.admin_record_pokemon_species_artwork_import(25, v_ref, '25', 'https://example.test/25.png', now(),
    'official-artwork/0025/original-' || repeat('a', 16) || '.png', 475, 475, 1000, v_sha_a,
    'official-artwork/0025/w320-' || repeat('b', 16) || '.webp', 320, 320, 500, v_sha_b);
  if v_res->>'action' <> 'UNCHANGED' then raise exception '6842 FAIL 3h: %', v_res; end if;

  -- Falha posterior não derruba a imagem válida
  v_res := public.admin_record_pokemon_species_artwork_failure(25, 'DOWNLOAD_TIMEOUT', 'tempo esgotado');
  if (v_res->>'image_preserved')::boolean is not true then raise exception '6842 FAIL 3i: %', v_res; end if;
  select display_storage_path into v_path from public.admin_list_pokemon_species_artwork_status('IMPORTED', 10, 0) where national_dex_number = 25;
  if v_path is distinct from 'official-artwork/0025/w320-' || repeat('b', 16) || '.webp' then
    raise exception '6842 FAIL 3j: imagem válida alterada pela falha (%)', v_path;
  end if;

  -- Troca de imagem (arquivos novos, registro trocado)
  v_res := public.admin_record_pokemon_species_artwork_import(25, v_ref, '25', 'https://example.test/25.png', now(),
    'official-artwork/0025/original-' || repeat('c', 16) || '.png', 475, 475, 1100, v_sha_c,
    'official-artwork/0025/w320-' || repeat('d', 16) || '.webp', 320, 320, 600, v_sha_d);
  if v_res->>'action' <> 'REPLACED' then raise exception '6842 FAIL 3k: %', v_res; end if;

  select count(*) into v_rows from public.admin_list_pokemon_species_artwork_status('IMPORTED', 10, 0);
  if v_rows <> 1 then raise exception '6842 FAIL 3l: importadas = %', v_rows; end if;
end;
$$;

-- 4. Colecionador vê só o caminho da imagem importada ------------------------------------
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-4000-8000-000000006842","role":"authenticated"}';
do $$
declare
  v_path text;
  v_with_art integer;
begin
  select artwork_path into v_path from public.get_pokedex_national_species('25');
  if v_path is distinct from 'official-artwork/0025/w320-' || repeat('d', 16) || '.webp' then
    raise exception '6842 FAIL 4a: artwork_path = %', v_path;
  end if;
  select count(artwork_path) into v_with_art from public.get_pokedex_national_species();
  if v_with_art <> 1 then raise exception '6842 FAIL 4b: % espécies com imagem', v_with_art; end if;
end;
$$;

-- 5. anon --------------------------------------------------------------------------------
reset role;
set local role anon;
do $$
begin
  perform public.admin_list_pokemon_species_artwork_status();
  raise exception '6842 FAIL 5a: anon listou cobertura';
exception when insufficient_privilege then null;
end;
$$;
do $$
begin
  perform public.get_pokedex_national_species();
  raise exception '6842 FAIL 5b: anon leu a Pokédex';
exception when insufficient_privilege then null;
end;
$$;

-- 6. CHECKs diretos (como owner) ----------------------------------------------------------
reset role;
do $$
declare
  v_species uuid := (select id from public.pokemon_species where national_dex_number = 1);
  v_source uuid := (select id from public.asset_source where code = 'POKEAPI');
begin
  begin
    insert into public.pokemon_species_artwork (pokemon_species_id, asset_source_id, status)
    values (v_species, v_source, 'IMPORTED');
    raise exception '6842 FAIL 6a: IMPORTED incompleto aceito';
  exception when check_violation then null;
  end;
  begin
    insert into public.pokemon_species_artwork (pokemon_species_id, asset_source_id, status, last_error_code)
    values (v_species, v_source, 'PENDENTE', 'X');
    raise exception '6842 FAIL 6b: status inválido aceito';
  exception when check_violation then null;
  end;
  begin
    insert into public.pokemon_species_artwork (pokemon_species_id, asset_source_id, status)
    values (v_species, v_source, 'FAILED');
    raise exception '6842 FAIL 6c: FAILED sem erro aceito';
  exception when check_violation then null;
  end;
end;
$$;

select '6842 PASS' as resultado;

rollback;
