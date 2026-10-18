/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5834 - Harness: Código opcional da Coleção livre
              (5179 coluna + 5180 RPC)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-18 — 21/21 PASS, GATE PASS, resíduo zero
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-18

Mesmo protocolo de 5832/5833: um único statement (criar a função
temporária e chamar `select * from pg_temp.rc_5834_validate();` na mesma
chamada), usuários de teste efêmeros em auth.users, tudo desfeito pela
sentinela LI000 e resíduo zero conferido no fim (9.1). Não toca dados reais.

Checagens:
  0.x  estrutura: coluna nula + CHECK; função SECURITY DEFINER,
       search_path vazio, ACL só authenticated; não referencia cartas.
  1.1  anon → 42501        2.1  sem identidade → 28000
  3.x  RPC: define e normaliza; idempotente; remove (NULL e vazio);
       formatos inválidos (curto, longo, símbolo); coleção de Set
       recusada; coleção alheia e inexistente (mesma resposta, sem
       alterar a alheia); mesmo código em duas coleções (não é único);
       CHECK recusa valor fora do formato; nenhuma alocação criada.
  4.1  RLS: outro usuário não lê o código.
  9.1  resíduo zero.
GATE: n = 21 e todas PASS.
================================================================
*/

create or replace function pg_temp.rc_5834_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  v_fn      oid := to_regprocedure('public.set_my_collection_cover_code(uuid,text)');
  p_user_a  uuid := gen_random_uuid();
  p_user_b  uuid := gen_random_uuid();
  v_sfx     text := substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
  v_set     uuid;
  v_free_a  uuid;
  v_free_a2 uuid;
  v_free_b  uuid;
  v_set_a   uuid;
  v_code    text;
  v_state   text;
  v_msg     text;
  v_cnt     bigint;
  v_base_us bigint;
  v_base_co bigint;
  v_base_ca bigint;
  v_base_sc bigint;
  res       jsonb := '[]'::jsonb;
  r         jsonb;
  n         integer := 0;
  passes    integer := 0;
