-- Query 6136 | Pokédex P3d — publicação do piloto editorial MMKYU pt-BR (10 espécies)
--
-- Status: PROPOSTA (não executada). Executar no LIVE só com autorização explícita de Fabrício.
--
-- Objetivo
-- Gravar em public.pokemon_species_text a classificação (GENUS) e a descrição (FLAVOR)
-- editoriais MMKYU em pt-BR das 10 espécies do piloto aprovado em 2026-10-12
-- (pilot-pt-BR.json, revisão 4). Conteúdo autoral MMKYU — nunca apresentado como oficial.
--
-- Contrato usado (Query 6133, sem alteração):
-- - chave única uq_pokemon_species_text (pokemon_species_id, text_kind, language_code, origin);
-- - origin = 'MMKYU_EDITORIAL', rights_status = 'MMKYU_EDITORIAL', language_code = 'pt-BR';
-- - asset_source_id, source_version e retrieved_at nulos (permitidos para origem não SOURCE);
-- - ck_pokemon_species_text_content (1..2000 caracteres), trigger de updated_at existente.
--
-- Garantias (falha integral: qualquer violação lança exceção e nada é gravado)
-- 1. Pré-condições: exatamente 10 espécies ativas, com perfil IMPORTED e com os textos
--    oficiais en (GENUS + FLAVOR); nenhuma linha editorial em outra espécie é tocada.
-- 2. Escrita restrita a origin = 'MMKYU_EDITORIAL' das 10 espécies; textos SOURCE nunca são
--    atualizados nem excluídos (só INSERT ... ON CONFLICT na chave editorial).
-- 3. Idempotente: reexecutar não cria linhas; só atualiza se o conteúdo mudou.
-- 4. Pós-condições na mesma transação: 20 linhas editoriais do piloto com o conteúdo exato,
--    hash do conjunto SOURCE idêntico ao de antes, nenhuma outra linha editorial alterada.
--
-- Sem novas funções, tabelas, colunas ou grants. Nenhuma outra espécie afetada.

begin;

do $pub$
declare
  v_expected_species constant integer := 10;
  v_source_before text;
  v_source_after text;
  v_source_count_before integer;
  v_source_count_after integer;
  v_other_editorial_before text;
  v_other_editorial_after text;
  v_species_found integer;
  v_written integer;
  v_pilot_rows integer;
  v_mismatch integer;
