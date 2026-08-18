-- Query 3906 — CONFIRMADO EXECUTADO (Incremento P13.1 — Fundação de Orquestração Programada
-- de Pricing, 2026-08-18). Aplicada originalmente via Supabase MCP no mesmo dia; versionada
-- retroativamente durante a auditoria final do P13.1 (ver nota de proveniência em 3905).
--
-- Contexto: confirmed_by era NOT NULL, incompatível com execuções SCHEDULED (sem nenhum
-- administrador confirmando manualmente). Nenhum administrador sintético é criado em
-- admin_user — em vez disso, confirmed_by passa a aceitar NULL, com uma regra correlacionada
-- que torna MANUAL e SCHEDULED mutuamente exclusivos quanto à exigência de admin real. A
-- função de validação (existente desde a correção pós-P8, Query 3083) é recriada via
-- CREATE OR REPLACE — mesma assinatura, mesmo SECURITY DEFINER/search_path='', EXECUTE
-- continua revogado de todos os papéis — para só consultar admin_user quando o valor não for
-- NULL (sempre dispensável em SCHEDULED, garantido pelo CHECK abaixo).

-- 1. confirmed_by deixa de ser NOT NULL
ALTER TABLE public.pricing_sync_run
  ALTER COLUMN confirmed_by DROP NOT NULL;

-- 2. Regra correlacionada: MANUAL sempre com confirmed_by; SCHEDULED sempre sem confirmed_by
ALTER TABLE public.pricing_sync_run
  ADD CONSTRAINT ck_pricing_sync_run_confirmed_by_by_trigger
  CHECK (
    (triggered_by = 'MANUAL' AND confirmed_by IS NOT NULL)
    OR
    (triggered_by = 'SCHEDULED' AND confirmed_by IS NULL)
  );

-- 3. Trigger de validação passa a só consultar admin_user quando confirmed_by não for NULL
--    (mesma função, mesma assinatura, mesmo search_path='' / SECURITY DEFINER já vigentes —
--    CREATE OR REPLACE preserva REVOKE EXECUTE já aplicado a PUBLIC/anon/authenticated/service_role)
CREATE OR REPLACE FUNCTION public.validate_pricing_sync_run_confirmed_by()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF NEW.confirmed_by IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.admin_user WHERE id = NEW.confirmed_by
        ) THEN
            RAISE EXCEPTION 'PRICING_SYNC_RUN_CONFIRMED_BY_INVALID';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;
