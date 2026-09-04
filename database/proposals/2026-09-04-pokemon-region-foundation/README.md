# Staging — Pokémon Region Foundation

| Campo | Valor |
|-------|-------|
| **Rodada** | POKEMON-REGION-FOUNDATION-PHYSICAL-STAGING-01 (revisado via POKEMON-REGION-FOUNDATION-PHYSICAL-STAGING-REVISION-01, GATE 4; implementado via POKEMON-REGION-FOUNDATION-PHYSICAL-IMPLEMENTATION-01, GATE 5; fechado via GATE 8 (auditoria independente) e promovido via POKEMON-REGION-FOUNDATION-CANONICAL-PROMOTION-01, GATE 9) |
| **Status** | **CLOSED / PROMOTED** — `6060`/`6061`/`6070`/`6071`/`6080` CONFIRMADO EXECUTADO no banco real e promovidos para `database/schema/`; `6810` CONFIRMADO EXECUTADO — resultado PASS, permanece nesta pasta como evidência histórica (mesmo padrão de `6800`) |
| **Data** | 2026-09-04 |
| **Módulo** | Pokémon Catalog Foundation (milhar 6000-6999, ADR-011 v1.2) |

**Nota de revisão (GATE 4):** auditoria do código real aprovou 6060/6061/6070/6071 sem alterações. `6080` e `6810` foram corrigidos (FK de `main_region_id` agora declara `ON UPDATE RESTRICT` explicitamente, além de `ON DELETE RESTRICT`; validação ampliada — ver tabela de arquivos abaixo).

**Nota de fechamento (GATE 9, POKEMON-REGION-FOUNDATION-CANONICAL-PROMOTION-01):** todos os 5 arquivos de DDL foram aplicados ao banco real (projeto `qjfutqujxrbzgrtkpgkg`) via `POKEMON-REGION-FOUNDATION-PHYSICAL-IMPLEMENTATION-01`, validados por `6810` (PASS) e por postcheck independente (GATE 8), e promovidos para `database/schema/` com corpo SQL idêntico ao desta pasta. Esta pasta é preservada como evidência histórica de staging/revisão/validação — não apagada. Sourcing continua **SUSPENSO**.

## Escopo desta rodada

Cria a estrutura física da Região Pokémon (Region) como entidade canônica própria, e o vínculo N:1 de `pokemon_generation` para sua Região principal. Não popula nenhuma linha — sourcing (carga real via PokéAPI) permanece **SUSPENSO**, retomado apenas em rodada futura própria.

Esta rodada é staging puro: os arquivos ficam em `database/proposals/2026-09-04-pokemon-region-foundation/` até execução real confirmada + autorização explícita de Fabrício, e só então são promovidos para `database/schema/` (nunca antes — princípio já seguido em todas as fatias anteriores do módulo: 02G, Pokédex Foundation).

## Decisões congeladas (herdadas das rodadas anteriores, não reabertas aqui)

- Region é entidade canônica própria, nunca concatenação TEXT com Generation (`POKEMON-REGION-DOMAIN-MODELING-AUDIT-01`, READ-ONLY, CLOSED).
- Cardinalidade Generation → Region é **N:1**: cada Generation tem exatamente uma Main Region; uma Region pode ser Main Region de 0..N Generations. A unicidade reversa observada hoje no dataset da PokéAPI (aparentemente 1:1) **não é invariante de domínio** — por isso **nenhuma UNIQUE** existe em `pokemon_generation.main_region_id` (`POKEMON-REGION-FOUNDATION-PHYSICAL-MODELING-01`, READ-ONLY, CLOSED).
- `main_region_id` é dado estrutural sourced, mas permanece corrigível a nível de banco (sem trigger de imutabilidade) — a proteção contra mudança não intencional vive na futura camada de sourcing/reconciliação (classificação DIVERGENT), não em `govern_pokemon_generation()`.
- Nomes canônicos de Region vêm de `names[language=en]` da PokéAPI, nunca do slug roteável.

## Arquivos desta pasta

