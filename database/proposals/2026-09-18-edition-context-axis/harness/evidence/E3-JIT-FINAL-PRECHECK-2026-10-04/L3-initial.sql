SELECT jsonb_build_object(
    'sessions', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                    'pid', a.pid, 'usename', a.usename, 'application_name', a.application_name,
                    'backend_type', a.backend_type, 'state', a.state,
                    'wait_event_type', a.wait_event_type, 'wait_event', a.wait_event,
                    'xact_start', a.xact_start, 'state_change', a.state_change,
                    'backend_xid', a.backend_xid::text) ORDER BY a.backend_type, a.state, a.pid)
                  FROM pg_stat_activity a
                 WHERE a.pid <> pg_backend_pid() AND a.datname = current_database()), '[]'::jsonb),
    'locks_on_scope', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                    'pid', l.pid, 'relation', c.relname, 'mode', l.mode, 'granted', l.granted) ORDER BY c.relname, l.pid)
                  FROM pg_locks l JOIN pg_class c ON c.oid = l.relation
                 WHERE l.pid <> pg_backend_pid()
                   AND c.relname IN ('card_edition_context_trait','card_edition_context_profile',
                                     'card_edition_context_profile_trait','card_edition_context_external_mapping',
                                     'card_edition_context_external_mapping_trait','card_variant',
                                     'catalog_variant_import_job','catalog_variant_import_row',
                                     'catalog_admin_action_log','game')), '[]'::jsonb),
    'checked_at', clock_timestamp()
) AS l3_concurrency;
