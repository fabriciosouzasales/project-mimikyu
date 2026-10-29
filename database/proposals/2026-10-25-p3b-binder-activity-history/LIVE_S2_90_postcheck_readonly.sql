/*
================================================================
Projeto.....: Project Mimikyu
Arquivo.....: LIVE_S2_90_postcheck_readonly.sql — P3-B S2, depois de 5274
Versão......: 1.1 (2026-10-27, P3-B S2 — errata A.2: md5 esperados de 5272–5274 recalculados a partir
              do corpo entre `as $fn$` e `$fn$;`; a v1.0 os extraiu a partir do "$fn$" citado no
              cabeçalho de comentário, e os valores estavam errados. Instalação não afetada.)
              1.0 (2026-10-27, P3-B S2)
Status......: PROPOSTA. SÓ LEITURA. Dois blocos, cada um um SELECT.
  Bloco A (estrutural) — logo após a 5274. Esperado: ok = true em todas as linhas.
  Bloco B (funcional)  — depois que o proprietário fizer, pela interface, ao menos:
           colocar 1 carta (ADD), substituir 1 (REPLACE), mover 1 para bolso vazio,
           trocar 2 de lugar, retirar ≥ 2 cartas de uma vez e desfazer uma retirada.
           Esperado: ok = true em B.1–B.7; B.8 é a amostra para conferência visual.
================================================================
*/

-- BLOCO A — estrutural ------------------------------------------------------------------------
with f as (
  select p.oid, p.proname, p.prosecdef, p.proconfig, md5(p.prosrc) as m
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('binder_activity_add_card_item','place_my_physical_card_in_slot','move_slot_assignment','remove_slot_assignment')
)
select 'A.1' as id, 'ledger 5271–5274, na ordem' as detail,
       coalesce((select array_agg(name order by version) from supabase_migrations.schema_migrations where name ~ '^(5271|5272|5273|5274)_')
         = array['5271_create_binder_activity_add_card_item','5272_instrument_place_my_physical_card_in_slot',
                 '5273_instrument_move_slot_assignment','5274_instrument_remove_slot_assignment'], false) as ok
union all
select 'A.2', 'corpos iguais aos da proposta (md5 de prosrc)',
       (select m from f where proname = 'binder_activity_add_card_item') = 'c5f9b7bdfee614f96eec9fb415e5cbf1'
       and (select m from f where proname = 'place_my_physical_card_in_slot') = '2672da179d73797ec5329c649b594202'
       and (select m from f where proname = 'move_slot_assignment') = 'fe149c755b5f3b9181172e600c2238a3'
       and (select m from f where proname = 'remove_slot_assignment') = 'e4b6c8cd8e8c61554ddc92304d602a73'
union all
select 'A.3', 'helper interno: DEFINER, search_path vazio, sem EXECUTE para PUBLIC/anon/authenticated/service_role',
       coalesce((select prosecdef and proconfig @> array['search_path=""']
               and not has_function_privilege('anon', oid, 'EXECUTE')
               and not has_function_privilege('authenticated', oid, 'EXECUTE')
               and not has_function_privilege('service_role', oid, 'EXECUTE')
               and not exists (select 1 from aclexplode((select proacl from pg_proc where oid = f.oid)) x where x.grantee = 0)
        from f where proname = 'binder_activity_add_card_item'), false)
union all
select 'A.4', 'funções instrumentadas: DEFINER, SET preservados, EXECUTE só authenticated (sem anon/PUBLIC)',
       (select bool_and(prosecdef and proconfig @> array['search_path=""']
                        and has_function_privilege('authenticated', oid, 'EXECUTE')
                        and not has_function_privilege('anon', oid, 'EXECUTE')
                        and not exists (select 1 from aclexplode((select proacl from pg_proc q where q.oid = f.oid)) x where x.grantee = 0))
        from f where proname <> 'binder_activity_add_card_item')
       and (select proconfig @> array['lock_timeout=5s'] from f where proname = 'place_my_physical_card_in_slot')
union all
select 'A.5', 'assinaturas e retornos inalterados',
       pg_get_function_result('public.place_my_physical_card_in_slot(uuid, uuid, uuid)'::regprocedure)
         = 'TABLE(assignment_id uuid, slot_id uuid, physical_card_id uuid, operation text, replaced_physical_card_id uuid)'
       and pg_get_function_result('public.move_slot_assignment(uuid, uuid)'::regprocedure)
         = 'TABLE(operation text, assignment_id uuid, new_slot_id uuid, swapped_assignment_id uuid, swapped_new_slot_id uuid)'
       and pg_get_function_result('public.remove_slot_assignment(uuid[])'::regprocedure) = 'integer'
