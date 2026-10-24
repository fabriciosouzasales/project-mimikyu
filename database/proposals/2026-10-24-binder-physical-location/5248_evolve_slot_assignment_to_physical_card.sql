/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5248 - Posição pelo exemplar físico
              collection_layout_slot_assignment.physical_card_id
Versão......: 1.1 (2026-10-24, BINDER-PHYSICAL-LOCATION-IMPLEMENTATION-READINESS-01)
Status......: PROPOSTA — NÃO EXECUTADA. Fase A, depois da 5247 (README §6).
v1.1: inserção só com o exemplar (5250) grava também a alocação vigente
      (compatibilidade das leituras antigas durante a implantação).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-24

Antes: a posição apontava para a alocação (exemplar × coleção), NOT NULL,
ON DELETE CASCADE, e o gatilho exigia coleção participante e ACTIVE.
Depois:
  - physical_card_id NOT NULL, UNIQUE (um exemplar ocupa no máximo um bolso
    em todo o sistema), FK → physical_card ON DELETE CASCADE (exemplar que sai
    do acervo sai do bolso).
  - collection_allocation_id passa a ser legado: NULL permitido, FK
    ON DELETE SET NULL (trocar/tirar de coleção NÃO apaga a posição — D1/D2,
    princípio 3). A origem exibida é sempre lida pelo exemplar → alocação
    atual, nunca por esta coluna.
  - Escritores antigos (5224 montagem, 5229 assign_card_to_slot) continuam
    funcionando: inserção só com alocação preenche physical_card_id.
  - Gatilho de integridade (substitui 5117/5229): exemplar do MESMO dono do
    fichário e GUARDADO no local físico do fichário (5247). A coleção do
    exemplar não importa (pode ser outra, nenhuma ou arquivada — D1).
  - Trava (5118): a exclusão em cascata pelo exemplar passa a ser liberada
    como já era pela alocação.
Backfill das 155 posições a partir da alocação, sem mexer em updated_at.
Nenhuma posição muda de bolso.
Dependências: 5115, 5116, 5117/5229, 5118, 5247.
================================================================
*/

begin;

set local lock_timeout = '5s';

do $pre$
begin
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'collection_layout'
                   and column_name = 'storage_container_id') then
    raise exception 'PRECHECK 5248: aplique a 5247 antes';
  end if;
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'collection_layout_slot_assignment'
               and column_name = 'physical_card_id') then
    raise exception 'PRECHECK 5248: physical_card_id já existe';
  end if;
  if (select count(*) from pg_trigger
      where tgrelid = 'public.collection_layout_slot_assignment'::regclass
        and tgname in ('trg_collection_layout_slot_assignment_integrity',
                       'trg_collection_layout_slot_assignment_lock',
                       'trg_collection_layout_slot_assignment_updated_at')) <> 3 then
    raise exception 'PRECHECK 5248: gatilhos 5116/5117/5118 esperados não encontrados';
  end if;
  -- Toda posição atual está no local físico do seu fichário (senão o backfill quebraria a regra nova).
  if exists (
    select 1
    from public.collection_layout_slot_assignment a
    join public.collection_allocation ca on ca.id = a.collection_allocation_id
    join public.physical_card pc         on pc.id = ca.physical_card_id
    join public.collection_layout_slot s on s.id = a.slot_id
    join public.collection_layout_page p on p.id = s.page_id
    join public.collection_layout l      on l.id = p.layout_id
    where pc.storage_container_id is distinct from l.storage_container_id
  ) then
    raise exception 'PRECHECK 5248: há carta posicionada fora do local físico do fichário — decidir antes de aplicar';
  end if;
end;
$pre$;

-- 1. Gatilho de integridade (versão física) — antes do backfill, que o exercita ---
create or replace function public.enforce_collection_layout_slot_assignment_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_alloc_pc       uuid;
  v_layout_owner   uuid;
  v_container      uuid;
  v_card_owner     uuid;
  v_card_container uuid;
