/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6010 - Create Pokemon Species Table
Versão......: 1.0
Status......: PROPOSTA (staging — aguardando execução)
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-04

Descrição resumida:
Cria pokemon_species — catálogo global e canônico das espécies
Pokémon (Bulbasaur, Charmander, Pikachu...), identificadas pelo
national_dex_number.

Descrição:
pokemon_species, assim como pokemon_generation (Query 6000), é uma
entidade global do universo Pokémon, sem game_id — decisão congelada
(COLLECTIONS-PHYSICAL-INCREMENT-02G-IMPLEMENTATION-01). O vínculo com
o TCG acontece depois, em Card → Species, fora do escopo desta rodada.

national_dex_number é o identificador canônico e único da espécie na
Pokédex Nacional. É obrigatório, único e maior que zero — mas
permanece corrigível administrativamente (não protegido pelo trigger
de governança, Query 6011): é dado editorial canônico, não identidade
técnica. Só id e created_at são protegidos — mesmo raciocínio: UUID é
identidade técnica imutável; national_dex_number, generation_id e
canonical_name são dado editorial canônico, único onde exigido, mas
corrigível via reconciliação administrativa.

Hierarquia:
Pokemon Generation
  └── Pokemon Species

Regras de Negócio:
- Cada Species pertence a exatamente uma Generation (generation_id NOT
  NULL).
- national_dex_number deve ser único, maior que zero.
- canonical_name não pode ser vazio.
- A exclusão de uma Generation referenciada deve ser impedida.
- Row Level Security deve permanecer habilitado, sem policy de leitura
  self-service nesta rodada.

Fora de Escopo (decisão explícita desta rodada):
- pokemon_form, pokemon_variety, pokedex, pokedex_position,
  card_primary_species, sincronização com PokéAPI/TCGdex, frontend,
  admin UI.

Pré-requisitos:
- Query 6000 - Create Pokemon Generation Table.
===============================================================================
*/

BEGIN;

CREATE TABLE public.pokemon_species (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    generation_id        UUID NOT NULL
                             REFERENCES public.pokemon_generation (id)
                             ON UPDATE RESTRICT ON DELETE RESTRICT,

    national_dex_number  INTEGER NOT NULL,
    canonical_name       VARCHAR(150) NOT NULL,

    is_active            BOOLEAN NOT NULL DEFAULT TRUE,

    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_pokemon_species_national_dex_number
        UNIQUE (national_dex_number),
    CONSTRAINT ck_pokemon_species_national_dex_number_positive
        CHECK (national_dex_number > 0),
    CONSTRAINT ck_pokemon_species_canonical_name_not_blank
        CHECK (BTRIM(canonical_name) <> '')
);

COMMENT ON TABLE public.pokemon_species IS
    'Catálogo global e canônico das espécies Pokémon, identificadas por national_dex_number. Módulo Pokémon Catalog Foundation (ADR-011 v1.2, LDM-175 a LDM-185). Sem game_id — decisão deliberada (COLLECTIONS-PHYSICAL-INCREMENT-02G-IMPLEMENTATION-01).';

COMMENT ON COLUMN public.pokemon_species.id IS
    'Identificador técnico único da espécie. Imutável (protegido por trigger de governança, Query 6011).';

COMMENT ON COLUMN public.pokemon_species.generation_id IS
    'Geração à qual a espécie pertence. Corrigível administrativamente (não protegido pelo trigger de governança).';

COMMENT ON COLUMN public.pokemon_species.national_dex_number IS
    'Número canônico da espécie na Pokédex Nacional. Único, obrigatório, corrigível administrativamente (não protegido pelo trigger de governança) — dado editorial canônico, não identidade técnica.';

COMMENT ON COLUMN public.pokemon_species.canonical_name IS
    'Nome de exibição canônico da espécie. Corrigível administrativamente.';

COMMENT ON COLUMN public.pokemon_species.is_active IS
    'Indica se a espécie está disponível para uso em novos registros.';

COMMENT ON COLUMN public.pokemon_species.created_at IS
    'Data e hora de criação do registro. Imutável (protegido por trigger de governança, Query 6011).';

COMMENT ON COLUMN public.pokemon_species.updated_at IS
    'Data e hora da última atualização do registro.';

CREATE INDEX ix_pokemon_species_generation_id
    ON public.pokemon_species (generation_id);

ALTER TABLE public.pokemon_species
    ENABLE ROW LEVEL SECURITY;

COMMIT;
