/*
================================================================
Projeto.....: Project Mimikyu
Query.......: G5-OPEN — abre a barreira 5389 para todos os autenticados (V1-13 · etapa 7)
Versão......: 1.0 (2026-11-27, rodada A da abertura funcional)
Status......: PREPARADA — NÃO EXECUTADA. Só com o parecer G5 = GO e autorização expressa do proprietário,
              pelo executor por arquivo (G5_OPEN_MANIFEST.txt). Não é migration: muda só o estado da barreira.
Efeito......: modo OPEN. As capacidades novas da V1-13 passam a valer para qualquer conta autenticada;
              cada operação continua decidida no servidor por papel, participação e posse (5366–5398).
              Nenhuma identidade é registrada (o registro só existe no modo TEST).
Reversão....: G5_BARRIER_CLOSE.sql (CLOSED + registro vazio), pelo G5_CLOSE_MANIFEST.txt. Sem deploy.
================================================================
*/

begin;
set local lock_timeout = '5s';

do $pre$
begin
  if (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'CLOSED'
     or (select count(*) from public.v1_13_barrier_identity) <> 0 then
    raise exception 'PRECHECK G5-OPEN: barreira não está CLOSED com registro vazio';
  end if;
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_assert_capability()')) is distinct from 'e4f710904f50e6e8c3f1d8e2337639e0'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_capability_open()')) is distinct from '32e2f636361732b497e8401e50f0bbe0' then
    raise exception 'PRECHECK G5-OPEN: funções da porta diferem do canônico';
  end if;
end;
$pre$;

update public.v1_13_barrier_state
   set mode = 'OPEN', changed_at = now(), change_note = 'V1-13 etapa 7: abertura funcional (G5 GO do proprietário)'
 where id = 1;

do $post$
begin
  if (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'OPEN'
     or (select count(*) from public.v1_13_barrier_identity) <> 0 then
    raise exception 'POSTCHECK G5-OPEN: modo diferente de OPEN ou registro não vazio';
  end if;
end;
$post$;

commit;
