# ADR-015 — Promotional Card Set Model (Black Star Promos)

| Campo | Valor |
|--------|-------|
| **ADR** | ADR-015 |
| **Título** | Promotional Card Set Model (Black Star Promos) |
| **Status** | Aprovado |
| **Data** | 2026-07 |
| **Decisores** | Project Mimikyu |
| **Decisão** | Cartas promocionais (Black Star Promos) não recebem uma entidade própria (`promo_set`/`promo_series`). Elas são registradas como um `card_set` do tipo `PROMO`, vinculado diretamente à sua Expansion, seguindo uma convenção fixa de preenchimento em vez de campos opcionais: código = código da Expansion + `0`; nome = código da Expansion + `Black Star Promos`; primeira posição na sequência de Sets da Expansion (`release_order = 1`, deslocando os demais); mesma data de lançamento do primeiro Set regular/especial da Expansion; `base_set_size = total_set_size`, representando a quantidade atualmente conhecida de cartas promocionais (não uma quantidade editorial fechada). |
| **Documentos Relacionados** | `../04-domain-model.md`, `../05-modelo-de-dados.md`, `ADR-003-multi-tcg-architecture.md`, `ADR-004-set-identity.md` |

---

# Context

Antes de iniciar a modelagem da entidade Card — apontada como a mais complexa e importante do catálogo — Fabrício identificou uma observação que muda a forma do modelo de `card_set`: existe um conjunto de cartas, as **cartas promocionais (Black Star Promos)**, diretamente ligadas a uma Expansion, mas sem as características de um Set editorial tradicional:

- não possuem necessariamente um código oficial próprio;
- não possuem necessariamente um nome oficial próprio;
- não ocupam uma posição fixa na sequência editorial de Sets da Expansion;
- não possuem uma quantidade de cartas fechada — a quantidade cresce ao longo do tempo, conforme novos produtos daquela Expansion são lançados.

Sem tratar esse caso antes de criar `card`, toda carta promocional ficaria sem um Set ao qual se vincular, ou forçaria uma modelagem alternativa (uma segunda chave estrangeira em `card`) que se propagaria para praticamente todo o restante do sistema.

---

# Decision

## Sem entidade separada

Não foi criada uma entidade `promo_set`/`promo_series`. Essa alternativa obrigaria `card` a ter dois relacionamentos possíveis (`card_set_id` ou `promo_series_id`), e essa duplicidade se propagaria para coleção, inventário, traduções, imagens, consultas, relatórios e importações — o mesmo tipo de complexidade estrutural permanente que o Project Mimikyu evita por princípio (ver AP-004, AP-016).

## `card_set` generalizado com um terceiro tipo: `PROMO`

`card_set` passa a representar um **contêiner editorial numerado de cartas**, com três tipos possíveis: `REGULAR`, `SPECIAL`, `PROMO`. Uma série promocional Black Star é registrada como um `card_set` comum, vinculado à sua Expansion, do tipo `PROMO`, usando os mesmos campos dos demais Sets — mas com uma convenção de preenchimento fixa, não com campos nulos:

| Campo | Regular / Especial | Promocional (`PROMO`) |
|-------|--------------------|-------------------------|
| `expansion_id` | obrigatório | obrigatório |
| `code` | código oficial próprio | código da Expansion + `0` (ex.: `ME0`) |
| `name` | nome oficial próprio | código da Expansion + `Black Star Promos` (ex.: `ME Black Star Promos`) |
| `set_type` | `REGULAR` ou `SPECIAL` | `PROMO` |
| `release_order` | posição própria na sequência | sempre `1` (primeiro Set da Expansion; os demais são deslocados) |
| `release_date` | data própria | mesma data do primeiro Set regular/especial da Expansion |
| `base_set_size` | quantidade base fechada | igual a `total_set_size` — quantidade atualmente conhecida de cartas promocionais |
| `total_set_size` | quantidade total fechada | igual a `base_set_size` — cresce conforme novas cartas promocionais são catalogadas |

