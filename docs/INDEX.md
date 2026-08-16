# Índice da Documentação

| Campo | Valor |
|--------|-------|
| **Documento** | Índice |
| **Arquivo** | `docs/INDEX.md` |
| **Versão** | 1.7 |
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
| [ADR-023](adr/ADR-023-catalog-editorial-write-authorization.md) | Autorização de escrita administrativa no catálogo editorial (Game/Expansion/Card Set completos; Card com ciclo vertical completo — create/update/deactivate/reactivate — via UI). |
| [ADR-024](adr/ADR-024-catalog-card-ingestion-strategy.md) | Estratégia de ingestão administrativa de cartas — Ciclo 1 e Ciclo 2 (TCGdex) CONFIRMADOS EXECUTADOS E VALIDADOS de ponta a ponta (validação `2818`, 8/8 itens); bug real de status corrigido (Query `2082` v1.1 + Migration `2118`); emenda de Raridade self-service e revalidação; multi-provider adiado (decisão de escopo); canal PDF (Ciclos 3/4) encerrado definitivamente (2026-08-08). |
| [ADR-025](adr/ADR-025-energy-as-catalog-card-category.md) | Energia como categoria de carta no catálogo. |
| [ADR-026](adr/ADR-026-manual-local-file-asset-import-channel.md) | Canal manual de importação de imagens via arquivo local (`scripts/import-manual-assets.ts`, `asset_source` `MANUAL`) quando a fonte externa não publica o asset — caso real `MEE`/`MEP`; conclusão de `MEP` priorizada à frente do Ciclo 3 de ADR-024. |
| [ADR-027](adr/ADR-027-catalog-editorial-canonical-metrics-views.md) | Views administrativas de métrica canônica do catálogo (`security_invoker = true`, GRANT restrito a `authenticated`) — padrão que estreia com `catalog_card_set_metrics`/`catalog_card_set_image_coverage` (Query `2123`) e será reutilizado pela futura Central de Relatórios. |
| [ADR-028](adr/ADR-028-card-variant-governance.md) | Card Variant como entidade mestre do Catálogo Editorial — criação/alteração/ativação exclusivas de administradores; usuário final só seleciona uma variante existente, nunca escreve em `card_variant`. Quatro revisões (`1.0`–`1.4`) cobrem resolução de mapeamento externo, governança soft de `card_variant_type` e UI administrativa. Bloco declarado fundação encerrada em 2026-08-16 (base necessária para Pricing e Collection) — ver `ROADMAP.md`, seção "Now". |

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
| [`history/development/HANDOFF-2026-08-02.md`](history/development/HANDOFF-2026-08-02.md) | Handoff superado (02/08). |
| [`history/development/HANDOFF-2026-08-08.md`](history/development/HANDOFF-2026-08-08.md) | Handoff superado (08/08). |
| [`history/development/HANDOFF-2026-08-09.md`](history/development/HANDOFF-2026-08-09.md) | Handoff superado (09/08). |

## Development (handoff vigente)

| Documento | Resumo |
|---|---|
| [`development/HANDOFF-2026-08-16.md`](development/HANDOFF-2026-08-16.md) | Handoff vigente — bloco Card Variant encerrado como fundação (governança, taxonomia, pipeline "Importar Variantes"), Auth Experience (Login V1 congelado, propagado), Design System consolidado como baseline, evoluções do Módulo Gerencial, correção do bug de paginação de impressão, sequência estratégica Card Variant → Pricing → Collection → Analytics aprovada, e as duas rodadas de auditoria documental de 2026-08-16 (a segunda reconstruiu `05b-cartas-e-raridade.md`). |

---

## Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Criação deste documento (2026-08-06), como parte da adequação do projeto ao padrão LLM Wiki. |
| 1.1 | Resumo de `ADR-024` atualizado (2026-08-08) para refletir o encerramento definitivo do canal PDF (Ciclos 3/4) — decisão explícita de Fabrício, ver `adr/ADR-024-catalog-card-ingestion-strategy.md` revisão `1.7`. |
| 1.2 | Handoff vigente atualizado para `development/HANDOFF-2026-08-08.md` (2026-08-08) — `HANDOFF-2026-08-02.md` estava significativamente desatualizado (não refletia o fechamento formal do Ciclo 2 de `ADR-024`, a conclusão de `ADR-023`, `ADR-026` nem o encerramento do canal PDF, todos ocorridos depois de 02/08); movido para `history/development/`. |
| 1.3 | Adicionado `ADR-027` (Catalog Editorial Canonical Metrics Views, 2026-08-08) — decisão de Fabrício de abrir ADR novo (não emendar `ADR-006`) para o padrão `security_invoker = true`/GRANT restrito, estreado pela Query `2123` da Sprint Gerencial 1. |
| 1.4 | Resumo do handoff vigente atualizado (2026-08-08) para refletir o encerramento formal do Catálogo Editorial (cinco frentes A–E concluídas) e o início do Módulo Gerencial (Sprint Gerencial 1) — ver `development/HANDOFF-2026-08-08.md` (amendado no mesmo dia) e `ROADMAP.md` revisão `1.22`. |
| 1.5 | Handoff vigente atualizado para `development/HANDOFF-2026-08-09.md` (2026-08-09) — consolida o encerramento formal do Módulo Gerencial (Trilha 4: Histórico de Importações, Log de Atualizações, Central de Relatórios, todos concluídos e aprovados por Fabrício nesta janela). `HANDOFF-2026-08-08.md` movido para `history/development/`. Ver `ROADMAP.md` revisão `1.45` e `docs/README.md` revisão `1.98`. |
| 1.6 | **Auditoria documental completa (2026-08-16).** Adicionado `ADR-028` (Card Variant Governance) à lista rápida de ADRs — ausente desde sua criação em 2026-08-14, apesar de já constar em `adr/ADR-INDEX.md` (revisão `2.16`). Handoff vigente atualizado para `development/HANDOFF-2026-08-16.md`; `HANDOFF-2026-08-09.md` movido para `history/development/`. Ver `ROADMAP.md` revisão `1.48` e `docs/README.md` revisão `2.00`. |
| 1.7 | **Segunda rodada de auditoria documental (2026-08-16, mesma data), achado de segunda ordem.** Resumos de `ADR-028` e do handoff vigente ainda diziam "substancialmente implementado e pausado" — desatualizados pela decisão formal de Fabrício (Card Variant = fundação encerrada) tomada na segunda rodada; ambos corrigidos. Ver `ROADMAP.md` revisão `1.49` e `docs/README.md` revisão `2.01`. |
