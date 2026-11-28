/*
================================================================
Projeto.....: Project Mimikyu
Query.......: E4-CLOSE — encerra o modo TEST: barreira CLOSED e registro de identidades vazio (V1-13 · E4)
Versão......: 1.0 (2026-11-27, `E4 — FINAL HOMOLOGATION EXECUTION READINESS`)
Status......: PREPARADA — NÃO EXECUTADA. Pelo executor por arquivo (E4_CLOSE_MANIFEST.txt), com
              autorização. É também o STOP da E4: sem pré-condição que impeça fechar.
Efeito......: modo CLOSED e nenhuma identidade registrada. Não apaga contas, coleções, convites nem
              eventos da homologação (ficam nas contas do conjunto, inertes com a barreira fechada).
================================================================
*/

begin;
set local lock_timeout = '5s';

update public.v1_13_barrier_state
   set mode = 'CLOSED', changed_at = now(), change_note = 'E4: encerramento do TEST'
 where id = 1;

delete from public.v1_13_barrier_identity;

do $post$
begin
  if (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'CLOSED'
     or (select count(*) from public.v1_13_barrier_identity) <> 0 then
    raise exception 'POSTCHECK E4-CLOSE: barreira não ficou CLOSED com registro vazio';
  end if;
end;
$post$;

commit;
