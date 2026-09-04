/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6070 - Create Pokemon Region External Reference Table
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-04 (staging em POKEMON-REGION-FOUNDATION-
               PHYSICAL-STAGING-01; aplicado em 2026-09-04 via
               POKEMON-REGION-FOUNDATION-PHYSICAL-IMPLEMENTATION-01)

Descrição resumida:
Cria pokemon_region_external_reference — mapeia uma pokemon_region
interna para seu identificador em uma Fonte externa (PokéAPI etc.).
Segunda e última tabela nova desta rodada.

Descrição:
Mesmo padrão físico de pokemon_species_external_reference (Query 6020)
e pokedex_external_reference (Query 6050): evidência de integração
externa, não dado self-service. pokemon_region é entidade-raiz de
catálogo com identidade própria e independente na PokéAPI (o recurso
`/region/{id}` tem seu próprio id numérico estável — ex.: 1 para
kanto — distinto do slug/name "kanto", que é apresentacional/roteável
na API, não o identificador canônico a ser armazenado) — mesmo
raciocínio já aplicado a external_pokedex_id (Query 6050).

Mesmo princípio de "nunca pokeapi_id solto na entidade canônica" já
aplicado a pokemon_species/pokedex (Query 6020/6050): nenhuma coluna
pokeapi_id em pokemon_region; o identificador externo mora
exclusivamente aqui.

Hierarquia:
Pokemon Region
  └── Pokemon Region External Reference (por Asset Source)

Regras de Negócio:
- Cada linha vincula exatamente uma pokemon_region a exatamente um
  asset_source.
- external_region_id não pode ser vazio.
- source_url, quando presente, deve iniciar com https:// (mesmo padrão
  de asset_source/pokemon_species_external_reference/pokedex_external_
  reference).
- metadata é JSONB, nunca nulo, sempre um objeto (nunca array/escalar).
- Unicidade dupla: (pokemon_region_id, asset_source_id) — uma Região
  não pode ter duas referências para a mesma Fonte; (asset_source_id,
  external_region_id) — um external_region_id não pode apontar para
  duas Regiões na mesma Fonte.
- A exclusão de uma pokemon_region referenciada deve arrastar suas
  referências externas (ON DELETE CASCADE) — evidência de integração
  não tem existência própria sem a Região que descreve.
- A exclusão de um asset_source referenciado deve ser impedida (ON
  DELETE RESTRICT) — mesmo raciocínio das demais external_reference do
  módulo.
- Row Level Security deve permanecer habilitado, sem nenhuma policy
  (SELECT/INSERT/UPDATE/DELETE) nesta rodada — tabela completamente
  fechada a authenticated comum, mesma decisão congelada das demais
  external_reference do módulo.

Índices: nenhum além dos gerados pela PK e pelas duas UNIQUE compostas —
mesma decisão explícita já tomada em pokemon_species_external_reference
(Query 6020) e pokedex_external_reference (Query 6050) de não adicionar
índices especulativos.

Fora de Escopo (decisão explícita desta rodada):
- Pipeline de sincronização real com PokéAPI/TCGdex, RPC de escrita
  self-service, admin UI — sourcing permanece SUSPENSO.

Pré-requisitos:
- Query 6060 - Create Pokemon Region Table.
- Query 200 - Create Asset Source Table (já CONFIRMADO EXECUTADO;
  linha POKEAPI já existe via Query 6700, CONFIRMADO EXECUTADO).
===============================================================================
*/

BEGIN;

