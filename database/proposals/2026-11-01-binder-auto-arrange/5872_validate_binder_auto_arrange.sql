/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5872 - Harness: organização automática do fichário (5341–5344)
Versão......: 1.5
Status......: PROPOSTO — NÃO EXECUTADO (FOUNDATION-06; v1.1 TARGETED SQL SAFETY AUDIT-07,
              2026-11-01). Nenhum PASS foi observado; só revisão estática local.
              v1.1: K9 e C.4 desativam variante NÃO padrão (ck_card_variant_default_active
              impede desativar a padrão — a v1.0 falharia na fixture); reserva da
              convidada pela RPC oficial; bolsos da proprietária com collection_id
              nulo ou = CS; I.4 (mesmo conjunto de pares reaparece → token antigo
              ALREADY_APPLIED, nova prévia aplica).
              v1.2 (TOKEN & CONCURRENCY CLOSEOUT-08): I.5 — limpeza do histórico
              (5270) não reautoriza tokens antigos; H.2 recontado; marco de
              cobertura no resíduo 9.1 (53 ids).
              v1.3 (CONTROLLED EXECUTION READINESS-09): acabamento alternativo fixado
              em REVERSE_HOLO (preflight: o 1º por código no LIVE é COSMO_HOLO_EBGAMES);
              S0.6 guarda a premissa da época (único escritor do marco = 5270 com
              now(), sem EXECUTE para clientes) — 54 ids.
              v1.4 (P2 GATE 02 TARGETED CORRECTION-12): só S0.4 — a busca de
              escrita passa a rodar sobre o código sem literais e comentários (o
              rótulo 'INSERT' da 5342 dava falso negativo) e, para a 5342, exige
              LANGUAGE sql + STABLE (o PostgreSQL recusa DML em função SQL não
              volátil). Mesmos 54 ids e mesmo GATE.
              v1.5 (P2 HARNESS C-SERIES CORRECTION-14): só o laço C.1–C.6 — na v1.4
              as contagens de controle rodavam como authenticated (42501 em
              binder_activity_event; posições filtradas por RLS) e os seis casos não
              chegavam à 5344 (GATE 03: 48/54). Agora as leituras de controle rodam
              como dono do banco; só a alteração do cenário e a chamada da 5344 rodam
              como authenticated. Cada caso confere também: token ainda vigente antes
              da alteração e reservas/alocações/exemplares/posições idênticos antes e
              depois da chamada. Mesmos 54 ids e mesmo GATE.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-01

Protocolo (o mesmo de 5854/5871): função em pg_temp, UMA chamada; usuários
efêmeros A, B e C; catálogo sintético inserido pelo dono do banco; locais,
coleções, fichários, alocações, reservas e travas pelas RPCs oficiais como o
próprio usuário; exemplares inseridos pelo dono no Inventory criado pelo
gatilho de auth.users. A sentinela TR000 desfaz tudo; 9.1 confere resíduo
zero. Executar SÓ depois de 5341 → 5342 → 5343 → 5344 aplicadas.

GATE por identificadores: cada id de v_expected aparece exatamente uma vez,
todos PASS, nenhum X.1 e nenhum id fora da lista.

Fixture (usuário A, Set sintético K1..K11, fichário 3×3 do Set "CS" no local BIN)
  K1  1 cópia                                      → INSERT (reserva só carta)
  K2  2 cópias                                     → ambíguo por cópias
  K3  1 cópia + 2ª reserva da proprietária         → ambíguo por destinos
  K4  1 cópia, bolso travado                       → bolso inelegível
  K5  2 cópias, uma já posicionada no bolso        → bolso ocupado intocado
  K6  1 cópia alocada, guardada em OTH             → fora do local
  K7  1 cópia no BIN alocada à coleção livre CF    → outra coleção
  K8  sem cópias                                   → bolso sem candidato
  K9  1 cópia da variante ALT (não padrão), desativada depois → INACTIVE_VARIANT
  K10 STD + ALT; bolso reduzido à variante ALT     → reserva por variante exata
  K11 cópia da convidada CG; bolso extra reservado à convidada → excluídos
  CM  Master Set (STD+ALT) no local BINM: K10 STD e K10 ALT → reserva carta+acabamento
  CC  usuário C, Set sintético de 501 cartas, 501 cópias → limite e volume

Checagens
  S0.1–S0.3 configuração e ACL de 5342/5343/5344 · S0.4 corpo sem escrita (código sem literais/comentários; 5342 sql STABLE)
  proibida · S0.5 5341 (CHECK + categoria) · F.1 fixture
  A.1 anon prévia 42501 · A.2 anon aplicação 42501 · A.3 sem identidade 28000
  A.4 B prévia de A → COLLECTION_NOT_FOUND · A.5 B aplica token de A → idem,
  zero escrita · A.6 authenticated sem EXECUTE na função interna
  T.1 Pokédex · T.2 Livre → AUTO_ARRANGE_UNSUPPORTED_COLLECTION · T.3
  convidada → AUTO_ARRANGE_NOT_BINDER_OWNER · T.4 sem fichário →
  BINDER_NOT_FOUND · T.5 arquivada → COLLECTION_ARCHIVED · T.6 argumentos
  P.1 prévia: READY, 2 itens exatos · P.2 exclusões por motivo · P.3 bolsos
  vazios por motivo · P.4 travado/ocupado/convidada/fora fora do plano ·
  P.5 determinismo e somente leitura · P.6 desempenho (501/500)
  G.1 carta · G.2 carta + acabamento (Master Set, aplicado) · G.3 variante exata
  M.1 1:1 · M.2 ambiguidade por cópias · M.3 por destinos · M.4 variante
  inativa · M.5 outra coleção / fora do local
  C.1 exemplar movido · C.2 bolso ocupado · C.3 reserva alterada · C.4
  variante desativada · C.5 bolso travado · C.6 nova cópia ambígua →
  AUTO_ARRANGE_PLAN_CHANGED 40001, zero escrita, reservas/alocações/exemplares
  preservados (cada um em sub-bloco desfeito; leituras de controle como dono do banco)
  D.1 aplicação · D.2 nenhum efeito colateral (reservas, travas, alocações,
  locais, exemplares, posições anteriores)
  H.1 um evento + itens rastreáveis · H.2 exatamente 3 eventos restantes (só APPLIED gravam; limpeza de CM em I.5)
  I.1 repetição → ALREADY_APPLIED · I.2 plano vazio → EMPTY / NOTHING_TO_DO ·
  I.3 token alheio → PLAN_CHANGED · I.4 mesmos pares reaparecem (Master Set):
  token antigo → ALREADY_APPLIED; nova prévia tem token novo e aplica · I.5
  limpeza do histórico do fichário (5270) + mesmos pares: tokens antigos →
  PLAN_CHANGED, zero escrita; nova prévia aplica
  L.1 prévia 501 → LIMIT_EXCEEDED · L.2 aplicação 501 → 54000, zero escrita ·
  L.3 500 → APPLIED, evento com 500 itens
  K.1 ordem de travas e dois recálculos (estático)
  R.1 consolidado de zero escrita nos caminhos de erro
  9.1 resíduo zero e papel restaurado
  Concorrência real entre sessões: roteiro manual no README (K-M1..K-M3),
  fora do GATE automático — NÃO PROVADA por este harness.
Erro inesperado: X.1 FAIL.
================================================================
*/

