# Roadmap

| Campo | Valor |
|--------|-------|
| **Documento** | Roadmap |
| **Arquivo** | `docs/ROADMAP.md` |
| **Versão** | 1.14 |
| **Status** | Aprovado |
| **Objetivo** | Consolidar, em uma única fonte de verdade, a trajetória macro do Project Mimikyu — o que já foi concluído, o que está em andamento e o que é direção futura provável, mas ainda não comprometida. |
| **Escopo** | Marcos de alto nível (Fases/Sub-Fases/Blocos). Não substitui `docs/README.md` (estado atual detalhado), `05-modelo-de-dados.md` (execução física) nem `06-pipeline-importacao.md` (estratégia de importação). |
| **Dependências** | `docs/README.md`, `05-modelo-de-dados.md` |
| **Documentos Relacionados** | `06-pipeline-importacao.md`, `adr/ADR-013-collection-item-identity-model.md`, `adr/ADR-014-collection-and-collection-entry-model.md`, `adr/ADR-018-single-function-import-pipeline.md`, `adr/ADR-019-web-application-as-primary-interface.md` |

---

# Purpose

Este documento existe porque, ao longo de dezenas de ciclos de documentação, surgiram múltiplas formas paralelas e não reconciliadas de descrever a trajetória do projeto (`B2.x`/`B3.x`, `FASE 1-6`, `FASE 1-4`, `Fase 1-7`), nenhuma delas formalizada como fonte única de verdade. Este documento resolve essa lacuna — mas **apenas para o que já é uma decisão real de Fabrício**. Onde a direção futura ainda não foi comprometida, este documento diz isso explicitamente, em vez de adotar silenciosamente qualquer uma das propostas anteriores.

Criado em 2026-07-24, junto com a reativação da manutenção de `adr/ADR-INDEX.md` e `standards/STD-INDEX.md` — Fabrício declarou nesta data que a documentação do passado do projeto está encerrada e que os artefatos de governança (índices, roadmap) devem passar a ser mantidos ativamente a partir de agora.

---

# Now — Em Andamento

Três trilhas ativas. **Correção real (2026-08-02):** a revisão `1.13` deste documento registrava que a Trilha 3 (`ADR-024`) só começaria após o fechamento da Trilha 2 (`ADR-023`) — na prática, Fabrício redirecionou o foco para a Trilha 3 antes de a Trilha 2 estar 100% concluída (o subciclo `Card` de `ADR-023` segue pausado, não fechado). A dependência planejada não se confirmou como sequência rígida; as duas trilhas avançaram por decisão direta de Fabrício, não por engano de execução. Ver "Catálogo Editorial — Frentes de Encerramento", abaixo, para como as trilhas B–E se encaixam no fechamento do módulo.

## Trilha 1 — Importação manual de imagens de `MEE`/`MEP` (TCGdex não tem os assets)

O pipeline de importação (`import-card-assets`, `ADR-018`) foi executado com sucesso para as sete Card Sets da Expansion `ME`: `card_external_reference` 100% importada em todas (`927`/`927`). Imagens completas para as 5 coleções originais (`ME1`-`ME4`/`ME2.5`: `859` Cards, `1.718` Card Assets, `en`+`pt-BR`, `0` falhas). Para `MEE`/`MEP` (`68` Cards), confirmado por consulta direta ao CDN da TCGdex que o asset genuinamente não existe na fonte (não é gap de API) — decisão de Fabrício: importar manualmente via novo script `scripts/import-manual-assets.ts` (`source_code = 'MANUAL'`, rastreável), em vez de esperar a TCGdex publicar. **`MEE` já confirmada 100% completa (`en`+`pt-BR`, referências e imagens).** Pendente: `MEP`/`en`, `MEP`/`pt-BR` (`60` Cards cada) — hoje só há `13`/`60` de `MEP`/`en` salvas localmente; Fabrício optou por aguardar as duas pastas completas antes de rodar o script de verdade.

Em paralelo, bug real corrigido nesta revisão (2026-07-25): `asset_import_run` nunca transicionava de `PENDING`, mesmo em execuções bem-sucedidas — a função `import-card-assets` nunca escrevia na tabela após o `SELECT` inicial. Corrigido (v2.6.0, CONFIRMADO DEPLOYADO E TESTADO EM PRODUÇÃO), as 11 runs históricas corrigidas via backfill, e um novo gap de GRANT (mesmo padrão recorrente do projeto) resolvido por `database/migrations/272_grant_asset_import_run_write_permissions.sql`. Ver `docs/05-modelo-de-dados.md`, seção "Correção real: máquina de estados nunca escrita (v2.6.0)", para o detalhe completo.

