/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5357 - get_my_binder_value_groups(): grupos variante + idioma dos
              exemplares físicos POSICIONADOS nos bolsos de um fichário (Valor
              do Fichário — BINDER-VALUE, 05d v2.73, D1–D9)
Versão......: 0.2 (B2 STATIC AUDIT CORRECTION-01: só o cabeçalho mudou; o corpo
              da função é o mesmo da 0.1 — md5 do trecho "create or replace
              function" até o fim = a84c3df37e57c8b37746d0a6d1659319)
Status......: PROPOSTO — NÃO EXECUTADO (BINDER VALUE — B2 AGGREGATED READ SQL
              PROPOSAL & HARNESS DESIGN-01). Nenhum banco tocado. Execução,
              harness e aplicação dependem de auditoria e autorização próprias.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-08

Por que existe (lacuna comprovada — 05d v2.73, D7)
  O Valor do Fichário (D1) considera cada exemplar físico do titular posicionado
  em um bolso do fichário, qualquer que seja a coleção dele (inclusive nenhuma
  ou arquivada). Nenhuma leitura existente devolve esses grupos de forma barata:
  - get_my_collection_binder_pages (5252): bolso a bolso, no máximo 4 páginas
    por chamada, com imagens/conteúdo esperado/local — N/4 chamadas pesadas;
  - get_my_binder_occupancy (5245): só contagens;
  - get_my_inventory_items (5159/5261): filtra por COLEÇÃO (alocação) — perímetro
    errado depois da 5248 (bolso pode ter exemplar sem coleção ou de coleção
    não participante).

Modelo físico (verificado nas definições versionadas)
  collection_layout (5105; collection_id UNIQUE = proprietária; 5247:
    storage_container_id NOT NULL UNIQUE)
  → collection_layout_page (5108; UNIQUE (layout_id, page_number))
  → collection_layout_slot (5110; UNIQUE (page_id, row_index, column_index))
  → collection_layout_slot_assignment (5115 → 5248): slot_id UNIQUE (um exemplar
    por bolso), physical_card_id NOT NULL UNIQUE (um bolso por exemplar no
    sistema; ON DELETE CASCADE), collection_allocation_id legado/anulável.
    Gatilho 5248: exemplar do MESMO dono do fichário e guardado no local físico
    do fichário; a coleção do exemplar não importa.
  → physical_card (5010; card_variant_id, language_id, inventory_id; 5023
    storage_container_id) → inventory (5000; owner_user_id UNIQUE).
  Convidadas: collection_layout_guest (5229; PK collection_id; gatilho: mesmo
    dono da proprietária).
  Imagens (5232), mesclagens/regiões (5119/5239) e reservas (5113, conteúdo
  esperado) NÃO têm linha de ocupação — ficam fora naturalmente; idem exemplar
  guardado no fichário sem bolso. filled_count (5252) = count(a.id) sobre o
  MESMO percurso página → bolso → ocupação.

Contrato
  get_my_binder_value_groups(p_collection_id uuid,
                             p_limit  integer default 200,   -- 1..200
                             p_offset integer default 0)     -- 0..10000
  RETURNS TABLE: SUBCONJUNTO das colunas da 5261, com os mesmos nomes e tipos,
  suficiente para o leitor homologado `toItem` (R2-E) — card_variant_id,
  language_code, language_name, card_name, collector_number, collector_total,
  card_set_code, card_set_name, is_default_variant, variant_label, image_path,
  copies_count — mais os totais total_count (grupos) e total_copies
  (exemplares nos bolsos), iguais em toda página (calculados antes da
  paginação, no mesmo statement). Ficam de fora, por não terem uso no valor:
  last_added_at, copies_owned, variant_type_code e rarity_code (`toItem` lê
  rarity_code como opcional → null; a R2-E não usa rarityCode).
  Sem dados financeiros, sem ids de bolso/página/alocação/exemplar.
  Ordem total e determinística = SET_NUMBER da 5159: lançamento desc, ordem de
  lançamento desc, código do Set, collector_order, variant_order,
  language_order, card_variant_id, language_id.
  Coleção própria sem fichário → 0 linhas. Fichário sem cartas nos bolsos →
  0 linhas.
  Erros: 28000 sem sessão; 22023 INVALID_ARGUMENT (coleção nula) /
  INVALID_PAGE; P0002 COLLECTION_NOT_FOUND (inexistente, de outro titular ou
  compartilhada com você — mesma resposta, sem enumerar; padrão da 5252).

Segurança
  SECURITY DEFINER — mesma justificativa e padrão de 5252/5245/5356: catálogo
  (card, card_set, card_variant, card_asset) só legível por administrador
  (catalog_admin_select); as tabelas do fichário têm RLS cujo caminho de
  convidada não cobre esta agregação. Em SECURITY INVOKER o colecionador não
  leria o catálogo. Mitigações:
  - identidade só de auth.uid(); o cliente nunca envia user_id, layout, bolso
    ou exemplar;
  - fronteira de autorização ANTES de qualquer outra tabela: a coleção informada
    tem de ser do chamador;
  - o fichário é resolvido SÓ a partir dessa coleção (proprietária ou convidada)
    e o dono da coleção proprietária do fichário é reconferido (= chamador);
  - os exemplares só entram pelo inventário do chamador (defesa em profundidade,
    além do gatilho 5248);
  - search_path '' e objetos qualificados; STABLE; nenhuma escrita;
  - EXECUTE só authenticated (REVOKE de PUBLIC e anon — o default privilege do
    Supabase concede a anon). Como na 5252/5356, nada é feito para
    service_role: se o default privilege lhe conceder EXECUTE (inferência,
    registrada pelo S2 do harness), a chamada sem sub cai em 28000 — padrão
    vigente das leituras do colecionador, não alterado aqui.
  - Nenhuma referência a collection_allocation no corpo: o perímetro não
    depende de alocação (D1).

Desempenho (estimativa estática — EXPLAIN sem ANALYZE é gate separado)
  Mesmo percurso do filled_count (5252, já executado a cada abertura do
  fichário): página por UNIQUE (layout_id, page_number); bolso por UNIQUE
  (page_id, row_index, column_index); ocupação por UNIQUE (slot_id); exemplar
  pela PK; inventário pela PK. Custo ~ bolsos do fichário (centenas a pouco
  mais de mil). Agregação sobre ≤ filled_count exemplares; catálogo e imagem só
  dos grupos da página. Sem índice novo.
================================================================
*/

create or replace function public.get_my_binder_value_groups(
  p_collection_id uuid,
  p_limit         integer default 200,
  p_offset        integer default 0
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
  image_path         text,
  copies_count       integer,
  total_count        bigint,
  total_copies       bigint
)
language plpgsql
security definer
stable
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid        uuid := auth.uid();
  v_layout     uuid;
  v_layout_own uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  if p_limit is null or p_limit not between 1 and 200
     or p_offset is null or p_offset not between 0 and 10000 then
    raise exception 'INVALID_PAGE' using errcode = '22023';
  end if;

  -- 1. Fronteira de autorização antes de qualquer outra tabela.
  perform 1
  from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- 2. Fichário SÓ a partir desta coleção: proprietária ou convidada.
  select l.id into v_layout
  from public.collection_layout l
  where l.collection_id = p_collection_id;
  if v_layout is null then
    select g.layout_id into v_layout
    from public.collection_layout_guest g
    where g.collection_id = p_collection_id;
  end if;
  if v_layout is null then
    return;  -- coleção própria sem fichário: vazio
  end if;

  -- 3. Defesa: o dono da coleção proprietária do fichário é o chamador.
  select oc.owner_user_id into v_layout_own
  from public.collection_layout l
  join public.collection oc on oc.id = l.collection_id
  where l.id = v_layout;
  if v_layout_own is distinct from v_uid then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- 4. Exemplares nos bolsos (só do inventário do chamador), agrupados.
  return query
  with pocketed as (
    select pc.card_variant_id, pc.language_id
    from public.collection_layout_page p
    join public.collection_layout_slot s            on s.page_id = p.id
    join public.collection_layout_slot_assignment a on a.slot_id = s.id
    join public.physical_card pc                    on pc.id = a.physical_card_id
    join public.inventory i                         on i.id = pc.inventory_id
                                                   and i.owner_user_id = v_uid
    where p.layout_id = v_layout
  ),
  grouped as (
    select pk.card_variant_id, pk.language_id, count(*)::integer as n
    from pocketed pk
    group by pk.card_variant_id, pk.language_id
  ),
  ordered as (
    select gr.card_variant_id, gr.language_id, gr.n,
           count(*) over ()  as total,
           sum(gr.n) over () as copies_sum,
           row_number() over (order by
             cs.release_date  desc nulls last,
             cs.release_order desc nulls last,
             cs.code          asc,
             c.collector_order asc,
             cv.variant_order asc,
             l.language_order asc,
             gr.card_variant_id asc,
             gr.language_id     asc) as ord
    from grouped gr
    join public.card_variant cv on cv.id = gr.card_variant_id
    join public.card c          on c.id = cv.card_id
    join public.card_set cs     on cs.id = c.card_set_id
    join public.language l      on l.id = gr.language_id
  )
  select
    o.card_variant_id,
    l.code::text,
    l.name::text,
    c.name::text,
    c.collector_number::text,
    c.collector_total,
    cs.code::text,
    cs.name::text,
    cv.is_default,
    nullif(concat_ws(' · ', vt.name, pp.name, ec.name), '')::text,
    img.storage_path::text,
    o.n,
    o.total,
    o.copies_sum
  from ordered o
  join public.card_variant cv on cv.id = o.card_variant_id
  join public.card c          on c.id = cv.card_id
  join public.card_set cs     on cs.id = c.card_set_id
  join public.language l      on l.id = o.language_id
  left join public.card_variant_type vt            on vt.id = cv.variant_type_id
  left join public.card_printing_profile pp        on pp.id = cv.printing_profile_id
  left join public.card_edition_context_profile ec on ec.id = cv.edition_context_profile_id
  left join lateral (
    select ca.storage_path
    from public.card_asset ca
    join public.card_asset_type cat on cat.id = ca.asset_type_id and cat.code = 'CARD_FRONT'
    join public.language al         on al.id = ca.language_id
    where ca.card_id = c.id
      and ca.is_primary
      and ca.is_active
      and ca.storage_path is not null
    order by (ca.language_id = o.language_id) desc,
             (al.code = 'pt-BR') desc,
             (al.code = 'en') desc,
             al.language_order asc
    limit 1
  ) img on true
  where o.ord > p_offset and o.ord <= p_offset + p_limit
  order by o.ord;
end;
$$;

revoke all on function public.get_my_binder_value_groups(uuid, integer, integer) from public;
revoke all on function public.get_my_binder_value_groups(uuid, integer, integer) from anon;
grant execute on function public.get_my_binder_value_groups(uuid, integer, integer) to authenticated;

comment on function public.get_my_binder_value_groups(uuid, integer, integer) is
  'BINDER-VALUE (Query 5357): grupos Card Variant + idioma dos exemplares físicos do titular posicionados nos bolsos do fichário da coleção informada (proprietária ou convidada), qualquer que seja a coleção do exemplar (05d v2.73, D1). Colunas no formato da 5159 (copies_count) + total_count/total_copies; ordem SET_NUMBER; limite 1..200, offset 0..10000. Exige auth.uid(); coleção alheia/inexistente → P0002 sem enumerar. Somente leitura.';
