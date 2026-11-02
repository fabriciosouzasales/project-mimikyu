/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5346 - Funções da Lista de desejos (V1-11 W1): incluir, remover,
              estado em lote (por variante e por carta) e listagem paginada
Versão......: 1.0
Status......: PROPOSTO — NÃO EXECUTADO (V1-11 W1 IMPLEMENTATION-01, 2026-11-01)
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-01

Padrão (o mesmo da 5336, Favoritos de cartas)
  SECURITY DEFINER, search_path '', objetos qualificados; identidade só de
  auth.uid() (o cliente nunca envia user_id, C-102/C-217); EXECUTE só
  authenticated (REVOKE de PUBLIC e anon). Sem identidade → 28000.
  Nenhuma função lê ou escreve Collection, Binder, Allocation ou posição
  (C-211/LDM-204); a posse é só LIDA do Inventory do próprio usuário.

Funções
  1. add_my_wishlist_entry(p_card_variant_id uuid, p_language_code text default null)
     → table(entry_id uuid, created boolean, language_code text)
     Inclui o desejo; idempotente: repetir devolve a mesma entrada com
     created = false (unicidade NULLS NOT DISTINCT, 5345; ON CONFLICT DO
     NOTHING + releitura, seguro sob concorrência). Idioma vazio/NULL =
     qualquer (C-92); senão um código ativo de public.language.
     Erros: 22023 INVALID_CARD_VARIANT_ID / INVALID_LANGUAGE;
            P0002 CARD_VARIANT_UNAVAILABLE (inexistente, inativa ou de carta
            inativa — inclusão só em variante ativa, C-214).

  2. remove_my_wishlist_entries(p_entry_ids uuid[]) → integer
     Remove desejos do próprio usuário por id (um ou vários — seleção
     múltipla). Idempotente: ids alheios, inexistentes ou já removidos são
     ignorados sem revelar nada; devolve quantas linhas saíram. Remover
     nunca exige variante ativa (C-214). 1..500 ids; fora disso 22023
     INVALID_ENTRY_IDS.

  3. get_my_wishlist_state_by_variant(p_card_variant_ids uuid[])
     → table(card_variant_id uuid, entry_id uuid, language_code text)
     Estado em lote para grades que conhecem a variante (Acervo, Fichário
     por variante presente/planejada, Master Set com variante única). Uma
     linha por desejo existente; variante sem desejo não aparece. 1..500.

  4. get_my_wishlist_state_by_card(p_card_ids uuid[])
     → table(card_id uuid, card_variant_id uuid, entry_id uuid, language_code text)
     Estado em lote para grades que conhecem só a carta (Pesquisa, Set,
     Pokédex com carta). Uma linha por desejo existente de qualquer
     variante da carta. 1..500. Nunca "promove" a carta a variante: só
     informa o que já está na lista (C-212).

  5. get_my_wishlist(p_limit integer, p_offset integer)
     → página "Lista de desejos", mais recentes primeiro (wished_at desc,
       entry_id). Inclui desejos de variante/carta desativada, sinalizados
       (variant_available = false) — nunca some (C-214/LDM-205). Posse
       derivada (C-213), quatro níveis:
         SAME_VARIANT_LANGUAGE        tem esta variante neste idioma
                                      ("qualquer" conta qualquer exemplar)
         SAME_VARIANT_OTHER_LANGUAGE  tem a variante em outro idioma
         OTHER_VARIANT                tem outra variante da carta
         NONE                         não tem
     Imagens: mesma regra da 5336 (CARD_FRONT primária ativa, pt-BR/en).
     p_limit 1..100, p_offset 0..100000; fora disso 22023 INVALID_PAGE.

Desempenho
  1: card_variant/card por PK, language por código, insert na unique.
  2: PK. 3: prefixo (user_id, card_variant_id) da unique. 4: linhas do
  usuário (prefixo user_id) × card_variant por PK. 5: ix_card_wishlist_
  entry_user_recent para a página; posse por ix_physical_card_inventory_
  variant, só para as linhas da página; card_asset só das cartas da página.

Como validar: Query 5873 (mesma pasta).
Como reverter: DROP FUNCTION das cinco funções (nada no banco depende delas).
================================================================
*/

begin;

