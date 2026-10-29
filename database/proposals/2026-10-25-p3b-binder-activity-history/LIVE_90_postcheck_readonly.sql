/*
================================================================
Projeto.....: Project Mimikyu
Arquivo.....: LIVE_90_postcheck_readonly.sql — P3-B S1, depois de 5270
Versão......: 1.1 (2026-10-25, P3-B-S1-SECURITY-CORRECTION-01: +90.11 W8, +90.12 B1)
Status......: PROPOSTA. SÓ LEITURA. Executar logo após 5267 → 5270.
Esperado....: todas as linhas com ok = true.
================================================================
*/
with fns as (
  select p.oid, p.proname, p.prosecdef, p.proconfig
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('binder_activity_begin','binder_activity_add_item','binder_activity_end',
                      'binder_activity_category','get_my_binder_activity','get_my_binder_activity_coverage',
                      'list_my_closed_binder_histories','purge_my_binder_activity',
                      'binder_activity_event_guard','binder_activity_item_guard')
)
select '90.1' as id, 'ledger 5267–5270' as detail,
       (select count(*) from supabase_migrations.schema_migrations where name ~ '^(5267|5268|5269|5270)_') = 4 as ok
union all
select '90.2', '4 tabelas com RLS e sem privilégio de cliente',
       (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'public' and c.relname in ('binder_activity_event','binder_activity_item',
              'binder_activity_coverage','binder_activity_setting') and c.relrowsecurity) = 4
       and not exists (
         select 1 from unnest(array['public.binder_activity_event','public.binder_activity_item',
                                    'public.binder_activity_coverage','public.binder_activity_setting']) t(tbl),
                       unnest(array['anon','authenticated','service_role']) r(rol),
                       unnest(array['SELECT','INSERT','UPDATE','DELETE']) pv(priv)
         where has_table_privilege(r.rol, t.tbl, pv.priv))
union all
select '90.3', '10 funções com search_path vazio; 9 SECURITY DEFINER (binder_activity_category é SQL pura)',
       (select count(*) from fns) = 10
       and (select bool_and(proconfig @> array['search_path=""']
                            and prosecdef = (proname <> 'binder_activity_category')) from fns)
union all
select '90.4', 'EXECUTE só nas 3 leituras para authenticated; nada para anon',
       (select bool_and(has_function_privilege('authenticated', oid, 'EXECUTE')
                        = (proname in ('get_my_binder_activity','get_my_binder_activity_coverage','list_my_closed_binder_histories'))
                        and not has_function_privilege('anon', oid, 'EXECUTE'))
        from fns)
union all
select '90.5', 'gatilhos de imutabilidade (4)',
       (select count(*) from pg_trigger t where not t.tgisinternal
          and t.tgname in ('trg_bae_immutable','trg_bae_no_truncate','trg_bai_immutable','trg_bai_no_truncate')) = 4
union all
select '90.6', 'legado L01: eventos = incorporações; sem ator; 1 item cada',
       (select count(*) from public.binder_activity_event where source = 'LEGADO')
         = (select count(*) from public.collection_layout_catalog_incorporation)
       and not exists (select 1 from public.binder_activity_event where source = 'LEGADO' and actor_user_id is not null)
       and not exists (select 1 from public.binder_activity_event e where e.source = 'LEGADO'
                       and (select count(*) from public.binder_activity_item i where i.event_id = e.id) <> 1)
union all
select '90.7', 'legado sem posição',
       not exists (select 1 from public.binder_activity_item i join public.binder_activity_event e on e.id = i.event_id
                   where e.source = 'LEGADO' and (i.from_page is not null or i.to_page is not null))
union all
select '90.8', 'nenhum evento não legado (S1 não instrumenta nada)',
       not exists (select 1 from public.binder_activity_event where source <> 'LEGADO')
union all
select '90.9', 'cobertura global ainda NULL (O4)',
       (select full_coverage_from is null from public.binder_activity_setting where id = 1)
union all
select '90.10', 'nenhuma função existente referencia o histórico (G4 no LIVE)',
       not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                   where n.nspname = 'public' and p.oid not in (select oid from fns)
                     and pg_get_functiondef(p.oid) ~* 'binder_activity_')
union all
select '90.11', 'W8: sequência da identidade sem privilégio de cliente nem PUBLIC',
       not exists (select 1 from unnest(array['anon','authenticated','service_role']) r(rol),
                                 unnest(array['USAGE','SELECT','UPDATE']) pv(priv)
                   where has_sequence_privilege(r.rol, 'public.binder_activity_event_id_seq', pv.priv))
       and not exists (select 1 from pg_class c, aclexplode(c.relacl) x
                       where c.oid = 'public.binder_activity_event_id_seq'::regclass and x.grantee = 0)
union all
select '90.12', 'B1: ator sem FK; única FK do evento = titular com cascata',
       (select count(*) from pg_constraint k where k.conrelid = 'public.binder_activity_event'::regclass and k.contype = 'f') = 1
       and exists (select 1 from pg_constraint k join pg_attribute a on a.attrelid = k.conrelid and a.attnum = any (k.conkey)
                   where k.conrelid = 'public.binder_activity_event'::regclass and k.contype = 'f'
                     and a.attname = 'owner_user_id' and k.confdeltype = 'c')
       and to_regclass('public.ix_bae_actor') is null;
