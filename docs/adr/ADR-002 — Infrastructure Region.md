# ADR-002 — Infrastructure Region

| Campo | Valor |
|--------|-------|
| **Documento** | ADR-002 — Infrastructure Region |
| **Arquivo** | `docs/adr/ADR-002-infrastructure-region.md` |
| **Versão** | 1.0 |
| **Status** | Aprovado |
| **Categoria** | Infrastructure |
| **Objetivo** | Registrar a decisão arquitetural referente à região da infraestrutura do Project Mimikyu. |
| **Escopo** | Definição da região principal de hospedagem do ambiente Supabase. |
| **Dependências** | `01-technical-identity.md` |
| **Documentos Relacionados** | `ADR-001-environment-foundation.md` |

---

# Context

Durante a criação do ambiente Supabase foi necessário selecionar a região física onde a infraestrutura principal da plataforma seria hospedada.

Essa decisão influencia diretamente a latência da aplicação, a experiência dos usuários e a estratégia de crescimento da plataforma.

---

# Decision

A infraestrutura principal do Project Mimikyu será hospedada na região:

**South America (São Paulo) — `sa-east-1`**

---

# Rationale

A escolha da região de São Paulo foi baseada nos seguintes fatores:

- O desenvolvimento do projeto é realizado no Brasil.
- Os primeiros usuários da plataforma estão localizados no Brasil.
- A menor latência proporciona melhor experiência durante o desenvolvimento e operação inicial.
- A região atende adequadamente ao horizonte de crescimento previsto para os próximos anos.

A estratégia adotada considera a infraestrutura necessária para os próximos **3 a 5 anos**, evitando tanto superdimensionamento quanto limitações prematuras.

---

# Consequences

## Positivas

- Menor latência para os usuários brasileiros.
- Melhor desempenho durante desenvolvimento e testes.
- Infraestrutura alinhada ao mercado inicial da plataforma.
- Não há necessidade de arquiteturas distribuídas nesta fase.

## Negativas

- Usuários de outras regiões poderão apresentar maior latência.
- Caso a plataforma passe a operar globalmente, poderão ser necessários mecanismos adicionais de distribuição, cache ou replicação geográfica.

---

# Status

**Aceita e implementada.**

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Criação inicial do documento. |