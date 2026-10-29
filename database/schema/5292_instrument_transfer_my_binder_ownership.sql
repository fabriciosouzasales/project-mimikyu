/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5292 - P3-B S6 · Histórico do Fichário — instrumentação E20 (Fichário passou a outra coleção do mesmo dono)
              transfer_my_binder_ownership(uuid, uuid)
Versão......: 1.0 (2026-10-28, P3-B S6 — instrumentação E01, E16–E20)
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core (P3-B S6, autorização
              operacional do proprietário; harness dispensado sob H-A; ledger 20261028215622 `5292_instrument_transfer_my_binder_ownership`).
              Do `begin;` ao `commit;` idêntica ao arquivo de database/proposals/2026-10-25-
              p3b-binder-activity-history/ (só este bloco Status difere); enviada via
              apply_migration sem as linhas `begin;`/`commit;` externas — texto do ledger = corpo (md5).
              LIVE_S6_90 bloco A 6/6; E20 NÃO exercitado dinamicamente (sem caminho no frontend).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-28
Base........: 5254 (md5(prosrc) LIVE 4755a772e002c5a3994c6ad81ac53bb9, conferido em 2026-10-28;
              canônico: database/schema/5254_create_transfer_my_binder_ownership.sql).
Autoridade..: README da proposta §4.1, §4.2, §14.7, §20 (W3), §33 (S6).

Diff mínimo: o corpo é o da base LIVE, byte a byte, mais as linhas marcadas com
"-- P3B-S6". Removidas essas linhas e trocado o delimitador $fn$ → $$, o corpo volta a
ter o md5 acima (static_check_p3b_s6.py). Assinatura, retorno, SET, mensagens, códigos de
erro, ordem de travas e permissões inalterados (REVOKE/GRANT originais reaplicados).

Evento BINDER_OWNERSHIP_TRANSFERRED (atômico), coleção = destino. Só as três chamadas de §14.7:
begin depois das travas, 1 item BINDER/TRANSFERRED (origem e destino) depois da troca, end antes
do retorno. UNCHANGED, assinatura, erros, ordem de travas e a exceção controlada da 5136 inalterados.
================================================================
*/

begin;

do $pre$
begin
  if to_regprocedure('public.binder_activity_add_card_item(text, uuid, uuid, uuid)') is null
     or to_regprocedure('public.binder_activity_add_reservation_item(text, uuid)') is null
     or to_regprocedure('public.binder_activity_add_pocket_shift_items(uuid, uuid)') is null
     or to_regprocedure('public.binder_activity_begin(uuid, text, text, uuid, jsonb)') is null then
    raise exception 'PRECHECK 5292: dependências ausentes (5268/5271/5275/5279)';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('public.transfer_my_binder_ownership(uuid, uuid)')) is distinct from '4755a772e002c5a3994c6ad81ac53bb9' then
    raise exception 'PRECHECK 5292: função no LIVE diverge da base 5254 (md5)';
  end if;
end;
$pre$;

CREATE OR REPLACE FUNCTION public.transfer_my_binder_ownership(
  p_from_collection_id uuid,
  p_to_collection_id   uuid
)
returns table (
  outcome              text,     -- TRANSFERRED | UNCHANGED
  layout_id            uuid,
  reservations_pinned  integer   -- reservas implícitas da antiga proprietária tornadas explícitas
)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $fn$
#variable_conflict use_column
declare
  v_uid     uuid := auth.uid();
  v_layout  uuid;
  v_status  text;
  v_pinned  integer := 0;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_from_collection_id is null or p_to_collection_id is null
     or p_from_collection_id = p_to_collection_id then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  perform 1 from public.collection c where c.id = p_from_collection_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;
  perform 1 from public.collection c where c.id = p_to_collection_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- Repetição já concluída: destino é a proprietária e origem é convidada do mesmo layout.
  select l.id into v_layout from public.collection_layout l where l.collection_id = p_to_collection_id;
  if v_layout is not null
     and exists (select 1 from public.collection_layout_guest g
                 where g.layout_id = v_layout and g.collection_id = p_from_collection_id) then
    return query select 'UNCHANGED'::text, v_layout, 0;
    return;
  end if;

  -- Travas: origem → layout → destino.
  perform 1 from public.collection c where c.id = p_from_collection_id for update;
  select l.id into v_layout from public.collection_layout l
  where l.collection_id = p_from_collection_id
  for update;
  if v_layout is null then
    raise exception 'BINDER_NOT_OWNED' using errcode = 'P0002',
      hint = 'a coleção de origem não é a proprietária de um fichário';
  end if;
  select c.lifecycle_status into v_status from public.collection c
  where c.id = p_to_collection_id for update;
  if v_status <> 'ACTIVE' then
    raise exception 'COLLECTION_ARCHIVED' using errcode = '55000';
  end if;
  if exists (select 1 from public.collection_layout l where l.collection_id = p_to_collection_id) then
    raise exception 'COLLECTION_HAS_OWN_BINDER' using errcode = '55000';
  end if;
  if exists (select 1 from public.collection_layout_guest g
             where g.collection_id = p_to_collection_id and g.layout_id <> v_layout) then
    raise exception 'COLLECTION_IS_BINDER_GUEST' using errcode = '55000',
      hint = 'a coleção de destino usa outro fichário — desassocie antes';
  end if;

  -- E20 (§14.7): depois das validações e travas; UNCHANGED sai antes → nada gravado.  -- P3B-S6
  perform public.binder_activity_begin(v_layout, 'BINDER_OWNERSHIP_TRANSFERRED', 'FICHARIO', p_to_collection_id);  -- P3B-S6
  -- Reservas implícitas da proprietária ficam com a coleção de origem.
  update public.collection_layout_slot_expected_content e
     set collection_id = p_from_collection_id
   where e.collection_id is null
     and e.slot_id in (select s.id from public.collection_layout_slot s
                       join public.collection_layout_page p on p.id = s.page_id
                       where p.layout_id = v_layout);
  get diagnostics v_pinned = row_count;

  delete from public.collection_layout_guest g
   where g.collection_id = p_to_collection_id and g.layout_id = v_layout;

  perform set_config('mmkyu.binder_owner_transfer', v_layout::text, true);
  update public.collection_layout l set collection_id = p_to_collection_id where l.id = v_layout;
  perform set_config('mmkyu.binder_owner_transfer', '', true);

  insert into public.collection_layout_guest (collection_id, layout_id)
  values (p_from_collection_id, v_layout);
  perform public.binder_activity_add_item('BINDER', 'TRANSFERRED', null, null, null, null, null, null,  -- P3B-S6
                                          jsonb_build_object('from_collection_id', p_from_collection_id,  -- P3B-S6
                                                             'to_collection_id', p_to_collection_id));  -- P3B-S6
  perform public.binder_activity_end();  -- P3B-S6

  return query select 'TRANSFERRED'::text, v_layout, v_pinned;
end;
$fn$;

revoke all on function public.transfer_my_binder_ownership(uuid, uuid) from public, anon;
grant execute on function public.transfer_my_binder_ownership(uuid, uuid) to authenticated;

commit;

/*
Resultado esperado: transfer_my_binder_ownership(uuid, uuid) recriada com o mesmo contrato; nenhum evento gravado pela instalação.
Como validar (só leitura): LIVE_S6_90_postcheck_readonly.sql, bloco A.
*/
