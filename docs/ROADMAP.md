# Roadmap

| Campo | Valor |
|--------|-------|
| **Documento** | Roadmap |
| **Arquivo** | `docs/ROADMAP.md` |
| **Versão** | 1.4 |
| **Status** | Aprovado |
| **Objetivo** | Consolidar, em uma única fonte de verdade, a trajetória macro do Project Mimikyu — o que já foi concluído, o que está em andamento e o que é direção futura provável, mas ainda não comprometida. |
| **Escopo** | Marcos de alto nível (Fases/Sub-Fases/Blocos). Não substitui `docs/README.md` (estado atual detalhado), `05-modelo-de-dados.md` (execução física) nem `06-pipeline-importacao.md` (estratégia de importação). |
| **Dependências** | `docs/README.md`, `05-modelo-de-dados.md` |
| **Documentos Relacionados** | `06-pipeline-importacao.md`, `adr/ADR-013-collection-item-identity-model.md`, `adr/ADR-014-collection-and-collection-entry-model.md`, `adr/ADR-018-single-function-import-pipeline.md` |

---

# Purpose

Este documento existe porque, ao longo de dezenas de ciclos de documentação, surgiram múltiplas formas paralelas e não reconciliadas de descrever a trajetória do projeto (`B2.x`/`B3.x`, `FASE 1-6`, `FASE 1-4`, `Fase 1-7`), nenhuma delas formalizada como fonte única de verdade. Este documento resolve essa lacuna — mas **apenas para o que já é uma decisão real de Fabrício**. Onde a direção futura ainda não foi comprometida, este documento diz isso explicitamente, em vez de adotar silenciosamente qualquer uma das propostas anteriores.

Criado em 2026-07-24, junto com a reativação da manutenção de `adr/ADR-INDEX.md` e `standards/STD-INDEX.md` — Fabrício declarou nesta data que a documentação do passado do projeto está encerrada e que os artefatos de governança (índices, roadmap) devem passar a ser mantidos ativamente a partir de agora.

---

# Now — Em Andamento

**Importação manual de imagens de `MEE`/`MEP` (TCGdex não tem os assets).**

O pipeline de importação (`import-card-assets`, `ADR-018`) foi executado com sucesso para as sete Card Sets da Expansion `ME`: `card_external_reference` 100% importada em todas (`927`/`927`). Imagens completas para as 5 coleções originais (`ME1`-`ME4`/`ME2.5`: `859` Cards, `1.718` Card Assets, `en`+`pt-BR`, `0` falhas). Para `MEE`/`MEP` (`68` Cards), confirmado por consulta direta ao CDN da TCGdex que o asset genuinamente não existe na fonte (não é gap de API) — decisão de Fabrício: importar manualmente via novo script `scripts/import-manual-assets.ts` (`source_code = 'MANUAL'`, rastreável), em vez de esperar a TCGdex publicar. **`MEE` já confirmada 100% completa (`en`+`pt-BR`, referências e imagens).** Pendente: `MEP`/`en`, `MEP`/`pt-BR` (`60` Cards cada).

Só quando as imagens de `MEE`/`MEP` também estiverem importadas o Catálogo Editorial estará genuinamente fechado — conforme a própria correção de Fabrício registrada em `05-modelo-de-dados.md`, revisão `0.63`: *"Não teremos encerrado toda a fundação do catálogo editorial do Project Mimikyu. Só concluímos após importação de todas as imagens para nossa base."*

---

# Next — Comprometido, Ainda Não Iniciado

**Sub-Fase 2 — Coleções.**

O domínio do colecionador (Collection, Collection Entry, Collection Item — ver `04-domain-model.md` e `ADR-013`/`ADR-014`) já está conceitualmente modelado e aprovado, mas ainda não tem modelo físico (`05-modelo-de-dados.md`) nem tabelas criadas no Supabase. Fabrício confirmou diretamente (revisão `1.40` de `docs/README.md`) que este é o próximo módulo real do projeto, distinto do Catálogo Editorial: exemplares físicos possuídos pelo usuário, objetivos de coleção, e a relação entre ambos.

