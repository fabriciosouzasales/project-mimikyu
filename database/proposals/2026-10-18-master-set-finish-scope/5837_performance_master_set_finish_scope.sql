/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5837 - Desempenho do Master Set por acabamento (5187–5196)
Versão......: 1.2 (AUDIT-CORRECTION-01: P2.2 — Biblioteca via get_my_collections;
              v1.2 LIVE-EXECUTION: leituras de catálogo (card, card_variant,
              card_set, card_variant_type — RLS só admin) saem do trecho em
              papel authenticated e passam a ser preparadas como dono do banco)
Status......: PROPOSTO — v1.1 executada no LIVE em 2026-10-18 pelo SQL
              Editor: GATE FAIL 7/9 (P1.2 grade 1.695,6 ms — falha real, ver
              5841; X.1 lista vazia no P2 — defeito do harness corrigido na
              v1.2). v1.2 a executar.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-18 (MASTER-SET-DOCUMENTATION-AND-CONTRACT-PROPOSAL-01)

Protocolo: um único statement; usuário efêmero; catálogo REAL só lido
(nenhuma escrita em card/card_variant/card_set); exemplares e coleções
criados para o usuário efêmero e desfeitos pela sentinela MP000;
resíduo zero conferido no fim.

Cenários (tempo de parede por chamada, clock_timestamp, média e máximo):
  P1  Set de maior cobertura do LIVE (hoje ME2.5: 295 cartas, 623
      variantes). Exemplares: 1 por variante ativa + repetidas até
      ~3.000 (C-21: repetidas não inflam, mas pesam na leitura).
      Coleção MASTER_SET com {Padrão, Holo, Reverse} e todos os
      exemplares vinculados.
        summary ×20 · grade 200/página ×20 · opções ×20 · prévia ×20 ·
        fora do objetivo ×20 · edição alternando 2 conjuntos ×10
  P2  Biblioteca: 20 coleções MASTER_SET (os 20 Sets com mais
      variantes), cada uma com 1 exemplar por variante da 1ª carta;
      soma de 20 chamadas de summary (P2.1) e a leitura real da
      Biblioteca, get_my_collections(false, 48, 0) ×10 (P2.2, R1 de 5182),
      que calcula o resumo de cada coleção da página no servidor.

Limites de aceitação (recomendados para homologação; ajustáveis por
Fabrício diante da medição real):
  P1 summary média < 150 ms; grade, prévia, opções, fora do objetivo
  média < 300 ms; edição média < 400 ms; P2.1 total < 1.500 ms;
  P2.2 média < 1.500 ms por página.
Saída: uma linha por cenário com média/máximo e PASS/FAIL do limite, mais
GATE e resíduo.
================================================================
*/

create or replace function pg_temp.ms_5837_perf()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  p_user  uuid := gen_random_uuid();
  v_sfx   text := substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
  v_game  uuid; v_pt uuid; v_inv uuid; v_box uuid; v_set uuid; v_coll uuid;
  v_def   uuid[]; v_alt uuid[];
  v_ids   uuid[]; v_i integer; v_t0 timestamptz; v_ms numeric; v_sum numeric; v_max numeric;
  v_sets  uuid[]; v_colls uuid[] := '{}'; v_x uuid; v_n integer;
  v_code  text; v_plan jsonb := '[]'::jsonb; v_item jsonb;
  b_us bigint; b_co bigint; b_ca bigint; b_pc bigint; b_fn bigint;
  res jsonb := '[]'::jsonb; r jsonb; n integer := 0; passes integer := 0;
