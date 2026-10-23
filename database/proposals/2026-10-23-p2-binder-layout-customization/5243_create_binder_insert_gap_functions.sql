/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5243 - Create Binder Insert Gap Functions ("Inserir espaço")
Versão......: 1.1 (REVIEW-01: tokens incluem a identidade da reserva e a fixação)
Status......: PROPOSTO — NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-23 (P2-BINDER-LAYOUT-CUSTOMIZATION-IMPLEMENTATION-PROPOSAL-01)
Descrição...:
Abre um bolso livre antes do bolso X, empurrando X..(primeiro livre − 1)
uma posição na ordem de leitura (página → linha → coluna). Espelho exato
de web/lib/colecoes/binder-insert.ts (testes locais).

Regras (D1 ajustada, D2–D4 aprovadas):
- Bolso LIVRE: sem carta, sem reserva, sem imagem, não fixado, fora de mesclagem.
- BARREIRA: bolso fixado ou em mesclagem. O deslocamento NÃO a atravessa:
  barreira antes do primeiro livre → BLOCKED (com a posição da barreira).
- O bolso inteiro anda junto: posição da carta (UPDATE slot_id, id
  preservado — LDM-35), reserva (UPDATE slot_id) e imagem (remove+inclui o
  vínculo na mesma transação; o arquivo e o caminho são os mesmos).
- Execução do fim para o começo: cada destino está livre quando recebe —
  nenhum estado intermediário inválido, nenhuma restrição diferida.
- Primeiro livre na mesma página → SAME_PAGE. Em outra página → CROSS_PAGE,
  só com p_confirm_cross_page. Nenhum livre até o fim → NEEDS_PAGE, só com
  p_confirm_add_page (D3: inclusão de página exige confirmação explícita);
  a página é criada por add_layout_page (5125) na mesma transação.
- LIMITE OPERACIONAL: no máximo 500 linhas movidas (posições + reservas +
  imagens) por operação → OVER_LIMIT. Fundamento: é o mesmo teto por
  chamada já validado no fichário para operações em lote no mesmo
  desenho (trava do fichário + gatilhos por linha): 5129/5130/5133,
  hardening 5138–5140, validado por 5820. Acima disso a operação deixa de
  ser comparável ao que já foi medido; a confirmação do número exato fica
  na homologação (tempo de trava medido).
- Plano conferido: a prévia devolve plan_token (sha256 da cadeia); a
  execução refaz o cálculo sob trava e recusa se mudou (GAP_PLAN_CHANGED).
- Desfazer (D4): close_my_binder_gap com undo_token devolvido pela
  inserção; recusa se o estado mudou (GAP_UNDO_EXPIRED). Remove a página
  criada pela inserção somente se ela voltou a ficar inteiramente livre.

Autorização: binder_layout_lock_for_collection (5240) — proprietária ou
convidada, ACTIVE, fichário travado. Não toca alocações, cartas físicas,
progresso nem valor; só a posição no fichário.
Dependências: 5125, 5126/5235, 5232, 5238, 5239, 5240.
================================================================
*/

begin;

do $pre$
begin
  if to_regprocedure('public.binder_layout_lock_for_collection(uuid)') is null then
    raise exception 'PRECHECK 5243: aplique 5240 antes';
  end if;
  if to_regprocedure('public.add_layout_page(uuid)') is null
     or to_regprocedure('public.remove_layout_page(uuid)') is null then
    raise exception 'PRECHECK 5243: add/remove_layout_page ausentes';
  end if;
  if to_regprocedure('public.insert_my_binder_gap(uuid, uuid, text, boolean, boolean)') is not null then
    raise exception 'PRECHECK 5243: já aplicada';
  end if;
end;
$pre$;

