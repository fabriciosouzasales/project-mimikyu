/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6040 - Create Pokedex Position Table
Versão......: 1.1 (revisão: least privilege de tabela, Query 2147)
Status......: PROPOSTA (staging — aguardando execução)
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-04 (staging,
               COLLECTIONS-POKEDEX-POSITION-PHYSICAL-STAGING-01)

Descrição resumida:
Cria pokedex_position — uma posição de um Pokédex, referenciando
exatamente uma pokemon_species (LDM-176). Segunda tabela da Fatia A.

Descrição:
Campos e nomenclatura seguem literalmente o diagrama de LDM-176:

```text
Pokédex
└── Pokédex Position
    ├── id
    ├── species_id → exactly one Pokémon Species
    └── position_number
```

species_id (não pokemon_species_id) é nomenclatura deliberada — mesmo
padrão já usado por pokemon_species.generation_id (FK para
pokemon_generation, também sem repetir o nome completo da tabela
referenciada), e decisão congelada explicitamente nomeada em
COLLECTIONS-POKEDEX-POSITION-PHYSICAL-MODELING-FINAL-01.

position_number e pokemon_species.national_dex_number permanecem
campos distintos (decisão congelada, decisão 2 do mandato de
revisão): para o Pokédex Nacional os dois valores devem coincidir na
prática, mas essa igualdade NÃO é imposta por CHECK/trigger
cross-tabela nesta Fatia — é responsabilidade do futuro pipeline de
ingestão/reconciliação (fora de escopo), que deve tratar divergência
como erro/reconciliação explícita, nunca aceitá-la silenciosamente.
A existência de position_number como campo próprio (em vez de reusar
national_dex_number) é o que permite, sem retrabalho físico, uma
futura Pokédex não-nacional com numeração diferente.

Hierarquia:
Pokedex
  └── Pokedex Position

Regras de Negócio:
- Cada Position pertence a exatamente um Pokedex (pokedex_id NOT NULL).
- Cada Position referencia exatamente uma pokemon_species (species_id
  NOT NULL) — nunca uma Form/Variety diretamente (LDM-176).
- Uma Species aparece no máximo uma vez por Pokedex: UNIQUE(pokedex_id,
  species_id).
- Um número de posição é único dentro do Pokedex: UNIQUE(pokedex_id,
  position_number).
- position_number deve ser maior que zero.
- A exclusão de um pokedex referenciado deve arrastar suas Positions
  (ON DELETE CASCADE) — uma Position não tem existência própria sem o
  Pokedex ao qual pertence.
- A exclusão de uma pokemon_species referenciada deve ser impedida (ON
  DELETE RESTRICT) — mesmo raciocínio já usado por pokemon_species.
  generation_id (Query 6010) e pelas *_external_reference do módulo
  para o lado "Fonte"/entidade-pai estável.
- id, pokedex_id, species_id e created_at imutáveis após criação
  (Query 6041) — decisão congelada explícita (decisão 3 do mandato de
  revisão).
- position_number É dado editorial canônico, administrativamente
  corrigível — mesmo tratamento já dado a pokemon_species.
  national_dex_number (Query 6010/6011): NÃO protegido pelo trigger de
  governança (decisão congelada explícita, decisão 3).
- Row Level Security deve permanecer habilitado, sem policy de leitura
  self-service nesta rodada.
- Least privilege de tabela (achado de auditoria externa, correção
  desta revisão): REVOKE explícito de TRUNCATE/REFERENCES/TRIGGER/
  MAINTAIN de anon/authenticated, mesmo padrão vigente já aplicado ao
  Catálogo Editorial (Query 2147). Nenhum GRANT novo é criado.

Índices: nenhum além dos gerados pela PK e pelas duas UNIQUE
compostas. As duas UNIQUE já cobrem os padrões de busca previsíveis
com pokedex_id como coluna líder (por Species dentro de um Pokedex; por
número de posição dentro de um Pokedex). Nenhum índice isolado em
species_id foi adicionado — decisão explícita de não antecipar índice
especulativo sem padrão de acesso real que o justifique (mesmo
princípio já aplicado em pokemon_species_external_reference, Query
6020, e reafirmado no mandato de revisão desta Fatia). Ver Query 6800,
Seção 4 (Performance), para o racional completo.

