/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 197 - Integrate Storage Bucket into Card Asset
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18

Descrição:
Integra o catálogo public.storage_bucket à tabela public.card_asset.

A migration:
- adiciona storage_bucket_id;
- cria a foreign key para public.storage_bucket;
- substitui a validação baseada em storage_provider;
- remove triggers e constraints antigas que dependam de storage_provider;
- remove índices antigos associados a storage_provider;
- remove definitivamente storage_provider de public.card_asset;
- cria os novos índices;
- cria trigger para validar a coerência entre bucket, storage_path e external_url.

Regra final:
- bucket com provider EXTERNAL:
    external_url obrigatório;
    storage_path deve ser nulo.
- bucket com qualquer outro provider:
    storage_path obrigatório;
    external_url deve ser nulo.

Observação:
Esta migration exige que public.card_asset esteja vazia. A carga inicial dos
ativos ainda não foi executada, portanto a mudança pode ser realizada sem uma
conversão arbitrária de registros existentes.

Pré-requisitos:
- Query 180 - Create Card Asset
- Query 181 - Card Asset Triggers
- Query 193 - Add Language to Card Asset
- Query 194 - Govern Card Asset Storage Provider
- Query 195 - Create Storage Bucket
- Query 196 - Storage Bucket Triggers
- Query 895 - Seed Storage Bucket
- Query 975 - Validate Storage Bucket
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
            'Query 197 falhou: a tabela public.card_asset não existe.';
    END IF;

    IF to_regclass('public.storage_bucket') IS NULL THEN
        RAISE EXCEPTION
            'Query 197 falhou: a tabela public.storage_bucket não existe.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'card_asset'
          AND column_name = 'storage_provider'
    ) THEN
        RAISE EXCEPTION
            'Query 197 falhou: a coluna public.card_asset.storage_provider não existe.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'card_asset'
          AND column_name = 'storage_path'
    ) THEN
        RAISE EXCEPTION
            'Query 197 falhou: a coluna public.card_asset.storage_path não existe.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'card_asset'
          AND column_name = 'external_url'
    ) THEN
        RAISE EXCEPTION
            'Query 197 falhou: a coluna public.card_asset.external_url não existe.';
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
2. Proteção contra migração ambígua de dados existentes
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    card_asset_count BIGINT;
BEGIN
    SELECT COUNT(*)
    INTO card_asset_count
    FROM public.card_asset;

    IF card_asset_count > 0 THEN
        RAISE EXCEPTION
            'Query 197 interrompida: public.card_asset possui % registros. A atribuição de buckets deve ser definida antes da remoção de storage_provider.',
            card_asset_count;
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
3. Validação dos buckets obrigatórios
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
          AND actual.is_active = TRUE
    );

    IF missing_count > 0 THEN
        RAISE EXCEPTION
            'Query 197 falhou: existem % buckets obrigatórios ausentes ou inativos.',
            missing_count;
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
4. Adição de storage_bucket_id
-------------------------------------------------------------------------------
*/
ALTER TABLE public.card_asset
    ADD COLUMN storage_bucket_id UUID;

/*
-------------------------------------------------------------------------------
5. Foreign key para storage_bucket
-------------------------------------------------------------------------------
*/
ALTER TABLE public.card_asset
    ADD CONSTRAINT fk_card_asset_storage_bucket
    FOREIGN KEY (storage_bucket_id)
    REFERENCES public.storage_bucket(id)
    ON UPDATE RESTRICT
    ON DELETE RESTRICT;

/*
-------------------------------------------------------------------------------
6. Remoção de triggers antigos dependentes de storage_provider
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    trigger_record RECORD;
BEGIN
    FOR trigger_record IN
        SELECT
            trigger_data.tgname AS trigger_name
        FROM pg_trigger trigger_data
        JOIN pg_proc function_data
          ON function_data.oid = trigger_data.tgfoid
        WHERE trigger_data.tgrelid = 'public.card_asset'::regclass
          AND trigger_data.tgisinternal = FALSE
          AND LOWER(pg_get_functiondef(function_data.oid))
              LIKE '%storage_provider%'
    LOOP
        EXECUTE FORMAT(
            'DROP TRIGGER IF EXISTS %I ON public.card_asset',
            trigger_record.trigger_name
        );
    END LOOP;
END;
$$;

/*
-------------------------------------------------------------------------------
7. Remoção de constraints antigas dependentes de storage_provider
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    constraint_record RECORD;
BEGIN
    FOR constraint_record IN
        SELECT
            constraint_data.conname AS constraint_name
        FROM pg_constraint constraint_data
        WHERE constraint_data.conrelid = 'public.card_asset'::regclass
          AND LOWER(pg_get_constraintdef(constraint_data.oid))
              LIKE '%storage_provider%'
    LOOP
        EXECUTE FORMAT(
            'ALTER TABLE public.card_asset DROP CONSTRAINT %I',
            constraint_record.constraint_name
        );
    END LOOP;
END;
$$;

/*
-------------------------------------------------------------------------------
8. Remoção de índices antigos dependentes de storage_provider
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    index_record RECORD;
BEGIN
    FOR index_record IN
        SELECT
            index_data.indexname
        FROM pg_indexes index_data
        WHERE index_data.schemaname = 'public'
          AND index_data.tablename = 'card_asset'
          AND LOWER(index_data.indexdef) LIKE '%storage_provider%'
    LOOP
        EXECUTE FORMAT(
            'DROP INDEX IF EXISTS public.%I',
            index_record.indexname
        );
    END LOOP;
END;
$$;

/*
-------------------------------------------------------------------------------
9. Remoção definitiva de storage_provider
-------------------------------------------------------------------------------
*/
ALTER TABLE public.card_asset
    DROP COLUMN storage_provider;

