/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 200 - Create Asset Source
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18

Descrição:
Cria o catálogo public.asset_source.

O catálogo identifica as fontes externas utilizadas para obtenção de
metadados e arquivos digitais das cartas, mantendo separadas:
- a origem do arquivo;
- a localização definitiva no Supabase Storage.

Exemplos de fontes:
- Pokémon TCG API;
- TCGdex;
- datasets estruturados;
- importações manuais controladas.

Princípio arquitetural:
A fonte externa serve apenas para aquisição e rastreabilidade.
Depois da importação, o arquivo definitivo permanece internalizado no
Supabase Storage e é referenciado por public.card_asset.storage_path.

Pré-requisitos:
- Query 197 - Integrate Storage Bucket into Card Asset
- Query 980 - Validate Card Asset

Próximas migrations:
- Query 201 - Asset Source Triggers
- Query 900 - Seed Asset Source
- Query 985 - Validate Asset Source
===============================================================================
*/

BEGIN;

/*
-------------------------------------------------------------------------------
1. Proteção contra criação sobre objeto incompatível
-------------------------------------------------------------------------------
*/
DO $$
BEGIN
    IF to_regclass('public.asset_source') IS NOT NULL THEN
        RAISE EXCEPTION
            'Query 200 interrompida: public.asset_source já existe.';
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
2. Criação da tabela
-------------------------------------------------------------------------------
*/
CREATE TABLE public.asset_source
(
    id UUID
        PRIMARY KEY
        DEFAULT gen_random_uuid(),

    code TEXT
        NOT NULL,
    name TEXT
        NOT NULL,
    source_type TEXT
        NOT NULL,

    base_url TEXT,
    api_base_url TEXT,
    documentation_url TEXT,
    terms_url TEXT,
    attribution_text TEXT,

    supports_api BOOLEAN
        NOT NULL
        DEFAULT FALSE,
    supports_bulk_download BOOLEAN
        NOT NULL
        DEFAULT FALSE,
    is_active BOOLEAN
        NOT NULL
        DEFAULT TRUE,
    source_order INTEGER
        NOT NULL,

    created_at TIMESTAMPTZ
        NOT NULL
        DEFAULT NOW(),
    updated_at TIMESTAMPTZ
        NOT NULL
        DEFAULT NOW(),

    CONSTRAINT uq_asset_source_code
        UNIQUE (code),
    CONSTRAINT uq_asset_source_order
        UNIQUE (source_order),

    CONSTRAINT ck_asset_source_code
        CHECK (
            code = UPPER(code)
            AND code ~ '^[A-Z][A-Z0-9_]*$'
        ),
    CONSTRAINT ck_asset_source_name
        CHECK (
            BTRIM(name) <> ''
        ),
    CONSTRAINT ck_asset_source_type
        CHECK (
            source_type IN (
                'API',
                'DATASET',
                'MANUAL'
            )
        ),
    CONSTRAINT ck_asset_source_base_url
        CHECK (
            base_url IS NULL
            OR (
                BTRIM(base_url) <> ''
                AND base_url ~* '^https://'
            )
        ),
    CONSTRAINT ck_asset_source_api_base_url
        CHECK (
            api_base_url IS NULL
            OR (
                BTRIM(api_base_url) <> ''
                AND api_base_url ~* '^https://'
            )
        ),
    CONSTRAINT ck_asset_source_documentation_url
        CHECK (
            documentation_url IS NULL
            OR (
                BTRIM(documentation_url) <> ''
                AND documentation_url ~* '^https://'
            )
        ),
    CONSTRAINT ck_asset_source_terms_url
        CHECK (
            terms_url IS NULL
            OR (
                BTRIM(terms_url) <> ''
                AND terms_url ~* '^https://'
            )
        ),
    CONSTRAINT ck_asset_source_attribution_text
        CHECK (
            attribution_text IS NULL
            OR BTRIM(attribution_text) <> ''
        ),
    CONSTRAINT ck_asset_source_order
        CHECK (
            source_order > 0
        ),
    CONSTRAINT ck_asset_source_api_configuration
        CHECK (
            supports_api = FALSE
            OR api_base_url IS NOT NULL
        ),
    CONSTRAINT ck_asset_source_manual_configuration
        CHECK (
            source_type <> 'MANUAL'
            OR (
                supports_api = FALSE
                AND supports_bulk_download = FALSE
            )
        )
);

/*
-------------------------------------------------------------------------------
3. Índices
-------------------------------------------------------------------------------
*/
CREATE INDEX ix_asset_source_active_order
    ON public.asset_source (
        is_active,
        source_order
    );

