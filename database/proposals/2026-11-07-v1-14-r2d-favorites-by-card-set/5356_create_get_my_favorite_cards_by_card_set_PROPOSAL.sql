/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5356 - get_my_favorite_cards_by_card_set(): cartas favoritas do
              titular de UM Card Set canônico (V1-14 R2-D)
Versão......: 0.1
Status......: PROPOSTO — NÃO EXECUTADO (R2-D — CONTRACT APPROVAL & QUERY 5356 PROPOSAL-01)
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-07

Por que existe (lacuna comprovada)
  O relatório "Cartas favoritas do Card Set" (R2-D) precisa das favoritas cuja
  carta pertence ao Card Set de referência da coleção. get_my_favorite_cards
  (5336) devolve card_set_code/card_set_name, mas NÃO card_set_id nem filtro por
  Set; e card_set.code só é único DENTRO da expansão (uq_card_set_expansion_code
  (expansion_id, code), Query 120) — filtrar pelo código não é identidade
  canônica. Esta função filtra pelo vínculo canônico card.card_set_id no banco.
  A 5336 não muda.

Semântica (idêntica à 5336, só restrita a um Card Set)
  - Só favoritos do usuário da sessão (card_favorite.user_id = auth.uid()).
  - Só cartas ativas (card.is_active): carta desativada some da lista, o
    favorito permanece (C-90) — mesma regra da 5336.
  - Unidade = a carta (PK (user_id, card_id), 5335): uma linha por carta.
  - Imagens: mesma regra da 5336 (CARD_FRONT primária e ativa, pt-BR e en).
  - Independe de posse, Inventory, Collection ou Allocation.

Contrato
  get_my_favorite_cards_by_card_set(p_card_set_id uuid,
                                    p_limit  integer default 100,  -- 1..100
                                    p_offset integer default 0)    -- 0..100000
  RETURNS TABLE(card_id, card_name, collector_number, collector_total,
                card_set_id, card_set_code, card_set_name,
                image_path_pt, image_path_en, favorited_at, total_count)
  = as colunas da 5336 + card_set_id (conferência no relatório).
  Ordem: número do Set (card.collector_order — único por Set, Query 140), nome,
  id — determinística e estável entre páginas. total_count = favoritas do
  titular NESTE Card Set (antes da paginação).
  Card Set inexistente ou sem favoritas → 0 linhas (nunca erro). Só devolve
  favoritos do próprio titular, qualquer que seja o Card Set pedido; o R2-D só
  passa o Card Set da coleção já autorizada pela 5332.
  Erros: 28000 sem sessão; 22023 INVALID_CARD_SET (nulo) / INVALID_PAGE.

Segurança
  SECURITY DEFINER — justificativa: card, card_set e card_asset só são legíveis
  por administrador (catalog_admin_select, migrations 274/2134); em SECURITY
  INVOKER o colecionador não leria nome, número nem imagem (a 5336 é DEFINER pelo
  mesmo motivo). Restrições: search_path '', objetos qualificados, STABLE,
  identidade só de auth.uid() (o cliente nunca envia user_id), EXECUTE só
  authenticated (REVOKE de PUBLIC e anon). Nenhuma RLS ou policy alterada.

Desempenho
  Favoritos do usuário pelo prefixo da PK (user_id, card_id) → card pela PK com
  filtro card_set_id/is_active → ordenação só sobre as favoritas do titular no
  Set (dezenas a centenas). card_asset só das cartas da página. Sem índice novo.
================================================================
*/

create or replace function public.get_my_favorite_cards_by_card_set(
  p_card_set_id uuid,
  p_limit       integer default 100,
  p_offset      integer default 0
)
returns table (
  card_id          uuid,
  card_name        text,
  collector_number text,
  collector_total  integer,
  card_set_id      uuid,
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

  if p_card_set_id is null then
    raise exception 'INVALID_CARD_SET' using errcode = '22023';
  end if;

  if p_limit is null or p_limit not between 1 and 100
     or p_offset is null or p_offset not between 0 and 100000 then
    raise exception 'INVALID_PAGE' using errcode = '22023';
  end if;

  return query
  with page as (
    select f.card_id, f.created_at, c.collector_order, c.name as card_name_sort, count(*) over () as total_count
    from public.card_favorite f
    join public.card c on c.id = f.card_id and c.is_active and c.card_set_id = p_card_set_id
    where f.user_id = v_user
    order by c.collector_order, c.name, f.card_id
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
         cs.id,
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
  order by p.collector_order, p.card_name_sort, p.card_id;
end;
$$;

revoke all on function public.get_my_favorite_cards_by_card_set(uuid, integer, integer) from public;
revoke all on function public.get_my_favorite_cards_by_card_set(uuid, integer, integer) from anon;
grant execute on function public.get_my_favorite_cards_by_card_set(uuid, integer, integer) to authenticated;

comment on function public.get_my_favorite_cards_by_card_set(uuid, integer, integer) is
  'V1-14 R2-D (Query 5356): cartas favoritas do usuário da sessão de UM Card Set canônico (card.card_set_id), na ordem do Set (collector_order, nome, id), limite 1..100. Mesma semântica da 5336 (só cartas ativas; favorito de carta desativada permanece, C-90). Somente leitura.';
