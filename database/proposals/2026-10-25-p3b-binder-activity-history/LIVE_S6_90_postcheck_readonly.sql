/*
================================================================
Projeto.....: Project Mimikyu
Arquivo.....: LIVE_S6_90_postcheck_readonly.sql — P3-B S6, depois de 5296
Versão......: 1.0 (2026-10-28, P3-B S6)
Status......: PROPOSTA. SÓ LEITURA. Dois blocos, cada um um SELECT.
  Bloco A (estrutural) — logo após a 5296. Esperado: ok = true em todas as linhas.
  Bloco B (funcional)  — depois das operações reais do proprietário. Cada linha B.x só avalia os
           eventos que existirem; B.1 lista a cobertura (tipos ausentes = NÃO TESTADOS, sem PASS).
  md5 esperados (A.2) calculados do corpo entre `as $fn$` e `$fn$;` de cada arquivo.
================================================================
*/

-- BLOCO A — estrutural ------------------------------------------------------------------------
select 'A.1' as id, 'ledger 5290–5296, na ordem, depois da 5289' as detail,
       coalesce((select array_agg(name order by version) from (select version, name from supabase_migrations.schema_migrations order by version desc limit 8) x)
         = array['5289_instrument_remove_my_physical_card','5290_instrument_attach_my_collection_to_binder',
                 '5291_instrument_detach_my_collection_from_binder','5292_instrument_transfer_my_binder_ownership',
                 '5293_instrument_delete_collection_layout','5294_instrument_dismantle_my_collection_binder',
                 '5295_instrument_create_my_collection_binder','5296_instrument_apply_my_binder_catalog_reconciliation'], false) as ok
union all
select 'A.2', 'corpos iguais aos da proposta (md5 de prosrc)',
       (select md5(prosrc) from pg_proc where oid = 'public.attach_my_collection_to_binder(uuid, uuid)'::regprocedure) = '20a8a2529d7bc778a4f082258a7f88c3'
       and (select md5(prosrc) from pg_proc where oid = 'public.detach_my_collection_from_binder(uuid, text, boolean)'::regprocedure) = '535e7b78f510358fab80fb765deb52cf'
       and (select md5(prosrc) from pg_proc where oid = 'public.transfer_my_binder_ownership(uuid, uuid)'::regprocedure) = 'd501c1e8390b6abd92a38de899bd902a'
       and (select md5(prosrc) from pg_proc where oid = 'public.delete_collection_layout(uuid)'::regprocedure) = '28e9cc2961b92f10298b97c089b16b70'
       and (select md5(prosrc) from pg_proc where oid = 'public.dismantle_my_collection_binder(uuid, text)'::regprocedure) = 'ec946297e3172377717a4094b48b6f55'
       and (select md5(prosrc) from pg_proc where oid = 'public.create_my_collection_binder(uuid, integer, integer, text, text)'::regprocedure) = '332eb9492bfa4673330dec62b6c3f8e7'
       and (select md5(prosrc) from pg_proc where oid = 'public.apply_my_binder_catalog_reconciliation(uuid, text[], text, boolean, boolean)'::regprocedure) = '0f25fc937aa7d1b8b3d88416d55f5395'
union all
select 'A.3', 'instrumentadas: DEFINER, search_path vazio, EXECUTE só authenticated; lock_timeout preservado onde existia',
       (select bool_and(p.prosecdef and p.proconfig @> array['search_path=""']
                        and has_function_privilege('authenticated', p.oid, 'EXECUTE')
                        and not has_function_privilege('anon', p.oid, 'EXECUTE')
                        and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0))
        from pg_proc p where p.oid in ('public.attach_my_collection_to_binder(uuid, uuid)'::regprocedure,
          'public.detach_my_collection_from_binder(uuid, text, boolean)'::regprocedure, 'public.transfer_my_binder_ownership(uuid, uuid)'::regprocedure,
          'public.delete_collection_layout(uuid)'::regprocedure, 'public.dismantle_my_collection_binder(uuid, text)'::regprocedure,
          'public.create_my_collection_binder(uuid, integer, integer, text, text)'::regprocedure,
          'public.apply_my_binder_catalog_reconciliation(uuid, text[], text, boolean, boolean)'::regprocedure))
       and (select bool_and(p.proconfig @> array['lock_timeout=5s']) from pg_proc p where p.oid in (
          'public.attach_my_collection_to_binder(uuid, uuid)'::regprocedure, 'public.detach_my_collection_from_binder(uuid, text, boolean)'::regprocedure,
          'public.transfer_my_binder_ownership(uuid, uuid)'::regprocedure, 'public.dismantle_my_collection_binder(uuid, text)'::regprocedure,
          'public.create_my_collection_binder(uuid, integer, integer, text, text)'::regprocedure,
          'public.apply_my_binder_catalog_reconciliation(uuid, text[], text, boolean, boolean)'::regprocedure))
