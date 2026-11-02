/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5873 - Harness: Lista de desejos (V1-11 W1) — 5345, 5346 e 5347
Versão......: 1.1 (LIVE-VALIDATION-03: constante do GATE corrigida de 16 para 17 — a lista
              sempre teve 17 checagens; nenhuma checagem alterada)
Status......: v1.0 EXECUTADA no LIVE (LIVE SQL EXECUTION & VALIDATION-03, 2026-11-02 UTC): 17/17
              checagens PASS, sem X.1, resíduo zero; GATE impresso FAIL só pela constante 16.
              v1.1 NÃO reexecutada.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-01

Protocolo (o mesmo da 5868): função em pg_temp, uma chamada; usuários
efêmeros A e B; a sentinela TR000 desfaz tudo o que o harness cria; 9.1
confere resíduo zero. Não lê nem altera dados reais de nenhum usuário e
não altera o catálogo. Executar SÓ depois de 5345, 5346 e 5347 aplicadas.

Checagens (GATE = todas PASS, 17):
  0.1  tabela: PK id; FK user CASCADE; FK variante RESTRICT; FK idioma;
       unique (user, variante, idioma) NULLS NOT DISTINCT; RLS + 1 policy
       SELECT; authenticated só SELECT; anon nada
  0.2  6 funções: SECURITY DEFINER, search_path vazio, plpgsql, 1 versão;
       add/remove VOLATILE, leituras STABLE
  0.3  ACL: EXECUTE só authenticated nas 6 (anon e PUBLIC sem acesso)
  1.1  anon: 42501 nas 6 funções e no SELECT da tabela
  2.1  authenticated sem identidade: 28000 nas 6
  2.2  argumentos inválidos: 22023 (variante nula, idioma desconhecido,
       lotes nulo/vazio/501, página fora dos limites); P0002 (variante
       inexistente e variante inativa — inclusão só em variante ativa)
  3.1  incluir "qualquer idioma": created = true; aparece por variante e
       por carta, com idioma NULL
  3.2  idempotência: incluir de novo devolve o mesmo id com created =
       false; 1 linha; idioma '' equivale a NULL
  3.3  múltiplos idiomas: + pt-BR = segunda entrada legítima (C-99);
       resumo: 2 desejos, 1 variante distinta
  3.4  isolamento: B não vê nada de A (por variante, por carta, página,
       resumo, SELECT direto) e remover o id de A como B devolve 0
  3.5  escrita direta bloqueada: INSERT/UPDATE/DELETE como authenticated = 42501
  3.6  posse derivada (C-213): sem exemplar = NONE; com exemplar EN da
       variante: "qualquer" = SAME_VARIANT_LANGUAGE, pt-BR =
       SAME_VARIANT_OTHER_LANGUAGE; desejo de outra variante da carta =
       OTHER_VARIANT
  3.7  variante desativada permanece (C-214): entrada pré-existente de
       variante inativa aparece com variant_available = false e pode ser
       removida
  3.8  página: mais recente primeiro, total_count correto, limite respeitado
  3.9  valor de referência (C-216): igual à soma de UMA referência válida
       (> 0) por variante distinta via 3983; NULL sem cobertura
  3.10 remoção em lote: devolve quantas saíram; repetir devolve 0
  9.1  resíduo zero (usuários, desejos, exemplares) e papel restaurado
Erro inesperado: X.1 FAIL.
================================================================
*/

