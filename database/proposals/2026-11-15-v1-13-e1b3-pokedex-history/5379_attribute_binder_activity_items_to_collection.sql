/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5379 - Histórico do fichário: coleção de cada item e marca de
              atribuição por evento (V1-13 · E1-B3) — ALTER TABLE em
              binder_activity_item/binder_activity_event e CREATE OR REPLACE de
              binder_activity_add_item (5268 → 5372 → 5379)
Versão......: 1.1 (2026-11-15, `HISTORY INTEGRITY REVIEW-02`: reaplicação aceita colunas preservadas por
              reversão conservadora; corpo da função inalterado). 1.0 (2026-11-15)
Status......: PROPOSTA — NÃO EXECUTADA. Preparada em
              `V1-13 / E1-B3 | POKÉDEX AND ACTIVITY HISTORY FOUNDATION-01`
              (2026-11-15). Execução só com prova dinâmica sob protocolo
              controlado (C-244) e autorização expressa e específica.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-15
Contrato....: C-241 (o membro vê só itens que se referem a exemplares, reservas
              ou bolsos de X; item de outra coleção dentro de um evento de X não
              aparece nem entra em contagens e resumos; a gravação só aceita ator
              diferente do titular quando ele é EDITOR ativo da coleção do evento),
              C-204 (titular do evento), C-179 (imutabilidade).
Depende de..: E1-B1 (5372). Não toca a leitura do titular (5269) nem nenhuma
              função instrumentada: todas chamam binder_activity_add_item com a
              mesma assinatura.

O que muda (fundação; a LEITURA para membros é da E1-D):
  1. binder_activity_item.collection_id uuid NULL — coleção do item, guardada
     como VALOR (sem FK, como layout_key), gravada uma vez e nunca reescrita
     (gatilho de imutabilidade 5267 intacto). ADD COLUMN sem DEFAULT: só
     catálogo, sem reescrita da tabela.
  2. binder_activity_event.item_collection_recorded boolean NOT NULL DEFAULT
     false — marca os eventos cujos itens passaram pela atribuição desta
     migration (true) e separa o histórico anterior (false). DEFAULT constante:
     só catálogo, sem reescrita; as linhas existentes ficam false sem UPDATE.
  3. binder_activity_add_item, no ponto de gravação do item:
     - deriva a coleção do item do conteúdo real, no mesmo instante:
         CARD        → alocação vigente do exemplar (detalhe physical_card_id);
         RESERVATION → coleção da reserva (detalhe collection_id, copiado pela
                       5275/5279); sem coleção registrada = proprietária (C-196);
         POCKET      → conteúdo do bolso na ordem da classificação (carta, senão
                       reserva, senão referência de espécie); imagem do titular
                       → NULL;
         PAGE, COLLECTION, BINDER → NULL (estrutura do fichário);
       coleção de outro titular → NULL. Nada vem de parâmetro do cliente.
     - ator ≠ titular (EDITOR): todo item CARD/RESERVATION/POCKET precisa ser da
       coleção do evento e itens COLLECTION/BINDER são recusados
       (42501 BINDER_ACTIVITY_CROSS_COLLECTION). Defesa em profundidade: as
       escritas do EDITOR (5374/5375) já só tocam bolsos de X.
     - novo evento grava item_collection_recorded = true.
     - todo item confere que o evento do contexto é desta operação: mesmo
       fichário, mesmo ator e gravado nesta transação (created_xact); contexto
       forjado com event_id de outro evento → 42501 BINDER_ACTIVITY_FORGED_CONTEXT.
       Vale para qualquer ator (nenhuma operação legítima abre contexto alheio).
     Caminho do titular: mesma validação e mesmas linhas; só ganha a coleção
     do item. Nenhuma recusa nova no uso legítimo (a única nova para o titular
     é a de contexto forjado, que nenhuma função instrumentada produz).

Histórico anterior: eventos com item_collection_recorded = false nunca têm
  item atribuído retroativamente (imutáveis; nenhuma inferência). Como a leitura
  de membros os trata é a decisão D12, PENDENTE (README, "Histórico anterior").
A coleção do item NÃO concede visibilidade: eventos estruturais e de acervo
  (E01, E06, E07, E17–E20) também têm itens atribuídos e continuam ocultos pela
  lista de tipos da C-241 (E1-D).
Custo: até 3 leituras por índice a mais por item (alocação por exemplar,
  reserva e referência pelo bolso, evento pela PK). Eventos grandes (organização
  automática, centenas de itens) ficam proporcionalmente mais lentos; não medido.
Canal.......: psql. Precheck: md5 do corpo vigente = 5372
              (59ec5791e514026b7a8340e104d66f30); colunas ausentes OU
              presentes com a forma exata desta migration (reaplicação depois de
              uma reversão conservadora, que preserva as colunas e os dados).
Idempotência: corpo = f8cfba40e442e85056e7c8ce7954d4f4 e colunas presentes → 'JÁ APLICADA'.
Reversão....: R5379 em ROLLBACK_E1B3.sql: reaplica o corpo da 5372 e PRESERVA
              as colunas e tudo o que foi gravado (a 5372 grava sem elas: item
              NULL, evento false = "não atribuído"). A remoção das colunas é um
              bloco à parte (R5379-D), só antes de qualquer uso: recusa se houver
              um único evento atribuído.