union all
select 'A.4', 'retornos inalterados',
       pg_get_function_result('public.attach_my_collection_to_binder(uuid, uuid)'::regprocedure) = 'TABLE(outcome text, layout_id uuid, owner_collection_id uuid)'
       and pg_get_function_result('public.transfer_my_binder_ownership(uuid, uuid)'::regprocedure) = 'TABLE(outcome text, layout_id uuid, reservations_pinned integer)'
       and pg_get_function_result('public.delete_collection_layout(uuid)'::regprocedure) = 'void'
       and pg_get_function_result('public.detach_my_collection_from_binder(uuid, text, boolean)'::regprocedure)
           = 'TABLE(outcome text, assignments_removed integer, reservations_removed integer, locks_released integer)'
union all
select 'A.5', 'gate de cobertura (§7.3): 24 funções fora da S1 referenciam o histórico (S2–S6)',
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public'
          and p.proname not in ('binder_activity_begin','binder_activity_add_item','binder_activity_end','binder_activity_category',
                                'get_my_binder_activity','get_my_binder_activity_coverage','list_my_closed_binder_histories',
                                'purge_my_binder_activity','binder_activity_event_guard','binder_activity_item_guard')
          and pg_get_functiondef(p.oid) ~* 'binder_activity_') = 24
union all
select 'A.6', 'nenhum evento da S6 gravado pela instalação',
       not exists (select 1 from public.binder_activity_event
                   where event_type in ('BINDER_ASSEMBLED','CATALOG_NOVELTIES_INCORPORATED','COLLECTION_ATTACHED','COLLECTION_DETACHED',
                                        'BINDER_DISMANTLED','BINDER_DELETED_EMPTY','BINDER_OWNERSHIP_TRANSFERRED'));

-- BLOCO B — funcional (só eventos existentes; ausência = não testado) --------------------------
with e as (
  select ev.*, (select count(*) from public.binder_activity_item i where i.event_id = ev.id) as n,
         (select max(i.ordinal) from public.binder_activity_item i where i.event_id = ev.id) as mx
  from public.binder_activity_event ev
  where ev.event_type in ('BINDER_ASSEMBLED','CATALOG_NOVELTIES_INCORPORATED','COLLECTION_ATTACHED','COLLECTION_DETACHED',
                          'BINDER_DISMANTLED','BINDER_DELETED_EMPTY','BINDER_OWNERSHIP_TRANSFERRED')
), it as (
  select i.*, ev.event_type, ev.created_xact from public.binder_activity_item i join e ev on ev.id = i.event_id
)
select 'B.1 COBERTURA' as id, 'eventos S6 por tipo: ' || coalesce((select string_agg(event_type || '=' || c, ', ' order by event_type)
        from (select event_type, count(*) c from e group by event_type) x), '-') as detail, true as ok
union all
select 'B.2', 'todo evento: ator = titular, origem coerente, coleção presente, ≥ 1 item, ordinais contíguos',
       not exists (select 1 from e where actor_user_id is distinct from owner_user_id or n < 1 or mx <> n
                   or source <> case event_type when 'CATALOG_NOVELTIES_INCORPORATED' then 'CATALOGO' else 'FICHARIO' end
                   or (collection_id is null and event_type <> 'BINDER_DELETED_EMPTY'))
