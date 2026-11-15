/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5386 - Organização automática do fichário pelo EDITOR, só no fichário
              exclusivo da coleção autorizada (V1-13 · E1-C2)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA. Preparada em
              `V1-13 / E1-C2 | REMAINING BULK OPERATIONS-01` (2026-11-15).
              Execução só com prova dinâmica sob protocolo controlado (C-244) e
              autorização expressa e específica.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-15
Contrato....: C-220–C-226 (organização automática), C-235 (o EDITOR coloca só
              exemplar alocado à coleção e guardado no fichário), C-237 (operação em
              massa: só no fichário de uma coleção), C-242, C-243.
Depende de..: 5342/5360 (binder_auto_arrange_plan — REUSADO, plano e token
              idênticos aos do titular), 5385 (ajudantes), 5382, 5384 (tipo
              CARDS_AUTO_ARRANGED para o EDITOR).

O que o plano canônico faz (5342/5360, inalterado):
  - Set padrão / Master Set: insere exemplar de X (alocado a X, no local do
    fichário, fora de bolso) em bolso VAZIO com reserva da proprietária (= X no
    fichário exclusivo), não fixado, sem imagem, fora de mesclagem, 1:1 estrito
    (sem desempate arbitrário: grau 1 dos dois lados);
  - Pokédex: insere a REPRESENTANTE da espécie (5204/5360) em bolso VAZIO com
    referência de espécie de X, sem reserva, imagem, trava ou mesclagem;
  - nunca move, retira ou substitui carta; nunca toca reserva, trava, imagem,
    referência, alocação, local ou condição. Só INSERT de posições.
  Nenhuma regra de prioridade nova: o EDITOR recebe exatamente o plano do titular.
RPCs novas (EXECUTE só authenticated):
  editor_preview_binder_auto_arrange(p_collection_id) → jsonb
      (status, insert_count, limit, plan_token, excluded_cards, unfilled_slots,
       unfilled_count, pages, items[ord, physical_card_id, page_number,
       row_index, column_index, card_id, card_variant_id]) — como a 5360, sem
       slot_id; só conteúdo de X (o plano só considera X).
  editor_apply_binder_auto_arrange(p_collection_id, p_plan_token) → jsonb
      (status: APPLIED | ALREADY_APPLIED | NOTHING_TO_DO, inserted, event_id, pages)
Regras adicionais do EDITOR:
  - fichário exclusivo (5382/5385);
  - todo bolso de destino precisa ser OWN para X (reserva ou referência de X,
    nada de terceiros) → senão OPERATION_RESERVED_TO_OWNER, antes de escrever
    (defesa em profundidade: o plano já só escolhe bolsos de X);
  - mesmo limite de 500, mesmo token, mesmo ALREADY_APPLIED (evento do fichário e
    do titular com o mesmo token, gravado pelo titular ou pelo EDITOR).
Travas: proprietária → layout → participação (5382) → bolsos (por id) →
  exemplares (por id), igual à 5360 depois da 5122; plano recalculado sob as
  travas e comparado ao token.
Histórico: CARDS_AUTO_ARRANGED (FICHARIO, coleção X), um item PLACED por carta (X).
Funções do titular (5342/5343/5344/5360): não tocadas. DEVER DE ESPELHO (README).
Canal.......: psql. Idempotência: funções já presentes → 'JÁ APLICADA ou
              DIVERGENTE'. Reversão: R5386 em ROLLBACK_E1C2.sql.
Como validar: harness 5893, seção 2.
================================================================
*/

begin;

set local lock_timeout = '5s';

do $pre$
begin
  if to_regprocedure('public.binder_auto_arrange_plan(uuid, uuid, uuid)') is null
     or to_regprocedure('public.editor_binder_exclusive_read(uuid)') is null
     or to_regprocedure('public.binder_editor_any_foreign(uuid, uuid, uuid[])') is null then
    raise exception 'PRECHECK 5386: 5360 ou 5385 ausentes';
  end if;
  if to_regprocedure('public.editor_preview_binder_auto_arrange(uuid)') is not null
     or to_regprocedure('public.editor_apply_binder_auto_arrange(uuid, text)') is not null then
    raise exception 'PRECHECK 5386: JÁ APLICADA ou ESTADO DIVERGENTE';
  end if;
end;
$pre$;

