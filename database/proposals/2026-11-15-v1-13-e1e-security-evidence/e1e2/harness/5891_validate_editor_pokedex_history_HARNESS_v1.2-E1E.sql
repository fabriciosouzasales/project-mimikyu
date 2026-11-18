/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5891 - Harness V1-13 · E1-B3 (5378–5380): Pokédex pelo EDITOR,
              referência de espécie no bolso, coleção por item do histórico,
              contexto forjado, revogação; titular intocado; sem efeito
              patrimonial; resíduo zero
Versão......: 1.2-E1E (2026-11-16, `G2_B/G2_C — MGMTAPI READINESS CORRECTION-01`, só o harness):
              conferências internas de estado (classe B) que liam tabelas de fichário,
              histórico, alocação ou referências sob o papel do CLIENTE (EDITOR/estranho)
              passam a ler no contexto do dono (reset role → instrução → wh_5891_as do mesmo
              usuário). Sob o cliente, a RLS "select_own" devolvia vazio (resultado falso) e
              as tabelas revogadas (histórico, referências) dariam 42501. Linhas "-- E1E".
              Chamadas às RPCs (classe A) e negativas (classe C) intactas; nenhuma
              verificação removida, nenhum critério alterado. Original preservado.
              1.1 (2026-11-15, `E1-E2 | CANONICAL BASELINE RECONCILIATION AND G2 CORRECTION-02`,
              defeito E2-D1: 0.3 conferia o md5 da 6122; passa ao da 6123, corpo
              canônico vigente). 1.0 (2026-11-15)
Status......: PROPOSTA — NÃO EXECUTADA. Prova DINÂMICA da E1-B3. Sem ambiente
              isolado (C-244): executar SOMENTE sob protocolo controlado
              equivalente ao P1 da E1-A (transação explícita READ WRITE terminada
              em erro/ROLLBACK, conexão direta única, psql), depois da E1-A, E1-B1,
              E1-B2 e E1-B3, com autorização expressa e específica. Sem
              BEGIN/COMMIT próprios; não é comando pronto para produção.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-15

Pressupõe aplicadas: E1-A 5366–5370, E1-B1 5371–5374, E1-B2 5375–5377,
E1-B3 5378–5380.

Usuários efêmeros: A titular · B EDITOR de CP (Pokédex, proprietária do
fichário) · V VIEWER de CP · R EDITOR de CP removido · E EDITOR de CX (coleção
livre convidada) · C estranho · D outra conta (coleção livre com d1).
Catálogo sintético: K1 (Pokémon, espécie da posição P1), K2 e K3 (Pokémon, sem
espécie). Posições P1–P3: as três primeiras da geração da 1ª posição nacional
(mesma regra da 5850). Sentinela MS891 desfaz a fixture por subtransação;
99.1 prova resíduo zero.

  select * from pg_temp.wh_5891_validate();
  -- GATE esperado: 33/33 PASS (32 verificações + F.2)

Fichário 3×3 de CP, CX convidada, página 1:
  r1c1 ref. P1 (CP)    r1c2 ref. P2 (CP)    r1c3 ref. P3 (CP)
  r2c1 livre           r2c2 livre           r2c3 livre
  r3c1 livre           r3c2 livre           r3c3 livre
Exemplares de A: a1 (K1), a3 (K1), a2 (K2) alocados a CP; x1 (K3) alocado a
CX; n1 (K2) sem coleção. d1 (K2) é de D. Todos no local do fichário, exceto d1.

Limitações declaradas:
  L1 SET LOCAL ROLE prova o banco, não o JWT do PostgREST.
  L2 Concorrência titular × EDITOR (S8 concorrente, S10), inclusive Pokédex e
     histórico: PENDENTE (sessão única).
  L3 Leitura do histórico para membros: E1-D. Aqui só a gravação (coleção por
     item, marca do evento) é provada.
  L4 md5 das funções do titular da Pokédex (6123/6124/6126/6125) derivados dos
     arquivos; 0.3 falha se o LIVE divergir.
================================================================
*/

create or replace function pg_temp.wh_5891_as(p_user uuid)
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

create or replace function pg_temp.wh_5891_slot(p_layout uuid, p_row integer, p_col integer)
returns uuid language sql stable as $sl$
  select s.id from public.collection_layout_slot s
  join public.collection_layout_page p on p.id = s.page_id
  where p.layout_id = p_layout and p.page_number = 1 and s.row_index = p_row and s.column_index = p_col;
$sl$;

create or replace function pg_temp.wh_5891_try(p_sql text)
returns text language plpgsql volatile as $try$
begin
  execute p_sql;
  return 'OK';
exception when others then
  return sqlerrm;
end;
$try$;

create or replace function pg_temp.wh_5891_last_event(p_layout uuid, p_actor uuid, p_type text)
returns bigint language sql stable as $le$
  select max(e.id) from public.binder_activity_event e
  where e.layout_key = p_layout and e.actor_user_id = p_actor and e.event_type = p_type;
$le$;

create or replace function pg_temp.wh_5891_item_colls(p_event bigint)
returns text language sql stable as $ic$
  -- "<kind>:<coleção ou ->" de cada item, em ordem
  select string_agg(i.item_kind || ':' || coalesce(i.collection_id::text, '-'), ',' order by i.ordinal)
  from public.binder_activity_item i where i.event_id = p_event;
$ic$;

