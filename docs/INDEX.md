# Índice da Documentação

| Campo | Valor |
|--------|-------|
| **Documento** | Índice |
| **Arquivo** | `docs/INDEX.md` |
| **Versão** | 1.0 |
| **Status** | Aprovado |
| **Objetivo** | Catálogo único de tudo que existe na documentação do projeto — um resumo de uma linha por documento, para orientar uma sessão nova sem precisar ler cada arquivo. |
| **Manutenção** | Atualizar sempre que um documento for criado, removido ou tiver título/resumo alterado de forma relevante (mesma disciplina de `adr/ADR-INDEX.md`/`standards/STD-INDEX.md`). |

Leia primeiro `CLAUDE.md` (raiz do repositório). Este índice é o segundo passo.

---

## Núcleo

| Documento | Resumo |
|---|---|
| [`README.md`](README.md) | Ponto de entrada, navegação e status atual do projeto (fase vigente, handoff em uso). |
| [`ROADMAP.md`](ROADMAP.md) | Trajetória macro do projeto — concluído, em andamento, direção futura ainda não comprometida. |
| [`log.md`](log.md) | Log cronológico enxuto de tudo que acontece no projeto (uma linha por evento). |
| [`00-project-charter.md`](00-project-charter.md) | Missão, visão, princípios estratégicos e critérios de sucesso. |
| [`01-technical-identity.md`](01-technical-identity.md) | Identidade técnica vigente da plataforma (stack, infraestrutura). |
| [`02-architecture-principles.md`](02-architecture-principles.md) | Princípios permanentes para decisões arquiteturais. |
| [`03-documentation-architecture.md`](03-documentation-architecture.md) | Organização, responsabilidades e governança da documentação — o que cada artefato pode e não pode conter. |
| [`04-domain-model.md`](04-domain-model.md) | Modelo de domínio conceitual — entidades, relacionamentos e regras de negócio, sem SQL. |
| [`05-modelo-de-dados.md`](05-modelo-de-dados.md) | Índice de redirecionamento para o modelo físico/SQL, dividido por área — ver seção "Modelo de Dados (físico)" abaixo. |
| [`06-pipeline-importacao.md`](06-pipeline-importacao.md) | Estratégia e arquitetura final do pipeline de importação de cartas e imagens. |
| [`07-catalogo-editorial.md`](07-catalogo-editorial.md) | Fluxo de ingestão administrativa do catálogo (ADR-024) — resumo e pendências. |

## Modelo de Dados (físico)

Ver `05-modelo-de-dados.md` para o mapa completo de divisão por área (histórico de física/SQL de cada bloco do domínio).

## Architecture Decision Records

Catálogo completo com status em [`adr/ADR-INDEX.md`](adr/ADR-INDEX.md). Lista rápida:

