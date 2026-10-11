# Pricing 80 — PRICING-CATALOG-VARIANT-RECONCILIATION-01 (2026-10-10)

| Campo | Valor |
|---|---|
| **Status** | **CLOSED para o gate (2026-10-11):** 155.852 de 156.568 produtos ligados (99,5%); fila residual documentada de 716 (não bloqueia, decisão de Fabrício) — ver "Remedição 2026-10-11" no fim |
| **Mandato** | Fabrício, 2026-10-10: vínculo direto com `card_variant`, escopo "todos os desalinhamentos"; plano revisado (vínculo no produto) "Plano aprovado!". 2026-10-11: regras R1/R2/R3 "As três"; fila "documentada, não bloqueia". |
| **Migrations** | `3973` vocabulário · `3974` regra/RPC/trigger · `3975` backfill · `3976` aposentar tipos legados · `3977` regras de fallback · `3985` contexto inerente · `3986` família reverse/holo + impressão única |

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

## Remedição 2026-10-11 e regras `3986`

Depois de BOOTSTRAP-03 e DEFAULT-BACKFILL, o Pricing ganhou Sets novos: 156.566 produtos, **2.342 sem variante**
(NO_CANDIDATE 2.289 · UNIQUE_CONTEXT_ONLY 28 · AMBIGUOUS 25), todos com preço observado.

Regras novas (Fabrício: "As três"); todas só para produto sem qualificador, sem candidata nas regras anteriores,
com exatamente 1 candidata, sem sobrescrever vínculo:

| Regra | O que faz | Produtos |
|---|---|---:|
| R1 | "Reverse Holofoil" aceita a família reverse quando a carta não tem `REVERSE_HOLO` (EX5/EX6 Energy Reverse, SVE Tinsel, BOG Cosmos) | 671 |
| R2 | "Holofoil" aceita também Cracked Ice / Tinsel / Galaxy / Master Ball holo (EX5, SVE, POP8, SV10.5) | 80 |
| R3 | `UNIQUE_SINGLE_PRINTING`: a identidade da fonte tem um único rótulo e a carta uma única variante — liga mesmo com nome de acabamento divergente (SMP 515, ME5.5 194, 2022SWSH 45, RU1, PL2, DP7, Alph Lithograph…) | 875 |

R1/R2 são dado (`pricing_source_printing_finish_fallback`, 33 linhas); R3 é código (`internal.resolve_pricing_product_card_variant`).
Dry-run abortado de propósito antes: mesmos números; 154.226 vínculos existentes reconferidos sem mudança.
Aplicado: **1.626 produtos**, produto ligado a variante de outra carta **0**, log em `pricing_admin_action_log`
(`operation = PRICING-80-REMEASURE-2026-10-11`). Limite conhecido de R3: se a fonte depois acrescentar um segundo
rótulo à mesma identidade, os vínculos já gravados permanecem.

### Fila residual (716 produtos, documentada, não bloqueia o gate)

O preço dessas cartas continua existindo no nível da carta; só não é atribuído a uma variante.

| Grupo | Produtos | Cartas | Natureza / próxima ação |
|---|---:|---:|---|
| A "Normal" em carta que o catálogo só tem HOLO (EX6–EX9, COL1, MEP, BW7, ME2, SV1/SV8, SVP, SWSH8, HGSS2) | 351 | 111 | Fonte lista uma impressão que o catálogo não tem. Revisar se a versão não-holo existe (criar variante) ou se é anúncio sem correspondência |
| F Qualificador sem variante no catálogo (MEP Staff 38, MEP Pokémon Center 16, cosmos holo SVE/SWSHP 50) | 104 | 27 | Lacuna de catálogo: criar as variantes com selo/Cosmos |
| C ME2.5 "Reverse Holofoil" genérico × 2 reverses de padrão | 69 | 62 | Ambíguo de verdade: decidir a que reverse o anúncio genérico corresponde |
| B "Reverse Holofoil" em carta sem nenhuma reverse (DP1, BW1, BW6, HGSS1–3, ME5, POP8) | 64 | 27 | Lacuna de catálogo provável (reverse que falta) |
| G "Holofoil" em carta sem holo (EX7/EX9/EX13, ME1, MEE, POP4, SMP, SV10.5, SVE) | 50 | 16 | Revisão editorial |
| D Ambíguos (BASEP, SVP, SV10.5W) | 40 | 11 | Revisão editorial |
| E Promo com selo, produto sem qualificador (DPP, EX6, EX8, PL3, SWSH4) | 28 | 7 | Revisão editorial (já existia) |
| H GYM2 "1st Edition" sem variante 1ª edição | 10 | 2 | Lacuna de catálogo |

Medição:

```sql
select count(*) from public.pricing_product where card_variant_id is null;  -- 716 em 2026-10-11 (cresce com o sync)
```
