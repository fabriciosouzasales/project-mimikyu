/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5258 - Referências de espécie: plano, prévia, aplicação,
              exibição e remoção
              binder_species_reference_target(uuid)                  — helper interno (dono + Pokédex)
              binder_species_reference_plan(uuid, uuid, uuid, text)  — helper interno (FONTE ÚNICA do plano)
              preview_my_binder_species_references(uuid)             — prévia (não grava)
              apply_my_binder_species_references(uuid, text)         — aplicação única, idempotente
              set_my_binder_species_reference_visibility(uuid, bool) — mostrar/ocultar (não apaga)
              clear_my_binder_species_references(uuid, int)          — remoção explícita
Versão......: 1.0 (2026-10-24, POKEDEX-BINDER-SPECIES-REFERENCE-IMPLEMENTATION-01)
Status......: PROPOSTA — NÃO EXECUTADA. Depende da 5257.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-24

Regras:
  R1  Só a coleção PROPRIETÁRIA do fichário, de Pokédex (REFERENCE_BASED /
      REFERENCE_POSITION / referência POKEDEX), aplica ou remove.
      Convidada → BINDER_OWNER_ONLY (42501). Coleção comum →
      NOT_POKEDEX_COLLECTION (22023). Alheia/inexistente → COLLECTION_NOT_FOUND
      (P0002, mesma mensagem; não enumera). Sem fichário → BINDER_NOT_FOUND.
  R2  Plano (fonte única, usado pela prévia e pela aplicação):
        bolsos do fichário em ordem página → linha → coluna, numerados 1..S;
        posições da Pokédex NO ESCOPO da coleção (mesma regra da 5204:
        FULL_REFERENCE ou geração selecionada) em ordem de position_number,
        numeradas 1..P;
        par n = (bolso n, posição n), n ≤ min(S, P).
      F002 (66 × 16 = 1.056 bolsos, 1.025 posições): 1.025 pares; bolsos
      1.026–1.056 sem referência. Nenhuma página é criada (P > S → as
      posições excedentes ficam sem bolso e a prévia informa).
  R3  plan_token = SHA-256 do layout + pares ordenados. A aplicação recalcula
      SOB A TRAVA canônica COLLECTION → LAYOUT (5122) e recusa com
      PLAN_CHANGED se divergir (página adicionada/removida/reordenada,
      escopo alterado, etc.).
  R4  Idempotência: aplicar de novo o MESMO plano já gravado →
      operation = 'ALREADY_APPLIED', nada gravado. Fichário com referências de
      outro plano → SPECIES_REFERENCES_PRESENT (remover antes; nunca mistura).
  R5  A aplicação grava os pares com UM insert … select (sem laço) e marca a
      preferência como visível. Não toca páginas, bolsos, cartas, posições,
      reservas, imagens, regiões, alocações, exemplares, armazenamento,
      progresso nem collection_layout.updated_at.
  R6  Ajuste A — exibição separada da remoção: set_…_visibility só grava a
      preferência (upsert por layout); NUNCA apaga vínculos. Proprietária ou
      convidada (mesmo dono) podem alternar; vale para o fichário inteiro.
      Mesmo valor → UNCHANGED.
  R7  clear_… remove só a camada de referências do fichário e exige
      p_expected_count = quantidade atual (proteção contra remoção às cegas;
      divergência → COUNT_MISMATCH). Sem referências → REMOVED com 0
      (repetível). A preferência de exibição permanece.
  Bolso com carta, reserva, imagem ou mesclagem também recebe referência:
  ela fica oculta enquanto o espaço estiver ocupado (D3) — a prévia informa
  quantos pares estão nessa situação (slots_with_content).
Dependências: 5257, 5122, 5229 (guest), 5232 (imagem), 5119/5238 (região),
5113 (reserva), 5248 (posição).
================================================================
*/

begin;

do $pre$
begin
  if to_regclass('public.collection_layout_slot_species_reference') is null
     or to_regclass('public.collection_layout_species_reference_setting') is null then
    raise exception 'PRECHECK 5258: aplique a 5257 antes';
  end if;
  if to_regprocedure('public.assert_collection_layout_mutable(uuid)') is null then
    raise exception 'PRECHECK 5258: 5122 ausente';
  end if;
  if to_regprocedure('public.apply_my_binder_species_references(uuid, text)') is not null then
    raise exception 'PRECHECK 5258: funções já existem';
  end if;
end;
$pre$;

