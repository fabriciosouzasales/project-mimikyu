/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 980 - Validate Card Asset
Versão......: 2.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18

Descrição:
Homologa integralmente a arquitetura vigente da tabela public.card_asset após
a introdução dos catálogos Language e Storage Bucket.

A validação contempla:
- existência e estrutura das colunas essenciais;
- obrigatoriedade das colunas;
- defaults técnicos;
- primary key;
- foreign keys;
- unicidade lógica dos ativos;
- unicidade do ativo primário;
- índices essenciais;
- triggers e funções;
- Row Level Security;
- integridade dos registros existentes;
- coerência entre bucket, storage_path e external_url;
- consistência das referências aos catálogos.

Pré-requisitos:
- Query 170 - Create Card Asset Type
- Query 171 - Card Asset Type Triggers
- Query 180 - Create Card Asset
- Query 181 - Card Asset Triggers
- Query 190 - Create Language
- Query 191 - Language Triggers
- Query 192 - Refine Language Code Constraint
- Query 193 - Add Language to Card Asset
- Query 194 - Govern Card Asset Storage Provider
- Query 195 - Create Storage Bucket
- Query 196 - Storage Bucket Triggers
- Query 870 - Seed Card Asset Type
- Query 890 - Seed Language
- Query 895 - Seed Storage Bucket
- Query 970 - Validate Language
- Query 975 - Validate Storage Bucket
- Query 197 - Integrate Storage Bucket into Card Asset
===============================================================================
*/

BEGIN;

