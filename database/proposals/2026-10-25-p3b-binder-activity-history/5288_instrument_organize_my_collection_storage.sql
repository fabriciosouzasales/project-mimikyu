/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5288 - P3-B S5 · Histórico do Fichário — instrumentação E06b (Cartas saíram ao organizar a guarda da coleção)
              organize_my_collection_storage(uuid, uuid, text, integer, text, boolean) — a de 5 argumentos (5222) não muda
Versão......: 1.0 (2026-10-28, P3-B S5 — instrumentação E06a, E06b, E07)
Status......: PROPOSTA — NÃO EXECUTADA. Exige autorização própria para o LIVE.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-28
Base........: 5249 (md5(prosrc) LIVE 083dc24206720b084c0bc5434d93e1fa, conferido em 2026-10-28;
              idêntico ao corpo canônico de database/schema/5249_binder_storage_change_writers.sql).
Autoridade..: README da proposta §4.1, §5.3, §7.2, §20 (W3), §32 (S5).

Diff mínimo: o corpo é o da base LIVE, byte a byte, mais as linhas marcadas com
"-- P3B-S5". Removidas essas linhas e trocado o delimitador $fn$ → $$, o corpo volta a
ter o md5 acima (static_check_p3b_s5.py). Assinatura, retorno, SET, mensagens, códigos de
erro, ordem de travas e permissões inalterados (REVOKE/GRANT originais reaplicados).

Evento CARDS_LEFT_BY_COLLECTION_STORAGE, origem COLECAO (Organizar armazenamento da coleção):
  · mesma regra da 5287 (evento por fichário afetado, CARD/LEFT por exemplar, I-10, I-8);
  · coleção do evento = a coleção organizada (D8) — o fichário pode ser de outra coleção
    do mesmo dono (fichário compartilhado);
  · posições lidas sobre as travas NOWAIT já adquiridas pela função (passo 6b).
  #variable_conflict use_column: as linhas novas qualificam toda coluna (sem ambiguidade).
================================================================
*/

begin;

do $pre$
begin
  if to_regprocedure('public.binder_activity_add_card_item(text, uuid, uuid, uuid)') is null
     or to_regprocedure('public.binder_activity_begin(uuid, text, text, uuid, jsonb)') is null
     or to_regprocedure('public.binder_activity_end()') is null then
    raise exception 'PRECHECK 5288: dependências ausentes (5268/5271)';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('public.organize_my_collection_storage(uuid, uuid, text, integer, text, boolean)')) is distinct from '083dc24206720b084c0bc5434d93e1fa' then
    raise exception 'PRECHECK 5288: função no LIVE diverge da base 5249 (md5)';
  end if;
end;
$pre$;

CREATE OR REPLACE FUNCTION public.organize_my_collection_storage(
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
as $fn$
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
  v_act_layout  uuid;  -- P3B-S5
  v_act         record;  -- P3B-S5
  v_act_summary jsonb;  -- P3B-S5
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
    -- E06b: um evento por fichário afetado; itens de origem ANTES do DELETE (I-10), com o  -- P3B-S5
    -- mesmo predicado do DELETE e sobre as posições já travadas acima (NOWAIT). Coleção do  -- P3B-S5
    -- evento = a coleção organizada (D8); destino copiado no resumo (R3).  -- P3B-S5
    v_act_summary := jsonb_build_object('storage_container_id', p_storage_container_id,  -- P3B-S5
        'storage_container_name', (select left(sc.name, 200) from public.storage_container sc where sc.id = p_storage_container_id));  -- P3B-S5
    for v_act_layout in  -- P3B-S5
      select distinct p.layout_id  -- P3B-S5
      from public.collection_layout_slot_assignment a  -- P3B-S5
      join public.collection_layout_slot s on s.id = a.slot_id  -- P3B-S5
      join public.collection_layout_page p on p.id = s.page_id  -- P3B-S5
      where a.physical_card_id = any(v_ids)  -- P3B-S5
      order by p.layout_id  -- P3B-S5
    loop  -- P3B-S5
      perform public.binder_activity_begin(v_act_layout, 'CARDS_LEFT_BY_COLLECTION_STORAGE', 'COLECAO', p_collection_id, v_act_summary);  -- P3B-S5
      for v_act in  -- P3B-S5
        select a.physical_card_id, a.slot_id  -- P3B-S5
        from public.collection_layout_slot_assignment a  -- P3B-S5
        join public.collection_layout_slot s on s.id = a.slot_id  -- P3B-S5
        join public.collection_layout_page p on p.id = s.page_id  -- P3B-S5
        where p.layout_id = v_act_layout  -- P3B-S5
          and a.physical_card_id = any(v_ids)  -- P3B-S5
        order by p.page_number, s.row_index, s.column_index  -- P3B-S5
      loop  -- P3B-S5
        perform public.binder_activity_add_card_item('LEFT', v_act.physical_card_id, v_act.slot_id, null);  -- P3B-S5
      end loop;  -- P3B-S5
      perform public.binder_activity_end();  -- P3B-S5
    end loop;  -- P3B-S5
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
$fn$;

revoke all on function public.organize_my_collection_storage(uuid, uuid, text, integer, text, boolean) from public, anon;
grant execute on function public.organize_my_collection_storage(uuid, uuid, text, integer, text, boolean) to authenticated;

commit;

/*
Resultado esperado: organize_my_collection_storage(uuid, uuid, text, integer, text, boolean) recriada com o mesmo contrato; nenhum evento gravado pela
instalação (o histórico só registra quando a função é chamada e tira carta de um bolso).
Como validar (só leitura): LIVE_S5_90_postcheck_readonly.sql, bloco A.
*/
