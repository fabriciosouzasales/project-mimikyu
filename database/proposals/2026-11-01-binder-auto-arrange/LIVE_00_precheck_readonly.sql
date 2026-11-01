/*
================================================================
Projeto.....: Project Mimikyu
Query.......: LIVE_00 - Pré-checagem somente leitura da P2 (5341–5344 + 5872)
Versão......: 1.0
Status......: PREPARADO — NÃO EXECUTADO (P2 OPERATIONAL ROUTE CORRECTION-11, 2026-11-01)
Classe......: R1 (somente leitura). Nenhuma escrita, nenhuma trava além de leitura.

Uso: duas chamadas execute_sql, na ordem.
  PRE   → todas as linhas ok = true; qualquer false = STOP.
  FP    → impressão digital dos dados do usuário (contagem + md5 por tabela,
          sem identificadores). Guardar a saída: o LIVE_90 repete o FP e
          exige igualdade (prova de que nenhum dado real mudou).
Janela: sem uso do app durante todo o ciclo (o FP depende disso).
================================================================
*/

-- PRE --------------------------------------------------------------------------------
set transaction read only;
with
deps(sig) as (values
  ('public.assert_collection_layout_mutable(uuid)'), ('public.binder_activity_begin(uuid,text,text,uuid,jsonb)'),
  ('public.binder_activity_end()'), ('public.binder_activity_add_card_item(text,uuid,uuid,uuid)'),
  ('public.binder_activity_category(text)'), ('public.purge_my_binder_activity(uuid,uuid)'),
  ('public.allocate_physical_cards_to_collection(uuid,uuid[])'), ('public.archive_collection(uuid)'),
  ('public.attach_my_collection_to_binder(uuid,uuid)'), ('public.clear_slot_expected_content(uuid[])'),
  ('public.create_my_card_set_collection(uuid,uuid,text,uuid)'), ('public.create_my_collection_binder(uuid,integer,integer,text,text)'),
  ('public.create_my_free_collection(uuid,text,uuid)'), ('public.create_my_pokedex_collection(uuid,text,text[],uuid)'),
  ('public.create_my_storage_container(uuid,text,text)'), ('public.get_my_collection_binder(uuid)'),
  ('public.place_my_physical_card_in_slot(uuid,uuid,uuid)'), ('public.preview_my_collection_binder(uuid,integer,integer,text)'),
  ('public.remove_slot_assignment(uuid[])'), ('public.set_collection_completion_policy_to_master_set(uuid,uuid[])'),
  ('public.set_physical_cards_storage(uuid,uuid[],boolean)'), ('public.set_slot_expected_content(uuid,uuid,uuid,uuid,uuid)'),
  ('public.set_slot_lock(uuid[],boolean)')),
types_5341(t) as (select unnest(array[
  'BINDER_ASSEMBLED','CARD_PLACED','CARD_MOVED','CARDS_SWAPPED','CARDS_REMOVED','CARDS_LEFT_BY_STORAGE',
  'CARDS_LEFT_BY_COLLECTION_STORAGE','CARD_LEFT_BY_INVENTORY_EXIT','POCKET_RESERVED','RESERVATIONS_RELEASED',
  'POCKETS_LOCKED','POCKETS_UNLOCKED','GAP_OPENED','GAP_CLOSED','PAGES_ADDED','PAGE_REMOVED','PAGES_REORDERED',
  'CATALOG_NOVELTIES_INCORPORATED','COLLECTION_ATTACHED','COLLECTION_DETACHED','BINDER_DISMANTLED',
  'BINDER_DELETED_EMPTY','BINDER_OWNERSHIP_TRANSFERRED','LEGACY_CATALOG_INCORPORATION'])),
live_types(t) as (select m[1] from regexp_matches(pg_get_constraintdef(
  (select oid from pg_constraint where conrelid = 'public.binder_activity_event'::regclass and conname = 'chk_bae_event_type')),
  '''([A-Z_0-9]+)''', 'g') m),
