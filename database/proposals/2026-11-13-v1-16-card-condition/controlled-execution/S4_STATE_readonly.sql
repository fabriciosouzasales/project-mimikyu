/*
================================================================
V1-16 · S4 — estado SOMENTE LEITURA antes e depois da 5364
(`S4 READINESS-01`, 2026-11-13)
Status.....: PREPARADO.
Natureza...: UMA instrução SELECT sobre catálogo e contagens; não chama a
             função, não escreve, não trava. Nenhuma linha identifica usuário.
Uso........: S4-PRE e S4-POST, junto com POSTCHECK_readonly.sql e
             S2_STATE_readonly.sql. Critérios em
             CONTROLLED-EXECUTION-PROTOCOL.md §14.
================================================================
*/
with
f as (select to_regprocedure('public.set_my_physical_cards_condition(uuid[],text)') as oid),
checks(ord, verificacao, got, esperado) as (
  select 1, 'H-01 sobrecargas de set_my_physical_cards_condition',
         (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'set_my_physical_cards_condition')::text,
         'PRE: 0 · POST: 1'
  union all
  select 2, 'H-02 md5 do corpo',
         coalesce((select case md5(p.prosrc) when 'b569ecdbe202428a6bdc9461c6d62e37' then '5364 v1.1 b569ecdb…'
                                              else 'DIVERGENTE ' || md5(p.prosrc) end
                     from pg_proc p, f where p.oid = f.oid), 'ausente'),
         'PRE: ausente · POST: 5364 v1.1 b569ecdb…'
  union all
  select 3, 'H-03 assinatura e retorno',
         coalesce((select pg_get_function_identity_arguments(f.oid) || ' -> ' || pg_get_function_result(f.oid) from f where f.oid is not null), 'ausente'),
         'POST: p_physical_card_ids uuid[], p_condition_code text -> TABLE(requested_count integer, changed_count integer)'
  union all
  select 4, 'H-04 perfil (linguagem, secdef, volatilidade, config, dono, ACL)',
         coalesce((select l.lanname || ' secdef=' || p.prosecdef || ' vol=' || p.provolatile::text
                          || ' cfg=' || coalesce(array_to_string(p.proconfig, ';'), '-') || ' owner=' || pg_get_userbyid(p.proowner)
                          || ' acl=' || coalesce(array_to_string(p.proacl, ','), '(default)')
                     from pg_proc p join pg_language l on l.oid = p.prolang, f where p.oid = f.oid), 'ausente'),
         'POST: plpgsql secdef=true vol=v cfg=search_path="";lock_timeout=5s owner=postgres acl=postgres=X/postgres,authenticated=X/postgres'
  union all
  select 5, 'H-05 EXECUTE (authenticated, anon, service_role, PUBLIC)',
         coalesce((select has_function_privilege('authenticated', f.oid, 'EXECUTE') || ',' || has_function_privilege('anon', f.oid, 'EXECUTE')
                          || ',' || has_function_privilege('service_role', f.oid, 'EXECUTE')
                          || ',' || coalesce((select bool_or(a.grantee = 0) from pg_proc p, aclexplode(p.proacl) a where p.oid = f.oid), false)
                     from f where f.oid is not null), 'ausente'),
         'POST: true,false,false,false'
  union all
  select 6, 'H-06 pré-requisitos: validador (5362) e leitura (5363)',
         'validador=' || coalesce((select md5(prosrc) from pg_proc where oid = to_regprocedure('public.physical_card_unknown_condition_codes(text[])')), 'ausente')
         || ' leitura=' || coalesce((select md5(prosrc) from pg_proc where oid = to_regprocedure('public.get_my_inventory_item_copies(uuid,text)')), 'ausente'),
         'validador=df223290a53ce5252808899fbb03da60 leitura=77abbb9a33f2cb46280925bade22dee5 (PRE = POST)'
  union all
  select 7, 'H-07 gatilhos de physical_card que disparam num UPDATE só de condition_code',
         coalesce((select string_agg(t.tgname, ', ' order by t.tgname) from pg_trigger t
                    where t.tgrelid = 'public.physical_card'::regclass and not t.tgisinternal and t.tgenabled <> 'D'
                      and (t.tgtype & 16) <> 0                      -- UPDATE
                      and (coalesce(array_length(t.tgattr::int2[], 1), 0) = 0   -- sem lista de colunas
                           or (select attnum from pg_attribute where attrelid = 'public.physical_card'::regclass and attname = 'condition_code') = any(t.tgattr::int2[]))), '(nenhum)'),
         'trg_physical_card_set_updated_at (PRE = POST)'
  union all
  select 8, 'H-08 physical_card: RLS / FORCE / dono / grants de tabela a clientes',
         (select relrowsecurity || '/' || relforcerowsecurity || ' dono=' || pg_get_userbyid(relowner) from pg_class where oid = 'public.physical_card'::regclass)
         || ' grants=' || coalesce((select string_agg(grantee || ':' || privilege_type, ',' order by grantee, privilege_type) from information_schema.role_table_grants
                                     where table_schema = 'public' and table_name = 'physical_card' and grantee in ('anon', 'authenticated')), '-'),
         'true/false dono=postgres grants=authenticated:SELECT (PRE = POST)'
  union all
  select 9, 'H-09 condições e carimbos de physical_card',
         'total=' || (select count(*) from public.physical_card)
         || ' ' || coalesce((select string_agg(condition_code || '=' || n, ' ' order by condition_code)
                               from (select condition_code, count(*) as n from public.physical_card group by condition_code) s), '-')
         || ' max_updated=' || coalesce((select max(updated_at)::text from public.physical_card), '-'),
         'POST = PRE (a 5364 só cria a função; nenhum exemplar muda)'
  union all
  select 10, 'H-10 sessões/travas pendentes (exceto esta)',
         'sessoes=' || (select count(*) from pg_stat_activity
                         where pid <> pg_backend_pid() and datname = current_database()
                           and (state like 'idle in transaction%' or (state = 'active' and xact_start < now() - interval '60 seconds')))
         || ' travas_fortes=' || (select count(*) from pg_locks l join pg_class c on c.oid = l.relation
                                   where l.pid <> pg_backend_pid() and c.relname in ('physical_card', 'card_condition', 'inventory')
                                     and l.mode not in ('AccessShareLock', 'RowShareLock', 'RowExclusiveLock')),
         'sessoes=0 travas_fortes=0'
)
select ord, verificacao, got, esperado from checks order by ord;
