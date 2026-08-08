# Catálogo Editorial

| Campo | Valor |
|--------|-------|
| **Documento** | Catálogo Editorial |
| **Arquivo** | `docs/07-catalogo-editorial.md` |
| **Versão** | 0.7 |
| **Status** | Em elaboração |
| **Objetivo** | Documentar como as informações do Catálogo Editorial são efetivamente capturadas e disponibilizadas pelo Project Mimikyu. |
| **Escopo** | Estratégia de captura e disponibilização de dados do catálogo. Não redefine entidades (ver `04-domain-model.md`) nem decisões arquiteturais (ver ADRs) — o fluxo de ingestão resumido abaixo é uma referência de leitura, não a especificação; a especificação completa vive em `adr/ADR-024-catalog-card-ingestion-strategy.md`. |
| **Dependências** | `04-domain-model.md`, `adr/ADR-012-structured-vs-visual-card-data.md` |
| **Documentos Relacionados** | `adr/ADR-011-pokemon-tcg-domain-scope.md`, `adr/ADR-024-catalog-card-ingestion-strategy.md`, `05-modelo-de-dados.md`, `06-pipeline-importacao.md`, `operations/import-card-assets.md`, `development/` (handoff vigente) |

---

# Purpose

Este documento explica, em termos práticos, como o Catálogo Editorial do Project Mimikyu disponibiliza as informações de uma Card — combinando dados estruturados no banco de dados com a imagem oficial da própria Card.

A decisão arquitetural que fundamenta este documento está registrada em `adr/ADR-012-structured-vs-visual-card-data.md`.

> **Nota sobre o Status "Em elaboração" (2026-07-30).** O modelo de três níveis e o critério de estruturação estão definidos e estáveis (AP-017 encerrou permanentemente a questão de mecânica de jogo). O que mantém este documento em elaboração está listado objetivamente na seção "Em Aberto", abaixo — não uma promoção de status.

---

# Três Níveis de Disponibilidade da Informação

## 1. Structured Data (Dados Estruturados)

São informações armazenadas em campos próprios e utilizáveis diretamente em filtros, regras e relatórios.

Exemplos conceituais: Set, Number, Category, Trainer Subcategory, Rarity, Pokémon reference.

Exemplos físicos (colunas reais de `card`, ver `05-modelo-de-dados.md`): `card_set_id`, `rarity_id`, `category_id`, `collector_number`, `collector_total`, `collector_order`, `name`, `is_active`. A referência a Pokémon (conceitual: `Pokémon reference`) prevista em `04-domain-model.md` ainda não corresponde a nenhuma coluna física em `card` — a tabela física, hoje, não possui `pokemon_id` nem equivalente.

Com esses dados, o sistema consegue responder eficientemente perguntas como: quais cartas são do Pikachu; quais cartas são Trainer; quais são Illustration Rare; quais cartas faltam no ME1.

## 2. Visual Source (Fonte Visual)

É a imagem oficial da Card. Permite que o usuário veja informações que não foram estruturadas, como ataques, HP, textos, fraquezas, custos e demais detalhes editoriais.

O sistema possui acesso visual ao conteúdo, mas não necessariamente consegue pesquisá-lo ou utilizá-lo automaticamente em regras. Ter a imagem não equivale, tecnicamente, a possuir os dados estruturados: o texto de um ataque pode estar perfeitamente legível na imagem, mas não pode ser filtrado ou pesquisado sem extração ou cadastro estruturado.

## 3. Extracted Data (Dados Extraídos)

Algumas informações hoje disponíveis apenas na imagem podem, em ciclos futuros, ser convertidas em dados estruturados — por importação de APIs, revisão manual ou outro mecanismo — quando houver necessidade concreta de pesquisa, filtro ou funcionalidade (AP-015, "Progressive Catalog Enrichment").

**Isso nunca se aplica a informações de mecânica de jogo.** Por decisão definitiva de Fabrício, formalizada em AP-017 — Princípio do Escopo Colecionável (`02-architecture-principles.md`), o Project Mimikyu é uma plataforma de colecionismo, não um banco de dados de mecânicas de jogo. HP, ataques, habilidades, fraqueza, resistência, custo de recuo, estágio evolutivo, efeitos e demais textos de regras, e qualquer outra estatística usada para jogar uma partida, **nunca** serão lidos, extraídos (via OCR, reconhecimento de imagem ou qualquer outro processamento automatizado ou manual) nem convertidos em dados estruturados — permanentemente, não apenas na primeira versão. Essas informações continuam visíveis ao usuário apenas através da imagem oficial da Card.

```text
Card Image → Extraction Process → (apenas campos com utilidade comprovada para o colecionismo,
                                     nunca mecânica de jogo — ver AP-017)
```

O enriquecimento futuro descrito acima só se aplica a informações com utilidade comprovada para o colecionismo (ex.: metadados editoriais, atributos de catalogação) e que não violem AP-017 — nunca a mecânica de jogo listada acima.

