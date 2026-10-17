/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5830 - Validate Minhas coleções (5166–5170)
Versão......: 1.1 (2026-10-17: identidades de teste efêmeras criadas e
              desfeitas no próprio statement; R3 só "1 de cada")
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-17 — GATE PASS 35/35,
              resíduo zero (Set de fixture FUT2020, 5 cartas)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-17 (MY-COLLECTIONS-FOUNDATION-01)

Mesmo protocolo de 5827/5829: tudo num único statement; fixtures,
trocas de papel e chamadas ficam num bloco que termina SEMPRE com a
exceção sentinela LI000 — o savepoint desfaz tudo (exemplares, locais,
coleções, alocações, registro de idempotência, gatilho de falha).
Resultados sobrevivem em variáveis. 9.1 prova resíduo zero.

Identidades (condição de Fabrício, 2026-10-17): o harness NÃO usa
nenhum usuário real. Cria dois usuários de teste efêmeros (A e B) em
auth.users dentro do bloco revertido — os gatilhos existentes criam o
perfil e o Inventory deles — e tudo é desfeito pela sentinela. Nenhum
dado real (usuários, acervo, coleções, locais) é lido para escrita,
alterado ou excluído. 9.1 prova que auth.users, user_profile, inventory,
physical_card, storage_container, collection, collection_allocation e
collection_creation_request voltaram exatamente à linha de base.

Pré-requisitos:
  - 5166 → 5167 → 5168 → 5169 → 5170 aplicadas.
  - O Set de teste é escolhido automaticamente: o menor Set com ≥ 2
    cartas ativas com variante padrão (só leitura de catálogo).

Execução:
  SELECT * FROM pg_temp.rc_5830_validate();

Cobertura:
  0.x  estrutura, RLS, privilégios (B7)
  1.x  anon; 2.x sem identidade
  3.1  falha induzida após a criação do local → nada fica (CT-01 item 1/7)
  4.x  CT-01: Local padrão (D-A), replay, chave reutilizada, local exigido
       quando já existe, local escolhido, local alheio, entradas inválidas,
       nenhuma carta recebe local (NS-13)
  5.x  R1 Biblioteca + isolamento
  6.x  R3 candidatas (D-C: só 1 de cada; sem modo "todas") + isolamento
  7.x  vincular via 5046 → R1/R2/R3 coerentes com 5070; sem duplicar cartas
  8.x  R2 isolamento e filtro inválido
  9.1  resíduo zero e papel restaurado

Esperado: 35 linhas PASS + GATE = PASS.
================================================================
*/

create or replace function pg_temp.rc_5830_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  v_ct01    oid := to_regprocedure('public.create_my_card_set_collection(uuid,uuid,text,uuid)');
  v_r1      oid := to_regprocedure('public.get_my_collections(boolean,integer,integer)');
  v_r2      oid := to_regprocedure('public.get_my_collection_positions(uuid,text,integer,integer)');
  v_r3      oid := to_regprocedure('public.get_my_collection_link_candidates(uuid,integer)');
  p_user_a  uuid := gen_random_uuid();
  p_user_b  uuid := gen_random_uuid();
  v_sfx     text := substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
  v_base_us bigint;
  v_base_up bigint;
  v_base_iv bigint;
  v_tbl     regclass := to_regclass('public.collection_creation_request');
  v_inv_a   uuid;
  v_inv_b   uuid;
  v_set     uuid;
  v_set_code text;
  v_positions bigint;
  v_card1   uuid;
  v_card2   uuid;
  v_var1    uuid;
  v_var2    uuid;
  v_lang    uuid;
  v_pc1a    uuid;
  v_pc1b    uuid;
  v_pc2     uuid;
  v_box_b   uuid;
  v_k1      uuid := gen_random_uuid();
  v_k2      uuid := gen_random_uuid();
  v_kf      uuid := gen_random_uuid();
  v_coll1   uuid;
  v_coll2   uuid;
  v_store_a uuid;
  v_rec     record;
  v_rec2    record;
  v_ids     uuid[];
  v_cnt     bigint;
  v_cnt2    bigint;
  v_state   text;
  v_msg     text;
  v_ok      boolean;
  v_base_pc bigint;
  v_base_sc bigint;
  v_base_co bigint;
  v_base_ca bigint;
  v_base_rq bigint;
  res       jsonb := '[]'::jsonb;
  r         jsonb;
  n         integer := 0;
  passes    integer := 0;
