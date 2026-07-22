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

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Criação inicial do padrão de modelagem de domínio. |
| 1.1 | Padronização do cabeçalho (Título, Arquivo, Escopo, Dependências, Documentos Relacionados) e correção de estrutura de seções (separadores e nível de heading). |