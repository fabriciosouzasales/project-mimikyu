/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 130 - Create Rarity Table
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18
Descrição...:
Cria a tabela rarity, responsável por representar as classificações oficiais
de raridade utilizadas pelas cartas de um determinado Game.
Exemplos para Pokémon TCG:
- COMMON
- UNCOMMON
- RARE
- DOUBLE_RARE
- ILLUSTRATION_RARE
- SPECIAL_ILLUSTRATION_RARE
- SAR
- HYPER_RARE
Regras de Negócio:
- Toda Rarity deve pertencer a exatamente um Game.
- O código da Rarity deve ser único dentro do respectivo Game.
- Jogos diferentes podem utilizar códigos de raridade iguais.
- O código representa a identificação técnica e estável da raridade.
- O nome representa a descrição oficial ou principal da raridade.
- A ordem de exibição permite organizar as raridades de maneira lógica.
- A ordem de exibição não precisa ser única, pois raridades diferentes podem
  ocupar níveis equivalentes de classificação.
- O código pode conter letras maiúsculas, números e sublinhado.
- O nome não pode ser vazio.
- A ordem de exibição deve ser um número inteiro positivo.
- Um Game que possua Rarities não pode ser excluído.
- O UUID é gerado automaticamente.
- O Row Level Security permanece habilitado.
Observações:
- Raridades pertencentes a taxonomias diferentes devem permanecer distintas.
- Códigos como SAR e SIR não devem ser considerados equivalentes
  automaticamente.
- Eventuais agrupamentos de raridades equivalentes serão tratados
  posteriormente, caso exista necessidade real para o colecionismo.
===============================================================================
*/

CREATE TABLE public.rarity (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL,
    code VARCHAR(50) NOT NULL,
    name VARCHAR(150) NOT NULL,
    display_order INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_rarity_game
        FOREIGN KEY (game_id)
        REFERENCES public.game (id)
        ON DELETE RESTRICT,
    CONSTRAINT uq_rarity_game_code
        UNIQUE (game_id, code),
    CONSTRAINT ck_rarity_code_format
        CHECK (code ~ '^[A-Z0-9][A-Z0-9_]*$'),
    CONSTRAINT ck_rarity_name_not_blank
        CHECK (btrim(name) <> ''),
    CONSTRAINT ck_rarity_display_order_positive
        CHECK (display_order > 0)
);

ALTER TABLE public.rarity
ENABLE ROW LEVEL SECURITY;
