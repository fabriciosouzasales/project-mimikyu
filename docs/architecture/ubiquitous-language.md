# Ubiquitous Language

| Campo | Valor |
|--------|-------|
| **Documento** | Ubiquitous Language |
| **Arquivo** | `docs/architecture/ubiquitous-language.md` |
| **Versão** | 1.0 |
| **Status** | Em elaboração |
| **Objetivo** | Definir o vocabulário oficial utilizado durante todo o desenvolvimento do Project Mimikyu. |
| **Escopo** | Terminologia de domínio utilizada em toda a documentação e implementação do projeto. |
| **Dependências** | `../04-domain-model.md`, `../standards/STD-003-documentation-conventions.md` |
| **Documentos Relacionados** | `../adr/ADR-003-multi-game-architecture.md`, `../adr/ADR-004-set-identity.md`, `../adr/ADR-005-catalog-language-model.md`, `../adr/ADR-006-separation-of-catalog-ownership-and-analytics.md`, `../adr/ADR-007-card-translation-model.md`, `../adr/ADR-010-card-rarity-and-finish-model.md` |

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
| Card | Posição editorial oficial pertencente a um Set. Existe uma única vez no catálogo e não representa um exemplar físico. |
| Card Translation | Conteúdo editorial de uma Card em um idioma específico (nome, texto de regras, etc.). Não cria uma nova posição catalográfica nem duplica a Card. |
| Rarity | Classificação de raridade oficial de uma Card (Common, Uncommon, Rare, Double Rare, Ultra Rare, Illustration Rare, Special Illustration Rare, Mega Hyper Rare, entre outras). Atributo de primeira classe da Card, distinto de Finish. |
| Finish | Catálogo controlado de acabamentos físicos oficiais (ex.: Standard, Standard Foil). Não altera número, arte, Rarity ou identidade editorial da Card. Termo canônico — "Card Variant", "Printing Variant" e "Finish Variant" foram descartados (ver ADR-010). |
| Card Finish | Associação entre uma Card e um Finish em que ela está oficialmente disponível. Não deve ser assumido que todas as Cards de um Set possuem os mesmos Card Finishes. |
| Inventory Item | Exemplar físico específico pertencente a um usuário. Referencia uma Card Finish específica, não a Card diretamente. |
| Editorial Catalog | Conjunto de informações oficiais organizadas pela hierarquia Game, Expansion, Set e Card. |
| User Ownership | Conjunto de exemplares físicos pertencentes aos usuários e suas características particulares. |
| Analytics | Informações derivadas do Catálogo Editorial e do Patrimônio do Usuário. |

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Estrutura inicial do vocabulário oficial do projeto. |
| 1.1 | Padronização do cabeçalho (Arquivo, Escopo, Dependências, Documentos Relacionados) e reordenação da tabela de termos para seguir a hierarquia editorial (Game → Expansion → Set → Card → Card Variant → Inventory Item). Nenhuma definição foi alterada. |
| 1.2 | Adicionado o termo Card Translation. Atualizada a definição de Card Variant para refletir seu escopo (forma de impressão) e sinalizar que sua regra de identidade ainda está em aberto. |
| 1.3 | Resolvida a definição de Card Variant: escopo restrito a diferenças de acabamento (ver ADR-009). |
| 1.4 | Substituído o termo Card Variant por Rarity, Finish e Card Finish, com base em documento oficial (ver ADR-010). |