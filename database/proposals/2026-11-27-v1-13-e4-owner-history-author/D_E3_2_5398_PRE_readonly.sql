/*
V1-13 · D-E3-2 — 5398: PRE SOMENTE LEITURA (um SELECT, modo gate). PASS = booleanos true, barreira CLOSED, 0 identidades.
*/

select jsonb_build_object(
  'executor',                   current_user,
  'barreira',                   (select s.mode from public.v1_13_barrier_state s where s.id = 1),
  'identidades_teste',          (select count(*) from public.v1_13_barrier_identity),
  'funcoes_barreira_canonicas', (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_assert_capability()')) = 'e4f710904f50e6e8c3f1d8e2337639e0'
                                and (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_capability_open()')) = '32e2f636361732b497e8401e50f0bbe0',
  'ausente_5398',               to_regprocedure('public.get_my_binder_activity_actors(uuid, bigint[])') is null,
  'leitura_5269_presente',      to_regprocedure('public.get_my_binder_activity(uuid, text[], timestamptz, bigint, integer)') is not null,
  'pode_criar_em_public',       pg_catalog.has_schema_privilege(current_user, 'public', 'CREATE')
) as d_e3_2_5398_pre;