-- 0. Helper: alvo (dono, fichário, Pokédex) ------------------------------------------------
create function public.binder_species_reference_target(p_collection_id uuid)
returns table (layout_id uuid, pokedex_id uuid, collection_reference_id uuid, scope_kind text)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid    uuid := auth.uid();
  v_layout uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  perform 1 from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  select l.id into v_layout
  from public.collection_layout l where l.collection_id = p_collection_id;
  if v_layout is null then
    if exists (select 1 from public.collection_layout_guest g where g.collection_id = p_collection_id) then
      raise exception 'BINDER_OWNER_ONLY' using errcode = '42501',
        hint = 'as referências são definidas pela coleção dona do fichário';
    end if;
    raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
  end if;

  return query
  select v_layout, cpr.pokedex_id, cr.id, cpr.scope_kind::text
  from public.collection c
  join public.collection_reference cr
    on cr.collection_id = c.id and cr.reference_kind = 'POKEDEX'
  join public.collection_pokedex_reference cpr on cpr.collection_reference_id = cr.id
  where c.id = p_collection_id
    and c.mode = 'REFERENCE_BASED'
    and c.completion_policy = 'REFERENCE_POSITION';
  if not found then
    raise exception 'NOT_POKEDEX_COLLECTION' using errcode = '22023',
      hint = 'referências de espécie existem só em fichários de coleções Pokédex';
  end if;
end;
$$;

revoke all on function public.binder_species_reference_target(uuid)
  from public, anon, authenticated, service_role;

-- 1. Helper: plano (fonte única) -----------------------------------------------------------
create function public.binder_species_reference_plan(
  p_layout_id uuid,
  p_pokedex_id uuid,
  p_collection_reference_id uuid,
  p_scope_kind text
)
returns table (
  ord                 integer,
  slot_id             uuid,
  page_number         integer,
  row_index           integer,
  column_index        integer,
  pokedex_position_id uuid,
  position_number     integer
)
language sql
stable
security definer
set search_path = ''
as $$
  with slots as (
    select s.id as slot_id, pg.page_number, s.row_index, s.column_index,
           row_number() over (order by pg.page_number, s.row_index, s.column_index, s.id)::integer as n
    from public.collection_layout_page pg
    join public.collection_layout_slot s on s.page_id = pg.id
    where pg.layout_id = p_layout_id
  ),
  positions as (
    select pp.id as pos_id, pp.position_number,
           row_number() over (order by pp.position_number, pp.id)::integer as n
    from public.pokedex_position pp
    join public.pokemon_species sp on sp.id = pp.species_id
    where pp.pokedex_id = p_pokedex_id
      and (p_scope_kind = 'FULL_REFERENCE'
           or exists (select 1 from public.collection_pokedex_scope_generation sg
                      where sg.collection_reference_id = p_collection_reference_id
                        and sg.generation_id = sp.generation_id))
  )
  select sl.n, sl.slot_id, sl.page_number, sl.row_index, sl.column_index, po.pos_id, po.position_number
  from slots sl
  join positions po on po.n = sl.n
  order by sl.n;
$$;

revoke all on function public.binder_species_reference_plan(uuid, uuid, uuid, text)
  from public, anon, authenticated, service_role;

-- 2. Prévia -------------------------------------------------------------------------------
create function public.preview_my_binder_species_references(p_collection_id uuid)
returns table (
  layout_id          uuid,
  positions_in_scope integer,
  slots_total        integer,
  pair_count         integer,
  slots_left_free    integer,
  positions_unplaced integer,
  first_page         integer,
  last_page          integer,
  first_number       integer,
  last_number        integer,
  slots_with_content integer,
  existing_count     integer,
  already_applied    boolean,
  plan_token         text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  t  record;
  v_pos integer; v_slots integer; v_pairs integer; v_fp integer; v_lp integer;
  v_fn integer; v_ln integer; v_content integer; v_existing integer; v_token text; v_same boolean;
begin
  select * into t from public.binder_species_reference_target(p_collection_id);

  select count(*)::integer into v_pos
  from public.pokedex_position pp
  join public.pokemon_species sp on sp.id = pp.species_id
  where pp.pokedex_id = t.pokedex_id
    and (t.scope_kind = 'FULL_REFERENCE'
         or exists (select 1 from public.collection_pokedex_scope_generation sg
                    where sg.collection_reference_id = t.collection_reference_id
                      and sg.generation_id = sp.generation_id));

  select count(*)::integer into v_slots
  from public.collection_layout_page pg
  join public.collection_layout_slot s on s.page_id = pg.id
  where pg.layout_id = t.layout_id;

  select count(*)::integer, min(p.page_number), max(p.page_number), min(p.position_number), max(p.position_number),
         count(*) filter (where exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = p.slot_id)
                             or exists (select 1 from public.collection_layout_slot_expected_content e where e.slot_id = p.slot_id)
                             or exists (select 1 from public.collection_layout_slot_image i where i.slot_id = p.slot_id)
                             or exists (select 1 from public.collection_layout_slot s
                                        join public.collection_layout_region rg on rg.page_id = s.page_id
                                        where s.id = p.slot_id
                                          and s.row_index    between rg.top_row     and rg.top_row     + rg.height - 1
                                          and s.column_index between rg.left_column and rg.left_column + rg.width  - 1))::integer,
         encode(sha256(convert_to(t.layout_id::text || '|' ||
                coalesce(string_agg(p.slot_id::text || ':' || p.pokedex_position_id::text, ',' order by p.ord), ''), 'UTF8')), 'hex')
    into v_pairs, v_fp, v_lp, v_fn, v_ln, v_content, v_token
  from public.binder_species_reference_plan(t.layout_id, t.pokedex_id, t.collection_reference_id, t.scope_kind) p;

  select count(*)::integer into v_existing
  from public.collection_layout_slot_species_reference r where r.layout_id = t.layout_id;

  v_same := v_existing = v_pairs and v_pairs > 0 and not exists (
    select 1 from public.binder_species_reference_plan(t.layout_id, t.pokedex_id, t.collection_reference_id, t.scope_kind) p
    where not exists (select 1 from public.collection_layout_slot_species_reference r
                      where r.slot_id = p.slot_id and r.pokedex_position_id = p.pokedex_position_id
                        and r.collection_id = p_collection_id));

  layout_id          := t.layout_id;
  positions_in_scope := v_pos;
  slots_total        := v_slots;
  pair_count         := v_pairs;
  slots_left_free    := v_slots - v_pairs;
  positions_unplaced := v_pos - v_pairs;
  first_page         := v_fp;
  last_page          := v_lp;
  first_number       := v_fn;
  last_number        := v_ln;
  slots_with_content := v_content;
  existing_count     := v_existing;
  already_applied    := v_same;
  plan_token         := v_token;
  return next;
