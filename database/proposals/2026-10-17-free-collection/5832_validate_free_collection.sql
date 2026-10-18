/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5832 - Validate Coleção livre (5175)
Versão......: 1.1 (FREE-COLLECTION-READINESS-01: ACL igual à de 5167;
              restrições adiadas forçadas; reutilização de chave entre
              usuários; checagem de exemplares restrita aos usuários de teste)
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-17 — 25/25 PASS + GATE PASS;
              resíduo zero (9.1)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-17 (COLLECTIONS-FUNCTIONAL-RECOVERY-01)

Mesmo protocolo de 5830: tudo num único statement; fixtures, trocas de
papel e chamadas ficam num bloco que termina SEMPRE com a exceção
sentinela LI000 — o savepoint desfaz tudo (usuários de teste, locais,
coleções, registros de idempotência, gatilho de falha). Os resultados
sobrevivem em variáveis. 9.1 prova resíduo zero.

Identidades: o harness NÃO usa nenhum usuário real. Cria dois usuários
de teste efêmeros (A e B) em auth.users dentro do bloco revertido — os
gatilhos existentes criam o perfil e o Inventory deles — e tudo é
desfeito pela sentinela. Nenhum dado real é lido para escrita, alterado
ou excluído. Nenhuma coleção real é criada.

Pré-requisitos:
  - 5166–5170 aplicadas (LIVE) e 5175 aplicada.
  - Um Set qualquer do catálogo, escolhido automaticamente (só leitura),
    para provar a separação de chaves entre 5167 e 5175 (seção 4.4).

Execução:
  SELECT * FROM pg_temp.rc_5832_validate();

Cobertura:
  0.x  estrutura, segurança, privilégios; 5167 intacta
  1.x  anon; 2.x sem identidade
  3.1  falha induzida após a criação do local → nada fica (atomicidade)
  4.x  D-A, replay, chave reutilizada (inclusive entre 5167 e 5175),
       local exigido, local escolhido, local alheio, entradas inválidas,
       nenhuma carta tocada, mesma chave usada por outro usuário (4.11),
       restrições adiadas conferidas antes do fim do statement (4.12)
  5.x  Biblioteca (R1): curadoria aberta sem progresso + isolamento
  6.1  fila única com 5167 (mesma chave de advisory lock)
  9.1  resíduo zero e papel restaurado

Esperado: 25 linhas PASS + GATE = PASS.
================================================================
*/

create or replace function pg_temp.rc_5832_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  v_free    oid := to_regprocedure('public.create_my_free_collection(uuid,text,uuid)');
  v_ct01    oid := to_regprocedure('public.create_my_card_set_collection(uuid,uuid,text,uuid)');
  v_r1      oid := to_regprocedure('public.get_my_collections(boolean,integer,integer)');
  p_user_a  uuid := gen_random_uuid();
  p_user_b  uuid := gen_random_uuid();
  v_sfx     text := substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
  v_inv_a   uuid;
  v_inv_b   uuid;
  v_set     uuid;
  v_game    uuid;
  v_box_b   uuid;
  v_k1      uuid := gen_random_uuid();
  v_k2      uuid := gen_random_uuid();
  v_k3      uuid := gen_random_uuid();
  v_k4      uuid := gen_random_uuid();
  v_kf      uuid := gen_random_uuid();
  v_coll1   uuid;
  v_store_a uuid;
  v_rec     record;
  v_rec2    record;
  v_cnt     bigint;
  v_cnt2    bigint;
  v_state   text;
  v_msg     text;
  v_state2  text;
  v_msg2    text;
  v_ok      boolean;
  v_base_us bigint;
  v_base_up bigint;
  v_base_iv bigint;
  v_base_pc bigint;
  v_base_sc bigint;
  v_base_co bigint;
  v_base_ca bigint;
  v_base_cr bigint;
  v_base_rq bigint;
  res       jsonb := '[]'::jsonb;
  r         jsonb;
  n         integer := 0;
  passes    integer := 0;