Fora de Escopo (decisão explícita desta rodada):
- Regra física de igualdade position_number = national_dex_number —
  ver acima.
- pokedex_position_external_reference — decisão congelada de NÃO
  criar (ver header de 6050 para o racional completo, fundamentado no
  precedente card_variant, que também não tem external_reference
  própria por ser entidade composta de duas FKs já rastreáveis).
- Pokédex Position Assignment, Primary Representative — Fatia D, não
  antecipada.

Pré-requisitos:
- Query 6030 - Create Pokedex Table.
- Query 6010 - Create Pokemon Species Table (já CONFIRMADO EXECUTADO).

Como validar (após execução real, nunca antes):
Ver Query 6800 - Validate Pokedex Foundation, Seção 1 (estrutura) e
Seção 2 (comportamental) desta mesma pasta de staging.
===============================================================================
*/

BEGIN;

CREATE TABLE public.pokedex_position (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    pokedex_id       UUID NOT NULL
                         REFERENCES public.pokedex (id)
                         ON DELETE CASCADE,
    species_id       UUID NOT NULL
                         REFERENCES public.pokemon_species (id)
                         ON DELETE RESTRICT,

    position_number  INTEGER NOT NULL,

    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_pokedex_position_pokedex_species
        UNIQUE (pokedex_id, species_id),
    CONSTRAINT uq_pokedex_position_pokedex_number
        UNIQUE (pokedex_id, position_number),
    CONSTRAINT ck_pokedex_position_number_positive
        CHECK (position_number > 0)
);

COMMENT ON TABLE public.pokedex_position IS
    'Uma posição de um Pokédex, referenciando exatamente uma Pokémon Species (LDM-176). Fatia A ("Canonical Pokédex Foundation") do módulo Pokémon Catalog Foundation (ADR-011 v1.2).';

COMMENT ON COLUMN public.pokedex_position.id IS
    'Identificador técnico único da posição. Imutável (protegido por trigger de governança, Query 6041).';

COMMENT ON COLUMN public.pokedex_position.pokedex_id IS
    'Pokédex ao qual esta posição pertence. ON DELETE CASCADE — a posição não sobrevive ao Pokédex. Imutável (protegido por trigger de governança, Query 6041).';

COMMENT ON COLUMN public.pokedex_position.species_id IS
    'Pokémon Species referenciada por esta posição (LDM-176) — nunca uma Form/Variety diretamente. ON DELETE RESTRICT. Imutável (protegido por trigger de governança, Query 6041).';

COMMENT ON COLUMN public.pokedex_position.position_number IS
    'Número da posição dentro do Pokédex. Dado editorial canônico, corrigível administrativamente (não protegido pelo trigger de governança) — mesmo tratamento de pokemon_species.national_dex_number. Deliberadamente distinto de national_dex_number: não há regra física de igualdade entre os dois campos (decisão congelada, COLLECTIONS-POKEDEX-POSITION-PHYSICAL-MODELING-REVISION-01).';

COMMENT ON COLUMN public.pokedex_position.created_at IS
    'Data e hora de criação do registro. Imutável (protegido por trigger de governança, Query 6041).';

COMMENT ON COLUMN public.pokedex_position.updated_at IS
    'Data e hora da última atualização do registro.';

ALTER TABLE public.pokedex_position
    ENABLE ROW LEVEL SECURITY;

-- Least privilege de tabela (mesmo padrão de Query 2147 - Least
-- Privilege: Revoke DDL Grants Catalog Tables). Nenhum GRANT é criado
-- aqui — apenas REVOKE de privilégios de administração de schema que
-- o app nunca exerce; SELECT/INSERT/UPDATE/DELETE permanecem
-- bloqueados por RLS sem policy (Seção 1.9/1.10 da Query 6800).
REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON public.pokedex_position FROM anon, authenticated;

COMMIT;

-- ================================================================
-- PROPOSTA — NÃO EXECUTADA. Nenhuma migration foi aplicada ao banco
-- real por esta Query. Ver nota de status ao final de 6030.
-- ================================================================
