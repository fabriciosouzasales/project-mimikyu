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
- views.

Comentários e cabeçalhos explicativos dentro dos scripts SQL (descrição, regras de negócio, autor, data) são escritos em **português**, como o restante da documentação do projeto — apenas os identificadores técnicos (nomes de objetos do banco) seguem o inglês. Ver Seção 10 (Migration Standards) para o modelo de cabeçalho.

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

## Palavras Reservadas do SQL

Quando o nome conceitual de uma entidade colide com uma palavra reservada do SQL (ex.: `SET` no PostgreSQL), a tabela física deve adotar um nome qualificado que evite a ambiguidade — mesmo que o conceito de domínio continue com seu nome original na documentação e na aplicação.

Exemplo: o conceito **Set (Set)** — ver `04-domain-model.md` — é implementado fisicamente como a tabela `card_set`.

---

# 3. Data Types

## Tipos de Texto

- `VARCHAR(n)` — quando houver um limite de negócio claro e conhecido (ex.: um código com tamanho máximo definido).
- `TEXT` — quando o conteúdo for naturalmente livre, sem limite de negócio conhecido.

Não adotaremos limites arbitrários por tradição (ex.: `VARCHAR(255)` em todos os campos de texto, sem relação com uma regra de negócio real).

## Identificadores Técnicos

`UUID` para toda chave primária técnica (ver Seção 5 — Primary Keys).

## Datas de Auditoria

`TIMESTAMPTZ` (timestamp com fuso horário) para todos os campos de data/hora de auditoria (`created_at`, `updated_at`, e demais quando existirem). Nunca armazenar apenas data local ou horário sem fuso.

---

# 4. Audit Model

## Padrão Mínimo

Toda entidade de negócio deverá possuir obrigatoriamente:

```text
id (UUID)
created_at (TIMESTAMPTZ)
updated_at (TIMESTAMPTZ)
```

`updated_at` deve ser atualizado automaticamente pelo banco (ex.: função/trigger reutilizável), sem depender de aplicações ou importadores lembrarem de alterá-lo manualmente.

## Campos Adicionais (sob demanda)

Os campos `created_by` e `updated_by` **não** são adicionados por padrão a todas as tabelas. Só devem ser adicionados quando houver necessidade real: múltiplos administradores, edição colaborativa, necessidade concreta de rastrear alterações, ou governança sobre o catálogo (Princípio da Simplicidade Inicial — ver AP-004).

`deleted_at`/`deleted_by` seguem a mesma lógica de "sob demanda" — ver Seção 8 (Logical Delete).

---

# 5. Primary Keys

Toda tabela possui uma chave primária técnica chamada `id`, do tipo UUID (ver Seção 4 — Audit Model).

O `id` é a identidade técnica permanente do registro: não deve ser reaproveitado, reordenado, nem carregar significado de negócio.

Chaves de negócio (ex.: código do Set; Set + Número da Card) representam a identidade de domínio (ver `04-domain-model.md`) e podem receber restrições de unicidade próprias, mas não substituem o `id` técnico como chave primária da tabela.

## Versão do UUID

Para o MVP, utiliza-se **UUID v4**, gerado pelo próprio banco (ex.: `gen_random_uuid()`, extensão `pgcrypto` no PostgreSQL). UUID v7 (com ordenação temporal) é preferível quando a camada tecnológica oferecer suporte adequado, mas não é um requisito do MVP — essa escolha é puramente técnica, não afeta o domínio, e pode ser revista futuramente sem impacto conceitual.

## Identidade de Negócio (code)

Além do `id` técnico, uma entidade pode possuir um `code`: um identificador curto, estável e legível, usado por pessoas, integrações ou regras editoriais (ex.: `game.code = POKEMON`; `card_set.code = ME2.5`). O `code` nunca substitui o `id` como chave primária, mas normalmente recebe uma restrição de unicidade própria.

---

# 6. Foreign Keys

Toda chave estrangeira segue o padrão `<entidade_referenciada>_id`, referenciando a coluna `id` (UUID) da tabela relacionada.

Exemplos: `game_id` (em `expansion`), `set_id` (em `card`), `card_id` (em `card_finish`, `collection_entry`).

---

# 7. Indexes

*Documentação pendente.*

---

# 8. Logical Delete

A exclusão lógica generalizada (`deleted_at` em todas as tabelas) **não** é adotada por padrão. Soft delete generalizado aumenta a complexidade do sistema: todas as consultas precisam ignorar registros excluídos; índices e restrições de unicidade ficam mais difíceis; relacionamentos podem manter dados aparentemente ativos; erros de implementação podem fazer registros "apagados" reaparecerem.

Exclusão lógica (`deleted_at`/`deleted_by`) só deve ser aplicada onde houver necessidade concreta de restauração ou preservação histórica.

Para o catálogo editorial, o padrão recomendado é um campo `status`, representando um estado de negócio — não uma exclusão:

```text
status: ACTIVE, INACTIVE
```

ou estados específicos do domínio, quando fizerem sentido:

```text
status: ANNOUNCED, RELEASED, CANCELLED
```

Isso não é soft delete — é estado de negócio, com semântica própria de cada entidade.

---

# 9. SQL Standards

Regras estruturais importantes devem existir no próprio banco de dados, e não apenas na camada de aplicação. A aplicação oferece mensagens amigáveis; o banco garante que dados inválidos não sejam persistidos, mesmo em caso de falha ou bypass da aplicação.

