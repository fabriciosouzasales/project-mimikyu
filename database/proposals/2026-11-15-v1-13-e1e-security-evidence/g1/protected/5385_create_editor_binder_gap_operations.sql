/* G1 (D-E1) — VERSÃO PROTEGIDA GERADA. Não editar à mão: g1/build_g1_protected.py.
   Base auditada: database/proposals/2026-11-15-v1-13-e1c2-remaining-bulk-operations/5385_create_editor_binder_gap_operations.sql
   sha256 da base: 79855ad2db7ea23bccccfa09e826d46d8d622e7a549a96db92deb596c4ab35c4
   Única mudança: porta 5389 consultada antes de qualquer leitura ou efeito em 3 função(ões); precheck da 5389.
   Status: PROPOSTA — NÃO EXECUTADA. Mecanismo não homologado (G1). */
/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5385 - Inserir e fechar espaço pelo EDITOR, só no fichário exclusivo e
              só com conteúdo da coleção autorizada (V1-13 · E1-C2), e ajudantes
              internos comuns da E1-C2
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA. Preparada em
              `V1-13 / E1-C2 | REMAINING BULK OPERATIONS-01` (2026-11-15).
              Execução só com prova dinâmica sob protocolo controlado (C-244) e
              autorização expressa e específica.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-15
Contrato....: C-237 (inserir e fechar espaço são operações em massa: num fichário
              de várias coleções, só o titular; num fichário de uma coleção, o
              EDITOR, sem deslocar, retirar nem descartar conteúdo de terceiros),
              C-238, C-241, C-243.
Depende de..: 5243 (cadeia, avaliação, deslocamento e token de desfazer — reusados,
              não copiados), 5279, 5371 (binder_slot_at, binder_slot_editor_scope),
              5378, 5379, 5382 (assert_collection_binder_editor_exclusive), 5384
              (tipos GAP_OPENED/GAP_CLOSED para o EDITOR — aplicar a 5384 antes de
              usar estas funções; a 5385 não depende dela para ser criada).

Ajudantes internos (sem EXECUTE para a API), usados também pela 5386/5387:
  editor_binder_exclusive_read(p_collection_id) → (layout_id, owner_user_id,
      container_id)  STABLE, SEM trava — autorização das PRÉVIAS: EDITOR ACTIVE de
      X, X proprietária do fichário, nenhuma convidada, X e o fichário ativos.
      Mesmas recusas da 5382 (COLLECTION_NOT_FOUND, BINDER_NOT_FOUND,
      OPERATION_RESERVED_TO_OWNER, COLLECTION_ARCHIVED).
  binder_editor_any_foreign(p_layout_id, p_collection_id, p_slot_ids uuid[])
      → boolean  STABLE — algum bolso do conjunto é FOREIGN para X (5371/5378).
      "Fichário exclusivo" não basta: restam cartas de convidada desassociada
      (5253), cartas sem coleção, imagens, mesclagens e travas do titular e
      referências de proprietária anterior (5254).
  binder_editor_append_page(p_layout_id) → (page_id, page_number)  VOLATILE —
      página vazia no fim, com a grade do fichário, e item PAGE_ADDED no evento
      ABERTO (espelho do trecho da 5280 usado pela 5243/5296; a 5280 do titular
      exige o titular e não pode ser chamada pelo EDITOR).

RPCs novas (EXECUTE só authenticated), endereçadas por POSIÇÃO visível:
  editor_preview_binder_insert_gap(p_collection_id, p_page, p_row, p_column)
      → (outcome, moved_pockets, moved_cards, moved_reserves, rows_moved,
         row_limit, pages, target_page, target_row, target_column, plan_token)
  editor_insert_binder_gap(p_collection_id, p_page, p_row, p_column, p_plan_token,
                           p_confirm_cross_page default false,
                           p_confirm_add_page default false)
      → (outcome, end_page, end_row, end_column, added_page_number,
         moved_pockets, rows_moved, pages, undo_token)
  editor_close_binder_gap(p_collection_id, p_gap_page, p_gap_row, p_gap_column,
                          p_end_page, p_end_row, p_end_column, p_undo_token,
                          p_added_page_number default null)
      → (outcome, moved_pockets, rows_moved, page_removed)
