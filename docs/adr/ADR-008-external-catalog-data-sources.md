# ADR-008 — External Catalog Data Sources

| Campo | Valor |
|--------|-------|
| **ADR** | ADR-008 |
| **Título** | External Catalog Data Sources |
| **Status** | Aprovado |
| **Data** | 2026-07 |
| **Decisores** | Project Mimikyu |
| **Decisão** | Nenhuma API externa será a proprietária lógica do catálogo do Project Mimikyu. APIs externas atuam exclusivamente como fontes de importação/sincronização; o catálogo interno permanece soberano. |
| **Documentos Relacionados** | `../02-architecture-principles.md`, `ADR-006-separation-of-catalog-ownership-and-analytics.md`, `../06-pipeline-importacao.md` |

---

# Context

Foi pesquisado se a The Pokémon Company mantém uma API oficial documentada para integração de sistemas externos. A empresa mantém um banco de cartas pesquisável publicamente (por nome, expansão, tipo e outros atributos), mas não foi encontrada evidência pública de uma API oficial documentada para esse fim.

Existem APIs amplamente utilizadas por desenvolvedores para dados de Pokémon TCG, mas são projetos independentes, não mantidos pela The Pokémon Company:

- **Pokémon TCG API** — disponibiliza Cards e Sets em JSON via REST; o serviço informa que passou a integrar a plataforma Scrydex.
- **TCGdex** — oferece dados multilíngues, incluindo estrutura de Sets, Cards e traduções por idioma, via REST e GraphQL.

Não se deve assumir que sites ou ferramentas de terceiros consultam diretamente uma API oficial da The Pokémon Company — é mais provável que utilizem uma base própria, uma API independente, ou uma combinação de fontes.

---

# Decision

O Project Mimikyu manterá registros próprios e independentes das seguintes entidades do Catálogo Editorial:

- Game;
- Expansion;
- Set;
- Card;
- Card Translation;
- Card Variant.

Qualquer fonte de dados externa (API pública, base de terceiros, ou outra origem) será tratada exclusivamente como uma fonte de importação, segundo o padrão:

```text
External Data Source
        ↓
Import / Synchronization
        ↓
Project Mimikyu Catalog
```

Nenhuma API externa será uma dependência estrutural em tempo real do catálogo. O catálogo interno permanece soberano, conforme já estabelecido pelo princípio AP-006 e por ADR-006.

---

# Consequences

## Benefícios

- permite corrigir dados inconsistentes vindos de fontes externas;
- permite complementar informações ausentes;
- preserva os registros do catálogo caso uma fonte externa seja descontinuada;
- permite integrar mais de uma fonte de dados simultaneamente;
- mantém controle sobre os códigos internos do catálogo;
- permite registrar a procedência (fonte) de cada informação importada.

## Restrições

- toda integração com fonte externa deve passar por uma camada de importação/sincronização, nunca por consulta direta em tempo real substituindo o catálogo interno;
- os mecanismos concretos de importação e sincronização serão detalhados em `06-pipeline-importacao.md`.

---

# Alternatives Considered

## Consultar uma API externa diretamente como fonte de verdade do catálogo

Rejeitada por tornar o Project Mimikyu dependente da disponibilidade, formato e continuidade de um serviço de terceiros, além de impedir a correção de inconsistências e a integração de múltiplas fontes.

---

# Related Documents

- `../02-architecture-principles.md`
- `ADR-006-separation-of-catalog-ownership-and-analytics.md`
- `../06-pipeline-importacao.md`

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Registro da decisão de soberania do catálogo interno sobre fontes de dados externas. |
