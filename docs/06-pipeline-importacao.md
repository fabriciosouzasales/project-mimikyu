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

# Importação de Ativos Visuais (Imagens e Logos)

Além de dados editoriais estruturados, o mesmo padrão Import/Synchronization se aplica a ativos visuais (imagens de Card; logotipo completo e símbolo do Set — ver `04-domain-model.md`, seção Set — "Identidade Visual"): a fonte externa nunca é referenciada diretamente pela aplicação — o arquivo é importado via API e armazenado no Supabase (Storage), e o catálogo interno referencia o ativo já armazenado.

```text
External Data Source (imagem)
        ↓
Import / Synchronization
        ↓
Supabase Storage
        ↓
Project Mimikyu Catalog (referência ao ativo armazenado)
```

O banco físico já possui infraestrutura pré-existente para esse padrão (anterior a esta fase de consolidação documental, ver "Status Atual do Projeto" em `README.md`): `card_asset`, `card_asset_type`, `asset_source`, `asset_import_run`, `asset_import_failure`, `storage_bucket`. Essas tabelas ainda não foram documentadas em nível conceitual — previsto para um ciclo futuro.

**Correção (2026-07-22):** uma versão anterior deste documento atribuía `logo_url` à Expansion. Corrigido: a identidade visual pertence ao **Set** (`logo_url` e `symbol_url`, ver `04-domain-model.md` e `05-modelo-de-dados.md`, seção Set), não à Expansion. O princípio permanece o mesmo — importação automática via API, sem preenchimento manual — apenas a entidade destinatária foi corrigida.

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

- quais fontes externas específicas serão efetivamente integradas — **parcialmente respondido para Card Variant** (ver abaixo); segue em aberto para as demais entidades do catálogo;
- formato e frequência de importação/sincronização;
- estratégia de tratamento de falhas e reprocessamento;
- estratégia de resolução de conflitos entre múltiplas fontes;
- documentação conceitual formal do padrão de ativos visuais (`card_asset`, `card_asset_type`, `asset_source`, `asset_import_run`, `asset_import_failure`, `storage_bucket`) e se essa infraestrutura, hoje nomeada em torno de Card, se generaliza para Set (que precisará de `logo_url` e `symbol_url` — ver `04-domain-model.md`) ou se recebe uma estrutura própria.

---

# Primeira Aplicação Concreta — Seed de Card Variant (`860`)

Escopo restrito: apenas para popular a tabela `card_variant` (ver `04-domain-model.md`, seção Card Variant Type/Card Variant, e `05-modelo-de-dados.md`, seção Card Variant). Não é ainda uma definição geral de pipeline para as demais entidades do catálogo.

Fontes identificadas e seus papéis:

- **Checklist oficial da Pokémon** (já usado como fonte primária para `840`): confirma quais Cards existem, numeração, raridade e a impressão principal — mas nem sempre lista individualmente variantes paralelas (`REVERSE_HOLO`, `POKE_BALL_REVERSE`, `MASTER_BALL_REVERSE`).
- **TCGdex**: expõe por Card um campo `variants` (`normal`/`reverse`/`holo`/`firstEdition`) que descreve explicitamente quais impressões são conhecidas — fonte estruturada principal proposta para `860`.
- **Pokémon TCG API**: não tem campo tão direto, mas seu objeto de preços (`normal`/`holofoil`/`reverseHolofoil`) serve como evidência complementar — não deve ser usada isoladamente, já que ausência de preço não comprova ausência da variante.

Pipeline proposto (ainda não implementado, apenas decidido): `Checklist oficial + TCGdex variants + Pokémon TCG API (evidência complementar) + validação manual de exceções (POKE_BALL_REVERSE, MASTER_BALL_REVERSE, PROMO_STAMPED — exigem tratamento individual por Card Set) → dataset intermediário rastreável (fonte + status de validação por linha) → Query 860`. Dado o volume estimado, o Seed será dividido e validado por Card Set (`860A`–`860E`), consolidado depois na Query canônica `860`.

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 0.1 | Estrutura inicial do documento, com o padrão geral de importação/sincronização definido em ADR-008. Mecanismos concretos de pipeline ainda pendentes. |
| 0.2 | Adicionada a seção "Importação de Ativos Visuais": o mesmo padrão Import/Synchronization se aplica a imagens e logotipos, com armazenamento no Supabase Storage. Referenciada a infraestrutura física pré-existente (`card_asset`, `card_asset_type`, `asset_source`, `asset_import_run`, `asset_import_failure`, `storage_bucket`) e sinalizada como ponto em aberto se ela se generaliza além de Card. Confirmado que o logotipo da Expansion segue este mesmo padrão. |
| 0.3 | Correção: o logotipo/símbolo pertence ao Set, não à Expansion (ver `04-domain-model.md` e `05-modelo-de-dados.md`). Atualizadas as referências à infraestrutura de ativos visuais e ao ponto em aberto sobre generalização. |
| 0.4 | Adicionada a seção "Primeira Aplicação Concreta — Seed de Card Variant (`860`)": resposta parcial e com escopo restrito ao ponto em aberto "quais fontes externas específicas serão efetivamente integradas" — checklist oficial + campo `variants` da TCGdex (fonte estruturada principal) + Pokémon TCG API (evidência complementar de preço, não fonte isolada) + validação manual para variantes específicas de Card Set (`POKE_BALL_REVERSE`/`MASTER_BALL_REVERSE`) e `PROMO_STAMPED`. Pipeline decidido, ainda não implementado. Ver `04-domain-model.md` e `05-modelo-de-dados.md`, seção Card Variant, para o contexto completo. |
| 0.5 | Cross-referência à seção "Finish/Card Finish" de `04-domain-model.md` corrigida para "Card Variant Type/Card Variant", refletindo a convergência de nomenclatura de ADR-016. |
