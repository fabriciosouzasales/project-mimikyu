# Cobertura de fonte de variante — classificação dos 169 Card Sets elegíveis

| Campo | Valor |
|--------|-------|
| **Documento** | Evidência congelada de `SOURCE-VARIANT-SCHEMA-COVERAGE-AUDIT-01` |
| **Arquivo** | `database/proposals/2026-09-18-bulk-staging-01/source-variant-coverage-169.md` |
| **Versão** | 1.0 |
| **Status** | CONGELADO — é a origem do manifesto TARGET/DEFERRED de `bulk-staging-runner.js` |
| **Criado em** | 2026-09-18 |
| **Objetivo** | Tornar auditáveis, Set a Set, os 113 TARGET e os 56 DEFERRED da campanha `BULK-STAGING-01`. |

---

## 1. Por que este documento existe

A CANARY LIVE de 2026-09-18 terminou tecnicamente com 3/3 STAGED, mas SM12
produziu **0 rows** com 271 Cards correlacionadas — e o job foi para `STAGED`
com `error_summary` nulo, indistinguível de sucesso. A auditoria que se seguiu
mostrou que o formato `variants` da TCGdex não é único, e que **`SOURCE_READY`
≠ `VARIANT_SOURCE_READY`**.

Este arquivo é a evidência que sustenta a decisão de escopo: **o FULL processa
somente os 113 Sets cuja fonte é ARRAY em 100% das Cards.**

## 2. Método (sem Edge, sem jobs, sem Contents API repetitiva)

O discriminador é **local**, extraído do payload TCGdex já importado em
`catalog_import_row.raw_data`, campo `variants_detailed[].variantId`:

| `variantId` | Significado |
|---|---|
| id opaco real (ex.: `endfynwn4n10gzq`) | a variante veio do **array** do arquivo-fonte |
| `"generated"` | o compilador da TCGdex **derivou** a variante — não havia array |

A autoridade é `server/compiler/utils/cardUtil.ts` do repositório da fonte:
`variantsToVariantsDetailed()` só é chamada quando `card.variants` **não** é
array, e todo item que ela emite carrega `variantId: "generated"`.

A separação de `DERIVED` entre OBJECT e ABSENT veio da API de busca do GitHub,
com aritmética fechada:

```
"variants: {"  repo-wide                                → 311 arquivos
"variants: {" + "from '../Sword & Shield'"              → 239   (SWSH1)
"variants: {" NOT "from '../Sword & Shield'"            →  80   (Champion's Path)
                                                    239 + 80 = 311  ✔
```

E a ausência foi provada por ausência total, não por inferência:
`"from '../Cosmic Eclipse'"` = 276 arquivos; `+ "variants"` = **0**. Idem XY1,
Black & White e Hidden Fates.

### Validação do discriminador contra a CANARY LIVE

| Set | Variantes previstas pelo proxy | `total_rows` real do job |
|---|---:|---:|
| SM12 | 0 | **0** ✔ |
| SV4 | 449 | **449** ✔ |
| SV2 | 483 | **484** (Δ +1) |

Precisão medida: **931/932 = 99,89%**. O Δ+1 de SV2 é drift legítimo do
upstream — a fonte no GitHub ganhou uma variante depois do snapshot do catálogo.
O erro sempre subestima, nunca superestima.

> **Ressalva de método.** A classificação usa o snapshot de `raw_data` (data do
> catalog import), não uma leitura ao vivo do GitHub por Card. É suficiente para
> decidir escopo; a contagem exata por Set vem do próprio job. O guard
> `VARIANT_SOURCE_UNSUPPORTED_FOR_CORRELATED_CARDS` existe justamente para que
> um Set reclassificado pelo upstream falhe em vez de produzir staging parcial.

## 3. Resultado