union all
select 'A.6', 'gate de cobertura (§7.3): fora da S1, só 5271–5274 referenciam o histórico',
       (select coalesce(array_agg(p.proname::text order by p.proname), '{}') from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public'
          and p.proname not in ('binder_activity_begin','binder_activity_add_item','binder_activity_end','binder_activity_category',
                                'get_my_binder_activity','get_my_binder_activity_coverage','list_my_closed_binder_histories',
                                'purge_my_binder_activity','binder_activity_event_guard','binder_activity_item_guard')
          and pg_get_functiondef(p.oid) ~* 'binder_activity_')
       = array['binder_activity_add_card_item','move_slot_assignment','place_my_physical_card_in_slot','remove_slot_assignment']
union all
select 'A.7', 'nenhum evento instrumentado gravado pela instalação (só legado)',
       not exists (select 1 from public.binder_activity_event where source <> 'LEGADO');

-- BLOCO B — funcional (depois das operações reais do proprietário) ------------------------------
with e as (
  select ev.*, (select count(*) from public.binder_activity_item i where i.event_id = ev.id) as n,
         (select max(i.ordinal) from public.binder_activity_item i where i.event_id = ev.id) as mx
  from public.binder_activity_event ev where ev.source <> 'LEGADO'
), it as (
  select i.*, ev.event_type from public.binder_activity_item i join e ev on ev.id = i.event_id
)
select 'B.1' as id, 'eventos S2 presentes por tipo: ' || coalesce((select string_agg(event_type || '=' || c, ', ' order by event_type)
        from (select event_type, count(*) c from e group by event_type) x), '-') as detail,
       (select count(distinct event_type) from e) = 4
       and not exists (select 1 from e where event_type not in ('CARD_PLACED','CARD_MOVED','CARDS_SWAPPED','CARDS_REMOVED')) as ok
union all
select 'B.2', 'todo evento: ator = titular, origem FICHARIO, ≥ 1 item, ordinais 1..n contíguos',
       not exists (select 1 from e where actor_user_id is distinct from owner_user_id or source <> 'FICHARIO' or n < 1 or mx <> n)
union all
select 'B.3', 'CARD_MOVED = 1 item MOVED com origem e destino completos e diferentes',
       not exists (select 1 from e where event_type = 'CARD_MOVED' and (n <> 1 or exists (
         select 1 from it where it.event_id = e.id and (effect <> 'MOVED' or from_row is null or to_row is null
           or (from_page, from_row, from_col) = (to_page, to_row, to_col)))))
union all
select 'B.4', 'CARDS_SWAPPED = 2 itens SWAPPED com posições recíprocas',
       not exists (select 1 from e where event_type = 'CARDS_SWAPPED' and (n <> 2 or not exists (
         select 1 from it a join it b on b.event_id = a.event_id and b.ordinal = 2
         where a.event_id = e.id and a.ordinal = 1 and a.effect = 'SWAPPED' and b.effect = 'SWAPPED'
           and (a.from_page, a.from_row, a.from_col) = (b.to_page, b.to_row, b.to_col)
           and (a.to_page, a.to_row, a.to_col) = (b.from_page, b.from_row, b.from_col))))
union all
select 'B.5', 'CARDS_REMOVED: só REMOVED, origem completa, sem destino, posições distintas',
       not exists (select 1 from it where event_type = 'CARDS_REMOVED' and (effect <> 'REMOVED' or from_row is null or to_page is not null))
       and not exists (select 1 from it where event_type = 'CARDS_REMOVED'
                       group by event_id, from_page, from_row, from_col having count(*) > 1)
union all
select 'B.6', 'CARD_PLACED: 1 PLACED com destino (ADD) ou REMOVED+PLACED no mesmo bolso (REPLACE)',
       not exists (select 1 from e where event_type = 'CARD_PLACED' and not (
         (n = 1 and exists (select 1 from it where it.event_id = e.id and effect = 'PLACED' and to_row is not null and from_page is null))
         or (n = 2 and exists (select 1 from it a join it b on b.event_id = a.event_id
                               where a.event_id = e.id and a.ordinal = 1 and b.ordinal = 2 and a.effect = 'REMOVED' and b.effect = 'PLACED'
                                 and (a.from_page, a.from_row, a.from_col) = (b.to_page, b.to_row, b.to_col)))))
union all
select 'B.7', 'todo item de carta: cópia do catálogo e physical_card_id no detalhe',
       not exists (select 1 from it where item_kind <> 'CARD' or card_id is null or card_name is null or card_set_code is null
                   or variant_type_code is null or detail ->> 'physical_card_id' is null)
union all
select 'B.8 AMOSTRA', (select string_agg(x.linha, E'\n' order by x.id desc) from (
         select e.id, to_char(e.occurred_at at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI:SS') || ' · ' || e.event_type || ' · ' ||
                (select string_agg(i.effect || ' ' || i.card_name || ' ' || i.collector_number || ' ' || coalesce(i.variant_type_code, '') ||
                         coalesce(' de p' || i.from_page || ' l' || i.from_row || ' c' || i.from_col, '') ||
                         coalesce(' para p' || i.to_page || ' l' || i.to_row || ' c' || i.to_col, ''), ' | ' order by i.ordinal)
                 from public.binder_activity_item i where i.event_id = e.id) as linha
         from e order by e.id desc limit 20) x), true;
