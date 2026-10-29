/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5283 - P3-B S4 · Histórico do Fichário — instrumentação E11 (Espaço aberto)
              insert_my_binder_gap(uuid, uuid, text, boolean, boolean)
Versão......: 1.0 (2026-10-27, P3-B S4 — instrumentação E11–E15)
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core (P3-B S4, autorização
              expressa de Fabrício; harness dispensado sob H-A; ledger 20261027232052 `5283_instrument_insert_my_binder_gap`).
              Do `begin;` ao `commit;` idêntica ao arquivo de database/proposals/2026-10-25-
              p3b-binder-activity-history/ (só este bloco Status difere); enviada via
              apply_migration sem as linhas `begin;`/`commit;` externas — texto do ledger = corpo (md5).
              LIVE_S4_90 bloco A 7/7; bloco B 9/9 + amostra.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-27
Base........: 5243 (corpo do LIVE; o arquivo canônico difere só por comentários) (md5(prosrc) LIVE a99a90c572d2bd35424b4c725fff0150, conferido em 2026-10-27).
Autoridade..: README da proposta §4.1, §5.2, §7.2 (R5), §20 (W3), §31 (S4).

Diff mínimo: o corpo é o da base LIVE, byte a byte, mais as linhas marcadas com
"-- P3B-S4". Removidas essas linhas e trocado o delimitador $fn$ → $$, o corpo volta a
ter o md5 acima (static_check_p3b_s4.py). Assinatura, retorno, SET, mensagens, códigos de
erro, ordem de travas e permissões inalterados (REVOKE/GRANT originais reaplicados).

Evento GAP_OPENED (lote atômico, até 500 linhas — teto da 5243):
  · página nova embutida (NEEDS_PAGE) → item PAGE/PAGE_ADDED (via add_layout_page, R5);
  · por bolso deslocado: CARD/SHIFTED, RESERVATION/SHIFTED e POCKET/SHIFTED (imagem), cada um
    com origem → destino, lidos depois de todos os deslocamentos (5279);
  · ALREADY_FREE sai antes do begin: nenhum evento.
================================================================
*/

begin;

do $pre$
begin
  if to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)') is null then
    raise exception 'PRECHECK 5283: dependência ausente (binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb))';
  end if;
  if to_regprocedure('public.binder_activity_add_pocket_shift_items(uuid, uuid)') is null then
    raise exception 'PRECHECK 5283: dependência ausente (binder_activity_add_pocket_shift_items(uuid, uuid))';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('public.insert_my_binder_gap(uuid, uuid, text, boolean, boolean)')) is distinct from 'a99a90c572d2bd35424b4c725fff0150' then
    raise exception 'PRECHECK 5283: função no LIVE diverge da base 5243 (md5)';
  end if;
end;
$pre$;

