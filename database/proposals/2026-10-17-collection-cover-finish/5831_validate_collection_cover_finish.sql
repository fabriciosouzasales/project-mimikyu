/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5831 - Validação de 5171–5174 (cor do fichário + leitura de
              logos de Set)
Versão......: 1.2 (2026-10-17, execução LIVE: S1.9 ignora as policies admin pré-existentes com roles {public}, que exigem is_admin(); v1.1, readiness K12: fixture de usuários corrigida; S1.8 cobre WITH CHECK; casos S2.6/S2.7/S2.8 novos)
Status......: PROPOSTA — NÃO EXECUTADA (rodar só depois de 5171–5174)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-17

Execução: um bloco por vez; tudo dentro de BEGIN … ROLLBACK, com usuários
efêmeros criados no próprio bloco (mesmo padrão do 5830 v1.1). Nenhum dado
real é lido como fixture nem alterado; resíduo zero após o ROLLBACK.
Resultado esperado: todas as linhas com ok = true.
================================================================
*/

-- Seção 1 — estrutura (somente leitura)
select 'S1.1 coluna cover_finish nula por padrão' as caso,
       exists (select 1 from information_schema.columns
               where table_schema = 'public' and table_name = 'collection'
                 and column_name = 'cover_finish' and is_nullable = 'YES') as ok
union all
select 'S1.2 CHECK do vocabulário',
       exists (select 1 from pg_constraint where conname = 'chk_collection_cover_finish')
union all
select 'S1.3 5172 SECURITY DEFINER + search_path vazio',
       exists (select 1 from pg_proc where proname = 'set_my_collection_cover_finish'
                 and prosecdef and proconfig @> array['search_path=""'])
union all
select 'S1.4 5172 sem EXECUTE para anon',
       not has_function_privilege('anon', 'public.set_my_collection_cover_finish(uuid, text)', 'EXECUTE')
union all
select 'S1.5 5173 devolve cover_finish',
       pg_get_function_result('public.get_my_collections(boolean, integer, integer)'::regprocedure) like '%cover_finish text%'
union all
select 'S1.6 5173 sem EXECUTE para anon',
       not has_function_privilege('anon', 'public.get_my_collections(boolean, integer, integer)', 'EXECUTE')
union all
select 'S1.7 policy de leitura para authenticated',
       exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
                 and policyname = 'card_set_logo_authenticated_select' and cmd = 'SELECT'
                 and roles = '{authenticated}')
union all
select 'S1.8 escrita do bucket continua admin-only (USING e WITH CHECK)',
       not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
                     and cmd <> 'SELECT'
                     and (coalesce(qual, '') || ' ' || coalesce(with_check, '')) ilike '%card-set-logo%'
                     and (coalesce(qual, '') || ' ' || coalesce(with_check, '')) not ilike '%is_admin%')
union all
select 'S1.9 nenhuma policy sem is_admin() alcança anon/public no bucket',
       not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
                     and (coalesce(qual, '') || ' ' || coalesce(with_check, '')) ilike '%card-set-logo%'
                     and (coalesce(qual, '') || ' ' || coalesce(with_check, '')) not ilike '%is_admin%'
                     and ('anon' = any(roles) or 'public' = any(roles)))
union all
select 'S1.10 5172 com EXECUTE para authenticated',
       has_function_privilege('authenticated', 'public.set_my_collection_cover_finish(uuid, text)', 'EXECUTE')
union all
select 'S1.11 5173 com EXECUTE para authenticated',
       has_function_privilege('authenticated', 'public.get_my_collections(boolean, integer, integer)', 'EXECUTE')
union all
select 'S1.12 authenticated sem UPDATE direto em collection',
       not has_table_privilege('authenticated', 'public.collection', 'UPDATE');

-- Seções 2 e 3 — comportamento (BEGIN … ROLLBACK, usuários efêmeros)
begin;

create temp table r5831 (caso text, ok boolean) on commit drop;
grant all on r5831 to authenticated, anon;

do $$
declare
  v_a uuid := gen_random_uuid();
  v_b uuid := gen_random_uuid();
  v_sfx text := substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
  v_set uuid;
  v_col uuid;
  v_res text;
