# ESTRATÉGIA DE LINEAGE — `card_variant` × `catalog_variant_import_row`

**Correções 5 e 6 da `OPERATIONAL-BOUNDARY-CORRECTION-01`.**

---

## A separação que faltava

Duas coisas foram tratadas como uma só até aqui:

| | `card_variant` | `catalog_variant_import_row` |
|---|---|---|
| Natureza | **catálogo vivo** — identidade de 4 componentes | **registro histórico** de uma importação |
| Cardinalidade | 1 Variant | 1..N rows por Variant |
| `2213` a altera? | **sim** | **a decidir — ver abaixo** |
| Precisa de Edition Context? | sim, é a identidade | não, é snapshot |

`B = 365` conta **Variants estruturais**, nunca rows. `STAFF_HOLO` = 40
Variants / 76 rows. Confundir os dois foi a origem de três defeitos
sucessivos neste ciclo.

---

## Correção 5 — o estado híbrido proibido

Alterar `edition_context_profile_id` numa row terminal sem alterar a Variant
produziria:

```
normalized_data.variant_type_id      = <tipo legado contaminado>
normalized_data.edition_context_…    = <profile NOVO>
resulting_variant_id                 → card_variant com identidade ANTIGA
```

Um registro que afirma três coisas incompatíveis: que o acabamento é o tipo
contaminado, que o contexto já foi decomposto, e que produziu uma Variant que
não tem contexto nenhum. **Pior que desatualizado — é contraditório.**

### Regra

> **Row terminal só é alterada se a identidade completa for atualizada de
> forma atômica, na mesma transação da Variant.** Não havendo isso, não se
> altera.

Os três componentes têm de andar juntos:
`variant_type_id` (finish alvo) · `edition_context_profile_id` ·
`resulting_variant_id` (que aponta para a Variant já decomposta).

---

## Correção 6 — o que `2213` faz

### READY_UNCONDITIONED (285) — decisão: **card_variant + lineage, atômico**

`2213` altera `card_variant` **e** reconcilia o lineage das rows que apontam
para essas 285 Variants, na **mesma transação**.

**Por quê, e não "só `card_variant`":** as rows de lineage dessas 285
carregam `normalized_data.variant_type_id` = tipo contaminado. Depois da
decomposição, a Variant tem `variant_type_id` = finish puro +
`edition_context_profile_id`. Se o lineage não acompanhar, toda row que o
referencia passa a descrever uma Variant que não existe mais naquela forma —
e é justamente o estado híbrido que a Correção 5 proíbe, só que criado pela
omissão em vez de pela ação.

| Componente | Fonte |
|---|---|
| `variant_type_id` | finish alvo, o mesmo gravado na Variant |
| `edition_context_profile_id` | o profile resolvido, o mesmo da Variant |
| `resulting_variant_id` | **inalterado** — `card_variant.id` é preservado |

Atomicidade é natural: é um `UPDATE` só, na transação da migração.

**Escopo estrito:** apenas rows com `resulting_variant_id` ∈ (as 285).
Nenhuma outra row terminal é tocada — as ~23.957 restantes ficam como estão.

### READY_PRICING_CONDITIONED (80) — **nenhuma reconciliação**

`STAFF_HOLO` (40) e `SET_LOGO_REVERSE` (40) não entram em `2213`. Por
consequência, **o lineage delas também não é tocado** — nem "adiantando" o
Edition Context, nem gravando `JSON null`. Adiantar o lineage sem a Variant
criaria exatamente o híbrido da Correção 5.

Liberação só em `PRICING-CATALOG-VARIANT-RECONCILIATION-01`.

### HOLD (107 + 379 + 57) — **nenhuma alteração**

Nem Variant, nem lineage, nem chave. Já era a regra; segue.

---

## Tabela de decisão

| Universo | `card_variant` | lineage | quando |
|---|---|---|---|
| READY_UNCONDITIONED (285) | ✅ `2213` | ✅ **atômico com a Variant** | após Gate A + seeds |
| READY_PRICING_CONDITIONED (80) | ❌ | ❌ | após Pricing |
| HOLD (107) | ❌ | ❌ | — |
| EX7–EX10 (379) | ❌ | ❌ | `SET-LOGO-EX-ERA-FINISH-01` |
| `foil`-programa (57) | ❌ | ❌ | B3 |
| Terminal restante (~23.957 rows) | ❌ | ❌ | **nunca** — snapshot histórico |
| CANCELLED (415 rows) | ❌ | ❌ | **nunca** — terminal |

---

## Consequências para `2831` e `2213`

