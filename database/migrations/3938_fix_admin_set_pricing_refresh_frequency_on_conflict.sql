-- Query 3938 — Corrigir ON CONFLICT ambíguo em admin_set_pricing_refresh_frequency()
-- Status: CONFIRMADO EXECUTADO em 2026-08-22 (Supabase MCP, projeto qjfutqujxrbzgrtkpgkg)
--
-- Objetivo: corrigir cirurgicamente o único defeito encontrado na
-- validação funcional pós-aplicação da migration 3937 (item 6 dos 10
-- pedidos por Fabrício: "1→3 gera exatamente 1 alteração + 1 audit log").
--
-- Diagnóstico: RETURNS TABLE(pricing_source_id uuid, frequency_days
-- integer, updated_at timestamptz) declara essas três colunas como
-- variáveis de saída implícitas do PL/pgSQL, acessíveis por nome puro em
-- todo o corpo da função — inclusive dentro de comandos SQL. O comando
-- INSERT ... ON CONFLICT (pricing_source_id) exige um nome de coluna
-- puro como alvo do conflito, e colidiu com a variável de saída
-- homônima, gerando "42702: column reference pricing_source_id is
-- ambiguous" em toda tentativa de mudança real de frequência (o caminho
-- no-op, que não executa o INSERT, funcionava normalmente e mascarou o
-- defeito até a primeira mudança de valor real ser testada). Confirmado
-- atômico/sem corrupção: a tentativa que falhou não alterou
-- frequency_days nem gerou linha de auditoria.
--
-- Correção mandatada por Fabrício: em vez do pragma genérico
-- #variable_conflict use_column, apontar o conflito pelo nome real da
-- constraint (não pela lista de colunas), confirmado via pg_constraint:
--   SELECT conname, contype, pg_get_constraintdef(oid)
--   FROM pg_constraint WHERE conrelid = 'public.pricing_refresh_policy'::regclass;
--   -> pricing_refresh_policy_pricing_source_id_key (UNIQUE, pricing_source_id)
-- Substituído "ON CONFLICT (pricing_source_id)" por
-- "ON CONFLICT ON CONSTRAINT pricing_refresh_policy_pricing_source_id_key".
-- Restante da função idêntico à migration 3937 — nenhuma outra mudança.
--
-- Resultado confirmado pós-execução (revalidação completa dos 10 itens
-- pedidos por Fabrício):
--   1→1 (no-op): zero update, zero audit log (comportamento preservado)
--   1→3 (mudança real): 1 update em pricing_refresh_policy, 1 linha nova
--     em pricing_admin_action_log com old_frequency_days=1/new=3
--   3→1 (retorno ao valor original, também auditado): 1 update, 1 linha
--     nova de auditoria — JUSTTCG termina novamente em frequency_days=1
--   close_pricing_set_refresh_attempt em SUCCESS, como service_role,
--     calcula next_due_at corretamente a partir da policy configurada
--   branches de backoff (AUTH_FAILURE/SET_TERMINAL_ERROR/TRANSIENT_ERROR/
--     BUDGET_STOPPED|DEADLINE_STOPPED/RECONCILIATION_INCOMPLETE): inalterados
--   zero novo advisory de segurança de classe nova (confirmado via
--     get_advisors: apenas os mesmos WARN authenticated_security_definer_
--     function_executable já aceitos para dezenas de admin_*/get_* pré-
--     existentes, e rls_enabled_no_policy já esperado para as 2 tabelas
--     novas da 3937)
--   cron/dispatcher (justtcg-price-refresh-set-dispatcher, */5 * * * *) e
--     pricing_set_refresh_state: nenhuma alteração

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
    NULL;
  ELSE
    INSERT INTO public.pricing_refresh_policy (pricing_source_id, frequency_days, updated_by)
    VALUES (p_pricing_source_id, p_frequency_days, auth.uid())
    ON CONFLICT ON CONSTRAINT pricing_refresh_policy_pricing_source_id_key
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
