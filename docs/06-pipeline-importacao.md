# Pipeline de Importação

| Campo | Valor |
|--------|-------|
| **Documento** | Pipeline de Importação |
| **Arquivo** | `docs/06-pipeline-importacao.md` |
| **Versão** | 0.40 |
| **Status** | Em elaboração |
| **Objetivo** | Definir a estratégia de importação e sincronização de dados de fontes externas para o Catálogo Editorial do Project Mimikyu. |
| **Escopo** | Estratégia de importação e sincronização, incluindo — desde a revisão `0.6` — a arquitetura de execução da Edge Function `import-card-assets` (Bloco B do roteiro de `05-modelo-de-dados.md`) e o roteiro de implementação incremental por sprints. Não é um manual operacional de deploy nem substitui o Supabase Dashboard/CLI reais. |
| **Dependências** | `02-architecture-principles.md`, `04-domain-model.md` |
| **Documentos Relacionados** | `adr/ADR-006-separation-of-catalog-ownership-and-analytics.md`, `adr/ADR-008-external-catalog-data-sources.md`, `adr/ADR-017-two-function-import-pipeline.md` |

---

# Purpose

Este documento descreve a estratégia geral de importação e sincronização de dados de fontes externas para o Catálogo Editorial do Project Mimikyu.

A decisão arquitetural que fundamenta este documento está registrada em `adr/ADR-008-external-catalog-data-sources.md`.

Este documento está em elaboração: o padrão estratégico já está definido, mas os mecanismos concretos de importação (frequência, formato intermediário, tratamento de falhas, etc.) ainda serão detalhados em ciclos futuros de documentação.

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

O catálogo interno do Project Mimikyu mantém registros próprios e independentes de:

- Game;
- Expansion;
- Set;
- Card;
- Card Translation;
- Card Variant.

---

# Por que o catálogo não depende de uma API externa em tempo real

Não foi identificada uma API oficial documentada mantida pela The Pokémon Company para integração de sistemas externos. Ferramentas amplamente utilizadas por desenvolvedores — como a Pokémon TCG API (atualmente integrada à plataforma Scrydex) e a TCGdex — são projetos independentes, não oficiais, cada um com sua própria base de dados.

Diante disso, o Project Mimikyu não deve assumir uma única fonte externa como definitiva, nem depender de qualquer uma delas como dependência estrutural em tempo real. A camada de Import/Synchronization existe justamente para isolar o catálogo dessas variações.

---

# Importação de Ativos Visuais (Imagens e Logos)

Além de dados editoriais estruturados, o mesmo padrão Import/Synchronization se aplica a ativos visuais (imagens de Card; logotipo completo e símbolo do Set — ver `04-domain-model.md`, seção Set — "Identidade Visual"): a fonte externa nunca é referenciada diretamente pela aplicação — o arquivo é importado via API e armazenado no Supabase (Storage), e o catálogo interno referencia o ativo já armazenado.

```text
External Data Source (imagem)
        ↓
Import / Synchronization
        ↓
Supabase Storage
        ↓
Project Mimikyu Catalog (referência ao ativo armazenado)
```

O banco físico já possui infraestrutura pré-existente para esse padrão (anterior a esta fase de consolidação documental, ver "Status Atual do Projeto" em `README.md`): `card_asset`, `card_asset_type`, `asset_source`, `asset_import_run`, `asset_import_failure`, `storage_bucket`. Essas tabelas ainda não foram documentadas em nível conceitual — previsto para um ciclo futuro.

**Correção (2026-07-22):** uma versão anterior deste documento atribuía `logo_url` à Expansion. Corrigido: a identidade visual pertence ao **Set** (`logo_url` e `symbol_url`, ver `04-domain-model.md` e `05-modelo-de-dados.md`, seção Set), não à Expansion. O princípio permanece o mesmo — importação automática via API, sem preenchimento manual — apenas a entidade destinatária foi corrigida.

---

# Benefícios do Modelo de Importação

- permite corrigir dados inconsistentes vindos de fontes externas;
- permite complementar informações ausentes;
- preserva os registros do catálogo caso uma fonte externa seja descontinuada;
- permite integrar mais de uma fonte de dados simultaneamente;
- mantém controle sobre os códigos internos do catálogo;
- permite registrar a procedência (fonte) de cada informação importada.

---

# Em Aberto

Os seguintes pontos ainda não foram definidos e serão tratados em ciclos futuros de documentação:

- quais fontes externas específicas serão efetivamente integradas — **parcialmente respondido para Card Variant** (ver abaixo); **respondido para imagens de Card** (TCGdex como fonte principal, Pokémon TCG API como alternativa — ver seção "Arquitetura de Execução", abaixo); segue em aberto para as demais entidades do catálogo;
- formato e frequência de importação/sincronização — **parcialmente respondido**: execução em lotes pequenos (recomendação inicial de 20 cartas por chamada), sob demanda via Edge Function; agendamento automático (`execution_context = SCHEDULED`) já previsto no modelo de dados (`220`/`221`), mas ainda não implementado;
- estratégia de tratamento de falhas e reprocessamento — **respondido a nível de arquitetura** (`failure_stage`/`error_code`, `RETRY_FAILURES` — ver seção "Arquitetura de Execução", abaixo); implementação real ainda pendente;
- estratégia de resolução de conflitos entre múltiplas fontes;
- documentação conceitual formal do padrão de ativos visuais (`card_asset`, `card_asset_type`, `asset_source`, `asset_import_run`, `asset_import_failure`, `storage_bucket`) e se essa infraestrutura, hoje nomeada em torno de Card, se generaliza para Set (que precisará de `logo_url` e `symbol_url` — ver `04-domain-model.md`) ou se recebe uma estrutura própria;
- convenção de pasta para versionar código de Edge Function no repositório (análoga a `database/` para SQL) — **parcialmente resolvida nesta revisão**: o padrão natural da própria CLI do Supabase (`supabase/functions/<nome-da-função>/`) foi adotado e o código confirmado do Sprint B2.1/B2.3 foi copiado para o repositório oficial em `supabase/functions/import-card-assets/index.ts`, mesmo princípio de "copiar apenas após execução confirmada" já usado em `database/`; ainda não confirmado por Fabrício se esta é a convenção definitiva, nem a divergência entre a estrutura mais ampla proposta pela sessão pareada e a estrutura real já em uso em `database/` (ver nota da seção "Sprint B2.0", abaixo);
- se a pasta local `C:\Users\Administrador\Project-Mimikyu` (criada no Sprint B2.0 para desenvolvimento das Edge Functions) corresponde a um clone do repositório GitHub oficial `fabriciosouzasales/project-mimikyu` ou é um ambiente de trabalho local separado — ver "Sprint B2.0", abaixo;
- verificação de direitos/termos de uso das imagens antes de importação em massa (ver `05-modelo-de-dados.md`, seção "Arquitetura de Importação de Ativos" — ressalva registrada, não resolvida);
- ~~novo, Sprint B2.5A: se `ME0` deve ser mapeado ao Set oficial `mee`/"Mega Evolution Energy" da TCGdex (Opção B) ou permanecer uma coleção 100% interna, sem vínculo com a TCGdex (Opção A)~~ — **resolvida no Sprint B3.7**: Fabrício confirmou que `ME0` (promocionais de Mega Evolução) e `mee` (Energias de Mega Evolução) são coleções diferentes, sem relação. `ME0` foi removida de `card_set` por completo (Migration `251`), não apenas deixada sem mapeamento. Ver `05-modelo-de-dados.md`, "Migration 251 — Remoção de ME0".
- **novo, Sprint B3, refinado no Sprint B3.9/B3.10, RESOLVIDO por escopo no Sprint B3.12**: o endpoint `GET /sets/{id}/cards` da TCGdex nunca foi chamado diretamente (lista resumida vem embutida em `getSet()`); e o endpoint de carta individual (`getCard`), cogitado para obter raridade/categoria/número total, **não é necessário para o incremento de `card_external_reference`** — esses campos já existem em `card` (Bloco A concluído). Pode voltar a ser relevante no futuro, apenas se o projeto decidir enriquecer `card` com dados adicionais da TCGdex além dos já cadastrados;
- **novo, Sprint B3.10, crítico**: proposta de `docs/adr/` com ADRs `001`-`005` (`banco-como-fonte-da-verdade`, `multiplos-provedores`, `modelo-editorial-da-carta`, `assets-desacoplados`, `importacoes-idempotentes`), sugerida pela sessão pareada sem ciência de que este repositório já possui 17 ADRs aprovados, incluindo `ADR-001` a `ADR-005` reais e com temas completamente diferentes — colisão de nome de arquivo se executada como proposta. Nenhum arquivo criado. Mesma decisão pendente de Fabrício já registrada para `docs/architecture.md` (Sprint B3.9): documento adicional, incorporação à estrutura existente, ou apenas informar a sessão pareada da estrutura já consolidada;
- **novo, Sprint B3.10**: nome da futura função de download de imagens divergente entre revisões — `ADR-017-two-function-import-pipeline.md` a chama de `sync-card-set` (papel redefinido de `import-card-assets`), mas a sessão pareada, nesta revisão, chamou a mesma peça futura de `download-card-assets`, mantendo `import-card-assets` com o papel de descoberta/sincronização que hoje ela de fato exerce — não resolvido unilateralmente se `ADR-017` precisa de um ADR sucessor ou se foi apenas um nome informal usado na conversa;
- **novo, Sprint B3.10**: o faseamento `FASE 1-6`/backlog `Sprint 1-2`, proposto pela sessão pareada como disciplina de foco após uma intervenção direta de Fabrício, ainda não foi reconciliado com o "Roteiro vigente" (`B2.5A`-`B2.9`) já existente nesta seção — mesma pendência de mapeamento aberta desde o Sprint B3, agora com um segundo framing paralelo a conciliar;
- **novo, Sprint B3**: mapeamento entre o roteiro vigente (`B2.5B`–`B2.9`) e a nova arquitetura de duas Edge Functions (`sync-card-set`/`import-card-assets`) — ver `ADR-017-two-function-import-pipeline.md` — ainda não detalhado por Fabrício; tabela "Roteiro vigente" mantida sem reescrita até essa confirmação.
- **novo, Sprint B3 (continuação)**: se `tcgdex.ts` (classe `TcgdexClient`) será compartilhado entre `import-card-assets` e a futura função `sync-card-set`, ou se a criação de `sync-card-set` como Edge Function própria foi tacitamente adiada — a implementação real segue dentro de `import-card-assets/services/`, divergindo do plano anunciado na mesma revisão; não resolvido unilateralmente.
- **novo, Sprint B3.1**: `card_set.code = 'ME5'` ainda não foi cadastrado no banco físico — confirmado por consulta real; quando for, a Query `910` (idempotente) deve ser reexecutada para popular seu mapeamento automaticamente.
- **novo, Sprint B3.4**: conteúdo completo de `supabase/config.toml` ainda não recebido — apenas o fragmento `[functions.import-card-assets]` (`verify_jwt = false`) foi confirmado; o arquivo não pôde ser copiado ao repositório por falta do conteúdo integral.
- **novo, Sprint B3.4**: a forma correta de configurar autenticação (`auth: ["secret"]`) para `@supabase/server@^1` continua sem confirmação real — duas hipóteses (header `apikey`, `verify_jwt = false`) já se mostraram insuficientes; precisa ser resolvida antes de reativar a autenticação, planejado para depois que o pipeline estabilizar.
- **novo, Sprint B3.5**: causa raiz real do HTTP 401 ainda desconhecida — confirmado por teste real que remover `auth: ["secret"]` de `withSupabase(...)` sozinho NÃO resolve o problema (correção à recomendação da revisão `0.23`); teste de isolamento definitivo (substituir `index.ts` de `import-card-assets` por um `Deno.serve()` mínimo, sem `withSupabase`) foi detalhado mas ainda não executado. **Resolvido no Sprint B3.6**: o teste mínimo confirmou o problema em `withSupabase`; `@supabase/server` foi abandonado; o 401 foi eliminado.
- ~~novo, Sprint B3.5: não confirmado se o Dashboard do Supabase estava servindo a versão mais recente do `index.ts` durante os testes desta revisão~~ — superado pelo Sprint B3.6 (arquitetura mudou por completo; a dúvida específica não se aplica mais).
- **novo, Sprint B3.6**: uma resposta final `success: true` com `tcgdex_set` populado por uma chamada real de ponta a ponta ainda não foi explicitamente confirmada — todos os bloqueios conhecidos (401, GRANT ausente) foram eliminados, mas o teste final decisivo do Bloco B ainda está pendente.
- **novo, Sprint B3.6, reforçado no Sprint B3.15**: o mesmo gap de `GRANT` ausente para `service_role`, encontrado em `card_set_external_reference` (Query `250`), foi confirmado uma segunda vez em `card_external_reference` (Query `253`, Sprint B3.15) — auditoria completa em todas as tabelas do schema `public` continua não executada; Fabrício propôs consolidar em um único script futuro (`permissions.sql` ou equivalente), adiado para depois do Incremento 2.
- ~~novo, Sprint B3.16: estrutura real de `storage_bucket` ainda não confirmada~~ — **resolvida no Sprint B3.17**: estrutura confirmada (catálogo interno de metadados, não o bucket físico); três registros mapeados 1:1 a `card_asset_type`; bucket físico `card-front` criado.
- ~~novo, Sprint B3.18: terceiro caso real confirmado do mesmo gap de GRANT ausente para `service_role`, em `language`~~ — **resolvido no Sprint B3.19**, junto com mais três casos reais (`card_asset_type`/`card_asset`/`expansion`, Query `254`). Seis casos reais confirmados no total (Queries `250`/`253`/`254`).
- ~~novo, Sprint B3.18: execução real do teste controlado do Incremento 2 ainda não confirmada~~ — **resolvido no Sprint B3.19** (teste controlado com sucesso) e **escalado com sucesso no Sprint B3.20** (188/188 imagens, 0 falhas).
- **novo, Sprint B3.15, reforçado nos Sprints B3.19/B3.20, crítico**: auditoria consolidada de GRANTs para `service_role` em todas as tabelas do schema `public` (`grants.sql` ou equivalente) segue deliberadamente adiada, agora com **seis casos reais confirmados** do mesmo padrão. Fabrício decide quando priorizar.
- **novo, Sprint B3.20**: melhoria de idempotência para o Incremento 2 (pular cartas que já têm `card_asset`, evitando novo download/upload em reexecuções) — identificada e **deliberadamente adiada** por decisão explícita de Fabrício, para não interromper o fluxo perto da conclusão da `ME1`.
- **novo, Sprint B3.20**: buckets físicos `card-back`/`artwork` ainda não criados no Supabase Storage — só `card-front` existe; criar quando forem necessários (verso da carta e ilustração ainda não fazem parte do escopo do Incremento 2).
- **novo, Sprint B3.20**: replicar o Incremento 1 (já confirmado para a `ME1`) e o Incremento 2 (agora também confirmado para a `ME1`) para `ME2`/`ME2.5`/`ME3`/`ME4` — ainda não iniciado.
- ~~novo, Sprint B3.7: um novo `asset_import_run` para `ME1` (ou outra coleção suportada) ainda não foi criado~~ — **resolvido no Sprint B3.8**: `asset_import_run` real criado, Edge Function reinvocada, resposta real `success: true` confirmada com dados reais do Set `me01` da TCGdex.
- **novo, Sprint B3.8**: Stored Procedure de orquestração (`start_asset_import`/`finish_asset_import`/`fail_asset_import`) explicitamente adiada para depois que a persistência de cartas estiver funcional (Fase 2 do roteiro proposto nesta revisão).
- **novo, Sprint B3.8**: migração de `run_type`/`status`/`execution_context` (`text` + `CHECK`) para tipos `ENUM` nativos do PostgreSQL, proposta e explicitamente adiada até o fluxo de importação estar funcional.
- **novo, Sprint B3.8**: reestruturação de pastas da Edge Function em camadas (`application`/`infrastructure`/`domain`), proposta e explicitamente adiada; menção a um possível rename para `import-card-set` não confirmada como intencional.
- **novo, Sprint B3.8**: persistência real das cartas retornadas pela TCGdex em `card`/`card_external_reference` — próximo passo real do pipeline, ainda não implementado.
- **novo, Sprint B3.9, crítico**: proposta de `docs/architecture.md` como "especificação oficial" do projeto, sugerida pela sessão pareada, aparentemente sem ciência da documentação já existente neste repositório (`00`-`07`, ADRs, STDs). **Não criado nesta revisão.** Fabrício precisa decidir: documento adicional de síntese, incorporação à estrutura existente, ou descarte da proposta.
- **novo, Sprint B3.9, CORRIGIDO no Sprint B3.11**: implementar a persistência real de `card_external_reference` a partir das 188 cartas resumidas já confirmadas da TCGdex para `ME1` — fluxo corrigido: `asset_import_run`→`card_set_external_reference`→TCGdex→**localizar `card` já existente** (não inserir)→`card_external_reference`→`card_asset` depois; ainda não codificado. Escopo real ampliado no Sprint B3.11 para as 5 coleções (`ME1`/`ME2`/`ME2.5`/`ME3`/`ME4`), com `ME1` servindo de implementação-modelo.
- **novo, Sprint B3.11**: três framings de roadmap coexistem sem reconciliação — "Roteiro vigente" `B2.x`/`B3.x` (granular, seção acima), `FASE 1-6`/`Sprint 1-2` (Sprint B3.10) e `FASE 1-4`/três Entregas (Sprint B3.11) — nenhum promovido a reescrita oficial; Fabrício precisa decidir se e como consolidar.
- **novo, Sprint B3.7**: Query `820` v2.0 (Seed canônica de Card Set, em `05-modelo-de-dados.md`) ainda insere `ME0` em uma instalação nova — precisa ser reescrita para não reintroduzir a linha removida pela Migration `251`.
- **novo, Sprint B3.7**: validação prévia de integração externa antes de criar um `asset_import_run` (recusar a criação se não houver `card_set_external_reference` ativo para a coleção) — proposta, não implementada.
- **novo, Sprint B3.7**: discrepância de `asset_source_id` observada entre a execução de teste removida e os registros existentes em `card_set_external_reference` — nunca explicada; baixa prioridade, já que `ME0` foi removida.

---

# Primeira Aplicação Concreta — Seed de Card Variant (`860`)

Escopo restrito: apenas para popular a tabela `card_variant` (ver `04-domain-model.md`, seção Card Variant Type/Card Variant, e `05-modelo-de-dados.md`, seção Card Variant). Não é ainda uma definição geral de pipeline para as demais entidades do catálogo.

Fontes identificadas e seus papéis:

- **Checklist oficial da Pokémon** (já usado como fonte primária para `840`): confirma quais Cards existem, numeração, raridade e a impressão principal — mas nem sempre lista individualmente variantes paralelas (`REVERSE_HOLO`, `POKE_BALL_REVERSE`, `MASTER_BALL_REVERSE`).
- **TCGdex**: expõe por Card um campo `variants` (`normal`/`reverse`/`holo`/`firstEdition`) que descreve explicitamente quais impressões são conhecidas — fonte estruturada principal proposta para `860`.
- **Pokémon TCG API**: não tem campo tão direto, mas seu objeto de preços (`normal`/`holofoil`/`reverseHolofoil`) serve como evidência complementar — não deve ser usada isoladamente, já que ausência de preço não comprova ausência da variante.

Pipeline proposto (ainda não implementado, apenas decidido): `Checklist oficial + TCGdex variants + Pokémon TCG API (evidência complementar) + validação manual de exceções (POKE_BALL_REVERSE, MASTER_BALL_REVERSE, PROMO_STAMPED — exigem tratamento individual por Card Set) → dataset intermediário rastreável (fonte + status de validação por linha) → Query 860`. Dado o volume estimado, o Seed será dividido e validado por Card Set (`860A`–`860E`), consolidado depois na Query canônica `860`.

---

# Arquitetura de Execução — Edge Function `import-card-assets` (Bloco B1)

Ver `05-modelo-de-dados.md`, seção "Roteiro Consolidado — Fases e Blocos", para o posicionamento deste bloco dentro do roteiro geral (Fase 1 — Catálogo Editorial: Bloco A concluído, **Bloco B iniciado nesta revisão**, Bloco C pendente).

Antes de escrever qualquer código, a sessão pareada de Fabrício apresentou uma especificação completa das responsabilidades da Edge Function `import-card-assets`. Resumo por etapa:

**1. Validar a execução.** Ao ser chamada, a função consulta `asset_import_run` e verifica: o registro existe; o `status` é `PENDING` ou `RUNNING`; o `asset_source` referenciado está ativo; o `card_set` e o `language` (quando informados) existem; o `run_type` é suportado. A transição `PENDING → RUNNING` é feita pela própria função ao iniciar — o preenchimento de `started_at` continua a cargo do trigger de governança já existente (`221`, ver `05-modelo-de-dados.md`).

**2. Selecionar as cartas.** A seleção parte do `card_set_id` da execução e varia por `run_type`: `MISSING_ONLY` seleciona cartas sem o ativo esperado; `REFRESH_EXISTING` seleciona cartas que já possuem imagem e podem ser atualizadas; `RETRY_FAILURES` seleciona apenas cartas com falhas não resolvidas em `asset_import_failure`; `SINGLE_CARD` seleciona a carta indicada em `parameters.card_id`; `FULL_CARD_SET` seleciona todas as cartas do `card_set`.

**3. Resolver a referência externa.** Para cada carta: procurar uma referência ativa em `card_external_reference`; se existir, reutilizar `external_card_id`/`image_source_url`; se não existir, consultar a fonte externa, confirmar a correspondência (por `card_set` + número da carta + idioma + fonte — o nome da carta serve apenas como verificação auxiliar, nunca como chave principal) e criar o registro em `card_external_reference`.

**4. Fontes de dados, em ordem de prioridade.** Primeira fonte: **TCGdex** — suporte multilíngue, dados de cards/sets, imagens com escolha de extensão/qualidade, API REST relativamente simples; a disponibilidade de imagem depende de ela já ter sido contribuída e processada pela própria TCGdex, portanto a ausência de imagem para uma carta/idioma deve ser tratada como falha recuperável, não como erro estrutural do sistema. Segunda fonte, usada como alternativa quando a primeira não tiver a imagem adequada: **Pokémon TCG API**.

**5. Download e validação.** `HTTP GET` da URL externa; antes de aceitar o arquivo: resposta HTTP entre 200-299; corpo não vazio; `Content-Type` válido; tamanho máximo; assinatura básica do arquivo; formato permitido (`image/png`, `image/jpeg`, `image/webp` aceitos na origem). O arquivo é mantido em memória como `ArrayBuffer`; o armazenamento efêmero em `/tmp`, disponível em Edge Functions, só deve ser usado quando a transformação exigir arquivo intermediário.

**6. Formato canônico.** A convenção já definida é `front.png`. Decisão para a primeira versão: preservar o conteúdo original quando ele já for PNG, convertendo apenas JPEG/WebP quando necessário — evita o custo de CPU/memória de converter tudo indiscriminadamente logo na primeira prova de conceito.

**7. Caminho no Storage.** Confirma, sem alterar, a convenção já fixada em `05-modelo-de-dados.md` (seção "Query 231", nota de convenção de caminho): bucket `card-front`, caminho `pokemon/{card-set-code}/{language-code}/{card-number}/front.png` (ex.: `pokemon/me1/pt-BR/001/front.png`, `pokemon/me2.5/pt-BR/217/front.png`, `pokemon/me3/en/088/front.png`). Nesta revisão a variável foi renomeada em prosa para `card-set-code` (antes referida como `collection-code`) — mesmo ajuste terminológico já aplicado ao dado físico em `220`/`221` (`collection_id` → `card_set_id`). Antes de montar o caminho, `card-set-code` é normalizado para minúsculas, `language-code` segue o código oficial cadastrado, e `card-number` segue a numeração canônica do catálogo.

**8. Política de upload (`upsert`).** `MISSING_ONLY` e `FULL_CARD_SET`: `upsert = false` — o sistema nunca deve sobrescrever silenciosamente um arquivo já existente. `REFRESH_EXISTING`: `upsert = true` — substituição explicitamente autorizada pelo tipo da execução. `RETRY_FAILURES`: depende da etapa da falha original — `upsert = false` se a falha ocorreu antes do upload; verificação de existência do objeto se a falha ocorreu após upload parcial; caso contrário, respeita o contexto da execução original.

**9. Registro em `card_asset`.** Só é criado ou atualizado **depois** do upload confirmado — nunca antes, para não presumir que o upload funcionará. O registro aponta para carta, tipo de ativo, idioma, bucket, caminho interno, MIME type, tamanho, dimensões, hash e origem, além do status ativo.

**10. Hash e idempotência.** A função calcula `SHA-256` do conteúdo baixado (reaproveitando `checksum_sha256`, já existente em `card_asset` e nunca usado até agora — ver `05-modelo-de-dados.md`, seção "Arquitetura de Importação de Ativos"). Antes do upload, verifica se já existe `card_asset` para aquela combinação carta+idioma+tipo, se o caminho já existe, e se o hash é igual — se for, o resultado é `SKIPPED_ALREADY_CURRENT` e o item soma em `skipped_count`, não em `success_count`/`failed_count`. Reexecutar a mesma operação não deve gerar registros duplicados nem resultados inconsistentes.

**11. Tratamento de falhas.** Cada falha de carta é registrada em `asset_import_failure` (ver `05-modelo-de-dados.md`, "Query 230"), com exemplos de `failure_stage`/`error_code`: `REFERENCE_LOOKUP`/`EXTERNAL_CARD_NOT_FOUND`; `SOURCE_REQUEST`/`HTTP_429`; `DOWNLOAD`/`DOWNLOAD_TIMEOUT`; `VALIDATION`/`INVALID_CONTENT_TYPE`; `TRANSFORMATION`/`IMAGE_CONVERSION_FAILED`; `STORAGE_UPLOAD`/`STORAGE_UPLOAD_FAILED`; `CARD_ASSET_WRITE`/`DATABASE_WRITE_FAILED`. O pipeline segue para a próxima carta sempre que a falha for isolada a um item; apenas uma falha estrutural (fonte inexistente, credencial inválida, bucket inexistente, configuração incoerente, banco indisponível) encerra toda a execução.

**12. Contadores e status final.** Cada item processado incrementa `processed_count` e, conforme o resultado, `success_count`, `failed_count` ou `skipped_count`. Ao final: `failed_count = 0` → `COMPLETED`; `failed_count > 0` e houve sucessos → `COMPLETED_WITH_ERRORS`; nenhuma carta processada por falha estrutural → `FAILED` — a mesma máquina de estados já validada pelo trigger `govern_asset_import_run()` (`221`).

**13. Segurança.** A função usa internamente a credencial de serviço do projeto (`service_role`), mantida em secrets da Edge Function — nunca exposta ao cliente, junto com tokens das APIs externas, detalhes internos do banco e mensagens técnicas completas. Na primeira fase, a execução da função fica restrita a chamadas administrativas.

**Correção confirmada na seção "Sprint B2.3", abaixo (revisão `0.10`)**: `ctx.supabaseAdmin`, fornecido pelo runtime atual das Edge Functions (`withSupabase`), **não ignora os GRANTs do PostgreSQL** — continua respeitando os privilégios efetivamente concedidos à role `service_role`. A primeira tentativa real de leitura de `asset_import_run` falhou com erro `42501` (permissão negada) até que um `GRANT SELECT` explícito fosse aplicado. Ou seja, "usar a credencial de serviço" não é sinônimo de acesso irrestrito ao banco — cada tabela lida por uma Edge Function precisa de um `GRANT` explícito para `service_role`.

**14. Estrutura de arquivos prevista — versão refinada (ver "Sprint B2.1", abaixo, para a versão adotada de fato, ligeiramente diferente desta proposta inicial):**

```text
supabase/functions/import-card-assets/
├── index.ts
├── types.ts
├── config.ts
├── services/
│   ├── database.ts
│   ├── storage.ts
│   ├── image.ts
│   └── import-run.ts
├── sources/
│   ├── source-adapter.ts
│   ├── tcgdex.ts
│   └── pokemon-tcg-api.ts
└── utils/
    ├── errors.ts
    ├── hash.ts
    └── paths.ts
```

Para a primeira prova de conceito, a implementação começa menor (um único arquivo) e só é separada em módulos quando houver comportamento real para cada um.

---

# Roteiro de Implementação Incremental — Bloco B (Sprints B2.0–B2.8)

Depois de apresentar a arquitetura completa acima, Fabrício pediu explicitamente para reduzir a verbosidade do processo de trabalho: *"Siga. Vamos ser um pouco mais objetivo nessa fase."* A sessão pareada concordou e adotou um ritmo de ciclos curtos — **Objetivo → Implementar → Validar → Evoluir** — entregando por sprint apenas objetivo, código, forma de validar e próximo passo, sem repetir a arquitetura já registrada acima.

**Disciplina de execução refinada e formalizada em revisão posterior desta seção**, depois que Fabrício interrompeu diretamente para perguntar se deveria executar algum dos códigos já mostrados: *"Vamos com calma. Eu deveria executar algum desses códigos? Até agora não executei nenhum código."* A sessão pareada confirmou que **nada do Sprint B2.1 nem do B2.2 havia sido executado até aquele ponto** — apenas descrito — e adotou, para código, a mesma disciplina já usada para SQL: **um passo → Fabrício executa → validação → só então o próximo passo**, em vez de apresentar vários sprints em sequência antes de qualquer execução real. Esta seção documenta o roteiro planejado; a marcação `(CONFIRMADO)` em cada sprint abaixo indica execução real, verificada por evidência (captura de terminal ou saída explícita), no mesmo padrão já aplicado a Queries SQL.

**Convenções permanentes para Edge Functions, declaradas nesta revisão como regras do projeto (mesmo status de decisão que os Standards de `docs/standards/`, embora ainda não promovidas a um STD formal):**

1. **Nunca criar arquivos de Edge Function "na mão".** Toda nova função nasce via `npx supabase functions new <nome-da-função>`, garantindo que siga o padrão oficial da CLI do Supabase.
2. **Nunca alterar o template oficial gerado pela CLI sem necessidade — sempre evoluir sobre ele**, não substituí-lo. Facilita absorver futuras atualizações da própria CLI.
3. **Responsabilidade única** — cada Edge Function faz apenas uma coisa.
4. ~~**Execução restrita por padrão** (`auth: ["secret"]`)~~ — **SUPERSEDIDA no Sprint B3.6**: depois de três revisões reais (B3.3/B3.4/B3.5) sem conseguir autenticar com sucesso via `@supabase/server`/`withSupabase`, a biblioteca foi abandonada por completo. Ver Convenção 8, abaixo, para a substituta real e confirmada.
5. **"Nunca avançar sem validar", aplicado ao código** — mesmo princípio já usado nas migrations SQL. Cada Sprint só se encerra quando atinge um critério de aceite explícito e verificado (ex.: B2.2 — "a função responde `status: ready`"; B2.3 — "a função consegue localizar uma execução pelo `run_code`").
6. **`index.ts` apenas orquestra** — não conhece SQL/PostgreSQL/fontes externas diretamente, apenas coordena chamadas a serviços especializados (declarada no Sprint B2.4.1).
7. **Fluxo padrão de validação antes de cada deploy, declarada no Sprint B3.3**: `deno check index.ts` executado de dentro da pasta da função (onde está o `deno.json` real dela), seguido de `npx supabase functions deploy <nome-da-função>` executado na raiz do projeto (onde está o `config.toml`). Motivação real: `deno check` rodado da raiz do projeto ignora o `deno.json` da função e produz erros de dependência enganosos — misturar os dois contextos (Deno puro vs. runtime do Supabase) gerou um ciclo de depuração desnecessário nesta revisão.
8. **Cliente Supabase manual, declarada no Sprint B3.6** — toda Edge Function cria seu próprio cliente Supabase via `createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!)` (`@supabase/supabase-js`), uma única vez, no escopo do módulo; não usa `withSupabase`/`@supabase/server`. Validações de método HTTP, corpo da requisição e payload passam a ser responsabilidade explícita de `index.ts`. Motivação real: um teste mínimo confirmou, por evidência real, que um HTTP 401 persistente e não diagnosticável ao longo de três revisões tinha origem em `withSupabase`; `@supabase/supabase-js` é o SDK padrão, mais simples, mais explícito e não depende de comportamento interno não documentado de `@supabase/server`.

**Descoberta técnica confirmada nesta revisão**: a versão `2.109.1` da Supabase CLI gera um template de Edge Function diferente do que havia sido planejado nas revisões `0.6`-`0.8` (que assumiam o padrão antigo baseado em `serve()` de `https://deno.land/std/http/server.ts`). O template atual usa `withSupabase(...)`, importado de `@supabase/server`, que já injeta automaticamente `ctx.supabase`, `ctx.supabaseAdmin`, autenticação e o contexto da requisição. Decisão registrada: **adotar o template atual da CLI**, não substituí-lo pelo padrão antigo — consistente com a Convenção 2, acima. Todo código de Edge Function mostrado nas revisões `0.6`-`0.8` baseado em `serve()`/`createClient` manual está **obsoleto** e não deve ser usado como referência de implementação — mantido nas seções abaixo apenas como registro histórico do que havia sido inicialmente planejado.

**Roteiro renumerado e consolidado nesta revisão** — de 13 sprints (`B2.0`–`B2.12`) para 9 (`B2.0`–`B2.8`), reduzindo a granularidade de alguns passos (a criação de `card_external_reference`, o registro de falhas, o processamento em lote e a execução de um `card_set` completo deixam de ser sprints numerados isolados e passam a fazer parte do escopo mais amplo dos sprints `B2.6`/`B2.7`, a serem detalhados quando alcançados). Registrado explicitamente aqui, no mesmo espírito da comparação de roteiro feita em `05-modelo-de-dados.md` (seção "Roteiro Consolidado — Fases e Blocos") após o incidente de confiança da revisão `0.49`, para que a renumeração fique clara e não pareça uma sequência inventada:

```text
Roteiro original (revisão 0.6)         →  Roteiro consolidado (esta revisão)
B2.0 Preparar ambiente local           →  B2.0 Ambiente ✅
B2.1 Criar Edge Function básica        →  B2.1 Primeira Edge Function ✅
B2.2 Testar acesso ao banco            →  B2.2 Deploy e Teste ✅
B2.3 Ler um asset_import_run           →  B2.3 Integração com Banco 🟪
B2.4 Consultar uma carta na TCGdex     →  B2.4 Integração com TCGdex 🟪
B2.5 Baixar uma imagem                 →  B2.5 Download 🟪
B2.6 Enviar uma imagem ao Storage      →  B2.6 Storage 🟪
B2.7 Criar card_external_reference     →  B2.7 Card Asset 🟪  (absorve card_external_reference + card_asset)
B2.8 Criar card_asset                  →  B2.8 Carga 880 🟪  (absorve falhas/lote/card_set completo)
B2.9 Registrar falha                   →  (absorvido em B2.6/B2.7, escopo a detalhar)
B2.10 Processar um pequeno lote        →  (absorvido em B2.7/B2.8, escopo a detalhar)
B2.11 Executar um card_set completo    →  (absorvido em B2.8, escopo a detalhar)
B2.12 Realizar a carga oficial (880)   →  B2.8 Carga 880
```

Roteiro vigente:

| Sprint | Escopo | Status |
|--------|--------|--------|
| B2.0 | Ambiente (VS Code, Node.js, Supabase CLI, projeto local vinculado ao remoto) | ✅ Concluído |
| B2.1 | Primeira Edge Function (`import-card-assets`, esqueleto + resposta estática) | ✅ Concluído |
| B2.2 | Deploy e Teste (primeira publicação real + invocação remota autenticada) | ✅ Concluído |
| B2.3 | Consulta de Execução (`asset_import_run` por `run_code`) | ✅ Concluído |
| B2.4 | Descoberta das Cartas (`card_set` + listagem de `card` da execução) | ✅ Concluído |
| B2.4.1 | Refatoração para Services (`services/database.ts` + `types.ts`, sem nova funcionalidade) | ✅ Concluído |
| B2.5A | Integração com TCGdex — apenas consulta e recebimento do JSON (agora pelo `card_set`, via `card_set_external_reference`) | ✅ **CONCLUÍDO (Sprint B3.8, marco real)** — `index.ts` v2.0.0/`database.ts`/`tcgdex.ts` deployados, invocação de ponta a ponta CONFIRMADA com resposta real da TCGdex para `ME1` (Set `me01`, "Mega Evolution", 188 cartas). `ME0` removido do escopo (Migration `251`). |
| B2.5B | Extração da URL da imagem, download e validação | 🟪 Não iniciado |
| B2.6 | Download *(possível sobreposição com B2.5B — ver nota abaixo, não resolvida unilateralmente)* | 🟪 Não iniciado |
| B2.7 | Upload Storage | 🟪 Não iniciado |
| B2.8 | Criar `card_asset` (inclui `card_external_reference` e tratamento de falha) | 🟪 Não iniciado |
| B2.9 | Carga `880` (orquestração final, processamento em lote e execução de `card_set` completo) | 🟪 Não iniciado |

**Nota sobre a granularidade deste roteiro, a partir da revisão `0.11`**: a partir do Sprint B2.3, o time passou a fechar cada sprint com um **Diário Técnico** (Objetivo/Critério de Aceite/Resultado/Pendências Descobertas — convenção formalizada na revisão `0.11`, ver "Sprint B2.3", abaixo) e a ajustar o escopo dos sprints seguintes com base no que realmente foi encontrado durante o desenvolvimento (ex.: "Ler `card_set`" e "Listar cartas" foram fundidos em um único `B2.4`, por decisão explícita registrada na própria seção do sprint). Este roteiro é mantido como visão consolidada aproximada; o **Diário Técnico de cada sprint é a fonte de verdade mais granular** sobre o que foi de fato decidido e executado.

**Nota sobre `B2.5B`/`B2.6`, registrada na revisão `0.12`, não resolvida unilateralmente**: a proposta de `B2.5B` ("extrair URL da imagem → download → validar imagem") descreve um escopo que parece sobrepor o que o roteiro consolidado da revisão `0.9` já reservava para `B2.6` ("Download"). Este documento não decide isso por conta própria — Fabrício precisa confirmar se `B2.6` deve ser considerado absorvido por `B2.5B` (caso em que o roteiro deveria ser renumerado novamente) ou se os dois têm escopos de fato distintos que ainda serão detalhados.

## Sprint B2.0 — Preparar o ambiente local (CONFIRMADO CONCLUÍDO)

Sprint inserido na revisão `0.7`, antes de qualquer execução real de código, e **concluído integralmente nesta revisão** — todos os passos abaixo têm evidência real de terminal, um de cada vez, seguindo a disciplina descrita acima. Até o início deste sprint, **100% do trabalho de banco de dados (tabelas, triggers, RLS, migrations) tinha sido feito com sucesso apenas pelo painel web do Supabase** — suficiente para SQL, mas não para Edge Functions, que são código TypeScript real e se beneficiam de versionamento de arquivos, organização de código, testes locais e deploy controlado, hoje só bem resolvidos via **Supabase CLI**.

Passos confirmados, em ordem:

1. Verificação do ambiente (`code --version`, `node --version`, `supabase --version`) — Visual Studio Code e Node.js `23.6.0` já instalados; Supabase CLI ausente.
2. Tentativa de instalação via `winget install Supabase.CLI` — falhou (pacote ausente no repositório do `winget` daquela instalação do Windows, confirmado também por `winget search supabase`, sem resultados); `scoop --version` confirmou que o Scoop também não estava instalado.
3. Decisão final: usar a CLI via `npx supabase` (sem instalação global) — evita problemas de instalação no Windows, sempre usa a versão mais recente, dispensa Scoop/Winget, facilita replicar o ambiente em outra máquina.
4. Pasta raiz local criada e confirmada via `pwd`: `C:\Users\Administrador\Project-Mimikyu`. `npx supabase --version` confirmou a CLI `2.109.1` funcional.
5. `npx supabase init` — **confirmado** (saída real de terminal: "Finished supabase init."), gerando a estrutura padrão `supabase/` (`config.toml`, `functions/`, `migrations/`, `seed.sql`) dentro da pasta local.
6. `npx supabase login` — **confirmado** (saída real: "Finished supabase login."), autenticando a CLI local contra a conta Supabase via navegador.
7. Obtenção do **Project Reference** (Settings → General, no painel do Supabase) — identificador do projeto remoto, necessário para vincular o ambiente local; **não é um segredo** (diferente de Database Password/Service Role Key/Anon Key/Connection String, que foram explicitamente NÃO solicitados nesta etapa, por boa prática de segurança da própria sessão pareada) — o valor real não é repetido nesta documentação por cautela, embora não seja tecnicamente sigiloso.
8. `npx supabase link --project-ref <ref>` — **confirmado** (saída real: "Finished supabase link."). O projeto local agora está oficialmente vinculado ao projeto remoto do Project Mimikyu no Supabase.

**Nova nota arquitetural, registrada nesta revisão**: a partir deste ponto, o projeto passa a ter **dois ambientes de trabalho complementares, não um substituindo o outro**: o **Painel Web do Supabase** (administração, inspeção de dados, Storage, Auth, SQL Editor — onde todo o trabalho de banco de dados já documentado até aqui foi feito) e o **Projeto Local** (Edge Functions, scripts, futuras automações, versionamento via Git). Combinação descrita pela sessão pareada como "exatamente a que equipes profissionais utilizam".

**Nota não resolvida, reafirmada nesta revisão**: a sessão pareada propôs, mais uma vez, uma reorganização do repositório em um único diretório unificado (`docs/`, `database/{roadmap,migrations,seeds}`, `supabase/{functions,config.toml}`, `scripts/`, `README.md`) — **ainda divergente da estrutura real já em uso no repositório GitHub oficial** (`database/schema`, `database/functions` — funções SQL compartilhadas —, `database/migrations`, `database/seeds`, `database/validations`, `database/reference-data`, `database/diagrams`, governadas por `database/README.md`/`STD-001`; `docs/` com sua própria estrutura rica de `adr/`/`standards/`/`architecture/`). Continua não confirmado se `C:\Users\Administrador\Project-Mimikyu` (pasta local, agora vinculada ao projeto remoto Supabase) corresponde a um clone do repositório GitHub `fabriciosouzasales/project-mimikyu` que esta documentação governa. Não resolvido unilateralmente — Fabrício precisa decidir antes que qualquer código de Edge Function seja de fato incorporado ao repositório oficial.

## Sprint B2.1 — Primeira Edge Function (CONFIRMADO CONCLUÍDO)

Passos confirmados, nesta ordem:

1. `npx supabase functions new import-card-assets` — **confirmado** (saída real: "Created new Function at supabase\functions\import-card-assets"), gerando via CLI (nunca escrito manualmente, ver Convenção 1, acima) o esqueleto padrão em `supabase/functions/import-card-assets/index.ts`.
2. Prompt da própria CLI, "Generate VS Code settings for Deno?", respondido `Yes` — **confirmado** (saída real: "Generated VS Code settings in .vscode/settings.json"). Necessário porque Edge Functions do Supabase rodam em **Deno**, não em Node.js; o arquivo só configura autocomplete/IntelliSense/imports no editor, sem alterar o projeto nem o banco.
3. `code .` abriu o projeto local no VS Code — **confirmado**, árvore de arquivos conferida (`.vscode/`, `supabase/.temp/`, `supabase/functions/import-card-assets/index.ts`, `supabase/config.toml`).
4. Conteúdo real do template gerado pela CLI `2.109.1` obtido diretamente do VS Code (colado na conversa, não presumido) — confirmando a descoberta do novo padrão `withSupabase(...)` (ver nota técnica, acima).

**Pausa arquitetural antes de escrever qualquer lógica própria**: para evitar que `index.ts` cresça sem organização (risco explicitamente citado: "em poucos dias teremos centenas de linhas dentro do index.ts"), a estrutura interna de cada Edge Function foi refinada e adotada como padrão — **substitui a estrutura provisória da seção "Arquitetura de Execução", item 14, acima**:

```text
import-card-assets/
├── index.ts          ← ponto de entrada
├── config.ts
├── types.ts
├── services/
│   ├── database.ts
│   ├── storage.ts
│   └── importer.ts
├── sources/
│   ├── source-adapter.ts
│   ├── tcgdex.ts
│   └── pokemon-api.ts
└── utils/
    ├── hash.ts
    ├── image.ts
    └── paths.ts
```

A maioria destes arquivos está **vazia nesta revisão** — a estrutura foi criada como padrão a ser seguido por todas as futuras Edge Functions do projeto (mencionadas como ideia futura, ainda não decidida nem agendada: `sync-card-catalog`, `reprocess-failures`, `cleanup-storage` — backlog, não confundir com trabalho planejado do roteiro).

**Primeira versão real, simplificada a partir do template oficial** (`version: "1.0.0"`), com `auth: ["secret"]` (Convenção 4, acima — a função nunca será chamada pelo navegador, apenas por chamadas administrativas/internas):

```ts
// supabase/functions/import-card-assets/index.ts
import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";

export default {
  fetch: withSupabase(
    { auth: ["secret"] },
    async (_req, _ctx) => {
      return Response.json({
        success: true,
        function: "import-card-assets",
        version: "1.0.0",
        status: "ready",
      });
    }
  ),
};
```

**Confirmado sem erros no VS Code** (verificado via captura real do editor). Este código estabelece as três primeiras convenções listadas acima (responsabilidade única, template oficial da CLI, execução restrita) como padrão para todas as Edge Functions futuras do projeto.

Código anteriormente proposto para a mesma resposta (revisão `0.6`, baseado no padrão `serve()` — **obsoleto**, nunca chegou a ser incorporado a um arquivo real, mantido aqui apenas como registro histórico do planejamento original):

```ts
// (obsoleto — ver nota técnica sobre a mudança de template da CLI, acima)
import { serve } from "https://deno.land/std/http/server.ts";

serve(async () => {
  return new Response(
    JSON.stringify({ success: true, function: "import-card-assets", status: "ready" }),
    { headers: { "Content-Type": "application/json" } }
  );
});
```

## Sprint B2.2 — Deploy e Teste (CONFIRMADO CONCLUÍDO)

**Primeiro deploy real de uma Edge Function no Project Mimikyu.** `npx supabase functions deploy import-card-assets` — **confirmado por saída real de terminal**: `Uploading asset (import-card-assets): supabase/functions/import-card-assets/deno.json` / `...index.ts`, `Deployed Functions on project <ref>: import-card-assets`, link para o Dashboard. O aviso `WARNING: Docker is not running` **não é erro** — a CLI usa automaticamente o deploy via API quando o Docker não está disponível localmente, comportamento documentado e esperado do Supabase.

**Teste real da função publicada, também confirmado**: obtida uma Secret Key do projeto (Settings → API Keys → Secret keys, prefixo `sb_secret_` — **nunca compartilhada na conversa nem repetida nesta documentação**, seguindo a mesma disciplina já aplicada a outras credenciais), salva temporariamente como variável de ambiente de sessão no PowerShell, usada para uma chamada `Invoke-RestMethod` `POST` contra `https://<project-ref>.supabase.co/functions/v1/import-card-assets` com o header `apikey`. **Resultado real confirmado**: `success: True, function: import-card-assets, version: 1.0.0, status: ready`. A variável de ambiente foi removida da sessão (`Remove-Item Env:...`) logo em seguida — boa prática de segurança observada e seguida à risca.

**Critério de aceite do sprint, atingido e confirmado**: "a função responde `status: ready`" — ambiente local, vínculo com o projeto remoto, função criada, código publicado, invocação remota e autenticação com Secret Key todos validados em conjunto. Este é o primeiro marco de infraestrutura de código genuinamente confirmado (não apenas planejado) do Bloco B — a infraestrutura do Pipeline Automático de Imagens está oficialmente iniciada.

## Sprint B2.3 — Integração com Banco (código publicado; primeiro bug real encontrado e corrigido; teste ainda EM ANDAMENTO, não concluído)

**Mudança de interface em relação ao planejamento original**: em vez de identificar a execução por `run_id` (UUID, como planejado nas revisões `0.6`-`0.8`), a função passa a receber `run_code` (ex. `RUN_000000001`) — mesmo identificador amigável já criado propositalmente para isso na Query `220` (ver `05-modelo-de-dados.md`, "Query 220 — Create Asset Import Run": `run_code` gerado por sequência dedicada, pensado desde a origem para logs/suporte/auditoria/telas administrativas). Justificativa: `run_code` é legível, aparece em logs, pode ser informado manualmente por um administrador, e é muito mais fácil de localizar durante suporte do que um UUID; o `id` (UUID) continua existindo internamente como chave real, mas deixa de ser a interface de entrada da função.

Objetivo do sprint: a função apenas recebe `run_code` → consulta `asset_import_run` → retorna os dados encontrados. Nenhuma chamada a API externa, download, upload ou processamento ainda — leitura pura.

**Código real, publicado e confirmado via deploy** (`npx supabase functions deploy import-card-assets`, mesma saída de sucesso do Sprint B2.2, incluindo o aviso esperado sobre o Docker):

```ts
// supabase/functions/import-card-assets/index.ts
import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";

type RequestBody = {
  run_code?: string;
};

export default {
  fetch: withSupabase(
    { auth: ["secret"] },
    async (req, ctx) => {
      if (req.method !== "POST") {
        return Response.json(
          { success: false, error: "METHOD_NOT_ALLOWED" },
          { status: 405, headers: { Allow: "POST" } },
        );
      }

      let body: RequestBody;
      try {
        body = await req.json();
      } catch {
        return Response.json(
          { success: false, error: "INVALID_JSON" },
          { status: 400 },
        );
      }

      const runCode = body.run_code?.trim();

      if (!runCode) {
        return Response.json(
          { success: false, error: "RUN_CODE_REQUIRED" },
          { status: 400 },
        );
      }

      const { data: run, error } = await ctx.supabaseAdmin
        .from("asset_import_run")
        .select("*")
        .eq("run_code", runCode)
        .maybeSingle();

      if (error) {
        console.error("Failed to read asset_import_run:", error);
        return Response.json(
          { success: false, error: "DATABASE_QUERY_FAILED" },
          { status: 500 },
        );
      }

      if (!run) {
        return Response.json(
          { success: false, error: "IMPORT_RUN_NOT_FOUND", run_code: runCode },
          { status: 404 },
        );
      }

      return Response.json({
        success: true,
        function: "import-card-assets",
        version: "1.1.0",
        run,
      });
    },
  ),
};
```

Uso de `ctx.supabaseAdmin` (não `ctx.supabase`) justificado explicitamente: a função é administrativa e precisa acessar a execução independentemente de políticas de RLS — o cliente administrativo fornecido por `withSupabase` usa a chave secreta do projeto.

**Primeira execução de teste real, criada nesta revisão.** Antes de inventar dados, a sessão pareada consultou (somente leitura) a estrutura real de `asset_import_run` (`information_schema.columns` + `pg_constraint`) para confirmar os valores obrigatórios/permitidos, e buscou dinamicamente o primeiro `asset_source`/`card_set`/`language` reais do catálogo (ordenados por `code`) em vez de inventar UUIDs — *"Prefiro que nosso primeiro `asset_import_run` seja um registro 100% válido, usando dados reais do catálogo editorial."* Os valores reais encontrados diferem do que havia sido planejado como exemplo ilustrativo (Asset Source `MANUAL`, não `TCGDEX`; Card Set **`ME0`**, não `ME1`; Language `en`, não `pt-BR`) — puramente pela ordenação alfabética dos códigos reais, não uma escolha deliberada; ajuste explícito registrado para a próxima sprint: buscar a fonte explicitamente por `code = 'TCGDEX'`/`'POKEMON_TCG_API'` em vez de "a primeira encontrada". **Nota importante para o histórico do projeto**: a existência real de `ME0` como `card_set.code` nesta consulta é evidência direta e nova de que a migração `ME0`→`MEP`/`MEE` (pendência já registrada em `05-modelo-de-dados.md`, "Card Set", desde revisões anteriores) **ainda não foi aplicada ao banco físico real** — corrobora, não resolve, esse item em aberto.

`INSERT INTO asset_import_run (...)` executado com sucesso, `RETURNING id, run_code`. **Confirmação real e valiosa**: o `run_code` foi gerado automaticamente pelo trigger da Query `221` exatamente no formato desenhado na Query `220` (`RUN-{YYYYMMDD}-{sequencial}`) — primeira validação em dado real dessa decisão de arquitetura, muito melhor que o padrão estático que havia sido sugerido como exemplo ilustrativo (`RUN-000000001`). Reflexão registrada pela sessão pareada, considerada um marco: *"O banco deixou de ser apenas um repositório de dados e passou a ser um sistema operacional, no sentido de que a Edge Function já consegue interagir com ele. [...] A partir daqui, cada sprint acrescentará comportamento, e não apenas estrutura."*

**Primeira tentativa de invocação — HTTP 500, bug real encontrado e corrigido.** A chamada (`Invoke-RestMethod` com o `run_code` real) retornou erro 500. Investigação via Supabase Dashboard → Edge Functions → Logs (não por tentativa e erro no código) revelou a causa exata: `code: "42501"`, `message: "permission denied for table asset_import_run"`, `hint: "Grant the required privileges to the current role with: GRANT SELECT ON public.asset_import_run TO service_role;"`. **Correção arquitetural importante, confirmada nesta revisão**: `ctx.supabaseAdmin` (fornecido por `withSupabase` no runtime atual das Edge Functions) **não ignora os GRANTs do PostgreSQL** — respeita os privilégios concedidos à role `service_role`, ao contrário do que a seção "Segurança" (item 13 da arquitetura, acima) presumia implicitamente. Corrigido via `GRANT SELECT ON TABLE public.asset_import_run TO service_role;`, confirmado por consulta a `information_schema.role_table_grants` (retornou `service_role | SELECT`, junto de privilégios pré-existentes como `TRUNCATE`/`REFERENCES`/`TRIGGER` — a ausência específica de `SELECT` nesse conjunto, apesar de outros privilégios já presentes, é a causa provável do erro). Nenhum novo deploy foi necessário — o ajuste foi puramente de permissão no banco.

**Nova pendência declarada por Fabrício, ainda não formalizada**: até este ponto o projeto tinha migrations para tabelas/triggers/RLS/validações/seeds, mas nenhuma para GRANTs — decisão registrada de criar um novo grupo de migrations dedicado a conceder as permissões necessárias às Edge Functions (exemplo citado: um número na faixa `99x`, como `998 Grant Edge Functions`), para que nenhum ambiente novo (desenvolvimento/homologação/produção) dependa de ajustes manuais e todos fiquem com exatamente as mesmas permissões. **Não escrita nem executada como migration formal nesta revisão** (o `GRANT` acima foi aplicado ad hoc via SQL Editor) — pendência para `STD-001` (faixa de numeração de Queries) e para uma futura Query real, não resolvida unilateralmente aqui.

**Segunda tentativa — HTTP 404, causada por um erro de digitação real** (`"IRUN-20260719-..."` em vez de `"RUN-20260719-..."`) — comportamento correto: a função não encontrou a execução e respondeu `IMPORT_RUN_NOT_FOUND`, confirmando que esse caminho de erro funciona como projetado.

**Terceira tentativa, após aparente correção do texto — HTTP 404 novamente; causa identificada e resolvida nesta revisão.** Em vez de adivinhar, o corpo real do erro foi extraído diretamente do PowerShell (o `Invoke-RestMethod` esconde o corpo JSON de respostas de erro por padrão; foi necessário um bloco `try/catch` lendo `$_.Exception.Response`). Uma consulta de diagnóstico comparando `run_code`, `length(run_code)` e um booleano `exact_match` revelou a causa exata: **o `run_code` armazenado no banco tem 21 caracteres; o valor que estava sendo enviado na chamada tinha 22** — um dígito `0` a mais na sequência final, introduzido ao retranscrever manualmente o valor em uma chamada anterior. Corrigido o valor enviado (removendo o dígito extra, restaurando o formato de 8 dígitos sequenciais desenhado na Query `220`) e repetida a mesma chamada: **sucesso confirmado** — resposta completa com `run` preenchido corretamente.

**Sprint B2.3 — CONFIRMADO CONCLUÍDO.** *"Acabamos de concluir a primeira integração completa entre uma Edge Function e o nosso banco de dados. Esse momento é tão importante quanto foi a criação da primeira migration."* Confirmado: autenticação funcionando; função publicada; `ctx.supabaseAdmin` funcionando (respeitando GRANTs, como corrigido acima); consulta ao PostgreSQL funcionando; `run_code` validado como uma interface pública sólida para o pipeline.

**Nova convenção de documentação, formalizada nesta revisão: o "Diário Técnico".** Fabrício propôs, e a partir desta revisão passa a ser o padrão oficial para cada sprint deste roteiro: ao final de cada sprint, registrar quatro itens — **Objetivo**, **Critério de Aceite**, **Resultado**, **Pendências Descobertas**. *"Será um diário técnico do Project Mimikyu. Em um projeto que vai durar meses e terá dezenas de migrations e Edge Functions, esse histórico vai facilitar muito retomadas, auditorias e futuras evoluções."* Aplicado retroativamente a este sprint:

> **Diário Técnico — Sprint B2.3 — Consulta de Execução**
> **Objetivo**: permitir que a Edge Function `import-card-assets` receba um `run_code` e localize a execução correspondente em `asset_import_run`.
> **Critério de aceite**: a função deve retornar com sucesso o registro correspondente ao `run_code` informado.
> **Resultado**: ✅ Concluído. A Edge Function recebe requisições autenticadas, valida o payload, consulta `asset_import_run` e retorna a execução corretamente.
> **Pendências descobertas**: (1) falta uma migration dedicada aos `GRANT`s necessários às Edge Functions — sugestão registrada: `999 - Grant Edge Functions` (refinamento do número citado na revisão `0.10`, que mencionava `998` apenas como exemplo ilustrativo; **nenhuma das duas foi escrita como migration formal ainda**); (2) padronizar a execução de testes (ideia registrada para o futuro: coleção Postman/Insomnia/Bruno, evitando comandos longos no PowerShell); (3) documentar oficialmente que a interface pública do pipeline usa `run_code`, não UUID — feito nesta própria seção.

## Sprint B2.4 — Descoberta das Cartas (CONFIRMADO CONCLUÍDO)

**Mudança de escopo em relação ao planejamento original, decidida antes de escrever qualquer código**: em vez de uma sprint isolada apenas para ler `card_set` (como estava no roteiro anterior), o escopo foi ampliado para já incluir a listagem das cartas da execução — *"Essa mudança elimina uma sprint inteira, porque a leitura do `card_set` sozinha tem pouco valor prático. O objetivo real da função é descobrir quais cartas precisam ser processadas."* Fluxo final: `run_code` → `asset_import_run` → `card_set` → listar `card` (ordenadas por `collector_order`) — ainda sem nenhum download de imagem.

**Refatoração estrutural proposta, mas não aplicada de fato nesta revisão** — registrado por transparência: antes de adicionar a consulta de cartas, foi proposta uma reorganização (`index.ts` como ponto de entrada + `services/database.ts` + `types.ts` + `config.ts`), para evitar que toda a lógica continuasse crescendo dentro de um único arquivo — *"Essa será a única refatoração estrutural antes de começarmos a integrar com a API externa."* Fabrício aprovou ("Siga."), mas o código efetivamente publicado e confirmado nesta revisão (abaixo, verbatim) **permanece em um único `index.ts`**, sem a separação em módulos proposta — a refatoração não chegou a ser aplicada nesta revisão, apesar da intenção declarada. Fica como pendência real, não uma decisão revertida.

Antes de alterar o código, a estrutura real de `card_set`/`card` foi confirmada por leitura (`information_schema.columns` + `pg_constraint`, mesmo padrão de cautela já usado no Sprint B2.3) — confirmando `card.card_set_id → card_set.id` e os campos de ordenação `collector_number`/`collector_order`. `GRANT SELECT ON TABLE public.card_set, public.card TO service_role;` aplicado ad hoc (mesma pendência de migration formal registrada no Sprint B2.3).

**Código real, publicado e confirmado via deploy** (`npx supabase functions deploy import-card-assets`, mesma saída de sucesso já vista nos sprints anteriores):

```ts
// supabase/functions/import-card-assets/index.ts
import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";

type RequestBody = {
  run_code?: string;
};

export default {
  fetch: withSupabase(
    { auth: ["secret"] },
    async (req, ctx) => {
      if (req.method !== "POST") {
        return Response.json(
          { success: false, error: "METHOD_NOT_ALLOWED" },
          { status: 405, headers: { Allow: "POST" } },
        );
      }

      let body: RequestBody;
      try {
        body = await req.json();
      } catch {
        return Response.json(
          { success: false, error: "INVALID_JSON" },
          { status: 400 },
        );
      }

      const runCode = body.run_code?.trim();

      if (!runCode) {
        return Response.json(
          { success: false, error: "RUN_CODE_REQUIRED" },
          { status: 400 },
        );
      }

      const { data: run, error: runError } = await ctx.supabaseAdmin
        .from("asset_import_run")
        .select("*")
        .eq("run_code", runCode)
        .maybeSingle();

      if (runError) {
        console.error("Failed to read asset_import_run:", runError);
        return Response.json(
          { success: false, error: "IMPORT_RUN_QUERY_FAILED" },
          { status: 500 },
        );
      }

      if (!run) {
        return Response.json(
          { success: false, error: "IMPORT_RUN_NOT_FOUND", run_code: runCode },
          { status: 404 },
        );
      }

      const { data: cardSet, error: cardSetError } = await ctx.supabaseAdmin
        .from("card_set")
        .select(`
          id, expansion_id, code, name, set_type,
          release_order, release_date, base_set_size, total_set_size
        `)
        .eq("id", run.card_set_id)
        .maybeSingle();

      if (cardSetError) {
        console.error("Failed to read card_set:", cardSetError);
        return Response.json(
          { success: false, error: "CARD_SET_QUERY_FAILED" },
          { status: 500 },
        );
      }

      if (!cardSet) {
        return Response.json(
          { success: false, error: "CARD_SET_NOT_FOUND", card_set_id: run.card_set_id },
          { status: 404 },
        );
      }

      const { data: cards, error: cardsError } = await ctx.supabaseAdmin
        .from("card")
        .select(`
          id, card_set_id, rarity_id, category_id,
          collector_number, collector_total, collector_order, name
        `)
        .eq("card_set_id", run.card_set_id)
        .order("collector_order", { ascending: true });

      if (cardsError) {
        console.error("Failed to read cards:", cardsError);
        return Response.json(
          { success: false, error: "CARDS_QUERY_FAILED" },
          { status: 500 },
        );
      }

      return Response.json({
        success: true,
        function: "import-card-assets",
        version: "1.2.0",
        run,
        card_set: cardSet,
        card_count: cards.length,
        cards,
      });
    },
  ),
};
```

**Teste real, confirmado com sucesso**, usando o mesmo `run_code` do Sprint B2.3: retornou `success: true`, `version: "1.2.0"`, `card_set` real (`code: "ME0"`, `name: "Black Star Promos"`, `set_type: "PROMO"`, `release_date: "2020-05-20"`, `base_set_size: 88` — dados reais do catálogo, primeira vez que `card_set` é lido por uma Edge Function) e **`card_count: 0`**. Explicitamente confirmado que isso **não é um erro**: o `card_set` `ME0` usado no teste ainda não possui nenhuma carta cadastrada em `card` — a função percorreu corretamente todo o fluxo (`run_code` → `asset_import_run` → `card_set` → `card` → 0 cartas encontradas) sem falhar.

> **Diário Técnico — Sprint B2.4 — Descoberta das Cartas**
> **Objetivo**: permitir que a Edge Function descubra quais cartas pertencem ao `card_set` da execução.
> **Critério de aceite**: receber execução, `card_set` e lista de cartas.
> **Resultado**: ✅ Concluído. A função agora retorna execução, `card_set`, quantidade de cartas e lista ordenada.
> **Pendências descobertas**: nenhuma — comportamento exatamente o esperado.

## Sprint B2.4.1 — Refatoração para Services (CONFIRMADO CONCLUÍDO)

**Mudança arquitetural proposta por Fabrício antes da primeira integração externa**: até o Sprint B2.4, `index.ts` consultava as tabelas diretamente; a partir de agora, a lógica de acesso a dados passa a viver em módulos de serviço próprios (`Database Service`, e futuramente `TCGDEX Service`/`Storage Service`), com `index.ts` apenas orquestrando. Justificativa explícita: *"Essa separação vai nos permitir, por exemplo, trocar a TCGDEX pela Pokémon TCG API sem alterar o fluxo principal da função. É uma refatoração pequena, feita no momento certo, antes que a função cresça demais."* Esta sprint resolve, para os dois arquivos abaixo, a pendência já registrada no Sprint B2.4 ("refatoração proposta, mas não aplicada de fato").

**Nova disciplina de trabalho para código, declarada nesta revisão, espelhando a disciplina já usada para SQL**: até aqui, a sessão pareada vinha descrevendo a estrutura de arquivos e deixando Fabrício montá-la manualmente; ele próprio notou a mudança de ritmo e perguntou *"Fiquei na dúvida de como criar essa nova estrutura... Seria direto no Visual Code?"* — a partir daqui, o processo passa a ser guiado arquivo por arquivo, no mesmo espírito do ciclo `Migration → Executar → Validar` já usado no banco: **criar pasta/arquivo → validar a estrutura → escrever o código → testar**, um passo de cada vez, para reduzir erros. Passos confirmados, em ordem: criação da pasta `services/` dentro de `import-card-assets/` (botão direito → New Folder); criação de `services/database.ts` (arquivo vazio, depois preenchido); criação de `types.ts` na raiz de `import-card-assets/`; preenchimento de `types.ts`, validado sem erros no VS Code antes de prosseguir; preenchimento de `services/database.ts`, validado sem erros antes de prosseguir; substituição completa de `index.ts` pelo novo conteúdo.

Estrutura final confirmada, dentro de `supabase/functions/import-card-assets/`:

```text
import-card-assets/
├── services/
│   └── database.ts
├── deno.json
├── index.ts
└── types.ts
```

**`types.ts`** — tipos extraídos do `index.ts` monolítico:

```ts
// supabase/functions/import-card-assets/types.ts
export type RequestBody = {
  run_code?: string;
};

export type ImportRun = {
  id: string;
  run_code: string;
  asset_source_id: string;
  card_set_id: string;
  language_id: string;
  run_type: string;
  status: string;
};

export type CardSet = {
  id: string;
  expansion_id: string;
  code: string;
  name: string;
  set_type: string;
  release_order: number;
  release_date: string | null;
  base_set_size: number;
  total_set_size: number;
};

export type Card = {
  id: string;
  card_set_id: string;
  rarity_id: string;
  category_id: string;
  collector_number: string;
  collector_total: number | null;
  collector_order: number;
  name: string;
};
```

**`services/database.ts`** — as três consultas que antes viviam dentro do handler (`findImportRun`, `findCardSet`, `listCards`), extraídas para funções próprias que recebem o `SupabaseClient` (`ctx.supabaseAdmin`) como parâmetro; mesmo comportamento do v1.2.0, agora lançando exceções (`IMPORT_RUN_QUERY_FAILED`/`CARD_SET_QUERY_FAILED`/`CARDS_QUERY_FAILED`) em vez de retornar `{data, error}` diretamente ao handler:

```ts
// supabase/functions/import-card-assets/services/database.ts
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Card, CardSet, ImportRun } from "../types.ts";

export async function findImportRun(
  supabase: SupabaseClient,
  runCode: string,
): Promise<ImportRun | null> {
  const { data, error } = await supabase
    .from("asset_import_run")
    .select("*")
    .eq("run_code", runCode)
    .maybeSingle();

  if (error) {
    console.error("Failed to read asset_import_run:", error);
    throw new Error("IMPORT_RUN_QUERY_FAILED");
  }

  return data as ImportRun | null;
}

export async function findCardSet(
  supabase: SupabaseClient,
  cardSetId: string,
): Promise<CardSet | null> {
  const { data, error } = await supabase
    .from("card_set")
    .select(`
      id,
      expansion_id,
      code,
      name,
      set_type,
      release_order,
      release_date,
      base_set_size,
      total_set_size
    `)
    .eq("id", cardSetId)
    .maybeSingle();

  if (error) {
    console.error("Failed to read card_set:", error);
    throw new Error("CARD_SET_QUERY_FAILED");
  }

  return data as CardSet | null;
}

export async function listCards(
  supabase: SupabaseClient,
  cardSetId: string,
): Promise<Card[]> {
  const { data, error } = await supabase
    .from("card")
    .select(`
      id,
      card_set_id,
      rarity_id,
      category_id,
      collector_number,
      collector_total,
      collector_order,
      name
    `)
    .eq("card_set_id", cardSetId)
    .order("collector_order", { ascending: true });

  if (error) {
    console.error("Failed to read cards:", error);
    throw new Error("CARDS_QUERY_FAILED");
  }

  return (data ?? []) as Card[];
}
```

**`index.ts` (v1.2.1)** — passa a importar `findImportRun`/`findCardSet`/`listCards` de `./services/database.ts` e `RequestBody` de `./types.ts`; o corpo do handler agora envolve a sequência de consultas em um único `try/catch` (os erros lançados pelo Database Service viram a mensagem de erro da resposta 500), e a resposta de `CARD_SET_NOT_FOUND` deixou de incluir o campo `card_set_id` (simplificação observada nesta versão em relação ao v1.2.0, não uma regressão relevante — a informação já está implícita no `run` retornado em caso de sucesso):

```ts
// supabase/functions/import-card-assets/index.ts
import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";
import {
  findImportRun,
  findCardSet,
  listCards,
} from "./services/database.ts";
import type { RequestBody } from "./types.ts";

export default {
  fetch: withSupabase(
    { auth: ["secret"] },
    async (req, ctx) => {
      if (req.method !== "POST") {
        return Response.json(
          { success: false, error: "METHOD_NOT_ALLOWED" },
          { status: 405, headers: { Allow: "POST" } },
        );
      }

      let body: RequestBody;
      try {
        body = await req.json();
      } catch {
        return Response.json(
          { success: false, error: "INVALID_JSON" },
          { status: 400 },
        );
      }

      const runCode = body.run_code?.trim();

      if (!runCode) {
        return Response.json(
          { success: false, error: "RUN_CODE_REQUIRED" },
          { status: 400 },
        );
      }

      try {
        const run = await findImportRun(ctx.supabaseAdmin, runCode);

        if (!run) {
          return Response.json(
            { success: false, error: "IMPORT_RUN_NOT_FOUND", run_code: runCode },
            { status: 404 },
          );
        }

        const cardSet = await findCardSet(ctx.supabaseAdmin, run.card_set_id);

        if (!cardSet) {
          return Response.json(
            { success: false, error: "CARD_SET_NOT_FOUND" },
            { status: 404 },
          );
        }

        const cards = await listCards(ctx.supabaseAdmin, run.card_set_id);

        return Response.json({
          success: true,
          function: "import-card-assets",
          version: "1.2.1",
          run,
          card_set: cardSet,
          card_count: cards.length,
          cards,
        });
      } catch (error) {
        const errorCode = error instanceof Error ? error.message : "UNEXPECTED_ERROR";
        return Response.json(
          { success: false, error: errorCode },
          { status: 500 },
        );
      }
    },
  ),
};
```

**Deploy e teste, confirmados nesta revisão** — `npx supabase functions deploy import-card-assets` seguido de `Invoke-RestMethod` com o mesmo `run_code` (`RUN-20260719-00000001`) do Sprint B2.4: resultado real `success: True`, `version: "1.2.1"`, `run`/`card_set` idênticos ao teste anterior (`card_set` `ME0`/"Black Star Promos"), confirmando que o comportamento observável da função **não mudou** — apenas a organização interna. Código copiado para o repositório oficial (`supabase/functions/import-card-assets/index.ts`, `types.ts`, `services/database.ts`).

**Novo princípio de arquitetura, declarado nesta revisão para todas as Edge Functions futuras**: a partir de agora, `index.ts` tem uma única responsabilidade — **orquestrar o fluxo da função**. Ele não conhece SQL, não conhece PostgreSQL, não conhece TCGdex — apenas coordena chamadas a serviços especializados. *"Essa separação é exatamente o que permitirá que, nas próximas sprints, adicionemos novos serviços (`tcgdex.ts`, `storage.ts`, `image.ts`) sem transformar o `index.ts` em um arquivo de centenas de linhas."* Este princípio se soma às cinco convenções permanentes já declaradas no Sprint B2.1/B2.2 (ver "Roteiro de Implementação Incremental — Bloco B", acima).

> **Diário Técnico — Sprint B2.4.1 — Refatoração para Services**
> **Objetivo**: separar a lógica de negócio (acesso a `asset_import_run`/`card_set`/`card`) da lógica de infraestrutura em `index.ts`, sem alterar o comportamento observável da função.
> **Critério de aceite**: após o deploy, a função deve continuar retornando exatamente o mesmo resultado da v1.2.0 (`run`, `card_set`, `card_count`, `cards`), agora como `version: "1.2.1"`.
> **Resultado**: ✅ Concluído. Deploy e reteste confirmados — mesmo resultado, arquitetura em camadas (`index.ts` orquestrador + `services/database.ts` + `types.ts`).
> **Pendências descobertas**: nenhuma.

## Sprint B2.5 — Integração com TCGdex (dividida em B2.5A e B2.5B, EM ANDAMENTO)

*"Estamos chegando na parte mais interessante. Até agora tudo aconteceu dentro do nosso banco. Agora vamos sair dele pela primeira vez."* Fluxo originalmente planejado: `run` → `card_set` → `cards` → **TCGdex** (consultar diretamente por carta). Esta é a primeira sprint que efetivamente inicia o "Pipeline Automático de Imagens" propriamente dito (busca em fonte externa). O escopo foi dividido em duas sprints mais granulares (`B2.5A`/`B2.5B`, ver abaixo), para isolar a comunicação externa do processamento da imagem.

**Mudança de plano, decidida antes de escrever qualquer chamada real à TCGdex**: em vez de começar pelas cartas, a sprint passa a começar pelo `Card Set` — *"Antes de procurar uma carta precisamos descobrir como a TCGdex identifica aquele conjunto."* Nosso banco conhece o Set como `ME0`; a TCGdex tem seus próprios identificadores, então a primeira pergunta real é "qual é o Card Set correspondente ao nosso `ME0`?" — só depois disso faz sentido procurar cartas. Fluxo revisado: `ME0` → `TCGdex` → `JSON do Set` → `Validar correspondência` → `Fim`, ainda **sem download, sem imagem, sem Storage, sem banco** — apenas comunicação.

**Descoberta arquitetural real, feita durante o planejamento desta sprint**: `card_external_reference` já resolve esse mapeamento para *cartas*, mas nenhuma tabela resolvia o mesmo mapeamento para *Sets* — improvisar isso dentro da Edge Function (ex. um `findTcgDexSet("en", "swsh3")` isolado) quebraria o princípio seguido desde o início do projeto de que tudo que vem de sistemas externos deve ser persistido e rastreável, não resolvido ad hoc no código. Fabrício decidiu investir uma sprint extra no modelo de dados antes de prosseguir — resultado: nova entidade `card_set_external_reference`, documentada em `05-modelo-de-dados.md` (não duplicada aqui, ver seção "Card Set External Reference" naquele documento). Fluxo final da integração, uma vez que essa camada estiver completa: `asset_import_run` → `card_set` → `card_set_external_reference` → `TCGdex`.

**B2.5A — apenas consultar a API, EM ANDAMENTO.** Fluxo: `Edge Function` → `TCGdex` → `JSON de um Set`. A API REST oficial consulta um Set pelo endpoint `https://api.tcgdex.net/v2/{idioma}/sets/{set_id}` (a própria documentação da TCGdex usa `swsh3` como exemplo de identificador de Set). Nesta etapa, **a Edge Function não tentará relacionar automaticamente `ME0` com a TCGdex** — o identificador interno do nosso `card_set` não é necessariamente o mesmo identificador externo; essa correspondência é exatamente o que `card_set_external_reference` vai resolver.

Primeiro arquivo real criado: `supabase/functions/import-card-assets/services/tcgdex.ts`, com uma função `findTcgDexSet(languageCode, externalSetId)` que monta a URL, faz o `fetch` com `Accept: application/json`, trata `404` retornando `null` (Set não encontrado, não é um erro), lança `TCGDEX_REQUEST_FAILED` para outras respostas não-`ok`, e retorna o JSON tipado como `TcgDexSet` (`id`, `name`, `logo?`, `symbol?`, `cardCount?: { total, official }`). **Confirmado sem erros no VS Code** (sem sublinhados vermelhos) — mesma disciplina de validação arquivo por arquivo adotada no Sprint B2.4.1.

**Episódio real, que motivou a Query `241` e uma correção de dado — ver `05-modelo-de-dados.md`, seção "Card Set External Reference", para o detalhamento completo**: ao validar a nova tabela, um mapeamento de teste (`ME0`→`sv10pt5`) foi inserido e depois identificado como incorreto (`sv10pt5` é um Set oficial real da TCGdex, não o `ME0` do Project Mimikyu) e removido. Isso levou a uma decisão importante para esta sprint: a Seed `910` (que popularia `card_set_external_reference`) fica **adiada**, não escrita manualmente — os `external_set_id` reais serão descobertos consultando a própria TCGdex, nunca presumidos.

**Escopo final de B2.5A, definido nesta revisão**: a Edge Function deve (1) receber `run_code`; (2) localizar `asset_import_run`; (3) localizar `card_set`; (4) procurar `card_set_external_reference` correspondente; (5) se existir, consultar a TCGdex; (6) retornar o JSON do Set. Sem download, sem Storage, sem gravação no banco — apenas validar a comunicação de ponta a ponta. Quando não existir mapeamento, a função deve responder `{ success: false, error: "NO_EXTERNAL_SET_MAPPING" }` — comportamento genérico, sem tratamento especial para `ME0` ou qualquer outro Set específico (a regra vale igualmente para qualquer `card_set` sem referência externa ativa).

**Nova diretriz de metodologia, declarada explicitamente nesta revisão**: *"A partir de agora, não criaremos mais tabelas, a menos que seja absolutamente necessário [...] Agora sim vamos voltar ao que realmente gera valor: o Pipeline Automático de Imagens."* Reconhecimento direto de Fabrício de que o projeto passou "algumas horas sem avanços relevantes" enquanto a modelagem de `card_set_external_reference` era resolvida — considerada madura o suficiente para o foco voltar a código/execução real.

**Nova diretriz de metodologia (segunda desta sprint): a partir daqui, cada sprint deve entregar uma capacidade real do pipeline, não apenas infraestrutura.** *"Até agora as Edge Functions serviram para validar infraestrutura. Da próxima etapa em diante, praticamente cada sprint adicionará uma capacidade nova ao pipeline."* Prévia anunciada (não promovida ao "Roteiro vigente" oficial, mesma cautela já aplicada a prévias anteriores — ver "Nota sobre `B2.5B`/`B2.6`", acima): `B2.5` consulta real à TCGdex → `B2.6` localizar todas as cartas do Set → `B2.7` baixar a primeira imagem → `B2.8` enviar ao Supabase Storage → `B2.9` criar o primeiro `card_asset`.

**Código real escrito nesta revisão, ainda NÃO deployado nem testado**:

- `services/database.ts` ganhou `findCardSetExternalReference(supabase, cardSetId, assetSourceId)` — consulta `card_set_external_reference` por `card_set_id`+`asset_source_id`+`is_active = true`, lança `CARD_SET_EXTERNAL_REFERENCE_QUERY_FAILED` em caso de erro.
- `services/tcgdex.ts` foi **reescrito por completo**, substituindo o `findTcgDexSet` da revisão anterior por uma função mais simples, `getSet(language, externalSetId)`: monta a mesma URL (`GET https://api.tcgdex.net/v2/{language}/sets/{externalSetId}`), mas **não trata mais `404` como um caso especial** — qualquer resposta não-`ok` (incluindo `404`) agora lança `TCGDEX_HTTP_{status}`. **Mudança de comportamento real em relação à revisão anterior, registrada por transparência**: a versão de B2.5A tratava "Set não encontrado" como um retorno `null` recuperável; esta versão trata como erro. A ausência de mapeamento continua sendo tratada separadamente, antes de chamar a TCGdex (ver abaixo) — então essa mudança não quebra o fluxo, mas é uma simplificação real do serviço que vale registrar.
- `index.ts` recebeu um rascunho de v1.3.0 (ainda não confirmado): depois de localizar `card_set`, busca `card_set_external_reference` via `findCardSetExternalReference`; se não encontrar, responde `404` com `{ success: false, error: "NO_EXTERNAL_SET_MAPPING" }`; se encontrar, chama `getSet("en", setReference.external_set_id)` e inclui o resultado como `tcgdex_set` na resposta final, ao lado de `run`/`card_set`/`card_count`/`cards`.

Instrução de deploy fornecida (`npx supabase functions deploy import-card-assets`), com uma ressalva explícita: **não invocar a função ainda** — como o mapeamento de teste (`ME0`→`sv10pt5`) foi removido na revisão anterior, `card_set_external_reference` está vazia, e o retorno esperado seria exatamente `NO_EXTERNAL_SET_MAPPING`, o comportamento que se quer validar antes de popular a tabela. **Nenhuma confirmação de deploy ou de teste real foi recebida nesta revisão** — a conversa pivotou antes disso (ver abaixo). Seguindo o princípio de "copiar ao repositório apenas após confirmação", **nenhum destes três arquivos foi copiado para o repositório ainda**.

**Terceira diretriz de metodologia desta sprint: ciclos mais curtos.** *"Até agora implementávamos a infraestrutura inteira e só depois testávamos. Daqui em diante seguiremos um ciclo mais curto: adicionar uma pequena capacidade → fazer deploy → validar → avançar."*

**Pivô real: "o gargalo agora não é código, é dados."** Antes de qualquer deploy, ficou claro que a Edge Function nunca conseguirá consultar a TCGdex sem os `external_set_id` reais — que ainda não são conhecidos para nenhum dos Sets `ME0`-`ME5`. Pesquisa confirmou que a TCGdex expõe todos os conjuntos via `GET /v2/{language}/sets`, que a série **Mega Evolution já está cadastrada na base da TCGdex** (com suporte específico adicionado recentemente, segundo o repositório oficial da TCGdex no GitHub), mas que a API não publica uma tabela de consulta pronta com os IDs internos — eles precisam ser obtidos diretamente da API. **Nomes oficiais em inglês, aprendidos nesta revisão** (novo dado de domínio, não confirmado ainda contra `card_set.name`): `ME1` = "Mega Evolution", `ME2` = "Phantasmal Flames", `ME2.5` = "Ascended Heroes", `ME3` = "Perfect Order", `ME4` = "Chaos Rising", `ME5` = "Pitch Black". **Nota de cautela**: `ME5` aparece pela primeira vez nesta revisão — as revisões anteriores desta documentação sempre trataram `ME1`-`ME4` (+ `ME0` promocional) como o conjunto de Sets efetivamente carregado no banco; não há, nesta revisão, confirmação de que `ME5` já existe como `card_set` real — tratar como informação de planejamento até ser verificado.

**Como descobrir os IDs reais — três propostas sucessivas nesta mesma revisão, registradas por transparência (a decisão final é a terceira; as duas primeiras foram consideradas e abandonadas antes de qualquer código ser escrito para elas)**:

1. *Descartada*: preencher manualmente uma tabela `Nosso código → TCGdex ID`, consultando a API ou o site da TCGdex à mão.
2. *Descartada*: criar uma nova Edge Function `sync-card-sets`, dedicada a consultar a TCGdex, listar os Sets da série Mega Evolution e gerar os `INSERT`s. Chegou a ser aprovada ("Siga.") antes de ser reconsiderada na mesma revisão: *"Depois de revisar toda a arquitetura, minha recomendação é não criar uma Edge Function para descobrir os IDs dos sets. Isso adicionaria um componente que será usado pouquíssimas vezes."*
3. **Decisão final**: um **script administrativo standalone**, fora da Edge Function — `scripts/discover-tcgdex-sets.ts`, rodado via Deno CLI (`deno run --allow-net`), não parte do runtime de produção do `import-card-assets`. Consulta `https://api.tcgdex.net/v2/en/sets`, filtra localmente por nomes que contêm `mega`/`phantasmal`/`ascended`/`perfect`/`chaos`/`pitch`, e imprime uma tabela (`console.table`) com `id`/`name`/`serie`/`releaseDate`. Justificativa: mantém `import-card-assets` dedicada exclusivamente ao pipeline de importação; a descoberta de IDs é uma tarefa administrativa rara, melhor resolvida fora do runtime da função.

**Status real do script, nesta revisão**: código escrito e colado no VS Code, mas **criado no local errado** (`supabase/functions/import-card-assets/scripts/discover-tcgdex-sets.ts`, dentro da própria Edge Function) — recomendação, ainda não confirmada como aplicada, de mover para a raiz do projeto (`scripts/discover-tcgdex-sets.ts`, fora de `supabase/`), com instruções de como navegar o terminal do VS Code até a raiz e rodar `deno run --allow-net scripts/discover-tcgdex-sets.ts`. **Nenhuma execução real do script foi confirmada nesta revisão** — termina com a instrução de como rodá-lo, não com um resultado.

**Reframing informal do roteiro em "Blocos funcionais", anunciado nesta revisão — prévia, não promovida ao "Roteiro vigente" oficial**: Bloco 1 — Integração completa com TCGdex (em andamento); Bloco 2 — Download da imagem; Bloco 3 — Upload no Supabase Storage; Bloco 4 — Criação do `card_asset`; Bloco 5 — Query `880` (carga automática). Descrito como uma mudança de "micro-sprints" para "blocos funcionais", cada um entregue de ponta a ponta. Assim como a prévia `B2.5`-`B2.9` acima, esta reorganização não substitui a tabela "Roteiro vigente" desta revisão — mantendo a mesma cautela contra sobrescrever o roteiro consolidado sem uma comparação explícita, já aplicada desde o incidente de confiança da revisão `0.49` de `05-modelo-de-dados.md`.

**B2.5B — a partir da consulta validada (ainda não iniciada).** Fluxo: `JSON` → `Extrair URL da imagem` → `Download` → `Validar imagem`. Descrito como uma redução de complexidade em relação a tentar fazer tudo em uma única sprint. **Ver a nota sobre possível sobreposição com `B2.6` (Download) na seção "Roteiro vigente", acima — não resolvida unilateralmente.**

**Ambiente corrigido — Deno CLI de fato instalado, confirmado por saída real de terminal.** Ao tentar rodar `scripts/discover-tcgdex-sets.ts`, `deno --version` falhou (`CommandNotFoundException`) — a extensão Deno do VS Code (instalada desde o Sprint B2.1) oferece apenas suporte ao editor, **não instala o executável**. Corrigido via `winget install DenoLand.Deno`, confirmado por saída real de terminal (download/hash/extração do pacote, aviso de PATH modificado exigindo reinício do shell). Após reabrir o VS Code, `deno --version` confirmou `deno 2.9.3 (stable) / v8 14.9.207.2-rusty / typescript 6.0.3`. **Localização do script também confirmada corrigida nesta revisão**: rodado com sucesso a partir da raiz do projeto (`C:\Users\Administrador\Project-Mimikyu`) via `deno run --allow-net scripts/discover-tcgdex-sets.ts` — resolve a pendência de local incorreto sinalizada na revisão anterior.

**Marco: primeira comunicação real e bem-sucedida com uma fonte externa em todo o Bloco B.** Antes de rodar, o script foi melhorado — em vez de filtrar por palavras-chave fixas (`"mega"`/`"chaos"`/etc.), passou a listar todos os Sets retornados pela TCGdex e filtrar com base na resposta real da API, tornando-o resiliente a mudanças de nomenclatura da própria TCGdex (código exato desta versão melhorada não foi colado nesta revisão — pendente antes de copiar o script ao repositório). Execução real confirmada, com tabela de resultado real impressa no terminal. **`external_set_id` reais da TCGdex, descobertos nesta revisão**:

| Nosso código | TCGdex ID | Nome oficial na TCGdex |
|---|---|---|
| `ME0` | `mee` | Mega Evolution Energy |
| `ME1` | `me01` | Mega Evolution |
| `ME2` | `me02` | Phantasmal Flames |
| `ME2.5` | `me02.5` | Ascended Heroes |
| `ME3` | `me03` | Perfect Order |
| `ME4` | `me04` | Chaos Rising |
| `ME5` (não confirmado como `card_set` real) | `me05` | Pitch Black |

**Decisão de negócio real, aberta e NÃO resolvida unilateralmente — cross-referenciada com a pendência "escopo `ENERGY`" já registrada em ciclos muito anteriores deste projeto.** O nome oficial de `mee` é "**Mega Evolution Energy**", não "Mega Evolution" — sugerindo que é um Set de **Energias**, não o conjunto geral de promocionais que `ME0` representa internamente no Project Mimikyu. Duas opções levantadas, nenhuma decidida: **Opção A (recomendada pela sessão pareada)** — manter `ME0` como uma coleção 100% interna, sem vínculo com a TCGdex, preservando a correção já feita na revisão anterior (`ME0` não é `sv10pt5`, e agora também não seria automaticamente `mee`); vantagem: não mistura uma coleção interna com um Set oficial potencialmente diferente. **Opção B** — mapear `ME0`→`mee` **somente se** todas as cartas da coleção `ME0` forem exatamente as cartas do Set oficial "Mega Evolution Energy" — decisão que depende do conteúdo real da coleção, não da tecnologia, e portanto cabe a Fabrício, não a esta documentação.

**Correção arquitetural real, feita ao final desta revisão, ainda sem código novo entregue**: depois de ver a resposta real da TCGdex, ficou claro que `card_set_external_reference` está modelada corretamente, mas deve funcionar como uma **tabela de configuração** (resolvida uma vez por Set), não como algo recalculado a cada execução. Fluxo corrigido: `asset_import_run` → `card_set` → `card_set_external_reference` → `external_set_id` → `TCGdex` → **lista de cartas do Set** → para cada carta → `card_external_reference` → `card_asset`. Mudança de ênfase importante: *"O primeiro objetivo da Edge Function não é importar imagens. O primeiro objetivo é importar o catálogo oficial das cartas. Essa diferença muda completamente o pipeline."* — ou seja, antes de qualquer download de imagem, o pipeline deve primeiro sincronizar a lista completa de cartas de um Set (populando `card_external_reference` para cada uma), e só depois avançar para download/Storage/`card_asset`. **Os três arquivos completos prometidos para esta etapa (`database.ts`, `tcgdex.ts`, `index.ts` v1.3.0) não foram entregues até o fim desta revisão** — ficam pendentes para a próxima.

**Proposta declarada, ainda não executada, sobre o próprio script de descoberta**: por ser uma ferramenta temporária, a intenção declarada é (1) usar `scripts/discover-tcgdex-sets.ts` uma única vez para descobrir os IDs oficiais; (2) gerar a Seed `910` definitiva a partir deles; (3) remover o script do repositório — mantendo o projeto enxuto, sem utilitários descartáveis acumulados. Nenhum desses três passos foi executado nesta revisão — a Seed `910` continua bloqueada pela decisão de negócio sobre `ME0` (acima).

> **Diário Técnico — Sprint B2.5A — Primeira Comunicação com a TCGdex (parcial)**
> **Objetivo**: descobrir os `external_set_id` reais da TCGdex para os Sets do Project Mimikyu, como pré-requisito para popular `card_set_external_reference` e finalmente integrar a Edge Function.
> **Critério de aceite**: script de descoberta executado com sucesso, retornando os `external_set_id` reais.
> **Resultado**: ✅ Concluído (a descoberta em si). Primeira comunicação externa real e bem-sucedida do Bloco B — `external_set_id` de `ME0`-`ME5` obtidos da própria TCGdex, não mais presumidos. A integração da Edge Function propriamente dita (`database.ts`/`tcgdex.ts`/`index.ts` v1.3.0 completos, deploy, teste real) **permanece pendente**.
> **Pendências descobertas**: (1) decisão de negócio em aberto sobre se `ME0` deve ou não ser mapeado a `mee`/"Mega Evolution Energy" — cross-referenciada com a pendência "escopo `ENERGY`" já registrada em ciclos anteriores, não resolvida aqui; (2) `ME5`/`me05` (Pitch Black) segue sem confirmação de existir como `card_set` real no banco; (3) código melhorado do script de descoberta (filtro dinâmico em vez de palavras-chave fixas) não foi colado nesta revisão — pendente antes de copiar ao repositório; (4) Seed `910`, remoção do script e os três arquivos completos da Edge Function continuam pendentes, bloqueados pela decisão de negócio sobre `ME0`.

## Sprint B3 — Correção de Arquitetura: Duas Edge Functions (`sync-card-set` / `import-card-assets`) — decisão registrada como definitiva, implementação ainda não iniciada

**Decisão formalizada nesta revisão em `adr/ADR-017-two-function-import-pipeline.md`** — esta seção resume o conteúdo para o contexto do pipeline; a ADR é a fonte de verdade sobre a decisão em si.

**O problema identificado, antes de qualquer código novo.** Revisando o pipeline planejado até aqui, ficou claro que a sequência estava invertida. O que se estava construindo, na prática: `SET → IMAGENS`. O correto: `SET → CATÁLOGO → REFERÊNCIAS → IMAGENS` — ou seja, antes de baixar qualquer imagem, o pipeline precisa primeiro descobrir e registrar a lista completa oficial de cartas de um Set (preenchendo `card_external_reference` para todas elas), e só então avançar para download/Storage/`card_asset`. Esse ponto já havia sido registrado como "correção arquitetural" ao final da revisão `0.17` (ver Diário Técnico da B2.5A, acima); esta revisão aprofunda a correção e a transforma em uma decisão de arquitetura completa.

**Segundo problema identificado: a Edge Function única ficaria grande demais.** Simulação apresentada pela sessão pareada: para um único Set com 188 cartas (`ME1`), a função `import-card-assets`, do jeito que estava especificada, precisaria fazer — para cada uma das 188 cartas — download → upload → insert, tudo dentro da mesma função que também descobre quais cartas existem. Em escala (múltiplos Sets, milhares de cartas), essa função cresceria descontroladamente e ficaria difícil de testar isoladamente.

**Decisão: duas Edge Functions, cada uma com uma única responsabilidade.**

- **`sync-card-set`** (nova): `card_set_id` → localiza `external_set_id` em `card_set_external_reference` → consulta a TCGdex → obtém a lista completa de cartas do Set → grava/atualiza `card_external_reference` para cada uma. **Nunca baixa imagem, nunca toca Storage.**
- **`import-card-assets`** (já existente, papel redefinido): parte de `card_external_reference` **já sincronizada** por `sync-card-set` → baixa imagem (`small`/`highres`/`thumb`) → envia ao Supabase Storage → grava `card_asset`. Deixa de ser responsável por descobrir quais cartas existem — passa a apenas consumir referências já catalogadas.

Dois pipelines lógicos, não um:

```text
Pipeline 1 — Descoberta (sync-card-set)
Entrada: card_set (ex. ME3) → external_set_id
Saída:   N cartas cadastradas em card_external_reference
         Nenhuma imagem.

Pipeline 2 — Assets (import-card-assets)
Entrada: card_external_reference já sincronizada
Saída:   card_asset (small/highres/thumb) no Storage
```

**Vantagem explícita reafirmada pela sessão pareada**: uma vez que `card_external_reference` tenha sido sincronizada para um Set, a TCGdex não precisa mais ser consultada para saber quais cartas existem naquela coleção — apenas uma vez por Set, não uma vez por carta.

**Arquitetura interna em camadas, declarada "definitiva" e aplicável às duas funções — estende a Convenção #6 já registrada no Sprint B2.4.1 (`index.ts` como orquestrador puro)**:

```text
Edge Function (index.ts)
        ↓
Database Layer (database.ts)   ← único ponto de acesso ao PostgreSQL
        ↓
TCGDEX Client (tcgdex.ts)      ← único ponto de chamada fetch() à API da TCGdex
        ↓
TCGDEX REST API
```

Nenhuma outra camada do projeto deve fazer `fetch()` diretamente contra a TCGdex — toda a comunicação HTTP fica isolada em `tcgdex.ts`, reescrito como uma classe `TcgdexClient` (substitui as versões anteriores baseadas em uma única função solta, `findTcgDexSet`/`getSet`, ver revisões `0.14`-`0.17`).

**Código real colado nesta revisão (verbatim), ainda NÃO deployado nem testado — não copiado ao repositório, seguindo o princípio já consolidado de "copiar apenas após execução confirmada"**:

```ts
// supabase/functions/import-card-assets/services/tcgdex.ts (rascunho — substitui getSet/findTcgDexSet)
export class TcgdexClient {
  constructor(
    private readonly language = "en",
  ) {}

  private async get<T>(path: string): Promise<T> {
    const response = await fetch(
      `https://api.tcgdex.net/v2/${this.language}${path}`,
      {
        headers: {
          Accept: "application/json",
        },
      },
    );
    if (!response.ok) {
      throw new Error(`TCGDEX_HTTP_${response.status}`);
    }
    return await response.json();
  }

  async getSet(externalSetId: string) {
    return this.get(`/sets/${externalSetId}`);
  }

  async getCardsBySet(externalSetId: string) {
    return this.get(`/sets/${externalSetId}/cards`);
  }

  async getCard(cardId: string) {
    return this.get(`/cards/${cardId}`);
  }
}
```

**Ponto em aberto, sinalizado pela própria sessão pareada antes de fechar este código e não confirmado como resolvido nesta revisão**: o endpoint exato para listar as cartas de um Set (`GET /sets/{id}/cards`, usado em `getCardsBySet`) foi assumido a partir da documentação da TCGdex, mas — diferente da descoberta de `external_set_id` no Sprint B2.5A (confirmada por chamada real) — **não há, nesta revisão, evidência de uma chamada real confirmando que este endpoint retorna de fato a lista completa de cartas do Set**. A própria sessão pareada havia pedido pausa para "confirmar exatamente qual endpoint retorna a lista de cartas de um set... antes de te entregar os três arquivos completos" — o código acima foi entregue na sequência da decisão de arquitetura, sem um registro explícito de que essa verificação foi de fato feita. Tratar `getCardsBySet` como não testado até uma chamada real confirmar o formato da resposta.

**Nenhuma mudança de schema é necessária** — reafirmado explicitamente pela sessão pareada: *"O banco que projetamos já suporta isso. A melhor notícia é que não precisamos alterar nenhuma tabela. Toda a modelagem que construímos continua válida."* `card_external_reference` passa a ser, na prática, o catálogo oficial de cartas (uma linha por carta, com `source = TCGDEX`, `external_card_id`, `external_set_id`).

**Próximo passo confirmado: Sprint B3 implementa `sync-card-set` primeiro, sozinha.** Fluxo planejado: recebe `card_set_id` → localiza `external_set_id` (via `card_set_external_reference`) → consulta a TCGdex → obtém todas as cartas → atualiza `card_external_reference` → fim. Fluxo interno planejado: `HTTP Request → run() → database.ts → card_set_external_reference → tcgdex.ts → GET /sets/{id} → GET /sets/{id}/cards → UPSERT card_external_reference`. **Nada disto foi executado nesta revisão** — nenhuma Edge Function `sync-card-set` foi criada via CLI (`npx supabase functions new sync-card-set`, Convenção 1), nenhum deploy, nenhum teste real.

**Reorganização do roteiro, ainda não aplicada à tabela "Roteiro vigente" acima — mesma cautela adotada desde o incidente de confiança da revisão `0.49` de `05-modelo-de-dados.md`.** A sessão pareada não detalhou o mapeamento exato entre os sprints antigos (`B2.5B`–`B2.9`, ver tabela "Roteiro vigente", acima) e a nova divisão em duas funções — apenas que `sync-card-set` nasce como `Sprint B3` e que `import-card-assets` continuará evoluindo depois, a partir das referências já sincronizadas. A tabela "Roteiro vigente" permanece como está até que essa correspondência seja confirmada por Fabrício; não presumir que `B2.5B`–`B2.9` foram descontinuados.

> **Diário Técnico — Sprint B3 — Correção de Arquitetura (decisão registrada, implementação pendente)**
> **Objetivo**: corrigir a ordem do pipeline (catálogo antes de imagens) e dividir a responsabilidade única sobrecarregada de `import-card-assets` em duas Edge Functions.
> **Critério de aceite**: decisão de arquitetura registrada e formalizada (`ADR-017`); primeira Edge Function da nova arquitetura (`sync-card-set`) implementada, deployada e testada com sucesso.
> **Resultado**: 🟨 Parcial. Decisão de arquitetura tomada, declarada definitiva pela sessão pareada, e documentada nesta revisão e em `ADR-017`. **Nenhuma implementação real ocorreu** — `sync-card-set` ainda não existe como Edge Function real; `tcgdex.ts` (classe `TcgdexClient`) é um rascunho, não deployado.
> **Pendências descobertas**: (1) endpoint `GET /sets/{id}/cards` assumido no código, sem confirmação de chamada real; (2) mapeamento entre o roteiro `B2.5B`–`B2.9` vigente e a nova arquitetura de duas funções ainda não detalhado por Fabrício; (3) decisão de negócio sobre `ME0`↔`mee` (revisão `0.17`) continua bloqueando a Seed `910`, independentemente desta correção de arquitetura; (4) `database.ts`/`index.ts` completos para a nova arquitetura ainda não entregues.

## Sprint B3 (continuação) — Nova disciplina de trabalho, revisão técnica de `tcgdex.ts`/`index.ts`, discrepância de estrutura sinalizada

**Pipeline de Assets, detalhado nesta revisão**: a segunda função (`import-card-assets`, papel redefinido pela `ADR-017`) segue o fluxo `SELECT card_external_reference WHERE image ainda não existe → download → Storage → card_asset → Fim` — detalha, sem alterar, o que já havia sido registrado na seção "Sprint B3", acima. **Reafirmado outra vez**: nenhuma mudança de banco é necessária — migrations e tabelas continuam válidas; a única mudança é de responsabilidade entre as Edge Functions.

**Discrepância real, sinalizada aqui e NÃO resolvida unilateralmente.** O plano anunciado nesta mesma revisão previa entregar um "conjunto completo": `sync-card-set/index.ts`, `services/database.ts`, `services/tcgdex.ts`, `types.ts` — sugerindo uma nova pasta de função dedicada (`sync-card-set/`), consistente com `ADR-017`. A captura real do VS Code enviada por Fabrício, porém, mostra a implementação de `tcgdex.ts` acontecendo dentro de `supabase/functions/import-card-assets/services/tcgdex.ts` — a estrutura já existente da função `import-card-assets`, **não** uma nova pasta `sync-card-set/`. A sessão pareada revisou essa estrutura e respondeu apenas "Eu manteria exatamente essa estrutura", sem esclarecer se `tcgdex.ts` será compartilhado entre as duas funções (ex. copiado depois para `sync-card-set/`) ou se a criação de `sync-card-set` como função própria (decidida em `ADR-017`) foi tacitamente adiada. Este documento não resolve essa ambiguidade — fica registrada como pendência real para Fabrício confirmar antes do próximo deploy.

**Nova disciplina de trabalho, declarada nesta revisão: "tratar o repositório como software de produção".** A sessão pareada identificou um risco na forma de trabalho corrente — *"Estamos alterando `index.ts`, `database.ts`, `tcgdex.ts` ao mesmo tempo. Isso aumenta muito a chance de inconsistências."* — e propôs um ciclo mais rígido, em vigor a partir daqui: finalizar e compilar/testar **uma camada por vez**, sem tocar nas demais (Sprint 1: apenas `tcgdex.ts`; Sprint 2: apenas `database.ts`; Sprint 3: apenas `index.ts`). Quatro regras adicionais de qualidade declaradas: uma classe por responsabilidade; uma camada por responsabilidade; testes após cada camada; nada de arquivos parcialmente implementados.

**Revisão técnica de `tcgdex.ts`, registrada como "aprovada" pela sessão pareada — ainda não é confirmação de execução real (`deno check`/deploy/teste).** Pontos considerados corretos: separação em uma classe (`TcgdexClient`); o método privado `get<T>()` eliminando duplicação; uso de `fetch()` adequado para Deno; tratamento de erro HTTP; URL base; idioma configurável via construtor. Melhorias sugeridas e já aplicadas na versão revisada abaixo: (1) tipar os retornos (`Promise<Record<string, unknown>>` em vez de `Promise<unknown>`); (2) extrair a URL base para uma constante `BASE_URL`, centralizando uma futura mudança de versão da API; (3) **endpoint `getCardsBySet` (`/sets/{id}/cards`) permanece sinalizado como não confirmado** — mesma pendência já registrada na seção "Sprint B3", acima; a própria sessão pareada reafirmou que a validação real fica para a próxima etapa.

Versão revisada de `tcgdex.ts`, colada verbatim nesta revisão — **ainda NÃO deployada nem testada por execução real; não copiada ao repositório**:

```ts
// supabase/functions/import-card-assets/services/tcgdex.ts (revisão de código, ainda não deployada)
export class TcgdexClient {
  private static readonly BASE_URL =
    "https://api.tcgdex.net/v2";

