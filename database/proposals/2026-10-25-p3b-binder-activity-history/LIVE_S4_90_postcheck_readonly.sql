/*
================================================================
Projeto.....: Project Mimikyu
Arquivo.....: LIVE_S4_90_postcheck_readonly.sql — P3-B S4, depois de 5284
Versão......: 1.0 (2026-10-27, P3-B S4)
Status......: PROPOSTA. SÓ LEITURA. Dois blocos, cada um um SELECT.
  Bloco A (estrutural) — logo após a 5284. Esperado: ok = true em todas as linhas.
  Bloco B (funcional)  — depois que o proprietário fizer, pela interface: adicionar 2 páginas;
           abrir espaço com deslocamento simples; abrir espaço que exija página nova e desfazê-lo
           (fechar); reordenar páginas. Esperado: ok = true em B.1–B.9; B.10 é a amostra.
  md5 esperados (A.2) calculados do corpo entre `as $fn$` e `$fn$;` de cada arquivo.
================================================================
*/

-- BLOCO A — estrutural ------------------------------------------------------------------------
with f as (
  select p.oid, p.proname, p.oid::regprocedure::text as sig, p.prosecdef, p.proconfig, md5(p.prosrc) as m
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('binder_activity_add_pocket_shift_items','add_layout_page','remove_layout_page','reorder_layout_pages',
                      'insert_my_binder_gap','close_my_binder_gap','binder_gap_move_pocket')
)
select 'A.1' as id, 'ledger 5279–5284, na ordem' as detail,
       coalesce((select array_agg(name order by version) from supabase_migrations.schema_migrations where name ~ '^(5279|5280|5281|5282|5283|5284)_')
         = array['5279_create_binder_activity_add_pocket_shift_items','5280_instrument_add_layout_page','5281_instrument_remove_layout_page',
                 '5282_instrument_reorder_layout_pages','5283_instrument_insert_my_binder_gap','5284_instrument_close_my_binder_gap'], false) as ok
union all
select 'A.2', 'corpos iguais aos da proposta (md5 de prosrc); invólucro e binder_gap_move_pocket inalterados',
       (select m from f where proname = 'binder_activity_add_pocket_shift_items') = '4d84fc04ec1b453043e8fbf6e55950b7'
       and (select m from f where proname = 'add_layout_page') = '9df4f0978e7dcc4f940567a4f6aae12f'
       and (select m from f where sig = 'remove_layout_page(uuid,integer)') = '5ea978d582f055fb8690f9974a2bea2f'
       and (select m from f where sig = 'remove_layout_page(uuid)') = '98736e42641bb8a592f2d8e4fd40fab1'
       and (select m from f where proname = 'reorder_layout_pages') = '5e2afe5ae5fa24bd9c1d51ff0808bf30'
       and (select m from f where proname = 'insert_my_binder_gap') = 'c76e6881dd2a40126c03b86e717904ad'
       and (select m from f where proname = 'close_my_binder_gap') = 'd6b4d852a008f3a582e59f4ab9045885'
       and (select m from f where proname = 'binder_gap_move_pocket') = 'ea19694de441a7a2d2ac6e63813d5035'
union all
select 'A.3', 'helper interno: DEFINER, search_path vazio, sem EXECUTE para PUBLIC/anon/authenticated/service_role',
       coalesce((select prosecdef and proconfig @> array['search_path=""']
               and not has_function_privilege('anon', oid, 'EXECUTE')
               and not has_function_privilege('authenticated', oid, 'EXECUTE')
               and not has_function_privilege('service_role', oid, 'EXECUTE')
               and not exists (select 1 from aclexplode((select proacl from pg_proc where oid = f.oid)) x where x.grantee = 0)
        from f where proname = 'binder_activity_add_pocket_shift_items'), false)
union all
select 'A.4', 'instrumentadas: DEFINER, search_path vazio, EXECUTE só authenticated (sem anon/PUBLIC)',
       (select bool_and(prosecdef and proconfig @> array['search_path=""']
                        and has_function_privilege('authenticated', oid, 'EXECUTE')
                        and not has_function_privilege('anon', oid, 'EXECUTE')
                        and not exists (select 1 from aclexplode((select proacl from pg_proc q where q.oid = f.oid)) x where x.grantee = 0))
        from f where proname in ('add_layout_page','remove_layout_page','reorder_layout_pages','insert_my_binder_gap','close_my_binder_gap'))
       and (select bool_and(proconfig @> array['lock_timeout=5s']) from f where proname in ('insert_my_binder_gap','close_my_binder_gap'))
