select (select count(*) from auth.users)::text || '|' || (select count(*) from public.admin_user)::text || '|'
    || (select count(*) from public.catalog_admin_action_log)::text || '|'
    || (select count(*) from public.admin_user a join auth.users u on u.id = a.id)::text || '|'
    || current_setting('transaction_read_only');