*(Estado em 2026-10-04: a `2831` **v3.0** (`BATCH13-2831-READINESS-CONTRACT-RECONCILIATION-01`, proposta, **não executada**) implementa a reconciliação atômica e as provas L1–L4, além de L8/L9 como pós-condição da simulação. O texto a seguir, que descrevia a v2.0 como "só `card_variant`", fica como registro de origem.)*

`2831` (simulação) **na v2.0** cobria apenas `card_variant`. Com a Correção 6, tanto
a simulação quanto a migração real precisam de **mais duas provas**:

| # | Prova | Onde |
|---|---|---|
| **L1** | toda row com `resulting_variant_id` ∈ (285) tem `normalized_data.variant_type_id` = finish alvo **e** `edition_context_profile_id` = profile da Variant | `2831` · `2213` |
| **L2** | zero híbrido: nenhuma row cujo `edition_context_profile_id` esteja preenchido aponte para Variant com `edition_context_profile_id IS NULL`, e vice-versa | `2831` · `2213` · `2830` L2 |
| **L3** | nenhuma row fora das 285 foi tocada | `2831` · `2213` |
| **L4** | `resulting_variant_id` preservado em 100% — `UPDATE`, nunca `DELETE`+`INSERT` | `2831` v3.0 PASSO 5 · `2213`. *(Correção 2026-10-04: a v2.0 só provava `card_variant.id` não perdido — isso é L8, não L4. A afirmação anterior "já existe em `2831` PASSO 5" era imprecisa.)* |
| **L5** | guard de HOLD: decompor `card_variant_id` da lista congelada (107) aborta com `EDITION_CONTEXT_HOLD_VIOLATION` (ex-K5 da `2830`) | `2213` |
| **L6** | guard PRICING_CONDITIONED: `card_variant_id` ligado a `pricing_source_card_identity` **ou** `pricing_source_variant_mapping` aborta; os dois conceitos checados separadamente (ex-K6) | `2213` |
| **L7** | o guard cobre STAFF_HOLO (40) e SET_LOGO_REVERSE (40) — total 80 (ex-K7) | `2213` |
| **L8** | `card_variant.id` preservado em 285/285 (ex-5.4) | `2213` |
| **L9** | `variant_order` e `is_default` inalterados (ex-5.5) | `2213` |

**Isto é trabalho novo em `2213`, que ainda não foi escrito.** Fica
registrado como requisito, não como algo pronto. L5–L9 vieram da `2830` v7.0
(`BATCH12-2830-SPEC-CORRECTION-01`): eram casos do gate automático que só
passariam por ausência da `2213`. A **exclusão** dos 107 HOLD e dos 80
PRICING_CONDITIONED do plano continua provada no gate atual (`2830` 5.1, 5.3,
5.7).

---

## Nota de implementação — `2831` v3.0 (2026-10-04, `BATCH13-2831-READINESS-CONTRACT-RECONCILIATION-01`)

- **Escopo do lineage:** só `resulting_variant_id` ∈ plano. Rows que apenas
  *casaram* (`matched_variant_id`) com uma Variant do plano **não** são
  reconciliadas — ficam provadamente intactas (L3) e são contadas num aviso.
  Se esse recorte precisar crescer, é decisão de contrato, não de artefato.
- **Destino:** o mesmo da Variant (evidência = row mais antiga). Toda row-alvo
  é resolvida também pelo próprio `raw_data`; divergência aborta
  (`LINEAGE_EVIDENCE_DIVERGENT`).
- **JSON:** padrão da `2219` — `jsonb_set` encadeado só nas duas chaves, UUID
  como string JSON, demais chaves preservadas e provadas (L3 por row).
- **Ordem:** lock `card_variant` → lock lineage → gates → `UPDATE`
  `card_variant` → `UPDATE` lineage. Nenhum guard cruza as tabelas; os guards
  por linha (2214, 2224, game consistency, `uq_card_variant_identity`,
  `uq_cvir_row_identity`) aceitam cada estado intermediário, provado por gates
  de pré-condição (nenhuma Variant do plano e nenhuma row-alvo já tem EC).
  Nenhum trigger é desabilitado.
- **`updated_at`** das rows-alvo muda pelo trigger `set_updated_at` — metadado,
  não conteúdo; L3 por row exclui só essa coluna.

## O que NÃO muda

- `card_variant.id` preservado — toda FK de lineage continua válida por
  consequência.
- `variant_order`, `is_default` — fora do `SET`.
- `raw_data` — imutável, em qualquer row, sempre.
- `validation_status`, `decision_status`, `persistence_status` das rows de
  lineage: **inalterados**. A reconciliação toca `normalized_data` e nada
  mais. Uma row `INSERTED` continua `INSERTED`.
