-- Query 3967 — Preço Manual (Bloco novo do Pricing Admin) — tabela append-only,
-- helper de leitura, RPC de escrita e RPC de listagem elegível.
-- Status: CONFIRMADO EXECUTADO em 2026-08-27 via Supabase MCP (apply_migration).
--
-- Contexto: fecha o fluxo de cartas sem preço automático utilizável (NOT_FOUND
-- em toda fonte ativa, ou CONFIRMED numa fonte porém sem produto/observação/
-- câmbio que produza um preço exibível) permitindo que um administrador
-- registre um preço declarado manualmente, sem jamais fabricar
-- pricing_card_mapping/pricing_product/external_*_id fictícios e sem tocar
-- pricing_card_mapping em nenhum momento. Desenho aprovado por Fabrício em
-- 3 rodadas de revisão (elegibilidade por card+condition, não por status de
-- mapping isolado; "manual utilizável" formalizado; tolerância de clock skew
-- de observed_at reduzida de 1 dia para 1 hora).
--
-- Elegibilidade da tela (RPC 3, abaixo) — nível CARD, agregando todas as
-- fontes ativas, por CONDITION:
--   elegível ⟺ (existe pricing_card_mapping.CONFIRMED em fonte ativa
--                OR existe pricing_card_mapping.NOT_FOUND em fonte ativa)
--              AND NÃO existe preço automático utilizável para (card, condition).
--   "Automático utilizável" (definição usada aqui e reaplicada verbatim nas
--   migrations 3968/3969): pricing_card_mapping.CONFIRMED, pricing_product
--   ativo, fonte ativa, pricing_observation MARKET na condição pedida, e
--   (moeda da observação = moeda alvo OU câmbio PTAX resolvível para a data
--   da observação). CONFIRMED sozinho nunca basta.
--   Motivo exibido: 'MATCHED_WITHOUT_USABLE_PRICE' quando existe CONFIRMED
--   (mesmo que sem preço utilizável); 'NO_EXTERNAL_MATCH' quando só existe
--   NOT_FOUND. Ausência total de linha em pricing_card_mapping (fonte nunca
--   avaliou a carta) nunca é elegível — não confundir com NOT_FOUND.
--
-- Elegibilidade de ESCRITA (admin_set_manual_price) — deliberadamente sem
-- guard de match_status: qualquer card_id existente pode receber um preço
-- manual a qualquer momento. A decisão de "o que mostrar" vive inteiramente
-- na precedência de leitura (migrations 3968/3969), nunca na escrita — assim
-- um manual registrado quando a carta era NOT_FOUND continua servindo de
-- fallback se o mapping for revertido no futuro, sem exigir re-escrita.
--
-- Modelo append-only: nenhuma rotina faz UPDATE/DELETE em pricing_manual_price
-- — "Atualizar preço" na UI é sempre um novo INSERT; a leitura sempre pega a
-- última linha por (card_id, condition_id) via pricing_latest_manual_price().
--
-- Testado transacionalmente (BEGIN/ROLLBACK, 29 cenários) antes da aplicação
-- real: zero RLS policies, zero grants diretos na tabela, grants corretos
-- (authenticated + owner) nas 2 RPCs, helper sem nenhum grant.

