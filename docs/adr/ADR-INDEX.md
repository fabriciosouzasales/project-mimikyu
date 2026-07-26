# Architecture Decision Records Index

| Campo | Valor |
|--------|-------|
| **Documento** | Architecture Decision Records Index |
| **Arquivo** | `docs/adr/ADR-INDEX.md` |
| **Versão** | 2.5 |
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
| [ADR-019](ADR-019-web-application-as-primary-interface.md) | Web Application as the Primary User Interface | Aprovado |
| [ADR-020](ADR-020-user-profile-and-username-identity-model.md) | User Profile and Username Identity Model | Aprovado |
| [ADR-021](ADR-021-administrative-role-model.md) | Administrative Role Model | Aprovado |
| [ADR-022](ADR-022-catalog-editorial-admin-only-access.md) | Catalog Editorial Admin-Only Access | Aprovado |
| [ADR-023](ADR-023-catalog-editorial-write-authorization.md) | Catalog Editorial Write Authorization | Aprovado |
| [ADR-024](ADR-024-catalog-card-ingestion-strategy.md) | Catalog Card Ingestion Strategy | Aprovado |

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
| 2.1 | Adicionado `ADR-019` (Web Application as the Primary User Interface, 2026-07-25) — decisão de Fabrício de adotar aplicação web própria (React/Next.js) como interface principal do produto, descartando Power Apps/SharePoint/Power BI da arquitetura-alvo, motivada pela proposta de iniciar o front-end pelo Catálogo Editorial e pelo esclarecimento do objetivo comercial multiusuário do produto. |
| 2.2 | Adicionado `ADR-020` (User Profile and Username Identity Model, 2026-07-25) — `user_profile` separado de `auth.users`, contendo apenas dados básicos de perfil (username público/único/estável, display_name editável, avatar); papéis/permissões/preferências ficam fora do escopo desta decisão. Complementa ADR-019, que já havia identificado `user_profile` como modelagem pendente. |
| 2.3 | Adicionado `ADR-021` (Administrative Role Model, 2026-07-26) — papel administrativo modelado como tabela dedicada (`admin_user`), sem política de RLS, distinta de `user_profile`; um único papel, sem RBAC genérico; funções `SECURITY DEFINER` que verificam somente o próprio chamador; auditoria (`admin_action_log`) com FKs anuláveis, sobrevivendo à exclusão de usuários. Resolve a pendência de modelagem de papéis deixada em aberto por ADR-020. |
| 2.4 | Adicionado `ADR-022` (Catalog Editorial Admin-Only Access, 2026-07-26) — todo o módulo Catálogo Editorial (menu, rota e dado) restrito a administradores; leitura liberada tabela a tabela via RLS `is_admin()` apenas onde uma tela real consulta; escrita administrativa sempre por função `SECURITY DEFINER` específica, nunca política de `UPDATE` ampla; migrations de controle de acesso numeradas na faixa de evolução (`200`–`299`). Motivado pela retomada da concepção da tela Visão Geral e pela descoberta de que as 17 tabelas do Catálogo Editorial já estavam de fato fechadas (RLS sem política), tornando essa realidade uma decisão explícita. |
| 2.5 | Adicionados `ADR-023` (Catalog Editorial Write Authorization, 2026-07-26) e `ADR-024` (Catalog Card Ingestion Strategy, 2026-07-26). `ADR-023` formaliza a escrita administrativa de `game`/`expansion`/`card_set`/`card` por função `SECURITY DEFINER`, com a lógica de persistência isolada num schema interno (`internal`) não exposto pela API, `EXECUTE` revogado de `PUBLIC`/`anon`/`authenticated`; define `is_active` em `card` como soft delete real e irrestrito; protege `card_set_id`/`collector_number` contra alteração administrativa; cria auditoria editorial própria, separada de `admin_action_log`. `ADR-024` formaliza os três canais de entrada de Cards (individual, PDF, TCGdex) convergindo para a camada interna de `ADR-023` via staging (`catalog_import_job`/`catalog_import_row`), com quatro estados independentes por linha e oito estados de job; registra o Princípio da Fonte Canônica (o banco é a única autoridade sobre dados editoriais, fontes externas fornecem apenas propostas sujeitas a validação administrativa); separa arquitetura (o contrato `fonte → processador → linhas de staging`) de implementação (a tecnologia concreta de cada processador — TCGdex tem uma escolha inicial, PDF pendente de prova técnica); corrige a semântica transacional da confirmação em lote (isolamento de erro por linha não é durabilidade independente por linha). Motivados pela retomada do desenvolvimento do módulo Catálogo Editorial e pela ausência histórica de qualquer via de escrita controlada para Cards. |
