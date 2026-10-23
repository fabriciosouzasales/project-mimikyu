/*
================================================================
Projeto.....: Project Mimikyu
Arquivo.....: LIVE_00 - Fichário Digital (P2-A1): pré-checagens SÓ LEITURA no LIVE
Versão......: 1.0 (2026-10-23, P2-A1-LIVE-READINESS-01)
Status......: PREPARADO — NÃO EXECUTADO. Cada bloco exige autorização
              expressa de Fabrício para a etapa "pré-checagens de leitura".
Classe......: R1 — leitura de catálogo do Postgres e contagens. Nenhum
              INSERT/UPDATE/DELETE/DDL, nenhuma RPC do produto, nenhuma
              função criada (nem em pg_temp), nenhum SET ROLE.

COMO EXECUTAR
  Um bloco por vez, cada um isolado em transação SÓ LEITURA:
      begin transaction read only;
      <bloco>
      rollback;
  Em "read only" o próprio Postgres recusa qualquer escrita (25006); é a
  garantia mecânica de que a etapa não altera o LIVE.
  Guardar a saída integral de cada bloco como evidência (RUNBOOK-LIVE.md §7).

CRITÉRIO
  Linhas com coluna ok = false nos blocos PRE-2, PRE-3 e PRE-4 → STOP.
  PRE-5, PRE-6 e PRE-7 são baseline/informativos, com os gatilhos de
  decisão descritos no RUNBOOK-LIVE.md §5.
================================================================
*/

-- PRE-1 — Identidade e ledger ------------------------------------------------
select current_database() as db, current_user as usr, version() as pg, now() as at;

select version, name
from supabase_migrations.schema_migrations
order by version desc
limit 10;

-- PRE-2 — Objetos-base presentes e objetos do pacote ausentes ----------------
select id, ok, detail from (values
  ('P2.01', to_regprocedure('public.set_slot_expected_content(uuid, uuid, uuid)') is not null,
            '5128 (3 args) presente — a 5225 a substitui'),
  ('P2.02', to_regprocedure('public.set_slot_expected_content(uuid, uuid, uuid, uuid)') is null,
            'assinatura de 4 args ainda ausente'),
  ('P2.03', not exists (select 1 from information_schema.columns
                        where table_schema = 'public'
                          and table_name = 'collection_layout_slot_expected_content'
                          and column_name = 'expected_variant_type_id'),
            'coluna expected_variant_type_id ainda ausente'),
  ('P2.04', not exists (select 1 from pg_constraint
                        where conname in ('fk_expected_content_variant_type', 'chk_expected_content_variant_xor_type'))
            and to_regclass('public.ix_expected_content_variant_type') is null
            and not exists (select 1 from pg_trigger where tgname = 'trg_expected_content_variant_type_game')
            and to_regprocedure('public.enforce_expected_content_variant_type_game()') is null,
            'FK, CHECK, índice, trigger e função de trigger da 5225 ausentes'),
  ('P2.05', to_regprocedure('public.get_my_collection_binder(uuid)') is null
            and to_regprocedure('public.get_my_collection_binder_pages(uuid, integer, integer)') is null,
            'funções da 5223 ausentes'),
  ('P2.06', to_regprocedure('public.collection_binder_plan(uuid, integer, integer, text)') is null
            and to_regprocedure('public.preview_my_collection_binder(uuid, integer, integer, text)') is null
            and to_regprocedure('public.create_my_collection_binder(uuid, integer, integer, text, text)') is null,
            'funções da 5224 ausentes'),
  ('P2.07', to_regprocedure('public.collection_binder_dismantle_snapshot(uuid)') is null
            and to_regprocedure('public.preview_my_collection_binder_dismantle(uuid)') is null
            and to_regprocedure('public.dismantle_my_collection_binder(uuid, text)') is null,
            'funções da 5226 ausentes'),
  ('P2.08', to_regprocedure('public.create_collection_layout(uuid, integer, integer)') is not null
            and to_regprocedure('public.set_collection_layout_grid(uuid, integer, integer)') is not null
            and to_regprocedure('public.assert_collection_layout_mutable(uuid)') is not null
            and to_regprocedure('public.delete_collection(uuid)') is not null
            and to_regprocedure('public.master_set_positions(uuid, uuid[])') is not null,
            'base: 5123, 5137/5141, 5122, 5039, master_set_positions presentes'),
  ('P2.09', to_regclass('public.collection_layout') is not null
            and to_regclass('public.collection_layout_page') is not null
            and to_regclass('public.collection_layout_slot') is not null
            and to_regclass('public.collection_layout_slot_expected_content') is not null
            and to_regclass('public.collection_layout_slot_assignment') is not null
            and to_regclass('public.collection_layout_region') is not null
            and to_regclass('public.collection_master_set_finish') is not null
            and to_regclass('public.collection_pokedex_position_assignment') is not null
            and to_regclass('public.collection_pokedex_position_primary_representative') is not null
            and to_regclass('public.collection_pokedex_scope_generation') is not null
            and to_regclass('public.storage_container') is not null
            and to_regclass('public.card_variant_type') is not null
            and to_regclass('public.expansion') is not null,
            'tabelas-base presentes'),
  ('P2.10', exists (select 1 from information_schema.columns
                    where table_schema = 'public' and table_name = 'storage_container'
                      and column_name = 'kind_code'),
            'storage_container.kind_code (5213) presente')
) as t(id, ok, detail)
order by id;

