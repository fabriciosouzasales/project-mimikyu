/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5353 - get_my_inventory_value_report(): Inventário e valor do
              Acervo (V1-14 R1-B, contrato D7 §D7.6)
Versão......: 1.0
Status......: PROPOSTO — NÃO EXECUTADO; EM REAVALIAÇÃO, NÃO APLICAR (REPORT CATALOG
              RESTRUCTURING-03, 2026-11-06: Valor, Top 10 e Cobertura viram relatórios distintos)
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-06

Por que (lacuna comprovada)
  - 5160 (get_my_inventory_summary) dá exemplares, diferentes e repetidas,
    mas nenhum valor.
  - 3983 (get_card_variants_pricing_summary) dá a referência NM por variante,
    mas aceita até 100 ids por chamada e não conhece o Inventory: valorar o
    acervo inteiro pelo frontend exigiria ler todos os exemplares (5159
    pagina grupos, não exemplares) e N chamadas.
  - 5340/5347 valoram Favoritos/Wishlist UMA vez por carta/variante; o
    patrimônio (D7.6) soma por EXEMPLAR físico.
  Menor extensão: uma leitura agregada que reaproveita a 3983 sem alterá-la.

Fonte canônica do preço (inalterada)
  public.get_card_variants_pricing_summary(uuid[]) — Query 3983: VARIANT
  (observação MARKET/NM da própria variante) ou CARD_FALLBACK (referência
  geral da carta); PTAX da data da observação; sem câmbio → has_pricing =
  false. Idioma e condição física do exemplar NÃO entram (referência do
  mercado internacional, NM). Nenhuma regra de Pricing é alterada.

Contrato (uma linha, sempre — inclusive acervo vazio)
  total_copies         exemplares (Physical Cards) do Inventory do usuário
  distinct_items       grupos Card Variant + idioma ("diferentes", = 5160)
  duplicate_copies     total_copies − distinct_items (= 5160)
  distinct_cards       Cards (identidade canônica de catálogo) distintas
  variant_count        Card Variants distintas no acervo
  priced_variant_count dessas, com referência válida (has_pricing, valor
                       não nulo e > 0 — referência zero não é cotação,
                       mesma decisão de 5340/5347)
  priced_copies        exemplares cuja variante tem referência válida
  unpriced_copies      total_copies − priced_copies (nunca valem zero)
  total_brl            Σ por exemplar da referência da sua variante; NULL
                       quando priced_copies = 0 (nunca "R$ 0" por ausência)
  price_observed_min   observação mais antiga entre as referências usadas
  price_observed_max   observação mais recente (NULL se nenhuma traz data)
  top_copies           jsonb: até p_top exemplares (1–50, padrão 10) mais
                       valiosos, SÓ entre os cotados, um item por exemplar:
                       rank, physical_card_id, card_variant_id, card_name,
                       collector_number, collector_total, card_set_code,
                       card_set_name, variant_label, is_default_variant,
                       language_code, copy_index, copy_count (cópia N de M
                       do mesmo Card Variant + idioma, por data de cadastro),
                       added_at, brl_amount, price_basis, observed_at
  Ordem do Top (determinística, total): brl_amount desc, card_name,
  card_set_code, collector_number, card_variant_id, language_code,
  added_at, physical_card_id.

Desenho
  SECURITY DEFINER, STABLE, search_path '', identidade só de auth.uid()
  (28000), EXECUTE só authenticated. Somente leitura: nenhuma escrita em
  Inventory, coleções, Pricing ou Wishlist.
  Variantes distintas do usuário lidas uma vez (ix_physical_card_inventory_variant);
  3983 chamada em blocos de 100 dentro do banco (uma ida do frontend);
  totais e Top num único agrupamento sobre os exemplares do usuário.
  Custo: ceil(variant_count / 100) chamadas da 3983 + O(total_copies).

Resultado esperado: função criada; 5879 GATE PASS.
Como validar: Query 5879 (mesma pasta).
Como reverter: DROP FUNCTION public.get_my_inventory_value_report(integer);
================================================================
*/

begin;

