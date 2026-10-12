-- Query 6844 v1.1 | PROPOSTA — validação da Query 6133 (Pokédex P3a — enriquecimento)
--
-- v1.1 (2026-10-12, ensaio): a v1.0 usava retrieved_at de fixture no futuro (2026-10-13),
-- corretamente recusado pela 6133 (PAYLOAD_INVALID: retrieved_at no futuro). Defeito do
-- fixture, não da 6133: datas de fixture passaram para 2026-10-01/02. Nenhuma asserção mudou.
--
-- Objetivo
-- Provar, depois de executar a 6133:
--   1. estrutura, RLS, privilégios, vocabulário (18 tipos) e contrato da galeria intacto;
--   2. colecionador: lê a ficha só pela função, sem tabelas nem funções admin; anon nada;
--   3. admin: cobertura inicial (1.025 PENDING), gravação, idempotência (UNCHANGED, inclusive
--      com retrieved_at diferente), atualização, ordem dos tipos, rótulos pt-BR, unidades;
--   4. recusas: vínculo oficial errado, tipo desconhecido/repetido/excesso, texto vazio,
--      idioma inválido, versão ausente/indevida, medida inválida, forma de outra espécie;
--   5. falha preserva perfil válido; falha em espécie nova = FAILED sem dados;
--   6. idioma: pt-BR editorial (MMKYU) vence en oficial e volta marcado como não oficial;
--      reimportação não apaga texto editorial;
--   7. espécies, imagens e galeria nacional intactas.
-- Tudo em BEGIN/ROLLBACK. Resultado esperado: linha final "6844 PASS".

begin;

-- 0. Preparação como owner (tabelas fechadas para authenticated) -------------------------
select set_config('mmkyu.v6844_ref25', (
  select r.external_species_id from public.pokemon_species_external_reference r
    join public.pokemon_species s on s.id = r.pokemon_species_id
    join public.asset_source a on a.id = r.asset_source_id and a.code = 'POKEAPI'
   where s.national_dex_number = 25 and r.is_active), true);
select set_config('mmkyu.v6844_ref1', (
  select r.external_species_id from public.pokemon_species_external_reference r
    join public.pokemon_species s on s.id = r.pokemon_species_id
    join public.asset_source a on a.id = r.asset_source_id and a.code = 'POKEAPI'
   where s.national_dex_number = 1 and r.is_active), true);
select set_config('mmkyu.v6844_ref26', (
  select r.external_species_id from public.pokemon_species_external_reference r
    join public.pokemon_species s on s.id = r.pokemon_species_id
    join public.asset_source a on a.id = r.asset_source_id and a.code = 'POKEAPI'
   where s.national_dex_number = 26 and r.is_active), true);
select set_config('mmkyu.v6844_admin', (select id::text from public.admin_user order by granted_at limit 1), true);
select set_config('mmkyu.v6844_art', (select count(*)::text from public.pokemon_species_artwork where status = 'IMPORTED'), true);

-- 1. Estrutura e privilégios ------------------------------------------------------------
do $$
declare
  v_count integer;
  v_table text;
