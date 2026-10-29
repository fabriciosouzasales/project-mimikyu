/*
================================================================
Projeto.....: Project Mimikyu
Arquivo.....: LIVE_S5_90_postcheck_readonly.sql — P3-B S5, depois de 5289
Versão......: 1.0 (2026-10-28, P3-B S5)
Status......: PROPOSTA. SÓ LEITURA. Dois blocos, cada um um SELECT.
  Bloco A (estrutural) — logo após a 5289. Esperado: ok = true em todas as linhas.
  Bloco B (funcional)  — depois que o proprietário fizer, pela interface:
           E06a  Meu acervo → mover para outro local ≥ 2 exemplares que estão no fichário
                 (confirmando a saída dos bolsos);
           E06b  Coleção → Organizar armazenamento com exemplares posicionados (confirmando);
           E07   Meu acervo → remover um exemplar sem coleção que ainda ocupa um bolso.
           Esperado: ok = true em B.1–B.7; B.8 é a amostra.
  md5 esperados (A.2) calculados do corpo entre `as $fn$` e `$fn$;` de cada arquivo.
================================================================
*/

-- BLOCO A — estrutural ------------------------------------------------------------------------
with f as (
  select p.oid, p.proname, p.oid::regprocedure::text as sig, p.prosecdef, p.proconfig, md5(p.prosrc) as m
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('set_physical_cards_storage','organize_my_collection_storage','remove_my_physical_card')
)
select 'A.1' as id, 'ledger 5287–5289, na ordem, depois da 5286' as detail,
       coalesce((select array_agg(name order by version desc) from (select version, name from supabase_migrations.schema_migrations order by version desc limit 4) x)
         = array['5289_instrument_remove_my_physical_card','5288_instrument_organize_my_collection_storage',
                 '5287_instrument_set_physical_cards_storage','5286_harden_remove_layout_page'], false) as ok
union all
select 'A.2', 'corpos iguais aos da proposta (md5 de prosrc); sobrecargas antigas inalteradas',
       (select m from f where sig = 'set_physical_cards_storage(uuid,uuid[],boolean)') = '09e342a1fc65b6eb588dc9784f20034d'
       and (select m from f where sig = 'organize_my_collection_storage(uuid,uuid,text,integer,text,boolean)') = '26ea92ac712d103ff21856e779b94ef2'
       and (select m from f where sig = 'remove_my_physical_card(uuid)') = 'd51b9264381b5e1623fe186d7dec67a3'
       and (select m from f where sig = 'set_physical_cards_storage(uuid,uuid[])') = 'cf8d15bcbd1f0842541bfac99be3eb72'
       and (select m from f where sig = 'organize_my_collection_storage(uuid,uuid,text,integer,text)') = '595e5229051e4dc6e16a1c9e484a6e9b'
union all
select 'A.3', 'instrumentadas: DEFINER, search_path vazio, EXECUTE só authenticated (sem anon/PUBLIC); lock_timeout preservado',
       (select bool_and(prosecdef and proconfig @> array['search_path=""']
                        and has_function_privilege('authenticated', oid, 'EXECUTE')
                        and not has_function_privilege('anon', oid, 'EXECUTE')
                        and not exists (select 1 from aclexplode((select proacl from pg_proc q where q.oid = f.oid)) x where x.grantee = 0))
        from f where sig in ('set_physical_cards_storage(uuid,uuid[],boolean)','organize_my_collection_storage(uuid,uuid,text,integer,text,boolean)',
                             'remove_my_physical_card(uuid)'))
       and (select bool_and(proconfig @> array['lock_timeout=5s']) from f
            where sig in ('set_physical_cards_storage(uuid,uuid[],boolean)','organize_my_collection_storage(uuid,uuid,text,integer,text,boolean)'))
union all
select 'A.4', 'assinaturas e retornos inalterados',
       pg_get_function_result('public.set_physical_cards_storage(uuid, uuid[], boolean)'::regprocedure)
           = 'TABLE(id uuid, storage_container_id uuid, updated_at timestamp with time zone)'
       and pg_get_function_result('public.organize_my_collection_storage(uuid, uuid, text, integer, text, boolean)'::regprocedure)
           = 'TABLE(collection_id uuid, storage_container_id uuid, mode text, moved_count integer, total_count integer, at_target_count integer)'
       and pg_get_function_result('public.remove_my_physical_card(uuid)'::regprocedure) = 'boolean'
union all
select 'A.5', 'gate de cobertura (§7.3): fora da S1, só S2 + S3 + S4 + S5 referenciam o histórico',
       (select coalesce(array_agg(p.proname::text order by p.proname), '{}') from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public'
          and p.proname not in ('binder_activity_begin','binder_activity_add_item','binder_activity_end','binder_activity_category',
                                'get_my_binder_activity','get_my_binder_activity_coverage','list_my_closed_binder_histories',
                                'purge_my_binder_activity','binder_activity_event_guard','binder_activity_item_guard')
          and pg_get_functiondef(p.oid) ~* 'binder_activity_')
       = array['add_layout_page','binder_activity_add_card_item','binder_activity_add_pocket_shift_items','binder_activity_add_reservation_item',
               'clear_slot_expected_content','close_my_binder_gap','insert_my_binder_gap','move_slot_assignment',
               'organize_my_collection_storage','place_my_physical_card_in_slot','remove_layout_page','remove_my_physical_card',
               'remove_slot_assignment','reorder_layout_pages','set_physical_cards_storage','set_slot_expected_content','set_slot_lock']
