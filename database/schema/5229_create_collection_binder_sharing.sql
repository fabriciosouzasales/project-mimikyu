/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5229 - Fichário Digital compartilhado (P2-SHARED-BINDER):
              proprietária + coleções convidadas
              tabela   collection_layout_guest
              coluna   collection_layout_slot_expected_content.collection_id
              gatilhos guest_integrity, layout_owner_not_guest,
                       layout_delete_without_guests,
                       expected_content_participant
              5117     enforce_collection_layout_slot_assignment_integrity (evolução)
              5131     assign_card_to_slot (evolução, mesma assinatura)
              5225     set_slot_expected_content (+ p_collection_id, DROP+CREATE)
              5226     delete_collection (+ recusa BINDER_GUEST)
              5226     preview_my_collection_binder_dismantle (+ guest_count,
                       blocked_reason; DROP+CREATE) e
                       dismantle_my_collection_binder (recusa BINDER_HAS_GUESTS
                       ANTES de remover; convidada → COLLECTION_IS_BINDER_GUEST)
              novas    attach_my_collection_to_binder(uuid, uuid)
                       collection_binder_detach_snapshot(uuid)   — helper interno
                       preview_my_collection_binder_detach(uuid)
                       detach_my_collection_from_binder(uuid, text, boolean)
Versão......: 1.1 (2026-10-23, P2-SHARED-BINDER-AUDIT-CORRECTION-01: desmontagem
              recusada antes da remoção e prévia com convidadas; trava da
              convidada antes da alocação em assign (ordem da 5047); gatilho
              de posição sem trava — removido ciclo com 5047 × 5132)
              1.0 (2026-10-23, P2-SHARED-BINDER-PROPOSAL-01)
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE em 2026-10-23 UTC
              (P2-SHARED-BINDER-LIVE-APPLY-01, autorização expressa de Fabrício;
              ledger 20261023160611 `5229_create_collection_binder_sharing`). Do `begin;` ao `commit;`
              byte a byte idêntica ao texto aplicado e ao arquivo da pasta
              database/proposals/2026-10-23-p2-shared-binder/ (só este
              bloco Status difere). POST-1 14/14 PASS; dados intocados
              (contagens e md5 = baseline); harness 5851 NÃO EXECUTADO
              (cria dados — proibido no LIVE); sem prova comportamental.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-23

Decisões (C-195–C-197, emenda de C-38/C-191; aprovadas em
P2-SHARED-BINDER-PROPOSAL-01, alternativa A do discovery):
  D1 compartilhar exige associação explícita (attach), nunca automática;
  D2 progresso e alocações de cada coleção permanecem independentes — nada
     aqui toca collection_allocation nem os read models de completude;
  D3 nada existente é rearranjado: attach não escreve bolso algum;
  D4 a convidada posiciona manualmente (assign/move/remove existentes);
  D5 desassociar remove só posições e reservas da convidada;
  D6 bolsos fixados afetados só são soltos com p_release_locks = true;
  D7 desmontagem bloqueada enquanto houver convidadas (BINDER_HAS_GUESTS);
  D8 reservas novas registram a coleção (collection_id); as existentes
     (NULL) continuam da proprietária;
  D9 o local físico identifica candidatos (5230) e é exigido no attach,
     mas mudar o local depois NÃO desfaz a associação.

Modelo: collection_layout.collection_id continua sendo a PROPRIETÁRIA
(UNIQUE, imutável — 5105/5136 intocados). Convidadas ficam em
collection_layout_guest (PK collection_id ⇒ uma coleção é convidada de no
máximo um fichário). Participantes de um fichário = proprietária ∪
convidadas; todos do MESMO dono (gatilho). Uma coleção nunca é
proprietária e convidada ao mesmo tempo (dois gatilhos, um de cada lado,
serializados pela trava da linha da coleção).

Autorização: inalterada na raiz — toda RPC resolve o bolso/fichário pela
coleção PROPRIETÁRIA com owner_user_id = auth.uid(). Como todos os
participantes são do mesmo dono, nenhuma RPC passa a aceitar dado de
outro usuário. Alocação de coleção não participante, inexistente ou de
outro usuário colapsa na mesma mensagem (não enumera).

Ordem de travas (canônica, compatível com 5122/5224/5226):
  coleção PROPRIETÁRIA (FOR UPDATE) → LAYOUT (FOR UPDATE) →
  coleção CONVIDADA (FOR UPDATE no attach/detach; FOR SHARE em assign e
  na reserva, sempre ANTES da alocação) → SLOT → ALLOCATION → ASSIGNMENT.
  Fora do layout: 5046/5047 travam COLEÇÃO → ALLOCATION (→ posição por
  cascata, 5115 ON DELETE CASCADE, 5118 permite). Como assign trava a
  convidada antes da alocação e nenhum gatilho trava coleção depois de
  uma posição, não há ciclo entre desalocar a carta da convidada e
  posicioná-la/movê-la.
  Toda escrita no fichário passa pela trava do LAYOUT (5122), então duas
  coleções participantes nunca escrevem no mesmo fichário ao mesmo tempo.
  archive_collection trava só a linha da própria coleção e não espera
  layout: sem ciclo. create_my_collection_binder (5224) trava só a coleção
  que cria: sem ciclo com attach (que trava proprietária→layout→convidada).

Erros novos (P0001 salvo indicação): BINDER_NOT_FOUND (P0002),
  COLLECTION_NOT_FOUND (P0002), COLLECTION_ARCHIVED, BINDER_ARCHIVED,
  BINDER_SELF (22023), NOT_SAME_LOCATION, COLLECTION_HAS_OWN_BINDER,
  COLLECTION_ALREADY_IN_BINDER, COLLECTION_IS_BINDER_GUEST,
  BINDER_HAS_GUESTS, BINDER_GUEST (hint em delete_collection),
  DETACH_PLAN_CHANGED, LOCKED_SLOTS_REQUIRE_CONFIRMATION,
  INVALID_DETACH_TOKEN (22023), 55P03 (lock_timeout 5s).
================================================================
*/

begin;

