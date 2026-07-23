/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 975 - Validate Storage Bucket
Versão......: 1.1
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18

Descrição:
Valida integralmente a estrutura, as regras de negócio, as constraints,
os índices, o trigger, o RLS e a carga inicial do catálogo
public.storage_bucket.

A validação também executa testes controlados de rejeição de dados inválidos.
Esses testes não deixam registros na tabela.

NOTA DE NUMERAÇÃO (adicionada pela documentação, não pelo autor original):
pelo padrão de deslocamento fixo já em uso no projeto (Validate = Create + 800),
Storage Bucket (Create = 195) deveria ter sido numerada 995, não 975. Além
disso, 975 está a apenas 5 posições de 970, que já é usada por duas Queries
distintas neste mesmo lote ("970 - Validate Card Asset Type", executada em
ciclo anterior, e "970 - Validate Language", deste mesmo lote). Este arquivo
foi preservado com o número exatamente como executado no Supabase — ver
docs/05-modelo-de-dados.md para o registro completo da divergência,
sinalizada e não resolvida unilateralmente.

Pré-requisitos:
- Query 195 - Create Storage Bucket
- Query 196 - Create Storage Bucket Triggers
- Query 895 - Seed Storage Bucket
===============================================================================
*/

BEGIN;

/*
-------------------------------------------------------------------------------
1. Existência da tabela
-------------------------------------------------------------------------------
*/
DO $$
BEGIN
    IF to_regclass('public.storage_bucket') IS NULL THEN
        RAISE EXCEPTION
            'Validação 975 falhou: a tabela public.storage_bucket não existe.';
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
2. Estrutura das colunas
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
            ('id',               'uuid',                     'uuid',        'NO'),
            ('code',             'text',                     'text',        'NO'),
            ('name',             'text',                     'text',        'NO'),
            ('description',      'text',                     'text',        'YES'),
            ('storage_provider', 'text',                     'text',        'NO'),
            ('bucket_order',     'integer',                  'int4',        'NO'),
            ('is_public',        'boolean',                  'bool',        'NO'),
            ('is_active',        'boolean',                  'bool',        'NO'),
            ('created_at',       'timestamp with time zone', 'timestamptz', 'NO'),
            ('updated_at',       'timestamp with time zone', 'timestamptz', 'NO')
    )
    SELECT COUNT(*)
    INTO invalid_count
    FROM expected_columns expected
    LEFT JOIN information_schema.columns actual
      ON actual.table_schema = 'public'
     AND actual.table_name = 'storage_bucket'
     AND actual.column_name = expected.column_name
    WHERE actual.column_name IS NULL
       OR actual.data_type IS DISTINCT FROM expected.data_type
       OR actual.udt_name IS DISTINCT FROM expected.udt_name
       OR actual.is_nullable IS DISTINCT FROM expected.is_nullable;

    IF invalid_count > 0 THEN
        RAISE EXCEPTION
            'Validação 975 falhou: existem % colunas ausentes ou incompatíveis em public.storage_bucket.',
            invalid_count;
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
3. Ausência de colunas inesperadas
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    unexpected_count INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO unexpected_count
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'storage_bucket'
      AND column_name NOT IN (
          'id',
          'code',
          'name',
          'description',
          'storage_provider',
          'bucket_order',
          'is_public',
          'is_active',
          'created_at',
          'updated_at'
      );

    IF unexpected_count > 0 THEN
        RAISE EXCEPTION
            'Validação 975 falhou: public.storage_bucket possui % colunas inesperadas.',
            unexpected_count;
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
4. Defaults obrigatórios
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
            ('is_public',  'false'),
            ('is_active',  'true'),
            ('created_at', 'now()'),
            ('updated_at', 'now()')
    )
    SELECT COUNT(*)
    INTO invalid_count
    FROM expected_defaults expected
    LEFT JOIN information_schema.columns actual
      ON actual.table_schema = 'public'
     AND actual.table_name = 'storage_bucket'
     AND actual.column_name = expected.column_name
    WHERE actual.column_name IS NULL
       OR actual.column_default IS NULL
       OR LOWER(actual.column_default)
          NOT LIKE '%' || LOWER(expected.default_fragment) || '%';

    IF invalid_count > 0 THEN
        RAISE EXCEPTION
            'Validação 975 falhou: existem % defaults ausentes ou incompatíveis em public.storage_bucket.',
            invalid_count;
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
5. Primary key sobre a coluna id
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    id_attribute_number SMALLINT;
BEGIN
    SELECT attribute_data.attnum
    INTO id_attribute_number
    FROM pg_attribute attribute_data
    WHERE attribute_data.attrelid = 'public.storage_bucket'::regclass
      AND attribute_data.attname = 'id'
      AND attribute_data.attisdropped = FALSE;

    IF id_attribute_number IS NULL THEN
        RAISE EXCEPTION
            'Validação 975 falhou: não foi possível localizar a coluna id.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint constraint_data
        WHERE constraint_data.conrelid = 'public.storage_bucket'::regclass
          AND constraint_data.contype = 'p'
          AND constraint_data.conkey =
              ARRAY[id_attribute_number]::SMALLINT[]
    ) THEN
        RAISE EXCEPTION
            'Validação 975 falhou: não existe primary key exclusiva sobre a coluna id.';
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
6. Unicidade da coluna code
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    code_attribute_number SMALLINT;
BEGIN
    SELECT attribute_data.attnum
    INTO code_attribute_number
    FROM pg_attribute attribute_data
    WHERE attribute_data.attrelid = 'public.storage_bucket'::regclass
      AND attribute_data.attname = 'code'
      AND attribute_data.attisdropped = FALSE;

    IF code_attribute_number IS NULL THEN
        RAISE EXCEPTION
            'Validação 975 falhou: não foi possível localizar a coluna code.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint constraint_data
        WHERE constraint_data.conrelid = 'public.storage_bucket'::regclass
          AND constraint_data.contype = 'u'
          AND constraint_data.conkey =
              ARRAY[code_attribute_number]::SMALLINT[]
    ) THEN
        RAISE EXCEPTION
            'Validação 975 falhou: não existe constraint UNIQUE sobre a coluna code.';
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
7. Unicidade da coluna bucket_order
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    order_attribute_number SMALLINT;
BEGIN
    SELECT attribute_data.attnum
    INTO order_attribute_number
    FROM pg_attribute attribute_data
    WHERE attribute_data.attrelid = 'public.storage_bucket'::regclass
      AND attribute_data.attname = 'bucket_order'
      AND attribute_data.attisdropped = FALSE;

    IF order_attribute_number IS NULL THEN
        RAISE EXCEPTION
            'Validação 975 falhou: não foi possível localizar a coluna bucket_order.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint constraint_data
        WHERE constraint_data.conrelid = 'public.storage_bucket'::regclass
          AND constraint_data.contype = 'u'
          AND constraint_data.conkey =
              ARRAY[order_attribute_number]::SMALLINT[]
    ) THEN
        RAISE EXCEPTION
            'Validação 975 falhou: não existe constraint UNIQUE sobre a coluna bucket_order.';
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
8. Existência de CHECK constraints
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    check_count INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO check_count
    FROM pg_constraint constraint_data
    WHERE constraint_data.conrelid = 'public.storage_bucket'::regclass
      AND constraint_data.contype = 'c';

    IF check_count < 5 THEN
        RAISE EXCEPTION
            'Validação 975 falhou: foram encontradas somente % CHECK constraints; o mínimo esperado é 5.',
            check_count;
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
9. Teste da regra de storage_provider
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    test_code  TEXT;
    test_order INTEGER;
