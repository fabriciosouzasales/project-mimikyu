/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5869 - Harness: get_my_favorite_collection_count() (5337)
Versão......: 1.1 (AUDIT-10: cartas X/Y escolhidas no Game da coleção — a 5046
              exige exemplar do mesmo Game; resíduo inclui locais e memberships)
Status......: CONFIRMADO EXECUTADO no LIVE (EXECUTION-11, 2026-10-31): GATE 9/9 PASS,
              sem X.1, resíduo zero
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-31

Protocolo (o mesmo da 5868): função em pg_temp, uma chamada; usuários
efêmeros A e B; coleções, exemplares e alocações criados pelas RPCs oficiais
como o próprio usuário; a sentinela TR000 desfaz tudo; 9.1 confere resíduo
zero. Não lê nem altera dados reais. Executar SÓ depois de 5337 aplicada.

Cenário de A (carta X favoritável, carta Y nunca favoritada):
  C1  ativa  → x1, x2 (X) + y1 (Y)        (duas favoritas na mesma coleção)
  CN  ativa  → y2 (Y)                      (coleção sem favoritas)
  CE  ativa  → vazia
  CA  ARQUIVADA → x5 (X)
  C2, C3 ativas → x3, x4 (X), alocados no passo 3.3 (mesma carta em 3 coleções)
  x6 (X) no acervo, sem coleção
  CB de B (ativa, com bx de X), compartilhada com A como membro ACTIVE

Checagens (GATE = todas PASS, 9):
  0.1  configuração: SECURITY DEFINER, search_path vazio, plpgsql, STABLE,
       retorna integer, uma versão
  0.2  ACL: EXECUTE só authenticated (anon e PUBLIC sem acesso)
  1.1  anon: 42501
  2.1  authenticated sem identidade: 28000
  3.1  A sem favoritos: 0 (coleções com X não contam sem favorito)
  3.2  A favorita X: 1 — C1 uma vez (2 exemplares favoritos); CN, CE,
       arquivada CA, compartilhada CB e x6 sem coleção não contam
  3.3  X também em C2 e C3: 3 (a mesma carta favorita conta em cada coleção)
  3.4  isolamento: B não herda o favorito de A (0); B favorita X: 1 (só CB);
       A continua 3; A desfavorita X: 0 (B continua 1)
  9.1  resíduo zero (usuários, favoritos, exemplares, coleções, locais,
       memberships) e papel restaurado
Erro inesperado: X.1 FAIL.
================================================================
*/

create or replace function pg_temp.tr_5869_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  v_f      oid := to_regprocedure('public.get_my_favorite_collection_count()');
  p_user_a uuid := gen_random_uuid();
  p_user_b uuid := gen_random_uuid();
  v_sfx    text := substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
  v_game   uuid;
  v_lang   uuid;
  v_card_x uuid;
  v_card_y uuid;
  v_vx     uuid;
  v_vy     uuid;
  v_inv_a  uuid;
  v_inv_b  uuid;
  v_loc_a  uuid;
  v_loc_b  uuid;
  c1 uuid; c2 uuid; c3 uuid; cn uuid; ce uuid; ca uuid; cb uuid;
  x1 uuid; x2 uuid; x3 uuid; x4 uuid; x5 uuid; x6 uuid; y1 uuid; y2 uuid; bx uuid;
  v_s      text[];
  v_n      integer;
  v_m      integer;
  v_k      integer;
  v_base_us bigint;
  v_base_cf bigint;
  v_base_pc bigint;
  v_base_co bigint;
  v_base_sc bigint;
  v_base_cm bigint;
  res      jsonb := '[]'::jsonb;
  r        jsonb;
  n        integer := 0;
  passes   integer := 0;
