# ADR-018 — Single-Function Import Pipeline

| Campo | Valor |
|--------|-------|
| **ADR** | ADR-018 |
| **Título** | Single-Function Import Pipeline |
| **Status** | Aprovado — formaliza a arquitetura real, já implementada e confirmada por execução de ponta a ponta (859 cartas, 1.718 imagens, `en`+`pt-BR`, 0 falhas, nas 5 coleções `ME1`-`ME4`/`ME2.5`). |
| **Data** | 2026-07-24 |
| **Decisores** | Project Mimikyu (reconciliação de documentação conduzida por Fabrício) |
| **Decisão** | O pipeline de importação de referências externas e ativos visuais permanece em **uma única Edge Function**, `import-card-assets`: recebe um `run_code`, resolve `card_set`/`card_set_external_reference`, consulta a TCGdex (`TcgdexClient.getSet()`), sincroniza `card_external_reference` (`UPSERT`) e, na mesma execução, baixa/envia ao Storage/grava `card_asset` para cada carta. Substitui a divisão em duas Edge Functions (`sync-card-set`/`import-card-assets`) decidida em `ADR-017`, nunca implementada. |
| **Documentos Relacionados** | `../06-pipeline-importacao.md`, `../operations/import-card-assets.md`, `ADR-017-two-function-import-pipeline.md` (substituída por esta ADR), `ADR-008-external-catalog-data-sources.md` |

---

# Context

`ADR-017` (2026-07) decidiu dividir o pipeline em duas Edge Functions — `sync-card-set` (descoberta/catalogação) e `import-card-assets` (download de imagens) — para evitar que uma única função sobrecarregada crescesse descontroladamente conforme o catálogo aumentasse.

Essa divisão nunca se concretizou. Ao longo dos Sprints B3.11–B3.26 (ver `../06-pipeline-importacao.md` e `../history/pipeline-sprint-log.md`), todo o trabalho real — Incremento 1 (sincronização de `card_external_reference` a partir da TCGdex) e Incremento 2 (download de imagens, upload ao Storage, registro em `card_asset`) — foi implementado, deployado e confirmado dentro da Edge Function já existente, `import-card-assets`. Nenhuma pasta `sync-card-set/` chegou a ser criada via CLI; o único diretório real em `supabase/functions/` é `import-card-assets/`.

O resultado, confirmado por execução real, é uma única função que resolve o Set, consulta a fonte externa, sincroniza referências **e** baixa imagens na mesma invocação — exatamente o desenho "original" que `ADR-017` havia descartado por risco de escala, não o desenho de duas funções que `ADR-017` decidiu adotar.

Esta divergência já estava sinalizada, sem resolução, em `../06-pipeline-importacao.md` ("Em Aberto", desde a revisão `1.1`): *"`ADR-017-two-function-import-pipeline.md` descreve uma arquitetura de duas Edge Functions (`sync-card-set`/`import-card-assets`); na prática, apenas `import-card-assets` foi construída e faz tudo — o ADR precisa ser revisado/marcado como superado ou reconciliado com a implementação real."* Esta ADR resolve essa pendência: reconcilia a documentação com a implementação, sem alterar código.

---

# Decision

## Uma Edge Function, todas as responsabilidades

`import-card-assets` (`supabase/functions/import-card-assets/`) é a única função do pipeline de importação. Recebe um `run_code` (identificador de um `asset_import_run` já criado) e, numa única execução:

```text
run_code → asset_import_run → card_set → card_set_external_reference
    → TcgdexClient.getSet() (catálogo completo do Set na TCGdex)
    → UPSERT em card_external_reference (todas as cartas)
    → download + upload ao Storage + UPSERT em card_asset (todas as cartas)
```

