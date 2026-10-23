/*
================================================================
Projeto.....: Project Mimikyu
Arquivo.....: LIVE_90 - Fichário Digital (P2-A1): pós-checagens SÓ LEITURA no LIVE
Versão......: 1.0 (2026-10-23, P2-A1-LIVE-READINESS-01)
Status......: PREPARADO — NÃO EXECUTADO.
Classe......: R1 — mesma classe do LIVE_00 (catálogo + contagens).

ORIGEM
  POST-1 reproduz, como SELECT puro, as checagens estruturais 0.1–0.10 do
  harness 5850. O 5850 em si NÃO roda no LIVE em nenhum modo: mesmo com
  p_isolated = false ele cria função em pg_temp e insere catálogo, usuário,
  exemplares, coleções e alocações sintéticos (Seção F em diante), ainda
  que desfaça tudo no fim.

COMO EXECUTAR
  Depois da 5228 (ou depois do último arquivo aplicado, em caso de parada
  parcial — ver RUNBOOK-LIVE.md §6). Um bloco por vez:
      begin transaction read only;
      <bloco>
      rollback;

CRITÉRIO
  POST-1: todas as linhas ok = true. POST-2: contagens IGUAIS ao PRE-6
  (o pacote não grava dados). POST-3: as seis entradas novas no ledger.
================================================================
*/

