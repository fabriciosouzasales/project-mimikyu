/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5870 - Harness: get_my_favorite_card_set_count() (5338)
Versão......: 1.2
Status......: PROPOSTA — NÃO EXECUTADA (KPI-4 CARD SET SEMANTIC CORRECTION-13;
              v1.1 SQL READINESS-14: fixture da carta inativa conferida por row_count)
Execução....: EXECUTION-15 (2026-10-31): 10/10 checagens PASS, sem X.1, resíduo zero,
              mas GATE = FAIL por DEFEITO DO HARNESS — o arquivo tem 10 checagens
              (0.1, 0.2, 1.1, 2.1, 3.1–3.5, 9.1) e o GATE exige n = 9. STOP; arquivo
              mantido como executado (não corrigido para forçar PASS).
              ACCEPTED BY INDEPENDENT REVIEW — 10/10 CHECKS PASS; GATE COUNT
              CONFIGURATION DEFECT (GATE COUNT ACCEPTANCE & API CLOSEOUT-16).
Histórico...: v1.0 CORRECTION-13 · v1.1 READINESS-14 (fixture da carta inativa por
              row_count; executada na EXECUTION-15, GATE FAIL por contagem) ·
              v1.2 CLOSEOUT-16: só a expectativa do GATE 9 → 10 (consultas,
              fixtures, checagens e exceções idênticas à v1.1). v1.2 NÃO EXECUTADA.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-31

Protocolo (o mesmo da 5868/5869): função em pg_temp, uma chamada; usuários
efêmeros A e B, SEM exemplares, inventário em uso ou coleções (prova que a
contagem independe de posse e de Collection); favoritos gravados pela RPC
oficial set_card_favorite como o próprio usuário; a sentinela TR000 desfaz
tudo; 9.1 confere resíduo zero. Executar SÓ depois de 5338 aplicada.

Carta inativa (3.4): usa uma carta já inativa do catálogo, de um Card Set
diferente dos de A; se o catálogo não tiver nenhuma, desativa uma carta ativa
de outro Card Set DENTRO da transação (desfeito pelo TR000; nunca confirmado).
Triggers de card no repositório (141): trg_card_set_updated_at (BEFORE UPDATE,
só ajusta updated_at) e trg_card_validate_game_consistency (só UPDATE OF
card_set_id/rarity_id/category_id — não dispara para is_active). O UPDATE deve
afetar exatamente 1 linha; caso contrário TR_FIXTURE (X.1), nunca um 3.4 falso.
Efeito sobre outras sessões: só o lock da linha durante a chamada (milissegundos);
a mudança nunca é visível fora da transação. O favorito da carta inativa entra
por INSERT direto do dono do banco — a RPC recusa favoritar carta inativa.

Checagens (GATE = todas PASS, 10):
  0.1  configuração: SECURITY DEFINER, search_path vazio, plpgsql, STABLE,
       retorna integer, uma versão
  0.2  ACL: EXECUTE só authenticated (anon e PUBLIC sem acesso)
  1.1  anon: 42501
  2.1  authenticated sem identidade: 28000
  3.1  A sem favoritas: 0
  3.2  A favorita 7 cartas do mesmo Card Set (sem possuí-las, sem coleção): 1
  3.3  A favorita uma carta de outro Card Set: 2
  3.4  favorito de carta inativa de um terceiro Card Set: continua 2
  3.5  isolamento: B favorita carta de um terceiro Card Set → B 1, A continua
       2; A desfavorita a carta do 2º Set → A 1, B continua 1
  9.1  resíduo zero (usuários, favoritos, cartas ativas) e papel restaurado
Erro inesperado: X.1 FAIL.
================================================================
*/

