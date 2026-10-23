/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5851 - Harness P2-SHARED-BINDER (5229/5230): fichário
              compartilhado — estrutura, outro usuário, coleção não
              participante, vínculo duplicado, posições, reservas,
              desmontagem bloqueada, exclusão, desassociação e resíduo zero
Versão......: 1.1 (2026-10-23, P2-SHARED-BINDER-AUDIT-CORRECTION-01: 5.4–5.7)
              1.0 (2026-10-23, P2-SHARED-BINDER-PROPOSAL-01)
Status......: PROPOSTA — NÃO EXECUTADA. Executar só com autorização de
              Fabrício, DEPOIS de 5229 → 5230 aplicadas no ambiente-alvo.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-23

Protocolo (o mesmo da 5850): um único statement, usuários efêmeros A e B,
catálogo SINTÉTICO mínimo (1 Set, 1 carta, 1 variante STANDARD) criado
como dono do banco; a sentinela MS851 desfaz tudo; 99.1 prova resíduo zero.

  select * from pg_temp.wh_5851_validate();

Fixture (tudo do usuário pelas RPCs canônicas):
  A — locais BIN (BINDER), BIN2 (BINDER), BOX (sem tipo).
      CO  Livre (BIN) com o1 → fichário 2×2 (proprietária; o1 no 1º bolso)
      CG  Livre (BIN) com g1, g2 → convidada
      CE  Livre (BIN) vazia → convidada para a prova de exclusão
      CX  Livre (BOX) com x1 → outro local (não participante)
      CH  Livre (BIN2) com h1 → fichário próprio 2×2
  B — local LB (BINDER); CB Livre com b1 e fichário 2×2.

Seções:
  0  estrutura: tabela + RLS + sem DML; colunas; gatilhos; RPCs (definer,
     search_path vazio, EXECUTE só authenticated, helper sem EXECUTE);
     assinatura antiga de set_slot_expected_content removida
  1  segurança: anon 42501; outro usuário não lê nem associa (não enumera)
  2  descoberta e associação: candidatos; NOT_SAME_LOCATION; HAS_OWN_BINDER;
     SELF; ATTACHED; ALREADY_ATTACHED; ALREADY_IN_BINDER; cabeçalho GUEST;
     montar fichário próprio sendo convidada recusado; nada de bolso escrito
  3  posições: convidada posiciona; não participante e outro usuário
     recusados; mover/trocar entre coleções; leitura pelas duas coleções;
     cartas fora dos bolsos; alocações intactas
  4  reservas: atribuída à coleção da carta; não participante recusada;
     reserva explícita da proprietária
  5  desmontagem recusada antes de remover e prévia com convidadas;
     convidada não desmonta; desalocação da carta convidada (sem órfã,
     reserva coerente); convidada arquivada não posiciona nem move;
     delete_collection da convidada recusado (BINDER_GUEST)
  6  desassociação: travas exigem confirmação; token desatualizado;
     DETACHED remove só o da convidada; proprietária intacta; repetição
  99 resíduo zero e papel restaurado

Limitações declaradas:
  L1 SET LOCAL ROLE prova o banco, não o JWT do PostgREST.
  L2 Um único statement não tem duas sessões: espera, lock_timeout e
     deadlock NÃO são exercitados. As provas de duas sessões são o roteiro
     manual K1–K4 do README desta pasta.
================================================================
*/

