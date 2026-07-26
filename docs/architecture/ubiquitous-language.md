# Ubiquitous Language

| Campo | Valor |
|--------|-------|
| **Documento** | Ubiquitous Language |
| **Arquivo** | `docs/architecture/ubiquitous-language.md` |
| **Versão** | 1.10 |
| **Status** | Em elaboração |
| **Objetivo** | Definir o vocabulário oficial utilizado durante todo o desenvolvimento do Project Mimikyu. |
| **Escopo** | Terminologia de domínio utilizada em toda a documentação e implementação do projeto. |
| **Dependências** | `../04-domain-model.md`, `../standards/STD-003-documentation-conventions.md` |
| **Documentos Relacionados** | `../adr/ADR-003-multi-game-architecture.md`, `../adr/ADR-004-set-identity.md`, `../adr/ADR-005-catalog-language-model.md`, `../adr/ADR-006-separation-of-catalog-ownership-and-analytics.md`, `../adr/ADR-007-card-translation-model.md`, `../adr/ADR-010-card-rarity-and-finish-model.md`, `../adr/ADR-011-pokemon-tcg-domain-scope.md`, `../adr/ADR-012-structured-vs-visual-card-data.md`, `../adr/ADR-013-collection-item-identity-model.md`, `../adr/ADR-014-collection-and-collection-entry-model.md`, `../adr/ADR-016-card-variant-naming-convention.md`, `../02-architecture-principles.md` (AP-013, AP-014, AP-015), `../standards/STD-002-domain-modeling.md` |

---

# Purpose

Este documento centraliza a terminologia oficial do sistema.

Seu objetivo é eliminar ambiguidades e garantir que todos os documentos utilizem os mesmos conceitos.

---

