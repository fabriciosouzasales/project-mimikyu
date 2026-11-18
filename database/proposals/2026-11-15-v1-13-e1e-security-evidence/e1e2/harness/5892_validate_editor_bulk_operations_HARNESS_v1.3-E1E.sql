/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5892 - Harness V1-13 · E1-C (5381–5383): páginas e referências de
              espécie pelo EDITOR só no fichário exclusivo da coleção; recusa em
              fichário de várias coleções; tipos de evento do EDITOR; revogação;
              titular intocado; sem efeito patrimonial; resíduo zero
Versão......: 1.3-E1E (2026-11-16, `G2_B v2 LIVE FAIL — CONSOLIDATED HARNESS CORRECTION-01`, só o harness):
              C1: caminho da imagem de bolso da fixture passa a <dono>/<fichário>/<uuid>.webp
              (gen_random_uuid), como exigem chk_collection_layout_slot_image_path_format e
              _path_owner (5232); o nome literal "wh589N.webp" violava o CHECK (23514 no
              G2_B v2 LIVE, TXID 815477). Linhas "-- E1E". Nenhum critério alterado.
              1.2-E1E (2026-11-16, `G2_B/G2_C — MGMTAPI READINESS CORRECTION-01`, só o harness):
              conferências internas de estado (classe B) que liam tabelas de fichário,
              histórico, alocação ou referências sob o papel do CLIENTE (EDITOR/estranho)
              passam a ler no contexto do dono (reset role → instrução → wh_5892_as do mesmo
              usuário). Sob o cliente, a RLS "select_own" devolvia vazio (resultado falso) e
              as tabelas revogadas (histórico, referências) dariam 42501. Linhas "-- E1E".
              Chamadas às RPCs (classe A) e negativas (classe C) intactas; nenhuma
              verificação removida, nenhum critério alterado. Original preservado.
              1.1 (2026-11-15, `BULK OPERATIONS SAFETY REVIEW-02`: 1.4 com trava do titular e
              recusa reservada; 7.2/7.3 fichário exclusivo com conteúdo da antiga proprietária). 1.0
Status......: PROPOSTA — NÃO EXECUTADA. Prova DINÂMICA da E1-C. Sem ambiente
              isolado (C-244): executar SOMENTE sob protocolo controlado
              equivalente ao P1 da E1-A (transação explícita READ WRITE terminada
              em erro/ROLLBACK, conexão direta única, psql), depois da E1-A, E1-B1,
              E1-B2, E1-B3 e E1-C, com autorização expressa e específica. Sem
              BEGIN/COMMIT próprios; não é comando pronto para produção.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-15

Pressupõe aplicadas: 5366–5383.

Usuários efêmeros: A titular · B EDITOR de CP, CS e CF · V VIEWER de CP · R EDITOR
de CP removido · E EDITOR de CG · C estranho.
Coleções de A:
  CP  Pokédex, fichário próprio e EXCLUSIVO (2×2), com imagem do titular em p1 r2c2;
  CS  livre, fichário próprio e EXCLUSIVO (2×2);
  CF  livre, fichário próprio com a convidada CG (fichário de VÁRIAS coleções).
Exemplares de A: a1 (CP), s1 (CS), f1 (CF), todos no local do respectivo fichário.

  select * from pg_temp.wh_5892_validate();
  -- GATE esperado: 27/27 PASS (26 verificações + F.2)

Limitações declaradas:
  L1 SET LOCAL ROLE prova o banco, não o JWT do PostgREST.
  L2 Concorrência (S8 concorrente, S10): PENDENTE — sessão única. Inclui página e
     referências do EDITOR × associação/escrita do titular.
  L3 O número de páginas criadas pelo plano do fichário é lido da fixture (não
     fixado); as verificações usam esse valor.
================================================================
*/

create or replace function pg_temp.wh_5892_as(p_user uuid)
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

create or replace function pg_temp.wh_5892_try(p_sql text)
returns text language plpgsql volatile as $try$
begin
  execute p_sql;
  return 'OK';
exception when others then
  return sqlerrm;
end;
$try$;

create or replace function pg_temp.wh_5892_slot(p_layout uuid, p_page integer, p_row integer, p_col integer)
returns uuid language sql stable as $sl$
  select s.id from public.collection_layout_slot s
  join public.collection_layout_page p on p.id = s.page_id
  where p.layout_id = p_layout and p.page_number = p_page and s.row_index = p_row and s.column_index = p_col;
$sl$;

create or replace function pg_temp.wh_5892_pages(p_layout uuid)
returns integer language sql stable as $pg$
  select count(*)::integer from public.collection_layout_page p where p.layout_id = p_layout;
$pg$;

