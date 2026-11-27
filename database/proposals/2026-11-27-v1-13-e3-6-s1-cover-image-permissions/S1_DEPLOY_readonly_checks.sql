/*
V1-13 · E3-6 / S1 — implantação controlada da 5390: verificações SOMENTE LEITURA.
Cada bloco é uma única instrução SELECT; nada é escrito, nenhum modo da barreira é
alterado, nenhum arquivo do Storage é tocado, nenhum nome de arquivo ou usuário é
devolvido (só contagens). Executar com o mesmo papel que aplicará a migration.

PRE  — antes da autorização de aplicar. PASS = todos os booleanos de PRIMEIRO NÍVEL true e
       "acl_i1_inesperado" vazio. Os itens "arquivos_*" são CLASSIFICAÇÃO (relatório),
       não bloqueiam por si (ver README §"Arquivos históricos"). O objeto
       "privilegios_observaveis" é relatório (esperado hoje: membro_dono_objects = false).
       "precedente_5377_mesmo_papel" é evidência histórica, NÃO prova de autorização para
       DROP POLICY (PRECHECK CORRECTION-01, README §10.4).
POST — depois da 5390 aplicada. PASS = todos os itens booleanos true; "acl_i1" só
       com o dono; "keep_policies_md5" igual ao do PRE.
*/