create or replace function pg_temp.tr_5872_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  f_plan  oid := to_regprocedure('public.binder_auto_arrange_plan(uuid,uuid,uuid)');
  f_prev  oid := to_regprocedure('public.preview_my_binder_auto_arrange(uuid)');
  f_apply oid := to_regprocedure('public.apply_my_binder_auto_arrange(uuid,text)');
  v_expected text[] := array[
    'S0.1','S0.2','S0.3','S0.4','S0.5','S0.6','F.1',
    'A.1','A.2','A.3','A.4','A.5','A.6',
    'T.1','T.2','T.3','T.4','T.5','T.6',
    'P.1','P.2','P.3','P.4','P.5','P.6',
    'G.1','G.2','G.3','M.1','M.2','M.3','M.4','M.5',
    'C.1','C.2','C.3','C.4','C.5','C.6',
    'D.1','D.2','H.1','H.2','I.1','I.2','I.3','I.4','I.5',
    'L.1','L.2','L.3','K.1','R.1','9.1'];
  u_a uuid := gen_random_uuid();
  u_b uuid := gen_random_uuid();
  u_c uuid := gen_random_uuid();
  v_sfx text := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  v_game uuid; v_pt uuid; v_std uuid; v_alt uuid; v_rar uuid; v_cat uuid;
  v_exp uuid; v_set uuid; v_set2 uuid;
  k uuid[] := '{}'; kv uuid[] := '{}'; v_id uuid; k10alt uuid; k9alt uuid;
  v_inv_a uuid; v_inv_c uuid;
  v_bin uuid; v_oth uuid; v_binm uuid; v_binc uuid;
  cs uuid; cf uuid; cg uuid; csg uuid; cnb uuid; cp uuid; car uuid; cm uuid; cc uuid;
  ls uuid; lm uuid; lc uuid;
  c1 uuid; c2a uuid; c2b uuid; c3 uuid; c4 uuid; c5a uuid; c5b uuid; c6 uuid; c7 uuid;
  c9 uuid; c10s uuid; c10a uuid; c11g uuid; m10s uuid; m10a uuid;
  v_cpcs uuid[];
  sk uuid[] := '{}'; s3x uuid; sg uuid; slc uuid;
  p record;
  j jsonb; j2 jsonb;
  t_cs text; t_cm text; t_c text; t_e text; t_cm2 text; t_cm3 text; v_s2 text[];
  v_err text; v_st text; v_s text[];
  v_ok boolean; v_csg_ok boolean := false; v_k9_ok boolean := false;
  v_zero_ok boolean := true;
  v_n bigint; v_m bigint; v_e0 bigint; v_e1 bigint;
  v_aa0 bigint;
  v_t0 timestamptz; v_ms_prev numeric; v_ms_apply numeric;
  h_before text; h_after text;
  v_src text;
  b_counts bigint[];
  res jsonb := '[]'::jsonb;
  r jsonb;
  n integer := 0;
  passes integer := 0;
  v_ok_ids boolean;
