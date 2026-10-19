/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5846 - Harness PKX-03 (5208–5211): estrutura, segurança,
              candidatos, vínculo normal, vínculo excepcional atômico,
              gerenciar vínculos/representante, lote, isolamento,
              resíduo zero
Versão......: 1.0
Status......: EXECUTADO no LIVE em 2026-10-19 após 5208–5211 — 27/27 PASS,
              GATE PASS, 99.1 resíduo zero. Mantido aqui como evidência.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-19 (POKEDEX-PKX-03-IMPLEMENTATION-01)

Protocolo (o mesmo da 5844, executada no LIVE): um único statement no
SQL Editor; usuários efêmeros A e B; catálogo SINTÉTICO de cartas
(expansão, Set, cartas, variantes e espécie principal) criado e desfeito
na mesma transação; a sentinela MS846 desfaz tudo; a seção 99 prova
resíduo zero. Usa a Pokédex Nacional real (só leitura) para #1, #4, #7
e #152. Exercita também os contratos canônicos reutilizados (5046,
5047, 6119, 6122, 6124, 6125, 5102, 5204) no fluxo PKX-03.

Fixture:
  Cartas sintéticas (Set PX): k1, k2 → espécie #1; k3 → #152; k4 → #4.
  A: a1(k1), a2(k2), a5(k1), a3(k3), a4(k4), a6(k4).   B: b1(k1).
  C1 = Pokédex de A com todas as gerações catalogadas (5202).
  F  = Coleção livre de A com a4 (exemplar em outra coleção).

Seções:
  0.x estrutura, privilégios, retorno, fixture
  1.1 anon → 42501;  2.1 sem identidade → 28000
  3.x candidatos (5208): SPECIES, ACERVO com busca escapada, entradas
  4.1 vínculo normal: 5210 sem confirmação (5046 + 6119, SPECIES_MATCH)
  5.x vínculo excepcional (5210 com confirmação): confirmação, atomicidade,
      idempotência, outra coleção, alheio, progresso pela posição,
      nunca move vínculo existente
  6.x gerenciar (5209 + 6125 + 6124 + 5047): representante, retirar
      vínculo ≠ tirar da coleção, atributos físicos preservados
  7.x lote (5211 + 5046): prévia, confirmação, nunca exceção
  8.x isolamento e coleção arquivada
  99.1 resíduo zero
GATE: todas PASS e n = 27.
================================================================
*/

create or replace function pg_temp.ms_5846_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  f_cand oid := to_regprocedure('public.get_my_pokedex_link_candidates(uuid,uuid,text,text,integer,integer)');
  f_copy oid := to_regprocedure('public.get_my_pokedex_position_copies(uuid,uuid)');
  f_link oid := to_regprocedure('public.link_my_pokedex_copy(uuid,uuid,uuid,boolean)');
  f_bulk oid := to_regprocedure('public.get_my_pokedex_bulk_link_preview(uuid,text)');
  p_user_a uuid := gen_random_uuid();
  p_user_b uuid := gen_random_uuid();
  v_sfx    text := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  v_game uuid; v_rar uuid; v_cat uuid; v_pt uuid; t_std uuid; v_dex uuid;
  v_exp uuid := gen_random_uuid(); v_set uuid := gen_random_uuid();
  k1 uuid := gen_random_uuid(); k2 uuid := gen_random_uuid(); k3 uuid := gen_random_uuid(); k4 uuid := gen_random_uuid();
  v1 uuid := gen_random_uuid(); v2 uuid := gen_random_uuid(); v3 uuid := gen_random_uuid(); v4 uuid := gen_random_uuid();
  sp1 uuid; sp4 uuid; sp7 uuid; sp152 uuid;
  pos1 uuid; pos4 uuid; pos7 uuid; pos152 uuid;
  v_inv_a uuid; v_inv_b uuid;
  a1 uuid; a2 uuid; a3 uuid; a4 uuid; a5 uuid; a6 uuid; b1 uuid;
  v_c1 uuid; v_f uuid; v_box uuid;
  v_all_codes text[]; v_n_pos bigint;
  v_rec record; v_sum record; v_snap text; v_snap2 text;
  v_ids uuid[]; v_ids2 uuid[]; v_cnt bigint; v_cnt2 bigint; v_cnt3 bigint; v_ok boolean; v_err text; v_msg text;
  b_us bigint; b_co bigint; b_ca bigint; b_pc bigint; b_card bigint; b_cv bigint; b_cs bigint; b_ex bigint;
  b_sc bigint; b_ccr bigint; b_cps bigint; b_asg bigint; b_rep bigint;
  res jsonb := '[]'::jsonb; r jsonb; n integer := 0; passes integer := 0;
