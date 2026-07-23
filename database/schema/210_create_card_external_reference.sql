/*
Project Mimikyu
Query 210 - Create Card External Reference
Pré-requisitos: Queries 180, 200 e 985.
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

    CONSTRAINT uq_card_external_reference_card_source
        UNIQUE (card_id, asset_source_id),
    CONSTRAINT uq_card_external_reference_source_external
        UNIQUE (asset_source_id, external_card_id),

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
    'Relaciona cartas internas aos identificadores e URLs das fontes externas.';

COMMENT ON COLUMN public.card_external_reference.external_card_id IS
    'Identificador único da carta na fonte externa.';
COMMENT ON COLUMN public.card_external_reference.external_set_id IS
    'Identificador da coleção na fonte externa.';
COMMENT ON COLUMN public.card_external_reference.source_number IS
    'Número da carta conforme informado pela fonte externa.';
COMMENT ON COLUMN public.card_external_reference.source_url IS
    'URL do registro ou página da carta na fonte externa.';
COMMENT ON COLUMN public.card_external_reference.image_source_url IS
    'URL utilizada para aquisição automática da imagem original.';
COMMENT ON COLUMN public.card_external_reference.metadata IS
    'Metadados adicionais da fonte externa em formato JSON.';

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
              'uq_card_external_reference_card_source'
          AND contype = 'u'
    ) THEN
        RAISE EXCEPTION
            'Query 210 falhou: unicidade card/source ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid =
              'public.card_external_reference'::regclass
          AND conname =
              'uq_card_external_reference_source_external'
          AND contype = 'u'
    ) THEN
        RAISE EXCEPTION
            'Query 210 falhou: unicidade source/external ausente.';
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