---

# Critério para Estruturar uma Informação

A primeira pergunta é sempre um filtro definitivo, não uma questão de priorização:

> Essa informação serve para colecionar, ou apenas para jogar uma partida (AP-017)?

Se a informação for mecânica de jogo (ver "Campos que permanecem apenas na imagem", abaixo), a resposta está encerrada — nunca será estruturada, independentemente de qualquer critério de utilidade. Só para as informações que passam por esse filtro (servem ao colecionismo), a pergunta seguinte se aplica:

> Essa informação precisa ser pesquisável, filtrável, validável ou utilizada em regras do produto?

Se a resposta for não, a imagem é suficiente por ora — e essa parte permanece uma questão de priorização (AP-015), podendo mudar em ciclos futuros.

## Campos estruturados na primeira versão

Conceituais: Set, Number, Category, Trainer Subcategory, Rarity, Pokémon reference, Available Variants (Card Variant), Translations (Card Translation), Image reference.

## Campos que permanecem apenas na imagem, permanentemente (AP-017)

`HP`, `Attacks`, `Abilities`, `Weakness`, `Resistance`, `Retreat Cost`, `Evolution Stage`, `Detailed Rules Text` (Effect), e demais estatísticas usadas para jogar. Diferente dos demais campos "por ora" deste documento, estes nunca migram para "Estruturados" — AP-017 os mantém permanentemente como Visual Source, não como uma fase inicial do catálogo.

---

# Benefícios desta Abordagem

- reduz volume de cadastro e dependência de APIs externas completas;
- reduz erros de importação e custo de validação;
- reduz complexidade do modelo lógico inicial;
- reduz o tempo necessário para disponibilizar novos Sets no catálogo;
- preserva a informação (via imagem) mesmo quando não estruturada — nada é perdido, apenas adiado.

---

# Fluxo Atual de Ingestão (Resumo)

Desde `ADR-024` (Catalog Card Ingestion Strategy), a captura de novas Cards a partir de fontes externas segue um fluxo único de staging/confirmação administrativa, independente da fonte concreta:

```text
Fonte externa (ex.: TCGdex)
        ↓
Processador (ex.: Edge Function import-catalog-cards)
        ↓
catalog_import_job
        ↓
catalog_import_row
        ↓
Revisão administrativa
        ↓
Decisão (aprovar / rejeitar / editar)
        ↓
Confirmação em lote
        ↓
Persistência canônica (internal.write_card())
        ↓
Importação de Assets (imagens — import-card-assets)
```

Nenhuma fonte externa grava diretamente no catálogo canônico — toda captura passa por staging revisável (`catalog_import_job`/`catalog_import_row`) antes de chegar a `internal.write_card()`, mesma camada de persistência já usada pela escrita administrativa direta (`ADR-023`). Estado real (2026-08-08): o **Ciclo 1** (infraestrutura comum de staging/confirmação) está confirmado executado e validado; o **Ciclo 2** (processador TCGdex completo, incluindo a etapa final de importação de imagens) está confirmado executado e validado de ponta a ponta. Um processador para PDF (Ciclos 3/4 de `ADR-024`) **não será implementado** — encerrado por decisão explícita de Fabrício (`ADR-024`, emenda 2026-08-08), motivada pela taxa de sucesso já suficiente do canal TCGdex, pela direção futura de multi-provider, e pelos canais manuais já existentes (`ADR-023`/`ADR-026`) cobrirem o caso residual sem automação.

Este resumo não substitui a especificação completa — para o contrato exato de estados, funções e regras de negócio, ver `adr/ADR-024-catalog-card-ingestion-strategy.md`; para o detalhe de implementação físico, `05-modelo-de-dados.md` (seção "Catálogo Editorial — Escrita e Ingestão") e `06-pipeline-importacao.md`; para o passo a passo operacional de imagens, `operations/import-card-assets.md`; para o estado mais recente da sessão de desenvolvimento, o handoff vigente em `development/`.

---

# Em Aberto

- critérios objetivos para priorizar quais campos hoje visuais **e elegíveis a estruturação** (ou seja, que servem ao colecionismo, não à mecânica de jogo — ver AP-017) serão estruturados em ciclos futuros;
- mecanismo concreto de extração de dados (manual, automatizado ou híbrido) — depende do pipeline de importação (`06-pipeline-importacao.md`); aplica-se apenas a campos elegíveis, nunca a mecânica de jogo (AP-017).

