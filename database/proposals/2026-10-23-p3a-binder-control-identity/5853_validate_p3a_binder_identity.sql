/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5853 - Harness P3-A (5244–5246): identidade do fichário,
              ocupação e coleções vinculadas
Versão......: 1.0 (2026-10-23, P3A-BINDER-CONTROL-IDENTITY-IMPLEMENTATION-01)
Status......: PROPOSTA — NÃO EXECUTADA. NUNCA executar no LIVE (cria
              usuários, catálogo sintético e dados — desfeitos pela
              sentinela, mas proibido no LIVE por convenção). Executar só
              em ambiente descartável, com autorização de Fabrício, DEPOIS
              de 5244 → 5245 → 5246.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-23

Protocolo (o mesmo da 5851): um único statement, usuários efêmeros A e B,
catálogo SINTÉTICO mínimo; a sentinela MS853 desfaz tudo; 99.1 prova
resíduo zero.

  select * from pg_temp.wh_5853_validate();

Fixture (pelas RPCs canônicas):
  A — local BIN (BINDER): CO (o1) com fichário 2×2 (proprietária),
      CG (g1) e CE (vazia) convidadas.
  B — local LB (BINDER): CB (b1) com fichário 2×2.

Seções:
  0  estrutura: colunas + CHECK; 4 RPCs definer, search_path vazio,
     EXECUTE só authenticated; sem DML do cliente em collection_layout
  1  segurança: anon 42501; B não lê/edita/lista o fichário de A
  2  identidade (proprietária): leitura inicial com fallback; normalização;
     UNCHANGED sem updated_at novo; nome inválido (quebra de linha, >60);
     vazio volta ao fallback; logomarca; argumento nulo; UPDATE direto
     recusado; CHECK recusa formato fora do canônico
  3  compartilhado: convidada lê a mesma identidade e não edita
     (BINDER_OWNER_ONLY, nada muda); participantes (proprietária vê 3,
     convidada vê 2); ocupação soma = bolsos
  4  arquivada: proprietária arquivada → COLLECTION_ARCHIVED; leitura
     continua, can_edit falso
  5  integridade: nenhuma escrita de identidade alterou cartas, reservas,
     páginas, bolsos, regiões, imagens ou alocações
  99 resíduo zero e papel restaurado

Limitações declaradas:
  L1 SET LOCAL ROLE prova o banco, não o JWT do PostgREST.
  L2 Um statement não tem duas sessões: concorrência real (duas abas
     gravando o nome) não é exercitada — a trava é a mesma 5122 já
     provada nas rodadas anteriores.
  L3 Imagens e mesclagens exigem arquivos no Storage: a ocupação com
     imagem/mesclagem NÃO é exercitada aqui (só a soma com zero) —
     homologação pela interface (README §11, H5).
================================================================
*/

create or replace function pg_temp.wh_5853_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  f_set  oid := to_regprocedure('public.set_my_binder_identity(uuid, text, boolean)');
  f_id   oid := to_regprocedure('public.get_my_binder_identity(uuid)');
  f_oc   oid := to_regprocedure('public.get_my_binder_occupancy(uuid)');
  f_par  oid := to_regprocedure('public.get_my_binder_participants(uuid)');
  u_a uuid := gen_random_uuid();
  u_b uuid := gen_random_uuid();
  v_sfx text := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  v_game uuid; v_pt uuid; v_rar uuid; v_cat uuid; v_std uuid;
  v_exp uuid; v_set uuid; k1 uuid; k1s uuid;
  v_inv_a uuid; v_inv_b uuid; v_ids uuid[];
  o1 uuid; g1 uuid; b1 uuid;
  v_bin uuid; v_lb uuid;
  v_co uuid; v_cg uuid; v_ce uuid; v_cb uuid;
  l_o uuid; s_o2 uuid; a_g1 uuid;
  p record; o record; q record; w record;
  v_ok boolean; v_err text; v_hint text; v_ts timestamptz; n integer; n2 integer; n3 integer; n4 integer;
  b_counts bigint[]; e_counts bigint[]; i_before bigint[]; i_after bigint[];
  res jsonb := '[]'::jsonb; r jsonb; cnt integer := 0; passes integer := 0;
  v_expected integer := 30;