do $pre$
begin
  if to_regclass('public.collection_layout_guest') is not null then
    raise exception 'PRECHECK 5229: collection_layout_guest já existe';
  end if;
  if to_regprocedure('public.set_slot_expected_content(uuid, uuid, uuid, uuid)') is null
     or to_regprocedure('public.dismantle_my_collection_binder(uuid, text)') is null
     or to_regprocedure('public.get_my_collection_binder(uuid)') is null then
    raise exception 'PRECHECK 5229: aplique 5223–5228 (P2-A1) antes';
  end if;
  if exists (select 1 from information_schema.columns
             where table_schema = 'public'
               and table_name = 'collection_layout_slot_expected_content'
               and column_name = 'collection_id') then
    raise exception 'PRECHECK 5229: expected_content.collection_id já existe';
  end if;
end;
$pre$;

-- 1. Convidadas --------------------------------------------------------------------
create table public.collection_layout_guest (
  collection_id uuid        primary key
                references public.collection(id) on update restrict on delete restrict,
  layout_id     uuid        not null
                references public.collection_layout(id) on update restrict on delete restrict,
  created_at    timestamptz not null default now()
);

create index ix_collection_layout_guest_layout on public.collection_layout_guest (layout_id);

comment on table public.collection_layout_guest is
  'Fichário Digital compartilhado (5229, C-195): coleção CONVIDADA de um fichário cuja proprietária é collection_layout.collection_id. PK collection_id ⇒ no máximo um fichário por convidada; uma proprietária nunca é convidada (gatilhos). Escrita só pelas RPCs attach/detach.';

alter table public.collection_layout_guest enable row level security;

create policy collection_layout_guest_select_own
  on public.collection_layout_guest for select
  using (exists (
    select 1 from public.collection c
    where c.id = collection_layout_guest.collection_id
      and c.owner_user_id = (select auth.uid())
  ));

grant select on public.collection_layout_guest to authenticated;
revoke truncate, references, trigger, maintain on public.collection_layout_guest from anon, authenticated;
revoke insert, update, delete on public.collection_layout_guest from public, anon, authenticated;

-- 2. Reservas com coleção (D8) --------------------------------------------------------
alter table public.collection_layout_slot_expected_content
  add column collection_id uuid null
      references public.collection(id) on update restrict on delete restrict;

create index ix_expected_content_collection
  on public.collection_layout_slot_expected_content (collection_id)
  where collection_id is not null;

comment on column public.collection_layout_slot_expected_content.collection_id is
  '5229 (C-196): coleção à qual a reserva pertence. NULL = proprietária do fichário (todas as reservas anteriores à 5229 e as da montagem automática 5224). Precisa ser participante do fichário do bolso (gatilho).';

-- 3. Gatilhos de integridade -----------------------------------------------------------
-- 3a. Convidada: imutável, mesmo dono da proprietária, sem fichário próprio.
create function public.enforce_collection_layout_guest_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_guest_owner uuid;
  v_layout_owner uuid;
begin
  if tg_op = 'UPDATE' then
    raise exception 'collection_layout_guest é imutável — desassocie e associe de novo';
  end if;

  select c.owner_user_id into v_guest_owner
  from public.collection c where c.id = new.collection_id
  for share;

  select c.owner_user_id into v_layout_owner
  from public.collection_layout l
  join public.collection c on c.id = l.collection_id
  where l.id = new.layout_id;

  if v_guest_owner is null or v_layout_owner is null
     or v_guest_owner is distinct from v_layout_owner then
    raise exception 'convidada e proprietária precisam ser do mesmo dono';
  end if;

  if exists (select 1 from public.collection_layout l where l.collection_id = new.collection_id) then
    raise exception 'COLLECTION_HAS_OWN_BINDER';
  end if;

  return new;
end;
$$;

create trigger trg_collection_layout_guest_integrity
  before insert or update on public.collection_layout_guest
  for each row execute function public.enforce_collection_layout_guest_integrity();

-- 3b. Proprietária nunca é convidada (lado do fichário próprio).
create function public.enforce_collection_layout_owner_not_guest()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform 1 from public.collection c where c.id = new.collection_id for share;
  if exists (select 1 from public.collection_layout_guest g where g.collection_id = new.collection_id) then
    raise exception 'COLLECTION_IS_BINDER_GUEST'
      using hint = 'a coleção já usa o fichário de outra coleção — desassocie antes de montar um próprio';
  end if;
  return new;
end;
$$;

create trigger trg_collection_layout_owner_not_guest
  before insert on public.collection_layout
  for each row execute function public.enforce_collection_layout_owner_not_guest();

-- 3c. Desmontagem bloqueada com convidadas (D7). A FK RESTRICT já impede;
--     o gatilho dá a mensagem estável.
create function public.enforce_collection_layout_delete_without_guests()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from public.collection_layout_guest g where g.layout_id = old.id) then
    raise exception 'BINDER_HAS_GUESTS'
      using hint = 'desassocie as outras coleções deste fichário antes de desmontá-lo';
  end if;
  return old;
end;
$$;

create trigger trg_collection_layout_delete_without_guests
  before delete on public.collection_layout
  for each row execute function public.enforce_collection_layout_delete_without_guests();

-- 3d. Reserva só de participante.
create function public.enforce_expected_content_participant()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_layout uuid;
  v_owner_collection uuid;
begin
  if new.collection_id is null then
    return new;
  end if;
  select l.id, l.collection_id into v_layout, v_owner_collection
  from public.collection_layout_slot s
  join public.collection_layout_page p on p.id = s.page_id
  join public.collection_layout l on l.id = p.layout_id
  where s.id = new.slot_id;

  if new.collection_id is distinct from v_owner_collection
     and not exists (select 1 from public.collection_layout_guest g
                     where g.collection_id = new.collection_id and g.layout_id = v_layout) then
    raise exception 'reserva de coleção que não participa deste fichário';
  end if;
  return new;
end;
$$;

create trigger trg_expected_content_participant
  before insert or update of collection_id, slot_id on public.collection_layout_slot_expected_content
  for each row execute function public.enforce_expected_content_participant();

