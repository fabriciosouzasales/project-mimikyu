# Pipeline de Importação

| Campo | Valor |
|--------|-------|
| **Documento** | Pipeline de Importação |
| **Arquivo** | `docs/06-pipeline-importacao.md` |
| **Versão** | 1.5 |
| **Status** | Bloco B (importação de referências e imagens de Card) **CONFIRMADO CONCLUÍDO e operacional**, via Edge Function `import-card-assets`, para as 5 coleções originais (`ME1`/`ME2`/`ME2.5`/`ME3`/`ME4`), nos dois idiomas suportados (`en`/`pt-BR`). `MEE` foi concluída à parte, por importação manual (`scripts/import-manual-assets.ts`, fora do escopo desta Edge Function — ver `ROADMAP.md`); `MEP` permanece pendente. Total atual: `927` Cards, `1.734` Card Assets, `6` de `7` Card Sets com imagens completas. O Catálogo Editorial (Bloco B) ainda não está integralmente encerrado enquanto `MEP` não for concluída — ver `ROADMAP.md`, seção "Catálogo Editorial — Frentes de Encerramento". |
| **Objetivo** | Descrever a estratégia de importação/sincronização de dados de fontes externas para o Catálogo Editorial e a arquitetura real da Edge Function `import-card-assets`. |
| **Escopo** | Estratégia de importação/sincronização e arquitetura vigente da Edge Function `import-card-assets`. Este documento registra apenas a solução final confirmada, não é um changelog do desenvolvimento. **A partir da revisão `1.2`, três responsabilidades antes reunidas aqui foram separadas em três documentos**: este arquivo cobre apenas arquitetura/estratégia; o guia operacional (passo a passo para importar uma coleção) está em `operations/import-card-assets.md`; o histórico de tentativas/bugs/sprints está em `history/pipeline-sprint-log.md`. |
| **Dependências** | `02-architecture-principles.md`, `04-domain-model.md`, `05-modelo-de-dados.md` |
| **Documentos Relacionados** | `operations/import-card-assets.md`, `history/pipeline-sprint-log.md`, `adr/ADR-006-separation-of-catalog-ownership-and-analytics.md`, `adr/ADR-008-external-catalog-data-sources.md`, `adr/ADR-018-single-function-import-pipeline.md` (formaliza a arquitetura de função única descrita abaixo; substitui `adr/ADR-017-two-function-import-pipeline.md`) |

---

# Purpose

Este documento descreve a estratégia de importação e sincronização de dados de fontes externas para o Catálogo Editorial do Project Mimikyu, e documenta o processo real e confirmado de importação de referências externas e imagens de Card via Edge Function.

A decisão arquitetural que fundamenta o padrão geral está registrada em `adr/ADR-008-external-catalog-data-sources.md`.

---

# Padrão Geral

Nenhuma fonte de dados externa é a proprietária lógica do catálogo. Toda fonte externa passa por uma camada de importação/sincronização antes de alimentar o catálogo interno:

```text
External Data Source
        ↓
Import / Synchronization
        ↓
Project Mimikyu Catalog
```

O catálogo interno do Project Mimikyu mantém registros próprios e independentes de: Game, Expansion, Set, Card, Card Translation, Card Variant.

---

# Por que o catálogo não depende de uma API externa em tempo real

Não existe uma API oficial documentada, mantida pela The Pokémon Company, para integração de sistemas externos. Ferramentas amplamente usadas por desenvolvedores — como a TCGdex e a Pokémon TCG API — são projetos independentes, não oficiais, cada um com sua própria base de dados.

Por isso, o Project Mimikyu não assume nenhuma fonte externa como definitiva, nem depende de qualquer uma delas em tempo real. A camada de Import/Synchronization existe justamente para isolar o catálogo dessas variações.

---

# Importação de Ativos Visuais (Imagens e Logos)

