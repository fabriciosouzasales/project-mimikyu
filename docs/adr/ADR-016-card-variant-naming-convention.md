# ADR-016 — Card Variant Naming Convention

| Campo | Valor |
|--------|-------|
| **ADR** | ADR-016 |
| **Título** | Card Variant Naming Convention |
| **Status** | Aprovado |
| **Data** | 2026-07-23 |
| **Decisores** | Fabrício Sales |
| **Decisão** | O termo conceitual canônico do domínio volta a ser **Card Variant Type** / **Card Variant**, convergindo com o nome já usado no schema físico, no pipeline de importação e na linguagem prática do projeto. Esta decisão substitui **apenas** a parte de nomenclatura de ADR-010 (que havia introduzido "Finish"/"Card Finish"). A separação de Rarity como atributo de primeira classe da Card, também decidida em ADR-010, permanece válida e não é afetada. |
| **Documentos Relacionados** | `../04-domain-model.md`, `../05-modelo-de-dados.md`, `ADR-009-card-variant-scope.md`, `ADR-010-card-rarity-and-finish-model.md` |

---

# Context

ADR-010 retirou o termo "Card Variant" do vocabulário conceitual do domínio, substituindo-o por "Finish" (catálogo de acabamentos) e "Card Finish" (associação Card+Finish), deixando explicitamente em aberto se as tabelas físicas pré-existentes `card_variant`/`card_variant_type` seriam renomeadas para acompanhar essa decisão conceitual.

Essa renomeação física nunca se concretizou, nem foi necessária na prática: toda a modelagem física subsequente (Queries `150`/`151`/`160`/`161`/`850`/`950`/`860`, e a própria ADR-008) foi construída e executada sob os nomes `card_variant_type`/`card_variant`, sem qualquer referência a "Finish"/"Card Finish". A divergência entre o vocabulário conceitual (`04-domain-model.md`) e o nome usado na implementação real (`05-modelo-de-dados.md`, banco de dados, pipeline de importação) foi sinalizada repetidamente ao longo de múltiplos ciclos de documentação, sem resolução — cada novo lote de execução reforçava a evidência de que "Card Variant" era o nome efetivamente em uso, sem que a decisão conceitual fosse revisitada.

Avaliação de Fabrício, que resolve a tensão: Card Variant Type/Card Variant deve prevalecer como termo conceitual, porque:

- é o nome já adotado no banco de dados;
- é o nome usado no fluxo de importação;
- é o nome intuitivamente utilizado pelo próprio usuário do sistema;
- "Card Variant" não está sendo usado para descrever Full Art, Gold ou Secret Rare — o escopo já está corretamente restrito a versões físicas da mesma Card (a restrição de escopo estabelecida em ADR-009 e preservada em ADR-010 permanece válida e não é reaberta por esta decisão);
- manter um termo conceitual ("Finish"/"Card Finish") e um termo físico diferente ("Card Variant") sem necessidade aumenta a carga cognitiva sem benefício correspondente.

---

# Decision

O vocabulário conceitual do domínio adota **Card Variant Type** e **Card Variant** como termos canônicos, revertendo a escolha de nomenclatura de ADR-010:

- **Card Variant Type**: catálogo controlado de tipos de acabamento físico possíveis para uma Card (ex.: Standard, Holo, Reverse Holo). Substitui o termo conceitual "Finish".
- **Card Variant**: declara que uma Card específica está disponível em um Card Variant Type específico. Substitui o termo conceitual "Card Finish". Relação: `Card 1 → N Card Variant`, cada Card Variant referenciando 1 Card Variant Type.
- **Collection Item** referencia um Card Variant específico (não a Card diretamente) — mesma relação já estabelecida em ADR-010 e ADR-013, apenas com o nome atualizado.

**O que NÃO muda** — decisões de ADR-010 preservadas sem alteração:

- Rarity continua sendo um atributo/relação de primeira classe da Card, distinto de Card Variant.
- O escopo de Card Variant continua restrito a diferenças físicas de acabamento sobre a mesma posição catalográfica — Full Art, Illustration Rare, Special Illustration Rare, Hyper Rare, Gold e Rainbow continuam sendo Cards independentes, não Card Variants (ADR-009, preservado por ADR-010, preservado aqui).

Nenhuma alteração é necessária no schema físico: `card_variant`/`card_variant_type` já usam o nome agora adotado também no vocabulário conceitual.

---

# Consequences

## Benefícios

- elimina a divergência entre o vocabulário conceitual e o nome já usado no banco de dados, no pipeline de importação e na comunicação prática do projeto;
- reduz a carga cognitiva de manter e traduzir mentalmente dois nomes para o mesmo conceito;
- nenhuma migration ou renomeação física é necessária — a convergência ocorre inteiramente no vocabulário conceitual, não no banco.

## Restrições

- toda documentação existente que usa "Finish"/"Card Finish" como termo conceitual deve ser atualizada para "Card Variant Type"/"Card Variant" (`04-domain-model.md`, `05-modelo-de-dados.md`, `architecture/ubiquitous-language.md`, e referências cruzadas em outros documentos);
- "Finish" e "Card Finish" passam a ser tratados como sinônimos históricos, preservados no histórico de revisão dos documentos e no texto original de ADR-009/ADR-010, não como termos ativos do vocabulário.

---

# Alternatives Considered

## Manter Finish/Card Finish como termo conceitual, mapeado para as tabelas físicas

Rejeitada. Manteria permanentemente uma tradução mental entre o termo usado na documentação e o termo usado na prática (banco, importação, comunicação do projeto), sem benefício correspondente — a motivação original de ADR-010 para o nome "Finish" (evitar que a palavra "variant" sugerisse uma versão editorial derivada) não se mostrou necessária, já que o escopo de Card Variant já está claramente restrito a acabamentos físicos por ADR-009.

## Renomear as tabelas físicas para `finish`/`card_finish`

Rejeitada. Exigiria uma migration de renomeação sem ganho conceitual, além de romper a consistência já estabelecida com Queries, seeds e validações já executadas e documentadas sob os nomes atuais.

---

# Related Documents

- `../04-domain-model.md`
- `../05-modelo-de-dados.md`
- `ADR-009-card-variant-scope.md`
- `ADR-010-card-rarity-and-finish-model.md`

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Registro da decisão que converge o vocabulário conceitual do domínio para Card Variant Type/Card Variant, revertendo a nomenclatura Finish/Card Finish de ADR-010. A separação de Rarity como atributo de primeira classe da Card (também decidida em ADR-010) permanece válida e não é afetada. |