Como validar: harness 5891, seções 3–5.
================================================================
*/

begin;

set local lock_timeout = '5s';

do $pre$
declare
  v_m text := (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
               where p.oid = to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)'));
  v_ci boolean := exists (select 1 from information_schema.columns c
                          where c.table_schema = 'public' and c.table_name = 'binder_activity_item' and c.column_name = 'collection_id');
  v_ce boolean := exists (select 1 from information_schema.columns c
                          where c.table_schema = 'public' and c.table_name = 'binder_activity_event' and c.column_name = 'item_collection_recorded');
  v_ci_ok boolean := exists (select 1 from information_schema.columns c
                             where c.table_schema = 'public' and c.table_name = 'binder_activity_item'
                               and c.column_name = 'collection_id' and c.data_type = 'uuid'
                               and c.is_nullable = 'YES' and c.column_default is null);
  v_ce_ok boolean := exists (select 1 from information_schema.columns c
                             where c.table_schema = 'public' and c.table_name = 'binder_activity_event'
                               and c.column_name = 'item_collection_recorded' and c.data_type = 'boolean'
                               and c.is_nullable = 'NO' and c.column_default = 'false');
begin
  if v_m = 'f8cfba40e442e85056e7c8ce7954d4f4' and v_ci and v_ce then
    raise exception 'PRECHECK 5379: JÁ APLICADA — não reaplicar';
  end if;
  if v_m is distinct from '59ec5791e514026b7a8340e104d66f30' then
    raise exception 'PRECHECK 5379: ESTADO DIVERGENTE — corpo vigente difere da 5372 (%)', v_m;
  end if;
  if (v_ci and not v_ci_ok) or (v_ce and not v_ce_ok) or (v_ci <> v_ce) then
    raise exception 'PRECHECK 5379: ESTADO DIVERGENTE — colunas de atribuição presentes com forma diferente';
  end if;
  if to_regclass('public.collection_layout_slot_species_reference') is null then
    raise exception 'PRECHECK 5379: 5257 ausente';
  end if;
end;
$pre$;

-- IF NOT EXISTS: na reaplicação depois de uma reversão conservadora as colunas (e os
-- dados) já estão lá, com a forma conferida no precheck.
alter table public.binder_activity_item add column if not exists collection_id uuid null;
alter table public.binder_activity_event add column if not exists item_collection_recorded boolean not null default false;

comment on column public.binder_activity_item.collection_id is
  'V1-13 E1-B3 (5379): coleção do item, derivada no servidor no instante da gravação (exemplar → alocação; reserva → coleção registrada ou proprietária; bolso → conteúdo). Valor sem FK, nunca reescrito. NULL = item sem coleção (estrutura, imagem do titular, exemplar sem coleção) ou evento não atribuído (ver item_collection_recorded). Não concede visibilidade: a leitura de membros filtra antes pelo tipo de evento (C-241).';
