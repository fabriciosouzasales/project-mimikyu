/*
V1-13 · E3-6 / S4-b — 5395: POST SOMENTE LEITURA (um SELECT). PASS = todos os booleanos true, barreira
CLOSED e 0 identidades. Inventário de escritores inalterado (mesmas assinaturas) como booleano. Modo gate.
*/

select jsonb_build_object(
  'titular_instrumentado',    (select bool_and(x.ok) from (values
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_pokedex_position_assignment(uuid, uuid, boolean)')) = 'ce63a458c1e79024dd512e60726a4004'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.remove_pokedex_position_assignment(uuid)')) = '2502eb25191383cc00aac62969b2671d'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_pokedex_position_primary_representative(uuid)')) = '1bbf1a6a5fe0bafedadbb7543f6d7951'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.clear_pokedex_position_primary_representative(uuid, uuid)')) = '2bf25d3d21e6ab06ccb50269bff1502b')) x(ok)),
  'titular_privilegios',      (select bool_and(pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
                                       and not pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')
                                       and p.prosecdef and p.proconfig = array['search_path=""'])
                               from pg_catalog.pg_proc p
                               where p.oid in (to_regprocedure('public.set_pokedex_position_assignment(uuid, uuid, boolean)'), to_regprocedure('public.remove_pokedex_position_assignment(uuid)'), to_regprocedure('public.set_pokedex_position_primary_representative(uuid)'), to_regprocedure('public.clear_pokedex_position_primary_representative(uuid, uuid)'))),
  'leitura_historico',        (select count(*) = 1 from pg_catalog.pg_proc p
                               where p.oid = to_regprocedure('public.get_collection_activity(uuid, bigint, integer)')
                                 and p.prosecdef and p.proconfig = array['search_path=""'] and p.provolatile = 's'
                                 and pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
                                 and not pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')
                                 and not pg_catalog.has_function_privilege('service_role', p.oid, 'EXECUTE')),
  'inventario_atribuicao_pos',  (select coalesce(string_agg(n.nspname || '.' || p.proname || '(' || replace(pg_catalog.oidvectortypes(p.proargtypes), ', ', ',') || ')', ', ' order by n.nspname || '.' || p.proname || '(' || replace(pg_catalog.oidvectortypes(p.proargtypes), ', ', ',') || ')' collate "C"), '')
                               from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                               where n.nspname = 'public' and p.prosrc ~* '(insert\s+into|delete\s+from|update)\s+public\.collection_pokedex_position_assignment\y')
                                = 'public.auto_assign_pokedex_position_species_match(), public.editor_move_pokedex_copy(uuid,text,uuid,uuid,boolean), public.editor_remove_pokedex_position_assignment(uuid,uuid), public.editor_set_pokedex_position_assignment(uuid,uuid,uuid,boolean), public.editor_unassign_pokedex_copy(uuid,text,uuid), public.remove_pokedex_position_assignment(uuid), public.set_pokedex_position_assignment(uuid,uuid,boolean)',
  'inventario_representante_pos', (select coalesce(string_agg(n.nspname || '.' || p.proname || '(' || replace(pg_catalog.oidvectortypes(p.proargtypes), ', ', ',') || ')', ', ' order by n.nspname || '.' || p.proname || '(' || replace(pg_catalog.oidvectortypes(p.proargtypes), ', ', ',') || ')' collate "C"), '')
                               from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                               where n.nspname = 'public' and p.prosrc ~* '(insert\s+into|delete\s+from|update)\s+public\.collection_pokedex_position_primary_representative\y')
                                = 'public.clear_pokedex_position_primary_representative(uuid,uuid), public.editor_choose_pokedex_representative(uuid,text,uuid,text), public.editor_clear_pokedex_position_primary_representative(uuid,uuid), public.editor_restore_pokedex_automatic_representative(uuid,uuid,text), public.editor_set_pokedex_position_primary_representative(uuid,uuid), public.set_pokedex_position_primary_representative(uuid)',
  'dependencias_canonicas',   (select bool_and(x.ok) from (values
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_assert_capability()')) = 'e4f710904f50e6e8c3f1d8e2337639e0'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_capability_open()')) = '32e2f636361732b497e8401e50f0bbe0'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.collection_activity_open(uuid)')) = 'd5f52bf5a2a29f1a4d8279c560b97043'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.collection_activity_record_pokedex(uuid, text, uuid, uuid, uuid, uuid, text, boolean)')) = 'c7245940a39d7c2a3d0674deb3be06dd'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.collection_share_role(uuid)')) = 'efdb495b5b703e9f093eb0f49a1d0a5d')) x(ok)),
  'sem_eventos',              not exists (select 1 from public.collection_activity_event),
  'barreira',                 (select s.mode from public.v1_13_barrier_state s where s.id = 1),
  'identidades_teste',        (select count(*) from public.v1_13_barrier_identity)
) as s4b_5395_post;
