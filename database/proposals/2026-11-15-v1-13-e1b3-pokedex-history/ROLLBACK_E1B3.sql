/*
================================================================
Projeto.....: Project Mimikyu
Query.......: ROLLBACK_E1B3 — reversão de 5378–5380 (V1-13 · E1-B3)
Versão......: 1.1 (2026-11-15, `HISTORY INTEGRITY REVIEW-02`: reversão da 5379
              preserva o histórico; remoção de colunas só antes de uso)
Status......: PROPOSTA — NÃO EXECUTADA. Uso exclusivo de recuperação, pelo
              proprietário, com autorização expressa. Ordem obrigatória:
              R5380 → R5379 → R5378 (inversa da aplicação), cada bloco uma
              transação própria (psql). Vem ANTES de ROLLBACK_E1B2 e
              ROLLBACK_E1B1, se forem necessários (R5372 espera o corpo da 5372).
              R5379-D (no fim) NÃO faz parte da reversão padrão.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-15
Efeito......: retira as RPCs de Pokédex do EDITOR; devolve
              binder_activity_add_item ao corpo da 5372 (cópia literal; md5
              59ec5791e514026b7a8340e104d66f30) — a ESCRITA da atribuição para,
              mas as duas colunas e tudo o que foi gravado PERMANECEM (histórico
              imutável, C-179). A 5372 é compatível com a estrutura ampliada: não
              nomeia as colunas novas, então grava item NULL e evento false, que
              significam "não atribuído" — nunca uma atribuição falsa. Devolve
              binder_slot_editor_scope ao corpo da 5371 (cópia literal; md5
              3086014a164704f309c7051419df3f23).
              Reaplicar a 5379 depois disto é seguro: o precheck aceita as
              colunas existentes com a forma exata e o ADD COLUMN é IF NOT EXISTS.
              Mesmo depois de ROLLBACK_E1B1 (corpo da 5268) as colunas são
              inertes: nenhuma função antiga as lê ou escreve.
              Posições e representantes gravados por EDITOR PERMANECEM (estado da
              coleção): a reversão retira capacidades, não desfaz edições.
================================================================
*/

-- R5380 -------------------------------------------------------------------------------------
begin;
set local lock_timeout = '5s';
drop function if exists public.editor_set_pokedex_position_assignment(uuid, uuid, uuid, boolean);
drop function if exists public.editor_remove_pokedex_position_assignment(uuid, uuid);
drop function if exists public.editor_set_pokedex_position_primary_representative(uuid, uuid);
drop function if exists public.editor_clear_pokedex_position_primary_representative(uuid, uuid);
drop function if exists public.editor_pokedex_of_collection(uuid);
commit;

-- R5379 -------------------------------------------------------------------------------------
begin;
set local lock_timeout = '5s';

do $pre$
begin
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)'))
     is distinct from 'f8cfba40e442e85056e7c8ce7954d4f4' then
    raise exception 'R5379: corpo vigente não é o da 5379 — reversão interrompida';
  end if;
end;
$pre$;