Regras (espelho de 5243/5283/5284 com coleção explícita):
  - mesma cadeia, mesmo plano, mesmo token (g1/u1), mesmas barreiras (bolso
    fixado ou mesclado não anda e bloqueia), mesmo limite de 500 linhas;
  - ANTES de qualquer escrita: todos os bolsos que andam e o bolso de destino
    (ou, ao fechar, todo o trecho gap..fim) precisam ser OWN ou FREE para X.
    Qualquer FOREIGN → OPERATION_RESERVED_TO_OWNER, sem dizer o quê. Assim uma
    imagem do titular, uma carta de terceiros ou um bolso rotulado por outra
    coleção nunca são deslocados, sobrescritos nem passam a abrigar carta de X;
  - prévia sem posição da barreira, sem contagem de imagens e sem ids de bolso;
  - página nova (NEEDS_PAGE, com confirmação) criada pelo ajudante, no mesmo
    evento; ao fechar, a página criada só é removida se for a última, estiver
    totalmente vazia e sem referência de espécie (senão fica);
  - referências de espécie NÃO andam (ficam no bolso, como no titular): o
    conteúdo de X pode passar para um bolso rotulado por X (OWN) ou livre.
Travas: proprietária → layout → participação (5382) → bolsos da cadeia por id
  (mesma ordem da 5283/5284 depois da 5122). Toda recusa antes da escrita ou
  exceção que desfaz a chamada inteira.
Histórico: GAP_OPENED / GAP_CLOSED (FICHARIO, coleção X), itens SHIFTED (5279) e
  PAGE_ADDED/PAGE_REMOVED, todos de X ou de página (5379).
Funções do titular (5243, 5283, 5284, 5280, 5286): não tocadas. DEVER DE
  ESPELHO: mudanças nelas precisam ser repetidas aqui (README).
Canal.......: psql. Idempotência: funções já presentes → 'JÁ APLICADA ou
              DIVERGENTE'. Reversão: R5385 em ROLLBACK_E1C2.sql.
Como validar: harness 5893, seção 1.
================================================================
*/

begin;

set local lock_timeout = '5s';

do $pre$
begin
  if to_regprocedure('public.v1_13_assert_capability()') is null or to_regprocedure('public.v1_13_capability_open()') is null then raise exception 'PRECHECK G1: barreira 5389 ausente'; end if;  -- G1 (D-E1)
  if to_regprocedure('public.binder_gap_chain(uuid, uuid)') is null
     or to_regprocedure('public.binder_gap_evaluate(uuid, uuid)') is null
     or to_regprocedure('public.binder_gap_move_pocket(uuid, uuid)') is null
     or to_regprocedure('public.binder_gap_undo_token(uuid, uuid, uuid, uuid)') is null
     or to_regprocedure('public.binder_activity_add_pocket_shift_items(uuid, uuid)') is null
     or to_regprocedure('public.assert_collection_binder_editor_exclusive(uuid)') is null
     or to_regprocedure('public.binder_slot_at(uuid, integer, integer, integer)') is null
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
          where p.oid = to_regprocedure('public.binder_slot_editor_scope(uuid, uuid, uuid, uuid)'))
        is distinct from '21f1b51a3a0f6c80337c2c593cc6054f' then
    raise exception 'PRECHECK 5385: 5243, 5279, E1-B1, 5378 ou E1-C1 (5382) ausentes';
  end if;
  if to_regprocedure('public.editor_binder_exclusive_read(uuid)') is not null
     or to_regprocedure('public.binder_editor_any_foreign(uuid, uuid, uuid[])') is not null
     or to_regprocedure('public.binder_editor_append_page(uuid)') is not null
     or to_regprocedure('public.editor_preview_binder_insert_gap(uuid, integer, integer, integer)') is not null
     or to_regprocedure('public.editor_insert_binder_gap(uuid, integer, integer, integer, text, boolean, boolean)') is not null
     or to_regprocedure('public.editor_close_binder_gap(uuid, integer, integer, integer, integer, integer, integer, text, integer)') is not null then
    raise exception 'PRECHECK 5385: JÁ APLICADA ou ESTADO DIVERGENTE';
  end if;
