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

## Correção real à convenção de `code`/`name` (não ao mecanismo geral)

**O mecanismo geral desta ADR permanece válido**: cartas promocionais continuam sendo um `card_set` do tipo `PROMO`, sem entidade separada. O que estava errado era a convenção fixa de preenchimento de `code`/`name` (tabela acima: "código da Expansion + `0`") — ela gera um identificador **sintético**, sem correspondência em nenhuma fonte externa real, o que impediu a Migration `910`/`241` de mapear `ME0` a qualquer coisa (ver `05-modelo-de-dados.md`, "Migration 251"). Uma investigação real (cruzando TCGdex, TCGCodex e fontes de referência da comunidade) encontrou o identificador oficial verdadeiro: **`MEP`** ("Mega Evolution Black Star Promos", TCGdex `mep`) — um Set irmão de `ME1`-`ME4` dentro da Expansion `ME`, cobrindo cartas promocionais de toda a era (não apenas da `ME1`), mesmo padrão já usado pela Pokémon Company em outras eras (ex.: `SVP` para Scarlet & Violet).

**Convenção corrigida**: `code`/`name` de um Set `PROMO` não são mais derivados por uma fórmula fixa — devem usar o identificador oficial real, quando existir (pesquisado antes de cadastrar o Set), seguindo o novo `AP-018` (`02-architecture-principles.md`). Quando nenhum identificador oficial for encontrável, a fórmula "código da Expansion + `0`" pode voltar a servir como fallback temporário, mas o Set deve ser tratado como provisório até a pesquisa ser feita — nunca cadastrado como definitivo sem essa checagem.

## Convenção de `release_order` atualizada — coexistência com Set de Energia

**Decisão real de Fabrício, ainda NÃO executada**: quando uma Expansion tem tanto um Set de Energia (ex.: `MEE`) quanto um Set `PROMO` (ex.: `MEP`), o Set de Energia vem primeiro: `release_order = 1` para o Set de Energia, `release_order = 2` para o `PROMO`, Sets regulares a partir de `3`, na ordem oficial de lançamento. Isso refina a regra original desta ADR (`release_order` sempre `1` para `PROMO`) para o caso em que mais de um Set especial coexiste na mesma Expansion — a regra original permanece válida quando `PROMO` é o único Set especial existente.

O Set de Energia em si (`MEE`) não é modelado por esta ADR — ao contrário do `PROMO`, um Set de Energia da TCGdex é um produto editorial fechado, com identificador e conteúdo próprios, não uma convenção de preenchimento fixo. Fica para a modelagem real de `MEE` (ainda não iniciada) decidir se ele usa `set_type = REGULAR`/`SPECIAL` ou se justifica um novo valor de `set_type`.

**Atualização (revisão `1.6`): decidido que `MEE` usa um novo valor de `set_type`, não `REGULAR`/`SPECIAL`.** `ENERGY` foi adicionado ao domínio de `set_type` (Migration `263`, CONFIRMADA EXECUTADA — ver `05-modelo-de-dados.md`, seção Set/Card Set, "Migration `263`–`264`"), e o `release_order` de `ME1`-`ME4` já foi reorganizado (Migration `264`, CONFIRMADA EXECUTADA) para liberar as posições `1`/`2` da convenção acima. `MEE`/`MEP` em si ainda não foram inseridos como registros — apenas o domínio e o espaço de `release_order` foram preparados.

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

