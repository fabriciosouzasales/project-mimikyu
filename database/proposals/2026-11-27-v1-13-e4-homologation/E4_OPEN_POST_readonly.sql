/*
V1-13 · E4 — POST da ABERTURA (somente leitura, um SELECT, modo gate). Sem as chaves 'barreira' e 'identidades_teste'
(o executor as exige CLOSED/0): o modo TEST e o registro são provados por booleanos próprios.
*/

select jsonb_build_object(
  'executor',                                           current_user,
  'modo_teste',                                         (select s.mode from public.v1_13_barrier_state s where s.id = 1) = 'TEST',
  'registro_igual_contas',                              (select count(*) from public.v1_13_barrier_identity) = 4
                                 and not exists (select 1 from public.v1_13_barrier_identity i where i.user_id not in (select up.id from public.user_profile up where md5(up.username) in ('827f042802bd9c8f2524e4ef0c69e980', 'c87549f021e1d4ecd308b7514ee54229', 'aff41bfce3aefe2cd8e48622f0db56a3', '0de10d7efb9cb0d4eb1a7ebbcaf57ef7'))),
  'funcoes_barreira_canonicas',                         (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_assert_capability()')) = 'e4f710904f50e6e8c3f1d8e2337639e0'
                                 and (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_capability_open()')) = '32e2f636361732b497e8401e50f0bbe0',
  'contas_conjunto_4',                                  (select count(*) from public.user_profile up where md5(up.username) in ('827f042802bd9c8f2524e4ef0c69e980', 'c87549f021e1d4ecd308b7514ee54229', 'aff41bfce3aefe2cd8e48622f0db56a3', '0de10d7efb9cb0d4eb1a7ebbcaf57ef7')) = 4,
  'titular_com_colecoes',                               exists (select 1 from public.collection c where c.owner_user_id = (select up.id from public.user_profile up where md5(up.username) = '827f042802bd9c8f2524e4ef0c69e980') and c.lifecycle_status = 'ACTIVE'),
  'sem_editor_fora_do_conjunto',                        not exists (select 1 from public.collection_membership m join public.collection c on c.id = m.collection_id
                                 where m.role = 'EDITOR' and (m.user_id not in (select up.id from public.user_profile up where md5(up.username) in ('827f042802bd9c8f2524e4ef0c69e980', 'c87549f021e1d4ecd308b7514ee54229', 'aff41bfce3aefe2cd8e48622f0db56a3', '0de10d7efb9cb0d4eb1a7ebbcaf57ef7')) or c.owner_user_id not in (select up.id from public.user_profile up where md5(up.username) in ('827f042802bd9c8f2524e4ef0c69e980', 'c87549f021e1d4ecd308b7514ee54229', 'aff41bfce3aefe2cd8e48622f0db56a3', '0de10d7efb9cb0d4eb1a7ebbcaf57ef7')))),
  'sem_auditoria_colecao_fora_do_conjunto',             not exists (select 1 from public.collection_activity_event e where e.owner_user_id not in (select up.id from public.user_profile up where md5(up.username) in ('827f042802bd9c8f2524e4ef0c69e980', 'c87549f021e1d4ecd308b7514ee54229', 'aff41bfce3aefe2cd8e48622f0db56a3', '0de10d7efb9cb0d4eb1a7ebbcaf57ef7'))),
  'admins_no_conjunto_n',                               (select count(*) from public.admin_user a where a.id in (select up.id from public.user_profile up where md5(up.username) in ('827f042802bd9c8f2524e4ef0c69e980', 'c87549f021e1d4ecd308b7514ee54229', 'aff41bfce3aefe2cd8e48622f0db56a3', '0de10d7efb9cb0d4eb1a7ebbcaf57ef7'))),
  'membros_fora_do_conjunto_nas_colecoes_do_titular_n', (select count(*) from public.collection_membership m
                                 where m.collection_id in (select c.id from public.collection c where c.owner_user_id = (select up.id from public.user_profile up where md5(up.username) = '827f042802bd9c8f2524e4ef0c69e980')) and m.user_id not in (select up.id from public.user_profile up where md5(up.username) in ('827f042802bd9c8f2524e4ef0c69e980', 'c87549f021e1d4ecd308b7514ee54229', 'aff41bfce3aefe2cd8e48622f0db56a3', '0de10d7efb9cb0d4eb1a7ebbcaf57ef7'))),
  'participacoes_do_conjunto_em_colecoes_de_fora_n',    (select count(*) from public.collection_membership m join public.collection c on c.id = m.collection_id
                                 where m.user_id in (select up.id from public.user_profile up where md5(up.username) in ('827f042802bd9c8f2524e4ef0c69e980', 'c87549f021e1d4ecd308b7514ee54229', 'aff41bfce3aefe2cd8e48622f0db56a3', '0de10d7efb9cb0d4eb1a7ebbcaf57ef7')) and c.owner_user_id not in (select up.id from public.user_profile up where md5(up.username) in ('827f042802bd9c8f2524e4ef0c69e980', 'c87549f021e1d4ecd308b7514ee54229', 'aff41bfce3aefe2cd8e48622f0db56a3', '0de10d7efb9cb0d4eb1a7ebbcaf57ef7'))),
  'eventos_editor_externos_n',                          (select count(*) from public.binder_activity_event b
                                 where b.actor_user_id is not null and b.actor_user_id <> b.owner_user_id and b.actor_user_id not in (select up.id from public.user_profile up where md5(up.username) in ('827f042802bd9c8f2524e4ef0c69e980', 'c87549f021e1d4ecd308b7514ee54229', 'aff41bfce3aefe2cd8e48622f0db56a3', '0de10d7efb9cb0d4eb1a7ebbcaf57ef7')))
) as e4_open_post;
