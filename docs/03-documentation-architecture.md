# Documentation Architecture

| Campo | Valor |
|--------|-------|
| **Documento** | Documentation Architecture |
| **Arquivo** | `docs/03-documentation-architecture.md` |
| **Versão** | 1.12 |
| **Status** | Aprovado |
| **Objetivo** | Definir a organização, as responsabilidades e a governança da documentação oficial do Project Mimikyu. |
| **Escopo** | Toda a documentação mantida no repositório oficial. |
| **Dependências** | `00-project-charter.md`, `01-technical-identity.md`, `02-architecture-principles.md` |
| **Documentos Relacionados** | `README.md`, `adr/ADR-INDEX.md`, `standards/STD-INDEX.md`, `architecture/README.md` |

---

# Overview

A documentação do Project Mimikyu é organizada em artefatos especializados. Cada artefato possui uma responsabilidade única e deve evitar sobreposição de conteúdo.

O repositório oficial é a fonte permanente de verdade para decisões, padrões, arquitetura e identidade técnica do projeto.

---

# Documentation Structure

```text
CLAUDE.md (raiz do repositório, fora de docs/)
docs/
├── README.md
├── ROADMAP.md
├── INDEX.md
├── log.md
├── 00-project-charter.md
├── 01-technical-identity.md
├── 02-architecture-principles.md
├── 03-documentation-architecture.md
├── 04-domain-model.md
├── 05-modelo-de-dados.md (índice + metodologia)
├── 05a-catalogo-base.md
├── 05b-cartas-e-raridade.md
├── 05c-assets-e-importacao.md
├── 05d-colecoes-e-usuarios.md
├── 05e-catalogo-editorial.md
├── 06-pipeline-importacao.md
├── 07-catalogo-editorial.md
├── adr/
│   ├── ADR-INDEX.md
│   └── ADR-NNN-title.md
├── standards/
│   ├── STD-INDEX.md
│   └── STD-NNN-title.md
├── architecture/
│   ├── README.md
│   ├── ubiquitous-language.md
│   └── ...
├── operations/
│   └── <artefato>.md
├── history/
│   ├── <artefato>.md
│   └── development/
│       └── HANDOFF-AAAA-MM-DD.md
└── development/
    └── HANDOFF-AAAA-MM-DD.md
```

Os documentos `04` a `07` seguem a mesma numeração sequencial dos documentos centrais (`00`-`03`) e já possuem conteúdo em elaboração.

**`development/` — formalizado (2026-07-26), a partir de `docs/development/HANDOFF-2026-07-26.md`, criado sem que a árvore documental o previsse.** Ver a responsabilidade completa e o ciclo de vida na tabela "Artifact Responsibilities" e na nota abaixo.

**Ciclo de vida dos handoffs.** Apenas um handoff é vigente por vez, nomeado `HANDOFF-AAAA-MM-DD.md` com a data da sessão que o produziu. Ao criar um novo handoff, o anterior é movido para `history/development/` (mesmo padrão de `history/`: preserva rastreabilidade sem sobrecarregar a leitura corrente) — nunca dois handoffs vigentes simultâneos em `development/`. `docs/README.md`, seção "Status Atual do Projeto", aponta para o handoff vigente. Nenhuma decisão permanente (arquitetural, de modelagem, de processo) deve existir apenas em um handoff — se uma sessão tomar uma decisão desse tipo, ela precisa ser registrada em seu artefato normativo próprio (ADR, Standard, ou o documento de arquitetura correspondente) no mesmo ciclo; o handoff pode referenciá-la, mas não é a fonte de verdade dela.

**`CLAUDE.md`/`INDEX.md`/`log.md` — criados (2026-08-06), adequação ao padrão LLM Wiki.** Três artefatos novos, motivados pela avaliação do projeto contra o padrão LLM Wiki (Andrej Karpathy), a pedido de Fabrício: `CLAUDE.md` (raiz do repositório) é o "schema" — convenções operacionais para qualquer agente de IA, antes existentes apenas em memória de sessão privada, agora versionadas e portáveis. `docs/INDEX.md` é o catálogo único de toda a documentação, um resumo de uma linha por documento. `docs/log.md` é o log cronológico enxuto (formato `## [AAAA-MM-DD] tipo | resumo`), complementar às tabelas de Revision History de cada documento, não substituto delas. Ver `CLAUDE.md` para o detalhe operacional completo — não duplicado aqui.

