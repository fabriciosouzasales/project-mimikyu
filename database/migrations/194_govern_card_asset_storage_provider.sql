/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 194 - Govern Card Asset Storage Provider
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18

Descrição:
Fortalece a governança da localização dos ativos armazenados em
public.card_asset.

Provedores permitidos:
- SUPABASE
- S3
- R2
- LOCAL
- EXTERNAL

Regras:
- storage_provider é obrigatório;
- EXTERNAL exige external_url;
- SUPABASE, S3, R2 e LOCAL exigem storage_path;
- external_url continua permitido para ativos internos quando representar
  uma URL pública ou CDN associada ao arquivo armazenado.

Pré-requisitos:
- Query 180 - Create Card Asset.
- Query 193 - Add Language to Card Asset.
===============================================================================
*/

BEGIN;

/*
-------------------------------------------------------------------------------
1. Validação do pré-requisito
-------------------------------------------------------------------------------
*/
DO $$
BEGIN
    IF to_regclass('public.card_asset') IS NULL THEN
        RAISE EXCEPTION
            'Não foi possível executar a Query 194: a tabela public.card_asset não existe.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'card_asset'
          AND column_name = 'storage_provider'
    ) THEN
        RAISE EXCEPTION
            'Não foi possível executar a Query 194: a coluna card_asset.storage_provider não existe.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'card_asset'
          AND column_name = 'storage_path'
    ) THEN
        RAISE EXCEPTION
            'Não foi possível executar a Query 194: a coluna card_asset.storage_path não existe.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'card_asset'
          AND column_name = 'external_url'
    ) THEN
        RAISE EXCEPTION
            'Não foi possível executar a Query 194: a coluna card_asset.external_url não existe.';
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
2. Normalização dos valores existentes
-------------------------------------------------------------------------------
*/
UPDATE public.card_asset
SET storage_provider =
    CASE
        WHEN storage_provider IS NULL
             OR BTRIM(storage_provider) = ''
        THEN
            CASE
                WHEN external_url IS NOT NULL
                     AND BTRIM(external_url) <> ''
                THEN 'EXTERNAL'
                ELSE 'LOCAL'
            END
        WHEN UPPER(BTRIM(storage_provider)) IN (
            'SUPABASE',
            'SUPABASE STORAGE'
        )
        THEN 'SUPABASE'
        WHEN UPPER(BTRIM(storage_provider)) IN (
            'S3',
            'AWS S3',
            'AMAZON S3'
        )
        THEN 'S3'
        WHEN UPPER(BTRIM(storage_provider)) IN (
            'R2',
            'CLOUDFLARE R2'
        )
        THEN 'R2'
        WHEN UPPER(BTRIM(storage_provider)) IN (
            'LOCAL',
            'LOCAL STORAGE'
        )
        THEN 'LOCAL'
        WHEN UPPER(BTRIM(storage_provider)) IN (
            'EXTERNAL',
            'URL',
            'EXTERNAL URL'
        )
        THEN 'EXTERNAL'
        ELSE UPPER(BTRIM(storage_provider))
    END;

/*
-------------------------------------------------------------------------------
3. Validação dos dados anteriores à criação das constraints
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    invalid_provider_count BIGINT;
    invalid_location_count BIGINT;
BEGIN
    SELECT COUNT(*)
    INTO invalid_provider_count
    FROM public.card_asset
    WHERE storage_provider NOT IN (
        'SUPABASE',
        'S3',
        'R2',
        'LOCAL',
        'EXTERNAL'
    );

    IF invalid_provider_count > 0 THEN
        RAISE EXCEPTION
            'Não foi possível executar a Query 194: existem % registros com storage_provider não reconhecido.',
            invalid_provider_count;
    END IF;

    SELECT COUNT(*)
    INTO invalid_location_count
    FROM public.card_asset
    WHERE
        (
            storage_provider = 'EXTERNAL'
            AND (
                external_url IS NULL
                OR BTRIM(external_url) = ''
            )
        )
        OR
        (
            storage_provider IN (
                'SUPABASE',
                'S3',
                'R2',
                'LOCAL'
            )
            AND (
                storage_path IS NULL
                OR BTRIM(storage_path) = ''
            )
        );

    IF invalid_location_count > 0 THEN
        RAISE EXCEPTION
            'Não foi possível executar a Query 194: existem % registros incompatíveis com as regras de localização do storage_provider.',
            invalid_location_count;
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
4. Obrigatoriedade de storage_provider
-------------------------------------------------------------------------------
*/
ALTER TABLE public.card_asset
    ALTER COLUMN storage_provider SET NOT NULL;

/*
-------------------------------------------------------------------------------
5. Constraint dos provedores permitidos
-------------------------------------------------------------------------------
*/
ALTER TABLE public.card_asset
    DROP CONSTRAINT IF EXISTS ck_card_asset_storage_provider;

ALTER TABLE public.card_asset
    ADD CONSTRAINT ck_card_asset_storage_provider
    CHECK (
        storage_provider IN (
            'SUPABASE',
            'S3',
            'R2',
            'LOCAL',
            'EXTERNAL'
        )
    );

/*
-------------------------------------------------------------------------------
6. Compatibilidade entre provedor e localização
-------------------------------------------------------------------------------
*/
ALTER TABLE public.card_asset
    DROP CONSTRAINT IF EXISTS ck_card_asset_storage_provider_location;

ALTER TABLE public.card_asset
    ADD CONSTRAINT ck_card_asset_storage_provider_location
    CHECK (
        (
            storage_provider = 'EXTERNAL'
            AND external_url IS NOT NULL
            AND BTRIM(external_url) <> ''
        )
        OR
        (
            storage_provider IN (
                'SUPABASE',
                'S3',
                'R2',
                'LOCAL'
            )
            AND storage_path IS NOT NULL
            AND BTRIM(storage_path) <> ''
        )
    );

/*
-------------------------------------------------------------------------------
7. Comentários
-------------------------------------------------------------------------------
*/
COMMENT ON COLUMN public.card_asset.storage_provider IS
'Provedor responsável pela localização do ativo. Valores permitidos: SUPABASE, S3, R2, LOCAL e EXTERNAL.';

COMMENT ON CONSTRAINT ck_card_asset_storage_provider
ON public.card_asset IS
'Restringe storage_provider aos provedores homologados pelo Project Mimikyu.';

COMMENT ON CONSTRAINT ck_card_asset_storage_provider_location
ON public.card_asset IS
'Exige external_url para ativos EXTERNAL e storage_path para ativos armazenados em SUPABASE, S3, R2 ou LOCAL.';

COMMIT;
