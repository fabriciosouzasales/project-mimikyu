SELECT 'IMG|' || t || '|' || n || '|' || h FROM (
    SELECT 'public.game' AS t, count(*) AS n, md5(coalesce(string_agg(r::text, '|' ORDER BY r.id::text), '')) AS h FROM public.game r
    UNION ALL SELECT 'public.expansion', count(*), md5(coalesce(string_agg(r::text, '|' ORDER BY r.id::text), '')) FROM public.expansion r
    UNION ALL SELECT 'public.card_set', count(*), md5(coalesce(string_agg(r::text, '|' ORDER BY r.id::text), '')) FROM public.card_set r
    UNION ALL SELECT 'public.rarity', count(*), md5(coalesce(string_agg(r::text, '|' ORDER BY r.id::text), '')) FROM public.rarity r
    UNION ALL SELECT 'public.card_category', count(*), md5(coalesce(string_agg(r::text, '|' ORDER BY r.id::text), '')) FROM public.card_category r
    UNION ALL SELECT 'public.card_variant_type', count(*), md5(coalesce(string_agg(r::text, '|' ORDER BY r.id::text), '')) FROM public.card_variant_type r
    UNION ALL SELECT 'public.card', count(*), md5(coalesce(string_agg(r::text, '|' ORDER BY r.id::text), '')) FROM public.card r
    UNION ALL SELECT 'public.card_variant', count(*), md5(coalesce(string_agg(r::text, '|' ORDER BY r.id::text), '')) FROM public.card_variant r
    UNION ALL SELECT 'public.catalog_variant_import_job', count(*), md5(coalesce(string_agg(r::text, '|' ORDER BY r.id::text), '')) FROM public.catalog_variant_import_job r
    UNION ALL SELECT 'public.catalog_variant_import_row', count(*), md5(coalesce(string_agg(r::text, '|' ORDER BY r.id::text), '')) FROM public.catalog_variant_import_row r
    UNION ALL SELECT 'public.catalog_admin_action_log', count(*), md5(coalesce(string_agg(r::text, '|' ORDER BY r.id::text), '')) FROM public.catalog_admin_action_log r
    UNION ALL SELECT 'public.admin_user', count(*), md5(coalesce(string_agg(r::text, '|' ORDER BY r.id::text), '')) FROM public.admin_user r
    UNION ALL SELECT 'auth.users(id,updated_at,last_sign_in_at)', count(*), md5(coalesce(string_agg(r.id::text || ',' || coalesce(r.updated_at::text, '') || ',' || coalesce(r.last_sign_in_at::text, ''), '|' ORDER BY r.id::text), '')) FROM auth.users r
) x ORDER BY t;
SELECT 'GLOBAL|' || coalesce(string_agg(format('%I.%I', s.nspname, c.relname) || '=' ||
       (xpath('/row/n/text()', query_to_xml(format('select count(*) as n from %I.%I', s.nspname, c.relname), false, true, '')))[1]::text,
       ',' ORDER BY s.nspname, c.relname), '')
  FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace s ON s.oid = c.relnamespace
 WHERE c.relkind IN ('r', 'p') AND s.nspname IN ('public', 'auth', 'internal');