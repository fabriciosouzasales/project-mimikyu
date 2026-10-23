/*
================================================================
Projeto.....: Project Mimikyu
Arquivo.....: LIVE_00 - Imagens personalizadas do bolso (5231–5236):
              pré-checagens SÓ LEITURA
Versão......: 1.0 (2026-10-23, P2-BINDER-CUSTOM-IMAGES-LIVE-READINESS-01)
Status......: PREPARADO — NÃO EXECUTADO. Executar só com autorização expressa
              de Fabrício para a etapa R1-pré.
Classe......: R1 — catálogo do Postgres, catálogo do Storage (metadados,
              políticas, gatilhos) e contagens. Nenhum INSERT/UPDATE/DELETE/
              DDL, nenhuma RPC do produto, nenhum SET ROLE, nenhum acesso à
              API do Storage, nenhum arquivo criado ou apagado.

COMO EXECUTAR — um bloco por vez, com o MESMO papel que aplicará as
migrations (o do apply_migration / SQL Editor, esperado `postgres`):
    begin transaction read only;
    <bloco>
    rollback;
Guardar a saída integral (RUNBOOK-LIVE.md §8).

CRITÉRIO: qualquer ok = false em PRE-2, PRE-3, PRE-4, PRE-5 ou PRE-6 → STOP.
PRE-7 (baseline) e PRE-8 (janela) não são PASS/FAIL de conteúdo: PRE-7 é
fotografia comparada no pós; PRE-8 decide o momento.
================================================================
*/

-- PRE-1 — Identidade, versão e ledger ------------------------------------------------
select current_database() as db, current_user as usr, session_user as sess,
       version() as pg, now() as at;

select version, name
from supabase_migrations.schema_migrations
order by version desc
limit 12;
-- Esperado: 5229/5230 (fichário compartilhado) presentes como as mais recentes do
-- recurso; nenhuma entrada 5231–5236.
select 'P1.1' as id,
       not exists (select 1 from supabase_migrations.schema_migrations m
                   where m.name ~ '^(p2[a-z_]*_)?523[1-6]_') as ok,
       'nenhuma migration 5231–5236 no ledger' as detail
union all
select 'P1.2',
       exists (select 1 from supabase_migrations.schema_migrations m where m.name like '%5229_create_collection_binder_sharing%')
       and exists (select 1 from supabase_migrations.schema_migrations m where m.name like '%5230_evolve_get_my_collection_binder_for_sharing%'),
       '5229 e 5230 aplicadas (base das 5232/5236)';

-- PRE-2 — Pacote ausente (nada de 5231–5236 existe) -----------------------------------
select id, ok, detail from (values
  ('P2.01', not exists (select 1 from storage.buckets b where b.id = 'binder-slot-image'),
            'bucket binder-slot-image ausente'),
  ('P2.02', not exists (select 1 from pg_policies p where p.schemaname = 'storage' and p.tablename = 'objects'
                        and p.policyname like 'binder\_slot\_image\_%'),
            'nenhuma política binder_slot_image_* em storage.objects'),
  ('P2.03', to_regclass('public.collection_layout_slot_image') is null,
            'tabela collection_layout_slot_image ausente'),
  ('P2.04', not exists (select 1 from pg_trigger t where not t.tgisinternal and t.tgname in (
              'trg_collection_layout_slot_image_updated_at','trg_collection_layout_slot_image_integrity',
              'trg_slot_assignment_without_custom_image','trg_slot_expected_content_without_custom_image',
              'trg_slot_lock_without_custom_image','trg_region_without_custom_image')),
            'nenhum dos 6 gatilhos novos existe'),
  ('P2.05', not exists (select 1 from pg_proc q join pg_namespace n on n.oid = q.pronamespace
                        where n.nspname = 'public' and q.proname in (
              'set_collection_layout_slot_image_updated_at','enforce_collection_layout_slot_image_integrity',
              'enforce_slot_without_custom_image','enforce_slot_lock_without_custom_image',
              'enforce_region_without_custom_image','binder_slot_image_path_is_linked',
              'binder_slot_image_lock_target','set_my_binder_slot_image','set_my_binder_slot_image_focus',
              'clear_my_binder_slot_image','binder_slot_image_resolve_layout',
              'get_my_collection_binder_slot_images','get_my_binder_slot_image_summary',
              'list_my_unlinked_binder_slot_images')),
            'nenhuma das 14 funções novas existe (qualquer assinatura)'),
  ('P2.06', not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                        where n.nspname = 'public' and c.relname in (
              'ix_collection_layout_slot_image_owner','uq_collection_layout_slot_image_path')),
            'índices novos ausentes')
) as t(id, ok, detail)
order by id;

