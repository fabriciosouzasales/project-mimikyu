/*
================================================================
Projeto.....: Project Mimikyu
Arquivo.....: LIVE_90 - Imagens personalizadas do bolso (5231–5236):
              pós-checagens SÓ LEITURA
Versão......: 1.0 (2026-10-23, P2-BINDER-CUSTOM-IMAGES-LIVE-READINESS-01)
Status......: PREPARADO — NÃO EXECUTADO. Executar só depois do W1 (5231→5236)
              e com autorização para a etapa R1-pós.
Classe......: R1 — mesmo regime do LIVE_00 (begin transaction read only; …
              rollback;). Deriva da Seção 0 do harness 5852 (sem criar dados).

O QUE ESTE ARQUIVO PROVA: que os objetos existem com a forma, os privilégios
e o texto esperados, e que nenhum dado de produto mudou.
O QUE ELE NÃO PROVA: que o Storage de fato recusa apagar um arquivo vinculado,
que o vínculo trava o arquivo, nem as corridas. Isso exige a prova funcional
autorizada F1–F7 do RUNBOOK-LIVE.md §7.

CRITÉRIO: POST-1 todas ok; POST-2 igual ao PRE-7 (exceto as diferenças
esperadas listadas); POST-3 seis entradas na ordem; POST-4 sem achado novo de
outra classe.
================================================================
*/

