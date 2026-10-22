/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5848 - Harness WHERE-04 (5220): filtro por localização física
              e contagens da galeria do Meu acervo — regressão da 5159,
              distribuição física, segurança, integridade e desempenho
Versão......: 1.1 (2026-10-22: 5.9 — valor esperado calculado na fixture,
              como dono do banco; a v1.0 o lia de card/card_variant sob
              authenticated, que a RLS admin-only do catálogo esvazia → 49/50)
Status......: PROPOSTA — v1.0 executada no LIVE após a 5220 (49/50, 99.1
              PASS); v1.1 autorizada para reexecução funcional.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-21

Protocolo (o mesmo da 5847, que já rodou no LIVE): um único statement;
usuários efêmeros A e B (o Inventory nasce pelo trigger de auth.users);
exemplares sobre variantes ATIVAS já existentes (catálogo só lido); a
sentinela MS848 desfaz tudo; a seção 99 prova resíduo zero. Nenhum dado
real é lido como resultado nem alterado.

  select * from pg_temp.wh_5848_validate(false);   -- funcional (rápido)
  select * from pg_temp.wh_5848_validate(true);    -- + Seção P (20.000 exemplares sintéticos)

Fixture (como dono do banco; revertida no fim):
  A, igual à 5827: V1 pt ×3, V1 en ×1, V2 pt ×1, V3 pt ×2 (V3 = variante
  não padrão). Coleção C com V1pt[1], V1pt[2]; local X com V1pt[1]
  (mesmas RPCs da 5827: 5022, 5034/5068, 5046, 5024).
  Depois da regressão: V4 pt ×5 → 2 no local FA (Fichário A), 1 no local
  CB (Caixa B), 2 sem localização (o exemplo obrigatório da WHERE-04).
  B: V1 pt ×2, ambos no local LB de B.

Seções:
  0.x  estrutura, privilégios, retorno exato, uma única sobrecarga, fixture
  1.x  anon → 42501; sem identidade → 28000
  2.x  REGRESSÃO — mesmos valores da 5827 (4.2–4.15) sem os parâmetros
       novos; colunas novas neutras; erros existentes preservados
  3.x  DISTRIBUIÇÃO — 5 / 2 / 1 / 2 com copies_owned = 5; troca de local
       pela 5024 reflete na hora
  4.x  SEGURANÇA — combinação inválida, local inexistente, local de outro
       usuário, isolamento, usuário sem acervo
  5.x  INTEGRIDADE — combinações com busca, Set, idioma, coleção; paginação
       sem duplicar nem perder itens; ordem; invariantes dos contadores;
       leitura direta de physical_card de outro usuário = 0 (4.9)
  P.x  DESEMPENHO (só com p_perf = true) — p95 de 30 execuções por cenário
  99.1 resíduo zero e papel restaurado
GATE: funcional n = 50 todas PASS; com p_perf, também P.1–P.10 presentes.
      Sem p_perf, P.x não aparece — desempenho fica NÃO MEDIDO (nunca PASS).

Limitações: L1 SET LOCAL ROLE prova o banco, não o JWT do PostgREST (a
camada web tem testes próprios); L2 leituras STABLE, sem concorrência a
provar; L3 a Seção P concorre com a carga real se rodar no LIVE (North
Star §4.2 aceita: transação revertida) — preferir ambiente isolado.
================================================================
*/

