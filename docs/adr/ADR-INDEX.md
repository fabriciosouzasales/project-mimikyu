# Architecture Decision Records Index

| Campo | Valor |
|--------|-------|
| **Documento** | Architecture Decision Records Index |
| **Arquivo** | `docs/adr/ADR-INDEX.md` |
| **Versão** | 2.11 |
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
| [ADR-025](ADR-025-energy-as-catalog-card-category.md) | Energy as Catalog Card Category | Aprovado |

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
| 2.6 | **`ADR-023` emendado (v1.1) durante a implementação do ciclo vertical de `Game` (2026-07-26)**: `Game` ganha exclusão real via UI (`admin_delete_game()`, Queries `2041`/`2042`), substituindo a correção antes prevista "por SQL direta" — bloqueada pela `FK` existente quando há Expansions associadas. Distinta de desativação (`is_active`), que `Game` continua sem ter. Restrita a `Game`; `Expansion`/`Card Set` não afetados. |
| 2.7 | Adicionado `ADR-025` (Energy as Catalog Card Category, 2026-07-30) — resolve `OD-001` (`04-domain-model.md`) por decisão explícita e definitiva de Fabrício: cartas de Energia passam a ocupar posição oficial no Set e a fazer parte do catálogo editorial numerado, como Pokémon e Trainer; `Card Category` passa a ter três valores (`POKEMON`, `TRAINER`, `ENERGY`); esclarece que Energy Card (categoria da própria Card) e Energy Type (atributo elemental, mecânica de jogo, AP-017) são conceitos distintos. Substitui a antiga "Decisão de Escopo — Cartas de Energia" de `04-domain-model.md` (texto histórico preservado). Nenhuma alteração física no banco — a categoria `ENERGY` e os 17 Cards que a utilizam já existiam (Query `831`); o ADR formaliza documentalmente uma realidade já implementada. |
| 2.8 | **Duas emendas de `ADR-023` (2026-07-31), até então ausentes do histórico deste índice, registradas retroativamente ao serem descobertas durante reconciliação documental**: emenda v1.2 — `Expansion` ganha exclusão real via UI (`admin_delete_expansion()`, Queries `2043`/`2044`), mesmo padrão já usado por `Game` (revisão `2.6`), bloqueada pela `FK fk_card_set_expansion` quando há Card Sets associados; validação funcional (`2809`) confirmada por Fabrício pela própria interface. Emenda v1.3 — `Card Set` ganha atualização e exclusão real via UI (`admin_update_card_set()`/`admin_delete_card_set()`, Queries `2048`/`2049`/`2050`), primeira via de escrita estrutural dessa entidade além da logo; bloqueada pela `FK fk_card_card_set` quando há Cards associadas; validação estrutural (`2811`) confirmada, funcional ainda pendente. Ambas as emendas motivadas pelo pedido de Fabrício de levar Coleções ao mesmo padrão de Expansões. Nenhuma mudança de status do ADR (segue `Aprovado`) — apenas revisão de conteúdo. |
| 2.9 | **Três emendas adicionais de `ADR-023`, até então ausentes do histórico deste índice, registradas durante a auditoria de reconciliação documental de 2026-08-02**: emenda v1.4 (2026-07-31) — `Card Set` ganha cadastro real via UI (`admin_create_card_set()`, Query `2051`), fechando o ciclo vertical create+update+delete para `Game`/`Expansion`/`Card Set`; corrigida no mesmo dia (v1.1) para aceitar a categoria `ENERGY`; validação funcional (`2812`) confirmada por Fabrício pela própria tela. Emenda v1.5 (2026-07-31) — `admin_update_card_set()` ampliada para aceitar tipo (`set_type`) e data de lançamento (`release_date`), Query `2048` v2.0/Migration `2052`; validação funcional confirmada pela própria tela. Emenda v1.6 (2026-08-01) — `Card Set` ganha código editável condicional (Migration `2091`, incorporada à Query `2048` canônica v3.0): `code` passa a ser alterável só enquanto o Card Set não tiver nenhuma Card cadastrada, motivada por um erro real de cadastro (Coleção "151", código `SV4` corrigido para `MEW`); validação `2815` confirmada. Nenhuma mudança de status do ADR (segue `Aprovado`) — apenas revisão de conteúdo. Nenhuma alteração em `ADR-024`, `STD-INDEX.md` nem em nenhum ADR além de `ADR-023` nesta rodada. |
| 2.10 | **Duas emendas adicionais de `ADR-023` (2026-08-07), fechando o subciclo `Card`**: emenda v1.7 — `Card` ganha atualização real via UI (`admin_update_card()`, Query `2114`), primeira função pública a chamar `internal.write_card()` em modo `UPDATE`; `card_set_id`/`collector_number` protegidos, fora da assinatura; validada pela própria tela. Registrada retroativamente nesta rodada — mesma classe de gap já corrigida para a v1.6 (emenda já existia no corpo do ADR desde sua implementação, sem entrada na Revision History nem neste índice). Emenda v1.8 — `Card` ganha cadastro e desativação/reativação real via UI (`admin_create_card()`/`admin_deactivate_card()`/`admin_reactivate_card()`, Queries `2115`/`2116`/`2117`, validação `2817`), fechando o ciclo vertical create+update+deactivate+reactivate para `Card` — último item do escopo original deste ADR. Validação de consistência de Game entre Raridade/Categoria e Card Set antecipada como erro administrativo; duplicidade de número/ordem checada contra Cards ativas e inativas; auditoria única por operação confirmada. Descoberta real durante a validação: `GRANT EXECUTE ... TO authenticated` não revoga o `EXECUTE` implícito que `PUBLIC` recebe na criação de qualquer função — `anon` herdava acesso; corrigido com `REVOKE ALL ... FROM PUBLIC/anon` explícito nas três novas funções. Auditoria retroativa do mesmo gap nas demais funções `admin_*` do módulo (criadas antes desta rodada, nenhuma com `REVOKE` explícito) fica como item futuro separado, por decisão explícita de Fabrício. Nenhuma mudança de status do ADR (segue `Aprovado`). Nenhuma alteração em `ADR-024`, `STD-INDEX.md` nem em nenhum ADR além de `ADR-023` nesta rodada. |
| 2.11 | **`ADR-024` — fechamento documental do Ciclo 2 (fluxo TCGdex completo), 2026-08-07.** Nova seção "Ciclo 2 — Fluxo vertical completo via TCGdex" em `05e-catalogo-editorial.md`, consolidando o que estava disperso desde 2026-08-01 nas revisões `1.1`–`1.50` de `05-modelo-de-dados.md` (antes da divisão de 2026-08-06): processador (Edge Function `import-catalog-cards`, sem Query SQL própria — reaproveita `2080`–`2082` do Ciclo 1), módulo compartilhado `_shared/catalog-normalization/`, frontend (`/catalogo/importar-cartas`/`/catalogo/importar-imagens`), e a emenda de continuação automática cartas→imagens (`admin_start_asset_import_run()`, Query `2092` v1.0–v1.3, Migration `2093`). Nova validação `2818` (somente leitura, sobre dado real de produção — diferente da `2814` do Ciclo 1, que usou dado sintético porque na época nenhum processador existia ainda) escrita e apresentada a Fabrício, aguardando execução. Divergência real encontrada e sinalizada, não resolvida unilateralmente: o cabeçalho do arquivo canônico `2092` (v1.3) ainda diz "PROPOSTA — AGUARDANDO EXECUÇÃO", contradizendo a Revision History e o uso real em produção — a Query `2818` (item 1) resolve isso diretamente contra o banco. Também nesta rodada: decisão explícita de Fabrício de manter "multi-provider" (múltiplas fontes externas estruturadas) como implementação futura, fora do escopo desta sprint — registrada em `06-pipeline-importacao.md` revisão `1.7`, não em `ADR-008`/`ADR-024` (nenhuma das sub-decisões técnicas foi resolvida, só a pergunta de escopo/prioridade). Nenhuma mudança de status de nenhum ADR (ambos seguem `Aprovado`). |
