/*
Project Mimikyu
Query 220 - Create Asset Import Run
Pré-requisitos: Asset Source, Card Set e Language.
*/

BEGIN;

DO $$
BEGIN
    IF to_regclass('public.asset_source') IS NULL THEN
        RAISE EXCEPTION
            'Query 220 interrompida: public.asset_source não existe.';
    END IF;

    IF to_regclass('public.card_set') IS NULL THEN
        RAISE EXCEPTION
            'Query 220 interrompida: public.card_set não existe.';
    END IF;

    IF to_regclass('public.language') IS NULL THEN
        RAISE EXCEPTION
            'Query 220 interrompida: public.language não existe.';
    END IF;

    IF to_regclass('public.asset_import_run') IS NOT NULL THEN
        RAISE EXCEPTION
            'Query 220 interrompida: public.asset_import_run já existe.';
    END IF;

    IF to_regclass('public.asset_import_run_code_seq') IS NOT NULL THEN
        RAISE EXCEPTION
            'Query 220 interrompida: sequência de códigos já existe.';
    END IF;
END;
$$;

CREATE SEQUENCE public.asset_import_run_code_seq
    AS BIGINT
    START WITH 1
    INCREMENT BY 1
    MINVALUE 1
    NO MAXVALUE
    CACHE 20;

CREATE TABLE public.asset_import_run
(
    id UUID
        PRIMARY KEY
        DEFAULT gen_random_uuid(),

    run_code TEXT
        NOT NULL
        DEFAULT (
            'RUN-' ||
            TO_CHAR(CLOCK_TIMESTAMP(), 'YYYYMMDD') ||
            '-' ||
            LPAD(
                NEXTVAL(
                    'public.asset_import_run_code_seq'::REGCLASS
                )::TEXT,
                8,
                '0'
            )
        ),

    asset_source_id UUID
        NOT NULL,
    card_set_id UUID,
    language_id UUID,

    run_type TEXT
        NOT NULL,
    status TEXT
        NOT NULL
        DEFAULT 'PENDING',
    execution_context TEXT
        NOT NULL
        DEFAULT 'MANUAL',
    initiated_by TEXT,

    requested_count INTEGER
        NOT NULL
        DEFAULT 0,
    processed_count INTEGER
        NOT NULL
        DEFAULT 0,
    success_count INTEGER
        NOT NULL
        DEFAULT 0,
    failed_count INTEGER
        NOT NULL
        DEFAULT 0,
    skipped_count INTEGER
        NOT NULL
        DEFAULT 0,

    parameters JSONB
        NOT NULL
        DEFAULT '{}'::JSONB,
    error_summary TEXT,

    started_at TIMESTAMPTZ,
    finished_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ
        NOT NULL
        DEFAULT NOW(),
    updated_at TIMESTAMPTZ
        NOT NULL
        DEFAULT NOW(),

    CONSTRAINT fk_asset_import_run_asset_source
        FOREIGN KEY (asset_source_id)
        REFERENCES public.asset_source (id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_asset_import_run_card_set
        FOREIGN KEY (card_set_id)
        REFERENCES public.card_set (id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_asset_import_run_language
        FOREIGN KEY (language_id)
        REFERENCES public.language (id)
        ON DELETE RESTRICT,

    CONSTRAINT uq_asset_import_run_code
        UNIQUE (run_code),

    CONSTRAINT ck_asset_import_run_code
        CHECK (
            run_code ~ '^RUN-[0-9]{8}-[0-9]{8,}$'
        ),
    CONSTRAINT ck_asset_import_run_type
        CHECK (
            run_type IN (
                'MISSING_ONLY',
                'REFRESH_EXISTING',
                'RETRY_FAILURES',
                'SINGLE_CARD',
                'FULL_CARD_SET'
            )
        ),
    CONSTRAINT ck_asset_import_run_status
        CHECK (
            status IN (
                'PENDING',
                'RUNNING',
                'COMPLETED',
                'COMPLETED_WITH_ERRORS',
                'FAILED',
                'CANCELLED'
            )
        ),
    CONSTRAINT ck_asset_import_run_execution_context
        CHECK (
            execution_context IN (
                'MANUAL',
                'SCHEDULED',
                'API',
                'SYSTEM'
            )
        ),
    CONSTRAINT ck_asset_import_run_initiated_by
        CHECK (
            initiated_by IS NULL
            OR BTRIM(initiated_by) <> ''
        ),
    CONSTRAINT ck_asset_import_run_counts
        CHECK (
            requested_count >= 0
            AND processed_count >= 0
            AND success_count >= 0
            AND failed_count >= 0
            AND skipped_count >= 0
        ),
    CONSTRAINT ck_asset_import_run_processed_count
        CHECK (
            requested_count = 0
            OR processed_count <= requested_count
        ),
    CONSTRAINT ck_asset_import_run_result_counts
        CHECK (
            success_count +
            failed_count +
            skipped_count
            <= processed_count
        ),
    CONSTRAINT ck_asset_import_run_parameters
        CHECK (
            JSONB_TYPEOF(parameters) = 'object'
        ),
    CONSTRAINT ck_asset_import_run_period
        CHECK (
            finished_at IS NULL
            OR started_at IS NULL
            OR finished_at >= started_at
        )
);

ALTER SEQUENCE public.asset_import_run_code_seq
    OWNED BY public.asset_import_run.run_code;

CREATE INDEX ix_asset_import_run_status
    ON public.asset_import_run (
        status,
        created_at DESC
    );

CREATE INDEX ix_asset_import_run_source
    ON public.asset_import_run (
        asset_source_id,
        created_at DESC
    );

CREATE INDEX ix_asset_import_run_card_set_language
    ON public.asset_import_run (
        card_set_id,
        language_id,
        created_at DESC
    )
    WHERE card_set_id IS NOT NULL;

CREATE INDEX ix_asset_import_run_active
    ON public.asset_import_run (
        created_at DESC
    )
    WHERE status IN ('PENDING', 'RUNNING');

CREATE INDEX ix_asset_import_run_finished
    ON public.asset_import_run (
        finished_at DESC
    )
    WHERE finished_at IS NOT NULL;

ALTER TABLE public.asset_import_run
    ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF to_regclass('public.asset_import_run') IS NULL THEN
        RAISE EXCEPTION
            'Query 220 falhou: tabela não criada.';
    END IF;

    IF to_regclass('public.asset_import_run_code_seq') IS NULL THEN
        RAISE EXCEPTION
            'Query 220 falhou: sequência não criada.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'public.asset_import_run'::REGCLASS
          AND conname = 'fk_asset_import_run_asset_source'
          AND contype = 'f'
    ) THEN
        RAISE EXCEPTION
            'Query 220 falhou: FK para asset_source ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'public.asset_import_run'::REGCLASS
          AND conname = 'fk_asset_import_run_card_set'
          AND contype = 'f'
    ) THEN
        RAISE EXCEPTION
            'Query 220 falhou: FK para card_set ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'public.asset_import_run'::REGCLASS
          AND conname = 'fk_asset_import_run_language'
          AND contype = 'f'
    ) THEN
        RAISE EXCEPTION
            'Query 220 falhou: FK para language ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_class
        WHERE oid = 'public.asset_import_run'::REGCLASS
          AND relrowsecurity = TRUE
    ) THEN
        RAISE EXCEPTION
            'Query 220 falhou: RLS não habilitado.';
    END IF;

    RAISE NOTICE
        'QUERY 220 CONCLUÍDA: ASSET IMPORT RUN CRIADA';
END;
$$;

COMMIT;
