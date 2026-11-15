/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5894 - Harness V1-13 · E1-D (5323, 5324, 5388): leituras de
              participante de Master Set, Pokédex e histórico do fichário;
              matriz OWNER/EDITOR/VIEWER/negados; não exposição do acervo;
              filtragem por coleção, D12, D13; resíduo zero
Versão......: 1.3 (2026-11-15, `D14 HISTORICAL AUTHORSHIP RECONCILIATION-04`: h21 — linha sem
              coleção de outro titular com item de CF). 1.2 (`D14 CONTRACT REFINEMENT AND MINIMAL CORRECTION-03`: eventos do
              titular sem coleção — visível com item de X, oculto sem item de X, misto,
              estrutural, não atribuído e sem autoria comprovada). 1.1 (`SHARED READS PRIVACY AND CONTRACT REVIEW-02`: evento do titular sem
              coleção, L01 com origem insuficiente, sinal parcial sem efeito de terceiros,
              agregados, transferência de âncora). 1.0
Status......: PROPOSTA — NÃO EXECUTADA. Prova DINÂMICA da E1-D. Sem ambiente
              isolado (C-244): executar SOMENTE sob protocolo controlado
              equivalente ao P1 da E1-A (transação explícita READ WRITE terminada
              em erro/ROLLBACK, conexão direta única, psql), depois de E1-A … E1-D,
              com autorização expressa e específica. Sem BEGIN/COMMIT próprios;
              não é comando pronto para produção.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-15

Pressupõe aplicadas: 5366–5388, 5323, 5324.

Usuários efêmeros: A titular · B EDITOR de CF, CM e CD · V VIEWER de CF, CM e CD ·
R EDITOR de CF removido · P convite pendente em CF · E EDITOR de CG · C estranho
(titular de X2).
Coleções de A:
  CF  livre, fichário 3×3 (bolsos esvaziados após a montagem); CG convidada do fichário de CF;
  CM  Master Set (STANDARD), fichário 3×3 (bolsos esvaziados); L01 com e sem origem;
  CD  Pokédex (geração da primeira espécie nacional), sem fichário.
Exemplares de A: f1 (k1, CF), g1 (k2, CG), ma1 (m1, CM), ma2 (m1, livre),
  d1 (k1, CD; espécie da posição P1), d2 (k1, livre). Depois (2.3/3.2): ma3 (m1,
  livre), d3 (k1, livre) e d4 (k1, CF) — mudam o acervo sem mudar a coleção.
Histórico: eventos gravados DIRETAMENTE na fixture (privilegiado) com a forma
  exata que a 5379 grava (coleção por item, item_collection_recorded), para
  exercitar cada ramo da regra de leitura:
  h1  CARD_PLACED  CF  atribuído  ator A  item CARD de CF com detalhe privado
  h2  CARDS_AUTO_ARRANGED CF atribuído: CARD de CG, CARD de CF, PAGE, CARD de CG
  h3  CARDS_AUTO_ARRANGED CF atribuído: só cartas de CG          → oculto (D13)
  h4  CARD_MOVED   CG  atribuído  item de CG                     → só para E
  h5  CARD_LEFT_BY_INVENTORY_EXIT (ACERVO) CF                     → oculto (E07)
  h6  COLLECTION_ATTACHED CF                                      → oculto (E17)
  h7  CARD_PLACED  CF  NÃO atribuído (anterior à 5379)            → oculto (D12)
  h8  PAGES_ADDED  CF  atribuído  item PAGE                       → visível
  h9  CARD_PLACED  CF  atribuído  ator B (EDITOR)                 → visível
  h10 CARD_PLACED  CF  atribuído  outro fichário (chave antiga)   → oculto
  h12 CATALOG_NOVELTIES_INCORPORATED com origem FICHARIO          → oculto (par)
  h13 CARD_PLACED  CF  titular C (linha forjada)                  → oculto
  h14 CARD_MOVED   SEM coleção (como o titular grava, 5273), ator A, item de CF → visível (D14)
  h17 CARD_MOVED   SEM coleção, ator A, só item de CG              → oculto a CF; visível a CG
  h18 CARDS_REMOVED SEM coleção, ator A, itens de CG e de CF       → só o item de cada coleção
  h19 PAGES_ADDED  SEM coleção, ator A, só PAGE (estrutural)       → oculto a todos os membros
  h20 CARD_MOVED   SEM coleção, ator NULO, item de CF              → oculto (autoria não comprovada)
  h16 CARD_MOVED   SEM coleção, ator A, NÃO atribuído (fichário de CM) → oculto (D12)
  h21 CARD_MOVED   SEM coleção, titular gravado C = ator C, item de CF, no fichário de CF
      (linha forjada: o domínio não a produz — 5032, 5229, 5379) → oculto
      (ator = titular gravado não basta: o titular do evento precisa ser o de X)
  h15 COLLECTION_ATTACHED CG NÃO atribuído (estrutura)            → não acende o aviso de CG
  l1  L01 de CM com linha de origem                               → visível (D12)
  l2  L01 de CM sem linha de origem                               → oculto (D12)
  l3  L01 de CM com linha de origem de OUTRA coleção (CF)         → oculto
  l4  L01 de CM com linha de origem de OUTRO fichário (o de CF)   → oculto

  select * from pg_temp.wh_5894_validate();
  -- GATE esperado: 29/29 PASS (28 verificações + F.2)

Limitações declaradas:
  L1 SET LOCAL ROLE prova o banco, não o JWT do PostgREST.
  L2 Concorrência (S8 concorrente, S10): PENDENTE — sessão única. A 6.1 prova
     revogação sequencial, não a corrida com uma leitura em andamento.
  L3 O histórico é gravado direto (não pelas funções instrumentadas), para cobrir
     ramos que o uso normal só produz com dados antigos (D12) ou com fichários
     de várias coleções (D13). A gravação real pela 5379 é provada na 5891.
  L4 Desempenho não é medido aqui (E1-E).
================================================================
*/

