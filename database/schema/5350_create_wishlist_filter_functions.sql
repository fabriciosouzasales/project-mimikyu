/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5350 - Lista de desejos filtrada (V1-11 W6): página com filtros
              combináveis e opções de filtro do próprio usuário
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE (2026-11-03, LIVE SQL VALIDATION-02; ledger
              20261103015727; corpo executado = este arquivo, sem edição). Harness 5876:
              GATE PASS 17/17. Assinatura de 7 argumentos substituída pela 5351.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-02

Por que (lacuna comprovada)
  get_my_wishlist (5346) só pagina (limite/offset): não recebe filtro e não
  devolve card_set_id nem raridade. Filtrar só as 60 linhas da página no
  cliente daria resultados e contagens incompletos. Estas duas leituras
  aplicam os filtros no conjunto INTEIRO do usuário antes de paginar.

Padrão (o mesmo da 5346)
  SECURITY DEFINER, search_path '', objetos qualificados; identidade só de
  auth.uid() — o cliente nunca envia user_id; EXECUTE só authenticated
  (REVOKE de PUBLIC e anon). Sem identidade → 28000. Só leitura: nenhuma
  escrita em desejo, catálogo, inventário, coleção ou fichário.

Funções
  1. get_my_wishlist_filtered(
       p_limit       integer default 60,     -- 1..100
       p_offset      integer default 0,      -- 0..100000
       p_search      text    default null,   -- nome ou número (até 100 caracteres)
       p_card_set_id uuid    default null,   -- Card Set (identidade canônica)
       p_rarity_id   uuid    default null,   -- raridade do catálogo (card.rarity_id)
       p_language    text    default null,   -- null = todos; '*' = só "qualquer idioma";
                                             -- senão código do idioma DO DESEJO
       p_ownership   text    default null)   -- null | 'OWNED' | 'NOT_OWNED'
     → as mesmas colunas da 5346, mais card_set_id, rarity_id e rarity_name.
     Ordem e paginação idênticas à 5346 (wished_at desc, entry_id);
     total_count = total do conjunto FILTRADO (não da página).
     Busca: a mesma regra da 5159 (Meu acervo) — trecho do nome sem
       diferenciar maiúsculas, ou número da carta sem zeros à esquerda,
       opcionalmente "número/total" ("125/094" = "125/94").
     Idioma: '*' casa só desejos "qualquer idioma" (language_id NULL; nunca
       um idioma específico); um código casa só desejos daquele idioma.
     Posse (C-213, mesma derivação da 5346):
       OWNED     = SAME_VARIANT_LANGUAGE — o acervo tem a MESMA variante no
                   idioma desejado ("qualquer" aceita qualquer exemplar);
       NOT_OWNED = todo o resto (sem exemplar, outra variante da carta ou a
                   variante só em outro idioma). Nunca casa só pela carta.
     Erros 22023: INVALID_PAGE, INVALID_SEARCH (> 100), INVALID_OWNERSHIP.
     Card Set, raridade ou idioma inexistentes = 0 linhas (nunca erro: a
     URL pode ficar velha).

  2. get_my_wishlist_filter_options()
     → table(kind text, option_value text, label text, detail text,
             sort_key integer, entry_count bigint)
     Uma linha por opção PRESENTE na lista do usuário, com quantos desejos
     cada uma tem (contagem global, não recalculada pelos outros filtros):
       CARD_SET   value = card_set_id, label = nome do Card Set, detail = código
                  (ordem: lançamento mais recente primeiro)
       RARITY     value = rarity_id, label = nome da raridade (ordem do catálogo)
       LANGUAGE   value = código do idioma ou '*' ("qualquer idioma", primeiro)
       OWNERSHIP  value = OWNED / NOT_OWNED (só os que têm desejos)
     Expansion NÃO entra (W6 filtra Card Set, nunca Expansion).

Desempenho
  Linhas do usuário pelo prefixo user_id (ix_card_wishlist_entry_user_recent),
  card_variant/card/card_set/rarity/language pela PK. A posse só é calculada
  para o conjunto quando o filtro de posse está ativo (CASE com o parâmetro
  antes do EXISTS) e, para as colunas da resposta, só nas linhas da página;
  EXISTS por ix_physical_card_inventory_variant. Imagens só das cartas da
  página. Escala com centenas/milhares de desejos por usuário.

Como validar: Query 5876 (mesma pasta).
Como reverter:
  drop function if exists public.get_my_wishlist_filtered(integer, integer, text, uuid, uuid, text, text);
  drop function if exists public.get_my_wishlist_filter_options();
================================================================
*/

begin;