fixture_tables(sch, tbl) as (values ('auth','users'),('public','expansion'),('public','card_set'),('public','card'),
  ('public','card_variant'),('public','physical_card'),('public','collection'),('public','collection_allocation'),
  ('public','collection_layout'),('public','collection_layout_slot_assignment'),('public','binder_activity_event'),
  ('public','storage_container'),('public','collection_layout_slot_expected_content'),('public','collection_layout_guest'))
select 'PRE-1' as id,
       current_setting('server_version') like '17.%'
       and current_setting('default_transaction_isolation') = 'read committed' as ok,
       'PG ' || current_setting('server_version') || '; isolamento padrão ' || current_setting('default_transaction_isolation') as detail
union all
select 'PRE-2', count(*) filter (where to_regprocedure(sig) is null) = 0,
       '23 dependências; ausentes: ' || coalesce(string_agg(sig, ', ') filter (where to_regprocedure(sig) is null), 'nenhuma')
from deps
union all
select 'PRE-3',
       to_regprocedure('public.binder_auto_arrange_plan(uuid,uuid,uuid)') is null
       and to_regprocedure('public.preview_my_binder_auto_arrange(uuid)') is null
       and to_regprocedure('public.apply_my_binder_auto_arrange(uuid,text)') is null
       and not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
                       and p.proname in ('binder_auto_arrange_plan','preview_my_binder_auto_arrange','apply_my_binder_auto_arrange')),
       'funções propostas ausentes (nenhuma versão)'
union all
select 'PRE-4',
       (select array_agg(t order by t) from live_types) = (select array_agg(t order by t) from types_5341)
       and (select count(*) from public.binder_activity_event where event_type = 'CARDS_AUTO_ARRANGED') = 0,
       'CHECK do LIVE = lista da 5341 sem o tipo novo (' || (select count(*) from live_types) || ' tipos); 0 eventos CARDS_AUTO_ARRANGED'
union all
select 'PRE-5',
       (select bool_and(public.binder_activity_category(t) = case
          when t in ('CARD_PLACED','CARD_MOVED','CARDS_SWAPPED','CARDS_REMOVED','CARDS_LEFT_BY_STORAGE',
                     'CARDS_LEFT_BY_COLLECTION_STORAGE','CARD_LEFT_BY_INVENTORY_EXIT') then 'CARDS'
          when t in ('POCKET_RESERVED','RESERVATIONS_RELEASED') then 'RESERVATIONS'
          when t in ('POCKETS_LOCKED','POCKETS_UNLOCKED') then 'LOCKS'
          when t in ('GAP_OPENED','GAP_CLOSED','PAGES_ADDED','PAGE_REMOVED','PAGES_REORDERED') then 'PAGES'
          when t in ('CATALOG_NOVELTIES_INCORPORATED','LEGACY_CATALOG_INCORPORATION') then 'CATALOG'
          else 'BINDER' end) from types_5341),
       'binder_activity_category do LIVE = corpo que a 5341 substitui (sem regressão de categoria)'
union all
select 'PRE-6',
       (select array_agg(p.proname::text order by p.proname) from pg_proc p
        where p.pronamespace = 'public'::regnamespace
          and p.prosrc ~* '(insert\s+into|update)\s+public\.binder_activity_coverage') = array['purge_my_binder_activity']
       and not has_function_privilege('authenticated', 'public.purge_my_binder_activity(uuid,uuid)', 'EXECUTE')
       and not has_function_privilege('anon', 'public.purge_my_binder_activity(uuid,uuid)', 'EXECUTE'),
       'único escritor do marco de cobertura = 5270, sem EXECUTE para clientes (premissa da época do token)'
