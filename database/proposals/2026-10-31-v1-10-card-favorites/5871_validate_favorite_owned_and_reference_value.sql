/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5871 - Harness: get_my_favorite_owned_count() (5339) e
              get_my_favorite_reference_value() (5340)
Versão......: 1.2
Status......: CONFIRMADO EXECUTADO — v1.2 (CONTROLLED EXECUTION-20, 2026-10-31): GATE 20/20 PASS,
              ids esperados todos presentes uma vez, sem X.1, resíduo zero. Histórico:
              (REMAINING KPI DATA CONTRACTS-17;
              v1.1 SQL READINESS-18: fixture de 105 cartas garante candidatas com
              preço; filtro > 0 alinhado à 5340 v1.1; 4.5 sem cotação → NULL;
              v1.2 FIXTURE CORRECTION-20: 105 cartas completadas com outras ativas
              quando faltam cartas sem mapeamento (LIVE tem 82; a v1.1 exigia 85 —
              STOP na EXECUTION-19); exemplares só de variantes ativas (trigger
              trg_guard_card_variant_active, MV001). Só fixture e metadados mudam)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-31

Protocolo (o mesmo de 5868–5870): função em pg_temp, uma chamada; usuários
efêmeros A, B e C; favoritos pela RPC oficial set_card_favorite como o próprio
usuário; exemplares inseridos pelo dono do banco no Inventory criado pelo
trigger de auth.users (padrão da 5869); a sentinela TR000 desfaz tudo; 9.1
confere resíduo zero. Executar SÓ depois de 5339 e 5340 aplicadas.

GATE por identificadores (lição da EXECUTION-15): o GATE exige que cada id da
lista v_expected apareça exatamente uma vez, todos PASS, e nenhum X.1 — não
depende de uma contagem escrita à mão.

Carta inativa: usa uma carta já inativa que tenha variante; se não houver,
desativa DENTRO da transação uma carta ativa com variante (row_count = 1,
senão TR_FIXTURE → X.1). Triggers de card (141): só o de updated_at dispara
para is_active. O favorito da carta inativa entra por INSERT do dono do banco
(set_card_favorite recusa carta inativa).

Checagens
  Owned (5339)
  O0.1 configuração (SECURITY DEFINER, search_path vazio, plpgsql, STABLE,
       integer, 1 versão)        O0.2 ACL (só authenticated)
  O1.1 anon 42501                O2.1 sem identidade 28000
  Value (5340)
  V0.1 configuração (… retorna 3 colunas: favorite_count, priced_count,
       total_brl; 1 versão)      V0.2 ACL (só authenticated)
  V1.1 anon 42501                V2.1 sem identidade 28000
  Funcional — No meu acervo
  3.1 A sem favoritas: owned 0 e value (0, 0, NULL)
  3.2 A favorita X, Y, Z; possui X em 3 exemplares (2 variantes quando a
      carta tiver, 2 idiomas): owned 1
  3.3 B possui Y (no Inventory de B) e não favorita nada: A continua 1; B 0
  3.4 A favorita carta inativa e possui exemplar dela: A continua 1
  3.5 A remove os exemplares de X: owned 0
  3.6 corpo da 5339 não lê collection/binder/storage (posse só pelo Inventory)
  Funcional — Valor de referência
  4.1 C favorita 105 cartas ativas (2 blocos): favorite_count, priced_count e
      total_brl iguais aos obtidos chamando get_cards_pricing_summary
      diretamente nos mesmos blocos; exige 0 < priced < 105
  4.2 C possui 3 exemplares de uma favorita com preço: valor inalterado
  4.3 favorita inativa de C: favorite_count e total inalterados
  4.4 isolamento: A vê favorite_count 3 (X, Y, Z) e priced_count ≤ 3
  4.5 B favorita só uma carta sem cotação válida (escolhida pela própria função
      canônica): (1, 0, NULL) — ausência de preço nunca vira zero
  9.1 resíduo zero (usuários, favoritos, exemplares, cartas ativas) e papel
      restaurado