end;
$pre$;

-- Ajudante: autorização sem trava para as prévias ------------------------------------------
create function public.editor_binder_exclusive_read(p_collection_id uuid)
returns table (layout_id uuid, owner_user_id uuid, container_id uuid)
language plpgsql
stable
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_uid    uuid := (select auth.uid());
  v_owner  uuid;
  v_status text;
  v_layout uuid;
  v_cont   uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  select c.owner_user_id, c.lifecycle_status into v_owner, v_status
  from public.collection c
  join public.collection_membership m
    on m.collection_id = c.id and m.user_id = v_uid and m.status = 'ACTIVE' and m.role = 'EDITOR'
  where c.id = p_collection_id and c.owner_user_id <> v_uid;
  if v_owner is null then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;
  select l.id, l.storage_container_id into v_layout, v_cont
  from public.collection_layout l where l.collection_id = p_collection_id;
  if v_layout is null then
    if exists (select 1 from public.collection_layout_guest g where g.collection_id = p_collection_id) then
      raise exception 'OPERATION_RESERVED_TO_OWNER' using errcode = '42501',
        hint = 'num fichário com mais de uma coleção, esta operação é do titular';
    end if;
    raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
  end if;
  if exists (select 1 from public.collection_layout_guest g where g.layout_id = v_layout) then
    raise exception 'OPERATION_RESERVED_TO_OWNER' using errcode = '42501',
      hint = 'num fichário com mais de uma coleção, esta operação é do titular';
  end if;
  if v_status <> 'ACTIVE' then
    raise exception 'COLLECTION_ARCHIVED' using errcode = '55000';
  end if;
  return query select v_layout, v_owner, v_cont;
end;
$fn$;

