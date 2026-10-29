/*
================================================================
Projeto.....: Project Mimikyu
Arquivo.....: LIVE_S3_90_postcheck_readonly.sql — P3-B S3, depois de 5278
Versão......: 1.0 (2026-10-27, P3-B S3)
Status......: PROPOSTA. SÓ LEITURA. Dois blocos, cada um um SELECT.
  Bloco A (estrutural) — logo após a 5278. Esperado: ok = true em todas as linhas.
  Bloco B (funcional)  — depois que o proprietário fizer, pela interface, ao menos:
           reservar 1 bolso vazio, trocar a reserva de um bolso já reservado,
           liberar ≥ 2 reservas de uma vez, fixar ≥ 2 bolsos e desfixá-los.
           Esperado: ok = true em B.1–B.6; B.7 é a amostra para conferência visual.
  md5 esperados (A.2) calculados do corpo entre `as $fn$` e `$fn$;` de cada arquivo.
================================================================
*/

-- BLOCO A — estrutural ------------------------------------------------------------------------
with f as (
  select p.oid, p.proname, p.prosecdef, p.proconfig, md5(p.prosrc) as m
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('binder_activity_add_reservation_item','set_slot_expected_content','clear_slot_expected_content','set_slot_lock')
)
select 'A.1' as id, 'ledger 5275–5278, na ordem' as detail,
       coalesce((select array_agg(name order by version) from supabase_migrations.schema_migrations where name ~ '^(5275|5276|5277|5278)_')
         = array['5275_create_binder_activity_add_reservation_item','5276_instrument_set_slot_expected_content',
                 '5277_instrument_clear_slot_expected_content','5278_instrument_set_slot_lock'], false) as ok
union all
select 'A.2', 'corpos iguais aos da proposta (md5 de prosrc)',
       (select m from f where proname = 'binder_activity_add_reservation_item') = 'dfde6ee11f60c0dc917f34aee19d5112'
       and (select m from f where proname = 'set_slot_expected_content') = '33dde5013dbb491bd4a0452ab7ce8132'
       and (select m from f where proname = 'clear_slot_expected_content') = '0b8f26825ff713a24226548ffe3a63b7'
       and (select m from f where proname = 'set_slot_lock') = '651048a4bf7d3229904ef2a073c509c5'
union all
select 'A.3', 'helper interno: DEFINER, search_path vazio, sem EXECUTE para PUBLIC/anon/authenticated/service_role',
       coalesce((select prosecdef and proconfig @> array['search_path=""']
               and not has_function_privilege('anon', oid, 'EXECUTE')
               and not has_function_privilege('authenticated', oid, 'EXECUTE')
               and not has_function_privilege('service_role', oid, 'EXECUTE')
               and not exists (select 1 from aclexplode((select proacl from pg_proc where oid = f.oid)) x where x.grantee = 0)
        from f where proname = 'binder_activity_add_reservation_item'), false)
union all
select 'A.4', 'funções instrumentadas: DEFINER, search_path vazio, EXECUTE só authenticated (sem anon/PUBLIC)',
       (select bool_and(prosecdef and proconfig @> array['search_path=""']
                        and has_function_privilege('authenticated', oid, 'EXECUTE')
                        and not has_function_privilege('anon', oid, 'EXECUTE')
                        and not exists (select 1 from aclexplode((select proacl from pg_proc q where q.oid = f.oid)) x where x.grantee = 0))
        from f where proname <> 'binder_activity_add_reservation_item')
union all
select 'A.5', 'assinaturas e retornos inalterados',
       pg_get_function_result('public.set_slot_expected_content(uuid, uuid, uuid, uuid, uuid)'::regprocedure)
         = 'TABLE(slot_id uuid, card_id uuid, card_variant_id uuid, expected_variant_type_id uuid, collection_id uuid)'
       and pg_get_function_result('public.clear_slot_expected_content(uuid[])'::regprocedure) = 'integer'
       and pg_get_function_result('public.set_slot_lock(uuid[], boolean)'::regprocedure) = 'integer'
union all
select 'A.6', 'gate de cobertura (§7.3): fora da S1, só S2 + S3 referenciam o histórico',
       (select coalesce(array_agg(p.proname::text order by p.proname), '{}') from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public'
          and p.proname not in ('binder_activity_begin','binder_activity_add_item','binder_activity_end','binder_activity_category',
                                'get_my_binder_activity','get_my_binder_activity_coverage','list_my_closed_binder_histories',
                                'purge_my_binder_activity','binder_activity_event_guard','binder_activity_item_guard')
          and pg_get_functiondef(p.oid) ~* 'binder_activity_')
       = array['binder_activity_add_card_item','binder_activity_add_reservation_item','clear_slot_expected_content',
               'move_slot_assignment','place_my_physical_card_in_slot','remove_slot_assignment',
               'set_slot_expected_content','set_slot_lock']