union all
select 'PRE-7',
       exists (select 1 from public.game where code = 'POKEMON')
       and exists (select 1 from public.language where code = 'pt-BR')
       and (select count(*) from public.card_variant_type t join public.game g on g.id = t.game_id
            where g.code = 'POKEMON' and t.code in ('STANDARD','REVERSE_HOLO')) = 2
       and exists (select 1 from public.pokemon_generation where code = 'GENERATION_I'),
       'referência usada pela fixture: POKEMON, pt-BR, STANDARD, REVERSE_HOLO, GENERATION_I'
union all
select 'PRE-8',
       not exists (select 1 from pg_trigger tg join pg_class c on c.oid = tg.tgrelid join pg_proc p on p.oid = tg.tgfoid
                   join fixture_tables f on f.sch = c.relnamespace::regnamespace::text and f.tbl = c.relname
                   where not tg.tgisinternal
                     and p.prosrc ~* '(net\.|http_|pg_notify|notify\s|dblink|pg_background)'),
       'nenhum gatilho com efeito fora da transação nas tabelas tocadas pela fixture (rollback é integral)'
union all
select 'PRE-9',
       not exists (select 1 from pg_stat_activity a
                   where a.datname = current_database() and a.pid <> pg_backend_pid()
                     and a.backend_type = 'client backend'
                     and a.state in ('active','idle in transaction','idle in transaction (aborted)')
                     and a.xact_start < now() - interval '60 seconds'),
       'nenhuma transação de cliente aberta há mais de 60 s';

-- FP ---------------------------------------------------------------------------------
set transaction read only;
select 'collection' as tbl, count(*) as n, md5(coalesce(string_agg(x::text, '|' order by x::text), '')) as fp from public.collection x
union all select 'collection_allocation', count(*), md5(coalesce(string_agg(x::text, '|' order by x::text), '')) from public.collection_allocation x
union all select 'physical_card', count(*), md5(coalesce(string_agg(x::text, '|' order by x::text), '')) from public.physical_card x
union all select 'storage_container', count(*), md5(coalesce(string_agg(x::text, '|' order by x::text), '')) from public.storage_container x
union all select 'collection_layout', count(*), md5(coalesce(string_agg(x::text, '|' order by x::text), '')) from public.collection_layout x
union all select 'collection_layout_page', count(*), md5(coalesce(string_agg(x::text, '|' order by x::text), '')) from public.collection_layout_page x
union all select 'collection_layout_slot', count(*), md5(coalesce(string_agg(x::text, '|' order by x::text), '')) from public.collection_layout_slot x
union all select 'collection_layout_slot_assignment', count(*), md5(coalesce(string_agg(x::text, '|' order by x::text), '')) from public.collection_layout_slot_assignment x
union all select 'collection_layout_slot_expected_content', count(*), md5(coalesce(string_agg(x::text, '|' order by x::text), '')) from public.collection_layout_slot_expected_content x
union all select 'collection_layout_guest', count(*), md5(coalesce(string_agg(x::text, '|' order by x::text), '')) from public.collection_layout_guest x
union all select 'binder_activity_event', count(*), md5(coalesce(string_agg(x::text, '|' order by x::text), '')) from public.binder_activity_event x
union all select 'binder_activity_coverage', count(*), md5(coalesce(string_agg(x::text, '|' order by x::text), '')) from public.binder_activity_coverage x
union all select 'auth.users (ids)', count(*), md5(coalesce(string_agg(x.id::text, '|' order by x.id), '')) from auth.users x
union all select 'card (ids)', count(*), md5(coalesce(string_agg(x.id::text, '|' order by x.id), '')) from public.card x
union all select 'card_variant (id, ativo)', count(*), md5(coalesce(string_agg(x.id::text || x.is_active::text, '|' order by x.id), '')) from public.card_variant x
union all select 'card_set (ids)', count(*), md5(coalesce(string_agg(x.id::text, '|' order by x.id), '')) from public.card_set x
union all select 'expansion (ids)', count(*), md5(coalesce(string_agg(x.id::text, '|' order by x.id), '')) from public.expansion x
order by 1;