union all
select 'B.3', 'efeitos por tipo conforme §33.3',
       not exists (select 1 from it where (item_kind, effect) not in (
         select * from (values ('COLLECTION','ATTACHED'),('COLLECTION','DETACHED'),('POCKET','UNLOCKED'),('RESERVATION','RELEASED'),
                               ('BINDER','TRANSFERRED'),('BINDER','CLOSED'),('CARD','REMOVED'),('PAGE','PAGE_ADDED'),('CARD','PLACED'),
                               ('RESERVATION','RESERVED'),('RESERVATION','INCORPORATED'),('CARD','SHIFTED'),('RESERVATION','SHIFTED'),
                               ('POCKET','SHIFTED')) v(k, f))
         or (event_type = 'COLLECTION_ATTACHED' and effect <> 'ATTACHED')
         or (event_type = 'BINDER_OWNERSHIP_TRANSFERRED' and effect <> 'TRANSFERRED')
         or (event_type = 'BINDER_DELETED_EMPTY' and effect <> 'CLOSED')
         or (event_type = 'COLLECTION_DETACHED' and effect not in ('UNLOCKED','RELEASED','DETACHED'))
         or (event_type = 'BINDER_DISMANTLED' and effect not in ('REMOVED','RELEASED','CLOSED'))
         or (event_type = 'BINDER_ASSEMBLED' and effect not in ('PAGE_ADDED','PLACED','RESERVED'))
         or (event_type = 'CATALOG_NOVELTIES_INCORPORATED' and effect not in ('SHIFTED','PAGE_ADDED','RESERVED','INCORPORATED')))
union all
select 'B.4', 'origem/destino: saídas com origem e sem destino; entradas com destino e sem origem; SHIFTED com ambos',
       not exists (select 1 from it where
            (effect in ('REMOVED','RELEASED','UNLOCKED') and (from_page is null or to_page is not null))
         or (effect in ('PLACED','RESERVED','INCORPORATED') and (to_page is null or from_page is not null))
         or (effect = 'SHIFTED' and (from_row is null or to_row is null)))
union all
select 'B.5', 'exatamente 1 item de marco por evento (ATTACHED/DETACHED/TRANSFERRED/CLOSED) onde aplicável',
       not exists (select 1 from e where event_type in ('COLLECTION_ATTACHED','COLLECTION_DETACHED','BINDER_OWNERSHIP_TRANSFERRED',
                                                       'BINDER_DELETED_EMPTY','BINDER_DISMANTLED')
                   and (select count(*) from it where it.event_id = e.id and effect in ('ATTACHED','DETACHED','TRANSFERRED','CLOSED')) <> 1)
union all
select 'B.6', 'R5: nenhum PAGES_ADDED independente na transação de uma incorporação de novidades',
       not exists (select 1 from e a join public.binder_activity_event b on b.created_xact = a.created_xact and b.id <> a.id
                   where a.event_type = 'CATALOG_NOVELTIES_INCORPORATED' and b.event_type in ('PAGES_ADDED','PAGE_REMOVED'))
union all
select 'B.7', 'sem duplicidade de carta/reserva no mesmo evento (exceto SHIFTED repetido da E16)',
       not exists (select 1 from it where effect <> 'SHIFTED' and item_kind in ('CARD','RESERVATION')
                   group by event_id, item_kind, effect, coalesce(from_page, to_page), coalesce(from_row, to_row), coalesce(from_col, to_col)
                   having count(*) > 1)
union all
select 'B.8 AMOSTRA', (select string_agg(x.linha, E'\n' order by x.id desc) from (
         select e.id, to_char(e.occurred_at at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI:SS') || ' · ' || e.event_type || ' · '
                || coalesce(e.collection_name, '-') || ' · ' || e.n || ' itens · ' ||
                (select string_agg(i.item_kind || '/' || i.effect || coalesce(' ' || i.card_name, ''), ' | ' order by i.ordinal)
                 from (select * from public.binder_activity_item i0 where i0.event_id = e.id order by i0.ordinal limit 6) i) as linha
         from e order by e.id desc limit 20) x), true;