begin
  -- 0. Estrutura e privilégios -------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok', v_free is not null and v_ct01 is not null and v_r1 is not null,
    'detail','5175 existe; 5167 e R1 (5173) continuam com a mesma assinatura');
  res := res || jsonb_build_object('id','0.2','ok',
    coalesce((select p.prosecdef and p.provolatile = 'v' and p.proconfig = array['search_path=""']
              from pg_proc p where p.oid = v_free), false),
    'detail','5175: SECURITY DEFINER, VOLATILE, search_path vazio');
  res := res || jsonb_build_object('id','0.3','ok',
    v_free is not null
      and has_function_privilege('authenticated', v_free, 'EXECUTE')
      and not has_function_privilege('anon', v_free, 'EXECUTE')
      and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = v_free and a.grantee = 0)
      and (select array_agg(distinct a.grantee::text || ':' || a.privilege_type order by a.grantee::text || ':' || a.privilege_type)
             from pg_proc p, aclexplode(p.proacl) a where p.oid = v_free)
        = (select array_agg(distinct a.grantee::text || ':' || a.privilege_type order by a.grantee::text || ':' || a.privilege_type)
             from pg_proc p, aclexplode(p.proacl) a where p.oid = v_ct01),
    'detail','5175: EXECUTE só authenticated (sem PUBLIC, sem anon) e ACL idêntica à de 5167');
  res := res || jsonb_build_object('id','0.4','ok',
    coalesce((select position('physical_card' in p.prosrc) = 0 and position('collection_allocation' in p.prosrc) = 0
              from pg_proc p where p.oid = v_free), false),
    'detail','5175 não referencia physical_card nem collection_allocation (NS-13, C-26)');

  select count(*) into v_base_us from auth.users;
  select count(*) into v_base_up from public.user_profile;
  select count(*) into v_base_iv from public.inventory;
  select count(*) into v_base_pc from public.physical_card;
  select count(*) into v_base_sc from public.storage_container;
  select count(*) into v_base_co from public.collection;
  select count(*) into v_base_ca from public.collection_allocation;
  select count(*) into v_base_cr from public.collection_reference;
  select count(*) into v_base_rq from public.collection_creation_request;

  begin
    -- Identidades de teste efêmeras (desfeitas pela sentinela)
    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    values (p_user_a, 'authenticated', 'authenticated', 'rc5832-a-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'rc5832a_'||v_sfx, 'display_name', 'RC 5832 A'), now(), now()),
           (p_user_b, 'authenticated', 'authenticated', 'rc5832-b-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'rc5832b_'||v_sfx, 'display_name', 'RC 5832 B'), now(), now());

    select i.id into v_inv_a from public.inventory i where i.owner_user_id = p_user_a;
    select i.id into v_inv_b from public.inventory i where i.owner_user_id = p_user_b;
    select g.id into v_game from public.game g where g.code = 'POKEMON';
    select cs.id into v_set
    from public.card_set cs join public.expansion e on e.id = cs.expansion_id
    where e.game_id = v_game
    order by cs.id limit 1;

    res := res || jsonb_build_object('id','0.5','ok',
      p_user_a <> p_user_b and v_inv_a is not null and v_inv_b is not null and v_game is not null and v_set is not null
        and not exists (select 1 from public.storage_container sc where sc.inventory_id in (v_inv_a, v_inv_b))
        and not exists (select 1 from public.collection co where co.owner_user_id in (p_user_a, p_user_b)),
      'detail','fixture: A/B de teste efêmeros com Inventory, sem locais nem coleções; Game POKEMON e um Set presentes');

    -- 1. anon -------------------------------------------------------------
    perform set_config('request.jwt.claims', '', true);
    execute 'set local role anon';
    begin perform public.create_my_free_collection(v_k1, 'x', null); v_state := 'executou';
    exception when others then v_state := sqlstate; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.1','ok', v_state = '42501', 'detail','anon: '||v_state);

    -- 2. sem auth.uid() ----------------------------------------------------
    execute 'set local role authenticated';
    begin perform public.create_my_free_collection(v_k1, 'x', null); v_state := 'executou';
    exception when others then v_state := sqlstate; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','2.1','ok', v_state = '28000', 'detail','sem identidade: '||v_state);

    -- 3. Falha induzida DEPOIS da criação do local (B sem locais) ----------
    create function public.rc_5832_fail() returns trigger language plpgsql as
      $t$ begin raise exception 'RC5832_INDUCED_FAILURE'; end; $t$;
    create trigger rc_5832_fail before insert on public.collection
      for each row when (new.name = 'FALHA 5832') execute function public.rc_5832_fail();

    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    begin perform public.create_my_free_collection(v_kf, 'FALHA 5832', null); v_state := 'executou'; v_msg := '';
    exception when others then v_state := sqlstate; v_msg := sqlerrm; end;
    execute 'reset role';
    select count(*) into v_cnt from public.collection_creation_request where owner_user_id = p_user_b;
    res := res || jsonb_build_object('id','3.1','ok',
      v_msg like '%RC5832_INDUCED_FAILURE%'
        and not exists (select 1 from public.storage_container sc where sc.inventory_id = v_inv_b)
        and not exists (select 1 from public.collection co where co.owner_user_id = p_user_b)
        and v_cnt = 0,
      'detail','falha após criar o local: nenhum local, coleção ou registro de B ('||v_state||')');
    drop trigger rc_5832_fail on public.collection;
    drop function public.rc_5832_fail();

    insert into public.storage_container (inventory_id, name) values (v_inv_b, 'Caixa B 5832') returning id into v_box_b;

    -- 4. Coleção livre como A ---------------------------------------------
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select * into v_rec from public.create_my_free_collection(v_k1, ' Minhas favoritas 5832 ', null);
    v_coll1 := v_rec.collection_id; v_store_a := v_rec.storage_container_id;
    select * into v_rec2 from public.create_my_free_collection(v_k1, 'Minhas favoritas 5832', null);
    begin perform public.create_my_free_collection(v_k1, 'Outro nome', null); v_state := 'executou'; v_msg := '';
    exception when others then v_state := sqlstate; v_msg := sqlerrm; end;
    execute 'reset role';
    select count(*) into v_cnt from public.collection_creation_request where owner_user_id = p_user_a;
    res := res || jsonb_build_object('id','4.1','ok',
      v_rec.storage_container_created and not v_rec.replayed
        and (select sc.name from public.storage_container sc where sc.id = v_store_a and sc.inventory_id = v_inv_a) = 'Local padrão'
        and exists (select 1 from public.collection co
                    where co.id = v_coll1 and co.owner_user_id = p_user_a and co.game_id = v_game
                      and co.name = 'Minhas favoritas 5832' and co.mode = 'OPEN_CURATION'
                      and co.completion_policy = 'NONE' and co.default_storage_container_id = v_store_a)
        and not exists (select 1 from public.collection_reference cr where cr.collection_id = v_coll1)
        and v_cnt = 1,
      'detail','A sem locais: "Local padrão" + Coleção livre (OPEN_CURATION, NONE, sem referência) + registro (D-A)');
    res := res || jsonb_build_object('id','4.2','ok',
      v_rec2.replayed and v_rec2.collection_id = v_coll1 and v_rec2.storage_container_id = v_store_a
        and v_rec2.storage_container_created
        and (select count(*) from public.collection co where co.owner_user_id = p_user_a) = 1
        and (select count(*) from public.storage_container sc where sc.inventory_id = v_inv_a) = 1,
      'detail','repetição da mesma chave: mesmo resultado, nada duplicado');
    res := res || jsonb_build_object('id','4.3','ok', v_state = '22023' and v_msg = 'IDEMPOTENCY_KEY_REUSED',
      'detail','mesma chave com pedido diferente: '||v_state||' '||v_msg);

    -- 4.4 Chaves não se confundem entre as duas portas (5167 ↔ 5175).
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.create_my_card_set_collection(v_k3, v_set, 'Set 5832', v_store_a);
    begin perform public.create_my_free_collection(v_k3, 'Set 5832', v_store_a); v_state := 'executou'; v_msg := '';
    exception when others then v_state := sqlstate; v_msg := sqlerrm; end;
    perform public.create_my_free_collection(v_k4, 'Livre 5832', v_store_a);
    begin perform public.create_my_card_set_collection(v_k4, v_set, 'Livre 5832', v_store_a); v_state2 := 'executou'; v_msg2 := '';
    exception when others then v_state2 := sqlstate; v_msg2 := sqlerrm; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','4.4','ok',
      v_msg = 'IDEMPOTENCY_KEY_REUSED' and v_msg2 = 'IDEMPOTENCY_KEY_REUSED'
        and (select count(*) from public.collection co where co.owner_user_id = p_user_a) = 3,
      'detail','chave de Set usada na livre e vice-versa: IDEMPOTENCY_KEY_REUSED nos dois sentidos; nada extra criado');

    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    begin perform public.create_my_free_collection(v_k2, 'Segunda 5832', null); v_state := 'executou'; v_msg := '';
    exception when others then v_state := sqlstate; v_msg := sqlerrm; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','4.5','ok',
      v_state = '55000' and v_msg = 'STORAGE_CONTAINER_REQUIRED'
        and (select count(*) from public.collection co where co.owner_user_id = p_user_a) = 3,
      'detail','A já tem local e não escolheu: '||v_state||' '||v_msg||' (nada criado)');

    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select * into v_rec from public.create_my_free_collection(v_k2, 'Segunda 5832', v_store_a);
    begin perform public.create_my_free_collection(gen_random_uuid(), 'Terceira 5832', v_box_b); v_state := 'executou'; v_msg := '';
    exception when others then v_state := sqlstate; v_msg := sqlerrm; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','4.6','ok',
      not v_rec.storage_container_created and not v_rec.replayed and v_rec.storage_container_id = v_store_a
        and (select count(*) from public.storage_container sc where sc.inventory_id = v_inv_a) = 1
        and (select count(*) from public.collection co where co.owner_user_id = p_user_a) = 4,
      'detail','local escolhido explicitamente: nenhum local novo');
    res := res || jsonb_build_object('id','4.7','ok', v_state = '22023' and v_msg = 'STORAGE_CONTAINER_INVALID',
      'detail','local de B informado por A: '||v_state||' '||v_msg);

    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    v_ok := true;
    begin perform public.create_my_free_collection(gen_random_uuid(), '   ', v_store_a); v_ok := false;
    exception when others then v_ok := v_ok and sqlstate = '22023' and sqlerrm = 'INVALID_REQUEST'; end;
    begin perform public.create_my_free_collection(gen_random_uuid(), null, v_store_a); v_ok := false;
    exception when others then v_ok := v_ok and sqlstate = '22023' and sqlerrm = 'INVALID_REQUEST'; end;
    begin perform public.create_my_free_collection(null, 'x', v_store_a); v_ok := false;
    exception when others then v_ok := v_ok and sqlstate = '22023' and sqlerrm = 'INVALID_REQUEST'; end;
    begin perform public.create_my_free_collection(gen_random_uuid(), 'x', gen_random_uuid()); v_ok := false;
    exception when others then v_ok := v_ok and sqlerrm = 'STORAGE_CONTAINER_INVALID'; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','4.8','ok', v_ok
        and (select count(*) from public.collection co where co.owner_user_id = p_user_a) = 4,
      'detail','nome vazio, nome nulo, chave nula, local inexistente → recusados, nada criado');
    res := res || jsonb_build_object('id','4.9','ok',
      not exists (select 1 from public.physical_card pc where pc.inventory_id in (v_inv_a, v_inv_b))
        and not exists (select 1 from public.collection_allocation ca
                        join public.collection co on co.id = ca.collection_id
                        where co.owner_user_id in (p_user_a, p_user_b)),
      'detail','nenhum exemplar criado nem vinculado para os usuários de teste (NS-13, C-26); contagem global em 9.1');
    res := res || jsonb_build_object('id','4.10','ok',
      (select count(*) from public.collection_reference cr
         join public.collection co on co.id = cr.collection_id
        where co.owner_user_id = p_user_a) = 1,
      'detail','das 4 coleções de A, só a criada por 5167 tem referência de Set');

    -- 4.11 A mesma chave de A, usada por B, não devolve nada de A.
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select * into v_rec2 from public.create_my_free_collection(v_k1, 'Favoritas B 5832', v_box_b);
    execute 'reset role';
    res := res || jsonb_build_object('id','4.11','ok',
      not v_rec2.replayed and v_rec2.collection_id <> v_coll1 and not v_rec2.storage_container_created
        and v_rec2.storage_container_id = v_box_b
        and (select co.owner_user_id from public.collection co where co.id = v_rec2.collection_id) = p_user_b
        and (select count(*) from public.collection co where co.owner_user_id = p_user_a) = 4,
      'detail','chave de A reutilizada por B: coleção própria de B, nada de A devolvido ou alterado');

    -- 4.12 Restrições adiadas (gatilhos de consistência de referência) conferidas já.
    begin
      execute 'set constraints all immediate';
      v_ok := true; v_msg := '';
    exception when others then v_ok := false; v_msg := sqlerrm; end;
    res := res || jsonb_build_object('id','4.12','ok', v_ok,
      'detail','SET CONSTRAINTS ALL IMMEDIATE sem violação (coleções livres e de Set) '||coalesce(v_msg,''));

    -- 5. Biblioteca (R1) --------------------------------------------------
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select bool_and(g.card_set_id is null and g.card_set_code is null and g.completion_policy = 'NONE'
                    and g.mode = 'OPEN_CURATION' and g.total_positions is null and g.progress_percentage is null
                    and g.copies_count = 0)
      into v_ok
    from public.get_my_collections(false, 48, 0) g
    where g.collection_id = v_coll1;
    select count(*) into v_cnt from public.get_my_collections(false, 48, 0);
    execute 'reset role';
    res := res || jsonb_build_object('id','5.1','ok', coalesce(v_ok, false),
      'detail','Biblioteca: Coleção livre sem Set e sem progresso (C-20)');
    res := res || jsonb_build_object('id','5.2','ok', v_cnt = 4, 'detail', format('Biblioteca de A: %s coleções (esperado 4)', v_cnt));

    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select count(*), count(*) filter (where g.collection_id in (select co.id from public.collection co where co.owner_user_id = p_user_a))
      into v_cnt, v_cnt2
    from public.get_my_collections(true, 100, 0) g;
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    res := res || jsonb_build_object('id','5.3','ok', v_cnt = 1 and v_cnt2 = 0,
      'detail', format('B vê só a própria coleção (%s) e nenhuma de A (%s)', v_cnt, v_cnt2));

    -- 6. Fila única com 5167 ----------------------------------------------
    res := res || jsonb_build_object('id','6.1','ok',
      coalesce((select position('''create_my_card_set_collection:''' in p.prosrc) > 0 from pg_proc p where p.oid = v_free), false)
        and coalesce((select position('''create_my_card_set_collection:''' in p.prosrc) > 0 from pg_proc p where p.oid = v_ct01), false),
      'detail','5175 e 5167 usam a mesma chave de advisory lock (D-A decidido em fila única)');

    raise exception 'LI000' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'LI000' then
      res := res || jsonb_build_object('id','X.1','ok', false, 'detail','erro inesperado: '||sqlstate||' '||sqlerrm);
    end if;
  end;

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  res := res || jsonb_build_object('id','9.1','ok',
    (select count(*) from auth.users) = v_base_us
      and (select count(*) from public.user_profile) = v_base_up
      and (select count(*) from public.inventory) = v_base_iv
      and (select count(*) from public.physical_card) = v_base_pc
      and (select count(*) from public.storage_container) = v_base_sc
      and (select count(*) from public.collection) = v_base_co
      and (select count(*) from public.collection_allocation) = v_base_ca
      and (select count(*) from public.collection_reference) = v_base_cr
      and (select count(*) from public.collection_creation_request) = v_base_rq
      and to_regprocedure('public.rc_5832_fail()') is null
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
  status := case when passes = n and n = 25 then 'PASS' else 'FAIL' end;
  detail := format('%s/%s PASS (esperado 25)', passes, n);
  return next;
end;
$fn$;

-- SELECT * FROM pg_temp.rc_5832_validate();
