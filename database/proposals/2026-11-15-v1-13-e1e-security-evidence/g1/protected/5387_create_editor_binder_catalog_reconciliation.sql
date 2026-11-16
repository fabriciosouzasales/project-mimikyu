/* G1 (D-E1) — VERSÃO PROTEGIDA GERADA. Não editar à mão: g1/build_g1_protected.py.
   Base auditada: database/proposals/2026-11-15-v1-13-e1c2-remaining-bulk-operations/5387_create_editor_binder_catalog_reconciliation.sql
   sha256 da base: ea001d06c703a4b816ca44459c4f8028273f3d9cb103e70f7ebeeaade4e8c313
   Única mudança: porta 5389 consultada antes de qualquer leitura ou efeito em 2 função(ões); precheck da 5389.
   Status: PROPOSTA — NÃO EXECUTADA. Mecanismo não homologado (G1). */
/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5387 - Novidades do Catálogo pelo EDITOR (Master Set), só no fichário
              exclusivo e só com conteúdo da coleção autorizada (V1-13 · E1-C2)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA. Preparada em
              `V1-13 / E1-C2 | REMAINING BULK OPERATIONS-01` (2026-11-15).
              Execução só com prova dinâmica sob protocolo controlado (C-244) e
              autorização expressa e específica.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-15
Contrato....: C-200 (novidades do Catálogo), C-237 (operação em massa: só no
              fichário de uma coleção, sem deslocar terceiros), C-239 (Set, escopo e
              acabamentos são do titular — nada disso muda aqui), C-242, C-243.
Depende de..: 5263/5264 (contexto, novidades e plano canônico — REUSADOS),
              5243 (deslocamento), 5265 (prévia do titular, como referência),
              5296 (aplicação do titular, espelhada), 5385 (ajudantes), 5382,
              5384 (tipo CATALOG_NOVELTIES_INCORPORATED com origem CATALOGO para o
              EDITOR).

O que a operação do titular faz (5264/5296), por partes:
  leitura de novidades — binder_catalog_novelties: posições do Master Set de X
      nascidas depois do marco de participação, ainda sem reserva e não
      incorporadas (W5). Só leitura; dados do Catálogo e de X;
  prévia — binder_catalog_plan: simulação completa e token rc1;
  confirmação — por novidade: reserva nova no bolso natural (IN_PLACE), reserva
      sobre exemplar já no bolso natural (RESERVE_PLACED), acabamento
      acrescentado a reserva genérica de X (UPGRADE_RESERVATION) ou deslocamento
      com a regra da 5243 (SHIFT) e, sem bolso livre, página nova no fim;
      registro de incorporação (layout, X, chave) para a novidade não voltar;
  referências de espécie — nunca lidas nem escritas: fichário com qualquer
      referência é inelegível (5264);
  estrutura — só páginas novas no fim; nenhum Set, escopo, acabamento, política,
      alocação, exemplar, local ou condição muda.
  Global? O plano é por coleção e o registro também; o único efeito sobre o
  fichário inteiro é o deslocamento e a página nova — isoláveis pela regra
  abaixo. Por isso a operação é oferecida ao EDITOR, e não reservada ao titular.
RPCs novas (EXECUTE só authenticated):
  editor_preview_binder_catalog_reconciliation(p_collection_id, p_keys default null)
      → as colunas da 5265, com layout_id, capacidade e bolsos livres em NULL
        (revelariam ocupação de terceiros) e posição de barreira em NULL quando
        o bolso da barreira não é de X.
  editor_apply_binder_catalog_reconciliation(p_collection_id, p_keys, p_plan_token,
        p_confirm_cross_page default false, p_confirm_add_page default false)
      → as colunas da 5296.
Regras adicionais do EDITOR (antes de qualquer escrita, sob as travas):
  - fichário exclusivo (5382) e X elegível (5264), com o mesmo fichário e titular;
    referência de espécie de outra coleção no fichário (proprietária anterior,
    5254) → OPERATION_RESERVED_TO_OWNER antes da elegibilidade, para a recusa
    não revelar o motivo (a 5264 a recusaria como SPECIES_REFERENCES_PRESENT);
  - CONJUNTO AFETADO = bolsos de destino de cada passo + todo o trecho de cada
    deslocamento (posições existentes entre destino e fim). Nenhum pode ser
    FOREIGN para X → senão OPERATION_RESERVED_TO_OWNER. Basta o estado atual:
    um conteúdo só se desloca a partir de uma posição que está num desses
    trechos no passo em que anda, e páginas novas nascem vazias;
  - BLOCKED sem a posição da barreira na mensagem.
