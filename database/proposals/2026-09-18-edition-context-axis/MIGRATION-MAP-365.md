# MAPA DE MIGRAÇÃO — READY

**READY_STRUCTURAL 365 = READY_UNCONDITIONED 285 + READY_PRICING_CONDITIONED 80.**
Somente as **285** entram na futura migration `2213`.

Regra de derivação: **nenhum destino vem do `code` do tipo contaminado.**
Todos vêm do `raw_data` original, acessível porque as 365 têm **100% de lineage**
(`catalog_variant_import_row.resulting_variant_id`).

- Finish target: do `type`/`foil` residual após remover os tokens de contexto.
- Edition Context target: profile cujo `traits_signature` = conjunto exato dos
  tokens de contexto da própria `raw_data`.
- Printing target: `NULL` em 365/365 (nenhuma READY tem profile de tiragem).
- Evidence: `catalog_variant_import_row.id` + `raw_data`.

| Legacy type | Qtd | → Finish | → Printing | → Edition Context | Colisão |
|---|---:|---|---|---|:---:|
| `SATANDARD_REWARDS` | 51 | `STANDARD` | NULL | `PROGRAM_PLAYER_REWARDS` | sim |
| `STAFF_HOLO` 🔒 **CONDICIONADO** | 40 | `HOLO` | NULL | `ROLE_STAFF` | sim |
| `SET_LOGO_REVERSE` 🔒 **CONDICIONADO** (SVP 38 + DP1 2) | 40 | `HOLO` | NULL | `ARTWORK_SET_LOGO` | parcial |
| `REWARDS_HOLO` | 30 | `HOLO` | NULL | `PROGRAM_PLAYER_REWARDS` | sim |
| `POKEMON_CENTER_HOLO` | 19 | `HOLO` | NULL | `CHANNEL_POKEMON_CENTER` | sim |
| `COSMOS_REWARDS_HOLO` | 18 | `COSMOS_HOLO` | NULL | `PROGRAM_PLAYER_REWARDS` | sim |
| `COSMOS_REWARDS_REVERSE` | 17 | `COSMOS_REVERSE` | NULL | `PROGRAM_PLAYER_REWARDS` | sim |
| `COSMOS_PROFESSOR_REVERSE` | 16 | `COSMOS_REVERSE` | NULL | `PROGRAM_PROFESSOR` | sim |
| `STANDARDS_TEACHER_PROGRAM` | 14 | `STANDARD` | NULL | `PROGRAM_PROFESSOR` | sim |
| `STANDARD_GYM_CHALLENGE` | 9 | `STANDARD` | NULL | `EVENT_GYM_CHALLENGE` | sim |
| `GAMESTOP_HOLO` | 9 | `HOLO` | NULL | `CHANNEL_GAMESTOP` | sim |
| `STANDARD_REGIONAL_CHAMPIONSHIPS` | 8 | `STANDARD` | NULL | `EVENT_REGIONALS` | sim |
| `EBGAMES_HOLO` | 8 | `HOLO` | NULL | `CHANNEL_EB_GAMES` | sim |
| `STANDARD_PIKACHU_WORLD_2000` | 6 | `STANDARD` | NULL | `CAMPAIGN_PIKACHU_WORLD_2000` | sim |
| `W_PROMO_STAMPED` | 6 | `STANDARD` | NULL | `CHANNEL_WOTC_PROMO` | sim |
| `SET_LOGO_STANDARDS` (DP1) | 4 | `STANDARD` | NULL | `ARTWORK_SET_LOGO` | sim |
| `STANDARD_FIRST_MOVIE` | 4 | `STANDARD` | NULL | `CAMPAIGN_FIRST_MOVIE` | sim |
| `STANDARD_FIRST_MOVIE_INVERTED` | 4 | `STANDARD` | NULL | `CAMPAIGN_FIRST_MOVIE_INVERTED` | sim |
| `STANDARD_REGIONAL_CHAMPIONSHIPS_STAFF` | 4 | `STANDARD` | NULL | `EVENT_REGIONALS` + `ROLE_STAFF` | sim |
| `STANDARDS_LEAGUE` | 4 | `STANDARD` | NULL | `PROGRAM_LEAGUE` ⚠️ B3 | sim |
| `STANDARD_WORLDS_2024` | 3 | `STANDARD` | NULL | `EVENT_WORLDS_2024` | sim |
| `STANDARDS_HORIZONS` | 3 | `STANDARD` | NULL | `CAMPAIGN_HORIZONS` | sim |
| `GYM_CHALLENGE_HOLO` | 3 | `HOLO` | NULL | `EVENT_GYM_CHALLENGE` | sim |
| 21× `STANDARDS_WORLDS_*` / `ASIA` | 21 | `STANDARD` | NULL | `EVENT_WORLDS_<ano>` (+ `PLACEMENT_*` / `ROLE_STAFF`) | sim |
| Demais (24 tipos, 1 cada) | **24** | conforme residual | NULL | conforme família | misto |
| **Σ** | **365** | | | | **188 sim** |

## Invariantes da migração real (`2213`) — e da simulação `2831`

1. `UPDATE` puro — `card_variant.id` preservado em 365/365.
2. `variant_order` e `is_default` **não aparecem no `SET`**.
3. Lineage intacto por consequência (o `id` não muda).
4. `WHERE cv.id NOT IN (hold_frozen)` — H1 inelegível por construção.
5. **Collision gate roda ANTES** e simula a identidade nova (4 componentes);
   qualquer colisão não prevista ⇒ `RAISE EXCEPTION`, transação inteira aborta.
6. **READY_PRICING_CONDITIONED (80)** fica FORA do plano por guard executável
   derivado do LIVE (ver `HOLD-MANIFEST.md` H6) — `STAFF_HOLO` 40 e
   `SET_LOGO_REVERSE` 40. A migration real opera sobre **285**.
7. O arquivo `2831` é **SIMULAÇÃO** (termina em `ROLLBACK`). A migration real
   será `2213`, escrita somente após o Gate A.

## Conferência aritmética (GATE-A-01)

A versão anterior desta tabela fechava a linha residual em "~43", o que somava
**384 ≠ 365**. Soma das 23 linhas nomeadas + a linha agregada de 21 Worlds:
**341**. Residual correto: **365 − 341 = 24**. Corrigido acima.

Das 365: **80 são 🔒 PRICING_CONDITIONED** (`STAFF_HOLO` 40 + `SET_LOGO_REVERSE`
40) ⇒ **285 entram em `2213`**.