Início previsto apenas após o fechamento do Catálogo Editorial (item "Now", acima).

---

# Later — Direção Futura Provável, Não Comprometida

Os itens abaixo refletem temas que já apareceram em mais de uma proposta de roadmap ao longo do projeto (sessões pareadas e o próprio Fabrício), mas **nenhum foi formalmente comprometido em sequência, escopo ou modelo de dados**. Estão listados aqui para dar visibilidade de direção, não como plano de execução:

- **Aquisição e movimentação** — registro de compras, trocas e vendas de Cards/Card Variants pelo colecionador.
- **Avaliação e inteligência** — precificação, relatórios e análises sobre a Collection do usuário.
- **Interface / Front-end** — camada de apresentação (mencionada em propostas anteriores como Power Apps, sem decisão vigente sobre a tecnologia).

Qualquer um destes itens só entra em "Next" quando Fabrício o confirmar explicitamente, com escopo próprio — seguindo a mesma disciplina de não resolver unilateralmente decisões de direção que já se aplica ao restante deste projeto.

---

# Concluído

- **Fase 1 — Arquitetura Conceitual.** Princípios arquiteturais, delimitação do domínio, estrutura do catálogo editorial, modelo do universo do colecionador, separação Set/Collection, estratégia de evolução incremental.
- **Sub-Fase 1 — Catálogo Editorial, Bloco A (Modelo de Dados).** Todas as entidades estruturais criadas e homologadas para as 7 Card Sets: `game`, `expansion`, `card_set`, `card` (`927`), `card_category`, `rarity` (10), `language`, `card_variant_type`, `card_variant` (`1.653`), `card_asset_type`/`card_asset`, `storage_bucket`, `asset_source`, `card_external_reference`, `card_set_external_reference`, `asset_import_run`, `asset_import_failure`.
- **Sub-Fase 1 — Catálogo Editorial, Bloco B (Pipeline de Importação), para as 5 coleções originais.** `859` Cards processadas, `859` referências externas, `1.718` Card Assets, `en`+`pt-BR`, `0` falhas.

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Criação do documento (2026-07-24), a pedido explícito de Fabrício, junto com a reativação de `ADR-INDEX.md`/`STD-INDEX.md`. Consolida, pela primeira vez, uma única fonte de verdade para a trajetória do projeto — sem adotar nenhuma das múltiplas propostas de roadmap não reconciliadas surgidas ao longo do projeto (`B2.x`/`B3.x`, `FASE 1-6`, `FASE 1-4`, `Fase 1-7`); itens ainda não comprometidos por Fabrício ficam explicitamente em "Later", não em "Next". |
| 1.1 | Registrado o progresso real de "Now" (2026-07-24): pipeline `import-card-assets` executado pela primeira vez para `MEE` — referências externas confirmadas, imagens bloqueadas por gap de dados na TCGdex (ver `operations/import-card-assets.md`). Próximo passo do item "Now" passa a ser `MEP`. |
| 1.2 | `MEP` executada no mesmo dia, mesmo resultado da `MEE`: referências externas 100%, imagens bloqueadas pelo mesmo gap real de dados na TCGdex. "Now" reescrito — não há mais nenhuma coleção com execução pendente do lado do Project Mimikyu; o item permanece aberto apenas aguardando a TCGdex publicar os assets de `MEE`/`MEP`. |
| 1.3 | Decisão de Fabrício: em vez de esperar a TCGdex, importar as imagens de `MEE`/`MEP` manualmente — confirmado antes que o asset genuinamente não existe no CDN da TCGdex (404 direto, não só ausência no campo `image` da API). Novo script `scripts/import-manual-assets.ts` criado e CONFIRMADO EXECUTADO para `MEE`/`en` (8/8, 0 falhas). "Now" reescrito para refletir trabalho ativo novamente. |
| 1.4 | `MEE`/`pt-BR` executada no mesmo dia (8/8, 0 falhas) — `MEE` agora 100% completa nos dois idiomas. Falta só `MEP`/`en`+`pt-BR` (`60` Cards cada) para o Catálogo Editorial estar genuinamente fechado. |
