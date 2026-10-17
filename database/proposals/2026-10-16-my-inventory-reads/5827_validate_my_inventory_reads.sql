/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5827 - Validate My Inventory Reads (5159-5163)
Versão......: 1.1 (2026-10-16, antes da 1ª execução: 4.11/4.12/6.2 deixam
              de ler card/card_variant sob o papel authenticated — RLS
              admin-only tornaria a expectativa dependente do usuário ser
              admin; os valores passam a ser lidos na fixture, como admin)
Status......: EXECUTADO NO LIVE em 2026-10-17 (v1.1, p_perf = false):
              GATE PASS, 52/52 PASS, resíduo zero. Seção P não executada
              no LIVE (fica para o ambiente isolado, R3).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-16 (MY-INVENTORY-IMPLEMENTATION-01, Etapa A)

PROTOCOLO (mesmo de 6849 v2.1 / 5818 §B)
----------------------------------------------------------------
1. Todo o teste roda num ÚNICO statement:
     SELECT * FROM pg_temp.mi_5827_validate(<A>, <B>, <perf>);
2. Fixtures, trocas de papel e claims ficam num bloco BEGIN …
   EXCEPTION que termina SEMPRE com a exceção sentinela MI000 —
   o savepoint reverte tudo; os resultados sobrevivem em variáveis.
3. Erro inesperado no bloco → linha X.1 = FAIL (GATE FAIL), também
   revertido. Depois do bloco, 10.1/10.2 provam a reversão (contagens
   iguais à linha de base; papel e claims restaurados). Sem reversão
   confirmada → MI_5827_ROLLBACK_NOT_CONFIRMED aborta o statement.
4. Único objeto fora do statement: a função pg_temp (local da sessão).

Execução (2 chamadas, ambas por Fabrício):
  CALL 1 — este arquivo inteiro. Preencher os dois UUIDs (usuários de
           teste do Supabase Auth, SEM exemplares) e p_perf:
             false → só segurança/isolamento/contrato (rápido);
             true  → também Seção P (VR: 20.000 exemplares sintéticos
                     para A, ≥ 30 execuções por leitura, p95).
  CALL 2 — POSTCHECK somente leitura (bloco comentado no fim).

Ambiente (North Star §4.1, R3): a Seção P é medição de B4
("Leituras de tela no servidor": transação revertida, VR em fixture
sintética, p95 ≤ 150 ms). Rodar a Seção P no ambiente isolado quando
ele existir; no banco do projeto ela é aceitável pelo próprio §4.2
(transação revertida), mas concorre com a carga real.

Estados: PASS / FAIL / NOT_PROVEN. Resultado nulo de verificação
obrigatória = FAIL. GATE confere a lista exata de ids esperados.

Limitações: L1 papel administrativo + SET LOCAL ROLE (prova o banco,
não o JWT do PostgREST — a camada web é coberta pelos testes da UI);
L2 sem concorrência (leituras STABLE, sem escrita); L3 exige dois
usuários de teste existentes e sem exemplares; L4 sintaxe validada
apenas por EXPLAIN das consultas internas no LIVE (somente leitura).

Pré-requisitos: 5159, 5160, 5161, 5162, 5163 aplicadas.
================================================================
*/

