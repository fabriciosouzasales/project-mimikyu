/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5850 - Harness P2-A1 (5223/5224/5225/5226): Fichário Digital —
              estrutura, segurança, elegibilidade, montagem automática por
              tipo de coleção, exemplares adicionais, sete modelos, plano
              mudado, atomicidade, desmontagem, M3, desempenho e resíduo zero
Versão......: 1.2 (2026-10-23, P2-A1-PROPOSAL-FINAL-CONSOLIDATION-01: 0.9/0.10 e
              Seção 14 provam a 5228 — sete modelos na alteração de grade — e a
              ausência de caminho alternativo autorizado de criação/grade;
              67 funcionais)
              1.1 (2026-10-23, P2-A1-PROPOSAL-AUDIT-CORRECTION-01: 0.8/1.7 provam
              o fechamento da 5123 pela 5227; Seção P aloca em lotes de 500
              — teto real da 5046 —, a v1.0 abortaria; função de falha da
              Seção 11 no schema public, desfeita pela sentinela e conferida
              no 99.1; precheck fail-loud da Pokédex antes do fixture;
              roteiro K1–K6 detalhado no README)
Status......: PROPOSTA — NÃO EXECUTADA. Nada aqui é PASS até ser executado
              com autorização expressa de Fabrício, DEPOIS de 5225 → 5223 →
              5224 → 5226 → 5227 → 5228 aplicadas no ambiente-alvo.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-22 (P2-A1-PROPOSAL-01)

Protocolo (o mesmo da 5847/5848/5849): um único statement; usuários
efêmeros A e B (o Inventory nasce pelo trigger de auth.users); catálogo
SINTÉTICO criado como dono do banco (expansão, Set, 4 cartas, variantes,
um Game e um acabamento extras para a prova de jogo da 5225); a sentinela
MS850 desfaz tudo; 99.1 prova resíduo zero.

  select * from pg_temp.wh_5850_validate(false);  -- funcional (padrão)
  select * from pg_temp.wh_5850_validate(true);   -- + Seções 11 e P

  p_isolated = true executa a Seção 11 (injeção de falha por trigger
  temporário — DDL dentro da transação) e a Seção P (carga sintética de
  500 / 2.000 / 10.000 / 10.001 alocações). NÃO executar com true no LIVE:
  só em ambiente isolado, quando autorizado. Sem elas o GATE é
  PASS_FUNCTIONAL_ISOLATED_NOT_EXERCISED — nunca PASS pleno, e o teto
  provisório (10.000 alocações / 20.000 bolsos) continua NÃO APROVADO.

Fixture (catálogo como dono; tudo do usuário pelas RPCs canônicas):
  Set sintético P2A1xxxx (base 3, total 4): K1 #1, K2 #2, K3 #3, K4 #4
  (secreta). Variantes: K1 STANDARD(1, padrão) + REVERSE_HOLO(2);
  K2 STANDARD(1) + HOLO(2) + REVERSE_HOLO(3); K3 STANDARD(1);
  K4 HOLO(1) — a secreta só tem HOLO.
  A — locais BIN (BINDER), BOX (sem tipo), BIN2 (BINDER).
      CSET  Set (padrão BIN): a K1-STD-pt, b K1-STD-pt (mais recente → cópia
            idêntica), c K1-STD-en (outro idioma), d K1-REV-pt (outra
            variante), e K3-STD-pt. K2/K4 sem exemplar → reservas.
      CMS   Master Set (padrão BIN; acabamentos STANDARD + REVERSE_HOLO):
            m1 K1-STD, m4 K1-REV, m3 K4-HOLO (secreta → posição só da carta),
            m2 K2-HOLO (fora do objetivo).
      CMS2  Master Set vazio (PLAN_CHANGED por acabamento/catálogo/modelo).
      CFREE Livre (local BIN): fz K3, fa K1, fb K2 — fz entrou antes;
            fa/fb no mesmo instante (desempate documentado).
      CDEX  Pokédex (geração da 1ª posição nacional, local BIN): x2/x3 na
            posição P1 (mesma variante e idioma → cópia idêntica), x1 em P3,
            x4 sem vínculo (fora do objetivo).
      CEMP  Livre vazia (local BIN).
      CNB   Livre com local BOX (não elegível).
      CPC   Set vazio (padrão BIN) — plano muda entre prévia e criação.
      CARB  Livre (local BIN2) — fichário criado; local vira BOX; coleção
            arquivada; desmontada.
  B — local LB (BINDER); coleção CB com fichário.

Seções:
  0   estrutura, privilégios, helpers internos, 5225, 5039 v1.4, 5227
      (create_collection_layout sem EXECUTE para authenticated), 5228
      (set_collection_layout_grid só nos sete modelos) e nenhum outro
      caminho executável por authenticated que crie layout ou mude a grade
  F   fixture (catálogo sintético e do usuário)
  1   segurança: anon 42501, sem identidade 28000, alheia/inexistente
      P0002 (não enumera), helpers inacessíveis, RLS de leitura direta,
      caminho direto 5123 fechado (1.7)
  2   elegibilidade e argumentos: grade, opção, token malformado,
      NOT_ELIGIBLE (D1), prévia sem escrita e determinística, D1 após a
      criação, arquivada
  3   Set: contagens, criação, posições/reservas/principal lidos pela 5223,
      cabeçalho, ALREADY_EXISTS
  4   adicionais: categorias sem dupla contagem, páginas próprias, nada
      intercalado, nenhuma reserva para adicional
  5   Master Set: ordem dos acabamentos (display_order), secreta só carta,
      fora do objetivo sem bolso, MATCH × MISMATCH por granularidade
  6   Livre: ordem de entrada + desempate
  7   Pokédex: ordem nacional, sem reservas, cópia idêntica, fora do objetivo
  8   coleção vazia
  9   sete modelos, mapeamento 3×4 (3 colunas × 4 linhas) × 4×3, pares
      fora da lista recusados
  10  PLAN_CHANGED: alocação, desalocação (token volta a conferir),
      acabamentos, catálogo (C-190), modelo, opção — nada gravado
  11  (só p_isolated) falha injetada no meio da gravação → nada gravado
  12  desmontagem: prévia, token desatualizado, travas + mesclagem,
      sucesso atômico, repetição, coleção arquivada, delete_collection
      recusado com fichário e liberado depois, token malformado
  13  M3 (5225): carta + acabamento; exclusividade; outro jogo; CHECK
  14  alteração de grade (5228): sete modelos aceitos com zero páginas,
      fora da lista recusada sem gravar, bloqueio com páginas preservado,
      outro usuário e coleção arquivada recusados, layout preexistente fora
      dos sete (7×7) intacto
  P   (só p_isolated) desempenho 500 / 2.000 / 10.000 (2×2) e 10.001 → teto
  99.1 resíduo zero e papel restaurado

GATE: funcional n = 67, todas PASS. Sem p_isolated:
      PASS_FUNCTIONAL_ISOLATED_NOT_EXERCISED. Com p_isolated: PASS exige
      também 11.1 e P.1–P.4. Os tempos da Seção P são MEDIDOS e reportados;
      aprovar o teto é decisão de Fabrício, não do harness.

Limitações declaradas:
  L1 SET LOCAL ROLE prova o banco, não o JWT do PostgREST.
  L2 Um único statement não tem duas sessões: travas, espera, lock_timeout
     e deadlock NÃO são exercitados aqui. A concorrência LÓGICA (estado
     mudou entre prévia e confirmação) é provada sequencialmente (Seções 10
     e 12). As provas de DUAS SESSÕES são o roteiro manual K1–K6 do README
     desta pasta e estão identificadas como tal.
  L3 Toda a transação usa o mesmo now(): collection_allocation.created_at
     é igual para todos. A ordem de entrada da Coleção Livre é simulada
     ajustando created_at como dono (Seção F) — prova a regra, não o relógio.
  L4 Dois exemplares do MESMO acabamento com variant_order diferente exigem
     um perfil de impressão (uq_card_variant_card_type_printing); o
     desempate por variant_order dentro do acabamento é provado por
     inspeção do plano (5224), não por fixture.
  L5 Catálogo sintético é criado e desfeito como dono do banco: a prova de
     C-190 (10.4) desativa uma carta SINTÉTICA, nunca do catálogo real.
================================================================
*/

create or replace function pg_temp.wh_5850_validate(p_isolated boolean default false)
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  f_get   oid := to_regprocedure('public.get_my_collection_binder(uuid)');
  f_pages oid := to_regprocedure('public.get_my_collection_binder_pages(uuid, integer, integer)');
  f_plan  oid := to_regprocedure('public.collection_binder_plan(uuid, integer, integer, text)');
  f_prev  oid := to_regprocedure('public.preview_my_collection_binder(uuid, integer, integer, text)');
  f_crt   oid := to_regprocedure('public.create_my_collection_binder(uuid, integer, integer, text, text)');
  f_snap  oid := to_regprocedure('public.collection_binder_dismantle_snapshot(uuid)');
  f_dprev oid := to_regprocedure('public.preview_my_collection_binder_dismantle(uuid)');
  f_dism  oid := to_regprocedure('public.dismantle_my_collection_binder(uuid, text)');
  f_sec   oid := to_regprocedure('public.set_slot_expected_content(uuid, uuid, uuid, uuid)');
  f_trg   oid := to_regprocedure('public.enforce_expected_content_variant_type_game()');
  f_del   oid := to_regprocedure('public.delete_collection(uuid)');
  f_lay   oid := to_regprocedure('public.create_collection_layout(uuid, integer, integer)');
  f_grid  oid := to_regprocedure('public.set_collection_layout_grid(uuid, integer, integer)');
  u_a uuid := gen_random_uuid();
  u_b uuid := gen_random_uuid();
  v_sfx text := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  v_game uuid; v_pt uuid; v_en uuid; v_rar uuid; v_cat uuid;
  v_std uuid; v_holo uuid; v_rev uuid;
  v_game2 uuid; v_vt_other uuid;
  v_exp uuid; v_set uuid;
  k1 uuid; k2 uuid; k3 uuid; k4 uuid;
  k1s uuid; k1r uuid; k2s uuid; k2h uuid; k2r uuid; k3s uuid; k4h uuid;
  v_inv_a uuid; v_inv_b uuid;
  v_ids uuid[];
  a uuid; b uuid; c uuid; d uuid; e uuid; m1 uuid; m2 uuid; m3 uuid; m4 uuid;
  fz uuid; fa uuid; fb uuid; x1 uuid; x2 uuid; x3 uuid; x4 uuid; pk2 uuid; bb1 uuid;
  v_bin uuid; v_box uuid; v_bin2 uuid; v_lb uuid;
  v_cset uuid; v_cms uuid; v_cms2 uuid; v_cfree uuid; v_cdex uuid; v_cemp uuid;
  v_cnb uuid; v_cpc uuid; v_carb uuid; v_cb uuid; v_cperf uuid;
  v_gen_code text; p1 uuid; p3 uuid;
  v_first uuid;
  v_slot1 uuid; v_slot2 uuid; v_page uuid; v_off integer;
  v_cgrid uuid; v_cleg uuid; v_lay_g uuid; v_lay_l uuid; v_upd timestamptz;
  p record; p2 record; o record; s record;
  v_ok boolean; v_err text; v_tok text; v_tok2 text; v_hint text;
  h1 text; h2 text;
  n integer; n2 integer; v_size integer;
  v_t0 timestamptz; v_ms numeric;
  b_us bigint; b_sc bigint; b_co bigint; b_ca bigint; b_pc bigint; b_cr bigint;
  b_l bigint; b_lp bigint; b_ls bigint; b_le bigint; b_la bigint; b_lr bigint;
  b_card bigint; b_cv bigint; b_cs bigint; b_ex bigint; b_g bigint; b_vt bigint;
  res jsonb := '[]'::jsonb; r jsonb; cnt integer := 0; passes integer := 0;
  v_expected integer := 67;
