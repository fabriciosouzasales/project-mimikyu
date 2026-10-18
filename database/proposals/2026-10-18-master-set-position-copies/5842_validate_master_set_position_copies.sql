/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5842 - Harness: get_my_master_set_position_copies (5199)
              estrutura, segurança, elegibilidade, paginação, isolamento,
              coerência com a grade e preservação
Versão......: 1.1 (READINESS-01: casos funcionais com fixture sintética;
              substitui a v1.0, só estrutural)
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-18, após a 5199
              (ledger 20261018204909): GATE PASS 30/30, 99.1 resíduo zero.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-18 (MASTER-SET-POSITION-COPIES-READINESS-01)

Protocolo (o mesmo da 5836, já executado no LIVE): um único statement
no SQL Editor; usuários efêmeros A e B; catálogo SINTÉTICO próprio
(expansão, Set, cartas e variantes criados e desfeitos na mesma
transação — nenhum dado real de catálogo, acervo ou coleção é tocado);
a sentinela MS842 desfaz tudo; a seção 99 prova resíduo zero. Nenhuma
leitura de dado real além das contagens de linha de base.

Catálogo sintético (Set S, base 3, total 5):
  c1 001  Padrão (padrão) · Padrão 1ª Edição · Reverse · Reverse Liga
  c2 002  Holo (padrão)                     → sem posição no objetivo
  c3 003  Padrão (padrão)
  c4 004  Gold (padrão) · Cosmos            → secreta sem acabamento escolhido: posição genérica
  c5 005  Padrão (padrão)                   → secreta com acabamento escolhido: posição (c5, Padrão)
Objetivo de v_ms (A): {Padrão, Reverse}. Posições esperadas: c1P, c1R,
c3P, c4 genérica, c5P = 5.

Exemplares de A:
  a1  c1 Padrão           pt-BR  local v_box   livre
  a10 c1 Padrão           pt-BR                livre
  a11 c1 Padrão           pt-BR                livre
  a2  c1 Padrão 1ª Ed.    en                   livre      (mesma posição c1P)
  a3  c1 Reverse Liga     pt-BR                livre      (posição c1R)
  a4  c1 Reverse          pt-BR                vinculado a v_ms
  a5  c2 Holo             pt-BR                livre      (sem posição)
  a6  c4 Gold             pt-BR                livre      (genérica)
  a7  c4 Cosmos           en                   livre      (genérica)
  a8  c3 Padrão           pt-BR                vinculado à Coleção livre v_free
  a12 c5 Padrão           pt-BR                livre      (c5P)
Exemplar de B: b1 c1 Padrão pt-BR, livre, no acervo de B.

Seções:
  0.x estrutura, privilégios, retorno mínimo
  1.x anon → 42501            2.x sem identidade → 28000; página/posição inválidas → 22023
  3.x elegibilidade (acabamento, secreta genérica e específica, idioma,
      edição, impressão, já vinculado, fora do objetivo)
  4.x coerência com a grade (5189/5198): posições não multiplicam e
      total = copies_available em todas as posições
  5.x paginação e ordem determinística
  6.x isolamento (outro usuário, coleção alheia/arquivada/livre/padrão/inexistente)
  7.x só leitura e fluxo de vínculo pela 5046
  99.1 resíduo zero
GATE: todas PASS e n = total esperado.
================================================================
*/