begin
  -- S0. Configuração, ACL e corpo ---------------------------------------------------------
  res := res || jsonb_build_object('id','S0.1','ok',
    f_plan is not null
    and (select not p.prosecdef and p.proconfig = array['search_path=""'] and l.lanname = 'sql'
                and p.provolatile = 's' and p.proretset
         from pg_proc p join pg_language l on l.oid = p.prolang where p.oid = f_plan)
    and not has_function_privilege('authenticated', f_plan, 'EXECUTE')
    and not has_function_privilege('anon', f_plan, 'EXECUTE')
    and not has_function_privilege('service_role', f_plan, 'EXECUTE')
    and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = f_plan and a.grantee = 0),
    'detail','5342: INVOKER, sql, STABLE, search_path vazio, sem EXECUTE para PUBLIC/anon/authenticated/service_role');
  res := res || jsonb_build_object('id','S0.2','ok',
    f_prev is not null
    and (select p.prosecdef and p.proconfig = array['search_path=""'] and l.lanname = 'plpgsql'
                and p.provolatile = 's' and p.prorettype = 'jsonb'::regtype
         from pg_proc p join pg_language l on l.oid = p.prolang where p.oid = f_prev)
    and has_function_privilege('authenticated', f_prev, 'EXECUTE')
    and not has_function_privilege('anon', f_prev, 'EXECUTE')
    and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = f_prev and a.grantee = 0)
    and (select count(*) from pg_proc q join pg_namespace ns on ns.oid = q.pronamespace
         where ns.nspname = 'public' and q.proname = 'preview_my_binder_auto_arrange') = 1,
    'detail','5343: DEFINER, plpgsql, STABLE, jsonb, search_path vazio, EXECUTE só authenticated, 1 versão');
  res := res || jsonb_build_object('id','S0.3','ok',
    f_apply is not null
    and (select p.prosecdef and p.proconfig @> array['search_path=""','lock_timeout=5s'] and cardinality(p.proconfig) = 2
                and l.lanname = 'plpgsql' and p.provolatile = 'v' and p.prorettype = 'jsonb'::regtype
         from pg_proc p join pg_language l on l.oid = p.prolang where p.oid = f_apply)
    and has_function_privilege('authenticated', f_apply, 'EXECUTE')
    and not has_function_privilege('anon', f_apply, 'EXECUTE')
    and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = f_apply and a.grantee = 0)
    and (select count(*) from pg_proc q join pg_namespace ns on ns.oid = q.pronamespace
         where ns.nspname = 'public' and q.proname = 'apply_my_binder_auto_arrange') = 1,
    'detail','5344: DEFINER, plpgsql, VOLATILE, jsonb, search_path vazio + lock_timeout 5s, EXECUTE só authenticated, 1 versão');
  select p.prosrc into v_src from pg_proc p where p.oid = f_apply;
  -- S0.4 (v1.4): a busca de escrita roda sobre o CÓDIGO, sem literais e sem
  -- comentários (literais viram aspas vazias; depois saem comentários de linha
  -- e de bloco). Isso
  -- evita o falso negativo do rótulo 'INSERT' da 5342. Para a 5342 a prova não
  -- é só textual: exige-se LANGUAGE sql + STABLE, e o PostgreSQL recusa
  -- INSERT/UPDATE/DELETE em função SQL não volátil na execução (P.5/P.6 a executam).
  res := res || jsonb_build_object('id','S0.4','ok',
    v_src is not null
    and (select a.code !~* '\m(delete|update|truncate|merge)\M'
                and a.code !~* 'insert\s+into\s+public\.(collection_layout_slot_expected_content|collection_allocation|physical_card|storage_container|collection_layout_slot\s|collection_layout_slot\()'
                and a.code !~* 'on\s+conflict'
         from (select regexp_replace(regexp_replace(regexp_replace(regexp_replace(v_src,
                        '''(?:[^'']|'''')*''', '''''', 'g'),
                        '--[^\n]*', '', 'g'),
                        '/\*.*?\*/', '', 'g'),
                        'for\s+update', '', 'gi') as code) a)
    and (select l.lanname = 'sql' and q.provolatile = 's'
                and q.prosrc ~* 'collection_layout_slot_image' and q.prosrc ~* 'collection_layout_region'
                and q.prosrc ~* 'not s\.locked' and q.prosrc ~* 'collection_allocation'
                and q.prosrc ~* 'storage_container_id = p_container_id'
                and q.prosrc ~* 'e\.collection_id is null or e\.collection_id = p_collection_id'
                and regexp_replace(regexp_replace(regexp_replace(q.prosrc,
                      '''(?:[^'']|'''')*''', '''''', 'g'),
                      '--[^\n]*', '', 'g'),
                      '/\*.*?\*/', '', 'g') !~* '\m(insert|update|delete|truncate|merge)\M'
         from pg_proc q join pg_language l on l.oid = q.prolang where q.oid = f_plan),
    'detail','5344 sem DELETE/UPDATE/MERGE/ON CONFLICT nem INSERT fora de posições (código sem literais/comentários); 5342 sql STABLE, sem comando de escrita no código e com os filtros de bolso/exemplar');
  res := res || jsonb_build_object('id','S0.5','ok',
    position('CARDS_AUTO_ARRANGED' in pg_get_constraintdef(
      (select oid from pg_constraint where conrelid = 'public.binder_activity_event'::regclass and conname = 'chk_bae_event_type'))) > 0
    and public.binder_activity_category('CARDS_AUTO_ARRANGED') = 'CARDS'
    and public.binder_activity_category('CARD_PLACED') = 'CARDS',
    'detail','5341: tipo CARDS_AUTO_ARRANGED aceito e categoria CARDS; CARD_PLACED inalterado');
  res := res || jsonb_build_object('id','S0.6','ok',
    (select array_agg(p.proname::text order by p.proname)
     from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname = 'public'
       and p.prosrc ~* '(insert\s+into|update)\s+public\.binder_activity_coverage') = array['purge_my_binder_activity']
    and (select p.prosrc ~* 'updated_at\s*=\s*excluded\.updated_at' and p.prosrc ~* 'now\(\)'
         from pg_proc p where p.oid = to_regprocedure('public.purge_my_binder_activity(uuid,uuid)'))
    and not has_function_privilege('authenticated', 'public.purge_my_binder_activity(uuid,uuid)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.purge_my_binder_activity(uuid,uuid)', 'EXECUTE')
    and position('binder_activity_coverage' in (select q.prosrc from pg_proc q where q.oid = f_plan)) > 0,
    'detail','premissa da época: único escritor do marco é a 5270 (updated_at = now()), sem EXECUTE para clientes; 5342 lê o marco');
  res := res || jsonb_build_object('id','K.1','ok',
    v_src is not null
    and position('assert_collection_layout_mutable' in v_src) > 0
    and position('assert_collection_layout_mutable' in v_src) < position('for update of s' in v_src)
    and position('for update of s' in v_src) < position('for update of pc' in v_src)
    and position('for update of pc' in v_src) < position('binder_activity_begin' in v_src)
    and position('binder_activity_begin' in v_src) < position('insert into public.collection_layout_slot_assignment' in v_src)
    and (length(v_src) - length(replace(v_src, 'public.binder_auto_arrange_plan(', ''))) / length('public.binder_auto_arrange_plan(') = 2
    and v_src ~ 'AUTO_ARRANGE_PLAN_CHANGED' and v_src ~ '40001'
    and v_src ~ 'AUTO_ARRANGE_LIMIT_EXCEEDED' and v_src ~ '54000',
    'detail','5344: coleção → bolsos → exemplares → evento → INSERT; plano calculado 2 vezes; códigos 40001/54000');

  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.storage_container), (select count(*) from public.collection_layout),
               (select count(*) from public.collection_layout_slot_assignment),
               (select count(*) from public.collection_layout_slot_expected_content),
               (select count(*) from public.collection_layout_guest), (select count(*) from public.card),
               (select count(*) from public.card_variant where is_active),
               (select count(*) from public.binder_activity_event),
               (select count(*) from public.binder_activity_coverage)]
    into b_counts;
  select count(*) into v_aa0 from public.binder_activity_event where event_type = 'CARDS_AUTO_ARRANGED';

  begin
    -- F. Catálogo sintético --------------------------------------------------------------
    select g.id into v_game from public.game g where g.code = 'POKEMON';
    select l.id into v_pt from public.language l where l.code = 'pt-BR';
    select t.id into v_std from public.card_variant_type t where t.game_id = v_game and t.code = 'STANDARD';
    select t.id into v_alt from public.card_variant_type t where t.game_id = v_game and t.code = 'REVERSE_HOLO';
    select c0.rarity_id, c0.category_id into v_rar, v_cat
    from public.card c0 join public.card_set cs0 on cs0.id = c0.card_set_id
    join public.expansion e0 on e0.id = cs0.expansion_id
    where e0.game_id = v_game limit 1;
    if v_game is null or v_pt is null or v_std is null or v_alt is null or v_rar is null then
      raise exception 'TR_FIXTURE: pré-requisitos de catálogo ausentes';
    end if;
    insert into public.expansion (game_id, code, name, release_order)
    values (v_game, 'AA_' || v_sfx, 'AA Harness ' || v_sfx,
            (select coalesce(max(x.release_order), 0) + 1000 from public.expansion x where x.game_id = v_game))
    returning id into v_exp;
    insert into public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_exp, 'AA' || v_sfx, 'AA Set ' || v_sfx, 'REGULAR', 1, 11, 11) returning id into v_set;
    for i in 1 .. 11 loop
      insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
      values (v_set, v_rar, v_cat, i::text, i, 'AA K' || i, true) returning id into v_id;
      k := k || v_id;
      insert into public.card_variant (card_id, variant_type_id, variant_order, is_default)
      values (v_id, v_std, 1, true) returning id into v_id;
      kv := kv || v_id;
    end loop;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default)
    values (k[10], v_alt, 2, false) returning id into k10alt;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default)
    values (k[9], v_alt, 2, false) returning id into k9alt;

    insert into public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_exp, 'AL' || v_sfx, 'AA Limit ' || v_sfx, 'REGULAR', 2, 501, 501) returning id into v_set2;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    select v_set2, v_rar, v_cat, g::text, g, 'AA L' || g, true from generate_series(1, 501) g;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default)
    select c.id, v_std, 1, true from public.card c where c.card_set_id = v_set2;

    -- Usuários e locais -------------------------------------------------------------------
    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    values (u_a, 'authenticated', 'authenticated', 'aa5872-a-'||lower(v_sfx)||'@example.invalid',
            jsonb_build_object('username', 'aa5872a_'||lower(v_sfx), 'display_name', 'AA 5872 A'), now(), now()),
           (u_b, 'authenticated', 'authenticated', 'aa5872-b-'||lower(v_sfx)||'@example.invalid',
            jsonb_build_object('username', 'aa5872b_'||lower(v_sfx), 'display_name', 'AA 5872 B'), now(), now()),
           (u_c, 'authenticated', 'authenticated', 'aa5872-c-'||lower(v_sfx)||'@example.invalid',
            jsonb_build_object('username', 'aa5872c_'||lower(v_sfx), 'display_name', 'AA 5872 C'), now(), now());
    select i.id into v_inv_a from public.inventory i where i.owner_user_id = u_a;
    select i.id into v_inv_c from public.inventory i where i.owner_user_id = u_c;
    if v_inv_a is null or v_inv_c is null then
      raise exception 'TR_FIXTURE: Inventory não provisionado';
    end if;

    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select x.storage_container_id into v_bin  from public.create_my_storage_container(gen_random_uuid(), 'AA BIN', 'BINDER') x;
    select x.storage_container_id into v_oth  from public.create_my_storage_container(gen_random_uuid(), 'AA OTH', 'BINDER') x;
    select x.storage_container_id into v_binm from public.create_my_storage_container(gen_random_uuid(), 'AA BINM', 'BINDER') x;
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', u_c, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select x.storage_container_id into v_binc from public.create_my_storage_container(gen_random_uuid(), 'AA BINC', 'BINDER') x;
    execute 'reset role';

    -- Exemplares (dono do banco; nenhum posicionado) ---------------------------------------
    insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id) values (kv[1],  v_pt, v_inv_a, v_bin) returning id into c1;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id) values (kv[2],  v_pt, v_inv_a, v_bin) returning id into c2a;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id) values (kv[2],  v_pt, v_inv_a, v_bin) returning id into c2b;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id) values (kv[3],  v_pt, v_inv_a, v_bin) returning id into c3;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id) values (kv[4],  v_pt, v_inv_a, v_bin) returning id into c4;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id) values (kv[5],  v_pt, v_inv_a, v_bin) returning id into c5a;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id) values (kv[5],  v_pt, v_inv_a, v_bin) returning id into c5b;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id) values (kv[6],  v_pt, v_inv_a, v_oth) returning id into c6;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id) values (kv[7],  v_pt, v_inv_a, v_bin) returning id into c7;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id) values (k9alt,  v_pt, v_inv_a, v_bin) returning id into c9;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id) values (kv[10], v_pt, v_inv_a, v_bin) returning id into c10s;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id) values (k10alt, v_pt, v_inv_a, v_bin) returning id into c10a;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id) values (kv[11], v_pt, v_inv_a, v_bin) returning id into c11g;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id) values (kv[10], v_pt, v_inv_a, v_binm) returning id into m10s;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id) values (k10alt, v_pt, v_inv_a, v_binm) returning id into m10a;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id)
    select cv.id, v_pt, v_inv_c, v_binc
    from public.card_variant cv join public.card c on c.id = cv.card_id where c.card_set_id = v_set2;
    select array_agg(pc.id order by pc.id) into v_cpcs from public.physical_card pc where pc.inventory_id = v_inv_c;

    -- A: coleções, fichários (antes das alocações ⇒ bolsos reservados vazios) -------------
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select x.collection_id into cs from public.create_my_card_set_collection(gen_random_uuid(), v_set, 'AA CS', v_bin) x;
    select * into p from public.preview_my_collection_binder(cs, 3, 3, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(cs, 3, 3, 'PRINCIPAL_ONLY', p.plan_token);
    select l.layout_id into ls from public.get_my_collection_binder(cs) l;
    select x.collection_id into cf from public.create_my_free_collection(gen_random_uuid(), 'AA CF', v_bin) x;
    select x.collection_id into cg from public.create_my_free_collection(gen_random_uuid(), 'AA CG', v_bin) x;
    perform count(*) from public.attach_my_collection_to_binder(cg, ls);
    begin
      select x.collection_id into csg from public.create_my_card_set_collection(gen_random_uuid(), v_set, 'AA CSG', v_bin) x;
      perform count(*) from public.attach_my_collection_to_binder(csg, ls);
      v_csg_ok := true;
    exception when others then
      v_csg_ok := false; csg := null;
    end;
    perform public.allocate_physical_cards_to_collection(cf, array[c7]);
    perform public.allocate_physical_cards_to_collection(cg, array[c11g]);
    perform public.allocate_physical_cards_to_collection(cs, array[c1, c2a, c2b, c3, c4, c5a, c5b, c6, c9, c10s, c10a]);
    select x.collection_id into cnb from public.create_my_card_set_collection(gen_random_uuid(), v_set, 'AA CNB', v_oth) x;
    select x.collection_id into cp from public.create_my_pokedex_collection(gen_random_uuid(), 'AA CP', array['GENERATION_I'], v_oth) x;
    select x.collection_id into car from public.create_my_card_set_collection(gen_random_uuid(), v_set, 'AA CAR', v_oth) x;
    select * into p from public.preview_my_collection_binder(car, 3, 3, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(car, 3, 3, 'PRINCIPAL_ONLY', p.plan_token);
    perform count(*) from public.archive_collection(car);
    select x.collection_id into cm from public.create_my_card_set_collection(gen_random_uuid(), v_set, 'AA CM', v_binm) x;
    perform count(*) from public.set_collection_completion_policy_to_master_set(cm, array[v_std, v_alt]);
    select * into p from public.preview_my_collection_binder(cm, 3, 3, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(cm, 3, 3, 'PRINCIPAL_ONLY', p.plan_token);
    select l.layout_id into lm from public.get_my_collection_binder(cm) l;
    perform public.allocate_physical_cards_to_collection(cm, array[m10s, m10a]);
    execute 'reset role';

    -- Bolsos da proprietária por carta (leitura privilegiada).
    for i in 1 .. 11 loop
      select s.id into v_id
      from public.collection_layout_slot s
      join public.collection_layout_page pg on pg.id = s.page_id
      join public.collection_layout_slot_expected_content e on e.slot_id = s.id
      where pg.layout_id = ls and e.card_id = k[i] and (e.collection_id is null or e.collection_id = cs)
      order by pg.page_number, s.row_index, s.column_index limit 1;
      sk := sk || v_id;
    end loop;
    select s.id into s3x
    from public.collection_layout_slot s join public.collection_layout_page pg on pg.id = s.page_id
    where pg.layout_id = ls and not s.locked
      and not exists (select 1 from public.collection_layout_slot_expected_content e where e.slot_id = s.id)
      and not exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = s.id)
    order by pg.page_number, s.row_index, s.column_index limit 1;

    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.set_slot_expected_content(s3x, k[3]);                       -- 2ª reserva de K3 (proprietária)
    perform public.set_slot_lock(array[sk[4]], true);                          -- K4 travado
    perform count(*) from public.place_my_physical_card_in_slot(cs, sk[5], c5a);  -- K5 ocupado
    perform public.clear_slot_expected_content(array[sk[10]]);
    perform public.set_slot_expected_content(sk[10], k[10], k10alt);           -- K10 só variante ALT
    execute 'reset role';

    -- Reserva da convidada CG num bolso livre, pela RPC oficial (5276 grava collection_id = CG).
    select s.id into sg
    from public.collection_layout_slot s join public.collection_layout_page pg on pg.id = s.page_id
    where pg.layout_id = ls and not s.locked
      and not exists (select 1 from public.collection_layout_slot_expected_content e where e.slot_id = s.id)
      and not exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = s.id)
    order by pg.page_number, s.row_index, s.column_index limit 1;
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.set_slot_expected_content(sg, k[11], null, null, cg);
    execute 'reset role';

    -- C: Set de 501 cartas, fichário antes das alocações.
    perform set_config('request.jwt.claims', json_build_object('sub', u_c, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select x.collection_id into cc from public.create_my_card_set_collection(gen_random_uuid(), v_set2, 'AA CC', v_binc) x;
    select * into p from public.preview_my_collection_binder(cc, 3, 3, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(cc, 3, 3, 'PRINCIPAL_ONLY', p.plan_token);
    select l.layout_id into lc from public.get_my_collection_binder(cc) l;
    perform public.allocate_physical_cards_to_collection(cc, v_cpcs[1:250]);
    perform public.allocate_physical_cards_to_collection(cc, v_cpcs[251:501]);
    execute 'reset role';

    -- K9: variante desativada DEPOIS do exemplar existir (desfeito pelo TR000).
    begin
      update public.card_variant set is_active = false where id = k9alt and is_active;
      get diagnostics v_n = row_count;
      v_k9_ok := (v_n = 1);
    exception when others then
      v_k9_ok := false;
    end;

    res := res || jsonb_build_object('id','F.1','ok',
      ls is not null and lm is not null and lc is not null and s3x is not null and sg is not null
      and cardinality(sk) = 11 and array_position(sk, null) is null and sk[10] <> s3x
      and (select count(*) from public.collection_layout_slot_assignment a
           join public.collection_layout_slot s on s.id = a.slot_id
           join public.collection_layout_page pg on pg.id = s.page_id where pg.layout_id = ls) = 1
      and (select count(*) from public.collection_layout_slot_assignment a
           join public.collection_layout_slot s on s.id = a.slot_id
           join public.collection_layout_page pg on pg.id = s.page_id where pg.layout_id in (lm, lc)) = 0
      and (select count(*) from public.collection_layout_slot_expected_content e
           join public.collection_layout_slot s on s.id = e.slot_id
           join public.collection_layout_page pg on pg.id = s.page_id
           where pg.layout_id = lm and e.card_id = k[10] and e.expected_variant_type_id in (v_std, v_alt)) = 2
      and (select count(*) from public.collection_layout_slot_expected_content e
           join public.collection_layout_slot s on s.id = e.slot_id
           join public.collection_layout_page pg on pg.id = s.page_id
           where pg.layout_id = lc and (e.collection_id is null or e.collection_id = cc)) = 501
      and exists (select 1 from public.collection_layout_slot_expected_content e where e.slot_id = sg and e.collection_id = cg),
      'detail', format('fichários CS/CM/CC montados vazios (só K5 posicionado à mão); CM com reservas K10 STD e ALT; CC com 501 reservas; convidada Set: %s; K9 inativa: %s',
                       v_csg_ok, v_k9_ok));

    -- A. Segurança ---------------------------------------------------------------------
    perform set_config('request.jwt.claims', '', true);
    execute 'set local role anon';
    v_s := '{}';
    begin perform public.preview_my_binder_auto_arrange(cs); v_s := v_s || 'executou'::text;
    exception when others then v_s := v_s || sqlstate::text; end;
    begin perform public.apply_my_binder_auto_arrange(cs, 'aa1:' || repeat('0', 64)); v_s := v_s || 'executou'::text;
    exception when others then v_s := v_s || sqlstate::text; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','A.1','ok', v_s[1] = '42501', 'detail','anon prévia: '||coalesce(v_s[1],'?'));
    res := res || jsonb_build_object('id','A.2','ok', v_s[2] = '42501', 'detail','anon aplicação: '||coalesce(v_s[2],'?'));

    execute 'set local role authenticated';
    v_s := '{}';
    begin perform public.preview_my_binder_auto_arrange(cs); v_s := v_s || 'executou'::text;
    exception when others then v_s := v_s || sqlstate::text; end;
    begin perform public.apply_my_binder_auto_arrange(cs, 'aa1:' || repeat('0', 64)); v_s := v_s || 'executou'::text;
    exception when others then v_s := v_s || sqlstate::text; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','A.3','ok', v_s[1] = '28000' and v_s[2] = '28000',
      'detail','sem identidade: prévia '||coalesce(v_s[1],'?')||', aplicação '||coalesce(v_s[2],'?'));

    -- Token legítimo de A (necessário a A.5).
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    j := public.preview_my_binder_auto_arrange(cs);
    execute 'reset role';
    t_cs := j ->> 'plan_token';

    select count(*) into v_n from public.collection_layout_slot_assignment;
    select count(*) into v_e0 from public.binder_activity_event;
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    v_s := '{}';
    begin perform public.preview_my_binder_auto_arrange(cs); v_s := v_s || 'executou'::text;
    exception when others then v_s := v_s || sqlerrm::text; end;
    begin perform public.apply_my_binder_auto_arrange(cs, t_cs); v_s := v_s || 'executou'::text;
    exception when others then v_s := v_s || sqlerrm::text; end;
    begin perform count(*) from public.binder_auto_arrange_plan(cs, ls, v_bin); v_s := v_s || 'executou'::text;
    exception when others then v_s := v_s || sqlstate::text; end;
    execute 'reset role';
    v_ok := (select count(*) from public.collection_layout_slot_assignment) = v_n
            and (select count(*) from public.binder_activity_event) = v_e0;
    v_zero_ok := v_zero_ok and v_ok;
    res := res || jsonb_build_object('id','A.4','ok', v_s[1] = 'COLLECTION_NOT_FOUND',
      'detail','B prévia da coleção de A: '||coalesce(v_s[1],'?'));
    res := res || jsonb_build_object('id','A.5','ok', v_s[2] = 'COLLECTION_NOT_FOUND' and v_ok and t_cs is not null,
      'detail','B aplica o token de A: '||coalesce(v_s[2],'?')||'; zero escrita: '||v_ok);
    res := res || jsonb_build_object('id','A.6','ok', v_s[3] = '42501',
      'detail','authenticated chama a função interna 5342: '||coalesce(v_s[3],'?'));

    -- T. Tipos e estados -----------------------------------------------------------------
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    v_s := '{}';
    begin perform public.preview_my_binder_auto_arrange(cp);  v_s := v_s || 'executou'::text; exception when others then v_s := v_s || (sqlstate||' '||sqlerrm)::text; end;
    begin perform public.preview_my_binder_auto_arrange(cf);  v_s := v_s || 'executou'::text; exception when others then v_s := v_s || (sqlstate||' '||sqlerrm)::text; end;
    if v_csg_ok then
      begin perform public.preview_my_binder_auto_arrange(csg); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || (sqlstate||' '||sqlerrm)::text; end;
    else
      v_s := v_s || 'fixture: convidada Set não associada'::text;
    end if;
    begin perform public.preview_my_binder_auto_arrange(cnb); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || (sqlstate||' '||sqlerrm)::text; end;
    begin perform public.preview_my_binder_auto_arrange(car); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || (sqlstate||' '||sqlerrm)::text; end;
    begin perform public.preview_my_binder_auto_arrange(null); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || (sqlstate||' '||sqlerrm)::text; end;
    begin perform public.apply_my_binder_auto_arrange(cs, 'v1:abc'); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || (sqlstate||' '||sqlerrm)::text; end;
    begin perform public.apply_my_binder_auto_arrange(cs, null); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || (sqlstate||' '||sqlerrm)::text; end;
    begin perform public.apply_my_binder_auto_arrange(cf, 'aa1:' || repeat('0', 64)); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || (sqlstate||' '||sqlerrm)::text; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','T.1','ok', v_s[1] = '22023 AUTO_ARRANGE_UNSUPPORTED_COLLECTION', 'detail','Pokédex: '||coalesce(v_s[1],'?'));
    res := res || jsonb_build_object('id','T.2','ok', v_s[2] = '22023 AUTO_ARRANGE_UNSUPPORTED_COLLECTION'
                                                     and v_s[9] = '22023 AUTO_ARRANGE_UNSUPPORTED_COLLECTION',
      'detail','Livre: prévia '||coalesce(v_s[2],'?')||'; aplicação '||coalesce(v_s[9],'?'));
    res := res || jsonb_build_object('id','T.3','ok', v_csg_ok and v_s[3] = '42501 AUTO_ARRANGE_NOT_BINDER_OWNER', 'detail','Set convidada: '||coalesce(v_s[3],'?'));
    res := res || jsonb_build_object('id','T.4','ok', v_s[4] = 'P0002 BINDER_NOT_FOUND', 'detail','Set sem fichário: '||coalesce(v_s[4],'?'));
    res := res || jsonb_build_object('id','T.5','ok', v_s[5] = '55000 COLLECTION_ARCHIVED', 'detail','arquivada: '||coalesce(v_s[5],'?'));
    res := res || jsonb_build_object('id','T.6','ok',
      v_s[6] = '22023 INVALID_ARGUMENT' and v_s[7] = '22023 INVALID_ARGUMENT' and v_s[8] = '22023 INVALID_ARGUMENT',
      'detail','nulo/token malformado: '||coalesce(v_s[6],'?')||' | '||coalesce(v_s[7],'?')||' | '||coalesce(v_s[8],'?'));

    -- P/G/M. Plano -----------------------------------------------------------------------
    res := res || jsonb_build_object('id','P.1','ok',
      j ->> 'status' = 'READY' and (j ->> 'insert_count')::int = 2 and (j ->> 'limit')::int = 500
      and t_cs ~ '^aa1:[0-9a-f]{64}$'
      and (select array_agg((x ->> 'slot_id') || '|' || (x ->> 'physical_card_id') order by (x ->> 'ord')::int)
           from jsonb_array_elements(j -> 'items') x)
          = array[sk[1]::text || '|' || c1::text, sk[10]::text || '|' || c10a::text],
      'detail','prévia CS: '||coalesce(j ->> 'status','?')||' '||coalesce(j ->> 'insert_count','?')||' itens');
    res := res || jsonb_build_object('id','P.2','ok',
      v_k9_ok and j -> 'excluded_cards'
        = '{"COMPETING_CANDIDATES":2,"MULTIPLE_DESTINATIONS":1,"NO_COMPATIBLE_RESERVATION":3,"INACTIVE_VARIANT":1}'::jsonb,
      'detail','exclusões: '||coalesce((j -> 'excluded_cards')::text,'?'));
    res := res || jsonb_build_object('id','P.3','ok',
      j -> 'unfilled_slots' = '{"COMPETING_CANDIDATES":1,"MULTIPLE_DESTINATIONS":2,"NO_CANDIDATE":4,"INACTIVE_VARIANT":1}'::jsonb
      and (j ->> 'unfilled_count')::int = 8 and v_k9_ok,
      'detail','bolsos vazios: '||coalesce((j -> 'unfilled_slots')::text,'?'));
    res := res || jsonb_build_object('id','P.4','ok',
      not exists (select 1 from public.binder_auto_arrange_plan(cs, ls, v_bin) h
                  where h.slot_id in (sk[4], sk[5], sg)
                     or h.physical_card_id in (c5a, c6, c7, c11g)),
      'detail','bolso travado (K4), ocupado (K5), da convidada; exemplares posicionado/fora do local/outra coleção/da convidada: ausentes do plano');
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    j2 := public.preview_my_binder_auto_arrange(cs);
    execute 'reset role';
    res := res || jsonb_build_object('id','P.5','ok',
      j2 = j and (select count(*) from public.collection_layout_slot_assignment) = v_n
      and (select count(*) from public.binder_activity_event) = v_e0,
      'detail','duas prévias idênticas (mesmo token) e nenhuma escrita');

    res := res || jsonb_build_object('id','G.1','ok',
      exists (select 1 from public.collection_layout_slot_expected_content e
              where e.slot_id = sk[1] and e.card_variant_id is null and e.expected_variant_type_id is null)
      and exists (select 1 from public.binder_auto_arrange_plan(cs, ls, v_bin) h
                  where h.item_kind = 'INSERT' and h.slot_id = sk[1] and h.physical_card_id = c1),
      'detail','reserva só por carta (Set) aceita a cópia STD');
    res := res || jsonb_build_object('id','G.3','ok',
      exists (select 1 from public.collection_layout_slot_expected_content e where e.slot_id = sk[10] and e.card_variant_id = k10alt)
      and exists (select 1 from public.binder_auto_arrange_plan(cs, ls, v_bin) h
                  where h.item_kind = 'INSERT' and h.slot_id = sk[10] and h.physical_card_id = c10a)
      and exists (select 1 from public.binder_auto_arrange_plan(cs, ls, v_bin) h
                  where h.item_kind = 'EXCLUDED_CARD' and h.physical_card_id = c10s and h.reason = 'NO_COMPATIBLE_RESERVATION'),
      'detail','reserva por variante exata: ALT entra, STD da mesma carta fica fora');
    res := res || jsonb_build_object('id','M.1','ok',
      (select count(*) = count(distinct h.slot_id) and count(*) = count(distinct h.physical_card_id)
       from public.binder_auto_arrange_plan(cs, ls, v_bin) h where h.item_kind = 'INSERT')
      and (select count(*) = 1 from public.binder_auto_arrange_plan(cs, ls, v_bin) h where h.item_kind = 'HEADER'),
      'detail','INSERT sem bolso nem exemplar repetido; um HEADER');
    res := res || jsonb_build_object('id','M.2','ok',
      (select count(*) from public.binder_auto_arrange_plan(cs, ls, v_bin) h
       where h.item_kind = 'EXCLUDED_CARD' and h.physical_card_id in (c2a, c2b) and h.reason = 'COMPETING_CANDIDATES') = 2
      and exists (select 1 from public.binder_auto_arrange_plan(cs, ls, v_bin) h
                  where h.item_kind = 'UNFILLED_SLOT' and h.slot_id = sk[2] and h.reason = 'COMPETING_CANDIDATES'),
      'detail','duas cópias para um bolso: nenhuma escolhida');
    res := res || jsonb_build_object('id','M.3','ok',
      exists (select 1 from public.binder_auto_arrange_plan(cs, ls, v_bin) h
              where h.item_kind = 'EXCLUDED_CARD' and h.physical_card_id = c3 and h.reason = 'MULTIPLE_DESTINATIONS')
      and (select count(*) from public.binder_auto_arrange_plan(cs, ls, v_bin) h
           where h.item_kind = 'UNFILLED_SLOT' and h.slot_id in (sk[3], s3x) and h.reason = 'MULTIPLE_DESTINATIONS') = 2,
      'detail','uma cópia para dois bolsos: nenhum escolhido');
    res := res || jsonb_build_object('id','M.4','ok',
      v_k9_ok
      and exists (select 1 from public.binder_auto_arrange_plan(cs, ls, v_bin) h
                  where h.item_kind = 'EXCLUDED_CARD' and h.physical_card_id = c9 and h.reason = 'INACTIVE_VARIANT')
      and exists (select 1 from public.binder_auto_arrange_plan(cs, ls, v_bin) h
                  where h.item_kind = 'UNFILLED_SLOT' and h.slot_id = sk[9] and h.reason = 'INACTIVE_VARIANT'),
      'detail','variante inativa: exemplar e bolso marcados INACTIVE_VARIANT (fixture K9: '||v_k9_ok||')');
    res := res || jsonb_build_object('id','M.5','ok',
      (select count(*) from public.binder_auto_arrange_plan(cs, ls, v_bin) h
       where h.item_kind = 'UNFILLED_SLOT' and h.slot_id in (sk[6], sk[7], sk[8], sk[11]) and h.reason = 'NO_CANDIDATE') = 4,
      'detail','K6 (fora do local), K7 (outra coleção), K8 (sem cópia), K11 (cópia da convidada): bolsos NO_CANDIDATE');

    -- C. PLAN_CHANGED (cada caso em sub-bloco desfeito) ------------------------------------
    -- v1.5: toda leitura de controle (plano, posições, histórico, reservas, alocações,
    -- exemplares) roda como dono do banco (reset role); só a alteração do cenário e a
    -- chamada da 5344 rodam como authenticated com a identidade de A.
    for i in 1 .. 6 loop
      v_err := null; v_st := null;
      begin
        -- Pré-condição: o token da prévia ainda é o plano vigente (antes da alteração).
        v_ok := t_cs is not null
                and (select max(h.plan_token) from public.binder_auto_arrange_plan(cs, ls, v_bin) h) = t_cs;
        perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
        execute 'set local role authenticated';
        if i = 1 then
          perform public.set_physical_cards_storage(v_oth, array[c1], false);
        elsif i = 2 then
          perform count(*) from public.place_my_physical_card_in_slot(cs, sk[1], c1);
        elsif i = 3 then
          perform public.clear_slot_expected_content(array[sk[1]]);
        elsif i = 4 then
          execute 'reset role';
          update public.card_variant set is_active = false where id = k10alt;   -- não padrão, no plano (c10a)
          execute 'set local role authenticated';
        elsif i = 5 then
          perform public.set_slot_lock(array[sk[1]], true);
        else
          execute 'reset role';
          insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id)
          values (kv[1], v_pt, v_inv_a, v_bin) returning id into v_id;
          execute 'set local role authenticated';
          perform public.allocate_physical_cards_to_collection(cs, array[v_id]);
        end if;
        -- Estado depois da alteração e antes da aplicação (papel autorizado).
        execute 'reset role';
        select count(*) into v_n from public.collection_layout_slot_assignment;
        select count(*) into v_e0 from public.binder_activity_event where event_type = 'CARDS_AUTO_ARRANGED';
        select md5(string_agg(x, ',' order by x)) into h_before from (
          select 'E|'||e.slot_id||'|'||e.card_id||'|'||coalesce(e.card_variant_id::text,'-')||'|'||coalesce(e.expected_variant_type_id::text,'-')||'|'||coalesce(e.collection_id::text,'-') as x
          from public.collection_layout_slot_expected_content e
          join public.collection_layout_slot s on s.id = e.slot_id join public.collection_layout_page pg on pg.id = s.page_id
          where pg.layout_id = ls
          union all select 'A|'||ca.physical_card_id||'|'||ca.collection_id from public.collection_allocation ca
          join public.physical_card pc on pc.id = ca.physical_card_id where pc.inventory_id = v_inv_a
          union all select 'P|'||pc.id||'|'||coalesce(pc.storage_container_id::text,'-')||'|'||pc.card_variant_id||'|'||pc.inventory_id
          from public.physical_card pc where pc.inventory_id = v_inv_a
          union all select 'S|'||a.slot_id||'|'||a.physical_card_id from public.collection_layout_slot_assignment a) z;
        -- Operação testada: authenticated, identidade de A, token anterior.
        perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
        execute 'set local role authenticated';
        begin
          perform public.apply_my_binder_auto_arrange(cs, t_cs);
        exception when others then v_err := sqlerrm; v_st := sqlstate; end;
        -- Estado depois da aplicação (papel autorizado).
        execute 'reset role';
        select md5(string_agg(x, ',' order by x)) into h_after from (
          select 'E|'||e.slot_id||'|'||e.card_id||'|'||coalesce(e.card_variant_id::text,'-')||'|'||coalesce(e.expected_variant_type_id::text,'-')||'|'||coalesce(e.collection_id::text,'-') as x
          from public.collection_layout_slot_expected_content e
          join public.collection_layout_slot s on s.id = e.slot_id join public.collection_layout_page pg on pg.id = s.page_id
          where pg.layout_id = ls
          union all select 'A|'||ca.physical_card_id||'|'||ca.collection_id from public.collection_allocation ca
          join public.physical_card pc on pc.id = ca.physical_card_id where pc.inventory_id = v_inv_a
          union all select 'P|'||pc.id||'|'||coalesce(pc.storage_container_id::text,'-')||'|'||pc.card_variant_id||'|'||pc.inventory_id
          from public.physical_card pc where pc.inventory_id = v_inv_a
          union all select 'S|'||a.slot_id||'|'||a.physical_card_id from public.collection_layout_slot_assignment a) z;
        v_ok := v_ok and v_st = '40001' and v_err = 'AUTO_ARRANGE_PLAN_CHANGED'
                and (select count(*) from public.collection_layout_slot_assignment) = v_n
                and (select count(*) from public.binder_activity_event where event_type = 'CARDS_AUTO_ARRANGED') = v_e0
                and h_before is not null and h_before = h_after;
        v_zero_ok := v_zero_ok and v_ok;
        res := res || jsonb_build_object('id','C.'||i,'ok', v_ok,
          'detail', (array['exemplar movido para outro local','bolso ocupado depois da prévia','reserva removida',
                           'variante (não padrão) do par K10 desativada','bolso travado','nova cópia cria ambiguidade'])[i]
                    ||' → '||coalesce(v_st,'sem erro')||' '||coalesce(v_err,'')
                    ||'; zero escrita; reservas/alocações/exemplares/posições preservados: '||coalesce((h_before = h_after)::text,'?'));
        raise exception 'TR_SUB';
      exception when others then
        if sqlerrm <> 'TR_SUB' then
          res := res || jsonb_build_object('id','C.'||i,'ok', false, 'detail','fixture do caso falhou: '||sqlstate||' '||sqlerrm);
        end if;
      end;
      execute 'reset role';
    end loop;

    -- D/H. Aplicação ---------------------------------------------------------------------
    select md5(string_agg(x, ',' order by x)) into h_before from (
      select 'E|'||e.slot_id||'|'||e.card_id||'|'||coalesce(e.card_variant_id::text,'-')||'|'||coalesce(e.expected_variant_type_id::text,'-')||'|'||coalesce(e.collection_id::text,'-') as x
      from public.collection_layout_slot_expected_content e
      join public.collection_layout_slot s on s.id = e.slot_id join public.collection_layout_page pg on pg.id = s.page_id
      where pg.layout_id = ls
      union all select 'L|'||s.id||'|'||s.locked from public.collection_layout_slot s
      join public.collection_layout_page pg on pg.id = s.page_id where pg.layout_id = ls
      union all select 'A|'||ca.physical_card_id||'|'||ca.collection_id from public.collection_allocation ca
      join public.physical_card pc on pc.id = ca.physical_card_id where pc.inventory_id = v_inv_a
      union all select 'P|'||pc.id||'|'||coalesce(pc.storage_container_id::text,'-')||'|'||pc.card_variant_id||'|'||pc.inventory_id
      from public.physical_card pc where pc.inventory_id = v_inv_a
      union all select 'S|'||a.slot_id||'|'||a.physical_card_id from public.collection_layout_slot_assignment a
      join public.physical_card pc on pc.id = a.physical_card_id where pc.inventory_id = v_inv_a) z;
    select count(*) into v_n from public.collection_layout_slot_assignment;
    select count(*) into v_e0 from public.binder_activity_event where event_type = 'CARDS_AUTO_ARRANGED';

    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    j := public.apply_my_binder_auto_arrange(cs, t_cs);
    execute 'reset role';
    res := res || jsonb_build_object('id','D.1','ok',
      j ->> 'status' = 'APPLIED' and (j ->> 'inserted')::int = 2 and (j ->> 'event_id') is not null
      and exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = sk[1] and a.physical_card_id = c1)
      and exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = sk[10] and a.physical_card_id = c10a)
      and (select count(*) from public.collection_layout_slot_assignment) = v_n + 2,
      'detail','aplicação CS: '||coalesce(j::text,'?'));
    select md5(string_agg(x, ',' order by x)) into h_after from (
      select 'E|'||e.slot_id||'|'||e.card_id||'|'||coalesce(e.card_variant_id::text,'-')||'|'||coalesce(e.expected_variant_type_id::text,'-')||'|'||coalesce(e.collection_id::text,'-') as x
      from public.collection_layout_slot_expected_content e
      join public.collection_layout_slot s on s.id = e.slot_id join public.collection_layout_page pg on pg.id = s.page_id
      where pg.layout_id = ls
      union all select 'L|'||s.id||'|'||s.locked from public.collection_layout_slot s
      join public.collection_layout_page pg on pg.id = s.page_id where pg.layout_id = ls
      union all select 'A|'||ca.physical_card_id||'|'||ca.collection_id from public.collection_allocation ca
      join public.physical_card pc on pc.id = ca.physical_card_id where pc.inventory_id = v_inv_a
      union all select 'P|'||pc.id||'|'||coalesce(pc.storage_container_id::text,'-')||'|'||pc.card_variant_id||'|'||pc.inventory_id
      from public.physical_card pc where pc.inventory_id = v_inv_a
      union all select 'S|'||a.slot_id||'|'||a.physical_card_id from public.collection_layout_slot_assignment a
      join public.physical_card pc on pc.id = a.physical_card_id where pc.inventory_id = v_inv_a
        and not (a.slot_id = sk[1] and a.physical_card_id = c1) and not (a.slot_id = sk[10] and a.physical_card_id = c10a)) z;
    res := res || jsonb_build_object('id','D.2','ok', h_before = h_after
      and exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = sk[5] and a.physical_card_id = c5a),
      'detail','reservas, travas, alocações, locais, exemplares e posições anteriores idênticos (K5 intocado)');

    select count(*) into v_e1 from public.binder_activity_event where event_type = 'CARDS_AUTO_ARRANGED';
    res := res || jsonb_build_object('id','H.1','ok',
      v_e1 = v_e0 + 1
      and exists (select 1 from public.binder_activity_event e
                  where e.id = (j ->> 'event_id')::bigint and e.layout_key = ls and e.owner_user_id = u_a
                    and e.actor_user_id = u_a and e.event_type = 'CARDS_AUTO_ARRANGED' and e.source = 'FICHARIO'
                    and e.collection_id = cs and e.summary ->> 'plan_token' = t_cs and (e.summary ->> 'inserted')::int = 2)
      and (select array_agg(i.item_kind || '|' || i.effect || '|' || i.card_id || '|' || i.to_page || '|' || i.to_row || '|' || i.to_col
                            order by i.ordinal)
           from public.binder_activity_item i where i.event_id = (j ->> 'event_id')::bigint)
          = (select array_agg('CARD|PLACED|' || e.card_id || '|' || pg.page_number || '|' || s.row_index || '|' || s.column_index
                              order by pg.page_number, s.row_index, s.column_index)
             from public.collection_layout_slot s join public.collection_layout_page pg on pg.id = s.page_id
             join public.collection_layout_slot_expected_content e on e.slot_id = s.id
             where s.id in (sk[1], sk[10])),
      'detail','um evento CARDS_AUTO_ARRANGED (FICHARIO, CS, token, 2) com 2 itens CARD/PLACED nas posições de destino');

    -- I. Idempotência e plano vazio ----------------------------------------------------------
    select count(*) into v_n from public.collection_layout_slot_assignment;
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    j2 := public.apply_my_binder_auto_arrange(cs, t_cs);
    execute 'reset role';
    v_ok := (select count(*) from public.collection_layout_slot_assignment) = v_n
            and (select count(*) from public.binder_activity_event where event_type = 'CARDS_AUTO_ARRANGED') = v_e1;
    v_zero_ok := v_zero_ok and v_ok;
    res := res || jsonb_build_object('id','I.1','ok',
      j2 ->> 'status' = 'ALREADY_APPLIED' and (j2 ->> 'inserted')::int = 0 and j2 ->> 'event_id' = j ->> 'event_id' and v_ok,
      'detail','repetição da confirmação: '||coalesce(j2::text,'?'));

    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    j2 := public.preview_my_binder_auto_arrange(cs);
    t_e := j2 ->> 'plan_token';
    j := public.apply_my_binder_auto_arrange(cs, t_e);
    v_err := null; v_st := null;
    begin perform public.apply_my_binder_auto_arrange(cs, 'aa1:' || repeat('f', 64));
    exception when others then v_err := sqlerrm; v_st := sqlstate; end;
    execute 'reset role';
    v_ok := (select count(*) from public.collection_layout_slot_assignment) = v_n
            and (select count(*) from public.binder_activity_event where event_type = 'CARDS_AUTO_ARRANGED') = v_e1;
    v_zero_ok := v_zero_ok and v_ok;
    res := res || jsonb_build_object('id','I.2','ok',
      j2 ->> 'status' = 'EMPTY' and (j2 ->> 'insert_count')::int = 0 and j2 -> 'items' = '[]'::jsonb
      and j ->> 'status' = 'NOTHING_TO_DO' and v_ok,
      'detail','depois da aplicação: prévia '||coalesce(j2 ->> 'status','?')||'; confirmação '||coalesce(j ->> 'status','?')||'; sem evento');
    res := res || jsonb_build_object('id','I.3','ok', v_st = '40001' and v_err = 'AUTO_ARRANGE_PLAN_CHANGED' and v_ok,
      'detail','token bem formado que nunca foi emitido: '||coalesce(v_st,'sem erro')||' '||coalesce(v_err,''));

    -- G.2 Master Set (carta + acabamento), aplicado.
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    j2 := public.preview_my_binder_auto_arrange(cm);
    t_cm := j2 ->> 'plan_token';
    j := public.apply_my_binder_auto_arrange(cm, t_cm);
    execute 'reset role';
    res := res || jsonb_build_object('id','G.2','ok',
      j2 ->> 'status' = 'READY' and (j2 ->> 'insert_count')::int = 2 and j ->> 'status' = 'APPLIED'
      and (select count(*) from public.collection_layout_slot_assignment a
           join public.collection_layout_slot_expected_content e on e.slot_id = a.slot_id
           join public.physical_card pc on pc.id = a.physical_card_id
           join public.card_variant cv on cv.id = pc.card_variant_id
           where a.physical_card_id in (m10s, m10a) and e.card_id = k[10] and e.expected_variant_type_id = cv.variant_type_id) = 2,
      'detail','Master Set: STD no bolso STD e ALT no bolso ALT ('||coalesce(j2 ->> 'insert_count','?')||' → '||coalesce(j ->> 'status','?')||')');

    -- I.4 Mesmo conjunto de pares reaparece depois de alterações legítimas (época do token).
    select count(*) into v_e0 from public.binder_activity_event where event_type = 'CARDS_AUTO_ARRANGED';
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.remove_slot_assignment(array(
      select a.slot_id from public.collection_layout_slot_assignment a where a.physical_card_id in (m10s, m10a)));
    j := public.apply_my_binder_auto_arrange(cm, t_cm);            -- confirmação antiga repetida
    j2 := public.preview_my_binder_auto_arrange(cm);               -- nova intenção
    t_cm2 := j2 ->> 'plan_token';
    execute 'reset role';
    v_ok := (select count(*) from public.collection_layout_slot_assignment where physical_card_id in (m10s, m10a)) = 0
            and (select count(*) from public.binder_activity_event where event_type = 'CARDS_AUTO_ARRANGED') = v_e0;
    v_zero_ok := v_zero_ok and v_ok;
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    j2 := public.apply_my_binder_auto_arrange(cm, t_cm2);
    execute 'reset role';
    res := res || jsonb_build_object('id','I.4','ok',
      j ->> 'status' = 'ALREADY_APPLIED' and v_ok and t_cm2 is distinct from t_cm
      and j2 ->> 'status' = 'APPLIED' and (j2 ->> 'inserted')::int = 2,
      'detail','pares de CM reaparecem: token antigo → '||coalesce(j ->> 'status','?')
               ||' sem escrita; nova prévia (token novo: '||(t_cm2 is distinct from t_cm)||') → '||coalesce(j2 ->> 'status','?'));

    -- I.5 Limpeza do histórico (5270) com os mesmos pares de volta: nenhum token antigo reautoriza.
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.remove_slot_assignment(array(
      select a.slot_id from public.collection_layout_slot_assignment a where a.physical_card_id in (m10s, m10a)));
    execute 'reset role';
    -- 5270 não tem EXECUTE para clientes (O2): chamada pelo dono do banco com a identidade de A.
    perform public.purge_my_binder_activity(lm, lm);
    select count(*) into v_n from public.collection_layout_slot_assignment;
    select count(*) into v_m from public.binder_activity_event where layout_key = lm;   -- deve ser 0
    select count(*) into v_e0 from public.binder_activity_event where event_type = 'CARDS_AUTO_ARRANGED';
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    v_s2 := '{}';
    begin perform public.apply_my_binder_auto_arrange(cm, t_cm);  v_s2 := v_s2 || 'executou'::text;
    exception when others then v_s2 := v_s2 || (sqlstate||' '||sqlerrm)::text; end;
    begin perform public.apply_my_binder_auto_arrange(cm, t_cm2); v_s2 := v_s2 || 'executou'::text;
    exception when others then v_s2 := v_s2 || (sqlstate||' '||sqlerrm)::text; end;
    execute 'reset role';
    v_ok := (select count(*) from public.collection_layout_slot_assignment) = v_n
            and (select count(*) from public.binder_activity_event where event_type = 'CARDS_AUTO_ARRANGED') = v_e0;
    v_zero_ok := v_zero_ok and v_ok;
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    j2 := public.preview_my_binder_auto_arrange(cm);
    t_cm3 := j2 ->> 'plan_token';
    j := public.apply_my_binder_auto_arrange(cm, t_cm3);
    execute 'reset role';
    res := res || jsonb_build_object('id','I.5','ok',
      v_m = 0                                    -- eventos do fichário de CM apagados pela limpeza
      and v_s2[1] = '40001 AUTO_ARRANGE_PLAN_CHANGED' and v_s2[2] = '40001 AUTO_ARRANGE_PLAN_CHANGED' and v_ok
      and t_cm3 is distinct from t_cm and t_cm3 is distinct from t_cm2
      and j ->> 'status' = 'APPLIED' and (j ->> 'inserted')::int = 2,
      'detail','após limpeza: token original '||coalesce(v_s2[1],'?')||'; token pós-I.4 '||coalesce(v_s2[2],'?')
               ||'; zero escrita: '||v_ok||'; nova prévia → '||coalesce(j ->> 'status','?'));

    -- L. Limite e volume (usuário C) ----------------------------------------------------------
    select count(*) into v_n from public.collection_layout_slot_assignment;
    select count(*) into v_m from public.binder_activity_event where event_type = 'CARDS_AUTO_ARRANGED';
    perform set_config('request.jwt.claims', json_build_object('sub', u_c, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    v_t0 := clock_timestamp();
    j := public.preview_my_binder_auto_arrange(cc);
    v_ms_prev := extract(epoch from clock_timestamp() - v_t0) * 1000;
    t_c := j ->> 'plan_token';
    v_err := null; v_st := null;
    begin perform public.apply_my_binder_auto_arrange(cc, t_c);
    exception when others then v_err := sqlerrm; v_st := sqlstate; end;
    execute 'reset role';
    v_ok := (select count(*) from public.collection_layout_slot_assignment) = v_n
            and (select count(*) from public.binder_activity_event where event_type = 'CARDS_AUTO_ARRANGED') = v_m;
    v_zero_ok := v_zero_ok and v_ok;
    res := res || jsonb_build_object('id','L.1','ok',
      j ->> 'status' = 'LIMIT_EXCEEDED' and (j ->> 'insert_count')::int = 501 and j -> 'items' = '[]'::jsonb and t_c is not null,
      'detail','prévia com 501 inserções: '||coalesce(j ->> 'status','?')||' '||coalesce(j ->> 'insert_count','?'));
    res := res || jsonb_build_object('id','L.2','ok', v_st = '54000' and v_err = 'AUTO_ARRANGE_LIMIT_EXCEEDED' and v_ok,
      'detail','confirmação com 501: '||coalesce(v_st,'sem erro')||' '||coalesce(v_err,'')||'; zero escrita: '||v_ok);

    select s.id into slc
    from public.collection_layout_slot s join public.collection_layout_page pg on pg.id = s.page_id
    join public.collection_layout_slot_expected_content e on e.slot_id = s.id
    where pg.layout_id = lc order by pg.page_number, s.row_index, s.column_index limit 1;
    perform set_config('request.jwt.claims', json_build_object('sub', u_c, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.set_slot_lock(array[slc], true);
    j2 := public.preview_my_binder_auto_arrange(cc);
    v_t0 := clock_timestamp();
    j := public.apply_my_binder_auto_arrange(cc, j2 ->> 'plan_token');
    v_ms_apply := extract(epoch from clock_timestamp() - v_t0) * 1000;
    execute 'reset role';
    res := res || jsonb_build_object('id','L.3','ok',
      j2 ->> 'status' = 'READY' and (j2 ->> 'insert_count')::int = 500 and jsonb_array_length(j2 -> 'items') = 500
      and j ->> 'status' = 'APPLIED' and (j ->> 'inserted')::int = 500
      and (select count(*) from public.binder_activity_item i where i.event_id = (j ->> 'event_id')::bigint and i.effect = 'PLACED') = 500
      and (select count(*) from public.collection_layout_slot_assignment a
           join public.collection_layout_slot s on s.id = a.slot_id
           join public.collection_layout_page pg on pg.id = s.page_id where pg.layout_id = lc) = 500,
      'detail','500 inserções: '||coalesce(j ->> 'status','?')||', evento com 500 itens');
    res := res || jsonb_build_object('id','P.6','ok', v_ms_prev < 3000 and v_ms_apply < 15000,
      'detail', format('prévia 501 candidatos × 504 bolsos: %s ms (< 3000); aplicação de 500 com histórico: %s ms (< 15000)',
                       round(v_ms_prev), round(v_ms_apply)));

    select count(*) into v_e1 from public.binder_activity_event where event_type = 'CARDS_AUTO_ARRANGED';
    res := res || jsonb_build_object('id','H.2','ok', v_e1 = v_aa0 + 3,
      'detail', format('eventos CARDS_AUTO_ARRANGED na transação: %s (esperado 3: CS, CM pós-limpeza em I.5, CC-500 — os 2 eventos de CM anteriores saem na limpeza); prévias, vazio, repetição, limite e divergências não gravam', v_e1 - v_aa0));

    res := res || jsonb_build_object('id','R.1','ok', v_zero_ok,
      'detail','todos os caminhos de erro/sem ação (A.5, C.1–C.6, I.1–I.5, L.2) sem escrita de posição nem evento');

    raise exception 'TR000' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'TR000' then
      res := res || jsonb_build_object('id','X.1','ok', false, 'detail','erro inesperado: '||sqlstate||' '||sqlerrm);
    end if;
  end;

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  res := res || jsonb_build_object('id','9.1','ok',
    array[(select count(*) from auth.users), (select count(*) from public.collection),
          (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
          (select count(*) from public.storage_container), (select count(*) from public.collection_layout),
          (select count(*) from public.collection_layout_slot_assignment),
          (select count(*) from public.collection_layout_slot_expected_content),
          (select count(*) from public.collection_layout_guest), (select count(*) from public.card),
          (select count(*) from public.card_variant where is_active),
          (select count(*) from public.binder_activity_event),
          (select count(*) from public.binder_activity_coverage)] = b_counts
    and current_user = session_user,
    'detail','resíduo zero (usuários, coleções, alocações, exemplares, locais, fichários, posições, reservas, convidadas, cartas, variantes ativas, eventos) e papel restaurado');

  for r in select * from jsonb_array_elements(res) loop
    n := n + 1;
    if coalesce((r->>'ok')::boolean, false) then passes := passes + 1; end if;
    seq := n; check_id := r->>'id';
    status := case when coalesce((r->>'ok')::boolean, false) then 'PASS' else 'FAIL' end;
    detail := r->>'detail';
    return next;
  end loop;

  v_ok_ids := (select count(*) = cardinality(v_expected)
                 from (select e.value->>'id' as id, count(*) as c
                         from jsonb_array_elements(res) e group by 1) g
                where g.id = any(v_expected) and g.c = 1)
              and not exists (select 1 from jsonb_array_elements(res) e where e.value->>'id' = 'X.1')
              and not exists (select 1 from jsonb_array_elements(res) e where not (e.value->>'id' = any(v_expected)));
  seq := 99; check_id := 'GATE';
  status := case when v_ok_ids and passes = n then 'PASS' else 'FAIL' end;
  detail := format('%s/%s PASS; ids esperados %s, todos presentes uma vez: %s', passes, n, cardinality(v_expected), v_ok_ids);
  return next;
end;
$fn$;

select * from pg_temp.tr_5872_validate();
