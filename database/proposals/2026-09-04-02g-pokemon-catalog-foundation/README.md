# Staging — 02G Pokémon Catalog Foundation

Rodada: `COLLECTIONS-PHYSICAL-INCREMENT-02G-IMPLEMENTATION-01` (2026-09-04).

**Status: PROMOVIDO.** Os 7 arquivos desta pasta foram aplicados com sucesso no banco real (projeto `qjfutqujxrbzgrtkpgkg`, via `apply_migration`/MCP do Supabase), validados estruturalmente e comportamentalmente, e promovidos para `database/schema/` com a nota "CONFIRMADO EXECUTADO" e evidência de execução. Esta pasta é mantida apenas como histórico do staging original — a fonte canônica é `database/schema/6000...6700`.

## Arquivos

| Query | Objetivo |
|-------|----------|
| 6000 | `pokemon_generation` — tabela |
| 6001 | `pokemon_generation` — triggers (normalize/govern/touch_updated_at) |
| 6010 | `pokemon_species` — tabela |
| 6011 | `pokemon_species` — triggers |
| 6020 | `pokemon_species_external_reference` — tabela |
| 6021 | `pokemon_species_external_reference` — triggers |
| 6700 | Seed: linha `POKEAPI` em `asset_source` |

## Decisões congeladas honradas (ver mandato completo na conversa)

- Sem `game_id` em `pokemon_generation`/`pokemon_species` (entidades globais do universo Pokémon, não do TCG).
- `pricing_source` confirmado existente no banco real (Query 3000/3001/3002) durante esta rodada — não investigado a fundo, registrado como gap de documentação separado (arquivo não localizado em `database/schema/`), não bloqueante para 02G.
- `pokemon_species_external_reference` com RLS completamente fechado (sem `catalog_admin_select`, sem GRANT a `authenticated`).
- `pokemon_generation.code` = `GENERATION_I`, `GENERATION_II`... + `ordinal_number` inteiro separado.
- `pokemon_species.national_dex_number` corrigível administrativamente (não protegido pelo trigger de governança); só `id`/`created_at` protegidos.
- Milhar `6000`–`6999` — novo módulo "Pokémon Catalog Foundation", confirmado livre via Glob antes do uso (nenhum arquivo `6*` pré-existente em `database/schema/` ou `database/migrations/`).
- Nenhum índice especulativo além dos exigidos pelas UNIQUE/PK e do índice explícito em `pokemon_species(generation_id)`.
