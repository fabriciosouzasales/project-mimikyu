/*
V1-13 · E3-6 / S2 — 5391: PRE SOMENTE LEITURA (um SELECT). Só catálogo e contagens;
nenhum dado de usuário, segredo ou identificador. PASS = todos os booleanos de primeiro
nível true; "escritores_*", "participacoes" e "privilegios_observaveis" são relatório
(premissa de serialização da S2 §3.5). Executar pelo executor por arquivo (STD-005 §3),
modo gate, com o mesmo papel que aplicará a migration.
*/

select jsonb_build_object(
  'executor',               current_user,
  'barreira',               (select s.mode from public.v1_13_barrier_state s where s.id = 1),
  'identidades_teste',      (select count(*) from public.v1_13_barrier_identity),
  'barreira_canonica',      (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_assert_capability()')) = 'e4f710904f50e6e8c3f1d8e2337639e0'
                            and (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_capability_open()')) = '32e2f636361732b497e8401e50f0bbe0',
  'pgcrypto_extensions',    to_regprocedure('extensions.hmac(bytea, bytea, text)') is not null
                            and to_regprocedure('extensions.gen_random_bytes(integer)') is not null,
  'participacao_canonica',  (select bool_and(x.ok) from (values
                               ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.invite_collection_member(uuid, text, text)')) = '5a5ea20616ded5b1a8e8bfe0487743ff'),
                               ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_collection_member_role(uuid, uuid, text)')) = '840d1e5c3cc55f253a2579eda7b7703d'),
                               ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.respond_collection_invite(uuid, boolean)')) = '08f28dcd1bce04bcf50ad2077bddeaa7'),
                               ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.remove_collection_member(uuid, uuid)')) = '2c267678b7ff711fb47d8f6b2ee8071a'),
                               ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.leave_shared_collection(uuid)')) = 'da8aeedd4a155794e794757590d86f62'),
                               ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.collection_member_role(uuid)')) = '1e90ce8a9f4d88c067e9125bf602eff8')) x(ok)),
  'membership_sem_gatilho', not exists (select 1 from pg_catalog.pg_trigger t where t.tgrelid = 'public.collection_membership'::regclass and not t.tgisinternal),
  'pode_travar_membership', pg_catalog.has_table_privilege(current_user, 'public.collection_membership', 'UPDATE')
                            or pg_catalog.has_table_privilege(current_user, 'public.collection_membership', 'DELETE')
                            or pg_catalog.has_table_privilege(current_user, 'public.collection_membership', 'TRUNCATE'),
  'executor_dono_membership', (select pg_catalog.pg_has_role(current_user, c.relowner, 'MEMBER') from pg_catalog.pg_class c where c.oid = 'public.collection_membership'::regclass),
  'dependencias_pokedex',   to_regclass('public.collection_pokedex_position_assignment') is not null
                            and to_regclass('public.collection_pokedex_position_primary_representative') is not null
                            and to_regclass('public.card_primary_species') is not null
                            and to_regclass('public.collection_pokedex_scope_generation') is not null,
  'indices_caminho',        to_regclass('public.ix_collection_allocation_collection') is not null
                            and to_regclass('public.idx_collection_pokedex_position_assignment_position_id') is not null,
  'ausente_5391',           to_regclass('public.collection_membership_epoch') is null
                            and to_regclass('public.collection_membership_epoch_seq') is null
                            and to_regclass('public.v1_13_copy_token_secret') is null
                            and not exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                                            where n.nspname = 'public' and p.proname in ('get_editor_pokedex_position_copies', 'v1_13_editor_membership',
                                                                                         'v1_13_pokedex_copy_token', 'collection_membership_epoch_touch')),
  -- Relatório: escritores das tabelas da Pokédex (premissa "todo escritor trava a coleção primeiro", S2 §3.5).
  'escritores_atribuicao',  (select coalesce(string_agg(p.proname, ', ' order by p.proname), '')
                             from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                             where n.nspname = 'public' and p.prosrc ~* '(insert\s+into|delete\s+from|update)\s+public\.collection_pokedex_position_assignment\y'),
  'escritores_representante', (select coalesce(string_agg(p.proname, ', ' order by p.proname), '')
                             from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                             where n.nspname = 'public' and p.prosrc ~* '(insert\s+into|delete\s+from|update)\s+public\.collection_pokedex_position_primary_representative\y'),
  'participacoes',          (select count(*) from public.collection_membership),
  'privilegios_observaveis', (select jsonb_build_object('rolsuper', r.rolsuper, 'rolbypassrls', r.rolbypassrls)
                              from pg_catalog.pg_roles r where r.rolname = current_user)
) as s2_5391_pre;