create or replace function pg_temp.tr_5873_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  v_t       oid := to_regclass('public.card_wishlist_entry');
  v_f1      oid := to_regprocedure('public.add_my_wishlist_entry(uuid,text)');
  v_f2      oid := to_regprocedure('public.remove_my_wishlist_entries(uuid[])');
  v_f3      oid := to_regprocedure('public.get_my_wishlist_state_by_variant(uuid[])');
  v_f4      oid := to_regprocedure('public.get_my_wishlist_state_by_card(uuid[])');
  v_f5      oid := to_regprocedure('public.get_my_wishlist(integer,integer)');
  v_f6      oid := to_regprocedure('public.get_my_wishlist_summary()');
  p_user_a  uuid := gen_random_uuid();
  p_user_b  uuid := gen_random_uuid();
  v_sfx     text := substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
  v_card_x  uuid;
  v_vx1     uuid;
  v_vx2     uuid;
  v_vin     uuid;
  v_lang_en uuid;
  v_inv_a   uuid;
  v_e_any   uuid;
  v_e_pt    uuid;
  v_e_x2    uuid;
  v_e_in    uuid;
  v_id      uuid;
  v_created boolean;
  v_code    text;
  v_s       text[];
  v_bad     integer;
  v_n       integer;
  v_m       integer;
  v_ids     uuid[];
  v_first   uuid;
  v_total   bigint;
  v_ec      integer;
  v_vc      integer;
  v_pc      integer;
  v_brl     numeric;
  v_exp     numeric;
  v_expc    integer;
  v_o1      text;
  v_o2      text;
  v_o3      text;
  v_avail   boolean;
  v_base_us bigint;
  v_base_we bigint;
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
                and pg_get_constraintdef(c.oid) = 'PRIMARY KEY (id)')
    and exists (select 1 from pg_constraint c where c.conrelid = v_t and c.contype = 'f'
                and c.confrelid = 'auth.users'::regclass and c.confdeltype = 'c')
    and exists (select 1 from pg_constraint c where c.conrelid = v_t and c.contype = 'f'
                and c.confrelid = 'public.card_variant'::regclass and c.confdeltype = 'r')
    and exists (select 1 from pg_constraint c where c.conrelid = v_t and c.contype = 'f'
                and c.confrelid = 'public.language'::regclass)
    and exists (select 1 from pg_constraint c where c.conrelid = v_t and c.contype = 'u'
                and pg_get_constraintdef(c.oid) = 'UNIQUE NULLS NOT DISTINCT (user_id, card_variant_id, language_id)')
    and (select relrowsecurity from pg_class where oid = v_t)
    and (select count(*) from pg_policy p where p.polrelid = v_t) = 1
    and (select count(*) from pg_policy p where p.polrelid = v_t and p.polcmd = 'r') = 1
    and has_table_privilege('authenticated', v_t, 'SELECT')
    and not has_table_privilege('authenticated', v_t, 'INSERT')
    and not has_table_privilege('authenticated', v_t, 'UPDATE')
    and not has_table_privilege('authenticated', v_t, 'DELETE')
    and not has_table_privilege('anon', v_t, 'SELECT'),
    'detail','card_wishlist_entry: PK id, FKs (user CASCADE, variante RESTRICT, idioma), unique NULLS NOT DISTINCT, RLS + 1 policy SELECT, authenticated só SELECT, anon nada');

  res := res || jsonb_build_object('id','0.2','ok',
    v_f1 is not null and v_f2 is not null and v_f3 is not null and v_f4 is not null and v_f5 is not null and v_f6 is not null
    and (select bool_and(p.prosecdef and p.proconfig = array['search_path=""'] and l.lanname = 'plpgsql')
         from pg_proc p join pg_language l on l.oid = p.prolang where p.oid in (v_f1, v_f2, v_f3, v_f4, v_f5, v_f6))
    and (select bool_and(provolatile = 'v') from pg_proc where oid in (v_f1, v_f2))
    and (select bool_and(provolatile = 's') from pg_proc where oid in (v_f3, v_f4, v_f5, v_f6))
    and (select count(*) from pg_proc q join pg_namespace ns on ns.oid = q.pronamespace
         where ns.nspname = 'public'
           and q.proname in ('add_my_wishlist_entry','remove_my_wishlist_entries','get_my_wishlist_state_by_variant',
                             'get_my_wishlist_state_by_card','get_my_wishlist','get_my_wishlist_summary')) = 6,
    'detail','6 funções: SECURITY DEFINER, search_path vazio, plpgsql, 1 versão; escrita VOLATILE, leituras STABLE');

  res := res || jsonb_build_object('id','0.3','ok',
    v_f1 is not null and v_f2 is not null and v_f3 is not null and v_f4 is not null and v_f5 is not null and v_f6 is not null
    and (select bool_and(has_function_privilege('authenticated', x, 'EXECUTE') and not has_function_privilege('anon', x, 'EXECUTE'))
         from unnest(array[v_f1, v_f2, v_f3, v_f4, v_f5, v_f6]) x)
    and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid in (v_f1, v_f2, v_f3, v_f4, v_f5, v_f6) and a.grantee = 0),
    'detail','EXECUTE só authenticated nas 6 (anon e PUBLIC sem acesso)');

  select count(*) into v_base_us from auth.users;
  select count(*) into v_base_we from public.card_wishlist_entry;
  select count(*) into v_base_pc from public.physical_card;

  begin
    -- 1.1 anon ------------------------------------------------------------
    perform set_config('request.jwt.claims', '', true);
    execute 'set local role anon';
    v_s := '{}';
    begin perform * from public.add_my_wishlist_entry(gen_random_uuid(), null); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    begin perform public.remove_my_wishlist_entries(array[gen_random_uuid()]); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    begin perform * from public.get_my_wishlist_state_by_variant(array[gen_random_uuid()]); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    begin perform * from public.get_my_wishlist_state_by_card(array[gen_random_uuid()]); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    begin perform * from public.get_my_wishlist(10, 0); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    begin perform * from public.get_my_wishlist_summary(); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    begin perform 1 from public.card_wishlist_entry; v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.1','ok', v_s = array['42501','42501','42501','42501','42501','42501','42501'],
      'detail', 'anon: '||array_to_string(v_s, ', '));

    -- 2.1 sem identidade ---------------------------------------------------
    execute 'set local role authenticated';
    v_s := '{}';
    begin perform * from public.add_my_wishlist_entry(gen_random_uuid(), null); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    begin perform public.remove_my_wishlist_entries(array[gen_random_uuid()]); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    begin perform * from public.get_my_wishlist_state_by_variant(array[gen_random_uuid()]); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    begin perform * from public.get_my_wishlist_state_by_card(array[gen_random_uuid()]); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    begin perform * from public.get_my_wishlist(10, 0); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    begin perform * from public.get_my_wishlist_summary(); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','2.1','ok', v_s = array['28000','28000','28000','28000','28000','28000'],
      'detail', 'sem identidade: '||array_to_string(v_s, ', '));

    -- Fixture (dono do banco: o catálogo só é legível por admin) ------------
    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    values (p_user_a, 'authenticated', 'authenticated', 'tr5873-a-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'tr5873a_'||v_sfx, 'display_name', 'TR 5873 A'), now(), now()),
           (p_user_b, 'authenticated', 'authenticated', 'tr5873-b-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'tr5873b_'||v_sfx, 'display_name', 'TR 5873 B'), now(), now());

    select c.id into v_card_x
    from public.card c join public.card_variant cv on cv.card_id = c.id and cv.is_active
    where c.is_active
    group by c.id having count(*) >= 2
    order by c.id limit 1;
    select cv.id into v_vx1 from public.card_variant cv where cv.card_id = v_card_x and cv.is_active order by cv.id limit 1;
    select cv.id into v_vx2 from public.card_variant cv where cv.card_id = v_card_x and cv.is_active order by cv.id offset 1 limit 1;
    select cv.id into v_vin from public.card_variant cv where not cv.is_active order by cv.id limit 1;
    select l.id into v_lang_en from public.language l where l.code = 'en';
    select iv.id into v_inv_a from public.inventory iv where iv.owner_user_id = p_user_a;
    if v_vx2 is null or v_vin is null or v_inv_a is null or v_lang_en is null then
      raise exception 'TR_FIXTURE: catálogo sem carta com 2 variantes ativas, sem variante inativa, sem idioma en ou inventário ausente';
    end if;

    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';

    -- 2.2 argumentos inválidos ---------------------------------------------
    v_bad := 0;
    v_ids := array(select gen_random_uuid() from generate_series(1, 501));
    begin perform * from public.add_my_wishlist_entry(null, null); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.add_my_wishlist_entry(v_vx1, 'xx'); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.add_my_wishlist_entry(gen_random_uuid(), null); v_bad := v_bad + 1; exception when sqlstate 'P0002' then null; end;
    begin perform * from public.add_my_wishlist_entry(v_vin, null); v_bad := v_bad + 1; exception when sqlstate 'P0002' then null; end;
    begin perform public.remove_my_wishlist_entries(null); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform public.remove_my_wishlist_entries('{}'); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform public.remove_my_wishlist_entries(v_ids); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.get_my_wishlist_state_by_variant(null); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.get_my_wishlist_state_by_variant('{}'); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.get_my_wishlist_state_by_variant(v_ids); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.get_my_wishlist_state_by_card(null); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.get_my_wishlist_state_by_card('{}'); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.get_my_wishlist_state_by_card(v_ids); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.get_my_wishlist(0, 0); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.get_my_wishlist(101, 0); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.get_my_wishlist(10, -1); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    res := res || jsonb_build_object('id','2.2','ok', v_bad = 0, 'detail', format('%s de 16 chamadas inválidas não recusadas com o código esperado', v_bad));

    -- 3.1 incluir "qualquer idioma" ---------------------------------------------
    select t.entry_id, t.created, t.language_code into v_e_any, v_created, v_code
    from public.add_my_wishlist_entry(v_vx1, null) t;
    select count(*) into v_n from public.get_my_wishlist_state_by_variant(array[v_vx1, v_vx2]) t
      where t.card_variant_id = v_vx1 and t.entry_id = v_e_any and t.language_code is null;
    select count(*) into v_m from public.get_my_wishlist_state_by_card(array[v_card_x]) t
      where t.card_id = v_card_x and t.card_variant_id = v_vx1 and t.entry_id = v_e_any;
    res := res || jsonb_build_object('id','3.1','ok', v_e_any is not null and v_created and v_code is null and v_n = 1 and v_m = 1,
      'detail', format('created %s; idioma %s; por variante %s; por carta %s (esperado true/NULL/1/1)', v_created, coalesce(v_code,'NULL'), v_n, v_m));

    -- 3.2 idempotência --------------------------------------------------------------
    select t.entry_id, t.created into v_id, v_created from public.add_my_wishlist_entry(v_vx1, '') t;
    execute 'reset role';
    select count(*) into v_n from public.card_wishlist_entry w where w.user_id = p_user_a and w.card_variant_id = v_vx1;
    execute 'set local role authenticated';
    res := res || jsonb_build_object('id','3.2','ok', v_id = v_e_any and not v_created and v_n = 1,
      'detail', format('mesmo id: %s; created %s; linhas %s (esperado true/false/1)', v_id = v_e_any, v_created, v_n));

    -- 3.3 múltiplos idiomas -----------------------------------------------------------
    select t.entry_id, t.created into v_e_pt, v_created from public.add_my_wishlist_entry(v_vx1, 'pt-BR') t;
    select s.entry_count, s.variant_count into v_ec, v_vc from public.get_my_wishlist_summary() s;
    res := res || jsonb_build_object('id','3.3','ok', v_created and v_e_pt <> v_e_any and v_ec = 2 and v_vc = 1,
      'detail', format('pt-BR created %s; desejos %s; variantes distintas %s (esperado true/2/1)', v_created, v_ec, v_vc));

    -- 3.4 isolamento -----------------------------------------------------------------
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select count(*) into v_n from public.get_my_wishlist_state_by_variant(array[v_vx1]);
    select v_n + count(*) into v_n from public.get_my_wishlist_state_by_card(array[v_card_x]);
    select v_n + count(*) into v_n from public.get_my_wishlist(100, 0);
    select v_n + count(*) into v_n from public.card_wishlist_entry;
    select v_n + s.entry_count into v_n from public.get_my_wishlist_summary() s;
    v_m := public.remove_my_wishlist_entries(array[v_e_any, v_e_pt]);
    execute 'reset role';
    select count(*) into v_ec from public.card_wishlist_entry w where w.user_id = p_user_a;
    res := res || jsonb_build_object('id','3.4','ok', v_n = 0 and v_m = 0 and v_ec = 2,
      'detail', format('B enxergou %s registros de A (esperado 0); remoção por B: %s (esperado 0); desejos de A: %s (esperado 2)', v_n, v_m, v_ec));

    -- 3.5 escrita direta bloqueada ----------------------------------------------------
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    v_s := '{}';
    begin insert into public.card_wishlist_entry (user_id, card_variant_id) values (p_user_a, v_vx2); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    begin update public.card_wishlist_entry set language_id = null where id = v_e_pt; v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    begin delete from public.card_wishlist_entry where id = v_e_any; v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    res := res || jsonb_build_object('id','3.5','ok', v_s = array['42501','42501','42501'],
      'detail', 'INSERT/UPDATE/DELETE direto como authenticated: '||array_to_string(v_s, ', '));

    -- 3.6 posse derivada ---------------------------------------------------------------
    select t.ownership into v_o1 from public.get_my_wishlist(100, 0) t where t.entry_id = v_e_any;
    select t.entry_id into v_e_x2 from public.add_my_wishlist_entry(v_vx2, null) t;
    execute 'reset role';
    insert into public.physical_card (card_variant_id, language_id, inventory_id)
    values (v_vx1, v_lang_en, v_inv_a);
    execute 'set local role authenticated';
    select max(t.ownership) filter (where t.entry_id = v_e_any),
           max(t.ownership) filter (where t.entry_id = v_e_pt),
           max(t.ownership) filter (where t.entry_id = v_e_x2)
      into v_o2, v_o3, v_code
    from public.get_my_wishlist(100, 0) t;
    res := res || jsonb_build_object('id','3.6','ok',
      v_o1 = 'NONE' and v_o2 = 'SAME_VARIANT_LANGUAGE' and v_o3 = 'SAME_VARIANT_OTHER_LANGUAGE' and v_code = 'OTHER_VARIANT',
      'detail', format('antes: %s; qualquer: %s; pt-BR: %s; outra variante: %s', v_o1, v_o2, v_o3, v_code));

    -- 3.7 variante desativada permanece ------------------------------------------------
    execute 'reset role';
    -- Fixture: desejo pré-existente de uma variante já inativa (sem alterar o catálogo).
    insert into public.card_wishlist_entry (user_id, card_variant_id, language_id, created_at)
    values (p_user_a, v_vin, null, now() - interval '2 minute') returning id into v_e_in;
    execute 'set local role authenticated';
    select t.variant_available into v_avail from public.get_my_wishlist(100, 0) t where t.entry_id = v_e_in;
    v_m := public.remove_my_wishlist_entries(array[v_e_in]);
    res := res || jsonb_build_object('id','3.7','ok', v_avail is false and v_m = 1,
      'detail', format('variant_available %s; removida %s (esperado false/1)', coalesce(v_avail::text,'ausente'), v_m));

    -- 3.8 página -----------------------------------------------------------------------
    execute 'reset role';
    update public.card_wishlist_entry set created_at = now() - interval '1 minute'
    where user_id = p_user_a and id in (v_e_any, v_e_pt);
    execute 'set local role authenticated';
    select (array_agg(t.entry_id order by t.wished_at desc, t.entry_id))[1], max(t.total_count), count(*)
      into v_first, v_total, v_n
    from public.get_my_wishlist(100, 0) t;
    select count(*) into v_m from public.get_my_wishlist(1, 0) t;
    res := res || jsonb_build_object('id','3.8','ok', v_first = v_e_x2 and v_total = 3 and v_n = 3 and v_m = 1,
      'detail', format('primeira = mais recente: %s; total_count %s; linhas %s; limit 1 → %s', v_first = v_e_x2, v_total, v_n, v_m));

    -- 3.9 valor de referência por variante distinta -----------------------------------
    select s.priced_variant_count, s.total_brl, s.variant_count into v_pc, v_brl, v_vc from public.get_my_wishlist_summary() s;
    select count(*)::integer, sum(p.brl_amount) into v_expc, v_exp
    from public.get_card_variants_pricing_summary(array[v_vx1, v_vx2]) p
    where p.has_pricing and p.brl_amount is not null and p.brl_amount > 0;
    res := res || jsonb_build_object('id','3.9','ok',
      v_vc = 2 and v_pc = v_expc and ((v_expc = 0 and v_brl is null) or (v_expc > 0 and v_brl = v_exp)),
      'detail', format('variantes %s; cotadas %s (esperado %s); total %s (esperado %s; NULL sem cobertura)', v_vc, v_pc, v_expc, coalesce(v_brl::text,'NULL'), coalesce(v_exp::text,'NULL')));

    -- 3.10 remoção em lote --------------------------------------------------------------
    v_n := public.remove_my_wishlist_entries(array[v_e_any, v_e_pt, v_e_x2, gen_random_uuid()]);
    v_m := public.remove_my_wishlist_entries(array[v_e_any, v_e_pt, v_e_x2]);
    select s.entry_count, s.total_brl into v_ec, v_brl from public.get_my_wishlist_summary() s;
    res := res || jsonb_build_object('id','3.10','ok', v_n = 3 and v_m = 0 and v_ec = 0 and v_brl is null,
      'detail', format('removidos %s; repetir %s; desejos restantes %s; total %s (esperado 3/0/0/NULL)', v_n, v_m, v_ec, coalesce(v_brl::text,'NULL')));
    execute 'reset role';

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
  status := case when passes = n and n = 17 then 'PASS' else 'FAIL' end;
  detail := format('%s/%s PASS (esperado 17)', passes, n);
  return next;
end;
$fn$;

select * from pg_temp.tr_5873_validate();