begin
  -- Escritores legados (5224, 5229): só a alocação → o exemplar vem dela.
  if tg_op = 'INSERT' and new.physical_card_id is null and new.collection_allocation_id is not null then
    select ca.physical_card_id into new.physical_card_id
    from public.collection_allocation ca where ca.id = new.collection_allocation_id;
  end if;
  -- Escritor novo (5250): só o exemplar → grava a alocação vigente (ou NULL).
  -- Mantém corretas, durante a implantação, as leituras antigas (5230) que
  -- ainda reconhecem "posicionado" pela alocação (README §6, compatibilidade).
  if tg_op = 'INSERT' and new.collection_allocation_id is null and new.physical_card_id is not null then
    select ca.id into new.collection_allocation_id
    from public.collection_allocation ca where ca.physical_card_id = new.physical_card_id;
  end if;

  if tg_op = 'UPDATE' then
    if old.physical_card_id is not null
       and new.physical_card_id is distinct from old.physical_card_id then
      raise exception
        'physical_card_id de uma posição é IMUTÁVEL — remova e posicione de novo';
    end if;
    if new.collection_allocation_id is distinct from old.collection_allocation_id
       and new.collection_allocation_id is not null then
      raise exception
        'collection_allocation_id é legado: só pode virar NULL (alocação desfeita)';
    end if;
    -- Nada que mude elegibilidade (ex.: alocação → NULL, updated_at): sem revalidar.
    if old.physical_card_id is not null and new.slot_id is not distinct from old.slot_id then
      return new;
    end if;
  end if;

  if new.physical_card_id is null then
    raise exception 'physical_card_id é obrigatório';
  end if;

  if new.collection_allocation_id is not null then
    select ca.physical_card_id into v_alloc_pc
    from public.collection_allocation ca where ca.id = new.collection_allocation_id;
    if v_alloc_pc is distinct from new.physical_card_id then
      raise exception 'collection_allocation_id não pertence a este exemplar';
    end if;
  end if;

  select c.owner_user_id, l.storage_container_id into v_layout_owner, v_container
  from public.collection_layout_slot s
  join public.collection_layout_page p on p.id = s.page_id
  join public.collection_layout l      on l.id = p.layout_id
  join public.collection c             on c.id = l.collection_id
  where s.id = new.slot_id;
  if not found then
    raise exception 'slot_id % não existe', new.slot_id;
  end if;

  select i.owner_user_id, pc.storage_container_id into v_card_owner, v_card_container
  from public.physical_card pc
  join public.inventory i on i.id = pc.inventory_id
  where pc.id = new.physical_card_id;

  -- Inexistente e de outro dono colapsam na mesma mensagem (não enumera).
  if v_card_owner is null or v_card_owner is distinct from v_layout_owner then
    raise exception 'PHYSICAL_CARD_NOT_FOUND' using errcode = 'P0002';
  end if;

  if v_card_container is distinct from v_container then
    raise exception 'CARD_NOT_IN_BINDER_LOCATION'
      using errcode = '55000',
            hint = 'só exemplares guardados neste fichário físico podem ocupar seus bolsos';
  end if;

  return new;
end;
$$;

revoke all on function public.enforce_collection_layout_slot_assignment_integrity() from public, anon, authenticated;

-- 2. Trava (5118): cascata pelo exemplar é liberada ------------------------------
create or replace function public.enforce_collection_layout_slot_lock()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_locked boolean;
begin
  if tg_op = 'DELETE' then
    -- Exemplar removido do acervo (cascata 5248): a posição sai junto.
    if old.physical_card_id is not null
       and not exists (select 1 from public.physical_card pc where pc.id = old.physical_card_id) then
      return old;
    end if;
    -- Legado: alocação já desfeita (antes da 5248 era cascata).
    if old.physical_card_id is null
       and not exists (select 1 from public.collection_allocation ca where ca.id = old.collection_allocation_id) then
      return old;
    end if;
    select s.locked into v_locked from public.collection_layout_slot s where s.id = old.slot_id;
    if coalesce(v_locked, false) then
      raise exception 'Slot bloqueado (locked) — Remove/Bandeja não permitido enquanto o Lock estiver ativo';
    end if;
    return old;
  end if;

  if tg_op = 'UPDATE' then
    if new.slot_id is distinct from old.slot_id then
      select s.locked into v_locked from public.collection_layout_slot s where s.id = old.slot_id;
      if coalesce(v_locked, false) then
        raise exception 'Slot de origem bloqueado (locked) — Move/Swap não permitido';
      end if;
      select s.locked into v_locked from public.collection_layout_slot s where s.id = new.slot_id;
      if coalesce(v_locked, false) then
        raise exception 'Slot de destino bloqueado (locked) — Move/Swap não permitido';
      end if;
    end if;
    return new;
  end if;

  select s.locked into v_locked from public.collection_layout_slot s where s.id = new.slot_id;
  if coalesce(v_locked, false) then
    raise exception 'Slot bloqueado (locked) — Add/Replace não permitido enquanto o Lock estiver ativo';
  end if;
  return new;
