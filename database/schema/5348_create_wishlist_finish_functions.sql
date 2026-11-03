/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5348 - Lista de desejos por acabamento (V1-11 W3 — Master Set):
              get_catalog_card_variants_for_finish() e
              get_my_wishlist_state_by_card_finish()
Versão......: 1.0
Status......: PROPOSTO — NÃO EXECUTADO no LIVE. Executar só com autorização
              de Fabrício; validar com 5874 logo depois.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-02 (V1-11 W3 | MASTER SET INTEGRATION-01)

Por que existe (lacuna L2 do contrato de produto da Wishlist)
  A posição do Master Set é (carta, acabamento) — 5189/5198 devolvem
  card_id + variant_type_id. O desejo é por Card Variant (5345). As leituras
  da W1 não ligam uma coisa à outra:
    - 5163 (seletor de variantes) devolve as variantes ativas da carta SEM o
      acabamento — oferecer todas seria oferecer variantes incompatíveis com
      a posição;
    - 5346 get_my_wishlist_state_by_card devolve carta → variante desejada,
      também SEM o acabamento — a grade não saberia QUAL posição marcar.
  card_variant não é legível pelo usuário final (RLS admin), então o
  frontend não pode cruzar por conta própria. Esta é a menor extensão:
  duas leituras novas, sem tabela, sem escrita, sem alterar 5163/5346.
  A inclusão e a remoção continuam nas funções da W1 (5346).

Contratos
  1. get_catalog_card_variants_for_finish(p_card_id uuid, p_variant_type_id uuid)
     Variantes ATIVAS de uma carta ATIVA compatíveis com a posição:
       - p_variant_type_id informado → só variantes desse acabamento;
       - p_variant_type_id NULL → posição de carta secreta: qualquer
         acabamento vale (mesma regra de 5198), todas as variantes ativas.
     Colunas: as de 5163 + variant_type_id (o cliente confere de novo).
     Ordem: padrão primeiro, variant_order, id (igual a 5163).
     Nunca escolhe variante: devolve 0, 1 ou N opções; o frontend decide
     entre "sem ação", "inclusão direta" e "escolha explícita".
  2. get_my_wishlist_state_by_card_finish(p_card_ids uuid[])
     Desejos do usuário da sessão nas cartas pedidas (1..500), com o
     acabamento da variante desejada — a grade marca a posição (carta,
     acabamento), e a posição secreta quando há qualquer desejo da carta.
     Mesmas linhas de 5346 get_my_wishlist_state_by_card + variant_type_id.
     Inclui desejos de variantes desativadas (C-214), como a 5346.

Segurança
  SECURITY DEFINER, search_path '', STABLE, identidade só por auth.uid()
  (28000 sem sessão); EXECUTE só para authenticated (PUBLIC e anon
  revogados). A leitura 1 é de catálogo (sem dado de usuário); a 2 filtra
  sempre por user_id = auth.uid() — nenhum outro usuário aparece.

Limites e erros
  22023 INVALID_CARD (carta nula) · 22023 INVALID_CARD_IDS (nulo, vazio, >500).

Desempenho
  1: índice de card_variant por card_id (usado por 5163). 2: mesmo plano de
  5346 (card_wishlist_entry por usuário, junção por PK de card_variant).

Como validar: 5874 (harness, BEGIN/ROLLBACK lógico via sentinela).
================================================================
*/

begin;

-- 1. Variantes compatíveis com a posição --------------------------------------
create or replace function public.get_catalog_card_variants_for_finish(
  p_card_id         uuid,
  p_variant_type_id uuid
)
returns table (
  card_variant_id    uuid,
  variant_type_id    uuid,
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
         cv.variant_type_id,
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
    and (p_variant_type_id is null or cv.variant_type_id = p_variant_type_id)
  order by cv.is_default desc, cv.variant_order, cv.id;
end;
$$;

comment on function public.get_catalog_card_variants_for_finish(uuid, uuid) is
  'V1-11 W3 (Query 5348): variantes ativas de uma carta ativa compatíveis com uma posição de Master Set — só o acabamento pedido; NULL = posição de carta secreta (qualquer acabamento, regra de 5198). Leitura de catálogo; exige auth.uid().';

-- 2. Estado da lista por carta, com acabamento -----------------------------------
create or replace function public.get_my_wishlist_state_by_card_finish(p_card_ids uuid[])
returns table (card_id uuid, variant_type_id uuid, card_variant_id uuid, entry_id uuid, language_code text)
language plpgsql
security definer
stable
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if p_card_ids is null or cardinality(p_card_ids) = 0 or cardinality(p_card_ids) > 500 then
    raise exception 'INVALID_CARD_IDS' using errcode = '22023';
  end if;

  return query
  select cv.card_id, cv.variant_type_id, w.card_variant_id, w.id, l.code::text
  from public.card_wishlist_entry w
  join public.card_variant cv on cv.id = w.card_variant_id
  left join public.language l on l.id = w.language_id
  where w.user_id = v_user
    and cv.card_id = any(p_card_ids);
end;
$$;

comment on function public.get_my_wishlist_state_by_card_finish(uuid[]) is
  'V1-11 W3 (Query 5348): desejos do usuário da sessão nas cartas pedidas (até 500), com o acabamento da variante desejada — marcação das posições (carta, acabamento) do Master Set em uma leitura. Nunca escolhe variante.';

-- Grants ------------------------------------------------------------------------
revoke all on function public.get_catalog_card_variants_for_finish(uuid, uuid) from public;
revoke all on function public.get_catalog_card_variants_for_finish(uuid, uuid) from anon;
grant execute on function public.get_catalog_card_variants_for_finish(uuid, uuid) to authenticated;

revoke all on function public.get_my_wishlist_state_by_card_finish(uuid[]) from public;
revoke all on function public.get_my_wishlist_state_by_card_finish(uuid[]) from anon;
grant execute on function public.get_my_wishlist_state_by_card_finish(uuid[]) to authenticated;

commit;

-- Como validar (rápido; completo na 5874):
-- select p.oid::regprocedure, p.prosecdef, p.proconfig, p.provolatile,
--        has_function_privilege('anon', p.oid, 'EXECUTE') as anon_exec,
--        has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_exec
-- from pg_proc p
-- where p.oid in ('public.get_catalog_card_variants_for_finish(uuid,uuid)'::regprocedure,
--                 'public.get_my_wishlist_state_by_card_finish(uuid[])'::regprocedure);
-- Esperado (2 linhas): t | {search_path=""} | s | f | t