| Classe | Sets | Cards | Rows previstas | Destino |
|---|---:|---:|---:|---|
| **ARRAY_SUPPORTED** (puro) | **113** | 10.301 | ~18.915 | **TARGET** |
| MIXED (ARRAY + ABSENT) | 8 | 1.182 (54 ARRAY) | 64 | DEFERRED |
| ABSENT | 46 | 4.926 | 0 | DEFERRED |
| OBJECT_BOOLEAN | 2 | 296 | 0 | DEFERRED |
| UNKNOWN | 0 | 0 | — | — |
| **Total** | **169** | **16.705** | | |

`113 + 8 + 46 + 2 = 169` · `10.301 + 1.182 + 4.926 + 296 = 16.705` — fecha exato.

### Distribuição por era

| Era | ARRAY | MIXED | ABSENT | OBJECT | Cards sem fonte |
|---|---:|---:|---:|---:|---:|
| Sun & Moon | 7 | 4 | 12 | 0 | 2.485 |
| XY | 3 | 0 | 24 | 0 | 2.151 |
| Black & White | 4 | 3 | 10 | 0 | 1.417 |
| Sword & Shield | 23 | 0 | 0 | 2 | 296 |
| HeartGold & SoulSilver | 6 | 1 | 0 | 0 | 1 |
| EX · S&V · D&P · E-Card · Platinum · Neo · Gym · POP · BS · LC · CoL | 70 | 0 | 0 | 0 | **0** |

O gap está inteiramente contido em três eras (SM, XY, BW) mais SWSH1/SWSH3.5.

## 4. TARGET — 113 Sets ARRAY_SUPPORTED puros

Ordem alfabética. É esta lista, literal, que está congelada em
`TARGET_SET_CODES` no runner.

```
2011BW, 2012BW, 2014XY, 2015XY, 2016XY, 2017SM, 2018SM, 2019SM, 2021SWSH,
2022SWSH, 2023SV, 2024SV, BASE2, BASE4, BASE5, BOG, CEL25, COL1, DP1, DP2,
DP3, DP4, DP5, DP6, DP7, DPP, ECARD1, ECARD2, ECARD3, EX1, EX10, EX11, EX12,
EX13, EX14, EX15, EX16, EX2, EX3, EX4, EX5, EX5.5, EX6, EX7, EX8, EX9,
FUT2020, GYM1, GYM2, HGSS1, HGSS2, HGSS3, HGSS4, HGSSP, LC, MFB, NEO1, NEO2,
NEO3, NEO4, NP, PL1, PL2, PL3, PL4, POP1, POP2, POP3, POP4, POP5, POP6, POP7,
POP8, POP9, RU1, SI1, SM3, SMP, SV1, SV2, SV3, SV4, SV4.5, SWSH10, SWSH10.5,
SWSH10TG, SWSH11, SWSH11TG, SWSH12, SWSH12.5, SWSH12.5GG, SWSH12TG, SWSH2,
SWSH3, SWSH4, SWSH4.5, SWSH4.5SV, SWSH5, SWSH6, SWSH7, SWSH9, SWSH9TG,
TK-BW-E, TK-BW-Z, TK-DP-L, TK-DP-M, TK-EX-LATIA, TK-EX-LATIO, TK-EX-M,
TK-EX-P, TK-HS-R, TK-SM-L, TK-SM-R
```

## 5. DEFERRED — 56 Sets

### 5.1 MIXED (8) — ARRAY e ABSENT no mesmo Set

Excluídos por decisão de Fabrício em `SOURCE-VARIANT-SAFETY-01`. A parte ARRAY
produziria linhas e o job terminaria `STAGED`: **staging parcial indistinguível
de staging completo**. É exatamente o que o guard por Card impede.

| Set | Cards | ARRAY | ABSENT |
|---|---:|---:|---:|
| SM11 | 258 | 2 | 256 |
| SM10 | 234 | 1 | 233 |
| SM9 | 196 | 1 | 195 |
| SM6 | 146 | 1 | 145 |
| BW5 | 111 | 15 | 96 |
| BW10 | 105 | 3 | 102 |
| BW3 | 102 | 2 | 100 |
| TK-HS-G | 30 | 29 | 1 |

