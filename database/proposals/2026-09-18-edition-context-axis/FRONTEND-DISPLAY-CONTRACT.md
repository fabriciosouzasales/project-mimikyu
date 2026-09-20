# Contrato de exibição de Card Variant no frontend

**`CARD-VARIANTS-FRONTEND-DISPLAY-AUDIT-01`.** Auditoria read-only. Nada
implementado, nenhum SQL alterado, nenhuma execução LIVE.

## Diagnóstico do bug

`/catalogo/cartas` mostra `Holográfica ×4` porque o eixo exibido é **um só**:

```
queries.ts:2027   card_variant(card_variant_type(name, display_order))
queries.ts:2047   .map((variant) => variant.card_variant_type.name)
queries.ts:1934   variantNames: string[]
```

Quatro `card_variant` distintas achatam para quatro cópias da mesma string.
A identidade da linha (`card_variant.id`) **é descartada no mapper** — e com
ela some qualquer possibilidade de distinguir as quatro. O defeito de key
React (`cartas-gallery.tsx:1224`, `key={variantName}`) é consequência, não
causa: sem `id`, não há key estável a usar.

Dois eixos nunca chegaram ao frontend: **Printing** (`card_printing_profile`,
LIVE desde 2026-09-12 — **zero** ocorrências em `web/`) e **Edition Context**
(`card_edition_context_profile`, ainda proposta).

---

## 1. Inventário de superfícies

### 1.1 Consomem `card_variant` como identidade — PRECISAM MUDAR

| # | Arquivo | Função/componente | Dado atual | Risco semântico | Muda? |
|---|---|---|---|---|---|
| 1 | `lib/catalogo/queries.ts` | `CartaCompletaRow` (1934) · `CartaCompletaVariantRawRow` (1944-1946) · `.select()` (2027) · mapper (2047-2050) | `variantNames: string[]` derivado só de `card_variant_type.name` | **Raiz do bug.** Achata N linhas distintas em N strings possivelmente iguais; descarta `card_variant.id`; ignora Printing e Edition Context | **SIM** |
| 2 | `components/catalogo/cartas-gallery.tsx` | tag `Layers` (1209-1215) · tooltip (1220-1227) · `hasAnyVariants` (405) · filtro (412-413) | `variantNames.length` / `variantNames[]` | Tooltip repetido; `key={variantName}` duplicada (1224); contagem correta por acidente (length de array não-deduplicado) | **SIM** |
| 3 | `app/catalogo/relatorios/variantes-por-carta/page.tsx` | coluna "Variantes cadastradas" (236-250) · totais (145-149) | `variantNames.join(", ")` | Relatório imprime `Holográfica, Holográfica, Holográfica, Holográfica` | **SIM** |
| 4 | `lib/pricing/queries.ts` | `PricingMappingDetail.localVariants` (249) · raw (294) · map (348-354) | `{id, variantTypeId, code, name, isDefault}` | **Único lugar que já carrega `card_variant.id`.** Mas rotula a variante só pelo Variant Type → duas variantes da mesma Card aparecem idênticas no select | **SIM** |
| 5 | `components/pricing/resolucao-mapeamento-detail.tsx` | bloco "Variantes locais" (252-263) · `<select>` "Variante local" (396-412) | `localVariants` | `key={v.variantTypeId}` (410) duplica `<option>` quando a Card tem 2 variantes do mesmo tipo — **o usuário não consegue escolher a segunda** | **SIM** |

### 1.2 Exibem variante mas em outro eixo — rodada separada

| # | Arquivo | Componente | Dado | Por que não agora | Muda? |
|---|---|---|---|---|---|
| 6 | `components/catalogo/revisao-importacao-variantes-table.tsx` | coluna "Variante Proposta" (546-555) | `row.variantTypeName ?? "—"` | É **staging**, não `card_variant`. Pós-EC a linha resolve 3 eixos e esta coluna fica incompleta — mas o consertos pertence ao ciclo do pipeline de importação, não ao do catálogo | **SIM — rodada própria** |
| 7 | `components/catalogo/revisao-importacao-variantes-table.tsx` | `VariantRawChips` (154-165) | `rawType/rawFoil/rawSubtype/rawStamp` | Chips da assinatura bruta. Corretos como estão — são a evidência de origem, não o resultado | NÃO |

