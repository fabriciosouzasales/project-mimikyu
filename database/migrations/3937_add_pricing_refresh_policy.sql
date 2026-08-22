-- Query 3937 — Política de frequência de sincronização de Pricing
-- Status: CONFIRMADO EXECUTADO em 2026-08-22 (Supabase MCP, projeto qjfutqujxrbzgrtkpgkg)
--
-- Objetivo: introduzir a infraestrutura da Política de Sincronização de
-- Pricing — configuração admin-only de frequência de refresh por
-- pricing_source (1/2/3/5 dias), separada do estado operacional em
-- pricing_set_refresh_state. Cria pricing_refresh_policy (config) e
-- pricing_admin_action_log (trilha de auditoria zero-grant, mesmo padrão
-- de catalog_admin_action_log/ADR-023), as RPCs admin
-- admin_set_pricing_refresh_frequency()/get_pricing_refresh_policy(), e
-- altera cirurgicamente close_pricing_set_refresh_attempt() para que o
-- branch SUCCESS calcule next_due_at a partir da frequência configurada
-- (fallback 1 dia quando não há policy explícita), em vez do intervalo
-- fixo de ~24h anterior. O dispatcher (*/5 * * * *, migration 3935)
-- permanece inalterado — a política só passa a valer no próximo SUCCESS
-- de cada Set, nunca recomputa next_due_at de linhas já agendadas.
--
-- Aprovado por Fabrício em 3 rodadas: arquitetura, formalização SQL, e
-- correção de privilégio mínimo (GRANT SELECT a service_role, suficiente
-- para o SECURITY INVOKER de close_pricing_set_refresh_attempt) + no-op
-- guard em admin_set_pricing_refresh_frequency() (mudança para a mesma
-- frequência não gera update nem entrada de auditoria).
--
-- Nota: esta migration contém um bug real (ON CONFLICT (pricing_source_id)
-- ambíguo contra a variável de saída homônima de
-- RETURNS TABLE(pricing_source_id, ...)), descoberto durante a validação
-- funcional pós-aplicação e corrigido pela migration 3938, sem alterar
-- mais nada. Ver 3938 para o detalhe do defeito e da correção.
--
-- Resultado confirmado pós-execução (antes da correção 3938):
--   pricing_refresh_policy: 1 linha (JUSTTCG, frequency_days=1)
--   pricing_admin_action_log: 0 linhas (nenhuma escrita administrativa ainda)
--   service_role: SELECT concedido em pricing_refresh_policy, sem INSERT/UPDATE/DELETE
--   authenticated: sem acesso direto às tabelas (só via RPC SECURITY DEFINER)
--   zero novo advisory de segurança de classe nova (mesmo padrão WARN já
--   aceito para admin_*/get_* SECURITY DEFINER e rls_enabled_no_policy)

-- ---------------------------------------------------------------------
-- 1) pricing_admin_action_log — trilha de auditoria de escrita
--    administrativa do módulo Pricing (mesmo padrão de
--    catalog_admin_action_log, ADR-023): RLS habilitado, zero policies,
--    zero grants diretos — só alcançável via funções SECURITY DEFINER.
-- ---------------------------------------------------------------------
CREATE TABLE public.pricing_admin_action_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  action text NOT NULL,
  entity_type text NOT NULL,
  entity_id uuid NOT NULL,
  metadata jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pricing_admin_action_log_entity_type_check
    CHECK (entity_type IN ('PRICING_SOURCE')),
  CONSTRAINT pricing_admin_action_log_action_check
    CHECK (action IN ('PRICING_REFRESH_FREQUENCY_CHANGED')),
  CONSTRAINT pricing_admin_action_log_action_entity_match_check
    CHECK (
      (action = 'PRICING_REFRESH_FREQUENCY_CHANGED' AND entity_type = 'PRICING_SOURCE')
    )
);

CREATE INDEX pricing_admin_action_log_created_at_idx
  ON public.pricing_admin_action_log (created_at DESC);

ALTER TABLE public.pricing_admin_action_log ENABLE ROW LEVEL SECURITY;
-- Nenhuma policy, nenhum GRANT direto — igual a catalog_admin_action_log.
-- Único caminho de escrita: admin_set_pricing_refresh_frequency()
-- (SECURITY DEFINER, roda como dono da tabela).

