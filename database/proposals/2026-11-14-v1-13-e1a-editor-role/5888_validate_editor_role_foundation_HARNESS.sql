/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5888 - Harness V1-13 · E1-A (5366–5370): papel EDITOR, convite
              com papel, troca de papel, papel real nas leituras,
              compatibilidade VIEWER/EDITOR, privacidade, resíduo zero
Versão......: 1.0 (2026-11-14); cabeçalho revisado em 2026-11-15
              (`V1-13 / E1-A | VALIDATION PROTOCOL HARDENING-02`): só o
              contexto de execução mudou, nenhuma verificação mudou.
Status......: PROPOSTA — NÃO EXECUTADA. Prova DINÂMICA da E1-A. Sem ambiente
              isolado (C-244 revisada em 2026-11-15): executar SOMENTE sob o
              protocolo controlado de VALIDATION-STRATEGY-E1A.md (P1 antes da
              aplicação, P3 depois), com autorização específica do proprietário
              para aquela execução. Sempre dentro de transação explícita
              READ WRITE terminada em erro/ROLLBACK, por psql, em conexão
              direta única. Nunca pelo SQL Editor, apply_migration, pooler em
              modo transação ou psql -1. Nunca confirmar a fixture.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-14

Protocolo (o mesmo da 5861): uma única chamada, usuários efêmeros
A (titular), B (participante), C (estranho) e D (segundo convidado),
catálogo SINTÉTICO mínimo, sentinela MS888 desfaz a fixture por
subtransação; 99.1 prova resíduo zero. A subtransação NÃO é a garantia de
reversão: as funções pg_temp e o SET LOCAL ROLE vivem na transação externa,
que o protocolo sempre encerra por erro ou ROLLBACK (VALIDATION-STRATEGY-E1A.md §2).
Este arquivo não contém BEGIN/COMMIT nem é um comando pronto para execução.

  -- GATE esperado: 54/54 PASS

Fixture (tudo de A pelas RPCs canônicas):
  CO  coleção livre (local BIN) com a1 (carta K1) e fichário 3×3 → compartilhada
  CX  outra coleção livre de A (C é convidado PENDING; B nunca participa)

Seções:
  0  estrutura: CHECK, interna sem EXECUTE, sobrecarga única do convite,
     troca de papel com ACL canônica, 5302/5308 intocadas, leituras com ACL
  1  convite: padrão VIEWER (chamada de 2 argumentos, igual ao frontend),
     EDITOR explícito, papel inválido, NULL, normalização, autoconvite
  2  convite pendente: mesmo papel → ALREADY_PENDING; outro papel →
     INVITE_PENDING_ROLE_IMMUTABLE sem alterar nada; troca recusada; caixa
  3  leitura: EDITOR lê exatamente o mesmo que o VIEWER (cabeçalho, galeria,
     fichário, páginas, imagens, capa, posições, lista); access continua
     'VIEWER'; role = 'EDITOR'; 5302 = VIEWER; PUBLIC não é papel
  4  troca de papel: idempotência, EDITOR↔VIEWER, efeito imediato, ids
     cruzados, inexistente, papel inválido/OWNER/NULL, ALREADY_MEMBER
  5  segurança: autopromoção, EDITOR promovendo outro, EDITOR convidando,
     painel do titular negado, estranho, anon, recusado, recusado + outro
     papel = id novo, aba antiga, removido, saiu
  6  privacidade: chaves de retorno = contrato V1-12 + 'role'; sem e-mail,
     username ou ids
  7  sem escrita: EDITOR continua sem escrita (E1-B não aplicada)
  99 resíduo zero e papel restaurado

Limitações declaradas:
  L1 SET LOCAL ROLE prova o banco, não o JWT do PostgREST. A resolução de
     sobrecarga pelo PostgREST é coberta estaticamente (0.3: uma única
     assinatura) e na homologação funcional (convite pela tela atual).
  L2 Concorrência real (troca de papel × escrita do EDITOR, duas sessões)
     pertence à E1-B/E1-E (S8/S10).
  L3 Depende de catálogo mínimo (jogo POKEMON, pt-BR, variante STANDARD e
     uma carta com raridade/categoria) e das RPCs de fixture vigentes
     (5175, 5216, 5046, 5224, 5295). Sem eles → F.1 FAIL.
================================================================
*/

create or replace function pg_temp.wh_5888_as(p_user uuid)
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

