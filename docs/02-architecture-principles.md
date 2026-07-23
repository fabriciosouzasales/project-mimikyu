# Architecture Principles

|Campo|Valor|
|-|-|
|**Documento**|Architecture Principles|
|**Arquivo**|`docs/02-architecture-principles.md`|
|**Versão**|1.0|
|**Status**|Aprovado|
|**Objetivo**|Definir os princípios permanentes que orientam as decisões arquiteturais do Project Mimikyu.|
|**Escopo**|Princípios de arquitetura e governança técnica. Não contém regras detalhadas de implementação.|
|**Dependências**|`00-project-charter.md`, `01-technical-identity.md`|
|**Documentos Relacionados**|`03-documentation-architecture.md`, `adr/ADR-INDEX.md`, `standards/STD-INDEX.md`|

---

# Overview

Os princípios deste documento orientam decisões técnicas, arquiteturais e documentais em todo o Project Mimikyu.

Eles não substituem decisões específicas registradas em ADRs nem regras de implementação definidas em Standards.

---

# Principles

## AP-001 — Direction over Speed

O avanço do projeto deve preservar direção, coerência e qualidade. Velocidade não justifica decisões precipitadas, inconsistentes ou sem fundamento.

## AP-002 — Every Important Decision Requires a Rationale

Toda decisão relevante deve possuir justificativa clara, permitindo compreender o problema, as alternativas consideradas e os efeitos da escolha.

## AP-003 — Prefer Simplicity over Unnecessary Complexity

A solução mais simples que atenda adequadamente à necessidade deve ser preferida. Complexidade adicional exige benefício concreto e demonstrável.

## AP-004 — Build for Growth without Premature Optimization

A arquitetura deve permitir evolução e crescimento, sem introduzir antecipadamente mecanismos, componentes ou abstrações que ainda não resolvam um problema real.

Exemplo de aplicação (Princípio da Simplicidade Inicial): nenhuma entidade nasce preparada para todos os cenários futuros — apenas para os cenários já conhecidos. Campos não devem ser adicionados por hipótese ("porque um dia talvez sejam úteis"); o modelo evolui quando uma necessidade real surgir.

Isso inclui não presumir uma "forma padrão" aplicável a toda entidade (ex.: sempre incluir `status`) — cada atributo, em cada entidade, precisa justificar sua própria existência no domínio. Exemplo: nem Game nem Expansion receberam `status`, porque nenhum caso de uso concreto foi identificado para nenhuma das duas.

## AP-005 — Documentation Supports Decisions, Not Bureaucracy

A documentação deve preservar contexto, orientar execução e reduzir retrabalho. Ela não deve existir apenas para ampliar o volume documental.

## AP-006 — Every Technology Must Solve a Real Problem

Toda tecnologia, ferramenta ou componente deve responder a uma necessidade objetiva do projeto. Adoção por tendência, preferência pessoal ou hipótese não validada deve ser evitada.

## AP-007 — Decisions Explain Why; Standards Define How

ADRs registram decisões e suas justificativas. Standards definem as regras permanentes de implementação decorrentes dessas decisões.

## AP-008 — One Official Source for Each Information

Cada informação deve possuir um único local oficial. Duplicações documentais devem ser evitadas para reduzir divergência e custo de manutenção.

## AP-009 — Documentation Evolves with the Software

Mudanças relevantes na arquitetura, nos padrões ou na implementação devem ser refletidas na documentação correspondente durante o mesmo ciclo de trabalho.

## AP-010 — Responsible Generalization

O sistema deverá ser modelado para suportar cenários plausíveis, evitando antecipar funcionalidades puramente hipotéticas.

Isso significa:

1. evitar soluções excessivamente específicas para Pokémon;
2. evitar abstrações desnecessárias para cenários improváveis.

Como consequência, o Project Mimikyu suporta múltiplos Trading Card Games (TCGs), mas não busca abstrair genericamente qualquer tipo de coleção existente.

## AP-011 — Editorial Identity

Os conceitos editoriais do domínio devem possuir identidade única e independente de regionalizações.

Características como idioma, distribuição ou impressão pertencem à representação do exemplar e não alteram a identidade editorial do catálogo.

## AP-012 — Separation of Catalog, Ownership and Analytics

Informações editoriais oficiais, informações sobre exemplares físicos e informações analíticas devem possuir responsabilidades conceituais distintas.

O catálogo não deve depender de dados dos usuários.

O patrimônio do usuário deve referenciar o catálogo sem duplicar sua identidade editorial.

Informações analíticas devem ser derivadas sempre que seu armazenamento redundante não for necessário.

## AP-013 — Permanence Principle

Uma informação deve pertencer à entidade cuja existência permanece verdadeira mesmo quando todas as demais entidades desaparecem.

Exemplo de aplicação: o nome, o HP e os ataques de uma Card continuam verdadeiros mesmo que nenhum usuário possua um exemplar dela — por isso pertencem à Card. Já o estado de conservação, o preço pago e uma certificação PSA deixam de existir se o exemplar físico deixar de existir — por isso pertencem ao Inventory Item.

Este princípio orienta, em conjunto com ADR-006, a decisão sobre a qual responsabilidade conceitual (Catálogo Editorial, Patrimônio do Usuário ou Analytics) uma nova informação pertence.

## AP-014 — Editorial Reuse Principle

