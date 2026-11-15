/*
================================================================
Projeto.....: Project Mimikyu
Arquivo.....: P1_S0_POST_readonly.sql — S0 (antes) e pós-estado (depois) do ensaio P1 da E1-A
Versão......: 1.1 (2026-11-15, `V1-13 / E1-A | P1 INDEPENDENT ARTIFACT AUDIT-04`: contagens
              passam a informativas (uso real as altera); resíduos por marca sintética
              também em auth.users e card; pré-requisitos da fixture; visibilidade de
              pg_stat_activity; timeouts dos papéis da API; sessão sem início visível
              conta como risco). 1.0 (`P1 ARTIFACT PREPARATION-03`)
Status......: PROPOSTA — NÃO EXECUTADA. Leitura do LIVE NÃO autorizada nesta rodada.
              Executar só com autorização expressa: uma vez imediatamente antes do
              ensaio (S0) e uma vez imediatamente depois (pós-estado). Os dois
              resultados precisam ser IDÊNTICOS nas chaves marcadas [=]; as
              marcadas [~] são informativas (podem mudar por uso real entre as
              duas leituras e não provam nem reprovam o ensaio).
Forma.......: UMA instrução SELECT, sem DO, sem set_config, sem escrita, sem
              tabela temporária, sem nextval. Seguro em transação somente leitura.
              Canal: psql com `-v ON_ERROR_STOP=1` dentro de
              `BEGIN READ ONLY; ... ; ROLLBACK;` ou SQL Editor (só leitura).
Saída.......: um objeto JSON (coluna s0). Chaves:
  ambiente   versão, recuperação, parâmetros de sessão e de log, usuário
  md5        corpos vigentes de 5302/5303/5308/5309/5311/5312 e comparação com os
             canônicos derivados de database/schema/ (precisam ser true na S0) [=]
  e1a        estado da E1-A no banco: CHECK, sobrecargas, funções novas (S0: não
             aplicada) [=]
  acl        ACL completa das funções afetadas [=]
  contagens  auth.users, participações por papel/estado, coleções, exemplares [~]
  residuo    linhas com marcas sintéticas da 5888 (precisa ser 0) [=]
  fixture    pré-requisitos de catálogo da 5888 (precisam ser true na S0)
  visibilidade  pode ver início de transação de outras sessões (pg_read_all_stats)
  papeis_api statement_timeout configurado em anon/authenticated/authenticator [~]
  gatilhos   gatilhos não internos das tabelas tocadas, com marca de efeito externo
  eventos    gatilhos de evento habilitados, com marca de efeito externo
  publicacoes publicações que incluem as tabelas tocadas
  extensoes  extensões instaladas relevantes (pg_net, http, dblink)
  sessoes    sessões com lock em collection_membership e transação aberta há > 1 s
================================================================
*/
select jsonb_build_object(
  'ambiente', jsonb_build_object(
    'server_version_num', current_setting('server_version_num')::int,
    'in_recovery', pg_is_in_recovery(),
    'default_transaction_read_only', current_setting('default_transaction_read_only'),
    'session_replication_role', current_setting('session_replication_role'),
    'log_statement', current_setting('log_statement'),
    'log_min_error_statement', current_setting('log_min_error_statement'),
    'current_user', current_user,
    'session_user', session_user),
  'md5', (
    select jsonb_object_agg(x.fn, jsonb_build_object('md5', x.m, 'canonico', x.m = x.expected))
    from (
      select v.fn, v.expected,
             (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure(v.sig)) as m
      from (values
        ('5302', 'public.collection_share_role(uuid)',            'efdb495b5b703e9f093eb0f49a1d0a5d'),
        ('5303', 'public.invite_collection_member(uuid, text)',   'ed7418f20c1004b23c58c68c84a6ae73'),
        ('5308', 'public.get_my_collection_sharing(uuid)',        'e36aa9c675f6b8097b6a43292b62603f'),
        ('5309', 'public.get_my_collection_invites()',            '74ea7dc1af9032e337b6c0e04ae7c478'),
        ('5311', 'public.get_collections_shared_with_me()',       '67b4395f013a2591fcb1e1585ba53a16'),
        ('5312', 'public.get_shared_collection(uuid)',            '254d56f3f9c8097ee3d36e580c851c29')
      ) v(fn, sig, expected)
    ) x),
  'e1a', jsonb_build_object(
    'check_papel', (select pg_get_constraintdef(k.oid) from pg_constraint k
                     where k.conrelid = 'public.collection_membership'::regclass
                       and k.conname = 'chk_collection_membership_role'),
    'sobrecargas_convite', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                             where n.nspname = 'public' and p.proname = 'invite_collection_member'),
    'convite_3_args', to_regprocedure('public.invite_collection_member(uuid, text, text)') is not null,
    'collection_member_role', to_regprocedure('public.collection_member_role(uuid)') is not null,
    'set_collection_member_role', to_regprocedure('public.set_collection_member_role(uuid, uuid, text)') is not null),
  'acl', (
    select jsonb_object_agg(v.sig, (
             select coalesce(string_agg(a::text, ',' order by a::text), '<NULL>')
             from pg_proc p cross join lateral unnest(p.proacl) a
             where p.oid = to_regprocedure(v.sig)))
    from (values ('public.collection_share_role(uuid)'), ('public.invite_collection_member(uuid, text)'),
                 ('public.remove_collection_member(uuid, uuid)'), ('public.get_my_collection_sharing(uuid)'),
                 ('public.get_my_collection_invites()'), ('public.get_collections_shared_with_me()'),
                 ('public.get_shared_collection(uuid)')) v(sig)),
  'contagens', jsonb_build_object(
    'auth_users', (select count(*) from auth.users),
    'membership', (select coalesce(jsonb_object_agg(r.k, r.n), '{}'::jsonb)
                   from (select m.role || '/' || m.status as k, count(*) as n
                         from public.collection_membership m group by 1) r),
    'collection', (select count(*) from public.collection),
    'physical_card', (select count(*) from public.physical_card),
    'expansion', (select count(*) from public.expansion),
    'card_set', (select count(*) from public.card_set)),
  'residuo', jsonb_build_object(
    'user_profile_wh888', (select count(*) from public.user_profile where username like 'wh888%'),
    'auth_users_wh888', (select count(*) from auth.users where email like 'wh888%@example.invalid'),
    'card_edr', (select count(*) from public.card where name = 'EDR K1'),
    'expansion_edr', (select count(*) from public.expansion where code like 'EDR\_%'),
    'collection_5888', (select count(*) from public.collection where name in ('CO 5888', 'CX 5888'))),
  'gatilhos', (
    select coalesce(jsonb_agg(jsonb_build_object('tabela', n.nspname || '.' || c.relname, 'gatilho', t.tgname,
             'funcao', p.proname, 'externo', p.prosrc ~* '(net\.|http_|pg_net|dblink|pg_notify|notify\s)')
             order by n.nspname, c.relname, t.tgname), '[]'::jsonb)
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    join pg_proc p on p.oid = t.tgfoid
    where not t.tgisinternal and n.nspname in ('public', 'auth')
      and c.relname in ('users', 'collection_membership', 'collection', 'expansion', 'card_set', 'card',
                        'card_variant', 'physical_card', 'inventory', 'user_profile', 'collection_allocation',
                        'collection_layout', 'collection_layout_page', 'collection_layout_slot',
                        'collection_layout_slot_assignment', 'collection_layout_slot_expected_content',
                        'binder_activity_event', 'binder_activity_item')),
  'eventos', (
    select coalesce(jsonb_agg(jsonb_build_object('evento', e.evtname, 'quando', e.evtevent, 'funcao', p.proname,
             'externo', p.prosrc ~* '(net\.|http_|pg_net|dblink)') order by e.evtname), '[]'::jsonb)
    from pg_event_trigger e join pg_proc p on p.oid = e.evtfoid
    where e.evtenabled <> 'D'),
  'publicacoes', (
    select coalesce(jsonb_agg(distinct pt.pubname || ':' || pt.schemaname || '.' || pt.tablename), '[]'::jsonb)
    from pg_publication_tables pt
    where pt.schemaname in ('public', 'auth')
      and pt.tablename in ('users', 'collection_membership', 'collection', 'physical_card', 'user_profile')),
  'extensoes', (
    select coalesce(jsonb_agg(x.extname order by x.extname), '[]'::jsonb)
    from pg_extension x where x.extname in ('pg_net', 'http', 'dblink')),
  'sessoes', (
    select count(*)
    from pg_locks l join pg_stat_activity a on a.pid = l.pid
    where l.relation = to_regclass('public.collection_membership')
      and l.pid <> pg_backend_pid()
      and (a.xact_start is null or a.xact_start < clock_timestamp() - interval '1 second')),
  'fixture', jsonb_build_object(
    'jogo_pokemon', exists (select 1 from public.game g where g.code = 'POKEMON'),
    'idioma_pt_br', exists (select 1 from public.language l where l.code = 'pt-BR'),
    'variante_standard', exists (select 1 from public.card_variant_type t join public.game g on g.id = t.game_id
                                 where g.code = 'POKEMON' and t.code = 'STANDARD'),
    'carta_com_raridade', exists (select 1 from public.card c join public.card_set cs on cs.id = c.card_set_id
                                  join public.expansion e on e.id = cs.expansion_id join public.game g on g.id = e.game_id
                                  where g.code = 'POKEMON' and c.rarity_id is not null)),
  'visibilidade', jsonb_build_object(
    'pg_read_all_stats', pg_has_role(current_user, 'pg_read_all_stats', 'member')),
  'papeis_api', (
    select coalesce(jsonb_object_agg(r.rolname, coalesce(to_jsonb(r.rolconfig), 'null'::jsonb)), '{}'::jsonb)
    from pg_roles r where r.rolname in ('anon', 'authenticated', 'authenticator'))
) as s0;