/*
-------------------------------------------------------------------------------
1. Existência das tabelas obrigatórias
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    missing_count INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO missing_count
    FROM (
        VALUES
            ('card'),
            ('card_asset_type'),
            ('language'),
            ('storage_bucket'),
            ('card_asset')
    ) AS expected(table_name)
    WHERE to_regclass(
        'public.' || expected.table_name
    ) IS NULL;

    IF missing_count > 0 THEN
        RAISE EXCEPTION
            'Validação 980 falhou: existem % tabelas obrigatórias ausentes.',
            missing_count;
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
2. Estrutura das colunas essenciais
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    invalid_count INTEGER;
BEGIN
    WITH expected_columns (
        column_name,
        data_type,
        udt_name,
        is_nullable
    ) AS (
        VALUES
            ('id',                'uuid',                     'uuid',        'NO'),
            ('card_id',           'uuid',                     'uuid',        'NO'),
            ('asset_type_id',     'uuid',                     'uuid',        'NO'),
            ('language_id',       'uuid',                     'uuid',        'NO'),
            ('storage_bucket_id', 'uuid',                     'uuid',        'NO'),
            ('storage_path',      'text',                     'text',        'YES'),
            ('external_url',      'text',                     'text',        'YES'),
            ('asset_order',       'integer',                  'int4',        'NO'),
            ('is_primary',        'boolean',                  'bool',        'NO'),
            ('created_at',        'timestamp with time zone', 'timestamptz', 'NO'),
            ('updated_at',        'timestamp with time zone', 'timestamptz', 'NO')
    )
    SELECT COUNT(*)
    INTO invalid_count
    FROM expected_columns expected
    LEFT JOIN information_schema.columns actual
      ON actual.table_schema = 'public'
     AND actual.table_name = 'card_asset'
     AND actual.column_name = expected.column_name
    WHERE actual.column_name IS NULL
       OR actual.data_type IS DISTINCT FROM expected.data_type
       OR actual.udt_name IS DISTINCT FROM expected.udt_name
       OR actual.is_nullable IS DISTINCT FROM expected.is_nullable;

    IF invalid_count > 0 THEN
        RAISE EXCEPTION
            'Validação 980 falhou: existem % colunas essenciais ausentes ou incompatíveis em public.card_asset.',
            invalid_count;
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
3. Coluna storage_provider removida
-------------------------------------------------------------------------------
*/
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'card_asset'
          AND column_name = 'storage_provider'
    ) THEN
        RAISE EXCEPTION
            'Validação 980 falhou: a coluna obsoleta public.card_asset.storage_provider ainda existe.';
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
4. Defaults técnicos obrigatórios
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    invalid_count INTEGER;
BEGIN
    WITH expected_defaults (
        column_name,
        default_fragment
    ) AS (
        VALUES
            ('id',         'gen_random_uuid'),
            ('created_at', 'now()'),
            ('updated_at', 'now()')
    )
    SELECT COUNT(*)
    INTO invalid_count
    FROM expected_defaults expected
    LEFT JOIN information_schema.columns actual
      ON actual.table_schema = 'public'
     AND actual.table_name = 'card_asset'
     AND actual.column_name = expected.column_name
    WHERE actual.column_name IS NULL
       OR actual.column_default IS NULL
       OR LOWER(actual.column_default)
          NOT LIKE '%' || LOWER(expected.default_fragment) || '%';

    IF invalid_count > 0 THEN
        RAISE EXCEPTION
            'Validação 980 falhou: existem % defaults técnicos ausentes ou incompatíveis.',
            invalid_count;
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
5. Primary key exclusiva sobre id
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    id_attribute_number SMALLINT;
BEGIN
    SELECT attribute_data.attnum
    INTO id_attribute_number
    FROM pg_attribute attribute_data
    WHERE attribute_data.attrelid = 'public.card_asset'::regclass
      AND attribute_data.attname = 'id'
      AND attribute_data.attisdropped = FALSE;

    IF id_attribute_number IS NULL THEN
        RAISE EXCEPTION
            'Validação 980 falhou: não foi possível localizar public.card_asset.id.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint constraint_data
        WHERE constraint_data.conrelid = 'public.card_asset'::regclass
          AND constraint_data.contype = 'p'
          AND constraint_data.conkey =
              ARRAY[id_attribute_number]::SMALLINT[]
    ) THEN
        RAISE EXCEPTION
            'Validação 980 falhou: não existe primary key exclusiva sobre public.card_asset.id.';
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
6. Foreign key card_id → card.id
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    column_attribute_number SMALLINT;
BEGIN
    SELECT attribute_data.attnum
    INTO column_attribute_number
    FROM pg_attribute attribute_data
    WHERE attribute_data.attrelid = 'public.card_asset'::regclass
      AND attribute_data.attname = 'card_id'
      AND attribute_data.attisdropped = FALSE;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint constraint_data
        WHERE constraint_data.conrelid = 'public.card_asset'::regclass
          AND constraint_data.contype = 'f'
          AND constraint_data.confrelid = 'public.card'::regclass
          AND constraint_data.conkey =
              ARRAY[column_attribute_number]::SMALLINT[]
    ) THEN
        RAISE EXCEPTION
            'Validação 980 falhou: não existe foreign key de card_asset.card_id para card.id.';
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
7. Foreign key asset_type_id → card_asset_type.id
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    column_attribute_number SMALLINT;
BEGIN
    SELECT attribute_data.attnum
    INTO column_attribute_number
    FROM pg_attribute attribute_data
    WHERE attribute_data.attrelid = 'public.card_asset'::regclass
      AND attribute_data.attname = 'asset_type_id'
      AND attribute_data.attisdropped = FALSE;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint constraint_data
        WHERE constraint_data.conrelid = 'public.card_asset'::regclass
          AND constraint_data.contype = 'f'
          AND constraint_data.confrelid =
              'public.card_asset_type'::regclass
          AND constraint_data.conkey =
              ARRAY[column_attribute_number]::SMALLINT[]
    ) THEN
        RAISE EXCEPTION
            'Validação 980 falhou: não existe foreign key de card_asset.asset_type_id para card_asset_type.id.';
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
8. Foreign key language_id → language.id
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    column_attribute_number SMALLINT;
BEGIN
    SELECT attribute_data.attnum
    INTO column_attribute_number
    FROM pg_attribute attribute_data
    WHERE attribute_data.attrelid = 'public.card_asset'::regclass
      AND attribute_data.attname = 'language_id'
      AND attribute_data.attisdropped = FALSE;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint constraint_data
        WHERE constraint_data.conrelid = 'public.card_asset'::regclass
          AND constraint_data.contype = 'f'
          AND constraint_data.confrelid = 'public.language'::regclass
          AND constraint_data.conkey =
              ARRAY[column_attribute_number]::SMALLINT[]
    ) THEN
        RAISE EXCEPTION
            'Validação 980 falhou: não existe foreign key de card_asset.language_id para language.id.';
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
9. Foreign key storage_bucket_id → storage_bucket.id
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    column_attribute_number SMALLINT;
BEGIN
    SELECT attribute_data.attnum
    INTO column_attribute_number
    FROM pg_attribute attribute_data
    WHERE attribute_data.attrelid = 'public.card_asset'::regclass
      AND attribute_data.attname = 'storage_bucket_id'
      AND attribute_data.attisdropped = FALSE;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint constraint_data
        WHERE constraint_data.conrelid = 'public.card_asset'::regclass
          AND constraint_data.contype = 'f'
          AND constraint_data.confrelid =
              'public.storage_bucket'::regclass
          AND constraint_data.conkey =
              ARRAY[column_attribute_number]::SMALLINT[]
    ) THEN
        RAISE EXCEPTION
            'Validação 980 falhou: não existe foreign key de card_asset.storage_bucket_id para storage_bucket.id.';
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
10. Unicidade lógica do ativo
Regra:
(card_id, asset_type_id, language_id, asset_order)
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    card_attribute_number       SMALLINT;
    type_attribute_number       SMALLINT;
    language_attribute_number   SMALLINT;
    order_attribute_number      SMALLINT;