-- PRE-3 — Dependências do banco que as migrations usam --------------------------------
select id, ok, detail from (values
  ('P3.01', to_regprocedure('public.assert_collection_layout_mutable(uuid)') is not null
            and to_regprocedure('public.remove_layout_page(uuid)') is not null
            and to_regprocedure('public.preview_my_collection_binder_dismantle(uuid)') is not null
            and to_regprocedure('public.dismantle_my_collection_binder(uuid, text)') is not null
            and to_regprocedure('public.collection_binder_dismantle_snapshot(uuid)') is not null
            and to_regprocedure('public.assign_card_to_slot(uuid, uuid)') is not null
            and to_regprocedure('public.set_slot_expected_content(uuid, uuid, uuid, uuid, uuid)') is not null
            and to_regprocedure('public.set_slot_lock(uuid[], boolean)') is not null
            and to_regprocedure('public.merge_layout_region(uuid, integer, integer, integer, integer)') is not null,
            'funções existentes que as novas usam ou cujo comportamento é estendido'),
  ('P3.02', to_regclass('public.collection_layout_guest') is not null
            and to_regclass('public.collection_layout_region') is not null
            and (select count(*) from information_schema.columns where table_schema = 'public'
                   and table_name = 'collection_layout_region'
                   and column_name in ('page_id','top_row','left_column','height','width')) = 5
            and (select count(*) from information_schema.columns where table_schema = 'public'
                   and table_name = 'collection_layout_slot'
                   and column_name in ('id','page_id','row_index','column_index','locked')) = 5
            and (select count(*) from information_schema.columns where table_schema = 'public'
                   and table_name = 'collection' and column_name in ('owner_user_id','lifecycle_status')) = 2,
            'tabelas e colunas lidas pelos gatilhos e RPCs novos'),
  ('P3.03', to_regprocedure('storage.foldername(text)') is not null
            and to_regprocedure('auth.uid()') is not null
            and to_regprocedure('pg_catalog.hashtextextended(text, bigint)') is not null,
            'storage.foldername, auth.uid e hashtextextended disponíveis'),
  ('P3.04', (select count(*) from information_schema.columns where table_schema = 'storage'
               and table_name = 'objects'
               and column_name in ('bucket_id','name','owner','owner_id','metadata','created_at')) = 6
            and (select count(*) from information_schema.columns where table_schema = 'storage'
               and table_name = 'buckets'
               and column_name in ('id','name','public','file_size_limit','allowed_mime_types')) = 5,
            'colunas do Storage usadas por 5231/5233/5234'),
  ('P3.05', exists (select 1 from pg_constraint k
                    where k.conrelid = 'storage.objects'::regclass and k.contype in ('u','p')
                      and pg_get_constraintdef(k.oid) ilike '%bucket_id%name%')
            or exists (select 1 from pg_index i
                       join pg_class c on c.oid = i.indexrelid
                       where i.indrelid = 'storage.objects'::regclass and i.indisunique
                         and pg_get_indexdef(i.indexrelid) ilike '%bucket_id%name%'),
            'unicidade (bucket_id, name) em storage.objects — base do "arquivo novo, nunca sobrescrito"')
) as t(id, ok, detail)
order by id;

