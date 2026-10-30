/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5862 - Harness V1-12 VIEWER EXPERIENCE PARITY (5320, 5321, 5322)
Versão......: 2.0 (2026-10-30) — v1.0 só lia dados reais (sem VIEWER,
              pendente nem revogação); v2.0 segue o protocolo da 5861:
              fixture sintética efêmera + sentinela MS862 + resíduo zero.
              v2.1 (BINDER IDENTITY PRIVACY CORRECTION-01): identidade do
              fichário convidado (nome e logomarca) no VIEWER (5321 v1.2) e na
              vitrine pública (5322); mascaramento de cartas de outra coleção
              nos dois contextos; placement explícito de K2 no fichário de CO.
Status......: PROPOSTA — NÃO EXECUTADA. Executar só depois de 5320, 5321
              v1.2 e 5322 aplicadas e com autorização de Fabrício. NÃO substitui a
              5861 (51/51 PASS permanece a evidência dos contratos 5300–5319).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-30

Protocolo: um único statement, como dono do banco.

  select * from pg_temp.wh_5862_validate();

  Tudo que a fixture cria é desfeito pela sentinela MS862 (exceção
  capturada no bloco interno); 99.1 compara 7 contagens antes/depois.

Fixture (catálogo SINTÉTICO, usuários efêmeros, RPCs canônicas do titular):
  Set SHV com K1 (2 variantes: STD e outra do jogo, se existir), K2, K3.
  A (titular): local BIN (BINDER).
    CO  coleção de Set (STANDARD_SET) do SHV, no BIN: a1 = K1 na variante
        NÃO padrão, a2 = K2 → satisfeitas K1 (por variante) e K2.
    a3  = K3 no acervo de A, SEM coleção (prova de não vazamento: K3
        continua "Falta" para o VIEWER e nada indica que A a possui).
    CX  coleção livre no BIN com x1 (K1), convidada do fichário de CO.
    Fichário 3×3 de CO, nome próprio "WH 5862 Fichário", sem logomarca.
  B VIEWER ativo de CO e de CX. C convite PENDENTE. D convite RECUSADO.
  F aceitou e foi REMOVIDO. E estranho. anon.

Seções:
  S  estrutura (definer, search_path, grants, sem colunas de acervo)
  F  fixture íntegra
  P  5320: titular ≡ 5169 (sem acervo); VIEWER ≡ titular; Tenho/Faltam
     corretos com variante; K3 em Faltam; CX (livre) → zero; filtro inválido
  N  negação: C, D, E, F → zero linhas; anon → 42501
  B  5321: dona → nome próprio + preferência real (false); convidada →
     nome NULL e logomarca padrão true (real do dono = false); chaves
     antigas preservadas; sem chaves privadas; negados → NULL
  M  mascaramento: K2 (só de CO, num bolso) nunca aparece nas páginas de
     CX — VIEWER (5316) e vitrine (5318)
  PB vitrine (5322): CO pública → nome + false; CX pública → nome NULL +
     true; CX privatizada → NULL
  R  revogação ao vivo: A remove B → 5320 zero e 5321 NULL na hora
  99 resíduo zero

Gate: GATE PASS com N/N (N = v_expected). Qualquer FAIL → STOP; não
corrigir no LIVE; reportar.
================================================================
*/