Só quando as imagens de `MEE`/`MEP` também estiverem importadas o Catálogo Editorial estará genuinamente fechado — conforme a própria correção de Fabrício registrada em `05-modelo-de-dados.md`, revisão `0.63`: *"Não teremos encerrado toda a fundação do catálogo editorial do Project Mimikyu. Só concluímos após importação de todas as imagens para nossa base."*

## Trilha 2 — Catálogo Editorial: Escrita Administrativa (`ADR-023`, em andamento)

Formaliza a autoria (criação/edição/exclusão administrativa) das entidades do Catálogo Editorial pela própria interface web, em ciclos verticais por entidade (Backend → Tela → Validação), um de cada vez. Numeração dedicada no milhar `2000`–`2999` (`STD-001` v1.17).

Estado atual (2026-08-02): infraestrutura comum (schema `internal`, tabela `catalog_admin_action_log`, `card.is_active`, `internal.write_card()`) CONCLUÍDA. Três das quatro entidades do escopo vertical têm escrita administrativa concluída — `Game` (create+update+delete, Queries `2031`/`2032`/`2041`/`2042`, validações `2804`/`2808`), `Expansion` (create+update+delete+logo, Queries `2033`/`2034`/`2043`/`2044`/`2045`–`2047`, validações `2805`/`2809`/`2810`) e `Card Set` (create+update+delete+logo+código editável, Queries `2048`–`2051`/`2091`, validações `2811`/`2812`/`2815`) — `admin_create_card_set()` cobriu inclusive as duas categorias antes fora de escopo (`ENERGY`, código editável condicional). Só resta o subciclo `Card` (criação/edição; desativação/reativação): **pausado, não iniciado** — Fabrício redirecionou o foco do projeto para a Trilha 3 (`ADR-024`) antes de abrir esse subciclo (ver correção acima). Percentual aproximado de conclusão do módulo: ~75% (mesma estimativa do handoff vigente). Detalhamento completo em `05-modelo-de-dados.md`, seção "Catálogo Editorial — Escrita e Ingestão", e no handoff vigente (ver `docs/README.md` para o arquivo atual).

## Trilha 3 — Catálogo Editorial: Ingestão Administrativa (`ADR-024`, em andamento)

Formaliza a estratégia de captura/confirmação administrativa de novas Cards a partir de fontes externas (ex.: TCGdex), reutilizando `internal.write_card()` como camada canônica de persistência (já concluída na Trilha 2). `ADR-024` define quatro ciclos verticais: **Ciclo 1** (infraestrutura comum de staging — `catalog_import_job`/`catalog_import_row`, `catalog_admin_action_log` ampliada, `admin_start_catalog_import()`/`admin_decide_catalog_import_row()`/`admin_confirm_catalog_import()`) — **CONFIRMADO EXECUTADO E VALIDADO** (2026-08-01, validação funcional `2814` completa). **Ciclo 2** (fluxo vertical completo TCGdex — Edge Function `import-catalog-cards`, telas `/catalogo/importar-cartas` e `/catalogo/importar-imagens`, revisão interativa, confirmação em lote, integração automática cartas→imagens) — **implementado e em uso ativo em produção** (múltiplos Card Sets já importados via TCGdex), mas sem o mesmo fechamento formal/validação final que o Ciclo 1 recebeu — pendência real registrada, não apenas de documentação. **Ciclo 3** (prova técnica do processador de PDF) e **Ciclo 4** (fluxo PDF completo) — não iniciados. Detalhamento completo em `05-modelo-de-dados.md`, seção "Catálogo Editorial — Escrita e Ingestão" (Ciclo 1) e revisões `1.1`–`1.50` (Ciclo 2), e no handoff vigente.

---

# Catálogo Editorial — Frentes de Encerramento

"Catálogo Editorial" é usado neste roadmap e no restante da documentação para mais de um escopo — modelo de dados, pipeline de imagens, leitura, escrita administrativa, ingestão administrativa. Esta seção formaliza as cinco frentes que compõem o módulo e o critério para declará-lo encerrado: **as cinco precisam estar concluídas**, não apenas a mais recente em andamento.