begin
  -- 0. Configuração e ACL -------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    v_f is not null
    and (select p.prosecdef and p.proconfig = array['search_path=""'] and l.lanname = 'plpgsql'
                and p.provolatile = 's' and p.prorettype = 'integer'::regtype
         from pg_proc p join pg_language l on l.oid = p.prolang where p.oid = v_f)
    and (select count(*) from pg_proc q join pg_namespace ns on ns.oid = q.pronamespace
         where ns.nspname = 'public' and q.proname = 'get_my_favorite_collection_count') = 1,
    'detail','SECURITY DEFINER, search_path vazio, plpgsql, STABLE, integer, 1 versão');

  res := res || jsonb_build_object('id','0.2','ok',
    v_f is not null
    and has_function_privilege('authenticated', v_f, 'EXECUTE')
    and not has_function_privilege('anon', v_f, 'EXECUTE')
    and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = v_f and a.grantee = 0),
    'detail','EXECUTE só authenticated (anon e PUBLIC sem acesso)');

  select count(*) into v_base_us from auth.users;
  select count(*) into v_base_cf from public.card_favorite;
  select count(*) into v_base_pc from public.physical_card;
  select count(*) into v_base_co from public.collection;
  select count(*) into v_base_sc from public.storage_container;
  select count(*) into v_base_cm from public.collection_membership;

  begin
    -- 1.1 anon / 2.1 sem identidade -----------------------------------------
    perform set_config('request.jwt.claims', '', true);
    execute 'set local role anon';
    v_s := '{}';
    begin perform public.get_my_favorite_collection_count(); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.1','ok', v_s = array['42501'], 'detail','anon: '||array_to_string(v_s, ', '));

    execute 'set local role authenticated';
    v_s := '{}';
    begin perform public.get_my_favorite_collection_count(); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','2.1','ok', v_s = array['28000'], 'detail','sem identidade: '||array_to_string(v_s, ', '));

    -- Fixture de catálogo (dono do banco; só leitura) ---------------------------
    select g.id into v_game from public.game g where g.code = 'POKEMON';
    select l.id into v_lang from public.language l where l.code = 'pt-BR';
    -- Só cartas do Game da coleção: allocate_physical_cards_to_collection (5046) recusa
    -- exemplar de outro Game (card → card_set → expansion.game_id).
    select c.id, cv.id into v_card_x, v_vx
    from public.card c
    join public.card_variant cv on cv.card_id = c.id and cv.is_active and cv.is_default
    join public.card_set cs on cs.id = c.card_set_id
    join public.expansion ex on ex.id = cs.expansion_id and ex.game_id = v_game
    where c.is_active order by c.id limit 1;
    select c.id, cv.id into v_card_y, v_vy
    from public.card c
    join public.card_variant cv on cv.card_id = c.id and cv.is_active and cv.is_default
    join public.card_set cs on cs.id = c.card_set_id
    join public.expansion ex on ex.id = cs.expansion_id and ex.game_id = v_game
    where c.is_active and c.id <> v_card_x order by c.id limit 1;
    if v_game is null or v_lang is null or v_vx is null or v_vy is null then
      raise exception 'TR_FIXTURE: catálogo sem Game POKEMON, pt-BR ou duas cartas ativas com variante padrão';
    end if;

    -- Usuários e exemplares (dono do banco, como na 5866/5868) ------------------
    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    values (p_user_a, 'authenticated', 'authenticated', 'tr5869-a-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'tr5869a_'||v_sfx, 'display_name', 'TR 5869 A'), now(), now()),
           (p_user_b, 'authenticated', 'authenticated', 'tr5869-b-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'tr5869b_'||v_sfx, 'display_name', 'TR 5869 B'), now(), now());
    select i.id into v_inv_a from public.inventory i where i.owner_user_id = p_user_a;
    select i.id into v_inv_b from public.inventory i where i.owner_user_id = p_user_b;
    if v_inv_a is null or v_inv_b is null then
      raise exception 'TR_FIXTURE: inventário ausente';
    end if;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_vx, v_lang, v_inv_a) returning id into x1;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_vx, v_lang, v_inv_a) returning id into x2;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_vx, v_lang, v_inv_a) returning id into x3;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_vx, v_lang, v_inv_a) returning id into x4;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_vx, v_lang, v_inv_a) returning id into x5;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_vx, v_lang, v_inv_a) returning id into x6;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_vy, v_lang, v_inv_a) returning id into y1;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_vy, v_lang, v_inv_a) returning id into y2;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_vx, v_lang, v_inv_b) returning id into bx;

    -- B: coleção com X, compartilhada com A (membro ACTIVE) -----------------------
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select x.id into v_loc_b from public.create_storage_container('Local B 5869') x;
    select x.id into cb from public.create_collection(v_game, 'CB 5869', null, v_loc_b) x;
    perform public.allocate_physical_cards_to_collection(cb, array[bx]);
    execute 'reset role';
    insert into public.collection_membership (collection_id, user_id, role, status, invited_by, responded_at)
    values (cb, p_user_a, 'VIEWER', 'ACTIVE', p_user_b, now());

    -- A: coleções e alocações ------------------------------------------------------
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select x.id into v_loc_a from public.create_storage_container('Local A 5869') x;
    select x.id into c1 from public.create_collection(v_game, 'C1 5869', null, v_loc_a) x;
    select x.id into c2 from public.create_collection(v_game, 'C2 5869', null, v_loc_a) x;
    select x.id into c3 from public.create_collection(v_game, 'C3 5869', null, v_loc_a) x;
    select x.id into cn from public.create_collection(v_game, 'CN 5869', null, v_loc_a) x;
    select x.id into ce from public.create_collection(v_game, 'CE 5869', null, v_loc_a) x;
    select x.id into ca from public.create_collection(v_game, 'CA 5869', null, v_loc_a) x;
    perform public.allocate_physical_cards_to_collection(c1, array[x1, x2, y1]);
    perform public.allocate_physical_cards_to_collection(cn, array[y2]);
    perform public.allocate_physical_cards_to_collection(ca, array[x5]);
    perform public.archive_collection(ca);

    -- 3.1 sem favoritos ---------------------------------------------------------------
    v_n := public.get_my_favorite_collection_count();
    res := res || jsonb_build_object('id','3.1','ok', v_n = 0,
      'detail', format('A sem favoritos: %s (esperado 0)', v_n));

    -- 3.2 favorita X ----------------------------------------------------------------
    perform public.set_card_favorite(v_card_x, true);
    v_n := public.get_my_favorite_collection_count();
    res := res || jsonb_build_object('id','3.2','ok', v_n = 1,
      'detail', format('A favorita X: %s (esperado 1 — só C1; CN, CE, arquivada, compartilhada e x6 fora)', v_n));

    -- 3.3 mesma carta em três coleções ------------------------------------------------
    perform public.allocate_physical_cards_to_collection(c2, array[x3]);
    perform public.allocate_physical_cards_to_collection(c3, array[x4]);
    v_n := public.get_my_favorite_collection_count();
    res := res || jsonb_build_object('id','3.3','ok', v_n = 3,
      'detail', format('X em C1, C2 e C3: %s (esperado 3)', v_n));
    execute 'reset role';

    -- 3.4 isolamento ------------------------------------------------------------------
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    v_n := public.get_my_favorite_collection_count();              -- B antes de favoritar
    perform public.set_card_favorite(v_card_x, true);
    v_m := public.get_my_favorite_collection_count();              -- B depois
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    v_k := public.get_my_favorite_collection_count();              -- A com o favorito de B
    perform public.set_card_favorite(v_card_x, false);
    v_s := array[public.get_my_favorite_collection_count()::text]; -- A sem favorito
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    v_s := v_s || public.get_my_favorite_collection_count()::text; -- B depois de A desfavoritar
    execute 'reset role';
    res := res || jsonb_build_object('id','3.4','ok', v_n = 0 and v_m = 1 and v_k = 3 and v_s = array['0','1'],
      'detail', format('B antes %s (0), B depois %s (1), A %s (3), A desfavorita %s (0), B %s (1)', v_n, v_m, v_k, v_s[1], v_s[2]));

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
      and (select count(*) from public.card_favorite) = v_base_cf
      and (select count(*) from public.physical_card) = v_base_pc
      and (select count(*) from public.collection) = v_base_co
      and (select count(*) from public.storage_container) = v_base_sc
      and (select count(*) from public.collection_membership) = v_base_cm
      and current_user = session_user,
    'detail','resíduo zero (usuários, favoritos, exemplares, coleções, locais, memberships) e papel restaurado');

  for r in select * from jsonb_array_elements(res) loop
    n := n + 1;
    if coalesce((r->>'ok')::boolean, false) then passes := passes + 1; end if;
    seq := n; check_id := r->>'id';
    status := case when coalesce((r->>'ok')::boolean, false) then 'PASS' else 'FAIL' end;
    detail := r->>'detail';
    return next;
  end loop;
  seq := 99; check_id := 'GATE';
  status := case when passes = n and n = 9 then 'PASS' else 'FAIL' end;
  detail := format('%s/%s PASS (esperado 9)', passes, n);
  return next;
end;
$fn$;

select * from pg_temp.tr_5869_validate();