do $rv$
declare f text;
begin
  foreach f in array array[
    'public.enforce_collection_layout_guest_integrity()',
    'public.enforce_collection_layout_owner_not_guest()',
    'public.enforce_collection_layout_delete_without_guests()',
    'public.enforce_expected_content_participant()'] loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f);
  end loop;
end;
$rv$;

-- 4. 5117 evoluída: posição aceita participante; convidada arquivada não muda --------
create or replace function public.enforce_collection_layout_slot_assignment_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_allocation_collection_id uuid;
  v_layout_id                uuid;
  v_layout_collection_id     uuid;
  v_status                   text;
begin
  -- §6 (5117) collection_allocation_id imutável.
  if tg_op = 'UPDATE'
     and new.collection_allocation_id is distinct from old.collection_allocation_id then
    raise exception
      'collection_allocation_id de uma Slot Assignment é IMUTÁVEL — use a operação REPLACE (assign_card_to_slot), que remove a Assignment antiga e cria uma nova; UPDATE direto contornaria o enforcement de Lock';
  end if;

  select ca.collection_id into v_allocation_collection_id
  from public.collection_allocation ca
  where ca.id = new.collection_allocation_id;
  if not found then
    raise exception 'collection_allocation_id % não existe', new.collection_allocation_id;
  end if;

  select l.id, l.collection_id into v_layout_id, v_layout_collection_id
  from public.collection_layout_slot s
  join public.collection_layout_page p on p.id = s.page_id
  join public.collection_layout l      on l.id = p.layout_id
  where s.id = new.slot_id;
  if not found then
    raise exception 'slot_id % não existe', new.slot_id;
  end if;

  if v_allocation_collection_id is distinct from v_layout_collection_id then
    -- 5229: convidada do MESMO fichário também pode ocupar bolsos.
    if not exists (select 1 from public.collection_layout_guest g
                   where g.collection_id = v_allocation_collection_id
                     and g.layout_id = v_layout_id) then
      raise exception
        'Physical Card não está alocada a uma coleção participante deste fichário — Slot Assignment exige alocação prévia à proprietária ou a uma convidada';
    end if;
    -- Convidada arquivada é somente leitura (C-37). Leitura SEM trava de
    -- propósito (AUDIT-CORRECTION-01): o gatilho roda depois de a posição
    -- já estar travada; travar a coleção aqui inverteria a ordem da 5047
    -- (coleção → alocação → posição em cascata) e formaria ciclo com
    -- move_slot_assignment (5132). A RPC de entrada (5131 evoluída) trava a
    -- convidada ANTES da alocação; move/troca ficam com esta checagem.
    select c.lifecycle_status into v_status
    from public.collection c where c.id = v_allocation_collection_id;
    if v_status <> 'ACTIVE' then
      raise exception 'COLLECTION_ARCHIVED'
        using hint = 'a coleção desta carta está arquivada — reative-a para organizar';
    end if;
  end if;

  return new;
end;
$$;

revoke execute on function public.enforce_collection_layout_slot_assignment_integrity()
  from public, anon, authenticated;

-- 5. 5131 evoluída: alocação escopada aos participantes ------------------------------
create or replace function public.assign_card_to_slot(
    p_slot_id                  uuid,
    p_collection_allocation_id uuid
)
returns table (
    assignment_id            uuid,
    slot_id                  uuid,
    collection_allocation_id uuid,
    operation                text,
    replaced_allocation_id   uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_layout_id             uuid;
    v_layout_collection_id  uuid;
    v_slot_locked           boolean;
    v_existing_assignment   uuid;
    v_replaced_allocation   uuid;
    v_operation             text;
    v_new_assignment_id     uuid;
    v_guest_collection_id   uuid;
    v_guest_status          text;
begin
    if (select auth.uid()) is null then
        raise exception 'authentication required';
    end if;

    -- 1) RESOLVE OWNER-SCOPED do Slot (pela proprietária).
    select p.layout_id
      into v_layout_id
      from public.collection_layout_slot s
      join public.collection_layout_page p on p.id = s.page_id
      join public.collection_layout l      on l.id = p.layout_id
      join public.collection c             on c.id = l.collection_id
     where s.id = p_slot_id
       and c.owner_user_id = (select auth.uid());

    if not found then
        raise exception 'layout slot not found or not owned by caller';
    end if;

    -- 2) COLLECTION (proprietária) LOCK -> LAYOUT LOCK + ACTIVE.
    begin
        v_layout_collection_id := public.assert_collection_layout_mutable(v_layout_id);
    exception
        when others then
            if sqlerrm like 'collection layout not found%' then
                raise exception 'layout slot not found or not owned by caller';
            end if;
            raise;
    end;

    -- 3) SLOT LOCK.
    perform 1
       from public.collection_layout_slot s
      where s.id = p_slot_id
      for update;

    -- 4) Revalidação pós-lock + leitura de `locked`.
    select s.locked
      into v_slot_locked
      from public.collection_layout_slot s
      join public.collection_layout_page p on p.id = s.page_id
     where s.id = p_slot_id
       and p.layout_id = v_layout_id;

    if not found then
        raise exception 'layout slot not found or not owned by caller';
    end if;

    if v_slot_locked then
        raise exception
            'Slot bloqueado (locked) — Add/Replace não permitido enquanto o Lock estiver ativo';
    end if;

    -- 5a) Convidada (AUDIT-CORRECTION-01): resolve a coleção da alocação
    -- SEM trava e, se for convidada deste layout, trava a convidada
    -- (FOR SHARE) e confere ACTIVE ANTES de travar a alocação — mesma ordem
    -- da 5047 (coleção → alocação), sem ciclo com a desalocação.
    select ca.collection_id into v_guest_collection_id
      from public.collection_allocation ca
      join public.collection_layout_guest g on g.collection_id = ca.collection_id
     where ca.id = p_collection_allocation_id
       and g.layout_id = v_layout_id;
    if v_guest_collection_id is not null then
        select c.lifecycle_status into v_guest_status
          from public.collection c
         where c.id = v_guest_collection_id
           and c.owner_user_id = (select auth.uid())
         for share;
        if not found then
            raise exception 'collection allocation not found or not owned by caller';
        end if;
        if v_guest_status <> 'ACTIVE' then
            raise exception 'COLLECTION_ARCHIVED'
              using hint = 'a coleção desta carta está arquivada — reative-a para organizar';
        end if;
    end if;

    -- 5) ALLOCATION ESCOPADA aos PARTICIPANTES do fichário (5229):
    -- proprietária ou convidada deste layout. Inexistente, de coleção não
    -- participante e de outro dono colapsam na MESMA mensagem.
    perform 1
       from public.collection_allocation ca
      where ca.id = p_collection_allocation_id
        and (ca.collection_id = v_layout_collection_id
             or exists (select 1 from public.collection_layout_guest g
                        where g.collection_id = ca.collection_id
                          and g.layout_id = v_layout_id))
      for update;

    if not found then
        raise exception 'collection allocation not found or not owned by caller';
    end if;

    -- 6) Revalidação pós-lock.
    perform 1
       from public.collection_allocation ca
      where ca.id = p_collection_allocation_id
        and (ca.collection_id = v_layout_collection_id
             or exists (select 1 from public.collection_layout_guest g
                        where g.collection_id = ca.collection_id
                          and g.layout_id = v_layout_id));

    if not found then
        raise exception 'collection allocation not found or not owned by caller';
    end if;

    -- 7) REPLACE / ADD (inalterado).
    select a.id, a.collection_allocation_id
      into v_existing_assignment, v_replaced_allocation
      from public.collection_layout_slot_assignment a
     where a.slot_id = p_slot_id
     for update;

    if found then
        if v_replaced_allocation = p_collection_allocation_id then
            raise exception 'no-op: esta Physical Card já ocupa este Slot';
        end if;
        delete from public.collection_layout_slot_assignment
         where id = v_existing_assignment;
        v_operation := 'REPLACE';
    else
        v_replaced_allocation := null;
        v_operation           := 'ADD';
    end if;

    begin
        insert into public.collection_layout_slot_assignment as a
            (slot_id, collection_allocation_id)
        values
            (p_slot_id, p_collection_allocation_id)
        returning a.id into v_new_assignment_id;
    exception
        when unique_violation then
            raise exception
                'esta Physical Card já possui Slot Assignment neste Layout — mova-a em vez de atribuí-la novamente';
    end;

    return query
    select a.id, a.slot_id, a.collection_allocation_id, v_operation, v_replaced_allocation
      from public.collection_layout_slot_assignment a
     where a.id = v_new_assignment_id;
