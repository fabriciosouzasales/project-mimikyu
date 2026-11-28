/*
================================================================
Projeto.....: Project Mimikyu
Query.......: G5-CLOSE — fecha a barreira 5389: CLOSED e registro vazio (V1-13 · etapa 7, rollback/STOP)
Versão......: 1.0 (2026-11-27, rodada A da abertura funcional)
Status......: PREPARADA — NÃO EXECUTADA. Pelo executor por arquivo (G5_CLOSE_MANIFEST.txt). Sem pré-condição
              que impeça fechar: serve de reversão da abertura e de STOP de emergência.
Efeito......: modo CLOSED e nenhuma identidade. Não apaga dados gravados enquanto aberta (ficam inertes:
              leituras V1-13 vazias e escritas com CAPABILITY_NOT_ENABLED).
================================================================
*/

begin;
set local lock_timeout = '5s';

update public.v1_13_barrier_state
   set mode = 'CLOSED', changed_at = now(), change_note = 'V1-13 etapa 7: fechamento (rollback ou STOP)'
 where id = 1;

delete from public.v1_13_barrier_identity;

do $post$
begin
  if (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'CLOSED'
     or (select count(*) from public.v1_13_barrier_identity) <> 0 then
    raise exception 'POSTCHECK G5-CLOSE: barreira não ficou CLOSED com registro vazio';
  end if;
end;
$post$;

commit;
