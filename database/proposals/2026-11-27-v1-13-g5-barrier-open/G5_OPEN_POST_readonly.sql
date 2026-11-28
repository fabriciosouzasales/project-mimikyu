/*
V1-13 · Etapa 7 — POST da ABERTURA (somente leitura, um SELECT, modo gate). Sem a chave 'barreira' (o executor a
exige CLOSED): o modo OPEN é provado pelo booleano 'modo_aberto'. Registro de identidades continua vazio.
*/

select jsonb_build_object(
  'executor',                      current_user,
  'modo_aberto',                   coalesce((select s.mode from public.v1_13_barrier_state s where s.id = 1) = 'OPEN', false),
  'identidades_teste',             (select count(*) from public.v1_13_barrier_identity),
  'estado_barreira_unico',         (select count(*) from public.v1_13_barrier_state) = 1,
  'funcoes_barreira_canonicas',    coalesce((select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_assert_capability()')) = 'e4f710904f50e6e8c3f1d8e2337639e0'
                                 and (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_capability_open()')) = '32e2f636361732b497e8401e50f0bbe0', false)
) as g5_open_post;
