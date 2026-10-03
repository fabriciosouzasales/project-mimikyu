select (select count(*) from auth.users)::text || '|' || (select count(*) from public.admin_user)::text || '|'
    || (select count(*) from public.catalog_admin_action_log)::text || '|'
    || (select count(*) from public.admin_user a join auth.users u on u.id = a.id)::text || '|'
    || coalesce((select a.id::text from public.admin_user a join auth.users u on u.id = a.id), 'NONE') || '|'
    || ((select count(*) from public.game) + (select count(*) from public.expansion) + (select count(*) from public.card_set)
      + (select count(*) from public.rarity) + (select count(*) from public.card_category) + (select count(*) from public.card_variant_type)
      + (select count(*) from public.card) + (select count(*) from public.card_variant) + (select count(*) from public.catalog_variant_import_job)
      + (select count(*) from public.catalog_variant_import_row))::text;