end;
$$;

revoke execute on function public.assign_card_to_slot(uuid, uuid) from public, anon;
grant execute on function public.assign_card_to_slot(uuid, uuid) to authenticated;

-- 6. Reserva com coleção (5225 → 5229) -------------------------------------------------
drop function public.set_slot_expected_content(uuid, uuid, uuid, uuid);

create function public.set_slot_expected_content(
  p_slot_id                  uuid,
  p_card_id                  uuid,
  p_card_variant_id          uuid default null,
  p_expected_variant_type_id uuid default null,
  p_collection_id            uuid default null
)
returns table (
  slot_id                  uuid,
  card_id                  uuid,
  card_variant_id          uuid,
  expected_variant_type_id uuid,
  collection_id            uuid
)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_layout_id        uuid;
  v_owner_collection uuid;
  v_target           uuid;
  v_status           text;
begin
  if (select auth.uid()) is null then
    raise exception 'authentication required';
  end if;

  select p.layout_id into v_layout_id
    from public.collection_layout_slot s
    join public.collection_layout_page p on p.id = s.page_id
    join public.collection_layout l      on l.id = p.layout_id
    join public.collection c             on c.id = l.collection_id
   where s.id = p_slot_id
     and c.owner_user_id = (select auth.uid());
  if not found then
    raise exception 'layout slot not found or not owned by caller';
  end if;

  begin
    v_owner_collection := public.assert_collection_layout_mutable(v_layout_id);
  exception
    when others then
      if sqlerrm like 'collection layout not found%' then
        raise exception 'layout slot not found or not owned by caller';
      end if;
      raise;
  end;

  perform 1 from public.collection_layout_slot s where s.id = p_slot_id for update;

  perform 1
     from public.collection_layout_slot s
     join public.collection_layout_page p on p.id = s.page_id
    where s.id = p_slot_id and p.layout_id = v_layout_id;
  if not found then
    raise exception 'layout slot not found or not owned by caller';
  end if;

  if p_card_id is null then
    raise exception 'p_card_id é obrigatório';
  end if;
  if p_card_variant_id is not null and p_expected_variant_type_id is not null then
    raise exception 'EXPECTED_CONTENT_VARIANT_AND_TYPE_EXCLUSIVE: informe a variante específica OU o acabamento, não os dois'
      using errcode = '22023';
  end if;

  -- D8: a reserva pertence a p_collection_id; sem ele, à coleção da carta
  -- que ocupa o bolso; sem carta, à proprietária.
  v_target := p_collection_id;
  if v_target is null then
    select ca.collection_id into v_target
    from public.collection_layout_slot_assignment a
    join public.collection_allocation ca on ca.id = a.collection_allocation_id
    where a.slot_id = p_slot_id;
  end if;
  v_target := coalesce(v_target, v_owner_collection);

  if v_target <> v_owner_collection then
    -- Convidada deste fichário, do mesmo dono, ativa (mesma mensagem para
    -- não participante, inexistente ou alheia).
    select c.lifecycle_status into v_status
    from public.collection_layout_guest g
    join public.collection c on c.id = g.collection_id
    where g.collection_id = v_target and g.layout_id = v_layout_id
      and c.owner_user_id = (select auth.uid())
    for share of c;
    if not found then
      raise exception 'collection not found or not a participant of this binder';
    end if;
    if v_status <> 'ACTIVE' then
      raise exception 'COLLECTION_ARCHIVED';
    end if;
  end if;

  begin
    insert into public.collection_layout_slot_expected_content as ec
      (slot_id, card_id, card_variant_id, expected_variant_type_id, collection_id)
    values
      (p_slot_id, p_card_id, p_card_variant_id, p_expected_variant_type_id, v_target)
    on conflict on constraint collection_layout_slot_expected_content_pkey
    do update set card_id                  = excluded.card_id,
                  card_variant_id          = excluded.card_variant_id,
                  expected_variant_type_id = excluded.expected_variant_type_id,
                  collection_id            = excluded.collection_id;
  exception
    when foreign_key_violation then
      raise exception
        'Card/Card Variant/acabamento inválido — quando informada, a Card Variant deve pertencer à Card indicada e o acabamento deve existir';
  end;

  return query
  select e.slot_id, e.card_id, e.card_variant_id, e.expected_variant_type_id, e.collection_id
    from public.collection_layout_slot_expected_content e
   where e.slot_id = p_slot_id;