A relação entre a imagem da Card (Card Image) e o Card Variant, especificamente para o ativo digital (Card Asset), **está definida, não mais em aberto**: um Card Asset pertence à Card, possui idioma (`language_id`), e é independente de Card Variant (não existe `card_variant_id` em `card_asset` — resolvido deliberadamente, ver `05-modelo-de-dados.md`, seção Card Asset); o ativo principal por combinação é definido por Card + Card Asset Type + Language (`ux_card_asset_primary_per_card_type_language`, Query `193`, confirmada executada e validada). Continua em aberto, sem relação com o ponto acima: a modelagem física de **Card Translation** (conteúdo textual editorial multi-idioma, ex. nome/regras traduzidos) — a tabela física atual não possui uma entidade própria para isso; `card.name` é um único valor, sem dimensão de idioma. Ver `04-domain-model.md`, seção Card Translation.

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 0.1 | Estrutura inicial do documento, com o modelo de três níveis de disponibilidade de informação e o critério de estruturação de campos, definidos em ADR-012. |
| 0.2 | Adicionado ponto em aberto sobre a relação entre Card Image e Card Translation/Card Finish. |
| 0.3 | "Available Finishes"/"Card Finish" atualizados para "Available Variants"/"Card Variant" (Campos estruturados, Em Aberto), refletindo a convergência de nomenclatura de ADR-016. A entrada 0.2, acima, é preservada sem alteração como registro histórico do momento em que o ponto em aberto foi originalmente adicionado. |
| 0.4 | **Correção direcionada (2026-07-30), a pedido de Fabrício — reconciliação com `AP-017` (Princípio do Escopo Colecionável, `02-architecture-principles.md`, já aprovado desde a revisão `1.6` daquele documento).** "Extracted Data" reescrita: mecânica de jogo (HP, ataques, habilidades, fraqueza, resistência, custo de recuo, estágio evolutivo, efeitos/textos de regra) nunca será extraída/estruturada, independentemente de OCR, API ou revisão manual — permanentemente, não uma possibilidade de evolução. "Critério para Estruturar uma Informação" ganhou um filtro definitivo anterior ao critério de utilidade ("serve para colecionar, ou só para jogar?"). "Campos que permanecem apenas na imagem" renomeada para deixar explícito que é permanente (AP-017), não "por ora". Exemplos de "Structured Data" corrigidos: removidos `set_id`/`card_number`/`category`/`pokemon_id` como exemplos de colunas físicas (`pokemon_id` não existe na tabela `card`); adicionados exemplos físicos reais (`card_set_id`/`rarity_id`/`category_id`/`collector_number`/`collector_total`/`collector_order`/`name`/`is_active`), separados explicitamente dos exemplos conceituais. "Em Aberto": fechada a relação Card Asset↔idioma↔Card Variant (definida e implementada — Query `193`, `05-modelo-de-dados.md`), mantida em aberto apenas a modelagem física de Card Translation (texto multi-idioma, sem tabela própria hoje), e qualificado o item de priorização de campos visuais para excluir explicitamente mecânica de jogo. Nenhuma decisão nova criada nesta revisão — apenas reconciliação com `AP-017`, já vigente. |
| 0.5 | Nota objetiva adicionada (2026-07-30), a pedido de Fabrício, explicando o que mantém o Status deste documento como "Em elaboração" — sem promover para "Aprovado": os itens já listados em "Em Aberto", abaixo. Nenhum conteúdo novo, apenas uma referência cruzada explícita a partir da abertura do documento. |
| 0.6 | **Auditoria de reconciliação documental (2026-08-02), a pedido de Fabrício.** Nova seção "Fluxo Atual de Ingestão (Resumo)": diagrama condensado (fonte externa → processador → staging → revisão → decisão → confirmação → persistência canônica → importação de Assets), com o estado real de cada Ciclo de `ADR-024` (Ciclo 1 concluído/validado; Ciclo 2 implementado e em uso ativo, sem fechamento formal; Ciclos 3/4 não iniciados) e referências cruzadas para a especificação completa (`ADR-024`), o detalhe físico (`05-modelo-de-dados.md`), a arquitetura do pipeline de imagens (`06-pipeline-importacao.md`), o guia operacional (`operations/import-card-assets.md`) e o handoff vigente — sem duplicar a especificação completa do ADR. "Documentos Relacionados" e "Escopo" (cabeçalho) atualizados com as mesmas referências. Status permanece "Em elaboração" — os itens de "Em Aberto" (critérios de priorização de campos, mecanismo de extração) não foram resolvidos por esta rodada, que é sobre o fluxo de ingestão administrativa, não sobre extração de dados visuais. |
| 0.7 | **Fluxo Atual de Ingestão atualizado (2026-08-08).** Ciclo 2 (TCGdex) corrigido para "confirmado executado e validado de ponta a ponta" (já fechado desde 2026-08-07). Canal PDF (Ciclos 3/4 de `ADR-024`) atualizado de "ainda não foi iniciado" para "não será implementado" — encerrado por decisão explícita de Fabrício (`ADR-024`, emenda 2026-08-08), motivada pela taxa de sucesso já suficiente do canal TCGdex, pela direção futura de multi-provider, e pelos canais manuais já existentes (`ADR-023`/`ADR-026`) cobrirem o caso residual sem automação. |
