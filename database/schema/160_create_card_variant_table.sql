/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 160 - Create Card Variant Table
Versão......: 1.0
Status......: CANÔNICA
Data........: 2026-07-18

Descrição resumida:
Cria a tabela card_variant, responsável por representar cada variante
colecionável oficialmente existente para uma Card.

Descrição:
A entidade card_variant relaciona uma Card a um Card Variant Type.

Exemplos:
- ME1-001 + STANDARD
- ME1-001 + REVERSE_HOLO
- ME2.5-025 + POKE_BALL_REVERSE

Esta tabela pertence ao Catálogo Editorial. Ela não representa uma cópia física
possuída pelo usuário. As cópias físicas serão registradas posteriormente na
camada de inventário e deverão referenciar uma Card Variant.

Estrutura:
- id
- card_id
- variant_type_id
- variant_order
- is_default
- created_at
- updated_at

Regras de Negócio:
- Cada combinação Card + Card Variant Type deve ser única.
- variant_order deve ser único dentro da Card.
- variant_order deve ser maior que zero.
- Uma Card pode possuir no máximo uma variante marcada como padrão.
- A existência de pelo menos uma variante padrão por Card será validada no
  processo de carga e na Query 960, após a execução do Seed 860.
- Card e Card Variant Type devem pertencer ao mesmo Game.
- A consistência entre Games será garantida pela Query 161.
- Exclusões de Cards ou Card Variant Types referenciados devem ser impedidas.
- Row Level Security deve permanecer habilitado.

Pré-requisitos:
- Query 140 - Create Card Table.
- Query 150 - Create Card Variant Type Table.
- Função public.set_updated_at() criada na infraestrutura.

===============================================================================
*/

BEGIN;

CREATE TABLE IF NOT EXISTS public.card_variant (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    card_id UUID NOT NULL,

    variant_type_id UUID NOT NULL,

    variant_order INTEGER NOT NULL,

    is_default BOOLEAN NOT NULL DEFAULT FALSE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_card_variant_card
        FOREIGN KEY (card_id)
        REFERENCES public.card (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT fk_card_variant_variant_type
        FOREIGN KEY (variant_type_id)
        REFERENCES public.card_variant_type (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT uq_card_variant_card_type
        UNIQUE (card_id, variant_type_id),

    CONSTRAINT uq_card_variant_card_order
        UNIQUE (card_id, variant_order),

    CONSTRAINT ck_card_variant_order_positive
        CHECK (variant_order > 0)
);

COMMENT ON TABLE public.card_variant IS
'Representa uma variante colecionável oficialmente existente para uma Card.';

COMMENT ON COLUMN public.card_variant.id IS
'Identificador técnico único da Card Variant.';

COMMENT ON COLUMN public.card_variant.card_id IS
'Card editorial à qual a variante pertence.';

COMMENT ON COLUMN public.card_variant.variant_type_id IS
'Tipo de variante colecionável aplicado à Card.';

COMMENT ON COLUMN public.card_variant.variant_order IS
'Ordem de apresentação da variante dentro da Card.';

COMMENT ON COLUMN public.card_variant.is_default IS
'Indica se esta é a variante editorial principal da Card.';

COMMENT ON COLUMN public.card_variant.created_at IS
'Data e hora de criação do registro.';

COMMENT ON COLUMN public.card_variant.updated_at IS
'Data e hora da última atualização do registro.';


-- Garante no máximo uma variante padrão por Card.
CREATE UNIQUE INDEX IF NOT EXISTS uq_card_variant_one_default_per_card
    ON public.card_variant (card_id)
    WHERE is_default = TRUE;


-- Índices para relacionamentos e consultas frequentes.
CREATE INDEX IF NOT EXISTS ix_card_variant_card_id
    ON public.card_variant (card_id);

CREATE INDEX IF NOT EXISTS ix_card_variant_variant_type_id
    ON public.card_variant (variant_type_id);


ALTER TABLE public.card_variant ENABLE ROW LEVEL SECURITY;

COMMIT;
