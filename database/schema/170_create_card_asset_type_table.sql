/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 170 - Create Card Asset Type Table
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-23

Descrição resumida:
Cria a tabela card_asset_type, catálogo editorial dos tipos semânticos de
ativo digital associados a uma Card.

Descrição:
Card Asset Type descreve a finalidade semântica de um ativo digital (ex.:
frente da carta, ilustração isolada, verso da carta) — não a resolução,
formato de arquivo ou localização de armazenamento (que pertencem a
card_asset), e não representa uma Card Variant física.

Hierarquia:
Game
  └── Card Asset Type

Regras de Negócio:
- Cada Card Asset Type pertence a exatamente um Game.
- O code deve ser único dentro do Game.
- O name deve ser único dentro do Game.
- O asset_order deve ser único dentro do Game.
- O code deve utilizar letras maiúsculas, números e underscore.
- code e name não podem ser vazios.
- asset_order deve ser positivo.
- A exclusão de um Game referenciado deve ser impedida.
- A tabela utiliza UUID como chave primária.
- A tabela utiliza created_at e updated_at.
- O Row Level Security deve permanecer habilitado.

Pré-requisitos:
- Query 000 - Infrastructure.
- Tabela public.game.

===============================================================================

NOTA DE DOCUMENTAÇÃO: cabeçalho reformatado para o padrão STD-001 e comentários
(COMMENT ON) traduzidos para português, mantendo a lógica SQL (tabelas,
colunas, constraints, índices) idêntica ao texto originalmente executado.
Reformatação solicitada por Fabrício, já que a sessão pareada (ChatGPT) passou
a gerar cabeçalhos fora do padrão do projeto a partir deste ciclo.
===============================================================================
*/

BEGIN;

CREATE TABLE IF NOT EXISTS public.card_asset_type (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL,
    code TEXT NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    asset_order INTEGER NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_card_asset_type_game
        FOREIGN KEY (game_id)
        REFERENCES public.game (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT ck_card_asset_type_code_not_blank
        CHECK (BTRIM(code) <> ''),

    CONSTRAINT ck_card_asset_type_name_not_blank
        CHECK (BTRIM(name) <> ''),

    CONSTRAINT ck_card_asset_type_code_format
        CHECK (code ~ '^[A-Z][A-Z0-9_]*$'),

    CONSTRAINT ck_card_asset_type_asset_order_positive
        CHECK (asset_order > 0),

    CONSTRAINT uq_card_asset_type_game_code
        UNIQUE (game_id, code),

    CONSTRAINT uq_card_asset_type_game_name
        UNIQUE (game_id, name),

    CONSTRAINT uq_card_asset_type_game_order
        UNIQUE (game_id, asset_order)
);

CREATE INDEX IF NOT EXISTS ix_card_asset_type_game_id
    ON public.card_asset_type (game_id);

CREATE INDEX IF NOT EXISTS ix_card_asset_type_is_active
    ON public.card_asset_type (is_active);

ALTER TABLE public.card_asset_type ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.card_asset_type IS
    'Catálogo editorial dos tipos semânticos de ativo digital associados a uma Card. Não representa Card Variants físicas.';

COMMENT ON COLUMN public.card_asset_type.id IS
    'Identificador único (chave primária substituta) do tipo de ativo.';

COMMENT ON COLUMN public.card_asset_type.game_id IS
    'Game ao qual o tipo de ativo pertence.';

COMMENT ON COLUMN public.card_asset_type.code IS
    'Código técnico estável, em maiúsculas, ex. CARD_FRONT.';

COMMENT ON COLUMN public.card_asset_type.name IS
    'Nome de exibição do tipo de ativo, legível por humanos.';

COMMENT ON COLUMN public.card_asset_type.description IS
    'Definição de negócio e uso pretendido do tipo de ativo.';

COMMENT ON COLUMN public.card_asset_type.asset_order IS
    'Ordem de apresentação editorial dentro do Game.';

COMMENT ON COLUMN public.card_asset_type.is_active IS
    'Indica se o tipo de ativo está atualmente disponível para uso.';

COMMENT ON COLUMN public.card_asset_type.created_at IS
    'Data e hora de criação do registro.';

COMMENT ON COLUMN public.card_asset_type.updated_at IS
    'Data e hora da última atualização do registro.';

COMMIT;