**`05-modelo-de-dados.md` dividido em `05a`–`05e` (2026-08-06).** O documento único ultrapassou 700 KB, acima do que ferramentas de leitura de agentes de IA processam em uma chamada. Dividido por área de domínio (catálogo base, cartas/raridade, assets/importação, coleções/usuários, catálogo editorial); `05-modelo-de-dados.md` passou a ser o índice e a metodologia comum (Purpose, Roteiro por Entidade), preservando o histórico de revisão anterior à divisão. Referências genéricas a `05-modelo-de-dados.md` em outros documentos continuam válidas (o arquivo existe e aponta para a página certa); não foram reescritas uma a uma.

**`ROADMAP.md` — criado (2026-07-24).** Consolida, pela primeira vez, a trajetória macro do projeto (concluído/em andamento/direção futura ainda não comprometida) em uma única fonte de verdade, resolvendo a fragmentação de múltiplas propostas de roadmap não reconciliadas ao longo do projeto (ver `06-pipeline-importacao.md`, revisão `1.4`). Não segue a numeração sequencial `00`-`07` por ser um artefato de natureza diferente (trajetória, não arquitetura/modelo), mesmo padrão de `README.md`.

**`ADR-INDEX.md`/`STD-INDEX.md` — mudança de regra de manutenção (2026-07-24).** Desde o início do projeto, esses dois índices eram deliberadamente mantidos desatualizados por decisão de Fabrício, até o encerramento da fase de documentação (ver `docs/README.md`, "Retomando este Projeto"). Fabrício declarou nesta data que a documentação do passado do projeto está encerrada — tudo que for documentado a partir de agora é sobre novas atualizações — e que, portanto, é o momento correto de reativar a manutenção contínua desses índices, conforme suas próprias "Maintenance Rules" já previam desde a criação de cada um. Ambos foram atualizados para refletir o estado real (`ADR-INDEX.md` revisão `2.0`, todos os 18 ADRs; `STD-INDEX.md` revisão `2.0`, `STD-001`/`002`/`003`) e devem ser atualizados a cada novo ADR/Standard ou mudança de status, a partir de agora.

**`08-decisoes-arquiteturais.md` — removido (2026-07-24).** Era um stub (apenas o título "Decisões Arquiteturais") desde sua criação, sem escopo definido em nenhuma das dezenas de ciclos de documentação já concluídos; seu propósito aparente já era integralmente coberto por `adr/` (um ADR por decisão, catalogado em `ADR-INDEX.md`), tornando-o redundante. Recomendado para remoção nesta mesma auditoria e confirmado excluído por Fabrício em seguida — não consta mais na árvore acima nem no repositório.

**Pastas órfãs — todas as quatro removidas (2026-07-24, encerra a nota das revisões `1.5`-`1.9`)**: `docs/pipelines/`, `docs/editorial/`, `docs/sprint/` e `docs/glossary/`, cada uma contendo apenas um `.gitkeep`, sem propósito identificável e redundantes com `operations/`/`history/`/`architecture/ubiquitous-language.md`, foram todas recomendadas para remoção e confirmadas excluídas por Fabrício — verificado por inspeção direta do repositório, nenhuma das quatro existe mais. O arquivo solto `_delete_test_dummy.txt`, encontrado na raiz do repositório durante a auditoria de `1.6`, também foi confirmado excluído. Este item está encerrado; nenhuma pasta órfã pendente no momento.

---

# Artifact Responsibilities

