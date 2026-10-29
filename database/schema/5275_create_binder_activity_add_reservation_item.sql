/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5275 - P3-B S3 · Histórico do Fichário — item de reserva de bolso
              binder_activity_add_reservation_item(text, uuid)   — interna
Versão......: 1.0 (2026-10-27, P3-B S3 — instrumentação E08–E10)
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core em 2026-10-27
              (P3-B S3, autorização expressa de Fabrício; harness dispensado sob H-A
              só para a S3; ledger 20261027221555 `5275_create_binder_activity_add_reservation_item`). Do `begin;` ao `commit;`
              idêntica ao arquivo de database/proposals/2026-10-25-p3b-binder-
              activity-history/ (só este bloco Status difere); enviada via
              apply_migration sem as linhas `begin;`/`commit;` externas — o texto
              gravado no ledger é igual ao corpo enviado (md5).
              LIVE_S3_90 bloco A 7/7; bloco B v1.1 6/6. Troca de reserva no mesmo
              evento não exercitada; concorrência e desempenho não medidos. README §30.8–§30.10.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-27
Autoridade..: C-205, C-206; LDM-199–LDM-201; README da proposta §4.1, §7.2, §20, §30.

Por que existe: E08/E09 (S3) e depois E18 (S6) registram itens de RESERVA a partir da
reserva que está no bolso naquele instante. A cópia do catálogo (carta e acabamento)
precisa ser resolvida no momento do evento (R3), sempre do mesmo jeito. Esta função
lê a reserva atual do bolso e delega a gravação a `binder_activity_add_item` (5268):

  · reserva → (card_id, acabamento): o acabamento pedido; senão o da variante
    específica reservada; senão nenhum;
  · RELEASED → origem = bolso (chamar ANTES de apagar/sobrescrever, I-10);
    RESERVED → destino = bolso (chamar DEPOIS de gravar);
  · detail = {"collection_id", "card_variant_id"} (nulos omitidos) — coleção dona da
    reserva (D8) e variante específica, quando houver. Nada além disso.

Contrato W3: não abre nem fecha operação (sem begin/end) e não grava direto — I-5.
Bolso sem reserva ou efeito fora de RESERVED/RELEASED → erro (nunca item sem carta).
Interna: SECURITY DEFINER, search_path vazio, EXECUTE revogado de
PUBLIC/anon/authenticated/service_role.
Dependências: 5268; collection_layout_slot_expected_content; card_variant.
================================================================
*/

begin;

do $pre$
begin
  if to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)') is null then
    raise exception 'PRECHECK 5275: aplique a 5268 antes';
  end if;
  if to_regprocedure('public.binder_activity_add_reservation_item(text, uuid)') is not null then
    raise exception 'PRECHECK 5275: função já existe';
  end if;
end;
$pre$;

create function public.binder_activity_add_reservation_item(
  p_effect  text,
  p_slot_id uuid
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_card uuid;
  v_vt   uuid;
  v_cv   uuid;
  v_coll uuid;
begin
  if p_effect is null or p_effect not in ('RESERVED', 'RELEASED') then
    raise exception 'binder activity: invalid reservation effect' using errcode = '22023', hint = 'BINDER_ACTIVITY_RESERVATION';
  end if;
  select e.card_id, coalesce(e.expected_variant_type_id, cv.variant_type_id), e.card_variant_id, e.collection_id
    into v_card, v_vt, v_cv, v_coll
  from public.collection_layout_slot_expected_content e
  left join public.card_variant cv on cv.id = e.card_variant_id
  where e.slot_id = p_slot_id;
  if v_card is null then
    raise exception 'binder activity: reservation not found' using errcode = 'P0002', hint = 'BINDER_ACTIVITY_RESERVATION';
  end if;
  perform public.binder_activity_add_item('RESERVATION', p_effect, v_card, v_vt,
                                          case when p_effect = 'RELEASED' then p_slot_id end,
                                          case when p_effect = 'RESERVED' then p_slot_id end,
                                          null, null,
                                          jsonb_strip_nulls(jsonb_build_object('collection_id', v_coll, 'card_variant_id', v_cv)));
end;
$fn$;

revoke all on function public.binder_activity_add_reservation_item(text, uuid) from public, anon, authenticated, service_role;

comment on function public.binder_activity_add_reservation_item(text, uuid) is
  'P3-B 5275 (interna): item RESERVATION do evento aberto a partir da reserva atual do bolso — carta e acabamento copiados no momento (R3), bolso como origem (RELEASED) ou destino (RESERVED), coleção e variante no detalhe. Grava só via 5268.';

commit;
