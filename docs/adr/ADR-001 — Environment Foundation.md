# ADR-001 — Environment Foundation

| Campo | Valor |
|--------|-------|
| **Documento** | ADR-001 — Environment Foundation |
| **Arquivo** | `docs/adr/ADR-001-environment-foundation.md` |
| **Versão** | 1.0 |
| **Status** | Aprovado |
| **Categoria** | Infrastructure |
| **Objetivo** | Registrar a decisão arquitetural referente à fundação do ambiente do Project Mimikyu no Supabase. |
| **Escopo** | Organização inicial da infraestrutura do projeto. |
| **Dependências** | `01-technical-identity.md` |
| **Documentos Relacionados** | `ADR-002-infrastructure-region.md` |

---

# Context

O Project Mimikyu necessitava de uma infraestrutura moderna, escalável e de baixo custo para servir como base para todo o desenvolvimento da plataforma.

Como primeiro passo, foi necessário definir a forma de organização do ambiente no Supabase.

---

# Decision

Foi adotada uma organização do tipo **Personal** para hospedar o projeto.

Essa decisão estabelece que, durante a fase inicial de desenvolvimento, toda a administração da infraestrutura será centralizada em uma única conta responsável pelo projeto.

---

# Rationale

A opção **Personal** atende integralmente às necessidades da fase atual do Project Mimikyu, oferecendo simplicidade administrativa e acesso a todos os recursos necessários para o desenvolvimento da solução.

A decisão não impõe restrições arquiteturais ao sistema e poderá ser revisada futuramente caso a evolução do projeto exija colaboração administrativa ou novos modelos de governança.

---

# Consequences

## Positivas

- Configuração inicial simplificada.
- Menor complexidade administrativa.
- Infraestrutura pronta para o desenvolvimento imediato.
- Possibilidade de evolução futura sem impacto na arquitetura da aplicação.

## Negativas

- Administração concentrada em uma única conta durante a fase inicial do projeto.

---

# Status

**Aceita e implementada.**

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Criação inicial do documento. |