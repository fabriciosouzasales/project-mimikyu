/*
V1-13 · E3-6 / S4-a — 5394: POST SOMENTE LEITURA (um SELECT). PASS = todos os booleanos
true, "sem_eventos" true, "escritores_md5" igual ao do PRE, barreira CLOSED, 0 identidades.
Executar pelo executor por arquivo (STD-005 §3), modo gate, depois do COMMIT confirmado.
*/

select jsonb_build_object(
  'tabela_interna',           to_regclass('public.collection_activity_event') is not null
                              and (select c.relrowsecurity from pg_catalog.pg_class c where c.oid = to_regclass('public.collection_activity_event'))
                              and not exists (select 1 from pg_catalog.pg_roles x where x.rolname in ('anon', 'authenticated', 'service_role', 'authenticator')
                                              and (pg_catalog.has_table_privilege(x.oid, 'public.collection_activity_event', 'SELECT')
                                                   or pg_catalog.has_table_privilege(x.oid, 'public.collection_activity_event', 'INSERT')
                                                   or pg_catalog.has_table_privilege(x.oid, 'public.collection_activity_event', 'UPDATE')
                                                   or pg_catalog.has_table_privilege(x.oid, 'public.collection_activity_event', 'DELETE'))),
  'funcoes_9',                (select count(*) = 9 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                               where n.nspname = 'public' and p.proname like 'collection_activity\_%'
                                 and p.prosecdef and p.proconfig = array['search_path=""']),
  'funcoes_sem_api',          not exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                                          cross join pg_catalog.pg_roles x
                                          where n.nspname = 'public' and p.proname like 'collection_activity\_%'
                                            and x.rolname in ('anon', 'authenticated', 'service_role', 'authenticator')
                                            and pg_catalog.has_function_privilege(x.oid, p.oid, 'EXECUTE')),
  'gatilhos_7',               (select count(*) = 7 from pg_catalog.pg_trigger t
                               where not t.tgisinternal and t.tgenabled = 'O' and t.tgname like 'trg\_900\_collection\_activity\_%'),
  'gatilhos_instrucao',       (select count(*) = 5 from pg_catalog.pg_trigger t
                               where not t.tgisinternal and t.tgname like 'trg\_900\_collection\_activity\_%'
                                 and pg_catalog.pg_get_triggerdef(t.oid) ~ 'FOR EACH STATEMENT'
                                 and pg_catalog.pg_get_triggerdef(t.oid) ~ 'REFERENCING (NEW|OLD) TABLE'),
  'sem_eventos',              not exists (select 1 from public.collection_activity_event),
  'escritores_md5',           (select md5(string_agg(p.proname || ':' || md5(p.prosrc), ';' order by p.proname, p.oid))
                               from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                               where n.nspname = 'public'
                                 and p.proname in ('allocate_physical_cards_to_collection', 'deallocate_physical_cards_from_collection',
                                                   'auto_assign_pokedex_position_species_match', 'set_pokedex_position_assignment',
                                                   'remove_pokedex_position_assignment', 'set_pokedex_position_primary_representative',
                                                   'clear_pokedex_position_primary_representative', 'editor_set_pokedex_position_assignment',
                                                   'editor_remove_pokedex_position_assignment', 'editor_set_pokedex_position_primary_representative',
                                                   'editor_clear_pokedex_position_primary_representative')),
  'titular_canonico',         (select bool_and(x.ok) from (values
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_pokedex_position_assignment(uuid, uuid, boolean)')) = '8c572182a03025503e993e5ecc25e07a'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.remove_pokedex_position_assignment(uuid)')) = '26ef2d5da3312661111df0194dfc8ba2'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_pokedex_position_primary_representative(uuid)')) = '6353dffe6c3877967997033dcc2bfd4c'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.clear_pokedex_position_primary_representative(uuid, uuid)')) = 'eeede3a5b871fbf07f81eb59ecea932f')) x(ok)),
  'barreira',                 (select s.mode from public.v1_13_barrier_state s where s.id = 1),
  'identidades_teste',        (select count(*) from public.v1_13_barrier_identity)
) as s4a_5394_post;
