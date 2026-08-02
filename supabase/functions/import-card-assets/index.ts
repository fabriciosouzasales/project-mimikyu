/*
Project Mimikyu
Edge Function: import-card-assets
Sprint: B3.6 — Marco real: o HTTP 401 que bloqueava toda invocação desde o
Sprint B3.3 foi definitivamente eliminado, confirmado por teste real de
terminal. CONFIRMADO DEPLOYADO: `npx supabase functions deploy
import-card-assets` bem-sucedido, seguido de uma chamada real SEM nenhum
header de autenticação (agora desnecessário — ver abaixo) retornando HTTP 500
em vez do 401 histórico, prova de que a função finalmente executa. Ver
docs/06-pipeline-importacao.md, "Sprint B3.6", para o contexto completo.

Este arquivo é uma cópia versionada do código confirmado como publicado no
projeto Supabase, seguindo o mesmo princípio já usado em `database/` para SQL:
copiado para o repositório apenas depois de confirmado (ver `database/README.md`).

MUDANÇA ARQUITETURAL REAL, decidida e confirmada nesta revisão: a biblioteca
`@supabase/server` (`withSupabase`) foi abandonada para esta função — e,
esperado, para as futuras Edge Functions do projeto — depois de três revisões
consecutivas (Sprints B3.3/B3.4/B3.5) sem conseguir fazer `auth: ["secret"]`
autenticar com sucesso uma Secret Key real, mesmo após múltiplas hipóteses
reais testadas e descartadas (tipo/nome da chave, `verify_jwt`, header
`apikey`, remoção do próprio `auth: ["secret"]`). Substituída por
`Deno.serve()` puro + `@supabase/supabase-js`, com um cliente Supabase criado
uma única vez, no escopo do módulo, a partir de `SUPABASE_URL`/
`SUPABASE_SERVICE_ROLE_KEY` (variáveis de ambiente padrão de toda Edge
Function Supabase, não secrets customizados). Decisão explicitamente
concordada por Fabrício ("Concordo completamente... eu também abandonaria o
@supabase/server. A arquitetura ficará mais simples e muito mais previsível.").
A Convenção #4 (execução restrita via `auth: ["secret"]`), declarada na
revisão `0.9` de docs/06-pipeline-importacao.md, está SUPERSEDIDA por esta
mudança — ver nova Convenção #8 abaixo.

Consequência prática: validações que antes eram implícitas via `withSupabase`
(método HTTP, parsing de JSON, corpo obrigatório) agora são feitas manualmente
neste arquivo — sem alteração de comportamento observável para quem chama a
função.

Histórico:
- v1.0.0 (Sprint B2.1/B2.2, CONFIRMADO publicado e invocado com sucesso):
  respondia apenas `{ success: true, function: "import-card-assets", version: "1.0.0", status: "ready" }`.
- v1.1.0 (Sprint B2.3, CONFIRMADO publicado e testado): recebe `run_code` via
  payload JSON e consulta `asset_import_run`.
- v1.2.0 (Sprint B2.4, CONFIRMADO publicado e testado com execução real —
  `card_set` `ME0`/"Black Star Promos", `card_count: 0`): fluxo ampliado para
  `run_code` → `asset_import_run` → `card_set` → listagem de `card` (ordenada
  por `collector_order`). Toda a lógica vivia em um único arquivo.
- v1.2.1 (Sprint B2.4.1, CONFIRMADO publicado e testado — mesmo resultado do
  teste anterior, apenas com `version: "1.2.1"`): refatoração estrutural, sem
  mudança de comportamento observável. Lógica de acesso a dados extraída para
  `services/database.ts`.
- v1.3.0 (Sprint B3.3, CONFIRMADO DEPLOYADO — primeira vez que a função chama
  uma fonte externa real): fluxo passa a incluir `findCardSetExternalReference`
  e uma chamada real a `TcgdexClient.getSet()` (`services/tcgdex.ts`, também
  confirmado deployado nessa revisão pela primeira vez). Deploy confirmado,
  mas nenhuma invocação bem-sucedida — bloqueada por HTTP 401.
- v1.3.1 (Sprint B3.4/B3.5, aplicada e testada por Fabrício): removia
  `{ auth: ["secret"] }` de `withSupabase(...)`, mantendo a biblioteca. Testada
  de ponta a ponta no Sprint B3.5 — o 401 PERSISTIU, invalidando essa hipótese
  como correção suficiente. Nunca copiada a este arquivo no repositório.
- v2.0.0 (Sprint B3.6, CONFIRMADO DEPLOYADO, COM O 401 ELIMINADO POR TESTE
  REAL): remove completamente `@supabase/server`/`withSupabase`; cliente
  Supabase criado manualmente via `createClient(SUPABASE_URL,
  SUPABASE_SERVICE_ROLE_KEY)` no escopo do módulo; mesmo fluxo funcional das
  versões anteriores (`findImportRun`→`findCardSet`→
  `findCardSetExternalReference`→`TcgdexClient.getSet()`), agora com
  validação manual de método HTTP/corpo JSON/`run_code` (antes implícita via
  `withSupabase`). Teste real sem nenhum header de autenticação (correto
  agora — a autenticação é interna à função, via variável de ambiente)
  retornou HTTP 500 em vez de 401, confirmando que a função finalmente
  executa. Causa do 500 diagnosticada como GRANT ausente em
  `card_set_external_reference` para `service_role` (a tabela nunca recebeu
  `GRANT SELECT/INSERT/UPDATE/DELETE` explícito) — corrigida por uma nova
  migration real (ver `database/migrations/250_grant_card_set_external_reference_permissions.sql`)
  e reconfirmada por consulta real a `information_schema.role_table_grants`.
- v2.1.0 (Sprint B3.13, CONFIRMADO CONCLUÍDO no Sprint B3.15 — execução real
  de ponta a ponta validada: `imported: 188`, `ignored: 0`, `total: 188` para
  a `ME1`, reconfirmado por `COUNT(*)` em `card_external_reference`):
  incremento real de persistência (Incremento 1). `card`/`card_variant` já
  estão populadas para as 5 coleções (ver docs/05-modelo-de-dados.md) — esta
  função NUNCA insere em `card`, apenas consulta. Carrega todas as cartas da
  coleção via `listCardsMap` (um único SELECT, `Map<collector_number,
  card_id>`) e faz `UPSERT` em `card_external_reference`
  (`upsertCardExternalReference`, idempotente via
  `ON CONFLICT (card_id, asset_source_id)`). Bloqueio real encontrado e
  corrigido no caminho: GRANT ausente em `card_external_reference` para
  `service_role` (Query 253).
- v2.2.0 (Sprint B3.18/B3.19): Incremento 2 (Download de Imagens), primeira
  versão do teste controlado com uma única carta (`set.cards[0]`). Deploy
  confirmado no Sprint B3.18; execução bloqueada, em sequência, por quatro
  novos casos reais do mesmo gap de GRANT (`language`, `card_asset_type`,
  `card_asset`, `expansion` — Query `254`), cada um diagnosticado pelo erro
  real do PostgreSQL nos logs, nunca adivinhado. **CONFIRMADO CONCLUÍDO no
  Sprint B3.19**: com os quatro GRANTs corrigidos, o teste controlado
  finalmente executou de ponta a ponta com sucesso — primeira imagem real do
  projeto baixada da TCGdex, enviada ao Supabase Storage (bucket
  `card-front`) e registrada em `card_asset` (`ME1-001`/Bulbasaur).
- v2.3.0 (Sprint B3.20, 🎉 CONFIRMADO CONCLUÍDO — MARCO REAL: Incremento 2
  100% completo para a `ME1`, `188/188` imagens importadas, `0` falhas):
  refatoração aprovada por Fabrício antes de escalar — lógica de
  download/checksum/caminho/upload extraída para `services/storage.ts`
  (`buildTcgdexHighImageUrl`, `buildCardStoragePath`, `downloadImage`,
  `uploadImage`); `index.ts` volta a ser apenas orquestrador. Processamento
  ampliado de uma única carta (`set.cards[0]`) para todas as cartas da
  coleção, com concorrência controlada em lotes de 5 (`processInBatches`,
  `IMAGE_BATCH_SIZE = 5`) — evita excesso de requisições simultâneas contra a
  TCGdex/Storage. Caminho de Storage passou a incluir o idioma
  (`me1/en/001.webp`), preparando o terreno para uma futura importação em
  `pt-BR` sem colisão. **Bug real de regra de negócio encontrado e
  corrigido** na primeira tentativa em escala: o código gravava a URL de
  origem da TCGdex em `external_url` mesmo para ativos já baixados e
  armazenados internamente (`storage_path` preenchido) — violando uma regra
  já aplicada pelo banco (esse campo é reservado para ativos não baixados,
  apenas referenciados externamente); corrigido para `external_url: null`
  sempre que o ativo é armazenado internamente. **Pergunta real de
  idempotência respondida, sem código novo**: reexecutar a função não
  duplica nem arquivos no Storage (`upsert: true` no upload) nem registros em
  `card_asset` (busca por chave natural antes de `INSERT`/`UPDATE`) — uma
  melhoria de performance (pular cartas já importadas, evitando novo
  download/upload) foi proposta e **deliberadamente adiada por decisão
  explícita de Fabrício**, para não interromper o fluxo a um passo da
  conclusão da `ME1`. Resposta final ampliada:
  `configuration`/`external_references`/`images`/`failures`.
- v2.3.1 (Sprint B3.23, CONFIRMADO DEPLOYADO — teste controlado da Fase 2):
  `LANGUAGE_CODE` alterado de `"en"` para `"pt-BR"` — **mudança temporária,
  usada apenas para o teste controlado com uma carta (reexecução do
  `run_code` original da `ME1`)**, seguindo a mesma disciplina já usada no
  Incremento 2 (validar com uma carta antes de escalar para as 5 coleções).
  Resultado real: segunda linha de `card_asset` criada para `ME1-001`
  (`language_id` = `pt-BR`, `storage_path` = `me1/pt-BR/001.webp`), ao lado
  da linha `en` já existente — confirma que `card_asset` já suporta múltiplos
  idiomas por carta corretamente. **Discrepância real sinalizada antes de
  qualquer nova execução em lote, NÃO resolvida nesta revisão**: a
  `UNIQUE (card_id, asset_source_id)` de `card_external_reference` não inclui
  idioma — como `asset_source_id` (TCGDEX) é o mesmo independente do idioma,
  uma execução em `pt-BR` pode fazer `UPSERT` sobre a mesma linha já usada
  para `en`, em vez de criar uma segunda. Fabrício optou por confirmar o
  comportamento real antes de alterar qualquer coisa — ver
  docs/06-pipeline-importacao.md, "Sprint B3.23". Espera-se que este valor
  volte a ser um parâmetro da requisição (já identificado como pré-requisito
  da Fase 2 desde o Sprint B3.21), não uma constante fixa.
- v2.4.0 (Sprint B3.24, 🎉 CONFIRMADO CONCLUÍDO — teste controlado da Fase 2
  com sucesso real de ponta a ponta): bug real encontrado e corrigido —
  `TcgdexClient` estava sendo criado com `LANGUAGE_CODE` (`"pt-BR"`, o código
  interno do Mimikyu) diretamente, mas a API da TCGdex não reconhece esse
  identificador (`TCGDEX_HTTP_404`); confirmado por teste direto no navegador
  que o identificador real da TCGdex para português é `"pt"`. Nova constante
  `TCGDEX_LANGUAGE = "pt"` introduzida, usada exclusivamente para criar o
  `TcgdexClient` — `LANGUAGE_CODE` continua sendo usado em todos os outros
  pontos (busca em `language`, `card_asset.language_id`, caminho no Storage),
  sem nenhuma alteração no banco. Resultado real, reexecutando o `run_code`
  original da `ME1`: `external_references: { imported: 188 }`,
  `images: { imported: 188, failed: 0 }`. Três validações reais confirmadas:
  arquivo presente no bucket `card-front` (`me1/pt-BR/001.webp`); duas linhas
  reais em `card_asset` para a mesma carta (`en`/`pt-BR`); imagem pública
  aberta e confirmada visualmente em português. **Pendência que segue real e
  NÃO confirmada por consulta direta**: se `card_external_reference` (que
  tem `UNIQUE (card_id, asset_source_id)`, sem idioma) agora tem os dados da
  `en` sobrescritos pelos da `pt-BR`, dado que nenhuma consulta específica a
  essa tabela foi executada nesta revisão — ver docs/06-pipeline-importacao.md,
  "Sprint B3.24".
- v2.5.0 (2026-07-24, retomada da implementação após o encerramento da fase de
  documentação retroativa — primeira execução real do pipeline para uma
  coleção além das 5 originais): `LANGUAGE_CODE`/`TCGDEX_LANGUAGE` revertidos
  de `"pt-BR"`/`"pt"` para `"en"`/`"en"`, para importar `MEE` (Set de Energias
  Básicas, 8 Cards, `card`/`card_variant` já confirmados no catálogo) em
  inglês primeiro, seguindo o mesmo padrão Fase 1 (`en`) / Fase 2 (`pt-BR`) já
  usado nas 5 coleções originais. `image_source_url: tcgCard.image ?? null,`
  corrigido (era `tcgCard.image,`, incompatível com o tipo real da coluna,
  nula com CHECK — ver `services/database.ts` para a correção irmã do tipo).
  Resultado real (`RUN-20260724-00000041`): `card_external_reference` 8/8
  importadas; imagens 0/8 — TCGdex não publica o campo `image` para este Set
  (confirmado por consulta direta ao endpoint de Set e de carta individual),
  gap de dados na fonte, não falha do pipeline. `MEE`
  `card_set_external_reference` já confirmado (`external_set_id = 'mee'`,
  Migration `270`).
- v2.6.0 (2026-07-25, bug real encontrado por Fabrício em produção,
  inspecionando `asset_import_run` diretamente): a tabela tem uma máquina de
  estados completa (`PENDING`→`RUNNING`→`COMPLETED`/`COMPLETED_WITH_ERRORS`/
  `FAILED`/`CANCELLED`, governada por `govern_asset_import_run()`), mas
  nenhuma versão anterior deste arquivo jamais escrevia nela — só o `SELECT`
  de `findImportRun`. Toda execução, inclusive as bem-sucedidas, ficava presa
  em `PENDING` para sempre. Corrigido chamando
  `transitionImportRunToRunning` assim que a run é localizada, e
  `finishImportRun` em todo caminho de saída (sucesso com/sem falhas de
  imagem, e todo erro conhecido após a run ser localizada) — ver
  `services/database.ts` para as duas novas funções. As 11 runs já
  executadas antes desta correção foram corrigidas via backfill manual (ver
  docs/05-modelo-de-dados.md, seção Asset Import Run). **CONFIRMADO
  DEPLOYADO E TESTADO EM PRODUÇÃO**: primeira invocação real após o deploy
  (`RUN-20260725-00000081`, nova run criada só para este teste, `MEP`)
  falhou com `permission denied for table asset_import_run` no primeiro
  `UPDATE` (`transitionImportRunToRunning`) — mesmo padrão de gap de GRANT
  já visto nas Queries 250/253/254 (RLS habilitado não substitui GRANT de
  tabela); `service_role` tinha apenas `SELECT`/`TRUNCATE`/`REFERENCES`/
  `TRIGGER` nesta tabela, confirmado por consulta direta a
  `information_schema.role_table_grants` antes de corrigir. Corrigido por
  `database/migrations/272_grant_asset_import_run_write_permissions.sql`
  (concede `INSERT`/`UPDATE`). Reinvocada a mesma run após o GRANT: status
  final `COMPLETED_WITH_ERRORS` (`60`/`60`/`0`/`60`, mesmo gap conhecido de
  imagens da `MEP` na TCGdex), `started_at`/`finished_at` corretamente
  preenchidos — confirma que a máquina de estados agora funciona de ponta a
  ponta em produção.
- v2.7.0 (2026-08-02, CONFIRMADO DEPLOYADO — `npx supabase functions deploy
  import-card-assets` bem-sucedido, projeto `qjfutqujxrbzgrtkpgkg`, `deno
  cache`/`deno check` executados por Fabrício antes do deploy): dois
  problemas reais
  encontrados ao testar a continuação automática cartas->imagens (Query
  2092) numa Coleção grande (SV4/Fenda Paradoxal, 266 cartas) — a função
  estourou o tempo de execução da plataforma no meio do processamento
  (HTTP 546) e, como reprocessava a Coleção INTEIRA a cada chamada
  (decisão original do Sprint B3.20, deliberadamente adiada por Fabrício na
  época — ver v2.3.0 acima), toda nova tentativa manual travava sempre no
  mesmo ponto (~115/266), sem nunca progredir. Fabrício autorizou
  explicitamente revisitar essa decisão: "Se for preciso alterar a function
  para corrigir o problema, vamos fazer." Duas mudanças:
  1. Pular cartas já importadas — antes de montar o lote de
     download/upload, a função agora consulta quais Cards da coleção já têm
     uma imagem primária ativa para o tipo/idioma (`listCardIdsWithPrimaryAsset`,
     novo em `services/database.ts`) e as exclui do lote (`cardsToImport`).
     `upsertCardAsset` continua idempotente por si só (mantido, defesa em
     profundidade) — esta exclusão só evita o custo de rede de repetir um
     download/upload já bem-sucedido, o que faz cada retry avançar de
     verdade em vez de recomeçar do zero. `requested_count`/`processed_count`
     da run passam a refletir só o que ESTA run tentou (a resposta HTTP
     ganhou `images.already_imported` para mostrar quantas ficaram de fora).
  2. Progresso incremental — `asset_import_run` passa a ser atualizada a
     cada lote de `IMAGE_BATCH_SIZE` cartas processado
     (`updateImportRunProgress`, novo em `services/database.ts`), não só
     uma vez no final (`finishImportRun`, mantido). Pedido explícito de
     Fabrício: "quero colocar um contador... que indique a quantidade de
     imagens importadas e o total a ser importada. Quero enxergar o
     progresso real" — o frontend passa a consultar essa linha por
     `run_code` via polling enquanto a importação está rodando (ver
     `05-modelo-de-dados.md`). Efeito colateral positivo: se a plataforma
     matar a função no meio (como o HTTP 546 observado), o progresso real
     feito até ali já está gravado, em vez de a run ficar com contadores
     zerados/desatualizados. Os contadores de progresso
     (`requestedSoFar`/`processedSoFar`/`successSoFar`/`failuresSoFar`)
     também foram movidos para fora do `try` (mesmo padrão já usado por
     `run`, desde v2.6.0) — o `catch` agora encerra a run com o progresso
     real acumulado até o erro, em vez de zerar tudo incondicionalmente.
- v2.8.0 (2026-08-02, mesmo dia, rodada seguinte, PROPOSTA — AGUARDANDO
  `deno check` + deploy por Fabrício, ainda não confirmada publicada):
  otimização de velocidade — Fabrício reportou lentidão real comparando com
  o script PowerShell manual ("era quase instantânea"): o retry automático
  do frontend (revisão `1.38` de `05-modelo-de-dados.md`) fazia várias
  chamadas seguidas a esta função, e cada uma refazia a sincronização de
  `card_external_reference` para as 266 cartas da Coleção inteira, mesmo
  quando só uma fração ainda precisava de imagem. `cardsToImport` (cálculo
  de "quais cartas ainda faltam", introduzido na v2.7.0) foi movido para
  ANTES do passo de sincronização de referências (era depois) e a
  sincronização passou a rodar só sobre `cardsToImport`, não mais
  `set.cards` — uma carta com imagem já salva necessariamente já teve sua
  referência sincronizada num passo anterior bem-sucedido (a sincronização
  sempre roda por completo antes do laço de imagens, na mesma invocação),
  então pular essas cartas é seguro. `external_references.total` na
  resposta também passou a refletir `cardsToImport.length`.
- v2.9.0 (2026-08-02, mesmo dia, PROPOSTA — AGUARDANDO `deno check` +
  deploy por Fabrício): suporte real a EN + PT-BR simultâneos — pedido
  explícito de Fabrício ("O processo de importação das imagens só importou
  as cartas em inglês, ficaram pendentes as 266 imagens em PT"), depois de
  escolher explicitamente "Os dois idiomas (EN + PT-BR)" em vez de trocar o
  padrão para só PT-BR. `LANGUAGE_CODE`/`TCGDEX_LANGUAGE` (constantes fixas
  desde sempre) removidas como fonte de verdade — o idioma agora vem de
  `asset_import_run.language_id` (a run já guardava esse valor desde a
  Query 220/v1.0, mas nunca era lido; `admin_start_asset_import_run()` v1.3,
  Query 2092, passa a resolvê-lo a partir de `p_language_code`, parâmetro
  novo do frontend). `findImportRun` (services/database.ts) passa a
  selecionar `language_id`; `findLanguageByCode` (por código fixo) é
  substituída por `findLanguageById` (pelo id da run) neste fluxo.
  `TCGDEX_LANGUAGE_BY_CODE` — novo mapa local, único lugar que ainda conhece
  a tradução entre o código interno do Mimikyu e o identificador da TCGdex
  (`pt-BR` → `pt`, confirmado no Sprint B3.24; qualquer outro código usa a
  si mesmo) — decide o idioma passado a `new TcgdexClient(...)`.
  `upsertCardExternalReference` passa a receber `language_id` (Query 210
  v2.0/Migration 277: `card_external_reference` agora tem o idioma como
  parte da identidade da linha — `UNIQUE (card_id, asset_source_id,
  language_id)` — resolvendo a colisão sinalizada, e nunca corrigida, desde
  o Sprint B3.23/B3.24, em que sincronizar `pt-BR` sobrescrevia a linha já
  gravada em `en`). Nenhuma mudança na lógica de download/upload de imagem
  em si (`card_asset` já suportava múltiplos idiomas por carta desde o
  Sprint B3.23) — só a origem do idioma usado em cada run.

- v2.9.1 (2026-08-02, mesmo dia, rodada seguinte, CONFIRMADO DEPLOYADO —
  `npx supabase functions deploy import-card-assets` bem-sucedido, projeto
  `qjfutqujxrbzgrtkpgkg`, versão 26): `downloadImage()` (services/storage.ts)
  ganhou um
  timeout explícito de 20s — ver o comentário completo naquele arquivo.
  Motivado por um bug real reportado por Fabrício (importação de ME5/120
  cartas "travada", 0 imagens no Storage) diagnosticado via MCP do Supabase
  (logs da Edge Function, logs do Storage e `asset_import_run` direto no
  banco): sem timeout, um download pendurado consumia sozinho todo o
  orçamento de execução da plataforma sem nenhum progresso gravado —
  runs anteriores da mesma Coleção confirmam o padrão (`processed_count`
  chegava a 60–85 em quase 15 minutos, `success_count` sempre `0`). Nenhuma
  mudança em `index.ts` nesta revisão — só em `services/storage.ts`.
- v2.9.2 (2026-08-02, mesmo dia, rodada seguinte, CONFIRMADO DEPLOYADO —
  verificado via MCP do Supabase, `list_edge_functions`, versão 27,
  `updated_at` compatível com o horário real das runs de teste seguintes):
  bug real encontrado logo depois do
  deploy da v2.9.1 — nova tentativa de ME5 falhou rápido (não mais travada)
  com `IMPORT_RUN_TRANSITION_TO_RUNNING_FAILED: Execução encerrada não pode
  mudar de status.`. Diagnosticado via MCP do Supabase (`asset_import_run`,
  logs da Edge Function, `pg_get_functiondef` de `admin_start_asset_import_
  run()`/`govern_asset_import_run()`): a primeira chamada real (run nova,
  `RUN-20260802-00000261`) falhou por um motivo genuíno mas não identificável
  a posteriori (aconteceu antes do laço de imagens — `requested_count`/
  `processed_count` ficaram zerados — provavelmente uma falha transiente de
  rede/API externa entre `transitionImportRunToRunning` e o início do laço de
  download), encerrando a run como `FAILED` com o erro real gravado. O retry
  automático do cliente (mesmo `run_code`, ver `web/components/catalogo/
  importar-imagens-view.tsx`) tentou de novo em seguida — mas como a run já
  estava `FAILED` (terminal), `govern_asset_import_run()` bloqueou a
  transição de volta pra `RUNNING`, e o `catch` desta função reescreveu
  `error_summary` com essa mensagem genérica de transição, apagando o motivo
  real da primeira falha. Corrigido: nova checagem logo após localizar a run
  (ver comentário completo acima, antes de `transitionImportRunToRunning`) —
  detecta run já terminal e devolve `code: "IMPORT_RUN_ALREADY_TERMINAL"` sem
  tocar na run. Mudança irmã, necessária pro cliente saber abrir uma run nova
  em vez de insistir na morta: `web/app/catalogo/importar-cartas/tcgdex/
  actions.ts` (`executarImportacaoImagens` passa a expor `runExpired`),
  `importar-imagens-view.tsx` e `importar-tcgdex-view.tsx` (retry automático
  abre run nova quando `runExpired`, em vez de só reusar o run_code morto).

Ver docs/06-pipeline-importacao.md, seções "Sprint B3.6", "Sprint B3.15",
"Sprint B3.19", "Sprint B3.20", "Sprint B3.23" e "Sprint B3.24", para o
contexto completo, o roteiro de sprints e o status real de cada etapa (o que
foi de fato confirmado vs. o que
ainda está planejado).

Convenções permanentes de Edge Functions do Project Mimikyu (ver docs/06):
1. Nunca criar arquivos de Edge Function "na mão" — sempre via
   `npx supabase functions new <nome-da-função>`.
2. Nunca alterar o template oficial da CLI sem necessidade — evoluir sobre ele.
3. Responsabilidade única por função.
4. [SUPERSEDIDA no Sprint B3.6] Execução restrita por padrão via
   `auth: ["secret"]` (`@supabase/server`) — substituída pela Convenção #8
   abaixo, depois de três revisões reais sem sucesso em autenticar com essa
   biblioteca.
5. Nunca avançar sem validar — cada sprint fecha só com critério de aceite
   confirmado.
6. `index.ts` apenas orquestra — não conhece SQL/PostgreSQL/fontes externas
   diretamente, apenas coordena chamadas aos serviços especializados.
7. Fluxo padrão de validação antes de cada deploy: `deno cache index.ts` +
   `deno check index.ts`, executados de dentro da pasta da função (onde está
   o `deno.json`), depois `npx supabase functions deploy <nome-da-função>`
   executado na raiz do projeto (onde está o `config.toml`).
8. [NOVA, Sprint B3.6] Toda Edge Function cria seu próprio cliente Supabase
   manualmente, via `createClient(Deno.env.get("SUPABASE_URL")!,
   Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!)`, uma única vez, no escopo do
   módulo — não usa `withSupabase`/`@supabase/server`. Validações de método
   HTTP, corpo e payload passam a ser responsabilidade explícita do próprio
   `index.ts`.
*/

