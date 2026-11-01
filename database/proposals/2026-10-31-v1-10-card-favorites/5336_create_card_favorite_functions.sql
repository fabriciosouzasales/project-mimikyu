/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5336 - Funções de Favorite de Card (V1-10): definir, ler em
              lote (por carta e por variante) e listar paginado
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE (V1-10 CONTROLLED LIVE EXECUTION-04, 2026-10-31;
              ledger 20261031213231 `5336_create_card_favorite_functions`; md5(prosrc) LIVE = corpos
              deste arquivo; enviada sem `begin;`/`commit;` — só este bloco Status difere)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-31

Padrão (o mesmo da Query 6137, Espécie favorita da Pokédex)
  SECURITY DEFINER, search_path '', objetos qualificados; identidade só
  de auth.uid() (o cliente nunca envia user_id); EXECUTE só authenticated
  (REVOKE de PUBLIC e anon). Sem identidade → 28000.

Funções
  1. set_card_favorite(p_card_id uuid, p_favorite boolean) → boolean
     DEFINE (não alterna) o estado; idempotente; devolve o estado final.
     Única via de escrita de card_favorite.
     Erros: 22023 INVALID_FAVORITE_STATE / INVALID_CARD_ID;
            P0002 CARD_NOT_FOUND (carta inexistente; ou inativa ao
            favoritar — desfavoritar uma carta inativa continua permitido).

  2. get_my_card_favorite_ids(p_card_ids uuid[]) → table(card_id)
     Quais das cartas pedidas são favoritas do usuário da sessão (para
     marcar uma grade: Pesquisa). 1..500 ids; fora disso 22023
     INVALID_CARD_IDS.

  3. get_my_card_favorites_by_variant(p_card_variant_ids uuid[])
     → table(card_variant_id, card_id, is_favorite)
     Para grades que só conhecem a variante (Acervo: 5220 não devolve
     card_id e card_variant não é legível pelo usuário — RLS admin). Uma
     linha por variante existente pedida, com a carta e o estado. 1..500
     ids; fora disso 22023 INVALID_CARD_VARIANT_IDS. Não lê nada do
     acervo: só catálogo (identidade pública) + favoritos do próprio
     usuário.

  4. get_my_favorite_cards(p_limit integer, p_offset integer)
     → table(card_id, card_name, collector_number, collector_total,
             card_set_code, card_set_name, image_path_pt, image_path_en,
             favorited_at, total_count)
     Página "Cartas favoritas": mais recentes primeiro (favorited_at desc,
     card_id). Só cartas ativas (uma carta desativada some da lista, mas o
     favorito permanece — C-90). Imagens: mesma regra da search_cards
     (CARD_FRONT primária e ativa, pt-BR e en). p_limit 1..100,
     p_offset 0..100000; fora disso 22023 INVALID_PAGE.

Desempenho
  1/2: PK (user_id, card_id). 3: card_variant por PK + PK do favorito.
  4: ix_card_favorite_user_recent (página), card/card_set por PK,
  card_asset só das cartas da página.

Como validar: Query 5868 (mesma pasta).
Como reverter: DROP FUNCTION das quatro funções (nada depende delas).
================================================================
*/

begin;

-- 1. Definir ------------------------------------------------------------
create or replace function public.set_card_favorite(
  p_card_id  uuid,
  p_favorite boolean
)
returns boolean
language plpgsql
security definer
volatile
set search_path = ''
as $$
declare
  v_user      uuid := auth.uid();
  v_is_active boolean;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if p_favorite is null then
    raise exception 'INVALID_FAVORITE_STATE' using errcode = '22023';
  end if;

  if p_card_id is null then
    raise exception 'INVALID_CARD_ID' using errcode = '22023';
  end if;

  select c.is_active into v_is_active
  from public.card c
  where c.id = p_card_id;

  if v_is_active is null or (p_favorite and not v_is_active) then
    raise exception 'CARD_NOT_FOUND' using errcode = 'P0002';
  end if;

  if p_favorite then
    insert into public.card_favorite (user_id, card_id)
    values (v_user, p_card_id)
    on conflict on constraint pk_card_favorite do nothing;
  else
    delete from public.card_favorite f
    where f.user_id = v_user
      and f.card_id = p_card_id;
  end if;

  return p_favorite;
end;
$$;

comment on function public.set_card_favorite(uuid, boolean) is
  'V1-10 (Query 5336): define (não alterna) se uma Card é favorita do usuário da sessão; idempotente; devolve o estado final. Única via de escrita de card_favorite.';