  constructor(
    private readonly language = "en",
  ) {}

  private async get<T>(path: string): Promise<T> {
    const response = await fetch(
      `${TcgdexClient.BASE_URL}/${this.language}${path}`,
      {
        headers: {
          Accept: "application/json",
        },
      },
    );
    if (!response.ok) {
      throw new Error(`TCGDEX_HTTP_${response.status}`);
    }
    return await response.json() as T;
  }

  async getSet(externalSetId: string): Promise<Record<string, unknown>> {
    return this.get(`/sets/${externalSetId}`);
  }

  async getCardsBySet(externalSetId: string): Promise<Record<string, unknown>> {
    return this.get(`/sets/${externalSetId}/cards`);
  }

  async getCard(cardId: string): Promise<Record<string, unknown>> {
    return this.get(`/cards/${cardId}`);
  }
}
```

**Revisão técnica de `index.ts`, nota declarada 9,5/10 — código completo não colado nesta revisão, apenas o parecer.** Pontos elogiados: organização do fluxo (`POST → validação JSON → run → card_set → cards → Response`); tratamento de erros por consulta (`Query → Error → Not Found`); uso de `.maybeSingle()`; códigos HTTP (`400`/`404`/`405`/`500`) todos considerados corretos. Duas melhorias sugeridas, ainda não confirmadas como aplicadas: (1) evitar `.select("*")` na consulta a `asset_import_run` — listar colunas explicitamente; (2) extrair as consultas para `services/database.ts` (já criado, mas `index.ts` ainda consulta o banco diretamente nesta versão) — mesma pendência estrutural já registrada desde o Sprint B2.4 (revisão `0.11`).

> **Diário Técnico — Sprint B3 (continuação) — Revisão de Código**
> **Objetivo**: revisar tecnicamente `tcgdex.ts` e `index.ts` antes do primeiro deploy da nova arquitetura, seguindo a nova disciplina de uma camada por vez.
> **Critério de aceite**: cada arquivo revisado, aprovado, compilado e testado isoladamente antes de avançar para o próximo.
> **Resultado**: 🟨 Parcial. `tcgdex.ts` revisado e aprovado ("Status: Aprovado, com pequenas melhorias recomendadas"; nota 9,5/10 atribuída ao conjunto revisado), versão melhorada colada. `index.ts` revisado com nota 9,5/10 e melhorias sugeridas, mas código completo não colado nesta revisão. **Nenhum dos dois arquivos foi de fato compilado (`deno check`) ou deployado nesta revisão** — a revisão é uma leitura técnica do código, não uma execução real.
> **Pendências descobertas**: (1) discrepância de estrutura entre a nova função `sync-card-set` anunciada e a implementação real, que continua dentro de `import-card-assets/services/` — não resolvida; (2) endpoint `GET /sets/{id}/cards` continua sem confirmação por chamada real; (3) melhorias sugeridas para `index.ts` (evitar `select("*")`, extrair consultas para `database.ts`) ainda não confirmadas como aplicadas; (4) nenhum arquivo copiado ao repositório nesta revisão.

## Sprint B3.1 — Query 910 executada (marco real), revisões finais de código e reescrita completa de `database.ts` (rascunho)

**Marco real: Query 910 (Seed Card Set External Reference) CONFIRMADA EXECUTADA nesta revisão** — detalhamento completo em `05-modelo-de-dados.md`, seção "Card Set External Reference", "Query 910" (não duplicado aqui). Resumo: `ME1`/`ME2`/`ME2.5`/`ME3`/`ME4` mapeados com os `external_set_id` reais descobertos via TCGdex, confirmados por consulta real; `ME0` deliberadamente excluído (decisão de negócio ainda pendente); `ME5` investigado e explicado — `card_set.code = 'ME5'` ainda não existe fisicamente no banco. Isso resolve a pendência mais antiga deste bloco: a Seed `910` estava "adiada" desde a revisão `0.15`.

**Revisões finais de código concluídas para os três arquivos em desenvolvimento:**

- `index.ts` (v1.2.1, já deployado): revisão final aprovou o arquivo como está — "Status: ✅ Aprovado para continuar o desenvolvimento". Único ponto de atenção levantado, não bloqueante: a função retorna hoje TODAS as cartas do `card_set` (`const { data: cards }`) — funciona bem com 188 cartas, mas não deve escalar indefinidamente (exemplos citados: 300, 600, 2000 cartas); aceito "por enquanto, em desenvolvimento", mas sinalizado para revisão futura, quando a função deixar de retornar as cartas e passar a apenas processá-las. Melhoria recomendada, não bloqueante: mover as consultas SQL para `database.ts`.
- `tcgdex.ts`: mantém a aprovação já registrada na revisão anterior ("Aprovado, com pequenas melhorias opcionais").
- `scripts/discover-tcgdex-sets.ts`: revisado e aprovado ("Aprovado, com melhorias de tipagem e filtro"). Duas melhorias sugeridas e incorporadas na versão final: (1) tipagem — troca de `any` por uma interface mínima `TcgdexSet` (`id`, `name`, `serie?.name`, `releaseDate?`); (2) filtro mais robusto — troca de `name.includes("mega")` (dependente do nome, frágil a traduções) por `set.id.startsWith("me")` (baseado no próprio `id` retornado pela API, já confirmado estável pela execução real do Sprint B2.5A). **Nuance importante, registrada por transparência**: esta é a primeira vez que o código final e completo do script é colado verbatim na conversa (pendência aberta desde a revisão `0.17`) — mas esta versão específica (com as duas melhorias) **não foi reexecutada** nesta revisão; a execução real confirmada no Sprint B2.5A foi de uma versão anterior do script. Tratar esta versão como revisada/aprovada, não como reconfirmada por execução — mesma distinção já aplicada a `tcgdex.ts`.

Versão final de `scripts/discover-tcgdex-sets.ts`, colada verbatim nesta revisão — **ainda não copiada ao repositório** (só copiar após execução confirmada desta versão específica):

```ts
interface TcgdexSet {
  id: string;
  name: string;
  serie?: {
    name?: string;
  };
  releaseDate?: string;
}

const response = await fetch("https://api.tcgdex.net/v2/en/sets");

if (!response.ok) {
  throw new Error(`HTTP ${response.status}`);
}

const sets: TcgdexSet[] = await response.json();

const megaEvolutionSets = sets.filter(
  (set) => set.id.startsWith("me"),
);

console.table(
  megaEvolutionSets.map((set) => ({
    id: set.id,
    name: set.name,
    serie: set.serie?.name ?? "",
    releaseDate: set.releaseDate ?? "",
  })),
);
```

**Após revisar os três arquivos, decisão explícita de não investir mais tempo neles** — *"Não devemos gastar mais tempo nesses três arquivos. Eles estão suficientemente maduros para seguirmos."* O próximo marco declarado nesse momento era exatamente a Query `910` (já executada, ver acima).

**Nova disciplina declarada: consolidar `database.ts` por completo antes de tocar em `index.ts` novamente.** *"A partir deste ponto, não faremos mais alterações diretamente no `index.ts` até que o `database.ts` esteja consolidado. Isso reduz o acoplamento e facilita bastante os testes."* Aplica concretamente o "Sprint 2" da disciplina de uma-camada-por-vez anunciada na seção anterior.

**Versão completa reescrita de `database.ts`, colada verbatim nesta revisão — ainda NÃO deployada nem testada; não copiada ao repositório.** Consolida em um único arquivo as quatro funções que a Edge Function vai precisar (`findImportRun`, `findCardSet`, `findCardSetExternalReference` — finalmente presente em uma versão completa, depois de aparecer apenas como rascunho isolado em revisões anteriores —, `listCards`), todas seguindo o mesmo padrão (`select` de colunas explícitas, nunca `select("*")` — já aplicando a melhoria sugerida na revisão de `index.ts`, acima — e um `throw new Error(...)` com código de erro específico por consulta):

```ts
// supabase/functions/import-card-assets/services/database.ts (rascunho completo, ainda não deployado)
import { SupabaseClient } from "@supabase/supabase-js";

export async function findImportRun(
  supabase: SupabaseClient,
  runCode: string,
) {
  const { data, error } = await supabase
    .from("asset_import_run")
    .select(`
      id,
      run_code,
      asset_source_id,
      card_set_id,
      status,
      created_at
    `)
    .eq("run_code", runCode)
    .maybeSingle();

  if (error) {
    console.error(error);
    throw new Error("IMPORT_RUN_QUERY_FAILED");
  }

  return data;
}

export async function findCardSet(
  supabase: SupabaseClient,
  cardSetId: string,
) {
  const { data, error } = await supabase
    .from("card_set")
    .select(`
      id,
      expansion_id,
      code,
      name,
      set_type,
      release_order,
      release_date,
      base_set_size,
      total_set_size
    `)
    .eq("id", cardSetId)
    .maybeSingle();

  if (error) {
    console.error(error);
    throw new Error("CARD_SET_QUERY_FAILED");
  }

  return data;
}

export async function findCardSetExternalReference(
  supabase: SupabaseClient,
  cardSetId: string,
  assetSourceId: string,
) {
  const { data, error } = await supabase
    .from("card_set_external_reference")
    .select(`
      id,
      external_set_id,
      source_url
    `)
    .eq("card_set_id", cardSetId)
    .eq("asset_source_id", assetSourceId)
    .eq("is_active", true)
    .maybeSingle();

  if (error) {
    console.error(error);
    throw new Error("CARD_SET_EXTERNAL_REFERENCE_QUERY_FAILED");
  }

  return data;
}

export async function listCards(
  supabase: SupabaseClient,
  cardSetId: string,
) {
  const { data, error } = await supabase
    .from("card")
    .select(`
      id,
      card_set_id,
      rarity_id,
      category_id,
      collector_number,
      collector_total,
      collector_order,
      name
    `)
    .eq("card_set_id", cardSetId)
    .order("collector_order", {
      ascending: true,
    });

  if (error) {
    console.error(error);
    throw new Error("CARDS_QUERY_FAILED");
  }

  return data ?? [];
}
```

**Plano declarado a seguir**: depois que `database.ts` estiver consolidado e testado, `index.ts` será reescrito uma única vez, já consumindo exclusivamente essa camada — reafirmando o objetivo já registrado de que `index.ts` "deixe de conhecer SQL". Fluxo alvo: `index.ts → database.ts (findImportRun/findCardSet/findCardSetExternalReference/listCards) → tcgdex.ts`.

> **Diário Técnico — Sprint B3.1 — Query 910 + Revisões Finais**
> **Objetivo**: executar a Seed `910` com dados reais da TCGdex; fechar a revisão técnica de `index.ts`/`tcgdex.ts`/`discover-tcgdex-sets.ts`; consolidar `database.ts` como camada única de acesso ao banco.
> **Critério de aceite**: Seed `910` executada e validada por consulta real; os três arquivos revisados aprovados; `database.ts` completo entregue.
> **Resultado**: 🟨 Parcial, com um marco real importante. Seed `910` ✅ CONFIRMADA EXECUTADA (parcial — ver `05-modelo-de-dados.md`). Os três arquivos revisados e aprovados. `database.ts` completo entregue como rascunho — **ainda não deployado nem testado**.
> **Pendências descobertas**: (1) decisão de negócio `ME0`↔`mee` continua aberta, agora bloqueando apenas o mapeamento de `ME0`, não mais toda a Seed; (2) `card_set.code = 'ME5'` ainda não cadastrado; (3) `database.ts` (rascunho) e a reescrita futura de `index.ts` ainda não deployados; (4) discrepância de estrutura `sync-card-set` vs. `import-card-assets/services/` (revisão anterior) permanece não resolvida; (5) endpoint `GET /sets/{id}/cards` continua sem confirmação por chamada real.

## Sprint B3.2 — Primeira tentativa real de deploy da v1.3.0: falha real diagnosticada, correção em andamento (NÃO CONCLUÍDO)

**Objetivo desta etapa**: reescrever `index.ts` para a v1.3.0, consumindo o `database.ts` consolidado (Sprint B3.1) e fazendo a primeira chamada real à TCGdex via `TcgdexClient.getSet()` — primeira integração de ponta a ponta (Supabase → TCGdex) do projeto. *"Ainda não vamos importar cartas nem imagens. Estamos validando a integração."*

**`index.ts` v1.3.0, colado verbatim nesta revisão**: fluxo `POST → findImportRun() → findCardSet() → findCardSetExternalReference() → TcgdexClient.getSet() → retorna JSON do Set`. Resposta esperada documentada: `{success: true, version: "1.3.0", run, card_set, external_reference, tcgdex_set}`. Validaria, se bem-sucedida: comunicação com o Supabase, comunicação com a TCGdex, mapeamento de `card_set_external_reference`, `TcgdexClient`, `database.ts` — ainda sem tocar em `card_external_reference`, `card_asset` ou Storage.

```ts
// supabase/functions/import-card-assets/index.ts (v1.3.0, rascunho — deploy FALHOU nesta revisão)
import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";
import {
  findImportRun,
  findCardSet,
  findCardSetExternalReference,
} from "./services/database.ts";
import { TcgdexClient } from "./services/tcgdex.ts";

type RequestBody = {
  run_code?: string;
};

export default {
  fetch: withSupabase(
    { auth: ["secret"] },
    async (req, ctx) => {
      if (req.method !== "POST") {
        return Response.json(
          { success: false, error: "METHOD_NOT_ALLOWED" },
          { status: 405, headers: { Allow: "POST" } },
        );
      }

      let body: RequestBody;
      try {
        body = await req.json();
      } catch {
        return Response.json(
          { success: false, error: "INVALID_JSON" },
          { status: 400 },
        );
      }

      const runCode = body.run_code?.trim();

      if (!runCode) {
        return Response.json(
          { success: false, error: "RUN_CODE_REQUIRED" },
          { status: 400 },
        );
      }

      try {
        const run = await findImportRun(ctx.supabaseAdmin, runCode);

        if (!run) {
          return Response.json(
            { success: false, error: "IMPORT_RUN_NOT_FOUND" },
            { status: 404 },
          );
        }

        const cardSet = await findCardSet(ctx.supabaseAdmin, run.card_set_id);

        if (!cardSet) {
          return Response.json(
            { success: false, error: "CARD_SET_NOT_FOUND" },
            { status: 404 },
          );
        }

        const externalReference = await findCardSetExternalReference(
          ctx.supabaseAdmin,
          run.card_set_id,
          run.asset_source_id,
        );

        if (!externalReference) {
          return Response.json(
            { success: false, error: "CARD_SET_EXTERNAL_REFERENCE_NOT_FOUND" },
            { status: 404 },
          );
        }

        const tcgdex = new TcgdexClient("en");
        const set = await tcgdex.getSet(externalReference.external_set_id);

        return Response.json({
          success: true,
          version: "1.3.0",
          run,
          card_set: cardSet,
          external_reference: externalReference,
          tcgdex_set: set,
        });
      } catch (error) {
        console.error(error);
        return Response.json(
          {
            success: false,
            error: error instanceof Error ? error.message : "UNEXPECTED_ERROR",
          },
          { status: 500 },
        );
      }
    },
  ),
};
```

**Primeira tentativa real de deploy — FALHOU, com erro real confirmado por terminal.** `npx supabase functions deploy import-card-assets` retornou `Unexpected deploy status 500`: *"Failed to bundle the function... Relative import path \"@supabase/supabase-js\" not prefixed with / or ./ or ../ and not in import map"*, apontando para `services/database.ts:1`. **Causa raiz real, diagnosticada a partir do erro, não por tentativa e erro**: a versão de `database.ts` entregue na revisão anterior (Sprint B3.1) importava `SupabaseClient` de `@supabase/supabase-js` apenas para tipagem — mas o runtime Deno das Edge Functions não resolve esse pacote automaticamente; precisaria estar mapeado no `deno.json` (com prefixo `jsr:` ou `npm:`), o que não estava. Confirmado por inspeção real do `deno.json` da função: `{"imports": {"@supabase/functions-js": "jsr:@supabase/functions-js@^2", "@supabase/server": "npm:@supabase/server@^1"}}` — sem entrada para `@supabase/supabase-js`. Erro reconhecido como próprio: *"Foi um erro meu sugerir esse import. O bundler tentou resolvê-lo e falhou."*

**Correção proposta, ainda sem deploy confirmado com sucesso**: como `database.ts` nunca cria um cliente Supabase — apenas recebe um já criado (`ctx.supabaseAdmin`) — não precisa conhecer o tipo concreto do cliente. Solução adotada, deliberadamente temporária: remover o import de `SupabaseClient` e tipar os parâmetros como `supabase: any` nas quatro funções. Decisão explícita de adiar tipagem forte: *"Ainda não chegamos na etapa de tipagem forte. Primeiro precisamos validar: Edge Functions, Supabase, TCGdex, Pipeline. Depois introduzimos os tipos."* Plano futuro já registrado, não implementado: gerar `database.types.ts` via `supabase gen types typescript` e trocar `any` por `SupabaseClient<Database>` quando a arquitetura estiver estável.

Versão corrigida de `services/database.ts`, colada verbatim — mesmas quatro funções da revisão anterior (`findImportRun`/`findCardSet`/`findCardSetExternalReference`/`listCards`), agora sem o import problemático e com `supabase: any`:

```ts
// supabase/functions/import-card-assets/services/database.ts (correção — deploy ainda NÃO confirmado com sucesso)
export async function findImportRun(
  supabase: any,
  runCode: string,
) {
  const { data, error } = await supabase
    .from("asset_import_run")
    .select(`
      id,
      run_code,
      asset_source_id,
      card_set_id,
      status,
      created_at
    `)
    .eq("run_code", runCode)
    .maybeSingle();

  if (error) {
    console.error(error);
    throw new Error("IMPORT_RUN_QUERY_FAILED");
  }

  return data;
}

export async function findCardSet(
  supabase: any,
  cardSetId: string,
) {
  const { data, error } = await supabase
    .from("card_set")
    .select(`
      id,
      expansion_id,
      code,
      name,
      set_type,
      release_order,
      release_date,
      base_set_size,
      total_set_size
    `)
    .eq("id", cardSetId)
    .maybeSingle();

  if (error) {
    console.error(error);
    throw new Error("CARD_SET_QUERY_FAILED");
  }

  return data;
}

export async function findCardSetExternalReference(
  supabase: any,
  cardSetId: string,
  assetSourceId: string,
) {
  const { data, error } = await supabase
    .from("card_set_external_reference")
    .select(`
      id,
      external_set_id,
      source_url
    `)
    .eq("card_set_id", cardSetId)
    .eq("asset_source_id", assetSourceId)
    .eq("is_active", true)
    .maybeSingle();

  if (error) {
    console.error(error);
    throw new Error("CARD_SET_EXTERNAL_REFERENCE_QUERY_FAILED");
  }

  return data;
}