BEGIN
    SELECT attnum
    INTO card_attribute_number
    FROM pg_attribute
    WHERE attrelid = 'public.card_asset'::regclass
      AND attname = 'card_id'
      AND attisdropped = FALSE;

    SELECT attnum
    INTO type_attribute_number
    FROM pg_attribute
    WHERE attrelid = 'public.card_asset'::regclass
      AND attname = 'asset_type_id'
      AND attisdropped = FALSE;

    SELECT attnum
    INTO language_attribute_number
    FROM pg_attribute
    WHERE attrelid = 'public.card_asset'::regclass
      AND attname = 'language_id'
      AND attisdropped = FALSE;

    SELECT attnum
    INTO order_attribute_number
    FROM pg_attribute
    WHERE attrelid = 'public.card_asset'::regclass
      AND attname = 'asset_order'
      AND attisdropped = FALSE;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint constraint_data
        WHERE constraint_data.conrelid = 'public.card_asset'::regclass
          AND constraint_data.contype = 'u'
          AND constraint_data.conkey =
              ARRAY[
                  card_attribute_number,
                  type_attribute_number,
                  language_attribute_number,
                  order_attribute_number
              ]::SMALLINT[]
    ) THEN
        RAISE EXCEPTION
            'Validação 980 falhou: não existe UNIQUE(card_id, asset_type_id, language_id, asset_order).';
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
11. Índice único parcial para ativo primário
Regra:
um único is_primary = TRUE por
(card_id, asset_type_id, language_id)
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    valid_index_count INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO valid_index_count
    FROM pg_index index_data
    JOIN pg_class index_relation
      ON index_relation.oid = index_data.indexrelid
    WHERE index_data.indrelid = 'public.card_asset'::regclass
      AND index_data.indisunique = TRUE
      AND index_data.indpred IS NOT NULL
      AND LOWER(pg_get_indexdef(index_data.indexrelid))
          LIKE '%card_id%'
      AND LOWER(pg_get_indexdef(index_data.indexrelid))
          LIKE '%asset_type_id%'
      AND LOWER(pg_get_indexdef(index_data.indexrelid))
          LIKE '%language_id%'
      AND LOWER(pg_get_expr(
              index_data.indpred,
              index_data.indrelid
          ))
          LIKE '%is_primary%';

    IF valid_index_count = 0 THEN
        RAISE EXCEPTION
            'Validação 980 falhou: não existe índice único parcial para o ativo primário por carta, tipo e idioma.';
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
12. CHECK de asset_order positivo
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    valid_constraint_count INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO valid_constraint_count
    FROM pg_constraint constraint_data
    WHERE constraint_data.conrelid = 'public.card_asset'::regclass
      AND constraint_data.contype = 'c'
      AND LOWER(pg_get_constraintdef(constraint_data.oid))
          LIKE '%asset_order%'
      AND (
          pg_get_constraintdef(constraint_data.oid) LIKE '%> 0%'
          OR
          pg_get_constraintdef(constraint_data.oid) LIKE '%>= 1%'
      );

    IF valid_constraint_count = 0 THEN
        RAISE EXCEPTION
            'Validação 980 falhou: não existe CHECK garantindo asset_order positivo.';
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
13. Índices da integração com Storage Bucket
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    missing_count INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO missing_count
    FROM (
        VALUES
            ('ix_card_asset_storage_bucket_id'),
            ('ix_card_asset_bucket_language'),
            ('ix_card_asset_card_bucket')
    ) AS expected(index_name)
    WHERE to_regclass(
        'public.' || expected.index_name
    ) IS NULL;

    IF missing_count > 0 THEN
        RAISE EXCEPTION
            'Validação 980 falhou: existem % índices da arquitetura Storage Bucket ausentes.',
            missing_count;
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
14. Cobertura de índice para card_id
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    index_count INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO index_count
    FROM pg_indexes index_data
    WHERE index_data.schemaname = 'public'
      AND index_data.tablename = 'card_asset'
      AND LOWER(index_data.indexdef) LIKE '%card_id%';

    IF index_count = 0 THEN
        RAISE EXCEPTION
            'Validação 980 falhou: não existe índice cobrindo card_asset.card_id.';
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
15. Cobertura de índice para asset_type_id
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    index_count INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO index_count
    FROM pg_indexes index_data
    WHERE index_data.schemaname = 'public'
      AND index_data.tablename = 'card_asset'
      AND LOWER(index_data.indexdef) LIKE '%asset_type_id%';

    IF index_count = 0 THEN
        RAISE EXCEPTION
            'Validação 980 falhou: não existe índice cobrindo card_asset.asset_type_id.';
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
16. Cobertura de índice para language_id
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    index_count INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO index_count
    FROM pg_indexes index_data
    WHERE index_data.schemaname = 'public'
      AND index_data.tablename = 'card_asset'
      AND LOWER(index_data.indexdef) LIKE '%language_id%';

    IF index_count = 0 THEN
        RAISE EXCEPTION
            'Validação 980 falhou: não existe índice cobrindo card_asset.language_id.';
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
17. Trigger de updated_at
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    trigger_definition TEXT;
BEGIN
    SELECT pg_get_triggerdef(trigger_data.oid)
    INTO trigger_definition
    FROM pg_trigger trigger_data
    WHERE trigger_data.tgrelid = 'public.card_asset'::regclass
      AND trigger_data.tgname = 'trg_card_asset_set_updated_at'
      AND trigger_data.tgisinternal = FALSE
      AND trigger_data.tgenabled <> 'D';

    IF trigger_definition IS NULL THEN
        RAISE EXCEPTION
            'Validação 980 falhou: trg_card_asset_set_updated_at não existe ou está desabilitado.';
    END IF;

    IF LOWER(trigger_definition) NOT LIKE '%set_updated_at%' THEN
        RAISE EXCEPTION
            'Validação 980 falhou: trg_card_asset_set_updated_at não utiliza set_updated_at().';
    END IF;

    IF to_regprocedure('public.set_updated_at()') IS NULL THEN
        RAISE EXCEPTION
            'Validação 980 falhou: public.set_updated_at() não existe.';
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
18. Trigger de validação do armazenamento
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    trigger_definition TEXT;
BEGIN
    SELECT pg_get_triggerdef(trigger_data.oid)
    INTO trigger_definition
    FROM pg_trigger trigger_data
    WHERE trigger_data.tgrelid = 'public.card_asset'::regclass
      AND trigger_data.tgname = 'trg_card_asset_validate_storage'
      AND trigger_data.tgisinternal = FALSE
      AND trigger_data.tgenabled <> 'D';

    IF trigger_definition IS NULL THEN
        RAISE EXCEPTION
            'Validação 980 falhou: trg_card_asset_validate_storage não existe ou está desabilitado.';
    END IF;

    IF LOWER(trigger_definition)
       NOT LIKE '%validate_card_asset_storage%' THEN
        RAISE EXCEPTION
            'Validação 980 falhou: trg_card_asset_validate_storage não utiliza validate_card_asset_storage().';
    END IF;

    IF to_regprocedure(
        'public.validate_card_asset_storage()'
    ) IS NULL THEN
        RAISE EXCEPTION
            'Validação 980 falhou: public.validate_card_asset_storage() não existe.';
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
19. Conteúdo mínimo da função validate_card_asset_storage
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    function_definition TEXT;
BEGIN
    SELECT LOWER(
        pg_get_functiondef(
            'public.validate_card_asset_storage()'::regprocedure
        )
    )
    INTO function_definition;

    IF function_definition NOT LIKE '%storage_bucket%'
       OR function_definition NOT LIKE '%storage_provider%'
       OR function_definition NOT LIKE '%storage_path%'
       OR function_definition NOT LIKE '%external_url%'
       OR function_definition NOT LIKE '%is_active%'
       OR function_definition NOT LIKE '%external%' THEN
        RAISE EXCEPTION
            'Validação 980 falhou: validate_card_asset_storage() não contém todas as validações obrigatórias.';
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
20. Row Level Security
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    rls_enabled BOOLEAN;
BEGIN
    SELECT class_data.relrowsecurity
    INTO rls_enabled
    FROM pg_class class_data
    WHERE class_data.oid = 'public.card_asset'::regclass;

    IF rls_enabled IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION
            'Validação 980 falhou: Row Level Security não está habilitado em public.card_asset.';
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
21. Integridade básica dos registros existentes
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    invalid_count BIGINT;
BEGIN
    SELECT COUNT(*)
    INTO invalid_count
    FROM public.card_asset
    WHERE card_id IS NULL
       OR asset_type_id IS NULL
       OR language_id IS NULL
       OR storage_bucket_id IS NULL
       OR asset_order <= 0
       OR created_at IS NULL
       OR updated_at IS NULL;

    IF invalid_count > 0 THEN
        RAISE EXCEPTION
            'Validação 980 falhou: existem % registros com campos obrigatórios ausentes ou inválidos.',
            invalid_count;
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
22. Integridade das referências
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    invalid_card_count     BIGINT;
    invalid_type_count     BIGINT;
    invalid_language_count BIGINT;
    invalid_bucket_count   BIGINT;
