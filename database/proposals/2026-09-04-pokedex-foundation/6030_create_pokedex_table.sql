/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6030 - Create Pokedex Table
Versão......: 1.1 (revisão: least privilege de tabela, Query 2147)
Status......: PROPOSTA (staging — aguardando execução)
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-04 (staging,
               COLLECTIONS-POKEDEX-POSITION-PHYSICAL-STAGING-01)

Descrição resumida:
Cria pokedex — catálogo raiz e canônico dos universos de Pokédex
(ex.: Pokédex Nacional). Primeira tabela da Fatia A ("Canonical
Pokédex Foundation") do módulo Pokémon Catalog Foundation (milhar
6000-6999, ADR-011 v1.2, LDM-176).

Descrição:
LDM-176 (`docs/domain-modeling/collections/logical-model.md`) define
Pokédex e Pokédex Position como conceitos próprios, deliberadamente
não colapsados em pokemon_species — decisão congelada, reafirmada em
COLLECTIONS-POKEDEX-POSITION-PHYSICAL-MODELING-REVISION-01/FINAL-01,
não reaberta nesta rodada:

```text
Pokédex
└── Pokédex Position
    ├── id
    ├── species_id → exactly one Pokémon Species
    └── position_number
```

pokedex é uma entidade-raiz de catálogo, mesmo esqueleto físico de
pokemon_generation (Query 6000): id/code/canonical_name/is_active/
created_at/updated_at. Sem FK — não é subordinada a nenhuma outra
entidade. V1 tem exatamente uma linha esperada (`code = 'NATIONAL'`),
mas a tabela existe desde já como catálogo (não singleton hard-coded)
para comportar, sem retrabalho físico, uma eventual Pokédex adicional
no futuro (ex.: regional) — mesmo raciocínio que já justifica
pokedex_position.position_number existir como campo próprio, distinto
de pokemon_species.national_dex_number (Query 6040).

Hierarquia:
(nenhuma — pokedex é raiz da Fatia A, mesmo papel de pokemon_generation
no restante do módulo)

Regras de Negócio:
- code deve ser único, maiúsculo, mesmo formato genérico já usado por
  pokemon_generation.code (^[A-Z][A-Z0-9_]*$) — decisão congelada
  desta rodada: código técnico estável, sem validação de convenção de
  nomenclatura específica imposta pelo CHECK (mesmo princípio já
  corrigido documentalmente em pokemon_generation, Query 6002).
- canonical_name não pode ser vazio.
- code e id imutáveis após criação (Query 6031); canonical_name e
  is_active permanecem corrigíveis administrativamente.
- Row Level Security deve permanecer habilitado, sem policy de leitura
  self-service nesta rodada — mesmo padrão fechado de pokemon_generation/
  pokemon_species (acesso futuro só via função administrativa ou
  service_role).
- Least privilege de tabela (achado de auditoria externa, correção
  desta revisão): REVOKE explícito de TRUNCATE/REFERENCES/TRIGGER/
  MAINTAIN de anon/authenticated, mesmo padrão vigente já aplicado ao
  Catálogo Editorial (Query 2147 - Least Privilege: Revoke DDL Grants
  Catalog Tables). Nenhum GRANT novo é criado — apenas REVOKE de
  privilégios de administração de schema que o app nunca exerce
  (SELECT/INSERT/UPDATE/DELETE não são tocados por este REVOKE; RLS
  sem policy já os bloqueia por completo). Aplicado explicitamente
  aqui mesmo que a correção de causa raiz de Query 2147 (ALTER DEFAULT
  PRIVILEGES FOR ROLE postgres IN SCHEMA public) já deva impedir que
  tabelas novas herdem esses privilégios — defesa em profundidade,
  sem depender silenciosamente do default de outra Query.

Fora de Escopo (decisão explícita desta rodada, Fatia A é
exclusivamente Canonical Pokédex Foundation):
- pokedex_position (Query 6040), pokedex_external_reference (Query
  6050) — vêm em seguida nesta mesma pasta de staging, mas são objetos
  distintos.
