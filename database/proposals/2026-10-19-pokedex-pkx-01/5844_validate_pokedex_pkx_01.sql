/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5844 - Harness PKX-01 (5201–5205): estrutura, segurança,
              criação idempotente, gerações, grade, mudança de escopo,
              geração nova, isolamento, resíduo zero
Versão......: 1.0
Status......: PROPOSTA — não executado. Rodar só depois de 5201–5205.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-19 (POKEDEX-PKX-01-IMPLEMENTATION-01)

Protocolo (o mesmo da 5842/5843, já executadas no LIVE): um único
statement no SQL Editor; usuários efêmeros A e B; catálogo SINTÉTICO de
cartas (expansão, Set, cartas, variantes e espécie principal) e uma
GERAÇÃO SINTÉTICA nova (região, geração, espécie e posição na Pokédex
Nacional) criados e desfeitos na mesma transação; a sentinela MS844
desfaz tudo; a seção 99 prova resíduo zero. Usa a Pokédex Nacional real
(só leitura) para as posições #1, #2, #3, #4, #7 e #152.

Fixture:
  Cartas sintéticas (Set PX): k1 e k2 → espécie #1; k3 → #152; k4 → #4.
  A: a1(k1), a2(k2), a3(k3), a4(k4).  B: b1(k1).
  C1 = Pokédex de A com todas as gerações catalogadas.
  F  = Coleção livre de A (recebe a4 → estado ELSEWHERE em #4).
  Geração nova (seção 6): G10 com 1 espécie S10 e posição P10; carta k10
  (espécie S10) e cópia a10 de A. G11 sem posições (não catalogada).

Seções:
  0.x estrutura e privilégios (inclui 5205)
  1.x anon → 42501; authenticated → 5098/5099 recusadas (42501)
  2.x sem identidade → 28000
  3.x opções de geração e criação idempotente
  4.x grade: estados, representante, paginação, filtros, coerência
  5.x mudança de escopo sem perda de cartas/vínculos
  6.x geração nova catalogada: disponível, sem expansão automática
  7.x isolamento e coleção arquivada
  99.1 resíduo zero
GATE: todas PASS e n = 37.
================================================================
*/

create or replace function pg_temp.ms_5844_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  f_opt oid := to_regprocedure('public.get_my_pokedex_generation_options(uuid)');
  f_cre oid := to_regprocedure('public.create_my_pokedex_collection(uuid,text,text[],uuid)');
  f_set oid := to_regprocedure('public.set_my_pokedex_generations(uuid,text[])');
  f_pos oid := to_regprocedure('public.get_my_pokedex_positions(uuid,text,text,integer,integer)');
  f_old_c oid := to_regprocedure('public.create_reference_based_pokedex_collection(uuid,text,text,uuid,uuid,text,uuid[])');
  f_old_s oid := to_regprocedure('public.set_collection_pokedex_scope(uuid,text,uuid[])');
  p_user_a uuid := gen_random_uuid();
  p_user_b uuid := gen_random_uuid();
  v_sfx    text := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  v_game uuid; v_rar uuid; v_cat uuid; v_pt uuid; t_std uuid; v_dex uuid;
  v_exp uuid := gen_random_uuid(); v_set uuid := gen_random_uuid();
  k1 uuid := gen_random_uuid(); k2 uuid := gen_random_uuid(); k3 uuid := gen_random_uuid();
  k4 uuid := gen_random_uuid(); k10 uuid := gen_random_uuid();
  v1 uuid := gen_random_uuid(); v2 uuid := gen_random_uuid(); v3 uuid := gen_random_uuid();
  v4 uuid := gen_random_uuid(); v10 uuid := gen_random_uuid();
  sp1 uuid; sp4 uuid; sp7 uuid; sp152 uuid;
  n1 integer; n4 integer; n7 integer; n152 integer;
  v_region uuid := gen_random_uuid(); v_g10 uuid := gen_random_uuid(); v_g11 uuid := gen_random_uuid();
  v_s10 uuid := gen_random_uuid(); v_p10 uuid := gen_random_uuid(); v_n10 integer;
  v_g10_code text; v_g11_code text;
  v_inv_a uuid; v_inv_b uuid;
  a1 uuid; a2 uuid; a3 uuid; a4 uuid; a10 uuid; b1 uuid;
  v_c1 uuid; v_c2 uuid; v_cb uuid; v_f uuid; v_box uuid;
  v_key1 uuid := gen_random_uuid(); v_key2 uuid := gen_random_uuid(); v_keyb uuid;
  v_all_codes text[]; v_all_codes2 text[]; v_gen1 text; v_gen2 text;
  v_n_gens integer; v_n_pos bigint; v_gen1_count bigint;
  v_rec record; v_rec2 record; v_sum record;
  v_ids uuid[]; v_ids2 uuid[]; v_ids3 uuid[];
  v_cnt bigint; v_cnt2 bigint; v_cnt3 bigint; v_tot bigint; v_ok boolean; v_err text; v_msg text;
  v_fp text; v_fp2 text; v_alloc_a2 uuid;
  b_us bigint; b_co bigint; b_ca bigint; b_pc bigint; b_card bigint; b_cv bigint; b_cs bigint; b_ex bigint;
  b_sc bigint; b_ccr bigint; b_cps bigint; b_gen bigint; b_spc bigint; b_pp bigint; b_reg bigint; b_asg bigint;
  res jsonb := '[]'::jsonb; r jsonb; n integer := 0; passes integer := 0;
begin
  -- 0. Estrutura e privilégios -------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    f_opt is not null and f_cre is not null and f_set is not null and f_pos is not null
    and (select count(*) from pg_proc p where p.oid in (f_opt, f_cre, f_set, f_pos)
           and p.prosecdef and p.proconfig = array['search_path=""']) = 4
    and (select p.provolatile from pg_proc p where p.oid = f_opt) = 's'
    and (select p.provolatile from pg_proc p where p.oid = f_pos) = 's'
    and (select p.provolatile from pg_proc p where p.oid = f_cre) = 'v'
    and (select p.provolatile from pg_proc p where p.oid = f_set) = 'v'
    and (select count(*) from pg_proc p join pg_namespace s on s.oid = p.pronamespace
         where s.nspname = 'public' and p.proname in ('get_my_pokedex_generation_options','create_my_pokedex_collection',
                                                       'set_my_pokedex_generations','get_my_pokedex_positions')) = 4,
    'detail','5201–5204 existem com a assinatura do contrato, sem sobrecarga; SECURITY DEFINER, search_path vazio; leituras STABLE, escritas VOLATILE');

  if f_opt is null or f_cre is null or f_set is null or f_pos is null or f_old_c is null or f_old_s is null then
    res := res || jsonb_build_object('id','X.0','ok', false, 'detail','contratos ausentes — aplique 5201–5205 antes deste harness');
  else
  res := res || jsonb_build_object('id','0.2','ok',
    (select bool_and(has_function_privilege('authenticated', f, 'EXECUTE') and not has_function_privilege('anon', f, 'EXECUTE'))
       from unnest(array[f_opt, f_cre, f_set, f_pos]) f)
    and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid in (f_opt, f_cre, f_set, f_pos) and a.grantee = 0),
    'detail','5201–5204: EXECUTE só authenticated; anon e PUBLIC sem acesso');
  res := res || jsonb_build_object('id','0.3','ok',
    not has_function_privilege('authenticated', f_old_c, 'EXECUTE')
    and not has_function_privilege('authenticated', f_old_s, 'EXECUTE')
    and not has_function_privilege('anon', f_old_c, 'EXECUTE')
    and not has_function_privilege('anon', f_old_s, 'EXECUTE')
    and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid in (f_old_c, f_old_s) and a.grantee = 0)
    and has_function_privilege((select pg_get_userbyid(p.proowner) from pg_proc p where p.oid = f_cre), f_old_c, 'EXECUTE')
    and has_function_privilege((select pg_get_userbyid(p.proowner) from pg_proc p where p.oid = f_set), f_old_s, 'EXECUTE'),
    'detail','5205: 5098/5099 sem EXECUTE para authenticated, anon e PUBLIC; o dono das novas portas (5202/5203) mantém EXECUTE');
  res := res || jsonb_build_object('id','0.4','ok',
    not exists (
      select 1 from unnest(array['collection','collection_reference','collection_pokedex_reference',
                                 'collection_pokedex_scope_generation','collection_creation_request']) t,
                    unnest(array['INSERT','UPDATE','DELETE']) pv
      where has_table_privilege('authenticated', 'public.' || t, pv)
         or has_table_privilege('anon', 'public.' || t, pv)),
    'detail','nenhum caminho alternativo: authenticated/anon sem INSERT/UPDATE/DELETE nas tabelas de coleção e escopo');
  res := res || jsonb_build_object('id','0.5','ok',
    pg_get_function_result(f_pos) = 'TABLE(pokedex_position_id uuid, position_number integer, species_id uuid, species_name text, generation_code text, generation_ordinal integer, species_artwork_path text, is_satisfied boolean, copies_in_collection integer, copies_available integer, copies_elsewhere integer, acervo_state text, representative_card_name text, representative_collector_number text, representative_set_code text, representative_image_path text, total_count bigint)'
    and pg_get_function_result(f_opt) = 'TABLE(generation_code text, generation_ordinal integer, generation_name text, region_name text, species_count bigint, first_number integer, last_number integer, is_selected boolean, satisfied_count bigint)',
    'detail','retorno de 5204 e 5201 exatamente o do contrato (sem ids de acervo)');

  -- linha de base -------------------------------------------------------------
  select count(*) into b_us from auth.users;
  select count(*) into b_co from public.collection;
  select count(*) into b_ca from public.collection_allocation;
  select count(*) into b_pc from public.physical_card;
  select count(*) into b_card from public.card;
  select count(*) into b_cv from public.card_variant;
  select count(*) into b_cs from public.card_set;
  select count(*) into b_ex from public.expansion;
  select count(*) into b_sc from public.storage_container;
  select count(*) into b_ccr from public.collection_creation_request;
  select count(*) into b_cps from public.card_primary_species;
  select count(*) into b_gen from public.pokemon_generation;
  select count(*) into b_spc from public.pokemon_species;
  select count(*) into b_pp from public.pokedex_position;
  select count(*) into b_reg from public.pokemon_region;
  select count(*) into b_asg from public.collection_pokedex_position_assignment;

  begin
    -- Fixture (como dono do banco) --------------------------------------------
    select g.id into v_game from public.game g where g.code = 'POKEMON';
    select rr.id into v_rar from public.rarity rr where rr.game_id = v_game and rr.code = 'COMMON';
    select c.id into v_cat from public.card_category c where c.game_id = v_game and c.code = 'POKEMON';
    select l.id into v_pt from public.language l where l.code = 'pt-BR';
    select t.id into t_std from public.card_variant_type t where t.game_id = v_game and t.code = 'STANDARD';
    select d.id into v_dex from public.pokedex d where d.code = 'NATIONAL' and d.is_active;
    select s.id, pp.position_number into sp1, n1 from public.pokemon_species s join public.pokedex_position pp on pp.species_id = s.id and pp.pokedex_id = v_dex where s.national_dex_number = 1;
    select s.id, pp.position_number into sp4, n4 from public.pokemon_species s join public.pokedex_position pp on pp.species_id = s.id and pp.pokedex_id = v_dex where s.national_dex_number = 4;
    select s.id, pp.position_number into sp7, n7 from public.pokemon_species s join public.pokedex_position pp on pp.species_id = s.id and pp.pokedex_id = v_dex where s.national_dex_number = 7;
    select s.id, pp.position_number into sp152, n152 from public.pokemon_species s join public.pokedex_position pp on pp.species_id = s.id and pp.pokedex_id = v_dex where s.national_dex_number = 152;
    select g.code::text into v_gen1 from public.pokemon_generation g join public.pokemon_species s on s.generation_id = g.id where s.id = sp1;
    select g.code::text into v_gen2 from public.pokemon_generation g join public.pokemon_species s on s.generation_id = g.id where s.id = sp152;
    -- Oráculos do catálogo real (como dono).
    select count(*), sum(x.c) into v_n_gens, v_n_pos from (
      select g.id, count(pp.id) c from public.pokemon_generation g
      join public.pokemon_species s on s.generation_id = g.id
      join public.pokedex_position pp on pp.species_id = s.id and pp.pokedex_id = v_dex
      where g.is_active group by g.id) x;
    select count(*) into v_gen1_count from public.pokedex_position pp join public.pokemon_species s on s.id = pp.species_id
      join public.pokemon_generation g on g.id = s.generation_id where pp.pokedex_id = v_dex and g.code = v_gen1;

    insert into public.expansion (id, game_id, code, name, release_order)
    values (v_exp, v_game, 'ZZPX5844_'||v_sfx, 'PX 5844 '||v_sfx,
            (select coalesce(max(e.release_order), 0) + 1 from public.expansion e where e.game_id = v_game));
    insert into public.card_set (id, expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_set, v_exp, 'ZZPX-'||v_sfx, 'PX 5844 S', 'REGULAR', 1, 5, 5);
    insert into public.card (id, card_set_id, rarity_id, category_id, collector_number, collector_total, collector_order, name)
    values (k1, v_set, v_rar, v_cat, '001', 5, 1, 'PX Um'),
           (k2, v_set, v_rar, v_cat, '002', 5, 2, 'PX Dois'),
           (k3, v_set, v_rar, v_cat, '003', 5, 3, 'PX Três'),
           (k4, v_set, v_rar, v_cat, '004', 5, 4, 'PX Quatro');
    insert into public.card_variant (id, card_id, variant_type_id, printing_profile_id, edition_context_profile_id, variant_order, is_default, is_active)
    values (v1, k1, t_std, null, null, 1, true, true), (v2, k2, t_std, null, null, 1, true, true),
           (v3, k3, t_std, null, null, 1, true, true), (v4, k4, t_std, null, null, 1, true, true);
    insert into public.card_primary_species (card_id, pokemon_species_id, resolution_basis, source_evidence)
    values (k1, sp1,   'AUTOMATIC_DEXID', jsonb_build_object('source','TCGDEX','tcgdex_dex_ids',jsonb_build_array(1),'resolved_dex_id',1)),
           (k2, sp1,   'AUTOMATIC_DEXID', jsonb_build_object('source','TCGDEX','tcgdex_dex_ids',jsonb_build_array(1),'resolved_dex_id',1)),
           (k3, sp152, 'AUTOMATIC_DEXID', jsonb_build_object('source','TCGDEX','tcgdex_dex_ids',jsonb_build_array(152),'resolved_dex_id',152)),
           (k4, sp4,   'AUTOMATIC_DEXID', jsonb_build_object('source','TCGDEX','tcgdex_dex_ids',jsonb_build_array(4),'resolved_dex_id',4));

    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    values (p_user_a, 'authenticated', 'authenticated', 'px5844-a-'||lower(v_sfx)||'@example.invalid',
            jsonb_build_object('username', 'px5844a_'||lower(v_sfx), 'display_name', 'PX 5844 A'), now(), now()),
           (p_user_b, 'authenticated', 'authenticated', 'px5844-b-'||lower(v_sfx)||'@example.invalid',
            jsonb_build_object('username', 'px5844b_'||lower(v_sfx), 'display_name', 'PX 5844 B'), now(), now());
    select i.id into v_inv_a from public.inventory i where i.owner_user_id = p_user_a;
    select i.id into v_inv_b from public.inventory i where i.owner_user_id = p_user_b;

    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v1, v_pt, v_inv_a) returning id into a1;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v2, v_pt, v_inv_a) returning id into a2;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v3, v_pt, v_inv_a) returning id into a3;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v4, v_pt, v_inv_a) returning id into a4;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v1, v_pt, v_inv_b) returning id into b1;

    res := res || jsonb_build_object('id','0.6','ok',
      v_game is not null and v_dex is not null and t_std is not null and sp1 is not null and sp4 is not null
      and sp7 is not null and sp152 is not null and v_gen1 is not null and v_gen2 is not null and v_gen1 <> v_gen2
      and v_n_gens > 0 and v_n_pos > 0 and v_inv_a is not null and v_inv_b is not null,
      'detail','fixture: Pokédex Nacional real (#1, #4, #7, #152), 4 cartas sintéticas com espécie principal, 4 cópias de A + 1 de B');

    -- 1. anon e contratos antigos --------------------------------------------
    execute 'set local role anon';
    v_cnt := 0;
    begin perform * from public.get_my_pokedex_generation_options(null); exception when others then if sqlstate = '42501' then v_cnt := v_cnt + 1; end if; end;
    begin perform * from public.create_my_pokedex_collection(gen_random_uuid(), 'x', array['GENERATION_I'], null); exception when others then if sqlstate = '42501' then v_cnt := v_cnt + 1; end if; end;
    begin perform * from public.set_my_pokedex_generations(gen_random_uuid(), array['GENERATION_I']); exception when others then if sqlstate = '42501' then v_cnt := v_cnt + 1; end if; end;
    begin perform * from public.get_my_pokedex_positions(gen_random_uuid(), 'ALL', null, 10, 0); exception when others then if sqlstate = '42501' then v_cnt := v_cnt + 1; end if; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.1','ok', v_cnt = 4, 'detail','anon recusado (42501) nas 4 funções: '||v_cnt||'/4');

    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    v_cnt := 0;
    begin
      perform * from public.create_reference_based_pokedex_collection(v_game, 'PX bypass', null, null, v_dex, 'FULL_REFERENCE', null);
    exception when others then if sqlstate = '42501' then v_cnt := v_cnt + 1; end if; end;
    begin
      perform * from public.set_collection_pokedex_scope(gen_random_uuid(), 'FULL_REFERENCE', null);
    exception when others then if sqlstate = '42501' then v_cnt := v_cnt + 1; end if; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.2','ok', v_cnt = 2
      and not exists (select 1 from public.collection c where c.owner_user_id = p_user_a),
      'detail','authenticated chamando 5098 (FULL_REFERENCE) e 5099 diretamente → 42501, nada criado: '||v_cnt||'/2');

    -- 2. sem identidade ------------------------------------------------------
    perform set_config('request.jwt.claims', '', true);
    execute 'set local role authenticated';
    v_cnt := 0;
    begin perform * from public.get_my_pokedex_generation_options(null); exception when others then if sqlstate = '28000' then v_cnt := v_cnt + 1; end if; end;
    begin perform * from public.create_my_pokedex_collection(gen_random_uuid(), 'x', array['GENERATION_I'], null); exception when others then if sqlstate = '28000' then v_cnt := v_cnt + 1; end if; end;
    begin perform * from public.set_my_pokedex_generations(gen_random_uuid(), array['GENERATION_I']); exception when others then if sqlstate = '28000' then v_cnt := v_cnt + 1; end if; end;
    begin perform * from public.get_my_pokedex_positions(gen_random_uuid(), 'ALL', null, 10, 0); exception when others then if sqlstate = '28000' then v_cnt := v_cnt + 1; end if; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','2.1','ok', v_cnt = 4, 'detail','authenticated sem auth.uid() → 28000 nas 4 funções: '||v_cnt||'/4');

    -- 3. Opções e criação (como A) ---------------------------------------------
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select array_agg(o.generation_code order by o.generation_ordinal), count(*), sum(o.species_count),
           bool_and(o.is_selected is null and o.satisfied_count is null)
      into v_all_codes, v_cnt, v_tot, v_ok
      from public.get_my_pokedex_generation_options(null) o;
    res := res || jsonb_build_object('id','3.1','ok', v_cnt = v_n_gens and v_tot = v_n_pos and v_ok,
      'detail','opções sem coleção: só gerações catalogadas ('||v_cnt||'), '||v_tot||' posições no total, sem estado de seleção');

    select * into v_rec from public.create_my_pokedex_collection(v_key1, 'PX Pokédex', v_all_codes, null);
    v_c1 := v_rec.collection_id; v_box := v_rec.storage_container_id;
    res := res || jsonb_build_object('id','3.2','ok',
      v_c1 is not null and v_rec.storage_container_created and not v_rec.replayed
      and v_rec.generation_codes = v_all_codes,
      'detail','criação com todas as gerações (padrão): coleção criada, "Local padrão" criado, gerações devolvidas na ordem');

    select * into v_rec2 from public.create_my_pokedex_collection(v_key1, 'PX Pokédex', v_all_codes, null);
    execute 'reset role';
    res := res || jsonb_build_object('id','3.3','ok',
      v_rec2.collection_id = v_c1 and v_rec2.replayed and v_rec2.storage_container_id = v_box
      and (select count(*) from public.collection c where c.owner_user_id = p_user_a) = 1
      and (select count(*) from public.storage_container sc where sc.inventory_id = v_inv_a) = 1,
      'detail','repetição da mesma chave → mesma coleção (replayed), exatamente 1 coleção e 1 local');

    execute 'set local role authenticated';
    v_cnt := 0; v_msg := '';
    begin
      perform * from public.create_my_pokedex_collection(v_key1, 'PX Pokédex', array[v_gen1], null);
    exception when others then if sqlstate = '22023' and sqlerrm = 'IDEMPOTENCY_KEY_REUSED' then v_cnt := v_cnt + 1; end if; end;
    begin
      perform * from public.create_my_pokedex_collection(v_key2, 'PX Outra', v_all_codes, null);
    exception when others then if sqlstate = '55000' and sqlerrm = 'STORAGE_CONTAINER_REQUIRED' then v_cnt := v_cnt + 1; end if; end;
    res := res || jsonb_build_object('id','3.4','ok', v_cnt = 2,
      'detail','mesma chave com pedido diferente → IDEMPOTENCY_KEY_REUSED; sem local já tendo locais → STORAGE_CONTAINER_REQUIRED (um único local padrão): '||v_cnt||'/2');

    v_cnt := 0;
    begin perform * from public.create_my_pokedex_collection(gen_random_uuid(), 'PX x', array[]::text[], v_box); exception when others then if sqlstate = '22023' then v_cnt := v_cnt + 1; end if; end;
    begin perform * from public.create_my_pokedex_collection(gen_random_uuid(), 'PX x', array['GENERATION_INEXISTENTE'], v_box); exception when others then if sqlstate = '22023' and sqlerrm = 'GENERATION_NOT_AVAILABLE' then v_cnt := v_cnt + 1; end if; end;
    begin perform * from public.create_my_pokedex_collection(gen_random_uuid(), 'PX x', array[v_gen1, null], v_box); exception when others then if sqlstate = '22023' then v_cnt := v_cnt + 1; end if; end;
    begin perform * from public.create_my_pokedex_collection(gen_random_uuid(), '  ', array[v_gen1], v_box); exception when others then if sqlstate = '22023' then v_cnt := v_cnt + 1; end if; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','3.5','ok', v_cnt = 4
      and (select count(*) from public.collection c where c.owner_user_id = p_user_a) = 1,
      'detail','lista vazia, geração inexistente, código nulo e nome vazio → 22023; nada criado: '||v_cnt||'/4');

    res := res || jsonb_build_object('id','3.6','ok',
      (select cpr.scope_kind from public.collection_reference cr join public.collection_pokedex_reference cpr on cpr.collection_reference_id = cr.id where cr.collection_id = v_c1) = 'GENERATION_FILTERED'
      and (select count(*) from public.collection_reference cr join public.collection_pokedex_scope_generation sg on sg.collection_reference_id = cr.id where cr.collection_id = v_c1) = v_n_gens
      and (select c.completion_policy from public.collection c where c.id = v_c1) = 'REFERENCE_POSITION',
      'detail','escopo gravado explícito (GENERATION_FILTERED) com as '||v_n_gens||' gerações; nunca FULL_REFERENCE');

    execute 'set local role authenticated';
    select * into v_sum from public.collection_completion_summary(v_c1);
    select bool_and(o.is_selected) and count(*) = v_n_gens and sum(o.satisfied_count) = 0 into v_ok
      from public.get_my_pokedex_generation_options(v_c1) o;
    res := res || jsonb_build_object('id','3.7','ok', v_sum.total_positions = v_n_pos and v_sum.satisfied_positions = 0 and v_ok,
      'detail','coleção nova: '||v_sum.total_positions||' posições, 0 conquistadas; opções com a coleção: todas selecionadas');

    -- 4. Grade ---------------------------------------------------------------
    select c.collection_id into v_f from public.create_my_free_collection(gen_random_uuid(), 'PX Livre', v_box) c;
    perform public.allocate_physical_cards_to_collection(v_c1, array[a1]);
    perform public.allocate_physical_cards_to_collection(v_f, array[a4]);
    select * into v_sum from public.collection_completion_summary(v_c1);
    select max(g.total_count) into v_cnt from public.get_my_pokedex_positions(v_c1, 'OWNED', null, 500, 0) g;
    select max(g.total_count) into v_cnt2 from public.get_my_pokedex_positions(v_c1, 'MISSING', null, 500, 0) g;
    select max(g.total_count) into v_cnt3 from public.get_my_pokedex_positions(v_c1, 'ALL', null, 1, 0) g;
    res := res || jsonb_build_object('id','4.1','ok',
      v_sum.satisfied_positions = 1 and v_cnt = 1 and v_cnt2 = v_n_pos - 1 and v_cnt3 = v_n_pos,
      'detail','a1 (espécie #1) vinculada automaticamente: Tenho 1, Faltam '||v_cnt2||', Todas '||v_cnt3||' = resumo');

    select * into v_rec from public.get_my_pokedex_positions(v_c1, 'ALL', v_gen1, 500, 0) g where g.position_number = n1;
    v_ok := v_rec.acervo_state = 'OWNED' and v_rec.is_satisfied and v_rec.copies_in_collection = 1
            and v_rec.representative_card_name = 'PX Um' and v_rec.representative_set_code = 'ZZPX-'||v_sfx
            and v_rec.species_artwork_path is not null;
    select * into v_rec from public.get_my_pokedex_positions(v_c1, 'ALL', v_gen2, 500, 0) g where g.position_number = n152;
    v_ok := v_ok and v_rec.acervo_state = 'AVAILABLE' and v_rec.copies_available = 1 and not v_rec.is_satisfied
            and v_rec.representative_card_name is null;
    select * into v_rec from public.get_my_pokedex_positions(v_c1, 'ALL', v_gen1, 500, 0) g where g.position_number = n4;
    v_ok := v_ok and v_rec.acervo_state = 'ELSEWHERE' and v_rec.copies_elsewhere = 1 and v_rec.copies_available = 0;
    select * into v_rec from public.get_my_pokedex_positions(v_c1, 'ALL', v_gen1, 500, 0) g where g.position_number = n7;
    v_ok := v_ok and v_rec.acervo_state = 'NOT_FOUND' and v_rec.copies_available = 0 and v_rec.copies_elsewhere = 0;
    res := res || jsonb_build_object('id','4.2','ok', v_ok,
      'detail','4 estados distintos: #1 OWNED (representante, Set, arte da espécie), #152 AVAILABLE (cópia livre), #4 ELSEWHERE (só em outra coleção), #7 NOT_FOUND');

    perform public.allocate_physical_cards_to_collection(v_c1, array[a2]);
    select * into v_sum from public.collection_completion_summary(v_c1);
    select * into v_rec from public.get_my_pokedex_positions(v_c1, 'OWNED', null, 500, 0) g where g.position_number = n1;
    v_ok := v_sum.satisfied_positions = 1 and v_rec.copies_in_collection = 2;
    execute 'reset role';
    select ca.id into v_alloc_a2 from public.collection_allocation ca where ca.physical_card_id = a2;
    execute 'set local role authenticated';
    perform public.set_pokedex_position_primary_representative(v_alloc_a2);
    select * into v_rec from public.get_my_pokedex_positions(v_c1, 'OWNED', null, 500, 0) g where g.position_number = n1;
    res := res || jsonb_build_object('id','4.3','ok', v_ok and v_rec.representative_card_name = 'PX Dois',
      'detail','segunda carta da mesma espécie: 2 cópias na posição, conquista continua 1 (sem inflar); representante escolhido (6125) é o devolvido');

    -- Impressão digital antes das leituras de paginação/filtro.
    execute 'reset role';
    select md5(string_agg(pc.id::text||coalesce(ca.collection_id::text,'-')||coalesce(a.pokedex_position_id::text,'-'), ',' order by pc.id))
      into v_fp
    from public.physical_card pc
    left join public.collection_allocation ca on ca.physical_card_id = pc.id
    left join public.collection_pokedex_position_assignment a on a.collection_allocation_id = ca.id
    where pc.inventory_id in (v_inv_a, v_inv_b);
    execute 'set local role authenticated';

    select array_agg(x.pokedex_position_id order by x.ord), max(x.total_count) into v_ids, v_cnt
      from public.get_my_pokedex_positions(v_c1, 'ALL', null, 4, 0)
           with ordinality x(pokedex_position_id, position_number, species_id, species_name, generation_code, generation_ordinal,
                             species_artwork_path, is_satisfied, copies_in_collection, copies_available, copies_elsewhere, acervo_state,
                             representative_card_name, representative_collector_number, representative_set_code, representative_image_path, total_count, ord);
    select array_agg(x.pokedex_position_id order by x.ord) into v_ids2
      from public.get_my_pokedex_positions(v_c1, 'ALL', null, 2, 0)
           with ordinality x(pokedex_position_id, position_number, species_id, species_name, generation_code, generation_ordinal,
                             species_artwork_path, is_satisfied, copies_in_collection, copies_available, copies_elsewhere, acervo_state,
                             representative_card_name, representative_collector_number, representative_set_code, representative_image_path, total_count, ord);
    select array_agg(x.pokedex_position_id order by x.ord) into v_ids3
      from public.get_my_pokedex_positions(v_c1, 'ALL', null, 2, 2)
           with ordinality x(pokedex_position_id, position_number, species_id, species_name, generation_code, generation_ordinal,
                             species_artwork_path, is_satisfied, copies_in_collection, copies_available, copies_elsewhere, acervo_state,
                             representative_card_name, representative_collector_number, representative_set_code, representative_image_path, total_count, ord);
    select count(*) into v_cnt2 from public.get_my_pokedex_positions(v_c1, 'ALL', null, 10, v_n_pos::integer);
    select bool_and(x.pnum > coalesce(x.prev, 0)) into v_ok from (
      select w.position_number as pnum, lag(w.position_number) over (order by w.ord) as prev
      from public.get_my_pokedex_positions(v_c1, 'ALL', null, 500, 0)
           with ordinality w(pokedex_position_id, position_number, species_id, species_name, generation_code, generation_ordinal,
                             species_artwork_path, is_satisfied, copies_in_collection, copies_available, copies_elsewhere, acervo_state,
                             representative_card_name, representative_collector_number, representative_set_code, representative_image_path, total_count, ord)) x;
    res := res || jsonb_build_object('id','4.4','ok',
      v_ids2 || v_ids3 = v_ids and cardinality(v_ids) = 4 and v_cnt = v_n_pos and v_cnt2 = 0 and v_ok,
      'detail','paginação no servidor: [0..1] + [2..3] = página de 4, sem repetição; total antes do limite; além do fim → vazio; ordem crescente pelo número nacional');

    select max(g.total_count), bool_and(g.generation_code = v_gen1) into v_cnt, v_ok
      from public.get_my_pokedex_positions(v_c1, 'ALL', v_gen1, 500, 0) g;
    res := res || jsonb_build_object('id','4.5','ok', v_cnt = v_gen1_count and v_ok,
      'detail','filtro por geração: '||v_gen1||' devolve só as '||v_cnt||' posições dela');

    select * into v_sum from public.collection_completion_summary(v_c1);
    select max(g.total_count) into v_cnt  from public.get_my_pokedex_positions(v_c1, 'ALL', null, 1, 0) g;
    select max(g.total_count) into v_cnt2 from public.get_my_pokedex_positions(v_c1, 'OWNED', null, 1, 0) g;
    select max(g.total_count) into v_cnt3 from public.get_my_pokedex_positions(v_c1, 'MISSING', null, 1, 0) g;
    res := res || jsonb_build_object('id','4.6','ok',
      v_cnt = v_sum.total_positions and v_cnt2 = v_sum.satisfied_positions and v_cnt3 = v_sum.missing_positions
      and v_cnt2 + v_cnt3 = v_cnt,
      'detail','Todas/Tenho/Faltam = total/conquistadas/faltantes do resumo (5102); Tenho + Faltam = Todas');

    v_cnt := 0;
    begin perform * from public.get_my_pokedex_positions(v_c1, 'X', null, 10, 0); exception when others then if sqlstate = '22023' then v_cnt := v_cnt + 1; end if; end;
    begin perform * from public.get_my_pokedex_positions(v_c1, 'ALL', null, 0, 0); exception when others then if sqlstate = '22023' then v_cnt := v_cnt + 1; end if; end;
    begin perform * from public.get_my_pokedex_positions(v_c1, 'ALL', null, 501, 0); exception when others then if sqlstate = '22023' then v_cnt := v_cnt + 1; end if; end;
    begin perform * from public.get_my_pokedex_positions(v_c1, 'ALL', null, 10, -1); exception when others then if sqlstate = '22023' then v_cnt := v_cnt + 1; end if; end;
    res := res || jsonb_build_object('id','4.7','ok', v_cnt = 4, 'detail','filtro inválido, limite 0/501 e offset −1 → 22023: '||v_cnt||'/4');

    execute 'reset role';
    select md5(string_agg(pc.id::text||coalesce(ca.collection_id::text,'-')||coalesce(a.pokedex_position_id::text,'-'), ',' order by pc.id))
      into v_fp2
    from public.physical_card pc
    left join public.collection_allocation ca on ca.physical_card_id = pc.id
    left join public.collection_pokedex_position_assignment a on a.collection_allocation_id = ca.id
    where pc.inventory_id in (v_inv_a, v_inv_b);
    res := res || jsonb_build_object('id','4.8','ok', v_fp = v_fp2,
      'detail','leituras não alteram cartas, alocações nem vínculos');

    -- 5. Mudança de escopo ---------------------------------------------------
    execute 'set local role authenticated';
    select * into v_rec from public.set_my_pokedex_generations(v_c1, array[v_gen1]);
    execute 'reset role';
    res := res || jsonb_build_object('id','5.1','ok',
      v_rec.changed and v_rec.total_positions = v_gen1_count and v_rec.satisfied_positions = 1
      and v_rec.generation_codes = array[v_gen1]
      and (select count(*) from public.collection_allocation ca where ca.collection_id = v_c1) = 2
      and (select count(*) from public.collection_allocation ca join public.collection_pokedex_position_assignment a on a.collection_allocation_id = ca.id where ca.collection_id = v_c1) = 2,
      'detail','remover gerações: escopo = só '||v_gen1||' ('||v_rec.total_positions||' posições), conquista mantida; 2 alocações e 2 vínculos intactos');

    execute 'set local role authenticated';
    select * into v_rec from public.set_my_pokedex_generations(v_c1, array[v_gen1, v_gen1]);
    res := res || jsonb_build_object('id','5.2','ok', not v_rec.changed and v_rec.total_positions = v_gen1_count,
      'detail','mesma lista de novo (com repetido) → nada gravado (changed = false)');

    select * into v_rec from public.set_my_pokedex_generations(v_c1, array[v_gen2]);
    select count(*) into v_cnt from public.get_my_pokedex_positions(v_c1, 'ALL', v_gen1, 500, 0);
    select max(g.total_count) into v_cnt2 from public.get_my_pokedex_positions(v_c1, 'OWNED', null, 500, 0) g;
    select bool_and(o.is_selected = (o.generation_code = v_gen2)) into v_ok from public.get_my_pokedex_generation_options(v_c1) o;
    execute 'reset role';
    res := res || jsonb_build_object('id','5.3','ok',
      v_rec.satisfied_positions = 0 and v_cnt = 0 and coalesce(v_cnt2, 0) = 0 and v_ok
      and (select count(*) from public.collection_allocation ca join public.collection_pokedex_position_assignment a on a.collection_allocation_id = ca.id where ca.collection_id = v_c1) = 2,
      'detail','escopo só '||v_gen2||': #1 fora do escopo não conta e não aparece; vínculos de #1 preservados; opções marcam só '||v_gen2);

    execute 'set local role authenticated';
    select * into v_rec from public.set_my_pokedex_generations(v_c1, v_all_codes);
    select bool_and(o.is_selected) into v_ok from public.get_my_pokedex_generation_options(v_c1) o;
    select o.satisfied_count into v_cnt from public.get_my_pokedex_generation_options(v_c1) o where o.generation_code = v_gen1;
    res := res || jsonb_build_object('id','5.4','ok',
      v_rec.changed and v_rec.total_positions = v_n_pos and v_rec.satisfied_positions = 1 and v_ok and v_cnt = 1,
      'detail','incluir de volta todas as gerações: total '||v_rec.total_positions||', conquista de #1 volta a contar; opções: todas selecionadas, '||v_gen1||' com 1 conquistada');

    v_cnt := 0;
    begin perform * from public.set_my_pokedex_generations(v_c1, array[]::text[]); exception when others then if sqlstate = '22023' then v_cnt := v_cnt + 1; end if; end;
    begin perform * from public.set_my_pokedex_generations(v_c1, array['GENERATION_INEXISTENTE']); exception when others then if sqlstate = '22023' then v_cnt := v_cnt + 1; end if; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','5.5','ok', v_cnt = 2
      and (select count(*) from public.collection_reference cr join public.collection_pokedex_scope_generation sg on sg.collection_reference_id = cr.id where cr.collection_id = v_c1) = v_n_gens,
      'detail','lista vazia e geração inexistente nos Ajustes → 22023, escopo intacto: '||v_cnt||'/2');

    -- 6. Geração nova catalogada (como dono) -----------------------------------
    v_g10_code := 'ZZGEN10_'||v_sfx; v_g11_code := 'ZZGEN11_'||v_sfx;
    insert into public.pokemon_region (id, code, canonical_name) values (v_region, 'ZZREG_'||v_sfx, 'PX Região');
    insert into public.pokemon_generation (id, code, canonical_name, ordinal_number, main_region_id)
    values (v_g10, v_g10_code, 'PX Geração 10', (select max(g.ordinal_number) + 100 from public.pokemon_generation g), v_region),
           (v_g11, v_g11_code, 'PX Geração 11', (select max(g.ordinal_number) + 200 from public.pokemon_generation g), v_region);
    v_n10 := (select max(s.national_dex_number) + 1000 from public.pokemon_species s);
    insert into public.pokemon_species (id, generation_id, national_dex_number, canonical_name)
    values (v_s10, v_g10, v_n10, 'PX Espécie Nova');
    insert into public.pokedex_position (id, pokedex_id, species_id, position_number)
    values (v_p10, v_dex, v_s10, (select max(pp.position_number) + 1000 from public.pokedex_position pp where pp.pokedex_id = v_dex));
    insert into public.card (id, card_set_id, rarity_id, category_id, collector_number, collector_total, collector_order, name)
    values (k10, v_set, v_rar, v_cat, '005', 5, 5, 'PX Nova');
    insert into public.card_variant (id, card_id, variant_type_id, printing_profile_id, edition_context_profile_id, variant_order, is_default, is_active)
    values (v10, k10, t_std, null, null, 1, true, true);
    insert into public.card_primary_species (card_id, pokemon_species_id, resolution_basis, source_evidence)
    values (k10, v_s10, 'AUTOMATIC_DEXID', jsonb_build_object('source','TCGDEX','tcgdex_dex_ids',jsonb_build_array(v_n10),'resolved_dex_id',v_n10));
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v10, v_pt, v_inv_a) returning id into a10;

    execute 'set local role authenticated';
    select * into v_sum from public.collection_completion_summary(v_c1);
    select count(*) into v_cnt from public.get_my_pokedex_generation_options(v_c1) o where o.generation_code = v_g10_code and not o.is_selected and o.species_count = 1;
    select count(*) into v_cnt2 from public.get_my_pokedex_generation_options(null) o;
    res := res || jsonb_build_object('id','6.1','ok',
      v_sum.total_positions = v_n_pos and v_cnt = 1 and v_cnt2 = v_n_gens + 1,
      'detail','geração nova catalogada: coleção existente continua com '||v_sum.total_positions||' posições (sem expansão automática); a geração aparece como opção não selecionada');

    select count(*) into v_cnt from public.get_my_pokedex_generation_options(null) o where o.generation_code = v_g11_code;
    v_err := 'executou';
    begin perform * from public.set_my_pokedex_generations(v_c1, array[v_g11_code]); exception when others then v_err := sqlstate||' '||sqlerrm; end;
    res := res || jsonb_build_object('id','6.2','ok', v_cnt = 0 and v_err = '22023 GENERATION_NOT_AVAILABLE',
      'detail','geração sem posições não é oferecida nem aceita: '||v_err);

    select array_agg(o.generation_code order by o.generation_ordinal) into v_all_codes2 from public.get_my_pokedex_generation_options(null) o;
    select * into v_rec from public.set_my_pokedex_generations(v_c1, v_all_codes2);
    perform public.allocate_physical_cards_to_collection(v_c1, array[a10]);
    select * into v_sum from public.collection_completion_summary(v_c1);
    select count(*) into v_cnt from public.get_my_pokedex_positions(v_c1, 'OWNED', v_g10_code, 500, 0) g where g.pokedex_position_id = v_p10;
    res := res || jsonb_build_object('id','6.3','ok',
      v_rec.changed and v_rec.total_positions = v_n_pos + 1 and v_sum.satisfied_positions = 2 and v_cnt = 1,
      'detail','inclusão explícita da geração nova pelos Ajustes: '||v_rec.total_positions||' posições; carta da espécie nova conquista a posição dela');

    select * into v_rec from public.create_my_pokedex_collection(gen_random_uuid(), 'PX Pokédex 2', v_all_codes2, v_box);
    v_c2 := v_rec.collection_id;
    select * into v_sum from public.collection_completion_summary(v_c2);
    res := res || jsonb_build_object('id','6.4','ok', v_sum.total_positions = v_n_pos + 1 and v_sum.satisfied_positions = 0,
      'detail','coleção criada depois, com todas as opções: '||v_sum.total_positions||' posições');
    execute 'reset role';

    -- 7. Isolamento e arquivada ----------------------------------------------
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select count(*) into v_cnt from public.get_my_pokedex_positions(v_c1, 'ALL', null, 500, 0);
    select count(*) into v_cnt2 from public.get_my_pokedex_generation_options(v_c1);
    v_err := ''; v_msg := '';
    begin perform * from public.set_my_pokedex_generations(v_c1, array[v_gen1]); exception when others then v_err := sqlstate||' '||sqlerrm; end;
    begin perform * from public.set_my_pokedex_generations(gen_random_uuid(), array[v_gen1]); exception when others then v_msg := sqlstate||' '||sqlerrm; end;
    res := res || jsonb_build_object('id','7.1','ok',
      v_cnt = 0 and v_cnt2 = 0 and v_err = 'P0002 COLLECTION_NOT_FOUND' and v_msg = v_err,
      'detail','B na coleção de A: grade e opções vazias; Ajustes → mesma resposta de coleção inexistente ('||v_err||')');

    v_keyb := v_key1;  -- mesma chave de A: idempotência é por usuário
    select * into v_rec from public.create_my_pokedex_collection(v_keyb, 'PX B', v_all_codes, null);
    v_cb := v_rec.collection_id;
    v_ok := not v_rec.replayed and v_rec.storage_container_created;
    perform public.allocate_physical_cards_to_collection(v_cb, array[b1]);
    select * into v_rec from public.get_my_pokedex_positions(v_cb, 'ALL', v_gen2, 500, 0) g where g.position_number = n152;
    select * into v_rec2 from public.get_my_pokedex_positions(v_cb, 'OWNED', null, 500, 0) g where g.position_number = n1;
    execute 'reset role';
    res := res || jsonb_build_object('id','7.2','ok',
      v_cb is not null and v_cb <> v_c1 and v_ok
      and v_rec.acervo_state = 'NOT_FOUND' and v_rec.copies_available = 0
      and v_rec2.copies_in_collection = 1 and v_rec2.representative_card_name = 'PX Um'
      and (select count(*) from public.collection_allocation ca where ca.collection_id = v_c1) = 3,
      'detail','B com a mesma chave cria a própria coleção; nunca vê as cartas de A (#152 NOT_FOUND para B); coleção de A intacta');

    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.archive_collection(v_c2);
    v_err := '';
    begin perform * from public.set_my_pokedex_generations(v_c2, array[v_gen1]); exception when others then v_err := sqlstate||' '||sqlerrm; end;
    select count(*) into v_cnt from public.get_my_pokedex_positions(v_c2, 'ALL', null, 10, 0);
    execute 'reset role';
    res := res || jsonb_build_object('id','7.3','ok', v_err = '55000 COLLECTION_ARCHIVED' and v_cnt = 10,
      'detail','coleção arquivada: Ajustes recusam ('||v_err||'); grade continua legível');

    raise exception 'MS844' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MS844' then
      res := res || jsonb_build_object('id','X.1','ok', false, 'detail','erro inesperado: '||sqlstate||' '||sqlerrm);
    end if;
  end;

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  res := res || jsonb_build_object('id','99.1','ok',
    (select count(*) from auth.users) = b_us
      and (select count(*) from public.collection) = b_co
      and (select count(*) from public.collection_allocation) = b_ca
      and (select count(*) from public.physical_card) = b_pc
      and (select count(*) from public.card) = b_card
      and (select count(*) from public.card_variant) = b_cv
      and (select count(*) from public.card_set) = b_cs
      and (select count(*) from public.expansion) = b_ex
      and (select count(*) from public.storage_container) = b_sc
      and (select count(*) from public.collection_creation_request) = b_ccr
      and (select count(*) from public.card_primary_species) = b_cps
      and (select count(*) from public.pokemon_generation) = b_gen
      and (select count(*) from public.pokemon_species) = b_spc
      and (select count(*) from public.pokedex_position) = b_pp
      and (select count(*) from public.pokemon_region) = b_reg
      and (select count(*) from public.collection_pokedex_position_assignment) = b_asg
      and current_user = session_user,
    'detail','resíduo zero (usuários, coleções, locais, pedidos, alocações, vínculos, cartas, espécie principal, gerações, espécies, posições, regiões) e papel restaurado');
  end if;

  for r in select * from jsonb_array_elements(res) loop
    n := n + 1;
    if coalesce((r->>'ok')::boolean, false) then passes := passes + 1; end if;
    seq := n; check_id := r->>'id';
    status := case when coalesce((r->>'ok')::boolean, false) then 'PASS' else 'FAIL' end;
    detail := r->>'detail';
    return next;
  end loop;
  seq := 999; check_id := 'GATE';
  status := case when passes = n and n = 37 then 'PASS' else 'FAIL' end;
  detail := format('%s/%s PASS (esperado 37)', passes, n);
  return next;
end;
$fn$;

select * from pg_temp.ms_5844_validate();
