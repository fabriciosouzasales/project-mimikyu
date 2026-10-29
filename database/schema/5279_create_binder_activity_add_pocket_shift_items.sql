/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5279 - P3-B S4 · Histórico do Fichário — itens de deslocamento de bolso
              binder_activity_add_pocket_shift_items(uuid, uuid)   — interna
Versão......: 1.0 (2026-10-27, P3-B S4 — instrumentação E11–E15)
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core (P3-B S4, autorização
              expressa de Fabrício; harness dispensado sob H-A; ledger 20261027231843 `5279_create_binder_activity_add_pocket_shift_items`).
              Do `begin;` ao `commit;` idêntica ao arquivo de database/proposals/2026-10-25-
              p3b-binder-activity-history/ (só este bloco Status difere); enviada via
              apply_migration sem as linhas `begin;`/`commit;` externas — texto do ledger = corpo (md5).
              LIVE_S4_90 bloco A 7/7; bloco B 9/9 + amostra.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-27
Autoridade..: C-205, C-206; LDM-199–LDM-201; README da proposta §5.2, §7.2, §20, §31.

Por que existe: abrir/fechar espaço (E11/E12, S4) e incorporar novidades (E16, S6) deslocam
o conteúdo inteiro de um bolso para outro com `binder_gap_move_pocket` (interna, sem
permissão para clientes). A interna NÃO é instrumentada (é chamada também pela E16, ainda
sem contexto aberto até a S6). Esta função, chamada pela operação externa DEPOIS dos
deslocamentos, lê o conteúdo que está agora no bolso de destino e grava um item SHIFTED
por objeto, com origem → destino:

  · CARD/SHIFTED        — exemplar físico do bolso (via 5271, cópia da carta e acabamento);
  · RESERVATION/SHIFTED — reserva do bolso (carta, acabamento, coleção e variante no detalhe);
  · POCKET/SHIFTED      — imagem personalizada do bolso (detail {"content":"IMAGE"}).

Fixação (locked) e referência de espécie ficam no bolso — não se deslocam (5243, D1).
Bolso de destino vazio → nenhum item. Contrato W3: não abre nem fecha operação e não grava
direto (I-5). Interna: SECURITY DEFINER, search_path vazio, EXECUTE revogado de
PUBLIC/anon/authenticated/service_role.
Dependências: 5268, 5271; collection_layout_slot_assignment, _slot_expected_content,
_slot_image; card_variant.
================================================================
*/

begin;

do $pre$
begin
  if to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)') is null
     or to_regprocedure('public.binder_activity_add_card_item(text, uuid, uuid, uuid)') is null then
    raise exception 'PRECHECK 5279: aplique 5268 e 5271 antes';
  end if;
  if to_regprocedure('public.binder_activity_add_pocket_shift_items(uuid, uuid)') is not null then
    raise exception 'PRECHECK 5279: função já existe';
  end if;
end;
$pre$;

create function public.binder_activity_add_pocket_shift_items(
  p_from uuid,
  p_to   uuid
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_pc   uuid;
  v_card uuid;
  v_vt   uuid;
  v_cv   uuid;
  v_coll uuid;
begin
  if p_from is null or p_to is null or p_from = p_to then
    raise exception 'binder activity: invalid shift' using errcode = '22023', hint = 'BINDER_ACTIVITY_SHIFT';
  end if;

  select a.physical_card_id into v_pc
  from public.collection_layout_slot_assignment a where a.slot_id = p_to;
  if v_pc is not null then
    perform public.binder_activity_add_card_item('SHIFTED', v_pc, p_from, p_to);
  end if;

  select e.card_id, coalesce(e.expected_variant_type_id, cv.variant_type_id), e.card_variant_id, e.collection_id
    into v_card, v_vt, v_cv, v_coll
  from public.collection_layout_slot_expected_content e
  left join public.card_variant cv on cv.id = e.card_variant_id
  where e.slot_id = p_to;
  if v_card is not null then
    perform public.binder_activity_add_item('RESERVATION', 'SHIFTED', v_card, v_vt, p_from, p_to, null, null,
                                            jsonb_strip_nulls(jsonb_build_object('collection_id', v_coll, 'card_variant_id', v_cv)));
  end if;

  if exists (select 1 from public.collection_layout_slot_image i where i.slot_id = p_to) then
    perform public.binder_activity_add_item('POCKET', 'SHIFTED', null, null, p_from, p_to, null, null,
                                            jsonb_build_object('content', 'IMAGE'));
  end if;
end;
$fn$;

revoke all on function public.binder_activity_add_pocket_shift_items(uuid, uuid) from public, anon, authenticated, service_role;

comment on function public.binder_activity_add_pocket_shift_items(uuid, uuid) is
  'P3-B 5279 (interna): itens SHIFTED do evento aberto para o conteúdo que está agora no bolso de destino (exemplar, reserva, imagem), com origem → destino. Chamada pela operação externa depois dos deslocamentos. Grava só via 5268/5271.';

commit;
