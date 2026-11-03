/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5875 - Harness: cartas do catálogo por espécie (V1-11 W4) — 5349
Versão......: 1.0
Status......: v1.0 EXECUTADA no LIVE (LIVE SQL VALIDATION-02, 2026-11-02):
              GATE PASS 11/11, sem X.1, sem dados criados.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-02

Protocolo (o mesmo da 5873/5874): função em pg_temp, uma chamada; a
sentinela TR000 desfaz tudo; 9.1 confere papel restaurado. Não cria
usuário (a função só exige auth.uid() — claims com sub efêmero), não lê
dados de usuário e não altera o catálogo (o catálogo só é LIDO, como dono
do banco, para calcular o esperado).

Checagens (GATE = todas PASS, 11):
  0.1  função: SECURITY DEFINER, search_path vazio, plpgsql, STABLE, 1 versão
  0.2  ACL: EXECUTE só authenticated (anon e PUBLIC sem acesso)
  1.1  anon: 42501
  2.1  authenticated sem identidade: 28000
  2.2  argumentos inválidos: 22023 (espécie nula; limite 0 e 61; offset -1 e 10001)
  3.1  conjunto exato: para até 120 espécies com cartas, a função (paginada
       de 60 em 60 até o fim) devolve exatamente as cartas ativas POKEMON
       da espécie com ao menos uma variante ativa; total_count = esperado
  3.2  exclusões: nenhuma carta devolvida é inativa, de outra categoria,
       de outra espécie ou sem variante ativa
  3.3  paginação: páginas disjuntas, sem buraco, ordem estável entre duas leituras
  3.4  espécie inexistente → 0 linhas
  3.5  active_variant_count = número real de variantes ativas da carta
  9.1  papel restaurado e claims limpas
Erro inesperado: X.1 FAIL.
================================================================
*/

create or replace function pg_temp.tr_5875_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  v_f       oid := to_regprocedure('public.get_catalog_cards_for_species(uuid,integer,integer)');
  v_species uuid[];
  v_sp      uuid;
  v_exp     uuid[];
  v_got     uuid[];
  v_page    uuid[];
  v_again   uuid[];
  v_seen    uuid[] := '{}';
  v_total   bigint;
  v_tot_bad integer := 0;
  v_set_bad integer := 0;
  v_pag_bad integer := 0;
  v_off     integer;
  v_k       integer;
  v_bad     integer;
  v_n       integer;
  v_counts  jsonb := '{}'::jsonb;
  v_vars    jsonb;
  v_s       text[];
  res       jsonb := '[]'::jsonb;
  r         jsonb;
  n         integer := 0;
  passes    integer := 0;
