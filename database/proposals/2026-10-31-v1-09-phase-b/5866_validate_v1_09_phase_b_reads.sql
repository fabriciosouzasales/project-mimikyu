/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5866 - Harness: 5333 get_my_collection_card_variants e
              5334 get_my_pokedex_representative_variants (V1-09 Fase B)
Versão......: 1.1 (READINESS-02: uma única leitura de get_my_collections
              para classificar as coleções de v_owner; antes, 4.1 relia
              o resumo de todas as coleções a cada iteração)
Status......: v1.1 CONFIRMADO EXECUTADO no LIVE em 2026-10-31 — GATE 12/12,
              resíduo zero. Arquivo mantém v_owner como placeholder.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-31

Protocolo (mesmo da 5865): função em pg_temp, uma chamada; usuários
efêmeros; a sentinela TR000 desfaz tudo o que o harness cria; 9.1
confere resíduo zero. Dados reais do usuário de v_owner só são LIDOS
(4.1/4.2). Antes de executar, preencher v_owner (sem isso 4.1/4.2
falham de propósito). Executar SÓ depois de 5333 e 5334 aplicadas.

Checagens (GATE = todas PASS):
  0.1  5333: SECURITY DEFINER, search_path vazio, STABLE, plpgsql, 1 versão
  0.2  5334: idem
  0.3  ACL: EXECUTE só authenticated nas duas (anon e PUBLIC sem acesso)
  1.1  anon: 42501 nas duas
  2.1  sem identidade: 28000 nas duas
  2.2  argumentos inválidos (nulo, vazio, 501 ids): 22023 nas duas
  3.1  fixture Set: 5333 devolve 1 linha por variante, cópias corretas
       (2 variantes da carta X: 2 + 1 exemplares; carta Y: 1)
  3.2  fixture: soma de cópias por carta (5333) = copies_in_collection (5169)
  3.3  isolamento: B lendo a coleção de A = 0 linhas (5333 e 5334);
       coleção inexistente = 0 linhas
  4.1  dados reais (Set/Master Set de v_owner, somente leitura): soma de
       cópias da 5333 por posição = copies_in_collection de 5169/5198
  4.2  dados reais (Pokédex de v_owner, somente leitura): 5334 devolve
       uma linha por posição conquistada da página e a carta do
       representante coincide com a da 5204 (número + Set)
  9.1  resíduo zero (usuários, coleções, vínculos, exemplares) e papel restaurado
Erro inesperado: X.1 FAIL.
================================================================
*/

create or replace function pg_temp.tr_5866_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  -- >>> PREENCHER com o id do seu usuário (auth.users.id) <<<
  v_owner   uuid := '00000000-0000-0000-0000-000000000000';

  v_f1      oid := to_regprocedure('public.get_my_collection_card_variants(uuid,uuid[])');
  v_f2      oid := to_regprocedure('public.get_my_pokedex_representative_variants(uuid,uuid[])');
  p_user_a  uuid := gen_random_uuid();
  p_user_b  uuid := gen_random_uuid();
  v_sfx     text := substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
  v_set     uuid;
  v_card_x  uuid;
  v_card_y  uuid;
  v_vx1     uuid;
  v_vx2     uuid;
  v_vy      uuid;
  v_lang    uuid;
  v_inv_a   uuid;
  v_coll    uuid;
  v_pcs     uuid[];
  v_pc      uuid;
  v_state   text;
  v_state2  text;
  v_rows    integer;
  v_bad     integer;
  v_n       integer;
  v_cid     uuid;
  v_std_ids uuid[];
  v_ms_ids  uuid[];
  v_dex_ids uuid[];
  v_ids     uuid[];
  v_detail  text;
  v_base_us bigint;
  v_base_co bigint;
  v_base_ca bigint;
  v_base_pc bigint;
  res       jsonb := '[]'::jsonb;
  r         jsonb;
  n         integer := 0;
  passes    integer := 0;
  i         integer;