Travas: proprietária → layout → participação (5382) → bolsos de cada passo por id
  (igual à 5296 depois da 5240/5122).
Histórico: CATALOG_NOVELTIES_INCORPORATED (origem CATALOGO, coleção X), itens de
  reserva, deslocamento e página — todos de X ou de página (5379).
Funções do titular (5263–5266, 5296): não tocadas. DEVER DE ESPELHO (README).
Canal.......: psql. Idempotência: funções já presentes → 'JÁ APLICADA ou
              DIVERGENTE'. Reversão: R5387 em ROLLBACK_E1C2.sql.
Como validar: harness 5893, seção 3.
================================================================
*/

begin;

set local lock_timeout = '5s';

do $pre$
begin
  if to_regprocedure('public.v1_13_assert_capability()') is null or to_regprocedure('public.v1_13_capability_open()') is null then raise exception 'PRECHECK G1: barreira 5389 ausente'; end if;  -- G1 (D-E1)
  if to_regprocedure('public.binder_catalog_assert_eligible(uuid)') is null
     or to_regprocedure('public.binder_catalog_novelties(uuid)') is null
     or to_regprocedure('public.binder_catalog_plan(uuid, text[])') is null
     or to_regprocedure('public.binder_gap_move_pocket(uuid, uuid)') is null
     or to_regprocedure('public.binder_editor_append_page(uuid)') is null
     or to_regprocedure('public.editor_binder_exclusive_read(uuid)') is null then
    raise exception 'PRECHECK 5387: 5264, 5243 ou 5385 ausentes';
  end if;
  if to_regprocedure('public.binder_editor_catalog_affected(uuid, uuid, text[])') is not null
     or to_regprocedure('public.editor_preview_binder_catalog_reconciliation(uuid, text[])') is not null
     or to_regprocedure('public.editor_apply_binder_catalog_reconciliation(uuid, text[], text, boolean, boolean)') is not null then
    raise exception 'PRECHECK 5387: JÁ APLICADA ou ESTADO DIVERGENTE';
  end if;
end;
$pre$;

-- Ajudante interno: bolsos existentes alcançados pelo plano --------------------------------------
create function public.binder_editor_catalog_affected(p_layout_id uuid, p_collection_id uuid, p_keys text[])
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $fn$
  with st as (
    select * from public.binder_catalog_plan(p_collection_id, p_keys) p
    where p.row_kind = 'ITEM' and p.kind in ('IN_PLACE', 'RESERVE_PLACED', 'UPGRADE_RESERVATION', 'SHIFT')
  ),
  pos as (
    select s.id, pg.page_number, s.row_index, s.column_index
    from public.collection_layout_page pg
    join public.collection_layout_slot s on s.page_id = pg.id
    where pg.layout_id = p_layout_id
  )
  select coalesce(array_agg(distinct pos.id), '{}'::uuid[])
  from st
  join pos
    on (st.kind <> 'SHIFT'
        and (pos.page_number, pos.row_index, pos.column_index) = (st.target_page, st.target_row, st.target_column))
    or (st.kind = 'SHIFT'
        and (pos.page_number, pos.row_index, pos.column_index) >= (st.target_page, st.target_row, st.target_column)
        and (pos.page_number, pos.row_index, pos.column_index) <= (st.end_page, st.end_row, st.end_column));
$fn$;

