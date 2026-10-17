/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5829 - Validate remove_my_physical_card (5165)
Versão......: 1.1 (fixture: create_collection exige Storage Container
              do próprio Inventory — 1ª execução abortou no fixture,
              não na 5165)
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-17 — 14/14 PASS
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-17 (INVENTORY-REMOVE-COPY-01)

Mesmo protocolo de 5827: tudo num único statement; fixtures, trocas
de papel e chamadas ficam num bloco que termina SEMPRE com a exceção
sentinela LI000 — o savepoint desfaz tudo (exemplares, coleção,
alocação). Resultados sobrevivem em variáveis. Depois do bloco, 9.1
prova que nada ficou (contagens iguais à linha de base).

Execução (por Fabrício), com 5165 aplicada:
  SELECT * FROM pg_temp.rc_5829_validate('<UUID usuário A>', '<UUID usuário B>');
  A e B: usuários reais distintos, com Inventory (qualquer um; os
  exemplares de teste são criados e desfeitos dentro do statement).

Esperado: 14 linhas PASS + GATE = PASS.
================================================================
*/

create or replace function pg_temp.rc_5829_validate(p_user_a uuid, p_user_b uuid)
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  v_fn       oid := to_regprocedure('public.remove_my_physical_card(uuid)');
  v_inv_a    uuid;
  v_variant  uuid;
  v_game     uuid;
  v_lang     uuid;
  v_card1    uuid;
  v_card2    uuid;
  v_coll     uuid;
  v_box      uuid;
  v_base_pc  bigint;
  v_base_sc  bigint;
  v_base_ca  bigint;
  v_base_co  bigint;
  v_state    text;
  v_bool     boolean;
  res        jsonb := '[]'::jsonb;
  r          jsonb;
  n          integer := 0;
  passes     integer := 0;
begin
  -- 0. Estrutura e privilégios
  res := res || jsonb_build_object('id','0.1','ok', v_fn is not null, 'detail','função existe');
  res := res || jsonb_build_object('id','0.2','ok',
    coalesce((select p.prosecdef and p.provolatile = 'v' and p.proconfig = array['search_path=""']
              from pg_proc p where p.oid = v_fn), false),
    'detail','SECURITY DEFINER, VOLATILE, search_path vazio');
  res := res || jsonb_build_object('id','0.3','ok',
    v_fn is not null and has_function_privilege('authenticated', v_fn, 'EXECUTE')
      and not has_function_privilege('anon', v_fn, 'EXECUTE'),
    'detail','EXECUTE só authenticated');

  select i.id into v_inv_a from public.inventory i where i.owner_user_id = p_user_a;
  select cv.id, e.game_id into v_variant, v_game
  from public.card_variant cv
  join public.card c on c.id = cv.card_id and c.is_active
  join public.card_set cs on cs.id = c.card_set_id
  join public.expansion e on e.id = cs.expansion_id
  where cv.is_active
  order by cv.id limit 1;
  select l.id into v_lang from public.language l where l.code = 'pt-BR';
  res := res || jsonb_build_object('id','0.4','ok',
    v_inv_a is not null and v_variant is not null and v_lang is not null and p_user_a <> p_user_b
      and exists (select 1 from public.inventory i where i.owner_user_id = p_user_b),
    'detail','fixture: A e B com Inventory, variante ativa, idioma');

  select count(*) into v_base_pc from public.physical_card;
  select count(*) into v_base_ca from public.collection_allocation;
  select count(*) into v_base_co from public.collection;
  select count(*) into v_base_sc from public.storage_container;

  begin
    insert into public.physical_card (card_variant_id, language_id, inventory_id)
    values (v_variant, v_lang, v_inv_a) returning id into v_card1;
    insert into public.physical_card (card_variant_id, language_id, inventory_id)
    values (v_variant, v_lang, v_inv_a) returning id into v_card2;
    -- create_collection exige um Storage Container do próprio Inventory (v1.1)
    insert into public.storage_container (inventory_id, name)
    values (v_inv_a, 'Caixa 5829') returning id into v_box;

    -- 1. anon
    perform set_config('request.jwt.claims', '', true);
    execute 'set local role anon';
    begin perform public.remove_my_physical_card(v_card1); v_state := 'executou';
    exception when others then v_state := sqlstate; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.1','ok', v_state = '42501', 'detail','anon: '||v_state);

    -- 2. sem auth.uid()
    execute 'set local role authenticated';
    begin perform public.remove_my_physical_card(v_card1); v_state := 'executou';
    exception when others then v_state := sqlstate; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','2.1','ok', v_state = '28000', 'detail','sem identidade: '||v_state);

    -- 3. B tenta remover exemplar de A → false, e o exemplar continua existindo
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    v_bool := public.remove_my_physical_card(v_card1);
    begin perform public.remove_my_physical_card(null); v_state := 'executou';
    exception when others then v_state := sqlstate; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','3.1','ok', v_bool = false and exists (select 1 from public.physical_card where id = v_card1),
             'detail', format('B sobre exemplar de A → %s (exemplar intacto)', v_bool));
    res := res || jsonb_build_object('id','3.2','ok', v_state = '22023', 'detail','id nulo: '||v_state);

    -- 4. A remove o próprio exemplar → true; repetir → false (idempotente); inexistente → false
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    v_bool := public.remove_my_physical_card(v_card1);
    res := res || jsonb_build_object('id','4.1','ok', v_bool = true, 'detail', format('A remove o próprio → %s', v_bool));
    v_bool := public.remove_my_physical_card(v_card1);
    res := res || jsonb_build_object('id','4.2','ok', v_bool = false, 'detail', format('repetição → %s', v_bool));
    v_bool := public.remove_my_physical_card(gen_random_uuid());
    res := res || jsonb_build_object('id','4.3','ok', v_bool = false, 'detail', format('inexistente → %s', v_bool));

    -- 5. Exemplar alocado em coleção → 55000 e continua existindo
    select c.id into v_coll from public.create_collection(v_game, 'Coleção 5829', null, v_box) c;
    perform public.allocate_physical_cards_to_collection(v_coll, array[v_card2]);
    begin perform public.remove_my_physical_card(v_card2); v_state := 'executou';
    exception when others then v_state := sqlstate; end;
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    res := res || jsonb_build_object('id','4.4','ok', not exists (select 1 from public.physical_card where id = v_card1),
             'detail','exemplar removido não existe mais');
    res := res || jsonb_build_object('id','5.1','ok', v_state = '55000' and exists (select 1 from public.physical_card where id = v_card2),
             'detail','alocado: '||v_state||' (exemplar intacto)');

    raise exception 'LI000' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'LI000' then
      res := res || jsonb_build_object('id','X.1','ok', false, 'detail','erro inesperado: '||sqlstate||' '||sqlerrm);
    end if;
  end;

  execute 'reset role';
  res := res || jsonb_build_object('id','9.1','ok',
    (select count(*) from public.physical_card) = v_base_pc
      and (select count(*) from public.collection_allocation) = v_base_ca
      and (select count(*) from public.collection) = v_base_co
      and (select count(*) from public.storage_container) = v_base_sc
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
  seq := 99; check_id := 'GATE';
  status := case when passes = n and n = 14 then 'PASS' else 'FAIL' end;
  detail := format('%s/%s PASS (esperado 14)', passes, n);
  return next;
end;
$fn$;

-- SELECT * FROM pg_temp.rc_5829_validate('<UUID usuário A>', '<UUID usuário B>');