-- Ajudante: algum bolso do conjunto é de terceiros? -------------------------------------------
create function public.binder_editor_any_foreign(p_layout_id uuid, p_collection_id uuid, p_slot_ids uuid[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select exists (
    select 1 from unnest(coalesce(p_slot_ids, '{}'::uuid[])) u(sid)
    where u.sid is null
       or public.binder_slot_editor_scope(p_layout_id, p_collection_id, p_collection_id, u.sid) = 'FOREIGN');
$fn$;

-- Ajudante: página nova no fim, dentro do evento aberto --------------------------------------
create function public.binder_editor_append_page(p_layout_id uuid)
returns table (page_id uuid, page_number integer)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_rows integer;
  v_cols integer;
  v_next integer;
  v_page uuid;
  v_n    integer;
begin
  select l.grid_rows, l.grid_columns into v_rows, v_cols
  from public.collection_layout l where l.id = p_layout_id;
  select coalesce(max(p.page_number), 0) + 1 into v_next
  from public.collection_layout_page p where p.layout_id = p_layout_id;
  insert into public.collection_layout_page as clp (layout_id, page_number)
  values (p_layout_id, v_next)
  returning clp.id into v_page;
  insert into public.collection_layout_slot (page_id, row_index, column_index)
  select v_page, r, c
  from generate_series(1, v_rows) as r
  cross join generate_series(1, v_cols) as c;
  get diagnostics v_n = row_count;
  if v_n <> v_rows * v_cols then
    raise exception 'inconsistência estrutural: % bolsos criados, esperado %', v_n, v_rows * v_cols;
  end if;
  perform public.binder_activity_add_item('PAGE', 'PAGE_ADDED', null, null, null, null, null, v_next);
  return query select v_page, v_next;
end;
$fn$;

-- Prévia de inserir espaço ---------------------------------------------------------------------
create function public.editor_preview_binder_insert_gap(
  p_collection_id uuid,
  p_page          integer,
  p_row           integer,
  p_column        integer
)
returns table (
  outcome text, moved_pockets integer, moved_cards integer, moved_reserves integer,
  rows_moved integer, row_limit integer, pages integer[],
  target_page integer, target_row integer, target_column integer, plan_token text
)
language plpgsql
stable
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_layout uuid;
  v_slot   uuid;
  e        record;
  v_set    uuid[];
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  select x.layout_id into v_layout from public.editor_binder_exclusive_read(p_collection_id) x;
  v_slot := public.binder_slot_at(v_layout, p_page, p_row, p_column);
  if v_slot is null then
    raise exception 'SLOT_NOT_FOUND' using errcode = 'P0002';
  end if;
  select * into e from public.binder_gap_evaluate(v_layout, v_slot);
  if e.outcome in ('SAME_PAGE', 'CROSS_PAGE', 'NEEDS_PAGE', 'OVER_LIMIT', 'BLOCKED') then
    select array_agg(c.slot_id) into v_set
    from public.binder_gap_chain(v_layout, v_slot) c
    where c.ord < (select min(c0.ord) from public.binder_gap_chain(v_layout, v_slot) c0) + e.moved_pockets;
    if public.binder_editor_any_foreign(v_layout, p_collection_id,
                                        v_set || case when e.target_slot_id is null then '{}'::uuid[] else array[e.target_slot_id] end) then
      raise exception 'OPERATION_RESERVED_TO_OWNER' using errcode = '42501',
        hint = 'o espaço deslocaria conteúdo que só o titular pode mover';
    end if;
  end if;
  return query
  select e.outcome, e.moved_pockets, e.moved_cards, e.moved_reserves, e.rows_moved, e.row_limit, e.pages,
         tp.page_number, ts.row_index, ts.column_index, e.plan_token
  from (select 1) z
  left join public.collection_layout_slot ts on ts.id = e.target_slot_id
  left join public.collection_layout_page tp on tp.id = ts.page_id;
end;
$fn$;

-- Inserir espaço -------------------------------------------------------------------------------
create function public.editor_insert_binder_gap(
  p_collection_id      uuid,
  p_page               integer,
  p_row                integer,
  p_column             integer,
  p_plan_token         text,
  p_confirm_cross_page boolean default false,
  p_confirm_add_page   boolean default false
)
returns table (
  outcome text, end_page integer, end_row integer, end_column integer, added_page_number integer,
  moved_pockets integer, rows_moved integer, pages integer[], undo_token text
)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_layout uuid;
  v_slot   uuid;
  e        record;
  v_chain  uuid[];
  v_dest   uuid[];
  v_target uuid;
  v_added  uuid;
  v_addn   integer;
  v_rows   integer := 0;
  i        integer;
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  if p_plan_token is null or p_plan_token !~ '^g1:[0-9a-f]{64}$' then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  select x.layout_id into v_layout from public.assert_collection_binder_editor_exclusive(p_collection_id) x;
  v_slot := public.binder_slot_at(v_layout, p_page, p_row, p_column);
  if v_slot is null then
    raise exception 'SLOT_NOT_FOUND' using errcode = 'P0002';
  end if;
  select * into e from public.binder_gap_evaluate(v_layout, v_slot);

  if e.outcome = 'ALREADY_FREE' then
    return query select 'ALREADY_FREE'::text, null::integer, null::integer, null::integer, null::integer,
                        0, 0, null::integer[], null::text;
    return;
  end if;
  if e.outcome = 'NOT_FOUND' then
    raise exception 'SLOT_NOT_FOUND' using errcode = 'P0002';
  end if;
  if e.plan_token is distinct from p_plan_token then
    raise exception 'GAP_PLAN_CHANGED' using errcode = '40001',
      hint = 'o fichário mudou desde a prévia — veja a prévia de novo';
  end if;
  if e.outcome in ('AT_BARRIER', 'BLOCKED') then
    raise exception 'GAP_BLOCKED' using errcode = '55000', hint = 'há um bolso fixado ou mesclado no caminho';
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
  from public.binder_gap_chain(v_layout, v_slot) c
  where c.ord < (select min(c0.ord) from public.binder_gap_chain(v_layout, v_slot) c0) + e.moved_pockets;
  if v_chain is null or cardinality(v_chain) <> e.moved_pockets then
    raise exception 'GAP_INCONSISTENT';
  end if;

  -- Conjunto afetado inteiro, sob as travas, antes de qualquer escrita.
  if public.binder_editor_any_foreign(v_layout, p_collection_id,
                                      v_chain || case when e.target_slot_id is null then '{}'::uuid[] else array[e.target_slot_id] end) then
    raise exception 'OPERATION_RESERVED_TO_OWNER' using errcode = '42501',
      hint = 'o espaço deslocaria conteúdo que só o titular pode mover';
  end if;

  perform public.binder_activity_begin(v_layout, 'GAP_OPENED', 'FICHARIO', p_collection_id);
  if e.outcome = 'NEEDS_PAGE' then
    select ap.page_id, ap.page_number into v_added, v_addn from public.binder_editor_append_page(v_layout) ap;
    v_target := public.binder_slot_at(v_layout, v_addn, 1, 1);
  else
    v_target := e.target_slot_id;
  end if;
  if v_target is null then
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
     or exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = v_slot)
     or exists (select 1 from public.collection_layout_slot_expected_content x where x.slot_id = v_slot)
     or exists (select 1 from public.collection_layout_slot_image im where im.slot_id = v_slot) then
    raise exception 'GAP_INCONSISTENT';
  end if;
  for i in 1..cardinality(v_chain) loop
    perform public.binder_activity_add_pocket_shift_items(v_chain[i], v_dest[i]);
  end loop;
  perform public.binder_activity_end();

  return query
  select 'INSERTED'::text, tp.page_number, ts.row_index, ts.column_index, v_addn,
         e.moved_pockets, v_rows, e.pages, public.binder_gap_undo_token(v_layout, v_slot, v_target, v_added)
  from public.collection_layout_slot ts
  join public.collection_layout_page tp on tp.id = ts.page_id
  where ts.id = v_target;
end;
$fn$;

-- Fechar espaço (desfazer) ---------------------------------------------------------------------
create function public.editor_close_binder_gap(
  p_collection_id     uuid,
  p_gap_page          integer,
  p_gap_row           integer,
  p_gap_column        integer,
  p_end_page          integer,
  p_end_row           integer,
  p_end_column        integer,
  p_undo_token        text,
  p_added_page_number integer default null
)
returns table (outcome text, moved_pockets integer, rows_moved integer, page_removed boolean)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  c_row_limit constant integer := 500;
  v_layout uuid;
  v_gap    uuid;
  v_end    uuid;
  v_added  uuid;
  v_chain  uuid[];
  v_count  integer;
  v_rows   integer := 0;
  v_removed boolean := false;
  i        integer;
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  if p_undo_token is null or p_undo_token !~ '^u1:[0-9a-f]{64}$' then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  select x.layout_id into v_layout from public.assert_collection_binder_editor_exclusive(p_collection_id) x;
  v_gap := public.binder_slot_at(v_layout, p_gap_page, p_gap_row, p_gap_column);
  v_end := public.binder_slot_at(v_layout, p_end_page, p_end_row, p_end_column);
  if p_added_page_number is not null then
    select p.id into v_added from public.collection_layout_page p
    where p.layout_id = v_layout and p.page_number = p_added_page_number;
  end if;
  if v_gap is null or v_end is null or (p_added_page_number is not null and v_added is null)
     or public.binder_gap_undo_token(v_layout, v_gap, v_end, v_added) is distinct from p_undo_token then
    raise exception 'GAP_UNDO_EXPIRED' using errcode = '40001',
      hint = 'o fichário mudou desde que o espaço foi aberto';
  end if;

  with s as (
    select sl.id, sl.locked,
           (row_number() over (order by p.page_number, sl.row_index, sl.column_index))::integer as ord,
           exists (select 1 from public.collection_layout_region r
                   where r.page_id = sl.page_id
                     and sl.row_index    between r.top_row     and r.top_row     + r.height - 1
                     and sl.column_index between r.left_column and r.left_column + r.width  - 1) as in_region
    from public.collection_layout_slot sl
    join public.collection_layout_page p on p.id = sl.page_id
    where p.layout_id = v_layout
  ), c as (
    select s.* from s
    where s.ord between (select s1.ord from s s1 where s1.id = v_gap)
                    and (select s2.ord from s s2 where s2.id = v_end)
  )
  select array_agg(c.id order by c.ord), count(*) filter (where c.locked or c.in_region)
    into v_chain, v_count
  from c;
  if v_chain is null or cardinality(v_chain) < 2 or v_count > 0 then
    raise exception 'GAP_UNDO_EXPIRED' using errcode = '40001';
  end if;

  -- Trecho inteiro de X ou livre, antes de qualquer escrita.
  if public.binder_editor_any_foreign(v_layout, p_collection_id, v_chain) then
    raise exception 'OPERATION_RESERVED_TO_OWNER' using errcode = '42501',
      hint = 'fechar o espaço deslocaria conteúdo que só o titular pode mover';
  end if;

  perform 1 from public.collection_layout_slot s where s.id = any (v_chain) order by s.id for update;
  perform public.binder_activity_begin(v_layout, 'GAP_CLOSED', 'FICHARIO', p_collection_id);
  for i in 2..cardinality(v_chain) loop
    v_rows := v_rows + public.binder_gap_move_pocket(v_chain[i], v_chain[i - 1]);
    if v_rows > c_row_limit then
      raise exception 'GAP_OVER_LIMIT' using errcode = '54000';
    end if;
  end loop;
  for i in 2..cardinality(v_chain) loop
    perform public.binder_activity_add_pocket_shift_items(v_chain[i], v_chain[i - 1]);
  end loop;

  -- Página criada pela inserção: só sai se for a última e estiver vazia de TUDO,
  -- inclusive referência de espécie (nada é descartado; senão fica).
  if v_added is not null
     and p_added_page_number = (select max(p2.page_number) from public.collection_layout_page p2 where p2.layout_id = v_layout)
     and (select count(*) from public.collection_layout_page p3 where p3.layout_id = v_layout) > 1
     and not exists (
       select 1 from public.collection_layout_slot s
       where s.page_id = v_added
         and (s.locked
              or exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = s.id)
              or exists (select 1 from public.collection_layout_slot_expected_content x where x.slot_id = s.id)
              or exists (select 1 from public.collection_layout_slot_image im where im.slot_id = s.id)
              or exists (select 1 from public.collection_layout_slot_species_reference sr where sr.slot_id = s.id)))
     and not exists (select 1 from public.collection_layout_region r where r.page_id = v_added) then
    perform public.binder_activity_add_item('PAGE', 'PAGE_REMOVED', null, null, null, null, p_added_page_number, null);
    delete from public.collection_layout_page p where p.id = v_added;
    v_removed := true;
  end if;
  perform public.binder_activity_end();

  return query select 'CLOSED'::text, cardinality(v_chain) - 1, v_rows, v_removed;
