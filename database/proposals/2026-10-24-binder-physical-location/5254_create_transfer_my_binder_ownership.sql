/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5254 - Exclusão segura da coleção proprietária
              transfer_my_binder_ownership(uuid, uuid)
              + exceção controlada na 5136 (collection_layout.collection_id)
Versão......: 1.0 (2026-10-24, BINDER-PHYSICAL-LOCATION-ELIGIBILITY-DECISIONS-01)
Status......: PROPOSTA — NÃO EXECUTADA. Depois da 5253 (README §6).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-24

Problema: o fichário passa a representar um local físico com exemplares de
várias origens; a exclusão da coleção proprietária não pode implicar
desmontá-lo. Hoje delete_collection (5229) JÁ recusa excluir a proprietária
(BINDER_EXISTS) — não há exclusão silenciosa — mas a única saída é desmontar.

Menor caminho seguro (README §5): passar a âncora do fichário para outra
coleção do MESMO usuário, numa transação, sem tocar em bolso, posição,
reserva de outra coleção, imagem, mesclagem, trava, identidade (nome e
logomarca, P3-A) ou local físico. A antiga proprietária vira convidada; daí
ela pode ser desassociada (D2: posições ficam) e excluída pelo fluxo normal.
Nada é excluído automaticamente.

Regras:
  - as duas coleções são do usuário; a de origem é a proprietária ATUAL do
    fichário (qualquer lifecycle — é o caminho de saída de uma arquivada);
  - a de destino está ACTIVE, não é proprietária de outro fichário e não é
    convidada de OUTRO fichário (convidada deste é aceita e deixa de sê-lo);
  - reservas implícitas da proprietária (collection_id NULL) passam a ter a
    coleção de origem explícita, para não mudarem de dono;
  - repetição depois de concluída → UNCHANGED.
Travas: origem (proprietária) → layout → destino, mesma ordem das demais
escritas do fichário.
5136: collection_layout.collection_id continua imutável, EXCETO dentro desta
função (configuração de transação mmkyu.binder_owner_transfer = id do layout)
e só para coleção do MESMO dono. Reparentar é seguro agora porque a posição
é do exemplar e a elegibilidade é o local físico (5248), não a coleção.
Dependências: 5136, 5229, 5248, 5253.
================================================================
*/

begin;

do $pre$
begin
  if to_regprocedure('public.transfer_my_binder_ownership(uuid, uuid)') is not null then
    raise exception 'PRECHECK 5254: função já existe';
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'trg_collection_layout_collection_id_immutable') then
    raise exception 'PRECHECK 5254: gatilho 5136 ausente';
  end if;
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'collection_layout_slot_assignment'
                   and column_name = 'physical_card_id') then
    raise exception 'PRECHECK 5254: aplique a 5248 antes';
  end if;
end;
$pre$;

-- 1. 5136 com exceção controlada ----------------------------------------------------
create or replace function public.enforce_collection_layout_structural_fk_immutability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_column text := tg_argv[0];
  v_old    text;
  v_new    text;
begin
  v_old := to_jsonb(old) ->> v_column;
  v_new := to_jsonb(new) ->> v_column;

  if v_new is distinct from v_old then
    -- 5254: transferência da âncora do fichário, só dentro de
    -- transfer_my_binder_ownership e só entre coleções do mesmo dono.
    if tg_table_name = 'collection_layout' and v_column = 'collection_id'
       and coalesce(current_setting('mmkyu.binder_owner_transfer', true), '') = (old.id)::text
       and (select c.owner_user_id from public.collection c where c.id = (v_old)::uuid)
           = (select c.owner_user_id from public.collection c where c.id = (v_new)::uuid) then
      return new;
    end if;
    raise exception
      '%.% é IMUTÁVEL na V1 — reparentar objetos do Layout mudaria a Collection efetiva do Slot sem revalidar as Slot Assignments; a operação suportada é remover e recriar',
      tg_table_name, v_column;
  end if;

  return new;
end;
$$;

revoke execute on function public.enforce_collection_layout_structural_fk_immutability() from public, anon, authenticated;

