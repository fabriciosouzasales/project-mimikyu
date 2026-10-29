/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5271 - P3-B S2 · Histórico do Fichário — item de carta física
              binder_activity_add_card_item(text, uuid, uuid, uuid)   — interna
Versão......: 1.0 (2026-10-27, P3-B S2 — instrumentação E02–E05)
Status......: PROPOSTA — NÃO EXECUTADA. Exige autorização própria para o LIVE.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-27
Autoridade..: C-205, C-206; LDM-199–LDM-201; README da proposta §4.1, §7.2, §20, §29.

Por que existe: E02–E05 (S2) e depois E06a/E06b/E07/E19 (S5/S6) registram itens de
CARTA a partir de um exemplar físico (`physical_card`). A cópia do catálogo (carta e
acabamento) precisa ser resolvida no momento do evento (R3), sempre do mesmo jeito.
Esta função faz só isso e delega a gravação a `binder_activity_add_item` (5268):

  · exemplar → card_variant → (card_id, variant_type_id);
  · item CARD com o efeito informado, origem/destino por bolso (a 5268 converte em
    página/linha/coluna e recusa bolso de outro fichário);
  · detail = {"physical_card_id": …} — permite à interface abrir o exemplar no
    Meu acervo; nada além disso (sem valor, sem coleção, sem local).

Contrato W3: não abre nem fecha operação (sem begin/end) e não grava direto — I-5.
Exemplar inexistente → erro (nunca item sem carta). Interna: SECURITY DEFINER,
search_path vazio, EXECUTE revogado de PUBLIC/anon/authenticated/service_role.
Dependências: 5268; physical_card; card_variant.
================================================================
*/

begin;

do $pre$
begin
  if to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)') is null then
    raise exception 'PRECHECK 5271: aplique a 5268 antes';
  end if;
  if to_regprocedure('public.binder_activity_add_card_item(text, uuid, uuid, uuid)') is not null then
    raise exception 'PRECHECK 5271: função já existe';
  end if;
end;
$pre$;

create function public.binder_activity_add_card_item(
  p_effect           text,
  p_physical_card_id uuid,
  p_from_slot_id     uuid,
  p_to_slot_id       uuid
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
begin
  select cv.card_id, cv.variant_type_id into v_card, v_vt
  from public.physical_card pc
  join public.card_variant cv on cv.id = pc.card_variant_id
  where pc.id = p_physical_card_id;
  if v_card is null then
    raise exception 'binder activity: physical card not found' using errcode = 'P0002', hint = 'BINDER_ACTIVITY_CARD';
  end if;
  perform public.binder_activity_add_item('CARD', p_effect, v_card, v_vt, p_from_slot_id, p_to_slot_id,
                                          null, null, jsonb_build_object('physical_card_id', p_physical_card_id));
end;
$fn$;

revoke all on function public.binder_activity_add_card_item(text, uuid, uuid, uuid) from public, anon, authenticated, service_role;

comment on function public.binder_activity_add_card_item(text, uuid, uuid, uuid) is
  'P3-B 5271 (interna): item CARD do evento aberto a partir de um exemplar físico — cópia de carta e acabamento no momento (R3), bolsos de origem/destino e physical_card_id no detalhe. Grava só via 5268.';

commit;
