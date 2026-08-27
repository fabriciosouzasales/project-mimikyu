-- Query 3970 — Preços Manuais: corrigir elegibilidade para match_status='NOT_FOUND'
-- estrito, reconciliando com o KPI "Não encontrados" da Visão Geral.
-- Status: CONFIRMADO EXECUTADO em 2026-08-27 via Supabase MCP (apply_migration).
--
-- Contexto: Fabrício reportou divergência funcional — Visão Geral mostrava
-- "Não encontrados" = 18 (get_pricing_admin_overview, count(*) FILTER WHERE
-- match_status='NOT_FOUND' sobre pricing_card_mapping inteira, migration 3939/
-- 3952) enquanto /pricing/precos-manuais mostrava 20 cartas. Causa raiz: a
-- elegibilidade original de admin_list_pricing_manual_price_candidates
-- (migration 3967) era mais ampla — incluía cartas CONFIRMED sem preço
-- automático utilizável na condição (razão 'MATCHED_WITHOUT_USABLE_PRICE'),
-- além de NOT_FOUND. Decisão corrigida por Fabrício: Preços Manuais deve
-- representar EXATAMENTE o universo NOT_FOUND — nunca PENDING, REJECTED,
-- CONFIRMED sem preço automático, ou carta sem mapping.
--
-- Mudança: a CTE `eligible` deixa de agregar por card (bool_or has_confirmed/
-- has_not_found com JOIN em fonte ativa) e de excluir cartas com "automático
-- utilizável" — vira um filtro direto e único:
--   SELECT DISTINCT pcm.card_id, 'NO_EXTERNAL_MATCH' AS reason
--   FROM pricing_card_mapping pcm
--   WHERE pcm.match_status = 'NOT_FOUND'
-- A exclusão de "automático utilizável" se torna redundante por construção:
-- uma carta com preço automático utilizável tem mapping CONFIRMED, nunca
-- NOT_FOUND, na fonte que produziu esse preço — não precisa mais ser
-- verificada explicitamente aqui (a precedência de LEITURA continua intacta,
-- inalterada, nas migrations 3968/3969).
--
-- DISTINCT por card_id (não GROUP BY/bool_or): hoje existe 1 única fonte
-- ativa, então 1 linha NOT_FOUND por carta (confirmado: 18 linhas = 18 cartas
-- distintas, 0 cartas com >1 linha NOT_FOUND). DISTINCT preserva a
-- corretude se uma segunda fonte ativa futura produzir NOT_FOUND na mesma
-- carta — nunca duplica a listagem, mesmo que o KPI de contagem de linha da
-- Visão Geral (que não usa DISTINCT) divirja nesse cenário hipotético futuro.
--
-- 'reason' colapsa para 'NO_EXTERNAL_MATCH' sempre (motivo único agora) —
-- coluna preservada por compatibilidade de contrato com o frontend
-- (PricingManualPriceCandidateItem.reason), sem remover a coluna nesta
-- rodada. 'MATCHED_WITHOUT_USABLE_PRICE' nunca mais é produzido por esta RPC.
--
-- Testado transacionalmente (BEGIN/ROLLBACK) antes da aplicação real:
-- SELECT count(*) sem filtros = 18, 100% reason='NO_EXTERNAL_MATCH'.
-- Validado novamente após a aplicação real (fora de transação de teste):
-- mesmo resultado — 18 linhas, 18 cartas distintas, grants corretos
-- (authenticated + owner, sem PUBLIC/anon). Nenhuma outra RPC/tabela
-- alterada — admin_set_manual_price, pricing_latest_manual_price e a
-- precedência AUTOMATIC > MANUAL das migrations 3968/3969 permanecem
-- intocadas.

DROP FUNCTION public.admin_list_pricing_manual_price_candidates(uuid, text, text, uuid, integer, integer);

