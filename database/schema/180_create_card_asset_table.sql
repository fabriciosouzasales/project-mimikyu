/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 180 - Create Card Asset Table
Versão......: 1.1
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18

Descrição resumida:
Cria a tabela card_asset, responsável por registrar os ativos digitais
associados diretamente a uma Card.

Descrição:
A entidade card_asset representa arquivos ou referências digitais utilizados
para exibir uma Card no sistema.

A imagem pertence à Card e não à Card Variant. Portanto, esta tabela não possui
relacionamento com card_variant.

Exemplos de ativos:
- imagem completa da frente da Card;
- ilustração isolada da Card;
- imagem do verso da Card.

Estrutura:
- id
- card_id
- asset_type_id
- source_code
- source_reference
- storage_provider
- storage_path
- external_url
- mime_type
- file_extension
- file_size_bytes
- width_pixels
- height_pixels
- checksum_sha256
- is_primary
- asset_order
- is_active
- created_at
- updated_at

Regras de Negócio:
- Cada Card Asset deve pertencer a uma Card.
- Cada Card Asset deve possuir um Card Asset Type.
- Card e Card Asset Type devem pertencer ao mesmo Game.
- A consistência entre Games será garantida pela Query 181.
- O ativo deve possuir storage_path ou external_url.
- asset_order deve ser maior que zero.
- asset_order deve ser único dentro da combinação Card + Card Asset Type.
- Pode existir no máximo um ativo principal para cada combinação
  Card + Card Asset Type.
- Dimensões, quando informadas, devem ser maiores que zero.
- file_size_bytes, quando informado, não pode ser negativo.
- checksum_sha256, quando informado, deve possuir 64 caracteres hexadecimais.
- Exclusões de Cards ou Card Asset Types referenciados devem ser impedidas.
- Row Level Security deve permanecer habilitado.

Pré-requisitos:
- Query 140 - Create Card Table.
- Query 170 - Create Card Asset Type Table.
- Função public.set_updated_at() criada na infraestrutura.

===============================================================================

NOTA DE DOCUMENTAÇÃO: esta Query foi recebida com o cabeçalho já no padrão
STD-001 (nenhuma reformatação foi necessária). Fica registrado, para
verificação futura, que a tabela public.card_asset já existia fisicamente
antes desta Query (confirmado via Table Editor do Supabase, ver
04-domain-model.md/05-modelo-de-dados.md — estrutura física real diverge
desta proposta em pelo menos duas colunas: possui storage_bucket_id e
language_id, ausentes aqui, e não possui storage_provider). Como o comando
abaixo usa CREATE TABLE IF NOT EXISTS, é tecnicamente esperado que ele não
tenha alterado a estrutura já existente da tabela — Fabrício confirmou a
execução sem erro, mas essa confirmação por si só não garante que as novas
colunas/constraints/índices abaixo estejam de fato aplicados fisicamente.
Sinalizado, não resolvido unilateralmente.
===============================================================================
*/

BEGIN;

