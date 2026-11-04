/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5352 - Lista de desejos em lote (V1-11 W7 — faltantes de Set e
              Master Set): get_catalog_card_variants_for_cards() e
              add_my_wishlist_entries()
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE (2026-11-04 UTC, LIVE SQL VALIDATION-04;
              ledger 20261104005319; corpo executado = este arquivo, sem edição).
              Harness 5878: GATE PASS 13/13, resíduo zero.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-03 (V1-11 W7 | BULK ADD MISSING CARDS-01)

Por que existe (lacuna comprovada)
  O contrato (wishlist-product-contract.md §4.2) pede a inclusão de faltantes
  em lote com prévia separando "inclusões diretas", "já na lista" e "exigem
  escolha". Para classificar centenas de posições é preciso saber, por carta,
  quais variantes ativas existem (e de qual acabamento). Hoje só há leituras
  de UMA carta (5163, 5348) — o lote viraria uma chamada por carta, e
  card_variant não é legível pelo usuário final (RLS admin). A gravação
  também é de um desejo por chamada (5346 add_my_wishlist_entry): um lote de
  200 seriam 200 idas ao banco, sem resultado único.
  Menor extensão: uma leitura de catálogo em lote e uma inclusão em lote.
  Sem tabela, sem índice, sem alterar 5163/5346/5348.

Contratos
  1. get_catalog_card_variants_for_cards(p_card_ids uuid[])
     Variantes ATIVAS das cartas ATIVAS pedidas (1..500 ids distintos), com
     o acabamento — exatamente as linhas que 5348
     get_catalog_card_variants_for_finish(card, NULL) devolveria para cada
     carta, mais card_id. Nunca escolhe variante: o frontend classifica
     0 (sem ação) / 1 (direta) / N (escolha explícita), por posição.
     Ordem: card_id, padrão primeiro, variant_order, id.
  2. add_my_wishlist_entries(p_card_variant_ids uuid[])
     Inclui na Lista do usuário da sessão, em UMA transação, as variantes
     pedidas (1..500 ids; repetidos contam uma vez), sempre "qualquer
     idioma" (language_id NULL, C-92 — o idioma específico continua sendo
     escolha individual). Uma linha por variante pedida:
       CREATED     — desejo novo;
       EXISTING    — o desejo "qualquer idioma" já existia (idempotente:
                     repetir o lote não duplica);
       UNAVAILABLE — variante inexistente ou desativada (carta ou variante
                     inativa): nada gravado para ela.
     Não grava nada fora de card_wishlist_entry: nenhuma coleção, posição,
     exemplar, alocação, reserva ou progresso (C-211).
     Concorrência: insert com ON CONFLICT DO NOTHING (unique NULLS NOT
     DISTINCT de 5345) em ordem de id; os já existentes são lidos depois do
     insert (nova leitura vê o que outra sessão acabou de gravar).

Segurança
  SECURITY DEFINER, search_path '', identidade só por auth.uid() (28000 sem
  sessão); EXECUTE só authenticated (PUBLIC e anon revogados). A leitura 1 é
  de catálogo (sem dado de usuário); a 2 só grava/lê linhas com
  user_id = auth.uid() — o cliente nunca envia user_id.

Limites e erros
  22023 INVALID_CARD_IDS (nulo, vazio, elemento nulo ou > 500 distintos)
  22023 INVALID_CARD_VARIANT_IDS (idem).

Desempenho
  1: card por PK + card_variant pelo índice por card_id (o mesmo de 5163),
     uma chamada para até 500 cartas.
  2: card_variant/card por PK; insert pela unique; releitura pelo prefixo
     (user_id, card_variant_id) da unique. Uma chamada por lote.

Como validar: 5878 (harness, sentinela TR000, resíduo zero).
Como reverter:
  drop function if exists public.add_my_wishlist_entries(uuid[]);
  drop function if exists public.get_catalog_card_variants_for_cards(uuid[]);
================================================================
*/

begin;