| Artefato | Responsabilidade |
|----------|------------------|
| `CLAUDE.md` (raiz) | Schema do agente — como qualquer LLM deve operar neste repositório (fluxo por ciclo, pareamento de SQL, estilo de histórico, ambiente). Não é sobre o que está documentado, é sobre como documentar e trabalhar. |
| `README.md` | Ponto de entrada e navegação da documentação. |
| `docs/INDEX.md` | Catálogo único de toda a documentação — uma linha por documento, para orientação rápida de uma sessão nova. |
| `docs/log.md` | Log cronológico enxuto de eventos do projeto — complementar à Revision History de cada documento, não substituto. |
| Project Charter | Define missão, visão, princípios estratégicos e critérios de sucesso. |
| Technical Identity | Consolida a identidade técnica vigente da plataforma. |
| Architecture Principles | Define princípios permanentes para decisões arquiteturais. |
| ADR | Registra por que uma decisão arquitetural relevante foi tomada. |
| Standard | Define como um padrão permanente deve ser aplicado. |
| Architecture | Documenta componentes, modelos, relacionamentos, integrações, fluxos e diagramas da solução. |
| Operations | Guia operacional passo a passo de como executar um processo já implementado (ex.: como importar uma nova coleção). Não contém racional de arquitetura nem histórico — apenas os passos, na ordem, prontos para seguir. |
| History | Diário histórico de como uma parte do sistema chegou ao seu estado atual — tentativas, bugs reais, propostas descartadas, evolução sprint a sprint. Não é atualizado com novas decisões (isso vai no documento de arquitetura correspondente) nem com passo a passo de uso (isso vai em Operations). Existe para preservar rastreabilidade sem sobrecarregar os documentos de leitura frequente. |
| Development | Documentos temporais de continuidade operacional entre sessões de desenvolvimento (handoffs), contendo estado executado, arquivos alterados, validações, pendências imediatas e checklist de retomada. Operacional, não normativo — não substitui `README.md`, `ROADMAP.md`, ADR, Standard, Architecture, Operations ou History; nenhuma decisão permanente deve residir apenas aqui. Apenas um handoff vigente por vez; handoffs anteriores são movidos para `history/development/`. Ver ciclo de vida completo na nota acima. |
| `database/` (fora de `docs/`) | Registro versionado e canônico dos scripts SQL do projeto (estrutura, migrations, seeds, validações) — cópia fiel do que está documentado em prosa em `05-modelo-de-dados.md`. A execução pode ocorrer diretamente pelo ambiente de desenvolvimento autorizado (hoje, Claude Code integrado ao Supabase via MCP) ou, excepcionalmente, pelo SQL Editor — em ambos os casos, todo script executado deve ser versionado, validado e documentado no mesmo ciclo (ver STD-001, Seção 10, e `database/README.md`). Esta responsabilidade é sobre o registro e a disciplina de versionamento, não sobre qual ferramenta executa o script. |

---

# Architecture Decision Records

Um ADR deve ser criado quando uma decisão:

- possuir impacto arquitetural relevante;
- definir ou alterar uma tecnologia, estrutura ou estratégia;
- envolver alternativas significativas;
- exigir preservação de contexto e justificativa.

Cada ADR deve registrar:

- status;
- contexto;
- decisão;
- justificativa;
- consequências;
- alternativas consideradas, quando aplicável.

A numeração dos ADRs é sequencial e permanente. Um número não deve ser reutilizado, mesmo que o ADR seja substituído ou rejeitado.

Todos os ADRs devem ser catalogados em `adr/ADR-INDEX.md`.

---

# Standards

Um Standard deve ser criado quando uma regra:

- for permanente ou recorrente;
- orientar implementação, nomenclatura ou documentação;
- precisar ser aplicada de forma consistente;
- puder ser verificada durante desenvolvimento ou revisão.

Standards podem ser atualizados quando o padrão evoluir. Alterações relevantes devem ser registradas no histórico de revisão.

Todos os Standards devem ser catalogados em `standards/STD-INDEX.md`.

---

# Architecture Documentation

A pasta `architecture/` deve conter representações do funcionamento e da estrutura da solução, incluindo:

- visão de contexto;
- modelo lógico;
- modelo físico;
- componentes;
- integrações;
- fluxos;
- diagramas.

