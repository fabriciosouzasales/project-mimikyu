/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5272 - P3-B S2 · Histórico do Fichário — instrumentação E02 (Carta colocada)
              place_my_physical_card_in_slot(uuid, uuid, uuid)
Versão......: 1.0 (2026-10-27, P3-B S2 — instrumentação E02–E05)
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core em 2026-10-27
              (P3-B S2, autorização expressa de Fabrício; harness dispensado sob H-A
              só para a S2; ledger 20261027030713 `5272_instrument_place_my_physical_card_in_slot`). Do `begin;` ao `commit;`
              idêntica ao arquivo de database/proposals/2026-10-25-p3b-binder-
              activity-history/ (só este bloco Status difere); enviada via
              apply_migration sem as linhas `begin;`/`commit;` externas — o texto
              gravado no ledger é igual ao corpo do arquivo da proposta (md5).
              LIVE_S2_90 bloco A 7/7, bloco B B.1–B.7 PASS. ADD pela interface não
              comprovado; REPLACE não testado; desempenho não medido. README §29.9–§29.11.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-27
Base........: 5250 (LIVE = canônico: md5(prosrc) caecf1bd88d9955dcfe409fb85a3effd, conferido em 2026-10-27).
Autoridade..: README da proposta §4.1 (E02 (Carta colocada)), §7.2, §20 (W3), §29 (S2).

Diff mínimo: o corpo é o da 5250, byte a byte, mais as linhas marcadas com
"-- P3B-S2" (só begin/add_item/end e o necessário para elas). Removidas essas linhas e
trocado o delimitador $fn$ → $$, o corpo volta a ter o md5 acima
(static_check_p3b_s2.py, S2.2). Assinatura, retorno, SET, mensagens, códigos de erro,
ordem de travas e permissões inalterados (CREATE OR REPLACE preserva o ACL; REVOKE/GRANT
originais reaplicados de forma idempotente).

Evento CARD_PLACED (origem FICHARIO, coleção = a coleção que abriu o fichário):
  · ADD     → 1 item CARD/PLACED (destino = bolso);
  · REPLACE → CARD/REMOVED do exemplar anterior (origem = bolso, antes do DELETE) +
              CARD/PLACED do novo (destino = bolso, depois do INSERT);
  · UNCHANGED → sai antes do begin: nenhum evento (C-206, I-8).
"Desfazer remoção" do frontend chama esta mesma função: gera um CARD_PLACED novo.

Precheck: recusa se a função LIVE divergir da base (md5) ou se 5268/5271 faltarem.
================================================================
*/

begin;

do $pre$
begin
  if to_regprocedure('public.binder_activity_add_card_item(text, uuid, uuid, uuid)') is null then
    raise exception 'PRECHECK 5272: aplique 5268 e 5271 antes';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('public.place_my_physical_card_in_slot(uuid, uuid, uuid)')) is distinct from 'caecf1bd88d9955dcfe409fb85a3effd' then
    raise exception 'PRECHECK 5272: place_my_physical_card_in_slot no LIVE diverge da base 5250 (md5)';
  end if;
end;
$pre$;

