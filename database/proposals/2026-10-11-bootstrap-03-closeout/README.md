# CATALOG-HISTORICAL-BOOTSTRAP-03 — closeout

| Campo | Valor |
|---|---|
| **Status** | **EXECUTADA / CLOSED** (2026-10-11, LIVE `qjfutqujxrbzgrtkpgkg`) |
| **Sequência** | ROADMAP, item 6: ME5.5 ✔ → **BOOTSTRAP-03 closeout** → DEFAULT-BACKFILL-01 → Pricing 80 → gate final de Card Variants |
| **Decisões de Fabrício (2026-10-11)** | Trainer Kits sem variante: "Usar a Scrydex". CEL25CC: "Criar HOLO pela tabela" (revoga a decisão de 2026-10-09 de deixá-la sem variante). |
| **Artefato** | `database/migrations/2257_bootstrap03_closeout_variants.sql` (CONFIRMADO EXECUTADO) · emenda v0.4 do ADR-034 |

## 1. Diagnóstico (LIVE, antes)

| Pendência | Situação | Tratamento |
|---|---|---|
| 11 jobs de variantes `FAILED` (SV10, SV3.5 ×2, SVE ×3, SVP ×2, TK-DP-M, XY2, XY3) | Tentativas antigas, todas com 0 linhas; cada Set tem job `COMPLETED` posterior e cobertura total de variantes | Nenhuma ação: histórico terminal, não bloqueia |
| 15 linhas `PENDING` (SV5 12, BASE1 3) | Pertencem a jobs `CANCELLED` (substituídos) | Nenhuma ação: inertes |
| **295 cartas ativas sem nenhuma Card Variant** | 9 Trainer Kits HS/XY (270, sem fonte) + CEL25CC (25, excluída em 2026-10-09) | Migration 2257 |

Sem variante, a carta não entra em Collections (`physical_card.card_variant_id NOT NULL`).

## 2. Fontes e regra

- **Trainer Kits (TK-HS-G, TK-XY-N/SY/W/B/LATIO/LATIA/SU/P):** página pública de expansão da Scrydex, que
  declara a variante de cada carta (`?variant=`). Nos 9 kits: cartas 1–29 `normal`, carta 30 `holofoil`.
  Mapeado para STANDARD/HOLO — o mesmo padrão dos Trainer Kits já catalogados (TK-HS-R, TK-BW-E, TK-SM-L…).
  Correspondência carta a carta e nomes já conferidos na importação das imagens (`2026-10-10-scrydex-card-assets`).
- **CEL25CC:** snapshot Pokémon TCG API `cel25c` (só `holofoil`), casado pela tabela CC001–CC025 da
  importação de imagens da Coleção Clássica. HOLO, sem Edition Context (mesmo padrão da CEL25).
- Todas com `variant_order = 1` e `is_default = false` (o default é o DEFAULT-BACKFILL-01).

## 3. Execução e postcheck (CONFIRMADO EXECUTADO, 2026-10-11)

1. Dry-run estrutural (bloco abortado de propósito): 295 cartas únicas, nenhuma com variante.
2. Migration 2257 (guardas G1 nome/unicidade, G2 sem variante, P1 contagens): **295 variantes**
   (STANDARD 261, HOLO 34); 10 linhas em `catalog_admin_action_log` (`CARD_SET_UPDATED`, `metadata.operation = BOOTSTRAP-03-CLOSEOUT-2257`).
3. Pricing: os produtos JustTCG dessas 10 coleções foram religados pelo resolver de variantes
   (`internal.resolve_pricing_product_card_variant`, regra 3974+3977+3985): **1.129 `UNIQUE` ligados**,
   registrados em `pricing_admin_action_log`.

| Verificação | Resultado |
|---|---|
| `card_variant` | 37.556 → **37.851** |
| Cartas ativas sem variante | 295 → **0** |
| Produtos de preço sem variante | 1.811 (todo o resto; nenhum dos 10 Sets) |

## 4. Achados para as próximas etapas

- **DEFAULT-BACKFILL-01:** 20.240 cartas ativas sem variante `is_default` (todas têm ao menos uma variante agora).
- **Pricing 80:** o total de produtos sem variante subiu para 1.811 (antes 472) porque novos Sets foram
  implantados no Pricing desde a medição anterior: NO_CANDIDATE 1.758, UNIQUE_CONTEXT_ONLY 28, AMBIGUOUS 25.
  Precisa de remedição e classificação antes do gate.