-- ---------------------------------------------------------------------------
-- 1) pricing_manual_price — fato imutável, mesma disciplina de
--    pricing_observation (INSERT-only). RLS habilitado, zero policy, zero
--    grant direto — único caminho de acesso é via RPC SECURITY DEFINER.
-- ---------------------------------------------------------------------------
CREATE TABLE public.pricing_manual_price (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    card_id         UUID NOT NULL REFERENCES public.card (id) ON DELETE RESTRICT,
    condition_id    UUID NOT NULL REFERENCES public.card_condition (id) ON DELETE RESTRICT,
    price           NUMERIC(12,2) NOT NULL,
    currency_code   TEXT NOT NULL DEFAULT 'BRL',
    observed_at     TIMESTAMPTZ NOT NULL,
    reason          TEXT NOT NULL,
    actor_id        UUID REFERENCES auth.users (id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT ck_pricing_manual_price_price_non_negative
        CHECK (price >= 0),
    CONSTRAINT ck_pricing_manual_price_currency_format
        CHECK (currency_code ~ '^[A-Z]{3}$'),
    CONSTRAINT ck_pricing_manual_price_reason_not_blank
        CHECK (BTRIM(reason) <> '')
);

CREATE INDEX ix_pricing_manual_price_latest_lookup
    ON public.pricing_manual_price (card_id, condition_id, observed_at DESC, created_at DESC, id DESC);

ALTER TABLE public.pricing_manual_price ENABLE ROW LEVEL SECURITY;
-- Nenhuma policy, nenhum GRANT direto — mesmo padrão de pricing_admin_action_log
-- (migration 3937). Único caminho de escrita: admin_set_manual_price()
-- (SECURITY DEFINER). Único caminho de leitura: pricing_latest_manual_price()
-- e admin_list_pricing_manual_price_candidates() (ambas SECURITY DEFINER).

-- ---------------------------------------------------------------------------
-- 2) Ampliar vocabulário de pricing_admin_action_log (mesmo padrão DROP+ADD
--    CONSTRAINT já usado em 3963/3964).
-- ---------------------------------------------------------------------------
ALTER TABLE public.pricing_admin_action_log DROP CONSTRAINT pricing_admin_action_log_action_check;
ALTER TABLE public.pricing_admin_action_log DROP CONSTRAINT pricing_admin_action_log_action_entity_match_check;
ALTER TABLE public.pricing_admin_action_log DROP CONSTRAINT pricing_admin_action_log_entity_type_check;

ALTER TABLE public.pricing_admin_action_log
  ADD CONSTRAINT pricing_admin_action_log_entity_type_check
  CHECK (entity_type = ANY (ARRAY[
    'PRICING_SOURCE'::text,
    'PRICING_CARD_MAPPING'::text,
    'PRICING_SET_MAPPING'::text,
    'CARD_CONDITION'::text,
    'PRICING_CONDITION_MAPPING'::text,
    'PRICING_MANUAL_PRICE'::text
  ]));

ALTER TABLE public.pricing_admin_action_log
  ADD CONSTRAINT pricing_admin_action_log_action_check
  CHECK (action = ANY (ARRAY[
    'PRICING_REFRESH_FREQUENCY_CHANGED'::text,
    'PRICING_SOURCE_UPDATED'::text,
    'PRICING_MAPPING_CONFIRMED'::text,
    'PRICING_MAPPING_REJECTED'::text,
    'PRICING_MAPPING_NOT_FOUND'::text,
    'PRICING_SET_MAPPING_DETAILS_UPDATED'::text,
    'PRICING_SET_MAPPING_CONFIRMED'::text,
    'PRICING_SET_MAPPING_REJECTED'::text,
    'CARD_CONDITION_CREATED'::text,
    'CARD_CONDITION_UPDATED'::text,
    'PRICING_CONDITION_MAPPING_UPDATED'::text,
    'PRICING_MANUAL_PRICE_SET'::text
  ]));

ALTER TABLE public.pricing_admin_action_log
  ADD CONSTRAINT pricing_admin_action_log_action_entity_match_check
  CHECK (
    ((entity_type = 'PRICING_SOURCE'::text) AND (action = ANY (ARRAY['PRICING_REFRESH_FREQUENCY_CHANGED'::text, 'PRICING_SOURCE_UPDATED'::text])))
    OR ((entity_type = 'PRICING_CARD_MAPPING'::text) AND (action = ANY (ARRAY['PRICING_MAPPING_CONFIRMED'::text, 'PRICING_MAPPING_REJECTED'::text, 'PRICING_MAPPING_NOT_FOUND'::text])))
    OR ((entity_type = 'PRICING_SET_MAPPING'::text) AND (action = ANY (ARRAY['PRICING_SET_MAPPING_DETAILS_UPDATED'::text, 'PRICING_SET_MAPPING_CONFIRMED'::text, 'PRICING_SET_MAPPING_REJECTED'::text])))
    OR ((entity_type = 'CARD_CONDITION'::text) AND (action = ANY (ARRAY['CARD_CONDITION_CREATED'::text, 'CARD_CONDITION_UPDATED'::text])))
    OR ((entity_type = 'PRICING_CONDITION_MAPPING'::text) AND (action = 'PRICING_CONDITION_MAPPING_UPDATED'::text))
    OR ((entity_type = 'PRICING_MANUAL_PRICE'::text) AND (action = 'PRICING_MANUAL_PRICE_SET'::text))
  );

