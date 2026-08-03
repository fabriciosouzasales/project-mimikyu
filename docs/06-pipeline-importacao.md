# Pipeline de Importação

| Campo | Valor |
|--------|-------|
| **Documento** | Pipeline de Importação |
| **Arquivo** | `docs/06-pipeline-importacao.md` |
| **Versão** | 1.6 |
| **Status** | Edge Function `import-card-assets` **CONFIRMADO CONCLUÍDA e operacional**, hoje em v2.9.3, com suporte real e simultâneo a `en`/`pt-BR` (idioma resolvido dinamicamente por `asset_import_run.language_id`, não mais fixo em código). Escopo de uso cresceu além das 5 coleções originais da Expansion `ME` — o mesmo pipeline processa hoje as imagens de Card Sets incorporados via `ADR-024` (Ciclo 2, ingestão TCGdex), incluindo pelo menos `SV1`–`SV5`/`SV3.5`/`SVE`/`SVP`/`ME5` (lista não exaustiva, ver handoff vigente). **Contagem exata do catálogo não é confirmável apenas por este documento** — a última contagem documentada por completo (`927` Cards / `1.734` Card Assets / `6` de `7` Card Sets da Expansion `ME` com imagens completas) é anterior ao crescimento via Ciclo 2 e reflete apenas o Bloco B original; para o estado agregado atual, ver `docs/README.md`. `MEP` (Expansion `ME`) permanece com imagens pendentes — ver `ROADMAP.md`, Trilha 1. |
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

## ~~⚠️ Limitação real atual — idioma é configuração fixa no código, não parâmetro~~ — RESOLVIDO E DEPLOYADO (2026-08-02, v2.9.0, confirmado; evoluído até v2.9.3)

Descrição histórica preservada por rastreabilidade: `index.ts` usava duas constantes fixas para controlar o idioma da execução, que precisavam ser mantidas em sincronia manualmente a cada troca de idioma (`LANGUAGE_CODE`/`TCGDEX_LANGUAGE`) — reimplantar a função era o único jeito de trocar o idioma de uma nova coleção.

**Resolvido e CONFIRMADO DEPLOYADO** (suporte real e simultâneo a EN + PT-BR, pedido explícito de Fabrício, ver `05-modelo-de-dados.md`, revisão `1.40`): `LANGUAGE_CODE`/`TCGDEX_LANGUAGE` removidas — o idioma agora vem de `asset_import_run.language_id`, resolvido por `admin_start_asset_import_run()` v1.3 (Query `2092`) a partir de um parâmetro `p_language_code` (`DEFAULT 'en'`). `TCGDEX_LANGUAGE_BY_CODE` (mapa local em `index.ts`) mantém a tradução `pt-BR` → `pt` no único lugar que ainda precisa dela. `source_url` também passou a usar o mesmo `language.code` resolvido dinamicamente. **Status de deploy:** Query `2092` v1.3/Migration `2093` e Edge Function v2.9.0 confirmadas publicadas por Fabrício (verificado via MCP do Supabase, ver `05-modelo-de-dados.md`, revisão `1.41`); a função evoluiu na sequência até **v2.9.3, CONFIRMADO DEPLOYADO** (timeout de download, correção de sobrescrita de erro, retry por download individual — ver `05-modelo-de-dados.md`, revisões `1.41`–`1.44`, e o handoff vigente).

**`card_external_reference` deixou de ser idioma-agnóstico (2026-08-02, Query `210` v2.0/Migration `277`)**: a tabela ganhou `language_id UUID NOT NULL` como parte da identidade da linha — as duas `UNIQUE` (`(card_id, asset_source_id)` e `(asset_source_id, external_card_id)`) passaram a incluir `language_id`. A "Nota real" abaixo (preservada por rastreabilidade) descreve o comportamento ANTES desta correção: o total ficou em `859` mesmo após importar as 5 coleções nos dois idiomas porque a execução em `pt-BR` fazia `UPSERT` sobre a mesma linha já criada pela `en`, em vez de criar uma segunda — a "decisão em aberto" mencionada ali foi resolvida a favor de adicionar `language_id` à chave.

---

# Guia Operacional e Estado Atual

Movidos para `operations/import-card-assets.md`, a partir da revisão `1.2`: o passo a passo de 8 etapas para importar uma nova coleção, e a tabela de estado atual confirmado (859 cartas, 1.718 assets, 1.718 imagens, 0 falhas). Este documento mantém apenas arquitetura e estratégia.