begin
  -- 0. Estrutura e privilégios -------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    f_cand is not null and f_copy is not null and f_link is not null and f_bulk is not null
    and (select count(*) from pg_proc p where p.oid in (f_cand, f_copy, f_link, f_bulk)
           and p.prosecdef and p.proconfig = array['search_path=""']) = 4
    and (select p.provolatile from pg_proc p where p.oid = f_cand) = 's'
    and (select p.provolatile from pg_proc p where p.oid = f_copy) = 's'
    and (select p.provolatile from pg_proc p where p.oid = f_bulk) = 's'
    and (select p.provolatile from pg_proc p where p.oid = f_link) = 'v'
    and (select count(*) from pg_proc p join pg_namespace s on s.oid = p.pronamespace
         where s.nspname = 'public' and p.proname in ('get_my_pokedex_link_candidates','get_my_pokedex_position_copies',
                                                       'link_my_pokedex_copy','get_my_pokedex_bulk_link_preview')) = 4,
    'detail','5208–5211 existem com a assinatura do contrato, sem sobrecarga; SECURITY DEFINER, search_path vazio; leituras STABLE, escrita VOLATILE');

  if f_cand is null or f_copy is null or f_link is null or f_bulk is null then
    res := res || jsonb_build_object('id','X.0','ok', false, 'detail','contratos ausentes — aplique 5208–5211 antes deste harness');
  else
  res := res || jsonb_build_object('id','0.2','ok',
    (select bool_and(has_function_privilege('authenticated', f, 'EXECUTE') and not has_function_privilege('anon', f, 'EXECUTE'))
       from unnest(array[f_cand, f_copy, f_link, f_bulk]) f)
    and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid in (f_cand, f_copy, f_link, f_bulk) and a.grantee = 0)
    and not exists (
      select 1 from unnest(array['collection_allocation','collection_pokedex_position_assignment',
                                 'collection_pokedex_position_primary_representative']) t,
                    unnest(array['INSERT','UPDATE','DELETE']) pv
      where has_table_privilege('authenticated', 'public.' || t, pv) or has_table_privilege('anon', 'public.' || t, pv)),
    'detail','5208–5211: EXECUTE só authenticated (anon e PUBLIC sem acesso); nenhuma escrita direta em alocação, vínculo ou representante');
  res := res || jsonb_build_object('id','0.3','ok',
    pg_get_function_result(f_cand) = 'TABLE(physical_card_id uuid, card_name text, collector_number text, card_set_code text, card_set_name text, variant_label text, is_default_variant boolean, language_code text, language_name text, storage_name text, image_path text, added_at timestamp with time zone, in_this_collection boolean, card_species_name text, card_species_number integer, species_match boolean, total_count bigint)'
    and pg_get_function_result(f_copy) = 'TABLE(collection_allocation_id uuid, physical_card_id uuid, card_name text, collector_number text, card_set_code text, card_set_name text, variant_label text, is_default_variant boolean, language_code text, language_name text, storage_name text, image_path text, assignment_basis text, assigned_at timestamp with time zone, is_representative boolean, card_species_name text, card_species_number integer, total_count bigint)'
    and pg_get_function_result(f_link) = 'TABLE(collection_allocation_id uuid, pokedex_position_id uuid, assignment_basis text, allocated_now boolean, satisfied_positions bigint, total_positions bigint)'
    and pg_get_function_result(f_bulk) = 'TABLE(pokedex_position_id uuid, position_number integer, species_name text, species_artwork_path text, eligible_count integer, physical_card_id uuid, card_name text, collector_number text, card_set_code text, variant_label text, language_code text, language_name text, storage_name text, image_path text, missing_total bigint, total_count bigint)',
    'detail','retorno de 5208–5211 exatamente o do contrato');

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
  select count(*) into b_asg from public.collection_pokedex_position_assignment;
  select count(*) into b_rep from public.collection_pokedex_position_primary_representative;

  begin
    -- Fixture (como dono do banco) --------------------------------------------
    select g.id into v_game from public.game g where g.code = 'POKEMON';
    select rr.id into v_rar from public.rarity rr where rr.game_id = v_game and rr.code = 'COMMON';
    select c.id into v_cat from public.card_category c where c.game_id = v_game and c.code = 'POKEMON';
    select l.id into v_pt from public.language l where l.code = 'pt-BR';
    select t.id into t_std from public.card_variant_type t where t.game_id = v_game and t.code = 'STANDARD';
    select d.id into v_dex from public.pokedex d where d.code = 'NATIONAL' and d.is_active;
    select s.id, pp.id into sp1, pos1 from public.pokemon_species s join public.pokedex_position pp on pp.species_id = s.id and pp.pokedex_id = v_dex where s.national_dex_number = 1;
    select s.id, pp.id into sp4, pos4 from public.pokemon_species s join public.pokedex_position pp on pp.species_id = s.id and pp.pokedex_id = v_dex where s.national_dex_number = 4;
    select s.id, pp.id into sp7, pos7 from public.pokemon_species s join public.pokedex_position pp on pp.species_id = s.id and pp.pokedex_id = v_dex where s.national_dex_number = 7;
    select s.id, pp.id into sp152, pos152 from public.pokemon_species s join public.pokedex_position pp on pp.species_id = s.id and pp.pokedex_id = v_dex where s.national_dex_number = 152;

    insert into public.expansion (id, game_id, code, name, release_order)
    values (v_exp, v_game, 'ZZPX5846_'||v_sfx, 'PX 5846 '||v_sfx,
            (select coalesce(max(e.release_order), 0) + 1 from public.expansion e where e.game_id = v_game));
    insert into public.card_set (id, expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_set, v_exp, 'ZZPX-'||v_sfx, 'PX 5846 S', 'REGULAR', 1, 4, 4);
    insert into public.card (id, card_set_id, rarity_id, category_id, collector_number, collector_total, collector_order, name)
    values (k1, v_set, v_rar, v_cat, '001', 4, 1, 'PX Um'),
           (k2, v_set, v_rar, v_cat, '002', 4, 2, 'PX Dois'),
           (k3, v_set, v_rar, v_cat, '003', 4, 3, 'PX Três'),
           (k4, v_set, v_rar, v_cat, '004', 4, 4, 'PX Quatro');
    insert into public.card_variant (id, card_id, variant_type_id, printing_profile_id, edition_context_profile_id, variant_order, is_default, is_active)
    values (v1, k1, t_std, null, null, 1, true, true), (v2, k2, t_std, null, null, 1, true, true),
           (v3, k3, t_std, null, null, 1, true, true), (v4, k4, t_std, null, null, 1, true, true);
    insert into public.card_primary_species (card_id, pokemon_species_id, resolution_basis, source_evidence)
    values (k1, sp1,   'AUTOMATIC_DEXID', jsonb_build_object('source','TCGDEX','tcgdex_dex_ids',jsonb_build_array(1),'resolved_dex_id',1)),
           (k2, sp1,   'AUTOMATIC_DEXID', jsonb_build_object('source','TCGDEX','tcgdex_dex_ids',jsonb_build_array(1),'resolved_dex_id',1)),
           (k3, sp152, 'AUTOMATIC_DEXID', jsonb_build_object('source','TCGDEX','tcgdex_dex_ids',jsonb_build_array(152),'resolved_dex_id',152)),
           (k4, sp4,   'AUTOMATIC_DEXID', jsonb_build_object('source','TCGDEX','tcgdex_dex_ids',jsonb_build_array(4),'resolved_dex_id',4));

    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    values (p_user_a, 'authenticated', 'authenticated', 'px5846-a-'||lower(v_sfx)||'@example.invalid',
            jsonb_build_object('username', 'px5846a_'||lower(v_sfx), 'display_name', 'PX 5846 A'), now(), now()),
           (p_user_b, 'authenticated', 'authenticated', 'px5846-b-'||lower(v_sfx)||'@example.invalid',
            jsonb_build_object('username', 'px5846b_'||lower(v_sfx), 'display_name', 'PX 5846 B'), now(), now());
    select i.id into v_inv_a from public.inventory i where i.owner_user_id = p_user_a;
    select i.id into v_inv_b from public.inventory i where i.owner_user_id = p_user_b;

    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v1, v_pt, v_inv_a) returning id into a1;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v2, v_pt, v_inv_a) returning id into a2;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v3, v_pt, v_inv_a) returning id into a3;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v4, v_pt, v_inv_a) returning id into a4;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v1, v_pt, v_inv_a) returning id into a5;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v4, v_pt, v_inv_a) returning id into a6;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v1, v_pt, v_inv_b) returning id into b1;

    res := res || jsonb_build_object('id','0.4','ok',
      v_game is not null and v_dex is not null and t_std is not null and pos1 is not null and pos4 is not null
      and pos7 is not null and pos152 is not null and v_inv_a is not null and v_inv_b is not null,
      'detail','fixture: Pokédex Nacional real (#1, #4, #7, #152), 4 cartas sintéticas com espécie principal, 6 cópias de A + 1 de B');

    -- 1. anon ------------------------------------------------------------------
    execute 'set local role anon';
    v_cnt := 0;
    begin perform * from public.get_my_pokedex_link_candidates(gen_random_uuid(), gen_random_uuid(), 'SPECIES', null, 10, 0); exception when others then if sqlstate = '42501' then v_cnt := v_cnt + 1; end if; end;
    begin perform * from public.get_my_pokedex_position_copies(gen_random_uuid(), gen_random_uuid()); exception when others then if sqlstate = '42501' then v_cnt := v_cnt + 1; end if; end;
    begin perform * from public.link_my_pokedex_copy(gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), true); exception when others then if sqlstate = '42501' then v_cnt := v_cnt + 1; end if; end;
    begin perform * from public.get_my_pokedex_bulk_link_preview(gen_random_uuid(), null); exception when others then if sqlstate = '42501' then v_cnt := v_cnt + 1; end if; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.1','ok', v_cnt = 4, 'detail','anon recusado (42501) nas 4 funções: '||v_cnt||'/4');

    -- 2. sem identidade ----------------------------------------------------------
    perform set_config('request.jwt.claims', '', true);
    execute 'set local role authenticated';
    v_cnt := 0;
    begin perform * from public.get_my_pokedex_link_candidates(gen_random_uuid(), gen_random_uuid(), 'SPECIES', null, 10, 0); exception when others then if sqlstate = '28000' then v_cnt := v_cnt + 1; end if; end;
    begin perform * from public.get_my_pokedex_position_copies(gen_random_uuid(), gen_random_uuid()); exception when others then if sqlstate = '28000' then v_cnt := v_cnt + 1; end if; end;
    begin perform * from public.link_my_pokedex_copy(gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), true); exception when others then if sqlstate = '28000' then v_cnt := v_cnt + 1; end if; end;
    begin perform * from public.get_my_pokedex_bulk_link_preview(gen_random_uuid(), null); exception when others then if sqlstate = '28000' then v_cnt := v_cnt + 1; end if; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','2.1','ok', v_cnt = 4, 'detail','authenticated sem auth.uid() → 28000 nas 4 funções: '||v_cnt||'/4');

    -- Coleções de A ------------------------------------------------------------
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select array_agg(o.generation_code order by o.generation_ordinal) into v_all_codes from public.get_my_pokedex_generation_options(null) o;
    select * into v_rec from public.create_my_pokedex_collection(gen_random_uuid(), 'PX Pokédex', v_all_codes, null);
    v_c1 := v_rec.collection_id; v_box := v_rec.storage_container_id;
    select c.collection_id into v_f from public.create_my_free_collection(gen_random_uuid(), 'PX Livre', v_box) c;
    perform public.allocate_physical_cards_to_collection(v_f, array[a4]);
    select s.total_positions into v_n_pos from public.collection_completion_summary(v_c1) s;

    -- 3. Candidatos (5208) -----------------------------------------------------
    select array_agg(c.physical_card_id order by c.physical_card_id), bool_and(c.species_match and not c.in_this_collection and c.card_species_number = 1),
           max(c.total_count)
      into v_ids, v_ok, v_cnt
      from public.get_my_pokedex_link_candidates(v_c1, pos1, 'SPECIES', null, 48, 0) c;
    res := res || jsonb_build_object('id','3.1','ok',
      v_ids = (select array_agg(x order by x) from unnest(array[a1, a2, a5]) x) and v_ok and v_cnt = 3,
      'detail','SPECIES em #1: só os 3 exemplares livres de A da espécie #1 (nunca o de B, nunca outra espécie), total 3');

    select array_agg(c.physical_card_id order by c.physical_card_id), bool_and(not c.species_match)
      into v_ids, v_ok
      from public.get_my_pokedex_link_candidates(v_c1, pos1, 'ACERVO', null, 48, 0) c;
    select count(*) into v_cnt from public.get_my_pokedex_link_candidates(v_c1, pos1, 'ACERVO', 'Três', 48, 0) c where c.physical_card_id = a3 and c.card_species_number = 152;
    select count(*) into v_cnt2 from public.get_my_pokedex_link_candidates(v_c1, pos1, 'ACERVO', '%', 48, 0) c;
    select count(*) into v_cnt3 from public.get_my_pokedex_link_candidates(v_c1, pos1, 'ACERVO', 'Três', 48, 0) c;
    res := res || jsonb_build_object('id','3.2','ok',
      v_ids = (select array_agg(x order by x) from unnest(array[a3, a6]) x) and v_ok and v_cnt = 1 and v_cnt3 = 1 and v_cnt2 = 0,
      'detail','ACERVO em #1: só os livres de outra espécie (a3, a6; a4 está em outra coleção); busca "Três" → a3 com espécie #152; "%" literal → 0 linhas');

    v_cnt := 0;
    begin perform * from public.get_my_pokedex_link_candidates(v_c1, pos1, 'OUTRO', null, 48, 0); exception when others then if sqlstate = '22023' and sqlerrm = 'INVALID_SCOPE' then v_cnt := v_cnt + 1; end if; end;
    begin perform * from public.get_my_pokedex_link_candidates(v_c1, pos1, 'SPECIES', null, 0, 0); exception when others then if sqlstate = '22023' and sqlerrm = 'INVALID_PAGE' then v_cnt := v_cnt + 1; end if; end;
    begin perform * from public.get_my_pokedex_link_candidates(v_c1, null, 'SPECIES', null, 10, 0); exception when others then if sqlstate = '22023' and sqlerrm = 'INVALID_POSITION' then v_cnt := v_cnt + 1; end if; end;
    select count(*) into v_cnt2 from public.get_my_pokedex_link_candidates(v_c1, gen_random_uuid(), 'SPECIES', null, 10, 0);
    select count(*) into v_cnt3 from public.get_my_pokedex_link_candidates(v_f, pos1, 'SPECIES', null, 10, 0);
    res := res || jsonb_build_object('id','3.3','ok', v_cnt = 3 and v_cnt2 = 0 and v_cnt3 = 0,
      'detail','escopo inválido, página inválida e posição nula → 22023; posição inexistente e coleção que não é Pokédex → zero linhas');

    -- 4. Vínculo normal (5210 sem confirmação → 5046 + 6119) ---------------------
    select * into v_sum from public.link_my_pokedex_copy(v_c1, pos1, a1, false);
    select count(*) into v_cnt from public.get_my_pokedex_link_candidates(v_c1, pos1, 'SPECIES', null, 48, 0);
    select * into v_rec from public.get_my_pokedex_position_copies(v_c1, pos1);
    res := res || jsonb_build_object('id','4.1','ok',
      v_sum.assignment_basis = 'SPECIES_MATCH' and v_sum.allocated_now and v_sum.satisfied_positions = 1
      and v_cnt = 2 and v_rec.physical_card_id = a1 and v_rec.assignment_basis = 'SPECIES_MATCH'
      and not v_rec.is_representative and v_rec.total_count = 1 and v_rec.card_species_number = 1
      and v_rec.language_code = 'pt-BR',
      'detail','vínculo normal de a1 (sem confirmação): 5046 + 6119 → SPECIES_MATCH em #1; candidatos caem para 2; posição conquistada (1)');

    -- 5. Vínculo excepcional (5210) --------------------------------------------
    v_cnt := 0;
    begin perform * from public.link_my_pokedex_copy(v_c1, pos1, a3, false); exception when others then if sqlstate = '55000' and sqlerrm = 'EXCEPTION_CONFIRMATION_REQUIRED' then v_cnt := v_cnt + 1; end if; end;
    begin perform * from public.link_my_pokedex_copy(v_c1, pos1, a3, null); exception when others then if sqlstate = '55000' and sqlerrm = 'EXCEPTION_CONFIRMATION_REQUIRED' then v_cnt := v_cnt + 1; end if; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','5.1','ok',
      v_cnt = 2 and not exists (select 1 from public.collection_allocation ca where ca.physical_card_id = a3),
      'detail','divergência sem confirmação (false e NULL) → 55000 EXCEPTION_CONFIRMATION_REQUIRED; nada gravado: '||v_cnt||'/2');

    execute 'set local role authenticated';
    select * into v_rec from public.link_my_pokedex_copy(v_c1, pos1, a3, true);
    select g.is_satisfied into v_ok from public.get_my_pokedex_positions(v_c1, 'ALL', null, 500, 0) g where g.pokedex_position_id = pos152;
    execute 'reset role';
    res := res || jsonb_build_object('id','5.2','ok',
      v_rec.assignment_basis = 'USER_OVERRIDE' and v_rec.allocated_now and v_rec.pokedex_position_id = pos1
      and v_rec.satisfied_positions = 1 and v_rec.total_positions = v_n_pos and not v_ok
      and (select a.assigned_by_user_id from public.collection_pokedex_position_assignment a
             join public.collection_allocation ca on ca.id = a.collection_allocation_id where ca.physical_card_id = a3) = p_user_a
      and (select cps.pokemon_species_id from public.card_primary_species cps where cps.card_id = k3) = sp152,
      'detail','confirmada: alocação + USER_OVERRIDE em #1 numa chamada (autor = A); #152 continua faltando; espécie principal de k3 inalterada');

    execute 'set local role authenticated';
    select * into v_rec from public.link_my_pokedex_copy(v_c1, pos1, a3, true);
    execute 'reset role';
    res := res || jsonb_build_object('id','5.3','ok',
      v_rec.assignment_basis = 'USER_OVERRIDE' and not v_rec.allocated_now
      and (select count(*) from public.collection_allocation ca where ca.collection_id = v_c1) = 2
      and (select count(*) from public.collection_pokedex_position_assignment a
             join public.collection_allocation ca on ca.id = a.collection_allocation_id where ca.collection_id = v_c1) = 2,
      'detail','repetir a mesma chamada: sem nova escrita (allocated_now = false), 2 alocações e 2 vínculos');

    execute 'set local role authenticated';
    v_err := '';
    begin perform * from public.link_my_pokedex_copy(v_c1, pos7, a4, true); exception when others then v_err := sqlstate||' '||sqlerrm; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','5.4','ok',
      v_err = '55000 COPY_IN_OTHER_COLLECTION'
      and (select ca.collection_id from public.collection_allocation ca where ca.physical_card_id = a4) = v_f,
      'detail','exemplar em outra coleção → '||v_err||'; continua na Coleção livre (nada movido)');

    execute 'set local role authenticated';
    v_err := ''; v_msg := ''; v_snap := '';
    begin perform * from public.link_my_pokedex_copy(v_c1, pos7, b1, true); exception when others then v_err := sqlstate||' '||sqlerrm; end;
    begin perform * from public.link_my_pokedex_copy(v_c1, gen_random_uuid(), a5, true); exception when others then v_msg := sqlstate||' '||sqlerrm; end;
    begin perform * from public.link_my_pokedex_copy(gen_random_uuid(), pos7, a5, true); exception when others then v_snap := sqlstate||' '||sqlerrm; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','5.5','ok',
      v_err = 'P0002 COPY_NOT_FOUND' and v_msg = '22023 POSITION_NOT_IN_SCOPE' and v_snap = 'P0002 COLLECTION_NOT_FOUND'
      and not exists (select 1 from public.collection_allocation ca where ca.physical_card_id in (b1, a5)),
      'detail','exemplar de B → '||v_err||'; posição inexistente → '||v_msg||'; coleção inexistente → '||v_snap||'; nada gravado');

    execute 'set local role authenticated';
    select * into v_rec from public.link_my_pokedex_copy(v_c1, pos7, a2, true);
    select g.acervo_state into v_msg from public.get_my_pokedex_positions(v_c1, 'ALL', null, 500, 0) g where g.pokedex_position_id = pos7;
    execute 'reset role';
    res := res || jsonb_build_object('id','5.6','ok',
      v_rec.assignment_basis = 'USER_OVERRIDE' and v_rec.satisfied_positions = 2 and v_msg = 'OWNED'
      and (select a.pokedex_position_id from public.collection_pokedex_position_assignment a
             join public.collection_allocation ca on ca.id = a.collection_allocation_id where ca.physical_card_id = a2) = pos7
      and (select count(*) from public.collection_pokedex_position_assignment a
             join public.collection_allocation ca on ca.id = a.collection_allocation_id
            where ca.collection_id = v_c1 and a.pokedex_position_id = pos1) = 2,
      'detail','carta da espécie #1 confirmada em #7: o progresso conta #7 (2 conquistadas); o vínculo automático da 6119 em #1 foi substituído na mesma transação');

    execute 'set local role authenticated';
    v_err := '';
    begin perform * from public.link_my_pokedex_copy(v_c1, pos4, a2, true); exception when others then v_err := sqlstate||' '||sqlerrm; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','5.7','ok',
      v_err = '55000 COPY_ALREADY_LINKED'
      and (select a.pokedex_position_id from public.collection_pokedex_position_assignment a
             join public.collection_allocation ca on ca.id = a.collection_allocation_id where ca.physical_card_id = a2) = pos7,
      'detail','exemplar já vinculado a outra posição → '||v_err||'; vínculo em #7 preservado (mover nunca é implícito)');

    -- 6. Gerenciar ---------------------------------------------------------------
    execute 'set local role authenticated';
    select max(c.total_count),
           count(*) filter (where c.physical_card_id = a1 and c.assignment_basis = 'SPECIES_MATCH' and c.card_species_number = 1),
           count(*) filter (where c.physical_card_id = a3 and c.assignment_basis = 'USER_OVERRIDE' and c.card_species_number = 152)
      into v_cnt, v_cnt2, v_cnt3
      from public.get_my_pokedex_position_copies(v_c1, pos1) c;
    res := res || jsonb_build_object('id','6.1','ok',
      v_cnt = 2 and v_cnt2 = 1 and v_cnt3 = 1,
      'detail','vínculos de #1: a1 (SPECIES_MATCH) e a3 (USER_OVERRIDE, carta da espécie #152)');

    perform public.set_pokedex_position_primary_representative(
      (select c.collection_allocation_id from public.get_my_pokedex_position_copies(v_c1, pos1) c where c.physical_card_id = a3));
    select * into v_rec from public.get_my_pokedex_position_copies(v_c1, pos1);
    select g.representative_card_name into v_msg from public.get_my_pokedex_positions(v_c1, 'OWNED', null, 500, 0) g where g.pokedex_position_id = pos1;
    res := res || jsonb_build_object('id','6.2','ok',
      v_rec.physical_card_id = a3 and v_rec.is_representative and v_msg = 'PX Três',
      'detail','6125: a3 vira representante — primeiro na lista (5209) e na grade (5204: '||coalesce(v_msg,'∅')||')');

    execute 'reset role';
    select concat_ws('|', pc.card_variant_id, pc.language_id, pc.inventory_id, pc.storage_container_id) into v_snap
      from public.physical_card pc where pc.id = a3;
    execute 'set local role authenticated';
    perform public.remove_pokedex_position_assignment(a3);
    select count(*) into v_cnt from public.get_my_pokedex_link_candidates(v_c1, pos1, 'ACERVO', null, 48, 0) c where c.physical_card_id = a3 and c.in_this_collection;
    select * into v_sum from public.collection_completion_summary(v_c1);
    execute 'reset role';
    select concat_ws('|', pc.card_variant_id, pc.language_id, pc.inventory_id, pc.storage_container_id) into v_snap2
      from public.physical_card pc where pc.id = a3;
    res := res || jsonb_build_object('id','6.3','ok',
      (select ca.collection_id from public.collection_allocation ca where ca.physical_card_id = a3) = v_c1
      and not exists (select 1 from public.collection_pokedex_position_assignment a join public.collection_allocation ca on ca.id = a.collection_allocation_id where ca.physical_card_id = a3)
      and not exists (select 1 from public.collection_pokedex_position_primary_representative pr where pr.collection_id = v_c1)
      and v_cnt = 1 and v_sum.satisfied_positions = 2 and v_snap = v_snap2,
      'detail','retirar o vínculo (6124): a3 continua NA coleção, sem posição e sem representante; volta como candidato "nesta coleção"; exemplar físico idêntico; progresso 2');

    execute 'set local role authenticated';
    perform public.deallocate_physical_cards_from_collection(v_c1, array[a2]);
    select * into v_sum from public.collection_completion_summary(v_c1);
    execute 'reset role';
    res := res || jsonb_build_object('id','6.4','ok',
      not exists (select 1 from public.collection_allocation ca where ca.physical_card_id = a2)
      and exists (select 1 from public.physical_card pc where pc.id = a2 and pc.inventory_id = v_inv_a)
      and v_sum.satisfied_positions = 1,
      'detail','tirar da coleção (5047): a2 sai da coleção e o vínculo em #7 cai junto; a carta continua no acervo; progresso 1');

    -- 7. Lote (5211 + 5046) ------------------------------------------------------
    execute 'set local role authenticated';
    select array_agg(b.pokedex_position_id), array_agg(b.physical_card_id), max(b.eligible_count), max(b.missing_total), max(b.total_count)
      into v_ids, v_ids2, v_cnt, v_cnt2, v_cnt3
      from public.get_my_pokedex_bulk_link_preview(v_c1, null) b;
    res := res || jsonb_build_object('id','7.1','ok',
      v_ids = array[pos4] and v_ids2 = array[a6] and v_cnt = 1 and v_cnt2 = v_n_pos - 1 and v_cnt3 = 1,
      'detail','prévia: só #4 (a6 livre; a4 está em outra coleção; #1 já conquistada; a3 está na coleção, não livre); faltam '||coalesce(v_cnt2::text,'∅'));

    perform public.allocate_physical_cards_to_collection(v_c1, array[a6]);
    select count(*) into v_cnt from public.get_my_pokedex_bulk_link_preview(v_c1, null);
    select * into v_sum from public.collection_completion_summary(v_c1);
    execute 'reset role';
    res := res || jsonb_build_object('id','7.2','ok',
      v_cnt = 0 and v_sum.satisfied_positions = 2
      and (select a.assignment_basis from public.collection_pokedex_position_assignment a join public.collection_allocation ca on ca.id = a.collection_allocation_id where ca.physical_card_id = a6) = 'SPECIES_MATCH',
      'detail','confirmação pela 5046 → 6119 vincula #4 (SPECIES_MATCH); prévia vazia; progresso 2');

    res := res || jsonb_build_object('id','7.3','ok',
      (select count(*) from public.collection_pokedex_position_assignment a join public.collection_allocation ca on ca.id = a.collection_allocation_id
        where ca.collection_id = v_c1 and a.assignment_basis = 'USER_OVERRIDE') = 0
      and (select count(*) from public.collection_pokedex_position_assignment a join public.collection_allocation ca on ca.id = a.collection_allocation_id
        where ca.collection_id = v_c1 and a.assignment_basis = 'SPECIES_MATCH') = 2,
      'detail','o lote nunca cria vínculo excepcional: 0 USER_OVERRIDE, 2 SPECIES_MATCH (a1, a6)');

    -- 8. Isolamento e arquivada --------------------------------------------------
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select count(*) into v_cnt from public.get_my_pokedex_link_candidates(v_c1, pos1, 'ACERVO', null, 48, 0);
    select count(*) into v_cnt2 from public.get_my_pokedex_position_copies(v_c1, pos1);
    select count(*) into v_cnt3 from public.get_my_pokedex_bulk_link_preview(v_c1, null);
    v_err := '';
    begin perform * from public.link_my_pokedex_copy(v_c1, pos7, b1, true); exception when others then v_err := sqlstate||' '||sqlerrm; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','8.1','ok',
      v_cnt = 0 and v_cnt2 = 0 and v_cnt3 = 0 and v_err = 'P0002 COLLECTION_NOT_FOUND'
      and not exists (select 1 from public.collection_allocation ca where ca.physical_card_id = b1),
      'detail','B na coleção de A: candidatos, vínculos e prévia vazios; vínculo → '||v_err||' (igual a inexistente)');

    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.archive_collection(v_c1);
    v_err := '';
    begin perform * from public.link_my_pokedex_copy(v_c1, pos7, a5, true); exception when others then v_err := sqlstate||' '||sqlerrm; end;
    select count(*) into v_cnt from public.get_my_pokedex_link_candidates(v_c1, pos7, 'ACERVO', null, 48, 0);
    select count(*) into v_cnt2 from public.get_my_pokedex_bulk_link_preview(v_c1, null);
    select count(*) into v_cnt3 from public.get_my_pokedex_position_copies(v_c1, pos1);
    execute 'reset role';
    res := res || jsonb_build_object('id','8.2','ok',
      v_err = '55000 COLLECTION_ARCHIVED' and v_cnt = 0 and v_cnt2 = 0 and v_cnt3 = 1,
      'detail','arquivada: vínculo recusado ('||v_err||'), candidatos e prévia vazios, vínculos existentes legíveis');

    raise exception 'MS846' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MS846' then
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
      and (select count(*) from public.collection_pokedex_position_assignment) = b_asg
      and (select count(*) from public.collection_pokedex_position_primary_representative) = b_rep
      and current_user = session_user,
    'detail','resíduo zero (usuários, coleções, locais, pedidos, alocações, vínculos, representantes, cartas, espécie principal) e papel restaurado');
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
  status := case when passes = n and n = 27 then 'PASS' else 'FAIL' end;
  detail := format('%s/%s PASS (esperado 27)', passes, n);
  return next;
end;
$fn$;

select * from pg_temp.ms_5846_validate();
