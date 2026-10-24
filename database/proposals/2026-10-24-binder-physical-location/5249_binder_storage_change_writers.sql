/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5249 - Mudança de local de exemplar posicionado (D3) —
              escritores com confirmação explícita (FASE A, aditiva)
              preview_my_physical_cards_binder_impact(uuid[], uuid)
              preview_my_collection_storage_binder_impact(uuid, uuid, text)
              set_physical_cards_storage(uuid, uuid[], boolean)      — NOVA sobrecarga
              organize_my_collection_storage(uuid, uuid, text, integer, text, boolean) — NOVA sobrecarga
Versão......: 2.0 (2026-10-24, BINDER-PHYSICAL-LOCATION-IMPLEMENTATION-READINESS-01)
Status......: PROPOSTA — NÃO EXECUTADA. Fase A (README §6).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-24

v2.0 (readiness): sai o gatilho com configuração de sessão da v1.0. A
regra D3 passa a ser aplicada DENTRO dos escritores novos (trava, conta,
recusa ou remove a posição e só então muda o local) — e o gatilho de
proteção, sem nenhuma configuração de sessão, vai para a 5256 (fase B),
depois do frontend novo. Assim:
  - nada que o frontend atual chama muda de assinatura nem de
    comportamento nesta fase (5024 e 5222 originais intactas);
  - as sobrecargas novas têm o parâmetro de confirmação SEM DEFAULT: uma
    chamada com os argumentos antigos nunca é ambígua e continua indo para
    a função antiga;
  - na fase B (5256) o gatilho garante a regra para QUALQUER caminho que
    não tenha removido a posição antes (5024/5222 antigas inclusive).

Regras (D3 aprovada + D1 desta rodada para a 5222):
  - exemplar posicionado que muda de local → exige confirmação explícita;
  - com confirmação, a posição é removida na MESMA transação, antes do
    UPDATE de local (atomicidade: falhou qualquer coisa → nada muda);
  - bolso travado → BINDER_POSITION_LOCKED (55000), mesmo confirmando;
  - prévias informam quantos sairão dos bolsos e quantos estão travados.
Mensagens (= códigos): BINDER_POSITION_CONFIRMATION_REQUIRED,
BINDER_POSITION_LOCKED (+ hint com a quantidade); as demais são as
das funções de origem (5024/5222), inalteradas.
Travas: exemplares (ordem de id) → posições; a 5222 nova mantém
NOWAIT em ambos (LOCK_BUSY). A gravação concorrente de cadeado no bolso
é barrada pela 5118 (DELETE de posição em bolso travado falha e desfaz).
Dependências: 5024, 5221, 5222, 5248.
================================================================
*/

begin;

set local lock_timeout = '5s';

do $pre$
begin
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'collection_layout_slot_assignment'
                   and column_name = 'physical_card_id') then
    raise exception 'PRECHECK 5249: aplique a 5248 antes';
  end if;
  if to_regprocedure('public.set_physical_cards_storage(uuid, uuid[])') is null
     or to_regprocedure('public.organize_my_collection_storage(uuid, uuid, text, integer, text)') is null then
    raise exception 'PRECHECK 5249: 5024/5222 ausentes';
  end if;
  if to_regprocedure('public.set_physical_cards_storage(uuid, uuid[], boolean)') is not null
     or to_regprocedure('public.organize_my_collection_storage(uuid, uuid, text, integer, text, boolean)') is not null
     or to_regprocedure('public.preview_my_physical_cards_binder_impact(uuid[], uuid)') is not null
     or to_regprocedure('public.preview_my_collection_storage_binder_impact(uuid, uuid, text)') is not null then
    raise exception 'PRECHECK 5249: objetos já existem';
  end if;
end;
$pre$;

