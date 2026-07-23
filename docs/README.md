# Project Mimikyu Documentation

Esta pasta contém a documentação oficial do Project Mimikyu.

## Status Atual do Projeto

| Campo | Valor |
|-------|-------|
| **Fase 1 — Arquitetura Conceitual** | Concluída |
| **Fase 2 — Modelo Lógico** | Em andamento. O banco físico (Supabase, projeto `mimikyu-core`) já possui 17 tabelas com carga inicial de dados: `game`, `expansion`, `card_set`, `card`, `card_category`, `rarity`, `language`, `card_variant`, `card_variant_type`, `card_asset`, `card_asset_type`, `card_external_reference`, `card_set_external_reference`, `asset_source`, `asset_import_run`, `asset_import_failure`, `storage_bucket`. A documentação formal completa (roteiro de `05-modelo-de-dados.md`) cobre apenas **Game** até o momento — as demais estão sendo documentadas retroativamente, uma de cada vez, a partir do histórico e da estrutura já existente. |
| **Última atualização** | 2026-07-22 |

Fase 1 entregou: princípios arquiteturais, delimitação do domínio (Pokémon TCG, não o universo Pokémon), estrutura do catálogo editorial, modelo do universo do colecionador, separação entre Set e Collection, e a estratégia de evolução incremental. Fase 2 transforma cada conceito já validado em modelo lógico e, em seguida, tabela física — uma entidade por vez, validada com dados reais antes de avançar para a próxima.

## Retomando este Projeto com uma Nova Sessão de IA

Este repositório é a única fonte de verdade do Project Mimikyu. Ele foi estruturado para que qualquer sessão de IA — inclusive uma sessão nova, sem memória de conversas anteriores — consiga retomar o projeto de forma confiável.

Ao iniciar uma nova sessão (por perda de contexto, início de uma nova fase, ou troca de ferramenta), utilize um prompt equivalente a este:

> Você está retomando o Project Mimikyu. O repositório oficial (`fabriciosouzasales/project-mimikyu`) é a única fonte de verdade — não presuma nenhuma decisão que não esteja explicitamente documentada nele, mesmo que pareça familiar. Antes de qualquer ação:
>
> 1. Leia `docs/README.md` (este documento), incluindo a seção "Status Atual do Projeto".
> 2. Leia, em ordem, `docs/00-project-charter.md` até o último documento numerado existente em `docs/`.
> 3. Leia todos os arquivos `docs/adr/ADR-NNN-*.md` presentes na pasta — não confie apenas no `ADR-INDEX.md`, que pode estar temporariamente desatualizado durante a fase de consolidação documental.
> 4. Leia todos os arquivos `docs/standards/STD-NNN-*.md`.
> 5. Leia `docs/architecture/ubiquitous-language.md` para o vocabulário oficial do domínio.
> 6. Depois de ler tudo, resuma a fase atual do projeto, as decisões já consolidadas e as pendências em aberto — e só então aguarde instruções para iniciar qualquer trabalho novo.
>
> Não avance com implementação ou com novas decisões de modelagem sem essa confirmação.

Este prompt funciona da mesma forma na fase de documentação e na fase de implementação — o que muda é apenas o papel assumido pela IA depois da confirmação. Decisões permanentes (ADRs) são imutáveis uma vez aprovadas; supersessões geram um novo número, preservando o histórico — por isso ler todos os ADRs, e não apenas os "vigentes", é seguro e recomendado.

## Core Documents

| Documento | Finalidade |
|------------|------------|
| [Project Charter](00-project-charter.md) | Define missão, visão, princípios e critérios de sucesso. |
| [Technical Identity](01-technical-identity.md) | Consolida a identidade técnica permanente do projeto. |
| [Architecture Principles](02-architecture-principles.md) | Define os princípios que orientam decisões arquiteturais. |
| [Documentation Architecture](03-documentation-architecture.md) | Define a organização e a governança da documentação. |
| [Domain Model](04-domain-model.md) | Define o modelo conceitual do domínio, anterior à modelagem lógica e física. *(Em elaboração)* |
| [Modelo de Dados](05-modelo-de-dados.md) | Modelo lógico e físico (SQL) de cada entidade, uma por vez, validado com dados reais. *(Em elaboração)* |
| [Pipeline de Importação](06-pipeline-importacao.md) | Estratégia de importação e sincronização de fontes externas. *(Em elaboração)* |
| [Catálogo Editorial](07-catalogo-editorial.md) | Estratégia de captura e disponibilização de dados do catálogo. *(Em elaboração)* |

## Documentation Areas

| Área | Finalidade |
|------|------------|
| [Architecture Decision Records](adr/ADR-INDEX.md) | Registra decisões arquiteturais e suas justificativas. |
| [Standards](standards/STD-INDEX.md) | Define padrões permanentes de implementação e documentação. |
| [Architecture](architecture/README.md) | Reúne visões, modelos, diagramas e descrições arquiteturais. |

## Governing Rule

> ADRs explain **why**. Standards define **how**.

Cada informação deve possuir um único local oficial. A documentação deve evoluir junto com o software e permanecer sincronizada com as decisões e a implementação.

---

## Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Estrutura inicial do documento de navegação. |
| 1.1 | Adicionadas as seções "Status Atual do Projeto" e "Retomando este Projeto com uma Nova Sessão de IA", garantindo que o repositório permaneça recuperável mesmo após perda total de contexto de uma sessão de IA. |
| 1.2 | Adicionado Modelo de Dados à tabela de Core Documents. Atualizado "Status Atual do Projeto": entidade Game concluída na Fase 2. |
| 1.3 | Corrigido "Status Atual do Projeto": o banco físico já possui as 17 tabelas originais com carga inicial de dados, construídas antes desta fase de consolidação documental — a documentação formal (05-modelo-de-dados.md) está sendo escrita retroativamente, e não define uma sequência de criação do zero. |
