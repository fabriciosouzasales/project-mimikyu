/*
================================================================
V1-16 · S0 — pré-checagem SOMENTE LEITURA (CONTROLLED EXECUTION READINESS-01)
Status.....: PREPARADO, NÃO EXECUTADO.
Natureza...: UMA única instrução SELECT. Não escreve, não trava linhas,
             não chama função que escreva. Lê catálogo do PostgreSQL e
             contagens agregadas. Nenhuma linha identifica usuário.
Revisão....: S0 READ-ONLY SAFETY CHECK (2026-11-13): removidas S0-18/S0-19
             (identidade mascarada de u1/u2 — desnecessária: nenhum harness
             está autorizado); S0-15 e S0-17 (pré-requisitos de harness)
             passam a INFO. Numeração das demais linhas preservada.
Canal......: SQL Editor do Supabase (aceito para S0) ou psql com
             PGOPTIONS='-c default_transaction_read_only=on'.
Leitura....: uma linha por verificação: ord | verificacao | status | got | want
             status = GO (confere) · STOP (diverge) · INFO (anotar)
Evidência..: copiar a grade inteira (26 linhas: S0-01…S0-17 e S0-20…S0-28).
================================================================
*/
with
touched(tbl) as (
  select unnest(array['physical_card','inventory','bulk_operation','collection','collection_allocation',
                      'collection_reference','collection_card_set_reference','storage_container',
                      'expansion','card_set','card','card_variant'])
),
fn(k, proname, want_md5) as (
  values ('5153', 'bulk_register_physical_card_items', 'a5fd5107cc008b68a6d598a1a0501a6e'),
         ('5155', 'register_physical_cards_bulk',      '0b7221b6a2485ad75e2918365f515e0a'),
         ('5157', 'register_card_set_bulk',            '1526fd4d633f29f91ddc5c49141eef59'),
         ('5158', 'preview_bulk_operation',            '8dcf2656676739b5417b94b4882bd26c'),
         ('5262', 'get_my_inventory_item_copies',      'd8cce43b511856a5e25f061e75a7cede')
),
fn_state as (
  select f.k, f.proname, f.want_md5,
         (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = f.proname) as overloads,
         (select string_agg(md5(p.prosrc), ',') from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = f.proname) as md5s
    from fn f
),
trg as (
  select c.relname as tbl, t.tgname, p.proname, pn.nspname as fn_schema,
         (p.prosrc ~* '(net\.|http_request|http_get|http_post|dblink|pg_notify|\mnotify\M)'
          or p.proname ~* 'http' or pn.nspname in ('supabase_functions', 'net')) as external_effect
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace cn on cn.oid = c.relnamespace and cn.nspname = 'public'
    join pg_proc p on p.oid = t.tgfoid
    join pg_namespace pn on pn.oid = p.pronamespace
   where not t.tgisinternal and c.relname in (select tbl from touched)
),
rows(ord, verificacao, status, got, want) as (
  select 1, 'S0-01 versão do servidor', 'INFO', current_setting('server_version'), 'anotar'
  union all
  select 2, 'S0-02 escala canônica card_condition',
         case when g = 'M:1,NM:2,LP:3,MP:4,HP:5,DMG:6' then 'GO' else 'STOP' end, g, 'M:1,NM:2,LP:3,MP:4,HP:5,DMG:6'
    from (select string_agg(code || ':' || condition_order, ',' order by condition_order) as g from public.card_condition) s
  union all
  select 3, 'S0-03 card_condition.code com índice único (alvo da FK da 5361)',
         case when x then 'GO' else 'STOP' end, x::text, 'true'
    from (select exists (select 1 from pg_index i
                          where i.indrelid = 'public.card_condition'::regclass and i.indisunique and i.indnkeyatts = 1
                            and (select a.attname from pg_attribute a where a.attrelid = i.indrelid and a.attnum = i.indkey[0]) = 'code') as x) s
  union all
  select 3 + row_number() over (order by k),
         'S0-0' || (3 + row_number() over (order by k)) || ' corpo vigente ' || proname || ' (' || k || ')',
         case when overloads = 1 and md5s = want_md5 then 'GO' else 'STOP' end,
         overloads || ' sobrecarga(s); md5=' || coalesce(md5s, '-'), '1 sobrecarga(s); md5=' || want_md5
    from fn_state
  union all
  select 9, 'S0-09 retorno vigente de get_my_inventory_item_copies (5363 compara literalmente)',
         case when r = w then 'GO' else 'STOP' end, coalesce(r, '(função ausente)'), w
    from (select pg_get_function_result(to_regprocedure('public.get_my_inventory_item_copies(uuid,text)')) as r,
                 'TABLE(card_variant_id uuid, language_code text, language_name text, card_name text, collector_number text, collector_total integer, card_set_code text, card_set_name text, is_default_variant boolean, variant_label text, image_path text, copies_total integer, physical_card_id uuid, copy_number integer, added_at timestamp with time zone, collection_id uuid, collection_name text, storage_name text, variant_type_code text, rarity_code text)'::text as w) s
  union all
  select 10, 'S0-10 V1-16 ainda não aplicada: coluna physical_card.condition_code',
         case when x then 'STOP' else 'GO' end, case when x then 'presente' else 'ausente' end, 'ausente'
    from (select exists (select 1 from pg_attribute where attrelid = 'public.physical_card'::regclass
                          and attname = 'condition_code' and not attisdropped) as x) s
  union all
  select 11, 'S0-11 V1-16 ainda não aplicada: FK fk_physical_card_condition_code',
         case when x then 'STOP' else 'GO' end, case when x then 'presente' else 'ausente' end, 'ausente'
    from (select exists (select 1 from pg_constraint where conname = 'fk_physical_card_condition_code') as x) s
  union all
  select 12, 'S0-12 V1-16 ainda não aplicada: physical_card_unknown_condition_codes',
         case when n = 0 then 'GO' else 'STOP' end, n || ' função(ões)', '0 função(ões)'
    from (select count(*) as n from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
           where ns.nspname = 'public' and p.proname = 'physical_card_unknown_condition_codes') s
  union all
  select 13, 'S0-13 V1-16 ainda não aplicada: set_my_physical_cards_condition',
         case when n = 0 then 'GO' else 'STOP' end, n || ' função(ões)', '0 função(ões)'
    from (select count(*) as n from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
           where ns.nspname = 'public' and p.proname = 'set_my_physical_cards_condition') s
  union all
  select 14, 'S0-14 contagens de referência (baseline das etapas)', 'INFO',
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
         'anotar (comparado depois de cada etapa e de cada harness)'
  union all
  select 15, 'S0-15 referências de catálogo usadas pelas fixtures de harness (POKEMON / COMMON / POKEMON / STANDARD / idioma)',
         'INFO', x::text, 'true (só relevante se um harness vier a ser autorizado)'
    from (select exists (select 1 from public.game g
                          where g.code = 'POKEMON'
                            and exists (select 1 from public.rarity r where r.game_id = g.id and r.code = 'COMMON')
                            and exists (select 1 from public.card_category c where c.game_id = g.id and c.code = 'POKEMON')
                            and exists (select 1 from public.card_variant_type v where v.game_id = g.id and v.code = 'STANDARD'))
                 and exists (select 1 from public.language) as x) s
  union all
  select 16, 'S0-16 resíduo sintético de harnesses anteriores',
         case when e + cs + col = 0 then 'GO' else 'STOP' end,
         'expansion ZZ%=' || e || ' card_set ZZ%=' || cs || ' collection %HARNESS%=' || col, 'todos 0'
    from (select (select count(*) from public.expansion where code like 'ZZ%') as e,
                 (select count(*) from public.card_set where code like 'ZZ%') as cs,
                 (select count(*) from public.collection where name like '%HARNESS%') as col) s
  union all
  select 17, 'S0-17 total de contas em auth.users (agregado; pré-requisito de harness)',
         'INFO', n::text, 'anotar'
    from (select count(*) as n from auth.users) s
  union all
  select 20, 'S0-20 gatilhos com efeito externo nas tabelas tocadas (http/pg_net/dblink/notify/webhook)',
         case when n = 0 then 'GO' else 'STOP' end, n || coalesce(': ' || l, ''), '0'
    from (select count(*) filter (where external_effect) as n,
                 string_agg(tbl || '.' || tgname || '→' || fn_schema || '.' || proname, ', ') filter (where external_effect) as l
            from trg) s
  union all
  select 21, 'S0-21 gatilhos não internos nas tabelas tocadas', 'INFO',
         coalesce((select string_agg(tbl || '.' || tgname, ', ' order by tbl, tgname) from trg), '(nenhum)'), 'anotar'
  union all
  select 22, 'S0-22 event triggers habilitados (disparam em DDL de S1–S4)', 'INFO',
         coalesce((select string_agg(evtname || ':' || evtevent, ', ' order by evtname) from pg_event_trigger where evtenabled <> 'D'), '(nenhum)'),
         'anotar'
  union all
  select 23, 'S0-23 tabelas tocadas em publicações (Realtime só decodifica COMMIT)', 'INFO',
         coalesce((select string_agg(pubname || ':' || tablename, ', ' order by pubname, tablename)
                     from pg_publication_tables where schemaname = 'public' and tablename in (select tbl from touched)), '(nenhuma)'),
         'anotar'
  union all
  select 24, 'S0-24 physical_card: RLS ligada e nenhuma política de escrita (premissa do A05)',
         case when rls and w = 0 then 'GO' else 'STOP' end, 'rls=' || rls || ' politicas_escrita=' || w, 'rls=true politicas_escrita=0'
    from (select (select relrowsecurity from pg_class where oid = 'public.physical_card'::regclass) as rls,
                 (select count(*) from pg_policies where schemaname = 'public' and tablename = 'physical_card'
                     and cmd in ('INSERT', 'UPDATE', 'DELETE', 'ALL')) as w) s
  union all
  select 25, 'S0-25 sessões em transação aberta > 60 s ou idle in transaction (exceto esta)', 'INFO',
         n::text, '0 no momento de cada etapa (recontar imediatamente antes de S1)'
    from (select count(*) as n from pg_stat_activity
           where pid <> pg_backend_pid() and datname = current_database()
             and (state like 'idle in transaction%' or (state = 'active' and xact_start < now() - interval '60 seconds'))) s
  union all
  select 26, 'S0-26 extensão pg_net instalada', 'INFO',
         (select coalesce(max(extversion), 'não instalada') from pg_extension where extname = 'pg_net'), 'anotar'
  union all
  select 27, 'S0-27 última versão no ledger de migrations', 'INFO',
         (select coalesce(max(version), '-') from supabase_migrations.schema_migrations), 'anotar'
  union all
  select 28, 'S0-28 timeouts da sessão (idle_in_transaction / statement / lock)', 'INFO',
         'idle_in_transaction_session_timeout=' || current_setting('idle_in_transaction_session_timeout')
         || ' statement_timeout=' || current_setting('statement_timeout')
         || ' lock_timeout=' || current_setting('lock_timeout'), 'anotar'
)
select ord, verificacao, status, got, want from rows order by ord;
