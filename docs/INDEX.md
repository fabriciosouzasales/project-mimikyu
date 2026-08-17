# Índice da Documentação

| Campo | Valor |
|--------|-------|
| **Documento** | Índice |
| **Arquivo** | `docs/INDEX.md` |
| **Versão** | 1.17 |
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

Ver `05-modelo-de-dados.md` para o mapa completo de divisão por área (histórico de física/SQL de cada bloco do domínio). Inclui [`05f-pricing.md`](05f-pricing.md) — modelo lógico e físico do domínio Pricing (`ADR-029`); **dez de dez entidades `CONFIRMADO EXECUTADO`** no Supabase (2026-08-16) — `pricing_source`, `card_condition`, `pricing_condition_mapping` (Incremento P1); `pricing_set_mapping`, `pricing_card_mapping` (Incremento P2); `pricing_sync_run`, `pricing_sync_run_call` (Incremento P3); `pricing_product` (Incremento P4); `pricing_fx_rate` (Incremento P5); `pricing_observation` (Incremento P6, identidade market-aware `UNIQUE NULLS NOT DISTINCT`) — todas vazias, fundação física completa, domínio ainda não operacional.

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
| [ADR-029](adr/ADR-029-pricing-domain-model.md) | Pricing como quarto domínio conceitual, independente de Catálogo/Ownership/Analytics — dez entidades próprias (`pricing_source` até `pricing_sync_run_call`, ver `05f-pricing.md`), nenhuma reaproveitando tabelas do Catálogo Editorial. "Valor Brasil" depende de evidência em `pricing_observation`, nunca só do default da fonte ou de conversão cambial. **Dez de dez entidades criadas no Supabase (Incrementos P1–P6, 2026-08-16)** — fundação física completa. **Incremento P7 (2026-08-17)**: `JUSTTCG` cadastrada em `pricing_source`, homologada para piloto técnico (produto/printing/condição/preço USD/histórico), não homologada para PT-BR/"Valor Brasil", `is_active = FALSE`. Domínio ainda não operacional (plano comercial contratado, condições semeadas, mappings reais, sincronização, PTAX, frontend e Analytics/Item Valuation seguem pendentes). |
| [ADR-030](adr/ADR-030-card-search-projection.md) | Pesquisa Global de Cartas — `public.search_cards()`/`public.search_card_filter_options()` (`SECURITY DEFINER STABLE`, módulo `4000`–`4999`) como único caminho de leitura para combobox do header + página `/pesquisa`, disponível a qualquer usuário autenticado sem ampliar o acesso direto ao Catálogo Editorial (`ADR-022` intacto). **CONFIRMADO EXECUTADO** (2026-08-17) — validado com `SET ROLE anon`/`authenticated` reais e `EXPLAIN` sobre 22.104 linhas sintéticas. |

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
| [`history/development/HANDOFF-2026-08-16.md`](history/development/HANDOFF-2026-08-16.md) | Handoff superado (16/08). |

## Development (handoff vigente)

