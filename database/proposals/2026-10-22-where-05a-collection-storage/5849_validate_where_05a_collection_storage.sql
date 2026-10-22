/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5849 - Harness WHERE-05A (5221/5222): prévia e organização
              física atômica dos exemplares de uma coleção no local padrão —
              estrutura, segurança, prévia, execução, concorrência lógica,
              integridade, modalidades e resíduo zero
Versão......: 1.1 (2026-10-22, CONTRACT CONCURRENCY CORRECTION-01: 0.3 confere
              também a trava de todo o universo com NOWAIT e o LOCK_BUSY da 5222
              v1.1; roteiro K4 atualizado no README)
              1.2 (2026-10-22, CONTRACT CORRECTION-02: 0.3 confere as travas de
              exemplar em laço FOREACH ordenado com NOWAIT e o teto D6 sobre o
              total ANTES delas; L.2 nova — D6 pela contagem real, só fora do LIVE)
              1.3 (2026-10-22, OPTIONAL TABLE CORRECTION: a v1.2 abortou no LIVE
              com 42P01 antes de qualquer check — o PL/pgSQL prepara o CASE
              inteiro, inclusive o ramo com public.collection_master_set_scope,
              inexistente no LIVE, e to_regclass não impede isso. As contagens
              das tabelas opcionais (baseline b_pkx/b_ms/b_slot e o check 4.9)
              passam a usar EXECUTE dinâmico só quando to_regclass confirma o
              objeto; ausente = sentinela -1. Nenhum check, ID, gate ou
              protocolo alterado; 5221/5222 intactas.)
              1.4 (2026-10-22, STALE REFERENCE CORRECTION: a v1.3 rodou no LIVE
              com 47/50 — 3.7, 3.8 e 3.9 receberam o erro esperado, mas
              comparavam o mapa com o h_map do 3.6, capturado com a1 em Y antes
              da devolução de a1. Recaptura de h_map logo após a devolução, no
              fim do 3.6. Nenhum check, ID, gate ou protocolo alterado.)
Status......: PROPOSTA. v1.2 abortou (42P01); v1.3 rodou no LIVE com gate
              FAIL 47/50 por referência desatualizada no próprio harness
              (resíduo zero). A v1.4 aguarda execução autorizada; nada aqui é
              PASS até ser executado.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-22

Protocolo (o mesmo da 5847/5848, que já rodaram no LIVE): um único
statement; usuários efêmeros A e B (o Inventory nasce pelo trigger de
auth.users); exemplares sobre UMA variante ATIVA já existente (catálogo só
lido); a sentinela MS849 desfaz tudo; 99.1 prova resíduo zero. Nenhum dado
real é lido como resultado nem alterado.

  select * from pg_temp.wh_5849_validate(false);  -- funcional (padrão)
  select * from pg_temp.wh_5849_validate(true);   -- + Seção L (10.001 exemplares)

  A Seção L (teto pela contagem real) cria 10.001 exemplares sintéticos e é
  CARGA SINTÉTICA: NÃO executar no LIVE (D3/D4). Só em ambiente isolado,
  quando autorizado. Sem ela, o GATE é PASS_FUNCTIONAL_LIMIT_NOT_EXERCISED —
  nunca PASS pleno. O teto pelo argumento declarado (3.3) é coberto sempre.

Fixture (como dono do banco para os exemplares; RPCs canônicas como A/B):
  A — locais X ("F001 — Fichário 5849"), Y ("Caixa 5849").
      C1  (create_collection, padrão X): a1, a2 sem local; a3, a4 em Y;
          a5, a6 em X  → total 6 / sem local 2 / no destino 2 / outros 2.
      C2  (create_collection, padrão Y): c2a sem local (outra coleção).
      CE  (create_collection, padrão X): vazia.
      CS  (create_reference_based_card_set_collection, padrão X): s1, s2 sem
          local (modalidade Set — REFERENCE_BASED/CARD_SET).
      CF  (create_my_free_collection, local X): r1 em Y (Coleção livre).
      Fora de coleção: f1, f2 sem local; f3 em Y; n1 sem local (usado para
          alterar a composição de C1 entre prévia e execução).
  B — local LB; coleção CB (padrão LB) com b1 sem local.

Seções:
  0.x  estrutura, privilégios, retorno exato, helper interno, fixture
  1.x  segurança: anon 42501, sem identidade 28000, helper inacessível,
       coleção/local de outro usuário (não enumera), argumentos nulos
  2.x  prévia: coleção vazia, contagens 6/2/2/2, elegíveis por modalidade,
       destino ≠ padrão, token determinístico e por destino, sem escrita
  3.x  execução: modalidade/argumentos inválidos, teto declarado, contagem
       ou token divergentes, mudança de local / entrada / saída de exemplar
       entre prévia e execução, destino alterado (DEFAULT_CHANGED), local de
       outro usuário, UNLOCATED, confirmação duplicada, no-op, ALL, tudo no
       destino, coleção arquivada — cada recusa com ZERO alterações
  4.x  integridade: exemplares fora da coleção intactos, vínculos intactos,
       colunas além do local intactas, B intacto, Set e Livre, contagem por
       local (5219), estrutura (só physical_card é escrito), Master Set /
       Pokédex / fichário intactos
  L.1  (só p_big) teto pela contagem real: > 10.000 alocados e elegíveis →
       recusa sem alterar nada
  L.2  (só p_big) D6: total > 10.000 com só 1 elegível → recusa pelo TOTAL,
       sem alterar nada (o teto só de elegíveis não recusaria)
  99.1 resíduo zero e papel restaurado
GATE: funcional n = 50, todas PASS. Sem p_big: PASS_FUNCTIONAL_LIMIT_NOT_
      EXERCISED. Com p_big: PASS exige também L.1 e L.2. Desempenho: NÃO MEDIDO
      (fora deste harness; ver README).