union all
select 'A.6', 'nenhum evento da S5 gravado pela instalação',
       not exists (select 1 from public.binder_activity_event
                   where event_type in ('CARDS_LEFT_BY_STORAGE','CARDS_LEFT_BY_COLLECTION_STORAGE','CARD_LEFT_BY_INVENTORY_EXIT'))
union all
select 'A.7', 'guarda 5256 continua ativa (sobrecargas antigas seguem sem poder tirar carta de bolso)',
       exists (select 1 from pg_trigger where tgname = 'trg_physical_card_binder_position_guard'
               and tgrelid = 'public.physical_card'::regclass and tgenabled = 'O');

-- BLOCO B — funcional (depois das operações reais do proprietário) ------------------------------
with e as (
  select ev.*, (select count(*) from public.binder_activity_item i where i.event_id = ev.id) as n,
         (select max(i.ordinal) from public.binder_activity_item i where i.event_id = ev.id) as mx
  from public.binder_activity_event ev
  where ev.event_type in ('CARDS_LEFT_BY_STORAGE','CARDS_LEFT_BY_COLLECTION_STORAGE','CARD_LEFT_BY_INVENTORY_EXIT')
), it as (
  select i.*, ev.event_type, ev.created_xact from public.binder_activity_item i join e ev on ev.id = i.event_id
)
select 'B.1' as id, 'eventos S5 por tipo: ' || coalesce((select string_agg(event_type || '=' || c, ', ' order by event_type)
        from (select event_type, count(*) c from e group by event_type) x), '-') as detail,
       (select count(distinct event_type) from e) = 3 as ok
union all
select 'B.2', 'todo evento: ator = titular, origem coerente com o tipo, ≥ 1 item, ordinais 1..n contíguos',
       not exists (select 1 from e where actor_user_id is distinct from owner_user_id or n < 1 or mx <> n
                   or source <> case event_type when 'CARDS_LEFT_BY_COLLECTION_STORAGE' then 'COLECAO' else 'ACERVO' end)
union all
select 'B.3', 'itens: só CARD/LEFT, com bolso de origem e sem destino; cópia da carta e exemplar no detalhe',
       not exists (select 1 from it where item_kind <> 'CARD' or effect <> 'LEFT' or from_row is null or from_col is null
                   or to_page is not null or card_id is null or card_name is null or detail ->> 'physical_card_id' is null)
union all
select 'B.4', 'resumos: E06a/E06b com o destino; E06b com a coleção organizada; E07 com 1 item',
       not exists (select 1 from e where event_type in ('CARDS_LEFT_BY_STORAGE','CARDS_LEFT_BY_COLLECTION_STORAGE') and not (summary ? 'storage_container_id'))
       and not exists (select 1 from e where event_type = 'CARDS_LEFT_BY_COLLECTION_STORAGE' and collection_id is null)
       and not exists (select 1 from e where event_type = 'CARD_LEFT_BY_INVENTORY_EXIT' and n <> 1)
union all
select 'B.5', 'sem duplicidade: um item por exemplar no evento; um evento por fichário na mesma transação',
       not exists (select 1 from it group by event_id, detail ->> 'physical_card_id' having count(*) > 1)
       and not exists (select 1 from e group by created_xact, layout_key, event_type having count(*) > 1)
union all
select 'B.6', 'E07: o exemplar registrado não existe mais (saiu do acervo)',
       not exists (select 1 from it where event_type = 'CARD_LEFT_BY_INVENTORY_EXIT'
                   and exists (select 1 from public.physical_card pc where pc.id = (it.detail ->> 'physical_card_id')::uuid))
union all
select 'B.7', 'E06: nenhum outro evento de bolso na mesma transação (a saída por local não é registrada em dobro como E05)',
       not exists (select 1 from e a join public.binder_activity_event b on b.created_xact = a.created_xact and b.id <> a.id
                   where a.event_type in ('CARDS_LEFT_BY_STORAGE','CARDS_LEFT_BY_COLLECTION_STORAGE')
                     and b.event_type not in ('CARDS_LEFT_BY_STORAGE','CARDS_LEFT_BY_COLLECTION_STORAGE'))
union all
select 'B.8 AMOSTRA', (select string_agg(x.linha, E'\n' order by x.id desc) from (
         select e.id, to_char(e.occurred_at at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI:SS') || ' · ' || e.event_type || ' · ' || e.source
                || ' · ' || e.n || ' itens · ' || coalesce(e.summary ->> 'storage_container_name', '-') || ' · ' ||
                (select string_agg(i.card_name || ' de p' || i.from_page || ' l' || i.from_row || ' c' || i.from_col, ' | ' order by i.ordinal)
                 from (select * from public.binder_activity_item i0 where i0.event_id = e.id order by i0.ordinal limit 6) i) as linha
         from e order by e.id desc limit 20) x), true;
