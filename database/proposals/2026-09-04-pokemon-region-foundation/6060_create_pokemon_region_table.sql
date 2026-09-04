/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6060 - Create Pokemon Region Table
Versão......: 1.0
Status......: PROPOSTO (staging — NÃO executado)
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-04 (staging em POKEMON-REGION-FOUNDATION-
               PHYSICAL-STAGING-01, após POKEMON-REGION-DOMAIN-
               MODELING-AUDIT-01 e POKEMON-REGION-FOUNDATION-PHYSICAL-
               MODELING-01, ambos READ-ONLY, CLOSED)

Descrição resumida:
Cria pokemon_region — catálogo raiz e canônico das Regiões Pokémon
(ex.: Kanto, Johto, Hoenn...). Primeira tabela da Region Foundation do
módulo Pokémon Catalog Foundation (milhar 6000-6999, ADR-011 v1.2).
Sourcing (carga real de dados via PokéAPI) permanece SUSPENSO nesta
rodada — esta Query cria apenas a estrutura, sem inserir nenhuma linha.

Descrição:
POKEMON-REGION-DOMAIN-MODELING-AUDIT-01 (READ-ONLY, CLOSED) confirmou,
via auditoria direta da PokéAPI (`/region/`, 11 regiões: kanto, johto,
hoenn, sinnoh, unova, kalos, alola, galar, hisui, paldea, orre — ids
1-11), que Region é entidade canônica própria, independente de
Generation — inclusive existem Regiões sem nenhuma Generation principal
associada (`main_generation: null` para Orre e Hisui). UX alvo
("Generation I · Kanto") nunca deve depender de concatenação TEXT.

pokemon_region é uma entidade-raiz de catálogo, mesmo esqueleto físico
de pokemon_generation (Query 6000) e pokedex (Query 6030): id/code/
canonical_name/is_active/created_at/updated_at. Sem FK — não é
subordinada a nenhuma outra entidade. A relação inversa (Generation →
Main Region) é modelada como coluna em pokemon_generation (Query 6080),
não aqui.

Hierarquia:
(nenhuma — pokemon_region é raiz, mesmo papel de pokemon_generation e
pokedex no restante do módulo)

Regras de Negócio:
- code deve ser único, maiúsculo, mesmo formato genérico já usado por
  pokemon_generation.code e pokedex.code (^[A-Z][A-Z0-9_]*$) — código
  técnico estável, sem validação de convenção de nomenclatura
  específica imposta pelo CHECK.
- canonical_name não pode ser vazio. Fonte esperada no sourcing futuro:
  `names[language=en].name` da PokéAPI — nunca o slug/name roteável
  (decisão congelada em POKEMON-REGION-DOMAIN-MODELING-AUDIT-01).
- code e id imutáveis após criação (Query 6061); canonical_name e
  is_active permanecem corrigíveis administrativamente.
- Row Level Security deve permanecer habilitado, sem policy de leitura
  self-service nesta rodada — mesmo padrão fechado de pokemon_generation/
  pokedex (acesso futuro só via função administrativa ou service_role).
- Least privilege de tabela (mesmo padrão já aplicado a pokemon_
  generation/pokedex): REVOKE explícito de TRUNCATE/REFERENCES/
  TRIGGER/MAINTAIN de anon/authenticated (Query 2147 - Least Privilege:
  Revoke DDL Grants Catalog Tables). Nenhum GRANT novo é criado — nem
  para anon/authenticated, nem para service_role (que hoje não possui
  nenhum DML direto nas 6 tabelas Pokémon/Pokédex existentes,
  confirmado por consulta real a role_table_grants nesta mesma rodada
  de modelagem — este padrão é preservado, não alterado). Defesa em
  profundidade, sem depender silenciosamente do default de outra Query.

Fora de Escopo (decisão explícita desta rodada):
- pokemon_region_external_reference (Query 6070/6071) — vem em seguida
  nesta mesma pasta de staging, mas é objeto distinto.
- Alteração de pokemon_generation (Query 6080) — incremento separado,
  não reescreve 6000/6001.
