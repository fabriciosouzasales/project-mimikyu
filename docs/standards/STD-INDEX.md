# Standards Index

|Campo|Valor|
|-|-|
|**Documento**|Standards Index|
|**Arquivo**|`docs/standards/STD-INDEX.md`|
|**Versão**|2.0|
|**Status**|Aprovado|
|**Objetivo**|Catalogar os Standards oficiais do Project Mimikyu.|
|**Dependências**|`../03-documentation-architecture.md`|

---

# Overview

Este índice apresenta os Standards oficiais do Project Mimikyu.

Standards definem regras permanentes e verificáveis de implementação, nomenclatura, documentação e operação.

---

# Catalog

|Standard|Título|Status|
|-|-|-|
|[STD-001](STD-001-database-standards.md)|Database Standards|Aprovado|
|[STD-002](STD-002-domain-modeling.md)|Domain Modeling|Aprovado|
|[STD-003](STD-003-documentation-conventions.md)|Documentation Conventions|Aprovado|

---

# Maintenance Rules

* Utilizar numeração sequencial no formato `STD-NNN`.
* Não reutilizar números.
* Adotar nomes de arquivo no formato `STD-NNN-title.md`.
* Atualizar este índice sempre que um Standard for criado ou tiver seu status alterado.
* Não tratar um item planejado como regra vigente antes da aprovação do documento correspondente.

---

# Revision History

|Versão|Descrição|
|-|-|
|1.0|Criação inicial do índice de Standards.|
|1.1|Correção de separadores markdown mal formatados (`\---`). Nenhuma alteração de catálogo ou conteúdo.|
|2.0|**Catálogo corrigido para refletir o estado real dos Standards (2026-07-24), a pedido explícito de Fabrício.** Até esta revisão, o índice listava `STD-002` como "SQL Conventions" e `STD-003` como "Documentation Conventions" na seção "Planned Standards" (não vigentes) — mas ambos já existiam como documentos aprovados havia dezenas de ciclos, com títulos reais diferentes do planejado: `STD-002` é "Domain Modeling" (não "SQL Conventions" — esse tema nunca virou um Standard próprio), `STD-003` é "Documentation Conventions" (título coincidia, mas o status não). Seção "Planned Standards" removida — não há, no momento, nenhum Standard identificado e ainda não escrito. Mesma decisão de Fabrício que reativou a manutenção do `ADR-INDEX.md`: a documentação do passado está encerrada, e os índices passam a ser mantidos ativamente a partir de agora. |



