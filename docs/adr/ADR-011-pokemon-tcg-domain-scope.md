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

# Atualização — Dados de Referência da Pokédex (v1.4, 2026-10-12)

Pokédex P3a (decisão D1 de Fabrício). A emenda de AP-017 (`02-architecture-principles.md` v1.10) distingue dois escopos:

1. **Catálogo Pokémon TCG** — inalterado: nenhuma mecânica de batalha (HP, ataques, habilidades, fraqueza, resistência, custo de recuo, estágio, texto de regras) é estruturada em Card ou entidades do catálogo de cartas.
2. **Pokédex** — pode armazenar informações de referência das espécies para identificação, exploração, pesquisa e apresentação visual: classificação, descrição selecionada da Pokédex, indicadores lendário/mítico/bebê (espécie); tipos, altura e peso (forma padrão); vocabulário dos 18 tipos elementais.

Consequências:
- **Pokémon Form / Variety** (LDM-175) ganha a primeira estrutura física, `pokemon_form`, restrita à forma padrão (uma por espécie), identificada pela referência oficial da PokéAPI e conferida pelo vínculo espécie → variedade padrão → Pokémon. Formas regionais, alternativas, Mega e Gigantamax continuam fora.
- Habilidades, estatísticas-base, golpes e cadeias evolutivas continuam fora de escopo.
- Textos de terceiros (classificação e descrição) são guardados com idioma, versão de origem e situação de direitos (`THIRD_PARTY_UNLICENSED`), como a arte das espécies; traduções editoriais futuras ficam identificadas como conteúdo MMKYU, nunca como oficiais.
- Estrutura física proposta em `database/proposals/2026-10-12-pokedex-p3a-species-enrichment/` (Query 6133). Texto de v1.0–v1.3 preservado inalterado.

---

# Atualização — Operação Editorial pt-BR em Paralelo (v1.5, 2026-10-13)

Decisão do responsável pelo MMKYU, após a publicação e homologação da P3e — Lote 01 (commit `54da0a2`; 60 espécies com conteúdo `MMKYU_EDITORIAL` pt-BR) e a extração do pacote factual das 965 espécies restantes (`database/proposals/2026-10-13-pokedex-editorial-factual-pack/`, fingerprint global `f5669eba65c187755d96cea226bb1517`). A produção editorial da Pokédex passa a correr **em paralelo** ao desenvolvimento funcional, em duas frentes:

| Frente | Prioridade | Responsáveis | Escopo |
|---|---|---|---|
| **A — Produto e funcionalidades** | Principal | Claude implementa; ChatGPT principal faz consultoria, definição de produto e auditoria; o responsável pelo MMKYU aprova | Exploração por geração, pesquisa avançada, Pokémon Favoritos e evoluções futuras da experiência da Pokédex |
| **B — Operação editorial pt-BR** | Paralela | Um chat ChatGPT dedicado produz e revisa; o Claude faz integração técnica, validação independente e preparação da publicação quando houver entrega e autorização | Classificações e descrições das 965 espécies restantes, em lotes de ~100, seguindo o guia editorial v0.2 e o glossário aprovados; revisão editorial, identificação de exceções e entrega em JSON estruturado |

Regras de governança:

1. Os 60 textos editoriais publicados não são modificados, e os lotes P3d e P3e não são reabertos.
2. A Frente A não produz descrições editoriais.
3. Nenhum lote novo é iniciado por iniciativa própria do Claude; cada lote começa pela entrega da Frente B.
4. Nenhuma publicação editorial no LIVE sem autorização explícita, mantido o rito ensaio com rollback → publicação → validação → homologação já usado na P3d/P3e.
5. Rastreabilidade e proveniência preservadas: cada texto continua identificado como conteúdo MMKYU (`origin = MMKYU_EDITORIAL`), nunca como oficial, e cada entrada do lote carrega o `md5` do texto de origem (`source_basis`), conferido pelo validador `scripts/editorial/validate-editorial-lot.ts` antes de qualquer aprovação.
6. O chat editorial não altera o repositório nem executa SQL; entrega arquivos ao responsável pelo MMKYU, que os encaminha para integração.
7. As frentes não editam os mesmos arquivos ao mesmo tempo: a Frente B fica restrita à pasta do próprio lote em `database/proposals/` e às respectivas Queries de publicação; a Frente A não toca nessas pastas nem em `scripts/editorial/`.
8. O desenvolvimento funcional não espera o fim da produção editorial: toda tela da Pokédex continua funcionando para espécies sem texto pt-BR (texto de origem em inglês, já identificado como tal na ficha).

Sem alteração de schema, funções ou dados nesta atualização. Texto de v1.0–v1.4 preservado inalterado.

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
| 1.4 | **Dados de referência da Pokédex, 2026-10-12** (Pokédex P3a, decisão D1). Adicionada "Atualização — Dados de Referência da Pokédex (v1.4)": AP-017 preservado para o Catálogo Pokémon TCG; a Pokédex pode estruturar classificação, descrição, lendário/mítico/bebê, tipos, altura e peso da forma padrão e o vocabulário dos 18 tipos. Primeira estrutura física de Pokémon Form (`pokemon_form`, só forma padrão). Habilidades, estatísticas, golpes, evoluções e formas alternativas continuam fora. Texto de v1.0–v1.3 preservado. |
| 1.5 | **Operação editorial pt-BR em paralelo, 2026-10-13** (decisão do responsável pelo MMKYU). Adicionada "Atualização — Operação Editorial pt-BR em Paralelo (v1.5)": Frente A (produto e funcionalidades, prioridade principal) e Frente B (produção editorial das 965 espécies restantes por chat ChatGPT dedicado, lotes de ~100, guia v0.2 e glossário), com responsabilidades e oito regras de governança (60 textos publicados e lotes P3d/P3e intocados, publicação só com autorização, proveniência por `md5` de origem, sem edição simultânea dos mesmos arquivos, funcional não espera o editorial). Sem alteração física. Texto de v1.0–v1.4 preservado. |