create or replace function pg_temp.wh_5894_as(p_user uuid)
returns void language plpgsql volatile as $as$
begin
  execute 'reset role';
  if p_user is null then
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
  else
    perform set_config('request.jwt.claim.sub', p_user::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
  end if;
end;
$as$;

create or replace function pg_temp.wh_5894_try(p_sql text)
returns text language plpgsql volatile as $try$
begin
  execute p_sql;
  return 'OK';
exception when others then
  return sqlerrm;
end;
$try$;

-- Assinatura comparável da grade Master Set (colunas comuns às leituras do titular e do participante).
create or replace function pg_temp.wh_5894_ms(p_coll uuid, p_filter text, p_shared boolean)
returns text language plpgsql volatile as $ms$
declare v text;
begin
  if p_shared then
    select coalesce(string_agg(concat_ws('|', x.card_id, x.variant_type_id, x.is_secret, x.image_path,
                                         x.is_satisfied, x.copies_in_collection, x.total_count), ',' order by x.card_id, x.variant_type_id), '<vazio>')
      into v from public.get_shared_master_set_positions(p_coll, p_filter, 500, 0) x;
  else
    select coalesce(string_agg(concat_ws('|', x.card_id, x.variant_type_id, x.is_secret, x.image_path,
                                         x.is_satisfied, x.copies_in_collection, x.total_count), ',' order by x.card_id, x.variant_type_id), '<vazio>')
      into v from public.get_my_master_set_positions(p_coll, p_filter, 500, 0) x;
  end if;
  return v;
end;
$ms$;

-- Assinatura comparável da grade Pokédex (colunas comuns).
create or replace function pg_temp.wh_5894_pd(p_coll uuid, p_filter text, p_gen text, p_shared boolean)
returns text language plpgsql volatile as $pd$
declare v text;
begin
  if p_shared then
    select coalesce(string_agg(concat_ws('|', x.pokedex_position_id, x.position_number, x.species_id, x.generation_code,
                                         x.species_artwork_path, x.is_satisfied, x.copies_in_collection,
                                         x.representative_card_name, x.representative_collector_number,
                                         x.representative_set_code, x.representative_image_path, x.total_count),
                               ',' order by x.position_number, x.pokedex_position_id), '<vazio>')
      into v from public.get_shared_pokedex_positions(p_coll, p_filter, p_gen, 500, 0) x;
  else
    select coalesce(string_agg(concat_ws('|', x.pokedex_position_id, x.position_number, x.species_id, x.generation_code,
                                         x.species_artwork_path, x.is_satisfied, x.copies_in_collection,
                                         x.representative_card_name, x.representative_collector_number,
                                         x.representative_set_code, x.representative_image_path, x.total_count),
                               ',' order by x.position_number, x.pokedex_position_id), '<vazio>')
      into v from public.get_my_pokedex_positions(p_coll, p_filter, p_gen, 500, 0) x;
  end if;
  return v;
end;
$pd$;

-- Histórico compartilhado inteiro (todas as páginas de 50) como texto: ids na ordem + JSON das linhas.
create or replace function pg_temp.wh_5894_hist(p_coll uuid)
returns text language plpgsql volatile as $hi$
declare v text;
begin
  select coalesce(string_agg(to_jsonb(x)::text, E'\n' order by x.occurred_at desc, x.event_id desc), '<vazio>')
    into v from public.get_shared_binder_activity(p_coll, null, null, null, 50) x;
  return v;
end;
$hi$;

create or replace function pg_temp.wh_5894_ids(p_coll uuid, p_categories text[] default null)
returns bigint[] language sql volatile as $ids$
  select coalesce(array_agg(x.event_id order by x.occurred_at desc, x.event_id desc), '{}')
  from public.get_shared_binder_activity(p_coll, p_categories, null, null, 50) x;
$ids$;

create or replace function pg_temp.wh_5894_ev(p_owner uuid, p_layout uuid, p_min integer, p_actor uuid, p_type text,
                                              p_source text, p_coll uuid, p_recorded boolean, p_summary jsonb default '{}'::jsonb)
returns bigint language sql volatile as $ev$
  insert into public.binder_activity_event
    (owner_user_id, layout_key, occurred_at, actor_user_id, event_type, source, collection_id, collection_name,
     binder_name, summary, item_collection_recorded)
  values (p_owner, p_layout, now() - (p_min || ' min')::interval, p_actor, p_type, p_source, p_coll,
          case when p_coll is null then null else 'NOME GRAVADO ' || p_type end, 'FICHARIO GRAVADO',
          p_summary, p_recorded)
  returning id;
$ev$;

create or replace function pg_temp.wh_5894_it(p_event bigint, p_ord integer, p_kind text, p_effect text, p_card uuid,
                                              p_name text, p_coll uuid, p_detail jsonb default null,
                                              p_page integer default null, p_row integer default null, p_col integer default null)
returns void language sql volatile as $it$
  insert into public.binder_activity_item
    (event_id, ordinal, item_kind, effect, card_id, card_name, collector_number, card_set_code,
     to_page, to_row, to_col, detail, collection_id)
  values (p_event, p_ord, p_kind, p_effect, p_card, p_name, case when p_card is null then null else '1' end,
          case when p_card is null then null else 'WHSET' end, p_page, p_row, p_col, p_detail, p_coll);
$it$;

create or replace function pg_temp.wh_5894_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
as $fn$
#variable_conflict use_column
declare
  u_a uuid := gen_random_uuid(); u_b uuid := gen_random_uuid(); u_v uuid := gen_random_uuid();
  u_r uuid := gen_random_uuid(); u_p uuid := gen_random_uuid(); u_e uuid := gen_random_uuid();
  u_c uuid := gen_random_uuid();
  v_sfx text := lower(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  v_game uuid; v_pt uuid; v_rar uuid; v_cat uuid; v_std uuid; v_exp uuid; v_set uuid; v_sm uuid; v_gen text;
  k1 uuid; k1s uuid; k2 uuid; k2s uuid; m1 uuid; m1s uuid; m2 uuid; v_pos uuid; v_spc uuid;
  v_inv_a uuid; v_ids uuid[]; f1 uuid; g1 uuid; ma1 uuid; ma2 uuid; d1 uuid; d2 uuid;
  v_bf uuid; v_bm uuid; v_bd uuid; v_bx uuid;
  v_cf uuid; v_cg uuid; v_cm uuid; v_cd uuid; v_x2 uuid;
  l_f uuid; l_m uuid; c_f uuid;
  m_b uuid; m_bm uuid; m_bd uuid; m_v uuid; m_vm uuid; m_vd uuid; m_r uuid; m_p uuid; m_e uuid;
  h1 bigint; h2 bigint; h3 bigint; h4 bigint; h5 bigint; h6 bigint; h7 bigint; h8 bigint; h9 bigint;
  h10 bigint; h12 bigint; h13 bigint; h14 bigint; h15 bigint; h16 bigint; h17 bigint; h18 bigint; h19 bigint; h20 bigint; h21 bigint; l1 bigint; l2 bigint; l3 bigint; l4 bigint;
  p record; q record; v_err text; v_txt text; v_txt2 text; v_s1 text; v_s2 text; v_s3 text; v_o1 text; v_o2 text;
  v_a bigint[]; v_b bigint[]; v_j jsonb; v_ok boolean; n integer; n2 integer; v_cnt_owner integer;
  pc0 text; alloc0 text;
  b_counts bigint[]; e_counts bigint[];
  res jsonb := '[]'::jsonb; r jsonb; cnt integer := 0; passes integer := 0;
  v_expected integer := 0;
begin
  -- 0. Estrutura ---------------------------------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    (select count(*) from pg_proc q
      where q.oid in (to_regprocedure('public.get_shared_master_set_positions(uuid, text, integer, integer)'),
                      to_regprocedure('public.get_shared_pokedex_positions(uuid, text, text, integer, integer)'),
                      to_regprocedure('public.get_shared_binder_activity(uuid, text[], timestamptz, bigint, integer)'),
                      to_regprocedure('public.get_shared_binder_activity_status(uuid)'))
        and q.prosecdef and q.proconfig = array['search_path=""'] and q.provolatile = 's'
        and has_function_privilege('authenticated', q.oid, 'EXECUTE')
        and not has_function_privilege('anon', q.oid, 'EXECUTE')
        and pg_get_function_result(q.oid) !~* '(copies_available|copies_elsewhere|acervo_state|summary|detail|collection_name|binder_name|actor_user_id|owner_user_id|layout_key|physical_card|storage|condition|email|username)') = 4,
    'detail','4 leituras novas: definer, search_path vazio, STABLE, só authenticated; nenhuma coluna de acervo, resumo, detalhe, nome gravado ou id interno no retorno');
  res := res || jsonb_build_object('id','0.2','ok',
    (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.collection_share_role(uuid)')) = 'efdb495b5b703e9f093eb0f49a1d0a5d'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.get_my_master_set_positions(uuid, text, integer, integer)')) = '8b85264a6c7224a6fde9c9bffb723335'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.get_my_pokedex_positions(uuid, text, text, integer, integer)')) = '79d2cd331031b5c98c64f2c43ecb077f'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.get_my_binder_activity(uuid, text[], timestamptz, bigint, integer)')) = 'fab40eb28280d7c62ca207642b35ff65'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)')) = 'f8cfba40e442e85056e7c8ce7954d4f4',
    'detail','5302, leituras do titular (5198, 5204, 5269) e gravação do histórico (5379) inalteradas');

  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.collection_membership), (select count(*) from public.collection_layout_page),
               (select count(*) from public.collection_layout_slot_assignment),
               (select count(*) from public.collection_layout_catalog_incorporation),
               (select count(*) from public.collection_pokedex_position_assignment),
               (select count(*) from public.binder_activity_event), (select count(*) from public.binder_activity_item),
               (select count(*) from public.card)]
    into b_counts;

  begin
    -- F. Fixture ---------------------------------------------------------------------------
    select g.id into v_game from public.game g where g.code = 'POKEMON';
    select l.id into v_pt from public.language l where l.code = 'pt-BR';
    select t.id into v_std from public.card_variant_type t where t.game_id = v_game and t.code = 'STANDARD';
    select c.id into v_cat from public.card_category c where c.game_id = v_game and c.code = 'POKEMON';
    select c0.rarity_id into v_rar
    from public.card c0 join public.card_set cs0 on cs0.id = c0.card_set_id
    join public.expansion e0 on e0.id = cs0.expansion_id where e0.game_id = v_game limit 1;
    select g.code, pp.id, pp.species_id into v_gen, v_pos, v_spc
    from public.pokedex dx
    join public.pokedex_position pp on pp.pokedex_id = dx.id
    join public.pokemon_species sp on sp.id = pp.species_id
    join public.pokemon_generation g on g.id = sp.generation_id
    where dx.code = 'NATIONAL' order by pp.position_number limit 1;
    if v_game is null or v_pt is null or v_std is null or v_cat is null or v_rar is null or v_pos is null then
      res := res || jsonb_build_object('id','F.1','ok', false, 'detail','pré-requisitos de catálogo ou Pokédex NATIONAL ausentes');
      raise exception 'MS894' using errcode = 'P0001';
    end if;
    insert into public.expansion (game_id, code, name, release_order)
    values (v_game, 'SR_' || upper(v_sfx), 'SR Harness ' || v_sfx,
            (select coalesce(max(x.release_order), 0) + 1000 from public.expansion x where x.game_id = v_game))
    returning id into v_exp;
    insert into public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_exp, 'SR' || upper(v_sfx), 'SR Set ' || v_sfx, 'REGULAR', 1, 2, 2) returning id into v_set;
    insert into public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_exp, 'SM' || upper(v_sfx), 'SM Set ' || v_sfx, 'REGULAR', 2, 2, 2) returning id into v_sm;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '1', 1, 'SR K1', true) returning id into k1;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '2', 2, 'SR K2 SEGREDO DE CG', true) returning id into k2;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_sm, v_rar, v_cat, '1', 1, 'SM 1', true) returning id into m1;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_sm, v_rar, v_cat, '2', 2, 'SM 2', true) returning id into m2;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k1, v_std, 1, true) returning id into k1s;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k2, v_std, 1, true) returning id into k2s;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (m1, v_std, 1, true) returning id into m1s;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (m2, v_std, 1, true);

    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    select u.id, 'authenticated', 'authenticated', 'wh894' || u.t || '_' || v_sfx || '@example.invalid',
           jsonb_build_object('username', 'wh894' || u.t || '_' || v_sfx, 'display_name', 'WH 5894 ' || upper(u.t)), now(), now()
    from (values (u_a, 'a'), (u_b, 'b'), (u_v, 'v'), (u_r, 'r'), (u_p, 'p'), (u_e, 'e'), (u_c, 'c')) u(id, t);
    insert into public.card_primary_species (card_id, pokemon_species_id, resolution_basis, resolved_by_user_id)
    values (k1, v_spc, 'EDITORIAL_RECONCILIATION', u_a);
    select i.id into v_inv_a from public.inventory i where i.owner_user_id = u_a;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, created_at)
    select v.cv, v_pt, v_inv_a, now() - (v.o || ' min')::interval
    from (values (k1s, 6), (k2s, 5), (m1s, 4), (m1s, 3), (k1s, 2), (k1s, 1)) v(cv, o);
    select array_agg(pc.id order by pc.created_at) into v_ids from public.physical_card pc where pc.inventory_id = v_inv_a;
    f1 := v_ids[1]; g1 := v_ids[2]; ma1 := v_ids[3]; ma2 := v_ids[4]; d1 := v_ids[5]; d2 := v_ids[6];

    perform pg_temp.wh_5894_as(u_a);
    select x.storage_container_id into v_bf from public.create_my_storage_container(gen_random_uuid(), 'BIN F 5894', 'BINDER') x;
    select x.storage_container_id into v_bm from public.create_my_storage_container(gen_random_uuid(), 'BIN M 5894', 'BINDER') x;
    select x.storage_container_id into v_bd from public.create_my_storage_container(gen_random_uuid(), 'BIN D 5894', 'BINDER') x;
    select x.collection_id into v_cf from public.create_my_free_collection(gen_random_uuid(), 'CF 5894', v_bf) x;
    select x.collection_id into v_cm from public.create_my_card_set_collection(gen_random_uuid(), v_sm, 'CM 5894', v_bm) x;
    select x.collection_id into v_cd from public.create_my_pokedex_collection(gen_random_uuid(), 'CD 5894', array[v_gen], v_bd) x;
    perform count(*) from public.set_collection_completion_policy_to_master_set(v_cm, array[v_std]);
    perform public.allocate_physical_cards_to_collection(v_cf, array[f1]);
    perform public.allocate_physical_cards_to_collection(v_cm, array[ma1]);
    -- Fichários montados como na 5893; a montagem (E01) é oculta aos membros e os bolsos são
    -- esvaziados em seguida (o histórico desta prova é o gravado abaixo).
    select * into p from public.preview_my_collection_binder(v_cf, 3, 3, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_cf, 3, 3, 'PRINCIPAL_ONLY', p.plan_token);
    select * into p from public.preview_my_collection_binder(v_cm, 3, 3, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_cm, 3, 3, 'PRINCIPAL_ONLY', p.plan_token);
    execute 'reset role';
    select l.id, l.storage_container_id into l_f, c_f from public.collection_layout l where l.collection_id = v_cf;
    select l.id into l_m from public.collection_layout l where l.collection_id = v_cm;
    delete from public.collection_layout_slot_assignment a using public.collection_layout_slot s, public.collection_layout_page p2
     where a.slot_id = s.id and s.page_id = p2.id and p2.layout_id in (l_f, l_m);
    perform pg_temp.wh_5894_as(u_a);
    select x.collection_id into v_cg from public.create_my_free_collection(gen_random_uuid(), 'CG 5894 SEGREDO', c_f) x;
    perform public.attach_my_collection_to_binder(v_cg, l_f);
    perform public.allocate_physical_cards_to_collection(v_cg, array[g1]);
    perform public.allocate_physical_cards_to_collection(v_cd, array[d1]);
    if not exists (select 1 from public.collection_pokedex_position_assignment a
                   join public.collection_allocation ca on ca.id = a.collection_allocation_id
                   where ca.physical_card_id = d1) then
      perform count(*) from public.set_pokedex_position_assignment(d1, v_pos, false);
    end if;
    m_b  := (public.invite_collection_member(v_cf, 'wh894b_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_bm := (public.invite_collection_member(v_cm, 'wh894b_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_bd := (public.invite_collection_member(v_cd, 'wh894b_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_v  := (public.invite_collection_member(v_cf, 'wh894v_' || v_sfx) ->> 'membership_id')::uuid;
    m_vm := (public.invite_collection_member(v_cm, 'wh894v_' || v_sfx) ->> 'membership_id')::uuid;
    m_vd := (public.invite_collection_member(v_cd, 'wh894v_' || v_sfx) ->> 'membership_id')::uuid;
    m_r  := (public.invite_collection_member(v_cf, 'wh894r_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_p  := (public.invite_collection_member(v_cf, 'wh894p_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_e  := (public.invite_collection_member(v_cg, 'wh894e_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    perform pg_temp.wh_5894_as(u_b);
    perform public.respond_collection_invite(m_b, true);
    perform public.respond_collection_invite(m_bm, true);
    perform public.respond_collection_invite(m_bd, true);
    perform pg_temp.wh_5894_as(u_v);
    perform public.respond_collection_invite(m_v, true);
    perform public.respond_collection_invite(m_vm, true);
    perform public.respond_collection_invite(m_vd, true);
    perform pg_temp.wh_5894_as(u_r); perform public.respond_collection_invite(m_r, true);
    perform pg_temp.wh_5894_as(u_e); perform public.respond_collection_invite(m_e, true);
    perform pg_temp.wh_5894_as(u_a); perform public.remove_collection_member(v_cf, m_r);
    perform pg_temp.wh_5894_as(u_c);
    select x.storage_container_id into v_bx from public.create_my_storage_container(gen_random_uuid(), 'BIN X 5894', 'BINDER') x;
    select x.collection_id into v_x2 from public.create_my_free_collection(gen_random_uuid(), 'X2 5894', v_bx) x;
    execute 'reset role';

    -- Histórico (gravação direta, forma da 5379; minutos atrás definem a ordem).
    h1  := pg_temp.wh_5894_ev(u_a, l_f, 100, u_a, 'CARD_PLACED', 'FICHARIO', v_cf, true, '{"cards":1}');
    perform pg_temp.wh_5894_it(h1, 1, 'CARD', 'PLACED', k1, 'SR K1', v_cf,
      jsonb_build_object('physical_card_id', f1, 'condition_code', 'NM', 'storage_container_id', c_f), 1, 1, 1);
    h2  := pg_temp.wh_5894_ev(u_a, l_f, 90, u_a, 'CARDS_AUTO_ARRANGED', 'FICHARIO', v_cf, true,
      jsonb_build_object('moved', 3, 'collections', 2, 'other_collection', v_cg));
    perform pg_temp.wh_5894_it(h2, 1, 'CARD', 'MOVED', k2, 'SR K2 SEGREDO DE CG', v_cg, jsonb_build_object('physical_card_id', g1), 1, 2, 1);
    perform pg_temp.wh_5894_it(h2, 2, 'CARD', 'MOVED', k1, 'SR K1', v_cf, jsonb_build_object('physical_card_id', f1), 1, 1, 2);
    perform pg_temp.wh_5894_it(h2, 3, 'PAGE', 'PAGE_ADDED', null, null, null, null, 2);
    perform pg_temp.wh_5894_it(h2, 4, 'CARD', 'MOVED', k2, 'SR K2 SEGREDO DE CG', v_cg, null, 1, 3, 1);
    h3  := pg_temp.wh_5894_ev(u_a, l_f, 85, u_a, 'CARDS_AUTO_ARRANGED', 'FICHARIO', v_cf, true);
    perform pg_temp.wh_5894_it(h3, 1, 'CARD', 'MOVED', k2, 'SR K2 SEGREDO DE CG', v_cg, null, 1, 2, 2);
    h4  := pg_temp.wh_5894_ev(u_a, l_f, 80, u_a, 'CARD_MOVED', 'FICHARIO', v_cg, true);
    perform pg_temp.wh_5894_it(h4, 1, 'CARD', 'MOVED', k2, 'SR K2 SEGREDO DE CG', v_cg, null, 1, 1, 3);
    h5  := pg_temp.wh_5894_ev(u_a, l_f, 75, u_a, 'CARD_LEFT_BY_INVENTORY_EXIT', 'ACERVO', v_cf, true);
    perform pg_temp.wh_5894_it(h5, 1, 'CARD', 'LEFT', k1, 'SR K1', v_cf);
    h6  := pg_temp.wh_5894_ev(u_a, l_f, 70, u_a, 'COLLECTION_ATTACHED', 'FICHARIO', v_cf, true);
    perform pg_temp.wh_5894_it(h6, 1, 'COLLECTION', 'ATTACHED', null, null, null);
    h7  := pg_temp.wh_5894_ev(u_a, l_f, 65, u_a, 'CARD_PLACED', 'FICHARIO', v_cf, false);
    perform pg_temp.wh_5894_it(h7, 1, 'CARD', 'PLACED', k1, 'SR K1', null, null, 1, 1, 1);
    h8  := pg_temp.wh_5894_ev(u_a, l_f, 60, u_a, 'PAGES_ADDED', 'FICHARIO', v_cf, true);
    perform pg_temp.wh_5894_it(h8, 1, 'PAGE', 'PAGE_ADDED', null, null, null, null, 2);
    h9  := pg_temp.wh_5894_ev(u_a, l_f, 50, u_b, 'CARD_PLACED', 'FICHARIO', v_cf, true);
    perform pg_temp.wh_5894_it(h9, 1, 'CARD', 'PLACED', k1, 'SR K1', v_cf, null, 1, 2, 2);
    h10 := pg_temp.wh_5894_ev(u_a, gen_random_uuid(), 45, u_a, 'CARD_PLACED', 'FICHARIO', v_cf, true);
    perform pg_temp.wh_5894_it(h10, 1, 'CARD', 'PLACED', k1, 'SR K1', v_cf, null, 1, 1, 1);
    h12 := pg_temp.wh_5894_ev(u_a, l_f, 40, u_a, 'CATALOG_NOVELTIES_INCORPORATED', 'FICHARIO', v_cf, true);
    perform pg_temp.wh_5894_it(h12, 1, 'RESERVATION', 'INCORPORATED', k1, 'SR K1', v_cf, null, 1, 3, 3);
    h13 := pg_temp.wh_5894_ev(u_c, l_f, 35, u_c, 'CARD_PLACED', 'FICHARIO', v_cf, true);
    perform pg_temp.wh_5894_it(h13, 1, 'CARD', 'PLACED', k1, 'SR K1', v_cf, null, 1, 1, 1);
    insert into public.collection_layout_catalog_incorporation (layout_id, collection_id, item_key)
    values (l_m, v_cm, m1::text || ':*');
    l1 := pg_temp.wh_5894_ev(u_a, l_m, 30, null, 'LEGACY_CATALOG_INCORPORATION', 'LEGADO', v_cm, false,
      jsonb_build_object('item_key', m1::text || ':*'));
    perform pg_temp.wh_5894_it(l1, 1, 'CARD', 'INCORPORATED', m1, 'SM 1', null);
    l2 := pg_temp.wh_5894_ev(u_a, l_m, 25, null, 'LEGACY_CATALOG_INCORPORATION', 'LEGADO', v_cm, false,
      jsonb_build_object('item_key', m2::text || ':*'));
    perform pg_temp.wh_5894_it(l2, 1, 'CARD', 'INCORPORATED', m2, 'SM 2', null);
    h14 := pg_temp.wh_5894_ev(u_a, l_f, 33, u_a, 'CARD_MOVED', 'FICHARIO', null, true);
    perform pg_temp.wh_5894_it(h14, 1, 'CARD', 'MOVED', k1, 'SR K1', v_cf, null, 1, 3, 3);
    h17 := pg_temp.wh_5894_ev(u_a, l_f, 31, u_a, 'CARD_MOVED', 'FICHARIO', null, true);
    perform pg_temp.wh_5894_it(h17, 1, 'CARD', 'MOVED', k2, 'SR K2 SEGREDO DE CG', v_cg, null, 2, 1, 1);
    h18 := pg_temp.wh_5894_ev(u_a, l_f, 29, u_a, 'CARDS_REMOVED', 'FICHARIO', null, true, '{"cards":2}');
    perform pg_temp.wh_5894_it(h18, 1, 'CARD', 'REMOVED', k2, 'SR K2 SEGREDO DE CG', v_cg, jsonb_build_object('physical_card_id', g1));
    perform pg_temp.wh_5894_it(h18, 2, 'CARD', 'REMOVED', k1, 'SR K1', v_cf, jsonb_build_object('physical_card_id', f1));
    h19 := pg_temp.wh_5894_ev(u_a, l_f, 28, u_a, 'PAGES_ADDED', 'FICHARIO', null, true);
    perform pg_temp.wh_5894_it(h19, 1, 'PAGE', 'PAGE_ADDED', null, null, null, null, 3);
    h20 := pg_temp.wh_5894_ev(u_a, l_f, 27, null, 'CARD_MOVED', 'FICHARIO', null, true);
    perform pg_temp.wh_5894_it(h20, 1, 'CARD', 'MOVED', k1, 'SR K1', v_cf, null, 1, 2, 3);
    h21 := pg_temp.wh_5894_ev(u_c, l_f, 34, u_c, 'CARD_MOVED', 'FICHARIO', null, true);
    perform pg_temp.wh_5894_it(h21, 1, 'CARD', 'MOVED', k1, 'SR K1', v_cf, null, 1, 1, 2);
    h16 := pg_temp.wh_5894_ev(u_a, l_m, 26, u_a, 'CARD_MOVED', 'FICHARIO', null, false);
    perform pg_temp.wh_5894_it(h16, 1, 'CARD', 'MOVED', m1, 'SM 1', null, null, 1, 1, 2);
    h15 := pg_temp.wh_5894_ev(u_a, l_f, 32, u_a, 'COLLECTION_ATTACHED', 'FICHARIO', v_cg, false);
    perform pg_temp.wh_5894_it(h15, 1, 'COLLECTION', 'ATTACHED', null, null, null);
    insert into public.collection_layout_catalog_incorporation (layout_id, collection_id, item_key)
    values (l_m, v_cf, k1::text || ':*'), (l_f, v_cm, k2::text || ':*');
    l3 := pg_temp.wh_5894_ev(u_a, l_m, 24, null, 'LEGACY_CATALOG_INCORPORATION', 'LEGADO', v_cm, false,
      jsonb_build_object('item_key', k1::text || ':*'));
    perform pg_temp.wh_5894_it(l3, 1, 'CARD', 'INCORPORATED', k1, 'SR K1', null);
    l4 := pg_temp.wh_5894_ev(u_a, l_m, 23, null, 'LEGACY_CATALOG_INCORPORATION', 'LEGADO', v_cm, false,
      jsonb_build_object('item_key', k2::text || ':*'));
    perform pg_temp.wh_5894_it(l4, 1, 'CARD', 'INCORPORATED', k2, 'SR K2 SEGREDO DE CG', null);

    select string_agg(ca.physical_card_id::text || ':' || ca.collection_id::text, ',' order by ca.physical_card_id) into alloc0
      from public.collection_allocation ca where ca.physical_card_id in (f1, g1, ma1, ma2, d1, d2);
    select string_agg(md5((to_jsonb(pc) - 'updated_at')::text), ',' order by pc.id) into pc0
      from public.physical_card pc where pc.id in (f1, g1, ma1, ma2, d1, d2);
    res := res || jsonb_build_object('id','F.2','ok',
      exists (select 1 from public.collection_layout_guest g where g.layout_id = l_f and g.collection_id = v_cg)
      and exists (select 1 from public.collection_pokedex_position_assignment a join public.collection_allocation ca
                  on ca.id = a.collection_allocation_id where ca.physical_card_id = d1 and a.pokedex_position_id = v_pos)
      and (select count(*) from public.collection_membership m where m.collection_id = v_cf and m.status = 'ACTIVE') = 2
      and exists (select 1 from public.collection_membership m where m.id = m_p and m.status = 'PENDING')
      and not exists (select 1 from public.collection_layout_slot_assignment a join public.collection_layout_slot s on s.id = a.slot_id
                      join public.collection_layout_page pg on pg.id = s.page_id where pg.layout_id in (l_f, l_m)),
      'detail','fixture: CF com convidada CG; CD com d1 na posição P1; B e V ativos em CF; P pendente; bolsos dos fichários vazios');

    -- 1. Matriz de acesso --------------------------------------------------------------------
    perform pg_temp.wh_5894_as(u_b);
    v_j := public.get_shared_collection(v_cf);
    select count(*) into n from public.get_shared_collection_cards(v_cf, 50, 0);
    execute 'reset role';
    res := res || jsonb_build_object('id','1.1','ok', v_j ->> 'access' = 'VIEWER' and v_j ->> 'role' = 'EDITOR' and n >= 1,
      'detail','EDITOR continua com as leituras da V1-12 (nível VIEWER pela 5302, papel EDITOR na 5312)');

    v_ok := true;
    foreach v_txt in array array[u_c::text, u_p::text, u_r::text] loop
      perform pg_temp.wh_5894_as(v_txt::uuid);
      if exists (select 1 from public.get_shared_master_set_positions(v_cm, 'ALL', 500, 0))
         or exists (select 1 from public.get_shared_pokedex_positions(v_cd, 'ALL', null, 500, 0))
         or exists (select 1 from public.get_shared_binder_activity(v_cf, null, null, null, 50))
         or exists (select 1 from public.get_shared_binder_activity(v_cm, null, null, null, 50))
         or exists (select 1 from public.get_shared_binder_activity_status(v_cf)) then
        v_ok := false;
      end if;
    end loop;
    perform pg_temp.wh_5894_as(u_b);
    if exists (select 1 from public.get_shared_binder_activity(v_x2, null, null, null, 50))
       or exists (select 1 from public.get_shared_binder_activity_status(v_x2)) then
      v_ok := false;
    end if;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.2','ok', v_ok,
      'detail','estranho, convite pendente e membro removido: zero linhas nas 4 leituras; EDITOR de A não lê coleção de outro titular');

    perform pg_temp.wh_5894_as(null);
    v_err := pg_temp.wh_5894_try(format('select * from public.get_shared_master_set_positions(%L)', v_cm))
      || ';' || pg_temp.wh_5894_try(format('select * from public.get_shared_pokedex_positions(%L)', v_cd))
      || ';' || pg_temp.wh_5894_try(format('select * from public.get_shared_binder_activity(%L)', v_cf))
      || ';' || pg_temp.wh_5894_try(format('select * from public.get_shared_binder_activity_status(%L)', v_cf));
    execute 'reset role';
    res := res || jsonb_build_object('id','1.3','ok',
      (select count(*) from regexp_matches(v_err, 'permission denied', 'g')) = 4,
      'detail','sessão anônima: sem EXECUTE nas 4 leituras');

    -- 2. Master Set (5323) --------------------------------------------------------------------
    perform pg_temp.wh_5894_as(u_a);
    v_o1 := pg_temp.wh_5894_ms(v_cm, 'ALL', false);
    v_s3 := pg_temp.wh_5894_ms(v_cm, 'ALL', true);
    select x.copies_available into n from public.get_my_master_set_positions(v_cm, 'ALL', 500, 0) x where x.card_id = m1;
    perform pg_temp.wh_5894_as(u_b); v_s1 := pg_temp.wh_5894_ms(v_cm, 'ALL', true);
    perform pg_temp.wh_5894_as(u_v); v_s2 := pg_temp.wh_5894_ms(v_cm, 'ALL', true);
    execute 'reset role';
    res := res || jsonb_build_object('id','2.1','ok', v_o1 <> '<vazio>' and v_s1 = v_o1 and v_s2 = v_o1 and v_s3 = v_o1 and n = 1,
      'detail','Master Set: EDITOR, VIEWER e titular pela leitura compartilhada = colunas comuns da grade do titular (posições, satisfação, exemplares da coleção, imagem); o titular tem 1 exemplar livre que a leitura compartilhada não devolve');

    perform pg_temp.wh_5894_as(u_a);
    v_o1 := pg_temp.wh_5894_ms(v_cm, 'OWNED', false) || '#' || pg_temp.wh_5894_ms(v_cm, 'MISSING', false);
    perform pg_temp.wh_5894_as(u_b);
    v_s1 := pg_temp.wh_5894_ms(v_cm, 'OWNED', true) || '#' || pg_temp.wh_5894_ms(v_cm, 'MISSING', true);
    v_err := pg_temp.wh_5894_try(format('select * from public.get_shared_master_set_positions(%L, %L)', v_cm, 'X'))
      || ';' || pg_temp.wh_5894_try(format('select * from public.get_shared_master_set_positions(%L, %L, 501)', v_cm, 'ALL'));
    select count(*) into n from public.get_shared_master_set_positions(v_cf, 'ALL', 500, 0);
    execute 'reset role';
    res := res || jsonb_build_object('id','2.2','ok', v_s1 = v_o1 and v_err = 'INVALID_FILTER;INVALID_PAGE' and n = 0,
      'detail','filtros Tenho/Faltam iguais aos do titular; filtro e página inválidos recusados; coleção que não é Master Set → zero linhas');

    perform pg_temp.wh_5894_as(u_b); v_s1 := pg_temp.wh_5894_ms(v_cm, 'ALL', true);
    execute 'reset role';
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (m1s, v_pt, v_inv_a);
    perform pg_temp.wh_5894_as(u_a);
    select x.copies_available into n2 from public.get_my_master_set_positions(v_cm, 'ALL', 500, 0) x where x.card_id = m1;
    perform pg_temp.wh_5894_as(u_b); v_s2 := pg_temp.wh_5894_ms(v_cm, 'ALL', true);
    execute 'reset role';
    res := res || jsonb_build_object('id','2.3','ok', n2 = 2 and v_s2 = v_s1,
      'detail','novo exemplar livre no acervo: muda a grade do titular (disponíveis 1→2) e NÃO muda a do participante (sem inferência do acervo)');

    -- 3. Pokédex (5324) ------------------------------------------------------------------------
    perform pg_temp.wh_5894_as(u_a);
    v_o1 := pg_temp.wh_5894_pd(v_cd, 'ALL', null, false);
    v_s3 := pg_temp.wh_5894_pd(v_cd, 'ALL', null, true);
    select * into q from public.get_my_pokedex_positions(v_cd, 'ALL', null, 500, 0) x where x.pokedex_position_id = v_pos;
    perform pg_temp.wh_5894_as(u_b); v_s1 := pg_temp.wh_5894_pd(v_cd, 'ALL', null, true);
    perform pg_temp.wh_5894_as(u_v); v_s2 := pg_temp.wh_5894_pd(v_cd, 'ALL', null, true);
    execute 'reset role';
    res := res || jsonb_build_object('id','3.1','ok', v_o1 <> '<vazio>' and v_s1 = v_o1 and v_s2 = v_o1 and v_s3 = v_o1
      and q.is_satisfied and q.copies_in_collection = 1 and q.copies_available = 1 and q.copies_elsewhere = 1
      and q.representative_card_name = 'SR K1',
      'detail','Pokédex: EDITOR, VIEWER e titular pela leitura compartilhada = colunas comuns (escopo, satisfação, representante da coleção); disponíveis e em outra coleção existem para o titular e não saem para o participante');

    perform pg_temp.wh_5894_as(u_b); v_s1 := pg_temp.wh_5894_pd(v_cd, 'ALL', null, true);
    execute 'reset role';
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (k1s, v_pt, v_inv_a), (k1s, v_pt, v_inv_a);
    perform pg_temp.wh_5894_as(u_a);
    perform public.allocate_physical_cards_to_collection(v_cf,
      array[(select pc.id from public.physical_card pc where pc.inventory_id = v_inv_a and pc.card_variant_id = k1s
               and not exists (select 1 from public.collection_allocation ca where ca.physical_card_id = pc.id)
             order by pc.created_at desc, pc.id limit 1)]);
    select * into q from public.get_my_pokedex_positions(v_cd, 'ALL', null, 500, 0) x where x.pokedex_position_id = v_pos;
    perform pg_temp.wh_5894_as(u_b); v_s2 := pg_temp.wh_5894_pd(v_cd, 'ALL', null, true);
    execute 'reset role';
    res := res || jsonb_build_object('id','3.2','ok', q.copies_available = 2 and q.copies_elsewhere = 2 and v_s2 = v_s1,
      'detail','novos exemplares livres e em outra coleção: mudam a grade do titular e NÃO mudam a do participante');

    perform pg_temp.wh_5894_as(u_a);
    v_o1 := pg_temp.wh_5894_pd(v_cd, 'MISSING', v_gen, false) || '#' || pg_temp.wh_5894_pd(v_cd, 'OWNED', null, false);
    perform pg_temp.wh_5894_as(u_b);
    v_s1 := pg_temp.wh_5894_pd(v_cd, 'MISSING', v_gen, true) || '#' || pg_temp.wh_5894_pd(v_cd, 'OWNED', null, true);
    v_err := pg_temp.wh_5894_try(format('select * from public.get_shared_pokedex_positions(%L, %L)', v_cd, 'X'));
    select count(*) into n from public.get_shared_pokedex_positions(v_cm, 'ALL', null, 500, 0);
    execute 'reset role';
    res := res || jsonb_build_object('id','3.3','ok', v_s1 = v_o1 and v_err = 'INVALID_FILTER' and n = 0,
      'detail','filtro de geração e Tenho/Faltam iguais aos do titular; filtro inválido recusado; coleção que não é Pokédex → zero linhas');

    perform pg_temp.wh_5894_as(u_b);
    select (s.satisfied_positions = (select count(*) filter (where x.is_satisfied) from public.get_shared_master_set_positions(v_cm, 'ALL', 500, 0) x)
            and s.total_positions = (select max(x.total_count) from public.get_shared_master_set_positions(v_cm, 'ALL', 500, 0) x))
      into v_ok from public.collection_completion_summary_shared(v_cm) s;
    select v_ok and (s.satisfied_positions = (select count(*) filter (where x.is_satisfied) from public.get_shared_pokedex_positions(v_cd, 'ALL', null, 500, 0) x)
            and s.total_positions = (select max(x.total_count) from public.get_shared_pokedex_positions(v_cd, 'ALL', null, 500, 0) x))
      into v_ok from public.collection_completion_summary_shared(v_cd) s;
    select sum(x.copies_in_collection) into n from public.get_shared_master_set_positions(v_cm, 'ALL', 500, 0) x;
    select sum(x.copies_in_collection) into n2 from public.get_shared_pokedex_positions(v_cd, 'ALL', null, 500, 0) x;
    execute 'reset role';
    res := res || jsonb_build_object('id','3.4','ok', coalesce(v_ok, false)
      and n = (select count(*) from public.collection_allocation ca where ca.collection_id = v_cm)
      and n2 = (select count(*) from public.collection_allocation ca join public.collection_pokedex_position_assignment a
                 on a.collection_allocation_id = ca.id where ca.collection_id = v_cd),
      'detail','agregados: progresso compartilhado (5310) = satisfeitas/total das grades 5323/5324; soma de exemplares = alocações da coleção (nada do acervo entra na soma)');

    -- 4. Histórico compartilhado (5388) --------------------------------------------------------
    perform pg_temp.wh_5894_as(u_b);
    v_a := pg_temp.wh_5894_ids(v_cf);
    v_txt := pg_temp.wh_5894_hist(v_cf);
    execute 'reset role';
    res := res || jsonb_build_object('id','4.1','ok', v_a = array[h18, h14, h9, h8, h2, h1],
      'detail','EDITOR em CF vê exatamente h18, h14, h9, h8, h2, h1 (ordem occurred_at desc, id desc); ocultos: só de CG (h3), registrado para CG (h4), E07 (h5), E17 (h6), não atribuído (h7), outro fichário (h10), par tipo/origem inválido (h12), outro titular (h13), sem coleção só com item de CG (h17), sem coleção só estrutural (h19), sem coleção e sem autoria (h20), sem coleção de outro titular (h21)');

    perform pg_temp.wh_5894_as(u_b);
    select * into p from public.get_shared_binder_activity(v_cf, null, null, null, 50) x where x.event_id = h2;
    execute 'reset role';
    res := res || jsonb_build_object('id','4.2','ok', p.item_count = 1 and not p.items_truncated
      and jsonb_array_length(p.items) = 1 and (p.items -> 0 ->> 'ordinal')::integer = 1
      and p.items -> 0 ->> 'card_name' = 'SR K1' and p.items -> 0 ->> 'kind' = 'CARD' and p.category = 'CARDS',
      'detail','organização automática (D13): só o item de CF, contagem 1, ordinal renumerado; cartas de CG e página fora');

    res := res || jsonb_build_object('id','4.3','ok',
      position('SEGREDO' in v_txt) = 0 and position('GRAVADO' in v_txt) = 0 and position('"detail"' in v_txt) = 0
      and position('summary' in v_txt) = 0 and position('NM' in v_txt) = 0 and position('example.invalid' in v_txt) = 0
      and position('wh894' in v_txt) = 0 and position(f1::text in v_txt) = 0 and position(c_f::text in v_txt) = 0
      and position(v_cg::text in v_txt) = 0 and position(v_cf::text in v_txt) = 0 and position(u_a::text in v_txt) = 0
      and position(u_b::text in v_txt) = 0 and position(l_f::text in v_txt) = 0,
      'detail','saída sem nome de outra coleção ou carta dela, nome de coleção/fichário gravado, detalhe (exemplar, condição, local), resumo, e-mail, nome de usuário e ids de coleção, fichário ou usuário');

    perform pg_temp.wh_5894_as(u_b);
    select * into p from public.get_shared_binder_activity(v_cf, null, null, null, 50) x where x.event_id = h9;
    select * into q from public.get_shared_binder_activity(v_cf, null, null, null, 50) x where x.event_id = h1;
    execute 'reset role';
    res := res || jsonb_build_object('id','4.4','ok', p.actor_role = 'PARTICIPANT' and p.actor_display_name = 'WH 5894 B'
      and q.actor_role = 'OWNER' and q.actor_display_name = 'WH 5894 A',
      'detail','ator: papel e nome de exibição público (EDITOR → Participante; titular → Titular)');

    perform pg_temp.wh_5894_as(u_v); v_txt2 := pg_temp.wh_5894_hist(v_cf);
    perform pg_temp.wh_5894_as(u_a); v_s1 := pg_temp.wh_5894_hist(v_cf);
    select count(*) into v_cnt_owner from public.get_my_binder_activity(l_f, null, null, null, 50);
    execute 'reset role';
    res := res || jsonb_build_object('id','4.5','ok', v_txt2 = v_txt and v_s1 = v_txt
      and v_cnt_owner = (select count(*) from public.binder_activity_event e where e.owner_user_id = u_a and e.layout_key = l_f),
      'detail','VIEWER e titular pela leitura compartilhada veem o mesmo que o EDITOR; leitura integral do titular (5269) inalterada');

    perform pg_temp.wh_5894_as(u_e); v_b := pg_temp.wh_5894_ids(v_cg);
    execute 'reset role';
    res := res || jsonb_build_object('id','4.6','ok', v_b = array[h18, h17, h4],
      'detail','EDITOR da convidada CG vê o evento registrado para CG (h4) e os do titular sem coleção com item de CG (h17, h18); evento registrado para CF com cartas de CG (h2) não aparece');

    -- D14: evento do titular sem coleção registrada, itens filtrados por coleção.
    perform pg_temp.wh_5894_as(u_b);
    select * into p from public.get_shared_binder_activity(v_cf, null, null, null, 50) x where x.event_id = h18;
    select * into q from public.get_shared_binder_activity(v_cf, null, null, null, 50) x where x.event_id = h14;
    perform pg_temp.wh_5894_as(u_e);
    select x.item_count::text || ':' || (x.items -> 0 ->> 'card_name') || ':' || (x.items -> 0 ->> 'ordinal') into v_s1
      from public.get_shared_binder_activity(v_cg, null, null, null, 50) x where x.event_id = h18;
    v_ok := not exists (select 1 from public.get_shared_binder_activity(v_cg, null, null, null, 50) x
                        where x.event_id in (h14, h19, h20));
    execute 'reset role';
    res := res || jsonb_build_object('id','4.9','ok', p.item_count = 1 and jsonb_array_length(p.items) = 1
      and p.items -> 0 ->> 'card_name' = 'SR K1' and (p.items -> 0 ->> 'ordinal')::integer = 1
      and p.actor_role = 'OWNER' and p.category = 'CARDS'
      and q.item_count = 1 and q.actor_role = 'OWNER' and q.actor_display_name = 'WH 5894 A'
      and v_s1 = '1:SR K2 SEGREDO DE CG:1' and v_ok,
      'detail','D14: evento do titular sem coleção com itens de CF e CG — CF vê só o seu item (contagem 1, ordinal 1) e CG só o dele; h14 visível a CF com autor Titular; h14/h19/h20 não aparecem a CG');

    perform pg_temp.wh_5894_as(u_b);
    v_b := pg_temp.wh_5894_ids(v_cf, array['PAGES']);
    select array_agg(x.event_id order by x.occurred_at desc, x.event_id desc) into v_a
      from public.get_shared_binder_activity(v_cf, null, null, null, 2) x;
    select * into p from public.get_shared_binder_activity(v_cf, null, null, null, 2) x order by x.occurred_at, x.event_id limit 1;
    select v_a || array_agg(x.event_id order by x.occurred_at desc, x.event_id desc) into v_a
      from public.get_shared_binder_activity(v_cf, null, p.occurred_at, p.event_id, 50) x;
    v_err := pg_temp.wh_5894_try(format('select * from public.get_shared_binder_activity(%L, null, now(), null)', v_cf))
      || ';' || pg_temp.wh_5894_try(format('select * from public.get_shared_binder_activity(%L, array[%L])', v_cf, 'NADA'));
    execute 'reset role';
    res := res || jsonb_build_object('id','4.7','ok', v_b = array[h8] and v_a = array[h18, h14, h9, h8, h2, h1]
      and v_err = 'cursor must have occurred_at and id together;unknown category',
      'detail','categoria Páginas → só h8; paginação por cursor (2 + resto) reconstitui a lista sem repetir; cursor incompleto e categoria desconhecida recusados');

    perform pg_temp.wh_5894_as(u_b);
    v_a := pg_temp.wh_5894_ids(v_cm);
    select * into p from public.get_shared_binder_activity(v_cm, null, null, null, 50) x where x.event_id = l1;
    execute 'reset role';
    res := res || jsonb_build_object('id','4.8','ok', v_a = array[l1] and p.is_legacy and p.actor_role is null
      and p.actor_display_name is null and p.category = 'CATALOG' and p.item_count = 1
      and p.items -> 0 ->> 'effect' = 'INCORPORATED' and p.items -> 0 ->> 'card_name' = 'SM 1',
      'detail','L01 (D12): visível só com a linha de origem de CM neste fichário (l1); sem origem (l2), origem de outra coleção (l3) ou de outro fichário (l4) oculto; sem ator; evento do titular sem coleção não atribuído (h16) oculto');

    -- 5. Estado do histórico e fichário encerrado ----------------------------------------------
    perform pg_temp.wh_5894_as(u_b);
    select * into p from public.get_shared_binder_activity_status(v_cf);
    select * into q from public.get_shared_binder_activity_status(v_cd);
    select count(*) into n from public.get_shared_binder_activity(v_cd, null, null, null, 50);
    v_txt := (select s.has_binder::text || '/' || s.history_may_be_partial::text from public.get_shared_binder_activity_status(v_cm) s);
    perform pg_temp.wh_5894_as(u_e);
    v_txt2 := (select s.has_binder::text || '/' || s.history_may_be_partial::text from public.get_shared_binder_activity_status(v_cg) s);
    execute 'reset role';
    res := res || jsonb_build_object('id','5.1','ok', p.has_binder and p.history_may_be_partial
      and not q.has_binder and not q.history_may_be_partial and n = 0 and v_txt = 'true/true' and v_txt2 = 'true/false',
      'detail','histórico parcial (D12): CF (h7 não atribuído) e CM (l2 sem origem, h16 sem coleção não atribuído) → true; CG → false apesar de h7 (registrado para outra coleção), h15 (estrutura não atribuída de CG) e eventos D14 atribuídos; CD sem fichário → false/false e nenhum evento');

    perform pg_temp.wh_5894_as(u_a);
    perform count(*) from public.transfer_my_binder_ownership(v_cf, v_cg);
    perform pg_temp.wh_5894_as(u_b); v_a := pg_temp.wh_5894_ids(v_cf);
    v_txt := (select s.has_binder::text from public.get_shared_binder_activity_status(v_cf) s);
    perform pg_temp.wh_5894_as(u_e); v_b := pg_temp.wh_5894_ids(v_cg);
    execute 'reset role';
    v_ok := exists (select 1 from public.collection_layout l where l.id = l_f and l.collection_id = v_cg)
        and exists (select 1 from public.collection_layout_guest g where g.layout_id = l_f and g.collection_id = v_cf);
    perform pg_temp.wh_5894_as(u_a);
    perform count(*) from public.transfer_my_binder_ownership(v_cg, v_cf);
    execute 'reset role';
    res := res || jsonb_build_object('id','5.3','ok', v_ok and v_a = array[h18, h14, h9, h8, h2, h1] and v_txt = 'true' and v_b = array[h18, h17, h4]
      and exists (select 1 from public.collection_layout l where l.id = l_f and l.collection_id = v_cf),
      'detail','transferência de âncora CF→CG (chave do fichário preservada, CF vira convidada): membros de CF seguem vendo os eventos de CF anteriores; membros de CG não ganham eventos de CF; E20 oculto; âncora devolvida');

    perform pg_temp.wh_5894_as(u_a);
    select * into p from public.preview_my_collection_binder_detach(v_cg);
    perform count(*) from public.detach_my_collection_from_binder(v_cg, p.detach_token, false);
    perform pg_temp.wh_5894_as(u_e);
    select count(*) into n from public.get_shared_binder_activity(v_cg, null, null, null, 50);
    select * into q from public.get_shared_binder_activity_status(v_cg);
    execute 'reset role';
    res := res || jsonb_build_object('id','5.2','ok', n = 0 and not q.has_binder and not q.history_may_be_partial,
      'detail','convidada desassociada: o histórico do fichário deixa de ser legível pelos membros dela (C-208); evento h4 continua gravado');

    -- 6. Revogação e estado da coleção ---------------------------------------------------------
    perform pg_temp.wh_5894_as(u_a);
    perform public.set_collection_member_role(v_cf, m_b, 'VIEWER');
    perform pg_temp.wh_5894_as(u_b); v_a := pg_temp.wh_5894_ids(v_cf);
    perform pg_temp.wh_5894_as(u_a);
    perform public.remove_collection_member(v_cf, m_b);
    perform public.remove_collection_member(v_cm, m_bm);
    perform public.remove_collection_member(v_cd, m_bd);
    perform pg_temp.wh_5894_as(u_b);
    v_ok := not exists (select 1 from public.get_shared_binder_activity(v_cf, null, null, null, 50))
        and not exists (select 1 from public.get_shared_binder_activity_status(v_cf))
        and not exists (select 1 from public.get_shared_master_set_positions(v_cm, 'ALL', 500, 0))
        and not exists (select 1 from public.get_shared_pokedex_positions(v_cd, 'ALL', null, 500, 0));
    execute 'reset role';
    res := res || jsonb_build_object('id','6.1','ok', v_a = array[h18, h14, h9, h8, h2, h1] and v_ok,
      'detail','troca EDITOR→VIEWER mantém a mesma leitura; remoção encerra as 4 leituras na chamada seguinte');

    -- 7. Sem efeito patrimonial ----------------------------------------------------------------
    res := res || jsonb_build_object('id','7.1','ok',
      (select string_agg(ca.physical_card_id::text || ':' || ca.collection_id::text, ',' order by ca.physical_card_id)
         from public.collection_allocation ca where ca.physical_card_id in (f1, g1, ma1, ma2, d1, d2)) = alloc0
      and (select string_agg(md5((to_jsonb(pc) - 'updated_at')::text), ',' order by pc.id)
             from public.physical_card pc where pc.id in (f1, g1, ma1, ma2, d1, d2)) = pc0
      and not exists (select 1 from public.binder_activity_event e where e.owner_user_id = u_a and e.actor_user_id in (u_b, u_v, u_e)
                        and e.id not in (h9)),
      'detail','leituras não gravam nada: alocações e exemplares da fixture intactos; nenhum evento de membro além do gravado na fixture (C-171)');

    perform pg_temp.wh_5894_as(u_a); perform public.archive_collection(v_cm);
    perform pg_temp.wh_5894_as(u_v);
    v_ok := ((public.get_shared_collection(v_cm)) is not null)
            = exists (select 1 from public.get_shared_master_set_positions(v_cm, 'ALL', 500, 0))
        and ((public.get_shared_collection(v_cm)) is not null)
            = exists (select 1 from public.get_shared_binder_activity(v_cm, null, null, null, 50));
    execute 'reset role';
    res := res || jsonb_build_object('id','6.2','ok', v_ok,
      'detail','coleção arquivada: as leituras novas seguem exatamente a regra vigente da 5312 (mesmo acesso de leitura)');

    execute 'reset role';
    raise exception 'MS894' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MS894' then
      res := res || jsonb_build_object('id','X.1','ok', false, 'detail','erro inesperado: '||sqlstate||' '||sqlerrm);
    end if;
  end;

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('mmkyu.binder_activity_ctx', '', true);
  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.collection_membership), (select count(*) from public.collection_layout_page),
               (select count(*) from public.collection_layout_slot_assignment),
               (select count(*) from public.collection_layout_catalog_incorporation),
               (select count(*) from public.collection_pokedex_position_assignment),
               (select count(*) from public.binder_activity_event), (select count(*) from public.binder_activity_item),
               (select count(*) from public.card)]
    into e_counts;
  res := res || jsonb_build_object('id','99.1','ok', b_counts = e_counts and current_user = session_user,
    'detail','resíduo zero (12 contagens, inclusive atribuições Pokédex, incorporações e histórico) e papel restaurado');

  v_expected := 29;
  for r in select * from jsonb_array_elements(res) loop
    cnt := cnt + 1;
    if coalesce((r ->> 'ok')::boolean, false) then passes := passes + 1; end if;
    seq := cnt; check_id := r ->> 'id';
    status := case when coalesce((r ->> 'ok')::boolean, false) then 'PASS' else 'FAIL' end;
    detail := r ->> 'detail';
    return next;
  end loop;
  seq := cnt + 1; check_id := 'GATE';
  status := case when passes = cnt and cnt = v_expected then 'PASS' else 'FAIL' end;
  detail := passes || '/' || cnt || ' PASS (esperado ' || v_expected || ')';
  return next;
end;
$fn$;
