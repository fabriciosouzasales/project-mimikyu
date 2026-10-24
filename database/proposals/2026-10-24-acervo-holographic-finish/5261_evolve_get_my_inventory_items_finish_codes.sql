/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5261 - get_my_inventory_items(): códigos estáveis de
              variante e raridade para o acabamento visual da galeria
              (MY-INVENTORY-HOLOGRAPHIC-FINISH-FOUNDATION-01; evolui a 5220)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA. Não aplicar sem autorização de Fabrício.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-24

Por que existe: a galeria do Meu acervo vai diferenciar visualmente
padrão / holográfica / reversa (protótipo aprovado em 1×). A etiqueta
variant_label é texto de exibição (pode mudar de idioma ou de redação);
a classificação precisa dos códigos estáveis do catálogo:
card_variant_type.code e rarity.code.

Contrato: MESMA assinatura de entrada da 5220 (text, text, text, uuid, boolean, text, integer, integer, uuid, boolean);
retorno = as 16 colunas da 5220, na mesma ordem e com os mesmos valores,
MAIS duas colunas ao final:
  variant_type_code text   -- card_variant_type.code (ex.: STANDARD, HOLO, REVERSE_HOLO)
  rarity_code       text   -- rarity.code da carta (ex.: RARE, ILLUSTRATION_RARE)

Por que DROP + CREATE: o PostgreSQL não permite mudar o RETURNS TABLE com
CREATE OR REPLACE (erro 42P13). Mesma transação: ninguém observa a
função ausente; EXECUTE é reconcedido na mesma transação.

Consumidores (inventário 2026-10-24, nenhum no banco — pg_depend = 0 e
nenhum prosrc chama a função): web/lib/colecoes/acervo-queries.ts,
web/lib/colecoes/colecoes-queries.ts (getAvailableGroupCount),
web/app/colecoes/colecoes/actions.ts (duas chamadas). Todos leem por NOME
de coluna (PostgREST → JSON); colunas novas ao final são ignoradas por
quem não as usa. As chamadas existentes com 8 argumentos nomeados seguem
válidas (defaults da 5220 preservados).

Ordem de publicação segura em qualquer sentido: banco antes → frontend
antigo ignora as colunas; frontend antes → códigos ausentes = sem efeito
(classificação conservadora), nunca erro.

Desempenho: as duas colunas saem da FASE 2 (≤ 96 linhas), por junções por
PK (card_variant_type.id já juntada; rarity.id). FASE 1 (paginação,
filtros, ordenação, contagens) inalterada, texto idêntico.

Segurança: idêntica à 5220 — SECURITY DEFINER, STABLE, search_path '',
auth.uid() obrigatório (28000), dono resolvido no servidor; EXECUTE só
authenticated (revogado de PUBLIC e anon).

Recuperação: reaplicar a 5220 canônica depois de
  drop function public.get_my_inventory_items(text, text, text, uuid, boolean, text, integer, integer, uuid, boolean);
Como validar: Query 5858 (mesma pasta), seções A–D.
================================================================
*/

begin;

-- Pré-checagem (falha alto, nada é alterado): a definição vigente é EXATAMENTE
-- a 5220 canônica (md5 do corpo e retorno), sem sobrecarga e sem dependentes.
do $pre$
declare
  v_oid oid := to_regprocedure('public.get_my_inventory_items(text, text, text, uuid, boolean, text, integer, integer, uuid, boolean)');
begin
  if v_oid is null then
    raise exception 'PRECHECK 5261: assinatura da 5220 ausente';
  end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'get_my_inventory_items') <> 1 then
    raise exception 'PRECHECK 5261: há mais de uma sobrecarga de get_my_inventory_items';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = v_oid) <> '93786a7b8fc9226eed53ba5463e01aa3' then
    raise exception 'PRECHECK 5261: corpo vigente difere da 5220 canônica';
  end if;
  if pg_get_function_result(v_oid) <> 'TABLE(card_variant_id uuid, language_code text, language_name text, card_name text, collector_number text, collector_total integer, card_set_code text, card_set_name text, is_default_variant boolean, variant_label text, copies_count integer, last_added_at timestamp with time zone, image_path text, total_count bigint, copies_owned integer, total_copies bigint)' then
    raise exception 'PRECHECK 5261: retorno vigente difere da 5220';
  end if;
  if exists (select 1 from pg_depend d
             where d.refclassid = 'pg_catalog.pg_proc'::regclass and d.refobjid = v_oid and d.deptype = 'n') then
    raise exception 'PRECHECK 5261: há objetos dependentes de get_my_inventory_items';
  end if;
  if to_regclass('public.rarity') is null or to_regclass('public.card_variant_type') is null then
    raise exception 'PRECHECK 5261: tabelas de catálogo ausentes';
  end if;
end;
$pre$;

drop function public.get_my_inventory_items(text, text, text, uuid, boolean, text, integer, integer, uuid, boolean);

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
  total_copies       bigint,
  variant_type_code  text,
  rarity_code        text
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
    v_total_copies,
    -- 5261: códigos estáveis para a classificação visual do acabamento (função
    -- pura no frontend). Mesmas junções da etiqueta; nenhuma leitura nova de tabela
    -- de exemplares. NULL quando o catálogo não tiver o tipo (não ocorre no LIVE).
    vt.code::text,
    r.code::text
  from unnest(v_variants, v_languages, v_counts, v_lasts)
       with ordinality as u(variant_id, language_id, n, last_added, ord)
  join public.card_variant cv on cv.id = u.variant_id
  join public.card c          on c.id = cv.card_id
  join public.card_set cs     on cs.id = c.card_set_id
  join public.language l      on l.id = u.language_id
  left join public.card_variant_type vt            on vt.id = cv.variant_type_id
  left join public.rarity r                        on r.id = c.rarity_id
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
  'Meu acervo (Query 5159, evoluída pela 5220 e pela 5261): grupos Card Variant + idioma do acervo do usuário da sessão, paginados (≤ 96), com filtros, ordenação RECENT|SET_NUMBER, filtro por localização física, contagens copies_count/copies_owned/total_copies, imagem CARD_FRONT e códigos estáveis variant_type_code/rarity_code (acabamento visual). Exige auth.uid(); dono resolvido no servidor.';

revoke all on function public.get_my_inventory_items(text, text, text, uuid, boolean, text, integer, integer, uuid, boolean) from public;
revoke all on function public.get_my_inventory_items(text, text, text, uuid, boolean, text, integer, integer, uuid, boolean) from anon;
grant execute on function public.get_my_inventory_items(text, text, text, uuid, boolean, text, integer, integer, uuid, boolean) to authenticated;

-- PostgREST relê o schema (retorno novo) ao confirmar a transação.
notify pgrst, 'reload schema';

commit;