end;
$$;

comment on function public.preview_my_binder_species_references(uuid) is
  'POKEDEX-BINDER-SPECIES-REFERENCE (5258): prévia das referências de espécie do fichário da coleção Pokédex proprietária — pares bolso n ↔ posição n (ordem página → linha → coluna × position_number no escopo), bolsos livres, posições sem bolso, bolsos com conteúdo (referência oculta) e plan_token. Não grava nada.';

revoke all on function public.preview_my_binder_species_references(uuid) from public, anon;
grant execute on function public.preview_my_binder_species_references(uuid) to authenticated;

-- 3. Aplicação ----------------------------------------------------------------------------
create function public.apply_my_binder_species_references(p_collection_id uuid, p_plan_token text)
returns table (
  layout_id          uuid,
  operation          text,
  reference_count    integer,
  references_visible boolean
)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
#variable_conflict use_column
declare
  t  record;
  pv record;
  v_count integer;
begin
  if p_plan_token is null or p_plan_token !~ '^[0-9a-f]{64}$' then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  select * into t from public.binder_species_reference_target(p_collection_id);

  -- Trava canônica COLLECTION → LAYOUT e ACTIVE lido sob a trava (5122).
  begin
    perform public.assert_collection_layout_mutable(t.layout_id);
  exception
    when others then
      if sqlerrm like 'collection layout not found%' then
        raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
      elsif sqlerrm like 'collection is ARCHIVED%' then
        raise exception 'COLLECTION_ARCHIVED' using errcode = '55000',
          hint = 'reative a coleção para editar o fichário';
      end if;
      raise;
  end;

  -- Plano recalculado SOB a trava.
  select * into pv from public.preview_my_binder_species_references(p_collection_id);
  if pv.plan_token <> p_plan_token then
    raise exception 'PLAN_CHANGED' using errcode = 'P0001',
      hint = 'o fichário mudou desde a prévia; revise e confirme de novo';
  end if;

  if pv.already_applied then
    operation := 'ALREADY_APPLIED';
  else
    if pv.existing_count > 0 then
      raise exception 'SPECIES_REFERENCES_PRESENT' using errcode = 'P0001',
        hint = 'este fichário já tem referências; remova-as antes de aplicar de novo';
    end if;
    if pv.pair_count = 0 then
      raise exception 'NOTHING_TO_APPLY' using errcode = 'P0001',
        hint = 'o fichário não tem bolsos ou a coleção não tem Pokémon no escopo';
    end if;

    insert into public.collection_layout_slot_species_reference
      (slot_id, layout_id, collection_id, pokedex_position_id, source)
    select p.slot_id, t.layout_id, p_collection_id, p.pokedex_position_id, 'NATIONAL_ORDER'
    from public.binder_species_reference_plan(t.layout_id, t.pokedex_id, t.collection_reference_id, t.scope_kind) p;

    operation := 'APPLIED';
  end if;

  insert into public.collection_layout_species_reference_setting as st (layout_id, references_visible, updated_at)
  values (t.layout_id, true, now())
  on conflict on constraint pk_cl_species_reference_setting
  do update set references_visible = true, updated_at = now()
  where st.references_visible is distinct from true;

  select count(*)::integer into v_count
  from public.collection_layout_slot_species_reference r where r.layout_id = t.layout_id;

  layout_id          := t.layout_id;
  reference_count    := v_count;
  references_visible := true;
  return next;
