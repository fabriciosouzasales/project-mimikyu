/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5879 - Harness: Inventário e valor do Acervo (V1-14 R1-B) — 5353
Versão......: 1.0
Status......: PROPOSTO — NÃO EXECUTADO; EM REAVALIAÇÃO, NÃO APLICAR (REPORT CATALOG
              RESTRUCTURING-03, 2026-11-06: Valor, Top 10 e Cobertura viram relatórios distintos)
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-06

Protocolo (o mesmo da 5876–5878): função em pg_temp, uma chamada; usuários
efêmeros A e B; a sentinela TR000 desfaz tudo o que o harness cria; 9.1
confere resíduo zero. Não lê nem altera dados de nenhum usuário real; não
altera catálogo nem Pricing (só LÊ variantes ativas e as referências da
3983 dessas variantes). Executar SÓ depois de 5353 aplicada.

Fixture
  Até 300 variantes ativas (ordem por id) consultadas na 3983 como A:
  Vp = primeira com referência válida (> 0); Vu = primeira sem referência.
  Sem ambas → TR_FIXTURE (o harness não fabrica preço).

Checagens (GATE = todas PASS, 14):
  0.1  SECURITY DEFINER, search_path vazio, plpgsql, STABLE, 1 versão
  0.2  ACL: EXECUTE só authenticated (anon e PUBLIC sem acesso)
  1.1  anon: 42501
  2.1  authenticated sem identidade: 28000
  2.2  p_top inválido (nulo, 0, 51) → 22023
  3.1  acervo vazio: zeros, total_brl NULL (nunca 0), datas NULL, Top []
  3.2  cálculo por exemplar: Vp en ×2 + Vp pt-BR ×1 + Vu en ×1 → 4
       exemplares, 3 diferentes, 1 repetida, 2 variantes, 1 cotada, 3
       exemplares com preço, 1 sem preço, total = 3 × referência(Vp) da 3983;
       datas = observed_at da referência
  3.3  coerência com 5160: exemplares, diferentes e repetidas idênticos
  3.4  Top: só os 3 exemplares cotados (Vu ausente), ids físicos distintos,
       rank 1..3, cópia 1/2 e 2/2 (en) e 1/1 (pt-BR); 2ª chamada idêntica
  3.5  limite: +10 exemplares de Vp → Top padrão = 10, p_top 50 = 13;
       total = 13 × referência(Vp)
  3.6  isolamento: B vazio vê zeros e Top []; B com 1 exemplar de Vp vê só
       o seu; números de A inalterados; B não recebe ids de A
  3.7  somente leitura: exemplares, inventários, coleções, alocações,
       desejos, observações de preço e preços manuais inalterados pelas
       chamadas
  3.8  volume: +2.000 exemplares de A sobre as variantes candidatas →
       cotados + sem preço = total; total_brl = Σ por exemplar recalculado
       a partir da 3983; tempo < 3.000 ms
  9.1  resíduo zero (usuários, exemplares) e papel restaurado
Erro inesperado: X.1 FAIL.
================================================================
*/

