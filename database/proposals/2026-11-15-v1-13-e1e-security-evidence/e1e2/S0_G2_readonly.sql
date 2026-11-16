/*
================================================================
Projeto.....: Project Mimikyu
Arquivo.....: S0_G2_readonly.sql — S0 ampliada (antes) e pós-estado (depois) dos ensaios G2
Versão......: 1.0 (2026-11-15, `V1-13 / E1-E2 | PROTECTED CHAIN AND G2 TEST READINESS-01`)
Status......: PROPOSTA — NÃO EXECUTADA. Leitura do LIVE NÃO autorizada. Executar só com
              autorização expressa: imediatamente antes do ensaio (S0) e imediatamente
              depois (pós-estado). Chaves [=] precisam ser idênticas nas duas leituras;
              [~] são informativas. Amplia a P1_S0_POST_readonly.sql (E1-A), que continua
              válida para o P1 original.
Forma.......: UMA instrução SELECT, sem DO, sem set_config, sem escrita, sem tabela
              temporária. Canal: psql `-v ON_ERROR_STOP=1` dentro de
              `BEGIN READ ONLY; ... ; ROLLBACK;`.
O que decide (observável em S0) × o que só o ensaio mostra:
  S0  versão do PostgreSQL (e se há transaction_timeout); executor e papéis; dono e
      privilégios em storage.objects e nas tabelas que levam ACCESS EXCLUSIVE; md5 das
      funções canônicas que os prechecks e harnesses fixam; ausência de objetos da
      V1-13; políticas atuais de Storage; gatilhos e gatilhos de evento com efeito
      externo; publicações; extensões; últimas migrations do ledger; sessões com
      trava nas tabelas do ensaio; timeouts dos papéis da API; pré-requisitos e
      resíduo das fixtures.
  Só o ensaio: se o executor consegue de fato CREATE POLICY e LOCK em storage.objects;
      tempo real de retenção das travas; duração dos harnesses; comportamento das
      versões protegidas; efeito dos timeouts.
Chaves:
  ambiente [=]     versão, transaction_timeout disponível, recuperação, parâmetros, executor
  privilegios [=]  dono e privilégios por tabela travada; pertença do executor ao dono
  md5 [=]          corpos vigentes × canônicos (por nome; todas as sobrecargas)
  v113 [=]         estado da V1-13 no banco (S0: nada aplicado)
  storage [=]      buckets e políticas atuais de storage.objects nos buckets envolvidos
  gatilhos [=]     gatilhos não internos em public/auth/storage com marca de efeito externo
  eventos [=]      gatilhos de evento habilitados
  publicacoes [=]  publicações que incluem tabelas tocadas
  extensoes [=]    pg_net, http, dblink
  ledger [~]       últimas 15 migrations registradas
  sessoes [~]      sessões com trava nas tabelas do ensaio ou transação longa
  papeis_api [~]   rolconfig de anon/authenticated/authenticator
  fixture [=]      pré-requisitos de catálogo e de Pokédex das fixtures
  residuo [=]      linhas com marcas sintéticas dos harnesses (precisa ser 0)
  contagens [~]    volumes informativos (para M1–M7 e para comparar com o pós-estado)
================================================================
*/
select jsonb_build_object(
  'ambiente', jsonb_build_object(
    'server_version_num', current_setting('server_version_num')::int,
    'transaction_timeout_disponivel', exists (select 1 from pg_settings where name = 'transaction_timeout'),
    'client_connection_check_interval_disponivel', exists (select 1 from pg_settings where name = 'client_connection_check_interval'),
    'in_recovery', pg_is_in_recovery(),
    'default_transaction_read_only', current_setting('default_transaction_read_only'),
    'session_replication_role', current_setting('session_replication_role'),
    'log_statement', current_setting('log_statement'),
    'log_min_error_statement', current_setting('log_min_error_statement'),
    'current_user', current_user,
    'session_user', session_user,
    'pg_read_all_stats', pg_has_role(current_user, 'pg_read_all_stats', 'member')),
  'privilegios', (
    select jsonb_object_agg(t.rel, jsonb_build_object(
             'existe', to_regclass(t.rel) is not null,
             'dono', (select pg_get_userbyid(c.relowner) from pg_class c where c.oid = to_regclass(t.rel)),
             'executor_e_dono_ou_membro', (select pg_has_role(current_user, c.relowner, 'USAGE') from pg_class c where c.oid = to_regclass(t.rel)),
             'update_delete_truncate', case when to_regclass(t.rel) is null then null
                                            else has_table_privilege(current_user, to_regclass(t.rel), 'UPDATE, DELETE, TRUNCATE') end,
             'rls', (select c.relrowsecurity from pg_class c where c.oid = to_regclass(t.rel))))
    from (values ('public.collection_membership'), ('public.binder_activity_event'), ('public.binder_activity_item'),
                 ('storage.objects'), ('auth.users')) t(rel)),
  'md5', (
    select jsonb_object_agg(v.fn, jsonb_build_object(
             'vigentes', (select coalesce(jsonb_agg(md5(p.prosrc) order by md5(p.prosrc)), '[]'::jsonb)
                          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                          where n.nspname = 'public' and p.proname = v.fn),
             'canonico', v.expected,
             'confere', exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                                where n.nspname = 'public' and p.proname = v.fn and md5(p.prosrc) = v.expected)))
    from (values
      ('collection_share_role',                        'efdb495b5b703e9f093eb0f49a1d0a5d'),
      ('invite_collection_member',                     'ed7418f20c1004b23c58c68c84a6ae73'),
      ('get_my_collection_sharing',                    'e36aa9c675f6b8097b6a43292b62603f'),
      ('get_my_collection_invites',                    '74ea7dc1af9032e337b6c0e04ae7c478'),
      ('get_collections_shared_with_me',               '67b4395f013a2591fcb1e1585ba53a16'),
      ('get_shared_collection',                        '254d56f3f9c8097ee3d36e580c851c29'),
      ('assert_collection_layout_mutable',             'd600f36fade0b67c0fd5af33e9965070'),
      ('place_my_physical_card_in_slot',               '2672da179d73797ec5329c649b594202'),
      ('move_slot_assignment',                         'fe149c755b5f3b9181172e600c2238a3'),
      ('remove_slot_assignment',                       'e4b6c8cd8e8c61554ddc92304d602a73'),
      ('set_slot_expected_content',                    '33dde5013dbb491bd4a0452ab7ce8132'),
      ('clear_slot_expected_content',                  '0b8f26825ff713a24226548ffe3a63b7'),
      ('set_slot_lock',                                '651048a4bf7d3229904ef2a073c509c5'),
      ('update_collection_metadata',                   'a581235db9cabaf7043707a290f963b7'),
      ('set_my_collection_cover_finish',               '4f48d9161b4a29ecb23e7443e31d1806'),
      ('set_my_collection_cover_code',                 'd0d8cbfa517b9da3728a55af47de21cb'),
      ('set_my_collection_cover_logo',                 '5868fb1c8de760787d1128ac20a09507'),
      ('set_pokedex_position_assignment',              '8c572182a03025503e993e5ecc25e07a'),  -- 6123 (não 6122): ver bloqueio E2-D1
      ('remove_pokedex_position_assignment',           '26ef2d5da3312661111df0194dfc8ba2'),
      ('set_pokedex_position_primary_representative',  '6353dffe6c3877967997033dcc2bfd4c'),
      ('clear_pokedex_position_primary_representative','eeede3a5b871fbf07f81eb59ecea932f'),
      ('get_my_master_set_positions',                  '8b85264a6c7224a6fde9c9bffb723335'),
      ('get_my_pokedex_positions',                     '79d2cd331031b5c98c64f2c43ecb077f'),
      ('get_my_binder_activity',                       'fab40eb28280d7c62ca207642b35ff65'),
      ('binder_activity_add_item',                     '5ac90272cf7bc203e5d2316ea4eba7d4')
    ) v(fn, expected)),
  'v113', jsonb_build_object(
    'barreira', to_regclass('public.v1_13_barrier_state') is not null or to_regclass('public.v1_13_barrier_identity') is not null,
    'check_papel', (select pg_get_constraintdef(k.oid) from pg_constraint k
                     where k.conrelid = 'public.collection_membership'::regclass
                       and k.conname = 'chk_collection_membership_role'),
    'sobrecargas_convite', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                             where n.nspname = 'public' and p.proname = 'invite_collection_member'),
    'funcoes_v113', (select coalesce(jsonb_agg(p.proname order by p.proname), '[]'::jsonb)
                     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                     where n.nspname = 'public'
                       and (p.proname like 'editor\_%' or p.proname like 'v1\_13\_%'
                            or p.proname in ('collection_member_role', 'set_collection_member_role',
                                             'get_shared_binder_placeable_cards', 'get_shared_master_set_positions',
                                             'get_shared_pokedex_positions', 'get_shared_binder_activity',
                                             'get_shared_binder_activity_status', 'collection_cover_editor_folder_ok',
                                             'collection_cover_editor_can_upload', 'binder_activity_event_editor_type_guard'))),
    'colunas_5379', (select count(*) from information_schema.columns c
                     where c.table_schema = 'public'
                       and ((c.table_name = 'binder_activity_item' and c.column_name = 'collection_id')
                            or (c.table_name = 'binder_activity_event' and c.column_name = 'item_collection_recorded'))),
    'gatilho_5381', exists (select 1 from pg_trigger t where t.tgname = 'trg_bae_editor_event_type'),
    'participacoes_editor', (select count(*) from public.collection_membership m where m.role <> 'VIEWER')),
  'storage', jsonb_build_object(
    'buckets', (select coalesce(jsonb_object_agg(b.id, jsonb_build_object('public', b.public,
                         'file_size_limit', b.file_size_limit, 'mime', b.allowed_mime_types)), '{}'::jsonb)
                from storage.buckets b where b.id in ('collection-cover', 'binder-slot-image', 'card-set-logo')),
    'politicas', (select coalesce(jsonb_agg(p.policyname || ':' || p.cmd || ':' || array_to_string(p.roles, '|') order by p.policyname), '[]'::jsonb)
                  from pg_policies p
                  where p.schemaname = 'storage' and p.tablename = 'objects'
                    and (coalesce(p.qual, '') || coalesce(p.with_check, '')) ~ '(collection-cover|binder-slot-image|card-set-logo)')),
  'gatilhos', (
    select coalesce(jsonb_agg(jsonb_build_object('tabela', n.nspname || '.' || c.relname, 'gatilho', t.tgname,
             'funcao', p.proname, 'externo', p.prosrc ~* '(net\.|http_|pg_net|dblink|pg_notify|notify\s)')
             order by n.nspname, c.relname, t.tgname), '[]'::jsonb)
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    join pg_proc p on p.oid = t.tgfoid
    where not t.tgisinternal and n.nspname in ('public', 'auth', 'storage')),
  'eventos', (
    select coalesce(jsonb_agg(jsonb_build_object('evento', e.evtname, 'quando', e.evtevent, 'funcao', p.proname,
             'externo', p.prosrc ~* '(net\.|http_|pg_net|dblink)') order by e.evtname), '[]'::jsonb)
    from pg_event_trigger e join pg_proc p on p.oid = e.evtfoid
    where e.evtenabled <> 'D'),
  'publicacoes', (
    select coalesce(jsonb_agg(distinct pt.pubname || ':' || pt.schemaname || '.' || pt.tablename), '[]'::jsonb)
    from pg_publication_tables pt
    where pt.schemaname in ('public', 'auth', 'storage')),
  'extensoes', (
    select coalesce(jsonb_agg(x.extname || ':' || x.extversion order by x.extname), '[]'::jsonb)
    from pg_extension x where x.extname in ('pg_net', 'http', 'dblink')),
  'ledger', (
    select coalesce(jsonb_agg(m.version || ' ' || coalesce(m.name, '') order by m.version desc), '[]'::jsonb)
    from (select version, name from supabase_migrations.schema_migrations order by version desc limit 15) m),
  'sessoes', jsonb_build_object(
    'com_trava_nas_tabelas', (select count(distinct l.pid) from pg_locks l
                              where l.relation in (to_regclass('public.collection_membership'), to_regclass('public.binder_activity_event'),
                                                   to_regclass('public.binder_activity_item'), to_regclass('storage.objects'))
                                and l.pid <> pg_backend_pid()),
    'transacoes_longas', (select count(*) from pg_stat_activity a
                          where a.pid <> pg_backend_pid() and a.state <> 'idle'
                            and (a.xact_start is null or a.xact_start < clock_timestamp() - interval '1 second'))),
  'papeis_api', (
    select coalesce(jsonb_object_agg(r.rolname, coalesce(to_jsonb(r.rolconfig), 'null'::jsonb)), '{}'::jsonb)
    from pg_roles r where r.rolname in ('anon', 'authenticated', 'authenticator', 'service_role')),
  'fixture', jsonb_build_object(
    'jogo_pokemon', exists (select 1 from public.game g where g.code = 'POKEMON'),
    'idioma_pt_br', exists (select 1 from public.language l where l.code = 'pt-BR'),
    'variante_standard', exists (select 1 from public.card_variant_type t join public.game g on g.id = t.game_id
                                 where g.code = 'POKEMON' and t.code = 'STANDARD'),
    'categoria_pokemon', exists (select 1 from public.card_category c join public.game g on g.id = c.game_id
                                 where g.code = 'POKEMON' and c.code = 'POKEMON'),
    'carta_com_raridade', exists (select 1 from public.card c join public.card_set cs on cs.id = c.card_set_id
                                  join public.expansion e on e.id = cs.expansion_id join public.game g on g.id = e.game_id
                                  where g.code = 'POKEMON' and c.rarity_id is not null),
    'pokedex_national', exists (select 1 from public.pokedex d join public.pokedex_position pp on pp.pokedex_id = d.id
                                where d.code = 'NATIONAL')),
  'residuo', jsonb_build_object(
    'auth_users_wh', (select count(*) from auth.users where email ~ '^wh8[0-9]{2}' and email like '%@example.invalid'),
    'user_profile_wh', (select count(*) from public.user_profile where username ~ '^wh8[0-9]{2}'),
    'collection_wh', (select count(*) from public.collection where name ~ '^(C[A-Z] |X2 )58[6-9][0-9]'),
    'objetos_storage_wh', (select count(*) from storage.objects o
                           where o.bucket_id in ('collection-cover', 'binder-slot-image')
                             and o.owner_id in (select u.id::text from auth.users u where u.email like 'wh8%@example.invalid'))),
  'contagens', jsonb_build_object(
    'auth_users', (select count(*) from auth.users),
    'membership', (select coalesce(jsonb_object_agg(r.k, r.n), '{}'::jsonb)
                   from (select m.role || '/' || m.status as k, count(*) as n from public.collection_membership m group by 1) r),
    'collection', (select count(*) from public.collection),
    'physical_card', (select count(*) from public.physical_card),
    'binder_activity_event', (select count(*) from public.binder_activity_event),
    'binder_activity_item', (select count(*) from public.binder_activity_item),
    'storage_objects', (select count(*) from storage.objects))
) as s0;
