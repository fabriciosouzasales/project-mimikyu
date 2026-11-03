/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5876 - Harness: Lista de desejos filtrada (V1-11 W6) — 5350
Versão......: 1.0
Status......: v1.0 EXECUTADO no LIVE (2026-11-03, LIVE SQL VALIDATION-02): GATE PASS 17/17,
              sem X.1, resíduo zero. Depois da 5351 não serve mais de gate (procura a
              assinatura de 7 argumentos); a 5877 cobre a versão de 8.
              5350 promovida para database/schema/.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-02

Protocolo (o mesmo da 5873): função em pg_temp, uma chamada; usuários
efêmeros A e B; a sentinela TR000 desfaz tudo o que o harness cria; 9.1
confere resíduo zero. Não lê nem altera dados reais de nenhum usuário e
não altera o catálogo (só LÊ duas cartas ativas de Card Sets diferentes).
Executar SÓ depois de 5345–5347 (W1) e 5350 aplicadas.

Fixture
  A deseja: V1 "qualquer idioma", V1 en, V2 pt-BR   (V1 ∈ Card Set S1, V2 ∈ S2)
  A possui: um exemplar en de V1   → V1/qualquer e V1/en = posse; V2/pt-BR não
  B deseja: V2 "qualquer idioma"   (isolamento)

Checagens (GATE = todas PASS, 17):
  0.1  2 funções: SECURITY DEFINER, search_path vazio, plpgsql, STABLE, 1 versão
  0.2  ACL: EXECUTE só authenticated (anon e PUBLIC sem acesso)
  1.1  anon: 42501 nas 2
  2.1  authenticated sem identidade: 28000 nas 2
  2.2  argumentos inválidos: 22023 (limite 0 e 101, offset -1, busca de 101
       caracteres, posse desconhecida)
  3.1  sem filtro = get_my_wishlist (mesmas linhas, mesma ordem, mesmo total)
  3.2  Card Set S1 → só desejos de cartas com card_set_id = S1 (2); total 2
  3.3  raridade → exatamente os desejos cuja carta tem a raridade pedida
  3.4  idioma: '*' só "qualquer" (1); 'en' só en (1); 'pt-BR' só pt-BR (1);
       código inexistente → 0
  3.5  posse: OWNED = V1/qualquer + V1/en (2); NOT_OWNED = V2/pt-BR (1);
       coluna ownership coerente (SAME_VARIANT_LANGUAGE só nos OWNED)
  3.6  busca: trecho do nome (maiúsculas trocadas) e número sem zeros à
       esquerda casam o esperado; "número/total" casa; texto sem sentido → 0
  3.7  combinação S1 + OWNED + 'en' → 1 (V1/en)
  3.8  paginação: limite 1, offsets 0..2 → páginas disjuntas na ordem da
       5346, total_count = 3 em todas; offset além do fim → 0 linhas
  3.9  isolamento: B vê só o próprio desejo; filtro S1 para B → 0; opções de
       B não citam S1
  3.10 opções de A: Card Sets S1=2 e S2=1; idiomas '*'=1 (primeiro), en=1,
       pt-BR=1; posse OWNED=2, NOT_OWNED=1; soma das raridades = 3
  3.11 nenhuma escrita: desejos, exemplares e catálogo inalterados pelas leituras
  9.1  resíduo zero (usuários, desejos, exemplares) e papel restaurado
Erro inesperado: X.1 FAIL.
================================================================
*/

