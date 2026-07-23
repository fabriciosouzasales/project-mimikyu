/*
Project Mimikyu
Query 230 - Create Asset Import Failure
Pré-requisitos: Queries 220 e 221.
*/

BEGIN;

DO $$
BEGIN
    IF to_regclass('public.asset_import_run') IS NULL THEN
        RAISE EXCEPTION
            'Query 230 interrompida: public.asset_import_run não existe.';
    END IF;

    IF to_regclass('public.card') IS NULL THEN
        RAISE EXCEPTION
            'Query 230 interrompida: public.card não existe.';
    END IF;

    IF to_regclass('public.asset_import_failure') IS NOT NULL THEN
        RAISE EXCEPTION
            'Query 230 interrompida: public.asset_import_failure já existe.';
    END IF;
END;
$$;

CREATE TABLE public.asset_import_failure
(
    id UUID
        PRIMARY KEY
        DEFAULT gen_random_uuid(),

    asset_import_run_id UUID
        NOT NULL,
    card_id UUID
        NOT NULL,

    failure_stage TEXT
        NOT NULL,
    error_code TEXT
        NOT NULL,
    error_message TEXT
        NOT NULL,
    external_card_id TEXT,

    attempt_count INTEGER
        NOT NULL
        DEFAULT 1,

    is_resolved BOOLEAN
        NOT NULL
        DEFAULT FALSE,
    resolved_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ
        NOT NULL
        DEFAULT NOW(),
    updated_at TIMESTAMPTZ
        NOT NULL
        DEFAULT NOW(),

    CONSTRAINT fk_asset_import_failure_run
        FOREIGN KEY (asset_import_run_id)
        REFERENCES public.asset_import_run (id)
        ON DELETE CASCADE,
    CONSTRAINT fk_asset_import_failure_card
        FOREIGN KEY (card_id)
        REFERENCES public.card (id)
        ON DELETE RESTRICT,

    CONSTRAINT uq_asset_import_failure_run_card_error
        UNIQUE (
            asset_import_run_id,
            card_id,
            failure_stage,
            error_code
        ),

    CONSTRAINT ck_asset_import_failure_stage
        CHECK (
            failure_stage IN (
                'REFERENCE_LOOKUP',
                'SOURCE_REQUEST',
                'DOWNLOAD',
                'VALIDATION',
                'TRANSFORMATION',
                'STORAGE_UPLOAD',
                'CARD_ASSET_WRITE'
            )
        ),
    CONSTRAINT ck_asset_import_failure_error_code
        CHECK (
            error_code ~ '^[A-Z][A-Z0-9_]*$'
        ),
    CONSTRAINT ck_asset_import_failure_error_message
        CHECK (
            BTRIM(error_message) <> ''
        ),
    CONSTRAINT ck_asset_import_failure_external_card_id
        CHECK (
            external_card_id IS NULL
            OR BTRIM(external_card_id) <> ''
        ),
    CONSTRAINT ck_asset_import_failure_attempt_count
        CHECK (
            attempt_count > 0
        ),
    CONSTRAINT ck_asset_import_failure_resolution
        CHECK (
            (
                is_resolved = FALSE
                AND resolved_at IS NULL
            )
            OR
            (
                is_resolved = TRUE
                AND resolved_at IS NOT NULL
            )
        )
);

CREATE INDEX ix_asset_import_failure_run
    ON public.asset_import_failure (
        asset_import_run_id,
        created_at DESC
    );

CREATE INDEX ix_asset_import_failure_card
    ON public.asset_import_failure (
        card_id,
        created_at DESC
    );

CREATE INDEX ix_asset_import_failure_stage_code
    ON public.asset_import_failure (
        failure_stage,
        error_code,
        created_at DESC
    );

CREATE INDEX ix_asset_import_failure_unresolved
    ON public.asset_import_failure (
        created_at,
        attempt_count
    )
    WHERE is_resolved = FALSE;

ALTER TABLE public.asset_import_failure
    ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF to_regclass('public.asset_import_failure') IS NULL THEN
        RAISE EXCEPTION
            'Query 230 falhou: tabela não criada.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid =
              'public.asset_import_failure'::REGCLASS
          AND contype = 'p'
    ) THEN
        RAISE EXCEPTION
            'Query 230 falhou: primary key ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid =
              'public.asset_import_failure'::REGCLASS
          AND conname = 'fk_asset_import_failure_run'
          AND contype = 'f'
    ) THEN
        RAISE EXCEPTION
            'Query 230 falhou: FK para asset_import_run ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid =
              'public.asset_import_failure'::REGCLASS
          AND conname = 'fk_asset_import_failure_card'
          AND contype = 'f'
    ) THEN
        RAISE EXCEPTION
            'Query 230 falhou: FK para card ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid =
              'public.asset_import_failure'::REGCLASS
          AND conname =
              'uq_asset_import_failure_run_card_error'
          AND contype = 'u'
    ) THEN
        RAISE EXCEPTION
            'Query 230 falhou: unicidade da falha ausente.';
    END IF;

    IF to_regclass(
        'public.ix_asset_import_failure_run'
    ) IS NULL THEN
        RAISE EXCEPTION
            'Query 230 falhou: índice por execução ausente.';
    END IF;

    IF to_regclass(
        'public.ix_asset_import_failure_card'
    ) IS NULL THEN
        RAISE EXCEPTION
            'Query 230 falhou: índice por carta ausente.';
    END IF;

    IF to_regclass(
        'public.ix_asset_import_failure_stage_code'
    ) IS NULL THEN
        RAISE EXCEPTION
            'Query 230 falhou: índice por etapa e erro ausente.';
    END IF;

    IF to_regclass(
        'public.ix_asset_import_failure_unresolved'
    ) IS NULL THEN
        RAISE EXCEPTION
            'Query 230 falhou: índice de falhas abertas ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_class
        WHERE oid =
              'public.asset_import_failure'::REGCLASS
          AND relrowsecurity = TRUE
    ) THEN
        RAISE EXCEPTION
            'Query 230 falhou: RLS não habilitado.';
    END IF;

    RAISE NOTICE
        'QUERY 230 CONCLUÍDA: ASSET IMPORT FAILURE CRIADA';
END;
$$;

COMMIT;