O mesmo padrão Import/Synchronization se aplica a ativos visuais (imagens de Card; logotipo e símbolo do Set — ver `04-domain-model.md`, seção Set): a fonte externa nunca é referenciada diretamente pela aplicação — o arquivo é baixado, armazenado no Supabase Storage, e o catálogo interno referencia o ativo já armazenado.

```text
External Data Source (imagem)
        ↓
Import / Synchronization
        ↓
Supabase Storage
        ↓
Project Mimikyu Catalog (referência ao ativo armazenado)
```

Infraestrutura física de suporte: `card_asset`, `card_asset_type`, `asset_source`, `asset_import_run`, `asset_import_failure`, `storage_bucket` (documentadas em `05-modelo-de-dados.md`).

---

# Benefícios do Modelo de Importação

- permite corrigir dados inconsistentes vindos de fontes externas;
- permite complementar informações ausentes;
- preserva os registros do catálogo caso uma fonte externa seja descontinuada;
- permite integrar mais de uma fonte de dados simultaneamente;
- mantém controle sobre os códigos internos do catálogo;
- permite registrar a procedência (fonte) de cada informação importada.

---

# Arquitetura Final — Edge Function `import-card-assets`

Processo real, confirmado por execução: `859` cartas × 2 idiomas, `1.718` imagens importadas, `0` falhas, nas 5 coleções atuais (`ME1`/`ME2`/`ME2.5`/`ME3`/`ME4`).

## O que a função faz

Recebe um `run_code` (identificador de um `asset_import_run` já criado) e, numa única execução:

1. Localiza o `asset_import_run` pelo `run_code`, e a partir dele o `card_set` e o `card_set_external_reference` (mapeamento do `card_set` para o identificador da TCGdex, ex.: `ME1` → `me01`).
2. Resolve `language`, `card_asset_type` (`CARD_FRONT`) e `storage_bucket` (`card-front`) por código.
3. Consulta a TCGdex (`TcgdexClient.getSet()`) para obter a lista completa de cartas do Set.
4. Carrega todas as `card` já cadastradas do `card_set` (a função **nunca insere** em `card`/`card_variant` — essas tabelas precisam já estar populadas antes da execução).
5. Sincroniza `card_external_reference` para cada carta (`UPSERT` em lotes de 20, por `ON CONFLICT (card_id, asset_source_id)`).
6. Baixa, envia ao Storage e registra em `card_asset` a imagem de cada carta (em lotes controlados de `IMAGE_BATCH_SIZE = 5`).
7. Retorna um resumo: `external_references.{imported,ignored,total}`, `images.{imported,failed,total}`, `failures[]` (uma entrada por carta que falhou, com `error`).

## Convenções fixas do processo

- **Caminho no Storage**: `card-front/{card_set.code}/{language.code}/{collector_number}.{extensão}` (ex.: `me1/pt-BR/001.webp`) — inclui o idioma, evitando colisão entre execuções em idiomas diferentes.
- **Idempotência**: reexecutar a mesma importação não duplica nada — upload usa `upsert: true` no Storage; `card_asset` é localizado pela chave natural (`card_id` + `asset_type_id` + `language_id` + `storage_bucket_id`) antes de inserir ou atualizar.
- **`external_url` é sempre `null`** para ativos baixados e armazenados internamente — reservado apenas para ativos referenciados externamente, nunca baixados.
- **Falha isolada não interrompe a execução**: uma carta que falha (imagem ausente na TCGdex, erro de rede, etc.) é registrada em `failures[]` e o processamento segue para as próximas.

## Pré-requisitos reais antes de rodar

- **`GRANT` explícito em cada tabela usada, para `service_role`**. RLS habilitado não substitui `GRANT` de tabela — cada uma das tabelas a seguir precisa de `GRANT SELECT` (e `INSERT`/`UPDATE` onde a função escreve) para `service_role`, confirmado necessário por experiência real: `asset_import_run`, `card_set_external_reference`, `card_external_reference`, `language`, `card_asset_type`, `card_asset`, `expansion`. Ver `database/migrations/250`, `253` e `254`.
- **Secret `SUPABASE_SERVICE_ROLE_KEY`** configurado na Edge Function (junto com `SUPABASE_URL`, padrão de toda Edge Function Supabase).
- **Bucket físico `card-front`** já existe no Supabase Storage. `card-back`/`artwork` (para verso e ilustração completa) ainda não foram criados — só criar quando forem realmente usados.

