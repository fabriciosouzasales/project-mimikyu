/*
================================================================
V1-16 · POSTCHECK — SOMENTE LEITURA, reutilizado depois de CADA etapa e de
CADA harness (CONTROLLED EXECUTION READINESS-01).
Status.....: PREPARADO, NÃO EXECUTADO.
Natureza...: UMA única instrução SELECT; não escreve nem trava linhas.
Canal......: SQL Editor ou psql com PGOPTIONS='-c default_transaction_read_only=on'.
Uso........: P-01 informa o ESTÁGIO detectado (S0…S4 ou DIVERGENTE) a partir
             do estado real; P-12 tem o MESMO formato de S0-14 e deve ser
             idêntico ao baseline (zero resíduo); P-14/P-15 mostram transação
             ou trava deixada para trás. Os valores esperados por etapa estão
             em CONTROLLED-EXECUTION-PROTOCOL.md §5.
================================================================
*/
with
st as (
  select
    exists (select 1 from pg_attribute where attrelid = 'public.physical_card'::regclass
             and attname = 'condition_code' and not attisdropped)                                    as col,
    (select convalidated from pg_constraint where conname = 'fk_physical_card_condition_code')       as fk_valid,
    (select md5(prosrc) from pg_proc where oid = to_regprocedure('public.bulk_register_physical_card_items(jsonb,uuid,uuid,uuid,text,uuid,text,text,uuid,bigint)')) as m5153,
    (select md5(prosrc) from pg_proc where oid = to_regprocedure('public.register_physical_cards_bulk(jsonb)'))   as m5155,
    (select md5(prosrc) from pg_proc where oid = to_regprocedure('public.register_card_set_bulk(jsonb)'))         as m5157,
    (select md5(prosrc) from pg_proc where oid = to_regprocedure('public.preview_bulk_operation(jsonb)'))         as m5158,
    (select md5(prosrc) from pg_proc where oid = to_regprocedure('public.get_my_inventory_item_copies(uuid,text)')) as mgmic,
    (select md5(prosrc) from pg_proc where oid = to_regprocedure('public.physical_card_unknown_condition_codes(text[])')) as mval,
    (select md5(prosrc) from pg_proc where oid = to_regprocedure('public.set_my_physical_cards_condition(uuid[],text)')) as mscmc
),
stage as (
  select st.*,
    (m5153 = 'a5fd5107cc008b68a6d598a1a0501a6e' and m5155 = '0b7221b6a2485ad75e2918365f515e0a'
     and m5157 = '1526fd4d633f29f91ddc5c49141eef59' and m5158 = '8dcf2656676739b5417b94b4882bd26c') as bulk_old,
    (m5153 = '86426fc066009400748cfccdf1fbf322' and m5155 = 'd08dcc259222a286d99bcd53f9da7285'
     and m5157 = '83cd76fcb38a41a3a2c0a77d36fa4196' and m5158 = '99f7b2e2a723d599e06ef2e7ca9b1831') as bulk_new
  from st
),
detected as (
  select s.*,
    case
      when not col and fk_valid is null and bulk_old and mgmic = 'd8cce43b511856a5e25f061e75a7cede' and mval is null and mscmc is null then 'S0 (nada aplicado)'
      when col and fk_valid and bulk_old and mgmic = 'd8cce43b511856a5e25f061e75a7cede' and mval is null and mscmc is null then 'S1 (5361)'
      when col and fk_valid and bulk_new and mval is not null and mgmic = 'd8cce43b511856a5e25f061e75a7cede' and mscmc is null then 'S2 (5361+5362)'
      when col and fk_valid and bulk_new and mval is not null and mgmic = '77abbb9a33f2cb46280925bade22dee5' and mscmc is null then 'S3 (5361–5363)'
      when col and fk_valid and bulk_new and mval is not null and mgmic = '77abbb9a33f2cb46280925bade22dee5' and mscmc = 'b569ecdbe202428a6bdc9461c6d62e37' then 'S4 (5361–5364)'
      else 'DIVERGENTE'
    end as estagio
  from stage s
),
rows(ord, verificacao, got) as (
  select 1, 'P-01 estágio detectado', estagio from detected
  union all
  select 2, 'P-02 coluna condition_code / FK validada',
         'coluna=' || case when col then 'presente' else 'ausente' end || ' fk=' || coalesce(fk_valid::text, 'ausente') from detected
  union all
  select 3, 'P-03 exemplares com condição diferente de NM',
         case when col then (select count(*) from public.physical_card
                              where (to_jsonb(physical_card) ->> 'condition_code') is distinct from 'NM')::text
              else 'n/a (coluna ausente)' end from detected
  union all
  select 4, 'P-04 md5 família Bulk (5153,5155,5157,5158)',
         case when bulk_old then 'CANÔNICO (antes da 5362)' when bulk_new then 'V1-16 (5362)' else 'DIVERGENTE: '
              || coalesce(m5153, '-') || ',' || coalesce(m5155, '-') || ',' || coalesce(m5157, '-') || ',' || coalesce(m5158, '-') end
    from detected
  union all
  select 5, 'P-05 get_my_inventory_item_copies',
         case mgmic when 'd8cce43b511856a5e25f061e75a7cede' then '5262 (20 colunas)'
                    when '77abbb9a33f2cb46280925bade22dee5' then '5363 (21 colunas, condition_code)'
                    else 'DIVERGENTE: ' || coalesce(mgmic, 'ausente') end
         || ' | retorno termina em: ' || coalesce(right(pg_get_function_result(to_regprocedure('public.get_my_inventory_item_copies(uuid,text)')), 40), '-')
    from detected
  union all
  select 6, 'P-06 physical_card_unknown_condition_codes', coalesce(mval, 'ausente') from detected
  union all
  select 7, 'P-07 set_my_physical_cards_condition', coalesce(mscmc, 'ausente') from detected
  union all
  select 8, 'P-08 EXECUTE de authenticated (B1 / B2 / Preview / leitura / edição)',
         concat_ws(' ',
           'B1=' || has_function_privilege('authenticated', 'public.register_physical_cards_bulk(jsonb)', 'EXECUTE'),
           'B2=' || has_function_privilege('authenticated', 'public.register_card_set_bulk(jsonb)', 'EXECUTE'),
           'preview=' || has_function_privilege('authenticated', 'public.preview_bulk_operation(jsonb)', 'EXECUTE'),
           'leitura=' || has_function_privilege('authenticated', 'public.get_my_inventory_item_copies(uuid,text)', 'EXECUTE'),
           'edicao=' || case when mscmc is null then 'n/a' else has_function_privilege('authenticated', 'public.set_my_physical_cards_condition(uuid[],text)', 'EXECUTE')::text end)
    from detected
  union all
  select 9, 'P-09 nada executável por anon; internos fechados a clientes',
         concat_ws(' ',
           'anon_B1=' || has_function_privilege('anon', 'public.register_physical_cards_bulk(jsonb)', 'EXECUTE'),
           'anon_B2=' || has_function_privilege('anon', 'public.register_card_set_bulk(jsonb)', 'EXECUTE'),
           'anon_preview=' || has_function_privilege('anon', 'public.preview_bulk_operation(jsonb)', 'EXECUTE'),
           'anon_leitura=' || has_function_privilege('anon', 'public.get_my_inventory_item_copies(uuid,text)', 'EXECUTE'),
           'anon_edicao=' || case when mscmc is null then 'n/a' else has_function_privilege('anon', 'public.set_my_physical_cards_condition(uuid[],text)', 'EXECUTE')::text end,
           'auth_helper=' || has_function_privilege('authenticated', 'public.bulk_register_physical_card_items(jsonb,uuid,uuid,uuid,text,uuid,text,text,uuid,bigint)', 'EXECUTE'),
           'auth_validacao=' || case when mval is null then 'n/a' else has_function_privilege('authenticated', 'public.physical_card_unknown_condition_codes(text[])', 'EXECUTE')::text end)
    from detected
  union all
  select 10, 'P-10 RLS de physical_card e políticas de escrita',
         'rls=' || (select relrowsecurity from pg_class where oid = 'public.physical_card'::regclass)
         || ' politicas_escrita=' || (select count(*) from pg_policies where schemaname = 'public' and tablename = 'physical_card'
                                       and cmd in ('INSERT', 'UPDATE', 'DELETE', 'ALL'))
  union all
  select 11, 'P-11 resíduo sintético (ZZ% / %HARNESS%)',
         'expansion=' || (select count(*) from public.expansion where code like 'ZZ%')
         || ' card_set=' || (select count(*) from public.card_set where code like 'ZZ%')
         || ' collection=' || (select count(*) from public.collection where name like '%HARNESS%')
  union all
  select 12, 'P-12 contagens (mesmo formato de S0-14; igual ao baseline)',
         'physical_card=' || (select count(*) from public.physical_card)
         || ' with_storage=' || (select count(*) from public.physical_card where storage_container_id is not null)
         || ' collection_allocation=' || (select count(*) from public.collection_allocation)
         || ' bulk_operation=' || (select count(*) from public.bulk_operation)
         || ' inventory=' || (select count(*) from public.inventory)
         || ' collection=' || (select count(*) from public.collection)
         || ' collection_reference=' || (select count(*) from public.collection_reference)
         || ' collection_card_set_reference=' || (select count(*) from public.collection_card_set_reference)
         || ' storage_container=' || (select count(*) from public.storage_container)
         || ' expansion=' || (select count(*) from public.expansion)
         || ' card_set=' || (select count(*) from public.card_set)
         || ' card=' || (select count(*) from public.card)
         || ' card_variant=' || (select count(*) from public.card_variant)
  union all
  select 13, 'P-13 variantes inativas (igual ao POSTCHECK de baseline)',
         'card_variant_inativas=' || (select count(*) from public.card_variant where not is_active)
  union all
  select 14, 'P-14 sessões em transação (idle in transaction / aberta > 60 s), exceto esta',
         coalesce((select string_agg('pid=' || pid || ' estado=' || state || ' idade=' || date_trunc('second', now() - xact_start)
                                     || ' app=' || coalesce(nullif(application_name, ''), '-'), ' ; ')
                     from pg_stat_activity
                    where pid <> pg_backend_pid() and datname = current_database()
                      and (state like 'idle in transaction%' or (state = 'active' and xact_start < now() - interval '60 seconds'))),
                  'nenhuma')
  union all
  select 15, 'P-15 travas concedidas a OUTRAS sessões em physical_card / inventory / card_condition',
         coalesce((select string_agg(c.relname || ':' || l.mode || ' pid=' || l.pid, ' ; ')
                     from pg_locks l join pg_class c on c.oid = l.relation
                    where l.granted and l.pid <> pg_backend_pid()
                      and c.relname in ('physical_card', 'inventory', 'card_condition')
                      and l.mode not in ('AccessShareLock', 'RowShareLock', 'RowExclusiveLock')),
                  'nenhuma')
)
select ord, verificacao, got from rows order by ord;
