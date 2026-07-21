# ADR-001 — Environment Foundation

| Campo | Valor |
|--------|-------|
| **ADR** | ADR-001 |
| **Título** | Environment Foundation |
| **Status** | Aprovado |
| **Data** | 2026-07 |
| **Decisores** | Project Mimikyu |
| **Documentos Relacionados** | `../01-technical-identity.md` |

---

# Context

O Project Mimikyu precisava estabelecer sua fundação inicial no Supabase antes da criação dos componentes de banco de dados e demais recursos da plataforma.

O Supabase organiza projetos dentro de organizações. Para a fase inicial, o projeto é desenvolvido e administrado individualmente, sem uma equipe formal, estrutura empresarial constituída ou necessidade imediata de segregação organizacional.

Criar uma organização corporativa antecipadamente adicionaria estrutura sem resolver uma necessidade atual.

---

# Decision

Utilizar uma organização do tipo **Personal** como fundação inicial do ambiente Supabase do Project Mimikyu.

O projeto principal da plataforma será mantido nessa organização enquanto o desenvolvimento permanecer sob administração individual.

---

# Rationale

A organização Personal:

- atende integralmente à fase atual do projeto;
- reduz complexidade administrativa;
- permite criação e operação do projeto Supabase;
- não impede evolução futura;
- evita antecipar uma estrutura organizacional ainda desnecessária.

---

# Consequences

## Positive

- Configuração inicial simples.
- Menor carga administrativa.
- Compatibilidade com o estágio atual do projeto.
- Possibilidade de migração ou reorganização futura, caso surja necessidade real.

## Trade-offs

- A governança permanece centralizada em uma única conta.
- A entrada de uma equipe poderá exigir revisão de permissões ou da estrutura organizacional.
- Uma futura operação comercial poderá justificar uma organização específica.

---

# Alternatives Considered

## Team or Business Organization

Não adotada nesta fase por introduzir uma estrutura superior à necessidade atual, sem benefício operacional proporcional.

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Registro da fundação inicial do ambiente Supabase. |
