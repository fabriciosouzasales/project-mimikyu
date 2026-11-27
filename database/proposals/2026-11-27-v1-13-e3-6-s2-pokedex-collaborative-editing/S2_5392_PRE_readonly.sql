/*
V1-13 · E3-6 / S2 — 5392: PRE SOMENTE LEITURA (um SELECT). Só catálogo e contagens.
PASS = todos os booleanos de primeiro nível true; "escritores_atribuicao" e
"escritores_representante" (por ASSINATURA COMPLETA, esquema.nome(tipos)) comparados pelo
executor v1.4 com S2_5392_EXPECTATIVAS.json; "acl_5380" e "privilegios_observaveis" são
relatório (o rollback usa acl_5380). Executar pelo executor por arquivo (STD-005 §3), modo gate.
*/

select jsonb_build_object(
  'executor',                 current_user,
  'barreira',                 (select s.mode from public.v1_13_barrier_state s where s.id = 1),
  'identidades_teste',        (select count(*) from public.v1_13_barrier_identity),
  'barreira_canonica',        (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_assert_capability()')) = 'e4f710904f50e6e8c3f1d8e2337639e0'
                              and (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_capability_open()')) = '32e2f636361732b497e8401e50f0bbe0',
  'dependencias_canonicas',   (select bool_and(x.ok) from (values
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.assert_collection_editor(uuid)')) = '9a7482588b5c7995f40a5d945c957f31'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_pokedex_of_collection(uuid)')) = '6342e8fea261c62487c7ebf5f2b66829'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_pokedex_copy_token(uuid, uuid, bigint)')) = '64fa85659b6b999796deeef94dad4e4c'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_editor_membership(uuid)')) = '856ddff63fd4946f712bca1deeaa7a6c'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.collection_activity_open(uuid)')) = 'd5f52bf5a2a29f1a4d8279c560b97043'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.collection_activity_record_pokedex(uuid, text, uuid, uuid, uuid, uuid, text, boolean)')) = 'c7245940a39d7c2a3d0674deb3be06dd')) x(ok)),
  'escritas_5380_canonicas',  (select bool_and(x.ok) from (values
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_set_pokedex_position_assignment(uuid, uuid, uuid, boolean)')) = '90ee1b0594ffe8cf7a3bf6c54549e5ef'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_remove_pokedex_position_assignment(uuid, uuid)')) = '3cef5f640a60b2ad290c9420cc71a596'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_set_pokedex_position_primary_representative(uuid, uuid)')) = '2882df84eb882648552c3350bda3876d'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_clear_pokedex_position_primary_representative(uuid, uuid)')) = 'b8d4408299e90de6258dcc0c7c2a1b75')) x(ok)),
  'titular_canonico',         (select bool_and(x.ok) from (values
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_pokedex_position_assignment(uuid, uuid, boolean)')) = '8c572182a03025503e993e5ecc25e07a'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.remove_pokedex_position_assignment(uuid)')) = '26ef2d5da3312661111df0194dfc8ba2'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_pokedex_position_primary_representative(uuid)')) = '6353dffe6c3877967997033dcc2bfd4c'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.clear_pokedex_position_primary_representative(uuid, uuid)')) = 'eeede3a5b871fbf07f81eb59ecea932f')) x(ok)),
  'escopo_geracoes_presente', to_regclass('public.collection_pokedex_scope_generation') is not null,
  'pode_criar_em_public',     pg_catalog.has_schema_privilege(current_user, 'public', 'CREATE'),
  'sem_eventos',              not exists (select 1 from public.collection_activity_event),
  'ausente_5392',             not exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                                          where n.nspname = 'public'
                                            and p.proname in ('v1_13_resolve_pokedex_copy', 'v1_13_pokedex_position_in_scope', 'editor_move_pokedex_copy', 'editor_unassign_pokedex_copy',
                                                              'editor_choose_pokedex_representative', 'editor_restore_pokedex_automatic_representative')),
  -- Gate do executor: escritores por assinatura completa (sobrecarga ou troca de assinatura são visíveis).
  'escritores_atribuicao',    (select coalesce(string_agg(n.nspname || '.' || p.proname || '(' || replace(pg_catalog.oidvectortypes(p.proargtypes), ', ', ',') || ')', ', ' order by n.nspname || '.' || p.proname || '(' || replace(pg_catalog.oidvectortypes(p.proargtypes), ', ', ',') || ')' collate "C"), '')
                               from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                               where n.nspname = 'public' and p.prosrc ~* '(insert\s+into|delete\s+from|update)\s+public\.collection_pokedex_position_assignment\y'),
  'escritores_representante', (select coalesce(string_agg(n.nspname || '.' || p.proname || '(' || replace(pg_catalog.oidvectortypes(p.proargtypes), ', ', ',') || ')', ', ' order by n.nspname || '.' || p.proname || '(' || replace(pg_catalog.oidvectortypes(p.proargtypes), ', ', ',') || ')' collate "C"), '')
                               from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                               where n.nspname = 'public' and p.prosrc ~* '(insert\s+into|delete\s+from|update)\s+public\.collection_pokedex_position_primary_representative\y'),
  -- Relatório: ACL atual das escritas da 5380 (referência do rollback).
  'acl_5380',                 (select coalesce(string_agg(p.proname || ':' || coalesce(r.rolname, 'PUBLIC'), ', ' order by p.proname, r.rolname), '')
                               from pg_catalog.pg_proc p cross join lateral pg_catalog.aclexplode(p.proacl) a
                               left join pg_catalog.pg_roles r on r.oid = a.grantee
                               where p.oid in (to_regprocedure('public.editor_set_pokedex_position_assignment(uuid, uuid, uuid, boolean)'),
                                               to_regprocedure('public.editor_remove_pokedex_position_assignment(uuid, uuid)'),
                                               to_regprocedure('public.editor_set_pokedex_position_primary_representative(uuid, uuid)'),
                                               to_regprocedure('public.editor_clear_pokedex_position_primary_representative(uuid, uuid)'))
                                 and a.privilege_type = 'EXECUTE' and a.grantee <> p.proowner),
  'privilegios_observaveis',  (select jsonb_build_object('rolsuper', r.rolsuper, 'rolbypassrls', r.rolbypassrls) from pg_catalog.pg_roles r where r.rolname = current_user)
) as s2_5392_pre;