create or replace function pg_temp.wh_5888_claims(p_user uuid)
returns void language plpgsql volatile as $cl$
begin
  -- Só troca a identidade (auth.uid()); o papel de banco continua o da sessão (dono).
  if p_user is null then
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
  else
    perform set_config('request.jwt.claim.sub', p_user::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  end if;
end;
$cl$;

create or replace function pg_temp.wh_5888_reads(p_collection uuid)
returns jsonb language sql volatile as $rd$
  -- Tudo o que um participante lê da coleção, sem a chave 'role' (que é a única diferença esperada).
  select jsonb_build_object(
    'hdr', public.get_shared_collection(p_collection) - 'role',
    'crd', (select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text), '[]'::jsonb) from public.get_shared_collection_cards(p_collection, 48, 0) x),
    'bh',  public.get_shared_collection_binder(p_collection),
    'bp',  (select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text), '[]'::jsonb) from public.get_shared_collection_binder_pages(p_collection, 1, 4) x),
    'img', (select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text), '[]'::jsonb) from public.get_shared_collection_binder_images(p_collection, 1, 4) x),
    'cov', (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from public.get_shared_collection_cover(p_collection) x),
    'pos', (select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text), '[]'::jsonb) from public.get_shared_collection_positions(p_collection, 'ALL', 200, 0) x),
    'swm', (select coalesce(jsonb_agg(e - 'role'), '[]'::jsonb) from jsonb_array_elements(public.get_collections_shared_with_me()) e));
$rd$;

