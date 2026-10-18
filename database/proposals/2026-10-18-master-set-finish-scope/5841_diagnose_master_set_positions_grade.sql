/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5841 - Diagnóstico de desempenho da grade do Master Set
              (get_my_master_set_positions, 5189)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO — LIVE, SQL Editor, 2026-10-18 (Fabrício).
              Resultado: D0 1.241,5 ms; D4 1.876,5 ms; D5 33,1 ms; EQ IGUAL
              (336|9a4113f1…); plano: SubPlan de "available" com 336 loops ×
              6,18 ms (837.312 laços internos); 99.1 PASS. Base da 5198.
              Nota: D4a/D4b isolados (3–4 ms) não refletem o custo real — sem
              a coluna no resultado final o planejador descarta a subconsulta;
              o plano (PLN) é a evidência.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-18 (MASTER-SET LIVE-EXECUTION, após 5837 v1.1 P1.2 FAIL)

Por quê: no 5837 v1.1 (LIVE, SQL Editor) a grade levou em média 1.695,6 ms
por página (limite 300 ms) com o maior Set do LIVE (2.492 exemplares, 336
posições), enquanto resumo, opções, prévia, fora do objetivo e edição — que
montam as mesmas posições — ficaram entre 15 e 38 ms. Este script mede cada
parte da grade separadamente antes de qualquer correção.

COMO EXECUTAR: colar o arquivo INTEIRO no SQL Editor e clicar Run uma vez
(duas instruções na mesma requisição, como o 5840/5837). Escrita SINTÉTICA
revertida: mesmo fixture do 5837 P1 (usuário efêmero, exemplares do Set de
maior cobertura, coleção MASTER_SET {Padrão, Holo, Reverse}); a sentinela
MD000 desfaz tudo e a linha 99.1 confere resíduo zero. Catálogo real só lido.

O QUE MEDE (5 repetições cada, média e máximo em ms):
  D0  chamada real get_my_master_set_positions(coll,'ALL',200,0) como dono
      autenticado — reproduz o P1.2.
  D1  só as posições: master_set_positions(set, acabamentos).
  D2  só a agregação "na coleção" (in_collection).
  D3  só a agregação "disponível no acervo" (available).
  D4  pos_rows como está no 5189 (3 subconsultas correlacionadas por posição),
      sem imagem e sem paginação.
  D4a D4 só com as 2 subconsultas de in_collection.
  D4b D4 só com a subconsulta de available.
  D5  pos_rows CANDIDATO (agregação única por par e por carta + junção),
      forma proposta para a 5198.
  EQ  equivalência D4 × D5: contagem e md5 das linhas (carta, acabamento,
      exemplares na coleção, idioma, exemplares disponíveis) — precisa ser
      IGUAL para a reescrita ser aceitável.
  PLN plano real (EXPLAIN ANALYZE) da forma atual (D4), linhas do plano.
As consultas D1–D5 rodam como dono do banco com os mesmos parâmetros que a
função recebe (Set, acabamentos, coleção, acervo), reproduzindo o corpo de
5189; não chamam a função por dentro.

Hipótese a confirmar: a CTE "available" é referenciada uma única vez, então o
PostgreSQL a incorpora na subconsulta correlacionada e reexecuta a varredura
de exemplares do acervo para cada uma das 336 posições.
================================================================
*/

create or replace function pg_temp.ms_5841_diag()
returns table (seq integer, item text, value text)
language plpgsql
volatile
as $fn$
declare
  p_user  uuid := gen_random_uuid();
  v_sfx   text := substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
  v_game  uuid; v_pt uuid; v_inv uuid; v_set uuid; v_coll uuid; v_code text;
  v_def   uuid[];
  v_ids   uuid[]; v_i integer; v_k integer; v_t0 timestamptz; v_ms numeric; v_sum numeric; v_max numeric;
  v_line  text; v_ids_lbl text[]; v_names text[]; v_qs text[];
  q_pos text; q_ic text; q_av text; q_cur text; q_cur_in text; q_cur_av text; q_new text;
  q_with text;
  v_eq_cur text; v_eq_new text;
  b_us bigint; b_co bigint; b_ca bigint; b_pc bigint; b_fn bigint;
  res jsonb := '[]'::jsonb; r jsonb; n integer := 0;
