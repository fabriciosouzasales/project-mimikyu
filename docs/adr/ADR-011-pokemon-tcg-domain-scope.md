# ADR-011 — Pokémon TCG Domain Scope

| Campo | Valor |
|--------|-------|
| **ADR** | ADR-011 |
| **Título** | Pokémon TCG Domain Scope |
| **Status** | Aprovado |
| **Data** | 2026-07 |
| **Decisores** | Project Mimikyu |
| **Decisão** | O Project Mimikyu modelará as regras editoriais e colecionáveis do Pokémon TCG, sem reproduzir o domínio completo dos videogames ou do universo Pokémon. A entidade Pokémon será mantida de forma mínima. |
| **Documentos Relacionados** | `../04-domain-model.md`, `ADR-003-multi-game-architecture.md`, `../02-architecture-principles.md` (AP-010, AP-014) |

---

# Context

Durante a modelagem detalhada da Card, foi identificado que HP, ataques, fraqueza, resistência e custo de recuo pertencem à Card impressa, não ao Pokémon — a mesma espécie (ex.: Bulbasaur) pode ter valores impressos diferentes em Cards de Sets diferentes.

Isso levou a uma reflexão mais ampla: o modelo estava em risco de confundir o **domínio Pokémon** (personagem/espécie, com toda sua extensão nos jogos eletrônicos — estatísticas de batalha, movimentos aprendidos por nível, habitat, natureza, gerações e regiões) com o **domínio Pokémon TCG** (o jogo de cartas colecionável, que é o produto real do Project Mimikyu).

Modelar o domínio Pokémon completo seria desnecessário e transformaria o sistema em uma Pokédex completa, desviando do produto. Por outro lado, tratar o nome do Pokémon apenas como texto solto em cada Card impediria relacionar todas as Cards do mesmo Pokémon entre Sets.

---

# Decision

O Project Mimikyu modelará as regras editoriais e colecionáveis do **Pokémon TCG como produto colecionável**, e não o universo geral dos jogos Pokémon.

A entidade **Pokémon** será mantida de forma mínima, apenas para identificar e relacionar Cards que representam o mesmo personagem ou espécie: `id`, `national_dex_number`, `canonical_name`.

Regra de escopo adotada:

> Uma informação sobre Pokémon só entra no Project Mimikyu quando for necessária para identificar, pesquisar, agrupar ou analisar Cards e coleções.

Ficam fora de escopo: altura e peso da espécie, habitat, habilidades e estatísticas dos videogames, natureza, movimentos aprendidos por nível, cadeia evolutiva completa dos jogos, gerações ou regiões — salvo se algum desses dados vier a ter valor direto e concreto para o colecionismo.

A Card (e, mais especificamente, a Pokémon Card Details — ver `04-domain-model.md`) permanece responsável por HP, ataques e demais propriedades impressas, pois esses valores variam por publicação, não por espécie.

**A associação `Card → Pokémon` não é uma regra universal da plataforma.** Ela pertence exclusivamente ao módulo específico do Pokémon TCG:

```text
Catalog Domain (genérico, multi-TCG)
├── Game
├── Expansion
├── Set
└── Card

Pokémon TCG Domain (específico)
├── Pokémon
├── Pokémon Card Details
└── Trainer Card Details
```

Cards de categoria Trainer não possuem relação com Pokémon.

---

# Consequences

## Benefícios

- o modelo permanece focado no colecionismo, não no jogo Pokémon;
- dados de batalha dos videogames ficam fora do escopo, reduzindo complexidade e volume de dados irrelevantes;
- a Card continua sendo responsável por HP, ataques e demais propriedades impressas — corretamente, já que variam por publicação;
- Cards de Treinador não possuem relação com Pokémon;
- a plataforma preserva uma base genérica para outros TCGs (Magic, Lorcana, One Piece) sem obrigá-los a adotar conceitos como Pokémon, HP ou evolução (ADR-003, AP-010);
- funcionalidades como pesquisa por Pokémon e Pokédex pessoal do usuário continuam possíveis, já que a entidade Pokémon existe (de forma mínima).

