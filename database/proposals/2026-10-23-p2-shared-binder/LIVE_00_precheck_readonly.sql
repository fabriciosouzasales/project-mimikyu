/*
================================================================
Projeto.....: Project Mimikyu
Arquivo.....: LIVE_00 - Fichário compartilhado (5229/5230): pré-checagens SÓ LEITURA
Versão......: 1.0 (2026-10-23, P2-SHARED-BINDER-LIVE-READINESS-01)
Status......: PREPARADO — NÃO EXECUTADO. Executar só com autorização expressa
              de Fabrício para a etapa R1-pré.
Classe......: R1 — catálogo do Postgres e contagens. Nenhum INSERT/UPDATE/
              DELETE/DDL, nenhuma RPC do produto, nenhuma função criada,
              nenhum SET ROLE.

COMO EXECUTAR — um bloco por vez:
    begin transaction read only;
    <bloco>
    rollback;
Guardar a saída integral (RUNBOOK-LIVE.md §6).

CRITÉRIO: qualquer ok = false em PRE-2, PRE-3 ou PRE-4 → STOP.
PRE-5 (inventário) e PRE-6 (sessões) são baseline / gatilho de janela.
================================================================
*/

-- PRE-1 — Identidade e ledger --------------------------------------------------------
select current_database() as db, current_user as usr, version() as pg, now() as at;

select version, name
from supabase_migrations.schema_migrations
order by version desc
limit 12;
-- Esperado: P2-A1 (5223–5228) presente; nenhuma entrada 5229/5230.

-- PRE-2 — Pacote ausente, dependências presentes -------------------------------------
select id, ok, detail from (values
  ('P2.01', to_regclass('public.collection_layout_guest') is null,
            'tabela collection_layout_guest ainda ausente'),
  ('P2.02', not exists (select 1 from information_schema.columns
                        where table_schema = 'public'
                          and table_name = 'collection_layout_slot_expected_content'
                          and column_name = 'collection_id'),
            'coluna expected_content.collection_id ainda ausente'),
  ('P2.03', not exists (select 1 from pg_trigger where not tgisinternal and tgname in (
                          'trg_collection_layout_guest_integrity','trg_collection_layout_owner_not_guest',
                          'trg_collection_layout_delete_without_guests','trg_expected_content_participant'))
            and to_regprocedure('public.enforce_collection_layout_guest_integrity()') is null
            and to_regprocedure('public.enforce_collection_layout_owner_not_guest()') is null
            and to_regprocedure('public.enforce_collection_layout_delete_without_guests()') is null
            and to_regprocedure('public.enforce_expected_content_participant()') is null,
            'gatilhos e funções de gatilho da 5229 ausentes'),
  ('P2.04', to_regprocedure('public.attach_my_collection_to_binder(uuid, uuid)') is null
            and to_regprocedure('public.collection_binder_detach_snapshot(uuid)') is null
            and to_regprocedure('public.preview_my_collection_binder_detach(uuid)') is null
            and to_regprocedure('public.detach_my_collection_from_binder(uuid, text, boolean)') is null
            and to_regprocedure('public.set_slot_expected_content(uuid, uuid, uuid, uuid, uuid)') is null,
            'RPCs novas da 5229 e assinatura de 5 args ausentes'),
  ('P2.05', to_regprocedure('public.list_my_binder_join_candidates(uuid)') is null
            and to_regprocedure('public.get_my_collection_binder_unplaced(uuid, integer, integer)') is null,
            'leituras novas da 5230 ausentes'),
  ('P2.06', to_regprocedure('public.set_slot_expected_content(uuid, uuid, uuid, uuid)') is not null
            and to_regprocedure('public.get_my_collection_binder(uuid)') is not null
            and to_regprocedure('public.get_my_collection_binder_pages(uuid, integer, integer)') is not null
            and to_regprocedure('public.preview_my_collection_binder_dismantle(uuid)') is not null
            and to_regprocedure('public.dismantle_my_collection_binder(uuid, text)') is not null
            and to_regprocedure('public.collection_binder_dismantle_snapshot(uuid)') is not null
            and to_regprocedure('public.delete_collection(uuid)') is not null
            and to_regprocedure('public.assign_card_to_slot(uuid, uuid)') is not null
            and to_regprocedure('public.assert_collection_layout_mutable(uuid)') is not null
            and to_regprocedure('public.enforce_collection_layout_slot_assignment_integrity()') is not null,
            'dependências P2-A1/Foundation presentes (5223, 5225, 5226, 5117, 5122, 5131)'),
  ('P2.07', to_regclass('public.collection_layout') is not null
            and to_regclass('public.collection_layout_slot_assignment') is not null
            and to_regclass('public.collection_layout_slot_expected_content') is not null
            and to_regclass('public.storage_container') is not null
            and exists (select 1 from information_schema.columns where table_schema = 'public'
                        and table_name = 'storage_container' and column_name = 'kind_code')
            and exists (select 1 from information_schema.columns where table_schema = 'public'
                        and table_name = 'collection' and column_name = 'default_storage_container_id'),
            'tabelas e colunas-base presentes'),
  ('P2.08', exists (select 1 from pg_trigger t where not t.tgisinternal
                    and t.tgname = 'trg_collection_layout_slot_assignment_integrity'
                    and t.tgrelid = 'public.collection_layout_slot_assignment'::regclass),
            'gatilho 5117 ligado à tabela de posições (a 5229 troca só a função)')
) as t(id, ok, detail)
order by id;

