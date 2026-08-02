/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 210 - Create Card External Reference
Versão......: 2.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: (v1.0 original), 2026-08-02 (v2.0)

Pré-requisitos: Queries 180, 190 (Language), 200 e 985.

Ampliação de escopo (v2.0, 2026-08-02, Migration 277): `language_id`
adicionado — a v1.0 tratava "referência externa de uma Card" como
independente de idioma (`UNIQUE (card_id, asset_source_id)`), o que
fazia sentido enquanto só o pipeline de imagens em inglês existia de
verdade (`LANGUAGE_CODE` hardcoded em `import-card-assets/index.ts`).
Fabrício pediu suporte real a EN + PT-BR simultaneamente ("os dois
idiomas") depois de notar que a importação automática nunca trazia as
imagens em português — a TCGdex devolve `image`/`name`/outros campos
DIFERENTES por idioma para a MESMA carta (mesmo `id` externo,
confirmado no teste real do Sprint B3.24: `ME1-001` em `en` e `pt-BR`
são o mesmo `external_card_id`, com `image_source_url` diferente).
Sem `language_id`, sincronizar a referência em `pt-BR` depois de já
ter sincronizado em `en` fazia `UPSERT` sobre a MESMA linha (colisão
silenciosa via `ON CONFLICT (card_id, asset_source_id)`), perdendo o
`image_source_url`/`metadata` do idioma anterior — sinalizado como
risco real, não resolvido, desde o próprio teste do Sprint B3.23/
B3.24 ("Discrepância real sinalizada... NÃO resolvida nesta revisão").
Agora cada (card, fonte, idioma) tem sua própria linha:
`uq_card_external_reference_card_source` vira
`uq_card_external_reference_card_source_language` (adiciona
`language_id`); `uq_card_external_reference_source_external` vira
`uq_card_external_reference_source_external_language` pelo mesmo
motivo (o `external_card_id` da TCGdex é o mesmo entre idiomas, então
a unicidade por fonte+identificador externo também precisa do idioma
para não colidir entre as duas linguas da mesma carta). Backfill de
banco já instalado (todas as linhas existentes são de importações em
`en`) e reconciliação de constraints ficam na Migration 277 — esta
Query CANÔNICA é só a forma correta para instalação nova.

Descrição...:
Cria a tabela card_external_reference, que relaciona cada Card
interna aos identificadores e URLs de uma fonte externa
(asset_source, ex.: TCGDEX), agora com o idioma como parte da
identidade da linha — a mesma Card pode ter uma referência externa
por idioma suportado.
================================================================
*/

BEGIN;

DO $$
BEGIN
    IF to_regclass('public.card') IS NULL THEN
        RAISE EXCEPTION 'Query 210 interrompida: public.card não existe.';
    END IF;

    IF to_regclass('public.asset_source') IS NULL THEN
        RAISE EXCEPTION 'Query 210 interrompida: public.asset_source não existe.';
    END IF;

    IF to_regclass('public.language') IS NULL THEN
        RAISE EXCEPTION 'Query 210 interrompida: public.language não existe.';
    END IF;

    IF to_regclass('public.card_external_reference') IS NOT NULL THEN
        RAISE EXCEPTION
            'Query 210 interrompida: public.card_external_reference já existe.';
    END IF;
END;
$$;

CREATE TABLE public.card_external_reference
(
    id UUID
        PRIMARY KEY
        DEFAULT gen_random_uuid(),

    card_id UUID
        NOT NULL,
    asset_source_id UUID
        NOT NULL,
    language_id UUID
        NOT NULL,

    external_card_id TEXT
        NOT NULL,
    external_set_id TEXT,
    source_number TEXT,
    source_url TEXT,
    image_source_url TEXT,
    metadata JSONB
        NOT NULL
        DEFAULT '{}'::JSONB,

    is_active BOOLEAN
        NOT NULL
        DEFAULT TRUE,

    created_at TIMESTAMPTZ
        NOT NULL
        DEFAULT NOW(),
    updated_at TIMESTAMPTZ
        NOT NULL
        DEFAULT NOW(),

    CONSTRAINT fk_card_external_reference_card
        FOREIGN KEY (card_id)
        REFERENCES public.card (id)
        ON DELETE CASCADE,
    CONSTRAINT fk_card_external_reference_asset_source
        FOREIGN KEY (asset_source_id)
        REFERENCES public.asset_source (id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_card_external_reference_language
        FOREIGN KEY (language_id)
        REFERENCES public.language (id)
        ON DELETE RESTRICT,

    CONSTRAINT uq_card_external_reference_card_source_language
        UNIQUE (card_id, asset_source_id, language_id),
    CONSTRAINT uq_card_external_reference_source_external_language
        UNIQUE (asset_source_id, external_card_id, language_id),

    CONSTRAINT ck_card_external_reference_external_card_id
        CHECK (BTRIM(external_card_id) <> ''),
    CONSTRAINT ck_card_external_reference_external_set_id
        CHECK (
            external_set_id IS NULL
            OR BTRIM(external_set_id) <> ''
        ),
    CONSTRAINT ck_card_external_reference_source_number
        CHECK (
            source_number IS NULL
            OR BTRIM(source_number) <> ''
        ),
    CONSTRAINT ck_card_external_reference_source_url
        CHECK (
            source_url IS NULL
            OR (
                BTRIM(source_url) <> ''
                AND source_url ~* '^https://'
            )
        ),
    CONSTRAINT ck_card_external_reference_image_source_url
        CHECK (
            image_source_url IS NULL
            OR (
                BTRIM(image_source_url) <> ''
                AND image_source_url ~* '^https://'
            )
        ),
    CONSTRAINT ck_card_external_reference_metadata
        CHECK (JSONB_TYPEOF(metadata) = 'object')
);

CREATE INDEX ix_card_external_reference_card
    ON public.card_external_reference (card_id);
CREATE INDEX ix_card_external_reference_asset_source
    ON public.card_external_reference (asset_source_id);
CREATE INDEX ix_card_external_reference_language
    ON public.card_external_reference (language_id);
CREATE INDEX ix_card_external_reference_external_set
    ON public.card_external_reference (
        asset_source_id,
        external_set_id
    )
    WHERE external_set_id IS NOT NULL;
CREATE INDEX ix_card_external_reference_source_number
    ON public.card_external_reference (
        asset_source_id,
        external_set_id,
        source_number
    )
    WHERE source_number IS NOT NULL;
CREATE INDEX ix_card_external_reference_active
    ON public.card_external_reference (
        asset_source_id,
        is_active
    );

ALTER TABLE public.card_external_reference
    ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.card_external_reference IS
    'Relaciona cartas internas aos identificadores e URLs das fontes externas, por idioma.';

COMMENT ON COLUMN public.card_external_reference.language_id IS
    'Idioma desta referência externa — a mesma Card pode ter uma linha por idioma suportado (v2.0).';
COMMENT ON COLUMN public.card_external_reference.external_card_id IS
    'Identificador único da carta na fonte externa (estável entre idiomas).';
COMMENT ON COLUMN public.card_external_reference.external_set_id IS
    'Identificador da coleção na fonte externa.';
COMMENT ON COLUMN public.card_external_reference.source_number IS
    'Número da carta conforme informado pela fonte externa.';
COMMENT ON COLUMN public.card_external_reference.source_url IS
    'URL do registro ou página da carta na fonte externa.';
COMMENT ON COLUMN public.card_external_reference.image_source_url IS
    'URL utilizada para aquisição automática da imagem original, específica do idioma desta linha.';
COMMENT ON COLUMN public.card_external_reference.metadata IS
    'Metadados adicionais da fonte externa em formato JSON, específicos do idioma desta linha.';

DO $$
BEGIN
    IF to_regclass('public.card_external_reference') IS NULL THEN
        RAISE EXCEPTION
            'Query 210 falhou: tabela não criada.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid =
              'public.card_external_reference'::regclass
          AND conname =
              'fk_card_external_reference_card'
          AND contype = 'f'
    ) THEN
        RAISE EXCEPTION
            'Query 210 falhou: FK para card ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid =
              'public.card_external_reference'::regclass
          AND conname =
              'fk_card_external_reference_asset_source'
          AND contype = 'f'
    ) THEN
        RAISE EXCEPTION
            'Query 210 falhou: FK para asset_source ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid =
              'public.card_external_reference'::regclass
          AND conname =
              'fk_card_external_reference_language'
          AND contype = 'f'
    ) THEN
        RAISE EXCEPTION
            'Query 210 falhou: FK para language ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid =
              'public.card_external_reference'::regclass
          AND conname =
              'uq_card_external_reference_card_source_language'
          AND contype = 'u'
    ) THEN
        RAISE EXCEPTION
            'Query 210 falhou: unicidade card/source/language ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid =
              'public.card_external_reference'::regclass
          AND conname =
              'uq_card_external_reference_source_external_language'
          AND contype = 'u'
    ) THEN
        RAISE EXCEPTION
            'Query 210 falhou: unicidade source/external/language ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_class
        WHERE oid =
              'public.card_external_reference'::regclass
          AND relrowsecurity = TRUE
    ) THEN
        RAISE EXCEPTION
            'Query 210 falhou: RLS não habilitado.';
    END IF;

    RAISE NOTICE
        'QUERY 210 CONCLUÍDA: CARD EXTERNAL REFERENCE CRIADA';
END;
$$;

COMMIT;