Limitações declaradas:
  L1 SET LOCAL ROLE prova o banco, não o JWT do PostgREST.
  L2 Um único statement não tem duas sessões: travas, espera e deadlock
     (FOR UPDATE da coleção × 5036/5046/5047; FOR KEY SHARE do destino ×
     5218; FOR UPDATE NOWAIT de todos os exemplares × 5024) NÃO são
     exercitadas aqui — numa só sessão as próprias travas não conflitam. A
     concorrência LÓGICA (estado mudou entre prévia e execução) é provada
     de forma sequencial (3.6–3.9, 3.12). Prova de sessões concorrentes:
     roteiro manual K1–K4 no README, fora deste harness.
  L3 Pokédex e Master Set: provados por estrutura (4.8) e invariância das
     tabelas próprias (4.9), não por fixture de vínculo de posição — o
     mecanismo físico (collection_allocation) é o mesmo das modalidades
     cobertas por fixture (OPEN, Set, Livre).
  L4 Seção L é carga sintética — só fora do LIVE.
================================================================
*/

create or replace function pg_temp.wh_5849_validate(p_big boolean default false)
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  f_plan oid := to_regprocedure('public.get_my_collection_storage_plan(uuid, uuid)');
  f_org  oid := to_regprocedure('public.organize_my_collection_storage(uuid, uuid, text, integer, text)');
  f_snap oid := to_regprocedure('public.collection_storage_plan_snapshot(uuid, uuid)');
  p_user_a uuid := gen_random_uuid();
  p_user_b uuid := gen_random_uuid();
  v_sfx text := lower(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  v_inv_a uuid; v_inv_b uuid; v_game uuid; v_pt uuid; v_var uuid; v_set uuid;
  v_ids uuid[];
  a1 uuid; a2 uuid; a3 uuid; a4 uuid; a5 uuid; a6 uuid;
  f1 uuid; f2 uuid; f3 uuid; n1 uuid; c2a uuid; s1 uuid; s2 uuid; r1 uuid; b1 uuid;
  v_x uuid; v_y uuid; v_lb uuid;
  v_c1 uuid; v_c2 uuid; v_ce uuid; v_cs uuid; v_cf uuid; v_cb uuid;
  p record; p2 record; o record;
  v_ok boolean; v_err text; v_tok text;
  h_map text; h_map2 text; h_rest text; h_b text; h_alloc text;
  n integer;
  b_us bigint; b_sc bigint; b_co bigint; b_ca bigint; b_pc bigint; b_cr bigint; b_ccr bigint;
  b_pkx bigint; b_ms bigint; b_slot bigint;
  c_pkx bigint; c_ms bigint; c_slot bigint;   -- v1.3: contagens finais das tabelas opcionais (4.9)
  res jsonb := '[]'::jsonb; r jsonb; cnt integer := 0; passes integer := 0;
  v_expected integer := 50;
  v_plan_sig text := 'TABLE(collection_id uuid, storage_container_id uuid, collection_active boolean, '
    || 'target_is_default boolean, total_count integer, unlocated_count integer, at_target_count integer, '
    || 'elsewhere_count integer, eligible_unlocated integer, eligible_all integer, max_per_operation integer, plan_token text)';
  v_org_sig text := 'TABLE(collection_id uuid, storage_container_id uuid, mode text, moved_count integer, '
    || 'total_count integer, at_target_count integer)';
begin
  -- 0. Estrutura ---------------------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok', f_plan is not null and f_org is not null and f_snap is not null,
    'detail','5221 (get_my_collection_storage_plan + helper) e 5222 (organize_my_collection_storage) presentes');

  if f_plan is null or f_org is null or f_snap is null then
    res := res || jsonb_build_object('id','X.0','ok', false, 'detail','aplique 5221 e 5222 antes deste harness');
  else
  res := res || jsonb_build_object('id','0.2','ok',
    (select p.prosecdef and p.provolatile = 'v' and p.proconfig = array['search_path=""'] from pg_proc p where p.oid = f_plan),
    'detail','5221: SECURITY DEFINER, VOLATILE, search_path vazio');
  res := res || jsonb_build_object('id','0.3','ok',
    (select p.prosecdef and p.provolatile = 'v'
            and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s']
     from pg_proc p where p.oid = f_org)
    and (select lower(d) like '%foreach v_id in array v_all loop%'
                and lower(d) like '%array_agg(ca.physical_card_id order by ca.physical_card_id)%'
                and (length(lower(d)) - length(replace(lower(d), 'for update nowait', ''))) / length('for update nowait') = 1
                and lower(d) not like '%for update of pc%'
                and lower(d) like '%when lock_not_available then%'
                and d like '%LOCK_BUSY%'
                and strpos(lower(d), 'd6: teto sobre o total') > 0
                and strpos(lower(d), 'd6: teto sobre o total') < strpos(lower(d), 'foreach v_id in array v_all')
         from (select pg_get_functiondef(f_org) d) q),
    'detail','5222 v1.2: SECURITY DEFINER, VOLATILE, search_path vazio, lock_timeout 5s; travas de exemplar uma a uma (FOREACH sobre ids ordenados, FOR UPDATE NOWAIT → LOCK_BUSY); teto D6 sobre o total antes delas');
  res := res || jsonb_build_object('id','0.4','ok',
    (select not p.prosecdef and p.provolatile = 'v' and p.proconfig = array['search_path=""'] from pg_proc p where p.oid = f_snap),
    'detail','helper: SECURITY INVOKER, VOLATILE, search_path vazio (padrão 5149)');
  res := res || jsonb_build_object('id','0.5','ok',
    has_function_privilege('authenticated', f_plan, 'EXECUTE') and has_function_privilege('authenticated', f_org, 'EXECUTE')
    and not has_function_privilege('anon', f_plan, 'EXECUTE') and not has_function_privilege('anon', f_org, 'EXECUTE')
    and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid in (f_plan, f_org) and a.grantee = 0),
    'detail','5221/5222: EXECUTE só authenticated; anon e PUBLIC sem acesso');
  res := res || jsonb_build_object('id','0.6','ok',
    (select p.proacl is not null from pg_proc p where p.oid = f_snap)
    and not has_function_privilege('anon', f_snap, 'EXECUTE')
    and not has_function_privilege('authenticated', f_snap, 'EXECUTE')
    and not has_function_privilege('service_role', f_snap, 'EXECUTE')
    and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = f_snap and a.grantee = 0),
    'detail','helper interno: nenhum papel de API (PUBLIC/anon/authenticated/service_role) executa');
  res := res || jsonb_build_object('id','0.7','ok',
    pg_get_function_result(f_plan) = v_plan_sig and pg_get_function_result(f_org) = v_org_sig,
    'detail','retornos exatos de 5221 (12 colunas) e 5222 (6 colunas)');

  select count(*) into b_us from auth.users;
  select count(*) into b_sc from public.storage_container;
  select count(*) into b_co from public.collection;
  select count(*) into b_ca from public.collection_allocation;
  select count(*) into b_pc from public.physical_card;
  select count(*) into b_cr from public.collection_reference;
  select count(*) into b_ccr from public.collection_creation_request;
  -- v1.3: tabelas OPCIONAIS só por EXECUTE dinâmico, após to_regclass confirmar
  -- o objeto (referência estática falha na preparação mesmo no ramo não
  -- executado — 42P01 da v1.2). Ausente = sentinela -1.
  b_pkx := -1; b_ms := -1; b_slot := -1;
  if to_regclass('public.collection_pokedex_position_assignment') is not null then
    execute 'select count(*) from public.collection_pokedex_position_assignment' into b_pkx;
  end if;
  if to_regclass('public.collection_master_set_scope') is not null then
    execute 'select count(*) from public.collection_master_set_scope' into b_ms;
  end if;
  if to_regclass('public.collection_layout_slot_assignment') is not null then
    execute 'select count(*) from public.collection_layout_slot_assignment' into b_slot;
  end if;

  begin
    -- Fixture de catálogo (dono do banco; só leitura) ------------------------------
    select g.id into v_game from public.game g where g.code = 'POKEMON';
    select l.id into v_pt from public.language l where l.code = 'pt-BR';
    select d.id, c.card_set_id into v_var, v_set
    from public.card c
    join public.card_set cs on cs.id = c.card_set_id
    join public.card_variant d on d.card_id = c.id and d.is_active and d.is_default
    where c.is_active
    order by cs.release_date desc nulls last, c.collector_order
    limit 1;
    v_ok := v_game is not null and v_pt is not null and v_var is not null and v_set is not null;
    res := res || jsonb_build_object('id','0.8','ok', v_ok, 'detail','fixture de catálogo: Game POKEMON, pt-BR, uma variante ativa padrão');
    if not v_ok then raise exception 'MS849' using errcode = 'P0001'; end if;

    -- Usuários efêmeros e exemplares -------------------------------------------------
    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    values (p_user_a, 'authenticated', 'authenticated', 'wh5849-a-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'wh5849a_'||v_sfx, 'display_name', 'WH 5849 A'), now(), now()),
           (p_user_b, 'authenticated', 'authenticated', 'wh5849-b-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'wh5849b_'||v_sfx, 'display_name', 'WH 5849 B'), now(), now());
    select i.id into v_inv_a from public.inventory i where i.owner_user_id = p_user_a;
    select i.id into v_inv_b from public.inventory i where i.owner_user_id = p_user_b;

    insert into public.physical_card (card_variant_id, language_id, inventory_id, created_at)
    select v_var, v_pt, v_inv_a, now() - make_interval(secs => g) from generate_series(1, 16) g;
    select array_agg(pc.id order by pc.created_at desc) into v_ids from public.physical_card pc where pc.inventory_id = v_inv_a;
    a1 := v_ids[1]; a2 := v_ids[2]; a3 := v_ids[3]; a4 := v_ids[4]; a5 := v_ids[5]; a6 := v_ids[6];
    f1 := v_ids[7]; f2 := v_ids[8]; f3 := v_ids[9]; n1 := v_ids[10]; c2a := v_ids[11];
    s1 := v_ids[12]; s2 := v_ids[13]; r1 := v_ids[14];
    insert into public.physical_card (card_variant_id, language_id, inventory_id, created_at)
    values (v_var, v_pt, v_inv_b, now());
    select pc.id into b1 from public.physical_card pc where pc.inventory_id = v_inv_b;

    -- B ---------------------------------------------------------------------------
    perform set_config('request.jwt.claim.sub', p_user_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select x.id into v_lb from public.create_storage_container('Local B 5849') x;
    select x.id into v_cb from public.create_collection(v_game, 'Coleção B 5849', null, v_lb) x;
    perform public.allocate_physical_cards_to_collection(v_cb, array[b1]);
    execute 'reset role';
    select md5(string_agg(to_jsonb(pc)::text, ',' order by pc.id)) into h_b
    from public.physical_card pc where pc.inventory_id = v_inv_b;

    -- A ---------------------------------------------------------------------------
    perform set_config('request.jwt.claim.sub', p_user_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select x.id into v_x from public.create_storage_container('F001 — Fichário 5849') x;
    select x.id into v_y from public.create_storage_container('Caixa 5849') x;
    select x.id into v_c1 from public.create_collection(v_game, 'C1 5849', null, v_x) x;
    select x.id into v_c2 from public.create_collection(v_game, 'C2 5849', null, v_y) x;
    select x.id into v_ce from public.create_collection(v_game, 'CE 5849', null, v_x) x;
    select x.id into v_cs from public.create_reference_based_card_set_collection(v_game, 'CS 5849', null, v_x, v_set) x;
    select x.collection_id into v_cf from public.create_my_free_collection(gen_random_uuid(), 'CF 5849', v_x) x;
    perform public.allocate_physical_cards_to_collection(v_c1, array[a1, a2, a3, a4, a5, a6]);
    perform public.allocate_physical_cards_to_collection(v_c2, array[c2a]);
    perform public.allocate_physical_cards_to_collection(v_cs, array[s1, s2]);
    perform public.allocate_physical_cards_to_collection(v_cf, array[r1]);
    perform public.set_physical_cards_storage(v_y, array[a3, a4, f3, r1]);
    perform public.set_physical_cards_storage(v_x, array[a5, a6]);
    execute 'reset role';

    -- Estado de referência de A (dono do banco) ----------------------------------
    select md5(string_agg(pc.id::text || ':' || coalesce(pc.storage_container_id::text, '-'), ',' order by pc.id)) into h_map
    from public.physical_card pc where pc.inventory_id = v_inv_a;
    select md5(string_agg((to_jsonb(pc) - 'storage_container_id' - 'updated_at')::text, ',' order by pc.id)) into h_rest
    from public.physical_card pc where pc.inventory_id = v_inv_a;
    select md5(string_agg(ca.physical_card_id::text || '>' || ca.collection_id::text || '@' || ca.created_at::text, ','
                          order by ca.physical_card_id)) into h_alloc
    from public.collection_allocation ca join public.physical_card pc on pc.id = ca.physical_card_id
    where pc.inventory_id = v_inv_a;

    -- 1. Segurança -------------------------------------------------------------------
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);
    execute 'set local role anon';
    begin
      perform count(*) from public.get_my_collection_storage_plan(v_c1, v_x); v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlstate = '42501'; v_err := sqlstate;
    end;
    res := res || jsonb_build_object('id','1.1','ok', v_ok, 'detail','anon sem EXECUTE na 5221: '||v_err);
    begin
      perform count(*) from public.organize_my_collection_storage(v_c1, v_x, 'ALL', 0, 'v1:'||md5('x')); v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlstate = '42501'; v_err := sqlstate;
    end;
    res := res || jsonb_build_object('id','1.2','ok', v_ok, 'detail','anon sem EXECUTE na 5222: '||v_err);
    execute 'reset role';
    execute 'set local role authenticated';
    begin
      perform count(*) from public.get_my_collection_storage_plan(v_c1, v_x); v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlstate = '28000'; v_err := sqlstate;
    end;
    res := res || jsonb_build_object('id','1.3','ok', v_ok, 'detail','5221 sem auth.uid(): '||v_err);
    begin
      perform count(*) from public.organize_my_collection_storage(v_c1, v_x, 'ALL', 0, 'v1:'||md5('x')); v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlstate = '28000'; v_err := sqlstate;
    end;
    res := res || jsonb_build_object('id','1.4','ok', v_ok, 'detail','5222 sem auth.uid(): '||v_err);
    execute 'reset role';

    perform set_config('request.jwt.claim.sub', p_user_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    begin
      perform count(*) from public.collection_storage_plan_snapshot(v_c1, v_x); v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlstate = '42501'; v_err := sqlstate;
    end;
    res := res || jsonb_build_object('id','1.5','ok', v_ok, 'detail','helper interno inacessível a authenticated: '||v_err);
    begin
      perform count(*) from public.get_my_collection_storage_plan(v_cb, v_x); v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlstate = 'P0002' and sqlerrm = 'COLLECTION_NOT_FOUND'; v_err := sqlstate||' '||sqlerrm;
    end;
    res := res || jsonb_build_object('id','1.6','ok', v_ok, 'detail','prévia da coleção de B por A: '||v_err);
    begin
      perform count(*) from public.get_my_collection_storage_plan(gen_random_uuid(), v_x); v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlstate = 'P0002' and sqlerrm = 'COLLECTION_NOT_FOUND'; v_err := sqlstate||' '||sqlerrm;
    end;
    res := res || jsonb_build_object('id','1.7','ok', v_ok, 'detail','coleção inexistente = mesma resposta (não enumera): '||v_err);
    begin
      perform count(*) from public.get_my_collection_storage_plan(v_c1, v_lb); v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlstate = 'P0002' and sqlerrm = 'STORAGE_NOT_FOUND'; v_err := sqlstate||' '||sqlerrm;
    end;
    res := res || jsonb_build_object('id','1.8','ok', v_ok, 'detail','prévia com local de B: '||v_err);
    begin
      perform count(*) from public.organize_my_collection_storage(v_cb, v_lb, 'ALL', 1, 'v1:'||md5('x')); v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlstate = 'P0002' and sqlerrm = 'COLLECTION_NOT_FOUND'; v_err := sqlstate||' '||sqlerrm;
    end;
    res := res || jsonb_build_object('id','1.9','ok', v_ok, 'detail','A organizando a coleção de B: '||v_err);
    begin
      perform count(*) from public.get_my_collection_storage_plan(null, v_x); v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlstate = '22023' and sqlerrm = 'INVALID_ARGUMENT'; v_err := sqlstate||' '||sqlerrm;
    end;
    res := res || jsonb_build_object('id','1.10','ok', v_ok, 'detail','argumento nulo: '||v_err);

    -- 2. Prévia ---------------------------------------------------------------------
    select * into p from public.get_my_collection_storage_plan(v_ce, v_x);
    res := res || jsonb_build_object('id','2.1','ok',
      p.total_count = 0 and p.eligible_unlocated = 0 and p.eligible_all = 0 and p.plan_token ~ '^v1:[0-9a-f]{32}$',
      'detail', format('coleção vazia: total %s, elegíveis %s/%s', p.total_count, p.eligible_unlocated, p.eligible_all));
    select * into p from public.get_my_collection_storage_plan(v_c1, v_x);
    res := res || jsonb_build_object('id','2.2','ok',
      p.total_count = 6 and p.unlocated_count = 2 and p.at_target_count = 2 and p.elsewhere_count = 2
      and p.eligible_unlocated = 2 and p.eligible_all = 4 and p.target_is_default and p.collection_active
      and p.max_per_operation = 10000,
      'detail', format('C1→X: total %s / sem local %s / no destino %s / outros %s; UNLOCATED %s, ALL %s (esperado 6/2/2/2; 2, 4)',
        p.total_count, p.unlocated_count, p.at_target_count, p.elsewhere_count, p.eligible_unlocated, p.eligible_all));
    select * into p2 from public.get_my_collection_storage_plan(v_c1, v_y);
    res := res || jsonb_build_object('id','2.3','ok',
      not p2.target_is_default and p2.at_target_count = 2 and p2.elsewhere_count = 2 and p2.eligible_all = 4,
      'detail','C1→Y (não é o padrão): target_is_default = false, contagens relativas a Y');
    select x.plan_token into v_tok from public.get_my_collection_storage_plan(v_c1, v_x) x;
    res := res || jsonb_build_object('id','2.4','ok', v_tok = p.plan_token, 'detail','token determinístico (duas prévias iguais)');
    res := res || jsonb_build_object('id','2.5','ok', p2.plan_token <> p.plan_token, 'detail','token muda com o destino');
    select md5(string_agg(pc.id::text || ':' || coalesce(pc.storage_container_id::text, '-'), ',' order by pc.id)) into h_map2
    from public.physical_card pc;   -- RLS: só os de A
    res := res || jsonb_build_object('id','2.6','ok', h_map2 = h_map, 'detail','a prévia não escreve nada');

    -- 3. Execução ------------------------------------------------------------------
    begin
      perform count(*) from public.organize_my_collection_storage(v_c1, v_x, 'TUDO', 2, p.plan_token); v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlstate = '22023' and sqlerrm = 'INVALID_MODE'; v_err := sqlstate||' '||sqlerrm;
    end;
    res := res || jsonb_build_object('id','3.1','ok', v_ok, 'detail','modalidade inválida: '||v_err);
    begin
      perform count(*) from public.organize_my_collection_storage(v_c1, v_x, 'UNLOCATED', 2, 'abc'); v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlstate = '22023' and sqlerrm = 'INVALID_ARGUMENT'; v_err := sqlstate||' '||sqlerrm;
    end;
    res := res || jsonb_build_object('id','3.2','ok', v_ok, 'detail','identificação da prévia mal formada: '||v_err);
    begin
      perform count(*) from public.organize_my_collection_storage(v_c1, v_x, 'ALL', 10001, p.plan_token); v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlstate = '54000' and sqlerrm = 'COLLECTION_TOO_LARGE'; v_err := sqlstate||' '||sqlerrm;
    end;
    res := res || jsonb_build_object('id','3.3','ok', v_ok, 'detail','teto declarado (10.001 > 10.000): '||v_err);
    begin
      perform count(*) from public.organize_my_collection_storage(v_c1, v_x, 'UNLOCATED', 3, p.plan_token); v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlerrm = 'PLAN_CHANGED'; v_err := sqlstate||' '||sqlerrm;
    end;
    select md5(string_agg(pc.id::text || ':' || coalesce(pc.storage_container_id::text, '-'), ',' order by pc.id)) into h_map2 from public.physical_card pc;
    res := res || jsonb_build_object('id','3.4','ok', v_ok and h_map2 = h_map, 'detail','quantidade diferente da prévia → PLAN_CHANGED, zero alterações: '||v_err);
    begin
      perform count(*) from public.organize_my_collection_storage(v_c1, v_x, 'UNLOCATED', 2, p2.plan_token); v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlerrm = 'PLAN_CHANGED'; v_err := sqlstate||' '||sqlerrm;
    end;
    select md5(string_agg(pc.id::text || ':' || coalesce(pc.storage_container_id::text, '-'), ',' order by pc.id)) into h_map2 from public.physical_card pc;
    res := res || jsonb_build_object('id','3.5','ok', v_ok and h_map2 = h_map, 'detail','token de outra prévia → PLAN_CHANGED, zero alterações: '||v_err);

    -- 3.6 local de um exemplar muda entre prévia e execução (outra aba: 5024)
    select * into p from public.get_my_collection_storage_plan(v_c1, v_x);
    perform public.set_physical_cards_storage(v_y, array[a1]);
    select md5(string_agg(pc.id::text || ':' || coalesce(pc.storage_container_id::text, '-'), ',' order by pc.id)) into h_map from public.physical_card pc;
    begin
      perform count(*) from public.organize_my_collection_storage(v_c1, v_x, 'UNLOCATED', p.eligible_unlocated, p.plan_token); v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlerrm = 'PLAN_CHANGED'; v_err := sqlstate||' '||sqlerrm;
    end;
    select md5(string_agg(pc.id::text || ':' || coalesce(pc.storage_container_id::text, '-'), ',' order by pc.id)) into h_map2 from public.physical_card pc;
    res := res || jsonb_build_object('id','3.6','ok', v_ok and h_map2 = h_map, 'detail','local alterado após a prévia → PLAN_CHANGED, nada movido: '||v_err);
    perform public.set_physical_cards_storage(null, array[a1]);   -- volta ao estado da fixture
    -- v1.4: nova referência após devolver a1 (3.7–3.9 comparavam com o mapa de a1 em Y)
    select md5(string_agg(pc.id::text || ':' || coalesce(pc.storage_container_id::text, '-'), ',' order by pc.id)) into h_map from public.physical_card pc;

    -- 3.7 exemplar entra na coleção entre prévia e execução (5046)
    select * into p from public.get_my_collection_storage_plan(v_c1, v_x);
    perform public.allocate_physical_cards_to_collection(v_c1, array[n1]);
    begin
      perform count(*) from public.organize_my_collection_storage(v_c1, v_x, 'UNLOCATED', p.eligible_unlocated, p.plan_token); v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlerrm = 'PLAN_CHANGED'; v_err := sqlstate||' '||sqlerrm;
    end;
    select md5(string_agg(pc.id::text || ':' || coalesce(pc.storage_container_id::text, '-'), ',' order by pc.id)) into h_map2 from public.physical_card pc;
    res := res || jsonb_build_object('id','3.7','ok', v_ok and h_map2 = h_map, 'detail','exemplar vinculado após a prévia → PLAN_CHANGED (n1 não é movido em silêncio): '||v_err);

    -- 3.8 exemplar sai da coleção entre prévia e execução (5047)
    select * into p from public.get_my_collection_storage_plan(v_c1, v_x);
    perform public.deallocate_physical_cards_from_collection(v_c1, array[n1]);
    begin
      perform count(*) from public.organize_my_collection_storage(v_c1, v_x, 'UNLOCATED', p.eligible_unlocated, p.plan_token); v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlerrm = 'PLAN_CHANGED'; v_err := sqlstate||' '||sqlerrm;
    end;
    select md5(string_agg(pc.id::text || ':' || coalesce(pc.storage_container_id::text, '-'), ',' order by pc.id)) into h_map2 from public.physical_card pc;
    res := res || jsonb_build_object('id','3.8','ok', v_ok and h_map2 = h_map, 'detail','exemplar desvinculado após a prévia → PLAN_CHANGED (n1 não é movido): '||v_err);

    -- 3.9 local padrão trocado entre prévia e execução (5036)
    select * into p from public.get_my_collection_storage_plan(v_c1, v_x);
    perform public.set_collection_default_storage(v_c1, v_y);
    begin
      perform count(*) from public.organize_my_collection_storage(v_c1, v_x, 'UNLOCATED', p.eligible_unlocated, p.plan_token); v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlerrm = 'DEFAULT_CHANGED'; v_err := sqlstate||' '||sqlerrm;
    end;
    select md5(string_agg(pc.id::text || ':' || coalesce(pc.storage_container_id::text, '-'), ',' order by pc.id)) into h_map2 from public.physical_card pc;
    res := res || jsonb_build_object('id','3.9','ok', v_ok and h_map2 = h_map, 'detail','destino deixou de ser o padrão → DEFAULT_CHANGED, nada movido: '||v_err);
    perform public.set_collection_default_storage(v_c1, v_x);

    begin
      perform count(*) from public.organize_my_collection_storage(v_c1, v_lb, 'UNLOCATED', p.eligible_unlocated, p.plan_token); v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlstate = 'P0002' and sqlerrm = 'STORAGE_NOT_FOUND'; v_err := sqlstate||' '||sqlerrm;
    end;
    res := res || jsonb_build_object('id','3.10','ok', v_ok, 'detail','destino de outro usuário: '||v_err);

    -- 3.11 UNLOCATED com estado inalterado
    select * into p from public.get_my_collection_storage_plan(v_c1, v_x);
    select * into o from public.organize_my_collection_storage(v_c1, v_x, 'UNLOCATED', p.eligible_unlocated, p.plan_token);
    select count(*) into n from public.physical_card pc where pc.id in (a1, a2) and pc.storage_container_id = v_x;
    v_ok := o.moved_count = 2 and n = 2 and o.total_count = 6 and o.at_target_count = 4 and o.mode = 'UNLOCATED'
      and (select count(*) from public.physical_card pc where pc.id in (a3, a4) and pc.storage_container_id = v_y) = 2;
    res := res || jsonb_build_object('id','3.11','ok', v_ok,
      'detail', format('UNLOCATED: movidos %s (a1, a2 → X); a3, a4 continuam em Y; no destino %s de %s', o.moved_count, o.at_target_count, o.total_count));

    -- 3.12 confirmação duplicada (mesma prévia)
    select md5(string_agg(pc.id::text || ':' || coalesce(pc.storage_container_id::text, '-'), ',' order by pc.id)) into h_map from public.physical_card pc;
    begin
      perform count(*) from public.organize_my_collection_storage(v_c1, v_x, 'UNLOCATED', p.eligible_unlocated, p.plan_token); v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlerrm = 'PLAN_CHANGED'; v_err := sqlstate||' '||sqlerrm;
    end;
    select md5(string_agg(pc.id::text || ':' || coalesce(pc.storage_container_id::text, '-'), ',' order by pc.id)) into h_map2 from public.physical_card pc;
    res := res || jsonb_build_object('id','3.12','ok', v_ok and h_map2 = h_map, 'detail','repetir a mesma confirmação → PLAN_CHANGED, nada muda: '||v_err);

    -- 3.13 nada a mover (no-op idempotente)
    select * into p from public.get_my_collection_storage_plan(v_c1, v_x);
    select * into o from public.organize_my_collection_storage(v_c1, v_x, 'UNLOCATED', p.eligible_unlocated, p.plan_token);
    select md5(string_agg(pc.id::text || ':' || coalesce(pc.storage_container_id::text, '-'), ',' order by pc.id)) into h_map2 from public.physical_card pc;
    res := res || jsonb_build_object('id','3.13','ok', p.eligible_unlocated = 0 and o.moved_count = 0 and h_map2 = h_map,
      'detail','nova prévia: UNLOCATED 0; executar move 0 e não altera nada');

    -- 3.14 ALL
    select * into p from public.get_my_collection_storage_plan(v_c1, v_x);
    select * into o from public.organize_my_collection_storage(v_c1, v_x, 'ALL', p.eligible_all, p.plan_token);
    res := res || jsonb_build_object('id','3.14','ok',
      p.eligible_all = 2 and o.moved_count = 2 and o.at_target_count = 6 and o.total_count = 6
      and (select count(*) from public.physical_card pc where pc.id in (a3, a4) and pc.storage_container_id = v_x) = 2,
      'detail', format('ALL: elegíveis %s, movidos %s (a3, a4 de Y → X); no destino %s de %s', p.eligible_all, o.moved_count, o.at_target_count, o.total_count));

    -- 3.15 todos já no destino
    select * into p from public.get_my_collection_storage_plan(v_c1, v_x);
    res := res || jsonb_build_object('id','3.15','ok', p.eligible_all = 0 and p.eligible_unlocated = 0 and p.at_target_count = p.total_count,
      'detail','depois do ALL: nada elegível; no destino = total');

    -- 3.16 coleção arquivada
    perform public.archive_collection(v_c1);
    select * into p from public.get_my_collection_storage_plan(v_c1, v_x);
    begin
      perform count(*) from public.organize_my_collection_storage(v_c1, v_x, 'ALL', p.eligible_all, p.plan_token); v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlstate = '55000' and sqlerrm = 'COLLECTION_ARCHIVED'; v_err := sqlstate||' '||sqlerrm;
    end;
    res := res || jsonb_build_object('id','3.16','ok', v_ok and not p.collection_active,
      'detail','arquivada: prévia mostra collection_active = false; execução recusada: '||v_err);

    -- 4. Integridade -----------------------------------------------------------------
    v_ok := (select count(*) from public.physical_card pc where pc.id in (f1, f2, n1, c2a, s1, s2) and pc.storage_container_id is null) = 6
      and (select count(*) from public.physical_card pc where pc.id in (f3, r1) and pc.storage_container_id = v_y) = 2;
    res := res || jsonb_build_object('id','4.1','ok', v_ok,
      'detail','exemplares fora de C1 (sem coleção, outra coleção, Set, Livre) intactos após as operações em C1');

    -- 4.5 Set (REFERENCE_BASED / CARD_SET) e 4.6 Livre: mesma operação funciona
    select * into p from public.get_my_collection_storage_plan(v_cs, v_x);
    select * into o from public.organize_my_collection_storage(v_cs, v_x, 'UNLOCATED', p.eligible_unlocated, p.plan_token);
    res := res || jsonb_build_object('id','4.5','ok', p.total_count = 2 and o.moved_count = 2 and o.at_target_count = 2,
      'detail', format('coleção de Set: total %s, movidos %s', p.total_count, o.moved_count));
    select * into p from public.get_my_collection_storage_plan(v_cf, v_x);
    select * into o from public.organize_my_collection_storage(v_cf, v_x, 'ALL', p.eligible_all, p.plan_token);
    res := res || jsonb_build_object('id','4.6','ok', p.total_count = 1 and p.elsewhere_count = 1 and o.moved_count = 1,
      'detail', format('Coleção livre: r1 de Y → X (movidos %s)', o.moved_count));

    select (select l.card_count from public.get_my_storage_locations() l where l.storage_container_id = v_x) into n;
    res := res || jsonb_build_object('id','4.7','ok', n = 9,
      'detail','5219: X guarda 9 exemplares (C1 6 + Set 2 + Livre 1): '||coalesce(n::text,'NULL'));
    execute 'reset role';

    select md5(string_agg(ca.physical_card_id::text || '>' || ca.collection_id::text || '@' || ca.created_at::text, ','
                          order by ca.physical_card_id)) into h_map2
    from public.collection_allocation ca join public.physical_card pc on pc.id = ca.physical_card_id
    where pc.inventory_id = v_inv_a;
    res := res || jsonb_build_object('id','4.2','ok', h_map2 = h_alloc, 'detail','vínculos com coleções de A idênticos aos da fixture');
    select md5(string_agg((to_jsonb(pc) - 'storage_container_id' - 'updated_at')::text, ',' order by pc.id)) into h_map2
    from public.physical_card pc where pc.inventory_id = v_inv_a;
    res := res || jsonb_build_object('id','4.3','ok', h_map2 = h_rest,
      'detail','exemplares de A: só local e updated_at mudaram (variante, idioma, condição, acervo, criação intactos); nenhum criado/removido');
    select md5(string_agg(to_jsonb(pc)::text, ',' order by pc.id)) into h_map2
    from public.physical_card pc where pc.inventory_id = v_inv_b;
    res := res || jsonb_build_object('id','4.4','ok', h_map2 = h_b, 'detail','acervo de B intacto (linha a linha)');

    res := res || jsonb_build_object('id','4.8','ok',
      (select (length(lower(d)) - length(replace(lower(d), 'update public.', ''))) / length('update public.') = 1
              and lower(d) like '%update public.physical_card%'
              and lower(d) not like '%insert into%' and lower(d) not like '%delete from%'
              and lower(d) not like '%pokedex%' and lower(d) not like '%master_set%' and lower(d) not like '%layout%'
       from (select pg_get_functiondef(f_org) d) q)
      and (select lower(d) not like '%update %' and lower(d) not like '%insert %' and lower(d) not like '%delete %'
           from (select pg_get_functiondef(f_snap) d) q),
      'detail','estrutura: a 5222 escreve só em physical_card (um UPDATE) e não toca Pokédex/Master Set/fichário; o helper não escreve');
    -- v1.3: mesma regra do baseline — EXECUTE dinâmico só se o objeto existir.
    c_pkx := -1; c_ms := -1; c_slot := -1;
    if to_regclass('public.collection_pokedex_position_assignment') is not null then
      execute 'select count(*) from public.collection_pokedex_position_assignment' into c_pkx;
    end if;
    if to_regclass('public.collection_master_set_scope') is not null then
      execute 'select count(*) from public.collection_master_set_scope' into c_ms;
    end if;
    if to_regclass('public.collection_layout_slot_assignment') is not null then
      execute 'select count(*) from public.collection_layout_slot_assignment' into c_slot;
    end if;
    res := res || jsonb_build_object('id','4.9','ok',
      b_pkx = c_pkx and b_ms = c_ms and b_slot = c_slot,
      'detail', format('posições da Pokédex, escopo do Master Set e posições do fichário inalterados (antes/depois: %s/%s, %s/%s, %s/%s; -1 = objeto ausente)',
        b_pkx, c_pkx, b_ms, c_ms, b_slot, c_slot));

    -- L. Teto pela contagem real (carga sintética — só fora do LIVE) -------------------
    if p_big then
      insert into public.physical_card (card_variant_id, language_id, inventory_id, created_at)
      select v_var, v_pt, v_inv_a, now() from generate_series(1, 10001);
      insert into public.collection_allocation (physical_card_id, collection_id)
      select pc.id, v_ce from public.physical_card pc
      where pc.inventory_id = v_inv_a and pc.id not in (select ca.physical_card_id from public.collection_allocation ca);
      perform set_config('request.jwt.claim.sub', p_user_a::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role', 'authenticated')::text, true);
      execute 'set local role authenticated';
      select * into p from public.get_my_collection_storage_plan(v_ce, v_x);
      select md5(string_agg(pc.id::text || ':' || coalesce(pc.storage_container_id::text, '-'), ',' order by pc.id)) into h_map from public.physical_card pc;
      begin
        perform count(*) from public.organize_my_collection_storage(v_ce, v_x, 'UNLOCATED', 10000, p.plan_token); v_ok := false; v_err := 'executou';
      exception when others then v_ok := sqlstate = '54000' and sqlerrm = 'COLLECTION_TOO_LARGE'; v_err := sqlstate||' '||sqlerrm;
      end;
      select md5(string_agg(pc.id::text || ':' || coalesce(pc.storage_container_id::text, '-'), ',' order by pc.id)) into h_map2 from public.physical_card pc;
      execute 'reset role';
      res := res || jsonb_build_object('id','L.1','ok', v_ok and h_map2 = h_map and p.eligible_unlocated > 10000,
        'detail', format('> 10.000 elegíveis e alocados reais (prévia: total %s, elegíveis %s) → recusa sem alterar nada: %s',
          p.total_count, p.eligible_unlocated, v_err));

      -- L.2 D6: deixa só 1 elegível (o resto vai para X, como dono) — o total segue > 10.000.
      update public.physical_card pc set storage_container_id = v_x
      where pc.id in (select ca.physical_card_id from public.collection_allocation ca where ca.collection_id = v_ce)
        and pc.id <> (select min(ca.physical_card_id::text)::uuid from public.collection_allocation ca
                      join public.physical_card q on q.id = ca.physical_card_id
                      where ca.collection_id = v_ce and q.storage_container_id is null);
      execute 'set local role authenticated';
      select * into p from public.get_my_collection_storage_plan(v_ce, v_x);
      select md5(string_agg(pc.id::text || ':' || coalesce(pc.storage_container_id::text, '-'), ',' order by pc.id)) into h_map from public.physical_card pc;
      begin
        perform count(*) from public.organize_my_collection_storage(v_ce, v_x, 'UNLOCATED', p.eligible_unlocated, p.plan_token); v_ok := false; v_err := 'executou';
      exception when others then v_ok := sqlstate = '54000' and sqlerrm = 'COLLECTION_TOO_LARGE'; v_err := sqlstate||' '||sqlerrm;
      end;
      select md5(string_agg(pc.id::text || ':' || coalesce(pc.storage_container_id::text, '-'), ',' order by pc.id)) into h_map2 from public.physical_card pc;
      execute 'reset role';
      res := res || jsonb_build_object('id','L.2','ok', v_ok and h_map2 = h_map and p.eligible_unlocated = 1 and p.total_count > 10000,
        'detail', format('D6: total %s com %s elegível → recusa pelo total, nada alterado: %s', p.total_count, p.eligible_unlocated, v_err));
    end if;

    raise exception 'MS849' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MS849' then
      res := res || jsonb_build_object('id','X.1','ok', false, 'detail','erro inesperado: '||sqlstate||' '||sqlerrm);
    end if;
  end;

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  res := res || jsonb_build_object('id','99.1','ok',
    (select count(*) from auth.users) = b_us
      and (select count(*) from public.storage_container) = b_sc
      and (select count(*) from public.collection) = b_co
      and (select count(*) from public.collection_allocation) = b_ca
      and (select count(*) from public.physical_card) = b_pc
      and (select count(*) from public.collection_reference) = b_cr
      and (select count(*) from public.collection_creation_request) = b_ccr
      and current_user = session_user,
    'detail','resíduo zero (usuários, locais, coleções, referências, pedidos de criação, alocações, exemplares) e papel restaurado');
  end if;

  for r in select * from jsonb_array_elements(res) loop
    cnt := cnt + 1;
    if coalesce((r->>'ok')::boolean, false) then passes := passes + 1; end if;
    seq := cnt; check_id := r->>'id';
    status := case when coalesce((r->>'ok')::boolean, false) then 'PASS' else 'FAIL' end;
    detail := r->>'detail';
    return next;
  end loop;
  seq := 999; check_id := 'GATE';
  status := case
    when passes <> cnt then 'FAIL'
    when (select count(*) from jsonb_array_elements(res) e where e->>'id' not like 'L.%') <> v_expected then 'FAIL'
    when p_big and (select count(*) from jsonb_array_elements(res) e where e->>'id' like 'L.%') <> 2 then 'FAIL'
    when not p_big then 'PASS_FUNCTIONAL_LIMIT_NOT_EXERCISED'
    else 'PASS' end;
  detail := format('%s/%s PASS (funcional esperado %s%s); desempenho NÃO MEDIDO', passes, cnt, v_expected,
    case when p_big then ' + L.1/L.2' else '' end);
  return next;
end;
$fn$;

select * from pg_temp.wh_5849_validate(false);
