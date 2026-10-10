# Cartas sem variante em coleções parciais + recuperação XY (2026-10-10)

| Campo | Valor |
|---|---|
| **Status** | Passo A EXECUTADO; R1 EXECUTADO (2026-10-10, canônica `database/migrations/2251_…`); pendentes Importar Imagens e Importar Variantes dos 8 Sets pela UI |
| **Mandato** | Fabrício, 2026-10-10: "Aprovo grupos 1 e 2 agora e sigo pela frente das 15 cartas faltantes" |
| **Origem** | Seletor de Importar Variantes: 12 coleções com cartas "sem variante" parciais (33 cartas) |

## Passo A — 21 variantes HOLO (EXECUTADO, 2026-10-10)

Inseridas pelo writer canônico `internal.write_card_variant('CREATE', …, HOLO, order 1)`, gates de escopo
(21 cartas, todas sem variante) e de delta (+21).

| Grupo | Cartas | Evidência |
|---|---|---|
| 1. Yellow A Alternate | XY2 88a; XY4 24a, 65a; XY6 77a, 92a; XY7 75a; XY9 107a, 98b; XY10 43a, 105a; G1 28a, 73a; XYP XY67a, XY150a, XY177a, XY198a, XY200a | Reimpressões Full Art com "A" amarelo (Bulbapedia, *Yellow A Alternate cards*). O `normal` da TCGdex é `variantId: generated`, não evidência. |
| 2. SWSHP 112–115 | Cinderace, Inteleon, Cresselia, Passimian | Promos da Chilling Reign (Build & Battle); TCGdex `holo: true`; vizinhas 104–126 já são HOLO puro. |

Resultado: `card_variant` 37.314 → **37.335**; cartas sem variante 330 → **309**.

Pendentes desta lista (12 cartas, pesquisa/decisão): BWP BW77/BW78 (cancelados em inglês), XYP XY176/XY202,
SVP 191/192/213/214/215/225/226, MEP 028.

## Passo B — 12 promos restantes (EXECUTADO, 2026-10-10, aprovado por Fabrício)

| Carta | Gravado | Evidência |
|---|---|---|
| XYP XY202 Pikachu | HOLO | Promo de liga (Evolutions); mercado só lista holofoil |
| XYP XY176 Champions Festival | STANDARD | Participação Worlds 2016, não holo; versões carimbadas por colocação ficam para depois |
| SVP 191 Sprigatito, 192 Fuecoco | HOLO | Grand Adventure Collection (nov/2024), Bulbapedia |
| SVP 213, 214, 215 | STANDARD | Illustration Contest 2024, não holo |
| SVP 225 Pikachu | STANDARD + `EVENT_WORLDS_2025` | Worlds 2025, não holo; mesmo formato da SVP 224. Versão "WINNER" fica para depois |
| MEP 028 Celebratory Fanfare | STANDARD | Ace Trainer 2024-25; lojas com base TCGplayer dizem Normal (fontes divergem) |
| BWP BW77 Pikachu, BW78 Raichu | STANDARD | Cancelados em inglês; Fabrício decidiu manter com STANDARD |
| SVP 226 Terapagos & Friends | **inativada** (`admin_deactivate_card`) | Carta jumbo (oversized); o catálogo não modela tamanho |

`card_variant` 37.357 → **37.368**. Cartas ativas sem variante: **297** = Trainer Kits 270 + CEL25CC 25 + ME5.5 2.

## R1 — 15 cartas que não existem no catálogo (dry-run PASS)

**Causa.** Na carga TCGdex pt-BR de 11/09 a regra antiga `deriveCollectorOrder()` deu às cartas com sufixo a
ordem da carta seguinte; 15 linhas falharam com `uq_card_card_set_collector_order` e nunca viraram carta. A
regra SET-LEVEL (`collector-order.ts`, 2026-09-10) corrige cargas novas, mas os 8 Sets nunca foram reprocessados.

| Set | Cartas ausentes |
|---|---|
| XY2 | 88 (Ferreiro) |
| XY3 | 55a |
| XY4 | 25, 67 |
| XY6 | 77 (Shaymin-EX), 93 |
| XY7 | 76 |
| XY8 | 146a |
| XY9 | 98, 98a, 110 |
| XY10 | 43 (Regirock-EX), 54a, 108, 111a |

**Script:** `R1_recover_xy_collector_order_and_missing_cards.sql` (plano por conjunto completo, ordem natural
`88 < 88a < 88b < 89`, reordenação em duas fases, criação via `internal.write_card`, Primary Species por job).

**Dry-run (2026-10-10, desfeito):** gates G0–G6 PASS; 966 → 981 cartas nos 8 Sets; 359 ordens mudam de fato;
15 inseridas; 8 jobs → COMPLETED; ordens densas 1..N em todos; Primary Species resolvida para 6 cartas Pokémon.

**Apply (2026-10-10, aprovado por Fabrício):** mesmos números do dry-run. Leitura posterior: XY2 110, XY3 114,
XY4 124, XY6 112, XY7 101, XY8 165, XY9 126, XY10 129 cartas, cada Set com ordem 1..N; 8 jobs COMPLETED; as 15
novas aparecem como "sem variante" até a importação de variantes.

**Variantes das 15 (2026-10-10, execução direta).** Importar Variantes pela UI falhou nos Sets XY com
`VARIANT_SOURCE_UNSUPPORTED_FOR_CORRELATED_CARDS` (a TCGdex não tem `variants` em nenhuma carta XY; por isso a
F6 usou a 2ª fonte). As 22 variantes foram gravadas por `internal.write_card_variant`, com o snapshot
`pokemontcg-snapshot-2026-10-09` como evidência (`F3/stage_xy*.sql` da proposta variant-coverage-gap):
`normal + reverseHolofoil` → STANDARD (1) + REVERSE_HOLO (2) em XY2 88, XY4 25, XY6 93, XY7 76, XY9 98/110,
XY10 108; `holofoil` → HOLO em XY4 67, XY6 77, XY10 43; os 5 Yellow A Alternate sem chave de preço (XY3 55a,
XY8 146a, XY9 98a, XY10 54a/111a) → HOLO, mesma decisão do Passo A. `card_variant` 37.335 → **37.357**.

**Imagens:** importadas em XY2–XY9; XY8 146a sem imagem na TCGdex EN (`TCGDEX_IMAGE_NOT_AVAILABLE`); XY10 ainda
não importado (43, 54a, 108, 111a).

**Depois do apply, pela UI:** Importar Imagens dos 8 Sets (cria `card_external_reference` e `card_asset`) e
Importar Variantes dos 8 Sets (só as 15 cartas novas geram linhas).
