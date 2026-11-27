/*
V1-13 · E3-6 / S4-c — 5396 v1.1: POST SOMENTE LEITURA (um SELECT). PASS = todos os booleanos true, barreira
CLOSED e 0 identidades. Inventário de escritores inalterado (mesmas assinaturas) como booleano. Modo gate.
*/

select jsonb_build_object(
  'funcoes_instrumentadas',   (select bool_and(x.ok) from (values
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.apply_my_binder_species_references(uuid, text)')) = 'bc19e70ae2dd815dddaf03a47e989251'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.clear_my_binder_species_references(uuid, integer)')) = '82bd5d3f36f20ab77338c92fc2b1a916'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_my_binder_species_reference_visibility(uuid, boolean)')) = 'c5455b5cb3457d82c4231b90b54708d9'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_apply_binder_species_references(uuid, text)')) = '61e9a9785e72c19b5bacdc121bbb0e69'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_clear_binder_species_references(uuid, integer)')) = '86e9736fa756119f9d04f290b8c1c8a1'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_set_binder_species_reference_visibility(uuid, boolean)')) = 'd429cea12b4ad9b863bfb1b176f6a257'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.binder_activity_event_editor_type_guard()')) = '5ef790bd6c70c22efbe737f318d1ec21'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.binder_activity_category(text)')) = '0e25078ad9db87616f713edb66504c19'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.get_my_binder_activity(uuid, text[], timestamptz, bigint, integer)')) = 'e6e6d1a4102ab42253346f9ef0598d46'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.get_shared_binder_activity(uuid, text[], timestamptz, bigint, integer)')) = '4e8b83043b037feb6740132729c4f6d4')) x(ok)),
  'tipos_5396',               (select array_agg(m.v[1] order by m.v[1] collate "C") from pg_catalog.pg_constraint k cross join lateral regexp_matches(pg_catalog.pg_get_constraintdef(k.oid), '''([A-Z0-9_]+)''', 'g') as m(v) where k.conrelid = 'public.binder_activity_event'::regclass and k.conname = 'chk_bae_event_type') = array['BINDER_ASSEMBLED', 'BINDER_DELETED_EMPTY', 'BINDER_DISMANTLED', 'BINDER_OWNERSHIP_TRANSFERRED', 'CARDS_AUTO_ARRANGED', 'CARDS_LEFT_BY_COLLECTION_STORAGE', 'CARDS_LEFT_BY_STORAGE', 'CARDS_REMOVED', 'CARDS_SWAPPED', 'CARD_LEFT_BY_INVENTORY_EXIT', 'CARD_MOVED', 'CARD_PLACED', 'CATALOG_NOVELTIES_INCORPORATED', 'COLLECTION_ATTACHED', 'COLLECTION_DETACHED', 'GAP_CLOSED', 'GAP_OPENED', 'LEGACY_CATALOG_INCORPORATION', 'PAGES_ADDED', 'PAGES_REORDERED', 'PAGE_REMOVED', 'POCKETS_LOCKED', 'POCKETS_UNLOCKED', 'POCKET_RESERVED', 'RESERVATIONS_RELEASED', 'SPECIES_REFERENCES_APPLIED', 'SPECIES_REFERENCES_CLEARED', 'SPECIES_REFERENCES_HIDDEN', 'SPECIES_REFERENCES_SHOWN']::text[],
  'privilegios_rpcs',         (select count(*) = 8 and bool_and(p.prosecdef and array['search_path=""'::text] <@ coalesce(p.proconfig, array[]::text[])
                                       and pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
                                       and not pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE'))
                               from pg_catalog.pg_proc p where p.oid in (to_regprocedure('public.apply_my_binder_species_references(uuid, text)'), to_regprocedure('public.clear_my_binder_species_references(uuid, integer)'), to_regprocedure('public.set_my_binder_species_reference_visibility(uuid, boolean)'), to_regprocedure('public.editor_apply_binder_species_references(uuid, text)'), to_regprocedure('public.editor_clear_binder_species_references(uuid, integer)'), to_regprocedure('public.editor_set_binder_species_reference_visibility(uuid, boolean)'), to_regprocedure('public.get_my_binder_activity(uuid, text[], timestamptz, bigint, integer)'), to_regprocedure('public.get_shared_binder_activity(uuid, text[], timestamptz, bigint, integer)'))),
  'leituras_stable',          (select count(*) = 2 and bool_and(p.provolatile = 's') from pg_catalog.pg_proc p where p.oid in (to_regprocedure('public.get_my_binder_activity(uuid, text[], timestamptz, bigint, integer)'), to_regprocedure('public.get_shared_binder_activity(uuid, text[], timestamptz, bigint, integer)'))),
  'primitiva_interna',        (select count(*) = 1 from pg_catalog.pg_proc p
                               where p.oid = to_regprocedure('public.binder_activity_record_species(uuid, uuid, text, integer)')
                                 and p.prosecdef and p.proconfig = array['search_path=""']
                                 and not exists (select 1 from pg_catalog.pg_roles x
                                                 where x.rolname in ('anon', 'authenticated', 'service_role', 'authenticator')
                                                   and pg_catalog.has_function_privilege(x.oid, p.oid, 'EXECUTE'))),
  'categoria_especie',        public.binder_activity_category('SPECIES_REFERENCES_APPLIED') = 'SPECIES'
                              and public.binder_activity_category('SPECIES_REFERENCES_HIDDEN') = 'SPECIES'
                              and public.binder_activity_category('CARDS_AUTO_ARRANGED') = 'CARDS'
                              and public.binder_activity_category('BINDER_ASSEMBLED') = 'BINDER',
  'gatilho_editor_ativo',     exists (select 1 from pg_catalog.pg_trigger t where t.tgrelid = 'public.binder_activity_event'::regclass
                                       and t.tgname = 'trg_bae_editor_event_type' and t.tgenabled = 'O'),
  'inventario_referencias_pos', (select coalesce(string_agg(n.nspname || '.' || p.proname || '(' || replace(pg_catalog.oidvectortypes(p.proargtypes), ', ', ',') || ')', ', ' order by n.nspname || '.' || p.proname || '(' || replace(pg_catalog.oidvectortypes(p.proargtypes), ', ', ',') || ')' collate "C"), '')
                               from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                               where n.nspname = 'public' and p.prosrc ~* '(insert\s+into|delete\s+from|update)\s+public\.collection_layout_slot_species_reference\y')
                                = 'public.apply_my_binder_species_references(uuid,text), public.clear_my_binder_species_references(uuid,integer), public.editor_apply_binder_species_references(uuid,text), public.editor_clear_binder_species_references(uuid,integer), public.editor_remove_binder_page(uuid,integer,integer), public.remove_layout_page(uuid,integer)',
  'inventario_preferencia_pos', (select coalesce(string_agg(n.nspname || '.' || p.proname || '(' || replace(pg_catalog.oidvectortypes(p.proargtypes), ', ', ',') || ')', ', ' order by n.nspname || '.' || p.proname || '(' || replace(pg_catalog.oidvectortypes(p.proargtypes), ', ', ',') || ')' collate "C"), '')
                               from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                               where n.nspname = 'public' and p.prosrc ~* '(insert\s+into|delete\s+from|update)\s+public\.collection_layout_species_reference_setting\y')
                                = 'public.apply_my_binder_species_references(uuid,text), public.editor_apply_binder_species_references(uuid,text), public.editor_set_binder_species_reference_visibility(uuid,boolean), public.set_my_binder_species_reference_visibility(uuid,boolean)',
  'sem_eventos_especie',      not exists (select 1 from public.binder_activity_event e where e.event_type like 'SPECIES%'),
  'barreira',                 (select s.mode from public.v1_13_barrier_state s where s.id = 1),
  'identidades_teste',        (select count(*) from public.v1_13_barrier_identity)
) as s4c_5396_post;
