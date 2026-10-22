/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5220 - get_my_inventory_items(): filtro por localização
              física e contagens por exemplar — WHERE-04 (evolui a 5159)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA. Preparada em WHERE-04 CONTRACT GAP
              RESOLUTION (2026-10-21). Execução só com autorização expressa
              de Fabrício, depois de auditoria independente.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-21

Por que existe: a galeria do Meu acervo (5159) não filtra por local, não
informa quantos exemplares a carta tem no total quando um filtro separa
exemplares do mesmo grupo e não soma os exemplares correspondentes de todas
as páginas. Filtrar no navegador exigiria baixar o acervo inteiro (WHERE-04
READINESS: CONTRACT GAP). Esta Query EVOLUI a própria 5159 — mesma função,
mesmo nome, mesmas regras — em vez de criar uma função paralela.

Contrato (assinatura nova; a anterior deixa de existir):
  get_my_inventory_items(
    p_search               text    default null,
    p_card_set_code        text    default null,
    p_language_code        text    default null,
    p_collection_id        uuid    default null,
    p_without_collection   boolean default false,
    p_sort                 text    default 'RECENT',
    p_limit                integer default 48,
    p_offset               integer default 0,
    p_storage_container_id uuid    default null,   -- NOVO: só exemplares neste local
    p_without_storage      boolean default false    -- NOVO: só exemplares sem local
  )
  RETURNS TABLE(... as 14 colunas da 5159, na mesma ordem ...,
                copies_owned integer,               -- NOVO
                total_copies bigint)                -- NOVO

  Os dois parâmetros novos ausentes/desligados → resultado idêntico ao da
  5159 (mesmas linhas, mesma ordem, mesmos valores nas 14 colunas).
  p_storage_container_id e p_without_storage juntos → 22023
  INVALID_STORAGE_FILTER. Local inexistente ou de outro usuário → vazio
  (mesma resposta de um local próprio vazio — não enumera).

Semântica dos contadores (item = grupo Card Variant + idioma, como na 5159):
  copies_count  exemplares do item que atendem a TODOS os filtros por
                exemplar (idioma, coleção, sem coleção, local, sem local).
                Igual à 5159 quando os filtros novos estão desligados.
  copies_owned  todos os exemplares do item no acervo, ignorando QUALQUER
                filtro (coleção e localização inclusive). Busca, Set e idioma
                não mudam este número, porque definem o item, não o exemplar.
                Sem filtro por exemplar, copies_owned = copies_count.
  total_count   itens distintos que atendem aos filtros (paginação) —
                semântica da 5159 inalterada.
  total_copies  soma de copies_count de TODOS os itens que atendem aos
                filtros (todas as páginas), não só da página.
  Invariantes: 1 ≤ copies_count ≤ copies_owned por linha; total_copies ≥
  total_count; sem filtro algum, total_copies = exemplares do acervo.

Desempenho: caminho rápido e caminho completo da 5159 preservados; o
filtro de local é um predicado a mais sobre physical_card antes do
agrupamento (ix_physical_card_storage_container / inventory). total_copies
é uma soma de janela na mesma passada que já conta total_count.
copies_owned: no máximo 96 contagens por índice
(ix_physical_card_inventory_variant), e só quando há filtro por exemplar.
Nenhum índice novo. Meta B4 (p95 ≤ 150 ms) a medir pela 5848 Seção P.

Segurança: igual à 5159 — SECURITY DEFINER, STABLE, search_path '',
auth.uid() obrigatório (28000), dono resolvido no servidor, EXECUTE só
authenticated (revogado de PUBLIC e anon na nova assinatura).

Recuperação: reaplicar a 5159 canônica depois de
  drop function public.get_my_inventory_items(text, text, text, uuid, boolean, text, integer, integer, uuid, boolean);
(ver README desta proposta, "Rollback").
Como validar: Query 5848 (mesma pasta).
================================================================
*/

begin;

-- Pré-checagem (falha alto, nada é alterado): exatamente a assinatura
-- canônica da 5159 existe, sem outra sobrecarga, e nenhuma view/regra
-- depende dela (pg_depend). Funções que a chamam não são rastreadas pelo
-- pg_depend — o inventário de chamadores está no README (nenhuma no banco).
do $pre$
declare
  v_oid oid := to_regprocedure('public.get_my_inventory_items(text, text, text, uuid, boolean, text, integer, integer)');
