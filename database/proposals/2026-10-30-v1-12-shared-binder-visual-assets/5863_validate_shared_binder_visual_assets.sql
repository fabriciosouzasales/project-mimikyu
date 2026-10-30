/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5863 - Harness V1-12 SHARED BINDER VISUAL ASSETS (5325–5329)
Versão......: 1.1 (2026-10-30, SECURITY READINESS-01: +SO.1–SO.4 RLS real em
              storage.objects — listagem e escrita; +RM.1 imagem retirada do
              layout; S.4 confere predicado de dono nas políticas de escrita;
              resíduo inclui storage.objects dos dois buckets)
              1.0 (2026-10-30)
Status......: PROPOSTA — NÃO EXECUTADA. Executar só depois de 5325–5329
              aplicadas e com autorização de Fabrício. Não substitui 5861
              (51/51) nem 5862 (33/33), que continuam a evidência de
              5300–5322.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-30

Protocolo: o mesmo da 5861/5862 — um único statement, como dono do banco:

  select * from pg_temp.wh_5863_validate();

  Fixture sintética efêmera desfeita pela sentinela MS863 (exceção
  capturada no bloco interno); 99.1 compara 10 contagens antes/depois.
  Objetos de Storage da fixture: linhas em storage.objects inseridas como
  dono do banco DENTRO da sentinela (sem arquivo físico; desfeitas pelo
  MS863). Com elas a política é provada pela RLS REAL de storage.objects
  no papel de cada leitor — a mesma checagem que a API faz ao assinar URL
  e ao listar (storage.search/list_objects_with_delimiter são SECURITY
  INVOKER). A assinatura HTTP real fica na homologação (H.6).

Fixture (mesma base da 5862):
  Set SHV (K1, K2, K3). A titular; local BIN.
  CO coleção de Set no BIN, fichário 3×3 próprio, com:
     - imagem de bolso IS (caminho P_SLOT) num bolso livre da página 1;
     - mesclagem 1×2 com imagem IR (caminho P_REG) em dois bolsos livres;
     - P_LOOSE: caminho válido na pasta do fichário, NÃO vinculado.
  CX coleção livre no BIN, convidada do fichário de CO; capa enviada
     P_COVER + código 'WH863'; P_OLD = outra capa (não atual).
  B VIEWER ACTIVE de CO e de CX. C convite PENDENTE. D RECUSADO.
  F aceitou e foi REMOVIDO de CO. E estranho. anon.

Seções:
  S   estrutura (definer, search_path, grants, políticas, dono intacto)
  F   fixture
  I   5326 (participante): CO → 2 imagens com posição/recorte; convidada
      CX → nada; titular idem; páginas inválidas
  ST  5329 função de decisão no papel do VIEWER: vinculadas sim; solta,
      inexistente, bucket trocado, capa antiga não
  C   5328 capa: VIEWER sim; estranho e anon (privada) não
  N   negação: C, D, E, F → 5326 P0002 e Storage negado; anon → 42501
  PB  vitrine: CO pública → 5327 e Storage liberados para anon; CX pública
      (convidada) → 5327 vazio mas capa liberada; privatizar → corte
  SO  RLS real de storage.objects: o que cada leitor enxerga/lista
      (exatamente os vinculados autorizados) e escrita/exclusão negadas
  R   revogação: B removido de CO → 5326 P0002 e Storage negado, mesmo
      continuando VIEWER de CX (convidada do mesmo fichário)
  RM  imagem retirada do layout deixa de ser legível na hora
  99  resíduo zero

Gate: GATE PASS com N/N (N = v_expected). Qualquer FAIL → STOP; não
corrigir no LIVE; reportar.
================================================================
*/

