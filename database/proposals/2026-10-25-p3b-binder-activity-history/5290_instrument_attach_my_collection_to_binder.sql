/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5290 - P3-B S6 · Histórico do Fichário — instrumentação E17 (Coleção associada)
              attach_my_collection_to_binder(uuid, uuid)
Versão......: 1.0 (2026-10-28, P3-B S6 — instrumentação E01, E16–E20)
Status......: PROPOSTA — NÃO EXECUTADA. Exige autorização própria para o LIVE.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-28
Base........: 5255 (md5(prosrc) LIVE 1b87933cf804aa3fc29f8659dc947e2c, conferido em 2026-10-28;
              canônico: database/schema/5255_binder_attach_by_physical_location.sql).
Autoridade..: README da proposta §4.1, §4.2, §14.7, §20 (W3), §33 (S6).

Diff mínimo: o corpo é o da base LIVE, byte a byte, mais as linhas marcadas com
"-- P3B-S6". Removidas essas linhas e trocado o delimitador $fn$ → $$, o corpo volta a
ter o md5 acima (static_check_p3b_s6.py). Assinatura, retorno, SET, mensagens, códigos de
erro, ordem de travas e permissões inalterados (REVOKE/GRANT originais reaplicados).

Evento COLLECTION_ATTACHED (atômico): 1 item COLLECTION/ATTACHED (detalhe: coleção). Nenhum
bolso é tocado (D3). ALREADY_ATTACHED sai antes do begin → nada gravado (C-206).
================================================================
*/

begin;

do $pre$
begin
  if to_regprocedure('public.binder_activity_add_card_item(text, uuid, uuid, uuid)') is null
     or to_regprocedure('public.binder_activity_add_reservation_item(text, uuid)') is null
     or to_regprocedure('public.binder_activity_add_pocket_shift_items(uuid, uuid)') is null
     or to_regprocedure('public.binder_activity_begin(uuid, text, text, uuid, jsonb)') is null then
    raise exception 'PRECHECK 5290: dependências ausentes (5268/5271/5275/5279)';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('public.attach_my_collection_to_binder(uuid, uuid)')) is distinct from '1b87933cf804aa3fc29f8659dc947e2c' then
    raise exception 'PRECHECK 5290: função no LIVE diverge da base 5255 (md5)';
  end if;
end;
$pre$;

CREATE OR REPLACE FUNCTION public.attach_my_collection_to_binder(
  p_collection_id uuid,
  p_layout_id     uuid
)
returns table (
  outcome             text,    -- ATTACHED | ALREADY_ATTACHED
  layout_id           uuid,
  owner_collection_id uuid
)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $fn$
#variable_conflict use_column
declare
  v_uid        uuid := auth.uid();
  v_owner_coll uuid;
  v_status     text;
  v_default    uuid;
  v_kind       text;
  v_current    uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null or p_layout_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  -- 1. Fichário pelo dono (sem trava): inexistente e alheio no mesmo ramo.
  select l.collection_id into v_owner_coll
  from public.collection_layout l
  join public.collection c on c.id = l.collection_id
  where l.id = p_layout_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_owner_coll = p_collection_id then
    raise exception 'BINDER_SELF' using errcode = '22023';
  end if;

  -- 2. Proprietária → layout (trava + ACTIVE), ordem canônica (5122).
  begin
    perform public.assert_collection_layout_mutable(p_layout_id);
  exception
    when others then
      if sqlerrm like 'collection layout not found%' then
        raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
      end if;
      if sqlerrm like 'collection is ARCHIVED%' then
        raise exception 'BINDER_ARCHIVED';
      end if;
      raise;
  end;

  -- 3. Convidada (trava).
  select c.lifecycle_status, c.default_storage_container_id into v_status, v_default
  from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_uid
  for update;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_status <> 'ACTIVE' then
    raise exception 'COLLECTION_ARCHIVED';
  end if;

  -- 4. Idempotência e participação única (D-única).
  select g.layout_id into v_current
  from public.collection_layout_guest g where g.collection_id = p_collection_id;
  if v_current is not null then
    if v_current = p_layout_id then
      outcome := 'ALREADY_ATTACHED'; layout_id := p_layout_id; owner_collection_id := v_owner_coll;
      return next;
      return;
    end if;
    raise exception 'COLLECTION_ALREADY_IN_BINDER';
  end if;
  if exists (select 1 from public.collection_layout l where l.collection_id = p_collection_id) then
    raise exception 'COLLECTION_HAS_OWN_BINDER';
  end if;

  -- 5. Local físico (D9): o local padrão da convidada é um fichário e é o
  --    local padrão de algum participante deste fichário.
  if v_default is not null then
    select sc.kind_code::text into v_kind
    from public.storage_container sc
    join public.inventory i on i.id = sc.inventory_id
    where sc.id = v_default and i.owner_user_id = v_uid;
  end if;
  -- 5255 (D2 da rodada READINESS): compatibilidade pelo local físico PRÓPRIO
  -- do fichário (5247), não pelo local padrão da proprietária/participantes.
  if v_kind is distinct from 'BINDER'
     or v_default is distinct from (select l.storage_container_id from public.collection_layout l where l.id = p_layout_id) then
    raise exception 'NOT_SAME_LOCATION'
      using hint = 'escolha como local padrão o mesmo fichário físico das coleções deste fichário';
  end if;

  -- E17: depois das validações e do retorno ALREADY_ATTACHED (que não grava). Coleção do  -- P3B-S6
  -- evento = a convidada associada (D8).  -- P3B-S6
  perform public.binder_activity_begin(p_layout_id, 'COLLECTION_ATTACHED', 'FICHARIO', p_collection_id);  -- P3B-S6
  -- 6. Associação: nenhum bolso, reserva ou carta é tocado (D3).
  insert into public.collection_layout_guest (collection_id, layout_id)
  values (p_collection_id, p_layout_id);
  perform public.binder_activity_add_item('COLLECTION', 'ATTACHED', null, null, null, null, null, null,  -- P3B-S6
                                          jsonb_build_object('collection_id', p_collection_id));  -- P3B-S6
  perform public.binder_activity_end();  -- P3B-S6

  outcome := 'ATTACHED'; layout_id := p_layout_id; owner_collection_id := v_owner_coll;
  return next;
end;
$fn$;

revoke all on function public.attach_my_collection_to_binder(uuid, uuid) from public;
revoke all on function public.attach_my_collection_to_binder(uuid, uuid) from anon;
grant execute on function public.attach_my_collection_to_binder(uuid, uuid) to authenticated;

commit;

/*
Resultado esperado: attach_my_collection_to_binder(uuid, uuid) recriada com o mesmo contrato; nenhum evento gravado pela instalação.
Como validar (só leitura): LIVE_S6_90_postcheck_readonly.sql, bloco A.
*/
