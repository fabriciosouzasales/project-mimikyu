/*
Project Mimikyu
Query 990 - Validate Card External Reference
Pré-requisitos: Queries 210 e 211.
*/

BEGIN;

DO $$
DECLARE
    missing_columns TEXT;
BEGIN
    IF to_regclass('public.card_external_reference') IS NULL THEN
        RAISE EXCEPTION
            'Query 990 falhou: public.card_external_reference não existe.';
    END IF;

    SELECT STRING_AGG(required_column, ', ')
    INTO missing_columns
    FROM (
        VALUES
            ('id'),
            ('card_id'),
            ('asset_source_id'),
            ('external_card_id'),
            ('external_set_id'),
            ('source_number'),
            ('source_url'),
            ('image_source_url'),
            ('metadata'),
            ('is_active'),
            ('created_at'),
            ('updated_at')
    ) required(required_column)
    WHERE NOT EXISTS (
        SELECT 1
        FROM information_schema.columns column_data
        WHERE column_data.table_schema = 'public'
          AND column_data.table_name = 'card_external_reference'
          AND column_data.column_name = required.required_column
    );

    IF missing_columns IS NOT NULL THEN
        RAISE EXCEPTION
            'Query 990 falhou. Colunas ausentes: %',
            missing_columns;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'public.card_external_reference'::regclass
          AND contype = 'p'
    ) THEN
        RAISE EXCEPTION
            'Query 990 falhou: primary key ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'public.card_external_reference'::regclass
          AND conname = 'fk_card_external_reference_card'
          AND contype = 'f'
    ) THEN
        RAISE EXCEPTION
            'Query 990 falhou: FK para card ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'public.card_external_reference'::regclass
          AND conname = 'fk_card_external_reference_asset_source'
          AND contype = 'f'
    ) THEN
        RAISE EXCEPTION
            'Query 990 falhou: FK para asset_source ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'public.card_external_reference'::regclass
          AND conname = 'uq_card_external_reference_card_source'
          AND contype = 'u'
    ) THEN
        RAISE EXCEPTION
            'Query 990 falhou: unicidade card/source ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'public.card_external_reference'::regclass
          AND conname = 'uq_card_external_reference_source_external'
          AND contype = 'u'
    ) THEN
        RAISE EXCEPTION
            'Query 990 falhou: unicidade source/external ausente.';
    END IF;

    IF to_regclass(
        'public.ix_card_external_reference_card'
    ) IS NULL THEN
        RAISE EXCEPTION
            'Query 990 falhou: índice por card ausente.';
    END IF;

    IF to_regclass(
        'public.ix_card_external_reference_asset_source'
    ) IS NULL THEN
        RAISE EXCEPTION
            'Query 990 falhou: índice por fonte ausente.';
    END IF;

    IF to_regclass(
        'public.ix_card_external_reference_external_set'
    ) IS NULL THEN
        RAISE EXCEPTION
            'Query 990 falhou: índice por coleção externa ausente.';
    END IF;

    IF to_regclass(
        'public.ix_card_external_reference_source_number'
    ) IS NULL THEN
        RAISE EXCEPTION
            'Query 990 falhou: índice por número externo ausente.';
    END IF;

    IF to_regclass(
        'public.ix_card_external_reference_active'
    ) IS NULL THEN
        RAISE EXCEPTION
            'Query 990 falhou: índice de registros ativos ausente.';
    END IF;

    IF to_regprocedure(
        'public.normalize_card_external_reference()'
    ) IS NULL THEN
        RAISE EXCEPTION
            'Query 990 falhou: função de normalização ausente.';
    END IF;

    IF to_regprocedure(
        'public.protect_card_external_reference_identity()'
    ) IS NULL THEN
        RAISE EXCEPTION
            'Query 990 falhou: função de proteção ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgrelid = 'public.card_external_reference'::regclass
          AND tgname = 'trg_card_external_reference_normalize'
          AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION
            'Query 990 falhou: trigger de normalização ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgrelid = 'public.card_external_reference'::regclass
          AND tgname = 'trg_card_external_reference_set_updated_at'
          AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION
            'Query 990 falhou: trigger de updated_at ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgrelid = 'public.card_external_reference'::regclass
          AND tgname = 'trg_card_external_reference_protect_identity'
          AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION
            'Query 990 falhou: trigger de proteção ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_class
        WHERE oid = 'public.card_external_reference'::regclass
          AND relrowsecurity = TRUE
    ) THEN
        RAISE EXCEPTION
            'Query 990 falhou: RLS não habilitado.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.card_external_reference
        WHERE BTRIM(external_card_id) = ''
           OR JSONB_TYPEOF(metadata) <> 'object'
           OR (
               source_url IS NOT NULL
               AND source_url !~* '^https://'
           )
           OR (
               image_source_url IS NOT NULL
               AND image_source_url !~* '^https://'
           )
    ) THEN
        RAISE EXCEPTION
            'Query 990 falhou: registros inválidos encontrados.';
    END IF;

    IF EXISTS (
        SELECT card_id, asset_source_id
        FROM public.card_external_reference
        GROUP BY card_id, asset_source_id
        HAVING COUNT(*) > 1
    ) THEN
        RAISE EXCEPTION
            'Query 990 falhou: duplicidade por carta e fonte.';
    END IF;

    IF EXISTS (
        SELECT asset_source_id, external_card_id
        FROM public.card_external_reference
        GROUP BY asset_source_id, external_card_id
        HAVING COUNT(*) > 1
    ) THEN
        RAISE EXCEPTION
            'Query 990 falhou: identificador externo duplicado.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.card_external_reference reference_data
        LEFT JOIN public.card card_data
          ON card_data.id = reference_data.card_id
        WHERE card_data.id IS NULL
    ) THEN
        RAISE EXCEPTION
            'Query 990 falhou: referência para carta inexistente.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.card_external_reference reference_data
        LEFT JOIN public.asset_source source_data
          ON source_data.id = reference_data.asset_source_id
        WHERE source_data.id IS NULL
    ) THEN
        RAISE EXCEPTION
            'Query 990 falhou: referência para fonte inexistente.';
    END IF;

    RAISE NOTICE
        'QUERY 990 CONCLUÍDA: CARD EXTERNAL REFERENCE VALIDADA';
END;
$$;

COMMIT;
