/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5877 - Harness: ordenação da Lista de desejos filtrada (V1-11 W6) — 5351
Versão......: 1.1
Status......: v1.0 EXECUTADO no LIVE (2026-11-03, por Fabrício no SQL Editor): 12/12 checagens
              PASS; GATE agregado FAIL só pela constante esperada (11 em vez de 12).
              v1.1 corrige a constante (sem mudar nenhuma checagem); não reexecutada.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-03

Protocolo (o mesmo da 5876): função em pg_temp, uma chamada; usuários
efêmeros A e B; a sentinela TR000 desfaz tudo o que o harness cria; 9.1
confere resíduo zero. Não lê nem altera dados reais de nenhum usuário e
não altera o catálogo. Executar SÓ depois de 5345–5347 (W1), 5350 e 5351.
Depois da 5351, a 5876 NÃO deve ser reexecutada como gate: suas checagens
0.1/0.2 procuram a assinatura de 7 argumentos, que a 5351 remove (as
checagens funcionais dela continuariam passando pelo default de p_sort).
Estrutura e ACL da versão de 8 argumentos são cobertas aqui (0.1/0.2).

Fixture (a mesma da 5876)
  A deseja, nesta ordem: V1 "qualquer idioma", V1 en, V2 pt-BR
                         (V1 ∈ Card Set S1, V2 ∈ S2)
  B deseja: V2 "qualquer idioma"   (isolamento)

Checagens (GATE = todas PASS, 12):
  0.1  uma versão só de get_my_wishlist_filtered, com 8 argumentos (a de 7
       foi removida): SECURITY DEFINER, search_path vazio, plpgsql, STABLE
  0.2  ACL: EXECUTE só authenticated (anon e PUBLIC sem acesso)
  1.1  anon: 42501
  2.1  authenticated sem identidade: 28000
  2.2  ordenação desconhecida → 22023; 'set_number' em minúsculas aceito
  3.1  RECENT (padrão, explícito e chamada com os 7 argumentos antigos por
       nome) = get_my_wishlist (mesma ordem, total 3)
  3.2  SET_NUMBER = ordem esperada calculada pelo catálogo (Card Set mais
       recente → número → variante → "qualquer" antes de idioma específico);
       V1/qualquer vem imediatamente antes de V1/en
  3.3  SET_NUMBER paginado (limite 1, offsets 0..2) = ordem completa;
       total_count 3 em todas as páginas; além do fim → 0
  3.4  SET_NUMBER + Card Set S1 → só V1/qualquer, V1/en, nessa ordem; total 2
  3.5  isolamento: B com SET_NUMBER vê só o próprio desejo
  3.6  nenhuma escrita: desejos, exemplares e catálogo inalterados
  9.1  resíduo zero (usuários, desejos, exemplares) e papel restaurado
Erro inesperado: X.1 FAIL.
================================================================
*/

create or replace function pg_temp.tr_5877_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  v_f       oid := to_regprocedure('public.get_my_wishlist_filtered(integer,integer,text,uuid,uuid,text,text,text)');
  p_user_a  uuid := gen_random_uuid();
  p_user_b  uuid := gen_random_uuid();
  v_sfx     text := substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
  v_c1      uuid;
  v_c2      uuid;
  v_s1      uuid;
  v_v1      uuid;
  v_v2      uuid;
  v_lang_en uuid;
  v_inv_a   uuid;
  v_e_any   uuid;
  v_e_en    uuid;
  v_e_pt    uuid;
  v_s       text[];
  v_bad     integer;
  v_got     uuid[];
  v_got2    uuid[];
  v_got3    uuid[];
  v_exp     uuid[];
  v_p0      uuid[];
  v_p1      uuid[];
  v_p2      uuid[];
  v_n       integer;
  v_total   bigint;
  v_ok      boolean;
  v_pos     integer;
  v_base_us bigint;
  v_base_we bigint;
  v_base_pc bigint;
  v_base_c  bigint;
  res       jsonb := '[]'::jsonb;
  r         jsonb;
  n         integer := 0;
  passes    integer := 0;
