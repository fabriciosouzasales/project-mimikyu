/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 970 - Validate Language
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18

Descrição:
Valida integralmente a estrutura, as regras e a carga inicial do catálogo
public.language.

NOTA DE NUMERAÇÃO (adicionada pela documentação, não pelo autor original):
o número 970 já era utilizado por "970 - Validate Card Asset Type"
(database/validations/970_validate_card_asset_type.sql, executada em ciclo
anterior). Pelo padrão de deslocamento fixo já em uso no projeto
(Validate = Create + 800), Language (Create = 190) deveria ter sido
numerada 990, não 970. Este arquivo foi preservado com o número exatamente
como executado no Supabase, para não divergir do que rodou de fato no banco
real — ver docs/05-modelo-de-dados.md para o registro completo da
divergência, sinalizada e não resolvida unilateralmente.

Pré-requisitos:
- Query 190 - Create Language.
- Query 191 - Create Language Triggers.
- Query 192 - Refine Language Code Constraint.
- Query 890 - Seed Language.
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
    IF to_regclass('public.language') IS NULL THEN
        RAISE EXCEPTION
            'Validação 970 falhou: a tabela public.language não existe.';
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
            ('id',             'uuid',                     'uuid',         'NO'),
            ('code',           'text',                     'text',         'NO'),
            ('name',           'text',                     'text',         'NO'),
            ('native_name',    'text',                     'text',         'NO'),
            ('language_order', 'integer',                  'int4',         'NO'),
            ('is_active',      'boolean',                  'bool',         'NO'),
            ('created_at',     'timestamp with time zone', 'timestamptz',  'NO'),
            ('updated_at',     'timestamp with time zone', 'timestamptz',  'NO')
    )
    SELECT COUNT(*)
    INTO invalid_count
    FROM expected_columns expected
    LEFT JOIN information_schema.columns actual
      ON actual.table_schema = 'public'
     AND actual.table_name = 'language'
     AND actual.column_name = expected.column_name
    WHERE actual.column_name IS NULL
       OR actual.data_type <> expected.data_type
       OR actual.udt_name <> expected.udt_name
       OR actual.is_nullable <> expected.is_nullable;

    IF invalid_count > 0 THEN
        RAISE EXCEPTION
            'Validação 970 falhou: existem % colunas ausentes ou incompatíveis em public.language.',
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
      AND table_name = 'language'
      AND column_name NOT IN (
          'id',
          'code',
          'name',
          'native_name',
          'language_order',
          'is_active',
          'created_at',
          'updated_at'
      );

    IF unexpected_count > 0 THEN
        RAISE EXCEPTION
            'Validação 970 falhou: public.language possui % colunas inesperadas.',
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
    SELECT COUNT(*)
    INTO invalid_count
    FROM (
        VALUES
            ('id',         'gen_random_uuid'),
            ('is_active',  'true'),
            ('created_at', 'now()'),
            ('updated_at', 'now()')
    ) AS expected(column_name, expected_default)
    LEFT JOIN information_schema.columns actual
      ON actual.table_schema = 'public'
     AND actual.table_name = 'language'
     AND actual.column_name = expected.column_name
    WHERE actual.column_default IS NULL
       OR LOWER(actual.column_default) NOT LIKE
          '%' || LOWER(expected.expected_default) || '%';

    IF invalid_count > 0 THEN
        RAISE EXCEPTION
            'Validação 970 falhou: existem % defaults ausentes ou incompatíveis em public.language.',
            invalid_count;
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
5. Primary key
-------------------------------------------------------------------------------
*/
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint constraint_data
        WHERE constraint_data.conrelid = 'public.language'::regclass
          AND constraint_data.contype = 'p'
          AND constraint_data.conname = 'language_pkey'
    ) THEN
        RAISE EXCEPTION
            'Validação 970 falhou: a primary key language_pkey não existe.';
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
6. Constraints obrigatórias
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
            ('uq_language_code',             'u'),
            ('uq_language_order',            'u'),
            ('ck_language_code_not_blank',   'c'),
            ('ck_language_name_not_blank',   'c'),
            ('ck_language_native_name_not_blank', 'c'),
            ('ck_language_code_format',      'c'),
            ('ck_language_order_positive',   'c')
    ) AS expected(constraint_name, constraint_type)
    WHERE NOT EXISTS (
        SELECT 1
        FROM pg_constraint actual
        WHERE actual.conrelid = 'public.language'::regclass
          AND actual.conname = expected.constraint_name
          AND actual.contype::TEXT = expected.constraint_type
    );

    IF missing_count > 0 THEN
        RAISE EXCEPTION
            'Validação 970 falhou: existem % constraints obrigatórias ausentes ou incompatíveis.',
            missing_count;
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
7. Conteúdo da constraint de formato
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    constraint_definition TEXT;
BEGIN
    SELECT pg_get_constraintdef(oid)
    INTO constraint_definition
    FROM pg_constraint
    WHERE conrelid = 'public.language'::regclass
      AND conname = 'ck_language_code_format';

    IF constraint_definition IS NULL
       OR constraint_definition NOT LIKE '%^[a-z]{2}(-[A-Z]{2})?$%' THEN
        RAISE EXCEPTION
            'Validação 970 falhou: ck_language_code_format não utiliza o padrão esperado xx ou xx-YY.';
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
8. Índice obrigatório
-------------------------------------------------------------------------------
*/
DO $$
BEGIN
    IF to_regclass('public.ix_language_is_active') IS NULL THEN
        RAISE EXCEPTION
            'Validação 970 falhou: o índice ix_language_is_active não existe.';
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
9. Trigger de updated_at
-------------------------------------------------------------------------------
*/
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger trigger_data
        WHERE trigger_data.tgrelid = 'public.language'::regclass
          AND trigger_data.tgname = 'trg_language_set_updated_at'
          AND trigger_data.tgenabled <> 'D'
          AND NOT trigger_data.tgisinternal
    ) THEN
        RAISE EXCEPTION
            'Validação 970 falhou: o trigger trg_language_set_updated_at não existe ou está desabilitado.';
    END IF;

    IF to_regprocedure('public.set_updated_at()') IS NULL THEN
        RAISE EXCEPTION
            'Validação 970 falhou: a função public.set_updated_at() não existe.';
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
10. Row Level Security
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    rls_enabled BOOLEAN;
BEGIN
    SELECT relrowsecurity
    INTO rls_enabled
    FROM pg_class
    WHERE oid = 'public.language'::regclass;

    IF rls_enabled IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION
            'Validação 970 falhou: Row Level Security não está habilitado em public.language.';
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
11. Integridade geral dos dados
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    invalid_count BIGINT;
BEGIN
    SELECT COUNT(*)
    INTO invalid_count
    FROM public.language
    WHERE BTRIM(code) = ''
       OR code !~ '^[a-z]{2}(-[A-Z]{2})?$'
       OR BTRIM(name) = ''
       OR BTRIM(native_name) = ''
       OR language_order <= 0
       OR created_at IS NULL
       OR updated_at IS NULL;

    IF invalid_count > 0 THEN
        RAISE EXCEPTION
            'Validação 970 falhou: existem % registros inválidos em public.language.',
            invalid_count;
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
12. Unicidade lógica dos dados
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    duplicate_code_count INTEGER;
    duplicate_order_count INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO duplicate_code_count
    FROM (
        SELECT code
        FROM public.language
        GROUP BY code
        HAVING COUNT(*) > 1
    ) duplicated_codes;

    IF duplicate_code_count > 0 THEN
        RAISE EXCEPTION
            'Validação 970 falhou: existem % códigos de idioma duplicados.',
            duplicate_code_count;
    END IF;

    SELECT COUNT(*)
    INTO duplicate_order_count
    FROM (
        SELECT language_order
        FROM public.language
        GROUP BY language_order
        HAVING COUNT(*) > 1
    ) duplicated_orders;

    IF duplicate_order_count > 0 THEN
        RAISE EXCEPTION
            'Validação 970 falhou: existem % ordens de idioma duplicadas.',
            duplicate_order_count;
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
13. Seed obrigatório
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    missing_count INTEGER;
    invalid_count INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO missing_count
    FROM (
        VALUES
            ('pt-BR'),
            ('en')
    ) AS expected(code)
    WHERE NOT EXISTS (
        SELECT 1
        FROM public.language actual
        WHERE actual.code = expected.code
    );

    IF missing_count > 0 THEN
        RAISE EXCEPTION
            'Validação 970 falhou: existem % idiomas obrigatórios ausentes.',
            missing_count;
    END IF;

    SELECT COUNT(*)
    INTO invalid_count
    FROM public.language
    WHERE
        (
            code = 'pt-BR'
            AND (
                name <> 'Português (Brasil)'
                OR native_name <> 'Português (Brasil)'
                OR language_order <> 1
                OR is_active IS DISTINCT FROM TRUE
            )
        )
        OR
        (
            code = 'en'
            AND (
                name <> 'English'
                OR native_name <> 'English'
                OR language_order <> 2
                OR is_active IS DISTINCT FROM TRUE
            )
        );

    IF invalid_count > 0 THEN
        RAISE EXCEPTION
            'Validação 970 falhou: existem % registros obrigatórios com valores divergentes.',
            invalid_count;
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
14. Quantidade mínima da carga
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    language_count BIGINT;
BEGIN
    SELECT COUNT(*)
    INTO language_count
    FROM public.language;

    IF language_count < 2 THEN
        RAISE EXCEPTION
            'Validação 970 falhou: public.language possui somente % registros; o mínimo esperado é 2.',
            language_count;
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
15. Resultado
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    language_count BIGINT;
    active_count BIGINT;
BEGIN
    SELECT
        COUNT(*),
        COUNT(*) FILTER (WHERE is_active = TRUE)
    INTO
        language_count,
        active_count
    FROM public.language;

    RAISE NOTICE
        'VALIDAÇÃO 970 CONCLUÍDA: LANGUAGE COMPLETE | idiomas: % | ativos: %',
        language_count,
        active_count;
END;
$$;

COMMIT;
