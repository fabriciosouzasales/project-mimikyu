/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5868 - Harness: Favorite de Card (V1-10) — 5335 e 5336
Versão......: 1.1 (READINESS-03: 3.7 remove o exemplar pela via oficial,
              remove_my_physical_card/5165, como o próprio usuário)
Status......: CONFIRMADO EXECUTADO no LIVE (EXECUTION-04, 2026-10-31): GATE 15/15 PASS,
              sem X.1, resíduo zero. Nota: a base vigente de remove_my_physical_card é a
              5289 (P3B-S5, corpo = LIVE), que estende a 5165 sem mudar o contrato.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-31

Protocolo (o mesmo da 5865/5866): função em pg_temp, uma chamada;
usuários efêmeros A e B; a sentinela TR000 desfaz tudo o que o harness
cria; 9.1 confere resíduo zero. Não lê nem altera dados reais de nenhum
usuário. Executar SÓ depois de 5335 e 5336 aplicadas.

Checagens (GATE = todas PASS, 15):
  0.1  tabela: PK (user_id, card_id); FK user CASCADE; FK card RESTRICT;
       RLS ativa; 1 policy (SELECT); authenticated só SELECT; anon nada
  0.2  4 funções: SECURITY DEFINER, search_path vazio, plpgsql, 1 versão;
       set VOLATILE, leituras STABLE
  0.3  ACL: EXECUTE só authenticated nas 4 (anon e PUBLIC sem acesso)
  1.1  anon: 42501 nas 4 funções e no SELECT da tabela
  2.1  authenticated sem identidade: 28000 nas 4
  2.2  argumentos inválidos: 22023 (estado nulo, carta nula, lotes nulo/
       vazio/501, página fora dos limites); carta inexistente: P0002
  3.1  favoritar carta não possuída: true; aparece no lote
  3.2  idempotência: favoritar de novo = 1 linha; desfavoritar 2× = 0
       linhas, sem erro
  3.3  isolamento: B não vê nem remove o favorito de A (lote, página,
       SELECT direto, set false de B)
  3.4  escrita direta bloqueada: INSERT/DELETE na tabela como
       authenticated = 42501
  3.5  lote por variante: carta e estado corretos para variante
       favoritada (2 variantes da mesma carta → ambas true) e não
       favoritada; variante inexistente omitida
  3.6  página: mais recente primeiro e total_count correto (o catálogo
       não é alterado: o filtro de carta inativa é coberto só por revisão)
  3.7  independência do acervo: favorito permanece após o próprio usuário
       remover o exemplar pela via oficial (remove_my_physical_card, 5165)
  3.8  limite de leitura: p_limit 100 aceito; 101 recusado (coberto em
       2.2) e a página respeita o limite pedido (limit 1 → 1 linha)
  9.1  resíduo zero (usuários, favoritos, exemplares) e papel restaurado
Erro inesperado: X.1 FAIL.
================================================================
*/

create or replace function pg_temp.tr_5868_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  v_t       oid := to_regclass('public.card_favorite');
  v_f1      oid := to_regprocedure('public.set_card_favorite(uuid,boolean)');
  v_f2      oid := to_regprocedure('public.get_my_card_favorite_ids(uuid[])');
  v_f3      oid := to_regprocedure('public.get_my_card_favorites_by_variant(uuid[])');
  v_f4      oid := to_regprocedure('public.get_my_favorite_cards(integer,integer)');
  p_user_a  uuid := gen_random_uuid();
  p_user_b  uuid := gen_random_uuid();
  v_sfx     text := substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
  v_card_x  uuid;
  v_card_y  uuid;
  v_vx1     uuid;
  v_vx2     uuid;
  v_vy      uuid;
  v_lang    uuid;
  v_inv_a   uuid;
  v_pc      uuid;
  v_ok      boolean;
  v_s       text[];
  v_bad     integer;
  v_n       integer;
  v_m       integer;
  v_ids     uuid[];
  v_first   uuid;
  v_total   bigint;
  v_base_us bigint;
  v_base_cf bigint;
  v_base_pc bigint;
  res       jsonb := '[]'::jsonb;
  r         jsonb;
  n         integer := 0;
  passes    integer := 0;
