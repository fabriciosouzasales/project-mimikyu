/*
V1-13 · Etapa 7 — PRE da ABERTURA (somente leitura, um SELECT, modo gate). PASS = barreira CLOSED, 0 identidades,
funções da porta canônicas e as entregas da E4 presentes no banco (5397 e 5398).
*/

select jsonb_build_object(
  'executor',                      current_user,
  'barreira',                      (select s.mode from public.v1_13_barrier_state s where s.id = 1),
  'identidades_teste',             (select count(*) from public.v1_13_barrier_identity),
  'estado_barreira_unico',         (select count(*) from public.v1_13_barrier_state) = 1,
  'funcoes_barreira_canonicas',    coalesce((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_assert_capability()')) = 'e4f710904f50e6e8c3f1d8e2337639e0'
                                 and (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_capability_open()')) = '32e2f636361732b497e8401e50f0bbe0', false),
  'entrega_5397_presente',         exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                                    where n.nspname = 'public' and p.proname = 'get_shared_binder_placeable_copies'),
  'entrega_5398_presente',         to_regprocedure('public.get_my_binder_activity_actors(uuid, bigint[])') is not null
) as g5_open_pre;