- **Executado.** Os cinco Sets já cadastrados (`ME1`–`ME4`) permaneceram corretos e não precisaram ser recriados. A migration `122 - Adapt Card Set for Promo` (nome real, não "Promo Series") foi executada dentro de uma transação (`BEGIN`/`COMMIT`): ampliou `set_type` para incluir `PROMO`, deslocou o `release_order` dos cinco Sets existentes em duas etapas (evitando violar a constraint `UNIQUE` durante a operação) e adicionou a constraint `ck_card_set_promo_size`. O registro `ME0 — ME Black Star Promos` foi inserido pela Query `821 - Seed Promo Card Set`, com `base_set_size = total_set_size = 89` (quantidade real informada por Fabrício). Confirmado por validação (`920`, versão 2.0) — ver `05-modelo-de-dados.md`, seção Set.
- **Divergência entre o recomendado e o executado — corrigida na definição canônica, ainda não confirmada no banco físico:** esta ADR recomendava um índice único parcial (`CREATE UNIQUE INDEX ... WHERE set_type = 'PROMO'`) para impedir mais de uma série promocional por Expansion ao nível do banco. A migration `122` efetivamente executada não incluiu esse índice. Com a adoção do **Princípio da Fonte Canônica** (STD-001, Seção 10), a Query `120 - Create Card Set Table` foi consolidada para `Versão 2.0` (Status `CANÔNICA`) já incluindo o índice — ver `05-modelo-de-dados.md`, seção Set, "Modelo Físico — Versão Canônica (2.0)". **Isso resolve a divergência na definição, não necessariamente na instância física atual:** o banco em produção foi construído pelo caminho antigo (`120` v1.0 + migration `122`), e a atualização da Query canônica foi feita no repositório/documentação, não reexecutada contra o Supabase. O status real do índice no banco físico permanece **não confirmado** — não presumir que existe.
- a atualização de `base_set_size`/`total_set_size` da série promocional conforme novas cartas são catalogadas não é automatizada nesta fase — depende da existência da tabela `card`;
- esta ADR não define regras específicas sobre a própria Card promocional (numeração, se possui código próprio de carta, etc.) — isso fica para a modelagem da entidade Card, próximo ciclo;
- **Resolvida:** a Query `820 - Seed Card Set` foi reescrita para `Versão 2.0` (Status `CANÔNICA`), consolidando `ME0`–`ME4` em um único snapshot com `ON CONFLICT ... DO UPDATE` — ver `05-modelo-de-dados.md`, seção Set, "Seed — Versão Canônica (2.0)". As Queries `122` e `821`, que originalmente introduziram o suporte a `PROMO` em um banco já existente, foram reclassificadas como Status `MIGRATION`: preservadas para rastreabilidade, mas fora do fluxo de instalação limpa (uma instalação nova executa apenas `120` v2.0 e `820` v2.0).

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
| 1.1 | Registrada a execução real: migration `122 - Adapt Card Set for Promo` (nome corrigido) executada em transação; Seed `821` inseriu `ME0` com `base_set_size = total_set_size = 89`; validação `920` v2.0 confirmada. Sinalizada divergência entre o índice único parcial recomendado (não implementado) e o que foi de fato executado. Adicionada pendência da reescrita de `820` para incluir o Set promocional no snapshot completo. |
| 1.2 | Registrada a adoção do Princípio da Fonte Canônica (STD-001, Seção 10): `120` e `820` consolidadas para `Versão 2.0` (Status `CANÔNICA`) — `120` v2.0 já inclui o índice único parcial antes divergente; `820` v2.0 consolida `ME0`–`ME4` em um único snapshot com `ON CONFLICT ... DO UPDATE`. `122` e `821` reclassificadas como Status `MIGRATION` (históricas). Pendência da reescrita de `820` marcada como resolvida. Divergência do índice único parcial marcada como resolvida na definição canônica, mas com status no banco físico atual ainda não confirmado. |
| 1.3 | **Registrada a remoção real do único registro `PROMO` existente (`ME0`), via Migration `251` — ver `05-modelo-de-dados.md`, seção "Migration 251 — Remoção de ME0", para o histórico completo.** Fabrício confirmou, com conhecimento direto do domínio, que `ME0` (interno) e o Set `mee` da TCGdex não têm relação — coleções diferentes, apesar do código semelhante. `ME0` foi removida de `card_set` até que exista uma fonte externa homologada para seu conteúdo. **O mecanismo geral desta ADR (Set `PROMO` sem entidade separada, convenção fixa de preenchimento) permanece válido e não foi revisto** — apenas seu único exemplo concreto até agora deixou de existir fisicamente no banco. Pendência nova: a Query `820` v2.0 (canônica) ainda insere `ME0` em uma instalação nova; precisa ser reescrita. |
| 1.4 | **Encontrado o identificador oficial real da série promocional: `MEP` (Mega Evolution Black Star Promos, TCGdex `mep`), respondendo a pergunta deixada em aberto pela Migration `251`.** O mecanismo geral (Set `PROMO`, sem entidade separada) permanece válido e correto — o erro real estava apenas na convenção de preenchimento de `code`/`name` ("código da Expansion + `0`"), que produzia um identificador sintético sem correspondência externa. Convenção corrigida: usar o identificador oficial real, quando pesquisável, em vez da fórmula fixa (ver nova seção "Correção real à convenção de `code`/`name`", acima, e novo `AP-018`). Recadastro de `MEP` planejado, **ainda NÃO executado nesta revisão** — ver `05-modelo-de-dados.md`, "Migration 251", seção "Investigação de acompanhamento". |
| 1.5 | **Convenção de `release_order` refinada para o caso de coexistência com um Set de Energia**: Energia primeiro (`1`), `PROMO` em seguida (`2`), regulares depois — decisão real de Fabrício, motivada pela decisão de também cadastrar `MEE` (Set de Energia da Expansion `ME`), ainda NÃO executada. A regra original (`PROMO` sempre `1`) continua válida quando não há Set de Energia. O Set de Energia em si não é modelado por esta ADR — fica para a modelagem real de `MEE` decidir seu `set_type`. |
| 1.6 | **Primeira execução real da preparação para `MEE`/`MEP`**: `ENERGY` adicionado ao domínio de `set_type` (Migration `263`, CONFIRMADA EXECUTADA) e `release_order` de `ME1`-`ME4` reorganizado para `3`-`7` (Migration `264`, CONFIRMADA EXECUTADA), liberando as posições `1`/`2` conforme a convenção da revisão `1.5`. Decidido, durante a auditoria estrutural que precedeu as migrations, que `MEE` usa um novo valor de `set_type` (`ENERGY`), não `REGULAR`/`SPECIAL` — resolve a questão deixada em aberto na revisão `1.5`. Refatoração de `set_type` em duas dimensões (natureza editorial vs. natureza do conteúdo) cogitada e deliberadamente adiada por Fabrício, registrada como possível ADR futura. `MEE`/`MEP` em si **ainda NÃO cadastrados** — ver `05-modelo-de-dados.md`, "Migration `263`–`264`", para o histórico completo. |
| 1.7 | **`MEE`/`MEP` CONFIRMADOS EXECUTADOS (Migrations `265`–`268`)** — ambos cadastrados com dados editoriais reais (não presumidos), `MEP` com `card_set_external_reference` confirmada (TCGdex, `mep`), `MEE` deliberadamente ainda sem referência externa (nenhuma fonte oficial equivalente encontrada). `MEP`: identificador/nome oficiais confirmados via TCGdex (`mep`/`MEP Black Star Promos`), contagem real de cartas corrigida de uma estimativa inicial (`52`) para o valor confirmado via API (`60`). Esclarecida a semântica de `base_set_size = total_set_size` para `PROMO`/`ENERGY`: representa uma fotografia da contagem oficialmente conhecida no momento, não um conjunto fechado — para Sets evolutivos, ambos os campos devem ser atualizados a cada nova carta catalogada (regra operacional ainda não formalizada). Ver `05-modelo-de-dados.md`, "Migration `265`–`268`", e `02-architecture-principles.md`, `AP-018` revisão `1.8` (nomes de entidades editoriais devem espelhar a fonte oficial consultada, não ser traduzidos). |
| 1.8 | **Gap canônico corrigido (2026-07-31): `database/schema/120_create_card_set_table.sql` nunca tinha incorporado a Migration `263` (`ENERGY` em `ck_card_set_type`), apesar de confirmada executada em produção desde 2026-07-26.** Descoberto ao construir `admin_create_card_set()` (ADR-023, Query `2051`) e perceber que a validação da função só cobria `REGULAR`/`SPECIAL`/`PROMO` — uma instalação nova a partir da v2.1 do arquivo canônico ficaria divergente da produção real. Reconciliado: `120` bump para v2.2, `ck_card_set_type` agora inclui `ENERGY` no arquivo canônico, batendo com o que a migration `263` já garantia fisicamente. Nenhuma mudança de comportamento no banco real (a migration já estava aplicada) — só correção da fonte canônica para instalações novas. |
