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

---

# Revision History

|Versão|Descrição|
|-|-|
|1.0|Criação inicial dos princípios arquiteturais oficiais.|
|1.1|Correção de separadores markdown mal formatados (`\---`) e padronização do nível de heading e formatação de AP-010 a AP-012.|
|1.2|Adicionados AP-013 (Permanence Principle) e AP-014 (Editorial Reuse Principle), descobertos e validados durante a modelagem detalhada da Card.|
|1.3|Adicionado AP-015 (Progressive Catalog Enrichment), formalizando o critério de estruturação de dados já registrado em ADR-012.|



