/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6020 - Create Pokemon Species External Reference Table
Versão......: 1.0
Status......: PROPOSTA (staging — aguardando execução)
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-04

Descrição resumida:
Cria pokemon_species_external_reference — mapeia uma pokemon_species
interna para seu identificador em uma Fonte externa (PokéAPI etc.),
mesmo padrão conceitual de card_set_external_reference (Query 240),
sem language_id (Species, assim como Set, não varia por idioma).

Descrição:
Esta tabela é evidência de integração externa, não dado self-service —
mesma distinção já estabelecida entre card_set_external_reference/
card_external_reference (fechadas) e rarity_external_mapping/
card_variant_type_external_mapping (abertas a curadoria, Query 2140).
Decisão congelada (COLLECTIONS-PHYSICAL-INCREMENT-02G-IMPLEMENTATION-01):
RLS completamente fechado — sem policy catalog_admin_select, sem GRANT
direto para authenticated. Ver Entrega da rodada para o racional de
segurança completo.

Diferença deliberada em relação ao padrão bruto de card_set_external_
reference (Query 240): esta Query não cria índices adicionais além dos
dois UNIQUE (que já indexam por pokemon_species_id e por
asset_source_id como coluna líder) — decisão explícita de não
adicionar índices especulativos nesta rodada (ex.: nenhum índice por
is_active), diferente de ix_card_set_external_reference_active em 240.

Hierarquia:
Pokemon Species
  └── Pokemon Species External Reference (por Asset Source)

Regras de Negócio:
- Cada linha vincula exatamente uma pokemon_species a exatamente um
  asset_source.
- external_species_id não pode ser vazio.
- source_url, quando presente, deve iniciar com https:// (mesmo
  padrão de asset_source/card_set_external_reference).
- metadata é JSONB, nunca nulo, sempre um objeto (nunca array/escalar).
- Unicidade dupla: (pokemon_species_id, asset_source_id) — uma Species
  não pode ter duas referências para a mesma Fonte; (asset_source_id,
  external_species_id) — um external_species_id não pode apontar para
  duas Species na mesma Fonte.
- A exclusão de uma pokemon_species referenciada deve arrastar suas
  referências externas (ON DELETE CASCADE) — evidência de integração
  não tem existência própria sem a Species que descreve, mesmo
  raciocínio de card_set_external_reference.card_set_id.
- A exclusão de um asset_source referenciado deve ser impedida (ON
  DELETE RESTRICT) — mesmo raciocínio de card_set_external_reference.
  asset_source_id.
- Row Level Security deve permanecer habilitado, sem nenhuma policy
  (SELECT/INSERT/UPDATE/DELETE) nesta rodada — tabela completamente
  fechada a authenticated comum.

Fora de Escopo (decisão explícita desta rodada):
- Pipeline de sincronização real com PokéAPI/TCGdex, RPC de escrita
  self-service, admin UI, internal.write_pokemon_species() (só se
  justifica quando houver ≥2 canais de escrita convergentes).

Pré-requisitos:
- Query 6010 - Create Pokemon Species Table.
- Query 200 - Create Asset Source Table.
===============================================================================
*/

BEGIN;

CREATE TABLE public.pokemon_species_external_reference (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    pokemon_species_id    UUID NOT NULL
                              REFERENCES public.pokemon_species (id)
                              ON DELETE CASCADE,
    asset_source_id       UUID NOT NULL
                              REFERENCES public.asset_source (id)
                              ON DELETE RESTRICT,

    external_species_id   TEXT NOT NULL,
    source_url            TEXT,
    metadata              JSONB NOT NULL DEFAULT '{}'::JSONB,

    is_active             BOOLEAN NOT NULL DEFAULT TRUE,

    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_pokemon_species_external_reference_species_source
        UNIQUE (pokemon_species_id, asset_source_id),
    CONSTRAINT uq_pokemon_species_external_reference_source_external
        UNIQUE (asset_source_id, external_species_id),
    CONSTRAINT ck_pokemon_species_external_reference_external_id_not_blank
        CHECK (BTRIM(external_species_id) <> ''),
    CONSTRAINT ck_pokemon_species_external_reference_source_url
        CHECK (
            source_url IS NULL
            OR (
                BTRIM(source_url) <> ''
                AND source_url ~ '^https://'
            )
        ),
    CONSTRAINT ck_pokemon_species_external_reference_metadata
        CHECK (JSONB_TYPEOF(metadata) = 'object')
);

COMMENT ON TABLE public.pokemon_species_external_reference IS
    'Evidência de integração externa: mapeia pokemon_species para seu identificador em uma Fonte externa (PokéAPI etc.). Padrão conceitual de card_set_external_reference (Query 240), sem language_id. RLS completamente fechado — não é dado self-service (COLLECTIONS-PHYSICAL-INCREMENT-02G-IMPLEMENTATION-01).';

COMMENT ON COLUMN public.pokemon_species_external_reference.pokemon_species_id IS
    'Species interna referenciada. ON DELETE CASCADE — evidência não sobrevive à Species. Imutável (protegido por trigger de governança, Query 6021).';

COMMENT ON COLUMN public.pokemon_species_external_reference.asset_source_id IS
    'Fonte externa (asset_source) que originou esta referência. ON DELETE RESTRICT. Imutável (protegido por trigger de governança, Query 6021).';

COMMENT ON COLUMN public.pokemon_species_external_reference.external_species_id IS
    'Identificador da espécie na Fonte externa (ex.: id numérico da PokéAPI). Imutável (protegido por trigger de governança, Query 6021).';

COMMENT ON COLUMN public.pokemon_species_external_reference.metadata IS
    'Metadados adicionais da Fonte externa, em formato livre (JSONB), sempre um objeto.';

ALTER TABLE public.pokemon_species_external_reference
    ENABLE ROW LEVEL SECURITY;

COMMIT;