begin
  -- 0. Estrutura ---------------------------------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    f_set is not null and f_id is not null and f_oc is not null and f_par is not null
    and (select count(*) from information_schema.columns where table_schema = 'public'
         and table_name = 'collection_layout' and column_name in ('display_name','show_brand_mark')) = 2
    and exists (select 1 from pg_constraint where conrelid = 'public.collection_layout'::regclass
                and conname = 'chk_collection_layout_display_name_format'),
    'detail','5244–5246 presentes: 2 colunas, CHECK de formato, 4 RPCs');
  if (res -> 0 ->> 'ok')::boolean is not true then
    res := res || jsonb_build_object('id','X.0','ok', false, 'detail','aplique 5244 → 5245 → 5246 antes deste harness');
  else
  res := res || jsonb_build_object('id','0.2','ok',
    (select bool_and(q.prosecdef and q.proconfig @> array['search_path=""']
                     and has_function_privilege('authenticated', q.oid, 'EXECUTE')
                     and not has_function_privilege('anon', q.oid, 'EXECUTE'))
     from pg_proc q where q.oid in (f_set, f_id, f_oc, f_par))
    and not exists (select 1 from pg_proc q, aclexplode(q.proacl) x where q.oid in (f_set, f_id, f_oc, f_par) and x.grantee = 0)
    and (select q.proconfig @> array['lock_timeout=5s'] from pg_proc q where q.oid = f_set),
    'detail','RPCs: SECURITY DEFINER, search_path vazio, EXECUTE só authenticated (sem PUBLIC); escrita com lock_timeout 5s');
  res := res || jsonb_build_object('id','0.3','ok',
    not has_table_privilege('authenticated', 'public.collection_layout', 'UPDATE')
    and not has_table_privilege('authenticated', 'public.collection_layout', 'INSERT')
    and not has_table_privilege('anon', 'public.collection_layout', 'SELECT'),
    'detail','collection_layout continua sem DML para o cliente');

  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.storage_container), (select count(*) from public.collection_layout),
               (select count(*) from public.collection_layout_slot_assignment),
               (select count(*) from public.collection_layout_slot_expected_content),
               (select count(*) from public.collection_layout_guest), (select count(*) from public.card)]
    into b_counts;

  begin
    -- F. Catálogo sintético e usuários -------------------------------------------------------
    select g.id into v_game from public.game g where g.code = 'POKEMON';
    select l.id into v_pt from public.language l where l.code = 'pt-BR';
    select t.id into v_std from public.card_variant_type t where t.game_id = v_game and t.code = 'STANDARD';
    select c0.rarity_id, c0.category_id into v_rar, v_cat
    from public.card c0 join public.card_set cs0 on cs0.id = c0.card_set_id
    join public.expansion e0 on e0.id = cs0.expansion_id
    where e0.game_id = v_game limit 1;
    if v_game is null or v_pt is null or v_std is null or v_rar is null then
      res := res || jsonb_build_object('id','F.1','ok', false, 'detail','pré-requisitos de catálogo ausentes');
      raise exception 'MS853' using errcode = 'P0001';
    end if;
    insert into public.expansion (game_id, code, name, release_order)
    values (v_game, 'P3A_' || v_sfx, 'P3A Harness ' || v_sfx,
            (select coalesce(max(x.release_order), 0) + 1000 from public.expansion x where x.game_id = v_game))
    returning id into v_exp;
    insert into public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_exp, 'P3A' || v_sfx, 'P3A Set ' || v_sfx, 'REGULAR', 1, 1, 1) returning id into v_set;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '1', 1, 'P3A K1', true) returning id into k1;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default)
    values (k1, v_std, 1, true) returning id into k1s;

    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    values (u_a, 'authenticated', 'authenticated', 'wh5853-a-'||lower(v_sfx)||'@example.invalid',
            jsonb_build_object('username', 'wh5853a_'||lower(v_sfx), 'display_name', 'WH 5853 A'), now(), now()),
           (u_b, 'authenticated', 'authenticated', 'wh5853-b-'||lower(v_sfx)||'@example.invalid',
            jsonb_build_object('username', 'wh5853b_'||lower(v_sfx), 'display_name', 'WH 5853 B'), now(), now());
    select i.id into v_inv_a from public.inventory i where i.owner_user_id = u_a;
    select i.id into v_inv_b from public.inventory i where i.owner_user_id = u_b;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, created_at) values
      (k1s, v_pt, v_inv_a, now() - interval '2 min'), (k1s, v_pt, v_inv_a, now() - interval '1 min');
    select array_agg(pc.id order by pc.created_at) into v_ids from public.physical_card pc where pc.inventory_id = v_inv_a;
    o1 := v_ids[1]; g1 := v_ids[2];
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (k1s, v_pt, v_inv_b) returning id into b1;

    -- B
    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select x.storage_container_id into v_lb from public.create_my_storage_container(gen_random_uuid(), 'LB 5853', 'BINDER') x;
    select x.collection_id into v_cb from public.create_my_free_collection(gen_random_uuid(), 'CB 5853', v_lb) x;
    perform public.allocate_physical_cards_to_collection(v_cb, array[b1]);
    select * into p from public.preview_my_collection_binder(v_cb, 2, 2, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_cb, 2, 2, 'PRINCIPAL_ONLY', p.plan_token);

    -- A
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select x.storage_container_id into v_bin from public.create_my_storage_container(gen_random_uuid(), 'BIN 5853', 'BINDER') x;
    select x.collection_id into v_co from public.create_my_free_collection(gen_random_uuid(), 'CO 5853', v_bin) x;
    select x.collection_id into v_cg from public.create_my_free_collection(gen_random_uuid(), 'CG 5853', v_bin) x;
    select x.collection_id into v_ce from public.create_my_free_collection(gen_random_uuid(), 'CE 5853', v_bin) x;
    perform public.allocate_physical_cards_to_collection(v_co, array[o1]);
    perform public.allocate_physical_cards_to_collection(v_cg, array[g1]);
    select * into p from public.preview_my_collection_binder(v_co, 2, 2, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_co, 2, 2, 'PRINCIPAL_ONLY', p.plan_token);
    execute 'reset role';

    select l.id into l_o from public.collection_layout l where l.collection_id = v_co;
    select array_agg(s.id order by s.row_index, s.column_index) into v_ids
    from public.collection_layout_slot s join public.collection_layout_page pg on pg.id = s.page_id
    where pg.layout_id = l_o and pg.page_number = 1;
    s_o2 := v_ids[2];
    select ca.id into a_g1 from public.collection_allocation ca where ca.physical_card_id = g1;
    res := res || jsonb_build_object('id','F.1','ok', l_o is not null and s_o2 is not null and a_g1 is not null,
      'detail','fixture: fichário 2×2 de CO (A) e de CB (B)');

    select array[(select count(*) from public.collection_layout_page), (select count(*) from public.collection_layout_slot),
                 (select count(*) from public.collection_layout_slot_assignment),
                 (select count(*) from public.collection_layout_slot_expected_content),
                 (select count(*) from public.collection_layout_region), (select count(*) from public.collection_layout_slot_image),
                 (select count(*) from public.collection_allocation),
                 (select count(*) from public.collection_layout_slot where locked)]
      into i_before;

    -- 1. Segurança ---------------------------------------------------------------------------
    execute 'set local role anon';
    v_ok := false;
    begin perform count(*) from public.set_my_binder_identity(v_co, 'X', true);
    exception when insufficient_privilege then v_ok := true; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.1','ok', v_ok, 'detail','anon não executa set_my_binder_identity (42501)');

    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    v_err := null; begin perform count(*) from public.get_my_binder_identity(v_co);
    exception when others then v_err := sqlerrm; end;
    v_hint := null; begin perform count(*) from public.get_my_binder_occupancy(v_co);
    exception when others then v_hint := sqlerrm; end;
    res := res || jsonb_build_object('id','1.2','ok', v_err = 'COLLECTION_NOT_FOUND' and v_hint = 'COLLECTION_NOT_FOUND',
      'detail','B lê identidade e ocupação de A → COLLECTION_NOT_FOUND nas duas: ' || coalesce(v_err, 'sem erro') || ' / ' || coalesce(v_hint, 'sem erro'));
    v_err := null; begin perform count(*) from public.set_my_binder_identity(v_co, 'Invasão', false);
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','1.3','ok', v_err = 'COLLECTION_NOT_FOUND',
      'detail','B renomeia o fichário de A → COLLECTION_NOT_FOUND: ' || coalesce(v_err, 'sem erro'));
    v_err := null; begin perform count(*) from public.get_my_binder_participants(v_co);
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','1.4','ok', v_err = 'COLLECTION_NOT_FOUND',
      'detail','B lista participantes de A → COLLECTION_NOT_FOUND: ' || coalesce(v_err, 'sem erro'));
    execute 'reset role';
    res := res || jsonb_build_object('id','1.5','ok',
      (select l.display_name is null and l.show_brand_mark from public.collection_layout l where l.id = l_o),
      'detail','fichário de A intacto após as tentativas de B');

    -- 2. Identidade (proprietária) ----------------------------------------------------------
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select * into o from public.get_my_binder_identity(v_co);
    select * into q from public.get_my_binder_occupancy(v_co);
    res := res || jsonb_build_object('id','2.1','ok',
      o.binder_role = 'OWNER' and o.display_name is null and o.effective_name = 'CO 5853' and o.show_brand_mark
      and o.can_edit_identity and q.pocket_count = 4 and q.page_count = 1
      and q.card_pocket_count + q.image_pocket_count + q.merged_pocket_count + q.reserved_empty_count + q.free_pocket_count = q.pocket_count,
      'detail','leitura inicial: OWNER, sem nome próprio → nome da coleção, logomarca ligada, 4 bolsos (soma fecha)');
    select * into w from public.set_my_binder_identity(v_co, E'  Meu   Fichário  ', true);
    execute 'reset role';
    select l.updated_at into v_ts from public.collection_layout l where l.id = l_o;
    res := res || jsonb_build_object('id','2.2','ok',
      w.operation = 'UPDATED' and w.display_name = 'Meu Fichário' and w.effective_name = 'Meu Fichário'
      and (select l.display_name from public.collection_layout l where l.id = l_o) = 'Meu Fichário',
      'detail','nome normalizado (pontas aparadas, espaços colapsados) e gravado: ' || coalesce(w.display_name, 'NULL'));
    execute 'set local role authenticated';
    select * into w from public.set_my_binder_identity(v_co, 'Meu Fichário', true);
    execute 'reset role';
    res := res || jsonb_build_object('id','2.3','ok',
      w.operation = 'UNCHANGED' and (select l.updated_at from public.collection_layout l where l.id = l_o) = v_ts,
      'detail','mesmo valor → UNCHANGED, updated_at intacto');
    execute 'set local role authenticated';
    v_err := null; begin perform count(*) from public.set_my_binder_identity(v_co, E'Linha\nquebrada', true);
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','2.4','ok', v_err = 'INVALID_BINDER_NAME',
      'detail','quebra de linha → INVALID_BINDER_NAME: ' || coalesce(v_err, 'sem erro'));
    v_err := null; begin perform count(*) from public.set_my_binder_identity(v_co, repeat('a', 61), true);
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','2.5','ok', v_err = 'INVALID_BINDER_NAME',
      'detail','61 caracteres → INVALID_BINDER_NAME: ' || coalesce(v_err, 'sem erro'));
    select * into w from public.set_my_binder_identity(v_co, repeat('é', 60), true);
    res := res || jsonb_build_object('id','2.6','ok', w.operation = 'UPDATED' and char_length(w.display_name) = 60,
      'detail','60 caracteres multibyte aceitos (conta caracteres, não bytes)');
    v_err := null; begin perform count(*) from public.set_my_binder_identity(v_co, 'X', null);
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','2.7','ok', v_err = 'INVALID_ARGUMENT',
      'detail','logomarca nula → INVALID_ARGUMENT: ' || coalesce(v_err, 'sem erro'));
    select * into w from public.set_my_binder_identity(v_co, '   ', false);
    select * into o from public.get_my_binder_identity(v_co);
    res := res || jsonb_build_object('id','2.8','ok',
      w.operation = 'UPDATED' and w.display_name is null and o.display_name is null
      and o.effective_name = 'CO 5853' and not o.show_brand_mark,
      'detail','só espaços → volta ao nome da coleção; logomarca desligada');
    v_err := null; begin update public.collection_layout set display_name = 'Direto' where id = l_o;
    exception when others then v_err := sqlstate; end;
    res := res || jsonb_build_object('id','2.9','ok', v_err = '42501',
      'detail','UPDATE direto como authenticated → 42501: ' || coalesce(v_err, 'sem erro'));
    execute 'reset role';
    v_err := null; begin update public.collection_layout set display_name = ' Fora do padrão' where id = l_o;
    exception when check_violation then v_err := 'CHECK'; end;
    res := res || jsonb_build_object('id','2.10','ok', v_err = 'CHECK',
      'detail','CHECK recusa nome fora do formato canônico mesmo para o dono do banco');
    execute 'set local role authenticated';
    select * into w from public.set_my_binder_identity(v_co, 'Fichário Azul', true);

    -- 3. Compartilhado ---------------------------------------------------------------------
    perform count(*) from public.attach_my_collection_to_binder(v_cg, l_o);
    perform count(*) from public.attach_my_collection_to_binder(v_ce, l_o);
    perform count(*) from public.assign_card_to_slot(s_o2, a_g1);
    select * into o from public.get_my_binder_identity(v_cg);
    select * into q from public.get_my_binder_occupancy(v_cg);
    res := res || jsonb_build_object('id','3.1','ok',
      o.binder_role = 'GUEST' and o.layout_id = l_o and o.effective_name = 'Fichário Azul' and o.show_brand_mark
      and not o.can_edit_identity and o.owner_collection_id = v_co and q.participant_count = 3 and q.layout_id = l_o,
      'detail','convidada lê a mesma identidade, sem permissão de edição; 3 participantes');
    v_err := null; begin perform count(*) from public.set_my_binder_identity(v_cg, 'Tomada', false);
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','3.2','ok', v_err = 'BINDER_OWNER_ONLY',
      'detail','convidada renomeia → BINDER_OWNER_ONLY: ' || coalesce(v_err, 'sem erro'));
    execute 'reset role';
    res := res || jsonb_build_object('id','3.3','ok',
      (select l.display_name = 'Fichário Azul' and l.show_brand_mark from public.collection_layout l where l.id = l_o),
      'detail','identidade intacta após a recusa da convidada');
    execute 'set local role authenticated';
    select count(*), count(*) filter (where binder_role = 'OWNER'), count(*) filter (where is_current),
           sum(card_pocket_count)::integer
      into n, n2, n3, n4
    from public.get_my_binder_participants(v_co);
    res := res || jsonb_build_object('id','3.4','ok', n = 3 and n2 = 1 and n3 = 1 and n4 = 2,
      'detail','proprietária vê 3 participantes (1 OWNER, 1 atual), 2 bolsos com carta no total');
    select count(*) into n from public.get_my_binder_participants(v_cg);
    v_ok := not exists (select 1 from public.get_my_binder_participants(v_cg) x where x.collection_id = v_ce);
    res := res || jsonb_build_object('id','3.5','ok', n = 2 and v_ok,
      'detail','convidada vê só a proprietária e a si mesma (não vê CE)');
    select (x.collection_id = v_co) into v_ok from public.get_my_binder_participants(v_cg) x limit 1;
    res := res || jsonb_build_object('id','3.6','ok', coalesce(v_ok, false), 'detail','proprietária vem primeiro');
    select * into q from public.get_my_binder_occupancy(v_co);
    res := res || jsonb_build_object('id','3.7','ok',
      q.card_pocket_count = 2 and q.free_pocket_count + q.reserved_empty_count = 2
      and q.image_pocket_count = 0 and q.merged_pocket_count = 0 and q.merged_region_count = 0
      and q.card_pocket_count + q.image_pocket_count + q.merged_pocket_count + q.reserved_empty_count + q.free_pocket_count = q.pocket_count,
      'detail','ocupação: 2 com carta (CO + CG), sem imagens/mesclagens, soma = 4');
    v_err := null; begin perform count(*) from public.get_my_binder_identity(v_cb);
    exception when others then v_err := sqlerrm; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','3.8','ok', v_err = 'COLLECTION_NOT_FOUND',
      'detail','A lê o fichário de B (CB) → COLLECTION_NOT_FOUND (simetria de 1.2): ' || coalesce(v_err, 'sem erro'));

    -- 4. Arquivada -----------------------------------------------------------------------------
    execute 'set local role authenticated';
    perform count(*) from public.archive_collection(v_co);
    v_err := null; begin perform count(*) from public.set_my_binder_identity(v_co, 'Arquivo', true);
    exception when others then v_err := sqlerrm; end;
    select * into o from public.get_my_binder_identity(v_co);
    execute 'reset role';
    res := res || jsonb_build_object('id','4.1','ok', v_err = 'COLLECTION_ARCHIVED' and not o.can_edit_identity
      and o.effective_name = 'Fichário Azul',
      'detail','proprietária arquivada: escrita → COLLECTION_ARCHIVED; leitura continua, sem edição: ' || coalesce(v_err, 'sem erro'));

    -- 5. Integridade ---------------------------------------------------------------------------
    select array[(select count(*) from public.collection_layout_page), (select count(*) from public.collection_layout_slot),
                 (select count(*) from public.collection_layout_slot_assignment) - 1,
                 (select count(*) from public.collection_layout_slot_expected_content),
                 (select count(*) from public.collection_layout_region), (select count(*) from public.collection_layout_slot_image),
                 (select count(*) from public.collection_allocation),
                 (select count(*) from public.collection_layout_slot where locked)]
      into i_after;
    res := res || jsonb_build_object('id','5.1','ok', i_before = i_after,
      'detail','identidade não alterou páginas, bolsos, posições (exceto a 1 feita no teste), reservas, regiões, imagens, alocações ou travas');

    raise exception 'MS853' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MS853' then
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
