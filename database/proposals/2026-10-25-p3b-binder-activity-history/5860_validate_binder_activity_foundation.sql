/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5860 - Harness P3-B S1 · Histórico do Fichário (5267–5270)
Versão......: 1.2 (2026-10-25, P3-B-S1-LIVE-DRYRUN-STRUCTURAL-CORRECTION-02: 2.11/2.12
              acompanham o teto W1 v1.2 — 676 num 2×2 de 2 páginas)
              1.1 (P3-B-S1-SECURITY-CORRECTION-01: B1, W1, W8)
              v1.1: +0.6 (W8 sequência), +0.7 (B1 FKs), +2.11/2.12 (W1 teto
              por capacidade), 9.2 reescrito (ator inalterado). GATE 43 → 47.
Status......: PROPOSTA — OFICIALMENTE NÃO EXECUTADO (nenhuma versão deste
              harness rodou em nenhum ambiente). NUNCA executar no LIVE (cria
              usuários, catálogo sintético, coleção e fichário — desfeitos
              pela sentinela, mas proibido no LIVE por convenção). Execução
              só com autorização expressa de Fabrício, no protocolo vigente
              (mesmo das 5853/5857/5859), DEPOIS de 5267 → 5270.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-25

Protocolo: um único statement por função; usuários efêmeros A, B, C; a
sentinela MS860 desfaz tudo; 99.1 prova resíduo zero.

  select * from pg_temp.wh_5860_validate();   -- funcional/segurança: GATE esperado 47/47
  select * from pg_temp.wh_5860_perf();        -- desempenho: MEDIÇÕES (metas, não aceite) + 2 PASS/FAIL de plano

Cobertura (README v1.2 §10):
  0.x  estrutura, privilégios, gatilhos, legado, sequência (W8), FKs (B1) (S1–S5, I8)
  1.x  autorização de execução e de tabela (S1–S3)
  2.x  gravação: preguiçosa, operação lógica com aninhamento, sequência,
       fichário diferente, sem contexto, bolso alheio, ator ≠ titular,
       sem sessão, rollback, teto por capacidade (W1) (I1, I2, I3, I9, C-205, C-206)
  3.x  imutabilidade (I6)
  4.x  cópia de carta e posição (I5, R3)
  5.x  leituras: ordem, cursor, categoria, erros, isolamento, cobertura (S2)
  6.x  fichário desmontado: eventos preservados e consultáveis (I10, C-208)
  7.x  segregação por titular (S6, C-207)
  8.x  exclusão definitiva e marco mínimo (C-203)
  9.x  exclusão da conta: cascata do titular; ator de outro titular inalterado (A5, B1)
  99.1 resíduo zero

Fixture: catálogo sintético (1 Set, 1 carta, STANDARD); A com local BINDER,
coleção livre e fichário 2×2 de 2 páginas mínimas (montagem canônica 5224);
B com local, coleção e fichário próprios; C só com linhas de histórico
inseridas com privilégio (para a exclusão de conta).
================================================================
*/

