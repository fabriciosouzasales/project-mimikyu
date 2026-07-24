# ADR-017 — Two-Function Import Pipeline (Catalog Discovery vs. Asset Import)

| Campo | Valor |
|--------|-------|
| **ADR** | ADR-017 |
| **Título** | Two-Function Import Pipeline (Catalog Discovery vs. Asset Import) |
| **Status** | Substituído por `ADR-018-single-function-import-pipeline.md` (2026-07-24) — a divisão em duas Edge Functions aqui decidida nunca foi implementada; a arquitetura real, confirmada por execução de ponta a ponta ao longo dos Sprints B2.1–B3.26 (859 cartas, 1.718 imagens, `en`+`pt-BR`, 0 falhas), consolidou tudo em uma única Edge Function (`import-card-assets`). Ver `ADR-018` para a decisão vigente e a Revision History abaixo para o contexto da supersessão. |
| **Data** | 2026-07 |
| **Decisores** | Project Mimikyu |
| **Decisão** | O pipeline de importação de ativos visuais passa a ser dividido em duas Edge Functions com responsabilidades exclusivas: `sync-card-set` (nova) sincroniza o catálogo completo de cartas de um `card_set` a partir da TCGdex, populando `card_external_reference` — nunca baixa imagem, nunca toca Storage; `import-card-assets` (já existente, papel redefinido) consome as referências já sincronizadas, baixa as imagens e grava `card_asset` — deixa de descobrir cartas por conta própria. Internamente, cada função segue uma arquitetura em camadas fixa: `index.ts` (orquestrador) → `database.ts` (único acesso ao PostgreSQL) → `tcgdex.ts` (único ponto de chamada `fetch()` à API da TCGdex, encapsulado em uma classe `TcgdexClient`) → API REST da TCGdex. |
| **Documentos Relacionados** | `../06-pipeline-importacao.md`, `ADR-008-external-catalog-data-sources.md` |

---

# Context

O desenho original da Edge Function `import-card-assets` (ver `../06-pipeline-importacao.md`, seção "Arquitetura de Execução — Edge Function `import-card-assets` (Bloco B1)") especificava uma única função responsável por, em sequência: validar a execução, selecionar as cartas, resolver a referência externa, consultar a fonte externa, baixar a imagem, validá-la, formatá-la, enviá-la ao Storage e registrar `card_asset` — tudo dentro do mesmo fluxo, para cada carta processada.

Ao planejar a integração real com a TCGdex (Sprint B2.5A/B2.5B), dois problemas concretos surgiram:

**1. Ordem invertida do pipeline.** A implementação estava, na prática, seguindo `SET → IMAGENS` diretamente — tentando ir do `card_set` até o download de imagens sem antes estabelecer o catálogo oficial completo de cartas daquele Set. A ordem correta, identificada durante o planejamento desta sprint, é `SET → CATÁLOGO → REFERÊNCIAS → IMAGENS`: antes de baixar qualquer imagem, é preciso primeiro descobrir e registrar todas as cartas do Set (`card_external_reference`), para então, em uma etapa seguinte e independente, processar as imagens pendentes.

**2. Uma única função sobrecarregada não escala.** Simulação apresentada pela sessão pareada: para um único Set com 188 cartas (`ME1`), a função, do jeito originalmente especificada, executaria — para cada uma das 188 cartas — download → upload → insert, tudo dentro do mesmo fluxo que também descobre quais cartas existem e resolve suas referências externas. Em escala (múltiplos Sets, milhares de cartas), essa função cresceria descontroladamente e seria difícil de testar isoladamente por etapa.

---

# Decision

## Duas Edge Functions, cada uma com responsabilidade exclusiva

