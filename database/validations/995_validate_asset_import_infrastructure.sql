/*
Project Mimikyu
Query 995 - Validate Asset Import Infrastructure
Pré-requisitos: Queries 220, 221, 230 e 231.
*/

BEGIN;

DO $$
DECLARE
    missing_columns TEXT;
BEGIN
    ----------------------------------------------------------------------------
    -- asset_import_run
    ----------------------------------------------------------------------------
    IF to_regclass('public.asset_import_run') IS NULL THEN
        RAISE EXCEPTION
            'Query 995 falhou: asset_import_run não existe.';
    END IF;

    SELECT STRING_AGG(required_column, ', ')
    INTO missing_columns
    FROM (
        VALUES
            ('id'),
            ('run_code'),
            ('asset_source_id'),
            ('card_set_id'),
            ('language_id'),
            ('run_type'),
            ('status'),
            ('execution_context'),
            ('initiated_by'),
            ('requested_count'),
            ('processed_count'),
            ('success_count'),
            ('failed_count'),
            ('skipped_count'),
            ('parameters'),
            ('error_summary'),
            ('started_at'),
            ('finished_at'),
            ('created_at'),
            ('updated_at')
    ) required(required_column)
    WHERE NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema='public'
          AND table_name='asset_import_run'
          AND column_name=required.required_column
    );

    IF missing_columns IS NOT NULL THEN
        RAISE EXCEPTION
            'asset_import_run incompleta. Colunas: %',
            missing_columns;
    END IF;

    ----------------------------------------------------------------------------
    -- asset_import_failure
    ----------------------------------------------------------------------------
    SELECT STRING_AGG(required_column, ', ')
    INTO missing_columns
    FROM (
        VALUES
            ('id'),
            ('asset_import_run_id'),
            ('card_id'),
            ('failure_stage'),
            ('error_code'),
            ('error_message'),
            ('external_card_id'),
            ('attempt_count'),
            ('is_resolved'),
            ('resolved_at'),
            ('created_at'),
            ('updated_at')
    ) required(required_column)
    WHERE NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema='public'
          AND table_name='asset_import_failure'
          AND column_name=required.required_column
    );

    IF missing_columns IS NOT NULL THEN
        RAISE EXCEPTION
            'asset_import_failure incompleta. Colunas: %',
            missing_columns;
    END IF;

    ----------------------------------------------------------------------------
    -- Functions
    ----------------------------------------------------------------------------
    IF to_regprocedure('public.normalize_asset_import_run()') IS NULL THEN
        RAISE EXCEPTION
            'normalize_asset_import_run() ausente.';
    END IF;

    IF to_regprocedure('public.govern_asset_import_run()') IS NULL THEN
        RAISE EXCEPTION
            'govern_asset_import_run() ausente.';
    END IF;

    IF to_regprocedure('public.normalize_asset_import_failure()') IS NULL THEN
        RAISE EXCEPTION
            'normalize_asset_import_failure() ausente.';
    END IF;

    IF to_regprocedure('public.govern_asset_import_failure()') IS NULL THEN
        RAISE EXCEPTION
            'govern_asset_import_failure() ausente.';
    END IF;

    ----------------------------------------------------------------------------
    -- Triggers
    ----------------------------------------------------------------------------
    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgrelid='public.asset_import_run'::regclass
          AND tgname='trg_asset_import_run_normalize'
          AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION 'Trigger normalize asset_import_run ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgrelid='public.asset_import_run'::regclass
          AND tgname='trg_asset_import_run_govern'
          AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION 'Trigger govern asset_import_run ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgrelid='public.asset_import_run'::regclass
          AND tgname='trg_asset_import_run_set_updated_at'
          AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION 'Trigger updated_at asset_import_run ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgrelid='public.asset_import_failure'::regclass
          AND tgname='trg_asset_import_failure_normalize'
          AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION 'Trigger normalize asset_import_failure ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgrelid='public.asset_import_failure'::regclass
          AND tgname='trg_asset_import_failure_govern'
          AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION 'Trigger govern asset_import_failure ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgrelid='public.asset_import_failure'::regclass
          AND tgname='trg_asset_import_failure_set_updated_at'
          AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION 'Trigger updated_at asset_import_failure ausente.';
    END IF;

    ----------------------------------------------------------------------------
    -- RLS
    ----------------------------------------------------------------------------
    IF NOT EXISTS (
        SELECT 1
        FROM pg_class
        WHERE oid='public.asset_import_run'::regclass
          AND relrowsecurity = TRUE
    ) THEN
        RAISE EXCEPTION
            'RLS não habilitado em asset_import_run.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_class
        WHERE oid='public.asset_import_failure'::regclass
          AND relrowsecurity = TRUE
    ) THEN
        RAISE EXCEPTION
            'RLS não habilitado em asset_import_failure.';
    END IF;

    ----------------------------------------------------------------------------
    -- Integridade
    ----------------------------------------------------------------------------
    IF EXISTS (
        SELECT 1
        FROM public.asset_import_failure f
        LEFT JOIN public.asset_import_run r
            ON r.id = f.asset_import_run_id
        WHERE r.id IS NULL
    ) THEN
        RAISE EXCEPTION
            'Existem falhas sem execução.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.asset_import_failure f
        LEFT JOIN public.card c
            ON c.id = f.card_id
        WHERE c.id IS NULL
    ) THEN
        RAISE EXCEPTION
            'Existem falhas apontando para cartas inexistentes.';
    END IF;

    ----------------------------------------------------------------------------
    RAISE NOTICE
        'QUERY 995 CONCLUÍDA: ASSET IMPORT INFRASTRUCTURE VALIDADA';
END;
$$;

COMMIT;
