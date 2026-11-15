/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5372 - Histórico do fichário aceita EDITOR como ator (V1-13 · E1-B1)
              — CREATE OR REPLACE de binder_activity_add_item (5268)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA. Preparada em
              `V1-13 / E1-B1 | EDITOR AUTHORIZATION AND CORE BINDER OPERATIONS-01`
              (2026-11-15). Execução só com prova dinâmica sob protocolo
              controlado (C-244) e autorização expressa e específica.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-15
Contrato....: C-241 (ações do EDITOR geram eventos no histórico do titular,
              com o EDITOR como ator guardado como valor; a gravação só aceita
              ator diferente do titular quando ele é EDITOR ativo da coleção do
              evento), C-204 (titular do evento = dono do fichário).

DEPENDÊNCIA DECLARADA (não é a E1-B3): place/move/remove são instrumentadas
(P3-B S2) e a gravação de hoje (5268) recusa qualquer ator diferente do
titular ("actor is not the binder owner"). Sem esta mudança mínima, toda
escrita do EDITOR da E1-B1 abortaria no primeiro item do histórico. Fica
FORA desta migration o que é da E1-B3/E1-D: coleção por item, leitura do
histórico para membros, lista de permissão de eventos, nome do ator.

Mudança mínima, só no cabeçalho do evento (primeiro item):
  ANTES: v_owner <> v_uid → recusa.
  AGORA: v_owner <> v_uid → recusa, SALVO se o ator for EDITOR ACTIVE da
         coleção registrada no contexto do evento, essa coleção for do mesmo
         titular e participar do fichário do evento (proprietária ou
         convidada). Evento sem coleção registrada com ator ≠ titular →
         recusa (as escritas do EDITOR sempre registram a coleção).
  A atribuição de v_coll subiu uma linha (antes do teste); nada mais muda.
  Caminho do titular (v_owner = v_uid): idêntico.
Assinatura, ACL (sem EXECUTE para API) e SECURITY DEFINER preservados
(CREATE OR REPLACE).
Canal.......: psql. Precheck: md5 do corpo vigente = 5268 canônica
              (5ac90272cf7bc203e5d2316ea4eba7d4, derivado do arquivo; confirmar na S0).
Idempotência: corpo já igual ao desta proposta (59ec5791e514026b7a8340e104d66f30) → 'JÁ APLICADA'.
Reversão....: R5372 em ROLLBACK_E1B1.sql (reaplica o corpo da 5268).
Como validar: harness 5889, seções 3–5 (eventos com ator EDITOR) e 0.4.
================================================================
*/

begin;

set local lock_timeout = '5s';

do $pre$
declare
  v_m text := (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
               where p.oid = to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)'));
begin
  if v_m = '59ec5791e514026b7a8340e104d66f30' then
    raise exception 'PRECHECK 5372: JÁ APLICADA — não reaplicar';
  end if;
  if v_m is distinct from '5ac90272cf7bc203e5d2316ea4eba7d4' then
    raise exception 'PRECHECK 5372: ESTADO DIVERGENTE — corpo vigente difere da 5268 canônica (%)', v_m;
  end if;
  if to_regclass('public.collection_membership') is null then
    raise exception 'PRECHECK 5372: E1-A não aplicada';
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

do $post$
declare
  f oid := to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)');
begin
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = f) is distinct from '59ec5791e514026b7a8340e104d66f30'
     or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
     or (select p.proconfig from pg_catalog.pg_proc p where p.oid = f) is distinct from array['search_path=""']
     or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not false
     or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false
     or pg_catalog.has_function_privilege('service_role', f, 'EXECUTE') is not false then
    raise exception 'POSTCHECK 5372: binder_activity_add_item fora do estado esperado';
  end if;
end;
$post$;

commit;