### 1.3 Não representam Card Variant — NÃO MUDAM

| Superfície | Arquivo | O que é de fato |
|---|---|---|
| CRUD de Tipos de Variação | `app/catalogo/tipos-variacao/*` · `components/catalogo/tipos-variacao-table.tsx` | Cadastro de `card_variant_type` — o **eixo Finish**. Correto e completo |
| "Variante" no Pricing | `preco-por-carta-report.tsx` · `price-history-chart.tsx` · `card-price-summary.tsx` · `valor-por-set-*.tsx` · `app/api/cards/**/pricing/*` | `pricing_product.source_printing_label` — **rótulo textual da fonte externa de preço**. Homônimo, não é `card_variant` nem `card_printing_profile`. Não tocar semanticamente |
| Relatório Checklist | `app/catalogo/relatorios/checklist/page.tsx` | Zero ocorrências de variante |
| Hub do Card Set | `app/catalogo/card-sets/[code]/page.tsx` | As 4 ocorrências de `variant` são `<Button variant="outline">` |
| Busca / Pesquisa | `app/api/cards/search/route.ts` · `components/pesquisa/*` · `global-search.tsx` | `search_cards` não retorna nem filtra variante |
| Cobertura de Variantes | `app/catalogo/relatorios/cobertura-variantes/page.tsx` | Conta Cards com/sem variante — cardinalidade, não identidade |
| Stats do Catálogo | `lib/catalogo/queries.ts:1670` | `COUNT(*)` de `card_variant`. O card "VARIAÇÕES" já foi removido da UI |

### 1.4 Collections — nada real existe ainda

Busca por `physical_card`, `inventory_item`, `.from("collection"\|"binder"\|"slot")`
em `app/`, `components/`, `lib/`, `hooks/`: **0 resultados**. Não há read
model, selector nem hook de Collections no frontend.

O que existe são **mocks de spike**, todos com `variantLabel?: string`
declaradamente fictício:

| Arquivo | Campo | Nota no próprio código |
|---|---|---|
| `app/experimental/binder-nav-01/card-picker-mock.ts:50` | `variantLabel?` | *"não há Card Variant de verdade por trás de `variantLabel`"* |
| `app/experimental/binder-nav-01/card-detail-mock.ts:57` | `variantLabel?` | *"sem leitura de Card Variant reais"* |
| `components/experimental/binder-nav-01/card-picker-modal.tsx:320` | render ` · ${variantLabel}` | já usa o separador ` · ` |
| `components/experimental/binder-nav-01/card-detail-modal.tsx:300` | `setInfo.variantLabel` | — |

**Consequência para Collections:** quando o Binder/Card Picker deixar de ser
mock, `variantLabel?: string` tem de nascer já como `CardVariantDisplay` —
senão o mesmo bug reaparece num contexto pior (o usuário escolhendo **qual
cópia física** possui). O Card Picker é exatamente a tela em que duas
"Holográfica" indistinguíveis tornam a escolha impossível.

### 1.5 Keys de React em risco

| Arquivo | Linha | Key atual | Diagnóstico |
|---|---|---|---|
| `components/catalogo/cartas-gallery.tsx` | 1224 | `key={variantName}` | **Duplicada hoje**, no caso do bug relatado |
| `components/pricing/resolucao-mapeamento-detail.tsx` | 410 | `key={v.variantTypeId}` | **Duplicável** quando 2 variantes compartilham Variant Type — e duplica um `<option>` selecionável |
| `components/catalogo/revisao-importacao-variantes-table.tsx` | 163 | `` `${chip}-${index}` `` | Aceitável — lista imutável por render, e são chips de assinatura bruta |

---

## 2. Contrato visual canônico

Arquivo novo proposto: **`web/lib/catalogo/card-variant-display.ts`**.

