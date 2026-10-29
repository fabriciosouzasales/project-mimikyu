/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5276 - P3-B S3 · Histórico do Fichário — instrumentação E08 (Bolso reservado)
              set_slot_expected_content(uuid, uuid, uuid, uuid, uuid)
Versão......: 1.0 (2026-10-27, P3-B S3 — instrumentação E08–E10)
Status......: PROPOSTA — NÃO EXECUTADA. Exige autorização própria para o LIVE.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-27
Base........: 5229 (LIVE = canônico: md5(prosrc) 56a9aa74307e3708b34c014f471a4cd6, conferido em 2026-10-27).
Autoridade..: README da proposta §4.1, §7.2, §20 (W3), §30 (S3).

Diff mínimo: o corpo é o da base, byte a byte, mais as linhas marcadas com
"-- P3B-S3" (só begin/add_item/end e o necessário para elas). Removidas essas linhas e
trocado o delimitador $fn$ → $$, o corpo volta a ter o md5 acima
(static_check_p3b_s3.py). Assinatura, retorno, SET, mensagens, códigos de erro, ordem de
travas e permissões inalterados (REVOKE/GRANT originais reaplicados de forma idempotente).

Evento POCKET_RESERVED (atômico, um bolso):
  · bolso sem reserva → 1 item RESERVATION/RESERVED (destino = bolso);
  · bolso com reserva diferente → RESERVATION/RELEASED da anterior (origem = bolso, lido antes
    do upsert) + RESERVATION/RESERVED da nova (destino = bolso, lido depois);
  · reserva idêntica (mesma carta, variante, acabamento e coleção) → nenhum item, nenhum evento
    (C-206). Coleção do evento = coleção dona da reserva (D8).
================================================================
*/

begin;

do $pre$
begin
  if to_regprocedure('public.binder_activity_add_reservation_item(text, uuid)') is null then
    raise exception 'PRECHECK 5276: aplique 5268 e 5275 antes';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('public.set_slot_expected_content(uuid, uuid, uuid, uuid, uuid)')) is distinct from '56a9aa74307e3708b34c014f471a4cd6' then
    raise exception 'PRECHECK 5276: função no LIVE diverge da base 5229 (md5)';
  end if;
end;
$pre$;

CREATE OR REPLACE FUNCTION public.set_slot_expected_content(
  p_slot_id                  uuid,
  p_card_id                  uuid,
  p_card_variant_id          uuid default null,
  p_expected_variant_type_id uuid default null,
  p_collection_id            uuid default null
)
returns table (
  slot_id                  uuid,
  card_id                  uuid,
  card_variant_id          uuid,
  expected_variant_type_id uuid,
  collection_id            uuid
)
language plpgsql
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_layout_id        uuid;
  v_owner_collection uuid;
  v_target           uuid;
  v_status           text;
  v_hist_same        boolean;  -- P3B-S3
