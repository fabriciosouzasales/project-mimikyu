/*
Project Mimikyu
Query 900 - Seed Asset Source
Pré-requisitos: Queries 200 e 201.
*/

BEGIN;

INSERT INTO public.asset_source
(
    code,
    name,
    source_type,
    base_url,
    api_base_url,
    documentation_url,
    terms_url,
    attribution_text,
    supports_api,
    supports_bulk_download,
    is_active,
    source_order
)
VALUES
(
    'POKEMON_TCG_API',
    'Pokémon TCG API',
    'API',
    'https://pokemontcg.io',
    'https://api.pokemontcg.io/v2',
    'https://docs.pokemontcg.io',
    'https://dev.pokemontcg.io/terms',
    'Data and images provided by the Pokémon TCG API.',
    TRUE,
    TRUE,
    TRUE,
    1
),
(
    'TCGDEX',
    'TCGdex',
    'API',
    'https://tcgdex.dev',
    'https://api.tcgdex.net/v2',
    'https://tcgdex.dev',
    NULL,
    'Data and images provided by TCGdex.',
    TRUE,
    FALSE,
    TRUE,
    2
),
(
    'MANUAL',
    'Manual Controlled Import',
    'MANUAL',
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    FALSE,
    FALSE,
    TRUE,
    99
)
ON CONFLICT (code) DO UPDATE
SET
    name = EXCLUDED.name,
    source_type = EXCLUDED.source_type,
    base_url = EXCLUDED.base_url,
    api_base_url = EXCLUDED.api_base_url,
    documentation_url = EXCLUDED.documentation_url,
    terms_url = EXCLUDED.terms_url,
    attribution_text = EXCLUDED.attribution_text,
    supports_api = EXCLUDED.supports_api,
    supports_bulk_download = EXCLUDED.supports_bulk_download,
    is_active = EXCLUDED.is_active,
    source_order = EXCLUDED.source_order;

DO $$
DECLARE
    missing_codes TEXT;
BEGIN
    SELECT STRING_AGG(required_code, ', ')
    INTO missing_codes
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

    IF missing_codes IS NOT NULL THEN
        RAISE EXCEPTION
            'Query 900 falhou. Fontes ausentes: %',
            missing_codes;
    END IF;

    IF (
        SELECT COUNT(*)
        FROM public.asset_source
        WHERE code IN (
            'POKEMON_TCG_API',
            'TCGDEX',
            'MANUAL'
        )
    ) <> 3 THEN
        RAISE EXCEPTION
            'Query 900 falhou: quantidade inesperada de fontes.';
    END IF;

    RAISE NOTICE
        'QUERY 900 CONCLUÍDA: 3 FONTES CADASTRADAS';
END;
$$;

COMMIT;