-- Prévia ------------------------------------------------------------------------------------------
create function public.editor_preview_binder_catalog_reconciliation(p_collection_id uuid, p_keys text[] default null)
returns table (
  row_kind text, step_no integer, item_key text, card_id uuid, variant_type_id uuid, pos_ord integer, kind text,
  target_page integer, target_row integer, target_column integer, end_page integer, end_row integer, end_column integer,
  anchor_page integer, anchor_row integer, anchor_column integer, pockets_moved integer, rows_moved integer,
  other_reserves_moved integer, crosses_page boolean, adds_page boolean, barrier_page integer, barrier_row integer,
  barrier_column integer, barrier_kind text, outcome text, reason text, layout_id uuid, total_items integer,
  total_rows_moved integer, row_limit integer, item_limit integer, requires_cross_page boolean,
  requires_add_page boolean, pages_added integer, added_page_numbers integer[], capacity_before integer,
  capacity_after integer, free_pockets_after integer, plan_token text
)
language plpgsql
stable
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  r record;
  x record;
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  select * into r from public.editor_binder_exclusive_read(p_collection_id) e;
  if exists (select 1 from public.collection_layout_slot_species_reference sr
             where sr.layout_id = r.layout_id and sr.collection_id <> p_collection_id) then
    raise exception 'OPERATION_RESERVED_TO_OWNER' using errcode = '42501',
      hint = 'este fichário tem referências que só o titular pode alterar';
  end if;
  select * into x from public.binder_catalog_assert_eligible(p_collection_id) a;
  if x.layout_id is distinct from r.layout_id or x.is_guest then
    raise exception 'OPERATION_RESERVED_TO_OWNER' using errcode = '42501';
  end if;
  if public.binder_editor_any_foreign(r.layout_id, p_collection_id,
                                      public.binder_editor_catalog_affected(r.layout_id, p_collection_id, p_keys)) then
    raise exception 'OPERATION_RESERVED_TO_OWNER' using errcode = '42501',
      hint = 'a incorporação deslocaria conteúdo que só o titular pode mover';
  end if;
  return query
  select p.row_kind, p.step_no, p.item_key, p.card_id, p.variant_type_id, p.pos_ord, p.kind,
         p.target_page, p.target_row, p.target_column, p.end_page, p.end_row, p.end_column,
         p.anchor_page, p.anchor_row, p.anchor_column, p.pockets_moved, p.rows_moved,
         p.other_reserves_moved, p.crosses_page, p.adds_page,
         case when bf.foreign_ then null else p.barrier_page end,
         case when bf.foreign_ then null else p.barrier_row end,
         case when bf.foreign_ then null else p.barrier_column end,
         p.barrier_kind, p.outcome, p.reason, null::uuid, p.total_items,
         p.total_rows_moved, p.row_limit, p.item_limit, p.requires_cross_page,
         p.requires_add_page, p.pages_added, p.added_page_numbers, null::integer,
         null::integer, null::integer, p.plan_token
  from public.binder_catalog_plan(p_collection_id, p_keys) p
  cross join lateral (
    select p.barrier_page is not null
           and public.binder_editor_any_foreign(r.layout_id, p_collection_id,
                 array[public.binder_slot_at(r.layout_id, p.barrier_page, p.barrier_row, p.barrier_column)]) as foreign_
  ) bf;
end;
$fn$;