-- PRE ---------------------------------------------------------------------------------------
select jsonb_build_object(
  'executor',               current_user,
  'dono_i1',                (select pg_catalog.pg_get_userbyid(p.proowner) from pg_catalog.pg_proc p
                              where p.oid = to_regprocedure('public.editor_set_collection_cover_logo(uuid, text)')),
  'executor_e_dono_i1',     current_user = (select pg_catalog.pg_get_userbyid(p.proowner) from pg_catalog.pg_proc p
                              where p.oid = to_regprocedure('public.editor_set_collection_cover_logo(uuid, text)')),
  -- PRECHECK CORRECTION-01: o antigo `pode_alterar_objects` (pertencer ao dono de storage.objects)
  -- foi removido — é o mesmo critério removido da 5237 (2026-10-23, CORRECTION-02) e é falso neste
  -- canal, embora este papel tenha criado as 3 políticas da 5377 (E1 R1, 2026-11-18). Três itens:
  -- (a) relatório de privilégios observáveis — não é critério, não prova DDL;
  'privilegios_observaveis', (select jsonb_build_object(
                                'rolsuper', r.rolsuper, 'rolbypassrls', r.rolbypassrls,
                                'dono_objects', (select pg_catalog.pg_get_userbyid(c.relowner) from pg_catalog.pg_class c where c.oid = 'storage.objects'::regclass),
                                'membro_dono_objects', pg_catalog.pg_has_role(current_user, (select c.relowner from pg_catalog.pg_class c where c.oid = 'storage.objects'::regclass), 'MEMBER'),
                                'update', pg_catalog.has_table_privilege(current_user, 'storage.objects', 'UPDATE'),
                                'delete', pg_catalog.has_table_privilege(current_user, 'storage.objects', 'DELETE'),
                                'truncate', pg_catalog.has_table_privilege(current_user, 'storage.objects', 'TRUNCATE'),
                                'maintain', pg_catalog.has_table_privilege(current_user, 'storage.objects', 'MAINTAIN'))
                              from pg_catalog.pg_roles r where r.rolname = current_user),
  -- (b) critério demonstrável: LOCK TABLE … ACCESS EXCLUSIVE exige UPDATE, DELETE, TRUNCATE ou MAINTAIN (PG 17);
  'pode_travar_objects',    pg_catalog.has_table_privilege(current_user, 'storage.objects', 'UPDATE')
                            or pg_catalog.has_table_privilege(current_user, 'storage.objects', 'DELETE')
                            or pg_catalog.has_table_privilege(current_user, 'storage.objects', 'TRUNCATE')
                            or pg_catalog.has_table_privilege(current_user, 'storage.objects', 'MAINTAIN'),
  -- (c) EVIDÊNCIA HISTÓRICA, não garantia: os 2 ajudantes, criados na MESMA transação da 5377 que criou as
  --     3 políticas a remover, pertencem ao executor atual — o papel que fez CREATE POLICY em storage.objects
  --     por este canal é o mesmo. DROP POLICY exige ser dono da tabela; nenhum booleano de catálogo prova isso.
  --     Se recusado, a transação da 5390 aborta inteira (nada persiste) → STOP, sem repetição.
  'precedente_5377_mesmo_papel', (select count(*) = 2 and bool_and(p.proowner = (select r.oid from pg_catalog.pg_roles r where r.rolname = current_user))
                              from pg_catalog.pg_proc p
                              where p.oid in (to_regprocedure('public.collection_cover_editor_folder_ok(text)'),
                                              to_regprocedure('public.collection_cover_editor_can_upload(text)'))),
  'barreira',               (select s.mode from public.v1_13_barrier_state s where s.id = 1),
  'identidades_teste',      (select count(*) from public.v1_13_barrier_identity),
  'md5_i1',                 (select md5(p.prosrc) = '8d211f8fa20bb064fc7085038281ab24' from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_set_collection_cover_logo(uuid, text)')),
  'md5_folder_ok',          (select md5(p.prosrc) = '5e9fdc4b2dec92663594ddd2cc427711' from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.collection_cover_editor_folder_ok(text)')),
  'md5_can_upload',         (select md5(p.prosrc) = 'abce88d6802c00982735bc286a3edfc3' from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.collection_cover_editor_can_upload(text)')),
  'politicas_editor_3',     (select count(*) = 3 from pg_catalog.pg_policies p where p.schemaname = 'storage' and p.tablename = 'objects'
                              and p.policyname in ('collection_cover_insert_editor', 'collection_cover_select_editor', 'collection_cover_delete_editor')
                              and p.roles = array['authenticated']::name[]),
  'politicas_dono_e_5329',  (select count(*) = 5 from pg_catalog.pg_policies p where p.schemaname = 'storage' and p.tablename = 'objects'
                              and p.policyname in ('collection_cover_select_own', 'collection_cover_insert_own', 'collection_cover_update_own',
                                                   'collection_cover_delete_own', 'collection_cover_select_shared')),
  'keep_policies_md5',      (select md5(string_agg(p.policyname || '|' || p.cmd || '|' || array_to_string(p.roles, ',') || '|' ||
                                                   coalesce(p.qual, '') || '|' || coalesce(p.with_check, ''), E'\n' order by p.policyname))
                              from pg_catalog.pg_policies p where p.schemaname = 'storage' and p.tablename = 'objects'
                              and p.policyname in ('collection_cover_select_own', 'collection_cover_insert_own', 'collection_cover_update_own',
                                                   'collection_cover_delete_own', 'collection_cover_select_shared')),
  'ajudantes_so_politicas', not exists (select 1 from pg_catalog.pg_depend d
                              where d.refclassid = 'pg_catalog.pg_proc'::regclass
                                and d.refobjid in (to_regprocedure('public.collection_cover_editor_folder_ok(text)'),
                                                   to_regprocedure('public.collection_cover_editor_can_upload(text)'))
                                and not (d.classid = 'pg_catalog.pg_policy'::regclass
                                         and d.objid in (select pol.oid from pg_catalog.pg_policy pol where pol.polrelid = 'storage.objects'::regclass
                                                         and pol.polname in ('collection_cover_insert_editor', 'collection_cover_select_editor', 'collection_cover_delete_editor')))),
  'ajudantes_sem_outras_refs', not exists (select 1 from pg_catalog.pg_proc p
                              where p.prokind = 'f'
                                and p.oid not in (to_regprocedure('public.collection_cover_editor_folder_ok(text)'), to_regprocedure('public.collection_cover_editor_can_upload(text)'))
                                and (p.prosrc like '%collection_cover_editor_folder_ok%' or p.prosrc like '%collection_cover_editor_can_upload%')),
  'acl_i1',                 (select coalesce(string_agg(coalesce(r.rolname, 'PUBLIC') || '=' || a.privilege_type, ', ' order by coalesce(r.rolname, 'PUBLIC'), a.privilege_type), '<vazio>')
                              from pg_catalog.pg_proc p cross join lateral pg_catalog.aclexplode(p.proacl) a
                              left join pg_catalog.pg_roles r on r.oid = a.grantee
                              where p.oid = to_regprocedure('public.editor_set_collection_cover_logo(uuid, text)')),
  'acl_i1_inesperado',      (select coalesce(string_agg(coalesce(r.rolname, 'PUBLIC'), ', '), '')
                              from pg_catalog.pg_proc p cross join lateral pg_catalog.aclexplode(p.proacl) a
                              left join pg_catalog.pg_roles r on r.oid = a.grantee
                              where p.oid = to_regprocedure('public.editor_set_collection_cover_logo(uuid, text)')
                                and a.privilege_type = 'EXECUTE' and a.grantee <> p.proowner
                                and coalesce(r.rolname, 'PUBLIC') not in ('authenticated', 'service_role')),
  'herdeiros_dono_i1',      (select coalesce(string_agg(r.rolname, ', ' order by r.rolname), '')
                              from pg_catalog.pg_roles r
                              where r.oid <> (select p.proowner from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_set_collection_cover_logo(uuid, text)'))
                                and pg_catalog.pg_has_role(r.oid, (select p.proowner from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_set_collection_cover_logo(uuid, text)')), 'USAGE')),
  'md5_titular_e_e33',      (select bool_and(x.ok) from (values
                               ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_my_collection_cover_logo(uuid, text)')) = '5868fb1c8de760787d1128ac20a09507'),
                               ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_my_collection_cover_finish(uuid, text)')) = '4f48d9161b4a29ecb23e7443e31d1806'),
                               ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_my_collection_cover_code(uuid, text)')) = 'd0d8cbfa517b9da3728a55af47de21cb'),
                               ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.update_collection_metadata(uuid, text, text)')) = 'a581235db9cabaf7043707a290f963b7'),
                               ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_update_collection_metadata(uuid, text, text)')) = '81da7a37d4b9d126a565074b706aaea8'),
                               ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_set_collection_cover_finish(uuid, text)')) = '8fc815a4ff48f5a7896e84ad367e86c3'),
                               ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_set_collection_cover_code(uuid, text)')) = '4feb35ab58042b11aa1df00c329f379b'),
                               ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.assert_collection_editor(uuid)')) = '9a7482588b5c7995f40a5d945c957f31')) x(ok)),
  -- Arquivos históricos do bucket (só contagens; nada é alterado).
  'arquivos_total',         (select count(*) from storage.objects o where o.bucket_id = 'collection-cover'),
  'arquivos_dono_comprovado', (select count(*) from storage.objects o where o.bucket_id = 'collection-cover'
                              and coalesce(o.owner_id, o.owner::text) = (storage.foldername(o.name))[1]),
  'arquivos_terceiros',     (select count(*) from storage.objects o where o.bucket_id = 'collection-cover'
                              and coalesce(o.owner_id, o.owner::text) is not null
                              and coalesce(o.owner_id, o.owner::text) <> (storage.foldername(o.name))[1]),
  'arquivos_sem_titularidade', (select count(*) from storage.objects o where o.bucket_id = 'collection-cover'
                              and coalesce(o.owner_id, o.owner::text) is null),
  'capas_atuais_de_terceiros', (select count(*) from public.collection c join storage.objects o
                              on o.bucket_id = 'collection-cover' and o.name = c.cover_logo_path
                              where coalesce(o.owner_id, o.owner::text) is distinct from c.owner_user_id::text),
  'i1_presente',            to_regprocedure('public.editor_set_collection_cover_logo(uuid, text)') is not null
) as s1_pre;

-- POST --------------------------------------------------------------------------------------
select jsonb_build_object(
  'politicas_editor_ausentes', not exists (select 1 from pg_catalog.pg_policies p where p.schemaname = 'storage' and p.tablename = 'objects'
                                 and p.policyname like 'collection_cover_%' and p.policyname like '%editor%'),
  'ajudantes_ausentes',     to_regprocedure('public.collection_cover_editor_folder_ok(text)') is null
                            and to_regprocedure('public.collection_cover_editor_can_upload(text)') is null,
  'i1_presente_intacta',    (select md5(p.prosrc) = '8d211f8fa20bb064fc7085038281ab24' from pg_catalog.pg_proc p
                              where p.oid = to_regprocedure('public.editor_set_collection_cover_logo(uuid, text)')),
  'acl_i1',                 (select coalesce(string_agg(coalesce(r.rolname, 'PUBLIC') || '=' || a.privilege_type, ', ' order by coalesce(r.rolname, 'PUBLIC'), a.privilege_type), '<vazio>')
                              from pg_catalog.pg_proc p cross join lateral pg_catalog.aclexplode(p.proacl) a
                              left join pg_catalog.pg_roles r on r.oid = a.grantee
                              where p.oid = to_regprocedure('public.editor_set_collection_cover_logo(uuid, text)')),
  'i1_so_dono',             not exists (select 1 from pg_catalog.pg_proc p cross join lateral pg_catalog.aclexplode(p.proacl) a
                              where p.oid = to_regprocedure('public.editor_set_collection_cover_logo(uuid, text)')
                                and a.privilege_type = 'EXECUTE' and a.grantee <> p.proowner),
  'clientes_sem_execute',   not exists (select 1 from pg_catalog.pg_roles r
                              where r.rolname in ('anon', 'authenticated', 'service_role', 'authenticator')
                                and pg_catalog.has_function_privilege(r.oid, to_regprocedure('public.editor_set_collection_cover_logo(uuid, text)'), 'EXECUTE')),
  'login_sem_execute',      (select coalesce(string_agg(r.rolname, ', ' order by r.rolname), '')
                              from pg_catalog.pg_roles r
                              where r.rolcanlogin and not r.rolsuper
                                and pg_catalog.has_function_privilege(r.oid, to_regprocedure('public.editor_set_collection_cover_logo(uuid, text)'), 'EXECUTE')),
  'keep_policies_md5',      (select md5(string_agg(p.policyname || '|' || p.cmd || '|' || array_to_string(p.roles, ',') || '|' ||
                                                   coalesce(p.qual, '') || '|' || coalesce(p.with_check, ''), E'\n' order by p.policyname))
                              from pg_catalog.pg_policies p where p.schemaname = 'storage' and p.tablename = 'objects'
                              and p.policyname in ('collection_cover_select_own', 'collection_cover_insert_own', 'collection_cover_update_own',
                                                   'collection_cover_delete_own', 'collection_cover_select_shared')),
  'e33_titular_execute',    pg_catalog.has_function_privilege('authenticated', to_regprocedure('public.editor_update_collection_metadata(uuid, text, text)'), 'EXECUTE')
                            and pg_catalog.has_function_privilege('authenticated', to_regprocedure('public.editor_set_collection_cover_finish(uuid, text)'), 'EXECUTE')
                            and pg_catalog.has_function_privilege('authenticated', to_regprocedure('public.editor_set_collection_cover_code(uuid, text)'), 'EXECUTE')
                            and pg_catalog.has_function_privilege('authenticated', to_regprocedure('public.set_my_collection_cover_logo(uuid, text)'), 'EXECUTE'),
  'md5_titular_e_e33',      (select bool_and(x.ok) from (values
                               ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_my_collection_cover_logo(uuid, text)')) = '5868fb1c8de760787d1128ac20a09507'),
                               ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_update_collection_metadata(uuid, text, text)')) = '81da7a37d4b9d126a565074b706aaea8'),
                               ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_set_collection_cover_finish(uuid, text)')) = '8fc815a4ff48f5a7896e84ad367e86c3'),
                               ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_set_collection_cover_code(uuid, text)')) = '4feb35ab58042b11aa1df00c329f379b'),
                               ((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.assert_collection_editor(uuid)')) = '9a7482588b5c7995f40a5d945c957f31')) x(ok)),
  'emergency_stop_compat',  to_regprocedure('public.editor_set_collection_cover_logo(uuid, text)') is not null,
  'barreira',               (select s.mode from public.v1_13_barrier_state s where s.id = 1),
  'identidades_teste',      (select count(*) from public.v1_13_barrier_identity),
  'arquivos_total',         (select count(*) from storage.objects o where o.bucket_id = 'collection-cover')
) as s1_post;
