/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5893 - Harness V1-13 · E1-C2 (5384–5387): inserir/fechar espaço,
              organização automática e novidades do Catálogo pelo EDITOR só no
              fichário exclusivo e só com conteúdo da coleção; conteúdo residual de
              terceiros; tipos de evento; revogação; titular intocado; sem efeito
              patrimonial; resíduo zero
Versão......: 1.1 (2026-11-15, `BULK OPERATIONS INTEGRITY REVIEW-02`: token u1 de outro usuário,
              prévias vencidas, elegibilidade alterada, efeitos da incorporação). 1.0
Status......: PROPOSTA — NÃO EXECUTADA. Prova DINÂMICA da E1-C2. Sem ambiente
              isolado (C-244): executar SOMENTE sob protocolo controlado
              equivalente ao P1 da E1-A (transação explícita READ WRITE terminada
              em erro/ROLLBACK, conexão direta única, psql), depois de E1-A … E1-C2,
              com autorização expressa e específica. Sem BEGIN/COMMIT próprios;
              não é comando pronto para produção.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-15

Pressupõe aplicadas: 5366–5387.

Usuários efêmeros: A titular · B EDITOR de CF, CD e CM · V VIEWER de CF · R EDITOR
de CF removido · E EDITOR de CG · C estranho.
Coleções de A:
  CF  livre, fichário 3×3; CG convidada (depois desassociada: a carta g1 fica);
  CD  Pokédex, fichário 2×2 exclusivo, referências de espécie do titular;
  CM  Master Set (só STANDARD), fichário 3×3 exclusivo; novidades M3 e M4
      criadas depois do marco (L3).
Exemplares de A: f1, f2 (CF), g1 (CG), d1 (CD; espécie da posição P1).

  select * from pg_temp.wh_5893_validate();
  -- GATE esperado: 24/24 PASS (23 verificações + F.2)

Limitações declaradas:
  L1 SET LOCAL ROLE prova o banco, não o JWT do PostgREST.
  L2 Concorrência (S8 concorrente, S10): PENDENTE — sessão única.
  L3 Dentro de uma transação todo now() é igual: o marco do Catálogo de CM é
     recuado com privilégio (mesmo recurso da 5859, L7) para M3/M4 serem
     novidades.
  L4 Posições da fixture vêm dos planos canônicos (montagem, referências,
     novidades); as verificações leem esses valores em vez de fixá-los.
================================================================
*/

create or replace function pg_temp.wh_5893_as(p_user uuid)
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

create or replace function pg_temp.wh_5893_try(p_sql text)
returns text language plpgsql volatile as $try$
begin
  execute p_sql;
  return 'OK';
exception when others then
  return sqlerrm;
end;
$try$;

create or replace function pg_temp.wh_5893_slot(p_layout uuid, p_page integer, p_row integer, p_col integer)
returns uuid language sql stable as $sl$
  select s.id from public.collection_layout_slot s
  join public.collection_layout_page p on p.id = s.page_id
  where p.layout_id = p_layout and p.page_number = p_page and s.row_index = p_row and s.column_index = p_col;
$sl$;

create or replace function pg_temp.wh_5893_at(p_layout uuid, p_card uuid)
returns text language sql stable as $at$
  -- "<página>:<linha>:<coluna>" do exemplar no fichário, ou NULL
  select p.page_number || ':' || s.row_index || ':' || s.column_index
  from public.collection_layout_slot_assignment a
  join public.collection_layout_slot s on s.id = a.slot_id
  join public.collection_layout_page p on p.id = s.page_id
  where p.layout_id = p_layout and a.physical_card_id = p_card;
$at$;