begin
  foreach v_table in array array['pokemon_type', 'pokemon_form', 'pokemon_form_type',
                                 'pokemon_species_profile', 'pokemon_species_text'] loop
    if not (select relrowsecurity from pg_class where oid = ('public.' || v_table)::regclass) then
      raise exception '6844 FAIL 1a: RLS desligada em %', v_table;
    end if;
    if has_table_privilege('anon', 'public.' || v_table, 'select')
       or has_table_privilege('authenticated', 'public.' || v_table, 'select')
       or has_table_privilege('authenticated', 'public.' || v_table, 'insert')
       or has_table_privilege('authenticated', 'public.' || v_table, 'update')
       or has_table_privilege('authenticated', 'public.' || v_table, 'delete') then
      raise exception '6844 FAIL 1b: % acessível diretamente', v_table;
    end if;
    if exists (select 1 from pg_policies where schemaname = 'public' and tablename = v_table) then
      raise exception '6844 FAIL 1c: policy inesperada em %', v_table;
    end if;
  end loop;

  if (select count(*) from public.pokemon_type where is_active) <> 18
     or (select count(*) from public.pokemon_type where labels ->> 'pt-BR' = 'Elétrico' and code = 'ELECTRIC') <> 1
     or (select string_agg(code, ',' order by display_order) from public.pokemon_type)
        <> 'NORMAL,FIGHTING,FLYING,POISON,GROUND,ROCK,BUG,GHOST,STEEL,FIRE,WATER,GRASS,ELECTRIC,PSYCHIC,ICE,DRAGON,DARK,FAIRY' then
    raise exception '6844 FAIL 1d: vocabulário de tipos divergente';
  end if;
  if (select count(*) from public.pokemon_form) + (select count(*) from public.pokemon_form_type)
     + (select count(*) from public.pokemon_species_profile) + (select count(*) from public.pokemon_species_text) <> 0 then
    raise exception '6844 FAIL 1e: tabelas de dados deveriam nascer vazias';
  end if;

  select count(*) into v_count
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('admin_record_pokemon_species_profile', 'admin_record_pokemon_species_profile_failure',
                       'admin_list_pokemon_species_profile_status', 'get_pokedex_species_detail')
     and p.prosecdef and p.proconfig = array['search_path=""']
     and not has_function_privilege('anon', p.oid, 'execute')
     and has_function_privilege('authenticated', p.oid, 'execute');
  if v_count <> 4 then raise exception '6844 FAIL 1f: funções endurecidas = %', v_count; end if;

  if pg_get_function_result('public.get_pokedex_national_species(text, integer)'::regprocedure)
     <> 'TABLE(national_dex_number integer, species_name text, generation_code text, generation_ordinal integer, artwork_path text)' then
    raise exception '6844 FAIL 1g: contrato da galeria nacional alterado';
  end if;
  if (select count(*) from public.pokemon_species where is_active) <> 1025 then
    raise exception '6844 FAIL 1h: espécies alteradas';
  end if;
  if current_setting('mmkyu.v6844_ref25', true) is null or current_setting('mmkyu.v6844_admin', true) is null then
    raise exception '6844 FAIL 1i: fixture sem referência oficial ou admin';
  end if;
end;
$$;

-- 2. Usuário comum ----------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-4000-8000-000000006844","role":"authenticated"}';
do $$
declare
  v_row record;
  v_rows integer;
begin
  if public.is_admin() then raise exception '6844 FAIL 2: usuário sintético é admin'; end if;

  select * into v_row from public.get_pokedex_species_detail(25);
  if v_row.species_name is distinct from 'Pikachu' or v_row.profile_available is distinct from false
     or v_row.primary_type_code is not null or v_row.height_m is not null or v_row.generation_ordinal <> 1
     or v_row.artwork_path is null then
    raise exception '6844 FAIL 2a: ficha #25 antes da importação = %', row_to_json(v_row);
  end if;
  select count(*) into v_rows from public.get_pokedex_species_detail(99999);
  if v_rows <> 0 then raise exception '6844 FAIL 2b: espécie inexistente devolveu linha'; end if;
  begin
    perform 1 from public.get_pokedex_species_detail(25, 'pt_br');
    raise exception '6844 FAIL 2c: idioma inválido aceito';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform 1 from public.pokemon_species_profile limit 1;
    raise exception '6844 FAIL 2d: usuário comum leu o perfil';
  exception when insufficient_privilege then null;
  end;
  begin
    perform 1 from public.pokemon_type limit 1;
    raise exception '6844 FAIL 2e: usuário comum leu pokemon_type';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.admin_list_pokemon_species_profile_status();
    raise exception '6844 FAIL 2f: usuário comum listou cobertura';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.admin_record_pokemon_species_profile(25, '{}'::jsonb);
    raise exception '6844 FAIL 2g: usuário comum gravou perfil';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.admin_record_pokemon_species_profile_failure(25, 'TEST_FAILURE', 'teste');
    raise exception '6844 FAIL 2h: usuário comum registrou falha';
  exception when insufficient_privilege then null;
  end;
end;
$$;

-- 3. Anônimo ----------------------------------------------------------------------------
reset role;
set local role anon;
do $$
begin
  begin
    perform 1 from public.get_pokedex_species_detail(25);
    raise exception '6844 FAIL 3: anon leu a ficha';
  exception when insufficient_privilege then null;
  end;
end;
$$;

