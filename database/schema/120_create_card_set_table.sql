/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 120 - Create Card Set Table
Versão......: 1.0
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-17
Descrição...:
Cria a tabela card_set, responsável por representar as publicações oficiais
numeradas pertencentes a uma Expansion.
Exemplos:
- ME1   - Megaevolução
- ME2   - Fogo Fantasmagórico
- ME2.5 - Heróis Excelsos
- ME3   - Equilíbrio Perfeito
- ME4   - Caos Ascendente
Regras de Negócio:
- Todo Card Set deve pertencer a exatamente uma Expansion.
- O código deve ser único dentro da respectiva Expansion.
- A ordem de lançamento deve ser única dentro da respectiva Expansion.
- O código pode conter letras maiúsculas, números, ponto, hífen e sublinhado.
- O tipo do Set deve ser REGULAR ou SPECIAL (ampliado para incluir PROMO
  pela migration 122 — ver database/migrations/122_adapt_card_set_for_promo.sql).
- A ordem de lançamento deve ser um número inteiro positivo.
- A data de lançamento pode permanecer nula enquanto não estiver confirmada.
- A quantidade base deve ser um número inteiro positivo.
- A quantidade total deve ser igual ou superior à quantidade base.
- A quantidade de cartas secretas será calculada pela diferença entre
  total_set_size e base_set_size.
- Uma Expansion que possua Card Sets não pode ser excluída.
- O UUID é gerado automaticamente.
- O Row Level Security permanece habilitado.
===============================================================================
*/

CREATE TABLE public.card_set (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    expansion_id UUID NOT NULL,
    code VARCHAR(50) NOT NULL,
    name VARCHAR(150) NOT NULL,
    set_type VARCHAR(20) NOT NULL,
    release_order INTEGER NOT NULL,
    release_date DATE NULL,
    base_set_size INTEGER NOT NULL,
    total_set_size INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_card_set_expansion
        FOREIGN KEY (expansion_id)
        REFERENCES public.expansion (id)
        ON DELETE RESTRICT,
    CONSTRAINT uq_card_set_expansion_code
        UNIQUE (expansion_id, code),
    CONSTRAINT uq_card_set_expansion_release_order
        UNIQUE (expansion_id, release_order),
    CONSTRAINT ck_card_set_code_format
        CHECK (code ~ '^[A-Z0-9][A-Z0-9._-]*$'),
    CONSTRAINT ck_card_set_name_not_blank
        CHECK (btrim(name) <> ''),
    CONSTRAINT ck_card_set_type
        CHECK (set_type IN ('REGULAR', 'SPECIAL')),
    CONSTRAINT ck_card_set_release_order_positive
        CHECK (release_order > 0),
    CONSTRAINT ck_card_set_base_size_positive
        CHECK (base_set_size > 0),
    CONSTRAINT ck_card_set_total_size_valid
        CHECK (total_set_size >= base_set_size)
);

ALTER TABLE public.card_set
ENABLE ROW LEVEL SECURITY;