| Frente | Escopo | Estado |
|--------|--------|--------|
| A. Modelo de Dados | Entidades estruturais do catálogo (`game` até `asset_import_failure`) | **Concluído** |
| B. Pipeline de Assets | Importação automatizada (`import-card-assets`, `ADR-018`) + importação manual (`MEE`/`MEP`) | **Concluído parcialmente** — `MEE` completa; `MEP` pendente (Trilha 1, acima) |
| C. Interface de Consulta | Leitura administrativa do catálogo (`ADR-022`) e tela Visão Geral (`/catalogo`) | **Concluído parcialmente** — implementado, validação visual em `npm run dev` pendente |
| D. Escrita Administrativa | `ADR-023` — cadastro/edição/exclusão pela interface, por ciclos verticais | **~75% concluído** — `Game`/`Expansion`/`Card Set` concluídos; subciclo `Card` pausado, não iniciado (Trilha 2, acima) |
| E. Ingestão Administrativa | `ADR-024` — captura/confirmação de novas Cards a partir de fontes externas | **Em andamento** — Ciclo 1 concluído e validado; Ciclo 2 (TCGdex) implementado e em uso ativo, fechamento formal pendente; Ciclos 3/4 (PDF) não iniciados (Trilha 3, acima) |

Só quando as cinco frentes estiverem concluídas o Catálogo Editorial está genuinamente encerrado e a Sub-Fase 2 (Coleções, abaixo) pode começar.

---

# Next — Comprometido, Ainda Não Iniciado

**Sub-Fase 2 — Coleções.**

O domínio do colecionador (Collection, Collection Entry, Collection Item — ver `04-domain-model.md` e `ADR-013`/`ADR-014`) já está conceitualmente modelado e aprovado, mas ainda não tem modelo físico (`05-modelo-de-dados.md`) nem tabelas criadas no Supabase. Fabrício confirmou diretamente (revisão `1.40` de `docs/README.md`) que este é o próximo módulo real do projeto, distinto do Catálogo Editorial: exemplares físicos possuídos pelo usuário, objetivos de coleção, e a relação entre ambos.

Início previsto apenas após o fechamento das cinco frentes do Catálogo Editorial (ver "Catálogo Editorial — Frentes de Encerramento", acima) — hoje, isso significa concluir a Trilha 1 (imagens de `MEP`) e as Trilhas 2/3 (`ADR-023`/`ADR-024`).

---

# Later — Direção Futura Provável, Não Comprometida

Os itens abaixo refletem temas que já apareceram em mais de uma proposta de roadmap ao longo do projeto (sessões pareadas e o próprio Fabrício), mas **nenhum foi formalmente comprometido em sequência, escopo ou modelo de dados**. Estão listados aqui para dar visibilidade de direção, não como plano de execução:

- **Aquisição e movimentação** — registro de compras, trocas e vendas de Cards/Card Variants pelo colecionador.
- **Avaliação e inteligência** — precificação, relatórios e análises sobre a Collection do usuário.

Qualquer um destes itens só entra em "Next" quando Fabrício o confirmar explicitamente, com escopo próprio — seguindo a mesma disciplina de não resolver unilateralmente decisões de direção que já se aplica ao restante deste projeto.

---

# Concluído