-- Aplicar -----------------------------------------------------------------------------------------
create function public.editor_apply_binder_catalog_reconciliation(
  p_collection_id      uuid,
  p_keys               text[],
  p_plan_token         text,
  p_confirm_cross_page boolean default false,
  p_confirm_add_page   boolean default false
)
returns table (
  outcome text, items_applied integer, reservations_created integer, reservations_upgraded integer,
  pockets_moved integer, rows_moved integer, pages_added integer, added_page_numbers integer[]
)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  r          record;
  x          record;
  st         record;
  h          record;
  v_layout   uuid;
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
  k          integer;
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  if p_collection_id is null or p_plan_token is null or p_plan_token !~ '^rc1:[0-9a-f]{64}$'
     or (p_keys is not null and (cardinality(p_keys) = 0 or array_position(p_keys, null) is not null)) then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  select * into r from public.assert_collection_binder_editor_exclusive(p_collection_id) e;
  v_layout := r.layout_id;
  if exists (select 1 from public.collection_layout_slot_species_reference sr
             where sr.layout_id = v_layout and sr.collection_id <> p_collection_id) then
    raise exception 'OPERATION_RESERVED_TO_OWNER' using errcode = '42501',
      hint = 'este fichário tem referências que só o titular pode alterar';
  end if;
  select * into x from public.binder_catalog_assert_eligible(p_collection_id) a;
  if x.layout_id is distinct from v_layout or x.owner_user_id is distinct from r.owner_user_id or x.is_guest then
    raise exception 'RECONCILE_INCONSISTENT' using errcode = 'P0001';
  end if;

  if p_keys is null then
    select array_agg(nv.item_key order by nv.pos_ord) into v_pending
    from public.binder_catalog_novelties(p_collection_id) nv where nv.is_novelty;
    if v_pending is null then
      return query select 'NOTHING_TO_DO'::text, 0, 0, 0, 0, 0, 0, '{}'::integer[];
      return;
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
      return query select 'ALREADY_APPLIED'::text, 0, 0, 0, 0, 0, 0, '{}'::integer[];
      return;
    end if;
  end if;

  -- Cabeçalho do plano: as mesmas recusas da 5296, antes de qualquer escrita.
  select * into h from public.binder_catalog_plan(p_collection_id, v_pending) p where p.row_kind = 'HEADER';
  if h.outcome = 'OVER_LIMIT' then
    raise exception 'RECONCILE_OVER_LIMIT' using errcode = '54000',
      hint = format('%s (limites: %s itens, %s linhas movidas)', h.reason, h.item_limit, h.row_limit);
  end if;
  if h.plan_token is distinct from p_plan_token then
    raise exception 'RECONCILE_PLAN_CHANGED' using errcode = '40001',
      hint = 'o fichário ou o Catálogo mudou desde a prévia — veja a prévia de novo';
  end if;
  if h.outcome = 'BLOCKED' then
    raise exception 'RECONCILE_BLOCKED' using errcode = '55000', hint = 'há um bolso fixado ou mesclado no caminho';
  elsif h.outcome = 'NEEDS_REVIEW' then
    raise exception 'RECONCILE_NEEDS_REVIEW' using errcode = '55000',
      hint = 'há novidade com carta fora da ordem ou reserva genérica ambígua — desmarque-a e resolva separadamente';
  elsif h.outcome = 'NO_ANCHOR' then
    raise exception 'RECONCILE_NO_ANCHOR' using errcode = '55000',
      hint = 'há novidade sem posição vizinha no fichário — desmarque-a';
  elsif h.outcome is distinct from 'READY' then
    raise exception 'RECONCILE_INCONSISTENT' using errcode = 'P0001';
  end if;
  if h.requires_cross_page and not coalesce(p_confirm_cross_page, false) then
    raise exception 'RECONCILE_CONFIRMATION_REQUIRED' using errcode = '55000', hint = 'CROSS_PAGE';
  end if;
  if h.requires_add_page and not coalesce(p_confirm_add_page, false) then
    raise exception 'RECONCILE_CONFIRMATION_REQUIRED' using errcode = '55000', hint = 'ADD_PAGE';
  end if;

  -- Conjunto afetado inteiro, sob as travas.
  if public.binder_editor_any_foreign(v_layout, p_collection_id,
                                      public.binder_editor_catalog_affected(v_layout, p_collection_id, v_pending)) then
    raise exception 'OPERATION_RESERVED_TO_OWNER' using errcode = '42501',
      hint = 'a incorporação deslocaria conteúdo que só o titular pode mover';
  end if;

  perform public.binder_activity_begin(v_layout, 'CATALOG_NOVELTIES_INCORPORATED', 'CATALOGO', p_collection_id);
  for st in
    select * from public.binder_catalog_plan(p_collection_id, v_pending) p
    where p.row_kind = 'ITEM'
    order by p.step_no
  loop
    if st.kind not in ('IN_PLACE', 'RESERVE_PLACED', 'SHIFT', 'UPGRADE_RESERVATION') then
      raise exception 'RECONCILE_INCONSISTENT' using errcode = 'P0001';
    end if;

    if st.kind = 'UPGRADE_RESERVATION' then
      v_target := public.binder_slot_at(v_layout, st.target_page, st.target_row, st.target_column);
      perform 1 from public.collection_layout_slot s where s.id = v_target for update;
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
      perform public.binder_activity_add_item('RESERVATION', 'INCORPORATED', st.card_id, st.variant_type_id,
                                              null, v_target, null, null, jsonb_build_object('upgrade', true));
      continue;
    end if;

    if st.adds_page then
      v_expect := case when st.kind = 'SHIFT' then st.end_page else st.target_page end;
      select ap.page_number into v_page_no from public.binder_editor_append_page(v_layout) ap;
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
        perform public.binder_activity_add_pocket_shift_items(v_chain[k], v_chain[k + 1]);
      end loop;
      v_pm := v_pm + st.pockets_moved;
      v_target := v_chain[1];
    else
      v_target := public.binder_slot_at(v_layout, st.target_page, st.target_row, st.target_column);
      if v_target is null then
        raise exception 'RECONCILE_INCONSISTENT' using errcode = 'P0001';
      end if;
      perform 1 from public.collection_layout_slot s where s.id = v_target for update;
    end if;

    if exists (select 1 from public.collection_layout_slot_expected_content e where e.slot_id = v_target)
       or (st.kind <> 'RESERVE_PLACED'
           and (exists (select 1 from public.collection_layout_slot_assignment a0 where a0.slot_id = v_target)
                or exists (select 1 from public.collection_layout_slot_image im where im.slot_id = v_target)
                or exists (select 1 from public.collection_layout_slot s where s.id = v_target and s.locked)))
       or (st.kind = 'RESERVE_PLACED'
           and not exists (select 1 from public.collection_layout_slot_assignment a0 where a0.slot_id = v_target)) then
      raise exception 'RECONCILE_INCONSISTENT' using errcode = 'P0001';
    end if;

    -- Fichário exclusivo: X é a proprietária → reserva sem coleção explícita, como no titular.
    insert into public.collection_layout_slot_expected_content
      (slot_id, card_id, card_variant_id, expected_variant_type_id, collection_id)
    values (v_target, st.card_id, null, st.variant_type_id, null);
    v_res := v_res + 1;
    perform public.binder_activity_add_reservation_item('RESERVED', v_target);
  end loop;

  if v_rows <> h.total_rows_moved or v_res + v_upg <> cardinality(v_pending)
     or exists (select 1
                from unnest(v_pending) u(k)
                left join public.binder_catalog_novelties(p_collection_id) nv on nv.item_key = u.k
                where nv.is_reserved is distinct from true) then
    raise exception 'RECONCILE_INCONSISTENT' using errcode = 'P0001';
  end if;

  insert into public.collection_layout_catalog_incorporation (layout_id, collection_id, item_key)
  select v_layout, p_collection_id, u.k
  from unnest(v_pending) u(k)
  on conflict (layout_id, collection_id, item_key) do nothing;
  get diagnostics k = row_count;
  if k <> cardinality(v_pending) then
    raise exception 'RECONCILE_INCONSISTENT' using errcode = 'P0001';
  end if;
  perform public.binder_activity_end();

  return query select 'APPLIED'::text, cardinality(v_pending), v_res, v_upg, v_pm, v_rows,
                      cardinality(v_added), v_added;