| Documento | Resumo |
|---|---|
| [`development/HANDOFF-2026-08-17.md`](development/HANDOFF-2026-08-17.md) | Handoff vigente — Pesquisa Global de Cartas (`ADR-030`) **formalmente encerrada**: combobox no header, página `/pesquisa`, projeção segura `search_cards`/`search_card_filter_options`, validações de segurança/performance reais, quatro rodadas corretivas, validação local (UI/lint/build) aprovada por Fabrício, commit e push realizados; divergência pré-existente de rastreabilidade em `database/migrations/` permanece registrada como débito não bloqueante. |

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
| 1.8 | **Adicionados `05f-pricing.md` e `ADR-029` (2026-08-16, mesma data, ciclo seguinte)** — modelagem conceitual e lógica do domínio Pricing (dez entidades, quarto domínio independente de Catálogo/Ownership/Analytics), decorrente da sequência estratégica aprovada por Fabrício (Card Variant → Pricing → Collection → Analytics). Nenhuma tabela criada no Supabase; homologação de fonte externa (JustTCG) segue pendente em paralelo, sem bloquear a modelagem. Ver `ROADMAP.md` revisão equivalente e `docs/README.md` revisão equivalente. |
| 1.9 | **Incremento P1 — Fundação Física de Pricing (2026-08-16, mesma data, ciclo seguinte)** — resumo de `05f-pricing.md` atualizado: três entidades fundacionais `CONFIRMADO EXECUTADO` no Supabase. Ver `ROADMAP.md`/`docs/README.md` revisões equivalentes. |
| 1.10 | **Incremento P2 — Correspondência Externa de Pricing (2026-08-16, mesma data, ciclo seguinte)** — resumo de `05f-pricing.md` atualizado: `pricing_set_mapping`/`pricing_card_mapping` também `CONFIRMADO EXECUTADO` (ambas vazias); cinco de dez entidades do domínio agora implementadas. Ver `ROADMAP.md` revisão `1.52`, `docs/README.md` revisão `2.04` e `docs/log.md`, entrada `feature` de 2026-08-16. |
| 1.11 | **Incremento P3 — Auditoria Operacional de Sincronização (2026-08-16, mesma data, ciclo seguinte)** — resumo de `05f-pricing.md` atualizado: `pricing_sync_run`/`pricing_sync_run_call` também `CONFIRMADO EXECUTADO` (ambas vazias); sete de dez entidades do domínio agora implementadas. Ver `ROADMAP.md` revisão `1.53`, `docs/README.md` revisão `2.05` e `docs/log.md`, entrada `feature` de 2026-08-16. |
| 1.12 | **Incremento P4 — Produto Externo de Pricing (2026-08-16, mesma data, ciclo seguinte)** — resumo de `05f-pricing.md` atualizado: `pricing_product` também `CONFIRMADO EXECUTADO` (vazia); oito de dez entidades do domínio agora implementadas. Ver `ROADMAP.md` revisão `1.54`, `docs/README.md` revisão `2.06` e `docs/log.md`, entrada `feature` de 2026-08-16. |
| 1.13 | **Incremento P5 — Série Histórica de Taxas de Câmbio (2026-08-16, mesma data, ciclo seguinte)** — resumos de `05f-pricing.md` e `ADR-029` atualizados (este último corrigido de uma dessincronização de várias revisões, ainda referindo só o Incremento P1): `pricing_fx_rate` também `CONFIRMADO EXECUTADO` (vazia); nove de dez entidades do domínio agora implementadas, resta apenas `pricing_observation`. Ver `ROADMAP.md` revisão `1.55`, `docs/README.md` revisão `2.07` e `docs/log.md`, entrada `feature` de 2026-08-16. |
| 1.14 | **Incremento P6 — Observação Histórica de Preço (2026-08-16, mesma data, ciclo seguinte) — fundação física de Pricing concluída.** Resumos de `05f-pricing.md` e `ADR-029` atualizados: `pricing_observation` também `CONFIRMADO EXECUTADO` (vazia, identidade market-aware `UNIQUE NULLS NOT DISTINCT` corrigida); dez de dez entidades do domínio agora implementadas — zero entidades restantes propostas. Domínio ainda não operacional. Ver `ROADMAP.md` revisão `1.56`, `docs/README.md` revisão `2.08` e `docs/log.md`, entrada `feature` de 2026-08-16. |
| 1.15 | **Incremento Pesquisa Global de Cartas (2026-08-17) — `ADR-030` adicionado.** Handoff vigente atualizado para `development/HANDOFF-2026-08-17.md`; `HANDOFF-2026-08-16.md` movido para `history/development/`. Ver `ROADMAP.md` revisão `1.58` e `docs/README.md` revisão `2.09`. |
| 1.15 | **Adicionado `ADR-030` (Pesquisa Global de Cartas, 2026-08-17)** — projeção segura nova (`public.search_cards()`/`public.search_card_filter_options()`, módulo `4000`–`4999`) para combobox do header + página `/pesquisa`, disponível a qualquer usuário autenticado sem ampliar acesso direto ao Catálogo Editorial. CONFIRMADO EXECUTADO e validado com `SET ROLE` real. Ver `ROADMAP.md` revisão `1.58`, `docs/standards/STD-001-database-standards.md` revisão `1.27`, `docs/standards/STD-004-frontend-standards.md` revisão `1.4` e `docs/log.md`. |
| 1.16 | **Pesquisa Global de Cartas formalmente encerrada (2026-08-17, mesmo dia)** — resumo do handoff vigente atualizado: validação local (UI/lint/build) aprovada por Fabrício, commit e push das cinco commits do incremento (implementação original + quatro rodadas corretivas) já realizados. Ver `ROADMAP.md` revisão `1.60`, `docs/README.md` revisão `2.12` e `docs/log.md`. |
| 1.17 | **Incremento P7 — Homologação Condicionada da JustTCG executado (2026-08-17, ciclo seguinte).** Descrição de `ADR-029` atualizada: `JUSTTCG` cadastrada em `pricing_source` (Query `3700`), homologada para piloto técnico, `is_active = FALSE`, plano comercial pendente. Ver `docs/adr/ADR-029-pricing-domain-model.md` revisão `1.9`, `docs/05f-pricing.md` versão `1.9`, `ROADMAP.md` revisão `1.61`, `docs/README.md` revisão `2.13` e `docs/log.md`. |