Uma primeira proposta considerada tornava `code`, `name`, `release_order`, `release_date`, `base_set_size` e `total_set_size` opcionais (`NULL`) para `PROMO`. Essa proposta foi **descartada em favor da convenção fixa acima**: com valores sempre determináveis a partir da Expansion, a série promocional deixa de ser uma exceção estrutural (campos nulos, regras condicionais complexas) e passa a ser um `card_set` plenamente formado, exigindo apenas que a constraint de `set_type` seja ampliada para aceitar `PROMO`.

## Unicidade

Cada Expansion pode ter, no máximo, uma série promocional (`UNIQUE (expansion_id) WHERE set_type = 'PROMO'`, via índice único parcial — necessário porque `UNIQUE (expansion_id, code)` sozinho não impediria duas séries promocionais com o mesmo `code` derivado).

## Quantidade variável, não uma quantidade "secreta"

Diferente de um Set fechado (onde `secret_set_size = total_set_size - base_set_size` é uma quantidade editorial real), em `PROMO` a igualdade `base_set_size = total_set_size` é deliberada — não há cartas "acima da base", apenas uma contagem que se atualiza conforme o catálogo cresce. Quando a entidade Card existir, essa contagem poderá ser validada contra `COUNT(card.id)` daquele Set; a atualização automática não é implementada nesta fase, por ainda não existir a tabela `card` (ver `05-modelo-de-dados.md`, seção Set).

---

# Consequences

## Benefícios

- toda Card permanece vinculada a um único tipo de entidade-pai (`card_set`), sem relacionamento alternativo — nenhuma duplicidade se propaga para coleção, inventário, traduções, imagens ou importações;
- as regras de negócio já existentes (`UNIQUE (expansion_id, code)`, `UNIQUE (expansion_id, release_order)`, obrigatoriedade de `code`/`name`/`release_order`/`base_set_size`/`total_set_size`) continuam válidas sem exceção, porque a convenção fixa sempre produz um valor determinável — não é necessário relaxar nenhuma dessas colunas para `NULL`;
- a única mudança estrutural necessária em `card_set` é ampliar a constraint de `set_type` para aceitar `PROMO` e adicionar a regra `PROMO → base_set_size = total_set_size`.

## Restrições / Pendências

- os cinco Sets já cadastrados (`ME1`–`ME4`) permanecem corretos e não precisam ser recriados; é necessária apenas uma migration (`122 - Adapt Card Set for Promo Series`) para ampliar `set_type`, deslocar `release_order` dos Sets existentes (`+1`, para abrir espaço para `ME0` na posição `1`) e adicionar a regra condicional de quantidades — ainda não executada (ver `05-modelo-de-dados.md`, seção Set);
- a atualização de `base_set_size`/`total_set_size` da série promocional conforme novas cartas são catalogadas não é automatizada nesta fase — depende da existência da tabela `card`;
- esta ADR não define regras específicas sobre a própria Card promocional (numeração, se possui código próprio de carta, etc.) — isso fica para a modelagem da entidade Card, próximo ciclo.

---

# Alternatives Considered

## Criar uma entidade separada (`promo_set` ou `promo_series`)

Rejeitada por forçar `card` a ter dois relacionamentos possíveis com sua entidade-pai, propagando duplicidade para todo o restante do sistema (coleção, inventário, traduções, imagens, consultas, relatórios, importações).

## Tornar `code`, `name`, `release_order`, `release_date`, `base_set_size` e `total_set_size` opcionais em `card_set`

Considerada e desenvolvida inicialmente (índice único parcial para `code IS NULL`, regras condicionais por tipo), mas descartada em favor da convenção fixa de preenchimento: como todos os valores de uma série promocional são determináveis a partir da Expansion à qual pertence, não há necessidade real de permitir valores nulos — a convenção fixa é mais simples e mantém as constraints originais intactas.

---

# Related Documents

- `../04-domain-model.md`
- `../05-modelo-de-dados.md`
- `ADR-003-multi-tcg-architecture.md`
- `ADR-004-set-identity.md`

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Registro da decisão: cartas promocionais (Black Star Promos) modeladas como `card_set` do tipo `PROMO`, sem entidade separada, usando uma convenção fixa de preenchimento (não campos nulos). Documentada a proposta intermediária de campos opcionais, descartada em favor da convenção fixa. |
