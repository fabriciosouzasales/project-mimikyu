/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5343 - Fichário (P2): prévia da organização automática
Versão......: 1.0
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core em 2026-11-01
              (P2 LIVE GATE 02, ledger 20261101140115 `p2_5343_create_preview_my_binder_auto_arrange`). Do `begin;` ao fim
              idêntica ao arquivo de database/proposals/2026-11-01-binder-auto-arrange/
              (só este bloco Status difere). md5 do corpo instalado = arquivo:
              14dee353691b8dfc499bc33aa50b7c35 (GATE 04 SRC). Harness 5872 v1.5 54/54 PASS (GATE 03 RERUN-15);
              postcheck e medição ME3 PASS (GATE 04). Homologada em
              P2 SQL FOUNDATION CLOSEOUT-16. Ver README da proposta.
              Histórico da proposta: (P2 AUTO-ARRANGE SQL FOUNDATION-06, 2026-11-01)
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-01

Objetivo
  RPC de leitura que mostra ao titular o que a organização automática faria no
  fichário da coleção informada, sem escrever nada, e devolve o token que a
  confirmação (5344) exige. Prévia obrigatória (D11).

Assinatura
  public.preview_my_binder_auto_arrange(p_collection_id uuid) returns jsonb
  SECURITY DEFINER · STABLE · search_path '' · EXECUTE só para authenticated.

Fronteiras (deny by default)
  · sem sessão                                → 28000 not_authenticated
  · argumento nulo                            → 22023 INVALID_ARGUMENT
  · coleção inexistente ou de outro usuário   → P0002 COLLECTION_NOT_FOUND
    (os dois casos colapsam — sem enumeração)
  · coleção arquivada                         → 55000 COLLECTION_ARCHIVED
  · tipo fora de Set/Master Set (Pokédex, Livre, Set sem política) →
                                                22023 AUTO_ARRANGE_UNSUPPORTED_COLLECTION
  · coleção convidada de fichário alheio      → 42501 AUTO_ARRANGE_NOT_BINDER_OWNER
  · coleção sem fichário                      → P0002 BINDER_NOT_FOUND
  Tipo é verificado antes do fichário: Pokédex/Livre recebem sempre o mesmo
  motivo, tenham fichário ou não.

Retorno (jsonb)
  {
    "status":            "READY" | "EMPTY" | "LIMIT_EXCEEDED",
    "insert_count":      n,
    "limit":             500,
    "plan_token":        "aa1:…",
    "excluded_cards":    { "<motivo>": n, … },
    "unfilled_slots":    { "<motivo>": n, … },
    "unfilled_count":    n,
    "pages":             [page_number, …]    -- páginas afetadas, ordenadas
    "items":             [ {ord, slot_id, physical_card_id, page_number,
                            row_index, column_index, card_id, card_variant_id}, … ]
  }
  items vem vazio quando status = LIMIT_EXCEEDED (nada será aplicado; a prévia
  não carrega 500+ linhas inúteis). Os ids devolvidos são de objetos do próprio
  titular (bolsos e exemplares dele); nenhum UUID de usuário é exposto.

Resultado esperado: função criada; EXECUTE apenas authenticated.
Como validar: harness 5872, S0.* e A.*.
================================================================
*/

begin;

do $pre$
begin
  if to_regprocedure('public.binder_auto_arrange_plan(uuid,uuid,uuid)') is null then
    raise exception 'PRECHECK 5343: 5342 ausente';
  end if;
  if to_regprocedure('public.preview_my_binder_auto_arrange(uuid)') is not null then
    raise exception 'PRECHECK 5343: função já existe';
  end if;
end;
$pre$;

create function public.preview_my_binder_auto_arrange(p_collection_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  c_limit     constant integer := 500;
  v_uid       uuid := auth.uid();
  v_mode      text;
  v_policy    text;
  v_status    text;
  v_layout    uuid;
  v_container uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  select c.mode, c.completion_policy, c.lifecycle_status
    into v_mode, v_policy, v_status
  from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_status <> 'ACTIVE' then
    raise exception 'COLLECTION_ARCHIVED' using errcode = '55000';
  end if;
  if v_mode is distinct from 'REFERENCE_BASED'
     or v_policy is null or v_policy not in ('STANDARD_SET', 'MASTER_SET') then
    raise exception 'AUTO_ARRANGE_UNSUPPORTED_COLLECTION' using errcode = '22023';
  end if;

  select l.id, l.storage_container_id into v_layout, v_container
  from public.collection_layout l
  where l.collection_id = p_collection_id;
  if v_layout is null then
    if exists (select 1 from public.collection_layout_guest g where g.collection_id = p_collection_id) then
      raise exception 'AUTO_ARRANGE_NOT_BINDER_OWNER' using errcode = '42501';
    end if;
    raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- Plano calculado UMA vez (CTE referenciada várias vezes ⇒ materializada).
  return (
    with plan as materialized (
      select * from public.binder_auto_arrange_plan(p_collection_id, v_layout, v_container)
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
                                     'ord', p.ord, 'slot_id', p.slot_id, 'physical_card_id', p.physical_card_id,
                                     'page_number', p.page_number, 'row_index', p.row_index,
                                     'column_index', p.column_index, 'card_id', p.card_id,
                                     'card_variant_id', p.card_variant_id) order by p.ord)
                                  from plan p where p.item_kind = 'INSERT'), '[]'::jsonb) end
    )
    from h
  );
end;
$fn$;

revoke all on function public.preview_my_binder_auto_arrange(uuid) from public, anon;
grant execute on function public.preview_my_binder_auto_arrange(uuid) to authenticated;

comment on function public.preview_my_binder_auto_arrange(uuid) is
  'P2 5343 (C-220..C-226): prévia somente leitura da organização automática do fichário da coleção (titular, Set/Master Set, proprietária). Devolve status READY/EMPTY/LIMIT_EXCEEDED, contagens por motivo, itens (até 500) e plan_token aa1 exigido por apply_my_binder_auto_arrange.';

notify pgrst, 'reload schema';

commit;