create or replace function pg_temp.wh_5863_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
as $fn$
declare
  f_core oid := to_regprocedure('public.collection_binder_shared_images(uuid,integer,integer)');
  f_shr  oid := to_regprocedure('public.get_shared_collection_binder_images(uuid,integer,integer)');
  f_pub  oid := to_regprocedure('public.get_public_collection_binder_images(uuid,integer,integer)');
  f_cov  oid := to_regprocedure('public.get_shared_collection_cover(uuid)');
  f_rd   oid := to_regprocedure('public.shared_visual_asset_readable(text,text)');
  u_a uuid := gen_random_uuid(); u_b uuid := gen_random_uuid(); u_c uuid := gen_random_uuid();
  u_d uuid := gen_random_uuid(); u_e uuid := gen_random_uuid(); u_f uuid := gen_random_uuid();
  v_sfx text := lower(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  v_game uuid; v_pt uuid; v_rar uuid; v_cat uuid; v_std uuid;
  v_exp uuid; v_set uuid; k1 uuid; k2 uuid; k3 uuid; k1s uuid; k2s uuid; k3s uuid;
  v_inv_a uuid; a1 uuid; a2 uuid; x1 uuid;
  v_bin uuid; v_co uuid; v_cx uuid; v_layout uuid; v_page uuid; p record;
  m_b uuid; m_c uuid; m_d uuid; m_f uuid; m_bx uuid;
  v_reg_row int; v_reg_col int; v_slot uuid; v_slot_row int; v_slot_col int; v_region uuid;
  p_slot text; p_reg text; p_loose text; p_cover text; p_old text;
  j jsonb; v_err text; v_txt text; n integer; n2 integer; b1 boolean; b2 boolean; b3 boolean;
  b_counts bigint[]; e_counts bigint[];
  res jsonb := '[]'::jsonb; r jsonb; cnt integer := 0; passes integer := 0;
  v_expected integer := 37;
  v_names text;
begin
  -- S. Estrutura -------------------------------------------------------------------------
  res := res || jsonb_build_object('id','S.1','ok',
    f_core is not null and f_shr is not null and f_pub is not null and f_cov is not null and f_rd is not null
    and (select bool_and(q.prosecdef and q.proconfig @> array['search_path=""']) from pg_proc q where q.oid in (f_core, f_shr, f_pub, f_cov, f_rd)),
    'detail','5325–5329 presentes, definer, search_path vazio');
  res := res || jsonb_build_object('id','S.2','ok',
    not has_function_privilege('anon', f_core, 'EXECUTE') and not has_function_privilege('authenticated', f_core, 'EXECUTE')
    and has_function_privilege('authenticated', f_shr, 'EXECUTE') and not has_function_privilege('anon', f_shr, 'EXECUTE')
    and has_function_privilege('anon', f_pub, 'EXECUTE') and has_function_privilege('authenticated', f_pub, 'EXECUTE')
    and has_function_privilege('anon', f_cov, 'EXECUTE') and has_function_privilege('anon', f_rd, 'EXECUTE')
    and not exists (select 1 from pg_proc q, aclexplode(coalesce(q.proacl, '{}')) a where q.oid in (f_core, f_shr, f_pub, f_cov, f_rd) and a.grantee = 0),
    'detail','núcleo sem EXECUTE; participante só authenticated; vitrine/capa/decisão anon+authenticated; nada para PUBLIC');
  res := res || jsonb_build_object('id','S.3','ok',
    (select count(*) from pg_policies where schemaname = 'storage' and tablename = 'objects'
       and policyname in ('binder_slot_image_select_shared','collection_cover_select_shared')
       and cmd = 'SELECT' and roles @> array['anon','authenticated']::name[] and array_length(roles, 1) = 2
       and qual like '%shared_visual_asset_readable%') = 2
    and not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
       and policyname in ('binder_slot_image_select_shared','collection_cover_select_shared') and cmd <> 'SELECT'),
    'detail','duas políticas SELECT escopadas (anon, authenticated) delegando à função de decisão; nenhuma escrita');
  res := res || jsonb_build_object('id','S.4','ok',
    (select count(*) from pg_policies where schemaname = 'storage' and tablename = 'objects'
       and policyname in ('binder_slot_image_select_own','binder_slot_image_insert_own','binder_slot_image_delete_own',
                          'collection_cover_select_own','collection_cover_insert_own','collection_cover_update_own','collection_cover_delete_own')) = 7
    and (select count(*) from pg_policies where schemaname = 'storage' and tablename = 'objects'
       and (qual like '%binder-slot-image%' or qual like '%collection-cover%' or with_check like '%binder-slot-image%' or with_check like '%collection-cover%')) = 9
    and not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
       and cmd <> 'SELECT'
       and (qual like '%binder-slot-image%' or qual like '%collection-cover%' or with_check like '%binder-slot-image%' or with_check like '%collection-cover%')
       and (coalesce(qual, '') || coalesce(with_check, '')) not like '%auth.uid()%'),
    'detail','7 políticas do dono intactas; total nos dois buckets = 9; toda política de escrita exige a pasta do próprio usuário');
  res := res || jsonb_build_object('id','S.5','ok',
    not exists (select 1 from pg_proc q, unnest(q.proargnames, q.proargmodes) a(name, mode)
                where q.oid in (f_shr, f_pub) and a.mode in ('o','t') and a.name ~* '(_id$|slot|region_id|layout|owner)'),
    'detail','portas sem ids internos (bolso, região, fichário, dono) no retorno');

  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.collection_membership), (select count(*) from public.card),
               (select count(*) from public.collection_layout), (select count(*) from public.collection_layout_slot_image),
               (select count(*) from public.collection_layout_region_image),
               (select count(*) from storage.objects where bucket_id in ('binder-slot-image','collection-cover'))]
    into b_counts;

  begin
    -- F. Fixture -----------------------------------------------------------------------------
    select g.id into v_game from public.game g where g.code = 'POKEMON';
    select l.id into v_pt from public.language l where l.code = 'pt-BR';
    select t.id into v_std from public.card_variant_type t where t.game_id = v_game and t.code = 'STANDARD';
    select c0.rarity_id, c0.category_id into v_rar, v_cat
    from public.card c0 join public.card_set cs0 on cs0.id = c0.card_set_id
    join public.expansion e0 on e0.id = cs0.expansion_id where e0.game_id = v_game limit 1;
    if v_game is null or v_pt is null or v_std is null or v_rar is null then
      res := res || jsonb_build_object('id','F.0','ok', false, 'detail','pré-requisitos de catálogo ausentes');
      raise exception 'MS863' using errcode = 'P0001';
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
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k2, v_std, 1, true) returning id into k2s;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k3, v_std, 1, true) returning id into k3s;

    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    select x.id, 'authenticated', 'authenticated', x.u || '@example.invalid', jsonb_build_object('username', x.u, 'display_name', 'WH 5863 ' || x.t), now(), now()
    from (values (u_a, 'wh863a_' || v_sfx, 'A'), (u_b, 'wh863b_' || v_sfx, 'B'), (u_c, 'wh863c_' || v_sfx, 'C'),
                 (u_d, 'wh863d_' || v_sfx, 'D'), (u_e, 'wh863e_' || v_sfx, 'E'), (u_f, 'wh863f_' || v_sfx, 'F')) x(id, u, t);
    select i.id into v_inv_a from public.inventory i where i.owner_user_id = u_a;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (k1s, v_pt, v_inv_a) returning id into a1;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (k2s, v_pt, v_inv_a) returning id into a2;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (k1s, v_pt, v_inv_a) returning id into x1;

    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select x.storage_container_id into v_bin from public.create_my_storage_container(gen_random_uuid(), 'BIN 5863', 'BINDER') x;
    select x.collection_id into v_co from public.create_my_card_set_collection(gen_random_uuid(), v_set, 'CO 5863', v_bin) x;
    select x.collection_id into v_cx from public.create_my_free_collection(gen_random_uuid(), 'CX 5863', v_bin) x;
    perform public.allocate_physical_cards_to_collection(v_co, array[a1, a2]);
    perform public.allocate_physical_cards_to_collection(v_cx, array[x1]);
    select * into p from public.preview_my_collection_binder(v_co, 3, 3, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_co, 3, 3, 'PRINCIPAL_ONLY', p.plan_token);
    execute 'reset role';
    select l.id into v_layout from public.collection_layout l where l.collection_id = v_co;
    execute 'set local role authenticated';
    perform public.attach_my_collection_to_binder(v_cx, v_layout);
    m_b  := (public.invite_collection_member(v_co, 'wh863b_' || v_sfx) ->> 'membership_id')::uuid;
    m_c  := (public.invite_collection_member(v_co, 'wh863c_' || v_sfx) ->> 'membership_id')::uuid;
    m_d  := (public.invite_collection_member(v_co, 'wh863d_' || v_sfx) ->> 'membership_id')::uuid;
    m_f  := (public.invite_collection_member(v_co, 'wh863f_' || v_sfx) ->> 'membership_id')::uuid;
    m_bx := (public.invite_collection_member(v_cx, 'wh863b_' || v_sfx) ->> 'membership_id')::uuid;
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

    -- Personalizações (privilegiado; gatilhos de integridade 5232/5239 continuam valendo).
    select pg.id into v_page from public.collection_layout_page pg where pg.layout_id = v_layout and pg.page_number = 1;
    select s1.row_index, s1.column_index into v_reg_row, v_reg_col
    from public.collection_layout_slot s1
    join public.collection_layout_slot s2 on s2.page_id = s1.page_id and s2.row_index = s1.row_index and s2.column_index = s1.column_index + 1
    where s1.page_id = v_page
      and not exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id in (s1.id, s2.id))
      and not exists (select 1 from public.collection_layout_slot_expected_content e where e.slot_id in (s1.id, s2.id))
      and not s1.locked and not s2.locked
    order by s1.row_index desc, s1.column_index limit 1;
    insert into public.collection_layout_region (page_id, top_row, left_column, height, width)
    values (v_page, v_reg_row, v_reg_col, 1, 2) returning id into v_region;
    p_reg   := u_a || '/' || v_layout || '/' || gen_random_uuid() || '.webp';
    insert into public.collection_layout_region_image (region_id, owner_user_id, storage_path, focal_x, focal_y)
    values (v_region, u_a, p_reg, 30, 70);
    select s.id, s.row_index, s.column_index into v_slot, v_slot_row, v_slot_col
    from public.collection_layout_slot s
    where s.page_id = v_page and not s.locked
      and not (s.row_index = v_reg_row and s.column_index between v_reg_col and v_reg_col + 1)
      and not exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = s.id)
      and not exists (select 1 from public.collection_layout_slot_expected_content e where e.slot_id = s.id)
    order by s.row_index desc, s.column_index desc limit 1;
    p_slot  := u_a || '/' || v_layout || '/' || gen_random_uuid() || '.webp';
    insert into public.collection_layout_slot_image (slot_id, owner_user_id, storage_path, focal_y)
    values (v_slot, u_a, p_slot, 20);
    p_loose := u_a || '/' || v_layout || '/' || gen_random_uuid() || '.webp';
    p_cover := u_a || '/' || v_cx || '/' || gen_random_uuid() || '.webp';
    p_old   := u_a || '/' || v_cx || '/' || gen_random_uuid() || '.webp';
    update public.collection set cover_logo_path = p_cover, cover_code = 'WH863' where id = v_cx;
    -- Objetos de Storage da fixture (só linhas; desfeitas pela sentinela).
    insert into storage.objects (bucket_id, name, metadata) values
      ('binder-slot-image', p_slot,  '{"mimetype":"image/webp"}'),
      ('binder-slot-image', p_reg,   '{"mimetype":"image/webp"}'),
      ('binder-slot-image', p_loose, '{"mimetype":"image/webp"}'),
      ('collection-cover',  p_cover, '{"mimetype":"image/webp"}'),
      ('collection-cover',  p_old,   '{"mimetype":"image/webp"}');

    res := res || jsonb_build_object('id','F.1','ok',
      v_co is not null and v_cx is not null and v_layout is not null and v_region is not null and v_slot is not null
      and exists (select 1 from public.collection_layout_guest g where g.layout_id = v_layout and g.collection_id = v_cx)
      and (select m.status from public.collection_membership m where m.id = m_b) = 'ACTIVE'
      and (select m.status from public.collection_membership m where m.id = m_bx) = 'ACTIVE'
      and (select m.status from public.collection_membership m where m.id = m_c) = 'PENDING'
      and (select m.status from public.collection_membership m where m.id = m_d) = 'DECLINED'
      and not exists (select 1 from public.collection_membership m where m.id = m_f),
      'detail','CO dona com imagem de bolso (' || v_slot_row || ',' || v_slot_col || ') e mesclagem (' || v_reg_row || ',' || v_reg_col || ' 1×2); CX convidada com capa; B ativo em CO e CX; C pendente; D recusado; F removido');

    -- I. Porta do participante (5326) --------------------------------------------------------
    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select string_agg(x.page_number || ':' || x.row_index || ':' || x.column_index || ':' || x.height || 'x' || x.width || ':' || x.is_region || ':' || x.focal_x || '/' || x.focal_y, ',' order by x.row_index, x.column_index),
           count(*) filter (where x.storage_path in (p_slot, p_reg))
      into v_txt, n
      from public.get_shared_collection_binder_images(v_co, 1, 4) x;
    res := res || jsonb_build_object('id','I.1','ok', n = 2
      and v_txt like '%1:' || v_slot_row || ':' || v_slot_col || ':1x1:false:50/20%'
      and v_txt like '%1:' || v_reg_row || ':' || v_reg_col || ':1x2:true:30/70%',
      'detail','VIEWER em CO (dona): ' || coalesce(v_txt, '(vazio)') || ' — bolso e mesclagem com posição, recorte e enquadramento');
    select count(*) into n from public.get_shared_collection_binder_images(v_cx, 1, 4);
    res := res || jsonb_build_object('id','I.2','ok', n = 0, 'detail','VIEWER em CX (convidada do mesmo fichário): ' || n || ' imagens — sem propriedade determinável, nada atravessa');
    select count(*) into n from public.get_shared_collection_binder_images(v_co, 2, 4);
    v_err := null; begin perform count(*) from public.get_shared_collection_binder_images(v_co, 1, 5); exception when others then v_err := sqlstate || ' ' || sqlerrm; end;
    res := res || jsonb_build_object('id','I.3','ok', n = 0 and v_err like '22023%INVALID_PAGE%', 'detail','páginas fora do intervalo → 0; lote de 5 → ' || coalesce(v_err, 'aceitou'));
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select count(*) into n from public.get_shared_collection_binder_images(v_co, 1, 4);
    select count(*) into n2 from public.get_shared_collection_binder_images(v_cx, 1, 4);
    execute 'reset role';
    res := res || jsonb_build_object('id','I.4','ok', n = 2 and n2 = 0, 'detail','titular pela mesma porta: CO ' || n || ', CX ' || n2 || ' (mesma regra; o titular segue usando 5234/5241 no próprio fichário)');

    -- ST. Decisão de Storage no papel do VIEWER (5329) -----------------------------------------
    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    res := res || jsonb_build_object('id','ST.1','ok',
      public.shared_visual_asset_readable('binder-slot-image', p_slot) and public.shared_visual_asset_readable('binder-slot-image', p_reg),
      'detail','VIEWER lê imagem de bolso e de mesclagem vinculadas ao fichário da coleção autorizada');
    res := res || jsonb_build_object('id','ST.2','ok',
      not public.shared_visual_asset_readable('binder-slot-image', p_loose)
      and not public.shared_visual_asset_readable('binder-slot-image', u_a || '/' || gen_random_uuid() || '/' || gen_random_uuid() || '.webp')
      and not public.shared_visual_asset_readable('binder-slot-image', 'qualquer/coisa.webp'),
      'detail','arquivo solto na pasta do fichário, caminho inexistente e lixo → negados');
    res := res || jsonb_build_object('id','ST.3','ok',
      not public.shared_visual_asset_readable('collection-cover', p_slot)
      and not public.shared_visual_asset_readable('binder-slot-image', p_cover)
      and not public.shared_visual_asset_readable('card-set-logo', p_slot),
      'detail','bucket trocado → negado (decisão por bucket)');
    res := res || jsonb_build_object('id','ST.4','ok',
      public.shared_visual_asset_readable('collection-cover', p_cover)
      and not public.shared_visual_asset_readable('collection-cover', p_old),
      'detail','capa atual da coleção autorizada (CX) liberada; outra capa da mesma pasta (não atual) negada');

    -- SO. RLS real de storage.objects no papel do VIEWER --------------------------------------
    select string_agg(o.name, ',' order by o.name) into v_names
    from storage.objects o
    where o.bucket_id in ('binder-slot-image','collection-cover') and o.name like u_a || '/%';
    res := res || jsonb_build_object('id','SO.1','ok',
      v_names = (select string_agg(x, ',' order by x) from unnest(array[p_slot, p_reg, p_cover]) x),
      'detail','VIEWER lista/lê na pasta da titular exatamente bolso + mesclagem + capa atual (3); solto e capa antiga invisíveis');
    begin
      update storage.objects set metadata = '{"x":1}' where bucket_id = 'binder-slot-image' and name in (p_slot, p_reg);
      get diagnostics n = row_count;
      perform set_config('storage.allow_delete_query', 'true', true);
      delete from storage.objects where bucket_id in ('binder-slot-image','collection-cover') and name like u_a || '/%';
      get diagnostics n2 = row_count;
      perform set_config('storage.allow_delete_query', 'false', true);
      v_err := null;
      begin
        insert into storage.objects (bucket_id, name) values ('binder-slot-image', u_a || '/' || v_layout || '/' || gen_random_uuid() || '.webp');
      exception when others then v_err := sqlstate;
      end;
    end;
    res := res || jsonb_build_object('id','SO.3','ok', n = 0 and n2 = 0 and v_err = '42501',
      'detail','VIEWER: UPDATE ' || n || ' linhas, DELETE ' || n2 || ' linhas (trava de exclusão desligada para provar a RLS), INSERT na pasta da titular = ' || coalesce(v_err, 'aceito'));

    -- C. Capa (5328) -----------------------------------------------------------------------------
    select count(*) filter (where x.cover_logo_path = p_cover and x.cover_code = 'WH863') into n from public.get_shared_collection_cover(v_cx) x;
    select count(*) into n2 from public.get_shared_collection_cover(v_co) x;
    execute 'reset role';
    res := res || jsonb_build_object('id','C.1','ok', n = 1 and n2 = 1, 'detail','VIEWER: capa e código da CX (' || n || '); CO responde a própria linha (' || n2 || ')');
    perform set_config('request.jwt.claim.sub', u_e::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_e, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select count(*) into n from public.get_shared_collection_cover(v_cx);
    b1 := public.shared_visual_asset_readable('collection-cover', p_cover);
    execute 'reset role';
    res := res || jsonb_build_object('id','C.2','ok', n = 0 and not b1, 'detail','estranho: capa 0 linhas e arquivo negado');
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    select count(*) into n from public.get_shared_collection_cover(v_cx);
    b1 := public.shared_visual_asset_readable('collection-cover', p_cover);
    b2 := public.shared_visual_asset_readable('binder-slot-image', p_slot);
    execute 'reset role';
    res := res || jsonb_build_object('id','C.3','ok', n = 0 and not b1 and not b2, 'detail','anon com coleções privadas: capa 0 linhas, capa e imagem negadas');
    perform set_config('request.jwt.claim.sub', u_e::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_e, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select count(*) into n from storage.objects o where o.bucket_id in ('binder-slot-image','collection-cover') and o.name like u_a || '/%';
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    select count(*) into n2 from storage.objects o where o.bucket_id in ('binder-slot-image','collection-cover') and o.name like u_a || '/%';
    execute 'reset role';
    res := res || jsonb_build_object('id','SO.2','ok', n = 0 and n2 = 0, 'detail','estranho lista ' || n || ' e anon lista ' || n2 || ' objetos na pasta da titular (coleções privadas)');

    -- N. Negação ----------------------------------------------------------------------------------
    for p in select * from (values ('C pendente', u_c), ('D recusado', u_d), ('E estranho', u_e), ('F removido', u_f)) v(label, uid) loop
      perform set_config('request.jwt.claim.sub', p.uid::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', p.uid, 'role', 'authenticated')::text, true);
      execute 'set local role authenticated';
      v_err := null; begin perform count(*) from public.get_shared_collection_binder_images(v_co, 1, 4); exception when others then v_err := sqlstate; end;
      b1 := public.shared_visual_asset_readable('binder-slot-image', p_slot);
      b2 := public.shared_visual_asset_readable('binder-slot-image', p_reg);
      execute 'reset role';
      res := res || jsonb_build_object('id','N.' || p.label,'ok', v_err = 'P0002' and not b1 and not b2,
        'detail', p.label || ': 5326 = ' || coalesce(v_err, 'executou') || '; Storage bolso/mesclagem = ' || b1 || '/' || b2);
    end loop;
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    v_err := null; begin perform count(*) from public.get_shared_collection_binder_images(v_co, 1, 4); exception when others then v_err := sqlstate; end;
    res := res || jsonb_build_object('id','N.anon 5326','ok', v_err = '42501', 'detail', coalesce(v_err, 'executou'));
    v_err := null; begin perform count(*) from public.get_public_collection_binder_images(v_co, 1, 4); exception when others then v_err := sqlstate; end;
    res := res || jsonb_build_object('id','N.anon 5327 privada','ok', v_err = 'P0002', 'detail', coalesce(v_err, 'executou'));
    v_err := null; begin perform count(*) from public.collection_binder_shared_images(v_co, 1, 4); exception when others then v_err := sqlstate; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','N.anon núcleo','ok', v_err = '42501', 'detail','5325 interna: ' || coalesce(v_err, 'executou'));
    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    v_err := null; begin perform count(*) from public.collection_binder_shared_images(v_co, 1, 4); exception when others then v_err := sqlstate; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','N.auth núcleo','ok', v_err = '42501', 'detail','5325 interna para authenticated: ' || coalesce(v_err, 'executou'));

    -- PB. Vitrine pública ---------------------------------------------------------------------------
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.set_collection_visibility(v_co, 'PUBLIC');
    perform public.set_collection_visibility(v_cx, 'PUBLIC');
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    select count(*) into n from public.get_public_collection_binder_images(v_co, 1, 4) x where x.storage_path in (p_slot, p_reg);
    b1 := public.shared_visual_asset_readable('binder-slot-image', p_slot);
    b2 := public.shared_visual_asset_readable('binder-slot-image', p_reg);
    b3 := public.shared_visual_asset_readable('binder-slot-image', p_loose);
    res := res || jsonb_build_object('id','PB.1','ok', n = 2 and b1 and b2 and not b3,
      'detail','CO pública: visitante recebe as 2 imagens e pode assiná-las; arquivo solto continua negado');
    select count(*) into n from public.get_public_collection_binder_images(v_cx, 1, 4);
    select count(*) filter (where x.cover_logo_path = p_cover) into n2 from public.get_shared_collection_cover(v_cx) x;
    b1 := public.shared_visual_asset_readable('collection-cover', p_cover);
    res := res || jsonb_build_object('id','PB.2','ok', n = 0 and n2 = 1 and b1,
      'detail','CX pública (convidada): 0 imagens do fichário alheio; capa própria liberada');
    select string_agg(o.name, ',' order by o.name) into v_names
    from storage.objects o
    where o.bucket_id in ('binder-slot-image','collection-cover') and o.name like u_a || '/%';
    res := res || jsonb_build_object('id','SO.4','ok',
      v_names = (select string_agg(x, ',' order by x) from unnest(array[p_slot, p_reg, p_cover]) x),
      'detail','visitante (CO e CX públicas) lista exatamente bolso + mesclagem + capa atual; solto e capa antiga invisíveis');
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.set_collection_visibility(v_co, 'PRIVATE');
    perform public.set_collection_visibility(v_cx, 'PRIVATE');
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    v_err := null; begin perform count(*) from public.get_public_collection_binder_images(v_co, 1, 4); exception when others then v_err := sqlstate; end;
    b1 := public.shared_visual_asset_readable('binder-slot-image', p_slot);
    b2 := public.shared_visual_asset_readable('collection-cover', p_cover);
    execute 'reset role';
    res := res || jsonb_build_object('id','PB.3','ok', v_err = 'P0002' and not b1 and not b2,
      'detail','despublicar: 5327 = ' || coalesce(v_err, 'executou') || '; novas assinaturas negadas na hora');

    -- PB.4 troca de capa: a antiga deixa de ser legível --------------------------------------------
    update public.collection set cover_logo_path = p_old where id = v_cx;
    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    b1 := public.shared_visual_asset_readable('collection-cover', p_cover);
    b2 := public.shared_visual_asset_readable('collection-cover', p_old);
    execute 'reset role';
    res := res || jsonb_build_object('id','PB.4','ok', not b1 and b2, 'detail','capa trocada: arquivo anterior negado, novo liberado ao VIEWER');

    -- R. Revogação ------------------------------------------------------------------------------------
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.remove_collection_member(v_co, m_b);
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    v_err := null; begin perform count(*) from public.get_shared_collection_binder_images(v_co, 1, 4); exception when others then v_err := sqlstate; end;
    b1 := public.shared_visual_asset_readable('binder-slot-image', p_slot);
    b2 := public.shared_visual_asset_readable('binder-slot-image', p_reg);
    select count(*) into n from public.get_shared_collection_binder_images(v_cx, 1, 4);
    b3 := public.shared_visual_asset_readable('collection-cover', p_old);
    execute 'reset role';
    res := res || jsonb_build_object('id','R.1','ok', v_err = 'P0002' and not b1 and not b2,
      'detail','B removido de CO: 5326 = ' || coalesce(v_err, 'executou') || '; Storage bolso/mesclagem negados na mesma transação');
    res := res || jsonb_build_object('id','R.2','ok', n = 0 and b3,
      'detail','B segue VIEWER de CX (convidada do MESMO fichário): continua sem imagens do fichário (' || n || ') e mantém só a capa da CX');

    -- RM. Imagem retirada do layout -------------------------------------------------------------
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.set_collection_visibility(v_co, 'PUBLIC');
    execute 'reset role';
    delete from public.collection_layout_region_image where region_id = v_region;
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    b1 := public.shared_visual_asset_readable('binder-slot-image', p_reg);
    b2 := public.shared_visual_asset_readable('binder-slot-image', p_slot);
    select count(*) into n from storage.objects o where o.bucket_id = 'binder-slot-image' and o.name = p_reg;
    select count(*) into n2 from public.get_public_collection_binder_images(v_co, 1, 4);
    execute 'reset role';
    res := res || jsonb_build_object('id','RM.1','ok', not b1 and b2 and n = 0 and n2 = 1,
      'detail','mesclagem retirada (CO pública): arquivo dela negado e invisível; imagem de bolso restante segue liberada; 5327 = ' || n2 || ' imagem');

    raise exception 'MS863' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MS863' then
      res := res || jsonb_build_object('id','X.1','ok', false, 'detail','erro inesperado: ' || sqlstate || ' ' || sqlerrm);
    end if;
  end;

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.collection_membership), (select count(*) from public.card),
               (select count(*) from public.collection_layout), (select count(*) from public.collection_layout_slot_image),
               (select count(*) from public.collection_layout_region_image),
               (select count(*) from storage.objects where bucket_id in ('binder-slot-image','collection-cover'))]
    into e_counts;
  res := res || jsonb_build_object('id','99.1','ok', b_counts = e_counts and current_user = session_user,
    'detail','resíduo zero (10 contagens) e papel restaurado');

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

-- Executar (uma única vez, depois de 5325–5329, com autorização):
-- select * from pg_temp.wh_5863_validate();