end;
$$;

comment on function public.set_slot_expected_content(uuid, uuid, uuid, uuid, uuid) is
  '5128 → 5225 → 5229: conteúdo planejado de um bolso — carta; carta + variante; ou carta + acabamento (exclusivos) — e a coleção dona da reserva (p_collection_id; senão a da carta no bolso; senão a proprietária). Participante e ACTIVE exigidos; não enumera.';

revoke all on function public.set_slot_expected_content(uuid, uuid, uuid, uuid, uuid) from public;
revoke all on function public.set_slot_expected_content(uuid, uuid, uuid, uuid, uuid) from anon;
grant execute on function public.set_slot_expected_content(uuid, uuid, uuid, uuid, uuid) to authenticated;

-- 7. delete_collection (5226 → 5229): convidada desassocia antes -----------------------
create or replace function public.delete_collection(p_collection_id uuid)
returns table (id uuid)
language plpgsql
security definer
set search_path = ''
as $$
begin
    if auth.uid() is null then
        raise exception 'authentication required';
    end if;

    perform 1
    from public.collection col
    where col.id = p_collection_id
      and col.owner_user_id = auth.uid()
    for update;
    if not found then
        raise exception 'collection not found or not owned by caller';
    end if;

    if exists (select 1 from public.collection_allocation ca where ca.collection_id = p_collection_id) then
        raise exception 'collection has allocated physical cards — deallocate them before deleting';
    end if;

    if exists (select 1 from public.collection_layout l where l.collection_id = p_collection_id) then
        raise exception 'collection has a digital binder — dismantle it before deleting'
            using hint = 'BINDER_EXISTS';
    end if;

    -- 5229: convidada de um fichário compartilhado.
    if exists (select 1 from public.collection_layout_guest g where g.collection_id = p_collection_id) then
        raise exception 'collection uses a shared digital binder — detach it before deleting'
            using hint = 'BINDER_GUEST';
    end if;

    return query
    delete from public.collection
    where collection.id = p_collection_id and collection.owner_user_id = auth.uid()
    returning collection.id;

    if not found then
        raise exception 'collection not found or not owned by caller';
    end if;
end;
$$;

revoke execute on function public.delete_collection(uuid) from public, anon;
grant execute on function public.delete_collection(uuid) to authenticated;

-- 7b. Desmontagem (5226 → 5229, AUDIT-CORRECTION-01) -----------------------------------
-- A recusa acontece ANTES de qualquer remoção, sob as mesmas travas da 5226
-- (coleção → layout); attach também trava a proprietária primeiro, então a
-- leitura de convidadas sob a trava é definitiva. O gatilho de DELETE do
-- layout (§3c) continua como segunda barreira. Convidada que tenta
-- "desmontar" recebe orientação para desassociar (não ALREADY_ABSENT).
drop function public.preview_my_collection_binder_dismantle(uuid);