create or replace function pg_temp.wh_5851_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  f_att  oid := to_regprocedure('public.attach_my_collection_to_binder(uuid, uuid)');
  f_snp  oid := to_regprocedure('public.collection_binder_detach_snapshot(uuid)');
  f_dpv  oid := to_regprocedure('public.preview_my_collection_binder_detach(uuid)');
  f_det  oid := to_regprocedure('public.detach_my_collection_from_binder(uuid, text, boolean)');
  f_cand oid := to_regprocedure('public.list_my_binder_join_candidates(uuid)');
  f_unp  oid := to_regprocedure('public.get_my_collection_binder_unplaced(uuid, integer, integer)');
  f_get  oid := to_regprocedure('public.get_my_collection_binder(uuid)');
  f_pgs  oid := to_regprocedure('public.get_my_collection_binder_pages(uuid, integer, integer)');
  f_sec  oid := to_regprocedure('public.set_slot_expected_content(uuid, uuid, uuid, uuid, uuid)');
  f_asg  oid := to_regprocedure('public.assign_card_to_slot(uuid, uuid)');
  f_del  oid := to_regprocedure('public.delete_collection(uuid)');
  u_a uuid := gen_random_uuid();
  u_b uuid := gen_random_uuid();
  v_sfx text := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  v_game uuid; v_pt uuid; v_rar uuid; v_cat uuid; v_std uuid;
  v_exp uuid; v_set uuid; k1 uuid; k1s uuid;
  v_inv_a uuid; v_inv_b uuid; v_ids uuid[];
  o1 uuid; g1 uuid; g2 uuid; x1 uuid; h1 uuid; b1 uuid;
  v_bin uuid; v_bin2 uuid; v_box uuid; v_lb uuid;
  v_co uuid; v_cg uuid; v_ce uuid; v_cx uuid; v_ch uuid; v_cb uuid;
  l_o uuid; l_h uuid; l_b uuid;
  s_o1 uuid; s_o2 uuid; s_o3 uuid; s_o4 uuid; s_b1 uuid;
  a_o1 uuid; a_g1 uuid; a_g2 uuid; a_x1 uuid; a_b1 uuid;
  p record; o record; d record;
  v_ok boolean; v_err text; v_hint text; v_tok text; n integer; n2 integer;
  b_counts bigint[]; e_counts bigint[];
  res jsonb := '[]'::jsonb; r jsonb; cnt integer := 0; passes integer := 0;
  v_expected integer := 47;
