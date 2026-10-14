-- Query 6848 | Validação independente da publicação do P3e-lote-01 (Query 6137)
--
-- Somente leitura (BEGIN/ROLLBACK). Executar depois da 6137.
-- Gerado por scripts/editorial/generate-editorial-lot-sql.ts — NÃO EDITAR À MÃO; regerar a partir do JSON.
-- Lote: P3e-lote-01 · revisão 11 · guia 0.2 · sha256 do JSON 73ab17d3fbb634b504e86854450cf0f89ccfa0fe32d67c6d7913d8f49fddf001
-- Publicado preservado: database/proposals/2026-10-12-pokedex-p3d-editorial-ptbr/pilot-pt-BR.json · sha256 4d2edea2f7848abb5193f6a27e8ba205eda4921dab9362049dfcac9fa5045115
--
-- Confere:
--   1. total editorial = 120 linhas / 60 espécies (100 do lote + 20 publicados antes);
--   2. forma: pt-BR, rights MMKYU_EDITORIAL, sem proveniência de fonte; uma GENUS e uma FLAVOR por espécie;
--   3. md5 dos 100 textos do lote iguais aos aprovados no JSON;
--   4. md5 dos 20 registros publicados antes iguais aos versionados (preservação do piloto);
--   5. SOURCE: 2050 linhas com o hash de linha de base;
--   6. leitura da ficha (sessão autenticada simulada, nada gravado): espécie do lote em pt-BR devolve o
--      editorial; a mesma em en devolve o oficial com versão; piloto continua editorial; espécie fora de
--      ambos continua com o oficial en.
-- Resultado esperado: NOTICE "6848 PASS (...)"; qualquer divergência: "6848 FAIL: ...".

begin;

do $val$
declare
  v_lot constant integer[] := array[4, 6, 7, 39, 52, 54, 94, 133, 143, 151, 155, 175, 197, 212, 248, 249, 257, 282, 359, 382, 384, 385, 393, 405, 445, 448, 483, 491, 494, 495, 530, 609, 643, 658, 681, 700, 701, 716, 722, 745, 778, 791, 823, 873, 887, 888, 908, 959, 998, 1000];
  v_published constant integer[] := array[1, 25, 150, 201, 493, 649, 721, 905, 906, 1025];
  v_source_baseline_count constant integer := 2050;
  v_source_baseline_md5 constant text := 'ca8e9c87244160063971bd1a9f808b78';
  v_n integer;
  v_md5 text;
  v_user uuid;
  v_r record;
