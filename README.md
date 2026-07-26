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
- Supabase (Auth, Storage, Edge Functions, Supabase SSR)
- Next.js
- React
- TypeScript
- Tailwind CSS
- GitHub
- Visual Studio Code

---

# Estrutura do Repositório

```text
web/           Aplicação web (Next.js/React)
docs/          Documentação oficial
database/      Registro versionado do SQL já executado no Supabase
supabase/      Código confirmado deployado das Edge Functions
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
| [Roadmap](docs/ROADMAP.md) | Trajetória macro do projeto (concluído/em andamento/direção futura). |
| [Project Charter](docs/00-project-charter.md) | Missão, visão e princípios do projeto. |
| [Technical Identity](docs/01-technical-identity.md) | Identidade técnica permanente da plataforma. |
| [Architecture Principles](docs/02-architecture-principles.md) | Princípios que orientam decisões arquiteturais. |
| [Documentation Architecture](docs/03-documentation-architecture.md) | Organização e governança da documentação. |
| [Domain Model](docs/04-domain-model.md) | Modelo conceitual do domínio. |
| [Modelo de Dados](docs/05-modelo-de-dados.md) | Modelo lógico e físico (SQL) de cada entidade. |
| [Pipeline de Importação](docs/06-pipeline-importacao.md) | Estratégia de importação e sincronização de fontes externas. |
| [Catálogo Editorial](docs/07-catalogo-editorial.md) | Estratégia de captura e disponibilização de dados do catálogo. |
| [ADRs](docs/adr/ADR-INDEX.md) | Registro das decisões arquiteturais. |
| [Standards](docs/standards/STD-INDEX.md) | Padrões permanentes de implementação e documentação. |

---

# Estado do Projeto

**Fase 1 — Arquitetura Conceitual:** Concluída.

**Fase 2 — Modelo Lógico:** Em andamento. Sub-Fase 1 (Catálogo Editorial) com Bloco A (Modelo de Dados) concluído — 7 Card Sets, 927 Cards catalogadas — e Bloco B (Pipeline de Importação) concluído para as 5 coleções originais (859 cartas, 1.718 imagens, `en`+`pt-BR`, 0 falhas). Sub-Fase 2 (Coleções) ainda não iniciada.

Ver [`docs/README.md`](docs/README.md#status-atual-do-projeto) para o status detalhado e atualizado — fonte única, não duplicada aqui.

---

# Licença

Distribuído sob a licença [MIT](LICENSE).