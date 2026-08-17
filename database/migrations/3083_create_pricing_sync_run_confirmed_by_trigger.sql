-- ============================================================================
-- ARQUIVO RECONSTRUIDO RETROATIVAMENTE A PARTIR DO HISTORICO OFICIAL
-- (supabase_migrations.schema_migrations) -- nunca reexecutado; o SQL abaixo e
-- o statement armazenado, sem qualquer alteracao.
-- version: 20260817195138
-- Recuperado em: 2026-08-17
-- ============================================================================


-- Query 3083 — Validate confirmed_by via BEFORE INSERT trigger on pricing_sync_run
-- Objetivo: garantir que todo pricing_sync_run.confirmed_by referencie um admin_user
-- real, sem expor uma função RPC pública que aceite UUID arbitrário como parâmetro
-- (o ADR-021-administrative-role-model.md registra esse padrão como já avaliado e
-- rejeitado). A checagem roda como efeito colateral obrigatório do primeiro write do
-- piloto (INSERT em pricing_sync_run) — nunca como uma função chamável isoladamente.
-- service_role continua sem SELECT direto em admin_user (não alterado por esta Query).
-- Erro genérico (sem interpolar o UUID recebido) para não funcionar como oráculo de
-- enumeração de administradores.

CREATE OR REPLACE FUNCTION public.validate_pricing_sync_run_confirmed_by()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.admin_user WHERE id = NEW.confirmed_by
    ) THEN
        RAISE EXCEPTION 'PRICING_SYNC_RUN_CONFIRMED_BY_INVALID';
    END IF;
    RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public.validate_pricing_sync_run_confirmed_by() IS
    'Trigger BEFORE INSERT de pricing_sync_run: confirma que confirmed_by existe em admin_user. Nunca invocável diretamente (RETURNS TRIGGER + EXECUTE revogado de todos os papéis) — ver ADR-021-administrative-role-model.md e Query 3083, docs/log.md 2026-08-17.';

-- Defesa em profundidade: mesmo que RETURNS TRIGGER já impeça chamada direta via
-- SELECT, o EXECUTE é revogado explicitamente de todos os papéis, incluindo
-- service_role — nenhum papel deve conseguir invocar esta função fora do mecanismo
-- de trigger (o disparo do trigger em si não depende de EXECUTE do papel que faz o
-- INSERT na tabela).
REVOKE EXECUTE ON FUNCTION public.validate_pricing_sync_run_confirmed_by() FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER trg_pricing_sync_run_validate_confirmed_by
    BEFORE INSERT ON public.pricing_sync_run
    FOR EACH ROW
    EXECUTE FUNCTION public.validate_pricing_sync_run_confirmed_by();