union all
select 'A.7', 'nenhum evento da S3 gravado pela instalação',
       not exists (select 1 from public.binder_activity_event
                   where event_type in ('POCKET_RESERVED','RESERVATIONS_RELEASED','POCKETS_LOCKED','POCKETS_UNLOCKED'));

-- BLOCO B — funcional (depois das operações reais do proprietário) ------------------------------
with e as (
  select ev.*, (select count(*) from public.binder_activity_item i where i.event_id = ev.id) as n,
         (select max(i.ordinal) from public.binder_activity_item i where i.event_id = ev.id) as mx
  from public.binder_activity_event ev
  where ev.event_type in ('POCKET_RESERVED','RESERVATIONS_RELEASED','POCKETS_LOCKED','POCKETS_UNLOCKED')
), it as (
  select i.*, ev.event_type from public.binder_activity_item i join e ev on ev.id = i.event_id
)
select 'B.1' as id, 'eventos S3 presentes por tipo: ' || coalesce((select string_agg(event_type || '=' || c, ', ' order by event_type)
        from (select event_type, count(*) c from e group by event_type) x), '-') as detail,
       (select count(distinct event_type) from e) = 4 as ok
union all
select 'B.2', 'todo evento: ator = titular, origem FICHARIO, ≥ 1 item, ordinais 1..n contíguos',
       not exists (select 1 from e where actor_user_id is distinct from owner_user_id or source <> 'FICHARIO' or n < 1 or mx <> n)
union all
select 'B.3', 'POCKET_RESERVED: 1 RESERVED com destino (novo) ou RELEASED+RESERVED no mesmo bolso (troca)',
       not exists (select 1 from e where event_type = 'POCKET_RESERVED' and not (
         (n = 1 and exists (select 1 from it where it.event_id = e.id and effect = 'RESERVED' and to_row is not null and from_page is null))
         or (n = 2 and exists (select 1 from it a join it b on b.event_id = a.event_id
                               where a.event_id = e.id and a.ordinal = 1 and b.ordinal = 2 and a.effect = 'RELEASED' and b.effect = 'RESERVED'
                                 and (a.from_page, a.from_row, a.from_col) = (b.to_page, b.to_row, b.to_col)))))
union all
select 'B.4', 'RESERVATIONS_RELEASED: só RELEASED, origem completa, sem destino, bolsos distintos',
       not exists (select 1 from it where event_type = 'RESERVATIONS_RELEASED' and (effect <> 'RELEASED' or from_row is null or to_page is not null))
       and not exists (select 1 from it where event_type = 'RESERVATIONS_RELEASED' group by event_id, from_page, from_row, from_col having count(*) > 1)
union all
select 'B.5', 'POCKETS_LOCKED/UNLOCKED: só LOCKED (destino) / UNLOCKED (origem), bolsos distintos, sem carta',
       not exists (select 1 from it where event_type = 'POCKETS_LOCKED' and (item_kind <> 'POCKET' or effect <> 'LOCKED' or to_row is null or from_page is not null or card_id is not null))
       and not exists (select 1 from it where event_type = 'POCKETS_UNLOCKED' and (item_kind <> 'POCKET' or effect <> 'UNLOCKED' or from_row is null or to_page is not null or card_id is not null))
       and not exists (select 1 from it where event_type in ('POCKETS_LOCKED','POCKETS_UNLOCKED')
                       group by event_id, coalesce(to_page, from_page), coalesce(to_row, from_row), coalesce(to_col, from_col) having count(*) > 1)
union all
select 'B.6', 'todo item de reserva: cópia do catálogo e coleção no detalhe',
       not exists (select 1 from it where item_kind = 'RESERVATION'
                   and (card_id is null or card_name is null or card_set_code is null or detail ->> 'collection_id' is null))
union all
select 'B.7 AMOSTRA', (select string_agg(x.linha, E'\n' order by x.id desc) from (
         select e.id, to_char(e.occurred_at at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI:SS') || ' · ' || e.event_type || ' · ' ||
                (select string_agg(i.effect || coalesce(' ' || i.card_name || ' ' || i.collector_number, '') ||
                         coalesce(' ' || i.variant_type_code, '') ||
                         coalesce(' de p' || i.from_page || ' l' || i.from_row || ' c' || i.from_col, '') ||
                         coalesce(' para p' || i.to_page || ' l' || i.to_row || ' c' || i.to_col, ''), ' | ' order by i.ordinal)
                 from public.binder_activity_item i where i.event_id = e.id) as linha
         from e order by e.id desc limit 20) x), true;
