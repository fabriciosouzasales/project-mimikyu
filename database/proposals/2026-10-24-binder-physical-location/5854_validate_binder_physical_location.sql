/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5854 - Harness BINDER-PHYSICAL-LOCATION (5247–5256):
              fichário = local físico, posição = exemplar
Versão......: 2.0 (2026-10-24, BINDER-PHYSICAL-LOCATION-IMPLEMENTATION-READINESS-01)
Status......: PROPOSTA — NÃO EXECUTADA. NUNCA executar no LIVE (cria
              usuários, catálogo sintético e dados — desfeitos pela
              sentinela, mas proibido no LIVE por convenção). Executar só
              em ambiente descartável, com autorização de Fabrício, DEPOIS
              de TODA a sequência: fase A 5247 → 5255 e fase B 5256 (README §6).
              v2.0: escritores com confirmação (5249 v2), organizar (D1),
              associação pelo local do fichário (5255), proteção de fase B
              (5256) e coexistência/remoção das assinaturas antigas.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-24

Protocolo (o mesmo da 5851/5853): um único statement, usuários efêmeros A
e B, catálogo SINTÉTICO mínimo; a sentinela MS854 desfaz tudo; 99.1 prova
resíduo zero.

  select * from pg_temp.wh_5854_validate();

Fixture (exemplares inseridos já com local; o resto pelas RPCs canônicas):
  A — locais BIN (BINDER) e OTH (BINDER, outro fichário físico).
      CO (proprietária, padrão BIN): o1, o2 (BIN), o3 (OTH).
      CG (convidada, padrão BIN):    g1, g2 (BIN).
      CX (NÃO participante, padrão OTH — o caso Mudkip): x1 (BIN).
      CA (arquivada, padrão BIN):    a1 (BIN).
      CN (ativa, vazia, padrão BIN): destino da transferência.
      sem coleção: n1 (BIN), f1 (OTH).
      Fichário de CO 3×3 PRINCIPAL_ONLY; CG associada.
  B — local LB: CB (b1) com fichário 2×2.

Seções:
  0  estrutura, ACL, ações de FK, versão do plano, assinaturas antigas
  F  montagem (5251) só posiciona cartas guardadas no fichário físico
  1  segurança: anon; B não lê/posiciona/transfere no fichário de A;
     A não posiciona exemplar de B; sem DML direto do cliente
  2  "Cartas disponíveis": elegibilidade por local, filtros de origem,
     ordem, cabeçalho (available_count, own_unplaced_count)
  3  posicionar: outra coleção, sem coleção, arquivada (D1); UNCHANGED;
     CARD_ALREADY_PLACED; fora do local; REPLACE pela convidada; bolso
     travado; escritor legado; UNIQUE no banco; nada de coleção muda
  4  D3: prévia; caminho antigo (5024) recusado pela 5256; sobrecarga sem
     confirmação recusa; organizar (D1): prévia por coleção, recusa sem
     confirmação e tira do bolso com confirmação; bolso travado recusa;
     carta sem bolso move livre; UPDATE direto também recusa
  5  independência coleção × posição: desalocar mantém; realocar mantém e
     a origem exibida acompanha; remover o exemplar cascateia
  6  D2: desassociar mantém posições; convidada perde acesso
  7  exclusão segura da proprietária: recusa direta; transferência
     (ARCHIVED recusa, TRANSFERRED, UNCHANGED, 5136 fora da função);
     desalocar → desassociar → excluir sem perder posições
  8  identidade física imutável; local não deixa de ser BINDER; associação
     e candidatos pelo local do fichário (5255)
  9  participantes depois do fluxo
  99 resíduo zero, fichário de B intacto e papel restaurado

Limitações declaradas:
  L1 SET LOCAL ROLE prova o banco, não o JWT do PostgREST.
  L2 Um statement não tem duas sessões: concorrência real (posicionar ×
     mover de local; desassociar × posicionar) não é exercitada — a ordem
     de travas está documentada nas 5249/5250 e é prova de revisão.
  L3 Imagens e mesclagens exigem arquivos no Storage: não exercitadas
     (gatilhos 5232/5238 inalterados).
  L4 Reservas de convidada: removidas na desassociação exatamente como na
     5229 (regressão coberta pela 5851); aqui só se prova que posições
     ficam.
================================================================
*/

create or replace function pg_temp.wh_5854_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  f_place oid := to_regprocedure('public.place_my_physical_card_in_slot(uuid, uuid, uuid)');
  f_prev  oid := to_regprocedure('public.preview_my_physical_cards_binder_impact(uuid[], uuid)');
  f_sto   oid := to_regprocedure('public.set_physical_cards_storage(uuid, uuid[], boolean)');
  f_tr    oid := to_regprocedure('public.transfer_my_binder_ownership(uuid, uuid)');
  f_un    oid := to_regprocedure('public.get_my_collection_binder_unplaced(uuid, integer, integer, text, uuid)');
  f_hd    oid := to_regprocedure('public.get_my_collection_binder(uuid)');
  f_pg    oid := to_regprocedure('public.get_my_collection_binder_pages(uuid, integer, integer)');
  f_par   oid := to_regprocedure('public.get_my_binder_participants(uuid)');
  f_det   oid := to_regprocedure('public.detach_my_collection_from_binder(uuid, text, boolean)');
  f_org   oid := to_regprocedure('public.organize_my_collection_storage(uuid, uuid, text, integer, text, boolean)');
  f_cimp  oid := to_regprocedure('public.preview_my_collection_storage_binder_impact(uuid, uuid, text)');
  f_att   oid := to_regprocedure('public.attach_my_collection_to_binder(uuid, uuid)');
  u_a uuid := gen_random_uuid();
  u_b uuid := gen_random_uuid();
  v_sfx text := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  v_game uuid; v_pt uuid; v_rar uuid; v_cat uuid; v_std uuid;
  v_exp uuid; v_set uuid; k1 uuid; k1s uuid;
  v_inv_a uuid; v_inv_b uuid;
  v_bin uuid; v_oth uuid; v_lb uuid;
  o1 uuid; o2 uuid; o3 uuid; g1 uuid; g2 uuid; x1 uuid; a1 uuid; n1 uuid; f1 uuid; b1 uuid;
  v_co uuid; v_cg uuid; v_cx uuid; v_ca uuid; v_cn uuid; v_cb uuid; v_cz uuid; v_cy uuid;
  l_o uuid; l_b uuid; fs uuid[]; v_ids uuid[];
  p record; w record; h record; q record;
  v_ok boolean; v_err text; v_state text; v_txt text; v_ts timestamptz; n integer; n2 integer;
  v_md5 text; v_md5b text; v_snap text;
  b_counts bigint[]; e_counts bigint[];
  res jsonb := '[]'::jsonb; r jsonb; cnt integer := 0; passes integer := 0;
  v_expected integer := 53;
