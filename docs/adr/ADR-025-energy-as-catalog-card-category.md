# ADR-025 — Energy as Catalog Card Category

| Campo | Valor |
|--------|-------|
| **ADR** | ADR-025 |
| **Título** | Energy as Catalog Card Category |
| **Status** | Aprovado |
| **Data** | 2026-07-30 |
| **Decisores** | Fabrício Sales |
| **Decisão** | Cartas de Energia passam a ocupar posição oficial no Set e a fazer parte do catálogo editorial numerado do Project Mimikyu, da mesma forma que Cards de Pokémon e de Treinador. `Card Category` passa a ter, no contexto atual do Pokémon TCG, três valores possíveis: `POKEMON`, `TRAINER`, `ENERGY`. Esta decisão substitui a definição de escopo anterior (ver `04-domain-model.md`, seção "Decisão de Escopo — Cartas de Energia", agora marcada como substituída), sob a qual cartas de Energia estavam fora do catálogo numerado. |
| **Documentos Relacionados** | `ADR-011-pokemon-tcg-domain-scope.md`, `ADR-012-structured-vs-visual-card-data.md`, `../04-domain-model.md`, `../05-modelo-de-dados.md`, `../architecture/ubiquitous-language.md` |

---

# Context

A definição original de escopo do domínio Pokémon TCG (`ADR-011`) e a modelagem de `Card Category` em `04-domain-model.md` estabeleceram, historicamente, apenas dois valores para a categoria de uma Card no catálogo numerado: Pokémon e Trainer. Sob essa definição, cartas de Energia eram tratadas como fora do escopo do catálogo editorial numerado — não ocupando posição oficial no Set.

Essa definição de escopo divergiu da realidade física do banco de dados: a categoria `ENERGY` já existe na tabela `card_category`, e existem hoje 17 Cards reais com essa categoria, importadas e presentes no catálogo (confirmado via Query `831`, executada em produção). Ou seja, o sistema já armazena e trata cartas de Energia como Cards de pleno direito — com posição de coleção (`collector_number`), pertencimento a um Set (`card_set_id`) e demais atributos padrão de `card` — mesmo com a documentação descrevendo o oposto.

Essa divergência entre decisão documentada e dado físico foi identificada e registrada como Open Decision (`OD-001`) em `04-domain-model.md`, aguardando resolução explícita de Fabrício.

# Decision

Fabrício decidiu, de forma explícita e definitiva, encerrar essa divergência reconhecendo a realidade já implementada como a decisão vigente do produto: **cartas de Energia ocupam posição oficial no Set e fazem parte do catálogo editorial numerado, da mesma forma que Cards de Pokémon e de Treinador.**

## `Card Category` passa a ter três valores

No contexto atual do domínio Pokémon TCG (`ADR-011`), `Card Category` passa a admitir três valores: `POKEMON`, `TRAINER`, `ENERGY`. Os campos condicionais já existentes na regra de integridade conceitual de Card (`04-domain-model.md`) se aplicam a Energy da mesma forma que já se aplicavam a Trainer: uma Card de categoria Energy não possui Trainer Subcategory nem referência a Pokémon.

Nenhuma alteração física é necessária no banco para viabilizar esta decisão — a categoria `ENERGY` e os 17 Cards que a utilizam já existem e já estão corretamente modelados na tabela `card_category`/`card`. Este ADR formaliza documentalmente uma realidade que já era física, não introduz uma mudança de schema.

## Energy Card não é o mesmo conceito que Energy Type

Esta decisão distingue explicitamente dois conceitos que compartilham o nome apenas por coincidência de domínio:

- **Card Category = Energy** — descrito por este ADR. É a categoria da própria Card: ela é, ela mesma, uma carta de Energia (ex.: "Fire Energy", "Double Colorless Energy"), com posição no Set e presença no catálogo numerado, no mesmo nível estrutural de Pokémon e Trainer.
- **Energy Type** — não afetado por este ADR. É um atributo elemental (ex.: Fire, Water, Grass) que qualifica um Pokémon ou um ataque, permanentemente não estruturado por decisão de AP-017 (Princípio do Escopo Colecionável, `02-architecture-principles.md`) — é mecânica de jogo, visível apenas via imagem.

Uma carta de Energia (Card Category = Energy) pode inclusive representar visualmente um Energy Type (ex.: a carta "Fire Energy" remete ao tipo Fire) — essa relação permanece apenas visual, não estruturada, exatamente como já valia para os demais campos de mecânica de jogo cobertos por AP-017.

## Escopo de domínio (`ADR-011`) não é reaberto

