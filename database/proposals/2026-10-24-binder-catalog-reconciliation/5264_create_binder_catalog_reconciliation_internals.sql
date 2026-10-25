/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5264 - Fichário Digital × Catálogo: funções internas da
              reconciliação de novidades (MASTER_SET)
Versão......: 1.4 (2026-10-24, A7-FINAL-CORRECTION-01: só marco ativo —
              ended_xact NULL.) Anterior 1.3 (2026-10-24, BINDER-CATALOG-RECONCILIATION-A7-CORRECTION-01:
              marco lido de collection_layout_catalog_marker (5263) —
              persistente por (fichário, coleção), preservado em transferência;
              sem marco → MARKER_MISSING, nunca outra data.)
              Anterior 1.2 (2026-10-24, BINDER-CATALOG-RECONCILIATION-W5-FOUNDATION-01:
              W5 — novidades já incorporadas (registro 5263) não são mais
              oferecidas, mesmo com a reserva liberada; renumerada de 5263
              para 5264.) Anterior 1.1 (AUDIT-CORRECTION-01): W1 token sem
              TimeZone/DateStyle; W3 reserva genérica → específica; W4 limites
              documentados; W6 carta fora da ordem → revisão.
Status......: PROPOSTA — NÃO EXECUTADA. Sem autorização para o LIVE.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-24

Descrição...:
Funções internas (sem EXECUTE para clientes) usadas pelas RPCs 5265/5266.
Nenhuma tabela, gatilho, política ou função existente é criada/alterada.
Lê (nunca escreve) o registro de incorporações e o marco de participação da 5263.

  binder_catalog_context(collection)        — elegibilidade e marco temporal
  binder_catalog_assert_eligible(collection) — o mesmo, falhando com o erro público
  binder_catalog_positions(set, finishes)   — posições do Master Set na MESMA
                                              ordem do planejamento 5224 + nascimento
  binder_catalog_novelties(collection)      — posições nascidas após o marco
  binder_catalog_plan(collection, keys)     — simulação completa (somente leitura)

Regras (decisões de Fabrício, rodadas 02/04 e PROPOSAL-01):
- Só MASTER_SET. Pokédex nunca entra: coleção não-MASTER_SET → NOT_MASTER_SET;
  fichário de dona Pokédex (REFERENCE_POSITION) ou com qualquer referência de
  espécie → não elegível. Referências da Pokédex jamais são lidas para decisão
  além de "existe alguma?" e jamais são escritas.
- Novidade = posição atual de master_set_positions (5187) sem reserva da
  coleção no fichário, AINDA NÃO INCORPORADA (sem linha da coleção/fichário
  em collection_layout_catalog_incorporation, 5263 — W5) e com nascimento
  posterior ao marco:
    nascimento = greatest(card.created_at, menor created_at das variantes
                 ATIVAS que geram a posição);
    marco      = collection_layout_catalog_marker.marker_at (5263, A7): início
                 da participação contínua da coleção no fichário, igual para
                 dona e convidada e preservado em transferência (5254). Antes
                 da A7 era derivado do papel atual (criação do fichário /
                 entrada da convidada), o que mudava na transferência.
  Reserva liberada de posição antiga NÃO volta (regra 5).
  LIMITES DA DETECÇÃO TEMPORAL (ajuste 1 / W4) — não são novidade:
    - variante reativada (card_variant.is_active false→true; created_at antigo);
    - carta reativada (card.is_active false→true; created_at antigo);
    - carta reatribuída a outro Set por mesclagem/edição editorial;
    - acabamento acrescentado depois ao objetivo da coleção (decisão do
      usuário, não do Catálogo);
    - corrida no marco: created_at registra o INÍCIO da transação que criou a
      variante; importação iniciada antes da montagem e confirmada depois fica
      com created_at < marco e nunca é detectada.
    Essas posições continuam visíveis como "Falta" na coleção e podem ser
    reservadas manualmente.
  W5 (decisão de Fabrício, estrutura 5263): uma novidade incorporada cuja
    reserva é liberada depois NÃO volta a ser oferecida (is_incorporated). O
    registro é por (fichário, coleção): desassociar e reassociar a convidada
    cria marco novo, posterior a toda incorporação antiga, que fica inerte.
- W3 (decisão de Fabrício): carta cuja posição genérica "carta:*" deixou de
  existir (ganhou acabamento) e que tem reserva genérica desta coleção no
  fichário → UPGRADE_RESERVATION: a reserva existente recebe o acabamento no
  próprio bolso (nada anda, nada duplica). Correspondência não inequívoca
  (mais de uma reserva genérica da carta, ou mais de uma novidade tipada da
  carta) → REVIEW_REQUIRED (operação recusada; resolver separadamente).
- W6 (decisão de Fabrício): exemplar da novidade já colocado no fichário só
  vira reserva se estiver no bolso natural (RESERVE_PLACED). Em qualquer outro
  bolso a carta fica onde está e o item vai para revisão (OUT_OF_ORDER,
  operação recusada se selecionado).