create or replace function pg_temp.wh_5891_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
as $fn$
#variable_conflict use_column
declare
  f_set oid := to_regprocedure('public.editor_set_pokedex_position_assignment(uuid, uuid, uuid, boolean)');
  f_rem oid := to_regprocedure('public.editor_remove_pokedex_position_assignment(uuid, uuid)');
  f_rep oid := to_regprocedure('public.editor_set_pokedex_position_primary_representative(uuid, uuid)');
  f_clr oid := to_regprocedure('public.editor_clear_pokedex_position_primary_representative(uuid, uuid)');
  f_dex oid := to_regprocedure('public.editor_pokedex_of_collection(uuid)');
  f_add oid := to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)');
  f_scp oid := to_regprocedure('public.binder_slot_editor_scope(uuid, uuid, uuid, uuid)');
  u_a uuid := gen_random_uuid(); u_b uuid := gen_random_uuid(); u_v uuid := gen_random_uuid();
  u_r uuid := gen_random_uuid(); u_e uuid := gen_random_uuid(); u_c uuid := gen_random_uuid();
  u_d uuid := gen_random_uuid();
  v_sfx text := lower(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  v_game uuid; v_pt uuid; v_rar uuid; v_cat uuid; v_std uuid; v_exp uuid; v_set uuid;
  v_gen text; v_pos uuid[]; p1 uuid; p2 uuid; p3 uuid; s1 uuid;
  k1 uuid; k1s uuid; k2 uuid; k2s uuid; k3 uuid; k3s uuid;
  v_inv_a uuid; v_inv_d uuid; a1 uuid; a2 uuid; a3 uuid; x1 uuid; n1 uuid; d1 uuid;
  v_bin uuid; v_bind uuid; v_cp uuid; v_cx uuid; v_dx uuid; v_layout uuid; v_lc uuid;
  m_b uuid; m_v uuid; m_r uuid; m_e uuid;
  p record; v_err text; v_txt text; v_txt2 text; v_txt3 text; v_u uuid; n integer; n2 integer; v_ev bigint; v_ev2 bigint;
  alloc0 text; pc0 text;
  b_counts bigint[]; e_counts bigint[];
  res jsonb := '[]'::jsonb; r jsonb; cnt integer := 0; passes integer := 0;
  v_expected integer := 0;
begin
  -- 0. Estrutura ---------------------------------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    (select count(*) from pg_proc q where q.oid in (f_set, f_rem, f_rep, f_clr)
       and q.prosecdef and q.proconfig @> array['search_path=""']
       and has_function_privilege('authenticated', q.oid, 'EXECUTE')
       and not has_function_privilege('anon', q.oid, 'EXECUTE')) = 4
    and f_dex is not null and not has_function_privilege('authenticated', f_dex, 'EXECUTE')
    and not has_function_privilege('service_role', f_dex, 'EXECUTE'),
    'detail','4 RPCs de Pokédex do EDITOR: definer, search_path vazio, só authenticated; ajudante interno');
  res := res || jsonb_build_object('id','0.2','ok',
    (select md5(q.prosrc) from pg_proc q where q.oid = f_scp) = '21f1b51a3a0f6c80337c2c593cc6054f'
    and (select md5(q.prosrc) from pg_proc q where q.oid = f_add) = 'f8cfba40e442e85056e7c8ce7954d4f4'
    and not has_function_privilege('authenticated', f_add, 'EXECUTE')
    and not has_function_privilege('authenticated', to_regprocedure('public.binder_activity_begin(uuid, text, text, uuid, jsonb)'), 'EXECUTE')
    and (select c.is_nullable from information_schema.columns c where c.table_schema = 'public'
          and c.table_name = 'binder_activity_item' and c.column_name = 'collection_id') = 'YES'
    and (select c.is_nullable || ':' || c.column_default from information_schema.columns c where c.table_schema = 'public'
          and c.table_name = 'binder_activity_event' and c.column_name = 'item_collection_recorded') = 'NO:false',
    'detail','5378 e 5379 no lugar; histórico sem EXECUTE para a API; colunas de atribuição como esperado');
  res := res || jsonb_build_object('id','0.3','ok',
    (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.set_pokedex_position_assignment(uuid, uuid, boolean)')) = '8c572182a03025503e993e5ecc25e07a'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.remove_pokedex_position_assignment(uuid)')) = '26ef2d5da3312661111df0194dfc8ba2'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.set_pokedex_position_primary_representative(uuid)')) = '6353dffe6c3877967997033dcc2bfd4c'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.clear_pokedex_position_primary_representative(uuid, uuid)')) = 'eeede3a5b871fbf07f81eb59ecea932f'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.place_my_physical_card_in_slot(uuid, uuid, uuid)')) = '2672da179d73797ec5329c649b594202'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.move_slot_assignment(uuid, uuid)')) = 'fe149c755b5f3b9181172e600c2238a3'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.set_slot_expected_content(uuid, uuid, uuid, uuid, uuid)')) = '33dde5013dbb491bd4a0452ab7ce8132'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.set_slot_lock(uuid[], boolean)')) = '651048a4bf7d3229904ef2a073c509c5'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.assert_collection_layout_mutable(uuid)')) = 'd600f36fade0b67c0fd5af33e9965070',
    'detail','titular: Pokédex (6123, 6124, 6126, 6125) e fichário (5272, 5273, 5276, 5278, 5122) byte a byte canônicos');
  res := res || jsonb_build_object('id','0.4','ok',
    not exists (select 1 from public.binder_activity_event e
                join public.binder_activity_item i on i.event_id = e.id
                where not e.item_collection_recorded and i.collection_id is not null)
    and not exists (select 1 from public.binder_activity_event e
                    where e.source = 'LEGADO' and e.item_collection_recorded),
    'detail','histórico anterior (e legado L01) nunca tem item atribuído: nenhuma atribuição retroativa');

  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.collection_membership), (select count(*) from public.binder_activity_event),
               (select count(*) from public.binder_activity_item), (select count(*) from public.collection_pokedex_position_assignment),
               (select count(*) from public.collection_pokedex_position_primary_representative),
               (select count(*) from public.collection_layout_slot_species_reference), (select count(*) from public.card_primary_species)]
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
    select g.code, array_agg(pp.id order by pp.position_number)
      into v_gen, v_pos
    from public.pokedex dx
    join public.pokedex_position pp on pp.pokedex_id = dx.id
    join public.pokemon_species sp on sp.id = pp.species_id
    join public.pokemon_generation g on g.id = sp.generation_id
    where dx.code = 'NATIONAL'
      and g.id = (select sp2.generation_id from public.pokedex_position pp2
                  join public.pokemon_species sp2 on sp2.id = pp2.species_id
                  where pp2.pokedex_id = dx.id order by pp2.position_number limit 1)
    group by g.code;
    p1 := v_pos[1]; p2 := v_pos[2]; p3 := v_pos[3];
    select pp.species_id into s1 from public.pokedex_position pp where pp.id = p1;
    if v_game is null or v_pt is null or v_std is null or v_cat is null or v_rar is null or p3 is null then
      res := res || jsonb_build_object('id','F.1','ok', false, 'detail','pré-requisitos de catálogo ou Pokédex NATIONAL ausentes');
      raise exception 'MS891' using errcode = 'P0001';
    end if;
    insert into public.expansion (game_id, code, name, release_order)
    values (v_game, 'EB3_' || upper(v_sfx), 'EB3 Harness ' || v_sfx,
            (select coalesce(max(x.release_order), 0) + 1000 from public.expansion x where x.game_id = v_game))
    returning id into v_exp;
    insert into public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_exp, 'EB3' || upper(v_sfx), 'EB3 Set ' || v_sfx, 'REGULAR', 1, 3, 3) returning id into v_set;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '1', 1, 'EB3 K1', true) returning id into k1;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '2', 2, 'EB3 K2', true) returning id into k2;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '3', 3, 'EB3 K3', true) returning id into k3;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k1, v_std, 1, true) returning id into k1s;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k2, v_std, 1, true) returning id into k2s;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k3, v_std, 1, true) returning id into k3s;

    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    select u.id, 'authenticated', 'authenticated', 'wh891' || u.t || '_' || v_sfx || '@example.invalid',
           jsonb_build_object('username', 'wh891' || u.t || '_' || v_sfx, 'display_name', 'WH 5891 ' || upper(u.t)), now(), now()
    from (values (u_a, 'a'), (u_b, 'b'), (u_v, 'v'), (u_r, 'r'), (u_e, 'e'), (u_c, 'c'), (u_d, 'd')) u(id, t);
    insert into public.card_primary_species (card_id, pokemon_species_id, resolution_basis, resolved_by_user_id)
    values (k1, s1, 'EDITORIAL_RECONCILIATION', u_a);
    select i.id into v_inv_a from public.inventory i where i.owner_user_id = u_a;
    select i.id into v_inv_d from public.inventory i where i.owner_user_id = u_d;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, created_at)
    select v.cv, v_pt, v_inv_a, now() - (v.o || ' min')::interval
    from (values (k1s, 5), (k2s, 4), (k1s, 3), (k3s, 2), (k2s, 1)) v(cv, o);
    select array_agg(pc.id order by pc.created_at) into v_pos from public.physical_card pc where pc.inventory_id = v_inv_a;
    a1 := v_pos[1]; a2 := v_pos[2]; a3 := v_pos[3]; x1 := v_pos[4]; n1 := v_pos[5];
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (k2s, v_pt, v_inv_d) returning id into d1;

    perform pg_temp.wh_5891_as(u_d);
    select x.storage_container_id into v_bind from public.create_my_storage_container(gen_random_uuid(), 'BIN D 5891', 'BINDER') x;
    select x.collection_id into v_dx from public.create_my_free_collection(gen_random_uuid(), 'DX 5891', v_bind) x;
    perform public.allocate_physical_cards_to_collection(v_dx, array[d1]);

    perform pg_temp.wh_5891_as(u_a);
    select x.storage_container_id into v_bin from public.create_my_storage_container(gen_random_uuid(), 'BIN 5891', 'BINDER') x;
    select x.collection_id into v_cp from public.create_my_pokedex_collection(gen_random_uuid(), 'CP 5891', array[v_gen], v_bin) x;
    perform public.allocate_physical_cards_to_collection(v_cp, array[a1, a2, a3]);
    select * into p from public.preview_my_collection_binder(v_cp, 3, 3, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_cp, 3, 3, 'PRINCIPAL_ONLY', p.plan_token);
    execute 'reset role';
    select l.id, l.storage_container_id into v_layout, v_lc from public.collection_layout l where l.collection_id = v_cp;
    delete from public.collection_layout_slot_assignment a using public.collection_layout_slot s, public.collection_layout_page p2
     where a.slot_id = s.id and s.page_id = p2.id and p2.layout_id = v_layout;
    delete from public.collection_layout_slot_expected_content e using public.collection_layout_slot s, public.collection_layout_page p2
     where e.slot_id = s.id and s.page_id = p2.id and p2.layout_id = v_layout;
    update public.physical_card pc set storage_container_id = v_lc where pc.id in (a1, a2, a3, x1, n1);
    delete from public.collection_layout_slot_species_reference sr where sr.layout_id = v_layout;
    insert into public.collection_layout_slot_species_reference (slot_id, layout_id, collection_id, pokedex_position_id)
    values (pg_temp.wh_5891_slot(v_layout, 1, 1), v_layout, v_cp, p1),
           (pg_temp.wh_5891_slot(v_layout, 1, 2), v_layout, v_cp, p2),
           (pg_temp.wh_5891_slot(v_layout, 1, 3), v_layout, v_cp, p3);
    perform pg_temp.wh_5891_as(u_a);
    select x.collection_id into v_cx from public.create_my_free_collection(gen_random_uuid(), 'CX 5891', v_lc) x;
    perform public.allocate_physical_cards_to_collection(v_cx, array[x1]);
    perform public.attach_my_collection_to_binder(v_cx, v_layout);
    m_b := (public.invite_collection_member(v_cp, 'wh891b_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_v := (public.invite_collection_member(v_cp, 'wh891v_' || v_sfx) ->> 'membership_id')::uuid;
    m_r := (public.invite_collection_member(v_cp, 'wh891r_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_e := (public.invite_collection_member(v_cx, 'wh891e_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    perform pg_temp.wh_5891_as(u_b); perform public.respond_collection_invite(m_b, true);
    perform pg_temp.wh_5891_as(u_v); perform public.respond_collection_invite(m_v, true);
    perform pg_temp.wh_5891_as(u_r); perform public.respond_collection_invite(m_r, true);
    perform pg_temp.wh_5891_as(u_e); perform public.respond_collection_invite(m_e, true);
    perform pg_temp.wh_5891_as(u_a); perform public.remove_collection_member(v_cp, m_r);
    execute 'reset role';
    select string_agg(ca.physical_card_id::text || ':' || ca.collection_id::text, ',' order by ca.physical_card_id) into alloc0
      from public.collection_allocation ca where ca.physical_card_id in (a1, a2, a3, x1, n1, d1);
    select string_agg(md5((to_jsonb(pc) - 'updated_at')::text), ',' order by pc.id) into pc0
      from public.physical_card pc where pc.id in (a1, a2, a3, x1, n1, d1);
    res := res || jsonb_build_object('id','F.2','ok',
      v_layout is not null
      and (select string_agg(a.collection_allocation_id::text || ':' || a.pokedex_position_id::text || ':' || a.assignment_basis, ',')
             from public.collection_pokedex_position_assignment a join public.collection_allocation ca on ca.id = a.collection_allocation_id
            where ca.collection_id = v_cp) is not null
      and (select count(*) from public.collection_pokedex_position_assignment a join public.collection_allocation ca on ca.id = a.collection_allocation_id
            where ca.collection_id = v_cp and a.pokedex_position_id = p1 and a.assignment_basis = 'SPECIES_MATCH') = 2
      and (select count(*) from public.collection_layout_slot_species_reference sr where sr.layout_id = v_layout) = 3
      and exists (select 1 from public.collection_layout_guest g where g.layout_id = v_layout and g.collection_id = v_cx),
      'detail','fixture: CP Pokédex com fichário 3×3 e 3 referências de espécie; a1/a3 em P1 pela 6119; CX convidada');

    -- 1. Posição Pokédex pelo EDITOR --------------------------------------------------------------
    perform pg_temp.wh_5891_as(u_b);
    v_err := pg_temp.wh_5891_try(format('select * from public.editor_set_pokedex_position_assignment(%L, %L, %L)', v_cp, a2, p2));
    select x.operation || ':' || x.assignment_basis into v_txt
      from public.editor_set_pokedex_position_assignment(v_cp, a2, p2, true) x;
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    res := res || jsonb_build_object('id','1.1','ok', v_err = 'CONFIRMATION_REQUIRED' and v_txt = 'CREATED:USER_OVERRIDE'
      and (select a.assigned_by_user_id from public.collection_pokedex_position_assignment a
             join public.collection_allocation ca on ca.id = a.collection_allocation_id where ca.physical_card_id = a2) = u_b,
      'detail','sem espécie correspondente exige confirmação; confirmado → CREATED/USER_OVERRIDE com o EDITOR registrado');
    perform pg_temp.wh_5891_as(u_b);  -- E1E: volta ao mesmo cliente
    select x.operation || ':' || x.assignment_basis into v_txt
      from public.editor_set_pokedex_position_assignment(v_cp, a1, p2, true) x;
    select x.operation || ':' || x.assignment_basis into v_txt2
      from public.editor_set_pokedex_position_assignment(v_cp, a1, p1) x;
    select x.operation into v_txt3 from public.editor_set_pokedex_position_assignment(v_cp, a1, p1) x;
    res := res || jsonb_build_object('id','1.2','ok', v_txt = 'MOVED:USER_OVERRIDE' and v_txt2 = 'MOVED:SPECIES_MATCH' and v_txt3 = 'UNCHANGED',
      'detail','mover para outra posição (confirmado), voltar por espécie (SPECIES_MATCH) e repetir → UNCHANGED');
    select x.operation into v_txt from public.editor_remove_pokedex_position_assignment(v_cp, a2) x;
    select x.operation into v_txt2 from public.editor_remove_pokedex_position_assignment(v_cp, a2) x;
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    res := res || jsonb_build_object('id','1.3','ok', v_txt = 'REMOVED' and v_txt2 = 'UNCHANGED'
      and exists (select 1 from public.collection_allocation ca where ca.physical_card_id = a2 and ca.collection_id = v_cp),
      'detail','retirar a posição não desaloca; repetir → UNCHANGED');
    perform pg_temp.wh_5891_as(u_b);  -- E1E: volta ao mesmo cliente
    v_err := pg_temp.wh_5891_try(format('select * from public.editor_set_pokedex_position_assignment(%L, %L, %L, true)', v_cp, a2, gen_random_uuid()));
    res := res || jsonb_build_object('id','1.4','ok', v_err = 'POKEDEX_POSITION_NOT_FOUND',
      'detail','posição inexistente ou de outra Pokédex → POKEDEX_POSITION_NOT_FOUND');

    -- 2. Representante pelo EDITOR ----------------------------------------------------------------
    select x.operation into v_txt from public.editor_set_pokedex_position_primary_representative(v_cp, a1) x;
    select x.operation into v_txt2 from public.editor_set_pokedex_position_primary_representative(v_cp, a3) x;
    select x.operation into v_txt3 from public.editor_set_pokedex_position_primary_representative(v_cp, a3) x;
    res := res || jsonb_build_object('id','2.1','ok', v_txt = 'SET' and v_txt2 = 'REPLACED' and v_txt3 = 'UNCHANGED',
      'detail','escolher, trocar e repetir o representante entre exemplares de CP na mesma posição');
    v_err := pg_temp.wh_5891_try(format('select * from public.editor_set_pokedex_position_primary_representative(%L, %L)', v_cp, a2));
    res := res || jsonb_build_object('id','2.2','ok', v_err = 'POKEDEX_ASSIGNMENT_NOT_FOUND',
      'detail','exemplar de CP sem posição não pode ser representante');
    select x.operation into v_txt from public.editor_clear_pokedex_position_primary_representative(v_cp, p1) x;
    select x.operation into v_txt2 from public.editor_clear_pokedex_position_primary_representative(v_cp, p1) x;
    res := res || jsonb_build_object('id','2.3','ok', v_txt = 'CLEARED' and v_txt2 = 'UNCHANGED',
      'detail','limpar o representante; repetir → UNCHANGED');
    perform public.editor_set_pokedex_position_primary_representative(v_cp, a3);
    perform public.editor_set_pokedex_position_assignment(v_cp, a3, p3, true);
    execute 'reset role';
    res := res || jsonb_build_object('id','2.4','ok',
      not exists (select 1 from public.collection_pokedex_position_primary_representative r
                  where r.collection_id = v_cp and r.pokedex_position_id = p1),
      'detail','mover o representante para outra posição remove o representante antigo em cascata (6120), como no titular');

    -- 3. Recusas da Pokédex -------------------------------------------------------------------------
    perform pg_temp.wh_5891_as(u_b);
    v_err := pg_temp.wh_5891_try(format('select * from public.editor_set_pokedex_position_assignment(%L, %L, %L, true)', v_cp, n1, p2))
          || ';' || pg_temp.wh_5891_try(format('select * from public.editor_set_pokedex_position_assignment(%L, %L, %L, true)', v_cp, x1, p2))
          || ';' || pg_temp.wh_5891_try(format('select * from public.editor_set_pokedex_position_assignment(%L, %L, %L, true)', v_cp, d1, p2))
          || ';' || pg_temp.wh_5891_try(format('select * from public.editor_set_pokedex_position_assignment(%L, %L, %L, true)', v_cp, gen_random_uuid(), p2))
          || ';' || pg_temp.wh_5891_try(format('select * from public.editor_set_pokedex_position_primary_representative(%L, %L)', v_cp, x1))
          || ';' || pg_temp.wh_5891_try(format('select * from public.editor_remove_pokedex_position_assignment(%L, %L)', v_cp, d1));
    res := res || jsonb_build_object('id','3.1','ok',
      v_err = 'PHYSICAL_CARD_NOT_ELIGIBLE;PHYSICAL_CARD_NOT_ELIGIBLE;PHYSICAL_CARD_NOT_ELIGIBLE;PHYSICAL_CARD_NOT_ELIGIBLE;PHYSICAL_CARD_NOT_ELIGIBLE;PHYSICAL_CARD_NOT_ELIGIBLE',
      'detail','sem alocação, de outra coleção, de outra conta ou inexistente → a mesma recusa, nos três caminhos');
    v_err := '';
    foreach v_u in array array[u_v, u_c, u_r, u_a] loop
      perform pg_temp.wh_5891_as(v_u);
      v_err := v_err || pg_temp.wh_5891_try(format('select * from public.editor_set_pokedex_position_assignment(%L, %L, %L, true)', v_cp, a2, p2)) || ';';
    end loop;
    perform pg_temp.wh_5891_as(null);
    v_err := v_err || pg_temp.wh_5891_try(format('select * from public.editor_clear_pokedex_position_primary_representative(%L, %L)', v_cp, p1));
    res := res || jsonb_build_object('id','3.2','ok',
      v_err ~ '^COLLECTION_NOT_FOUND;COLLECTION_NOT_FOUND;COLLECTION_NOT_FOUND;COLLECTION_NOT_FOUND;permission denied',
      'detail','VIEWER, estranho, ex-membro e titular pelo caminho do EDITOR → COLLECTION_NOT_FOUND; anon sem EXECUTE');
    perform pg_temp.wh_5891_as(u_e);
    v_err := pg_temp.wh_5891_try(format('select * from public.editor_set_pokedex_position_assignment(%L, %L, %L, true)', v_cx, x1, p2));
    perform pg_temp.wh_5891_as(u_b);
    v_err := v_err || ';' || pg_temp.wh_5891_try(format('select * from public.editor_set_pokedex_position_assignment(%L, %L, %L, true)', v_cx, x1, p2));
    execute 'reset role';
    res := res || jsonb_build_object('id','3.3','ok', v_err = 'NOT_POKEDEX_COLLECTION;COLLECTION_NOT_FOUND'
      and not exists (select 1 from public.collection_pokedex_position_assignment a join public.collection_allocation ca on ca.id = a.collection_allocation_id
                      where ca.physical_card_id in (n1, x1, d1))
      and not exists (select 1 from public.collection_pokedex_position_assignment a join public.collection_allocation ca on ca.id = a.collection_allocation_id
                      where ca.physical_card_id = a2),
      'detail','EDITOR de coleção livre → NOT_POKEDEX_COLLECTION; EDITOR de CP em CX → COLLECTION_NOT_FOUND; recusas sem efeito');

    -- 4. Referência de espécie no bolso (5378) ------------------------------------------------------
    res := res || jsonb_build_object('id','4.1','ok',
      public.binder_slot_editor_scope(v_layout, v_cp, v_cp, pg_temp.wh_5891_slot(v_layout, 1, 3)) = 'OWN'
      and public.binder_slot_editor_scope(v_layout, v_cp, v_cx, pg_temp.wh_5891_slot(v_layout, 1, 3)) = 'FOREIGN'
      and public.binder_slot_editor_scope(v_layout, v_cp, v_cp, pg_temp.wh_5891_slot(v_layout, 3, 3)) = 'FREE'
      and public.binder_slot_editor_scope(v_layout, v_cp, v_cx, pg_temp.wh_5891_slot(v_layout, 3, 3)) = 'FREE',
      'detail','bolso só com referência de CP: OWN para CP, FOREIGN para a convidada; bolso vazio: FREE para ambas');
    perform pg_temp.wh_5891_as(u_b);
    select x.operation into v_txt from public.editor_set_binder_lock(v_cp, 1, 1, 3, true) x;
    select x.operation into v_txt2 from public.editor_set_binder_lock(v_cp, 1, 1, 3, false) x;
    v_err := pg_temp.wh_5891_try(format('select * from public.editor_place_card_in_binder(%L, 1, 1, 1, %L)', v_cp, a1));
    res := res || jsonb_build_object('id','4.2','ok', v_txt = 'LOCKED' and v_txt2 = 'UNLOCKED' and v_err = 'OK',
      'detail','EDITOR da Pokédex fixa e solta bolso com referência de CP (C-237) e coloca carta nele');
    perform pg_temp.wh_5891_as(u_e);
    v_err := pg_temp.wh_5891_try(format('select * from public.editor_set_binder_reservation(%L, 1, 1, 2, %L)', v_cx, k3))
          || ';' || pg_temp.wh_5891_try(format('select * from public.editor_set_binder_lock(%L, 1, 1, 2, true)', v_cx))
          || ';' || pg_temp.wh_5891_try(format('select * from public.editor_place_card_in_binder(%L, 1, 1, 2, %L)', v_cx, x1))
          || ';' || pg_temp.wh_5891_try(format('select * from public.editor_place_card_in_binder(%L, 1, 2, 1, %L)', v_cx, x1));
    execute 'reset role';
    res := res || jsonb_build_object('id','4.3','ok', v_err = 'SLOT_NOT_EDITABLE;SLOT_NOT_EDITABLE;SLOT_NOT_EDITABLE;OK'
      and not exists (select 1 from public.collection_layout_slot_expected_content e where e.slot_id = pg_temp.wh_5891_slot(v_layout, 1, 2))
      and not (select s.locked from public.collection_layout_slot s where s.id = pg_temp.wh_5891_slot(v_layout, 1, 2)),
      'detail','EDITOR da convidada não reserva, não fixa e não coloca em bolso com referência de CP; bolso livre funciona');

    -- 5. Coleção por item ------------------------------------------------------------------------------
    v_ev := pg_temp.wh_5891_last_event(v_layout, u_b, 'POCKETS_LOCKED');
    v_ev2 := pg_temp.wh_5891_last_event(v_layout, u_b, 'CARD_PLACED');
    res := res || jsonb_build_object('id','5.1','ok',
      pg_temp.wh_5891_item_colls(v_ev) = 'POCKET:' || v_cp::text
      and pg_temp.wh_5891_item_colls(v_ev2) = 'CARD:' || v_cp::text
      and (select bool_and(e.item_collection_recorded and e.collection_id = v_cp and e.owner_user_id = u_a)
             from public.binder_activity_event e where e.id in (v_ev, v_ev2)),
      'detail','eventos do EDITOR de CP: itens de bolso e de carta atribuídos a CP; titular do evento = A; evento marcado');
    v_ev := pg_temp.wh_5891_last_event(v_layout, u_e, 'CARD_PLACED');
    res := res || jsonb_build_object('id','5.2','ok',
      pg_temp.wh_5891_item_colls(v_ev) = 'CARD:' || v_cx::text
      and (select e.collection_id from public.binder_activity_event e where e.id = v_ev) = v_cx,
      'detail','evento do EDITOR da convidada: coleção CX no evento e no item');
    perform pg_temp.wh_5891_as(u_a);
    perform public.move_slot_assignment(pg_temp.wh_5891_slot(v_layout, 1, 1), pg_temp.wh_5891_slot(v_layout, 2, 1));
    perform public.set_slot_expected_content(pg_temp.wh_5891_slot(v_layout, 3, 1), k2, null, null, null);
    perform public.set_slot_expected_content(pg_temp.wh_5891_slot(v_layout, 3, 2), k3, null, null, v_cx);
    perform public.set_slot_lock(array[pg_temp.wh_5891_slot(v_layout, 3, 3)], true);
    perform public.set_slot_lock(array[pg_temp.wh_5891_slot(v_layout, 1, 2)], true);
    execute 'reset role';
    v_ev := pg_temp.wh_5891_last_event(v_layout, u_a, 'CARDS_SWAPPED');
    res := res || jsonb_build_object('id','5.3','ok',
      (select string_agg(coalesce(i.collection_id::text, '-'), ',' order by i.collection_id::text)
         from public.binder_activity_item i where i.event_id = v_ev)
      = (select string_agg(x, ',' order by x) from unnest(array[v_cp::text, v_cx::text]) x),
      'detail','evento do titular com cartas de duas coleções (troca a1 ↔ x1): cada item com a própria coleção');
    res := res || jsonb_build_object('id','5.4','ok',
      exists (select 1 from public.binder_activity_item i join public.binder_activity_event e on e.id = i.event_id
              where e.layout_key = v_layout and e.actor_user_id = u_a and i.item_kind = 'RESERVATION'
                and i.to_row = 3 and i.to_col = 1 and i.collection_id = v_cp)
      and exists (select 1 from public.binder_activity_item i join public.binder_activity_event e on e.id = i.event_id
                  where e.layout_key = v_layout and e.actor_user_id = u_a and i.item_kind = 'RESERVATION'
                    and i.to_row = 3 and i.to_col = 2 and i.collection_id = v_cx),
      'detail','reserva sem coleção registrada → proprietária CP (C-196); reserva para CX → CX');
    res := res || jsonb_build_object('id','5.5','ok',
      exists (select 1 from public.binder_activity_item i join public.binder_activity_event e on e.id = i.event_id
              where e.layout_key = v_layout and e.actor_user_id = u_a and i.item_kind = 'POCKET' and i.effect = 'LOCKED'
                and i.to_row = 3 and i.to_col = 3 and i.collection_id is null)
      and exists (select 1 from public.binder_activity_item i join public.binder_activity_event e on e.id = i.event_id
                  where e.layout_key = v_layout and e.actor_user_id = u_a and i.item_kind = 'POCKET' and i.effect = 'LOCKED'
                    and i.to_row = 1 and i.to_col = 2 and i.collection_id = v_cp),
      'detail','fixar bolso vazio → item sem coleção (nunca atribuído a um membro); bolso com referência de CP → CP');
    res := res || jsonb_build_object('id','5.6','ok',
      not exists (select 1 from public.binder_activity_event e where e.layout_key = v_layout
                  and e.created_xact = pg_current_xact_id() and not e.item_collection_recorded)
      and not exists (select 1 from public.binder_activity_event e join public.binder_activity_item i on i.event_id = e.id
                      where e.layout_key = v_layout and e.actor_user_id <> e.owner_user_id
                        and (i.collection_id is distinct from e.collection_id or i.item_kind in ('COLLECTION', 'BINDER'))),
      'detail','todo evento novo marcado; nenhum evento de EDITOR com item de outra coleção, sem coleção ou estrutural');

    -- 6. Contexto forjado -----------------------------------------------------------------------------
    perform pg_temp.wh_5891_as(u_b);
    v_err := pg_temp.wh_5891_try(format('select public.binder_activity_add_item(%L, %L)', 'CARD', 'PLACED'))
          || ';' || pg_temp.wh_5891_try(format('select public.binder_activity_begin(%L, %L, %L, %L)', v_layout, 'CARD_PLACED', 'FICHARIO', v_cp));
    res := res || jsonb_build_object('id','6.1','ok', v_err ~ '^permission denied.*;permission denied',
      'detail','gravação e abertura do histórico sem EXECUTE para a API');
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    v_ev := pg_temp.wh_5891_last_event(v_layout, u_a, 'CARDS_SWAPPED');
    select count(*) into n from public.binder_activity_item i where i.event_id = v_ev;
    perform pg_temp.wh_5891_as(u_b);  -- E1E: volta ao mesmo cliente
    perform set_config('mmkyu.binder_activity_ctx', jsonb_build_object('depth', 1, 'layout', v_layout, 'type', 'CARDS_SWAPPED',
      'source', 'FICHARIO', 'collection', v_cp, 'summary', '{}'::jsonb, 'event_id', v_ev, 'n', n, 'cap', 0)::text, true);
    v_err := pg_temp.wh_5891_try(format('select * from public.editor_set_binder_lock(%L, 1, 1, 3, true)', v_cp));
    perform set_config('mmkyu.binder_activity_ctx', '', true);
    perform set_config('mmkyu.binder_activity_ctx', jsonb_build_object('depth', 1, 'layout', v_layout, 'type', 'POCKETS_LOCKED',
      'source', 'FICHARIO', 'collection', v_cx, 'summary', '{}'::jsonb, 'event_id', null, 'n', 0, 'cap', 0)::text, true);
    v_err := v_err || ';' || pg_temp.wh_5891_try(format('select * from public.editor_set_binder_lock(%L, 1, 1, 3, true)', v_cp));
    perform set_config('mmkyu.binder_activity_ctx', '', true);
    execute 'reset role';
    select count(*) into n2 from public.binder_activity_item i where i.event_id = v_ev;
    res := res || jsonb_build_object('id','6.2','ok',
      v_err = 'binder activity: event context does not belong to this operation;binder activity: actor is not the binder owner'
      and n2 = n and not (select s.locked from public.collection_layout_slot s where s.id = pg_temp.wh_5891_slot(v_layout, 1, 3)),
      'detail','contexto forjado com evento do titular → recusa (5379); com coleção de que não é EDITOR → recusa (5372); nada gravado');

    -- 7. Revogação -------------------------------------------------------------------------------------
    select count(*) into n from public.binder_activity_event e where e.layout_key = v_layout and e.actor_user_id = u_b;
    perform pg_temp.wh_5891_as(u_a); perform public.set_collection_member_role(v_cp, m_b, 'VIEWER');
    perform pg_temp.wh_5891_as(u_b);
    v_err := pg_temp.wh_5891_try(format('select * from public.editor_set_pokedex_position_assignment(%L, %L, %L, true)', v_cp, a2, p2))
          || ';' || pg_temp.wh_5891_try(format('select * from public.editor_set_pokedex_position_primary_representative(%L, %L)', v_cp, a1))
          || ';' || pg_temp.wh_5891_try(format('select * from public.editor_set_binder_lock(%L, 1, 1, 3, true)', v_cp));
    perform pg_temp.wh_5891_as(u_a); perform public.set_collection_member_role(v_cp, m_b, 'EDITOR');
    execute 'reset role';
    select count(*) into n2 from public.binder_activity_event e where e.layout_key = v_layout and e.actor_user_id = u_b;
    res := res || jsonb_build_object('id','7.1','ok', v_err = 'COLLECTION_NOT_FOUND;COLLECTION_NOT_FOUND;COLLECTION_NOT_FOUND' and n2 = n,
      'detail','EDITOR rebaixado perde Pokédex e fichário na hora; nenhum evento gravado depois da revogação');

    -- 8. Titular intocado --------------------------------------------------------------------------------
    perform pg_temp.wh_5891_as(u_a);
    perform public.set_pokedex_position_assignment(a2, p2, true);
    perform public.set_pokedex_position_primary_representative(
      (select ca.id from public.collection_allocation ca where ca.physical_card_id = a2));
    perform public.clear_pokedex_position_primary_representative(v_cp, p2);
    perform public.remove_pokedex_position_assignment(a2);
    execute 'reset role';
    res := res || jsonb_build_object('id','8.1','ok',
      not exists (select 1 from public.collection_pokedex_position_assignment a join public.collection_allocation ca on ca.id = a.collection_allocation_id
                  where ca.physical_card_id = a2)
      and not exists (select 1 from public.collection_pokedex_position_primary_representative r where r.collection_id = v_cp and r.pokedex_position_id = p2),
      'detail','titular continua posicionando, escolhendo e limpando representante e retirando posição (6122/6124/6126/6125)');
    res := res || jsonb_build_object('id','8.2','ok',
      exists (select 1 from public.binder_activity_event e where e.layout_key = v_layout and e.actor_user_id = u_a
              and e.event_type = 'CARDS_SWAPPED' and e.item_collection_recorded),
      'detail','titular continua gravando histórico pelas funções instrumentadas, agora com coleção por item');

    -- 9. Patrimônio ----------------------------------------------------------------------------------------
    res := res || jsonb_build_object('id','9.1','ok',
      (select string_agg(ca.physical_card_id::text || ':' || ca.collection_id::text, ',' order by ca.physical_card_id)
         from public.collection_allocation ca where ca.physical_card_id in (a1, a2, a3, x1, n1, d1)) = alloc0
      and (select string_agg(md5((to_jsonb(pc) - 'updated_at')::text), ',' order by pc.id)
             from public.physical_card pc where pc.id in (a1, a2, a3, x1, n1, d1)) = pc0,
      'detail','nenhuma alocação, local, condição ou outro campo de exemplar mudou (Pokédex e fichário não são patrimônio)');

    -- 10. Coleção arquivada --------------------------------------------------------------------------------
    perform pg_temp.wh_5891_as(u_a); perform public.archive_collection(v_cp);
    perform pg_temp.wh_5891_as(u_b);
    v_err := pg_temp.wh_5891_try(format('select * from public.editor_set_pokedex_position_assignment(%L, %L, %L, true)', v_cp, a2, p2))
          || ';' || pg_temp.wh_5891_try(format('select * from public.editor_clear_pokedex_position_primary_representative(%L, %L)', v_cp, p1))
          || ';' || pg_temp.wh_5891_try(format('select * from public.editor_remove_pokedex_position_assignment(%L, %L)', v_cp, a1));
    execute 'reset role';
    res := res || jsonb_build_object('id','10.1','ok', v_err = 'COLLECTION_ARCHIVED;COLLECTION_ARCHIVED;COLLECTION_ARCHIVED',
      'detail','Pokédex arquivada: EDITOR recusado só depois de autorizado');

    execute 'reset role';
    raise exception 'MS891' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MS891' then
      res := res || jsonb_build_object('id','X.1','ok', false, 'detail','erro inesperado: '||sqlstate||' '||sqlerrm);
    end if;
  end;

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('mmkyu.binder_activity_ctx', '', true);
  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.collection_membership), (select count(*) from public.binder_activity_event),
               (select count(*) from public.binder_activity_item), (select count(*) from public.collection_pokedex_position_assignment),
               (select count(*) from public.collection_pokedex_position_primary_representative),
               (select count(*) from public.collection_layout_slot_species_reference), (select count(*) from public.card_primary_species)]
    into e_counts;
  res := res || jsonb_build_object('id','99.1','ok', b_counts = e_counts and current_user = session_user,
    'detail','resíduo zero (11 contagens, inclusive histórico, posições, representantes e referências) e papel restaurado');

  v_expected := 33;
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