create or replace function pg_temp.wh5860_claims(p_uid uuid)
returns void language plpgsql as $c$
begin
  if p_uid is null then
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
  else
    perform set_config('request.jwt.claim.sub', p_uid::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  end if;
end;
$c$;

create or replace function pg_temp.wh_5860_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  u_a uuid := gen_random_uuid();
  u_b uuid := gen_random_uuid();
  u_c uuid := gen_random_uuid();
  v_sfx text := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  v_game uuid; v_pt uuid; v_rar uuid; v_cat uuid; v_std uuid;
  v_exp uuid; v_set uuid; k1 uuid; k1s uuid;
  v_inv_a uuid; v_inv_b uuid; pa uuid; pb uuid;
  v_bin_a uuid; v_bin_b uuid; v_col_a uuid; v_col_b uuid;
  l_a uuid; l_b uuid; s_a1 uuid; s_a2 uuid; s_b1 uuid;
  p record; v_ids uuid[];
  v_ok boolean; v_err text; v_hint text; n integer; n2 integer; n3 bigint;
  e1 bigint; e2 bigint; e3 bigint; v_ts timestamptz; v_id bigint;
  b_counts bigint[]; e_counts bigint[];
  res jsonb := '[]'::jsonb; r jsonb; cnt integer := 0; passes integer := 0;
  v_expected integer := 47;
  f_fns oid[];
begin
  -- 0. Estrutura ---------------------------------------------------------------------------
  select array_agg(q.oid) into f_fns from pg_proc q join pg_namespace ns on ns.oid = q.pronamespace
  where ns.nspname = 'public' and q.proname in ('binder_activity_begin','binder_activity_add_item','binder_activity_end',
        'binder_activity_category','get_my_binder_activity','get_my_binder_activity_coverage',
        'list_my_closed_binder_histories','purge_my_binder_activity','binder_activity_event_guard','binder_activity_item_guard');

  res := res || jsonb_build_object('id','0.1','ok',
    coalesce(array_length(f_fns, 1), 0) = 10
    and to_regclass('public.binder_activity_event') is not null and to_regclass('public.binder_activity_item') is not null
    and to_regclass('public.binder_activity_coverage') is not null and to_regclass('public.binder_activity_setting') is not null,
    'detail','5267–5270 presentes: 4 tabelas e 10 funções');
  if (res -> 0 ->> 'ok')::boolean is not true then
    res := res || jsonb_build_object('id','X.0','ok', false, 'detail','aplique 5267 → 5270 antes deste harness');
  else
  res := res || jsonb_build_object('id','0.2','ok',
    (select bool_and(q.prosecdef = (q.proname <> 'binder_activity_category') and q.proconfig @> array['search_path=""']
                     and not has_function_privilege('anon', q.oid, 'EXECUTE')
                     and has_function_privilege('authenticated', q.oid, 'EXECUTE')
                         = (q.proname in ('get_my_binder_activity','get_my_binder_activity_coverage','list_my_closed_binder_histories')))
     from pg_proc q where q.oid = any (f_fns))
    and not exists (select 1 from pg_proc q, aclexplode(q.proacl) x where q.oid = any (f_fns) and x.grantee = 0),
    'detail','funções: 9 DEFINER + 1 SQL pura, search_path vazio, sem PUBLIC/anon; EXECUTE de cliente só nas 3 leituras');
  res := res || jsonb_build_object('id','0.3','ok',
    not exists (select 1 from unnest(array['public.binder_activity_event','public.binder_activity_item',
                                           'public.binder_activity_coverage','public.binder_activity_setting']) t(tbl),
                              unnest(array['anon','authenticated','service_role']) rr(rol),
                              unnest(array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE']) pv(priv)
                where has_table_privilege(rr.rol, t.tbl, pv.priv))
    and (select bool_and(c.relrowsecurity) from pg_class c where c.oid in
         ('public.binder_activity_event'::regclass,'public.binder_activity_item'::regclass,
          'public.binder_activity_coverage'::regclass,'public.binder_activity_setting'::regclass)),
    'detail','tabelas com RLS e sem nenhum privilégio para anon/authenticated/service_role');
  res := res || jsonb_build_object('id','0.4','ok',
    (select count(*) from pg_trigger t where not t.tgisinternal
       and t.tgname in ('trg_bae_immutable','trg_bae_no_truncate','trg_bai_immutable','trg_bai_no_truncate')) = 4,
    'detail','4 gatilhos de imutabilidade');
  res := res || jsonb_build_object('id','0.5','ok',
    (select count(*) from public.binder_activity_event where source = 'LEGADO')
      = (select count(*) from public.collection_layout_catalog_incorporation)
    and not exists (select 1 from public.binder_activity_event e where e.source = 'LEGADO'
                    and (e.actor_user_id is not null or e.collection_name is not null or e.binder_name is not null))
    and not exists (select 1 from public.binder_activity_item i join public.binder_activity_event e on e.id = i.event_id
                    where e.source = 'LEGADO' and (i.from_page is not null or i.to_page is not null or i.effect <> 'INCORPORATED')),
    'detail','legado L01: um evento por incorporação real; sem ator, nomes ou posições inventados');
  -- W8: sequência da identidade sem nenhum privilégio de cliente
  res := res || jsonb_build_object('id','0.6','ok',
    pg_get_serial_sequence('public.binder_activity_event', 'id') = 'public.binder_activity_event_id_seq'
    and not exists (select 1 from unnest(array['anon','authenticated','service_role']) rr(rol),
                                  unnest(array['USAGE','SELECT','UPDATE']) pv(priv)
                    where has_sequence_privilege(rr.rol, 'public.binder_activity_event_id_seq', pv.priv))
    and not exists (select 1 from pg_class c, aclexplode(c.relacl) x
                    where c.oid = 'public.binder_activity_event_id_seq'::regclass
                      and (x.grantee = 0 or x.grantee in (select oid from pg_roles where rolname in ('anon','authenticated','service_role')))),
    'detail','W8: sequência da identidade sem USAGE/SELECT/UPDATE para anon/authenticated/service_role nem PUBLIC');
  -- B1: ator sem FK (nenhuma ação referencial reescreve evento); titular e item em cascata
  res := res || jsonb_build_object('id','0.7','ok',
    not exists (select 1 from pg_constraint k join pg_attribute a on a.attrelid = k.conrelid and a.attnum = any (k.conkey)
                where k.conrelid = 'public.binder_activity_event'::regclass and k.contype = 'f' and a.attname = 'actor_user_id')
    and exists (select 1 from pg_constraint k join pg_attribute a on a.attrelid = k.conrelid and a.attnum = any (k.conkey)
                where k.conrelid = 'public.binder_activity_event'::regclass and k.contype = 'f'
                  and a.attname = 'owner_user_id' and k.confdeltype = 'c' and k.confrelid = 'auth.users'::regclass)
    and exists (select 1 from pg_constraint k where k.conrelid = 'public.binder_activity_item'::regclass
                  and k.contype = 'f' and k.confdeltype = 'c' and k.confrelid = 'public.binder_activity_event'::regclass)
    and exists (select 1 from pg_constraint k where k.conrelid = 'public.binder_activity_coverage'::regclass
                  and k.contype = 'f' and k.confdeltype = 'c' and k.confrelid = 'auth.users'::regclass)
    and (select count(*) from pg_constraint k where k.conrelid = 'public.binder_activity_event'::regclass and k.contype = 'f') = 1
    and to_regclass('public.ix_bae_actor') is null,
    'detail','B1: ator sem FK e sem índice próprio; únicas FKs = titular (cascata), item→evento (cascata), marco→titular (cascata)');

  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.physical_card), (select count(*) from public.collection_layout),
               (select count(*) from public.card), (select count(*) from public.binder_activity_event),
               (select count(*) from public.binder_activity_item), (select count(*) from public.binder_activity_coverage)]
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
      res := res || jsonb_build_object('id','F.1','ok', false, 'detail','pré-requisitos de catálogo ausentes');
      raise exception 'MS860' using errcode = 'P0001';
    end if;
    insert into public.expansion (game_id, code, name, release_order)
    values (v_game, 'P3B_' || v_sfx, 'P3B Harness ' || v_sfx,
            (select coalesce(max(x.release_order), 0) + 1000 from public.expansion x where x.game_id = v_game))
    returning id into v_exp;
    insert into public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_exp, 'P3B' || v_sfx, 'P3B Set ' || v_sfx, 'REGULAR', 1, 1, 1) returning id into v_set;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '1', 1, 'P3B K1', true) returning id into k1;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default)
    values (k1, v_std, 1, true) returning id into k1s;

    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
      (u_a, 'authenticated', 'authenticated', 'wh5860-a-'||lower(v_sfx)||'@example.invalid',
       jsonb_build_object('username','wh5860a_'||lower(v_sfx), 'display_name','WH 5860 A'), now(), now()),
      (u_b, 'authenticated', 'authenticated', 'wh5860-b-'||lower(v_sfx)||'@example.invalid',
       jsonb_build_object('username','wh5860b_'||lower(v_sfx), 'display_name','WH 5860 B'), now(), now()),
      (u_c, 'authenticated', 'authenticated', 'wh5860-c-'||lower(v_sfx)||'@example.invalid',
       jsonb_build_object('username','wh5860c_'||lower(v_sfx), 'display_name','WH 5860 C'), now(), now());
    select i.id into v_inv_a from public.inventory i where i.owner_user_id = u_a;
    select i.id into v_inv_b from public.inventory i where i.owner_user_id = u_b;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (k1s, v_pt, v_inv_a) returning id into pa;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (k1s, v_pt, v_inv_b) returning id into pb;

    perform pg_temp.wh5860_claims(u_b);
    execute 'set local role authenticated';
    select x.storage_container_id into v_bin_b from public.create_my_storage_container(gen_random_uuid(), 'LB 5860', 'BINDER') x;
    select x.collection_id into v_col_b from public.create_my_free_collection(gen_random_uuid(), 'CB 5860', v_bin_b) x;
    perform public.allocate_physical_cards_to_collection(v_col_b, array[pb]);
    select * into p from public.preview_my_collection_binder(v_col_b, 2, 2, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_col_b, 2, 2, 'PRINCIPAL_ONLY', p.plan_token);

    perform pg_temp.wh5860_claims(u_a);
    execute 'set local role authenticated';
    select x.storage_container_id into v_bin_a from public.create_my_storage_container(gen_random_uuid(), 'LA 5860', 'BINDER') x;
    select x.collection_id into v_col_a from public.create_my_free_collection(gen_random_uuid(), 'CA 5860', v_bin_a) x;
    perform public.allocate_physical_cards_to_collection(v_col_a, array[pa]);
    select * into p from public.preview_my_collection_binder(v_col_a, 2, 2, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_col_a, 2, 2, 'PRINCIPAL_ONLY', p.plan_token);
    execute 'reset role';

    select l.id into l_a from public.collection_layout l where l.collection_id = v_col_a;
    select l.id into l_b from public.collection_layout l where l.collection_id = v_col_b;
    select array_agg(s.id order by pg.page_number, s.row_index, s.column_index) into v_ids
    from public.collection_layout_slot s join public.collection_layout_page pg on pg.id = s.page_id where pg.layout_id = l_a;
    s_a1 := v_ids[1]; s_a2 := v_ids[2];
    select s.id into s_b1 from public.collection_layout_slot s join public.collection_layout_page pg on pg.id = s.page_id
    where pg.layout_id = l_b order by pg.page_number, s.row_index, s.column_index limit 1;
    res := res || jsonb_build_object('id','F.1','ok', l_a is not null and l_b is not null and s_a2 is not null and s_b1 is not null,
      'detail','fixture: fichários 2×2 de A e de B');

    -- 1. Autorização ------------------------------------------------------------------------
    execute 'set local role anon';
    v_ok := false;
    begin perform count(*) from public.get_my_binder_activity(l_a); exception when insufficient_privilege then v_ok := true; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.1','ok', v_ok, 'detail','anon não executa get_my_binder_activity (42501)');

    perform pg_temp.wh5860_claims(u_a);
    execute 'set local role authenticated';
    n := 0;
    begin perform public.binder_activity_begin(l_a, 'CARD_MOVED', 'FICHARIO'); exception when insufficient_privilege then n := n + 1; end;
    begin perform public.binder_activity_add_item('CARD', 'MOVED'); exception when insufficient_privilege then n := n + 1; end;
    begin perform public.binder_activity_end(); exception when insufficient_privilege then n := n + 1; end;
    begin perform public.purge_my_binder_activity(l_a, l_a); exception when insufficient_privilege then n := n + 1; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.2','ok', n = 4, 'detail','authenticated não executa begin/add_item/end/purge (4×42501)');

    execute 'set local role authenticated';
    n := 0;
    begin perform count(*) from public.binder_activity_event; exception when insufficient_privilege then n := n + 1; end;
    begin perform count(*) from public.binder_activity_item; exception when insufficient_privilege then n := n + 1; end;
    begin perform count(*) from public.binder_activity_coverage; exception when insufficient_privilege then n := n + 1; end;
    begin insert into public.binder_activity_event (owner_user_id, layout_key, actor_user_id, event_type, source)
          values (u_a, l_a, u_a, 'CARD_MOVED', 'FICHARIO');
    exception when insufficient_privilege then n := n + 1; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.3','ok', n = 4, 'detail','authenticated não lê nem grava as tabelas (4×42501)');

    -- 2. Gravação (internas, chamadas com privilégio e sessão de A) ----------------------------
    perform pg_temp.wh5860_claims(u_a);
    select count(*) into n3 from public.binder_activity_event where layout_key = l_a;
    perform public.binder_activity_begin(l_a, 'CARDS_REMOVED', 'FICHARIO');
    perform public.binder_activity_end();
    res := res || jsonb_build_object('id','2.1','ok',
      (select count(*) from public.binder_activity_event where layout_key = l_a) = n3,
      'detail','operação sem efeito (nenhum item) não grava evento (C-206)');

    perform public.binder_activity_begin(l_a, 'CARD_MOVED', 'FICHARIO', v_col_a);
    perform public.binder_activity_add_item('CARD', 'MOVED', k1, v_std, s_a1, s_a2);
    perform public.binder_activity_end();
    select e.id into e1 from public.binder_activity_event e where e.layout_key = l_a and e.event_type = 'CARD_MOVED';
    res := res || jsonb_build_object('id','2.2','ok',
      e1 is not null
      and (select owner_user_id = u_a and actor_user_id = u_a and source = 'FICHARIO' and collection_id = v_col_a
                  and collection_name = 'CA 5860' and binder_name is not null and created_xact = pg_current_xact_id()
           from public.binder_activity_event where id = e1)
      and (select count(*) from public.binder_activity_item where event_id = e1) = 1
      and (select from_page = 1 and from_row = 1 and from_col = 1 and to_page = 1 and to_row = 1 and to_col = 2
                  and card_name = 'P3B K1' and collector_number = '1' and card_set_code = 'P3B' || v_sfx
                  and variant_type_code = 'STANDARD'
           from public.binder_activity_item where event_id = e1 and ordinal = 1),
      'detail','1 evento + 1 item; titular/ator = A; posições e carta copiadas; mesma transação');

    perform public.binder_activity_begin(l_a, 'GAP_OPENED', 'FICHARIO');
    perform public.binder_activity_begin(l_a, 'PAGES_ADDED', 'FICHARIO');      -- interna aninhada
    perform public.binder_activity_add_item('PAGE', 'PAGE_ADDED', null, null, null, null, null, 3);
    perform public.binder_activity_end();
    perform public.binder_activity_add_item('CARD', 'SHIFTED', k1, v_std, s_a2, s_a1);
    perform public.binder_activity_end();
    select e.id into e2 from public.binder_activity_event e where e.layout_key = l_a and e.event_type = 'GAP_OPENED';
    res := res || jsonb_build_object('id','2.3','ok',
      e2 is not null
      and not exists (select 1 from public.binder_activity_event where layout_key = l_a and event_type = 'PAGES_ADDED')
      and (select array_agg(effect order by ordinal) from public.binder_activity_item where event_id = e2)
          = array['PAGE_ADDED','SHIFTED'],
      'detail','operação composta: 1 evento (externo) com os efeitos internos como itens, sem duplicidade (C-205)');

    perform public.binder_activity_begin(l_a, 'POCKETS_LOCKED', 'FICHARIO');
    perform public.binder_activity_add_item('POCKET', 'LOCKED', null, null, null, s_a1);
    perform public.binder_activity_end();
    perform public.binder_activity_begin(l_a, 'POCKETS_UNLOCKED', 'FICHARIO');
    perform public.binder_activity_add_item('POCKET', 'UNLOCKED', null, null, null, s_a1);
    perform public.binder_activity_end();
    res := res || jsonb_build_object('id','2.4','ok',
      (select count(*) from public.binder_activity_event where layout_key = l_a
         and event_type in ('POCKETS_LOCKED','POCKETS_UNLOCKED') and created_xact = pg_current_xact_id()) = 2,
      'detail','duas operações na mesma transação → dois eventos (contexto limpo no fim)');

    v_hint := null;
    perform public.binder_activity_begin(l_a, 'GAP_OPENED', 'FICHARIO');
    begin perform public.binder_activity_begin(l_b, 'PAGES_ADDED', 'FICHARIO');
    exception when others then get stacked diagnostics v_hint = pg_exception_hint; end;
    perform public.binder_activity_end();
    res := res || jsonb_build_object('id','2.5','ok', v_hint = 'BINDER_ACTIVITY_NESTED_LAYOUT',
      'detail','operação aninhada em outro fichário → recusa (nunca mistura fichários)');

    v_hint := null;
    begin perform public.binder_activity_add_item('CARD', 'MOVED', k1);
    exception when others then get stacked diagnostics v_hint = pg_exception_hint; end;
    res := res || jsonb_build_object('id','2.6','ok', v_hint = 'BINDER_ACTIVITY_NO_CONTEXT',
      'detail','item sem operação aberta → recusa');

    v_hint := null;
    perform public.binder_activity_begin(l_a, 'CARD_MOVED', 'FICHARIO');
    begin perform public.binder_activity_add_item('CARD', 'MOVED', k1, null, s_b1, s_a1);
    exception when others then get stacked diagnostics v_hint = pg_exception_hint; end;
    perform public.binder_activity_end();
    res := res || jsonb_build_object('id','2.7','ok', v_hint = 'BINDER_ACTIVITY_SLOT',
      'detail','bolso de outro fichário → recusa');

    select count(*) into n3 from public.binder_activity_event;
    perform pg_temp.wh5860_claims(u_b);
    v_hint := null;
    perform public.binder_activity_begin(l_a, 'CARD_MOVED', 'FICHARIO');
    begin perform public.binder_activity_add_item('CARD', 'MOVED', k1, null, s_a1, s_a2);
    exception when others then get stacked diagnostics v_hint = pg_exception_hint; end;
    perform public.binder_activity_end();
    res := res || jsonb_build_object('id','2.8','ok',
      v_hint = 'BINDER_ACTIVITY_NOT_OWNER' and (select count(*) from public.binder_activity_event) = n3,
      'detail','ator ≠ dono do fichário → recusa sem gravar');

    perform pg_temp.wh5860_claims(null);
    v_err := null;
    perform public.binder_activity_begin(l_a, 'CARD_MOVED', 'FICHARIO');
    begin perform public.binder_activity_add_item('CARD', 'MOVED', k1, null, s_a1, s_a2);
    exception when others then v_err := sqlstate; end;
    perform public.binder_activity_end();
    res := res || jsonb_build_object('id','2.9','ok', v_err = '28000' and (select count(*) from public.binder_activity_event) = n3,
      'detail','sem sessão → 28000, nada gravado');

    perform pg_temp.wh5860_claims(u_a);
    begin
      perform public.binder_activity_begin(l_a, 'CARDS_REMOVED', 'FICHARIO');
      perform public.binder_activity_add_item('CARD', 'REMOVED', k1, v_std, s_a1);
      raise exception 'WH5860_ROLLBACK';
    exception when others then null;
    end;
    res := res || jsonb_build_object('id','2.10','ok',
      not exists (select 1 from public.binder_activity_event where layout_key = l_a and event_type = 'CARDS_REMOVED')
      and coalesce(current_setting('mmkyu.binder_activity_ctx', true), '') = '',
      'detail','operação que falha: evento e contexto desfeitos junto (R1)');

    -- W1: teto derivado da capacidade, recalculado quando o fichário cresce na operação.
    -- Tudo dentro de um bloco desfeito por WH5860_W1 (nenhum evento sobra).
    perform pg_temp.wh5860_claims(u_a);
    select count(*) * (8 * 2 * 2 + 2) + 8 + 600 into n
    from public.collection_layout_page pg where pg.layout_id = l_a;          -- teto esperado (grade 2×2 + folga 600)
    n2 := -1; v_ok := false; v_hint := null;
    begin
      perform public.binder_activity_begin(l_a, 'PAGES_REORDERED', 'FICHARIO');
      for i in 1 .. n loop
        perform public.binder_activity_add_item('PAGE', 'PAGE_RENUMBERED', null, null, null, null, 1, 1);
      end loop;
      begin perform public.binder_activity_add_item('PAGE', 'PAGE_RENUMBERED', null, null, null, null, 1, 1);
      exception when others then get stacked diagnostics v_hint = pg_exception_hint; end;
      -- o fichário ganha uma página DENTRO da operação (como E11/E16): o teto é recalculado
      perform count(*) from public.add_layout_page(l_a);
      begin perform public.binder_activity_add_item('PAGE', 'PAGE_ADDED', null, null, null, null, null, 3);
            v_ok := true;
      exception when others then v_ok := false; end;
      perform public.binder_activity_end();
      select count(*) into n2 from public.binder_activity_item i join public.binder_activity_event e on e.id = i.event_id
      where e.layout_key = l_a and e.event_type = 'PAGES_REORDERED';
      raise exception 'WH5860_W1';
    exception when others then
      if sqlerrm <> 'WH5860_W1' then v_hint := 'UNEXPECTED: ' || sqlerrm; v_ok := false; end if;
    end;
    res := res || jsonb_build_object('id','2.11','ok', v_hint = 'BINDER_ACTIVITY_ITEM_LIMIT' and n = 676,
      'detail','W1: fichário 2×2 de 2 páginas → teto 2×(8×4+2)+8+600 = 676; o 677º item sem crescimento é recusado com erro explícito');
    res := res || jsonb_build_object('id','2.12','ok', v_ok and n2 = n + 1
      and not exists (select 1 from public.binder_activity_event where layout_key = l_a and event_type = 'PAGES_REORDERED')
      and coalesce(current_setting('mmkyu.binder_activity_ctx', true), '') = '',
      'detail','W1: página criada na operação → teto recalculado no item PAGE_ADDED; operação válida não é rejeitada; tudo desfeito no fim');

    -- 3. Imutabilidade -----------------------------------------------------------------------
    v_hint := null;
    begin update public.binder_activity_event set source = 'ACERVO' where id = e1;
    exception when others then get stacked diagnostics v_hint = pg_exception_hint; end;
    res := res || jsonb_build_object('id','3.1','ok', v_hint = 'BINDER_ACTIVITY_IMMUTABLE', 'detail','UPDATE de evento recusado');
    v_hint := null;
    begin delete from public.binder_activity_event where id = e1;
    exception when others then get stacked diagnostics v_hint = pg_exception_hint; end;
    res := res || jsonb_build_object('id','3.2','ok', v_hint = 'BINDER_ACTIVITY_IMMUTABLE', 'detail','DELETE de evento sem a porta da 5270 recusado');
    n := 0;
    begin update public.binder_activity_item set card_name = 'X' where event_id = e1;
    exception when others then n := n + 1; end;
    begin delete from public.binder_activity_item where event_id = e1;
    exception when others then n := n + 1; end;
    res := res || jsonb_build_object('id','3.3','ok', n = 2, 'detail','UPDATE e DELETE de item recusados');
    n := 0;
    begin execute 'truncate public.binder_activity_item'; exception when others then n := n + 1; end;
    begin execute 'truncate public.binder_activity_event cascade'; exception when others then n := n + 1; end;
    res := res || jsonb_build_object('id','3.4','ok', n = 2 and exists (select 1 from public.binder_activity_event where id = e1),
      'detail','TRUNCATE recusado nas duas tabelas');

    -- 4. Cópia (R3) ---------------------------------------------------------------------------
    update public.card set name = 'P3B K1 renomeada' where id = k1;
    update public.collection_layout_page set page_number = page_number + 100 where layout_id = l_a;
    res := res || jsonb_build_object('id','4.1','ok',
      (select card_name = 'P3B K1' and from_page = 1 and to_page = 1 from public.binder_activity_item where event_id = e1 and ordinal = 1),
      'detail','renomear a carta e renumerar páginas não altera o evento');
    update public.collection_layout_page set page_number = page_number - 100 where layout_id = l_a;
    update public.card set name = 'P3B K1' where id = k1;

    -- 5. Leituras ----------------------------------------------------------------------------
    perform pg_temp.wh5860_claims(u_a);
    execute 'set local role authenticated';
    select count(*), min(item_count) into n, n2 from public.get_my_binder_activity(l_a);
    res := res || jsonb_build_object('id','5.1','ok',
      n = 4 and n2 >= 1
      and (select bool_and(true) from public.get_my_binder_activity(l_a) x where x.items is not null)
      and (select array_agg(x.event_id order by x.occurred_at desc, x.event_id desc) from public.get_my_binder_activity(l_a) x)
          = (select array_agg(x.event_id) from public.get_my_binder_activity(l_a) x),
      'detail','A lê os 4 eventos do seu fichário, do mais recente ao mais antigo, com itens');
    select x.occurred_at, x.event_id into v_ts, v_id from public.get_my_binder_activity(l_a, null, null, null, 1) x;
    select count(*) into n from public.get_my_binder_activity(l_a, null, v_ts, v_id, 50) x where x.event_id = v_id;
    select count(*) into n2 from public.get_my_binder_activity(l_a, null, v_ts, v_id, 50);
    res := res || jsonb_build_object('id','5.2','ok', n = 0 and n2 = 3, 'detail','cursor (occurred_at, id): próxima página sem repetir');
    select count(*) into n from public.get_my_binder_activity(l_a, array['PAGES']);
    select count(*) into n2 from public.get_my_binder_activity(l_a, array['LOCKS']);
    res := res || jsonb_build_object('id','5.3','ok', n = 1 and n2 = 2, 'detail','filtro por categoria (PAGES = 1, LOCKS = 2)');
    n := 0;
    begin perform count(*) from public.get_my_binder_activity(l_a, null, now(), null); exception when invalid_parameter_value then n := n + 1; end;
    begin perform count(*) from public.get_my_binder_activity(l_a, array['XYZ']); exception when invalid_parameter_value then n := n + 1; end;
    res := res || jsonb_build_object('id','5.4','ok', n = 2, 'detail','cursor incompleto e categoria desconhecida → 22023');
    execute 'reset role';

    perform pg_temp.wh5860_claims(u_b);
    execute 'set local role authenticated';
    select count(*) into n from public.get_my_binder_activity(l_a);
    select count(*) into n2 from public.get_my_binder_activity_coverage(l_a);
    execute 'reset role';
    perform pg_temp.wh5860_claims(null);
    execute 'set local role authenticated';
    select count(*) into n3 from public.get_my_binder_activity(l_a);
    execute 'reset role';
    res := res || jsonb_build_object('id','5.5','ok', n = 0 and n2 = 0 and n3 = 0,
      'detail','B (outro usuário) e sem sessão: zero linhas, sem distinção');

    perform pg_temp.wh5860_claims(u_a);
    execute 'set local role authenticated';
    res := res || jsonb_build_object('id','5.6','ok',
      (select full_coverage_from is null and covered_from is null and binder_is_mine and not has_legacy
       from public.get_my_binder_activity_coverage(l_a)),
      'detail','cobertura: global ainda NULL (O4); fichário é de A; sem legado neste fichário');
    select count(*) into n from public.list_my_closed_binder_histories();
    res := res || jsonb_build_object('id','5.7','ok', n = 0, 'detail','fichário ativo não aparece entre os encerrados');
    execute 'reset role';

    -- 6. Fichário desmontado (A1) ---------------------------------------------------------------
    perform pg_temp.wh5860_claims(u_a);
    execute 'set local role authenticated';
    select * into p from public.preview_my_collection_binder_dismantle(v_col_a);
    perform count(*) from public.dismantle_my_collection_binder(v_col_a, p.dismantle_token);
    res := res || jsonb_build_object('id','6.1','ok',
      not exists (select 1 from public.collection_layout l where l.collection_id = v_col_a),
      'detail','fichário de A desmontado pela função homologada');
    select count(*) into n from public.get_my_binder_activity(l_a);
    res := res || jsonb_build_object('id','6.2','ok', n = 4, 'detail','os 4 eventos sobrevivem à desmontagem e continuam legíveis por A');
    res := res || jsonb_build_object('id','6.3','ok',
      (select count(*) = 1 and bool_and(x.layout_key = l_a and x.event_count = 4) from public.list_my_closed_binder_histories() x)
      and (select not binder_is_mine from public.get_my_binder_activity_coverage(l_a)),
      'detail','fichário encerrado listado para A; cobertura indica que não é mais dele');
    execute 'reset role';
    perform pg_temp.wh5860_claims(u_b);
    execute 'set local role authenticated';
    select count(*) into n from public.get_my_binder_activity(l_a);
    select count(*) into n2 from public.list_my_closed_binder_histories();
    execute 'reset role';
    res := res || jsonb_build_object('id','6.4','ok', n = 0 and n2 = 0, 'detail','B não vê o histórico encerrado de A');

    -- 7. Segregação por titular (C-207) --------------------------------------------------------
    insert into public.binder_activity_event (owner_user_id, layout_key, actor_user_id, event_type, source)
    values (u_b, l_a, u_b, 'BINDER_OWNERSHIP_TRANSFERRED', 'FICHARIO') returning id into e3;
    insert into public.binder_activity_item (event_id, ordinal, item_kind, effect) values (e3, 1, 'BINDER', 'TRANSFERRED');
    perform pg_temp.wh5860_claims(u_a);
    execute 'set local role authenticated';
    select count(*) into n from public.get_my_binder_activity(l_a) x where x.event_id = e3;
    execute 'reset role';
    perform pg_temp.wh5860_claims(u_b);
    execute 'set local role authenticated';
    select count(*) into n2 from public.get_my_binder_activity(l_a);
    execute 'reset role';
    res := res || jsonb_build_object('id','7.1','ok', n = 0 and n2 = 1,
      'detail','mesma chave, titulares diferentes: cada um vê só os seus eventos (transferência futura entre usuários)');

    -- 8. Exclusão definitiva (C-203) ------------------------------------------------------------
    perform pg_temp.wh5860_claims(u_a);
    n := 0;
    begin perform public.purge_my_binder_activity(l_a, gen_random_uuid()); exception when invalid_parameter_value then n := 1; end;
    res := res || jsonb_build_object('id','8.1','ok', n = 1 and (select count(*) from public.binder_activity_event where owner_user_id = u_a and layout_key = l_a) = 4,
      'detail','confirmação diferente da chave → 22023, nada apagado');
    select public.purge_my_binder_activity(l_a, l_a) into n;
    res := res || jsonb_build_object('id','8.2','ok',
      n = 4
      and not exists (select 1 from public.binder_activity_event where owner_user_id = u_a and layout_key = l_a)
      and not exists (select 1 from public.binder_activity_item where event_id in (e1, e2))
      and exists (select 1 from public.binder_activity_event where id = e3)
      and coalesce(current_setting('mmkyu.binder_activity_purge', true), '') = '',
      'detail','4 eventos de A e seus itens apagados; evento de B com a mesma chave intacto; porta fechada');
    res := res || jsonb_build_object('id','8.3','ok',
      (select reason = 'HISTORY_PURGED' and covered_from is not null
       from public.binder_activity_coverage where owner_user_id = u_a and layout_key = l_a)
      and (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'binder_activity_coverage') = 5,
      'detail','marco mínimo: só titular, chave, data, motivo e updated_at — sem conteúdo histórico');
    execute 'set local role authenticated';
    select count(*) into n from public.get_my_binder_activity(l_a);
    res := res || jsonb_build_object('id','8.4','ok',
      n = 0 and (select coverage_reason = 'HISTORY_PURGED' from public.get_my_binder_activity_coverage(l_a)),
      'detail','leitura após exclusão: zero eventos e marco HISTORY_PURGED visível ao titular');
    execute 'reset role';

    -- 9. Exclusão da conta (A5) -----------------------------------------------------------------
    insert into public.binder_activity_event (owner_user_id, layout_key, actor_user_id, event_type, source)
    values (u_c, gen_random_uuid(), u_c, 'CARD_MOVED', 'FICHARIO') returning id into v_id;
    insert into public.binder_activity_item (event_id, ordinal, item_kind, effect) values (v_id, 1, 'CARD', 'MOVED');
    insert into public.binder_activity_coverage (owner_user_id, layout_key, covered_from, reason)
    values (u_c, gen_random_uuid(), now(), 'HISTORY_PURGED');
    insert into public.binder_activity_event (owner_user_id, layout_key, actor_user_id, event_type, source)
    values (u_b, l_b, u_c, 'CARD_MOVED', 'FICHARIO') returning id into e1;
    insert into public.binder_activity_item (event_id, ordinal, item_kind, effect) values (e1, 1, 'CARD', 'MOVED');
    -- O fluxo de exclusão de conta (futuro) remove antes o inventário (FK RESTRICT); aqui, o de C está vazio.
    delete from public.inventory where owner_user_id = u_c;
    delete from auth.users where id = u_c;
    res := res || jsonb_build_object('id','9.1','ok',
      not exists (select 1 from public.binder_activity_event where owner_user_id = u_c)
      and not exists (select 1 from public.binder_activity_item where event_id = v_id)
      and not exists (select 1 from public.binder_activity_coverage where owner_user_id = u_c),
      'detail','exclusão da conta: eventos, itens e marcos do titular saem pela cascata (porta (b) do gatilho)');
    res := res || jsonb_build_object('id','9.2','ok',
      (select actor_user_id = u_c and owner_user_id = u_b and created_xact = pg_current_xact_id()
       from public.binder_activity_event where id = e1)
      and (select count(*) from public.binder_activity_item where event_id = e1) = 1
      and not exists (select 1 from auth.users where id = u_c),
      'detail','B1: exclusão da conta de C conclui; evento de B em que C era ator permanece INALTERADO (ator como valor opaco, nenhum UPDATE)');

    raise exception 'MS860' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MS860' then
      res := res || jsonb_build_object('id','X.1','ok', false, 'detail','erro inesperado: '||sqlstate||' '||sqlerrm);
    end if;
  end;

  execute 'reset role';
  perform pg_temp.wh5860_claims(null);
  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.physical_card), (select count(*) from public.collection_layout),
               (select count(*) from public.card), (select count(*) from public.binder_activity_event),
               (select count(*) from public.binder_activity_item), (select count(*) from public.binder_activity_coverage)]
    into e_counts;
  res := res || jsonb_build_object('id','99.1','ok', b_counts = e_counts and current_user = session_user,
    'detail','resíduo zero (8 tabelas) e papel restaurado');
  end if;

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

