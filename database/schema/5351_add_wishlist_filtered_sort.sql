/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5351 - Lista de desejos filtrada (V1-11 W6): ordenação
              "Mais recentes" | "Set e número"
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE (2026-11-03, por Fabrício no SQL Editor, arquivo
              sem edição; sem entrada no ledger de migrations). Harness 5877: 12/12 PASS.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-03

Por que
  A Lista de desejos passa a ter o mesmo controle de ordenação do Meu acervo
  ("Mais recentes" | "Set e número"). A ordem precisa valer para o conjunto
  INTEIRO antes de paginar — ordenar só as 60 linhas da página no cliente
  daria uma ordem errada entre páginas. A 5350 (LIVE) só ordena por data.

O que muda (só leitura; sem tabela, sem índice, sem escrita)
  get_my_wishlist_filtered ganha o 8º argumento p_sort text default 'RECENT'.
  A assinatura de 7 argumentos da 5350 é REMOVIDA no mesmo passo (uma versão
  só da função; chamadas por nome com os 7 argumentos antigos continuam
  válidas pelo default). get_my_wishlist_filter_options NÃO muda.
    RECENT     = exatamente a ordem da 5350/5346 (wished_at desc, entry_id).
    SET_NUMBER = a mesma regra da 5159/5261 (Meu acervo): Card Set mais
                 recente primeiro (release_date desc, release_order desc,
                 código), depois número da carta (collector_order), ordem da
                 variante e idioma do desejo ("qualquer" antes, depois
                 language_order); desempate wished_at desc, entry_id.
  Valor desconhecido → 22023 INVALID_SORT. Todo o resto (filtros, posse
  C-213, busca, total_count do conjunto filtrado, identidade só por
  auth.uid(), EXECUTE só authenticated) é idêntico à 5350.

Desempenho
  Igual à 5350: a contagem total já exige ler o conjunto filtrado do usuário
  (prefixo user_id); a ordenação acontece sobre esse conjunto (centenas a
  milhares de linhas por usuário) com card_set pela PK. Sem índice novo.

Pré-requisito: 5350 no LIVE (ledger 20261103015727).
Como validar: Query 5877 (mesma pasta).
Como reverter (volta exatamente à 5350):
  drop function if exists public.get_my_wishlist_filtered(integer, integer, text, uuid, uuid, text, text, text);
  -- e reaplicar a seção 1 da 5350 (create function + comment + revoke/grant).
================================================================
*/

begin;

drop function if exists public.get_my_wishlist_filtered(integer, integer, text, uuid, uuid, text, text);

