/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5295 - P3-B S6 · Histórico do Fichário — instrumentação E01 (Fichário montado)
              create_my_collection_binder(uuid, integer, integer, text, text)
Versão......: 1.0 (2026-10-28, P3-B S6 — instrumentação E01, E16–E20)
Status......: PROPOSTA — NÃO EXECUTADA. Exige autorização própria para o LIVE.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-28
Base........: 5224 (md5(prosrc) LIVE 5ba7941f175137f322179eff72f7a37c, conferido em 2026-10-28;
              canônico: database/schema/5224_create_collection_binder_plan_preview_create.sql).
Autoridade..: README da proposta §4.1, §4.2, §14.7, §20 (W3), §33 (S6).

Diff mínimo: o corpo é o da base LIVE, byte a byte, mais as linhas marcadas com
"-- P3B-S6". Removidas essas linhas e trocado o delimitador $fn$ → $$, o corpo volta a
ter o md5 acima (static_check_p3b_s6.py). Assinatura, retorno, SET, mensagens, códigos de
erro, ordem de travas e permissões inalterados (REVOKE/GRANT originais reaplicados).

Evento BINDER_ASSEMBLED (lote), coleção = a montada; resumo = grade, política de extras e
extras fora do fichário. Itens (destino), depois de gravar tudo: PAGE/PAGE_ADDED por página,
CARD/PLACED por carta posicionada, RESERVATION/RESERVED por reserva. Fichário sempre tem ≥ 1
página → o evento sempre existe.
================================================================
*/

begin;

do $pre$
begin
  if to_regprocedure('public.binder_activity_add_card_item(text, uuid, uuid, uuid)') is null
     or to_regprocedure('public.binder_activity_add_reservation_item(text, uuid)') is null
     or to_regprocedure('public.binder_activity_add_pocket_shift_items(uuid, uuid)') is null
     or to_regprocedure('public.binder_activity_begin(uuid, text, text, uuid, jsonb)') is null then
    raise exception 'PRECHECK 5295: dependências ausentes (5268/5271/5275/5279)';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('public.create_my_collection_binder(uuid, integer, integer, text, text)')) is distinct from '5ba7941f175137f322179eff72f7a37c' then
    raise exception 'PRECHECK 5295: função no LIVE diverge da base 5224 (md5)';
  end if;
end;
$pre$;

CREATE OR REPLACE FUNCTION public.create_my_collection_binder(
  p_collection_id uuid,
  p_grid_columns  integer,
  p_grid_rows     integer,
  p_extra_policy  text,
  p_plan_token    text
)
returns table (
  outcome              text,     -- CREATED | ALREADY_EXISTS
  layout_id            uuid,
  grid_columns         integer,
  grid_rows            integer,
  pages_created        integer,
  slots_created        integer,
  reservations_created integer,
  assignments_created  integer,
  extras_unplaced      integer
)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $fn$
#variable_conflict use_column
declare
  c_max_allocations constant integer := 10000;   -- PROVISÓRIO: mesmo valor da prévia
  c_max_slots       constant integer := 20000;   -- PROVISÓRIO: mesmo valor da prévia
  v_uid       uuid := auth.uid();
  v_policy_x  text := upper(btrim(coalesce(p_extra_policy, '')));
  v_status    text;
  v_default   uuid;
  v_kind_sc   text;
  v_layout    uuid;
  v_ex_cols   integer;
  v_ex_rows   integer;
  v_allocs    integer;
  v_cap       integer;
  v_token     text;
  v_pages     integer;
  v_unplaced  integer;
  a_pg        integer[];
  a_rw        integer[];
  a_cl        integer[];
  a_ec        uuid[];
  a_ev        uuid[];
  a_al        uuid[];
  v_exp_resv  integer;
  v_exp_asg   integer;
  v_n_pages   integer;
  v_n_slots   integer;
  v_n_resv    integer;
  v_n_asg     integer;
  v_act       record;  -- P3B-S6
