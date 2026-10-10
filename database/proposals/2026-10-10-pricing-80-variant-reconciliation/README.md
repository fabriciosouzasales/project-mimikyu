# Pricing 80 — PRICING-CATALOG-VARIANT-RECONCILIATION-01 (2026-10-10)

| Campo | Valor |
|---|---|
| **Status** | Contrato implantado; 49.899 de 50.470 produtos ligados (98,9%); fila residual de 571 para revisão editorial / lacuna de catálogo |
| **Mandato** | Fabrício, 2026-10-10: vínculo direto com `card_variant`, escopo "todos os desalinhamentos"; plano revisado (vínculo no produto) "Plano aprovado!" |
| **Migrations** | `3973` vocabulário · `3974` regra/RPC/trigger · `3975` backfill · `3976` aposentar tipos legados · `3977` regras de fallback |

## Diagnóstico (LIVE)

- As 80 variantes `STAFF_HOLO`/`SET_LOGO_REVERSE` do mandato original já tinham sido decompostas pela D2.
  Sobravam 18 identidades de preço (17 Staff + 1 Set Logo) e a chave de vocabulário `staff`.
- O problema real era maior: a identidade de preço só guardava `card_variant_type_id`, um eixo; o catálogo
  identifica variante por três (Finish + Printing + Edition Context). 626 identidades tipadas não achavam
  variante (465 eram nomes duplicados `*_BALL_PATTERN` × `*_BALL_REVERSE`).
- Uma identidade (anúncio da JustTCG) tem vários produtos, um por impressão ("Normal", "Holofoil",
  "Reverse Holofoil", "1st Edition"…). Por isso o vínculo correto é **por produto**:
  `pricing_product.card_variant_id`, que já existia e estava vazio em 50.470 produtos.

## Contrato

**Regra única** (`internal.resolve_pricing_product_card_variant`, 3974):

- Finish = Finish imposto pelo qualificador da identidade (`pricing_source_variant_mapping.catalog_finish_type_id`),
  senão o do rótulo de impressão (`pricing_source_printing_mapping`).
- Printing = perfil do rótulo, igualdade exata (`1st Edition` → `FIRST_EDITION`; demais → base).
- Edition Context: a variante precisa conter o traço exigido pelo qualificador (`staff` → `ROLE_STAFF`,
  `pokemon center*` → `CHANNEL_POKEMON_CENTER`); entre as candidatas vence a de menos traços.
- Só grava quando há **uma** candidata e, se o produto não tem qualificador, a variante não tem Edition
  Context (`UNIQUE`). Nunca sobrescreve vínculo existente.

Pontos de uso: `admin_reconcile_pricing_product_variants(p_apply)` (admin, dry-run por padrão, log em
`pricing_admin_action_log` como `PRICING_PRODUCT_VARIANT_RECONCILED`) e o trigger
`trg_pricing_product_link_card_variant` (produtos novos do sync já nascem ligados).

A identidade de preço mantém `card_variant_type_id` só como classificação da fonte. Os tipos `STAFF_HOLO`,
`SET_LOGO_REVERSE`, `POKE_BALL_PATTERN` e `MASTER_BALL_PATTERN` foram repontados (HOLO, STANDARD,
POKE_BALL_REVERSE, MASTER_BALL_REVERSE) e desativados (3976).

## Resultado (LIVE, 2026-10-10)

| Resolução | Produtos | Cartas |
|---|---:|---:|
| `UNIQUE` → ligado | 48.316 | — |
| `NO_CANDIDATE` | 1.939 | ~480 |
| `UNIQUE_CONTEXT_ONLY` | 190 | 43 |
| `AMBIGUOUS` | 25 | 5 |

Produto ligado a variante de outra carta: 0. Reexecução: 0 novos (idempotente). Execução completa: ~4,5 s.

Testes (transação desfeita): não-admin recebe `FORBIDDEN`; dry-run não grava; produto novo inserido é ligado
pelo trigger.

## Regras de fallback (3977, Fabrício: "Aplique as duas regras do grupo 1 e 2")

Só para produto sem qualificador, só quando a regra principal deu `NO_CANDIDATE`, só variante sem
Edition Context e só com exatamente uma candidata (`UNIQUE_FALLBACK`):

1. **Família holo:** "Holofoil"/"Unlimited Holofoil" também aceitam `RAINBOW_HOLO`, `GOLD_HOLO`, `COSMOS_HOLO`
   (tabela `pricing_source_printing_finish_fallback`).
2. **Impressão base:** rótulos sem Printing aceitam `UNLIMITED` quando não há variante base
   (`pricing_source_printing_mapping.fallback_printing_profile_id`).

Resultado: +1.583 produtos (1.153 "Holofoil" + 430 "Normal"); total 49.899/50.470; carta errada 0.

## Fila residual (571 produtos, revisão editorial ou lacuna de catálogo)

| Grupo | Produtos | Cartas | Natureza |
|---|---:|---:|---|
| Base sem candidata (ME2.5 reverse sem padrão, "Normal" em carta só HOLO etc.) | 252 | 120 | Revisão editorial |
| Promos com carimbo e produto sem qualificador (`UNIQUE_CONTEXT_ONLY`) | 190 | 43 | Revisão editorial |
| `cosmos holo`/`cosmo holo` sem variante Cosmos | 50 | 10 | Lacuna de catálogo |
| MEP Staff | 38 | 12 | Lacuna de catálogo |
| `AMBIGUOUS` (BASEP/SVP) | 25 | 5 | Revisão editorial |
| MEP Pokémon Center | 16 | 5 | Lacuna de catálogo |

## Fila residual original (antes da 3977, histórico)

| Grupo | Cartas | Proposta |
|---|---:|---|
| "Holofoil" em carta cujo único holo é `RAINBOW_HOLO` (89), `GOLD_HOLO` (86), `COSMOS_HOLO` (49) | 224 | Fallback de família holo: ligar quando houver exatamente uma variante holo-especial |
| Base Set "Normal"/"Holofoil" com catálogo em `UNLIMITED` explícito (por causa de Shadowless) | ~100 | Fallback de impressão: rótulo base → `UNLIMITED` quando não houver variante base |
| Promos SVP/BASEP com carimbo (`ARTWORK_SET_LOGO`, Prerelease etc.) e produto sem qualificador | 43 | Revisão editorial: decidir se o produto "puro" corresponde à variante carimbada |
| ME2.5 "Reverse Holofoil" sem qualificador, catálogo só com reverses de padrão | ~75 | Revisão: provavelmente produto inexistente na prática |
| "Normal" em carta só `HOLO` (promos) | ~20 | Revisão editorial |
| MEP Staff (12) e Pokémon Center (5) | 17 | Lacuna de catálogo: variantes Staff/PC não existem para MEP |
| `AMBIGUOUS` (BASEP/SVP) | 5 | Revisão editorial |