create or replace function pg_temp.mi_5827_validate(p_user_a uuid, p_user_b uuid, p_perf boolean default false)
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  v_role0   text := current_user;
  v_claims0 text := coalesce(current_setting('request.jwt.claims', true), '');
  v_sub0    text := coalesce(current_setting('request.jwt.claim.sub', true), '');
  res       jsonb := '[]'::jsonb;
  v_unexpected text;
  v_b_pc bigint; v_b_ca bigint; v_b_co bigint; v_b_sc bigint;
  v_a_pc bigint; v_a_ca bigint; v_a_co bigint; v_a_sc bigint;
  v_inv_a uuid; v_inv_b uuid;
  v_game uuid;
  v_set_code text;
  v_card3 uuid;
  v_v1 uuid; v_v2 uuid; v_v3 uuid;
  v_v2_name text; v_v2_number text; v_card3_active_variants integer;
  v_pt uuid; v_en uuid;
  v_ids uuid[];
  v_alloc uuid[];
  v_sc uuid; v_col uuid;
  n integer; n2 integer;
  ok boolean;
  st text;
  r record;
  v_first uuid;
  v_t0 timestamptz;
  v_times numeric[];
  v_p95 numeric;
  i integer;
  fn text;
  v_fns text[] := array[
    'public.get_my_inventory_items(text, text, text, uuid, boolean, text, integer, integer)',
    'public.get_my_inventory_summary()',
    'public.get_my_inventory_filter_options()',
    'public.get_my_inventory_item_copies(uuid, text)',
    'public.get_catalog_card_variants_for_picker(uuid)'];
  v_expected text[] := array[
    '0.1','0.2','0.3','0.4',
    '1.1','1.2','1.3','1.4','1.5',
    '2.1','2.2','2.3','2.4','2.5',
    '3.1','3.2','3.3','3.4','3.5',
    '4.1','4.2','4.3','4.4','4.5','4.6','4.7','4.8','4.9','4.10','4.11','4.12','4.13','4.14','4.15','4.16',
    '5.1','5.2','5.3','5.4','5.5','5.6','5.7','5.8',
    '6.1','6.2','6.3','6.4',
    '7.1','7.2','7.3',
    '10.1','10.2'];
  v_perf_ids text[] := array['P.1','P.2','P.3','P.4','P.5','P.6','P.7'];
