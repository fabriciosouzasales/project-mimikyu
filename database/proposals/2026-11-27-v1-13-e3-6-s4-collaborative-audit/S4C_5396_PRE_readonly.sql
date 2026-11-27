/*
V1-13 · E3-6 / S4-c — 5396 v1.1: PRE SOMENTE LEITURA (um SELECT). PASS = todos os booleanos de primeiro
nível true; "escritores_referencias"/"escritores_preferencia" (assinatura completa) comparados pelo
executor v1.4 com S4C_5396_EXPECTATIVAS.json. Modo gate.
*/

select jsonb_build_object(
  'executor',                 current_user,
  'barreira',                 (select s.mode from public.v1_13_barrier_state s where s.id = 1),
  'identidades_teste',        (select count(*) from public.v1_13_barrier_identity),
  'funcoes_canonicas',        (select bool_and(x.ok) from (values
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.apply_my_binder_species_references(uuid, text)')) = '1fc0bbcbb88ef4722478cbd74db996c2'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.clear_my_binder_species_references(uuid, integer)')) = '723724fb7d47c135021ffe3c2cac3d1c'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_my_binder_species_reference_visibility(uuid, boolean)')) = 'bf3385f8ddb943581a19a0502b40b8c7'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_apply_binder_species_references(uuid, text)')) = '54d14043bc2826f687867c60c241db1f'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_clear_binder_species_references(uuid, integer)')) = 'dcc32db55aef7978b37c4ba1dc55f44b'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_set_binder_species_reference_visibility(uuid, boolean)')) = '0a1955ff43cdc3a3b23f87bf38efa42d'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.binder_activity_event_editor_type_guard()')) = '78fa0d34dad161eac1165f3143874260'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.binder_activity_category(text)')) = 'a7f9f99fa1f98171897904ed6d380bc4'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.get_my_binder_activity(uuid, text[], timestamptz, bigint, integer)')) = 'fab40eb28280d7c62ca207642b35ff65'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.get_shared_binder_activity(uuid, text[], timestamptz, bigint, integer)')) = '5b2887919ed00aca98b20d048f10722b')) x(ok)),
  'tipos_5341',               (select array_agg(m.v[1] order by m.v[1] collate "C") from pg_catalog.pg_constraint k cross join lateral regexp_matches(pg_catalog.pg_get_constraintdef(k.oid), '''([A-Z0-9_]+)''', 'g') as m(v) where k.conrelid = 'public.binder_activity_event'::regclass and k.conname = 'chk_bae_event_type') = array['BINDER_ASSEMBLED', 'BINDER_DELETED_EMPTY', 'BINDER_DISMANTLED', 'BINDER_OWNERSHIP_TRANSFERRED', 'CARDS_AUTO_ARRANGED', 'CARDS_LEFT_BY_COLLECTION_STORAGE', 'CARDS_LEFT_BY_STORAGE', 'CARDS_REMOVED', 'CARDS_SWAPPED', 'CARD_LEFT_BY_INVENTORY_EXIT', 'CARD_MOVED', 'CARD_PLACED', 'CATALOG_NOVELTIES_INCORPORATED', 'COLLECTION_ATTACHED', 'COLLECTION_DETACHED', 'GAP_CLOSED', 'GAP_OPENED', 'LEGACY_CATALOG_INCORPORATION', 'PAGES_ADDED', 'PAGES_REORDERED', 'PAGE_REMOVED', 'POCKETS_LOCKED', 'POCKETS_UNLOCKED', 'POCKET_RESERVED', 'RESERVATIONS_RELEASED']::text[],
  'dono_tabela_eventos',      pg_catalog.pg_has_role(current_user, (select c.relowner from pg_catalog.pg_class c where c.oid = 'public.binder_activity_event'::regclass), 'USAGE'),
  'gatilho_editor_ativo',     exists (select 1 from pg_catalog.pg_trigger t where t.tgrelid = 'public.binder_activity_event'::regclass
                                       and t.tgname = 'trg_bae_editor_event_type' and t.tgenabled = 'O'),
  'atribuicao_5379',          exists (select 1 from information_schema.columns c where c.table_schema = 'public'
                                       and c.table_name = 'binder_activity_event' and c.column_name = 'item_collection_recorded'),
  'pode_criar_em_public',     pg_catalog.has_schema_privilege(current_user, 'public', 'CREATE'),
  'sem_eventos_especie',      not exists (select 1 from public.binder_activity_event e where e.event_type like 'SPECIES%'),
  'ausente_5396',             to_regprocedure('public.binder_activity_record_species(uuid, uuid, text, integer)') is null,
  'escritores_referencias',   (select coalesce(string_agg(n.nspname || '.' || p.proname || '(' || replace(pg_catalog.oidvectortypes(p.proargtypes), ', ', ',') || ')', ', ' order by n.nspname || '.' || p.proname || '(' || replace(pg_catalog.oidvectortypes(p.proargtypes), ', ', ',') || ')' collate "C"), '')
                               from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                               where n.nspname = 'public' and p.prosrc ~* '(insert\s+into|delete\s+from|update)\s+public\.collection_layout_slot_species_reference\y'),
  'escritores_preferencia',   (select coalesce(string_agg(n.nspname || '.' || p.proname || '(' || replace(pg_catalog.oidvectortypes(p.proargtypes), ', ', ',') || ')', ', ' order by n.nspname || '.' || p.proname || '(' || replace(pg_catalog.oidvectortypes(p.proargtypes), ', ', ',') || ')' collate "C"), '')
                               from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                               where n.nspname = 'public' and p.prosrc ~* '(insert\s+into|delete\s+from|update)\s+public\.collection_layout_species_reference_setting\y'),
  'privilegios_observaveis',  (select jsonb_build_object('rolsuper', r.rolsuper, 'rolbypassrls', r.rolbypassrls) from pg_catalog.pg_roles r where r.rolname = current_user)
) as s4c_5396_pre;
