/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 132 - Create Card Category Table
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18

Descrição resumida:
Cria a tabela card_category, responsável por armazenar as categorias editoriais
utilizadas para classificar as cartas de cada Game.

Descrição:
A entidade card_category representa uma classificação editorial ampla da carta.
Para o Pokémon TCG, as categorias iniciais são:
- Pokémon
- Treinador
- Energia

A categoria pertence obrigatoriamente a um Game. Isso permite que outros jogos
de cartas utilizem categorias próprias sem exigir alterações estruturais na
tabela card.

A tabela utiliza UUID como chave primária, possui timestamps de criação e
atualização e referencia a tabela game por meio de chave estrangeira.

Regras de Negócio:
- Toda categoria deve pertencer a um Game.
- O código deve ser único dentro do mesmo Game.
- Games diferentes podem utilizar o mesmo código de categoria.
- O código deve utilizar letras maiúsculas, números e underscore.
- O nome não pode ser vazio.
- A ordem de exibição deve ser maior que zero.
- A ordem de exibição organiza as categorias na interface e nos relatórios.
- A exclusão de um Game com categorias cadastradas deve ser impedida.
- A tabela deve utilizar Row Level Security.

Pré-requisitos:
- Query 000 - Infrastructure.
- Query 100 - Create Game Table.
===============================================================================
*/

CREATE TABLE public.card_category (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL,
    code VARCHAR(50) NOT NULL,
    name VARCHAR(100) NOT NULL,
    display_order INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT fk_card_category_game
        FOREIGN KEY (game_id)
        REFERENCES public.game (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT uq_card_category_game_code
        UNIQUE (game_id, code),

    CONSTRAINT ck_card_category_code_format
        CHECK (
            code ~ '^[A-Z0-9][A-Z0-9_]*$'
        ),

    CONSTRAINT ck_card_category_name_not_blank
        CHECK (
            btrim(name) <> ''
        ),

    CONSTRAINT ck_card_category_display_order_positive
        CHECK (
            display_order > 0
        )
);

COMMENT ON TABLE public.card_category IS
    'Armazena as categorias editoriais utilizadas para classificar as cartas de cada Game.';

COMMENT ON COLUMN public.card_category.id IS
    'Identificador único da categoria de carta.';

COMMENT ON COLUMN public.card_category.game_id IS
    'Game ao qual a categoria pertence.';

COMMENT ON COLUMN public.card_category.code IS
    'Código técnico e estável da categoria dentro do Game.';

COMMENT ON COLUMN public.card_category.name IS
    'Nome principal da categoria para apresentação ao usuário.';

COMMENT ON COLUMN public.card_category.display_order IS
    'Ordem lógica de exibição da categoria.';

COMMENT ON COLUMN public.card_category.created_at IS
    'Data e hora de criação do registro.';

COMMENT ON COLUMN public.card_category.updated_at IS
    'Data e hora da última atualização do registro.';

ALTER TABLE public.card_category ENABLE ROW LEVEL SECURITY;