-- 2. Transferência --------------------------------------------------------------------
create function public.transfer_my_binder_ownership(
  p_from_collection_id uuid,
  p_to_collection_id   uuid
)
returns table (
  outcome              text,     -- TRANSFERRED | UNCHANGED
  layout_id            uuid,
  reservations_pinned  integer   -- reservas implícitas da antiga proprietária tornadas explícitas
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
  v_status  text;
  v_pinned  integer := 0;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_from_collection_id is null or p_to_collection_id is null
     or p_from_collection_id = p_to_collection_id then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  perform 1 from public.collection c where c.id = p_from_collection_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;
  perform 1 from public.collection c where c.id = p_to_collection_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- Repetição já concluída: destino é a proprietária e origem é convidada do mesmo layout.
  select l.id into v_layout from public.collection_layout l where l.collection_id = p_to_collection_id;
  if v_layout is not null
     and exists (select 1 from public.collection_layout_guest g
                 where g.layout_id = v_layout and g.collection_id = p_from_collection_id) then
    return query select 'UNCHANGED'::text, v_layout, 0;
    return;
  end if;

  -- Travas: origem → layout → destino.
  perform 1 from public.collection c where c.id = p_from_collection_id for update;
  select l.id into v_layout from public.collection_layout l
  where l.collection_id = p_from_collection_id
  for update;
  if v_layout is null then
    raise exception 'BINDER_NOT_OWNED' using errcode = 'P0002',
      hint = 'a coleção de origem não é a proprietária de um fichário';
  end if;
  select c.lifecycle_status into v_status from public.collection c
  where c.id = p_to_collection_id for update;
  if v_status <> 'ACTIVE' then
    raise exception 'COLLECTION_ARCHIVED' using errcode = '55000';
  end if;
  if exists (select 1 from public.collection_layout l where l.collection_id = p_to_collection_id) then
    raise exception 'COLLECTION_HAS_OWN_BINDER' using errcode = '55000';
  end if;
  if exists (select 1 from public.collection_layout_guest g
             where g.collection_id = p_to_collection_id and g.layout_id <> v_layout) then
    raise exception 'COLLECTION_IS_BINDER_GUEST' using errcode = '55000',
      hint = 'a coleção de destino usa outro fichário — desassocie antes';
  end if;

  -- Reservas implícitas da proprietária ficam com a coleção de origem.
  update public.collection_layout_slot_expected_content e
     set collection_id = p_from_collection_id
   where e.collection_id is null
     and e.slot_id in (select s.id from public.collection_layout_slot s
                       join public.collection_layout_page p on p.id = s.page_id
                       where p.layout_id = v_layout);
  get diagnostics v_pinned = row_count;

  delete from public.collection_layout_guest g
   where g.collection_id = p_to_collection_id and g.layout_id = v_layout;

  perform set_config('mmkyu.binder_owner_transfer', v_layout::text, true);
  update public.collection_layout l set collection_id = p_to_collection_id where l.id = v_layout;
  perform set_config('mmkyu.binder_owner_transfer', '', true);

  insert into public.collection_layout_guest (collection_id, layout_id)
  values (p_from_collection_id, v_layout);

  return query select 'TRANSFERRED'::text, v_layout, v_pinned;
end;
$$;

comment on function public.transfer_my_binder_ownership(uuid, uuid) is
  '5254: passa a âncora do fichário da proprietária atual para outra coleção ACTIVE do mesmo usuário; a antiga vira convidada. Não toca em bolsos, posições, imagens, mesclagens, travas, identidade nem local físico. Caminho seguro antes de excluir a proprietária (desassociar → excluir). TRANSFERRED | UNCHANGED.';

revoke all on function public.transfer_my_binder_ownership(uuid, uuid) from public, anon;
grant execute on function public.transfer_my_binder_ownership(uuid, uuid) to authenticated;

notify pgrst, 'reload schema';

commit;

/*
Como validar (só leitura):
select p.prosecdef, p.proconfig, has_function_privilege('anon', p.oid, 'EXECUTE') as anon_exec
from pg_proc p where p.oid = 'public.transfer_my_binder_ownership(uuid, uuid)'::regprocedure;
*/
