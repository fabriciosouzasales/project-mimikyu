# STD-002 — Domain Modeling

| Campo | Valor |
|--------|-------|
| Documento | STD-002 |
| Status | Aprovado |
| Objetivo | Padronizar a modelagem dos conceitos do domínio. |

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

## Business Identity vs Technical Identity

Durante a modelagem do domínio deve-se distinguir explicitamente:

- identidade de negócio;
- identidade técnica.

Identificadores técnicos (UUID) nunca substituem identificadores de negócio utilizados pelo domínio.

Da mesma forma, códigos de negócio nunca devem ser utilizados como chave técnica.

# Responsibility Separation

Todo novo conceito deverá ser classificado conforme sua responsabilidade predominante:

- Editorial Catalog;
- User Ownership;
- Analytics.

Um conceito não deverá misturar dados editoriais oficiais com características particulares de exemplares físicos.

Informações derivadas deverão ser identificadas explicitamente para evitar que sejam tratadas como dados primários do domínio.