/*
V1-13 · E4 — PRE do ENCERRAMENTO (somente leitura, um SELECT, modo gate). Só registra o estado antes de fechar;
o único critério é a linha de estado existir. Esperado após a E4 ou um STOP: modo_atual = TEST, identidades_n = 4,
identidades_fora_do_conjunto_n = 0 (se diferente: fechar mesmo assim e registrar como incidente).
*/

select jsonb_build_object(
  'executor',                       current_user,
  'estado_barreira_presente',       exists (select 1 from public.v1_13_barrier_state s where s.id = 1),
  'modo_atual',                     (select s.mode from public.v1_13_barrier_state s where s.id = 1),
  'identidades_n',                  (select count(*) from public.v1_13_barrier_identity),
  'identidades_fora_do_conjunto_n', (select count(*) from public.v1_13_barrier_identity i where i.user_id not in (select up.id from public.user_profile up where md5(up.username) in ('827f042802bd9c8f2524e4ef0c69e980', 'c87549f021e1d4ecd308b7514ee54229', 'aff41bfce3aefe2cd8e48622f0db56a3', '0de10d7efb9cb0d4eb1a7ebbcaf57ef7'))),
  'eventos_editor_externos_n',      (select count(*) from public.binder_activity_event b
                                 where b.actor_user_id is not null and b.actor_user_id <> b.owner_user_id and b.actor_user_id not in (select up.id from public.user_profile up where md5(up.username) in ('827f042802bd9c8f2524e4ef0c69e980', 'c87549f021e1d4ecd308b7514ee54229', 'aff41bfce3aefe2cd8e48622f0db56a3', '0de10d7efb9cb0d4eb1a7ebbcaf57ef7')))
) as e4_close_pre;
