/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5381 - Histórico do fichário: tipos de evento que um ator que não é o
              titular (EDITOR) pode gravar (V1-13 · E1-C) — gatilho BEFORE INSERT
              em binder_activity_event
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA. Preparada em
              `V1-13 / E1-C | COLLECTION-SCOPED BULK OPERATIONS-01` (2026-11-15).
              Execução só com prova dinâmica sob protocolo controlado (C-244) e
              autorização expressa e específica.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-15
Contrato....: C-234 (fronteira do EDITOR), C-237 (operações por coleção), C-238
              (estrutura do fichário é do titular), C-241 (gravação com ator EDITOR).
Depende de..: E1-B1 (5372), E1-B3 (5379).

Requisito registrado na E1-B3: restringir os tipos de evento que o EDITOR pode
produzir. Feito como GATILHO, não como nova versão de binder_activity_add_item:
  - vale para QUALQUER caminho que grave evento (função atual, contexto forjado,
    função futura), porque fica na tabela;
  - não muda o corpo da gravação (md5 da 5379 preservado, fixado nos harnesses
    5889 e 5891).
Regra (só para linha nova cujo ator existe e é diferente do titular do evento):
  - event_type na lista fechada abaixo — exatamente os tipos que as funções do
    EDITOR (E1-B1, E1-B2, E1-C) produzem; nenhum tipo é liberado "para o futuro";
  - source = 'FICHARIO';
  - collection_id preenchido (a coleção autorizada; a 5372 já exige EDITOR ativo
    dela).
  Lista: CARD_PLACED, CARD_MOVED, CARDS_SWAPPED, CARDS_REMOVED (E1-B1);
         POCKET_RESERVED, RESERVATIONS_RELEASED, POCKETS_LOCKED, POCKETS_UNLOCKED
         (E1-B2); PAGES_ADDED, PAGE_REMOVED, PAGES_REORDERED (E1-C).
  Fora (titular): montagem, associação, desassociação, desmontagem, exclusão,
    transferência (E01, E17–E20), saídas pelo acervo (E06, E07), espaços (E11,
    E12), novidades do Catálogo (E16), organização automática (E21) e legado.
  Recusa: 42501 BINDER_ACTIVITY_EVENT_TYPE (a operação inteira é desfeita).
Titular (ator = titular) e legado (ator NULL): sem mudança.
Canal.......: psql. Idempotência: gatilho já presente → 'JÁ APLICADA ou DIVERGENTE'.
Reversão....: R5381 em ROLLBACK_E1C.sql (remove gatilho e função; nada é apagado).
Como validar: harness 5892, seção 5.
================================================================
*/

begin;

set local lock_timeout = '5s';

do $pre$
begin
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)'))
     is distinct from 'f8cfba40e442e85056e7c8ce7954d4f4' then
    raise exception 'PRECHECK 5381: E1-B3 (5379) não aplicada';
  end if;
  if exists (select 1 from pg_catalog.pg_trigger t
             where t.tgrelid = 'public.binder_activity_event'::regclass and t.tgname = 'trg_bae_editor_event_type')
     or to_regprocedure('public.binder_activity_event_editor_type_guard()') is not null then
    raise exception 'PRECHECK 5381: JÁ APLICADA ou ESTADO DIVERGENTE';
  end if;
end;
$pre$;

create function public.binder_activity_event_editor_type_guard()
returns trigger
language plpgsql
set search_path = ''
as $fn$
begin
  if new.actor_user_id is not null and new.actor_user_id is distinct from new.owner_user_id then
    if new.event_type not in ('CARD_PLACED', 'CARD_MOVED', 'CARDS_SWAPPED', 'CARDS_REMOVED',
                              'POCKET_RESERVED', 'RESERVATIONS_RELEASED', 'POCKETS_LOCKED', 'POCKETS_UNLOCKED',
                              'PAGES_ADDED', 'PAGE_REMOVED', 'PAGES_REORDERED')
       or new.source is distinct from 'FICHARIO'
       or new.collection_id is null then
      raise exception 'binder activity: event type not allowed for this actor' using errcode = '42501',
        hint = 'BINDER_ACTIVITY_EVENT_TYPE';
    end if;
  end if;
  return new;
end;
$fn$;

comment on function public.binder_activity_event_editor_type_guard() is
  'V1-13 E1-C (5381): evento novo com ator diferente do titular só com tipo de curadoria da lista fechada, origem FICHARIO e coleção registrada. Titular e legado sem mudança.';

revoke all on function public.binder_activity_event_editor_type_guard() from public, anon, authenticated, service_role;

create trigger trg_bae_editor_event_type
  before insert on public.binder_activity_event
  for each row execute function public.binder_activity_event_editor_type_guard();

do $post$
begin
  if not exists (select 1 from pg_catalog.pg_trigger t
                 where t.tgrelid = 'public.binder_activity_event'::regclass and t.tgname = 'trg_bae_editor_event_type'
                   and t.tgenabled = 'O')
     or pg_catalog.has_function_privilege('authenticated', to_regprocedure('public.binder_activity_event_editor_type_guard()'), 'EXECUTE')
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
          where p.oid = to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)'))
        is distinct from 'f8cfba40e442e85056e7c8ce7954d4f4' then
    raise exception 'POSTCHECK 5381: gatilho fora do estado esperado';
  end if;
end;
$post$;

commit;
