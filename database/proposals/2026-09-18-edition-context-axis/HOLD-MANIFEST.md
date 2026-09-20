# HOLD MANIFEST — universos que NÃO podem ser tocados

Status: **normativo**. Cada item abaixo é um *guard executável* no `2210` e no
harness `2830`, não um comentário.

## H1 — Legacy HOLD · 107 `card_variant`

| Tipo | Variants | Motivo |
|---|---:|---|
| `SET_LOGO_STANDARDS` (fora EX7–EX16 e fora DP1/SWSH9/SVP) | 15 | sem evidência documental por Set |
| `SET_LOGO_REVERSE` (idem) | 55 | idem |
| `SET_LOGO_COSMOS_HOLO` | 3 | SV10.5B, SV5, SV6 — sem documentação |
| `SET_LOGO_STAFF_HOLO` | 1 | HGSS4 — sem documentação |
| `PROMO_STAMPED` | 33 | contexto genérico, 0 mappings, mandato próprio |
| **Σ** | **107** | |

**Guard obrigatório no `2210`:** a lista de `card_variant_id` é congelada em CTE
e o `UPDATE` recebe `WHERE cv.id NOT IN (SELECT id FROM hold_frozen)`.
O harness prova `0` interseção entre o conjunto atualizado e H1.

## H2 — Staging EX7–EX10 · 379 linhas

`reverse` + `set-logo` em EX7 (95), EX8 (95), EX9 (89), EX10 (100).
Pertencem ao eixo **FINISH**; alvo canônico é de `SET-LOGO-EX-ERA-FINISH-01`.
**Edition Context não as absorve.** Guard: `raw_field='stamp' AND token='SET-LOGO'`
só tem mapping para `external_set_id IN ('dp1','swsh9','svp')` — jamais GLOBAL.

## H3 — Staging `foil`-programa · 57 linhas

`foil ∈ {LEAGUE, PLAYER-REWARD, PROFESSOR-PROGRAM}` (46+2+2) e 7 sem sinal.
Decisão editorial pendente (Blocker B3).

**Guard endurecido na CORRECTION-01:** `raw_field` agora é
`CHECK (raw_field IN ('stamp','subtype'))` — **`foil` está FORA do domínio do
DDL**. Não é possível criar mapping de `foil` nem por engano. O legado que já
carrega esses conceitos recebe Edition Context por **migração via lineage**,
que não passa por esta tabela. Ampliar o domínio exige migration própria.

## H4 — `PROMO_STAMPED` · 33 (⊂ H1)

Mandato próprio. Listado à parte porque bloqueia por razão diferente: não é
falta de evidência de era, é ausência total de mapping e contexto genérico.

## H5 — Pricing orphan

`MASTER_BALL_PATTERN` 209 `pscid` + 1 `psvm` · `POKE_BALL_PATTERN` 256 + 1 ·
`POKEMON_CENTER_EXCLUSIVE` 24 + 3 = **489 `pscid` + 5 `psvm`**
(os dois conceitos nunca somados).
Mandato: `PRICING-CATALOG-VARIANT-RECONCILIATION-01`. Nada corrigido aqui.


## H6 — READY_PRICING_CONDITIONED · 80 `card_variant`

**BLOCKER 5.** As 365 READY são deterministicamente classificadas, mas **não
são todas executáveis hoje**.

| Tipo | Variants | `pscid` | `psvm` |
|---|---:|---:|---:|
| `STAFF_HOLO` | 40 | **17** | **1** |
| `SET_LOGO_REVERSE` (SVP 38 + DP1 2) | 40 | **1** | 0 |
| **Σ condicionado** | **80** | **18** | **1** |

> **Correção de expectativa:** o mandato previa 325 UNCONDITIONED "se não
> existir outro condicionado". **Existe** — `SET_LOGO_REVERSE` tem 1 `pscid`.
> O número real é **285**, não 325.

| Partição | Variants |
|---|---:|
| READY_STRUCTURAL | **365** |
| READY_PRICING_CONDITIONED | **80** |
| **READY_UNCONDITIONED** | **285** |

**Guard executável de STOP** (no `2831` e na futura `2213`):

```sql
IF EXISTS (
    SELECT 1 FROM plan p
      JOIN public.card_variant cv ON cv.id = p.card_variant_id
     WHERE EXISTS (SELECT 1 FROM public.pricing_source_card_identity x
                    WHERE x.card_variant_type_id = cv.variant_type_id)
        OR EXISTS (SELECT 1 FROM public.pricing_source_variant_mapping x
                    WHERE x.variant_type_id = cv.variant_type_id)
) THEN
    RAISE EXCEPTION 'PRICING_CONDITIONED_IN_PLAN: plano contem tipo com dependencia de Pricing. Bloqueado ate PRICING-CATALOG-VARIANT-RECONCILIATION-01 fechar.';
END IF;
```

O guard é **derivado do LIVE**, não de lista estática: se um tipo ganhar
dependência de Pricing depois, ele bloqueia automaticamente.
