/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5237 / R1-pré — Pré-checagem SOMENTE LEITURA no LIVE
Versão......: 1.2 (2026-10-23, CORRECTION-02: PRE-4 só exige BYPASSRLS)
Status......: PREPARADO — NÃO EXECUTADO.
Executar....: com o MESMO papel que aplicará a 5237 (esperado `postgres`),
              cada bloco inteiro, dentro de `begin transaction read only; … rollback;`.
Nada aqui escreve: só catálogo, contagens e hash de texto de políticas.
================================================================
*/

begin transaction read only;

-- PRE-1 — Ledger: 5231–5236 aplicadas; 5237 ainda não ---------------------------------
select
  (select count(*) from supabase_migrations.schema_migrations m
    where m.name in ('5231_create_binder_slot_image_bucket_and_policies',
                     '5232_create_collection_layout_slot_image_table',
                     '5233_create_binder_slot_image_write_functions',
                     '5234_create_binder_slot_image_read_functions',
                     '5235_update_remove_layout_page_for_custom_images',
                     '5236_update_binder_dismantle_for_custom_images')) = 6 as p1_package_applied,
  not exists (select 1 from supabase_migrations.schema_migrations m
               where m.name like '5237%') as p1_5237_absent;

-- PRE-2 — A política a corrigir é a da 5231 (subconsulta autorreferente) -------------
select p.policyname, p.cmd, p.roles,
       p.with_check like '%count(%'           as has_count_subquery,
       p.with_check like '%storage.objects%'  as self_reference,
       p.with_check like '%550%'              as has_cap_550,
       p.with_check like '%foldername%'       as has_folder_check,
       md5(p.with_check)                      as with_check_md5
from pg_policies p
where p.schemaname = 'storage' and p.tablename = 'objects'
  and p.policyname = 'binder_slot_image_insert_own';
-- PASS: 1 linha, cmd INSERT, roles {authenticated}, as quatro colunas booleanas true.

-- PRE-3 — Objeto novo ainda não existe; dependências presentes -----------------------
select
  to_regprocedure('public.binder_slot_image_under_object_cap()') is null as p3_function_absent,
  exists (select 1 from storage.buckets b where b.id = 'binder-slot-image')   as p3_bucket_present,
  to_regprocedure('public.list_my_unlinked_binder_slot_images(integer)') is not null as p3_5234_present;

-- PRE-4 — Papel: BYPASSRLS (sem ele a função recorreria) -----------------------------
-- CORRECTION-02: sem exigência de vínculo com o dono de storage.objects
-- (supabase_storage_admin). As políticas binder_slot_image_* já criadas por este papel
-- são evidência de compatibilidade (não prova de autorização para ALTER POLICY).
select r.rolname, r.rolsuper, r.rolbypassrls,
       (select count(*) from pg_policies p
         where p.schemaname = 'storage' and p.tablename = 'objects'
           and p.policyname like 'binder\_slot\_image\_%') as binder_policies_existing
from pg_roles r where r.rolname = current_user;
-- PASS: rolbypassrls ou rolsuper. binder_policies_existing = 3 é só evidência registrada.

-- PRE-5 — Linha de base (o POST-2 compara campo a campo) -----------------------------
select
  (select count(*) from storage.objects o where o.bucket_id = 'binder-slot-image') as objects_in_bucket,
  (select count(*) from public.collection_layout_slot_image)                        as images,
  (select count(*) from pg_policies p where p.schemaname = 'storage' and p.tablename = 'objects') as storage_object_policies,
  -- Todas as políticas de storage.objects EXCETO a corrigida: nome, comando, papéis, USING e WITH CHECK.
  md5(coalesce((select string_agg(p.policyname || '|' || p.cmd || '|' || p.roles::text || '|' ||
                                  coalesce(p.qual, '') || '|' || coalesce(p.with_check, ''), E'\n' order by p.policyname)
                from pg_policies p
                where p.schemaname = 'storage' and p.tablename = 'objects'
                  and p.policyname <> 'binder_slot_image_insert_own'), '')) as fp_other_storage_policies,
  (select b.public::text || '|' || b.file_size_limit::text || '|' || b.allowed_mime_types::text
     from storage.buckets b where b.id = 'binder-slot-image') as bucket_config;
-- Esperado hoje: objects_in_bucket 0, images 0, storage_object_policies 24,
-- bucket_config 'false|524288|{image/webp,image/jpeg}'.

-- PRE-6 — Janela: nenhuma transação longa nem trava em storage.objects --------------
select a.pid, a.usename, a.state, now() - a.xact_start as xact_age, l.mode, l.granted
from pg_locks l
join pg_stat_activity a on a.pid = l.pid
where l.relation = 'storage.objects'::regclass and a.pid <> pg_backend_pid();
-- PASS: nenhuma linha com xact_age > 1 min. ALTER POLICY pede trava exclusiva breve
-- de storage.objects (envios de capas/avatares esperam milissegundos).

rollback;
