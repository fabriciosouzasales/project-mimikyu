/*
================================================================
Projeto.....: Project Mimikyu
Arquivo.....: LIVE_DRYRUN_S1_gate_readonly.sql — verificações SOMENTE LEITURA antes e
              depois do ensaio LIVE da P3-B S1 (LIVE_DRYRUN_S1_rollback.sql v2.1)
Versão......: 1.1 (2026-10-25, P3-B-S1-LIVE-DRYRUN-EXECUTOR-E2-READINESS-02: +P.11, +P.12
              informativo, +Q.09 — sessão E2 identificada por application_name)
              1.0 (P3-B-S1-LIVE-DRYRUN-EXECUTION-GATE-01)
Status......: PRONTO. Só SELECT. Não altera nada. Complementa LIVE_00 (que continua
              obrigatório antes e depois). README §26.

Uso: executar o bloco G-PRE imediatamente antes do ensaio e o bloco G-POST
imediatamente depois, cada um como uma consulta. Todos os itens com ok = true;
qualquer false = STOP. As contagens de G-PRE são a linha de base de G-POST.
================================================================
*/

-- G-PRE — estado da sessão, concorrência e linha de base -------------------------------------
select 'P.01 read_only da sessão off' as id, current_setting('default_transaction_read_only') as detail,
       current_setting('default_transaction_read_only') = 'off' and current_setting('transaction_read_only') = 'off' as ok
union all select 'P.02 gatilhos ativos (origin)', current_setting('session_replication_role'),
       current_setting('session_replication_role') = 'origin'
union all select 'P.03 GUCs do histórico livres',
       coalesce(current_setting('mmkyu.binder_activity_purge', true), '') || '|' || coalesce(current_setting('mmkyu.binder_activity_ctx', true), ''),
       coalesce(current_setting('mmkyu.binder_activity_purge', true), '') = '' and coalesce(current_setting('mmkyu.binder_activity_ctx', true), '') = ''
union all select 'P.04 nenhuma outra sessão cliente ativa',
       (select count(*)::text from pg_stat_activity where pid <> pg_backend_pid() and backend_type = 'client backend' and state is not null and state <> 'idle'),
       not exists (select 1 from pg_stat_activity where pid <> pg_backend_pid() and backend_type = 'client backend' and state is not null and state <> 'idle')
union all select 'P.05 nenhuma transação ociosa ou abortada aberta',
       (select count(*)::text from pg_stat_activity where pid <> pg_backend_pid() and state like 'idle in transaction%'),
       not exists (select 1 from pg_stat_activity where pid <> pg_backend_pid() and state like 'idle in transaction%')
union all select 'P.06 nenhum lock em auth.users',
       (select count(*)::text from pg_locks where relation = 'auth.users'::regclass and pid <> pg_backend_pid()),
       not exists (select 1 from pg_locks where relation = 'auth.users'::regclass and pid <> pg_backend_pid())
union all select 'P.07 nenhum lock aguardando no cluster',
       (select count(*)::text from pg_locks where not granted),
       not exists (select 1 from pg_locks where not granted)
union all select 'P.08 nenhum DDL/manutenção em curso',
       (select count(*)::text from pg_stat_activity where pid <> pg_backend_pid() and state <> 'idle'
          and (backend_type = 'autovacuum worker' or query ~* '^\s*(alter|create|drop|vacuum|analyze|reindex)\M')),
       not exists (select 1 from pg_stat_activity where pid <> pg_backend_pid() and state <> 'idle'
          and (backend_type = 'autovacuum worker' or query ~* '^\s*(alter|create|drop|vacuum|analyze|reindex)\M'))
union all select 'P.09 nomes temporários do ensaio livres', '-',
       to_regclass('pg_temp.mmkyu_dryrun_veto_parent') is null and to_regclass('pg_temp.mmkyu_dryrun_veto_child') is null
       and to_regclass('pg_temp.mmkyu_dryrun_evidence') is null