-- 1. Variantes ativas de várias cartas ------------------------------------------
create or replace function public.get_catalog_card_variants_for_cards(p_card_ids uuid[])
returns table (
  card_id            uuid,
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
#variable_conflict use_column
declare
  v_ids uuid[];
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if p_card_ids is null or array_position(p_card_ids, null) is not null then
    raise exception 'INVALID_CARD_IDS' using errcode = '22023';
  end if;

  select array_agg(distinct x) into v_ids from unnest(p_card_ids) x;

  if v_ids is null or cardinality(v_ids) > 500 then
    raise exception 'INVALID_CARD_IDS' using errcode = '22023';
  end if;

  return query
  select c.id,
         cv.id,
         cv.variant_type_id,
         cv.is_default,
         nullif(concat_ws(' · ', vt.name, pp.name, ec.name), '')::text,
         cv.variant_order
  from public.card c
  join public.card_variant cv on cv.card_id = c.id and cv.is_active
  left join public.card_variant_type vt            on vt.id = cv.variant_type_id
  left join public.card_printing_profile pp        on pp.id = cv.printing_profile_id
  left join public.card_edition_context_profile ec on ec.id = cv.edition_context_profile_id
  where c.id = any(v_ids)
    and c.is_active
  order by c.id, cv.is_default desc, cv.variant_order, cv.id;
end;
$$;

comment on function public.get_catalog_card_variants_for_cards(uuid[]) is
  'V1-11 W7 (Query 5352): variantes ativas (com acabamento) de até 500 cartas ativas, numa chamada — base da prévia de faltantes em lote. Mesmas linhas de 5348 com acabamento NULL, por carta. Leitura de catálogo; exige auth.uid().';

revoke all on function public.get_catalog_card_variants_for_cards(uuid[]) from public;
revoke all on function public.get_catalog_card_variants_for_cards(uuid[]) from anon;
grant execute on function public.get_catalog_card_variants_for_cards(uuid[]) to authenticated;

-- 2. Inclusão em lote ("qualquer idioma") ----------------------------------------
create or replace function public.add_my_wishlist_entries(p_card_variant_ids uuid[])
returns table (card_variant_id uuid, entry_id uuid, outcome text)
language plpgsql
security definer
volatile
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user    uuid := auth.uid();
  v_ids     uuid[];
  v_ok      uuid[];
  v_created uuid[];
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if p_card_variant_ids is null or array_position(p_card_variant_ids, null) is not null then
    raise exception 'INVALID_CARD_VARIANT_IDS' using errcode = '22023';
  end if;

  select array_agg(distinct x) into v_ids from unnest(p_card_variant_ids) x;

  if v_ids is null or cardinality(v_ids) > 500 then
    raise exception 'INVALID_CARD_VARIANT_IDS' using errcode = '22023';
  end if;

  -- Só variantes ativas de cartas ativas (mesma regra de add_my_wishlist_entry).
  select coalesce(array_agg(cv.id order by cv.id), '{}') into v_ok
  from public.card_variant cv
  join public.card c on c.id = cv.card_id
  where cv.id = any(v_ids)
    and cv.is_active
    and c.is_active;

  with ins as (
    insert into public.card_wishlist_entry (user_id, card_variant_id, language_id)
    select v_user, x, null
    from unnest(v_ok) x
    order by x
    on conflict on constraint uq_card_wishlist_entry_user_variant_language do nothing
    returning card_wishlist_entry.card_variant_id
  )
  select coalesce(array_agg(ins.card_variant_id), '{}') into v_created from ins;

  return query
  select w.card_variant_id,
         w.id,
         case when w.card_variant_id = any(v_created) then 'CREATED' else 'EXISTING' end
  from public.card_wishlist_entry w
  where w.user_id = v_user
    and w.card_variant_id = any(v_ok)
    and w.language_id is null;

  return query
  select x, null::uuid, 'UNAVAILABLE'
  from unnest(v_ids) x
  where not (x = any(v_ok));
end;
$$;

comment on function public.add_my_wishlist_entries(uuid[]) is
  'V1-11 W7 (Query 5352): inclui em lote (até 500, uma transação) variantes ativas na Lista de desejos do usuário da sessão, sempre "qualquer idioma". Idempotente. Uma linha por variante: CREATED, EXISTING ou UNAVAILABLE. Não toca coleção, exemplar, alocação ou fichário.';

revoke all on function public.add_my_wishlist_entries(uuid[]) from public;
revoke all on function public.add_my_wishlist_entries(uuid[]) from anon;
grant execute on function public.add_my_wishlist_entries(uuid[]) to authenticated;

commit;
