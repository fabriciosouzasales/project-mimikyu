/*
================================================================
Projeto.....: Project Mimikyu
Arquivo.....: LIVE_00_precheck_readonly.sql — P3-B S1, antes de 5267
Versão......: 1.1 (2026-10-27, E3 BASELINE RECONCILIATION — MEP-01: 00.1 passa a exigir o último
              ledger 20261026124224 fix_mep_bootstrap_preserve_confirmed_primary_identity — versão e nome)
              1.0 (2026-10-25, P3-B-S1-FOUNDATION-READINESS-01)
Status......: PROPOSTA. SÓ LEITURA. Executar imediatamente antes da 5267,
              apenas com G8 aberto.
Esperado....: todas as linhas com ok = true.
================================================================
*/
select '00.1' as id,
       (select version || '|' || name from supabase_migrations.schema_migrations order by version desc limit 1) as detail,
       coalesce((select version || '|' || name from supabase_migrations.schema_migrations order by version desc limit 1), '')
         = '20261026124224|fix_mep_bootstrap_preserve_confirmed_primary_identity' as ok   -- baseline do ledger desde 2026-10-26 (correção MEP)
union all
select '00.2', 'nenhum objeto binder_activity_*',
       not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                   where n.nspname = 'public' and c.relname like 'binder_activity%')
       and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                       where n.nspname = 'public' and p.proname like '%binder_activity%')
union all
select '00.3', 'numeração 5267–5270 livre no ledger',
       not exists (select 1 from supabase_migrations.schema_migrations where name ~ '^(5267|5268|5269|5270)_')
union all
select '00.4', 'incorporações legadas = ' || (select count(*) from public.collection_layout_catalog_incorporation),
       (select count(*) from public.collection_layout_catalog_incorporation) = 1   -- Chi-Yu, leitura de 2026-10-25
union all
select '00.5', 'GUCs livres (nenhum uso prévio de mmkyu.binder_activity_*)',
       not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                   where n.nspname = 'public' and pg_get_functiondef(p.oid) ~ 'mmkyu\.binder_activity_')
union all
select '00.6', 'dependências presentes',
       to_regclass('public.collection_layout') is not null
       and to_regclass('public.collection_layout_catalog_incorporation') is not null
       and to_regclass('public.card_variant_type') is not null;
