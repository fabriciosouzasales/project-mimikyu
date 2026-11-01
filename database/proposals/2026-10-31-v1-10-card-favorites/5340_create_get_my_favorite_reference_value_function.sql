/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5340 - get_my_favorite_reference_value(): valor de referência
              das cartas favoritas, com cobertura (V1-10 — 2º indicador)
Versão......: 1.1
Status......: CONFIRMADO EXECUTADO no LIVE — v1.1 (CONTROLLED EXECUTION-20, 2026-10-31; ledger
              20261031233455; md5(prosrc) LIVE fab45a74… = arquivo; enviada sem `begin;`/`commit;`).
              v1.1 SQL READINESS-18: referência ≤ 0 não conta como cotação
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-31

Fonte canônica da referência por carta
  public.get_cards_pricing_summary(uuid[]) — definição efetiva 3968 +
  hardening 3972 —, a mesma que a Pesquisa usa (via /api/cards/pricing/batch).
  Para cada card_id devolve no máximo UMA referência, já em BRL:
    - condição NM, price_type MARKET, fonte e mapeamento CONFIRMED;
    - hierarquia de impressão fixa: Normal > Holofoil > Reverse Holofoil >
      Unlimited > Unlimited Holofoil > 1st Edition > 1st Edition Holofoil
      (é a "referência geral da carta", não o preço de uma variante possuída);
    - observação mais recente da impressão escolhida;
    - USD → BRL pela PTAX (BCB_PTAX) da data da observação; sem PTAX →
      has_pricing = false (FX_RATE_UNAVAILABLE);
    - fallback de preço manual (Curadoria) em BRL ou convertido;
    - idioma não é considerado (referência do mercado internacional).
  Teto de 100 ids por chamada (3972).

Contrato
  - favorite_count: cartas favoritas ativas do usuário da sessão (Y).
  - priced_count: dessas, quantas têm referência válida: has_pricing, valor não
    nulo e > 0 (X). pricing_observation e pricing_manual_price aceitam price = 0
    (CHECK price >= 0, 3070/3967); referência zero não é cotação — não entra na
    soma nem na cobertura (decisão de apresentação deste KPI; a 3972 não muda).
  - total_brl: soma de UMA referência unitária por carta coberta; nunca
    multiplica por exemplares (o Inventory não é lido); NULL quando X = 0
    (nunca "R$ 0" para ausência de preço).
  - Todas as parcelas estão em BRL e vêm da mesma regra; nada é somado de
    fontes ou moedas incompatíveis; nenhuma variante é escolhida aqui.
  - Sem data de validade: a 3972 não devolve observed_at (a Pesquisa também
    não aplica janela). Limitação registrada no README.

Desenho
  - SECURITY DEFINER, search_path '', identidade só de auth.uid() (28000),
    STABLE, EXECUTE só authenticated.
  - Ids das favoritas ativas lidos uma vez (prefixo da PK de card_favorite +
    PK de card), ordenados; get_cards_pricing_summary chamada em blocos de
    100 dentro do banco — uma ida do frontend, regra de preço não duplicada
    (a função canônica continua sendo a única dona da hierarquia).
  - Custo: ceil(Y / 100) chamadas da função canônica.

Resultado esperado: função criada; 5871 GATE PASS.
Como validar: Query 5871 (mesma pasta).
Como reverter: DROP FUNCTION public.get_my_favorite_reference_value();
================================================================
*/

begin;

create or replace function public.get_my_favorite_reference_value()
returns table (favorite_count integer, priced_count integer, total_brl numeric)
language plpgsql
security definer
stable
set search_path = ''
as $$
declare
  v_user   uuid := auth.uid();
  v_ids    uuid[];
  v_n      integer;
  v_i      integer := 1;
  v_total  numeric := 0;
  v_priced integer := 0;
  v_part_t numeric;
  v_part_p integer;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select coalesce(array_agg(f.card_id order by f.card_id), '{}'::uuid[]) into v_ids
  from public.card_favorite f
  join public.card k on k.id = f.card_id and k.is_active
  where f.user_id = v_user;

  v_n := cardinality(v_ids);

  while v_i <= v_n loop
    select coalesce(sum(s.brl_amount), 0), count(*)::integer
      into v_part_t, v_part_p
    from public.get_cards_pricing_summary(v_ids[v_i : least(v_i + 99, v_n)]) s
    where s.has_pricing and s.brl_amount is not null and s.brl_amount > 0;

    v_total  := v_total + v_part_t;
    v_priced := v_priced + v_part_p;
    v_i      := v_i + 100;
  end loop;

  favorite_count := v_n;
  priced_count   := v_priced;
  total_brl      := case when v_priced = 0 then null else v_total end;
  return next;
end;
$$;

comment on function public.get_my_favorite_reference_value() is
  'V1-10 (Query 5340): valor de referência das cartas favoritas ativas do usuário da sessão — soma de uma referência NM por carta (get_cards_pricing_summary, a mesma da Pesquisa), sem multiplicar por exemplares, com cobertura (priced_count de favorite_count). total_brl NULL sem cobertura.';

revoke all on function public.get_my_favorite_reference_value() from public;
revoke all on function public.get_my_favorite_reference_value() from anon;
grant execute on function public.get_my_favorite_reference_value() to authenticated;

commit;
