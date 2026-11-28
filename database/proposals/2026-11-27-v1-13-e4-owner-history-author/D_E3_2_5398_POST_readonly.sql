/*
V1-13 · D-E3-2 — 5398: POST SOMENTE LEITURA (um SELECT, modo gate). PASS = booleanos true, barreira CLOSED, 0 identidades.
*/

select jsonb_build_object(
  'executor',                   current_user,
  'barreira',                   (select s.mode from public.v1_13_barrier_state s where s.id = 1),
  'identidades_teste',          (select count(*) from public.v1_13_barrier_identity),
  'funcoes_barreira_canonicas', (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_assert_capability()')) = 'e4f710904f50e6e8c3f1d8e2337639e0'
                                and (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_capability_open()')) = '32e2f636361732b497e8401e50f0bbe0',
  'funcao_5398',                (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.get_my_binder_activity_actors(uuid, bigint[])')) = 'f395a0f109b760a863e8e00832c177b6',
  'definer_estavel_search_path', (select p.prosecdef and p.provolatile = 's' and array['search_path=""'::text] <@ coalesce(p.proconfig, array[]::text[])
                                 from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.get_my_binder_activity_actors(uuid, bigint[])')),
  'so_authenticated',           pg_catalog.has_function_privilege('authenticated', to_regprocedure('public.get_my_binder_activity_actors(uuid, bigint[])'), 'EXECUTE')
                                and not pg_catalog.has_function_privilege('anon', to_regprocedure('public.get_my_binder_activity_actors(uuid, bigint[])'), 'EXECUTE')
                                and not pg_catalog.has_function_privilege('service_role', to_regprocedure('public.get_my_binder_activity_actors(uuid, bigint[])'), 'EXECUTE')
) as d_e3_2_5398_post;