-- POST-1 — Estrutura -----------------------------------------------------------------
with f as (
  select
    to_regprocedure('public.set_my_binder_slot_image(uuid, uuid, text, smallint)')          as f_set,
    to_regprocedure('public.set_my_binder_slot_image_focus(uuid, uuid, smallint)')          as f_foc,
    to_regprocedure('public.clear_my_binder_slot_image(uuid, uuid)')                        as f_clr,
    to_regprocedure('public.get_my_collection_binder_slot_images(uuid, integer, integer)')  as f_get,
    to_regprocedure('public.get_my_binder_slot_image_summary(uuid)')                        as f_sum,
    to_regprocedure('public.list_my_unlinked_binder_slot_images(integer)')                  as f_unl,
    to_regprocedure('public.binder_slot_image_lock_target(uuid, uuid)')                     as f_lck,
    to_regprocedure('public.binder_slot_image_resolve_layout(uuid)')                        as f_res,
    to_regprocedure('public.binder_slot_image_path_is_linked(text)')                        as f_lnk,
    to_regprocedure('public.remove_layout_page(uuid)')                                      as f_rmp,
    to_regprocedure('public.preview_my_collection_binder_dismantle(uuid)')                  as f_dpv,
    to_regprocedure('public.dismantle_my_collection_binder(uuid, text)')                    as f_dis
)
select id, ok, detail from f, lateral (values
  ('Q1.01', exists (select 1 from storage.buckets b where b.id = 'binder-slot-image' and not b.public
                    and b.file_size_limit = 524288
                    and b.allowed_mime_types @> array['image/webp','image/jpeg']
                    and cardinality(b.allowed_mime_types) = 2),
            'bucket privado, 512 KB, só webp/jpeg'),
  ('Q1.02', (select count(*) from pg_policies p where p.schemaname = 'storage' and p.tablename = 'objects'
               and p.policyname in ('binder_slot_image_select_own','binder_slot_image_insert_own','binder_slot_image_delete_own')
               and p.roles = array['authenticated']::name[] and p.permissive = 'PERMISSIVE') = 3
            and not exists (select 1 from pg_policies p where p.schemaname = 'storage' and p.tablename = 'objects'
               and p.policyname like 'binder\_slot\_image\_%' and p.cmd in ('UPDATE','ALL')),
            '3 políticas só authenticated; nenhuma UPDATE/ALL'),
  ('Q1.03', exists (select 1 from pg_policies p where p.policyname = 'binder_slot_image_insert_own'
               and p.cmd = 'INSERT' and p.with_check like '%550%' and p.with_check like '%foldername%'),
            'INSERT: pasta própria, nome canônico, teto 550'),
  ('Q1.04', exists (select 1 from pg_policies p where p.policyname = 'binder_slot_image_delete_own'
               and p.cmd = 'DELETE' and p.qual like '%binder_slot_image_path_is_linked%'
               and p.qual like '%foldername%'),
            'DELETE: pasta própria E arquivo não vinculado'),
  ('Q1.05', (select q.provolatile = 'v' and q.prosecdef and q.proconfig @> array['search_path=""']
                    and has_function_privilege('authenticated', q.oid, 'EXECUTE')
                    and not has_function_privilege('anon', q.oid, 'EXECUTE')
             from pg_proc q where q.oid = f.f_lnk),
            'binder_slot_image_path_is_linked: volátil, definer, EXECUTE só authenticated'),
  ('Q1.06', (select c.relrowsecurity from pg_class c where c.oid = 'public.collection_layout_slot_image'::regclass)
            and not has_table_privilege('authenticated', 'public.collection_layout_slot_image', 'SELECT')
            and not has_table_privilege('authenticated', 'public.collection_layout_slot_image', 'INSERT')
            and not has_table_privilege('authenticated', 'public.collection_layout_slot_image', 'UPDATE')
            and not has_table_privilege('authenticated', 'public.collection_layout_slot_image', 'DELETE')
            and not has_table_privilege('anon', 'public.collection_layout_slot_image', 'SELECT'),
            'tabela com RLS e sem privilégio para a API'),
  ('Q1.07', (select count(*) from pg_constraint k where k.conrelid = 'public.collection_layout_slot_image'::regclass
               and k.conname in ('uq_collection_layout_slot_image_path','chk_collection_layout_slot_image_focal',
                                 'chk_collection_layout_slot_image_path_format','chk_collection_layout_slot_image_path_owner')) = 4
            and exists (select 1 from pg_constraint k where k.conrelid = 'public.collection_layout_slot_image'::regclass
               and k.contype = 'f' and k.confdeltype = 'r'),
            'UNIQUE/CHECKs; FK do bolso RESTRICT'),
  ('Q1.08', (select count(*) from pg_trigger t where not t.tgisinternal and t.tgenabled = 'O' and t.tgname in (
               'trg_collection_layout_slot_image_updated_at','trg_collection_layout_slot_image_integrity',
               'trg_slot_assignment_without_custom_image','trg_slot_expected_content_without_custom_image',
               'trg_slot_lock_without_custom_image','trg_region_without_custom_image')) = 6,
            '6 gatilhos criados e habilitados'),
  ('Q1.09', (select bool_and(q.prosecdef and q.proconfig @> array['search_path=""']
                             and not has_function_privilege('authenticated', q.oid, 'EXECUTE'))
             from pg_proc q join pg_namespace n on n.oid = q.pronamespace
             where n.nspname = 'public' and q.proname in (
               'set_collection_layout_slot_image_updated_at','enforce_collection_layout_slot_image_integrity',
               'enforce_slot_without_custom_image','enforce_slot_lock_without_custom_image',
               'enforce_region_without_custom_image')),
            'funções de gatilho definer, search_path vazio, sem EXECUTE para a API'),
  ('Q1.10', (select bool_and(q.prosecdef and q.proconfig @> array['search_path=""']
                             and has_function_privilege('authenticated', q.oid, 'EXECUTE')
                             and not has_function_privilege('anon', q.oid, 'EXECUTE'))
             from pg_proc q where q.oid in (f.f_set, f.f_foc, f.f_clr, f.f_get, f.f_sum, f.f_unl, f.f_rmp, f.f_dpv, f.f_dis))
            and not exists (select 1 from pg_proc q, aclexplode(q.proacl) x
                            where q.oid in (f.f_set, f.f_foc, f.f_clr, f.f_get, f.f_sum, f.f_unl, f.f_dpv, f.f_dis)
                              and x.grantee = 0)
            and not has_function_privilege('authenticated', f.f_lck, 'EXECUTE')
            and not has_function_privilege('authenticated', f.f_res, 'EXECUTE')
            and (select bool_and(q.proconfig @> array['lock_timeout=5s']) from pg_proc q where q.oid in (f.f_set, f.f_foc, f.f_clr)),
            'RPCs definer, search_path vazio, EXECUTE só authenticated; internas fechadas; lock_timeout 5s'),
  ('Q1.11', (select q.prosrc like '%for share of o%' and q.prosrc like '%metadata%'
             from pg_proc q where q.oid = f.f_set)
            and (select r.rolbypassrls or r.rolsuper from pg_proc q join pg_roles r on r.oid = q.proowner where q.oid = f.f_set)
            and has_table_privilege((select q.proowner from pg_proc q where q.oid = f.f_set), 'storage.objects', 'UPDATE'),
            'vínculo trava o objeto FOR SHARE; dono das RPCs com bypass de RLS e UPDATE em storage.objects'),
  ('Q1.12', (select q.prosrc like '%custom image(s)%' from pg_proc q where q.oid = f.f_rmp)
            and (select 'images_count' = any(q.proargnames) from pg_proc q where q.oid = f.f_dpv)
            and (select 'images_removed' = any(q.proargnames) and 'image_paths' = any(q.proargnames)
                 from pg_proc q where q.oid = f.f_dis),
            'remove_layout_page conta imagens (5235); prévia e desmontagem com colunas novas (5236)'),
  ('Q1.13', (select pg_get_function_result(f.f_dis)) like '%locks_released integer, images_removed integer, image_paths text[])'
            and (select pg_get_function_result(f.f_dpv)) like '%blocked_reason text, images_count integer)',
            'colunas antigas preservadas; novas só no fim')
) as t(id, ok, detail)
order by id;