Arquitetura interna em camadas (preservada de `ADR-017`, já real e confirmada): `index.ts` (orquestrador puro) → `services/database.ts` (único acesso ao PostgreSQL) → `services/tcgdex.ts` (`TcgdexClient`, único ponto de `fetch()` à TCGdex) → `services/storage.ts` (upload ao Supabase Storage). Ver `../06-pipeline-importacao.md`, seção "Arquitetura Final", para o detalhamento completo já documentado como estado vigente.

## Nenhuma mudança de código motivada por esta ADR

Esta ADR não altera a implementação — apenas documenta, como decisão formal, o que já está deployado e confirmado. Nenhuma ação em `supabase/functions/` decorre desta revisão.

---

# Consequences

## Benefícios

- a documentação arquitetural (`ADR`) passa a refletir com precisão o que está realmente implantado, eliminando a divergência sinalizada em `../06-pipeline-importacao.md`;
- confirmado por evidência real (5 coleções, 2 idiomas, 0 falhas) que uma única função dá conta do volume atual do projeto sem o problema de escala que `ADR-017` antecipava;
- simplicidade operacional: um único deploy, uma única invocação por coleção (ver `../operations/import-card-assets.md`).

## Restrições / Pendências

- **O risco de escala que motivou `ADR-017` não foi refutado, apenas ainda não se materializou.** Com 7 Card Sets e 927 Cards no catálogo (ainda crescendo — `MEE`/`MEP` aguardam `card_variant`), uma coleção futura significativamente maior, ou a necessidade de reexecutar descoberta e download em cadências diferentes, pode reabrir a justificativa original de `ADR-017`. Se isso ocorrer, a divisão em duas funções deve ser reavaliada como uma nova ADR — não revivendo `ADR-017` (permanece Substituída, histórico preservado), mas com uma decisão nova, à luz da necessidade real então observada.
- A limitação real de idioma fixo no código (`LANGUAGE_CODE`/`TCGDEX_LANGUAGE` como constantes, não parâmetros) permanece sem solução, documentada em `../06-pipeline-importacao.md`, "Em Aberto" — não é escopo desta ADR.
- `MEE`/`MEP` ainda não passaram por este pipeline (aguardam `card_variant`, ver `../05-modelo-de-dados.md`) — quando passarem, usarão a mesma função única aqui formalizada, sem mudança de arquitetura esperada.

---

# Alternatives Considered

## Reviver a divisão de `ADR-017` agora, criando `sync-card-set`

Rejeitada nesta revisão. Não há evidência real de que a função única esteja sobrecarregada — 927 Cards/7 Card Sets processados com 0 falhas. Dividir a função agora seria trabalho de engenharia sem problema real a resolver, contrariando o princípio de simplicidade inicial (`AP-004`). Fica registrada como opção futura, não descartada, condicionada a uma necessidade real observada (ver "Restrições / Pendências", acima).

## Manter `ADR-017` como "Aprovada" e tratar a implementação como pendente

Rejeitada. `ADR-017` já estava marcada como "decisão declarada, sem implementação real" há dezenas de batches, sem nenhum sinal de que `sync-card-set` viria a ser criada — o próprio roteiro real do projeto (Sprints B3.11 em diante) seguiu por outro caminho sem revisitar essa decisão. Manter o ADR como vigente enquanto a realidade diverge continuamente é o problema que esta ADR resolve, não uma alternativa válida.

---

# Related Documents

- `../06-pipeline-importacao.md`
- `../operations/import-card-assets.md`
- `../history/pipeline-sprint-log.md`
- `ADR-017-two-function-import-pipeline.md` (substituída por esta ADR)
- `ADR-008-external-catalog-data-sources.md`

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Criação — formaliza a arquitetura de função única (`import-card-assets`) como decisão vigente, substituindo `ADR-017-two-function-import-pipeline.md`. Reconciliação motivada por auditoria de qualidade documental conduzida por Fabrício (2026-07-24); divergência já estava sinalizada, sem resolução, em `../06-pipeline-importacao.md` desde sua revisão `1.1`. Nenhuma mudança de código. |