begin
  -- 0. Estrutura e ACL --------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    v_f1 is not null
    and coalesce((select p.prosecdef and p.proconfig = array['search_path=""'] and p.provolatile = 's' and l.lanname = 'plpgsql'
                  from pg_proc p join pg_language l on l.oid = p.prolang where p.oid = v_f1), false)
    and (select count(*) from pg_proc q join pg_namespace ns on ns.oid = q.pronamespace
          where ns.nspname = 'public' and q.proname = 'get_my_collection_card_variants') = 1,
    'detail','5333: SECURITY DEFINER, search_path vazio, STABLE, plpgsql, 1 versão');
  res := res || jsonb_build_object('id','0.2','ok',
    v_f2 is not null
    and coalesce((select p.prosecdef and p.proconfig = array['search_path=""'] and p.provolatile = 's' and l.lanname = 'plpgsql'
                  from pg_proc p join pg_language l on l.oid = p.prolang where p.oid = v_f2), false)
    and (select count(*) from pg_proc q join pg_namespace ns on ns.oid = q.pronamespace
          where ns.nspname = 'public' and q.proname = 'get_my_pokedex_representative_variants') = 1,
    'detail','5334: SECURITY DEFINER, search_path vazio, STABLE, plpgsql, 1 versão');
  res := res || jsonb_build_object('id','0.3','ok',
    v_f1 is not null and v_f2 is not null
    and has_function_privilege('authenticated', v_f1, 'EXECUTE') and has_function_privilege('authenticated', v_f2, 'EXECUTE')
    and not has_function_privilege('anon', v_f1, 'EXECUTE') and not has_function_privilege('anon', v_f2, 'EXECUTE')
    and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid in (v_f1, v_f2) and a.grantee = 0),
    'detail','EXECUTE só authenticated nas duas (anon e PUBLIC sem acesso)');

  select count(*) into v_base_us from auth.users;
  select count(*) into v_base_co from public.collection;
  select count(*) into v_base_ca from public.collection_allocation;
  select count(*) into v_base_pc from public.physical_card;

  begin
    -- 1.1 anon / 2.1 sem identidade ------------------------------------
    perform set_config('request.jwt.claims', '', true);
    execute 'set local role anon';
    begin perform * from public.get_my_collection_card_variants(gen_random_uuid(), array[gen_random_uuid()]); v_state := 'executou';
    exception when others then v_state := sqlstate; end;
    begin perform * from public.get_my_pokedex_representative_variants(gen_random_uuid(), array[gen_random_uuid()]); v_state2 := 'executou';
    exception when others then v_state2 := sqlstate; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.1','ok', v_state = '42501' and v_state2 = '42501',
      'detail', format('anon: 5333 %s, 5334 %s', v_state, v_state2));

    execute 'set local role authenticated';
    begin perform * from public.get_my_collection_card_variants(gen_random_uuid(), array[gen_random_uuid()]); v_state := 'executou';
    exception when others then v_state := sqlstate; end;
    begin perform * from public.get_my_pokedex_representative_variants(gen_random_uuid(), array[gen_random_uuid()]); v_state2 := 'executou';
    exception when others then v_state2 := sqlstate; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','2.1','ok', v_state = '28000' and v_state2 = '28000',
      'detail', format('sem identidade: 5333 %s, 5334 %s', v_state, v_state2));

    -- Fixture (como dono do banco: catálogo só é legível por admin) ------
    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    values (p_user_a, 'authenticated', 'authenticated', 'tr5866-a-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'tr5866a_'||v_sfx, 'display_name', 'TR 5866 A'), now(), now()),
           (p_user_b, 'authenticated', 'authenticated', 'tr5866-b-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'tr5866b_'||v_sfx, 'display_name', 'TR 5866 B'), now(), now());

    -- Carta X com ao menos 2 variantes ativas e carta Y do mesmo Set.
    select c.card_set_id, c.id into v_set, v_card_x
    from public.card c
    join public.card_variant cv on cv.card_id = c.id and cv.is_active
    where c.is_active
    group by c.card_set_id, c.id, c.collector_order
    having count(*) >= 2
    order by c.card_set_id, c.collector_order, c.id
    limit 1;
    select cv.id into v_vx1 from public.card_variant cv where cv.card_id = v_card_x and cv.is_active order by cv.id limit 1;
    select cv.id into v_vx2 from public.card_variant cv where cv.card_id = v_card_x and cv.is_active order by cv.id offset 1 limit 1;
    select c.id, cv.id into v_card_y, v_vy
    from public.card c join public.card_variant cv on cv.card_id = c.id and cv.is_active
    where c.card_set_id = v_set and c.is_active and c.id <> v_card_x
    order by c.collector_order, c.id, cv.id limit 1;
    select l.id into v_lang from public.language l where l.code = 'pt-BR';
    select iv.id into v_inv_a from public.inventory iv where iv.owner_user_id = p_user_a;
    if v_vx2 is null or v_vy is null or v_inv_a is null then
      raise exception 'TR_FIXTURE: catálogo sem carta com 2 variantes ou inventário ausente';
    end if;

    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select c.collection_id into v_coll from public.create_my_card_set_collection(gen_random_uuid(), v_set, 'Set 5866', null) c;
    execute 'reset role';

    v_pcs := '{}';
    foreach v_pc in array array[v_vx1, v_vx1, v_vx2, v_vy] loop
      insert into public.physical_card (card_variant_id, language_id, inventory_id)
      values (v_pc, v_lang, v_inv_a) returning id into v_cid;
      v_pcs := v_pcs || v_cid;
    end loop;
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.allocate_physical_cards_to_collection(v_coll, v_pcs);

    -- 2.2 argumentos inválidos (com identidade) --------------------------
    v_bad := 0;
    v_ids := array(select gen_random_uuid() from generate_series(1, 501));
    begin perform * from public.get_my_collection_card_variants(v_coll, null); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.get_my_collection_card_variants(v_coll, '{}'); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.get_my_collection_card_variants(v_coll, v_ids); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.get_my_pokedex_representative_variants(v_coll, null); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.get_my_pokedex_representative_variants(v_coll, '{}'); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.get_my_pokedex_representative_variants(v_coll, v_ids); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    res := res || jsonb_build_object('id','2.2','ok', v_bad = 0, 'detail', format('%s de 6 chamadas inválidas não recusadas com 22023', v_bad));

    -- 3.1 forma da 5333 na fixture ---------------------------------------
    select count(*),
           count(*) filter (where (t.card_variant_id = v_vx1 and t.copies = 2)
                               or (t.card_variant_id = v_vx2 and t.copies = 1)
                               or (t.card_variant_id = v_vy  and t.copies = 1))
    into v_rows, v_n
    from public.get_my_collection_card_variants(v_coll, array[v_card_x, v_card_y]) t;
    res := res || jsonb_build_object('id','3.1','ok', v_rows = 3 and v_n = 3,
      'detail', format('%s linhas (esperado 3), %s com variante e cópias corretas', v_rows, v_n));

    -- 3.2 equivalência de contagem com a 5169 -----------------------------
    select count(*) into v_bad
    from public.get_my_collection_positions(v_coll, 'OWNED', 500, 0) p
    left join (select t.card_id, sum(t.copies)::integer as s
               from public.get_my_collection_card_variants(v_coll, array[v_card_x, v_card_y]) t
               group by t.card_id) v on v.card_id = p.card_id
    where coalesce(v.s, 0) <> p.copies_in_collection;
    res := res || jsonb_build_object('id','3.2','ok', v_bad = 0, 'detail', format('%s cartas com soma divergente da 5169', v_bad));

    -- 3.3 isolamento -----------------------------------------------------
    select count(*) into v_rows from public.get_my_collection_card_variants(gen_random_uuid(), array[v_card_x]);
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select v_rows + count(*) into v_rows from public.get_my_collection_card_variants(v_coll, array[v_card_x, v_card_y]);
    select v_rows + count(*) into v_rows from public.get_my_pokedex_representative_variants(v_coll, array[gen_random_uuid()]);
    execute 'reset role';
    res := res || jsonb_build_object('id','3.3','ok', v_rows = 0, 'detail', 'B→A e coleção inexistente: '||v_rows||' linhas (esperado 0)');

    -- 4. Dados reais de v_owner (somente leitura) ------------------------
    if v_owner = '00000000-0000-0000-0000-000000000000'::uuid
       or not exists (select 1 from auth.users u where u.id = v_owner) then
      res := res || jsonb_build_object('id','4.1','ok', false, 'detail','v_owner não preenchido ou inexistente');
      res := res || jsonb_build_object('id','4.2','ok', false, 'detail','v_owner não preenchido ou inexistente');
    else
      perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role','authenticated')::text, true);
      execute 'set local role authenticated';

      -- Coleções de v_owner classificadas numa única leitura de R1 (5182).
      select coalesce(array_agg(g.collection_id) filter (where g.completion_policy = 'STANDARD_SET'), '{}'),
             coalesce(array_agg(g.collection_id) filter (where g.completion_policy = 'MASTER_SET'), '{}'),
             coalesce(array_agg(g.collection_id) filter (where g.completion_policy = 'REFERENCE_POSITION'), '{}')
      into v_std_ids, v_ms_ids, v_dex_ids
      from public.get_my_collections(true, 100, 0) g;

      -- 4.1 Set e Master Set
      v_bad := 0; v_n := 0; v_detail := '';
      foreach v_cid in array v_std_ids || v_ms_ids loop
        v_n := v_n + 1;
        if v_cid = any(v_std_ids) then
          select array_agg(p.card_id) into v_ids from public.get_my_collection_positions(v_cid, 'OWNED', 500, 0) p;
          if v_ids is not null then
            select v_bad + count(*) into v_bad
            from public.get_my_collection_positions(v_cid, 'OWNED', 500, 0) p
            left join (select t.card_id, sum(t.copies)::integer as s
                       from public.get_my_collection_card_variants(v_cid, v_ids) t group by t.card_id) v on v.card_id = p.card_id
            where coalesce(v.s, 0) <> p.copies_in_collection;
          end if;
        else
          select array_agg(distinct p.card_id) into v_ids from public.get_my_master_set_positions(v_cid, 'OWNED', 500, 0) p;
          if v_ids is not null then
            select v_bad + count(*) into v_bad
            from public.get_my_master_set_positions(v_cid, 'OWNED', 500, 0) p
            left join lateral (
              select sum(t.copies)::integer as s
              from public.get_my_collection_card_variants(v_cid, v_ids) t
              where t.card_id = p.card_id and (p.variant_type_id is null or t.variant_type_id = p.variant_type_id)
            ) v on true
            where coalesce(v.s, 0) <> p.copies_in_collection;
          end if;
        end if;
      end loop;
      res := res || jsonb_build_object('id','4.1','ok', v_n > 0 and v_bad = 0,
        'detail', format('%s coleções de Set/Master Set, %s posições com soma divergente', v_n, v_bad));

      -- 4.2 Pokédex
      v_bad := 0; v_n := 0; v_rows := 0;
      foreach v_cid in array v_dex_ids loop
        v_n := v_n + 1;
        select array_agg(p.pokedex_position_id) into v_ids from public.get_my_pokedex_positions(v_cid, 'OWNED', null, 120, 0) p;
        if v_ids is not null then
          select v_rows + count(*) into v_rows from public.get_my_pokedex_representative_variants(v_cid, v_ids);
          select v_bad + count(*) into v_bad
          from public.get_my_pokedex_positions(v_cid, 'OWNED', null, 120, 0) p
          left join public.get_my_pokedex_representative_variants(v_cid, v_ids) t on t.pokedex_position_id = p.pokedex_position_id
          where t.pokedex_position_id is null
             or t.collector_number is distinct from p.representative_collector_number
             or t.card_set_code is distinct from p.representative_set_code;
        end if;
      end loop;
      execute 'reset role';
      res := res || jsonb_build_object('id','4.2','ok', v_bad = 0,
        'detail', format('%s coleções Pokédex, %s representantes lidos, %s divergentes da 5204%s',
                         v_n, v_rows, v_bad, case when v_n = 0 then ' (sem Pokédex: só verifica ausência de erro)' else '' end));
    end if;

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
      and (select count(*) from public.collection) = v_base_co
      and (select count(*) from public.collection_allocation) = v_base_ca
      and (select count(*) from public.physical_card) = v_base_pc
      and current_user = session_user,
    'detail','resíduo zero (usuários, coleções, vínculos, exemplares) e papel restaurado');

  for r in select * from jsonb_array_elements(res) loop
    n := n + 1;
    if coalesce((r->>'ok')::boolean, false) then passes := passes + 1; end if;
    seq := n; check_id := r->>'id';
    status := case when coalesce((r->>'ok')::boolean, false) then 'PASS' else 'FAIL' end;
    detail := r->>'detail';
    return next;
  end loop;
  seq := 99; check_id := 'GATE';
  status := case when passes = n and n = 12 then 'PASS' else 'FAIL' end;
  detail := format('%s/%s PASS (esperado 12)', passes, n);
  return next;
end;
$fn$;

select * from pg_temp.tr_5866_validate();