import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";
import {
  findImportRun,
  transitionImportRunToRunning,
  finishImportRun,
  updateImportRunProgress,
  findCardSet,
  findCardSetExternalReference,
  listCardsMap,
  listCardIdsWithPrimaryAsset,
  upsertCardExternalReference,
  findLanguageById,
  findCardAssetTypeByCode,
  findStorageBucketByCode,
  upsertCardAsset,
} from "./services/database.ts";
import { TcgdexClient } from "./services/tcgdex.ts";
import {
  buildTcgdexHighImageUrl,
  buildCardStoragePath,
  downloadImage,
  uploadImage,
} from "./services/storage.ts";

type RequestBody = {
  run_code?: string;
};

type ImageImportResult = {
  external_card_id: string;
  collector_number: string;
  name: string;
  success: boolean;
  storage_path?: string;
  public_url?: string;
  card_asset_id?: string;
  error?: string;
};

// v2.9.0 — o idioma da importação passa a vir de `asset_import_run.language_id`
// (resolvido por `admin_start_asset_import_run()` v1.3, Query 2092), não mais
// de uma constante fixa. `LANGUAGE_CODE`/`TCGDEX_LANGUAGE` removidas.
//
// Sprint B3.24 — o código de idioma interno do Mimikyu (`language.code`) e o
// identificador de idioma da TCGdex são domínios independentes e NÃO podem
// ser usados um pelo outro: `pt-BR` é o código correto no banco, mas a API
// da TCGdex não o reconhece (`TCGDEX_HTTP_404`, confirmado por consulta
// direta no navegador a `.../v2/pt-BR/sets/me01`); o identificador real da
// TCGdex para português é `pt` (confirmado da mesma forma em
// `.../v2/pt/sets/me01`). Este mapa traduz apenas para a chamada à TCGdex,
// sem alterar `language.code` em nenhum outro uso (busca em `language`,
// `card_asset.language_id`, caminho no Storage) — qualquer código sem
// entrada explícita aqui usa a si mesmo (é o caso de `en`, já correto tanto
// no Mimikyu quanto na TCGdex).
const TCGDEX_LANGUAGE_BY_CODE: Record<string, string> = {
  "pt-BR": "pt",
};