begin
  -- handle_new_user (Query 1020) exige username/display_name: mesmo padrão do 5830 v1.1.
  insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  values (v_a, 'authenticated', 'authenticated', 'cover-a-' || v_sfx || '@test.invalid',
          jsonb_build_object('username', 'cov5831a_' || v_sfx, 'display_name', 'Cover 5831 A'), now(), now()),
         (v_b, 'authenticated', 'authenticated', 'cover-b-' || v_sfx || '@test.invalid',
          jsonb_build_object('username', 'cov5831b_' || v_sfx, 'display_name', 'Cover 5831 B'), now(), now());

  -- Fixture como dono do banco, antes de trocar de papel (mesmo critério do 5830).
  select c.card_set_id into v_set
  from public.card c
  join public.card_variant cv on cv.card_id = c.id and cv.is_default and cv.is_active
  where c.is_active
  group by c.card_set_id
  having count(distinct c.id) >= 2
  order by count(distinct c.id), c.card_set_id
  limit 1;

  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select c.collection_id into v_col
  from public.create_my_card_set_collection(gen_random_uuid(), v_set, 'Cover 5831', null) c;

  -- 2.1 grava e devolve
  v_res := public.set_my_collection_cover_finish(v_col, 'vinho');
  insert into r5831 values ('S2.1 grava vinho', v_res = 'vinho');
  -- 2.2 idempotente
  v_res := public.set_my_collection_cover_finish(v_col, 'vinho');
  insert into r5831 values ('S2.2 repetir devolve o mesmo', v_res = 'vinho');
  -- 2.3 valor inválido
  begin
    perform public.set_my_collection_cover_finish(v_col, 'neon');
    insert into r5831 values ('S2.3 recusa valor fora do vocabulário', false);
  exception when sqlstate '22023' then
    insert into r5831 values ('S2.3 recusa valor fora do vocabulário', true);
  end;
  -- 3.1 R1 v2 devolve a cor
  insert into r5831
  select 'S3.1 R1 devolve cover_finish', g.cover_finish = 'vinho'
  from public.get_my_collections(false, 48, 0) g where g.collection_id = v_col;

  -- 2.4 outro usuário não altera nem enumera
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin
    perform public.set_my_collection_cover_finish(v_col, 'perola');
    insert into r5831 values ('S2.4 usuário B não altera coleção de A', false);
  exception when sqlstate 'P0002' then
    insert into r5831 values ('S2.4 usuário B não altera coleção de A', true);
  end;
  insert into r5831
  select 'S3.2 R1 de B não vê a coleção de A', count(*) = 0
  from public.get_my_collections(true, 100, 0) g where g.collection_id = v_col;
  reset role;

  insert into r5831
  select 'S2.5 cor de A intacta após tentativa de B', c.cover_finish = 'vinho'
  from public.collection c where c.id = v_col;

  -- 2.6 coleção inexistente → mesma resposta que coleção alheia (não enumera)
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin
    perform public.set_my_collection_cover_finish(gen_random_uuid(), 'onix');
    insert into r5831 values ('S2.6 inexistente responde como alheia', false);
  exception when sqlstate 'P0002' then
    insert into r5831 values ('S2.6 inexistente responde como alheia', true);
  end;
  reset role;

  -- 2.7 sem sessão → not_authenticated
  perform set_config('request.jwt.claims', '', true);
  set local role authenticated;
  begin
    perform public.set_my_collection_cover_finish(v_col, 'onix');
    insert into r5831 values ('S2.7 sem sessão recusa', false);
  exception when sqlstate '28000' then
    insert into r5831 values ('S2.7 sem sessão recusa', true);
  end;
  reset role;

  -- 2.8 anon não executa (comportamento real, não só ACL)
  set local role anon;
  begin
    perform public.set_my_collection_cover_finish(v_col, 'onix');
    insert into r5831 values ('S2.8 anon sem EXECUTE', false);
  exception when insufficient_privilege then
    insert into r5831 values ('S2.8 anon sem EXECUTE', true);
  end;
  reset role;
end;
$$;

select caso, ok from r5831 order by caso;

rollback;

-- Seção 4 — leitura de logo por não-admin (manual, no app ou via API com a
-- sessão de um usuário comum): createSignedUrl('card-set-logo', <path de um
-- logo existente>) deve devolver URL; upload no mesmo bucket deve falhar.
-- Resíduo (após o ROLLBACK): select count(*) from auth.users where email like 'cover-%@test.invalid'; → 0