begin
  select count(*) into b_us from auth.users;
  select count(*) into b_co from public.collection;
  select count(*) into b_ca from public.collection_allocation;
  select count(*) into b_pc from public.physical_card;
  select count(*) into b_fn from public.collection_master_set_finish;

  begin
    -- Fixture (igual ao 5837 P1) ------------------------------------------------
    select g.id into v_game from public.game g where g.code = 'POKEMON';
    select l.id into v_pt from public.language l where l.code = 'pt-BR';
    select array_agg(t.id) into v_def from public.card_variant_type t
      where t.game_id = v_game and t.code in ('STANDARD','HOLO','REVERSE_HOLO');
    select c.card_set_id into v_set
    from public.card c join public.card_variant cv on cv.card_id = c.id and cv.is_active
    where c.is_active
    group by c.card_set_id order by count(*) desc, c.card_set_id limit 1;
    select cs.code into v_code from public.card_set cs where cs.id = v_set;

    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    values (p_user, 'authenticated', 'authenticated', 'ms5841-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'ms5841_'||v_sfx, 'display_name', 'MS 5841'), now(), now());
    select i.id into v_inv from public.inventory i where i.owner_user_id = p_user;

    insert into public.physical_card (card_variant_id, language_id, inventory_id)
    select cv.id, v_pt, v_inv
    from public.card c join public.card_variant cv on cv.card_id = c.id and cv.is_active
    cross join generate_series(1, greatest(1, (3000 / greatest(1, (select count(*) from public.card c2
                     join public.card_variant v2 on v2.card_id = c2.id and v2.is_active where c2.card_set_id = v_set))))) g
    where c.card_set_id = v_set and c.is_active;
    select array_agg(pc.id order by pc.id) into v_ids from public.physical_card pc where pc.inventory_id = v_inv;

    perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select c.collection_id into v_coll
      from public.create_my_card_set_collection(gen_random_uuid(), v_set, 'MS 5841', null) c;
    v_i := 1;
    while v_i <= cardinality(v_ids) loop
      perform public.allocate_physical_cards_to_collection(v_coll, v_ids[v_i : least(v_i + 499, cardinality(v_ids))]);
      v_i := v_i + 500;
    end loop;
    perform public.set_collection_completion_policy_to_master_set(v_coll, v_def);

    res := res || jsonb_build_object('k','F', 'v', format('Set %s; %s exemplares vinculados; posições %s',
      v_code, cardinality(v_ids), (select s.total_positions from public.collection_completion_summary(v_coll) s)));

    -- D0 chamada real (como dono autenticado) ----------------------------------
    v_sum := 0; v_max := 0;
    for v_k in 1..5 loop
      v_t0 := clock_timestamp();
      perform * from public.get_my_master_set_positions(v_coll, 'ALL', 200, 0);
      v_ms := extract(epoch from clock_timestamp() - v_t0) * 1000; v_sum := v_sum + v_ms; v_max := greatest(v_max, v_ms);
    end loop;
    res := res || jsonb_build_object('k','D0', 'v', format('função real (200/página): média %s ms, máx %s ms', round(v_sum/5,1), round(v_max,1)));
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);

    -- Consultas reproduzindo o corpo de 5189 (como dono do banco) ---------------
    q_pos := format('select p.card_id, p.variant_type_id, p.is_secret from public.master_set_positions(%L::uuid, %L::uuid[]) p',
                    v_set, v_def);
    q_ic := format($q$select cv.card_id, cv.variant_type_id, count(*)::integer as copies,
                          min(pc.language_id::text)::uuid as lang
                   from public.collection_allocation ca
                   join public.physical_card pc on pc.id = ca.physical_card_id
                   join public.card_variant cv  on cv.id = pc.card_variant_id
                   where ca.collection_id = %L::uuid
                   group by cv.card_id, cv.variant_type_id$q$, v_coll);
    q_av := format($q$select cv.card_id, cv.variant_type_id, count(*)::integer as copies
                   from public.physical_card pc
                   join public.card_variant cv on cv.id = pc.card_variant_id
                   join public.card c          on c.id = cv.card_id and c.card_set_id = %L::uuid
                   where pc.inventory_id = %L::uuid
                     and not exists (select 1 from public.collection_allocation ca where ca.physical_card_id = pc.id)
                   group by cv.card_id, cv.variant_type_id$q$, v_set, v_inv);
    q_with := 'with positions as (' || q_pos || '), in_collection as (' || q_ic || '), available as (' || q_av || ') ';

    -- forma atual (5189): 3 subconsultas correlacionadas
    q_cur := q_with || $q$, pos_rows as (
        select p.card_id, p.variant_type_id,
          (select sum(ic.copies) from in_collection ic
            where ic.card_id = p.card_id
              and (p.variant_type_id is null or ic.variant_type_id = p.variant_type_id))::integer as in_copies,
          (select min(ic.lang::text)::uuid from in_collection ic
            where ic.card_id = p.card_id
              and (p.variant_type_id is null or ic.variant_type_id = p.variant_type_id)) as lang,
          (select sum(av.copies) from available av
            where av.card_id = p.card_id
              and (p.variant_type_id is null or av.variant_type_id = p.variant_type_id))::integer as av_copies
        from positions p
        join public.card c on c.id = p.card_id)
      select count(*)::text || '|' || coalesce(md5(string_agg(concat_ws(':', card_id, variant_type_id, coalesce(in_copies, 0), lang, coalesce(av_copies, 0)),
                                         ',' order by card_id, variant_type_id nulls first)), '-')
      from pos_rows$q$;
    q_cur_in := q_with || $q$, pos_rows as (
        select p.card_id,
          (select sum(ic.copies) from in_collection ic
            where ic.card_id = p.card_id
              and (p.variant_type_id is null or ic.variant_type_id = p.variant_type_id))::integer as in_copies,
          (select min(ic.lang::text)::uuid from in_collection ic
            where ic.card_id = p.card_id
              and (p.variant_type_id is null or ic.variant_type_id = p.variant_type_id)) as lang
        from positions p
        join public.card c on c.id = p.card_id)
      select count(*)::text from pos_rows$q$;
    q_cur_av := q_with || $q$, pos_rows as (
        select p.card_id,
          (select sum(av.copies) from available av
            where av.card_id = p.card_id
              and (p.variant_type_id is null or av.variant_type_id = p.variant_type_id))::integer as av_copies
        from positions p
        join public.card c on c.id = p.card_id)
      select count(*)::text from pos_rows$q$;
    -- forma candidata (5198): agrega uma vez por par e por carta, depois junta
    q_new := q_with || $q$,
      ic_card as (select ic.card_id, sum(ic.copies)::integer as copies, min(ic.lang::text) as lang
                  from in_collection ic group by ic.card_id),
      av_card as (select av.card_id, sum(av.copies)::integer as copies
                  from available av group by av.card_id),
      pos_rows as (
        select p.card_id, p.variant_type_id,
          case when p.variant_type_id is null then icc.copies else icp.copies end as in_copies,
          (case when p.variant_type_id is null then icc.lang else icp.lang::text end)::uuid as lang,
          case when p.variant_type_id is null then avc.copies else avp.copies end as av_copies
        from positions p
        join public.card c          on c.id = p.card_id
        left join in_collection icp on icp.card_id = p.card_id and icp.variant_type_id = p.variant_type_id
        left join ic_card icc       on icc.card_id = p.card_id
        left join available avp     on avp.card_id = p.card_id and avp.variant_type_id = p.variant_type_id
        left join av_card avc       on avc.card_id = p.card_id)
      select count(*)::text || '|' || coalesce(md5(string_agg(concat_ws(':', card_id, variant_type_id, coalesce(in_copies, 0), lang, coalesce(av_copies, 0)),
                                         ',' order by card_id, variant_type_id nulls first)), '-')
      from pos_rows$q$;

    -- medições D1–D5 -------------------------------------------------------------
    v_ids_lbl := array['D1','D2','D3','D4','D4a','D4b','D5'];
    v_names := array['só posições', 'só agregação na coleção', 'só agregação disponível no acervo',
                     'pos_rows atual (5189, 3 subconsultas)', 'pos_rows atual só com in_collection',
                     'pos_rows atual só com available', 'pos_rows candidato (5198)'];
    v_qs := array['select count(*)::text from (' || q_pos || ') x',
                  'select count(*)::text from (' || q_ic || ') x',
                  'select count(*)::text from (' || q_av || ') x',
                  q_cur, q_cur_in, q_cur_av, q_new];
    for v_i in 1..cardinality(v_qs) loop
      v_sum := 0; v_max := 0;
      for v_k in 1..5 loop
        v_t0 := clock_timestamp();
        execute v_qs[v_i] into v_line;
        v_ms := extract(epoch from clock_timestamp() - v_t0) * 1000; v_sum := v_sum + v_ms; v_max := greatest(v_max, v_ms);
      end loop;
      res := res || jsonb_build_object('k', v_ids_lbl[v_i],
        'v', format('%s: média %s ms, máx %s ms (resultado %s)', v_names[v_i], round(v_sum/5,1), round(v_max,1), v_line));
    end loop;

    -- equivalência D4 × D5 --------------------------------------------------------
    execute q_cur into v_eq_cur;
    execute q_new into v_eq_new;
    res := res || jsonb_build_object('k','EQ', 'v', format('%s — atual %s · candidato %s',
      case when v_eq_cur = v_eq_new then 'IGUAL' else 'DIFERENTE' end, v_eq_cur, v_eq_new));

    -- plano real da forma atual ------------------------------------------------------
    v_k := 0;
    for v_line in execute 'explain (analyze, buffers, format text) ' || q_cur loop
      v_k := v_k + 1;
      exit when v_k > 80;
      res := res || jsonb_build_object('k', 'PLN', 'v', v_line);
    end loop;

    raise exception 'MD000' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MD000' then
      res := res || jsonb_build_object('k','X.1', 'v','erro inesperado: '||sqlstate||' '||sqlerrm);
    end if;
  end;

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  res := res || jsonb_build_object('k','99.1', 'v',
    case when (select count(*) from auth.users) = b_us
           and (select count(*) from public.collection) = b_co
           and (select count(*) from public.collection_allocation) = b_ca
           and (select count(*) from public.physical_card) = b_pc
           and (select count(*) from public.collection_master_set_finish) = b_fn
           and current_user = session_user
         then 'PASS — resíduo zero e papel restaurado' else 'FAIL — resíduo encontrado' end);

  for r in select * from jsonb_array_elements(res) loop
    n := n + 1;
    seq := n; item := r->>'k'; value := r->>'v';
    return next;
  end loop;
end;
$fn$;

select * from pg_temp.ms_5841_diag();
