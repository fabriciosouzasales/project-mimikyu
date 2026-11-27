/*
V1-13 · E3-7b — 5397: PRE SOMENTE LEITURA (um SELECT). PASS = todos os booleanos de primeiro nível true;
"escritores_bolso" (funções da V1-13 que gravam bolsos) e "escritores_exposicao_fisica" (RPCs do EDITOR com
physical_card_id em argumento, coluna ou chave JSON, executáveis por authenticated) comparados pelo
executor v1.4 com E37B_5397_EXPECTATIVAS.json, por assinatura completa. Modo gate.
*/

select jsonb_build_object(
  'executor',                    current_user,
  'barreira',                    (select s.mode from public.v1_13_barrier_state s where s.id = 1),
  'identidades_teste',           (select count(*) from public.v1_13_barrier_identity),
  'funcoes_canonicas',           (select bool_and(x.ok) from (values
                                    ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.get_shared_binder_placeable_cards(uuid, integer, integer)')) = '8e9bf913f422eb60fb4dfc82f8741328'),
                                    ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_place_card_in_binder(uuid, integer, integer, integer, uuid)')) = 'd95ab478018a0dd431083cf0af492311'),
                                    ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_preview_binder_auto_arrange(uuid)')) = '0cb490ec67f551d0044226ab3c34fda1')) x(ok)),
  'ajudantes_canonicos',         (select bool_and(x.ok) from (values
                                    ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_pokedex_copy_token(uuid, uuid, bigint)')) = '64fa85659b6b999796deeef94dad4e4c'),
                                    ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_editor_membership(uuid)')) = '856ddff63fd4946f712bca1deeaa7a6c'),
                                    ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_resolve_pokedex_copy(uuid, text, uuid, bigint, uuid)')) = '20a6fbe856c0e2ba3987e236d1f00fb3'),
                                    ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_assert_capability()')) = 'e4f710904f50e6e8c3f1d8e2337639e0'),
                                    ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_capability_open()')) = '32e2f636361732b497e8401e50f0bbe0')) x(ok)),
  'contratos_antigos_ativos',    pg_catalog.has_function_privilege('authenticated', to_regprocedure('public.get_shared_binder_placeable_cards(uuid, integer, integer)'), 'EXECUTE')
                                 and pg_catalog.has_function_privilege('authenticated', to_regprocedure('public.editor_place_card_in_binder(uuid, integer, integer, integer, uuid)'), 'EXECUTE'),
  'ausente_5397',                to_regprocedure('public.get_shared_binder_placeable_copies(uuid, integer, integer)') is null
                                 and to_regprocedure('public.editor_place_copy_in_binder(uuid, integer, integer, integer, text)') is null,
  'pode_criar_em_public',        pg_catalog.has_schema_privilege(current_user, 'public', 'CREATE'),
  'escritores_bolso',            (select coalesce(string_agg(n.nspname || '.' || p.proname || '(' || replace(pg_catalog.oidvectortypes(p.proargtypes), ', ', ',') || ')', ', ' order by n.nspname || '.' || p.proname || '(' || replace(pg_catalog.oidvectortypes(p.proargtypes), ', ', ',') || ')' collate "C"), '')
                               from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                               where n.nspname = 'public' and p.prosrc ~ 'v1_13_(assert_capability|capability_open)'
                                 and p.prosrc ~* '(insert\s+into|delete\s+from|update)\s+public\.collection_layout_slot_assignment\y'),
  'escritores_exposicao_fisica', (select coalesce(string_agg(n.nspname || '.' || p.proname || '(' || replace(pg_catalog.oidvectortypes(p.proargtypes), ', ', ',') || ')', ', ' order by n.nspname || '.' || p.proname || '(' || replace(pg_catalog.oidvectortypes(p.proargtypes), ', ', ',') || ')' collate "C"), '')
                               from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                               where n.nspname = 'public' and p.prosrc ~ 'v1_13_(assert_capability|capability_open)' and p.proname ~ '^(editor_|get_shared_|get_editor_)'
                                 and pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
                                 and (exists (select 1 from unnest(coalesce(p.proargnames, array[]::text[])) a(nm) where a.nm like '%physical_card_id%')
                                      or p.prosrc like '%''physical_card_id''%')),
  'privilegios_observaveis',     (select jsonb_build_object('rolsuper', r.rolsuper, 'rolbypassrls', r.rolbypassrls) from pg_catalog.pg_roles r where r.rolname = current_user)
) as e37b_5397_pre;