create or replace function pg_temp.ms_5842_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  f_pc  oid := to_regprocedure('public.get_my_master_set_position_copies(uuid,uuid,uuid,integer,integer)');
  p_user_a uuid := gen_random_uuid();
  p_user_b uuid := gen_random_uuid();
  v_sfx    text := substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
  v_game uuid; v_rar uuid; v_cat uuid; v_pt uuid; v_en uuid; v_fe uuid; v_lg uuid;
  t_std uuid; t_holo uuid; t_rev uuid; t_gold uuid; t_cos uuid;
  v_exp uuid := gen_random_uuid(); v_set uuid := gen_random_uuid();
  c1 uuid := gen_random_uuid(); c2 uuid := gen_random_uuid(); c3 uuid := gen_random_uuid();
  c4 uuid := gen_random_uuid(); c5 uuid := gen_random_uuid();
  v_c1p uuid := gen_random_uuid(); v_c1pfe uuid := gen_random_uuid(); v_c1r uuid := gen_random_uuid();
  v_c1rl uuid := gen_random_uuid(); v_c2h uuid := gen_random_uuid(); v_c3p uuid := gen_random_uuid();
  v_c4g uuid := gen_random_uuid(); v_c4c uuid := gen_random_uuid(); v_c5p uuid := gen_random_uuid();
  v_inv_a uuid; v_inv_b uuid;
  a1 uuid; a2 uuid; a3 uuid; a4 uuid; a5 uuid; a6 uuid; a7 uuid; a8 uuid; a10 uuid; a11 uuid; a12 uuid; b1 uuid;
  v_ms uuid; v_sd uuid; v_arch uuid; v_free uuid; v_box uuid; v_b uuid; v_box_name text;
  v_ids uuid[]; v_ids2 uuid[]; v_ids3 uuid[]; v_oracle uuid[];
  v_cnt bigint; v_cnt2 bigint; v_tot bigint; v_tot2 bigint; v_ok boolean; v_err text;
  v_fp text; v_fp2 text; v_rec record; v_label_a2 text;
  b_us bigint; b_co bigint; b_ca bigint; b_pc bigint; b_fn bigint; b_card bigint; b_cv bigint; b_cs bigint; b_ex bigint; b_sc bigint;
  res jsonb := '[]'::jsonb; r jsonb; n integer := 0; passes integer := 0;