- **`sync-card-set`** (nova, ainda não criada via CLI): recebe `card_set_id` → localiza `external_set_id` em `card_set_external_reference` → consulta a TCGdex → obtém a lista completa de cartas do Set → grava/atualiza `card_external_reference` para cada uma. **Nunca baixa imagem, nunca toca Storage.**
- **`import-card-assets`** (já existente — ver Sprints B2.0-B2.4.1 em `../06-pipeline-importacao.md` —, papel redefinido): parte de `card_external_reference` **já sincronizada** por `sync-card-set` → baixa imagem (`small`/`highres`/`thumb`) → envia ao Supabase Storage → grava `card_asset`. Deixa de ser responsável por descobrir quais cartas existem — passa a apenas consumir referências já catalogadas.

Dois pipelines lógicos resultam disso, não um:

```text
Pipeline 1 — Descoberta (sync-card-set)
Entrada: card_set (ex. ME3) → external_set_id
Saída:   N cartas cadastradas em card_external_reference
         Nenhuma imagem.

Pipeline 2 — Assets (import-card-assets)
Entrada: card_external_reference já sincronizada
Saída:   card_asset (small/highres/thumb) no Storage
```

Uma vez que `card_external_reference` tenha sido sincronizada para um Set, a TCGdex não precisa mais ser consultada para saber quais cartas existem naquela coleção — apenas uma vez por Set, não uma vez por carta.

## Arquitetura interna em camadas, fixa para as duas funções

Estende a Convenção #6 já declarada no Sprint B2.4.1 (`index.ts` como orquestrador puro, sem conhecer SQL/PostgreSQL/TCGdex diretamente):

```text
Edge Function (index.ts)
        ↓
Database Layer (database.ts)   ← único ponto de acesso ao PostgreSQL
        ↓
TCGDEX Client (tcgdex.ts)      ← único ponto de chamada fetch() à API da TCGdex
        ↓
TCGDEX REST API
```

Nenhuma outra camada do projeto deve fazer `fetch()` diretamente contra a TCGdex. Toda a comunicação HTTP com a fonte externa fica isolada em `tcgdex.ts`, reescrito como uma classe `TcgdexClient` (substitui as versões anteriores baseadas em uma função solta — `findTcgDexSet`, depois `getSet` — ver `../06-pipeline-importacao.md`, revisões `0.14`-`0.17`).

## Nenhuma mudança de schema necessária

Reafirmado explicitamente pela sessão pareada: toda a modelagem física já existente (`card_set_external_reference`, `card_external_reference`, `card_asset`, `asset_import_run`, `asset_import_failure`) já suporta esta divisão sem alteração de tabela — a mudança é puramente de organização de código/responsabilidade entre Edge Functions.

---

# Consequences

## Benefícios

- cada função fica pequena e testável isoladamente, podendo ser reexecutada quantas vezes forem necessárias sem efeito colateral sobre a outra;
- separa claramente "descobrir o que existe" (barato, uma vez por Set) de "baixar o que falta" (caro, uma vez por carta/imagem);
- evita que `import-card-assets` cresça descontroladamente conforme o catálogo aumenta;
- a camada `tcgdex.ts` isolada permite, no futuro, trocar ou adicionar uma segunda fonte externa (ex. Pokémon TCG API, já prevista como fonte alternativa em `../06-pipeline-importacao.md`) sem alterar `index.ts`/`database.ts`.

## Restrições / Pendências