create function public.preview_my_collection_binder_dismantle(p_collection_id uuid)
returns table (
  collection_id      uuid,
  lifecycle_status   text,
  has_binder         boolean,
  layout_id          uuid,
  grid_columns       integer,
  grid_rows          integer,
  pages_count        integer,
  slots_count        integer,
  locked_count       integer,
  assignments_count  integer,
  reservations_count integer,
  regions_count      integer,
  dismantle_token    text,
  guest_count        integer,   -- 5229: convidadas do fichário
  blocked_reason     text       -- 5229: null | BINDER_HAS_GUESTS | COLLECTION_IS_BINDER_GUEST
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid    uuid := auth.uid();
  v_status text;
  r        record;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  select c.lifecycle_status into v_status
  from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  select * into r from public.collection_binder_dismantle_snapshot(p_collection_id);

  collection_id    := p_collection_id;
  lifecycle_status := v_status;
  has_binder       := r.layout_id is not null;
  guest_count      := 0;
  if has_binder then
    layout_id          := r.layout_id;
    grid_columns       := r.grid_columns;
    grid_rows          := r.grid_rows;
    pages_count        := r.pages_count;
    slots_count        := r.slots_count;
    locked_count       := r.locked_count;
    assignments_count  := r.assignments_count;
    reservations_count := r.reservations_count;
    regions_count      := r.regions_count;
    dismantle_token    := r.dismantle_token;
    select count(*)::integer into guest_count
    from public.collection_layout_guest g where g.layout_id = r.layout_id;
    if guest_count > 0 then
      blocked_reason := 'BINDER_HAS_GUESTS';
    end if;
  elsif exists (select 1 from public.collection_layout_guest g where g.collection_id = p_collection_id) then
    blocked_reason := 'COLLECTION_IS_BINDER_GUEST';
  end if;
  return next;
end;
$$;

comment on function public.preview_my_collection_binder_dismantle(uuid) is
  'Fichário Digital (5226 → 5229): prévia da desmontagem — páginas, bolsos, travados, posições, reservas, mesclagens, token — e, desde a 5229, guest_count e blocked_reason (BINDER_HAS_GUESTS: desassocie as convidadas antes; COLLECTION_IS_BINDER_GUEST: esta coleção usa o fichário de outra — desassocie-a). Não grava nada; não enumera.';

revoke all on function public.preview_my_collection_binder_dismantle(uuid) from public;
revoke all on function public.preview_my_collection_binder_dismantle(uuid) from anon;
grant execute on function public.preview_my_collection_binder_dismantle(uuid) to authenticated;

create or replace function public.dismantle_my_collection_binder(
  p_collection_id   uuid,
  p_dismantle_token text
)
returns table (
  outcome              text,
  pages_removed        integer,
  slots_removed        integer,
  assignments_removed  integer,
  reservations_removed integer,
  regions_removed      integer,
  locks_released       integer
)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
#variable_conflict use_column
declare
  v_uid     uuid := auth.uid();
  v_layout  uuid;
  r         record;
  v_unlock  integer;
  v_asg     integer;
  v_exc     integer;
  v_rg      integer;
  v_pg      integer;
  v_left    integer;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  if p_dismantle_token is null or p_dismantle_token !~ '^d1:[0-9a-f]{64}$' then
    raise exception 'INVALID_DISMANTLE_TOKEN' using errcode = '22023';
  end if;

  perform 1
  from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_uid
  for update;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  select l.id into v_layout
  from public.collection_layout l
  where l.collection_id = p_collection_id
  for update;
  if v_layout is null then
    -- 5229: convidada não "desmonta" o fichário de outra coleção.
    if exists (select 1 from public.collection_layout_guest g where g.collection_id = p_collection_id) then
      raise exception 'COLLECTION_IS_BINDER_GUEST'
        using hint = 'esta coleção usa o fichário de outra coleção — desassocie-a em vez de desmontar';
    end if;
    outcome := 'ALREADY_ABSENT';
    pages_removed := 0; slots_removed := 0; assignments_removed := 0;
    reservations_removed := 0; regions_removed := 0; locks_released := 0;
    return next;
    return;
  end if;

  -- 5229 (D7): recusa ANTES de qualquer remoção, sob a trava do layout.
  if exists (select 1 from public.collection_layout_guest g where g.layout_id = v_layout) then
    raise exception 'BINDER_HAS_GUESTS'
      using hint = 'desassocie as outras coleções deste fichário antes de desmontá-lo';
  end if;

  select * into r from public.collection_binder_dismantle_snapshot(p_collection_id);
  if r.dismantle_token is distinct from p_dismantle_token then
    raise exception 'DISMANTLE_PLAN_CHANGED';
  end if;

  update public.collection_layout_slot s
     set locked = false
   where s.locked
     and s.page_id in (select p.id from public.collection_layout_page p where p.layout_id = v_layout);
  get diagnostics v_unlock = row_count;

  delete from public.collection_layout_slot_assignment a
   using public.collection_layout_slot s, public.collection_layout_page p
   where a.slot_id = s.id and s.page_id = p.id and p.layout_id = v_layout;
  get diagnostics v_asg = row_count;

  delete from public.collection_layout_slot_expected_content e
   using public.collection_layout_slot s, public.collection_layout_page p
   where e.slot_id = s.id and s.page_id = p.id and p.layout_id = v_layout;
  get diagnostics v_exc = row_count;

  delete from public.collection_layout_region rg
   using public.collection_layout_page p
   where rg.page_id = p.id and p.layout_id = v_layout;
  get diagnostics v_rg = row_count;

  delete from public.collection_layout_page p where p.layout_id = v_layout;
  get diagnostics v_pg = row_count;

  delete from public.collection_layout l where l.id = v_layout;

  select count(*)::integer into v_left
  from public.collection_layout l where l.collection_id = p_collection_id;

  if v_left <> 0
     or v_unlock <> r.locked_count
     or v_asg <> r.assignments_count
     or v_exc <> r.reservations_count
     or v_rg <> r.regions_count
     or v_pg <> r.pages_count then
    raise exception 'BINDER_DISMANTLE_INCONSISTENT';
  end if;

  outcome              := 'DISMANTLED';
  pages_removed        := v_pg;
  slots_removed        := r.slots_count;
  assignments_removed  := v_asg;
  reservations_removed := v_exc;
  regions_removed      := v_rg;
  locks_released       := v_unlock;
  return next;
end;
$$;

revoke all on function public.dismantle_my_collection_binder(uuid, text) from public;
revoke all on function public.dismantle_my_collection_binder(uuid, text) from anon;
grant execute on function public.dismantle_my_collection_binder(uuid, text) to authenticated;

-- 8. Associar (D1, D3, D9) --------------------------------------------------------------
create function public.attach_my_collection_to_binder(
  p_collection_id uuid,
  p_layout_id     uuid
)
returns table (
  outcome             text,    -- ATTACHED | ALREADY_ATTACHED
  layout_id           uuid,
  owner_collection_id uuid
)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
#variable_conflict use_column
declare
  v_uid        uuid := auth.uid();
  v_owner_coll uuid;
  v_status     text;
  v_default    uuid;
  v_kind       text;
  v_current    uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null or p_layout_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  -- 1. Fichário pelo dono (sem trava): inexistente e alheio no mesmo ramo.
  select l.collection_id into v_owner_coll
  from public.collection_layout l
  join public.collection c on c.id = l.collection_id
  where l.id = p_layout_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_owner_coll = p_collection_id then
    raise exception 'BINDER_SELF' using errcode = '22023';
  end if;

  -- 2. Proprietária → layout (trava + ACTIVE), ordem canônica (5122).
  begin
    perform public.assert_collection_layout_mutable(p_layout_id);
  exception
    when others then
      if sqlerrm like 'collection layout not found%' then
        raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
      end if;
      if sqlerrm like 'collection is ARCHIVED%' then
        raise exception 'BINDER_ARCHIVED';
      end if;
      raise;
  end;

  -- 3. Convidada (trava).
  select c.lifecycle_status, c.default_storage_container_id into v_status, v_default
  from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_uid
  for update;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_status <> 'ACTIVE' then
    raise exception 'COLLECTION_ARCHIVED';
  end if;

  -- 4. Idempotência e participação única (D-única).
  select g.layout_id into v_current
  from public.collection_layout_guest g where g.collection_id = p_collection_id;
  if v_current is not null then
    if v_current = p_layout_id then
      outcome := 'ALREADY_ATTACHED'; layout_id := p_layout_id; owner_collection_id := v_owner_coll;
      return next;
      return;
    end if;
    raise exception 'COLLECTION_ALREADY_IN_BINDER';
  end if;
  if exists (select 1 from public.collection_layout l where l.collection_id = p_collection_id) then
    raise exception 'COLLECTION_HAS_OWN_BINDER';
  end if;

  -- 5. Local físico (D9): o local padrão da convidada é um fichário e é o
  --    local padrão de algum participante deste fichário.
  if v_default is not null then
    select sc.kind_code::text into v_kind
    from public.storage_container sc
    join public.inventory i on i.id = sc.inventory_id
    where sc.id = v_default and i.owner_user_id = v_uid;
  end if;
  if v_kind is distinct from 'BINDER'
     or not exists (
       select 1 from public.collection pc
       where pc.owner_user_id = v_uid
         and pc.default_storage_container_id = v_default
         and (pc.id = v_owner_coll
              or exists (select 1 from public.collection_layout_guest g
                         where g.layout_id = p_layout_id and g.collection_id = pc.id))) then
    raise exception 'NOT_SAME_LOCATION'
      using hint = 'escolha como local padrão o mesmo fichário físico das coleções deste fichário';
  end if;

  -- 6. Associação: nenhum bolso, reserva ou carta é tocado (D3).
  insert into public.collection_layout_guest (collection_id, layout_id)
  values (p_collection_id, p_layout_id);

  outcome := 'ATTACHED'; layout_id := p_layout_id; owner_collection_id := v_owner_coll;
  return next;
end;
$$;

comment on function public.attach_my_collection_to_binder(uuid, uuid) is
  '5229 (C-195): associa explicitamente uma coleção ATIVA, sem fichário próprio e sem outra associação, como convidada do fichário de outra coleção do mesmo dono, guardada no mesmo fichário físico. Não escreve bolso, reserva nem alocação. Idempotente (ALREADY_ATTACHED). Trava proprietária → layout → convidada; lock_timeout 5s.';

revoke all on function public.attach_my_collection_to_binder(uuid, uuid) from public;
revoke all on function public.attach_my_collection_to_binder(uuid, uuid) from anon;
grant execute on function public.attach_my_collection_to_binder(uuid, uuid) to authenticated;

-- 9. Desassociar (D5, D6) ----------------------------------------------------------------
-- 9a. Retrato interno do que a desassociação remove (padrão 5226).
create function public.collection_binder_detach_snapshot(p_collection_id uuid)
returns table (
  layout_id           uuid,
  owner_collection_id uuid,
  assignments_count   integer,
  reservations_count  integer,
  locked_count        integer,
  detach_token        text
)
language sql
stable
security invoker
set search_path = ''
as $$
  with g as (
    select x.layout_id from public.collection_layout_guest x where x.collection_id = p_collection_id
  ),
  sl as (
    select s.id, s.locked
    from g
    join public.collection_layout_page p on p.layout_id = g.layout_id
    join public.collection_layout_slot s on s.page_id = p.id
  ),
  asg as (
    select a.slot_id, a.collection_allocation_id
    from public.collection_layout_slot_assignment a
    join sl on sl.id = a.slot_id
    join public.collection_allocation ca on ca.id = a.collection_allocation_id
    where ca.collection_id = p_collection_id
  ),
  exc as (
    select e.slot_id, e.card_id, e.card_variant_id, e.expected_variant_type_id
    from public.collection_layout_slot_expected_content e
    join sl on sl.id = e.slot_id
    where e.collection_id = p_collection_id
  ),
  lk as (
    select sl.id from sl
    where sl.locked and (sl.id in (select asg.slot_id from asg) or sl.id in (select exc.slot_id from exc))
  ),
  ser as (
    select
      'G|' || p_collection_id || '|' || coalesce((select g.layout_id::text from g), '-')
      || E'\nA|' || coalesce((select string_agg(asg.slot_id || ':' || asg.collection_allocation_id, ',' order by asg.slot_id) from asg), '')
      || E'\nE|' || coalesce((select string_agg(exc.slot_id || ':' || exc.card_id || ':' || coalesce(exc.card_variant_id::text, '-') || ':' || coalesce(exc.expected_variant_type_id::text, '-'), ',' order by exc.slot_id) from exc), '')
      || E'\nK|' || coalesce((select string_agg(lk.id::text, ',' order by lk.id) from lk), '')
      as s
  )
  select g.layout_id,
         (select l.collection_id from public.collection_layout l where l.id = g.layout_id),
         (select count(*) from asg)::integer,
         (select count(*) from exc)::integer,
         (select count(*) from lk)::integer,
         'g1:' || encode(sha256(convert_to(ser.s, 'UTF8')), 'hex')
  from g cross join ser;
$$;

revoke all on function public.collection_binder_detach_snapshot(uuid) from public, anon, authenticated, service_role;

-- 9b. Prévia.
create function public.preview_my_collection_binder_detach(p_collection_id uuid)
returns table (
  layout_id             uuid,
  owner_collection_id   uuid,
  owner_collection_name text,
  assignments_count     integer,
  reservations_count    integer,
  locked_count          integer,
  detach_token          text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  perform 1 from public.collection c where c.id = p_collection_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  return query
  select s.layout_id, s.owner_collection_id, oc.name::text,
         s.assignments_count, s.reservations_count, s.locked_count, s.detach_token
  from public.collection_binder_detach_snapshot(p_collection_id) s
  join public.collection oc on oc.id = s.owner_collection_id;
end;
$$;

comment on function public.preview_my_collection_binder_detach(uuid) is
  '5229 (C-197): prévia da desassociação de uma convidada — quantas cartas dela saem dos bolsos, quantas reservas dela são liberadas, quantos bolsos fixados seriam soltos — e o token a confirmar. Sem linha = a coleção não é convidada.';

revoke all on function public.preview_my_collection_binder_detach(uuid) from public;
revoke all on function public.preview_my_collection_binder_detach(uuid) from anon;
grant execute on function public.preview_my_collection_binder_detach(uuid) to authenticated;

-- 9c. Desassociação.
create function public.detach_my_collection_from_binder(
  p_collection_id uuid,
  p_detach_token  text,
  p_release_locks boolean default false
)
returns table (
  outcome              text,     -- DETACHED | ALREADY_DETACHED
  assignments_removed  integer,
  reservations_removed integer,
  locks_released       integer
)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
#variable_conflict use_column
declare
  v_uid    uuid := auth.uid();
  v_layout uuid;
  v_owner  uuid;
  r        record;
  v_unlock integer := 0;
  v_asg    integer;
  v_exc    integer;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  if p_detach_token is null or p_detach_token !~ '^g1:[0-9a-f]{64}$' then
    raise exception 'INVALID_DETACH_TOKEN' using errcode = '22023';
  end if;

  perform 1 from public.collection c where c.id = p_collection_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  select g.layout_id, l.collection_id into v_layout, v_owner
  from public.collection_layout_guest g
  join public.collection_layout l on l.id = g.layout_id
  where g.collection_id = p_collection_id;
  if v_layout is null then
    outcome := 'ALREADY_DETACHED'; assignments_removed := 0; reservations_removed := 0; locks_released := 0;
    return next;
    return;
  end if;

  -- Ordem canônica: proprietária → layout → convidada. Qualquer lifecycle
  -- (desfazer participação é permitido mesmo arquivada, como a 5226).
  perform 1 from public.collection c where c.id = v_owner and c.owner_user_id = v_uid for update;
  perform 1 from public.collection_layout l where l.id = v_layout for update;
  perform 1 from public.collection c where c.id = p_collection_id for update;

  if not exists (select 1 from public.collection_layout_guest g
                 where g.collection_id = p_collection_id and g.layout_id = v_layout) then
    outcome := 'ALREADY_DETACHED'; assignments_removed := 0; reservations_removed := 0; locks_released := 0;
    return next;
    return;
  end if;

  select * into r from public.collection_binder_detach_snapshot(p_collection_id);
  if r.detach_token is distinct from p_detach_token then
    raise exception 'DETACH_PLAN_CHANGED';
  end if;

  if r.locked_count > 0 and not coalesce(p_release_locks, false) then
    raise exception 'LOCKED_SLOTS_REQUIRE_CONFIRMATION'
      using hint = 'confirme soltar os bolsos fixados com cartas ou reservas desta coleção';
  end if;

  -- D6: solta só os bolsos fixados afetados.
  update public.collection_layout_slot s
     set locked = false
   where s.locked
     and s.page_id in (select p.id from public.collection_layout_page p where p.layout_id = v_layout)
     and (exists (select 1 from public.collection_layout_slot_assignment a
                  join public.collection_allocation ca on ca.id = a.collection_allocation_id
                  where a.slot_id = s.id and ca.collection_id = p_collection_id)
          or exists (select 1 from public.collection_layout_slot_expected_content e
                     where e.slot_id = s.id and e.collection_id = p_collection_id));
  get diagnostics v_unlock = row_count;

  -- D5: só posições e reservas da convidada.
  delete from public.collection_layout_slot_assignment a
   using public.collection_allocation ca, public.collection_layout_slot s, public.collection_layout_page p
   where ca.id = a.collection_allocation_id and ca.collection_id = p_collection_id
     and s.id = a.slot_id and p.id = s.page_id and p.layout_id = v_layout;
  get diagnostics v_asg = row_count;

  delete from public.collection_layout_slot_expected_content e
   using public.collection_layout_slot s, public.collection_layout_page p
   where e.collection_id = p_collection_id
     and s.id = e.slot_id and p.id = s.page_id and p.layout_id = v_layout;
  get diagnostics v_exc = row_count;

  delete from public.collection_layout_guest g where g.collection_id = p_collection_id;

  if v_asg <> r.assignments_count or v_exc <> r.reservations_count or v_unlock <> r.locked_count then
    raise exception 'BINDER_DETACH_INCONSISTENT';
  end if;

  outcome := 'DETACHED'; assignments_removed := v_asg; reservations_removed := v_exc; locks_released := v_unlock;
  return next;
end;
$$;

comment on function public.detach_my_collection_from_binder(uuid, text, boolean) is
  '5229 (C-197): desassocia uma convidada do fichário compartilhado — remove só as posições das cartas dela e as reservas dela; solta bolsos fixados afetados apenas com p_release_locks = true; não altera alocações nem progresso. Token da prévia obrigatório (DETACH_PLAN_CHANGED). Idempotente (ALREADY_DETACHED). Trava proprietária → layout → convidada; lock_timeout 5s.';

revoke all on function public.detach_my_collection_from_binder(uuid, text, boolean) from public;
revoke all on function public.detach_my_collection_from_binder(uuid, text, boolean) from anon;
grant execute on function public.detach_my_collection_from_binder(uuid, text, boolean) to authenticated;

notify pgrst, 'reload schema';

commit;

/*
Reversão (só antes de qualquer associação real):
  begin;
  -- exige zero linhas em collection_layout_guest e expected_content.collection_id
  drop function public.detach_my_collection_from_binder(uuid, text, boolean);
  drop function public.preview_my_collection_binder_detach(uuid);
  drop function public.collection_binder_detach_snapshot(uuid);
  drop function public.attach_my_collection_to_binder(uuid, uuid);
  -- reaplicar os corpos canônicos de 5117, 5131, 5225 (§6) e 5226
  -- (delete_collection, preview_my_collection_binder_dismantle — DROP+CREATE —
  -- e dismantle_my_collection_binder)
  drop trigger trg_expected_content_participant on public.collection_layout_slot_expected_content;
  drop trigger trg_collection_layout_delete_without_guests on public.collection_layout;
  drop trigger trg_collection_layout_owner_not_guest on public.collection_layout;
  drop function public.enforce_expected_content_participant();
  drop function public.enforce_collection_layout_delete_without_guests();
  drop function public.enforce_collection_layout_owner_not_guest();
  alter table public.collection_layout_slot_expected_content drop column collection_id;
  drop table public.collection_layout_guest;   -- leva o gatilho de integridade
  drop function public.enforce_collection_layout_guest_integrity();
  commit;
  -- Aplicar a reversão da 5230 ANTES desta.

Como validar: harness 5851 (Seções 0–8 e 99).
*/