Decisões e padrões não devem ser duplicados nessa pasta. Quando necessário, os documentos arquiteturais devem referenciar os ADRs e Standards correspondentes.

---

# Documentation Status

Os documentos podem utilizar os seguintes status:

| Status | Significado |
|--------|-------------|
| Proposto | Documento em avaliação e ainda não vigente. |
| Aprovado | Documento vigente e aplicável ao projeto. |
| Substituído | Documento sucedido por outro artefato oficial. |
| Rejeitado | Proposta avaliada e não adotada. |
| Obsoleto | Documento não mais aplicável e sem substituição direta. |

---

# Maintenance Rules

## New Architectural Decision

1. Criar o ADR correspondente.
2. Atualizar `adr/ADR-INDEX.md`.
3. Atualizar documentos relacionados, quando necessário.

## New or Updated Standard

1. Criar ou atualizar o Standard correspondente.
2. Atualizar `standards/STD-INDEX.md`.
3. Atualizar documentos relacionados, quando necessário.

## Architecture Change

1. Atualizar a documentação arquitetural afetada.
2. Criar ou revisar o ADR que justifica a mudança, quando aplicável.
3. Criar ou revisar os Standards decorrentes, quando aplicável.

## General Rules

- Não duplicar conteúdo entre artefatos.
- Utilizar links relativos para navegação interna.
- Atualizar a documentação no mesmo ciclo da mudança correspondente.
- Preservar o histórico de decisões substituídas.
- Não criar artefatos sem responsabilidade definida.

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Criação da arquitetura oficial da documentação. |
| 1.1 | Atualização da árvore de estrutura documental para refletir os arquivos `04-domain-model.md` a `08-decisoes-arquiteturais.md` já existentes no repositório. |
| 1.2 | Atualizada a nota de status: `06-pipeline-importacao.md` e `07-catalogo-editorial.md` deixaram de ser stubs e já possuem conteúdo em elaboração. |
| 1.3 | Atualizada a nota de status: `05-modelo-de-dados.md` deixou de ser stub e já possui conteúdo em elaboração (primeira entidade, Game, com modelo lógico e físico completos). |
| 1.4 | Adicionada a pasta `database/` (fora de `docs/`) à tabela de Artifact Responsibilities: registro versionado, em `.sql`, das Queries já executadas no Supabase — não fazia parte da arquitetura documental antes, embora já existisse no repositório. |
| 1.5 | **Formalizados dois novos tipos de artefato**: `operations/` (guia operacional passo a passo, sem racional de arquitetura nem histórico) e `history/` (diário histórico de tentativas/bugs/evolução sprint a sprint, sem novas decisões). Motivados pela divisão real de `06-pipeline-importacao.md` em três documentos, a pedido explícito de Fabrício, para reduzir o tamanho do documento de arquitetura. Árvore de estrutura atualizada. Registrada a existência de três pastas órfãs em `docs/` (`pipelines/`, `sprint/`, `editorial/`, vazias, nunca documentadas), não reaproveitadas por decisão de Fabrício — removê-las ou definir seu propósito real fica pendente. |
| 1.6 | **Auditoria de qualidade documental conduzida por Fabrício (2026-07-24)**, confirmada por inspeção real do repositório. Resolvidas duas pendências abertas desde a revisão `1.5`: (a) as três pastas órfãs (`docs/pipelines/`, `docs/sprint/`, `docs/editorial/`) não têm propósito identificável e são redundantes com `operations/`/`history/` — recomendação registrada de remoção manual por Fabrício (Claude não consegue apagar arquivos neste ambiente); (b) `08-decisoes-arquiteturais.md`, stub sem escopo definido desde a criação, identificado como redundante com `adr/` — mesma recomendação de remoção manual. Também sinalizado, na mesma auditoria, o arquivo solto `_delete_test_dummy.txt` na raiz do repositório, para remoção manual. |
| 1.7 | **Exclusões da revisão `1.6` confirmadas por Fabrício e verificadas por inspeção real do repositório**: `docs/08-decisoes-arquiteturais.md`, `docs/pipelines/`, `docs/editorial/` e `_delete_test_dummy.txt` não existem mais — removidos da árvore de estrutura e das notas, que agora registram a exclusão como fato consumado, não mais como recomendação. `docs/08-decisoes-arquiteturais.md` também removido da árvore. **Achado nesta verificação, não coberto pela exclusão anterior**: `docs/sprint/` ainda existe no repositório (confirmado por inspeção direta) — a mesma recomendação de remoção permanece válida e pendente para essa pasta especificamente. |
| 1.8 | **Auditoria documental completa (2026-07-24), a pedido explícito de Fabrício, antes de retomar o desenvolvimento.** Achado nesta rodada: `docs/glossary/` — quarta pasta órfã do mesmo perfil das já identificadas (apenas `.gitkeep`, criada em 2026-07-21, nunca referenciada em nenhum documento nem incluída na árvore de estrutura), passou despercebida nas auditorias anteriores porque a varredura de `1.5` não a havia detectado. Adicionada à nota de pastas órfãs, com a mesma recomendação de remoção manual. Nenhuma outra inconsistência estrutural encontrada nesta auditoria (verificação cruzada de contagens 859/927/1.555/1.653 em todos os documentos, status de ADRs, links internos e conteúdo de `04-domain-model.md`/`07-catalogo-editorial.md`/`architecture/`/`database/README.md`). |
| 1.9 | **Segunda auditoria (2026-07-24), conduzida por Fabrício sobre o resultado da revisão `1.8`.** `docs/ROADMAP.md` criado e adicionado à árvore de estrutura — primeira fonte única de verdade da trajetória do projeto. **Mudança de regra de manutenção**: `ADR-INDEX.md`/`STD-INDEX.md`, antes deliberadamente congelados até o fim da fase de documentação, passam a ser mantidos ativamente a partir de agora, por decisão explícita de Fabrício — a documentação do passado do projeto está encerrada. Ambos atualizados para refletir o estado real (ver nota própria, acima). `docs/sprint/`/`docs/glossary/` seguem pendentes de remoção manual — nenhuma pasta nova encontrada nesta rodada. |
| 1.10 | **Exclusão de `docs/sprint/` e `docs/glossary/` confirmada por Fabrício (2026-07-24) e verificada por inspeção direta do repositório — nenhuma das quatro pastas órfãs identificadas ao longo do projeto (`pipelines/`, `editorial/`, `sprint/`, `glossary/`) existe mais.** Nota de "Pastas órfãs" reescrita de recomendação pendente para fato consumado, mesmo padrão já usado para `pipelines/`/`editorial/` na revisão `1.7`. Este item está encerrado. |
| 1.12 | **Adequação ao padrão LLM Wiki (2026-08-06)**: três artefatos novos (`CLAUDE.md`, `docs/INDEX.md`, `docs/log.md`) e divisão de `05-modelo-de-dados.md` em `05a`–`05e` por área de domínio. Árvore de estrutura, tabela de Artifact Responsibilities e notas atualizadas — ver notas próprias, acima. |
| 1.11 | **Formalizado o tipo de artefato `development/` (2026-07-26), motivado por auditoria externa conduzida por Fabrício**: `docs/development/HANDOFF-2026-07-26.md` havia sido criado numa sessão anterior sem que a árvore documental o previsse, contrariando a regra "não criar artefatos sem responsabilidade definida". Adicionado à árvore de estrutura (junto com `history/development/`, destino dos handoffs superados); nova linha "Development" na tabela de Artifact Responsibilities; nova nota "Ciclo de vida dos handoffs" — um vigente por vez, decisões permanentes nunca residem só nele, `README.md` aponta para o vigente. **Corrigida também a responsabilidade de `database/`**, que ainda afirmava execução exclusivamente manual via SQL Editor — desatualizada frente ao fluxo real consolidado no projeto (Claude Code executando e validando Queries diretamente no Supabase via MCP, ver `development/HANDOFF-2026-07-26.md`); reescrita para descrever `database/` como o registro versionado e canônico dos scripts, neutro quanto à ferramenta de execução. |
