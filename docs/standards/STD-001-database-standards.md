# STD-001 — Database Standards

| Campo | Valor |
|--------|-------|
| **Documento** | STD-001 |
| **Título** | Database Standards |
| **Versão** | 1.0 |
| **Status** | Aprovado |
| **Objetivo** | Definir os padrões permanentes utilizados na modelagem e implementação do banco de dados do Project Mimikyu. |
| **Escopo** | Todas as entidades, tabelas, relacionamentos e scripts SQL do projeto. |

---

# Purpose

Este documento define os padrões oficiais de banco de dados do Project Mimikyu.

Toda decisão relacionada à modelagem deverá obedecer às regras descritas neste documento.

Este documento representa a "Constituição" do banco de dados.

---

# 1. Technical Language

Toda a modelagem será desenvolvida utilizando inglês.

Inclui:

- nomes de tabelas;
- colunas;
- constraints;
- índices;
- funções;
- triggers;
- views;
- documentação técnica relacionada ao banco.

---

# 2. Naming Conventions

*Documentação pendente.*

---

# 3. Data Types

*Documentação pendente.*

---

# 4. Audit Model

Toda entidade de negócio deverá possuir obrigatoriamente os seguintes campos:

```text
id (UUID)

created_at
created_by

updated_at
updated_by
```

Quando aplicável, poderão existir também:

```text
deleted_at

deleted_by
```

Este padrão deverá ser seguido por todas as entidades persistidas.

---

# 5. Primary Keys

*Documentação pendente.*

---

# 6. Foreign Keys

*Documentação pendente.*

---

# 7. Indexes

*Documentação pendente.*

---

# 8. Logical Delete

*Documentação pendente.*

---

# 9. SQL Standards

*Documentação pendente.*

---

# 10. Migration Standards

*Documentação pendente.*

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Criação inicial do documento. |