union all
select 'A.5', 'assinaturas e retornos inalterados',
       pg_get_function_result('public.add_layout_page(uuid)'::regprocedure) = 'TABLE(id uuid, layout_id uuid, page_number integer, slots_created integer)'
       and pg_get_function_result('public.remove_layout_page(uuid, integer)'::regprocedure) = 'void'
       and pg_get_function_result('public.reorder_layout_pages(uuid, uuid[])'::regprocedure) = 'TABLE(id uuid, page_number integer)'
       and pg_get_function_result('public.insert_my_binder_gap(uuid, uuid, text, boolean, boolean)'::regprocedure)
           = 'TABLE(outcome text, gap_slot_id uuid, end_slot_id uuid, added_page_id uuid, moved_pockets integer, rows_moved integer, pages integer[], undo_token text)'
       and pg_get_function_result('public.close_my_binder_gap(uuid, uuid, uuid, text, uuid)'::regprocedure)
           = 'TABLE(outcome text, moved_pockets integer, rows_moved integer, page_removed boolean)'
union all
select 'A.6', 'gate de cobertura (§7.3): fora da S1, só S2 + S3 + S4 referenciam o histórico',
       (select coalesce(array_agg(p.proname::text order by p.proname), '{}') from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public'
          and p.proname not in ('binder_activity_begin','binder_activity_add_item','binder_activity_end','binder_activity_category',
                                'get_my_binder_activity','get_my_binder_activity_coverage','list_my_closed_binder_histories',
                                'purge_my_binder_activity','binder_activity_event_guard','binder_activity_item_guard')
          and pg_get_functiondef(p.oid) ~* 'binder_activity_')
       = array['add_layout_page','binder_activity_add_card_item','binder_activity_add_pocket_shift_items','binder_activity_add_reservation_item',
               'clear_slot_expected_content','close_my_binder_gap','insert_my_binder_gap','move_slot_assignment',
               'place_my_physical_card_in_slot','remove_layout_page','remove_slot_assignment','reorder_layout_pages',
               'set_slot_expected_content','set_slot_lock']
union all
select 'A.7', 'nenhum evento da S4 gravado pela instalação',
       not exists (select 1 from public.binder_activity_event
                   where event_type in ('GAP_OPENED','GAP_CLOSED','PAGES_ADDED','PAGE_REMOVED','PAGES_REORDERED'));

-- BLOCO B — funcional (depois das operações reais do proprietário) ------------------------------
with e as (
  select ev.*, (select count(*) from public.binder_activity_item i where i.event_id = ev.id) as n,
         (select max(i.ordinal) from public.binder_activity_item i where i.event_id = ev.id) as mx
  from public.binder_activity_event ev
  where ev.event_type in ('GAP_OPENED','GAP_CLOSED','PAGES_ADDED','PAGE_REMOVED','PAGES_REORDERED')
), it as (
  select i.*, ev.event_type from public.binder_activity_item i join e ev on ev.id = i.event_id
)
select 'B.1' as id, 'eventos S4 por tipo: ' || coalesce((select string_agg(event_type || '=' || c, ', ' order by event_type)
        from (select event_type, count(*) c from e group by event_type) x), '-') as detail,
       (select count(distinct event_type) from e where event_type in ('GAP_OPENED','GAP_CLOSED','PAGES_ADDED','PAGES_REORDERED')) = 4 as ok
union all
select 'B.2', 'todo evento: ator = titular, origem FICHARIO, ≥ 1 item, ordinais 1..n contíguos',
       not exists (select 1 from e where actor_user_id is distinct from owner_user_id or source <> 'FICHARIO' or n < 1 or mx <> n)
union all
select 'B.3', 'PAGES_ADDED: exatamente 1 PAGE/PAGE_ADDED com destino de página e sem origem',
       not exists (select 1 from e where event_type = 'PAGES_ADDED' and not (n = 1 and exists (
         select 1 from it where it.event_id = e.id and item_kind = 'PAGE' and effect = 'PAGE_ADDED' and to_page is not null and from_page is null and to_row is null)))
union all
select 'B.4', 'PAGES_REORDERED: só PAGE_RENUMBERED, origem ≠ destino, sem página repetida',
       not exists (select 1 from it where event_type = 'PAGES_REORDERED'
                   and (item_kind <> 'PAGE' or effect <> 'PAGE_RENUMBERED' or from_page is null or to_page is null or from_page = to_page))
       and not exists (select 1 from it where event_type = 'PAGES_REORDERED' group by event_id, from_page having count(*) > 1)
       and not exists (select 1 from it where event_type = 'PAGES_REORDERED' group by event_id, to_page having count(*) > 1)