begin
  res := res || jsonb_build_object('id','0.1','ok',
    v_f is not null
    and (select p.prosecdef and p.proconfig = array['search_path=""'] and l.lanname = 'plpgsql' and p.provolatile = 's'
         from pg_proc p join pg_language l on l.oid = p.prolang where p.oid = v_f)
    and (select count(*) from pg_proc q join pg_namespace ns on ns.oid = q.pronamespace
         where ns.nspname = 'public' and q.proname = 'get_catalog_cards_for_species') = 1,
    'detail','SECURITY DEFINER, search_path vazio, plpgsql, STABLE, 1 versão');

  res := res || jsonb_build_object('id','0.2','ok',
    v_f is not null
    and has_function_privilege('authenticated', v_f, 'EXECUTE')
    and not has_function_privilege('anon', v_f, 'EXECUTE')
    and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = v_f and a.grantee = 0),
    'detail','EXECUTE só authenticated (anon e PUBLIC sem acesso)');

  begin
    -- 1.1 anon ------------------------------------------------------------
    perform set_config('request.jwt.claims', '', true);
    execute 'set local role anon';
    v_s := '{}';
    begin perform * from public.get_catalog_cards_for_species(gen_random_uuid(), 24, 0); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.1','ok', v_s = array['42501'], 'detail', 'anon: '||array_to_string(v_s, ', '));

    -- 2.1 sem identidade ---------------------------------------------------
    execute 'set local role authenticated';
    v_s := '{}';
    begin perform * from public.get_catalog_cards_for_species(gen_random_uuid(), 24, 0); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','2.1','ok', v_s = array['28000'], 'detail', 'sem identidade: '||array_to_string(v_s, ', '));

    -- Esperados (dono do banco) ----------------------------------------------
    select array_agg(x.sp) into v_species from (
      select cps.pokemon_species_id as sp
      from public.card_primary_species cps
      join public.card c on c.id = cps.card_id and c.is_active
      group by cps.pokemon_species_id
      order by count(*) desc, cps.pokemon_species_id
      limit 120
    ) x;
    if v_species is null then
      raise exception 'TR_FIXTURE: catálogo sem carta com espécie primária';
    end if;

    perform set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role','authenticated')::text, true);
    execute 'set local role authenticated';

    -- 2.2 argumentos inválidos ---------------------------------------------
    v_bad := 0;
    begin perform * from public.get_catalog_cards_for_species(null, 24, 0); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.get_catalog_cards_for_species(v_species[1], 0, 0); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.get_catalog_cards_for_species(v_species[1], 61, 0); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.get_catalog_cards_for_species(v_species[1], 24, -1); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    begin perform * from public.get_catalog_cards_for_species(v_species[1], 24, 10001); v_bad := v_bad + 1; exception when sqlstate '22023' then null; end;
    res := res || jsonb_build_object('id','2.2','ok', v_bad = 0, 'detail', format('%s de 5 chamadas inválidas não recusadas com 22023', v_bad));

    -- 3.1/3.3 leitura paginada por espécie (como authenticated) --------------
    for v_k in 1..cardinality(v_species) loop
      v_sp := v_species[v_k];
      v_got := '{}'; v_off := 0; v_total := null;
      loop
        select coalesce(array_agg(t.card_id order by t.ord), '{}'), max(t.total_count)
          into v_page, v_total
        from public.get_catalog_cards_for_species(v_sp, 60, v_off)
             with ordinality t(card_id, card_name, collector_number, collector_total, card_set_code, card_set_name,
                               image_path_pt, image_path_en, active_variant_count, total_count, ord);
        exit when cardinality(v_page) = 0;
        if v_got && v_page then v_pag_bad := v_pag_bad + 1; end if;   -- páginas sobrepostas
        v_got := v_got || v_page;
        v_off := v_off + 60;
        exit when v_off >= 10000;
      end loop;
      -- estabilidade: a 1ª página relida tem a mesma ordem
      select coalesce(array_agg(t.card_id order by t.ord), '{}') into v_again
      from public.get_catalog_cards_for_species(v_sp, 60, 0)
           with ordinality t(card_id, card_name, collector_number, collector_total, card_set_code, card_set_name,
                             image_path_pt, image_path_en, active_variant_count, total_count, ord);
      if v_again <> v_got[1:cardinality(v_again)] then v_pag_bad := v_pag_bad + 1; end if;
      if v_total is not null and v_total <> cardinality(v_got) then v_tot_bad := v_tot_bad + 1; end if;
      v_counts := v_counts || jsonb_build_object(v_sp::text, to_jsonb(v_got));
      v_seen := v_seen || v_got;
    end loop;

    -- 3.5 contagem de variantes (lida como authenticated, conferida como dono)
    select coalesce(jsonb_agg(jsonb_build_object('card_id', t.card_id, 'n', t.active_variant_count)), '[]'::jsonb)
      into v_vars
    from unnest(v_species[1:10]) s(sp)
    cross join lateral public.get_catalog_cards_for_species(s.sp, 60, 0) t;

    execute 'reset role';

    -- 3.1 conjunto exato (esperado calculado como dono)
    for v_k in 1..cardinality(v_species) loop
      v_sp := v_species[v_k];
      select coalesce(array_agg(c.id order by c.id), '{}') into v_exp
      from public.card_primary_species cps
      join public.card c on c.id = cps.card_id and c.is_active
      join public.card_category cc on cc.id = c.category_id and cc.code = 'POKEMON'
      where cps.pokemon_species_id = v_sp
        and exists (select 1 from public.card_variant cv where cv.card_id = c.id and cv.is_active);
      select coalesce(array_agg(j.x::uuid order by j.x::uuid), '{}') into v_got
      from jsonb_array_elements_text(coalesce(v_counts -> v_sp::text, '[]'::jsonb)) j(x);
      if v_got <> v_exp then v_set_bad := v_set_bad + 1; end if;
    end loop;
    res := res || jsonb_build_object('id','3.1','ok', v_set_bad = 0 and v_tot_bad = 0,
      'detail', format('%s de %s espécies com conjunto divergente; %s com total_count divergente', v_set_bad, cardinality(v_species), v_tot_bad));

    -- 3.2 exclusões
    select count(*) into v_n
    from unnest(v_seen) s(id)
    join public.card c on c.id = s.id
    join public.card_category cc on cc.id = c.category_id
    left join public.card_primary_species cps on cps.card_id = c.id
    where not c.is_active
       or cc.code <> 'POKEMON'
       or cps.pokemon_species_id is null
       or not exists (select 1 from public.card_variant cv where cv.card_id = c.id and cv.is_active);
    res := res || jsonb_build_object('id','3.2','ok', v_n = 0,
      'detail', format('%s cartas devolvidas inativas, de outra categoria, sem espécie ou sem variante ativa (esperado 0); %s cartas conferidas', v_n, cardinality(v_seen)));

    res := res || jsonb_build_object('id','3.3','ok', v_pag_bad = 0,
      'detail', format('%s espécies com páginas sobrepostas ou ordem instável (esperado 0)', v_pag_bad));

    -- 3.5 conferência
    select count(*) into v_n
    from jsonb_to_recordset(v_vars) t(card_id uuid, n integer)
    where t.n <> (select count(*) from public.card_variant cv where cv.card_id = t.card_id and cv.is_active);
    v_k := jsonb_array_length(v_vars);
    res := res || jsonb_build_object('id','3.5','ok', v_n = 0 and v_k > 0,
      'detail', format('%s de %s cartas com active_variant_count divergente (esperado 0)', v_n, v_k));

    -- 3.4 espécie inexistente
    perform set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select count(*) into v_n from public.get_catalog_cards_for_species(gen_random_uuid(), 24, 0);
    execute 'reset role';
    res := res || jsonb_build_object('id','3.4','ok', v_n = 0, 'detail', format('espécie inexistente: %s linhas (esperado 0)', v_n));

    raise exception 'TR000' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'TR000' then
      res := res || jsonb_build_object('id','X.1','ok', false, 'detail','erro inesperado: '||sqlstate||' '||sqlerrm);
    end if;
  end;

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  res := res || jsonb_build_object('id','9.1','ok', current_user = session_user,
    'detail','papel restaurado e claims limpas (o harness não cria dados)');

  for r in select * from jsonb_array_elements(res) loop
    n := n + 1;
    if coalesce((r->>'ok')::boolean, false) then passes := passes + 1; end if;
    seq := n; check_id := r->>'id';
    status := case when coalesce((r->>'ok')::boolean, false) then 'PASS' else 'FAIL' end;
    detail := r->>'detail';
    return next;
  end loop;
  seq := 99; check_id := 'GATE';
  status := case when passes = n and n = 11 then 'PASS' else 'FAIL' end;
  detail := format('%s/%s PASS (esperado 11)', passes, n);
  return next;
end;
$fn$;

select * from pg_temp.tr_5875_validate();
