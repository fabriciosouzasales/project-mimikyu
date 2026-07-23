/*
Project Mimikyu
Query 221 - Asset Import Run Triggers
Pré-requisito: Query 220.
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.normalize_asset_import_run()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.run_code := UPPER(BTRIM(NEW.run_code));
    NEW.run_type := UPPER(BTRIM(NEW.run_type));
    NEW.status := UPPER(BTRIM(NEW.status));
    NEW.execution_context := UPPER(BTRIM(NEW.execution_context));
    NEW.initiated_by := NULLIF(BTRIM(NEW.initiated_by), '');
    NEW.error_summary := NULLIF(BTRIM(NEW.error_summary), '');
    IF NEW.parameters IS NULL THEN
        NEW.parameters := '{}'::JSONB;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_asset_import_run_normalize
BEFORE INSERT OR UPDATE
ON public.asset_import_run
FOR EACH ROW
EXECUTE FUNCTION public.normalize_asset_import_run();

CREATE OR REPLACE FUNCTION public.govern_asset_import_run()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    is_terminal BOOLEAN;
BEGIN
    is_terminal := NEW.status IN (
        'COMPLETED',
        'COMPLETED_WITH_ERRORS',
        'FAILED',
        'CANCELLED'
    );

    IF TG_OP = 'UPDATE' THEN
        IF NEW.id IS DISTINCT FROM OLD.id THEN
            RAISE EXCEPTION
                'asset_import_run.id não pode ser alterado.';
        END IF;

        IF NEW.run_code IS DISTINCT FROM OLD.run_code THEN
            RAISE EXCEPTION
                'asset_import_run.run_code não pode ser alterado.';
        END IF;

        IF OLD.status <> 'PENDING' AND (
            NEW.asset_source_id IS DISTINCT FROM OLD.asset_source_id
            OR NEW.card_set_id IS DISTINCT FROM OLD.card_set_id
            OR NEW.language_id IS DISTINCT FROM OLD.language_id
            OR NEW.run_type IS DISTINCT FROM OLD.run_type
            OR NEW.execution_context IS DISTINCT FROM OLD.execution_context
            OR NEW.initiated_by IS DISTINCT FROM OLD.initiated_by
            OR NEW.parameters IS DISTINCT FROM OLD.parameters
        ) THEN
            RAISE EXCEPTION
                'O escopo da importação não pode ser alterado após o início.';
        END IF;

        IF NEW.status IS DISTINCT FROM OLD.status THEN
            IF OLD.status = 'PENDING'
               AND NEW.status NOT IN (
                   'RUNNING',
                   'FAILED',
                   'CANCELLED'
               ) THEN
                RAISE EXCEPTION
                    'Transição inválida: PENDING para %.',
                    NEW.status;
            END IF;

            IF OLD.status = 'RUNNING'
               AND NEW.status NOT IN (
                   'COMPLETED',
                   'COMPLETED_WITH_ERRORS',
                   'FAILED',
                   'CANCELLED'
               ) THEN
                RAISE EXCEPTION
                    'Transição inválida: RUNNING para %.',
                    NEW.status;
            END IF;

            IF OLD.status IN (
                'COMPLETED',
                'COMPLETED_WITH_ERRORS',
                'FAILED',
                'CANCELLED'
            ) THEN
                RAISE EXCEPTION
                    'Execução encerrada não pode mudar de status.';
            END IF;
        END IF;
    END IF;

    IF NEW.status = 'PENDING' THEN
        NEW.started_at := NULL;
        NEW.finished_at := NULL;
    ELSIF NEW.status = 'RUNNING' THEN
        NEW.started_at := COALESCE(
            NEW.started_at,
            CLOCK_TIMESTAMP()
        );
        NEW.finished_at := NULL;
    ELSIF is_terminal THEN
        NEW.started_at := COALESCE(
            NEW.started_at,
            OLD.started_at,
            CLOCK_TIMESTAMP()
        );
        NEW.finished_at := COALESCE(
            NEW.finished_at,
            CLOCK_TIMESTAMP()
        );
    END IF;

    IF NEW.status = 'COMPLETED'
       AND NEW.failed_count <> 0 THEN
        RAISE EXCEPTION
            'COMPLETED exige failed_count igual a zero.';
    END IF;

    IF NEW.status = 'COMPLETED_WITH_ERRORS'
       AND NEW.failed_count = 0 THEN
        RAISE EXCEPTION
            'COMPLETED_WITH_ERRORS exige failed_count maior que zero.';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_asset_import_run_govern
BEFORE INSERT OR UPDATE
ON public.asset_import_run
FOR EACH ROW
EXECUTE FUNCTION public.govern_asset_import_run();

CREATE TRIGGER trg_asset_import_run_set_updated_at
BEFORE UPDATE
ON public.asset_import_run
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

DO $$
BEGIN
    IF to_regprocedure(
        'public.normalize_asset_import_run()'
    ) IS NULL THEN
        RAISE EXCEPTION
            'Query 221 falhou: função de normalização ausente.';
    END IF;

    IF to_regprocedure(
        'public.govern_asset_import_run()'
    ) IS NULL THEN
        RAISE EXCEPTION
            'Query 221 falhou: função de governança ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgrelid = 'public.asset_import_run'::REGCLASS
          AND tgname = 'trg_asset_import_run_normalize'
          AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION
            'Query 221 falhou: trigger de normalização ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgrelid = 'public.asset_import_run'::REGCLASS
          AND tgname = 'trg_asset_import_run_govern'
          AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION
            'Query 221 falhou: trigger de governança ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgrelid = 'public.asset_import_run'::REGCLASS
          AND tgname = 'trg_asset_import_run_set_updated_at'
          AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION
            'Query 221 falhou: trigger de updated_at ausente.';
    END IF;

    RAISE NOTICE
        'QUERY 221 CONCLUÍDA: ASSET IMPORT RUN TRIGGERS CRIADOS';
END;
$$;

COMMIT;