begin
  if v_oid is null then
    raise exception 'PRECHECK 5220: assinatura canônica da 5159 ausente';
  end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'get_my_inventory_items') <> 1 then
    raise exception 'PRECHECK 5220: há mais de uma sobrecarga de get_my_inventory_items';
  end if;
  if exists (select 1 from pg_depend d
             where d.refclassid = 'pg_catalog.pg_proc'::regclass and d.refobjid = v_oid and d.deptype = 'n') then
    raise exception 'PRECHECK 5220: há objetos dependentes de get_my_inventory_items';
  end if;
  if to_regclass('public.ix_physical_card_storage_container') is null
     or to_regclass('public.ix_physical_card_inventory_variant') is null then
    raise exception 'PRECHECK 5220: índices de physical_card ausentes (5010/5023)';
  end if;
end;
$pre$;

-- Troca de assinatura e de retorno exige DROP (CREATE OR REPLACE criaria uma
-- sobrecarga). Mesma transação: ninguém observa a função ausente.
drop function public.get_my_inventory_items(text, text, text, uuid, boolean, text, integer, integer);

create function public.get_my_inventory_items(
  p_search             text    default null,
  p_card_set_code      text    default null,
  p_language_code      text    default null,
  p_collection_id      uuid    default null,
  p_without_collection boolean default false,
  p_sort               text    default 'RECENT',
  p_limit                integer default 48,
  p_offset               integer default 0,
  p_storage_container_id uuid    default null,
  p_without_storage      boolean default false
)
returns table (
  card_variant_id    uuid,
  language_code      text,
  language_name      text,
  card_name          text,
  collector_number   text,
  collector_total    integer,
  card_set_code      text,
  card_set_name      text,
  is_default_variant boolean,
  variant_label      text,
  copies_count       integer,
  last_added_at      timestamptz,
  image_path         text,
  total_count        bigint,
  copies_owned       integer,
  total_copies       bigint
)
language plpgsql
security definer
stable
set search_path = ''
as $$
declare
  v_user        uuid := auth.uid();
  v_inventory   uuid;
  v_sort        text := upper(coalesce(nullif(btrim(p_sort), ''), 'RECENT'));
  v_q           text := nullif(btrim(coalesce(p_search, '')), '');
  v_q_like      text;
  v_q_num       text;
  v_q_tot       text;
  v_slash       integer;
  v_without     boolean := coalesce(p_without_collection, false);
  v_variants    uuid[];
  v_languages   uuid[];
  v_counts      integer[];
  v_lasts       timestamptz[];
  v_total       bigint;
  v_total_copies bigint;
  v_without_storage boolean := coalesce(p_without_storage, false);
  -- Algum filtro POR EXEMPLAR que pode separar exemplares do mesmo grupo
  -- (idioma não entra: o idioma é parte da chave do grupo).
  v_filtered    boolean := p_collection_id is not null or coalesce(p_without_collection, false)
                           or p_storage_container_id is not null or coalesce(p_without_storage, false);
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if v_sort not in ('RECENT', 'SET_NUMBER') then
    raise exception 'INVALID_SORT' using errcode = '22023';
  end if;

  if p_limit is null or p_limit not between 1 and 96
     or p_offset is null or p_offset not between 0 and 100000 then
    raise exception 'INVALID_PAGE' using errcode = '22023';
  end if;

  if v_q is not null and length(v_q) > 100 then
    raise exception 'INVALID_SEARCH' using errcode = '22023';
  end if;

  if p_collection_id is not null and v_without then
    raise exception 'INVALID_COLLECTION_FILTER' using errcode = '22023';
  end if;

  if p_storage_container_id is not null and v_without_storage then
    raise exception 'INVALID_STORAGE_FILTER' using errcode = '22023';
  end if;

  select i.id into v_inventory
  from public.inventory i
  where i.owner_user_id = v_user;

  if v_inventory is null then
    return;  -- usuário sem Inventory: acervo vazio, sem erro
  end if;

  if v_q is not null then
    v_q_like := replace(replace(replace(lower(v_q), '\', '\\'), '%', '\%'), '_', '\_');
    v_slash  := strpos(v_q, '/');
    if v_slash > 1 then
      v_q_num := btrim(substr(v_q, 1, v_slash - 1));
      v_q_tot := btrim(substr(v_q, v_slash + 1));
      if v_q_tot = '' or translate(v_q_tot, '0123456789', '') <> '' then
        v_q_tot := null;
      else
        v_q_tot := coalesce(nullif(ltrim(v_q_tot, '0'), ''), '0');
      end if;
    else
      v_q_num := v_q;
    end if;
    v_q_num := coalesce(nullif(ltrim(lower(v_q_num), '0'), ''), '0');
  end if;

  -- FASE 1 — chaves da página (grupo = Card Variant + idioma), em arrays.
  -- Caminho rápido (visão padrão: RECENT, sem busca e sem Set): pagina
  -- direto sobre o agrupamento dos exemplares; catálogo só para ≤ 96
  -- linhas. Caminho completo (busca, Set ou SET_NUMBER): junta o catálogo
  -- de todos os grupos do usuário, porque o filtro/ordem dependem dele.
  if v_q is null and p_card_set_code is null and v_sort = 'RECENT' then
    with copies as (
      select pc.card_variant_id, pc.language_id, pc.created_at
      from public.physical_card pc
      where pc.inventory_id = v_inventory
        and (p_language_code is null or pc.language_id = (
              select l.id from public.language l where l.code = p_language_code))
        and (p_collection_id is null or exists (
              select 1
              from public.collection_allocation ca
              join public.collection co
                on co.id = ca.collection_id
               and co.owner_user_id = v_user
              where ca.physical_card_id = pc.id
                and ca.collection_id = p_collection_id))
        and (not v_without or not exists (
              select 1 from public.collection_allocation ca
              where ca.physical_card_id = pc.id))
        -- WHERE-04 (5220): localização física do EXEMPLAR (C-58). Local de
        -- outro acervo nunca casa (FK composta de 5023: o local de um
        -- exemplar é sempre do mesmo Inventory) → vazio, sem enumerar.
        and (p_storage_container_id is null or pc.storage_container_id = p_storage_container_id)
        and (not v_without_storage or pc.storage_container_id is null)
    ),
    grouped as (
      select g.card_variant_id, g.language_id,
             count(*)::integer as n, max(g.created_at) as last_added
      from copies g
      group by g.card_variant_id, g.language_id
    ),
    page as (
      select gr.*, count(*) over () as total, sum(gr.n) over () as copies_sum
      from grouped gr
      order by gr.last_added desc, gr.card_variant_id, gr.language_id
      limit p_limit offset p_offset
    )
    select array_agg(pg.card_variant_id order by pg.last_added desc, pg.card_variant_id, pg.language_id),
           array_agg(pg.language_id     order by pg.last_added desc, pg.card_variant_id, pg.language_id),
           array_agg(pg.n               order by pg.last_added desc, pg.card_variant_id, pg.language_id),
           array_agg(pg.last_added      order by pg.last_added desc, pg.card_variant_id, pg.language_id),
           max(pg.total),
           max(pg.copies_sum)
      into v_variants, v_languages, v_counts, v_lasts, v_total, v_total_copies
    from page pg;
  else
    with copies as (
      select pc.card_variant_id, pc.language_id, pc.created_at
      from public.physical_card pc
      where pc.inventory_id = v_inventory
        and (p_language_code is null or pc.language_id = (
              select l.id from public.language l where l.code = p_language_code))
        and (p_collection_id is null or exists (
              select 1
              from public.collection_allocation ca
              join public.collection co
                on co.id = ca.collection_id
               and co.owner_user_id = v_user
              where ca.physical_card_id = pc.id
                and ca.collection_id = p_collection_id))
        and (not v_without or not exists (
              select 1 from public.collection_allocation ca
              where ca.physical_card_id = pc.id))
        -- WHERE-04 (5220): localização física do EXEMPLAR (C-58). Local de
        -- outro acervo nunca casa (FK composta de 5023: o local de um
        -- exemplar é sempre do mesmo Inventory) → vazio, sem enumerar.
        and (p_storage_container_id is null or pc.storage_container_id = p_storage_container_id)
        and (not v_without_storage or pc.storage_container_id is null)
    ),
    grouped as (
      select g.card_variant_id, g.language_id,
             count(*)::integer as n, max(g.created_at) as last_added
      from copies g
      group by g.card_variant_id, g.language_id
    ),
    joined as (
      select gr.card_variant_id, gr.language_id, gr.n, gr.last_added,
             cv.variant_order, c.collector_order,
             cs.code as set_code, cs.release_date, cs.release_order,
             l.language_order
      from grouped gr
      join public.card_variant cv on cv.id = gr.card_variant_id
      join public.card c          on c.id = cv.card_id
      join public.card_set cs     on cs.id = c.card_set_id
      join public.language l      on l.id = gr.language_id
      where (p_card_set_code is null or cs.code = p_card_set_code)
        and (v_q is null
             or lower(c.name) like '%' || v_q_like || '%' escape '\'
             or (coalesce(nullif(ltrim(lower(c.collector_number), '0'), ''), '0') = v_q_num
                 and (v_q_tot is null
                      or coalesce(nullif(ltrim(c.collector_total::text, '0'), ''), '0') = v_q_tot)))
    ),
    page as (
      select j.card_variant_id, j.language_id, j.n, j.last_added,
             count(*) over () as total,
             sum(j.n) over () as copies_sum,
             row_number() over (order by
               case when v_sort = 'RECENT' then j.last_added end desc nulls last,
               case when v_sort = 'SET_NUMBER' then j.release_date end desc nulls last,
               case when v_sort = 'SET_NUMBER' then j.release_order end desc nulls last,
               case when v_sort = 'SET_NUMBER' then j.set_code end asc,
               j.collector_order asc,
               j.variant_order asc,
               j.language_order asc,
               j.card_variant_id asc,
               j.language_id asc) as ord
      from joined j
    )
    select array_agg(pg.card_variant_id order by pg.ord),
           array_agg(pg.language_id     order by pg.ord),
           array_agg(pg.n               order by pg.ord),
           array_agg(pg.last_added      order by pg.ord),
           max(pg.total),
           max(pg.copies_sum)
      into v_variants, v_languages, v_counts, v_lasts, v_total, v_total_copies
    from page pg
    where pg.ord > p_offset and pg.ord <= p_offset + p_limit;
  end if;

  if v_variants is null then
    return;  -- página vazia (sem exemplares, sem resultados ou além do fim)
  end if;

  -- FASE 2 — apresentação só das linhas da página, na ordem da fase 1.
  return query
  select
    u.variant_id,
    l.code,
    l.name,
    c.name::text,
    c.collector_number::text,
    c.collector_total,
    cs.code::text,
    cs.name::text,
    cv.is_default,
    nullif(concat_ws(' · ', vt.name, pp.name, ec.name), '')::text,
    u.n,
    u.last_added,
    img.storage_path,
    v_total,
    case when v_filtered then own.n else u.n end,
    v_total_copies
  from unnest(v_variants, v_languages, v_counts, v_lasts)
       with ordinality as u(variant_id, language_id, n, last_added, ord)
  join public.card_variant cv on cv.id = u.variant_id
  join public.card c          on c.id = cv.card_id
  join public.card_set cs     on cs.id = c.card_set_id
  join public.language l      on l.id = u.language_id
  left join public.card_variant_type vt            on vt.id = cv.variant_type_id
  left join public.card_printing_profile pp        on pp.id = cv.printing_profile_id
  left join public.card_edition_context_profile ec on ec.id = cv.edition_context_profile_id
  left join lateral (
    select ca.storage_path
    from public.card_asset ca
    join public.card_asset_type cat on cat.id = ca.asset_type_id and cat.code = 'CARD_FRONT'
    join public.language al on al.id = ca.language_id
    where ca.card_id = c.id
      and ca.is_primary
      and ca.is_active
      and ca.storage_path is not null
    order by (ca.language_id = u.language_id) desc,
             (al.code = 'pt-BR') desc,
             (al.code = 'en') desc,
             al.language_order asc
    limit 1
  ) img on true
  -- copies_owned: todos os exemplares do grupo no acervo, sem filtro algum.
  -- Só é lido quando há filtro por exemplar (senão é igual a copies_count);
  -- no máximo uma busca por linha da página (≤ 96), via
  -- ix_physical_card_inventory_variant.
  left join lateral (
    select count(*)::integer as n
    from public.physical_card pc
    where v_filtered
      and pc.inventory_id = v_inventory
      and pc.card_variant_id = u.variant_id
      and pc.language_id = u.language_id
  ) own on true
  order by u.ord;
end;
$$;

comment on function public.get_my_inventory_items(text, text, text, uuid, boolean, text, integer, integer, uuid, boolean) is
  'Meu acervo (Query 5159, evoluída pela 5220 — WHERE-04): grupos Card Variant + idioma do acervo do usuário da sessão, paginados (≤ 96), com filtros, ordenação RECENT|SET_NUMBER, filtro por localização física (local ou sem localização), contagens copies_count/copies_owned/total_copies e imagem CARD_FRONT. Exige auth.uid(); dono resolvido no servidor.';

revoke all on function public.get_my_inventory_items(text, text, text, uuid, boolean, text, integer, integer, uuid, boolean) from public;
revoke all on function public.get_my_inventory_items(text, text, text, uuid, boolean, text, integer, integer, uuid, boolean) from anon;
grant execute on function public.get_my_inventory_items(text, text, text, uuid, boolean, text, integer, integer, uuid, boolean) to authenticated;

-- PostgREST relê o schema (assinatura nova) ao confirmar a transação.
notify pgrst, 'reload schema';

commit;