-- 0. Interna: cadeia a partir do bolso, até o primeiro livre/barreira (inclusive) --------
create function public.binder_gap_chain(p_layout uuid, p_slot uuid)
returns table (
  ord          integer,
  slot_id      uuid,
  page_id      uuid,
  page_number  integer,
  row_index    integer,
  column_index integer,
  is_barrier   boolean,
  barrier_kind text,
  is_free      boolean,
  has_card     boolean,
  has_reserve  boolean,
  image_path   text,
  assignment_id uuid,
  reserve_sig  text      -- REVIEW-01: identidade da reserva (qual carta/variante), não só "há reserva"
)
language sql
stable
security definer
set search_path = ''
as $$
  with s as (
    select sl.id, sl.page_id, p.page_number, sl.row_index, sl.column_index, sl.locked,
           exists (select 1 from public.collection_layout_region r
                   where r.page_id = sl.page_id
                     and sl.row_index    between r.top_row     and r.top_row     + r.height - 1
                     and sl.column_index between r.left_column and r.left_column + r.width  - 1) as in_region,
           a.id as asg_id,
           (e.slot_id is not null) as has_exp,
           case when e.slot_id is null then null else md5(e::text) end as exp_sig,
           i.storage_path as img,
           (row_number() over (order by p.page_number, sl.row_index, sl.column_index))::integer as ord
    from public.collection_layout_slot sl
    join public.collection_layout_page p on p.id = sl.page_id
    left join public.collection_layout_slot_assignment a       on a.slot_id = sl.id
    left join public.collection_layout_slot_expected_content e on e.slot_id = sl.id
    left join public.collection_layout_slot_image i            on i.slot_id = sl.id
    where p.layout_id = p_layout
  ),
  m as (
    select s.*,
           (s.locked or s.in_region) as barrier,
           (not s.locked and not s.in_region and s.asg_id is null and not s.has_exp and s.img is null) as free
    from s
    where s.ord >= (select s0.ord from s s0 where s0.id = p_slot)
  ),
  stop as (
    select min(m.ord) as ord from m
    where m.ord > (select min(m0.ord) from m m0) and (m.barrier or m.free)
  )
  select m.ord, m.id, m.page_id, m.page_number, m.row_index, m.column_index,
         m.barrier, case when m.locked then 'LOCKED' when m.in_region then 'REGION' end,
         m.free, m.asg_id is not null, m.has_exp, m.img, m.asg_id, m.exp_sig
  from m
  where m.ord <= coalesce((select stop.ord from stop), 2147483647)
  order by m.ord;
$$;

revoke all on function public.binder_gap_chain(uuid, uuid)
  from public, anon, authenticated, service_role;