CREATE INDEX ix_asset_source_type
    ON public.asset_source (
        source_type
    );

/*
-------------------------------------------------------------------------------
4. Row Level Security
-------------------------------------------------------------------------------
*/
ALTER TABLE public.asset_source
    ENABLE ROW LEVEL SECURITY;

/*
-------------------------------------------------------------------------------
5. Comentários
-------------------------------------------------------------------------------
*/
COMMENT ON TABLE public.asset_source IS
    'Catálogo das fontes externas utilizadas para aquisição de metadados e ativos digitais das cartas.';

COMMENT ON COLUMN public.asset_source.id IS
    'Identificador único da fonte externa.';
COMMENT ON COLUMN public.asset_source.code IS
    'Código técnico estável e único da fonte.';
COMMENT ON COLUMN public.asset_source.name IS
    'Nome de exibição da fonte externa.';
COMMENT ON COLUMN public.asset_source.source_type IS
    'Tipo da fonte: API, DATASET ou MANUAL.';
COMMENT ON COLUMN public.asset_source.base_url IS
    'Endereço principal da fonte externa.';
COMMENT ON COLUMN public.asset_source.api_base_url IS
    'Endereço-base da API utilizada pela rotina de integração.';
COMMENT ON COLUMN public.asset_source.documentation_url IS
    'Endereço da documentação técnica da fonte.';
COMMENT ON COLUMN public.asset_source.terms_url IS
    'Endereço dos termos de uso ou regras aplicáveis à fonte.';
COMMENT ON COLUMN public.asset_source.attribution_text IS
    'Texto de atribuição exigido ou recomendado pela fonte.';
COMMENT ON COLUMN public.asset_source.supports_api IS
    'Indica se a fonte disponibiliza uma API para integração automatizada.';
COMMENT ON COLUMN public.asset_source.supports_bulk_download IS
    'Indica se a fonte oferece dataset ou mecanismo de download em lote.';
COMMENT ON COLUMN public.asset_source.is_active IS
    'Indica se a fonte pode ser utilizada em novas importações.';
COMMENT ON COLUMN public.asset_source.source_order IS
    'Ordem de prioridade e apresentação da fonte.';
COMMENT ON COLUMN public.asset_source.created_at IS
    'Data e hora de criação do registro.';
COMMENT ON COLUMN public.asset_source.updated_at IS
    'Data e hora da última atualização do registro.';

/*
-------------------------------------------------------------------------------
6. Validação estrutural pós-criação
-------------------------------------------------------------------------------
*/
DO $$
BEGIN
    IF to_regclass('public.asset_source') IS NULL THEN
        RAISE EXCEPTION
            'Query 200 falhou: public.asset_source não foi criada.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint constraint_data
        WHERE constraint_data.conrelid =
              'public.asset_source'::regclass
          AND constraint_data.contype = 'p'
    ) THEN
        RAISE EXCEPTION
            'Query 200 falhou: a primary key de public.asset_source não foi criada.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint constraint_data
        WHERE constraint_data.conrelid =
              'public.asset_source'::regclass
          AND constraint_data.conname =
              'uq_asset_source_code'
          AND constraint_data.contype = 'u'
    ) THEN
        RAISE EXCEPTION
            'Query 200 falhou: uq_asset_source_code não foi criada.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint constraint_data
        WHERE constraint_data.conrelid =
              'public.asset_source'::regclass
          AND constraint_data.conname =
              'uq_asset_source_order'
          AND constraint_data.contype = 'u'
    ) THEN
        RAISE EXCEPTION
            'Query 200 falhou: uq_asset_source_order não foi criada.';
    END IF;

    IF to_regclass(
        'public.ix_asset_source_active_order'
    ) IS NULL THEN
        RAISE EXCEPTION
            'Query 200 falhou: ix_asset_source_active_order não foi criado.';
    END IF;

    IF to_regclass(
        'public.ix_asset_source_type'
    ) IS NULL THEN
        RAISE EXCEPTION
            'Query 200 falhou: ix_asset_source_type não foi criado.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_class class_data
        WHERE class_data.oid =
              'public.asset_source'::regclass
          AND class_data.relrowsecurity = TRUE
    ) THEN
        RAISE EXCEPTION
            'Query 200 falhou: Row Level Security não foi habilitado.';
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
7. Resultado
-------------------------------------------------------------------------------
*/
DO $$
BEGIN
    RAISE NOTICE
        'QUERY 200 CONCLUÍDA: ASSET SOURCE CRIADA';
END;
$$;

COMMIT;
