# Architecture Decision Records Index

| Campo | Valor |
|--------|-------|
| **Documento** | Architecture Decision Records Index |
| **Arquivo** | `docs/adr/ADR-INDEX.md` |
| **Versão** | 1.0 |
| **Status** | Aprovado |
| **Objetivo** | Catalogar os Architecture Decision Records do Project Mimikyu. |
| **Dependências** | `../03-documentation-architecture.md` |

---

# Overview

Este índice apresenta os ADRs oficiais do Project Mimikyu.

ADRs registram decisões arquiteturais relevantes e preservam seu contexto, justificativa e consequências.

---

# Catalog

| ADR | Título | Status |
|-----|--------|--------|
| [ADR-001](ADR-001-environment-foundation.md) | Environment Foundation | Aprovado |
| [ADR-002](ADR-002-infrastructure-region.md) | Infrastructure Region | Aprovado |

---

# Status Reference

| Status | Significado |
|--------|-------------|
| Proposto | Decisão em avaliação. |
| Aprovado | Decisão vigente. |
| Substituído | Decisão sucedida por outro ADR. |
| Rejeitado | Alternativa avaliada e não adotada. |
| Obsoleto | Decisão não mais aplicável e sem substituição direta. |

---

# Maintenance Rules

- Utilizar numeração sequencial no formato `ADR-NNN`.
- Não reutilizar números.
- Adotar nomes de arquivo no formato `ADR-NNN-title.md`.
- Atualizar este índice sempre que um ADR for criado ou tiver seu status alterado.
- Preservar ADRs substituídos, rejeitados ou obsoletos como histórico decisório.

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Criação inicial do índice de ADRs. |
