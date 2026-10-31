/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5865 - Harness: get_my_collection(uuid) (5332) —
              equivalência com R1 (5182), segurança e redução de trabalho
Versão......: 1.3 (STORAGE FIX & RETEST-06: fixture passa o local do
              usuário A nas criações após a primeira — regra 55000
              STORAGE_CONTAINER_REQUIRED preservada, como em 5835).
              v1.2: 4.2 em amostra determinística, gate por blocos.
Status......: v1.3 CONFIRMADO EXECUTADO no LIVE em 2026-10-31 — GATE 17/17
              PASS, resíduo zero (RETEST-06). Arquivo mantém v_owner
              como placeholder; a execução usou cópia com o id preenchido.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-31

Executar DEPOIS de aplicar 5332, num único statement (SQL Editor, papel
dono do banco). Mesmo protocolo de 5835/5837: função pg_temp, usuários
efêmeros, sentinela TR000 (tudo o que o harness cria é desfeito pela
exceção final) e resíduo zero (9.1). Não altera dados reais.

ANTES DE EXECUTAR: troque o valor de v_owner (linha marcada "PREENCHER")
pelo id do seu usuário (auth.users.id). A Parte 4 lê as SUAS coleções
reais em modo somente leitura — é ela que cobre Master Set, Pokédex com
vínculos e capas reais. Com o valor de exemplo a Parte 4 falha de
propósito (o GATE não passa sem dado real).

Checagens:
  0.1  5332 existe: assinatura (uuid), SECURITY DEFINER, search_path
       vazio, STABLE, plpgsql, 1 versão.
  0.2  ACL: EXECUTE só authenticated (nem anon, nem PUBLIC).
  0.3  Tipo de retorno idêntico ao de R1 (pg_get_function_result).
  0.4  R1 inalterada: corpo de get_my_collections com md5
       08fc4dd162d269c5015e024db8eefb32 (5182, 2.709 caracteres) e uma
       única versão — a Biblioteca não muda.
  0.5  Filtro antecipado: no corpo, `c.id = p_collection_id` e
       `c.owner_user_id = v_user` aparecem antes do primeiro LATERAL.
  1.1  anon → 42501 (sem grant).
  2.1  authenticated sem identidade → 28000.
  2.2  id nulo → 22023.
  3.x  Usuários efêmeros A e B. A cria: coleção livre; coleção de Set
       com 1 exemplar vinculado (capa e contagem não triviais); Pokédex
       (Geração I); coleção livre arquivada; e tenta uma segunda coleção
       de Set convertida em Master Set (informativo — depende do catálogo).
  3.1  Para TODAS as coleções de A: get_my_collection(id) devolve 1 linha,
       total_count = 1, e as outras 18 colunas são iguais à linha de R1
       (get_my_collections(true,100,0)) do mesmo id.
  3.2  Cobertura sintética: livre, Set padrão, Pokédex e arquivada
       presentes; Set com copies_count = 1 e capa não nula.
  3.3  Isolamento: A lendo coleção de B → 0 linhas; B lendo coleção de
       A → 0 linhas.
  3.4  Não enumera: id inexistente → 0 linhas (mesma resposta de 3.3).
  3.5  Arquivada devolvida com lifecycle_status = ARCHIVED.
  3.6  Master Set sintético (informativo, sempre PASS): diz se foi
       possível ativar; se sim, já entrou na equivalência 3.1.
  4.1  Dados reais de v_owner (somente leitura): para TODAS as coleções
       (todas as páginas de R1, incluindo arquivadas) a linha de 5332 é
       igual à de R1 (18 colunas) e total_count = 1. Detalhe traz a
       contagem por completion_policy e lifecycle.
  4.2  Redução de trabalho (dados reais, AMOSTRA): até 3 coleções,
       escolhidas de forma determinística a partir da fotografia de 4.1 —
       primeiro uma de cada tipo caro, nesta ordem: Pokédex
       (REFERENCE_POSITION), Master Set, Set padrão (em cada tipo, a de
       mais exemplares; empate pelo id); se faltar, completa com as
       próximas na mesma ordem; livres só se não houver outras.
       Para cada coleção da amostra:
         - trabalho: EXPLAIN (ANALYZE, BUFFERS) uma vez da leitura atual
           (as páginas de R1 até a que contém o id, como faz
           getMyCollection hoje) e uma vez de 5332; soma de shared
           hit + read blocks; e nº de resumos calculados (linhas de R1
           lidas × 1);
         - tempo: 3 rodadas intercaladas (atual, nova), mediana de cada.
       GATE: soma dos blocos de 5332 < soma dos blocos da leitura atual
       (com 1 coleção só no total, não há redução possível: PASS com essa
       observação). O tempo é só informativo: medido num banco
       compartilhado, varia com a carga do momento e com o cache, e por
       isso não decide PASS/FAIL. Blocos também incluem acertos de cache,
       mas não dependem da concorrência — são o critério estável.
       Carga máxima: 3 coleções × (1 + 3) leituras atuais e 3 × (1 + 3)
       chamadas de 5332.
  9.1  Resíduo zero e papel restaurado.