create or replace function public.get_my_inventory_value_report(p_top integer default 10)
returns table (
  total_copies         bigint,
  distinct_items       bigint,
  duplicate_copies     bigint,
  distinct_cards       bigint,
  variant_count        integer,
  priced_variant_count integer,
  priced_copies        bigint,
  unpriced_copies      bigint,
  total_brl            numeric,
  price_observed_min   timestamptz,
  price_observed_max   timestamptz,
  top_copies           jsonb
)
language plpgsql
security definer
stable
set search_path = ''
as $$
declare
  v_user      uuid := auth.uid();
  v_inventory uuid;
  v_ids       uuid[];
  v_n         integer;
  v_i         integer := 1;
  v_p_ids     uuid[] := '{}';
  v_p_brl     numeric[] := '{}';
  v_p_basis   text[] := '{}';
  v_p_obs     timestamptz[] := '{}';
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_top is null or p_top < 1 or p_top > 50 then
    raise exception 'invalid_top' using errcode = '22023';
  end if;

  select i.id into v_inventory from public.inventory i where i.owner_user_id = v_user;

  select coalesce(array_agg(distinct pc.card_variant_id order by pc.card_variant_id), '{}'::uuid[])
    into v_ids
  from public.physical_card pc
  where v_inventory is not null and pc.inventory_id = v_inventory;

  v_n := cardinality(v_ids);

  while v_i <= v_n loop
    select v_p_ids   || coalesce(array_agg(s.card_variant_id), '{}'),
           v_p_brl   || coalesce(array_agg(s.brl_amount), '{}'),
           v_p_basis || coalesce(array_agg(s.price_basis), '{}'),
           v_p_obs   || coalesce(array_agg(s.observed_at), '{}')
      into v_p_ids, v_p_brl, v_p_basis, v_p_obs
    from public.get_card_variants_pricing_summary(v_ids[v_i : least(v_i + 99, v_n)]) s
    where s.has_pricing and s.brl_amount is not null and s.brl_amount > 0;
    v_i := v_i + 100;
  end loop;

  return query
  with copies as (
    select pc.id, pc.card_variant_id, pc.language_id, pc.created_at,
           row_number() over (partition by pc.card_variant_id, pc.language_id order by pc.created_at, pc.id) as copy_index,
           count(*)     over (partition by pc.card_variant_id, pc.language_id) as copy_count
    from public.physical_card pc
    where v_inventory is not null and pc.inventory_id = v_inventory
  ),
  prices as (
    select u.vid, u.brl, u.basis, u.obs
    from unnest(v_p_ids, v_p_brl, v_p_basis, v_p_obs) as u(vid, brl, basis, obs)
  ),
  valued as (
    select cp.*, pr.brl, pr.basis, pr.obs
    from copies cp
    left join prices pr on pr.vid = cp.card_variant_id
  ),
  totals as (
    select count(*)::bigint as total_copies,
           count(distinct (v.card_variant_id, v.language_id))::bigint as distinct_items,
           count(*) filter (where v.brl is not null)::bigint as priced_copies,
           sum(v.brl) as total_brl
    from valued v
  ),
  cards as (
    select count(distinct cv.card_id)::bigint as n
    from (select distinct v.card_variant_id from valued v) d
    join public.card_variant cv on cv.id = d.card_variant_id
  ),
  top_rows as (
    select v.id, v.card_variant_id, v.language_id, v.created_at, v.copy_index, v.copy_count,
           v.brl, v.basis, v.obs,
           c.name::text as card_name, c.collector_number::text as collector_number, c.collector_total,
           cs.code::text as set_code, cs.name::text as set_name, cv.is_default,
           nullif(concat_ws(' · ', vt.name, pp.name, ec.name), '')::text as variant_label,
           l.code::text as language_code
    from valued v
    join public.card_variant cv on cv.id = v.card_variant_id
    join public.card c          on c.id = cv.card_id
    join public.card_set cs     on cs.id = c.card_set_id
    join public.language l      on l.id = v.language_id
    left join public.card_variant_type vt            on vt.id = cv.variant_type_id
    left join public.card_printing_profile pp        on pp.id = cv.printing_profile_id
    left join public.card_edition_context_profile ec on ec.id = cv.edition_context_profile_id
    where v.brl is not null
    order by v.brl desc, c.name, cs.code, c.collector_number, v.card_variant_id, l.code, v.created_at, v.id
    limit p_top
  ),
  top_json as (
    select coalesce(jsonb_agg(jsonb_build_object(
             'rank', t.rk,
             'physical_card_id', t.id,
             'card_variant_id', t.card_variant_id,
             'card_name', t.card_name,
             'collector_number', t.collector_number,
             'collector_total', t.collector_total,
             'card_set_code', t.set_code,
             'card_set_name', t.set_name,
             'variant_label', t.variant_label,
             'is_default_variant', t.is_default,
             'language_code', t.language_code,
             'copy_index', t.copy_index,
             'copy_count', t.copy_count,
             'added_at', t.created_at,
             'brl_amount', t.brl,
             'price_basis', t.basis,
             'observed_at', t.obs) order by t.rk), '[]'::jsonb) as j
    from (
      select tp.*, row_number() over (order by tp.brl desc, tp.card_name, tp.set_code, tp.collector_number,
                                               tp.card_variant_id, tp.language_code, tp.created_at, tp.id) as rk
      from top_rows tp
    ) t
  )
  select
    tt.total_copies,
    tt.distinct_items,
    tt.total_copies - tt.distinct_items,
    (select cd.n from cards cd),
    v_n,
    cardinality(v_p_ids),
    tt.priced_copies,
    tt.total_copies - tt.priced_copies,
    case when tt.priced_copies = 0 then null else tt.total_brl end,
    (select min(p.obs) from prices p),
    (select max(p.obs) from prices p),
    (select tj.j from top_json tj)
  from totals tt;
end;
$$;

comment on function public.get_my_inventory_value_report(integer) is
  'V1-14 R1-B (Query 5353): inventário e valor estimado do Acervo do usuário da sessão — exemplares, diferentes (Card Variant + idioma), repetidas, cartas distintas, valor por exemplar pela referência NM da variante (get_card_variants_pricing_summary, 3983), cobertura por exemplar e Top N exemplares cotados (ordem determinística). total_brl NULL sem cobertura. Somente leitura; exige auth.uid().';

revoke all on function public.get_my_inventory_value_report(integer) from public;
revoke all on function public.get_my_inventory_value_report(integer) from anon;
grant execute on function public.get_my_inventory_value_report(integer) to authenticated;

commit;