-- POST-1 — Estrutura e privilégios (equivalente a 0.1–0.10 do 5850) ---------
with f as (
  select
    to_regprocedure('public.get_my_collection_binder(uuid)')                               as f_get,
    to_regprocedure('public.get_my_collection_binder_pages(uuid, integer, integer)')       as f_pages,
    to_regprocedure('public.collection_binder_plan(uuid, integer, integer, text)')         as f_plan,
    to_regprocedure('public.preview_my_collection_binder(uuid, integer, integer, text)')   as f_prev,
    to_regprocedure('public.create_my_collection_binder(uuid, integer, integer, text, text)') as f_crt,
    to_regprocedure('public.collection_binder_dismantle_snapshot(uuid)')                   as f_snap,
    to_regprocedure('public.preview_my_collection_binder_dismantle(uuid)')                 as f_dprev,
    to_regprocedure('public.dismantle_my_collection_binder(uuid, text)')                   as f_dism,
    to_regprocedure('public.set_slot_expected_content(uuid, uuid, uuid, uuid)')            as f_sec,
    to_regprocedure('public.enforce_expected_content_variant_type_game()')                 as f_trg,
    to_regprocedure('public.delete_collection(uuid)')                                      as f_del,
    to_regprocedure('public.create_collection_layout(uuid, integer, integer)')             as f_lay,
    to_regprocedure('public.set_collection_layout_grid(uuid, integer, integer)')           as f_grid
)
select id, coalesce(ok, false) as ok, detail from f, lateral (values
  ('0.1',
   f_get is not null and f_pages is not null and f_plan is not null and f_prev is not null
   and f_crt is not null and f_snap is not null and f_dprev is not null and f_dism is not null
   and f_sec is not null and f_trg is not null and f_del is not null and f_lay is not null and f_grid is not null,
   'todas as funções do pacote e as de base presentes'),
  ('0.2',
   (select bool_and(q.prosecdef and q.proconfig @> array['search_path=""'])
      from pg_proc q where q.oid in (f_get, f_pages, f_prev, f_crt, f_dprev, f_dism, f_sec, f_del))
   and (select bool_and(q.provolatile = 's') from pg_proc q where q.oid in (f_get, f_pages, f_dprev))
   and (select bool_and(q.provolatile = 'v') from pg_proc q where q.oid in (f_prev, f_crt, f_dism)),
   'RPCs: SECURITY DEFINER e search_path vazio; leituras STABLE; prévia/criação/desmontagem VOLATILE'),
  ('0.3',
   (select bool_and(not q.prosecdef and q.proconfig @> array['search_path=""']) from pg_proc q where q.oid in (f_plan, f_snap))
   and not has_function_privilege('anon', f_plan, 'EXECUTE') and not has_function_privilege('authenticated', f_plan, 'EXECUTE')
   and not has_function_privilege('service_role', f_plan, 'EXECUTE')
   and not has_function_privilege('anon', f_snap, 'EXECUTE') and not has_function_privilege('authenticated', f_snap, 'EXECUTE')
   and not has_function_privilege('service_role', f_snap, 'EXECUTE')
   and not has_function_privilege('authenticated', f_trg, 'EXECUTE') and not has_function_privilege('anon', f_trg, 'EXECUTE')
   and not exists (select 1 from pg_proc q, aclexplode(q.proacl) x where q.oid in (f_plan, f_snap, f_trg) and x.grantee = 0),
   'helpers SECURITY INVOKER; nenhum papel de API executa helpers nem a função de trigger'),
  ('0.4',
   (select bool_and(has_function_privilege('authenticated', q.oid, 'EXECUTE')
                    and not has_function_privilege('anon', q.oid, 'EXECUTE'))
      from pg_proc q where q.oid in (f_get, f_pages, f_prev, f_crt, f_dprev, f_dism, f_sec, f_del))
   and not exists (select 1 from pg_proc q, aclexplode(q.proacl) x
                   where q.oid in (f_get, f_pages, f_prev, f_crt, f_dprev, f_dism, f_sec, f_del) and x.grantee = 0),
   'RPCs públicas: EXECUTE só authenticated (efetivo, com herança)'),
  ('0.5',
   (select bool_and(q.proconfig @> array['lock_timeout=5s']) from pg_proc q where q.oid in (f_crt, f_dism))
   and lower(pg_get_functiondef(f_crt)) like '%for update%' and lower(pg_get_functiondef(f_dism)) like '%for update%',
   'criação e desmontagem: lock_timeout 5s e FOR UPDATE da coleção'),
  ('0.6',
   exists (select 1 from information_schema.columns where table_schema = 'public'
           and table_name = 'collection_layout_slot_expected_content' and column_name = 'expected_variant_type_id')
   and exists (select 1 from pg_constraint where conname = 'chk_expected_content_variant_xor_type'
               and conrelid = 'public.collection_layout_slot_expected_content'::regclass)
   and exists (select 1 from pg_constraint where conname = 'fk_expected_content_variant_type'
               and conrelid = 'public.collection_layout_slot_expected_content'::regclass)
   and exists (select 1 from pg_trigger where tgname = 'trg_expected_content_variant_type_game' and not tgisinternal)
   and to_regprocedure('public.set_slot_expected_content(uuid, uuid, uuid)') is null,
   '5225: coluna, FK, CHECK, trigger; assinatura de 3 args removida'),
  ('0.7',
   (select q.prosrc like '%digital binder%' and q.prosrc like '%deallocate them before deleting%' from pg_proc q where q.oid = f_del)
   and pg_get_function_result(f_del) = 'TABLE(id uuid)',
   'delete_collection v1.4: recusa com fichário; regra de alocações preservada'),
  ('0.8',
   not has_function_privilege('authenticated', f_lay, 'EXECUTE')
   and not has_function_privilege('anon', f_lay, 'EXECUTE')
   and not exists (select 1 from pg_proc q, aclexplode(q.proacl) x where q.oid = f_lay and x.grantee = 0),
   '5227: create_collection_layout sem EXECUTE para authenticated/anon/PUBLIC'),
  ('0.9',
   (select q.prosecdef and q.proconfig @> array['search_path=""'] and q.prosrc like '%INVALID_GRID%'
           and q.prosrc like '%(5,4)%' and q.prosrc like '%WHERE l.id = p_layout_id%'
      from pg_proc q where q.oid = f_grid)
   and pg_get_function_result(f_grid) = 'TABLE(id uuid, collection_id uuid, grid_rows integer, grid_columns integer)'
   and has_function_privilege('authenticated', f_grid, 'EXECUTE')
   and not has_function_privilege('anon', f_grid, 'EXECUTE')
   and not exists (select 1 from pg_proc q, aclexplode(q.proacl) x where q.oid = f_grid and x.grantee = 0),
   '5228: grade só nos sete modelos; mesma assinatura/retorno; EXECUTE só authenticated'),
  ('0.10',
   (select coalesce(array_agg(q.proname::text order by q.proname), '{}')
      from pg_proc q join pg_namespace ns on ns.oid = q.pronamespace
     where ns.nspname = 'public'
       and q.prosrc ~* 'insert\s+into\s+public\.collection_layout\s*(as\s+\w+\s*)?\('
       and has_function_privilege('authenticated', q.oid, 'EXECUTE')) = array['create_my_collection_binder']
   and not exists (select 1 from pg_proc q join pg_namespace ns on ns.oid = q.pronamespace
                   where ns.nspname = 'public'
                     and q.prosrc ~* 'update\s+public\.collection_layout(\s+as\s+\w+)?\s+set'
                     and has_function_privilege('authenticated', q.oid, 'EXECUTE')
                     and q.prosrc not like '%INVALID_GRID%'),
   'sem caminho alternativo (busca textual + privilégio efetivo)')
) as t(id, ok, detail)
order by string_to_array(id, '.')::int[];

-- POST-2 — Dados intocados: comparar campo a campo com o PRE-6 --------------
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
  (select count(*) from public.collection_layout_region)                as regions,
  (select count(*) from public.collection_layout_slot_expected_content
    where expected_variant_type_id is not null)                         as expected_with_type;
-- Esperado: idêntico ao PRE-6; expected_with_type = 0.

-- POST-3 — Ledger -------------------------------------------------------------
select version, name
from supabase_migrations.schema_migrations
order by version desc
limit 8;
-- Esperado: seis entradas novas, na ordem 5225, 5223, 5224, 5226, 5227, 5228.

-- POST-4 — Security Advisor: get_advisors(type = 'security') pela ferramenta
-- (leitura). Esperado no lint 0029 (SECURITY DEFINER executável por
-- authenticated): +6 RPCs novas (5223 ×2, 5224 ×2, 5226 ×2); a
-- set_slot_expected_content de 4 args no lugar da de 3; create_collection_layout
-- fora da lista se hoje constar. Helpers e função de trigger ausentes.
-- Nenhum achado novo de outra classe.