-- POST-2 — Dados intocados (comparar com PRE-7, campo a campo) ------------------------
-- Diferenças ESPERADAS: buckets +1; storage_object_policies +3; fp_storage_policies
-- muda. TODO o resto idêntico. images = 0; objetos no bucket novo = 0.
select
  (select count(*) from public.collection)                              as collections,
  (select count(*) from public.collection_allocation)                   as allocations,
  (select count(*) from public.physical_card)                           as physical_cards,
  (select count(*) from public.collection_layout)                       as layouts,
  (select count(*) from public.collection_layout_guest)                 as guests,
  (select count(*) from public.collection_layout_page)                  as pages,
  (select count(*) from public.collection_layout_slot)                  as slots,
  (select count(*) from public.collection_layout_slot_assignment)       as assignments,
  (select count(*) from public.collection_layout_slot_expected_content) as reservations,
  (select count(*) from public.collection_layout_slot where locked)     as locked_slots,
  (select count(*) from public.collection_layout_region)                as regions,
  (select count(*) from storage.buckets)                                as buckets,
  (select count(*) from storage.objects)                                as storage_objects,
  (select count(*) from pg_policies p where p.schemaname = 'storage' and p.tablename = 'objects') as storage_object_policies,
  (select count(*) from public.collection_layout_slot_image)            as images,
  (select count(*) from storage.objects o where o.bucket_id = 'binder-slot-image') as objects_in_new_bucket;

select
  md5(coalesce((select string_agg(a.slot_id::text || ':' || a.collection_allocation_id::text, ',' order by a.slot_id)
                from public.collection_layout_slot_assignment a), '')) as fp_assignments,
  md5(coalesce((select string_agg(e.slot_id::text || ':' || e.card_id::text || ':' || coalesce(e.card_variant_id::text, '-')
                                  || ':' || coalesce(e.collection_id::text, '-'), ',' order by e.slot_id)
                from public.collection_layout_slot_expected_content e), '')) as fp_reservations,
  md5(coalesce((select string_agg(s.id::text, ',' order by s.id)
                from public.collection_layout_slot s where s.locked), '')) as fp_locked,
  md5(coalesce((select string_agg(p.layout_id::text || ':' || p.page_number::text, ',' order by p.layout_id, p.page_number)
                from public.collection_layout_page p), '')) as fp_pages,
  md5(coalesce((select string_agg(ca.id::text || ':' || ca.collection_id::text || ':' || ca.physical_card_id::text, ',' order by ca.id)
                from public.collection_allocation ca), '')) as fp_allocations,
  md5(coalesce((select string_agg(p.policyname || ':' || p.cmd, ',' order by p.policyname)
                from pg_policies p where p.schemaname = 'storage' and p.tablename = 'objects'
                  and p.policyname not like 'binder\_slot\_image\_%'), '')) as fp_storage_policies_preexisting;
-- fp_storage_policies_preexisting deve ser igual ao fp_storage_policies do PRE-7
-- (as políticas que já existiam não mudaram).

-- POST-3 — Ledger ------------------------------------------------------------------------
select version, name
from supabase_migrations.schema_migrations
where name ~ '523[1-6]_'
order by version;
-- Esperado: exatamente 6 linhas, 5231 → 5236, nessa ordem.

-- POST-4 — Advisor de segurança: rodar get_advisors(type='security') fora deste
-- arquivo e comparar com o resultado anterior ao W1. Esperado: as RPCs novas na
-- mesma classe já aceita (lint 0029, authenticated SECURITY DEFINER); nenhum
-- achado novo de outra classe.