-- 1. Incluir --------------------------------------------------------------
create or replace function public.add_my_wishlist_entry(
  p_card_variant_id uuid,
  p_language_code   text default null
)
returns table (entry_id uuid, created boolean, language_code text)
language plpgsql
security definer
volatile
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user        uuid := auth.uid();
  v_available   boolean;
  v_lang_code   text := nullif(btrim(p_language_code), '');
  v_language_id uuid;
  v_id          uuid;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if p_card_variant_id is null then
    raise exception 'INVALID_CARD_VARIANT_ID' using errcode = '22023';
  end if;

  if v_lang_code is not null then
    select l.id into v_language_id
    from public.language l
    where l.code = v_lang_code and l.is_active;

    if v_language_id is null then
      raise exception 'INVALID_LANGUAGE' using errcode = '22023';
    end if;
  end if;

  select (cv.is_active and c.is_active) into v_available
  from public.card_variant cv
  join public.card c on c.id = cv.card_id
  where cv.id = p_card_variant_id;

  if v_available is null or not v_available then
    raise exception 'CARD_VARIANT_UNAVAILABLE' using errcode = 'P0002';
  end if;

  insert into public.card_wishlist_entry (user_id, card_variant_id, language_id)
  values (v_user, p_card_variant_id, v_language_id)
  on conflict on constraint uq_card_wishlist_entry_user_variant_language do nothing
  returning id into v_id;

  if v_id is not null then
    return query select v_id, true, v_lang_code;
    return;
  end if;

  select w.id into v_id
  from public.card_wishlist_entry w
  where w.user_id = v_user
    and w.card_variant_id = p_card_variant_id
    and w.language_id is not distinct from v_language_id;

  return query select v_id, false, v_lang_code;
end;
$$;

comment on function public.add_my_wishlist_entry(uuid, text) is
  'V1-11 W1 (Query 5346): inclui uma Card Variant ativa na Lista de desejos do usuário da sessão, com idioma opcional (NULL = qualquer). Idempotente: repetir devolve a mesma entrada com created = false.';

-- 2. Remover ----------------------------------------------------------------
create or replace function public.remove_my_wishlist_entries(p_entry_ids uuid[])
returns integer
language plpgsql
security definer
volatile
set search_path = ''
as $$
declare
  v_user    uuid := auth.uid();
  v_removed integer;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if p_entry_ids is null or cardinality(p_entry_ids) = 0 or cardinality(p_entry_ids) > 500 then
    raise exception 'INVALID_ENTRY_IDS' using errcode = '22023';
  end if;

  delete from public.card_wishlist_entry w
  where w.user_id = v_user
    and w.id = any(p_entry_ids);

  get diagnostics v_removed = row_count;
  return v_removed;
end;
$$;

comment on function public.remove_my_wishlist_entries(uuid[]) is
  'V1-11 W1 (Query 5346): remove desejos do usuário da sessão por id (1..500). Idempotente; ids alheios ou inexistentes são ignorados sem revelar nada. Devolve quantos saíram.';

-- 3. Estado em lote por variante --------------------------------------------
create or replace function public.get_my_wishlist_state_by_variant(p_card_variant_ids uuid[])
returns table (card_variant_id uuid, entry_id uuid, language_code text)
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

  if p_card_variant_ids is null or cardinality(p_card_variant_ids) = 0 or cardinality(p_card_variant_ids) > 500 then
    raise exception 'INVALID_CARD_VARIANT_IDS' using errcode = '22023';
  end if;

  return query
  select w.card_variant_id, w.id, l.code::text
  from public.card_wishlist_entry w
  left join public.language l on l.id = w.language_id
  where w.user_id = v_user
    and w.card_variant_id = any(p_card_variant_ids);
end;
$$;

comment on function public.get_my_wishlist_state_by_variant(uuid[]) is
  'V1-11 W1 (Query 5346): desejos do usuário da sessão entre as variantes pedidas (até 500) — uma linha por desejo; marcação de grade em uma leitura.';

-- 4. Estado em lote por carta -------------------------------------------------
create or replace function public.get_my_wishlist_state_by_card(p_card_ids uuid[])
returns table (card_id uuid, card_variant_id uuid, entry_id uuid, language_code text)
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
  select cv.card_id, w.card_variant_id, w.id, l.code::text
  from public.card_wishlist_entry w
  join public.card_variant cv on cv.id = w.card_variant_id
  left join public.language l on l.id = w.language_id
  where w.user_id = v_user
    and cv.card_id = any(p_card_ids);
end;
$$;

comment on function public.get_my_wishlist_state_by_card(uuid[]) is
  'V1-11 W1 (Query 5346): desejos do usuário da sessão em qualquer variante das cartas pedidas (até 500). Nunca escolhe variante: só informa o que já está na lista.';