create or replace function pg_temp.tr_5870_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  v_f       oid := to_regprocedure('public.get_my_favorite_card_set_count()');
  p_user_a  uuid := gen_random_uuid();
  p_user_b  uuid := gen_random_uuid();
  v_sfx     text := substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
  v_set1    uuid;
  v_set2    uuid;
  v_seven   uuid[];
  v_b1      uuid;
  v_c1      uuid;
  v_i1      uuid;
  v_forced  boolean := false;
  v_rows    integer;
  v_id      uuid;
  v_s       text[];
  v_n       integer;
  v_m       integer;
  v_k       integer;
  v_base_us bigint;
  v_base_cf bigint;
  v_base_ca bigint;
  res       jsonb := '[]'::jsonb;
  r         jsonb;
  n         integer := 0;
  passes    integer := 0;
begin
  -- 0. Configuração e ACL -------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    v_f is not null
    and (select p.prosecdef and p.proconfig = array['search_path=""'] and l.lanname = 'plpgsql'
                and p.provolatile = 's' and p.prorettype = 'integer'::regtype
         from pg_proc p join pg_language l on l.oid = p.prolang where p.oid = v_f)
    and (select count(*) from pg_proc q join pg_namespace ns on ns.oid = q.pronamespace
         where ns.nspname = 'public' and q.proname = 'get_my_favorite_card_set_count') = 1,
    'detail','SECURITY DEFINER, search_path vazio, plpgsql, STABLE, integer, 1 versão');

  res := res || jsonb_build_object('id','0.2','ok',
    v_f is not null
    and has_function_privilege('authenticated', v_f, 'EXECUTE')
    and not has_function_privilege('anon', v_f, 'EXECUTE')
    and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = v_f and a.grantee = 0),
    'detail','EXECUTE só authenticated (anon e PUBLIC sem acesso)');

  select count(*) into v_base_us from auth.users;
  select count(*) into v_base_cf from public.card_favorite;
  select count(*) into v_base_ca from public.card where is_active;

  begin
    -- 1.1 anon / 2.1 sem identidade -----------------------------------------
    perform set_config('request.jwt.claims', '', true);
    execute 'set local role anon';
    v_s := '{}';
    begin perform public.get_my_favorite_card_set_count(); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.1','ok', v_s = array['42501'], 'detail','anon: '||array_to_string(v_s, ', '));

    execute 'set local role authenticated';
    v_s := '{}';
    begin perform public.get_my_favorite_card_set_count(); v_s := v_s || 'executou'::text; exception when others then v_s := v_s || sqlstate::text; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','2.1','ok', v_s = array['28000'], 'detail','sem identidade: '||array_to_string(v_s, ', '));

    -- Fixture de catálogo (dono do banco) -----------------------------------------
    select k.card_set_id into v_set1
    from public.card k where k.is_active
    group by k.card_set_id having count(*) >= 7
    order by k.card_set_id limit 1;
    v_seven := array(select k.id from public.card k where k.card_set_id = v_set1 and k.is_active order by k.id limit 7);
    select k.id, k.card_set_id into v_b1, v_set2
    from public.card k where k.is_active and k.card_set_id <> v_set1 order by k.id limit 1;
    select k.id into v_c1
    from public.card k where k.is_active and k.card_set_id not in (v_set1, v_set2) order by k.id limit 1;
    select k.id into v_i1
    from public.card k where not k.is_active and k.card_set_id not in (v_set1, v_set2) order by k.id limit 1;
    if v_i1 is null then
      select k.id into v_i1
      from public.card k
      where k.is_active and k.card_set_id not in (v_set1, v_set2) and k.id <> v_c1
      order by k.id limit 1;
      update public.card set is_active = false where id = v_i1 and is_active;   -- desfeito pelo TR000
      get diagnostics v_rows = row_count;
      if v_rows <> 1 then
        raise exception 'TR_FIXTURE: desativação transacional da carta do caso inativo afetou % linha(s)', v_rows;
      end if;
      v_forced := true;
    end if;
    if v_set1 is null or cardinality(v_seven) <> 7 or v_b1 is null or v_c1 is null or v_i1 is null then
      raise exception 'TR_FIXTURE: catálogo sem Card Set com 7 cartas ativas, sem segundo/terceiro Card Set ou sem carta para o caso inativo';
    end if;

    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    values (p_user_a, 'authenticated', 'authenticated', 'tr5870-a-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'tr5870a_'||v_sfx, 'display_name', 'TR 5870 A'), now(), now()),
           (p_user_b, 'authenticated', 'authenticated', 'tr5870-b-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'tr5870b_'||v_sfx, 'display_name', 'TR 5870 B'), now(), now());

    -- A ------------------------------------------------------------------------------
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';

    -- 3.1 sem favoritas
    v_n := public.get_my_favorite_card_set_count();
    res := res || jsonb_build_object('id','3.1','ok', v_n = 0, 'detail', format('A sem favoritas: %s (esperado 0)', v_n));

    -- 3.2 sete cartas do mesmo Card Set, sem possuí-las e sem coleção
    foreach v_id in array v_seven loop
      perform public.set_card_favorite(v_id, true);
    end loop;
    v_n := public.get_my_favorite_card_set_count();
    res := res || jsonb_build_object('id','3.2','ok', v_n = 1,
      'detail', format('7 favoritas do mesmo Card Set, sem exemplar nem coleção: %s (esperado 1)', v_n));

    -- 3.3 outro Card Set
    perform public.set_card_favorite(v_b1, true);
    v_n := public.get_my_favorite_card_set_count();
    res := res || jsonb_build_object('id','3.3','ok', v_n = 2, 'detail', format('+1 favorita de outro Card Set: %s (esperado 2)', v_n));
    execute 'reset role';

    -- 3.4 carta inativa (favorito gravado pelo dono do banco)
    insert into public.card_favorite (user_id, card_id) values (p_user_a, v_i1);
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    v_n := public.get_my_favorite_card_set_count();
    execute 'reset role';
    res := res || jsonb_build_object('id','3.4','ok', v_n = 2,
      'detail', format('favorita inativa de um terceiro Card Set: %s (esperado 2; carta %s)', v_n,
                       case when v_forced then 'desativada na transação' else 'já inativa no catálogo' end));

    -- 3.5 isolamento
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.set_card_favorite(v_c1, true);
    v_m := public.get_my_favorite_card_set_count();                -- B
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    v_k := public.get_my_favorite_card_set_count();                -- A com o favorito de B
    perform public.set_card_favorite(v_b1, false);
    v_s := array[public.get_my_favorite_card_set_count()::text];   -- A sem a carta do 2º Set
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    v_s := v_s || public.get_my_favorite_card_set_count()::text;   -- B depois
    execute 'reset role';
    res := res || jsonb_build_object('id','3.5','ok', v_m = 1 and v_k = 2 and v_s = array['1','1'],
      'detail', format('B %s (1), A %s (2), A desfavorita 2º Set %s (1), B %s (1)', v_m, v_k, v_s[1], v_s[2]));

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
      and (select count(*) from public.card where is_active) = v_base_ca
      and current_user = session_user,
    'detail','resíduo zero (usuários, favoritos, cartas ativas) e papel restaurado');

  for r in select * from jsonb_array_elements(res) loop
    n := n + 1;
    if coalesce((r->>'ok')::boolean, false) then passes := passes + 1; end if;
    seq := n; check_id := r->>'id';
    status := case when coalesce((r->>'ok')::boolean, false) then 'PASS' else 'FAIL' end;
    detail := r->>'detail';
    return next;
  end loop;
  seq := 99; check_id := 'GATE';
  status := case when passes = n and n = 10 then 'PASS' else 'FAIL' end;
  detail := format('%s/%s PASS (esperado 10)', passes, n);
  return next;
end;
$fn$;

select * from pg_temp.tr_5870_validate();
