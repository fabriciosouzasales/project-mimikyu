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

O banco de dados é tratado como um produto do projeto, não apenas como suporte da aplicação — por isso a nomenclatura abaixo é uma convenção permanente e única para todo o projeto, nunca misturando estilos entre tabelas ou módulos.

## Tabelas

Nome no singular, em inglês, minúsculas, no formato `snake_case`.

Exemplos: `game`, `expansion`, `set`, `card`, `collection`, `collection_item`.

## Colunas

Minúsculas, no formato `snake_case`. Nunca `camelCase`, `PascalCase` ou notação húngara.

Proibido: `gameId`, `GameID`, `idGame`.

Correto: `game_id`.

## Colunas Reservadas Comuns

`id`, `status`, `created_at`, `updated_at`, `deleted_at`, `created_by`, `updated_by`, `deleted_by` (ver Seção 4 — Audit Model) possuem significado padronizado em todo o projeto e não devem ser reutilizadas com outro propósito.

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

Toda tabela possui uma chave primária técnica chamada `id`, do tipo UUID (ver Seção 4 — Audit Model).

O `id` é a identidade técnica permanente do registro: não deve ser reaproveitado, reordenado, nem carregar significado de negócio.

Chaves de negócio (ex.: código do Set; Set + Número da Card) representam a identidade de domínio (ver `04-domain-model.md`) e podem receber restrições de unicidade próprias, mas não substituem o `id` técnico como chave primária da tabela.

---

# 6. Foreign Keys

Toda chave estrangeira segue o padrão `<entidade_referenciada>_id`, referenciando a coluna `id` (UUID) da tabela relacionada.

Exemplos: `game_id` (em `expansion`), `set_id` (em `card`), `card_id` (em `card_finish`, `collection_entry`).

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
| 1.1 | Preenchidas as Seções 2 (Naming Conventions), 5 (Primary Keys) e 6 (Foreign Keys): tabelas em `snake_case` singular, colunas em `snake_case` (nunca camelCase/PascalCase), chave primária `id` (UUID) como identidade técnica, chave estrangeira no padrão `<entidade_referenciada>_id`. |