Erro inesperado: X.1 FAIL.
================================================================
*/

create or replace function pg_temp.tr_5871_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  v_fo      oid := to_regprocedure('public.get_my_favorite_owned_count()');
  v_fv      oid := to_regprocedure('public.get_my_favorite_reference_value()');
  v_expected text[] := array['O0.1','O0.2','O1.1','O2.1','V0.1','V0.2','V1.1','V2.1',
                             '3.1','3.2','3.3','3.4','3.5','3.6','4.1','4.2','4.3','4.4','4.5','9.1'];
  p_user_a  uuid := gen_random_uuid();
  p_user_b  uuid := gen_random_uuid();
  p_user_c  uuid := gen_random_uuid();
  v_sfx     text := substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
  v_inv_a   uuid;
  v_inv_b   uuid;
  v_inv_c   uuid;
  v_lang1   uuid;
  v_lang2   uuid;
  v_x       uuid;
  v_xv1     uuid;
  v_xv2     uuid;
  v_y       uuid;
  v_yv      uuid;
  v_z       uuid;
  v_i       uuid;
  v_iv      uuid;
  v_forced  boolean := false;
  v_rows    integer;
  v_ids     uuid[];
  v_id      uuid;
  v_priced_card uuid;
  v_pv      uuid;
  v_unpriced uuid;
  v_cand    uuid[];
  v_s       text[];
  v_n       integer;
  v_m       integer;
  v_r       record;
  v_r2      record;
  v_exp_t   numeric;
  v_exp_p   integer;
  v_base_us bigint;
  v_base_cf bigint;
  v_base_pc bigint;
  v_base_ca bigint;
  res       jsonb := '[]'::jsonb;
  r         jsonb;
  n         integer := 0;
  passes    integer := 0;
  v_ok_ids  boolean;
