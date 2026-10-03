select 'K1IMG|' || count(*)::text || '|' || md5(coalesce(string_agg(x, '|' order by x), '')) from (
    select 'g' || r::text as x from public.game r where r.id::text like 'c16b0100-%'
    union all select 'e' || r::text from public.expansion r where r.id::text like 'c16b0100-%'
    union all select 's' || r::text from public.card_set r where r.id::text like 'c16b0100-%'
    union all select 'r' || r::text from public.rarity r where r.id::text like 'c16b0100-%'
    union all select 'k' || r::text from public.card_category r where r.id::text like 'c16b0100-%'
    union all select 't' || r::text from public.card_variant_type r where r.id::text like 'c16b0100-%'
    union all select 'c' || r::text from public.card r where r.id::text like 'c16b0100-%'
    union all select 'j' || r::text from public.catalog_variant_import_job r where r.id::text like 'c16b0100-%'
    union all select 'w' || r::text from public.catalog_variant_import_row r where r.id::text like 'c16b0100-%'
    union all select 'v' || r::text from public.card_variant r where r.card_id = 'c16b0100-0000-4000-8000-000000000021'
    union all select 'l' || r::text from public.catalog_admin_action_log r where r.entity_id in ('c16b0100-0000-4000-8000-000000000031', 'c16b0100-0000-4000-8000-000000000032')
) s;