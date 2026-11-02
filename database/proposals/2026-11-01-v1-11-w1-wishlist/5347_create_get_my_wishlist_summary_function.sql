/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5347 - get_my_wishlist_summary() (V1-11 W1): contagem de desejos,
              variantes distintas e valor de referência NM com cobertura
Versão......: 1.0
Status......: PROPOSTO — NÃO EXECUTADO (V1-11 W1 IMPLEMENTATION-01, 2026-11-01)
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-01

Fonte canônica do preço (inalterada)
  public.get_card_variants_pricing_summary(uuid[]) — Query 3983, a mesma do
  V1-09 (etiqueta NM por variante em Acervo/coleções/fichário): VARIANT
  (observação MARKET/NM da própria variante) ou CARD_FALLBACK (referência
  geral da carta); PTAX da data da observação; sem câmbio → has_pricing =
  false. Teto de 100 ids por chamada. Nenhuma regra de Pricing é alterada.

Contrato (C-216 / LDM-206; contrato W0 §7)
  - entry_count: desejos do usuário (cada variante + condição de idioma
    conta uma vez).
  - variant_count: variantes DISTINTAS da lista (ativas ou desativadas —
    a variante desativada continua na lista, C-214).
  - priced_variant_count: dessas, quantas têm referência válida
    (has_pricing, valor não nulo e > 0; referência zero não é cotação —
    mesma decisão da 5340).
  - total_brl: soma de UMA referência por variante distinta coberta.
    Preferências de idioma sobrepostas ("qualquer" + "pt-BR" da mesma
    variante) não duplicam; nunca multiplica por exemplares (o Inventory
    não é lido); NULL quando priced_variant_count = 0 — nunca "R$ 0".
  - Natureza: indicação de mercado; não é preço-alvo, compromisso de compra
    nem valor patrimonial (o desejo não é posse).

Desenho
  SECURITY DEFINER, search_path '', identidade só de auth.uid() (28000),
  STABLE, EXECUTE só authenticated. Variantes distintas lidas uma vez
  (prefixo user_id da unique), ordenadas; a função canônica é chamada em
  blocos de 100 dentro do banco — uma ida do frontend.
  Custo: ceil(variant_count / 100) chamadas da 3983.

Como validar: Query 5873 (mesma pasta), Parte D.
Como reverter: DROP FUNCTION public.get_my_wishlist_summary();
================================================================
*/

begin;

create or replace function public.get_my_wishlist_summary()
returns table (
  entry_count          integer,
  variant_count        integer,
  priced_variant_count integer,
  total_brl            numeric
)
language plpgsql
security definer
stable
set search_path = ''
as $$
declare
  v_user    uuid := auth.uid();
  v_entries integer;
  v_ids     uuid[];
  v_n       integer;
  v_i       integer := 1;
  v_total   numeric := 0;
  v_priced  integer := 0;
  v_part_t  numeric;
  v_part_p  integer;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select count(*)::integer,
         coalesce(array_agg(distinct w.card_variant_id order by w.card_variant_id), '{}'::uuid[])
    into v_entries, v_ids
  from public.card_wishlist_entry w
  where w.user_id = v_user;

  v_n := cardinality(v_ids);

  while v_i <= v_n loop
    select coalesce(sum(s.brl_amount), 0), count(*)::integer
      into v_part_t, v_part_p
    from public.get_card_variants_pricing_summary(v_ids[v_i : least(v_i + 99, v_n)]) s
    where s.has_pricing and s.brl_amount is not null and s.brl_amount > 0;

    v_total  := v_total + v_part_t;
    v_priced := v_priced + v_part_p;
    v_i      := v_i + 100;
  end loop;

  entry_count          := v_entries;
  variant_count        := v_n;
  priced_variant_count := v_priced;
  total_brl            := case when v_priced = 0 then null else v_total end;
  return next;
end;
$$;

comment on function public.get_my_wishlist_summary() is
  'V1-11 W1 (Query 5347): indicadores da Lista de desejos do usuário da sessão — desejos, variantes distintas e valor de referência NM (get_card_variants_pricing_summary, 3983) somado uma vez por variante distinta, com cobertura. total_brl NULL sem cobertura.';

revoke all on function public.get_my_wishlist_summary() from public;
revoke all on function public.get_my_wishlist_summary() from anon;
grant execute on function public.get_my_wishlist_summary() to authenticated;

commit;