| ADR | Resumo |
|---|---|
| [ADR-001](adr/ADR-001-environment-foundation.md) | Fundação de ambiente (Supabase + Next.js). |
| [ADR-002](adr/ADR-002-infrastructure-region.md) | Região de infraestrutura. |
| [ADR-003](adr/ADR-003-multi-game-architecture.md) | Arquitetura multi-jogo (não só Pokémon TCG). |
| [ADR-004](adr/ADR-004-set-identity.md) | Identidade de Card Set. |
| [ADR-005](adr/ADR-005-catalog-language-model.md) | Modelo de idioma do catálogo. |
| [ADR-006](adr/ADR-006-separation-of-catalog-ownership-and-analytics.md) | Separação entre propriedade do catálogo e analytics. |
| [ADR-007](adr/ADR-007-card-translation-model.md) | Modelo de tradução de cartas. |
| [ADR-008](adr/ADR-008-external-catalog-data-sources.md) | Fontes externas de dados de catálogo (hoje só TCGdex; multi-provider em aberto). |
| [ADR-009](adr/ADR-009-card-variant-scope.md) | Escopo de variantes de carta. |
| [ADR-010](adr/ADR-010-card-rarity-and-finish-model.md) | Modelo de raridade e acabamento (finish) de carta. |
| [ADR-011](adr/ADR-011-pokemon-tcg-domain-scope.md) | Escopo de domínio do Pokémon TCG. |
| [ADR-012](adr/ADR-012-structured-vs-visual-card-data.md) | Dado estruturado vs. dado visual da carta. |
| [ADR-013](adr/ADR-013-collection-item-identity-model.md) | Identidade de item de coleção. |
| [ADR-014](adr/ADR-014-collection-and-collection-entry-model.md) | Modelo de Coleção e entrada de coleção. |
| [ADR-015](adr/ADR-015-promotional-card-set-model.md) | Modelo de Card Set promocional. |
| [ADR-016](adr/ADR-016-card-variant-naming-convention.md) | Convenção de nomenclatura de variante de carta. |
| [ADR-017](adr/ADR-017-two-function-import-pipeline.md) | Pipeline de importação em duas funções (substituído por ADR-018). |
| [ADR-018](adr/ADR-018-single-function-import-pipeline.md) | Pipeline de importação em função única. |
| [ADR-019](adr/ADR-019-web-application-as-primary-interface.md) | Aplicação web como interface primária. |
| [ADR-020](adr/ADR-020-user-profile-and-username-identity-model.md) | Modelo de perfil de usuário e identidade de username. |
| [ADR-021](adr/ADR-021-administrative-role-model.md) | Modelo de papel administrativo. |
| [ADR-022](adr/ADR-022-catalog-editorial-admin-only-access.md) | Acesso ao catálogo editorial restrito a administradores. |
| [ADR-023](adr/ADR-023-catalog-editorial-write-authorization.md) | Autorização de escrita administrativa no catálogo editorial (Game/Expansion/Card Set completos; Card com atualização via UI, cadastro/desativação pendentes). |
| [ADR-024](adr/ADR-024-catalog-card-ingestion-strategy.md) | Estratégia de ingestão administrativa de cartas (Ciclo 1 e 2 via TCGdex — Ciclo 2 sem fechamento formal). |
| [ADR-025](adr/ADR-025-energy-as-catalog-card-category.md) | Energia como categoria de carta no catálogo. |

## Standards

Catálogo completo com status em [`standards/STD-INDEX.md`](standards/STD-INDEX.md). Lista rápida:

| Standard | Resumo |
|---|---|
| [STD-001](standards/STD-001-database-standards.md) | Padrões de banco de dados — nomenclatura, numeração de Query, padrão de pareamento SQL. |
| [STD-002](standards/STD-002-domain-modeling.md) | Padrões de modelagem de domínio. |
| [STD-003](standards/STD-003-documentation-conventions.md) | Convenções de escrita e formatação da documentação. |
| [STD-004](standards/STD-004-frontend-standards.md) | Padrões de frontend. |

## Architecture

| Documento | Resumo |
|---|---|
| [`architecture/README.md`](architecture/README.md) | Visão geral da pasta de documentação arquitetural. |
| [`architecture/ubiquitous-language.md`](architecture/ubiquitous-language.md) | Glossário de linguagem ubíqua do domínio. |

## Operations

| Documento | Resumo |
|---|---|
| [`operations/import-card-assets.md`](operations/import-card-assets.md) | Guia operacional passo a passo da importação manual de imagens de carta. |

## History

| Documento | Resumo |
|---|---|
| [`history/pipeline-sprint-log.md`](history/pipeline-sprint-log.md) | Diário histórico da evolução sprint a sprint do pipeline de importação. |
| [`history/development/HANDOFF-2026-07-26.md`](history/development/HANDOFF-2026-07-26.md) | Handoff superado (26/07). |
| [`history/development/HANDOFF-2026-07-31.md`](history/development/HANDOFF-2026-07-31.md) | Handoff superado (31/07). |

## Development (handoff vigente)

| Documento | Resumo |
|---|---|
| [`development/HANDOFF-2026-08-02.md`](development/HANDOFF-2026-08-02.md) | Handoff vigente — estado real do projeto, pendências imediatas, checklist de retomada. |

---

## Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Criação deste documento (2026-08-06), como parte da adequação do projeto ao padrão LLM Wiki. |