| Termo | Definição |
|--------|-----------|
| Game | Trading Card Game suportado pelo sistema. |
| Expansion | Grande ciclo editorial que agrupa diversos Sets. |
| Set | Publicação editorial oficial pertencente a uma Expansion. Possui identidade única e não é duplicado por idioma. |
| Card | Posição editorial oficial pertencente a um Set. Existe uma única vez no catálogo e não representa um exemplar físico. Contém as características editoriais permanentes da publicação (AP-013). |
| Card Category | Classifica a natureza da Card. No catálogo numerado, apenas Pokémon e Trainer — cartas de Energia não ocupam posição no Set. Nem toda Card representa um Pokémon. |
| Trainer Subcategory | Subclassificação obrigatória de uma Card de categoria Trainer: Item, Supporter, Stadium ou Tool. |
| Card Translation | Conteúdo editorial de uma Card em um idioma específico (nome, texto de regras, etc.). Não cria uma nova posição catalográfica nem duplica a Card. |
| Card Details | Estrutura que agrupa informações específicas por Card Category (Pokémon Card Details / Trainer Card Details). Não é um conceito genérico da plataforma — pertence ao módulo Pokémon TCG (ver ADR-011). |
| Pokémon | Identidade mínima do personagem/espécie (id, national_dex_number, canonical_name), referenciada por Cards de Card Category Pokémon. Não armazena HP, ataques ou demais valores impressos — esses pertencem à Card, pois variam entre publicações da mesma espécie. |
| Illustrator | Pessoa responsável pela arte de uma Card. Entidade de referência reutilizada entre Cards. |
| Energy Type | Tipo elemental de uma Card (ex.: Água, Fogo), quando aplicável. Entidade de referência. |
| Rarity | Classificação de raridade oficial de uma Card (Common, Uncommon, Rare, Double Rare, Ultra Rare, Illustration Rare, Special Illustration Rare, Mega Hyper Rare, entre outras). Atributo de primeira classe da Card, distinto de Card Variant. |
| Card Variant Type | Catálogo controlado de tipos de acabamento físico oficiais (ex.: Standard, Holo, Reverse Holo, Cosmos Holo). Não altera número, arte, Rarity ou identidade editorial da Card. Termo canônico — "Finish" foi o termo conceitual adotado por ADR-010 entre 2026-07 e a reversão desta decisão; "Printing Variant" e "Finish Variant" permanecem descartados (ver ADR-009, ADR-010, ADR-016). |
| Card Variant | Associação entre uma Card e um Card Variant Type em que ela está oficialmente disponível. Não deve ser assumido que todas as Cards de um Set possuem os mesmos Card Variants. Termo canônico desde ADR-016 — "Card Finish" foi o termo conceitual usado por ADR-010 entre 2026-07 e a reversão desta decisão. |
| Collection Item | Exemplar físico individual e identificável de uma Card, pertencente ou anteriormente pertencente a um colecionador. Referencia um Card Variant específico e um idioma, não a Card diretamente. Nunca representado como quantidade agregada — cada cópia física possui identidade própria, técnica e permanente (ver ADR-013). Substitui o termo provisório "Inventory Item". |
| Ownership Status | Dimensão do Collection Item que responde se o exemplar ainda pertence ao usuário (ex.: OWNED, SOLD, DISPOSED). Distinta de Availability Status. |
| Availability Status | Dimensão do Collection Item que responde se o exemplar está disponível para alguma finalidade, como troca ou venda (ex.: AVAILABLE_FOR_TRADE, RESERVED). Distinta de Ownership Status. |
| Collection | Agrupamento definido pelo colecionador para organizar um objetivo de coleção (ex.: Pokédex Nacional, uma coleção temática, o objetivo de completar um Set). Pertence ao colecionador, não ao catálogo editorial — distinto de Set (ver ADR-014). |
| Collection Entry | Item que compõe o objetivo de uma Collection: uma Card específica (Card Target) ou um assunto mais amplo satisfeito por qualquer Card correspondente, como um Pokémon (Subject Target). Ver ADR-014. |
| Collector Universe | Termo utilizado para descrever o conjunto formado por User, Collection, Collection Entry e Collection Item — abrange tanto os objetivos de coleção quanto os exemplares fisicamente possuídos. Relaciona-se com User Ownership (ver ADR-006), mas inclui também itens ainda não possuídos (objetivos declarados). |
| Official Card Count | Quantidade de posições numeradas em um Set (ex.: ME1 = 188). |
| Base Set Count | Denominador oficial exibido nas Cards de um Set (ex.: ME1 = 132). Característica do Set. |
| Collectible Variant Count | Soma dos Card Variants disponíveis para todas as Cards de um Set. Pode ser maior que o Official Card Count. |
| Identity Entity | Classificação de conceito (STD-002) com identidade própria, referenciável por outras entidades (ex.: Card, Set, Pokémon, Illustrator). |
| Value Object | Classificação de conceito (STD-002) sem identidade própria, que só existe como parte de outra entidade (ex.: HP, Weakness, Retreat Cost). |
| Reference Data | Classificação de conceito (STD-002), também chamada Tabela de Domínio: catálogo pequeno e controlado, reutilizado pelo sistema (ex.: Rarity, Card Category, Card Variant Type). |
| Structured Data | Informação de uma Card armazenada em campo próprio, pesquisável e filtrável (ver ADR-012). |
| Visual Source | A imagem oficial da Card, que preserva informações não estruturadas (ver ADR-012). |
| Extracted Data | Informação futuramente convertida da imagem para campo estruturado, por importação, OCR ou revisão manual (ver ADR-012). |
| Editorial Catalog | Conjunto de informações oficiais organizadas pela hierarquia Game, Expansion, Set e Card. |
| User Ownership | Conjunto de exemplares físicos pertencentes aos usuários e suas características particulares. |
| Analytics | Informações derivadas do Catálogo Editorial e do Patrimônio do Usuário. |
| User Profile | Entidade de identidade e perfil básico do usuário (nome de exibição, avatar, Username), separada da autenticação (Supabase Auth). Relação 1:1 com o usuário autenticado. Não armazena papéis, permissões ou preferências — ficam fora do escopo desta entidade até necessidade concreta (ver ADR-020). |
| Username | Identidade pública, única e estável do usuário dentro da plataforma. Escolhida no cadastro, imutável pelo próprio usuário depois de criada — pensada para uso futuro em compartilhamento, URLs amigáveis e perfis públicos (ver ADR-020). |
| Reserved Username | Termo que nenhum usuário pode reivindicar como Username (ex.: admin, suporte, perfil). Tabela de apoio, não uma entidade de domínio. |

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Estrutura inicial do vocabulário oficial do projeto. |
| 1.1 | Padronização do cabeçalho (Arquivo, Escopo, Dependências, Documentos Relacionados) e reordenação da tabela de termos para seguir a hierarquia editorial (Game → Expansion → Set → Card → Card Variant → Inventory Item). Nenhuma definição foi alterada. |
| 1.2 | Adicionado o termo Card Translation. Atualizada a definição de Card Variant para refletir seu escopo (forma de impressão) e sinalizar que sua regra de identidade ainda está em aberto. |
| 1.3 | Resolvida a definição de Card Variant: escopo restrito a diferenças de acabamento (ver ADR-009). |
| 1.4 | Substituído o termo Card Variant por Rarity, Finish e Card Finish, com base em documento oficial (ver ADR-010). |
| 1.5 | Adicionados Card Category, Pokémon, Illustrator, Energy Type, Official Card Count, Base Set Count e Collectible Finish Count. |
| 1.6 | Resolvida a taxonomia de Card Category (Pokémon/Trainer; Energia fora do catálogo numerado); adicionados Trainer Subcategory, Card Details, Identity Entity, Value Object, Reference Data, Structured Data, Visual Source e Extracted Data; Pokémon redefinido como identidade mínima (ver ADR-011, ADR-012). |
| 1.7 | Substituído o termo Inventory Item por Collection Item, refletindo identidade individual por exemplar físico. Adicionados Ownership Status e Availability Status como dimensões distintas (ver ADR-013). |
| 1.8 | Adicionados Collection, Collection Entry e Collector Universe, formalizando a distinção entre Set (catálogo editorial) e Collection (objetivo do colecionador), ver ADR-014. |
| 1.9 | Revertidos os termos Finish e Card Finish (adotados em 1.4, ver ADR-010) para Card Variant Type e Card Variant, convergindo o vocabulário conceitual com o nome já usado no schema físico, no pipeline de importação e na prática do projeto (ver ADR-016). Collectible Finish Count renomeado para Collectible Variant Count. Atualizadas as definições de Rarity, Collection Item e Reference Data. "Finish" e "Card Finish" passam a ser tratados como sinônimos históricos, não como termos ativos do vocabulário. |
| 1.10 | Adicionados User Profile, Username e Reserved Username, formalizando o primeiro módulo fora do Catálogo Editorial (Identidade e Acesso, Incremento 1 "Meu Perfil"), com entidade real já executada no banco (ver ADR-020, `05-modelo-de-dados.md`). |