```ts
/** Um eixo resolvido de uma Card Variant. */
export type CardVariantAxis = {
  /** id da entidade canônica do eixo (variant_type / printing_profile / edition_context_profile) */
  id: string;
  /** label editorial pt-BR vindo da entidade canônica. NUNCA derivado de code. */
  label: string;
  /** display_order da entidade canônica, para ordenação determinística */
  displayOrder: number;
};

/** Uma linha de card_variant, com os três eixos. Substitui `string[]`. */
export type CardVariantDisplay = {
  /** card_variant.id — KEY ESTÁVEL. Nunca usar label, nome ou índice. */
  id: string;
  /** card_variant.variant_type_id é NOT NULL (160_create_card_variant_table.sql:61) → nunca nulo */
  finish: CardVariantAxis;
  /** card_variant.printing_profile_id é NULL-able (2176) */
  printing: CardVariantAxis | null;
  /** card_variant.edition_context_profile_id é NULL-able (2208) */
  editionContext: CardVariantAxis | null;
  /** derivado — ver §3 */
  displayLabel: string;
  /** derivado — ver §4 */
  sortKey: string;
};
```

`CartaCompletaRow.variantNames: string[]` é **removido** e substituído por
`variants: CardVariantDisplay[]`.

### Invariantes

| # | Invariante | Garantia |
|---|---|---|
| I1 | `id` é único dentro de uma Card | PK de `card_variant` |
| I2 | `finish` nunca é `null` | `variant_type_id UUID NOT NULL` |
| I3 | Duas `CardVariantDisplay` da mesma Card nunca têm os 3 eixos iguais | `uq_card_variant_identity` de 4 componentes, `NULLS NOT DISTINCT` (Query 2209) |
| I4 | Nenhum consumidor deduplica por `displayLabel` | I3 garante que labels iguais ⇒ eixos iguais ⇒ impossível; se aparecerem, é **bug de dado**, não de UI, e deve permanecer visível |
| I5 | Nenhum consumidor faz parse de `code` | `2166:40-42` — *"NEM code NEM name representam a identidade matemática do conjunto"* |

---

## 3. Regra de label

```
Finish
Finish <SEP> Printing
Finish <SEP> Edition Context
Finish <SEP> Printing <SEP> Edition Context
```

Implementação: filtrar os eixos nulos e juntar. Nunca há separador solto,
nunca aparece `null`, nunca há fallback inventado.

```ts
export function formatCardVariantLabel(v: {
  finish: CardVariantAxis;
  printing: CardVariantAxis | null;
  editionContext: CardVariantAxis | null;
}): string {
  return [v.finish, v.printing, v.editionContext]
    .filter((axis): axis is CardVariantAxis => axis !== null)
    .map((axis) => axis.label)
    .join(SEP);
}
```

### Fonte de cada label

| Eixo | Fonte canônica | Idioma no LIVE | Evidência |
|---|---|---|---|
| Finish | `card_variant_type.name` | pt-BR | "Holográfica", "Holográfica Reversa" |
| Printing | `card_printing_profile.name` | pt-BR | `2169:97-103` — `'Tiragem Ilimitada'`, `'Sem Sombra'`, `'Sem Sombra · 1ª Edição'` |
| Edition Context | `card_edition_context_profile.name` | **INGLÊS** — ver **B1** | `2231:51` — `name` = `'My First Battle — Blue Border · …'`, pt-BR está em `description` |

`profile.name` **pode** ser usado como label agregado: o veto de `2166:40-42`
é sobre derivar **composição** a partir de `name`/`code` (filtro por trait é
sempre JOIN), não sobre exibir o nome. Mas ver **B1** e **B2** — há duas
divergências reais que precisam de decisão antes de fixar `SEP`.

---

## 4. Regra de ordenação

Prioridade, com prova de suporte no schema:

| # | Chave | Campo | Suporta? | Prova |
|---|---|---|---|---|
| 1 | Finish | `card_variant_type.display_order` | **SIM** | `NOT NULL` + `UNIQUE (game_id, display_order)` (`150_create_card_variant_type_table.sql`) → ordem total dentro do Game |
| 2 | Printing | `card_printing_profile.display_order` | **SIM** | `NOT NULL` + `UNIQUE (game_id, display_order)` + `CHECK (display_order > 0)` (`2166:107,126-127,142-143`) |
| 2b | Ausência de Printing | sentinela `0` | **SIM** | `CHECK (display_order > 0)` garante que nenhum profile real vale 0 → "sem tiragem" ordena **antes** de qualquer tiragem, sem colisão possível |
| 3 | Edition Context | `card_edition_context_profile.display_order` | **SIM** | `NOT NULL` + `UNIQUE (game_id, display_order)` + `CHECK (display_order > 0)` (`2204:33,45,55`). Esparso de 10 em 10, por desenho (`2204:20-21`) |
| 3b | Ausência de EC | sentinela `0` | **SIM** | mesmo argumento do CHECK |
| 4 | Desempate | `card_variant.id` | **SIM — e provadamente inalcançável** | Chegar aqui exige duas linhas da mesma Card com os 3 eixos idênticos, o que `uq_card_variant_identity` (2209) proíbe. É desempate **defensivo**: mantém a ordenação total mesmo se a UNIQUE ainda não estiver aplicada (hoje é o caso) |

```ts
const PAD = 10; // cobre INT4 máximo (2147483647)
const pad = (n: number) => String(n).padStart(PAD, "0");

export function buildSortKey(v: {
  id: string;
  finish: CardVariantAxis;
  printing: CardVariantAxis | null;
  editionContext: CardVariantAxis | null;
}): string {
  return [
    pad(v.finish.displayOrder),
    pad(v.printing?.displayOrder ?? 0),
    pad(v.editionContext?.displayOrder ?? 0),
    v.id,
  ].join("|");
}
```

Ordenar é então `[...variants].sort((a, b) => a.sortKey.localeCompare(b.sortKey))`
— ou, melhor, `compareCardVariantDisplay()` comparando os campos numéricos
diretamente e caindo em `id` só no fim. `sortKey` existe como campo do
contrato para que qualquer consumidor (tabela, relatório, `<select>`) ordene
igual sem reimplementar a regra.

> **Nota sobre `variant_order`:** continua fora. É ordem técnica de
> persistência (a ordem em que o pipeline confirmou cada linha), não
> semântica visual — decisão de Fabrício já registrada em `queries.ts:1926-1927`.
> O frontend nunca o leu e não deve passar a ler.

---

## 5. UX

Preservado integralmente: a tag monocromática com ícone `Layers` + contagem,
o tooltip compacto, o agrupamento `gap-0.5` com a raridade, o
`use-infinite-reveal` da galeria, o pill de preço. **Nenhuma mudança visual
fora do conteúdo do tooltip.**

A contagem passa a ser `variants.length` — mesmo número de hoje, agora com
significado garantido (linhas distintas, não strings).

Tooltip:

```
Variações cadastradas
• Holográfica
• Holográfica · 1ª Edição
• Holográfica · Pré-lançamento
• Holográfica · Staff · Campeonato Mundial 2010
```

Cada `<li key={variant.id}>`. Uma linha por `card_variant`, sempre — nunca
deduplicar, nunca agrupar. O tooltip continua sendo texto simples: sem
ícones por eixo, sem cores, sem grid, sem sub-blocos. Se um label ficar longo
demais para o tooltip, a resposta é **truncar o tooltip**, nunca encurtar o
label omitindo um eixo.

Relatório `variantes-por-carta`: a célula passa de `join(", ")` para uma `<ul>`
com uma linha por variante — `", "` entre labels que já contêm ` · ` é
ilegível.

---

## 6. Performance

### Consulta atual

```
card(… , card_variant(card_variant_type(name, display_order)))
```

Um único `.select()` do PostgREST → **uma requisição**, um plano. `card_asset`
já usa a mesma técnica.

### Consulta futura

```
card_variant(
  id,
  card_variant_type(id, name, display_order),
  card_printing_profile(id, name, display_order),
  card_edition_context_profile(id, name, display_order)
)
```

| Métrica | Impacto |
|---|---|
| Round-trips HTTP | **inalterado — 1** |
| Consultas por `card_variant` | **zero.** Os dois embeds novos são FK escalares resolvidas no mesmo plano — não é N+1 por construção |
| Linhas retornadas | **inalterado.** Os embeds são `many-to-one`: não multiplicam linhas, só alargam cada uma |
| Bytes por variante | ~3× no bloco de variante (3 objetos de 3 campos em vez de 1 de 2). O bloco de variante é uma fração pequena do payload por Card — o peso está em `card_asset` e nas URLs públicas |
| Volume típico | Um Card Set (≤ ~250 Cards) × variantes por Card. Sem paginação nova |