create or replace function pg_temp.wh_5893_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
as $fn$
#variable_conflict use_column
declare
  u_a uuid := gen_random_uuid(); u_b uuid := gen_random_uuid(); u_v uuid := gen_random_uuid();
  u_r uuid := gen_random_uuid(); u_e uuid := gen_random_uuid(); u_c uuid := gen_random_uuid();
  v_sfx text := lower(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  v_game uuid; v_pt uuid; v_rar uuid; v_cat uuid; v_std uuid; v_exp uuid; v_set uuid; v_sm uuid; v_gen text;
  v_old timestamptz := now() - interval '2 days';
  k1 uuid; k1s uuid; k2 uuid; k2s uuid; m1 uuid; m2 uuid; m3 uuid; m4 uuid; v_pos uuid; v_spc uuid;
  v_inv_a uuid; v_ids uuid[]; f1 uuid; f2 uuid; g1 uuid; d1 uuid;
  v_bf uuid; v_bd uuid; v_bm uuid;
  v_cf uuid; v_cg uuid; v_cd uuid; v_cm uuid;
  l_f uuid; l_d uuid; l_m uuid; c_f uuid; c_d uuid;
  m_b uuid; m_bd uuid; m_bm uuid; m_v uuid; m_r uuid; m_e uuid;
  p record; q record; v_err text; v_err2 text; v_txt text; v_s1 text; v_s2 text; n3 integer; v_ep integer; v_er integer; v_ec integer; v_tok text; v_key3 text; v_key4 text; v_j jsonb;
  v_u uuid; n integer; n2 integer;
  alloc0 text; pc0 text;
  b_counts bigint[]; e_counts bigint[];
  res jsonb := '[]'::jsonb; r jsonb; cnt integer := 0; passes integer := 0;
  v_expected integer := 0;
begin
  -- 0. Estrutura ---------------------------------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    (select count(*) from pg_proc q
      where q.oid in (to_regprocedure('public.editor_preview_binder_insert_gap(uuid, integer, integer, integer)'),
                      to_regprocedure('public.editor_insert_binder_gap(uuid, integer, integer, integer, text, boolean, boolean)'),
                      to_regprocedure('public.editor_close_binder_gap(uuid, integer, integer, integer, integer, integer, integer, text, integer)'),
                      to_regprocedure('public.editor_preview_binder_auto_arrange(uuid)'),
                      to_regprocedure('public.editor_apply_binder_auto_arrange(uuid, text)'),
                      to_regprocedure('public.editor_preview_binder_catalog_reconciliation(uuid, text[])'),
                      to_regprocedure('public.editor_apply_binder_catalog_reconciliation(uuid, text[], text, boolean, boolean)'))
        and q.prosecdef and q.proconfig @> array['search_path=""']
        and has_function_privilege('authenticated', q.oid, 'EXECUTE')
        and not has_function_privilege('anon', q.oid, 'EXECUTE')) = 7
    and (select count(*) from pg_proc q
          where q.oid in (to_regprocedure('public.editor_binder_exclusive_read(uuid)'),
                          to_regprocedure('public.binder_editor_any_foreign(uuid, uuid, uuid[])'),
                          to_regprocedure('public.binder_editor_append_page(uuid)'),
                          to_regprocedure('public.binder_editor_catalog_affected(uuid, uuid, text[])'))
            and not has_function_privilege('authenticated', q.oid, 'EXECUTE')) = 4,
    'detail','7 RPCs do EDITOR: definer, search_path vazio, só authenticated; 4 ajudantes internos');
  res := res || jsonb_build_object('id','0.2','ok',
    (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.binder_activity_event_editor_type_guard()')) = '78fa0d34dad161eac1165f3143874260'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)')) = 'f8cfba40e442e85056e7c8ce7954d4f4'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.binder_slot_editor_scope(uuid, uuid, uuid, uuid)')) = '21f1b51a3a0f6c80337c2c593cc6054f',
    'detail','lista de tipos estendida (5384); gravação (5379) e classificação (5378) inalteradas');

  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.collection_membership), (select count(*) from public.collection_layout_page),
               (select count(*) from public.collection_layout_slot), (select count(*) from public.collection_layout_slot_assignment),
               (select count(*) from public.collection_layout_slot_expected_content),
               (select count(*) from public.collection_layout_catalog_incorporation),
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
      raise exception 'MS893' using errcode = 'P0001';
    end if;
    insert into public.expansion (game_id, code, name, release_order)
    values (v_game, 'ED_' || upper(v_sfx), 'ED Harness ' || v_sfx,
            (select coalesce(max(x.release_order), 0) + 1000 from public.expansion x where x.game_id = v_game))
    returning id into v_exp;
    insert into public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_exp, 'ED' || upper(v_sfx), 'ED Set ' || v_sfx, 'REGULAR', 1, 2, 2) returning id into v_set;
    insert into public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_exp, 'EM' || upper(v_sfx), 'EM Set ' || v_sfx, 'REGULAR', 2, 4, 4) returning id into v_sm;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '1', 1, 'ED K1', true) returning id into k1;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '2', 2, 'ED K2', true) returning id into k2;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k1, v_std, 1, true) returning id into k1s;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k2, v_std, 1, true) returning id into k2s;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active, created_at)
    values (v_sm, v_rar, v_cat, '1', 1, 'EM 1', true, v_old) returning id into m1;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active, created_at)
    values (v_sm, v_rar, v_cat, '2', 2, 'EM 2', true, v_old) returning id into m2;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default, created_at)
    values (m1, v_std, 1, true, v_old), (m2, v_std, 1, true, v_old);

    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    select u.id, 'authenticated', 'authenticated', 'wh893' || u.t || '_' || v_sfx || '@example.invalid',
           jsonb_build_object('username', 'wh893' || u.t || '_' || v_sfx, 'display_name', 'WH 5893 ' || upper(u.t)), now(), now()
    from (values (u_a, 'a'), (u_b, 'b'), (u_v, 'v'), (u_r, 'r'), (u_e, 'e'), (u_c, 'c')) u(id, t);
    insert into public.card_primary_species (card_id, pokemon_species_id, resolution_basis, resolved_by_user_id)
    values (k1, v_spc, 'EDITORIAL_RECONCILIATION', u_a);
    select i.id into v_inv_a from public.inventory i where i.owner_user_id = u_a;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, created_at)
    select v.cv, v_pt, v_inv_a, now() - (v.o || ' min')::interval from (values (k2s, 4), (k2s, 3), (k2s, 2), (k1s, 1)) v(cv, o);
    select array_agg(pc.id order by pc.created_at) into v_ids from public.physical_card pc where pc.inventory_id = v_inv_a;
    f1 := v_ids[1]; f2 := v_ids[2]; g1 := v_ids[3]; d1 := v_ids[4];

    perform pg_temp.wh_5893_as(u_a);
    select x.storage_container_id into v_bf from public.create_my_storage_container(gen_random_uuid(), 'BIN F 5893', 'BINDER') x;
    select x.storage_container_id into v_bd from public.create_my_storage_container(gen_random_uuid(), 'BIN D 5893', 'BINDER') x;
    select x.storage_container_id into v_bm from public.create_my_storage_container(gen_random_uuid(), 'BIN M 5893', 'BINDER') x;
    select x.collection_id into v_cf from public.create_my_free_collection(gen_random_uuid(), 'CF 5893', v_bf) x;
    select x.collection_id into v_cd from public.create_my_pokedex_collection(gen_random_uuid(), 'CD 5893', array[v_gen], v_bd) x;
    select x.collection_id into v_cm from public.create_my_card_set_collection(gen_random_uuid(), v_sm, 'CM 5893', v_bm) x;
    perform count(*) from public.set_collection_completion_policy_to_master_set(v_cm, array[v_std]);
    perform public.allocate_physical_cards_to_collection(v_cf, array[f1, f2]);
    perform public.allocate_physical_cards_to_collection(v_cd, array[d1]);
    select * into p from public.preview_my_collection_binder(v_cf, 3, 3, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_cf, 3, 3, 'PRINCIPAL_ONLY', p.plan_token);
    select * into p from public.preview_my_collection_binder(v_cd, 2, 2, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_cd, 2, 2, 'PRINCIPAL_ONLY', p.plan_token);
    select * into p from public.preview_my_collection_binder(v_cm, 3, 3, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_cm, 3, 3, 'PRINCIPAL_ONLY', p.plan_token);
    execute 'reset role';
    select l.id, l.storage_container_id into l_f, c_f from public.collection_layout l where l.collection_id = v_cf;
    select l.id, l.storage_container_id into l_d, c_d from public.collection_layout l where l.collection_id = v_cd;
    select l.id into l_m from public.collection_layout l where l.collection_id = v_cm;
    delete from public.collection_layout_slot_assignment a using public.collection_layout_slot s, public.collection_layout_page p2
     where a.slot_id = s.id and s.page_id = p2.id and p2.layout_id in (l_f, l_d);
    delete from public.collection_layout_slot_expected_content e using public.collection_layout_slot s, public.collection_layout_page p2
     where e.slot_id = s.id and s.page_id = p2.id and p2.layout_id in (l_f, l_d);
    delete from public.collection_layout_slot_species_reference sr where sr.layout_id in (l_f, l_d);
    update public.physical_card pc set storage_container_id = c_f where pc.id in (f1, f2, g1);
    update public.physical_card pc set storage_container_id = c_d where pc.id = d1;
    -- Catálogo de CM: marco recuado e duas cartas novas depois dele (L3).
    update public.collection_layout_catalog_marker mk set marker_at = now() - interval '1 day'
     where mk.layout_id = l_m and mk.collection_id = v_cm;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_sm, v_rar, v_cat, '3', 3, 'EM 3', true) returning id into m3;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_sm, v_rar, v_cat, '4', 4, 'EM 4', true) returning id into m4;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (m3, v_std, 1, true), (m4, v_std, 1, true);
    select nv.item_key into v_key3 from public.binder_catalog_novelties(v_cm) nv where nv.is_novelty and nv.item_key like m3::text || ':%';
    select nv.item_key into v_key4 from public.binder_catalog_novelties(v_cm) nv where nv.is_novelty and nv.item_key like m4::text || ':%';

    perform pg_temp.wh_5893_as(u_a);
    select x.collection_id into v_cg from public.create_my_free_collection(gen_random_uuid(), 'CG 5893', c_f) x;
    perform public.allocate_physical_cards_to_collection(v_cg, array[g1]);
    perform public.attach_my_collection_to_binder(v_cg, l_f);
    perform public.place_my_physical_card_in_slot(v_cf, pg_temp.wh_5893_slot(l_f, 1, 1, 1), f1);
    perform public.place_my_physical_card_in_slot(v_cf, pg_temp.wh_5893_slot(l_f, 1, 1, 2), f2);
    perform public.place_my_physical_card_in_slot(v_cg, pg_temp.wh_5893_slot(l_f, 1, 1, 3), g1);
    select * into p from public.preview_my_binder_species_references(v_cd);
    perform count(*) from public.apply_my_binder_species_references(v_cd, p.plan_token);
    m_b  := (public.invite_collection_member(v_cf, 'wh893b_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_bd := (public.invite_collection_member(v_cd, 'wh893b_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_bm := (public.invite_collection_member(v_cm, 'wh893b_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_v  := (public.invite_collection_member(v_cf, 'wh893v_' || v_sfx) ->> 'membership_id')::uuid;
    m_r  := (public.invite_collection_member(v_cf, 'wh893r_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_e  := (public.invite_collection_member(v_cg, 'wh893e_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    perform pg_temp.wh_5893_as(u_b);
    perform public.respond_collection_invite(m_b, true);
    perform public.respond_collection_invite(m_bd, true);
    perform public.respond_collection_invite(m_bm, true);
    perform pg_temp.wh_5893_as(u_v); perform public.respond_collection_invite(m_v, true);
    perform pg_temp.wh_5893_as(u_r); perform public.respond_collection_invite(m_r, true);
    perform pg_temp.wh_5893_as(u_e); perform public.respond_collection_invite(m_e, true);
    perform pg_temp.wh_5893_as(u_a); perform public.remove_collection_member(v_cf, m_r);
    execute 'reset role';
    select string_agg(ca.physical_card_id::text || ':' || ca.collection_id::text, ',' order by ca.physical_card_id) into alloc0
      from public.collection_allocation ca where ca.physical_card_id in (f1, f2, g1, d1);
    select string_agg(md5((to_jsonb(pc) - 'updated_at')::text), ',' order by pc.id) into pc0
      from public.physical_card pc where pc.id in (f1, f2, g1, d1);
    res := res || jsonb_build_object('id','F.2','ok',
      pg_temp.wh_5893_at(l_f, f1) = '1:1:1' and pg_temp.wh_5893_at(l_f, f2) = '1:1:2' and pg_temp.wh_5893_at(l_f, g1) = '1:1:3'
      and exists (select 1 from public.collection_layout_guest g where g.layout_id = l_f and g.collection_id = v_cg)
      and exists (select 1 from public.collection_layout_slot_species_reference sr where sr.layout_id = l_d and sr.pokedex_position_id = v_pos)
      and v_key3 is not null and v_key4 is not null,
      'detail','fixture: CF com carta de CG na cadeia; CD com referências; CM com duas novidades');

    -- 1. Inserir e fechar espaço ---------------------------------------------------------------
    perform pg_temp.wh_5893_as(u_b);
    v_err := pg_temp.wh_5893_try(format('select * from public.editor_preview_binder_insert_gap(%L, 1, 1, 1)', v_cf));
    perform pg_temp.wh_5893_as(u_e);
    v_err := v_err || ';' || pg_temp.wh_5893_try(format('select * from public.editor_preview_binder_insert_gap(%L, 1, 1, 1)', v_cg));
    execute 'reset role';
    res := res || jsonb_build_object('id','1.1','ok', v_err = 'OPERATION_RESERVED_TO_OWNER;OPERATION_RESERVED_TO_OWNER',
      'detail','fichário com convidada: EDITOR da proprietária e da convidada não inserem espaço');
    perform pg_temp.wh_5893_as(u_a);
    select * into p from public.preview_my_collection_binder_detach(v_cg);
    perform count(*) from public.detach_my_collection_from_binder(v_cg, p.detach_token, false);
    execute 'reset role';
    select e.plan_token into v_tok from public.binder_gap_evaluate(l_f, pg_temp.wh_5893_slot(l_f, 1, 1, 1)) e;
    perform pg_temp.wh_5893_as(u_b);
    v_err := pg_temp.wh_5893_try(format('select * from public.editor_preview_binder_insert_gap(%L, 1, 1, 1)', v_cf))
          || ';' || pg_temp.wh_5893_try(format('select * from public.editor_insert_binder_gap(%L, 1, 1, 1, %L, true, true)', v_cf, v_tok));
    execute 'reset role';
    res := res || jsonb_build_object('id','1.2','ok', v_err = 'OPERATION_RESERVED_TO_OWNER;OPERATION_RESERVED_TO_OWNER'
      and pg_temp.wh_5893_at(l_f, g1) = '1:1:3' and pg_temp.wh_5893_at(l_f, f1) = '1:1:1'
      and not exists (select 1 from public.collection_layout_guest g where g.layout_id = l_f),
      'detail','fichário exclusivo com carta da convidada desassociada na cadeia: prévia e inserção (mesmo com token válido) recusadas; nada anda');
    perform pg_temp.wh_5893_as(u_a); perform public.remove_slot_assignment(array[pg_temp.wh_5893_slot(l_f, 1, 1, 3)]);
    perform pg_temp.wh_5893_as(u_b);
    select * into p from public.editor_preview_binder_insert_gap(v_cf, 1, 1, 1);
    -- plano válido que deixou de representar o estado: o titular reserva o bolso de destino
    perform pg_temp.wh_5893_as(u_a);
    perform public.set_slot_expected_content(pg_temp.wh_5893_slot(l_f, 1, 1, 3), k2, null, null, null);
    perform pg_temp.wh_5893_as(u_b);
    v_err2 := pg_temp.wh_5893_try(format('select * from public.editor_insert_binder_gap(%L, 1, 1, 1, %L)', v_cf, p.plan_token));
    perform pg_temp.wh_5893_as(u_a);
    perform public.clear_slot_expected_content(array[pg_temp.wh_5893_slot(l_f, 1, 1, 3)]);
    perform pg_temp.wh_5893_as(u_b);
    select * into q from public.editor_insert_binder_gap(v_cf, 1, 1, 1, p.plan_token);
    execute 'reset role';
    res := res || jsonb_build_object('id','1.3','ok', p.outcome = 'SAME_PAGE' and p.moved_pockets = 2 and v_err2 = 'GAP_PLAN_CHANGED'
      and q.outcome = 'INSERTED' and q.end_page = 1 and q.end_row = 1 and q.end_column = 3
      and pg_temp.wh_5893_at(l_f, f1) = '1:1:2' and pg_temp.wh_5893_at(l_f, f2) = '1:1:3'
      and exists (select 1 from public.binder_activity_event e where e.layout_key = l_f and e.actor_user_id = u_b
                  and e.event_type = 'GAP_OPENED' and e.collection_id = v_cf and e.source = 'FICHARIO')
      and not exists (select 1 from public.binder_activity_item i join public.binder_activity_event e on e.id = i.event_id
                      where e.layout_key = l_f and e.actor_user_id = u_b and e.event_type = 'GAP_OPENED'
                        and i.collection_id is distinct from v_cf),
      'detail','token de prévia vencido pela mudança do destino → GAP_PLAN_CHANGED; estado de volta: espaço aberto, ordem preservada, GAP_OPENED com itens de CF');
    perform pg_temp.wh_5893_as(u_b);
    select * into p from public.editor_close_binder_gap(v_cf, 1, 1, 1, q.end_page, q.end_row, q.end_column, q.undo_token);
    v_err := pg_temp.wh_5893_try(format('select * from public.editor_close_binder_gap(%L, 1, 1, 1, 1, 1, 3, %L)', v_cf, q.undo_token));
    execute 'reset role';
    res := res || jsonb_build_object('id','1.4','ok', p.outcome = 'CLOSED' and p.moved_pockets = 2
      and pg_temp.wh_5893_at(l_f, f1) = '1:1:1' and pg_temp.wh_5893_at(l_f, f2) = '1:1:2' and v_err = 'GAP_UNDO_EXPIRED'
      and exists (select 1 from public.binder_activity_event e where e.layout_key = l_f and e.actor_user_id = u_b
                  and e.event_type = 'GAP_CLOSED'),
      'detail','fechar com o token de desfazer devolve as cartas; repetir → GAP_UNDO_EXPIRED');
    -- token u1 de OUTRO usuário (o titular abre, o EDITOR fecha): o token só confere o estado.
    perform pg_temp.wh_5893_as(u_a);
    select * into p from public.preview_my_binder_insert_gap(v_cf, pg_temp.wh_5893_slot(l_f, 1, 1, 1));
    select * into q from public.insert_my_binder_gap(v_cf, pg_temp.wh_5893_slot(l_f, 1, 1, 1), p.plan_token, true, true);
    execute 'reset role';
    select pg.page_number, s.row_index, s.column_index into v_ep, v_er, v_ec
      from public.collection_layout_slot s join public.collection_layout_page pg on pg.id = s.page_id where s.id = q.end_slot_id;
    perform pg_temp.wh_5893_as(u_b);
    select * into p from public.editor_close_binder_gap(v_cf, 1, 1, 1, v_ep, v_er, v_ec, q.undo_token);
    execute 'reset role';
    res := res || jsonb_build_object('id','1.5','ok', p.outcome = 'CLOSED'
      and pg_temp.wh_5893_at(l_f, f1) = '1:1:1' and pg_temp.wh_5893_at(l_f, f2) = '1:1:2',
      'detail','espaço aberto pelo titular só sobre cartas de CF: o EDITOR que recebe o token pode fechá-lo (mesmo efeito que mover cartas de CF)');
    insert into public.collection_layout_slot_image (slot_id, owner_user_id, storage_path)
    values (pg_temp.wh_5893_slot(l_f, 1, 1, 3), u_a, u_a::text || '/' || l_f::text || '/wh5893.webp');
    perform pg_temp.wh_5893_as(u_b);
    v_err := pg_temp.wh_5893_try(format('select * from public.editor_preview_binder_insert_gap(%L, 1, 1, 1)', v_cf));
    execute 'reset role';
    res := res || jsonb_build_object('id','1.6','ok', v_err = 'OPERATION_RESERVED_TO_OWNER'
      and exists (select 1 from public.collection_layout_slot_image i where i.slot_id = pg_temp.wh_5893_slot(l_f, 1, 1, 3)),
      'detail','imagem do titular na cadeia → recusa; a imagem não anda');
    perform pg_temp.wh_5893_as(u_a);
    select * into p from public.preview_my_binder_insert_gap(v_cf, pg_temp.wh_5893_slot(l_f, 1, 1, 1));
    select * into q from public.insert_my_binder_gap(v_cf, pg_temp.wh_5893_slot(l_f, 1, 1, 1), p.plan_token, true, true);
    execute 'reset role';
    select pg.page_number, s.row_index, s.column_index into v_ep, v_er, v_ec
      from public.collection_layout_slot s join public.collection_layout_page pg on pg.id = s.page_id where s.id = q.end_slot_id;
    perform pg_temp.wh_5893_as(u_b);
    v_err := pg_temp.wh_5893_try(format('select * from public.editor_close_binder_gap(%L, 1, 1, 1, %s, %s, %s, %L)', v_cf, v_ep, v_er, v_ec, q.undo_token));
    perform pg_temp.wh_5893_as(u_a);
    perform count(*) from public.close_my_binder_gap(v_cf, q.gap_slot_id, q.end_slot_id, q.undo_token, q.added_page_id);
    execute 'reset role';
    res := res || jsonb_build_object('id','1.7','ok', v_err = 'OPERATION_RESERVED_TO_OWNER'
      and pg_temp.wh_5893_at(l_f, f1) = '1:1:1'
      and exists (select 1 from public.collection_layout_slot_image i where i.slot_id = pg_temp.wh_5893_slot(l_f, 1, 1, 3)),
      'detail','espaço do titular que deslocou a imagem dele: o EDITOR não desfaz (trecho com terceiros), mesmo com o token; o titular desfaz');

    -- 2. Organização automática (Pokédex exclusiva) -----------------------------------------------
    perform pg_temp.wh_5893_as(u_b);
    v_j := public.editor_preview_binder_auto_arrange(v_cd);
    v_tok := v_j ->> 'plan_token';
    -- elegibilidade muda entre a prévia e a confirmação: o titular posiciona d1
    select sr.slot_id into v_u from public.collection_layout_slot_species_reference sr
     where sr.layout_id = l_d and sr.pokedex_position_id = v_pos;
    perform pg_temp.wh_5893_as(u_a); perform public.place_my_physical_card_in_slot(v_cd, v_u, d1);
    perform pg_temp.wh_5893_as(u_b);
    v_err2 := pg_temp.wh_5893_try(format('select public.editor_apply_binder_auto_arrange(%L, %L)', v_cd, v_tok));
    select count(*) into n3 from public.binder_activity_event e where e.layout_key = l_d and e.event_type = 'CARDS_AUTO_ARRANGED';
    perform pg_temp.wh_5893_as(u_a); perform public.remove_slot_assignment(array[v_u]);
    perform pg_temp.wh_5893_as(u_b);
    v_txt := public.editor_apply_binder_auto_arrange(v_cd, v_tok) ->> 'status';
    v_txt := v_txt || ';' || (public.editor_apply_binder_auto_arrange(v_cd, v_tok) ->> 'status');
    v_err := pg_temp.wh_5893_try(format('select public.editor_preview_binder_auto_arrange(%L)', v_cf));
    execute 'reset role';
    res := res || jsonb_build_object('id','2.1','ok', v_j ->> 'status' = 'READY' and (v_j ->> 'insert_count')::integer = 1
      and not (v_j -> 'items' -> 0 ? 'slot_id') and (v_j -> 'items' -> 0 ->> 'physical_card_id')::uuid = d1
      and v_txt = 'APPLIED;ALREADY_APPLIED'
      and exists (select 1 from public.collection_layout_slot_assignment a
                  join public.collection_layout_slot_species_reference sr on sr.slot_id = a.slot_id
                  where a.physical_card_id = d1 and sr.pokedex_position_id = v_pos)
      and v_err = 'AUTO_ARRANGE_UNSUPPORTED_COLLECTION',
      'detail','prévia sem ids de bolso; a representante vai para o bolso da espécie; repetir → ALREADY_APPLIED; coleção livre não organiza');
    res := res || jsonb_build_object('id','2.2','ok',
      exists (select 1 from public.binder_activity_event e where e.layout_key = l_d and e.actor_user_id = u_b
              and e.event_type = 'CARDS_AUTO_ARRANGED' and e.collection_id = v_cd and e.source = 'FICHARIO')
      and not exists (select 1 from public.binder_activity_item i join public.binder_activity_event e on e.id = i.event_id
                      where e.layout_key = l_d and e.actor_user_id = u_b and i.collection_id is distinct from v_cd),
      'detail','evento CARDS_AUTO_ARRANGED com o EDITOR e CD; itens só de CD');
    res := res || jsonb_build_object('id','2.3','ok', v_err2 = 'AUTO_ARRANGE_PLAN_CHANGED' and n3 = 0,
      'detail','exemplar posicionado entre prévia e confirmação → AUTO_ARRANGE_PLAN_CHANGED, nada gravado; com o estado de volta, o mesmo token aplica');

    -- 3. Novidades do Catálogo (Master Set exclusivo) ---------------------------------------------
    select string_agg(md5((to_jsonb(e) - 'updated_at')::text), ',' order by e.slot_id) into v_s1
      from public.collection_layout_slot_expected_content e
      join public.collection_layout_slot s on s.id = e.slot_id join public.collection_layout_page pg on pg.id = s.page_id
     where pg.layout_id = l_m;
    select count(*) into n3 from public.collection_layout_slot_expected_content;
    select md5((to_jsonb(c) - 'updated_at')::text)
           || ':' || coalesce((select string_agg(f.variant_type_id::text, ',' order by f.variant_type_id)
                               from public.collection_master_set_finish f where f.collection_id = v_cm), '-')
      into v_s2 from public.collection c where c.id = v_cm;
    perform pg_temp.wh_5893_as(u_b);
    select pv.plan_token into v_tok from public.editor_preview_binder_catalog_reconciliation(v_cm, array[v_key3]) pv
     where pv.row_kind = 'HEADER';
    select * into p from public.editor_apply_binder_catalog_reconciliation(v_cm, array[v_key3], v_tok);
    execute 'reset role';
    res := res || jsonb_build_object('id','3.1','ok', p.outcome = 'APPLIED' and p.reservations_created = 1
      and exists (select 1 from public.collection_layout_catalog_incorporation ci
                  where ci.layout_id = l_m and ci.collection_id = v_cm and ci.item_key = v_key3)
      and exists (select 1 from public.binder_activity_event e where e.layout_key = l_m and e.actor_user_id = u_b
                  and e.event_type = 'CATALOG_NOVELTIES_INCORPORATED' and e.source = 'CATALOGO' and e.collection_id = v_cm),
      'detail','novidade incorporada pelo EDITOR: reserva criada, registro de incorporação, evento com origem CATALOGO');
    res := res || jsonb_build_object('id','3.3','ok',
      (select string_agg(md5((to_jsonb(e) - 'updated_at')::text), ',' order by e.slot_id)
         from public.collection_layout_slot_expected_content e
         join public.collection_layout_slot s on s.id = e.slot_id join public.collection_layout_page pg on pg.id = s.page_id
        where pg.layout_id = l_m and e.card_id <> m3) = v_s1
      and (select count(*) from public.collection_layout_slot_expected_content) = n3 + 1
      and (select count(*) from public.collection_layout_slot_expected_content e where e.card_id = m3 and e.collection_id is null) = 1
      and (select array_agg(ci.item_key) from public.collection_layout_catalog_incorporation ci where ci.layout_id = l_m) = array[v_key3]
      and (select md5((to_jsonb(c) - 'updated_at')::text)
                  || ':' || coalesce((select string_agg(f.variant_type_id::text, ',' order by f.variant_type_id)
                                      from public.collection_master_set_finish f where f.collection_id = v_cm), '-')
             from public.collection c where c.id = v_cm) = v_s2,
      'detail','efeitos da incorporação: só uma reserva nova (de CM) e um registro; reservas existentes, coleção, Set e acabamentos intactos');
    select * into q from public.binder_catalog_plan(v_cm, array[v_key4]) pl where pl.row_kind = 'ITEM';
    insert into public.collection_layout_slot_image (slot_id, owner_user_id, storage_path)
    values (pg_temp.wh_5893_slot(l_m, q.target_page, q.target_row, q.target_column), u_a, u_a::text || '/' || l_m::text || '/wh5893.webp');
    select pl.plan_token into v_tok from public.binder_catalog_plan(v_cm, array[v_key4]) pl where pl.row_kind = 'HEADER';
    perform pg_temp.wh_5893_as(u_b);
    v_err := pg_temp.wh_5893_try(format('select * from public.editor_preview_binder_catalog_reconciliation(%L, %L)', v_cm, array[v_key4]))
          || ';' || pg_temp.wh_5893_try(format('select * from public.editor_apply_binder_catalog_reconciliation(%L, %L, %L, true, true)',
                                               v_cm, array[v_key4], v_tok))
          || ';' || pg_temp.wh_5893_try(format('select * from public.editor_preview_binder_catalog_reconciliation(%L)', v_cd));
    execute 'reset role';
    res := res || jsonb_build_object('id','3.2','ok',
      v_err ~ '^OPERATION_RESERVED_TO_OWNER;OPERATION_RESERVED_TO_OWNER;(NOT_MASTER_SET|BINDER_NOT_ELIGIBLE)'
      and not exists (select 1 from public.collection_layout_slot_expected_content e
                      join public.collection_layout_slot s on s.id = e.slot_id
                      join public.collection_layout_page pg on pg.id = s.page_id
                      where pg.layout_id = l_m and e.card_id = m4),
      'detail','imagem do titular no bolso natural: prévia e aplicação (com token válido) recusadas, nada criado; Pokédex não incorpora');

    -- 4. Tipos de evento e recusas ------------------------------------------------------------------
    res := res || jsonb_build_object('id','4.1','ok',
      not exists (select 1 from public.binder_activity_event e
                  where e.layout_key in (l_f, l_d, l_m) and e.actor_user_id in (u_b, u_e)
                    and not ((e.event_type in ('CARD_PLACED', 'CARD_MOVED', 'CARDS_SWAPPED', 'CARDS_REMOVED',
                                               'POCKET_RESERVED', 'RESERVATIONS_RELEASED', 'POCKETS_LOCKED', 'POCKETS_UNLOCKED',
                                               'PAGES_ADDED', 'PAGE_REMOVED', 'PAGES_REORDERED',
                                               'GAP_OPENED', 'GAP_CLOSED', 'CARDS_AUTO_ARRANGED') and e.source = 'FICHARIO')
                             or (e.event_type = 'CATALOG_NOVELTIES_INCORPORATED' and e.source = 'CATALOGO'))),
      'detail','todo evento do EDITOR tem par (tipo, origem) da lista fechada');
    perform pg_temp.wh_5893_as(u_b);
    n := (select count(*) from public.collection_layout_page p2 where p2.layout_id = l_f);
    perform set_config('mmkyu.binder_activity_ctx', jsonb_build_object('depth', 1, 'layout', l_f, 'type', 'GAP_OPENED',
      'source', 'CATALOGO', 'collection', v_cf, 'summary', '{}'::jsonb, 'event_id', null, 'n', 0, 'cap', 0)::text, true);
    v_err := pg_temp.wh_5893_try(format('select * from public.editor_add_binder_page(%L)', v_cf));
    perform set_config('mmkyu.binder_activity_ctx', jsonb_build_object('depth', 1, 'layout', l_f, 'type', 'CATALOG_NOVELTIES_INCORPORATED',
      'source', 'FICHARIO', 'collection', v_cf, 'summary', '{}'::jsonb, 'event_id', null, 'n', 0, 'cap', 0)::text, true);
    v_err := v_err || ';' || pg_temp.wh_5893_try(format('select * from public.editor_add_binder_page(%L)', v_cf));
    perform set_config('mmkyu.binder_activity_ctx', '', true);
    execute 'reset role';
    res := res || jsonb_build_object('id','4.2','ok',
      v_err = 'binder activity: event type not allowed for this actor;binder activity: event type not allowed for this actor'
      and (select count(*) from public.collection_layout_page p2 where p2.layout_id = l_f) = n,
      'detail','tipo novo com origem trocada (forjado) → recusa; a operação inteira é desfeita');
    v_err := '';
    foreach v_u in array array[u_v, u_c, u_r, u_a] loop
      perform pg_temp.wh_5893_as(v_u);
      v_err := v_err || pg_temp.wh_5893_try(format('select * from public.editor_preview_binder_insert_gap(%L, 1, 1, 1)', v_cf)) || ';';
    end loop;
    perform pg_temp.wh_5893_as(null);
    v_err := v_err || pg_temp.wh_5893_try(format('select public.editor_apply_binder_auto_arrange(%L, %L)', v_cd, 'aa1:' || repeat('0', 64)));
    execute 'reset role';
    res := res || jsonb_build_object('id','4.3','ok',
      v_err ~ ('^' || repeat('COLLECTION_NOT_FOUND;', 4) || 'permission denied'),
      'detail','VIEWER, estranho, ex-membro e titular pelo caminho do EDITOR → COLLECTION_NOT_FOUND; anon sem EXECUTE');
    select count(*) into n from public.binder_activity_event e where e.actor_user_id = u_b;
    perform pg_temp.wh_5893_as(u_a); perform public.set_collection_member_role(v_cf, m_b, 'VIEWER');
    perform pg_temp.wh_5893_as(u_b);
    v_err := pg_temp.wh_5893_try(format('select * from public.editor_close_binder_gap(%L, 1, 1, 1, 1, 1, 3, %L)', v_cf, 'u1:' || repeat('0', 64)));
    perform pg_temp.wh_5893_as(u_a); perform public.set_collection_member_role(v_cf, m_b, 'EDITOR');
    execute 'reset role';
    select count(*) into n2 from public.binder_activity_event e where e.actor_user_id = u_b;
    res := res || jsonb_build_object('id','4.4','ok', v_err = 'COLLECTION_NOT_FOUND' and n2 = n,
      'detail','EDITOR rebaixado perde as operações em massa na hora; nenhum evento depois');

    -- 5. Titular intocado ----------------------------------------------------------------------------
    perform pg_temp.wh_5893_as(u_a);
    select * into p from public.preview_my_binder_insert_gap(v_cf, pg_temp.wh_5893_slot(l_f, 1, 1, 1));
    select * into q from public.insert_my_binder_gap(v_cf, pg_temp.wh_5893_slot(l_f, 1, 1, 1), p.plan_token, true, true);
    perform count(*) from public.close_my_binder_gap(v_cf, q.gap_slot_id, q.end_slot_id, q.undo_token, q.added_page_id);
    execute 'reset role';
    res := res || jsonb_build_object('id','5.1','ok', q.outcome = 'INSERTED'
      and pg_temp.wh_5893_at(l_f, f1) = '1:1:1' and pg_temp.wh_5893_at(l_f, f2) = '1:1:2'
      and exists (select 1 from public.binder_activity_event e where e.layout_key = l_f and e.actor_user_id = u_a
                  and e.event_type = 'GAP_OPENED'),
      'detail','titular continua inserindo espaço sobre a imagem dele e fechando (5283/5284); evento do titular gravado');

    -- 6. Patrimônio -----------------------------------------------------------------------------------
    res := res || jsonb_build_object('id','6.1','ok',
      (select string_agg(ca.physical_card_id::text || ':' || ca.collection_id::text, ',' order by ca.physical_card_id)
         from public.collection_allocation ca where ca.physical_card_id in (f1, f2, g1, d1)) = alloc0
      and (select string_agg(md5((to_jsonb(pc) - 'updated_at')::text), ',' order by pc.id)
             from public.physical_card pc where pc.id in (f1, f2, g1, d1)) = pc0,
      'detail','nenhuma alocação, local, condição ou outro campo de exemplar mudou');

    -- 7. Coleção arquivada -----------------------------------------------------------------------------
    perform pg_temp.wh_5893_as(u_a); perform public.archive_collection(v_cd);
    perform pg_temp.wh_5893_as(u_b);
    v_err := pg_temp.wh_5893_try(format('select public.editor_preview_binder_auto_arrange(%L)', v_cd))
          || ';' || pg_temp.wh_5893_try(format('select public.editor_apply_binder_auto_arrange(%L, %L)', v_cd, 'aa1:' || repeat('0', 64)));
    execute 'reset role';
    res := res || jsonb_build_object('id','7.1','ok', v_err = 'COLLECTION_ARCHIVED;COLLECTION_ARCHIVED',
      'detail','coleção arquivada: EDITOR recusado só depois de autorizado');

    execute 'reset role';
    raise exception 'MS893' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MS893' then
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
               (select count(*) from public.collection_layout_slot), (select count(*) from public.collection_layout_slot_assignment),
               (select count(*) from public.collection_layout_slot_expected_content),
               (select count(*) from public.collection_layout_catalog_incorporation),
               (select count(*) from public.binder_activity_event), (select count(*) from public.binder_activity_item),
               (select count(*) from public.card)]
    into e_counts;
  res := res || jsonb_build_object('id','99.1','ok', b_counts = e_counts and current_user = session_user,
    'detail','resíduo zero (13 contagens, inclusive posições, reservas, incorporações e histórico) e papel restaurado');

  v_expected := 24;
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
