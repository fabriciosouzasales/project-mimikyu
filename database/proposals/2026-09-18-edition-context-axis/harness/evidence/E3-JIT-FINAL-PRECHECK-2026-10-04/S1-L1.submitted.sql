SELECT jsonb_build_object(
    'current_user',                        current_user,
    'session_user',                        session_user,
    'is_superuser',                        (SELECT rolsuper FROM pg_roles WHERE rolname = current_user),
    'reads_all_stats',                     pg_has_role(current_user, 'pg_read_all_stats', 'USAGE'),
    'in_recovery',                         pg_is_in_recovery(),
    'transaction_read_only',               current_setting('transaction_read_only'),
    'default_transaction_read_only',       current_setting('default_transaction_read_only'),
    'statement_timeout',                   current_setting('statement_timeout'),
    'lock_timeout',                        current_setting('lock_timeout'),
    'idle_in_transaction_session_timeout', current_setting('idle_in_transaction_session_timeout'),
    'standard_conforming_strings',         current_setting('standard_conforming_strings'),
    'server_version_num',                  current_setting('server_version_num'),
    'application_name',                    current_setting('application_name'),
    'backend_pid',                         pg_backend_pid(),
    'activity_rows_state_hidden',          (SELECT count(*) FROM pg_stat_activity
                                             WHERE pid <> pg_backend_pid()
                                               AND backend_type = 'client backend'
                                               AND state IS NULL),
    'visible_foreign_sessions',            (SELECT count(*) FROM pg_stat_activity a
                                             WHERE a.pid <> pg_backend_pid()
                                               AND a.backend_type = 'client backend'
                                               AND a.usename IS NOT NULL
                                               AND NOT pg_has_role(current_user, a.usename, 'MEMBER')
                                               AND a.state IS NOT NULL),
    'ec_table_owner',                      (SELECT jsonb_object_agg(c.relname, pg_get_userbyid(c.relowner) ORDER BY c.relname)
                                              FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                                             WHERE n.nspname = 'public' AND c.relkind = 'r'
                                               AND c.relname LIKE 'card\_edition\_context%'),
    'checked_at',                          clock_timestamp()
) AS l1_channel;
