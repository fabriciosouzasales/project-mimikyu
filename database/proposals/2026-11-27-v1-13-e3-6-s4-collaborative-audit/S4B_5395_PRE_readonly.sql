/*
V1-13 · E3-6 / S4-b — 5395: PRE SOMENTE LEITURA (um SELECT). PASS = todos os booleanos de primeiro
nível true; "escritores_atribuicao"/"escritores_representante" (assinatura completa) comparados pelo
executor v1.4 com S4B_5395_EXPECTATIVAS.json (inventário confirmado no POST da 5392). Modo gate.
*/

select jsonb_build_object(
  'executor',                 current_user,
  'barreira',                 (select s.mode from public.v1_13_barrier_state s where s.id = 1),
  'identidades_teste',        (select count(*) from public.v1_13_barrier_identity),
  'dependencias_canonicas',   (select bool_and(x.ok) from (values
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_assert_capability()')) = 'e4f710904f50e6e8c3f1d8e2337639e0'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_capability_open()')) = '32e2f636361732b497e8401e50f0bbe0'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.collection_activity_open(uuid)')) = 'd5f52bf5a2a29f1a4d8279c560b97043'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.collection_activity_record_pokedex(uuid, text, uuid, uuid, uuid, uuid, text, boolean)')) = 'c7245940a39d7c2a3d0674deb3be06dd'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.collection_share_role(uuid)')) = 'efdb495b5b703e9f093eb0f49a1d0a5d')) x(ok)),
  'titular_canonico',         (select bool_and(x.ok) from (values
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_pokedex_position_assignment(uuid, uuid, boolean)')) = '8c572182a03025503e993e5ecc25e07a'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.remove_pokedex_position_assignment(uuid)')) = '26ef2d5da3312661111df0194dfc8ba2'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_pokedex_position_primary_representative(uuid)')) = '6353dffe6c3877967997033dcc2bfd4c'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.clear_pokedex_position_primary_representative(uuid, uuid)')) = 'eeede3a5b871fbf07f81eb59ecea932f')) x(ok)),
  'dependencia_5392',         to_regprocedure('public.editor_move_pokedex_copy(uuid, text, uuid, uuid, boolean)') is not null
                              and to_regclass('public.collection_activity_event') is not null,
  'perfil_publico_presente',  to_regclass('public.user_profile') is not null,
  'pode_criar_em_public',     pg_catalog.has_schema_privilege(current_user, 'public', 'CREATE'),
  'sem_eventos',              not exists (select 1 from public.collection_activity_event),
  'ausente_5395',             to_regprocedure('public.get_collection_activity(uuid, bigint, integer)') is null,
  'escritores_atribuicao',    (select coalesce(string_agg(n.nspname || '.' || p.proname || '(' || replace(pg_catalog.oidvectortypes(p.proargtypes), ', ', ',') || ')', ', ' order by n.nspname || '.' || p.proname || '(' || replace(pg_catalog.oidvectortypes(p.proargtypes), ', ', ',') || ')' collate "C"), '')
                               from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                               where n.nspname = 'public' and p.prosrc ~* '(insert\s+into|delete\s+from|update)\s+public\.collection_pokedex_position_assignment\y'),
  'escritores_representante', (select coalesce(string_agg(n.nspname || '.' || p.proname || '(' || replace(pg_catalog.oidvectortypes(p.proargtypes), ', ', ',') || ')', ', ' order by n.nspname || '.' || p.proname || '(' || replace(pg_catalog.oidvectortypes(p.proargtypes), ', ', ',') || ')' collate "C"), '')
                               from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                               where n.nspname = 'public' and p.prosrc ~* '(insert\s+into|delete\s+from|update)\s+public\.collection_pokedex_position_primary_representative\y'),
  'privilegios_observaveis',  (select jsonb_build_object('rolsuper', r.rolsuper, 'rolbypassrls', r.rolbypassrls) from pg_catalog.pg_roles r where r.rolname = current_user)
) as s4b_5395_pre;
