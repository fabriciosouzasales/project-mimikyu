/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5296 - P3-B S6 · Histórico do Fichário — instrumentação E16 (Novidades do Catálogo incorporadas)
              apply_my_binder_catalog_reconciliation(uuid, text[], text, boolean, boolean)
Versão......: 1.0 (2026-10-28, P3-B S6 — instrumentação E01, E16–E20)
Status......: PROPOSTA — NÃO EXECUTADA. Exige autorização própria para o LIVE.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-28
Base........: 5266 (md5(prosrc) LIVE aa58b231484cc1ed533c50c51c38f2cc, conferido em 2026-10-28;
              canônico: database/schema/5266_create_binder_catalog_reconciliation_apply.sql).
Autoridade..: README da proposta §4.1, §4.2, §14.7, §20 (W3), §33 (S6).

Diff mínimo: o corpo é o da base LIVE, byte a byte, mais as linhas marcadas com
"-- P3B-S6". Removidas essas linhas e trocado o delimitador $fn$ → $$, o corpo volta a
ter o md5 acima (static_check_p3b_s6.py). Assinatura, retorno, SET, mensagens, códigos de
erro, ordem de travas e permissões inalterados (REVOKE/GRANT originais reaplicados).

Evento CATALOG_NOVELTIES_INCORPORATED (lote), origem CATALOGO, coleção = a reconciliada:
  · SHIFTED por objeto deslocado (via 5279), logo após cada movimento da cadeia — deslocamentos
    repetidos do mesmo objeto em passos diferentes são esperados (I-7, exceção da E16; folga W1);
  · PAGE_ADDED da página embutida (R5, pela própria add_layout_page);
  · RESERVATION/RESERVED por reserva nova (destino, via 5275, depois do INSERT);
  · RESERVATION/INCORPORATED por reserva genérica convertida (destino, carta e acabamento).
  Fecha R-S4-1.
================================================================
*/

begin;

do $pre$
begin
  if to_regprocedure('public.binder_activity_add_card_item(text, uuid, uuid, uuid)') is null
     or to_regprocedure('public.binder_activity_add_reservation_item(text, uuid)') is null
     or to_regprocedure('public.binder_activity_add_pocket_shift_items(uuid, uuid)') is null
     or to_regprocedure('public.binder_activity_begin(uuid, text, text, uuid, jsonb)') is null then
    raise exception 'PRECHECK 5296: dependências ausentes (5268/5271/5275/5279)';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('public.apply_my_binder_catalog_reconciliation(uuid, text[], text, boolean, boolean)')) is distinct from 'aa58b231484cc1ed533c50c51c38f2cc' then
    raise exception 'PRECHECK 5296: função no LIVE diverge da base 5266 (md5)';
  end if;
end;
$pre$;