CREATE TABLE public.pokemon_region_external_reference (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    pokemon_region_id     UUID NOT NULL
                              REFERENCES public.pokemon_region (id)
                              ON DELETE CASCADE,
    asset_source_id       UUID NOT NULL
                              REFERENCES public.asset_source (id)
                              ON DELETE RESTRICT,

    external_region_id    TEXT NOT NULL,
    source_url            TEXT,
    metadata              JSONB NOT NULL DEFAULT '{}'::JSONB,

    is_active             BOOLEAN NOT NULL DEFAULT TRUE,

    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_pokemon_region_external_reference_region_source
        UNIQUE (pokemon_region_id, asset_source_id),
    CONSTRAINT uq_pokemon_region_external_reference_source_external
        UNIQUE (asset_source_id, external_region_id),
    CONSTRAINT ck_pokemon_region_external_reference_external_id_not_blank
        CHECK (BTRIM(external_region_id) <> ''),
    CONSTRAINT ck_pokemon_region_external_reference_source_url
        CHECK (
            source_url IS NULL
            OR (
                BTRIM(source_url) <> ''
                AND source_url ~ '^https://'
            )
        ),
    CONSTRAINT ck_pokemon_region_external_reference_metadata
        CHECK (JSONB_TYPEOF(metadata) = 'object')
);

COMMENT ON TABLE public.pokemon_region_external_reference IS
    'Evidência de integração externa: mapeia pokemon_region para seu identificador em uma Fonte externa (PokéAPI etc.). Mesmo padrão conceitual de pokemon_species_external_reference (Query 6020) e pokedex_external_reference (Query 6050). RLS completamente fechado — não é dado self-service.';

COMMENT ON COLUMN public.pokemon_region_external_reference.pokemon_region_id IS
    'Região interna referenciada. ON DELETE CASCADE — evidência não sobrevive à Região. Imutável (protegido por trigger de governança, Query 6071).';

COMMENT ON COLUMN public.pokemon_region_external_reference.asset_source_id IS
    'Fonte externa (asset_source) que originou esta referência. ON DELETE RESTRICT. Imutável (protegido por trigger de governança, Query 6071).';

COMMENT ON COLUMN public.pokemon_region_external_reference.external_region_id IS
    'Identificador estável da Região na Fonte externa. Para PokéAPI: o id numérico do recurso region, serializado como TEXT (ex.: "1" para kanto) — nunca o slug/name (ex.: "kanto"), que é apresentacional/roteável na API, não o identificador canônico armazenado neste campo. Imutável (protegido por trigger de governança, Query 6071).';

COMMENT ON COLUMN public.pokemon_region_external_reference.metadata IS
    'Metadados adicionais da Fonte externa, em formato livre (JSONB), sempre um objeto.';

ALTER TABLE public.pokemon_region_external_reference
    ENABLE ROW LEVEL SECURITY;

-- Least privilege de tabela (mesmo padrão de Query 2147, já embutido
-- em 6030/6050 no momento da criação). Nenhum GRANT é criado aqui —
-- apenas REVOKE de privilégios de administração de schema que o app
-- nunca exerce; SELECT/INSERT/UPDATE/DELETE permanecem bloqueados por
-- RLS sem policy. service_role não recebe nenhum GRANT novo por esta
-- Query.
REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON public.pokemon_region_external_reference FROM anon, authenticated;

COMMIT;

-- ================================================================
-- Confirmado executado (2026-09-04, via apply_migration/MCP do
-- Supabase, projeto qjfutqujxrbzgrtkpgkg,
-- POKEMON-REGION-FOUNDATION-PHYSICAL-IMPLEMENTATION-01). Postcheck
-- independente (GATE 8, POKEMON-REGION-FOUNDATION-CANONICAL-
-- PROMOTION-01) confirmou colunas/tipos, PK, as duas UNIQUE compostas,
-- os três CHECKs, ON DELETE CASCADE para pokemon_region e ON DELETE
-- RESTRICT para asset_source, RLS habilitado sem nenhuma policy
-- (rls_enabled_no_policy INFO no Security Advisor — esperado), e zero
-- privilégio efetivo (has_table_privilege) para anon/authenticated/
-- service_role. Zero linhas (sourcing permanece SUSPENSO). Validação
-- comportamental e o script completo de validação (6810) permanecem
-- em database/proposals/2026-09-04-pokemon-region-foundation/ como
-- evidência histórica — não promovidos para database/schema/.
-- ================================================================