-- ---------------------------------------------------------------------
-- 2) pricing_refresh_policy — configuração admin-only da frequência de
--    refresh por pricing_source. Separada de pricing_set_refresh_state
--    para não misturar configuração com estado operacional.
-- ---------------------------------------------------------------------
CREATE TABLE public.pricing_refresh_policy (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pricing_source_id uuid NOT NULL UNIQUE REFERENCES public.pricing_source(id) ON DELETE CASCADE,
  frequency_days integer NOT NULL CHECK (frequency_days IN (1, 2, 3, 5)),
  updated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_pricing_refresh_policy_set_updated_at
  BEFORE UPDATE ON public.pricing_refresh_policy
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.pricing_refresh_policy ENABLE ROW LEVEL SECURITY;
-- Nenhuma policy — leitura só via service_role (dispatcher) ou RPC admin
-- SECURITY DEFINER (UI de Pricing Admin).
GRANT SELECT ON public.pricing_refresh_policy TO service_role;

-- ---------------------------------------------------------------------
-- 3) Seed — JUSTTCG começa em 1 dia (mesmo comportamento efetivo já em
--    produção antes desta migration)
-- ---------------------------------------------------------------------
INSERT INTO public.pricing_refresh_policy (pricing_source_id, frequency_days)
SELECT id, 1
FROM public.pricing_source
WHERE code = 'JUSTTCG'
ON CONFLICT (pricing_source_id) DO NOTHING;

