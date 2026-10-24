/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5250 - Posicionar exemplar pelo local físico
              place_my_physical_card_in_slot(uuid, uuid, uuid)
Versão......: 1.0 (2026-10-24, BINDER-PHYSICAL-LOCATION-ELIGIBILITY-DECISIONS-01)
Status......: PROPOSTA — NÃO EXECUTADA. Depois da 5249 (README §6).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-24

Escritor novo, usado por "Cartas disponíveis", pelo seletor do bolso vazio e
pelo "Desfazer" (o frontend deixa de chamar assign_card_to_slot, que fica
como legado inalterado).

Elegibilidade (README §2): exemplar do usuário da sessão, GUARDADO no local
físico do fichário (5247), sem bolso em lugar algum; bolso livre de trava,
mesclagem e imagem. A coleção do exemplar NÃO importa (outra, nenhuma ou
arquivada — D1). Posicionar não grava nada em coleção, alocação, inventário
ou valor (princípio 5).

Parâmetros:
  p_collection_id     coleção pela qual o fichário está aberto (proprietária
                      ou convidada) — define o fichário e a fronteira de dono;
  p_slot_id           bolso de destino;
  p_physical_card_id  exemplar.
Resultado: ADD | REPLACE | UNCHANGED (+ exemplar substituído no REPLACE).
Erros (mensagem = código): COLLECTION_NOT_FOUND, BINDER_NOT_FOUND,
COLLECTION_ARCHIVED (coleção aberta ou proprietária arquivada),
SLOT_NOT_FOUND, SLOT_LOCKED, PHYSICAL_CARD_NOT_FOUND,
CARD_NOT_IN_BINDER_LOCATION, CARD_ALREADY_PLACED. Mesclagem/imagem: os
gatilhos 5238/5232 continuam recusando.
Ordem de travas (igual às demais escritas do fichário): proprietária →
layout (5122) → coleção aberta, se convidada (como a desassociação 5229) →
bolso → exemplar → posições. A mudança de local (5249) trava exemplar →
posição, a mesma ordem relativa.
Dependências: 5122, 5229, 5232, 5238, 5247, 5248.
================================================================
*/

begin;

do $pre$
begin
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'collection_layout_slot_assignment'
                   and column_name = 'physical_card_id') then
    raise exception 'PRECHECK 5250: aplique a 5248 antes';
  end if;
  if to_regprocedure('public.assert_collection_layout_mutable(uuid)') is null then
    raise exception 'PRECHECK 5250: assert_collection_layout_mutable (5122) ausente';
  end if;
  if to_regprocedure('public.place_my_physical_card_in_slot(uuid, uuid, uuid)') is not null then
    raise exception 'PRECHECK 5250: função já existe';
  end if;
end;
$pre$;