- Ordem (ajuste 2): binder_catalog_positions usa exatamente a chave de
  ordenação de collection_binder_plan (5224/5251, ramo MASTER_SET):
  collector_order, collector_number, card.id, (variant_type_id is null),
  coalesce(display_order, 2147483647), variant_type_id. Prova: harness 1.1/1.2
  e static check S9.
- Âncora = posição anterior (na ordem acima) materializada no fichário para a
  coleção (reserva da coleção — preferida — ou exemplar da coleção colocado).
  Sem anterior, a seguinte (a novidade entra antes dela). Sem nenhuma: NO_ANCHOR.
  Bolso natural = bolso seguinte à âncora na ordem de leitura.
- Bolso natural livre → IN_PLACE. Ocupado → SHIFT com a regra exata da 5243
  (cadeia até o 1º bolso livre; barreira = fixado ou mesclado → BLOCKED;
  nenhum livre até o fim → página nova). Exemplar da novidade já colocado em
  bolso natural sem reserva → RESERVE_PLACED (W6, acima).
- Várias novidades: ordem crescente do Master Set, âncora recalculada sobre o
  estado simulado.
- Limites (ajuste 4), contagem sem ambiguidade:
    item_limit = 100 novidades selecionadas por operação;
    row_limit  = 500 linhas MOVIDAS no total = soma, sobre todos os SHIFT, de
                 (posições de exemplar + reservas de qualquer coleção + imagens
                 de bolso) dos bolsos que andam — a mesma unidade de rows_moved
                 da 5243. Reservas novas e páginas criadas não entram na soma.
- plan_token (ajuste 6) = sha256 de: versão, coleção, fichário, dona, marco
  (epoch — W1), acabamentos, grade, maior página e nº de bolsos, assinatura de
  TODOS os bolsos (id, fixado, mesclado, posição+exemplar, identidade da
  reserva: carta/variante/acabamento/coleção — sem datas, W1 — e imagem), assinatura da lista ordenada de posições do objetivo, seleção
  resolvida e todos os passos simulados. Qualquer mudança que possa alterar o
  resultado muda o token (superconjunto conservador).
================================================================
*/

begin;

do $pre$
begin
  if to_regprocedure('public.master_set_positions(uuid, uuid[])') is null
     or to_regprocedure('public.binder_gap_move_pocket(uuid, uuid)') is null
     or to_regprocedure('public.binder_layout_lock_for_collection(uuid)') is null
     or to_regprocedure('public.binder_slot_image_resolve_layout(uuid)') is null
     or to_regprocedure('public.add_layout_page(uuid)') is null then
    raise exception 'PRECHECK 5264: dependências ausentes (5187, 5240, 5243, 5234, 5125)';
  end if;
  if to_regclass('public.collection_layout_slot_species_reference') is null
     or to_regclass('public.collection_layout_guest') is null then
    raise exception 'PRECHECK 5264: tabelas 5229/5257 ausentes';
  end if;
  if to_regclass('public.collection_layout_catalog_incorporation') is null
     or to_regclass('public.collection_layout_catalog_marker') is null then
    raise exception 'PRECHECK 5264: aplique 5263 antes';
  end if;
  if to_regprocedure('public.binder_catalog_plan(uuid, text[])') is not null then
    raise exception 'PRECHECK 5264: já aplicada';
  end if;
end;
$pre$;