**Nenhuma consulta nova, nenhum `useEffect` de fetch, nenhum hook novo.**

Alternativa avaliada e **não recomendada agora**: uma view
`card_variant_display` que materialize `display_label`/`sort_key` em SQL.
Vantagem real (label único para todos os consumidores, inclusive Collections);
custo: é trabalho de SQL, que este mandato excluiu, e cristaliza `SEP` no banco
antes de **B2** estar decidido. Fica registrada como opção para a rodada de
implementação — se adotada, o contrato TypeScript acima permanece idêntico,
só muda de onde `displayLabel`/`sortKey` vêm.

---

## 7. Sequência de rollout

### BEFORE — hoje

O frontend atual lê **apenas** `card_variant_type`, que está LIVE. Continua
operacional e correto-no-que-mostra (mostra o eixo Finish, e só). **Nenhuma
query produtiva é alterada nesta rodada** — os objetos de Edition Context não
existem no LIVE (confirmado em `2213-CRITICAL-PATH-DECISION.md` §5: a coluna
`edition_context_profile_id` está ausente, as 4 tabelas `card_edition_context_*`
não existem).

Referenciar qualquer um deles agora produziria erro de embed do PostgREST em
produção.

### AFTER DB DEPLOY

Pré-condições, todas da sequência já versionada em `ROLLOUT-ORDER.md`:

| Etapa | O que libera |
|---|---|
| 1 · `2203`–`2207` | tabelas de Edition Context existem |
| 2 · `2230`→`2231`→`2232` | traits, profiles e mappings semeados — labels existem |
| 4 · `2208` | coluna `edition_context_profile_id` em `card_variant` |
| **+** | **RLS nas 4 tabelas de EC — ver B3. Bloqueia o embed** |
| 15 · `2213` | 365 legacy decompostas — ver B4 |

### A troca pode ser um único deploy de frontend? **SIM.**

Três razões, todas verificáveis:

1. `getCartasCompletas` roda **server-side** (RSC). Não existe cache de
   cliente com o shape antigo de `CartaCompletaRow`.
2. `CartaCompletaRow.variantNames` tem exatamente **3 consumidores**
   (`cartas-gallery.tsx`, `variantes-por-carta/page.tsx`, e o próprio
   `queries.ts`). Todos mudam no mesmo commit; `tsc --noEmit` prova que não
   sobrou nenhum — o campo some do tipo, qualquer leitor esquecido vira erro
   de compilação. **Sem campo de compatibilidade**, mesma disciplina do writer.
3. Nenhum estado persistido (URL, `localStorage`, cookie) é chaveado por
   nome de variante. O filtro `?variantes=` do relatório usa
   `"todas"|"com"|"sem"` — independente do shape.

Ordem obrigatória: **schema e seeds primeiro, frontend depois.** O inverso
quebra `/catalogo/cartas` em produção. O PR de frontend não pode ser mergeado
antes da etapa 4 do rollout.

Durante o FREEZE de importação (etapas 3→14) nenhuma `card_variant` nova
nasce, então não há deriva entre o deploy de schema e o de frontend.

### Antes ou depois da `2213`?

Ambos funcionam. A diferença é o que o usuário vê para as 365 legacy:

- **Depois da `2213`** (recomendado): as 365 aparecem decompostas e corretas.
- **Entre `2208` e `2213`**: as 365 mostram `Finish` contaminado sozinho
  (ex.: o Variant Type `STANDARD_PIKACHU_WORLD_2000` em vez de
  `Padrão · Campanha Pikachu World 2000`). **Não é regressão** — é exatamente
  o que a tela já mostra hoje. Mas a UI nova torna a dívida mais visível, ao
  lado de variantes vizinhas já decompostas.

---

## 8. Arquivos a alterar

