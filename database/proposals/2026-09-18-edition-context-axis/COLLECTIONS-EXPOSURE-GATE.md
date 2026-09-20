# Exposição das 365 legacy em Collections — gate

**`EDITION-CONTEXT-AXIS-2213-COLLECTIONS-EXPOSURE-GATE-01`.** Read-only.

## Veredito

### `2213` → **CRITICAL PATH TO COLLECTIONS**

**Quarantine existente: NÃO.** As 365 legacy **podem** adquirir referências de
negócio assim que Collections reabrir. A auditoria anterior media o estado
*hoje*; este mandato pediu o estado *depois*, e a resposta inverte a conclusão
para esse eixo específico.

Permanecem válidos: `2213` × implantação do Edition Context → NOT CRITICAL
PATH · `2213` × novo Write Path → NOT CRITICAL PATH.

---

## 1. Exposição — A a E

| | Pergunta | Resposta | Evidência |
|---|---|---|---|
| **A** | as 365 aparecem como opções? | **SIM** | nenhum read model filtra. `5084` (`collection_master_set_scope_positions`) faz `JOIN public.card_variant_type` e **expõe o nome do tipo contaminado** na saída |
| **B** | alguma pode receber `physical_card`? | **SIM** | `5012` `add_physical_cards` — ver §2 |
| **C** | existe filtro/guard que as exclua? | **NÃO** | busca por `PROMO_STAMPED` · `SET_LOGO` · `legacy` · `quarant` · `READY_STRUCTURAL` em todo `database/schema/50*.sql` + `51*.sql`: **zero ocorrências** |
| **D** | o usuário chega a elas só por `card_variant.id`? | **SIM — e é pior** | `add_physical_cards` aceita o UUID **cru do payload**. Não é preciso passar por listagem nenhuma: basta ter o `id` |
| **E** | decomposta nova coexiste com legacy equivalente antes da `2213`? | **SIM** | ver §3 |

## 2. `add_physical_cards` — o caminho de criação

Guards reais da função (`5012`, linhas 95–128):

1. `p_items` é array JSON
2. array não vazio
3. ≤ 500 itens
4. `inventory` do `auth.uid()` existe

Depois disso:

```sql
INSERT INTO public.physical_card (card_variant_id, language_id, inventory_id)
SELECT (item->>'card_variant_id')::uuid, …
```

**Nenhuma validação sobre `card_variant`.** O único obstáculo é a FK — que
qualquer uma das 365 satisfaz. Não há checagem de tipo, de era, de
`edition_context_profile_id`, de nada.

`collection_master_set_scope` (`5073`) tem trigger de elegibilidade, mas ele
testa só duas coisas: (a) a Collection é `REFERENCE_BASED`/`CARD_SET`;
(b) a `card_variant` pertence ao Card Set referenciado. **Uma legacy do Set
certo passa.**

`set_slot_expected_content` (`5128`) valida propriedade do slot e
obrigatoriedade de `p_card_id` — nada sobre a variante.

## 3. Coexistência semântica (E)

Sob a UNIQUE de 4 componentes de `2209`:

| | `variant_type_id` | `printing_profile_id` | `edition_context_profile_id` |
|---|---|---|---|
| legacy não migrada | `SATANDARD_REWARDS` (contaminado) | NULL | **NULL** |
| decomposta nova | `STANDARD` | NULL | `PROGRAM_PLAYER_REWARDS` |

**Chaves distintas** → a UNIQUE aceita as duas. Duplicata semântica da mesma
carta física, sem violação física. E é exatamente essa nova que a `2213`
projetaria como destino da legacy.

## 4. Colisões futuras — o número não existe

| Pergunta | Resposta |
|---|---|
| quantas das 285 projetam colisão? | **DESCONHECIDO — não mensurável nesta rodada** |
| quantas não colidem? | idem |
| novas variants após UNFREEZE aumentam o número? | **SIM, demonstravelmente** |

Por que desconhecido:

- A cifra de **188** da coluna "Colisão" do `MIGRATION-MAP-365.md` está
  **explicitamente invalidada** pelo próprio cabeçalho da `2831` v2.0
  (defeito **H2**): *"O gate de colisao (PASSO 3) usava o code `'STANDARD'`
  fixo como destino de acabamento — ou seja, NAO testava a colisao real.
  A cifra de '188 colisoes previstas' NAO era produzida por este artefato."*
- A `2831` v2.0 corrigiu o gate, mas ele é **fail-loud binário**
  (`RAISE EXCEPTION` se ≠ 0), não um contador.
- E ela **não pode rodar hoje**: o pré-requisito declarado é *"2203-2211
  aplicados e os traits / profiles / mappings semeados"*. Nada disso está no
  LIVE → `resolve_variant_row_axes` devolve UNRESOLVED e o PASSO 2 aborta.

Por que novas variants aumentam o número — mecanismo exato. O gate do PASSO 3
procura colisão contra `card_variant x` com:

```sql
x.id NOT IN (SELECT card_variant_id FROM plan_ready)
```