/*
-------------------------------------------------------------------------------
10. storage_bucket_id obrigatório
-------------------------------------------------------------------------------
*/
ALTER TABLE public.card_asset
    ALTER COLUMN storage_bucket_id SET NOT NULL;

/*
-------------------------------------------------------------------------------
11. Índices da nova arquitetura
-------------------------------------------------------------------------------
*/
CREATE INDEX ix_card_asset_storage_bucket_id
    ON public.card_asset(storage_bucket_id);

CREATE INDEX ix_card_asset_bucket_language
    ON public.card_asset(
        storage_bucket_id,
        language_id
    );

CREATE INDEX ix_card_asset_card_bucket
    ON public.card_asset(
        card_id,
        storage_bucket_id
    );

/*
-------------------------------------------------------------------------------
12. Função de validação da localização física do ativo
-------------------------------------------------------------------------------
*/
CREATE OR REPLACE FUNCTION public.validate_card_asset_storage()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    bucket_provider TEXT;
    bucket_active   BOOLEAN;
BEGIN
    SELECT
        storage_bucket.storage_provider,
        storage_bucket.is_active
    INTO
        bucket_provider,
        bucket_active
    FROM public.storage_bucket storage_bucket
    WHERE storage_bucket.id = NEW.storage_bucket_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Card Asset inválido: storage_bucket_id % não existe.',
            NEW.storage_bucket_id;
    END IF;

    IF bucket_active IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION
            'Card Asset inválido: o bucket selecionado está inativo.';
    END IF;

    NEW.storage_path :=
        NULLIF(BTRIM(NEW.storage_path), '');
    NEW.external_url :=
        NULLIF(BTRIM(NEW.external_url), '');

    IF bucket_provider = 'EXTERNAL' THEN
        IF NEW.external_url IS NULL THEN
            RAISE EXCEPTION
                'Card Asset inválido: external_url é obrigatório para buckets EXTERNAL.';
        END IF;

        IF NEW.storage_path IS NOT NULL THEN
            RAISE EXCEPTION
                'Card Asset inválido: storage_path deve ser nulo para buckets EXTERNAL.';
        END IF;
    ELSE
        IF NEW.storage_path IS NULL THEN
            RAISE EXCEPTION
                'Card Asset inválido: storage_path é obrigatório para o provider %.',
                bucket_provider;
        END IF;

        IF NEW.external_url IS NOT NULL THEN
            RAISE EXCEPTION
                'Card Asset inválido: external_url deve ser nulo para o provider %.',
                bucket_provider;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

/*
-------------------------------------------------------------------------------
13. Trigger de validação
-------------------------------------------------------------------------------
*/
DROP TRIGGER IF EXISTS trg_card_asset_validate_storage
    ON public.card_asset;

CREATE TRIGGER trg_card_asset_validate_storage
BEFORE INSERT OR UPDATE OF
    storage_bucket_id,
    storage_path,
    external_url
ON public.card_asset
FOR EACH ROW
EXECUTE FUNCTION public.validate_card_asset_storage();

/*
-------------------------------------------------------------------------------
14. Comentários
-------------------------------------------------------------------------------
*/
COMMENT ON COLUMN public.card_asset.storage_bucket_id IS
    'Bucket físico ou lógico no qual o ativo digital está armazenado.';

COMMENT ON COLUMN public.card_asset.storage_path IS
    'Caminho do objeto dentro do bucket. Obrigatório para providers não externos.';

COMMENT ON COLUMN public.card_asset.external_url IS
    'URL absoluta do ativo. Utilizada exclusivamente por buckets com provider EXTERNAL.';

COMMENT ON FUNCTION public.validate_card_asset_storage() IS
    'Valida a coerência entre o bucket, o provider, storage_path e external_url de Card Asset.';

/*
-------------------------------------------------------------------------------
15. Validação estrutural pós-migration
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
            'Query 197 falhou: storage_provider ainda existe em public.card_asset.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'card_asset'
          AND column_name = 'storage_bucket_id'
          AND data_type = 'uuid'
          AND is_nullable = 'NO'
    ) THEN
        RAISE EXCEPTION
            'Query 197 falhou: storage_bucket_id não foi criado corretamente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint constraint_data
        WHERE constraint_data.conrelid = 'public.card_asset'::regclass
          AND constraint_data.conname = 'fk_card_asset_storage_bucket'
          AND constraint_data.contype = 'f'
    ) THEN
        RAISE EXCEPTION
            'Query 197 falhou: fk_card_asset_storage_bucket não foi criada.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger trigger_data
        WHERE trigger_data.tgrelid = 'public.card_asset'::regclass
          AND trigger_data.tgname = 'trg_card_asset_validate_storage'
          AND trigger_data.tgisinternal = FALSE
          AND trigger_data.tgenabled <> 'D'
    ) THEN
        RAISE EXCEPTION
            'Query 197 falhou: trg_card_asset_validate_storage não foi criado ou está desabilitado.';
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
16. Resultado
-------------------------------------------------------------------------------
*/
DO $$
BEGIN
    RAISE NOTICE
        'QUERY 197 CONCLUÍDA: STORAGE BUCKET INTEGRADO À CARD ASSET | storage_provider removido';
END;
$$;

COMMIT;