-- 0b. Interna: avalia a inserção (mesma regra da prévia e da execução) --------------------
create function public.binder_gap_evaluate(p_layout uuid, p_slot uuid)
returns table (
  outcome         text,   -- NOT_FOUND | ALREADY_FREE | AT_BARRIER | BLOCKED | OVER_LIMIT | SAME_PAGE | CROSS_PAGE | NEEDS_PAGE
  moved_pockets   integer,
  moved_cards     integer,
  moved_reserves  integer,
  moved_images    integer,
  rows_moved      integer,
  row_limit       integer,
  pages           integer[],
  target_slot_id  uuid,
  barrier_slot_id uuid,
  barrier_kind    text,
  barrier_page    integer,
  barrier_row     integer,
  barrier_column  integer,
  plan_token      text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  c_row_limit constant integer := 500;
  v_n      integer;
  v_first  record;
  v_last   record;
  v_chain  integer;      -- quantos bolsos andam
  v_sig    text;
begin
  row_limit := c_row_limit;
  select count(*) into v_n from public.binder_gap_chain(p_layout, p_slot);
  if v_n = 0 then
    outcome := 'NOT_FOUND'; return next; return;
  end if;
  select * into v_first from public.binder_gap_chain(p_layout, p_slot) c order by c.ord limit 1;
  select * into v_last  from public.binder_gap_chain(p_layout, p_slot) c order by c.ord desc limit 1;

  if v_first.is_barrier then
    outcome := 'AT_BARRIER';
    barrier_slot_id := v_first.slot_id; barrier_kind := v_first.barrier_kind;
    barrier_page := v_first.page_number; barrier_row := v_first.row_index; barrier_column := v_first.column_index;
    return next; return;
  end if;
  if v_first.is_free then
    outcome := 'ALREADY_FREE'; return next; return;
  end if;

  if v_n > 1 and v_last.is_barrier then
    outcome := 'BLOCKED'; v_chain := v_n - 1;
    barrier_slot_id := v_last.slot_id; barrier_kind := v_last.barrier_kind;
    barrier_page := v_last.page_number; barrier_row := v_last.row_index; barrier_column := v_last.column_index;
  elsif v_n > 1 and v_last.is_free then
    v_chain := v_n - 1;
    target_slot_id := v_last.slot_id;
    outcome := case when v_last.page_number = v_first.page_number then 'SAME_PAGE' else 'CROSS_PAGE' end;
  else
    outcome := 'NEEDS_PAGE'; v_chain := v_n;   -- nenhum livre nem barreira até o fim
  end if;

  select count(*)::integer,
         count(*) filter (where c.has_card)::integer,
         count(*) filter (where c.has_reserve)::integer,
         count(*) filter (where c.image_path is not null)::integer,
         string_agg(c.slot_id::text || ':' || coalesce(c.assignment_id::text, '-') || ':'
                    || coalesce(c.reserve_sig, '-') || ':' || coalesce(c.image_path, '-'), '|' order by c.ord)
    into moved_pockets, moved_cards, moved_reserves, moved_images, v_sig
  from public.binder_gap_chain(p_layout, p_slot) c
  where c.ord < v_first.ord + v_chain;
  rows_moved := moved_cards + moved_reserves + moved_images;

  select array_agg(distinct c.page_number order by c.page_number) into pages
  from public.binder_gap_chain(p_layout, p_slot) c
  where c.ord <= v_first.ord + v_chain - case when outcome = 'BLOCKED' then 1 else 0 end;
  if outcome = 'NEEDS_PAGE' then
    pages := pages || (select max(p.page_number) + 1 from public.collection_layout_page p where p.layout_id = p_layout);
  end if;

  if outcome in ('SAME_PAGE', 'CROSS_PAGE', 'NEEDS_PAGE') and rows_moved > c_row_limit then
    outcome := 'OVER_LIMIT';
  end if;

  plan_token := 'g1:' || encode(sha256(convert_to(
      outcome || '#' || v_sig || '#' || coalesce(target_slot_id::text, '-') || '#' || coalesce(barrier_slot_id::text, '-'),
      'UTF8')), 'hex');
  return next;
end;
$$;

revoke all on function public.binder_gap_evaluate(uuid, uuid)
  from public, anon, authenticated, service_role;

-- 0c. Interna: move o conteúdo de um bolso para outro LIVRE (o bolso inteiro) ---------------
create function public.binder_gap_move_pocket(p_from uuid, p_to uuid)
returns integer   -- linhas movidas
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_n   integer := 0;
  v_c   integer;
begin
  update public.collection_layout_slot_assignment a set slot_id = p_to where a.slot_id = p_from;
  get diagnostics v_c = row_count; v_n := v_n + v_c;
  update public.collection_layout_slot_expected_content e set slot_id = p_to where e.slot_id = p_from;
  get diagnostics v_c = row_count; v_n := v_n + v_c;
  -- Imagem: slot_id é imutável (5232) → o vínculo sai e entra de novo, na mesma
  -- transação, com o MESMO arquivo. Nenhuma outra sessão vê o intervalo sem vínculo.
  with d as (
    delete from public.collection_layout_slot_image i where i.slot_id = p_from
    returning i.owner_user_id, i.storage_path, i.focal_y
  )
  insert into public.collection_layout_slot_image (slot_id, owner_user_id, storage_path, focal_y)
  select p_to, d.owner_user_id, d.storage_path, d.focal_y from d;
  get diagnostics v_c = row_count; v_n := v_n + v_c;
  return v_n;
end;
$$;

revoke all on function public.binder_gap_move_pocket(uuid, uuid)
  from public, anon, authenticated, service_role;

-- 0d. Interna: token de desfazer (estado de gap..end depois da inserção) -------------------
create function public.binder_gap_undo_token(p_layout uuid, p_gap uuid, p_end uuid, p_added_page uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  with s as (
    select sl.id, (row_number() over (order by p.page_number, sl.row_index, sl.column_index))::integer as ord,
           a.id as asg_id,
           case when e.slot_id is null then '-' else md5(e::text) end as exp_sig,   -- REVIEW-01
           sl.locked,
           i.storage_path as img
    from public.collection_layout_slot sl
    join public.collection_layout_page p on p.id = sl.page_id
    left join public.collection_layout_slot_assignment a       on a.slot_id = sl.id
    left join public.collection_layout_slot_expected_content e on e.slot_id = sl.id
    left join public.collection_layout_slot_image i            on i.slot_id = sl.id
    where p.layout_id = p_layout
  )
  select 'u1:' || encode(sha256(convert_to(
           coalesce(string_agg(s.id::text || ':' || coalesce(s.asg_id::text, '-') || ':' || s.exp_sig
                               || ':' || s.locked::text || ':' || coalesce(s.img, '-'), '|' order by s.ord), '')
           || '#' || coalesce(p_added_page::text, '-'), 'UTF8')), 'hex')
  from s
  where s.ord between (select s1.ord from s s1 where s1.id = p_gap)
                  and (select s2.ord from s s2 where s2.id = p_end);
$$;

revoke all on function public.binder_gap_undo_token(uuid, uuid, uuid, uuid)
  from public, anon, authenticated, service_role;

-- 1. Prévia -----------------------------------------------------------------------------------
create function public.preview_my_binder_insert_gap(p_collection_id uuid, p_slot_id uuid)
returns table (
  outcome         text,
  moved_pockets   integer,
  moved_cards     integer,
  moved_reserves  integer,
  moved_images    integer,
  rows_moved      integer,
  row_limit       integer,
  pages           integer[],
  target_slot_id  uuid,
  barrier_slot_id uuid,
  barrier_kind    text,
  barrier_page    integer,
  barrier_row     integer,
  barrier_column  integer,
  plan_token      text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_layout uuid;
begin
  if p_slot_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  v_layout := public.binder_slot_image_resolve_layout(p_collection_id);   -- dono, sem enumerar
  if v_layout is null then
    raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
  end if;
  return query select * from public.binder_gap_evaluate(v_layout, p_slot_id);
end;
$$;

comment on function public.preview_my_binder_insert_gap(uuid, uuid) is
  'Fichário Digital (5243): prévia de "Inserir espaço" — quantos bolsos andam, páginas envolvidas, barreira (fixado/mesclagem) ou necessidade de página nova, e plan_token para a execução. Não grava nada.';

revoke all on function public.preview_my_binder_insert_gap(uuid, uuid) from public, anon;
grant execute on function public.preview_my_binder_insert_gap(uuid, uuid) to authenticated;

-- 2. Inserir -----------------------------------------------------------------------------------
create function public.insert_my_binder_gap(
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
as $$
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

  v_layout := public.binder_layout_lock_for_collection(p_collection_id);   -- fichário travado
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

  -- Trava os bolsos envolvidos em ordem determinística (anti-deadlock).
  perform 1 from public.collection_layout_slot s
  where s.id = any (v_chain || v_target)
  order by s.id
  for update;

  -- Do fim para o começo: cada destino já está livre.
  for i in reverse cardinality(v_chain)..1 loop
    v_rows := v_rows + public.binder_gap_move_pocket(v_chain[i], v_dest[i]);
  end loop;

  if v_rows <> e.rows_moved
     or exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = p_slot_id)
     or exists (select 1 from public.collection_layout_slot_expected_content x where x.slot_id = p_slot_id)
     or exists (select 1 from public.collection_layout_slot_image im where im.slot_id = p_slot_id) then
    raise exception 'GAP_INCONSISTENT';
  end if;

  outcome       := 'INSERTED';
  gap_slot_id   := p_slot_id;
  end_slot_id   := v_target;
  added_page_id := v_added;
  moved_pockets := e.moved_pockets;
  rows_moved    := v_rows;
  pages         := e.pages;
  undo_token    := public.binder_gap_undo_token(v_layout, p_slot_id, v_target, v_added);
  return next;
end;
$$;

comment on function public.insert_my_binder_gap(uuid, uuid, text, boolean, boolean) is
  'Fichário Digital (5243): abre um bolso livre antes do bolso indicado, empurrando o conteúdo (posição, reserva, imagem) até o primeiro bolso livre. Nunca atravessa bolso fixado ou mesclagem. Página nova só com p_confirm_add_page; outra página só com p_confirm_cross_page. Limite de 500 itens. Devolve undo_token.';

revoke all on function public.insert_my_binder_gap(uuid, uuid, text, boolean, boolean) from public, anon;
grant execute on function public.insert_my_binder_gap(uuid, uuid, text, boolean, boolean) to authenticated;

-- 3. Desfazer ------------------------------------------------------------------------------------
create function public.close_my_binder_gap(
  p_collection_id uuid,
  p_gap_slot_id   uuid,
  p_end_slot_id   uuid,
  p_undo_token    text,
  p_added_page_id uuid default null
)
returns table (
  outcome       text,      -- CLOSED
  moved_pockets integer,
  rows_moved    integer,
  page_removed  boolean
)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
#variable_conflict use_column
declare
  c_row_limit constant integer := 500;
  v_layout uuid;
  v_chain  uuid[];
  v_rows   integer := 0;
  v_count  integer;
  i        integer;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_gap_slot_id is null or p_end_slot_id is null
     or p_undo_token is null or p_undo_token !~ '^u1:[0-9a-f]{64}$' then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  v_layout := public.binder_layout_lock_for_collection(p_collection_id);

  if public.binder_gap_undo_token(v_layout, p_gap_slot_id, p_end_slot_id, p_added_page_id)
       is distinct from p_undo_token then
    raise exception 'GAP_UNDO_EXPIRED' using errcode = '40001',
      hint = 'o fichário mudou desde que o espaço foi aberto';
  end if;

  -- Cadeia gap..end em ordem de leitura; nenhuma barreira, gap livre.
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
    where s.ord between (select s1.ord from s s1 where s1.id = p_gap_slot_id)
                    and (select s2.ord from s s2 where s2.id = p_end_slot_id)
  )
  select array_agg(c.id order by c.ord), count(*) filter (where c.locked or c.in_region)
    into v_chain, v_count
  from c;
  if v_chain is null or cardinality(v_chain) < 2 or v_count > 0 then
    raise exception 'GAP_UNDO_EXPIRED' using errcode = '40001';
  end if;

  perform 1 from public.collection_layout_slot s where s.id = any (v_chain) order by s.id for update;

  -- Do começo para o fim: cada destino (o anterior) já está livre.
  for i in 2..cardinality(v_chain) loop
    v_rows := v_rows + public.binder_gap_move_pocket(v_chain[i], v_chain[i - 1]);
    if v_rows > c_row_limit then
      raise exception 'GAP_OVER_LIMIT' using errcode = '54000';
    end if;
  end loop;

  page_removed := false;
  if p_added_page_id is not null then
    -- Só a página criada pela inserção, se ainda for a última e estiver inteiramente livre.
    if exists (select 1 from public.collection_layout_page p
               where p.id = p_added_page_id and p.layout_id = v_layout
                 and p.page_number = (select max(p2.page_number) from public.collection_layout_page p2 where p2.layout_id = v_layout))
       and not exists (
         select 1 from public.collection_layout_slot s
         where s.page_id = p_added_page_id
           and (s.locked
                or exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = s.id)
                or exists (select 1 from public.collection_layout_slot_expected_content x where x.slot_id = s.id)
                or exists (select 1 from public.collection_layout_slot_image im where im.slot_id = s.id)))
       and not exists (select 1 from public.collection_layout_region r where r.page_id = p_added_page_id) then
      perform public.remove_layout_page(p_added_page_id);
      page_removed := true;
    end if;
  end if;

  outcome       := 'CLOSED';
  moved_pockets := cardinality(v_chain) - 1;
  rows_moved    := v_rows;
  return next;
end;
$$;

comment on function public.close_my_binder_gap(uuid, uuid, uuid, text, uuid) is
  'Fichário Digital (5243): desfaz "Inserir espaço" — puxa de volta o conteúdo de gap+1..end, se o estado ainda é o deixado pela inserção (undo_token). Remove a página criada pela inserção apenas se continuar a última e inteiramente livre.';

revoke all on function public.close_my_binder_gap(uuid, uuid, uuid, text, uuid) from public, anon;
grant execute on function public.close_my_binder_gap(uuid, uuid, uuid, text, uuid) to authenticated;

commit;

/*
Resultado esperado: 3 RPCs (authenticated) + 4 internas sem EXECUTE para clientes.
Como validar: LIVE_90 POST-4 (grants, prosecdef, search_path vazio). A prova
comportamental é a homologação pelo app (README §5), com baseline de patrimônio.
*/