function resolveTcgdexLanguage(languageCode: string): string {
  return TCGDEX_LANGUAGE_BY_CODE[languageCode] ?? languageCode;
}

const ASSET_TYPE_CODE = "CARD_FRONT";
const STORAGE_BUCKET_CODE = "card-front";
const IMAGE_BATCH_SIZE = 5;

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

/**
 * Executa operações assíncronas em lotes controlados — evita excesso de
 * requisições simultâneas contra a TCGdex/Storage ao processar uma coleção
 * inteira de cartas.
 */
async function processInBatches<T, R>(
  items: T[],
  batchSize: number,
  processor: (item: T) => Promise<R>,
): Promise<R[]> {
  const results: R[] = [];

  for (
    let index = 0;
    index < items.length;
    index += batchSize
  ) {
    const batch = items.slice(index, index + batchSize);
    const batchResults = await Promise.all(
      batch.map(processor),
    );
    results.push(...batchResults);
  }

  return results;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return Response.json(
      {
        success: false,
        error: "METHOD_NOT_ALLOWED",
      },
      {
        status: 405,
        headers: {
          Allow: "POST",
        },
      },
    );
  }

  let body: RequestBody;
  try {
    body = await req.json();
  } catch {
    return Response.json(
      {
        success: false,
        error: "INVALID_JSON",
      },
      { status: 400 },
    );
  }

  const runCode = body.run_code?.trim();

  if (!runCode) {
    return Response.json(
      {
        success: false,
        error: "RUN_CODE_REQUIRED",
      },
      { status: 400 },
    );
  }

  // v2.6.0 — declarado fora do try para que o catch consiga transicionar a
  // run para FAILED mesmo quando o erro acontece depois dela ser localizada.
  let run: Awaited<ReturnType<typeof findImportRun>> | null = null;

  // v2.7.0 — mesmo motivo, para os contadores de progresso: se um erro
  // inesperado acontecer DEPOIS de algumas imagens já terem sido
  // processadas (ex.: uma exceção fora do try/catch por-carta de
  // `processImageForCard`), o catch abaixo grava o progresso real já feito
  // em vez de zerar tudo — antes desta correção, `finishImportRun` no catch
  // sempre gravava contagens 0, mascarando qualquer progresso real anterior
  // ao erro.
  let requestedSoFar = 0;
  let processedSoFar = 0;
  let successSoFar = 0;
  let failuresSoFar = 0;

  try {
    run = await findImportRun(
      supabase,
      runCode,
    );

    if (!run) {
      return Response.json(
        {
          success: false,
          error: "IMPORT_RUN_NOT_FOUND",
        },
        { status: 404 },
      );
    }

    // v2.6.0 — `activeRun` (const) em vez de `run` (let) a partir daqui:
    // `run` precisa ser `let` para o catch conseguir lê-lo, mas isso impede
    // o TypeScript de propagar o null-check para dentro dos closures de
    // `processInBatches` abaixo (narrowing não atravessa closures sobre
    // variáveis mutáveis). `activeRun` é `const`, então a garantia de
    // "não nulo" vale em qualquer escopo aninhado.
    const activeRun = run;

    // v2.9.2 — a run já pode ter chegado a um status TERMINAL numa
    // tentativa anterior deste MESMO run_code. O retry automático do
    // cliente reusa o run_code de propósito (ver comentário em
    // `web/components/catalogo/importar-imagens-view.tsx`/
    // `importar-tcgdex-view.tsx`) para conseguir retomar de onde parou
    // quando a PLATAFORMA mata a função no meio, deixando a run presa em
    // RUNNING — nesse caso reusar é seguro e necessário. Mas se a run já
    // terminou de verdade (COMPLETED/COMPLETED_WITH_ERRORS/FAILED/
    // CANCELLED, por um erro real de aplicação, não por timeout de
    // plataforma), `govern_asset_import_run()` NUNCA permite reabri-la —
    // qualquer tentativa de transicionar de volta pra RUNNING falha com
    // "Execução encerrada não pode mudar de status.".
    // Bug real diagnosticado (ME5, 2026-08-02, via MCP do Supabase — logs
    // da Edge Function + `asset_import_run` direto no banco): sem esta
    // checagem, essa falha de transição SOBRESCREVIA o `error_summary`
    // real da run (gravado por `finishImportRun` na tentativa que de fato
    // a encerrou) por esta mensagem genérica, via o `catch` mais abaixo —
    // Fabrício via só "Execução encerrada..." no resultado final, nunca a
    // causa real da primeira falha. Corrigido: detecta esse caso ANTES de
    // tentar a transição e devolve um erro específico (`code:
    // "IMPORT_RUN_ALREADY_TERMINAL"`), sem tocar na run (preserva o
    // `error_summary` original gravado por quem de fato a encerrou) — o
    // cliente usa esse sinal pra abrir uma run NOVA em vez de insistir
    // numa run morta.
    if (
      activeRun.status !== "PENDING" &&
      activeRun.status !== "RUNNING"
    ) {
      return Response.json(
        {
          success: false,
          error:
            `IMPORT_RUN_ALREADY_TERMINAL: esta run já chegou a um status final (${activeRun.status}) numa tentativa anterior.`,
          code: "IMPORT_RUN_ALREADY_TERMINAL",
        },
        { status: 409 },
      );
    }

    // A partir daqui a run já existe: qualquer saída (sucesso ou erro) deve
    // terminar em um status terminal, nunca deixar PENDING.
    await transitionImportRunToRunning(supabase, activeRun.id);

    const cardSet = await findCardSet(
      supabase,
      activeRun.card_set_id,
    );

    if (!cardSet) {
      await finishImportRun(supabase, activeRun.id, {
        status: "FAILED",
        requested_count: 0,
        processed_count: 0,
        success_count: 0,
        failed_count: 0,
        error_summary: "CARD_SET_NOT_FOUND",
      });

      return Response.json(
        {
          success: false,
          error: "CARD_SET_NOT_FOUND",
        },
        { status: 404 },
      );
    }

    const externalReference =
      await findCardSetExternalReference(
        supabase,
        activeRun.card_set_id,
        activeRun.asset_source_id,
      );

    if (!externalReference) {
      await finishImportRun(supabase, activeRun.id, {
        status: "FAILED",
        requested_count: 0,
        processed_count: 0,
        success_count: 0,
        failed_count: 0,
        error_summary: "CARD_SET_EXTERNAL_REFERENCE_NOT_FOUND",
      });

      return Response.json(
        {
          success: false,
          error: "CARD_SET_EXTERNAL_REFERENCE_NOT_FOUND",
        },
        { status: 404 },
      );
    }

    // v2.9.0 — idioma resolvido pela própria run (`activeRun.language_id`,
    // definido por `admin_start_asset_import_run()` v1.3, Query 2092), não
    // mais por uma constante fixa.
    const language = await findLanguageById(
      supabase,
      activeRun.language_id,
    );

    if (!language) {
      throw new Error(
        `LANGUAGE_NOT_FOUND: ${activeRun.language_id}`,
      );
    }

    const assetType = await findCardAssetTypeByCode(
      supabase,
      ASSET_TYPE_CODE,
    );

    if (!assetType) {
      throw new Error(
        `CARD_ASSET_TYPE_NOT_FOUND: ${ASSET_TYPE_CODE}`,
      );
    }

    const storageBucket = await findStorageBucketByCode(
      supabase,
      STORAGE_BUCKET_CODE,
    );

    if (!storageBucket) {
      throw new Error(
        `STORAGE_BUCKET_NOT_FOUND: ${STORAGE_BUCKET_CODE}`,
      );
    }

    // v2.9.0 — traduz o idioma da run (código interno do Mimikyu) para o
    // identificador que a TCGdex reconhece (ver TCGDEX_LANGUAGE_BY_CODE
    // acima) — antes, sempre "en" fixo via TCGDEX_LANGUAGE.
    const tcgdex = new TcgdexClient(
      resolveTcgdexLanguage(language.code),
    );
    const set = await tcgdex.getSet(
      externalReference.external_set_id,
    );

    const cards = await listCardsMap(
      supabase,
      activeRun.card_set_id,
    );

    // v2.7.0 (2026-08-02) — Cards que já têm uma imagem primária ativa para
    // este tipo/idioma são excluídas do lote antes de processar (ver
    // `listCardIdsWithPrimaryAsset`, novo em `services/database.ts`): sem
    // isso, toda reexecução baixava/subia a coleção inteira de novo, mesmo
    // as cartas já importadas com sucesso — e como o tempo de execução da
    // plataforma é finito, uma Coleção grande o bastante travava sempre no
    // mesmo ponto, sem nunca progredir entre tentativas (caso real:
    // SV4/Fenda Paradoxal, 266 cartas, presa em ~115 a cada nova chamada).
    // `upsertCardAsset` continua idempotente por si só (mantido, defesa em
    // profundidade) — esta exclusão é só uma otimização que evita o custo de
    // rede desnecessário de repetir um download/upload já bem-sucedido.
    //
    // v2.8.0 (2026-08-02, mesmo dia, rodada seguinte) — movido para ANTES da
    // sincronização de `card_external_reference` logo abaixo (era depois):
    // Fabrício reportou lentidão real comparando com o script PowerShell
    // manual ("era quase instantânea"), e parte da causa é estrutural — cada
    // tentativa automática do retry (revisão `1.38`) refazia a sincronização
    // de `card_external_reference` para as 266 cartas da Coleção inteira,
    // mesmo quando só uma fração ainda precisava de imagem. Card com imagem
    // já salva necessariamente já teve sua referência sincronizada num
    // passo anterior bem-sucedido (a sincronização sempre roda por completo
    // ANTES do laço de imagens, na mesma invocação) — reordenar para
    // calcular `cardsToImport` primeiro permite restringir a sincronização
    // só a essas cartas, a mesma otimização já aplicada ao download de
    // imagem em si.
    const existingImageCardIds = await listCardIdsWithPrimaryAsset(
      supabase,
      Array.from(cards.values()),
      assetType.id,
      language.id,
    );
    const cardsToImport = set.cards.filter((tcgCard) => {
      const cardId = cards.get(tcgCard.localId);
      return Boolean(cardId) && !existingImageCardIds.has(cardId as string);
    });

    // Sincronização de card_external_reference (Incremento 1, CONFIRMADO
    // CONCLUÍDO no Sprint B3.15) — v2.8.0: restrita a `cardsToImport` (era
    // `set.cards`, a Coleção inteira), ver comentário acima.
    const referenceResults = await processInBatches(
      cardsToImport,
      20,
      async (tcgCard) => {
        const cardId = cards.get(tcgCard.localId);

        if (!cardId) {
          console.warn(
            `Carta ${tcgCard.localId} não encontrada no catálogo.`,
          );
          return false;
        }

        await upsertCardExternalReference(
          supabase,
          {
            card_id: cardId,
            asset_source_id: activeRun.asset_source_id,
            language_id: language.id,
            external_card_id: tcgCard.id,
            external_set_id: externalReference.external_set_id,
            source_number: tcgCard.localId,
            source_url:
              `https://api.tcgdex.net/v2/${language.code}/cards/${tcgCard.id}`,
            image_source_url: tcgCard.image ?? null,
            metadata: tcgCard,
            is_active: true,
          },
        );
        return true;
      },
    );

    const importedReferences =
      referenceResults.filter(Boolean).length;
    const ignoredReferences =
      referenceResults.length - importedReferences;

    // Incremento 2 (Sprint B3.20) — download + upload + card_asset, em lotes
    // controlados. v2.7.0: só para `cardsToImport` (ver acima); loop manual
    // (era `processInBatches`) para poder gravar o progresso real em
    // `asset_import_run` a cada lote concluído (`updateImportRunProgress`,
    // novo em `services/database.ts`) — o frontend consulta essa linha por
    // `run_code` via polling para mostrar "X de Y" enquanto a importação
    // ainda está rodando, em vez de só saber o resultado no final.
    async function processImageForCard(
      tcgCard: (typeof cardsToImport)[number],
    ): Promise<ImageImportResult> {
        try {
          const cardId = cards.get(tcgCard.localId);

          if (!cardId) {
            throw new Error(
              `CARD_NOT_FOUND: ${tcgCard.localId}`,
            );
          }

          if (!tcgCard.image) {
            throw new Error(
              `TCGDEX_IMAGE_NOT_AVAILABLE: ${tcgCard.id}`,
            );
          }

          const imageSourceUrl = buildTcgdexHighImageUrl(
            tcgCard.image,
          );
          const image = await downloadImage(imageSourceUrl);
          const storagePath = buildCardStoragePath(
            cardSet.code,
            tcgCard.localId,
            language.code,
            image.fileExtension,
          );
          const upload = await uploadImage({
            supabase,
            bucketCode: storageBucket.code,
            storagePath,
            image,
          });

          // external_url é reservado para ativos NÃO baixados (apenas
          // referenciados externamente); este ativo já foi baixado e
          // armazenado internamente (storage_path preenchido), por isso
          // permanece null — regra de negócio já aplicada pelo banco.
          const cardAsset = await upsertCardAsset(
            supabase,
            {
              card_id: cardId,
              asset_type_id: assetType.id,
              source_code: "TCGDEX",
              source_reference: tcgCard.id,
              storage_path: upload.storagePath,
              external_url: null,
              mime_type: image.mimeType,
              file_extension: image.fileExtension,
              file_size_bytes: image.fileSizeBytes,
              width_pixels: null,
              height_pixels: null,
              checksum_sha256: image.checksumSha256,
              is_primary: true,
              asset_order: 1,
              is_active: true,
              language_id: language.id,
              storage_bucket_id: storageBucket.id,
            },
          );

          return {
            external_card_id: tcgCard.id,
            collector_number: tcgCard.localId,
            name: tcgCard.name,
            success: true,
            storage_path: upload.storagePath,
            public_url: upload.publicUrl,
            card_asset_id: cardAsset.id,
          };
        } catch (error) {
          const errorMessage =
            error instanceof Error
              ? error.message
              : "UNEXPECTED_IMAGE_IMPORT_ERROR";
          console.error(
            `IMAGE IMPORT FAILED ${tcgCard.id}:`,
            errorMessage,
          );
          return {
            external_card_id: tcgCard.id,
            collector_number: tcgCard.localId,
            name: tcgCard.name,
            success: false,
            error: errorMessage,
          };
        }
    }

    // v2.7.0 — grava nas variáveis declaradas fora do try (ver comentário
    // acima, junto de `run`) — se um erro inesperado interromper o loop no
    // meio, o catch consegue encerrar a run com o progresso real já feito,
    // em vez de zerar tudo.
    const imageResults: ImageImportResult[] = [];
    requestedSoFar = cardsToImport.length;

    for (let index = 0; index < cardsToImport.length; index += IMAGE_BATCH_SIZE) {
      const batch = cardsToImport.slice(index, index + IMAGE_BATCH_SIZE);
      const batchResults = await Promise.all(
        batch.map((tcgCard) => processImageForCard(tcgCard)),
      );
      imageResults.push(...batchResults);
      processedSoFar = imageResults.length;
      successSoFar += batchResults.filter((result) => result.success).length;
      failuresSoFar += batchResults.filter((result) => !result.success).length;

      await updateImportRunProgress(supabase, activeRun.id, {
        requested_count: requestedSoFar,
        processed_count: processedSoFar,
        success_count: successSoFar,
        failed_count: failuresSoFar,
      });
    }

    const importedImages = imageResults.filter(
      (result) => result.success,
    );
    const failedImages = imageResults.filter(
      (result) => !result.success,
    );

    // v2.6.0 — encerra a run com o resultado real: COMPLETED se nenhuma
    // imagem falhou, COMPLETED_WITH_ERRORS caso contrário. Contagens
    // baseadas na dimensão "imagens" (o que a run efetivamente entrega).
    // v2.7.0 — `requested_count` passa a ser `cardsToImport.length` (quantas
    // cartas esta run de fato tentou — já excluindo as que puladas por já
    // terem imagem), não mais `set.cards.length` (tamanho total da Coleção).
    await finishImportRun(supabase, activeRun.id, {
      status:
        failedImages.length === 0
          ? "COMPLETED"
          : "COMPLETED_WITH_ERRORS",
      requested_count: cardsToImport.length,
      processed_count: imageResults.length,
      success_count: importedImages.length,
      failed_count: failedImages.length,
      error_summary:
        failedImages.length === 0
          ? null
          : `${failedImages.length}/${imageResults.length} imagens falharam`,
    });

    return Response.json({
      success: failedImages.length === 0,
      version: "2.9.2", // CONFIRMADO DEPLOYADO — ver "Histórico" acima
      run: {
        id: activeRun.id,
        run_code: activeRun.run_code,
      },
      card_set: {
        id: cardSet.id,
        code: cardSet.code,
        name: cardSet.name,
      },
      configuration: {
        language: language.code,
        asset_type: assetType.code,
        bucket: storageBucket.code,
        image_batch_size: IMAGE_BATCH_SIZE,
      },
      external_references: {
        imported: importedReferences,
        ignored: ignoredReferences,
        // v2.8.0 — total agora é `cardsToImport.length` (só as cartas desta
        // run tentou sincronizar), não mais `set.cards.length` (a Coleção
        // inteira) — ver comentário acima de `cardsToImport`.
        total: cardsToImport.length,
      },
      images: {
        imported: importedImages.length,
        failed: failedImages.length,
        // v2.7.0 — `total` agora é só o que ESTA run tentou (cartas ainda
        // sem imagem no início dela); `already_imported` mostra quantas
        // ficaram de fora por já terem imagem (não recontadas/redownload).
        // O total real da Coleção é `already_imported + total`.
        total: imageResults.length,
        already_imported: existingImageCardIds.size,
      },
      failures: failedImages,
    });
  } catch (error) {
    console.error(error);

    const errorMessage =
      error instanceof Error
        ? error.message
        : "UNEXPECTED_ERROR";

    // v2.6.0 — se a run já foi localizada (e por isso já está RUNNING),
    // encerra como FAILED em vez de deixá-la presa. `finishImportRun` não
    // relança erro — nunca deve mascarar a resposta 500 já decidida aqui.
    // v2.7.0 — usa o progresso real acumulado até aqui (`requestedSoFar`/
    // `processedSoFar`/`successSoFar`/`failuresSoFar`, declaradas fora do
    // try) em vez de zerar tudo: se o erro aconteceu depois de algumas
    // imagens já terem sido processadas com sucesso, essa informação real
    // não deve se perder.
    if (run) {
      await finishImportRun(supabase, run.id, {
        status: "FAILED",
        requested_count: requestedSoFar,
        processed_count: processedSoFar,
        success_count: successSoFar,
        failed_count: failuresSoFar,
        error_summary: errorMessage,
      });
    }

    return Response.json(
      {
        success: false,
        error: errorMessage,
      },
      { status: 500 },
    );
  }
});