-- 1. Página filtrada ----------------------------------------------------------
create or replace function public.get_my_wishlist_filtered(
  p_limit       integer default 60,
  p_offset      integer default 0,
  p_search      text    default null,
  p_card_set_id uuid    default null,
  p_rarity_id   uuid    default null,
  p_language    text    default null,
  p_ownership   text    default null
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
           cv.card_id, (cv.is_active and c.is_active) as available
    from public.card_wishlist_entry w
    join public.card_variant cv on cv.id = w.card_variant_id
    join public.card c          on c.id = cv.card_id
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
           count(*) over () as total_count
    from owned_filter o
    where v_own is null
       or (v_own = 'OWNED' and o.has_same)
       or (v_own = 'NOT_OWNED' and not o.has_same)
    order by o.created_at desc, o.id
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
  order by p.created_at desc, p.id;
end;
$$;

comment on function public.get_my_wishlist_filtered(integer, integer, text, uuid, uuid, text, text) is
  'V1-11 W6 (Query 5350): página da Lista de desejos do usuário da sessão com filtros combináveis (busca nome/número, Card Set, raridade, idioma do desejo, posse C-213) aplicados ao conjunto inteiro antes de paginar; total_count do conjunto filtrado.';

-- 2. Opções de filtro ---------------------------------------------------------
create or replace function public.get_my_wishlist_filter_options()
returns table (
  kind         text,
  option_value text,
  label        text,
  detail       text,
  sort_key     integer,
  entry_count  bigint
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

  select i.id into v_inventory
  from public.inventory i
  where i.owner_user_id = v_user;

  return query
  with mine as (
    select w.id, w.card_variant_id, w.language_id, c.card_set_id, c.rarity_id
    from public.card_wishlist_entry w
    join public.card_variant cv on cv.id = w.card_variant_id
    join public.card c          on c.id = cv.card_id
    where w.user_id = v_user
  ),
  sets as (
    select 'CARD_SET'::text as kind, cs.id::text as option_value, cs.name::text as label, cs.code::text as detail,
           row_number() over (order by cs.release_date desc nulls last, cs.release_order desc, cs.name, cs.id)::integer as sort_key,
           count(*)::bigint as entry_count
    from mine m
    join public.card_set cs on cs.id = m.card_set_id
    group by cs.id, cs.name, cs.code, cs.release_date, cs.release_order
  ),
  rarities as (
    select 'RARITY'::text, r.id::text, r.name::text, null::text,
           row_number() over (order by r.display_order, r.name, r.id)::integer,
           count(*)::bigint
    from mine m
    join public.rarity r on r.id = m.rarity_id
    group by r.id, r.name, r.display_order
  ),
  languages as (
    select 'LANGUAGE'::text, coalesce(l.code::text, '*'), coalesce(l.name::text, 'Qualquer idioma'), null::text,
           row_number() over (order by (l.id is not null), l.language_order, l.code)::integer,
           count(*)::bigint
    from mine m
    left join public.language l on l.id = m.language_id
    group by l.id, l.code, l.name, l.language_order
  ),
  owned as (
    select case
             when v_inventory is not null and exists (
               select 1 from public.physical_card pc
               where pc.inventory_id = v_inventory
                 and pc.card_variant_id = m.card_variant_id
                 and (m.language_id is null or pc.language_id = m.language_id)
             ) then 'OWNED'
             else 'NOT_OWNED'
           end as state
    from mine m
  ),
  ownership as (
    select 'OWNERSHIP'::text, o.state, case when o.state = 'OWNED' then 'Já no acervo' else 'Ainda não no acervo' end, null::text,
           case when o.state = 'OWNED' then 1 else 2 end,
           count(*)::bigint
    from owned o
    group by o.state
  )
  select * from sets
  union all select * from rarities
  union all select * from languages
  union all select * from ownership;
end;
$$;

comment on function public.get_my_wishlist_filter_options() is
  'V1-11 W6 (Query 5350): opções de filtro presentes na Lista de desejos do usuário da sessão (Card Set, raridade, idioma do desejo, posse C-213) com a contagem de desejos de cada uma.';

-- Grants ------------------------------------------------------------------------
revoke all on function public.get_my_wishlist_filtered(integer, integer, text, uuid, uuid, text, text) from public;
revoke all on function public.get_my_wishlist_filtered(integer, integer, text, uuid, uuid, text, text) from anon;
grant execute on function public.get_my_wishlist_filtered(integer, integer, text, uuid, uuid, text, text) to authenticated;

revoke all on function public.get_my_wishlist_filter_options() from public;
revoke all on function public.get_my_wishlist_filter_options() from anon;
grant execute on function public.get_my_wishlist_filter_options() to authenticated;

commit;
