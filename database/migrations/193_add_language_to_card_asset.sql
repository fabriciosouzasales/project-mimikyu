/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 193 - Add Language to Card Asset
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18

Descrição:
Integra o catálogo de idiomas à tabela public.card_asset.

Cada ativo passa a pertencer a um idioma específico. Dessa forma, uma mesma
Card pode possuir ativos do mesmo tipo em diferentes idiomas.

Exemplo:
Card + CARD_FRONT + pt-BR
Card + CARD_FRONT + en

Alterações realizadas:
- adiciona language_id à tabela card_asset;
- associa registros existentes ao idioma pt-BR;
- torna language_id obrigatório;
- cria a FK para public.language;
- remove a antiga unicidade sem idioma;
- cria unicidade por Card, tipo, idioma e ordem;
- atualiza a regra de ativo principal para considerar o idioma.

Pré-requisitos:
- Query 180 - Create Card Asset.
- Query 190 - Create Language.
- Query 191 - Create Language Triggers.
- Query 192 - Refine Language Code Constraint.
- Query 890 - Seed Language.
- Idioma pt-BR cadastrado em public.language.

Nota (numeração): esta migration havia sido inicialmente cogitada com o
número 192 em discussões anteriores; foi renumerada para 193 para não
reutilizar o número já consumido por 192 - Refine Language Code Constraint,
preservando a unicidade e rastreabilidade histórica das migrations.
===============================================================================
*/

BEGIN;

/*
-------------------------------------------------------------------------------
1. Validação dos pré-requisitos
-------------------------------------------------------------------------------
*/
DO $$
BEGIN
    IF to_regclass('public.card_asset') IS NULL THEN
        RAISE EXCEPTION
            'Não foi possível executar a Query 193: a tabela public.card_asset não existe.';
    END IF;

    IF to_regclass('public.language') IS NULL THEN
        RAISE EXCEPTION
            'Não foi possível executar a Query 193: a tabela public.language não existe.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.language
        WHERE code = 'pt-BR'
    ) THEN
        RAISE EXCEPTION
            'Não foi possível executar a Query 193: o idioma pt-BR não está cadastrado.';
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
2. Inclusão inicial da coluna
-------------------------------------------------------------------------------
*/
ALTER TABLE public.card_asset
    ADD COLUMN IF NOT EXISTS language_id UUID;

/*
-------------------------------------------------------------------------------
3. Migração dos registros existentes
Registros anteriores à introdução do catálogo de idiomas são classificados
como português do Brasil.
-------------------------------------------------------------------------------
*/
UPDATE public.card_asset
SET language_id = (
    SELECT id
    FROM public.language
    WHERE code = 'pt-BR'
)
WHERE language_id IS NULL;

/*
-------------------------------------------------------------------------------
4. Obrigatoriedade do idioma
-------------------------------------------------------------------------------
*/
ALTER TABLE public.card_asset
    ALTER COLUMN language_id SET NOT NULL;

/*
-------------------------------------------------------------------------------
5. Foreign key para language
-------------------------------------------------------------------------------
*/
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'public.card_asset'::regclass
          AND conname = 'fk_card_asset_language'
    ) THEN
        ALTER TABLE public.card_asset
            ADD CONSTRAINT fk_card_asset_language
            FOREIGN KEY (language_id)
            REFERENCES public.language (id)
            ON UPDATE RESTRICT
            ON DELETE RESTRICT;
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
6. Remoção da antiga constraint de unicidade
Remove qualquer UNIQUE formada exatamente por:
card_id
asset_type_id
asset_order
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    constraint_record RECORD;
BEGIN
    FOR constraint_record IN
        SELECT
            constraint_data.conname
        FROM (
            SELECT
                c.conname,
                ARRAY_AGG(a.attname ORDER BY key_columns.ordinality) AS columns
            FROM pg_constraint c
            CROSS JOIN LATERAL
                UNNEST(c.conkey)
                WITH ORDINALITY AS key_columns(attnum, ordinality)
            JOIN pg_attribute a
              ON a.attrelid = c.conrelid
             AND a.attnum = key_columns.attnum
            WHERE c.conrelid = 'public.card_asset'::regclass
              AND c.contype = 'u'
            GROUP BY c.conname
        ) AS constraint_data
        WHERE constraint_data.columns =
              ARRAY[
                  'card_id',
                  'asset_type_id',
                  'asset_order'
              ]::NAME[]
    LOOP
        EXECUTE FORMAT(
            'ALTER TABLE public.card_asset DROP CONSTRAINT %I',
            constraint_record.conname
        );
    END LOOP;