begin
  -- Linha de base (somente leitura, papel administrativo).
  select count(*) into v_b_pc from public.physical_card;
  select count(*) into v_b_ca from public.collection_allocation;
  select count(*) into v_b_co from public.collection;
  select count(*) into v_b_sc from public.storage_container;

  begin
    -- 0. Pré-condições -----------------------------------------------
    ok := (select bool_and(to_regprocedure(f) is not null) from unnest(v_fns) f);
    res := res || jsonb_build_object('id','0.1','status',case when ok then 'PASS' else 'FAIL' end,'detail','5159-5163 aplicadas');
    if not ok then raise exception using errcode = 'MI000', message = 'MI_5827_ROLLBACK_SENTINEL'; end if;

    select count(*) into n from auth.users u where u.id in (p_user_a, p_user_b);
    ok := p_user_a is not null and p_user_b is not null and p_user_a <> p_user_b and n = 2;
    res := res || jsonb_build_object('id','0.2','status',case when ok then 'PASS' else 'FAIL' end,'detail',format('usuários distintos e existentes: %s de 2', n));
    if not ok then raise exception using errcode = 'MI000', message = 'MI_5827_ROLLBACK_SENTINEL'; end if;

    select i.id into v_inv_a from public.inventory i where i.owner_user_id = p_user_a;
    select i.id into v_inv_b from public.inventory i where i.owner_user_id = p_user_b;
    select count(*) into n from public.physical_card pc where pc.inventory_id in (v_inv_a, v_inv_b);
    ok := v_inv_a is not null and v_inv_b is not null and n = 0;
    res := res || jsonb_build_object('id','0.3','status',case when ok then 'PASS' else 'FAIL' end,'detail',format('Inventories de A e B existem e estão sem exemplares (%s)', n));
    if not ok then raise exception using errcode = 'MI000', message = 'MI_5827_ROLLBACK_SENTINEL'; end if;

    -- Fixture de catálogo: carta com variante padrão E não padrão ativas,
    -- e duas outras cartas do mesmo Set com variante padrão ativa.
    select g.id into v_game from public.game g where g.code = 'POKEMON';
    select l.id into v_pt from public.language l where l.code = 'pt-BR';
    select l.id into v_en from public.language l where l.code = 'en';
    select c.id, cs.code, nd.id into v_card3, v_set_code, v_v3
    from public.card c
    join public.card_set cs on cs.id = c.card_set_id
    join public.card_variant nd on nd.card_id = c.id and nd.is_active and not nd.is_default
    where c.is_active
      and exists (select 1 from public.card_variant d where d.card_id = c.id and d.is_active and d.is_default)
      and (select count(*) from public.card c2
           join public.card_variant d2 on d2.card_id = c2.id and d2.is_active and d2.is_default
           where c2.card_set_id = c.card_set_id and c2.is_active and c2.id <> c.id) >= 2
    order by cs.release_date desc nulls last, c.collector_order, nd.variant_order
    limit 1;
    select (array_agg(d.id order by c.collector_order))[1], (array_agg(d.id order by c.collector_order))[2]
      into v_v1, v_v2
    from public.card c
    join public.card_set cs on cs.id = c.card_set_id and cs.code = v_set_code
    join public.card_variant d on d.card_id = c.id and d.is_active and d.is_default
    where c.is_active and c.id <> v_card3;
    select c.name, c.collector_number into v_v2_name, v_v2_number
    from public.card_variant cv join public.card c on c.id = cv.card_id where cv.id = v_v2;
    select count(*) into v_card3_active_variants
    from public.card_variant cv where cv.card_id = v_card3 and cv.is_active;
    ok := v_game is not null and v_pt is not null and v_en is not null and v_v1 is not null and v_v2 is not null and v_v3 is not null
      and v_v2_name is not null and v_v2_number is not null;
    res := res || jsonb_build_object('id','0.4','status',case when ok then 'PASS' else 'FAIL' end,'detail',format('fixture de catálogo no Set %s', coalesce(v_set_code,'?')));
    if not ok then raise exception using errcode = 'MI000', message = 'MI_5827_ROLLBACK_SENTINEL'; end if;

    -- 1. Estrutura e privilégios (B7 Privilégios) --------------------
    i := 0;
    foreach fn in array v_fns loop
      i := i + 1;
      select p.prosecdef and p.provolatile = 's'
         and exists (select 1 from unnest(coalesce(p.proconfig, '{}'::text[])) cfg
                     where cfg like 'search_path=%' and btrim(substring(cfg from 13), '''" ') = '')
         and has_function_privilege('authenticated', p.oid, 'EXECUTE')
         and not has_function_privilege('anon', p.oid, 'EXECUTE')
         and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)
         and pg_get_userbyid(p.proowner) not in ('anon','authenticated')
        into ok
      from pg_proc p where p.oid = fn::regprocedure;
      res := res || jsonb_build_object('id','1.'||i,'status',case when coalesce(ok,false) then 'PASS' else 'FAIL' end,
        'detail', fn || ': SECURITY DEFINER, STABLE, search_path vazio, EXECUTE só authenticated, sem PUBLIC');
    end loop;

    -- Fixture de exemplares (papel administrativo; revertida no fim).
    -- A: V1 pt ×3, V1 en ×1, V2 pt ×1, V3 pt ×2  → 7 exemplares, 4 grupos, 1 Set, 3 repetidas.
    -- B: V1 pt ×2                                → 2 exemplares, 1 grupo,  1 Set, 1 repetida.
    insert into public.physical_card (card_variant_id, language_id, inventory_id, created_at)
    select x.v, x.l, v_inv_a, now() - make_interval(mins => x.ago)
    from (values (v_v1, v_pt, 60), (v_v1, v_pt, 50), (v_v1, v_pt, 40),
                 (v_v1, v_en, 30), (v_v2, v_pt, 20), (v_v3, v_pt, 10), (v_v3, v_pt, 5)) x(v, l, ago);
    insert into public.physical_card (card_variant_id, language_id, inventory_id, created_at)
    select v_v1, v_pt, v_inv_b, now() - make_interval(mins => g) from generate_series(1, 2) g;

    select array_agg(pc.id order by pc.created_at) into v_ids
    from public.physical_card pc where pc.inventory_id = v_inv_a and pc.card_variant_id = v_v1 and pc.language_id = v_pt;

    -- Coleção e local de A pelas RPCs oficiais (como A).
    perform set_config('request.jwt.claim.sub', p_user_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select x.id into v_sc from public.create_storage_container('Fichário 5827') x;
    select x.id into v_col from public.create_collection(v_game, 'Coleção 5827', null, v_sc) x;
    perform public.allocate_physical_cards_to_collection(v_col, v_ids[1:2]);
    perform public.set_physical_cards_storage(v_sc, v_ids[1:1]);
    execute 'reset role';

    -- 2. anon sem EXECUTE --------------------------------------------
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);
    execute 'set local role anon';
    i := 0;
    foreach fn in array v_fns loop
      i := i + 1;
      begin
        execute case i
          when 1 then 'select count(*) from public.get_my_inventory_items()'
          when 2 then 'select count(*) from public.get_my_inventory_summary()'
          when 3 then 'select count(*) from public.get_my_inventory_filter_options()'
          when 4 then format('select count(*) from public.get_my_inventory_item_copies(%L::uuid, %L)', v_v1, 'pt-BR')
          else format('select count(*) from public.get_catalog_card_variants_for_picker(%L::uuid)', v_card3) end into n;
        ok := false; st := 'executou';
      exception when others then ok := sqlstate = '42501'; st := sqlstate;
      end;
      res := res || jsonb_build_object('id','2.'||i,'status',case when ok then 'PASS' else 'FAIL' end,'detail','anon '||fn||': '||st);
    end loop;
    execute 'reset role';

    -- 3. authenticated sem identidade → 28000 ------------------------
    execute 'set local role authenticated';
    i := 0;
    foreach fn in array v_fns loop
      i := i + 1;
      begin
        execute case i
          when 1 then 'select count(*) from public.get_my_inventory_items()'
          when 2 then 'select count(*) from public.get_my_inventory_summary()'
          when 3 then 'select count(*) from public.get_my_inventory_filter_options()'
          when 4 then format('select count(*) from public.get_my_inventory_item_copies(%L::uuid, %L)', v_v1, 'pt-BR')
          else format('select count(*) from public.get_catalog_card_variants_for_picker(%L::uuid)', v_card3) end into n;
        ok := false; st := 'executou';
      exception when others then ok := sqlstate = '28000'; st := sqlstate;
      end;
      res := res || jsonb_build_object('id','3.'||i,'status',case when ok then 'PASS' else 'FAIL' end,'detail','sem auth.uid() '||fn||': '||st);
    end loop;
    execute 'reset role';

    -- 4. Contrato, como A --------------------------------------------
    perform set_config('request.jwt.claim.sub', p_user_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';

    select * into r from public.get_my_inventory_summary();
    ok := r.total_copies = 7 and r.distinct_items = 4 and r.distinct_sets = 1 and r.duplicate_copies = 3;
    res := res || jsonb_build_object('id','4.1','status',case when coalesce(ok,false) then 'PASS' else 'FAIL' end,
      'detail',format('resumo A = %s/%s/%s/%s (esperado 7/4/1/3)', r.total_copies, r.distinct_items, r.distinct_sets, r.duplicate_copies));

    select count(*), max(x.total_count) into n, n2 from public.get_my_inventory_items() x;
    res := res || jsonb_build_object('id','4.2','status',case when n = 4 and n2 = 4 then 'PASS' else 'FAIL' end,'detail',format('itens A = %s, total_count = %s (esperado 4/4)', n, n2));

    select x.copies_count into n from public.get_my_inventory_items() x where x.card_variant_id = v_v1 and x.language_code = 'pt-BR';
    res := res || jsonb_build_object('id','4.3','status',case when n = 3 then 'PASS' else 'FAIL' end,'detail','V1 pt-BR agrupa 3 exemplares: '||coalesce(n::text,'NULL'));

    select x.card_variant_id into v_first from public.get_my_inventory_items() x limit 1;
    res := res || jsonb_build_object('id','4.4','status',case when v_first = v_v3 then 'PASS' else 'FAIL' end,'detail','RECENT: primeiro grupo é o registrado por último (V3)');

    select bool_and(x.is_default_variant = (x.card_variant_id <> v_v3)) and bool_and((x.card_variant_id = v_v3) = (x.variant_label is not null and not x.is_default_variant))
      into ok from public.get_my_inventory_items() x;
    res := res || jsonb_build_object('id','4.5','status',case when coalesce(ok,false) then 'PASS' else 'FAIL' end,'detail','is_default_variant/variant_label coerentes (V3 não padrão)');

    select count(*) filter (where x.image_path is not null), count(*) into n, n2 from public.get_my_inventory_items() x;
    res := res || jsonb_build_object('id','4.6','status',case when n2 = 4 then (case when n = 4 then 'PASS' else 'NOT_PROVEN' end) else 'FAIL' end,
      'detail',format('image_path preenchido em %s de %s (NOT_PROVEN se o Set da fixture não tiver imagem)', n, n2));

    select count(*) into n from public.get_my_inventory_items(p_language_code => 'en') x;
    res := res || jsonb_build_object('id','4.7','status',case when n = 1 then 'PASS' else 'FAIL' end,'detail','filtro idioma en: '||n);

    select count(*), sum(x.copies_count) into n, n2 from public.get_my_inventory_items(p_collection_id => v_col) x;
    res := res || jsonb_build_object('id','4.8','status',case when n = 1 and n2 = 2 then 'PASS' else 'FAIL' end,'detail',format('filtro coleção: %s grupo, %s exemplares (esperado 1/2)', n, n2));

    select sum(x.copies_count) into n from public.get_my_inventory_items(p_without_collection => true) x;
    res := res || jsonb_build_object('id','4.9','status',case when n = 5 then 'PASS' else 'FAIL' end,'detail','sem coleção: '||coalesce(n::text,'NULL')||' exemplares (esperado 5)');

    select count(*), max(x.total_count) into n, n2 from public.get_my_inventory_items(p_limit => 2, p_offset => 2) x;
    res := res || jsonb_build_object('id','4.10','status',case when n = 2 and n2 = 4 then 'PASS' else 'FAIL' end,'detail',format('página 2 de 2: %s linhas, total %s', n, n2));

    select count(*) into n from public.get_my_inventory_items(p_search => v_v2_name) x
      where x.card_variant_id = v_v2;
    res := res || jsonb_build_object('id','4.11','status',case when n = 1 then 'PASS' else 'FAIL' end,'detail','busca por nome encontra V2');

    select count(*) into n from public.get_my_inventory_items(p_search => v_v2_number) x
      where x.card_variant_id = v_v2;
    res := res || jsonb_build_object('id','4.12','status',case when n = 1 then 'PASS' else 'FAIL' end,'detail','busca por número encontra V2');

    select count(*), max(x.total_count) into n, n2 from public.get_my_inventory_items(p_card_set_code => v_set_code, p_sort => 'SET_NUMBER') x;
    res := res || jsonb_build_object('id','4.13','status',case when n = 4 and n2 = 4 then 'PASS' else 'FAIL' end,'detail','Set + SET_NUMBER: '||n);

    begin
      perform public.get_my_inventory_items(p_sort => 'PRICE');
      ok := false; st := 'executou';
    exception when others then ok := sqlstate = '22023' and sqlerrm = 'INVALID_SORT'; st := sqlstate||' '||sqlerrm;
    end;
    res := res || jsonb_build_object('id','4.14','status',case when ok then 'PASS' else 'FAIL' end,'detail','ordenação inválida: '||st);

    begin
      perform public.get_my_inventory_items(p_limit => 500);
      ok := false; st := 'executou';
    exception when others then ok := sqlstate = '22023' and sqlerrm = 'INVALID_PAGE'; st := sqlstate||' '||sqlerrm;
    end;
    res := res || jsonb_build_object('id','4.15','status',case when ok then 'PASS' else 'FAIL' end,'detail','página > 96: '||st);

    select count(*) = 3
       and min(x.copy_number) = 1 and max(x.copy_number) = 3
       and count(*) filter (where x.collection_name = 'Coleção 5827') = 2
       and count(*) filter (where x.storage_name = 'Fichário 5827') = 1
       and count(*) filter (where x.storage_name is null) = 2
       and max(x.copies_total) = 3
      into ok
    from public.get_my_inventory_item_copies(v_v1, 'pt-BR') x;
    res := res || jsonb_build_object('id','4.16','status',case when coalesce(ok,false) then 'PASS' else 'FAIL' end,
      'detail','detalhe V1 pt-BR: 3 exemplares numerados, 2 na coleção, 1 com local gravado, 2 "sem localização definida"');
    execute 'reset role';

    -- 5. Isolamento, como B (B7 Isolamento) ---------------------------
    perform set_config('request.jwt.claim.sub', p_user_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';

    select * into r from public.get_my_inventory_summary();
    ok := r.total_copies = 2 and r.distinct_items = 1 and r.distinct_sets = 1 and r.duplicate_copies = 1;
    res := res || jsonb_build_object('id','5.1','status',case when coalesce(ok,false) then 'PASS' else 'FAIL' end,
      'detail',format('resumo B = %s/%s/%s/%s (esperado 2/1/1/1)', r.total_copies, r.distinct_items, r.distinct_sets, r.duplicate_copies));

    select count(*), sum(x.copies_count) into n, n2 from public.get_my_inventory_items() x;
    res := res || jsonb_build_object('id','5.2','status',case when n = 1 and n2 = 2 then 'PASS' else 'FAIL' end,'detail',format('itens B: %s grupo, %s exemplares', n, n2));

    select count(*) into n from public.get_my_inventory_item_copies(v_v3, 'pt-BR');
    res := res || jsonb_build_object('id','5.3','status',case when n = 0 then 'PASS' else 'FAIL' end,'detail','B no grupo V3 (só de A): '||n||' linhas');

    select count(*) into n from public.get_my_inventory_item_copies(v_v1, 'pt-BR') x where x.physical_card_id = any(v_ids);
    res := res || jsonb_build_object('id','5.4','status',case when n = 0 then 'PASS' else 'FAIL' end,'detail','B no grupo V1 não vê exemplares de A: '||n);

    select count(*) into n from public.get_my_inventory_items(p_collection_id => v_col) x;
    res := res || jsonb_build_object('id','5.5','status',case when n = 0 then 'PASS' else 'FAIL' end,'detail','B filtrando pela coleção de A: '||n);

    select count(*) into n from public.get_my_inventory_filter_options() x where x.kind = 'COLLECTION';
    res := res || jsonb_build_object('id','5.6','status',case when n = 0 then 'PASS' else 'FAIL' end,'detail','opções de coleção de B: '||n);

    select count(*) into n from public.get_my_inventory_filter_options() x where x.kind = 'LANGUAGE' and x.value = 'en';
    res := res || jsonb_build_object('id','5.7','status',case when n = 0 then 'PASS' else 'FAIL' end,'detail','B não recebe idioma en (só A tem): '||n);

    execute 'select count(*) from public.physical_card where inventory_id = $1' into n using v_inv_a;
    res := res || jsonb_build_object('id','5.8','status',case when n = 0 then 'PASS' else 'FAIL' end,'detail','B SELECT direto em physical_card de A: '||n);
    execute 'reset role';

    -- 6. Opções de filtro e seletor, como A ----------------------------
    perform set_config('request.jwt.claim.sub', p_user_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';

    select count(*) filter (where x.kind = 'SET' and x.value = v_set_code and x.item_count = 7),
           count(*) filter (where x.kind = 'LANGUAGE'),
           count(*) filter (where x.kind = 'COLLECTION' and x.value = v_col::text and x.item_count = 2)
      into n, n2, i
    from public.get_my_inventory_filter_options() x;
    res := res || jsonb_build_object('id','6.1','status',case when n = 1 and n2 = 2 and i = 1 then 'PASS' else 'FAIL' end,
      'detail',format('opções A: Set=%s, idiomas=%s, coleção=%s (esperado 1/2/1)', n, n2, i));

    select count(*), count(*) filter (where x.card_variant_id = v_v3 and not x.is_default_variant)
      into n, n2
    from public.get_catalog_card_variants_for_picker(v_card3) x;
    i := v_card3_active_variants;
    res := res || jsonb_build_object('id','6.2','status',case when n = i and n2 = 1 then 'PASS' else 'FAIL' end,'detail',format('seletor: %s variantes ativas (catálogo: %s)', n, i));

    select count(*) into n from public.get_catalog_card_variants_for_picker(gen_random_uuid());
    res := res || jsonb_build_object('id','6.3','status',case when n = 0 then 'PASS' else 'FAIL' end,'detail','seletor com carta inexistente: '||n);

    begin
      perform public.get_catalog_card_variants_for_picker(null);
      ok := false; st := 'executou';
    exception when others then ok := sqlstate = '22023'; st := sqlstate||' '||sqlerrm;
    end;
    res := res || jsonb_build_object('id','6.4','status',case when ok then 'PASS' else 'FAIL' end,'detail','seletor com nulo: '||st);
    execute 'reset role';

    -- 7. Usuário sem exemplares / sem Inventory --------------------------
    perform set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', current_setting('request.jwt.claim.sub'), 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select * into r from public.get_my_inventory_summary();
    res := res || jsonb_build_object('id','7.1','status',case when r.total_copies = 0 and r.distinct_items = 0 and r.distinct_sets = 0 and r.duplicate_copies = 0 then 'PASS' else 'FAIL' end,'detail','resumo sem Inventory = zeros (1 linha)');
    select count(*) into n from public.get_my_inventory_items();
    res := res || jsonb_build_object('id','7.2','status',case when n = 0 then 'PASS' else 'FAIL' end,'detail','itens sem Inventory: '||n);
    select count(*) into n from public.get_my_inventory_filter_options();
    res := res || jsonb_build_object('id','7.3','status',case when n = 0 then 'PASS' else 'FAIL' end,'detail','opções sem Inventory: '||n);
    execute 'reset role';

    -- P. Performance B4 (opcional) -------------------------------------
    if p_perf then
      -- VR: 20.000 exemplares de A sobre ~14.000 variantes ativas, 2 idiomas.
      insert into public.physical_card (card_variant_id, language_id, inventory_id, created_at)
      select p.id, case when g % 2 = 0 then v_pt else v_en end, v_inv_a, now() - make_interval(secs => g)
      from generate_series(1, 20000) g
      join (select cv.id, row_number() over (order by cv.id) rn from public.card_variant cv where cv.is_active) p
        on p.rn = 1 + ((g * 7919) % 14000);
      analyze public.physical_card;

      perform set_config('request.jwt.claim.sub', p_user_a::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role', 'authenticated')::text, true);
      execute 'set local role authenticated';
      for i in 1..7 loop
        v_times := '{}';
        for n in 1..30 loop
          v_t0 := clock_timestamp();
          case i
            when 1 then perform count(*) from public.get_my_inventory_items();
            when 2 then perform count(*) from public.get_my_inventory_items(p_sort => 'SET_NUMBER');
            when 3 then perform count(*) from public.get_my_inventory_items(p_search => 'pika');
            when 4 then perform count(*) from public.get_my_inventory_items(p_language_code => 'en', p_offset => 960);
            when 5 then perform count(*) from public.get_my_inventory_summary();
            when 6 then perform count(*) from public.get_my_inventory_filter_options();
            else        perform count(*) from public.get_my_inventory_item_copies(v_v1, 'pt-BR');
          end case;
          v_times := v_times || (extract(epoch from clock_timestamp() - v_t0) * 1000)::numeric;
        end loop;
        select percentile_disc(0.95) within group (order by t) into v_p95 from unnest(v_times) t;
        res := res || jsonb_build_object('id','P.'||i,'status',case when v_p95 <= 150 then 'PASS' else 'FAIL' end,
          'detail',format('%s — p95 %s ms (30 execuções; mediana %s ms)',
            (array['itens RECENT','itens SET_NUMBER','itens busca','itens idioma pág.21','resumo','opções de filtro','detalhe'])[i],
            round(v_p95, 1),
            round((select percentile_disc(0.5) within group (order by t) from unnest(v_times) t), 1)));
      end loop;
      execute 'reset role';
    end if;

    raise exception using errcode = 'MI000', message = 'MI_5827_ROLLBACK_SENTINEL';
  exception
    when sqlstate 'MI000' then null;
    when others then
      get stacked diagnostics v_unexpected = message_text;
      res := res || jsonb_build_object('id','X.1','status','FAIL','detail','erro inesperado: '||sqlstate||' '||v_unexpected);
  end;

  -- 10. Reversão comprovada ----------------------------------------------
  select count(*) into v_a_pc from public.physical_card;
  select count(*) into v_a_ca from public.collection_allocation;
  select count(*) into v_a_co from public.collection;
  select count(*) into v_a_sc from public.storage_container;
  ok := v_a_pc = v_b_pc and v_a_ca = v_b_ca and v_a_co = v_b_co and v_a_sc = v_b_sc;
  res := res || jsonb_build_object('id','10.1','status',case when ok then 'PASS' else 'FAIL' end,
    'detail',format('resíduo zero: physical_card %s→%s, allocation %s→%s, collection %s→%s, storage %s→%s', v_b_pc, v_a_pc, v_b_ca, v_a_ca, v_b_co, v_a_co, v_b_sc, v_a_sc));
  if not ok then raise exception 'MI_5827_ROLLBACK_NOT_CONFIRMED'; end if;

  ok := current_user = v_role0
    and coalesce(current_setting('request.jwt.claims', true), '') = v_claims0
    and coalesce(current_setting('request.jwt.claim.sub', true), '') = v_sub0;
  res := res || jsonb_build_object('id','10.2','status',case when ok then 'PASS' else 'FAIL' end,'detail','papel e claims restaurados');
  if not ok then raise exception 'MI_5827_ROLLBACK_NOT_CONFIRMED'; end if;

  return query
  select (row_number() over ())::integer, e->>'id', e->>'status', e->>'detail'
  from jsonb_array_elements(res) e;

  return query
  select 9999, 'GATE',
    case
      when exists (select 1 from jsonb_array_elements(res) e where e->>'status' = 'FAIL') then 'FAIL'
      when (select array_agg(e->>'id' order by e->>'id') from jsonb_array_elements(res) e where e->>'id' not like 'P.%')
           is distinct from (select array_agg(x order by x) from unnest(v_expected) x) then 'FAIL'
      when p_perf and (select count(*) from jsonb_array_elements(res) e where e->>'id' = any(v_perf_ids)) <> 7 then 'FAIL'
      when exists (select 1 from jsonb_array_elements(res) e where e->>'status' = 'NOT_PROVEN') then 'PASS_WITH_NOT_PROVEN'
      else 'PASS' end,
    format('%s verificações; perf=%s', jsonb_array_length(res), p_perf);
end;
$fn$;

-- CALL 1 — preencher os UUIDs dos dois usuários de teste (sem exemplares).
select * from pg_temp.mi_5827_validate(
  '00000000-0000-0000-0000-00000000000A'::uuid,   -- usuário A
  '00000000-0000-0000-0000-00000000000B'::uuid,   -- usuário B
  false                                            -- true = Seção P (B4)
) order by seq;

/*
-- CALL 2 — POSTCHECK somente leitura (nova chamada):
select
  (select count(*) from public.physical_card)        as physical_card,
  (select count(*) from public.collection_allocation) as allocation,
  (select count(*) from public.collection where name = 'Coleção 5827')          as colecao_fixture,
  (select count(*) from public.storage_container where name = 'Fichário 5827') as local_fixture;
-- esperado: contagens iguais às da linha de base do CALL 1; fixtures = 0.
*/
