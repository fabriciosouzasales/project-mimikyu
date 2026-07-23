/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 140 - Create Card Table
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18

Descrição resumida:
Cria a tabela card, responsável por armazenar cada carta específica publicada
dentro de um Card Set.

Descrição:
A entidade card representa uma entrada individual do checklist oficial de um
Card Set.

Cada registro identifica uma carta por meio do Set ao qual pertence e de seu
número oficial de coleção.

Exemplos:
- Charizard ex nº 021 da coleção ME4;
- Pikachu nº 025 da coleção ME1;
- uma carta promocional identificada como SVP001.

A entidade não representa uma identidade editorial global compartilhada entre
diferentes Sets. Caso uma carta seja republicada em outro Set, será cadastrada
como um novo registro.

O campo collector_number preserva fielmente a identificação oficial da carta,
incluindo zeros à esquerda, prefixos e sufixos.

O campo collector_total registra, quando aplicável, o denominador exibido na
numeração da carta, como 182 em 021/182. Ele pode ser nulo para cartas cuja
numeração oficial não utiliza denominador.

O campo collector_order representa a posição editorial da carta no checklist
e deve ser utilizado para ordenação, independentemente do formato de
collector_number.

Regras de Negócio:
- Toda Card deve pertencer obrigatoriamente a um Card Set.
- Toda Card deve possuir uma Rarity.
- Toda Card deve possuir uma Card Category.
- Card Set, Rarity e Card Category devem pertencer ao mesmo Game.
- O número da carta deve ser único dentro do mesmo Card Set.
- O número deve ser armazenado exatamente como definido pela fonte oficial.
- O número não pode ser vazio.
- O total da numeração pode ser nulo.
- Quando informado, collector_total deve ser maior que zero.
- A ordem editorial deve ser maior que zero.
- A ordem editorial deve ser única dentro do mesmo Card Set.
- O nome deve ser armazenado conforme publicado no idioma do Set.
- O nome não pode ser vazio.
- Não deve existir um código redundante formado pelo código do Set e pelo
  número da carta.
- A exclusão de Card Set, Rarity ou Card Category utilizados por Cards deve ser
  impedida.
- A tabela deve utilizar Row Level Security.

Pré-requisitos:
- Query 000 - Infrastructure.
- Query 110 - Create Expansion Table.
- Query 120 - Create Card Set Table.
- Query 130 - Create Rarity Table.
- Query 132 - Create Card Category Table.
===============================================================================
*/

CREATE TABLE public.card (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    card_set_id UUID NOT NULL,
    rarity_id UUID NOT NULL,
    category_id UUID NOT NULL,

    collector_number VARCHAR(20) NOT NULL,
    collector_total INTEGER,
    collector_order INTEGER NOT NULL,
    name VARCHAR(200) NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT fk_card_card_set
        FOREIGN KEY (card_set_id)
        REFERENCES public.card_set (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT fk_card_rarity
        FOREIGN KEY (rarity_id)
        REFERENCES public.rarity (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT fk_card_category
        FOREIGN KEY (category_id)
        REFERENCES public.card_category (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT uq_card_card_set_collector_number
        UNIQUE (card_set_id, collector_number),

    CONSTRAINT uq_card_card_set_collector_order
        UNIQUE (card_set_id, collector_order),

    CONSTRAINT ck_card_collector_number_not_blank
        CHECK (
            btrim(collector_number) <> ''
        ),

    CONSTRAINT ck_card_collector_number_format
        CHECK (
            collector_number ~ '^[A-Za-z0-9][A-Za-z0-9._-]*$'
        ),

    CONSTRAINT ck_card_collector_total_positive
        CHECK (
            collector_total IS NULL
            OR collector_total > 0
        ),

    CONSTRAINT ck_card_collector_order_positive
        CHECK (
            collector_order > 0
        ),

    CONSTRAINT ck_card_name_not_blank
        CHECK (
            btrim(name) <> ''
        )
);

COMMENT ON TABLE public.card IS
    'Armazena cada carta específica publicada dentro de um Card Set.';

COMMENT ON COLUMN public.card.id IS
    'Identificador único da carta no catálogo.';

COMMENT ON COLUMN public.card.card_set_id IS
    'Card Set oficial ao qual a carta pertence.';

COMMENT ON COLUMN public.card.rarity_id IS
    'Raridade oficial da carta dentro do Card Set.';

COMMENT ON COLUMN public.card.category_id IS
    'Categoria editorial da carta, como Pokémon, Treinador ou Energia.';

COMMENT ON COLUMN public.card.collector_number IS
    'Número oficial da carta, preservando zeros, prefixos e sufixos.';

COMMENT ON COLUMN public.card.collector_total IS
    'Denominador da numeração oficial da carta, quando aplicável.';

COMMENT ON COLUMN public.card.collector_order IS
    'Posição editorial da carta no checklist oficial do Card Set.';

COMMENT ON COLUMN public.card.name IS
    'Nome oficial da carta no idioma em que o Card Set foi publicado.';

COMMENT ON COLUMN public.card.created_at IS
    'Data e hora de criação do registro.';

COMMENT ON COLUMN public.card.updated_at IS
    'Data e hora da última atualização do registro.';

ALTER TABLE public.card ENABLE ROW LEVEL SECURITY;
