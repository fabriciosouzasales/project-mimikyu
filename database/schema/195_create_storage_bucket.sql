/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 195 - Create Storage Bucket
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18

Descrição:
Cria o catálogo de buckets utilizados para armazenamento dos ativos digitais.
A entidade storage_bucket representa a camada de infraestrutura responsável
por organizar os arquivos dentro de um provedor de Object Storage.

Modelo:
Storage Provider
    └── Storage Bucket
            └── Object Path

Exemplo:
storage_provider = SUPABASE
code             = card-front
storage_path     = ME1/001.png

Provedores homologados:
- SUPABASE
- S3
- R2
- LOCAL
- EXTERNAL

Regras:
- cada bucket possui um código único;
- o código utiliza letras minúsculas, números e hífens;
- o nome não pode estar vazio;
- o provedor deve pertencer ao domínio homologado;
- bucket_order deve ser positivo e único;
- is_public informa se os objetos podem ser acessados por URL pública;
- RLS deve permanecer habilitado.

Pré-requisitos:
- Infraestrutura que disponibilize gen_random_uuid().
===============================================================================
*/

BEGIN;

/*
-------------------------------------------------------------------------------
1. Criação da tabela
-------------------------------------------------------------------------------
*/
CREATE TABLE IF NOT EXISTS public.storage_bucket (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    code TEXT NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    storage_provider TEXT NOT NULL,
    bucket_order INTEGER NOT NULL,
    is_public BOOLEAN NOT NULL DEFAULT FALSE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_storage_bucket_code
        UNIQUE (code),

    CONSTRAINT uq_storage_bucket_order
        UNIQUE (bucket_order),

    CONSTRAINT ck_storage_bucket_code_not_blank
        CHECK (
            BTRIM(code) <> ''
        ),

    CONSTRAINT ck_storage_bucket_code_format
        CHECK (
            code ~ '^[a-z0-9]+(-[a-z0-9]+)*$'
        ),

    CONSTRAINT ck_storage_bucket_name_not_blank
        CHECK (
            BTRIM(name) <> ''
        ),

    CONSTRAINT ck_storage_bucket_description_not_blank
        CHECK (
            description IS NULL
            OR BTRIM(description) <> ''
        ),

    CONSTRAINT ck_storage_bucket_provider
        CHECK (
            storage_provider IN (
                'SUPABASE',
                'S3',
                'R2',
                'LOCAL',
                'EXTERNAL'
            )
        ),

    CONSTRAINT ck_storage_bucket_order_positive
        CHECK (
            bucket_order > 0
        )
);

/*
-------------------------------------------------------------------------------
2. Índices
-------------------------------------------------------------------------------
*/
CREATE INDEX IF NOT EXISTS ix_storage_bucket_storage_provider
    ON public.storage_bucket (storage_provider);

CREATE INDEX IF NOT EXISTS ix_storage_bucket_is_active
    ON public.storage_bucket (is_active);

CREATE INDEX IF NOT EXISTS ix_storage_bucket_provider_active
    ON public.storage_bucket (
        storage_provider,
        is_active
    );

/*
-------------------------------------------------------------------------------
3. Comentários
-------------------------------------------------------------------------------
*/
COMMENT ON TABLE public.storage_bucket IS
'Catálogo de buckets utilizados para armazenar os ativos digitais do Project Mimikyu.';

COMMENT ON COLUMN public.storage_bucket.id IS
'Identificador técnico único do bucket.';

COMMENT ON COLUMN public.storage_bucket.code IS
'Código técnico e estável do bucket no provedor de armazenamento, como card-front, artwork ou card-back.';

COMMENT ON COLUMN public.storage_bucket.name IS
'Nome descritivo do bucket utilizado nas interfaces administrativas.';

COMMENT ON COLUMN public.storage_bucket.description IS
'Descrição funcional dos arquivos armazenados no bucket.';

COMMENT ON COLUMN public.storage_bucket.storage_provider IS
'Provedor de Object Storage no qual o bucket está hospedado. Valores permitidos: SUPABASE, S3, R2, LOCAL e EXTERNAL.';

COMMENT ON COLUMN public.storage_bucket.bucket_order IS
'Ordem editorial de apresentação do bucket no sistema.';

COMMENT ON COLUMN public.storage_bucket.is_public IS
'Indica se os objetos armazenados no bucket podem ser acessados por URL pública.';

COMMENT ON COLUMN public.storage_bucket.is_active IS
'Indica se o bucket está disponível para associação a novos ativos.';

COMMENT ON COLUMN public.storage_bucket.created_at IS
'Data e hora de criação do registro.';

COMMENT ON COLUMN public.storage_bucket.updated_at IS
'Data e hora da última atualização do registro.';

COMMENT ON CONSTRAINT ck_storage_bucket_code_format
ON public.storage_bucket IS
'Permite códigos formados por letras minúsculas, números e hífens, sem hífen no início ou no final.';

COMMENT ON CONSTRAINT ck_storage_bucket_provider
ON public.storage_bucket IS
'Restringe o bucket aos provedores de armazenamento homologados pelo Project Mimikyu.';

/*
-------------------------------------------------------------------------------
4. Row Level Security
-------------------------------------------------------------------------------
*/
ALTER TABLE public.storage_bucket
    ENABLE ROW LEVEL SECURITY;

COMMIT;