begin
  -- 0. Forma ------------------------------------------------------------------------
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null or p_grid_columns is null or p_grid_rows is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  if (p_grid_columns, p_grid_rows) not in ((2,2), (3,3), (3,4), (4,3), (4,4), (4,5), (5,4)) then
    raise exception 'INVALID_GRID' using errcode = '22023';
  end if;
  if v_policy_x not in ('PRINCIPAL_ONLY', 'APPEND_PAGES') then
    raise exception 'INVALID_EXTRA_POLICY' using errcode = '22023';
  end if;
  if p_plan_token is null or p_plan_token !~ '^v1:[0-9a-f]{64}$' then
    raise exception 'INVALID_PLAN_TOKEN' using errcode = '22023';
  end if;
  v_cap := p_grid_columns * p_grid_rows;

  -- 1. Coleção: trava comum a toda escrita de usuário que altera o plano --------
  select c.lifecycle_status, c.default_storage_container_id
    into v_status, v_default
  from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_uid
  for update;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- 2. Idempotência: fichário existente → ALREADY_EXISTS, nada muda ------------
  select l.id, l.grid_columns, l.grid_rows into v_layout, v_ex_cols, v_ex_rows
  from public.collection_layout l
  where l.collection_id = p_collection_id;
  if v_layout is not null then
    outcome := 'ALREADY_EXISTS';
    layout_id := v_layout;
    grid_columns := v_ex_cols;
    grid_rows := v_ex_rows;
    pages_created := 0; slots_created := 0; reservations_created := 0;
    assignments_created := 0; extras_unplaced := 0;
    return next;
    return;
  end if;

  -- 3. Coleção ativa ----------------------------------------------------------------
  if v_status <> 'ACTIVE' then
    raise exception 'COLLECTION_ARCHIVED' using errcode = '55000';
  end if;

  -- 4. D1: local padrão do próprio acervo, do tipo BINDER (lido sob a trava) ----
  if v_default is not null then
    select sc.kind_code::text into v_kind_sc
    from public.storage_container sc
    join public.inventory i on i.id = sc.inventory_id
    where sc.id = v_default and i.owner_user_id = v_uid;
  end if;
  if v_kind_sc is distinct from 'BINDER' then
    raise exception 'NOT_ELIGIBLE' using errcode = '55000';
  end if;

  -- 5. Volume (provisório) antes do plano -----------------------------------------
  select count(*)::integer into v_allocs
  from public.collection_allocation ca where ca.collection_id = p_collection_id;
  if v_allocs > c_max_allocations then
    raise exception 'COLLECTION_TOO_LARGE' using errcode = '54000';
  end if;

  -- 6. Plano: calculado UMA vez, sob a trava; é exatamente o que será gravado ----
  select max(h.plan_token),
         max(h.pages_total),
         array_agg(h.page_number order by h.item_kind, h.item_ord)
           filter (where h.item_kind <> 'HEADER' and h.page_number is not null),
         array_agg(h.row_index order by h.item_kind, h.item_ord)
           filter (where h.item_kind <> 'HEADER' and h.page_number is not null),
         array_agg(h.column_index order by h.item_kind, h.item_ord)
           filter (where h.item_kind <> 'HEADER' and h.page_number is not null),
         array_agg(h.expected_card_id order by h.item_kind, h.item_ord)
           filter (where h.item_kind <> 'HEADER' and h.page_number is not null),
         array_agg(h.expected_variant_type_id order by h.item_kind, h.item_ord)
           filter (where h.item_kind <> 'HEADER' and h.page_number is not null),
         array_agg(h.collection_allocation_id order by h.item_kind, h.item_ord)
           filter (where h.item_kind <> 'HEADER' and h.page_number is not null),
         (count(*) filter (where h.item_kind = 'EXTRA' and h.page_number is null))::integer,
         (count(*) filter (where h.item_kind <> 'HEADER' and h.page_number is not null
                             and h.expected_card_id is not null))::integer,
         (count(*) filter (where h.item_kind <> 'HEADER' and h.page_number is not null
                             and h.collection_allocation_id is not null))::integer
    into v_token, v_pages, a_pg, a_rw, a_cl, a_ec, a_ev, a_al, v_unplaced, v_exp_resv, v_exp_asg
  from public.collection_binder_plan(p_collection_id, p_grid_columns, p_grid_rows, v_policy_x) h;

  if v_pages is null or v_pages < 1 then
    raise exception 'BINDER_ASSEMBLY_INCONSISTENT';
  end if;
  if v_pages * v_cap > c_max_slots then
    raise exception 'COLLECTION_TOO_LARGE' using errcode = '54000';
  end if;

  -- 7. O usuário autoriza exatamente o que viu --------------------------------------
  if v_token is distinct from p_plan_token then
    raise exception 'PLAN_CHANGED';
  end if;

  -- 8. Escrita atômica, set-based ----------------------------------------------------
  begin
    insert into public.collection_layout (collection_id, grid_rows, grid_columns)
    values (p_collection_id, p_grid_rows, p_grid_columns)
    returning id into v_layout;
  exception when unique_violation then
    raise exception 'LAYOUT_ALREADY_EXISTS';
  end;

  insert into public.collection_layout_page (layout_id, page_number)
  select v_layout, g from generate_series(1, v_pages) g;
  get diagnostics v_n_pages = row_count;

  insert into public.collection_layout_slot (page_id, row_index, column_index)
  select p.id, gr.n, gc.n
  from public.collection_layout_page p
  cross join generate_series(1, p_grid_rows) as gr(n)
  cross join generate_series(1, p_grid_columns) as gc(n)
  where p.layout_id = v_layout;
  get diagnostics v_n_slots = row_count;

  insert into public.collection_layout_slot_expected_content
    (slot_id, card_id, card_variant_id, expected_variant_type_id)
  select s.id, u.ec, null, u.ev
  from unnest(coalesce(a_pg, '{}'), coalesce(a_rw, '{}'), coalesce(a_cl, '{}'),
              coalesce(a_ec, '{}'), coalesce(a_ev, '{}')) as u(pg, rw, cl, ec, ev)
  join public.collection_layout_page p on p.layout_id = v_layout and p.page_number = u.pg
  join public.collection_layout_slot s on s.page_id = p.id and s.row_index = u.rw and s.column_index = u.cl
  where u.ec is not null;
  get diagnostics v_n_resv = row_count;

  insert into public.collection_layout_slot_assignment (slot_id, collection_allocation_id)
  select s.id, u.al
  from unnest(coalesce(a_pg, '{}'), coalesce(a_rw, '{}'), coalesce(a_cl, '{}'),
              coalesce(a_al, '{}')) as u(pg, rw, cl, al)
  join public.collection_layout_page p on p.layout_id = v_layout and p.page_number = u.pg
  join public.collection_layout_slot s on s.page_id = p.id and s.row_index = u.rw and s.column_index = u.cl
  where u.al is not null;
  get diagnostics v_n_asg = row_count;

  -- 9. Conferência: qualquer divergência desfaz TUDO ------------------------------
  if v_n_pages <> v_pages
     or v_n_slots <> v_pages * v_cap
     or v_n_resv <> v_exp_resv
     or v_n_asg <> v_exp_asg then
    raise exception 'BINDER_ASSEMBLY_INCONSISTENT';
  end if;

  -- E01: itens DEPOIS de criar páginas, bolsos, reservas e posições (I-10; W1 recalcula o teto  -- P3B-S6
  -- a cada PAGE_ADDED). ALREADY_EXISTS e recusas saem antes → nada gravado.  -- P3B-S6
  perform public.binder_activity_begin(v_layout, 'BINDER_ASSEMBLED', 'FICHARIO', p_collection_id,  -- P3B-S6
    jsonb_build_object('grid_columns', p_grid_columns, 'grid_rows', p_grid_rows,  -- P3B-S6
                       'extra_policy', v_policy_x, 'extras_unplaced', v_unplaced));  -- P3B-S6
  for v_act in  -- P3B-S6
    select p.page_number from public.collection_layout_page p where p.layout_id = v_layout order by p.page_number  -- P3B-S6
  loop  -- P3B-S6
    perform public.binder_activity_add_item('PAGE', 'PAGE_ADDED', null, null, null, null, null, v_act.page_number);  -- P3B-S6
  end loop;  -- P3B-S6
  for v_act in  -- P3B-S6
    select a.physical_card_id, a.slot_id  -- P3B-S6
    from public.collection_layout_slot_assignment a  -- P3B-S6
    join public.collection_layout_slot s on s.id = a.slot_id  -- P3B-S6
    join public.collection_layout_page p on p.id = s.page_id  -- P3B-S6
    where p.layout_id = v_layout  -- P3B-S6
    order by p.page_number, s.row_index, s.column_index  -- P3B-S6
  loop  -- P3B-S6
    perform public.binder_activity_add_card_item('PLACED', v_act.physical_card_id, null, v_act.slot_id);  -- P3B-S6
  end loop;  -- P3B-S6
  for v_act in  -- P3B-S6
    select e.slot_id  -- P3B-S6
    from public.collection_layout_slot_expected_content e  -- P3B-S6
    join public.collection_layout_slot s on s.id = e.slot_id  -- P3B-S6
    join public.collection_layout_page p on p.id = s.page_id  -- P3B-S6
    where p.layout_id = v_layout  -- P3B-S6
    order by p.page_number, s.row_index, s.column_index  -- P3B-S6
  loop  -- P3B-S6
    perform public.binder_activity_add_reservation_item('RESERVED', v_act.slot_id);  -- P3B-S6
  end loop;  -- P3B-S6
  perform public.binder_activity_end();  -- P3B-S6
  -- P3B-S6
  outcome              := 'CREATED';
  layout_id            := v_layout;
  grid_columns         := p_grid_columns;
  grid_rows            := p_grid_rows;
  pages_created        := v_n_pages;
  slots_created        := v_n_slots;
  reservations_created := v_n_resv;
  assignments_created  := v_n_asg;
  extras_unplaced      := v_unplaced;
  return next;
end;
$fn$;

revoke all on function public.create_my_collection_binder(uuid, integer, integer, text, text) from public;
revoke all on function public.create_my_collection_binder(uuid, integer, integer, text, text) from anon;
grant execute on function public.create_my_collection_binder(uuid, integer, integer, text, text) to authenticated;

commit;

/*
Resultado esperado: create_my_collection_binder(uuid, integer, integer, text, text) recriada com o mesmo contrato; nenhum evento gravado pela instalação.
Como validar (só leitura): LIVE_S6_90_postcheck_readonly.sql, bloco A.
*/