begin
  -- 0. Estrutura ---------------------------------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    f_place is not null and f_prev is not null and f_sto is not null and f_tr is not null and f_un is not null
    and f_org is not null and f_cimp is not null
    and exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'collection_layout'
                and column_name = 'storage_container_id' and is_nullable = 'NO')
    and exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'collection_layout_slot_assignment'
                and column_name = 'physical_card_id' and is_nullable = 'NO')
    and exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'collection_layout_slot_assignment'
                and column_name = 'collection_allocation_id' and is_nullable = 'YES')
    and exists (select 1 from pg_constraint where conname = 'uq_collection_layout_storage_container' and contype = 'u')
    and exists (select 1 from pg_constraint where conname = 'uq_collection_layout_slot_assignment_physical_card' and contype = 'u')
    and (select count(*) from pg_trigger where not tgisinternal and tgname in
         ('trg_collection_layout_storage_container', 'trg_storage_container_binder_kind', 'trg_physical_card_binder_position_guard')) = 3
    and position('storage_container_id' in pg_get_functiondef(f_att)) > 0,
    'detail','5247–5256 presentes: colunas, UNIQUEs, 3 gatilhos novos, RPCs novas/sobrecargas, associação pelo local (5255)');
  if (res -> 0 ->> 'ok')::boolean is not true then
    res := res || jsonb_build_object('id','X.0','ok', false, 'detail','aplique 5247 → 5256 antes deste harness');
  else
  res := res || jsonb_build_object('id','0.2','ok',
    (select bool_and(x.prosecdef and x.proconfig @> array['search_path=""']
                     and has_function_privilege('authenticated', x.oid, 'EXECUTE')
                     and not has_function_privilege('anon', x.oid, 'EXECUTE'))
     from pg_proc x where x.oid in (f_place, f_prev, f_sto, f_tr, f_un, f_hd, f_pg, f_par, f_det, f_org, f_cimp, f_att))
    and not exists (select 1 from pg_proc x, aclexplode(x.proacl) a
                    where x.oid in (f_place, f_prev, f_sto, f_tr, f_un, f_hd, f_pg, f_par, f_det, f_org, f_cimp, f_att) and a.grantee = 0)
    and (select bool_and(x.proconfig @> array['lock_timeout=5s']) from pg_proc x where x.oid in (f_place, f_tr)),
    'detail','RPCs: SECURITY DEFINER, search_path vazio, EXECUTE só authenticated (sem PUBLIC); escritas novas com lock_timeout 5s');
  res := res || jsonb_build_object('id','0.3','ok',
    (select bool_and(not has_function_privilege('authenticated', x.oid, 'EXECUTE') and x.proconfig @> array['search_path=""'])
     from pg_proc x where x.proname in ('enforce_collection_layout_storage_container', 'enforce_storage_container_binder_kind',
                                        'binder_position_guard_on_storage_change', 'enforce_collection_layout_slot_assignment_integrity',
                                        'enforce_collection_layout_slot_lock', 'enforce_collection_layout_structural_fk_immutability')
       and x.pronamespace = 'public'::regnamespace),
    'detail','funções de gatilho: sem EXECUTE para authenticated, search_path vazio');
  res := res || jsonb_build_object('id','0.4','ok',
    (select confdeltype from pg_constraint where conname = 'fk_collection_layout_slot_assignment_physical_card') = 'c'
    and (select confdeltype from pg_constraint where conname = 'fk_collection_layout_slot_assignment_allocation') = 'n'
    and (select confdeltype from pg_constraint where conname = 'fk_collection_layout_storage_container') = 'r'
    and (select count(*) from pg_constraint where conrelid = 'public.collection_layout_slot_assignment'::regclass and contype = 'f'
         and confrelid = 'public.collection_allocation'::regclass) = 1,
    'detail','FKs: exemplar CASCADE, alocação SET NULL (única), local do fichário RESTRICT');
  res := res || jsonb_build_object('id','0.5','ok',
    to_regprocedure('public.set_physical_cards_storage(uuid, uuid[])') is not null
    and to_regprocedure('public.organize_my_collection_storage(uuid, uuid, text, integer, text)') is not null
    and to_regprocedure('public.get_my_collection_binder_unplaced(uuid, integer, integer)') is null
    and position('p2a1-plan-v2' in pg_get_functiondef('public.collection_binder_plan'::regproc)) > 0
    and position('p2a1-plan-v1' in pg_get_functiondef('public.collection_binder_plan'::regproc)) = 0,
    'detail','5024/5222 antigas coexistem (sem DEFAULT nas novas: nunca ambíguo); leitura de 3 argumentos removida pela 5256; plano v2');
  res := res || jsonb_build_object('id','0.6','ok',
    not has_table_privilege('authenticated', 'public.collection_layout_slot_assignment', 'INSERT')
    and not has_table_privilege('authenticated', 'public.collection_layout_slot_assignment', 'UPDATE')
    and not has_table_privilege('authenticated', 'public.collection_layout', 'UPDATE')
    and not has_table_privilege('anon', 'public.collection_layout_slot_assignment', 'SELECT'),
    'detail','posições e fichário continuam sem DML direto do cliente');

  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.storage_container), (select count(*) from public.collection_layout),
               (select count(*) from public.collection_layout_slot_assignment),
               (select count(*) from public.collection_layout_slot_expected_content),
               (select count(*) from public.collection_layout_guest), (select count(*) from public.card)]
    into b_counts;

  begin
    -- F. Catálogo sintético, usuários, locais e exemplares -------------------------------------
    select g.id into v_game from public.game g where g.code = 'POKEMON';
    select l.id into v_pt from public.language l where l.code = 'pt-BR';
    select t.id into v_std from public.card_variant_type t where t.game_id = v_game and t.code = 'STANDARD';
    select c0.rarity_id, c0.category_id into v_rar, v_cat
    from public.card c0 join public.card_set cs0 on cs0.id = c0.card_set_id
    join public.expansion e0 on e0.id = cs0.expansion_id
    where e0.game_id = v_game limit 1;
    if v_game is null or v_pt is null or v_std is null or v_rar is null then
      res := res || jsonb_build_object('id','F.1','ok', false, 'detail','pré-requisitos de catálogo ausentes');
      raise exception 'MS854' using errcode = 'P0001';
    end if;
    insert into public.expansion (game_id, code, name, release_order)
    values (v_game, 'BPL_' || v_sfx, 'BPL Harness ' || v_sfx,
            (select coalesce(max(x.release_order), 0) + 1000 from public.expansion x where x.game_id = v_game))
    returning id into v_exp;
    insert into public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_exp, 'BPL' || v_sfx, 'BPL Set ' || v_sfx, 'REGULAR', 1, 1, 1) returning id into v_set;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '1', 1, 'BPL K1', true) returning id into k1;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default)
    values (k1, v_std, 1, true) returning id into k1s;

    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    values (u_a, 'authenticated', 'authenticated', 'wh5854-a-'||lower(v_sfx)||'@example.invalid',
            jsonb_build_object('username', 'wh5854a_'||lower(v_sfx), 'display_name', 'WH 5854 A'), now(), now()),
           (u_b, 'authenticated', 'authenticated', 'wh5854-b-'||lower(v_sfx)||'@example.invalid',
            jsonb_build_object('username', 'wh5854b_'||lower(v_sfx), 'display_name', 'WH 5854 B'), now(), now());
    select i.id into v_inv_a from public.inventory i where i.owner_user_id = u_a;
    select i.id into v_inv_b from public.inventory i where i.owner_user_id = u_b;

    -- Locais pelas RPCs canônicas.
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select x.storage_container_id into v_bin from public.create_my_storage_container(gen_random_uuid(), 'BIN 5854', 'BINDER') x;
    select x.storage_container_id into v_oth from public.create_my_storage_container(gen_random_uuid(), 'OTH 5854', 'BINDER') x;
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select x.storage_container_id into v_lb from public.create_my_storage_container(gen_random_uuid(), 'LB 5854', 'BINDER') x;
    execute 'reset role';

    -- Exemplares já guardados (fixture privilegiada; nenhum posicionado ainda).
    insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id) values (k1s, v_pt, v_inv_a, v_bin) returning id into o1;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id) values (k1s, v_pt, v_inv_a, v_bin) returning id into o2;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id) values (k1s, v_pt, v_inv_a, v_oth) returning id into o3;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id) values (k1s, v_pt, v_inv_a, v_bin) returning id into g1;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id) values (k1s, v_pt, v_inv_a, v_bin) returning id into g2;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id) values (k1s, v_pt, v_inv_a, v_bin) returning id into x1;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id) values (k1s, v_pt, v_inv_a, v_bin) returning id into a1;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id) values (k1s, v_pt, v_inv_a, v_bin) returning id into n1;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id) values (k1s, v_pt, v_inv_a, v_oth) returning id into f1;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id) values (k1s, v_pt, v_inv_b, v_lb)  returning id into b1;

    -- B: coleção e fichário próprios.
    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select x.collection_id into v_cb from public.create_my_free_collection(gen_random_uuid(), 'CB 5854', v_lb) x;
    perform public.allocate_physical_cards_to_collection(v_cb, array[b1]);
    select * into p from public.preview_my_collection_binder(v_cb, 2, 2, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_cb, 2, 2, 'PRINCIPAL_ONLY', p.plan_token);
    execute 'reset role';

    -- A: coleções, alocações, arquivamento, fichário 3×3, convidada.
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select x.collection_id into v_co from public.create_my_free_collection(gen_random_uuid(), 'CO 5854', v_bin) x;
    select x.collection_id into v_cg from public.create_my_free_collection(gen_random_uuid(), 'CG 5854', v_bin) x;
    select x.collection_id into v_cx from public.create_my_free_collection(gen_random_uuid(), 'CX 5854', v_oth) x;
    select x.collection_id into v_ca from public.create_my_free_collection(gen_random_uuid(), 'CA 5854', v_bin) x;
    select x.collection_id into v_cn from public.create_my_free_collection(gen_random_uuid(), 'CN 5854', v_bin) x;
    perform public.allocate_physical_cards_to_collection(v_co, array[o1, o2, o3]);
    perform public.allocate_physical_cards_to_collection(v_cg, array[g1, g2]);
    perform public.allocate_physical_cards_to_collection(v_cx, array[x1]);
    perform public.allocate_physical_cards_to_collection(v_ca, array[a1]);
    perform count(*) from public.archive_collection(v_ca);
    select * into p from public.preview_my_collection_binder(v_co, 3, 3, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_co, 3, 3, 'PRINCIPAL_ONLY', p.plan_token);
    select l.layout_id into l_o from public.get_my_collection_binder(v_co) l;
    perform count(*) from public.attach_my_collection_to_binder(v_cg, l_o);
    execute 'reset role';

    select l.id into l_b from public.collection_layout l where l.collection_id = v_cb;
    -- Bolsos livres (sem posição e sem reserva), em ordem de leitura.
    select array_agg(s.id order by pg.page_number, s.row_index, s.column_index) into fs
    from public.collection_layout_slot s join public.collection_layout_page pg on pg.id = s.page_id
    where pg.layout_id = l_o
      and not exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = s.id)
      and not exists (select 1 from public.collection_layout_slot_expected_content e where e.slot_id = s.id);

    res := res || jsonb_build_object('id','F.1','ok',
      l_o is not null and l_b is not null and coalesce(cardinality(fs), 0) >= 6
      and (select l.storage_container_id from public.collection_layout l where l.id = l_o) = v_bin
      and (select array_agg(a.physical_card_id order by a.physical_card_id)
           from public.collection_layout_slot_assignment a
           join public.collection_layout_slot s on s.id = a.slot_id
           join public.collection_layout_page pg on pg.id = s.page_id
           where pg.layout_id = l_o) = (select array_agg(z order by z) from unnest(array[o1, o2]) z)
      and (select count(*) from public.collection_layout_guest g where g.layout_id = l_o and g.collection_id = v_cg) = 1,
      'detail','montagem (5251): fichário herda BIN; só o1/o2 (guardados no BIN) posicionados — o3 (OTH) fica fora; CG convidada; ≥6 bolsos livres');

    -- 1. Segurança ---------------------------------------------------------------------------
    execute 'set local role anon';
    v_ok := false;
    begin perform count(*) from public.place_my_physical_card_in_slot(v_co, fs[1], x1);
    exception when insufficient_privilege then v_ok := true; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.1','ok', v_ok, 'detail','anon não executa place_my_physical_card_in_slot (42501)');

    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    v_err := null; begin perform count(*) from public.place_my_physical_card_in_slot(v_co, fs[1], x1);
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','1.2','ok', v_err = 'COLLECTION_NOT_FOUND',
      'detail','B posiciona no fichário de A → COLLECTION_NOT_FOUND: ' || coalesce(v_err, 'sem erro'));
    v_err := null; begin perform count(*) from public.place_my_physical_card_in_slot(v_cb, fs[1], b1);
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','1.3','ok', v_err = 'SLOT_NOT_FOUND',
      'detail','B usa a própria coleção com bolso de A → SLOT_NOT_FOUND: ' || coalesce(v_err, 'sem erro'));
    v_err := null; begin perform count(*) from public.get_my_collection_binder_unplaced(v_co, 48, 0, 'ALL', null);
    exception when others then v_err := sqlerrm; end;
    v_txt := null; begin perform count(*) from public.transfer_my_binder_ownership(v_co, v_cn);
    exception when others then v_txt := sqlerrm; end;
    res := res || jsonb_build_object('id','1.4','ok', v_err = 'COLLECTION_NOT_FOUND' and v_txt = 'COLLECTION_NOT_FOUND',
      'detail','B lista disponíveis e transfere o fichário de A → COLLECTION_NOT_FOUND nas duas: ' || coalesce(v_err, 'sem erro') || ' / ' || coalesce(v_txt, 'sem erro'));
    v_err := null; begin perform count(*) from public.preview_my_physical_cards_binder_impact(array[x1], v_lb);
    exception when others then v_err := sqlerrm; end;
    select count(*) into n from public.preview_my_physical_cards_binder_impact(array[x1], v_lb) z where z.positioned_count + z.locked_count > 0;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.5','ok', v_err is null and n = 0,
      'detail','prévia de impacto com exemplar alheio não vaza nada (0 posicionados)');

    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    v_err := null; begin perform count(*) from public.place_my_physical_card_in_slot(v_co, fs[1], b1);
    exception when others then v_err := sqlerrm; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.6','ok', v_err = 'PHYSICAL_CARD_NOT_FOUND'
      and not exists (select 1 from public.collection_layout_slot_assignment a where a.physical_card_id = b1 and a.slot_id = fs[1]),
      'detail','A posiciona exemplar de B → PHYSICAL_CARD_NOT_FOUND (não enumera): ' || coalesce(v_err, 'sem erro'));

    -- 2. Cartas disponíveis -----------------------------------------------------------------
    execute 'set local role authenticated';
    select array_agg(z.physical_card_id order by z.physical_card_id), max(z.total_count) into v_ids, n
    from public.get_my_collection_binder_unplaced(v_co, 96, 0, 'ALL', null) z;
    execute 'reset role';
    res := res || jsonb_build_object('id','2.1','ok',
      v_ids = (select array_agg(z order by z) from unnest(array[g1, g2, x1, a1, n1]) z) and n = 5,
      'detail','disponíveis = guardados no BIN sem bolso, de qualquer origem (convidada, NÃO participante, arquivada, sem coleção); exclui OTH e B; total 5');

    execute 'set local role authenticated';
    select array_agg(z.physical_card_id order by z.physical_card_id) into v_ids from public.get_my_collection_binder_unplaced(v_cg, 96, 0, 'THIS', null) z;
    v_ok := v_ids = (select array_agg(z order by z) from unnest(array[g1, g2]) z);
    select array_agg(z.physical_card_id order by z.physical_card_id) into v_ids from public.get_my_collection_binder_unplaced(v_cg, 96, 0, 'OTHER_COLLECTIONS', null) z;
    v_ok := v_ok and v_ids = (select array_agg(z order by z) from unnest(array[x1, a1]) z);
    select array_agg(z.physical_card_id) into v_ids from public.get_my_collection_binder_unplaced(v_cg, 96, 0, 'NO_COLLECTION', null) z;
    v_ok := v_ok and v_ids = array[n1];
    execute 'reset role';
    res := res || jsonb_build_object('id','2.2','ok', v_ok,
      'detail','filtros pela convidada: Desta coleção {g1,g2}; Outras coleções {x1,a1}; Sem coleção {n1}');

    execute 'set local role authenticated';
    select z.origin_kind, z.origin_lifecycle_status, z.origin_collection_name into q
    from public.get_my_collection_binder_unplaced(v_cg, 96, 0, 'ALL', null) z where z.physical_card_id = a1;
    select z.origin_kind, z.origin_collection_id, z.collection_allocation_id into w
    from public.get_my_collection_binder_unplaced(v_cg, 96, 0, 'ALL', null) z where z.physical_card_id = n1;
    select string_agg(z.origin_kind, ',') into v_txt
    from (select z.origin_kind from public.get_my_collection_binder_unplaced(v_cg, 2, 0, 'ALL', null) z) z;
    execute 'reset role';
    res := res || jsonb_build_object('id','2.3','ok',
      q.origin_kind = 'OTHER_COLLECTION' and q.origin_lifecycle_status = 'ARCHIVED' and q.origin_collection_name = 'CA 5854'
      and w.origin_kind = 'NO_COLLECTION' and w.origin_collection_id is null and w.collection_allocation_id is null
      and v_txt = 'THIS,THIS',
      'detail','origem exibida: a1 = CA arquivada; n1 sem coleção (alocação NULL); a coleção aberta vem primeiro (' || coalesce(v_txt, 'NULL') || ')');

    execute 'set local role authenticated';
    v_err := null; begin perform count(*) from public.get_my_collection_binder_unplaced(v_co, 48, 0, 'MINE', null);
    exception when others then v_err := sqlerrm; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','2.4','ok', v_err = 'INVALID_ARGUMENT',
      'detail','origem desconhecida → INVALID_ARGUMENT: ' || coalesce(v_err, 'sem erro'));

    execute 'set local role authenticated';
    select * into h from public.get_my_collection_binder(v_co);
    select * into q from public.get_my_collection_binder(v_cg);
    execute 'reset role';
    res := res || jsonb_build_object('id','2.5','ok',
      h.binder_role = 'OWNER' and h.binder_storage_container_id = v_bin and h.binder_storage_name = 'BIN 5854'
      and h.available_count = 5 and h.own_unplaced_count = 0 and h.own_filled_count = 2 and h.filled_count = 2
      and q.binder_role = 'GUEST' and q.available_count = 5 and q.own_unplaced_count = 2 and q.own_filled_count = 0,
      'detail','cabeçalho: local do fichário BIN; disponíveis 5 (todas as origens); fora do fichário da coleção = só as dela no BIN (CO 0, CG 2)');

    -- 2.6 Recorte por coleção de origem no servidor (bolso reservado por outra coleção).
    execute 'set local role authenticated';
    select array_agg(z.physical_card_id), max(z.total_count) into v_ids, n
    from public.get_my_collection_binder_unplaced(v_cg, 1, 0, 'OTHER_COLLECTIONS', v_ca) z;
    select count(*) into n2 from public.get_my_collection_binder_unplaced(v_cg, 96, 0, 'NO_COLLECTION', v_ca) z;
    execute 'reset role';
    res := res || jsonb_build_object('id','2.6','ok', v_ids = array[a1] and n = 1 and n2 = 0,
      'detail','recorte por coleção (CA) no servidor: só a1, total 1 (paginação correta); combinado com Sem coleção → vazio');

    -- 3. Posicionar ---------------------------------------------------------------------------
    select md5(string_agg(ca.physical_card_id::text || ':' || ca.collection_id::text, ',' order by ca.physical_card_id))
      into v_snap from public.collection_allocation ca join public.physical_card pc on pc.id = ca.physical_card_id
      where pc.inventory_id = v_inv_a;
    select md5(string_agg(pc.id::text || ':' || coalesce(pc.storage_container_id::text, '-'), ',' order by pc.id))
      into v_md5b from public.physical_card pc where pc.inventory_id = v_inv_a;

    execute 'set local role authenticated';
    select * into w from public.place_my_physical_card_in_slot(v_co, fs[1], x1);
    execute 'reset role';
    res := res || jsonb_build_object('id','3.1','ok', w.operation = 'ADD' and w.slot_id = fs[1] and w.replaced_physical_card_id is null
      and (select a.collection_allocation_id from public.collection_layout_slot_assignment a where a.id = w.assignment_id)
          = (select ca.id from public.collection_allocation ca where ca.physical_card_id = x1),
      'detail','x1 de coleção NÃO participante (CX, padrão OTH) posicionado → ADD (o caso Mudkip)');
    execute 'set local role authenticated';
    select * into w from public.place_my_physical_card_in_slot(v_co, fs[2], n1);
    execute 'reset role';
    res := res || jsonb_build_object('id','3.2','ok', w.operation = 'ADD'
      and (select a.collection_allocation_id is null and a.physical_card_id = n1 from public.collection_layout_slot_assignment a where a.id = w.assignment_id),
      'detail','n1 sem coleção posicionado → ADD, posição sem alocação');
    execute 'set local role authenticated';
    select * into w from public.place_my_physical_card_in_slot(v_co, fs[3], a1);
    execute 'reset role';
    res := res || jsonb_build_object('id','3.3','ok', w.operation = 'ADD'
      and (select c.lifecycle_status from public.collection c where c.id = v_ca) = 'ARCHIVED',
      'detail','D1: a1 de coleção arquivada posicionado → ADD, CA continua ARCHIVED');
    execute 'set local role authenticated';
    select * into w from public.place_my_physical_card_in_slot(v_co, fs[1], x1);
    v_err := null; begin perform count(*) from public.place_my_physical_card_in_slot(v_co, fs[4], x1);
    exception when others then v_err := sqlerrm; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','3.4','ok', w.operation = 'UNCHANGED' and v_err = 'CARD_ALREADY_PLACED',
      'detail','repetir → UNCHANGED; mesmo exemplar em outro bolso → CARD_ALREADY_PLACED: ' || coalesce(v_err, 'sem erro'));
    execute 'set local role authenticated';
    v_err := null; begin perform count(*) from public.place_my_physical_card_in_slot(v_co, fs[4], f1);
    exception when others then v_err := sqlerrm; end;
    v_txt := null; begin perform count(*) from public.place_my_physical_card_in_slot(v_co, fs[4], o3);
    exception when others then v_txt := sqlerrm; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','3.5','ok', v_err = 'CARD_NOT_IN_BINDER_LOCATION' and v_txt = 'CARD_NOT_IN_BINDER_LOCATION',
      'detail','guardado em OTH (sem coleção e até da proprietária) → CARD_NOT_IN_BINDER_LOCATION: ' || coalesce(v_err, 'sem erro') || ' / ' || coalesce(v_txt, 'sem erro'));
    execute 'set local role authenticated';
    select * into w from public.place_my_physical_card_in_slot(v_cg, fs[2], g1);
    execute 'reset role';
    res := res || jsonb_build_object('id','3.6','ok', w.operation = 'REPLACE' and w.replaced_physical_card_id = n1
      and not exists (select 1 from public.collection_layout_slot_assignment a where a.physical_card_id = n1),
      'detail','convidada substitui n1 por g1 → REPLACE; n1 volta a disponível');
    update public.collection_layout_slot set locked = true where id = fs[4];
    execute 'set local role authenticated';
    v_err := null; begin perform count(*) from public.place_my_physical_card_in_slot(v_co, fs[4], g2);
    exception when others then v_err := sqlerrm; end;
    execute 'reset role';
    update public.collection_layout_slot set locked = false where id = fs[4];
    res := res || jsonb_build_object('id','3.7','ok', v_err = 'SLOT_LOCKED',
      'detail','bolso travado → SLOT_LOCKED: ' || coalesce(v_err, 'sem erro'));
    execute 'set local role authenticated';
    v_err := null; begin perform count(*) from public.assign_card_to_slot(fs[4], (select ca.id from public.collection_allocation ca where ca.physical_card_id = o3));
    exception when others then v_err := sqlerrm; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','3.8','ok', v_err is not null
      and not exists (select 1 from public.collection_layout_slot_assignment a where a.physical_card_id = o3),
      'detail','escritor legado (assign_card_to_slot) com exemplar fora do local é recusado pelo gatilho: ' || coalesce(v_err, 'sem erro'));
    v_state := null;
    begin insert into public.collection_layout_slot_assignment (slot_id, physical_card_id) values (fs[5], x1);
    exception when others then v_state := sqlstate; end;
    v_err := null;
    begin insert into public.collection_layout_slot_assignment (slot_id, physical_card_id) values (fs[5], f1);
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','3.9','ok', v_state = '23505' and v_err = 'CARD_NOT_IN_BINDER_LOCATION',
      'detail','no banco, por qualquer caminho: exemplar já posicionado → 23505; fora do local → CARD_NOT_IN_BINDER_LOCATION');
    select md5(string_agg(ca.physical_card_id::text || ':' || ca.collection_id::text, ',' order by ca.physical_card_id))
      into v_md5 from public.collection_allocation ca join public.physical_card pc on pc.id = ca.physical_card_id
      where pc.inventory_id = v_inv_a;
    select md5(string_agg(pc.id::text || ':' || coalesce(pc.storage_container_id::text, '-'), ',' order by pc.id))
      into v_txt from public.physical_card pc where pc.inventory_id = v_inv_a;
    res := res || jsonb_build_object('id','3.10','ok', v_md5 = v_snap and v_txt = v_md5b,
      'detail','posicionar não alterou nenhuma alocação nem local físico (princípio 5)');

    -- 4. D3: mudança de local ---------------------------------------------------------------
    -- estado: fs1 x1, fs2 g1, fs3 a1; n1 e g2 disponíveis.
    execute 'set local role authenticated';
    select * into q from public.preview_my_physical_cards_binder_impact(array[x1, f1, n1], v_oth);
    v_err := null; begin perform count(*) from public.set_physical_cards_storage(v_oth, array[x1]);
    exception when others then v_err := sqlerrm; end;
    v_txt := null; begin perform count(*) from public.set_physical_cards_storage(v_oth, array[x1], false);
    exception when others then v_txt := sqlerrm; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','4.1','ok', q.positioned_count = 1 and q.locked_count = 0,
      'detail','prévia: mover x1/f1/n1 para OTH tira 1 do bolso, 0 travados');
    res := res || jsonb_build_object('id','4.2','ok', v_err = 'BINDER_POSITION_CONFIRMATION_REQUIRED'
      and v_txt = 'BINDER_POSITION_CONFIRMATION_REQUIRED'
      and (select pc.storage_container_id from public.physical_card pc where pc.id = x1) = v_bin
      and exists (select 1 from public.collection_layout_slot_assignment a where a.physical_card_id = x1 and a.slot_id = fs[1]),
      'detail','5024 antiga (gatilho 5256) e sobrecarga sem confirmação recusam; nada mudou: ' || coalesce(v_err, 'sem erro') || ' / ' || coalesce(v_txt, 'sem erro'));
    -- Organizar (D1): CX (padrão OTH) tem x1 posicionado no BIN.
    execute 'set local role authenticated';
    select * into q from public.preview_my_collection_storage_binder_impact(v_cx, v_oth, 'ALL');
    select * into p from public.get_my_collection_storage_plan(v_cx, v_oth);
    v_err := null; begin perform count(*) from public.organize_my_collection_storage(v_cx, v_oth, 'ALL', p.eligible_all, p.plan_token, false);
    exception when others then v_err := sqlerrm; end;
    v_txt := null; begin perform count(*) from public.organize_my_collection_storage(v_cx, v_oth, 'ALL', p.eligible_all, p.plan_token);
    exception when others then v_txt := sqlerrm; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','4.3','ok', q.positioned_count = 1 and q.locked_count = 0
      and v_err = 'BINDER_POSITION_CONFIRMATION_REQUIRED' and v_txt = 'BINDER_POSITION_CONFIRMATION_REQUIRED'
      and (select pc.storage_container_id from public.physical_card pc where pc.id = x1) = v_bin,
      'detail','organizar (D1): prévia acusa 1 bolso; sem confirmação recusa — nova e 5222 antiga (gatilho): ' || coalesce(v_err, 'sem erro') || ' / ' || coalesce(v_txt, 'sem erro'));
    execute 'set local role authenticated';
    select * into w from public.organize_my_collection_storage(v_cx, v_oth, 'ALL', p.eligible_all, p.plan_token, true);
    execute 'reset role';
    res := res || jsonb_build_object('id','4.4','ok', w.moved_count = p.eligible_all
      and (select pc.storage_container_id from public.physical_card pc where pc.id = x1) = v_oth
      and not exists (select 1 from public.collection_layout_slot_assignment a where a.physical_card_id = x1),
      'detail','organizar com confirmação: x1 vai para OTH e sai do bolso na mesma transação (atômico)');
    execute 'set local role authenticated';
    select count(*) into n from public.set_physical_cards_storage(v_bin, array[x1], false);
    select * into w from public.place_my_physical_card_in_slot(v_co, fs[1], x1);
    select count(*) into n2 from public.set_physical_cards_storage(v_oth, array[x1], true);
    execute 'reset role';
    res := res || jsonb_build_object('id','4.5','ok', n = 1 and w.operation = 'ADD' and n2 = 1
      and (select pc.storage_container_id from public.physical_card pc where pc.id = x1) = v_oth
      and not exists (select 1 from public.collection_layout_slot_assignment a where a.physical_card_id = x1),
      'detail','sobrecarga 5249 com confirmação: x1 volta ao BIN, é posicionado e sai para OTH tirando a posição');
    update public.collection_layout_slot set locked = true where id = fs[3];
    execute 'set local role authenticated';
    select * into q from public.preview_my_physical_cards_binder_impact(array[a1], v_oth);
    v_err := null; begin perform count(*) from public.set_physical_cards_storage(v_oth, array[a1], true);
    exception when others then v_err := sqlerrm; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','4.6','ok', q.locked_count = 1 and q.positioned_count = 0
      and v_err = 'BINDER_POSITION_LOCKED'
      and (select pc.storage_container_id from public.physical_card pc where pc.id = a1) = v_bin
      and exists (select 1 from public.collection_layout_slot_assignment a where a.physical_card_id = a1 and a.slot_id = fs[3]),
      'detail','bolso travado: prévia acusa 1 travado; mesmo confirmando → BINDER_POSITION_LOCKED, nada mudou: ' || coalesce(v_err, 'sem erro'));
    update public.collection_layout_slot set locked = false where id = fs[3];
    execute 'set local role authenticated';
    select count(*) into n from public.set_physical_cards_storage(v_bin, array[f1], false);
    select count(*) into n2 from public.get_my_collection_binder_unplaced(v_co, 96, 0, 'NO_COLLECTION', null) z where z.physical_card_id = f1;
    execute 'reset role';
    res := res || jsonb_build_object('id','4.7','ok', n = 1 and n2 = 1,
      'detail','exemplar sem bolso muda de local sem confirmação; f1 guardado no BIN passa a disponível');
    v_err := null;
    begin update public.physical_card set storage_container_id = v_oth where id = a1;
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','4.8','ok', v_err = 'BINDER_POSITION_CONFIRMATION_REQUIRED'
      and (select pc.storage_container_id from public.physical_card pc where pc.id = a1) = v_bin,
      'detail','UPDATE direto (qualquer caminho, ex.: 5222) também recusa sem confirmação: ' || coalesce(v_err, 'sem erro'));

    -- 5. Coleção × posição ---------------------------------------------------------------------
    execute 'set local role authenticated';
    perform count(*) from public.deallocate_physical_cards_from_collection(v_cg, array[g1]);
    select z.physical_card_id, z.collection_allocation_id, z.present_collection_id into q
    from public.get_my_collection_binder_pages(v_co, 1, 1) z where z.slot_id = fs[2];
    execute 'reset role';
    res := res || jsonb_build_object('id','5.1','ok', q.physical_card_id = g1 and q.collection_allocation_id is null and q.present_collection_id is null
      and (select a.collection_allocation_id is null from public.collection_layout_slot_assignment a where a.physical_card_id = g1),
      'detail','desalocar g1 mantém a posição (alocação → NULL); leitura mostra sem coleção');
    execute 'set local role authenticated';
    perform public.allocate_physical_cards_to_collection(v_cx, array[g1]);
    select z.physical_card_id, z.present_collection_name, z.present_collection_lifecycle into q
    from public.get_my_collection_binder_pages(v_co, 1, 1) z where z.slot_id = fs[2];
    execute 'reset role';
    res := res || jsonb_build_object('id','5.2','ok', q.physical_card_id = g1 and q.present_collection_name = 'CX 5854' and q.present_collection_lifecycle = 'ACTIVE',
      'detail','realocar g1 em CX (não participante) mantém o bolso; a origem exibida acompanha a alocação atual');
    execute 'set local role authenticated';
    select * into w from public.place_my_physical_card_in_slot(v_co, fs[4], n1);
    v_ok := public.remove_my_physical_card(n1);
    execute 'reset role';
    res := res || jsonb_build_object('id','5.3','ok', w.operation = 'ADD' and v_ok
      and not exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = fs[4]),
      'detail','remover o exemplar do acervo leva a posição junto (CASCADE liberado pela trava)');

    -- 6. D2: desassociar mantém posições ------------------------------------------------------
    execute 'set local role authenticated';
    select * into w from public.place_my_physical_card_in_slot(v_cg, fs[5], g2);
    select * into p from public.preview_my_collection_binder_detach(v_cg);
    select * into q from public.detach_my_collection_from_binder(v_cg, p.detach_token, false);
    execute 'reset role';
    res := res || jsonb_build_object('id','6.1','ok', w.operation = 'ADD' and p.assignments_count = 0
      and q.outcome = 'DETACHED' and q.assignments_removed = 0
      and exists (select 1 from public.collection_layout_slot_assignment a where a.physical_card_id = g2 and a.slot_id = fs[5])
      and not exists (select 1 from public.collection_layout_guest g where g.collection_id = v_cg),
      'detail','D2: prévia e desassociação de CG removem 0 posições; g2 continua no mesmo bolso');
    execute 'set local role authenticated';
    select count(*) into n from public.get_my_collection_binder_unplaced(v_cg, 48, 0, 'ALL', null);
    v_err := null; begin perform count(*) from public.place_my_physical_card_in_slot(v_cg, fs[6], o3);
    exception when others then v_err := sqlerrm; end;
    select z.present_collection_name into v_txt from public.get_my_collection_binder_pages(v_co, 1, 1) z where z.slot_id = fs[5];
    execute 'reset role';
    res := res || jsonb_build_object('id','6.2','ok', n = 0 and v_err = 'BINDER_NOT_FOUND' and v_txt = 'CG 5854',
      'detail','CG desassociada não lista nem posiciona (BINDER_NOT_FOUND); pela proprietária g2 aparece com origem CG: ' || coalesce(v_err, 'sem erro'));

    -- 7. Exclusão segura da proprietária ------------------------------------------------------
    execute 'set local role authenticated';
    v_err := null; begin perform count(*) from public.delete_collection(v_co);
    exception when others then v_err := sqlerrm; end;
    v_txt := null; begin perform count(*) from public.transfer_my_binder_ownership(v_co, v_ca);
    exception when others then v_txt := sqlerrm; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','7.1','ok', v_err is not null and exists (select 1 from public.collection c where c.id = v_co),
      'detail','excluir a proprietária direto é recusado (sem exclusão silenciosa): ' || coalesce(v_err, 'sem erro'));
    res := res || jsonb_build_object('id','7.2','ok', v_txt = 'COLLECTION_ARCHIVED',
      'detail','transferir para coleção arquivada → COLLECTION_ARCHIVED: ' || coalesce(v_txt, 'sem erro'));

    select md5(string_agg(a.id::text || ':' || a.slot_id::text || ':' || a.physical_card_id::text || ':' || a.updated_at::text, ',' order by a.id)),
           count(*)
      into v_md5, n
    from public.collection_layout_slot_assignment a join public.collection_layout_slot s on s.id = a.slot_id
    join public.collection_layout_page pg on pg.id = s.page_id where pg.layout_id = l_o;
    select l.updated_at into v_ts from public.collection_layout l where l.id = l_o;
    execute 'set local role authenticated';
    select * into w from public.transfer_my_binder_ownership(v_co, v_cn);
    execute 'reset role';
    select md5(string_agg(a.id::text || ':' || a.slot_id::text || ':' || a.physical_card_id::text || ':' || a.updated_at::text, ',' order by a.id))
      into v_md5b
    from public.collection_layout_slot_assignment a join public.collection_layout_slot s on s.id = a.slot_id
    join public.collection_layout_page pg on pg.id = s.page_id where pg.layout_id = l_o;
    res := res || jsonb_build_object('id','7.3','ok', w.outcome = 'TRANSFERRED' and w.layout_id = l_o
      and (select l.collection_id = v_cn and l.storage_container_id = v_bin from public.collection_layout l where l.id = l_o)
      and exists (select 1 from public.collection_layout_guest g where g.layout_id = l_o and g.collection_id = v_co)
      and v_md5 = v_md5b,
      'detail','transferência CO → CN: âncora muda, CO vira convidada; local e posições (id, bolso, exemplar, updated_at) idênticos');
    execute 'set local role authenticated';
    select * into w from public.transfer_my_binder_ownership(v_co, v_cn);
    select * into h from public.get_my_collection_binder(v_cn);
    select * into q from public.get_my_collection_binder(v_co);
    execute 'reset role';
    res := res || jsonb_build_object('id','7.4','ok', w.outcome = 'UNCHANGED' and h.binder_role = 'OWNER' and q.binder_role = 'GUEST'
      and h.layout_id = l_o and q.layout_id = l_o,
      'detail','repetir → UNCHANGED; leituras: CN proprietária, CO convidada do mesmo fichário');
    v_err := null;
    begin update public.collection_layout set collection_id = v_co where id = l_o;
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','7.5','ok', v_err like '%IMUTÁVEL%'
      and (select l.collection_id from public.collection_layout l where l.id = l_o) = v_cn,
      'detail','fora da função, collection_layout.collection_id continua imutável (5136)');
    execute 'set local role authenticated';
    perform count(*) from public.deallocate_physical_cards_from_collection(v_co, array[o1, o2, o3]);
    select * into p from public.preview_my_collection_binder_detach(v_co);
    select * into q from public.detach_my_collection_from_binder(v_co, p.detach_token, false);
    select count(*) into n2 from public.delete_collection(v_co);
    execute 'reset role';
    res := res || jsonb_build_object('id','7.6','ok', q.outcome = 'DETACHED' and q.assignments_removed = 0 and n2 = 1
      and not exists (select 1 from public.collection c where c.id = v_co)
      and (select count(*) from public.collection_layout_slot_assignment a where a.physical_card_id in (o1, o2)) = 2
      and (select count(*) from public.collection_layout_slot_assignment a join public.collection_layout_slot s on s.id = a.slot_id
           join public.collection_layout_page pg on pg.id = s.page_id where pg.layout_id = l_o) = n,
      'detail','caminho seguro: desalocar → desassociar → excluir CO; o1/o2 continuam posicionados, nenhuma posição perdida');

    -- 8. Identidade física -------------------------------------------------------------------
    v_err := null;
    begin update public.collection_layout set storage_container_id = v_oth where id = l_o;
    exception when others then v_err := sqlerrm; end;
    v_txt := null;
    begin update public.storage_container set kind_code = null where id = v_bin;
    exception when others then v_txt := sqlerrm; end;
    res := res || jsonb_build_object('id','8.1','ok', v_err = 'BINDER_LOCATION_IMMUTABLE' and v_txt = 'STORAGE_IS_DIGITAL_BINDER'
      and (select l.storage_container_id from public.collection_layout l where l.id = l_o) = v_bin,
      'detail','local do fichário imutável; o local não deixa de ser Fichário: ' || coalesce(v_err, 'sem erro') || ' / ' || coalesce(v_txt, 'sem erro'));
    v_err := null;
    begin
      insert into public.collection_layout (collection_id, grid_columns, grid_rows, storage_container_id)
      values (v_cx, 3, 3, v_bin);
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','8.2','ok', v_err = 'BINDER_LOCATION_TAKEN'
      and not exists (select 1 from public.collection_layout l where l.collection_id = v_cx),
      'detail','segundo fichário digital no mesmo fichário físico é recusado: ' || coalesce(v_err, 'sem erro'));

    -- 5255: associação e candidatos pelo local PRÓPRIO do fichário (owner atual: CN).
    execute 'set local role authenticated';
    select x.collection_id into v_cz from public.create_my_free_collection(gen_random_uuid(), 'CZ 5854', v_oth) x;
    select x.collection_id into v_cy from public.create_my_free_collection(gen_random_uuid(), 'CY 5854', v_bin) x;
    v_err := null; begin perform count(*) from public.attach_my_collection_to_binder(v_cz, l_o);
    exception when others then v_err := sqlerrm; end;
    select count(*) into n from public.list_my_binder_join_candidates(v_cz);
    select count(*) into n2 from public.list_my_binder_join_candidates(v_cy) z where z.layout_id = l_o;
    select * into w from public.attach_my_collection_to_binder(v_cy, l_o);
    execute 'reset role';
    res := res || jsonb_build_object('id','8.3','ok', v_err = 'NOT_SAME_LOCATION' and n = 0 and n2 = 1 and w.outcome = 'ATTACHED',
      'detail','5255: padrão OTH → NOT_SAME_LOCATION e sem candidatos; padrão BIN (= local do fichário) → candidato e ATTACHED, mesmo com a proprietária trocada: ' || coalesce(v_err, 'sem erro'));

    -- 9. Participantes -----------------------------------------------------------------------
    execute 'set local role authenticated';
    select count(*), string_agg(z.binder_role, ',' order by z.binder_role) into n, v_txt from public.get_my_binder_participants(v_cn) z;
    execute 'reset role';
    res := res || jsonb_build_object('id','9.1','ok', n = 2 and v_txt = 'GUEST,OWNER',
      'detail','participantes após o fluxo: CN (proprietária) + CY (convidada recém-associada)');

    raise exception 'MS854' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MS854' then
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
