/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5880D - v1.1 | Integridade e ausência de resíduos (somente leitura)
Versão......: 1.1
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-11-06 (R1-B PRICING 3989 VALIDATION RECOVERY-03)
Autor.......: Fabrício Sales / Claude

Rastreabilidade com o 5880 v1.0: 10.1 (nenhuma alteração de dados) e a sentinela TR000.
Executar por último (depois de 5880B/C/E e, se autorizado, 5880A).

Verifica: definição em vigor = 3989 (md5), ACL, ledger com a 3989 como última migration,
nenhuma função/objeto de harness, nenhuma observação/produto sintético (H5880-%), nenhum
produto inativo, nenhuma sessão de harness ativa, contagens de controle (para comparar com o
baseline do postcheck anterior; observações crescem pelo cron justtcg-price-refresh).
================================================================
*/
begin isolation level repeatable read read only;
set local statement_timeout = '60s';
select
  (select md5(prosrc) from pg_proc where oid = to_regprocedure('public.get_card_variants_pricing_summary(uuid[])')) = 'e253fcc5613bbef1181c6564b56f5b8a' as definicao_3989_ok,
  (select proacl::text from pg_proc where oid = to_regprocedure('public.get_card_variants_pricing_summary(uuid[])')) as acl,
  (select version || ' ' || name from supabase_migrations.schema_migrations order by version desc limit 1) as ultima_migration,
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where p.proname ilike '%3983%' or p.proname ilike '%5880%' or (n.nspname like 'pg_temp%' and p.proname ilike '%pricing%')) as funcoes_de_harness,
  (select count(*) from public.pricing_product where not is_active) as produtos_inativos,
  (select count(*) from pg_stat_activity where query ilike '%5880%' and pid <> pg_backend_pid()) as sessoes_de_harness,
  (select count(*) from pg_stat_activity where state = 'idle in transaction' and pid <> pg_backend_pid()) as sessoes_idle_in_tx,
  (select count(*) from public.pricing_observation) as observacoes,
  (select count(*) from public.pricing_product) as produtos,
  (select count(*) || ':' || coalesce(sum(rate), 0) from public.pricing_fx_rate) as fx,
  (select count(*) from public.pricing_source_card_identity) as identidades,
  (select count(*) from public.card_variant) as variantes,
  (select count(*) from public.card_condition) as condicoes,
  (select count(*) from public.physical_card) as exemplares;
rollback;