- **Declarada como decisão definitiva, mas sem nenhuma implementação real confirmada.** Nenhuma Edge Function `sync-card-set` foi criada via CLI (`npx supabase functions new sync-card-set`); nenhum deploy; nenhum teste real de nenhuma das duas funções sob esta nova arquitetura.
- O `TcgdexClient` (`tcgdex.ts`) foi reescrito como classe (`getSet`/`getCardsBySet`/`getCard`) e colado verbatim na conversa, mas **não copiado ao repositório** — segue o princípio já consolidado no projeto de "copiar código apenas após execução/deploy confirmado".
- O endpoint usado por `getCardsBySet` (`GET /sets/{id}/cards`) foi assumido a partir da documentação da TCGdex, **sem confirmação por uma chamada real** antes de o código ser fechado — diferente da descoberta de `external_set_id` (Sprint B2.5A), que foi validada por execução real. Precisa ser verificado antes do primeiro deploy de `sync-card-set`.
- O mapeamento entre o roteiro vigente de `../06-pipeline-importacao.md` (`B2.5B`–`B2.9`, pensado para uma única função) e esta nova divisão em duas funções ainda não foi detalhado por Fabrício — a tabela "Roteiro vigente" daquele documento foi mantida sem reescrita, mesma cautela adotada desde o incidente de confiança da revisão `0.49` de `05-modelo-de-dados.md`.
- A decisão de negócio sobre `ME0`↔`mee`/"Mega Evolution Energy" (ver `../06-pipeline-importacao.md`, Sprint B2.5A, revisão `0.17`) continua em aberto e bloqueia a Seed `910`, independentemente desta correção de arquitetura.
- Próximo passo confirmado: Sprint B3 implementa `sync-card-set` primeiro, isoladamente — `import-card-assets` só evolui para a nova arquitetura depois disso.

---

# Alternatives Considered

## Uma única Edge Function fazendo tudo (desenho original)

O desenho inicial de `import-card-assets` (ver `../06-pipeline-importacao.md`, seção "Arquitetura de Execução") especificava uma função monolítica cobrindo desde a validação da execução até o registro final de `card_asset`. Descartado nesta revisão por não escalar bem — a simulação de `ME1` (188 cartas, cada uma exigindo download/upload/insert dentro do mesmo fluxo que também descobre e resolve referências) evidenciou o risco de uma função excessivamente grande e difícil de testar por etapa.

## Nova Edge Function dedicada apenas à descoberta de `external_set_id` (`sync-card-sets`)

Proposta e reconsiderada em uma sprint anterior (ver `../06-pipeline-importacao.md`, Sprint B2.5A, revisão `0.16`) — decisão diferente desta ADR, sobre um problema diferente (descoberta pontual de identificadores de Set, resolvida por um script administrativo standalone, não por uma Edge Function permanente). Não deve ser confundida com `sync-card-set` (singular), que é a função de sincronização de catálogo de cartas por Set, permanente, criada por esta ADR.

---

# Related Documents

- `../06-pipeline-importacao.md`
- `ADR-008-external-catalog-data-sources.md`

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Registro da decisão: pipeline de importação dividido em duas Edge Functions (`sync-card-set` para descoberta/catalogação, `import-card-assets` redefinida para consumo de referências já sincronizadas + download de imagens), com arquitetura interna em camadas fixa (`index.ts` → `database.ts` → `tcgdex.ts` → API REST da TCGdex). Decisão declarada definitiva pela sessão pareada; nenhuma implementação real confirmada nesta revisão — código de `tcgdex.ts` (`TcgdexClient`) recebido em rascunho, não deployado, não copiado ao repositório. |
| 1.1 | **Substituído por `ADR-018-single-function-import-pipeline.md`.** A divisão em duas Edge Functions nunca chegou a ser implementada: `sync-card-set` jamais foi criada (nenhuma pasta própria via `npx supabase functions new`), e todo o trabalho real dos Sprints B3.11–B3.26 — sincronização de `card_external_reference` (Incremento 1) e download de imagens (Incremento 2) — foi construído e confirmado dentro da função já existente, `import-card-assets`, que hoje faz sozinha tudo o que esta ADR havia dividido em duas. Já sinalizado como discrepância aberta em `../06-pipeline-importacao.md` ("Em Aberto") desde sua revisão `1.1`; reconciliado nesta revisão a pedido de Fabrício, após auditoria de qualidade documental (2026-07-24). O contexto/decisão originais acima são preservados como registro histórico, não reescritos — a decisão vigente está em `ADR-018`. |