comment on column public.binder_activity_event.item_collection_recorded is
  'V1-13 E1-B3 (5379): true = os itens deste evento passaram pela atribuição de coleção da 5379. false = evento não atribuído (anterior à 5379 ou gravado com a 5379 revertida): itens sem coleção registrada, nunca atribuídos retroativamente.';

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
  v_ev_owner uuid;   -- E1-B3 (5379)
  v_ev_coll  uuid;
  v_ev_lay   uuid;
  v_ev_actor uuid;
  v_ev_xact  xid8;
  v_islot    uuid;
  v_icoll    uuid;
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
       collection_id, collection_name, binder_name, summary, item_collection_recorded)
    values
      (v_owner, v_layout, v_uid, v_ctx ->> 'type', v_ctx ->> 'source',
       case when v_collname is not null then v_coll end, left(v_collname, 200), left(v_binder, 200),
       coalesce(v_ctx -> 'summary', '{}'::jsonb), true)
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

  -- V1-13 E1-B3 (5379): coleção do item, derivada no servidor no instante da gravação e
  -- só do conteúdo real do fichário (nunca de parâmetro do cliente). NULL = item sem
  -- coleção: estrutura do fichário (PAGE, COLLECTION, BINDER), imagem do titular,
  -- exemplar sem coleção, bolso sem conteúdo.
  select e.owner_user_id, e.collection_id, e.layout_key, e.actor_user_id, e.created_xact
    into v_ev_owner, v_ev_coll, v_ev_lay, v_ev_actor, v_ev_xact
  from public.binder_activity_event e where e.id = v_event;
  -- O evento do contexto precisa ser o desta operação: mesmo fichário, mesmo ator e
  -- gravado nesta transação. Contexto forjado (event_id de outro evento) → recusa.
  if v_ev_lay is distinct from v_layout or v_ev_actor is distinct from v_uid
     or v_ev_xact is distinct from pg_catalog.pg_current_xact_id() then
    raise exception 'binder activity: event context does not belong to this operation' using errcode = '42501',
      hint = 'BINDER_ACTIVITY_FORGED_CONTEXT';
  end if;
  v_islot := coalesce(p_to_slot_id, p_from_slot_id);
  if p_kind = 'CARD' then
    -- Exemplar: a alocação vigente (uma por exemplar).
    if p_detail ? 'physical_card_id' then
      select ca.collection_id into v_icoll
      from public.collection_allocation ca
      where ca.physical_card_id = (p_detail ->> 'physical_card_id')::uuid;
    end if;
  elsif p_kind = 'RESERVATION' then
    -- Reserva: a coleção registrada (5275/5279 copiam no detalhe); sem coleção
    -- registrada = proprietária do fichário (C-196).
    if p_detail ? 'collection_id' then
      v_icoll := (p_detail ->> 'collection_id')::uuid;
    elsif v_islot is not null then
      select coalesce(x.collection_id, l.collection_id) into v_icoll
      from public.collection_layout_slot_expected_content x
      join public.collection_layout l on l.id = v_layout
      where x.slot_id = v_islot;
    end if;
  elsif p_kind = 'POCKET' and v_islot is not null and coalesce(p_detail ->> 'content', '') <> 'IMAGE' then
    -- Bolso (fixar/soltar): o conteúdo que o classifica, na mesma ordem da 5371/5378 —
    -- carta (a alocação dela, ou nenhuma), senão reserva, senão referência de espécie.
    perform 1 from public.collection_layout_slot_assignment a where a.slot_id = v_islot;
    if found then
      select ca.collection_id into v_icoll
      from public.collection_layout_slot_assignment a
      join public.collection_allocation ca on ca.physical_card_id = a.physical_card_id
      where a.slot_id = v_islot;
    else
      select coalesce(x.collection_id, l.collection_id) into v_icoll
      from public.collection_layout_slot_expected_content x
      join public.collection_layout l on l.id = v_layout
      where x.slot_id = v_islot;
      if not found then
        select sr.collection_id into v_icoll
        from public.collection_layout_slot_species_reference sr
        where sr.slot_id = v_islot;
      end if;
    end if;
  end if;
  if v_icoll is not null
     and not exists (select 1 from public.collection c where c.id = v_icoll and c.owner_user_id = v_ev_owner) then
    v_icoll := null;   -- nunca atribui a coleção de outro titular
  end if;
  -- Ator que não é o titular (EDITOR, 5372): todo item de conteúdo precisa ser da
  -- coleção do evento; itens estruturais (COLLECTION, BINDER) nunca são dele.
  if v_uid is distinct from v_ev_owner
     and (p_kind in ('COLLECTION', 'BINDER')
          or (p_kind in ('CARD', 'RESERVATION', 'POCKET') and v_icoll is distinct from v_ev_coll)) then
    raise exception 'binder activity: item outside the authorized collection' using errcode = '42501',
      hint = 'BINDER_ACTIVITY_CROSS_COLLECTION';
  end if;

  insert into public.binder_activity_item
    (event_id, ordinal, item_kind, effect, card_id, card_name, collector_number, card_set_code,
     variant_type_code, variant_type_name, from_page, from_row, from_col, to_page, to_row, to_col, detail,
     collection_id)
  values
    (v_event, v_n, p_kind, p_effect, p_card_id, left(c_name, 200), left(c_num, 40), left(c_set, 40),
     left(vt_code, 60), left(vt_name, 120), f_page, f_row, f_col, t_page, t_row, t_col, p_detail,
     v_icoll);

  v_ctx := jsonb_set(v_ctx, '{n}', to_jsonb(v_n));
  perform set_config('mmkyu.binder_activity_ctx', v_ctx::text, true);
end;
$fn$;

do $post$
declare
  f oid := to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)');
begin
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = f) is distinct from 'f8cfba40e442e85056e7c8ce7954d4f4'
     or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
     or (select p.proconfig from pg_catalog.pg_proc p where p.oid = f) is distinct from array['search_path=""']
     or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not false
     or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false
     or pg_catalog.has_function_privilege('service_role', f, 'EXECUTE') is not false then
    raise exception 'POSTCHECK 5379: binder_activity_add_item fora do estado esperado';
  end if;
  if (select c.is_nullable from information_schema.columns c
       where c.table_schema = 'public' and c.table_name = 'binder_activity_item' and c.column_name = 'collection_id') <> 'YES'
     or (select c.is_nullable || ':' || c.column_default from information_schema.columns c
          where c.table_schema = 'public' and c.table_name = 'binder_activity_event' and c.column_name = 'item_collection_recorded') <> 'NO:false' then
    raise exception 'POSTCHECK 5379: colunas fora do estado esperado';
  end if;
  if exists (select 1 from pg_catalog.pg_trigger t
             where t.tgrelid in ('public.binder_activity_event'::regclass, 'public.binder_activity_item'::regclass)
               and not t.tgisinternal and t.tgenabled <> 'O') then
    raise exception 'POSTCHECK 5379: gatilhos de imutabilidade fora do estado esperado';
  end if;
end;
$post$;

commit;
