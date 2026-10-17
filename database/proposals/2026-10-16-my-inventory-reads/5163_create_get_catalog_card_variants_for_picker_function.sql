/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5163 - get_catalog_card_variants_for_picker(): variantes
              ativas de UMA carta, para o seletor de cartas do
              colecionador (MY-INVENTORY-IMPLEMENTATION-01, Etapa A)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-17
              (MY-INVENTORY-LIVE-DEPLOYMENT-01); validado pelo 5827 (52/52 PASS)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-16

Contexto (diagnóstico):
O seletor de cartas precisa de dois passos de catálogo:
  1. Achar a carta — JÁ EXISTE: public.search_cards() (Query 4032,
     LIVE), SECURITY DEFINER, authenticated, paginada (≤ 60), com
     imagem pt-BR/en. Reutilizada sem alteração.
  2. Escolher a variante — NÃO EXISTE leitura customer-facing:
     card_variant e eixos têm RLS admin-only (ADR-022) e
     register_physical_cards_bulk (5150) exige card_variant_id.
Esta função cobre só o passo 2, no menor contrato possível.

Contrato:
  get_catalog_card_variants_for_picker(p_card_id uuid)
  RETURNS TABLE(card_variant_id, is_default_variant, variant_label,
                variant_order)

- Só variantes ATIVAS de carta ATIVA (mesma regra de 5152 — variante
  inativa não é registrável).
- Nenhuma coluna administrativa (códigos, legado, traits, ids de eixo).
- Carta inexistente/inativa → zero linhas.
- Não amplia o catálogo: uma carta por chamada, ≤ número de variantes
  dela (VR do catálogo: máximo atual por carta medido em 5827 §0).

Segurança: SECURITY DEFINER, STABLE, search_path '', auth.uid()
obrigatório (28000), EXECUTE só para authenticated.
Erros (22023): INVALID_CARD (nulo).

Como validar: Query 5827.
================================================================
*/

begin;

create or replace function public.get_catalog_card_variants_for_picker(
  p_card_id uuid
)
returns table (
  card_variant_id    uuid,
  is_default_variant boolean,
  variant_label      text,
  variant_order      integer
)
language plpgsql
security definer
stable
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if p_card_id is null then
    raise exception 'INVALID_CARD' using errcode = '22023';
  end if;

  return query
  select cv.id,
         cv.is_default,
         nullif(concat_ws(' · ', vt.name, pp.name, ec.name), '')::text,
         cv.variant_order
  from public.card c
  join public.card_variant cv on cv.card_id = c.id and cv.is_active
  left join public.card_variant_type vt            on vt.id = cv.variant_type_id
  left join public.card_printing_profile pp        on pp.id = cv.printing_profile_id
  left join public.card_edition_context_profile ec on ec.id = cv.edition_context_profile_id
  where c.id = p_card_id
    and c.is_active
  order by cv.is_default desc, cv.variant_order, cv.id;
end;
$$;

comment on function public.get_catalog_card_variants_for_picker(uuid) is
  'Seletor de cartas (Query 5163): variantes ativas de uma carta ativa — id, padrão, rótulo (acabamento · tiragem · contexto) e ordem. Sem dados administrativos. Exige auth.uid().';

revoke all on function public.get_catalog_card_variants_for_picker(uuid) from public;
revoke all on function public.get_catalog_card_variants_for_picker(uuid) from anon;
grant execute on function public.get_catalog_card_variants_for_picker(uuid) to authenticated;

commit;