| Arquivo | Objetivo |
|---------|----------|
| `6060_create_pokemon_region_table.sql` | Cria `pokemon_region` (id/code/canonical_name/is_active/created_at/updated_at), RLS fechado, hardening least-privilege (Query 2147). |
| `6061_create_pokemon_region_triggers.sql` | `normalize_/govern_/touch_updated_at_pokemon_region()`, protege id/code/created_at. `REVOKE EXECUTE` já embutido na criação. |
| `6070_create_pokemon_region_external_reference_table.sql` | Cria `pokemon_region_external_reference` (evidência de integração externa, mesmo padrão de `pokemon_species_external_reference`/`pokedex_external_reference`). |
| `6071_create_pokemon_region_external_reference_triggers.sql` | `normalize_/govern_/touch_updated_at_pokemon_region_external_reference()`, protege id/pokemon_region_id/asset_source_id/external_region_id/created_at. `REVOKE EXECUTE` embutido. |
| `6080_add_main_region_id_to_pokemon_generation.sql` | Incremento sobre `pokemon_generation` (Query 6000/6001, não reescritas): adiciona `main_region_id UUID NOT NULL REFERENCES pokemon_region(id) ON UPDATE RESTRICT ON DELETE RESTRICT`, sem UNIQUE, sem índice. |
| `6810_validate_pokemon_region_foundation.sql` | Script de validação completo (estrutural — incluindo prova simultânea de ON UPDATE + ON DELETE RESTRICT, todos os CHECKs, e zero DML de `service_role` — comportamental transacional com ROLLBACK, incluindo prova de N:1, privilégios de função, nota de performance) — **CONFIRMADO EXECUTADO, resultado PASS**. Permanece nesta pasta (não promovido para `database/schema/`, mesmo padrão de `6800`). |

## Ordem de execução (realizada)

1. `6060` → `6061` → `6070` → `6071` → `6080` (nesta ordem exata — `6080` depende de `pokemon_region` já existir). Todos CONFIRMADO EXECUTADO.
2. `6810` (validação, dentro de transação com `ROLLBACK` final — zero resíduo mesmo em execução real). CONFIRMADO EXECUTADO — resultado PASS.
3. Postcheck físico independente (GATE 8, colunas, PK, FKs, UNIQUE, CHECK, triggers, RLS, `has_table_privilege()`) — PASS/CLOSED.
4. Promoção de `6060`/`6061`/`6070`/`6071`/`6080` para `database/schema/` (GATE 9) — concluída nesta rodada.

## Fora de escopo desta rodada

- Sourcing real (PokéAPI → `pokemon_region`/`pokemon_generation.main_region_id`) — mecanismo já desenhado em rounds anteriores (Generation/Species/Pokédex, hoje SUSPENSO), Region ainda não integrada a ele. Retomada em rodada futura própria (próximo checkpoint: resumir `POKEMON-CATALOG-SOURCING-INITIAL-LOAD` incorporando `regions[]` antes de Generations).
- Qualquer edição de `6000_create_pokemon_generation_table.sql`/`6001_create_pokemon_generation_triggers.sql` — já `CONFIRMADO EXECUTADO`, nunca reescritos retroativamente.
- Locations, Areas, Version Groups, grafo de navegação entre Regiões.

## Pré-requisitos já satisfeitos no banco real

- Query 6000/6001 (`pokemon_generation` + triggers) — `CONFIRMADO EXECUTADO`.
- Query 200/6700 (`asset_source`, linha `POKEAPI`) — `CONFIRMADO EXECUTADO`.
- `pokemon_generation` com zero linhas no momento da execução real (pré-condição confirmada antes de `6080`, e reconfirmada no postcheck GATE 8 — `pokemon_generation`/`pokemon_region`/`pokemon_region_external_reference` seguem com zero linhas, sourcing SUSPENSO).

## Estado físico canônico

`6060`/`6061`/`6070`/`6071`/`6080` estão promovidos em `database/schema/`, com corpo SQL idêntico ao desta pasta (apenas header `Status`/`Data` e o bloco de rodapé foram atualizados na promoção). Esta pasta permanece como registro histórico de staging, revisão (GATE 4) e validação (`6810`) — não é a fonte canônica após a promoção.