Tudo aquilo que pode ser compartilhado entre milhares de Cards deve possuir identidade própria, em vez de ser repetido como texto solto.

Exemplo de aplicação: um Pokémon (ex.: Bulbasaur) aparece em dezenas de Sets; um Illustrator ilustra centenas de Cards; um Energy Type (ex.: Água, Fogo) é compartilhado por milhares de Cards. Esses conceitos existem independentemente de qualquer Card específica e tendem a se tornar entidades de referência do catálogo, não colunas de texto repetidas.

## AP-015 — Progressive Catalog Enrichment

O catálogo deve armazenar inicialmente apenas os dados estruturados necessários às funcionalidades do produto. A imagem oficial de cada Card preserva as demais informações editoriais. Novos dados poderão ser estruturados progressivamente, apenas quando surgir uma necessidade concreta de pesquisa, análise, automação ou funcionalidade comercial (ver ADR-012).

Este princípio evita dois extremos: modelar exaustivamente cada informação antes de haver necessidade comprovada (ver AP-004), e perder informação por não estruturar nada além do mínimo indispensável — a imagem oficial garante que nenhuma informação editorial é descartada, apenas adiada.

## AP-016 — Catalog Uniqueness Principle

O catálogo é único; as formas de colecionar são infinitas.

O catálogo editorial (Game, Expansion, Set, Card e demais conceitos editoriais) nunca deve ser adaptado para atender a um tipo específico de coleção. A flexibilidade necessária para suportar diferentes formas de colecionar — oficiais, temáticas ou personalizadas — pertence exclusivamente à entidade Collection (ver ADR-014), nunca ao catálogo.

## AP-017 — Princípio do Escopo Colecionável

**O Project Mimikyu é uma plataforma de colecionismo, não um banco de dados de mecânicas de jogo.**

Informações relevantes apenas para jogar uma partida — HP, estágio evolutivo, tipo elemental, fraqueza, resistência, custo de recuo, ataques, habilidades, texto de regras e demais mecânicas de jogabilidade — não são estruturadas no banco de dados, independentemente de quão detalhado seja o catálogo editorial. Essas informações continuam visíveis para o usuário através da imagem oficial da Card (ver ADR-012), mas não precisam de campos próprios, filtros ou entidades de apoio.

Isso vale mesmo para informações que, à primeira vista, parecem estruturáveis por reduzirem duplicação (ex.: uma entidade `Pokémon` centralizando HP/ataques compartilhados entre Cards da mesma espécie) — a pergunta decisiva não é "isso se repete entre Cards?" (AP-014), mas sim **"isso serve para colecionar, ou apenas para jogar?"**. Uma entidade de referência para o personagem/espécie Pokémon pode continuar existindo de forma mínima quando necessária para identificar e relacionar Cards (ver ADR-011), mas nunca para armazenar suas estatísticas de batalha.

Este princípio nasceu de uma correção direta de Fabrício durante a modelagem física da Card: "Não faço questão dessas informações em nossa base de dados. Lembre que essas informações são relevantes para o jogo e não para o colecionismo." Ele reforça e torna permanente — não apenas uma fase inicial (V1) — o lado "Visual Source" do modelo de três níveis já estabelecido em ADR-012 para esse grupo específico de informações.

Consequência prática: especializações de conteúdo por categoria de Card (ex.: uma tabela `pokemon_card` para HP/estágio/tipo/fraqueza/resistência/recuo) deixam de ser necessárias — o padrão Card Details / Pokémon Card Details / Trainer Card Details definido em ADR-011 permanece válido como arquitetura de extensão por módulo, mas seu conteúdo concreto de mecânica de jogo fica vazio/adiado indefinidamente, não apenas para a primeira versão.

---

# Revision History

|Versão|Descrição|
|-|-|
|1.0|Criação inicial dos princípios arquiteturais oficiais.|
|1.1|Correção de separadores markdown mal formatados (`\---`) e padronização do nível de heading e formatação de AP-010 a AP-012.|
|1.2|Adicionados AP-013 (Permanence Principle) e AP-014 (Editorial Reuse Principle), descobertos e validados durante a modelagem detalhada da Card.|
|1.3|Adicionado AP-015 (Progressive Catalog Enrichment), formalizando o critério de estruturação de dados já registrado em ADR-012.|
|1.4|Adicionado AP-016 (Catalog Uniqueness Principle), formalizando que o catálogo nunca deve ser adaptado para um tipo específico de coleção — a flexibilidade pertence à Collection (ver ADR-014). Adicionado exemplo de aplicação ("Princípio da Simplicidade Inicial") a AP-004.|
|1.5|Reforçado o exemplo de aplicação de AP-004: nenhuma entidade recebe atributos por uma "forma padrão" presumida — cada atributo precisa justificar sua existência, mesmo campos aparentemente universais como `status`.|
|1.6|Adicionado AP-017 (Princípio do Escopo Colecionável), a partir de uma correção direta de Fabrício durante a modelagem física da Card: informações de mecânica de jogo (HP, ataques, habilidades, fraqueza, resistência, custo de recuo, estágio, texto de regras) não são estruturadas no banco de dados — permanecem apenas na imagem oficial da Card (ADR-012), permanentemente, não apenas na primeira versão. Torna o padrão Card Details/Pokémon Card Details/Trainer Card Details (ADR-011) uma arquitetura sem conteúdo de jogo concreto planejado.|