begin
  -- 0. Estrutura
  res := res || jsonb_build_object('id','0.1','ok',
    exists (select 1 from information_schema.columns c
            where c.table_schema = 'public' and c.table_name = 'collection'
              and c.column_name = 'cover_code' and c.is_nullable = 'YES' and c.column_default is null)
    and exists (select 1 from pg_constraint k
                where k.conrelid = 'public.collection'::regclass and k.conname = 'chk_collection_cover_code'),
    'detail','collection.cover_code (nulo, sem default) + CHECK de formato');
  res := res || jsonb_build_object('id','0.2','ok',
    coalesce((select p.prosecdef and p.proconfig = array['search_path=""'] from pg_proc p where p.oid = v_fn), false)
    and v_fn is not null
    and has_function_privilege('authenticated', v_fn, 'EXECUTE')
    and not has_function_privilege('anon', v_fn, 'EXECUTE')
    and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = v_fn and a.grantee = 0),
    'detail','5180: SECURITY DEFINER, search_path vazio, EXECUTE só authenticated');
  res := res || jsonb_build_object('id','0.3','ok',
    coalesce((select position('collection_allocation' in p.prosrc) = 0 and position('physical_card' in p.prosrc) = 0
              from pg_proc p where p.oid = v_fn), false),
    'detail','5180 não referencia cartas nem alocações');

  select count(*) into v_base_us from auth.users;
  select count(*) into v_base_co from public.collection;
  select count(*) into v_base_ca from public.collection_allocation;
  select count(*) into v_base_sc from public.storage_container;

  begin
    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    values (p_user_a, 'authenticated', 'authenticated', 'rc5834-a-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'rc5834a_'||v_sfx, 'display_name', 'RC 5834 A'), now(), now()),
           (p_user_b, 'authenticated', 'authenticated', 'rc5834-b-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'rc5834b_'||v_sfx, 'display_name', 'RC 5834 B'), now(), now());

    select cs.id into v_set
    from public.card_set cs join public.expansion e on e.id = cs.expansion_id
    join public.game g on g.id = e.game_id and g.code = 'POKEMON'
    order by cs.id limit 1;

    -- Coleções de teste pelos contratos oficiais (5175 livre, 5167 de Set).
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select c.collection_id into v_free_a  from public.create_my_free_collection(gen_random_uuid(), 'Livre A 5834', null) c;
    select c.collection_id into v_free_a2 from public.create_my_free_collection(gen_random_uuid(), 'Livre A2 5834',
      (select sc.id from public.storage_container sc join public.inventory i on i.id = sc.inventory_id
        where i.owner_user_id = p_user_a limit 1)) c;
    select c.collection_id into v_set_a
    from public.create_my_card_set_collection(gen_random_uuid(), v_set, 'Set A 5834',
      (select sc.id from public.storage_container sc join public.inventory i on i.id = sc.inventory_id
        where i.owner_user_id = p_user_a limit 1)) c;
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select c.collection_id into v_free_b from public.create_my_free_collection(gen_random_uuid(), 'Livre B 5834', null) c;
    perform public.set_my_collection_cover_code(v_free_b, 'BBB');
    execute 'reset role';

    -- 1.1 anon / 2.1 sem identidade
    perform set_config('request.jwt.claims', '', true);
    execute 'set local role anon';
    begin perform public.set_my_collection_cover_code(v_free_a, 'MMK'); v_state := 'executou';
    exception when others then v_state := sqlstate; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.1','ok', v_state = '42501', 'detail','anon: '||v_state);

    execute 'set local role authenticated';
    begin perform public.set_my_collection_cover_code(v_free_a, 'MMK'); v_state := 'executou';
    exception when others then v_state := sqlstate; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','2.1','ok', v_state = '28000', 'detail','sem identidade: '||v_state);

    -- 3.x como A
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';

    v_code := public.set_my_collection_cover_code(v_free_a, '  mmk1 ');
    res := res || jsonb_build_object('id','3.1','ok',
      v_code = 'MMK1' and (select c.cover_code from public.collection c where c.id = v_free_a) = 'MMK1',
      'detail','define e normaliza (" mmk1 " → '||coalesce(v_code,'NULL')||')');

    v_code := public.set_my_collection_cover_code(v_free_a, 'MMK1');
    res := res || jsonb_build_object('id','3.2','ok', v_code = 'MMK1', 'detail','repetir o mesmo valor é idempotente');

    begin perform public.set_my_collection_cover_code(v_free_a, 'A'); v_msg := 'executou';
    exception when others then v_msg := sqlerrm; end;
    res := res || jsonb_build_object('id','3.3','ok', v_msg = 'INVALID_COVER_CODE', 'detail','1 caractere: '||v_msg);

    begin perform public.set_my_collection_cover_code(v_free_a, 'ABCDEFG'); v_msg := 'executou';
    exception when others then v_msg := sqlerrm; end;
    res := res || jsonb_build_object('id','3.4','ok', v_msg = 'INVALID_COVER_CODE', 'detail','7 caracteres: '||v_msg);

    begin perform public.set_my_collection_cover_code(v_free_a, 'AB-1'); v_msg := 'executou';
    exception when others then v_msg := sqlerrm; end;
    res := res || jsonb_build_object('id','3.5','ok', v_msg = 'INVALID_COVER_CODE'
        and (select c.cover_code from public.collection c where c.id = v_free_a) = 'MMK1',
      'detail','símbolo recusado e código anterior mantido: '||v_msg);

    begin perform public.set_my_collection_cover_code(v_set_a, 'SET'); v_state := 'executou'; v_msg := '';
    exception when others then v_state := sqlstate; v_msg := sqlerrm; end;
    res := res || jsonb_build_object('id','3.6','ok', v_msg = 'NOT_FREE_COLLECTION', 'detail','coleção de Set: '||v_state||' '||v_msg);

    begin perform public.set_my_collection_cover_code(v_free_b, 'HACK'); v_msg := 'executou';
    exception when others then v_msg := sqlerrm; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','3.7','ok', v_msg = 'COLLECTION_NOT_FOUND'
        and (select c.cover_code from public.collection c where c.id = v_free_b) = 'BBB',
      'detail','coleção alheia: '||v_msg||'; código de B intacto');
    execute 'set local role authenticated';

    begin perform public.set_my_collection_cover_code(gen_random_uuid(), 'MMK'); v_msg := 'executou';
    exception when others then v_msg := sqlerrm; end;
    res := res || jsonb_build_object('id','3.8','ok', v_msg = 'COLLECTION_NOT_FOUND', 'detail','coleção inexistente: mesma resposta');

    v_code := public.set_my_collection_cover_code(v_free_a2, 'mmk1');
    res := res || jsonb_build_object('id','3.9','ok', v_code = 'MMK1', 'detail','mesmo código em outra coleção do dono é aceito (não é único)');

    v_code := public.set_my_collection_cover_code(v_free_a, null);
    res := res || jsonb_build_object('id','3.10','ok',
      v_code is null and (select c.cover_code from public.collection c where c.id = v_free_a) is null,
      'detail','NULL remove o código (opcional)');

    perform public.set_my_collection_cover_code(v_free_a, 'XY');
    v_code := public.set_my_collection_cover_code(v_free_a, '   ');
    res := res || jsonb_build_object('id','3.11','ok',
      v_code is null and (select c.cover_code from public.collection c where c.id = v_free_a) is null,
      'detail','vazio/espaços também remove');

    v_code := public.set_my_collection_cover_code(v_free_a, 'a1b2c3');
    res := res || jsonb_build_object('id','3.12','ok', v_code = 'A1B2C3', 'detail','6 caracteres, letras e números: '||coalesce(v_code,'NULL'));
    execute 'reset role';

    -- 4.1 B não lê o código de A (RLS select-own)
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select count(*) into v_cnt from public.collection c where c.id in (v_free_a, v_free_a2);
    execute 'reset role';
    res := res || jsonb_build_object('id','4.1','ok', v_cnt = 0, 'detail', format('B não vê coleções de A (%s)', v_cnt));

    -- 3.13 CHECK como defesa em profundidade (escrita direta privilegiada)
    begin
      update public.collection set cover_code = 'abc' where id = v_free_a;
      v_state := 'executou';
    exception when check_violation then v_state := '23514'; end;
    res := res || jsonb_build_object('id','3.13','ok', v_state = '23514', 'detail','CHECK recusa minúsculas: '||v_state);

    res := res || jsonb_build_object('id','3.14','ok',
      not exists (select 1 from public.collection_allocation ca where ca.collection_id in (v_free_a, v_free_a2, v_free_b, v_set_a))
      and (select c.cover_code from public.collection c where c.id = v_set_a) is null,
      'detail','nenhuma alocação criada; coleção de Set sem código');

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
  status := case when passes = n and n = 21 then 'PASS' else 'FAIL' end;
  detail := format('%s/%s PASS (esperado 21)', passes, n);
  return next;
end;
$fn$;

select * from pg_temp.rc_5834_validate();
