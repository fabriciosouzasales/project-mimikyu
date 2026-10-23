/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5237 / R1-pós — Pós-checagem SOMENTE LEITURA no LIVE
Versão......: 1.1 (2026-10-23, CORRECTION-01: função sem argumentos)
Status......: PREPARADO — NÃO EXECUTADO.
Executar....: logo após a 5237, com o mesmo papel, em transação read only.
Não prova o envio real: isso é o F1 (classe F, autorização própria).
================================================================
*/

begin transaction read only;

-- POST-1 — Estrutura (todas `ok` = true) ------------------------------------------------
with pol as (
  select p.* from pg_policies p
  where p.schemaname = 'storage' and p.tablename = 'objects'
    and p.policyname = 'binder_slot_image_insert_own'
), fn as (
  select p.oid, p.prosecdef, p.provolatile, p.proconfig, p.proowner, p.prorettype
  from pg_proc p where p.oid = to_regprocedure('public.binder_slot_image_under_object_cap()')
)
select * from (values
  ('Q1', (select count(*) from pol) = 1 and (select cmd from pol) = 'INSERT'
         and (select roles from pol) = array['authenticated']::name[],
         'mesma política, INSERT, só authenticated'),
  ('Q2', (select with_check not like '%storage.objects%' and with_check not like '%count(%' from pol),
         'sem autorreferência (causa da recursão removida)'),
  ('Q3', (select with_check like '%binder-slot-image%' and with_check like '%foldername%'
                 and with_check like '%auth.uid()%' and with_check like '%(webp|jpg)%' from pol),
         'bucket, pasta = auth.uid() e nome canônico preservados'),
  ('Q4', (select with_check like '%binder_slot_image_under_object_cap()%' from pol)
         and (select pronargs = 0 and prosrc like '%< 550%' and prosrc like '%auth.uid()%'
                from pg_proc where oid = (select oid from fn)),
         'teto 550 fixo na função sem argumentos; usuário só por auth.uid()'),
  ('Q5', (select prosecdef and provolatile = 's' and prorettype = 'boolean'::regtype
                 and proconfig @> array['search_path=""'] from fn),
         'função SECURITY DEFINER, STABLE, booleana, search_path vazio'),
  ('Q6', (select r.rolbypassrls or r.rolsuper from fn join pg_roles r on r.oid = fn.proowner),
         'dono da função lê storage.objects sem RLS (sem recursão)'),
  ('Q7', has_function_privilege('authenticated', 'public.binder_slot_image_under_object_cap()', 'EXECUTE')
         and not has_function_privilege('anon', 'public.binder_slot_image_under_object_cap()', 'EXECUTE')
         and (select p.proacl is not null from pg_proc p join fn on fn.oid = p.oid)
         and not exists (select 1 from pg_proc p join fn on fn.oid = p.oid, aclexplode(p.proacl) a
                          where a.grantee = 0),
         'EXECUTE só authenticated (nem anon, nem PUBLIC)'),
  ('Q8', not exists (select 1 from pg_policies p where p.schemaname = 'storage' and p.tablename = 'objects'
                       and p.policyname like 'binder\_slot\_image\_%' and p.cmd in ('UPDATE','ALL')),
         'continua sem UPDATE/ALL no bucket')
) t(check_id, ok, description);

-- POST-2 — Nada além da política e da função mudou (comparar com PRE-5) ------------
select
  (select count(*) from storage.objects o where o.bucket_id = 'binder-slot-image') as objects_in_bucket,
  (select count(*) from public.collection_layout_slot_image)                        as images,
  (select count(*) from pg_policies p where p.schemaname = 'storage' and p.tablename = 'objects') as storage_object_policies,
  md5(coalesce((select string_agg(p.policyname || '|' || p.cmd || '|' || p.roles::text || '|' ||
                                  coalesce(p.qual, '') || '|' || coalesce(p.with_check, ''), E'\n' order by p.policyname)
                from pg_policies p
                where p.schemaname = 'storage' and p.tablename = 'objects'
                  and p.policyname <> 'binder_slot_image_insert_own'), '')) as fp_other_storage_policies,
  (select b.public::text || '|' || b.file_size_limit::text || '|' || b.allowed_mime_types::text
     from storage.buckets b where b.id = 'binder-slot-image') as bucket_config;
-- PASS: os cinco valores IGUAIS aos do PRE-5 (inclusive fp_other_storage_policies —
-- prova que SELECT/DELETE e as 21 políticas pré-existentes não mudaram).

-- POST-3 — Ledger ------------------------------------------------------------------------
select m.version, m.name from supabase_migrations.schema_migrations m
where m.name like '5237%';
-- PASS: exatamente 1 linha.

rollback;

-- POST-4 — get_advisors(security): achado novo esperado só da classe já existente
-- (0029 — função SECURITY DEFINER executável por authenticated), como as demais do pacote.