-- 2. Lote por carta ------------------------------------------------------
create or replace function public.get_my_card_favorite_ids(p_card_ids uuid[])
returns table (card_id uuid)
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
  select f.card_id
  from public.card_favorite f
  where f.user_id = v_user
    and f.card_id = any(p_card_ids);
end;
$$;

comment on function public.get_my_card_favorite_ids(uuid[]) is
  'V1-10 (Query 5336): quais das cartas pedidas (até 500) são favoritas do usuário da sessão — marcação de grade em uma leitura.';

-- 3. Lote por variante ----------------------------------------------------
create or replace function public.get_my_card_favorites_by_variant(p_card_variant_ids uuid[])
returns table (card_variant_id uuid, card_id uuid, is_favorite boolean)
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
  select cv.id,
         cv.card_id,
         exists (
           select 1 from public.card_favorite f
           where f.user_id = v_user and f.card_id = cv.card_id
         )
  from public.card_variant cv
  where cv.id = any(p_card_variant_ids);
end;
$$;

comment on function public.get_my_card_favorites_by_variant(uuid[]) is
  'V1-10 (Query 5336): carta e estado favorito de cada variante pedida (até 500) — para grades que só conhecem a variante (Acervo). Não lê o acervo.';

-- 4. Página "Cartas favoritas" -------------------------------------------
create or replace function public.get_my_favorite_cards(
  p_limit  integer default 60,
  p_offset integer default 0
)
returns table (
  card_id          uuid,
  card_name        text,
  collector_number text,
  collector_total  integer,
  card_set_code    text,
  card_set_name    text,
  image_path_pt    text,
  image_path_en    text,
  favorited_at     timestamptz,
  total_count      bigint
)
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

  if p_limit is null or p_limit not between 1 and 100
     or p_offset is null or p_offset not between 0 and 100000 then
    raise exception 'INVALID_PAGE' using errcode = '22023';
  end if;

  return query
  with page as (
    select f.card_id, f.created_at, count(*) over () as total_count
    from public.card_favorite f
    join public.card c on c.id = f.card_id and c.is_active
    where f.user_id = v_user
    order by f.created_at desc, f.card_id
    limit p_limit offset p_offset
  ),
  front_asset as (
    select ca.card_id,
           max(ca.storage_path) filter (where l.code = 'pt-BR') as image_path_pt,
           max(ca.storage_path) filter (where l.code = 'en')    as image_path_en
    from public.card_asset ca
    join public.card_asset_type cat on cat.id = ca.asset_type_id
    join public.language l on l.id = ca.language_id
    where cat.code = 'CARD_FRONT' and ca.is_primary and ca.is_active
      and ca.card_id in (select p.card_id from page p)
    group by ca.card_id
  )
  select p.card_id,
         c.name::text,
         c.collector_number::text,
         c.collector_total,
         cs.code::text,
         cs.name::text,
         fa.image_path_pt::text,
         fa.image_path_en::text,
         p.created_at,
         p.total_count
  from page p
  join public.card c      on c.id = p.card_id
  join public.card_set cs on cs.id = c.card_set_id
  left join front_asset fa on fa.card_id = p.card_id
  order by p.created_at desc, p.card_id;
end;
$$;

comment on function public.get_my_favorite_cards(integer, integer) is
  'V1-10 (Query 5336): página de Cartas favoritas do usuário da sessão, mais recentes primeiro (limite 1..100). Só cartas ativas; o favorito de uma carta desativada permanece (C-90).';

-- Grants ------------------------------------------------------------------
revoke all on function public.set_card_favorite(uuid, boolean) from public;
revoke all on function public.set_card_favorite(uuid, boolean) from anon;
grant execute on function public.set_card_favorite(uuid, boolean) to authenticated;

revoke all on function public.get_my_card_favorite_ids(uuid[]) from public;
revoke all on function public.get_my_card_favorite_ids(uuid[]) from anon;
grant execute on function public.get_my_card_favorite_ids(uuid[]) to authenticated;

revoke all on function public.get_my_card_favorites_by_variant(uuid[]) from public;
revoke all on function public.get_my_card_favorites_by_variant(uuid[]) from anon;
grant execute on function public.get_my_card_favorites_by_variant(uuid[]) to authenticated;

revoke all on function public.get_my_favorite_cards(integer, integer) from public;
revoke all on function public.get_my_favorite_cards(integer, integer) from anon;
grant execute on function public.get_my_favorite_cards(integer, integer) to authenticated;

commit;