begin
  if (select auth.uid()) is null then
    raise exception 'authentication required';
  end if;

  select p.layout_id into v_layout_id
    from public.collection_layout_slot s
    join public.collection_layout_page p on p.id = s.page_id
    join public.collection_layout l      on l.id = p.layout_id
    join public.collection c             on c.id = l.collection_id
   where s.id = p_slot_id
     and c.owner_user_id = (select auth.uid());
  if not found then
    raise exception 'layout slot not found or not owned by caller';
  end if;

  begin
    v_owner_collection := public.assert_collection_layout_mutable(v_layout_id);
  exception
    when others then
      if sqlerrm like 'collection layout not found%' then
        raise exception 'layout slot not found or not owned by caller';
      end if;
      raise;
  end;

  perform 1 from public.collection_layout_slot s where s.id = p_slot_id for update;

  perform 1
     from public.collection_layout_slot s
     join public.collection_layout_page p on p.id = s.page_id
    where s.id = p_slot_id and p.layout_id = v_layout_id;
  if not found then
    raise exception 'layout slot not found or not owned by caller';
  end if;

  if p_card_id is null then
    raise exception 'p_card_id é obrigatório';
  end if;
  if p_card_variant_id is not null and p_expected_variant_type_id is not null then
    raise exception 'EXPECTED_CONTENT_VARIANT_AND_TYPE_EXCLUSIVE: informe a variante específica OU o acabamento, não os dois'
      using errcode = '22023';
  end if;

  -- D8: a reserva pertence a p_collection_id; sem ele, à coleção da carta
  -- que ocupa o bolso; sem carta, à proprietária.
  v_target := p_collection_id;
  if v_target is null then
    select ca.collection_id into v_target
    from public.collection_layout_slot_assignment a
    join public.collection_allocation ca on ca.id = a.collection_allocation_id
    where a.slot_id = p_slot_id;
  end if;
  v_target := coalesce(v_target, v_owner_collection);

  if v_target <> v_owner_collection then
    -- Convidada deste fichário, do mesmo dono, ativa (mesma mensagem para
    -- não participante, inexistente ou alheia).
    select c.lifecycle_status into v_status
    from public.collection_layout_guest g
    join public.collection c on c.id = g.collection_id
    where g.collection_id = v_target and g.layout_id = v_layout_id
      and c.owner_user_id = (select auth.uid())
    for share of c;
    if not found then
      raise exception 'collection not found or not a participant of this binder';
    end if;
    if v_status <> 'ACTIVE' then
      raise exception 'COLLECTION_ARCHIVED';
    end if;
  end if;

  -- E08: estado anterior lido sob a trava do bolso (null = sem reserva; true = idêntica → sem item).  -- P3B-S3
  select (e.card_id, e.card_variant_id, e.expected_variant_type_id, e.collection_id)  -- P3B-S3
         is not distinct from (p_card_id, p_card_variant_id, p_expected_variant_type_id, v_target)  -- P3B-S3
    into v_hist_same  -- P3B-S3
    from public.collection_layout_slot_expected_content e where e.slot_id = p_slot_id;  -- P3B-S3
  perform public.binder_activity_begin(v_layout_id, 'POCKET_RESERVED', 'FICHARIO', v_target);  -- P3B-S3
  if v_hist_same is false then  -- P3B-S3
    perform public.binder_activity_add_reservation_item('RELEASED', p_slot_id);  -- reserva anterior, antes de sobrescrever (I-10)  -- P3B-S3
  end if;  -- P3B-S3
  begin
    insert into public.collection_layout_slot_expected_content as ec
      (slot_id, card_id, card_variant_id, expected_variant_type_id, collection_id)
    values
      (p_slot_id, p_card_id, p_card_variant_id, p_expected_variant_type_id, v_target)
    on conflict on constraint collection_layout_slot_expected_content_pkey
    do update set card_id                  = excluded.card_id,
                  card_variant_id          = excluded.card_variant_id,
                  expected_variant_type_id = excluded.expected_variant_type_id,
                  collection_id            = excluded.collection_id;
  exception
    when foreign_key_violation then
      raise exception
        'Card/Card Variant/acabamento inválido — quando informada, a Card Variant deve pertencer à Card indicada e o acabamento deve existir';
  end;

  if v_hist_same is distinct from true then  -- P3B-S3
    perform public.binder_activity_add_reservation_item('RESERVED', p_slot_id);  -- depois de gravar (I-10)  -- P3B-S3
  end if;  -- P3B-S3
  return query
  select e.slot_id, e.card_id, e.card_variant_id, e.expected_variant_type_id, e.collection_id
    from public.collection_layout_slot_expected_content e
   where e.slot_id = p_slot_id;
  perform public.binder_activity_end();  -- P3B-S3
end;
$fn$;

revoke all on function public.set_slot_expected_content(uuid, uuid, uuid, uuid, uuid) from public;
revoke all on function public.set_slot_expected_content(uuid, uuid, uuid, uuid, uuid) from anon;
grant execute on function public.set_slot_expected_content(uuid, uuid, uuid, uuid, uuid) to authenticated;

commit;
