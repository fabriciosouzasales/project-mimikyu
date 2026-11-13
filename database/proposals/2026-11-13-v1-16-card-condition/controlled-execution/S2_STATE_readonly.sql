/*
================================================================
V1-16 · S2 — estado SOMENTE LEITURA antes e depois da 5362
(`S2 CONTROLLED EXECUTION READINESS-01`, 2026-11-13)
Status.....: PREPARADO, NÃO EXECUTADO.
Natureza...: UMA instrução SELECT. Sem DML/DDL, sem set_config, sem trava de
             escrita, sem chamar funções da aplicação (só catálogo e
             contagens). Funciona antes (S1) e depois (S2) da 5362: as
             funções são lidas por to_regprocedure/pg_proc, nunca chamadas.
Uso........: rodar ANTES (S2-PRE) e DEPOIS (S2-POST) da 5362, junto com
             POSTCHECK_readonly.sql. Critérios em
             CONTROLLED-EXECUTION-PROTOCOL.md §12. Nenhuma linha identifica
             usuário.
================================================================
*/
with
fns(k, sig, md5_old, md5_new) as (
  values
    ('5153', 'public.bulk_register_physical_card_items(jsonb,uuid,uuid,uuid,text,uuid,text,text,uuid,bigint)',
             'a5fd5107cc008b68a6d598a1a0501a6e', '86426fc066009400748cfccdf1fbf322'),
    ('5155', 'public.register_physical_cards_bulk(jsonb)', '0b7221b6a2485ad75e2918365f515e0a', 'd08dcc259222a286d99bcd53f9da7285'),
    ('5157', 'public.register_card_set_bulk(jsonb)',       '1526fd4d633f29f91ddc5c49141eef59', '83cd76fcb38a41a3a2c0a77d36fa4196'),
    ('5158', 'public.preview_bulk_operation(jsonb)',       '8dcf2656676739b5417b94b4882bd26c', '99f7b2e2a723d599e06ef2e7ca9b1831'),
    ('VAL',  'public.physical_card_unknown_condition_codes(text[])', null, 'df223290a53ce5252808899fbb03da60')
),
meta as (
  select f.k, f.md5_old, f.md5_new, p.oid,
         md5(p.prosrc) as md5_now,
         pg_get_function_identity_arguments(p.oid) || ' -> ' || pg_get_function_result(p.oid)
         || ' | lang=' || l.lanname || ' secdef=' || p.prosecdef || ' vol=' || p.provolatile::text
         || ' cfg=' || coalesce(array_to_string(p.proconfig, ';'), '-') || ' owner=' || pg_get_userbyid(p.proowner)
         || ' acl=' || coalesce(array_to_string(p.proacl, ','), '(default)') as fingerprint
    from fns f
    left join pg_proc p on p.oid = to_regprocedure(f.sig)
    left join pg_language l on l.oid = p.prolang
),
checks(ord, verificacao, got, esperado) as (
  select row_number() over (order by k), 'F-' || k || ' identidade',
         case when oid is null then 'ausente'
              else case when md5_now = md5_old then 'md5=ANTIGO' when md5_now = md5_new then 'md5=NOVO(5362)' else 'md5=DIVERGENTE ' || md5_now end
                   || ' | ' || fingerprint end,
         case when k = 'VAL' then 'PRE: ausente · POST: md5=NOVO(5362) | p_codes text[] -> text[] | lang=sql secdef=false vol=s cfg=search_path="" owner=postgres acl sem anon/authenticated/service_role'
              else 'PRE: md5=ANTIGO · POST: md5=NOVO(5362); o restante da linha IDÊNTICO entre PRE e POST' end
    from meta
  union all
  select 10, 'F-10 EXECUTE por papel (RPCs públicas / internos)',
         concat_ws(' ',
           'auth[B1,B2,prev]=' || has_function_privilege('authenticated', 'public.register_physical_cards_bulk(jsonb)', 'EXECUTE')
                               || ',' || has_function_privilege('authenticated', 'public.register_card_set_bulk(jsonb)', 'EXECUTE')
                               || ',' || has_function_privilege('authenticated', 'public.preview_bulk_operation(jsonb)', 'EXECUTE'),
           'anon[B1,B2,prev]=' || has_function_privilege('anon', 'public.register_physical_cards_bulk(jsonb)', 'EXECUTE')
                               || ',' || has_function_privilege('anon', 'public.register_card_set_bulk(jsonb)', 'EXECUTE')
                               || ',' || has_function_privilege('anon', 'public.preview_bulk_operation(jsonb)', 'EXECUTE'),
           'service_role[B1,B2,prev]=' || has_function_privilege('service_role', 'public.register_physical_cards_bulk(jsonb)', 'EXECUTE')
                               || ',' || has_function_privilege('service_role', 'public.register_card_set_bulk(jsonb)', 'EXECUTE')
                               || ',' || has_function_privilege('service_role', 'public.preview_bulk_operation(jsonb)', 'EXECUTE'),
           'helper[auth,anon,svc]=' || has_function_privilege('authenticated', 'public.bulk_register_physical_card_items(jsonb,uuid,uuid,uuid,text,uuid,text,text,uuid,bigint)', 'EXECUTE')
                               || ',' || has_function_privilege('anon', 'public.bulk_register_physical_card_items(jsonb,uuid,uuid,uuid,text,uuid,text,text,uuid,bigint)', 'EXECUTE')
                               || ',' || has_function_privilege('service_role', 'public.bulk_register_physical_card_items(jsonb,uuid,uuid,uuid,text,uuid,text,text,uuid,bigint)', 'EXECUTE')),
         'auth[B1,B2,prev]=true,true,true anon[B1,B2,prev]=false,false,false service_role[B1,B2,prev]=false,false,false helper[auth,anon,svc]=false,false,false — PRE = POST'
  union all
  select 11, 'F-11 escala card_condition', (select string_agg(code || ':' || condition_order, ',' order by condition_order) from public.card_condition),
         'M:1,NM:2,LP:3,MP:4,HP:5,DMG:6 — PRE = POST'
  union all
  select 12, 'F-12 distribuição de condition_code em physical_card',
         coalesce((select string_agg(condition_code || '=' || n, ' ' order by condition_code)
                     from (select condition_code, count(*) as n from public.physical_card group by condition_code) s), '(vazio)'),
         'PRE: NM=<total> · POST: idêntico ao PRE (a 5362 não escreve exemplares)'
  union all
  select 13, 'F-13 physical_card / bulk_operation (contagem e últimos carimbos)',
         'physical_card=' || (select count(*) from public.physical_card)
         || ' max_created=' || coalesce((select max(created_at)::text from public.physical_card), '-')
         || ' max_updated=' || coalesce((select max(updated_at)::text from public.physical_card), '-')
         || ' | bulk_operation=' || (select count(*) from public.bulk_operation)
         || ' max_created=' || coalesce((select max(created_at)::text from public.bulk_operation), '-'),
         'POST = PRE (salvo uso legítimo do app no intervalo — então explicar)'
  union all
  select 14, 'F-14 domínios que a 5362 não pode tocar (contagens)',
         'slot_assignment=' || (select count(*) from public.collection_layout_slot_assignment)
         || ' slot_expected_content(reservas)=' || (select count(*) from public.collection_layout_slot_expected_content)
         || ' collection=' || (select count(*) from public.collection)
         || ' collection_allocation=' || (select count(*) from public.collection_allocation)
         || ' collection_membership=' || (select count(*) from public.collection_membership)
         || ' card_favorite=' || (select count(*) from public.card_favorite)
         || ' pokedex_species_favorite=' || (select count(*) from public.pokedex_species_favorite)
         || ' card_wishlist_entry=' || (select count(*) from public.card_wishlist_entry)
         || ' storage_container=' || (select count(*) from public.storage_container),
         'POST = PRE'
  union all
  select 15, 'F-15 preços (podem mudar por rotina agendada de Pricing, independente da 5362)',
         'pricing_observation=' || (select count(*) from public.pricing_observation)
         || ' pricing_manual_price=' || (select count(*) from public.pricing_manual_price)
         || ' pricing_condition_mapping=' || (select count(*) from public.pricing_condition_mapping),
         'pricing_condition_mapping POST = PRE; demais: INFO'
  union all
  select 16, 'F-16 sessões/travas pendentes (exceto esta)',
         'sessoes=' || (select count(*) from pg_stat_activity
                         where pid <> pg_backend_pid() and datname = current_database()
                           and (state like 'idle in transaction%' or (state = 'active' and xact_start < now() - interval '60 seconds')))
         || ' travas_fortes=' || (select count(*) from pg_locks l join pg_class c on c.oid = l.relation
                                   where l.pid <> pg_backend_pid() and c.relname in ('physical_card', 'bulk_operation', 'inventory')
                                     and l.mode not in ('AccessShareLock', 'RowShareLock', 'RowExclusiveLock')),
         'sessoes=0 travas_fortes=0'
)
select ord, verificacao, got, esperado from checks order by ord;