-- PRE-4 — Corpos vivos que 5235/5236 substituem (marcadores = critério; md5 informativo)
-- md5 do corpo canônico em database/schema (LF):
--   5126 remove_layout_page                      c3ab5b0650ce9d161a0b7b8b7f673e45
--   5229 preview_my_collection_binder_dismantle  2b9ba43855d79151f3da3866a2ef40fa
--   5229 dismantle_my_collection_binder          4d87b112022329860cea4c881eb7b376
--   5122 assert_collection_layout_mutable        d600f36fade0b67c0fd5af33e9965070
select v.id,
       coalesce(p.oid is not null
                and position(v.must in p.prosrc) > 0
                and position(v.mustnot in p.prosrc) = 0
                and p.prosecdef
                and p.proconfig @> array['search_path=""'], false) as ok,
       md5(p.prosrc) as md5_live,
       v.md5_canon,
       v.detail
from (values
  ('P4.1', 'public.remove_layout_page(uuid)', 'layout region(s)', 'custom image',
           'c3ab5b0650ce9d161a0b7b8b7f673e45', '5126 sem contagem de imagens'),
  ('P4.2', 'public.preview_my_collection_binder_dismantle(uuid)', 'guest_count', 'images_count',
           '2b9ba43855d79151f3da3866a2ef40fa', '5229 prévia sem imagens'),
  ('P4.3', 'public.dismantle_my_collection_binder(uuid, text)', 'BINDER_HAS_GUESTS', 'image_paths',
           '4d87b112022329860cea4c881eb7b376', '5229 desmontagem sem imagens'),
  ('P4.4', 'public.assert_collection_layout_mutable(uuid)', 'FOR UPDATE', 'collection_layout_slot_image',
           'd600f36fade0b67c0fd5af33e9965070', '5122 trava proprietária → fichário')
) as v(id, sig, must, mustnot, md5_canon, detail)
left join pg_proc p on p.oid = to_regprocedure(v.sig)
order by v.id;

select 'P4.5' as id,
       pg_get_function_result(to_regprocedure('public.preview_my_collection_binder_dismantle(uuid)'))
         like '%blocked_reason text)' as ok_preview_tail,
       pg_get_function_result(to_regprocedure('public.dismantle_my_collection_binder(uuid, text)'))
         like '%locks_released integer)' as ok_dismantle_tail,
       'retornos atuais terminam onde a 5236 acrescenta colunas' as detail;

-- DROP+CREATE na 5236: nenhum objeto depende das duas funções.
select f.id,
       not exists (select 1 from pg_depend d
                   where d.refclassid = 'pg_catalog.pg_proc'::regclass
                     and d.refobjid = to_regprocedure(f.sig)
                     and d.deptype = 'n') as ok_no_pg_depend,
       not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                   where n.nspname not in ('pg_catalog', 'information_schema')
                     and p.oid <> to_regprocedure(f.sig)
                     and p.prosrc ilike '%' || f.name || '(%') as ok_no_sql_caller,
       f.detail
from (values
  ('P4.6', 'public.preview_my_collection_binder_dismantle(uuid)', 'preview_my_collection_binder_dismantle', 'DROP na 5236'),
  ('P4.7', 'public.dismantle_my_collection_binder(uuid, text)', 'dismantle_my_collection_binder', 'DROP na 5236')
) as f(id, sig, name, detail)
order by f.id;

-- Todos os escritores de posição/reserva/trava/mesclagem passam pela trava do
-- fichário (premissa da exclusividade). Lista as funções que escrevem nessas
-- tabelas e se chamam o helper 5122 (ou travam proprietária → layout).
select 'P4.8' as id, p.proname,
       (p.prosrc ilike '%assert_collection_layout_mutable%'
        or (p.prosrc ilike '%collection_layout l%for update%')) as uses_layout_lock,
       p.prosrc ilike '%collection_layout_slot_assignment%' as w_assignment,
       p.prosrc ilike '%collection_layout_slot_expected_content%' as w_reservation,
       p.prosrc ilike '%set locked%' as w_lock,
       p.prosrc ilike '%insert into public.collection_layout_region%' as w_region
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.prokind = 'f'
  and (p.prosrc ~* '(insert into|update|delete from)\s+public\.collection_layout_slot_(assignment|expected_content)'
       or p.prosrc ~* 'update\s+public\.collection_layout_slot\s'
       or p.prosrc ~* 'insert into\s+public\.collection_layout_region')