GATE: n = 17 e todas PASS.
================================================================
*/

create or replace function pg_temp.tr_5865_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  -- >>> PREENCHER com o id do seu usuário (auth.users.id) <<<
  v_owner   uuid := '00000000-0000-0000-0000-000000000000';

  v_fn      oid := to_regprocedure('public.get_my_collection(uuid)');
  v_r1      oid := to_regprocedure('public.get_my_collections(boolean,integer,integer)');
  p_user_a  uuid := gen_random_uuid();
  p_user_b  uuid := gen_random_uuid();
  v_sfx     text := substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
  v_set     uuid;
  v_variant uuid;
  v_lang    uuid;
  v_inv_a   uuid;
  v_pc      uuid;
  v_box     uuid;
  v_fins    uuid[];
  v_free    uuid;
  v_std     uuid;
  v_dex     uuid;
  v_arch    uuid;
  v_ms      uuid;
  v_ms_note text := 'não tentado';
  v_b1      uuid;
  v_ids     uuid[];
  v_snap    jsonb;
  v_page    uuid[];
  v_id      uuid;
  v_bad     integer;
  v_rows    integer;
  v_cnt     integer;
  v_state   text;
  v_src     text;
  v_t0      timestamptz;
  v_old     numeric;
  v_new     numeric;
  v_sample  uuid[];
  v_plan    json;
  v_blk_old bigint;
  v_blk_new bigint;
  v_rows_old bigint;
  v_t_old   numeric[];
  v_t_new   numeric[];
  v_page_end integer;
  v_total   integer;
  v_detail  text;
  v_off     integer;
  v_base_us bigint;
  v_base_co bigint;
  v_base_ca bigint;
  v_base_pc bigint;
  res       jsonb := '[]'::jsonb;
  r         jsonb;
  n         integer := 0;
  passes    integer := 0;
  i         integer;