begin
  -- 0. Estrutura ------------------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    f_pc is not null
    and exists (select 1 from pg_proc p where p.oid = f_pc
                and p.prosecdef and p.provolatile = 's' and p.proconfig = array['search_path=""']),
    'detail','5199 existe com a assinatura do contrato; SECURITY DEFINER, STABLE, search_path vazio');
  res := res || jsonb_build_object('id','0.2','ok',
    f_pc is not null
    and has_function_privilege('authenticated', f_pc, 'EXECUTE')
    and not has_function_privilege('anon', f_pc, 'EXECUTE')
    and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = f_pc and a.grantee = 0),
    'detail','EXECUTE só authenticated; anon e PUBLIC sem acesso');
  res := res || jsonb_build_object('id','0.3','ok',
    f_pc is not null
    and pg_get_function_result(f_pc) = 'TABLE(physical_card_id uuid, variant_label text, is_default_variant boolean, language_code text, language_name text, storage_name text, added_at timestamp with time zone, total_count bigint)',
    'detail','retorno mínimo: único identificador é physical_card_id (sem card_variant_id, inventário ou ids de local)');

  if f_pc is null then
    res := res || jsonb_build_object('id','X.0','ok', false, 'detail','5199 ausente — aplique a 5199 antes deste harness');
  else
  -- linha de base -------------------------------------------------------------
  select count(*) into b_us from auth.users;
  select count(*) into b_co from public.collection;
  select count(*) into b_ca from public.collection_allocation;
  select count(*) into b_pc from public.physical_card;
  select count(*) into b_fn from public.collection_master_set_finish;
  select count(*) into b_card from public.card;
  select count(*) into b_cv from public.card_variant;
  select count(*) into b_cs from public.card_set;
  select count(*) into b_ex from public.expansion;
  select count(*) into b_sc from public.storage_container;

  begin
    -- Fixture (como dono do banco) --------------------------------------------
    select g.id into v_game from public.game g where g.code = 'POKEMON';
    select r.id into v_rar from public.rarity r where r.game_id = v_game and r.code = 'COMMON';
    select c.id into v_cat from public.card_category c where c.game_id = v_game and c.code = 'POKEMON';
    select l.id into v_pt from public.language l where l.code = 'pt-BR';
    select l.id into v_en from public.language l where l.code = 'en';
    select p.id into v_fe from public.card_printing_profile p where p.code = 'FIRST_EDITION';
    select p.id into v_lg from public.card_edition_context_profile p where p.code = 'PROGRAM_LEAGUE';
    select t.id into t_std  from public.card_variant_type t where t.game_id = v_game and t.code = 'STANDARD';
    select t.id into t_holo from public.card_variant_type t where t.game_id = v_game and t.code = 'HOLO';
    select t.id into t_rev  from public.card_variant_type t where t.game_id = v_game and t.code = 'REVERSE_HOLO';
    select t.id into t_gold from public.card_variant_type t where t.game_id = v_game and t.code = 'GOLD_HOLO';
    select t.id into t_cos  from public.card_variant_type t where t.game_id = v_game and t.code = 'COSMOS_HOLO';

    insert into public.expansion (id, game_id, code, name, release_order)
    values (v_exp, v_game, 'ZZPC5842_'||upper(v_sfx), 'PC 5842 '||v_sfx,
            (select coalesce(max(e.release_order), 0) + 1 from public.expansion e where e.game_id = v_game));
    insert into public.card_set (id, expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_set, v_exp, 'ZZPC-'||upper(v_sfx), 'PC 5842 S', 'REGULAR', 1, 3, 5);
    insert into public.card (id, card_set_id, rarity_id, category_id, collector_number, collector_total, collector_order, name)
    values (c1, v_set, v_rar, v_cat, '001', 3, 1, 'PC Um'),
           (c2, v_set, v_rar, v_cat, '002', 3, 2, 'PC Dois'),
           (c3, v_set, v_rar, v_cat, '003', 3, 3, 'PC Três'),
           (c4, v_set, v_rar, v_cat, '004', 3, 4, 'PC Quatro Secreta'),
           (c5, v_set, v_rar, v_cat, '005', 3, 5, 'PC Cinco Secreta');
    insert into public.card_variant (id, card_id, variant_type_id, printing_profile_id, edition_context_profile_id, variant_order, is_default, is_active)
    values (v_c1p,   c1, t_std,  null, null, 1, true,  true),
           (v_c1pfe, c1, t_std,  v_fe, null, 2, false, true),
           (v_c1r,   c1, t_rev,  null, null, 3, false, true),
           (v_c1rl,  c1, t_rev,  null, v_lg, 4, false, true),
           (v_c2h,   c2, t_holo, null, null, 1, true,  true),
           (v_c3p,   c3, t_std,  null, null, 1, true,  true),
           (v_c4g,   c4, t_gold, null, null, 1, true,  true),
           (v_c4c,   c4, t_cos,  null, null, 2, false, true),
           (v_c5p,   c5, t_std,  null, null, 1, true,  true);

    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    values (p_user_a, 'authenticated', 'authenticated', 'pc5842-a-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'pc5842a_'||v_sfx, 'display_name', 'PC 5842 A'), now(), now()),
           (p_user_b, 'authenticated', 'authenticated', 'pc5842-b-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'pc5842b_'||v_sfx, 'display_name', 'PC 5842 B'), now(), now());
    select i.id into v_inv_a from public.inventory i where i.owner_user_id = p_user_a;
    select i.id into v_inv_b from public.inventory i where i.owner_user_id = p_user_b;

    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_c1p,   v_pt, v_inv_a) returning id into a1;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_c1pfe, v_en, v_inv_a) returning id into a2;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_c1rl,  v_pt, v_inv_a) returning id into a3;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_c1r,   v_pt, v_inv_a) returning id into a4;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_c2h,   v_pt, v_inv_a) returning id into a5;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_c4g,   v_pt, v_inv_a) returning id into a6;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_c4c,   v_en, v_inv_a) returning id into a7;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_c3p,   v_pt, v_inv_a) returning id into a8;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_c1p,   v_pt, v_inv_a) returning id into a10;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_c1p,   v_pt, v_inv_a) returning id into a11;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_c5p,   v_pt, v_inv_a) returning id into a12;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_c1p,   v_pt, v_inv_b) returning id into b1;

    -- coleções (como o próprio usuário, pelos contratos de produto)
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select c.collection_id, c.storage_container_id into v_ms, v_box
      from public.create_my_card_set_collection(gen_random_uuid(), v_set, 'PC 5842 Master', null) c;
    select c.collection_id into v_sd   from public.create_my_card_set_collection(gen_random_uuid(), v_set, 'PC 5842 Padrão', v_box) c;
    select c.collection_id into v_arch from public.create_my_card_set_collection(gen_random_uuid(), v_set, 'PC 5842 Arquivada', v_box) c;
    select c.collection_id into v_free from public.create_my_free_collection(gen_random_uuid(), 'PC 5842 Livre', v_box) c;
    perform public.allocate_physical_cards_to_collection(v_ms, array[a4]);
    perform public.allocate_physical_cards_to_collection(v_free, array[a8]);
    perform public.set_collection_completion_policy_to_master_set(v_ms, array[t_std, t_rev]);
    perform public.set_collection_completion_policy_to_master_set(v_arch, array[t_std, t_rev]);
    perform public.archive_collection(v_arch);
    execute 'reset role';

    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select c.collection_id into v_b from public.create_my_card_set_collection(gen_random_uuid(), v_set, 'PC 5842 B', null) c;
    perform public.set_collection_completion_policy_to_master_set(v_b, array[t_std, t_rev]);
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);

    -- local físico de a1 (para provar que o local é devolvido, nunca alterado)
    update public.physical_card set storage_container_id = v_box where id = a1;
    select sc.name into v_box_name from public.storage_container sc where sc.id = v_box;

    -- impressão digital do acervo sintético (variante, idioma, local, vínculo)
    select md5(string_agg(pc.id::text||pc.card_variant_id::text||pc.language_id::text||coalesce(pc.storage_container_id::text,'')
                          ||coalesce(ca.collection_id::text,'-'), ',' order by pc.id))
      into v_fp
    from public.physical_card pc left join public.collection_allocation ca on ca.physical_card_id = pc.id
    where pc.inventory_id in (v_inv_a, v_inv_b);

    -- Oráculos lidos como dono (catálogo tem RLS admin-only para authenticated):
    -- ordem documentada da 5199 e rótulo esperado de a2.
    select array_agg(pc.id order by cv.is_default desc, l.language_order, pc.created_at, pc.id) into v_oracle
      from public.physical_card pc
      join public.card_variant cv on cv.id = pc.card_variant_id
      join public.language l on l.id = pc.language_id
      where pc.id = any(array[a1, a2, a10, a11]);
    select concat_ws(' · ', t.name, p.name) into v_label_a2
      from public.card_variant_type t, public.card_printing_profile p
      where t.id = t_std and p.id = v_fe;

    res := res || jsonb_build_object('id','0.4','ok',
      v_game is not null and t_std is not null and t_rev is not null and t_gold is not null and t_cos is not null
      and t_holo is not null and v_fe is not null and v_lg is not null and v_en is not null
      and v_inv_a is not null and v_inv_b is not null and v_ms is not null and v_b is not null and v_box_name is not null
      and (select count(*) from public.collection_master_set_finish f where f.collection_id = v_ms) = 2
      and (select c.lifecycle_status from public.collection c where c.id = v_arch) <> 'ACTIVE',
      'detail','fixture sintética: 1 Set, 5 cartas, 9 variantes, 11 exemplares de A + 1 de B; v_ms e v_b em Master Set {Padrão, Reverse}; v_arch arquivada');

    -- 1. anon -----------------------------------------------------------------
    execute 'set local role anon';
    begin
      perform * from public.get_my_master_set_position_copies(v_ms, c1, t_std, 10, 0);
      v_err := 'executou';
    exception when others then v_err := sqlstate;
    end;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.1','ok', v_err = '42501', 'detail','anon recusado: '||v_err);

    -- 2. sem identidade e parâmetros inválidos ---------------------------------
    execute 'set local role authenticated';
    begin
      perform * from public.get_my_master_set_position_copies(v_ms, c1, t_std, 10, 0);
      v_err := 'executou';
    exception when others then v_err := sqlstate;
    end;
    execute 'reset role';
    res := res || jsonb_build_object('id','2.1','ok', v_err = '28000', 'detail','authenticated sem auth.uid() → 28000: '||v_err);

    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    v_cnt := 0;
    begin perform * from public.get_my_master_set_position_copies(v_ms, c1, t_std, 0, 0);   exception when others then if sqlstate = '22023' then v_cnt := v_cnt + 1; end if; end;
    begin perform * from public.get_my_master_set_position_copies(v_ms, c1, t_std, 101, 0); exception when others then if sqlstate = '22023' then v_cnt := v_cnt + 1; end if; end;
    begin perform * from public.get_my_master_set_position_copies(v_ms, c1, t_std, 10, -1); exception when others then if sqlstate = '22023' then v_cnt := v_cnt + 1; end if; end;
    begin perform * from public.get_my_master_set_position_copies(v_ms, c1, t_std, 10, 10001); exception when others then if sqlstate = '22023' then v_cnt := v_cnt + 1; end if; end;
    begin perform * from public.get_my_master_set_position_copies(v_ms, null, t_std, 10, 0); exception when others then if sqlstate = '22023' then v_cnt := v_cnt + 1; end if; end;
    res := res || jsonb_build_object('id','2.2','ok', v_cnt = 5,
      'detail','limite 0/101, offset -1/10001 e carta nula → 22023: '||v_cnt||'/5');

    -- 3. elegibilidade (como A) -----------------------------------------------
    select array_agg(g.physical_card_id), max(g.total_count) into v_ids, v_tot
      from public.get_my_master_set_position_copies(v_ms, c1, t_std, 100, 0) g;
    res := res || jsonb_build_object('id','3.1','ok',
      (select array_agg(x order by x) from unnest(v_ids) x) = (select array_agg(x order by x) from unnest(array[a1, a2, a10, a11]) x)
      and v_tot = 4,
      'detail','c1 Padrão: a1, a10, a11 (pt-BR) e a2 (1ª Edição, inglês) — impressão e idioma satisfazem a mesma posição; total 4');
    res := res || jsonb_build_object('id','3.2','ok',
      not (a3 = any(v_ids)) and not (a4 = any(v_ids)) and not (b1 = any(v_ids)) and not (a5 = any(v_ids)),
      'detail','c1 Padrão não traz Reverse (a3/a4), outro acabamento de outra carta (a5) nem exemplar de B (b1)');
    select array_agg(g.physical_card_id) into v_ids from public.get_my_master_set_position_copies(v_ms, c1, t_rev, 100, 0) g;
    res := res || jsonb_build_object('id','3.3','ok', v_ids = array[a3],
      'detail','c1 Reverse: só a3 (Reverse Liga — contexto de edição satisfaz); a4 já vinculado fica fora');
    select array_agg(g.physical_card_id) into v_ids from public.get_my_master_set_position_copies(v_ms, c4, null, 100, 0) g;
    res := res || jsonb_build_object('id','3.4','ok',
      (select array_agg(x order by x) from unnest(v_ids) x) = (select array_agg(x order by x) from unnest(array[a6, a7]) x),
      'detail','c4 secreta genérica: a6 (Gold, pt-BR) e a7 (Cosmos, inglês) — qualquer acabamento vale');
    select count(*) into v_cnt from public.get_my_master_set_position_copies(v_ms, c4, t_gold, 100, 0);
    select count(*) into v_cnt2 from public.get_my_master_set_position_copies(v_ms, c4, t_cos, 100, 0);
    res := res || jsonb_build_object('id','3.5','ok', v_cnt = 0 and v_cnt2 = 0,
      'detail','c4 com acabamento específico (Gold/Cosmos) não é posição do objetivo → zero linhas');
    select array_agg(g.physical_card_id) into v_ids from public.get_my_master_set_position_copies(v_ms, c5, t_std, 100, 0) g;
    select count(*) into v_cnt from public.get_my_master_set_position_copies(v_ms, c5, null, 100, 0);
    res := res || jsonb_build_object('id','3.6','ok', v_ids = array[a12] and v_cnt = 0,
      'detail','c5 secreta com Padrão escolhido: posição (c5, Padrão) traz a12; posição genérica de c5 não existe');
    select count(*) into v_cnt from public.get_my_master_set_position_copies(v_ms, c2, t_holo, 100, 0);
    select count(*) into v_cnt2 from public.get_my_master_set_position_copies(v_ms, c2, null, 100, 0);
    res := res || jsonb_build_object('id','3.7','ok', v_cnt = 0 and v_cnt2 = 0,
      'detail','c2 (só Holo, fora do objetivo; não secreta): nenhuma posição → zero linhas, mesmo com exemplar livre a5');
    select count(*) into v_cnt from public.get_my_master_set_position_copies(v_ms, c3, t_std, 100, 0);
    res := res || jsonb_build_object('id','3.8','ok', v_cnt = 0,
      'detail','c3 Padrão: o único exemplar (a8) está vinculado a outra coleção (Coleção livre) → excluído');
    select * into v_rec from public.get_my_master_set_position_copies(v_ms, c1, t_std, 100, 0) g where g.physical_card_id = a1;
    res := res || jsonb_build_object('id','3.9','ok',
      v_rec.storage_name = v_box_name and v_rec.language_code = 'pt-BR' and v_rec.is_default_variant
      and v_rec.variant_label is not null,
      'detail','a1: local, idioma e versão devolvidos como estão gravados');
    select * into v_rec from public.get_my_master_set_position_copies(v_ms, c1, t_std, 100, 0) g where g.physical_card_id = a2;
    res := res || jsonb_build_object('id','3.10','ok',
      v_rec.language_code = 'en' and not v_rec.is_default_variant
      and v_rec.variant_label = v_label_a2
      and v_rec.storage_name is null,
      'detail','a2: rótulo "acabamento · impressão", inglês, sem local');

    -- 4. coerência com a grade --------------------------------------------------
    select count(*) into v_cnt from public.get_my_master_set_positions(v_ms, 'ALL', 500, 0);
    res := res || jsonb_build_object('id','4.1','ok', v_cnt = 5,
      'detail','grade: 5 posições (c1P, c1R, c3P, c4 genérica, c5P) — idioma, impressão e contexto não multiplicam: '||v_cnt);
    v_ok := true;
    for v_rec in select g.card_id, g.variant_type_id, g.copies_available from public.get_my_master_set_positions(v_ms, 'ALL', 500, 0) g loop
      select coalesce(max(x.total_count), 0) into v_tot
        from public.get_my_master_set_position_copies(v_ms, v_rec.card_id, v_rec.variant_type_id, 100, 0) x;
      select count(*) into v_cnt2
        from public.get_my_master_set_position_copies(v_ms, v_rec.card_id, v_rec.variant_type_id, 100, 0) x;
      if v_tot <> v_rec.copies_available or v_cnt2 <> v_rec.copies_available then v_ok := false; end if;
    end loop;
    res := res || jsonb_build_object('id','4.2','ok', v_ok,
      'detail','em todas as posições: total_count e linhas devolvidas = copies_available da grade (5198)');

    -- 5. paginação e ordem ------------------------------------------------------
    select array_agg(x.physical_card_id order by x.ord) into v_ids
      from public.get_my_master_set_position_copies(v_ms, c1, t_std, 100, 0) with ordinality x(physical_card_id, variant_label, is_default_variant, language_code, language_name, storage_name, added_at, total_count, ord);
    select array_agg(x.physical_card_id order by x.ord) into v_ids2
      from public.get_my_master_set_position_copies(v_ms, c1, t_std, 100, 0) with ordinality x(physical_card_id, variant_label, is_default_variant, language_code, language_name, storage_name, added_at, total_count, ord);
    -- v_oracle: ordem documentada, calculada como dono na fixture
    res := res || jsonb_build_object('id','5.1','ok', v_ids = v_ids2 and v_ids = v_oracle and v_ids[4] = a2,
      'detail','ordem determinística (duas leituras iguais) e igual ao oráculo: padrão primeiro, idioma, mais antigo, id; a2 (não padrão) por último');
    select array_agg(x.physical_card_id order by x.ord), max(x.total_count) into v_ids2, v_tot
      from public.get_my_master_set_position_copies(v_ms, c1, t_std, 2, 0) with ordinality x(physical_card_id, variant_label, is_default_variant, language_code, language_name, storage_name, added_at, total_count, ord);
    select array_agg(x.physical_card_id order by x.ord), max(x.total_count) into v_ids3, v_tot2
      from public.get_my_master_set_position_copies(v_ms, c1, t_std, 2, 2) with ordinality x(physical_card_id, variant_label, is_default_variant, language_code, language_name, storage_name, added_at, total_count, ord);
    select count(*) into v_cnt from public.get_my_master_set_position_copies(v_ms, c1, t_std, 2, 4);
    res := res || jsonb_build_object('id','5.2','ok',
      v_ids2 || v_ids3 = v_ids and v_tot = 4 and v_tot2 = 4 and v_cnt = 0
      and cardinality(v_ids2) = 2 and cardinality(v_ids3) = 2,
      'detail','páginas de 2: [0..1] + [2..3] = lista completa, sem repetição nem lacuna; total_count 4 nas duas; offset 4 → vazio');

    -- 6. isolamento -------------------------------------------------------------
    select count(*) into v_cnt from public.get_my_master_set_position_copies(v_b, c1, t_std, 100, 0);
    select count(*) into v_cnt2 from public.get_my_master_set_position_copies(gen_random_uuid(), c1, t_std, 100, 0);
    res := res || jsonb_build_object('id','6.1','ok', v_cnt = 0 and v_cnt2 = 0,
      'detail','A lendo a coleção Master Set de B e uma coleção inexistente → zero linhas (mesma resposta)');
    select count(*) into v_cnt from public.get_my_master_set_position_copies(v_arch, c1, t_std, 100, 0);
    res := res || jsonb_build_object('id','6.2','ok', v_cnt = 0,
      'detail','coleção arquivada (Master Set) → zero linhas');
    select count(*) into v_cnt from public.get_my_master_set_position_copies(v_sd, c1, t_std, 100, 0);
    select count(*) into v_cnt2 from public.get_my_master_set_position_copies(v_free, c1, t_std, 100, 0);
    res := res || jsonb_build_object('id','6.3','ok', v_cnt = 0 and v_cnt2 = 0,
      'detail','coleção em Set padrão e Coleção livre → zero linhas');
    execute 'reset role';

    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select array_agg(g.physical_card_id) into v_ids from public.get_my_master_set_position_copies(v_b, c1, t_std, 100, 0) g;
    select count(*) into v_cnt from public.get_my_master_set_position_copies(v_ms, c1, t_std, 100, 0);
    execute 'reset role';
    res := res || jsonb_build_object('id','6.4','ok', v_ids = array[b1] and v_cnt = 0,
      'detail','B na própria coleção vê só b1 (nunca a1/a2/a10/a11); B na coleção de A → zero linhas');

    -- 7. só leitura e vínculo pela 5046 ----------------------------------------
    perform set_config('request.jwt.claims', '', true);
    select md5(string_agg(pc.id::text||pc.card_variant_id::text||pc.language_id::text||coalesce(pc.storage_container_id::text,'')
                          ||coalesce(ca.collection_id::text,'-'), ',' order by pc.id))
      into v_fp2
    from public.physical_card pc left join public.collection_allocation ca on ca.physical_card_id = pc.id
    where pc.inventory_id in (v_inv_a, v_inv_b);
    res := res || jsonb_build_object('id','7.1','ok', v_fp = v_fp2,
      'detail','depois de todas as leituras: exemplares de A e B com a mesma variante, idioma, local e vínculo');

    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.allocate_physical_cards_to_collection(v_ms, array[a1]);
    select array_agg(g.physical_card_id), max(g.total_count) into v_ids, v_tot
      from public.get_my_master_set_position_copies(v_ms, c1, t_std, 100, 0) g;
    select g.is_satisfied, g.copies_available into v_rec
      from public.get_my_master_set_positions(v_ms, 'ALL', 500, 0) g where g.card_id = c1 and g.variant_type_id = t_std;
    v_ok := v_ids is not null and not (a1 = any(v_ids)) and v_tot = 3 and v_rec.is_satisfied and v_rec.copies_available = 3;
    begin
      perform public.allocate_physical_cards_to_collection(v_ms, array[a1]);
      v_err := 'executou';
    exception when others then v_err := sqlstate;
    end;
    execute 'reset role';
    res := res || jsonb_build_object('id','7.2','ok', v_ok,
      'detail','vínculo de a1 pela 5046: some da leitura (3 restantes), posição c1 Padrão satisfeita, grade coerente');
    res := res || jsonb_build_object('id','7.3','ok', v_err <> 'executou',
      'detail','vincular a1 de novo é recusado pela 5046 (sem duplicar): '||v_err);
    res := res || jsonb_build_object('id','7.4','ok',
      (select pc.storage_container_id from public.physical_card pc where pc.id = a1) = v_box
      and (select pc.card_variant_id from public.physical_card pc where pc.id = a1) = v_c1p
      and (select pc.language_id from public.physical_card pc where pc.id = a1) = v_pt
      and (select count(*) from public.collection_allocation ca where ca.physical_card_id = a1) = 1,
      'detail','a1 vinculado mantém versão, idioma e local; um único vínculo');

    raise exception 'MS842' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MS842' then
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
      and (select count(*) from public.collection_master_set_finish) = b_fn
      and (select count(*) from public.card) = b_card
      and (select count(*) from public.card_variant) = b_cv
      and (select count(*) from public.card_set) = b_cs
      and (select count(*) from public.expansion) = b_ex
      and (select count(*) from public.storage_container) = b_sc
      and current_user = session_user,
    'detail','resíduo zero (usuários, coleções, vínculos, exemplares, acabamentos, locais, catálogo) e papel restaurado');
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
  status := case when passes = n and n = 30 then 'PASS' else 'FAIL' end;
  detail := format('%s/%s PASS (esperado 30)', passes, n);
  return next;
end;
$fn$;

select * from pg_temp.ms_5842_validate();