-- PRE-3 — Corpos vivos das funções que o pacote substitui --------------------
-- md5 esperado (corpo entre $$ dos arquivos canônicos, LF):
--   5039 v1.3 delete_collection          0be52e9175809cc74a2e91703cac7739
--   5137 v1.1 set_collection_layout_grid c0023d1a995daddf93faf1ac2166a363
-- O md5 é INFORMATIVO (diferença só de espaço é possível); o critério de
-- STOP é o dos marcadores, o mesmo que os prechecks embutidos usam.
select 'P3.1' as id,
       position('deallocate them before deleting' in p.prosrc) > 0
       and position('digital binder' in p.prosrc) = 0
       and pg_get_function_result(p.oid) = 'TABLE(id uuid)'
       and p.prosecdef and p.proconfig @> array['search_path=""'] as ok,
       md5(p.prosrc) as md5_live,
       'delete_collection = 5039 v1.3 (marcadores), sem regra do fichário' as detail
from pg_proc p where p.oid = to_regprocedure('public.delete_collection(uuid)')
union all
select 'P3.2',
       position('WHERE l.id = p_layout_id' in p.prosrc) > 0
       and position('INVALID_GRID' in p.prosrc) = 0
       and pg_get_function_result(p.oid) = 'TABLE(id uuid, collection_id uuid, grid_rows integer, grid_columns integer)'
       and p.prosecdef and p.proconfig @> array['search_path=""'],
       md5(p.prosrc),
       'set_collection_layout_grid = 5137 v1.1/5141, sem regra dos sete modelos'
from pg_proc p where p.oid = to_regprocedure('public.set_collection_layout_grid(uuid, integer, integer)')
union all
select 'P3.3',
       pg_get_function_result(p.oid) = 'TABLE(id uuid, collection_id uuid, grid_rows integer, grid_columns integer)',
       md5(p.prosrc),
       'create_collection_layout (5123): retorno que a pós-checagem da 5227 exige'
from pg_proc p where p.oid = to_regprocedure('public.create_collection_layout(uuid, integer, integer)');

-- PRE-4 — Chamadores e dependências (DROP da 5225, REVOKE da 5227) ----------
select 'P4.1' as id,
       not exists (select 1 from pg_depend d
                   where d.refclassid = 'pg_catalog.pg_proc'::regclass
                     and d.refobjid = to_regprocedure('public.set_slot_expected_content(uuid, uuid, uuid)')
                     and d.deptype = 'n') as ok,
       'nenhum objeto depende da set_slot_expected_content de 3 args' as detail
union all
select 'P4.2',
       not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                   where n.nspname not in ('pg_catalog', 'information_schema')
                     and p.proname <> 'set_slot_expected_content'
                     and p.prosrc ilike '%set_slot_expected_content(%'),
       'nenhuma função chama set_slot_expected_content'
union all
select 'P4.3',
       not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                   where n.nspname not in ('pg_catalog', 'information_schema')
                     and p.proname <> 'create_collection_layout'
                     and p.prosrc ilike '%create_collection_layout(%'),
       'nenhuma função chama create_collection_layout';

