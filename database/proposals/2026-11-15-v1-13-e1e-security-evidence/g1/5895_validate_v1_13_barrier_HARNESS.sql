/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5895 - Harness da barreira da V1-13 (D-E1, G1): porta 5389 e as
              37 capacidades protegidas em CLOSED, TEST e OPEN; contas
              registradas e não registradas; sessão anônima; configuração
              ausente; tabelas administrativas; preservação da V1-12; Storage
Versão......: 1.1 (2026-11-15, `E1-E2 | PROTECTED CHAIN AND G2 TEST READINESS-01`: 0.4 fixava
              em get_shared_collection o md5 da 5308 — corrigido para o corpo da 5368
              e 5308 conferida à parte; defeito encontrado pela conferência de md5
              fixados da E1-E2). 1.0
Status......: PROPOSTA — NÃO EXECUTADA. Prova da barreira para o G2. Sem
              ambiente isolado (C-244): executar SOMENTE sob protocolo
              controlado equivalente ao P1 (transação explícita READ WRITE
              terminada em erro/ROLLBACK, conexão direta única, psql), depois
              de 5389 + cadeia PROTEGIDA (g1/protected/) e com autorização
              expressa e específica. Sem BEGIN/COMMIT próprios.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-15

Pressupõe aplicadas, na transação do ensaio: 5389 (modo CLOSED, registro
vazio) → 5366–5368 → g1/protected/5369, 5370 → 5371, 5372 → protected 5373,
5374 → protected 5375, 5376, 5377 → 5378, 5379 → protected 5380 → 5381 →
protected 5382, 5383 → 5384 → protected 5385, 5386, 5387 → protected 5323,
5324, 5388.

Separação das duas camadas (nunca confundir):
  - barreira: a recusa é exatamente 'CAPABILITY_NOT_ENABLED' (escritas) ou
    zero linhas / falso (leituras e ajudantes) — e só acontece para quem a
    porta fecha;
  - autorização funcional: com a porta aberta, a resposta é a do produto
    (recusa por papel, coleção, validação) e NUNCA 'CAPABILITY_NOT_ENABLED'.
  Chamadas com argumentos nulos servem só para provar a porta (ela é a
  primeira instrução); a autorização funcional é provada com chamadas reais
  (2.3) e pelos harnesses funcionais 5888–5894, rodados com a porta aberta.

Usuários efêmeros (R = registrado como identidade de teste):
  A titular (R) · B EDITOR de CF (R) · U EDITOR de CF (não R) · V VIEWER de
  CF, CD, CM (R) · W VIEWER de CF, CD, CM (não R) · R EDITOR de CF removido
  (R) · P convite EDITOR pendente em CF (R) · S estranho (R) · X convidado
  VIEWER em CLOSED (não R) · Q convidado EDITOR em TEST e aceito em CLOSED
  (não R) · O titular de CO (não R) · T alvo dos convites de O.
Coleções: CF livre (A); CD Pokédex (A); CM Master Set (A); CO Pokédex (O).

  select * from pg_temp.wh_5895_validate();
  -- GATE esperado: 21/21 PASS (20 verificações + F.2)

Limitações declaradas:
  L1 SET LOCAL ROLE prova o banco, não o JWT do PostgREST nem a API do
     Storage: G3 (negação com JWT real) e G4 (contas de teste) continuam
     obrigatórios.
  L2 Sessão única: a revogação durante uma chamada em curso (CLOSED não
     cancela chamadas iniciadas) e a concorrência ficam para G4.
  L3 Leituras com argumentos nulos devolvem zero linhas com a porta aberta ou
     fechada; a prova de passagem das leituras usa dados da fixture (2.4).
================================================================
*/

create or replace function pg_temp.wh_5895_as(p_user uuid)
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

create or replace function pg_temp.wh_5895_try(p_sql text)
returns text language plpgsql volatile as $try$
begin
  execute p_sql;
  return 'OK';
exception when others then
  return sqlerrm;
end;
$try$;

-- Chama a função pela assinatura com argumentos nulos tipados; devolve 'OK' ou a mensagem.
create or replace function pg_temp.wh_5895_null_call(p_sig text)
returns text language plpgsql volatile as $nc$
declare
  v_oid  oid := to_regprocedure(p_sig);
  v_args text;
  v_sql  text;
