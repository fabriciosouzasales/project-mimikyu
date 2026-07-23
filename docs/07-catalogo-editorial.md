# Catálogo Editorial

| Campo | Valor |
|--------|-------|
| **Documento** | Catálogo Editorial |
| **Arquivo** | `docs/07-catalogo-editorial.md` |
| **Versão** | 0.3 |
| **Status** | Em elaboração |
| **Objetivo** | Documentar como as informações do Catálogo Editorial são efetivamente capturadas e disponibilizadas pelo Project Mimikyu. |
| **Escopo** | Estratégia de captura e disponibilização de dados do catálogo. Não redefine entidades (ver `04-domain-model.md`) nem decisões arquiteturais (ver ADRs). |
| **Dependências** | `04-domain-model.md`, `adr/ADR-012-structured-vs-visual-card-data.md` |
| **Documentos Relacionados** | `adr/ADR-011-pokemon-tcg-domain-scope.md`, `06-pipeline-importacao.md` |

---

# Purpose

Este documento explica, em termos práticos, como o Catálogo Editorial do Project Mimikyu disponibiliza as informações de uma Card — combinando dados estruturados no banco de dados com a imagem oficial da própria Card.

A decisão arquitetural que fundamenta este documento está registrada em `adr/ADR-012-structured-vs-visual-card-data.md`.

---

# Três Níveis de Disponibilidade da Informação

## 1. Structured Data (Dados Estruturados)

São informações armazenadas em campos próprios e utilizáveis diretamente em filtros, regras e relatórios.

Exemplos: `set_id`, `card_number`, `category`, `trainer_subcategory`, `rarity`, `pokemon_id`.

Com esses dados, o sistema consegue responder eficientemente perguntas como: quais cartas são do Pikachu; quais cartas são Trainer; quais são Illustration Rare; quais cartas faltam no ME1.

## 2. Visual Source (Fonte Visual)

É a imagem oficial da Card. Permite que o usuário veja informações que não foram estruturadas, como ataques, HP, textos, fraquezas, custos e demais detalhes editoriais.

O sistema possui acesso visual ao conteúdo, mas não necessariamente consegue pesquisá-lo ou utilizá-lo automaticamente em regras. Ter a imagem não equivale, tecnicamente, a possuir os dados estruturados: o texto de um ataque pode estar perfeitamente legível na imagem, mas não pode ser filtrado ou pesquisado sem extração ou cadastro estruturado.

## 3. Extracted Data (Dados Extraídos)

No futuro, algumas informações hoje disponíveis apenas na imagem poderão ser convertidas em dados estruturados por: importação de APIs; processamento automatizado; reconhecimento de imagem; revisão manual; enriquecimento progressivo do catálogo.

```text
Card Image → Extraction Process → HP: 180, Attack: ..., Weakness: ...
```

Essa extração é uma possibilidade de evolução, não uma obrigação da primeira versão.

---

# Critério para Estruturar uma Informação

A pergunta a ser feita nunca é "temos ou não temos essa informação?" — é sempre:

> Essa informação precisa ser pesquisável, filtrável, validável ou utilizada em regras do produto?

Se a resposta for não, a imagem é suficiente por ora.

## Campos estruturados na primeira versão

`Set`, `Number`, `Category`, `Trainer Subcategory`, `Rarity`, `Pokémon reference`, `Available Variants` (Card Variant), `Translations` (Card Translation), `Image reference`.

## Campos que permanecem apenas na imagem, por ora

`HP`, `Attacks`, `Abilities`, `Weakness`, `Resistance`, `Retreat Cost`, `Evolution Stage`, `Detailed Rules Text` (Effect).

---

# Benefícios desta Abordagem

- reduz volume de cadastro e dependência de APIs externas completas;
- reduz erros de importação e custo de validação;
- reduz complexidade do modelo lógico inicial;
- reduz o tempo necessário para disponibilizar novos Sets no catálogo;
- preserva a informação (via imagem) mesmo quando não estruturada — nada é perdido, apenas adiado.

---

# Em Aberto

- critérios objetivos para priorizar quais campos hoje visuais serão estruturados em ciclos futuros;
- mecanismo concreto de extração de dados (manual, automatizado ou híbrido) — depende do pipeline de importação (`06-pipeline-importacao.md`);
- relação definitiva entre a imagem da Card (Card Image) e a Card Translation / Card Variant (uma imagem por idioma, por acabamento, ou ambos) — decisão progressiva, ver `04-domain-model.md`, seção Card Translation, e AP-015.

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 0.1 | Estrutura inicial do documento, com o modelo de três níveis de disponibilidade de informação e o critério de estruturação de campos, definidos em ADR-012. |
| 0.2 | Adicionado ponto em aberto sobre a relação entre Card Image e Card Translation/Card Finish. |
| 0.3 | "Available Finishes"/"Card Finish" atualizados para "Available Variants"/"Card Variant" (Campos estruturados, Em Aberto), refletindo a convergência de nomenclatura de ADR-016. A entrada 0.2, acima, é preservada sem alteração como registro histórico do momento em que o ponto em aberto foi originalmente adicionado. |