## Restrições

- qualquer nova informação sobre Pokémon proposta no futuro deve ser avaliada quanto a ser necessária para identificação, pesquisa, agrupamento ou análise de Cards/coleções antes de ser adicionada à entidade Pokémon;
- a estrutura definitiva de Pokémon Card Details e Trainer Card Details será avaliada durante a modelagem lógica, incluindo o critério de quais campos recebem estrutura própria (ver ADR-012).

## Atualização — Escopo de Pokémon Card Details Esvaziado (ver AP-017)

Durante a modelagem física da Card (`04-domain-model.md`, "Modelagem Física — Discussão Iniciada"), Fabrício deu uma diretriz direta e mais restritiva do que esta ADR originalmente previa: informações de mecânica de jogo — HP, estágio, tipo elemental, fraqueza, resistência, custo de recuo, ataques, habilidades — **não devem ser estruturadas no banco de dados**, mesmo que variem por publicação como já reconhecido aqui. Isso formalizou o novo **AP-017 (Princípio do Escopo Colecionável)**.

Consequência prática: a arquitetura `Card → Card Details → Pokémon Card Details / Trainer Card Details` definida nesta ADR **permanece válida como padrão estrutural** (separação entre o Catalog Domain genérico e o Pokémon TCG Domain específico), mas seu conteúdo concreto de mecânica de jogo — que este documento originalmente atribuía a "Pokémon Card Details" — fica indefinidamente vazio/adiado, não apenas para a primeira versão. A entidade Pokémon mínima (`id`, `national_dex_number`, `canonical_name`) também deixa de ser um item planejado para a primeira versão da Card — permanece como possibilidade futura, apenas se e quando uma necessidade concreta de identificação/pesquisa/agrupamento surgir (mesmo critério de escopo já definido acima, agora reforçado por AP-017).

## Atualização — Revogação do Adiamento da Entidade Pokémon / Registro de Pokémon Species (v1.2, 2026-09-03)

> ⚠️ Esta seção **revoga parcialmente** a atualização anterior (v1.1, acima). Texto de v1.1 preservado inalterado por rastreabilidade — não editado, apenas superado no ponto específico indicado abaixo.

A necessidade concreta que v1.1 previa como condição para reverter o adiamento ("apenas se e quando uma necessidade concreta de identificação/pesquisa/agrupamento surgir") se materializou: a frente Collections Pokédex / `REFERENCE_POSITION` (cadeia de rodadas `COLLECTIONS-POKEDEX-MODELING-AUDIT-01` → `COLLECTIONS-POKEDEX-DATA-SOURCE-SPIKE-01` → `COLLECTIONS-POKEDEX-TCGDEX-DEXID-PROOF-01` → `COLLECTIONS-POKEDEX-MODELING-RECONCILIATION-01` → `COLLECTIONS-POKEDEX-MODELING-DOCUMENTATION-01`) depende estruturalmente de uma identidade de espécie para funcionar: uma Pokédex Position representa uma espécie, não uma Card; a Completion de uma Collection Pokédex é contada por espécie; e uma fonte de dados real e viável para essa identidade (PokéAPI, complementada por reconciliação editorial MMKYU) foi confirmada empiricamente (ver `COLLECTIONS-POKEDEX-DATA-SOURCE-SPIKE-01` e `COLLECTIONS-POKEDEX-TCGDEX-DEXID-PROOF-01`).

**Decisão desta atualização:**

