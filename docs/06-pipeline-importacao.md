# Pipeline de Importação

| Campo | Valor |
|--------|-------|
| **Documento** | Pipeline de Importação |
| **Arquivo** | `docs/06-pipeline-importacao.md` |
| **Versão** | 0.10 |
| **Status** | Em elaboração |
| **Objetivo** | Definir a estratégia de importação e sincronização de dados de fontes externas para o Catálogo Editorial do Project Mimikyu. |
| **Escopo** | Estratégia de importação e sincronização, incluindo — desde a revisão `0.6` — a arquitetura de execução da Edge Function `import-card-assets` (Bloco B do roteiro de `05-modelo-de-dados.md`) e o roteiro de implementação incremental por sprints. Não é um manual operacional de deploy nem substitui o Supabase Dashboard/CLI reais. |
| **Dependências** | `02-architecture-principles.md`, `04-domain-model.md` |
| **Documentos Relacionados** | `adr/ADR-006-separation-of-catalog-ownership-and-analytics.md`, `adr/ADR-008-external-catalog-data-sources.md` |

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
- verificação de direitos/termos de uso das imagens antes de importação em massa (ver `05-modelo-de-dados.md`, seção "Arquitetura de Importação de Ativos" — ressalva registrada, não resolvida).

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
| B2.3 | Integração com Banco (consulta a `asset_import_run` por `run_code`) | 🟪 Em andamento — bug de permissão encontrado e corrigido; teste ainda não concluído (ver seção do sprint, abaixo) |
| B2.4 | Integração com TCGdex | 🟪 Não iniciado |
| B2.5 | Download | 🟪 Não iniciado |
| B2.6 | Storage | 🟪 Não iniciado |
| B2.7 | Card Asset (inclui `card_external_reference` e tratamento de falha) | 🟪 Não iniciado |
| B2.8 | Carga `880` (inclui processamento em lote e execução de `card_set` completo) | 🟪 Não iniciado |

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

**Terceira tentativa, após aparente correção do texto — HTTP 404 novamente, causa ainda NÃO identificada ao final desta revisão.** Visualmente o `run_code` enviado parece idêntico ao armazenado, mas o resultado continua sendo "não encontrado". Uma consulta de diagnóstico foi preparada (comparando `run_code`, `length(run_code)` e um booleano `exact_match` contra o valor esperado) para descartar diferenças invisíveis (espaço/caractere oculto) — **ainda não executada nem reportada nesta revisão**. **Status real, sem ambiguidade**: o Sprint B2.3 permanece **em andamento, não concluído** — o critério de aceite ("a função consegue localizar uma execução pelo `run_code`") ainda não foi atingido; o que está confirmado até aqui é o deploy do código, a criação de um `asset_import_run` real, e a correção do bug de permissão.

**Prévia (não confirmada) da evolução dos próximos sprints**, compartilhada pela sessão pareada como expectativa, não como uma nova versão oficial do roteiro consolidado (ver tabela "Roteiro vigente", acima, que permanece a referência formal até ser explicitamente atualizada): B2.3 Ler `asset_import_run` → B2.4 Ler `card_set` → B2.5 Listar cartas → B2.6 Consultar TCGdex → B2.7 Baixar imagem → B2.8 Upload Storage → B2.9 Criar `card_asset`. Esta prévia já diverge da tabela consolidada da revisão `0.9` (que tinha "Integração com TCGdex" em `B2.4` e terminava em `B2.8` com a Carga `880`) — registrado aqui por transparência, no mesmo espírito da comparação de roteiro já feita antes, mas **sem promovê-la a roteiro oficial** até ser reconfirmada de forma consolidada, para não repetir o padrão que já gerou o incidente de confiança da revisão `0.49` em `05-modelo-de-dados.md`.

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