### 5.2 ABSENT (46) — a fonte não declara variante

Nenhum arquivo destes Sets contém a chave `variants`. A API expõe variantes,
mas são o default hardcoded do compilador (`normal: true`), não dado da fonte —
usá-las fabricaria significado editorial.

```
BW1, BW11, BW2, BW4, BW6, BW7, BW8, BW9, BWP, DC1, DET1, DV1, G1, SM1, SM115,
SM12, SM2, SM3.5, SM4, SM5, SM7, SM7.5, SM8, SMA, TK-XY-B, TK-XY-LATIA,
TK-XY-LATIO, TK-XY-N, TK-XY-P, TK-XY-SU, TK-XY-SY, TK-XY-W, XY0, XY1, XY10,
XY11, XY12, XY2, XY3, XY4, XY5, XY6, XY7, XY8, XY9, XYP
```

### 5.3 OBJECT_BOOLEAN (2) — SWSH1 (216 Cards), SWSH3.5 (80 Cards)

Formato legado `variants: { normal, reverse, holo, firstEdition }`. Só os
**dois únicos** Sets do repositório inteiro com esse formato (239 + 80 = 311
arquivos, aritmética fechada em §2).

O que o objeto **não** consegue representar — irrecuperável sem decisão
editorial:

| Dimensão do modelo C2 (ADR-028) | OBJECT |
|---|---|
| `type` | ✅ 3 valores (normal/reverse/holo) |
| **`foil`** | ❌ nunca emitido — o eixo de acabamento não existe |
| **`subtype`** | ❌ nunca emitido |
| `size` | ❌ hardcoded `"standard"` — o guard do incidente JUMBO fica sem sinal |
| `stamp` | ⚠️ só `1st-edition` e `w-Promo` |

`firstEdition` e `wPromo` são **stamps**, não types: multiplicam cada type
presente. Converter entregaria `type` com `foil`/`subtype`/`size` fabricados ou
nulos — a mesma classe de erro já rejeitada em `EXTERNAL-REF-RECOVERY-01`.

## 6. Interseção com os jobs de Variant Import existentes

| Set | Job | Rows | Classe | Tratamento no FULL |
|---|---|---:|---|---|
| **EX5.5** | STAGED | 5 | TARGET | `ALREADY_STAGED` — nunca reinvocado, confirmado ou excluído |
| **SV2** | STAGED | 484 | TARGET | `ALREADY_STAGED` — nunca recriado |
| **SV4** | STAGED | 449 | TARGET | `ALREADY_STAGED` — nunca recriado |
| **SM12** | STAGED | **0** | **DEFERRED (ABSENT)** | Removido da fila pelo filtro de cobertura; **não alterado, não cancelado, não excluído** |

O job STAGED/0 de SM12 permanece intocado. Seu tratamento futuro é decisão
editorial separada, fora desta campanha.

## 7. Denominador da campanha

- **Processáveis hoje:** 113 Sets / 10.301 Cards / ~18.915 rows.
- **Fora do FULL:** 56 Sets / 6.404 Cards.
- Cobertura efetiva sobre o universo elegível: **10.301 / 16.705 = 61,7% das Cards**,
  **113 / 169 = 66,9% dos Sets**.

Os 56 DEFERRED **não** são pendência da campanha — são escopo excluído por
decisão. O completion gate do runner usa 113 como denominador; contar os 169
faria o FULL parecer eternamente incompleto.

---

## Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | **Congelamento da classificação dos 169 Sets, 2026-09-18.** Criado em `SOURCE-VARIANT-SAFETY-01 / IMPLEMENTATION-01` para tornar auditável o manifesto TARGET/DEFERRED do runner. Origem: `SOURCE-VARIANT-SCHEMA-COVERAGE-AUDIT-01`, com o discriminador `variantId="generated"` validado contra a CANARY LIVE (931/932). |
