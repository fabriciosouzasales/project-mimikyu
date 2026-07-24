# Documentation Architecture

| Campo | Valor |
|--------|-------|
| **Documento** | Documentation Architecture |
| **Arquivo** | `docs/03-documentation-architecture.md` |
| **Versão** | 1.5 |
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
docs/
├── README.md
├── 00-project-charter.md
├── 01-technical-identity.md
├── 02-architecture-principles.md
├── 03-documentation-architecture.md
├── 04-domain-model.md
├── 05-modelo-de-dados.md
├── 06-pipeline-importacao.md
├── 07-catalogo-editorial.md
├── 08-decisoes-arquiteturais.md     (stub — conteúdo pendente)
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
└── history/
    └── <artefato>.md
```

Os documentos `04` a `08` seguem a mesma numeração sequencial dos documentos centrais (`00`-`03`). `04-domain-model.md`, `05-modelo-de-dados.md`, `06-pipeline-importacao.md` e `07-catalogo-editorial.md` já possuem conteúdo em elaboração; `08` permanece stub (apenas título) cujo escopo definitivo será estabelecido durante a fase de consolidação documental.

**Pastas órfãs, encontradas mas não documentadas oficialmente (2026-07-24)**: `docs/pipelines/`, `docs/sprint/` e `docs/editorial/` existem no repositório, cada uma contendo apenas um `.gitkeep`, sem nenhum conteúdo e sem menção em nenhuma versão anterior deste documento. Não se sabe se foram criadas intencionalmente (scaffold para uma estrutura planejada e nunca implementada) ou são resíduo de uma tentativa abandonada. Fabrício optou por não reaproveitá-las ao criar `operations/`/`history/` (ver revisão `1.5`, abaixo) — decisão sobre removê-las ou dar a elas um propósito real fica pendente.

---

# Artifact Responsibilities

| Artefato | Responsabilidade |
|----------|------------------|
| `README.md` | Ponto de entrada e navegação da documentação. |
| Project Charter | Define missão, visão, princípios estratégicos e critérios de sucesso. |
| Technical Identity | Consolida a identidade técnica vigente da plataforma. |
| Architecture Principles | Define princípios permanentes para decisões arquiteturais. |
| ADR | Registra por que uma decisão arquitetural relevante foi tomada. |
| Standard | Define como um padrão permanente deve ser aplicado. |
| Architecture | Documenta componentes, modelos, relacionamentos, integrações, fluxos e diagramas da solução. |
| Operations | Guia operacional passo a passo de como executar um processo já implementado (ex.: como importar uma nova coleção). Não contém racional de arquitetura nem histórico — apenas os passos, na ordem, prontos para seguir. |
| History | Diário histórico de como uma parte do sistema chegou ao seu estado atual — tentativas, bugs reais, propostas descartadas, evolução sprint a sprint. Não é atualizado com novas decisões (isso vai no documento de arquitetura correspondente) nem com passo a passo de uso (isso vai em Operations). Existe para preservar rastreabilidade sem sobrecarregar os documentos de leitura frequente. |
| `database/` (fora de `docs/`) | Registro versionado, em arquivos `.sql`, das Queries já executadas no Supabase — cópia fiel do que está documentado em prosa em `05-modelo-de-dados.md`. Não é um executor de migrations; a execução real continua manual, via SQL Editor (ver STD-001, Seção 10, e `database/README.md`). |

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