1. **O adiamento da entidade Pokémon mínima, registrado em v1.1, é revogado.** A entidade volta a ser um conceito ativo do domínio Pokémon TCG desta ADR — não mais "possibilidade futura sem necessidade concreta", mas necessidade concreta já confirmada e documentada em `docs/domain-modeling/collections/logical-model.md` (bloco LDM-175 a LDM-185).
2. **O adiamento de mecânica de jogo (HP, ataques, habilidades, fraqueza, resistência, custo de recuo, estágio), também registrado em v1.1 e formalizado por AP-017, permanece integralmente em vigor.** Esta revogação é específica à existência da entidade de identidade; não reabre a decisão de AP-017 sobre estrutura de jogo, que continua fora de escopo.
3. **Convergência terminológica**: a entidade passa a ser chamada **Pokémon Species** (não apenas "Pokémon"), para distinguir explicitamente a identidade de espécie/personagem (o que este documento sempre pretendeu — `id`, `national_dex_number`/`pokedex_numbers`, `canonical_name`) do domínio de jogo completo dos videogames, que permanece fora de escopo. Esta nomenclatura converge com o vocabulário da fonte de dados adotada (PokéAPI: `pokemon-species`). Dois conceitos subordinados são registrados junto com Pokémon Species, ambos também fora de escopo de mecânica de jogo:
   - **Generation** — a geração de introdução da espécie (ex.: Kanto/Generation I); Pokémon Species possui exatamente uma Generation de introdução.
   - **Pokémon Form / Variety** — variação visual/regional de uma Pokémon Species (ex.: Alolan Form, Mega, forma regional); subordinada à Species, não cria uma nova identidade de completion nem deve ser confundida com Card Variant (que é uma propriedade da Card, não da espécie).
4. **Sourcing**: PokéAPI é a fonte estruturada para Pokémon Species/Generation/Form-Variety/Pokédex/Position; TCGdex (já integrada ao catálogo MMKYU) é a fonte de Card/`dexId`; reconciliação editorial MMKYU resolve os casos em que `dexId` é múltiplo ou ausente. Nenhuma API externa é dependência de runtime — consistente com ADR-008; o catálogo interno do Project Mimikyu permanece a autoridade em tempo de execução.
5. O critério de escopo original desta ADR — "uma informação sobre Pokémon só entra no Project Mimikyu quando for necessária para identificar, pesquisar, agrupar ou analisar Cards e coleções" — **não é alterado**; esta atualização apenas confirma que esse critério foi atendido para a identidade mínima de espécie, não abre a porta para dados de jogo.

A modelagem lógica completa de Pokémon Species/Generation/Form-Variety e sua relação com Pokédex Position, Position Assignment e Completion está em `docs/domain-modeling/collections/logical-model.md` (LDM-175 a LDM-185) — não duplicada aqui. Estrutura física (tabelas, colunas) **não iniciada** — próximo checkpoint da frente Collections é "POKEDEX PHYSICAL MODELING".

---

# Atualização — Pokémon Region (v1.3, 2026-09-04)

`POKEMON-REGION-DOMAIN-MODELING-AUDIT-01` (auditoria read-only direta da PokéAPI, 11 regiões) confirma **Pokémon Region** (ex.: Kanto, Johto, Hoenn) como entidade canônica própria dentro do escopo mínimo já delimitado por este ADR — subordinada, junto com Generation e Pokémon Form/Variety, à mesma disciplina de "só entra o que for necessário para identificar, pesquisar, agrupar ou analisar Cards e coleções" (v1.0). Region é independente de Generation: existem Regiões sem nenhuma Generation principal associada (Orre, Hisui — `main_generation: null`), e a relação Generation → Main Region é modelada como N:1 (cada Generation tem exatamente uma Main Region; uma Region pode ser Main Region de 0..N Generations — unicidade reversa observada, não invariante de domínio). Fundação física (`pokemon_region`, `pokemon_region_external_reference`, `pokemon_generation.main_region_id`) **CONFIRMADO EXECUTADO em 2026-09-04** (`POKEMON-REGION-FOUNDATION-PHYSICAL-IMPLEMENTATION-01`/`-CANONICAL-PROMOTION-01`), com sourcing real ainda **SUSPENSO**. Locations, Areas, Version Groups e o grafo de navegação entre Regiões permanecem explicitamente fora de escopo — mesmo adiamento de mecânica/dado não necessário ao colecionismo já praticado por este ADR desde v1.0/v1.1. Detalhamento lógico completo em `docs/domain-modeling/collections/logical-model.md`, LDM-186 a LDM-190 — texto de v1.0/v1.1/v1.2 preservado inalterado.