-- PRE-3 — Corpos vivos que a 5229/5230 substituem (marcadores = critério; md5 informativo)
-- md5 do corpo canônico em database/schema (LF):
--   5117 enforce_..._assignment_integrity   4731cd479c1969ce3b614bf79408a408
--   5131 assign_card_to_slot                3d847cf260bd4108941ce0c2e84eb65b
--   5225 set_slot_expected_content (4 args) cb9fd88714e9d0d680c2b7738a17f096
--   5226 preview_my_collection_binder_dismantle ee7445c09a0062c6bbf58a8fcd8ce471
--   5226 dismantle_my_collection_binder     39406cb4b936f0f5fcc3cd6830f5480b
--   5226 delete_collection (v1.4)           9885f638cd170927f09521dc08b5865b
--   5223 get_my_collection_binder           0edb4bce02f0567ba8f97e3ffe3e4077
--   5223 get_my_collection_binder_pages     2d69e4d1af1b23940bed961ead45c4ab
select v.id,
       coalesce(p.oid is not null
                and position(v.must in p.prosrc) > 0
                and position(v.mustnot in p.prosrc) = 0
                and p.prosecdef
                and p.proconfig @> array['search_path=""'], false) as ok,
       md5(p.prosrc) as md5_live,
       v.detail
from (values
  ('P3.1', 'public.enforce_collection_layout_slot_assignment_integrity()',
           'Collection dona do Layout', 'collection_layout_guest', '5117 sem convidadas'),
  ('P3.2', 'public.assign_card_to_slot(uuid, uuid)',
           'ca.collection_id = v_layout_collection_id', 'collection_layout_guest', '5131 sem convidadas'),
  ('P3.3', 'public.set_slot_expected_content(uuid, uuid, uuid, uuid)',
           'EXPECTED_CONTENT_VARIANT_AND_TYPE_EXCLUSIVE', 'collection_layout_guest', '5225 de 4 args'),
  ('P3.4', 'public.preview_my_collection_binder_dismantle(uuid)',
           'dismantle_token', 'guest_count', '5226 prévia sem convidadas'),
  ('P3.5', 'public.dismantle_my_collection_binder(uuid, text)',
           'DISMANTLE_PLAN_CHANGED', 'BINDER_HAS_GUESTS', '5226 desmontagem sem convidadas'),
  ('P3.6', 'public.delete_collection(uuid)',
           'BINDER_EXISTS', 'BINDER_GUEST', 'delete_collection 5226 (v1.4)'),
  ('P3.7', 'public.get_my_collection_binder(uuid)',
           'default_storage_kind_code', 'binder_role', '5223 cabeçalho'),
  ('P3.8', 'public.get_my_collection_binder_pages(uuid, integer, integer)',
           'present_storage_container_id', 'present_collection_id', '5223 bolsos')
) as v(id, sig, must, mustnot, detail)
left join pg_proc p on p.oid = to_regprocedure(v.sig)
order by v.id;

select 'P3.9' as id,
       pg_get_function_result(to_regprocedure('public.preview_my_collection_binder_dismantle(uuid)'))
         like '%dismantle_token text)' as ok,
       pg_get_function_result(to_regprocedure('public.get_my_collection_binder(uuid)'))
         like '%default_storage_kind_code text)' as ok_header,
       pg_get_function_result(to_regprocedure('public.get_my_collection_binder_pages(uuid, integer, integer)'))
         like '%present_storage_container_id uuid)' as ok_pages,
       'retornos atuais terminam onde a 5229/5230 acrescentam colunas' as detail;

