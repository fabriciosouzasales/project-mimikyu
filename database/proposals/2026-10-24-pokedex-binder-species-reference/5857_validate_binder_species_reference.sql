/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5857 - Harness POKEDEX-BINDER-SPECIES-REFERENCE (5257–5260)
Versão......: 1.0 (2026-10-24, POKEDEX-BINDER-SPECIES-REFERENCE-IMPLEMENTATION-01)
Status......: PROPOSTA — NÃO EXECUTADA. NUNCA executar no LIVE (cria
              usuários, catálogo sintético e dados — desfeitos pela
              sentinela, mas proibido no LIVE por convenção). Executar só
              em ambiente descartável, com autorização de Fabrício, DEPOIS
              de 5257 → 5258 → 5259 → 5260.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-24

Protocolo (o mesmo da 5853): um único statement, usuários efêmeros A e B;
a sentinela MS857 desfaz tudo; 99.1 prova resíduo zero.

  select * from pg_temp.wh_5857_validate();

Pré-requisito de catálogo: Pokédex NATIONAL com GENERATION_VI (72
posições, #650–#721) — a mesma carga canônica do LIVE (6030–6051).

Fixture (pelas RPCs canônicas):
  A — local BIN (BINDER): CP, coleção Pokédex só GENERATION_VI, com
      fichário 4×4 completado até 5 páginas (80 bolsos);
      local BIN2 (BINDER): CF, coleção comum com 1 exemplar e fichário 2×2.
  B — local LB (BINDER): CB, coleção Pokédex com fichário próprio.

Seções:
  0  estrutura e ACL (tabelas sem grant/policy com RLS; FKs CASCADE/RESTRICT;
     RPCs definer, search_path vazio, só authenticated; helpers revogados)
  1  segurança: anon; B não lê/aplica/oculta/remove em A; coleção comum
  2  prévia/aplicação: 72 pares, 8 livres, #650→bolso 1 … #721→bolso 72;
     token errado; reaplicação idempotente; nada além da tabela nova muda
  3  exibição (ajuste A): ocultar/mostrar não apaga vínculos; UNCHANGED;
     leitura por páginas devolve mesmo com exibição desligada
  4  páginas: adicionar página não altera vínculos; remover página com
     referências exige a contagem exata (ajuste B); sem referências segue
     igual à 5235
  5  remoção explícita: COUNT_MISMATCH; REMOVED; preferência preservada
  6  defesa: DML direto recusado; gatilho de integridade; arquivada
  99 resíduo zero e papel restaurado

Limitações declaradas:
  L1 SET LOCAL ROLE prova o banco, não o JWT do PostgREST.
  L2 Concorrência real (duas sessões) não é exercitada: a aplicação usa a
     trava canônica 5122 já provada e o plan_token.
  L3 Inserir/fechar vão, mover/trocar carta, imagens e mesclagens não são
     exercitados aqui: nenhuma dessas funções lê ou escreve a tabela nova
     (prova estática: static_check_species_reference.py, regra S3) e a
     referência é chaveada pelo bolso.
  L4 Convidada (guest) só lê/oculta — leitura usa o helper 5234 já provado;
     não há fixture de convidada.
================================================================
*/

create or replace function pg_temp.wh_5857_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  f_prev oid := to_regprocedure('public.preview_my_binder_species_references(uuid)');
  f_app  oid := to_regprocedure('public.apply_my_binder_species_references(uuid, text)');
  f_vis  oid := to_regprocedure('public.set_my_binder_species_reference_visibility(uuid, boolean)');
  f_clr  oid := to_regprocedure('public.clear_my_binder_species_references(uuid, integer)');
  f_st   oid := to_regprocedure('public.get_my_binder_species_reference_state(uuid)');
  f_rd   oid := to_regprocedure('public.get_my_collection_binder_species_references(uuid, integer, integer)');
  f_rm2  oid := to_regprocedure('public.remove_layout_page(uuid, integer)');
  f_rm1  oid := to_regprocedure('public.remove_layout_page(uuid)');
  f_tg   oid := to_regprocedure('public.binder_species_reference_target(uuid)');
  f_pl   oid := to_regprocedure('public.binder_species_reference_plan(uuid, uuid, uuid, text)');
  f_trg  oid := to_regprocedure('public.enforce_collection_layout_slot_species_reference_integrity()');
  u_a uuid := gen_random_uuid();
  u_b uuid := gen_random_uuid();
  v_sfx text := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  v_game uuid; v_pt uuid; v_rar uuid; v_cat uuid; v_std uuid;
  v_exp uuid; v_set uuid; k1 uuid; k1s uuid; f1 uuid;
  v_inv_a uuid;
  v_bin uuid; v_bin2 uuid; v_lb uuid;
  v_cp uuid; v_cf uuid; v_cb uuid;
  l_p uuid; l_b uuid;
  pg1 uuid; pg5 uuid; pg6 uuid;
  v_tok text; v_ts timestamptz; v_upd timestamptz;
  p record; o record; w record;
  v_ok boolean; v_err text; v_hint text; n integer; n2 integer;
  b_counts bigint[]; e_counts bigint[]; i_before bigint[]; i_after bigint[];
  res jsonb := '[]'::jsonb; r jsonb; cnt integer := 0; passes integer := 0;
  v_expected integer := 35;
begin
  -- 0. Estrutura ----------------------------------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    to_regclass('public.collection_layout_slot_species_reference') is not null
    and to_regclass('public.collection_layout_species_reference_setting') is not null
    and f_prev is not null and f_app is not null and f_vis is not null and f_clr is not null
    and f_st is not null and f_rd is not null and f_rm2 is not null and f_rm1 is not null,
    'detail','5257–5260 presentes: 2 tabelas, 6 RPCs, remove_layout_page em 2 assinaturas');
  if (res -> 0 ->> 'ok')::boolean is not true then
    res := res || jsonb_build_object('id','X.0','ok', false, 'detail','aplique 5257 → 5258 → 5259 → 5260 antes deste harness');
  else
  res := res || jsonb_build_object('id','0.2','ok',
    (select bool_and(c.relrowsecurity) from pg_class c
      where c.oid in ('public.collection_layout_slot_species_reference'::regclass,
                      'public.collection_layout_species_reference_setting'::regclass))
    and not exists (select 1 from pg_policies pl
                    where pl.schemaname = 'public'
                      and pl.tablename in ('collection_layout_slot_species_reference','collection_layout_species_reference_setting'))
    and not has_table_privilege('authenticated', 'public.collection_layout_slot_species_reference', 'SELECT')
    and not has_table_privilege('authenticated', 'public.collection_layout_slot_species_reference', 'INSERT')
    and not has_table_privilege('authenticated', 'public.collection_layout_species_reference_setting', 'SELECT')
    and not has_table_privilege('anon', 'public.collection_layout_slot_species_reference', 'SELECT'),
    'detail','deny by default: RLS ligada, 0 policies, sem SELECT/INSERT para authenticated/anon');
  res := res || jsonb_build_object('id','0.3','ok',
    (select bool_and(q.prosecdef and q.proconfig @> array['search_path=""']
                     and has_function_privilege('authenticated', q.oid, 'EXECUTE')
                     and not has_function_privilege('anon', q.oid, 'EXECUTE'))
     from pg_proc q where q.oid in (f_prev, f_app, f_vis, f_clr, f_st, f_rd, f_rm2, f_rm1))
    and not exists (select 1 from pg_proc q, aclexplode(q.proacl) x
                    where q.oid in (f_prev, f_app, f_vis, f_clr, f_st, f_rd, f_rm2, f_rm1) and x.grantee = 0)
    and (select bool_and(q.proconfig @> array['lock_timeout=5s']) from pg_proc q where q.oid in (f_app, f_vis, f_clr)),
    'detail','RPCs: SECURITY DEFINER, search_path vazio, EXECUTE só authenticated (sem PUBLIC); escritas com lock_timeout 5s');
  res := res || jsonb_build_object('id','0.4','ok',
    (select bool_and(not has_function_privilege('authenticated', q.oid, 'EXECUTE')
                     and not has_function_privilege('anon', q.oid, 'EXECUTE'))
     from pg_proc q where q.oid in (f_tg, f_pl, f_trg)),
    'detail','helpers internos e função do gatilho sem EXECUTE para o cliente');
  res := res || jsonb_build_object('id','0.5','ok',
    (select string_agg(cn.conname || '=' || cn.confdeltype, ',' order by cn.conname)
       from pg_constraint cn
      where cn.conrelid = 'public.collection_layout_slot_species_reference'::regclass and cn.contype = 'f')
    = 'fk_cl_ssr_collection=c,fk_cl_ssr_layout=c,fk_cl_ssr_position=r,fk_cl_ssr_slot=c',
    'detail','FKs: bolso/layout/coleção CASCADE (desmontagem segue igual), posição RESTRICT');

  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.storage_container), (select count(*) from public.collection_layout),
               (select count(*) from public.collection_layout_slot_assignment),
               (select count(*) from public.collection_layout_slot_expected_content),
               (select count(*) from public.collection_layout_slot_species_reference),
               (select count(*) from public.collection_layout_species_reference_setting),
               (select count(*) from public.card)]
    into b_counts;

  begin
    -- F. Catálogo sintético (só para a coleção comum) e usuários ------------------------------
    select g.id into v_game from public.game g where g.code = 'POKEMON';
    select l.id into v_pt from public.language l where l.code = 'pt-BR';
    select t.id into v_std from public.card_variant_type t where t.game_id = v_game and t.code = 'STANDARD';
    select c0.rarity_id, c0.category_id into v_rar, v_cat
    from public.card c0 join public.card_set cs0 on cs0.id = c0.card_set_id
    join public.expansion e0 on e0.id = cs0.expansion_id
    where e0.game_id = v_game limit 1;
    if v_game is null or v_pt is null or v_std is null or v_rar is null
       or not exists (select 1 from public.pokemon_generation g where g.code = 'GENERATION_VI') then
      res := res || jsonb_build_object('id','F.1','ok', false, 'detail','pré-requisitos de catálogo ausentes');
      raise exception 'MS857' using errcode = 'P0001';
    end if;
    insert into public.expansion (game_id, code, name, release_order)
    values (v_game, 'PSR_' || v_sfx, 'PSR Harness ' || v_sfx,
            (select coalesce(max(x.release_order), 0) + 1000 from public.expansion x where x.game_id = v_game))
    returning id into v_exp;
    insert into public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_exp, 'PSR' || v_sfx, 'PSR Set ' || v_sfx, 'REGULAR', 1, 1, 1) returning id into v_set;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '1', 1, 'PSR K1', true) returning id into k1;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default)
    values (k1, v_std, 1, true) returning id into k1s;

    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    values (u_a, 'authenticated', 'authenticated', 'wh5857-a-'||lower(v_sfx)||'@example.invalid',
            jsonb_build_object('username', 'wh5857a_'||lower(v_sfx), 'display_name', 'WH 5857 A'), now(), now()),
           (u_b, 'authenticated', 'authenticated', 'wh5857-b-'||lower(v_sfx)||'@example.invalid',
            jsonb_build_object('username', 'wh5857b_'||lower(v_sfx), 'display_name', 'WH 5857 B'), now(), now());
    select i.id into v_inv_a from public.inventory i where i.owner_user_id = u_a;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (k1s, v_pt, v_inv_a) returning id into f1;

    -- B: Pokédex com fichário próprio
    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select x.storage_container_id into v_lb from public.create_my_storage_container(gen_random_uuid(), 'LB 5857', 'BINDER') x;
    select x.collection_id into v_cb from public.create_my_pokedex_collection(gen_random_uuid(), 'CB 5857', array['GENERATION_VI'], v_lb) x;
    select * into p from public.preview_my_collection_binder(v_cb, 4, 4, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_cb, 4, 4, 'PRINCIPAL_ONLY', p.plan_token);

    -- A: Pokédex (GENERATION_VI) + coleção comum
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select x.storage_container_id into v_bin from public.create_my_storage_container(gen_random_uuid(), 'BIN 5857', 'BINDER') x;
    select x.storage_container_id into v_bin2 from public.create_my_storage_container(gen_random_uuid(), 'BIN2 5857', 'BINDER') x;
    select x.collection_id into v_cp from public.create_my_pokedex_collection(gen_random_uuid(), 'CP 5857', array['GENERATION_VI'], v_bin) x;
    select * into p from public.preview_my_collection_binder(v_cp, 4, 4, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_cp, 4, 4, 'PRINCIPAL_ONLY', p.plan_token);
    select x.collection_id into v_cf from public.create_my_free_collection(gen_random_uuid(), 'CF 5857', v_bin2) x;
    perform public.allocate_physical_cards_to_collection(v_cf, array[f1]);
    select * into p from public.preview_my_collection_binder(v_cf, 2, 2, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_cf, 2, 2, 'PRINCIPAL_ONLY', p.plan_token);
    execute 'reset role';

    select l.id into l_p from public.collection_layout l where l.collection_id = v_cp;
    select l.id into l_b from public.collection_layout l where l.collection_id = v_cb;
    -- Completa o fichário de A até 5 páginas (80 bolsos) pela RPC canônica.
    execute 'set local role authenticated';
    loop
      select count(*) into n from public.collection_layout_page pg where pg.layout_id = l_p;
      exit when n >= 5;
      perform count(*) from public.add_layout_page(l_p);
    end loop;
    execute 'reset role';
    select count(*) into n from public.collection_layout_page pg where pg.layout_id = l_p;
    select pg.id into pg1 from public.collection_layout_page pg where pg.layout_id = l_p and pg.page_number = 1;
    select pg.id into pg5 from public.collection_layout_page pg where pg.layout_id = l_p and pg.page_number = 5;
    res := res || jsonb_build_object('id','F.1','ok', l_p is not null and l_b is not null and n = 5
      and (select count(*) from public.collection_layout_slot s join public.collection_layout_page pg on pg.id = s.page_id
           where pg.layout_id = l_p) = 80,
      'detail','fixture: CP (A) 5 páginas 4×4 = 80 bolsos; CB (B) Pokédex com fichário; CF (A) comum com fichário');

    select l.updated_at into v_upd from public.collection_layout l where l.id = l_p;
    select array[(select count(*) from public.collection_layout_page), (select count(*) from public.collection_layout_slot),
                 (select count(*) from public.collection_layout_slot_assignment),
                 (select count(*) from public.collection_layout_slot_expected_content),
                 (select count(*) from public.collection_layout_region), (select count(*) from public.collection_layout_slot_image),
                 (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
                 (select count(*) from public.collection_layout_slot where locked)]
      into i_before;

    -- 1. Segurança -----------------------------------------------------------------------------
    execute 'set local role anon';
    v_ok := false;
    begin perform count(*) from public.preview_my_binder_species_references(v_cp);
    exception when insufficient_privilege then v_ok := true; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.1','ok', v_ok, 'detail','anon não executa a prévia (42501)');

    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    v_err := null; begin perform count(*) from public.preview_my_binder_species_references(v_cp);
    exception when others then v_err := sqlerrm; end;
    v_hint := null; begin perform count(*) from public.get_my_collection_binder_species_references(v_cp, 1, 4);
    exception when others then v_hint := sqlerrm; end;
    res := res || jsonb_build_object('id','1.2','ok', v_err = 'COLLECTION_NOT_FOUND' and v_hint = 'COLLECTION_NOT_FOUND',
      'detail','B prévia/lê referências de A → COLLECTION_NOT_FOUND: ' || coalesce(v_err, 'sem erro') || ' / ' || coalesce(v_hint, 'sem erro'));
    v_err := null; begin perform count(*) from public.set_my_binder_species_reference_visibility(v_cp, false);
    exception when others then v_err := sqlerrm; end;
    v_hint := null; begin perform count(*) from public.clear_my_binder_species_references(v_cp, 0);
    exception when others then v_hint := sqlerrm; end;
    res := res || jsonb_build_object('id','1.3','ok', v_err = 'COLLECTION_NOT_FOUND' and v_hint = 'COLLECTION_NOT_FOUND',
      'detail','B oculta/remove em A → COLLECTION_NOT_FOUND: ' || coalesce(v_err, 'sem erro') || ' / ' || coalesce(v_hint, 'sem erro'));
    execute 'reset role';

    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    v_err := null; begin perform count(*) from public.preview_my_binder_species_references(v_cf);
    exception when others then v_err := sqlerrm; end;
    select * into o from public.get_my_binder_species_reference_state(v_cf);
    res := res || jsonb_build_object('id','1.4','ok', v_err = 'NOT_POKEDEX_COLLECTION'
      and o.has_binder and not o.is_pokedex_owner and not o.can_manage and o.reference_count = 0,
      'detail','coleção comum: prévia → NOT_POKEDEX_COLLECTION; estado sem gestão: ' || coalesce(v_err, 'sem erro'));

    -- 2. Prévia e aplicação ----------------------------------------------------------------------
    select * into p from public.preview_my_binder_species_references(v_cp);
    v_tok := p.plan_token;
    res := res || jsonb_build_object('id','2.1','ok',
      p.positions_in_scope = 72 and p.slots_total = 80 and p.pair_count = 72 and p.slots_left_free = 8
      and p.positions_unplaced = 0 and p.first_number = 650 and p.last_number = 721 and p.first_page = 1
      and p.last_page = 5 and p.existing_count = 0 and not p.already_applied and p.slots_with_content >= 0
      and v_tok ~ '^[0-9a-f]{64}$',
      'detail', format('prévia: %s posições, %s bolsos, %s pares, %s livres, #%s–#%s, págs %s–%s',
        p.positions_in_scope, p.slots_total, p.pair_count, p.slots_left_free, p.first_number, p.last_number, p.first_page, p.last_page));
    v_err := null; begin perform count(*) from public.apply_my_binder_species_references(v_cp, repeat('0', 64));
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','2.2','ok', v_err = 'PLAN_CHANGED',
      'detail','token divergente → PLAN_CHANGED: ' || coalesce(v_err, 'sem erro'));
    select * into w from public.apply_my_binder_species_references(v_cp, v_tok);
    res := res || jsonb_build_object('id','2.3','ok', w.operation = 'APPLIED' and w.reference_count = 72 and w.references_visible,
      'detail','aplicação: ' || coalesce(w.operation, 'NULL') || ', ' || coalesce(w.reference_count, -1) || ' referências');
    execute 'reset role';

    -- Ordem: bolso ordinal n ↔ posição ordinal n; 8 últimos sem referência.
    with sl as (
      select s.id, row_number() over (order by pg.page_number, s.row_index, s.column_index, s.id) as n
      from public.collection_layout_slot s join public.collection_layout_page pg on pg.id = s.page_id
      where pg.layout_id = l_p
    )
    select count(*) filter (where pp.position_number = 649 + sl.n),
           count(*) filter (where r.slot_id is null and sl.n > 72)
      into n, n2
    from sl
    left join public.collection_layout_slot_species_reference r on r.slot_id = sl.id
    left join public.pokedex_position pp on pp.id = r.pokedex_position_id;
    res := res || jsonb_build_object('id','2.4','ok', n = 72 and n2 = 8
      and (select count(*) from public.collection_layout_slot_species_reference r where r.layout_id = l_p and r.collection_id = v_cp) = 72,
      'detail', format('ordem nacional: %s bolsos com #(649+n); %s bolsos finais sem referência', n, n2));

    select max(r.created_at) into v_ts from public.collection_layout_slot_species_reference r where r.layout_id = l_p;
    execute 'set local role authenticated';
    select * into w from public.apply_my_binder_species_references(v_cp, v_tok);
    execute 'reset role';
    res := res || jsonb_build_object('id','2.5','ok', w.operation = 'ALREADY_APPLIED' and w.reference_count = 72
      and (select max(r.created_at) from public.collection_layout_slot_species_reference r where r.layout_id = l_p) = v_ts,
      'detail','reaplicar o mesmo plano → ALREADY_APPLIED, nada gravado');

    select array[(select count(*) from public.collection_layout_page), (select count(*) from public.collection_layout_slot),
                 (select count(*) from public.collection_layout_slot_assignment),
                 (select count(*) from public.collection_layout_slot_expected_content),
                 (select count(*) from public.collection_layout_region), (select count(*) from public.collection_layout_slot_image),
                 (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
                 (select count(*) from public.collection_layout_slot where locked)]
      into i_after;
    res := res || jsonb_build_object('id','2.6','ok', i_before = i_after
      and (select l.updated_at from public.collection_layout l where l.id = l_p) = v_upd
      and not exists (select 1 from public.collection_layout_slot_species_reference r where r.layout_id = l_b),
      'detail','aplicação não alterou páginas, bolsos, posições, reservas, regiões, imagens, alocações, exemplares, travas, updated_at do fichário nem o fichário de B');

    -- 3. Exibição (ajuste A) ---------------------------------------------------------------------
    execute 'set local role authenticated';
    select * into w from public.set_my_binder_species_reference_visibility(v_cp, false);
    select * into o from public.get_my_binder_species_reference_state(v_cp);
    res := res || jsonb_build_object('id','3.1','ok', w.operation = 'UPDATED' and not w.references_visible
      and not o.references_visible and o.reference_count = 72 and o.can_manage and o.is_pokedex_owner,
      'detail','ocultar → UPDATED; vínculos preservados (72); estado reflete a preferência');
    select * into w from public.set_my_binder_species_reference_visibility(v_cp, false);
    res := res || jsonb_build_object('id','3.2','ok', w.operation = 'UNCHANGED',
      'detail','ocultar de novo → UNCHANGED');
    select count(*), min(x.national_number), bool_and(x.artwork_path is not null)
      into n, n2, v_ok
    from public.get_my_collection_binder_species_references(v_cp, 1, 4) x;
    res := res || jsonb_build_object('id','3.3','ok', n = 64 and n2 = 650 and v_ok,
      'detail', format('leitura págs 1–4 com exibição desligada: %s referências, primeira #%s, todas com arte', n, n2));
    v_err := null; begin perform count(*) from public.get_my_collection_binder_species_references(v_cp, 1, 5);
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','3.4','ok', v_err = 'INVALID_PAGE',
      'detail','mais de 4 páginas → INVALID_PAGE: ' || coalesce(v_err, 'sem erro'));
    select * into w from public.set_my_binder_species_reference_visibility(v_cp, true);
    res := res || jsonb_build_object('id','3.5','ok', w.operation = 'UPDATED' and w.references_visible,
      'detail','mostrar → UPDATED');

    -- 4. Páginas ----------------------------------------------------------------------------------
    select x.id into pg6 from public.add_layout_page(l_p) x;
    select * into w from public.apply_my_binder_species_references(v_cp, v_tok);
    res := res || jsonb_build_object('id','4.1','ok', w.operation = 'ALREADY_APPLIED' and w.reference_count = 72,
      'detail','página nova no fim não altera os pares (mesmo token) nem cria referência');
    v_err := null; v_hint := null;
    begin perform public.remove_layout_page(pg1);
    exception when others then v_err := sqlerrm; get stacked diagnostics v_hint = pg_exception_hint; end;
    res := res || jsonb_build_object('id','4.2','ok', v_err like 'page has 16 species reference(s)%'
      and v_hint = 'SPECIES_REFERENCES_ON_PAGE:16'
      and (select count(*) from public.collection_layout_page pg where pg.layout_id = l_p) = 6,
      'detail','remover página 1 sem confirmação → recusa com contagem; nada muda: ' || coalesce(v_hint, 'sem hint'));
    v_err := null; begin perform public.remove_layout_page(pg1, 5);
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','4.3','ok', v_err like 'page has 16 species reference(s)%',
      'detail','confirmação com contagem errada → recusa');
    perform public.remove_layout_page(pg6);
    res := res || jsonb_build_object('id','4.4','ok',
      (select count(*) from public.collection_layout_page pg where pg.layout_id = l_p) = 5,
      'detail','página sem referências: assinatura de 1 argumento remove como na 5235');
    perform public.remove_layout_page(pg5, 8);
    select * into o from public.get_my_binder_species_reference_state(v_cp);
    res := res || jsonb_build_object('id','4.5','ok', o.reference_count = 64
      and (select count(*) from public.collection_layout_page pg where pg.layout_id = l_p) = 4,
      'detail','página 5 com 8 referências, confirmada com 8 → removida; 64 restantes');
    select * into p from public.preview_my_binder_species_references(v_cp);
    v_err := null; begin perform count(*) from public.apply_my_binder_species_references(v_cp, p.plan_token);
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','4.6','ok', p.pair_count = 64 and not p.already_applied and v_err = 'SPECIES_REFERENCES_PRESENT',
      'detail','plano diferente com referências presentes → SPECIES_REFERENCES_PRESENT (nunca mistura): ' || coalesce(v_err, 'sem erro'));

    -- 5. Remoção explícita -----------------------------------------------------------------------
    v_err := null; begin perform count(*) from public.clear_my_binder_species_references(v_cp, 72);
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','5.1','ok', v_err = 'COUNT_MISMATCH',
      'detail','contagem divergente → COUNT_MISMATCH: ' || coalesce(v_err, 'sem erro'));
    select * into w from public.clear_my_binder_species_references(v_cp, 64);
    select * into o from public.get_my_binder_species_reference_state(v_cp);
    res := res || jsonb_build_object('id','5.2','ok', w.operation = 'REMOVED' and w.removed_count = 64
      and o.reference_count = 0 and o.references_visible,
      'detail','remoção explícita: 64 removidas; preferência de exibição preservada');
    select * into w from public.clear_my_binder_species_references(v_cp, 0);
    res := res || jsonb_build_object('id','5.3','ok', w.operation = 'REMOVED' and w.removed_count = 0,
      'detail','remover sem referências → REMOVED 0 (repetível)');

    -- 6. Defesa --------------------------------------------------------------------------------
    v_ok := false;
    begin
      insert into public.collection_layout_slot_species_reference (slot_id, layout_id, collection_id, pokedex_position_id)
      select s.id, l_p, v_cp, (select pp.id from public.pokedex_position pp limit 1)
      from public.collection_layout_slot s join public.collection_layout_page pg on pg.id = s.page_id
      where pg.layout_id = l_p limit 1;
    exception when insufficient_privilege then v_ok := true; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','6.1','ok', v_ok, 'detail','INSERT direto pelo cliente → 42501');
    v_err := null;
    begin
      insert into public.collection_layout_slot_species_reference (slot_id, layout_id, collection_id, pokedex_position_id)
      select s.id, l_b, v_cp, (select pp.id from public.pokedex_position pp limit 1)
      from public.collection_layout_slot s join public.collection_layout_page pg on pg.id = s.page_id
      where pg.layout_id = l_p limit 1;
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','6.2','ok', v_err = 'SPECIES_REFERENCE_SLOT_LAYOUT_MISMATCH',
      'detail','gatilho: bolso de outro fichário → recusado: ' || coalesce(v_err, 'sem erro'));
    v_err := null;
    begin
      insert into public.collection_layout_slot_species_reference (slot_id, layout_id, collection_id, pokedex_position_id)
      select s.id, pg.layout_id, v_cf, (select pp.id from public.pokedex_position pp limit 1)
      from public.collection_layout_slot s join public.collection_layout_page pg on pg.id = s.page_id
      join public.collection_layout l on l.id = pg.layout_id
      where l.collection_id = v_cf limit 1;
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','6.3','ok', v_err = 'SPECIES_REFERENCE_NOT_POKEDEX',
      'detail','gatilho: fichário de coleção comum → recusado: ' || coalesce(v_err, 'sem erro'));
    execute 'set local role authenticated';
    perform count(*) from public.archive_collection(v_cp);
    select * into p from public.preview_my_binder_species_references(v_cp);
    v_err := null; begin perform count(*) from public.apply_my_binder_species_references(v_cp, p.plan_token);
    exception when others then v_err := sqlerrm; end;
    select * into o from public.get_my_binder_species_reference_state(v_cp);
    execute 'reset role';
    res := res || jsonb_build_object('id','6.4','ok', v_err = 'COLLECTION_ARCHIVED' and not o.can_manage,
      'detail','arquivada: aplicação → COLLECTION_ARCHIVED; estado sem gestão: ' || coalesce(v_err, 'sem erro'));

    raise exception 'MS857' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MS857' then
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
               (select count(*) from public.collection_layout_slot_species_reference),
               (select count(*) from public.collection_layout_species_reference_setting),
               (select count(*) from public.card)]
    into e_counts;
  res := res || jsonb_build_object('id','99.1','ok', b_counts = e_counts and current_user = session_user,
    'detail','resíduo zero (11 tabelas) e papel restaurado');
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