-- 4. Administrador ----------------------------------------------------------------------
reset role;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('mmkyu.v6844_admin'), 'role', 'authenticated')::text, true);
set local role authenticated;
do $$
declare
  v_base jsonb;
  v_res jsonb;
  v_row record;
  v_count integer;
  v_state text;
begin
  if not public.is_admin() then raise exception '6844 FAIL 4: fixture admin sem papel'; end if;

  select count(*) into v_count from public.admin_list_pokemon_species_profile_status('PENDING', 1000, 0);
  if v_count <> 1000 or (select max(total_count) from public.admin_list_pokemon_species_profile_status('PENDING', 1, 0)) <> 1025 then
    raise exception '6844 FAIL 4a: cobertura inicial (esperado 1.025 PENDING)';
  end if;

  v_base := jsonb_build_object(
    'source_species_id', current_setting('mmkyu.v6844_ref25'),
    'source_pokemon_id', '25', 'source_pokemon_name', 'pikachu',
    'source_url', 'https://pokeapi.co/api/v2/pokemon-species/25/',
    'retrieved_at', '2026-10-01T12:00:00Z',
    'is_legendary', false, 'is_mythical', false, 'is_baby', false,
    'height_dm', 4, 'weight_hg', 60,
    'types', jsonb_build_array('ELECTRIC'),
    'texts', jsonb_build_array(
      jsonb_build_object('kind', 'GENUS', 'language', 'en', 'content', 'Mouse Pokémon'),
      jsonb_build_object('kind', 'FLAVOR', 'language', 'en', 'content', 'When Pikachu meet, they touch tails.', 'source_version', 'shield')));

  -- 4b. inserção, idempotência e atualização
  v_res := public.admin_record_pokemon_species_profile(25, v_base);
  if v_res ->> 'action' <> 'INSERTED' then raise exception '6844 FAIL 4b: %', v_res; end if;
  v_res := public.admin_record_pokemon_species_profile(25, v_base);
  if v_res ->> 'action' <> 'UNCHANGED' then raise exception '6844 FAIL 4c: %', v_res; end if;
  v_res := public.admin_record_pokemon_species_profile(25, v_base || '{"retrieved_at":"2026-10-02T09:00:00Z"}');
  if v_res ->> 'action' <> 'UNCHANGED' then raise exception '6844 FAIL 4d (só data mudou): %', v_res; end if;
  v_res := public.admin_record_pokemon_species_profile(25, v_base || '{"weight_hg":61}');
  if v_res ->> 'action' <> 'UPDATED' then raise exception '6844 FAIL 4e: %', v_res; end if;

  select * into v_row from public.get_pokedex_species_detail(25);
  if v_row.profile_available is not true or v_row.primary_type_code <> 'ELECTRIC'
     or v_row.primary_type_label <> 'Elétrico' or v_row.secondary_type_code is not null
     or v_row.height_m <> 0.4 or v_row.weight_kg <> 6.1
     or v_row.genus <> 'Mouse Pokémon' or v_row.genus_language <> 'en' or v_row.genus_is_official is not true
     or v_row.description_language <> 'en' or v_row.description_source_version <> 'shield'
     or v_row.is_legendary is not false or v_row.artwork_path is null then
    raise exception '6844 FAIL 4f: ficha #25 = %', row_to_json(v_row);
  end if;
  select * into v_row from public.get_pokedex_species_detail(25, 'en');
  if v_row.primary_type_label <> 'Electric' then raise exception '6844 FAIL 4g: rótulo en = %', v_row.primary_type_label; end if;

  -- 4h. dois tipos: ordem oficial preservada
  v_res := public.admin_record_pokemon_species_profile(1, jsonb_build_object(
    'source_species_id', current_setting('mmkyu.v6844_ref1'),
    'source_pokemon_id', '1', 'source_pokemon_name', 'bulbasaur',
    'source_url', 'https://pokeapi.co/api/v2/pokemon-species/1/', 'retrieved_at', '2026-10-01T12:00:00Z',
    'is_legendary', false, 'is_mythical', false, 'is_baby', false, 'height_dm', 7, 'weight_hg', 69,
    'types', jsonb_build_array('GRASS', 'POISON'), 'texts', '[]'::jsonb));
  select * into v_row from public.get_pokedex_species_detail(1);
  if v_row.primary_type_code <> 'GRASS' or v_row.secondary_type_code <> 'POISON' or v_row.secondary_type_label <> 'Venenoso'
     or v_row.genus is not null or v_row.description is not null then
    raise exception '6844 FAIL 4h: ficha #1 = %', row_to_json(v_row);
  end if;

  -- 4i. recusas
  begin perform public.admin_record_pokemon_species_profile(25, v_base || jsonb_build_object('source_species_id', current_setting('mmkyu.v6844_ref26')));
    raise exception '6844 FAIL 4i1: vínculo oficial errado aceito';
  exception when raise_exception then
    get stacked diagnostics v_state = message_text;
    if v_state not like 'SOURCE_SPECIES_MISMATCH%' then raise exception '6844 FAIL 4i1: %', v_state; end if;
  end;
  begin perform public.admin_record_pokemon_species_profile(25, v_base || '{"types":["SHADOW"]}');
    raise exception '6844 FAIL 4i2: tipo desconhecido aceito';
  exception when raise_exception then
    get stacked diagnostics v_state = message_text;
    if v_state not like 'TYPE_UNKNOWN%' then raise exception '6844 FAIL 4i2: %', v_state; end if;
  end;
  begin perform public.admin_record_pokemon_species_profile(25, v_base || '{"types":["FIRE","FIRE"]}');
    raise exception '6844 FAIL 4i3: tipo repetido aceito';
  exception when invalid_parameter_value then null; end;
  begin perform public.admin_record_pokemon_species_profile(25, v_base || '{"types":["FIRE","WATER","GRASS"]}');
    raise exception '6844 FAIL 4i4: três tipos aceitos';
  exception when invalid_parameter_value then null; end;
  begin perform public.admin_record_pokemon_species_profile(25, v_base || '{"types":[]}');
    raise exception '6844 FAIL 4i5: zero tipos aceito';
  exception when invalid_parameter_value then null; end;
  begin perform public.admin_record_pokemon_species_profile(25, v_base || '{"texts":[{"kind":"GENUS","language":"en","content":"  "}]}');
    raise exception '6844 FAIL 4i6: texto vazio aceito';
  exception when invalid_parameter_value then null; end;
  begin perform public.admin_record_pokemon_species_profile(25, v_base || '{"texts":[{"kind":"GENUS","language":"pt_br","content":"x"}]}');
    raise exception '6844 FAIL 4i7: idioma inválido aceito';
  exception when invalid_parameter_value then null; end;
  begin perform public.admin_record_pokemon_species_profile(25, v_base || '{"texts":[{"kind":"FLAVOR","language":"en","content":"x"}]}');
    raise exception '6844 FAIL 4i8: descrição sem versão aceita';
  exception when invalid_parameter_value then null; end;
  begin perform public.admin_record_pokemon_species_profile(25, v_base || '{"texts":[{"kind":"GENUS","language":"en","content":"x","source_version":"red"}]}');
    raise exception '6844 FAIL 4i9: classificação com versão aceita';
  exception when invalid_parameter_value then null; end;
  begin perform public.admin_record_pokemon_species_profile(25, v_base || '{"texts":[{"kind":"GENUS","language":"en","content":"a"},{"kind":"GENUS","language":"en","content":"b"}]}');
    raise exception '6844 FAIL 4i10: texto repetido aceito';
  exception when invalid_parameter_value then null; end;
  begin perform public.admin_record_pokemon_species_profile(25, v_base || '{"height_dm":0}');
    raise exception '6844 FAIL 4i11: altura zero aceita';
  exception when invalid_parameter_value then null; end;
  begin perform public.admin_record_pokemon_species_profile(25, v_base - 'is_baby');
    raise exception '6844 FAIL 4i12: indicador ausente aceito';
  exception when invalid_parameter_value then null; end;
  -- forma padrão de outra espécie (mesmo pokemon id) não pode ser reaproveitada
  begin perform public.admin_record_pokemon_species_profile(26, v_base || jsonb_build_object(
      'source_species_id', current_setting('mmkyu.v6844_ref26'),
      'source_url', 'https://pokeapi.co/api/v2/pokemon-species/26/'));
    raise exception '6844 FAIL 4i13: pokemon id de outra espécie aceito';
  exception when unique_violation then null; end;

  select * into v_row from public.get_pokedex_species_detail(25);
  if v_row.weight_kg <> 6.1 or v_row.primary_type_code <> 'ELECTRIC' then
    raise exception '6844 FAIL 4j: recusa alterou a ficha';
  end if;

  -- 4k. falhas
  v_res := public.admin_record_pokemon_species_profile_failure(25, 'SOURCE_UNAVAILABLE', 'teste');
  if (v_res ->> 'profile_preserved')::boolean is not true then raise exception '6844 FAIL 4k1: %', v_res; end if;
  select * into v_row from public.get_pokedex_species_detail(25);
  if v_row.profile_available is not true or v_row.weight_kg <> 6.1 then raise exception '6844 FAIL 4k2: falha apagou perfil'; end if;
  v_res := public.admin_record_pokemon_species_profile_failure(4, 'SOURCE_NOT_FOUND', 'teste');
  if v_res ->> 'status' <> 'FAILED' then raise exception '6844 FAIL 4k3: %', v_res; end if;
  select * into v_row from public.get_pokedex_species_detail(4);
  if v_row.profile_available is not false or v_row.primary_type_code is not null then raise exception '6844 FAIL 4k4'; end if;
  select count(*) into v_count from public.admin_list_pokemon_species_profile_status('FAILED');
  if v_count <> 1 then raise exception '6844 FAIL 4k5: FAILED = %', v_count; end if;
  select count(*) into v_count from public.admin_list_pokemon_species_profile_status('IMPORTED');
  if v_count <> 2 then raise exception '6844 FAIL 4k6: IMPORTED = %', v_count; end if;