create or replace function pg_temp.wh_5888_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  f_inv  oid := to_regprocedure('public.invite_collection_member(uuid, text, text)');
  f_old  oid := to_regprocedure('public.invite_collection_member(uuid, text)');
  f_set  oid := to_regprocedure('public.set_collection_member_role(uuid, uuid, text)');
  f_mr   oid := to_regprocedure('public.collection_member_role(uuid)');
  f_rol  oid := to_regprocedure('public.collection_share_role(uuid)');
  f_box  oid := to_regprocedure('public.get_my_collection_invites()');
  f_swm  oid := to_regprocedure('public.get_collections_shared_with_me()');
  f_get  oid := to_regprocedure('public.get_shared_collection(uuid)');
  f_shr  oid := to_regprocedure('public.get_my_collection_sharing(uuid)');
  hdr_allowed text[] := array['collection_id','name','description','mode','completion_policy','lifecycle_status',
    'visibility','cover_finish','card_set_code','card_set_name','card_set_logo_path','owner_display_name',
    'access','membership_id','copies_count','total_positions','satisfied_positions','progress_percentage','is_complete','role'];
  swm_allowed text[] := array['collection_id','name','mode','completion_policy','lifecycle_status','cover_finish',
    'card_set_code','card_set_name','owner_display_name','accepted_at','copies_count','total_positions',
    'satisfied_positions','progress_percentage','is_complete','role'];
  box_allowed text[] := array['membership_id','role','collection_id','collection_name','mode','completion_policy',
    'card_set_name','owner_display_name','owner_username','invited_at'];
  inv_allowed text[] := array['outcome','membership_id','username','display_name','status','role'];
  u_a uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  u_c uuid := gen_random_uuid(); u_d uuid := gen_random_uuid();
  v_sfx text := lower(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  n_a text; n_b text; n_c text; n_d text;
  v_game uuid; v_pt uuid; v_rar uuid; v_cat uuid; v_std uuid; v_exp uuid; v_set uuid; k1 uuid; k1s uuid;
  v_inv_a uuid; a1 uuid; v_bin uuid; v_co uuid; v_cx uuid; m_b uuid; m_d uuid; m_d2 uuid;
  p record; j jsonb; j2 jsonb; v_err text; v_ok boolean; n integer;
  r_viewer jsonb; r_editor jsonb;
  b_counts bigint[]; e_counts bigint[];
  res jsonb := '[]'::jsonb; r jsonb; cnt integer := 0; passes integer := 0;
  v_expected integer := 54;
begin
  -- 0. Estrutura ---------------------------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    (select pg_get_constraintdef(k.oid) from pg_constraint k
      where k.conrelid = 'public.collection_membership'::regclass and k.conname = 'chk_collection_membership_role')
      = 'CHECK ((role = ANY (ARRAY[''VIEWER''::text, ''EDITOR''::text])))'
    and (select column_default from information_schema.columns where table_schema='public'
          and table_name='collection_membership' and column_name='role') = '''VIEWER''::text'
    and (select c2.relrowsecurity from pg_class c2 where c2.oid = 'public.collection_membership'::regclass)
    and not exists (select 1 from pg_policy pl where pl.polrelid = 'public.collection_membership'::regclass)
    and not has_table_privilege('authenticated', 'public.collection_membership', 'SELECT,INSERT,UPDATE,DELETE')
    and not has_table_privilege('anon', 'public.collection_membership', 'SELECT,INSERT,UPDATE,DELETE'),
    'detail','5366: papel VIEWER|EDITOR, padrão VIEWER, RLS sem política, sem privilégio de tabela');
  res := res || jsonb_build_object('id','0.2','ok',
    f_mr is not null
    and coalesce((select q.prosecdef and q.proconfig = array['search_path=""'] and q.provolatile = 's' from pg_proc q where q.oid = f_mr), false)
    and not has_function_privilege('authenticated', f_mr, 'EXECUTE') and not has_function_privilege('anon', f_mr, 'EXECUTE'),
    'detail','5367: collection_member_role interna (definer STABLE, search_path vazio, sem EXECUTE para API)');
  res := res || jsonb_build_object('id','0.3','ok',
    f_inv is not null and f_old is null
    and (select count(*) from pg_proc q join pg_namespace s on s.oid = q.pronamespace
          where s.nspname = 'public' and q.proname = 'invite_collection_member') = 1
    and coalesce((select q.prosecdef and q.proconfig = array['search_path=""'] and q.pronargdefaults = 1 from pg_proc q where q.oid = f_inv), false)
    and has_function_privilege('authenticated', f_inv, 'EXECUTE') and not has_function_privilege('anon', f_inv, 'EXECUTE'),
    'detail','5369: uma única sobrecarga (uuid, text, text DEFAULT), antiga removida, só authenticated');
  res := res || jsonb_build_object('id','0.4','ok',
    f_set is not null
    and coalesce((select q.prosecdef and q.proconfig = array['search_path=""'] from pg_proc q where q.oid = f_set), false)
    and has_function_privilege('authenticated', f_set, 'EXECUTE') and not has_function_privilege('anon', f_set, 'EXECUTE'),
    'detail','5370: set_collection_member_role definer, search_path vazio, só authenticated');
  res := res || jsonb_build_object('id','0.5','ok',
    (select md5(q.prosrc) from pg_proc q where q.oid = f_rol) = 'efdb495b5b703e9f093eb0f49a1d0a5d'
    and not has_function_privilege('authenticated', f_rol, 'EXECUTE')
    and (select md5(q.prosrc) from pg_proc q where q.oid = f_shr) = 'e36aa9c675f6b8097b6a43292b62603f',
    'detail','5302 (nível de leitura) e 5308 (painel do titular) intocadas (md5 = canônica V1-12)');
  res := res || jsonb_build_object('id','0.6','ok',
    coalesce((select bool_and(q.prosecdef and q.proconfig = array['search_path=""']
                     and has_function_privilege('authenticated', q.oid, 'EXECUTE')
                     and not has_function_privilege('anon', q.oid, 'EXECUTE'))
       from pg_proc q where q.oid in (f_box, f_swm, f_get)), false),
    'detail','5368: leituras alteradas mantêm definer, search_path vazio e ACL');

  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.collection_membership), (select count(*) from public.card)]
    into b_counts;

  begin
    -- F. Catálogo sintético, usuários e fixture --------------------------------------
    select g.id into v_game from public.game g where g.code = 'POKEMON';
    select l.id into v_pt from public.language l where l.code = 'pt-BR';
    select t.id into v_std from public.card_variant_type t where t.game_id = v_game and t.code = 'STANDARD';
    select c0.rarity_id, c0.category_id into v_rar, v_cat
    from public.card c0 join public.card_set cs0 on cs0.id = c0.card_set_id
    join public.expansion e0 on e0.id = cs0.expansion_id where e0.game_id = v_game limit 1;
    if v_game is null or v_pt is null or v_std is null or v_rar is null then
      res := res || jsonb_build_object('id','F.1','ok', false, 'detail','pré-requisitos de catálogo ausentes');
      raise exception 'MS888' using errcode = 'P0001';
    end if;
    insert into public.expansion (game_id, code, name, release_order)
    values (v_game, 'EDR_' || upper(v_sfx), 'EDR Harness ' || v_sfx,
            (select coalesce(max(x.release_order), 0) + 1000 from public.expansion x where x.game_id = v_game))
    returning id into v_exp;
    insert into public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_exp, 'EDR' || upper(v_sfx), 'EDR Set ' || v_sfx, 'REGULAR', 1, 1, 1) returning id into v_set;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '1', 1, 'EDR K1', true) returning id into k1;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k1, v_std, 1, true) returning id into k1s;

    n_a := 'wh888a_' || v_sfx; n_b := 'wh888b_' || v_sfx; n_c := 'wh888c_' || v_sfx; n_d := 'wh888d_' || v_sfx;
    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
      (u_a, 'authenticated', 'authenticated', n_a || '@example.invalid', jsonb_build_object('username', n_a, 'display_name', 'WH 5888 A'), now(), now()),
      (u_b, 'authenticated', 'authenticated', n_b || '@example.invalid', jsonb_build_object('username', n_b, 'display_name', 'WH 5888 B'), now(), now()),
      (u_c, 'authenticated', 'authenticated', n_c || '@example.invalid', jsonb_build_object('username', n_c, 'display_name', 'WH 5888 C'), now(), now()),
      (u_d, 'authenticated', 'authenticated', n_d || '@example.invalid', jsonb_build_object('username', n_d, 'display_name', 'WH 5888 D'), now(), now());
    select i.id into v_inv_a from public.inventory i where i.owner_user_id = u_a;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (k1s, v_pt, v_inv_a) returning id into a1;

    perform pg_temp.wh_5888_as(u_a);
    select x.storage_container_id into v_bin from public.create_my_storage_container(gen_random_uuid(), 'BIN 5888', 'BINDER') x;
    select x.collection_id into v_co from public.create_my_free_collection(gen_random_uuid(), 'CO 5888', v_bin) x;
    select x.collection_id into v_cx from public.create_my_free_collection(gen_random_uuid(), 'CX 5888', v_bin) x;
    perform public.allocate_physical_cards_to_collection(v_co, array[a1]);
    select * into p from public.preview_my_collection_binder(v_co, 3, 3, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_co, 3, 3, 'PRINCIPAL_ONLY', p.plan_token);

    -- 1. Convite -----------------------------------------------------------------------
    perform pg_temp.wh_5888_as(u_a);
    j := public.invite_collection_member(v_co, n_b);                       -- 2 argumentos, como o frontend
    m_b := (j ->> 'membership_id')::uuid;
    res := res || jsonb_build_object('id','1.1','ok',
      j ->> 'outcome' = 'INVITED' and j ->> 'role' = 'VIEWER'
      and (select m.role from public.collection_membership m where m.id = m_b) = 'VIEWER',
      'detail','convite sem papel (chamada de 2 argumentos) grava VIEWER');
    j := public.invite_collection_member(v_co, '@' || upper(n_d), ' editor ');
    m_d := (j ->> 'membership_id')::uuid;
    res := res || jsonb_build_object('id','1.2','ok',
      j ->> 'outcome' = 'INVITED' and j ->> 'role' = 'EDITOR'
      and (select m.role || '/' || m.status from public.collection_membership m where m.id = m_d) = 'EDITOR/PENDING',
      'detail','convite EDITOR explícito (papel e username normalizados)');
    v_ok := true;
    foreach v_err in array array['OWNER','PUBLIC','ADMIN',''] loop
      j2 := null;
      begin j2 := public.invite_collection_member(v_cx, n_c, v_err); exception when others then j2 := jsonb_build_object('e', sqlerrm, 's', sqlstate); end;
      v_ok := v_ok and coalesce(j2 ->> 'e' = 'INVALID_ROLE' and j2 ->> 's' = '22023', false);
    end loop;
    res := res || jsonb_build_object('id','1.3','ok', v_ok
      and not exists (select 1 from public.collection_membership m where m.collection_id = v_cx),
      'detail','OWNER/PUBLIC/ADMIN/vazio → INVALID_ROLE (22023), nada gravado');
    j := public.invite_collection_member(v_cx, n_c, null);
    res := res || jsonb_build_object('id','1.4','ok', j ->> 'role' = 'VIEWER' and j ->> 'outcome' = 'INVITED',
      'detail','p_role NULL explícito → VIEWER');
    v_err := null; begin perform public.invite_collection_member(v_co, n_a, 'EDITOR'); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','1.5','ok', v_err = 'CANNOT_INVITE_SELF',
      'detail','titular não se convida como EDITOR');

    -- 2. Convite pendente ----------------------------------------------------------------
    j := public.invite_collection_member(v_co, n_d, 'EDITOR');
    res := res || jsonb_build_object('id','2.1','ok', j ->> 'outcome' = 'ALREADY_PENDING' and (j ->> 'membership_id')::uuid = m_d and j ->> 'role' = 'EDITOR',
      'detail','pendente + mesmo papel → ALREADY_PENDING');
    v_err := null; begin perform public.invite_collection_member(v_co, n_d, 'VIEWER'); exception when others then v_err := sqlerrm || '/' || sqlstate; end;
    res := res || jsonb_build_object('id','2.2','ok', v_err = 'INVITE_PENDING_ROLE_IMMUTABLE/55000'
      and (select m.role || '/' || m.status from public.collection_membership m where m.id = m_d) = 'EDITOR/PENDING',
      'detail','pendente + outro papel → INVITE_PENDING_ROLE_IMMUTABLE, nada muda');
    v_err := null; begin perform public.invite_collection_member(v_co, n_d); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','2.3','ok', v_err = 'INVITE_PENDING_ROLE_IMMUTABLE',
      'detail','pendente EDITOR + chamada sem papel (VIEWER) também é recusada — sem conversão silenciosa');
    v_err := null; begin perform public.set_collection_member_role(v_co, m_d, 'VIEWER'); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','2.4','ok', v_err = 'INVITE_PENDING_ROLE_IMMUTABLE'
      and (select m.role from public.collection_membership m where m.id = m_d) = 'EDITOR',
      'detail','troca de papel de convite pendente recusada');
    perform pg_temp.wh_5888_as(u_d);
    j := public.get_my_collection_invites();
    res := res || jsonb_build_object('id','2.5','ok',
      jsonb_array_length(j) = 1 and j -> 0 ->> 'role' = 'EDITOR'
      and not exists (select 1 from jsonb_object_keys(j -> 0) k where k <> all (box_allowed)),
      'detail','caixa de convites mostra o papel oferecido; nenhuma chave nova além de role');

    -- 3. Leitura VIEWER × EDITOR ---------------------------------------------------------
    perform pg_temp.wh_5888_as(u_b);
    perform public.respond_collection_invite(m_b, true);
    r_viewer := pg_temp.wh_5888_reads(v_co);
    j := public.get_shared_collection(v_co);
    res := res || jsonb_build_object('id','3.1','ok', j ->> 'access' = 'VIEWER' and j ->> 'role' = 'VIEWER' and j ->> 'membership_id' = m_b::text,
      'detail','VIEWER: access VIEWER, role VIEWER, membership_id presente');
    perform pg_temp.wh_5888_as(u_a);
    j := public.set_collection_member_role(v_co, m_b, 'EDITOR');
    perform pg_temp.wh_5888_as(u_b);
    r_editor := pg_temp.wh_5888_reads(v_co);
    res := res || jsonb_build_object('id','3.2','ok', r_editor = r_viewer and coalesce(r_editor -> 'hdr', 'null'::jsonb) <> 'null'::jsonb
      and jsonb_array_length(r_editor -> 'crd') = 1,
      'detail','EDITOR recebe exatamente o mesmo que o VIEWER: cabeçalho, galeria, fichário, páginas, imagens, capa, posições e lista (exceto role)');
    j := public.get_shared_collection(v_co);
    res := res || jsonb_build_object('id','3.3','ok', j ->> 'access' = 'VIEWER' and j ->> 'role' = 'EDITOR' and j ->> 'membership_id' = m_b::text,
      'detail','EDITOR: access continua VIEWER (rotas compartilhadas intactas), role EDITOR');
    j := public.get_collections_shared_with_me();
    res := res || jsonb_build_object('id','3.4','ok', jsonb_array_length(j) = 1 and j -> 0 ->> 'role' = 'EDITOR' and j -> 0 ->> 'collection_id' = v_co::text,
      'detail','"Compartilhadas com você" mostra o papel EDITOR');
    execute 'reset role';
    res := res || jsonb_build_object('id','3.5','ok',
      public.collection_share_role(v_co) = 'VIEWER' and public.collection_member_role(v_co) = 'EDITOR'
      and public.collection_share_role(v_cx) is null and public.collection_member_role(v_cx) is null,
      'detail','nível de leitura (5302) = VIEWER; papel real (5367) = EDITOR; outra coleção do titular → NULL nos dois');
    perform pg_temp.wh_5888_claims(u_a);
    res := res || jsonb_build_object('id','3.6','ok', public.collection_member_role(v_co) = 'OWNER' and public.collection_share_role(v_co) = 'OWNER',
      'detail','titular: OWNER nos dois');
    perform pg_temp.wh_5888_claims(u_c);
    res := res || jsonb_build_object('id','3.7','ok', public.collection_member_role(v_co) is null and public.collection_member_role(v_cx) is null,
      'detail','estranho em CO e convidado PENDING em CX → NULL');
    perform pg_temp.wh_5888_claims(u_d);
    res := res || jsonb_build_object('id','3.8','ok', public.collection_member_role(v_co) is null and public.collection_share_role(v_co) is null,
      'detail','convite EDITOR ainda PENDING não dá papel nem leitura');
    perform pg_temp.wh_5888_claims(null);
    update public.collection set visibility = 'PUBLIC' where id = v_co;
    res := res || jsonb_build_object('id','3.9','ok', public.collection_member_role(v_co) is null and public.collection_share_role(v_co) = 'PUBLIC',
      'detail','sem sessão em coleção PUBLIC: papel NULL (PUBLIC não é papel)');
    update public.collection set visibility = 'PRIVATE' where id = v_co;

    -- 4. Troca de papel --------------------------------------------------------------------
    perform pg_temp.wh_5888_as(u_a);
    j := public.set_collection_member_role(v_co, m_b, 'EDITOR');
    res := res || jsonb_build_object('id','4.1','ok', j ->> 'outcome' = 'UNCHANGED' and j ->> 'role' = 'EDITOR',
      'detail','mesmo papel → UNCHANGED (idempotente)');
    j := public.set_collection_member_role(v_co, m_b, ' viewer ');
    res := res || jsonb_build_object('id','4.2','ok', j ->> 'outcome' = 'CHANGED' and j ->> 'previous_role' = 'EDITOR' and j ->> 'role' = 'VIEWER'
      and (select m.role || '/' || m.status from public.collection_membership m where m.id = m_b) = 'VIEWER/ACTIVE',
      'detail','EDITOR → VIEWER (normalizado), continua ACTIVE');
    perform pg_temp.wh_5888_as(u_b);
    res := res || jsonb_build_object('id','4.3','ok', public.get_shared_collection(v_co) ->> 'role' = 'VIEWER',
      'detail','efeito imediato: a leitura seguinte do membro já vê VIEWER');
    perform pg_temp.wh_5888_as(u_a);
    j := public.set_collection_member_role(v_co, m_b, 'EDITOR');
    res := res || jsonb_build_object('id','4.4','ok', j ->> 'outcome' = 'CHANGED' and j ->> 'previous_role' = 'VIEWER',
      'detail','VIEWER → EDITOR');
    v_ok := true;
    foreach v_err in array array['OWNER','PUBLIC','x'] loop
      j2 := null;
      begin j2 := public.set_collection_member_role(v_co, m_b, v_err); exception when others then j2 := jsonb_build_object('e', sqlerrm); end;
      v_ok := v_ok and coalesce(j2 ->> 'e' = 'INVALID_ROLE', false);
    end loop;
    v_err := null; begin perform public.set_collection_member_role(v_co, m_b, null); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','4.5','ok', v_ok and v_err = 'INVALID_ROLE'
      and (select m.role from public.collection_membership m where m.id = m_b) = 'EDITOR'
      and (select c.owner_user_id from public.collection c where c.id = v_co) = u_a,
      'detail','OWNER/PUBLIC/inválido/NULL → INVALID_ROLE; papel e titularidade intactos');
    v_err := null; begin perform public.set_collection_member_role(v_cx, m_b, 'VIEWER'); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','4.6','ok', v_err = 'MEMBERSHIP_NOT_FOUND',
      'detail','participação de outra coleção do mesmo titular (ids cruzados) → MEMBERSHIP_NOT_FOUND');
    v_err := null; begin perform public.set_collection_member_role(v_co, gen_random_uuid(), 'VIEWER'); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','4.7','ok', v_err = 'MEMBERSHIP_NOT_FOUND',
      'detail','participação inexistente → MEMBERSHIP_NOT_FOUND');
    v_err := null; begin perform public.invite_collection_member(v_co, n_b, 'VIEWER'); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','4.8','ok', v_err = 'ALREADY_MEMBER'
      and (select m.role from public.collection_membership m where m.id = m_b) = 'EDITOR',
      'detail','convidar membro ativo com outro papel → ALREADY_MEMBER (troca só pela 5370)');

    -- 5. Segurança -------------------------------------------------------------------------
    perform pg_temp.wh_5888_as(u_b);   -- B é EDITOR de CO
    v_err := null; begin perform public.set_collection_member_role(v_co, m_b, 'VIEWER'); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','5.1','ok', v_err = 'MEMBERSHIP_NOT_FOUND'
      and (select m.role from public.collection_membership m where m.id = m_b) = 'EDITOR',
      'detail','membro não altera o próprio papel');
    v_err := null; begin perform public.set_collection_member_role(v_co, m_d, 'VIEWER'); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','5.2','ok', v_err = 'MEMBERSHIP_NOT_FOUND',
      'detail','EDITOR não altera papel de outro participante');
    v_err := null; begin perform public.invite_collection_member(v_co, n_c, 'EDITOR'); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','5.3','ok', v_err = 'COLLECTION_NOT_FOUND'
      and not exists (select 1 from public.collection_membership m where m.collection_id = v_co and m.user_id = u_c),
      'detail','EDITOR não convida (C-154)');
    j := public.get_shared_collection(v_co);
    j2 := public.get_my_collection_sharing(v_co);
    res := res || jsonb_build_object('id','5.4','ok', j2 is null
      and not exists (select 1 from jsonb_object_keys(j) k where k <> all (hdr_allowed)),
      'detail','EDITOR não lê o painel do titular (papéis de outros membros); cabeçalho só com chaves do contrato + role');
    perform pg_temp.wh_5888_as(u_c);
    v_err := null; begin perform public.set_collection_member_role(v_co, m_b, 'VIEWER'); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','5.5','ok', v_err = 'MEMBERSHIP_NOT_FOUND',
      'detail','estranho → MEMBERSHIP_NOT_FOUND (não enumera)');
    perform pg_temp.wh_5888_as(null);
    v_err := null; begin perform public.set_collection_member_role(v_co, m_b, 'VIEWER'); exception when others then v_err := sqlstate; end;
    n := 0; begin perform public.invite_collection_member(v_co, n_c, 'EDITOR'); exception when others then if sqlstate = '42501' then n := 1; end if; end;
    res := res || jsonb_build_object('id','5.6','ok', v_err = '42501' and n = 1,
      'detail','anon sem EXECUTE na troca de papel e no convite');
    -- D recusa o convite EDITOR; titular reconvida como VIEWER → id novo; id antigo morto.
    perform pg_temp.wh_5888_as(u_d);
    perform public.respond_collection_invite(m_d, false);
    perform pg_temp.wh_5888_as(u_a);
    v_err := null; begin perform public.set_collection_member_role(v_co, m_d, 'VIEWER'); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','5.7','ok', v_err = 'MEMBER_NOT_ACTIVE',
      'detail','participação recusada não troca de papel');
    j := public.invite_collection_member(v_co, n_d, 'VIEWER');
    m_d2 := (j ->> 'membership_id')::uuid;
    res := res || jsonb_build_object('id','5.8','ok', j ->> 'outcome' = 'REINVITED' and j ->> 'role' = 'VIEWER' and m_d2 <> m_d
      and not exists (select 1 from public.collection_membership m where m.id = m_d),
      'detail','recusado + outro papel → convite novo com id novo; linha antiga apagada');
    perform pg_temp.wh_5888_as(u_d);
    v_err := null; begin perform public.respond_collection_invite(m_d, true); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','5.9','ok', v_err = 'INVITE_NOT_FOUND'
      and (select m.status from public.collection_membership m where m.id = m_d2) = 'PENDING',
      'detail','aba antiga não aceita o id anterior (papel não visto)');
    perform public.respond_collection_invite(m_d2, false);
    perform pg_temp.wh_5888_as(u_a);
    j := public.invite_collection_member(v_co, n_d, 'VIEWER');
    res := res || jsonb_build_object('id','5.10','ok', j ->> 'outcome' = 'REINVITED' and (j ->> 'membership_id')::uuid = m_d2,
      'detail','recusado + mesmo papel → mesma linha (comportamento V1-12)');
    j := public.remove_collection_member(v_co, m_b);
    v_err := null; begin perform public.set_collection_member_role(v_co, m_b, 'VIEWER'); exception when others then v_err := sqlerrm; end;
    perform pg_temp.wh_5888_as(u_b);
    res := res || jsonb_build_object('id','5.11','ok', v_err = 'MEMBERSHIP_NOT_FOUND' and public.get_shared_collection(v_co) is null
      and jsonb_array_length(public.get_collections_shared_with_me()) = 0,
      'detail','EDITOR removido: sem papel, sem leitura, sem troca');
    perform pg_temp.wh_5888_as(u_a);
    m_b := (public.invite_collection_member(v_co, n_b, 'EDITOR') ->> 'membership_id')::uuid;
    perform pg_temp.wh_5888_as(u_b);
    perform public.respond_collection_invite(m_b, true);
    j := public.leave_shared_collection(v_co);
    execute 'reset role';
    res := res || jsonb_build_object('id','5.12','ok', j ->> 'outcome' = 'LEFT' and public.collection_member_role(v_co) is null
      and not exists (select 1 from public.collection_membership m where m.id = m_b),
      'detail','EDITOR que saiu: sem papel na hora');

    -- 6. Privacidade das chaves --------------------------------------------------------------
    perform pg_temp.wh_5888_as(u_a);
    j := public.invite_collection_member(v_co, n_b, 'EDITOR');
    m_b := (j ->> 'membership_id')::uuid;
    res := res || jsonb_build_object('id','6.1','ok',
      not exists (select 1 from jsonb_object_keys(j) k where k <> all (inv_allowed)),
      'detail','retorno do convite: só outcome, membership_id, username, display_name, status, role');
    j := public.get_my_collection_sharing(v_co);
    res := res || jsonb_build_object('id','6.2','ok',
      exists (select 1 from jsonb_array_elements(j -> 'members') e where e ->> 'membership_id' = m_b::text and e ->> 'role' = 'EDITOR'),
      'detail','painel do titular (5308, inalterada) mostra o papel EDITOR');
    perform pg_temp.wh_5888_as(u_b);
    perform public.respond_collection_invite(m_b, true);
    j := public.get_collections_shared_with_me();
    res := res || jsonb_build_object('id','6.3','ok',
      not exists (select 1 from jsonb_array_elements(j) e, jsonb_object_keys(e) k where k <> all (swm_allowed)),
      'detail','"Compartilhadas com você": chaves do contrato V1-12 + role');
    j := public.get_shared_collection(v_co);
    res := res || jsonb_build_object('id','6.4','ok',
      j::text !~* '(@example\.invalid|wh888[a-d]_)' and strpos(j::text, u_a::text) = 0 and strpos(j::text, u_d::text) = 0,
      'detail','cabeçalho do EDITOR sem e-mail, username ou id de titular e de outros participantes');

    -- 7. Sem escrita na E1-A ------------------------------------------------------------------
    v_err := null; begin perform public.update_collection_metadata(v_co, 'Renomeada', null); exception when others then v_err := 'refused'; end;
    res := res || jsonb_build_object('id','7.1','ok', v_err = 'refused'
      and (select c.name from public.collection c where c.id = v_co) = 'CO 5888',
      'detail','EDITOR não edita metadados nesta etapa');
    v_err := null; begin perform public.set_collection_visibility(v_co, 'PUBLIC'); exception when others then v_err := 'refused'; end;
    res := res || jsonb_build_object('id','7.2','ok', v_err = 'refused'
      and (select c.visibility from public.collection c where c.id = v_co) = 'PRIVATE',
      'detail','EDITOR não altera visibilidade');
    v_err := null; begin perform public.remove_collection_member(v_co, m_b); exception when others then v_err := 'refused'; end;
    res := res || jsonb_build_object('id','7.3','ok', v_err = 'refused'
      and exists (select 1 from public.collection_membership m where m.id = m_b),
      'detail','EDITOR não remove participações por esse caminho');
    v_err := null; begin perform count(*) from public.collection_membership; exception when others then v_err := sqlstate; end;
    res := res || jsonb_build_object('id','7.4','ok', v_err = '42501',
      'detail','EDITOR sem acesso direto à tabela de participações');

    execute 'reset role';
    raise exception 'MS888' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MS888' then
      res := res || jsonb_build_object('id','X.1','ok', false, 'detail','erro inesperado: '||sqlstate||' '||sqlerrm);
    end if;
  end;

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.collection_membership), (select count(*) from public.card)]
    into e_counts;
  res := res || jsonb_build_object('id','99.1','ok', b_counts = e_counts and current_user = session_user,
    'detail','resíduo zero (6 contagens) e papel restaurado');

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

-- Execução: somente pelo protocolo de VALIDATION-STRATEGY-E1A.md, com autorização específica.
-- Chamada: select * from pg_temp.wh_5888_validate();
