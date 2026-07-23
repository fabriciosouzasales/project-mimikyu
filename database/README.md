# Database

Esta pasta contém o **registro versionado** das Queries SQL já executadas no banco físico do Project Mimikyu (Supabase, projeto `mimikyu-core`), organizadas seguindo a mesma faixa de numeração definida em `docs/standards/STD-001-database-standards.md`, Seção 10.

## O que esta pasta é

Uma cópia fiel, em arquivo `.sql`, de cada Query já executada com sucesso no Supabase — a mesma fonte de verdade documentada em prosa em `docs/05-modelo-de-dados.md`, aqui em formato executável e versionado pelo Git.

## O que esta pasta não é

**Não é** um sistema de migration automatizado. A execução real continua acontecendo manualmente no SQL Editor do Supabase, uma Query por vez, validada antes de avançar (ver STD-001, Seção 10 — "uso exclusivo do SQL Editor, nunca o menu visual"). Os arquivos aqui são copiados **depois** da execução confirmada, como registro histórico — nunca antes.

## Estrutura

```text
database/
├── schema/          Queries de criação de tabela e trigger (faixa 100-699, por módulo)
├── functions/        Funções compartilhadas (ex.: set_updated_at())
├── migrations/        Alterações em estruturas já existentes (ex.: 122 - Adapt Card Set for Promo)
├── seeds/             Queries de carga de dados (faixa 800-899)
├── validations/        Queries de validação (faixa 900-999)
├── reference-data/     Reservado para dados de referência estáticos (ainda vazio)
└── diagrams/           Reservado para diagramas físicos do banco (ainda vazio)
```

## Regra de manutenção

Sempre que uma nova Query for executada e confirmada no Supabase (ver o fluxo em `docs/05-modelo-de-dados.md`), o mesmo SQL deve ser copiado para o subdiretório correspondente aqui, com o cabeçalho oficial completo (Projeto/Query/Versão/Autor/Data/Descrição/Regras de Negócio — ver STD-001, Seção 10). Isso evita que o histórico de execução exista apenas dentro do Supabase ou embutido em prosa na documentação.

## Queries `CANÔNICA` vs. `MIGRATION`

Desde a adoção do **Princípio da Fonte Canônica** (STD-001, Seção 10), o cabeçalho de cada Query passou a incluir um campo `Status`, que pode ser:

- **`CANÔNICA`** — representa a forma correta e definitiva de criar aquela estrutura em uma instalação nova. É a versão que deve ser executada do zero.
- **`MIGRATION`** — Query histórica, que alterou um banco já existente. Não faz parte do fluxo de instalação limpa; preservada apenas para rastreabilidade de como o banco atual chegou ao seu estado.

Quando uma Query originalmente `CANÔNICA` precisa de uma correção permanente, ela é reescrita **no mesmo arquivo/número, com a versão incrementada** (ex.: `120` v1.0 → v2.0) — não é criada uma nova migration corretiva encadeada. Migrations que já introduziram essa correção em um banco pré-existente (ex.: `122`) são então reclassificadas retroativamente como `MIGRATION` e mantidas apenas como histórico.

**Atenção:** atualizar uma Query `CANÔNICA` neste repositório é uma alteração de arquivo/documentação — **não executa nada automaticamente contra o Supabase**. Um banco já construído pelo caminho antigo (versão anterior + migration) só reflete a nova versão canônica se a diferença entre elas for confirmada e, se necessário, aplicada manualmente. Ver o primeiro exemplo real desse cuidado em `docs/05-modelo-de-dados.md`, seção Set (índice `uq_card_set_expansion_promo`, cujo status no banco físico atual permanece não confirmado).
