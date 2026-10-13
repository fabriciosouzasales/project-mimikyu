-- Query 6847 | Validação independente da publicação do piloto editorial pt-BR (Query 6136)
--
-- Somente leitura (BEGIN/ROLLBACK). Executar depois da 6136.
-- Confere, contra os hashes do pilot-pt-BR.json (revisão 4) e a linha de base do LIVE de
-- 2026-10-12 (antes do piloto):
--   1. exatamente 20 linhas MMKYU_EDITORIAL no total, todas das 10 espécies do piloto;
--   2. uma GENUS e uma FLAVOR por espécie, pt-BR, rights MMKYU_EDITORIAL, sem proveniência de fonte;
--   3. conteúdo idêntico ao aprovado (md5 por texto);
--   4. textos oficiais preservados: 2.050 linhas SOURCE en, hash do conjunto igual à linha de base;
--   5. leitura pública: a ficha pt-BR devolve o editorial (não oficial) e a leitura en devolve o
--      texto oficial com a versão de origem — sessão autenticada simulada, sem gravação.
-- Resultado esperado: NOTICE "6847 PASS (...)"; qualquer divergência: "6847 FAIL: ...".

begin;

do $val$
declare
  v_pilot constant integer[] := array[1, 25, 150, 201, 493, 649, 721, 905, 906, 1025];
  v_source_baseline_count constant integer := 2050;
  v_source_baseline_md5 constant text := 'ca8e9c87244160063971bd1a9f808b78';
  v_n integer;
  v_md5 text;
  v_user uuid;
  v_r record;
