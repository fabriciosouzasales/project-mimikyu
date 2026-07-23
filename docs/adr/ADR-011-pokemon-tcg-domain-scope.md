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

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Registro da decisão de escopo do domínio Pokémon TCG, com entidade Pokémon mínima e separação do módulo específico do Pokémon TCG do núcleo genérico multi-TCG. |
| 1.1 | Adicionada "Atualização — Escopo de Pokémon Card Details Esvaziado": Fabrício determinou diretamente que mecânica de jogo (HP, ataques, habilidades, fraqueza, resistência, custo de recuo, estágio) não deve ser estruturada, formalizado em AP-017. O padrão Card Details/Pokémon Card Details/Trainer Card Details permanece válido como arquitetura, mas sem conteúdo de jogo planejado; a entidade Pokémon mínima deixa de ser item da primeira versão da Card. |