-- 5. Página "Lista de desejos" -----------------------------------------------
create or replace function public.get_my_wishlist(
  p_limit  integer default 60,
  p_offset integer default 0
)
returns table (
  entry_id          uuid,
  card_variant_id   uuid,
  card_id           uuid,
  card_name         text,
  collector_number  text,
  collector_total   integer,
  card_set_code     text,
  card_set_name     text,
  variant_label     text,
  variant_available boolean,
  language_code     text,
  ownership         text,
  image_path_pt     text,
  image_path_en     text,
  wished_at         timestamptz,
  total_count       bigint
)
language plpgsql
security definer
stable
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user      uuid := auth.uid();
  v_inventory uuid;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if p_limit is null or p_limit not between 1 and 100
     or p_offset is null or p_offset not between 0 and 100000 then
    raise exception 'INVALID_PAGE' using errcode = '22023';
  end if;

  select i.id into v_inventory
  from public.inventory i
  where i.owner_user_id = v_user;

  return query
  with page as (
    select w.id, w.card_variant_id, w.language_id, w.created_at,
           count(*) over () as total_count
    from public.card_wishlist_entry w
    where w.user_id = v_user
    order by w.created_at desc, w.id
    limit p_limit offset p_offset
  ),
  enriched as (
    select p.*, cv.card_id, (cv.is_active and c.is_active) as available
    from page p
    join public.card_variant cv on cv.id = p.card_variant_id
    join public.card c on c.id = cv.card_id
  ),
  front_asset as (
    select ca.card_id,
           max(ca.storage_path) filter (where l.code = 'pt-BR') as image_path_pt,
           max(ca.storage_path) filter (where l.code = 'en')    as image_path_en
    from public.card_asset ca
    join public.card_asset_type cat on cat.id = ca.asset_type_id
    join public.language l on l.id = ca.language_id
    where cat.code = 'CARD_FRONT' and ca.is_primary and ca.is_active
      and ca.card_id in (select e.card_id from enriched e)
    group by ca.card_id
  )
  select e.id,
         e.card_variant_id,
         e.card_id,
         c.name::text,
         c.collector_number::text,
         c.collector_total,
         cs.code::text,
         cs.name::text,
         nullif(concat_ws(' · ', vt.name, pp.name, ec.name), '')::text,
         e.available,
         wl.code::text,
         case
           when v_inventory is null then 'NONE'
           when exists (
             select 1 from public.physical_card pc
             where pc.inventory_id = v_inventory
               and pc.card_variant_id = e.card_variant_id
               and (e.language_id is null or pc.language_id = e.language_id)
           ) then 'SAME_VARIANT_LANGUAGE'
           when exists (
             select 1 from public.physical_card pc
             where pc.inventory_id = v_inventory
               and pc.card_variant_id = e.card_variant_id
           ) then 'SAME_VARIANT_OTHER_LANGUAGE'
           when exists (
             select 1
             from public.card_variant ocv
             join public.physical_card pc
               on pc.inventory_id = v_inventory
              and pc.card_variant_id = ocv.id
             where ocv.card_id = e.card_id
               and ocv.id <> e.card_variant_id
           ) then 'OTHER_VARIANT'
           else 'NONE'
         end,
         fa.image_path_pt::text,
         fa.image_path_en::text,
         e.created_at,
         e.total_count
  from enriched e
  join public.card c      on c.id = e.card_id
  join public.card_set cs on cs.id = c.card_set_id
  join public.card_variant cv on cv.id = e.card_variant_id
  left join public.card_variant_type vt            on vt.id = cv.variant_type_id
  left join public.card_printing_profile pp        on pp.id = cv.printing_profile_id
  left join public.card_edition_context_profile ec on ec.id = cv.edition_context_profile_id
  left join public.language wl                     on wl.id = e.language_id
  left join front_asset fa                         on fa.card_id = e.card_id
  order by e.created_at desc, e.id;
end;
$$;

comment on function public.get_my_wishlist(integer, integer) is
  'V1-11 W1 (Query 5346): página da Lista de desejos do usuário da sessão, mais recentes primeiro (limite 1..100). Inclui variantes desativadas sinalizadas (C-214); posse derivada em quatro níveis (C-213), nunca gravada.';

-- Grants --------------------------------------------------------------------
revoke all on function public.add_my_wishlist_entry(uuid, text) from public;
revoke all on function public.add_my_wishlist_entry(uuid, text) from anon;
grant execute on function public.add_my_wishlist_entry(uuid, text) to authenticated;

revoke all on function public.remove_my_wishlist_entries(uuid[]) from public;
revoke all on function public.remove_my_wishlist_entries(uuid[]) from anon;
grant execute on function public.remove_my_wishlist_entries(uuid[]) to authenticated;

revoke all on function public.get_my_wishlist_state_by_variant(uuid[]) from public;
revoke all on function public.get_my_wishlist_state_by_variant(uuid[]) from anon;
grant execute on function public.get_my_wishlist_state_by_variant(uuid[]) to authenticated;

revoke all on function public.get_my_wishlist_state_by_card(uuid[]) from public;
revoke all on function public.get_my_wishlist_state_by_card(uuid[]) from anon;
grant execute on function public.get_my_wishlist_state_by_card(uuid[]) to authenticated;

revoke all on function public.get_my_wishlist(integer, integer) from public;
revoke all on function public.get_my_wishlist(integer, integer) from anon;
grant execute on function public.get_my_wishlist(integer, integer) to authenticated;

commit;
