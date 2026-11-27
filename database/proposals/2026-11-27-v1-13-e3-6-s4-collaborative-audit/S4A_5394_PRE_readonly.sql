/*
V1-13 · E3-6 / S4-a — 5394: PRE SOMENTE LEITURA (um SELECT). Só catálogo e contagens.
PASS = todos os booleanos de primeiro nível true. "escritores_*", "gatilhos_existentes" e
"privilegios_observaveis" são relatório; "escritores_md5" deve reaparecer igual no POST.
"escritores_atribuicao"/"escritores_representante" são comparados pelo executor v1.4 com
S4A_5394_EXPECTATIVAS.json (gate obrigatório). "sessoes_com_trava" é relatório.
Executar pelo executor por arquivo (STD-005 §3), modo gate.
*/

select jsonb_build_object(
  'executor',                 current_user,
  'barreira',                 (select s.mode from public.v1_13_barrier_state s where s.id = 1),
  'identidades_teste',        (select count(*) from public.v1_13_barrier_identity),
  'barreira_canonica',        (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_assert_capability()')) = 'e4f710904f50e6e8c3f1d8e2337639e0',
  'titular_canonico',         (select bool_and(x.ok) from (values
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_pokedex_position_assignment(uuid, uuid, boolean)')) = '8c572182a03025503e993e5ecc25e07a'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.remove_pokedex_position_assignment(uuid)')) = '26ef2d5da3312661111df0194dfc8ba2'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_pokedex_position_primary_representative(uuid)')) = '6353dffe6c3877967997033dcc2bfd4c'),
                                 ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.clear_pokedex_position_primary_representative(uuid, uuid)')) = 'eeede3a5b871fbf07f81eb59ecea932f')) x(ok)),
  -- V06: em tabelas public do projeto, pertencer ao dono É a prova de que se pode criar gatilho.
  'executor_dono_tabelas',    (select bool_and(pg_catalog.pg_has_role(current_user, c.relowner, 'MEMBER')) from pg_catalog.pg_class c
                               where c.oid in ('public.collection_allocation'::regclass, 'public.collection_pokedex_position_assignment'::regclass,
                                               'public.collection_pokedex_position_primary_representative'::regclass, 'public.collection'::regclass)),
  'pode_referenciar_usuarios', pg_catalog.has_table_privilege(current_user, 'auth.users', 'REFERENCES'),
  'ausente_5394',             to_regclass('public.collection_activity_event') is null
                              and not exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                                              where n.nspname = 'public' and p.proname like 'collection_activity\_%')
                              and not exists (select 1 from pg_catalog.pg_trigger t where not t.tgisinternal and t.tgname like 'trg\_900\_collection\_activity\_%'),
  -- Ordem aprovada (D4): a 5391 precisa estar implantada e com o gatilho de época habilitado.
  'dependencia_5391',         to_regprocedure('public.get_editor_pokedex_position_copies(uuid, uuid, text, text, integer, integer)') is not null
                              and to_regclass('public.collection_membership_epoch') is not null
                              and exists (select 1 from pg_catalog.pg_trigger t
                                          where t.tgrelid = 'public.collection_membership'::regclass
                                            and t.tgname = 'trg_collection_membership_epoch' and t.tgenabled = 'O'),
  -- Relatório: outras sessões com trava nas 3 tabelas que a 5394 trava (NOWAIT recusa se houver conflito).
  'sessoes_com_trava',        (select count(distinct l.pid) from pg_catalog.pg_locks l
                               where l.pid <> pg_catalog.pg_backend_pid()
                                 and l.relation in ('public.collection_allocation'::regclass, 'public.collection_pokedex_position_assignment'::regclass,
                                                    'public.collection_pokedex_position_primary_representative'::regclass)),
  'gatilhos_existentes',      (select coalesce(string_agg(c.relname || '.' || t.tgname, ', ' order by c.relname, t.tgname), '')
                               from pg_catalog.pg_trigger t join pg_catalog.pg_class c on c.oid = t.tgrelid
                               where not t.tgisinternal
                                 and t.tgrelid in ('public.collection_allocation'::regclass, 'public.collection_pokedex_position_assignment'::regclass,
                                                   'public.collection_pokedex_position_primary_representative'::regclass)),
  'escritores_atribuicao',    (select coalesce(string_agg(p.proname, ', ' order by p.proname), '')
                               from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                               where n.nspname = 'public' and p.prosrc ~* '(insert\s+into|delete\s+from|update)\s+public\.collection_pokedex_position_assignment\y'),
  'escritores_representante', (select coalesce(string_agg(p.proname, ', ' order by p.proname), '')
                               from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                               where n.nspname = 'public' and p.prosrc ~* '(insert\s+into|delete\s+from|update)\s+public\.collection_pokedex_position_primary_representative\y'),
  'escritores_md5',           (select md5(string_agg(p.proname || ':' || md5(p.prosrc), ';' order by p.proname, p.oid))
                               from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                               where n.nspname = 'public'
                                 and p.proname in ('allocate_physical_cards_to_collection', 'deallocate_physical_cards_from_collection',
                                                   'auto_assign_pokedex_position_species_match', 'set_pokedex_position_assignment',
                                                   'remove_pokedex_position_assignment', 'set_pokedex_position_primary_representative',
                                                   'clear_pokedex_position_primary_representative', 'editor_set_pokedex_position_assignment',
                                                   'editor_remove_pokedex_position_assignment', 'editor_set_pokedex_position_primary_representative',
                                                   'editor_clear_pokedex_position_primary_representative')),
  'privilegios_observaveis',  (select jsonb_build_object('rolsuper', r.rolsuper, 'rolbypassrls', r.rolbypassrls) from pg_catalog.pg_roles r where r.rolname = current_user)
) as s4a_5394_pre;
