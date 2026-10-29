/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5291 - P3-B S6 · Histórico do Fichário — instrumentação E18 (Coleção desassociada)
              detach_my_collection_from_binder(uuid, text, boolean)
Versão......: 1.0 (2026-10-28, P3-B S6 — instrumentação E01, E16–E20)
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core (P3-B S6, autorização
              operacional do proprietário; harness dispensado sob H-A; ledger 20261028215554 `5291_instrument_detach_my_collection_from_binder`).
              Do `begin;` ao `commit;` idêntica ao arquivo de database/proposals/2026-10-25-
              p3b-binder-activity-history/ (só este bloco Status difere); enviada via
              apply_migration sem as linhas `begin;`/`commit;` externas — texto do ledger = corpo (md5).
              LIVE_S6_90 bloco A 6/6; bloco B: E18 comprovado (evento 104).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-28
Base........: 5253 (md5(prosrc) LIVE 09570bf964a8351c0f97acbc7ba9c736, conferido em 2026-10-28;
              canônico: database/schema/5253_binder_detach_keeps_positions.sql).
Autoridade..: README da proposta §4.1, §4.2, §14.7, §20 (W3), §33 (S6).

Diff mínimo: o corpo é o da base LIVE, byte a byte, mais as linhas marcadas com
"-- P3B-S6". Removidas essas linhas e trocado o delimitador $fn$ → $$, o corpo volta a
ter o md5 acima (static_check_p3b_s6.py). Assinatura, retorno, SET, mensagens, códigos de
erro, ordem de travas e permissões inalterados (REVOKE/GRANT originais reaplicados).

Evento COLLECTION_DETACHED (atômico), coleção = a convidada:
  · POCKET/UNLOCKED por bolso fixado solto (origem), RESERVATION/RELEASED por reserva da convidada
    (origem, via 5275) — ambos lidos ANTES da escrita, com o predicado dela;
  · 1 item COLLECTION/DETACHED. As posições (cartas) permanecem (5253) → nenhum item de carta.
  ALREADY_DETACHED sai antes do begin → nada gravado.
================================================================
*/

begin;

do $pre$
begin
  if to_regprocedure('public.binder_activity_add_card_item(text, uuid, uuid, uuid)') is null
     or to_regprocedure('public.binder_activity_add_reservation_item(text, uuid)') is null
     or to_regprocedure('public.binder_activity_add_pocket_shift_items(uuid, uuid)') is null
     or to_regprocedure('public.binder_activity_begin(uuid, text, text, uuid, jsonb)') is null then
    raise exception 'PRECHECK 5291: dependências ausentes (5268/5271/5275/5279)';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('public.detach_my_collection_from_binder(uuid, text, boolean)')) is distinct from '09570bf964a8351c0f97acbc7ba9c736' then
    raise exception 'PRECHECK 5291: função no LIVE diverge da base 5253 (md5)';
  end if;
end;
$pre$;