end;
$fn$;

comment on function public.binder_editor_catalog_affected(uuid, uuid, text[]) is
  'V1-13 E1-C2 (5387, interna): bolsos existentes alcançados pelo plano de novidades (destinos e trechos deslocados).';
comment on function public.editor_preview_binder_catalog_reconciliation(uuid, text[]) is
  'V1-13 E1-C2 (5387): prévia das novidades do Catálogo para o EDITOR do fichário exclusivo (plano e token da 5264); sem capacidade, layout ou barreira de terceiros.';
comment on function public.editor_apply_binder_catalog_reconciliation(uuid, text[], text, boolean, boolean) is
  'V1-13 E1-C2 (5387): EDITOR incorpora novidades do Catálogo no fichário exclusivo (espelho da 5296) só se o conjunto afetado for de X ou livre.';

revoke all on function public.binder_editor_catalog_affected(uuid, uuid, text[]) from public, anon, authenticated, service_role;
revoke all on function public.editor_preview_binder_catalog_reconciliation(uuid, text[]) from public, anon;
revoke all on function public.editor_apply_binder_catalog_reconciliation(uuid, text[], text, boolean, boolean) from public, anon;
grant execute on function public.editor_preview_binder_catalog_reconciliation(uuid, text[]) to authenticated;
grant execute on function public.editor_apply_binder_catalog_reconciliation(uuid, text[], text, boolean, boolean) to authenticated;

do $post$
declare
  f oid;
begin
  foreach f in array array[to_regprocedure('public.editor_preview_binder_catalog_reconciliation(uuid, text[])'),
                           to_regprocedure('public.editor_apply_binder_catalog_reconciliation(uuid, text[], text, boolean, boolean)')] loop
    if f is null
       or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
       or (select p.proconfig from pg_catalog.pg_proc p where p.oid = f) is distinct from array['search_path=""']
       or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not true
       or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false then
      raise exception 'POSTCHECK 5387: RPC fora do estado esperado (%)', f;
    end if;
  end loop;
  f := to_regprocedure('public.binder_editor_catalog_affected(uuid, uuid, text[])');
  if f is null or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not false then
    raise exception 'POSTCHECK 5387: ajudante interno fora do estado esperado';
  end if;
end;
$post$;

commit;
