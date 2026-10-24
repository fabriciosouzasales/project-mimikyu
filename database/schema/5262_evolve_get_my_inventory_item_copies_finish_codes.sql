/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5262 - get_my_inventory_item_copies(): códigos estáveis de
              variante e raridade para o acabamento visual do detalhe
              (MY-INVENTORY-HOLOGRAPHIC-FINISH-FOUNDATION-01; evolui a 5162)
Versão......: 1.0
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core em 2026-10-24
              (MY-INVENTORY-HOLOGRAPHIC-FINISH-LIVE-EXECUTION-01, autorização expressa
              de Fabrício; ledger 20261024185943 `5262_evolve_get_my_inventory_item_copies_finish_codes`). Texto
              gravado no ledger = arquivo integral de database/proposals/2026-10-24-
              acervo-holographic-finish/ (md5 2ab0eada31e6c7afaf9a778c9eed1cb6); este arquivo difere
              dele só neste bloco Status. Validação 5858: B 8/8 PASS; C original
              INCONCLUSIVA (cadastros concorrentes) e revalidada com acervo pausado
              (estável ×2); D PASS. Homologada visualmente em produção por Fabrício
              (ACERVO-HOLOGRAPHIC-FINISH-FINAL-CLOSEOUT-01). Definição vigente de
              public.get_my_inventory_item_copies.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-24

Por que existe: o detalhe ampliado da carta (decisão 5 da rodada) não lê a
5220/5261 — abre por deep link com uma única chamada à 5162. Sem esta
evolução o detalhe não teria os códigos e ficaria sem efeito.

Contrato: mesma entrada (uuid, text); retorno = as 18 colunas da 5162, na
mesma ordem e com os mesmos valores, MAIS duas ao final (repetidas em cada
linha, como as demais colunas de cabeçalho):
  variant_type_code text, rarity_code text

DROP + CREATE pelo mesmo motivo da 5261 (42P13), na mesma transação.

Consumidores (nenhum no banco): web/lib/colecoes/acervo-queries.ts
(getAcervoItemDetail) e web/app/colecoes/colecoes/actions.ts (três
chamadas). Todos leem por nome de coluna; colunas ao final são inofensivas.

Desempenho: duas colunas a mais no CTE head (1 linha), junção por PK em
rarity. Nenhuma mudança no CTE mine, no limite de 500 nem na ordem.
Segurança: idêntica à 5162.
Recuperação: reaplicar a 5162 canônica depois de
  drop function public.get_my_inventory_item_copies(uuid, text);
Como validar: Query 5858, seções A–D.
================================================================
*/

begin;

do $pre$
declare
  v_oid oid := to_regprocedure('public.get_my_inventory_item_copies(uuid, text)');
begin
  if v_oid is null then
    raise exception 'PRECHECK 5262: assinatura da 5162 ausente';
  end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'get_my_inventory_item_copies') <> 1 then
    raise exception 'PRECHECK 5262: há mais de uma sobrecarga de get_my_inventory_item_copies';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = v_oid) <> '0835268eb6e8b7bfd42e01c146087b26' then
    raise exception 'PRECHECK 5262: corpo vigente difere da 5162 canônica';
  end if;
  if pg_get_function_result(v_oid) <> 'TABLE(card_variant_id uuid, language_code text, language_name text, card_name text, collector_number text, collector_total integer, card_set_code text, card_set_name text, is_default_variant boolean, variant_label text, image_path text, copies_total integer, physical_card_id uuid, copy_number integer, added_at timestamp with time zone, collection_id uuid, collection_name text, storage_name text)' then
    raise exception 'PRECHECK 5262: retorno vigente difere da 5162';
  end if;
  if exists (select 1 from pg_depend d
             where d.refclassid = 'pg_catalog.pg_proc'::regclass and d.refobjid = v_oid and d.deptype = 'n') then
    raise exception 'PRECHECK 5262: há objetos dependentes de get_my_inventory_item_copies';
  end if;
end;
$pre$;

drop function public.get_my_inventory_item_copies(uuid, text);