CREATE OR REPLACE FUNCTION public.detach_my_collection_from_binder(
  p_collection_id uuid,
  p_detach_token  text,
  p_release_locks boolean default false
)
returns table (
  outcome              text,     -- DETACHED | ALREADY_DETACHED
  assignments_removed  integer,
  reservations_removed integer,
  locks_released       integer
)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $fn$
#variable_conflict use_column
declare
  v_uid    uuid := auth.uid();
  v_layout uuid;
  v_owner  uuid;
  r        record;
  v_unlock integer := 0;
  v_asg    integer;
  v_exc    integer;
  v_act    record;  -- P3B-S6
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  if p_detach_token is null or p_detach_token !~ '^g1:[0-9a-f]{64}$' then
    raise exception 'INVALID_DETACH_TOKEN' using errcode = '22023';
  end if;

  perform 1 from public.collection c where c.id = p_collection_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  select g.layout_id, l.collection_id into v_layout, v_owner
  from public.collection_layout_guest g
  join public.collection_layout l on l.id = g.layout_id
  where g.collection_id = p_collection_id;
  if v_layout is null then
    outcome := 'ALREADY_DETACHED'; assignments_removed := 0; reservations_removed := 0; locks_released := 0;
    return next;
    return;
  end if;

  -- Ordem canônica: proprietária → layout → convidada. Qualquer lifecycle
  -- (desfazer participação é permitido mesmo arquivada, como a 5226).
  perform 1 from public.collection c where c.id = v_owner and c.owner_user_id = v_uid for update;
  perform 1 from public.collection_layout l where l.id = v_layout for update;
  perform 1 from public.collection c where c.id = p_collection_id for update;

  if not exists (select 1 from public.collection_layout_guest g
                 where g.collection_id = p_collection_id and g.layout_id = v_layout) then
    outcome := 'ALREADY_DETACHED'; assignments_removed := 0; reservations_removed := 0; locks_released := 0;
    return next;
    return;
  end if;

  select * into r from public.collection_binder_detach_snapshot(p_collection_id);
  if r.detach_token is distinct from p_detach_token then
    raise exception 'DETACH_PLAN_CHANGED';
  end if;

  if r.locked_count > 0 and not coalesce(p_release_locks, false) then
    raise exception 'LOCKED_SLOTS_REQUIRE_CONFIRMATION'
      using hint = 'confirme soltar os bolsos fixados com cartas ou reservas desta coleção';
  end if;

  -- E18: depois dos retornos ALREADY_DETACHED, do token e da confirmação de bolsos fixados.  -- P3B-S6
  -- Itens de origem ANTES das escritas (I-10), com os mesmos predicados do UPDATE e do DELETE.  -- P3B-S6
  perform public.binder_activity_begin(v_layout, 'COLLECTION_DETACHED', 'FICHARIO', p_collection_id);  -- P3B-S6
  for v_act in  -- P3B-S6
    select s.id as slot_id  -- P3B-S6
    from public.collection_layout_slot s  -- P3B-S6
    join public.collection_layout_page p on p.id = s.page_id  -- P3B-S6
    where p.layout_id = v_layout and s.locked  -- P3B-S6
      and exists (select 1 from public.collection_layout_slot_expected_content e  -- P3B-S6
                  where e.slot_id = s.id and e.collection_id = p_collection_id)  -- P3B-S6
    order by p.page_number, s.row_index, s.column_index  -- P3B-S6
  loop  -- P3B-S6
    perform public.binder_activity_add_item('POCKET', 'UNLOCKED', null, null, v_act.slot_id, null, null, null, null);  -- P3B-S6
  end loop;  -- P3B-S6
  for v_act in  -- P3B-S6
    select e.slot_id  -- P3B-S6
    from public.collection_layout_slot_expected_content e  -- P3B-S6
    join public.collection_layout_slot s on s.id = e.slot_id  -- P3B-S6
    join public.collection_layout_page p on p.id = s.page_id  -- P3B-S6
    where e.collection_id = p_collection_id and p.layout_id = v_layout  -- P3B-S6
    order by p.page_number, s.row_index, s.column_index  -- P3B-S6
  loop  -- P3B-S6
    perform public.binder_activity_add_reservation_item('RELEASED', v_act.slot_id);  -- P3B-S6
  end loop;  -- P3B-S6
  -- D6: solta só os bolsos fixados afetados.
  update public.collection_layout_slot s
     set locked = false
   where s.locked
     and s.page_id in (select p.id from public.collection_layout_page p where p.layout_id = v_layout)
     and exists (select 1 from public.collection_layout_slot_expected_content e
                 where e.slot_id = s.id and e.collection_id = p_collection_id);
  get diagnostics v_unlock = row_count;

  -- 5253 (D2): posições permanecem (exemplares continuam no fichário físico);
  -- só as reservas da convidada saem.
  v_asg := 0;

  delete from public.collection_layout_slot_expected_content e
   using public.collection_layout_slot s, public.collection_layout_page p
   where e.collection_id = p_collection_id
     and s.id = e.slot_id and p.id = s.page_id and p.layout_id = v_layout;
  get diagnostics v_exc = row_count;

  delete from public.collection_layout_guest g where g.collection_id = p_collection_id;
  perform public.binder_activity_add_item('COLLECTION', 'DETACHED', null, null, null, null, null, null,  -- P3B-S6
                                          jsonb_build_object('collection_id', p_collection_id));  -- P3B-S6

  if v_asg <> r.assignments_count or v_exc <> r.reservations_count or v_unlock <> r.locked_count then
    raise exception 'BINDER_DETACH_INCONSISTENT';
  end if;

  perform public.binder_activity_end();  -- P3B-S6
  outcome := 'DETACHED'; assignments_removed := v_asg; reservations_removed := v_exc; locks_released := v_unlock;
  return next;
end;
$fn$;

revoke all on function public.detach_my_collection_from_binder(uuid, text, boolean) from public;
revoke all on function public.detach_my_collection_from_binder(uuid, text, boolean) from anon;
grant execute on function public.detach_my_collection_from_binder(uuid, text, boolean) to authenticated;

commit;

/*
Resultado esperado: detach_my_collection_from_binder(uuid, text, boolean) recriada com o mesmo contrato; nenhum evento gravado pela instalação.
Como validar (só leitura): LIVE_S6_90_postcheck_readonly.sql, bloco A.
*/
