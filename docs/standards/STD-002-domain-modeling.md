# STD-002 — Domain Modeling

| Campo | Valor |
|--------|-------|
| **Documento** | STD-002 |
| **Título** | Domain Modeling |
| **Arquivo** | `docs/standards/STD-002-domain-modeling.md` |
| **Versão** | 1.0 |
| **Status** | Aprovado |
| **Objetivo** | Padronizar a modelagem dos conceitos do domínio. |
| **Escopo** | Modelagem conceitual de entidades e conceitos do domínio, previamente à modelagem lógica e física. |
| **Dependências** | `../02-architecture-principles.md` |
| **Documentos Relacionados** | `../04-domain-model.md`, `STD-INDEX.md` |

---

# Purpose

Todo conceito do domínio deverá ser definido antes de qualquer modelagem lógica ou física.

---

# Modeling Rule

Para cada conceito responder obrigatoriamente:

## 1. O que é?

Define sua identidade.

---

## 2. O que não é?

Evita ambiguidades.

---

## 3. Qual problema resolve?

Justifica sua existência.

---

Nenhum conceito deverá ser introduzido sem responder claramente essas três perguntas.

---

# Benefits

- reduz ambiguidades;
- evita entidades artificiais;
- facilita evolução do domínio;
- melhora a comunicação entre arquitetura e implementação.

---

# Business Identity vs Technical Identity

Durante a modelagem do domínio deve-se distinguir explicitamente:

- identidade de negócio;
- identidade técnica.

Identificadores técnicos (UUID) nunca substituem identificadores de negócio utilizados pelo domínio.

Da mesma forma, códigos de negócio nunca devem ser utilizados como chave técnica.

---

# Responsibility Separation

Todo novo conceito deverá ser classificado conforme sua responsabilidade predominante:

- Editorial Catalog;
- User Ownership;
- Analytics.

Um conceito não deverá misturar dados editoriais oficiais com características particulares de exemplares físicos.

Informações derivadas deverão ser identificadas explicitamente para evitar que sejam tratadas como dados primários do domínio.

---

# Concept Classification

Além de responder às três perguntas da Modeling Rule, todo conceito deverá ser classificado em uma das três categorias abaixo. Essa classificação orienta diretamente a modelagem lógica e física — ela ajuda a definir quais conceitos merecem uma tabela própria e quais devem permanecer como parte de outra entidade.

## 1. Identity Entity (Entidade de Identidade)

Possui identidade própria e pode ser referenciada por muitas outras entidades.

Exemplos: Card, Set, Pokémon, Illustrator.

## 2. Value Object (Objeto de Valor)

Não possui identidade própria. Existe apenas como parte de outra entidade e não faz sentido isoladamente.

Exemplos: HP, Weakness, Resistance, Retreat Cost, Regulation Mark.

## 3. Reference Data (Tabela de Domínio)

Catálogo pequeno, controlado e reutilizado por todo o sistema.

Exemplos: Rarity, Card Category, Trainer Subcategory, Finish.

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Criação inicial do padrão de modelagem de domínio. |
| 1.1 | Padronização do cabeçalho (Título, Arquivo, Escopo, Dependências, Documentos Relacionados) e correção de estrutura de seções (separadores e nível de heading). |
| 1.2 | Adicionada a seção Concept Classification (Identity Entity / Value Object / Reference Data), descoberta durante a modelagem detalhada da Card. |