begin
  create temporary table p3d_pilot_text (
    national_dex_number integer not null,
    text_kind text not null,
    content text not null,
    primary key (national_dex_number, text_kind)
  ) on commit drop;

  insert into p3d_pilot_text (national_dex_number, text_kind, content) values
    (   1, 'GENUS',  $t$Pokémon Semente$t$),
    (   1, 'FLAVOR', $t$A semente nas costas de Bulbasaur não é enfeite: é a despensa que sustenta seu crescimento. Enquanto é jovem, ele recorre aos nutrientes guardados ali — um vínculo com o mundo das plantas que acompanha a espécie desde cedo.$t$),
    (  25, 'GENUS',  $t$Pokémon Rato$t$),
    (  25, 'FLAVOR', $t$As bochechas de Pikachu funcionam como pequenas baterias, onde ele guarda a eletricidade que produz. Engenhoso, encontrou um uso doméstico para esse poder: com um choque certeiro, tosta frutos duros antes de comê-los.$t$),
    ( 150, 'GENUS',  $t$Pokémon Genético$t$),
    ( 150, 'FLAVOR', $t$Mewtwo compartilha com Mew quase todo o seu DNA, mas o parentesco para por aí: no porte e, sobretudo, no temperamento, os dois são profundamente diferentes.$t$),
    ( 201, 'GENUS',  $t$Pokémon Símbolo$t$),
    ( 201, 'FLAVOR', $t$Unown chama atenção pelo formato incomum: seus corpos lembram caracteres de escrita, e a espécie se apresenta em muitas formas diferentes.$t$),
    ( 493, 'GENUS',  $t$Pokémon Alfa$t$),
    ( 493, 'FLAVOR', $t$Na mitologia de Hisui, Arceus está acima de tudo: é tido como o criador de todas as coisas e como a fonte de uma luz celeste que guia e protege os Pokémon da região.$t$),
    ( 649, 'GENUS',  $t$Pokémon Paleozoico$t$),
    ( 649, 'FLAVOR', $t$Em Genesect, passado remoto e tecnologia se encontram: a espécie remonta a cerca de 300 milhões de anos, mas foi alterada pela Equipe Plasma. O canhão que carrega nas costas é obra dessa intervenção, não da natureza.$t$),
    ( 721, 'GENUS',  $t$Pokémon Vapor$t$),
    ( 721, 'FLAVOR', $t$Volcanion reúne no mesmo corpo fogo e água, duas forças que costumam se anular, e transforma esse encontro em vapor. A pressão é liberada pelos braços que tem nas costas, com potência para arrasar uma montanha.$t$),
    ( 905, 'GENUS',  $t$Pokémon Amor-Ódio$t$),
    ( 905, 'FLAVOR', $t$Nas lendas de Hisui, Enamorus é o mensageiro da primavera: quando atravessa o mar e chega à região, o inverno rigoroso termina. As mesmas histórias atribuem ao seu afeto o despertar de vida nova pela terra.$t$),
    ( 906, 'GENUS',  $t$Pokémon Gato-Planta$t$),
    ( 906, 'FLAVOR', $t$O trunfo de Sprigatito é discreto: o aroma adocicado que o corpo exala, capaz de encantar quem estiver por perto. Sob o sol, o perfume fica mais intenso — e o encanto também.$t$),
    (1025, 'GENUS',  $t$Pokémon Dominação$t$),
    (1025, 'FLAVOR', $t$Por trás da aparência de fruta, Pecharunt guarda um perigo: a carapaça em forma de pêssego é um reservatório de veneno potente. É desse estoque que saem os mochis envenenados que ele prepara para oferecer a pessoas e Pokémon.$t$);

  -- Pré-condições -----------------------------------------------------------------
  if (select count(*) from p3d_pilot_text) <> 2 * v_expected_species
     or (select count(distinct national_dex_number) from p3d_pilot_text) <> v_expected_species then
    raise exception '6136 FAIL: payload deve ter 20 textos de 10 espécies';
  end if;

  select count(*) into v_species_found
    from (select distinct national_dex_number from p3d_pilot_text) t
    join public.pokemon_species s on s.national_dex_number = t.national_dex_number and s.is_active
    join public.pokemon_species_profile p on p.pokemon_species_id = s.id and p.status = 'IMPORTED'
   where exists (select 1 from public.pokemon_species_text o
                  where o.pokemon_species_id = s.id and o.origin = 'SOURCE' and o.language_code = 'en' and o.text_kind = 'GENUS')
     and exists (select 1 from public.pokemon_species_text o
                  where o.pokemon_species_id = s.id and o.origin = 'SOURCE' and o.language_code = 'en' and o.text_kind = 'FLAVOR');
  if v_species_found <> v_expected_species then
    raise exception '6136 FAIL: % de % espécies elegíveis (ativa, perfil IMPORTED, textos oficiais en)', v_species_found, v_expected_species;
  end if;

  if exists (select 1 from p3d_pilot_text where btrim(content) = '' or length(content) > 2000) then
    raise exception '6136 FAIL: conteúdo vazio ou acima de 2000 caracteres';
  end if;

  -- Linha de base -------------------------------------------------------------------
  select count(*), md5(string_agg(st.pokemon_species_id::text || '|' || st.text_kind || '|' || st.language_code || '|' || coalesce(st.source_version, '') || '|' || st.content || '|' || st.rights_status || '|' || coalesce(st.asset_source_id::text, '') || '|' || coalesce((st.retrieved_at at time zone 'UTC')::text, ''), E'\n' order by st.pokemon_species_id, st.text_kind, st.language_code))
    into v_source_count_before, v_source_before
    from public.pokemon_species_text st where st.origin = 'SOURCE';

  select md5(coalesce(string_agg(st.id::text || '|' || st.content || '|' || st.updated_at::text, E'\n' order by st.id), ''))
    into v_other_editorial_before
    from public.pokemon_species_text st
    join public.pokemon_species s on s.id = st.pokemon_species_id
   where st.origin = 'MMKYU_EDITORIAL'
     and s.national_dex_number not in (select national_dex_number from p3d_pilot_text);

  -- Escrita (só a chave editorial; SOURCE nunca é alvo) ---------------------------
  insert into public.pokemon_species_text as st (
    pokemon_species_id, text_kind, language_code, origin,
    asset_source_id, source_version, content, rights_status, retrieved_at
  )
  select s.id, t.text_kind, 'pt-BR', 'MMKYU_EDITORIAL',
         null, null, t.content, 'MMKYU_EDITORIAL', null
    from p3d_pilot_text t
    join public.pokemon_species s on s.national_dex_number = t.national_dex_number and s.is_active
  on conflict on constraint uq_pokemon_species_text do update
     set content = excluded.content,
         rights_status = 'MMKYU_EDITORIAL'
   where st.origin = 'MMKYU_EDITORIAL'
     and (st.content is distinct from excluded.content or st.rights_status is distinct from 'MMKYU_EDITORIAL');
  get diagnostics v_written = row_count;

  -- Pós-condições (mesma transação) -------------------------------------------------
  select count(*) into v_pilot_rows
    from public.pokemon_species_text st
    join public.pokemon_species s on s.id = st.pokemon_species_id
   where st.origin = 'MMKYU_EDITORIAL'
     and s.national_dex_number in (select national_dex_number from p3d_pilot_text);
  if v_pilot_rows <> 2 * v_expected_species then
    raise exception '6136 FAIL: % linhas editoriais do piloto, esperado 20', v_pilot_rows;
  end if;

  select count(*) into v_mismatch
    from p3d_pilot_text t
    join public.pokemon_species s on s.national_dex_number = t.national_dex_number
    left join public.pokemon_species_text st
      on st.pokemon_species_id = s.id and st.text_kind = t.text_kind
     and st.language_code = 'pt-BR' and st.origin = 'MMKYU_EDITORIAL'
   where st.id is null
      or st.content is distinct from t.content
      or st.rights_status <> 'MMKYU_EDITORIAL'
      or st.asset_source_id is not null or st.source_version is not null or st.retrieved_at is not null;
  if v_mismatch <> 0 then
    raise exception '6136 FAIL: % textos divergentes do payload aprovado', v_mismatch;
  end if;

  select count(*), md5(string_agg(st.pokemon_species_id::text || '|' || st.text_kind || '|' || st.language_code || '|' || coalesce(st.source_version, '') || '|' || st.content || '|' || st.rights_status || '|' || coalesce(st.asset_source_id::text, '') || '|' || coalesce((st.retrieved_at at time zone 'UTC')::text, ''), E'\n' order by st.pokemon_species_id, st.text_kind, st.language_code))
    into v_source_count_after, v_source_after
    from public.pokemon_species_text st where st.origin = 'SOURCE';
  if v_source_count_after <> v_source_count_before or v_source_after is distinct from v_source_before then
    raise exception '6136 FAIL: textos oficiais (SOURCE) alterados';
  end if;

  select md5(coalesce(string_agg(st.id::text || '|' || st.content || '|' || st.updated_at::text, E'\n' order by st.id), ''))
    into v_other_editorial_after
    from public.pokemon_species_text st
    join public.pokemon_species s on s.id = st.pokemon_species_id
   where st.origin = 'MMKYU_EDITORIAL'
     and s.national_dex_number not in (select national_dex_number from p3d_pilot_text);
  if v_other_editorial_after is distinct from v_other_editorial_before then
    raise exception '6136 FAIL: linhas editoriais de outras espécies alteradas';
  end if;

  raise notice '6136 OK: % linhas gravadas/atualizadas; piloto = % linhas editoriais; SOURCE preservado (% linhas)',
    v_written, v_pilot_rows, v_source_count_after;
end
$pub$;

commit;

-- Resultado esperado
-- Primeira execução: "6136 OK: 20 linhas gravadas/atualizadas; piloto = 20 linhas editoriais;
-- SOURCE preservado (2050 linhas)". Reexecução: "6136 OK: 0 linhas ...; piloto = 20 ...".
-- Qualquer FAIL desfaz a transação inteira (nada gravado).
--
-- Como validar: executar 6847_validate_pokedex_editorial_ptbr_pilot.sql → "6847 PASS".
--
-- Rollback (somente as 20 linhas do piloto; SOURCE intocado):
--   delete from public.pokemon_species_text st
--    using public.pokemon_species s
--    where s.id = st.pokemon_species_id and st.origin = 'MMKYU_EDITORIAL'
--      and st.language_code = 'pt-BR'
--      and s.national_dex_number in (1, 25, 150, 201, 493, 649, 721, 905, 906, 1025);
