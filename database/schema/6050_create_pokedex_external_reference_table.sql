/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6050 - Create Pokedex External Reference Table
Versão......: 1.1 (revisão: least privilege de tabela + redação de
               external_pokedex_id, sem alteração de schema)
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-04 (staging em COLLECTIONS-POKEDEX-POSITION-
               PHYSICAL-STAGING-01, aplicado em 2026-09-04 via
               COLLECTIONS-POKEDEX-POSITION-PHYSICAL-IMPLEMENTATION-01)

Descrição resumida:
Cria pokedex_external_reference — mapeia um pokedex interno para seu
identificador em uma Fonte externa (PokéAPI etc.). Terceira e última
tabela da Fatia A.

Descrição:
Mesmo padrão físico de pokemon_species_external_reference (Query
6020), por sua vez herdado de card_set_external_reference (Query 240):
evidência de integração externa, não dado self-service. Decisão
fundamentada nesta rodada (COLLECTIONS-POKEDEX-POSITION-PHYSICAL-
MODELING-FINAL-01), a partir de dois precedentes reais opostos já
existentes no repositório:

- Entidades-raiz de catálogo com identidade própria numa Fonte externa
  (card_set → card_set_external_reference; card → card_external_
  reference; pokemon_species → pokemon_species_external_reference) —
  todas seguem este mesmo esqueleto. pokedex se encaixa aqui: é
  entidade-raiz (como card_set/pokemon_species), com identidade
  própria e independente na PokéAPI (o recurso pokedex tem seu próprio
  id numérico estável — ex.: 1 para o Pokédex Nacional — distinto do
  slug/name "national", que é apresentacional/roteável na API, não o
  identificador canônico a ser armazenado; ver correção de redação
  desta rodada, decisão 5 de COLLECTIONS-POKEDEX-POSITION-PHYSICAL-
  STAGING-REVISION-01, abaixo em external_pokedex_id).
- Entidades derivadas/compostas, cuja identidade é a própria
  combinação de duas FKs já ancoradas (card_variant, composto de
  card_id + card_variant_type_id) — NÃO têm external reference
  própria; a tradução do dado bruto externo acontece via as tabelas
  dos dois lados que já a compõem. pokedex_position se encaixa aqui —
  por isso pokedex_position_external_reference NÃO é criada nesta
  rodada (decisão congelada explícita): sua identidade é inteiramente
  a composição de pokedex_id + species_id, ambos já rastreáveis
  externamente pelas próprias tabelas de referência (esta, e
  pokemon_species_external_reference). A ingestão de uma entrada de
  Pokédex da PokéAPI (entry_number + referência a uma species, dentro
  do payload do recurso pokedex) resolve os dois lados via as
  referências já existentes e faz UPSERT por UNIQUE(pokedex_id,
  species_id) — sem precisar de nenhum identificador externo próprio
  de "posição" (a PokéAPI, aliás, não expõe a posição como um recurso
  independente com seu próprio id).

Mesmo princípio de "nunca pokeapi_id solto na entidade canônica" já
aplicado a asset_source/pokemon_species_external_reference (Query
6700/6020): nenhuma coluna pokeapi_id em pokedex; o identificador
externo mora exclusivamente aqui.

Hierarquia:
Pokedex
  └── Pokedex External Reference (por Asset Source)

Regras de Negócio:
- Cada linha vincula exatamente um pokedex a exatamente um
  asset_source.
- external_pokedex_id não pode ser vazio.
- source_url, quando presente, deve iniciar com https:// (mesmo
  padrão de asset_source/pokemon_species_external_reference).
- metadata é JSONB, nunca nulo, sempre um objeto (nunca array/escalar).
- Unicidade dupla: (pokedex_id, asset_source_id) — um Pokedex não pode
  ter duas referências para a mesma Fonte; (asset_source_id,
  external_pokedex_id) — um external_pokedex_id não pode apontar para
  dois Pokedex na mesma Fonte.
- A exclusão de um pokedex referenciado deve arrastar suas referências
  externas (ON DELETE CASCADE) — evidência de integração não tem
  existência própria sem o Pokedex que descreve.
- A exclusão de um asset_source referenciado deve ser impedida (ON
  DELETE RESTRICT) — mesmo raciocínio de pokemon_species_external_
  reference.asset_source_id.
- Row Level Security deve permanecer habilitado, sem nenhuma policy
  (SELECT/INSERT/UPDATE/DELETE) nesta rodada — tabela completamente
  fechada a authenticated comum, mesma decisão congelada de
  pokemon_species_external_reference.

Índices: nenhum além dos gerados pela PK e pelas duas UNIQUE
compostas — mesma decisão explícita já tomada em pokemon_species_
external_reference (Query 6020) de não adicionar índices
especulativos (ex.: nenhum índice isolado por is_active).

Fora de Escopo (decisão explícita desta rodada):
- pokedex_position_external_reference — ver racional completo acima,
  decisão congelada de NÃO criar.
