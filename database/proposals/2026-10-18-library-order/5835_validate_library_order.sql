/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5835 - Harness: ordem da Biblioteca escolhida pelo
              colecionador (5181 coluna + 5182 R1 v3 + 5183 RPC)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-18 — 22/22 PASS, GATE PASS, resíduo zero
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-18

Mesmo protocolo de 5832–5834: um único statement, usuários efêmeros,
sentinela LI000, resíduo zero (9.1). A ordem esperada é sempre derivada
da leitura do próprio R1 (as coleções de teste nascem na mesma transação,
com o mesmo created_at). Não toca dados reais.

Checagens:
  0.x  estrutura: coluna nula + CHECK; 5183 SECURITY DEFINER, search_path
       vazio, ACL só authenticated, sem referência a cartas; R1 com a mesma
       assinatura e ACL.
  1.1  anon → 42501        2.1  sem identidade → 28000
  3.x  ordem inicial; mover para o início ("antes de"); mover para o fim
       ("depois de"); idempotência; coleção nova entra no início;
       movimentos inválidos; coleção e âncora alheias/inexistentes (mesma
       resposta, nada muda); isolamento do R1 entre usuários; paginação
       respeita a ordem; CHECK; nada além da posição muda.
  9.1  resíduo zero.
GATE: n = 22 e todas PASS.
================================================================
*/

create or replace function pg_temp.rc_5835_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  v_fn      oid := to_regprocedure('public.move_my_collection(uuid,uuid,uuid)');
  v_r1      oid := to_regprocedure('public.get_my_collections(boolean,integer,integer)');
  p_user_a  uuid := gen_random_uuid();
  p_user_b  uuid := gen_random_uuid();
  v_sfx     text := substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
  v_c       uuid[] := '{}';
  v_b1      uuid;
  v_b2      uuid;
  v_new     uuid;
  v_l0      uuid[];
  v_l       uuid[];
  v_lb      uuid[];
  v_pos     integer;
  v_state   text;
  v_msg     text;
  v_fp      text;
  v_base_us bigint;
  v_base_co bigint;
  v_base_ca bigint;
  v_base_sc bigint;
  res       jsonb := '[]'::jsonb;
  r         jsonb;
  n         integer := 0;
  passes    integer := 0;
  i         integer;
