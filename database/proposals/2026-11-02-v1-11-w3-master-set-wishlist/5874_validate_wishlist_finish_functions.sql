/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5874 - Harness: Lista de desejos por acabamento (V1-11 W3) — 5348
Versão......: 1.0
Status......: v1.0 EXECUTADA no LIVE (LIVE SQL VALIDATION-02, 2026-11-02):
              GATE PASS 14/14, sem X.1, resíduo zero. 3.4 cobriu só carta
              inexistente — catálogo sem carta inativa com variante.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-02

Protocolo (o mesmo da 5873): função em pg_temp, uma chamada; usuários
efêmeros A e B; a sentinela TR000 desfaz tudo o que o harness cria; 9.1
confere resíduo zero. Não lê nem altera dados reais de nenhum usuário e
não altera o catálogo (o catálogo só é LIDO, como dono do banco, para
calcular o esperado).

Checagens (GATE = todas PASS, 14):
  0.1  2 funções: SECURITY DEFINER, search_path vazio, plpgsql, STABLE,
       1 versão cada
  0.2  ACL: EXECUTE só authenticated (anon e PUBLIC sem acesso)
  1.1  anon: 42501 nas 2
  2.1  authenticated sem identidade: 28000 nas 2
  2.2  argumentos inválidos: 22023 (carta nula; lote nulo, vazio, 501)
  3.1  filtro por acabamento: para até 300 pares (carta ativa, acabamento
       de variante ativa), a função devolve EXATAMENTE as variantes ativas
       daquele acabamento (nenhuma a mais, nenhuma a menos)
  3.2  acabamento NULL (posição secreta) = todas as variantes ativas da
       carta — mesmo conjunto e mesma ordem de 5163, em até 200 cartas
  3.3  variante inativa nunca é oferecida (nem no acabamento dela, nem
       com NULL)
  3.4  carta inexistente → 0 linhas; carta inativa (se o catálogo tiver
       uma com variante) → 0 linhas
  3.5  estado: desejo "qualquer idioma" aparece com o acabamento da
       variante, o id do desejo e idioma NULL
  3.6  equivalência com 5346: mesmas linhas (carta, variante, desejo,
       idioma) que get_my_wishlist_state_by_card, com 3 desejos em 2
       variantes e 2 idiomas
  3.7  isolamento: B não vê nada de A
  3.8  desejo de variante desativada continua visível (C-214), com o
       acabamento dela
  9.1  resíduo zero (usuários, desejos) e papel restaurado
Erro inesperado: X.1 FAIL.
================================================================
*/

create or replace function pg_temp.tr_5874_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  v_f1      oid := to_regprocedure('public.get_catalog_card_variants_for_finish(uuid,uuid)');
  v_f2      oid := to_regprocedure('public.get_my_wishlist_state_by_card_finish(uuid[])');
  p_user_a  uuid := gen_random_uuid();
  p_user_b  uuid := gen_random_uuid();
  v_sfx     text := substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
  v_pairs   jsonb;
  v_cards   uuid[];
  v_card_x  uuid;
  v_vx1     uuid;
  v_vx2     uuid;
  v_vt1     uuid;
  v_vin     uuid;
  v_vin_vt  uuid;
  v_card_in uuid;
  v_card_off uuid;
  v_e_any   uuid;
  v_e_in    uuid;
  v_vt_got  uuid;
  v_eid_got uuid;
  v_lang    text;
  v_s       text[];
  v_bad     integer;
  v_n       integer;
  v_m       integer;
  v_k       integer;
  v_ids     uuid[];
  v_got     uuid[];
  v_exp     uuid[];
  v_pair    jsonb;
  v_base_us bigint;
  v_base_we bigint;
  res       jsonb := '[]'::jsonb;
  r         jsonb;
  n         integer := 0;
  passes    integer := 0;