-- 1. Contexto e elegibilidade ------------------------------------------------------------------
create function public.binder_catalog_context(p_collection_id uuid)
returns table (
  collection_id       uuid,
  owner_user_id       uuid,
  layout_id           uuid,
  owner_collection_id uuid,
  is_guest            boolean,
  marker_at           timestamptz,
  card_set_id         uuid,
  finish_type_ids     uuid[],
  grid_rows           integer,
  grid_columns        integer,
  eligible            boolean,
  reason              text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_mode     text;
  v_policy   text;
  v_status   text;
  v_o_user   uuid;
  v_o_policy text;
  v_o_status text;
  v_layout   uuid;   -- variáveis locais: nada de nome não qualificado igual a coluna
  v_owner    uuid;
begin
  collection_id := p_collection_id;
  eligible := false;

  select c.owner_user_id, c.mode::text, c.completion_policy::text, c.lifecycle_status::text
    into owner_user_id, v_mode, v_policy, v_status
  from public.collection c where c.id = p_collection_id;
  if not found then
    reason := 'COLLECTION_NOT_FOUND'; return next; return;
  end if;
  if v_mode = 'OPEN_CURATION' or v_policy is distinct from 'MASTER_SET' then
    reason := 'NOT_MASTER_SET'; return next; return;
  end if;

  select l.id, l.collection_id, l.grid_rows, l.grid_columns
    into v_layout, v_owner, grid_rows, grid_columns
  from public.collection_layout l where l.collection_id = p_collection_id;
  if found then
    is_guest := false;
  else
    select g.layout_id into v_layout
    from public.collection_layout_guest g where g.collection_id = p_collection_id;
    if v_layout is null then
      reason := 'BINDER_NOT_FOUND'; return next; return;
    end if;
    is_guest := true;
    select l.collection_id, l.grid_rows, l.grid_columns
      into v_owner, grid_rows, grid_columns
    from public.collection_layout l where l.id = v_layout;
  end if;
  layout_id := v_layout;
  owner_collection_id := v_owner;

  -- A7: marco persistente da participação (5263); ausente → MARKER_MISSING (fail-closed)
  select m.marker_at into marker_at
  from public.collection_layout_catalog_marker m
  where m.layout_id = v_layout and m.collection_id = p_collection_id
    and m.ended_xact is null;   -- só participação em curso (5263 v2.1)

  select c.owner_user_id, c.completion_policy::text, c.lifecycle_status::text
    into v_o_user, v_o_policy, v_o_status
  from public.collection c where c.id = v_owner;

  select ccsr.card_set_id into card_set_id
  from public.collection_reference cr
  join public.collection_card_set_reference ccsr on ccsr.collection_reference_id = cr.id
  where cr.collection_id = p_collection_id;

  select coalesce(array_agg(f.variant_type_id order by f.variant_type_id), '{}')
    into finish_type_ids
  from public.collection_master_set_finish f
  where f.collection_id = p_collection_id;

  -- Ajuste 5: invariante de propriedade (5229: convidada do mesmo dono).
  if v_o_user is distinct from owner_user_id then
    reason := 'OWNERSHIP_MISMATCH';
  elsif v_o_policy = 'REFERENCE_POSITION' then
    reason := 'BINDER_OWNER_POKEDEX';
  elsif exists (select 1 from public.collection_layout_slot_species_reference r
                where r.layout_id = v_layout) then
    reason := 'SPECIES_REFERENCES_PRESENT';
  elsif card_set_id is null or cardinality(finish_type_ids) = 0 then
    reason := 'COLLECTION_REFERENCE_MISSING';
  elsif v_status <> 'ACTIVE' or v_o_status is distinct from 'ACTIVE' then
    reason := 'COLLECTION_ARCHIVED';
  elsif marker_at is null then
    reason := 'MARKER_MISSING';
  else
    eligible := true;
  end if;
  return next;
end;
$$;

revoke all on function public.binder_catalog_context(uuid)
  from public, anon, authenticated, service_role;

-- 1b. O mesmo, falhando com o erro público ------------------------------------------------------
create function public.binder_catalog_assert_eligible(p_collection_id uuid)
returns table (
  collection_id       uuid,
  owner_user_id       uuid,
  layout_id           uuid,
  owner_collection_id uuid,
  is_guest            boolean,
  marker_at           timestamptz,
  card_set_id         uuid,
  finish_type_ids     uuid[],
  grid_rows           integer,
  grid_columns        integer,
  eligible            boolean,
  reason              text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v record;
begin
  select * into v from public.binder_catalog_context(p_collection_id);
  if v.reason = 'COLLECTION_NOT_FOUND' then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  elsif v.reason = 'NOT_MASTER_SET' then
    raise exception 'NOT_MASTER_SET' using errcode = '22023',
      hint = 'a incorporação de novidades do Catálogo vale só para coleções Master Set';
  elsif v.reason = 'BINDER_NOT_FOUND' then
    raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
  elsif v.reason = 'COLLECTION_REFERENCE_MISSING' then
    raise exception 'COLLECTION_REFERENCE_MISSING' using errcode = 'P0001';
  elsif v.reason = 'COLLECTION_ARCHIVED' then
    raise exception 'COLLECTION_ARCHIVED' using errcode = '55000';
  elsif not coalesce(v.eligible, false) then
    raise exception 'BINDER_NOT_ELIGIBLE' using errcode = '22023', hint = v.reason;
  end if;
  return query select * from public.binder_catalog_context(p_collection_id);
end;
$$;

revoke all on function public.binder_catalog_assert_eligible(uuid)
  from public, anon, authenticated, service_role;

-- 2. Posições do Master Set (ordem idêntica à 5224) + nascimento ---------------------------------
create function public.binder_catalog_positions(p_card_set_id uuid, p_variant_type_ids uuid[])
returns table (
  pos_key         text,
  card_id         uuid,
  variant_type_id uuid,
  pos_ord         integer,
  born_at         timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select m.card_id::text || ':' || coalesce(m.variant_type_id::text, '*'),
         m.card_id,
         m.variant_type_id,
         (row_number() over (order by c.collector_order, c.collector_number, c.id,
                                      (m.variant_type_id is null),
                                      coalesce(t.display_order, 2147483647),
                                      m.variant_type_id))::integer,
         greatest(c.created_at,
                  (select min(cv.created_at) from public.card_variant cv
                    where cv.card_id = m.card_id and cv.is_active
                      and (m.variant_type_id is null or cv.variant_type_id = m.variant_type_id)))
  from public.master_set_positions(p_card_set_id, p_variant_type_ids) m
  join public.card c on c.id = m.card_id
  left join public.card_variant_type t on t.id = m.variant_type_id
$$;

revoke all on function public.binder_catalog_positions(uuid, uuid[])
  from public, anon, authenticated, service_role;

-- 3. Novidades (e posições pós-marco já reservadas, para idempotência) --------------------------
create function public.binder_catalog_novelties(p_collection_id uuid)
returns table (
  item_key        text,
  card_id         uuid,
  variant_type_id uuid,
  pos_ord         integer,
  born_at         timestamptz,
  is_reserved     boolean,
  is_novelty      boolean,       -- sem reserva da coleção E ainda não incorporada (W5)
  is_incorporated boolean        -- W5: já incorporada por esta coleção neste fichário (5263)
)
language sql
stable
security definer
set search_path = ''
as $$
  with ctx as (
    select x.* from public.binder_catalog_context(p_collection_id) x where x.eligible
  ),
  pos as (
    select p.* from ctx cross join lateral public.binder_catalog_positions(ctx.card_set_id, ctx.finish_type_ids) p
  ),
  res as (
    select distinct e.card_id::text || ':' || coalesce(e.expected_variant_type_id::text, ecv.variant_type_id::text, '*') as k
    from ctx
    join public.collection_layout_page pg on pg.layout_id = ctx.layout_id
    join public.collection_layout_slot s on s.page_id = pg.id
    join public.collection_layout_slot_expected_content e on e.slot_id = s.id
    left join public.card_variant ecv on ecv.id = e.card_variant_id
    where coalesce(e.collection_id, ctx.owner_collection_id) = ctx.collection_id
  ),
  inc as (   -- W5: registro de incorporações (5263); PK cobre (layout_id, collection_id)
    select i.item_key as k
    from ctx
    join public.collection_layout_catalog_incorporation i
      on i.layout_id = ctx.layout_id and i.collection_id = ctx.collection_id
  )
  select pos.pos_key, pos.card_id, pos.variant_type_id, pos.pos_ord, pos.born_at,
         exists (select 1 from res where res.k = pos.pos_key),
         not exists (select 1 from res where res.k = pos.pos_key)
           and not exists (select 1 from inc where inc.k = pos.pos_key),
         exists (select 1 from inc where inc.k = pos.pos_key)
  from pos cross join ctx
  where pos.born_at > ctx.marker_at
$$;

revoke all on function public.binder_catalog_novelties(uuid)
  from public, anon, authenticated, service_role;

-- 4. Plano (simulação completa, somente leitura) -------------------------------------------------
create function public.binder_catalog_plan(p_collection_id uuid, p_keys text[])
returns table (
  row_kind             text,      -- HEADER | ITEM
  step_no              integer,
  item_key             text,
  card_id              uuid,
  variant_type_id      uuid,
  pos_ord              integer,
  kind                 text,      -- IN_PLACE | RESERVE_PLACED | SHIFT | UPGRADE_RESERVATION | BLOCKED |
                                  -- REVIEW_REQUIRED | OUT_OF_ORDER | NO_ANCHOR | NOT_EVALUATED
  target_page          integer,
  target_row           integer,
  target_column        integer,
  end_page             integer,
  end_row              integer,
  end_column           integer,
  anchor_page          integer,
  anchor_row           integer,
  anchor_column        integer,
  pockets_moved        integer,
  rows_moved           integer,
  other_reserves_moved integer,
  crosses_page         boolean,
  adds_page            boolean,
  barrier_page         integer,
  barrier_row          integer,
  barrier_column       integer,
  barrier_kind         text,      -- LOCKED | REGION | PLACED_OUT_OF_ORDER (W6) | GENERIC_RESERVATION (W3)
  outcome              text,      -- HEADER: READY | BLOCKED | NEEDS_REVIEW | NO_ANCHOR | OVER_LIMIT | NOTHING_TO_DO | NOT_ELIGIBLE
  reason               text,      -- NOT_ELIGIBLE: motivo; OVER_LIMIT: ITEM_LIMIT | ROW_LIMIT
  layout_id            uuid,
  total_items          integer,
  total_rows_moved     integer,
  row_limit            integer,
  item_limit           integer,
  requires_cross_page  boolean,
  requires_add_page    boolean,
  pages_added          integer,
  added_page_numbers   integer[],
  capacity_before      integer,
  capacity_after       integer,
  free_pockets_after   integer,
  plan_token           text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  c_version    constant text := 'rc1-r1';   -- revisão AUDIT-CORRECTION-01
  c_row_limit  constant integer := 500;
  c_item_limit constant integer := 100;
  x record;
  -- bolsos em ordem de leitura (índice fixo; o conteúdo anda)
  s_id  uuid[];  s_pg integer[]; s_rw integer[]; s_cl integer[]; s_bar boolean[]; s_bk text[];
  c_asg boolean[]; c_res boolean[]; c_img boolean[]; c_rkey text[]; c_roth boolean[]; c_pk1 text[]; c_pk2 text[];
  n integer; n0 integer; v_maxpage integer; v_maxpage0 integer;
  v_state text; v_pos text; v_ordmap jsonb;
  -- seleção
  sel_key text[]; sel_card uuid[]; sel_vt uuid[]; sel_ord integer[]; v_cnt integer;
  -- passos
  st_kind text[] := '{}'; st_t integer[] := '{}'; st_e integer[] := '{}'; st_a integer[] := '{}';
  st_b integer[] := '{}'; st_pm integer[] := '{}'; st_rows integer[] := '{}'; st_oth integer[] := '{}';
  st_cross boolean[] := '{}'; st_add boolean[] := '{}'; st_bk text[] := '{}';
  v_steps text := '';
  v_total_rows integer := 0; v_pages_added integer := 0; v_added integer[] := '{}';
  v_blocked boolean := false; v_no_anchor boolean := false; v_review boolean := false;
  v_tnov jsonb; v_star integer; v_pl integer; v_bkind text;
  v_outcome text; v_reason text; v_free integer; v_token text;
  q integer; k integer; i integer; j integer; b integer; a integer; m integer; r integer; cc integer;
  v_key text; v_o integer; v_kind text; v_rows integer; v_oth integer; v_add boolean;
  v_best integer; v_best_ord integer; v_best_res boolean; v_here_res boolean;
begin
  select * into x from public.binder_catalog_context(p_collection_id);

  row_kind := 'HEADER'; row_limit := c_row_limit; item_limit := c_item_limit; layout_id := x.layout_id;
  if not coalesce(x.eligible, false) then
    outcome := 'NOT_ELIGIBLE'; reason := x.reason; total_items := 0;
    return next; return;
  end if;

  -- Bolsos (estado inicial) ---------------------------------------------------------------------
  select array_agg(z.id order by z.o), array_agg(z.page_number order by z.o), array_agg(z.row_index order by z.o),
         array_agg(z.column_index order by z.o), array_agg(z.bar order by z.o), array_agg(z.bk order by z.o),
         array_agg(z.asg order by z.o), array_agg(z.res order by z.o), array_agg(z.img order by z.o),
         array_agg(z.rkey order by z.o), array_agg(z.roth order by z.o), array_agg(z.pk1 order by z.o),
         array_agg(z.pk2 order by z.o),
         md5(coalesce(string_agg(z.sig, '|' order by z.o), ''))
    into s_id, s_pg, s_rw, s_cl, s_bar, s_bk, c_asg, c_res, c_img, c_rkey, c_roth, c_pk1, c_pk2, v_state
  from (
    select sl.id, p.page_number, sl.row_index, sl.column_index,
           (row_number() over (order by p.page_number, sl.row_index, sl.column_index))::integer as o,
           (sl.locked or rg.in_region) as bar,
           case when sl.locked then 'LOCKED' when rg.in_region then 'REGION' end as bk,
           (a0.id is not null) as asg,
           (e.slot_id is not null) as res,
           (im.slot_id is not null) as img,
           case when e.slot_id is not null and coalesce(e.collection_id, x.owner_collection_id) = p_collection_id
                then e.card_id::text || ':' || coalesce(e.expected_variant_type_id::text, ecv.variant_type_id::text, '*')
           end as rkey,
           (e.slot_id is not null and coalesce(e.collection_id, x.owner_collection_id) <> p_collection_id) as roth,
           case when a0.id is not null and own.mine and pcv.variant_type_id is not null
                then pcv.card_id::text || ':' || pcv.variant_type_id::text end as pk1,
           case when a0.id is not null and own.mine then pcv.card_id::text || ':*' end as pk2,
           sl.id::text || ':' || sl.locked::text || ':' || rg.in_region::text || ':'
             || coalesce(a0.id::text, '-') || ':' || coalesce(a0.physical_card_id::text, '-') || ':'
             -- W1: só colunas de identidade da reserva (sem datas) → independe de TimeZone/DateStyle
             || case when e.slot_id is null then '-'
                     else e.card_id::text || '/' || coalesce(e.card_variant_id::text, '-') || '/'
                          || coalesce(e.expected_variant_type_id::text, '-') || '/' || coalesce(e.collection_id::text, '-') end || ':'
             || coalesce(im.storage_path, '-') as sig
    from public.collection_layout_slot sl
    join public.collection_layout_page p on p.id = sl.page_id
    cross join lateral (
      select exists (select 1 from public.collection_layout_region rr
                     where rr.page_id = sl.page_id
                       and sl.row_index    between rr.top_row     and rr.top_row     + rr.height - 1
                       and sl.column_index between rr.left_column and rr.left_column + rr.width  - 1) as in_region
    ) rg
    left join public.collection_layout_slot_assignment a0 on a0.slot_id = sl.id
    left join public.physical_card pc on pc.id = a0.physical_card_id
    left join public.card_variant pcv on pcv.id = pc.card_variant_id
    left join public.collection_layout_slot_expected_content e on e.slot_id = sl.id
    left join public.card_variant ecv on ecv.id = e.card_variant_id
    left join public.collection_layout_slot_image im on im.slot_id = sl.id
    cross join lateral (
      -- Exemplar "desta coleção": alocado a ela; ou, sendo ela a dona, não
      -- alocado a nenhuma participante do fichário (posição é do exemplar, 5249).
      select (a0.id is not null) and (
               exists (select 1 from public.collection_allocation ca
                       where ca.physical_card_id = a0.physical_card_id and ca.collection_id = p_collection_id)
               or (p_collection_id = x.owner_collection_id
                   and not exists (select 1 from public.collection_allocation ca
                                   where ca.physical_card_id = a0.physical_card_id
                                     and (ca.collection_id = x.owner_collection_id
                                          or ca.collection_id in (select g.collection_id from public.collection_layout_guest g
                                                                  where g.layout_id = x.layout_id))))
             ) as mine
    ) own
    where p.layout_id = x.layout_id
  ) z;

  n := coalesce(cardinality(s_id), 0);
  n0 := n;
  select coalesce(max(p.page_number), 0) into v_maxpage
  from public.collection_layout_page p where p.layout_id = x.layout_id;
  v_maxpage0 := v_maxpage;
  capacity_before := n0;

  -- Posições do objetivo ---------------------------------------------------------------------------
  select coalesce(jsonb_object_agg(p.pos_key, p.pos_ord), '{}'::jsonb),
         md5(coalesce(string_agg(p.pos_key, '|' order by p.pos_ord), ''))
    into v_ordmap, v_pos
  from public.binder_catalog_positions(x.card_set_id, x.finish_type_ids) p;

  -- Seleção ----------------------------------------------------------------------------------------
  if p_keys is not null then
    if cardinality(p_keys) = 0 or array_position(p_keys, null) is not null then
      raise exception 'INVALID_ARGUMENT' using errcode = '22023';
    end if;
    if exists (select 1
               from (select distinct u.k from unnest(p_keys) u(k)) d
               left join (select nv.item_key from public.binder_catalog_novelties(p_collection_id) nv
                          where nv.is_novelty) nv on nv.item_key = d.k
               where nv.item_key is null) then
      raise exception 'SELECTION_INVALID' using errcode = '22023',
        hint = 'há itens que não são novidades pendentes desta coleção';
    end if;
  end if;

  select array_agg(nv.item_key order by nv.pos_ord), array_agg(nv.card_id order by nv.pos_ord),
         array_agg(nv.variant_type_id order by nv.pos_ord), array_agg(nv.pos_ord order by nv.pos_ord)
    into sel_key, sel_card, sel_vt, sel_ord
  from public.binder_catalog_novelties(p_collection_id) nv
  where nv.is_novelty and (p_keys is null or nv.item_key = any (p_keys));
  v_cnt := coalesce(cardinality(sel_key), 0);
  total_items := v_cnt;

  if v_cnt = 0 then
    outcome := 'NOTHING_TO_DO'; capacity_after := n0; total_rows_moved := 0;
    return next; return;
  end if;
  if v_cnt > c_item_limit then
    outcome := 'OVER_LIMIT'; reason := 'ITEM_LIMIT'; capacity_after := n0; total_rows_moved := 0;
    return next; return;
  end if;

  -- W3: novidades tipadas por carta (todas as pendentes, não só as selecionadas)
  select coalesce(jsonb_object_agg(t.cid, t.n), '{}'::jsonb) into v_tnov
  from (select nv.card_id::text as cid, count(*) as n
        from public.binder_catalog_novelties(p_collection_id) nv
        where nv.is_novelty and nv.variant_type_id is not null
        group by nv.card_id) t;

  -- Simulação --------------------------------------------------------------------------------------
  for q in 1 .. v_cnt loop
    v_key := sel_key[q]; v_o := sel_ord[q];
    v_kind := null; v_bkind := null; i := null; j := null; b := null; a := null; v_rows := 0; v_oth := 0; v_add := false;

    if v_blocked then
      v_kind := 'NOT_EVALUATED';
    else
      -- (W3) reserva genérica "carta:*" desta coleção cuja posição genérica não existe mais
      --      (carta que ganhou acabamento): converter no próprio bolso, sem duplicar.
      v_star := 0; i := null;
      if sel_vt[q] is not null and not (v_ordmap ? (sel_card[q]::text || ':*')) then
        for k in 1 .. n loop
          if c_rkey[k] = sel_card[q]::text || ':*' then
            v_star := v_star + 1;
            if i is null then i := k; end if;
          end if;
        end loop;
      end if;
      if v_star > 0 then
        if v_star = 1 and coalesce((v_tnov ->> sel_card[q]::text)::integer, 0) = 1 then
          v_kind := 'UPGRADE_RESERVATION';
        else
          v_kind := 'REVIEW_REQUIRED'; v_review := true; b := i; v_bkind := 'GENERIC_RESERVATION'; i := null;
        end if;
      else
        i := null;
        -- (b) âncora anterior (reserva preferida; depois menor índice)
        v_best := null; v_best_ord := null; v_best_res := false;
        for k in 1 .. n loop
          m := null; v_here_res := false;
          if c_rkey[k] is not null then m := (v_ordmap ->> c_rkey[k])::integer; v_here_res := m is not null; end if;
          if m is null and c_pk1[k] is not null then m := (v_ordmap ->> c_pk1[k])::integer; end if;
          if m is null and c_pk2[k] is not null then m := (v_ordmap ->> c_pk2[k])::integer; end if;
          if m is not null and m < v_o
             and (v_best is null or m > v_best_ord or (m = v_best_ord and v_here_res and not v_best_res)) then
            v_best := k; v_best_ord := m; v_best_res := v_here_res;
          end if;
        end loop;
        if v_best is not null then
          a := v_best; i := v_best + 1;
        else
          -- (c) âncora seguinte: a novidade entra antes dela
          for k in 1 .. n loop
            m := null; v_here_res := false;
            if c_rkey[k] is not null then m := (v_ordmap ->> c_rkey[k])::integer; v_here_res := m is not null; end if;
            if m is null and c_pk1[k] is not null then m := (v_ordmap ->> c_pk1[k])::integer; end if;
            if m is null and c_pk2[k] is not null then m := (v_ordmap ->> c_pk2[k])::integer; end if;
            if m is not null and m > v_o
               and (v_best is null or m < v_best_ord or (m = v_best_ord and v_here_res and not v_best_res)) then
              v_best := k; v_best_ord := m; v_best_res := v_here_res;
            end if;
          end loop;
          if v_best is not null then a := v_best; i := v_best; end if;
        end if;

        -- (W6) exemplar desta posição já colocado no fichário: só no bolso natural vira
        --      reserva; em qualquer outro bolso a carta fica onde está e o item vai para revisão.
        v_pl := null;
        for k in 1 .. n loop
          if (sel_vt[q] is not null and c_pk1[k] = v_key) or (sel_vt[q] is null and c_pk2[k] = v_key) then
            if i is not null and k = i and not c_res[k] then v_pl := k; exit; end if;
            if v_pl is null then v_pl := -k; end if;
          end if;
        end loop;

        if v_pl is not null and v_pl > 0 then
          v_kind := 'RESERVE_PLACED';
        elsif v_pl is not null then
          v_kind := 'OUT_OF_ORDER'; v_review := true; b := -v_pl; v_bkind := 'PLACED_OUT_OF_ORDER';
        elsif i is null then
          v_kind := 'NO_ANCHOR'; v_no_anchor := true;
        elsif i > n then
          -- âncora no último bolso: página nova, sem deslocamento
          v_add := true;
          v_maxpage := v_maxpage + 1; v_pages_added := v_pages_added + 1; v_added := v_added || v_maxpage;
          for r in 1 .. x.grid_rows loop
            for cc in 1 .. x.grid_columns loop
              n := n + 1;
              s_id[n] := null; s_pg[n] := v_maxpage; s_rw[n] := r; s_cl[n] := cc; s_bar[n] := false; s_bk[n] := null;
              c_asg[n] := false; c_res[n] := false; c_img[n] := false; c_rkey[n] := null; c_roth[n] := false;
              c_pk1[n] := null; c_pk2[n] := null;
            end loop;
          end loop;
          v_kind := 'IN_PLACE';
        elsif s_bar[i] then
          v_kind := 'BLOCKED'; b := i; v_bkind := s_bk[i];
        elsif not c_asg[i] and not c_res[i] and not c_img[i] then
          v_kind := 'IN_PLACE';
        else
          -- mesma regra da 5243 (binder_gap_chain/evaluate)
          for k in i + 1 .. n loop
            if s_bar[k] then b := k; exit; end if;
            if not c_asg[k] and not c_res[k] and not c_img[k] then j := k; exit; end if;
          end loop;
          if b is not null then
            v_kind := 'BLOCKED'; v_bkind := s_bk[b];
          else
            if j is null then
              v_add := true;
              v_maxpage := v_maxpage + 1; v_pages_added := v_pages_added + 1; v_added := v_added || v_maxpage;
              j := n + 1;
              for r in 1 .. x.grid_rows loop
                for cc in 1 .. x.grid_columns loop
                  n := n + 1;
                  s_id[n] := null; s_pg[n] := v_maxpage; s_rw[n] := r; s_cl[n] := cc; s_bar[n] := false; s_bk[n] := null;
                  c_asg[n] := false; c_res[n] := false; c_img[n] := false; c_rkey[n] := null; c_roth[n] := false;
                  c_pk1[n] := null; c_pk2[n] := null;
                end loop;
              end loop;
            end if;
            v_kind := 'SHIFT';
            for k in i .. j - 1 loop
              v_rows := v_rows + (case when c_asg[k] then 1 else 0 end)
                               + (case when c_res[k] then 1 else 0 end)
                               + (case when c_img[k] then 1 else 0 end);
              v_oth := v_oth + (case when c_roth[k] then 1 else 0 end);
            end loop;
            for k in reverse j - 1 .. i loop
              c_asg[k + 1] := c_asg[k]; c_res[k + 1] := c_res[k]; c_img[k + 1] := c_img[k];
              c_rkey[k + 1] := c_rkey[k]; c_roth[k + 1] := c_roth[k];
              c_pk1[k + 1] := c_pk1[k]; c_pk2[k + 1] := c_pk2[k];
            end loop;
            c_asg[i] := false; c_res[i] := false; c_img[i] := false; c_rkey[i] := null; c_roth[i] := false;
            c_pk1[i] := null; c_pk2[i] := null;
          end if;
        end if;
      end if;

      if v_kind = 'BLOCKED' then
        v_blocked := true;
      elsif v_kind in ('IN_PLACE', 'RESERVE_PLACED', 'SHIFT', 'UPGRADE_RESERVATION') then
        c_res[i] := true; c_rkey[i] := v_key;
        v_total_rows := v_total_rows + v_rows;
      end if;
    end if;

    st_kind := st_kind || v_kind;
    st_t := array_append(st_t, i); st_e := array_append(st_e, j); st_a := array_append(st_a, a);
    st_b := array_append(st_b, b); st_bk := array_append(st_bk, v_bkind);
    st_pm := array_append(st_pm, case when v_kind = 'SHIFT' then j - i end);
    st_rows := array_append(st_rows, v_rows); st_oth := array_append(st_oth, v_oth);
    st_cross := array_append(st_cross, v_kind = 'SHIFT' and not v_add and s_pg[i] <> s_pg[j]);
    st_add := array_append(st_add, v_add);
    v_steps := v_steps || E'\n' || concat_ws('|', q, v_key, v_kind,
      coalesce(s_id[i]::text, 'new'), coalesce(s_pg[i]::text, '-'), coalesce(s_rw[i]::text, '-'), coalesce(s_cl[i]::text, '-'),
      coalesce(s_pg[j]::text, '-'), coalesce(s_rw[j]::text, '-'), coalesce(s_cl[j]::text, '-'),
      coalesce(s_id[a]::text, '-'), coalesce(s_id[b]::text, '-'), coalesce(v_bkind, '-'), v_add::text, v_rows, v_oth);
  end loop;

  select count(*) into v_free
  from generate_subscripts(s_id, 1) g(k)
  where not s_bar[g.k] and not c_asg[g.k] and not c_res[g.k] and not c_img[g.k];

  v_outcome := case when v_blocked then 'BLOCKED'
                    when v_review then 'NEEDS_REVIEW'
                    when v_no_anchor then 'NO_ANCHOR'
                    when v_total_rows > c_row_limit then 'OVER_LIMIT'
                    else 'READY' end;
  v_reason := case when v_outcome = 'OVER_LIMIT' then 'ROW_LIMIT' end;

  v_token := 'rc1:' || encode(sha256(convert_to(
      c_version || '#' || p_collection_id::text || '#' || x.layout_id::text || '#' || x.owner_collection_id::text || '#'
      || extract(epoch from x.marker_at)::text   -- W1: número, independe de TimeZone/DateStyle
      || '#' || array_to_string(x.finish_type_ids, ',') || '#'
      || x.grid_rows::text || 'x' || x.grid_columns::text || '#' || v_maxpage0::text || '#' || n0::text || '#'
      || v_state || '#' || v_pos || '#' || array_to_string(sel_key, ',') || '#' || v_outcome
      || v_steps, 'UTF8')), 'hex');

  -- Cabeçalho
  outcome := v_outcome; reason := v_reason; total_rows_moved := v_total_rows;
  requires_cross_page := coalesce(true = any (st_cross), false);
  requires_add_page := v_pages_added > 0;
  pages_added := v_pages_added; added_page_numbers := v_added;
  capacity_after := n; free_pockets_after := v_free; plan_token := v_token;
  return next;

  -- Itens
  for q in 1 .. v_cnt loop
    row_kind := 'ITEM'; outcome := null; reason := null; total_items := null; total_rows_moved := null;
    row_limit := null; item_limit := null; requires_cross_page := null; requires_add_page := null;
    pages_added := null; added_page_numbers := null; capacity_before := null; capacity_after := null;
    free_pockets_after := null; plan_token := null;
    step_no := q; item_key := sel_key[q]; card_id := sel_card[q]; variant_type_id := sel_vt[q]; pos_ord := sel_ord[q];
    kind := st_kind[q];
    i := st_t[q]; j := st_e[q]; a := st_a[q]; b := st_b[q];
    target_page := s_pg[i]; target_row := s_rw[i]; target_column := s_cl[i];
    end_page := s_pg[j]; end_row := s_rw[j]; end_column := s_cl[j];
    anchor_page := s_pg[a]; anchor_row := s_rw[a]; anchor_column := s_cl[a];
    barrier_page := s_pg[b]; barrier_row := s_rw[b]; barrier_column := s_cl[b]; barrier_kind := st_bk[q];
    pockets_moved := st_pm[q]; rows_moved := st_rows[q]; other_reserves_moved := st_oth[q];
    crosses_page := st_cross[q]; adds_page := st_add[q];
    return next;
  end loop;
end;
$$;

revoke all on function public.binder_catalog_plan(uuid, text[])
  from public, anon, authenticated, service_role;

commit;

/*
Resultado esperado: 5 funções internas, SECURITY DEFINER, search_path vazio,
sem EXECUTE para PUBLIC/anon/authenticated/service_role. Nenhum objeto
existente alterado.
Como validar: harness 5859 seção 0 (estrutura/ACL) e 1 (ordem).
*/
