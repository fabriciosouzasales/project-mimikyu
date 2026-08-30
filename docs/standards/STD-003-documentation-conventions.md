# STD-003 — Documentation Conventions

| Campo | Valor |
|--------|-------|
| **Documento** | STD-003 |
| **Título** | Documentation Conventions |
| **Arquivo** | `docs/standards/STD-003-documentation-conventions.md` |
| **Versão** | 1.2 |
| **Status** | Aprovado |
| **Objetivo** | Padronizar a escrita da documentação técnica do Project Mimikyu. |
| **Escopo** | Convenções de terminologia e redação aplicáveis a toda a documentação técnica do projeto. |
| **Dependências** | `../03-documentation-architecture.md` |
| **Documentos Relacionados** | `../architecture/ubiquitous-language.md`, `STD-INDEX.md` |

---

# Purpose

Padronizar a escrita da documentação técnica do Project Mimikyu.

---

# Technical Terms

Sempre que possível utilizar o formato:

```text
English (Português)
```

Exemplos:

```text
Game (Jogo)

Expansion (Expansão)

Card (Carta)

Physical Card (Exemplar Físico)
```

Quando o mercado utilizar predominantemente o termo em inglês (como Set), manter o termo original e acrescentar explicações quando necessário.

---

# Objective

Melhorar a legibilidade da documentação sem perder alinhamento com a implementação técnica.

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Criação inicial das convenções de documentação. |
| 1.1 | Padronização do cabeçalho (Título, Arquivo, Objetivo, Escopo, Dependências, Documentos Relacionados) para consistência com STD-001. |
| 1.2 | Convergência terminológica (2026-08-30): exemplo "Inventory Item (Item da Coleção)" atualizado para "Physical Card (Exemplar Físico)" — nome canônico vigente do exemplar físico, ver `concept-decisions.md` C-47/C-48. |