begin
  -- 0. Estrutura ---------------------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    f_get is not null and f_pages is not null and f_plan is not null and f_prev is not null
    and f_crt is not null and f_snap is not null and f_dprev is not null and f_dism is not null
    and f_sec is not null and f_trg is not null and f_del is not null and f_lay is not null and f_grid is not null,
    'detail','5223 (2), 5224 (3), 5225 (2), 5226 (3), delete_collection e create_collection_layout presentes');

  if not (f_get is not null and f_pages is not null and f_plan is not null and f_prev is not null
          and f_crt is not null and f_snap is not null and f_dprev is not null and f_dism is not null
          and f_sec is not null and f_trg is not null and f_del is not null and f_lay is not null and f_grid is not null) then
    res := res || jsonb_build_object('id','X.0','ok', false, 'detail','aplique 5225 → 5223 → 5224 → 5226 → 5227 → 5228 antes deste harness');
  else
  res := res || jsonb_build_object('id','0.2','ok',
    (select bool_and(q.prosecdef and q.proconfig @> array['search_path=""'])
     from pg_proc q where q.oid in (f_get, f_pages, f_prev, f_crt, f_dprev, f_dism, f_sec, f_del))
    and (select bool_and(q.provolatile = 's') from pg_proc q where q.oid in (f_get, f_pages, f_dprev))
    and (select bool_and(q.provolatile = 'v') from pg_proc q where q.oid in (f_prev, f_crt, f_dism)),
    'detail','RPCs públicas: SECURITY DEFINER, search_path vazio; leituras STABLE; prévia, criação e desmontagem VOLATILE');
  res := res || jsonb_build_object('id','0.3','ok',
    (select bool_and(not q.prosecdef and q.proconfig @> array['search_path=""']) from pg_proc q where q.oid in (f_plan, f_snap))
    and not has_function_privilege('anon', f_plan, 'EXECUTE') and not has_function_privilege('authenticated', f_plan, 'EXECUTE')
    and not has_function_privilege('service_role', f_plan, 'EXECUTE')
    and not has_function_privilege('anon', f_snap, 'EXECUTE') and not has_function_privilege('authenticated', f_snap, 'EXECUTE')
    and not has_function_privilege('service_role', f_snap, 'EXECUTE')
    and not has_function_privilege('authenticated', f_trg, 'EXECUTE') and not has_function_privilege('anon', f_trg, 'EXECUTE')
    and not exists (select 1 from pg_proc q, aclexplode(q.proacl) x where q.oid in (f_plan, f_snap, f_trg) and x.grantee = 0),
    'detail','helpers internos (plano, retrato) SECURITY INVOKER; nenhum papel de API executa helpers nem a função de trigger da 5225');
  res := res || jsonb_build_object('id','0.4','ok',
    (select bool_and(has_function_privilege('authenticated', q.oid, 'EXECUTE')
                     and not has_function_privilege('anon', q.oid, 'EXECUTE'))
     from pg_proc q where q.oid in (f_get, f_pages, f_prev, f_crt, f_dprev, f_dism, f_sec, f_del))
    and not exists (select 1 from pg_proc q, aclexplode(q.proacl) x
                    where q.oid in (f_get, f_pages, f_prev, f_crt, f_dprev, f_dism, f_sec, f_del) and x.grantee = 0),
    'detail','RPCs públicas: EXECUTE só authenticated; anon e PUBLIC sem acesso');
  res := res || jsonb_build_object('id','0.5','ok',
    (select bool_and(q.proconfig @> array['lock_timeout=5s']) from pg_proc q where q.oid in (f_crt, f_dism))
    and lower(pg_get_functiondef(f_crt)) like '%for update%' and lower(pg_get_functiondef(f_dism)) like '%for update%',
    'detail','criação e desmontagem: lock_timeout 5s e trava FOR UPDATE da coleção');
  res := res || jsonb_build_object('id','0.6','ok',
    exists (select 1 from information_schema.columns where table_schema = 'public'
            and table_name = 'collection_layout_slot_expected_content' and column_name = 'expected_variant_type_id')
    and exists (select 1 from pg_constraint where conname = 'chk_expected_content_variant_xor_type'
                and conrelid = 'public.collection_layout_slot_expected_content'::regclass)
    and exists (select 1 from pg_constraint where conname = 'fk_expected_content_variant_type'
                and conrelid = 'public.collection_layout_slot_expected_content'::regclass)
    and exists (select 1 from pg_trigger where tgname = 'trg_expected_content_variant_type_game' and not tgisinternal)
    and to_regprocedure('public.set_slot_expected_content(uuid, uuid, uuid)') is null,
    'detail','5225: coluna, FK, CHECK de exclusividade, trigger de jogo; assinatura antiga de 3 argumentos removida');
  res := res || jsonb_build_object('id','0.7','ok',
    (select q.prosrc like '%digital binder%' and q.prosrc like '%deallocate them before deleting%' from pg_proc q where q.oid = f_del)
    and pg_get_function_result(f_del) = 'TABLE(id uuid)',
    'detail','delete_collection (5039 v1.4): mesma assinatura e retorno; recusa com fichário; regra de alocações preservada');
  res := res || jsonb_build_object('id','0.8','ok',
    not has_function_privilege('authenticated', f_lay, 'EXECUTE')
    and not has_function_privilege('anon', f_lay, 'EXECUTE')
    and not exists (select 1 from pg_proc q, aclexplode(q.proacl) x where q.oid = f_lay and x.grantee = 0),
    'detail','5227: create_collection_layout (5123) sem EXECUTE para authenticated/anon/PUBLIC — único caminho de criação é a 5224');
  res := res || jsonb_build_object('id','0.9','ok',
    (select q.prosecdef and q.proconfig @> array['search_path=""'] and q.prosrc like '%INVALID_GRID%'
            and q.prosrc like '%(5,4)%' and q.prosrc like '%WHERE l.id = p_layout_id%'
     from pg_proc q where q.oid = f_grid)
    and pg_get_function_result(f_grid) = 'TABLE(id uuid, collection_id uuid, grid_rows integer, grid_columns integer)'
    and has_function_privilege('authenticated', f_grid, 'EXECUTE')
    and not has_function_privilege('anon', f_grid, 'EXECUTE')
    and not exists (select 1 from pg_proc q, aclexplode(q.proacl) x where q.oid = f_grid and x.grantee = 0),
    'detail','5228: set_collection_layout_grid com mesma assinatura/retorno, SECURITY DEFINER, search_path vazio, regra dos sete modelos; EXECUTE só authenticated');
  res := res || jsonb_build_object('id','0.10','ok',
    (select coalesce(array_agg(q.proname::text order by q.proname), '{}')
     from pg_proc q join pg_namespace ns on ns.oid = q.pronamespace
     where ns.nspname = 'public'
       and q.prosrc ~* 'insert\s+into\s+public\.collection_layout\s*(as\s+\w+\s*)?\('
       and has_function_privilege('authenticated', q.oid, 'EXECUTE')) = array['create_my_collection_binder']
    and not exists (select 1 from pg_proc q join pg_namespace ns on ns.oid = q.pronamespace
                    where ns.nspname = 'public'
                      and q.prosrc ~* 'update\s+public\.collection_layout(\s+as\s+\w+)?\s+set'
                      and has_function_privilege('authenticated', q.oid, 'EXECUTE')
                      and q.prosrc not like '%INVALID_GRID%'),
    'detail','sem caminho alternativo: a única função executável por authenticated que insere em collection_layout é a 5224; toda função executável que altera a grade valida os sete modelos');

  select count(*) into b_us from auth.users;
  select count(*) into b_sc from public.storage_container;
  select count(*) into b_co from public.collection;
  select count(*) into b_ca from public.collection_allocation;
  select count(*) into b_pc from public.physical_card;
  select count(*) into b_cr from public.collection_reference;
  select count(*) into b_l  from public.collection_layout;
  select count(*) into b_lp from public.collection_layout_page;
  select count(*) into b_ls from public.collection_layout_slot;
  select count(*) into b_le from public.collection_layout_slot_expected_content;
  select count(*) into b_la from public.collection_layout_slot_assignment;
  select count(*) into b_lr from public.collection_layout_region;
  select count(*) into b_card from public.card;
  select count(*) into b_cv from public.card_variant;
  select count(*) into b_cs from public.card_set;
  select count(*) into b_ex from public.expansion;
  select count(*) into b_g  from public.game;
  select count(*) into b_vt from public.card_variant_type;

  begin
    -- F. Catálogo sintético (dono do banco) -----------------------------------------
    select g.id into v_game from public.game g where g.code = 'POKEMON';
    select l.id into v_pt from public.language l where l.code = 'pt-BR';
    select l.id into v_en from public.language l where l.code = 'en';
    select t.id into v_std  from public.card_variant_type t where t.game_id = v_game and t.code = 'STANDARD';
    select t.id into v_holo from public.card_variant_type t where t.game_id = v_game and t.code = 'HOLO';
    select t.id into v_rev  from public.card_variant_type t where t.game_id = v_game and t.code = 'REVERSE_HOLO';
    select c0.rarity_id, c0.category_id into v_rar, v_cat
    from public.card c0
    join public.card_set cs0 on cs0.id = c0.card_set_id
    join public.expansion e0 on e0.id = cs0.expansion_id
    join public.card_category cc0 on cc0.id = c0.category_id
    where e0.game_id = v_game and cc0.code = 'POKEMON'
    limit 1;
    v_ok := v_game is not null and v_pt is not null and v_en is not null and v_std is not null
            and v_holo is not null and v_rev is not null and v_rar is not null and v_cat is not null;
    if not v_ok then
      res := res || jsonb_build_object('id','F.1','ok', false,
        'detail','pré-requisitos de catálogo ausentes (POKEMON, pt-BR, en, STANDARD/HOLO/REVERSE_HOLO, raridade/categoria POKEMON)');
      raise exception 'MS850' using errcode = 'P0001';
    end if;

    begin
      insert into public.expansion (game_id, code, name, release_order)
      values (v_game, 'P2A1_' || v_sfx, 'P2A1 Harness ' || v_sfx,
              (select coalesce(max(x.release_order), 0) + 1000 from public.expansion x where x.game_id = v_game))
      returning id into v_exp;
      insert into public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
      values (v_exp, 'P2A1' || v_sfx, 'P2A1 Set ' || v_sfx, 'REGULAR', 1, 3, 4)
      returning id into v_set;
      insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
      values (v_set, v_rar, v_cat, '1', 1, 'P2A1 K1', true) returning id into k1;
      insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
      values (v_set, v_rar, v_cat, '2', 2, 'P2A1 K2', true) returning id into k2;
      insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
      values (v_set, v_rar, v_cat, '3', 3, 'P2A1 K3', true) returning id into k3;
      insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
      values (v_set, v_rar, v_cat, '4', 4, 'P2A1 K4', true) returning id into k4;
      insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k1, v_std, 1, true)   returning id into k1s;
      insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k1, v_rev, 2, false)  returning id into k1r;
      insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k2, v_std, 1, true)   returning id into k2s;
      insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k2, v_holo, 2, false) returning id into k2h;
      insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k2, v_rev, 3, false)  returning id into k2r;
      insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k3, v_std, 1, true)   returning id into k3s;
      insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k4, v_holo, 1, true)  returning id into k4h;
      insert into public.game (code, name) values ('P2A1G' || v_sfx, 'P2A1 Game ' || v_sfx) returning id into v_game2;
      insert into public.card_variant_type (game_id, code, name, display_order)
      values (v_game2, 'P2A1_STD', 'P2A1 Standard', 1) returning id into v_vt_other;
      res := res || jsonb_build_object('id','F.1','ok', true,
        'detail','catálogo sintético: Set (base 3, total 4), 4 cartas, 7 variantes; Game e acabamento extras');
    exception when others then
      res := res || jsonb_build_object('id','F.1','ok', false, 'detail','catálogo sintético falhou: '||sqlstate||' '||sqlerrm);
      raise exception 'MS850' using errcode = 'P0001';
    end;

    -- Usuários efêmeros e exemplares (dono) --------------------------------------------
    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    values (u_a, 'authenticated', 'authenticated', 'wh5850-a-'||lower(v_sfx)||'@example.invalid',
            jsonb_build_object('username', 'wh5850a_'||lower(v_sfx), 'display_name', 'WH 5850 A'), now(), now()),
           (u_b, 'authenticated', 'authenticated', 'wh5850-b-'||lower(v_sfx)||'@example.invalid',
            jsonb_build_object('username', 'wh5850b_'||lower(v_sfx), 'display_name', 'WH 5850 B'), now(), now());
    select i.id into v_inv_a from public.inventory i where i.owner_user_id = u_a;
    select i.id into v_inv_b from public.inventory i where i.owner_user_id = u_b;

    insert into public.physical_card (card_variant_id, language_id, inventory_id, created_at) values
      (k1s, v_pt, v_inv_a, now() - interval '30 min'),   -- a
      (k1s, v_pt, v_inv_a, now() - interval '29 min'),   -- b (mais recente que a)
      (k1s, v_en, v_inv_a, now() - interval '28 min'),   -- c
      (k1r, v_pt, v_inv_a, now() - interval '27 min'),   -- d
      (k3s, v_pt, v_inv_a, now() - interval '26 min'),   -- e
      (k1s, v_pt, v_inv_a, now() - interval '25 min'),   -- m1
      (k2h, v_pt, v_inv_a, now() - interval '24 min'),   -- m2
      (k4h, v_pt, v_inv_a, now() - interval '23 min'),   -- m3
      (k1r, v_pt, v_inv_a, now() - interval '22 min'),   -- m4
      (k3s, v_pt, v_inv_a, now() - interval '21 min'),   -- fz
      (k1s, v_pt, v_inv_a, now() - interval '20 min'),   -- fa
      (k2s, v_pt, v_inv_a, now() - interval '19 min'),   -- fb
      (k1s, v_pt, v_inv_a, now() - interval '18 min'),   -- x1
      (k2s, v_pt, v_inv_a, now() - interval '17 min'),   -- x2
      (k2s, v_pt, v_inv_a, now() - interval '16 min'),   -- x3
      (k3s, v_pt, v_inv_a, now() - interval '15 min'),   -- x4
      (k2s, v_pt, v_inv_a, now() - interval '14 min');   -- pk2 (entra no CPC entre prévia e criação)
    select array_agg(pc.id order by pc.created_at) into v_ids from public.physical_card pc where pc.inventory_id = v_inv_a;
    a := v_ids[1]; b := v_ids[2]; c := v_ids[3]; d := v_ids[4]; e := v_ids[5];
    m1 := v_ids[6]; m2 := v_ids[7]; m3 := v_ids[8]; m4 := v_ids[9];
    fz := v_ids[10]; fa := v_ids[11]; fb := v_ids[12];
    x1 := v_ids[13]; x2 := v_ids[14]; x3 := v_ids[15]; x4 := v_ids[16]; pk2 := v_ids[17];
    insert into public.physical_card (card_variant_id, language_id, inventory_id, created_at)
    values (k1s, v_pt, v_inv_b, now()) returning id into bb1;

    -- Principal esperado de K1 no Set: STANDARD antes de REVERSE; entre a (pt) e c
    -- (en), o menor language_order; mesmo idioma → o exemplar mais antigo (a).
    select case when (select l.language_order from public.language l where l.id = v_pt)
                  <= (select l.language_order from public.language l where l.id = v_en) then a else c end
      into v_first;

    -- Pokédex: geração da 1ª posição nacional; P1/P3 = 1ª e 3ª posições dela.
    select g.code, array_agg(pp.id order by pp.position_number)
      into v_gen_code, v_ids
    from public.pokedex dx
    join public.pokedex_position pp on pp.pokedex_id = dx.id
    join public.pokemon_species sp on sp.id = pp.species_id
    join public.pokemon_generation g on g.id = sp.generation_id
    where dx.code = 'NATIONAL'
      and g.id = (select sp2.generation_id from public.pokedex_position pp2
                  join public.pokemon_species sp2 on sp2.id = pp2.species_id
                  where pp2.pokedex_id = dx.id order by pp2.position_number limit 1)
    group by g.code;
    p1 := v_ids[1]; p3 := v_ids[3];
    if v_gen_code is null or p1 is null or p3 is null then
      res := res || jsonb_build_object('id','X.2','ok', false,
        'detail','pré-requisito ausente: Pokédex NATIONAL com ≥ 3 posições na geração da 1ª posição');
      raise exception 'MS850' using errcode = 'P0001';
    end if;

    -- B -----------------------------------------------------------------------------
    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select x.storage_container_id into v_lb from public.create_my_storage_container(gen_random_uuid(), 'LB 5850', 'BINDER') x;
    select x.collection_id into v_cb from public.create_my_free_collection(gen_random_uuid(), 'CB 5850', v_lb) x;
    perform public.allocate_physical_cards_to_collection(v_cb, array[bb1]);
    select * into p from public.preview_my_collection_binder(v_cb, 3, 3, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_cb, 3, 3, 'PRINCIPAL_ONLY', p.plan_token);

    -- A -----------------------------------------------------------------------------
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select x.storage_container_id into v_bin  from public.create_my_storage_container(gen_random_uuid(), 'BIN 5850', 'BINDER') x;
    select x.storage_container_id into v_box  from public.create_my_storage_container(gen_random_uuid(), 'BOX 5850', null) x;
    select x.storage_container_id into v_bin2 from public.create_my_storage_container(gen_random_uuid(), 'BIN2 5850', 'BINDER') x;
    select x.id into v_cset from public.create_reference_based_card_set_collection(v_game, 'CSET 5850', null, v_bin, v_set) x;
    select x.id into v_cms  from public.create_reference_based_card_set_collection(v_game, 'CMS 5850', null, v_bin, v_set) x;
    select x.id into v_cms2 from public.create_reference_based_card_set_collection(v_game, 'CMS2 5850', null, v_bin, v_set) x;
    select x.id into v_cpc  from public.create_reference_based_card_set_collection(v_game, 'CPC 5850', null, v_bin, v_set) x;
    perform count(*) from public.set_collection_completion_policy_to_master_set(p_collection_id => v_cms,  p_variant_type_ids => array[v_std, v_rev]);
    perform count(*) from public.set_collection_completion_policy_to_master_set(p_collection_id => v_cms2, p_variant_type_ids => array[v_std, v_rev]);
    select x.collection_id into v_cfree from public.create_my_free_collection(gen_random_uuid(), 'CFREE 5850', v_bin) x;
    select x.collection_id into v_cemp  from public.create_my_free_collection(gen_random_uuid(), 'CEMP 5850', v_bin) x;
    select x.collection_id into v_cnb   from public.create_my_free_collection(gen_random_uuid(), 'CNB 5850', v_box) x;
    select x.collection_id into v_carb  from public.create_my_free_collection(gen_random_uuid(), 'CARB 5850', v_bin2) x;
    select x.collection_id into v_cdex  from public.create_my_pokedex_collection(gen_random_uuid(), 'CDEX 5850', array[v_gen_code], v_bin) x;
    perform public.allocate_physical_cards_to_collection(v_cset, array[a, b, c, d, e]);
    perform public.allocate_physical_cards_to_collection(v_cms,  array[m1, m2, m3, m4]);
    perform public.allocate_physical_cards_to_collection(v_cfree, array[fz, fa, fb]);
    perform count(*) from public.link_my_pokedex_copy(v_cdex, p3, x1, true);
    perform count(*) from public.link_my_pokedex_copy(v_cdex, p1, x2, true);
    perform count(*) from public.link_my_pokedex_copy(v_cdex, p1, x3, true);
    perform public.allocate_physical_cards_to_collection(v_cdex, array[x4]);
    execute 'reset role';
    -- L3: ordem de entrada da Livre simulada (mesmo now() em toda a transação).
    update public.collection_allocation ca set created_at = now() - interval '1 hour'
    where ca.collection_id = v_cfree and ca.physical_card_id = fz;
    res := res || jsonb_build_object('id','F.2','ok',
      (select count(*) from public.collection_allocation ca where ca.collection_id in (v_cset, v_cms, v_cfree, v_cdex)) = 16
      and (select count(*) from public.collection_pokedex_position_assignment pa
           join public.collection_allocation ca on ca.id = pa.collection_allocation_id where ca.collection_id = v_cdex) = 3
      and (select count(*) from public.collection_layout l where l.collection_id = v_cb) = 1
      and p1 is not null and p3 is not null,
      'detail','fixture do usuário: 16 alocações em 4 coleções de A, 3 vínculos de Pokédex, fichário de B criado');

    -- 1. Segurança --------------------------------------------------------------------
    execute 'set local role anon';
    v_ok := true; v_err := '';
    begin perform count(*) from public.preview_my_collection_binder(v_cset, 3, 3, 'PRINCIPAL_ONLY'); v_ok := false;
    exception when others then v_ok := v_ok and sqlstate = '42501'; v_err := v_err || sqlstate || ' '; end;
    begin perform count(*) from public.create_my_collection_binder(v_cset, 3, 3, 'PRINCIPAL_ONLY', 'v1:' || repeat('0', 64)); v_ok := false;
    exception when others then v_ok := v_ok and sqlstate = '42501'; v_err := v_err || sqlstate || ' '; end;
    begin perform count(*) from public.get_my_collection_binder(v_cset); v_ok := false;
    exception when others then v_ok := v_ok and sqlstate = '42501'; v_err := v_err || sqlstate || ' '; end;
    begin perform count(*) from public.dismantle_my_collection_binder(v_cset, 'd1:' || repeat('0', 64)); v_ok := false;
    exception when others then v_ok := v_ok and sqlstate = '42501'; v_err := v_err || sqlstate || ' '; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.1','ok', v_ok, 'detail','anon: prévia, criação, leitura e desmontagem → 42501: ' || v_err);

    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role authenticated';
    begin perform count(*) from public.preview_my_collection_binder(v_cset, 3, 3, 'PRINCIPAL_ONLY'); v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlstate = '28000'; v_err := sqlstate || ' ' || sqlerrm; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.2','ok', v_ok, 'detail','authenticated sem identidade → 28000: ' || v_err);

    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    v_ok := true; v_err := '';
    begin perform count(*) from public.get_my_collection_binder(v_cb); v_ok := false;
    exception when others then v_ok := v_ok and sqlstate = 'P0002' and sqlerrm = 'COLLECTION_NOT_FOUND'; v_err := v_err || sqlstate || ' '; end;
    begin perform count(*) from public.get_my_collection_binder_pages(v_cb, 1, 1); v_ok := false;
    exception when others then v_ok := v_ok and sqlstate = 'P0002' and sqlerrm = 'COLLECTION_NOT_FOUND'; v_err := v_err || sqlstate || ' '; end;
    begin perform count(*) from public.preview_my_collection_binder(v_cb, 3, 3, 'PRINCIPAL_ONLY'); v_ok := false;
    exception when others then v_ok := v_ok and sqlstate = 'P0002' and sqlerrm = 'COLLECTION_NOT_FOUND'; v_err := v_err || sqlstate || ' '; end;
    begin perform count(*) from public.create_my_collection_binder(v_cb, 3, 3, 'PRINCIPAL_ONLY', 'v1:' || repeat('0', 64)); v_ok := false;
    exception when others then v_ok := v_ok and sqlstate = 'P0002' and sqlerrm = 'COLLECTION_NOT_FOUND'; v_err := v_err || sqlstate || ' '; end;
    begin perform count(*) from public.preview_my_collection_binder_dismantle(v_cb); v_ok := false;
    exception when others then v_ok := v_ok and sqlstate = 'P0002' and sqlerrm = 'COLLECTION_NOT_FOUND'; v_err := v_err || sqlstate || ' '; end;
    begin perform count(*) from public.dismantle_my_collection_binder(v_cb, 'd1:' || repeat('0', 64)); v_ok := false;
    exception when others then v_ok := v_ok and sqlstate = 'P0002' and sqlerrm = 'COLLECTION_NOT_FOUND'; v_err := v_err || sqlstate || ' '; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.3','ok', v_ok and (select count(*) from public.collection_layout l where l.collection_id = v_cb) = 1,
      'detail','A sobre a coleção de B (leitura, páginas, prévia, criação, prévia/desmontagem) → P0002 COLLECTION_NOT_FOUND; fichário de B intacto: ' || v_err);
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';

    v_ok := true; v_err := '';
    begin perform count(*) from public.get_my_collection_binder(gen_random_uuid()); v_ok := false;
    exception when others then v_ok := v_ok and sqlstate = 'P0002' and sqlerrm = 'COLLECTION_NOT_FOUND'; v_err := v_err || sqlstate || ' '; end;
    begin perform count(*) from public.preview_my_collection_binder(gen_random_uuid(), 3, 3, 'PRINCIPAL_ONLY'); v_ok := false;
    exception when others then v_ok := v_ok and sqlstate = 'P0002' and sqlerrm = 'COLLECTION_NOT_FOUND'; v_err := v_err || sqlstate || ' '; end;
    res := res || jsonb_build_object('id','1.4','ok', v_ok, 'detail','coleção inexistente → mesma resposta da alheia (não enumera): ' || v_err);

    begin perform count(*) from public.collection_binder_plan(v_cset, 3, 3, 'PRINCIPAL_ONLY'); v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlstate = '42501'; v_err := sqlstate || ' ' || sqlerrm; end;
    begin perform count(*) from public.collection_binder_dismantle_snapshot(v_cb); v_ok := false; v_err := v_err || ' / executou';
    exception when others then v_ok := v_ok and sqlstate = '42501'; v_err := v_err || ' / ' || sqlstate; end;
    res := res || jsonb_build_object('id','1.5','ok', v_ok, 'detail','authenticated chamando os helpers internos diretamente → 42501: ' || v_err);

    begin perform count(*) from public.create_collection_layout(v_cnb, 3, 3); v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlstate = '42501'; v_err := sqlstate || ' ' || sqlerrm; end;
    res := res || jsonb_build_object('id','1.7','ok', v_ok and (select g.has_binder from public.get_my_collection_binder(v_cnb) g) = false,
      'detail','D1 sem atalho: A chamando create_collection_layout direto (coleção sem local BINDER) → 42501, nenhum layout: ' || v_err);

    res := res || jsonb_build_object('id','1.6','ok',
      (select count(*) from public.collection_layout l where l.collection_id = v_cb) = 0
      and (select count(*) from public.collection_layout_slot_assignment) = 0,
      'detail','leitura direta como A (RLS select-own): layout e posições de B invisíveis');

    -- 2. Elegibilidade e argumentos -----------------------------------------------------
    v_ok := true; v_err := '';
    begin perform count(*) from public.preview_my_collection_binder(v_cset, 3, 5, 'PRINCIPAL_ONLY'); v_ok := false;
    exception when others then v_ok := v_ok and sqlstate = '22023' and sqlerrm = 'INVALID_GRID'; v_err := v_err || sqlerrm || ' '; end;
    begin perform count(*) from public.create_my_collection_binder(v_cset, 0, 0, 'PRINCIPAL_ONLY', 'v1:' || repeat('0', 64)); v_ok := false;
    exception when others then v_ok := v_ok and sqlstate = '22023' and sqlerrm = 'INVALID_GRID'; v_err := v_err || sqlerrm || ' '; end;
    res := res || jsonb_build_object('id','2.1','ok', v_ok, 'detail','grade fora dos sete modelos → 22023 INVALID_GRID: ' || v_err);

    v_ok := true; v_err := '';
    begin perform count(*) from public.preview_my_collection_binder(v_cset, 3, 3, 'INTERLEAVE'); v_ok := false;
    exception when others then v_ok := v_ok and sqlstate = '22023' and sqlerrm = 'INVALID_EXTRA_POLICY'; v_err := v_err || sqlerrm || ' '; end;
    begin perform count(*) from public.create_my_collection_binder(v_cset, 3, 3, null, 'v1:' || repeat('0', 64)); v_ok := false;
    exception when others then v_ok := v_ok and sqlstate = '22023' and sqlerrm = 'INVALID_EXTRA_POLICY'; v_err := v_err || sqlerrm || ' '; end;
    res := res || jsonb_build_object('id','2.2','ok', v_ok, 'detail','opção de adicionais inválida/nula → 22023 INVALID_EXTRA_POLICY: ' || v_err);

    v_ok := true; v_err := '';
    begin perform count(*) from public.create_my_collection_binder(v_cset, 3, 3, 'PRINCIPAL_ONLY', 'abc'); v_ok := false;
    exception when others then v_ok := v_ok and sqlstate = '22023' and sqlerrm = 'INVALID_PLAN_TOKEN'; v_err := v_err || sqlerrm || ' '; end;
    begin perform count(*) from public.create_my_collection_binder(v_cset, 3, 3, 'PRINCIPAL_ONLY', null); v_ok := false;
    exception when others then v_ok := v_ok and sqlstate = '22023' and sqlerrm = 'INVALID_PLAN_TOKEN'; v_err := v_err || sqlerrm || ' '; end;
    res := res || jsonb_build_object('id','2.3','ok', v_ok, 'detail','token malformado/nulo → 22023 INVALID_PLAN_TOKEN: ' || v_err);

    select * into p from public.preview_my_collection_binder(v_cnb, 3, 3, 'PRINCIPAL_ONLY');
    begin perform count(*) from public.create_my_collection_binder(v_cnb, 3, 3, 'PRINCIPAL_ONLY', p.plan_token); v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlstate = '55000' and sqlerrm = 'NOT_ELIGIBLE'; v_err := sqlstate || ' ' || sqlerrm; end;
    select * into p2 from public.get_my_collection_binder(v_cnb);
    res := res || jsonb_build_object('id','2.4','ok', v_ok and p.eligible = false and p.plan_token is not null
      and p2.can_create = false and p2.has_binder = false,
      'detail','D1: local padrão sem tipo BINDER → prévia eligible=false, can_create=false, criação 55000 NOT_ELIGIBLE, nada criado: ' || v_err);

    execute 'reset role';
    select count(*) into n from public.collection_layout;
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select * into p  from public.preview_my_collection_binder(v_cset, 3, 3, 'PRINCIPAL_ONLY');
    select * into p2 from public.preview_my_collection_binder(v_cset, 3, 3, 'PRINCIPAL_ONLY');
    execute 'reset role';
    select count(*) into n2 from public.collection_layout;
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    res := res || jsonb_build_object('id','2.5','ok', n = n2 and p.plan_token = p2.plan_token
      and p.plan_token ~ '^v1:[0-9a-f]{64}$' and p.eligible and p.lifecycle_active and not p.binder_exists,
      'detail','prévia não grava e é determinística (mesmo token em duas chamadas); formato v1:<sha256>');

    -- 3/4. Set -------------------------------------------------------------------------
    res := res || jsonb_build_object('id','3.1','ok',
      p.collection_kind = 'SET' and p.positions_total = 4 and p.positions_owned = 2 and p.positions_reserved = 2
      and p.extras_total = 3 and p.extras_identical = 1 and p.extras_other_language = 1 and p.extras_other_variant = 1
      and p.extras_out_of_objective = 0 and p.extras_placed = 0 and p.extras_unplaced = 3
      and p.has_identical_duplicates and p.pages_total = 1 and p.slots_total = 9 and p.slots_empty_trailing = 5,
      'detail', format('Set PRINCIPAL_ONLY: posições %s (atendidas %s, reservadas %s), adicionais %s = %s+%s+%s+%s, páginas %s, bolsos %s',
        p.positions_total, p.positions_owned, p.positions_reserved, p.extras_total, p.extras_identical,
        p.extras_other_language, p.extras_other_variant, p.extras_out_of_objective, p.pages_total, p.slots_total));

    select * into p2 from public.preview_my_collection_binder(v_cset, 3, 3, 'APPEND_PAGES');
    res := res || jsonb_build_object('id','4.1','ok',
      p2.extras_placed = 3 and p2.extras_unplaced = 0 and p2.pages_total = 2 and p2.slots_total = 18
      and p2.extras_total = p2.extras_identical + p2.extras_other_language + p2.extras_other_variant + p2.extras_out_of_objective
      and p2.plan_token <> p.plan_token,
      'detail','APPEND_PAGES: 3 adicionais em página própria (2 páginas); soma das categorias = total (sem dupla contagem); token difere do PRINCIPAL_ONLY (R5: opção no token)');

    select md5(string_agg(ca.id::text || ':' || ca.physical_card_id || ':' || ca.collection_id, ',' order by ca.id)) into h1
    from public.collection_allocation ca;
    select * into o from public.create_my_collection_binder(v_cset, 3, 3, 'APPEND_PAGES', p2.plan_token);
    select md5(string_agg(ca.id::text || ':' || ca.physical_card_id || ':' || ca.collection_id, ',' order by ca.id)) into h2
    from public.collection_allocation ca;
    res := res || jsonb_build_object('id','3.2','ok',
      o.outcome = 'CREATED' and o.pages_created = 2 and o.slots_created = 18 and o.reservations_created = 4
      and o.assignments_created = 5 and o.extras_unplaced = 0 and o.grid_columns = 3 and o.grid_rows = 3 and h1 = h2,
      'detail', format('criação APPEND_PAGES: %s, páginas %s, bolsos %s, reservas %s, posições %s; alocações intactas',
        o.outcome, o.pages_created, o.slots_created, o.reservations_created, o.assignments_created));

    select string_agg(g.slot_state || '@' || g.page_number || '.' || g.row_index || '.' || g.column_index, ' '
                      order by g.page_number, g.row_index, g.column_index)
      into v_err
    from public.get_my_collection_binder_pages(v_cset, 1, 2) g;
    res := res || jsonb_build_object('id','3.3','ok',
      exists (select 1 from public.get_my_collection_binder_pages(v_cset, 1, 1) g
              where g.row_index = 1 and g.column_index = 1 and g.slot_state = 'OCCUPIED_MATCH'
                and g.expected_card_id = k1 and g.physical_card_id = v_first)
      and exists (select 1 from public.get_my_collection_binder_pages(v_cset, 1, 1) g
                  where g.row_index = 1 and g.column_index = 2 and g.slot_state = 'RESERVED_EMPTY' and g.expected_card_id = k2)
      and exists (select 1 from public.get_my_collection_binder_pages(v_cset, 1, 1) g
                  where g.row_index = 1 and g.column_index = 3 and g.slot_state = 'OCCUPIED_MATCH' and g.physical_card_id = e)
      and exists (select 1 from public.get_my_collection_binder_pages(v_cset, 1, 1) g
                  where g.row_index = 2 and g.column_index = 1 and g.slot_state = 'RESERVED_EMPTY' and g.expected_card_id = k4)
      and (select count(*) from public.get_my_collection_binder_pages(v_cset, 1, 1) g where g.slot_state = 'EMPTY') = 5,
      'detail','página 1 lida pela 5223: K1 (principal) MATCH, K2 reserva, K3 MATCH, K4 (secreta) reserva, 5 vazios — ' || v_err);

    res := res || jsonb_build_object('id','4.2','ok',
      (select count(*) from public.get_my_collection_binder_pages(v_cset, 2, 1) g where g.slot_state = 'OCCUPIED_UNPLANNED') = 3
      and (select count(*) from public.get_my_collection_binder_pages(v_cset, 2, 1) g where g.expected_card_id is not null) = 0
      and (select count(*) from public.get_my_collection_binder_pages(v_cset, 1, 1) g where g.slot_state = 'OCCUPIED_UNPLANNED') = 0
      and exists (select 1 from public.get_my_collection_binder_pages(v_cset, 2, 1) g
                  where g.row_index = 1 and g.column_index = 3 and g.physical_card_id = d),
      'detail','adicionais só na página 2 (sem reserva, nunca intercalados no checklist); o de outra variante (REVERSE) por último');

    select * into s from public.get_my_collection_binder(v_cset);
    res := res || jsonb_build_object('id','3.4','ok',
      s.has_binder and s.is_editable and not s.can_create and s.page_count = 2 and s.slot_count = 18
      and s.filled_count = 5 and s.reserved_count = 4 and s.reserved_empty_count = 2
      and s.grid_columns = 3 and s.grid_rows = 3 and s.collection_kind = 'SET',
      'detail', format('cabeçalho 5223: páginas %s, bolsos %s, ocupados %s, reservas %s (vazias %s)',
        s.page_count, s.slot_count, s.filled_count, s.reserved_count, s.reserved_empty_count));

    select * into o from public.create_my_collection_binder(v_cset, 4, 4, 'PRINCIPAL_ONLY', p.plan_token);
    res := res || jsonb_build_object('id','3.5','ok',
      o.outcome = 'ALREADY_EXISTS' and o.grid_columns = 3 and o.grid_rows = 3 and o.slots_created = 0
      and (select g.page_count from public.get_my_collection_binder(v_cset) g) = 2,
      'detail','nova criação com fichário existente → ALREADY_EXISTS (modelo original devolvido), nada muda');

    -- 5. Master Set --------------------------------------------------------------------
    select * into p from public.preview_my_collection_binder(v_cms, 3, 3, 'PRINCIPAL_ONLY');
    res := res || jsonb_build_object('id','5.1','ok',
      p.collection_kind = 'MASTER_SET' and p.positions_total = 6 and p.positions_owned = 3 and p.positions_reserved = 3
      and p.extras_total = 1 and p.extras_out_of_objective = 1 and p.extras_unplaced = 1,
      'detail', format('Master (STANDARD+REVERSE): posições %s (atendidas %s), adicionais %s (fora do objetivo %s)',
        p.positions_total, p.positions_owned, p.extras_total, p.extras_out_of_objective));
    select * into o from public.create_my_collection_binder(v_cms, 3, 3, 'PRINCIPAL_ONLY', p.plan_token);
    select string_agg(coalesce(g.expected_variant_type_code, '*') || ':' || coalesce(g.expected_card_name, '-'), ','
                      order by g.row_index, g.column_index)
      into v_err
    from public.get_my_collection_binder_pages(v_cms, 1, 1) g where g.expected_card_id is not null;
    res := res || jsonb_build_object('id','5.2','ok',
      o.outcome = 'CREATED' and o.reservations_created = 6 and o.assignments_created = 3 and o.extras_unplaced = 1
      and v_err = 'STANDARD:P2A1 K1,REVERSE_HOLO:P2A1 K1,STANDARD:P2A1 K2,REVERSE_HOLO:P2A1 K2,STANDARD:P2A1 K3,*:P2A1 K4',
      'detail','ordem por carta e display_order do acabamento; secreta só com a carta: ' || coalesce(v_err, '∅'));
    res := res || jsonb_build_object('id','5.3','ok',
      exists (select 1 from public.get_my_collection_binder_pages(v_cms, 1, 1) g
              where g.row_index = 2 and g.column_index = 3 and g.physical_card_id = m3 and g.slot_state = 'OCCUPIED_MATCH'
                and g.expected_variant_type_id is null)
      and exists (select 1 from public.get_my_collection_binder_pages(v_cms, 1, 1) g
                  where g.row_index = 1 and g.column_index = 2 and g.physical_card_id = m4 and g.slot_state = 'OCCUPIED_MATCH')
      and not exists (select 1 from public.get_my_collection_binder_pages(v_cms, 1, 1) g where g.physical_card_id = m2),
      'detail','secreta K4 (HOLO) na posição só da carta = MATCH; REVERSE no bolso REVERSE; fora do objetivo (K2 HOLO) sem bolso');

    select g.slot_id into v_slot1 from public.get_my_collection_binder_pages(v_cms, 1, 1) g where g.row_index = 1 and g.column_index = 1;
    select g.slot_id into v_slot2 from public.get_my_collection_binder_pages(v_cms, 1, 1) g where g.row_index = 2 and g.column_index = 1;
    perform count(*) from public.move_slot_assignment(v_slot1, v_slot2);
    res := res || jsonb_build_object('id','5.4','ok',
      exists (select 1 from public.get_my_collection_binder_pages(v_cms, 1, 1) g
              where g.row_index = 2 and g.column_index = 1 and g.physical_card_id = m1 and g.slot_state = 'OCCUPIED_MISMATCH')
      and exists (select 1 from public.get_my_collection_binder_pages(v_cms, 1, 1) g
                  where g.row_index = 1 and g.column_index = 1 and g.slot_state = 'RESERVED_EMPTY'),
      'detail','K1 STANDARD movida para a reserva K2 REVERSE → OCCUPIED_MISMATCH (granularidade carta + acabamento); origem volta a RESERVED_EMPTY');

    -- 6. Livre -------------------------------------------------------------------------
    select * into p from public.preview_my_collection_binder(v_cfree, 2, 2, 'PRINCIPAL_ONLY');
    select * into o from public.create_my_collection_binder(v_cfree, 2, 2, 'PRINCIPAL_ONLY', p.plan_token);
    select string_agg(g.physical_card_id::text, ',' order by g.row_index, g.column_index) into v_err
    from public.get_my_collection_binder_pages(v_cfree, 1, 1) g where g.physical_card_id is not null;
    res := res || jsonb_build_object('id','6.1','ok',
      p.collection_kind = 'FREE' and p.positions_total = 3 and p.positions_reserved = 0 and p.extras_total = 0
      and o.reservations_created = 0 and o.assignments_created = 3 and v_err = fz || ',' || fa || ',' || fb,
      'detail','Livre: ordem de entrada (fz antes); fa/fb no mesmo instante → desempate por número da carta (K1 antes de K2); sem reservas');

    -- 7. Pokédex -------------------------------------------------------------------------
    select * into p from public.preview_my_collection_binder(v_cdex, 3, 3, 'PRINCIPAL_ONLY');
    select * into o from public.create_my_collection_binder(v_cdex, 3, 3, 'PRINCIPAL_ONLY', p.plan_token);
    res := res || jsonb_build_object('id','7.1','ok',
      p.collection_kind = 'POKEDEX' and p.positions_total = 2 and p.positions_reserved = 0
      and p.extras_identical = 1 and p.extras_out_of_objective = 1 and p.extras_total = 2
      and o.reservations_created = 0 and o.assignments_created = 2
      and exists (select 1 from public.get_my_collection_binder_pages(v_cdex, 1, 1) g
                  where g.row_index = 1 and g.column_index = 1 and g.physical_card_id in (x2, x3))
      and exists (select 1 from public.get_my_collection_binder_pages(v_cdex, 1, 1) g
                  where g.row_index = 1 and g.column_index = 2 and g.physical_card_id = x1),
      'detail','Pokédex: só posições com vínculo, em ordem nacional (P1 antes de P3), sem reservas; 2ª cópia de P1 idêntica; sem vínculo = fora do objetivo');

    -- 8. Coleção vazia -------------------------------------------------------------------
    select * into p from public.preview_my_collection_binder(v_cemp, 4, 4, 'APPEND_PAGES');
    select * into o from public.create_my_collection_binder(v_cemp, 4, 4, 'APPEND_PAGES', p.plan_token);
    res := res || jsonb_build_object('id','8.1','ok',
      p.positions_total = 0 and p.pages_total = 1 and p.slots_total = 16
      and o.outcome = 'CREATED' and o.pages_created = 1 and o.slots_created = 16 and o.assignments_created = 0 and o.reservations_created = 0,
      'detail','coleção vazia: 1 página vazia de 16 bolsos (4×4), nenhuma reserva ou posição');

    -- 9. Sete modelos e mapeamento colunas × linhas ---------------------------------------
    v_ok := true; v_err := '';
    for n, n2 in select t.cc, t.rr from (values (2,2),(3,3),(3,4),(4,3),(4,4),(4,5),(5,4)) t(cc, rr) loop
      select * into p from public.preview_my_collection_binder(v_cpc, n, n2, 'PRINCIPAL_ONLY');
      v_ok := v_ok and p.capacity_per_page = n * n2 and p.grid_columns = n and p.grid_rows = n2;
      v_err := v_err || n || '×' || n2 || '=' || p.capacity_per_page || ' ';
    end loop;
    res := res || jsonb_build_object('id','9.1','ok', v_ok, 'detail','sete modelos aceitos, capacidade = colunas × linhas: ' || v_err);

    select * into p  from public.preview_my_collection_binder(v_cpc, 3, 4, 'PRINCIPAL_ONLY');
    select * into p2 from public.preview_my_collection_binder(v_cpc, 4, 3, 'PRINCIPAL_ONLY');
    res := res || jsonb_build_object('id','9.2','ok',
      exists (select 1 from jsonb_array_elements(p.sample) j
              where j->>'card_name' = 'P2A1 K4' and (j->>'row')::int = 2 and (j->>'column')::int = 1)
      and exists (select 1 from jsonb_array_elements(p2.sample) j
                  where j->>'card_name' = 'P2A1 K4' and (j->>'row')::int = 1 and (j->>'column')::int = 4)
      and p.plan_token <> p2.plan_token,
      'detail','"3×4" = 3 colunas × 4 linhas: 4ª carta na linha 2, coluna 1; em 4×3 na linha 1, coluna 4; tokens distintos');

    v_ok := true; v_err := '';
    for n, n2 in select t.cc, t.rr from (values (2,3),(5,5),(1,1),(6,4),(3,2)) t(cc, rr) loop
      begin perform count(*) from public.preview_my_collection_binder(v_cpc, n, n2, 'PRINCIPAL_ONLY'); v_ok := false;
      exception when others then v_ok := v_ok and sqlerrm = 'INVALID_GRID'; v_err := v_err || n || '×' || n2 || ' '; end;
    end loop;
    res := res || jsonb_build_object('id','9.3','ok', v_ok, 'detail','pares fora da lista recusados (INVALID_GRID): ' || v_err);

    -- 10. PLAN_CHANGED ---------------------------------------------------------------------
    select * into p from public.preview_my_collection_binder(v_cpc, 3, 3, 'PRINCIPAL_ONLY');
    v_tok := p.plan_token;
    perform public.allocate_physical_cards_to_collection(v_cpc, array[pk2]);
    begin perform count(*) from public.create_my_collection_binder(v_cpc, 3, 3, 'PRINCIPAL_ONLY', v_tok); v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlstate = 'P0001' and sqlerrm = 'PLAN_CHANGED'; v_err := sqlstate || ' ' || sqlerrm; end;
    res := res || jsonb_build_object('id','10.1','ok', v_ok and (select g.has_binder from public.get_my_collection_binder(v_cpc) g) = false,
      'detail','exemplar alocado entre prévia e confirmação → PLAN_CHANGED, nenhum fichário: ' || v_err);

    perform public.deallocate_physical_cards_from_collection(v_cpc, array[pk2]);
    select * into p from public.preview_my_collection_binder(v_cpc, 3, 3, 'PRINCIPAL_ONLY');
    v_tok2 := p.plan_token;
    select * into o from public.create_my_collection_binder(v_cpc, 3, 3, 'PRINCIPAL_ONLY', v_tok);
    res := res || jsonb_build_object('id','10.2','ok', v_tok2 = v_tok and o.outcome = 'CREATED' and o.reservations_created = 4 and o.assignments_created = 0,
      'detail','desalocado → o plano volta a ser o mesmo, o token antigo confere (token = plano resultante, não contagem) e a criação acontece');

    select * into p from public.preview_my_collection_binder(v_cms2, 3, 3, 'PRINCIPAL_ONLY');
    v_tok := p.plan_token;
    perform count(*) from public.replace_master_set_finishes(v_cms2, array[v_std, v_holo, v_rev]);
    begin perform count(*) from public.create_my_collection_binder(v_cms2, 3, 3, 'PRINCIPAL_ONLY', v_tok); v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlerrm = 'PLAN_CHANGED'; v_err := sqlstate || ' ' || sqlerrm; end;
    res := res || jsonb_build_object('id','10.3','ok', v_ok and (select g.has_binder from public.get_my_collection_binder(v_cms2) g) = false,
      'detail','acabamentos do Master Set mudaram entre prévia e confirmação → PLAN_CHANGED: ' || v_err);

    select * into p from public.preview_my_collection_binder(v_cms2, 3, 3, 'PRINCIPAL_ONLY');
    v_tok := p.plan_token;
    execute 'reset role';
    update public.card set is_active = false where id = k3;
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    begin perform count(*) from public.create_my_collection_binder(v_cms2, 3, 3, 'PRINCIPAL_ONLY', v_tok); v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlerrm = 'PLAN_CHANGED'; v_err := sqlstate || ' ' || sqlerrm; end;
    execute 'reset role';
    update public.card set is_active = true where id = k3;
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    res := res || jsonb_build_object('id','10.4','ok', v_ok and (select g.has_binder from public.get_my_collection_binder(v_cms2) g) = false,
      'detail','catálogo mudou (carta sintética desativada, C-190) entre prévia e confirmação → PLAN_CHANGED: ' || v_err);

    select * into p from public.preview_my_collection_binder(v_cms2, 3, 3, 'PRINCIPAL_ONLY');
    v_ok := true; v_err := '';
    begin perform count(*) from public.create_my_collection_binder(v_cms2, 4, 4, 'PRINCIPAL_ONLY', p.plan_token); v_ok := false;
    exception when others then v_ok := v_ok and sqlerrm = 'PLAN_CHANGED'; v_err := v_err || sqlerrm || ' '; end;
    begin perform count(*) from public.create_my_collection_binder(v_cms2, 3, 3, 'APPEND_PAGES', p.plan_token); v_ok := false;
    exception when others then v_ok := v_ok and sqlerrm = 'PLAN_CHANGED'; v_err := v_err || sqlerrm || ' '; end;
    res := res || jsonb_build_object('id','10.5','ok', v_ok and (select g.has_binder from public.get_my_collection_binder(v_cms2) g) = false,
      'detail','token de outro modelo ou de outra opção → PLAN_CHANGED (o usuário autoriza exatamente o que viu): ' || v_err);

    -- 2.6/2.7 D1 depois da criação e coleção arquivada -----------------------------------
    select * into p from public.preview_my_collection_binder(v_carb, 3, 3, 'PRINCIPAL_ONLY');
    select * into o from public.create_my_collection_binder(v_carb, 3, 3, 'PRINCIPAL_ONLY', p.plan_token);
    perform count(*) from public.update_my_storage_container(v_bin2, 'BIN2 5850', 'BOX');
    select * into s from public.get_my_collection_binder(v_carb);
    res := res || jsonb_build_object('id','2.6','ok', o.outcome = 'CREATED' and s.has_binder and s.is_editable and s.default_storage_kind_code = 'BOX',
      'detail','D1: depois de criado, trocar o tipo do local padrão não tira o acesso nem a edição do fichário');

    select * into p from public.preview_my_collection_binder(v_cms2, 3, 3, 'PRINCIPAL_ONLY');
    perform count(*) from public.archive_collection(v_cms2);
    begin perform count(*) from public.create_my_collection_binder(v_cms2, 3, 3, 'PRINCIPAL_ONLY', p.plan_token); v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlstate = '55000' and sqlerrm = 'COLLECTION_ARCHIVED'; v_err := sqlstate || ' ' || sqlerrm; end;
    res := res || jsonb_build_object('id','2.7','ok', v_ok and (select g.has_binder from public.get_my_collection_binder(v_cms2) g) = false,
      'detail','coleção arquivada → 55000 COLLECTION_ARCHIVED, nada criado: ' || v_err);

    -- 13. M3 (5225) ------------------------------------------------------------------------
    select g.slot_id into v_slot1 from public.get_my_collection_binder_pages(v_cpc, 1, 1) g where g.row_index = 3 and g.column_index = 3;
    select * into o from public.set_slot_expected_content(v_slot1, k2, null, v_holo);
    res := res || jsonb_build_object('id','13.1','ok', o.card_id = k2 and o.expected_variant_type_id = v_holo and o.card_variant_id is null
      and exists (select 1 from public.get_my_collection_binder_pages(v_cpc, 1, 1) g
                  where g.slot_id = v_slot1 and g.slot_state = 'RESERVED_EMPTY' and g.expected_variant_type_code = 'HOLO'),
      'detail','set_slot_expected_content(carta, acabamento) grava e a 5223 lê a reserva com o acabamento');
    begin perform count(*) from public.set_slot_expected_content(v_slot1, k2, k2h, v_holo); v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlstate = '22023' and sqlerrm = 'EXPECTED_CONTENT_VARIANT_AND_TYPE_EXCLUSIVE'; v_err := sqlstate || ' ' || sqlerrm; end;
    res := res || jsonb_build_object('id','13.2','ok', v_ok, 'detail','variante e acabamento juntos → 22023 EXCLUSIVE: ' || v_err);
    execute 'reset role';
    begin update public.collection_layout_slot_expected_content set expected_variant_type_id = v_vt_other where slot_id = v_slot1;
      v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlstate = '23514' and sqlerrm like '%EXPECTED_VARIANT_TYPE_GAME_MISMATCH%'; v_err := sqlstate || ' ' || sqlerrm; end;
    res := res || jsonb_build_object('id','13.3','ok', v_ok, 'detail','acabamento de outro jogo (escrita direta do dono) → 23514 pelo trigger: ' || v_err);
    begin update public.collection_layout_slot_expected_content set card_variant_id = k2h where slot_id = v_slot1;
      v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlstate = '23514'; v_err := sqlstate || ' ' || sqlerrm; end;
    res := res || jsonb_build_object('id','13.4','ok', v_ok, 'detail','variante + acabamento por escrita direta → CHECK chk_expected_content_variant_xor_type: ' || v_err);
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';

    -- 14. Alteração de grade restrita aos sete modelos (5228) ------------------------
    select x.collection_id into v_cgrid from public.create_my_free_collection(gen_random_uuid(), 'CGRID 5850', v_bin) x;
    select x.collection_id into v_cleg  from public.create_my_free_collection(gen_random_uuid(), 'CLEG 5850', v_bin) x;
    select * into p from public.preview_my_collection_binder(v_cgrid, 2, 2, 'PRINCIPAL_ONLY');
    select * into o from public.create_my_collection_binder(v_cgrid, 2, 2, 'PRINCIPAL_ONLY', p.plan_token);
    v_lay_g := o.layout_id;
    select g.page_id into v_page from public.get_my_collection_binder_pages(v_cgrid, 1, 1) g limit 1;
    perform public.remove_layout_page(v_page);
    -- assinatura vigente: (p_layout_id, p_grid_rows, p_grid_columns); modelos em colunas × linhas.
    v_ok := true; v_err := '';
    for n, n2 in select t.cc, t.rr from (values (2,2),(3,3),(3,4),(4,3),(4,4),(4,5),(5,4)) t(cc, rr) loop
      select * into s from public.set_collection_layout_grid(v_lay_g, n2, n);
      v_ok := v_ok and s.grid_columns = n and s.grid_rows = n2;
      v_err := v_err || n || '×' || n2 || ' ';
    end loop;
    select * into p2 from public.get_my_collection_binder(v_cgrid);
    res := res || jsonb_build_object('id','14.1','ok', v_ok and p2.page_count = 0 and p2.grid_columns = 5 and p2.grid_rows = 4,
      'detail','sete modelos aceitos com zero páginas (colunas × linhas): ' || v_err);

    v_ok := true; v_err := '';
    for n, n2 in select t.cc, t.rr from (values (2,3),(5,5),(1,1),(10,10),(4,6),(3,2)) t(cc, rr) loop
      begin perform count(*) from public.set_collection_layout_grid(v_lay_g, n2, n); v_ok := false;
      exception when others then v_ok := v_ok and sqlstate = '22023' and sqlerrm like 'INVALID_GRID%'; v_err := v_err || n || '×' || n2 || ' '; end;
    end loop;
    select * into p2 from public.get_my_collection_binder(v_cgrid);
    res := res || jsonb_build_object('id','14.2','ok', v_ok and p2.grid_columns = 5 and p2.grid_rows = 4 and p2.page_count = 0,
      'detail','pares fora da lista → 22023 INVALID_GRID, grade intacta (5×4): ' || v_err);

    perform count(*) from public.add_layout_page(v_lay_g);
    begin perform count(*) from public.set_collection_layout_grid(v_lay_g, 3, 3); v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlerrm like 'grid do Layout não pode ser alterado enquanto existirem Pages%'; v_err := sqlstate || ' ' || sqlerrm; end;
    select * into p2 from public.get_my_collection_binder(v_cgrid);
    res := res || jsonb_build_object('id','14.3','ok', v_ok and p2.grid_columns = 5 and p2.grid_rows = 4 and p2.page_count = 1,
      'detail','modelo válido com página existente → recusa preservada (regra 5137): ' || v_err);

    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    begin perform count(*) from public.set_collection_layout_grid(v_lay_g, 3, 3); v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlerrm = 'collection layout not found or not owned by caller'; v_err := sqlstate || ' ' || sqlerrm; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','14.4','ok', v_ok
      and (select l.grid_columns = 5 and l.grid_rows = 4 from public.collection_layout l where l.id = v_lay_g),
      'detail','B alterando a grade do layout de A → mesma resposta de inexistente (5122), grade intacta: ' || v_err);
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';

    perform count(*) from public.remove_layout_page((select g.page_id from public.get_my_collection_binder_pages(v_cgrid, 1, 1) g limit 1));
    perform count(*) from public.archive_collection(v_cgrid);
    begin perform count(*) from public.set_collection_layout_grid(v_lay_g, 3, 3); v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlerrm like 'collection is ARCHIVED%'; v_err := sqlstate || ' ' || sqlerrm; end;
    select * into p2 from public.get_my_collection_binder(v_cgrid);
    res := res || jsonb_build_object('id','14.5','ok', v_ok and p2.grid_columns = 5 and p2.grid_rows = 4,
      'detail','coleção arquivada → recusa da 5122 antes da regra de modelo, grade intacta: ' || v_err);

    execute 'reset role';
    -- Layout preexistente fora dos sete (simulado como dono: 7×7, zero páginas).
    insert into public.collection_layout (collection_id, grid_rows, grid_columns)
    values (v_cleg, 7, 7) returning id, updated_at into v_lay_l, v_upd;
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    begin perform count(*) from public.set_collection_layout_grid(v_lay_l, 7, 7); v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlstate = '22023' and sqlerrm like 'INVALID_GRID%'; v_err := sqlstate || ' ' || sqlerrm; end;
    select * into p2 from public.get_my_collection_binder(v_cleg);
    execute 'reset role';
    res := res || jsonb_build_object('id','14.6','ok', v_ok and p2.has_binder and p2.grid_columns = 7 and p2.grid_rows = 7
      and (select l.updated_at = v_upd and l.grid_rows = 7 and l.grid_columns = 7 from public.collection_layout l where l.id = v_lay_l),
      'detail','layout preexistente 7×7: legível pela 5223, não recebe grade fora da lista e não é alterado (updated_at igual): ' || v_err);
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';

    -- 12. Desmontagem ---------------------------------------------------------------------
    select g.slot_id, g.page_id into v_slot1, v_page from public.get_my_collection_binder_pages(v_cset, 1, 1) g
    where g.row_index = 1 and g.column_index = 1;
    perform public.set_slot_lock(array[v_slot1], true);
    perform count(*) from public.merge_layout_region(v_page, 3, 1, 1, 2);
    select * into p from public.preview_my_collection_binder_dismantle(v_cset);
    res := res || jsonb_build_object('id','12.1','ok',
      p.has_binder and p.pages_count = 2 and p.slots_count = 18 and p.locked_count = 1 and p.assignments_count = 5
      and p.reservations_count = 4 and p.regions_count = 1 and p.dismantle_token ~ '^d1:[0-9a-f]{64}$',
      'detail', format('prévia da desmontagem: páginas %s, bolsos %s, travados %s, posições %s, reservas %s, mesclagens %s',
        p.pages_count, p.slots_count, p.locked_count, p.assignments_count, p.reservations_count, p.regions_count));

    v_tok := p.dismantle_token;
    select g.slot_id into v_slot2 from public.get_my_collection_binder_pages(v_cset, 1, 1) g where g.row_index = 1 and g.column_index = 3;
    perform public.set_slot_lock(array[v_slot2], true);
    begin perform count(*) from public.dismantle_my_collection_binder(v_cset, v_tok); v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlstate = 'P0001' and sqlerrm = 'DISMANTLE_PLAN_CHANGED'; v_err := sqlstate || ' ' || sqlerrm; end;
    res := res || jsonb_build_object('id','12.2','ok', v_ok and (select g.has_binder from public.get_my_collection_binder(v_cset) g),
      'detail','fichário editado depois da prévia (nova trava) → DISMANTLE_PLAN_CHANGED, nada removido: ' || v_err);

    select * into p from public.preview_my_collection_binder_dismantle(v_cset);
    select md5(string_agg(to_jsonb(pc)::text, ',' order by pc.id)) into h1 from public.physical_card pc where pc.inventory_id = v_inv_a;
    select md5(string_agg(ca.id::text || ':' || ca.physical_card_id || ':' || ca.collection_id, ',' order by ca.id)) into v_tok2
    from public.collection_allocation ca where ca.collection_id = v_cset;
    select * into o from public.dismantle_my_collection_binder(v_cset, p.dismantle_token);
    select md5(string_agg(to_jsonb(pc)::text, ',' order by pc.id)) into h2 from public.physical_card pc where pc.inventory_id = v_inv_a;
    res := res || jsonb_build_object('id','12.3','ok',
      o.outcome = 'DISMANTLED' and o.pages_removed = 2 and o.slots_removed = 18 and o.assignments_removed = 5
      and o.reservations_removed = 4 and o.regions_removed = 1 and o.locks_released = 2
      and h1 = h2
      and v_tok2 = (select md5(string_agg(ca.id::text || ':' || ca.physical_card_id || ':' || ca.collection_id, ',' order by ca.id))
                    from public.collection_allocation ca where ca.collection_id = v_cset)
      and (select g.has_binder = false and g.can_create from public.get_my_collection_binder(v_cset) g),
      'detail', format('desmontagem atômica: páginas %s, bolsos %s, posições %s, reservas %s, mesclagens %s, travas liberadas %s; exemplares e alocações intactos; pode criar de novo',
        o.pages_removed, o.slots_removed, o.assignments_removed, o.reservations_removed, o.regions_removed, o.locks_released));

    select * into o from public.dismantle_my_collection_binder(v_cset, p.dismantle_token);
    res := res || jsonb_build_object('id','12.4','ok', o.outcome = 'ALREADY_ABSENT' and o.pages_removed = 0,
      'detail','repetição após sucesso → ALREADY_ABSENT, nada muda');

    perform count(*) from public.archive_collection(v_carb);
    select * into p from public.preview_my_collection_binder_dismantle(v_carb);
    select * into o from public.dismantle_my_collection_binder(v_carb, p.dismantle_token);
    res := res || jsonb_build_object('id','12.5','ok', p.lifecycle_status = 'ARCHIVED' and o.outcome = 'DISMANTLED'
      and (select g.has_binder from public.get_my_collection_binder(v_carb) g) = false,
      'detail','coleção ARQUIVADA: desmontagem permitida (R4) — sem ela o fichário prenderia a coleção');

    begin perform count(*) from public.delete_collection(v_cemp); v_ok := false; v_err := 'executou';
    exception when others then
      get stacked diagnostics v_hint = pg_exception_hint;
      v_ok := sqlerrm = 'collection has a digital binder — dismantle it before deleting' and v_hint = 'BINDER_EXISTS';
      v_err := sqlstate || ' ' || sqlerrm;
    end;
    res := res || jsonb_build_object('id','12.6','ok', v_ok and (select count(*) from public.collection c0 where c0.id = v_cemp) = 1,
      'detail','delete_collection com fichário → erro de domínio (HINT BINDER_EXISTS), sem cascata: ' || v_err);

    select * into p from public.preview_my_collection_binder_dismantle(v_cemp);
    perform count(*) from public.dismantle_my_collection_binder(v_cemp, p.dismantle_token);
    perform count(*) from public.delete_collection(v_cemp);
    res := res || jsonb_build_object('id','12.7','ok', (select count(*) from public.collection c0 where c0.id = v_cemp) = 0,
      'detail','depois da desmontagem confirmada, a exclusão da coleção acontece');

    v_ok := true; v_err := '';
    begin perform count(*) from public.dismantle_my_collection_binder(v_cms, 'x'); v_ok := false;
    exception when others then v_ok := v_ok and sqlstate = '22023' and sqlerrm = 'INVALID_DISMANTLE_TOKEN'; v_err := v_err || sqlerrm || ' '; end;
    begin perform count(*) from public.dismantle_my_collection_binder(v_cms, 'v1:' || repeat('0', 64)); v_ok := false;
    exception when others then v_ok := v_ok and sqlstate = '22023' and sqlerrm = 'INVALID_DISMANTLE_TOKEN'; v_err := v_err || sqlerrm || ' '; end;
    res := res || jsonb_build_object('id','12.8','ok', v_ok and (select g.has_binder from public.get_my_collection_binder(v_cms) g),
      'detail','token de desmontagem malformado (ou de plano de criação) → 22023 INVALID_DISMANTLE_TOKEN: ' || v_err);

    -- 11. Falha injetada (só p_isolated) ------------------------------------------------------
    if p_isolated then
      execute 'reset role';
      -- Função e trigger temporários de TESTE no schema public, criados e
      -- removidos dentro da transação da sentinela (só em ambiente isolado).
      execute $t$create function public.p2a1_harness_fail() returns trigger language plpgsql set search_path = '' as $b$
        begin raise exception 'P2A1_INJECTED_FAILURE'; end; $b$$t$;
      execute format('create trigger p2a1_fail before insert on public.collection_layout_slot_assignment for each row '
                     || 'when (new.collection_allocation_id = %L) execute function public.p2a1_harness_fail()',
                     (select ca.id from public.collection_allocation ca where ca.physical_card_id = e));
      perform set_config('request.jwt.claim.sub', u_a::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
      execute 'set local role authenticated';
      select * into p from public.preview_my_collection_binder(v_cset, 3, 3, 'PRINCIPAL_ONLY');
      begin perform count(*) from public.create_my_collection_binder(v_cset, 3, 3, 'PRINCIPAL_ONLY', p.plan_token); v_ok := false; v_err := 'executou';
      exception when others then v_ok := sqlerrm = 'P2A1_INJECTED_FAILURE'; v_err := sqlstate || ' ' || sqlerrm; end;
      execute 'reset role';
      execute 'drop trigger p2a1_fail on public.collection_layout_slot_assignment';
      execute 'drop function public.p2a1_harness_fail()';
      res := res || jsonb_build_object('id','11.1','ok', v_ok
        and (select count(*) from public.collection_layout l where l.collection_id = v_cset) = 0
        and (select count(*) from public.collection_layout_page lp
             where not exists (select 1 from public.collection_layout l where l.id = lp.layout_id)) = 0,
        'detail','falha no meio da gravação (2ª posição) → nenhum layout, página, bolso ou reserva sobra: ' || v_err);
      perform set_config('request.jwt.claim.sub', u_a::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
      execute 'set local role authenticated';

      -- P. Desempenho (carga sintética; só fora do LIVE) ---------------------------------------
      foreach v_size in array array[500, 2000, 10000, 10001] loop
        execute 'reset role';
        insert into public.physical_card (card_variant_id, language_id, inventory_id, created_at)
        select (array[k1s, k2s, k3s, k4h, k1r, k2h, k2r])[1 + g % 7], v_pt, v_inv_a, now() - make_interval(secs => g)
        from generate_series(1, v_size) g;
        select array_agg(pc.id) into v_ids from public.physical_card pc
        where pc.inventory_id = v_inv_a
          and not exists (select 1 from public.collection_allocation ca where ca.physical_card_id = pc.id);
        perform set_config('request.jwt.claim.sub', u_a::text, true);
        perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
        execute 'set local role authenticated';
        select x.collection_id into v_cperf from public.create_my_free_collection(gen_random_uuid(), 'PERF ' || v_size, v_bin) x;
        -- 5046 aceita no máximo 500 exemplares por chamada (5139): lotes.
        v_off := 0;
        while v_off < v_size loop
          perform public.allocate_physical_cards_to_collection(v_cperf, v_ids[v_off + 1 : least(v_off + 500, v_size)]);
          v_off := v_off + 500;
        end loop;
        v_t0 := clock_timestamp();
        select * into p from public.preview_my_collection_binder(v_cperf, 2, 2, 'APPEND_PAGES');
        v_ms := round(extract(epoch from clock_timestamp() - v_t0)::numeric * 1000, 1);
        if v_size <= 10000 then
          v_t0 := clock_timestamp();
          select * into o from public.create_my_collection_binder(v_cperf, 2, 2, 'APPEND_PAGES', p.plan_token);
          res := res || jsonb_build_object('id', case v_size when 500 then 'P.1' when 2000 then 'P.2' else 'P.3' end,
            'ok', o.outcome = 'CREATED' and o.assignments_created = v_size and o.slots_created = ((v_size + 3) / 4) * 4,
            'detail', format('%s alocações, 2×2: prévia %s ms, criação %s ms, %s páginas — MEDIDO (teto não aprovado por este harness)',
              v_size, v_ms, round(extract(epoch from clock_timestamp() - v_t0)::numeric * 1000, 1), o.pages_created));
        else
          begin perform count(*) from public.create_my_collection_binder(v_cperf, 2, 2, 'APPEND_PAGES', 'v1:' || repeat('0', 64)); v_ok := false; v_err := 'executou';
          exception when others then v_ok := sqlstate = '54000' and sqlerrm = 'COLLECTION_TOO_LARGE'; v_err := sqlstate || ' ' || sqlerrm; end;
          res := res || jsonb_build_object('id','P.4','ok', v_ok and p.too_large and p.plan_token is null
            and (select g.has_binder from public.get_my_collection_binder(v_cperf) g) = false,
            'detail', format('10.001 alocações: prévia too_large (%s ms), criação recusada sem gravar: %s', v_ms, v_err));
        end if;
      end loop;
    end if;

    raise exception 'MS850' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MS850' then
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
      and (select count(*) from public.collection_layout) = b_l
      and (select count(*) from public.collection_layout_page) = b_lp
      and (select count(*) from public.collection_layout_slot) = b_ls
      and (select count(*) from public.collection_layout_slot_expected_content) = b_le
      and (select count(*) from public.collection_layout_slot_assignment) = b_la
      and (select count(*) from public.collection_layout_region) = b_lr
      and (select count(*) from public.card) = b_card
      and (select count(*) from public.card_variant) = b_cv
      and (select count(*) from public.card_set) = b_cs
      and (select count(*) from public.expansion) = b_ex
      and (select count(*) from public.game) = b_g
      and (select count(*) from public.card_variant_type) = b_vt
      and not exists (select 1 from pg_trigger t where t.tgname = 'p2a1_fail')
      and to_regprocedure('public.p2a1_harness_fail()') is null
      and current_user = session_user,
    'detail','resíduo zero (usuários, locais, coleções, alocações, exemplares, fichário inteiro, catálogo sintético, trigger e função de falha) e papel restaurado');
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
    when (select count(*) from jsonb_array_elements(res) x where x->>'id' not like 'P.%' and x->>'id' <> '11.1') <> v_expected then 'FAIL'
    -- v1.1: um ID repetido não pode compensar um teste que deixou de rodar.
    when (select count(distinct x->>'id') from jsonb_array_elements(res) x) <> cnt then 'FAIL'
    when p_isolated and (select count(*) from jsonb_array_elements(res) x where x->>'id' like 'P.%' or x->>'id' = '11.1') <> 5 then 'FAIL'
    when not p_isolated then 'PASS_FUNCTIONAL_ISOLATED_NOT_EXERCISED'
    else 'PASS' end;
  detail := format('%s/%s PASS (funcional esperado %s%s); teto provisório NÃO aprovado pelo harness', passes, cnt, v_expected,
    case when p_isolated then ' + 11.1 e P.1–P.4' else '' end);
  return next;
end;
$fn$;

select * from pg_temp.wh_5850_validate(false);
