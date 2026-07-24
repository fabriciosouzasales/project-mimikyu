# Architecture Decision Records Index

| Campo | Valor |
|--------|-------|
| **Documento** | Architecture Decision Records Index |
| **Arquivo** | `docs/adr/ADR-INDEX.md` |
| **Versão** | 2.0 |
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
| [ADR-003](ADR-003-multi-game-architecture.md) | Multi-Game Architecture | Aprovado |
| [ADR-004](ADR-004-set-identity.md) | Set Identity | Aprovado |
| [ADR-005](ADR-005-catalog-language-model.md) | Catalog Language Model | Aprovado |
| [ADR-006](ADR-006-separation-of-catalog-ownership-and-analytics.md) | Separation of Catalog, Ownership and Analytics | Aprovado |
| [ADR-007](ADR-007-card-translation-model.md) | Card Translation Model | Aprovado |
| [ADR-008](ADR-008-external-catalog-data-sources.md) | External Catalog Data Sources | Aprovado |
| [ADR-009](ADR-009-card-variant-scope.md) | Card Variant Scope | Substituído (ver ADR-010) |
| [ADR-010](ADR-010-card-rarity-and-finish-model.md) | Card Rarity and Finish Model | Substituído parcialmente (ver ADR-016) |
| [ADR-011](ADR-011-pokemon-tcg-domain-scope.md) | Pokémon TCG Domain Scope | Aprovado |
| [ADR-012](ADR-012-structured-vs-visual-card-data.md) | Structured vs. Visual-Only Card Data | Aprovado |
| [ADR-013](ADR-013-collection-item-identity-model.md) | Collection Item Identity Model | Aprovado |
| [ADR-014](ADR-014-collection-and-collection-entry-model.md) | Collection and Collection Entry Model | Aprovado |
| [ADR-015](ADR-015-promotional-card-set-model.md) | Promotional Card Set Model (Black Star Promos) | Aprovado |
| [ADR-016](ADR-016-card-variant-naming-convention.md) | Card Variant Naming Convention | Aprovado |
| [ADR-017](ADR-017-two-function-import-pipeline.md) | Two-Function Import Pipeline (Catalog Discovery vs. Asset Import) | Substituído (ver ADR-018) |
| [ADR-018](ADR-018-single-function-import-pipeline.md) | Single-Function Import Pipeline | Aprovado |

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
| 2.0 | **Catálogo atualizado para refletir todos os 18 ADRs reais do repositório (2026-07-24), a pedido explícito de Fabrício.** Até esta revisão, o índice listava apenas `ADR-001`/`ADR-002` — desatualizado desde a criação de `ADR-003`, por decisão deliberada de Fabrício de manter os índices congelados até o encerramento da fase de documentação (ver `docs/README.md`, seção "Retomando este Projeto"). Fabrício declarou nesta data que a documentação do passado está encerrada e que agora é o momento correto de ativar a manutenção deste índice — a partir de agora, toda criação ou mudança de status de ADR deve atualizar este arquivo no mesmo ciclo, conforme a regra já definida em "Maintenance Rules", acima. Adicionados `ADR-003` a `ADR-018`, com status refletindo exatamente o campo `Status` de cada arquivo individual: `Aprovado` para 001-008, 011-016, 018; `Substituído (ver ADR-010)` para `ADR-009`; `Substituído parcialmente (ver ADR-016)` para `ADR-010`; `Substituído (ver ADR-018)` para `ADR-017`. |