- UNIQUE ou índice em qualquer FK reversa de Generation → Region — não
  pertence a esta tabela; ver 6080 para o racional completo de
  cardinalidade N:1 (decisão congelada em POKEMON-REGION-FOUNDATION-
  PHYSICAL-MODELING-01: uma Region pode ser Main Region de 0..N
  Generations, unicidade reversa NÃO é invariante de domínio).
- Locations, Areas, Version Groups, grafo de navegação entre Regiões —
  explicitamente fora de escopo (POKEMON-REGION-DOMAIN-MODELING-
  AUDIT-01).
- Seed de dados (nenhuma linha inserida por esta Query) e sincronização
  real com PokéAPI — sourcing permanece SUSPENSO.

Pré-requisitos:
- Extensão ou infraestrutura que disponibilize gen_random_uuid() (já
  presente no projeto, mesma usada por pokemon_generation/pokedex).
===============================================================================
*/

BEGIN;

CREATE TABLE public.pokemon_region (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    code            VARCHAR(50) NOT NULL,
    canonical_name  VARCHAR(100) NOT NULL,

    is_active       BOOLEAN NOT NULL DEFAULT TRUE,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_pokemon_region_code
        UNIQUE (code),
    CONSTRAINT ck_pokemon_region_code_format
        CHECK (code ~ '^[A-Z][A-Z0-9_]*$'),
    CONSTRAINT ck_pokemon_region_canonical_name_not_blank
        CHECK (BTRIM(canonical_name) <> '')
);

COMMENT ON TABLE public.pokemon_region IS
    'Catálogo raiz e canônico das Regiões Pokémon (ex.: Kanto, Johto, Hoenn). Entidade própria, independente de pokemon_generation — decisão congelada POKEMON-REGION-DOMAIN-MODELING-AUDIT-01/POKEMON-REGION-FOUNDATION-PHYSICAL-MODELING-01. Sourcing (carga via PokéAPI) permanece SUSPENSO nesta rodada.';

COMMENT ON COLUMN public.pokemon_region.id IS
    'Identificador técnico único da Região. Imutável (protegido por trigger de governança, Query 6061).';

COMMENT ON COLUMN public.pokemon_region.code IS
    'Código técnico estável da Região (ex.: KANTO). Único, maiúsculo. Imutável (protegido por trigger de governança, Query 6061).';

COMMENT ON COLUMN public.pokemon_region.canonical_name IS
    'Nome de exibição da Região. Fonte esperada no sourcing futuro: names[language=en] da PokéAPI, nunca o slug roteável. Corrigível administrativamente.';

COMMENT ON COLUMN public.pokemon_region.is_active IS
    'Indica se a Região está disponível para uso em novos registros. Corrigível administrativamente.';

COMMENT ON COLUMN public.pokemon_region.created_at IS
    'Data e hora de criação do registro. Imutável (protegido por trigger de governança, Query 6061).';

COMMENT ON COLUMN public.pokemon_region.updated_at IS
    'Data e hora da última atualização do registro.';

ALTER TABLE public.pokemon_region
    ENABLE ROW LEVEL SECURITY;

-- Least privilege de tabela (mesmo padrão de Query 2147 - Least
-- Privilege: Revoke DDL Grants Catalog Tables, já embutido em 6030/6050
-- no momento da criação). Nenhum GRANT é criado aqui — apenas REVOKE de
-- privilégios de administração de schema que o app nunca exerce;
-- SELECT/INSERT/UPDATE/DELETE permanecem bloqueados por RLS sem
-- policy. service_role não recebe nenhum GRANT novo por esta Query.
REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON public.pokemon_region FROM anon, authenticated;

COMMIT;

-- ================================================================
-- PROPOSTO — staging, NÃO executado. Este arquivo permanece em
-- database/proposals/2026-09-04-pokemon-region-foundation/ até
-- autorização explícita de Fabrício para execução real, seguida de
-- promoção para database/schema/ (só após CONFIRMADO EXECUTADO,
-- nunca antes).
-- ================================================================
