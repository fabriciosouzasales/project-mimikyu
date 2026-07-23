# Project Mimikyu

> Plataforma profissional para gerenciamento de coleções de Trading Card Games (TCG), iniciando pelo Pokémon TCG.

---

# Visão Geral

O Project Mimikyu é um projeto de software desenvolvido com foco em arquitetura sólida, escalabilidade e qualidade de engenharia.

O objetivo é construir uma plataforma capaz de gerenciar coleções de Trading Card Games, iniciando pelo Pokémon TCG, preparada para evolução contínua e futura comercialização.

---

# Objetivos

- Desenvolver uma plataforma profissional para gerenciamento de coleções TCG.
- Priorizar arquitetura e qualidade antes da implementação de funcionalidades.
- Documentar todas as decisões relevantes do projeto.
- Manter uma base de conhecimento única, versionada e rastreável.

---

# Tecnologias

- PostgreSQL
- Supabase
- GitHub
- Visual Studio Code

---

# Estrutura do Repositório

```text
docs/          Documentação oficial
database/      Registro versionado do SQL já executado no Supabase
assets/        Recursos do projeto (ex.: fontes primárias de dados)
scripts/       Scripts auxiliares
vscode/        Configurações do ambiente
archive/       Materiais históricos
```

---

# Documentação

A documentação oficial completa, incluindo o guia de retomada para uma nova sessão de IA, está em [`docs/README.md`](docs/README.md).

| Documento | Descrição |
|-----------|-----------|
| [Project Charter](docs/00-project-charter.md) | Missão, visão e princípios do projeto. |
| [Technical Identity](docs/01-technical-identity.md) | Identidade técnica permanente da plataforma. |
| [Architecture Principles](docs/02-architecture-principles.md) | Princípios que orientam decisões arquiteturais. |
| [Domain Model](docs/04-domain-model.md) | Modelo conceitual do domínio. |
| [Modelo de Dados](docs/05-modelo-de-dados.md) | Modelo lógico e físico (SQL) de cada entidade. |
| [ADRs](docs/adr/ADR-INDEX.md) | Registro das decisões arquiteturais. |
| [Standards](docs/standards/STD-INDEX.md) | Padrões permanentes de implementação e documentação. |

---

# Estado do Projeto

**Fase 1 — Arquitetura Conceitual:** Concluída.

**Fase 2 — Modelo Lógico:** Em andamento. As entidades **Game**, **Expansion** e **Set** já têm modelo lógico, modelo físico e dados reais validados no Supabase. Próxima entidade: **Card**.

Ver [`docs/README.md`](docs/README.md#status-atual-do-projeto) para o status detalhado e atualizado.

---

# Licença

Distribuído sob a licença [MIT](LICENSE).