end;
$fn$;

comment on function public.editor_binder_exclusive_read(uuid) is
  'V1-13 E1-C2 (5385, interna): autorização SEM trava das prévias do EDITOR — EDITOR ACTIVE, coleção proprietária do fichário, sem convidadas, ativa.';
comment on function public.binder_editor_any_foreign(uuid, uuid, uuid[]) is
  'V1-13 E1-C2 (5385, interna): verdadeiro se algum bolso do conjunto for FOREIGN para a coleção (5371/5378).';
comment on function public.binder_editor_append_page(uuid) is
  'V1-13 E1-C2 (5385, interna): página vazia no fim do fichário com item PAGE_ADDED no evento aberto.';
comment on function public.editor_preview_binder_insert_gap(uuid, integer, integer, integer) is
  'V1-13 E1-C2 (5385): prévia de inserir espaço para o EDITOR (5243), só no fichário exclusivo e com cadeia de X; sem barreira, imagens ou ids.';
comment on function public.editor_insert_binder_gap(uuid, integer, integer, integer, text, boolean, boolean) is
  'V1-13 E1-C2 (5385): EDITOR insere espaço (espelho da 5283) só se todos os bolsos que andam e o destino forem de X ou livres.';
comment on function public.editor_close_binder_gap(uuid, integer, integer, integer, integer, integer, integer, text, integer) is
  'V1-13 E1-C2 (5385): EDITOR fecha o espaço (espelho da 5284) com o token de desfazer, só com trecho de X ou livre.';

