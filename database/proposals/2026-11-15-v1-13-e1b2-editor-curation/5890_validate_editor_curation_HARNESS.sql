/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5890 - Harness V1-13 · E1-B2 (5375–5377): reservas, liberação, fixação,
              metadados, capa e Storage da capa pelo EDITOR; titular intocado;
              sem efeito patrimonial; resíduo zero
Versão......: 1.1 (2026-11-15; 5377 v1.1 — ajudantes separados, exclusão real 6.10)
Status......: PROPOSTA — NÃO EXECUTADA. Prova DINÂMICA da E1-B2. Sem ambiente
              isolado (C-244): executar SOMENTE sob protocolo controlado
              equivalente ao P1 da E1-A (transação explícita READ WRITE terminada
              em erro/ROLLBACK, conexão direta única, psql), depois da E1-A e da
              E1-B1, com autorização expressa e específica. Sem BEGIN/COMMIT
              próprios; não é comando pronto para produção.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-15

Pressupõe aplicadas: E1-A 5366–5370, E1-B1 5371–5374, E1-B2 5375–5377.

Usuários efêmeros: A titular · B EDITOR de CO · V VIEWER de CO · E EDITOR de CX
(convidada) · R EDITOR de CO removido · C estranho. Catálogo sintético (K1, K2,
K3). Sentinela MS890 desfaz a fixture por subtransação; 99.1 prova resíduo zero
(inclui storage.objects).

  select * from pg_temp.wh_5890_validate();
  -- GATE esperado: 45/45 PASS (44 verificações + F.2)

Fichário 3×3 de CO, CX convidada, página 1:
  r1c1 a1 (CO)          r1c2 x1 (CX)        r1c3 reserva de CX (K3)
  r2c1 livre            r2c2 FIXADO vazio   r2c3 livre
  r3c1–r3c2 MESCLAGEM   r3c3 IMAGEM do titular
CO é coleção livre (tem imagem de placa); CX também.

Limitações declaradas:
  L1 SET LOCAL ROLE prova o banco, não o JWT do PostgREST nem a API do Storage:
     o envio e a remoção pela API (upload/remove) só se comprovam na
     homologação; aqui as políticas são provadas por INSERT direto em
     storage.objects com o papel authenticated; a de exclusão por DELETE direto
     (6.9), com `storage.allow_delete_query` ligado só na transação (mesmo
     recurso da 5852). Se o gatilho do Storage usar outro GUC no ambiente, 6.10
     falha com o erro do gatilho: ler como proteção extra do Storage, não como
     defeito da 5377.
  L2 Referência de espécie: só por inspeção (fixture Pokédex = E1-B3).
  L3 Concorrência (S8 concorrente, S10): PENDENTE. Inclui o teto de envio sob
     corrida: a 5890 roda numa sessão só e prova a trava apenas
     estruturalmente (0.5); envios paralelos só pela API, na homologação.
================================================================
*/

create or replace function pg_temp.wh_5890_as(p_user uuid)
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

create or replace function pg_temp.wh_5890_slot(p_layout uuid, p_row integer, p_col integer)
returns uuid language sql stable as $sl$
  select s.id from public.collection_layout_slot s
  join public.collection_layout_page p on p.id = s.page_id
  where p.layout_id = p_layout and p.page_number = 1 and s.row_index = p_row and s.column_index = p_col;
$sl$;

create or replace function pg_temp.wh_5890_res(p_layout uuid, p_row integer, p_col integer)
returns text language sql stable as $rs$
  -- reserva do bolso: "<card_id>:<collection_id>" ou NULL
  select e.card_id::text || ':' || coalesce(e.collection_id::text, '-')
  from public.collection_layout_slot_expected_content e
  where e.slot_id = pg_temp.wh_5890_slot(p_layout, p_row, p_col);
$rs$;

create or replace function pg_temp.wh_5890_locked(p_layout uuid, p_row integer, p_col integer)
returns boolean language sql stable as $lk$
  select s.locked from public.collection_layout_slot s where s.id = pg_temp.wh_5890_slot(p_layout, p_row, p_col);
$lk$;

create or replace function pg_temp.wh_5890_try(p_sql text)
returns text language plpgsql volatile as $try$
begin
  execute p_sql;
  return 'OK';
exception when others then
  return sqlerrm;
end;
$try$;

