/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5878 - Harness: Lista de desejos em lote (V1-11 W7) — 5352
Versão......: 1.0
Status......: v1.0 EXECUTADO no LIVE (2026-11-04 UTC, LIVE SQL VALIDATION-04): GATE PASS
              13/13, sem X.1, resíduo zero. 5352 promovida para database/schema/.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-03

Protocolo (o mesmo da 5876/5877): função em pg_temp, uma chamada; usuários
efêmeros A e B; a sentinela TR000 desfaz tudo o que o harness cria; 9.1
confere resíduo zero. Não lê nem altera dados reais de nenhum usuário e
não altera o catálogo (só LÊ duas cartas ativas de Card Sets diferentes).
Executar SÓ depois de 5345–5348 e 5352 aplicadas.

Fixture
  V1 ∈ C1, V2 ∈ C2 (variantes ativas de cartas ativas de Card Sets
  diferentes). A tem um exemplar en de V1 no acervo (só para provar que nada
  fora da Lista muda) e já deseja V1 em 'en'.

Checagens (GATE = todas PASS, 13):
  0.1  2 funções: SECURITY DEFINER, search_path vazio, plpgsql, 1 versão cada;
       leitura STABLE, inclusão VOLATILE
  0.2  ACL: EXECUTE só authenticated (anon e PUBLIC sem acesso) nas 2
  1.1  anon: 42501 nas 2
  2.1  authenticated sem identidade: 28000 nas 2
  2.2  argumentos inválidos → 22023: nulo, vazio, elemento nulo, 501 ids
       distintos (nas 2)
  3.1  variantes em lote = união de 5348(card, NULL) para C1 e C2 (mesmas
       linhas e acabamentos); carta inexistente não devolve nada
  3.2  inclusão de V1 e V2 → 2 CREATED, ambas "qualquer idioma"; o desejo
       'en' de V1 continua intacto (outro idioma, outra linha)
  3.3  repetir o mesmo lote → 2 EXISTING com os mesmos entry_id; nenhuma
       linha nova (idempotente)
  3.4  ids repetidos na entrada contam uma vez (1 linha por variante)
  3.5  variante inexistente → UNAVAILABLE, nada gravado; o resto do lote
       grava normalmente (resultado por item, nunca silencioso)
  3.6  isolamento: B inclui V1 → CREATED para B (não EXISTING de A); os
       desejos de A não mudam; B não lê nem recebe entry_id de A
  3.7  nenhuma escrita fora da Lista: exemplares, coleções, alocações e
       catálogo inalterados pelas chamadas
  9.1  resíduo zero (usuários, desejos, exemplares) e papel restaurado
Erro inesperado: X.1 FAIL.
================================================================
*/

create or replace function pg_temp.tr_5878_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  v_f1      oid := to_regprocedure('public.get_catalog_card_variants_for_cards(uuid[])');
  v_f2      oid := to_regprocedure('public.add_my_wishlist_entries(uuid[])');
  p_user_a  uuid := gen_random_uuid();
  p_user_b  uuid := gen_random_uuid();
  v_sfx     text := substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
  v_c1      uuid;
  v_c2      uuid;
  v_v1      uuid;
  v_v2      uuid;
  v_lang_en uuid;
  v_inv_a   uuid;
  v_e_en    uuid;
  v_ghost   uuid := gen_random_uuid();
  v_big     uuid[];
  v_s       text[];
  v_bad     integer;
  v_n       integer;
  v_m       integer;
  v_ok      boolean;
  v_got     text[];
  v_exp     text[];
  v_ids1    uuid[];
  v_ids2    uuid[];
  v_we_a    bigint;
  v_base_us bigint;
  v_base_we bigint;
  v_base_pc bigint;
  v_base_c  bigint;
  v_base_cv bigint;
  v_base_co bigint;
  v_base_al bigint;
  res       jsonb := '[]'::jsonb;
  r         jsonb;
  n         integer := 0;
  passes    integer := 0;