create or replace function pg_temp.wh_5862_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
as $fn$
declare
  f_pos oid := to_regprocedure('public.get_shared_collection_positions(uuid,text,integer,integer)');
  f_bin oid := to_regprocedure('public.get_shared_collection_binder(uuid)');
  f_pub oid := to_regprocedure('public.get_public_collection_binder(uuid)');
  v_slot uuid; v_real_brand boolean; n3 integer;
  u_a uuid := gen_random_uuid(); u_b uuid := gen_random_uuid(); u_c uuid := gen_random_uuid();
  u_d uuid := gen_random_uuid(); u_e uuid := gen_random_uuid(); u_f uuid := gen_random_uuid();
  v_sfx text := lower(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  v_game uuid; v_pt uuid; v_rar uuid; v_cat uuid; v_std uuid; v_alt uuid;
  v_exp uuid; v_set uuid; k1 uuid; k2 uuid; k3 uuid; k1s uuid; k1a uuid; k2s uuid; k3s uuid;
  v_inv_a uuid; a1 uuid; a2 uuid; a3 uuid; x1 uuid;
  v_bin uuid; v_co uuid; v_cx uuid; v_layout uuid; p record;
  m_b uuid; m_c uuid; m_d uuid; m_f uuid; m_bx uuid;
  j jsonb; v_err text; n integer; n2 integer;
  b_counts bigint[]; e_counts bigint[];
  res jsonb := '[]'::jsonb; r jsonb; cnt integer := 0; passes integer := 0;
  v_expected integer := 33;
begin
  -- S. Estrutura ------------------------------------------------------------------------
  res := res || jsonb_build_object('id','S.1','ok', f_pos is not null and f_bin is not null, 'detail','5320 e 5321 presentes');
  res := res || jsonb_build_object('id','S.2','ok',
    (select bool_and(q.prosecdef and q.proconfig @> array['search_path=""']) from pg_proc q where q.oid in (f_pos, f_bin)),
    'detail','security definer + search_path vazio');
  res := res || jsonb_build_object('id','S.3','ok',
    (select bool_and(has_function_privilege('authenticated', q.oid, 'EXECUTE') and not has_function_privilege('anon', q.oid, 'EXECUTE'))
       from pg_proc q where q.oid in (f_pos, f_bin))
    and not exists (select 1 from pg_proc q, aclexplode(coalesce(q.proacl, '{}')) a where q.oid in (f_pos, f_bin) and a.grantee = 0),
    'detail','EXECUTE só authenticated; nada para anon/PUBLIC');
  res := res || jsonb_build_object('id','S.4','ok',
    not exists (select 1 from pg_proc q, unnest(q.proargnames, q.proargmodes) a(name, mode)
                where q.oid = f_pos and a.mode in ('o','t')
                  and a.name ~* '(available|elsewhere|acervo|inventory|storage|location|price|value|acquired|condition|physical)'),
    'detail','5320 sem colunas de acervo/patrimônio');
  res := res || jsonb_build_object('id','S.5','ok',
    f_pub is not null
    and (select q.prosecdef and q.proconfig @> array['search_path=""'] from pg_proc q where q.oid = f_pub)
    and has_function_privilege('anon', f_pub, 'EXECUTE') and has_function_privilege('authenticated', f_pub, 'EXECUTE')
    and position('true AS show_brand_mark' in pg_get_functiondef(f_pub)) > 0,
    'detail','5322 aplicada: vitrine definer, anon+authenticated, convidada com logomarca padrão');

  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.collection_membership), (select count(*) from public.card),
               (select count(*) from public.collection_layout)]
    into b_counts;

  begin
    -- F. Fixture --------------------------------------------------------------------------
    select g.id into v_game from public.game g where g.code = 'POKEMON';
    select l.id into v_pt from public.language l where l.code = 'pt-BR';
    select t.id into v_std from public.card_variant_type t where t.game_id = v_game and t.code = 'STANDARD';
    select t.id into v_alt from public.card_variant_type t where t.game_id = v_game and t.id <> v_std order by t.code limit 1;
    select c0.rarity_id, c0.category_id into v_rar, v_cat
    from public.card c0 join public.card_set cs0 on cs0.id = c0.card_set_id
    join public.expansion e0 on e0.id = cs0.expansion_id where e0.game_id = v_game limit 1;
    if v_game is null or v_pt is null or v_std is null or v_alt is null or v_rar is null then
      res := res || jsonb_build_object('id','F.0','ok', false, 'detail','pré-requisitos de catálogo ausentes (inclui 2º tipo de variante)');
      raise exception 'MS862' using errcode = 'P0001';
    end if;
    insert into public.expansion (game_id, code, name, release_order)
    values (v_game, 'SHV_' || upper(v_sfx), 'SHV Harness ' || v_sfx,
            (select coalesce(max(x.release_order), 0) + 1000 from public.expansion x where x.game_id = v_game))
    returning id into v_exp;
    insert into public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_exp, 'SHV' || upper(v_sfx), 'SHV Set ' || v_sfx, 'REGULAR', 1, 3, 3) returning id into v_set;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '1', 1, 'SHV K1', true) returning id into k1;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '2', 2, 'SHV K2', true) returning id into k2;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '3', 3, 'SHV K3', true) returning id into k3;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k1, v_std, 1, true) returning id into k1s;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k1, v_alt, 2, false) returning id into k1a;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k2, v_std, 1, true) returning id into k2s;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k3, v_std, 1, true) returning id into k3s;

    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    select x.id, 'authenticated', 'authenticated', x.u || '@example.invalid', jsonb_build_object('username', x.u, 'display_name', 'WH 5862 ' || x.t), now(), now()
    from (values (u_a, 'wh862a_' || v_sfx, 'A'), (u_b, 'wh862b_' || v_sfx, 'B'), (u_c, 'wh862c_' || v_sfx, 'C'),
                 (u_d, 'wh862d_' || v_sfx, 'D'), (u_e, 'wh862e_' || v_sfx, 'E'), (u_f, 'wh862f_' || v_sfx, 'F')) x(id, u, t);
    select i.id into v_inv_a from public.inventory i where i.owner_user_id = u_a;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (k1a, v_pt, v_inv_a) returning id into a1;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (k2s, v_pt, v_inv_a) returning id into a2;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (k3s, v_pt, v_inv_a) returning id into a3;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (k1s, v_pt, v_inv_a) returning id into x1;

    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select x.storage_container_id into v_bin from public.create_my_storage_container(gen_random_uuid(), 'BIN 5862', 'BINDER') x;
    select x.collection_id into v_co from public.create_my_card_set_collection(gen_random_uuid(), v_set, 'CO 5862', v_bin) x;
    select x.collection_id into v_cx from public.create_my_free_collection(gen_random_uuid(), 'CX 5862', v_bin) x;
    perform public.allocate_physical_cards_to_collection(v_co, array[a1, a2]);
    perform public.allocate_physical_cards_to_collection(v_cx, array[x1]);
    select * into p from public.preview_my_collection_binder(v_co, 3, 3, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_co, 3, 3, 'PRINCIPAL_ONLY', p.plan_token);
    perform public.set_my_binder_identity(v_co, 'WH 5862 Fichário', false);
    execute 'reset role';
    select l.id into v_layout from public.collection_layout l where l.collection_id = v_co;
    execute 'set local role authenticated';
    perform public.attach_my_collection_to_binder(v_cx, v_layout);
    -- K2 (a2, só de CO) num bolso: base das provas de mascaramento M.1/M.2.
    execute 'reset role';
    update public.physical_card pc
       set storage_container_id = (select l.storage_container_id from public.collection_layout l where l.id = v_layout)
     where pc.id in (a1, a2, x1);
    select l.show_brand_mark into v_real_brand from public.collection_layout l where l.id = v_layout;
    execute 'set local role authenticated';
    if not exists (select 1 from public.collection_layout_slot_assignment a where a.physical_card_id = a2) then
      select s.id into v_slot
      from public.collection_layout_slot s join public.collection_layout_page pg on pg.id = s.page_id
      where pg.layout_id = v_layout
        and not exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = s.id)
        and not exists (select 1 from public.collection_layout_slot_expected_content e where e.slot_id = s.id)
      order by pg.page_number, s.row_index, s.column_index limit 1;
      perform public.place_my_physical_card_in_slot(v_co, v_slot, a2);
    end if;
    m_b  := (public.invite_collection_member(v_co, 'wh862b_' || v_sfx) ->> 'membership_id')::uuid;
    m_c  := (public.invite_collection_member(v_co, 'wh862c_' || v_sfx) ->> 'membership_id')::uuid;
    m_d  := (public.invite_collection_member(v_co, 'wh862d_' || v_sfx) ->> 'membership_id')::uuid;
    m_f  := (public.invite_collection_member(v_co, 'wh862f_' || v_sfx) ->> 'membership_id')::uuid;
    m_bx := (public.invite_collection_member(v_cx, 'wh862b_' || v_sfx) ->> 'membership_id')::uuid;
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.respond_collection_invite(m_b, true);
    perform public.respond_collection_invite(m_bx, true);
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', u_d::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_d, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.respond_collection_invite(m_d, false);
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', u_f::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_f, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.respond_collection_invite(m_f, true);
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.remove_collection_member(v_co, m_f);
    execute 'reset role';

    res := res || jsonb_build_object('id','F.1','ok',
      v_co is not null and v_cx is not null and v_layout is not null
      and (select count(*) from public.collection_allocation ca where ca.collection_id = v_co) = 2
      and exists (select 1 from public.collection_layout_guest g where g.layout_id = v_layout and g.collection_id = v_cx)
      and (select m.status from public.collection_membership m where m.id = m_b) = 'ACTIVE'
      and (select m.status from public.collection_membership m where m.id = m_c) = 'PENDING'
      and (select m.status from public.collection_membership m where m.id = m_d) = 'DECLINED'
      and not exists (select 1 from public.collection_membership m where m.id = m_f)
      and not exists (select 1 from public.collection_allocation ca where ca.physical_card_id = a3),
      'detail','CO (STANDARD_SET, 2 alocadas, K1 por variante não padrão), CX convidada, B ativo, C pendente, D recusado, F removido, a3 só no acervo');
    res := res || jsonb_build_object('id','F.2','ok',
      exists (select 1 from public.collection_layout_slot_assignment a
              join public.collection_layout_slot s on s.id = a.slot_id
              join public.collection_layout_page pg on pg.id = s.page_id
              where a.physical_card_id = a2 and pg.layout_id = v_layout)
      and v_real_brand = false,
      'detail','K2 (a2, de CO) num bolso do fichário; preferência real de logomarca do fichário dono = ' || coalesce(v_real_brand::text, 'null'));

    -- P. Posições (5320) -------------------------------------------------------------------
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select count(*) into n from (
      (select card_id, collector_number, is_satisfied, copies_in_collection, image_path, total_count, o
         from public.get_my_collection_positions(v_co, 'ALL', 500, 0) with ordinality t(card_id, collector_number, collector_total, card_name, image_path, is_satisfied, copies_in_collection, copies_available, total_count, o)
       except
       select card_id, collector_number, is_satisfied, copies_in_collection, image_path, total_count, o
         from public.get_shared_collection_positions(v_co, 'ALL', 500, 0) with ordinality s(card_id, collector_number, collector_total, card_name, image_path, is_satisfied, copies_in_collection, total_count, o))
      union all
      (select card_id, collector_number, is_satisfied, copies_in_collection, image_path, total_count, o
         from public.get_shared_collection_positions(v_co, 'ALL', 500, 0) with ordinality s(card_id, collector_number, collector_total, card_name, image_path, is_satisfied, copies_in_collection, total_count, o)
       except
       select card_id, collector_number, is_satisfied, copies_in_collection, image_path, total_count, o
         from public.get_my_collection_positions(v_co, 'ALL', 500, 0) with ordinality t(card_id, collector_number, collector_total, card_name, image_path, is_satisfied, copies_in_collection, copies_available, total_count, o))
    ) d;
    select count(*) into n2 from public.get_my_collection_positions(v_co, 'ALL', 500, 0) x where x.card_id = k3 and x.copies_available = 1;
    execute 'reset role';
    res := res || jsonb_build_object('id','P.1','ok', n = 0 and n2 = 1,
      'detail','titular: 5320 ≡ 5169 em carta, ordem, satisfação, cópias, arte e total (' || n || ' divergências); 5169 do titular vê a3 disponível');

    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select string_agg(x.collector_number || ':' || x.is_satisfied || ':' || x.copies_in_collection || ':' || x.total_count, ',' order by o)
      into v_err from public.get_shared_collection_positions(v_co, 'ALL', 500, 0) with ordinality x(card_id, collector_number, collector_total, card_name, image_path, is_satisfied, copies_in_collection, total_count, o);
    res := res || jsonb_build_object('id','P.2','ok', v_err = '1:true:1:3,2:true:1:3,3:false:0:3',
      'detail','VIEWER, Todas, ordem do Set: ' || coalesce(v_err, '(vazio)') || ' — K1 satisfeita por variante não padrão');
    select string_agg(x.collector_number, ',' order by o) into v_err
      from public.get_shared_collection_positions(v_co, 'OWNED', 500, 0) with ordinality x(card_id, collector_number, collector_total, card_name, image_path, is_satisfied, copies_in_collection, total_count, o);
    res := res || jsonb_build_object('id','P.3','ok', v_err = '1,2', 'detail','VIEWER, Tenho: ' || coalesce(v_err, '(vazio)'));
    select string_agg(x.collector_number || ':' || x.copies_in_collection || ':' || x.total_count, ',' order by o) into v_err
      from public.get_shared_collection_positions(v_co, 'MISSING', 500, 0) with ordinality x(card_id, collector_number, collector_total, card_name, image_path, is_satisfied, copies_in_collection, total_count, o);
    res := res || jsonb_build_object('id','P.4','ok', v_err = '3:0:1',
      'detail','VIEWER, Faltam: ' || coalesce(v_err, '(vazio)') || ' — K3 falta embora o titular a tenha no acervo (nada vaza)');
    select count(*) into n from public.get_shared_collection_positions(v_co, 'ALL', 1, 1);
    select count(*) into n2 from public.get_shared_collection_positions(v_cx, 'ALL', 500, 0);
    res := res || jsonb_build_object('id','P.5','ok', n = 1 and n2 = 0, 'detail','paginação (1 linha no offset 1) e coleção livre → zero linhas');
    v_err := null; begin perform count(*) from public.get_shared_collection_positions(v_co, 'XYZ', 10, 0); exception when others then v_err := sqlstate || ' ' || sqlerrm; end;
    res := res || jsonb_build_object('id','P.6','ok', v_err like '22023%INVALID_FILTER%', 'detail', coalesce(v_err, 'aceitou filtro inválido'));
    v_err := null; begin perform count(*) from public.get_shared_collection_positions(v_co, 'ALL', 501, 0); exception when others then v_err := sqlstate || ' ' || sqlerrm; end;
    res := res || jsonb_build_object('id','P.7','ok', v_err like '22023%INVALID_PAGE%', 'detail', coalesce(v_err, 'aceitou p_limit 501'));

    -- B (VIEWER) --------------------------------------------------------------------------
    j := public.get_shared_collection_binder(v_co);
    res := res || jsonb_build_object('id','B.1','ok',
      j ?& array['has_binder','grid_columns','grid_rows','page_count','own_filled_count']
      and (j ->> 'has_binder')::boolean and (j ->> 'grid_columns')::int = 3,
      'detail','chaves da 5314 preservadas');
    res := res || jsonb_build_object('id','B.2','ok',
      j ->> 'binder_name' = 'WH 5862 Fichário' and jsonb_typeof(j -> 'show_brand_mark') = 'boolean' and (j ->> 'show_brand_mark')::boolean = false,
      'detail','coleção dona: nome próprio e logomarca do titular (' || coalesce(j ->> 'binder_name', 'null') || ')');
    res := res || jsonb_build_object('id','B.3','ok',
      not (j ?| array['layout_id','owner_collection_id','owner_collection_name','storage_container_id','storage_name','display_name']),
      'detail','sem chaves privadas');
    j := public.get_shared_collection_binder(v_cx);
    res := res || jsonb_build_object('id','B.4','ok',
      j is not null and (j ->> 'has_binder')::boolean and (j -> 'binder_name') = 'null'::jsonb,
      'detail','coleção convidada: fichário visível, nome do fichário de OUTRA coleção NÃO exposto');
    res := res || jsonb_build_object('id','B.5','ok',
      jsonb_typeof(j -> 'show_brand_mark') = 'boolean' and (j ->> 'show_brand_mark')::boolean = true and v_real_brand = false,
      'detail','coleção convidada: logomarca padrão true; a preferência real do fichário dono (false) não é inferível');
    select count(*) into n from public.get_shared_collection_binder_pages(v_cx, 1, 4) x where x.card_name = 'SHV K2';
    select count(*) into n2 from public.get_shared_collection_binder_pages(v_co, 1, 4) x where x.card_name = 'SHV K2' and x.pocket_state = 'CARD';
    res := res || jsonb_build_object('id','M.1','ok', n = 0 and n2 >= 1,
      'detail','VIEWER: K2 visível nas páginas de CO (' || n2 || ') e ausente nas de CX (' || n || ') — carta de outra coleção mascarada');
    execute 'reset role';

    -- PB. Vitrine pública (5322) -----------------------------------------------------------
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.set_collection_visibility(v_co, 'PUBLIC');
    perform public.set_collection_visibility(v_cx, 'PUBLIC');
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    j := public.get_public_collection_binder(v_co);
    res := res || jsonb_build_object('id','PB.1','ok',
      j is not null and j ->> 'binder_name' = 'WH 5862 Fichário' and (j ->> 'show_brand_mark')::boolean = false,
      'detail','vitrine da coleção dona: nome próprio e preferência real (' || coalesce(j ->> 'binder_name', 'null') || ', ' || coalesce(j ->> 'show_brand_mark', 'null') || ')');
    j := public.get_public_collection_binder(v_cx);
    res := res || jsonb_build_object('id','PB.2','ok',
      j is not null and (j ->> 'has_binder')::boolean and (j -> 'binder_name') = 'null'::jsonb
      and jsonb_typeof(j -> 'show_brand_mark') = 'boolean' and (j ->> 'show_brand_mark')::boolean = true,
      'detail','vitrine da coleção convidada: nome NULL e logomarca padrão true (real do dono = false)');
    select count(*) into n3 from public.get_public_collection_binder_pages(v_cx, 1, 4) x where x.card_name = 'SHV K2';
    res := res || jsonb_build_object('id','M.2','ok', n3 = 0,
      'detail','visitante: K2 (de CO) ausente nas páginas públicas de CX (' || n3 || ')');
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.set_collection_visibility(v_cx, 'PRIVATE');
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    j := public.get_public_collection_binder(v_cx);
    execute 'reset role';
    res := res || jsonb_build_object('id','PB.3','ok', j is null, 'detail','CX privatizada: vitrine NULL na hora');

    -- N. Negação ---------------------------------------------------------------------------
    for p in select * from (values ('C pendente', u_c), ('D recusado', u_d), ('E estranho', u_e), ('F removido', u_f)) v(label, uid) loop
      perform set_config('request.jwt.claim.sub', p.uid::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', p.uid, 'role', 'authenticated')::text, true);
      execute 'set local role authenticated';
      select count(*) into n from public.get_shared_collection_positions(v_co, 'ALL', 500, 0);
      j := public.get_shared_collection_binder(v_co);
      execute 'reset role';
      res := res || jsonb_build_object('id','N.' || p.label,'ok', n = 0 and j is null, 'detail', p.label || ': 5320 = ' || n || ' linhas, 5321 = ' || coalesce(j::text, 'NULL'));
    end loop;
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    v_err := null; begin perform count(*) from public.get_shared_collection_positions(v_co, 'ALL', 10, 0); exception when others then v_err := sqlstate; end;
    res := res || jsonb_build_object('id','N.anon 5320','ok', v_err = '42501', 'detail', coalesce(v_err, 'executou'));
    v_err := null; begin perform public.get_shared_collection_binder(v_co); exception when others then v_err := sqlstate; end;
    res := res || jsonb_build_object('id','N.anon 5321','ok', v_err = '42501', 'detail', coalesce(v_err, 'executou'));
    execute 'reset role';

    -- R. Revogação ao vivo ---------------------------------------------------------------------
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.remove_collection_member(v_co, m_b);
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select count(*) into n from public.get_shared_collection_positions(v_co, 'ALL', 500, 0);
    j := public.get_shared_collection_binder(v_co);
    select count(*) into n2 from public.get_shared_collection_positions(v_cx, 'ALL', 500, 0);
    execute 'reset role';
    res := res || jsonb_build_object('id','R.1','ok', n = 0 and j is null,
      'detail','B removido de CO: 5320 = ' || n || ' linhas, 5321 = ' || coalesce(j::text, 'NULL') || ' (na mesma transação, sem cache)');
    res := res || jsonb_build_object('id','R.2','ok', n2 = 0,
      'detail','participação em CX não abre CO (e CX, livre, não tem grade de Set)');

    raise exception 'MS862' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MS862' then
      res := res || jsonb_build_object('id','X.1','ok', false, 'detail','erro inesperado: ' || sqlstate || ' ' || sqlerrm);
    end if;
  end;

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.collection_membership), (select count(*) from public.card),
               (select count(*) from public.collection_layout)]
    into e_counts;
  res := res || jsonb_build_object('id','99.1','ok', b_counts = e_counts and current_user = session_user,
    'detail','resíduo zero (7 contagens) e papel restaurado');

  for r in select * from jsonb_array_elements(res) loop
    cnt := cnt + 1;
    if (r ->> 'ok')::boolean then passes := passes + 1; end if;
    seq := cnt; check_id := r ->> 'id';
    status := case when (r ->> 'ok')::boolean then 'PASS' else 'FAIL' end;
    detail := r ->> 'detail';
    return next;
  end loop;
  seq := cnt + 1; check_id := 'GATE';
  status := case when passes = cnt and cnt = v_expected then 'PASS' else 'FAIL' end;
  detail := passes || '/' || cnt || ' PASS (esperado ' || v_expected || ')';
  return next;
end;
$fn$;

-- Executar (uma única vez, depois de 5320/5321, com autorização):
-- select * from pg_temp.wh_5862_validate();