create or replace function pg_temp.tr_5879_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  v_f       oid := to_regprocedure('public.get_my_inventory_value_report(integer)');
  p_user_a  uuid := gen_random_uuid();
  p_user_b  uuid := gen_random_uuid();
  v_sfx     text := substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
  v_cand    uuid[];
  v_pr_ids  uuid[] := '{}';
  v_pr_brl  numeric[] := '{}';
  v_pr_obs  timestamptz[] := '{}';
  v_vp      uuid;
  v_vu      uuid;
  v_vp_brl  numeric;
  v_vp_obs  timestamptz;
  v_cards   bigint;
  v_lang_en uuid;
  v_lang_pt uuid;
  v_inv_a   uuid;
  v_inv_b   uuid;
  v_a_ids   uuid[];
  v_a_all   uuid[];
  v_s       text[];
  v_bad     integer;
  v_i       integer;
  r_rep     record;
  r_sum     record;
  v_top     jsonb;
  v_top2    jsonb;
  v_ok      boolean;
  v_exp     numeric;
  v_t0      timestamptz;
  v_ms      numeric;
  v_base_us bigint;
  v_base_pc bigint;
  v_c_pc bigint; v_c_inv bigint; v_c_co bigint; v_c_al bigint; v_c_we bigint; v_c_po bigint; v_c_mp bigint;
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
         where ns.nspname = 'public' and q.proname = 'get_my_inventory_value_report') = 1,
    'detail','SECURITY DEFINER, search_path vazio, plpgsql, STABLE, 1 versão');

  res := res || jsonb_build_object('id','0.2','ok',
    v_f is not null
    and has_function_privilege('authenticated', v_f, 'EXECUTE')
    and not has_function_privilege('anon', v_f, 'EXECUTE')
    and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = v_f and a.grantee = 0),
    'detail','EXECUTE só authenticated (anon e PUBLIC sem acesso)');

  select count(*) into v_base_us from auth.users;
  select count(*) into v_base_pc from public.physical_card;

  begin
    -- 1.1 anon -----------------------------------------------------------------
    v_s := '{}';
    perform set_config('request.jwt.claims', '', true);
    execute 'set local role anon';
    begin perform * from public.get_my_inventory_value_report(); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.1','ok', v_s = array['42501'], 'detail', 'anon: '||array_to_string(v_s, ', '));

    -- 2.1 sem identidade ---------------------------------------------------------
    v_s := '{}';
    execute 'set local role authenticated';
    begin perform * from public.get_my_inventory_value_report(); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','2.1','ok', v_s = array['28000'], 'detail', 'sem identidade: '||array_to_string(v_s, ', '));

    -- Fixture (dono do banco: catálogo legível) ---------------------------------
    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    values (p_user_a, 'authenticated', 'authenticated', 'tr5879-a-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'tr5879a_'||v_sfx, 'display_name', 'TR 5879 A'), now(), now()),
           (p_user_b, 'authenticated', 'authenticated', 'tr5879-b-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'tr5879b_'||v_sfx, 'display_name', 'TR 5879 B'), now(), now());
    select iv.id into v_inv_a from public.inventory iv where iv.owner_user_id = p_user_a;
    select iv.id into v_inv_b from public.inventory iv where iv.owner_user_id = p_user_b;
    select l.id into v_lang_en from public.language l where l.code = 'en';
    select l.id into v_lang_pt from public.language l where l.code = 'pt-BR';

    select array_agg(x.id order by x.id) into v_cand from (
      select cv.id from public.card_variant cv join public.card c on c.id = cv.card_id
      where cv.is_active and c.is_active order by cv.id limit 300) x;

    -- Referências canônicas (3983) das candidatas, como A.
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    v_i := 1;
    while v_i <= coalesce(cardinality(v_cand), 0) loop
      select v_pr_ids || coalesce(array_agg(s.card_variant_id) filter (where s.has_pricing and s.brl_amount > 0), '{}'),
             v_pr_brl || coalesce(array_agg(s.brl_amount)      filter (where s.has_pricing and s.brl_amount > 0), '{}'),
             v_pr_obs || coalesce(array_agg(s.observed_at)     filter (where s.has_pricing and s.brl_amount > 0), '{}'),
             coalesce(v_vu, (array_agg(s.card_variant_id order by s.card_variant_id) filter (where not (s.has_pricing and coalesce(s.brl_amount, 0) > 0)))[1])
        into v_pr_ids, v_pr_brl, v_pr_obs, v_vu
      from public.get_card_variants_pricing_summary(v_cand[v_i : least(v_i + 99, cardinality(v_cand))]) s;
      v_i := v_i + 100;
    end loop;
    v_vp := v_pr_ids[1]; v_vp_brl := v_pr_brl[1]; v_vp_obs := v_pr_obs[1];
    if v_vp is null or v_vu is null or v_lang_en is null or v_lang_pt is null or v_inv_a is null or v_inv_b is null then
      raise exception 'TR_FIXTURE: sem variante cotada e não cotada entre as candidatas, idioma en/pt-BR ou inventário ausente';
    end if;
    select count(distinct cv.card_id) into v_cards from public.card_variant cv where cv.id in (v_vp, v_vu);

    -- 2.2 p_top inválido -----------------------------------------------------------
    execute 'set local role authenticated';
    v_bad := 0;
    begin perform * from public.get_my_inventory_value_report(null); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.get_my_inventory_value_report(0);    v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.get_my_inventory_value_report(51);   v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    res := res || jsonb_build_object('id','2.2','ok', v_bad = 0, 'detail', format('%s valores de p_top inválidos aceitos (esperado 0)', v_bad));

    -- 3.1 acervo vazio -----------------------------------------------------------------
    select * into r_rep from public.get_my_inventory_value_report();
    res := res || jsonb_build_object('id','3.1','ok',
      r_rep.total_copies = 0 and r_rep.distinct_items = 0 and r_rep.duplicate_copies = 0 and r_rep.distinct_cards = 0
      and r_rep.variant_count = 0 and r_rep.priced_variant_count = 0 and r_rep.priced_copies = 0 and r_rep.unpriced_copies = 0
      and r_rep.total_brl is null and r_rep.price_observed_min is null and r_rep.price_observed_max is null
      and r_rep.top_copies = '[]'::jsonb,
      'detail', format('vazio: %s exemplares, total %s, Top %s (esperado 0 / NULL / [])', r_rep.total_copies, coalesce(r_rep.total_brl::text,'NULL'), r_rep.top_copies));
    execute 'reset role';

    -- 3.2 cálculo por exemplar ------------------------------------------------------------
    insert into public.physical_card (card_variant_id, language_id, inventory_id, created_at) values
      (v_vp, v_lang_en, v_inv_a, now() - interval '3 day'),
      (v_vp, v_lang_en, v_inv_a, now() - interval '2 day'),
      (v_vp, v_lang_pt, v_inv_a, now() - interval '1 day'),
      (v_vu, v_lang_en, v_inv_a, now());
    select array_agg(pc.id order by pc.created_at) into v_a_ids from public.physical_card pc where pc.inventory_id = v_inv_a and pc.card_variant_id = v_vp;
    select count(*) into v_c_pc  from public.physical_card;
    select count(*) into v_c_inv from public.inventory;
    select count(*) into v_c_co  from public.collection;
    select count(*) into v_c_al  from public.collection_allocation;
    select count(*) into v_c_we  from public.card_wishlist_entry;
    select count(*) into v_c_po  from public.pricing_observation;
    select count(*) into v_c_mp  from public.pricing_manual_price;

    execute 'set local role authenticated';
    select * into r_rep from public.get_my_inventory_value_report();
    res := res || jsonb_build_object('id','3.2','ok',
      r_rep.total_copies = 4 and r_rep.distinct_items = 3 and r_rep.duplicate_copies = 1 and r_rep.distinct_cards = v_cards
      and r_rep.variant_count = 2 and r_rep.priced_variant_count = 1 and r_rep.priced_copies = 3 and r_rep.unpriced_copies = 1
      and r_rep.total_brl = 3 * v_vp_brl
      and r_rep.price_observed_min is not distinct from v_vp_obs and r_rep.price_observed_max is not distinct from v_vp_obs,
      'detail', format('%s ex / %s dif / %s rep / %s cartas / %s var / %s cotada / %s com preço / %s sem; total %s (esperado 4/3/1/%s/2/1/3/1; %s)',
        r_rep.total_copies, r_rep.distinct_items, r_rep.duplicate_copies, r_rep.distinct_cards, r_rep.variant_count,
        r_rep.priced_variant_count, r_rep.priced_copies, r_rep.unpriced_copies, r_rep.total_brl, v_cards, 3 * v_vp_brl));

    -- 3.3 coerência com 5160 ---------------------------------------------------------------
    select * into r_sum from public.get_my_inventory_summary();
    res := res || jsonb_build_object('id','3.3','ok',
      r_sum.total_copies = r_rep.total_copies and r_sum.distinct_items = r_rep.distinct_items and r_sum.duplicate_copies = r_rep.duplicate_copies,
      'detail', format('5160: %s/%s/%s; 5353: %s/%s/%s', r_sum.total_copies, r_sum.distinct_items, r_sum.duplicate_copies,
        r_rep.total_copies, r_rep.distinct_items, r_rep.duplicate_copies));

    -- 3.4 Top ---------------------------------------------------------------------------------
    v_top := r_rep.top_copies;
    select * into r_rep from public.get_my_inventory_value_report();
    v_top2 := r_rep.top_copies;
    select jsonb_array_length(v_top) = 3
       and (select bool_and((e->>'card_variant_id')::uuid = v_vp and (e->>'brl_amount')::numeric = v_vp_brl) from jsonb_array_elements(v_top) e)
       and (select array_agg((e->>'physical_card_id')::uuid order by (e->>'physical_card_id')) from jsonb_array_elements(v_top) e)
           = (select array_agg(x order by x::text) from unnest(v_a_ids) x)
       and (select array_agg((e->>'rank')::int order by (e->>'rank')::int) from jsonb_array_elements(v_top) e) = array[1,2,3]
       and (select array_agg((e->>'copy_index')||'/'||(e->>'copy_count')||(e->>'language_code') order by (e->>'copy_index')||'/'||(e->>'copy_count')||(e->>'language_code'))
            from jsonb_array_elements(v_top) e) = array['1/1pt-BR','1/2en','2/2en']
       and v_top = v_top2
      into v_ok;
    res := res || jsonb_build_object('id','3.4','ok', coalesce(v_ok, false),
      'detail', format('Top: %s itens, só cotados, cópias identificadas, determinístico: %s', jsonb_array_length(v_top), coalesce(v_ok, false)));
    execute 'reset role';

    -- 3.5 limite do Top --------------------------------------------------------------------------
    insert into public.physical_card (card_variant_id, language_id, inventory_id)
    select v_vp, v_lang_en, v_inv_a from generate_series(1, 10);
    execute 'set local role authenticated';
    select * into r_rep from public.get_my_inventory_value_report();
    v_i := jsonb_array_length(r_rep.top_copies);
    select * into r_sum from public.get_my_inventory_value_report(50);
    res := res || jsonb_build_object('id','3.5','ok',
      v_i = 10 and jsonb_array_length(r_sum.top_copies) = 13 and r_rep.priced_copies = 13 and r_rep.total_brl = 13 * v_vp_brl,
      'detail', format('Top padrão %s, Top 50 %s, com preço %s, total %s (esperado 10/13/13/%s)',
        v_i, jsonb_array_length(r_sum.top_copies), r_rep.priced_copies, r_rep.total_brl, 13 * v_vp_brl));
    execute 'reset role';

    -- 3.6 isolamento ---------------------------------------------------------------------------------
    select array_agg(pc.id) into v_a_all from public.physical_card pc where pc.inventory_id = v_inv_a;
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select * into r_rep from public.get_my_inventory_value_report();
    v_ok := r_rep.total_copies = 0 and r_rep.total_brl is null and r_rep.top_copies = '[]'::jsonb;
    execute 'reset role';
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_vp, v_lang_en, v_inv_b);
    execute 'set local role authenticated';
    select * into r_rep from public.get_my_inventory_value_report();
    v_ok := v_ok and r_rep.total_copies = 1 and r_rep.total_brl = v_vp_brl
      and not exists (select 1 from jsonb_array_elements(r_rep.top_copies) e
                      where (e->>'physical_card_id')::uuid = any(v_a_all));
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select * into r_sum from public.get_my_inventory_value_report();
    v_ok := v_ok and r_sum.total_copies = 14 and r_sum.priced_copies = 13;
    res := res || jsonb_build_object('id','3.6','ok', coalesce(v_ok, false),
      'detail', format('B vazio → zeros; B com 1 exemplar vê só o seu; A continua com %s exemplares: %s', r_sum.total_copies, coalesce(v_ok, false)));
    execute 'reset role';

    -- 3.7 somente leitura -------------------------------------------------------------------------------
    res := res || jsonb_build_object('id','3.7','ok',
      (select count(*) from public.physical_card) = v_c_pc + 11
      and (select count(*) from public.inventory) = v_c_inv
      and (select count(*) from public.collection) = v_c_co
      and (select count(*) from public.collection_allocation) = v_c_al
      and (select count(*) from public.card_wishlist_entry) = v_c_we
      and (select count(*) from public.pricing_observation) = v_c_po
      and (select count(*) from public.pricing_manual_price) = v_c_mp,
      'detail','só os exemplares da fixture (+11); inventários, coleções, alocações, desejos e preços inalterados');

    -- 3.8 volume --------------------------------------------------------------------------------------------
    insert into public.physical_card (card_variant_id, language_id, inventory_id)
    select v_cand[1 + (g % cardinality(v_cand))], v_lang_en, v_inv_a from generate_series(1, 2000) g;
    select sum(p.brl) into v_exp
    from public.physical_card pc
    join unnest(v_pr_ids, v_pr_brl) as p(vid, brl) on p.vid = pc.card_variant_id
    where pc.inventory_id = v_inv_a;
    execute 'set local role authenticated';
    v_t0 := clock_timestamp();
    select * into r_rep from public.get_my_inventory_value_report();
    v_ms := extract(epoch from clock_timestamp() - v_t0) * 1000;
    res := res || jsonb_build_object('id','3.8','ok',
      r_rep.total_copies = 2014 and r_rep.priced_copies + r_rep.unpriced_copies = r_rep.total_copies
      and r_rep.total_brl = v_exp and v_ms < 3000,
      'detail', format('%s exemplares, %s variantes; total %s = recálculo %s; %s ms (limite 3.000)',
        r_rep.total_copies, r_rep.variant_count, r_rep.total_brl, v_exp, round(v_ms)));
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
      and (select count(*) from public.physical_card) = v_base_pc
      and current_user = session_user,
    'detail','resíduo zero (usuários, exemplares) e papel restaurado');

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

select * from pg_temp.tr_5879_validate();