- **Fase 1 — Arquitetura Conceitual.** Princípios arquiteturais, delimitação do domínio, estrutura do catálogo editorial, modelo do universo do colecionador, separação Set/Collection, estratégia de evolução incremental.
- **Sub-Fase 1 — Catálogo Editorial, Bloco A (Modelo de Dados).** Todas as entidades estruturais criadas e homologadas para as 7 Card Sets: `game`, `expansion`, `card_set`, `card` (`927`), `card_category`, `rarity` (10), `language`, `card_variant_type`, `card_variant` (`1.653`), `card_asset_type`/`card_asset`, `storage_bucket`, `asset_source`, `card_external_reference`, `card_set_external_reference`, `asset_import_run`, `asset_import_failure`.
- **Sub-Fase 1 — Catálogo Editorial, Bloco B (Pipeline de Importação), para as 5 coleções originais.** `859` Cards processadas, `859` referências externas, `1.718` Card Assets, `en`+`pt-BR`, `0` falhas.
- **Início do front-end (aplicação web).** Fabrício decidiu (2026-07-25, `ADR-019-web-application-as-primary-interface.md`) começar a construção da interface do produto sem esperar a modelagem de Coleções — React/Next.js adotado como interface principal, Power Apps/SharePoint/Power BI descartados da arquitetura-alvo. App shell e autenticação básica (Supabase Auth) no repositório (`web/`).
- **Identidade e Acesso — Incremento 1 ("Meu Perfil").** `user_profile`, separado de `auth.users` (`ADR-020`), inaugurando o Modelo Modular de Numeração do STD-001 (milhar `1000`–`1999`). Tabela, triggers, RLS, `handle_new_user()`, `username_available()`, bucket de avatares e frontend (`/perfil`) confirmados e validados ponta a ponta em produção.
- **Identidade e Acesso — Incremento 2 ("Administração de Usuários"), Fases 1–3.** Papel administrativo (`admin_user`, sem RLS direta) e auditoria (`admin_action_log`) — `ADR-021`. `is_admin()`, `admin_list_users()`, `admin_grant_admin()`/`admin_revoke_admin()` e interface (`/usuarios`) confirmados e validados em produção. Fase 4 (correção administrativa de `username`, `ADR-020`) deliberadamente fora deste incremento, por decisão de Fabrício.
- **Catálogo Editorial — Frente C (Interface de Consulta), fundação de autorização/logo e tela Visão Geral.** Descoberto que as 17 tabelas do módulo tinham RLS habilitado sem nenhuma política — formalizado como admin-only em `ADR-022-catalog-editorial-admin-only-access.md`. Leitura liberada via `catalog_admin_select` nas 10 tabelas usadas pela Visão Geral; escrita da logo restrita a `admin_set_card_set_logo()`; bucket privado `card-set-logo`. Queries `273`–`277` CONFIRMADAS EXECUTADAS. Tela `/catalogo` (Visão Geral) implementada — guarda de servidor nas seis rotas, quatro blocos (Estado do Catálogo, Card Sets navegável, Cartas por Raridade, Atividade Recente), rota de detalhe `/catalogo/card-sets/[code]`. `tsc --noEmit` limpo; validação visual em `npm run dev` ainda pendente.
- **Catálogo Editorial — Frente D (Escrita Administrativa), infraestrutura comum e ciclos verticais de `Game`/`Expansion`/`Card Set`.** `Card Set` inclui create+update+delete+logo e código editável condicional — subciclo `Card` (criação/edição) segue pausado. Ver Trilha 2, acima, e `05-modelo-de-dados.md`/handoff vigente para o detalhamento completo.
- **Catálogo Editorial — Frente E (Ingestão Administrativa), Ciclo 1 de `ADR-024`.** Infraestrutura comum de staging/confirmação (`catalog_import_job`/`catalog_import_row`) — CONFIRMADO EXECUTADO E VALIDADO (2026-08-01). Ver Trilha 3, acima.
- **Pipeline de importação de imagens (`import-card-assets`) — suporte simultâneo a EN+PT-BR, resiliência a timeout/retry, e integração automática cartas→imagens.** Evolução de v2.6.0 (correção da máquina de estados) a v2.9.3 (retry por download individual), incluindo `language_id` na identidade de `card_external_reference`. Ver `05-modelo-de-dados.md`, revisões `1.30`–`1.44`, e `06-pipeline-importacao.md`.
- **Correções de mapeamento de raridade** (`ACE_SPEC_RARE`/`SHINY_RARE`/`SHINY_ULTRA_RARE` cadastradas; símbolo de `HYPER_RARE` corrigido de uma para três estrelas, `GOLD_TRIPLE_STAR`) — ver `05-modelo-de-dados.md`, revisões `1.45`–`1.50`.
- **Galerias de Expansões e Coleções reagrupadas** (Expansões por Jogo; Coleções por Expansão) — puramente de apresentação, sem mudança de modelo de dados.

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Criação do documento (2026-07-24), a pedido explícito de Fabrício, junto com a reativação de `ADR-INDEX.md`/`STD-INDEX.md`. Consolida, pela primeira vez, uma única fonte de verdade para a trajetória do projeto — sem adotar nenhuma das múltiplas propostas de roadmap não reconciliadas surgidas ao longo do projeto (`B2.x`/`B3.x`, `FASE 1-6`, `FASE 1-4`, `Fase 1-7`); itens ainda não comprometidos por Fabrício ficam explicitamente em "Later", não em "Next". |
| 1.1 | Registrado o progresso real de "Now" (2026-07-24): pipeline `import-card-assets` executado pela primeira vez para `MEE` — referências externas confirmadas, imagens bloqueadas por gap de dados na TCGdex (ver `operations/import-card-assets.md`). Próximo passo do item "Now" passa a ser `MEP`. |
| 1.2 | `MEP` executada no mesmo dia, mesmo resultado da `MEE`: referências externas 100%, imagens bloqueadas pelo mesmo gap real de dados na TCGdex. "Now" reescrito — não há mais nenhuma coleção com execução pendente do lado do Project Mimikyu; o item permanece aberto apenas aguardando a TCGdex publicar os assets de `MEE`/`MEP`. |
| 1.3 | Decisão de Fabrício: em vez de esperar a TCGdex, importar as imagens de `MEE`/`MEP` manualmente — confirmado antes que o asset genuinamente não existe no CDN da TCGdex (404 direto, não só ausência no campo `image` da API). Novo script `scripts/import-manual-assets.ts` criado e CONFIRMADO EXECUTADO para `MEE`/`en` (8/8, 0 falhas). "Now" reescrito para refletir trabalho ativo novamente. |
| 1.4 | `MEE`/`pt-BR` executada no mesmo dia (8/8, 0 falhas) — `MEE` agora 100% completa nos dois idiomas. Falta só `MEP`/`en`+`pt-BR` (`60` Cards cada) para o Catálogo Editorial estar genuinamente fechado. |
| 1.5 | Bug real de `asset_import_run` nunca transicionar de `PENDING` corrigido e testado em produção (v2.6.0) — ver `05-modelo-de-dados.md`. `MEP`/`en` parcialmente salva localmente (`13`/`60`); execução real do script manual adiada até as duas pastas (`en`+`pt-BR`) estarem completas. |
| 1.6 | **Decisão real de Fabrício: iniciar o front-end (aplicação web) agora, em paralelo, sem esperar a modelagem de Coleções — formalizada em `ADR-019-web-application-as-primary-interface.md`.** React/Next.js adotado como interface principal; Power Apps/SharePoint/Power BI removidos da "Later" (não são mais direção provável — foram descartados). Novo parágrafo em "Now" descrevendo os dois módulos iniciais (Gestão de Usuários, Catálogo Editorial CRUD). Nenhum código de front-end ainda existe. |
| 1.7 | App shell, autenticação básica e telas de Catálogo Editorial confirmadas no repositório. **Base de dados do Incremento 1 de Identidade e Acesso ("Meu Perfil") concluída e confirmada no Supabase** (`user_profile`/`reserved_username`, `1000`–`1040`/`1710`/`1800`–`1840`, ADR-020, novo Modelo Modular de Numeração do STD-001) — falta só o frontend (formulário de cadastro + tela `/perfil`). Explicitado que Incremento 2 (lista administrativa) e papéis/permissões seguem fora de escopo até aprovação própria. |
| 1.8 | **Fechamento de governança do Incremento 1, a pedido de Fabrício (2026-07-26): banco de dados e documentação declarados formalmente CONCLUÍDOS** — nenhuma alteração adicional de modelo prevista, salvo bloqueio real durante a integração com o frontend. Deixado explícito que a implementação de interface é o único item pendente do incremento, sob Task 356 (em andamento). |
| 1.9 | **Incremento 1 fechado por completo (frontend validado em produção) e Incremento 2 ("Administração de Usuários") concluído nas Fases 1–3 (2026-07-26).** Papel administrativo (`admin_user`), auditoria (`admin_action_log`) e interface (`/usuarios`) formalizados em `ADR-021-administrative-role-model.md`, executados e validados ponta a ponta. Fase 4 (correção administrativa de `username`) explicitamente adiada para um incremento futuro, por decisão de Fabrício. |
| 1.10 | **Catálogo Editorial (frontend) — fundação de autorização e logo concluída (2026-07-26), formalizada em `ADR-022-catalog-editorial-admin-only-access.md`.** Descoberto que as 17 tabelas do módulo estavam de fato fechadas (RLS sem política); decisão de tornar isso permanente e admin-only. Queries `273`–`277` CONFIRMADAS EXECUTADAS: coluna `card_set.logo_storage_path`, política admin-only de leitura em 10 tabelas, função `admin_set_card_set_logo()`, bucket privado `card-set-logo` com quatro políticas de Storage. Novo parágrafo em "Now". Implementação da tela `/catalogo` em si permanece pendente. |
| 1.11 | **Tela Visão Geral (`/catalogo`) implementada no mesmo dia (2026-07-26), sobre a fundação da revisão `1.10`.** Guarda de servidor compartilhada (`requireCatalogoAdmin()`) nas seis rotas do módulo; quatro blocos (Estado do Catálogo, Card Sets navegável, Cartas por Raridade, Atividade Recente); nova rota de detalhe `/catalogo/card-sets/[code]`. `tsc --noEmit` limpo; validação visual em `npm run dev` pendente. Ressalva registrada em `05-modelo-de-dados.md`: indicadores exatos reconstruídos a partir do resumo pós-compactação, não do wireframe verbatim aprovado originalmente — valem conferência de Fabrício. |
| 1.12 | **Reconciliação documental (2026-07-26), motivada por auditoria externa conduzida por Fabrício após a sessão que produziu `development/HANDOFF-2026-07-26.md`.** "Now" reescrito em três trilhas explícitas: Trilha 1 (imagens `MEP`, inalterada em conteúdo), Trilha 2 (`ADR-023`, nova — registra infraestrutura comum/`Game`/`Expansion` concluídos e `Card Set` como próximo ciclo, referenciando o handoff vigente) e Trilha 3 (`ADR-024`, nova — explicitamente não iniciada). Itens já concluídos que estavam misturados em "Now" (início do front-end, Identidade e Acesso Incrementos 1/2, fundação de leitura/Visão Geral do Catálogo Editorial via `ADR-022`) movidos para "Concluído", eliminando a ambiguidade entre "em andamento" e "já fechado". Nova seção "Catálogo Editorial — Frentes de Encerramento" formaliza as cinco frentes do módulo (A. Modelo de Dados, B. Pipeline de Assets, C. Interface de Consulta, D. Escrita Administrativa, E. Ingestão Administrativa) e o critério de que as cinco precisam estar concluídas para o módulo ser declarado encerrado — "Next" (Sub-Fase 2 — Coleções) agora referencia esse critério explicitamente em vez de um "fechamento do Catálogo Editorial" genérico. |
| 1.13 | **Correção direcionada (2026-07-30), a pedido de Fabrício.** Parágrafo de abertura de "Now" corrigido: Trilha 3 (`ADR-024`) depende da conclusão da Trilha 2 (`ADR-023`) — `ADR-024` só começa após o fechamento de `ADR-023` — não são três trilhas totalmente independentes como a revisão `1.12` descrevia. Trilha 1 e Trilha 2 permanecem sem dependência entre si e podem avançar em paralelo. Sequência já comprometida das trilhas não foi alterada. |
| 1.14 | **Auditoria de reconciliação documental (2026-08-02), a pedido explícito de Fabrício ("vamos parar para organizar a casa").** Correção real registrada: a dependência sequencial planejada na revisão `1.13` (Trilha 3 só começa após o fechamento de Trilha 2) não se confirmou na prática — Fabrício redirecionou o foco para `ADR-024` com o subciclo `Card` de `ADR-023` ainda pausado, não fechado; registrado como decisão real, não como desvio não intencional. Trilha 2 atualizada: `Card Set` concluído (create+update+delete+logo+código editável), restando só o subciclo `Card`, pausado. Trilha 3 reescrita de "não iniciada" para "em andamento": Ciclo 1 confirmado executado e validado; Ciclo 2 (fluxo TCGdex completo) implementado e em uso ativo em produção, sem fechamento formal equivalente ao do Ciclo 1 — pendência real, preservada explicitamente, não declarada como resolvida. "Catálogo Editorial — Frentes de Encerramento": Frente D atualizada para ~75%; Frente E atualizada de "Não iniciada" para "Em andamento". "Concluído" ganhou cinco itens novos: ciclo `Card Set` de `ADR-023`; Ciclo 1 de `ADR-024`; evolução do pipeline de imagens (EN+PT-BR, retry, v2.6.0–v2.9.3); correções de mapeamento de raridade; reagrupamento das galerias de Expansões/Coleções. Nenhuma alteração em código, SQL ou decisão arquitetural nova — apenas reconciliação com o estado real do repositório. Multi-provider permanece explicitamente fora de "Next"/"Later" como compromisso — ver `06-pipeline-importacao.md`, seção "Em Aberto", para o registro dessa pendência arquitetural. |