create or replace function pg_temp.tr_5876_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  v_f1      oid := to_regprocedure('public.get_my_wishlist_filtered(integer,integer,text,uuid,uuid,text,text)');
  v_f2      oid := to_regprocedure('public.get_my_wishlist_filter_options()');
  p_user_a  uuid := gen_random_uuid();
  p_user_b  uuid := gen_random_uuid();
  v_sfx     text := substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
  v_c1      uuid;
  v_c2      uuid;
  v_s1      uuid;
  v_s2      uuid;
  v_v1      uuid;
  v_v2      uuid;
  v_r2      uuid;
  v_name1   text;
  v_num1    text;
  v_tot1    integer;
  v_lang_en uuid;
  v_inv_a   uuid;
  v_e_any   uuid;
  v_e_en    uuid;
  v_e_pt    uuid;
  v_s       text[];
  v_bad     integer;
  v_got     uuid[];
  v_exp     uuid[];
  v_p0      uuid[];
  v_p1      uuid[];
  v_p2      uuid[];
  v_n       integer;
  v_m       integer;
  v_k       integer;
  v_total   bigint;
  v_ok      boolean;
  v_frag    text;
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
    v_f1 is not null and v_f2 is not null
    and (select bool_and(p.prosecdef and p.proconfig = array['search_path=""'] and l.lanname = 'plpgsql' and p.provolatile = 's')
         from pg_proc p join pg_language l on l.oid = p.prolang where p.oid in (v_f1, v_f2))
    and (select count(*) from pg_proc q join pg_namespace ns on ns.oid = q.pronamespace
         where ns.nspname = 'public' and q.proname in ('get_my_wishlist_filtered','get_my_wishlist_filter_options')) = 2,
    'detail','2 funções: SECURITY DEFINER, search_path vazio, plpgsql, STABLE, 1 versão');

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

  begin
    -- 1.1 anon ---------------------------------------------------------------
    v_s := '{}';
    perform set_config('request.jwt.claims', '', true);
    execute 'set local role anon';
    begin perform * from public.get_my_wishlist_filtered(10, 0, null, null, null, null, null); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    begin perform * from public.get_my_wishlist_filter_options(); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.1','ok', v_s = array['42501','42501'], 'detail', 'anon: '||array_to_string(v_s, ', '));

    -- 2.1 sem identidade -------------------------------------------------------
    v_s := '{}';
    execute 'set local role authenticated';
    begin perform * from public.get_my_wishlist_filtered(10, 0, null, null, null, null, null); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    begin perform * from public.get_my_wishlist_filter_options(); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','2.1','ok', v_s = array['28000','28000'], 'detail', 'sem identidade: '||array_to_string(v_s, ', '));

    -- Fixture (dono do banco: o catálogo só é legível por admin) ------------
    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    values (p_user_a, 'authenticated', 'authenticated', 'tr5876-a-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'tr5876a_'||v_sfx, 'display_name', 'TR 5876 A'), now(), now()),
           (p_user_b, 'authenticated', 'authenticated', 'tr5876-b-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'tr5876b_'||v_sfx, 'display_name', 'TR 5876 B'), now(), now());

    select c.id, c.card_set_id, c.name, c.collector_number, c.collector_total
      into v_c1, v_s1, v_name1, v_num1, v_tot1
    from public.card c
    where c.is_active and length(c.name) >= 4
      and exists (select 1 from public.card_variant cv where cv.card_id = c.id and cv.is_active)
    order by c.id limit 1;
    select c.id, c.card_set_id, c.rarity_id into v_c2, v_s2, v_r2
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
    -- Trecho do meio do nome, com maiúsculas trocadas (busca não diferencia).
    v_frag := upper(substr(v_name1, 2, 3));

    -- Exemplar en de V1 no acervo de A (posse).
    insert into public.physical_card (card_variant_id, language_id, inventory_id)
    values (v_v1, v_lang_en, v_inv_a);

    -- Desejos de B e de A (pelas funções da W1, como cada usuário).
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    perform * from public.add_my_wishlist_entry(v_v2, null);
    execute 'reset role';

    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select e.entry_id into v_e_any from public.add_my_wishlist_entry(v_v1, null) e;
    select e.entry_id into v_e_en  from public.add_my_wishlist_entry(v_v1, 'en') e;
    select e.entry_id into v_e_pt  from public.add_my_wishlist_entry(v_v2, 'pt-BR') e;

    -- 2.2 argumentos inválidos -------------------------------------------------
    v_bad := 0;
    begin perform * from public.get_my_wishlist_filtered(0, 0, null, null, null, null, null); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.get_my_wishlist_filtered(101, 0, null, null, null, null, null); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.get_my_wishlist_filtered(10, -1, null, null, null, null, null); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.get_my_wishlist_filtered(10, 0, repeat('a', 101), null, null, null, null); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.get_my_wishlist_filtered(10, 0, null, null, null, null, 'TALVEZ'); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    res := res || jsonb_build_object('id','2.2','ok', v_bad = 0, 'detail', format('%s argumentos inválidos aceitos (esperado 0)', v_bad));

    -- 3.1 sem filtro = 5346 ------------------------------------------------------
    select array_agg(f.entry_id order by f.wished_at desc, f.entry_id), max(f.total_count) into v_got, v_total
      from public.get_my_wishlist_filtered(100, 0, null, null, null, null, null) f;
    select array_agg(g.entry_id order by g.wished_at desc, g.entry_id) into v_exp from public.get_my_wishlist(100, 0) g;
    res := res || jsonb_build_object('id','3.1','ok', v_got = v_exp and v_total = 3 and cardinality(v_got) = 3,
      'detail', format('sem filtro: %s linhas, total %s, igual à 5346: %s', coalesce(cardinality(v_got),0), v_total, v_got = v_exp));

    -- 3.2 Card Set ----------------------------------------------------------------
    select count(*), max(f.total_count), bool_and(f.card_set_id = v_s1) into v_n, v_total, v_ok
      from public.get_my_wishlist_filtered(100, 0, null, v_s1, null, null, null) f;
    res := res || jsonb_build_object('id','3.2','ok', v_n = 2 and v_total = 2 and v_ok,
      'detail', format('Card Set S1: %s linhas, total %s, todas de S1: %s (esperado 2/2/true)', v_n, v_total, v_ok));

    -- 3.3 raridade -----------------------------------------------------------------
    select array_agg(f.entry_id order by f.entry_id) into v_got
      from public.get_my_wishlist_filtered(100, 0, null, null, v_r2, null, null) f;
    execute 'reset role';
    select array_agg(w.id order by w.id) into v_exp
      from public.card_wishlist_entry w
      join public.card_variant cv on cv.id = w.card_variant_id
      join public.card c on c.id = cv.card_id
     where w.user_id = p_user_a and c.rarity_id = v_r2;
    execute 'set local role authenticated';
    res := res || jsonb_build_object('id','3.3','ok', v_got is not distinct from v_exp and v_exp is not null,
      'detail', format('raridade: %s linhas, esperado %s', coalesce(cardinality(v_got),0), coalesce(cardinality(v_exp),0)));

    -- 3.4 idioma ---------------------------------------------------------------------
    select array_agg(f.entry_id) into v_p0 from public.get_my_wishlist_filtered(100, 0, null, null, null, '*', null) f;
    select array_agg(f.entry_id) into v_p1 from public.get_my_wishlist_filtered(100, 0, null, null, null, 'en', null) f;
    select array_agg(f.entry_id) into v_p2 from public.get_my_wishlist_filtered(100, 0, null, null, null, 'pt-BR', null) f;
    select count(*) into v_n from public.get_my_wishlist_filtered(100, 0, null, null, null, 'xx-YY', null);
    res := res || jsonb_build_object('id','3.4','ok',
      v_p0 = array[v_e_any] and v_p1 = array[v_e_en] and v_p2 = array[v_e_pt] and v_n = 0,
      'detail', format('qualquer=%s en=%s pt-BR=%s inexistente=%s (esperado 1/1/1/0, cada um o desejo certo)',
                       coalesce(cardinality(v_p0),0), coalesce(cardinality(v_p1),0), coalesce(cardinality(v_p2),0), v_n));

    -- 3.5 posse ---------------------------------------------------------------------------
    select array_agg(f.entry_id order by f.entry_id), bool_and(f.ownership = 'SAME_VARIANT_LANGUAGE') into v_got, v_ok
      from public.get_my_wishlist_filtered(100, 0, null, null, null, null, 'OWNED') f;
    -- 'not_owned' em minúsculas: a função normaliza o valor.
    select count(*), coalesce(v_ok, false) and bool_and(f.ownership <> 'SAME_VARIANT_LANGUAGE') into v_n, v_ok
      from public.get_my_wishlist_filtered(100, 0, null, null, null, null, 'not_owned') f;
    res := res || jsonb_build_object('id','3.5','ok',
      v_got = (select array_agg(x order by x) from unnest(array[v_e_any, v_e_en]) x) and v_n = 1 and coalesce(v_ok, false),
      'detail', format('OWNED=%s NOT_OWNED=%s, ownership coerente: %s (esperado 2/1/true)', coalesce(cardinality(v_got),0), v_n, coalesce(v_ok, false)));

    -- 3.6 busca ----------------------------------------------------------------------------
    select array_agg(f.entry_id order by f.entry_id) into v_got
      from public.get_my_wishlist_filtered(100, 0, v_frag, null, null, null, null) f;
    execute 'reset role';
    select array_agg(w.id order by w.id) into v_exp
      from public.card_wishlist_entry w
      join public.card_variant cv on cv.id = w.card_variant_id
      join public.card c on c.id = cv.card_id
     where w.user_id = p_user_a and lower(c.name) like '%' || lower(v_frag) || '%';
    execute 'set local role authenticated';
    v_ok := v_got is not distinct from v_exp and v_e_any = any(v_got);
    select count(*) into v_n
      from public.get_my_wishlist_filtered(100, 0, '000' || v_num1, null, null, null, null) f
      where f.card_id = v_c1;
    select count(*) into v_m
      from public.get_my_wishlist_filtered(100, 0, v_num1 || '/' || coalesce(v_tot1::text, ''), null, null, null, null) f
      where f.card_id = v_c1;
    select count(*) into v_k from public.get_my_wishlist_filtered(100, 0, 'zzqx#tr5876', null, null, null, null);
    res := res || jsonb_build_object('id','3.6','ok', v_ok and v_n = 2 and v_m = 2 and v_k = 0,
      'detail', format('nome por trecho: %s; número com zeros: %s; número/total: %s; sem sentido: %s (esperado true/2/2/0)', v_ok, v_n, v_m, v_k));

    -- 3.7 combinação -------------------------------------------------------------------------
    select array_agg(f.entry_id), max(f.total_count) into v_got, v_total
      from public.get_my_wishlist_filtered(100, 0, null, v_s1, null, 'en', 'OWNED') f;
    res := res || jsonb_build_object('id','3.7','ok', v_got = array[v_e_en] and v_total = 1,
      'detail', format('S1 + en + OWNED: %s linhas, total %s (esperado 1/1)', coalesce(cardinality(v_got),0), v_total));

    -- 3.8 paginação ---------------------------------------------------------------------------
    select array_agg(f.entry_id) into v_p0 from public.get_my_wishlist_filtered(1, 0, null, null, null, null, null) f;
    select array_agg(f.entry_id) into v_p1 from public.get_my_wishlist_filtered(1, 1, null, null, null, null, null) f;
    select array_agg(f.entry_id) into v_p2 from public.get_my_wishlist_filtered(1, 2, null, null, null, null, null) f;
    select bool_and(f.total_count = 3) into v_ok from (
      select * from public.get_my_wishlist_filtered(1, 0, null, null, null, null, null)
      union all select * from public.get_my_wishlist_filtered(1, 1, null, null, null, null, null)
      union all select * from public.get_my_wishlist_filtered(1, 2, null, null, null, null, null)) f;
    select count(*) into v_n from public.get_my_wishlist_filtered(1, 3, null, null, null, null, null);
    select array_agg(g.entry_id order by g.wished_at desc, g.entry_id) into v_exp from public.get_my_wishlist(100, 0) g;
    res := res || jsonb_build_object('id','3.8','ok',
      v_p0 || v_p1 || v_p2 = v_exp and v_ok and v_n = 0,
      'detail', format('páginas de 1 = ordem da 5346: %s; total 3 em todas: %s; além do fim: %s', v_p0 || v_p1 || v_p2 = v_exp, v_ok, v_n));

    -- 3.10 opções de A ------------------------------------------------------------------------
    select
      (select count(*) = 2 from public.get_my_wishlist_filter_options() o where o.kind = 'CARD_SET')
      and (select o.entry_count = 2 from public.get_my_wishlist_filter_options() o where o.kind = 'CARD_SET' and o.option_value = v_s1::text)
      and (select o.entry_count = 1 from public.get_my_wishlist_filter_options() o where o.kind = 'CARD_SET' and o.option_value = v_s2::text)
      and (select o.entry_count = 1 and o.sort_key = 1 from public.get_my_wishlist_filter_options() o where o.kind = 'LANGUAGE' and o.option_value = '*')
      and (select o.entry_count = 1 from public.get_my_wishlist_filter_options() o where o.kind = 'LANGUAGE' and o.option_value = 'en')
      and (select o.entry_count = 1 from public.get_my_wishlist_filter_options() o where o.kind = 'LANGUAGE' and o.option_value = 'pt-BR')
      and (select o.entry_count = 2 from public.get_my_wishlist_filter_options() o where o.kind = 'OWNERSHIP' and o.option_value = 'OWNED')
      and (select o.entry_count = 1 from public.get_my_wishlist_filter_options() o where o.kind = 'OWNERSHIP' and o.option_value = 'NOT_OWNED')
      and (select sum(o.entry_count) = 3 from public.get_my_wishlist_filter_options() o where o.kind = 'RARITY')
    into v_ok;
    res := res || jsonb_build_object('id','3.10','ok', coalesce(v_ok, false),
      'detail','opções de A: Card Sets 2/1, idiomas qualquer(1º)/en/pt-BR = 1, posse 2/1, raridades somam 3');
    execute 'reset role';

    -- 3.9 isolamento (B) ------------------------------------------------------------------------
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select count(*), bool_and(f.card_variant_id = v_v2) into v_n, v_ok from public.get_my_wishlist_filtered(100, 0, null, null, null, null, null) f;
    select count(*) into v_m from public.get_my_wishlist_filtered(100, 0, null, v_s1, null, null, null);
    select count(*) into v_k from public.get_my_wishlist_filter_options() o where o.kind = 'CARD_SET' and o.option_value = v_s1::text;
    execute 'reset role';
    res := res || jsonb_build_object('id','3.9','ok', v_n = 1 and v_ok and v_m = 0 and v_k = 0,
      'detail', format('B: %s desejo(s) próprio(s); S1 para B: %s; opção S1 para B: %s (esperado 1/0/0)', v_n, v_m, v_k));

    -- 3.11 nenhuma escrita pelas leituras ---------------------------------------------------------
    res := res || jsonb_build_object('id','3.11','ok',
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
  status := case when passes = n and n = 17 then 'PASS' else 'FAIL' end;
  detail := format('%s/%s PASS (esperado 17)', passes, n);
  return next;
end;
$fn$;

select * from pg_temp.tr_5876_validate();