create function public.place_my_physical_card_in_slot(
  p_collection_id    uuid,
  p_slot_id          uuid,
  p_physical_card_id uuid
)
returns table (
  assignment_id             uuid,
  slot_id                   uuid,
  physical_card_id          uuid,
  operation                 text,   -- ADD | REPLACE | UNCHANGED
  replaced_physical_card_id uuid
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
  v_status     text;
  v_layout     uuid;
  v_container  uuid;
  v_locked     boolean;
  v_card_cont  uuid;
  v_here       uuid;   -- posição atual do exemplar (qualquer bolso)
  v_here_slot  uuid;
  v_old_asg    uuid;
  v_old_card   uuid;
  v_new_asg    uuid;
  v_op         text;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null or p_slot_id is null or p_physical_card_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  -- 1. Coleção aberta: fronteira de dono antes de qualquer outra tabela
  -- (sem trava aqui: a ordem canônica é proprietária → layout → convidada).
  perform 1 from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  select l.id into v_layout from public.collection_layout l where l.collection_id = p_collection_id;
  if v_layout is null then
    select g.layout_id into v_layout from public.collection_layout_guest g where g.collection_id = p_collection_id;
  end if;
  if v_layout is null then
    raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- 2. Proprietária → layout (5122: dono e ACTIVE).
  begin
    perform public.assert_collection_layout_mutable(v_layout);
  exception
    when others then
      if sqlerrm like 'collection is ARCHIVED%' then
        raise exception 'COLLECTION_ARCHIVED' using errcode = '55000';
      end if;
      raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
  end;

  -- Coleção aberta (se convidada) travada DEPOIS da proprietária/layout, como
  -- detach_my_collection_from_binder (5229) — sem ciclo de travas.
  select c.lifecycle_status into v_status
  from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_uid
  for share;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_status <> 'ACTIVE' then
    raise exception 'COLLECTION_ARCHIVED' using errcode = '55000';
  end if;
  -- Revalida a participação depois das travas (desassociação concorrente).
  if not exists (select 1 from public.collection_layout l where l.id = v_layout and l.collection_id = p_collection_id)
     and not exists (select 1 from public.collection_layout_guest g where g.layout_id = v_layout and g.collection_id = p_collection_id) then
    raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
  end if;

  select l.storage_container_id into v_container from public.collection_layout l where l.id = v_layout;

  -- 3. Bolso deste fichário.
  select s.locked into v_locked
  from public.collection_layout_slot s
  join public.collection_layout_page p on p.id = s.page_id
  where s.id = p_slot_id and p.layout_id = v_layout
  for update of s;
  if not found then
    raise exception 'SLOT_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_locked then
    raise exception 'SLOT_LOCKED' using errcode = '55000';
  end if;

  -- 4. Exemplar do usuário (inexistente e alheio colapsam).
  select pc.storage_container_id into v_card_cont
  from public.physical_card pc
  join public.inventory i on i.id = pc.inventory_id
  where pc.id = p_physical_card_id and i.owner_user_id = v_uid
  for update of pc;
  if not found then
    raise exception 'PHYSICAL_CARD_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_card_cont is distinct from v_container then
    raise exception 'CARD_NOT_IN_BINDER_LOCATION' using errcode = '55000';
  end if;

  -- 5. Já posicionado?
  select a.id, a.slot_id into v_here, v_here_slot
  from public.collection_layout_slot_assignment a
  where a.physical_card_id = p_physical_card_id
  for update;
  if v_here is not null then
    if v_here_slot = p_slot_id then
      return query select v_here, p_slot_id, p_physical_card_id, 'UNCHANGED'::text, null::uuid;
      return;
    end if;
    raise exception 'CARD_ALREADY_PLACED' using errcode = '23505',
      hint = 'o exemplar já está em outro bolso — mova-o em vez de posicioná-lo de novo';
  end if;

  -- 6. REPLACE / ADD.
  select a.id, a.physical_card_id into v_old_asg, v_old_card
  from public.collection_layout_slot_assignment a
  where a.slot_id = p_slot_id
  for update;
  if v_old_asg is not null then
    delete from public.collection_layout_slot_assignment where id = v_old_asg;
    v_op := 'REPLACE';
  else
    v_op := 'ADD';
  end if;

  begin
    insert into public.collection_layout_slot_assignment as a (slot_id, physical_card_id)
    values (p_slot_id, p_physical_card_id)
    returning a.id into v_new_asg;
  exception
    when unique_violation then
      raise exception 'CARD_ALREADY_PLACED' using errcode = '23505';
  end;

  return query select v_new_asg, p_slot_id, p_physical_card_id, v_op, v_old_card;
end;
$$;

comment on function public.place_my_physical_card_in_slot(uuid, uuid, uuid) is
  '5250: posiciona um exemplar do usuário num bolso do fichário aberto pela coleção informada (proprietária ou convidada). Elegível = guardado no local físico do fichário, sem bolso; a coleção do exemplar não importa. ADD | REPLACE | UNCHANGED. Não altera coleção, alocação, inventário nem valor.';

revoke all on function public.place_my_physical_card_in_slot(uuid, uuid, uuid) from public, anon;
grant execute on function public.place_my_physical_card_in_slot(uuid, uuid, uuid) to authenticated;

notify pgrst, 'reload schema';

commit;

/*
Como validar (só leitura):
select p.prosecdef, p.proconfig,
       has_function_privilege('anon', p.oid, 'EXECUTE') as anon_exec,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_exec
from pg_proc p where p.oid = 'public.place_my_physical_card_in_slot(uuid, uuid, uuid)'::regprocedure;
*/
