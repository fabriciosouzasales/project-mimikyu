/*
V1-13 · E3-6 / S3 — implantação controlada da 5393: verificações SOMENTE LEITURA
(antes e depois). Uma instrução SELECT por bloco; nada é escrito, nenhum modo da
barreira é alterado, nenhum dado sintético. Executar como o mesmo papel que
aplicará a migration (dono das funções da V1-12/E1).

PRE  — antes da autorização de aplicar: tudo true; barreira = CLOSED.
POST — depois da 5393 aplicada (barreira continua CLOSED): tudo true.
*/

-- PRE ---------------------------------------------------------------------------------------
select jsonb_build_object(
  'executor',            current_user,
  'dono_5315',           (select pg_catalog.pg_get_userbyid(p.proowner) from pg_catalog.pg_proc p
                           where p.oid = to_regprocedure('public.collection_binder_masked_pages(uuid, integer, integer)')),
  'executor_e_dono',     current_user = (select pg_catalog.pg_get_userbyid(p.proowner) from pg_catalog.pg_proc p
                           where p.oid = to_regprocedure('public.collection_binder_masked_pages(uuid, integer, integer)')),
  'barreira',            (select s.mode from public.v1_13_barrier_state s where s.id = 1),
  'identidades_teste',   (select count(*) from public.v1_13_barrier_identity),
  'md5_5302',            (select md5(p.prosrc) = 'efdb495b5b703e9f093eb0f49a1d0a5d' from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.collection_share_role(uuid)')),
  'md5_5315',            (select md5(p.prosrc) = 'ce559a495a49571a6598c83bc3d59202' from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.collection_binder_masked_pages(uuid, integer, integer)')),
  'md5_5316',            (select md5(p.prosrc) = '79f893c45a08909e0a61d661952ab750' from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.get_shared_collection_binder_pages(uuid, integer, integer)')),
  'md5_5318',            (select md5(p.prosrc) = '0da2d28209cd85b6bdbf6c20ae47efd6' from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.get_public_collection_binder_pages(uuid, integer, integer)')),
  'md5_5389_assert',     (select md5(p.prosrc) = 'e4f710904f50e6e8c3f1d8e2337639e0' from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_assert_capability()')),
  'md5_5389_open',       (select md5(p.prosrc) = '32e2f636361732b497e8401e50f0bbe0' from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_capability_open()')),
  'dependencias_stable', (select bool_and(p.provolatile in ('s', 'i')) and count(*) = 5 from pg_catalog.pg_proc p
                           where p.oid in (to_regprocedure('public.collection_share_role(uuid)'),
                                           to_regprocedure('public.collection_binder_masked_pages(uuid, integer, integer)'),
                                           to_regprocedure('public.v1_13_assert_capability()'),
                                           to_regprocedure('public.v1_13_capability_open()'),
                                           to_regprocedure('auth.uid()'))),
  'tabelas_5257',        to_regclass('public.collection_layout_slot_species_reference') is not null
                         and to_regclass('public.collection_layout_species_reference_setting') is not null,
  'indices_juncao',      (select count(*) = 3 from pg_catalog.pg_constraint k
                           where k.conname in ('uq_collection_layout_page_number', 'uq_collection_layout_slot_position', 'pk_cl_slot_species_reference')),
  'ausente_5393',        to_regprocedure('public.get_shared_collection_binder_pages_with_species(uuid, integer, integer)') is null
) as s3_pre;

-- POST --------------------------------------------------------------------------------------
select jsonb_build_object(
  'existe',              v.oid is not null,
  'definer_stable_sp',   (select p.prosecdef and p.provolatile = 's' and p.proconfig = array['search_path=""'] from pg_catalog.pg_proc p where p.oid = v.oid),
  'dono_igual_5315',     (select p.proowner from pg_catalog.pg_proc p where p.oid = v.oid)
                         = (select p.proowner from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.collection_binder_masked_pages(uuid, integer, integer)')),
  'exec_authenticated',  pg_catalog.has_function_privilege('authenticated', v.oid, 'EXECUTE'),
  'sem_exec_anon',       not pg_catalog.has_function_privilege('anon', v.oid, 'EXECUTE'),
  'sem_exec_public',     not exists (select 1 from pg_catalog.pg_proc p cross join lateral pg_catalog.aclexplode(p.proacl) a
                                     where p.oid = v.oid and a.grantee = 0 and a.privilege_type = 'EXECUTE'),
  'retorno_exato',       pg_catalog.pg_get_function_result(v.oid) = 'TABLE(page_number integer, row_index integer, column_index integer, pocket_state text, card_name text, collector_number text, collector_total integer, card_set_code text, variant_label text, language_code text, image_path text, species_national_number integer, species_name text, species_artwork_path text, references_visible boolean)',
  'md5_5393_igual_arquivo', (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v.oid),
  'v1_12_intacta',       (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.collection_binder_masked_pages(uuid, integer, integer)')) = 'ce559a495a49571a6598c83bc3d59202'
                         and (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.get_shared_collection_binder_pages(uuid, integer, integer)')) = '79f893c45a08909e0a61d661952ab750'
                         and (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.get_public_collection_binder_pages(uuid, integer, integer)')) = '0da2d28209cd85b6bdbf6c20ae47efd6',
  'barreira',            (select s.mode from public.v1_13_barrier_state s where s.id = 1),
  'identidades_teste',   (select count(*) from public.v1_13_barrier_identity)
) as s3_post
from (select to_regprocedure('public.get_shared_collection_binder_pages_with_species(uuid, integer, integer)') as oid) v;
-- 'md5_5393_igual_arquivo' é comparado fora do banco com o md5 do prosrc do arquivo da migration (static_check_s3.py imprime).