begin
  -- 0. Estrutura e ACL ----------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    v_f is not null
    and (select p.prosecdef and p.proconfig = array['search_path=""'] and l.lanname = 'plpgsql' and p.provolatile = 's'
         from pg_proc p join pg_language l on l.oid = p.prolang where p.oid = v_f)
    and (select count(*) from pg_proc q join pg_namespace ns on ns.oid = q.pronamespace
         where ns.nspname = 'public' and q.proname = 'get_my_wishlist_filtered') = 1,
    'detail','1 versão (8 argumentos): SECURITY DEFINER, search_path vazio, plpgsql, STABLE');

  res := res || jsonb_build_object('id','0.2','ok',
    v_f is not null
    and has_function_privilege('authenticated', v_f, 'EXECUTE')
    and not has_function_privilege('anon', v_f, 'EXECUTE')
    and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = v_f and a.grantee = 0),
    'detail','EXECUTE só authenticated (anon e PUBLIC sem acesso)');

  select count(*) into v_base_us from auth.users;
  select count(*) into v_base_we from public.card_wishlist_entry;
  select count(*) into v_base_pc from public.physical_card;
  select count(*) into v_base_c  from public.card;

  begin
    -- 1.1 anon ---------------------------------------------------------------
    v_s := '{}';
    perform set_config('request.jwt.claims', '', true);
    execute 'set local role anon';
    begin perform * from public.get_my_wishlist_filtered(10, 0, null, null, null, null, null, 'SET_NUMBER'); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.1','ok', v_s = array['42501'], 'detail', 'anon: '||array_to_string(v_s, ', '));

    -- 2.1 sem identidade -------------------------------------------------------
    v_s := '{}';
    execute 'set local role authenticated';
    begin perform * from public.get_my_wishlist_filtered(10, 0, null, null, null, null, null, 'SET_NUMBER'); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','2.1','ok', v_s = array['28000'], 'detail', 'sem identidade: '||array_to_string(v_s, ', '));

    -- Fixture (dono do banco: o catálogo só é legível por admin) ------------
    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    values (p_user_a, 'authenticated', 'authenticated', 'tr5877-a-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'tr5877a_'||v_sfx, 'display_name', 'TR 5877 A'), now(), now()),
           (p_user_b, 'authenticated', 'authenticated', 'tr5877-b-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'tr5877b_'||v_sfx, 'display_name', 'TR 5877 B'), now(), now());

    select c.id, c.card_set_id into v_c1, v_s1
    from public.card c
    where c.is_active
      and exists (select 1 from public.card_variant cv where cv.card_id = c.id and cv.is_active)
    order by c.id limit 1;
    select c.id into v_c2
    from public.card c
    where c.is_active and c.card_set_id <> v_s1
      and exists (select 1 from public.card_variant cv where cv.card_id = c.id and cv.is_active)
    order by c.id limit 1;
    select cv.id into v_v1 from public.card_variant cv where cv.card_id = v_c1 and cv.is_active order by cv.id limit 1;
    select cv.id into v_v2 from public.card_variant cv where cv.card_id = v_c2 and cv.is_active order by cv.id limit 1;
    select l.id into v_lang_en from public.language l where l.code = 'en';
    select iv.id into v_inv_a from public.inventory iv where iv.owner_user_id = p_user_a;
    if v_v1 is null or v_v2 is null or v_lang_en is null or v_inv_a is null
       or not exists (select 1 from public.language l where l.code = 'pt-BR' and l.is_active) then
      raise exception 'TR_FIXTURE: catálogo sem duas cartas ativas de Card Sets diferentes, sem idiomas en/pt-BR ou inventário ausente';
    end if;

    insert into public.physical_card (card_variant_id, language_id, inventory_id)
    values (v_v1, v_lang_en, v_inv_a);

    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    perform * from public.add_my_wishlist_entry(v_v2, null);
    execute 'reset role';

    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select e.entry_id into v_e_any from public.add_my_wishlist_entry(v_v1, null) e;
    select e.entry_id into v_e_en  from public.add_my_wishlist_entry(v_v1, 'en') e;
    select e.entry_id into v_e_pt  from public.add_my_wishlist_entry(v_v2, 'pt-BR') e;

    -- 2.2 ordenação inválida / minúsculas ----------------------------------------
    v_bad := 0;
    begin perform * from public.get_my_wishlist_filtered(10, 0, null, null, null, null, null, 'TALVEZ'); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.get_my_wishlist_filtered(10, 0, null, null, null, null, null, 'set_number'); exception when others then v_bad := v_bad + 1; end;
    res := res || jsonb_build_object('id','2.2','ok', v_bad = 0, 'detail', format('%s falha(s): TALVEZ deve dar 22023 e set_number ser aceito (esperado 0)', v_bad));

    -- 3.1 RECENT = 5346 ------------------------------------------------------------
    select array_agg(g.entry_id order by g.wished_at desc, g.entry_id) into v_exp from public.get_my_wishlist(100, 0) g;
    select array_agg(f.entry_id), max(f.total_count) into v_got, v_total
      from public.get_my_wishlist_filtered(100, 0, null, null, null, null, null) f;
    select array_agg(f.entry_id) into v_got2
      from public.get_my_wishlist_filtered(100, 0, null, null, null, null, null, 'RECENT') f;
    select array_agg(f.entry_id) into v_got3
      from public.get_my_wishlist_filtered(p_limit => 100, p_offset => 0, p_search => null, p_card_set_id => null,
                                           p_rarity_id => null, p_language => null, p_ownership => null) f;
    res := res || jsonb_build_object('id','3.1','ok', v_got = v_exp and v_got2 = v_exp and v_got3 = v_exp and v_total = 3,
      'detail', format('RECENT padrão/explícito/7 args por nome = 5346: %s/%s/%s; total %s', v_got = v_exp, v_got2 = v_exp, v_got3 = v_exp, v_total));

    -- 3.2 SET_NUMBER = ordem do catálogo ---------------------------------------------
    select array_agg(f.entry_id) into v_got
      from public.get_my_wishlist_filtered(100, 0, null, null, null, null, null, 'SET_NUMBER') f;
    execute 'reset role';
    select array_agg(x.id order by
             x.release_date desc nulls last, x.release_order desc nulls last, x.code,
             x.collector_order, x.variant_order, (x.language_id is not null), x.language_order,
             x.created_at desc, x.id)
      into v_exp
    from (
      select w.id, w.language_id, w.created_at, cs.release_date, cs.release_order, cs.code,
             c.collector_order, cv.variant_order, l.language_order
      from public.card_wishlist_entry w
      join public.card_variant cv on cv.id = w.card_variant_id
      join public.card c on c.id = cv.card_id
      join public.card_set cs on cs.id = c.card_set_id
      left join public.language l on l.id = w.language_id
      where w.user_id = p_user_a
    ) x;
    execute 'set local role authenticated';
    v_pos := array_position(v_got, v_e_any);
    res := res || jsonb_build_object('id','3.2','ok',
      v_got = v_exp and cardinality(v_got) = 3 and v_pos is not null and v_got[v_pos + 1] = v_e_en,
      'detail', format('SET_NUMBER = ordem do catálogo: %s; V1/qualquer logo antes de V1/en: %s',
                       v_got = v_exp, v_pos is not null and v_got[v_pos + 1] = v_e_en));

    -- 3.3 SET_NUMBER paginado ------------------------------------------------------------
    select array_agg(f.entry_id) into v_p0 from public.get_my_wishlist_filtered(1, 0, null, null, null, null, null, 'SET_NUMBER') f;
    select array_agg(f.entry_id) into v_p1 from public.get_my_wishlist_filtered(1, 1, null, null, null, null, null, 'SET_NUMBER') f;
    select array_agg(f.entry_id) into v_p2 from public.get_my_wishlist_filtered(1, 2, null, null, null, null, null, 'SET_NUMBER') f;
    select bool_and(f.total_count = 3) into v_ok from (
      select * from public.get_my_wishlist_filtered(1, 0, null, null, null, null, null, 'SET_NUMBER')
      union all select * from public.get_my_wishlist_filtered(1, 1, null, null, null, null, null, 'SET_NUMBER')
      union all select * from public.get_my_wishlist_filtered(1, 2, null, null, null, null, null, 'SET_NUMBER')) f;
    select count(*) into v_n from public.get_my_wishlist_filtered(1, 3, null, null, null, null, null, 'SET_NUMBER');
    res := res || jsonb_build_object('id','3.3','ok', v_p0 || v_p1 || v_p2 = v_exp and v_ok and v_n = 0,
      'detail', format('páginas de 1 = ordem completa: %s; total 3 em todas: %s; além do fim: %s', v_p0 || v_p1 || v_p2 = v_exp, v_ok, v_n));

    -- 3.4 SET_NUMBER + filtro -------------------------------------------------------------
    select array_agg(f.entry_id), max(f.total_count) into v_got, v_total
      from public.get_my_wishlist_filtered(100, 0, null, v_s1, null, null, null, 'SET_NUMBER') f;
    res := res || jsonb_build_object('id','3.4','ok', v_got = array[v_e_any, v_e_en] and v_total = 2,
      'detail', format('S1 + SET_NUMBER: %s linhas na ordem qualquer → en: %s; total %s (esperado 2/true/2)',
                       coalesce(cardinality(v_got),0), v_got = array[v_e_any, v_e_en], v_total));
    execute 'reset role';

    -- 3.5 isolamento (B) ------------------------------------------------------------------
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select count(*), bool_and(f.card_variant_id = v_v2) into v_n, v_ok
      from public.get_my_wishlist_filtered(100, 0, null, null, null, null, null, 'SET_NUMBER') f;
    execute 'reset role';
    res := res || jsonb_build_object('id','3.5','ok', v_n = 1 and v_ok,
      'detail', format('B com SET_NUMBER: %s desejo(s), só o próprio: %s (esperado 1/true)', v_n, v_ok));

    -- 3.6 nenhuma escrita -------------------------------------------------------------------
    res := res || jsonb_build_object('id','3.6','ok',
      (select count(*) from public.card_wishlist_entry) = v_base_we + 4
      and (select count(*) from public.physical_card) = v_base_pc + 1
      and (select count(*) from public.card) = v_base_c,
      'detail','depois das leituras: desejos +4 e exemplares +1 (só fixture); catálogo inalterado');

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
  status := case when passes = n and n = 12 then 'PASS' else 'FAIL' end;
  detail := format('%s/%s PASS (esperado 12)', passes, n);
  return next;
end;
$fn$;

select * from pg_temp.tr_5877_validate();
