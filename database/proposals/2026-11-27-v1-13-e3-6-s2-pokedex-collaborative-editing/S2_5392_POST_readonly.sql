/*
V1-13 · E3-6 / S2 — 5392: POST SOMENTE LEITURA (um SELECT). PASS = todos os booleanos true,
barreira CLOSED e 0 identidades. O inventário depois da 5392 é conferido aqui como booleano
(lista exata esperada, ordenação C), não pelas expectativas do PRE (que são o estado anterior).
Executar pelo executor por arquivo (STD-005 §3), modo gate, depois do COMMIT confirmado.
*/

select jsonb_build_object(
  'rpcs_4',                   (select count(*) = 4 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                               where n.nspname = 'public'
                                 and p.proname in ('editor_move_pokedex_copy', 'editor_unassign_pokedex_copy',
                                                   'editor_choose_pokedex_representative', 'editor_restore_pokedex_automatic_representative')
                                 and p.prosecdef and p.proconfig = array['search_path=""'] and p.provolatile = 'v'
                                 and pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
                                 and not pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')
                                 and not pg_catalog.has_function_privilege('service_role', p.oid, 'EXECUTE')),
  'ajudantes_internos',       (select count(*) = 2 from pg_catalog.pg_proc p
                               where p.oid in (to_regprocedure('public.v1_13_resolve_pokedex_copy(uuid, text, uuid, bigint, uuid)'),
                                               to_regprocedure('public.v1_13_pokedex_position_in_scope(uuid, uuid)'))
                                 and p.prosecdef and p.proconfig = array['search_path=""']
                                 and not exists (select 1 from pg_catalog.pg_roles x
                                                 where x.rolname in ('anon', 'authenticated', 'service_role', 'authenticator')
                                                   and pg_catalog.has_function_privilege(x.oid, p.oid, 'EXECUTE'))),
  'escritas_5380_revogadas',  not exists (select 1 from pg_catalog.pg_roles x
                                          cross join unnest(array[to_regprocedure('public.editor_set_pokedex_position_assignment(uuid, uuid, uuid, boolean)'),
                                                                  to_regprocedure('public.editor_remove_pokedex_position_assignment(uuid, uuid)'),
                                                                  to_regprocedure('public.editor_set_pokedex_position_primary_representative(uuid, uuid)'),
                                                                  to_regprocedure('public.editor_clear_pokedex_position_primary_representative(uuid, uuid)')]) g(oid)
                                          where x.rolname in ('anon', 'authenticated', 'service_role', 'authenticator')
                                            and (g.oid is null or pg_catalog.has_function_privilege(x.oid, g.oid, 'EXECUTE'))),
  'inventario_atribuicao_pos',  (select coalesce(string_agg(n.nspname || '.' || p.proname || '(' || replace(pg_catalog.oidvectortypes(p.proargtypes), ', ', ',') || ')', ', ' order by n.nspname || '.' || p.proname || '(' || replace(pg_catalog.oidvectortypes(p.proargtypes), ', ', ',') || ')' collate "C"), '')
                                 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                                 where n.nspname = 'public' and p.prosrc ~* '(insert\s+into|delete\s+from|update)\s+public\.collection_pokedex_position_assignment\y')
                                = 'public.auto_assign_pokedex_position_species_match(), public.editor_move_pokedex_copy(uuid,text,uuid,uuid,boolean), public.editor_remove_pokedex_position_assignment(uuid,uuid), public.editor_set_pokedex_position_assignment(uuid,uuid,uuid,boolean), public.editor_unassign_pokedex_copy(uuid,text,uuid), public.remove_pokedex_position_assignment(uuid), public.set_pokedex_position_assignment(uuid,uuid,boolean)',
  'inventario_representante_pos', (select coalesce(string_agg(n.nspname || '.' || p.proname || '(' || replace(pg_catalog.oidvectortypes(p.proargtypes), ', ', ',') || ')', ', ' order by n.nspname || '.' || p.proname || '(' || replace(pg_catalog.oidvectortypes(p.proargtypes), ', ', ',') || ')' collate "C"), '')
                                 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                                 where n.nspname = 'public' and p.prosrc ~* '(insert\s+into|delete\s+from|update)\s+public\.collection_pokedex_position_primary_representative\y')
                                = 'public.clear_pokedex_position_primary_representative(uuid,uuid), public.editor_choose_pokedex_representative(uuid,text,uuid,text), public.editor_clear_pokedex_position_primary_representative(uuid,uuid), public.editor_restore_pokedex_automatic_representative(uuid,uuid,text), public.editor_set_pokedex_position_primary_representative(uuid,uuid), public.set_pokedex_position_primary_representative(uuid)',
  'titular_canonico',         (select bool_and(x.ok) from (values
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_pokedex_position_assignment(uuid, uuid, boolean)')) = '8c572182a03025503e993e5ecc25e07a'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.remove_pokedex_position_assignment(uuid)')) = '26ef2d5da3312661111df0194dfc8ba2'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_pokedex_position_primary_representative(uuid)')) = '6353dffe6c3877967997033dcc2bfd4c'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.clear_pokedex_position_primary_representative(uuid, uuid)')) = 'eeede3a5b871fbf07f81eb59ecea932f')) x(ok)),
  'dependencias_canonicas',   (select bool_and(x.ok) from (values
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_pokedex_copy_token(uuid, uuid, bigint)')) = '64fa85659b6b999796deeef94dad4e4c'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.collection_activity_open(uuid)')) = 'd5f52bf5a2a29f1a4d8279c560b97043'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.collection_activity_record_pokedex(uuid, text, uuid, uuid, uuid, uuid, text, boolean)')) = 'c7245940a39d7c2a3d0674deb3be06dd')) x(ok)),
  'sem_eventos',              not exists (select 1 from public.collection_activity_event),
  'barreira',                 (select s.mode from public.v1_13_barrier_state s where s.id = 1),
  'identidades_teste',        (select count(*) from public.v1_13_barrier_identity)
) as s2_5392_post;