create or replace function pg_temp.wh_5848_validate(p_perf boolean default false)
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  f_new oid := to_regprocedure('public.get_my_inventory_items(text, text, text, uuid, boolean, text, integer, integer, uuid, boolean)');
  f_old oid := to_regprocedure('public.get_my_inventory_items(text, text, text, uuid, boolean, text, integer, integer)');
  p_user_a uuid := gen_random_uuid();
  p_user_b uuid := gen_random_uuid();
  v_sfx text := lower(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  v_inv_a uuid; v_inv_b uuid;
  v_game uuid; v_pt uuid; v_en uuid;
  v_set_code text; v_card3 uuid;
  v_v1 uuid; v_v2 uuid; v_v3 uuid; v_v4 uuid;
  v_v2_name text; v_v2_number text; v_v4_name text; v_v4_number text;
  v_ids uuid[]; v_v4_ids uuid[];
  v_x uuid; v_col uuid; v_fa uuid; v_cb uuid; v_lb uuid;
  v_big uuid; v_small uuid;
  n integer; n2 integer; n3 integer; t bigint; t2 bigint;
  v_ok boolean; v_err text; v_first uuid; v_exp uuid;
  v_keys text[];
  v_t0 timestamptz; v_times numeric[]; v_p95 numeric; i integer; k integer;
  b_us bigint; b_sc bigint; b_co bigint; b_ca bigint; b_pc bigint;
  res jsonb := '[]'::jsonb; r jsonb; cnt integer := 0; passes integer := 0;
  v_expected integer := 50;
  v_result_sig text := 'TABLE(card_variant_id uuid, language_code text, language_name text, card_name text, '
    || 'collector_number text, collector_total integer, card_set_code text, card_set_name text, '
    || 'is_default_variant boolean, variant_label text, copies_count integer, last_added_at timestamp with time zone, '
    || 'image_path text, total_count bigint, copies_owned integer, total_copies bigint)';
begin
  -- 0. Estrutura -----------------------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    f_new is not null and f_old is null
    and (select count(*) from pg_proc p join pg_namespace s on s.oid = p.pronamespace
         where s.nspname = 'public' and p.proname = 'get_my_inventory_items') = 1
    and (select p.prosecdef and p.provolatile = 's' and p.proconfig = array['search_path=""']
         from pg_proc p where p.oid = f_new),
    'detail','5220: só a assinatura nova (10 argumentos), sem sobrecarga; SECURITY DEFINER, STABLE, search_path vazio');

  if f_new is null then
    res := res || jsonb_build_object('id','X.0','ok', false, 'detail','5220 não aplicada — aplique antes deste harness');
  else
  res := res || jsonb_build_object('id','0.2','ok',
    has_function_privilege('authenticated', f_new, 'EXECUTE')
    and not has_function_privilege('anon', f_new, 'EXECUTE')
    and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = f_new and a.grantee = 0),
    'detail','EXECUTE só authenticated; anon e PUBLIC sem acesso');
  res := res || jsonb_build_object('id','0.3','ok', pg_get_function_result(f_new) = v_result_sig,
    'detail','retorno = 14 colunas da 5159 na mesma ordem + copies_owned integer + total_copies bigint');

  select count(*) into b_us from auth.users;
  select count(*) into b_sc from public.storage_container;
  select count(*) into b_co from public.collection;
  select count(*) into b_ca from public.collection_allocation;
  select count(*) into b_pc from public.physical_card;

  begin
    -- Fixture de catálogo (como dono do banco) ----------------------------------
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
           where c2.card_set_id = c.card_set_id and c2.is_active and c2.id <> c.id) >= 3
    order by cs.release_date desc nulls last, c.collector_order, nd.variant_order
    limit 1;
    select (array_agg(d.id order by c.collector_order))[1], (array_agg(d.id order by c.collector_order))[2],
           (array_agg(d.id order by c.collector_order))[3]
      into v_v1, v_v2, v_v4
    from public.card c
    join public.card_set cs on cs.id = c.card_set_id and cs.code = v_set_code
    join public.card_variant d on d.card_id = c.id and d.is_active and d.is_default
    where c.is_active and c.id <> v_card3;
    select c.name, c.collector_number into v_v2_name, v_v2_number
    from public.card_variant cv join public.card c on c.id = cv.card_id where cv.id = v_v2;
    select c.name, c.collector_number into v_v4_name, v_v4_number
    from public.card_variant cv join public.card c on c.id = cv.card_id where cv.id = v_v4;
    v_ok := v_game is not null and v_pt is not null and v_en is not null and v_v1 is not null and v_v2 is not null
      and v_v3 is not null and v_v4 is not null and v_v2_number is not null and v_v4_number is not null
      and v_v2_number <> v_v4_number;
    res := res || jsonb_build_object('id','0.4','ok', v_ok, 'detail', format('fixture de catálogo no Set %s (V1, V2, V4 padrão; V3 não padrão)', coalesce(v_set_code,'?')));
    if not v_ok then raise exception 'MS848' using errcode = 'P0001'; end if;
    -- 5.9 (v1.1): primeiro item esperado em SET_NUMBER, calculado aqui (dono do
    -- banco) sobre as variantes da própria fixture, na ordem canônica da 5220
    -- para itens do mesmo Set: collector_order, variant_order, card_variant_id.
    select cv.id into v_exp
    from public.card_variant cv join public.card c on c.id = cv.card_id
    where cv.id in (v_v1, v_v2, v_v3, v_v4)
    order by c.collector_order, cv.variant_order, cv.id
    limit 1;

    -- Usuários efêmeros e exemplares (fixture da 5827) ---------------------------
    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    values (p_user_a, 'authenticated', 'authenticated', 'wh5848-a-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'wh5848a_'||v_sfx, 'display_name', 'WH 5848 A'), now(), now()),
           (p_user_b, 'authenticated', 'authenticated', 'wh5848-b-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'wh5848b_'||v_sfx, 'display_name', 'WH 5848 B'), now(), now());
    select i.id into v_inv_a from public.inventory i where i.owner_user_id = p_user_a;
    select i.id into v_inv_b from public.inventory i where i.owner_user_id = p_user_b;

    insert into public.physical_card (card_variant_id, language_id, inventory_id, created_at)
    select x.v, x.l, v_inv_a, now() - make_interval(mins => x.ago)
    from (values (v_v1, v_pt, 60), (v_v1, v_pt, 50), (v_v1, v_pt, 40),
                 (v_v1, v_en, 30), (v_v2, v_pt, 20), (v_v3, v_pt, 10), (v_v3, v_pt, 5)) x(v, l, ago);
    insert into public.physical_card (card_variant_id, language_id, inventory_id, created_at)
    select v_v1, v_pt, v_inv_b, now() - make_interval(mins => g) from generate_series(1, 2) g;
    select array_agg(pc.id order by pc.created_at) into v_ids
    from public.physical_card pc where pc.inventory_id = v_inv_a and pc.card_variant_id = v_v1 and pc.language_id = v_pt;

    perform set_config('request.jwt.claim.sub', p_user_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select x.id into v_x from public.create_storage_container('Fichário 5848') x;
    select x.id into v_col from public.create_collection(v_game, 'Coleção 5848', null, v_x) x;
    perform public.allocate_physical_cards_to_collection(v_col, v_ids[1:2]);
    perform public.set_physical_cards_storage(v_x, v_ids[1:1]);
    execute 'reset role';

    -- 1. Papéis sem acesso --------------------------------------------------------
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);
    execute 'set local role anon';
    begin
      perform count(*) from public.get_my_inventory_items(p_without_storage => true);
      v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlstate = '42501'; v_err := sqlstate;
    end;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.1','ok', v_ok, 'detail','anon sem EXECUTE: '||v_err);
    execute 'set local role authenticated';
    begin
      perform count(*) from public.get_my_inventory_items(p_storage_container_id => v_x);
      v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlstate = '28000'; v_err := sqlstate;
    end;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.2','ok', v_ok, 'detail','authenticated sem auth.uid(): '||v_err);

    -- 2. REGRESSÃO (como A, sem os parâmetros novos) — valores da 5827 ------------
    perform set_config('request.jwt.claim.sub', p_user_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';

    select count(*), max(x.total_count) into n, t from public.get_my_inventory_items() x;
    res := res || jsonb_build_object('id','2.1','ok', n = 4 and t = 4, 'detail', format('itens = %s, total_count = %s (5827 4.2: 4/4)', n, t));
    select x.copies_count into n from public.get_my_inventory_items() x where x.card_variant_id = v_v1 and x.language_code = 'pt-BR';
    res := res || jsonb_build_object('id','2.2','ok', n = 3, 'detail','V1 pt-BR agrupa 3 exemplares (5827 4.3): '||coalesce(n::text,'NULL'));
    select x.card_variant_id into v_first from public.get_my_inventory_items() x limit 1;
    res := res || jsonb_build_object('id','2.3','ok', v_first = v_v3, 'detail','RECENT: primeiro grupo é V3 (5827 4.4)');
    select bool_and(x.is_default_variant = (x.card_variant_id <> v_v3))
       and bool_and((x.card_variant_id = v_v3) = (x.variant_label is not null and not x.is_default_variant))
      into v_ok from public.get_my_inventory_items() x;
    res := res || jsonb_build_object('id','2.4','ok', coalesce(v_ok,false), 'detail','is_default_variant/variant_label coerentes (5827 4.5)');
    select count(*) into n from public.get_my_inventory_items(p_language_code => 'en') x;
    res := res || jsonb_build_object('id','2.5','ok', n = 1, 'detail','idioma en (5827 4.7): '||n);
    select count(*), sum(x.copies_count) into n, n2 from public.get_my_inventory_items(p_collection_id => v_col) x;
    res := res || jsonb_build_object('id','2.6','ok', n = 1 and n2 = 2, 'detail', format('coleção: %s/%s (5827 4.8: 1/2)', n, n2));
    select sum(x.copies_count) into n from public.get_my_inventory_items(p_without_collection => true) x;
    res := res || jsonb_build_object('id','2.7','ok', n = 5, 'detail','sem coleção (5827 4.9): '||coalesce(n::text,'NULL'));
    select count(*), max(x.total_count) into n, t from public.get_my_inventory_items(p_limit => 2, p_offset => 2) x;
    res := res || jsonb_build_object('id','2.8','ok', n = 2 and t = 4, 'detail', format('página 2: %s linhas, total %s (5827 4.10)', n, t));
    select count(*) into n from public.get_my_inventory_items(p_search => v_v2_name) x where x.card_variant_id = v_v2;
    res := res || jsonb_build_object('id','2.9','ok', n = 1, 'detail','busca por nome encontra V2 (5827 4.11)');
    select count(*) into n from public.get_my_inventory_items(p_search => v_v2_number) x where x.card_variant_id = v_v2;
    res := res || jsonb_build_object('id','2.10','ok', n = 1, 'detail','busca por número encontra V2 (5827 4.12)');
    select count(*), max(x.total_count) into n, t from public.get_my_inventory_items(p_card_set_code => v_set_code, p_sort => 'SET_NUMBER') x;
    res := res || jsonb_build_object('id','2.11','ok', n = 4 and t = 4, 'detail','Set + SET_NUMBER (5827 4.13): '||n);
    begin
      perform public.get_my_inventory_items(p_sort => 'PRICE'); v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlstate = '22023' and sqlerrm = 'INVALID_SORT'; v_err := sqlstate||' '||sqlerrm;
    end;
    res := res || jsonb_build_object('id','2.12','ok', v_ok, 'detail','ordenação inválida (5827 4.14): '||v_err);
    begin
      perform public.get_my_inventory_items(p_limit => 500); v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlstate = '22023' and sqlerrm = 'INVALID_PAGE'; v_err := sqlstate||' '||sqlerrm;
    end;
    res := res || jsonb_build_object('id','2.13','ok', v_ok, 'detail','página > 96 (5827 4.15): '||v_err);
    begin
      perform public.get_my_inventory_items(p_collection_id => v_col, p_without_collection => true); v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlstate = '22023' and sqlerrm = 'INVALID_COLLECTION_FILTER'; v_err := sqlstate||' '||sqlerrm;
    end;
    res := res || jsonb_build_object('id','2.14','ok', v_ok, 'detail','coleção + sem coleção continua INVALID_COLLECTION_FILTER: '||v_err);
    select bool_and(x.copies_owned = x.copies_count), max(x.total_copies) into v_ok, t from public.get_my_inventory_items() x;
    res := res || jsonb_build_object('id','2.15','ok', coalesce(v_ok,false) and t = 7,
      'detail', format('sem filtro: copies_owned = copies_count em todas as linhas; total_copies = %s (esperado 7)', t));
    select x.copies_count, x.copies_owned, x.total_copies into n, n2, t from public.get_my_inventory_items(p_collection_id => v_col) x;
    res := res || jsonb_build_object('id','2.16','ok', n = 2 and n2 = 3 and t = 2,
      'detail', format('coleção: V1 pt %s correspondentes de %s possuídos; total_copies %s (esperado 2/3/2)', n, n2, t));
    select x.copies_count, x.copies_owned, x.total_copies into n, n2, t from public.get_my_inventory_items(p_language_code => 'en') x;
    res := res || jsonb_build_object('id','2.17','ok', n = 1 and n2 = 1 and t = 1,
      'detail','idioma não separa exemplares do item (idioma é parte do item): 1/1/1');
    execute 'reset role';

    -- 3. DISTRIBUIÇÃO FÍSICA (exemplo obrigatório) --------------------------------
    insert into public.physical_card (card_variant_id, language_id, inventory_id, created_at)
    select v_v4, v_pt, v_inv_a, now() - make_interval(secs => g) from generate_series(1, 5) g;
    select array_agg(pc.id order by pc.created_at) into v_v4_ids
    from public.physical_card pc where pc.inventory_id = v_inv_a and pc.card_variant_id = v_v4;
    execute 'set local role authenticated';
    select x.id into v_fa from public.create_storage_container('Fichário A 5848') x;
    select x.id into v_cb from public.create_storage_container('Caixa B 5848') x;
    perform public.set_physical_cards_storage(v_fa, v_v4_ids[1:2]);
    perform public.set_physical_cards_storage(v_cb, v_v4_ids[3:3]);

    select x.copies_count, x.copies_owned into n, n2 from public.get_my_inventory_items() x where x.card_variant_id = v_v4;
    select max(x.total_count), max(x.total_copies) into t, t2 from public.get_my_inventory_items() x;
    res := res || jsonb_build_object('id','3.1','ok', n = 5 and n2 = 5 and t = 5 and t2 = 12,
      'detail', format('todos os locais: V4 %s/%s; itens %s; exemplares %s (esperado 5/5, 5, 12)', n, n2, t, t2));
    select count(*), max(x.copies_count), max(x.copies_owned), max(x.total_count), max(x.total_copies)
      into n, n2, n3, t, t2 from public.get_my_inventory_items(p_storage_container_id => v_fa) x where x.card_variant_id = v_v4;
    select count(*) into k from public.get_my_inventory_items(p_storage_container_id => v_fa) x;
    res := res || jsonb_build_object('id','3.2','ok', n = 1 and k = 1 and n2 = 2 and n3 = 5 and t = 1 and t2 = 2,
      'detail', format('Fichário A: %s linha; %s correspondentes de %s; itens %s; exemplares %s (esperado 1; 2 de 5; 1; 2)', k, n2, n3, t, t2));
    select count(*), max(x.copies_count), max(x.copies_owned), max(x.total_copies)
      into n, n2, n3, t from public.get_my_inventory_items(p_storage_container_id => v_cb) x;
    res := res || jsonb_build_object('id','3.3','ok', n = 1 and n2 = 1 and n3 = 5 and t = 1,
      'detail', format('Caixa B: %s linha; %s de %s; exemplares %s (esperado 1; 1 de 5; 1)', n, n2, n3, t));
    select x.copies_count, x.copies_owned into n, n2 from public.get_my_inventory_items(p_without_storage => true) x where x.card_variant_id = v_v4;
    select x.copies_count, x.copies_owned into n3, k from public.get_my_inventory_items(p_without_storage => true) x
      where x.card_variant_id = v_v1 and x.language_code = 'pt-BR';
    select max(x.total_count), max(x.total_copies) into t, t2 from public.get_my_inventory_items(p_without_storage => true) x;
    res := res || jsonb_build_object('id','3.4','ok', n = 2 and n2 = 5 and n3 = 2 and k = 3 and t = 5 and t2 = 8,
      'detail', format('sem localização: V4 %s de %s; V1 pt %s de %s; itens %s; exemplares %s (esperado 2/5, 2/3, 5, 8)', n, n2, n3, k, t, t2));
    select count(*), max(x.copies_count), max(x.copies_owned) into n, n2, n3
    from public.get_my_inventory_items(p_storage_container_id => v_x) x where x.card_variant_id = v_v1 and x.language_code = 'pt-BR';
    res := res || jsonb_build_object('id','3.5','ok', n = 1 and n2 = 1 and n3 = 3, 'detail', format('local X: V1 pt %s de %s', n2, n3));
    perform public.set_physical_cards_storage(v_cb, v_v4_ids[1:1]);
    select max(x.copies_count) into n from public.get_my_inventory_items(p_storage_container_id => v_fa) x where x.card_variant_id = v_v4;
    select max(x.copies_count) into n2 from public.get_my_inventory_items(p_storage_container_id => v_cb) x where x.card_variant_id = v_v4;
    select max(x.copies_owned) into n3 from public.get_my_inventory_items(p_storage_container_id => v_cb) x where x.card_variant_id = v_v4;
    res := res || jsonb_build_object('id','3.6','ok', n = 1 and n2 = 2 and n3 = 5,
      'detail', format('troca de local pela 5024 reflete na hora: Fichário A %s, Caixa B %s, possuídos %s (esperado 1, 2, 5)', n, n2, n3));
    execute 'reset role';

    -- 4. SEGURANÇA ----------------------------------------------------------------
    insert into public.storage_container (inventory_id, name) values (v_inv_b, 'Local B 5848') returning id into v_lb;
    update public.physical_card set storage_container_id = v_lb where inventory_id = v_inv_b;

    perform set_config('request.jwt.claim.sub', p_user_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    begin
      perform public.get_my_inventory_items(p_storage_container_id => v_fa, p_without_storage => true); v_ok := false; v_err := 'executou';
    exception when others then v_ok := sqlstate = '22023' and sqlerrm = 'INVALID_STORAGE_FILTER'; v_err := sqlstate||' '||sqlerrm;
    end;
    res := res || jsonb_build_object('id','4.1','ok', v_ok, 'detail','local + sem localização juntos: '||v_err);
    select count(*) into n from public.get_my_inventory_items(p_storage_container_id => gen_random_uuid()) x;
    res := res || jsonb_build_object('id','4.2','ok', n = 0, 'detail','local inexistente: '||n||' linhas, sem erro');
    select count(*) into n from public.get_my_inventory_items(p_storage_container_id => v_lb) x;
    res := res || jsonb_build_object('id','4.3','ok', n = 0, 'detail','A filtrando pelo local de B: '||n||' linhas (mesma resposta de local vazio)');
    execute 'reset role';

    perform set_config('request.jwt.claim.sub', p_user_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select count(*), max(x.copies_count), max(x.copies_owned), max(x.total_copies) into n, n2, n3, t
    from public.get_my_inventory_items(p_storage_container_id => v_lb) x;
    res := res || jsonb_build_object('id','4.4','ok', n = 1 and n2 = 2 and n3 = 2 and t = 2, 'detail', format('B no próprio local: %s linha, %s/%s, total %s (controle positivo)', n, n2, n3, t));
    select count(*) into n from public.get_my_inventory_items(p_storage_container_id => v_fa) x;
    res := res || jsonb_build_object('id','4.5','ok', n = 0, 'detail','B filtrando pelo local de A: '||n);
    select count(*) into n from public.get_my_inventory_items(p_without_storage => true) x;
    res := res || jsonb_build_object('id','4.6','ok', n = 0, 'detail','B sem localização (todos os seus estão em LB; nada de A aparece): '||n);
    select count(*), max(x.total_copies) into n, t from public.get_my_inventory_items() x;
    res := res || jsonb_build_object('id','4.7','ok', n = 1 and t = 2, 'detail', format('B sem filtro: %s item, %s exemplares (isolamento)', n, t));
    execute 'select count(*) from public.physical_card where inventory_id = $1' into n using v_inv_a;
    res := res || jsonb_build_object('id','4.9','ok', n = 0, 'detail','B SELECT direto em physical_card de A (RLS): '||n);
    execute 'reset role';

    perform set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', current_setting('request.jwt.claim.sub'), 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select count(*) into n from public.get_my_inventory_items(p_without_storage => true) x;
    res := res || jsonb_build_object('id','4.8','ok', n = 0, 'detail','usuário sem acervo com filtro: '||n||' linhas, sem erro');
    execute 'reset role';

    -- 5. INTEGRIDADE (como A) -----------------------------------------------------
    perform set_config('request.jwt.claim.sub', p_user_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    -- Estado de A agora: V4 → Fichário A 1, Caixa B 2, sem local 2; V1pt[1] em X.
    select count(*) into n from public.get_my_inventory_items(p_storage_container_id => v_cb, p_search => v_v4_number) x where x.card_variant_id = v_v4;
    select count(*) into n2 from public.get_my_inventory_items(p_storage_container_id => v_cb, p_search => v_v2_number) x;
    res := res || jsonb_build_object('id','5.1','ok', n = 1 and n2 = 0, 'detail', format('local + busca: V4 encontrado (%s); V2 (fora do local) não aparece (%s)', n, n2));
    select count(*), max(x.copies_count), max(x.copies_owned), max(x.total_copies) into n, n2, n3, t
    from public.get_my_inventory_items(p_collection_id => v_col, p_without_storage => true) x;
    res := res || jsonb_build_object('id','5.2','ok', n = 1 and n2 = 1 and n3 = 3 and t = 1,
      'detail', format('coleção + sem localização: %s item, %s de %s, total %s (esperado 1, 1 de 3, 1)', n, n2, n3, t));
    select max(x.total_count), max(x.total_copies) into t, t2 from public.get_my_inventory_items(p_without_collection => true, p_without_storage => true) x;
    res := res || jsonb_build_object('id','5.3','ok', t = 5 and t2 = 7, 'detail', format('sem coleção + sem localização: %s itens, %s exemplares (esperado 5, 7)', t, t2));
    select count(*), max(x.total_count) into n, t from public.get_my_inventory_items(p_storage_container_id => v_cb, p_card_set_code => v_set_code, p_sort => 'SET_NUMBER') x;
    res := res || jsonb_build_object('id','5.4','ok', n = 1 and t = 1, 'detail','local + Set + SET_NUMBER (caminho completo): '||n);
    select count(*), max(x.copies_count) into n, n2 from public.get_my_inventory_items(p_without_storage => true, p_language_code => 'en') x;
    res := res || jsonb_build_object('id','5.5','ok', n = 1 and n2 = 1, 'detail','sem localização + idioma en: '||n);
    select array_agg(x.card_variant_id::text || '.' || x.language_code), sum(x.copies_count), min(x.total_count), max(x.total_count), min(x.total_copies), max(x.total_copies)
      into v_keys, n, t, t2, n2, n3
    from (
      select * from public.get_my_inventory_items(p_without_storage => true, p_limit => 2, p_offset => 0)
      union all select * from public.get_my_inventory_items(p_without_storage => true, p_limit => 2, p_offset => 2)
      union all select * from public.get_my_inventory_items(p_without_storage => true, p_limit => 2, p_offset => 4)
    ) x;
    res := res || jsonb_build_object('id','5.6','ok',
      cardinality(v_keys) = 5 and (select count(distinct k2) from unnest(v_keys) k2) = 5 and n = 8 and t = 5 and t2 = 5 and n2 = 8 and n3 = 8,
      'detail', format('paginação sem localização (2+2+1): %s linhas, %s distintas, soma %s; total_count %s–%s; total_copies %s–%s (esperado 5, 5, 8, 5, 8)',
        cardinality(v_keys), (select count(distinct k2) from unnest(v_keys) k2), n, t, t2, n2, n3));
    select count(*) into n from public.get_my_inventory_items(p_without_storage => true, p_limit => 2, p_offset => 6) x;
    res := res || jsonb_build_object('id','5.7','ok', n = 0, 'detail','além do fim com filtro: '||n||' linhas');
    select x.card_variant_id into v_first from public.get_my_inventory_items(p_without_storage => true) x limit 1;
    res := res || jsonb_build_object('id','5.8','ok', v_first = v_v4, 'detail','RECENT sob filtro: primeiro item é o de exemplar mais recente (V4)');
    select x.card_variant_id into v_first from public.get_my_inventory_items(p_without_storage => true, p_sort => 'SET_NUMBER') x limit 1;
    res := res || jsonb_build_object('id','5.9','ok', v_exp is not null and v_first = v_exp, 'detail','SET_NUMBER sob filtro segue a ordem do Set (esperado calculado na fixture)');
    select bool_and(x.copies_count between 1 and x.copies_owned and x.total_copies >= x.total_count)
      into v_ok
    from (
      select * from public.get_my_inventory_items()
      union all select * from public.get_my_inventory_items(p_storage_container_id => v_fa)
      union all select * from public.get_my_inventory_items(p_storage_container_id => v_cb)
      union all select * from public.get_my_inventory_items(p_without_storage => true)
      union all select * from public.get_my_inventory_items(p_collection_id => v_col)
      union all select * from public.get_my_inventory_items(p_without_collection => true, p_without_storage => true)
    ) x;
    res := res || jsonb_build_object('id','5.10','ok', coalesce(v_ok,false), 'detail','invariantes: 1 ≤ copies_count ≤ copies_owned; total_copies ≥ total_count (6 combinações)');
    select count(*) into n
    from (select x.card_variant_id, x.language_code from public.get_my_inventory_items(p_storage_container_id => v_cb) x
          group by 1, 2 having count(*) > 1) d;
    res := res || jsonb_build_object('id','5.11','ok', n = 0, 'detail','carta com exemplares em vários locais aparece uma única vez por listagem');
    execute 'reset role';

    -- P. DESEMPENHO (opcional) ----------------------------------------------------
    if p_perf then
      insert into public.storage_container (inventory_id, name) values (v_inv_a, 'Perf grande 5848') returning id into v_big;
      insert into public.storage_container (inventory_id, name) values (v_inv_a, 'Perf pequeno 5848') returning id into v_small;
      -- 20.000 exemplares de A sobre ~14.000 variantes ativas, 2 idiomas; ~1/3 no local
      -- grande, 50 no local pequeno, o resto sem localização.
      insert into public.physical_card (card_variant_id, language_id, inventory_id, created_at, storage_container_id)
      select p.id, case when g % 2 = 0 then v_pt else v_en end, v_inv_a, now() - make_interval(secs => g),
             case when g % 3 = 0 then v_big when g <= 150 and g % 3 = 1 then v_small else null end
      from generate_series(1, 20000) g
      join (select cv.id, row_number() over (order by cv.id) rn from public.card_variant cv where cv.is_active) p
        on p.rn = 1 + ((g * 7919) % 14000);
      analyze public.physical_card;

      perform set_config('request.jwt.claim.sub', p_user_a::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role', 'authenticated')::text, true);
      execute 'set local role authenticated';
      for i in 1..10 loop
        v_times := '{}';
        for k in 1..30 loop
          v_t0 := clock_timestamp();
          case i
            when 1  then perform count(*) from public.get_my_inventory_items();
            when 2  then perform count(*) from public.get_my_inventory_items(p_sort => 'SET_NUMBER');
            when 3  then perform count(*) from public.get_my_inventory_items(p_search => 'pika');
            when 4  then perform count(*) from public.get_my_inventory_items(p_storage_container_id => v_small);
            when 5  then perform count(*) from public.get_my_inventory_items(p_storage_container_id => v_big);
            when 6  then perform count(*) from public.get_my_inventory_items(p_without_storage => true);
            when 7  then perform count(*) from public.get_my_inventory_items(p_without_storage => true, p_offset => 960);
            when 8  then perform count(*) from public.get_my_inventory_items(p_storage_container_id => v_big, p_sort => 'SET_NUMBER');
            when 9  then perform count(*) from public.get_my_inventory_items(p_storage_container_id => v_big, p_language_code => 'en');
            else         perform count(*) from public.get_my_inventory_items(p_without_storage => true, p_search => 'pika');
          end case;
          v_times := v_times || (extract(epoch from clock_timestamp() - v_t0) * 1000)::numeric;
        end loop;
        select percentile_disc(0.95) within group (order by tt) into v_p95 from unnest(v_times) tt;
        res := res || jsonb_build_object('id','P.'||i,'ok', v_p95 <= 150,
          'detail', format('%s — p95 %s ms, mediana %s ms (30 execuções, 20.000 exemplares)',
            (array['sem filtro RECENT','sem filtro SET_NUMBER','busca','local pequeno (50)','local grande (~6.700)',
                   'sem localização','sem localização pág. 21','local grande + SET_NUMBER','local grande + idioma','sem localização + busca'])[i],
            round(v_p95, 1), round((select percentile_disc(0.5) within group (order by tt) from unnest(v_times) tt), 1)));
      end loop;
      execute 'reset role';
    end if;

    raise exception 'MS848' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MS848' then
      res := res || jsonb_build_object('id','X.1','ok', false, 'detail','erro inesperado: '||sqlstate||' '||sqlerrm);
    end if;
  end;

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  res := res || jsonb_build_object('id','99.1','ok',
    (select count(*) from auth.users) = b_us
      and (select count(*) from public.storage_container) = b_sc
      and (select count(*) from public.collection) = b_co
      and (select count(*) from public.collection_allocation) = b_ca
      and (select count(*) from public.physical_card) = b_pc
      and current_user = session_user,
    'detail','resíduo zero (usuários, locais, coleções, alocações, exemplares) e papel restaurado');
  end if;

  for r in select * from jsonb_array_elements(res) loop
    cnt := cnt + 1;
    if coalesce((r->>'ok')::boolean, false) then passes := passes + 1; end if;
    seq := cnt; check_id := r->>'id';
    status := case when coalesce((r->>'ok')::boolean, false) then 'PASS' else 'FAIL' end;
    detail := r->>'detail';
    return next;
  end loop;
  seq := 999; check_id := 'GATE';
  status := case
    when passes <> cnt then 'FAIL'
    when (select count(*) from jsonb_array_elements(res) e where e->>'id' not like 'P.%') <> v_expected then 'FAIL'
    when p_perf and (select count(*) from jsonb_array_elements(res) e where e->>'id' like 'P.%') <> 10 then 'FAIL'
    when not p_perf then 'PASS_FUNCTIONAL_PERF_NOT_MEASURED'
    else 'PASS' end;
  detail := format('%s/%s PASS (funcional esperado %s%s)', passes, cnt, v_expected, case when p_perf then ' + P.1–P.10' else '' end);
  return next;
end;
$fn$;

select * from pg_temp.wh_5848_validate(false);