union all
select 'B.5', 'GAP_OPENED: ≥ 1 SHIFTED; SHIFTED com origem e destino de bolso distintos; ≤ 1 PAGE_ADDED; sem objeto repetido',
       not exists (select 1 from e where event_type = 'GAP_OPENED' and not exists (select 1 from it where it.event_id = e.id and effect = 'SHIFTED'))
       and not exists (select 1 from it where event_type = 'GAP_OPENED' and not (
             (effect = 'SHIFTED' and item_kind in ('CARD','RESERVATION','POCKET') and from_row is not null and to_row is not null
              and (from_page, from_row, from_col) <> (to_page, to_row, to_col))
          or (item_kind = 'PAGE' and effect = 'PAGE_ADDED' and to_page is not null)))
       and not exists (select 1 from it where event_type = 'GAP_OPENED' and effect = 'PAGE_ADDED' group by event_id having count(*) > 1)
       and not exists (select 1 from it where event_type = 'GAP_OPENED' and effect = 'SHIFTED'
                       group by event_id, item_kind, from_page, from_row, from_col having count(*) > 1)
union all
select 'B.6', 'GAP_CLOSED: SHIFTED válidos; página removida embutida (≤ 1 PAGE_REMOVED) depois dos deslocamentos',
       not exists (select 1 from it where event_type = 'GAP_CLOSED' and not (
             (effect = 'SHIFTED' and item_kind in ('CARD','RESERVATION','POCKET') and from_row is not null and to_row is not null
              and (from_page, from_row, from_col) <> (to_page, to_row, to_col))
          or (item_kind = 'PAGE' and effect in ('PAGE_REMOVED','PAGE_RENUMBERED') and from_page is not null)))
       and not exists (select 1 from it where event_type = 'GAP_CLOSED' and effect = 'PAGE_REMOVED' group by event_id having count(*) > 1)
       and not exists (select 1 from it a join it b on b.event_id = a.event_id
                       where a.event_type = 'GAP_CLOSED' and a.item_kind = 'PAGE' and b.effect = 'SHIFTED' and b.ordinal > a.ordinal)
union all
select 'B.7', 'R5: nenhum evento de página independente na mesma transação de um espaço aberto/fechado',
       not exists (select 1 from e a join e b on b.created_xact = a.created_xact and b.id <> a.id
                   where a.event_type in ('GAP_OPENED','GAP_CLOSED') and b.event_type in ('PAGES_ADDED','PAGE_REMOVED'))
union all
select 'B.8', 'itens de carta com cópia do catálogo; reserva com carta; imagem marcada',
       not exists (select 1 from it where (item_kind = 'CARD' and (card_id is null or card_name is null or detail ->> 'physical_card_id' is null))
                                       or (item_kind = 'RESERVATION' and (card_id is null or card_name is null))
                                       or (item_kind = 'POCKET' and effect = 'SHIFTED' and detail ->> 'content' is distinct from 'IMAGE'))
union all
select 'B.9', 'PAGE_REMOVED independente (se houver): 1 PAGE_REMOVED e só renumerações',
       not exists (select 1 from e where event_type = 'PAGE_REMOVED' and (
         (select count(*) from it where it.event_id = e.id and effect = 'PAGE_REMOVED') <> 1
         or exists (select 1 from it where it.event_id = e.id and effect not in ('PAGE_REMOVED','PAGE_RENUMBERED'))))
union all
select 'B.10 AMOSTRA', (select string_agg(x.linha, E'\n' order by x.id desc) from (
         select e.id, to_char(e.occurred_at at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI:SS') || ' · ' || e.event_type || ' · ' || e.n || ' itens · ' ||
                (select string_agg(i.item_kind || '/' || i.effect || coalesce(' ' || i.card_name, '') ||
                         coalesce(' de p' || i.from_page || coalesce(' l' || i.from_row || ' c' || i.from_col, ''), '') ||
                         coalesce(' para p' || i.to_page || coalesce(' l' || i.to_row || ' c' || i.to_col, ''), ''), ' | ' order by i.ordinal)
                 from (select * from public.binder_activity_item i0 where i0.event_id = e.id order by i0.ordinal limit 6) i) as linha
         from e order by e.id desc limit 20) x), true;
