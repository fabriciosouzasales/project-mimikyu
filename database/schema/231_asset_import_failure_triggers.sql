/*
Project Mimikyu
Query 231 - Asset Import Failure Triggers
Pré-requisito: Query 230.
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.normalize_asset_import_failure()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.failure_stage := UPPER(BTRIM(NEW.failure_stage));
    NEW.error_code := UPPER(BTRIM(NEW.error_code));
    NEW.error_message := BTRIM(NEW.error_message);
    NEW.external_card_id :=
        NULLIF(BTRIM(NEW.external_card_id), '');
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_asset_import_failure_normalize
BEFORE INSERT OR UPDATE
ON public.asset_import_failure
FOR EACH ROW
EXECUTE FUNCTION public.normalize_asset_import_failure();

CREATE OR REPLACE FUNCTION public.govern_asset_import_failure()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF NEW.id IS DISTINCT FROM OLD.id THEN
            RAISE EXCEPTION
                'asset_import_failure.id não pode ser alterado.';
        END IF;

        IF NEW.asset_import_run_id
           IS DISTINCT FROM OLD.asset_import_run_id THEN
            RAISE EXCEPTION
                'asset_import_failure.asset_import_run_id não pode ser alterado.';
        END IF;

        IF NEW.card_id IS DISTINCT FROM OLD.card_id THEN
            RAISE EXCEPTION
                'asset_import_failure.card_id não pode ser alterado.';
        END IF;

        IF NEW.failure_stage IS DISTINCT FROM OLD.failure_stage THEN
            RAISE EXCEPTION
                'asset_import_failure.failure_stage não pode ser alterado.';
        END IF;

        IF NEW.error_code IS DISTINCT FROM OLD.error_code THEN
            RAISE EXCEPTION
                'asset_import_failure.error_code não pode ser alterado.';
        END IF;

        IF NEW.attempt_count < OLD.attempt_count THEN
            RAISE EXCEPTION
                'asset_import_failure.attempt_count não pode ser reduzido.';
        END IF;
    END IF;

    IF NEW.is_resolved = TRUE THEN
        IF TG_OP = 'INSERT' THEN
            NEW.resolved_at :=
                COALESCE(NEW.resolved_at, CLOCK_TIMESTAMP());
        ELSIF OLD.is_resolved = FALSE THEN
            NEW.resolved_at :=
                COALESCE(NEW.resolved_at, CLOCK_TIMESTAMP());
        ELSIF NEW.resolved_at IS NULL THEN
            NEW.resolved_at := OLD.resolved_at;
        END IF;
    ELSE
        NEW.resolved_at := NULL;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_asset_import_failure_govern
BEFORE INSERT OR UPDATE
ON public.asset_import_failure
FOR EACH ROW
EXECUTE FUNCTION public.govern_asset_import_failure();

CREATE TRIGGER trg_asset_import_failure_set_updated_at
BEFORE UPDATE
ON public.asset_import_failure
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

DO $$
BEGIN
    IF to_regprocedure(
        'public.normalize_asset_import_failure()'
    ) IS NULL THEN
        RAISE EXCEPTION
            'Query 231 falhou: função de normalização ausente.';
    END IF;

    IF to_regprocedure(
        'public.govern_asset_import_failure()'
    ) IS NULL THEN
        RAISE EXCEPTION
            'Query 231 falhou: função de governança ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgrelid =
              'public.asset_import_failure'::REGCLASS
          AND tgname =
              'trg_asset_import_failure_normalize'
          AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION
            'Query 231 falhou: trigger de normalização ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgrelid =
              'public.asset_import_failure'::REGCLASS
          AND tgname =
              'trg_asset_import_failure_govern'
          AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION
            'Query 231 falhou: trigger de governança ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgrelid =
              'public.asset_import_failure'::REGCLASS
          AND tgname =
              'trg_asset_import_failure_set_updated_at'
          AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION
            'Query 231 falhou: trigger de updated_at ausente.';
    END IF;

    RAISE NOTICE
        'QUERY 231 CONCLUÍDA: ASSET IMPORT FAILURE TRIGGERS CRIADOS';
END;
$$;

COMMIT;