end;
$$;

comment on function public.apply_my_binder_species_references(uuid, text) is
  'POKEDEX-BINDER-SPECIES-REFERENCE (5258): grava as referências de espécie do plano da prévia (plan_token conferido sob a trava 5122). Idempotente (ALREADY_APPLIED); recusa se houver referências de outro plano. Marca a exibição como visível. Não toca cartas, reservas, imagens, páginas, progresso ou armazenamento.';

revoke all on function public.apply_my_binder_species_references(uuid, text) from public, anon;
grant execute on function public.apply_my_binder_species_references(uuid, text) to authenticated;

-- 4. Exibição (ajuste A) ------------------------------------------------------------------
create function public.set_my_binder_species_reference_visibility(p_collection_id uuid, p_visible boolean)
returns table (layout_id uuid, references_visible boolean, operation text)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
#variable_conflict use_column
declare
  v_layout  uuid;
  v_current boolean;
begin
  if p_visible is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  -- Proprietária OU convidada do mesmo dono (helper 5234; P0002 se alheia).
  v_layout := public.binder_slot_image_resolve_layout(p_collection_id);
  if v_layout is null then
    raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
  end if;

  select st.references_visible into v_current
  from public.collection_layout_species_reference_setting st
  where st.layout_id = v_layout
  for update;

  if coalesce(v_current, true) = p_visible then
    operation := 'UNCHANGED';
  else
    insert into public.collection_layout_species_reference_setting (layout_id, references_visible, updated_at)
    values (v_layout, p_visible, now())
    on conflict on constraint pk_cl_species_reference_setting
    do update set references_visible = excluded.references_visible, updated_at = now();
    operation := 'UPDATED';
  end if;

  layout_id          := v_layout;
  references_visible := p_visible;
  return next;
end;
$$;

comment on function public.set_my_binder_species_reference_visibility(uuid, boolean) is
  'POKEDEX-BINDER-SPECIES-REFERENCE (5258): mostrar/ocultar as referências de espécie do fichário (preferência persistida por fichário). NUNCA apaga vínculos. Proprietária ou convidada do mesmo dono.';

revoke all on function public.set_my_binder_species_reference_visibility(uuid, boolean) from public, anon;
grant execute on function public.set_my_binder_species_reference_visibility(uuid, boolean) to authenticated;

-- 5. Remoção explícita --------------------------------------------------------------------
create function public.clear_my_binder_species_references(p_collection_id uuid, p_expected_count integer)
returns table (layout_id uuid, operation text, removed_count integer)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
#variable_conflict use_column
declare
  t  record;
  v_current integer;
  v_removed integer;
begin
  if p_expected_count is null or p_expected_count < 0 then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  select * into t from public.binder_species_reference_target(p_collection_id);

  begin
    perform public.assert_collection_layout_mutable(t.layout_id);
  exception
    when others then
      if sqlerrm like 'collection layout not found%' then
        raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
      elsif sqlerrm like 'collection is ARCHIVED%' then
        raise exception 'COLLECTION_ARCHIVED' using errcode = '55000',
          hint = 'reative a coleção para editar o fichário';
      end if;
      raise;
  end;

  select count(*)::integer into v_current
  from public.collection_layout_slot_species_reference r where r.layout_id = t.layout_id;

  if v_current <> p_expected_count then
    raise exception 'COUNT_MISMATCH' using errcode = 'P0001',
      hint = format('o fichário tem %s referências; revise antes de remover', v_current);
  end if;

  delete from public.collection_layout_slot_species_reference r where r.layout_id = t.layout_id;
  get diagnostics v_removed = row_count;

  layout_id     := t.layout_id;
  operation     := 'REMOVED';
  removed_count := v_removed;
  return next;
end;
$$;

comment on function public.clear_my_binder_species_references(uuid, integer) is
  'POKEDEX-BINDER-SPECIES-REFERENCE (5258): remove todas as referências de espécie do fichário (só a proprietária Pokédex ativa; exige a contagem atual). Não toca cartas, reservas, imagens, páginas ou progresso. Para só esconder, use set_my_binder_species_reference_visibility.';

revoke all on function public.clear_my_binder_species_references(uuid, integer) from public, anon;
grant execute on function public.clear_my_binder_species_references(uuid, integer) to authenticated;

commit;
