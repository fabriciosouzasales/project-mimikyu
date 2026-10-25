/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5266 - Fichário Digital × Catálogo: incorporação das novidades
Versão......: 1.2 (2026-10-24, BINDER-CATALOG-RECONCILIATION-W5-FOUNDATION-01:
              W5 — registra cada item incorporado em
              collection_layout_catalog_incorporation (5263) na mesma
              transação, depois das pós-condições; renumerada de 5265 para
              5266.) Anterior 1.1 (AUDIT-CORRECTION-01): W2 limite antes do
              token; W3 UPGRADE_RESERVATION; W6 NEEDS_REVIEW.
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core em 2026-10-25
              (LIVE-EXECUTION-AUTHORIZATION-01, autorização expressa de Fabrício;
              ledger 20261025145504 `5266_create_binder_catalog_reconciliation_apply`). Do `begin;` ao `commit;`
              idêntica ao arquivo de database/proposals/2026-10-24-binder-catalog-
              reconciliation/ (só este bloco Status difere); enviada via
              apply_migration sem as linhas `begin;`/`commit;` externas — o texto
              gravado no ledger é igual ao corpo do arquivo da proposta (md5).
              Harness 5859 NÃO EXECUTADO (estratégia H-A). Homologada pelo
              proprietário (funcional e visual). Ver README §16–§18 da proposta.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-24

Descrição...:
  apply_my_binder_catalog_reconciliation(collection, keys, plan_token,
                                         confirm_cross_page, confirm_add_page)

  1. Sessão obrigatória; argumentos válidos (token 'rc1:' + 64 hex).
  2. Trava canônica binder_layout_lock_for_collection (5240): coleção do
     usuário → trava COLEÇÃO dona → FICHÁRIO (5122), ambas ACTIVE; convidada
     ativa e participante. Serializa com Inserir Espaço, mover/trocar,
     colocar/retirar, reservar, páginas, imagens e mesclagens (todas passam
     pela mesma trava do fichário).
  3. Elegibilidade sob a trava (5264): só MASTER_SET; fichário de dona
     Pokédex ou com referências de espécie → BINDER_NOT_ELIGIBLE. Invariante
     de propriedade (ajuste 5): dono da coleção = dono do fichário = sessão.
  4. Idempotência: chaves já reservadas por esta coleção OU já incorporadas
     (registro 5263 — W5: continua valendo depois que a reserva é liberada)
     contam como aplicadas; todas aplicadas → ALREADY_APPLIED (keys
     informadas) ou NOTHING_TO_DO (keys = null), sem gravar nada e sem
     restaurar reserva liberada. Chave que não é posição nascida após o
     marco → SELECTION_INVALID.
  5. Recalcula o plano sob a trava. OVER_LIMIT → RECONCILE_OVER_LIMIT (54000)
     ANTES da comparação do token (W2: no limite de itens o plano não gera
     token). Token diferente do da prévia (ajuste 7) → RECONCILE_PLAN_CHANGED
     (40001). BLOCKED → RECONCILE_BLOCKED (55000, barreira no hint);
     NEEDS_REVIEW (carta fora da ordem, W6; reserva genérica ambígua, W3) →
     RECONCILE_NEEDS_REVIEW (55000); NO_ANCHOR → RECONCILE_NO_ANCHOR (55000);
     falta de confirmação → RECONCILE_CONFIRMATION_REQUIRED (55000,
     CROSS_PAGE | ADD_PAGE).
  6. Executa os passos na ordem simulada: página nova por add_layout_page
     (5125, mesmo número previsto); deslocamento por binder_gap_move_pocket
     (5243, bolso inteiro: posição, reserva de qualquer coleção, imagem), do
     fim para o começo, bolsos travados em ordem de id; reserva nova com
     acabamento (collection_id NULL para a dona — convenção 5224/5229 —, id
     da convidada para convidada); UPGRADE_RESERVATION (W3): a reserva
     genérica existente desta coleção recebe o acabamento no próprio bolso
     (UPDATE de exatamente 1 linha; nada anda, nada é criado).
  7. Pós-condições: linhas movidas = previstas; reservas criadas +
     convertidas = itens; toda chave selecionada agora reservada por esta
     coleção. Qualquer divergência → RECONCILE_INCONSISTENT e rollback total.
  8. W5 (estrutura 5263): só então registra cada chave aplicada (criação ou
     conversão) em collection_layout_catalog_incorporation com a coleção
     REAL (dona ou convidada) — INSERT … ON CONFLICT DO NOTHING com
     contagem exata: como as chaves pendentes não estavam incorporadas (lido
     sob a trava), qualquer conflito é inconsistência → rollback total.
     Recusas, falhas e prévias nunca chegam aqui: nada é registrado.

Nunca: move carta para fora da ordem, toca alocação/exemplar/progresso,
restaura reserva liberada, lê ou escreve referências da Pokédex, altera
funções existentes.
Dependências: 5263, 5264, 5265, 5240, 5243, 5125.
================================================================
*/

begin;

do $pre$
begin
  if to_regprocedure('public.binder_catalog_plan(uuid, text[])') is null
     or to_regprocedure('public.preview_my_binder_catalog_reconciliation(uuid, text[])') is null then
    raise exception 'PRECHECK 5266: aplique 5264 e 5265 antes';
  end if;
  if to_regprocedure('public.apply_my_binder_catalog_reconciliation(uuid, text[], text, boolean, boolean)') is not null then
    raise exception 'PRECHECK 5266: já aplicada';
  end if;
end;
$pre$;

create function public.apply_my_binder_catalog_reconciliation(
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
as $$
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
$$;

comment on function public.apply_my_binder_catalog_reconciliation(uuid, text[], text, boolean, boolean) is
  'Fichário Digital × Catálogo (5266): incorpora as novidades selecionadas no fichário de uma coleção Master Set, conforme a prévia (plan_token): reserva no bolso natural livre ou abre espaço deslocando as posições seguintes (bolso inteiro, mesma regra do Inserir Espaço). Atômica, idempotente, só o dono; página nova e outra página só com confirmação. Registra cada novidade incorporada (5263) para que não volte a ser oferecida depois de liberada. Nunca toca a Pokédex.';

revoke all on function public.apply_my_binder_catalog_reconciliation(uuid, text[], text, boolean, boolean) from public, anon;
grant execute on function public.apply_my_binder_catalog_reconciliation(uuid, text[], text, boolean, boolean) to authenticated;

commit;

/*
Resultado esperado: 1 RPC SECURITY DEFINER, VOLATILE, search_path vazio,
lock_timeout 5s, EXECUTE só para authenticated.
Como validar: harness 5859 seções 5–8.
*/
