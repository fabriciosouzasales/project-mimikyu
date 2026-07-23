/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 110 - Create Expansion Table
Versão......: 1.0
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-17
Descrição...:
Cria a tabela expansion, representando o ciclo editorial de um Game,
agrupando Card Sets (ex.: Scarlet & Violet, Mega Evolution).
Regras de Negócio:
- Toda Expansion deve pertencer a exatamente um Game.
- O código deve ser único dentro do respectivo Game, não globalmente.
- A ordem de lançamento deve ser única dentro do respectivo Game e positiva.
- O nome não pode ser vazio.
- Um Game que possua Expansions não pode ser excluído (ON DELETE RESTRICT).
===============================================================================
*/

CREATE TABLE public.expansion (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL,

    code VARCHAR(50) NOT NULL,
    name VARCHAR(150) NOT NULL,
    release_order INTEGER NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_expansion_game
        FOREIGN KEY (game_id)
        REFERENCES public.game (id)
        ON DELETE RESTRICT,

    CONSTRAINT uq_expansion_game_code
        UNIQUE (game_id, code),

    CONSTRAINT uq_expansion_game_release_order
        UNIQUE (game_id, release_order),

    CONSTRAINT ck_expansion_code_format
        CHECK (code ~ '^[A-Z][A-Z0-9_]*$'),

    CONSTRAINT ck_expansion_name_not_blank
        CHECK (btrim(name) <> ''),

    CONSTRAINT ck_expansion_release_order_positive
        CHECK (release_order > 0)
);

ALTER TABLE public.expansion
    ENABLE ROW LEVEL SECURITY;