CREATE OR REPLACE FUNCTION public.apply_my_binder_catalog_reconciliation(
  p_collection_id      uuid,
  p_keys               text[],
  p_plan_token         text,
  p_confirm_cross_page boolean default false,
  p_confirm_add_page   boolean default false
)
returns table (
  outcome              text,      -- APPLIED | ALREADY_APPLIED | NOTHING_TO_DO
  items_applied        integer,
  reservations_created integer,
  reservations_upgraded integer,
  pockets_moved        integer,
  rows_moved           integer,
  pages_added          integer,
  added_page_numbers   integer[]
)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $fn$
#variable_conflict use_column
declare
  v_uid      uuid := auth.uid();
  v_layout   uuid;
  x          record;
  st         record;
  h          record;
  v_pending  text[];
  v_invalid  integer;
  v_chain    uuid[];
  v_target   uuid;
  v_page_no  integer;
  v_expect   integer;
  v_rows     integer := 0;
  v_pm       integer := 0;
  v_res      integer := 0;
  v_upg      integer := 0;
  v_added    integer[] := '{}';
  v_seen_hdr boolean := false;
  v_hint     text;
  k          integer;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null or p_plan_token is null or p_plan_token !~ '^rc1:[0-9a-f]{64}$'
     or (p_keys is not null and (cardinality(p_keys) = 0 or array_position(p_keys, null) is not null)) then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  v_layout := public.binder_layout_lock_for_collection(p_collection_id);
  select * into x from public.binder_catalog_assert_eligible(p_collection_id);
  if x.layout_id is distinct from v_layout or x.owner_user_id is distinct from v_uid then
    raise exception 'RECONCILE_INCONSISTENT' using errcode = 'P0001';
  end if;

  -- Idempotência ---------------------------------------------------------------------------------
  if p_keys is null then
    select array_agg(nv.item_key order by nv.pos_ord) into v_pending
    from public.binder_catalog_novelties(p_collection_id) nv where nv.is_novelty;
    if v_pending is null then
      outcome := 'NOTHING_TO_DO'; items_applied := 0; reservations_created := 0; reservations_upgraded := 0; pockets_moved := 0;
      rows_moved := 0; pages_added := 0; added_page_numbers := '{}';
      return next; return;
    end if;
  else
    select count(*) filter (where nv.item_key is null)::integer,
           array_agg(d.k order by nv.pos_ord) filter (where nv.is_novelty)
      into v_invalid, v_pending
    from (select distinct u.k from unnest(p_keys) u(k)) d
    left join public.binder_catalog_novelties(p_collection_id) nv on nv.item_key = d.k;
    if v_invalid > 0 then
      raise exception 'SELECTION_INVALID' using errcode = '22023',
        hint = 'há itens que não são novidades desta coleção';
    end if;
    if v_pending is null then
      outcome := 'ALREADY_APPLIED'; items_applied := 0; reservations_created := 0; reservations_upgraded := 0; pockets_moved := 0;
      rows_moved := 0; pages_added := 0; added_page_numbers := '{}';
      return next; return;
    end if;
  end if;

  -- E16: depois dos retornos NOTHING_TO_DO/ALREADY_APPLIED (que não gravam). Página nova  -- P3B-S6
  -- (add_layout_page, já instrumentada) entra como item PAGE_ADDED deste evento (R5) —  -- P3B-S6
  -- encerra a exposição interina R-S4-1. Coleção do evento = a reconciliada.  -- P3B-S6
  perform public.binder_activity_begin(v_layout, 'CATALOG_NOVELTIES_INCORPORATED', 'CATALOGO', p_collection_id);  -- P3B-S6
  -- P3B-S6
  -- Plano sob a trava + execução na ordem simulada -----------------------------------------------
  for st in
    select * from public.binder_catalog_plan(p_collection_id, v_pending) p
    order by (p.row_kind = 'HEADER') desc, p.step_no
  loop
    if st.row_kind = 'HEADER' then
      v_seen_hdr := true;
      h := st;
      -- W2: limite antes do token (no ITEM_LIMIT o plano não gera token)
      if st.outcome = 'OVER_LIMIT' then
        raise exception 'RECONCILE_OVER_LIMIT' using errcode = '54000',
          hint = format('%s (limites: %s itens, %s linhas movidas)', st.reason, st.item_limit, st.row_limit);
      end if;
      if st.plan_token is distinct from p_plan_token then
        raise exception 'RECONCILE_PLAN_CHANGED' using errcode = '40001',
          hint = 'o fichário ou o Catálogo mudou desde a prévia — veja a prévia de novo';
      end if;
      if st.outcome = 'BLOCKED' then
        select format('barreira %s na página %s, linha %s, coluna %s', p.barrier_kind, p.barrier_page, p.barrier_row, p.barrier_column)
          into v_hint
        from public.binder_catalog_plan(p_collection_id, v_pending) p
        where p.kind = 'BLOCKED';
        raise exception 'RECONCILE_BLOCKED' using errcode = '55000', hint = coalesce(v_hint, 'barreira');
      elsif st.outcome = 'NEEDS_REVIEW' then
        raise exception 'RECONCILE_NEEDS_REVIEW' using errcode = '55000',
          hint = 'há novidade com carta fora da ordem ou reserva genérica ambígua — desmarque-a e resolva separadamente';
      elsif st.outcome = 'NO_ANCHOR' then
        raise exception 'RECONCILE_NO_ANCHOR' using errcode = '55000',
          hint = 'há novidade sem posição vizinha no fichário — desmarque-a';
      elsif st.outcome is distinct from 'READY' then
        raise exception 'RECONCILE_INCONSISTENT' using errcode = 'P0001';
      end if;
      if st.requires_cross_page and not coalesce(p_confirm_cross_page, false) then
        raise exception 'RECONCILE_CONFIRMATION_REQUIRED' using errcode = '55000', hint = 'CROSS_PAGE';
      end if;
      if st.requires_add_page and not coalesce(p_confirm_add_page, false) then
        raise exception 'RECONCILE_CONFIRMATION_REQUIRED' using errcode = '55000', hint = 'ADD_PAGE';
      end if;
      continue;
    end if;

    if not v_seen_hdr or st.kind not in ('IN_PLACE', 'RESERVE_PLACED', 'SHIFT', 'UPGRADE_RESERVATION') then
      raise exception 'RECONCILE_INCONSISTENT' using errcode = 'P0001';
    end if;

    -- W3: reserva genérica "carta:*" desta coleção convertida no próprio bolso
    if st.kind = 'UPGRADE_RESERVATION' then
      select s.id into v_target
      from public.collection_layout_slot s
      join public.collection_layout_page p on p.id = s.page_id
      where p.layout_id = v_layout and p.page_number = st.target_page
        and s.row_index = st.target_row and s.column_index = st.target_column
      for update of s;
      update public.collection_layout_slot_expected_content e
         set expected_variant_type_id = st.variant_type_id
       where e.slot_id = v_target
         and e.card_id = st.card_id
         and e.card_variant_id is null
         and e.expected_variant_type_id is null
         and coalesce(e.collection_id, x.owner_collection_id) = p_collection_id;
      get diagnostics k = row_count;
      if k <> 1 then
        raise exception 'RECONCILE_INCONSISTENT' using errcode = 'P0001';
      end if;
      v_upg := v_upg + 1;
      perform public.binder_activity_add_item('RESERVATION', 'INCORPORATED', st.card_id, st.variant_type_id,  -- P3B-S6
                                              null, v_target, null, null, jsonb_build_object('upgrade', true));  -- P3B-S6
      continue;
    end if;

    -- Página nova prevista para este passo
    if st.adds_page then
      v_expect := case when st.kind = 'SHIFT' then st.end_page else st.target_page end;
      select ap.page_number into v_page_no from public.add_layout_page(v_layout) ap;
      if v_page_no is distinct from v_expect then
        raise exception 'RECONCILE_INCONSISTENT' using errcode = 'P0001';
      end if;
      v_added := v_added || v_page_no;
    end if;

    if st.kind = 'SHIFT' then
      select array_agg(s.id order by p.page_number, s.row_index, s.column_index) into v_chain
      from public.collection_layout_slot s
      join public.collection_layout_page p on p.id = s.page_id
      where p.layout_id = v_layout
        and (p.page_number, s.row_index, s.column_index) >= (st.target_page, st.target_row, st.target_column)
        and (p.page_number, s.row_index, s.column_index) <= (st.end_page, st.end_row, st.end_column);
      if v_chain is null or cardinality(v_chain) <> st.pockets_moved + 1 then
        raise exception 'RECONCILE_INCONSISTENT' using errcode = 'P0001';
      end if;
      perform 1 from public.collection_layout_slot s where s.id = any (v_chain) order by s.id for update;
      if exists (select 1 from public.collection_layout_slot s where s.id = any (v_chain) and s.locked) then
        raise exception 'RECONCILE_INCONSISTENT' using errcode = 'P0001';
      end if;
      for k in reverse cardinality(v_chain) - 1 .. 1 loop
        v_rows := v_rows + public.binder_gap_move_pocket(v_chain[k], v_chain[k + 1]);
        perform public.binder_activity_add_pocket_shift_items(v_chain[k], v_chain[k + 1]);  -- P3B-S6
      end loop;
      v_pm := v_pm + st.pockets_moved;
      v_target := v_chain[1];
    else
      select s.id into v_target
      from public.collection_layout_slot s
      join public.collection_layout_page p on p.id = s.page_id
      where p.layout_id = v_layout and p.page_number = st.target_page
        and s.row_index = st.target_row and s.column_index = st.target_column
      for update of s;
      if v_target is null then
        raise exception 'RECONCILE_INCONSISTENT' using errcode = 'P0001';
      end if;
    end if;

    -- Pré-condição do bolso de destino
    if exists (select 1 from public.collection_layout_slot_expected_content e where e.slot_id = v_target)
       or (st.kind <> 'RESERVE_PLACED'
           and (exists (select 1 from public.collection_layout_slot_assignment a0 where a0.slot_id = v_target)
                or exists (select 1 from public.collection_layout_slot_image im where im.slot_id = v_target)
                or exists (select 1 from public.collection_layout_slot s where s.id = v_target and s.locked)))
       or (st.kind = 'RESERVE_PLACED'
           and not exists (select 1 from public.collection_layout_slot_assignment a0 where a0.slot_id = v_target)) then
      raise exception 'RECONCILE_INCONSISTENT' using errcode = 'P0001';
    end if;

    insert into public.collection_layout_slot_expected_content
      (slot_id, card_id, card_variant_id, expected_variant_type_id, collection_id)
    values
      (v_target, st.card_id, null, st.variant_type_id,
       case when p_collection_id = x.owner_collection_id then null else p_collection_id end);
    v_res := v_res + 1;
    perform public.binder_activity_add_reservation_item('RESERVED', v_target);  -- P3B-S6
  end loop;

  -- Pós-condições ----------------------------------------------------------------------------------
  if not v_seen_hdr or v_rows <> h.total_rows_moved or v_res + v_upg <> cardinality(v_pending)
     or exists (select 1
                from unnest(v_pending) u(k)
                left join public.binder_catalog_novelties(p_collection_id) nv on nv.item_key = u.k
                where nv.is_reserved is distinct from true) then
    raise exception 'RECONCILE_INCONSISTENT' using errcode = 'P0001';
  end if;

  -- W5: registro persistente das incorporações (5263), na mesma transação ----------------------------
  insert into public.collection_layout_catalog_incorporation (layout_id, collection_id, item_key)
  select v_layout, p_collection_id, u.k
  from unnest(v_pending) u(k)
  on conflict (layout_id, collection_id, item_key) do nothing;
  get diagnostics k = row_count;
  if k <> cardinality(v_pending) then
    raise exception 'RECONCILE_INCONSISTENT' using errcode = 'P0001';
  end if;

  perform public.binder_activity_end();  -- P3B-S6
  outcome := 'APPLIED';
  items_applied := cardinality(v_pending);
  reservations_created := v_res;
  reservations_upgraded := v_upg;
  pockets_moved := v_pm;
  rows_moved := v_rows;
  pages_added := cardinality(v_added);
  added_page_numbers := v_added;
  return next;
end;
$fn$;

revoke all on function public.apply_my_binder_catalog_reconciliation(uuid, text[], text, boolean, boolean) from public, anon;
grant execute on function public.apply_my_binder_catalog_reconciliation(uuid, text[], text, boolean, boolean) to authenticated;

commit;

/*
Resultado esperado: apply_my_binder_catalog_reconciliation(uuid, text[], text, boolean, boolean) recriada com o mesmo contrato; nenhum evento gravado pela instalação.
Como validar (só leitura): LIVE_S6_90_postcheck_readonly.sql, bloco A.
*/