-- Prévia ---------------------------------------------------------------------------------------
create function public.editor_preview_binder_auto_arrange(p_collection_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  c_limit  constant integer := 500;
  r        record;
  v_mode   text;
  v_policy text;
  v_slots  uuid[];
begin
  select * into r from public.editor_binder_exclusive_read(p_collection_id) x;
  select c.mode, c.completion_policy into v_mode, v_policy from public.collection c where c.id = p_collection_id;
  if v_mode is distinct from 'REFERENCE_BASED'
     or v_policy is null or v_policy not in ('STANDARD_SET', 'MASTER_SET', 'REFERENCE_POSITION') then
    raise exception 'AUTO_ARRANGE_UNSUPPORTED_COLLECTION' using errcode = '22023';
  end if;

  select array_agg(h.slot_id) filter (where h.item_kind = 'INSERT') into v_slots
  from public.binder_auto_arrange_plan(p_collection_id, r.layout_id, r.container_id) h;
  if public.binder_editor_any_foreign(r.layout_id, p_collection_id, v_slots) then
    raise exception 'OPERATION_RESERVED_TO_OWNER' using errcode = '42501',
      hint = 'a organização alcançaria bolsos que só o titular pode alterar';
  end if;

  return (
    with plan as materialized (
      select * from public.binder_auto_arrange_plan(p_collection_id, r.layout_id, r.container_id)
    ),
    h as (
      select p.insert_count as n, p.plan_token as t,
             case when p.insert_count = 0 then 'EMPTY'
                  when p.insert_count > c_limit then 'LIMIT_EXCEEDED'
                  else 'READY' end as st
      from plan p where p.item_kind = 'HEADER'
    )
    select jsonb_build_object(
      'status',         h.st,
      'insert_count',   h.n,
      'limit',          c_limit,
      'plan_token',     h.t,
      'excluded_cards', coalesce((select jsonb_object_agg(x.reason, x.n)
                                  from (select p.reason, count(*) as n from plan p
                                        where p.item_kind = 'EXCLUDED_CARD' group by p.reason) x), '{}'::jsonb),
      'unfilled_slots', coalesce((select jsonb_object_agg(x.reason, x.n)
                                  from (select p.reason, count(*) as n from plan p
                                        where p.item_kind = 'UNFILLED_SLOT' group by p.reason) x), '{}'::jsonb),
      'unfilled_count', (select count(*) from plan p where p.item_kind = 'UNFILLED_SLOT'),
      'pages',          coalesce((select jsonb_agg(distinct p.page_number order by p.page_number)
                                  from plan p where p.item_kind = 'INSERT'), '[]'::jsonb),
      'items',          case when h.st = 'LIMIT_EXCEEDED' then '[]'::jsonb
                             else coalesce((select jsonb_agg(jsonb_build_object(
                                     'ord', p.ord, 'physical_card_id', p.physical_card_id,
                                     'page_number', p.page_number, 'row_index', p.row_index,
                                     'column_index', p.column_index, 'card_id', p.card_id,
                                     'card_variant_id', p.card_variant_id) order by p.ord)
                                  from plan p where p.item_kind = 'INSERT'), '[]'::jsonb) end
    )
    from h
  );
end;
$fn$;

-- Aplicar --------------------------------------------------------------------------------------
create function public.editor_apply_binder_auto_arrange(p_collection_id uuid, p_plan_token text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  c_limit  constant integer := 500;
  r        record;
  v_mode   text;
  v_policy text;
  v_n      integer;
  v_token  text;
  v_event  bigint;
  v_rows   integer;
  v_slots  uuid[];
  v_cards  uuid[];
  v_pages  jsonb;
begin
  if p_collection_id is null or p_plan_token is null or p_plan_token !~ '^aa1:[0-9a-f]{64}$' then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  select * into r from public.assert_collection_binder_editor_exclusive(p_collection_id) x;
  select c.mode, c.completion_policy into v_mode, v_policy from public.collection c where c.id = p_collection_id;
  if v_mode is distinct from 'REFERENCE_BASED'
     or v_policy is null or v_policy not in ('STANDARD_SET', 'MASTER_SET', 'REFERENCE_POSITION') then
    raise exception 'AUTO_ARRANGE_UNSUPPORTED_COLLECTION' using errcode = '22023';
  end if;

  select max(h.plan_token), max(h.insert_count),
         array_agg(h.slot_id order by h.slot_id) filter (where h.item_kind = 'INSERT'),
         array_agg(h.physical_card_id order by h.physical_card_id) filter (where h.item_kind = 'INSERT')
    into v_token, v_n, v_slots, v_cards
  from public.binder_auto_arrange_plan(p_collection_id, r.layout_id, r.container_id) h;

  if v_token is distinct from p_plan_token then
    select e.id into v_event
    from public.binder_activity_event e
    where e.layout_key = r.layout_id
      and e.owner_user_id = r.owner_user_id
      and e.event_type = 'CARDS_AUTO_ARRANGED'
      and e.summary ->> 'plan_token' = p_plan_token
    order by e.id desc
    limit 1;
    if v_event is not null then
      return jsonb_build_object('status', 'ALREADY_APPLIED', 'inserted', 0, 'event_id', v_event);
    end if;
    raise exception 'AUTO_ARRANGE_PLAN_CHANGED' using errcode = '40001',
      hint = 'o fichário mudou desde a prévia — gere uma nova prévia';
  end if;
  if v_n = 0 then
    return jsonb_build_object('status', 'NOTHING_TO_DO', 'inserted', 0);
  end if;
  if v_n > c_limit then
    raise exception 'AUTO_ARRANGE_LIMIT_EXCEEDED' using errcode = '54000',
      detail = format('%s inserções planejadas; limite %s por confirmação', v_n, c_limit);
  end if;
  if public.binder_editor_any_foreign(r.layout_id, p_collection_id, v_slots) then
    raise exception 'OPERATION_RESERVED_TO_OWNER' using errcode = '42501',
      hint = 'a organização alcançaria bolsos que só o titular pode alterar';
  end if;

  perform 1 from public.collection_layout_slot s where s.id = any (v_slots) order by s.id for update of s;
  perform 1 from public.physical_card pc where pc.id = any (v_cards) order by pc.id for update of pc;

  select max(h.plan_token),
         array_agg(h.slot_id order by h.ord) filter (where h.item_kind = 'INSERT'),
         array_agg(h.physical_card_id order by h.ord) filter (where h.item_kind = 'INSERT'),
         coalesce(jsonb_agg(distinct h.page_number order by h.page_number) filter (where h.item_kind = 'INSERT'), '[]'::jsonb)
    into v_token, v_slots, v_cards, v_pages
  from public.binder_auto_arrange_plan(p_collection_id, r.layout_id, r.container_id) h;
  if v_token is distinct from p_plan_token then
    raise exception 'AUTO_ARRANGE_PLAN_CHANGED' using errcode = '40001',
      hint = 'o fichário mudou desde a prévia — gere uma nova prévia';
  end if;

  perform public.binder_activity_begin(r.layout_id, 'CARDS_AUTO_ARRANGED', 'FICHARIO', p_collection_id,
                                       jsonb_build_object('plan_token', p_plan_token, 'inserted', v_n));
  v_rows := 0;
  for i in 1 .. coalesce(array_length(v_slots, 1), 0) loop
    begin
      insert into public.collection_layout_slot_assignment (slot_id, physical_card_id)
      values (v_slots[i], v_cards[i]);
    exception
      when unique_violation then
        raise exception 'AUTO_ARRANGE_PLAN_CHANGED' using errcode = '40001',
          hint = 'o fichário mudou desde a prévia — gere uma nova prévia';
    end;
    perform public.binder_activity_add_card_item('PLACED', v_cards[i], null, v_slots[i]);
    v_rows := v_rows + 1;
  end loop;
  if v_rows <> v_n then
    raise exception 'AUTO_ARRANGE_PLAN_CHANGED' using errcode = '40001';
  end if;
  v_event := (nullif(current_setting('mmkyu.binder_activity_ctx', true), '')::jsonb ->> 'event_id')::bigint;
  perform public.binder_activity_end();

  return jsonb_build_object('status', 'APPLIED', 'inserted', v_rows, 'event_id', v_event, 'pages', v_pages);
end;
$fn$;

comment on function public.editor_preview_binder_auto_arrange(uuid) is
  'V1-13 E1-C2 (5386): prévia da organização automática para o EDITOR do fichário exclusivo (mesmo plano e token da 5360; sem ids de bolso).';
comment on function public.editor_apply_binder_auto_arrange(uuid, text) is
  'V1-13 E1-C2 (5386): EDITOR confirma a organização automática do fichário exclusivo (espelho da 5360): só posiciona exemplares de X em bolsos vazios de X.';

revoke all on function public.editor_preview_binder_auto_arrange(uuid) from public, anon;
revoke all on function public.editor_apply_binder_auto_arrange(uuid, text) from public, anon;
grant execute on function public.editor_preview_binder_auto_arrange(uuid) to authenticated;
grant execute on function public.editor_apply_binder_auto_arrange(uuid, text) to authenticated;

do $post$
declare
  f oid;
begin
  foreach f in array array[to_regprocedure('public.editor_preview_binder_auto_arrange(uuid)'),
                           to_regprocedure('public.editor_apply_binder_auto_arrange(uuid, text)')] loop
    if f is null
       or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
       or (select p.proconfig from pg_catalog.pg_proc p where p.oid = f) is distinct from array['search_path=""']
       or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not true
       or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false then
      raise exception 'POSTCHECK 5386: RPC fora do estado esperado (%)', f;
    end if;
  end loop;
end;
$post$;

commit;