-- ---------------------------------------------------------------------
-- 4) admin_set_pricing_refresh_frequency() — grava a frequência de uma
--    pricing_source (admin-only, upsert + auditoria, no-op guard).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_set_pricing_refresh_frequency(
  p_pricing_source_id uuid,
  p_frequency_days integer
)
RETURNS TABLE(pricing_source_id uuid, frequency_days integer, updated_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_old_frequency_days integer;
  v_source_exists boolean;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'ADMIN_SET_PRICING_REFRESH_FREQUENCY_FORBIDDEN: acesso restrito a administradores.';
  END IF;

  IF p_pricing_source_id IS NULL THEN
    RAISE EXCEPTION 'ADMIN_SET_PRICING_REFRESH_FREQUENCY_MISSING_SOURCE: p_pricing_source_id é obrigatório.';
  END IF;

  IF p_frequency_days IS NULL OR p_frequency_days NOT IN (1, 2, 3, 5) THEN
    RAISE EXCEPTION 'ADMIN_SET_PRICING_REFRESH_FREQUENCY_INVALID_VALUE: frequência deve ser 1, 2, 3 ou 5 dias (recebido: %).', p_frequency_days;
  END IF;

  SELECT EXISTS (SELECT 1 FROM public.pricing_source ps WHERE ps.id = p_pricing_source_id)
    INTO v_source_exists;

  IF NOT v_source_exists THEN
    RAISE EXCEPTION 'ADMIN_SET_PRICING_REFRESH_FREQUENCY_SOURCE_NOT_FOUND: nenhuma pricing_source encontrada para o id informado (%).', p_pricing_source_id;
  END IF;

  SELECT prp.frequency_days INTO v_old_frequency_days
  FROM public.pricing_refresh_policy prp
  WHERE prp.pricing_source_id = p_pricing_source_id
  FOR UPDATE;

  IF v_old_frequency_days IS NOT DISTINCT FROM p_frequency_days THEN
    -- No-op: mesma frequência, não gera update nem entrada de auditoria.
    NULL;
  ELSE
    INSERT INTO public.pricing_refresh_policy (pricing_source_id, frequency_days, updated_by)
    VALUES (p_pricing_source_id, p_frequency_days, auth.uid())
    ON CONFLICT (pricing_source_id)
    DO UPDATE SET
      frequency_days = EXCLUDED.frequency_days,
      updated_by = EXCLUDED.updated_by;

    INSERT INTO public.pricing_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
    VALUES (
      auth.uid(),
      'PRICING_REFRESH_FREQUENCY_CHANGED',
      'PRICING_SOURCE',
      p_pricing_source_id,
      jsonb_build_object('old_frequency_days', v_old_frequency_days, 'new_frequency_days', p_frequency_days)
    );
  END IF;

  RETURN QUERY
  SELECT prp.pricing_source_id, prp.frequency_days, prp.updated_at
  FROM public.pricing_refresh_policy prp
  WHERE prp.pricing_source_id = p_pricing_source_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_set_pricing_refresh_frequency(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_pricing_refresh_frequency(uuid, integer) TO authenticated;

-- ---------------------------------------------------------------------
-- 5) get_pricing_refresh_policy() — leitura admin-only de todas as
--    pricing_source com a frequência configurada (fallback 1 dia).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_pricing_refresh_policy()
RETURNS TABLE(
  pricing_source_id uuid,
  pricing_source_code text,
  pricing_source_name text,
  frequency_days integer,
  updated_at timestamptz,
  updated_by uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'GET_PRICING_REFRESH_POLICY_FORBIDDEN: acesso restrito a administradores.';
  END IF;

  RETURN QUERY
  SELECT
    ps.id,
    ps.code,
    ps.name,
    COALESCE(prp.frequency_days, 1) AS frequency_days,
    prp.updated_at,
    prp.updated_by
  FROM public.pricing_source ps
  LEFT JOIN public.pricing_refresh_policy prp ON prp.pricing_source_id = ps.id
  ORDER BY ps.source_order;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_pricing_refresh_policy() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_pricing_refresh_policy() TO authenticated;

-- ---------------------------------------------------------------------
-- 6) close_pricing_set_refresh_attempt() — alteração cirúrgica só no
--    branch SUCCESS: next_due_at passa a usar a frequência configurada
--    em pricing_refresh_policy (fallback 1 dia), em vez do intervalo
--    fixo anterior. SECURITY INVOKER e search_path='public','pg_temp'
--    preservados; todos os demais branches (AUTH_FAILURE,
--    SET_TERMINAL_ERROR, TRANSIENT_ERROR, BUDGET_STOPPED/DEADLINE_STOPPED,
--    RECONCILIATION_INCOMPLETE) permanecem verbatim.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.close_pricing_set_refresh_attempt(
  p_sync_run_id uuid,
  p_page_outcome text,
  p_run_status text,
  p_requests_made integer,
  p_rate_limit_hits integer DEFAULT 0,
  p_error_summary text DEFAULT NULL::text
)
RETURNS TABLE(final_outcome text, seen_count integer, expected_count integer)
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_state record;
  v_expected_count integer;
  v_seen_count integer;
  v_final_outcome text;
  v_frequency_days integer;
BEGIN
  -- [validação de p_page_outcome, UPDATE pricing_sync_run, SELECT v_state
  --  FOR UPDATE, branches AUTH_FAILURE / SET_TERMINAL_ERROR /
  --  TRANSIENT_ERROR / BUDGET_STOPPED|DEADLINE_STOPPED, cálculo de
  --  v_expected_count via pricing_source_card_identity/
  --  pricing_card_mapping/card/pricing_set_mapping — idênticos à versão
  --  anterior à migration 3937, sem alteração]

  v_seen_count := cardinality(v_state.cycle_seen_external_card_ids);

  IF v_expected_count = 0 OR v_seen_count >= v_expected_count THEN
    v_final_outcome := 'SUCCESS';

    SELECT COALESCE(prp.frequency_days, 1) INTO v_frequency_days
    FROM public.pricing_set_mapping psm
    LEFT JOIN public.pricing_refresh_policy prp ON prp.pricing_source_id = psm.pricing_source_id
    WHERE psm.id = v_state.pricing_set_mapping_id;

    UPDATE public.pricing_set_refresh_state
    SET
      lease_until = NULL,
      leased_by = NULL,
      resume_offset = 0,
      cycle_seen_external_card_ids = '{}',
      cycle_expected_card_count = NULL,
      attempt_count = 0,
      next_due_at = now() + make_interval(days => v_frequency_days),
      last_success_at = now(),
      last_outcome = 'SUCCESS',
      last_error_summary = NULL,
      last_sync_run_id = p_sync_run_id
    WHERE id = v_state.id;
  ELSE
    -- [branch RECONCILIATION_INCOMPLETE — idêntico à versão anterior]
    NULL;
  END IF;

  RETURN QUERY SELECT v_final_outcome, v_seen_count, v_expected_count;
END;
$function$;