begin
  -- 0. Estrutura e privilégios -------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    v_tbl is not null
      and (select c.relrowsecurity from pg_class c where c.oid = v_tbl)
      and not has_table_privilege('anon', v_tbl, 'SELECT')
      and not has_table_privilege('authenticated', v_tbl, 'SELECT')
      and not has_table_privilege('authenticated', v_tbl, 'INSERT')
      and not has_table_privilege('service_role', v_tbl, 'SELECT'),
    'detail','5166: tabela com RLS e sem privilégios de cliente');
  res := res || jsonb_build_object('id','0.2','ok',
    v_ct01 is not null and v_r1 is not null and v_r2 is not null and v_r3 is not null,
    'detail','5167–5170 existem');
  res := res || jsonb_build_object('id','0.3','ok',
    coalesce((select p.prosecdef and p.provolatile = 'v' and p.proconfig = array['search_path=""']
              from pg_proc p where p.oid = v_ct01), false),
    'detail','CT-01: SECURITY DEFINER, VOLATILE, search_path vazio');
  res := res || jsonb_build_object('id','0.4','ok',
    (select count(*) from pg_proc p
      where p.oid in (v_r1, v_r2, v_r3)
        and p.prosecdef and p.provolatile = 's' and p.proconfig = array['search_path=""']) = 3,
    'detail','R1–R3: SECURITY DEFINER, STABLE, search_path vazio');
  res := res || jsonb_build_object('id','0.5','ok',
    (select count(*) from unnest(array[v_ct01, v_r1, v_r2, v_r3]) f(o)
      where f.o is not null
        and has_function_privilege('authenticated', f.o, 'EXECUTE')
        and not has_function_privilege('anon', f.o, 'EXECUTE')) = 4,
    'detail','EXECUTE só authenticated nas 4 funções');

  select count(*) into v_base_us from auth.users;
  select count(*) into v_base_up from public.user_profile;
  select count(*) into v_base_iv from public.inventory;
  select count(*) into v_base_pc from public.physical_card;
  select count(*) into v_base_sc from public.storage_container;
  select count(*) into v_base_co from public.collection;
  select count(*) into v_base_ca from public.collection_allocation;
  if v_tbl is not null then
    execute 'select count(*) from public.collection_creation_request' into v_base_rq;
  end if;


  begin
    -- Identidades de teste efêmeras (desfeitas pela sentinela)
    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    values (p_user_a, 'authenticated', 'authenticated', 'rc5830-a-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'rc5830a_'||v_sfx, 'display_name', 'RC 5830 A'), now(), now()),
           (p_user_b, 'authenticated', 'authenticated', 'rc5830-b-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'rc5830b_'||v_sfx, 'display_name', 'RC 5830 B'), now(), now());

    -- Fixture (como dono do banco, antes de qualquer troca de papel)
    select i.id into v_inv_a from public.inventory i where i.owner_user_id = p_user_a;
    select i.id into v_inv_b from public.inventory i where i.owner_user_id = p_user_b;
    select l.id into v_lang from public.language l where l.code = 'pt-BR';

    select c.card_set_id into v_set
    from public.card c
    join public.card_variant cv on cv.card_id = c.id and cv.is_default and cv.is_active
    where c.is_active
      group by c.card_set_id
    having count(distinct c.id) >= 2
    order by count(distinct c.id), c.card_set_id
    limit 1;

    select cs.code into v_set_code from public.card_set cs where cs.id = v_set;
    select count(*) into v_positions from public.card c where c.card_set_id = v_set;

    select c.id, cv.id into v_card1, v_var1
    from public.card c join public.card_variant cv on cv.card_id = c.id and cv.is_default and cv.is_active
    where c.card_set_id = v_set and c.is_active
    order by c.collector_order, c.id limit 1;
    select c.id, cv.id into v_card2, v_var2
    from public.card c join public.card_variant cv on cv.card_id = c.id and cv.is_default and cv.is_active
    where c.card_set_id = v_set and c.is_active and c.id <> v_card1
    order by c.collector_order, c.id limit 1;

    res := res || jsonb_build_object('id','0.6','ok',
      p_user_a <> p_user_b and v_inv_a is not null and v_inv_b is not null and v_lang is not null
        and v_set is not null and v_card2 is not null
        and not exists (select 1 from public.storage_container sc where sc.inventory_id in (v_inv_a, v_inv_b))
        and not exists (select 1 from public.collection co where co.owner_user_id in (p_user_a, p_user_b)),
      'detail', format('fixture: A/B de teste efêmeros com Inventory, sem locais nem coleções; Set %s (%s cartas)', v_set_code, v_positions));

    insert into public.physical_card (card_variant_id, language_id, inventory_id, created_at)
    values (v_var1, v_lang, v_inv_a, now() - interval '2 minutes') returning id into v_pc1a;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, created_at)
    values (v_var1, v_lang, v_inv_a, now() - interval '1 minute') returning id into v_pc1b;
    insert into public.physical_card (card_variant_id, language_id, inventory_id)
    values (v_var2, v_lang, v_inv_a) returning id into v_pc2;

    -- 1. anon -------------------------------------------------------------
    perform set_config('request.jwt.claims', '', true);
    execute 'set local role anon';
    begin perform public.create_my_card_set_collection(v_k1, v_set, 'x', null); v_state := 'executou';
    exception when others then v_state := sqlstate; end;
    res := res || jsonb_build_object('id','1.1','ok', v_state = '42501', 'detail','anon CT-01: '||v_state);
    begin perform public.get_my_collections(false, 48, 0); v_state := 'executou';
    exception when others then v_state := sqlstate; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.2','ok', v_state = '42501', 'detail','anon R1: '||v_state);

    -- 2. sem auth.uid() ----------------------------------------------------
    execute 'set local role authenticated';
    begin perform public.create_my_card_set_collection(v_k1, v_set, 'x', null); v_state := 'executou';
    exception when others then v_state := sqlstate; end;
    res := res || jsonb_build_object('id','2.1','ok', v_state = '28000', 'detail','sem identidade CT-01: '||v_state);
    begin perform public.get_my_collection_positions(gen_random_uuid(), 'ALL', 10, 0); v_state := 'executou';
    exception when others then v_state := sqlstate; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','2.2','ok', v_state = '28000', 'detail','sem identidade R2: '||v_state);

    -- 3. Falha induzida DEPOIS da criação do local (B sem locais) ----------
    create function public.rc_5830_fail() returns trigger language plpgsql as
      $t$ begin raise exception 'RC5830_INDUCED_FAILURE'; end; $t$;
    create trigger rc_5830_fail before insert on public.collection
      for each row when (new.name = 'FALHA 5830') execute function public.rc_5830_fail();

    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    begin perform public.create_my_card_set_collection(v_kf, v_set, 'FALHA 5830', null); v_state := 'executou'; v_msg := '';
    exception when others then v_state := sqlstate; v_msg := sqlerrm; end;
    execute 'reset role';
    execute 'select count(*) from public.collection_creation_request where owner_user_id = $1' into v_cnt using p_user_b;
    res := res || jsonb_build_object('id','3.1','ok',
      v_msg like '%RC5830_INDUCED_FAILURE%'
        and not exists (select 1 from public.storage_container sc where sc.inventory_id = v_inv_b)
        and not exists (select 1 from public.collection co where co.owner_user_id = p_user_b)
        and v_cnt = 0,
      'detail','falha após criar o local: nenhum local, coleção ou registro de B ('||v_state||')');
    drop trigger rc_5830_fail on public.collection;
    drop function public.rc_5830_fail();

    insert into public.storage_container (inventory_id, name) values (v_inv_b, 'Caixa B 5830') returning id into v_box_b;

    -- 4. CT-01 como A -----------------------------------------------------
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select * into v_rec from public.create_my_card_set_collection(v_k1, v_set, ' Coleção 5830 ', null);
    v_coll1 := v_rec.collection_id; v_store_a := v_rec.storage_container_id;
    select * into v_rec2 from public.create_my_card_set_collection(v_k1, v_set, 'Coleção 5830', null);
    begin perform public.create_my_card_set_collection(v_k1, v_set, 'Outro nome', null); v_state := 'executou'; v_msg := '';
    exception when others then v_state := sqlstate; v_msg := sqlerrm; end;
    execute 'reset role';
    execute 'select count(*) from public.collection_creation_request where owner_user_id = $1' into v_cnt using p_user_a;
    res := res || jsonb_build_object('id','4.1','ok',
      v_rec.storage_container_created and not v_rec.replayed and v_rec.card_set_id = v_set
        and (select sc.name from public.storage_container sc where sc.id = v_store_a and sc.inventory_id = v_inv_a) = 'Local padrão'
        and (select co.default_storage_container_id from public.collection co where co.id = v_coll1 and co.owner_user_id = p_user_a) = v_store_a
        and exists (select 1 from public.collection_reference cr
                    join public.collection_card_set_reference ccsr on ccsr.collection_reference_id = cr.id
                    where cr.collection_id = v_coll1 and ccsr.card_set_id = v_set)
        and v_cnt = 1,
      'detail','A sem locais: cria "Local padrão" + coleção de Set + registro (D-A)');
    res := res || jsonb_build_object('id','4.2','ok',
      v_rec2.replayed and v_rec2.collection_id = v_coll1 and v_rec2.storage_container_id = v_store_a
        and (select count(*) from public.collection co where co.owner_user_id = p_user_a) = 1
        and (select count(*) from public.storage_container sc where sc.inventory_id = v_inv_a) = 1,
      'detail','repetição da mesma chave: mesmo resultado, nada duplicado');
    res := res || jsonb_build_object('id','4.3','ok', v_state = '22023' and v_msg = 'IDEMPOTENCY_KEY_REUSED',
      'detail','mesma chave com pedido diferente: '||v_state||' '||v_msg);

    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    begin perform public.create_my_card_set_collection(v_k2, v_set, 'Segunda 5830', null); v_state := 'executou'; v_msg := '';
    exception when others then v_state := sqlstate; v_msg := sqlerrm; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','4.4','ok',
      v_state = '55000' and v_msg = 'STORAGE_CONTAINER_REQUIRED'
        and (select count(*) from public.collection co where co.owner_user_id = p_user_a) = 1,
      'detail','A já tem local e não escolheu: '||v_state||' '||v_msg||' (nada criado)');

    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select * into v_rec from public.create_my_card_set_collection(v_k2, v_set, 'Segunda 5830', v_store_a);
    v_coll2 := v_rec.collection_id;
    begin perform public.create_my_card_set_collection(gen_random_uuid(), v_set, 'Terceira 5830', v_box_b); v_state := 'executou'; v_msg := '';
    exception when others then v_state := sqlstate; v_msg := sqlerrm; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','4.5','ok',
      not v_rec.storage_container_created and v_rec.storage_container_id = v_store_a
        and (select count(*) from public.storage_container sc where sc.inventory_id = v_inv_a) = 1
        and (select count(*) from public.collection co where co.owner_user_id = p_user_a) = 2,
      'detail','local escolhido explicitamente: nenhum local novo');
    res := res || jsonb_build_object('id','4.6','ok', v_state = '22023' and v_msg = 'STORAGE_CONTAINER_INVALID',
      'detail','local de B informado por A: '||v_state||' '||v_msg);

    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    v_ok := true;
    begin perform public.create_my_card_set_collection(gen_random_uuid(), v_set, '   ', v_store_a); v_ok := false;
    exception when others then v_ok := v_ok and sqlstate = '22023'; end;
    begin perform public.create_my_card_set_collection(gen_random_uuid(), null, 'x', v_store_a); v_ok := false;
    exception when others then v_ok := v_ok and sqlstate = '22023'; end;
    begin perform public.create_my_card_set_collection(null, v_set, 'x', v_store_a); v_ok := false;
    exception when others then v_ok := v_ok and sqlstate = '22023'; end;
    begin perform public.create_my_card_set_collection(gen_random_uuid(), gen_random_uuid(), 'x', v_store_a); v_ok := false;
    exception when others then v_ok := v_ok and sqlerrm = 'CARD_SET_NOT_FOUND'; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','4.7','ok', v_ok
        and (select count(*) from public.collection co where co.owner_user_id = p_user_a) = 2,
      'detail','nome vazio, Set nulo, chave nula, Set inexistente → 22023, nada criado');
    res := res || jsonb_build_object('id','4.8','ok',
      not exists (select 1 from public.physical_card pc where pc.inventory_id = v_inv_a and pc.storage_container_id is not null),
      'detail','nenhuma carta recebeu local (NS-13, C-26)');

    -- 5. R1 ---------------------------------------------------------------
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select count(*), min(g.total_count), bool_and(g.card_set_code = v_set_code and g.total_positions = v_positions
                                                  and g.satisfied_positions = 0 and g.copies_count = 0)
      into v_cnt, v_cnt2, v_ok
    from public.get_my_collections(false, 48, 0) g;
    begin perform public.get_my_collections(false, 0, 0); v_state := 'executou';
    exception when others then v_state := sqlstate; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','5.1','ok', v_cnt = 2 and v_cnt2 = 2 and v_ok,
      'detail', format('Biblioteca de A: %s coleções, Set %s, 0 de %s', v_cnt, v_set_code, v_positions));
    res := res || jsonb_build_object('id','5.2','ok', v_state = '22023', 'detail','página inválida: '||v_state);

    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select count(*) into v_cnt from public.get_my_collections(true, 100, 0);
    execute 'reset role';
    res := res || jsonb_build_object('id','5.3','ok', v_cnt = 0, 'detail','B não vê coleções de A');

    -- 6. R3 ---------------------------------------------------------------
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select array_agg(x.physical_card_id order by x.collector_number), count(distinct x.card_id), count(*)
      into v_ids, v_cnt, v_cnt2
    from public.get_my_collection_link_candidates(v_coll1, 500) x;
    res := res || jsonb_build_object('id','6.1','ok',
      v_cnt = 2 and v_cnt2 = 2 and v_pc1a = any(v_ids) and v_pc2 = any(v_ids) and not (v_pc1b = any(v_ids)),
      'detail','1 de cada: 2 exemplares, o mais antigo da carta repetida');
    begin perform public.get_my_collection_link_candidates(v_coll1, 0); v_state := 'executou';
    exception when others then v_state := sqlstate; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','6.2','ok',
      (select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
        where ns.nspname = 'public' and p.proname = 'get_my_collection_link_candidates') = 1
        and to_regprocedure('public.get_my_collection_link_candidates(uuid,text,integer)') is null,
      'detail','R3 só tem o modo "1 de cada" (nenhuma assinatura com modo "todas")');
    res := res || jsonb_build_object('id','6.4','ok', v_state = '22023', 'detail','limite inválido: '||v_state);

    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select count(*) into v_cnt from public.get_my_collection_link_candidates(v_coll1, 500);
    execute 'reset role';
    res := res || jsonb_build_object('id','6.3','ok', v_cnt = 0, 'detail','B sobre coleção de A: 0 linhas');

    -- 7. Vincular (5046) e reler -------------------------------------------
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.allocate_physical_cards_to_collection(v_coll1, v_ids);

    select g.satisfied_positions, g.copies_count into v_cnt, v_cnt2
    from public.get_my_collections(false, 48, 0) g where g.collection_id = v_coll1;
    res := res || jsonb_build_object('id','7.1','ok', v_cnt = 2 and v_cnt2 = 2,
      'detail', format('R1 após vincular: %s de %s, %s cartas', v_cnt, v_positions, v_cnt2));

    select count(*) into v_cnt from public.get_my_collection_positions(v_coll1, 'OWNED', 500, 0);
    select count(*) into v_cnt2 from public.get_my_collection_positions(v_coll1, 'MISSING', 500, 0);
    select p.copies_in_collection = 1 and p.copies_available = 1 and p.is_satisfied
      into v_ok
    from public.get_my_collection_positions(v_coll1, 'ALL', 500, 0) p where p.card_id = v_card1;
    res := res || jsonb_build_object('id','7.2','ok',
      v_cnt = 2 and v_cnt2 = v_positions - 2 and coalesce(v_ok, false)
        and (select max(p.total_count) from public.get_my_collection_positions(v_coll1, 'ALL', 1, 0) p) = v_positions,
      'detail', format('R2: tenho %s, faltam %s; repetida = 1 na coleção + 1 disponível', v_cnt, v_cnt2));

    select count(*) into v_cnt from public.get_my_collection_link_candidates(v_coll1, 500);
    select p.copies_available into v_cnt2
    from public.get_my_collection_positions(v_coll1, 'ALL', 500, 0) p where p.card_id = v_card1;
    res := res || jsonb_build_object('id','7.3','ok', v_cnt = 0 and v_cnt2 = 1,
      'detail', format('R3 após vincular: %s candidatas; a repetida segue no acervo (%s disponível)', v_cnt, v_cnt2));

    select (s.satisfied_positions = g.satisfied_positions and s.total_positions = g.total_positions)
      into v_ok
    from public.collection_completion_summary(v_coll1) s
    cross join lateral (select * from public.get_my_collections(false, 48, 0) x where x.collection_id = v_coll1) g;
    res := res || jsonb_build_object('id','7.4','ok', coalesce(v_ok, false), 'detail','R1 = 5070 (progresso canônico)');

    select array_agg(x.physical_card_id), count(*) into v_ids, v_cnt
    from public.get_my_collection_link_candidates(v_coll2, 500) x;
    execute 'reset role';
    res := res || jsonb_build_object('id','7.5','ok', v_cnt = 1 and v_ids = array[v_pc1b],
      'detail','segunda coleção: só o exemplar ainda livre é candidato');
    res := res || jsonb_build_object('id','7.6','ok',
      (select count(*) from public.physical_card) = v_base_pc + 3
        and (select count(*) from public.collection_allocation ca where ca.physical_card_id in (v_pc1a, v_pc1b, v_pc2)) = 2,
      'detail','vincular não duplica cartas: +3 exemplares de fixture, 2 alocações');

    -- 8. R2 isolamento e filtro inválido ------------------------------------
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select count(*) into v_cnt from public.get_my_collection_positions(v_coll1, 'ALL', 500, 0);
    begin perform public.get_my_collection_positions(v_coll1, 'TUDO', 500, 0); v_state := 'executou';
    exception when others then v_state := sqlstate; end;
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    res := res || jsonb_build_object('id','8.1','ok', v_cnt = 0, 'detail','B sobre coleção de A: 0 linhas');
    res := res || jsonb_build_object('id','8.2','ok', v_state = '22023', 'detail','filtro inválido: '||v_state);

    raise exception 'LI000' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'LI000' then
      res := res || jsonb_build_object('id','X.1','ok', false, 'detail','erro inesperado: '||sqlstate||' '||sqlerrm);
    end if;
  end;

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  if v_tbl is not null then
    execute 'select count(*) from public.collection_creation_request' into v_cnt;
  end if;
  res := res || jsonb_build_object('id','9.1','ok',
    (select count(*) from auth.users) = v_base_us
      and (select count(*) from public.user_profile) = v_base_up
      and (select count(*) from public.inventory) = v_base_iv
      and (select count(*) from public.physical_card) = v_base_pc
      and (select count(*) from public.storage_container) = v_base_sc
      and (select count(*) from public.collection) = v_base_co
      and (select count(*) from public.collection_allocation) = v_base_ca
      and coalesce(v_cnt, 0) = coalesce(v_base_rq, 0)
      and to_regprocedure('public.rc_5830_fail()') is null
      and current_user = session_user,
    'detail','resíduo zero (inclusive usuários de teste), gatilho de teste removido e papel restaurado');

  for r in select * from jsonb_array_elements(res) loop
    n := n + 1;
    if coalesce((r->>'ok')::boolean, false) then passes := passes + 1; end if;
    seq := n; check_id := r->>'id';
    status := case when coalesce((r->>'ok')::boolean, false) then 'PASS' else 'FAIL' end;
    detail := r->>'detail';
    return next;
  end loop;
  seq := 99; check_id := 'GATE';
  status := case when passes = n and n = 35 then 'PASS' else 'FAIL' end;
  detail := format('%s/%s PASS (esperado 35)', passes, n);
  return next;
end;
$fn$;

-- SELECT * FROM pg_temp.rc_5830_validate();
