# Pipeline de Importação

| Campo | Valor |
|--------|-------|
| **Documento** | Pipeline de Importação |
| **Arquivo** | `docs/06-pipeline-importacao.md` |
| **Versão** | 0.23 |
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
- **novo, Sprint B2.5A**: se `ME0` deve ser mapeado ao Set oficial `mee`/"Mega Evolution Energy" da TCGdex (Opção B) ou permanecer uma coleção 100% interna, sem vínculo com a TCGdex (Opção A, recomendada pela sessão pareada) — decisão de negócio que depende do conteúdo real da coleção `ME0`, cross-referenciada com a pendência de longa data "escopo `ENERGY`" já registrada em ciclos anteriores deste projeto; não resolvida unilateralmente.
- **novo, Sprint B3**: o endpoint `GET /sets/{id}/cards` da TCGdex (usado em `TcgdexClient.getCardsBySet`) foi assumido no código, mas ainda não confirmado por uma chamada real — precisa ser validado antes do deploy de `sync-card-set`;
- **novo, Sprint B3**: mapeamento entre o roteiro vigente (`B2.5B`–`B2.9`) e a nova arquitetura de duas Edge Functions (`sync-card-set`/`import-card-assets`) — ver `ADR-017-two-function-import-pipeline.md` — ainda não detalhado por Fabrício; tabela "Roteiro vigente" mantida sem reescrita até essa confirmação.
- **novo, Sprint B3 (continuação)**: se `tcgdex.ts` (classe `TcgdexClient`) será compartilhado entre `import-card-assets` e a futura função `sync-card-set`, ou se a criação de `sync-card-set` como Edge Function própria foi tacitamente adiada — a implementação real segue dentro de `import-card-assets/services/`, divergindo do plano anunciado na mesma revisão; não resolvido unilateralmente.
- **novo, Sprint B3.1**: `card_set.code = 'ME5'` ainda não foi cadastrado no banco físico — confirmado por consulta real; quando for, a Query `910` (idempotente) deve ser reexecutada para popular seu mapeamento automaticamente.
- **novo, Sprint B3.4**: conteúdo completo de `supabase/config.toml` ainda não recebido — apenas o fragmento `[functions.import-card-assets]` (`verify_jwt = false`) foi confirmado; o arquivo não pôde ser copiado ao repositório por falta do conteúdo integral.
- **novo, Sprint B3.4**: a forma correta de configurar autenticação (`auth: ["secret"]`) para `@supabase/server@^1` continua sem confirmação real — duas hipóteses (header `apikey`, `verify_jwt = false`) já se mostraram insuficientes; precisa ser resolvida antes de reativar a autenticação, planejado para depois que o pipeline estabilizar.

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
4. **Execução restrita por padrão** (`auth: ["secret"]`) — funções como `import-card-assets` são infraestrutura interna do sistema (chamadas por script administrativo, outra Edge Function, ou futuramente um agendamento/Cron), não interface pública; não devem aceitar chamadas de clientes anônimos/publicáveis a menos que explicitamente decidido o contrário.
5. **"Nunca avançar sem validar", aplicado ao código** — mesmo princípio já usado nas migrations SQL. Cada Sprint só se encerra quando atinge um critério de aceite explícito e verificado (ex.: B2.2 — "a função responde `status: ready`"; B2.3 — "a função consegue localizar uma execução pelo `run_code`").
6. **`index.ts` apenas orquestra** — não conhece SQL/PostgreSQL/fontes externas diretamente, apenas coordena chamadas a serviços especializados (declarada no Sprint B2.4.1).
7. **Fluxo padrão de validação antes de cada deploy, declarada no Sprint B3.3**: `deno check index.ts` executado de dentro da pasta da função (onde está o `deno.json` real dela), seguido de `npx supabase functions deploy <nome-da-função>` executado na raiz do projeto (onde está o `config.toml`). Motivação real: `deno check` rodado da raiz do projeto ignora o `deno.json` da função e produz erros de dependência enganosos — misturar os dois contextos (Deno puro vs. runtime do Supabase) gerou um ciclo de depuração desnecessário nesta revisão.

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
| B2.5A | Integração com TCGdex — apenas consulta e recebimento do JSON (agora pelo `card_set`, via `card_set_external_reference`) | 🟨 Em andamento (`external_set_id` reais descobertos; `index.ts` v1.3.0/`database.ts`/`tcgdex.ts` CONFIRMADOS DEPLOYADOS no Sprint B3.3; invocação de ponta a ponta com resposta real da TCGdex ainda não confirmada — bloqueada por chave de autenticação incorreta; decisão de negócio sobre `ME0` pendente) |
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
