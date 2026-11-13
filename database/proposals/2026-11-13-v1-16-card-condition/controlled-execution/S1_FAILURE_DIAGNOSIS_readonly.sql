/*
================================================================
V1-16 · S1 — diagnóstico SOMENTE LEITURA da falha da 5361 v1.0
(`S1 EXECUTION FAILURE DIAGNOSIS-01`, 2026-11-13)
Status.....: PREPARADO, NÃO EXECUTADO.
Natureza...: UMA instrução SELECT; sem DML/DDL, sem set_config, sem trava de
             escrita; não depende da coluna existir (lê pelo catálogo e por
             to_jsonb). Nenhuma linha identifica usuário.
Canal......: SQL Editor ou psql com PGOPTIONS='-c default_transaction_read_only=on'.
Rodar......: junto com POSTCHECK_readonly.sql. Interpretação (D1/D2/D3) em
             CONTROLLED-EXECUTION-PROTOCOL.md §11.
================================================================
*/
with
col as (
  select format_type(a.atttypid, a.atttypmod) as typ, a.attnotnull,
         pg_get_expr(ad.adbin, ad.adrelid) as def,
         col_description(a.attrelid, a.attnum) as cmt
    from pg_attribute a
    left join pg_attrdef ad on ad.adrelid = a.attrelid and ad.adnum = a.attnum
   where a.attrelid = 'public.physical_card'::regclass
     and a.attname = 'condition_code' and not a.attisdropped
),
fk as (
  select c.convalidated, replace(pg_get_constraintdef(c.oid), 'public.', '') as def
    from pg_constraint c
   where c.conrelid = 'public.physical_card'::regclass
     and c.conname = 'fk_physical_card_condition_code'
),
checks(ord, verificacao, got, want_d2) as (
  select 1, 'D-01 coluna condition_code',
         coalesce((select 'presente tipo=' || typ || ' notnull=' || attnotnull || ' default=' || coalesce(def, '-') from col), 'ausente'),
         'presente tipo=text notnull=true default=''NM''::text'
  union all
  select 2, 'D-02 FK fk_physical_card_condition_code',
         coalesce((select 'presente validada=' || convalidated || ' def=' || def from fk), 'ausente'),
         'presente validada=true def=FOREIGN KEY (condition_code) REFERENCES card_condition(code) ON UPDATE RESTRICT ON DELETE RESTRICT'
  union all
  select 3, 'D-03 comentário da coluna',
         coalesce((select case when cmt like 'V1-16 (C-227–C-233)%' then 'presente (texto da 5361)'
                               when cmt is null then 'ausente' else 'presente (OUTRO texto)' end from col), 'n/a (coluna ausente)'),
         'presente (texto da 5361)'
  union all
  select 4, 'D-04 exemplares com condição diferente de NM (ou nula)',
         case when exists (select 1 from col)
              then (select count(*) from public.physical_card
                     where (to_jsonb(physical_card) ->> 'condition_code') is distinct from 'NM')::text
              else 'n/a (coluna ausente)' end,
         '0'
  union all
  select 5, 'D-05 contagens (mesmo formato de S0-14)',
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
         || ' card_variant=' || (select count(*) from public.card_variant),
         'idêntico a S0-14 (salvo uso legítimo do app entre S0 e agora)'
  union all
  select 6, 'D-06 último updated_at de physical_card (anotar)',
         coalesce((select max(updated_at)::text from public.physical_card), '-'), 'anterior ao horário da tentativa da 5361'
  union all
  select 7, 'D-07 tabela temporária _v116_s1_before visível nesta sessão',
         case when to_regclass('pg_temp._v116_s1_before') is null then 'não' else 'SIM' end, 'não'
  union all
  select 8, 'D-08 sessões idle in transaction / transação > 60 s (exceto esta)',
         coalesce((select string_agg('pid=' || pid || ' estado=' || state || ' idade=' || date_trunc('second', now() - xact_start)
                                     || ' app=' || coalesce(nullif(application_name, ''), '-'), ' ; ')
                     from pg_stat_activity
                    where pid <> pg_backend_pid() and datname = current_database()
                      and (state like 'idle in transaction%' or (state = 'active' and xact_start < now() - interval '60 seconds'))),
                  'nenhuma'),
         'nenhuma'
  union all
  select 9, 'D-09 travas fortes de OUTRAS sessões em physical_card / card_condition',
         coalesce((select string_agg(c.relname || ':' || l.mode || ' pid=' || l.pid || ' concedida=' || l.granted, ' ; ')
                     from pg_locks l join pg_class c on c.oid = l.relation
                    where l.pid <> pg_backend_pid()
                      and c.relname in ('physical_card', 'card_condition')
                      and l.mode not in ('AccessShareLock', 'RowShareLock', 'RowExclusiveLock')),
                  'nenhuma'),
         'nenhuma'
)
select ord, verificacao, got, want_d2 as "esperado se a DDL da 1.0 foi comitada (D2)" from checks order by ord;