END;
$$;

/*
-------------------------------------------------------------------------------
7. Remoção do antigo índice de ativo principal
Remove índices únicos parciais antigos formados por:
card_id
asset_type_id
com predicado baseado em is_primary e sem language_id.
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    index_record RECORD;
BEGIN
    FOR index_record IN
        SELECT
            index_data.index_name
        FROM (
            SELECT
                index_class.relname AS index_name,
                ARRAY_AGG(
                    attribute_data.attname
                    ORDER BY indexed_columns.ordinality
                ) FILTER (
                    WHERE indexed_columns.ordinality <= index_data_raw.indnkeyatts
                ) AS columns,
                PG_GET_EXPR(
                    index_data_raw.indpred,
                    index_data_raw.indrelid
                ) AS predicate
            FROM pg_index index_data_raw
            JOIN pg_class table_class
              ON table_class.oid = index_data_raw.indrelid
            JOIN pg_namespace table_namespace
              ON table_namespace.oid = table_class.relnamespace
            JOIN pg_class index_class
              ON index_class.oid = index_data_raw.indexrelid
            CROSS JOIN LATERAL
                UNNEST(index_data_raw.indkey)
                WITH ORDINALITY AS indexed_columns(attnum, ordinality)
            LEFT JOIN pg_attribute attribute_data
              ON attribute_data.attrelid = index_data_raw.indrelid
             AND attribute_data.attnum = indexed_columns.attnum
            WHERE table_namespace.nspname = 'public'
              AND table_class.relname = 'card_asset'
              AND index_data_raw.indisunique = TRUE
              AND index_data_raw.indpred IS NOT NULL
            GROUP BY
                index_class.relname,
                index_data_raw.indpred,
                index_data_raw.indrelid,
                index_data_raw.indnkeyatts
        ) AS index_data
        WHERE index_data.columns =
              ARRAY[
                  'card_id',
                  'asset_type_id'
              ]::NAME[]
          AND index_data.predicate ILIKE '%is_primary%'
    LOOP
        EXECUTE FORMAT(
            'DROP INDEX IF EXISTS public.%I',
            index_record.index_name
        );
    END LOOP;
END;
$$;

/*
-------------------------------------------------------------------------------
8. Nova unicidade de ordem por idioma
-------------------------------------------------------------------------------
*/
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'public.card_asset'::regclass
          AND conname = 'uq_card_asset_card_type_language_order'
    ) THEN
        ALTER TABLE public.card_asset
            ADD CONSTRAINT uq_card_asset_card_type_language_order
            UNIQUE (
                card_id,
                asset_type_id,
                language_id,
                asset_order
            );
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
9. Um único ativo principal por Card, tipo e idioma
-------------------------------------------------------------------------------
*/
CREATE UNIQUE INDEX IF NOT EXISTS
    ux_card_asset_primary_per_card_type_language
ON public.card_asset (
    card_id,
    asset_type_id,
    language_id
)
WHERE is_primary = TRUE;

/*
-------------------------------------------------------------------------------
10. Índice de suporte para consultas por idioma
-------------------------------------------------------------------------------
*/
CREATE INDEX IF NOT EXISTS ix_card_asset_language_id
    ON public.card_asset (language_id);

/*
-------------------------------------------------------------------------------
11. Índice de consulta por Card, idioma e tipo
-------------------------------------------------------------------------------
*/
CREATE INDEX IF NOT EXISTS ix_card_asset_card_language_type
    ON public.card_asset (
        card_id,
        language_id,
        asset_type_id
    );

/*
-------------------------------------------------------------------------------
12. Comentários
-------------------------------------------------------------------------------
*/
COMMENT ON COLUMN public.card_asset.language_id IS
'Idioma ao qual o ativo da Card pertence. Permite armazenar ativos equivalentes em diferentes idiomas.';

COMMENT ON CONSTRAINT fk_card_asset_language
ON public.card_asset IS
'Garante que todo Card Asset esteja associado a um idioma válido do catálogo language.';

COMMENT ON CONSTRAINT uq_card_asset_card_type_language_order
ON public.card_asset IS
'Garante que asset_order não se repita para a mesma Card, tipo de ativo e idioma.';

COMMENT ON INDEX public.ux_card_asset_primary_per_card_type_language IS
'Garante somente um ativo principal para cada combinação de Card, tipo de ativo e idioma.';

COMMIT;
