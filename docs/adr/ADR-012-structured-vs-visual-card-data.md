# ADR-012 — Structured vs. Visual-Only Card Data

| Campo | Valor |
|--------|-------|
| **ADR** | ADR-012 |
| **Título** | Structured vs. Visual-Only Card Data |
| **Status** | Aprovado |
| **Data** | 2026-07 |
| **Decisores** | Project Mimikyu |
| **Decisão** | Nem toda informação de uma Card precisa de campo estruturado desde a primeira versão. Uma informação só recebe estrutura própria quando for necessária para identificação, pesquisa, organização, progresso da coleção ou uma funcionalidade comercial concreta. As demais permanecem disponíveis apenas através da imagem oficial da Card. |
| **Documentos Relacionados** | `../04-domain-model.md`, `../07-catalogo-editorial.md`, `ADR-011-pokemon-tcg-domain-scope.md` |

---

# Context

Uma Card carrega dezenas de informações (HP, ataques, habilidades, fraqueza, resistência, custo de recuo, estágio evolutivo, texto de regras, entre outras). Estruturar todas elas como campos próprios no banco de dados desde a primeira versão aumentaria significativamente o volume de cadastro, a dependência de APIs externas completas, o risco de erros de importação, o custo de validação e o tempo necessário para disponibilizar novos Sets no catálogo.

Ao mesmo tempo, o Project Mimikyu já planeja armazenar ou referenciar a imagem oficial de cada Card. Essa imagem, por si só, já preserva visualmente informações como HP, ataques, habilidades, fraqueza, resistência, custo de recuo, estágio evolutivo, texto de efeito, ilustrador, marca de regulamentação e demais elementos gráficos — mesmo que esses dados não estejam estruturados em campos próprios.

Isso evidenciou uma distinção arquitetural importante: **a informação pode estar disponível no sistema sem precisar estar estruturada no banco de dados.** Ter a imagem não equivale, tecnicamente, a possuir os dados estruturados — por exemplo, o sistema não consegue responder "mostre todas as Cards com HP superior a 150" apenas por possuir a imagem; isso exige um campo `hp` pesquisável.

---

# Decision

Adota-se um modelo de três níveis de disponibilidade da informação:

## 1. Structured Data (Dados Estruturados)

Informações armazenadas em campos próprios, utilizáveis diretamente em filtros, regras e relatórios.

Estruturados desde a primeira versão: Set, Number, Category, Trainer Subcategory, Rarity, Pokémon reference, Available Finishes (Card Finish), Translations (Card Translation), Image reference.

## 2. Visual Source (Fonte Visual)

A imagem oficial da Card. Permite que o usuário veja informações que não foram estruturadas, mas o sistema não consegue pesquisá-las ou utilizá-las automaticamente em regras.

Permanecem apenas na imagem, na primeira versão: HP, Attacks, Abilities, Weakness, Resistance, Retreat Cost, Evolution Stage, Detailed Rules Text (Effect).

## 3. Extracted Data (Dados Extraídos)

No futuro, informações hoje disponíveis apenas na imagem poderão ser convertidas em dados estruturados por importação de APIs, processamento automatizado, reconhecimento de imagem, revisão manual ou enriquecimento progressivo do catálogo. Essa extração é uma possibilidade de evolução, não uma obrigação da primeira versão.

## Critério para estruturar uma informação

> Uma informação da Card só deverá receber estrutura própria quando for necessária para identificação, pesquisa, organização, progresso da coleção ou uma funcionalidade comercial concreta.

A pergunta a ser feita nunca é "temos ou não temos essa informação?" — é sempre: **"essa informação precisa ser pesquisável, filtrável, validável ou utilizada em regras do produto?"** Se a resposta for não, a imagem é suficiente por ora.

---

# Consequences

## Benefícios

- reduz volume de cadastro e dependência de APIs externas completas na primeira versão;
- reduz erros de importação e custo de validação;
- reduz complexidade do modelo físico inicial;
- reduz o tempo necessário para disponibilizar novos Sets no catálogo;
- preserva a informação (via imagem) mesmo quando não estruturada — nada é perdido, apenas adiado;
- permite evolução incremental: campos podem ser estruturados posteriormente sob demanda real (AP-004).

## Restrições

- funcionalidades que dependam de busca ou filtro por um campo hoje não-estruturado (ex.: "buscar Cards com HP acima de X") não estarão disponíveis até que esse campo seja estruturado;
- a lista de campos estruturados nesta ADR reflete a primeira versão e deve ser revisada quando uma funcionalidade concreta exigir um novo campo estruturado.

---

# Alternatives Considered

## Estruturar todos os campos de todas as Cards desde a primeira versão

Rejeitada por aumentar significativamente volume de cadastro, dependência de fontes externas completas, risco de erro de importação e tempo de disponibilização de novos Sets, sem benefício imediato comprovado para o produto.

## Não estruturar nenhum campo além da imagem

Rejeitada por impedir funcionalidades essenciais do produto, como identificar a posição da carta no Set, sua raridade, seus acabamentos disponíveis, e o progresso de conclusão da coleção.

---

# Related Documents

- `../04-domain-model.md`
- `../07-catalogo-editorial.md`
- `ADR-011-pokemon-tcg-domain-scope.md`

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Registro do modelo de três níveis de disponibilidade de informação e do critério de estruturação de campos da Card. |