---

# Alternatives Considered

## Modelar o domínio completo da franquia Pokémon

Rejeitada por transformar o sistema em uma Pokédex completa, desviando do produto (colecionismo de TCG) e adicionando complexidade e dados irrelevantes.

## Tratar o Pokémon apenas como texto na Card, sem entidade própria

Rejeitada por impedir relacionar todas as Cards que representam o mesmo Pokémon entre diferentes Sets, prejudicando funcionalidades como pesquisa por personagem e Pokédex pessoal.

---

# Related Documents

- `../04-domain-model.md`
- `ADR-003-multi-game-architecture.md`
- `../02-architecture-principles.md`
- `ADR-008-external-catalog-data-sources.md`
- `../domain-modeling/collections/logical-model.md` (LDM-175 a LDM-185)
- `../05d-colecoes-e-usuarios.md`

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Registro da decisão de escopo do domínio Pokémon TCG, com entidade Pokémon mínima e separação do módulo específico do Pokémon TCG do núcleo genérico multi-TCG. |
| 1.1 | Adicionada "Atualização — Escopo de Pokémon Card Details Esvaziado": Fabrício determinou diretamente que mecânica de jogo (HP, ataques, habilidades, fraqueza, resistência, custo de recuo, estágio) não deve ser estruturada, formalizado em AP-017. O padrão Card Details/Pokémon Card Details/Trainer Card Details permanece válido como arquitetura, mas sem conteúdo de jogo planejado; a entidade Pokémon mínima deixa de ser item da primeira versão da Card. |
| 1.2 | **Revogação do adiamento da entidade Pokémon, 2026-09-03** (`COLLECTIONS-POKEDEX-MODELING-DOCUMENTATION-01`). Adicionada "Atualização — Revogação do Adiamento da Entidade Pokémon / Registro de Pokémon Species (v1.2)": a condição que v1.1 estabelecia para reverter o adiamento ("necessidade concreta de identificação/pesquisa/agrupamento") se confirmou com a frente Collections Pokédex/`REFERENCE_POSITION` (ver `docs/domain-modeling/collections/logical-model.md`, LDM-175 a LDM-185). Entidade renomeada para **Pokémon Species** (convergência com PokéAPI), com **Generation** e **Pokémon Form/Variety** registrados como conceitos subordinados. Sourcing formalizado: PokéAPI (Species/Generation/Form/Pokédex) + TCGdex (Card/`dexId`, já integrada) + reconciliação editorial MMKYU, sem dependência de runtime (consistente com ADR-008). O adiamento de mecânica de jogo (AP-017) **não é afetado** — permanece integralmente em vigor. Texto de v1.0/v1.1 preservado inalterado. Nenhuma estrutura física criada nesta rodada. |
| 1.3 | **Pokémon Region como entidade canônica própria, 2026-09-04** (`POKEMON-REGION-DOMAIN-MODELING-AUDIT-01` → `POKEMON-REGION-FOUNDATION-PHYSICAL-IMPLEMENTATION-01`/`-CANONICAL-PROMOTION-01`). Adicionada "Atualização — Pokémon Region (v1.3)": Region confirmada como entidade-raiz de catálogo independente de Generation (existem Regiões sem Main Generation — Orre, Hisui), cardinalidade Generation → Main Region é N:1. Fundação física (`pokemon_region`/`pokemon_region_external_reference`/`pokemon_generation.main_region_id`) **CONFIRMADO EXECUTADO**, sourcing real ainda SUSPENSO. Locations/Areas/Version Groups permanecem fora de escopo. Detalhamento lógico em `logical-model.md`, LDM-186 a LDM-190. Texto de v1.0/v1.1/v1.2 preservado inalterado. |
