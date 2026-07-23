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