create or replace function pg_temp.wh_5892_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
as $fn$
#variable_conflict use_column
declare
  v_e1e_np integer;  -- E1E: contagem de páginas lida no contexto do dono
  u_a uuid := gen_random_uuid(); u_b uuid := gen_random_uuid(); u_v uuid := gen_random_uuid();
  u_r uuid := gen_random_uuid(); u_e uuid := gen_random_uuid(); u_c uuid := gen_random_uuid();
  v_sfx text := lower(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  v_game uuid; v_pt uuid; v_rar uuid; v_cat uuid; v_std uuid; v_exp uuid; v_set uuid; v_gen text;
  k1 uuid; k1s uuid;
  v_inv_a uuid; v_ids uuid[]; a1 uuid; s1 uuid; f1 uuid;
  v_bp uuid; v_bs uuid; v_bf uuid;
  v_cp uuid; v_cs uuid; v_cf uuid; v_cg uuid; v_cq uuid; m_bq uuid;
  l_p uuid; l_s uuid; l_f uuid; c_p uuid; c_s uuid; c_f uuid;
  m_b uuid; m_bs uuid; m_bf uuid; m_v uuid; m_r uuid; m_e uuid;
  p record; v_err text; v_txt text; v_tok text; v_u uuid; n integer; n2 integer; np integer; v_page_img uuid;
  v_new integer; v_ord integer[];
  alloc0 text; pc0 text;
  b_counts bigint[]; e_counts bigint[];
  res jsonb := '[]'::jsonb; r jsonb; cnt integer := 0; passes integer := 0;
  v_expected integer := 0;
begin
  -- 0. Estrutura ---------------------------------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    (select count(*) from pg_proc q
      where q.oid in (to_regprocedure('public.editor_add_binder_page(uuid)'),
                      to_regprocedure('public.editor_remove_binder_page(uuid, integer, integer)'),
                      to_regprocedure('public.editor_reorder_binder_pages(uuid, integer[])'),
                      to_regprocedure('public.editor_preview_binder_species_references(uuid)'),
                      to_regprocedure('public.editor_apply_binder_species_references(uuid, text)'),
                      to_regprocedure('public.editor_clear_binder_species_references(uuid, integer)'),
                      to_regprocedure('public.editor_set_binder_species_reference_visibility(uuid, boolean)'))
        and q.prosecdef and q.proconfig @> array['search_path=""']
        and has_function_privilege('authenticated', q.oid, 'EXECUTE')
        and not has_function_privilege('anon', q.oid, 'EXECUTE')) = 7
    and not has_function_privilege('authenticated', to_regprocedure('public.assert_collection_binder_editor_exclusive(uuid)'), 'EXECUTE')
    and not has_function_privilege('authenticated', to_regprocedure('public.editor_species_reference_target_locked(uuid)'), 'EXECUTE')
    and not has_function_privilege('authenticated', to_regprocedure('public.editor_species_reference_summary(uuid, uuid, uuid, text, uuid)'), 'EXECUTE'),
    'detail','7 RPCs do EDITOR: definer, search_path vazio, só authenticated; 3 ajudantes internos');
  res := res || jsonb_build_object('id','0.2','ok',
    exists (select 1 from pg_trigger t where t.tgrelid = 'public.binder_activity_event'::regclass
            and t.tgname = 'trg_bae_editor_event_type' and t.tgenabled = 'O')
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)')) = 'f8cfba40e442e85056e7c8ce7954d4f4'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.binder_slot_editor_scope(uuid, uuid, uuid, uuid)')) = '21f1b51a3a0f6c80337c2c593cc6054f'
    and not exists (select 1 from unnest((select q.proargnames from pg_proc q
                     where q.oid = to_regprocedure('public.editor_preview_binder_species_references(uuid)'))) a(nm)
                    where a.nm = 'slots_with_content'),
    'detail','gatilho de tipos ativo; gravação (5379) e classificação (5378) inalteradas; prévia sem contagem de bolsos ocupados');

  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.collection_membership), (select count(*) from public.collection_layout_page),
               (select count(*) from public.collection_layout_slot), (select count(*) from public.collection_layout_slot_species_reference),
               (select count(*) from public.collection_layout_species_reference_setting),
               (select count(*) from public.binder_activity_event), (select count(*) from public.binder_activity_item)]
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
    select g.code into v_gen
    from public.pokedex dx
    join public.pokedex_position pp on pp.pokedex_id = dx.id
    join public.pokemon_species sp on sp.id = pp.species_id
    join public.pokemon_generation g on g.id = sp.generation_id
    where dx.code = 'NATIONAL' order by pp.position_number limit 1;
    if v_game is null or v_pt is null or v_std is null or v_cat is null or v_rar is null or v_gen is null then
      res := res || jsonb_build_object('id','F.1','ok', false, 'detail','pré-requisitos de catálogo ou Pokédex NATIONAL ausentes');
      raise exception 'MS892' using errcode = 'P0001';
    end if;
    insert into public.expansion (game_id, code, name, release_order)
    values (v_game, 'EC_' || upper(v_sfx), 'EC Harness ' || v_sfx,
            (select coalesce(max(x.release_order), 0) + 1000 from public.expansion x where x.game_id = v_game))
    returning id into v_exp;
    insert into public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_exp, 'EC' || upper(v_sfx), 'EC Set ' || v_sfx, 'REGULAR', 1, 1, 1) returning id into v_set;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '1', 1, 'EC K1', true) returning id into k1;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k1, v_std, 1, true) returning id into k1s;

    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    select u.id, 'authenticated', 'authenticated', 'wh892' || u.t || '_' || v_sfx || '@example.invalid',
           jsonb_build_object('username', 'wh892' || u.t || '_' || v_sfx, 'display_name', 'WH 5892 ' || upper(u.t)), now(), now()
    from (values (u_a, 'a'), (u_b, 'b'), (u_v, 'v'), (u_r, 'r'), (u_e, 'e'), (u_c, 'c')) u(id, t);
    select i.id into v_inv_a from public.inventory i where i.owner_user_id = u_a;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, created_at)
    select k1s, v_pt, v_inv_a, now() - (v.o || ' min')::interval from (values (3), (2), (1)) v(o);
    select array_agg(pc.id order by pc.created_at) into v_ids from public.physical_card pc where pc.inventory_id = v_inv_a;
    a1 := v_ids[1]; s1 := v_ids[2]; f1 := v_ids[3];

    perform pg_temp.wh_5892_as(u_a);
    select x.storage_container_id into v_bp from public.create_my_storage_container(gen_random_uuid(), 'BIN P 5892', 'BINDER') x;
    select x.storage_container_id into v_bs from public.create_my_storage_container(gen_random_uuid(), 'BIN S 5892', 'BINDER') x;
    select x.storage_container_id into v_bf from public.create_my_storage_container(gen_random_uuid(), 'BIN F 5892', 'BINDER') x;
    select x.collection_id into v_cp from public.create_my_pokedex_collection(gen_random_uuid(), 'CP 5892', array[v_gen], v_bp) x;
    select x.collection_id into v_cs from public.create_my_free_collection(gen_random_uuid(), 'CS 5892', v_bs) x;
    select x.collection_id into v_cf from public.create_my_free_collection(gen_random_uuid(), 'CF 5892', v_bf) x;
    perform public.allocate_physical_cards_to_collection(v_cp, array[a1]);
    perform public.allocate_physical_cards_to_collection(v_cs, array[s1]);
    perform public.allocate_physical_cards_to_collection(v_cf, array[f1]);
    select * into p from public.preview_my_collection_binder(v_cp, 2, 2, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_cp, 2, 2, 'PRINCIPAL_ONLY', p.plan_token);
    select * into p from public.preview_my_collection_binder(v_cs, 2, 2, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_cs, 2, 2, 'PRINCIPAL_ONLY', p.plan_token);
    select * into p from public.preview_my_collection_binder(v_cf, 2, 2, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_cf, 2, 2, 'PRINCIPAL_ONLY', p.plan_token);
    execute 'reset role';
    select l.id, l.storage_container_id into l_p, c_p from public.collection_layout l where l.collection_id = v_cp;
    select l.id, l.storage_container_id into l_s, c_s from public.collection_layout l where l.collection_id = v_cs;
    select l.id, l.storage_container_id into l_f, c_f from public.collection_layout l where l.collection_id = v_cf;
    delete from public.collection_layout_slot_assignment a using public.collection_layout_slot s, public.collection_layout_page p2
     where a.slot_id = s.id and s.page_id = p2.id and p2.layout_id in (l_p, l_s, l_f);
    delete from public.collection_layout_slot_expected_content e using public.collection_layout_slot s, public.collection_layout_page p2
     where e.slot_id = s.id and s.page_id = p2.id and p2.layout_id in (l_p, l_s, l_f);
    delete from public.collection_layout_slot_species_reference sr where sr.layout_id in (l_p, l_s, l_f);
    update public.physical_card pc set storage_container_id = c_p where pc.id = a1;
    update public.physical_card pc set storage_container_id = c_s where pc.id = s1;
    update public.physical_card pc set storage_container_id = c_f where pc.id = f1;
    insert into public.collection_layout_slot_image (slot_id, owner_user_id, storage_path)
    values (pg_temp.wh_5892_slot(l_p, 1, 2, 2), u_a, u_a::text || '/' || l_p::text || '/' || gen_random_uuid()::text || '.webp');  -- E1E: C1 — caminho canônico (uuid), atende aos CHECKs 5232
    select s.page_id into v_page_img from public.collection_layout_slot s where s.id = pg_temp.wh_5892_slot(l_p, 1, 2, 2);
    perform pg_temp.wh_5892_as(u_a);
    select x.collection_id into v_cg from public.create_my_free_collection(gen_random_uuid(), 'CG 5892', c_f) x;
    perform public.attach_my_collection_to_binder(v_cg, l_f);
    m_b  := (public.invite_collection_member(v_cp, 'wh892b_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_bs := (public.invite_collection_member(v_cs, 'wh892b_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_bf := (public.invite_collection_member(v_cf, 'wh892b_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_v  := (public.invite_collection_member(v_cp, 'wh892v_' || v_sfx) ->> 'membership_id')::uuid;
    m_r  := (public.invite_collection_member(v_cp, 'wh892r_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_e  := (public.invite_collection_member(v_cg, 'wh892e_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    perform pg_temp.wh_5892_as(u_b);
    perform public.respond_collection_invite(m_b, true);
    perform public.respond_collection_invite(m_bs, true);
    perform public.respond_collection_invite(m_bf, true);
    perform pg_temp.wh_5892_as(u_v); perform public.respond_collection_invite(m_v, true);
    perform pg_temp.wh_5892_as(u_r); perform public.respond_collection_invite(m_r, true);
    perform pg_temp.wh_5892_as(u_e); perform public.respond_collection_invite(m_e, true);
    perform pg_temp.wh_5892_as(u_a); perform public.remove_collection_member(v_cp, m_r);
    execute 'reset role';
    np := pg_temp.wh_5892_pages(l_p);
    select string_agg(ca.physical_card_id::text || ':' || ca.collection_id::text, ',' order by ca.physical_card_id) into alloc0
      from public.collection_allocation ca where ca.physical_card_id in (a1, s1, f1);
    select string_agg(md5((to_jsonb(pc) - 'updated_at')::text), ',' order by pc.id) into pc0
      from public.physical_card pc where pc.id in (a1, s1, f1);
    res := res || jsonb_build_object('id','F.2','ok',
      l_p is not null and l_s is not null and l_f is not null and np between 1 and 30
      and not exists (select 1 from public.collection_layout_guest g where g.layout_id in (l_p, l_s))
      and exists (select 1 from public.collection_layout_guest g where g.layout_id = l_f and g.collection_id = v_cg)
      and exists (select 1 from public.collection_layout_slot_image i where i.slot_id = pg_temp.wh_5892_slot(l_p, 1, 2, 2)),
      'detail','fixture: CP e CS com fichário exclusivo, CF com convidada CG, imagem do titular em CP p1 r2c2');

    -- 1. Páginas no fichário exclusivo -----------------------------------------------------------
    perform pg_temp.wh_5892_as(u_b);
    select x.page_number || ':' || x.slots_created into v_txt from public.editor_add_binder_page(v_cp) x;
    v_new := np + 1;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.1','ok', v_txt = v_new || ':4' and pg_temp.wh_5892_pages(l_p) = v_new
      and exists (select 1 from public.binder_activity_event e where e.layout_key = l_p and e.actor_user_id = u_b
                  and e.event_type = 'PAGES_ADDED' and e.collection_id = v_cp),
      'detail','EDITOR adiciona página vazia no fim (4 bolsos); evento PAGES_ADDED com o EDITOR e CP');
    perform pg_temp.wh_5892_as(u_b);
    select array_agg(g order by g desc) into v_ord from generate_series(1, v_new) g;
    perform count(*) from public.editor_reorder_binder_pages(v_cp, v_ord);
    execute 'reset role';
    res := res || jsonb_build_object('id','1.2','ok',
      (select p2.page_number from public.collection_layout_page p2 where p2.id = v_page_img) = v_new
      and exists (select 1 from public.collection_layout_slot_image i join public.collection_layout_slot s on s.id = i.slot_id
                  where s.page_id = v_page_img and s.row_index = 2 and s.column_index = 2)
      and exists (select 1 from public.binder_activity_event e where e.layout_key = l_p and e.actor_user_id = u_b
                  and e.event_type = 'PAGES_REORDERED'),
      'detail','reordenar move páginas inteiras: a imagem do titular continua no mesmo bolso da mesma página');
    perform pg_temp.wh_5892_as(u_b);
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    select count(*) into n from public.binder_activity_event e where e.layout_key = l_p;
    perform pg_temp.wh_5892_as(u_b);  -- E1E: volta ao mesmo cliente
    v_err := pg_temp.wh_5892_try(format('select * from public.editor_reorder_binder_pages(%L, %L)', v_cp, array[1, 1]::integer[]))
          || ';' || pg_temp.wh_5892_try(format('select * from public.editor_reorder_binder_pages(%L, %L)', v_cp,
                     (select array_agg(g order by g) from generate_series(1, v_new) g)));
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    select count(*) into n2 from public.binder_activity_event e where e.layout_key = l_p;
    perform pg_temp.wh_5892_as(u_b);  -- E1E: volta ao mesmo cliente
    res := res || jsonb_build_object('id','1.3','ok', v_err = 'INVALID_PAGE_ORDER;OK' and n2 = n,
      'detail','ordem inválida recusada; ordem igual à atual → sem evento');
    -- a página nova é agora a página 1 (ordem invertida)
    v_err := pg_temp.wh_5892_try(format('select * from public.editor_remove_binder_page(%L, %s)', v_cp, v_new));
    perform public.editor_place_card_in_binder(v_cp, 1, 1, 1, a1);
    v_err := v_err || ';' || pg_temp.wh_5892_try(format('select * from public.editor_remove_binder_page(%L, 1)', v_cp));
    perform public.editor_remove_binder_card(v_cp, 1, 1, 1);
    perform pg_temp.wh_5892_as(u_a); perform public.set_slot_lock(array[pg_temp.wh_5892_slot(l_p, 1, 2, 1)], true);
    perform pg_temp.wh_5892_as(u_b);
    v_err := v_err || ';' || pg_temp.wh_5892_try(format('select * from public.editor_remove_binder_page(%L, 1)', v_cp));
    perform pg_temp.wh_5892_as(u_a); perform public.set_slot_lock(array[pg_temp.wh_5892_slot(l_p, 1, 2, 1)], false);
    execute 'reset role';
    res := res || jsonb_build_object('id','1.4','ok', v_err = 'OPERATION_RESERVED_TO_OWNER;PAGE_NOT_EMPTY;OPERATION_RESERVED_TO_OWNER'
      and pg_temp.wh_5892_pages(l_p) = v_new,
      'detail','página com imagem do titular ou com bolso vazio fixado pelo titular → reservada ao titular; com carta da coleção → PAGE_NOT_EMPTY; sem contagens');

    -- 2. Fichário de várias coleções ---------------------------------------------------------------
    perform pg_temp.wh_5892_as(u_b);
    v_err := pg_temp.wh_5892_try(format('select * from public.editor_add_binder_page(%L)', v_cf))
          || ';' || pg_temp.wh_5892_try(format('select * from public.editor_reorder_binder_pages(%L, %L)', v_cf, array[1]::integer[]))
          || ';' || pg_temp.wh_5892_try(format('select * from public.editor_remove_binder_page(%L, 1)', v_cf))
          || ';' || pg_temp.wh_5892_try(format('select * from public.editor_set_binder_species_reference_visibility(%L, false)', v_cf))
          || ';' || pg_temp.wh_5892_try(format('select * from public.editor_preview_binder_species_references(%L)', v_cf));
    perform pg_temp.wh_5892_as(u_e);
    v_err := v_err || ';' || pg_temp.wh_5892_try(format('select * from public.editor_add_binder_page(%L)', v_cg))
          || ';' || pg_temp.wh_5892_try(format('select * from public.editor_set_binder_species_reference_visibility(%L, false)', v_cg))
          || ';' || pg_temp.wh_5892_try(format('select * from public.editor_preview_binder_species_references(%L)', v_cg));
    execute 'reset role';
    res := res || jsonb_build_object('id','2.1','ok',
      v_err = 'OPERATION_RESERVED_TO_OWNER;OPERATION_RESERVED_TO_OWNER;OPERATION_RESERVED_TO_OWNER;OPERATION_RESERVED_TO_OWNER;OPERATION_RESERVED_TO_OWNER;OPERATION_RESERVED_TO_OWNER;OPERATION_RESERVED_TO_OWNER;OPERATION_RESERVED_TO_OWNER',
      'detail','fichário com convidada: EDITOR da proprietária e da convidada recusados em páginas e referências (C-237)');
    res := res || jsonb_build_object('id','2.2','ok',
      not exists (select 1 from public.binder_activity_event e where e.layout_key = l_f and e.actor_user_id in (u_b, u_e))
      and not exists (select 1 from public.collection_layout_species_reference_setting st where st.layout_id = l_f),
      'detail','recusas em fichário de várias coleções não gravam nada');

    -- 3. Referências de espécie (Pokédex exclusiva) ------------------------------------------------
    perform pg_temp.wh_5892_as(u_b);
    select * into p from public.editor_preview_binder_species_references(v_cp);
    v_tok := p.plan_token;
    v_err := pg_temp.wh_5892_try(format('select * from public.editor_apply_binder_species_references(%L, %L)', v_cp, repeat('a', 64)));
    select x.operation || ':' || x.reference_count into v_txt from public.editor_apply_binder_species_references(v_cp, v_tok) x;
    execute 'reset role';
    res := res || jsonb_build_object('id','3.1','ok', v_err = 'PLAN_CHANGED' and p.pair_count > 0
      and p.pair_count = least(p.slots_total, p.positions_in_scope) and v_txt = 'APPLIED:' || p.pair_count
      and (select count(*) from public.collection_layout_slot_species_reference sr where sr.layout_id = l_p and sr.collection_id = v_cp) = p.pair_count,
      'detail','prévia com token; token antigo → PLAN_CHANGED; aplicar grava a camada de CP inteira');
    perform pg_temp.wh_5892_as(u_b);
    select * into p from public.editor_preview_binder_species_references(v_cp);
    select x.operation into v_txt from public.editor_apply_binder_species_references(v_cp, p.plan_token) x;
    execute 'reset role';
    res := res || jsonb_build_object('id','3.2','ok', p.already_applied and v_txt = 'ALREADY_APPLIED',
      'detail','aplicar de novo o mesmo plano → ALREADY_APPLIED');
    res := res || jsonb_build_object('id','3.3','ok',
      exists (select 1 from public.collection_layout_slot_image i where i.slot_id = pg_temp.wh_5892_slot(l_p, v_new, 2, 2))
      and public.binder_slot_editor_scope(l_p, v_cp, v_cp, pg_temp.wh_5892_slot(l_p, v_new, 2, 2)) = 'FOREIGN'
      and public.binder_slot_editor_scope(l_p, v_cp, v_cp, pg_temp.wh_5892_slot(l_p, v_new, 1, 1)) = 'OWN',
      'detail','bolso com imagem do titular recebe o rótulo, a imagem fica e o bolso continua FOREIGN; bolso só com referência de CP = OWN');
    perform pg_temp.wh_5892_as(u_b);
    select x.operation into v_txt from public.editor_set_binder_species_reference_visibility(v_cp, false) x;
    select v_txt || ';' || x.operation into v_txt from public.editor_set_binder_species_reference_visibility(v_cp, false) x;
    select v_txt || ';' || x.operation into v_txt from public.editor_set_binder_species_reference_visibility(v_cp, true) x;
    execute 'reset role';
    res := res || jsonb_build_object('id','3.4','ok', v_txt = 'UPDATED;UNCHANGED;UPDATED'
      and (select st.references_visible from public.collection_layout_species_reference_setting st where st.layout_id = l_p),
      'detail','ocultar, repetir (UNCHANGED) e mostrar; nenhum vínculo apagado');
    -- remover página vazia com referências de CP (a página 1, que era a nova)
    perform pg_temp.wh_5892_as(u_b);
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    select count(*)::integer into n from public.collection_layout_slot_species_reference sr
      join public.collection_layout_slot s on s.id = sr.slot_id
      join public.collection_layout_page p2 on p2.id = s.page_id where p2.layout_id = l_p and p2.page_number = 1;
    perform pg_temp.wh_5892_as(u_b);  -- E1E: volta ao mesmo cliente
    v_err := pg_temp.wh_5892_try(format('select * from public.editor_remove_binder_page(%L, 1)', v_cp));
    select x.removed_page_number || ':' || x.species_references_removed into v_txt from public.editor_remove_binder_page(v_cp, 1, n) x;
    execute 'reset role';
    res := res || jsonb_build_object('id','3.5','ok', n = 4 and v_err = 'SPECIES_REFERENCES_ON_PAGE' and v_txt = '1:4'
      and pg_temp.wh_5892_pages(l_p) = np
      and (select p2.page_number from public.collection_layout_page p2 where p2.id = v_page_img) = np
      and exists (select 1 from public.binder_activity_event e where e.layout_key = l_p and e.actor_user_id = u_b
                  and e.event_type = 'PAGE_REMOVED'),
      'detail','página vazia com referências de CP exige a contagem; removida, as demais são renumeradas; evento PAGE_REMOVED');
    perform pg_temp.wh_5892_as(u_b);
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    select count(*)::integer into n from public.collection_layout_slot_species_reference sr where sr.layout_id = l_p;
    perform pg_temp.wh_5892_as(u_b);  -- E1E: volta ao mesmo cliente
    v_err := pg_temp.wh_5892_try(format('select * from public.editor_clear_binder_species_references(%L, %s)', v_cp, n + 1));
    select x.operation || ':' || x.removed_count into v_txt from public.editor_clear_binder_species_references(v_cp, n) x;
    v_err := v_err || ';' || pg_temp.wh_5892_try(format('select * from public.editor_preview_binder_species_references(%L)', v_cs));
    execute 'reset role';
    res := res || jsonb_build_object('id','3.6','ok', v_err = 'COUNT_MISMATCH;NOT_POKEDEX_COLLECTION' and v_txt = 'REMOVED:' || n
      and not exists (select 1 from public.collection_layout_slot_species_reference sr where sr.layout_id = l_p),
      'detail','remover exige a contagem atual; remove a camada inteira; coleção livre → NOT_POKEDEX_COLLECTION');

    -- 4. Recusas de autorização ----------------------------------------------------------------------
    v_err := '';
    foreach v_u in array array[u_v, u_c, u_r, u_a] loop
      perform pg_temp.wh_5892_as(v_u);
      v_err := v_err || pg_temp.wh_5892_try(format('select * from public.editor_add_binder_page(%L)', v_cp)) || ';'
                     || pg_temp.wh_5892_try(format('select * from public.editor_preview_binder_species_references(%L)', v_cp)) || ';';
    end loop;
    perform pg_temp.wh_5892_as(null);
    v_err := v_err || pg_temp.wh_5892_try(format('select * from public.editor_add_binder_page(%L)', v_cp));
    execute 'reset role';
    res := res || jsonb_build_object('id','4.1','ok',
      v_err ~ ('^' || repeat('COLLECTION_NOT_FOUND;', 8) || 'permission denied')
      and pg_temp.wh_5892_pages(l_p) = np,
      'detail','VIEWER, estranho, ex-membro e titular pelo caminho do EDITOR → COLLECTION_NOT_FOUND; anon sem EXECUTE; nada gravado');
    perform pg_temp.wh_5892_as(u_b);
    select x.page_number into n from public.editor_add_binder_page(v_cs) x;
    execute 'reset role';
    res := res || jsonb_build_object('id','4.2','ok', n = pg_temp.wh_5892_pages(l_s),
      'detail','coleção livre com fichário exclusivo: EDITOR também gerencia páginas');

    -- 5. Tipos de evento do EDITOR (5381) --------------------------------------------------------------
    res := res || jsonb_build_object('id','5.1','ok',
      not exists (select 1 from public.binder_activity_event e
                  where e.layout_key in (l_p, l_s, l_f) and e.actor_user_id in (u_b, u_e)
                    and (e.event_type not in ('CARD_PLACED', 'CARD_MOVED', 'CARDS_SWAPPED', 'CARDS_REMOVED',
                                              'POCKET_RESERVED', 'RESERVATIONS_RELEASED', 'POCKETS_LOCKED', 'POCKETS_UNLOCKED',
                                              'PAGES_ADDED', 'PAGE_REMOVED', 'PAGES_REORDERED')
                         or e.source <> 'FICHARIO' or e.collection_id is null)),
      'detail','todo evento do EDITOR é de curadoria, de origem FICHARIO e com coleção');
    perform pg_temp.wh_5892_as(u_b);
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    n := pg_temp.wh_5892_pages(l_p);
    perform pg_temp.wh_5892_as(u_b);  -- E1E: volta ao mesmo cliente
    perform set_config('mmkyu.binder_activity_ctx', jsonb_build_object('depth', 1, 'layout', l_p, 'type', 'BINDER_DISMANTLED',
      'source', 'FICHARIO', 'collection', v_cp, 'summary', '{}'::jsonb, 'event_id', null, 'n', 0, 'cap', 0)::text, true);
    v_err := pg_temp.wh_5892_try(format('select * from public.editor_add_binder_page(%L)', v_cp));
    perform set_config('mmkyu.binder_activity_ctx', jsonb_build_object('depth', 1, 'layout', l_p, 'type', 'PAGES_ADDED',
      'source', 'ACERVO', 'collection', v_cp, 'summary', '{}'::jsonb, 'event_id', null, 'n', 0, 'cap', 0)::text, true);
    v_err := v_err || ';' || pg_temp.wh_5892_try(format('select * from public.editor_add_binder_page(%L)', v_cp));
    perform set_config('mmkyu.binder_activity_ctx', '', true);
    execute 'reset role';
    res := res || jsonb_build_object('id','5.2','ok',
      v_err = 'binder activity: event type not allowed for this actor;binder activity: event type not allowed for this actor'
      and pg_temp.wh_5892_pages(l_p) = n,
      'detail','contexto forjado com tipo estrutural ou origem de acervo → recusa (5381) e a operação inteira é desfeita');
    res := res || jsonb_build_object('id','5.3','ok',
      exists (select 1 from public.binder_activity_event e where e.layout_key = l_f and e.actor_user_id = u_a
              and e.event_type = 'COLLECTION_ATTACHED')
      and exists (select 1 from public.binder_activity_event e where e.layout_key = l_p and e.actor_user_id = u_a
                  and e.event_type = 'BINDER_ASSEMBLED'),
      'detail','eventos estruturais do titular (montagem, associação) continuam gravados');

    -- 6. Revogação ---------------------------------------------------------------------------------------
    select count(*) into n from public.binder_activity_event e where e.actor_user_id = u_b;
    perform pg_temp.wh_5892_as(u_a); perform public.set_collection_member_role(v_cp, m_b, 'VIEWER');
    perform pg_temp.wh_5892_as(u_b);
    v_err := pg_temp.wh_5892_try(format('select * from public.editor_add_binder_page(%L)', v_cp))
          || ';' || pg_temp.wh_5892_try(format('select * from public.editor_set_binder_species_reference_visibility(%L, false)', v_cp));
    perform pg_temp.wh_5892_as(u_a); perform public.set_collection_member_role(v_cp, m_b, 'EDITOR');
    execute 'reset role';
    select count(*) into n2 from public.binder_activity_event e where e.actor_user_id = u_b;
    res := res || jsonb_build_object('id','6.1','ok', v_err = 'COLLECTION_NOT_FOUND;COLLECTION_NOT_FOUND' and n2 = n,
      'detail','EDITOR rebaixado perde páginas e referências na hora; nenhum evento depois');

    -- 7. Titular intocado ---------------------------------------------------------------------------------
    perform pg_temp.wh_5892_as(u_a);
    select x.id into v_u from public.add_layout_page(l_f) x;
    perform public.reorder_layout_pages(l_f, (select array_agg(p2.id order by p2.page_number desc)
                                               from public.collection_layout_page p2 where p2.layout_id = l_f));
    perform public.remove_layout_page(v_u, 0);
    select x.operation into v_txt from public.set_my_binder_species_reference_visibility(v_cp, false) x;
    execute 'reset role';
    res := res || jsonb_build_object('id','7.1','ok', v_txt = 'UPDATED'
      and exists (select 1 from public.binder_activity_event e where e.layout_key = l_f and e.actor_user_id = u_a
                  and e.event_type in ('PAGES_ADDED', 'PAGES_REORDERED', 'PAGE_REMOVED')),
      'detail','titular continua com páginas no fichário de várias coleções e com a exibição das referências (5280/5282/5286/5258)');

    -- 7b. Fichário exclusivo com conteúdo de terceiros (proprietária anterior) ------------------------
    -- O titular aplica referências em CP, posiciona a1, transfere a âncora para CQ (5254) e
    -- desassocia CP (posições ficam, 5253): o fichário passa a ser EXCLUSIVO de CQ, com a
    -- carta e as referências de CP — conteúdo de terceiros para o EDITOR de CQ.
    perform pg_temp.wh_5892_as(u_a);
    perform count(*) from public.add_layout_page(l_p);
    select * into p from public.preview_my_binder_species_references(v_cp);
    perform count(*) from public.apply_my_binder_species_references(v_cp, p.plan_token);
    perform public.place_my_physical_card_in_slot(v_cp, pg_temp.wh_5892_slot(l_p, np + 1, 1, 1), a1);
    select x.collection_id into v_cq from public.create_my_free_collection(gen_random_uuid(), 'CQ 5892', c_p) x;
    perform count(*) from public.transfer_my_binder_ownership(v_cp, v_cq);
    select * into p from public.preview_my_collection_binder_detach(v_cp);
    perform count(*) from public.detach_my_collection_from_binder(v_cp, p.detach_token, false);
    m_bq := (public.invite_collection_member(v_cq, 'wh892b_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    perform pg_temp.wh_5892_as(u_b); perform public.respond_collection_invite(m_bq, true);
    execute 'reset role';
    select count(*)::integer into n from public.collection_layout_slot_species_reference sr where sr.layout_id = l_p and sr.collection_id = v_cp;
    select a.slot_id into v_u from public.collection_layout_slot_assignment a where a.physical_card_id = a1;
    perform pg_temp.wh_5892_as(u_b);
    v_err := pg_temp.wh_5892_try(format('select * from public.editor_remove_binder_page(%L, %s, %s)', v_cq, np + 1, 4))
          || ';' || pg_temp.wh_5892_try(format('select * from public.editor_clear_binder_species_references(%L, %s)', v_cq, n))
          || ';' || pg_temp.wh_5892_try(format('select * from public.editor_set_binder_species_reference_visibility(%L, false)', v_cq))
          || ';' || pg_temp.wh_5892_try(format('select * from public.editor_preview_binder_species_references(%L)', v_cq));
    execute 'reset role';
    res := res || jsonb_build_object('id','7.2','ok',
      (select l.collection_id from public.collection_layout l where l.id = l_p) = v_cq
      and not exists (select 1 from public.collection_layout_guest g where g.layout_id = l_p) and n > 0 and v_u is not null
      and v_err = 'OPERATION_RESERVED_TO_OWNER;OPERATION_RESERVED_TO_OWNER;OPERATION_RESERVED_TO_OWNER;OPERATION_RESERVED_TO_OWNER',
      'detail','fichário exclusivo de CQ com carta e referências da antiga proprietária: remover página, remover/esconder referências e prévia → reservadas ao titular');
    perform pg_temp.wh_5892_as(u_b);
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    v_e1e_np := pg_temp.wh_5892_pages(l_p);  -- E1E
    perform pg_temp.wh_5892_as(u_b);  -- E1E: volta ao mesmo cliente
    perform count(*) from public.editor_reorder_binder_pages(v_cq,
      (select array_agg(g order by g desc) from generate_series(1, v_e1e_np) g));  -- E1E
    perform count(*) from public.editor_add_binder_page(v_cq);
    execute 'reset role';
    res := res || jsonb_build_object('id','7.3','ok',
      (select count(*)::integer from public.collection_layout_slot_species_reference sr where sr.layout_id = l_p and sr.collection_id = v_cp) = n
      and (select a.slot_id from public.collection_layout_slot_assignment a where a.physical_card_id = a1) = v_u
      and exists (select 1 from public.collection_layout_slot_image i join public.collection_layout_slot s on s.id = i.slot_id
                  where s.page_id = v_page_img)
      and (select st.references_visible from public.collection_layout_species_reference_setting st where st.layout_id = l_p),
      'detail','reordenar e adicionar página no mesmo fichário não tocam a carta (mesmo bolso), as referências de CP, a imagem nem a exibição');

    -- 8. Patrimônio ----------------------------------------------------------------------------------------
    res := res || jsonb_build_object('id','8.1','ok',
      (select string_agg(ca.physical_card_id::text || ':' || ca.collection_id::text, ',' order by ca.physical_card_id)
         from public.collection_allocation ca where ca.physical_card_id in (a1, s1, f1)) = alloc0
      and (select string_agg(md5((to_jsonb(pc) - 'updated_at')::text), ',' order by pc.id)
             from public.physical_card pc where pc.id in (a1, s1, f1)) = pc0,
      'detail','nenhuma alocação, local, condição ou outro campo de exemplar mudou');

    -- 9. Coleção arquivada ----------------------------------------------------------------------------------
    perform pg_temp.wh_5892_as(u_a); perform public.archive_collection(v_cs);
    perform pg_temp.wh_5892_as(u_b);
    v_err := pg_temp.wh_5892_try(format('select * from public.editor_add_binder_page(%L)', v_cs))
          || ';' || pg_temp.wh_5892_try(format('select * from public.editor_reorder_binder_pages(%L, %L)', v_cs, array[1]::integer[]));
    execute 'reset role';
    res := res || jsonb_build_object('id','9.1','ok', v_err = 'COLLECTION_ARCHIVED;COLLECTION_ARCHIVED',
      'detail','coleção arquivada: EDITOR recusado só depois de autorizado');

    execute 'reset role';
    raise exception 'MS892' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MS892' then
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
               (select count(*) from public.collection_layout_slot), (select count(*) from public.collection_layout_slot_species_reference),
               (select count(*) from public.collection_layout_species_reference_setting),
               (select count(*) from public.binder_activity_event), (select count(*) from public.binder_activity_item)]
    into e_counts;
  res := res || jsonb_build_object('id','99.1','ok', b_counts = e_counts and current_user = session_user,
    'detail','resíduo zero (11 contagens, inclusive páginas, bolsos, referências e histórico) e papel restaurado');

  v_expected := 27;
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