order by p.proname;
-- Critério: toda linha com uses_layout_lock = true, EXCETO funções de gatilho e
-- os caminhos só de remoção/criação já analisados (detach 5229 — trava
-- proprietária → layout → convidada; create_my_collection_binder 5224 — fichário
-- novo). Linha inesperada com false → STOP e auditar.

-- PRE-5 — Papel que aplicará as migrations: permissões efetivas -----------------------
select 'P5.1' as id,
       r.rolname, r.rolsuper, r.rolbypassrls, r.rolcreaterole,
       has_table_privilege(current_user, 'storage.objects', 'SELECT') as obj_select,
       has_table_privilege(current_user, 'storage.objects', 'INSERT') as obj_insert,
       has_table_privilege(current_user, 'storage.objects', 'UPDATE') as obj_update,
       has_table_privilege(current_user, 'storage.objects', 'DELETE') as obj_delete,
       has_table_privilege(current_user, 'storage.buckets', 'INSERT') as bkt_insert,
       has_schema_privilege(current_user, 'storage', 'USAGE') as storage_usage,
       pg_get_userbyid(c.relowner) as objects_owner,
       pg_has_role(current_user, c.relowner, 'MEMBER') as member_of_objects_owner
from pg_roles r, pg_class c
where r.rolname = current_user and c.oid = 'storage.objects'::regclass;
-- Critério (STOP se qualquer um falhar):
--   rolbypassrls = true OU rolsuper = true — OBRIGATÓRIO. As RPCs (dono = este
--     papel) leem storage.objects e o travam FOR SHARE; FOR SHARE sob RLS exige
--     também política de UPDATE, que o bucket NÃO tem por desenho. Sem bypass,
--     todo vínculo falharia com IMAGE_FILE_NOT_FOUND.
--   obj_select, obj_update (FOR SHARE), bkt_insert (5231) = true.
--   member_of_objects_owner = true OU P5.2 = true (CREATE POLICY exige dono).

select 'P5.2' as id,
       (select count(*) from pg_policies p where p.schemaname = 'storage' and p.tablename = 'objects'
          and p.policyname like 'collection\_cover\_%') = 4 as ok,
       'precedente: as 4 políticas collection_cover_* (5176) foram criadas no LIVE pelo mesmo caminho' as detail;

select 'P5.3' as id,
       (select q.prosecdef and pg_get_userbyid(q.proowner) = current_user
          from pg_proc q where q.oid = to_regprocedure('public.set_my_collection_cover_logo(uuid, text)')) as ok,
       'precedente: 5178 (lê storage.objects como definer) pertence ao mesmo papel' as detail;

-- PRE-6 — Storage: políticas, RLS, gatilhos (compatibilidade da proteção) ------------
-- 6a. RLS ligada em storage.objects (sem ela, nenhuma política protege nada).
select 'P6.1' as id,
       c.relrowsecurity as ok, c.relforcerowsecurity as force_rls,
       'RLS ligada em storage.objects' as detail
from pg_class c where c.oid = 'storage.objects'::regclass;

-- 6b. CRÍTICO: políticas existentes que NÃO restringem bucket. Políticas
-- PERMISSIVE combinam por OR: uma política de DELETE/UPDATE/ALL sem filtro de
-- bucket deixaria apagar ou sobrescrever arquivo vinculado, anulando a 5232.
select 'P6.2' as id, p.policyname, p.cmd, p.permissive, p.roles,
       coalesce(p.qual, '') || ' | ' || coalesce(p.with_check, '') as expr,
       (coalesce(p.qual, '') || coalesce(p.with_check, '')) ~ 'bucket_id' as mentions_bucket
