/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5384 - Histórico do fichário: tipos de evento do EDITOR para as
              operações da E1-C2 (V1-13 · E1-C2) — CREATE OR REPLACE da função do
              gatilho trg_bae_editor_event_type (5381)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA. Preparada em
              `V1-13 / E1-C2 | REMAINING BULK OPERATIONS-01` (2026-11-15).
              Execução só com prova dinâmica sob protocolo controlado (C-244) e
              autorização expressa e específica.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-15
Contrato....: C-234, C-237, C-241.
Depende de..: E1-C1 (5381).

A 5381 fixou a lista dos 11 tipos que as funções do EDITOR abriam. A E1-C2 cria
funções que abrem exatamente QUATRO tipos novos — cada um com a função que o produz:
  GAP_OPENED                      editor_insert_binder_gap (5385)        origem FICHARIO
  GAP_CLOSED                      editor_close_binder_gap (5385)         origem FICHARIO
  CARDS_AUTO_ARRANGED             editor_apply_binder_auto_arrange (5386) origem FICHARIO
  CATALOG_NOVELTIES_INCORPORATED  editor_apply_binder_catalog_reconciliation (5387)
                                                                         origem CATALOGO
A origem fica igual à do titular (5283/5284/5360/5296). A regra passa a ser POR
PAR (tipo, origem): os 14 tipos de fichário só com FICHARIO; as novidades só com
CATALOGO. Nada mais muda: coleção obrigatória, só para ator ≠ titular; titular e
legado intactos. Continuam fora: montagem, associação, desassociação,
desmontagem, exclusão, transferência e saídas pelo acervo.
Mudança: só o corpo da função do gatilho (CREATE OR REPLACE; gatilho, ACL e
  comentário preservados).
Canal.......: psql. Precheck: md5 do corpo vigente = 5381 (b5da9a1258f26e53f31c206c5d5c442b).
Idempotência: corpo já igual ao desta proposta (78fa0d34dad161eac1165f3143874260) → 'JÁ APLICADA'.
Reversão....: R5384 em ROLLBACK_E1C2.sql (reaplica o corpo da 5381).
Como validar: harness 5893, seção 4.
================================================================
*/

begin;

set local lock_timeout = '5s';

do $pre$
declare
  v_m text := (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
               where p.oid = to_regprocedure('public.binder_activity_event_editor_type_guard()'));
begin
  if v_m = '78fa0d34dad161eac1165f3143874260' then
    raise exception 'PRECHECK 5384: JÁ APLICADA — não reaplicar';
  end if;
  if v_m is distinct from 'b5da9a1258f26e53f31c206c5d5c442b' then
    raise exception 'PRECHECK 5384: ESTADO DIVERGENTE — corpo vigente difere da 5381 (%)', v_m;
  end if;
end;
$pre$;

create or replace function public.binder_activity_event_editor_type_guard()
returns trigger
language plpgsql
set search_path = ''
as $fn$
begin
  if new.actor_user_id is not null and new.actor_user_id is distinct from new.owner_user_id then
    if new.collection_id is null
       or not (
         (new.event_type in ('CARD_PLACED', 'CARD_MOVED', 'CARDS_SWAPPED', 'CARDS_REMOVED',
                             'POCKET_RESERVED', 'RESERVATIONS_RELEASED', 'POCKETS_LOCKED', 'POCKETS_UNLOCKED',
                             'PAGES_ADDED', 'PAGE_REMOVED', 'PAGES_REORDERED',
                             'GAP_OPENED', 'GAP_CLOSED', 'CARDS_AUTO_ARRANGED')
          and new.source = 'FICHARIO')
         or (new.event_type = 'CATALOG_NOVELTIES_INCORPORATED' and new.source = 'CATALOGO')) then
      raise exception 'binder activity: event type not allowed for this actor' using errcode = '42501',
        hint = 'BINDER_ACTIVITY_EVENT_TYPE';
    end if;
  end if;
  return new;
end;
$fn$;

do $post$
begin
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.binder_activity_event_editor_type_guard()')) is distinct from '78fa0d34dad161eac1165f3143874260'
     or not exists (select 1 from pg_catalog.pg_trigger t
                    where t.tgrelid = 'public.binder_activity_event'::regclass and t.tgname = 'trg_bae_editor_event_type'
                      and t.tgenabled = 'O')
     or pg_catalog.has_function_privilege('authenticated', to_regprocedure('public.binder_activity_event_editor_type_guard()'), 'EXECUTE') then
    raise exception 'POSTCHECK 5384: gatilho fora do estado esperado';
  end if;
end;
$post$;

commit;