create or replace function pg_temp.wh_5890_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  f_res oid := to_regprocedure('public.editor_set_binder_reservation(uuid, integer, integer, integer, uuid, uuid, uuid)');
  f_clr oid := to_regprocedure('public.editor_clear_binder_reservation(uuid, integer, integer, integer)');
  f_lck oid := to_regprocedure('public.editor_set_binder_lock(uuid, integer, integer, integer, boolean)');
  f_ace oid := to_regprocedure('public.assert_collection_editor(uuid)');
  f_md  oid := to_regprocedure('public.editor_update_collection_metadata(uuid, text, text)');
  f_fin oid := to_regprocedure('public.editor_set_collection_cover_finish(uuid, text)');
  f_cod oid := to_regprocedure('public.editor_set_collection_cover_code(uuid, text)');
  f_logo oid := to_regprocedure('public.editor_set_collection_cover_logo(uuid, text)');
  f_fok oid := to_regprocedure('public.collection_cover_editor_folder_ok(text)');
  f_upl oid := to_regprocedure('public.collection_cover_editor_can_upload(text)');
  u_a uuid := gen_random_uuid(); u_b uuid := gen_random_uuid(); u_v uuid := gen_random_uuid();
  u_e uuid := gen_random_uuid(); u_r uuid := gen_random_uuid(); u_c uuid := gen_random_uuid();
  v_sfx text := lower(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  v_game uuid; v_pt uuid; v_rar uuid; v_cat uuid; v_std uuid; v_exp uuid; v_set uuid;
  k1 uuid; k1s uuid; k2 uuid; k2s uuid; k3 uuid; k3s uuid;
  v_inv_a uuid; a1 uuid; x1 uuid; v_ids uuid[];
  v_bin uuid; v_co uuid; v_cx uuid; v_layout uuid; v_lc uuid;
  m_b uuid; m_v uuid; m_e uuid; m_r uuid;
  p record; v_err text; v_ok boolean; n integer;
  f1 text; f2 text; f3 text; f4 text; fa text; fx text;
  alloc0 text; stor0 text;
  b_counts bigint[]; e_counts bigint[];
  res jsonb := '[]'::jsonb; r jsonb; cnt integer := 0; passes integer := 0;
  v_expected integer := 0;
begin
  -- 0. Estrutura ---------------------------------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    (select bool_and(q.prosecdef and q.proconfig @> array['search_path=""']
                     and has_function_privilege('authenticated', q.oid, 'EXECUTE')
                     and not has_function_privilege('anon', q.oid, 'EXECUTE'))
       from pg_proc q where q.oid in (f_res, f_clr, f_lck, f_md, f_fin, f_cod, f_logo))
    and (select count(*) from pg_proc q where q.oid in (f_res, f_clr, f_lck, f_md, f_fin, f_cod, f_logo)) = 7,
    'detail','7 RPCs do EDITOR: definer, search_path vazio, só authenticated');
  res := res || jsonb_build_object('id','0.2','ok',
    f_ace is not null and not has_function_privilege('authenticated', f_ace, 'EXECUTE')
    and not has_function_privilege('service_role', f_ace, 'EXECUTE')
    and f_fok is not null and has_function_privilege('authenticated', f_fok, 'EXECUTE')
    and not has_function_privilege('anon', f_fok, 'EXECUTE')
    and f_upl is not null and has_function_privilege('authenticated', f_upl, 'EXECUTE')
    and not has_function_privilege('anon', f_upl, 'EXECUTE')
    and to_regprocedure('public.collection_cover_editor_folder_ok(text, boolean)') is null,
    'detail','assert_collection_editor interna; os dois ajudantes das políticas só para authenticated');
  res := res || jsonb_build_object('id','0.3','ok',
    (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.set_slot_expected_content(uuid, uuid, uuid, uuid, uuid)')) = '33dde5013dbb491bd4a0452ab7ce8132'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.clear_slot_expected_content(uuid[])')) = '0b8f26825ff713a24226548ffe3a63b7'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.set_slot_lock(uuid[], boolean)')) = '651048a4bf7d3229904ef2a073c509c5'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.update_collection_metadata(uuid, text, text)')) = 'a581235db9cabaf7043707a290f963b7'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.set_my_collection_cover_finish(uuid, text)')) = '4f48d9161b4a29ecb23e7443e31d1806'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.set_my_collection_cover_code(uuid, text)')) = 'd0d8cbfa517b9da3728a55af47de21cb'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.set_my_collection_cover_logo(uuid, text)')) = '5868fb1c8de760787d1128ac20a09507'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.assert_collection_layout_mutable(uuid)')) = 'd600f36fade0b67c0fd5af33e9965070',
    'detail','titular: 5276–5278, 5035, 5172, 5178, 5180 e 5122 byte a byte canônicas');
  res := res || jsonb_build_object('id','0.4','ok',
    (select count(*) from pg_policies pp where pp.schemaname = 'storage' and pp.tablename = 'objects'
      and pp.policyname in ('collection_cover_insert_editor', 'collection_cover_select_editor', 'collection_cover_delete_editor')
      and pp.roles = array['authenticated']::name[]) = 3
    and not exists (select 1 from pg_policies pp where pp.schemaname = 'storage' and pp.tablename = 'objects'
                    and pp.policyname like 'collection_cover_%_editor' and pp.cmd = 'UPDATE')
    and (select count(*) from pg_policies pp where pp.schemaname = 'storage' and pp.tablename = 'objects'
          and pp.policyname like 'collection_cover_%_own') = 4,
    'detail','Storage: 3 políticas do EDITOR só para authenticated, nenhuma de UPDATE; as 4 do dono intactas');
  res := res || jsonb_build_object('id','0.5','ok',
    (select q.provolatile from pg_proc q where q.oid = f_upl) = 'v'
    and (select q.provolatile from pg_proc q where q.oid = f_fok) = 's'
    and position('pg_advisory_xact_lock' in (select q.prosrc from pg_proc q where q.oid = f_upl))
        between 1 and position('count(*)' in (select q.prosrc from pg_proc q where q.oid = f_upl))
    and (select pp.with_check from pg_policies pp where pp.schemaname = 'storage' and pp.tablename = 'objects'
          and pp.policyname = 'collection_cover_insert_editor') like '%collection_cover_editor_can_upload(name)%'
    and (select string_agg(pp.qual, '|' order by pp.policyname) from pg_policies pp where pp.schemaname = 'storage'
          and pp.tablename = 'objects' and pp.policyname in ('collection_cover_select_editor', 'collection_cover_delete_editor'))
        ~ '^[^|]*collection_cover_editor_folder_ok\(name\)[^|]*\|[^|]*collection_cover_editor_folder_ok\(name\)[^|]*$',
    'detail','envio por ajudante VOLÁTIL com trava (EDITOR, coleção) antes da contagem; ver/apagar pelo ajudante STABLE (prova estrutural, não de corrida)');

  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.collection_membership), (select count(*) from public.collection_layout_slot_expected_content),
               (select count(*) from public.binder_activity_event), (select count(*) from storage.objects)]
    into b_counts;

  begin
    -- F. Fixture ---------------------------------------------------------------------------
    select g.id into v_game from public.game g where g.code = 'POKEMON';
    select l.id into v_pt from public.language l where l.code = 'pt-BR';
    select t.id into v_std from public.card_variant_type t where t.game_id = v_game and t.code = 'STANDARD';
    select c0.rarity_id, c0.category_id into v_rar, v_cat
    from public.card c0 join public.card_set cs0 on cs0.id = c0.card_set_id
    join public.expansion e0 on e0.id = cs0.expansion_id where e0.game_id = v_game limit 1;
    if v_game is null or v_pt is null or v_std is null or v_rar is null then
      res := res || jsonb_build_object('id','F.1','ok', false, 'detail','pré-requisitos de catálogo ausentes');
      raise exception 'MS890' using errcode = 'P0001';
    end if;
    insert into public.expansion (game_id, code, name, release_order)
    values (v_game, 'EB2_' || upper(v_sfx), 'EB2 Harness ' || v_sfx,
            (select coalesce(max(x.release_order), 0) + 1000 from public.expansion x where x.game_id = v_game))
    returning id into v_exp;
    insert into public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_exp, 'EB2' || upper(v_sfx), 'EB2 Set ' || v_sfx, 'REGULAR', 1, 3, 3) returning id into v_set;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '1', 1, 'EB2 K1', true) returning id into k1;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '2', 2, 'EB2 K2', true) returning id into k2;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '3', 3, 'EB2 K3', true) returning id into k3;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k1, v_std, 1, true) returning id into k1s;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k2, v_std, 1, true) returning id into k2s;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k3, v_std, 1, true) returning id into k3s;

    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    select u.id, 'authenticated', 'authenticated', 'wh890' || u.t || '_' || v_sfx || '@example.invalid',
           jsonb_build_object('username', 'wh890' || u.t || '_' || v_sfx, 'display_name', 'WH 5890 ' || upper(u.t)), now(), now()
    from (values (u_a, 'a'), (u_b, 'b'), (u_v, 'v'), (u_e, 'e'), (u_r, 'r'), (u_c, 'c')) u(id, t);
    select i.id into v_inv_a from public.inventory i where i.owner_user_id = u_a;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, created_at)
    select v.cv, v_pt, v_inv_a, now() - (v.o || ' min')::interval from (values (k1s, 2), (k3s, 1)) v(cv, o);
    select array_agg(pc.id order by pc.created_at) into v_ids from public.physical_card pc where pc.inventory_id = v_inv_a;
    a1 := v_ids[1]; x1 := v_ids[2];

    perform pg_temp.wh_5890_as(u_a);
    select x.storage_container_id into v_bin from public.create_my_storage_container(gen_random_uuid(), 'BIN 5890', 'BINDER') x;
    select x.collection_id into v_co from public.create_my_free_collection(gen_random_uuid(), 'CO 5890', v_bin) x;
    perform public.allocate_physical_cards_to_collection(v_co, array[a1]);
    select * into p from public.preview_my_collection_binder(v_co, 3, 3, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_co, 3, 3, 'PRINCIPAL_ONLY', p.plan_token);
    execute 'reset role';
    select l.id, l.storage_container_id into v_layout, v_lc from public.collection_layout l where l.collection_id = v_co;
    delete from public.collection_layout_slot_assignment a using public.collection_layout_slot s, public.collection_layout_page p2
     where a.slot_id = s.id and s.page_id = p2.id and p2.layout_id = v_layout;
    delete from public.collection_layout_slot_expected_content e using public.collection_layout_slot s, public.collection_layout_page p2
     where e.slot_id = s.id and s.page_id = p2.id and p2.layout_id = v_layout;
    update public.physical_card pc set storage_container_id = v_lc where pc.id in (a1, x1);
    perform pg_temp.wh_5890_as(u_a);
    select x.collection_id into v_cx from public.create_my_free_collection(gen_random_uuid(), 'CX 5890', v_lc) x;
    perform public.allocate_physical_cards_to_collection(v_cx, array[x1]);
    perform public.attach_my_collection_to_binder(v_cx, v_layout);
    perform public.place_my_physical_card_in_slot(v_co, pg_temp.wh_5890_slot(v_layout, 1, 1), a1);
    perform public.place_my_physical_card_in_slot(v_cx, pg_temp.wh_5890_slot(v_layout, 1, 2), x1);
    perform public.set_slot_expected_content(pg_temp.wh_5890_slot(v_layout, 1, 3), k3, null, null, v_cx);
    perform public.set_slot_lock(array[pg_temp.wh_5890_slot(v_layout, 2, 2)], true);
    m_b := (public.invite_collection_member(v_co, 'wh890b_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_v := (public.invite_collection_member(v_co, 'wh890v_' || v_sfx) ->> 'membership_id')::uuid;
    m_r := (public.invite_collection_member(v_co, 'wh890r_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_e := (public.invite_collection_member(v_cx, 'wh890e_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    perform pg_temp.wh_5890_as(u_b); perform public.respond_collection_invite(m_b, true);
    perform pg_temp.wh_5890_as(u_v); perform public.respond_collection_invite(m_v, true);
    perform pg_temp.wh_5890_as(u_r); perform public.respond_collection_invite(m_r, true);
    perform pg_temp.wh_5890_as(u_e); perform public.respond_collection_invite(m_e, true);
    perform pg_temp.wh_5890_as(u_a); perform public.remove_collection_member(v_co, m_r);
    execute 'reset role';
    -- Mesclagem e imagem do titular (passo privilegiado; gatilhos 5232/5238 ativos).
    insert into public.collection_layout_region (page_id, top_row, left_column, height, width)
    values ((select p2.id from public.collection_layout_page p2 where p2.layout_id = v_layout and p2.page_number = 1), 3, 1, 1, 2);
    insert into public.collection_layout_slot_image (slot_id, owner_user_id, storage_path)
    values (pg_temp.wh_5890_slot(v_layout, 3, 3), u_a, u_a::text || '/' || v_layout::text || '/wh5890.webp');
    select string_agg(ca.physical_card_id::text || ':' || ca.collection_id::text, ',' order by ca.physical_card_id) into alloc0
      from public.collection_allocation ca where ca.physical_card_id in (a1, x1);
    select string_agg(pc.id::text || ':' || coalesce(pc.storage_container_id::text, '-'), ',' order by pc.id) into stor0
      from public.physical_card pc where pc.id in (a1, x1);
    res := res || jsonb_build_object('id','F.2','ok',
      v_lc is not null and (select count(*) from public.collection_layout_slot s join public.collection_layout_page p2 on p2.id = s.page_id
                             where p2.layout_id = v_layout and p2.page_number = 1) = 9
      and pg_temp.wh_5890_locked(v_layout, 2, 2) and pg_temp.wh_5890_res(v_layout, 1, 3) = k3::text || ':' || v_cx::text,
      'detail','fixture: fichário 3×3, CX convidada, carta/reserva de CX, fixado vazio, mesclagem e imagem do titular');

    -- 1. Reservar --------------------------------------------------------------------------------
    perform pg_temp.wh_5890_as(u_b);
    select x.operation into v_err from public.editor_set_binder_reservation(v_co, 1, 2, 1, k1) x;
    res := res || jsonb_build_object('id','1.1','ok', v_err = 'RESERVED' and pg_temp.wh_5890_res(v_layout, 2, 1) = k1::text || ':' || v_co::text,
      'detail','bolso livre: reserva criada e registrada para CO');
    select x.operation into v_err from public.editor_set_binder_reservation(v_co, 1, 2, 1, k1) x;
    res := res || jsonb_build_object('id','1.2','ok', v_err = 'UNCHANGED', 'detail','mesma reserva → UNCHANGED (sem evento)');
    select x.operation into v_err from public.editor_set_binder_reservation(v_co, 1, 2, 1, k2) x;
    res := res || jsonb_build_object('id','1.3','ok', v_err = 'REPLACED' and pg_temp.wh_5890_res(v_layout, 2, 1) = k2::text || ':' || v_co::text,
      'detail','reserva de CO trocada por outra carta → REPLACED, continua de CO');
    select x.operation into v_err from public.editor_set_binder_reservation(v_co, 1, 1, 1, k1) x;
    res := res || jsonb_build_object('id','1.4','ok', v_err = 'RESERVED' and pg_temp.wh_5890_res(v_layout, 1, 1) = k1::text || ':' || v_co::text,
      'detail','bolso com carta de CO aceita reserva da própria carta');
    v_err := pg_temp.wh_5890_try(format('select * from public.editor_set_binder_reservation(%L, 1, 1, 3, %L)', v_co, k1))
          || ';' || pg_temp.wh_5890_try(format('select * from public.editor_set_binder_reservation(%L, 1, 1, 2, %L)', v_co, k1))
          || ';' || pg_temp.wh_5890_try(format('select * from public.editor_set_binder_reservation(%L, 1, 2, 2, %L)', v_co, k1))
          || ';' || pg_temp.wh_5890_try(format('select * from public.editor_set_binder_reservation(%L, 1, 3, 1, %L)', v_co, k1))
          || ';' || pg_temp.wh_5890_try(format('select * from public.editor_set_binder_reservation(%L, 1, 3, 3, %L)', v_co, k1))
          || ';' || pg_temp.wh_5890_try(format('select * from public.editor_set_binder_reservation(%L, 9, 1, 1, %L)', v_co, k1));
    res := res || jsonb_build_object('id','1.5','ok',
      v_err = repeat('SLOT_NOT_EDITABLE;', 5) || 'SLOT_NOT_EDITABLE'
      and pg_temp.wh_5890_res(v_layout, 1, 3) = k3::text || ':' || v_cx::text
      and pg_temp.wh_5890_res(v_layout, 2, 2) is null and pg_temp.wh_5890_res(v_layout, 3, 1) is null,
      'detail','reserva de CX, carta de CX, fixado vazio, mesclagem, imagem e posição inexistente → a MESMA recusa; nada muda');
    v_err := pg_temp.wh_5890_try(format('select * from public.editor_set_binder_reservation(%L, 1, 2, 3, %L, %L, %L)', v_co, k1, k1s, v_std));
    res := res || jsonb_build_object('id','1.6','ok', v_err like 'EXPECTED_CONTENT_VARIANT_AND_TYPE_EXCLUSIVE%' and pg_temp.wh_5890_res(v_layout, 2, 3) is null,
      'detail','variante e acabamento ao mesmo tempo → recusa (mesma regra do titular)');
    perform pg_temp.wh_5890_as(u_v); v_err := pg_temp.wh_5890_try(format('select * from public.editor_set_binder_reservation(%L, 1, 2, 3, %L)', v_co, k1));
    perform pg_temp.wh_5890_as(u_c); v_err := v_err || ';' || pg_temp.wh_5890_try(format('select * from public.editor_set_binder_reservation(%L, 1, 2, 3, %L)', v_co, k1));
    perform pg_temp.wh_5890_as(u_r); v_err := v_err || ';' || pg_temp.wh_5890_try(format('select * from public.editor_set_binder_reservation(%L, 1, 2, 3, %L)', v_co, k1));
    perform pg_temp.wh_5890_as(u_a); v_err := v_err || ';' || pg_temp.wh_5890_try(format('select * from public.editor_set_binder_reservation(%L, 1, 2, 3, %L)', v_co, k1));
    perform pg_temp.wh_5890_as(u_e); v_err := v_err || ';' || pg_temp.wh_5890_try(format('select * from public.editor_set_binder_reservation(%L, 1, 2, 3, %L)', v_co, k1));
    res := res || jsonb_build_object('id','1.7','ok', v_err = 'COLLECTION_NOT_FOUND;COLLECTION_NOT_FOUND;COLLECTION_NOT_FOUND;COLLECTION_NOT_FOUND;COLLECTION_NOT_FOUND'
      and pg_temp.wh_5890_res(v_layout, 2, 3) is null,
      'detail','VIEWER, estranho, ex-EDITOR, titular e EDITOR de CX em CO → COLLECTION_NOT_FOUND');
    execute 'reset role';
    res := res || jsonb_build_object('id','1.8','ok',
      (select string_agg(ca.physical_card_id::text || ':' || ca.collection_id::text, ',' order by ca.physical_card_id)
         from public.collection_allocation ca where ca.physical_card_id in (a1, x1)) = alloc0
      and (select count(*) from public.collection_allocation ca where ca.collection_id = v_co) = 1,
      'detail','reservar não aloca nada');

    -- 2. Liberar ---------------------------------------------------------------------------------
    perform pg_temp.wh_5890_as(u_b);
    select x.operation into v_err from public.editor_clear_binder_reservation(v_co, 1, 2, 1) x;
    res := res || jsonb_build_object('id','2.1','ok', v_err = 'RELEASED' and pg_temp.wh_5890_res(v_layout, 2, 1) is null,
      'detail','reserva de CO liberada');
    select x.operation into v_err from public.editor_clear_binder_reservation(v_co, 1, 2, 1) x;
    res := res || jsonb_build_object('id','2.2','ok', v_err = 'UNCHANGED', 'detail','sem reserva → UNCHANGED (sem evento)');
    v_err := pg_temp.wh_5890_try(format('select * from public.editor_clear_binder_reservation(%L, 1, 1, 3)', v_co))
          || ';' || pg_temp.wh_5890_try(format('select * from public.editor_clear_binder_reservation(%L, 1, 2, 2)', v_co));
    res := res || jsonb_build_object('id','2.3','ok', v_err = 'SLOT_NOT_EDITABLE;SLOT_NOT_EDITABLE'
      and pg_temp.wh_5890_res(v_layout, 1, 3) = k3::text || ':' || v_cx::text,
      'detail','liberar reserva de CX ou mexer em bolso fixado vazio → recusa; reserva de CX intacta');
    perform pg_temp.wh_5890_as(u_e);
    v_err := pg_temp.wh_5890_try(format('select * from public.editor_clear_binder_reservation(%L, 1, 1, 1)', v_cx));
    select x.operation into fx from public.editor_set_binder_reservation(v_cx, 1, 2, 3, k3) x;
    res := res || jsonb_build_object('id','2.4','ok', v_err = 'SLOT_NOT_EDITABLE' and fx = 'RESERVED'
      and pg_temp.wh_5890_res(v_layout, 1, 1) = k1::text || ':' || v_co::text
      and pg_temp.wh_5890_res(v_layout, 2, 3) = k3::text || ':' || v_cx::text,
      'detail','EDITOR de CX não libera reserva de CO; reserva dele fica registrada para CX');

    -- 3. Fixar / soltar -------------------------------------------------------------------------
    perform pg_temp.wh_5890_as(u_b);
    select x.operation into v_err from public.editor_set_binder_lock(v_co, 1, 1, 1, true) x;
    select x.operation into fx from public.editor_set_binder_lock(v_co, 1, 1, 1, true) x;
    res := res || jsonb_build_object('id','3.1','ok', v_err = 'LOCKED' and fx = 'UNCHANGED' and pg_temp.wh_5890_locked(v_layout, 1, 1),
      'detail','fixar bolso de CO → LOCKED; repetir → UNCHANGED');
    select x.operation into v_err from public.editor_set_binder_lock(v_co, 1, 1, 1, false) x;
    res := res || jsonb_build_object('id','3.2','ok', v_err = 'UNLOCKED' and not pg_temp.wh_5890_locked(v_layout, 1, 1),
      'detail','soltar bolso de CO → UNLOCKED');
    v_err := pg_temp.wh_5890_try(format('select * from public.editor_set_binder_lock(%L, 1, 2, 1, true)', v_co))
          || ';' || pg_temp.wh_5890_try(format('select * from public.editor_set_binder_lock(%L, 1, 2, 2, false)', v_co))
          || ';' || pg_temp.wh_5890_try(format('select * from public.editor_set_binder_lock(%L, 1, 1, 2, true)', v_co))
          || ';' || pg_temp.wh_5890_try(format('select * from public.editor_set_binder_lock(%L, 1, 2, 3, true)', v_co))
          || ';' || pg_temp.wh_5890_try(format('select * from public.editor_set_binder_lock(%L, 1, 3, 1, true)', v_co));
    res := res || jsonb_build_object('id','3.3','ok', v_err = repeat('SLOT_NOT_EDITABLE;', 4) || 'SLOT_NOT_EDITABLE'
      and not pg_temp.wh_5890_locked(v_layout, 2, 1) and pg_temp.wh_5890_locked(v_layout, 2, 2)
      and not pg_temp.wh_5890_locked(v_layout, 1, 2) and not pg_temp.wh_5890_locked(v_layout, 2, 3),
      'detail','fixar livre, soltar fixado vazio do titular, fixar carta/reserva de CX e mesclagem → a MESMA recusa; travas intactas');
    perform pg_temp.wh_5890_as(u_e);
    select x.operation into v_err from public.editor_set_binder_lock(v_cx, 1, 1, 2, true) x;
    select x.operation into fx from public.editor_set_binder_lock(v_cx, 1, 1, 2, false) x;
    res := res || jsonb_build_object('id','3.4','ok', v_err = 'LOCKED' and fx = 'UNLOCKED',
      'detail','EDITOR de CX fixa e solta o bolso com carta de CX');

    -- 4. Metadados ------------------------------------------------------------------------------
    perform pg_temp.wh_5890_as(u_b);
    select x.name || '|' || coalesce(x.description, '') into v_err from public.editor_update_collection_metadata(v_co, '  Nova CO 5890  ', 'descrição B') x;
    res := res || jsonb_build_object('id','4.1','ok', v_err = 'Nova CO 5890|descrição B',
      'detail','EDITOR altera nome (sem brancos nas pontas) e descrição');
    v_err := pg_temp.wh_5890_try(format('select * from public.editor_update_collection_metadata(%L, %L, null)', v_co, '   '));
    res := res || jsonb_build_object('id','4.2','ok', v_err like 'p_name não pode ser vazio%', 'detail','nome vazio recusado');
    v_err := pg_temp.wh_5890_try(format('select * from public.update_collection_metadata(%L, %L, null)', v_co, 'X'))
          || ';' || pg_temp.wh_5890_try(format('select public.set_collection_visibility(%L, %L)', v_co, 'PUBLIC'))
          || ';' || pg_temp.wh_5890_try(format('select public.archive_collection(%L)', v_co))
          || ';' || pg_temp.wh_5890_try(format('select * from public.set_my_collection_cover_finish(%L, %L)', v_co, 'vinho'));
    execute 'reset role';
    res := res || jsonb_build_object('id','4.3','ok', v_err !~ '(^|;)OK(;|$)'
      and (select c.name || ':' || c.visibility || ':' || c.lifecycle_status from public.collection c where c.id = v_co) = 'Nova CO 5890:PRIVATE:ACTIVE',
      'detail','caminhos do titular (metadados, visibilidade, arquivar, capa) recusam o EDITOR: ' || v_err);
    res := res || jsonb_build_object('id','4.4','ok',
      not exists (select 1 from pg_proc q, unnest(q.proargnames) a(name)
                  where q.oid in (f_md, f_fin, f_cod, f_logo)
                    and a.name ~ '(visib|policy|reference|card_set|scope|finish_scope|archive|member|owner|mode)'),
      'detail','RPCs de metadados sem parâmetro para Set, escopo, política, modalidade, visibilidade, arquivamento, membros ou titular');
    perform pg_temp.wh_5890_as(u_v);
    v_err := pg_temp.wh_5890_try(format('select * from public.editor_update_collection_metadata(%L, %L, null)', v_co, 'V'));
    perform pg_temp.wh_5890_as(u_c);
    v_err := v_err || ';' || pg_temp.wh_5890_try(format('select * from public.editor_update_collection_metadata(%L, %L, null)', v_co, 'C'));
    perform pg_temp.wh_5890_as(u_e);
    v_err := v_err || ';' || pg_temp.wh_5890_try(format('select * from public.editor_update_collection_metadata(%L, %L, null)', v_co, 'E'));
    perform pg_temp.wh_5890_as(null);
    v_err := v_err || ';' || pg_temp.wh_5890_try(format('select * from public.editor_update_collection_metadata(%L, %L, null)', v_co, 'anon'));
    execute 'reset role';
    res := res || jsonb_build_object('id','4.5','ok', v_err ~ '^COLLECTION_NOT_FOUND;COLLECTION_NOT_FOUND;COLLECTION_NOT_FOUND;permission denied'
      and (select c.name from public.collection c where c.id = v_co) = 'Nova CO 5890',
      'detail','VIEWER, estranho, EDITOR de outra coleção e anon não alteram metadados');

    -- 5. Capa (acabamento e código) --------------------------------------------------------------
    perform pg_temp.wh_5890_as(u_b);
    v_err := pg_temp.wh_5890_try(format('select public.editor_set_collection_cover_finish(%L, %L)', v_co, 'floresta'))
          || ';' || pg_temp.wh_5890_try(format('select public.editor_set_collection_cover_finish(%L, %L)', v_co, 'neon'))
          || ';' || pg_temp.wh_5890_try(format('select public.editor_set_collection_cover_code(%L, %L)', v_co, 'cob2'));
    execute 'reset role';
    res := res || jsonb_build_object('id','5.1','ok', v_err = 'OK;INVALID_FINISH;OK'
      and (select c.cover_finish || ':' || c.cover_code from public.collection c where c.id = v_co) = 'floresta:COB2',
      'detail','acabamento e código da capa da coleção pelo EDITOR; acabamento inválido recusado');
    res := res || jsonb_build_object('id','5.2','ok',
      (select l.storage_container_id from public.collection_layout l where l.id = v_layout) = v_lc
      and not exists (select 1 from pg_proc q where q.oid in (f_md, f_fin, f_cod, f_logo)
                      and q.prosrc ~* '(collection_layout|slot_image|region_image)'),
      'detail','metadados e capa não tocam identidade, acabamento, âncora nem imagens do fichário');

    -- 6. Storage e imagem da placa --------------------------------------------------------------
    f1 := u_a::text || '/' || v_co::text || '/' || gen_random_uuid()::text || '.webp';
    f2 := u_a::text || '/' || v_co::text || '/' || gen_random_uuid()::text || '.webp';
    f3 := u_a::text || '/' || v_co::text || '/' || gen_random_uuid()::text || '.webp';
    f4 := u_a::text || '/' || v_co::text || '/' || gen_random_uuid()::text || '.webp';
    fa := u_a::text || '/' || v_co::text || '/' || gen_random_uuid()::text || '.webp';
    fx := u_a::text || '/' || v_cx::text || '/' || gen_random_uuid()::text || '.webp';
    insert into storage.objects (bucket_id, name, owner_id) values ('collection-cover', fa, u_a::text);   -- arquivo do titular
    perform pg_temp.wh_5890_as(u_b);
    v_err := pg_temp.wh_5890_try(format('insert into storage.objects (bucket_id, name, owner_id) values (%L, %L, %L)', 'collection-cover', f1, u_b))
          || ';' || pg_temp.wh_5890_try(format('insert into storage.objects (bucket_id, name, owner_id) values (%L, %L, %L)', 'collection-cover', f2, u_b))
          || ';' || pg_temp.wh_5890_try(format('insert into storage.objects (bucket_id, name, owner_id) values (%L, %L, %L)', 'collection-cover', f3, u_b))
          || ';' || pg_temp.wh_5890_try(format('insert into storage.objects (bucket_id, name, owner_id) values (%L, %L, %L)', 'collection-cover', f4, u_b));
    res := res || jsonb_build_object('id','6.1','ok', v_err ~ '^OK;OK;OK;new row violates row-level security',
      'detail','EDITOR envia até 3 arquivos ainda não usados na pasta do titular da coleção autorizada; o 4º é recusado pela política');
    v_err := pg_temp.wh_5890_try(format('insert into storage.objects (bucket_id, name, owner_id) values (%L, %L, %L)', 'collection-cover', fx, u_b))
          || ';' || pg_temp.wh_5890_try(format('insert into storage.objects (bucket_id, name, owner_id) values (%L, %L, %L)', 'collection-cover',
                                               u_a::text || '/' || v_co::text || '/x.webp', u_b));
    res := res || jsonb_build_object('id','6.2','ok', v_err ~ '^new row violates row-level security.*;new row violates row-level security',
      'detail','pasta de outra coleção do titular e nome fora do formato → recusados');
    perform pg_temp.wh_5890_as(u_v);
    v_err := pg_temp.wh_5890_try(format('insert into storage.objects (bucket_id, name, owner_id) values (%L, %L, %L)', 'collection-cover', f4, u_v));
    perform pg_temp.wh_5890_as(null);
    v_err := v_err || ';' || pg_temp.wh_5890_try(format('insert into storage.objects (bucket_id, name, owner_id) values (%L, %L, null)', 'collection-cover', f4));
    res := res || jsonb_build_object('id','6.3','ok', v_err ~ '^new row violates row-level security.*;(new row violates|permission denied)',
      'detail','VIEWER e anon não enviam para a pasta do titular');
    perform pg_temp.wh_5890_as(u_b);
    select count(*) into n from storage.objects o where o.bucket_id = 'collection-cover' and o.name in (f1, f2, f3, fa);
    res := res || jsonb_build_object('id','6.4','ok', n = 3,
      'detail','EDITOR vê só os 3 arquivos dele; o arquivo do titular não aparece');
    select x.cover_logo_path || '|' || coalesce(x.removable_previous_path, '-') into v_err from public.editor_set_collection_cover_logo(v_co, f1) x;
    select x.cover_logo_path || '|' || coalesce(x.removable_previous_path, '-') into fx from public.editor_set_collection_cover_logo(v_co, f2) x;
    res := res || jsonb_build_object('id','6.5','ok', v_err = f1 || '|-' and fx = f2 || '|' || f1,
      'detail','capa com arquivo do EDITOR; trocar devolve o anterior (dele) para exclusão');
    select x.cover_logo_path || '|' || coalesce(x.removable_previous_path, '-') into v_err from public.editor_set_collection_cover_logo(v_co, fa) x;
    select x.cover_logo_path || '|' || coalesce(x.removable_previous_path, '-') into fx from public.editor_set_collection_cover_logo(v_co, f3) x;
    res := res || jsonb_build_object('id','6.6','ok', v_err = fa || '|' || f2 and fx = f3 || '|-',
      'detail','arquivo do titular pode ser usado, mas nunca é oferecido para exclusão');
    v_err := pg_temp.wh_5890_try(format('select * from public.editor_set_collection_cover_logo(%L, %L)', v_co, u_b::text || '/' || v_co::text || '/' || gen_random_uuid()::text || '.webp'))
          || ';' || pg_temp.wh_5890_try(format('select * from public.editor_set_collection_cover_logo(%L, %L)', v_co, u_a::text || '/' || v_co::text || '/' || gen_random_uuid()::text || '.webp'));
    res := res || jsonb_build_object('id','6.7','ok', v_err = 'INVALID_COVER_PATH;COVER_FILE_NOT_FOUND',
      'detail','arquivo na pasta do próprio EDITOR → INVALID_COVER_PATH; arquivo inexistente → COVER_FILE_NOT_FOUND');
    res := res || jsonb_build_object('id','6.8','ok',
      public.collection_cover_editor_folder_ok(f1) and not public.collection_cover_editor_folder_ok(f3)
      and not public.collection_cover_editor_folder_ok(fx),
      'detail','exclusão: arquivo antigo dele permitido; a capa atual e outra coleção, não (a política também exige owner_id = EDITOR)');
    perform set_config('storage.allow_delete_query', 'true', true);
    v_err := '';
    for fx in select unnest(array[fa, f3, f1]) loop
      execute 'with d as (delete from storage.objects o where o.bucket_id = ''collection-cover'' and o.name = $1 returning 1) select count(*)::int from d'
        into n using fx;
      v_err := v_err || n::text;
    end loop;
    res := res || jsonb_build_object('id','6.9','ok', v_err = '001',
      'detail','DELETE direto como EDITOR: arquivo do titular 0 linhas, capa atual 0 linhas, arquivo antigo dele 1 linha');
    execute 'reset role';
    res := res || jsonb_build_object('id','6.10','ok',
      (select c.cover_logo_path from public.collection c where c.id = v_co) = f3
      and exists (select 1 from storage.objects o where o.name = fa and o.owner_id = u_a::text)
      and exists (select 1 from storage.objects o where o.name = f3)
      and not exists (select 1 from storage.objects o where o.name = f1),
      'detail','capa final = arquivo do EDITOR e continua no Storage; arquivo do titular continua com o titular; o antigo dele saiu');

    -- 7. Troca de papel ------------------------------------------------------------------------
    perform pg_temp.wh_5890_as(u_a); perform public.set_collection_member_role(v_co, m_b, 'VIEWER');
    perform pg_temp.wh_5890_as(u_b);
    v_err := pg_temp.wh_5890_try(format('select * from public.editor_set_binder_reservation(%L, 1, 2, 1, %L)', v_co, k1))
          || ';' || pg_temp.wh_5890_try(format('select * from public.editor_set_binder_lock(%L, 1, 1, 1, true)', v_co))
          || ';' || pg_temp.wh_5890_try(format('select * from public.editor_update_collection_metadata(%L, %L, null)', v_co, 'Z'));
    n := case when public.collection_cover_editor_can_upload(f1) then 1 else 0 end;
    perform pg_temp.wh_5890_as(u_a); perform public.set_collection_member_role(v_co, m_b, 'EDITOR');
    execute 'reset role';
    res := res || jsonb_build_object('id','7.1','ok', v_err = 'COLLECTION_NOT_FOUND;COLLECTION_NOT_FOUND;COLLECTION_NOT_FOUND' and n = 0,
      'detail','EDITOR rebaixado a VIEWER perde reservar, fixar, metadados e envio na hora');

    -- 8. Histórico ------------------------------------------------------------------------------
    res := res || jsonb_build_object('id','8.1','ok',
      exists (select 1 from public.binder_activity_event e where e.layout_key = v_layout and e.actor_user_id = u_b
              and e.event_type = 'POCKET_RESERVED' and e.collection_id = v_co and e.owner_user_id = u_a)
      and exists (select 1 from public.binder_activity_event e where e.layout_key = v_layout and e.actor_user_id = u_b
                  and e.event_type = 'RESERVATIONS_RELEASED' and e.collection_id = v_co)
      and exists (select 1 from public.binder_activity_event e where e.layout_key = v_layout and e.actor_user_id = u_b
                  and e.event_type in ('POCKETS_LOCKED', 'POCKETS_UNLOCKED') and e.collection_id = v_co)
      and exists (select 1 from public.binder_activity_event e where e.layout_key = v_layout and e.actor_user_id = u_e
                  and e.collection_id = v_cx)
      and not exists (select 1 from public.binder_activity_event e where e.layout_key = v_layout and e.actor_user_id in (u_v, u_c, u_r)),
      'detail','reservar, liberar, fixar e soltar geram eventos com o EDITOR como ator e a coleção autorizada; recusas não geram evento');

    -- 9. Titular intocado ------------------------------------------------------------------------
    perform pg_temp.wh_5890_as(u_a);
    perform public.set_slot_expected_content(pg_temp.wh_5890_slot(v_layout, 2, 1), k2, null, null, v_cx);
    perform public.clear_slot_expected_content(array[pg_temp.wh_5890_slot(v_layout, 1, 3)]);
    perform public.set_slot_lock(array[pg_temp.wh_5890_slot(v_layout, 2, 2)], false);
    perform public.update_collection_metadata(v_co, 'CO 5890', null);
    execute 'reset role';
    res := res || jsonb_build_object('id','9.1','ok',
      pg_temp.wh_5890_res(v_layout, 2, 1) = k2::text || ':' || v_cx::text and pg_temp.wh_5890_res(v_layout, 1, 3) is null
      and not pg_temp.wh_5890_locked(v_layout, 2, 2) and (select c.name from public.collection c where c.id = v_co) = 'CO 5890',
      'detail','titular continua reservando para CX, liberando, soltando e editando metadados (5276–5278, 5035)');

    -- 10. Patrimônio ------------------------------------------------------------------------------
    res := res || jsonb_build_object('id','10.1','ok',
      (select string_agg(ca.physical_card_id::text || ':' || ca.collection_id::text, ',' order by ca.physical_card_id)
         from public.collection_allocation ca where ca.physical_card_id in (a1, x1)) = alloc0
      and (select string_agg(pc.id::text || ':' || coalesce(pc.storage_container_id::text, '-'), ',' order by pc.id)
             from public.physical_card pc where pc.id in (a1, x1)) = stor0
      and (select c.owner_user_id from public.collection c where c.id = v_co) = u_a,
      'detail','alocações, locais físicos e titularidade intactos');

    -- 11. Coleção arquivada ------------------------------------------------------------------------
    perform pg_temp.wh_5890_as(u_a); perform public.archive_collection(v_cx);
    perform pg_temp.wh_5890_as(u_e);
    v_err := pg_temp.wh_5890_try(format('select * from public.editor_set_binder_reservation(%L, 1, 2, 3, %L)', v_cx, k1))
          || ';' || pg_temp.wh_5890_try(format('select * from public.editor_set_binder_lock(%L, 1, 1, 2, true)', v_cx))
          || ';' || pg_temp.wh_5890_try(format('select * from public.editor_update_collection_metadata(%L, %L, null)', v_cx, 'E'));
    execute 'reset role';
    res := res || jsonb_build_object('id','11.1','ok', v_err = 'COLLECTION_ARCHIVED;COLLECTION_ARCHIVED;COLLECTION_ARCHIVED',
      'detail','convidada arquivada: EDITOR de CX não reserva, não fixa, não edita metadados');

    execute 'reset role';
    raise exception 'MS890' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MS890' then
      res := res || jsonb_build_object('id','X.1','ok', false, 'detail','erro inesperado: '||sqlstate||' '||sqlerrm);
    end if;
  end;

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.collection_membership), (select count(*) from public.collection_layout_slot_expected_content),
               (select count(*) from public.binder_activity_event), (select count(*) from storage.objects)]
    into e_counts;
  res := res || jsonb_build_object('id','99.1','ok', b_counts = e_counts and current_user = session_user,
    'detail','resíduo zero (8 contagens, inclusive storage.objects) e papel restaurado');

  v_expected := 45;
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

-- Execução: somente sob protocolo controlado (C-244), com autorização específica.
-- Chamada: select * from pg_temp.wh_5890_validate();
