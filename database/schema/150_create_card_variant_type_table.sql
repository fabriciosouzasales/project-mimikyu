/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 150 - Create Card Variant Type Table
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18

Descrição resumida:
Cria a tabela card_variant_type, responsável pelo catálogo de tipos de variante
colecionável permitidos para cada Game.

Descrição:
Card Variant Type representa a classificação de uma variante física ou editorial
de uma Card.

Exemplos para Pokémon TCG:
- STANDARD;
- REVERSE_HOLO;
- POKE_BALL_REVERSE;
- MASTER_BALL_REVERSE;
- PROMO_STAMPED.

Esta entidade não representa uma cópia física e não vincula diretamente uma
variante a uma Card. Essa responsabilidade pertencerá à tabela card_variant.

Hierarquia:
Game
  └── Card Variant Type

Regras de Negócio:
- Cada Card Variant Type pertence a exatamente um Game.
- O code deve ser único dentro do Game.
- O display_order deve ser único dentro do Game.
- O code deve utilizar letras maiúsculas, números e underscore.
- name não pode ser vazio.
- display_order deve ser positivo.
- A exclusão de um Game referenciado deve ser impedida.
- A tabela utiliza UUID como chave primária.
- A tabela utiliza created_at e updated_at.
- O Row Level Security deve permanecer habilitado.

Pré-requisitos:
- Query 000 - Infrastructure.
- Tabela public.game.
- Função public.set_updated_at().

===============================================================================
*/

BEGIN;

CREATE TABLE public.card_variant_type (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    game_id UUID NOT NULL,

    code VARCHAR(50) NOT NULL,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    display_order INTEGER NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_card_variant_type_game
        FOREIGN KEY (game_id)
        REFERENCES public.game (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT uq_card_variant_type_game_code
        UNIQUE (game_id, code),

    CONSTRAINT uq_card_variant_type_game_display_order
        UNIQUE (game_id, display_order),

    CONSTRAINT ck_card_variant_type_code_format
        CHECK (code ~ '^[A-Z][A-Z0-9_]*$'),

    CONSTRAINT ck_card_variant_type_name_not_blank
        CHECK (btrim(name) <> ''),

    CONSTRAINT ck_card_variant_type_description_not_blank
        CHECK (description IS NULL OR btrim(description) <> ''),

    CONSTRAINT ck_card_variant_type_display_order_positive
        CHECK (display_order > 0)
);

COMMENT ON TABLE public.card_variant_type IS
    'Catálogo de tipos de variante colecionável permitidos para cada Game.';

COMMENT ON COLUMN public.card_variant_type.id IS
    'Identificador único do tipo de variante.';

COMMENT ON COLUMN public.card_variant_type.game_id IS
    'Game ao qual o tipo de variante pertence.';

COMMENT ON COLUMN public.card_variant_type.code IS
    'Código técnico, único dentro do Game.';

COMMENT ON COLUMN public.card_variant_type.name IS
    'Nome de exibição do tipo de variante.';

COMMENT ON COLUMN public.card_variant_type.description IS
    'Descrição permanente do significado do tipo de variante.';

COMMENT ON COLUMN public.card_variant_type.display_order IS
    'Ordem de apresentação do tipo de variante dentro do Game.';

COMMENT ON COLUMN public.card_variant_type.created_at IS
    'Data e hora de criação do registro.';

COMMENT ON COLUMN public.card_variant_type.updated_at IS
    'Data e hora da última atualização do registro.';

CREATE INDEX ix_card_variant_type_game_id
    ON public.card_variant_type (game_id);

ALTER TABLE public.card_variant_type
    ENABLE ROW LEVEL SECURITY;

COMMIT;