## ⚠️ Limitação real atual — idioma é configuração fixa no código, não parâmetro

`index.ts` usa duas constantes fixas para controlar o idioma da execução, e **elas não são derivadas uma da outra** — precisam ser mantidas em sincronia manualmente a cada mudança de idioma:

```ts
const LANGUAGE_CODE = "pt-BR";   // idioma no banco (language.code, card_asset.language_id, caminho no Storage)
const TCGDEX_LANGUAGE = "pt";    // idioma reconhecido pela API da TCGdex (não aceita "pt-BR")
```

**Estado atual do código publicado: configurado para `pt-BR`/`pt`.** Para importar uma coleção nova em inglês com o código como está hoje, as duas constantes precisam ser alteradas de volta para `"en"`/`"en"` e a função reimplantada (`npx supabase functions deploy import-card-assets`) — não é possível escolher o idioma por parâmetro na chamada. Transformar `language`/`asset_type`/`bucket` em parâmetros da requisição é uma melhoria real identificada e ainda não implementada (ver "Em Aberto").

Também `source_url` (armazenado em `card_external_reference`, apenas para referência, nunca buscado de volta) é montado com `LANGUAGE_CODE` em vez de `TCGDEX_LANGUAGE` — mesma inconsistência, sem efeito prático até hoje, mas vale corrigir junto da parametrização.

**Nota real sobre `card_external_reference` ser idioma-agnóstico**: a tabela tem `UNIQUE (card_id, asset_source_id)`, sem dimensão de idioma. O total ficou em `859` mesmo após importar as 5 coleções nos dois idiomas — confirma que a execução em `pt-BR` faz `UPSERT` sobre a mesma linha já criada pela `en`, em vez de criar uma segunda. Isso é aceitável hoje porque `card_external_reference` é só um cache de importação — quem carrega a dimensão de idioma que importa ao catálogo é `card_asset` (que corretamente tem uma linha por idioma). Decisão em aberto: manter assim de propósito, ou adicionar `language_id` à chave.

---

# Guia Operacional e Estado Atual

Movidos para `operations/import-card-assets.md`, a partir da revisão `1.2`: o passo a passo de 8 etapas para importar uma nova coleção, e a tabela de estado atual confirmado (859 cartas, 1.718 assets, 1.718 imagens, 0 falhas). Este documento mantém apenas arquitetura e estratégia.

---

# Em Aberto