create function public.get_my_inventory_item_copies(
  p_card_variant_id uuid,
  p_language_code   text
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
  copies_total       integer,
  physical_card_id   uuid,
  copy_number        integer,
  added_at           timestamptz,
  collection_id      uuid,
  collection_name    text,
  storage_name       text,
  variant_type_code  text,
  rarity_code        text
)
language plpgsql
security definer
stable
set search_path = ''
as $$
declare
  v_user      uuid := auth.uid();
  v_inventory uuid;
  v_language  uuid;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if p_card_variant_id is null or nullif(btrim(p_language_code), '') is null then
    raise exception 'INVALID_ITEM' using errcode = '22023';
  end if;

  select i.id into v_inventory
  from public.inventory i
  where i.owner_user_id = v_user;

  select l.id into v_language
  from public.language l
  where l.code = p_language_code;

  if v_inventory is null or v_language is null then
    return;
  end if;

  return query
  with mine as (
    select pc.id, pc.created_at, pc.storage_container_id,
           (row_number() over (order by pc.created_at, pc.id))::integer as num,
           (count(*) over ())::integer as total
    from public.physical_card pc
    where pc.inventory_id = v_inventory
      and pc.card_variant_id = p_card_variant_id
      and pc.language_id = v_language
  ),
  head as (
    select cv.id as variant_id, cv.card_id, cv.is_default,
           c.name::text as card_name, c.collector_number::text as number,
           c.collector_total as total_in_set,
           cs.code::text as set_code, cs.name::text as set_name,
           l.code as lang_code, l.name as lang_name,
           nullif(concat_ws(' · ', vt.name, pp.name, ec.name), '')::text as label,
           -- 5262: códigos estáveis para o acabamento visual do detalhe.
           vt.code::text as type_code,
           r.code::text  as rarity_code
    from public.card_variant cv
    join public.card c       on c.id = cv.card_id
    join public.card_set cs  on cs.id = c.card_set_id
    join public.language l   on l.id = v_language
    left join public.card_variant_type vt            on vt.id = cv.variant_type_id
    left join public.rarity r                        on r.id = c.rarity_id
    left join public.card_printing_profile pp        on pp.id = cv.printing_profile_id
    left join public.card_edition_context_profile ec on ec.id = cv.edition_context_profile_id
    where cv.id = p_card_variant_id
      and exists (select 1 from mine)
  )
  select
    h.variant_id, h.lang_code, h.lang_name, h.card_name, h.number,
    h.total_in_set, h.set_code, h.set_name, h.is_default, h.label,
    img.storage_path,
    m.total,
    m.id, m.num, m.created_at,
    co.id, co.name,
    sc.name,
    h.type_code,
    h.rarity_code
  from head h
  cross join mine m
  left join public.collection_allocation ca on ca.physical_card_id = m.id
  left join public.collection co           on co.id = ca.collection_id
                                          and co.owner_user_id = v_user
  left join public.storage_container sc    on sc.id = m.storage_container_id
                                          and sc.inventory_id = v_inventory
  left join lateral (
    select ca2.storage_path
    from public.card_asset ca2
    join public.card_asset_type cat on cat.id = ca2.asset_type_id and cat.code = 'CARD_FRONT'
    join public.language al on al.id = ca2.language_id
    where ca2.card_id = h.card_id
      and ca2.is_primary
      and ca2.is_active
      and ca2.storage_path is not null
    order by (ca2.language_id = v_language) desc,
             (al.code = 'pt-BR') desc,
             (al.code = 'en') desc,
             al.language_order asc
    limit 1
  ) img on true
  where m.num <= 500
  order by m.num;
end;
$$;

comment on function public.get_my_inventory_item_copies(uuid, text) is
  'Meu acervo (Query 5162, evoluída pela 5262): detalhe de um grupo Card Variant + idioma do usuário da sessão — cabeçalho da carta (com códigos estáveis variant_type_code/rarity_code) e um registro por exemplar (coleção e local gravados; nunca inferidos). Grupo alheio ou inexistente → zero linhas.';

revoke all on function public.get_my_inventory_item_copies(uuid, text) from public;
revoke all on function public.get_my_inventory_item_copies(uuid, text) from anon;
grant execute on function public.get_my_inventory_item_copies(uuid, text) to authenticated;

notify pgrst, 'reload schema';

commit;