-- PRE-5 — Privilégios efetivos e papéis (baseline; usa has_function_privilege,
-- que considera PUBLIC e herança por pertença) --------------------------------
select f.label,
       has_function_privilege('anon', f.oid, 'EXECUTE')          as anon_exec,
       has_function_privilege('authenticated', f.oid, 'EXECUTE') as auth_exec,
       has_function_privilege('service_role', f.oid, 'EXECUTE')  as svc_exec,
       exists (select 1 from pg_proc q, aclexplode(q.proacl) x where q.oid = f.oid and x.grantee = 0) as public_grant,
       (select string_agg(coalesce(r.rolname, 'PUBLIC') || ':' || x.privilege_type, ', ' order by r.rolname)
          from pg_proc q
          cross join lateral aclexplode(q.proacl) x
          left join pg_roles r on r.oid = x.grantee
         where q.oid = f.oid) as acl,
       (select q.proacl is null from pg_proc q where q.oid = f.oid) as acl_is_default
from (values
  ('5123 create_collection_layout',   to_regprocedure('public.create_collection_layout(uuid, integer, integer)')),
  ('5137 set_collection_layout_grid', to_regprocedure('public.set_collection_layout_grid(uuid, integer, integer)')),
  ('5128 set_slot_expected_content',  to_regprocedure('public.set_slot_expected_content(uuid, uuid, uuid)')),
  ('5039 delete_collection',          to_regprocedure('public.delete_collection(uuid)'))
) as f(label, oid);
-- Esperado hoje: 5123 auth_exec = true (é o que a 5227 fecha); 5137/5128/5039
-- auth_exec = true; anon_exec = false, public_grant = false e
-- acl_is_default = false em todas (ACL nula = EXECUTE implícito para PUBLIC).

select r.rolname, r.rolsuper, r.rolbypassrls, r.rolinherit,
       (select string_agg(g.rolname, ', ') from pg_auth_members m join pg_roles g on g.oid = m.roleid
         where m.member = r.oid) as member_of,
       (select string_agg(u.rolname, ', ') from pg_auth_members m join pg_roles u on u.oid = m.member
         where m.roleid = r.oid) as members
from pg_roles r
where r.rolname in ('anon', 'authenticated', 'service_role', 'authenticator')
order by r.rolname;
-- Esperado: anon/authenticated sem rolsuper/rolbypassrls e sem pertença a
-- papel que tenha EXECUTE nas funções acima.

select pg_get_userbyid(d.defaclrole) as owner, d.defaclobjtype, d.defaclacl
from pg_default_acl d
join pg_namespace n on n.oid = d.defaclnamespace
where n.nspname = 'public' and d.defaclobjtype = 'f';
-- Informativo: explica por que cada arquivo revoga de anon/PUBLIC
-- explicitamente depois de criar funções.

-- PRE-6 — Baseline de dados (os mesmos números são relidos no pós) ----------
select
  (select count(*) from public.collection)                              as collections,
  (select count(*) from public.collection_allocation)                   as allocations,
  (select count(*) from public.physical_card)                           as physical_cards,
  (select count(*) from public.storage_container)                       as storage_containers,
  (select count(*) from public.collection_layout)                       as layouts,
  (select count(*) from public.collection_layout_page)                  as pages,
  (select count(*) from public.collection_layout_slot)                  as slots,
  (select count(*) from public.collection_layout_slot_expected_content) as expected_content,
  (select count(*) from public.collection_layout_slot_assignment)       as assignments,
  (select count(*) from public.collection_layout_region)                as regions;

select l.grid_columns, l.grid_rows, count(*) as layouts,
       (l.grid_columns, l.grid_rows) in ((2,2), (3,3), (3,4), (4,3), (4,4), (4,5), (5,4)) as in_seven_models,
       count(*) filter (where not exists (select 1 from public.collection_layout_page p where p.layout_id = l.id)) as without_pages
from public.collection_layout l
group by l.grid_columns, l.grid_rows
order by 1, 2;

-- PRE-7 — Sessões e travas (janela de aplicação) ------------------------------
select a.pid, a.usename, a.application_name, a.state,
       now() - a.xact_start as xact_age, a.wait_event_type, left(a.query, 80) as query
from pg_stat_activity a
where a.datname = current_database()
  and a.pid <> pg_backend_pid()
  and a.state <> 'idle'
order by a.xact_start nulls last;

select c.relname, l.mode, l.granted, l.pid
from pg_locks l
join pg_class c on c.oid = l.relation
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('collection', 'collection_layout', 'collection_layout_page', 'collection_layout_slot',
                    'collection_layout_slot_expected_content', 'collection_layout_slot_assignment',
                    'card_variant_type', 'card', 'card_variant')
  and l.pid <> pg_backend_pid();