create or replace function public.binder_activity_add_item(
  p_kind            text,
  p_effect          text,
  p_card_id         uuid    default null,
  p_variant_type_id uuid    default null,
  p_from_slot_id    uuid    default null,
  p_to_slot_id      uuid    default null,
  p_from_page       integer default null,
  p_to_page         integer default null,
  p_detail          jsonb   default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_ctx      jsonb := nullif(current_setting('mmkyu.binder_activity_ctx', true), '')::jsonb;
  v_uid      uuid  := (select auth.uid());
  v_layout   uuid;
  v_event    bigint;
  v_n        integer;
  v_cap      bigint;
  v_cap_now  bigint;
  c_repeat_slack constant integer := 600;   -- ≥ 5264 c_row_limit (500) + c_item_limit (100); ≥ 5243 c_row_limit (500)
  v_owner    uuid;
  v_binder   text;
  v_coll     uuid;
  v_collname text;
  f_page int; f_row int; f_col int;
  t_page int; t_row int; t_col int;
  c_name text; c_num text; c_set text; vt_code text; vt_name text;
begin
  if v_ctx is null or (v_ctx ->> 'depth')::integer < 1 then
    raise exception 'binder activity: no open operation' using errcode = 'P0001', hint = 'BINDER_ACTIVITY_NO_CONTEXT';
  end if;
  if v_uid is null then
    raise exception 'binder activity requires an authenticated actor' using errcode = '28000';
  end if;
  v_layout := (v_ctx ->> 'layout')::uuid;
  v_event  := (v_ctx ->> 'event_id')::bigint;
  v_n      := (v_ctx ->> 'n')::integer + 1;
  v_cap    := coalesce((v_ctx ->> 'cap')::bigint, 0);

  -- W1: teto derivado da capacidade + folga de repetição (ver cabeçalho). Calculado no
  -- primeiro item (cap = 0), em todo PAGE_ADDED e quando excedido; guarda o máximo observado.
  if v_n > v_cap or (p_kind = 'PAGE' and p_effect = 'PAGE_ADDED') then
    select count(p.id) * (8::bigint * l.grid_rows * l.grid_columns + 2) + 8 + c_repeat_slack
      into v_cap_now
    from public.collection_layout l
    left join public.collection_layout_page p on p.layout_id = l.id
    where l.id = v_layout
    group by l.grid_rows, l.grid_columns;
    v_cap := greatest(v_cap, coalesce(v_cap_now, 8 + c_repeat_slack));
    if v_n > v_cap then
      raise exception 'binder activity: item limit exceeded (% > %)', v_n, v_cap using errcode = 'P0001',
        hint = 'BINDER_ACTIVITY_ITEM_LIMIT';
    end if;
    v_ctx := jsonb_set(v_ctx, '{cap}', to_jsonb(v_cap));
  end if;

  if v_event is null then
    -- Cabeçalho no primeiro item: titular e nomes copiados agora.
    select c.owner_user_id, coalesce(nullif(l.display_name, ''), c.name)
      into v_owner, v_binder
    from public.collection_layout l
    join public.collection c on c.id = l.collection_id
    where l.id = v_layout;
    if v_owner is null then
      raise exception 'binder activity: binder not found' using errcode = 'P0002', hint = 'BINDER_ACTIVITY_LAYOUT_NOT_FOUND';
    end if;
    v_coll := nullif(v_ctx ->> 'collection', '')::uuid;
    if v_owner <> v_uid then
      -- V1-13 E1-B1 (5372): ator diferente do titular só como EDITOR ACTIVE da coleção
      -- do evento, coleção do mesmo titular e participante deste fichário (C-241).
      -- Defesa em profundidade: a função de escrita já autorizou e travou (5371).
      if v_coll is null
         or not exists (select 1 from public.collection_membership m
                        where m.collection_id = v_coll and m.user_id = v_uid
                          and m.status = 'ACTIVE' and m.role = 'EDITOR')
         or not exists (select 1 from public.collection c
                        where c.id = v_coll and c.owner_user_id = v_owner)
         or not (exists (select 1 from public.collection_layout l
                         where l.id = v_layout and l.collection_id = v_coll)
                 or exists (select 1 from public.collection_layout_guest g
                            where g.layout_id = v_layout and g.collection_id = v_coll)) then
        raise exception 'binder activity: actor is not the binder owner' using errcode = '42501',
          hint = 'BINDER_ACTIVITY_NOT_OWNER';
      end if;
    end if;
    if v_coll is not null then
      select c.name into v_collname from public.collection c where c.id = v_coll and c.owner_user_id = v_owner;
    end if;
    insert into public.binder_activity_event
      (owner_user_id, layout_key, actor_user_id, event_type, source,
       collection_id, collection_name, binder_name, summary)
    values
      (v_owner, v_layout, v_uid, v_ctx ->> 'type', v_ctx ->> 'source',
       case when v_collname is not null then v_coll end, left(v_collname, 200), left(v_binder, 200),
       coalesce(v_ctx -> 'summary', '{}'::jsonb))
    returning id into v_event;
    v_ctx := jsonb_set(v_ctx, '{event_id}', to_jsonb(v_event));
  end if;

  -- Posições copiadas agora (R3); bolso de outro fichário → erro.
  if p_from_slot_id is not null then
    select p.page_number, s.row_index, s.column_index into f_page, f_row, f_col
    from public.collection_layout_slot s join public.collection_layout_page p on p.id = s.page_id
    where s.id = p_from_slot_id and p.layout_id = v_layout;
    if f_page is null then
      raise exception 'binder activity: origin pocket not in binder' using errcode = 'P0001', hint = 'BINDER_ACTIVITY_SLOT';
    end if;
  else
    f_page := p_from_page;
  end if;
  if p_to_slot_id is not null then
    select p.page_number, s.row_index, s.column_index into t_page, t_row, t_col
    from public.collection_layout_slot s join public.collection_layout_page p on p.id = s.page_id
    where s.id = p_to_slot_id and p.layout_id = v_layout;
    if t_page is null then
      raise exception 'binder activity: target pocket not in binder' using errcode = 'P0001', hint = 'BINDER_ACTIVITY_SLOT';
    end if;
  else
    t_page := p_to_page;
  end if;

  -- Cópia da carta e do acabamento.
  if p_card_id is not null then
    select k.name, k.collector_number, cs.code into c_name, c_num, c_set
    from public.card k join public.card_set cs on cs.id = k.card_set_id
    where k.id = p_card_id;
    if c_name is null then
      raise exception 'binder activity: card not found' using errcode = 'P0002', hint = 'BINDER_ACTIVITY_CARD';
    end if;
  end if;
  if p_variant_type_id is not null then
    select t.code, t.name into vt_code, vt_name from public.card_variant_type t where t.id = p_variant_type_id;
  end if;

  insert into public.binder_activity_item
    (event_id, ordinal, item_kind, effect, card_id, card_name, collector_number, card_set_code,
     variant_type_code, variant_type_name, from_page, from_row, from_col, to_page, to_row, to_col, detail)
  values
    (v_event, v_n, p_kind, p_effect, p_card_id, left(c_name, 200), left(c_num, 40), left(c_set, 40),
     left(vt_code, 60), left(vt_name, 120), f_page, f_row, f_col, t_page, t_row, t_col, p_detail);

  v_ctx := jsonb_set(v_ctx, '{n}', to_jsonb(v_n));
  perform set_config('mmkyu.binder_activity_ctx', v_ctx::text, true);
end;
$fn$;

-- As colunas e os dados ficam (nenhum DROP aqui).

do $post$
begin
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)'))
     is distinct from '59ec5791e514026b7a8340e104d66f30' then
    raise exception 'R5379: corpo restaurado diverge da 5372';
  end if;
  if (select count(*) from information_schema.columns c
       where c.table_schema = 'public'
         and ((c.table_name = 'binder_activity_item' and c.column_name = 'collection_id')
              or (c.table_name = 'binder_activity_event' and c.column_name = 'item_collection_recorded'))) <> 2 then
    raise exception 'R5379: as colunas de atribuição deveriam permanecer';
  end if;