create or replace function public.get_my_wishlist_filtered(
  p_limit       integer default 60,
  p_offset      integer default 0,
  p_search      text    default null,
  p_card_set_id uuid    default null,
  p_rarity_id   uuid    default null,
  p_language    text    default null,
  p_ownership   text    default null,
  p_sort        text    default 'RECENT'
)
returns table (
  entry_id          uuid,
  card_variant_id   uuid,
  card_id           uuid,
  card_name         text,
  collector_number  text,
  collector_total   integer,
  card_set_id       uuid,
  card_set_code     text,
  card_set_name     text,
  rarity_id         uuid,
  rarity_name       text,
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
  v_q         text := nullif(btrim(coalesce(p_search, '')), '');
  v_q_like    text;
  v_q_num     text;
  v_q_tot     text;
  v_slash     integer;
  v_lang      text := nullif(btrim(coalesce(p_language, '')), '');
  v_own       text := nullif(upper(btrim(coalesce(p_ownership, ''))), '');
  v_sort      text := upper(coalesce(nullif(btrim(p_sort), ''), 'RECENT'));
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if p_limit is null or p_limit not between 1 and 100
     or p_offset is null or p_offset not between 0 and 100000 then
    raise exception 'INVALID_PAGE' using errcode = '22023';
  end if;

  if v_q is not null and length(v_q) > 100 then
    raise exception 'INVALID_SEARCH' using errcode = '22023';
  end if;

  if v_own is not null and v_own not in ('OWNED', 'NOT_OWNED') then
    raise exception 'INVALID_OWNERSHIP' using errcode = '22023';
  end if;

  if v_sort not in ('RECENT', 'SET_NUMBER') then
    raise exception 'INVALID_SORT' using errcode = '22023';
  end if;

  -- Busca: a mesma regra da 5159 (nome por trecho; número sem zeros à esquerda; "número/total").
  if v_q is not null then
    v_q_like := replace(replace(replace(lower(v_q), '\', '\\'), '%', '\%'), '_', '\_');
    v_slash  := strpos(v_q, '/');
    if v_slash > 0 then
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

  select i.id into v_inventory
  from public.inventory i
  where i.owner_user_id = v_user;

  return query
  with base as (
    select w.id, w.card_variant_id, w.language_id, w.created_at,
           cv.card_id, (cv.is_active and c.is_active) as available,
           cs.release_date, cs.release_order, cs.code as set_code,
           c.collector_order, cv.variant_order, fl.language_order
    from public.card_wishlist_entry w
    join public.card_variant cv on cv.id = w.card_variant_id
    join public.card c          on c.id = cv.card_id
    join public.card_set cs     on cs.id = c.card_set_id
    left join public.language fl on fl.id = w.language_id
    where w.user_id = v_user
      and (p_card_set_id is null or c.card_set_id = p_card_set_id)
      and (p_rarity_id is null or c.rarity_id = p_rarity_id)
      and (v_lang is null
           or (v_lang = '*' and w.language_id is null)
           or (v_lang <> '*' and fl.code = v_lang))
      and (v_q is null
           or lower(c.name) like '%' || v_q_like || '%' escape '\'
           or (coalesce(nullif(ltrim(lower(c.collector_number), '0'), ''), '0') = v_q_num
               and (v_q_tot is null
                    or coalesce(nullif(ltrim(c.collector_total::text, '0'), ''), '0') = v_q_tot)))
  ),
  owned_filter as (
    select b.*,
           -- Só calcula a posse do conjunto quando o filtro de posse está ativo.
           case
             when v_own is null then null
             when v_inventory is null then false
             else exists (
               select 1 from public.physical_card pc
               where pc.inventory_id = v_inventory
                 and pc.card_variant_id = b.card_variant_id
                 and (b.language_id is null or pc.language_id = b.language_id)
             )
           end as has_same
    from base b
  ),
  page as (
    select o.id, o.card_variant_id, o.language_id, o.created_at, o.card_id, o.available,
           count(*) over () as total_count,
           row_number() over (order by
             case when v_sort = 'SET_NUMBER' then o.release_date end desc nulls last,
             case when v_sort = 'SET_NUMBER' then o.release_order end desc nulls last,
             case when v_sort = 'SET_NUMBER' then o.set_code end asc,
             case when v_sort = 'SET_NUMBER' then o.collector_order end asc,
             case when v_sort = 'SET_NUMBER' then o.variant_order end asc,
             -- "Qualquer idioma" antes dos idiomas específicos da mesma variante.
             case when v_sort = 'SET_NUMBER' then (o.language_id is not null) end asc,
             case when v_sort = 'SET_NUMBER' then o.language_order end asc,
             o.created_at desc,
             o.id) as ord
    from owned_filter o
    where v_own is null
       or (v_own = 'OWNED' and o.has_same)
       or (v_own = 'NOT_OWNED' and not o.has_same)
    order by ord
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
  select p.id,
         p.card_variant_id,
         p.card_id,
         c.name::text,
         c.collector_number::text,
         c.collector_total,
         cs.id,
         cs.code::text,
         cs.name::text,
         r.id,
         r.name::text,
         nullif(concat_ws(' · ', vt.name, pp.name, ec.name), '')::text,
         p.available,
         wl.code::text,
         case
           when v_inventory is null then 'NONE'
           when exists (
             select 1 from public.physical_card pc
             where pc.inventory_id = v_inventory
               and pc.card_variant_id = p.card_variant_id
               and (p.language_id is null or pc.language_id = p.language_id)
           ) then 'SAME_VARIANT_LANGUAGE'
           when exists (
             select 1 from public.physical_card pc
             where pc.inventory_id = v_inventory
               and pc.card_variant_id = p.card_variant_id
           ) then 'SAME_VARIANT_OTHER_LANGUAGE'
           when exists (
             select 1
             from public.card_variant ocv
             join public.physical_card pc
               on pc.inventory_id = v_inventory
              and pc.card_variant_id = ocv.id
             where ocv.card_id = p.card_id
               and ocv.id <> p.card_variant_id
           ) then 'OTHER_VARIANT'
           else 'NONE'
         end,
         fa.image_path_pt::text,
         fa.image_path_en::text,
         p.created_at,
         p.total_count
  from page p
  join public.card c      on c.id = p.card_id
  join public.card_set cs on cs.id = c.card_set_id
  join public.rarity r    on r.id = c.rarity_id
  join public.card_variant cv on cv.id = p.card_variant_id
  left join public.card_variant_type vt            on vt.id = cv.variant_type_id
  left join public.card_printing_profile pp        on pp.id = cv.printing_profile_id
  left join public.card_edition_context_profile ec on ec.id = cv.edition_context_profile_id
  left join public.language wl                     on wl.id = p.language_id
  left join front_asset fa                         on fa.card_id = p.card_id
  order by p.ord;
end;
$$;

comment on function public.get_my_wishlist_filtered(integer, integer, text, uuid, uuid, text, text, text) is
  'V1-11 W6 (Queries 5350/5351): página da Lista de desejos do usuário da sessão com filtros combináveis (busca nome/número, Card Set, raridade, idioma do desejo, posse C-213) e ordenação (RECENT | SET_NUMBER) aplicados ao conjunto inteiro antes de paginar; total_count do conjunto filtrado.';

revoke all on function public.get_my_wishlist_filtered(integer, integer, text, uuid, uuid, text, text, text) from public;
revoke all on function public.get_my_wishlist_filtered(integer, integer, text, uuid, uuid, text, text, text) from anon;
grant execute on function public.get_my_wishlist_filtered(integer, integer, text, uuid, uuid, text, text, text) to authenticated;

commit;