end;
$$;

revoke all on function public.enforce_collection_layout_slot_lock() from public, anon, authenticated;

-- 3. Coluna + backfill (sem mexer em updated_at; nenhuma posição muda de bolso) ---
alter table public.collection_layout_slot_assignment add column physical_card_id uuid;

alter table public.collection_layout_slot_assignment disable trigger trg_collection_layout_slot_assignment_updated_at;

update public.collection_layout_slot_assignment a
   set physical_card_id = ca.physical_card_id
  from public.collection_allocation ca
 where ca.id = a.collection_allocation_id;

alter table public.collection_layout_slot_assignment enable trigger trg_collection_layout_slot_assignment_updated_at;

alter table public.collection_layout_slot_assignment
  alter column physical_card_id set not null,
  add constraint fk_collection_layout_slot_assignment_physical_card
    foreign key (physical_card_id) references public.physical_card(id)
    on update restrict on delete cascade,
  add constraint uq_collection_layout_slot_assignment_physical_card unique (physical_card_id);

-- 4. Alocação vira legado: NULL permitido, SET NULL na exclusão ------------------
do $fk$
declare
  v_name text;
begin
  select con.conname into v_name
  from pg_constraint con
  where con.conrelid = 'public.collection_layout_slot_assignment'::regclass
    and con.contype = 'f'
    and con.conkey = array[(select a.attnum from pg_attribute a
                            where a.attrelid = 'public.collection_layout_slot_assignment'::regclass
                              and a.attname = 'collection_allocation_id')]::int2[];
  if v_name is null then
    raise exception '5248: FK de collection_allocation_id não encontrada';
  end if;
  execute format('alter table public.collection_layout_slot_assignment drop constraint %I', v_name);
end;
$fk$;

alter table public.collection_layout_slot_assignment
  alter column collection_allocation_id drop not null,
  add constraint fk_collection_layout_slot_assignment_allocation
    foreign key (collection_allocation_id) references public.collection_allocation(id)
    on update restrict on delete set null;

comment on column public.collection_layout_slot_assignment.physical_card_id is
  'Exemplar no bolso (5248). Único em todo o sistema. Elegível só se guardado no local físico do fichário (collection_layout.storage_container_id).';
comment on column public.collection_layout_slot_assignment.collection_allocation_id is
  'LEGADO (5248): alocação no momento do posicionamento; NULL quando desfeita. Origem atual = alocação do physical_card_id.';

do $post$
begin
  if exists (select 1 from public.collection_layout_slot_assignment where physical_card_id is null) then
    raise exception 'POSTCHECK 5248: posição sem exemplar';
  end if;
  if exists (select 1 from public.collection_layout_slot_assignment a
             join public.collection_allocation ca on ca.id = a.collection_allocation_id
             where ca.physical_card_id <> a.physical_card_id) then
    raise exception 'POSTCHECK 5248: exemplar divergente da alocação';
  end if;
end;
$post$;

commit;

/*
Resultado esperado: 155 posições com physical_card_id = exemplar da alocação;
mesmos slot_id e updated_at; UNIQUE(physical_card_id); FK exemplar CASCADE;
FK alocação SET NULL; collection_allocation_id NULL permitido.

Como validar (só leitura):
select count(*), count(physical_card_id), count(distinct physical_card_id)
from public.collection_layout_slot_assignment;
*/