Exemplos de restrições implementadas no banco:

- unicidade de códigos de negócio (ex.: `game.code` não pode se repetir — `UNIQUE`);
- obrigatoriedade de relacionamentos hierárquicos (ex.: uma Expansion deve pertencer a um Game; uma Card deve pertencer a um Card Set — `NOT NULL` + `FOREIGN KEY`);
- valores numéricos com regra de negócio (ex.: uma ordem de lançamento deve ser positiva — `CHECK`);
- formato de campos de negócio (ex.: um `code` deve seguir um padrão normalizado — `CHECK` com expressão regular).

## Row Level Security (RLS)

Toda tabela do schema `public` deve ter Row Level Security habilitado no momento da criação (`ALTER TABLE ... ENABLE ROW LEVEL SECURITY`), já que esse schema é exposto pela API automática do Supabase (ver `01-technical-identity.md`) a clientes anônimos ou autenticados. Políticas de acesso específicas são criadas posteriormente, apenas quando houver necessidade concreta — até lá, o RLS habilitado sem políticas impede qualquer leitura ou escrita externa à administração direta do banco.

---

# 10. Migration Standards

## Ferramenta

Migrations são sempre executadas via SQL Editor (Supabase), nunca pelo menu visual de criação de tabelas. O menu visual é adequado para protótipos, mas o Project Mimikyu depende de constraints, triggers, funções, índices e checks — recursos mais bem organizados, documentados e rastreáveis em SQL.

A ideia inicial era organizar migrations em arquivos numerados (`000_initial_database.sql`, `001_create_game.sql`, ...). Na prática, com o uso direto do SQL Editor, essa organização evoluiu para **Queries nomeadas e numeradas dentro da própria ferramenta**, seguindo a mesma lógica sequencial.

## Padrão Oficial de Queries SQL do Project Mimikyu

Toda Query deve possuir:

- **Número** — sequencial, permitindo ordenação natural e histórico de evolução do banco (ex.: `000`, `001`, `002`...);
- **Nome** — curto, descritivo, em inglês (ex.: `Create Game table`);
- **Descrição** — em português, explicando o que a Query faz;
- **Cabeçalho** — bloco de comentário no início do script (ver modelo abaixo);
- **SQL** — o script propriamente dito;
- **Validação** — uma ou mais consultas que confirmam que a execução funcionou corretamente.

Exemplo de sequência:

```text
000 - Enable pgcrypto
001 - Create updated_at function
002 - Create Game table
003 - Create Game trigger
004 - Seed Game
005 - Create Expansion table
```

### Modelo de Cabeçalho

```sql
/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 002 - Create Game table
Versão......: 1.0
Autor.......: [nome]
Data........: AAAA-MM-DD

Descrição...:
[o que este script cria ou altera]

Regras de Negócio:
- [regra 1]
- [regra 2]
================================================================
*/
```

O campo **Versão** identifica a evolução do próprio script (ex.: uma alteração futura na tabela Game seria uma nova Query, como `045 - Alter Game structure`, preservando o registro da versão original).

## Execução

Uma etapa por vez, sempre validada antes de avançar: instalar extensão → validar → criar função → validar → criar tabela → validar. Isso facilita identificar exatamente onde algo deu errado, em vez de executar dezenas de comandos de uma só vez.

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Criação inicial do documento. |
| 1.1 | Preenchidas as Seções 2 (Naming Conventions), 5 (Primary Keys) e 6 (Foreign Keys): tabelas em `snake_case` singular, colunas em `snake_case` (nunca camelCase/PascalCase), chave primária `id` (UUID) como identidade técnica, chave estrangeira no padrão `<entidade_referenciada>_id`. |
| 1.2 | Adicionada nota sobre palavras reservadas do SQL na Seção 2 (ex.: Set → `card_set`). Preenchida a Seção 3 (Data Types: VARCHAR vs. TEXT, UUID, TIMESTAMPTZ). Refinada a Seção 4 (Audit Model): `created_by`/`updated_by`/`deleted_at`/`deleted_by` deixam de ser obrigatórios por padrão, passando a ser adicionados apenas sob necessidade concreta (Princípio da Simplicidade Inicial, AP-004); padrão mínimo agora é `id`/`created_at`/`updated_at`. Adicionada à Seção 5 a versão do UUID (v4 no MVP, v7 quando houver suporte adequado) e a distinção entre identidade técnica (`id`) e identidade de negócio (`code`). Preenchida a Seção 8 (Logical Delete: preferir `status` de negócio a soft delete generalizado) e a Seção 9 (SQL Standards: restrições de integridade também no banco, não só na aplicação). |
| 1.3 | Refinada a Seção 1 (Technical Language): cabeçalhos e comentários explicativos dos scripts SQL passam a ser em português; apenas identificadores técnicos seguem o inglês. Adicionado à Seção 9 o requisito de Row Level Security (RLS) habilitado em toda tabela do schema `public`. Preenchida a Seção 10 (Migration Standards): uso exclusivo do SQL Editor (nunca o menu visual), Padrão Oficial de Queries SQL (Número/Nome/Descrição/Cabeçalho/SQL/Validação, com modelo de cabeçalho incluindo Versão) e execução validada passo a passo. |