begin
  -- 0. Configuração e ACL -------------------------------------------------
  res := res || jsonb_build_object('id','O0.1','ok',
    v_fo is not null
    and (select p.prosecdef and p.proconfig = array['search_path=""'] and l.lanname = 'plpgsql'
                and p.provolatile = 's' and p.prorettype = 'integer'::regtype
         from pg_proc p join pg_language l on l.oid = p.prolang where p.oid = v_fo)
    and (select count(*) from pg_proc q join pg_namespace ns on ns.oid = q.pronamespace
         where ns.nspname = 'public' and q.proname = 'get_my_favorite_owned_count') = 1,
    'detail','5339: SECURITY DEFINER, search_path vazio, plpgsql, STABLE, integer, 1 versão');
  res := res || jsonb_build_object('id','O0.2','ok',
    v_fo is not null
    and has_function_privilege('authenticated', v_fo, 'EXECUTE')
    and not has_function_privilege('anon', v_fo, 'EXECUTE')
    and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = v_fo and a.grantee = 0),
    'detail','5339: EXECUTE só authenticated');
  res := res || jsonb_build_object('id','V0.1','ok',
    v_fv is not null
    and (select p.prosecdef and p.proconfig = array['search_path=""'] and l.lanname = 'plpgsql'
                and p.provolatile = 's' and p.proretset
                and p.proargnames = array['favorite_count','priced_count','total_brl']
         from pg_proc p join pg_language l on l.oid = p.prolang where p.oid = v_fv)
    and (select count(*) from pg_proc q join pg_namespace ns on ns.oid = q.pronamespace
         where ns.nspname = 'public' and q.proname = 'get_my_favorite_reference_value') = 1,
    'detail','5340: SECURITY DEFINER, search_path vazio, plpgsql, STABLE, 3 colunas, 1 versão');
  res := res || jsonb_build_object('id','V0.2','ok',
    v_fv is not null
    and has_function_privilege('authenticated', v_fv, 'EXECUTE')
    and not has_function_privilege('anon', v_fv, 'EXECUTE')
    and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = v_fv and a.grantee = 0),
    'detail','5340: EXECUTE só authenticated');
  res := res || jsonb_build_object('id','3.6','ok',
    v_fo is not null
    and (select p.prosrc !~* '(collection|binder|storage)' from pg_proc p where p.oid = v_fo),
    'detail','corpo da 5339 sem collection/binder/storage');

  select count(*) into v_base_us from auth.users;
  select count(*) into v_base_cf from public.card_favorite;
  select count(*) into v_base_pc from public.physical_card;
  select count(*) into v_base_ca from public.card where is_active;

  begin
    -- 1.1 / 2.1 ----------------------------------------------------------------
    perform set_config('request.jwt.claims', '', true);
    execute 'set local role anon';
    v_s := '{}';
    begin perform public.get_my_favorite_owned_count(); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    begin perform public.get_my_favorite_reference_value(); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','O1.1','ok', v_s[1] = '42501', 'detail','anon 5339: '||coalesce(v_s[1],'?'));
    res := res || jsonb_build_object('id','V1.1','ok', v_s[2] = '42501', 'detail','anon 5340: '||coalesce(v_s[2],'?'));

    execute 'set local role authenticated';
    v_s := '{}';
    begin perform public.get_my_favorite_owned_count(); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    begin perform public.get_my_favorite_reference_value(); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','O2.1','ok', v_s[1] = '28000', 'detail','sem identidade 5339: '||coalesce(v_s[1],'?'));
    res := res || jsonb_build_object('id','V2.1','ok', v_s[2] = '28000', 'detail','sem identidade 5340: '||coalesce(v_s[2],'?'));

    -- Fixture (dono do banco) ----------------------------------------------------
    select l.id into v_lang1 from public.language l order by l.code limit 1;
    select l.id into v_lang2 from public.language l where l.id <> v_lang1 order by l.code limit 1;
    v_lang2 := coalesce(v_lang2, v_lang1);

    -- Exemplares só de variantes ativas: physical_card recusa variante inativa
    -- (trg_guard_card_variant_active, MV001).
    select cv.card_id into v_x
    from public.card_variant cv join public.card k on k.id = cv.card_id and k.is_active
    where cv.is_active
    group by cv.card_id having count(*) >= 2 order by cv.card_id limit 1;
    if v_x is null then
      select cv.card_id into v_x
      from public.card_variant cv join public.card k on k.id = cv.card_id and k.is_active
      where cv.is_active
      order by cv.card_id limit 1;
    end if;
    select cv.id into v_xv1 from public.card_variant cv where cv.card_id = v_x and cv.is_active order by cv.id limit 1;
    select cv.id into v_xv2 from public.card_variant cv where cv.card_id = v_x and cv.is_active order by cv.id desc limit 1;
    select cv.card_id, cv.id into v_y, v_yv
    from public.card_variant cv join public.card k on k.id = cv.card_id and k.is_active
    where cv.card_id <> v_x and cv.is_active order by cv.card_id, cv.id limit 1;
    select k.id into v_z from public.card k
    where k.is_active and k.id not in (v_x, v_y) order by k.id limit 1;
    select k.id, cv.id into v_i, v_iv
    from public.card k join public.card_variant cv on cv.card_id = k.id and cv.is_active
    where not k.is_active order by k.id, cv.id limit 1;
    if v_i is null then
      select k.id, cv.id into v_i, v_iv
      from public.card k join public.card_variant cv on cv.card_id = k.id and cv.is_active
      where k.is_active and k.id not in (v_x, v_y, v_z) order by k.id desc, cv.id limit 1;
      update public.card set is_active = false where id = v_i and is_active;   -- desfeito pelo TR000
      get diagnostics v_rows = row_count;
      if v_rows <> 1 then
        raise exception 'TR_FIXTURE: desativação transacional da carta inativa afetou % linha(s)', v_rows;
      end if;
      v_forced := true;
    end if;
    -- 105 cartas ativas distintas para C, em três camadas, cada uma excluindo as já
    -- escolhidas (<> all): (1) até 20 com mapeamento de preço CONFIRMED; (2) as ativas
    -- sem mapeamento algum que couberem; (3) se ainda faltar, outras ativas. A cobertura
    -- não é presumida pelo mapeamento: 4.1 compara com a função canônica e exige
    -- 0 < priced < 105. Ordem final por id (lotes determinísticos).
    v_ids := array(
      select k.id from public.card k
      join public.pricing_card_mapping pcm on pcm.card_id = k.id and pcm.match_status = 'CONFIRMED'
      where k.is_active group by k.id order by k.id limit 20);
    v_ids := v_ids || array(
      select k.id from public.card k
      where k.is_active and k.id <> all(v_ids)
        and not exists (select 1 from public.pricing_card_mapping pcm where pcm.card_id = k.id)
      order by k.id limit 105 - cardinality(v_ids));
    v_ids := v_ids || array(
      select k.id from public.card k
      where k.is_active and k.id <> all(v_ids)
      order by k.id limit 105 - cardinality(v_ids));
    v_ids := array(select distinct x from unnest(v_ids) x order by x);
    -- Candidatas para 4.5 (sem mapeamento; a função canônica decide como B).
    v_cand := array(
      select k.id from public.card k
      where k.is_active
        and not exists (select 1 from public.pricing_card_mapping pcm where pcm.card_id = k.id)
      order by k.id desc limit 20);
    if v_lang1 is null or v_x is null or v_xv1 is null or v_y is null or v_z is null
       or v_i is null or v_iv is null or cardinality(v_ids) <> 105 then
      raise exception 'TR_FIXTURE: catálogo insuficiente (idioma, cartas com variante, carta inativa ou 105 cartas ativas)';
    end if;

    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    values (p_user_a, 'authenticated', 'authenticated', 'tr5871-a-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'tr5871a_'||v_sfx, 'display_name', 'TR 5871 A'), now(), now()),
           (p_user_b, 'authenticated', 'authenticated', 'tr5871-b-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'tr5871b_'||v_sfx, 'display_name', 'TR 5871 B'), now(), now()),
           (p_user_c, 'authenticated', 'authenticated', 'tr5871-c-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'tr5871c_'||v_sfx, 'display_name', 'TR 5871 C'), now(), now());
    select i.id into v_inv_a from public.inventory i where i.owner_user_id = p_user_a;
    select i.id into v_inv_b from public.inventory i where i.owner_user_id = p_user_b;
    select i.id into v_inv_c from public.inventory i where i.owner_user_id = p_user_c;
    if v_inv_a is null or v_inv_b is null or v_inv_c is null then
      raise exception 'TR_FIXTURE: Inventory não provisionado para os usuários efêmeros';
    end if;

    -- 3.1 A sem favoritas ----------------------------------------------------------
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    v_n := public.get_my_favorite_owned_count();
    select * into v_r from public.get_my_favorite_reference_value();
    execute 'reset role';
    res := res || jsonb_build_object('id','3.1','ok',
      v_n = 0 and v_r.favorite_count = 0 and v_r.priced_count = 0 and v_r.total_brl is null,
      'detail', format('owned %s (0); value (%s, %s, %s) (0, 0, NULL)', v_n, v_r.favorite_count, v_r.priced_count, coalesce(v_r.total_brl::text,'NULL')));

    -- 3.2 A favorita X, Y, Z; possui X em 3 exemplares --------------------------------
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values
      (v_xv1, v_lang1, v_inv_a), (v_xv1, v_lang1, v_inv_a), (v_xv2, v_lang2, v_inv_a);
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.set_card_favorite(v_x, true);
    perform public.set_card_favorite(v_y, true);
    perform public.set_card_favorite(v_z, true);
    v_n := public.get_my_favorite_owned_count();
    execute 'reset role';
    res := res || jsonb_build_object('id','3.2','ok', v_n = 1,
      'detail', format('X com 3 exemplares (%s variante(s), %s idioma(s)), Y e Z sem exemplar: %s (1)',
                       case when v_xv1 = v_xv2 then 1 else 2 end, case when v_lang1 = v_lang2 then 1 else 2 end, v_n));

    -- 3.3 B possui Y e não favorita nada ----------------------------------------------
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_yv, v_lang1, v_inv_b);
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    v_n := public.get_my_favorite_owned_count();
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    v_m := public.get_my_favorite_owned_count();
    execute 'reset role';
    res := res || jsonb_build_object('id','3.3','ok', v_n = 1 and v_m = 0,
      'detail', format('exemplar de Y no Inventory de B: A %s (1), B sem favoritas %s (0)', v_n, v_m));

    -- 3.4 favorita inativa possuída por A -----------------------------------------------
    insert into public.card_favorite (user_id, card_id) values (p_user_a, v_i);
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_iv, v_lang1, v_inv_a);
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    v_n := public.get_my_favorite_owned_count();
    execute 'reset role';
    res := res || jsonb_build_object('id','3.4','ok', v_n = 1,
      'detail', format('carta inativa favoritada e possuída: %s (1; carta %s)', v_n,
                       case when v_forced then 'desativada na transação' else 'já inativa' end));

    -- 4.4 isolamento do valor de A (antes de remover exemplares) ---------------------------
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select * into v_r from public.get_my_favorite_reference_value();
    execute 'reset role';

    -- 3.5 A remove os exemplares de X ---------------------------------------------------
    delete from public.physical_card where inventory_id = v_inv_a and card_variant_id in (v_xv1, v_xv2);
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    v_n := public.get_my_favorite_owned_count();
    execute 'reset role';
    res := res || jsonb_build_object('id','3.5','ok', v_n = 0, 'detail', format('após remover os exemplares de X: %s (0)', v_n));

    -- 4.1 C favorita 105 cartas -----------------------------------------------------------
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_c, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    foreach v_id in array v_ids loop
      perform public.set_card_favorite(v_id, true);
    end loop;
    select coalesce(sum(s.brl_amount), 0), count(*)::integer into v_exp_t, v_exp_p
    from (
      select * from public.get_cards_pricing_summary(v_ids[1:100])
      union all
      select * from public.get_cards_pricing_summary(v_ids[101:105])
    ) s
    where s.has_pricing and s.brl_amount is not null and s.brl_amount > 0;
    select * into v_r2 from public.get_my_favorite_reference_value();
    execute 'reset role';
    res := res || jsonb_build_object('id','4.1','ok',
      v_r2.favorite_count = 105 and v_r2.priced_count = v_exp_p and v_exp_p > 0 and v_exp_p < 105
      and v_r2.total_brl is not distinct from v_exp_t,
      'detail', format('C: (%s, %s, %s); canônica em blocos: (105, %s, %s); exige 0 < priced < 105',
                       v_r2.favorite_count, v_r2.priced_count, coalesce(v_r2.total_brl::text,'NULL'), v_exp_p, v_exp_t));
    res := res || jsonb_build_object('id','4.4','ok',
      v_r.favorite_count = 3 and v_r.priced_count <= 3,
      'detail', format('A (X, Y, Z + inativa): favorite_count %s (3), priced_count %s (≤ 3) — favoritas de C não entram',
                       v_r.favorite_count, v_r.priced_count));

    -- 4.2 exemplares não multiplicam ----------------------------------------------------------
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_c, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select s.card_id into v_priced_card
    from public.get_cards_pricing_summary(v_ids[1:100]) s
    where s.has_pricing and s.brl_amount is not null order by s.card_id limit 1;
    if v_priced_card is null then
      select s.card_id into v_priced_card
      from public.get_cards_pricing_summary(v_ids[101:105]) s
      where s.has_pricing and s.brl_amount is not null order by s.card_id limit 1;
    end if;
    execute 'reset role';
    select cv.id into v_pv from public.card_variant cv where cv.card_id = v_priced_card and cv.is_active order by cv.id limit 1;
    if v_pv is not null then
      insert into public.physical_card (card_variant_id, language_id, inventory_id) values
        (v_pv, v_lang1, v_inv_c), (v_pv, v_lang1, v_inv_c), (v_pv, v_lang1, v_inv_c);
    end if;
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_c, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select * into v_r from public.get_my_favorite_reference_value();
    execute 'reset role';
    res := res || jsonb_build_object('id','4.2','ok',
      v_pv is not null and v_r.favorite_count = v_r2.favorite_count and v_r.priced_count = v_r2.priced_count
      and v_r.total_brl is not distinct from v_r2.total_brl,
      'detail', format('3 exemplares de uma favorita com preço: (%s, %s, %s) = antes (%s, %s, %s)',
                       v_r.favorite_count, v_r.priced_count, coalesce(v_r.total_brl::text,'NULL'),
                       v_r2.favorite_count, v_r2.priced_count, coalesce(v_r2.total_brl::text,'NULL')));

    -- 4.3 favorita inativa de C ----------------------------------------------------------------
    insert into public.card_favorite (user_id, card_id) values (p_user_c, v_i);
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_c, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select * into v_r from public.get_my_favorite_reference_value();
    execute 'reset role';
    res := res || jsonb_build_object('id','4.3','ok',
      v_r.favorite_count = v_r2.favorite_count and v_r.priced_count = v_r2.priced_count
      and v_r.total_brl is not distinct from v_r2.total_brl,
      'detail', format('com favorita inativa: (%s, %s, %s) = (%s, %s, %s)',
                       v_r.favorite_count, v_r.priced_count, coalesce(v_r.total_brl::text,'NULL'),
                       v_r2.favorite_count, v_r2.priced_count, coalesce(v_r2.total_brl::text,'NULL')));

    -- 4.5 B: só uma favorita sem cotação válida ---------------------------------------------
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select s.card_id into v_unpriced
    from public.get_cards_pricing_summary(v_cand) s
    where not (s.has_pricing and s.brl_amount is not null and s.brl_amount > 0)
    order by s.card_id limit 1;
    if v_unpriced is not null then
      perform public.set_card_favorite(v_unpriced, true);
    end if;
    select * into v_r from public.get_my_favorite_reference_value();
    execute 'reset role';
    res := res || jsonb_build_object('id','4.5','ok',
      v_unpriced is not null and v_r.favorite_count = 1 and v_r.priced_count = 0 and v_r.total_brl is null,
      'detail', format('B com uma favorita sem cotação: (%s, %s, %s) (1, 0, NULL)%s',
                       v_r.favorite_count, v_r.priced_count, coalesce(v_r.total_brl::text,'NULL'),
                       case when v_unpriced is null then ' — fixture sem carta sem cotação' else '' end));

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
      and (select count(*) from public.card where is_active) = v_base_ca
      and current_user = session_user,
    'detail','resíduo zero (usuários, favoritos, exemplares, cartas ativas) e papel restaurado');

  for r in select * from jsonb_array_elements(res) loop
    n := n + 1;
    if coalesce((r->>'ok')::boolean, false) then passes := passes + 1; end if;
    seq := n; check_id := r->>'id';
    status := case when coalesce((r->>'ok')::boolean, false) then 'PASS' else 'FAIL' end;
    detail := r->>'detail';
    return next;
  end loop;

  v_ok_ids := (select count(*) = cardinality(v_expected)
                 from (select e.value->>'id' as id, count(*) as c
                         from jsonb_array_elements(res) e group by 1) g
                where g.id = any(v_expected) and g.c = 1)
              and not exists (select 1 from jsonb_array_elements(res) e where e.value->>'id' = 'X.1')
              and not exists (select 1 from jsonb_array_elements(res) e where not (e.value->>'id' = any(v_expected)));
  seq := 99; check_id := 'GATE';
  status := case when v_ok_ids and passes = n then 'PASS' else 'FAIL' end;
  detail := format('%s/%s PASS; ids esperados %s, todos presentes uma vez: %s', passes, n, cardinality(v_expected), v_ok_ids);
  return next;
end;
$fn$;

select * from pg_temp.tr_5871_validate();