CREATE OR REPLACE FUNCTION public.insert_my_binder_gap(
  p_collection_id      uuid,
  p_slot_id            uuid,
  p_plan_token         text,
  p_confirm_cross_page boolean default false,
  p_confirm_add_page   boolean default false
)
returns table (
  outcome       text,      -- INSERTED | ALREADY_FREE
  gap_slot_id   uuid,
  end_slot_id   uuid,
  added_page_id uuid,
  moved_pockets integer,
  rows_moved    integer,
  pages         integer[],
  undo_token    text
)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $fn$
#variable_conflict use_column
declare
  v_layout uuid;
  e        record;
  v_chain  uuid[];
  v_dest   uuid[];
  v_target uuid;
  v_added  uuid;
  v_rows   integer := 0;
  i        integer;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_slot_id is null or p_plan_token is null or p_plan_token !~ '^g1:[0-9a-f]{64}$' then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  v_layout := public.binder_layout_lock_for_collection(p_collection_id);
  select * into e from public.binder_gap_evaluate(v_layout, p_slot_id);

  if e.outcome = 'NOT_FOUND' then
    raise exception 'SLOT_NOT_FOUND' using errcode = 'P0002';
  end if;
  if e.outcome = 'ALREADY_FREE' then
    outcome := 'ALREADY_FREE'; gap_slot_id := p_slot_id; moved_pockets := 0; rows_moved := 0;
    return next; return;
  end if;
  if e.plan_token is distinct from p_plan_token then
    raise exception 'GAP_PLAN_CHANGED' using errcode = '40001',
      hint = 'o fichário mudou desde a prévia — veja a prévia de novo';
  end if;
  if e.outcome in ('AT_BARRIER', 'BLOCKED') then
    raise exception 'GAP_BLOCKED' using errcode = '55000',
      hint = format('barreira %s na página %s, linha %s, coluna %s', e.barrier_kind, e.barrier_page, e.barrier_row, e.barrier_column);
  end if;
  if e.outcome = 'OVER_LIMIT' then
    raise exception 'GAP_OVER_LIMIT' using errcode = '54000',
      hint = format('%s itens excedem o limite de %s por operação', e.rows_moved, e.row_limit);
  end if;
  if e.outcome = 'CROSS_PAGE' and not coalesce(p_confirm_cross_page, false) then
    raise exception 'GAP_CONFIRMATION_REQUIRED' using errcode = '55000', hint = 'CROSS_PAGE';
  end if;
  if e.outcome = 'NEEDS_PAGE' and not coalesce(p_confirm_add_page, false) then
    raise exception 'GAP_CONFIRMATION_REQUIRED' using errcode = '55000', hint = 'ADD_PAGE';
  end if;

  select array_agg(c.slot_id order by c.ord) into v_chain
  from public.binder_gap_chain(v_layout, p_slot_id) c
  where c.ord < (select min(c0.ord) from public.binder_gap_chain(v_layout, p_slot_id) c0) + e.moved_pockets;

  -- E11: depois das validações e do retorno ALREADY_FREE (que não grava). Página embutida  -- P3B-S4
  -- (add_layout_page) entra como item PAGE_ADDED deste evento (R5).  -- P3B-S4
  perform public.binder_activity_begin(v_layout, 'GAP_OPENED', 'FICHARIO');  -- P3B-S4
  if e.outcome = 'NEEDS_PAGE' then
    select ap.id into v_added from public.add_layout_page(v_layout) ap;
    select s.id into v_target
    from public.collection_layout_slot s
    where s.page_id = v_added and s.row_index = 1 and s.column_index = 1;
  else
    v_target := e.target_slot_id;
  end if;
  if v_target is null or cardinality(v_chain) <> e.moved_pockets then
    raise exception 'GAP_INCONSISTENT';
  end if;

  v_dest := v_chain[2:] || v_target;

  perform 1 from public.collection_layout_slot s
  where s.id = any (v_chain || v_target)
  order by s.id
  for update;

  for i in reverse cardinality(v_chain)..1 loop
    v_rows := v_rows + public.binder_gap_move_pocket(v_chain[i], v_dest[i]);
  end loop;

  if v_rows <> e.rows_moved
     or exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = p_slot_id)
     or exists (select 1 from public.collection_layout_slot_expected_content x where x.slot_id = p_slot_id)
     or exists (select 1 from public.collection_layout_slot_image im where im.slot_id = p_slot_id) then
    raise exception 'GAP_INCONSISTENT';
  end if;

  -- Conteúdo deslocado: o que está agora em v_dest[i] veio de v_chain[i].  -- P3B-S4
  for i in 1..cardinality(v_chain) loop  -- P3B-S4
    perform public.binder_activity_add_pocket_shift_items(v_chain[i], v_dest[i]);  -- P3B-S4
  end loop;  -- P3B-S4
  outcome       := 'INSERTED';
  gap_slot_id   := p_slot_id;
  end_slot_id   := v_target;
  added_page_id := v_added;
  moved_pockets := e.moved_pockets;
  rows_moved    := v_rows;
  pages         := e.pages;
  undo_token    := public.binder_gap_undo_token(v_layout, p_slot_id, v_target, v_added);
  return next;
  perform public.binder_activity_end();  -- P3B-S4
end;
$fn$;

revoke all on function public.insert_my_binder_gap(uuid, uuid, text, boolean, boolean) from public, anon;
grant execute on function public.insert_my_binder_gap(uuid, uuid, text, boolean, boolean) to authenticated;

commit;
