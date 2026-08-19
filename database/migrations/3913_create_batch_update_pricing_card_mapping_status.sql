-- Query 3913 — CONFIRMADO EXECUTADO (Incremento P14.3 — persistência em lotes).
-- Aplicada via Supabase MCP em 2026-08-19.
--
-- Função de UPDATE em lote (SECURITY INVOKER) para pricing_card_mapping.
--
-- Contexto: .upsert() do Supabase JS é inutilizável aqui — prova empírica direta (SQL
-- reproduzindo o INSERT...ON CONFLICT DO UPDATE que o PostgREST geraria) mostrou que a
-- cláusula SET gerada inclui TODAS as colunas do payload, inclusive as colunas de conflito
-- (card_id, pricing_source_id) — que nunca têm GRANT UPDATE (Query 3912, deliberadamente
-- restrita a 8 colunas) e cuja tentativa de SET falha com 42501, mesmo que o valor não
-- mude de fato. Esta função é a exceção estrutural pré-autorizada para esse caso: um lote
-- de promoção de mapeamentos (PENDING/NOT_FOUND -> CONFIRMED numa reexecução) que o
-- PostgREST não consegue expressar nativamente sem essa lacuna.
--
-- SECURITY INVOKER (nunca SECURITY DEFINER — instrução explícita): a função roda com o
-- privilégio real de quem a chama, então fica limitada exatamente pelas mesmas 8 colunas
-- já concedidas por GRANT UPDATE (Query 3912) — nunca um bypass de privilégio. A cláusula
-- SET nunca referencia id/card_id/pricing_source_id/created_at/updated_at: impossibilidade
-- estrutural, não apenas checagem de privilégio (mesmo padrão de planVariantProjection/
-- diagnoseExternalCoverage/logDryRunCardEvidence do P14.2.2 — "nunca ter a capacidade" é
-- preferível a depender só do GRANT como fronteira de segurança).
--
-- EXECUTE revogado de PUBLIC e concedido somente a service_role — nunca chamada por
-- anon/authenticated.
--
-- Testado transacionalmente (BEGIN/ROLLBACK) antes desta aplicação real: array vazio
-- (no-op); promoção real de uma linha PENDING existente do piloto BASE4
-- (b038ed74-cc52-4fd7-9d94-259f5b904a53) para CONFIRMED usando um admin_user real
-- (fe316458-49dd-44e1-aac0-f4b7604ef8f2) — card_id inalterado, trigger de updated_at
-- disparado corretamente, e a CHECK ck_pricing_card_mapping_confirmation_consistency
-- rejeitou corretamente uma tentativa com confirmed_by NULL. Nenhuma linha real alterada
-- durante o teste (ROLLBACK). Confirmado pós-aplicação via pg_proc: prosecdef=false
-- (SECURITY INVOKER), proacl = {postgres=X/postgres, service_role=X/postgres}.

CREATE FUNCTION public.batch_update_pricing_card_mapping_status(p_updates jsonb)
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
  RETURNING t.id, t.card_id;
END;
$function$;

COMMENT ON FUNCTION public.batch_update_pricing_card_mapping_status(jsonb) IS
  'P14.3 — UPDATE em lote de pricing_card_mapping (promoção PENDING/NOT_FOUND -> CONFIRMED em reexecução), SECURITY INVOKER, escreve somente as 8 colunas já concedidas por GRANT UPDATE (Query 3912). Nunca chamada por anon/authenticated. Ver Query 3913 e ADR-029/05f-pricing.md (P14.3).';

REVOKE ALL ON FUNCTION public.batch_update_pricing_card_mapping_status(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.batch_update_pricing_card_mapping_status(jsonb) TO service_role;