end;
$$;

-- 5. Tradução editorial MMKYU (escrita direta como owner: ainda não há tela/RPC editorial)
reset role;
insert into public.pokemon_species_text (pokemon_species_id, text_kind, language_code, origin, content, rights_status)
select s.id, 'GENUS', 'pt-BR', 'MMKYU_EDITORIAL', 'Pokémon Rato', 'MMKYU_EDITORIAL'
  from public.pokemon_species s where s.national_dex_number = 25;
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('mmkyu.v6844_admin'), 'role', 'authenticated')::text, true);
set local role authenticated;
do $$
declare
  v_row record;
  v_res jsonb;
begin
  select * into v_row from public.get_pokedex_species_detail(25);
  if v_row.genus <> 'Pokémon Rato' or v_row.genus_language <> 'pt-BR' or v_row.genus_is_official is not false
     or v_row.description_language <> 'en' then
    raise exception '6844 FAIL 5a: preferência pt-BR = %', row_to_json(v_row);
  end if;
  select * into v_row from public.get_pokedex_species_detail(25, 'en');
  if v_row.genus <> 'Mouse Pokémon' or v_row.genus_is_official is not true then
    raise exception '6844 FAIL 5b: pedido en = %', row_to_json(v_row);
  end if;
  -- reimportação com conteúdo novo não apaga o editorial
  v_res := public.admin_record_pokemon_species_profile(25, jsonb_build_object(
    'source_species_id', current_setting('mmkyu.v6844_ref25'),
    'source_pokemon_id', '25', 'source_pokemon_name', 'pikachu',
    'source_url', 'https://pokeapi.co/api/v2/pokemon-species/25/', 'retrieved_at', '2026-10-01T12:00:00Z',
    'is_legendary', false, 'is_mythical', false, 'is_baby', false, 'height_dm', 4, 'weight_hg', 60,
    'types', jsonb_build_array('ELECTRIC'), 'texts', '[]'::jsonb));
  if v_res ->> 'action' <> 'UPDATED' then raise exception '6844 FAIL 5c: %', v_res; end if;
  select * into v_row from public.get_pokedex_species_detail(25);
  if v_row.genus <> 'Pokémon Rato' or v_row.description is not null then
    raise exception '6844 FAIL 5d: editorial/SOURCE após reimportação = %', row_to_json(v_row);
  end if;
end;
$$;

-- 6. Preservação --------------------------------------------------------------------------
reset role;
do $$
begin
  if (select count(*) from public.pokemon_species where is_active) <> 1025
     or (select count(*)::text from public.pokemon_species_artwork where status = 'IMPORTED') <> current_setting('mmkyu.v6844_art') then
    raise exception '6844 FAIL 6: espécies ou imagens alteradas';
  end if;
end;
$$;

select '6844 PASS' as resultado;

rollback;