-- 1. Prévia por exemplares (Meu acervo: mover / local do exemplar) ---------------
create function public.preview_my_physical_cards_binder_impact(
  p_physical_card_ids    uuid[],
  p_storage_container_id uuid
)
returns table (
  positioned_count integer,   -- sairão do bolso se a mudança for confirmada
  locked_count     integer    -- impedem a mudança até destravar
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_physical_card_ids is null or array_ndims(p_physical_card_ids) <> 1
     or cardinality(p_physical_card_ids) < 1 or cardinality(p_physical_card_ids) > 500 then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  return query
  select (count(*) filter (where not s.locked))::integer,
         (count(*) filter (where s.locked))::integer
  from public.physical_card pc
  join public.inventory i on i.id = pc.inventory_id and i.owner_user_id = v_uid
  join public.collection_layout_slot_assignment a on a.physical_card_id = pc.id
  join public.collection_layout_slot s on s.id = a.slot_id
  where pc.id = any(p_physical_card_ids)
    and pc.storage_container_id is distinct from p_storage_container_id;
end;
$$;

comment on function public.preview_my_physical_cards_binder_impact(uuid[], uuid) is
  '5249 (D3): dos exemplares informados (até 500, só os do usuário), quantos sairiam de um bolso do fichário ao ir para o local informado (NULL = sem local) e quantos estão em bolso travado. Só leitura.';

revoke all on function public.preview_my_physical_cards_binder_impact(uuid[], uuid) from public, anon;
grant execute on function public.preview_my_physical_cards_binder_impact(uuid[], uuid) to authenticated;

-- 2. Prévia por coleção (Organizar armazenamento, 5221/5222) ---------------------
create function public.preview_my_collection_storage_binder_impact(
  p_collection_id        uuid,
  p_storage_container_id uuid,
  p_mode                 text      -- UNLOCATED | ALL (mesma semântica da 5222)
)
returns table (
  positioned_count integer,
  locked_count     integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := auth.uid();
  v_mode text := upper(btrim(coalesce(p_mode, '')));
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null or p_storage_container_id is null or v_mode not in ('UNLOCATED', 'ALL') then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  perform 1 from public.collection c where c.id = p_collection_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  return query
  select (count(*) filter (where not s.locked))::integer,
         (count(*) filter (where s.locked))::integer
  from public.collection_allocation ca
  join public.physical_card pc on pc.id = ca.physical_card_id
  join public.inventory i on i.id = pc.inventory_id and i.owner_user_id = v_uid
  join public.collection_layout_slot_assignment a on a.physical_card_id = pc.id
  join public.collection_layout_slot s on s.id = a.slot_id
  where ca.collection_id = p_collection_id
    and case when v_mode = 'UNLOCATED' then pc.storage_container_id is null
             else pc.storage_container_id is distinct from p_storage_container_id end;
end;
$$;

comment on function public.preview_my_collection_storage_binder_impact(uuid, uuid, text) is
  '5249 (D1 da rodada READINESS): na organização da coleção (5221/5222) para o local informado, quantos exemplares elegíveis sairiam de bolsos do fichário e quantos estão em bolso travado. Só leitura.';

revoke all on function public.preview_my_collection_storage_binder_impact(uuid, uuid, text) from public, anon;
grant execute on function public.preview_my_collection_storage_binder_impact(uuid, uuid, text) to authenticated;

-- 3. set_physical_cards_storage — sobrecarga com confirmação (5024 intacta) -------
create function public.set_physical_cards_storage(
    p_storage_container_id uuid,
    p_physical_card_ids    uuid[],
    p_unplace_from_binder  boolean      -- sem DEFAULT (não colide com a 5024)
)
returns table (
    id                    uuid,
    storage_container_id  uuid,
    updated_at            timestamptz
)
language plpgsql
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
declare
    v_inventory_id           uuid;
    v_container_inventory_id uuid;
    v_distinct_ids           uuid[];
    v_raw_count              int;
    v_owned_count            int;
    v_pos                    int := 0;
    v_pos_lock               int := 0;
begin
    if auth.uid() is null then
        raise exception 'authentication required';
    end if;

    if p_physical_card_ids is null then
        raise exception 'p_physical_card_ids não pode ser vazio';
    end if;
    if p_unplace_from_binder is null then
        raise exception 'INVALID_ARGUMENT' using errcode = '22023';
    end if;

    v_raw_count := cardinality(p_physical_card_ids);
    if v_raw_count = 0 then
        raise exception 'p_physical_card_ids não pode ser vazio';
    end if;
    if array_ndims(p_physical_card_ids) <> 1 then
        raise exception
            'p_physical_card_ids deve ser um array unidimensional (recebido array com % dimensões)',
            array_ndims(p_physical_card_ids);
    end if;
    if v_raw_count > 500 then
        raise exception 'lote excede o limite de 500 itens por chamada';
    end if;

    select array_agg(distinct x) into v_distinct_ids
    from unnest(p_physical_card_ids) as x;

    select inv.id into v_inventory_id
    from public.inventory inv
    where inv.owner_user_id = auth.uid();
    if v_inventory_id is null then
        raise exception 'inventory not found for current user';
    end if;

    if p_storage_container_id is not null then
        select sc.inventory_id into v_container_inventory_id
        from public.storage_container sc
        where sc.id = p_storage_container_id;
        if v_container_inventory_id is null then
            raise exception 'storage container not found';
        end if;
        if v_container_inventory_id is distinct from v_inventory_id then
            raise exception 'storage container does not belong to caller inventory';
        end if;
    end if;

    select count(*) into v_owned_count
    from public.physical_card pc
    where pc.id = any(v_distinct_ids)
      and pc.inventory_id = v_inventory_id;
    if v_owned_count <> cardinality(v_distinct_ids) then
        raise exception 'um ou mais physical_card_ids não pertencem ao inventory do chamador';
    end if;

    -- 5249: trava os exemplares (ordem de id) antes de contar posições e decidir.
    perform 1
    from public.physical_card pc
    where pc.id = any(v_distinct_ids)
      and pc.inventory_id = v_inventory_id
    order by pc.id
    for update;

    -- 5249 (D3): posições de exemplares que realmente mudam de local.
    perform 1
    from public.collection_layout_slot_assignment a
    join public.physical_card pc on pc.id = a.physical_card_id
    where pc.id = any(v_distinct_ids)
      and pc.storage_container_id is distinct from p_storage_container_id
    order by a.id
    for update of a;
    select count(*) filter (where not s.locked)::int, count(*) filter (where s.locked)::int
      into v_pos, v_pos_lock
    from public.collection_layout_slot_assignment a
    join public.collection_layout_slot s on s.id = a.slot_id
    join public.physical_card pc on pc.id = a.physical_card_id
    where pc.id = any(v_distinct_ids)
      and pc.storage_container_id is distinct from p_storage_container_id;
    if v_pos_lock > 0 then
        raise exception 'BINDER_POSITION_LOCKED' using errcode = '55000',
          hint = v_pos_lock::text || ' exemplar(es) em bolso travado do fichário — destrave antes de mudar o local';
    end if;
    if v_pos > 0 and not p_unplace_from_binder then
        raise exception 'BINDER_POSITION_CONFIRMATION_REQUIRED' using errcode = '55000',
          hint = v_pos::text || ' exemplar(es) sairão dos bolsos do fichário — confirme';
    end if;
    if v_pos > 0 then
        delete from public.collection_layout_slot_assignment a
        using public.physical_card pc
        where pc.id = a.physical_card_id
          and pc.id = any(v_distinct_ids)
          and pc.storage_container_id is distinct from p_storage_container_id;
    end if;

    return query
    update public.physical_card
    set storage_container_id = p_storage_container_id
    where physical_card.id = any(v_distinct_ids)
      and physical_card.inventory_id = v_inventory_id
    returning physical_card.id, physical_card.storage_container_id, physical_card.updated_at;
end;
$$;

comment on function public.set_physical_cards_storage(uuid, uuid[], boolean) is
  '5249: mesma regra e retorno da 5024 (1–500 exemplares do próprio inventário; local ou NULL; atômica). Exemplar posicionado que muda de local exige p_unplace_from_binder = true — a posição sai na mesma transação; bolso travado recusa (BINDER_POSITION_LOCKED); sem confirmação → BINDER_POSITION_CONFIRMATION_REQUIRED.';

revoke all on function public.set_physical_cards_storage(uuid, uuid[], boolean) from public, anon;
grant execute on function public.set_physical_cards_storage(uuid, uuid[], boolean) to authenticated;

-- 4. organize_my_collection_storage — sobrecarga com confirmação (5222 intacta) ---
-- Gerada da canônica 5222: mesmo corpo + parâmetro p_unplace_from_binder e
-- o bloco 6b (posições) antes da escrita. Verificado pelo static check (S4).
create function public.organize_my_collection_storage(
  p_collection_id        uuid,
  p_storage_container_id uuid,
  p_mode                 text,
  p_expected_count       integer,
  p_plan_token           text,
  p_unplace_from_binder  boolean   -- 5249 (D1 desta rodada): sem DEFAULT — não colide com a assinatura 5222
)
returns table (
  collection_id        uuid,
  storage_container_id uuid,
  mode                 text,
  moved_count          integer,
  total_count          integer,
  at_target_count      integer
)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
#variable_conflict use_column
declare
  c_max_per_operation constant integer := 10000;   -- D3 (proposta); mesmo valor na 5221
  v_uid       uuid := auth.uid();
  v_mode      text := upper(btrim(coalesce(p_mode, '')));
  v_inventory uuid;
  v_status    text;
  v_default   uuid;
  v_eligible  integer;
  v_ids       uuid[];
  v_locked    integer;
  v_locked_all integer := 0;
  v_total     integer;
  v_all       uuid[];
  v_id        uuid;
  v_snap      record;
  v_snap_eligible integer;
  v_moved     integer := 0;
  v_pos       integer := 0;   -- 5249: elegíveis que estão num bolso solto
  v_pos_lock  integer := 0;   -- 5249: elegíveis que estão num bolso travado
begin
  -- 0. Forma -----------------------------------------------------------------
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if v_mode not in ('UNLOCATED', 'ALL') then
    raise exception 'INVALID_MODE' using errcode = '22023';
  end if;
  if p_collection_id is null or p_storage_container_id is null
     or p_expected_count is null or p_expected_count < 0
     or p_plan_token is null or p_plan_token !~ '^v1:[0-9a-f]{32}$'
     or p_unplace_from_binder is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  if p_expected_count > c_max_per_operation then
    raise exception 'COLLECTION_TOO_LARGE' using errcode = '54000';
  end if;

  select i.id into v_inventory from public.inventory i where i.owner_user_id = v_uid;

  -- 1. Coleção (trava comum a vínculo, desvínculo e local padrão) -----------
  select c.lifecycle_status, c.default_storage_container_id
    into v_status, v_default
  from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_uid
  for update;
  if not found or v_inventory is null then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_status <> 'ACTIVE' then
    raise exception 'COLLECTION_ARCHIVED' using errcode = '55000';
  end if;

  -- 2. Destino no acervo do chamador (bloqueia exclusão concorrente) -------
  perform 1
  from public.storage_container sc
  where sc.id = p_storage_container_id and sc.inventory_id = v_inventory
  for key share;
  if not found then
    raise exception 'STORAGE_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- 3. D2: o destino tem de ser o local padrão vigente ----------------------
  if v_default is distinct from p_storage_container_id then
    raise exception 'DEFAULT_CHANGED';
  end if;

  -- 4. Tetos antes de qualquer trava de exemplar --------------------------
  --    D6: teto sobre o total alocado à coleção (universo do plan_token).
  select count(*) into v_total
  from public.collection_allocation ca
  where ca.collection_id = p_collection_id;
  if v_total > c_max_per_operation then
    raise exception 'COLLECTION_TOO_LARGE' using errcode = '54000';
  end if;
  --    D3: teto sobre os elegíveis da modalidade (redundante com D6, mantido).
  select count(*) into v_eligible
  from public.collection_allocation ca
  join public.physical_card pc on pc.id = ca.physical_card_id
  where ca.collection_id = p_collection_id
    and pc.inventory_id = v_inventory
    and case when v_mode = 'UNLOCATED' then pc.storage_container_id is null
             else pc.storage_container_id is distinct from p_storage_container_id end;
  if v_eligible > c_max_per_operation then
    raise exception 'COLLECTION_TOO_LARGE' using errcode = '54000';
  end if;

  -- 5. Trava TODO o universo do plan_token, um a um, em ordem de id, sem
  --    esperar. A lista vem da composição já congelada pela trava da coleção
  --    (passo 1); a ordem de aquisição é a ordem do array (FOREACH), não a
  --    do plano. Exemplar ausente na hora da trava → PLAN_CHANGED.
  select coalesce(array_agg(ca.physical_card_id order by ca.physical_card_id), '{}')
    into v_all
  from public.collection_allocation ca
  where ca.collection_id = p_collection_id;

  begin
    foreach v_id in array v_all loop
      perform 1 from public.physical_card pc where pc.id = v_id for update nowait;
      if not found then
        raise exception 'PLAN_CHANGED';
      end if;
      v_locked_all := v_locked_all + 1;
    end loop;
  exception when lock_not_available then
    raise exception 'LOCK_BUSY' using errcode = '55P03';
  end;

  -- Elegíveis da modalidade, escolhidos dentro do conjunto já travado.
  select array_agg(pc.id order by pc.id) into v_ids
  from public.collection_allocation ca
  join public.physical_card pc on pc.id = ca.physical_card_id
  where ca.collection_id = p_collection_id
    and pc.inventory_id = v_inventory
    and case when v_mode = 'UNLOCATED' then pc.storage_container_id is null
             else pc.storage_container_id is distinct from p_storage_container_id end;
  v_locked := coalesce(cardinality(v_ids), 0);

  -- 6. Revalida o que foi autorizado (snapshot novo, após as travas) --------
  select * into v_snap
  from public.collection_storage_plan_snapshot(p_collection_id, p_storage_container_id);
  v_snap_eligible := case when v_mode = 'UNLOCATED' then v_snap.eligible_unlocated else v_snap.eligible_all end;

  if v_snap.plan_token <> p_plan_token
     or v_snap_eligible <> p_expected_count
     or v_locked <> p_expected_count
     or v_locked_all <> v_snap.total_count then
    raise exception 'PLAN_CHANGED';
  end if;

  -- 6b. 5249 — posições no fichário (D1/D3): exemplar que sai do local físico
  --     do fichário não pode continuar num bolso. Travas das posições sem
  --     esperar (mesma política NOWAIT dos exemplares). Bolso travado recusa;
  --     sem confirmação explícita recusa; com confirmação, as posições saem
  --     na MESMA transação, antes da mudança de local.
  begin
    perform 1
    from public.collection_layout_slot_assignment a
    where a.physical_card_id = any(coalesce(v_ids, '{}'))
    order by a.id
    for update nowait;
  exception when lock_not_available then
    raise exception 'LOCK_BUSY' using errcode = '55P03';
  end;
  select count(*) filter (where not s.locked)::integer, count(*) filter (where s.locked)::integer
    into v_pos, v_pos_lock
  from public.collection_layout_slot_assignment a
  join public.collection_layout_slot s on s.id = a.slot_id
  where a.physical_card_id = any(coalesce(v_ids, '{}'));
  if v_pos_lock > 0 then
    raise exception 'BINDER_POSITION_LOCKED' using errcode = '55000',
      hint = v_pos_lock::text || ' exemplar(es) em bolso travado do fichário — destrave antes de organizar';
  end if;
  if v_pos > 0 and not p_unplace_from_binder then
    raise exception 'BINDER_POSITION_CONFIRMATION_REQUIRED' using errcode = '55000',
      hint = v_pos::text || ' exemplar(es) sairão dos bolsos do fichário — confirme na prévia';
  end if;
  if v_pos > 0 then
    delete from public.collection_layout_slot_assignment a
    where a.physical_card_id = any(v_ids);
  end if;

  -- 7. Escrita única, set-based, só sobre os elegíveis (todos travados) ----
  if v_locked > 0 then
    update public.physical_card pc
    set storage_container_id = p_storage_container_id
    where pc.id = any(v_ids)
      and pc.inventory_id = v_inventory;
    get diagnostics v_moved = row_count;
    if v_moved <> v_locked then
      raise exception 'PLAN_CHANGED';   -- desfaz a transação inteira
    end if;
  end if;

  return query
  select p_collection_id,
         p_storage_container_id,
         v_mode,
         v_moved,
         s.total_count,
         s.at_target_count
  from public.collection_storage_plan_snapshot(p_collection_id, p_storage_container_id) s;
end;
$$;

comment on function public.organize_my_collection_storage(uuid, uuid, text, integer, text, boolean) is
  '5249 (D1 da rodada READINESS): 5222 + confirmação de fichário. Elegíveis posicionados exigem p_unplace_from_binder = true (posições saem na mesma transação, antes da escrita de local); bolso travado → BINDER_POSITION_LOCKED; posições em uso → LOCK_BUSY. Demais regras idênticas à 5222 (plan_token, DEFAULT_CHANGED, PLAN_CHANGED, tetos, NOWAIT).';

revoke all on function public.organize_my_collection_storage(uuid, uuid, text, integer, text, boolean) from public, anon;
grant execute on function public.organize_my_collection_storage(uuid, uuid, text, integer, text, boolean) to authenticated;

notify pgrst, 'reload schema';

commit;

/*
Resultado esperado: 4 funções novas (authenticated); 5024 e 5222 originais
intactas (o frontend atual continua chamando-as sem mudança).

Como validar (só leitura):
select p.oid::regprocedure from pg_proc p
where p.proname in ('set_physical_cards_storage', 'organize_my_collection_storage',
                    'preview_my_physical_cards_binder_impact', 'preview_my_collection_storage_binder_impact')
order by 1;
*/