BEGIN
    test_code :=
        'validation-provider-' ||
        REPLACE(gen_random_uuid()::TEXT, '-', '');

    SELECT COALESCE(MAX(bucket_order), 0) + 1000
    INTO test_order
    FROM public.storage_bucket;

    BEGIN
        INSERT INTO public.storage_bucket (
            code,
            name,
            description,
            storage_provider,
            bucket_order,
            is_public,
            is_active
        )
        VALUES (
            test_code,
            'Validation Provider',
            'Registro temporário da Query 975.',
            'INVALID_PROVIDER',
            test_order,
            FALSE,
            TRUE
        );

        RAISE EXCEPTION
            USING
                ERRCODE = 'P0001',
                MESSAGE =
                    'Validação 975 falhou: storage_provider aceitou um valor inválido.';
    EXCEPTION
        WHEN check_violation THEN
            NULL;
        WHEN SQLSTATE 'P0001' THEN
            RAISE;
    END;
END;
$$;

/*
-------------------------------------------------------------------------------
10. Teste da regra de formato do código
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    test_order INTEGER;
BEGIN
    SELECT COALESCE(MAX(bucket_order), 0) + 1001
    INTO test_order
    FROM public.storage_bucket;

    BEGIN
        INSERT INTO public.storage_bucket (
            code,
            name,
            description,
            storage_provider,
            bucket_order,
            is_public,
            is_active
        )
        VALUES (
            'INVALID CODE',
            'Validation Code',
            'Registro temporário da Query 975.',
            'SUPABASE',
            test_order,
            FALSE,
            TRUE
        );

        RAISE EXCEPTION
            USING
                ERRCODE = 'P0001',
                MESSAGE =
                    'Validação 975 falhou: code aceitou um formato inválido.';
    EXCEPTION
        WHEN check_violation THEN
            NULL;
        WHEN SQLSTATE 'P0001' THEN
            RAISE;
    END;
END;
$$;

/*
-------------------------------------------------------------------------------
11. Teste da regra de nome não vazio
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    test_code  TEXT;
    test_order INTEGER;
BEGIN
    test_code :=
        'validation-name-' ||
        REPLACE(gen_random_uuid()::TEXT, '-', '');

    SELECT COALESCE(MAX(bucket_order), 0) + 1002
    INTO test_order
    FROM public.storage_bucket;

    BEGIN
        INSERT INTO public.storage_bucket (
            code,
            name,
            description,
            storage_provider,
            bucket_order,
            is_public,
            is_active
        )
        VALUES (
            test_code,
            '   ',
            'Registro temporário da Query 975.',
            'SUPABASE',
            test_order,
            FALSE,
            TRUE
        );

        RAISE EXCEPTION
            USING
                ERRCODE = 'P0001',
                MESSAGE =
                    'Validação 975 falhou: name aceitou um valor vazio.';
    EXCEPTION
        WHEN check_violation THEN
            NULL;
        WHEN SQLSTATE 'P0001' THEN
            RAISE;
    END;
END;
$$;

/*
-------------------------------------------------------------------------------
12. Teste da regra de ordem positiva
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    test_code TEXT;
BEGIN
    test_code :=
        'validation-order-' ||
        REPLACE(gen_random_uuid()::TEXT, '-', '');

    BEGIN
        INSERT INTO public.storage_bucket (
            code,
            name,
            description,
            storage_provider,
            bucket_order,
            is_public,
            is_active
        )
        VALUES (
            test_code,
            'Validation Order',
            'Registro temporário da Query 975.',
            'SUPABASE',
            0,
            FALSE,
            TRUE
        );

        RAISE EXCEPTION
            USING
                ERRCODE = 'P0001',
                MESSAGE =
                    'Validação 975 falhou: bucket_order aceitou um valor menor ou igual a zero.';
    EXCEPTION
        WHEN check_violation THEN
            NULL;
        WHEN SQLSTATE 'P0001' THEN
            RAISE;
    END;
END;
$$;

/*
-------------------------------------------------------------------------------
13. Índices obrigatórios
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
            ('ix_storage_bucket_storage_provider'),
            ('ix_storage_bucket_is_active'),
            ('ix_storage_bucket_provider_active')
    ) AS expected(index_name)
    WHERE to_regclass(
        'public.' || expected.index_name
    ) IS NULL;

    IF missing_count > 0 THEN
        RAISE EXCEPTION
            'Validação 975 falhou: existem % índices obrigatórios ausentes.',
            missing_count;
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
14. Trigger de updated_at
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    trigger_definition TEXT;
BEGIN
    SELECT pg_get_triggerdef(trigger_data.oid)
    INTO trigger_definition
    FROM pg_trigger trigger_data
    WHERE trigger_data.tgrelid = 'public.storage_bucket'::regclass
      AND trigger_data.tgname = 'trg_storage_bucket_set_updated_at'
      AND trigger_data.tgisinternal = FALSE
      AND trigger_data.tgenabled <> 'D';

    IF trigger_definition IS NULL THEN
        RAISE EXCEPTION
            'Validação 975 falhou: o trigger trg_storage_bucket_set_updated_at não existe ou está desabilitado.';
    END IF;

    IF LOWER(trigger_definition) NOT LIKE '%set_updated_at%' THEN
        RAISE EXCEPTION
            'Validação 975 falhou: trg_storage_bucket_set_updated_at não utiliza public.set_updated_at().';
    END IF;

    IF to_regprocedure('public.set_updated_at()') IS NULL THEN
        RAISE EXCEPTION
            'Validação 975 falhou: a função public.set_updated_at() não existe.';
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
15. Row Level Security
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    rls_enabled BOOLEAN;
BEGIN
    SELECT class_data.relrowsecurity
    INTO rls_enabled
    FROM pg_class class_data
    WHERE class_data.oid = 'public.storage_bucket'::regclass;

    IF rls_enabled IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION
            'Validação 975 falhou: Row Level Security não está habilitado em public.storage_bucket.';
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
16. Integridade geral dos dados
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    invalid_count BIGINT;
BEGIN
    SELECT COUNT(*)
    INTO invalid_count
    FROM public.storage_bucket
    WHERE BTRIM(code) = ''
       OR BTRIM(name) = ''
       OR storage_provider NOT IN (
           'SUPABASE',
           'S3',
           'R2',
           'LOCAL',
           'EXTERNAL'
       )
       OR bucket_order <= 0
       OR created_at IS NULL
       OR updated_at IS NULL;

    IF invalid_count > 0 THEN
        RAISE EXCEPTION
            'Validação 975 falhou: existem % registros inválidos em public.storage_bucket.',
            invalid_count;
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
17. Unicidade lógica dos dados
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    duplicate_code_count  INTEGER;
    duplicate_order_count INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO duplicate_code_count
    FROM (
        SELECT code
        FROM public.storage_bucket
        GROUP BY code
        HAVING COUNT(*) > 1
    ) duplicated_codes;

    IF duplicate_code_count > 0 THEN
        RAISE EXCEPTION
            'Validação 975 falhou: existem % códigos de bucket duplicados.',
            duplicate_code_count;
    END IF;

    SELECT COUNT(*)
    INTO duplicate_order_count
    FROM (
        SELECT bucket_order
        FROM public.storage_bucket
        GROUP BY bucket_order
        HAVING COUNT(*) > 1
    ) duplicated_orders;

    IF duplicate_order_count > 0 THEN
        RAISE EXCEPTION
            'Validação 975 falhou: existem % ordens de bucket duplicadas.',
            duplicate_order_count;
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
18. Existência dos buckets obrigatórios
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
            ('card-front'),
            ('artwork'),
            ('card-back')
    ) AS expected(code)
    WHERE NOT EXISTS (
        SELECT 1
        FROM public.storage_bucket actual
        WHERE actual.code = expected.code
    );

    IF missing_count > 0 THEN
        RAISE EXCEPTION
            'Validação 975 falhou: existem % buckets obrigatórios ausentes.',
            missing_count;
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
19. Conteúdo da carga inicial
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    invalid_count INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO invalid_count
    FROM (
        VALUES
            (
                'card-front',
                'Card Front',
                'Imagens da frente das cartas colecionáveis.',
                'SUPABASE',
                1,
                TRUE,
                TRUE
            ),
            (
                'artwork',
                'Artwork',
                'Artes isoladas ou imagens artísticas associadas às cartas.',
                'SUPABASE',
                2,
                TRUE,
                TRUE
            ),
            (
                'card-back',
                'Card Back',
                'Imagens do verso das cartas colecionáveis.',
                'SUPABASE',
                3,
                TRUE,
                TRUE
            )
    ) AS expected(
        code,
        name,
        description,
        storage_provider,
        bucket_order,
        is_public,
        is_active
    )
    LEFT JOIN public.storage_bucket actual
      ON actual.code = expected.code
    WHERE actual.id IS NULL
       OR actual.name IS DISTINCT FROM expected.name
       OR actual.description IS DISTINCT FROM expected.description
       OR actual.storage_provider IS DISTINCT FROM expected.storage_provider
       OR actual.bucket_order IS DISTINCT FROM expected.bucket_order
       OR actual.is_public IS DISTINCT FROM expected.is_public
       OR actual.is_active IS DISTINCT FROM expected.is_active;

    IF invalid_count > 0 THEN
        RAISE EXCEPTION
            'Validação 975 falhou: existem % buckets obrigatórios com valores ausentes ou divergentes.',
            invalid_count;
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
20. Quantidade mínima da carga
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    bucket_count BIGINT;
BEGIN
    SELECT COUNT(*)
    INTO bucket_count
    FROM public.storage_bucket;

    IF bucket_count < 3 THEN
        RAISE EXCEPTION
            'Validação 975 falhou: public.storage_bucket possui somente % registros; o mínimo esperado é 3.',
            bucket_count;
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
21. Resultado
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    bucket_count        BIGINT;
    active_count        BIGINT;
    public_count        BIGINT;
    supabase_count      BIGINT;
BEGIN
    SELECT
        COUNT(*),
        COUNT(*) FILTER (
            WHERE is_active = TRUE
        ),
        COUNT(*) FILTER (
            WHERE is_public = TRUE
        ),
        COUNT(*) FILTER (
            WHERE storage_provider = 'SUPABASE'
        )
    INTO
        bucket_count,
        active_count,
        public_count,
        supabase_count
    FROM public.storage_bucket;

    RAISE NOTICE
        'VALIDAÇÃO 975 CONCLUÍDA: STORAGE BUCKET COMPLETE | buckets: % | ativos: % | públicos: % | Supabase: %',
        bucket_count,
        active_count,
        public_count,
        supabase_count;
END;
$$;

COMMIT;
