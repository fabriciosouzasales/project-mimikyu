/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 895 - Seed Storage Bucket
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18

Descrição:
Popula o catálogo inicial de buckets de armazenamento utilizados pelos ativos
digitais do Project Mimikyu.

Buckets iniciais:
- card-front
- artwork
- card-back

Todos os buckets são configurados inicialmente para:
- provedor SUPABASE;
- acesso público;
- utilização ativa.

Os registros desta migration representam o catálogo do banco de dados. Os
buckets físicos correspondentes também deverão ser criados no Supabase Storage.

Pré-requisitos:
- Query 195 - Create Storage Bucket.
- Query 196 - Create Storage Bucket Triggers.
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
    IF to_regclass('public.storage_bucket') IS NULL THEN
        RAISE EXCEPTION
            'Não foi possível executar a Query 895: a tabela public.storage_bucket não existe.';
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
2. Carga inicial dos buckets
-------------------------------------------------------------------------------
*/
INSERT INTO public.storage_bucket (
    code,
    name,
    description,
    storage_provider,
    bucket_order,
    is_public,
    is_active
)
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
ON CONFLICT (code)
DO UPDATE
SET
    name             = EXCLUDED.name,
    description      = EXCLUDED.description,
    storage_provider = EXCLUDED.storage_provider,
    bucket_order     = EXCLUDED.bucket_order,
    is_public        = EXCLUDED.is_public,
    is_active        = EXCLUDED.is_active;

/*
-------------------------------------------------------------------------------
3. Validação da carga
-------------------------------------------------------------------------------
*/
DO $$
DECLARE
    missing_bucket_count INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO missing_bucket_count
    FROM (
        VALUES
            ('card-front'),
            ('artwork'),
            ('card-back')
    ) AS expected_bucket(code)
    WHERE NOT EXISTS (
        SELECT 1
        FROM public.storage_bucket storage_bucket
        WHERE storage_bucket.code = expected_bucket.code
    );

    IF missing_bucket_count > 0 THEN
        RAISE EXCEPTION
            'Não foi possível concluir a Query 895: % buckets esperados não foram cadastrados.',
            missing_bucket_count;
    END IF;
END;
$$;

COMMIT;
