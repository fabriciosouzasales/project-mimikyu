/*
V1-13 · E3-7b — 5397: POST SOMENTE LEITURA (um SELECT). PASS = todos os booleanos true, barreira CLOSED e
0 identidades. Exposição física das RPCs do EDITOR = vazia; escritores de bolso = anteriores + a nova. Modo gate.
*/

select jsonb_build_object(
  'funcoes_5397',                (select bool_and(x.ok) from (values
                                    ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.get_shared_binder_placeable_copies(uuid, integer, integer)')) = '1c544a74420bdbcdebacdf0168c3d7f0'),
                                    ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_place_copy_in_binder(uuid, integer, integer, integer, text)')) = '09ea8105066f51e519c78f1149e7b9e4'),
                                    ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_preview_binder_auto_arrange(uuid)')) = 'ba412a9ce16502e211bdac89f5146163')) x(ok)),
  'ajudantes_canonicos',         (select bool_and(x.ok) from (values
                                    ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_pokedex_copy_token(uuid, uuid, bigint)')) = '64fa85659b6b999796deeef94dad4e4c'),
                                    ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_editor_membership(uuid)')) = '856ddff63fd4946f712bca1deeaa7a6c'),
                                    ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_resolve_pokedex_copy(uuid, text, uuid, bigint, uuid)')) = '20a6fbe856c0e2ba3987e236d1f00fb3'),
                                    ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_assert_capability()')) = 'e4f710904f50e6e8c3f1d8e2337639e0'),
                                    ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_capability_open()')) = '32e2f636361732b497e8401e50f0bbe0')) x(ok)),
  'rpcs_novas',                  (select count(*) = 2 and bool_and(p.prosecdef and array['search_path=""'::text] <@ coalesce(p.proconfig, array[]::text[])
                                          and pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
                                          and not pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')
                                          and not pg_catalog.has_function_privilege('service_role', p.oid, 'EXECUTE'))
                                  from pg_catalog.pg_proc p
                                  where p.oid in (to_regprocedure('public.get_shared_binder_placeable_copies(uuid, integer, integer)'), to_regprocedure('public.editor_place_copy_in_binder(uuid, integer, integer, integer, text)'))),
  'contratos_antigos_revogados', not exists (select 1 from pg_catalog.pg_roles x where x.rolname in ('anon', 'authenticated', 'service_role', 'authenticator')
                                  and pg_catalog.has_function_privilege(x.oid, to_regprocedure('public.get_shared_binder_placeable_cards(uuid, integer, integer)'), 'EXECUTE'))
                                 and not exists (select 1 from pg_catalog.pg_roles x where x.rolname in ('anon', 'authenticated', 'service_role', 'authenticator')
                                  and pg_catalog.has_function_privilege(x.oid, to_regprocedure('public.editor_place_card_in_binder(uuid, integer, integer, integer, uuid)'), 'EXECUTE')),
  'previa_executavel',           pg_catalog.has_function_privilege('authenticated', to_regprocedure('public.editor_preview_binder_auto_arrange(uuid)'), 'EXECUTE'),
  'inventario_exposicao_pos',    (select coalesce(string_agg(n.nspname || '.' || p.proname || '(' || replace(pg_catalog.oidvectortypes(p.proargtypes), ', ', ',') || ')', ', ' order by n.nspname || '.' || p.proname || '(' || replace(pg_catalog.oidvectortypes(p.proargtypes), ', ', ',') || ')' collate "C"), '')
                               from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                               where n.nspname = 'public' and p.prosrc ~ 'v1_13_(assert_capability|capability_open)' and p.proname ~ '^(editor_|get_shared_|get_editor_)'
                                 and pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
                                 and (exists (select 1 from unnest(coalesce(p.proargnames, array[]::text[])) a(nm) where a.nm like '%physical_card_id%')
                                      or p.prosrc like '%''physical_card_id''%')) = '',
  'inventario_bolso_pos',        (select coalesce(string_agg(n.nspname || '.' || p.proname || '(' || replace(pg_catalog.oidvectortypes(p.proargtypes), ', ', ',') || ')', ', ' order by n.nspname || '.' || p.proname || '(' || replace(pg_catalog.oidvectortypes(p.proargtypes), ', ', ',') || ')' collate "C"), '')
                               from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                               where n.nspname = 'public' and p.prosrc ~ 'v1_13_(assert_capability|capability_open)'
                                 and p.prosrc ~* '(insert\s+into|delete\s+from|update)\s+public\.collection_layout_slot_assignment\y')
                                 = 'public.editor_apply_binder_auto_arrange(uuid,text), public.editor_move_binder_card(uuid,integer,integer,integer,integer,integer,integer), public.editor_place_card_in_binder(uuid,integer,integer,integer,uuid), public.editor_place_copy_in_binder(uuid,integer,integer,integer,text), public.editor_remove_binder_card(uuid,integer,integer,integer)',
  'barreira',                    (select s.mode from public.v1_13_barrier_state s where s.id = 1),
  'identidades_teste',           (select count(*) from public.v1_13_barrier_identity)
) as e37b_5397_post;
