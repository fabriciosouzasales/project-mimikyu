/*
================================================================
Projeto.....: Project Mimikyu
Query.......: E4-OPEN — ativa o modo TEST da barreira 5389 para as 4 contas do conjunto E4 (V1-13 · E4)
Versão......: 1.0 (2026-11-27, `E4 — FINAL HOMOLOGATION EXECUTION READINESS`)
Status......: PREPARADA — NÃO EXECUTADA. Só com autorização expressa e específica, pelo executor por
              arquivo (E4_OPEN_MANIFEST.txt). Não é migration: muda só o estado da barreira.
Efeito......: registra as 4 contas do conjunto E4 (identificadas pelo md5 do username; titular, EDITOR,
              EDITOR 2 e VIEWER) em v1_13_barrier_identity e muda o modo para TEST. Qualquer conta fora do
              registro continua negada pela porta (5389).
Reversão....: E4_TEST_CLOSE.sql (CLOSED + registro vazio).
================================================================
*/

begin;
set local lock_timeout = '5s';

do $pre$
begin
  if (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'CLOSED'
     or (select count(*) from public.v1_13_barrier_identity) <> 0 then
    raise exception 'PRECHECK E4-OPEN: barreira não está CLOSED com registro vazio';
  end if;
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_assert_capability()')) is distinct from 'e4f710904f50e6e8c3f1d8e2337639e0'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_capability_open()')) is distinct from '32e2f636361732b497e8401e50f0bbe0' then
    raise exception 'PRECHECK E4-OPEN: funções da porta diferem do canônico';
  end if;
  if not ((select count(*) from public.user_profile up where md5(up.username) in ('827f042802bd9c8f2524e4ef0c69e980', 'c87549f021e1d4ecd308b7514ee54229', 'aff41bfce3aefe2cd8e48622f0db56a3', '0de10d7efb9cb0d4eb1a7ebbcaf57ef7')) = 4) or not (exists (select 1 from public.collection c where c.owner_user_id = (select up.id from public.user_profile up where md5(up.username) = '827f042802bd9c8f2524e4ef0c69e980') and c.lifecycle_status = 'ACTIVE')) or not (not exists (select 1 from public.collection_membership m join public.collection c on c.id = m.collection_id
                                 where m.role = 'EDITOR' and (m.user_id not in (select up.id from public.user_profile up where md5(up.username) in ('827f042802bd9c8f2524e4ef0c69e980', 'c87549f021e1d4ecd308b7514ee54229', 'aff41bfce3aefe2cd8e48622f0db56a3', '0de10d7efb9cb0d4eb1a7ebbcaf57ef7')) or c.owner_user_id not in (select up.id from public.user_profile up where md5(up.username) in ('827f042802bd9c8f2524e4ef0c69e980', 'c87549f021e1d4ecd308b7514ee54229', 'aff41bfce3aefe2cd8e48622f0db56a3', '0de10d7efb9cb0d4eb1a7ebbcaf57ef7'))))) or not (not exists (select 1 from public.collection_activity_event e where e.owner_user_id not in (select up.id from public.user_profile up where md5(up.username) in ('827f042802bd9c8f2524e4ef0c69e980', 'c87549f021e1d4ecd308b7514ee54229', 'aff41bfce3aefe2cd8e48622f0db56a3', '0de10d7efb9cb0d4eb1a7ebbcaf57ef7')))) then
    raise exception 'PRECHECK E4-OPEN: conjunto de contas incompleto, titular sem coleções ou isolamento violado';
  end if;
end;
$pre$;

insert into public.v1_13_barrier_identity (user_id, note)
select up.id, 'E4: conjunto de homologação'
from public.user_profile up
where md5(up.username) in ('827f042802bd9c8f2524e4ef0c69e980', 'c87549f021e1d4ecd308b7514ee54229', 'aff41bfce3aefe2cd8e48622f0db56a3', '0de10d7efb9cb0d4eb1a7ebbcaf57ef7');

update public.v1_13_barrier_state
   set mode = 'TEST', changed_at = now(), change_note = 'E4: homologação V1-13 (4 identidades do conjunto)'
 where id = 1;

do $post$
begin
  if (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'TEST'
     or (select count(*) from public.v1_13_barrier_identity) <> 4
     or exists (select 1 from public.v1_13_barrier_identity i where i.user_id not in (select up.id from public.user_profile up where md5(up.username) in ('827f042802bd9c8f2524e4ef0c69e980', 'c87549f021e1d4ecd308b7514ee54229', 'aff41bfce3aefe2cd8e48622f0db56a3', '0de10d7efb9cb0d4eb1a7ebbcaf57ef7'))) then
    raise exception 'POSTCHECK E4-OPEN: modo ou registro fora do esperado';
  end if;
end;
$post$;

commit;
