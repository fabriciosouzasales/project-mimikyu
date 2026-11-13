/*
================================================================
V1-16 · S3 — estado SOMENTE LEITURA de get_my_inventory_item_copies antes e
depois da 5363 (`S3 READINESS-01`, 2026-11-13)
Status.....: PREPARADO, NÃO EXECUTADO.
Natureza...: UMA instrução SELECT sobre o catálogo; não chama a função, não
             escreve, não trava. Nenhuma linha identifica usuário.
Uso........: rodar ANTES (S3-PRE) e DEPOIS (S3-POST) da 5363, junto com
             POSTCHECK_readonly.sql e S2_STATE_readonly.sql (contagens).
             Critérios em CONTROLLED-EXECUTION-PROTOCOL.md §13.
================================================================
*/
with
f as (select to_regprocedure('public.get_my_inventory_item_copies(uuid,text)') as oid),
cols as (
  select o.ord, o.name, format_type(o.typ, null) as typ
    from f, pg_proc p,
         lateral unnest(p.proargnames, p.proallargtypes, p.proargmodes) with ordinality as o(name, typ, mode, ord)
   where p.oid = f.oid and o.mode = 't'
),
checks(ord, verificacao, got, esperado) as (
  select 1, 'G-01 sobrecargas',
         (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'get_my_inventory_item_copies')::text,
         '1 (PRE e POST)'
  union all
  select 2, 'G-02 md5 do corpo',
         coalesce((select case md5(p.prosrc) when 'd8cce43b511856a5e25f061e75a7cede' then '5262 d8cce43b…'
                                              when '77abbb9a33f2cb46280925bade22dee5' then '5363 77abbb9a…'
                                              else 'DIVERGENTE ' || md5(p.prosrc) end
                     from pg_proc p, f where p.oid = f.oid), 'ausente'),
         'PRE: 5262 d8cce43b… · POST: 5363 77abbb9a…'
  union all
  select 3, 'G-03 argumentos de entrada',
         coalesce((select pg_get_function_identity_arguments(f.oid) from f), 'ausente'),
         'p_card_variant_id uuid, p_language_code text (PRE = POST)'
  union all
  select 4, 'G-04 colunas de retorno 1–20 (nome:tipo, em ordem)',
         coalesce((select string_agg(name || ':' || typ, ', ' order by ord) from (select row_number() over (order by ord) as ord, name, typ from cols) c where c.ord <= 20), '-'),
         'PRE = POST, idênticas'
  union all
  select 5, 'G-05 colunas além da 20ª',
         coalesce((select string_agg(name || ':' || typ, ', ' order by ord) from (select row_number() over (order by ord) as ord, name, typ from cols) c where c.ord > 20), '(nenhuma)'),
         'PRE: (nenhuma) · POST: condition_code:text'
  union all
  select 6, 'G-06 perfil (linguagem, secdef, volatilidade, config, dono, ACL)',
         coalesce((select l.lanname || ' secdef=' || p.prosecdef || ' vol=' || p.provolatile::text
                          || ' cfg=' || coalesce(array_to_string(p.proconfig, ';'), '-') || ' owner=' || pg_get_userbyid(p.proowner)
                          || ' acl=' || coalesce(array_to_string(p.proacl, ','), '(default)')
                     from pg_proc p join pg_language l on l.oid = p.prolang, f where p.oid = f.oid), 'ausente'),
         'plpgsql secdef=true vol=s cfg=search_path="" owner=postgres acl=postgres=X/postgres,authenticated=X/postgres (PRE = POST)'
  union all
  select 7, 'G-07 EXECUTE por papel (authenticated, anon, service_role, PUBLIC)',
         coalesce((select has_function_privilege('authenticated', f.oid, 'EXECUTE') || ',' || has_function_privilege('anon', f.oid, 'EXECUTE')
                          || ',' || has_function_privilege('service_role', f.oid, 'EXECUTE')
                          || ',' || coalesce((select bool_or(a.grantee = 0) from pg_proc p, aclexplode(p.proacl) a where p.oid = f.oid), false)
                     from f where f.oid is not null), 'ausente'),
         'true,false,false,false (PRE = POST)'
  union all
  select 8, 'G-08 comentário',
         coalesce((select case when d like '%5363%' then 'menciona 5363' when d like '%5262%' then 'menciona 5262' else 'outro' end
                     from (select obj_description(f.oid, 'pg_proc') as d from f) s), 'ausente'),
         'PRE: menciona 5262 · POST: menciona 5363'
  union all
  select 9, 'G-09 dependentes (pg_depend) e corpos/views que citam a função',
         'pg_depend=' || coalesce((select count(*) from pg_depend d, f where d.refclassid = 'pg_proc'::regclass and d.refobjid = f.oid and d.deptype = 'n'), 0)
         || ' funcoes=' || (select count(*) from pg_proc p where p.prosrc ilike '%get_my_inventory_item_copies%' and p.proname <> 'get_my_inventory_item_copies')
         || ' views=' || (select count(*) from pg_views where definition ilike '%get_my_inventory_item_copies%'),
         'pg_depend=0 funcoes=0 views=0'
  union all
  select 10, 'G-10 fonte da 21ª coluna: physical_card.condition_code',
         coalesce((select format_type(atttypid, atttypmod) || ' notnull=' || attnotnull from pg_attribute
                    where attrelid = 'public.physical_card'::regclass and attname = 'condition_code' and not attisdropped), 'ausente'),
         'text notnull=true'
)
select ord, verificacao, got, esperado from checks order by ord;