begin
  -- 0. Estrutura e ACL ----------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    v_f1 is not null and v_f2 is not null
    and (select bool_and(p.prosecdef and p.proconfig = array['search_path=""'] and l.lanname = 'plpgsql')
         from pg_proc p join pg_language l on l.oid = p.prolang where p.oid in (v_f1, v_f2))
    and (select p.provolatile = 's' from pg_proc p where p.oid = v_f1)
    and (select p.provolatile = 'v' from pg_proc p where p.oid = v_f2)
    and (select count(*) from pg_proc q join pg_namespace ns on ns.oid = q.pronamespace
         where ns.nspname = 'public' and q.proname in ('get_catalog_card_variants_for_cards','add_my_wishlist_entries')) = 2,
    'detail','2 funções: SECURITY DEFINER, search_path vazio, plpgsql; leitura STABLE, inclusão VOLATILE; 1 versão cada');

  res := res || jsonb_build_object('id','0.2','ok',
    v_f1 is not null and v_f2 is not null
    and (select bool_and(has_function_privilege('authenticated', x, 'EXECUTE') and not has_function_privilege('anon', x, 'EXECUTE'))
         from unnest(array[v_f1, v_f2]) x)
    and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid in (v_f1, v_f2) and a.grantee = 0),
    'detail','EXECUTE só authenticated nas 2 (anon e PUBLIC sem acesso)');

  select count(*) into v_base_us from auth.users;
  select count(*) into v_base_we from public.card_wishlist_entry;
  select count(*) into v_base_pc from public.physical_card;
  select count(*) into v_base_c  from public.card;
  select count(*) into v_base_cv from public.card_variant;
  select count(*) into v_base_co from public.collection;
  select count(*) into v_base_al from public.collection_allocation;

  begin
    -- 1.1 anon ---------------------------------------------------------------
    v_s := '{}';
    perform set_config('request.jwt.claims', '', true);
    execute 'set local role anon';
    begin perform * from public.get_catalog_card_variants_for_cards(array[gen_random_uuid()]); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    begin perform * from public.add_my_wishlist_entries(array[gen_random_uuid()]); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.1','ok', v_s = array['42501','42501'], 'detail', 'anon: '||array_to_string(v_s, ', '));

    -- 2.1 sem identidade -------------------------------------------------------
    v_s := '{}';
    execute 'set local role authenticated';
    begin perform * from public.get_catalog_card_variants_for_cards(array[gen_random_uuid()]); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    begin perform * from public.add_my_wishlist_entries(array[gen_random_uuid()]); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','2.1','ok', v_s = array['28000','28000'], 'detail', 'sem identidade: '||array_to_string(v_s, ', '));

    -- Fixture (dono do banco: o catálogo só é legível por admin) ------------
    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    values (p_user_a, 'authenticated', 'authenticated', 'tr5878-a-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'tr5878a_'||v_sfx, 'display_name', 'TR 5878 A'), now(), now()),
           (p_user_b, 'authenticated', 'authenticated', 'tr5878-b-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'tr5878b_'||v_sfx, 'display_name', 'TR 5878 B'), now(), now());

    select c.id into v_c1
    from public.card c
    where c.is_active
      and exists (select 1 from public.card_variant cv where cv.card_id = c.id and cv.is_active)
    order by c.id limit 1;
    select c.id into v_c2
    from public.card c
    where c.is_active and c.card_set_id <> (select c1.card_set_id from public.card c1 where c1.id = v_c1)
      and exists (select 1 from public.card_variant cv where cv.card_id = c.id and cv.is_active)
    order by c.id limit 1;
    select cv.id into v_v1 from public.card_variant cv where cv.card_id = v_c1 and cv.is_active order by cv.id limit 1;
    select cv.id into v_v2 from public.card_variant cv where cv.card_id = v_c2 and cv.is_active order by cv.id limit 1;
    select l.id into v_lang_en from public.language l where l.code = 'en';
    select iv.id into v_inv_a from public.inventory iv where iv.owner_user_id = p_user_a;
    if v_v1 is null or v_v2 is null or v_lang_en is null or v_inv_a is null then
      raise exception 'TR_FIXTURE: catálogo sem duas cartas ativas de Card Sets diferentes, sem idioma en ou inventário ausente';
    end if;
    select array_agg(gen_random_uuid()) into v_big from generate_series(1, 501);

    -- Exemplar de A (só para provar que nada fora da Lista muda).
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_v1, v_lang_en, v_inv_a);

    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select e.entry_id into v_e_en from public.add_my_wishlist_entry(v_v1, 'en') e;

    -- 2.2 argumentos inválidos -------------------------------------------------
    v_bad := 0;
    begin perform * from public.get_catalog_card_variants_for_cards(null); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.get_catalog_card_variants_for_cards('{}'::uuid[]); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.get_catalog_card_variants_for_cards(array[v_c1, null]); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.get_catalog_card_variants_for_cards(v_big); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.add_my_wishlist_entries(null); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.add_my_wishlist_entries('{}'::uuid[]); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.add_my_wishlist_entries(array[v_v1, null]); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.add_my_wishlist_entries(v_big); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    res := res || jsonb_build_object('id','2.2','ok', v_bad = 0, 'detail', format('%s argumentos inválidos aceitos (esperado 0)', v_bad));

    -- 3.1 variantes em lote = 5348 por carta ------------------------------------
    select array_agg(f.card_id::text||'|'||f.card_variant_id::text||'|'||coalesce(f.variant_type_id::text,'-')||'|'||f.is_default_variant::text||'|'||coalesce(f.variant_label,'') order by f.card_id, f.card_variant_id)
      into v_got
      from public.get_catalog_card_variants_for_cards(array[v_c1, v_c2, v_c1, gen_random_uuid()]) f;
    select array_agg(x.k order by x.k_card, x.k_var) into v_exp from (
      select v_c1::text||'|'||g.card_variant_id::text||'|'||coalesce(g.variant_type_id::text,'-')||'|'||g.is_default_variant::text||'|'||coalesce(g.variant_label,'') as k, v_c1 as k_card, g.card_variant_id as k_var
      from public.get_catalog_card_variants_for_finish(v_c1, null) g
      union all
      select v_c2::text||'|'||g.card_variant_id::text||'|'||coalesce(g.variant_type_id::text,'-')||'|'||g.is_default_variant::text||'|'||coalesce(g.variant_label,''), v_c2, g.card_variant_id
      from public.get_catalog_card_variants_for_finish(v_c2, null) g
    ) x;
    res := res || jsonb_build_object('id','3.1','ok', v_got = v_exp and cardinality(v_got) >= 2,
      'detail', format('lote = 5348 por carta: %s (%s linhas; carta repetida e inexistente ignoradas)', v_got = v_exp, coalesce(cardinality(v_got),0)));

    -- 3.2 inclusão nova --------------------------------------------------------------
    select count(*) filter (where f.outcome = 'CREATED'), count(*), array_agg(f.entry_id order by f.card_variant_id) into v_n, v_m, v_ids1
      from public.add_my_wishlist_entries(array[v_v1, v_v2]) f;
    execute 'reset role';
    select bool_and(w.language_id is null) into v_ok from public.card_wishlist_entry w where w.id = any(v_ids1);
    v_ok := coalesce(v_ok, false) and exists (select 1 from public.card_wishlist_entry w where w.id = v_e_en and w.language_id = v_lang_en);
    select count(*) into v_we_a from public.card_wishlist_entry w where w.user_id = p_user_a;
    execute 'set local role authenticated';
    res := res || jsonb_build_object('id','3.2','ok', v_n = 2 and v_m = 2 and v_ok and v_we_a = 3,
      'detail', format('CREATED %s de %s linhas; "qualquer idioma" e desejo en preservado: %s; desejos de A: %s (esperado 2/2/true/3)', v_n, v_m, v_ok, v_we_a));

    -- 3.3 idempotência -------------------------------------------------------------------
    select count(*) filter (where f.outcome = 'EXISTING'), array_agg(f.entry_id order by f.card_variant_id) into v_n, v_ids2
      from public.add_my_wishlist_entries(array[v_v2, v_v1]) f;
    execute 'reset role';
    select count(*) into v_m from public.card_wishlist_entry w where w.user_id = p_user_a;
    execute 'set local role authenticated';
    res := res || jsonb_build_object('id','3.3','ok', v_n = 2 and v_ids2 = v_ids1 and v_m = 3,
      'detail', format('repetir: EXISTING %s, mesmos ids: %s, desejos de A %s (esperado 2/true/3)', v_n, v_ids2 = v_ids1, v_m));

    -- 3.4 repetidos na entrada -----------------------------------------------------------
    select count(*), count(distinct f.card_variant_id) into v_n, v_m
      from public.add_my_wishlist_entries(array[v_v1, v_v1, v_v1]) f;
    res := res || jsonb_build_object('id','3.4','ok', v_n = 1 and v_m = 1,
      'detail', format('3× a mesma variante: %s linha(s) (esperado 1)', v_n));

    -- 3.5 indisponível no meio do lote ----------------------------------------------------
    select array_agg(f.outcome order by f.outcome) into v_got
      from public.add_my_wishlist_entries(array[v_ghost, v_v2]) f;
    execute 'reset role';
    select count(*) into v_n from public.card_wishlist_entry w where w.card_variant_id = v_ghost;
    execute 'set local role authenticated';
    res := res || jsonb_build_object('id','3.5','ok', v_got = array['EXISTING','UNAVAILABLE'] and v_n = 0,
      'detail', format('resultado por item: %s; gravado para a inexistente: %s (esperado EXISTING,UNAVAILABLE/0)', array_to_string(v_got, ','), v_n));
    execute 'reset role';

    -- 3.6 isolamento (B) ----------------------------------------------------------------------
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select array_agg(f.outcome), bool_and(not (f.entry_id = any(v_ids1)) and f.entry_id <> v_e_en) into v_got, v_ok
      from public.add_my_wishlist_entries(array[v_v1]) f;
    execute 'reset role';
    select count(*) into v_n from public.card_wishlist_entry w where w.user_id = p_user_a;
    select count(*) into v_m from public.card_wishlist_entry w where w.user_id = p_user_b;
    res := res || jsonb_build_object('id','3.6','ok', v_got = array['CREATED'] and coalesce(v_ok, false) and v_n = 3 and v_m = 1,
      'detail', format('B: %s, ids próprios: %s; desejos A %s / B %s (esperado CREATED/true/3/1)', array_to_string(v_got, ','), v_ok, v_n, v_m));

    -- 3.7 nada fora da Lista ---------------------------------------------------------------------
    res := res || jsonb_build_object('id','3.7','ok',
      (select count(*) from public.physical_card) = v_base_pc + 1
      and (select count(*) from public.collection) = v_base_co
      and (select count(*) from public.collection_allocation) = v_base_al
      and (select count(*) from public.card) = v_base_c
      and (select count(*) from public.card_variant) = v_base_cv
      and (select count(*) from public.card_wishlist_entry) = v_base_we + 4,
      'detail','exemplares +1 (só fixture), coleções, alocações e catálogo inalterados; desejos +4 (en de A, 2 de A, 1 de B)');

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
      and (select count(*) from public.physical_card) = v_base_pc
      and current_user = session_user,
    'detail','resíduo zero (usuários, desejos, exemplares) e papel restaurado');

  for r in select * from jsonb_array_elements(res) loop
    n := n + 1;
    if coalesce((r->>'ok')::boolean, false) then passes := passes + 1; end if;
    seq := n; check_id := r->>'id';
    status := case when coalesce((r->>'ok')::boolean, false) then 'PASS' else 'FAIL' end;
    detail := r->>'detail';
    return next;
  end loop;
  seq := 99; check_id := 'GATE';
  status := case when passes = n and n = 13 then 'PASS' else 'FAIL' end;
  detail := format('%s/%s PASS (esperado 13)', passes, n);
  return next;
end;
$fn$;

select * from pg_temp.tr_5878_validate();
