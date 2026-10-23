/*
================================================================
Projeto.....: Project Mimikyu
Arquivo.....: LIVE_90 - Fichário compartilhado (5229/5230): pós-checagens SÓ LEITURA
Versão......: 1.0 (2026-10-23, P2-SHARED-BINDER-LIVE-READINESS-01)
Status......: PREPARADO — NÃO EXECUTADO. Executar só depois de 5229 → 5230
              aplicadas, com autorização expressa para a etapa R1-pós.
Classe......: R1 — catálogo e contagens; nenhuma escrita, nenhuma RPC.

COMO EXECUTAR — um bloco por vez em `begin transaction read only; … rollback;`.

CRITÉRIO: POST-1 todas ok; POST-2 idêntico ao PRE-5 e com zero convidadas e
zero reservas com coleção; POST-3 com as duas entradas na ordem.
Substitui as Seções 0 do harness 5851, que NÃO roda no LIVE (cria dados).
================================================================
*/

-- POST-1 — Estrutura, segurança e contratos ----------------------------------------
select id, ok, detail from (values
  ('Q1.01', to_regclass('public.collection_layout_guest') is not null
            and (select c.relrowsecurity from pg_class c where c.oid = to_regclass('public.collection_layout_guest'))
            and has_table_privilege('authenticated', 'public.collection_layout_guest', 'SELECT')
            and not has_table_privilege('authenticated', 'public.collection_layout_guest', 'INSERT')
            and not has_table_privilege('authenticated', 'public.collection_layout_guest', 'UPDATE')
            and not has_table_privilege('authenticated', 'public.collection_layout_guest', 'DELETE')
            and not has_table_privilege('anon', 'public.collection_layout_guest', 'SELECT'),
            'convidadas: RLS, só SELECT para authenticated, nada para anon'),
  ('Q1.02', exists (select 1 from pg_constraint where conrelid = to_regclass('public.collection_layout_guest')
                    and contype = 'p')
            and (select count(*) from pg_constraint where conrelid = to_regclass('public.collection_layout_guest')
                 and contype = 'f') = 2,
            'convidadas: PK collection_id + 2 FKs (coleção, layout)'),
  ('Q1.03', exists (select 1 from information_schema.columns where table_schema = 'public'
                    and table_name = 'collection_layout_slot_expected_content'
                    and column_name = 'collection_id' and is_nullable = 'YES'),
            'reserva: coluna collection_id anulável'),
  ('Q1.04', (select count(*) from pg_trigger where not tgisinternal and tgname in (
              'trg_collection_layout_guest_integrity','trg_collection_layout_owner_not_guest',
              'trg_collection_layout_delete_without_guests','trg_expected_content_participant',
              'trg_collection_layout_slot_assignment_integrity')) = 5,
            'gatilhos: 4 novos + 5117 ainda ligado'),
  ('Q1.05', (select bool_and(not has_function_privilege('authenticated', q.oid, 'EXECUTE')
                             and not has_function_privilege('anon', q.oid, 'EXECUTE'))
             from pg_proc q join pg_namespace n on n.oid = q.pronamespace
             where n.nspname = 'public' and q.proname in (
               'enforce_collection_layout_guest_integrity','enforce_collection_layout_owner_not_guest',
               'enforce_collection_layout_delete_without_guests','enforce_expected_content_participant',
               'enforce_collection_layout_slot_assignment_integrity','collection_binder_detach_snapshot')),
            'funções de gatilho e retrato interno sem EXECUTE para a API'),
  ('Q1.06', (select bool_and(q.prosecdef and q.proconfig @> array['search_path=""']
                             and has_function_privilege('authenticated', q.oid, 'EXECUTE')
                             and not has_function_privilege('anon', q.oid, 'EXECUTE'))
             from pg_proc q where q.oid in (
               to_regprocedure('public.attach_my_collection_to_binder(uuid, uuid)'),
               to_regprocedure('public.preview_my_collection_binder_detach(uuid)'),
               to_regprocedure('public.detach_my_collection_from_binder(uuid, text, boolean)'),
               to_regprocedure('public.set_slot_expected_content(uuid, uuid, uuid, uuid, uuid)'),
               to_regprocedure('public.assign_card_to_slot(uuid, uuid)'),
               to_regprocedure('public.delete_collection(uuid)'),
               to_regprocedure('public.preview_my_collection_binder_dismantle(uuid)'),
               to_regprocedure('public.dismantle_my_collection_binder(uuid, text)'),
               to_regprocedure('public.list_my_binder_join_candidates(uuid)'),
               to_regprocedure('public.get_my_collection_binder_unplaced(uuid, integer, integer)'),
               to_regprocedure('public.get_my_collection_binder(uuid)'),
               to_regprocedure('public.get_my_collection_binder_pages(uuid, integer, integer)')))
            and (select count(*) from pg_proc q where q.oid in (
               to_regprocedure('public.attach_my_collection_to_binder(uuid, uuid)'),
               to_regprocedure('public.preview_my_collection_binder_detach(uuid)'),
               to_regprocedure('public.detach_my_collection_from_binder(uuid, text, boolean)'),
               to_regprocedure('public.set_slot_expected_content(uuid, uuid, uuid, uuid, uuid)'),
               to_regprocedure('public.list_my_binder_join_candidates(uuid)'),
               to_regprocedure('public.get_my_collection_binder_unplaced(uuid, integer, integer)'))) = 6,
            '12 RPCs: SECURITY DEFINER, search_path vazio, EXECUTE só authenticated; 6 novas presentes'),
  ('Q1.07', not exists (select 1 from pg_proc q, aclexplode(q.proacl) x
                        where q.oid in (
                          to_regprocedure('public.attach_my_collection_to_binder(uuid, uuid)'),
                          to_regprocedure('public.detach_my_collection_from_binder(uuid, text, boolean)'),
                          to_regprocedure('public.set_slot_expected_content(uuid, uuid, uuid, uuid, uuid)'),
                          to_regprocedure('public.preview_my_collection_binder_dismantle(uuid)'),
                          to_regprocedure('public.get_my_collection_binder(uuid)'),
                          to_regprocedure('public.get_my_collection_binder_pages(uuid, integer, integer)'))
                          and x.grantee = 0)
            and (select bool_and(q.proacl is not null) from pg_proc q where q.oid in (
                          to_regprocedure('public.preview_my_collection_binder_dismantle(uuid)'),
                          to_regprocedure('public.get_my_collection_binder(uuid)'),
                          to_regprocedure('public.get_my_collection_binder_pages(uuid, integer, integer)'))),
            'funções recriadas (DROP+CREATE) sem EXECUTE implícito para PUBLIC'),
  ('Q1.08', to_regprocedure('public.set_slot_expected_content(uuid, uuid, uuid, uuid)') is null,
            'assinatura de 4 args removida'),
  ('Q1.09', (select q.proconfig @> array['lock_timeout=5s'] from pg_proc q
             where q.oid = to_regprocedure('public.attach_my_collection_to_binder(uuid, uuid)'))
            and (select q.proconfig @> array['lock_timeout=5s'] from pg_proc q
                 where q.oid = to_regprocedure('public.detach_my_collection_from_binder(uuid, text, boolean)'))
            and (select q.proconfig @> array['lock_timeout=5s'] from pg_proc q
                 where q.oid = to_regprocedure('public.dismantle_my_collection_binder(uuid, text)')),
            'attach/detach/dismantle com lock_timeout 5s'),
  ('Q1.10', (select position('BINDER_HAS_GUESTS' in q.prosrc) > 0
                    and position('COLLECTION_IS_BINDER_GUEST' in q.prosrc) > 0
                    and position('BINDER_HAS_GUESTS' in q.prosrc) < position('DISMANTLE_PLAN_CHANGED' in q.prosrc)
             from pg_proc q where q.oid = to_regprocedure('public.dismantle_my_collection_binder(uuid, text)'))
            and pg_get_function_result(to_regprocedure('public.preview_my_collection_binder_dismantle(uuid)'))
                like '%guest_count integer, blocked_reason text)',
            'desmontagem recusa convidadas antes do token/remoção; prévia com guest_count e blocked_reason'),
  ('Q1.11', (select position('collection_layout_guest' in q.prosrc) > 0
                    and position('for share' in lower(q.prosrc)) = 0
             from pg_proc q where q.oid = to_regprocedure('public.enforce_collection_layout_slot_assignment_integrity()'))
            and (select position('v_guest_collection_id' in q.prosrc) > 0
                        and position('for share' in lower(q.prosrc)) > 0
                        and position('for share' in lower(q.prosrc)) < position('ALLOCATION ESCOPADA' in q.prosrc)
                 from pg_proc q where q.oid = to_regprocedure('public.assign_card_to_slot(uuid, uuid)')),
            'ordem de travas: gatilho de posição sem trava; assign trava convidada antes da alocação'),
  ('Q1.12', (select position('BINDER_GUEST' in q.prosrc) > 0 and position('BINDER_EXISTS' in q.prosrc) > 0
                    and pg_get_function_result(q.oid) = 'TABLE(id uuid)'
             from pg_proc q where q.oid = to_regprocedure('public.delete_collection(uuid)')),
            'delete_collection: BINDER_EXISTS + BINDER_GUEST, mesmo retorno'),
  ('Q1.13', pg_get_function_result(to_regprocedure('public.get_my_collection_binder(uuid)'))
              like '%default_storage_kind_code text, binder_role text, owner_collection_id uuid, owner_collection_name text, participant_count integer, own_filled_count integer, own_unplaced_count integer, join_candidate_count integer)'
            and pg_get_function_result(to_regprocedure('public.get_my_collection_binder_pages(uuid, integer, integer)'))
              like '%present_storage_container_id uuid, present_collection_id uuid, expected_collection_id uuid)',
            'leituras: colunas antigas preservadas, novas só no fim'),
  ('Q1.14', to_regclass('public.ix_collection_layout_guest_layout') is not null
            and to_regclass('public.ix_expected_content_collection') is not null,
            'índices novos presentes')
) as t(id, ok, detail)
order by id;