BEGIN
    SELECT COUNT(*)
    INTO invalid_card_count
    FROM public.card_asset asset
    LEFT JOIN public.card card_data
      ON card_data.id = asset.card_id
    WHERE card_data.id IS NULL;

    IF invalid_card_count > 0 THEN
        RAISE EXCEPTION
            'Validação 980 falhou: existem % ativos referenciando cartas inexistentes.',
            invalid_card_count;
    END IF;

    SELECT COUNT(*)
    INTO invalid_type_count
    FROM public.card_asset asset
    LEFT JOIN public.card_asset_type asset_type
      ON asset_type.id = asset.asset_type_id
    WHERE asset_type.id IS NULL;

    IF invalid_type_count > 0 THEN
        RAISE EXCEPTION
            'Validação 980 falhou: existem % ativos referenciando tipos inexistentes.',
            invalid_type_count;
    END IF;

    SELECT COUNT(*)
    INTO invalid_language_count
    FROM public.card_asset asset
    LEFT JOIN public.language language_data
      ON language_data.id = asset.language_id
    WHERE language_data.id IS NULL;

    IF invalid_language_count > 0 THEN
        RAISE EXCEPTION
            'Validação 980 falhou: existem % ativos referenciando idiomas inexistentes.',
            invalid_language_count;
    END IF;

    SELECT COUNT(*)
    INTO invalid_bucket_count
    FROM public.card_asset asset
    LEFT JOIN public.storage_bucket bucket
      ON bucket.id = asset.storage_bucket_id
    WHERE bucket.id IS NULL;

    IF invalid_bucket_count > 0 THEN
        RAISE EXCEPTION
            'Validação 980 falhou: existem % ativos referenciando buckets inexistentes.',
            invalid_bucket_count;
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
23. Coerência entre provider, storage_path e external_url
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    invalid_count BIGINT;
BEGIN
    SELECT COUNT(*)
    INTO invalid_count
    FROM public.card_asset asset
    JOIN public.storage_bucket bucket
      ON bucket.id = asset.storage_bucket_id
    WHERE
        (
            bucket.storage_provider = 'EXTERNAL'
            AND (
                asset.external_url IS NULL
                OR BTRIM(asset.external_url) = ''
                OR asset.storage_path IS NOT NULL
            )
        )
        OR
        (
            bucket.storage_provider <> 'EXTERNAL'
            AND (
                asset.storage_path IS NULL
                OR BTRIM(asset.storage_path) = ''
                OR asset.external_url IS NOT NULL
            )
        );

    IF invalid_count > 0 THEN
        RAISE EXCEPTION
            'Validação 980 falhou: existem % ativos incompatíveis com o provider do bucket.',
            invalid_count;
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
24. Duplicidade lógica dos ativos
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    duplicate_count BIGINT;
BEGIN
    SELECT COUNT(*)
    INTO duplicate_count
    FROM (
        SELECT
            card_id,
            asset_type_id,
            language_id,
            asset_order
        FROM public.card_asset
        GROUP BY
            card_id,
            asset_type_id,
            language_id,
            asset_order
        HAVING COUNT(*) > 1
    ) duplicated_assets;

    IF duplicate_count > 0 THEN
        RAISE EXCEPTION
            'Validação 980 falhou: existem % combinações duplicadas de carta, tipo, idioma e ordem.',
            duplicate_count;
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
25. Multiplicidade indevida de ativos primários
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    duplicate_primary_count BIGINT;
BEGIN
    SELECT COUNT(*)
    INTO duplicate_primary_count
    FROM (
        SELECT
            card_id,
            asset_type_id,
            language_id
        FROM public.card_asset
        WHERE is_primary = TRUE
        GROUP BY
            card_id,
            asset_type_id,
            language_id
        HAVING COUNT(*) > 1
    ) duplicated_primary_assets;

    IF duplicate_primary_count > 0 THEN
        RAISE EXCEPTION
            'Validação 980 falhou: existem % grupos com mais de um ativo primário.',
            duplicate_primary_count;
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
26. Registros com valores em branco
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    invalid_count BIGINT;
BEGIN
    SELECT COUNT(*)
    INTO invalid_count
    FROM public.card_asset
    WHERE storage_path IS NOT NULL
          AND BTRIM(storage_path) = ''
       OR external_url IS NOT NULL
          AND BTRIM(external_url) = '';

    IF invalid_count > 0 THEN
        RAISE EXCEPTION
            'Validação 980 falhou: existem % ativos com storage_path ou external_url em branco.',
            invalid_count;
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
27. Comentários da arquitetura de armazenamento
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    missing_count INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO missing_count
    FROM (
        VALUES
            ('storage_bucket_id'),
            ('storage_path'),
            ('external_url')
    ) AS expected(column_name)
    LEFT JOIN pg_attribute attribute_data
      ON attribute_data.attrelid =
         'public.card_asset'::regclass
     AND attribute_data.attname =
         expected.column_name
     AND attribute_data.attisdropped = FALSE
    WHERE attribute_data.attnum IS NULL
       OR col_description(
              'public.card_asset'::regclass,
              attribute_data.attnum
          ) IS NULL
       OR BTRIM(
              col_description(
                  'public.card_asset'::regclass,
                  attribute_data.attnum
              )
          ) = '';

    IF missing_count > 0 THEN
        RAISE EXCEPTION
            'Validação 980 falhou: existem % colunas de armazenamento sem comentário.',
            missing_count;
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
28. Resultado consolidado
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    asset_count             BIGINT;
    primary_count           BIGINT;
    internal_storage_count  BIGINT;
    external_storage_count  BIGINT;
    language_count          BIGINT;
    bucket_count            BIGINT;
BEGIN
    SELECT
        COUNT(*),
        COUNT(*) FILTER (
            WHERE asset.is_primary = TRUE
        ),
        COUNT(*) FILTER (
            WHERE bucket.storage_provider <> 'EXTERNAL'
        ),
        COUNT(*) FILTER (
            WHERE bucket.storage_provider = 'EXTERNAL'
        ),
        COUNT(DISTINCT asset.language_id),
        COUNT(DISTINCT asset.storage_bucket_id)
    INTO
        asset_count,
        primary_count,
        internal_storage_count,
        external_storage_count,
        language_count,
        bucket_count
    FROM public.card_asset asset
    LEFT JOIN public.storage_bucket bucket
      ON bucket.id = asset.storage_bucket_id;

    RAISE NOTICE
        'VALIDAÇÃO 980 v2.0 CONCLUÍDA: CARD ASSET COMPLETE | ativos: % | primários: % | internos: % | externos: % | idiomas utilizados: % | buckets utilizados: %',
        asset_count,
        primary_count,
        internal_storage_count,
        external_storage_count,
        language_count,
        bucket_count;
END;
$$;

COMMIT;