from pg_policies p
where p.schemaname = 'storage' and p.tablename = 'objects'
order by p.cmd, p.policyname;

select 'P6.3' as id,
       not exists (
         select 1 from pg_policies p
         where p.schemaname = 'storage' and p.tablename = 'objects'
           and p.permissive = 'PERMISSIVE'
           and p.cmd in ('DELETE', 'UPDATE', 'ALL', 'INSERT')
           and (p.roles && array['authenticated','public','anon']::name[])
           and (coalesce(p.qual, '') || coalesce(p.with_check, '')) !~ 'bucket_id'
       ) as ok,
       'nenhuma política permissiva de escrita sem filtro de bucket (senão: STOP)' as detail;
-- Revisar também, à mão, cada linha de P6.2 que mencione bucket_id por
-- negação/lista (ex.: bucket_id <> 'x', bucket_id = any(...)) — o filtro
-- textual não distingue igualdade de desigualdade.

-- 6c. Gatilhos em storage.objects (ex.: proteção de DELETE direto, prefixos).
select 'P6.4' as id, t.tgname, t.tgenabled, pg_get_triggerdef(t.oid) as def,
       p.proname as fn, p.prosecdef,
       p.prosrc ~* 'allow_delete_query' as mentions_allow_delete_guc,
       left(regexp_replace(p.prosrc, '\s+', ' ', 'g'), 300) as fn_head
from pg_trigger t join pg_proc p on p.oid = t.tgfoid
where t.tgrelid = 'storage.objects'::regclass and not t.tgisinternal
order by t.tgname;
-- Informativo: registra o comportamento real do Storage diante de DELETE em SQL.
-- Não é STOP. Se houver gatilho de proteção, o nome do GUC aparece aqui (o
-- harness 5852 depende dele; o produto não).

-- 6d. Versão do Storage (migrações internas) — informativo.
select 'P6.5' as id, name, executed_at
from storage.migrations
order by id desc
limit 5;

-- 6e. Bucket precedente com a mesma forma (privado, limites, sem anon).
select 'P6.6' as id, b.id as bucket, b.public, b.file_size_limit, b.allowed_mime_types
from storage.buckets b
where b.id in ('collection-cover', 'avatars', 'card-front', 'card-set-logo', 'expansion-logo')
order by b.id;

-- PRE-7 — Baseline de integridade (comparado campo a campo no POST-2) -----------------
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
  (select count(*) from pg_policies p where p.schemaname = 'storage' and p.tablename = 'objects') as storage_object_policies;

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
                from pg_policies p where p.schemaname = 'storage' and p.tablename = 'objects'), '')) as fp_storage_policies;

-- PRE-8 — Janela: sessões e travas -----------------------------------------------------
-- 5231 e 5232 fazem CREATE POLICY em storage.objects (trava exclusiva da tabela,
-- breve) e 5232 cria gatilhos em quatro tabelas do fichário. Uma transação longa
-- nessas tabelas faria a migration esperar e enfileirar o tráfego do Storage.
select a.pid, a.usename, a.application_name, a.state,
       now() - a.xact_start as xact_age, a.wait_event_type, left(a.query, 80) as query
from pg_stat_activity a
where a.datname = current_database() and a.pid <> pg_backend_pid() and a.state <> 'idle'
order by a.xact_start nulls last;

select n.nspname, c.relname, l.mode, l.granted, l.pid
from pg_locks l
join pg_class c on c.oid = l.relation
join pg_namespace n on n.oid = c.relnamespace
where ((n.nspname = 'public' and c.relname in ('collection', 'collection_layout', 'collection_layout_page',
          'collection_layout_slot', 'collection_layout_slot_expected_content',
          'collection_layout_slot_assignment', 'collection_layout_region'))
       or (n.nspname = 'storage' and c.relname in ('objects', 'buckets')))
  and l.pid <> pg_backend_pid();
