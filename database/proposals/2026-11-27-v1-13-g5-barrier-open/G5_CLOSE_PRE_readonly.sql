/*
V1-13 · Etapa 7 — PRE do FECHAMENTO / ROLLBACK (somente leitura, um SELECT, modo gate). Só registra o estado antes de
fechar; não impede fechar a partir de OPEN ou TEST (é também o STOP de emergência). Sem as chaves 'barreira' e
'identidades_teste' de propósito.
*/

select jsonb_build_object(
  'executor',                      current_user,
  'estado_barreira_presente',      exists (select 1 from public.v1_13_barrier_state s where s.id = 1),
  'modo_atual',                    (select s.mode from public.v1_13_barrier_state s where s.id = 1),
  'identidades_n',                 (select count(*) from public.v1_13_barrier_identity)
) as g5_close_pre;
