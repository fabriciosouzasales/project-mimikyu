/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6090 - Create Pokemon Generation External Reference Table
Versão......: 1.0 (PROPOSTA — GATE 3 STAGING)
Status......: PROPOSTO / NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-04 (staging em POKEMON-CATALOG-SOURCING-INITIAL-LOAD-
               PHYSICAL-STAGING-01, materializando docs/06a-pokemon-catalog-
               sourcing.md v1.1, CANONICALIZED / AUDITED / COMMITTED / PUSHED)

Descrição resumida:
Cria pokemon_generation_external_reference — mapeia uma pokemon_generation
interna para seu identificador em uma Fonte externa (PokéAPI etc.). Necessária
para: (a) a própria identidade externa de Generation; (b) resolver
species[].generation_external_id → pokemon_generation.id durante PLAN/APPLY do
Pokémon Catalog Sourcing (Query 6104/6105). NÃO resolve main_region_external_id
— isso já é resolvido via pokemon_region_external_reference (Query 6070),
existente e CONFIRMADO EXECUTADO.

Mesmo padrão físico de pokemon_region_external_reference (Query 6070) e
pokemon_species_external_reference (Query 6020): evidência de integração
externa, não dado self-service.

Hierarquia:
Pokemon Generation
  └── Pokemon Generation External Reference (por Asset Source)

Regras de Negócio:
- Cada linha vincula exatamente uma pokemon_generation a exatamente um
  asset_source.
- external_generation_id não pode ser vazio.
- source_url, quando presente, deve iniciar com https://.
- metadata é JSONB, nunca nulo, sempre um objeto (nunca array/escalar).
- Unicidade dupla: (pokemon_generation_id, asset_source_id) — uma Generation
  não pode ter duas referências para a mesma Fonte; (asset_source_id,
  external_generation_id) — um external_generation_id não pode apontar para
  duas Generations na mesma Fonte.
- A exclusão de uma pokemon_generation referenciada deve arrastar suas
  referências externas (ON DELETE CASCADE).
- A exclusão de um asset_source referenciado deve ser impedida (ON DELETE
  RESTRICT).
- Row Level Security deve permanecer habilitado, sem nenhuma policy nesta
  rodada — tabela completamente fechada a authenticated comum, mesma decisão
  congelada de pokemon_region_external_reference/pokemon_species_external_
  reference.

Índices: nenhum além dos gerados pela PK e pelas duas UNIQUE compostas —
nenhum índice especulativo (mesma decisão já tomada em 6020/6050/6070).

Fora de Escopo (decisão explícita desta rodada):
- Resolução de main_region_external_id — já coberta por Query 6070.
- Pipeline de sincronização real com PokéAPI, RPC de escrita self-service,
  admin UI.

Pré-requisitos:
- Query 6000 - Create Pokemon Generation Table (CONFIRMADO EXECUTADO).
- Query 200 - Create Asset Source Table (CONFIRMADO EXECUTADO).
===============================================================================
*/

BEGIN;

CREATE TABLE public.pokemon_generation_external_reference (
    id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    pokemon_generation_id     UUID NOT NULL
                                  REFERENCES public.pokemon_generation (id)
                                  ON DELETE CASCADE,
    asset_source_id           UUID NOT NULL
                                  REFERENCES public.asset_source (id)
                                  ON DELETE RESTRICT,

    external_generation_id    TEXT NOT NULL,
    source_url                TEXT,
    metadata                  JSONB NOT NULL DEFAULT '{}'::JSONB,

    is_active                 BOOLEAN NOT NULL DEFAULT TRUE,

    created_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_pokemon_generation_external_reference_generation_source
        UNIQUE (pokemon_generation_id, asset_source_id),
    CONSTRAINT uq_pokemon_generation_external_reference_source_external
        UNIQUE (asset_source_id, external_generation_id),

    CONSTRAINT ck_pokemon_generation_external_reference_external_id_not_blank
        CHECK (BTRIM(external_generation_id) <> ''),
    CONSTRAINT ck_pokemon_generation_external_reference_source_url
        CHECK (source_url IS NULL OR (BTRIM(source_url) <> '' AND source_url ~ '^https://')),
    CONSTRAINT ck_pokemon_generation_external_reference_metadata_object
        CHECK (JSONB_TYPEOF(metadata) = 'object')
);

COMMENT ON TABLE public.pokemon_generation_external_reference IS
    'Mapeia pokemon_generation para seu identificador em uma Fonte externa (PokéAPI). Evidência de integração, não dado self-service. Proposta GATE 3 STAGING (docs/06a-pokemon-catalog-sourcing.md).';
COMMENT ON COLUMN public.pokemon_generation_external_reference.external_generation_id IS
    'Identificador estável da Generation na Fonte externa (ex.: pokemon-api generation.id). TEXT, nunca slug.';

ALTER TABLE public.pokemon_generation_external_reference ENABLE ROW LEVEL SECURITY;

-- Least privilege: nenhuma DDL implícita de anon/authenticated sobre a tabela
-- (mesma decisão de 6070/2147). SELECT/INSERT/UPDATE/DELETE já bloqueados por
-- RLS sem policy; REVOKE explícito cobre grants de DDL que RLS não alcança.
REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
    ON public.pokemon_generation_external_reference
    FROM anon, authenticated;

COMMIT;