begin
  -- 0. Estrutura e ACL ----------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    v_t is not null
    and exists (select 1 from pg_constraint c where c.conrelid = v_t and c.contype = 'p'
                and pg_get_constraintdef(c.oid) = 'PRIMARY KEY (user_id, card_id)')
    and exists (select 1 from pg_constraint c where c.conrelid = v_t and c.contype = 'f'
                and c.confrelid = 'auth.users'::regclass and c.confdeltype = 'c')
    and exists (select 1 from pg_constraint c where c.conrelid = v_t and c.contype = 'f'
                and c.confrelid = 'public.card'::regclass and c.confdeltype = 'r')
    and (select relrowsecurity from pg_class where oid = v_t)
    and (select count(*) from pg_policy p where p.polrelid = v_t) = 1
    and (select count(*) from pg_policy p where p.polrelid = v_t and p.polcmd = 'r') = 1
    and has_table_privilege('authenticated', v_t, 'SELECT')
    and not has_table_privilege('authenticated', v_t, 'INSERT')
    and not has_table_privilege('authenticated', v_t, 'UPDATE')
    and not has_table_privilege('authenticated', v_t, 'DELETE')
    and not has_table_privilege('anon', v_t, 'SELECT'),
    'detail','card_favorite: PK, FK user CASCADE, FK card RESTRICT, RLS + 1 policy SELECT, authenticated só SELECT, anon nada');

  res := res || jsonb_build_object('id','0.2','ok',
    v_f1 is not null and v_f2 is not null and v_f3 is not null and v_f4 is not null
    and (select bool_and(p.prosecdef and p.proconfig = array['search_path=""'] and l.lanname = 'plpgsql')
         from pg_proc p join pg_language l on l.oid = p.prolang where p.oid in (v_f1, v_f2, v_f3, v_f4))
    and (select provolatile from pg_proc where oid = v_f1) = 'v'
    and (select bool_and(provolatile = 's') from pg_proc where oid in (v_f2, v_f3, v_f4))
    and (select count(*) from pg_proc q join pg_namespace ns on ns.oid = q.pronamespace
         where ns.nspname = 'public'
           and q.proname in ('set_card_favorite','get_my_card_favorite_ids','get_my_card_favorites_by_variant','get_my_favorite_cards')) = 4,
    'detail','4 funções: SECURITY DEFINER, search_path vazio, plpgsql, 1 versão; set VOLATILE, leituras STABLE');

  res := res || jsonb_build_object('id','0.3','ok',
    v_f1 is not null and v_f2 is not null and v_f3 is not null and v_f4 is not null
    and (select bool_and(has_function_privilege('authenticated', x, 'EXECUTE') and not has_function_privilege('anon', x, 'EXECUTE'))
         from unnest(array[v_f1, v_f2, v_f3, v_f4]) x)
    and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid in (v_f1, v_f2, v_f3, v_f4) and a.grantee = 0),
    'detail','EXECUTE só authenticated nas 4 (anon e PUBLIC sem acesso)');

  select count(*) into v_base_us from auth.users;
  select count(*) into v_base_cf from public.card_favorite;
  select count(*) into v_base_pc from public.physical_card;

  begin
    -- 1.1 anon ------------------------------------------------------------
    perform set_config('request.jwt.claims', '', true);
    execute 'set local role anon';
    v_s := '{}';
    begin perform public.set_card_favorite(gen_random_uuid(), true); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    begin perform * from public.get_my_card_favorite_ids(array[gen_random_uuid()]); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    begin perform * from public.get_my_card_favorites_by_variant(array[gen_random_uuid()]); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    begin perform * from public.get_my_favorite_cards(10, 0); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    begin perform 1 from public.card_favorite; v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.1','ok', v_s = array['42501','42501','42501','42501','42501'],
      'detail', 'anon: '||array_to_string(v_s, ', '));

    -- 2.1 sem identidade ---------------------------------------------------
    execute 'set local role authenticated';
    v_s := '{}';
    begin perform public.set_card_favorite(gen_random_uuid(), true); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    begin perform * from public.get_my_card_favorite_ids(array[gen_random_uuid()]); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    begin perform * from public.get_my_card_favorites_by_variant(array[gen_random_uuid()]); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    begin perform * from public.get_my_favorite_cards(10, 0); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','2.1','ok', v_s = array['28000','28000','28000','28000'],
      'detail', 'sem identidade: '||array_to_string(v_s, ', '));

    -- Fixture (como dono do banco: catálogo só é legível por admin) --------
    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    values (p_user_a, 'authenticated', 'authenticated', 'tr5868-a-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'tr5868a_'||v_sfx, 'display_name', 'TR 5868 A'), now(), now()),
           (p_user_b, 'authenticated', 'authenticated', 'tr5868-b-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'tr5868b_'||v_sfx, 'display_name', 'TR 5868 B'), now(), now());

    select c.id into v_card_x
    from public.card c join public.card_variant cv on cv.card_id = c.id and cv.is_active
    where c.is_active
    group by c.id having count(*) >= 2
    order by c.id limit 1;
    select cv.id into v_vx1 from public.card_variant cv where cv.card_id = v_card_x and cv.is_active order by cv.id limit 1;
    select cv.id into v_vx2 from public.card_variant cv where cv.card_id = v_card_x and cv.is_active order by cv.id offset 1 limit 1;
    select c.id, cv.id into v_card_y, v_vy
    from public.card c join public.card_variant cv on cv.card_id = c.id and cv.is_active
    where c.is_active and c.id <> v_card_x
    order by c.id, cv.id limit 1;
    select l.id into v_lang from public.language l where l.code = 'pt-BR';
    select iv.id into v_inv_a from public.inventory iv where iv.owner_user_id = p_user_a;
    if v_vx2 is null or v_vy is null or v_inv_a is null then
      raise exception 'TR_FIXTURE: catálogo sem carta com 2 variantes ou inventário ausente';
    end if;

    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';

    -- 2.2 argumentos inválidos ---------------------------------------------
    v_bad := 0;
    v_ids := array(select gen_random_uuid() from generate_series(1, 501));
    begin perform public.set_card_favorite(v_card_x, null); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform public.set_card_favorite(null, true); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform public.set_card_favorite(gen_random_uuid(), true); v_bad := v_bad + 1; exception when sqlstate 'P0002' then null; end;
    begin perform * from public.get_my_card_favorite_ids(null); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.get_my_card_favorite_ids('{}'); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.get_my_card_favorite_ids(v_ids); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.get_my_card_favorites_by_variant(null); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.get_my_card_favorites_by_variant('{}'); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.get_my_card_favorites_by_variant(v_ids); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.get_my_favorite_cards(0, 0); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.get_my_favorite_cards(101, 0); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.get_my_favorite_cards(10, -1); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    res := res || jsonb_build_object('id','2.2','ok', v_bad = 0, 'detail', format('%s de 12 chamadas inválidas não recusadas com o código esperado', v_bad));

    -- 3.1 favoritar carta não possuída --------------------------------------
    v_ok := public.set_card_favorite(v_card_x, true);
    select count(*) into v_n from public.get_my_card_favorite_ids(array[v_card_x, v_card_y]) t where t.card_id = v_card_x;
    select count(*) into v_m from public.get_my_card_favorite_ids(array[v_card_x, v_card_y]);
    res := res || jsonb_build_object('id','3.1','ok', v_ok and v_n = 1 and v_m = 1,
      'detail', format('retorno %s; lote: X %s, total %s (esperado true/1/1)', v_ok, v_n, v_m));

    -- 3.2 idempotência ---------------------------------------------------------
    v_ok := public.set_card_favorite(v_card_x, true);
    select count(*) into v_n from public.card_favorite f where f.user_id = p_user_a and f.card_id = v_card_x;
    v_bad := case when v_ok and v_n = 1 then 0 else 1 end;
    v_ok := public.set_card_favorite(v_card_x, false);
    v_ok := (not v_ok) and not public.set_card_favorite(v_card_x, false);
    select count(*) into v_m from public.card_favorite f where f.user_id = p_user_a and f.card_id = v_card_x;
    res := res || jsonb_build_object('id','3.2','ok', v_bad = 0 and v_ok and v_m = 0,
      'detail', format('favoritar 2×: %s linha; desfavoritar 2×: %s linhas', v_n, v_m));

    -- 3.3 isolamento -------------------------------------------------------------
    perform public.set_card_favorite(v_card_x, true);
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select count(*) into v_n from public.get_my_card_favorite_ids(array[v_card_x]);
    select v_n + count(*) into v_n from public.get_my_favorite_cards(100, 0);
    select v_n + count(*) into v_n from public.card_favorite;
    select v_n + count(*) into v_n from public.get_my_card_favorites_by_variant(array[v_vx1]) t where t.is_favorite;
    perform public.set_card_favorite(v_card_x, false);
    execute 'reset role';
    select count(*) into v_m from public.card_favorite f where f.user_id = p_user_a and f.card_id = v_card_x;
    res := res || jsonb_build_object('id','3.3','ok', v_n = 0 and v_m = 1,
      'detail', format('B enxergou %s registros de A (esperado 0); favorito de A após set false de B: %s (esperado 1)', v_n, v_m));

    -- 3.4 escrita direta bloqueada ----------------------------------------------
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    v_s := '{}';
    begin insert into public.card_favorite (user_id, card_id) values (p_user_a, v_card_y); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    begin delete from public.card_favorite where card_id = v_card_x; v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    res := res || jsonb_build_object('id','3.4','ok', v_s = array['42501','42501'],
      'detail', 'INSERT/DELETE direto como authenticated: '||array_to_string(v_s, ', '));

    -- 3.5 lote por variante ---------------------------------------------------------
    select count(*) filter (where (t.card_variant_id in (v_vx1, v_vx2) and t.card_id = v_card_x and t.is_favorite)
                               or (t.card_variant_id = v_vy and t.card_id = v_card_y and not t.is_favorite)),
           count(*)
    into v_n, v_m
    from public.get_my_card_favorites_by_variant(array[v_vx1, v_vx2, v_vy, gen_random_uuid()]) t;
    res := res || jsonb_build_object('id','3.5','ok', v_n = 3 and v_m = 3,
      'detail', format('%s linhas (esperado 3: inexistente omitida), %s corretas', v_m, v_n));

    -- 3.6 página: mais recente primeiro ---------------------------------------------
    perform public.set_card_favorite(v_card_y, true);
    execute 'reset role';
    -- now() é o mesmo na transação: o fixture recua o favorito de X (dono do banco).
    update public.card_favorite set created_at = now() - interval '1 minute'
    where user_id = p_user_a and card_id = v_card_x;
    execute 'set local role authenticated';
    select (array_agg(t.card_id order by t.favorited_at desc, t.card_id))[1], max(t.total_count), count(*)
    into v_first, v_total, v_n
    from public.get_my_favorite_cards(100, 0) t;
    res := res || jsonb_build_object('id','3.6','ok', v_first = v_card_y and v_total = 2 and v_n = 2,
      'detail', format('primeira = Y: %s; total_count %s; linhas %s (esperado true/2/2)', v_first = v_card_y, v_total, v_n));

    -- 3.8 limite respeitado ---------------------------------------------------------------
    select count(*), max(t.total_count) into v_n, v_total from public.get_my_favorite_cards(1, 0) t;
    select count(*) into v_m from public.get_my_favorite_cards(1, 1) t where t.card_id = v_card_x;
    res := res || jsonb_build_object('id','3.8','ok', v_n = 1 and v_total = 2 and v_m = 1,
      'detail', format('limit 1: %s linha, total_count %s; offset 1 traz X: %s', v_n, v_total, v_m = 1));
    execute 'reset role';

    -- 3.7 independência do acervo ---------------------------------------------------
    -- O exemplar entra como na 5866 (fixture, dono do banco) e sai pela via oficial do
    -- produto: remove_my_physical_card (5165) chamada pelo próprio A — sem DELETE direto.
    insert into public.physical_card (card_variant_id, language_id, inventory_id)
    values (v_vx1, v_lang, v_inv_a) returning id into v_pc;
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    v_ok := public.remove_my_physical_card(v_pc);
    execute 'reset role';
    select count(*) into v_m from public.physical_card where id = v_pc;
    select count(*) into v_n from public.card_favorite f where f.user_id = p_user_a and f.card_id = v_card_x;
    res := res || jsonb_build_object('id','3.7','ok', v_ok and v_m = 0 and v_n = 1,
      'detail', format('remove_my_physical_card: %s; exemplar restante: %s (esperado 0); favorito de X: %s (esperado 1)', v_ok, v_m, v_n));

    raise exception 'TR000' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'TR000' then
      res := res || jsonb_build_object('id','X.1','ok', false, 'detail','erro inesperado: '||sqlstate||' '||sqlerrm);
    end if;
  end;

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  res := res || jsonb_build_object('id','9.1','ok',
    (select count(*) from auth.users) = v_base_us
      and (select count(*) from public.card_favorite) = v_base_cf
      and (select count(*) from public.physical_card) = v_base_pc
      and current_user = session_user,
    'detail','resíduo zero (usuários, favoritos, exemplares) e papel restaurado');

  for r in select * from jsonb_array_elements(res) loop
    n := n + 1;
    if coalesce((r->>'ok')::boolean, false) then passes := passes + 1; end if;
    seq := n; check_id := r->>'id';
    status := case when coalesce((r->>'ok')::boolean, false) then 'PASS' else 'FAIL' end;
    detail := r->>'detail';
    return next;
  end loop;
  seq := 99; check_id := 'GATE';
  status := case when passes = n and n = 15 then 'PASS' else 'FAIL' end;
  detail := format('%s/%s PASS (esperado 15)', passes, n);
  return next;
end;
$fn$;

select * from pg_temp.tr_5868_validate();
