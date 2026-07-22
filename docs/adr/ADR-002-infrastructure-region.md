# ADR-002 — Infrastructure Region

| Campo | Valor |
|--------|-------|
| **ADR** | ADR-002 |
| **Título** | Infrastructure Region |
| **Status** | Aprovado |
| **Data** | 2026-07 |
| **Decisores** | Project Mimikyu |
| **Decisão** | Hospedar o projeto Supabase na região South America (São Paulo) — `sa-east-1`, com fuso horário de referência `America/Sao_Paulo`. |
| **Documentos Relacionados** | `../01-technical-identity.md` |

---

# Context

A região de infraestrutura do projeto Supabase influencia latência, localização operacional dos serviços e experiência dos usuários.

O Project Mimikyu é desenvolvido inicialmente no Brasil e tem como público inicial esperado usuários brasileiros. A escolha da região deveria priorizar proximidade geográfica e desempenho, sem introduzir uma arquitetura distribuída prematuramente.

---

# Decision

Hospedar o projeto principal do Supabase na região:

**South America (São Paulo) — `sa-east-1`**

A zona de tempo de referência da aplicação será:

**America/Sao_Paulo**

---

# Rationale

A região de São Paulo:

- é a opção geograficamente mais próxima do público inicial;
- reduz a latência esperada para acessos realizados no Brasil;
- mantém a infraestrutura centralizada e simples;
- atende ao horizonte inicial de evolução da plataforma.

A zona de tempo `America/Sao_Paulo` fornece uma referência explícita para regras de negócio, operações e documentação, sem substituir o uso de `timestamptz` para armazenamento de dados temporais.

---

# Consequences

## Positive

- Melhor proximidade com os usuários iniciais.
- Menor latência esperada no Brasil.
- Referência regional e temporal consistente.
- Infraestrutura simples, sem distribuição multirregional prematura.

## Trade-offs

- Usuários geograficamente distantes podem experimentar maior latência.
- Uma expansão internacional relevante poderá exigir nova avaliação arquitetural.
- A migração de região, se necessária no futuro, poderá exigir planejamento específico.

---

# Alternatives Considered

## North American Regions

Não adotadas devido à maior distância do público inicial e à ausência de benefício compensatório nesta fase.

## European or Asian Regions

Não adotadas por apresentarem distância ainda maior do público inicial e não atenderem a uma necessidade atual.

## Multi-region Architecture

Não adotada por adicionar custo e complexidade sem demanda validada.

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Registro da região oficial de infraestrutura. |
| 1.1 | Padronização do cabeçalho (adição do campo Decisão) para consistência com os demais ADRs. |