- Pipeline de sincronização real com PokéAPI/TCGdex, RPC de escrita
  self-service, admin UI.

Pré-requisitos:
- Query 6030 - Create Pokedex Table.
- Query 200 - Create Asset Source Table (já CONFIRMADO EXECUTADO;
  linha POKEAPI já existe via Query 6700, CONFIRMADO EXECUTADO).
===============================================================================
*/

BEGIN;

CREATE TABLE public.pokedex_external_reference (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    pokedex_id            UUID NOT NULL
                              REFERENCES public.pokedex (id)
                              ON DELETE CASCADE,
    asset_source_id       UUID NOT NULL
                              REFERENCES public.asset_source (id)
                              ON DELETE RESTRICT,

    external_pokedex_id   TEXT NOT NULL,
    source_url            TEXT,
    metadata              JSONB NOT NULL DEFAULT '{}'::JSONB,

    is_active             BOOLEAN NOT NULL DEFAULT TRUE,

    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_pokedex_external_reference_pokedex_source
        UNIQUE (pokedex_id, asset_source_id),
    CONSTRAINT uq_pokedex_external_reference_source_external
        UNIQUE (asset_source_id, external_pokedex_id),
    CONSTRAINT ck_pokedex_external_reference_external_id_not_blank
        CHECK (BTRIM(external_pokedex_id) <> ''),
    CONSTRAINT ck_pokedex_external_reference_source_url
        CHECK (
            source_url IS NULL
            OR (
                BTRIM(source_url) <> ''
                AND source_url ~ '^https://'
            )
        ),
    CONSTRAINT ck_pokedex_external_reference_metadata
        CHECK (JSONB_TYPEOF(metadata) = 'object')
);

COMMENT ON TABLE public.pokedex_external_reference IS
    'Evidência de integração externa: mapeia pokedex para seu identificador em uma Fonte externa (PokéAPI etc.). Mesmo padrão conceitual de pokemon_species_external_reference (Query 6020) e card_set_external_reference (Query 240). RLS completamente fechado — não é dado self-service.';

COMMENT ON COLUMN public.pokedex_external_reference.pokedex_id IS
    'Pokedex interno referenciado. ON DELETE CASCADE — evidência não sobrevive ao Pokedex. Imutável (protegido por trigger de governança, Query 6051).';

COMMENT ON COLUMN public.pokedex_external_reference.asset_source_id IS
    'Fonte externa (asset_source) que originou esta referência. ON DELETE RESTRICT. Imutável (protegido por trigger de governança, Query 6051).';

COMMENT ON COLUMN public.pokedex_external_reference.external_pokedex_id IS
    'Identificador estável do Pokedex na Fonte externa. Para PokéAPI: o id numérico do recurso pokedex, serializado como TEXT (ex.: "1" para o Pokédex Nacional) — nunca o slug/name (ex.: "national"), que é apresentacional/roteável na API, não o identificador canônico armazenado neste campo. Imutável (protegido por trigger de governança, Query 6051).';

COMMENT ON COLUMN public.pokedex_external_reference.metadata IS
    'Metadados adicionais da Fonte externa, em formato livre (JSONB), sempre um objeto.';

ALTER TABLE public.pokedex_external_reference
    ENABLE ROW LEVEL SECURITY;

-- Least privilege de tabela (mesmo padrão de Query 2147 - Least
-- Privilege: Revoke DDL Grants Catalog Tables). Nenhum GRANT é criado
-- aqui — apenas REVOKE de privilégios de administração de schema que
-- o app nunca exerce; SELECT/INSERT/UPDATE/DELETE permanecem
-- bloqueados por RLS sem policy (Seção 1.9/1.10 da Query 6800).
REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON public.pokedex_external_reference FROM anon, authenticated;

COMMIT;

-- ================================================================
-- Confirmado executado (2026-09-04, via apply_migration/MCP do
-- Supabase, projeto qjfutqujxrbzgrtkpgkg,
-- COLLECTIONS-POKEDEX-POSITION-PHYSICAL-IMPLEMENTATION-01). Postcheck
-- físico (Query 6800, Seção 1) confirmou colunas/tipos/defaults, PK,
-- as duas FKs com ON DELETE correto (CASCADE em pokedex_id, RESTRICT
-- em asset_source_id), as duas UNIQUE, os três CHECKs, RLS habilitado
-- sem nenhuma policy, e zero privilégio efetivo (has_table_privilege)
-- para anon/authenticated. Validação comportamental (Seção 2.3)
-- confirmou normalize, as duas UNIQUE isoladamente, o CHECK de
-- metadata isoladamente, a imutabilidade de external_pokedex_id, e o
-- RESTRICT em asset_source_id comprovado especificamente para a FK
-- desta tabela via GET STACKED DIAGNOSTICS. Script completo permanece
-- em database/proposals/2026-09-04-pokedex-foundation/ como evidência
-- histórica — não promovido para database/schema/.
-- ================================================================
