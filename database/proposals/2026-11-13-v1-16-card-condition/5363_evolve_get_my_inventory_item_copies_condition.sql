/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5363 - get_my_inventory_item_copies + condition_code (V1-16 · S3)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA. Preparada em
              `V1-16 | SQL PREPARATION-01` (2026-11-13) para revisão
              independente. Execução só pelo proprietário, uma etapa por
              vez, na ordem do README desta pasta.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-13
Contrato....: concept-decisions C-227–C-233 (C-108 substituída por C-228);
              05d v3.01, seção "Condição física por exemplar (V1-16)".
Objetivo....: O detalhe do Meu acervo passa a receber a condição de cada
              exemplar (C-232/C-233), sem leitura nova.

Contrato: mesma entrada (uuid, text); retorno = as 20 colunas da 5262,
  na MESMA ordem e com os MESMOS valores, MAIS condition_code text ao
  final (por exemplar). Mudança mínima no corpo: o CTE `mine` lê
  pc.condition_code e o SELECT final a devolve por último.
DROP + CREATE na mesma transação (mudar RETURNS TABLE exige — 42P13),
  no padrão da 5262: precheck de md5 do corpo vigente, do retorno
  vigente, de sobrecarga única e de ausência de dependentes no banco;
  COMMENT, REVOKE e GRANT reaplicados (o DROP os apaga).

Consumidores (nenhum no banco; todos leem por NOME de coluna — coluna ao
  final é inofensiva para o frontend publicado):
    web/lib/colecoes/acervo-queries.ts (getAcervoItemDetail)
    web/app/colecoes/colecoes/actions.ts (três chamadas)
    web/lib/colecoes/free-collection.ts
    web/lib/colecoes/storage-locations-queries.ts
  (a nota de consumidores da 5262 citava só os dois primeiros).

Segurança: idêntica à 5262 (SECURITY DEFINER, search_path vazio, só o
  inventário de auth.uid(); grupo alheio → zero linhas). A condição só
  sai para o DONO — nenhuma superfície compartilhada/pública usa esta
  função (C-233).
Pré-condições: 5361 aplicada; md5 vigente = 5262 canônica.
  Corpo e retorno já iguais aos desta proposta → 'JÁ APLICADA'.
Como validar: harness 5887, grupo C. O harness da 5262 (5858) fixa o
  retorno de 20 colunas e passa a falhar no item de assinatura por
  desenho — substituído pelo grupo C da 5887.
Recuperação: drop function public.get_my_inventory_item_copies(uuid, text);
  e reaplicar database/schema/5262 (corpo e ACL).
================================================================
*/

begin;

set local lock_timeout = '5s';

do $pre$
declare
  v_oid oid := to_regprocedure('public.get_my_inventory_item_copies(uuid, text)');
begin
  if not exists (select 1 from pg_attribute where attrelid = 'public.physical_card'::regclass
                  and attname = 'condition_code' and not attisdropped and attnotnull) then
    raise exception 'PRECHECK 5363: 5361 não aplicada';
  end if;
  if v_oid is null then
    raise exception 'PRECHECK 5363: get_my_inventory_item_copies(uuid, text) ausente';
  end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'get_my_inventory_item_copies') <> 1 then
    raise exception 'PRECHECK 5363: há mais de uma sobrecarga de get_my_inventory_item_copies';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = v_oid) = '77abbb9a33f2cb46280925bade22dee5'
     and pg_get_function_result(v_oid) = 'TABLE(card_variant_id uuid, language_code text, language_name text, card_name text, collector_number text, collector_total integer, card_set_code text, card_set_name text, is_default_variant boolean, variant_label text, image_path text, copies_total integer, physical_card_id uuid, copy_number integer, added_at timestamp with time zone, collection_id uuid, collection_name text, storage_name text, variant_type_code text, rarity_code text, condition_code text)' then
    raise exception 'PRECHECK 5363: JÁ APLICADA — não reaplicar';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = v_oid) <> 'd8cce43b511856a5e25f061e75a7cede' then
    raise exception 'PRECHECK 5363: corpo vigente difere da 5262 canônica — ESTADO DIVERGENTE';
  end if;
  if pg_get_function_result(v_oid) <> 'TABLE(card_variant_id uuid, language_code text, language_name text, card_name text, collector_number text, collector_total integer, card_set_code text, card_set_name text, is_default_variant boolean, variant_label text, image_path text, copies_total integer, physical_card_id uuid, copy_number integer, added_at timestamp with time zone, collection_id uuid, collection_name text, storage_name text, variant_type_code text, rarity_code text)' then
    raise exception 'PRECHECK 5363: retorno vigente difere da 5262 — ESTADO DIVERGENTE';
  end if;
  if exists (select 1 from pg_depend d
             where d.refclassid = 'pg_catalog.pg_proc'::regclass and d.refobjid = v_oid and d.deptype = 'n') then
    raise exception 'PRECHECK 5363: há objetos dependentes de get_my_inventory_item_copies';
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
  rarity_code        text,
  condition_code     text
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
    select pc.id, pc.created_at, pc.storage_container_id, pc.condition_code,
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
    h.rarity_code,
    m.condition_code
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
  'Meu acervo (Query 5162, evoluída pela 5262 e pela 5363): detalhe de um grupo Card Variant + idioma do usuário da sessão — cabeçalho da carta (com códigos estáveis variant_type_code/rarity_code) e um registro por exemplar (coleção e local gravados; nunca inferidos; condition_code = condição física do exemplar, V1-16). Grupo alheio ou inexistente → zero linhas.';

revoke all on function public.get_my_inventory_item_copies(uuid, text) from public;
revoke all on function public.get_my_inventory_item_copies(uuid, text) from anon;
grant execute on function public.get_my_inventory_item_copies(uuid, text) to authenticated;

do $post$
declare v_oid oid := to_regprocedure('public.get_my_inventory_item_copies(uuid, text)');
begin
  if (select md5(prosrc) from pg_proc where oid = v_oid) <> '77abbb9a33f2cb46280925bade22dee5'
     or pg_get_function_result(v_oid) <> 'TABLE(card_variant_id uuid, language_code text, language_name text, card_name text, collector_number text, collector_total integer, card_set_code text, card_set_name text, is_default_variant boolean, variant_label text, image_path text, copies_total integer, physical_card_id uuid, copy_number integer, added_at timestamp with time zone, collection_id uuid, collection_name text, storage_name text, variant_type_code text, rarity_code text, condition_code text)' then
    raise exception 'POSTCHECK 5363: corpo ou retorno gravado difere do proposto';
  end if;
  if not has_function_privilege('authenticated', v_oid, 'EXECUTE')
     or has_function_privilege('anon', v_oid, 'EXECUTE') then
    raise exception 'POSTCHECK 5363: ACL divergente';
  end if;
end;
$post$;

notify pgrst, 'reload schema';

commit;
