/*
Project Mimikyu
Query 985 - Validate Asset Source
Pré-requisitos: Queries 200, 201 e 900.
*/

BEGIN;

DO $$
DECLARE
    missing_columns TEXT;
    missing_sources TEXT;
BEGIN
    IF to_regclass('public.asset_source') IS NULL THEN
        RAISE EXCEPTION
            'Query 985 falhou: public.asset_source não existe.';
    END IF;

    SELECT STRING_AGG(required_column, ', ')
    INTO missing_columns
    FROM (
        VALUES
            ('id'),
            ('code'),
            ('name'),
            ('source_type'),
            ('base_url'),
            ('api_base_url'),
            ('documentation_url'),
            ('terms_url'),
            ('attribution_text'),
            ('supports_api'),
            ('supports_bulk_download'),
            ('is_active'),
            ('source_order'),
            ('created_at'),
            ('updated_at')
    ) required(required_column)
    WHERE NOT EXISTS (
        SELECT 1
        FROM information_schema.columns column_data
        WHERE column_data.table_schema = 'public'
          AND column_data.table_name = 'asset_source'
          AND column_data.column_name = required.required_column
    );

    IF missing_columns IS NOT NULL THEN
        RAISE EXCEPTION
            'Query 985 falhou. Colunas ausentes: %',
            missing_columns;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'public.asset_source'::regclass
          AND contype = 'p'
    ) THEN
        RAISE EXCEPTION
            'Query 985 falhou: primary key ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'public.asset_source'::regclass
          AND conname = 'uq_asset_source_code'
          AND contype = 'u'
    ) THEN
        RAISE EXCEPTION
            'Query 985 falhou: uq_asset_source_code ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'public.asset_source'::regclass
          AND conname = 'uq_asset_source_order'
          AND contype = 'u'
    ) THEN
        RAISE EXCEPTION
            'Query 985 falhou: uq_asset_source_order ausente.';
    END IF;

    IF to_regclass('public.ix_asset_source_active_order') IS NULL THEN
        RAISE EXCEPTION
            'Query 985 falhou: ix_asset_source_active_order ausente.';
    END IF;

    IF to_regclass('public.ix_asset_source_type') IS NULL THEN
        RAISE EXCEPTION
            'Query 985 falhou: ix_asset_source_type ausente.';
    END IF;

    IF to_regprocedure('public.normalize_asset_source()') IS NULL THEN
        RAISE EXCEPTION
            'Query 985 falhou: normalize_asset_source() ausente.';
    END IF;

    IF to_regprocedure('public.protect_asset_source_identity()') IS NULL THEN
        RAISE EXCEPTION
            'Query 985 falhou: protect_asset_source_identity() ausente.';
    END IF;

    IF to_regprocedure('public.set_updated_at()') IS NULL THEN
        RAISE EXCEPTION
            'Query 985 falhou: set_updated_at() ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgrelid = 'public.asset_source'::regclass
          AND tgname = 'trg_asset_source_normalize'
          AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION
            'Query 985 falhou: trg_asset_source_normalize ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgrelid = 'public.asset_source'::regclass
          AND tgname = 'trg_asset_source_set_updated_at'
          AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION
            'Query 985 falhou: trg_asset_source_set_updated_at ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgrelid = 'public.asset_source'::regclass
          AND tgname = 'trg_asset_source_protect_identity'
          AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION
            'Query 985 falhou: trg_asset_source_protect_identity ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_class
        WHERE oid = 'public.asset_source'::regclass
          AND relrowsecurity = TRUE
    ) THEN
        RAISE EXCEPTION
            'Query 985 falhou: RLS não está habilitado.';
    END IF;

    SELECT STRING_AGG(required_code, ', ')
    INTO missing_sources
    FROM (
        VALUES
            ('POKEMON_TCG_API'),
            ('TCGDEX'),
            ('MANUAL')
    ) required(required_code)
    WHERE NOT EXISTS (
        SELECT 1
        FROM public.asset_source source
        WHERE source.code = required.required_code
    );

    IF missing_sources IS NOT NULL THEN
        RAISE EXCEPTION
            'Query 985 falhou. Fontes ausentes: %',
            missing_sources;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.asset_source
        WHERE code <> UPPER(BTRIM(code))
           OR code !~ '^[A-Z][A-Z0-9_]*$'
           OR BTRIM(name) = ''
           OR source_type NOT IN ('API', 'DATASET', 'MANUAL')
           OR source_order <= 0
    ) THEN
        RAISE EXCEPTION
            'Query 985 falhou: registros inválidos em asset_source.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.asset_source
        WHERE supports_api = TRUE
          AND api_base_url IS NULL
    ) THEN
        RAISE EXCEPTION
            'Query 985 falhou: fonte com API sem api_base_url.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.asset_source
        WHERE source_type = 'MANUAL'
          AND (
              supports_api = TRUE
              OR supports_bulk_download = TRUE
          )
    ) THEN
        RAISE EXCEPTION
            'Query 985 falhou: configuração MANUAL inválida.';
    END IF;

    IF EXISTS (
        SELECT code
        FROM public.asset_source
        GROUP BY code
        HAVING COUNT(*) > 1
    ) THEN
        RAISE EXCEPTION
            'Query 985 falhou: códigos duplicados.';
    END IF;

    IF EXISTS (
        SELECT source_order
        FROM public.asset_source
        GROUP BY source_order
        HAVING COUNT(*) > 1
    ) THEN
        RAISE EXCEPTION
            'Query 985 falhou: ordens duplicadas.';
    END IF;

    RAISE NOTICE
        'QUERY 985 CONCLUÍDA: ASSET SOURCE VALIDADA';
END;
$$;

COMMIT;