Toda variante criada pelo write path v3 após o UNFREEZE é, por construção, um
`x` fora do plano e **já decomposta**. Se um usuário registrar a variante
canônica equivalente a uma legacy, ela ocupa a identidade de 4 componentes que
a `2213` projetaria para aquela legacy → `NEW_IDENTITY_COLLISION` → **a `2213`
inteira aborta** (fail-loud, transação completa).

E se essa legacy já tiver `physical_card` / `collection_allocation` /
`master_set_scope` apontando para ela, a reconciliação posterior precisaria
**fundir dois `card_variant.id` já referenciados** — exatamente o cenário que
este mandato levantou. É um dano que cresce monotonicamente com o tempo de
exposição.

---

## 5. Alternativa ao `2213` — o menor guard

Se a preferência for reabrir Collections antes da `2213`, o guard mínimo é
**uma função + três pontos de chamada**, sem tabela nova e sem coluna nova:

| Onde | O que |
|---|---|
| `internal.is_card_variant_business_eligible(uuid)` | predicado único, `STABLE` |
| `5012` `add_physical_cards` | recusa no `INSERT` |
| `5073` trigger de elegibilidade de `master_set_scope` | **já existe trigger** — é acrescentar uma cláusula |
| `5128` `set_slot_expected_content` | recusa antes de gravar |

**Pré-requisito honesto:** o predicado precisa de uma definição versionada de
"tipo contaminado". Hoje essa lista existe só em prosa no
`MIGRATION-MAP-365.md` (23 tipos nomeados + "21× `STANDARDS_WORLDS_*`" +
"Demais 24 tipos"). Versioná-la é trabalho comparável a fechar a própria
`2213`, que resolve o problema definitivamente em vez de contê-lo.

**Recomendação:** rodar a `2213` na sequência, antes de reabrir Collections.

---

## 6. Sequência mínima corrigida

| # | Ação | Nota |
|---|---|---|
| 1 | `2203`–`2207` — tabelas de Edition Context, vazias | aditivo puro |
| 2 | `2230` → `2231` → `2232` — 115 traits · 144 profiles · 122 mappings | |
| 3 | **FREEZE de importação** + baseline | |
| 4 | `2208` — coluna `edition_context_profile_id` | |
| 5 | `2212` → `2832` → `2833` → `2214` | |
| 6 | `2210` → `2211` | |
| 7 | Consumidores B chamam `2211` | |
| 8 | Deploy da Edge + suíte Deno | |
| 9 | **`2840` (T1)** — probe `apply_migration` × `NULLS NOT DISTINCT` | **NOVO** — precede tudo que dependa da cláusula |
| 10 | `2217` EXPAND → `2218` SWITCH → `2223` CONTRACT | **ver §7 — divergência RESOLVIDA** |
| 11 | `2209` — UNIQUE de 4 componentes | depende do T1 |
| 12 | `2215` → `2216` | |
| 13 | Read models C | |
| 14 | **UNFREEZE** | |
| 15 | **`2831` → `2213`** — decomposição dos 285 | **movido para DENTRO da sequência** |
| → | **Collections liberado** | |

Fora: os 80 de Pricing · as 12 composições de B · `CAMPAIGN_PIKACHU_WORLD_2000`.

## 7. Divergência sobre a ordem `2217` / `2218`

O mandato instrui: *"`2217` DEVE preceder `2218`"*. **Os artefatos provam o
contrário, e de forma mecanizada.**

`2217_redefine_write_card_variant_v3.sql`:

- linha **42–43**: *"POR QUE `DROP FUNCTION` DA DE SEIS É OBRIGATÓRIO —
  `CREATE OR REPLACE` com aridade diferente CRIA UM OVERLOAD"*
- linha **145**: *"Só pode rodar DEPOIS que a Query 2218 (confirm) já chama
  com sete"*
- linha **163**: `RAISE EXCEPTION 'OVERLOAD_DROP_BLOCKED: … Rode a Query 2218 antes.'`

`2218` linha **318** já chama o writer com sete argumentos.

Consequência de inverter: `2217` cria a de 7 args, chega ao `DROP` da de 6,
encontra o confirm ainda chamando com 6 e **aborta a transação inteira** pelo
guard da linha 163. A etapa 10 falharia por desenho.

Por isso a sequência **desta rodada** manteve `2218` → `2217`, e apontou que a
alternativa seria cindir a `2217` em "criar a de 7" e "dropar a de 6" — uma
mudança de artefato, fora do escopo daquele mandato.

> **RESOLVIDO em `WRITER-EXPAND-CONTRACT-CORRECTION-01`.** Foi exatamente a
> cisão sugerida acima. A `2217` virou **EXPAND** (cria a de 7, preserva a de
> 6, sem `DROP` e sem o guard `OVERLOAD_DROP_BLOCKED`); a `2218` permanece
> **SWITCH** sem alteração semântica; o `DROP` migrou para a nova **`2223`
> CONTRACT**. A ordem canônica passa a ser `2217` → `2218` → `2223` — o
> mandato original ("`2217` DEVE preceder `2218`") estava certo; o que faltava
> era tirar o `DROP` de dentro da `2217`. Autoridade: `ROLLOUT-ORDER.md`
> (etapas 9-A/9-B/9-C) e `DAG.md`.

O item T1 da correção **foi aplicado**: `2840` entra como etapa 9, antes de
`2209`.