begin
  -- 0. Estrutura ------------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    v_fn is not null
    and coalesce((select p.prosecdef and p.proconfig = array['search_path=""'] and p.provolatile = 's'
                         and l.lanname = 'plpgsql'
                  from pg_proc p join pg_language l on l.oid = p.prolang where p.oid = v_fn), false)
    and (select count(*) from pg_proc q join pg_namespace ns on ns.oid = q.pronamespace
          where ns.nspname = 'public' and q.proname = 'get_my_collection') = 1,
    'detail','5332: get_my_collection(uuid), SECURITY DEFINER, search_path vazio, STABLE, plpgsql, 1 versão');

  res := res || jsonb_build_object('id','0.2','ok',
    v_fn is not null
    and has_function_privilege('authenticated', v_fn, 'EXECUTE')
    and not has_function_privilege('anon', v_fn, 'EXECUTE')
    and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = v_fn and a.grantee = 0),
    'detail','ACL: EXECUTE só authenticated (anon e PUBLIC sem acesso)');

  res := res || jsonb_build_object('id','0.3','ok',
    v_fn is not null and v_r1 is not null
    and pg_get_function_result(v_fn) = pg_get_function_result(v_r1),
    'detail','tipo de retorno idêntico ao de get_my_collections (19 colunas, mesma ordem e tipos)');

  res := res || jsonb_build_object('id','0.4','ok',
    v_r1 is not null
    and (select md5(p.prosrc) from pg_proc p where p.oid = v_r1) = '08fc4dd162d269c5015e024db8eefb32'
    and (select count(*) from pg_proc q join pg_namespace ns on ns.oid = q.pronamespace
          where ns.nspname = 'public' and q.proname = 'get_my_collections') = 1,
    'detail','R1 inalterada: corpo = 5182 (md5 08fc4dd1…), uma versão');

  select p.prosrc into v_src from pg_proc p where p.oid = v_fn;
  res := res || jsonb_build_object('id','0.5','ok',
    v_src is not null
    and position('c.id = p_collection_id' in v_src) > 0
    and position('c.owner_user_id = v_user' in v_src) > 0
    and position('c.id = p_collection_id' in v_src) < position('left join lateral' in v_src)
    and position('c.owner_user_id = v_user' in v_src) < position('left join lateral' in v_src),
    'detail','filtro por id e titular no CTE mine, antes dos LATERAL');

  select count(*) into v_base_us from auth.users;
  select count(*) into v_base_co from public.collection;
  select count(*) into v_base_ca from public.collection_allocation;
  select count(*) into v_base_pc from public.physical_card;

  begin
    -- 1.1 anon / 2.1 sem identidade / 2.2 id nulo -----------------------
    perform set_config('request.jwt.claims', '', true);
    execute 'set local role anon';
    begin perform * from public.get_my_collection(gen_random_uuid()); v_state := 'executou';
    exception when others then v_state := sqlstate; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.1','ok', v_state = '42501', 'detail','anon: '||v_state);

    execute 'set local role authenticated';
    begin perform * from public.get_my_collection(gen_random_uuid()); v_state := 'executou';
    exception when others then v_state := sqlstate; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','2.1','ok', v_state = '28000', 'detail','sem identidade: '||v_state);

    -- 3. Fixture sintética (como dono do banco: catálogo só é legível por admin)
    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    values (p_user_a, 'authenticated', 'authenticated', 'tr5865-a-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'tr5865a_'||v_sfx, 'display_name', 'TR 5865 A'), now(), now()),
           (p_user_b, 'authenticated', 'authenticated', 'tr5865-b-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'tr5865b_'||v_sfx, 'display_name', 'TR 5865 B'), now(), now());

    -- Set e variante com imagem de frente ativa (capa não trivial em 3.2).
    select c.card_set_id, cv.id into v_set, v_variant
    from public.card c
    join public.card_variant cv on cv.card_id = c.id and cv.is_active
    join public.card_asset ast on ast.card_id = c.id and ast.is_primary and ast.is_active and ast.storage_path is not null
    join public.card_asset_type cat on cat.id = ast.asset_type_id and cat.code = 'CARD_FRONT'
    where c.is_active
    order by c.card_set_id, c.collector_order, c.id, cv.id
    limit 1;
    select l.id into v_lang from public.language l where l.code = 'pt-BR';
    select iv.id into v_inv_a from public.inventory iv where iv.owner_user_id = p_user_a;
    v_fins := array(select t.id from public.card_variant_type t
                    where exists (select 1 from public.card c join public.card_variant cv on cv.card_id = c.id and cv.is_active
                                  where c.card_set_id = v_set and c.is_active and cv.variant_type_id = t.id));

    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    -- 1ª coleção sem local: cria o "Local padrão" de A (5175).
    select c.collection_id into v_free from public.create_my_free_collection(gen_random_uuid(), 'Livre 5865', null) c;
    -- v1.3: com local existente, as criações exigem local explícito (55000
    -- STORAGE_CONTAINER_REQUIRED). Usa o único local de A, conferindo a
    -- titularidade pelo Inventory de A (mesma leitura de 5835).
    select min(sc.id::text)::uuid, count(*) into v_box, v_cnt
    from public.storage_container sc
    join public.inventory iv on iv.id = sc.inventory_id
    where iv.owner_user_id = p_user_a;
    if v_box is null or v_cnt <> 1 then
      raise exception 'TR_FIXTURE_STORAGE: % locais de A (esperado 1)', v_cnt;
    end if;
    select c.collection_id into v_std  from public.create_my_card_set_collection(gen_random_uuid(), v_set, 'Set 5865', v_box) c;
    select c.collection_id into v_dex  from public.create_my_pokedex_collection(gen_random_uuid(), 'Pokédex 5865', array['GENERATION_I'], v_box) c;
    select c.collection_id into v_arch from public.create_my_free_collection(gen_random_uuid(), 'Arquivada 5865', v_box) c;
    perform public.archive_collection(v_arch);
    select c.collection_id into v_ms   from public.create_my_card_set_collection(gen_random_uuid(), v_set, 'Master 5865', v_box) c;
    begin
      perform public.set_collection_completion_policy_to_master_set(v_ms, v_fins);
      v_ms_note := 'Master Set sintético ativado ('||cardinality(v_fins)||' acabamentos) e incluído em 3.1';
    exception when others then
      v_ms_note := 'Master Set sintético não ativado ('||sqlstate||'); permanece Set padrão — cobertura de Master Set vem da Parte 4';
    end;
    execute 'reset role';

    -- exemplar de A (inserido como dono, como em 5837) e vínculo à coleção de Set
    insert into public.physical_card (card_variant_id, language_id, inventory_id)
    values (v_variant, v_lang, v_inv_a)
    returning id into v_pc;
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.allocate_physical_cards_to_collection(v_std, array[v_pc]);
    execute 'reset role';

    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select c.collection_id into v_b1 from public.create_my_free_collection(gen_random_uuid(), 'B 5865', null) c;
    execute 'reset role';

    -- 2.2 id nulo (com identidade) ---------------------------------------
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    begin perform * from public.get_my_collection(null); v_state := 'executou';
    exception when others then v_state := sqlstate; end;
    res := res || jsonb_build_object('id','2.2','ok', v_state = '22023', 'detail','id nulo: '||v_state);

    -- 3.1 equivalência sintética (todas as coleções de A) ----------------
    -- Fotografia de R1 por id (sem total_count) e comparação com 5332.
    select coalesce(jsonb_object_agg(g.collection_id::text, to_jsonb(g) - 'total_count'), '{}'::jsonb),
           coalesce(array_agg(g.collection_id), '{}')
    into v_snap, v_ids
    from public.get_my_collections(true, 100, 0) g;
    v_bad := 0;
    foreach v_id in array v_ids loop
      select count(*), count(*) filter (where t.total_count = 1 and (to_jsonb(t) - 'total_count') = v_snap -> v_id::text)
      into v_rows, v_cnt
      from public.get_my_collection(v_id) t;
      if v_rows <> 1 or v_cnt <> 1 then v_bad := v_bad + 1; end if;
    end loop;
    res := res || jsonb_build_object('id','3.1','ok', cardinality(v_ids) = 5 and v_bad = 0,
      'detail', format('%s coleções de A comparadas, %s divergentes', cardinality(v_ids), v_bad));

    -- 3.2 cobertura sintética --------------------------------------------
    res := res || jsonb_build_object('id','3.2','ok',
      exists (select 1 from public.get_my_collection(v_free) t where t.completion_policy = 'NONE' and t.card_set_code is null)
      and exists (select 1 from public.get_my_collection(v_std)  t where t.card_set_id = v_set and t.copies_count = 1 and t.cover_image_path is not null)
      and exists (select 1 from public.get_my_collection(v_dex)  t where t.completion_policy = 'REFERENCE_POSITION')
      and exists (select 1 from public.get_my_collection(v_arch) t),
      'detail','livre, Set padrão (1 exemplar, capa), Pokédex e arquivada presentes');

    -- 3.3 isolamento A → B ------------------------------------------------
    select count(*) into v_rows from public.get_my_collection(v_b1);
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select v_rows + count(*) into v_rows from public.get_my_collection(v_std);
    select v_rows + count(*) into v_rows from public.get_my_collection(v_arch);
    execute 'reset role';
    res := res || jsonb_build_object('id','3.3','ok', v_rows = 0,
      'detail','A→B e B→A: '||v_rows||' linhas (esperado 0)');

    -- 3.4 inexistente / 3.5 arquivada ------------------------------------
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select count(*) into v_rows from public.get_my_collection(gen_random_uuid());
    res := res || jsonb_build_object('id','3.4','ok', v_rows = 0,
      'detail','id inexistente: '||v_rows||' linhas (mesma resposta de coleção alheia)');
    res := res || jsonb_build_object('id','3.5','ok',
      (select count(*) from public.get_my_collection(v_arch) t where t.lifecycle_status = 'ARCHIVED') = 1,
      'detail','arquivada devolvida com lifecycle_status = ARCHIVED');
    execute 'reset role';

    res := res || jsonb_build_object('id','3.6','ok', true, 'detail', v_ms_note);

    -- 4. Dados reais de v_owner (somente leitura) ------------------------
    if v_owner = '00000000-0000-0000-0000-000000000000'::uuid
       or not exists (select 1 from auth.users u where u.id = v_owner) then
      res := res || jsonb_build_object('id','4.1','ok', false, 'detail','v_owner não preenchido ou inexistente — Parte 4 não executada');
      res := res || jsonb_build_object('id','4.2','ok', false, 'detail','v_owner não preenchido ou inexistente — Parte 4 não executada');
    else
      perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role','authenticated')::text, true);
      execute 'set local role authenticated';

      -- Todas as páginas de R1 (arquivadas incluídas), na ordem da Biblioteca.
      v_ids := '{}'; v_snap := '{}'::jsonb; v_off := 0;
      loop
        select coalesce(array_agg(g.collection_id), '{}'),
               v_snap || coalesce(jsonb_object_agg(g.collection_id::text, to_jsonb(g) - 'total_count'), '{}'::jsonb)
        into v_page, v_snap
        from public.get_my_collections(true, 100, v_off) g;
        v_ids := v_ids || v_page;
        exit when cardinality(v_page) < 100 or v_off > 10000;
        v_off := v_off + 100;
      end loop;

      v_bad := 0;
      foreach v_id in array v_ids loop
        select count(*), count(*) filter (where t.total_count = 1 and (to_jsonb(t) - 'total_count') = v_snap -> v_id::text)
        into v_rows, v_cnt
        from public.get_my_collection(v_id) t;
        if v_rows <> 1 or v_cnt <> 1 then v_bad := v_bad + 1; end if;
      end loop;

      select string_agg(format('%s/%s: %s', coalesce(g.completion_policy, 'sem política'), g.lifecycle_status, g.qt), '; ')
      into v_detail
      from (select t.completion_policy, t.lifecycle_status, count(*) as qt
            from unnest(v_ids) u(id), lateral public.get_my_collection(u.id) t
            group by 1, 2 order by 1, 2) g;
      res := res || jsonb_build_object('id','4.1','ok', cardinality(v_ids) > 0 and v_bad = 0,
        'detail', format('%s coleções reais comparadas, %s divergentes [%s]', cardinality(v_ids), v_bad, coalesce(v_detail, '—')));

      -- 4.2 amostra determinística (até 3), tipos caros primeiro ------------
      v_total := cardinality(v_ids);
      select coalesce(array_agg(x.id order by x.ord), '{}') into v_sample
      from (
        select k.key::uuid as id,
               row_number() over (order by (k.pri = 4), k.rn_type, k.pri, k.copies desc, k.key) as ord
        from (
          select e.key,
                 case e.value->>'completion_policy'
                   when 'REFERENCE_POSITION' then 1 when 'MASTER_SET' then 2
                   when 'STANDARD_SET' then 3 else 4 end as pri,
                 coalesce((e.value->>'copies_count')::bigint, 0) as copies,
                 row_number() over (partition by e.value->>'completion_policy'
                                    order by coalesce((e.value->>'copies_count')::bigint, 0) desc, e.key) as rn_type
          from jsonb_each(v_snap) e
        ) k
      ) x
      where x.ord <= 3;

      v_blk_old := 0; v_blk_new := 0; v_rows_old := 0; v_detail := '';
      foreach v_id in array v_sample loop
        -- página de R1 em que o id aparece (ordem da Biblioteca, como em 4.1)
        v_page_end := (array_position(v_ids, v_id) - 1) / 100 * 100;

        -- trabalho: uma execução instrumentada de cada caminho
        v_off := 0;
        while v_off <= v_page_end loop
          execute format('explain (analyze, buffers, format json) select * from public.get_my_collections(true, 100, %s)', v_off)
            into v_plan;
          v_blk_old := v_blk_old + coalesce((v_plan->0->'Plan'->>'Shared Hit Blocks')::bigint, 0)
                                 + coalesce((v_plan->0->'Plan'->>'Shared Read Blocks')::bigint, 0);
          v_rows_old := v_rows_old + coalesce((v_plan->0->'Plan'->>'Actual Rows')::bigint, 0);
          v_off := v_off + 100;
        end loop;
        execute format('explain (analyze, buffers, format json) select * from public.get_my_collection(%L::uuid)', v_id)
          into v_plan;
        v_blk_new := v_blk_new + coalesce((v_plan->0->'Plan'->>'Shared Hit Blocks')::bigint, 0)
                               + coalesce((v_plan->0->'Plan'->>'Shared Read Blocks')::bigint, 0);

        -- tempo (informativo): 3 rodadas intercaladas, mediana
        v_t_old := '{}'; v_t_new := '{}';
        for i in 1..3 loop
          v_t0 := clock_timestamp();
          v_off := 0;
          while v_off <= v_page_end loop
            perform * from public.get_my_collections(true, 100, v_off);
            v_off := v_off + 100;
          end loop;
          v_t_old := v_t_old || (extract(epoch from clock_timestamp() - v_t0) * 1000)::numeric;
          v_t0 := clock_timestamp();
          perform * from public.get_my_collection(v_id);
          v_t_new := v_t_new || (extract(epoch from clock_timestamp() - v_t0) * 1000)::numeric;
        end loop;
        v_old := (select t from unnest(v_t_old) t order by t offset 1 limit 1);
        v_new := (select t from unnest(v_t_new) t order by t offset 1 limit 1);
        v_detail := v_detail || format('%s (%s): mediana %s→%s ms; ',
          left(v_id::text, 8), coalesce(v_snap -> v_id::text ->> 'completion_policy', '?'), round(v_old, 1), round(v_new, 1));
      end loop;
      execute 'reset role';
      res := res || jsonb_build_object('id','4.2','ok',
        cardinality(v_sample) > 0 and (v_blk_new < v_blk_old or v_total = 1),
        'detail', format('amostra %s de %s coleções; blocos %s → %s (razão %s); resumos por abertura %s → %s%s; tempo (informativo): %s',
                         cardinality(v_sample), v_total, v_blk_old, v_blk_new,
                         round(v_blk_new::numeric / nullif(v_blk_old, 0), 3),
                         v_rows_old, cardinality(v_sample),
                         case when v_total = 1 then ' — 1 coleção: sem redução possível' else '' end,
                         v_detail));
    end if;

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
      and (select count(*) from public.collection) = v_base_co
      and (select count(*) from public.collection_allocation) = v_base_ca
      and (select count(*) from public.physical_card) = v_base_pc
      and current_user = session_user,
    'detail','resíduo zero (usuários, coleções, vínculos, exemplares) e papel restaurado');

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

select * from pg_temp.tr_5865_validate();