create or replace function public.place_my_physical_card_in_slot(
  p_collection_id    uuid,
  p_slot_id          uuid,
  p_physical_card_id uuid
)
returns table (
  assignment_id             uuid,
  slot_id                   uuid,
  physical_card_id          uuid,
  operation                 text,   -- ADD | REPLACE | UNCHANGED
  replaced_physical_card_id uuid
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
  v_status     text;
  v_layout     uuid;
  v_container  uuid;
  v_locked     boolean;
  v_card_cont  uuid;
  v_here       uuid;   -- posição atual do exemplar (qualquer bolso)
  v_here_slot  uuid;
  v_old_asg    uuid;
  v_old_card   uuid;
  v_new_asg    uuid;
  v_op         text;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null or p_slot_id is null or p_physical_card_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  -- 1. Coleção aberta: fronteira de dono antes de qualquer outra tabela
  -- (sem trava aqui: a ordem canônica é proprietária → layout → convidada).
  perform 1 from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  select l.id into v_layout from public.collection_layout l where l.collection_id = p_collection_id;
  if v_layout is null then
    select g.layout_id into v_layout from public.collection_layout_guest g where g.collection_id = p_collection_id;
  end if;
  if v_layout is null then
    raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- 2. Proprietária → layout (5122: dono e ACTIVE).
  begin
    perform public.assert_collection_layout_mutable(v_layout);
  exception
    when others then
      if sqlerrm like 'collection is ARCHIVED%' then
        raise exception 'COLLECTION_ARCHIVED' using errcode = '55000';
      end if;
      raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
  end;

  -- Coleção aberta (se convidada) travada DEPOIS da proprietária/layout, como
  -- detach_my_collection_from_binder (5229) — sem ciclo de travas.
  select c.lifecycle_status into v_status
  from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_uid
  for share;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_status <> 'ACTIVE' then
    raise exception 'COLLECTION_ARCHIVED' using errcode = '55000';
  end if;
  -- Revalida a participação depois das travas (desassociação concorrente).
  if not exists (select 1 from public.collection_layout l where l.id = v_layout and l.collection_id = p_collection_id)
     and not exists (select 1 from public.collection_layout_guest g where g.layout_id = v_layout and g.collection_id = p_collection_id) then
    raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
  end if;

  select l.storage_container_id into v_container from public.collection_layout l where l.id = v_layout;

  -- 3. Bolso deste fichário.
  select s.locked into v_locked
  from public.collection_layout_slot s
  join public.collection_layout_page p on p.id = s.page_id
  where s.id = p_slot_id and p.layout_id = v_layout
  for update of s;
  if not found then
    raise exception 'SLOT_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_locked then
    raise exception 'SLOT_LOCKED' using errcode = '55000';
  end if;

  -- 4. Exemplar do usuário (inexistente e alheio colapsam).
  select pc.storage_container_id into v_card_cont
  from public.physical_card pc
  join public.inventory i on i.id = pc.inventory_id
  where pc.id = p_physical_card_id and i.owner_user_id = v_uid
  for update of pc;
  if not found then
    raise exception 'PHYSICAL_CARD_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_card_cont is distinct from v_container then
    raise exception 'CARD_NOT_IN_BINDER_LOCATION' using errcode = '55000';
  end if;

  -- 5. Já posicionado?
  select a.id, a.slot_id into v_here, v_here_slot
  from public.collection_layout_slot_assignment a
  where a.physical_card_id = p_physical_card_id
  for update;
  if v_here is not null then
    if v_here_slot = p_slot_id then
      return query select v_here, p_slot_id, p_physical_card_id, 'UNCHANGED'::text, null::uuid;
      return;
    end if;
    raise exception 'CARD_ALREADY_PLACED' using errcode = '23505',
      hint = 'o exemplar já está em outro bolso — mova-o em vez de posicioná-lo de novo';
  end if;

  -- E02: abre o evento depois das validações, travas e do retorno UNCHANGED (I-1).  -- P3B-S2
  perform public.binder_activity_begin(v_layout, 'CARD_PLACED', 'FICHARIO', p_collection_id);  -- P3B-S2
  -- P3B-S2
  -- 6. REPLACE / ADD.
  select a.id, a.physical_card_id into v_old_asg, v_old_card
  from public.collection_layout_slot_assignment a
  where a.slot_id = p_slot_id
  for update;
  if v_old_asg is not null then
    -- REPLACE: exemplar anterior sai do bolso — item de origem antes de apagar (I-10).  -- P3B-S2
    perform public.binder_activity_add_card_item('REMOVED', v_old_card, p_slot_id, null);  -- P3B-S2
    delete from public.collection_layout_slot_assignment where id = v_old_asg;
    v_op := 'REPLACE';
  else
    v_op := 'ADD';
  end if;

  begin
    insert into public.collection_layout_slot_assignment as a (slot_id, physical_card_id)
    values (p_slot_id, p_physical_card_id)
    returning a.id into v_new_asg;
  exception
    when unique_violation then
      raise exception 'CARD_ALREADY_PLACED' using errcode = '23505';
  end;

  perform public.binder_activity_add_card_item('PLACED', p_physical_card_id, null, p_slot_id);  -- P3B-S2
  return query select v_new_asg, p_slot_id, p_physical_card_id, v_op, v_old_card;
  perform public.binder_activity_end();  -- P3B-S2
end;
$fn$;

revoke all on function public.place_my_physical_card_in_slot(uuid, uuid, uuid) from public, anon;
grant execute on function public.place_my_physical_card_in_slot(uuid, uuid, uuid) to authenticated;

notify pgrst, 'reload schema';

commit;