union all select 'P.10 linha de base', (select jsonb_build_object(
         'ledger_count', (select count(*) from supabase_migrations.schema_migrations),
         'ledger_last', (select name from supabase_migrations.schema_migrations order by version desc limit 1),
         'auth_users', (select count(*) from auth.users),
         'incorporation', (select count(*) from public.collection_layout_catalog_incorporation),
         'collection', (select count(*) from public.collection),
         'collection_layout', (select count(*) from public.collection_layout),
         'collection_layout_page', (select count(*) from public.collection_layout_page),
         'collection_layout_slot', (select count(*) from public.collection_layout_slot),
         'card', (select count(*) from public.card),
         'card_set', (select count(*) from public.card_set),
         'card_variant_type', (select count(*) from public.card_variant_type),
         'public_functions', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'),
         'public_relations', (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public'))::text),
       true
union all select 'P.11 nenhuma sessão E2 do ensaio aberta (application_name)',
       (select count(*)::text from pg_stat_activity where application_name = 'mmkyu_dryrun_s1_e2'),
       not exists (select 1 from pg_stat_activity where application_name = 'mmkyu_dryrun_s1_e2')
union all select 'P.12 INFORMATIVO: última atividade de autenticação (não prova ausência de uso planejado)',
       (select coalesce(max(updated_at)::text, '-') from auth.users) || ' | sessões: '
       || coalesce((select max(coalesce(s.refreshed_at, s.updated_at, s.created_at))::text from auth.sessions s), '-'),
       true;

-- G-POST — resíduo zero (comparar P.10 do G-PRE com Q.08) ------------------------------------
select 'Q.01 nenhum objeto binder_activity_*' as id, '-' as detail,
       not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                   where n.nspname = 'public' and c.relname like 'binder_activity%')
       and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                       where n.nspname = 'public' and p.proname like '%binder_activity%') as ok
union all select 'Q.02 ledger inalterado',
       (select count(*)::text || ' | ' || (select name from supabase_migrations.schema_migrations order by version desc limit 1)
        from supabase_migrations.schema_migrations),
       (select name from supabase_migrations.schema_migrations order by version desc limit 1) = '5266_create_binder_catalog_reconciliation_apply'
       and not exists (select 1 from supabase_migrations.schema_migrations where name ~ '^(5267|5268|5269|5270)_')
union all select 'Q.03 nenhuma sessão do ensaio ativa ou abortada',
       (select count(*)::text from pg_stat_activity where pid <> pg_backend_pid()
          and (state like 'idle in transaction%' or query ilike '%mmkyu_dryrun%' or query ilike '%MSDRYRUN%')),
       not exists (select 1 from pg_stat_activity where pid <> pg_backend_pid()
          and (state like 'idle in transaction%' or query ilike '%mmkyu_dryrun%' or query ilike '%MSDRYRUN%'))
union all select 'Q.04 nenhum lock em auth.users',
       (select count(*)::text from pg_locks where relation = 'auth.users'::regclass and pid <> pg_backend_pid()),
       not exists (select 1 from pg_locks where relation = 'auth.users'::regclass and pid <> pg_backend_pid())
union all select 'Q.05 nenhum lock aguardando', (select count(*)::text from pg_locks where not granted),
       not exists (select 1 from pg_locks where not granted)
union all select 'Q.06 read_only da sessão de verificação off', current_setting('default_transaction_read_only'),
       current_setting('default_transaction_read_only') = 'off'
union all select 'Q.07 incorporação legada intacta', (select count(*)::text from public.collection_layout_catalog_incorporation),
       (select count(*) from public.collection_layout_catalog_incorporation) = 1
union all select 'Q.08 contagens (comparar com P.10)', (select jsonb_build_object(
         'ledger_count', (select count(*) from supabase_migrations.schema_migrations),
         'ledger_last', (select name from supabase_migrations.schema_migrations order by version desc limit 1),
         'auth_users', (select count(*) from auth.users),
         'incorporation', (select count(*) from public.collection_layout_catalog_incorporation),
         'collection', (select count(*) from public.collection),
         'collection_layout', (select count(*) from public.collection_layout),
         'collection_layout_page', (select count(*) from public.collection_layout_page),
         'collection_layout_slot', (select count(*) from public.collection_layout_slot),
         'card', (select count(*) from public.card),
         'card_set', (select count(*) from public.card_set),
         'card_variant_type', (select count(*) from public.card_variant_type),
         'public_functions', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'),
         'public_relations', (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public'))::text),
       true
union all select 'Q.09 conexão E2 do ensaio encerrada (application_name)',
       (select count(*)::text from pg_stat_activity where application_name = 'mmkyu_dryrun_s1_e2'),
       not exists (select 1 from pg_stat_activity where application_name = 'mmkyu_dryrun_s1_e2');
