/*
V1-13 · E3-6 / S2 — 5391: POST SOMENTE LEITURA (um SELECT). PASS = todos os booleanos
true (inclui "epocas_completas"), barreira CLOSED e 0 identidades. Executar pelo executor
por arquivo (STD-005 §3), modo gate, depois do COMMIT confirmado.
*/

select jsonb_build_object(
  'rpc_presente',           to_regprocedure('public.get_editor_pokedex_position_copies(uuid, uuid, text, text, integer, integer)') is not null,
  'rpc_seguranca',          (select p.prosecdef and p.proconfig = array['search_path=""'] and p.provolatile = 's'
                             from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.get_editor_pokedex_position_copies(uuid, uuid, text, text, integer, integer)')),
  'rpc_so_authenticated',   pg_catalog.has_function_privilege('authenticated', to_regprocedure('public.get_editor_pokedex_position_copies(uuid, uuid, text, text, integer, integer)'), 'EXECUTE')
                            and not pg_catalog.has_function_privilege('anon', to_regprocedure('public.get_editor_pokedex_position_copies(uuid, uuid, text, text, integer, integer)'), 'EXECUTE')
                            and not pg_catalog.has_function_privilege('service_role', to_regprocedure('public.get_editor_pokedex_position_copies(uuid, uuid, text, text, integer, integer)'), 'EXECUTE'),
  'ajudantes_internos',     not exists (select 1 from pg_catalog.pg_roles x
                              cross join unnest(array[to_regprocedure('public.collection_membership_epoch_touch()'),
                                                      to_regprocedure('public.v1_13_editor_membership(uuid)'),
                                                      to_regprocedure('public.v1_13_pokedex_copy_token(uuid, uuid, bigint)')]) f(oid)
                              where x.rolname in ('anon', 'authenticated', 'service_role', 'authenticator')
                                and (f.oid is null or pg_catalog.has_function_privilege(x.oid, f.oid, 'EXECUTE'))),
  'tabelas_internas',       not exists (select 1 from pg_catalog.pg_roles x
                              cross join unnest(array['public.collection_membership_epoch', 'public.v1_13_copy_token_secret']) t(n)
                              where x.rolname in ('anon', 'authenticated', 'service_role', 'authenticator')
                                and (pg_catalog.has_table_privilege(x.oid, t.n, 'SELECT') or pg_catalog.has_table_privilege(x.oid, t.n, 'INSERT')
                                     or pg_catalog.has_table_privilege(x.oid, t.n, 'UPDATE') or pg_catalog.has_table_privilege(x.oid, t.n, 'DELETE')))
                            and (select bool_and(c.relrowsecurity) from pg_catalog.pg_class c
                                 where c.oid in (to_regclass('public.collection_membership_epoch'), to_regclass('public.v1_13_copy_token_secret'))),
  'gatilho_habilitado',     exists (select 1 from pg_catalog.pg_trigger t where t.tgrelid = 'public.collection_membership'::regclass
                                    and t.tgname = 'trg_collection_membership_epoch' and t.tgenabled = 'O'),
  'participacoes',          (select count(*) from public.collection_membership),
  'epocas',                 (select count(*) from public.collection_membership_epoch),
  'epocas_completas',       (select count(*) from public.collection_membership) = (select count(*) from public.collection_membership_epoch)
                            and not exists (select 1 from public.collection_membership m
                                            where not exists (select 1 from public.collection_membership_epoch e where e.membership_id = m.id)),
  'epocas_unicas',          (select count(*) = count(distinct e.role_epoch) from public.collection_membership_epoch e),
  'segredo_presente',       (select count(*) = 1 from public.v1_13_copy_token_secret s where s.id = 1 and octet_length(s.secret) = 32),
  'participacao_canonica',  (select bool_and(x.ok) from (values
                               ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.invite_collection_member(uuid, text, text)')) = '5a5ea20616ded5b1a8e8bfe0487743ff'),
                               ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_collection_member_role(uuid, uuid, text)')) = '840d1e5c3cc55f253a2579eda7b7703d'),
                               ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.respond_collection_invite(uuid, boolean)')) = '08f28dcd1bce04bcf50ad2077bddeaa7'),
                               ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.remove_collection_member(uuid, uuid)')) = '2c267678b7ff711fb47d8f6b2ee8071a'),
                               ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.leave_shared_collection(uuid)')) = 'da8aeedd4a155794e794757590d86f62'),
                               ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.collection_member_role(uuid)')) = '1e90ce8a9f4d88c067e9125bf602eff8')) x(ok)),
  'barreira',               (select s.mode from public.v1_13_barrier_state s where s.id = 1),
  'identidades_teste',      (select count(*) from public.v1_13_barrier_identity)
) as s2_5391_post;