/*
Desempenho (README §10.3) — METAS, não aceite: volume sintético de 100.000
eventos num fichário + 200.000 em 20 outros, todos de um titular efêmero,
inseridos com privilégio e desfeitos pela sentinela MS860P. Mede a primeira
página e uma página por cursor (EXPLAIN ANALYZE). Dois PASS/FAIL objetivos:
o plano usa ix_bae_owner_layout_time e não faz Seq Scan na tabela de eventos.
Os tempos saem como MEASURE e são comparados à meta P2 (≤ 50 ms) no relatório.
*/
create or replace function pg_temp.wh_5860_perf()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
declare
  u_p uuid := gen_random_uuid();
  k_main uuid := gen_random_uuid();
  v_plan text; v_line text; t_first numeric; t_next numeric;
  v_ts timestamptz; v_id bigint;
  out_rows jsonb := '[]'::jsonb; r jsonb; cnt integer := 0;
begin
  begin
    insert into auth.users (id, aud, role, email, created_at, updated_at)
    values (u_p, 'authenticated', 'authenticated', 'wh5860-p-'||substr(u_p::text,1,8)||'@example.invalid', now(), now());

    insert into public.binder_activity_event (owner_user_id, layout_key, occurred_at, actor_user_id, event_type, source)
    select u_p, k_main, now() - (g || ' seconds')::interval, u_p, 'CARD_MOVED', 'FICHARIO'
    from generate_series(1, 100000) g;
    insert into public.binder_activity_item (event_id, ordinal, item_kind, effect, card_name, from_page, from_row, from_col, to_page, to_row, to_col)
    select e.id, 1, 'CARD', 'MOVED', 'P', 1, 1, 1, 1, 1, 2 from public.binder_activity_event e where e.layout_key = k_main;
    insert into public.binder_activity_event (owner_user_id, layout_key, occurred_at, actor_user_id, event_type, source)
    select u_p, ('00000000-0000-4000-8000-' || lpad((g % 20)::text, 12, '0'))::uuid,
           now() - (g || ' seconds')::interval, u_p, 'CARD_MOVED', 'FICHARIO'
    from generate_series(1, 200000) g;
    analyze public.binder_activity_event;
    analyze public.binder_activity_item;

    perform pg_temp.wh5860_claims(u_p);
    v_plan := '';
    for v_line in execute format('explain (analyze, format text) select * from public.get_my_binder_activity(%L::uuid)', k_main) loop
      v_plan := v_plan || v_line || E'\n';
    end loop;
    t_first := substring(v_plan from 'Execution Time: ([0-9.]+) ms')::numeric;

    select x.occurred_at, x.event_id into v_ts, v_id
    from public.get_my_binder_activity(k_main, null, null, null, 20) x order by x.occurred_at asc, x.event_id asc limit 1;
    for v_line in execute format(
      'explain (analyze, format text) select * from public.get_my_binder_activity(%L::uuid, null, %L::timestamptz, %s, 20)',
      k_main, v_ts, v_id) loop
      null;
    end loop;
    v_plan := '';
    for v_line in execute format(
      'explain (analyze, format text) select e.id from public.binder_activity_event e where e.owner_user_id = %L and e.layout_key = %L and (e.occurred_at, e.id) < (%L::timestamptz, %s) order by e.occurred_at desc, e.id desc limit 20',
      u_p, k_main, v_ts, v_id) loop
      v_plan := v_plan || v_line || E'\n';
    end loop;
    t_next := substring(v_plan from 'Execution Time: ([0-9.]+) ms')::numeric;

    out_rows := out_rows || jsonb_build_object('id','P.1','st','MEASURE','d','primeira página (função completa, 100k eventos no fichário): ' || coalesce(t_first::text,'?') || ' ms — meta P2 ≤ 50 ms');
    out_rows := out_rows || jsonb_build_object('id','P.2','st','MEASURE','d','página por cursor (consulta-base): ' || coalesce(t_next::text,'?') || ' ms — meta P2 ≤ 50 ms');
    out_rows := out_rows || jsonb_build_object('id','P.3','st', case when v_plan ~ 'ix_bae_owner_layout_time' then 'PASS' else 'FAIL' end,
      'd','cursor usa ix_bae_owner_layout_time');
    out_rows := out_rows || jsonb_build_object('id','P.4','st', case when v_plan !~ 'Seq Scan on binder_activity_event' then 'PASS' else 'FAIL' end,
      'd','sem Seq Scan na tabela de eventos');

    raise exception 'MS860P' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MS860P' then
      out_rows := out_rows || jsonb_build_object('id','X.1','st','FAIL','d','erro inesperado: '||sqlstate||' '||sqlerrm);
    end if;
  end;
  perform pg_temp.wh5860_claims(null);
  out_rows := out_rows || jsonb_build_object('id','99.P','st',
    case when not exists (select 1 from auth.users where id = u_p) then 'PASS' else 'FAIL' end, 'd','volume sintético desfeito');

  for r in select * from jsonb_array_elements(out_rows) loop
    cnt := cnt + 1; seq := cnt; check_id := r ->> 'id'; status := r ->> 'st'; detail := r ->> 'd';
    return next;
  end loop;
end;
$fn$;