begin
  select count(*) into b_us from auth.users;
  select count(*) into b_co from public.collection;
  select count(*) into b_ca from public.collection_allocation;
  select count(*) into b_pc from public.physical_card;
  select count(*) into b_fn from public.collection_master_set_finish;

  begin
    select g.id into v_game from public.game g where g.code = 'POKEMON';
    select l.id into v_pt from public.language l where l.code = 'pt-BR';
    select array_agg(t.id) into v_def from public.card_variant_type t
      where t.game_id = v_game and t.code in ('STANDARD','HOLO','REVERSE_HOLO');
    select array_agg(t.id) into v_alt from public.card_variant_type t
      where t.game_id = v_game and t.code in ('STANDARD','REVERSE_HOLO');

    select c.card_set_id into v_set
    from public.card c join public.card_variant cv on cv.card_id = c.id and cv.is_active
    where c.is_active
    group by c.card_set_id order by count(*) desc, c.card_set_id limit 1;
    select cs.code into v_code from public.card_set cs where cs.id = v_set;  -- v1.2: lido como dono

    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    values (p_user, 'authenticated', 'authenticated', 'ms5837-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'ms5837_'||v_sfx, 'display_name', 'MS 5837'), now(), now());
    select i.id into v_inv from public.inventory i where i.owner_user_id = p_user;

    -- exemplares: 1 por variante ativa do Set + repetidas até ~3.000
    insert into public.physical_card (card_variant_id, language_id, inventory_id)
    select cv.id, v_pt, v_inv
    from public.card c join public.card_variant cv on cv.card_id = c.id and cv.is_active
    cross join generate_series(1, greatest(1, (3000 / greatest(1, (select count(*) from public.card c2
                     join public.card_variant v2 on v2.card_id = c2.id and v2.is_active where c2.card_set_id = v_set))))) g
    where c.card_set_id = v_set and c.is_active;

    perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select c.collection_id, c.storage_container_id into v_coll, v_box
      from public.create_my_card_set_collection(gen_random_uuid(), v_set, 'MS 5837 P1', null) c;
    execute 'reset role';
    select array_agg(pc.id order by pc.id) into v_ids from public.physical_card pc where pc.inventory_id = v_inv;
    perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    v_i := 1;
    while v_i <= cardinality(v_ids) loop
      perform public.allocate_physical_cards_to_collection(v_coll, v_ids[v_i : least(v_i + 499, cardinality(v_ids))]);
      v_i := v_i + 500;
    end loop;
    perform public.set_collection_completion_policy_to_master_set(v_coll, v_def);

    res := res || jsonb_build_object('id','P1.0','ok', true, 'detail',
      format('Set %s: %s exemplares vinculados; posições %s',
        v_code, cardinality(v_ids),
        (select s.total_positions from public.collection_completion_summary(v_coll) s)));

    -- P1 summary
    v_sum := 0; v_max := 0;
    for v_i in 1..20 loop
      v_t0 := clock_timestamp();
      perform * from public.collection_completion_summary(v_coll);
      v_ms := extract(epoch from clock_timestamp() - v_t0) * 1000; v_sum := v_sum + v_ms; v_max := greatest(v_max, v_ms);
    end loop;
    res := res || jsonb_build_object('id','P1.1','ok', v_sum / 20 < 150, 'detail', format('summary: média %s ms, máx %s ms', round(v_sum/20,1), round(v_max,1)));
    -- P1 grade
    v_sum := 0; v_max := 0;
    for v_i in 1..20 loop
      v_t0 := clock_timestamp();
      perform * from public.get_my_master_set_positions(v_coll, 'ALL', 200, ((v_i - 1) % 3) * 200);
      v_ms := extract(epoch from clock_timestamp() - v_t0) * 1000; v_sum := v_sum + v_ms; v_max := greatest(v_max, v_ms);
    end loop;
    res := res || jsonb_build_object('id','P1.2','ok', v_sum / 20 < 300, 'detail', format('grade (200/página): média %s ms, máx %s ms', round(v_sum/20,1), round(v_max,1)));
    -- P1 opções
    v_sum := 0; v_max := 0;
    for v_i in 1..20 loop
      v_t0 := clock_timestamp();
      perform * from public.get_my_master_set_finish_options(v_coll);
      v_ms := extract(epoch from clock_timestamp() - v_t0) * 1000; v_sum := v_sum + v_ms; v_max := greatest(v_max, v_ms);
    end loop;
    res := res || jsonb_build_object('id','P1.3','ok', v_sum / 20 < 300, 'detail', format('opções: média %s ms, máx %s ms', round(v_sum/20,1), round(v_max,1)));
    -- P1 prévia
    v_sum := 0; v_max := 0;
    for v_i in 1..20 loop
      v_t0 := clock_timestamp();
      perform * from public.preview_my_master_set_finishes(v_coll, case when v_i % 2 = 0 then v_def else v_alt end);
      v_ms := extract(epoch from clock_timestamp() - v_t0) * 1000; v_sum := v_sum + v_ms; v_max := greatest(v_max, v_ms);
    end loop;
    res := res || jsonb_build_object('id','P1.4','ok', v_sum / 20 < 300, 'detail', format('prévia: média %s ms, máx %s ms', round(v_sum/20,1), round(v_max,1)));
    -- P1 fora do objetivo
    v_sum := 0; v_max := 0;
    for v_i in 1..20 loop
      v_t0 := clock_timestamp();
      perform * from public.get_my_master_set_out_of_scope_copies(v_coll, 200, 0);
      v_ms := extract(epoch from clock_timestamp() - v_t0) * 1000; v_sum := v_sum + v_ms; v_max := greatest(v_max, v_ms);
    end loop;
    res := res || jsonb_build_object('id','P1.5','ok', v_sum / 20 < 300, 'detail', format('fora do objetivo: média %s ms, máx %s ms', round(v_sum/20,1), round(v_max,1)));
    -- P1 edição
    v_sum := 0; v_max := 0;
    for v_i in 1..10 loop
      v_t0 := clock_timestamp();
      perform * from public.replace_master_set_finishes(v_coll, case when v_i % 2 = 0 then v_def else v_alt end);
      v_ms := extract(epoch from clock_timestamp() - v_t0) * 1000; v_sum := v_sum + v_ms; v_max := greatest(v_max, v_ms);
    end loop;
    res := res || jsonb_build_object('id','P1.6','ok', v_sum / 10 < 400, 'detail', format('edição: média %s ms, máx %s ms', round(v_sum/10,1), round(v_max,1)));
    execute 'reset role';

    -- P2 Biblioteca: 20 coleções MASTER_SET
    select array_agg(x.card_set_id order by x.cnt desc) into v_sets from (
      select c.card_set_id, count(*) cnt
      from public.card c join public.card_variant cv on cv.card_id = c.id and cv.is_active
      where c.is_active group by c.card_set_id order by count(*) desc, c.card_set_id limit 20) x;
    foreach v_x in array v_sets loop
      insert into public.physical_card (card_variant_id, language_id, inventory_id)
      select cv.id, v_pt, v_inv
      from public.card_variant cv
      where cv.is_active and cv.card_id = (select c.id from public.card c where c.card_set_id = v_x and c.is_active
                                           order by c.collector_order, c.id limit 1);
    end loop;
    -- v1.2: plano por Set preparado como dono do banco (card/card_variant/
    -- card_variant_type só são legíveis por admin; em papel authenticated a
    -- v1.1 recebia listas vazias). Exemplares ainda sem vínculo, por Set.
    foreach v_x in array v_sets loop
      v_plan := v_plan || jsonb_build_array(jsonb_build_object(
        'set', v_x,
        'ids', coalesce((select jsonb_agg(pc.id) from public.physical_card pc
                 join public.card_variant cv on cv.id = pc.card_variant_id
                 join public.card c on c.id = cv.card_id and c.card_set_id = v_x
                where pc.inventory_id = v_inv
                  and not exists (select 1 from public.collection_allocation ca where ca.physical_card_id = pc.id)), '[]'::jsonb),
        'fins', coalesce((select jsonb_agg(t.id) from public.card_variant_type t
                 where t.id = any (v_def)
                   and exists (select 1 from public.card c join public.card_variant cv on cv.card_id = c.id and cv.is_active
                               where c.card_set_id = v_x and c.is_active and cv.variant_type_id = t.id)), '[]'::jsonb)));
    end loop;
    perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    v_n := 0;
    for v_item in select * from jsonb_array_elements(v_plan) loop
      v_n := v_n + 1;
      v_x := (v_item->>'set')::uuid;
      select c.collection_id into v_coll from public.create_my_card_set_collection(gen_random_uuid(), v_x, 'MS 5837 L'||v_n, v_box) c;
      if jsonb_array_length(v_item->'ids') > 0 then
        perform public.allocate_physical_cards_to_collection(v_coll,
          array(select jsonb_array_elements_text(v_item->'ids')::uuid));
      end if;
      begin
        perform public.set_collection_completion_policy_to_master_set(v_coll,
          array(select jsonb_array_elements_text(v_item->'fins')::uuid));
      exception when others then null; -- Set sem nenhum dos 3 acabamentos: fica em Set padrão
      end;
      v_colls := v_colls || v_coll;
    end loop;
    v_t0 := clock_timestamp();
    foreach v_x in array v_colls loop
      perform * from public.collection_completion_summary(v_x);
    end loop;
    v_ms := extract(epoch from clock_timestamp() - v_t0) * 1000;
    execute 'reset role';
    res := res || jsonb_build_object('id','P2.1','ok', v_ms < 1500,
      'detail', format('Biblioteca: 20 summaries em %s ms (%s coleções em MASTER_SET)', round(v_ms,1),
        (select count(*) from public.collection c where c.id = any (v_colls) and c.completion_policy = 'MASTER_SET')));
    -- P2.2 leitura real da Biblioteca (R1): uma página com as 20 coleções MASTER_SET
    perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    v_sum := 0; v_max := 0;
    for v_i in 1..10 loop
      v_t0 := clock_timestamp();
      select count(*) into v_n from public.get_my_collections(false, 48, 0);
      v_ms := extract(epoch from clock_timestamp() - v_t0) * 1000;
      v_sum := v_sum + v_ms; v_max := greatest(v_max, v_ms);
    end loop;
    execute 'reset role';
    res := res || jsonb_build_object('id','P2.2','ok', v_sum / 10 < 1500 and v_n >= 20,
      'detail', format('Biblioteca get_my_collections (48/página, %s coleções): média %s ms, máx %s ms',
        v_n, round(v_sum/10,1), round(v_max,1)));

    raise exception 'MP000' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MP000' then
      res := res || jsonb_build_object('id','X.1','ok', false, 'detail','erro inesperado: '||sqlstate||' '||sqlerrm);
    end if;
  end;

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  res := res || jsonb_build_object('id','99.1','ok',
    (select count(*) from auth.users) = b_us
      and (select count(*) from public.collection) = b_co
      and (select count(*) from public.collection_allocation) = b_ca
      and (select count(*) from public.physical_card) = b_pc
      and (select count(*) from public.collection_master_set_finish) = b_fn
      and current_user = session_user,
    'detail','resíduo zero e papel restaurado');

  for r in select * from jsonb_array_elements(res) loop
    n := n + 1;
    if coalesce((r->>'ok')::boolean, false) then passes := passes + 1; end if;
    seq := n; check_id := r->>'id';
    status := case when coalesce((r->>'ok')::boolean, false) then 'PASS' else 'FAIL' end;
    detail := r->>'detail';
    return next;
  end loop;
  seq := 999; check_id := 'GATE';
  status := case when passes = n and n = 10 then 'PASS' else 'FAIL' end;
  detail := format('%s/%s PASS (esperado 10)', passes, n);
  return next;
end;
$fn$;

select * from pg_temp.ms_5837_perf();