-- ---------------------------------------------------------------------------
-- 3) pricing_latest_manual_price() — helper de leitura, última linha por
--    (card_id, condition_id). Sem GRANT — só chamável a partir de outra
--    SECURITY DEFINER (mesmo padrão de admin_pricing_report_set_price_candidates,
--    migration 3944).
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.pricing_latest_manual_price(p_card_id uuid, p_condition_id uuid)
RETURNS TABLE(price numeric, currency_code text, observed_at timestamptz, reason text, actor_id uuid)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $$
  SELECT price, currency_code, observed_at, reason, actor_id
  FROM public.pricing_manual_price
  WHERE card_id = p_card_id AND condition_id = p_condition_id
  ORDER BY observed_at DESC, created_at DESC, id DESC
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.pricing_latest_manual_price(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.pricing_latest_manual_price(uuid, uuid) FROM authenticated, anon, service_role;

-- ---------------------------------------------------------------------------
-- 4) admin_set_manual_price() — escrita administrativa (INSERT append-only +
--    auditoria). Sem guard de match_status (ver nota no cabeçalho).
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.admin_set_manual_price(
  p_card_id uuid,
  p_condition_id uuid,
  p_price numeric,
  p_currency_code text DEFAULT 'BRL',
  p_observed_at timestamptz DEFAULT now(),
  p_reason text DEFAULT NULL
)
RETURNS TABLE(
  id uuid, card_id uuid, condition_id uuid, price numeric, currency_code text,
  observed_at timestamptz, reason text, actor_id uuid, created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_actor uuid;
  v_currency text;
  v_row public.pricing_manual_price;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'ADMIN_SET_MANUAL_PRICE_FORBIDDEN: acesso restrito a administradores.';
  END IF;

  v_actor := auth.uid();

  -- Colunas de saída da função (id, card_id, condition_id, ...) colidem em nome
  -- com colunas de card/card_condition; aliases evitam erro 42702 (ambiguous).
  IF NOT EXISTS (SELECT 1 FROM public.card c WHERE c.id = p_card_id) THEN
    RAISE EXCEPTION 'ADMIN_SET_MANUAL_PRICE_CARD_NOT_FOUND: id=%', p_card_id;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.card_condition cc WHERE cc.id = p_condition_id) THEN
    RAISE EXCEPTION 'ADMIN_SET_MANUAL_PRICE_CONDITION_NOT_FOUND: id=%', p_condition_id;
  END IF;

  IF p_price IS NULL OR p_price < 0 THEN
    RAISE EXCEPTION 'ADMIN_SET_MANUAL_PRICE_INVALID_PRICE: %', p_price;
  END IF;

  v_currency := UPPER(COALESCE(NULLIF(BTRIM(p_currency_code), ''), 'BRL'));
  IF v_currency !~ '^[A-Z]{3}$' THEN
    RAISE EXCEPTION 'ADMIN_SET_MANUAL_PRICE_INVALID_CURRENCY: %', p_currency_code;
  END IF;

  IF p_reason IS NULL OR BTRIM(p_reason) = '' THEN
    RAISE EXCEPTION 'ADMIN_SET_MANUAL_PRICE_REASON_REQUIRED';
  END IF;

  IF p_observed_at IS NULL THEN
    RAISE EXCEPTION 'ADMIN_SET_MANUAL_PRICE_OBSERVED_AT_REQUIRED';
  END IF;

  -- Tolerância de clock skew: 1 hora (ajuste de Fabrício, 2026-08-27 —
  -- reduzida de 1 dia). TIMESTAMPTZ já resolve fuso horário corretamente;
  -- esta tolerância cobre só divergência de relógio entre cliente e servidor.
  IF p_observed_at > now() + interval '1 hour' THEN
    RAISE EXCEPTION 'ADMIN_SET_MANUAL_PRICE_OBSERVED_AT_IN_FUTURE: %', p_observed_at;
  END IF;

  INSERT INTO public.pricing_manual_price (card_id, condition_id, price, currency_code, observed_at, reason, actor_id)
  VALUES (p_card_id, p_condition_id, p_price, v_currency, p_observed_at, BTRIM(p_reason), v_actor)
  RETURNING * INTO v_row;

  INSERT INTO public.pricing_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
  VALUES (
    v_actor, 'PRICING_MANUAL_PRICE_SET', 'PRICING_MANUAL_PRICE', v_row.id,
    jsonb_build_object(
      'card_id', p_card_id, 'condition_id', p_condition_id,
      'price', v_row.price, 'currency_code', v_row.currency_code,
      'observed_at', v_row.observed_at, 'reason', v_row.reason
    )
  );

  RETURN QUERY
  SELECT v_row.id, v_row.card_id, v_row.condition_id, v_row.price, v_row.currency_code,
         v_row.observed_at, v_row.reason, v_row.actor_id, v_row.created_at;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_set_manual_price(uuid, uuid, numeric, text, timestamptz, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_manual_price(uuid, uuid, numeric, text, timestamptz, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 5) admin_list_pricing_manual_price_candidates() — listagem elegível da
--    tela /pricing/precos-manuais. Elegibilidade por CARD+CONDITION (ver
--    nota no cabeçalho) — nunca por status de mapping isolado.
-- ---------------------------------------------------------------------------
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
  WITH mapping_agg AS (
    SELECT
      pcm.card_id,
      bool_or(pcm.match_status = 'CONFIRMED') AS has_confirmed,
      bool_or(pcm.match_status = 'NOT_FOUND') AS has_not_found
    FROM public.pricing_card_mapping pcm
    JOIN public.pricing_source ps ON ps.id = pcm.pricing_source_id AND ps.is_active = TRUE
    GROUP BY pcm.card_id
  ),
  -- "Automático utilizável" (mesma definição reaplicada nas migrations
  -- 3968/3969): CONFIRMED + produto ativo + fonte ativa + observação MARKET
  -- na condição pedida + (moeda = alvo OU câmbio PTAX resolvível).
  automatic_usable AS (
    SELECT DISTINCT pcm.card_id
    FROM public.pricing_card_mapping pcm
    JOIN public.pricing_source ps ON ps.id = pcm.pricing_source_id AND ps.is_active = TRUE
    JOIN public.pricing_product pp ON pp.pricing_card_mapping_id = pcm.id AND pp.is_active = TRUE
    JOIN public.pricing_observation po ON po.pricing_product_id = pp.id
       AND po.condition_id = v_condition_id AND po.price_type = 'MARKET'
    LEFT JOIN LATERAL (
      SELECT 1
      FROM public.pricing_fx_rate fx
      WHERE fx.from_currency = po.currency_code AND fx.to_currency = v_currency
        AND fx.rate_source_code = 'BCB_PTAX'
        AND fx.rate_date <= (po.observed_at AT TIME ZONE 'UTC')::date
      ORDER BY fx.rate_date DESC
      LIMIT 1
    ) fx ON TRUE
    WHERE pcm.match_status = 'CONFIRMED'
      AND (po.currency_code = v_currency OR fx IS NOT NULL)
  ),
  eligible AS (
    SELECT
      ma.card_id,
      CASE WHEN ma.has_confirmed THEN 'MATCHED_WITHOUT_USABLE_PRICE' ELSE 'NO_EXTERNAL_MATCH' END AS reason
    FROM mapping_agg ma
    WHERE (ma.has_confirmed OR ma.has_not_found)
      AND ma.card_id NOT IN (SELECT au.card_id FROM automatic_usable au)
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