end;
$post$;
commit;

-- R5378 -------------------------------------------------------------------------------------
begin;
set local lock_timeout = '5s';

create or replace function public.binder_slot_editor_scope(
  p_layout_id            uuid,
  p_anchor_collection_id uuid,
  p_collection_id        uuid,
  p_slot_id              uuid
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_page    uuid;
  v_row     integer;
  v_col     integer;
  v_locked  boolean;
  v_card    uuid;
  v_card_cl uuid;
  v_res_cl  uuid;
  v_res     boolean;
  v_spc_cl  uuid;
  v_own     boolean := false;
begin
  select s.page_id, s.row_index, s.column_index, s.locked
    into v_page, v_row, v_col, v_locked
  from public.collection_layout_slot s
  join public.collection_layout_page p on p.id = s.page_id
  where s.id = p_slot_id and p.layout_id = p_layout_id;
  if v_page is null then
    return 'FOREIGN';
  end if;

  -- Carta: só é de X se o exemplar estiver alocado a X.
  select a.physical_card_id, ca.collection_id into v_card, v_card_cl
  from public.collection_layout_slot_assignment a
  left join public.collection_allocation ca on ca.physical_card_id = a.physical_card_id
  where a.slot_id = p_slot_id;
  if v_card is not null then
    if v_card_cl is distinct from p_collection_id then
      return 'FOREIGN';
    end if;
    v_own := true;
  end if;

  -- Reserva: sem coleção registrada = da proprietária (C-196).
  select true, coalesce(e.collection_id, p_anchor_collection_id) into v_res, v_res_cl
  from public.collection_layout_slot_expected_content e
  where e.slot_id = p_slot_id;
  if v_res then
    if v_res_cl is distinct from p_collection_id then
      return 'FOREIGN';
    end if;
    v_own := true;
  end if;

  -- Imagem personalizada e região mesclada: sempre do titular / fora da E1-B1.
  if exists (select 1 from public.collection_layout_slot_image i where i.slot_id = p_slot_id) then
    return 'FOREIGN';
  end if;
  if exists (select 1 from public.collection_layout_region r
             where r.page_id = v_page
               and v_row between r.top_row and r.top_row + r.height - 1
               and v_col between r.left_column and r.left_column + r.width - 1) then
    return 'FOREIGN';
  end if;

  -- Referência de espécie: só é de X se registrada para X.
  select sr.collection_id into v_spc_cl
  from public.collection_layout_slot_species_reference sr
  where sr.slot_id = p_slot_id;
  if found then
    if v_spc_cl is distinct from p_collection_id then
      return 'FOREIGN';
    end if;
  end if;

  -- Trava: sem carta nem reserva de X, o bolso fixado é do titular.
  if v_locked and not v_own then
    return 'FOREIGN';
  end if;

  return case when v_own then 'OWN' else 'FREE' end;
end;
$fn$;

do $post$
begin
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.binder_slot_editor_scope(uuid, uuid, uuid, uuid)'))
     is distinct from '3086014a164704f309c7051419df3f23' then
    raise exception 'R5378: corpo restaurado diverge da 5371';
  end if;
end;
$post$;
commit;

-- R5379-D (OPCIONAL, FORA DA REVERSÃO PADRÃO) -----------------------------------------------
-- Remove as colunas de atribuição SOMENTE se a 5379 nunca foi usada: a gravação já
-- voltou à 5372 (R5379) e não existe nenhum evento atribuído nem item com coleção.
-- Depois do primeiro uso real, recusa: o histórico atribuído não se apaga por reversão.
begin;
set local lock_timeout = '5s';

do $pre$
begin
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)'))
     is distinct from '59ec5791e514026b7a8340e104d66f30' then
    raise exception 'R5379-D: aplique R5379 antes (a gravação ainda usa as colunas)';
  end if;
  if exists (select 1 from public.binder_activity_event e where e.item_collection_recorded)
     or exists (select 1 from public.binder_activity_item i where i.collection_id is not null) then
    raise exception 'R5379-D: RECUSADO — já existe histórico atribuído; as colunas ficam (reversão conservadora)';
  end if;
end;
$pre$;

alter table public.binder_activity_event drop column if exists item_collection_recorded;
alter table public.binder_activity_item drop column if exists collection_id;
commit;
