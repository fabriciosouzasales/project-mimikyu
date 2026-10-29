/*
================================================================
Projeto.....: Project Mimikyu
Arquivo.....: CATALOG_R1R3_readonly.sql — fechamento das ressalvas R1 e R3 da auditoria
              da v2.2 (README §28.22): estado do catálogo LIVE ANTES do ensaio
Versão......: 1.1 (2026-10-26, correção mínima: removido um ')' excedente no fecho de C.7 — v1.0 STOP 42601)
              1.0 (2026-10-26, P3-B S1 E3 v2.2 — FECHAMENTO DAS RESSALVAS R1 E R3)
Status......: PROPOSTA. NÃO EXECUTADA. Um único SELECT. Exige autorização específica.
              README §28.23.

Lista canônica = CTE fns do LIVE_90 (conferida por script contra canonical_functions()).
Os predicados de C.1 e C.2 reproduzem os de 90.10 e 90.3/90.4 (schema public, por nome),
para que o estado atual mostre o que interferiria neles depois das migrations.
Esperado: ok = true em todas as linhas (C.4 e C.6 só informativos).
================================================================
*/
with c as (
  select array['binder_activity_begin','binder_activity_add_item','binder_activity_end',
               'binder_activity_category','get_my_binder_activity','get_my_binder_activity_coverage',
               'list_my_closed_binder_histories','purge_my_binder_activity',
               'binder_activity_event_guard','binder_activity_item_guard']::text[] as fns
),
pf as (
  select p.oid, p.proname, n.nspname, p.proconfig,
         p.oid::regprocedure::text as sig
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
),
dacl as (
  select a.grantee
  from pg_default_acl d, aclexplode(d.defaclacl) a
  where d.defaclobjtype = 'f' and a.privilege_type = 'EXECUTE'
    and (d.defaclnamespace = 0 or d.defaclnamespace = 'public'::regnamespace)
)
select 'C.1 (90.10) nenhuma função public fora da lista cita binder_activity_' as id,
       coalesce((select string_agg(pf.sig, ', ' order by pf.sig) from pf, c
                 where pf.nspname = 'public' and not (pf.proname = any(c.fns))
                   and pg_get_functiondef(pf.oid) ~* 'binder_activity_'), '-') as detail,
       not exists (select 1 from pf, c
                   where pf.nspname = 'public' and not (pf.proname = any(c.fns))
                     and pg_get_functiondef(pf.oid) ~* 'binder_activity_') as ok
union all
select 'C.2 (90.3/90.4) nenhuma função public com nome canônico (sem sobrecarga prévia)',
       coalesce((select string_agg(pf.sig, ', ' order by pf.sig) from pf, c
                 where pf.nspname = 'public' and pf.proname = any(c.fns)), '-'),
       not exists (select 1 from pf, c where pf.nspname = 'public' and pf.proname = any(c.fns))
union all
select 'C.3 list_my_closed_binder_histories inexistente em qualquer schema',
       coalesce((select string_agg(pf.sig, ', ') from pf where pf.proname = 'list_my_closed_binder_histories'), '-'),
       not exists (select 1 from pf where pf.proname = 'list_my_closed_binder_histories')
union all
select 'C.4 INFORMATIVO: nomes canônicos fora de public (não afetam 90.x)',
       coalesce((select string_agg(pf.sig, ', ' order by pf.sig) from pf, c
                 where pf.nspname <> 'public' and pf.proname = any(c.fns)), '-'),
       true
union all
select 'C.5 (90.4) anon/authenticated sem EXECUTE herdado por default ACL ou por pertença ao dono',
       coalesce((select string_agg(distinct coalesce(r.rolname, 'PUBLIC'), ', ') from dacl
                 left join pg_roles r on r.oid = dacl.grantee), '-'),
       not exists (select 1 from dacl
                   where dacl.grantee <> 0
                     and dacl.grantee not in ('anon'::regrole::oid, 'authenticated'::regrole::oid, 'service_role'::regrole::oid)
                     and (pg_has_role('authenticated', dacl.grantee, 'MEMBER') or pg_has_role('anon', dacl.grantee, 'MEMBER')))
       and not pg_has_role('authenticated', 'postgres', 'MEMBER')
       and not pg_has_role('anon', 'postgres', 'MEMBER')
union all
select 'C.6 INFORMATIVO (R3): formas de search_path em proconfig das funções public',
       coalesce((select string_agg(x.cfg || ' ×' || x.n, ' | ' order by x.n desc)
                 from (select cfg, count(*) as n from pf, unnest(pf.proconfig) cfg
                       where pf.nspname = 'public' and cfg like 'search_path=%' group by cfg) x), '-'),
       true
union all
select 'C.7 (R3/90.3) search_path vazio representado como search_path="" e casado por @>',
       (select count(*)::text from pf where pf.nspname = 'public' and pf.proconfig @> array['search_path=""']),
       exists (select 1 from pf where pf.nspname = 'public' and pf.proconfig @> array['search_path=""'])
       and not exists (select 1 from pf, unnest(pf.proconfig) cfg
                       where pf.nspname = 'public' and cfg in ('search_path=', 'search_path='''''));