| Arquivo | Natureza |
|---|---|
| **`web/lib/catalogo/card-variant-display.ts`** | **NOVO** — tipos, `formatCardVariantLabel()`, `buildSortKey()`, `compareCardVariantDisplay()` |
| **`web/lib/catalogo/card-variant-display.test.ts`** | **NOVO** — 1/2/3 eixos, ausência de cada eixo, ordenação, key estável, ausência de dedup |
| `web/lib/catalogo/queries.ts` | `CartaCompletaVariantRawRow`, `CartaCompletaRawRow`, `CartaCompletaRow`, `.select()`, mapper |
| `web/components/catalogo/cartas-gallery.tsx` | tooltip (`key={v.id}`, `displayLabel`), tag, `hasAnyVariants`, filtro |
| `web/app/catalogo/relatorios/variantes-por-carta/page.tsx` | célula `<ul>`, contagens, filtro |
| `web/lib/pricing/queries.ts` | `PricingMappingDetail.localVariants` passa a carregar os 3 eixos |
| `web/components/pricing/resolucao-mapeamento-detail.tsx` | `key={v.id}` (410), label do bloco e do `<select>` |

Rodada separada: `web/components/catalogo/revisao-importacao-variantes-table.tsx`
(coluna "Variante Proposta" do staging).

Quando Collections sair do mock: `card-picker-mock.ts`, `card-detail-mock.ts`
e os componentes que consomem `variantLabel?: string` adotam
`CardVariantDisplay`.

---

## 9. Blockers

> **B1 e B3 → RESOLVIDOS** em `EDITION-CONTEXT-AXIS-SECURITY-SEED-HARDENING-01`.
> **B1**: `2230` v2.1 e `2231` v3.1 — `name` passou a ser o label canônico
> PT-BR nas duas entidades (opção **(a)**, a recomendada abaixo), com o rótulo
> inglês preservado em `description`. Gates T4/P5/P6/P7 tornam a regra
> executável. Maior `profile.name`: **100 chars** / `VARCHAR(200)`.
> **B3**: `2203`–`2207` — RLS + `catalog_admin_select` + `REVOKE ALL` +
> `GRANT SELECT` nas 5 tabelas; escrita direta de `service_role` eliminada.
> **B2** segue aberto: `DEFERRED_TO_FRONTEND_AFTER_2213`.
> **B4** segue como dívida: `RESOLVED_BY_2213`.
> As seções abaixo ficam como o registro do diagnóstico original.

### B1 — STOP · `card_edition_context_profile.name` está em INGLÊS

`2204:31` define **uma** coluna `name`. O seed `2231` preenche:

| coluna | conteúdo real (linha 51) |
|---|---|
| `name` | `'My First Battle — Blue Border · My First Battle — Poké Ball Mark · …'` |
| `description` | `'My First Battle — Borda Azul · My First Battle — Marca Poké Ball · …'` |

Ou seja: o **pt-BR está em `description`**, e `name` é inglês. Isso contradiz
os outros dois eixos, ambos pt-BR no LIVE (`card_variant_type.name` =
"Holográfica"; `card_printing_profile.name` = "Sem Sombra · 1ª Edição",
`2169:97-103`), e contradiz o requisito deste mandato de usar labels
editoriais pt-BR das entidades canônicas.

Três saídas, todas com custo:

| Opção | O que muda | Custo |
|---|---|---|
| (a) trocar `name` ↔ `description` no `2231` | seed, antes de aplicar | baixo — o seed é PROPOSTA, nada executado. Mas `description` fica sem descrição de verdade |
| (b) acrescentar `name_pt` em `2204` | schema + seed | médio — assimetria com Printing/Finish, que têm uma coluna só |
| (c) frontend lê `description` para EC | só frontend | **rejeitado** — inventa contrato: `description` é descrição, e `card_printing_profile.description` é prosa ("Perfil de impressão da tiragem aberta."), não label |

**Decisão de Fabrício necessária.** Sem ela, o label de Edition Context não
tem fonte definida e o contrato não fecha. Recomendação: **(a)** — é o seed
que está fora do padrão, não o schema.

### B2 — STOP · colisão do separador ` · `

O separador da regra de display é ` · `. Mas `profile.name` de aridade ≥ 2
**já usa ` · ` internamente**, por regra de nomenclatura versionada:

> `2231:39` — *"name = names dos traits na MESMA ordem, unidos por ' · '"*
> `2169:101` — `'SHADOWLESS_FIRST_EDITION', 'Sem Sombra · 1ª Edição'`

Compondo os eixos com o mesmo separador, uma variante de aridade 3 no eixo EC
renderiza:

