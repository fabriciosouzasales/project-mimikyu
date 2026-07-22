# Pipeline de Importação

| Campo | Valor |
|--------|-------|
| **Documento** | Pipeline de Importação |
| **Arquivo** | `docs/06-pipeline-importacao.md` |
| **Versão** | 0.1 |
| **Status** | Em elaboração |
| **Objetivo** | Definir a estratégia de importação e sincronização de dados de fontes externas para o Catálogo Editorial do Project Mimikyu. |
| **Escopo** | Estratégia conceitual de importação. Não contém detalhes de implementação, código ou cronograma de execução. |
| **Dependências** | `02-architecture-principles.md`, `04-domain-model.md` |
| **Documentos Relacionados** | `adr/ADR-006-separation-of-catalog-ownership-and-analytics.md`, `adr/ADR-008-external-catalog-data-sources.md` |

---

# Purpose

Este documento descreve a estratégia geral de importação e sincronização de dados de fontes externas para o Catálogo Editorial do Project Mimikyu.

A decisão arquitetural que fundamenta este documento está registrada em `adr/ADR-008-external-catalog-data-sources.md`.

Este documento está em elaboração: o padrão estratégico já está definido, mas os mecanismos concretos de importação (frequência, formato intermediário, tratamento de falhas, etc.) ainda serão detalhados em ciclos futuros de documentação.

---

# Padrão Geral

Nenhuma fonte de dados externa é a proprietária lógica do catálogo. Toda fonte externa passa por uma camada de importação/sincronização antes de alimentar o catálogo interno:

```text
External Data Source
        ↓
Import / Synchronization
        ↓
Project Mimikyu Catalog
```

O catálogo interno do Project Mimikyu mantém registros próprios e independentes de:

- Game;
- Expansion;
- Set;
- Card;
- Card Translation;
- Card Variant.

---

# Por que o catálogo não depende de uma API externa em tempo real

Não foi identificada uma API oficial documentada mantida pela The Pokémon Company para integração de sistemas externos. Ferramentas amplamente utilizadas por desenvolvedores — como a Pokémon TCG API (atualmente integrada à plataforma Scrydex) e a TCGdex — são projetos independentes, não oficiais, cada um com sua própria base de dados.

Diante disso, o Project Mimikyu não deve assumir uma única fonte externa como definitiva, nem depender de qualquer uma delas como dependência estrutural em tempo real. A camada de Import/Synchronization existe justamente para isolar o catálogo dessas variações.

---

# Benefícios do Modelo de Importação

- permite corrigir dados inconsistentes vindos de fontes externas;
- permite complementar informações ausentes;
- preserva os registros do catálogo caso uma fonte externa seja descontinuada;
- permite integrar mais de uma fonte de dados simultaneamente;
- mantém controle sobre os códigos internos do catálogo;
- permite registrar a procedência (fonte) de cada informação importada.

---

# Em Aberto

Os seguintes pontos ainda não foram definidos e serão tratados em ciclos futuros de documentação:

- quais fontes externas específicas serão efetivamente integradas;
- formato e frequência de importação/sincronização;
- estratégia de tratamento de falhas e reprocessamento;
- estratégia de resolução de conflitos entre múltiplas fontes.

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 0.1 | Estrutura inicial do documento, com o padrão geral de importação/sincronização definido em ADR-008. Mecanismos concretos de pipeline ainda pendentes. |