- Estratégia de resolução de conflitos entre múltiplas fontes externas (ex.: TCGdex vs. Pokémon TCG API) — ainda não definida.
- Verificação de direitos/termos de uso das imagens antes de importação em massa (ver `05-modelo-de-dados.md`, seção "Arquitetura de Importação de Ativos") — ressalva registrada, não resolvida.
- **Crítico**: transformar `language`/`asset_type`/`bucket` em parâmetros da requisição da Edge Function, substituindo as constantes fixas hoje presas em `"pt-BR"`/`"pt"` — pré-requisito para importar uma coleção nova sem editar e reimplantar código a cada troca de idioma.
- `source_url` em `card_external_reference` usa `LANGUAGE_CODE` em vez de `TCGDEX_LANGUAGE` — corrigir junto da parametrização acima.
- `card_external_reference` sem dimensão de idioma na chave de unicidade — decisão pendente de Fabrício (manter idioma-agnóstico vs. adicionar `language_id`).
- Auditoria consolidada de `GRANT`s para `service_role` em todo o schema `public` (`grants.sql` ou equivalente) — sete casos reais já encontrados um a um; consolidação deliberadamente adiada por Fabrício.
- Melhoria de idempotência: pular cartas que já têm `card_asset` atualizado, evitando novo download/upload em reexecuções — identificada, deliberadamente adiada.
- Buckets físicos `card-back`/`artwork` ainda não criados — só `card-front` existe.
- ~~Múltiplas formas paralelas de descrever o roadmap do projeto nunca foram consolidadas em uma única fonte de verdade~~ — **RESOLVIDO (2026-07-24)**: `ROADMAP.md` criado como fonte única de verdade (estrutura Now/Next/Later), sem adotar nenhuma das propostas anteriores não confirmadas por Fabrício.
- `card_set.code = 'ME5'` ainda não cadastrado — quando for, o mapeamento externo (`card_set_external_reference`) precisa ser criado antes de importar.
- Validação prévia de integração externa antes de criar um `asset_import_run` (recusar a criação se não houver `card_set_external_reference` ativo para a coleção) — proposta, não implementada.
- Próximo módulo real do roadmap: **Coleções** (modelagem de banco, ainda não iniciada) — não interface de usuário. Perguntas de negócio já capturadas para quando essa modelagem começar (pertencimento a deck, binder como conceito próprio, status de empréstimo) cruzam para os módulos futuros `Decks`/`Trocas`/`Marketplace` — limites entre módulos ainda não decididos.
- Visão especulativa (não decidida, não implementada) de uma futura Edge Function orquestradora (`catalog-import`) que encadearia sozinha a criação de `asset_import_run` + sincronização + imagens por idioma, com uma tabela própria de acompanhamento — registrada apenas como ideia para quando o módulo de Coleções existir.

---

# Revision History

**Nota sobre esta revisão (`1.0`)**: a pedido explícito de Fabrício, este documento foi reescrito para registrar apenas a solução final confirmada do pipeline de importação, sem o histórico de tentativas, bugs corrigidos e etapas intermediárias que levaram até ela — cerca de 50 revisões incrementais (`0.1`–`0.48`), cobrindo dezenas de sprints (`B2.0`–`B3.28`), foram condensadas nas linhas abaixo. O objetivo é que qualquer pessoa consiga ler este documento uma única vez e executar o processo com sucesso, sem precisar reconstruir o caminho até aqui.