begin
  -- 1. Contagem e escopo
  select count(*) into v_n from public.pokemon_species_text where origin = 'MMKYU_EDITORIAL';
  if v_n <> 20 then raise exception '6847 FAIL: % linhas editoriais no total, esperado 20', v_n; end if;

  select count(*) into v_n
    from public.pokemon_species_text st join public.pokemon_species s on s.id = st.pokemon_species_id
   where st.origin = 'MMKYU_EDITORIAL' and not (s.national_dex_number = any (v_pilot));
  if v_n <> 0 then raise exception '6847 FAIL: % linhas editoriais fora do piloto', v_n; end if;

  -- 2. Forma
  select count(*) into v_n
    from public.pokemon_species_text st
   where st.origin = 'MMKYU_EDITORIAL'
     and (st.language_code <> 'pt-BR' or st.rights_status <> 'MMKYU_EDITORIAL'
          or st.asset_source_id is not null or st.source_version is not null or st.retrieved_at is not null);
  if v_n <> 0 then raise exception '6847 FAIL: % linhas editoriais com idioma/direitos/proveniência incorretos', v_n; end if;

  select count(*) into v_n from (
    select s.national_dex_number
      from public.pokemon_species_text st join public.pokemon_species s on s.id = st.pokemon_species_id
     where st.origin = 'MMKYU_EDITORIAL'
     group by s.national_dex_number
    having count(*) filter (where st.text_kind = 'GENUS') = 1 and count(*) filter (where st.text_kind = 'FLAVOR') = 1
  ) ok;
  if v_n <> 10 then raise exception '6847 FAIL: % espécies com GENUS + FLAVOR editoriais, esperado 10', v_n; end if;

  -- 3. Conteúdo aprovado
  select count(*) into v_n
    from (values
    (   1, 'GENUS',  'd106d48db7cd05b7318ef213e29ea191'),
    (   1, 'FLAVOR', '6fa190f58d6d7c9d181dbdf9fa8b029f'),
    (  25, 'GENUS',  'aeebd93bae1f0ffe1fd5d851a5c69f7d'),
    (  25, 'FLAVOR', 'ff535631f50d1f62ad41e6097fc4eb6e'),
    ( 150, 'GENUS',  '59c850213022ef77e8c3fee5abaab90e'),
    ( 150, 'FLAVOR', '77a4292d419ffa4e7675a9f638af9c72'),
    ( 201, 'GENUS',  '602a3977a95fcc0d5599e3685ece02a1'),
    ( 201, 'FLAVOR', '1e5fae200a90906ea79405ad638901ab'),
    ( 493, 'GENUS',  '4b5972befe205497fcc1223c6e19c713'),
    ( 493, 'FLAVOR', '2306a6e97fac096a4146f0eeddb03362'),
    ( 649, 'GENUS',  '15eb9c3d28c0ed3243f9f9d37249b334'),
    ( 649, 'FLAVOR', '3c39ddbe6f6ca53ef61f4b384c440d81'),
    ( 721, 'GENUS',  '3485c9988307a1efcba84ac1314c2a0b'),
    ( 721, 'FLAVOR', '3aec691ce234c1c25e55b0421cef99e3'),
    ( 905, 'GENUS',  '903cdcab9a504b1c836323397c451f24'),
    ( 905, 'FLAVOR', '2961132bc5248df54ff10d3235cc3cb0'),
    ( 906, 'GENUS',  '3d4ed43e6b1573197d5a106253b15a3c'),
    ( 906, 'FLAVOR', 'c1bab719d860c5afb06cc003b54ba08f'),
    (1025, 'GENUS',  'c790cbbfb620b3210bae0eb51ec6d1fd'),
    (1025, 'FLAVOR', '4cf656088f060510dd78da734f1db26a')
    ) e(national_dex_number, text_kind, content_md5)
    join public.pokemon_species s on s.national_dex_number = e.national_dex_number
    left join public.pokemon_species_text st
      on st.pokemon_species_id = s.id and st.text_kind = e.text_kind
     and st.origin = 'MMKYU_EDITORIAL' and st.language_code = 'pt-BR'
   where st.id is null or md5(st.content) <> e.content_md5;
  if v_n <> 0 then raise exception '6847 FAIL: % textos divergentes do aprovado', v_n; end if;

  -- 4. Textos oficiais preservados
  select count(*), md5(string_agg(st.pokemon_species_id::text || '|' || st.text_kind || '|' || st.language_code || '|' || coalesce(st.source_version, '') || '|' || st.content || '|' || st.rights_status || '|' || coalesce(st.asset_source_id::text, '') || '|' || coalesce((st.retrieved_at at time zone 'UTC')::text, ''), E'\n' order by st.pokemon_species_id, st.text_kind, st.language_code))
    into v_n, v_md5
    from public.pokemon_species_text st where st.origin = 'SOURCE';
  if v_n <> v_source_baseline_count or v_md5 <> v_source_baseline_md5 then
    raise exception '6847 FAIL: textos oficiais alterados (% linhas, hash %)', v_n, v_md5;
  end if;

  -- 5. Leitura pública (sessão autenticada simulada; nada é gravado)
  select id into v_user from auth.users order by created_at limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', v_user::text, 'role', 'authenticated')::text, true);

  select * into v_r from public.get_pokedex_species_detail(1, 'pt-BR');
  if v_r.description_language <> 'pt-BR' or v_r.description_is_official
     or v_r.genus_language <> 'pt-BR' or v_r.genus_is_official or v_r.genus <> 'Pokémon Semente' then
    raise exception '6847 FAIL: ficha pt-BR de #1 não devolve o editorial';
  end if;
  select * into v_r from public.get_pokedex_species_detail(1, 'en');
  if v_r.description_language <> 'en' or not v_r.description_is_official or v_r.description_source_version is null then
    raise exception '6847 FAIL: leitura en de #1 não devolve o texto oficial com versão';
  end if;
  select * into v_r from public.get_pokedex_species_detail(4, 'pt-BR');
  if v_r.description_language <> 'en' or not v_r.description_is_official then
    raise exception '6847 FAIL: espécie fora do piloto (#4) deixou de mostrar o oficial en';
  end if;

  raise notice '6847 PASS (editorial: 20 linhas / 10 espécies; SOURCE: % linhas preservadas)', v_source_baseline_count;
end
$val$;

rollback;
