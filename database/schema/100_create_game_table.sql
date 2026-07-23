/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 100 - Create Game Table
Versão......: 1.0
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-17
Descrição...:
Cria a tabela game, raiz da hierarquia editorial (Game → Expansion →
Card Set → Card), representando cada Trading Card Game suportado pela
plataforma (ex.: Pokémon TCG).
Regras de Negócio:
- O código deve ser único e normalizado (A-Z, 0-9, _).
- O nome não pode ser vazio.
- Mudanças no nome não alteram a identidade técnica (id) nem o código.
===============================================================================
*/

CREATE TABLE public.game (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    code VARCHAR(50) NOT NULL,
    name VARCHAR(150) NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_game_code
        UNIQUE (code),

    CONSTRAINT ck_game_code_format
        CHECK (code ~ '^[A-Z][A-Z0-9_]*$'),

    CONSTRAINT ck_game_name_not_blank
        CHECK (btrim(name) <> '')
);

ALTER TABLE public.game
    ENABLE ROW LEVEL SECURITY;