-- POST-2 — Dados intocados (comparar com PRE-5, campo a campo) -----------------------
select
  (select count(*) from public.collection_layout)                       as layouts,
  (select count(*) from public.collection_layout_page)                  as pages,
  (select count(*) from public.collection_layout_slot)                  as slots,
  (select count(*) from public.collection_layout_slot_assignment)       as assignments,
  (select count(*) from public.collection_layout_slot_expected_content) as reservations,
  (select count(*) from public.collection_layout_slot where locked)     as locked_slots,
  (select count(*) from public.collection_layout_region)                as regions,
  (select count(*) from public.collection_allocation)                   as allocations,
  (select count(*) from public.collection_layout_guest)                 as guests,          -- esperado 0
  (select count(*) from public.collection_layout_slot_expected_content
    where collection_id is not null)                                     as reservations_with_collection; -- esperado 0

-- POST-3 — Ledger --------------------------------------------------------------------
select version, name
from supabase_migrations.schema_migrations
order by version desc
limit 4;
-- Esperado: as duas entradas mais recentes são 5229 e 5230, nessa ordem.

-- POST-4 — Advisors: rodar get_advisors(security) e comparar com o resultado anterior;
-- nenhum achado novo de outra classe (fora de lint 0029 já conhecido nas RPCs SECURITY DEFINER).