```
Holográfica · My First Battle — Borda Azul · My First Battle — Marca Poké Ball · My First Battle — Deck Bulbasaur
```

Quatro segmentos com o mesmo separador. **A fronteira entre eixos fica
invisível** — o leitor não distingue "onde acaba Finish e começa Edition
Context". Como o mandato veta "repetir separador", isto precisa de decisão.

| Opção | Resultado | Avaliação |
|---|---|---|
| (a) separador de eixo distinto, ex. ` — ` | `Holográfica — Sem Sombra · 1ª Edição — Campeonato Mundial 2010 · Equipe` | Hierarquia visível em uma linha. **Mas** `—` já aparece dentro de nomes de trait (`'My First Battle — Borda Azul'`) → mesma colisão, deslocada |
| (b) ` · ` entre eixos e aceitar o achatamento | como acima | Cumpre a regra literal do mandato e mantém o exemplo conceitual dele, mas perde a hierarquia em aridade alta |
| (c) tooltip com um eixo por linha | `Holográfica`<br>`↳ Sem Sombra · 1ª Edição`<br>`↳ Campeonato Mundial 2010 · Equipe` | Hierarquia perfeita, zero ambiguidade. **Mas** transforma o tooltip em painel — vetado pelo mandato — e não resolve o label em uma linha (relatório, `<select>`) |

Cruzando os vetos do mandato ("nunca repetir separador" × "não transformar
tooltip em painel pesado"), **nenhuma das três é limpa**. É por isso que este
é um ponto de STOP e não uma escolha que eu faça sozinho.

Nota de escopo: das 144 composições de EC, **96 são de aridade 1**, 44 de
aridade 2 e só **4 são de aridade 3** (`SEED-COVERAGE.md` §3; as 89 da tabela
de §3 são só o subconjunto A — somadas aos 7 de B PROVEN dão 96). O caso ruim
é raro (8 rows em 1.085), o que favorece **(b)** — mas a decisão é de Fabrício.

### B3 — as tabelas de Edition Context têm `GRANT` sem `RLS`

Achado fora do frontend, mas que **bloqueia o embed**:

```
2204:69   GRANT SELECT ON TABLE public.card_edition_context_profile TO authenticated;
```

Busca por `ENABLE ROW LEVEL SECURITY` e `CREATE POLICY` em **toda** a pasta
`database/proposals/2026-09-18-edition-context-axis/`: **zero ocorrências**.

Comparação com o eixo irmão, já LIVE:

```
2166:178  ALTER TABLE public.card_printing_profile ENABLE ROW LEVEL SECURITY;
2166:180  CREATE POLICY catalog_admin_select …
2166:186  GRANT SELECT ON public.card_printing_profile TO authenticated;
```

`card_printing_profile` faz os três; as tabelas de EC fazem só o `GRANT`.
Como está, qualquer usuário `authenticated` leria o vocabulário editorial
inteiro — contrariando o padrão admin-only de ADR-028 que o próprio `2166`
segue. Precisa ser corrigido no pacote de EC **antes** de o frontend embutir
essas tabelas.

### B4 — as 365 legacy com Variant Type contaminado

Até a `2213`, 365 `card_variant` carregam Variant Types que codificam contexto
no nome do acabamento (`STANDARD_PIKACHU_WORLD_2000`, `SATANDARD_REWARDS`,
21× `STANDARDS_WORLDS_*`). Elas aparecerão com `Finish` contaminado e sem
Printing nem Edition Context. **Já é o que a tela mostra hoje** — não é
regressão introduzida por esta mudança. Mas é visível, e a UI nova a põe ao
lado de variantes corretas.

### B5 — nada do eixo EC está no LIVE

Reafirmado: a implementação de frontend **não pode começar** antes da etapa 4
do `ROLLOUT-ORDER.md`. Este documento é contrato, não código.

---

## Veredito

**Auditoria completa. Contrato definido. Implementação BLOQUEADA** por
**B1** e **B2** (decisões editoriais de Fabrício) e por **B5** (ordem de
rollout). **B3** é um defeito real do pacote de EC, a corrigir naquela
rodada. **B4** é dívida conhecida, sem ação nesta.