begin
  if v_oid is null then
    return 'MISSING';
  end if;
  select coalesce(string_agg('NULL::' || format_type(t, null), ', ' order by o), '')
    into v_args
  from unnest((select p.proargtypes::oid[] from pg_proc p where p.oid = v_oid)) with ordinality u(t, o);
  select format('select count(*) from %I.%I(%s)', n.nspname, p.proname, v_args) into v_sql
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace where p.oid = v_oid;
  execute v_sql;
  return 'OK';
exception when others then
  return sqlerrm;
end;
$nc$;

-- Quantas das assinaturas devolveram exatamente a recusa da barreira.
create or replace function pg_temp.wh_5895_barrier_count(p_sigs text[])
returns integer language plpgsql volatile as $bc$
declare s text; n integer := 0;
begin
  foreach s in array p_sigs loop
    if pg_temp.wh_5895_null_call(s) = 'CAPABILITY_NOT_ENABLED' then n := n + 1; end if;
  end loop;
  return n;
end;
$bc$;

create or replace function pg_temp.wh_5895_reads(p_cf uuid, p_cd uuid, p_cm uuid)
returns text language plpgsql volatile as $rd$
begin
  return (select count(*) from public.get_shared_master_set_positions(p_cm, 'ALL', 500, 0))::text
    || '/' || (select count(*) from public.get_shared_pokedex_positions(p_cd, 'ALL', null, 500, 0))::text
    || '/' || (select count(*) from public.get_shared_binder_activity_status(p_cf))::text
    || '/' || (select count(*) from public.get_shared_binder_activity(p_cf, null, null, null, 50))::text
    || '/' || (select count(*) from public.get_shared_binder_placeable_cards(p_cf, 96, 0))::text;
end;
$rd$;