begin
  -- 0. Estrutura e ACL ----------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    v_f1 is not null and v_f2 is not null
    and (select bool_and(p.prosecdef and p.proconfig = array['search_path=""'] and l.lanname = 'plpgsql' and p.provolatile = 's')
         from pg_proc p join pg_language l on l.oid = p.prolang where p.oid in (v_f1, v_f2))
    and (select count(*) from pg_proc q join pg_namespace ns on ns.oid = q.pronamespace
         where ns.nspname = 'public'
           and q.proname in ('get_catalog_card_variants_for_finish','get_my_wishlist_state_by_card_finish')) = 2,
    'detail','2 funções: SECURITY DEFINER, search_path vazio, plpgsql, STABLE, 1 versão cada');

  res := res || jsonb_build_object('id','0.2','ok',
    v_f1 is not null and v_f2 is not null
    and (select bool_and(has_function_privilege('authenticated', x, 'EXECUTE') and not has_function_privilege('anon', x, 'EXECUTE'))
         from unnest(array[v_f1, v_f2]) x)
    and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid in (v_f1, v_f2) and a.grantee = 0),
    'detail','EXECUTE só authenticated nas 2 (anon e PUBLIC sem acesso)');

  select count(*) into v_base_us from auth.users;
  select count(*) into v_base_we from public.card_wishlist_entry;

  begin
    -- 1.1 anon ------------------------------------------------------------
    perform set_config('request.jwt.claims', '', true);
    execute 'set local role anon';
    v_s := '{}';
    begin perform * from public.get_catalog_card_variants_for_finish(gen_random_uuid(), null); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    begin perform * from public.get_my_wishlist_state_by_card_finish(array[gen_random_uuid()]); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.1','ok', v_s = array['42501','42501'], 'detail', 'anon: '||array_to_string(v_s, ', '));

    -- 2.1 sem identidade ---------------------------------------------------
    execute 'set local role authenticated';
    v_s := '{}';
    begin perform * from public.get_catalog_card_variants_for_finish(gen_random_uuid(), null); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    begin perform * from public.get_my_wishlist_state_by_card_finish(array[gen_random_uuid()]); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','2.1','ok', v_s = array['28000','28000'], 'detail', 'sem identidade: '||array_to_string(v_s, ', '));

    -- Fixture e esperados (dono do banco: o catálogo só é legível por admin) --
    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    values (p_user_a, 'authenticated', 'authenticated', 'tr5874-a-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'tr5874a_'||v_sfx, 'display_name', 'TR 5874 A'), now(), now()),
           (p_user_b, 'authenticated', 'authenticated', 'tr5874-b-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'tr5874b_'||v_sfx, 'display_name', 'TR 5874 B'), now(), now());

    -- 3.1: pares (carta ativa, acabamento) com o conjunto exato esperado.
    select coalesce(jsonb_agg(jsonb_build_object('card', s.card_id, 'vt', s.variant_type_id, 'ids', s.ids)), '[]'::jsonb)
      into v_pairs
    from (
      select cv.card_id, cv.variant_type_id, array_agg(cv.id order by cv.id) as ids
      from public.card c
      join public.card_variant cv on cv.card_id = c.id and cv.is_active
      where c.is_active and cv.variant_type_id is not null
      group by cv.card_id, cv.variant_type_id
      order by count(*) desc, cv.card_id, cv.variant_type_id
      limit 300
    ) s;

    -- 3.2: cartas ativas com variantes de mais de um acabamento primeiro.
    select array_agg(x.id) into v_cards from (
      select c.id
      from public.card c join public.card_variant cv on cv.card_id = c.id and cv.is_active
      where c.is_active
      group by c.id
      order by count(distinct cv.variant_type_id) desc, c.id
      limit 200
    ) x;

    select c.id into v_card_x
    from public.card c join public.card_variant cv on cv.card_id = c.id and cv.is_active
    where c.is_active
    group by c.id having count(*) >= 2
    order by c.id limit 1;
    select cv.id, cv.variant_type_id into v_vx1, v_vt1 from public.card_variant cv where cv.card_id = v_card_x and cv.is_active order by cv.id limit 1;
    select cv.id into v_vx2 from public.card_variant cv where cv.card_id = v_card_x and cv.is_active order by cv.id offset 1 limit 1;

    select cv.id, cv.variant_type_id, cv.card_id into v_vin, v_vin_vt, v_card_in
    from public.card_variant cv join public.card c on c.id = cv.card_id and c.is_active
    where not cv.is_active order by cv.id limit 1;

    select c.id into v_card_off
    from public.card c where not c.is_active
      and exists (select 1 from public.card_variant cv where cv.card_id = c.id)
    order by c.id limit 1;

    if v_vx2 is null or v_vin is null or jsonb_array_length(v_pairs) = 0 or v_cards is null then
      raise exception 'TR_FIXTURE: catálogo sem carta com 2 variantes ativas, sem variante inativa em carta ativa ou sem pares';
    end if;

    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';

    -- 2.2 argumentos inválidos ---------------------------------------------
    v_bad := 0;
    v_ids := array(select gen_random_uuid() from generate_series(1, 501));
    begin perform * from public.get_catalog_card_variants_for_finish(null, null); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.get_my_wishlist_state_by_card_finish(null); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.get_my_wishlist_state_by_card_finish('{}'); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.get_my_wishlist_state_by_card_finish(v_ids); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    res := res || jsonb_build_object('id','2.2','ok', v_bad = 0, 'detail', format('%s de 4 chamadas inválidas não recusadas com 22023', v_bad));

    -- 3.1 filtro por acabamento ---------------------------------------------
    v_bad := 0; v_n := 0;
    for v_pair in select * from jsonb_array_elements(v_pairs) loop
      v_n := v_n + 1;
      select coalesce(array_agg(t.card_variant_id order by t.card_variant_id), '{}') into v_got
      from public.get_catalog_card_variants_for_finish((v_pair->>'card')::uuid, (v_pair->>'vt')::uuid) t
      where t.variant_type_id = (v_pair->>'vt')::uuid;
      select count(*) into v_k
      from public.get_catalog_card_variants_for_finish((v_pair->>'card')::uuid, (v_pair->>'vt')::uuid) t
      where t.variant_type_id is distinct from (v_pair->>'vt')::uuid;
      v_exp := array(select jsonb_array_elements_text(v_pair->'ids')::uuid order by 1);
      if v_got <> v_exp or v_k <> 0 then v_bad := v_bad + 1; end if;
    end loop;
    res := res || jsonb_build_object('id','3.1','ok', v_bad = 0 and v_n > 0,
      'detail', format('%s de %s pares (carta, acabamento) divergentes do esperado', v_bad, v_n));

    -- 3.2 NULL = qualquer acabamento = 5163 ----------------------------------
    v_bad := 0;
    for v_k in 1..cardinality(v_cards) loop
      select coalesce(array_agg(t.card_variant_id order by t.ord), '{}') into v_got
      from public.get_catalog_card_variants_for_finish(v_cards[v_k], null)
           with ordinality t(card_variant_id, variant_type_id, is_default_variant, variant_label, variant_order, ord);
      select coalesce(array_agg(t.card_variant_id order by t.ord), '{}') into v_exp
      from public.get_catalog_card_variants_for_picker(v_cards[v_k])
           with ordinality t(card_variant_id, is_default_variant, variant_label, variant_order, ord);
      if v_got <> v_exp then v_bad := v_bad + 1; end if;
    end loop;
    res := res || jsonb_build_object('id','3.2','ok', v_bad = 0,
      'detail', format('%s de %s cartas com conjunto/ordem diferente de 5163 (acabamento NULL)', v_bad, cardinality(v_cards)));

    -- 3.3 variante inativa nunca oferecida -----------------------------------
    select count(*) into v_n from public.get_catalog_card_variants_for_finish(v_card_in, v_vin_vt) t where t.card_variant_id = v_vin;
    select count(*) into v_m from public.get_catalog_card_variants_for_finish(v_card_in, null) t where t.card_variant_id = v_vin;
    res := res || jsonb_build_object('id','3.3','ok', v_n = 0 and v_m = 0,
      'detail', format('variante inativa no acabamento dela: %s; com NULL: %s (esperado 0/0)', v_n, v_m));

    -- 3.4 carta inexistente/inativa ------------------------------------------
    select count(*) into v_n from public.get_catalog_card_variants_for_finish(gen_random_uuid(), null);
    v_m := 0;
    if v_card_off is not null then
      select count(*) into v_m from public.get_catalog_card_variants_for_finish(v_card_off, null);
    end if;
    res := res || jsonb_build_object('id','3.4','ok', v_n = 0 and v_m = 0,
      'detail', format('carta inexistente: %s linhas; carta inativa: %s (esperado 0/0)', v_n,
        case when v_card_off is null then 'catálogo sem carta inativa com variante — não aplicável' else v_m::text end));

    -- 3.5 estado com acabamento -----------------------------------------------
    select t.entry_id into v_e_any from public.add_my_wishlist_entry(v_vx1, null) t;
    select count(*), max(t.variant_type_id::text)::uuid, max(t.entry_id::text)::uuid, max(t.language_code)
      into v_n, v_vt_got, v_eid_got, v_lang
    from public.get_my_wishlist_state_by_card_finish(array[v_card_x]) t
    where t.card_id = v_card_x and t.card_variant_id = v_vx1;
    res := res || jsonb_build_object('id','3.5','ok',
      v_n = 1 and v_vt_got is not distinct from v_vt1 and v_eid_got = v_e_any and v_lang is null,
      'detail', format('linhas %s; acabamento certo %s; desejo certo %s; idioma %s (esperado 1/true/true/NULL)',
        v_n, v_vt_got is not distinct from v_vt1, v_eid_got = v_e_any, coalesce(v_lang, 'NULL')));

    -- 3.6 equivalência com 5346 ----------------------------------------------
    perform * from public.add_my_wishlist_entry(v_vx1, 'pt-BR');
    perform * from public.add_my_wishlist_entry(v_vx2, null);
    select count(*) into v_n from (
      (select t.card_id, t.card_variant_id, t.entry_id, t.language_code from public.get_my_wishlist_state_by_card_finish(array[v_card_x]) t
       except
       select s.card_id, s.card_variant_id, s.entry_id, s.language_code from public.get_my_wishlist_state_by_card(array[v_card_x]) s)
      union all
      (select s.card_id, s.card_variant_id, s.entry_id, s.language_code from public.get_my_wishlist_state_by_card(array[v_card_x]) s
       except
       select t.card_id, t.card_variant_id, t.entry_id, t.language_code from public.get_my_wishlist_state_by_card_finish(array[v_card_x]) t)
    ) d;
    select count(*) into v_m from public.get_my_wishlist_state_by_card_finish(array[v_card_x]);
    res := res || jsonb_build_object('id','3.6','ok', v_n = 0 and v_m = 3,
      'detail', format('diferenças com 5346: %s; linhas: %s (esperado 0/3)', v_n, v_m));

    -- 3.7 isolamento --------------------------------------------------------------
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select count(*) into v_n from public.get_my_wishlist_state_by_card_finish(array[v_card_x]);
    execute 'reset role';
    res := res || jsonb_build_object('id','3.7','ok', v_n = 0, 'detail', format('B vê %s desejos de A (esperado 0)', v_n));

    -- 3.8 variante desativada continua visível (C-214) --------------------------
    insert into public.card_wishlist_entry (user_id, card_variant_id, language_id)
    values (p_user_a, v_vin, null) returning id into v_e_in;
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select count(*) into v_n from public.get_my_wishlist_state_by_card_finish(array[v_card_in]) t
      where t.card_variant_id = v_vin and t.entry_id = v_e_in and t.variant_type_id is not distinct from v_vin_vt;
    execute 'reset role';
    res := res || jsonb_build_object('id','3.8','ok', v_n = 1, 'detail', format('desejo da variante inativa visível com o acabamento dela: %s (esperado 1)', v_n));

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
      and (select count(*) from public.card_wishlist_entry) = v_base_we
      and current_user = session_user,
    'detail','resíduo zero (usuários, desejos) e papel restaurado');

  for r in select * from jsonb_array_elements(res) loop
    n := n + 1;
    if coalesce((r->>'ok')::boolean, false) then passes := passes + 1; end if;
    seq := n; check_id := r->>'id';
    status := case when coalesce((r->>'ok')::boolean, false) then 'PASS' else 'FAIL' end;
    detail := r->>'detail';
    return next;
  end loop;
  seq := 99; check_id := 'GATE';
  status := case when passes = n and n = 14 then 'PASS' else 'FAIL' end;
  detail := format('%s/%s PASS (esperado 14)', passes, n);
  return next;
end;
$fn$;

select * from pg_temp.tr_5874_validate();
