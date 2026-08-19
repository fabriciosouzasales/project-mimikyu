-- Query 3914 — CONFIRMADO EXECUTADO (revisão de segurança do P14.3 — persistência em
-- lotes), a pedido de Fabrício, ANTES da reexecução real do piloto BASE4.
-- Aplicada via Supabase MCP em 2026-08-19.
--
-- Parte 1 — batch_update_pricing_card_mapping_status: reescrita para ser EXCLUSIVAMENTE de
-- promoção. A versão anterior (Query 3913) tinha WHERE t.id = u.id sem nenhuma proteção
-- adicional — testado transacionalmente e comprovado que permitia rebaixar uma linha
-- CONFIRMED (para PENDING/NOT_FOUND) ou trocar sua identidade externa (external_card_id/
-- external_card_name/match_evidence) mantendo match_status='CONFIRMED'. Corrigido: a função
-- agora só afeta linhas cujo status atual seja PENDING ou NOT_FOUND E cujo status-alvo seja
-- CONFIRMED — qualquer outra combinação (CONFIRMED->qualquer coisa, PENDING->NOT_FOUND,
-- NOT_FOUND->PENDING) não casa no WHERE e a linha não é tocada (0 linhas afetadas, sem
-- erro). A proteção vive no WHERE da função, não apenas no TypeScript chamador — nunca
-- SECURITY DEFINER, EXECUTE restrito a service_role.
--
-- Parte 2 — batch_select_pricing_observation_by_identity: nova função. A pré-busca de
-- pricing_observation em scripts/sync-justtcg-pricing.ts usava 3 listas .in() independentes
-- (productIds/conditionIds/observedAtValues), o que gera um produto cartesiano — uma linha
-- cujo produto, condição e observed_at aparecessem individualmente em QUALQUER lugar do lote
-- passava pelo filtro, mesmo que essa combinação exata não correspondesse a nenhuma variante
-- real desta execução. Corrigida com JOIN por tupla COMPLETA da business key real de
-- pricing_observation (uq_pricing_observation_identity_market_aware: pricing_product_id,
-- condition_id, price_type, currency_code, market_label, observed_at), recebendo até 100
-- chaves completas por chamada via jsonb_to_recordset. SECURITY INVOKER (roda com o
-- privilégio de quem chama — service_role já tem SELECT direto em pricing_observation desde
-- a Query 3091/3002, nenhum GRANT novo necessário). EXECUTE restrito a service_role.
--
-- Ambas testadas transacionalmente (BEGIN/ROLLBACK) antes desta aplicação real:
-- (1) PENDING->CONFIRMED permitido; NOT_FOUND->CONFIRMED permitido; CONFIRMED->PENDING
--     bloqueado (0 linhas, linha intacta); CONFIRMED->CONFIRMED com outro external_card_id
--     bloqueado (0 linhas, byte-a-byte idêntica); PENDING->NOT_FOUND bloqueado (0 linhas).
-- (2) 2 chaves solicitadas contra dados reais com "iscas" deliberadas (mesmo produto+
--     condição noutra data; produto diferente com mesma condição+data de uma das chaves
--     pedidas) -> exatamente as 2 linhas pedidas voltaram, nenhuma isca vazou. Todas as 699
--     identidades reais da tabela solicitadas de uma vez -> 699 retornadas, 1:1, sem perda
--     nem duplicação.
--
-- Revalidado pós-aplicação via pg_proc: prosecdef=false (SECURITY INVOKER) nas duas,
-- search_path='public, pg_temp' nas duas, proacl = {postgres=X/postgres,
-- service_role=X/postgres} nas duas (sem PUBLIC, sem anon, sem authenticated). Reexecutado
-- transacionalmente contra as funções já publicadas: promoção e bloqueio de rebaixamento
-- confirmados; busca por identidade exata confirmada (1 linha, preço correto).

CREATE OR REPLACE FUNCTION public.batch_update_pricing_card_mapping_status(p_updates jsonb)
RETURNS TABLE(id uuid, card_id uuid)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  RETURN QUERY
  UPDATE public.pricing_card_mapping t
  SET
    match_status = u.match_status,
    match_method = u.match_method,
    match_evidence = u.match_evidence,
    last_checked_at = u.last_checked_at,
    external_card_id = u.external_card_id,
    external_card_name = u.external_card_name,
    confirmed_at = u.confirmed_at,
    confirmed_by = u.confirmed_by
  FROM jsonb_to_recordset(p_updates) AS u(
    id uuid,
    match_status text,
    match_method text,
    match_evidence jsonb,
    last_checked_at timestamptz,
    external_card_id text,
    external_card_name text,
    confirmed_at timestamptz,
    confirmed_by uuid
  )
  WHERE t.id = u.id
    AND t.match_status IN ('PENDING', 'NOT_FOUND')
    AND u.match_status = 'CONFIRMED'
  RETURNING t.id, t.card_id;
END;
$function$;

COMMENT ON FUNCTION public.batch_update_pricing_card_mapping_status(jsonb) IS
  'P14.3 (revisão de segurança 2026-08-19) — UPDATE em lote de pricing_card_mapping, EXCLUSIVAMENTE promoção PENDING/NOT_FOUND -> CONFIRMED. Nunca rebaixa nem troca identidade de uma linha CONFIRMED (WHERE t.match_status IN (PENDING,NOT_FOUND) AND u.match_status=CONFIRMED). SECURITY INVOKER, escreve só as 8 colunas concedidas por GRANT UPDATE (Query 3912). Nunca chamada por anon/authenticated. Ver Query 3914 e ADR-029/05f-pricing.md (P14.3).';

CREATE FUNCTION public.batch_select_pricing_observation_by_identity(p_keys jsonb)
RETURNS TABLE(
  pricing_product_id uuid,
  condition_id uuid,
  price_type text,
  currency_code text,
  market_label text,
  observed_at timestamptz,
  price numeric
)
LANGUAGE sql
SECURITY INVOKER
STABLE
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT o.pricing_product_id, o.condition_id, o.price_type, o.currency_code, o.market_label, o.observed_at, o.price
  FROM public.pricing_observation o
  JOIN jsonb_to_recordset(p_keys) AS k(
    pricing_product_id uuid,
    condition_id uuid,
    price_type text,
    currency_code text,
    market_label text,
    observed_at timestamptz
  ) ON o.pricing_product_id = k.pricing_product_id
     AND o.condition_id = k.condition_id
     AND o.price_type = k.price_type
     AND o.currency_code = k.currency_code
     AND o.market_label IS NOT DISTINCT FROM k.market_label
     AND o.observed_at = k.observed_at;
$function$;

COMMENT ON FUNCTION public.batch_select_pricing_observation_by_identity(jsonb) IS
  'P14.3 (revisão de segurança 2026-08-19) — busca em lote de pricing_observation por tupla COMPLETA da business key real (uq_pricing_observation_identity_market_aware), até 100 chaves por chamada. Substitui pré-busca por 3 listas .in() independentes (produto cartesiano, corrigido). SECURITY INVOKER (usa o SELECT já concedido a service_role desde Query 3091/3002, nenhum GRANT novo). Nunca chamada por anon/authenticated. Ver Query 3914 e ADR-029/05f-pricing.md (P14.3).';

REVOKE ALL ON FUNCTION public.batch_update_pricing_card_mapping_status(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.batch_update_pricing_card_mapping_status(jsonb) TO service_role;

REVOKE ALL ON FUNCTION public.batch_select_pricing_observation_by_identity(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.batch_select_pricing_observation_by_identity(jsonb) TO service_role;
