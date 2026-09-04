/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6000 - Create Pokemon Generation Table
Versão......: 1.0
Status......: PROPOSTA (staging — aguardando execução)
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-04

Descrição resumida:
Cria pokemon_generation — catálogo global e canônico das gerações da
Pokédex nacional (Generation I, II, III...). Primeira tabela do módulo
"Pokémon Catalog Foundation" (milhar 6000-6999, ADR-011 v1.2, LDM-175
a LDM-185).

Descrição:
pokemon_generation representa uma geração do universo Pokémon
(Generation I = Kanto, Generation II = Johto, etc.) como entidade
global, independente de Game — decisão congelada em
COLLECTIONS-PHYSICAL-INCREMENT-02G-IMPLEMENTATION-01: pokemon_generation
e pokemon_species não têm game_id porque são entidades canônicas do
universo Pokémon, não do TCG. O vínculo com o Game acontece depois, em
Card → Species (fora do escopo desta rodada).

code segue a convenção GENERATION_I, GENERATION_II, GENERATION_III...
(decisão congelada); ordinal_number é o número inteiro correspondente
(1, 2, 3...), campo separado, sem limite superior de gerações.

Hierarquia:
(nenhuma — pokemon_generation é raiz do módulo)

Regras de Negócio:
- code deve ser único, maiúsculo, formato GENERATION_<algarismo romano>.
- canonical_name não pode ser vazio.
- ordinal_number deve ser único e maior que zero.
- Row Level Security deve permanecer habilitado, sem policy de leitura
  self-service nesta rodada (ver Entrega da rodada para o racional de
  segurança completo — acesso exclusivamente via função administrativa
  futura ou service_role, mesmo padrão de game/rarity/card_category).

Fora de Escopo (decisão explícita desta rodada):
- pokemon_form, pokemon_variety, pokedex, pokedex_position,
  card_primary_species, sincronização com PokéAPI/TCGdex, frontend,
  admin UI.

Pré-requisitos:
- Extensão ou infraestrutura que disponibilize gen_random_uuid().
===============================================================================
*/

BEGIN;

CREATE TABLE public.pokemon_generation (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    code            VARCHAR(50) NOT NULL,
    canonical_name  VARCHAR(100) NOT NULL,
    ordinal_number  INTEGER NOT NULL,

    is_active       BOOLEAN NOT NULL DEFAULT TRUE,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_pokemon_generation_code
        UNIQUE (code),
    CONSTRAINT uq_pokemon_generation_ordinal_number
        UNIQUE (ordinal_number),
    CONSTRAINT ck_pokemon_generation_code_format
        CHECK (code ~ '^[A-Z][A-Z0-9_]*$'),
    CONSTRAINT ck_pokemon_generation_canonical_name_not_blank
        CHECK (BTRIM(canonical_name) <> ''),
    CONSTRAINT ck_pokemon_generation_ordinal_number_positive
        CHECK (ordinal_number > 0)
);

COMMENT ON TABLE public.pokemon_generation IS
    'Catálogo global e canônico das gerações da Pokédex nacional (Generation I, II, III...). Entidade raiz do módulo Pokémon Catalog Foundation (ADR-011 v1.2, LDM-175 a LDM-185). Sem game_id — decisão deliberada (COLLECTIONS-PHYSICAL-INCREMENT-02G-IMPLEMENTATION-01).';

COMMENT ON COLUMN public.pokemon_generation.id IS
    'Identificador técnico único da geração. Imutável (protegido por trigger de governança, Query 6001).';

COMMENT ON COLUMN public.pokemon_generation.code IS
    'Código técnico estável, formato GENERATION_<algarismo romano> (ex.: GENERATION_I). Imutável (protegido por trigger de governança, Query 6001).';

COMMENT ON COLUMN public.pokemon_generation.canonical_name IS
    'Nome de exibição da geração. Corrigível administrativamente.';

COMMENT ON COLUMN public.pokemon_generation.ordinal_number IS
    'Número ordinal da geração (1, 2, 3...), sem limite superior. Imutável (protegido por trigger de governança, Query 6001).';

COMMENT ON COLUMN public.pokemon_generation.is_active IS
    'Indica se a geração está disponível para uso em novos registros.';

COMMENT ON COLUMN public.pokemon_generation.created_at IS
    'Data e hora de criação do registro. Imutável (protegido por trigger de governança, Query 6001).';

COMMENT ON COLUMN public.pokemon_generation.updated_at IS
    'Data e hora da última atualização do registro.';

ALTER TABLE public.pokemon_generation
    ENABLE ROW LEVEL SECURITY;

COMMIT;