Este ADR não reabre nem reavalia o escopo geral do domínio definido em `ADR-011` (Pokémon TCG Domain Scope). Ele resolve especificamente a posição de cartas de Energia dentro do catálogo numerado — um ponto que `ADR-011` não havia decidido com a granularidade necessária, e que ficou registrado como divergência (`OD-001`) até esta decisão.

# Consequences

## Impactos conceituais e documentais

- `04-domain-model.md`: seção "Card Category" atualizada para três valores; antiga "Decisão de Escopo — Cartas de Energia" marcada como substituída (texto histórico preservado); nova subseção "Decisão Vigente — Cartas de Energia no Catálogo Numerado" registra o estado atual; "Regra de Integridade Conceitual" ganha o caso `Card Category = Energy`; seção "Energy Type" ganha nota de desambiguação; `OD-001` movida de Open Decisions para Resolvidas, com rastreabilidade a este ADR.
- `docs/architecture/ubiquitous-language.md`: definição de `Card Category` atualizada para refletir três valores, removendo a afirmação de que cartas de Energia não ocupam posição no Set.
- `docs/adr/ADR-INDEX.md`: catálogo de ADRs e Revision History atualizados com esta entrada.
- Nenhum impacto em `docs/07-catalogo-editorial.md`: o documento já trata "Category" apenas como um exemplo conceitual de Structured Data, sem enumerar valores específicos — não há afirmação a corrigir ali.
- Nenhum impacto em `docs/02-architecture-principles.md`: AP-017 (Princípio do Escopo Colecionável) trata exclusivamente de mecânica de jogo (HP, ataques, habilidades etc.) e não faz nenhuma afirmação sobre a posição de cartas de Energia no catálogo numerado — os dois pontos são ortogonais.

## O que é substituído

- A seção "Decisão de Escopo — Cartas de Energia" em `04-domain-model.md`, sob a qual cartas de Energia estavam fora do catálogo numerado, é substituída por este ADR. O texto histórico é preservado, não apagado — apenas marcado como não vigente.
- Nenhum ADR anterior tem seu conteúdo alterado retroativamente. `ADR-011` permanece com seu texto original; este ADR apenas complementa, para o ponto específico da posição de Energy no catálogo, uma decisão que `ADR-011` não havia tomado.

## Restrições / Pendências

- Nenhuma migration ou alteração física é necessária — a categoria `ENERGY` e os Cards que a utilizam já existem em produção (Query `831`).
- Esta decisão não define regras adicionais de captura, importação ou apresentação específicas para cartas de Energia além das já vigentes para Pokémon/Trainer — elas seguem o mesmo pipeline e o mesmo modelo de Card já documentados em `05-modelo-de-dados.md` e `06-pipeline-importacao.md`.

---

# Alternatives Considered

## Manter cartas de Energia fora do catálogo numerado, corrigindo o dado físico

Consideraria remover ou reclassificar os 17 Cards de categoria `ENERGY` já existentes para alinhar o banco à decisão documentada anteriormente. Rejeitada por Fabrício: a presença de cartas de Energia com posição própria no Set é a representação correta do produto colecionável (Energy é uma carta oficialmente numerada em um Set de Pokémon TCG), e a decisão anterior — que as excluía — é que estava desalinhada com a realidade do domínio, não o inverso.

## Tratar Energy como uma quarta categoria sem paridade estrutural com Pokémon/Trainer

Considerada uma modelagem intermediária, na qual Energy teria uma tabela ou regras à parte. Rejeitada por não haver necessidade concreta hoje (AP-004, Simplicidade Inicial) — Energy se encaixa integralmente no modelo já existente de `card`/`card_category`, sem exigir estrutura adicional.

---

# Related Documents

- `ADR-011-pokemon-tcg-domain-scope.md`
- `ADR-012-structured-vs-visual-card-data.md`
- `../04-domain-model.md`
- `../05-modelo-de-dados.md`
- `../architecture/ubiquitous-language.md`
- `../02-architecture-principles.md`

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Criação — formaliza a decisão explícita e definitiva de Fabrício de que cartas de Energia ocupam posição oficial no Set e fazem parte do catálogo editorial numerado, como Pokémon e Trainer. `Card Category` passa a ter três valores (`POKEMON`, `TRAINER`, `ENERGY`). Esclarece que Energy Card (categoria da própria Card) e Energy Type (atributo elemental, mecânica de jogo coberta por AP-017) são conceitos distintos. Resolve `OD-001`, registrada em `04-domain-model.md`. Nenhuma alteração física no banco — a categoria `ENERGY` e os 17 Cards que a utilizam já existiam (Query `831`); este ADR formaliza documentalmente uma realidade já implementada. |