CREATE FUNCTION public.admin_list_pricing_manual_price_candidates(
  p_condition_id uuid DEFAULT NULL,
  p_currency text DEFAULT 'BRL',
  p_search text DEFAULT NULL,
  p_card_set_id uuid DEFAULT NULL,
  p_limit integer DEFAULT 20,
  p_offset integer DEFAULT 0
)
RETURNS TABLE(
  card_id uuid,
  card_name text,
  collector_number text,
  collector_total integer,
  card_set_id uuid,
  card_set_code text,
  card_set_name text,
  thumbnail_storage_path text,
  reason text,
  manual_price numeric,
  manual_currency_code text,
  manual_observed_at timestamptz,
  manual_actor_id uuid,
  total_count bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_condition_id uuid;
  v_currency text;
  v_search text;
  v_limit int;
  v_offset int;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'ADMIN_LIST_PRICING_MANUAL_PRICE_CANDIDATES_FORBIDDEN: acesso restrito a administradores.';
  END IF;

  v_currency := UPPER(COALESCE(NULLIF(BTRIM(p_currency), ''), 'BRL'));
  IF v_currency NOT IN ('BRL', 'USD') THEN
    RAISE EXCEPTION 'ADMIN_LIST_PRICING_MANUAL_PRICE_CANDIDATES_INVALID_CURRENCY: %', p_currency;
  END IF;

  IF p_condition_id IS NULL THEN
    SELECT id INTO v_condition_id FROM public.card_condition WHERE code = 'NM';
  ELSE
    SELECT id INTO v_condition_id FROM public.card_condition WHERE id = p_condition_id;
  END IF;

  IF v_condition_id IS NULL THEN
    RAISE EXCEPTION 'ADMIN_LIST_PRICING_MANUAL_PRICE_CANDIDATES_CONDITION_NOT_FOUND: id=%', p_condition_id;
  END IF;

  v_search := NULLIF(BTRIM(p_search), '');
  v_limit := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 100);
  v_offset := GREATEST(COALESCE(p_offset, 0), 0);

  RETURN QUERY
  WITH eligible AS (
    SELECT DISTINCT pcm.card_id, 'NO_EXTERNAL_MATCH'::text AS reason
    FROM public.pricing_card_mapping pcm
    WHERE pcm.match_status = 'NOT_FOUND'
  )
  SELECT
    c.id, c.name::text, c.collector_number::text, c.collector_total,
    cs.id, cs.code::text, cs.name::text,
    thumb.storage_path,
    e.reason,
    mp.price, mp.currency_code, mp.observed_at, mp.actor_id,
    count(*) OVER() AS total_count
  FROM eligible e
  JOIN public.card c ON c.id = e.card_id AND c.is_active = TRUE
  JOIN public.card_set cs ON cs.id = c.card_set_id
  LEFT JOIN LATERAL public.pricing_latest_manual_price(c.id, v_condition_id) mp ON TRUE
  LEFT JOIN LATERAL (
    SELECT ca.storage_path
    FROM public.card_asset ca
    JOIN public.card_asset_type cat ON cat.id = ca.asset_type_id
    JOIN public.language lg ON lg.id = ca.language_id
    WHERE ca.card_id = c.id
      AND ca.is_primary = true
      AND cat.code = 'CARD_FRONT'
      AND lg.code IN ('pt-BR', 'en')
    ORDER BY CASE lg.code WHEN 'pt-BR' THEN 0 WHEN 'en' THEN 1 ELSE 2 END
    LIMIT 1
  ) thumb ON true
  WHERE (p_card_set_id IS NULL OR cs.id = p_card_set_id)
    AND (
      v_search IS NULL
      OR c.name ILIKE '%' || v_search || '%'
      OR c.collector_number ILIKE '%' || v_search || '%'
    )
  ORDER BY cs.release_date DESC NULLS LAST, c.collector_order ASC NULLS LAST, c.id
  LIMIT v_limit
  OFFSET v_offset;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_list_pricing_manual_price_candidates(uuid, text, text, uuid, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_pricing_manual_price_candidates(uuid, text, text, uuid, integer, integer) TO authenticated;