CREATE TABLE IF NOT EXISTS public.card_asset (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    card_id UUID NOT NULL,

    asset_type_id UUID NOT NULL,

    source_code TEXT,

    source_reference TEXT,

    storage_provider TEXT,

    storage_path TEXT,

    external_url TEXT,

    mime_type TEXT,

    file_extension TEXT,

    file_size_bytes BIGINT,

    width_pixels INTEGER,

    height_pixels INTEGER,

    checksum_sha256 TEXT,

    is_primary BOOLEAN NOT NULL DEFAULT FALSE,

    asset_order INTEGER NOT NULL DEFAULT 1,

    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_card_asset_card
        FOREIGN KEY (card_id)
        REFERENCES public.card (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT fk_card_asset_asset_type
        FOREIGN KEY (asset_type_id)
        REFERENCES public.card_asset_type (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT uq_card_asset_card_type_order
        UNIQUE (card_id, asset_type_id, asset_order),

    CONSTRAINT ck_card_asset_location_required
        CHECK (
            NULLIF(BTRIM(storage_path), '') IS NOT NULL
            OR NULLIF(BTRIM(external_url), '') IS NOT NULL
        ),

    CONSTRAINT ck_card_asset_source_code_not_blank
        CHECK (
            source_code IS NULL
            OR BTRIM(source_code) <> ''
        ),

    CONSTRAINT ck_card_asset_source_reference_not_blank
        CHECK (
            source_reference IS NULL
            OR BTRIM(source_reference) <> ''
        ),

    CONSTRAINT ck_card_asset_storage_provider_not_blank
        CHECK (
            storage_provider IS NULL
            OR BTRIM(storage_provider) <> ''
        ),

    CONSTRAINT ck_card_asset_storage_path_not_blank
        CHECK (
            storage_path IS NULL
            OR BTRIM(storage_path) <> ''
        ),

    CONSTRAINT ck_card_asset_external_url_not_blank
        CHECK (
            external_url IS NULL
            OR BTRIM(external_url) <> ''
        ),

    CONSTRAINT ck_card_asset_mime_type_not_blank
        CHECK (
            mime_type IS NULL
            OR BTRIM(mime_type) <> ''
        ),

    CONSTRAINT ck_card_asset_file_extension_not_blank
        CHECK (
            file_extension IS NULL
            OR BTRIM(file_extension) <> ''
        ),

    CONSTRAINT ck_card_asset_file_size_nonnegative
        CHECK (
            file_size_bytes IS NULL
            OR file_size_bytes >= 0
        ),

    CONSTRAINT ck_card_asset_width_positive
        CHECK (
            width_pixels IS NULL
            OR width_pixels > 0
        ),

    CONSTRAINT ck_card_asset_height_positive
        CHECK (
            height_pixels IS NULL
            OR height_pixels > 0
        ),

    CONSTRAINT ck_card_asset_checksum_sha256_format
        CHECK (
            checksum_sha256 IS NULL
            OR checksum_sha256 ~ '^[A-Fa-f0-9]{64}$'
        ),

    CONSTRAINT ck_card_asset_order_positive
        CHECK (asset_order > 0)
);


COMMENT ON TABLE public.card_asset IS
'Registra ativos digitais associados diretamente a uma Card, sem relacionamento com Card Variant.';

COMMENT ON COLUMN public.card_asset.id IS
'Identificador técnico único do Card Asset.';

COMMENT ON COLUMN public.card_asset.card_id IS
'Card editorial representada pelo ativo digital.';

COMMENT ON COLUMN public.card_asset.asset_type_id IS
'Tipo semântico do ativo digital associado à Card.';

COMMENT ON COLUMN public.card_asset.source_code IS
'Código da fonte de origem do ativo digital.';

COMMENT ON COLUMN public.card_asset.source_reference IS
'Referência do ativo na fonte de origem.';

COMMENT ON COLUMN public.card_asset.storage_provider IS
'Provedor utilizado para armazenamento do arquivo.';

COMMENT ON COLUMN public.card_asset.storage_path IS
'Caminho interno do arquivo no provedor de armazenamento.';

COMMENT ON COLUMN public.card_asset.external_url IS
'Endereço externo do ativo quando o arquivo não estiver armazenado internamente.';

COMMENT ON COLUMN public.card_asset.mime_type IS
'Tipo MIME do arquivo, como image/webp ou image/jpeg.';

COMMENT ON COLUMN public.card_asset.file_extension IS
'Extensão do arquivo, como webp, jpg ou png.';

COMMENT ON COLUMN public.card_asset.file_size_bytes IS
'Tamanho do arquivo em bytes, quando conhecido.';

COMMENT ON COLUMN public.card_asset.width_pixels IS
'Largura da imagem em pixels, quando aplicável.';

COMMENT ON COLUMN public.card_asset.height_pixels IS
'Altura da imagem em pixels, quando aplicável.';

COMMENT ON COLUMN public.card_asset.checksum_sha256 IS
'Checksum SHA-256 utilizado para validação de integridade do arquivo.';

COMMENT ON COLUMN public.card_asset.is_primary IS
'Indica se este é o ativo principal da combinação Card + Card Asset Type.';

COMMENT ON COLUMN public.card_asset.asset_order IS
'Ordem de apresentação dos ativos dentro da combinação Card + Card Asset Type.';

COMMENT ON COLUMN public.card_asset.is_active IS
'Indica se o ativo está disponível para utilização.';

COMMENT ON COLUMN public.card_asset.created_at IS
'Data e hora de criação do registro.';

COMMENT ON COLUMN public.card_asset.updated_at IS
'Data e hora da última atualização do registro.';


-- Garante no máximo um ativo principal por Card + Card Asset Type.
CREATE UNIQUE INDEX IF NOT EXISTS uq_card_asset_one_primary_per_card_type
    ON public.card_asset (card_id, asset_type_id)
    WHERE is_primary = TRUE;


-- Impede a repetição do mesmo caminho interno para o mesmo tipo de ativo.
CREATE UNIQUE INDEX IF NOT EXISTS uq_card_asset_card_type_storage_path
    ON public.card_asset (card_id, asset_type_id, storage_path)
    WHERE storage_path IS NOT NULL;


-- Impede a repetição da mesma URL externa para o mesmo tipo de ativo.
CREATE UNIQUE INDEX IF NOT EXISTS uq_card_asset_card_type_external_url
    ON public.card_asset (card_id, asset_type_id, external_url)
    WHERE external_url IS NOT NULL;


-- Índices para relacionamentos e consultas frequentes.
CREATE INDEX IF NOT EXISTS ix_card_asset_card_id
    ON public.card_asset (card_id);

CREATE INDEX IF NOT EXISTS ix_card_asset_asset_type_id
    ON public.card_asset (asset_type_id);

CREATE INDEX IF NOT EXISTS ix_card_asset_source_code
    ON public.card_asset (source_code);

CREATE INDEX IF NOT EXISTS ix_card_asset_is_active
    ON public.card_asset (is_active);


ALTER TABLE public.card_asset ENABLE ROW LEVEL SECURITY;

COMMIT;