begin
  -- 0. Estrutura
  res := res || jsonb_build_object('id','0.1','ok',
    exists (select 1 from information_schema.columns c
            where c.table_schema = 'public' and c.table_name = 'collection'
              and c.column_name = 'library_position' and c.is_nullable = 'YES' and c.column_default is null)
    and exists (select 1 from pg_constraint k
                where k.conrelid = 'public.collection'::regclass and k.conname = 'chk_collection_library_position'),
    'detail','collection.library_position (nula, sem default) + CHECK >= 1');
  res := res || jsonb_build_object('id','0.2','ok',
    coalesce((select p.prosecdef and p.proconfig = array['search_path=""'] from pg_proc p where p.oid = v_fn), false)
    and v_fn is not null
    and has_function_privilege('authenticated', v_fn, 'EXECUTE')
    and not has_function_privilege('anon', v_fn, 'EXECUTE')
    and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = v_fn and a.grantee = 0),
    'detail','5183: SECURITY DEFINER, search_path vazio, EXECUTE só authenticated');
  res := res || jsonb_build_object('id','0.3','ok',
    coalesce((select position('collection_allocation' in p.prosrc) = 0 and position('physical_card' in p.prosrc) = 0
              from pg_proc p where p.oid = v_fn), false),
    'detail','5183 não referencia cartas nem alocações');
  res := res || jsonb_build_object('id','0.4','ok',
    v_r1 is not null
    and (select count(*) from pg_proc q where q.proname = 'get_my_collections') = 1
    and has_function_privilege('authenticated', v_r1, 'EXECUTE')
    and not has_function_privilege('anon', v_r1, 'EXECUTE')
    and position('library_position asc nulls first' in (select p.prosrc from pg_proc p where p.oid = v_r1)) > 0,
    'detail','R1 (5182): mesma assinatura, ACL só authenticated, ordena por library_position');

  select count(*) into v_base_us from auth.users;
  select count(*) into v_base_co from public.collection;
  select count(*) into v_base_ca from public.collection_allocation;
  select count(*) into v_base_sc from public.storage_container;

  begin
    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    values (p_user_a, 'authenticated', 'authenticated', 'rc5835-a-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'rc5835a_'||v_sfx, 'display_name', 'RC 5835 A'), now(), now()),
           (p_user_b, 'authenticated', 'authenticated', 'rc5835-b-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'rc5835b_'||v_sfx, 'display_name', 'RC 5835 B'), now(), now());

    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    for i in 1..4 loop
      v_c := v_c || (select c.collection_id from public.create_my_free_collection(gen_random_uuid(), 'Ordem A'||i||' 5835',
        (select sc.id from public.storage_container sc join public.inventory iv on iv.id = sc.inventory_id
          where iv.owner_user_id = p_user_a limit 1)) c);
    end loop;
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select c.collection_id into v_b1 from public.create_my_free_collection(gen_random_uuid(), 'Ordem B1 5835', null) c;
    select c.collection_id into v_b2 from public.create_my_free_collection(gen_random_uuid(), 'Ordem B2 5835',
      (select sc.id from public.storage_container sc join public.inventory iv on iv.id = sc.inventory_id
        where iv.owner_user_id = p_user_b limit 1)) c;
    select array_agg(r.collection_id order by r.ordinality) into v_lb from public.get_my_collections(false, 100, 0) with ordinality r;
    execute 'reset role';

    -- 1.1 anon / 2.1 sem identidade
    perform set_config('request.jwt.claims', '', true);
    execute 'set local role anon';
    begin perform public.move_my_collection(v_c[1], v_c[2], null); v_state := 'executou';
    exception when others then v_state := sqlstate; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.1','ok', v_state = '42501', 'detail','anon: '||v_state);

    execute 'set local role authenticated';
    begin perform public.move_my_collection(v_c[1], v_c[2], null); v_state := 'executou';
    exception when others then v_state := sqlstate; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','2.1','ok', v_state = '28000', 'detail','sem identidade: '||v_state);

    -- 3.x como A
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';

    select array_agg(r.collection_id order by r.ordinality) into v_l0 from public.get_my_collections(false, 100, 0) with ordinality r;
    res := res || jsonb_build_object('id','3.1','ok',
      cardinality(v_l0) = 4 and v_l0 @> v_c and v_c @> v_l0
      and not exists (select 1 from public.collection c where c.id = any(v_c) and c.library_position is not null),
      'detail','ordem inicial: as 4 coleções de A, sem posição gravada (comportamento de hoje)');

    v_pos := public.move_my_collection(v_l0[4], null, v_l0[1]);
    select array_agg(r.collection_id order by r.ordinality) into v_l from public.get_my_collections(false, 100, 0) with ordinality r;
    res := res || jsonb_build_object('id','3.2','ok',
      v_pos = 1 and v_l = array[v_l0[4], v_l0[1], v_l0[2], v_l0[3]],
      'detail','mover a última para antes da primeira → posição '||v_pos);

    v_pos := public.move_my_collection(v_l0[1], v_l0[3], null);
    select array_agg(r.collection_id order by r.ordinality) into v_l from public.get_my_collections(false, 100, 0) with ordinality r;
    res := res || jsonb_build_object('id','3.3','ok',
      v_pos = 4 and v_l = array[v_l0[4], v_l0[2], v_l0[3], v_l0[1]]
      and (select array_agg(c.library_position order by c.library_position) from public.collection c where c.id = any(v_c)) = array[1,2,3,4],
      'detail','mover para depois de outra → posição '||v_pos||'; numeração 1..4 sem buracos');

    select md5(string_agg(c.id::text||c.library_position::text||c.updated_at::text, ',' order by c.id)) into v_fp
    from public.collection c where c.id = any(v_c);
    v_pos := public.move_my_collection(v_l0[1], v_l0[3], null);
    res := res || jsonb_build_object('id','3.4','ok',
      v_pos = 4
      and v_fp = (select md5(string_agg(c.id::text||c.library_position::text||c.updated_at::text, ',' order by c.id))
                  from public.collection c where c.id = any(v_c)),
      'detail','repetir o mesmo movimento é idempotente (nenhuma linha regravada)');

    select c.collection_id into v_new from public.create_my_free_collection(gen_random_uuid(), 'Ordem A5 5835',
      (select sc.id from public.storage_container sc join public.inventory iv on iv.id = sc.inventory_id
        where iv.owner_user_id = p_user_a limit 1)) c;
    select array_agg(r.collection_id order by r.ordinality) into v_l from public.get_my_collections(false, 100, 0) with ordinality r;
    res := res || jsonb_build_object('id','3.5','ok',
      v_l = array[v_new, v_l0[4], v_l0[2], v_l0[3], v_l0[1]],
      'detail','coleção criada depois da reordenação entra no início');

    begin perform public.move_my_collection(v_l0[1], null, null); v_msg := 'executou';
    exception when others then v_msg := sqlerrm; end;
    res := res || jsonb_build_object('id','3.6','ok', v_msg = 'INVALID_MOVE', 'detail','sem âncora: '||v_msg);

    begin perform public.move_my_collection(v_l0[1], v_l0[2], v_l0[3]); v_msg := 'executou';
    exception when others then v_msg := sqlerrm; end;
    res := res || jsonb_build_object('id','3.7','ok', v_msg = 'INVALID_MOVE', 'detail','duas âncoras: '||v_msg);

    begin perform public.move_my_collection(v_l0[1], v_l0[1], null); v_msg := 'executou';
    exception when others then v_msg := sqlerrm; end;
    res := res || jsonb_build_object('id','3.8','ok', v_msg = 'INVALID_MOVE', 'detail','âncora = a própria coleção: '||v_msg);

    begin perform public.move_my_collection(v_b1, v_l0[1], null); v_msg := 'executou';
    exception when others then v_msg := sqlerrm; end;
    res := res || jsonb_build_object('id','3.9','ok', v_msg = 'COLLECTION_NOT_FOUND', 'detail','mover coleção alheia: '||v_msg);

    begin perform public.move_my_collection(v_l0[1], v_b1, null); v_msg := 'executou';
    exception when others then v_msg := sqlerrm; end;
    select array_agg(r.collection_id order by r.ordinality) into v_l from public.get_my_collections(false, 100, 0) with ordinality r;
    res := res || jsonb_build_object('id','3.10','ok', v_msg = 'COLLECTION_NOT_FOUND'
        and v_l = array[v_new, v_l0[4], v_l0[2], v_l0[3], v_l0[1]],
      'detail','âncora alheia: '||v_msg||'; ordem de A intacta');

    begin perform public.move_my_collection(gen_random_uuid(), v_l0[1], null); v_msg := 'executou';
    exception when others then v_msg := sqlerrm; end;
    res := res || jsonb_build_object('id','3.11','ok', v_msg = 'COLLECTION_NOT_FOUND', 'detail','coleção inexistente: mesma resposta');

    select array_agg(r.collection_id order by r.ordinality) into v_l from public.get_my_collections(false, 2, 2) with ordinality r;
    res := res || jsonb_build_object('id','3.12','ok', v_l = array[v_l0[2], v_l0[3]],
      'detail','paginação (limit 2 offset 2) segue a ordem escolhida');
    execute 'reset role';

    -- B: nada mudou e R1 só devolve as dele
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select array_agg(r.collection_id order by r.ordinality) into v_l from public.get_my_collections(false, 100, 0) with ordinality r;
    execute 'reset role';
    res := res || jsonb_build_object('id','3.13','ok',
      v_l = v_lb and cardinality(v_l) = 2
      and not exists (select 1 from public.collection c where c.id in (v_b1, v_b2) and c.library_position is not null),
      'detail','B: R1 só com as 2 coleções dele, ordem e posições intactas');

    begin
      update public.collection set library_position = 0 where id = v_l0[1];
      v_state := 'executou';
    exception when check_violation then v_state := '23514'; end;
    res := res || jsonb_build_object('id','3.14','ok', v_state = '23514', 'detail','CHECK recusa posição 0: '||v_state);

    res := res || jsonb_build_object('id','3.15','ok',
      not exists (select 1 from public.collection_allocation ca where ca.collection_id = any(v_c || v_new))
      and not exists (select 1 from public.collection c where c.id = any(v_c || v_new)
                        and (c.cover_logo_path is not null or c.cover_code is not null or c.lifecycle_status <> 'ACTIVE')),
      'detail','nenhuma alocação, capa ou estado alterado — só a posição');

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
      and (select count(*) from public.collection) = v_base_co
      and (select count(*) from public.collection_allocation) = v_base_ca
      and (select count(*) from public.storage_container) = v_base_sc
      and current_user = session_user,
    'detail','resíduo zero (usuários, coleções, alocações, locais) e papel restaurado');

  for r in select * from jsonb_array_elements(res) loop
    n := n + 1;
    if coalesce((r->>'ok')::boolean, false) then passes := passes + 1; end if;
    seq := n; check_id := r->>'id';
    status := case when coalesce((r->>'ok')::boolean, false) then 'PASS' else 'FAIL' end;
    detail := r->>'detail';
    return next;
  end loop;
  seq := 99; check_id := 'GATE';
  status := case when passes = n and n = 22 then 'PASS' else 'FAIL' end;
  detail := format('%s/%s PASS (esperado 22)', passes, n);
  return next;
end;
$fn$;

select * from pg_temp.rc_5835_validate();
