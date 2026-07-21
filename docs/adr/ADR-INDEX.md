# ADR Index

| Campo | Valor |
|--------|-------|
| **Documento** | ADR Index |
| **Arquivo** | `docs/adr/ADR-INDEX.md` |
| **Versão** | 1.0 |
| **Status** | Aprovado |
| **Objetivo** | Catalogar todas as Architectural Decision Records (ADRs) do Project Mimikyu. |
| **Escopo** | Índice central das decisões arquiteturais do projeto. |
| **Dependências** | `00-project-charter.md`, `01-technical-identity.md` |
| **Documentos Relacionados** | Todos os documentos da pasta `docs/adr/` |

---

# Overview

Este documento centraliza todas as Architectural Decision Records (ADRs) do Project Mimikyu.

Cada ADR registra uma decisão arquitetural relevante tomada durante a evolução da plataforma, incluindo seu contexto, decisão, justificativa e consequências.

Sempre que um novo ADR for criado, este índice deverá ser atualizado na mesma alteração.

---

# ADR Catalog

| ADR | Título | Categoria | Versão | Status |
|-----|--------|-----------|:------:|:------:|
| [ADR-001](ADR-001-environment-foundation.md) | Environment Foundation | Infrastructure | 1.0 | ✅ Accepted |
| [ADR-002](ADR-002-infrastructure-region.md) | Infrastructure Region | Infrastructure | 1.0 | ✅ Accepted |

---

# Status Legend

| Status | Descrição |
|--------|-----------|
| ⏳ Planned | ADR identificado, mas ainda não elaborado. |
| 🚧 In Progress | ADR em elaboração ou avaliação. |
| ✅ Accepted | ADR aprovado, implementado e vigente. |
| 🔄 Superseded | ADR substituído por uma decisão posterior. |
| ❌ Deprecated | ADR obsoleto e não mais aplicável. |
| ⛔ Rejected | Alternativa formalmente avaliada e rejeitada. |

---

# Maintenance Rules

- Cada ADR deve possuir um identificador único e sequencial.
- A numeração de um ADR nunca deve ser reutilizada.
- O nome do arquivo deve seguir o padrão `ADR-NNN-descriptive-title.md`.
- O título apresentado neste índice deve corresponder ao título oficial do ADR.
- Todo ADR deve ser incluído neste índice no mesmo commit em que for criado.
- ADRs substituídos ou obsoletos devem permanecer disponíveis para preservação do histórico arquitetural.
- Um ADR com status **Superseded** deve indicar claramente qual decisão o substituiu.
- Apenas decisões efetivamente identificadas devem ser incluídas no catálogo.
- Este documento é a referência oficial para localização das decisões arquiteturais do Project Mimikyu.

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Criação inicial do índice oficial de ADRs. |