-- PRE-4 — Dependências dos DROPs (5229 §6/§7b e 5230) --------------------------------
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
  ('P4.1', 'public.set_slot_expected_content(uuid, uuid, uuid, uuid)', 'set_slot_expected_content', 'DROP na 5229 §6'),
  ('P4.2', 'public.preview_my_collection_binder_dismantle(uuid)', 'preview_my_collection_binder_dismantle', 'DROP na 5229 §7b'),
  ('P4.3', 'public.get_my_collection_binder(uuid)', 'get_my_collection_binder', 'DROP na 5230'),
  ('P4.4', 'public.get_my_collection_binder_pages(uuid, integer, integer)', 'get_my_collection_binder_pages', 'DROP na 5230')
) as f(id, sig, name, detail)
order by f.id;
-- Critério: ok_no_pg_depend e ok_no_sql_caller = true em todas (o padrão termina em
-- "(", então "get_my_collection_binder_pages(" não conta como chamada de P4.3).

select 'P4.5' as id,
       (select p.proacl is not null and not has_function_privilege('anon', p.oid, 'EXECUTE')
               and has_function_privilege('authenticated', p.oid, 'EXECUTE')
          from pg_proc p where p.oid = to_regprocedure('public.assign_card_to_slot(uuid, uuid)')) as ok,
       'assign_card_to_slot: só authenticated (CREATE OR REPLACE preserva a ACL; a 5229 reafirma)' as detail;

-- PRE-5 — Inventário dos fichários e candidatos (baseline; nada é alterado) -----------
select
  (select count(*) from public.collection_layout)                       as layouts,
  (select count(*) from public.collection_layout_page)                  as pages,
  (select count(*) from public.collection_layout_slot)                  as slots,
  (select count(*) from public.collection_layout_slot_assignment)       as assignments,
  (select count(*) from public.collection_layout_slot_expected_content) as reservations,
  (select count(*) from public.collection_layout_slot where locked)     as locked_slots,
  (select count(*) from public.collection_layout_region)                as regions,
  (select count(*) from public.collection_allocation)                   as allocations;

-- Fichários existentes e proprietárias.
select l.id as layout_id, c.id as owner_collection_id, c.name as owner_collection,
       c.lifecycle_status, c.owner_user_id,
       l.grid_columns || 'x' || l.grid_rows as model,
       sc.name as default_storage, sc.kind_code as storage_kind,
       (select count(*) from public.collection_layout_page p where p.layout_id = l.id) as pages,
       (select count(*) from public.collection_layout_slot_assignment a
          join public.collection_layout_slot s on s.id = a.slot_id
          join public.collection_layout_page p on p.id = s.page_id where p.layout_id = l.id) as filled,
       (select count(*) from public.collection_layout_slot_expected_content e
          join public.collection_layout_slot s on s.id = e.slot_id
          join public.collection_layout_page p on p.id = s.page_id where p.layout_id = l.id) as reserved
from public.collection_layout l
join public.collection c on c.id = l.collection_id
left join public.storage_container sc on sc.id = c.default_storage_container_id
order by c.owner_user_id, c.name;

-- Futuras convidadas possíveis: coleções sem fichário guardadas (local padrão
-- BINDER) no mesmo local de uma proprietária do mesmo dono. ME5.5CC deve aparecer
-- aqui ao lado da ME5.5 se o local padrão já estiver definido.
select g.id as candidate_collection_id, g.name as candidate_collection, g.lifecycle_status,
       c.name as owner_collection, l.id as layout_id, sc.name as shared_storage
from public.collection g
join public.storage_container sc on sc.id = g.default_storage_container_id and sc.kind_code = 'BINDER'
join public.collection c on c.default_storage_container_id = g.default_storage_container_id
                        and c.owner_user_id = g.owner_user_id and c.id <> g.id
join public.collection_layout l on l.collection_id = c.id
where not exists (select 1 from public.collection_layout l2 where l2.collection_id = g.id)
order by c.name, g.name;

-- Coleções do caso de referência (informativo).
select c.id, c.name, c.lifecycle_status, sc.name as default_storage, sc.kind_code,
       exists (select 1 from public.collection_layout l where l.collection_id = c.id) as has_binder,
       (select count(*) from public.collection_allocation ca where ca.collection_id = c.id) as allocations
from public.collection c
left join public.storage_container sc on sc.id = c.default_storage_container_id
where c.name ilike '%ME5.5%' or c.name ilike '%ME 5.5%'
order by c.name;

-- PRE-6 — Janela: sessões e travas --------------------------------------------------
select a.pid, a.usename, a.application_name, a.state,
       now() - a.xact_start as xact_age, a.wait_event_type, left(a.query, 80) as query
from pg_stat_activity a
where a.datname = current_database() and a.pid <> pg_backend_pid() and a.state <> 'idle'
order by a.xact_start nulls last;

select c.relname, l.mode, l.granted, l.pid
from pg_locks l
join pg_class c on c.oid = l.relation
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('collection', 'collection_layout', 'collection_layout_slot',
                    'collection_layout_slot_expected_content', 'collection_layout_slot_assignment',
                    'collection_allocation')
  and l.pid <> pg_backend_pid();