revoke all on function public.editor_binder_exclusive_read(uuid) from public, anon, authenticated, service_role;
revoke all on function public.binder_editor_any_foreign(uuid, uuid, uuid[]) from public, anon, authenticated, service_role;
revoke all on function public.binder_editor_append_page(uuid) from public, anon, authenticated, service_role;
revoke all on function public.editor_preview_binder_insert_gap(uuid, integer, integer, integer) from public, anon;
revoke all on function public.editor_insert_binder_gap(uuid, integer, integer, integer, text, boolean, boolean) from public, anon;
revoke all on function public.editor_close_binder_gap(uuid, integer, integer, integer, integer, integer, integer, text, integer) from public, anon;
grant execute on function public.editor_preview_binder_insert_gap(uuid, integer, integer, integer) to authenticated;
grant execute on function public.editor_insert_binder_gap(uuid, integer, integer, integer, text, boolean, boolean) to authenticated;
grant execute on function public.editor_close_binder_gap(uuid, integer, integer, integer, integer, integer, integer, text, integer) to authenticated;

do $post$
declare
  f oid;
begin
  foreach f in array array[to_regprocedure('public.editor_preview_binder_insert_gap(uuid, integer, integer, integer)'),
                           to_regprocedure('public.editor_insert_binder_gap(uuid, integer, integer, integer, text, boolean, boolean)'),
                           to_regprocedure('public.editor_close_binder_gap(uuid, integer, integer, integer, integer, integer, integer, text, integer)')] loop
    if f is null
       or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
       or (select p.proconfig from pg_catalog.pg_proc p where p.oid = f) is distinct from array['search_path=""']
       or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not true
       or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false then
      raise exception 'POSTCHECK 5385: RPC fora do estado esperado (%)', f;
    end if;
  end loop;
  foreach f in array array[to_regprocedure('public.editor_binder_exclusive_read(uuid)'),
                           to_regprocedure('public.binder_editor_any_foreign(uuid, uuid, uuid[])'),
                           to_regprocedure('public.binder_editor_append_page(uuid)')] loop
    if f is null
       or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not false
       or pg_catalog.has_function_privilege('service_role', f, 'EXECUTE') is not false then
      raise exception 'POSTCHECK 5385: ajudante interno fora do estado esperado (%)', f;
    end if;
  end loop;
end;
$post$;

commit;
