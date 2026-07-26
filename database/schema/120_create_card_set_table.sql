/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 120 - Create Card Set Table
Versão......: 2.1
Autor.......: Fabrício Sales / ChatGPT / Claude
Data........: 2026-07-26
Status......: CANÔNICA
Descrição...:
Cria a tabela card_set, responsável por representar as publicações oficiais
numeradas pertencentes a uma Expansion — já nascendo com suporte nativo ao
tipo PROMO (Card Set promocional Black Star Promos, ver ADR-015), com o
índice único parcial que impede mais de uma série PROMO por Expansion, e com
a coluna logo_storage_path (caminho relativo da logo oficial do Set no
bucket privado card-set-logo, ver ADR-022 e Query 273).
Exemplos:
- ME0   - ME Black Star Promos (PROMO)
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
- O tipo do Set deve ser REGULAR, SPECIAL ou PROMO.
- A ordem de lançamento deve ser um número inteiro positivo.
- A data de lançamento pode permanecer nula enquanto não estiver confirmada.
- A quantidade base deve ser um número inteiro positivo.
- A quantidade total deve ser igual ou superior à quantidade base.
- A quantidade de cartas secretas será calculada pela diferença entre
  total_set_size e base_set_size.
- Um Card Set PROMO deve possuir base_set_size igual a total_set_size.
- Deve existir no máximo um Card Set PROMO por Expansion.
- Uma Expansion que possua Card Sets não pode ser excluída.
- O UUID é gerado automaticamente.
- O Row Level Security permanece habilitado.
- logo_storage_path é opcional (NULL = Card Set ainda sem logo cadastrada),
  nunca uma URL absoluta, e só pode ser escrito pela função administrativa
  admin_set_card_set_logo() (ver database/migrations/275_*.sql) — nenhuma
  política de UPDATE é criada para esta tabela.
Nota — Princípio da Fonte Canônica (STD-001, Seção 10):
esta é a versão que uma instalação nova deve executar. Ela substitui, em uma
instalação nova, a Versão 1.0 desta Query, a migration 122 - Adapt Card Set
for Promo (ver database/migrations/122_adapt_card_set_for_promo.sql) e a
migration 273 - Add Card Set Logo Column (ver database/migrations/273_*.sql)
— ambas reclassificadas como Status MIGRATION, históricas, fora do fluxo de
instalação limpa.
Item aberto (herdado da Versão 2.0): o banco físico atual foi construído
pelo caminho antigo (120 v1.0 + migration 122), que não incluía o índice
uq_card_set_expansion_promo. Não presumir que esse índice já existe no
Supabase real até confirmação — ver docs/05-modelo-de-dados.md, seção Set.
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
    logo_storage_path TEXT NULL,
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
        CHECK (set_type IN ('REGULAR', 'SPECIAL', 'PROMO')),
    CONSTRAINT ck_card_set_release_order_positive
        CHECK (release_order > 0),
    CONSTRAINT ck_card_set_base_size_positive
        CHECK (base_set_size > 0),
    CONSTRAINT ck_card_set_total_size_valid
        CHECK (total_set_size >= base_set_size),
    CONSTRAINT ck_card_set_promo_size
        CHECK (
            set_type <> 'PROMO'
            OR base_set_size = total_set_size
        ),
    CONSTRAINT ck_card_set_logo_storage_path_not_url
        CHECK (
            logo_storage_path IS NULL
            OR logo_storage_path !~* '^[a-z][a-z0-9+.-]*://'
        )
);

-- Garante no máximo um Card Set promocional por Expansion
CREATE UNIQUE INDEX uq_card_set_expansion_promo
    ON public.card_set (expansion_id)
    WHERE set_type = 'PROMO';

ALTER TABLE public.card_set
ENABLE ROW LEVEL SECURITY;

COMMENT ON COLUMN public.card_set.logo_storage_path IS
    'Caminho relativo da logo oficial do Card Set dentro do bucket privado card-set-logo (nunca uma URL completa). NULL = Card Set ainda sem logo cadastrada. Escrita restrita à função admin_set_card_set_logo().';