- collection_pokedex_reference, Collection Pokédex Scope, Pokédex
  Position Assignment, Primary Representative, Card → Primary Species,
  alteração de collection.completion_policy — Fatias B/C/D/E,
  explicitamente não antecipadas (COLLECTIONS-POKEDEX-POSITION-
  PHYSICAL-MODELING-FINAL-01, decisão 4).
- Regra física exigindo position_number = national_dex_number para o
  Pokédex Nacional — decisão congelada de NÃO criar (decisão 2):
  divergência é responsabilidade do futuro pipeline de ingestão/
  reconciliação, nunca aceita silenciosamente, mas também nunca
  imposta por CHECK/trigger cross-tabela.
- Seed de dados (nenhuma linha inserida por esta Query) e sincronização
  real com PokéAPI.

Pré-requisitos:
- Extensão ou infraestrutura que disponibilize gen_random_uuid() (já
  presente no projeto, mesma usada por pokemon_generation).

Como validar (após execução real, nunca antes):
Ver Query 6800 - Validate Pokedex Foundation, Seção 1 (estrutura) e
Seção 2 (comportamental) desta mesma pasta de staging.
===============================================================================
*/

BEGIN;

CREATE TABLE public.pokedex (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    code            VARCHAR(50) NOT NULL,
    canonical_name  VARCHAR(100) NOT NULL,

    is_active       BOOLEAN NOT NULL DEFAULT TRUE,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_pokedex_code
        UNIQUE (code),
    CONSTRAINT ck_pokedex_code_format
        CHECK (code ~ '^[A-Z][A-Z0-9_]*$'),
    CONSTRAINT ck_pokedex_canonical_name_not_blank
        CHECK (BTRIM(canonical_name) <> '')
);

COMMENT ON TABLE public.pokedex IS
    'Catálogo raiz e canônico dos universos de Pokédex (ex.: Pokédex Nacional). Entidade própria, deliberadamente não colapsada em pokemon_species (LDM-176, decisão congelada COLLECTIONS-POKEDEX-POSITION-PHYSICAL-MODELING-REVISION-01/FINAL-01). Fatia A ("Canonical Pokédex Foundation") do módulo Pokémon Catalog Foundation (ADR-011 v1.2).';

COMMENT ON COLUMN public.pokedex.id IS
    'Identificador técnico único do Pokédex. Imutável (protegido por trigger de governança, Query 6031).';

COMMENT ON COLUMN public.pokedex.code IS
    'Código técnico estável do Pokédex (ex.: NATIONAL). Único, maiúsculo. Imutável (protegido por trigger de governança, Query 6031).';

COMMENT ON COLUMN public.pokedex.canonical_name IS
    'Nome de exibição do Pokédex. Corrigível administrativamente.';

COMMENT ON COLUMN public.pokedex.is_active IS
    'Indica se o Pokédex está disponível para uso em novos registros. Corrigível administrativamente.';

COMMENT ON COLUMN public.pokedex.created_at IS
    'Data e hora de criação do registro. Imutável (protegido por trigger de governança, Query 6031).';

COMMENT ON COLUMN public.pokedex.updated_at IS
    'Data e hora da última atualização do registro.';

ALTER TABLE public.pokedex
    ENABLE ROW LEVEL SECURITY;

-- Least privilege de tabela (mesmo padrão de Query 2147 - Least
-- Privilege: Revoke DDL Grants Catalog Tables). Nenhum GRANT é criado
-- aqui — apenas REVOKE de privilégios de administração de schema que
-- o app nunca exerce; SELECT/INSERT/UPDATE/DELETE permanecem
-- bloqueados por RLS sem policy (Seção 1.9/1.10 da Query 6800).
REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON public.pokedex FROM anon, authenticated;

COMMIT;

-- ================================================================
-- PROPOSTA — NÃO EXECUTADA. Nenhuma migration foi aplicada ao banco
-- real por esta Query. Este arquivo existe apenas em
-- database/proposals/2026-09-04-pokedex-foundation/ para auditoria
-- externa, conforme COLLECTIONS-POKEDEX-POSITION-PHYSICAL-STAGING-01.
-- Só é promovido para database/schema/ após execução real confirmada
-- e autorização explícita de Fabrício (Princípio da Fonte Canônica).
-- ================================================================