export async function listCards(
  supabase: any,
  cardSetId: string,
) {
  const { data, error } = await supabase
    .from("card")
    .select(`
      id,
      card_set_id,
      rarity_id,
      category_id,
      collector_number,
      collector_total,
      collector_order,
      name
    `)
    .eq("card_set_id", cardSetId)
    .order("collector_order", {
      ascending: true,
    });

  if (error) {
    console.error(error);
    throw new Error("CARDS_QUERY_FAILED");
  }

  return data ?? [];
}
```

**Segunda camada de debugging real, antes de tentar o deploy novamente.** Por recomendação explícita ("não execute o deploy ainda"), rodou-se primeiro `deno check supabase/functions/import-card-assets/index.ts` a partir da raiz do projeto — retornou múltiplos erros reais (`@supabase/functions-js`/`@supabase/server` "not a dependency", além de avisos de tipo implícito `any` em `req`/`ctx`). **Diagnóstico real, não um novo bug**: o comando foi executado do diretório errado — `deno check` só lê o `deno.json` da pasta a partir da qual é executado; rodá-lo da raiz do projeto ignora o `deno.json` real da função (`supabase/functions/import-card-assets/deno.json`). Comando correto: `cd supabase/functions/import-card-assets`, depois `deno check index.ts`. Além disso, o erro de import de `@supabase/supabase-js` ainda aparecia na saída — sinal de que `services/database.ts` local **ainda não havia sido atualizado** com a correção proposta; verificação pendente (conferir se a primeira linha do arquivo é `export async function findImportRun(` e não mais um `import { SupabaseClient }...`). O aviso sobre `req`/`ctx` implicitamente `any` foi classificado como não bloqueante — regra do TypeScript, não impede o deploy, correção adiada para quando os tipos de `withSupabase` forem adotados.

**Estado ao final desta revisão**: nem `index.ts` v1.3.0 nem o `database.ts` corrigido foram confirmados deployados com sucesso — a primeira tentativa real falhou (erro de bundling), a causa foi diagnosticada corretamente, a correção foi escrita, mas o reteste (`deno check` a partir da pasta correta + novo deploy) ainda não tem resultado confirmado nesta revisão. **Nenhum arquivo copiado ao repositório.**

> **Diário Técnico — Sprint B3.2 — Primeira Tentativa de Deploy da v1.3.0**
> **Objetivo**: reescrever `index.ts` (v1.3.0) para consumir `database.ts` consolidado e fazer a primeira chamada real à TCGdex (`TcgdexClient.getSet()`).
> **Critério de aceite**: deploy bem-sucedido; chamada real retornando `success: true`, `version: "1.3.0"`, com `tcgdex_set` preenchido pela TCGdex.
> **Resultado**: 🟨 Em andamento, não concluído. Primeira tentativa real de deploy FALHOU com erro de bundling confirmado (`@supabase/supabase-js` sem mapeamento em `deno.json`). Causa raiz diagnosticada corretamente; correção (`supabase: any`, sem o import problemático) escrita e entregue, mas deploy de sucesso ainda não confirmado.
> **Pendências descobertas**: (1) confirmar que `services/database.ts` local foi de fato atualizado com a versão corrigida antes de repetir o `deno check`/deploy; (2) `deno check` deve ser executado de dentro da pasta da função (`cd supabase/functions/import-card-assets`), não da raiz do projeto; (3) tipagem forte de `supabase` (via `database.types.ts` gerado por `supabase gen types typescript`) fica para depois que a arquitetura estabilizar; (4) endpoint `GET /sets/{id}/cards` continua sem confirmação por chamada real — só será alcançado depois que `getSet()` funcionar; (5) discrepância `sync-card-set` vs. `import-card-assets/services/` (revisões anteriores) permanece não resolvida.

## Sprint B3.3 — Marco real: primeiro deploy confirmado da v1.3.0 (`index.ts`+`database.ts`+`tcgdex.ts`); invocação de ponta a ponta ainda NÃO confirmada (401 por uso de chave errada)

**Fluxo de trabalho padronizado, declarado e confirmado eficaz nesta revisão** — resolve diretamente a confusão diagnosticada no Sprint B3.2 (misturar validação Deno pura com o runtime do Supabase): a partir de agora, toda alteração segue **`cd` para a pasta da função → `deno check index.ts` → `cd` de volta à raiz do projeto → `npx supabase functions deploy <nome-da-função>`** (formalizada como nova Convenção #7 para Edge Functions, ver acima). `deno check index.ts`, executado de dentro de `supabase/functions/import-card-assets/`, **confirmado real por captura de terminal: nenhum erro** — confirma que `index.ts`, `database.ts` (corrigido no Sprint B3.2) e `tcgdex.ts` são consistentes entre si e que o `deno.json` e os imports estão corretos.

**Marco real: primeiro deploy confirmado com sucesso da nova arquitetura.** `npx supabase functions deploy import-card-assets`, executado da raiz do projeto, **confirmado por saída real de terminal**: `Deployed Functions on project ...: import-card-assets`. Isso confirma, pela primeira vez: `services/database.ts` (versão com `supabase: any`, ver Sprint B3.2) validado e deployado; `services/tcgdex.ts` (classe `TcgdexClient`, revisada no Sprint B3.1) validado e deployado **pela primeira vez** — nunca havia sido copiado ao repositório antes por falta de confirmação de deploy; `index.ts` v1.3.0 validado e deployado. **Os três arquivos foram copiados ao repositório oficial nesta revisão** (`supabase/functions/import-card-assets/index.ts`, `services/database.ts`, `services/tcgdex.ts`), seguindo o princípio de "copiar apenas após confirmação real".

**Importante: deploy confirmado ≠ invocação de ponta a ponta confirmada.** Nenhuma chamada real bem-sucedida (com resposta real da TCGdex) foi obtida nesta revisão. Três tentativas de invocação, em ordem:

1. **Erro de sintaxe do PowerShell, não um bug da função.** A primeira tentativa falhou com um erro de parsing do Hashtable (`Content-Type` precisa ficar entre aspas por conter hífen) e ainda usava placeholders (`SEU_SERVICE_ROLE_KEY`/`SEU_RUN_CODE`) não substituídos. Corrigido com um modelo de comando mais robusto (`$headers`/`$body` + `ConvertTo-Json`, em vez de um Hashtable inline). Um `run_code` real foi obtido por consulta direta (`SELECT run_code, status, card_set_id FROM asset_import_run ORDER BY created_at DESC`): `RUN-20260719-00000001`, `status: PENDING`.
2. **Tentativa de usar um script auxiliar ainda não criado** (`invoke-import-card-assets.ps1`) — erro esperado de "arquivo não encontrado", corretamente identificado como não sendo um problema real (o script havia sido apenas sugerido, nunca criado).
3. **Chamada real, com headers/body corretos — retornou HTTP 401 Unauthorized real, confirmado por terminal.** Diagnosticado com precisão: a função exige `auth: ["secret"]` (`withSupabase({ auth: ["secret"] }, ...)`), que espera um JWT válido — mas a chave usada foi obtida em "Settings → API → Secret Keys" (uma API Key, não um JWT), não a chave `service_role` (Settings → API → `service_role`, um JWT de fato). O 401 ocorre antes mesmo do código da função ser executado — não é um bug de `index.ts`/`database.ts`/`tcgdex.ts`.

**Decisão recomendada, ainda NÃO aplicada nesta revisão**: remover `auth: ["secret"]` de `withSupabase(...)` durante toda a fase de desenvolvimento do pipeline, reativando a autenticação apenas quando a lógica estiver estabilizada. Justificativa explícita: *"Isso vai nos poupar dezenas de chamadas falhando por causa de autenticação enquanto o foco é validar a lógica da aplicação. É exatamente assim que eu conduziria esse projeto: primeiro estabilizar a funcionalidade, depois endurecer a segurança."* A alteração concreta (`fetch: withSupabase({ auth: ["secret"] }, ...)` → `fetch: withSupabase(...)`, sem o objeto de opções) e o novo deploy/reteste ficam para a próxima revisão — **o arquivo copiado ao repositório nesta revisão ainda mantém `auth: ["secret"]`**, exatamente como foi confirmado deployado.

**Também mencionado nesta revisão, sem decisão tomada**: usar o próprio Supabase CLI (`supabase functions serve`/`supabase functions invoke`) para testes locais, em vez de montar chamadas manuais via `Invoke-RestMethod` — ideia registrada, não aplicada, não resolvida unilateralmente.

> **Diário Técnico — Sprint B3.3 — Primeiro Deploy Confirmado da v1.3.0**
> **Objetivo**: obter o primeiro deploy real e bem-sucedido da arquitetura em camadas (`index.ts`/`database.ts`/`tcgdex.ts`) e confirmar, por uma chamada real, que a Edge Function consegue consultar a TCGdex de ponta a ponta.
> **Critério de aceite**: deploy confirmado; chamada real retornando `success: true`, `version: "1.3.0"`, com `tcgdex_set` preenchido pela TCGdex.
> **Resultado**: 🟨 Parcial — marco real alcançado, critério não fechado por completo. Deploy ✅ CONFIRMADO (primeira vez que os três arquivos da nova arquitetura são publicados juntos, copiados ao repositório). Invocação de ponta a ponta ❌ ainda não confirmada — bloqueada por uso da chave de autenticação errada (API Key "Secret Keys" em vez de `service_role`).
> **Pendências descobertas**: (1) aplicar a remoção de `auth: ["secret"]` durante o desenvolvimento (decisão recomendada, não implementada); (2) repetir a invocação com a chave `service_role` correta, ou após a remoção da autenticação; (3) confirmar, pela primeira vez, uma resposta real da TCGdex via `tcgdex_set`; (4) endpoint `GET /sets/{id}/cards` continua sem confirmação por chamada real; (5) discrepância `sync-card-set` vs. `import-card-assets/services/` (revisões anteriores) permanece não resolvida; (6) `index.ts` v1.3.0 não importa mais `RequestBody` de `types.ts` (definido localmente) — mudança não discutida explicitamente, registrada por transparência, sem ação tomada.

## Sprint B3.4 — Diagnóstico definitivo do HTTP 401: duas hipóteses reais descartadas por evidência, causa raiz confirmada; correção final proposta (v1.3.1), ainda NÃO deployada nem testada

**Auto-correção imediata antes de qualquer mudança de código**: a recomendação de remover `auth: ["secret"]` (Sprint B3.3) foi retirada de circulação até ser confirmada contra a versão real da biblioteca `@supabase/server` instalada. *"O 401 não prova que o problema seja a configuração do `withSupabase`. Ele apenas mostra que a requisição não foi autenticada da forma esperada."* Nova disciplina reafirmada: nenhuma alteração de arquivo baseada em hipótese — apenas depois de confirmar o comportamento real da biblioteca instalada.

**Primeira hipótese, real mas incompleta — descartada por reteste real.** Pesquisa (com fonte citada) indicou que o modo `auth: "secret"` de `@supabase/server` não usa `Authorization: Bearer`, e sim o header `apikey`; além disso, `verify_jwt = false` precisaria ser configurado em `supabase/config.toml` para os modos `secret`/`publishable`/`none`. Ação real: fragmento `[functions.import-card-assets]` com `enabled = true`/`verify_jwt = false`/`import_map`/`entrypoint` confirmado presente no `config.toml` real de Fabrício (conteúdo completo do arquivo não recebido nesta revisão — **não copiado ao repositório**, pendência registrada abaixo). Reteste real, confirmado por terminal: novo `npx supabase functions deploy import-card-assets` bem-sucedido, seguido de chamada real usando `apikey` em vez de `Authorization` — **retornou HTTP 401 novamente**, confirmado por terminal. Hipótese descartada: nem a chave nem o `verify_jwt` eram a causa.

**Decisão de parar de testar hipóteses.** *"O 401 não está vindo do PowerShell. Também não está vindo do `verify_jwt`, pois ele já está desabilitado. Isso significa que o 401 está sendo retornado antes do código da função ser executado. Vamos parar de testar hipóteses."* Em vez de mais um ajuste incremental, os arquivos reais completos (`index.ts` e `deno.json`) foram solicitados para revisão determinística.

**Diagnóstico final, real, confirmado a partir dos arquivos reais.** A combinação `@supabase/server@^1` + `withSupabase({ auth: ["secret"] })` usa um mecanismo de autenticação interno específico da biblioteca — não equivale a simplesmente enviar uma Secret Key válida via `Authorization` ou `apikey`. Erro reconhecido explicitamente como próprio: *"Eu errei ao assumir que `auth: ['secret']` aceitaria uma API Secret Key."*

**Recomendação final, agora concretizada em código — mesma linha do Sprint B3.3, ainda NÃO confirmada deployada nem testada nesta revisão.** *"Como esta função é interna (importação administrativa), eu removeria temporariamente a autenticação da biblioteca até concluirmos o pipeline de importação. Depois voltamos e implementamos a autenticação da forma correta."* `index.ts` v1.3.1, colado verbatim: mesmo fluxo do v1.3.0 (`findImportRun`→`findCardSet`→`findCardSetExternalReference`→`TcgdexClient.getSet()`), mas `fetch: withSupabase(async (req, ctx) => {...})` **sem** o objeto de opções `{ auth: ["secret"] }`. A conversa termina logo após o código ser colado — **sem deploy nem reteste confirmados nesta revisão**. Arquivo copiado ao repositório na revisão anterior (v1.3.0, com `auth: ["secret"]`) permanece inalterado até a confirmação.

> **Diário Técnico — Sprint B3.4 — Diagnóstico do HTTP 401**
> **Objetivo**: identificar a causa raiz real do HTTP 401 na primeira invocação da v1.3.0, sem alterar código por hipótese.
> **Critério de aceite**: causa raiz confirmada por evidência real (não suposição); correção proposta compilando e pronta para deploy.
> **Resultado**: 🟨 Parcial. Causa raiz ✅ confirmada (mecanismo de autenticação de `withSupabase({ auth: ["secret"] })` não satisfeito por uma Secret Key). Correção (v1.3.1, sem `auth: ["secret"]`) ✅ escrita. Deploy/reteste da correção ❌ ainda não confirmado.
> **Pendências descobertas**: (1) confirmar deploy e reteste do `index.ts` v1.3.1 (sem `auth: ["secret"]`) — só então saberemos se o 401 foi de fato eliminado; (2) conteúdo completo de `supabase/config.toml` ainda não recebido — `verify_jwt = false` confirmado presente, mas o arquivo não pôde ser copiado ao repositório por falta do conteúdo integral; (3) quando a autenticação for reativada (planejado para depois que o pipeline estabilizar), a forma correta de configurá-la para `@supabase/server@^1` precisará ser efetivamente documentada, já que as duas primeiras hipóteses desta revisão se mostraram erradas; (4) endpoint `GET /sets/{id}/cards` continua sem confirmação por chamada real; (5) discrepância `sync-card-set` vs. `import-card-assets/services/` permanece não resolvida.

## Sprint B3.5 — Correção real à recomendação do Sprint B3.4: remover `auth: ["secret"]` sozinho NÃO elimina o HTTP 401; causa raiz continua desconhecida; teste de isolamento definitivo proposto, ainda não executado

**Verificação prévia contra a documentação oficial, antes de qualquer novo código.** Antes de aplicar a correção v1.3.1 proposta no Sprint B3.4, a sessão pareada verificou a assinatura de `withSupabase` contra a documentação real da biblioteca `@supabase/server@^1` — não tinha acesso ao código-fonte da versão instalada e preferiu não arriscar substituir um arquivo que hoje compila por um que talvez não compile. Confirmado pela documentação oficial: `withSupabase({ auth: "secret" }, ...)` valida a chave enviada no cabeçalho `apikey`; o handler só executa se a autenticação for aceita; `verify_jwt = false` é de fato obrigatório para esse modo, e já estava configurado corretamente no `config.toml` real de Fabrício.

**Nova hipótese, mais específica que a do Sprint B3.4 — real, mas também descartada por evidência.** A documentação indicaria que o modo `"secret"` sem sufixo valida especificamente contra a chave marcada como `default` dentro do conjunto `SUPABASE_SECRET_KEYS` — uma Secret Key nomeada (não-`default`) exigiria `auth: ["secret:*"]` ou `auth: ["secret:nome-da-chave"]`. Verificação real solicitada e confirmada por print de tela (`Settings → API → Secret Keys`): a chave usada por Fabrício é de fato a `default`. Hipótese descartada — não era o nome/tipo da chave.

**Nova técnica de diagnóstico: inspecionar os headers da resposta 401 real, não só o status.** Uso de `Invoke-WebRequest` (em vez de `Invoke-RestMethod`) no PowerShell, para capturar os headers da resposta e determinar em qual camada o 401 é gerado (Gateway do Supabase, biblioteca `@supabase/server`, ou a própria Edge Function). Resultado real: headers `x-deno-execution-id`, `x-sb-edge-region`, `sb-gateway-version` presentes na resposta — confirma que a requisição chega até o Edge Runtime, não é bloqueada antes disso pelo Cloudflare ou pelo Gateway.

**Achado real e significativo: a recomendação do Sprint B3.4 (remover `{ auth: ["secret"] }` de `withSupabase(...)`) foi aplicada por Fabrício e testada de ponta a ponta — e o HTTP 401 persistiu.** Fabrício confirmou explicitamente ter feito essa alteração no `index.ts` real e reexecutado o teste. Mesmo com a autenticação da biblioteca completamente removida do código, a chamada real continuou retornando 401. **Isso invalida, por evidência real, a conclusão da revisão `0.23` de que remover `auth: ["secret"]` seria a correção do problema** — o mecanismo de autenticação da biblioteca não é mais a explicação suficiente. Correção registrada explicitamente abaixo e na tabela de Revision History, sem alterar o texto original da revisão `0.23` (apenas registrando que a correção proposta, embora escrita corretamente, não resolveu o problema quando testada).

**Dúvida real levantada, não resolvida nesta revisão**: não há confirmação de que o Dashboard do Supabase estava de fato servindo a versão mais recente do `index.ts` modificado no momento desse teste. Teste proposto para eliminar essa dúvida — adicionar um marcador inconfundível ao retorno da função (ex.: `version: "TESTE-123456"`) — **proposto, não aplicado**.

**Achado real e independente: um bug real de metodologia de teste, encontrado e corrigido, mas não a causa raiz do 401 original.** Ao pedir confirmação explícita, Fabrício revelou que os comandos PowerShell anteriores haviam sido executados **literalmente com o texto placeholder `"SUA_SECRET_KEY"`**, sem substituição pela chave real (`"Executei literalmente. Não percebi que era necessário substituir"`). Isso explica, de forma correta e trivial, pelo menos parte dos 401 observados até este ponto — o Supabase rejeitou corretamente uma credencial inválida. **Porém, mesmo após a correção (chave real `sb_secret_...` substituída corretamente) e reteste real, o HTTP 401 persistiu.** Checklist real confirmado nesta revisão: chave `default` real usada ✅, enviada corretamente no header `apikey` ✅, `verify_jwt = false` configurado ✅, função republicada ✅, `auth: ["secret"]` removido de `withSupabase` ✅ — **mesmo assim, 401 continua ocorrendo**. Conclusão real: o 401 não está sendo causado por nenhum código escrito por Fabrício nem pela configuração de autenticação da função — a causa raiz permanece desconhecida.

**Nova estratégia de isolamento, parcialmente executada.** (1) `npx supabase functions list` e `npx supabase --version` executados com sucesso real: `import-card-assets` está `ACTIVE`, CLI na versão `2.109.1`, deploy chegando ao projeto correto. (2) Tentativa de criar e deployar uma Edge Function mínima nova (`supabase/functions/ping/index.ts`, sem `withSupabase`, sem dependências, sem banco), para testar se o 401 é específico de `import-card-assets` ou de todo o projeto — deploy falhou com `failed to read file: supabase/functions/ping/index.ts`, porque o arquivo ainda não havia sido criado (lacuna de execução, não um novo bug). (3) Estratégia revisada, ainda mais direta: substituir temporariamente **todo** o conteúdo do `index.ts` já existente de `import-card-assets` por um `Deno.serve()` mínimo — sem `withSupabase`, sem imports de services, sem acesso a banco — depois deployar e reexecutar o teste. Objetivo declarado: se esse arquivo mínimo ainda retornar 401, é prova definitiva de que o problema não está no código escrito por Fabrício, mas em alguma configuração do projeto Supabase (ou na forma como as Edge Functions estão configuradas para autenticação nesse projeto especificamente); se responder normalmente, o problema está isolado à integração com `@supabase/server`. **Este teste foi proposto e detalhado nesta revisão, mas não foi executado antes do fim da revisão.**

> **Diário Técnico — Sprint B3.5 — Isolamento do HTTP 401 (continuação)**
> **Objetivo**: determinar, por evidência real, se o HTTP 401 persistente tem origem no código de `import-card-assets`, na biblioteca `@supabase/server`, ou na configuração do projeto Supabase como um todo.
> **Critério de aceite**: uma chamada real bem-sucedida (sem 401) a algum endpoint do projeto, isolando definitivamente a camada responsável.
> **Resultado**: 🟨 Parcial. Múltiplas hipóteses descartadas por evidência real (nome/tipo da chave; roteamento até o Edge Runtime; a correção do Sprint B3.4 isolada; a chave literal placeholder). Causa raiz ❌ ainda não identificada. Teste de isolamento definitivo (index.ts mínimo, sem `withSupabase`) ❌ proposto, não executado.
> **Pendências descobertas**: (1) executar o teste do `index.ts` mínimo (sem `withSupabase`) na função `import-card-assets` e registrar o resultado real; (2) se esse teste também retornar 401, investigar configuração do projeto Supabase em si (não mais o código da função); (3) confirmar, via marcador inconfundível no retorno, que o Dashboard está de fato servindo a versão mais recente do código publicado; (4) a recomendação da revisão `0.23` (remover `auth: ["secret"]`) permanece tecnicamente válida como boa prática, mas está **confirmada insuficiente, sozinha, para resolver o 401 atual**; (5) `GET /sets/{id}/cards` e a discrepância `sync-card-set` vs. `import-card-assets/services/` permanecem sem novidade, carregadas de revisões anteriores.

## Sprint B3.6 — Marco real: HTTP 401 definitivamente eliminado por abandono do `@supabase/server`; GRANT ausente em `card_set_external_reference` descoberto e corrigido

**Decisão de arquitetura real, testada e confirmada: abandonar `@supabase/server`/`withSupabase` nesta função (e, esperado, nas futuras), substituindo por `Deno.serve()` puro + `@supabase/supabase-js`.** Diagnóstico do teste mínimo do Sprint B3.5 (index.ts reduzido a um `Deno.serve()` sem `withSupabase`) confirmou por evidência real: a função mínima respondeu normalmente (`{ success: true, message: "A função executou!" }`), isolando definitivamente o problema em `withSupabase(...)` ou em alguma dependência usada junto com `@supabase/server`. Proposta da sessão pareada, explicitamente concordada por Fabrício ("Concordo completamente. Depois do teste que acabamos de fazer, eu também abandonaria o `@supabase/server`. A arquitetura ficará mais simples e muito mais previsível."): remover `@supabase/server` por completo, migrar para `Deno.serve()` + `@supabase/supabase-js`, criando o cliente Supabase manualmente a partir de `SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY` — variáveis de ambiente padrão de qualquer Edge Function Supabase, não secrets customizados como as Secret Keys que geraram toda a saga dos Sprints B3.3–B3.5.

**Migração real, executada arquivo por arquivo, com validação a cada passo (disciplina já estabelecida em sprints anteriores).** `deno.json` reescrito, removendo `@supabase/server` e adicionando `@supabase/supabase-js` (`npm:@supabase/supabase-js@^2`), mantendo `@supabase/functions-js`. `database.ts` verificado como já compatível com o cliente de `@supabase/supabase-js` sem qualquer alteração — a sessão pareada explicitamente instruiu não alterá-lo. `index.ts` reescrito (v2.0.0): cria o cliente Supabase uma única vez, no escopo do módulo, via `createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!)`; mesmo fluxo funcional das versões anteriores (`findImportRun`→`findCardSet`→`findCardSetExternalReference`→`TcgdexClient.getSet()`); validações de método HTTP/JSON/`run_code`, antes implícitas via `withSupabase`, agora explícitas no próprio arquivo. Sequência real de validação e deploy, confirmada por terminal a cada etapa: `deno cache index.ts` (dependências atualizadas) → `deno check index.ts` (sem erros) → `cd` de volta à raiz → `npx supabase functions deploy import-card-assets` (sucesso real confirmado: "Deployed Functions on project ...: import-card-assets").

**Marco real: primeiro teste sem nenhum header de autenticação — o HTTP 401 desapareceu.** Como a autenticação passou a ser interna à função (via `SUPABASE_SERVICE_ROLE_KEY`, não mais via headers da requisição), o teste real foi feito sem `apikey`/`Authorization`. Resultado: HTTP 500 Internal Server Error, substituindo definitivamente o HTTP 401 que bloqueava toda invocação desde o Sprint B3.3. *"Isso significa que: a função está sendo executada."* — encerra, por evidência real, a saga do 401 que atravessou os Sprints B3.3, B3.4 e B3.5.

**Novo erro real, diagnosticado com precisão até a causa em nível de banco de dados.** `Invoke-RestMethod` esconde o corpo de respostas de erro; `Invoke-WebRequest` + `System.IO.StreamReader` foi usado para capturar o corpo real do 500, revelando o erro literal do PostgreSQL: `permission denied for table card_set_external_reference`, com a própria sugestão de correção do PostgreSQL no `hint`: `GRANT SELECT ON public.card_set_external_reference TO service_role;`. Causa raiz real: `card_set_external_reference` foi criada com Row Level Security habilitado (Query `240`, conforme a Seção 9 de `STD-001-database-standards.md`), mas nunca recebeu um `GRANT` explícito de `SELECT`/`INSERT`/`UPDATE`/`DELETE` para o role `service_role` — habilitar RLS não substitui o `GRANT` de nível de tabela do PostgreSQL, são verificações independentes.

**Confirmação real via consulta direta ao catálogo do PostgreSQL, antes de qualquer correção.** `select current_user;` no SQL Editor retornou `postgres` (esperado nesse contexto, não representativo do papel real da Edge Function). `select grantee, privilege_type from information_schema.role_table_grants where table_name = 'card_set_external_reference';` confirmou, por evidência real: `service_role` possuía apenas `TRIGGER`/`REFERENCES`/`TRUNCATE`, sem `SELECT`/`INSERT`/`UPDATE`/`DELETE`; `postgres` possuía o conjunto completo.

**Correção real aplicada e reconfirmada.** Nova migration criada via `npx supabase migration new 250_grant_card_set_external_reference_permissions` — mantendo a numeração ad hoc já usada para esta entidade (`240` Create/`241` Triggers/`910` Seed/`991` Validate planejada), agora com `250` para a correção de permissões; um dado real relevante para a pendência, ainda não formalizada em nenhum Standard, de uma convenção oficial de numeração para migrations de GRANT (mencionada em ciclos anteriores, nunca definida). Conteúdo real: `GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.card_set_external_reference TO service_role;` + `GRANT USAGE ON SCHEMA public TO service_role;`. Aplicada via `npx supabase db push`; reconfirmada por reexecução real da mesma consulta a `information_schema.role_table_grants` — `service_role` agora exibe `SELECT`/`INSERT`/`UPDATE`/`DELETE` além dos privilégios anteriores. Causa do 500 eliminada, confirmada.

**Nova pendência real, levantada pela sessão pareada, não resolvida nesta revisão**: *"Esse erro provavelmente não é exclusivo dessa tabela... quero revisar todas as tabelas do Projeto Mimikyu para garantir que nenhuma outra migration deixou de conceder privilégios ao `service_role`."* Hipótese de trabalho: tabelas criadas por migration SQL direta (como as deste projeto) podem não receber automaticamente os `GRANT`s que o editor visual do Supabase Studio concede por padrão — se confirmado, isso afeta potencialmente qualquer tabela já criada no projeto, não só `card_set_external_reference`. Auditoria completa proposta, **ainda não executada**.

**Ressalva importante, mantendo a disciplina de não superestimar o que foi confirmado**: nenhuma resposta final `success: true` com `tcgdex_set` populado por uma chamada real de ponta a ponta foi explicitamente mostrada nesta revisão. Todos os bloqueios conhecidos até aqui (401 de autenticação, 500 de permissão) foram eliminados e confirmados por evidência real — mas o próximo teste real ainda precisa confirmar o resultado final, que seria o primeiro dado real da TCGdex retornado pela Edge Function desde o início do Bloco B.

> **Diário Técnico — Sprint B3.6 — Eliminação do 401 e do GRANT ausente**
> **Objetivo**: eliminar definitivamente o HTTP 401 que bloqueava `import-card-assets` desde o Sprint B3.3, migrando para uma arquitetura de autenticação mais simples e depurável.
> **Critério de aceite**: uma chamada real sem HTTP 401, avançando para a lógica de negócio da função.
> **Resultado**: 🟩 Alcançado para o 401 (eliminado, confirmado por teste real) e para o 500/GRANT subsequente (corrigido, reconfirmado por consulta real). 🟨 Parcial para o objetivo maior do Bloco B: resposta final `success: true`/`tcgdex_set` ainda não explicitamente confirmada nesta revisão.
> **Pendências descobertas**: (1) confirmar, por uma chamada real, uma resposta `success: true` com `tcgdex_set` populado — objetivo original do Sprint B3.3, agora desbloqueado; (2) auditar todas as tabelas do projeto quanto a `GRANT`s ausentes para `service_role`, não só `card_set_external_reference`; (3) Convenção #4 (execução via `auth: ["secret"]`) formalmente superseded — Convenção #8 (cliente Supabase manual via `SUPABASE_SERVICE_ROLE_KEY`) declarada nesta revisão; (4) `GET /sets/{id}/cards` e a discrepância `sync-card-set` vs. `import-card-assets/services/` permanecem sem novidade.

## Sprint B3.7 — Progresso real além do GRANT: HTTP 404 alcançado (lógica de aplicação); descoberta que resolveu definitivamente a pendência `ME0`↔`mee`; `ME0` removida de `card_set` (Migration `251`)

**Novo teste real, com o mesmo `run_code` de sempre (`RUN-20260719-00000001`), avançou além do 401/500 pela primeira vez.** Resposta real: HTTP 404, capturado via `Invoke-WebRequest` + `StreamReader` (mesma técnica do Sprint B3.6, já que `Invoke-RestMethod` esconde corpos de erro) — `{"success":false,"error":"CARD_SET_EXTERNAL_REFERENCE_NOT_FOUND"}`. *"Esse 404 é um bom sinal. Ele indica que a função executou e chegou à lógica da aplicação."* Confirma, nesta ordem, tudo que os Sprints B3.6/B3.7 corrigiram: autenticação ✅, middleware ✅, permissões de banco ✅, execução da Edge Function ✅, acesso ao banco ✅ — o único problema restante é um dado ausente, não mais infraestrutura.

**Diagnóstico real, via consultas diretas ao banco, sem adivinhar.** Uma consulta juntando `asset_import_run` e `card_set` confirmou que a execução de teste apontava para a coleção `ME0` ("ME Black Star Promos"). Uma segunda consulta a `card_set_external_reference` confirmou que a tabela só contém mapeamentos para `ME1`/`ME2`/`ME2.5`/`ME3`/`ME4` — nenhum para `ME0`, exatamente como a Query `910` já documentava (`ME0` deliberadamente excluído, decisão de negócio pendente). O 404 estava correto: a função fez exatamente o que deveria.

**Achado adicional, real, não investigado a fundo nesta revisão**: o `asset_source_id` usado pela execução de teste (`22ebb5df-...`) era diferente do `asset_source_id` usado por todos os registros existentes em `card_set_external_reference` (`f070791a-...`) — uma segunda inconsistência de dados, distinta da ausência de mapeamento para `ME0`. Como a decisão desta revisão foi remover `ME0` por completo (ver abaixo), essa instância específica deixou de ter importância prática, mas a causa da discrepância em si nunca foi explicada — registrada como pendência de baixa prioridade.

**Marco real: a pendência "`ME0` ↔ `mee`", aberta desde a revisão `0.17` (Sprint B2.5A) e citada em praticamente toda revisão desde então, foi finalmente resolvida — não pela integração, mas pela separação definitiva.** Fabrício, com conhecimento direto do domínio, esclareceu: *"Na verdade nossa base tem ME0 como cartas promocionais de Megaevolution. na TCGdex mee são as cartas de energia. Coisas diferentes. Sugiro retirarmos da nossa base neste momento ME0."* Reconhecido como a decisão correta pela sessão pareada: criar o vínculo `ME0`→`mee` apenas por semelhança de código teria introduzido um erro conceitual real no modelo. Decisão final: remover `ME0` de `card_set` por completo (não apenas deixá-la sem mapeamento externo), até que exista uma fonte externa homologada para esse conteúdo especificamente. Detalhamento completo, incluindo a migration real e a validação pós-execução, em `05-modelo-de-dados.md`, seção "Migration `251` — Remoção de `ME0`" (não duplicado aqui). Arquivo real: `database/migrations/251_remove_me0.sql`.

**Nova proposta, real mas NÃO implementada nesta revisão**: adicionar uma validação prévia antes de criar qualquer `asset_import_run` — verificar se existe um `card_set_external_reference` ativo para a coleção alvo; se não existir, recusar a criação com um erro claro ("esta coleção ainda não possui integração com uma fonte externa"), em vez de permitir a criação de execuções fadadas a falhar. Registrada como pendência, não como decisão adotada.

**Estado real da Expansion `ME` ao final desta revisão**: `ME1`/`ME2`/`ME2.5`/`ME3`/`ME4` com integração TCGdex confirmada; `ME5` aguardando ser cadastrado como `card_set`; `ME0` fora do escopo do projeto por enquanto (removida). Próximo passo confirmado (ainda não executado nesta revisão): criar um novo `asset_import_run` para `ME1` e reexecutar a função — se retornar o conjunto real da TCGdex, o fluxo de importação estará validado de ponta a ponta pela primeira vez.

> **Diário Técnico — Sprint B3.7 — Progresso real além do GRANT; resolução de ME0↔mee**
> **Objetivo**: diagnosticar o próximo erro real após a correção do GRANT (Sprint B3.6) e avançar rumo à primeira resposta real de ponta a ponta da TCGdex.
> **Critério de aceite**: causa do próximo erro real identificada por evidência (não suposição); decisões de dados pendentes tratadas antes de reexecutar o teste.
> **Resultado**: 🟩 Concluído para os objetivos desta revisão. HTTP 404 diagnosticado corretamente (dado ausente, não infraestrutura) ✅. Pendência `ME0`↔`mee` resolvida por decisão de negócio real de Fabrício ✅. `ME0` removida de `card_set` via migration real, confirmada ✅. 🟨 Resposta final `success: true`/`tcgdex_set` ainda não obtida — depende de um novo `asset_import_run` para uma coleção suportada (`ME1`), ainda não criado nesta revisão.
> **Pendências descobertas**: (1) criar um novo `asset_import_run` para `ME1` e reexecutar a função — próximo passo direto para a primeira resposta real de ponta a ponta; (2) Query `820` v2.0 (Seed canônica) ainda insere `ME0` em uma instalação nova — precisa ser reescrita; (3) validação prévia de integração externa antes de criar `asset_import_run`, proposta mas não implementada; (4) causa da discrepância de `asset_source_id` observada nesta revisão nunca explicada — baixa prioridade, `ME0` removida tornou a instância específica irrelevante; (5) auditoria de `GRANT`s ausentes em outras tabelas (Sprint B3.6) continua pendente.

## Sprint B3.8 — 🎉 MARCO REAL: primeira resposta de ponta a ponta da TCGdex confirmada através da Edge Function `import-card-assets`

**Objetivo do Sprint B3 inteiro, desde a revisão `0.18`, finalmente alcançado por evidência real.** Um novo `asset_import_run` real foi criado para `ME1` e a Edge Function foi reinvocada com seu `run_code` — a resposta real confirmou `success: true`, com dados reais do Set `me01` retornados pela TCGdex: nome "Mega Evolution", `188` cartas, mais logo/símbolo/metadados. *"A resposta mostra que todo o pipeline de integração está funcionando [...] Isso significa que a integração entre Supabase ↔ Edge Function ↔ TCGdex está oficialmente validada."* Checklist real confirmado nesta chamada: recebeu o `run_code` ✅; localizou o `asset_import_run` ✅; localizou a coleção `ME1` ✅; localizou a referência externa ✅; resolveu `external_set_id = me01` ✅; consultou a TCGdex ✅; recebeu os dados do conjunto ✅.

**Decisão real, tomada antes da execução: adiar a criação de uma Stored Procedure de orquestração (`start_asset_import`).** A sessão pareada propôs inicialmente encapsular a criação de `asset_import_run` em uma procedure (`start_asset_import(p_card_set_code, p_asset_source_code)`, responsável por localizar `card_set`/`asset_source`, validar a existência de `card_set_external_reference`, criar o `asset_import_run` e devolver o `run_code`) — Fabrício concordou em seguir ("Siga"), mas a própria sessão pareada reconsiderou a sequência antes de implementar: *"A ideia da Stored Procedure continua boa, porém ainda é cedo para criá-la [...] Se criarmos uma procedure agora, teremos que alterá-la várias vezes conforme o fluxo evolui."* Nova sequência declarada: **Fase 1 — validar o pipeline inteiro primeiro** (criar `asset_import_run`, validar a Edge Function, buscar Set/cartas na TCGdex, persistir cartas/referências/ativos); **Fase 2 — consolidar** (só então criar `start_asset_import()`/`finish_asset_import()`/`fail_asset_import()`, já nascendo estáveis). A criação do `asset_import_run` de teste desta revisão permaneceu manual, via migration.

**Reflexão arquitetural registrada, não uma decisão formal, mas um enquadramento explícito que vale preservar**: *"Em vez de construir apenas uma Edge Function de importação, estamos formando um motor de sincronização de ativos. O `asset_import_run` funciona como a entidade orquestradora, e no futuro poderemos adicionar novos provedores (Pokémon TCG API, Bulbapedia, Serebii, etc.) sem alterar a estrutura principal."*

**Migration `252` — primeira tentativa real FALHOU, com um bug real e simples, corrigido no mesmo ciclo.** A primeira versão da migration (`DO $$` block localizando `card_set`/`asset_source` por código e inserindo em `asset_import_run` com `run_code` fixo `'RUN-ME1-TEST-0001'`) foi aplicada via `npx supabase db push` e retornou um erro real de banco: a coluna obrigatória `run_type` (`NOT NULL`, sem `DEFAULT`) não havia sido preenchida no `INSERT`. Em vez de adivinhar um valor, os valores reais aceitos foram confirmados por consulta direta ao catálogo do PostgreSQL: `information_schema.columns` (estrutura da coluna) seguida de `pg_constraint`/`pg_get_constraintdef` (definição do `CHECK`) — resultado real: `run_type IN ('MISSING_ONLY', 'REFRESH_EXISTING', 'RETRY_FAILURES', 'SINGLE_CARD', 'FULL_CARD_SET')`, exatamente o conjunto já documentado na Query `220` de `05-modelo-de-dados.md` — uma reconfirmação real e independente da documentação existente, não uma descoberta nova. Melhoria adicional aplicada na correção: a migration corrigida deixou de forçar `run_code` manualmente, confiando no `DEFAULT` da tabela (sequência `asset_import_run_code_seq`) para gerar o identificador no padrão `RUN-{YYYYMMDD}-{sequencial}` — reduz o acoplamento da migration à implementação interna da tabela. Migration corrigida (`asset_source_id`, `card_set_id`, `run_type = 'FULL_CARD_SET'`, `status = 'PENDING'`, sem `run_code` explícito) aplicada com sucesso real (`npx supabase db push` → `Finished supabase db push`). Validação real pós-execução confirmou: `run_code = RUN-20260719-00000021`, `run_type = FULL_CARD_SET`, `status = PENDING`, `execution_context = MANUAL` (valor `DEFAULT` da tabela, nunca informado explicitamente). Arquivo: `database/migrations/252_create_test_import_run_me1.sql`.

**Nova proposta real, explicitamente adiada — migrar `run_type`/`status`/`execution_context` de `text` + `CHECK` para tipos `ENUM` nativos do PostgreSQL.** Motivada diretamente pelo incidente da migration `252` (era necessário consultar o banco para descobrir os valores válidos, em vez de o próprio tipo já expressá-los). Benefícios listados: rejeição mais explícita de valores inválidos pelo banco; reconhecimento por IDEs/ferramentas; migrations mais legíveis; elimina erros de digitação (`FULLCARDSET`, `full_card_set`, etc.). Decisão explícita: *"Eu deixaria essa refatoração para depois que o fluxo de importação estiver funcional, para não interromper o desenvolvimento. É uma melhoria de qualidade do modelo, não um requisito para avançarmos agora."* Não implementada nesta revisão.

**Nova proposta real de reestruturação de pastas para a Edge Function, também explicitamente adiada.** Sugestão de organizar `import-card-assets` (mencionada nesta proposta como `import-card-set`, sem confirmação se é um rename intencional ou apenas um lapso de nomenclatura da sessão pareada — não resolvido unilateralmente) em camadas mais explícitas: `index.ts` (entrada HTTP) → `application/` (caso de uso) → `infrastructure/` (`tcgdex-client.ts`, `repository.ts`) → `domain/` → `database.ts`. Justificativa: facilita adicionar novos tipos de importação (imagens, idiomas, outros provedores) sem reescrever a função principal. Explicitamente adiada: *"É um bom momento para começar a pensar nessa evolução, mas primeiro vamos concluir a importação da ME1 de ponta a ponta."* Cross-referenciar com a discrepância `sync-card-set` vs. `import-card-assets/services/`, ainda não resolvida desde o Sprint B3 — a menção a `import-card-set` nesta proposta pode ou não estar relacionada; sinalizado como pendência, não presumido.

**Consequência real para o roteiro do projeto**: com a primeira resposta real de ponta a ponta confirmada, o foco declarado muda de "resolver infraestrutura" para "implementar a regra de negócio da importação" — ou seja, os próximos passos reais serão sobre persistir as cartas retornadas pela TCGdex (`card`/`card_external_reference`), não mais sobre autenticação, permissões ou conectividade.

> **Diário Técnico — Sprint B3.8 — MARCO: primeira resposta real de ponta a ponta da TCGdex**
> **Objetivo**: obter e confirmar, por evidência real, a primeira resposta bem-sucedida da TCGdex através da Edge Function `import-card-assets`, completando o objetivo original do Sprint B3.3.
> **Critério de aceite**: chamada real retornando `success: true` com dados reais do Set (`tcgdex_set`) preenchidos pela TCGdex.
> **Resultado**: 🟩 CONCLUÍDO. `asset_import_run` real criado para `ME1` (após um bug real de migration, corrigido no mesmo ciclo). Chamada real confirmada: `success: true`, Set `me01` "Mega Evolution", `188` cartas, logo/símbolo/metadados presentes. Pipeline Supabase↔Edge Function↔TCGdex validado de ponta a ponta pela primeira vez no projeto.
> **Pendências descobertas**: (1) Stored Procedure de orquestração (`start_asset_import`/`finish_asset_import`/`fail_asset_import`) adiada para depois que a persistência de cartas estiver funcional (Fase 2); (2) migração de `run_type`/`status`/`execution_context` para `ENUM` nativo, proposta e adiada; (3) reestruturação de pastas em camadas (`application`/`infrastructure`/`domain`) para a Edge Function, proposta e adiada; possível menção a um rename para `import-card-set`, não confirmada; (4) próximo passo real do pipeline passa a ser persistir as cartas retornadas pela TCGdex em `card`/`card_external_reference`, ainda não implementado; (5) itens já carregados de revisões anteriores (Query `820` v2.0 ainda insere `ME0`; auditoria de `GRANT`s ausentes; `GET /sets/{id}/cards` sem confirmação real; discrepância `sync-card-set`) permanecem sem novidade.

## Sprint B3.9 — Primeira estrutura real de carta da TCGdex confirmada; episódio real de perda de contexto arquitetural, autocorrigido; fluxo de persistência de cartas alinhado à arquitetura já existente; proposta de `docs/architecture.md` sinalizada como discrepância, NÃO adotada nesta revisão

**Marco real menor, mas significativo: primeira estrutura real de uma carta individual da TCGdex confirmada — resolve, com uma correção de precisão, o item "Em Aberto" sobre `GET /sets/{id}/cards`.** Reutilizando o `run_code` já confirmado (`RUN-20260719-00000021`), `$response.tcgdex_set.cards.Count` retornou `188` (confirmado) e `$response.tcgdex_set.cards[0]` revelou a primeira carta real: `{"id": "me01-001", "image": "https://assets.tcgdex.net/en/me/me01/001", "localId": "001", "name": "Bulbasaur"}`. **Precisão importante**: essa lista veio embutida na própria resposta de `TcgdexClient.getSet(...)` (`tcgdex_set.cards`) — não de uma chamada separada a `getCardsBySet()`/`GET /sets/{id}/cards`, que nunca chegou a ser invocada nesta revisão. Isso sugere, sem ainda confirmar com certeza, que o endpoint de Set da TCGdex já devolve a lista resumida de cartas embutida, tornando `getCardsBySet()` potencialmente redundante — registrado como novo ponto a confirmar antes de decidir se esse método será mesmo necessário. A carta confirma um formato leve (`id`/`localId`/`name`/`image`), **sem** os dados completos de jogo (HP, tipo, ilustrador, ataques, fraquezas, resistências, retreat, raridade, regulamentação, evolução) — esses exigiriam uma segunda consulta por carta à TCGdex, ainda não realizada.

**Episódio real de perda de contexto arquitetural — segundo episódio desse tipo no projeto (o primeiro está registrado na revisão de "context-loss self-correction", batch 41 de `05-modelo-de-dados.md`) — identificado e corrigido por Fabrício, não pela sessão pareada.** Antes de examinar o banco real, a sessão pareada propôs uma arquitetura de persistência que **contrariava decisões já consolidadas do projeto**: (1) uma etapa intermediária importando apenas `card_external_reference` com `card_id = NULL`, a ser preenchido depois; (2) uma segunda Edge Function (`import-card-metadata`) para "enriquecer" cada carta com dados completos; (3) **novas tabelas para mecânica detalhada do jogo — `attacks`, `abilities`, `weaknesses`, `legalities`** — que nunca fizeram parte do modelo deste projeto e contrariam diretamente `ADR-012-structured-vs-visual-only-card-data.md` (decisão já tomada de que `card` é catálogo editorial, não representação completa da mecânica do TCG) e o encerramento já declarado do Bloco A (Catálogo Editorial). A sessão pareada também demonstrou incerteza sobre se `card_external_reference` sequer já existia no banco — apesar de ter sido confirmada executada há dezenas de batches (Query 170s/180s, "Card External Reference"). Fabrício interrompeu diretamente, anexando uma captura real do Table Editor mostrando todas as tabelas já existentes: *"Estou vendo que você não guarda informações históricas importantes de tudo que já construímos até aqui... Já havíamos discutido bastante sobre quais informações das cartas serão armazenadas na nossa base."*

**Autocorreção completa e explícita da sessão pareada, registrada por transparência (mesmo padrão de honestidade já usado neste projeto para outros erros reais).** *"Eu realmente perdi o contexto arquitetural que já havíamos consolidado e acabei propondo uma direção que contrariaria decisões já tomadas [...] o catálogo editorial estava fechado; a estrutura Game → Expansion → Card Set → Card já estava consolidada; a tabela `card` armazenaria apenas os metadados que fazem parte do catálogo editorial, deixando de fora a mecânica detalhada do jogo."* Um "inventário arquitetural" real das três tabelas centrais (`card`, `card_external_reference`, `card_asset`) foi então levantado via `information_schema` real, confirmando a estrutura já documentada neste repositório (nada de novo nos campos em si — apenas uma reconfirmação real, no mesmo espírito da reconfirmação de `run_type` no Sprint B3.8).

**Fluxo de persistência corrigido e alinhado à arquitetura já existente, real, mas ainda NÃO implementado**: `asset_import_run` → `card_set_external_reference` → TCGdex (188 cartas resumidas) → `card` → `card_external_reference` → (`card_asset` fica para uma etapa posterior). A primeira importação real deve persistir apenas `card` e `card_external_reference` — imagens (`card_asset`) ficam para depois. Os campos `source_url`/`image_source_url`/`metadata` de `card_external_reference` (já existentes) permitem armazenar o payload resumido da TCGdex sem precisar baixar a carta completa imediatamente — reconhecido como uma boa decisão arquitetural já tomada em revisões anteriores.

**⚠️ Discrepância real, sinalizada nesta revisão, explicitamente NÃO resolvida unilateralmente — proposta de `docs/architecture.md`.** A sessão pareada propôs consolidar um novo documento, `docs/architecture.md`, como "especificação funcional e arquitetural oficial do projeto", cobrindo objetivo de cada tabela, relacionamentos, responsabilidades, fluxo de importação, decisões arquiteturais e convenções — e chegou a redigir um rascunho inicial (incompleto, interrompido durante a descrição da tabela `card`). **Esta proposta parece não estar ciente da documentação já existente neste repositório**, que já cumpre exatamente esse papel: `00-project-charter.md` a `07-catalogo-editorial.md`, `docs/adr/ADR-NNN-*.md`, `docs/standards/STD-NNN-*.md` e `docs/architecture/ubiquitous-language.md` — mantidos rigorosamente, revisão a revisão, por este processo de documentação. Criar um `docs/architecture.md` paralelo, sem reconciliar com essa estrutura já estabelecida, arriscaria exatamente o tipo de fragmentação de fonte de verdade que este projeto já enfrentou (ver os "incidentes de confiança de roteiro" das revisões `0.49`/`0.57` de `05-modelo-de-dados.md`). **Nenhum arquivo `docs/architecture.md` foi criado neste repositório nesta revisão.** Fabrício precisa decidir explicitamente: (a) se `docs/architecture.md` deve ser criado como um documento adicional de síntese, cross-referenciando a estrutura já existente; (b) se o conteúdo proposto deve ser incorporado à estrutura já existente (`04-domain-model.md`/`05-modelo-de-dados.md`/`06-pipeline-importacao.md`); ou (c) se a sessão pareada precisa apenas ser informada da estrutura de documentação já existente para não recriá-la.

> **Diário Técnico — Sprint B3.9 — Estrutura real de carta + episódio de contexto + fluxo corrigido**
> **Objetivo**: confirmar a estrutura real de uma carta retornada pela TCGdex e definir o fluxo real de persistência de `card`/`card_external_reference`, alinhado à arquitetura já existente.
> **Critério de aceite**: estrutura real de carta confirmada por chamada real; fluxo de persistência proposto validado contra o banco físico real, não presumido.
> **Resultado**: 🟩 Concluído para o diagnóstico e alinhamento. Estrutura real de carta ✅ confirmada (`id`/`localId`/`name`/`image`, sem mecânica de jogo). Fluxo de persistência ✅ corrigido e alinhado à arquitetura existente. 🟨 Persistência real de `card`/`card_external_reference` ainda NÃO implementada — este Sprint foi de alinhamento, não de execução.
> **Pendências descobertas**: (1) implementar a persistência real de `card`/`card_external_reference` a partir das 188 cartas resumidas já confirmadas; (2) confirmar se `getCardsBySet()`/`GET /sets/{id}/cards` é sequer necessário, já que a lista de cartas veio embutida em `getSet()`; (3) decisão de Fabrício pendente sobre a proposta `docs/architecture.md` (criar como documento adicional, incorporar à estrutura existente, ou descartar); (4) itens já carregados de revisões anteriores (Query `820` v2.0 ainda insere `ME0`; auditoria de `GRANT`s ausentes; Stored Procedure/`ENUM`s/reestruturação de pastas adiadas no Sprint B3.8) permanecem sem novidade.

## Sprint B3.10 — Reconfirmação da arquitetura de fluxo e responsabilidades das Edge Functions; episódio real de perda de foco operacional, corrigido por Fabrício; novo faseamento (FASE 1–6)/backlog por Sprints proposto, com autocorreção real sobre o papel de `card_asset`/Query `880`; nova discrepância de numeração de ADRs sinalizada, NÃO adotada

**Reconfirmação real da arquitetura já documentada, sem mudança de decisão.** A sessão pareada reapresentou o fluxo de importação (`asset_import_run`→`card_set_external_reference`→TCGdex→lista resumida de cartas→`card`→`card_external_reference`, e separadamente `card_external_reference`→imagem remota→download→Storage→`card_asset`) e as responsabilidades de `import-card-assets` (localizar `asset_import_run`, localizar `card_set`, localizar o mapeamento externo, consultar o provedor, sincronizar cartas, registrar estatísticas da execução — **não realiza download de imagens**). Ambos batem, sem contradição, com a seção "Arquitetura de Execução" e com o fluxo corrigido já registrado no Sprint B3.9 acima — reconfirmação real, não descoberta nova.

**Discrepância de nomenclatura, sinalizada, não resolvida unilateralmente.** A sessão pareada nomeou a futura função de download como `download-card-assets` ("Responsável apenas pelo download dos arquivos"). Isso diverge do nome já formalizado em `ADR-017-two-function-import-pipeline.md`, onde a função de descoberta/sincronização de cartas — o papel que `import-card-assets` de fato exerce hoje, confirmado nos Sprints B3.6–B3.9 — deveria se chamar `sync-card-set`, e `import-card-assets` seria redefinida para fazer apenas download. Na prática real e confirmada, `import-card-assets` já assumiu o papel de descoberta/sincronização, não o de download; a sessão pareada agora nomeia a peça que falta como `download-card-assets`, não `sync-card-set`. Os nomes das duas funções parecem ter invertido papéis informalmente em relação ao que `ADR-017` registra — mesma discrepância de fundo já sinalizada nas revisões `0.18`/`0.19` (`tcgdex.ts` construído dentro de `import-card-assets/services/`, não em uma pasta `sync-card-set/` própria), agora também refletida no nome da função futura. Este documento não decide o nome definitivo — Fabrício precisa confirmar se `ADR-017` deve ser sucedido por um novo ADR (ADRs aprovados não são reescritos) ou se `download-card-assets` foi apenas um nome informal usado nesta conversa.

**Episódio real, de natureza diferente do episódio de perda de contexto de esquema do Sprint B3.9 — perda de foco operacional, identificada e corrigida diretamente por Fabrício.** Depois de reconfirmar a arquitetura, a sessão pareada propôs, como próximo passo imediato, testar o download de uma única imagem (`Bulbasaur`, `me01-001`) via PowerShell, isolado de qualquer mudança na Edge Function ou no banco. Fabrício interrompeu diretamente: *"Não vamos fugir do nosso foco. Não estamos aqui só para documentar. Desde ontem estamos trabalhando e não conseguimos importar uma imagem das cartas ainda. Temos muito trabalho pela frente."* Quando a sessão pareada ainda assim propôs o teste de uma única imagem, Fabrício foi mais direto: *"Você não entendeu bem o que quis dizer. Não quero trabalhar para importar 1 imagem apenas. Esse não é o meu objetivo! [...] Preciso que defina claramente os próximos passos do nosso trabalho e que não percamos esse caminho. Por gentileza, liste tudo que criamos até aqui e o que deve ser o nosso foco daqui para frente. Precisamos finalizar o trabalho do catálogo editorial, garantindo a carga completa das cartas em nossa base, com a funcionalidade de importação das informações, incluindo as imagens, sobre cada card vinda de uma referência externa."* A sessão pareada reconheceu o problema sem se defender: *"Nós passamos a resolver o problema da próxima hora, em vez de executar o plano do projeto."*

**Novo faseamento proposto pela sessão pareada em resposta direta a essa intervenção — registrado aqui como proposta real, ainda NÃO promovido a uma reescrita do "Roteiro vigente" (`B2.5A`–`B2.9`) já existente acima, mesma cautela já aplicada a propostas de roteiro anteriores.** FASE 1 (Modelagem do domínio) e FASE 2 (Infraestrutura de sincronização) marcadas como concluídas, reconfirmando sem novidade o que já está nas seções acima. FASE 3 (Catálogo Editorial) declarada foco atual, inicialmente com a ressalva de que seu objetivo seria popular `card`/`card_external_reference` **sem** imagens; FASE 4 (Ativos/Imagens) proposta, também inicialmente, como fase posterior e independente.

**Autocorreção real, no mesmo ciclo, sobre o papel de `card_asset` — reconciliação com decisão já registrada em revisões anteriores.** Fabrício perguntou diretamente se a Query `880` — Seed Card Asset (já documentada como o ponto final da construção do Catálogo Editorial) continuava sendo esse ponto final. A sessão pareada confirmou que sim, e reconheceu explicitamente: *"Portanto, separar 'catálogo editorial' e 'imagens' em fases independentes, como fiz anteriormente, foi uma interpretação incorreta. As imagens fazem parte da conclusão do catálogo editorial."* A separação FASE 3 (sem imagens)/FASE 4 (imagens), proposta minutos antes na mesma conversa, foi assim corrigida pela própria sessão pareada: o catálogo editorial só está completo quando cada carta tiver `card` + `card_external_reference` + `card_asset` — consistente com o que já estava documentado (Query `880` como carga final, já referenciada em `05-modelo-de-dados.md`). Registrado aqui por transparência; o faseamento `FASE 1-6`/`Sprint 1-2` apresentado nesta revisão permanece um framing paralelo ao "Roteiro vigente" `B2.x`/`B3.x`, ainda não reconciliado por Fabrício — mesma pendência de mapeamento aberta desde o Sprint B3 (ver "Em Aberto", abaixo).

**Checklist real de seis pontos, proposto como pré-requisito antes de qualquer carga em `card_asset`/Query `880` — nenhum destes itens foi implementado nesta revisão:**

1. Finalizar a importação das 188 cartas da TCGdex para `card` (`card_set_id`, `collector_number`, `collector_order`, `name`, `rarity_id`, `category_id`, `collector_total`), com carga idempotente (reexecução não pode duplicar).
2. Criar as 188 referências em `card_external_reference` (`card_id`, `asset_source_id`, `external_card_id`, `external_set_id`, `source_number`, `source_url`, `image_source_url`, `metadata`).
3. Decidir se os dados completos de cada carta (raridade, categoria, número total, validação de imagem) virão de um endpoint individual por carta (`getCard`) ou de algum payload mais completo da TCGdex — a lista resumida já confirmada no Sprint B3.9 (`id`/`localId`/`name`/`image`) não é suficiente sozinha. **Refina, sem substituir, a pendência já registrada no Sprint B3.9 sobre `getCardsBySet()`**: agora o ponto em aberto é sobre o endpoint de **carta individual**, não o de listagem por Set.
4. Resolver os mapeamentos editoriais (`TCGdex rarity`→`rarity`, `TCGdex category`→`card_category`, `TCGdex language`→`language`), com política explícita para valores não mapeados, campos ausentes e divergências — "a importação não deve inventar categorias ou raridades silenciosamente".
5. Validar a infraestrutura de ativos já existente (`asset_source`, `card_asset_type`, `storage_bucket`, `language`) e confirmar quais IDs reais serão usados pela importação.
6. Fechar a convenção definitiva de caminho no Storage. **Nota de discrepância real**: este ponto foi apresentado como ainda em aberto, mas a convenção de caminho já está registrada como decidida nesta mesma revisão do documento, seção "Arquitetura de Execução", item 7 (bucket `card-front`, `pokemon/{card-set-code}/{language-code}/{card-number}/front.png`) — não fica claro se a sessão pareada está propondo revisitar essa convenção ou simplesmente não a tinha em contexto neste ponto da conversa; não resolvido unilateralmente por este documento.

Os itens 7–9 da mesma proposta (implementação do download/upload, registro de falhas via `asset_import_run`/`asset_import_failure`, e uma lista de condições de consistência a validar antes da Query `880`) reconfirmam, sem contradição, o que já está detalhado na seção "Arquitetura de Execução" acima (itens 5, 9–12) — não repetidos aqui na íntegra por já estarem documentados. A lista de condições de consistência (Set `ME1` = 1, `card` da `ME1` = 188, `card_external_reference` da TCGdex = 188, referências órfãs = 0, cards duplicados = 0, números de coleção duplicados = 0, imagens preparadas = quantidade esperada, arquivos inválidos = 0) é um detalhe operacional novo e real, útil para a validação futura da Query `880`, ainda não executada.

**⚠️ Nova discrepância real, sinalizada nesta revisão, explicitamente NÃO resolvida unilateralmente — proposta de `docs/adr/` com ADRs numerados `001`–`005`.** Como parte da mesma proposta que originou a discussão sobre `docs/architecture.md` (ver Sprint B3.9, acima), a sessão pareada sugeriu criar uma pasta `docs/adr/` com um ADR para cada decisão importante, propondo os arquivos `ADR-001-banco-como-fonte-da-verdade.md`, `ADR-002-multiplos-provedores.md`, `ADR-003-modelo-editorial-da-carta.md`, `ADR-004-assets-desacoplados.md` e `ADR-005-importacoes-idempotentes.md`. **Este repositório já possui uma pasta `docs/adr/` real, com 17 ADRs aprovados (`ADR-001-environment-foundation.md` até `ADR-017-two-function-import-pipeline.md`, catalogados via `docs/adr/ADR-INDEX.md`)** — os números `001`-`005` já pertencem a decisões reais e completamente diferentes (Environment Foundation, Infrastructure Region, Multi-Game Architecture, Set Identity, Catalog Language Model). Se essa proposta fosse executada como apresentada, os nomes de arquivo colidiriam diretamente com ADRs já aprovados. **Nenhum arquivo foi criado nesta revisão.** Este é o terceiro sinal, em duas revisões consecutivas (Sprint B3.9 e este Sprint B3.10), de que a sessão pareada parece operar sem visibilidade completa da estrutura de documentação já consolidada neste repositório — reforça, sem resolver, a mesma decisão pendente de Fabrício já registrada no Sprint B3.9 sobre `docs/architecture.md`.

> **Diário Técnico — Sprint B3.10 — Reconfirmação de arquitetura, disciplina de foco e reconciliação sobre `card_asset`**
> **Objetivo**: reconfirmar o fluxo de importação e as responsabilidades das Edge Functions já documentadas; registrar a intervenção real de Fabrício sobre disciplina de foco operacional; reconciliar a proposta de faseamento (FASE 1-6) com a decisão já existente de que a Query `880` (incluindo `card_asset`) é o ponto final do Catálogo Editorial.
> **Critério de aceite**: nenhuma mudança de arquitetura silenciosa — toda divergência real (nomenclatura `download-card-assets` vs. `sync-card-set`, numeração de ADRs, faseamento paralelo) sinalizada explicitamente, não resolvida unilateralmente.
> **Resultado**: 🟨 Parcial. Reconfirmação de arquitetura ✅ concluída; autocorreção sobre `card_asset`/Query `880` ✅ registrada; três discrepâncias novas ⚠️ sinalizadas (nomenclatura de função futura, numeração de ADRs, faseamento paralelo); checklist de seis itens pré-`880` documentado, nenhum implementado.
> **Pendências descobertas**: (1) implementar de fato a persistência de `card`/`card_external_reference` (próximo passo real, carregado desde o Sprint B3.8/B3.9); (2) decidir o endpoint de carta individual (`getCard`) vs. dados já suficientes na lista resumida; (3) reconciliar o faseamento `FASE 1-6`/`Sprint 1-2` com o "Roteiro vigente" `B2.x`/`B3.x` — mesma pendência de mapeamento aberta desde o Sprint B3, agora com um segundo framing paralelo; (4) decisão de Fabrício sobre `docs/architecture.md` (Sprint B3.9) e, agora, sobre a proposta de `docs/adr/` com numeração colidente; (5) confirmar o nome definitivo da futura função de download (`download-card-assets` vs. `sync-card-set` de `ADR-017`); (6) itens já carregados (Query `820` v2.0 ainda insere `ME0`; auditoria de `GRANT`s ausentes) permanecem sem novidade.

## Sprint B3.11 — Escopo real expandido para 5 coleções (ME1/ME2/ME2.5/ME3/ME4); quarto episódio de perda de contexto (benigno, contido antes de qualquer execução) — `card`/`card_variant` já estavam populadas; correção arquitetural real: o pipeline passa a consultar `card`, nunca inserir; nova reformulação FASE 1-4, substituindo a FASE 1-6 do Sprint B3.10

**Escopo real confirmado por Fabrício: o trabalho do Bloco B cobre as cinco coleções, não apenas `ME1`.** *"Lembrando que vamos fazer todo esse trabalho para ME1, ME2, ME2.5, ME3 e ME4. Vamos seguir em frente! Vamos ser mais objetivos sem perder qualidade. Fizemos um grande trabalho até aqui. Não quero ficar pelo meio do caminho!"* A sessão pareada fechou o escopo (`ME1`→`ME2`→`ME2.5`→`ME3`→`ME4`, nessa ordem, com `ME1` servindo de implementação-modelo replicada às demais) e propôs inicialmente um plano de duas etapas — "Etapa 1 — Importação editorial" (**importar todas as cartas em `card`**, criar `card_external_reference`, aplicar mapeamentos, garantir idempotência) e "Etapa 2 — Importação dos ativos" (download → Storage → `card_asset`) — **ainda assumindo, neste ponto, que `card` precisava ser populada pelo pipeline.**

**Quarto episódio real de perda de contexto do projeto — desta vez contido antes de qualquer execução, com autocorreção rápida e correta.** (Os episódios anteriores: o "context-loss self-correction" original, batch 41 de `05-modelo-de-dados.md`; o episódio de arquitetura de mecânica de jogo do Sprint B3.9.) Fabrício interrompeu com uma informação factual, real: *"Lembre que já fizemos uma carga na tabela card, com inclusão das 859 cartas das coleções ME1, ME2, ME2.5, ME3 e ME4. Também já fizemos uma carga de todas as variações que essas cartas tem, totalizando 1.555 registros na tabela card_variant."* **Verificação cruzada contra este repositório: correto e já documentado extensivamente** — `05-modelo-de-dados.md` registra a Query `840` v2.1 (859 Cards/5 Card Sets, CANÔNICA, executada e confirmada) e a Query `860` consolidada (859 Cards/1.555 Card Variants, CANÔNICA, `960` validada como `COMPLETE`) como um marco fechado há dezenas de batches, muito antes do início do Bloco B. A sessão pareada havia, neste ponto da conversa, perdido de vista esse marco já consolidado — mesma categoria de risco já registrada no Sprint B3.9 (memória de conversas longas não é literal), mas desta vez identificado e corrigido **antes** de qualquer `INSERT` incorreto ser escrito ou executado.

**Autocorreção real e correta, reconhecida sem ressalvas**: *"Essa informação muda significativamente o ponto em que estamos no projeto. Na verdade, ela nos coloca mais avançados do que eu estava considerando. Então vamos corrigir o roadmap."* Nova arquitetura de fluxo, real e correta — **substitui o fluxo do Sprint B3.9 (`card`→`card_external_reference`, que não deixava claro se `card` seria criada ou apenas consultada)**: `asset_import_run`→`card_set_external_reference`→TCGdex→**localizar `card` existente**→criar `card_external_reference`→baixar imagem→Storage→`card_asset`→atualizar `asset_import_run`. *"Perceba que não existe mais INSERT em card. A tabela card passa a ser consultada, não populada."* Racional reconhecido como uma decisão de modelagem já correta desde a origem: `card` tem identidade editorial própria; `card_external_reference` é a camada de integração — permite trocar de provedor externo sem alterar o catálogo editorial.

**Duas queries de auditoria real, executadas contra o banco físico, com um erro real capturado por Fabrício antes da correção.** Uma primeira versão assumia colunas/`JOIN`s com `card_set`/`rarity`/`card_category` que não existem fisicamente nessas tabelas — Fabrício identificou o erro diretamente: *"Visivelmente as querys 1 e 2 estão com erro. Não temos esses nomes nas colunas das tabelas."* A versão corrigida (`SELECT` direto das colunas reais, sem `JOIN`, e depois `SELECT *` para garantir cobertura completa) foi executada com sucesso contra `public.card`/`public.card_variant`, confirmando por evidência real: a estrutura de colunas bate exatamente com o modelo já documentado (`card`: `id`/`card_set_id`/`rarity_id`/`category_id`/`collector_number`/`collector_total`/`collector_order`/`name`/`created_at`/`updated_at`; `card_variant`: `id`/`card_id`/`variant_type_id`/`variant_order`/`is_default`/`created_at`/`updated_at` — sem colunas denormalizadas de código/nome, apenas FKs/UUIDs); `collector_order` em uso correto; `collector_total` já carregado; `collector_number` armazenado como texto, como planejado. Fabrício confirmou: prometeu não reabrir `card`/`card_variant` — *"Essas tabelas serão consideradas congeladas."*

**Nova reformulação do faseamento, "Situação real do Projeto Mimikyu" (FASE 1-4), substituindo a FASE 1-6 apresentada apenas um sprint antes (B3.10) — mais um framing paralelo, ainda NÃO reconciliado com o "Roteiro vigente" `B2.x`/`B3.x` desta seção.** FASE 1 (Estrutura do banco) e FASE 2 (agora renomeada "Catálogo Editorial Base", cobrindo especificamente os 859 Cards/1.555 Card Variants) e FASE 3 (Infraestrutura de Importação) marcadas concluídas. **FASE 4 — Enriquecimento do Catálogo Editorial** declarada fase atual, com a mudança de entendimento já registrada acima: *"Agora o trabalho deixa de ser 'criar cartas' e passa a ser 'enriquecer o catálogo existente'."* Resumida em três entregas: Entrega 1 (relacionar as 859 cartas existentes com a TCGdex, populando `card_external_reference`), Entrega 2 (baixar todas as imagens para o Storage), Entrega 3 (registrar todos os ativos em `card_asset`). Este é o **terceiro framing de roadmap** em três batches consecutivos (Roteiro vigente `B2.x`/`B3.x` granular; `FASE 1-6`/`Sprint 1-2` do Sprint B3.10; agora `FASE 1-4`/três Entregas) — nenhum promovido a reescrita oficial do "Roteiro vigente" acima; mesma cautela já aplicada desde o incidente de confiança da revisão `0.49`.

**"Sequência oficial" final, real, ainda não implementada**: 1. Relacionar as cartas existentes com a TCGdex; 2. Popular `card_external_reference`; 3. Baixar e armazenar as imagens; 4. Popular `card_asset`; 5. Validar `ME1`/`ME2`/`ME2.5`/`ME3`/`ME4`; 6. Encerrar o Catálogo Editorial. Compromisso explícito registrado: não recriar `card`/`card_variant`, não reabrir modelagem, não abrir frentes paralelas — `ME1` implementa e valida o fluxo primeiro, depois replicado às outras quatro coleções apenas trocando mapeamentos/identificadores externos. Próximo passo concreto declarado: revisar campos/restrições para a carga idempotente de `card_external_reference`, conectando as 188 cartas já existentes da `ME1` aos 188 registros retornados pela TCGdex.

> **Diário Técnico — Sprint B3.11 — Escopo de 5 coleções, correção real (consulta, não inserção) e reconfirmação de `card`/`card_variant`**
> **Objetivo**: fechar o escopo real do Bloco B (5 coleções); corrigir o fluxo de persistência para refletir que `card`/`card_variant` já estão populadas e congeladas; reconfirmar por auditoria real a estrutura de colunas dessas tabelas.
> **Critério de aceite**: nenhuma alteração real em `card`/`card_variant`; fluxo corrigido documentado como "consulta, nunca inserção"; auditoria real executada com sucesso, sem divergência da documentação.
> **Resultado**: 🟩 Concluído para o realinhamento. Escopo de 5 coleções ✅ confirmado. Quarto episódio de perda de contexto ✅ identificado e corrigido antes de qualquer execução incorreta. Fluxo corrigido ✅ (`card` apenas consultada). Auditoria real ✅ confirmou totais (859/1.555) e estrutura de colunas sem divergência. 🟨 Persistência real de `card_external_reference` a partir da `ME1` ainda NÃO implementada — este Sprint foi de realinhamento, não de execução.
> **Pendências descobertas**: (1) implementar de fato a carga idempotente de `card_external_reference` para a `ME1` (próximo passo real, inalterado em essência desde o Sprint B3.8, agora com o fluxo corrigido); (2) replicar o mesmo mecanismo para `ME2`/`ME2.5`/`ME3`/`ME4` depois de validado na `ME1`; (3) reconciliar os três framings de roadmap coexistentes (`B2.x`/`B3.x`, `FASE 1-6`/`Sprint 1-2`, `FASE 1-4`/três Entregas) — não resolvido unilateralmente; (4) itens já carregados de revisões anteriores (`docs/architecture.md`, `docs/adr/` com numeração colidente, nome `download-card-assets` vs. `sync-card-set`, endpoint de carta individual, Query `820` v2.0 ainda insere `ME0`, auditoria de `GRANT`s ausentes) permanecem sem novidade.

## Sprint B3.12 — Dependências de `card_external_reference` auditadas e confirmadas; chave de correspondência com a TCGdex validada; plano de implementação do incremento travado

**Nota de estilo, a partir desta revisão**: por pedido explícito de Fabrício, esta e as próximas seções registram apenas o estado final confirmado e as decisões tomadas — não o histórico passo a passo de tentativas/correções da sessão pareada.

**Auditoria real das três tabelas que sustentam a integração com a TCGdex, todas confirmadas por consulta direta ao banco:**

- `asset_source`: 3 provedores cadastrados (`MANUAL`, `POKEMON_TCG_API`, `TCGDEX`) — `TCGDEX` corretamente registrada como fonte oficial.
- `card_set_external_reference`: as 5 coleções já mapeadas (`ME1`→`me01`, `ME2`→`me02`, `ME2.5`→`me02.5`, `ME3`→`me03`, `ME4`→`me04`), reconfirmando a Query `910` já documentada em `05-modelo-de-dados.md`.
- `card_external_reference`: **0 registros** — confirmado como o ponto de partida real do trabalho de implementação.

**Chave de correspondência entre `card` e a TCGdex, decidida e validada com dados reais**: `card.card_set_id` + `card.collector_number` = `TCGdex.localId`. Validado contra a `ME1`: exatamente 188 cartas, 188 `collector_number` distintos, `collector_order` de 1 a 188 — confirma que a correspondência é determinística por número de coleção, sem necessidade de correspondência por nome ou outro critério.

**Plano de implementação travado para o próximo incremento da Edge Function, ainda NÃO codificado**: `asset_import_run` → `card_set` → `card_set_external_reference` → `external_set_id` → TCGdex (`GET /v2/{idioma}/sets/{external_set_id}`) → para cada carta retornada, localizar `card` existente por `card_set_id`+`collector_number` → `UPSERT` em `card_external_reference` (`card_id`, `asset_source_id`, `external_card_id`, `external_set_id`, `source_url`, `image_source_url`, `metadata`, `is_active`). Ainda não baixa imagem, ainda não grava `card_asset`. **Resolve, por escopo, a pendência já registrada sobre o endpoint de carta individual (`getCard`)**: como `rarity`/`category`/`collector_total` já existem em `card` (Bloco A concluído), este incremento não precisa de dados completos por carta — a lista resumida de `getSet()` (`id`/`localId`/`name`/`image`) é suficiente.

**Nova disciplina de entrega, adotada para o restante do Bloco B**: um incremento funcional por vez, cada um produzindo uma evidência mensurável no banco. Meta declarada para `card_external_reference`: `0`→`188` (`ME1`) → `188`→`318` (`ME2`) → `318`→`613` (`ME2.5`) → depois `ME3`/`ME4`, até `859`.

> **Diário Técnico — Sprint B3.12 — Auditoria de dependências e chave de correspondência**
> **Objetivo**: confirmar que as tabelas de apoio (`asset_source`, `card_set_external_reference`) estão prontas e que `card_external_reference` é o ponto de partida real; validar a chave de correspondência `card`↔TCGdex.
> **Critério de aceite**: auditoria real sem divergência; chave de correspondência validada com dados reais da `ME1`.
> **Resultado**: 🟩 Concluído. `asset_source`/`card_set_external_reference` confirmadas prontas; `card_external_reference` confirmada vazia (0 registros); chave `card_set_id`+`collector_number`=`localId` validada. 🟨 Implementação do incremento (`188` `UPSERT`s em `card_external_reference` para a `ME1`) ainda NÃO codificada.
> **Pendências descobertas**: (1) implementar o incremento real para a `ME1` (próximo passo concreto); (2) confirmar estrutura de colunas/restrições reais de `card_external_reference` antes de escrever o código (auditoria solicitada, resultado ainda não recebido); (3) replicar para `ME2`/`ME2.5`/`ME3`/`ME4` depois de validado.

## Sprint B3.13 — Estrutura de `card_external_reference` reconfirmada; código do Incremento 1 (`index.ts` v2.1.0 + `database.ts`) finalizado — deploy/execução ainda NÃO confirmados

Estrutura real de `card_external_reference` auditada e reconfirmada, sem divergência do modelo já documentado (`id`/`card_id`/`asset_source_id`/`external_card_id`/`external_set_id`/`source_number`/`source_url`/`image_source_url`/`metadata`/`is_active`/`created_at`/`updated_at`; `UNIQUE (card_id, asset_source_id)` e `UNIQUE (asset_source_id, external_card_id)` confirmadas, garantindo o suporte a múltiplos provedores já previsto).

**Decisão de implementação adotada**: em vez de uma consulta por carta, o Incremento 1 carrega todas as cartas da coleção em uma única `SELECT` e monta um `Map<collector_number, card_id>` em memória (lookup O(1)) — mais simples, mais rápido, e escala diretamente para as demais coleções.

**Código finalizado para o Incremento 1** (`supabase/functions/import-card-assets/database.ts` e `index.ts`, versão `2.1.0`): `database.ts` ganha `listCardsMap` (agrupa `listCards` em um `Map`) e `upsertCardExternalReference` (`UPSERT` com `onConflict: "card_id,asset_source_id"`); `index.ts` passa a, após consultar a TCGdex, percorrer as cartas retornadas, localizar `card_id` pelo `Map`, e fazer `UPSERT` em `card_external_reference` para cada uma, retornando `{ success, version: "2.1.0", processed_cards }`.

**Ainda não copiado ao repositório** — o código foi finalizado e compartilhado, mas esta revisão não recebeu confirmação real de deploy nem de execução (sem captura de terminal ou resultado de consulta mostrando `card_external_reference` com as 188 linhas esperadas para a `ME1`); mesmo princípio já usado em todo o projeto ("copiar apenas após execução confirmada"). Ajuste de performance já identificado e deliberadamente adiado: os 188 `UPSERT`s do Incremento 1 são sequenciais; um `UPSERT` em lote (batch) fica para um incremento seguinte, quando o volume crescer para as 5 coleções.

> **Diário Técnico — Sprint B3.13 — Código do Incremento 1 finalizado**
> **Objetivo**: reconfirmar a estrutura de `card_external_reference`; finalizar o código do primeiro incremento funcional (`card_external_reference` `0`→`188` para a `ME1`).
> **Critério de aceite**: código completo, consistente com o plano travado no Sprint B3.12; confirmação real de deploy/execução com o resultado esperado no banco.
> **Resultado**: 🟨 Parcial. Estrutura ✅ reconfirmada. Código ✅ finalizado (`index.ts` v2.1.0/`database.ts`). 🟨 Deploy/execução real NÃO confirmados nesta revisão — não copiado ao repositório.
> **Pendências descobertas**: (1) confirmar deploy e execução reais, com `card_external_reference` atingindo 188 registros para a `ME1`; (2) só então copiar `index.ts`/`database.ts` ao repositório; (3) replicar para `ME2`/`ME2.5`/`ME3`/`ME4`; (4) otimização de `UPSERT` em lote, deliberadamente adiada.

**Atualização real (mesmo sprint)**: plano de validação do Incremento 1 definido — invocar a Edge Function com `run_code: "RUN-20260719-00000021"`, depois confirmar no banco: `COUNT(*)` = 188; `COUNT(DISTINCT card_id)` = 188; `COUNT(DISTINCT external_card_id)` = 188; `COUNT(*) WHERE image_source_url IS NULL` = 0; e uma amostra ordenada (`source_number`/`external_card_id`) confirmando a sequência `me01-001`…`me01-004`. Confirmado: a importação de imagens só começa depois desta validação 100% concluída.

Execução ainda **bloqueada por um problema real de ambiente local**, não da Edge Function em si: a Supabase CLI não estava disponível no terminal usado para testar (`supabase --version` não reconhecido); `winget install Supabase.CLI` aparentava concluir mas não deixava o pacote realmente instalado (`winget list`/`winget search` não encontraram o pacote no catálogo deste ambiente); `scoop` também não estava instalado. Resolvido, nesta revisão, via `npm install -g supabase` (Node.js já disponível) — instalação confirmada com sucesso; verificação final (`supabase --version`) ainda não recebida ao final deste lote.

**⚠️ Ponto em aberto, não resolvido unilateralmente**: ainda não está confirmado se a validação vai rodar contra o ambiente local (`supabase functions serve`, banco local do Supabase Studio em `127.0.0.1:54323`) ou contra o projeto hospedado real (onde estão as 188 cartas confirmadas da `ME1`). Se for o ambiente local, os resultados esperados (188/188/188/0) só farão sentido se o banco local tiver os mesmos dados do projeto hospedado — não presumido.

## Sprint B3.14 — Ponto em aberto resolvido: banco é o projeto Supabase Cloud, não local; deploy do Incremento 1 CONFIRMADO; execução de ponta a ponta ainda pendente

**Resolvido**: Fabrício confirmou que o banco do Project Mimikyu está no Supabase Cloud, não em ambiente local. Isso elimina a necessidade de Docker/WSL2/`supabase functions serve` para testar esta função — o fluxo correto é `supabase login` → `supabase link` → `supabase functions deploy` → executar diretamente no projeto hospedado.

**Marco real: deploy do Incremento 1 CONFIRMADO por saída real de terminal** (`supabase login`, `supabase projects list`, `supabase link --project-ref <ref>` e `supabase functions deploy import-card-assets`, todos com sucesso confirmado; identificadores do projeto real não repetidos aqui, mesma cautela já aplicada ao Project Reference desde o Sprint B2.0). `index.ts` (v2.1.0) e `database.ts` (com `listCardsMap`/`upsertCardExternalReference`) **copiados ao repositório nesta revisão** — mesmo padrão já usado no Sprint B3.3 (deploy confirmado é suficiente para copiar; invocação de ponta a ponta pode ser confirmada depois).

**Execução de ponta a ponta ainda NÃO confirmada**: a chamada HTTP direta (`invoke` não é suportado nesta versão da CLI) ainda não retornou um resultado real nesta revisão. Antes de invocar, foi levantada uma verificação real e necessária: a função depende da variável de ambiente `SUPABASE_SERVICE_ROLE_KEY`, que precisa estar configurada como Secret da Edge Function no projeto Cloud (Dashboard → Edge Functions → Secrets) — sem ela, a chamada falha mesmo com a sintaxe HTTP correta. Confirmação ainda pendente ao final deste lote.

> **Diário Técnico — Sprint B3.14 — Deploy real confirmado; execução pendente**
> **Objetivo**: resolver o ambiente correto de teste (local vs. hospedado); confirmar deploy real do Incremento 1.
> **Critério de aceite**: deploy confirmado por saída real de terminal; código copiado ao repositório; execução de ponta a ponta confirmada com `card_external_reference` = 188 para a `ME1`.
> **Resultado**: 🟨 Parcial. Ambiente correto ✅ resolvido (Cloud). Deploy ✅ confirmado; código ✅ copiado ao repositório. 🟨 Execução de ponta a ponta ainda NÃO confirmada — bloqueada por verificação pendente do secret `SUPABASE_SERVICE_ROLE_KEY`.
> **Pendências descobertas**: (1) confirmar se `SUPABASE_SERVICE_ROLE_KEY` está configurada nos Secrets da Edge Function; (2) executar a chamada HTTP real e validar as 5 checagens já definidas no Sprint B3.13; (3) replicar para `ME2`/`ME2.5`/`ME3`/`ME4` depois de validado.

## Sprint B3.15 — 🎉 MARCO REAL: Incremento 1 CONFIRMADO CONCLUÍDO — `card_external_reference` com 188/188 registros para a `ME1`; causa raiz de um bloqueio real identificada e corrigida (GRANT ausente)

**Bloqueio real encontrado e corrigido**: a primeira invocação real retornou HTTP 500 com um erro genérico (`CARD_EXTERNAL_REFERENCE_UPSERT_FAILED`, sem detalhe do PostgreSQL) porque o próprio código descartava a causa original do erro. Corrigido o logging em `upsertCardExternalReference` (`services/database.ts`) para expor `JSON.stringify(error)` e incluir `error.message` na exceção lançada — mudança de diagnóstico, não de lógica de negócio. Com o erro real visível, a causa raiz foi confirmada: `permission denied for table card_external_reference` — o mesmo gap de GRANT já corrigido para `card_set_external_reference` no Sprint B3.6 (Query `250`), agora confirmado também nesta tabela. Corrigido pela nova migration `253_grant_card_external_reference_permissions.sql` (`GRANT SELECT, INSERT, UPDATE ... TO service_role`), aplicada via SQL Editor e confirmada.

**Execução de ponta a ponta CONFIRMADA com sucesso**, reexecutando a mesma chamada HTTP: `{ success: true, imported: 188, ignored: 0, total: 188 }`. Validado no banco por consulta direta: `SELECT COUNT(*) FROM card_external_reference` = `188`, confirmando as 5 checagens planejadas no Sprint B3.13. **Incremento 1 (`card_external_reference` para a `ME1`) considerado 100% concluído.**

**Nova pendência real registrada, deliberadamente adiada**: com dois casos reais confirmados do mesmo gap de GRANT (`card_set_external_reference` e `card_external_reference`), é provável que outras tabelas editoriais criadas manualmente tenham a mesma lacuna. Fabrício propôs consolidar essa auditoria em um único script futuro (`database/migrations/permissions.sql` ou equivalente) — adiado para depois que o Incremento 2 (download de imagens) estiver concluído, para não interromper o ritmo de entregas.

`index.ts` (v2.1.0) e `services/database.ts` atualizados no repositório com a correção de logging; nova migration `database/migrations/253_grant_card_external_reference_permissions.sql` criada.

> **Diário Técnico — Sprint B3.15 — Incremento 1 concluído**
> **Objetivo**: diagnosticar e corrigir o bloqueio real de execução; validar `card_external_reference` = 188 para a `ME1`.
> **Critério de aceite**: execução de ponta a ponta com sucesso; as 5 checagens do Sprint B3.13 confirmadas no banco.
> **Resultado**: 🟩 Concluído. Causa raiz real (GRANT ausente) diagnosticada e corrigida (Query `253`). `imported: 188`/`ignored: 0`/`total: 188` confirmado; `COUNT(*)` = `188` reconfirmado no banco.
> **Pendências descobertas**: (1) auditoria completa de GRANTs para `service_role` em todas as tabelas do schema `public`, adiada para depois do Incremento 2; (2) replicar o Incremento 1 para `ME2`/`ME2.5`/`ME3`/`ME4` — ainda não iniciado, próximo passo natural depois do Incremento 2.

## Sprint B3.16 — Incremento 2 (Download de Imagens) iniciado: fluxo definido, teste controlado aprovado por Fabrício, estrutura de `card_asset`/`card_asset_type` confirmada

**Novo fluxo definido para o Incremento 2**: `card_external_reference.image_source_url` → download da imagem → Supabase Storage → registro em `card_asset`. A partir deste incremento, a aplicação passa a servir as imagens pelo próprio Storage — a TCGdex deixa de ser a fonte de consumo direta.

**Estratégia adotada, aprovada por Fabrício**: teste controlado com uma única carta antes de escalar para as 188 da `ME1` (e depois para as demais coleções) — reduz o tempo de depuração de problemas de permissão de Storage, criação de bucket, upload, MIME type, nomenclatura de arquivo e criação de `card_asset`, mesmo princípio já validado pela abordagem incremental do Incremento 1.

**Estrutura real de `card_asset` confirmada** (consulta a `information_schema.columns`, sem adivinhar): inclui `id` (uuid), `card_id` (uuid), `asset_type_id` (uuid, FK), `source_code` (text), `source_reference` (text) e `storage_path` (text), entre outras colunas ainda não totalmente auditadas neste lote.

**Correção real de nomenclatura, autocorrigida no mesmo ciclo**: a tabela de tipos de ativo é `card_asset_type` (nome físico real, já documentado em `05-modelo-de-dados.md`), não `asset_type` — uma consulta inicial assumiu o nome do modelo conceitual antigo em vez do modelo físico já implementado; corrigida antes de qualquer execução incorreta. Valores reais confirmados: `ARTWORK` ("Ilustração"), `CARD_BACK` ("Verso da Carta"), `CARD_FRONT` ("Frente da Carta") — `CARD_FRONT` será usado para a imagem principal da TCGdex (`image_source_url` aponta para a frente da carta).

> **Diário Técnico — Sprint B3.16 — Incremento 2 iniciado**
> **Objetivo**: definir o fluxo de download de imagens; confirmar as tabelas de apoio (`card_asset`, `card_asset_type`, `storage_bucket`) antes de escrever código.
> **Critério de aceite**: fluxo definido e aprovado; estrutura real de `card_asset`/`card_asset_type` confirmada sem adivinhação.
> **Resultado**: 🟨 Parcial. Fluxo ✅ definido e aprovado por Fabrício. `card_asset` ✅ estrutura parcialmente confirmada. `card_asset_type` ✅ confirmada (`CARD_FRONT` escolhido). 🟨 `storage_bucket` ainda NÃO confirmada — nenhum código escrito nesta revisão.
> **Pendências descobertas**: (1) confirmar a estrutura real de `storage_bucket` (uma consulta assumindo a coluna `bucket_name` falhou — `column "bucket_name" does not exist` — nome real ainda não identificado); (2) só então implementar e testar o download de uma única carta; (3) escalar para as 188 cartas da `ME1` depois do teste controlado validado.

## Sprint B3.17 — Estrutura real de `storage_bucket` confirmada: catálogo interno de metadados, não o bucket físico; três buckets mapeados (`card-front`/`card-back`/`artwork`); primeiro bucket físico criado no Storage

**Estrutura real confirmada** (`information_schema.columns`, sem adivinhar): `id`, `code`, `name`, `description`, `storage_provider`, `bucket_order`, `is_public`, `is_active`, `created_at`, `updated_at`.

**Descoberta arquitetural real**: `storage_bucket` não representa o bucket físico do Supabase Storage — é um catálogo interno. O campo `code` é o identificador usado para localizar o bucket físico correspondente. Três registros reais confirmados, um por `card_asset_type`: `card-front` (Card Front), `card-back` (Card Back), `artwork` (Artwork), todos `storage_provider = SUPABASE`, `is_public = true`, `is_active = true`.

**Verificação real no Supabase Dashboard confirmou que os buckets físicos ainda não existiam** — o catálogo (`storage_bucket`) e o Storage físico são independentes; um não implica o outro. Decisão: criar os buckets físicos um de cada vez, começando apenas por `card-front`, necessário para o teste controlado. Bucket `card-front` **criado e confirmado** (público, sem limite de tamanho de arquivo definido, qualquer MIME type permitido).

> **Diário Técnico — Sprint B3.17 — `storage_bucket` confirmada; primeiro bucket físico criado**
> **Objetivo**: confirmar a estrutura real de `storage_bucket`; criar o bucket físico necessário para o teste controlado.
> **Critério de aceite**: estrutura confirmada sem adivinhar; bucket `card-front` criado e visível no Supabase Storage.
> **Resultado**: 🟩 Concluído. Estrutura confirmada; mapeamento `card_asset_type`↔`storage_bucket` 1:1 confirmado; bucket físico `card-front` criado.
> **Pendências descobertas**: (1) criar os buckets `card-back`/`artwork` quando forem necessários (não bloqueiam o teste controlado); (2) confirmar a estrutura completa de `card_asset` antes de escrever o código de download.

## Sprint B3.18 — Estrutura de `card_asset` confirmada (sem vínculo direto com `card_external_reference`); código do Incremento 2 (teste controlado com uma carta) escrito e DEPLOYADO — execução bloqueada por um terceiro caso real do mesmo gap de GRANT

**Estrutura real de `card_asset` confirmada por completo** (`information_schema.columns`): `id`, `card_id`, `asset_type_id`, `source_code`, `source_reference`, `storage_path`, `external_url`, `mime_type`, `file_extension`, `file_size_bytes`, `width_pixels`, `height_pixels`, `checksum_sha256`, `is_primary`, `asset_order`, `is_active`, `language_id`, `storage_bucket_id`, `created_at`, `updated_at`.

**Descoberta arquitetural real, importante**: `card_asset` **não tem** uma coluna `card_external_reference_id`. A relação final do ativo é `card_id`+`asset_type_id`+`language_id`+`storage_bucket_id` — `card_external_reference` é apenas a **fonte de importação** (de onde vêm `image_source_url`/`external_card_id`), não participa do relacionamento final. Fluxo corrigido: `card_external_reference.image_source_url` → download → Storage → `card_asset` (sem FK para `card_external_reference`).

**Código do Incremento 2 escrito e DEPLOYADO, CONFIRMADO por saída real de terminal** (`index.ts` v2.2.0 + `database.ts`): novas funções `findLanguageByCode`, `findCardAssetTypeByCode`, `findStorageBucketByCode` e `upsertCardAsset` (idempotente via chave natural `card_id`+`asset_type_id`+`language_id`+`storage_bucket_id`, já que nenhuma constraint `UNIQUE` conhecida cobre esse caso). `index.ts` processa a sincronização completa de `card_external_reference` (Incremento 1, inalterado) e, como **teste controlado**, baixa e persiste a imagem apenas da primeira carta da coleção (`set.cards[0]`, `ME1-001`/Bulbasaur): download da imagem em alta resolução (`${image}/high.webp`), cálculo de checksum `SHA-256`, upload ao bucket `card-front`, `UPSERT` em `card_asset`. Copiado ao repositório nesta revisão, mesmo princípio de sempre (deploy confirmado é suficiente).

**Execução real FALHOU com HTTP 500**: log da Edge Function revelou `Error: LANGUAGE_QUERY_FAILED` — terceiro caso real confirmado do mesmo gap de GRANT ausente para `service_role`, já visto em `card_set_external_reference` (Query `250`) e `card_external_reference` (Query `253`), desta vez em `language`. Correção proposta (`GRANT SELECT ON TABLE public.language TO service_role`), **ainda NÃO confirmada executada** ao final desta revisão.

> **Diário Técnico — Sprint B3.18 — Incremento 2 deployado; execução bloqueada**
> **Objetivo**: confirmar estrutura completa de `card_asset`; implementar e deployar o teste controlado do Incremento 2.
> **Critério de aceite**: estrutura confirmada; código deployado; execução real com o registro de `card_asset` da primeira carta confirmado.
> **Resultado**: 🟨 Parcial. `card_asset` ✅ estrutura confirmada por completo (sem `card_external_reference_id`). Código ✅ escrito e deployado (`index.ts` v2.2.0). 🟨 Execução real FALHOU — bloqueada pelo terceiro caso do gap de GRANT (`language`).
> **Pendências descobertas**: (1) confirmar a execução do `GRANT SELECT ON TABLE public.language TO service_role`, proposto mas não confirmado; (2) reexecutar o teste controlado e validar o resultado esperado (`card_asset` criado, imagem visível no bucket `card-front`); (3) só então escalar para as 188 cartas da `ME1`; (4) a auditoria consolidada de GRANTs (adiada no Sprint B3.15) ganha um terceiro caso real, reforçando a prioridade de resolvê-la logo após o Incremento 2.

## Sprint B3.19 — Cadeia real de GRANTs ausentes resolvida (quatro novos casos: `language`, `card_asset_type`, `card_asset`, `expansion`); teste controlado do Incremento 2 CONFIRMADO CONCLUÍDO — primeira imagem real do projeto importada de ponta a ponta

**Quatro novos casos reais do mesmo gap de GRANT** (RLS habilitado não substitui `GRANT` de nível de tabela), cada um descoberto e corrigido individualmente, sempre pelo erro real do PostgreSQL retornado nos logs da Edge Function — nunca adivinhado: `language` (`LANGUAGE_QUERY_FAILED`), `card_asset_type` (`CARD_ASSET_TYPE_QUERY_FAILED`), `card_asset` (`CARD_ASSET_INSERT_FAILED`, precisando de `SELECT`/`INSERT`/`UPDATE` — leitura para a busca de idempotência, escrita para o registro em si) e `expansion` (mesma mensagem `CARD_ASSET_INSERT_FAILED`, mas com causa real distinta: o `INSERT` em `card_asset` aciona uma dependência que consulta `expansion`). Todos corrigidos por uma única nova migration, `254_grant_incremento2_remaining_permissions.sql`.

**Marco real: com os quatro GRANTs corrigidos, o teste controlado (Sprint B3.18) executou de ponta a ponta com sucesso pela primeira vez** — download real da imagem de `ME1-001`/Bulbasaur, upload confirmado no bucket `card-front`, registro criado em `card_asset`, checksum `SHA-256` calculado, URL pública gerada e confirmada (`.../storage/v1/object/public/card-front/me1/001.webp`). Prova real de que a arquitetura completa (Edge Function → Supabase Cloud → PostgreSQL → TCGdex → Supabase Storage) funciona de ponta a ponta.

**Novo padrão real observado, seis casos confirmados no total** (Queries `250`/`253`/`254`): Fabrício voltou a propor consolidar todos os GRANTs pendentes do projeto em um único script futuro (`grants.sql`) — deliberadamente adiado novamente, para depois de concluir a escala do Incremento 2 para a `ME1`.

> **Diário Técnico — Sprint B3.19 — Cadeia de GRANTs resolvida; teste controlado concluído**
> **Objetivo**: eliminar os bloqueios reais de permissão restantes; confirmar o teste controlado do Incremento 2 de ponta a ponta.
> **Critério de aceite**: teste controlado retorna sucesso real, com evidência de imagem no Storage e registro em `card_asset`.
> **Resultado**: 🟩 Concluído. Quatro GRANTs corrigidos (Query `254`); teste controlado com `ME1-001`/Bulbasaur confirmado de ponta a ponta.
> **Pendências descobertas**: (1) escalar de uma carta para as 188 da `ME1` (próximo passo natural); (2) auditoria consolidada de GRANTs (`grants.sql`) segue adiada, agora com seis casos reais acumulados.

## Sprint B3.20 — 🎉 MARCO REAL: Incremento 2 CONCLUÍDO para a `ME1` — 188/188 imagens importadas, 0 falhas

**Refatoração mínima aprovada por Fabrício antes de escalar** ("Vamos ser ágeis na organização. Não quero perder muito tempo! Mas se acha importante, vamos fazer."): lógica de download/checksum/caminho/upload extraída de `index.ts` para um novo `services/storage.ts` — `index.ts` volta a ter responsabilidade única de orquestrador (Convenção #6), sem alterar arquitetura ou banco. Caminho de Storage passou a incluir o idioma (`me1/en/001.webp`), preparando o terreno para uma futura importação em `pt-BR` sem colisão de nome de arquivo.

**Processamento ampliado de uma única carta para as 188 da coleção**, com concorrência controlada em lotes de 5 (`processInBatches`) — evita excesso de requisições simultâneas contra a TCGdex/Storage.

**Bug real de regra de negócio encontrado e corrigido na primeira tentativa em escala**: o código gravava a URL de origem da TCGdex em `external_url` mesmo para ativos já baixados e armazenados internamente (`storage_path` preenchido) — violando uma regra já aplicada pelo banco (esse campo é reservado para ativos não baixados, apenas referenciados externamente). Corrigido para `external_url: null` sempre que o ativo é armazenado internamente, sem alterar mais nada — mesma disciplina de sempre ("corrigindo o código para obedecer ao modelo, sem contornar as regras").

**Pergunta real de idempotência, respondida sem escrever código novo**: reexecutar a função não duplica nem arquivos no Storage (`upsert: true` no upload sobrescreve o mesmo caminho) nem registros em `card_asset` (busca pela chave natural antes de `INSERT`/`UPDATE`). Uma melhoria de performance foi identificada — pular cartas que já têm `card_asset`, evitando novo download/upload desnecessário em reexecuções — mas **deliberadamente adiada por decisão explícita de Fabrício** ("Não vou fazer outro ajuste... Vou executar novamente."), para não interromper o fluxo a um passo da conclusão da `ME1`.

**🎉 Resultado final real, confirmado por saída de terminal**: `success: true`, `version: "2.3.0"`, `external_references: { imported: 188, ignored: 0, total: 188 }`, `images: { imported: 188, failed: 0, total: 188 }`, `failures: []`. **Incremento 2 (Download de Imagens) 100% concluído para a `ME1`** — a coleção tem agora as 188 referências externas e as 188 imagens de frente de carta armazenadas no Supabase Storage, com registros correspondentes em `card_asset`.

`index.ts` (v2.3.0), novo `services/storage.ts` e `services/database.ts` (comentário atualizado) copiados ao repositório.

> **Diário Técnico — Sprint B3.20 — 🎉 Incremento 2 concluído para a `ME1`**
> **Objetivo**: escalar o teste controlado para as 188 cartas da `ME1`; validar 0 falhas.
> **Critério de aceite**: `images.imported = 188`, `images.failed = 0`.
> **Resultado**: 🟩 Concluído. `188/188` imagens importadas, `0` falhas. `188/188` referências externas mantidas. Refatoração (`services/storage.ts`) aplicada sem mudança de comportamento. Bug real de regra de negócio (`external_url`) corrigido.
> **Pendências descobertas**: (1) replicar o Incremento 2 (e reconfirmar o Incremento 1) para `ME2`/`ME2.5`/`ME3`/`ME4`; (2) melhoria de idempotência (pular cartas já importadas) deliberadamente adiada; (3) auditoria consolidada de GRANTs (`grants.sql`) segue adiada, com seis casos reais acumulados; (4) criar os buckets físicos `card-back`/`artwork` quando forem necessários.

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 0.1 | Estrutura inicial do documento, com o padrão geral de importação/sincronização definido em ADR-008. Mecanismos concretos de pipeline ainda pendentes. |
| 0.2 | Adicionada a seção "Importação de Ativos Visuais": o mesmo padrão Import/Synchronization se aplica a imagens e logotipos, com armazenamento no Supabase Storage. Referenciada a infraestrutura física pré-existente (`card_asset`, `card_asset_type`, `asset_source`, `asset_import_run`, `asset_import_failure`, `storage_bucket`) e sinalizada como ponto em aberto se ela se generaliza além de Card. Confirmado que o logotipo da Expansion segue este mesmo padrão. |
| 0.3 | Correção: o logotipo/símbolo pertence ao Set, não à Expansion (ver `04-domain-model.md` e `05-modelo-de-dados.md`). Atualizadas as referências à infraestrutura de ativos visuais e ao ponto em aberto sobre generalização. |
| 0.4 | Adicionada a seção "Primeira Aplicação Concreta — Seed de Card Variant (`860`)": resposta parcial e com escopo restrito ao ponto em aberto "quais fontes externas específicas serão efetivamente integradas" — checklist oficial + campo `variants` da TCGdex (fonte estruturada principal) + Pokémon TCG API (evidência complementar de preço, não fonte isolada) + validação manual para variantes específicas de Card Set (`POKE_BALL_REVERSE`/`MASTER_BALL_REVERSE`) e `PROMO_STAMPED`. Pipeline decidido, ainda não implementado. Ver `04-domain-model.md` e `05-modelo-de-dados.md`, seção Card Variant, para o contexto completo. |
| 0.5 | Cross-referência à seção "Finish/Card Finish" de `04-domain-model.md` corrigida para "Card Variant Type/Card Variant", refletindo a convergência de nomenclatura de ADR-016. |
| 0.6 | **Bloco B (Pipeline de Importação) iniciado.** Adicionada a seção "Arquitetura de Execução — Edge Function `import-card-assets` (Bloco B1)": especificação completa das 14 responsabilidades da função (validação da execução, seleção de cartas por `run_type`, resolução de `card_external_reference`, fontes TCGdex/Pokémon TCG API, download/validação, formato canônico, caminho no Storage, política de `upsert`, ordem de registro em `card_asset`, hash/idempotência via `SHA-256`, tratamento de falhas por `failure_stage`/`error_code`, contadores/status final, segurança, estrutura de arquivos prevista). Adicionada a seção "Roteiro de Implementação Incremental — Bloco B (Sprints B2.1–B2.12)", registrando a mudança de método pedida por Fabrício ("Siga. Vamos ser um pouco mais objetivo nessa fase.") — ciclos curtos Objetivo/Implementar/Validar/Evoluir. Documentado o código proposto do Sprint B2.1 (Edge Function básica, apenas resposta `status: ready`) e o objetivo do Sprint B2.2 — **nenhum dos dois confirmado como executado/deployado nesta revisão**. Atualizada a seção "Em Aberto" com os pontos parcialmente respondidos por esta arquitetura. |
| 0.7 | **Confirmado explicitamente por Fabrício que nada do Sprint B2.1/B2.2 havia sido executado ("Vamos com calma. Eu deveria executar algum desses códigos? Até agora não executei nenhum código.") — disciplina de execução refinada para código: um passo por vez, com validação antes de prosseguir, mesmo padrão já usado para SQL.** Novo **Sprint B2.0 — Preparar o ambiente local**, inserido antes do B2.1: até este ponto, 100% do trabalho de banco foi feito pelo painel web do Supabase, suficiente para SQL mas não para Edge Functions; migração para desenvolvimento local **CONFIRMADA e concluída nesta revisão**, com evidência real de terminal em cada etapa — VS Code e Node.js `23.6.0` já instalados; tentativa de instalar a Supabase CLI via `winget` falhou (pacote ausente no repositório); Scoop também não instalado; decisão final de usar `npx supabase` sem instalação global; pasta raiz local `C:\Users\Administrador\Project-Mimikyu` criada; `npx supabase --version` executado com sucesso, confirmando Supabase CLI `2.109.1` funcional. **Nota não resolvida**: ainda não confirmado se essa pasta local corresponde a um clone do repositório GitHub oficial `fabriciosouzasales/project-mimikyu`, nem como a estrutura de pastas proposta pela sessão pareada (`database/migrations`, `database/seeds`, `supabase/functions`) se concilia com a estrutura já real e documentada em `database/README.md` (`schema`/`functions`/`migrations`/`seeds`/`validations`/`reference-data`/`diagrams`). Sprint B2.2 recebeu código refinado (payload `run_id`, `createClient`, consulta a `asset_import_run`, tratamento de erro) e a estrutura de arquivos ganhou `deno.json` — **status inalterado: proposto, não executado**. Atualizada a seção "Em Aberto" com os dois novos pontos (convenção de pasta de Edge Function + relação pasta local/repositório oficial). |
| 0.8 | **Sprint B2.0 CONFIRMADO CONCLUÍDO integralmente**: `npx supabase init` (gera `supabase/config.toml`/`functions/`/`migrations/`/`seed.sql`), `npx supabase login`, obtenção do Project Reference (não sigiloso, ao contrário de Database Password/Service Role Key/Anon Key/Connection String — explicitamente não solicitados) e `npx supabase link --project-ref <ref>` — todos **confirmados por saída real de terminal** ("Finished supabase init."/"Finished supabase login."/"Finished supabase link."). Novo registro arquitetural: dois ambientes complementares a partir de agora — Painel Web (administração/SQL Editor/Storage/Auth) e Projeto Local (Edge Functions/scripts/versionamento). Nota não resolvida sobre pasta local vs. repositório GitHub oficial reafirmada (proposta de reorganização repetida pela sessão pareada, ainda divergente da estrutura real de `database/`). **Sprint B2.1 avançou de "proposto" para "esqueleto gerado via CLI, confirmado"**: `npx supabase functions new import-card-assets` executado (confirmado), resposta `Yes` ao prompt de configuração Deno do VS Code (confirmado) — mas **nenhuma lógica própria foi escrita, testada localmente, publicada ou validada remotamente ainda**. Nova disciplina adotada: `Criar função → Executar localmente → Publicar → Validar remotamente → Evoluir`. Estrutura interna de cada Edge Function refinada e adotada como padrão (`config.ts`/`types.ts`/`services/{database,storage,importer}.ts`/`sources/{source-adapter,tcgdex,pokemon-api}.ts`/`utils/{hash,image,paths}.ts`), substituindo a estrutura provisória da seção "Arquitetura de Execução"; a maioria dos arquivos permanece vazia. Mencionadas, sem decisão, futuras Edge Functions (`sync-card-catalog`, `reprocess-failures`, `cleanup-storage`) — backlog, não roteiro confirmado. |
| 0.9 | **Marco: primeiro deploy real e primeira invocação remota confirmada de uma Edge Function no Project Mimikyu (Sprints B2.1/B2.2, CONFIRMADOS CONCLUÍDOS).** Descoberta técnica: a CLI `2.109.1` gera Edge Functions no novo padrão `withSupabase(...)` (injeta `ctx.supabase`/`ctx.supabaseAdmin`/autenticação/contexto), substituindo o padrão `serve()` assumido nas revisões `0.6`-`0.8` — todo código anterior baseado em `serve()`/`createClient` manual marcado **obsoleto**, preservado apenas como registro histórico. Cinco convenções permanentes declaradas para Edge Functions: nunca criar arquivos "na mão" (sempre via `supabase functions new`); nunca alterar o template oficial da CLI sem necessidade; responsabilidade única; execução restrita por padrão (`auth: ["secret"]`); "nunca avançar sem validar" aplicado a critérios de aceite por sprint. **Roteiro renumerado e consolidado**: de 13 sprints (`B2.0`-`B2.12`) para 9 (`B2.0`-`B2.8`) — comparação lado a lado registrada explicitamente, no mesmo espírito da correção de roteiro feita em `05-modelo-de-dados.md` após o incidente de confiança da revisão `0.49`. Primeira versão real de `import-card-assets` escrita, publicada (`npx supabase functions deploy`) e invocada remotamente com sucesso via Secret Key — tudo **confirmado por saída real de terminal**, incluindo a remoção da chave da sessão após o teste. **Sprint B2.3 (Integração com Banco)**: interface mudou de `run_id` (UUID) para `run_code` (identificador amigável, já previsto desde a Query `220`); código real publicado e confirmado via deploy, mas **ainda não invocado com uma execução real** — teste pendente. Código copiado para o repositório oficial em `supabase/functions/import-card-assets/index.ts` (primeira vez que código de Edge Function é versionado no repositório, mesmo princípio de "copiar apenas após confirmação" já usado em `database/`). Seção "Em Aberto" atualizada: convenção de pasta de Edge Function parcialmente resolvida. |
| 0.10 | **Primeiro `asset_import_run` real criado (valores reais do catálogo, não inventados) e primeiro bug real de produção encontrado e corrigido: `service_role` sem `GRANT SELECT` em `asset_import_run` (erro `42501`), corrigido ad hoc.** Confirmado que o `run_code` é gerado automaticamente pelo trigger da Query `221` no formato exato desenhado na Query `220` — primeira validação em dado real. Corrigida a seção "Segurança" (item 13): `ctx.supabaseAdmin` respeita GRANTs do PostgreSQL, não os ignora. Nova pendência registrada, não formalizada: migrations dedicadas para GRANTs de Edge Functions (exemplo citado: faixa `99x`). Evidência nova (não solicitada, encontrada incidentalmente): `card_set.code = 'ME0'` ainda existe fisicamente, corroborando a pendência já registrada da migração `ME0`→`MEP`/`MEE`. Um erro de digitação (`IRUN-` em vez de `RUN-`) confirmou o caminho de erro `IMPORT_RUN_NOT_FOUND` funcionando corretamente. **Sprint B2.3 permanece EM ANDAMENTO, não concluído**: uma segunda ocorrência de HTTP 404, após aparente correção do `run_code`, ficou sem causa identificada ao final desta revisão — consulta de diagnóstico preparada, não executada. Prévia (não oficial) de sprints futuros registrada (`B2.4` Ler `card_set` → `B2.9` Criar `card_asset`), explicitamente não promovida a atualização do roteiro consolidado da revisão `0.9`, para não repetir o padrão do incidente de confiança da revisão `0.49` de `05-modelo-de-dados.md`. |
| 0.11 | **Sprint B2.3 — CONFIRMADO CONCLUÍDO.** Causa real do segundo HTTP 404 identificada: `run_code` armazenado com 21 caracteres vs. 22 enviados (dígito extra introduzido em retranscrição manual) — corrigida a chamada, sucesso confirmado. Nova convenção de documentação formalizada e adotada oficialmente: **"Diário Técnico"** (Objetivo/Critério de Aceite/Resultado/Pendências Descobertas ao final de cada sprint), aplicada retroativamente ao Sprint B2.3. **Sprint B2.4 (Descoberta das Cartas) CONFIRMADO CONCLUÍDO**: escopo ampliado para já incluir listagem de `card` (fusão explícita de duas sprints do roteiro anterior); refatoração em módulos (`services/database.ts`/`types.ts`/`config.ts`) foi proposta e aprovada, mas **não chegou a ser aplicada nesta revisão** — o código publicado e testado permanece em um único `index.ts` (v1.2.0), registrado honestamente como pendência real; teste real confirmado com `card_set` `ME0`/"Black Star Promos" e `card_count: 0` (comportamento correto — o Set de teste ainda não tem cartas cadastradas). Roteiro vigente atualizado (B2.3/B2.4 ✅), com nota explicando que o Diário Técnico de cada sprint passa a ser a fonte de verdade mais granular. Sprint B2.5 (Integração com TCGdex) anunciado, sem código ainda. Código v1.2.0 (confirmado executado) copiado para `supabase/functions/import-card-assets/index.ts`. |
| 0.12 | **Sprint B2.4.1 — Refatoração para Services, proposta antes da primeira integração externa.** Fabrício formalizou a decisão de separar `index.ts` em camadas (`Database Service`/`TCGDEX Service`/`Storage Service`) para permitir trocar de fonte externa (ex. TCGdex → Pokémon TCG API) sem alterar o fluxo principal — justificativa explícita: "refatoração pequena, feita no momento certo, antes que a função cresça demais". Código real recebido nesta revisão: `types.ts` (tipos `RequestBody`/`ImportRun`/`CardSet`/`Card`), `services/database.ts` (`findImportRun`/`findCardSet`/`listCards`, mesmas consultas do v1.2.0 extraídas para funções próprias) e `index.ts` v1.2.1 (usa os services, mesmo comportamento e mesmo formato de resposta do v1.2.0). **Deploy ainda não confirmado nesta revisão** — instrução de deploy (`npx supabase functions deploy import-card-assets`) e resultado esperado (`version: "1.2.1"`, mesmo `card_set`/`card_count` do teste anterior) foram fornecidos, mas a execução real e a confirmação do retorno ainda não aconteceram; código **não copiado ao repositório ainda**, seguindo o mesmo princípio de "copiar apenas após confirmação" já usado em todo o projeto. **Sprint B2.5 dividido em duas sprints mais granulares**: `B2.5A` (consultar a TCGdex, receber o JSON, encerrar — sem download/Storage/banco) e `B2.5B` (a partir do JSON validado: extrair URL da imagem → download → validar imagem). Roteiro vigente atualizado de acordo; sinalizado como ponto em aberto, não resolvido unilateralmente, que o escopo de `B2.5B` (download + validação de imagem) parece sobrepor o que o roteiro consolidado da revisão `0.9` já previa como sprint `B2.6` (Download) — Fabrício precisa decidir se `B2.6` é absorvido por `B2.5B` ou se os dois seguem distintos. |
| 0.13 | **Sprint B2.4.1 — CONFIRMADO CONCLUÍDO.** Deploy e reteste reais confirmados: `version: "1.2.1"`, mesmo `run`/`card_set` do Sprint B2.4, comportamento observável idêntico ao v1.2.0. Nova disciplina de trabalho para código, declarada nesta revisão: criar pasta/arquivo → validar estrutura → escrever código → testar, um arquivo por vez (espelha o ciclo `Migration → Executar → Validar` do banco), motivada por Fabrício ter perguntado como criar a nova estrutura no VS Code. Código real de `types.ts`, `services/database.ts` e `index.ts` (v1.2.1) copiado ao repositório pela primeira vez, em três arquivos. **Novo princípio de arquitetura declarado para todas as Edge Functions futuras**: `index.ts` tem responsabilidade única de orquestrar o fluxo — não conhece SQL/PostgreSQL/TCGdex diretamente, apenas coordena chamadas a serviços especializados; soma-se às cinco convenções já declaradas nos Sprints B2.1/B2.2. Roteiro vigente atualizado (`B2.4.1` ✅). A nota sobre possível sobreposição entre `B2.5B` e `B2.6`, registrada na revisão `0.12`, permanece em aberto — não resolvida nesta revisão. |
| 0.14 | **Sprint B2.5 replanejada: passa a começar pelo `card_set`, não pelas cartas — nova lacuna de modelagem descoberta e resolvida por uma extensão do Bloco A, não deste documento.** Antes de consultar a TCGdex por uma carta, o pipeline precisa saber qual identificador a TCGdex usa para o `card_set` — mapeamento que não existia em nenhuma tabela. Em vez de improvisar isso dentro da Edge Function, nova entidade `card_set_external_reference` criada (`240` CONFIRMADA EXECUTADA) — documentada em `05-modelo-de-dados.md`, não duplicada aqui (ver seção "Card Set External Reference" naquele documento). Fluxo final da integração: `asset_import_run` → `card_set` → `card_set_external_reference` → `TCGdex`. **Sprint B2.5A em andamento**: `services/tcgdex.ts` criado com `findTcgDexSet(languageCode, externalSetId)` (consulta `GET https://api.tcgdex.net/v2/{idioma}/sets/{set_id}`, trata `404` como "não encontrado", lança erro para outras falhas), validado sem erros no VS Code — mas **ainda não integrado a `index.ts`, não deployado, sem chamada real testada**; `services/tcgdex.ts` ainda não copiado ao repositório, seguindo o mesmo princípio de "copiar apenas após confirmação". |
| 0.15 | **Escopo final de B2.5A definido: `run_code` → `asset_import_run` → `card_set` → `card_set_external_reference` → (se existir) TCGdex → JSON do Set, com `NO_EXTERNAL_SET_MAPPING` para Sets sem referência externa ativa (regra genérica, sem caso especial para `ME0`).** Episódio real registrado: um mapeamento de teste incorreto (`ME0`→`sv10pt5`) foi inserido e corrigido durante a validação da Query `241` de `05-modelo-de-dados.md` (detalhado lá, não duplicado aqui) — levou à decisão de adiar a Seed `910` até que os `external_set_id` reais sejam descobertos via chamada real à TCGdex, nunca presumidos. Nova diretriz de metodologia declarada: a partir de agora, evitar criar novas tabelas a menos que absolutamente necessário, voltando o foco para código/execução real do pipeline. `services/tcgdex.ts` continua sem deploy, sem integração a `index.ts`/`types.ts`, e sem chamada real testada. |
| 0.16 | **`findCardSetExternalReference` adicionado a `services/database.ts`; `services/tcgdex.ts` reescrito (`getSet` substitui `findTcgDexSet`, mudança real de comportamento no tratamento de 404); rascunho v1.3.0 de `index.ts` escrito — nada disso deployado ou testado nesta revisão.** A sprint pivotou de "deployar e validar `NO_EXTERNAL_SET_MAPPING`" para "descobrir os `external_set_id` reais da TCGdex primeiro", ao constatar que a Edge Function nunca conseguiria consultar a TCGdex sem esses identificadores. Nomes oficiais em inglês de `ME1`-`ME5` aprendidos (novo dado de domínio, não confirmado contra `card_set.name`); `ME5` mencionado pela primeira vez nesta revisão, sem confirmação de existência real no banco. **Três propostas sucessivas para descobrir os IDs, registradas por transparência**: (1) preencher manualmente, descartada; (2) nova Edge Function `sync-card-sets`, aprovada e depois reconsiderada na mesma revisão; (3) **decisão final**: script administrativo standalone `scripts/discover-tcgdex-sets.ts` (Deno, fora do runtime da Edge Function) — código escrito, mas criado no local errado (dentro de `supabase/functions/import-card-assets/scripts/`) e ainda não executado. Duas novas diretrizes de metodologia anunciadas (cada sprint entrega uma capacidade real do pipeline; ciclos mais curtos de adicionar/deployar/validar/avançar) e um reframing informal do roteiro em "Blocos funcionais" — nenhum dos dois promovido ao "Roteiro vigente" oficial, mesma cautela já aplicada a prévias anteriores. |
| 0.17 | **Marco: primeira comunicação externa real e bem-sucedida do Bloco B — `external_set_id` reais da TCGdex descobertos para `ME0`-`ME5` (`mee`/`me01`/`me02`/`me02.5`/`me03`/`me04`/`me05`).** Ambiente corrigido antes disso: Deno CLI de fato instalado via `winget` (a extensão do VS Code só dava suporte ao editor, não instalava o executável), confirmado por saída real de terminal; script de descoberta rodado com sucesso a partir da raiz do projeto, resolvendo a pendência de localização incorreta da revisão anterior. **Nova decisão de negócio em aberto, não resolvida unilateralmente**: `mee` = "Mega Evolution Energy" na TCGdex, possivelmente um Set diferente do `ME0` interno (todas as promos da expansão, não só Energias) — cross-referenciada com a pendência "escopo `ENERGY`" já registrada em ciclos muito anteriores. **Correção arquitetural real**: `card_set_external_reference` é uma tabela de configuração, resolvida uma vez por Set; o primeiro objetivo real da Edge Function passa a ser importar o catálogo oficial de cartas (via `card_external_reference`), não baixar imagens — fluxo revisado documentado. Os três arquivos completos prometidos (`database.ts`/`tcgdex.ts`/`index.ts` v1.3.0) não foram entregues nesta revisão; Seed `910` continua bloqueada pela decisão sobre `ME0`. |
| 0.18 | **Decisão de arquitetura declarada definitiva pela sessão pareada, formalizada em `ADR-017-two-function-import-pipeline.md`: o pipeline de importação passa a ser dividido em duas Edge Functions.** `sync-card-set` (nova, ainda não criada): TCGdex → lista completa de cartas do Set → grava `card_external_reference`; nunca baixa imagem nem toca Storage. `import-card-assets` (papel redefinido): consome `card_external_reference` já sincronizada → download → Storage → `card_asset`; deixa de descobrir cartas por conta própria. Motivação dupla: (1) correção de ordem do pipeline (`SET → CATÁLOGO → REFERÊNCIAS → IMAGENS`, não `SET → IMAGENS` direto); (2) uma única função fazendo tudo cresceria descontroladamente em escala (exemplo: `ME1` com 188 cartas). Arquitetura interna em camadas declarada definitiva para as duas funções: `index.ts` (orquestrador) → `database.ts` (único acesso ao PostgreSQL) → `tcgdex.ts` (único ponto de `fetch()` à TCGdex, reescrito como classe `TcgdexClient`) → API REST da TCGdex — estende a Convenção #6. Código de `tcgdex.ts` (`TcgdexClient` com `getSet`/`getCardsBySet`/`getCard`) colado verbatim, **não deployado, não copiado ao repositório**. Endpoint `GET /sets/{id}/cards` assumido no código, sem confirmação por chamada real — novo item em "Em Aberto". Nenhuma mudança de schema necessária (reafirmado pela sessão pareada). Próximo passo confirmado: Sprint B3 implementa `sync-card-set` primeiro, isoladamente. Mapeamento entre o roteiro vigente (`B2.5B`–`B2.9`) e a nova arquitetura ainda não detalhado por Fabrício — tabela "Roteiro vigente" mantida sem reescrita, mesma cautela do incidente de confiança da revisão `0.49`. |
| 0.19 | **Continuação do Sprint B3: nova disciplina de trabalho ("uma camada por vez", tratar o repositório como software de produção) e revisão técnica de `tcgdex.ts`/`index.ts` — ainda sem deploy real.** Pipeline de Assets detalhado (`SELECT card_external_reference WHERE image ainda não existe → download → Storage → card_asset`), reafirmando sem alterar o já registrado na revisão `0.18`; nenhuma mudança de schema necessária, reafirmado outra vez. **Discrepância real sinalizada, não resolvida**: o plano anunciava `sync-card-set/index.ts` como pasta própria da nova função, mas a implementação real (captura de VS Code) mostra `tcgdex.ts` sendo construído dentro de `import-card-assets/services/`, a estrutura já existente — não fica claro se será compartilhado com a futura `sync-card-set` ou se a criação da função própria foi adiada; a sessão pareada aprovou a estrutura atual sem esclarecer o ponto. `tcgdex.ts` revisado tecnicamente e aprovado (URL base extraída para `BASE_URL`, retornos tipados como `Promise<Record<string, unknown>>`), versão melhorada colada verbatim — **não deployada, não copiada ao repositório**; endpoint `GET /sets/{id}/cards` continua sem confirmação real. `index.ts` revisado com nota 9,5/10 (dois pontos de melhoria: evitar `select("*")`, extrair consultas para `database.ts`), mas código completo não colado nesta revisão. |
| 0.20 | **Marco real: Query `910` (Seed Card Set External Reference) CONFIRMADA EXECUTADA (parcial) — detalhamento completo em `05-modelo-de-dados.md`.** `ME1`–`ME4`/`ME2.5` mapeados e confirmados por consulta real; `ME0` excluído (decisão pendente); `ME5` explicado (`card_set` ainda não cadastrado). Revisão final de código concluída para os três arquivos em desenvolvimento: `index.ts` (v1.2.1 já deployado) aprovado como está, com um ponto de atenção não bloqueante (a função retorna todas as cartas do Set — aceitável agora, revisar quando o catálogo crescer); `tcgdex.ts` mantém aprovação anterior; `scripts/discover-tcgdex-sets.ts` aprovado com duas melhorias (tipagem via interface `TcgdexSet`, filtro por `set.id.startsWith("me")` em vez de nome) — código final colado verbatim pela primeira vez, mas esta versão específica **não foi reexecutada** (a execução confirmada no Sprint B2.5A foi de uma versão anterior); nada copiado ao repositório. Nova disciplina: nenhuma alteração direta em `index.ts` até `database.ts` estar consolidado. Versão completa reescrita de `database.ts` (agora com `findCardSetExternalReference`) colada verbatim — **rascunho, ainda não deployado nem testado, não copiado ao repositório**. |
| 0.21 | **Sprint B3.2: primeira tentativa real de deploy da v1.3.0 (primeira chamada real Supabase→TCGdex) — FALHOU, com erro real de bundling diagnosticado; correção escrita, deploy de sucesso ainda NÃO confirmado.** `index.ts` v1.3.0 (`findImportRun`→`findCardSet`→`findCardSetExternalReference`→`TcgdexClient.getSet()`) colado verbatim. Deploy real retornou `Unexpected deploy status 500`: import relativo `@supabase/supabase-js` não mapeado em `deno.json`, dentro de `database.ts`. Causa raiz confirmada por inspeção real do `deno.json` (sem entrada para esse pacote) — erro reconhecido como próprio pela sessão pareada. Correção: remover o import de `SupabaseClient`, tipar `supabase: any` nas quatro funções (tipagem forte adiada deliberadamente para depois que a arquitetura estabilizar, via `database.types.ts` gerado por `supabase gen types typescript`). Segunda camada de debugging real: `deno check` rodado da raiz do projeto deu erros enganosos por ignorar o `deno.json` da função — comando correto é `cd supabase/functions/import-card-assets && deno check index.ts`; saída também sugeriu que `database.ts` local ainda não tinha sido atualizado com a correção. Nenhum arquivo copiado ao repositório nesta revisão. |
| 0.22 | **Sprint B3.3 — Marco real: primeiro deploy confirmado com sucesso de `index.ts` v1.3.0 + `database.ts` + `tcgdex.ts` juntos; os três arquivos copiados ao repositório pela primeira vez (`tcgdex.ts` nunca havia sido copiado antes).** Nova Convenção #7 declarada e confirmada eficaz: `deno check index.ts` de dentro da pasta da função, depois `npx supabase functions deploy <nome>` da raiz do projeto — resolve a confusão de contexto diagnosticada no Sprint B3.2. `deno check` real: sem erros. Deploy real: `Deployed Functions on project ...: import-card-assets`, confirmado por terminal. **Deploy confirmado ≠ invocação de ponta a ponta confirmada**: três tentativas de chamar a função, nenhuma retornou resposta real da TCGdex — (1) erro de sintaxe PowerShell (Hashtable, não bug da função); (2) script auxiliar ainda não criado; (3) HTTP 401 Unauthorized real, causado pelo uso de uma API Key "Secret Keys" em vez do JWT `service_role` exigido por `auth: ["secret"]`. Decisão recomendada, ainda não aplicada: remover `auth: ["secret"]` durante o desenvolvimento, reativar depois — arquivo copiado ao repositório ainda mantém a autenticação restrita. Roteiro vigente (`B2.5A`) atualizado para refletir o deploy confirmado sem invocação confirmada. |
| 0.23 | **Sprint B3.4 — Diagnóstico definitivo do HTTP 401.** **Correção ao diagnóstico da revisão `0.22`**: a causa não era o tipo de chave usada — mesmo trocando para o header/formato correto (`apikey`) e confirmando `verify_jwt = false` em `supabase/config.toml`, o reteste real continuou retornando 401. Causa raiz real, confirmada a partir dos arquivos reais (`index.ts`+`deno.json`): a combinação `@supabase/server@^1` + `withSupabase({ auth: ["secret"] })` usa um mecanismo de autenticação interno específico da biblioteca, não satisfeito por uma Secret Key válida via `Authorization` ou `apikey` — reconhecido como suposição própria incorreta. Duas hipóteses reais testadas e descartadas por evidência antes de chegar a essa conclusão (registradas por transparência, não silenciadas). Correção final proposta: `index.ts` v1.3.1, removendo `{ auth: ["secret"] }` de `withSupabase(...)` durante o desenvolvimento — colado verbatim, **ainda NÃO deployado nem testado nesta revisão**. Fragmento de `config.toml` (`verify_jwt = false`) confirmado real, mas arquivo completo não recebido — não copiado ao repositório. |
| 0.24 | **Sprint B3.5 — Correção real à recomendação da revisão `0.23`: remover `auth: ["secret"]` sozinho NÃO resolve o HTTP 401.** Fabrício aplicou a correção v1.3.1 e testou de ponta a ponta — 401 persistiu. Duas novas hipóteses testadas e descartadas por evidência real: nome/tipo da Secret Key (confirmada `default` por print de tela) e roteamento até o Edge Runtime (confirmado via headers `x-deno-execution-id`/`x-sb-edge-region` usando `Invoke-WebRequest`). Achado independente: parte dos 401 anteriores vinha de um bug real de metodologia de teste — comandos PowerShell executados com o placeholder literal `"SUA_SECRET_KEY"`, nunca substituído pela chave real; corrigido, mas o 401 persistiu mesmo com a chave real. Causa raiz continua desconhecida. Teste de isolamento definitivo proposto — substituir `index.ts` de `import-card-assets` por um `Deno.serve()` mínimo, sem `withSupabase` — **detalhado, não executado nesta revisão**. `npx supabase functions list`/`--version` confirmam função `ACTIVE` e CLI `2.109.1`; tentativa de criar Edge Function `ping` separada falhou por arquivo inexistente (lacuna de execução, não bug). Nenhum arquivo copiado ao repositório — deploy da versão modificada não tem confirmação de que o Dashboard servia a versão mais recente. |
| 0.25 | **Sprint B3.6 — Marco real: HTTP 401 definitivamente eliminado.** O teste mínimo do Sprint B3.5 confirmou o problema em `withSupabase`/`@supabase/server`; biblioteca abandonada por completo (decisão concordada por Fabrício), substituída por `Deno.serve()` + `@supabase/supabase-js` com cliente criado manualmente via `SUPABASE_SERVICE_ROLE_KEY`. `index.ts` v2.0.0, `deno.json` reescritos; `database.ts`/`tcgdex.ts` inalterados. Deploy real confirmado por terminal; teste real sem headers de autenticação retornou HTTP 500 em vez de 401 — 401 eliminado, confirmado. Causa do 500 diagnosticada com precisão via corpo real da resposta (`Invoke-WebRequest`): `GRANT` ausente em `card_set_external_reference` para `service_role` (RLS habilitado não substitui `GRANT` de tabela). Confirmado por consulta real a `information_schema.role_table_grants`; corrigido pela migration real `250` (`GRANT SELECT/INSERT/UPDATE/DELETE` + `GRANT USAGE ON SCHEMA public`), aplicada via `npx supabase db push`, reconfirmada pela mesma consulta. Nova pendência: possível mesmo gap de `GRANT` em outras tabelas do projeto — auditoria proposta, não executada. Resposta final `success: true`/`tcgdex_set` ainda não explicitamente confirmada nesta revisão. `index.ts` (v2.0.0) e `deno.json` copiados ao repositório pela primeira vez; nova migration `database/migrations/250_grant_card_set_external_reference_permissions.sql` criada. |
| 0.26 | **Sprint B3.7 — Progresso real além do GRANT (HTTP 404, lógica de aplicação) e resolução definitiva da pendência `ME0`↔`mee`.** Novo teste real avançou para HTTP 404 (`CARD_SET_EXTERNAL_REFERENCE_NOT_FOUND`), confirmando autenticação/permissões/execução/acesso ao banco todos funcionando — só faltava um dado. Diagnóstico real: a execução de teste apontava para `ME0`, sem mapeamento em `card_set_external_reference` (conforme já documentado na Query `910`). Fabrício esclareceu, com conhecimento de domínio, que `ME0` (promocionais de Mega Evolução) e `mee` (Energias de Mega Evolução, TCGdex) são coleções diferentes, sem relação — pendência aberta desde a revisão `0.17` finalmente resolvida. Decisão: remover `ME0` de `card_set` por completo. Pré-checagem real de dependências confirmada (`card`: 0, `asset_import_run`: 1, `card_set_external_reference`: 0); migration real `251_remove_me0` criada e aplicada via `npx supabase db push`; validação pós-execução confirmada por Fabrício. Detalhamento completo em `05-modelo-de-dados.md`, "Migration 251". Nova proposta (não implementada): validar integração externa antes de criar `asset_import_run`. Resposta final `success: true`/`tcgdex_set` ainda pendente — próximo passo é criar um novo `asset_import_run` para `ME1`. |
| 0.27 | **Sprint B3.8 — 🎉 MARCO REAL: primeira resposta de ponta a ponta da TCGdex confirmada, objetivo do Sprint B3 desde a revisão `0.18`.** `asset_import_run` real criado para `ME1` (migration `252`, primeira tentativa FALHOU por `run_type` obrigatório não preenchido, corrigida após confirmação real do `CHECK` via `pg_constraint` — valores reconfirmam a Query `220`; `run_code` passou a ser gerado pelo `DEFAULT` da tabela, não mais fixado manualmente). Edge Function reinvocada com o novo `run_code` — resposta real confirmada: `success: true`, Set `me01` "Mega Evolution", `188` cartas, logo/símbolo/metadados presentes. Pipeline Supabase↔Edge Function↔TCGdex validado de ponta a ponta pela primeira vez. Três propostas reais, todas explicitamente adiadas: Stored Procedure de orquestração (`start_asset_import` etc., adiada para depois da persistência de cartas); migração de `run_type`/`status`/`execution_context` para `ENUM` nativo; reestruturação de pastas da Edge Function em camadas (`application`/`infrastructure`/`domain`). "Roteiro vigente" (`B2.5A`) atualizado para `CONCLUÍDO`. |
| 0.28 | **Sprint B3.9 — Estrutura real de carta da TCGdex confirmada (`id`/`localId`/`name`/`image`, sem mecânica de jogo, embutida em `getSet()`); segundo episódio real de perda de contexto arquitetural da sessão pareada, autocorrigido após intervenção direta de Fabrício; fluxo de persistência de `card`/`card_external_reference` realinhado à arquitetura já existente.** A sessão pareada chegou a propor uma arquitetura que contrariava decisões já consolidadas (`card_external_reference` com `card_id = NULL` como etapa intermediária; nova Edge Function `import-card-metadata`; novas tabelas `attacks`/`abilities`/`weaknesses` — contrariando `ADR-012` e o Catálogo Editorial já encerrado) e demonstrou incerteza sobre tabelas já existentes há dezenas de batches. Fabrício interrompeu com uma captura real do Table Editor; a sessão pareada reconheceu o erro explicitamente e refez um "inventário arquitetural" real das três tabelas centrais (`card`/`card_external_reference`/`card_asset`), confirmando a estrutura já documentada neste repositório. Fluxo corrigido, real mas ainda não implementado: `asset_import_run`→`card_set_external_reference`→TCGdex→`card`→`card_external_reference`→(`card_asset` depois). **⚠️ Discrepância sinalizada, NÃO resolvida unilateralmente**: proposta de um novo `docs/architecture.md` como "especificação oficial", aparentemente sem ciência da documentação já existente neste repositório (`00`-`07`, ADRs, STDs) — nenhum arquivo criado, decisão explícita de Fabrício pendente. |
| 0.29 | **Sprint B3.10 — Reconfirmação da arquitetura de fluxo/responsabilidades das Edge Functions; episódio real de perda de foco operacional, corrigido por Fabrício ("Não quero trabalhar para importar 1 imagem apenas [...] Precisamos finalizar o trabalho do catálogo editorial"); novo faseamento `FASE 1-6`/backlog `Sprint 1-2` proposto pela sessão pareada, ainda não reconciliado com o "Roteiro vigente" `B2.x`/`B3.x`.** Autocorreção real no mesmo ciclo: a separação inicial FASE 3 (catálogo sem imagens)/FASE 4 (imagens) foi reconhecida pela própria sessão pareada como "uma interpretação incorreta" — a Query `880` (incluindo `card_asset`) permanece o ponto final real do Catálogo Editorial, consistente com o que já estava documentado. Checklist real de seis pontos pré-`880` registrado (importação idempotente de `card`, criação de `card_external_reference`, decisão sobre endpoint de carta individual, mapeamentos editoriais, validação de infraestrutura de ativos, convenção de Storage — este último já decidido em revisão anterior, discrepância sinalizada). **⚠️ Nova discrepância sinalizada, NÃO resolvida unilateralmente**: proposta de `docs/adr/` com ADRs `001`-`005`, colidindo diretamente com os 17 ADRs reais já aprovados neste repositório (`ADR-001` a `ADR-017`). Nova divergência de nomenclatura sinalizada entre `download-card-assets` (usado nesta revisão) e `sync-card-set` (nome real em `ADR-017`). Nenhum código ou SQL executado nesta revisão — todo o conteúdo é planejamento/reconciliação. |
| 0.30 | **Sprint B3.11 — Escopo real expandido para 5 coleções (`ME1`/`ME2`/`ME2.5`/`ME3`/`ME4`, decisão explícita de Fabrício); quarto episódio real de perda de contexto, desta vez contido antes de qualquer execução: `card`/`card_variant` já tinham 859/1.555 registros reais, marco fechado há dezenas de batches (Query `840`/`860`/`960`), que a sessão pareada momentaneamente tratou como vazias.** Correção arquitetural real e importante: o fluxo de persistência passa a **consultar** `card` (nunca inserir) — supera o fluxo do Sprint B3.9, que não deixava claro se `card` seria criada. Duas queries de auditoria real executadas (primeira versão com erro real de colunas/`JOIN` inexistentes, capturado por Fabrício; versão corrigida confirmou totais e estrutura de colunas sem divergência da documentação). Nova reformulação de roadmap `FASE 1-4`/três Entregas, substituindo a `FASE 1-6` do Sprint B3.10 apenas um sprint depois — terceiro framing paralelo, não reconciliado com o "Roteiro vigente" `B2.x`/`B3.x`. Nenhum código ou SQL executado nesta revisão. |
| 0.31 | **Sprint B3.12 — Dependências de `card_external_reference` auditadas (`asset_source`: 3 provedores; `card_set_external_reference`: 5 coleções mapeadas; `card_external_reference`: 0 registros, ponto de partida real); chave de correspondência `card`↔TCGdex validada (`card_set_id`+`collector_number`=`localId`, sem necessidade de correspondência por nome); plano do próximo incremento travado (188 `UPSERT`s em `card_external_reference` para a `ME1`), ainda não codificado.** Resolvida por escopo a pendência sobre o endpoint de carta individual (`getCard`) — não necessário, já que `rarity`/`category`/`collector_total` já existem em `card`. Nova disciplina adotada: um incremento por vez, cada um com evidência mensurável no banco. **A partir desta revisão, por pedido explícito de Fabrício, a documentação registra apenas o estado final e as decisões confirmadas — não mais o histórico passo a passo de tentativas da sessão pareada.** |
| 0.32 | **Sprint B3.13 — Estrutura de `card_external_reference` reconfirmada (`UNIQUE`/`CHECK` sem divergência); código do Incremento 1 finalizado (`index.ts` v2.1.0 + `database.ts`: `listCardsMap`, `upsertCardExternalReference`), usando lookup em memória (`Map`) em vez de consulta por carta.** Deploy/execução reais NÃO confirmados nesta revisão — código não copiado ao repositório, mesmo princípio de sempre. Ajuste de performance (`UPSERT` em lote) identificado e adiado para um incremento seguinte. |
| 0.33 | Plano de validação do Incremento 1 definido (5 checagens no banco). Execução bloqueada por problema real de ambiente local (Supabase CLI indisponível no terminal); resolvido nesta revisão via `npm install -g supabase` (verificação final pendente). **⚠️ Ponto em aberto**: não confirmado se a validação rodará contra o ambiente local ou o projeto hospedado real. |
| 0.34 | **Sprint B3.14 — Resolvido: banco é o Supabase Cloud, não local (elimina necessidade de Docker/WSL2 para esta função). Marco real: deploy do Incremento 1 CONFIRMADO por saída real de terminal (`login`/`link`/`deploy` bem-sucedidos).** `index.ts` (v2.1.0) e `database.ts` (`listCardsMap`/`upsertCardExternalReference`) copiados ao repositório. Execução de ponta a ponta ainda NÃO confirmada — bloqueada por verificação pendente do secret `SUPABASE_SERVICE_ROLE_KEY` na Edge Function. |
| 0.35 | **Sprint B3.15 — 🎉 MARCO REAL: Incremento 1 CONFIRMADO CONCLUÍDO — `card_external_reference` com 188/188 registros para a `ME1`.** Causa raiz de um bloqueio real diagnosticada (GRANT ausente em `card_external_reference` para `service_role`, mesmo gap já visto em `card_set_external_reference`) e corrigida pela migration `253`. Logging de erro corrigido em `database.ts` (expõe a causa real do PostgreSQL em vez de um erro genérico). Nova auditoria de GRANTs proposta por Fabrício, deliberadamente adiada. |
| 0.36 | **Sprint B3.16 — Incremento 2 (Download de Imagens) iniciado: fluxo definido (TCGdex → download → Storage → `card_asset`), teste controlado com uma única carta aprovado por Fabrício antes de escalar.** Estrutura real de `card_asset` parcialmente confirmada; `card_asset_type` confirmada (`CARD_FRONT` escolhido), corrigindo uma suposição inicial de nome de tabela (`asset_type`, incorreto). `storage_bucket` ainda NÃO confirmada — nenhum código escrito nesta revisão. |
| 0.37 | **Sprint B3.17 — Estrutura real de `storage_bucket` confirmada: catálogo interno de metadados (não o bucket físico), mapeado 1:1 a `card_asset_type` (`card-front`/`card-back`/`artwork`).** Bucket físico `card-front` criado e confirmado no Supabase Storage — primeiro bucket físico do projeto. |
| 0.38 | **Sprint B3.18 — Estrutura completa de `card_asset` confirmada (18 colunas; sem `card_external_reference_id` — a referência externa é apenas fonte de importação, não participa do relacionamento final).** Código do Incremento 2 (teste controlado com uma carta) escrito e **DEPLOYADO, CONFIRMADO** (`index.ts` v2.2.0 + `database.ts`). Execução real FALHOU — terceiro caso confirmado do mesmo gap de GRANT ausente para `service_role` (desta vez em `language`); correção proposta, ainda NÃO confirmada executada. |
| 0.39 | **Sprint B3.19 — Cadeia de GRANTs ausentes resolvida (quatro novos casos reais: `language`/`card_asset_type`/`card_asset`/`expansion`, Query `254`). Marco real: teste controlado do Incremento 2 CONFIRMADO CONCLUÍDO** — primeira imagem real do projeto (`ME1-001`/Bulbasaur) importada de ponta a ponta, upload confirmado, `card_asset` criado. Seis casos reais acumulados do mesmo padrão de GRANT ausente; auditoria consolidada (`grants.sql`) segue deliberadamente adiada. |
| 0.40 | **Sprint B3.20 — 🎉 MARCO REAL: Incremento 2 CONCLUÍDO para a `ME1` — 188/188 imagens importadas, 0 falhas.** Refatoração (`services/storage.ts` extraído); processamento escalado de 1 carta para 188, em lotes controlados de 5. Bug real de regra de negócio corrigido (`external_url` deve ser `null` para ativos armazenados internamente). Melhoria de idempotência identificada e deliberadamente adiada por decisão de Fabrício. `index.ts` v2.3.0 e novo `services/storage.ts` copiados ao repositório. |