| Versão | Descrição |
|---------|-----------|
| 0.1–0.5 | Padrão geral de importação/sincronização definido (`ADR-008`); infraestrutura física de ativos visuais referenciada; correção de que a identidade visual pertence ao Set, não à Expansion. |
| 0.6–0.20 | Bloco B iniciado: ambiente local configurado, primeira Edge Function criada, publicada e testada em ciclos incrementais; `card_set_external_reference` criada para mapear `card_set` a identificadores da TCGdex; `external_set_id` reais descobertos para as 5 coleções via script administrativo. |
| 0.21–0.34 | Correção arquitetural real: biblioteca `@supabase/server` abandonada (HTTP 401 nunca resolvido com ela) em favor de `Deno.serve()` + `@supabase/supabase-js` manual. Padrão de bug recorrente descoberto: `GRANT` explícito para `service_role` é sempre necessário, mesmo com RLS habilitado — primeiro caso corrigido em `card_set_external_reference`. `ME0` removida do catálogo (coleção distinta de `mee`/TCGdex). Primeira resposta de ponta a ponta da TCGdex confirmada. |
| 0.35–0.42 | Incremento 1 (sincronização de `card_external_reference`) e Incremento 2 (download de imagens para `card_asset`) concluídos para a `ME1` (188/188, 0 falhas) e replicados sem alteração de código para as demais 4 coleções — catálogo completo em inglês: 859 cartas/referências/imagens, 0 falhas. |
| 0.43–0.48 | Fase 2 (`pt-BR`) concluída para as 5 coleções — bug real de código de idioma da TCGdex corrigido (`pt` ≠ `pt-BR`); catálogo completo nos dois idiomas: 1.718 assets/imagens, 0 falhas. Guia operacional de importação de nova coleção escrito a pedido de Fabrício. |
| 1.0 | **Reescrita completa do documento**, a pedido explícito de Fabrício: removido o histórico sprint a sprint de tentativas/bugs/versões intermediárias; adicionada a seção "Arquitetura Final" (processo real, não a especificação pré-implementação usada antes de o código existir); "Guia Operacional" mantido e formalizado como processo de 8 passos; "Em Aberto" reduzido aos itens genuinamente pendentes; seção "Primeira Aplicação Concreta — Seed de Card Variant" removida (conteúdo superado, execução real já documentada em `05-modelo-de-dados.md`). |
| 1.1 | Atualizado item de "Em Aberto" sobre consolidação de roadmap: registrada uma quarta forma paralela (`Fase 1-7`, esboçada pela sessão pareada e aparentemente endorsada por Fabrício), e o fato de que `ROADMAP.md` foi planejado como o primeiro documento formal desse roadmap, ainda não criado. Nenhuma consolidação decidida. |
| 1.4 | Item "Em Aberto" sobre consolidação de roadmap marcado como resolvido: `docs/ROADMAP.md` criado (2026-07-24), consolidando Now/Next/Later como fonte única de verdade, sem adotar nenhuma das formas paralelas anteriores não confirmadas por Fabrício. |
| 1.2 | **Documento dividido em três**, a pedido explícito de Fabrício (mesmo apesar da reescrita `1.0` já ter removido o histórico sprint a sprint, o documento ainda misturava arquitetura, guia operacional e estado atual): seções "Guia Operacional" e "Estado Atual" movidas para `operations/import-card-assets.md`; histórico condensado (tabela `0.1`–`1.1`, abaixo) reconstruído em prosa em `history/pipeline-sprint-log.md`. Este documento passa a conter apenas arquitetura/estratégia vigente. `03-documentation-architecture.md` atualizado para formalizar `operations/` e `history/` como novos tipos de artefato. Descobertas três pastas órfãs em `docs/` (`pipelines/`, `sprint/`, `editorial/`, todas vazias, nunca documentadas em `03-documentation-architecture.md`) — sinalizadas para Fabrício decidir (reaproveitar ou remover), não usadas nesta revisão por decisão explícita dele. |
| 1.5 | **Corrigido o campo "Status" do cabeçalho (2026-07-26)**, motivado por correção documental direcionada de Fabrício, com evidências confirmadas diretamente no Supabase. A redação anterior ("concluído... para as 5 coleções atuais") dava a entender que essas 5 coleções ainda eram o total vigente do catálogo, sem mencionar `MEE`/`MEP`. Reescrito para distinguir: as 5 coleções originais concluídas pelo pipeline automatizado (`import-card-assets`, escopo inalterado desta Edge Function); `MEE` concluída à parte, por importação manual; `MEP` ainda pendente; total atual `927` Cards / `1.734` Card Assets / `6` de `7` Card Sets com imagens completas; Catálogo Editorial (Bloco B) ainda não integralmente encerrado. Nenhuma outra seção deste documento foi alterada — os números `859`/`1.718` que permanecem no corpo do texto (Arquitetura Final, Guia Operacional, Revision History `0.35`–`0.48`) descrevem corretamente o resultado específico das 5 coleções originais processadas pela Edge Function, não o total atual do catálogo, e por isso foram preservados. |
| 1.3 | **Item de "Em Aberto" sobre a divergência `ADR-017` resolvido**, a pedido de Fabrício (auditoria de qualidade documental, 2026-07-24): criada `adr/ADR-018-single-function-import-pipeline.md`, formalizando a arquitetura de função única já descrita na seção "Arquitetura Final" (abaixo) como a decisão vigente; `ADR-017-two-function-import-pipeline.md` marcada como Substituída, histórico preservado. "Documentos Relacionados" atualizado para referenciar `ADR-018`. Nenhuma mudança de código ou de arquitetura real — apenas reconciliação entre documentação e implementação. |