begin
  -- 0. Estrutura ---------------------------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    to_regclass('public.collection_layout_guest') is not null
    and f_att is not null and f_snp is not null and f_dpv is not null and f_det is not null
    and f_cand is not null and f_unp is not null and f_get is not null and f_pgs is not null
    and f_sec is not null and f_asg is not null and f_del is not null
    and to_regprocedure('public.set_slot_expected_content(uuid, uuid, uuid, uuid)') is null,
    'detail','5229/5230 presentes; assinatura de 4 argumentos de set_slot_expected_content removida');
  if (res -> 0 ->> 'ok')::boolean is not true then
    res := res || jsonb_build_object('id','X.0','ok', false, 'detail','aplique 5229 → 5230 antes deste harness');
  else
  res := res || jsonb_build_object('id','0.2','ok',
    (select c.relrowsecurity from pg_class c where c.oid = 'public.collection_layout_guest'::regclass)
    and has_table_privilege('authenticated', 'public.collection_layout_guest', 'SELECT')
    and not has_table_privilege('authenticated', 'public.collection_layout_guest', 'INSERT')
    and not has_table_privilege('authenticated', 'public.collection_layout_guest', 'UPDATE')
    and not has_table_privilege('authenticated', 'public.collection_layout_guest', 'DELETE')
    and not has_table_privilege('anon', 'public.collection_layout_guest', 'SELECT')
    and exists (select 1 from information_schema.columns where table_schema = 'public'
                and table_name = 'collection_layout_slot_expected_content' and column_name = 'collection_id'),
    'detail','tabela de convidadas com RLS, só SELECT para authenticated; coluna collection_id na reserva');
  res := res || jsonb_build_object('id','0.3','ok',
    (select count(*) from pg_trigger t where not t.tgisinternal and t.tgname in (
       'trg_collection_layout_guest_integrity','trg_collection_layout_owner_not_guest',
       'trg_collection_layout_delete_without_guests','trg_expected_content_participant')) = 4
    and (select bool_and(not has_function_privilege('authenticated', q.oid, 'EXECUTE'))
         from pg_proc q where q.proname in ('enforce_collection_layout_guest_integrity','enforce_collection_layout_owner_not_guest',
                                            'enforce_collection_layout_delete_without_guests','enforce_expected_content_participant')),
    'detail','quatro gatilhos novos; funções de gatilho sem EXECUTE para a API');
  res := res || jsonb_build_object('id','0.4','ok',
    (select bool_and(q.prosecdef and q.proconfig @> array['search_path=""']
                     and has_function_privilege('authenticated', q.oid, 'EXECUTE')
                     and not has_function_privilege('anon', q.oid, 'EXECUTE'))
     from pg_proc q where q.oid in (f_att, f_dpv, f_det, f_cand, f_unp, f_get, f_pgs, f_sec, f_asg, f_del))
    and not exists (select 1 from pg_proc q, aclexplode(q.proacl) x
                    where q.oid in (f_att, f_dpv, f_det, f_cand, f_unp, f_get, f_pgs, f_sec, f_asg, f_del) and x.grantee = 0)
    and (select not q.prosecdef from pg_proc q where q.oid = f_snp)
    and not has_function_privilege('authenticated', f_snp, 'EXECUTE')
    and (select bool_and(q.proconfig @> array['lock_timeout=5s']) from pg_proc q where q.oid in (f_att, f_det)),
    'detail','RPCs: SECURITY DEFINER, search_path vazio, EXECUTE só authenticated; retrato interno sem EXECUTE; attach/detach com lock_timeout 5s');

  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.storage_container), (select count(*) from public.collection_layout),
               (select count(*) from public.collection_layout_slot_assignment),
               (select count(*) from public.collection_layout_slot_expected_content),
               (select count(*) from public.collection_layout_guest), (select count(*) from public.card)]
    into b_counts;

  begin
    -- F. Catálogo sintético e usuários ------------------------------------------------
    select g.id into v_game from public.game g where g.code = 'POKEMON';
    select l.id into v_pt from public.language l where l.code = 'pt-BR';
    select t.id into v_std from public.card_variant_type t where t.game_id = v_game and t.code = 'STANDARD';
    select c0.rarity_id, c0.category_id into v_rar, v_cat
    from public.card c0 join public.card_set cs0 on cs0.id = c0.card_set_id
    join public.expansion e0 on e0.id = cs0.expansion_id
    where e0.game_id = v_game limit 1;
    if v_game is null or v_pt is null or v_std is null or v_rar is null then
      res := res || jsonb_build_object('id','F.1','ok', false, 'detail','pré-requisitos de catálogo ausentes');
      raise exception 'MS851' using errcode = 'P0001';
    end if;
    insert into public.expansion (game_id, code, name, release_order)
    values (v_game, 'SHB_' || v_sfx, 'SHB Harness ' || v_sfx,
            (select coalesce(max(x.release_order), 0) + 1000 from public.expansion x where x.game_id = v_game))
    returning id into v_exp;
    insert into public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_exp, 'SHB' || v_sfx, 'SHB Set ' || v_sfx, 'REGULAR', 1, 1, 1) returning id into v_set;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '1', 1, 'SHB K1', true) returning id into k1;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default)
    values (k1, v_std, 1, true) returning id into k1s;

    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    values (u_a, 'authenticated', 'authenticated', 'wh5851-a-'||lower(v_sfx)||'@example.invalid',
            jsonb_build_object('username', 'wh5851a_'||lower(v_sfx), 'display_name', 'WH 5851 A'), now(), now()),
           (u_b, 'authenticated', 'authenticated', 'wh5851-b-'||lower(v_sfx)||'@example.invalid',
            jsonb_build_object('username', 'wh5851b_'||lower(v_sfx), 'display_name', 'WH 5851 B'), now(), now());
    select i.id into v_inv_a from public.inventory i where i.owner_user_id = u_a;
    select i.id into v_inv_b from public.inventory i where i.owner_user_id = u_b;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, created_at) values
      (k1s, v_pt, v_inv_a, now() - interval '6 min'), (k1s, v_pt, v_inv_a, now() - interval '5 min'),
      (k1s, v_pt, v_inv_a, now() - interval '4 min'), (k1s, v_pt, v_inv_a, now() - interval '3 min'),
      (k1s, v_pt, v_inv_a, now() - interval '2 min');
    select array_agg(pc.id order by pc.created_at) into v_ids from public.physical_card pc where pc.inventory_id = v_inv_a;
    o1 := v_ids[1]; g1 := v_ids[2]; g2 := v_ids[3]; x1 := v_ids[4]; h1 := v_ids[5];
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (k1s, v_pt, v_inv_b) returning id into b1;

    -- B
    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select x.storage_container_id into v_lb from public.create_my_storage_container(gen_random_uuid(), 'LB 5851', 'BINDER') x;
    select x.collection_id into v_cb from public.create_my_free_collection(gen_random_uuid(), 'CB 5851', v_lb) x;
    perform public.allocate_physical_cards_to_collection(v_cb, array[b1]);
    select * into p from public.preview_my_collection_binder(v_cb, 2, 2, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_cb, 2, 2, 'PRINCIPAL_ONLY', p.plan_token);

    -- A
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select x.storage_container_id into v_bin  from public.create_my_storage_container(gen_random_uuid(), 'BIN 5851', 'BINDER') x;
    select x.storage_container_id into v_bin2 from public.create_my_storage_container(gen_random_uuid(), 'BIN2 5851', 'BINDER') x;
    select x.storage_container_id into v_box  from public.create_my_storage_container(gen_random_uuid(), 'BOX 5851', null) x;
    select x.collection_id into v_co from public.create_my_free_collection(gen_random_uuid(), 'CO 5851', v_bin) x;
    select x.collection_id into v_cg from public.create_my_free_collection(gen_random_uuid(), 'CG 5851', v_bin) x;
    select x.collection_id into v_ce from public.create_my_free_collection(gen_random_uuid(), 'CE 5851', v_bin) x;
    select x.collection_id into v_cx from public.create_my_free_collection(gen_random_uuid(), 'CX 5851', v_box) x;
    select x.collection_id into v_ch from public.create_my_free_collection(gen_random_uuid(), 'CH 5851', v_bin2) x;
    perform public.allocate_physical_cards_to_collection(v_co, array[o1]);
    perform public.allocate_physical_cards_to_collection(v_cg, array[g1, g2]);
    perform public.allocate_physical_cards_to_collection(v_cx, array[x1]);
    perform public.allocate_physical_cards_to_collection(v_ch, array[h1]);
    select * into p from public.preview_my_collection_binder(v_co, 2, 2, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_co, 2, 2, 'PRINCIPAL_ONLY', p.plan_token);
    select * into p from public.preview_my_collection_binder(v_ch, 2, 2, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_ch, 2, 2, 'PRINCIPAL_ONLY', p.plan_token);
    execute 'reset role';

    select l.id into l_o from public.collection_layout l where l.collection_id = v_co;
    select l.id into l_h from public.collection_layout l where l.collection_id = v_ch;
    select l.id into l_b from public.collection_layout l where l.collection_id = v_cb;
    select array_agg(s.id order by s.row_index, s.column_index) into v_ids
    from public.collection_layout_slot s join public.collection_layout_page pg on pg.id = s.page_id
    where pg.layout_id = l_o and pg.page_number = 1;
    s_o1 := v_ids[1]; s_o2 := v_ids[2]; s_o3 := v_ids[3]; s_o4 := v_ids[4];
    select s.id into s_b1 from public.collection_layout_slot s join public.collection_layout_page pg on pg.id = s.page_id
    where pg.layout_id = l_b order by pg.page_number, s.row_index, s.column_index limit 1;
    select ca.id into a_o1 from public.collection_allocation ca where ca.physical_card_id = o1;
    select ca.id into a_g1 from public.collection_allocation ca where ca.physical_card_id = g1;
    select ca.id into a_g2 from public.collection_allocation ca where ca.physical_card_id = g2;
    select ca.id into a_x1 from public.collection_allocation ca where ca.physical_card_id = x1;
    select ca.id into a_b1 from public.collection_allocation ca where ca.physical_card_id = b1;
    res := res || jsonb_build_object('id','F.1','ok',
      l_o is not null and l_h is not null and l_b is not null and s_o4 is not null
      and exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = s_o1 and a.collection_allocation_id = a_o1),
      'detail','fixture: fichários CO, CH (A) e CB (B); o1 no 1º bolso de CO');

    -- 1. Segurança ------------------------------------------------------------------------
    execute 'set local role anon';
    v_ok := false;
    begin perform count(*) from public.attach_my_collection_to_binder(v_cg, l_o);
    exception when insufficient_privilege then v_ok := true; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.1','ok', v_ok, 'detail','anon não executa attach (42501)');

    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    v_err := null;
    begin perform count(*) from public.attach_my_collection_to_binder(v_cb, l_o);
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','1.2','ok', v_err = 'BINDER_NOT_FOUND',
      'detail','B associa a própria coleção ao fichário de A → BINDER_NOT_FOUND (não enumera): ' || coalesce(v_err, 'sem erro'));
    v_err := null;
    begin perform count(*) from public.list_my_binder_join_candidates(v_cg);
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','1.3','ok', v_err = 'COLLECTION_NOT_FOUND',
      'detail','B lista candidatos de coleção de A → COLLECTION_NOT_FOUND: ' || coalesce(v_err, 'sem erro'));
    v_err := null;
    begin perform count(*) from public.assign_card_to_slot(s_b1, a_o1);
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','1.4','ok', v_err like 'collection allocation not found%',
      'detail','B posiciona carta de A no próprio fichário → recusado sem enumerar: ' || coalesce(v_err, 'sem erro'));
    execute 'reset role';

    -- 2. Descoberta e associação ------------------------------------------------------------
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';

    select count(*), min(c.layout_id::text) into n, v_tok from public.list_my_binder_join_candidates(v_cg) c;
    select count(*) into n2 from public.list_my_binder_join_candidates(v_cx);
    res := res || jsonb_build_object('id','2.1','ok', n = 1 and v_tok = l_o::text and n2 = 0,
      'detail','candidatos: CG vê só o fichário de CO (mesmo local); CX (caixa) não vê nenhum');
    select * into o from public.get_my_collection_binder(v_cg);
    res := res || jsonb_build_object('id','2.2','ok',
      not o.has_binder and o.binder_role is null and o.join_candidate_count = 1 and o.can_create,
      'detail','cabeçalho de CG antes: sem fichário, 1 candidato, montar próprio ainda possível');

    v_err := null; begin perform count(*) from public.attach_my_collection_to_binder(v_cx, l_o);
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','2.3','ok', v_err = 'NOT_SAME_LOCATION', 'detail','CX (outro local) → ' || coalesce(v_err, 'sem erro'));
    v_err := null; begin perform count(*) from public.attach_my_collection_to_binder(v_ch, l_o);
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','2.4','ok', v_err = 'COLLECTION_HAS_OWN_BINDER', 'detail','CH (proprietária de outro fichário) → ' || coalesce(v_err, 'sem erro'));
    v_err := null; begin perform count(*) from public.attach_my_collection_to_binder(v_co, l_o);
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','2.5','ok', v_err = 'BINDER_SELF', 'detail','proprietária no próprio fichário → ' || coalesce(v_err, 'sem erro'));

    select count(*) into n from public.collection_layout_slot_assignment a
    join public.collection_layout_slot s on s.id = a.slot_id join public.collection_layout_page pg on pg.id = s.page_id
    where pg.layout_id = l_o;
    select * into o from public.attach_my_collection_to_binder(v_cg, l_o);
    select count(*) into n2 from public.collection_layout_slot_assignment a
    join public.collection_layout_slot s on s.id = a.slot_id join public.collection_layout_page pg on pg.id = s.page_id
    where pg.layout_id = l_o;
    res := res || jsonb_build_object('id','2.6','ok', o.outcome = 'ATTACHED' and o.owner_collection_id = v_co and n = n2,
      'detail','CG associada: ATTACHED, nenhum bolso escrito (D3)');
    select * into o from public.attach_my_collection_to_binder(v_cg, l_o);
    res := res || jsonb_build_object('id','2.7','ok', o.outcome = 'ALREADY_ATTACHED', 'detail','repetição idempotente → ALREADY_ATTACHED');
    v_err := null; begin perform count(*) from public.attach_my_collection_to_binder(v_cg, l_h);
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','2.8','ok', v_err = 'COLLECTION_ALREADY_IN_BINDER', 'detail','CG em um segundo fichário → ' || coalesce(v_err, 'sem erro'));

    select * into o from public.get_my_collection_binder(v_cg);
    res := res || jsonb_build_object('id','2.9','ok',
      o.has_binder and o.binder_role = 'GUEST' and o.layout_id = l_o and o.owner_collection_id = v_co
      and o.participant_count = 2 and o.own_filled_count = 0 and o.own_unplaced_count = 2
      and not o.can_create and o.is_editable,
      'detail','cabeçalho de CG: GUEST do fichário de CO, 2 participantes, 2 cartas fora dos bolsos, não pode montar outro');
    select * into o from public.get_my_collection_binder(v_co);
    res := res || jsonb_build_object('id','2.10','ok', o.binder_role = 'OWNER' and o.participant_count = 2 and o.own_filled_count = 1,
      'detail','cabeçalho de CO: OWNER, 2 participantes');

    v_err := null;
    begin
      select * into p from public.preview_my_collection_binder(v_cg, 2, 2, 'PRINCIPAL_ONLY');
      perform count(*) from public.create_my_collection_binder(v_cg, 2, 2, 'PRINCIPAL_ONLY', p.plan_token);
    exception when others then v_err := sqlerrm; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','2.11','ok',
      v_err like '%COLLECTION_IS_BINDER_GUEST%'
      and not exists (select 1 from public.collection_layout l where l.collection_id = v_cg),
      'detail','convidada não monta fichário próprio (gatilho) — nada gravado: ' || coalesce(v_err, 'sem erro'));
    v_err := null;
    begin insert into public.collection_layout_guest (collection_id, layout_id) values (v_ch, l_o);
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','2.12','ok', v_err = 'COLLECTION_HAS_OWN_BINDER',
      'detail','escrita direta (dono do banco) de proprietária como convidada barrada pelo gatilho: ' || coalesce(v_err, 'sem erro'));

    -- 3. Posições ------------------------------------------------------------------------------
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select * into o from public.assign_card_to_slot(s_o2, a_g1);
    res := res || jsonb_build_object('id','3.1','ok', o.operation = 'ADD', 'detail','carta da convidada posicionada no fichário compartilhado');
    v_err := null; begin perform count(*) from public.assign_card_to_slot(s_o3, a_x1);
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','3.2','ok', v_err like 'collection allocation not found%',
      'detail','carta de coleção não participante (CX) recusada: ' || coalesce(v_err, 'sem erro'));
    v_err := null; begin perform count(*) from public.assign_card_to_slot(s_o3, a_b1);
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','3.3','ok', v_err like 'collection allocation not found%',
      'detail','carta de outro usuário recusada sem enumerar: ' || coalesce(v_err, 'sem erro'));
    select * into o from public.move_slot_assignment(s_o2, s_o3);
    select * into d from public.move_slot_assignment(s_o3, s_o1);
    res := res || jsonb_build_object('id','3.4','ok',
      exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = s_o1 and a.collection_allocation_id = a_g1)
      and exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = s_o3 and a.collection_allocation_id = a_o1),
      'detail','mover e trocar entre cartas de coleções diferentes no mesmo fichário');
    select count(*) filter (where pp.present_collection_id = v_cg), count(*) filter (where pp.present_collection_id = v_co)
      into n, n2 from public.get_my_collection_binder_pages(v_co, 1, 1) pp;
    res := res || jsonb_build_object('id','3.5','ok', n = 1 and n2 = 1,
      'detail','leitura pela proprietária mostra a carta de cada coleção com present_collection_id');
    select count(*) into n from public.get_my_collection_binder_pages(v_cg, 1, 1) pp where pp.present_card_id is not null;
    res := res || jsonb_build_object('id','3.6','ok', n = 2, 'detail','a convidada abre o mesmo fichário e vê as duas cartas');
    select count(*), max(u.total_count) into n, n2 from public.get_my_collection_binder_unplaced(v_cg, 48, 0) u;
    res := res || jsonb_build_object('id','3.7','ok', n = 1 and n2 = 1 and exists (
        select 1 from public.get_my_collection_binder_unplaced(v_cg, 48, 0) u where u.collection_allocation_id = a_g2),
      'detail','cartas da convidada fora dos bolsos: só g2');
    execute 'reset role';
    res := res || jsonb_build_object('id','3.8','ok',
      (select count(*) from public.collection_allocation ca where ca.collection_id = v_cg) = 2
      and (select count(*) from public.collection_allocation ca where ca.collection_id = v_co) = 1,
      'detail','alocações das duas coleções intactas (D2)');

    -- 4. Reservas -------------------------------------------------------------------------------
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select * into o from public.set_slot_expected_content(s_o1, k1);
    res := res || jsonb_build_object('id','4.1','ok', o.collection_id = v_cg,
      'detail','reserva sem coleção explícita no bolso de g1 pertence à convidada (D8)');
    v_err := null; begin perform count(*) from public.set_slot_expected_content(s_o4, k1, null, null, v_cx);
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','4.2','ok', v_err like 'collection not found or not a participant%',
      'detail','reserva para coleção não participante recusada: ' || coalesce(v_err, 'sem erro'));
    select * into o from public.set_slot_expected_content(s_o4, k1, null, null, v_co);
    res := res || jsonb_build_object('id','4.3','ok', o.collection_id = v_co, 'detail','reserva explícita da proprietária');
    select count(*) into n from public.get_my_collection_binder_pages(v_co, 1, 1) pp
      where (pp.slot_id = s_o1 and pp.expected_collection_id = v_cg) or (pp.slot_id = s_o4 and pp.expected_collection_id = v_co);
    res := res || jsonb_build_object('id','4.4','ok', n = 2, 'detail','leitura expõe expected_collection_id');

    -- 5. Desmontagem e exclusão ------------------------------------------------------------------
    select * into p from public.preview_my_collection_binder_dismantle(v_co);
    v_err := null; begin perform count(*) from public.dismantle_my_collection_binder(v_co, p.dismantle_token);
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','5.1','ok', v_err = 'BINDER_HAS_GUESTS'
      and exists (select 1 from public.collection_layout l where l.id = l_o),
      'detail','desmontagem bloqueada com convidada (D7), nada removido: ' || coalesce(v_err, 'sem erro'));
    res := res || jsonb_build_object('id','5.4','ok', p.guest_count = 1 and p.blocked_reason = 'BINDER_HAS_GUESTS',
      'detail','prévia da desmontagem informa convidadas (guest_count, blocked_reason)');
    select * into p from public.preview_my_collection_binder_dismantle(v_cg);
    v_err := null; begin perform count(*) from public.dismantle_my_collection_binder(v_cg, 'd1:' || repeat('a', 64));
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','5.5','ok', p.blocked_reason = 'COLLECTION_IS_BINDER_GUEST' and v_err = 'COLLECTION_IS_BINDER_GUEST',
      'detail','convidada não desmonta o fichário da proprietária e é orientada a desassociar: ' || coalesce(v_err, 'sem erro'));

    -- 5b. Desalocação da carta convidada (5047 inalterada) --------------------------------
    perform count(*) from public.assign_card_to_slot(s_o2, a_g2);
    perform count(*) from public.set_slot_expected_content(s_o2, k1);
    perform count(*) from public.deallocate_physical_cards_from_collection(v_cg, array[g2]);
    execute 'reset role';
    res := res || jsonb_build_object('id','5.6','ok',
      not exists (select 1 from public.collection_layout_slot_assignment a where a.collection_allocation_id = a_g2)
      and not exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = s_o2)
      and exists (select 1 from public.collection_layout_slot_expected_content e where e.slot_id = s_o2 and e.collection_id = v_cg)
      and exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = s_o1 and a.collection_allocation_id = a_g1),
      'detail','desalocar carta posicionada da convidada: posição removida em cascata (sem órfã); a reserva continua da convidada (participante); demais posições intactas');
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.clear_slot_expected_content(array[s_o2]);
    perform public.allocate_physical_cards_to_collection(v_cg, array[g2]);
    execute 'reset role';
    select ca.id into a_g2 from public.collection_allocation ca where ca.physical_card_id = g2;
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';

    -- 5c. Convidada arquivada: entrada (assign) e movimento (gatilho) recusados ------------
    perform count(*) from public.archive_collection(v_cg);
    v_err := null; begin perform count(*) from public.assign_card_to_slot(s_o2, a_g2);
    exception when others then v_err := sqlerrm; end;
    v_tok := v_err;
    v_err := null; begin perform count(*) from public.move_slot_assignment(s_o1, s_o2);
    exception when others then v_err := sqlerrm; end;
    perform count(*) from public.reactivate_collection(v_cg);
    res := res || jsonb_build_object('id','5.7','ok', v_tok = 'COLLECTION_ARCHIVED' and v_err = 'COLLECTION_ARCHIVED'
      and exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = s_o1 and a.collection_allocation_id = a_g1),
      'detail','convidada arquivada: posicionar (trava antes da alocação) e mover (gatilho sem trava) recusados; nada mudou');

    perform count(*) from public.attach_my_collection_to_binder(v_ce, l_o);
    v_err := null; v_hint := null;
    begin perform count(*) from public.delete_collection(v_ce);
    exception when others then get stacked diagnostics v_err = message_text, v_hint = pg_exception_hint; end;
    res := res || jsonb_build_object('id','5.2','ok', v_hint = 'BINDER_GUEST',
      'detail','excluir coleção convidada exige desassociar antes (BINDER_GUEST): ' || coalesce(v_err, 'sem erro'));
    select * into p from public.preview_my_collection_binder_detach(v_ce);
    select * into d from public.detach_my_collection_from_binder(v_ce, p.detach_token, false);
    res := res || jsonb_build_object('id','5.3','ok', d.outcome = 'DETACHED' and d.assignments_removed = 0,
      'detail','convidada vazia desassociada');

    -- 6. Desassociação de CG -------------------------------------------------------------------
    perform count(*) from public.set_slot_lock(array[s_o1], true);
    select * into p from public.preview_my_collection_binder_detach(v_cg);
    res := res || jsonb_build_object('id','6.1','ok',
      p.assignments_count = 1 and p.reservations_count = 1 and p.locked_count = 1 and p.owner_collection_id = v_co,
      'detail','prévia: 1 posição, 1 reserva e 1 bolso fixado da convidada');
    v_err := null; begin perform count(*) from public.detach_my_collection_from_binder(v_cg, p.detach_token, false);
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','6.2','ok', v_err = 'LOCKED_SLOTS_REQUIRE_CONFIRMATION'
      and exists (select 1 from public.collection_layout_guest g where g.collection_id = v_cg),
      'detail','sem confirmação o bolso fixado bloqueia (D6), nada muda: ' || coalesce(v_err, 'sem erro'));
    v_tok := p.detach_token;
    perform count(*) from public.assign_card_to_slot(s_o2, a_g2);
    v_err := null; begin perform count(*) from public.detach_my_collection_from_binder(v_cg, v_tok, true);
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','6.3','ok', v_err = 'DETACH_PLAN_CHANGED',
      'detail','token da prévia desatualizado após nova posição → ' || coalesce(v_err, 'sem erro'));
    select * into p from public.preview_my_collection_binder_detach(v_cg);
    select * into d from public.detach_my_collection_from_binder(v_cg, p.detach_token, true);
    res := res || jsonb_build_object('id','6.4','ok',
      d.outcome = 'DETACHED' and d.assignments_removed = 2 and d.reservations_removed = 1 and d.locks_released = 1,
      'detail','DETACHED: 2 posições e 1 reserva da convidada removidas, 1 bolso solto');
    execute 'reset role';
    res := res || jsonb_build_object('id','6.5','ok',
      exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = s_o3 and a.collection_allocation_id = a_o1)
      and exists (select 1 from public.collection_layout_slot_expected_content e where e.slot_id = s_o4 and e.collection_id = v_co)
      and not exists (select 1 from public.collection_layout_slot s where s.id = s_o1 and s.locked)
      and (select count(*) from public.collection_allocation ca where ca.collection_id = v_cg) = 2
      and not exists (select 1 from public.collection_layout_guest g where g.collection_id = v_cg),
      'detail','proprietária intacta (posição e reserva); convidada mantém as 2 alocações (D2, D5)');
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select * into d from public.detach_my_collection_from_binder(v_cg, p.detach_token, true);
    select * into o from public.get_my_collection_binder(v_cg);
    res := res || jsonb_build_object('id','6.6','ok', d.outcome = 'ALREADY_DETACHED' and not o.has_binder and o.join_candidate_count = 1,
      'detail','repetição → ALREADY_DETACHED; CG volta a ver o fichário como candidato');
    execute 'reset role';

    raise exception 'MS851' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MS851' then
      res := res || jsonb_build_object('id','X.1','ok', false, 'detail','erro inesperado: '||sqlstate||' '||sqlerrm);
    end if;
  end;

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.storage_container), (select count(*) from public.collection_layout),
               (select count(*) from public.collection_layout_slot_assignment),
               (select count(*) from public.collection_layout_slot_expected_content),
               (select count(*) from public.collection_layout_guest), (select count(*) from public.card)]
    into e_counts;
  res := res || jsonb_build_object('id','99.1','ok', b_counts = e_counts and current_user = session_user,
    'detail','resíduo zero (10 tabelas) e papel restaurado');
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