---

# Em Aberto

- **Estratégia de múltiplas fontes externas (multi-provider) — pendência arquitetural registrada, sem solução aprovada**, motivada por instabilidade real já observada na TCGdex (ex.: `TCGDEX_HTTP_502` transiente em `ME5`, 2026-08-02, resolvido sozinho, mas sem nenhum mecanismo de fallback). Ainda precisam ser decididos: providers candidatos (ex.: Pokémon TCG API); se um segundo provider seria usado para metadados, imagens, ou ambos; prioridade/ordem de tentativa; regra de fallback; tratamento diferenciado de timeout, 404, 429 e 5xx; rate limit; telemetria de disponibilidade por fonte; licenciamento de uso das imagens de cada fonte; disponibilidade por idioma; cobertura por Card Set. Não decidir unilateralmente nenhum destes pontos nem alterar `ADR-008` para registrá-los — cabe a Fabrício.
- Verificação de direitos/termos de uso das imagens antes de importação em massa (ver `05-modelo-de-dados.md`, seção "Arquitetura de Importação de Ativos") — ressalva registrada, não resolvida.
- ~~**Crítico**: transformar `language`/`asset_type`/`bucket` em parâmetros da requisição da Edge Function...~~ — **RESOLVIDO E DEPLOYADO (2026-08-02, v2.9.0)**: `language` agora vem de `asset_import_run.language_id`, ver seção acima. `asset_type`/`bucket` seguem fixos (`CARD_FRONT`/`card-front`) — fora do escopo desta rodada, nenhum pedido de Fabrício os tornou necessários ainda.
- ~~`source_url` em `card_external_reference` usa `LANGUAGE_CODE` em vez de `TCGDEX_LANGUAGE`~~ — **RESOLVIDO (2026-08-02, v2.9.0)**: ambos substituídos por `language.code`, resolvido dinamicamente.
- ~~`card_external_reference` sem dimensão de idioma na chave de unicidade~~ — **RESOLVIDO (2026-08-02, Query `210` v2.0/Migration `277`)**: `language_id` adicionado à chave, decisão confirmada por Fabrício ("Os dois idiomas (EN + PT-BR)").
- Auditoria consolidada de `GRANT`s para `service_role` em todo o schema `public` (`grants.sql` ou equivalente) — sete casos reais já encontrados um a um; consolidação deliberadamente adiada por Fabrício.
- Melhoria de idempotência: pular cartas que já têm `card_asset` atualizado, evitando novo download/upload em reexecuções — identificada, deliberadamente adiada.
- Buckets físicos `card-back`/`artwork` ainda não criados — só `card-front` existe.
- ~~Múltiplas formas paralelas de descrever o roadmap do projeto nunca foram consolidadas em uma única fonte de verdade~~ — **RESOLVIDO (2026-07-24)**: `ROADMAP.md` criado como fonte única de verdade (estrutura Now/Next/Later), sem adotar nenhuma das propostas anteriores não confirmadas por Fabrício.
- ~~`card_set.code = 'ME5'` ainda não cadastrado~~ — **RESOLVIDO**: `ME5` já foi cadastrado e teve imagens processadas por este pipeline (incidente de timeout/retry documentado em `05-modelo-de-dados.md`, revisões `1.41`–`1.44`, e no handoff vigente).
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
| 1.6 | **Auditoria de reconciliação documental (2026-08-02), a pedido de Fabrício.** Cabeçalho reescrito: `v2.9.0`/`v2.9.3` confirmadas deployadas (não mais "PROPOSTA — aguardando deploy"); escopo de uso do pipeline reconhecido como maior que as 5 coleções originais (Ciclo 2 de `ADR-024` passou a alimentar imagens de Card Sets adicionais via TCGdex); contagem exata do catálogo removida do cabeçalho (não confirmável só por este documento), substituída por referência a `docs/README.md`. Seção "Limitação real atual — idioma" reescrita de "RESOLVIDO... PROPOSTA — aguardando deploy" para "RESOLVIDO E DEPLOYADO", com a evolução até v2.9.3 registrada. "Em Aberto": item de `card_set.code = 'ME5'` marcado resolvido (já cadastrado, já processado por este pipeline); item de múltiplas fontes externas reescrito como pendência arquitetural explícita (multi-provider), com a lista de decisões ainda em aberto, sem propor solução nem alterar `ADR-008`. Nenhuma mudança de código, SQL ou decisão arquitetural nova. |