begin
  -- 1. Contagem e escopo
  select count(*) into v_n from public.pokemon_species_text where origin = 'MMKYU_EDITORIAL';
  if v_n <> 120 then raise exception '6848 FAIL: % linhas editoriais no total, esperado 120', v_n; end if;

  select count(*) into v_n
    from public.pokemon_species_text st join public.pokemon_species s on s.id = st.pokemon_species_id
   where st.origin = 'MMKYU_EDITORIAL' and not (s.national_dex_number = any (v_lot || v_published));
  if v_n <> 0 then raise exception '6848 FAIL: % linhas editoriais fora do lote e dos publicados', v_n; end if;

  -- 2. Forma
  select count(*) into v_n
    from public.pokemon_species_text st
   where st.origin = 'MMKYU_EDITORIAL'
     and (st.language_code <> 'pt-BR' or st.rights_status <> 'MMKYU_EDITORIAL'
          or st.asset_source_id is not null or st.source_version is not null or st.retrieved_at is not null);
  if v_n <> 0 then raise exception '6848 FAIL: % linhas editoriais com idioma/direitos/proveniência incorretos', v_n; end if;

  select count(*) into v_n from (
    select s.national_dex_number
      from public.pokemon_species_text st join public.pokemon_species s on s.id = st.pokemon_species_id
     where st.origin = 'MMKYU_EDITORIAL'
     group by s.national_dex_number
    having count(*) filter (where st.text_kind = 'GENUS') = 1 and count(*) filter (where st.text_kind = 'FLAVOR') = 1
  ) ok;
  if v_n <> 60 then raise exception '6848 FAIL: % espécies com GENUS + FLAVOR editoriais, esperado 60', v_n; end if;

  -- 3. Conteúdo do lote
  select count(*) into v_n
    from (values
    (   4, 'GENUS',  'b24a7e70e2d533ce4eef92e3c3dc1a31'),
    (   4, 'FLAVOR', '343335b22fdd573894634e9e19eb0557'),
    (   6, 'GENUS',  '9f92472c0938112d9d44f849651ce1bd'),
    (   6, 'FLAVOR', '9743cae699f8a3ae3ef23fdcf73a2442'),
    (   7, 'GENUS',  '33407a53a4904f248cc7e8b01cca01f9'),
    (   7, 'FLAVOR', '5b112eade7decef9ecbf35c1d8012127'),
    (  39, 'GENUS',  '2e32f89c3ee9b7d452ab45405054edcf'),
    (  39, 'FLAVOR', '532b3cca9c2aa60d7ea3a54e28cd5b5c'),
    (  52, 'GENUS',  '309165673409905f16cf135cb3ade0fa'),
    (  52, 'FLAVOR', '64470b6b27a745546826a812de143479'),
    (  54, 'GENUS',  '5e4beb323ec546b053ece35cad31fe77'),
    (  54, 'FLAVOR', '533dd3ec252fb9854aba6083835b8a14'),
    (  94, 'GENUS',  '58a039a54d455f2d5dd3e0348a40dcfc'),
    (  94, 'FLAVOR', '830c01f7f5b764e8274369299b3f5c97'),
    ( 133, 'GENUS',  'a41190d264d3703c2f84dac2868111fc'),
    ( 133, 'FLAVOR', '7eeeae80d9ec1e6190d0a3658ca42c97'),
    ( 143, 'GENUS',  'b44b3c01e5af5be6a5af1cc1108d0ce2'),
    ( 143, 'FLAVOR', '61c6f59e35995f73487c5288b95238c1'),
    ( 151, 'GENUS',  '18d8ec6a20b3a3b3288bfa72bf0ce058'),
    ( 151, 'FLAVOR', 'c69bd73a6d87c7709bf0bbc428ddd0f6'),
    ( 155, 'GENUS',  '0245650b1405a4c97af318d9a5e88cba'),
    ( 155, 'FLAVOR', 'a3f4634e0ea6313cc8174c3cb5dfaa3d'),
    ( 175, 'GENUS',  '0f3dc2d6d7063b5060d1afa2a194a2a0'),
    ( 175, 'FLAVOR', '01f3aae0593caef4476048cbfe633bd5'),
    ( 197, 'GENUS',  'a1a4bf3659f9f6585b829fba950fdd5a'),
    ( 197, 'FLAVOR', 'bfcf5738cfe3c4c75b036ef907ece037'),
    ( 212, 'GENUS',  '9f4618b8cc507be88a55f517dc86843b'),
    ( 212, 'FLAVOR', 'cf89ebf61f640f83f54f7ec24bf2ce87'),
    ( 248, 'GENUS',  '3c6dbcff474e09bed96c55ff2c4b49b7'),
    ( 248, 'FLAVOR', '4c8d023f2e23fd1c72c9c528996c20f6'),
    ( 249, 'GENUS',  '3ddcfcadb80e30bc48d5974ce5c52d48'),
    ( 249, 'FLAVOR', 'd48621e41565e76701d805e8560cfccc'),
    ( 257, 'GENUS',  '8b49ff1491b01304d13b468ba7fce892'),
    ( 257, 'FLAVOR', 'c9cb7eb264981b9371586ecdf69ce2fd'),
    ( 282, 'GENUS',  'ffc965bd4092d93d6db22581044f4db3'),
    ( 282, 'FLAVOR', '643000e8d65a84f099f1fc176aa8e79e'),
    ( 359, 'GENUS',  'ac79a97a83e1abb5d28b61badc16efae'),
    ( 359, 'FLAVOR', 'ea4f32d6d1f0a9e50d421a3b6f1ed03c'),
    ( 382, 'GENUS',  '0c307a7fc8d7bdbcf277d78ee6d1215f'),
    ( 382, 'FLAVOR', '37b0a7afa2ec85213627e485e91c23b6'),
    ( 384, 'GENUS',  '28610adb538038f02db36666c2e3747c'),
    ( 384, 'FLAVOR', '274e8bb7e47ced8f09f7b6732d585792'),
    ( 385, 'GENUS',  'f4e99f4a3ff0911c3eff99bc3254bd51'),
    ( 385, 'FLAVOR', 'fb649717e5f546a6c4ac014926aa1916'),
    ( 393, 'GENUS',  '7ae75282e5974a837bce7d55cff14583'),
    ( 393, 'FLAVOR', 'de583feff1e0107bb257ba343f25e2e7'),
    ( 405, 'GENUS',  '2dd4da7ea9a3d0f54d8821bac55f56c3'),
    ( 405, 'FLAVOR', '96b786fa9c3e113fb93919fe12845d80'),
    ( 445, 'GENUS',  '65e96af2db4c2e828f710b9c5b5bbf68'),
    ( 445, 'FLAVOR', '8e635338c33ab41d5357a510071e1a86'),
    ( 448, 'GENUS',  'ec8c96672616044281b3139e97babeb9'),
    ( 448, 'FLAVOR', 'fd55b91c878fa2650fcbb099ff809e46'),
    ( 483, 'GENUS',  '099aabfeece0a97765abeb104dec3751'),
    ( 483, 'FLAVOR', 'cb1196a57b390792bc37ec1dfaccad0f'),
    ( 491, 'GENUS',  'd1a4cf787e901ba0739c9f43ba20afa5'),
    ( 491, 'FLAVOR', 'bcef8b0432a7a340c46753524a7fbc28'),
    ( 494, 'GENUS',  '37b7c9340dd9190ef47e9901991b5854'),
    ( 494, 'FLAVOR', 'bb9e8bca29f51e6c7b4700c199b9afb2'),
    ( 495, 'GENUS',  '956d411657ebceb2a97e3b92508403d2'),
    ( 495, 'FLAVOR', 'bc92067e5d138bcc5f9a51f329438c4a'),
    ( 530, 'GENUS',  '59fe9b288ffedf4fc2d99ec72009da00'),
    ( 530, 'FLAVOR', 'a18609ef2a68a4f2a23ea56a23102a31'),
    ( 609, 'GENUS',  'bcee38e4d822db107c2e0ba2c8402561'),
    ( 609, 'FLAVOR', 'edd85d4421a01b1ca0e05db9584b6ae5'),
    ( 643, 'GENUS',  'a6173c2914a60e8c720c96a3446a8c90'),
    ( 643, 'FLAVOR', '55b64b01ad80d61ed845a6b73295f673'),
    ( 658, 'GENUS',  '6d149b1e0e49a30f275486f2022fe3d0'),
    ( 658, 'FLAVOR', '24be99151c0e78fc2aa080d385de3408'),
    ( 681, 'GENUS',  'e77121d067bbaade6af979456efeb39c'),
    ( 681, 'FLAVOR', '36600ea587ef4b06c0d6093ceeccd493'),
    ( 700, 'GENUS',  'f38e45e87bcfabc84ad4a723e702b321'),
    ( 700, 'FLAVOR', 'b3647b17fb2c06d81ef7508058a024c4'),
    ( 701, 'GENUS',  '2ea6571cf6de05029970c31bd1894935'),
    ( 701, 'FLAVOR', 'd029740e1e4c314cd5bda92207e65b44'),
    ( 716, 'GENUS',  '81899657afbb581ced2b3e2fecaa3558'),
    ( 716, 'FLAVOR', 'a816cfbd6d77e53e5a9ef1ce1aad68a3'),
    ( 722, 'GENUS',  '6c2590752b6922ff943ac37126a95691'),
    ( 722, 'FLAVOR', '8290c277cba180981eb618f0e256bc93'),
    ( 745, 'GENUS',  '551977e57c69e4026c76f4a153e490fc'),
    ( 745, 'FLAVOR', '77395ffa87477f8a48383891ce3d6a65'),
    ( 778, 'GENUS',  '0ba5cb3bb921f34f0d0dbade25cf1cf9'),
    ( 778, 'FLAVOR', '7b14a080a87104f91aed12f0cebe752c'),
    ( 791, 'GENUS',  '3c0f18354040cd55a4ac1772b20aa2d4'),
    ( 791, 'FLAVOR', 'fe7f34a958db027ccc1d851229e174e4'),
    ( 823, 'GENUS',  'cd0b8fa23aa708fb8557a7620cee46e7'),
    ( 823, 'FLAVOR', 'b2bc1c6ec0826cc13848e877f458f063'),
    ( 873, 'GENUS',  '7a5495843c178fdaec192de83b3d3322'),
    ( 873, 'FLAVOR', 'b4b26eddc8eb2e25a08a00c12d0457af'),
    ( 887, 'GENUS',  'b756311878629947da37b18c3681a6a5'),
    ( 887, 'FLAVOR', '4ba35576531137466f3d572cb98add7f'),
    ( 888, 'GENUS',  '97d9b0adce09d3abc724fe0a72147a9e'),
    ( 888, 'FLAVOR', '4b83ce45be82b18cca1cbb39bab94bf4'),
    ( 908, 'GENUS',  '1d6aecc4e311a4a8180f94f13d83852c'),
    ( 908, 'FLAVOR', '430a452996d9d3040ba7abe46ae3ee46'),
    ( 959, 'GENUS',  '0565b9face192bd0f06e1f0ca4f1401f'),
    ( 959, 'FLAVOR', 'b9c6ed4e83f07733c66ec6d17c86d883'),
    ( 998, 'GENUS',  '0d5d2691d133d5ce1ba14eb406a0b512'),
    ( 998, 'FLAVOR', '726023d457038935fcc6a3da363a3697'),
    (1000, 'GENUS',  'fc79b1400553132e6655197e23376a92'),
    (1000, 'FLAVOR', 'cda80f8290b76c9500f9437e7e1a3406')
    ) e(national_dex_number, text_kind, content_md5)
    join public.pokemon_species s on s.national_dex_number = e.national_dex_number
    left join public.pokemon_species_text st
      on st.pokemon_species_id = s.id and st.text_kind = e.text_kind
     and st.origin = 'MMKYU_EDITORIAL' and st.language_code = 'pt-BR'
   where st.id is null or md5(st.content) <> e.content_md5;
  if v_n <> 0 then raise exception '6848 FAIL: % textos do lote divergentes do aprovado', v_n; end if;

  -- 4. Preservação dos publicados antes
  select count(*) into v_n
    from (values
    (   1, 'FLAVOR', '6fa190f58d6d7c9d181dbdf9fa8b029f'),
    (   1, 'GENUS', 'd106d48db7cd05b7318ef213e29ea191'),
    (  25, 'FLAVOR', 'ff535631f50d1f62ad41e6097fc4eb6e'),
    (  25, 'GENUS', 'aeebd93bae1f0ffe1fd5d851a5c69f7d'),
    ( 150, 'FLAVOR', '77a4292d419ffa4e7675a9f638af9c72'),
    ( 150, 'GENUS', '59c850213022ef77e8c3fee5abaab90e'),
    ( 201, 'FLAVOR', '1e5fae200a90906ea79405ad638901ab'),
    ( 201, 'GENUS', '602a3977a95fcc0d5599e3685ece02a1'),
    ( 493, 'FLAVOR', '2306a6e97fac096a4146f0eeddb03362'),
    ( 493, 'GENUS', '4b5972befe205497fcc1223c6e19c713'),
    ( 649, 'FLAVOR', '3c39ddbe6f6ca53ef61f4b384c440d81'),
    ( 649, 'GENUS', '15eb9c3d28c0ed3243f9f9d37249b334'),
    ( 721, 'FLAVOR', '3aec691ce234c1c25e55b0421cef99e3'),
    ( 721, 'GENUS', '3485c9988307a1efcba84ac1314c2a0b'),
    ( 905, 'FLAVOR', '2961132bc5248df54ff10d3235cc3cb0'),
    ( 905, 'GENUS', '903cdcab9a504b1c836323397c451f24'),
    ( 906, 'FLAVOR', 'c1bab719d860c5afb06cc003b54ba08f'),
    ( 906, 'GENUS', '3d4ed43e6b1573197d5a106253b15a3c'),
    (1025, 'FLAVOR', '4cf656088f060510dd78da734f1db26a'),
    (1025, 'GENUS', 'c790cbbfb620b3210bae0eb51ec6d1fd')
    ) e(national_dex_number, text_kind, content_md5)
    join public.pokemon_species s on s.national_dex_number = e.national_dex_number
    left join public.pokemon_species_text st
      on st.pokemon_species_id = s.id and st.text_kind = e.text_kind
     and st.origin = 'MMKYU_EDITORIAL' and st.language_code = 'pt-BR'
   where st.id is null or md5(st.content) <> e.content_md5;
  if v_n <> 0 then raise exception '6848 FAIL: % registros publicados antes foram alterados', v_n; end if;

  -- 5. Textos oficiais preservados
  select count(*), md5(string_agg(st.pokemon_species_id::text || '|' || st.text_kind || '|' || st.language_code || '|' || coalesce(st.source_version, '') || '|' || st.content || '|' || st.rights_status || '|' || coalesce(st.asset_source_id::text, '') || '|' || coalesce((st.retrieved_at at time zone 'UTC')::text, ''), E'\n' order by st.pokemon_species_id, st.text_kind, st.language_code))
    into v_n, v_md5
    from public.pokemon_species_text st where st.origin = 'SOURCE';
  if v_n <> v_source_baseline_count or v_md5 <> v_source_baseline_md5 then
    raise exception '6848 FAIL: textos oficiais alterados (% linhas, hash %)', v_n, v_md5;
  end if;

  -- 6. Leitura da ficha (sessão autenticada simulada; nada é gravado)
  select id into v_user from auth.users order by created_at limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', v_user::text, 'role', 'authenticated')::text, true);

  select * into v_r from public.get_pokedex_species_detail(4, 'pt-BR');
  if v_r.description_language <> 'pt-BR' or v_r.description_is_official
     or v_r.genus_language <> 'pt-BR' or v_r.genus_is_official or v_r.genus <> $t$Pokémon Lagarto$t$ then
    raise exception '6848 FAIL: ficha pt-BR de #4 não devolve o editorial do lote';
  end if;
  select * into v_r from public.get_pokedex_species_detail(4, 'en');
  if v_r.description_language <> 'en' or not v_r.description_is_official or v_r.description_source_version is null then
    raise exception '6848 FAIL: leitura en de #4 não devolve o texto oficial com versão';
  end if;
  select * into v_r from public.get_pokedex_species_detail(1, 'pt-BR');
  if v_r.description_language <> 'pt-BR' or v_r.description_is_official then
    raise exception '6848 FAIL: espécie já publicada #1 deixou de devolver o editorial';
  end if;
  select * into v_r from public.get_pokedex_species_detail(2, 'pt-BR');
  if v_r.description_language <> 'en' or not v_r.description_is_official then
    raise exception '6848 FAIL: espécie fora dos lotes (#2) deixou de mostrar o oficial en';
  end if;

  raise notice '6848 PASS (editorial: 120 linhas / 60 espécies; lote: 100 / 50; publicados preservados: 20; SOURCE: % linhas preservadas)', v_source_baseline_count;
end
$val$;

rollback;