create or replace function pg_temp.wh_5895_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
as $fn$
#variable_conflict use_column
declare
  c_w text[] := array[
      'public.set_collection_member_role(UUID, UUID, TEXT)',
      'public.editor_place_card_in_binder(uuid, integer, integer, integer, uuid)',
      'public.editor_move_binder_card(uuid, integer, integer, integer, integer, integer, integer)',
      'public.editor_remove_binder_card(uuid, integer, integer, integer)',
      'public.editor_set_binder_reservation(uuid, integer, integer, integer, uuid, uuid, uuid)',
      'public.editor_clear_binder_reservation(uuid, integer, integer, integer)',
      'public.editor_set_binder_lock(uuid, integer, integer, integer, boolean)',
      'public.editor_update_collection_metadata(uuid, text, text)',
      'public.editor_set_collection_cover_finish(uuid, text)',
      'public.editor_set_collection_cover_code(uuid, text)',
      'public.editor_set_collection_cover_logo(uuid, text)',
      'public.editor_set_pokedex_position_assignment(uuid, uuid, uuid, boolean)',
      'public.editor_remove_pokedex_position_assignment(uuid, uuid)',
      'public.editor_set_pokedex_position_primary_representative(uuid, uuid)',
      'public.editor_clear_pokedex_position_primary_representative(uuid, uuid)',
      'public.editor_add_binder_page(uuid)',
      'public.editor_remove_binder_page(uuid, integer, integer)',
      'public.editor_reorder_binder_pages(uuid, integer[])',
      'public.editor_preview_binder_species_references(uuid)',
      'public.editor_apply_binder_species_references(uuid, text)',
      'public.editor_clear_binder_species_references(uuid, integer)',
      'public.editor_set_binder_species_reference_visibility(uuid, boolean)',
      'public.editor_preview_binder_insert_gap(uuid, integer, integer, integer)',
      'public.editor_insert_binder_gap(uuid, integer, integer, integer, text, boolean, boolean)',
      'public.editor_close_binder_gap(uuid, integer, integer, integer, integer, integer, integer, text, integer)',
      'public.editor_preview_binder_auto_arrange(uuid)',
      'public.editor_apply_binder_auto_arrange(uuid, text)',
      'public.editor_preview_binder_catalog_reconciliation(uuid, text[])',
      'public.editor_apply_binder_catalog_reconciliation(uuid, text[], text, boolean, boolean)'];
  c_r text[] := array[
      'public.get_shared_binder_placeable_cards(uuid, integer, integer)',
      'public.get_shared_master_set_positions(uuid, text, integer, integer)',
      'public.get_shared_pokedex_positions(uuid, text, text, integer, integer)',
      'public.get_shared_binder_activity(uuid, text[], timestamptz, bigint, integer)',
      'public.get_shared_binder_activity_status(uuid)'];
  c_h text[] := array[
      'public.collection_cover_editor_folder_ok(text)',
      'public.collection_cover_editor_can_upload(text)'];
  c_inv text := 'public.invite_collection_member(UUID, TEXT, TEXT)';
  c_gate text[] := array['public.v1_13_capability_open()', 'public.v1_13_assert_capability()'];
  u_a uuid := gen_random_uuid(); u_b uuid := gen_random_uuid(); u_u uuid := gen_random_uuid();
  u_v uuid := gen_random_uuid(); u_w uuid := gen_random_uuid(); u_r uuid := gen_random_uuid();
  u_p uuid := gen_random_uuid(); u_s uuid := gen_random_uuid(); u_x uuid := gen_random_uuid();
  u_q uuid := gen_random_uuid(); u_o uuid := gen_random_uuid(); u_t uuid := gen_random_uuid();
  v_sfx text := lower(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  v_game uuid; v_pt uuid; v_rar uuid; v_cat uuid; v_std uuid; v_exp uuid; v_sm uuid; v_gen text; m1 uuid;
  v_bf uuid; v_bd uuid; v_bm uuid; v_bo uuid; v_cf uuid; v_cd uuid; v_cm uuid; v_co uuid;
  m_b uuid; m_u uuid; m_v uuid; m_w uuid; m_r uuid; m_p uuid; m_q uuid; m_x uuid;
  m_vd uuid; m_wd uuid; m_vm uuid; m_wm uuid;
  f_ok text; f_own text; f_u text; f_b2 text;
  v_txt text; v_txt2 text; v_err text; v_j jsonb; v_ok boolean; n integer; n2 integer; s text;
  b_counts bigint[]; e_counts bigint[];
  res jsonb := '[]'::jsonb; r jsonb; cnt integer := 0; passes integer := 0;
  v_expected integer := 0;
begin
  -- 0. Estrutura e estado inicial ---------------------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    (select count(*) from pg_class c where c.oid in (to_regclass('public.v1_13_barrier_state'), to_regclass('public.v1_13_barrier_identity'))
       and c.relrowsecurity
       and not exists (select 1 from pg_policy p where p.polrelid = c.oid)
       and not has_table_privilege('anon', c.oid, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
       and not has_table_privilege('authenticated', c.oid, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
       and not has_table_privilege('service_role', c.oid, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')) = 2
    and (select count(*) from pg_proc q where q.oid in (to_regprocedure(c_gate[1]), to_regprocedure(c_gate[2]))
           and q.prosecdef and q.proconfig = array['search_path=""']
           and not has_function_privilege('anon', q.oid, 'EXECUTE')
           and not has_function_privilege('authenticated', q.oid, 'EXECUTE')
           and not has_function_privilege('service_role', q.oid, 'EXECUTE')) = 2,
    'detail','tabelas da barreira com RLS sem política e sem privilégio de cliente; porta definer, search_path vazio, sem EXECUTE para anon/authenticated/service_role');
  res := res || jsonb_build_object('id','0.2','ok',
    (select count(*) from unnest(c_w || c_r || c_h || array[c_inv]) s0(sig)
       join pg_proc q on q.oid = to_regprocedure(s0.sig)
      where q.prosecdef and has_function_privilege('authenticated', q.oid, 'EXECUTE')
        and not has_function_privilege('anon', q.oid, 'EXECUTE')
        and position('public.v1_13_' in q.prosrc) > 0) = 37
    and not exists (select 1 from pg_proc q join pg_namespace ns on ns.oid = q.pronamespace
                    where ns.nspname = 'public' and q.proname like 'editor\_%'
                      and has_function_privilege('authenticated', q.oid, 'EXECUTE')
                      and position('public.v1_13_' in q.prosrc) = 0),
    'detail','as 37 capacidades existem, são definer, só authenticated e chamam a porta; nenhuma RPC editor_* exposta sem porta');
  res := res || jsonb_build_object('id','0.3','ok',
    (select s1.mode from public.v1_13_barrier_state s1 where s1.id = 1) = 'CLOSED'
    and (select count(*) from public.v1_13_barrier_state) = 1
    and not exists (select 1 from public.v1_13_barrier_identity),
    'detail','estado ao fim da aplicação: CLOSED, uma linha, registro vazio');
  res := res || jsonb_build_object('id','0.4','ok',
    (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.collection_share_role(uuid)')) = 'efdb495b5b703e9f093eb0f49a1d0a5d'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.get_shared_collection(uuid)')) = '69d69fd11dddcaedabe7368a3e038368'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.get_my_collection_sharing(uuid)')) = 'e36aa9c675f6b8097b6a43292b62603f'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)')) = 'f8cfba40e442e85056e7c8ce7954d4f4'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.binder_slot_editor_scope(uuid, uuid, uuid, uuid)')) = '21f1b51a3a0f6c80337c2c593cc6054f'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.binder_activity_event_editor_type_guard()')) = '78fa0d34dad161eac1165f3143874260',
    'detail','funções compartilhadas sem porta e iguais às auditadas: 5302, leitura V1-12 substituída pela 5368 (get_shared_collection) e 5308 inalterada, gravação do histórico (5379), classificação (5378), gatilho (5384)');

  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_membership), (select count(*) from public.collection_allocation),
               (select count(*) from public.physical_card), (select count(*) from public.card),
               (select count(*) from storage.objects),
               (select count(*) from public.v1_13_barrier_state), (select count(*) from public.v1_13_barrier_identity),
               (select count(*) from public.binder_activity_event)]
    into b_counts;

  begin
    -- F. Fixture (modo TEST para os convites EDITOR) ---------------------------------------------
    select g.id into v_game from public.game g where g.code = 'POKEMON';
    select l.id into v_pt from public.language l where l.code = 'pt-BR';
    select t.id into v_std from public.card_variant_type t where t.game_id = v_game and t.code = 'STANDARD';
    select c.id into v_cat from public.card_category c where c.game_id = v_game and c.code = 'POKEMON';
    select c0.rarity_id into v_rar
    from public.card c0 join public.card_set cs0 on cs0.id = c0.card_set_id
    join public.expansion e0 on e0.id = cs0.expansion_id where e0.game_id = v_game limit 1;
    select g.code into v_gen
    from public.pokedex dx join public.pokedex_position pp on pp.pokedex_id = dx.id
    join public.pokemon_species sp on sp.id = pp.species_id join public.pokemon_generation g on g.id = sp.generation_id
    where dx.code = 'NATIONAL' order by pp.position_number limit 1;
    if v_game is null or v_pt is null or v_std is null or v_cat is null or v_rar is null or v_gen is null then
      res := res || jsonb_build_object('id','F.1','ok', false, 'detail','pré-requisitos de catálogo ou Pokédex NATIONAL ausentes');
      raise exception 'MS895' using errcode = 'P0001';
    end if;
    insert into public.expansion (game_id, code, name, release_order)
    values (v_game, 'BR_' || upper(v_sfx), 'BR Harness ' || v_sfx,
            (select coalesce(max(x.release_order), 0) + 1000 from public.expansion x where x.game_id = v_game))
    returning id into v_exp;
    insert into public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_exp, 'BR' || upper(v_sfx), 'BR Set ' || v_sfx, 'REGULAR', 1, 1, 1) returning id into v_sm;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_sm, v_rar, v_cat, '1', 1, 'BR 1', true) returning id into m1;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (m1, v_std, 1, true);

    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    select u.id, 'authenticated', 'authenticated', 'wh895' || u.t || '_' || v_sfx || '@example.invalid',
           jsonb_build_object('username', 'wh895' || u.t || '_' || v_sfx, 'display_name', 'WH 5895 ' || upper(u.t)), now(), now()
    from (values (u_a,'a'),(u_b,'b'),(u_u,'u'),(u_v,'v'),(u_w,'w'),(u_r,'r'),(u_p,'p'),(u_s,'s'),
                 (u_x,'x'),(u_q,'q'),(u_o,'o'),(u_t,'t')) u(id, t);
    update public.v1_13_barrier_state set mode = 'TEST' where id = 1;
    insert into public.v1_13_barrier_identity (user_id, note)
    select x, 'wh895' from unnest(array[u_a, u_b, u_v, u_r, u_p, u_s]) x;

    perform pg_temp.wh_5895_as(u_a);
    select x.storage_container_id into v_bf from public.create_my_storage_container(gen_random_uuid(), 'BIN F 5895', 'BINDER') x;
    select x.storage_container_id into v_bd from public.create_my_storage_container(gen_random_uuid(), 'BIN D 5895', 'BINDER') x;
    select x.storage_container_id into v_bm from public.create_my_storage_container(gen_random_uuid(), 'BIN M 5895', 'BINDER') x;
    select x.collection_id into v_cf from public.create_my_free_collection(gen_random_uuid(), 'CF 5895', v_bf) x;
    select x.collection_id into v_cd from public.create_my_pokedex_collection(gen_random_uuid(), 'CD 5895', array[v_gen], v_bd) x;
    select x.collection_id into v_cm from public.create_my_card_set_collection(gen_random_uuid(), v_sm, 'CM 5895', v_bm) x;
    perform count(*) from public.set_collection_completion_policy_to_master_set(v_cm, array[v_std]);
    m_b := (public.invite_collection_member(v_cf, 'wh895b_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_u := (public.invite_collection_member(v_cf, 'wh895u_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_r := (public.invite_collection_member(v_cf, 'wh895r_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_p := (public.invite_collection_member(v_cf, 'wh895p_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_q := (public.invite_collection_member(v_cf, 'wh895q_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_v := (public.invite_collection_member(v_cf, 'wh895v_' || v_sfx) ->> 'membership_id')::uuid;
    m_w := (public.invite_collection_member(v_cf, 'wh895w_' || v_sfx) ->> 'membership_id')::uuid;
    m_vd := (public.invite_collection_member(v_cd, 'wh895v_' || v_sfx) ->> 'membership_id')::uuid;
    m_wd := (public.invite_collection_member(v_cd, 'wh895w_' || v_sfx) ->> 'membership_id')::uuid;
    m_vm := (public.invite_collection_member(v_cm, 'wh895v_' || v_sfx) ->> 'membership_id')::uuid;
    m_wm := (public.invite_collection_member(v_cm, 'wh895w_' || v_sfx) ->> 'membership_id')::uuid;
    perform pg_temp.wh_5895_as(u_b); perform public.respond_collection_invite(m_b, true);
    perform pg_temp.wh_5895_as(u_u); perform public.respond_collection_invite(m_u, true);
    perform pg_temp.wh_5895_as(u_r); perform public.respond_collection_invite(m_r, true);
    perform pg_temp.wh_5895_as(u_v);
    perform public.respond_collection_invite(m_v, true); perform public.respond_collection_invite(m_vd, true);
    perform public.respond_collection_invite(m_vm, true);
    perform pg_temp.wh_5895_as(u_w);
    perform public.respond_collection_invite(m_w, true); perform public.respond_collection_invite(m_wd, true);
    perform public.respond_collection_invite(m_wm, true);
    perform pg_temp.wh_5895_as(u_a); perform public.remove_collection_member(v_cf, m_r);
    perform pg_temp.wh_5895_as(u_o);
    select x.storage_container_id into v_bo from public.create_my_storage_container(gen_random_uuid(), 'BIN O 5895', 'BINDER') x;
    select x.collection_id into v_co from public.create_my_pokedex_collection(gen_random_uuid(), 'CO 5895', array[v_gen], v_bo) x;
    execute 'reset role';
    f_ok  := u_a::text || '/' || v_cf::text || '/' || gen_random_uuid()::text || '.webp';
    f_b2  := u_a::text || '/' || v_cf::text || '/' || gen_random_uuid()::text || '.webp';
    f_u   := u_a::text || '/' || v_cf::text || '/' || gen_random_uuid()::text || '.webp';
    f_own := u_a::text || '/' || v_cf::text || '/' || gen_random_uuid()::text || '.webp';
    res := res || jsonb_build_object('id','F.2','ok',
      (select count(*) from public.collection_membership m where m.collection_id = v_cf and m.status = 'ACTIVE' and m.role = 'EDITOR') = 2
      and exists (select 1 from public.collection_membership m where m.id = m_p and m.status = 'PENDING' and m.role = 'EDITOR')
      and exists (select 1 from public.collection_membership m where m.id = m_q and m.status = 'PENDING' and m.role = 'EDITOR')
      and (select count(*) from public.v1_13_barrier_identity) = 6,
      'detail','fixture: B e U EDITOR ativos de CF; P e Q com convite EDITOR pendente; 6 identidades registradas');

    -- 1. CLOSED ---------------------------------------------------------------------------------
    update public.v1_13_barrier_state set mode = 'CLOSED' where id = 1;
    perform pg_temp.wh_5895_as(u_b);
    n := pg_temp.wh_5895_barrier_count(c_w);
    v_txt := public.collection_cover_editor_folder_ok(f_ok)::text || '/' || public.collection_cover_editor_can_upload(f_ok)::text;
    v_txt2 := (select count(*) from public.get_shared_binder_placeable_cards(v_cf, 96, 0))::text;
    perform pg_temp.wh_5895_as(u_a);
    v_err := pg_temp.wh_5895_try(format('select public.invite_collection_member(%L, %L, %L)', v_cf, 'wh895s_' || v_sfx, 'EDITOR'));
    perform pg_temp.wh_5895_as(u_v);
    s := pg_temp.wh_5895_reads(v_cf, v_cd, v_cm);
    execute 'reset role';
    res := res || jsonb_build_object('id','1.1','ok', n = 29 and v_err = 'CAPABILITY_NOT_ENABLED'
      and v_txt = 'false/false' and v_txt2 = '0' and s = '0/0/0/0/0',
      'detail','CLOSED: as 29 escritas recusadas pela barreira para EDITOR registrado; convite EDITOR recusado; ajudantes do Storage falsos; 5 leituras com zero linhas para VIEWER registrado');

    perform pg_temp.wh_5895_as(u_b);
    v_err := pg_temp.wh_5895_try(format('insert into storage.objects (bucket_id, name, owner_id) values (%L, %L, %L)', 'collection-cover', f_ok, u_b));
    perform pg_temp.wh_5895_as(u_a);
    v_txt := pg_temp.wh_5895_try(format('insert into storage.objects (bucket_id, name, owner_id) values (%L, %L, %L)', 'collection-cover', f_own, u_a));
    execute 'reset role';
    res := res || jsonb_build_object('id','1.2','ok', v_err ~ 'row-level security' and v_txt = 'OK',
      'detail','CLOSED: envio do EDITOR na pasta do titular recusado pela política; envio do titular na própria pasta (5176, V1-12) aceito');

    perform pg_temp.wh_5895_as(u_a);
    m_x := (public.invite_collection_member(v_cf, 'wh895x_' || v_sfx) ->> 'membership_id')::uuid;
    perform pg_temp.wh_5895_as(u_x); perform public.respond_collection_invite(m_x, true);
    perform pg_temp.wh_5895_as(u_v);
    v_j := public.get_shared_collection(v_cf);
    select count(*) into n from jsonb_array_elements(public.get_collections_shared_with_me()) e where (e ->> 'collection_id')::uuid = v_cf;
    perform pg_temp.wh_5895_as(u_b);
    v_txt := public.get_shared_collection(v_cf) ->> 'role';
    execute 'reset role';
    res := res || jsonb_build_object('id','1.3','ok', m_x is not null
      and exists (select 1 from public.collection_membership m where m.id = m_x and m.status = 'ACTIVE' and m.role = 'VIEWER')
      and v_j ->> 'access' = 'VIEWER' and n = 1 and v_txt = 'EDITOR',
      'detail','CLOSED preserva a V1-12: convite VIEWER de 2 argumentos e aceite; leitura da coleção e "compartilhadas comigo"; a 5368 continua devolvendo o papel');

    -- 2. TEST -----------------------------------------------------------------------------------
    update public.v1_13_barrier_state set mode = 'TEST' where id = 1;
    perform pg_temp.wh_5895_as(u_u);
    n := pg_temp.wh_5895_barrier_count(c_w);
    v_txt := public.collection_cover_editor_folder_ok(f_u)::text;
    v_err := pg_temp.wh_5895_try(format('insert into storage.objects (bucket_id, name, owner_id) values (%L, %L, %L)', 'collection-cover', f_u, u_u));
    perform pg_temp.wh_5895_as(u_w);
    s := pg_temp.wh_5895_reads(v_cf, v_cd, v_cm);
    execute 'reset role';
    res := res || jsonb_build_object('id','2.1','ok', n = 29 and v_txt = 'false' and v_err ~ 'row-level security' and s = '0/0/0/0/0',
      'detail','TEST, não registrados com papel válido: EDITOR U recusado pela barreira nas 29 escritas e no Storage; VIEWER W com zero linhas nas 5 leituras');

    perform pg_temp.wh_5895_as(u_b);
    n := pg_temp.wh_5895_barrier_count(c_w);
    v_txt := public.collection_cover_editor_folder_ok(f_b2)::text;
    v_err := pg_temp.wh_5895_try(format('insert into storage.objects (bucket_id, name, owner_id) values (%L, %L, %L)', 'collection-cover', f_b2, u_b));
    execute 'reset role';
    res := res || jsonb_build_object('id','2.2','ok', n = 0 and v_txt = 'true' and v_err = 'OK',
      'detail','TEST, EDITOR registrado: a barreira não recusa nenhuma das 29 escritas (as respostas são do produto); ajudante verdadeiro e envio aceito');

    perform pg_temp.wh_5895_as(u_b);
    v_err := pg_temp.wh_5895_try(format('select count(*) from public.editor_update_collection_metadata(%L, %L, null)', v_cf, 'CF 5895 B'));
    v_txt := '';
    foreach s in array array[u_v::text, u_s::text, u_r::text, u_p::text] loop
      perform pg_temp.wh_5895_as(s::uuid);
      v_txt := v_txt || pg_temp.wh_5895_try(format('select count(*) from public.editor_update_collection_metadata(%L, %L, null)', v_cf, 'CF 5895 X')) || ';';
    end loop;
    execute 'reset role';
    res := res || jsonb_build_object('id','2.3','ok', v_err = 'OK'
      and (select c.name from public.collection c where c.id = v_cf) = 'CF 5895 B'
      and position('CAPABILITY_NOT_ENABLED' in v_txt) = 0 and position('OK;' in v_txt) = 0,
      'detail','TEST: a barreira não mascara a autorização funcional — VIEWER, estranho, removido e pendente, todos registrados, recusados pelo produto (nunca pela barreira); EDITOR registrado grava');

    perform pg_temp.wh_5895_as(u_v); s := pg_temp.wh_5895_reads(v_cf, v_cd, v_cm);
    perform pg_temp.wh_5895_as(u_a);
    select count(*) into n from public.get_shared_pokedex_positions(v_cd, 'ALL', null, 500, 0);
    perform pg_temp.wh_5895_as(u_o);
    select count(*) into n2 from public.get_shared_pokedex_positions(v_co, 'ALL', null, 500, 0);
    execute 'reset role';
    res := res || jsonb_build_object('id','2.4','ok', split_part(s, '/', 1)::integer > 0 and split_part(s, '/', 2)::integer > 0
      and split_part(s, '/', 3) = '1' and n > 0 and n2 = 0,
      'detail','TEST: VIEWER registrado lê Master Set, Pokédex e estado do histórico; titular registrado lê a própria Pokédex; titular não registrado recebe zero linhas');

    perform pg_temp.wh_5895_as(u_o);
    v_err := pg_temp.wh_5895_try(format('select public.invite_collection_member(%L, %L, %L)', v_co, 'wh895t_' || v_sfx, 'EDITOR'))
          || ';' || pg_temp.wh_5895_try(format('select public.invite_collection_member(%L, %L)', v_co, 'wh895t_' || v_sfx));
    execute 'reset role';
    res := res || jsonb_build_object('id','2.5','ok', v_err = 'CAPABILITY_NOT_ENABLED;OK',
      'detail','TEST: titular não registrado não convida EDITOR; convite VIEWER legado continua');

    delete from public.v1_13_barrier_identity where user_id = u_b;
    perform pg_temp.wh_5895_as(u_b);
    v_err := pg_temp.wh_5895_null_call('public.editor_add_binder_page(uuid)');
    execute 'reset role';
    insert into public.v1_13_barrier_identity (user_id, note) values (u_b, 'wh895');
    perform pg_temp.wh_5895_as(u_b);
    v_txt := pg_temp.wh_5895_null_call('public.editor_add_binder_page(uuid)');
    perform pg_temp.wh_5895_as(u_a);
    perform public.set_collection_member_role(v_cf, m_b, 'VIEWER');
    perform pg_temp.wh_5895_as(u_b);
    v_txt2 := pg_temp.wh_5895_try(format('select count(*) from public.editor_update_collection_metadata(%L, %L, null)', v_cf, 'CF 5895 V'));
    perform pg_temp.wh_5895_as(u_a);
    perform public.set_collection_member_role(v_cf, m_b, 'EDITOR');
    execute 'reset role';
    res := res || jsonb_build_object('id','2.6','ok', v_err = 'CAPABILITY_NOT_ENABLED' and v_txt <> 'CAPABILITY_NOT_ENABLED'
      and v_txt2 <> 'OK' and v_txt2 <> 'CAPABILITY_NOT_ENABLED',
      'detail','revogação: retirar do registro fecha na chamada seguinte e recolocar reabre; troca de papel para VIEWER recusa pelo produto (não pela barreira)');

    -- 3. OPEN, configuração ausente, anon, tabelas administrativas, convite aceito em CLOSED -----
    update public.v1_13_barrier_state set mode = 'OPEN' where id = 1;
    perform pg_temp.wh_5895_as(u_u); n := pg_temp.wh_5895_barrier_count(c_w);
    perform pg_temp.wh_5895_as(u_w); s := pg_temp.wh_5895_reads(v_cf, v_cd, v_cm);
    execute 'reset role';
    res := res || jsonb_build_object('id','3.1','ok', n = 0 and split_part(s, '/', 2)::integer > 0,
      'detail','OPEN (estado futuro, só nesta transação): não registrados passam pela barreira e caem na autorização do produto');

    delete from public.v1_13_barrier_state where id = 1;
    perform pg_temp.wh_5895_as(u_b); n := pg_temp.wh_5895_barrier_count(c_w);
    v_txt := public.collection_cover_editor_folder_ok(f_ok)::text;
    perform pg_temp.wh_5895_as(u_v); s := pg_temp.wh_5895_reads(v_cf, v_cd, v_cm);
    execute 'reset role';
    insert into public.v1_13_barrier_state (id, mode) values (1, 'TEST');
    res := res || jsonb_build_object('id','3.2','ok', n = 29 and v_txt = 'false' and s = '0/0/0/0/0',
      'detail','configuração ausente (sem linha de estado): negação total, inclusive para registrados');

    res := res || jsonb_build_object('id','3.3','ok',
      (select count(*) from unnest(c_w || c_r || c_h || array[c_inv] || c_gate) s0(sig)
        where has_function_privilege('anon', to_regprocedure(s0.sig), 'EXECUTE')) = 0,
      'detail','anon sem EXECUTE nas 37 capacidades e na porta');
    perform pg_temp.wh_5895_as(null);
    v_err := pg_temp.wh_5895_try(format('select count(*) from public.get_shared_binder_activity_status(%L)', v_cf));
    execute 'reset role';
    res := res || jsonb_build_object('id','3.4','ok', v_err ~ 'permission denied',
      'detail','sessão anônima recusada pelo privilégio (antes da porta)');

    perform pg_temp.wh_5895_as(u_b);
    v_txt := pg_temp.wh_5895_try('select count(*) from public.v1_13_barrier_state')
      || ';' || pg_temp.wh_5895_try('select count(*) from public.v1_13_barrier_identity')
      || ';' || pg_temp.wh_5895_try(format('insert into public.v1_13_barrier_identity (user_id) values (%L)', u_u))
      || ';' || pg_temp.wh_5895_try('update public.v1_13_barrier_state set mode = ''OPEN''')
      || ';' || pg_temp.wh_5895_try('delete from public.v1_13_barrier_identity')
      || ';' || pg_temp.wh_5895_try('select public.v1_13_capability_open()')
      || ';' || pg_temp.wh_5895_try('select public.v1_13_assert_capability()');
    execute 'reset role';
    res := res || jsonb_build_object('id','3.5','ok',
      (select count(*) from regexp_matches(v_txt, 'permission denied', 'g')) = 7
      and (select s1.mode from public.v1_13_barrier_state s1 where s1.id = 1) = 'TEST'
      and not exists (select 1 from public.v1_13_barrier_identity i where i.user_id = u_u),
      'detail','authenticated não lê, não se inscreve, não muda o modo, não apaga o registro e não executa a porta');

    update public.v1_13_barrier_state set mode = 'CLOSED' where id = 1;
    perform pg_temp.wh_5895_as(u_q);
    v_err := pg_temp.wh_5895_try(format('select public.respond_collection_invite(%L, true)', m_q));
    v_txt := pg_temp.wh_5895_null_call('public.editor_add_binder_page(uuid)');
    v_txt2 := public.get_shared_collection(v_cf) ->> 'access';
    execute 'reset role';
    res := res || jsonb_build_object('id','3.6','ok', v_err = 'OK' and v_txt = 'CAPABILITY_NOT_ENABLED' and v_txt2 = 'VIEWER',
      'detail','convite EDITOR criado em TEST e aceito em CLOSED (5304, V1-12): a participação existe, mas toda capacidade do EDITOR fica fechada; a leitura V1-12 continua no nível VIEWER (5302)');

    execute 'reset role';
    raise exception 'MS895' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MS895' then
      res := res || jsonb_build_object('id','X.1','ok', false, 'detail','erro inesperado: '||sqlstate||' '||sqlerrm);
    end if;
  end;

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_membership), (select count(*) from public.collection_allocation),
               (select count(*) from public.physical_card), (select count(*) from public.card),
               (select count(*) from storage.objects),
               (select count(*) from public.v1_13_barrier_state), (select count(*) from public.v1_13_barrier_identity),
               (select count(*) from public.binder_activity_event)]
    into e_counts;
  res := res || jsonb_build_object('id','99.1','ok', b_counts = e_counts and current_user = session_user
    and (select s1.mode from public.v1_13_barrier_state s1 where s1.id = 1) = 'CLOSED'
    and not exists (select 1 from public.v1_13_barrier_identity),
    'detail','resíduo zero (10 contagens, inclusive Storage e as tabelas da barreira), modo de volta a CLOSED com registro vazio e papel restaurado');

  v_expected := 21;
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
