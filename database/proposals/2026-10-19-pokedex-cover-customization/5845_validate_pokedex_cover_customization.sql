/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5845 - Validação de 5206/5207 (capa e código no fichário
              da coleção Pokédex)
Versão......: 1.1 (v1.1: o resumo 5102 é lido com a identidade do dono — na v1.0 era lido com a de B e voltava nulo, falso FAIL em 5.1)
Status......: EXECUTADO no LIVE em 2026-10-19 após 5206/5207 — v1.0 14/15 (falso FAIL em 5.1,
              resumo lido sem a identidade do dono); v1.1 15/15 PASS, resíduo zero.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-19 (POKEDEX-COVER-CUSTOMIZATION-01)

Como rodar: um único statement (da criação de pg_temp.ms_5845_validate()
até o select final). Fixture sintética: usuários A e B, coleções criadas
pelos contratos oficiais (5175 livre, 5167 de Set, 5202 Pokédex) e
arquivos de capa como linhas em storage.objects — tudo desfeito pela
sentinela MS845 (rollback do bloco). 99.1 confere resíduo zero.

GATE: n = 15 e todas PASS.
================================================================
*/

create or replace function pg_temp.ms_5845_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
declare
  f_logo oid := to_regprocedure('public.set_my_collection_cover_logo(uuid,text)');
  f_code oid := to_regprocedure('public.set_my_collection_cover_code(uuid,text)');
  p_user_a uuid := gen_random_uuid();
  p_user_b uuid := gen_random_uuid();
  v_sfx text := lower(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  v_set uuid; v_box_a uuid; v_box_b uuid;
  v_free_a uuid; v_set_a uuid; v_dex_a uuid; v_dex_b uuid;
  v_p_dex_a1 text; v_p_dex_a2 text; v_p_free_a text; v_p_dex_b text;
  v_rec record; v_txt text; v_state text; v_msg text; v_ok boolean;
  v_total_before bigint; v_scope_before bigint;
  b_us bigint; b_co bigint; b_ca bigint; b_ob bigint; b_sc bigint; b_ccr bigint;
  res jsonb := '[]'::jsonb; r jsonb; n integer := 0; passes integer := 0;
begin
  -- 0. Estrutura ------------------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    f_logo is not null and f_code is not null
    and (select count(*) from pg_proc p where p.oid in (f_logo, f_code)
           and p.prosecdef and p.proconfig = array['search_path=""']) = 2
    and (select bool_and(has_function_privilege('authenticated', f, 'EXECUTE') and not has_function_privilege('anon', f, 'EXECUTE'))
           from unnest(array[f_logo, f_code]) f)
    and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid in (f_logo, f_code) and a.grantee = 0)
    and (select bool_and(position('POKEDEX' in p.prosrc) > 0) from pg_proc p where p.oid in (f_logo, f_code)),
    'detail','5206/5207 aplicadas: SECURITY DEFINER, search_path vazio, EXECUTE só authenticated, regra Pokédex presente');
  res := res || jsonb_build_object('id','0.2','ok',
    (select bool_and(p.prosrc !~ '(collection_allocation|physical_card|pokedex_position_assignment|scope_generation)')
       from pg_proc p where p.oid in (f_logo, f_code)),
    'detail','as duas funções não tocam cartas, alocações, vínculos nem escopo');

  select count(*) into b_us from auth.users;
  select count(*) into b_co from public.collection;
  select count(*) into b_ca from public.collection_allocation;
  select count(*) into b_ob from storage.objects;
  select count(*) into b_sc from public.storage_container;
  select count(*) into b_ccr from public.collection_creation_request;

  begin
    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    values (p_user_a, 'authenticated', 'authenticated', 'ms5845-a-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'ms5845a_'||v_sfx, 'display_name', 'MS 5845 A'), now(), now()),
           (p_user_b, 'authenticated', 'authenticated', 'ms5845-b-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'ms5845b_'||v_sfx, 'display_name', 'MS 5845 B'), now(), now());

    select cs.id into v_set
    from public.card_set cs join public.expansion e on e.id = cs.expansion_id
    join public.game g on g.id = e.game_id and g.code = 'POKEMON'
    order by cs.id limit 1;

    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select c.collection_id, c.storage_container_id into v_free_a, v_box_a
      from public.create_my_free_collection(gen_random_uuid(), 'Livre A 5845', null) c;
    select c.collection_id into v_set_a from public.create_my_card_set_collection(gen_random_uuid(), v_set, 'Set A 5845', v_box_a) c;
    select c.collection_id into v_dex_a from public.create_my_pokedex_collection(gen_random_uuid(), 'Pokédex A 5845', array['GENERATION_I'], v_box_a) c;
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select c.collection_id, c.storage_container_id into v_dex_b, v_box_b
      from public.create_my_pokedex_collection(gen_random_uuid(), 'Pokédex B 5845', array['GENERATION_I'], null) c;
    execute 'reset role';

    -- O resumo (5102) só responde ao dono: lido com a identidade de A (v1.1).
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    select s.total_positions into v_total_before from public.collection_completion_summary(v_dex_a) s;
    select count(*) into v_scope_before
      from public.collection_reference cr join public.collection_pokedex_scope_generation sg on sg.collection_reference_id = cr.id
     where cr.collection_id = v_dex_a;

    v_p_dex_a1 := p_user_a::text || '/' || v_dex_a::text || '/' || gen_random_uuid()::text || '.webp';
    v_p_dex_a2 := p_user_a::text || '/' || v_dex_a::text || '/' || gen_random_uuid()::text || '.png';
    v_p_free_a := p_user_a::text || '/' || v_free_a::text || '/' || gen_random_uuid()::text || '.jpg';
    v_p_dex_b  := p_user_b::text || '/' || v_dex_b::text || '/' || gen_random_uuid()::text || '.webp';
    insert into storage.objects (bucket_id, name, owner, owner_id, metadata)
    values ('collection-cover', v_p_dex_a1, p_user_a, p_user_a::text, '{"mimetype":"image/webp","size":1000}'::jsonb),
           ('collection-cover', v_p_dex_a2, p_user_a, p_user_a::text, '{"mimetype":"image/png","size":1000}'::jsonb),
           ('collection-cover', v_p_free_a, p_user_a, p_user_a::text, '{"mimetype":"image/jpeg","size":1000}'::jsonb),
           ('collection-cover', v_p_dex_b,  p_user_b, p_user_b::text, '{"mimetype":"image/webp","size":1000}'::jsonb);

    -- 1. anon / 2. sem identidade -----------------------------------------
    perform set_config('request.jwt.claims', '', true);
    execute 'set local role anon';
    v_ok := true;
    begin perform public.set_my_collection_cover_code(v_dex_a, 'PKX'); v_ok := false; exception when others then v_ok := v_ok and sqlstate = '42501'; end;
    begin perform public.set_my_collection_cover_logo(v_dex_a, v_p_dex_a1); v_ok := false; exception when others then v_ok := v_ok and sqlstate = '42501'; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.1','ok', v_ok, 'detail','anon recusado (42501) nas duas funções');

    execute 'set local role authenticated';
    v_ok := true;
    begin perform public.set_my_collection_cover_code(v_dex_a, 'PKX'); v_ok := false; exception when others then v_ok := v_ok and sqlstate = '28000'; end;
    begin perform public.set_my_collection_cover_logo(v_dex_a, v_p_dex_a1); v_ok := false; exception when others then v_ok := v_ok and sqlstate = '28000'; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','2.1','ok', v_ok, 'detail','authenticated sem identidade → 28000 nas duas funções');

    -- 3. Dono (A) na própria Pokédex --------------------------------------
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';

    v_txt := public.set_my_collection_cover_code(v_dex_a, ' pkx ');
    res := res || jsonb_build_object('id','3.1','ok',
      v_txt = 'PKX' and (select c.cover_code from public.collection c where c.id = v_dex_a) = 'PKX'
      and public.set_my_collection_cover_code(v_dex_a, 'PKX') = 'PKX',
      'detail','Pokédex aceita código (normalizado para PKX) e repetir é idempotente');

    select * into v_rec from public.set_my_collection_cover_logo(v_dex_a, v_p_dex_a1);
    v_ok := v_rec.cover_logo_path = v_p_dex_a1 and v_rec.previous_path is null;
    select * into v_rec from public.set_my_collection_cover_logo(v_dex_a, v_p_dex_a2);
    res := res || jsonb_build_object('id','3.2','ok',
      v_ok and v_rec.cover_logo_path = v_p_dex_a2 and v_rec.previous_path = v_p_dex_a1
      and (select c.cover_logo_path from public.collection c where c.id = v_dex_a) = v_p_dex_a2,
      'detail','Pokédex aceita imagem da capa; a troca devolve o caminho anterior');

    v_txt := public.set_my_collection_cover_code(v_dex_a, null);
    select * into v_rec from public.set_my_collection_cover_logo(v_dex_a, null);
    res := res || jsonb_build_object('id','3.3','ok',
      v_txt is null and v_rec.cover_logo_path is null and v_rec.previous_path = v_p_dex_a2
      and (select c.cover_code is null and c.cover_logo_path is null from public.collection c where c.id = v_dex_a),
      'detail','remover código e imagem volta à placa tipográfica');

    v_state := '';
    begin perform public.set_my_collection_cover_logo(v_dex_a, v_p_free_a); v_state := 'executou';
    exception when others then v_state := sqlstate || ' ' || sqlerrm; end;
    res := res || jsonb_build_object('id','3.4','ok', v_state = '22023 INVALID_COVER_PATH',
      'detail','arquivo de outra coleção do mesmo dono é recusado: '||v_state);

    v_state := '';
    begin perform public.set_my_collection_cover_code(v_dex_a, 'x'); v_state := 'executou';
    exception when others then v_state := sqlstate || ' ' || sqlerrm; end;
    res := res || jsonb_build_object('id','3.5','ok', v_state = '22023 INVALID_COVER_CODE',
      'detail','código fora do formato é recusado: '||v_state);

    -- Regressão: Coleção livre continua; coleção de Set continua recusada.
    v_txt := public.set_my_collection_cover_code(v_free_a, 'LVR');
    select * into v_rec from public.set_my_collection_cover_logo(v_free_a, v_p_free_a);
    res := res || jsonb_build_object('id','3.6','ok', v_txt = 'LVR' and v_rec.cover_logo_path = v_p_free_a,
      'detail','Coleção livre: código e imagem continuam funcionando (regressão)');

    v_ok := true;
    begin perform public.set_my_collection_cover_code(v_set_a, 'SET'); v_ok := false;
    exception when others then v_ok := v_ok and sqlstate = '55000' and sqlerrm = 'NOT_FREE_COLLECTION'; end;
    begin perform public.set_my_collection_cover_logo(v_set_a, null); v_ok := false;
    exception when others then v_ok := v_ok and sqlstate = '55000' and sqlerrm = 'NOT_FREE_COLLECTION'; end;
    res := res || jsonb_build_object('id','3.7','ok', v_ok
      and (select c.cover_code is null and c.cover_logo_path is null from public.collection c where c.id = v_set_a),
      'detail','coleção de Set continua recusada (55000 NOT_FREE_COLLECTION) nas duas funções');

    -- Deixa a Pokédex de A personalizada para o teste de isolamento.
    perform public.set_my_collection_cover_code(v_dex_a, 'DEX');
    perform public.set_my_collection_cover_logo(v_dex_a, v_p_dex_a1);
    execute 'reset role';

    -- 4. Isolamento (B) ---------------------------------------------------
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    v_ok := true;
    begin perform public.set_my_collection_cover_code(v_dex_a, 'HAX'); v_ok := false;
    exception when others then v_ok := v_ok and sqlstate = 'P0002' and sqlerrm = 'COLLECTION_NOT_FOUND'; end;
    begin perform public.set_my_collection_cover_logo(v_dex_a, null); v_ok := false;
    exception when others then v_ok := v_ok and sqlstate = 'P0002' and sqlerrm = 'COLLECTION_NOT_FOUND'; end;
    v_state := '';
    begin perform public.set_my_collection_cover_logo(v_dex_b, v_p_dex_a1); v_state := 'executou';
    exception when others then v_state := sqlstate || ' ' || sqlerrm; end;
    select * into v_rec from public.set_my_collection_cover_logo(v_dex_b, v_p_dex_b);
    execute 'reset role';
    res := res || jsonb_build_object('id','4.1','ok',
      v_ok and (select c.cover_code = 'DEX' and c.cover_logo_path = v_p_dex_a1 from public.collection c where c.id = v_dex_a),
      'detail','B na Pokédex de A → mesma resposta de inexistente (P0002); capa e código de A intactos');
    res := res || jsonb_build_object('id','4.2','ok',
      v_state = '22023 INVALID_COVER_PATH' and v_rec.cover_logo_path = v_p_dex_b,
      'detail','B não usa arquivo de A na própria Pokédex ('||v_state||'); com o próprio arquivo, funciona');

    -- 5. Nada além da aparência mudou --------------------------------------
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    res := res || jsonb_build_object('id','5.1','ok',
      v_total_before is not null and v_total_before > 0 and
      (select s.total_positions from public.collection_completion_summary(v_dex_a) s) = v_total_before
      and (select count(*) from public.collection_reference cr join public.collection_pokedex_scope_generation sg
             on sg.collection_reference_id = cr.id where cr.collection_id = v_dex_a) = v_scope_before
      and (select count(*) from public.collection_allocation ca where ca.collection_id in (v_dex_a, v_dex_b)) = 0,
      'detail','escopo, progresso e alocações da Pokédex inalterados pela personalização ('||coalesce(v_total_before::text,'∅')||' posições)');

    raise exception 'MS845' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MS845' then
      res := res || jsonb_build_object('id','X.1','ok', false, 'detail','erro inesperado: '||sqlstate||' '||sqlerrm);
    end if;
  end;

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  res := res || jsonb_build_object('id','99.1','ok',
    (select count(*) from auth.users) = b_us
      and (select count(*) from public.collection) = b_co
      and (select count(*) from public.collection_allocation) = b_ca
      and (select count(*) from storage.objects) = b_ob
      and (select count(*) from public.storage_container) = b_sc
      and (select count(*) from public.collection_creation_request) = b_ccr
      and current_user = session_user,
    'detail','resíduo zero (usuários, coleções, alocações, arquivos, locais, pedidos) e papel restaurado');

  for r in select * from jsonb_array_elements(res) loop
    n := n + 1;
    if coalesce((r->>'ok')::boolean, false) then passes := passes + 1; end if;
    seq := n; check_id := r->>'id';
    status := case when coalesce((r->>'ok')::boolean, false) then 'PASS' else 'FAIL' end;
    detail := r->>'detail';
    return next;
  end loop;
  seq := 999; check_id := 'GATE';
  status := case when passes = n and n = 15 then 'PASS' else 'FAIL' end;
  detail := format('%s/%s PASS (esperado 15)', passes, n);
  return next;
end;
$fn$;

select * from pg_temp.ms_5845_validate();
