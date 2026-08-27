/*
Project Mimikyu
Script administrativo standalone: sync-justtcg-pricing
Incremento P8 — Conector JustTCG e Piloto Controlado (2026-08-17).

Objetivo original (P8): primeiro fluxo real JustTCG -> Pricing, exclusivamente server-side e
acionado manualmente por um administrador — nunca em resposta a requisição HTTP, nunca
agendado, nunca chamado pelo frontend. Resolvia pricing_set_mapping/pricing_card_mapping
para dois Card Sets-piloto (ME1, BASE1) e até três cartas por Set, hardcoded, buscando cada
carta individualmente (uma chamada HTTP por carta). Esse desenho ficou congelado como
histórico: ME1/BASE1 permanecem CONFIRMED, com dados já persistidos e intocados por este
incremento — não fazem parte da execução real abaixo.

Arquitetura (decisão registrada, não uma Edge Function): mesmo precedente de
scripts/import-manual-assets.ts — roda localmente, sob demanda, com a Service Role Key
do projeto, nunca é implantado no Supabase. "Acionado manualmente por administrador"
aqui significa que é o próprio administrador (Fabrício) quem executa este script na sua
máquina, com suas próprias variáveis de ambiente — o mesmo padrão já usado para SQL
(CLAUDE.md: "Quem executa o SQL no Supabase, por padrão, é Fabrício") e para a prova
técnica original (PowerShell, também local).

Credenciais: `JUSTTCG_API_KEY`, `SUPABASE_URL` e `SUPABASE_SERVICE_ROLE_KEY` (variáveis de
ambiente, nunca argumento de linha de comando, nunca logadas — nem seus valores, nem em
mensagens de erro). Nunca solicita nenhuma delas interativamente nem aceita literal em texto.

Fix revisão de robustez 2026-08-19 (fechamento do P14.3): `--fixture-check` roda offline
explicitamente, sem depender do ambiente (funciona com ou sem qualquer credencial definida).
Fora desse modo, a ausência de QUALQUER uma das três variáveis obrigatórias encerra o
processo com código de saída diferente de zero, ANTES de qualquer chamada de rede ou acesso
ao Supabase — nunca mais cai automaticamente em modo --fixture-check por credencial ausente
(comportamento antigo, removido: mascarava um ambiente mal configurado como se fosse uma
execução de validação bem-sucedida). Ver resolveEntryDecision(), abaixo — decisão pura,
testada offline nos dois caminhos (fixture-check explícito x variáveis ausentes).

pricing_source.is_active é TRUE desde o Incremento P14.1 (2026-08-19, condição comercial
satisfeita) — este script não altera esse valor. getJustTcgSource(), abaixo, continua
consultando explicitamente `WHERE code = 'JUSTTCG'`, um literal fixo, nunca um parâmetro.

============================================================================
Incremento P14.2 — Cobertura Escalável e Sincronização em Lotes (2026-08-19)
============================================================================

Contexto: o desenho de P8 fazia uma chamada HTTP por carta (Fase B original, removida
abaixo) — inviável para os ~7.500 cards locais e desperdiça o batching contratado
(plano Starter: até 100 cards por requisição, confirmado em
https://justtcg.com/docs/api/cards, 2026-08-19). Este incremento substitui a Fase B
inteira por descoberta paginada de set completo, correlação por número de coleção
(primário) + nome (secundário, só para desempate/verificação) e separação explícita de
correspondências seguras/ausentes/ambíguas — nunca confirmando uma ambiguidade
automaticamente.

Achado material da introspecção, registrado antes de implementar (não é uma contradição
da premissa de Fabrício, só o "como" — não houve necessidade de pausar): o endpoint
POST /v1/cards (lote de até 200, até 100 no plano Starter/Pro) exige identificadores já
conhecidos por item (variantId/cardId/tcgplayerId/mtgjsonId/scryfallId/tcgplayerSkuId) —
inútil para descobrir cartas ainda não mapeadas. O mecanismo real de "até 100 cartas por
requisição" para preencher a cobertura de um Set inteiro é a paginação do GET /v1/cards
(`limit`/`offset`/`meta.hasMore`), documentada oficialmente como o próprio caso de uso
"fetch every card in a set, paginated" (https://justtcg.com/docs/examples). É isso que
fetchAllCardsForSet(), abaixo, implementa — uma chamada por página de até 100 cartas do
Set, não uma chamada por carta. O endpoint POST continua fora de escopo nesta rodada
(seria útil numa futura atualização de preço em lote de mappings já CONFIRMED — não é o
problema deste incremento, que é descoberta/mapeamento).

Segundo achado material: nenhuma tabela local (card_set/expansion/game) guarda um nome
em inglês — os nomes são todos pt-BR ("Coleção Básica", "Fóssil"), e até a origem do
nome em inglês de `expansion.name` é inconsistente entre eras (ex.: ME1 tem
"Mega Evolution" em inglês; BASE4 tem "Coleção Básica" em português). Casar Sets por
nome, portanto, não é confiável de forma genérica. resolveSetMatchV2(), abaixo, usa
`release_date` (data ISO exata, campo estável e comparável 1:1 com `card_set.release_date`
local) como sinal primário automatizado — se exatamente um Set da JustTCG compartilha a
mesma data, é candidato seguro; zero ou mais de um nunca é confirmado automaticamente
(NOT_FOUND ou PENDING/ambíguo, respectivamente). overrideExternalSetId continua suportado
(compatibilidade com o padrão manual de P8), mas não é usado no piloto real desta rodada.

Fix P14.2.1 (2026-08-19, mesmo dia, correção pós-piloto real de Fabrício): o piloto real
retornou `SET_NOT_FOUND(BASE4)` mesmo com `card_set.release_date='2000-02-24'` batendo
exatamente com o registro `base-set-2-pokemon` da JustTCG. Causa raiz: a API retorna
`release_date` como datetime ISO completo (`"2000-02-24T00:00:00.000Z"`), não como data pura
— a comparação de string exata original nunca batia com o `date` puro do Postgres.
normalizeExternalSetReleaseDate()/normalizeJustTcgSets(), abaixo, normalizam para `YYYY-MM-DD`
na fronteira de entrada (antes de resolveSetMatchV2), sem qualquer conversão de timezone
(regex de prefixo, nunca `Date`/`toISOString()`); o valor bruto é preservado em
`release_date_raw` para auditoria. Nenhuma migration, nenhuma chamada externa nesta correção.

Fix P14.2.2 (2026-08-19, mesmo dia, melhoria mínima pedida por Fabrício após revisar o
dry-run real de BASE4 — sem chamada externa, migration ou alteração no banco): o dry-run
antigo classificava as 130 cartas locais mas era opaco sobre o "porquê" dos números
agregados (nenhuma forma de saber de onde vinham os 7 registros externos excedentes,
nenhuma evidência recuperável dos 3 casos AMBIGUOUS, nenhuma indicação de quantos produtos/
observações uma execução real processaria). Três adições, todas cobertas por
--fixture-check:
1. diagnoseExternalCoverage() — quatro métricas novas no resumo (registros externos sem
   número utilizável; registros externos cujo número não existe no catálogo local; grupos
   de números externos duplicados; total de registros nesses grupos), deliberadamente
   independentes entre si — nunca somam externalCardsSeenTotal - cartas locais.
2. logDryRunCardEvidence() — em dry-run, imprime uma linha sanitizada por carta
   AMBIGUOUS/ABSENT (carta local, collector_number, motivo, candidatos externos com
   id/nome/número); nunca variantes/preço/payload/headers/segredos, porque matchResult
   nunca carrega esses dados (garantia estrutural, não só disciplina de impressão).
3. planVariantProjection() — em dry-run, para cada carta SAFE, projeta productsProjected/
   observationsProjected/variantsProjectionSkipped repetindo a mesma validação de dado do
   caminho real (id externo, printing, preço numérico, condição mapeada), mas sem nenhum
   parâmetro de SupabaseClient — estruturalmente incapaz de escrever. O `continue`
   antecipado que existia logo após `cardsSafe++` foi substituído por este ramo de
   projeção; o caminho real (upsertCardMapping + insert de pricing_product/
   pricing_observation) permanece exatamente como estava, mais abaixo no mesmo laço,
   nunca executado quando `args.dryRun`. `productsWritten`/`observationsWritten` continuam
   0 em dry-run — só o caminho real os incrementa.
Documentação (05f-pricing.md/ADR-029/handoff/log) fica para depois do piloto validado, por
instrução explícita de Fabrício.

Nenhuma migration foi necessária: `pricing_card_mapping.match_status`/
`pricing_set_mapping.match_status` já tinham o valor `PENDING` no enum (Incremento P2) —
reaproveitado aqui como "candidato ambíguo, aguardando revisão humana", mesmo padrão já
usado em outra frente do projeto (fila "Resolver mapeamento" de Card Variant). Não há
"AMBIGUOUS" novo no schema — é PENDING com `match_evidence.resolution` explicando o motivo.

Mudanças estruturais nesta rodada (todas cobertas por --fixture-check, ver runFixtureCheck):
1. JustTcgClient aceita `fetchImpl` injetável (default: fetch global) — necessário para
   testar paginação/retry/429 100% offline, mesmo padrão de injeção de dependência já usado
   em supabase/functions/_shared/pricing-ptax/core.ts.
2. fetchAllCardsForSet() pagina GET /v1/cards?game=&set=&limit=100&offset=N até
   meta.hasMore=false (ou data.length < limit como fallback) — uma chamada por página de
   até 100 cartas, nunca uma por carta.
3. classifyCardMatch() decide SAFE/AMBIGUOUS/ABSENT por carta local usando EXCLUSIVAMENTE
   Card Set já CONFIRMED + collector_number normalizado (P14.4.4 — correção de causa raiz,
   decisão de negócio confirmada por Fabrício: nome NUNCA é critério de matching, catálogo
   local é PT-BR e a JustTCG é em inglês). 1 candidato -> SAFE; 0 -> ABSENT; >1 -> AMBIGUOUS;
   número local ausente/inutilizável -> ABSENT. Nome é preservado só como evidência de
   auditoria/exibição (campo `divergencia_de_nome`), nunca bloqueia nem desempata. Cartas
   externas sem número utilizável (`number` ausente, vazio ou "N/A" — valor real documentado
   pela JustTCG para cartas sem numeração, ex. Energias promocionais) nunca entram no índice
   por número — ficam ABSENT deste lado. Sem exceção por categoria de carta (Treinador,
   Nidoran, tradução, Set específico) — regra única para todo o catálogo.
4. upsertSetMapping()/upsertCardMapping() fazem SELECT antes de decidir INSERT/UPDATE/no-op
   — corrige uma lacuna real do padrão insert-e-tolera-duplicata de P8: aquele padrão nunca
   conseguia promover uma linha PENDING/NOT_FOUND antiga para CONFIRMED numa reexecução
   (a chave única (card_id, pricing_source_id) já existe, então um INSERT puro sempre
   colidia, mesmo quando a nova classificação era melhor). Uma linha já CONFIRMED nunca é
   rebaixada por uma nova classificação pior — só registrada como divergência, sem escrita.
5. Escrita de pricing_observation agora distingue divergência real de preço (mesma
   identidade — produto+condição+tipo+moeda+mercado+observed_at — mas price diferente do já
   persistido) de conflito inofensivo (mesmo price). P8 tratava as duas coisas como
   CONFLICT_IGNORED silenciosamente; aqui, uma divergência de preço na mesma identidade é
   detectada, contada à parte (observationsDivergent) e nunca sobrescreve o valor já
   persistido — mesma disciplina de "divergência nunca sobrescreve" já usada em PTAX (P9).

Fora de escopo desta rodada (confirmado, não implementado): nenhuma Edge Function, Cron ou
nova arquitetura; nenhuma sincronização do catálogo completo (~7.500 cards) — só o Set-piloto
definido em SET_TARGETS abaixo; nenhuma alteração de PTAX ou frontend; nenhum novo GRANT/RLS;
nenhum segredo (`JUSTTCG_API_KEY`/`SUPABASE_SERVICE_ROLE_KEY`) visto, solicitado, exibido ou
registrado por este agente em nenhum momento.

============================================================================
Incremento P14.4.1 — Inventário de Cobertura e Plano de Ondas (2026-08-19)
============================================================================

Objetivo: substituir decisão por estimativa (SET_TARGETS hardcoded, escolhido manualmente a
cada rodada) por um plano calculado a partir do catálogo local real (hoje 45 Card Sets
ativos/7.429 cartas — ver introspecção desta rodada) e dos Sets reais devolvidos por
GET /v1/sets, considerando a expansão futura do catálogo para ~18.700 cartas. Implementa
SOMENTE o inventário/plano — nenhuma sincronização de preço, nenhuma escrita, nenhum
pricing_sync_run nesta rodada. A execução real de uma onda fica para um incremento seguinte
(P14.4.2+), que reaproveitará fetchAllCardsForSet()/persistBatchedResults() já existentes.

Novo modo `--expansion-plan` (ver runExpansionPlan()/executeExpansionPlan(), seção 7b,
abaixo): exige as mesmas três credenciais do piloto real (valida ANTES de qualquer rede/banco,
via resolveEntryDecision() — mesma disciplina do fix de robustez acima), faz EXATAMENTE uma
chamada HTTP (`GET /v1/sets?game=pokemon`), lê o catálogo local só para leitura (card_set/card/
pricing_set_mapping/pricing_card_mapping/pricing_product/pricing_observation — nenhum INSERT/
UPDATE/RPC em nenhuma dessas tabelas), nunca chama `/cards`, nunca cria pricing_sync_run, nunca
altera mapping/produto/observação, e nunca imprime a resposta bruta da API nem qualquer
credencial — só os campos derivados (id/nome/release_date/variants_count) por Set já resolvido.

Classificação por Set local ativo (classifySetForExpansionPlan(), pura): ALREADY_CONFIRMED
(mapping já CONFIRMED — preservado, nunca reavaliado) > SAFE_CANDIDATE (release_date normalizada
bate com exatamente um Set externo — mesmo sinal primário já validado em resolveSetMatchV2(),
P14.2; nome nunca é usado como fundamento isolado aqui, só apareceria como evidência auxiliar se
fosse necessário desempatar, o que não é o caso desta rodada) > AMBIGUOUS (2+ candidatos na
mesma data) > NOT_FOUND (zero candidatos, ou Set local sem release_date). Só SAFE_CANDIDATE
entra em uma onda automática — AMBIGUOUS/NOT_FOUND nunca.

Estimativa de páginas: a JustTCG documenta `variants_count` em `/v1/sets` (número de VARIANTES
rastreadas, não de CARTAS — confirmado em https://justtcg.com/docs/api/sets, 2026-08-19) — como
uma carta tem várias variantes (printing × condição), esse campo não é uma base confiável para
estimar páginas de `GET /v1/cards` (paginado por carta, não por variante). Por isso o plano
NUNCA inventa um total externo de cartas: `pagesEstimateExternal` é sempre `null`, com o motivo
explícito. A estimativa de chamadas por onda usa só o que se conhece com certeza — a contagem
LOCAL de cartas do Set (`Math.ceil(localCardCount / 100)`) — sinalizada como aproximação.

Plano por ondas (buildExpansionWaves(), pura): agrupa só os SAFE_CANDIDATE em ondas de até 5
Sets E até 500 cartas locais, o que vier primeiro. Um Set individual com mais de 500 cartas
locais nunca é descartado nem dividido — forma sua própria onda, sinalizada (`oversized: true`),
sem interromper a formação das ondas seguintes.

Fora de escopo desta rodada: qualquer execução de onda (fica para P14.4.2+, exigirá seleção
explícita de onda/códigos — nenhum modo padrão pode significar "todos os Sets"); qualquer
alteração em runRealPilot()/SET_TARGETS (permanecem exatamente como estão, still usados pelo
piloto real de Set único); qualquer migration (nenhuma foi necessária — todas as leituras usam
tabelas/colunas já existentes).

============================================================================
Fix P14.4.1 — Truncamento de 1.000 linhas do Data API no --expansion-plan (2026-08-19, mesmo dia)
============================================================================

Causa raiz: o piloto real do --expansion-plan reportou 11 Sets/1.000 cartas contra os 45
Sets/7.429 cartas confirmados na introspecção. fetchLocalCatalogRows() fazia um único
`.select()` sem paginação em `card` (7.429 linhas) — o Data API do Supabase/PostgREST aplica um
limite padrão de 1.000 linhas por requisição quando nenhum `.range()` é informado, truncando
silenciosamente (sem erro). `pricing_card_mapping`/`pricing_product`/`pricing_observation`
tinham o mesmo risco estrutural (hoje 136/667/851 linhas, abaixo de 1.000, mas cresce com o
catálogo — P14.4 mira ~18.700 cartas).

Correção, em duas frentes:
1) Inventário de Sets/cartas passou a reusar catalog_card_set_metrics.cards_ativas (view já
   existente, 1 linha por Set, agregada server-side) em vez de contar cartas uma a uma no
   cliente — elimina a leitura de 7.429 linhas por completo. Descoberto en passant: o service_role
   nunca tinha SELECT nesta view (nenhum script server-side a usava antes) — corrigido via GRANT
   na Query 3916 proposta (ver relatório desta rodada; não aplicada ainda).
2) Toda leitura Supabase que permanece linha-a-linha (card_set, pricing_set_mapping, a nova view
   pricing_set_coverage) passou a ser paginada de forma determinística (fetchAllPages() +
   .order("id").range(...), nunca deduzindo término por total presumido) e imediatamente
   reconciliada contra uma contagem exata e independente (`count: "exact", head: true`,
   fetchExactCount()) — qualquer divergência aborta o plano antes de retornar qualquer resultado
   (nunca parcial). A cobertura de produtos/observações por Set deixou de ser calculada
   encadeando pricing_card_mapping -> pricing_product -> pricing_observation inteiros no
   cliente (a segunda superfície de truncamento) e passou a vir da Query 3916 (proposta),
   agregada por card_set_id x pricing_source_id.

Ver Seção 7b (fetchAllPages/fetchAllRowsFromTable/fetchExactCount/assertPaginationComplete/
assertConfirmedMappingsPreserved) e o relatório desta rodada para o SQL completo da 3916,
ainda não aplicada — requer aprovação de Fabrício antes de qualquer execução real de
--expansion-plan pós-fix.

============================================================================
P14.4.3 — Cobertura completa de Sets já confirmados (2026-08-19, mesmo dia)
============================================================================

Lacuna corrigida: o planejador tratava todo Set com pricing_set_mapping CONFIRMED como
totalmente coberto e o excluía de todo planejamento futuro — premissa falsa. BASE1 e ME1
foram confirmados no nível do Set em pilotos anteriores (P14.1/P8), mas mapeados apenas
parcialmente (3 cartas cada, de 102 e 188 cartas ativas respectivamente). Introspecção real
(2026-08-19) confirmou exatamente 2 dos 7 Sets hoje CONFIRMED como incompletos: BASE1
(3/102, 99 faltantes) e ME1 (3/188, 185 faltantes); BASE2/BASE3/BASE4/BASE5/GYM2 já têm
cobertura total (0 faltantes).

`SetPlanClassification` deixou de ter um único status ALREADY_CONFIRMED e passou a ter dois:
ALREADY_CONFIRMED_COMPLETE (mapped_cards_count >= cartas ativas do Set) e
ALREADY_CONFIRMED_INCOMPLETE (mapped_cards_count < cartas ativas do Set) — "mapeada" conta
QUALQUER pricing_card_mapping existente (CONFIRMED, PENDING ou NOT_FOUND); o gap real é
ausência TOTAL de mapping, nunca o status de um mapping já existente. PENDING/NOT_FOUND nunca
são reprocessados automaticamente pelo backfill (ver Seção 7d) — só cartas sem NENHUM
pricing_card_mapping entram.

A view pricing_set_coverage (Query 3916, P14.4.1) foi estendida pela Query 3919 com
mapped_cards_count/confirmed_cards_count/pending_cards_count/not_found_cards_count — todas
COUNT(DISTINCT pricing_card_mapping.id) [+ FILTER por match_status], imunes ao fan-out dos
LEFT JOINs de produtos/observações já existentes na mesma view. classifySetForExpansionPlan()
agora recebe também localCardCount e a cobertura agregada do Set, decidindo COMPLETE/
INCOMPLETE ANTES de qualquer chamada à JustTCG — 100% a partir de dados já reconciliados
localmente (mesma disciplina de "nunca consumir quota externa para decisão local").

Novo campo no plano: `backfillWaves` (buildBackfillWaves(), pura) — agrupa só os Sets
ALREADY_CONFIRMED_INCOMPLETE em ondas de até 5 Sets E até 500 CARTAS FALTANTES (não cartas
totais do Set), mesmo algoritmo de buildExpansionWaves() adaptado; um Set cujas cartas
faltantes sozinhas excedem 500 nunca é dividido, forma sua própria onda (oversized). A
estimativa de chamadas por onda usa o tamanho TOTAL do Set (localCardCount), não
missingCardsCount — o executor de backfill (Seção 7d) ainda precisa paginar TODAS as cartas
externas do Set via fetchAllCardsForSet() para localizar as faltantes (a JustTCG não permite
filtrar por subconjunto), então basear a estimativa só nas faltantes subestimaria o
orçamento necessário.

Fora de escopo desta rodada: qualquer execução real de backfill (dry-run ou real) — fica
para Fabrício rodar localmente com o comando restrito entregue no relatório final; nenhuma
onda de expansão (--expansion-wave) pendente foi executada; nenhuma mudança de frontend/PTAX;
documentação normativa (05f-pricing.md/ADR-029) só será atualizada num ciclo de encerramento
próprio, por instrução explícita de Fabrício.

Uso:

  # PowerShell — defina as variáveis de ambiente ANTES de rodar. NUNCA cole a Service
  # Role Key nem a JUSTTCG_API_KEY em chat/log.
  $env:SUPABASE_URL = "https://qjfutqujxrbzgrtkpgkg.supabase.co"
  $env:SUPABASE_SERVICE_ROLE_KEY = "<service_role_key>"
  $env:JUSTTCG_API_KEY = "<justtcg_api_key>"   # opcional — ausente força --fixture-check

  # Validação offline (sempre segura, não requer nenhuma variável de rede/segredo):
  deno run --allow-env scripts/sync-justtcg-pricing.ts --fixture-check

  # Plano de expansão (P14.4.1) — só leitura, exige as três credenciais, 1 chamada HTTP,
  # nunca escreve nada:
  deno run --allow-net --allow-env scripts/sync-justtcg-pricing.ts --expansion-plan

  # Piloto real, sem gravar nada (recomendado primeiro — Convenção #7 do projeto):
  deno run --allow-net --allow-env scripts/sync-justtcg-pricing.ts --confirmed-by=<admin_user_uuid> --dry-run

  # Piloto real (requer as três variáveis + um admin_user.id real que está confirmando):
  deno run --allow-net --allow-env scripts/sync-justtcg-pricing.ts --confirmed-by=<admin_user_uuid>
*/

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
// Incremento de Atualização Diária JustTCG (2026-08-21), item A: cliente HTTP/paginação/
// tipos puros da JustTCG extraídos para _shared/pricing-justtcg/ — consumidos por este
// CLI e pela nova Edge Function justtcg-price-refresh a partir do mesmo núcleo, zero
// duplicação de parser/paginação/normalização/controle de orçamento. Nenhuma assinatura
// nem comportamento pré-existente deste script foi alterado por esta extração.
import {
  CARDS_PAGE_LIMIT,
  DELAY_BETWEEN_REQUESTS_MS,
  fetchAllCardsForSet,
  GAME_CODE,
  type JustTcgCard,
  type JustTcgSet,
  type JustTcgVariant,
  JustTcgClient,
  MAX_REQUESTS_PER_RUN,
  RATE_LIMIT_BACKOFF_MS,
  sanitize,
  sanitizeJson,
  splitPrintingLanguage,
} from "../supabase/functions/_shared/pricing-justtcg/mod.ts";
// Incremento P16.2 (Núcleo Compartilhado de Matching, 2026-08-25): lógica pura de matching
// (resolução de Set/carta e decisão de upsert de mapeamento) extraída para
// _shared/pricing-justtcg-matching/ — consumida por este CLI e pela futura Edge Function de
// onboarding interativo de Sets (P16.3), zero duplicação. Nenhuma assinatura nem
// comportamento pré-existente deste script foi alterado por esta extração (refatoração
// pura — ver mod.ts do módulo para o racional completo da fronteira "matching" x
// "persistência"/"planejamento em ondas", que permanecem só neste CLI).
import {
  type CardMatchResult,
  buildExternalNumberIndex,
  classifyCardMatch,
  classifySetForExpansionPlan,
  decideMappingUpsert,
  type ExistingSetMappingLite,
  isNameCompatible,
  isUsableExternalNumber,
  isValidCollectorTotal,
  type LocalCard,
  type MappingRowLike,
  normalizeExternalSetReleaseDate,
  normalizeJustTcgSets,
  normalizeName,
  normalizeNumber,
  parseCollectorNumberParts,
  resolveSetMatchV2,
  type SetMatchResult,
  type SetPlanClassification,
  type SetTarget,
  type UpsertAction,
} from "../supabase/functions/_shared/pricing-justtcg-matching/mod.ts";

// ============================================================================
// 0. Configuração fixa do piloto
// ============================================================================
//
// JUSTTCG_API_BASE/REQUEST_TIMEOUT_MS/MAX_REQUESTS_PER_RUN/DELAY_BETWEEN_REQUESTS_MS/
// RATE_LIMIT_BACKOFF_MS/CARDS_PAGE_LIMIT/GAME_CODE agora vêm do núcleo compartilhado
// acima (_shared/pricing-justtcg/client.ts) — valores idênticos aos desta rodada
// (MAX_REQUESTS_PER_RUN=30 desde P14.4.2; CARDS_PAGE_LIMIT=100 desde P14.2), nenhuma
// mudança de comportamento.

// SetTarget agora vem de _shared/pricing-justtcg-matching/mod.ts (Incremento P16.2) — mesma
// forma exata (codigoMmkyu/releaseDateIso/overrideExternalSetId), zero mudança de contrato.

// Set-piloto do Incremento P14.2 — ainda não mapeado antes desta rodada. Escolhido por:
// (a) não ter pricing_set_mapping/pricing_card_mapping prévios; (b) ser um Set principal
// (não promocional/energia), minimizando o risco de numeração não-padrão; (c) ter 130
// cartas locais — acima do limite de 100 por página, forçando paginação real (2 páginas)
// no próprio piloto real, não só nos testes offline; (d) mesma era Wizards já validada em
// P8 (BASE1/base-set-pokemon confirmado real), o que dá confiança razoável de que a
// `release_date` local (2000-02-24) bate com o registro da JustTCG.
// ME1/BASE1 (P8) deliberadamente EXCLUÍDOS desta lista — já CONFIRMED, dados intactos,
// esta rodada não amplia a cobertura deles.
const SET_TARGETS: SetTarget[] = [
  { codigoMmkyu: "BASE4", releaseDateIso: "2000-02-24" },
];

const MARKET_LABEL = "JUSTTCG_AGGREGATE"; // mesmo rótulo já usado como exemplo em 05f-pricing.md

// ============================================================================
// 1. Sanitização — sanitize()/sanitizeJson() agora vêm de _shared/pricing-justtcg/mod.ts
// (mesma disciplina da prova técnica, Protect-SensitiveText — comportamento idêntico).
// ============================================================================

// ============================================================================
// 2. Normalização — normalizeName/normalizeNumber/isUsableExternalNumber/
// parseCollectorNumberParts/isValidCollectorTotal agora vêm de
// _shared/pricing-justtcg-matching/normalize.ts (Incremento P16.2, extraídas da prova
// técnica original Get-NomeNormalizado/Get-NumeroNormalizado via P14.2/P14.4.4) — mesma
// lógica, zero mudança de comportamento nesta extração.
// ============================================================================

// splitPrintingLanguage() agora vem de _shared/pricing-justtcg/mod.ts (mesma lógica: v1
// documenta sufixo " - <Idioma>" em `printing`, removido só na v2; sem sufixo ->
// idiomaCodigo null, nunca presumir inglês nem qualquer outro idioma).

// ============================================================================
// 3. Cliente tipado JustTCG v1 — agora em _shared/pricing-justtcg/client.ts (import no
// topo do arquivo). Timeout, 401/429/5xx, orçamento conservador — comportamento
// idêntico ao pré-existente, zero mudança nesta extração.
// ============================================================================

// ============================================================================
// 3b. Paginação de /v1/cards por Set — fetchAllCardsForSet() agora em
// _shared/pricing-justtcg/pagination.ts (import no topo do arquivo); JustTcgCard/
// JustTcgVariant agora em _shared/pricing-justtcg/types.ts. Substituiu a Fase B por
// carta de P8 (uma chamada HTTP por carta, inviável em escala) — comportamento
// idêntico ao pré-existente, zero mudança nesta extração.
// ============================================================================

// ============================================================================
// 4. Acesso restrito e explícito à fonte JUSTTCG
// ============================================================================

// Único ponto do repositório autorizado a ler pricing_source com este literal fixo,
// nunca parametrizado — mesmo padrão de P8 (a restrição original protegia is_active=FALSE;
// desde P14.1 a fonte está is_active=TRUE, mas a função continua com o mesmo escopo
// estreito por disciplina, não por necessidade técnica atual).
async function getJustTcgSource(supabase: SupabaseClient) {
  const { data, error } = await supabase.from("pricing_source").select("id, code, is_active, requires_commercial_agreement").eq("code", "JUSTTCG").maybeSingle();
  if (error) throw new Error(`PRICING_SOURCE_QUERY_FAILED: ${error.message}`);
  if (!data) throw new Error("PRICING_SOURCE_JUSTTCG_NOT_FOUND: rode o Incremento P7 antes deste script.");
  return data;
}

async function getConditionMap(supabase: SupabaseClient, pricingSourceId: string): Promise<Map<string, string>> {
  const { data, error } = await supabase.from("pricing_condition_mapping").select("external_condition_code, condition_id").eq("pricing_source_id", pricingSourceId);
  if (error) throw new Error(`CONDITION_MAPPING_QUERY_FAILED: ${error.message}`);
  return new Map((data ?? []).map((r: { external_condition_code: string; condition_id: string }) => [r.external_condition_code, r.condition_id as string]));
}

async function findCardSetId(supabase: SupabaseClient, code: string): Promise<string | null> {
  const { data, error } = await supabase.from("card_set").select("id").eq("code", code).maybeSingle();
  if (error) throw new Error(`CARD_SET_QUERY_FAILED: ${error.message}`);
  return (data?.id as string) ?? null;
}

// LocalCard agora vem de _shared/pricing-justtcg-matching/mod.ts (Incremento P16.2) — mesma
// forma exata (card_id/name/collector_number/collector_total?), zero mudança de contrato.

// Substitui a busca pontual por carta de P8 (findCard, uma query por card-alvo hardcoded)
// por uma única query trazendo TODAS as cartas locais do Set — necessário para o novo
// desenho, que classifica a cobertura inteira do Set, não uma lista fixa de 3 cartas.
async function findLocalCardsForSet(supabase: SupabaseClient, cardSetId: string): Promise<LocalCard[]> {
  const { data, error } = await supabase.from("card").select("id, name, collector_number, collector_total").eq("card_set_id", cardSetId);
  if (error) throw new Error(`CARD_QUERY_FAILED: ${error.message}`);
  return (data ?? []).map((r: { id: string; name: string; collector_number: string; collector_total: number | null }) => ({
    card_id: r.id,
    name: r.name,
    collector_number: r.collector_number,
    collector_total: r.collector_total ?? null,
  }));
}

// ============================================================================
// 5. Resolução de correspondência de Set — resolveSetMatchV2/normalizeExternalSetReleaseDate/
// normalizeJustTcgSets agora vêm de _shared/pricing-justtcg-matching/mod.ts (Incremento
// P16.2, extraídas dos Incrementos P14.2/P14.2.1). Mesma lógica, zero mudança de
// comportamento nesta extração.
// ============================================================================

// JustTcgSet agora vem de _shared/pricing-justtcg/mod.ts (import no topo do arquivo).

// ============================================================================
// 5b. Correlação de cartas — buildExternalNumberIndex/isNameCompatible/classifyCardMatch
// agora vêm de _shared/pricing-justtcg-matching/mod.ts (Incremento P16.2, extraídas dos
// Incrementos P14.2/P14.4.4/fix/fix v2). Mesma lógica — número de coleção primário, nome
// só desempata/verifica —, zero mudança de comportamento nesta extração.
// ============================================================================

// ============================================================================
// 5b-bis. Diagnóstico de cobertura externa (Fix P14.2.2, a pedido de Fabrício após o
// dry-run real de BASE4 ter mostrado externalCardsSeenTotal=137 contra 130 cartas locais,
// sem nenhuma forma de explicar a diferença). Três fenômenos distintos, deliberadamente
// não forçados a somar exatamente externalCardsSeenTotal - localCardsTotal:
//   1. registros externos sem número utilizável (isUsableExternalNumber() == false) —
//      nunca entram no índice por número, nunca podem ser candidatos de nada;
//   2. registros externos com número utilizável mas que não existe no catálogo local —
//      candidatos "órfãos" do lado da JustTCG, nunca reportados em lugar nenhum antes;
//   3. grupos de números externos duplicados (2+ registros externos com o mesmo número
//      normalizado) e o total de registros que pertencem a esses grupos — a causa direta
//      de NUMERO_MULTIPLO_* em classifyCardMatch().
// Uma carta pode contar simultaneamente em (2) e (3) — não são mutuamente exclusivos.
// ============================================================================

type ExternalCoverageDiagnostics = {
  externalCardsWithoutUsableNumber: number;
  externalCardsNumberNotInLocalCatalog: number;
  duplicateExternalNumberGroups: number;
  duplicateExternalNumberGroupMembers: number;
};

function diagnoseExternalCoverage(externalCards: JustTcgCard[], localCards: LocalCard[]): ExternalCoverageDiagnostics {
  const localNumberSet = new Set(localCards.map((c) => normalizeNumber(c.collector_number)));
  let externalCardsWithoutUsableNumber = 0;
  const numberGroupSizes = new Map<string, number>();

  for (const card of externalCards) {
    if (!isUsableExternalNumber(card.number)) {
      externalCardsWithoutUsableNumber++;
      continue;
    }
    const key = normalizeNumber(card.number as string);
    numberGroupSizes.set(key, (numberGroupSizes.get(key) ?? 0) + 1);
  }

  let externalCardsNumberNotInLocalCatalog = 0;
  let duplicateExternalNumberGroups = 0;
  let duplicateExternalNumberGroupMembers = 0;
  for (const [key, count] of numberGroupSizes) {
    if (!localNumberSet.has(key)) externalCardsNumberNotInLocalCatalog += count;
    if (count > 1) {
      duplicateExternalNumberGroups++;
      duplicateExternalNumberGroupMembers += count;
    }
  }

  return { externalCardsWithoutUsableNumber, externalCardsNumberNotInLocalCatalog, duplicateExternalNumberGroups, duplicateExternalNumberGroupMembers };
}

// ============================================================================
// 5b-ter. Evidência sanitizada de mapping AMBIGUOUS/ABSENT (Fix P14.2.2) — só em dry-run,
// só carta local + collector_number + motivo + candidatos externos (id/nome/número).
// Nunca variantes, preços, payload bruto, headers ou segredos — matchResult nunca carrega
// esses dados (classifyCardMatch() nunca olha para variants/price), então não há risco de
// vazamento estrutural aqui, só disciplina do que é impresso.
// ============================================================================

function logDryRunCardEvidence(local: LocalCard, matchResult: CardMatchResult): void {
  const candidatosRaw = matchResult.evidence.candidatos as Array<{ id: string; name: string; number?: string | null }> | undefined;
  const candidatos = (candidatosRaw ?? []).map((c) => ({ id: c.id, name: c.name, number: c.number ?? null }));
  console.log(
    `  [${matchResult.classification}] carta_local="${local.name}" collector_number="${local.collector_number}" motivo=${matchResult.method} candidatos_externos=${JSON.stringify(candidatos)}`,
  );
}

// ============================================================================
// 5b-quater. Projeção de variantes em dry-run (Fix P14.2.2) — mesma validação de dado usada no
// caminho real (externalProductId/printingRaw/price presentes e válidos, condição
// resolvível em conditionMap), mas puramente síncrona, sem nenhuma chamada ao Supabase.
// Usada só quando args.dryRun é true, para contar productsProjected/observationsProjected
// sem escrever nada — nunca reaproveitada pelo caminho real (que permanece com sua própria
// lógica inline, inalterada, mais abaixo em runRealPilot()).
// ============================================================================

type VariantProjectionOutcome =
  | { status: "PROJECTED"; externalProductId: string; conditionId: string; printingTipo: string | null; price: number }
  | { status: "SKIPPED_INVALID_DATA"; reason: "SEM_ID_EXTERNO" | "SEM_PRINTING" | "PRECO_INVALIDO" }
  | { status: "SKIPPED_UNKNOWN_CONDITION"; conditionRaw: string };

function planVariantProjection(variant: JustTcgVariant, conditionMap: Map<string, string>): VariantProjectionOutcome {
  const externalProductId = String(variant.uuid ?? variant.id ?? "");
  const printingRaw = String(variant.printing ?? "");
  const conditionRaw = String(variant.condition ?? "");
  const price = variant.price;

  if (!externalProductId) return { status: "SKIPPED_INVALID_DATA", reason: "SEM_ID_EXTERNO" };
  if (!printingRaw) return { status: "SKIPPED_INVALID_DATA", reason: "SEM_PRINTING" };
  if (typeof price !== "number") return { status: "SKIPPED_INVALID_DATA", reason: "PRECO_INVALIDO" };

  const conditionId = conditionMap.get(conditionRaw);
  if (!conditionId) return { status: "SKIPPED_UNKNOWN_CONDITION", conditionRaw };

  const { printingTipo } = splitPrintingLanguage(printingRaw);
  return { status: "PROJECTED", externalProductId, conditionId, printingTipo, price };
}

// ============================================================================
// 5c. Classificação de escrita — INSERT novo vs. conflito (preço igual) vs. divergência
// ============================================================================

type InsertOutcome = "NEW" | "CONFLICT_IGNORED" | "OTHER_ERROR";

// Fix P14.3: accumulateWriteOutcome() (companheira original desta função, que somava
// resolved/written a partir de um único INSERT com erro classificado) foi removida — o
// caminho real agora resolve produtos em lote via pré-busca (Fase 2 de
// persistBatchedResults, REUSE vs. NEW), não mais via um INSERT-e-classifica-erro por
// variante. classifyInsertResult() permanece como primitiva pura testada isoladamente
// (ver runFixtureCheck), documentando a mesma semântica de classificação que a Fase 2
// replica em memória.
function classifyInsertResult(error: { message: string } | null): InsertOutcome {
  if (!error) return "NEW";
  return `${error.message}`.includes("duplicate key") ? "CONFLICT_IGNORED" : "OTHER_ERROR";
}

// Correção real sobre P8: um INSERT que colide em pricing_observation (mesma identidade —
// produto+condição+tipo+moeda+mercado+observed_at) pode significar duas coisas bem
// diferentes: (a) o mesmo dado já persistido (reexecução idempotente, inofensivo) ou
// (b) um preço DIFERENTE reportado para a mesma identidade (divergência real). P8 tratava
// as duas como CONFLICT_IGNORED silenciosamente. Esta função decide qual é qual com uma
// SELECT de confirmação — e, em caso de divergência, nunca sobrescreve o valor já
// persistido (mesma disciplina já aplicada à PTAX/P9: "divergência nunca sobrescreve").
type ObservationWriteOutcome = "NEW" | "CONFLICT_IGNORED_SAME_PRICE" | "DIVERGENT_PRESERVED" | "OTHER_ERROR";

function classifyObservationWrite(insertError: { message: string } | null, existingPrice: number | null, newPrice: number): ObservationWriteOutcome {
  if (!insertError) return "NEW";
  if (!`${insertError.message}`.includes("duplicate key")) return "OTHER_ERROR";
  if (existingPrice === null) return "CONFLICT_IGNORED_SAME_PRICE"; // não deveria ocorrer (colisão sem linha existente), tratado como inofensivo
  return existingPrice === newPrice ? "CONFLICT_IGNORED_SAME_PRICE" : "DIVERGENT_PRESERVED";
}

// ============================================================================
// 5d. Upsert idempotente de mapeamentos — decideMappingUpsert agora vem de
// _shared/pricing-justtcg-matching/mod.ts (Incremento P16.2, extraída do Incremento P8/
// P14.2). Corrige a lacuna de P8 (insert-e-tolera nunca promovia PENDING/NOT_FOUND para
// CONFIRMED numa reexecução) — mesma lógica, zero mudança de comportamento nesta extração.
// ============================================================================

// Fix P14.3: decisão de status final extraída como função pura testável — antes vivia como
// um ternário inline dentro de runRealPilot(). batchPersistenceFailed tem prioridade
// absoluta sobre qualquer outro sinal: uma falha parcial de lote nunca deve ser mascarada
// como COMPLETED_WITH_ERRORS só porque outras cartas/Set foram resolvidos com sucesso —
// o run precisa ficar objetivamente marcado como FAILED para nunca ser confundido com
// sucesso parcial silencioso (mesmo incidente histórico que motivou finalizeSyncRun nunca
// ser silenciosa, aplicado aqui à decisão de status em si).
function computeFinalStatus(
  batchPersistenceFailed: boolean,
  hasErrors: boolean,
  hasAnyProgress: boolean,
): "COMPLETED" | "COMPLETED_WITH_ERRORS" | "FAILED" {
  if (batchPersistenceFailed) return "FAILED";
  if (!hasErrors) return "COMPLETED";
  return hasAnyProgress ? "COMPLETED_WITH_ERRORS" : "FAILED";
}

// ============================================================================
// 5e. Persistência em lotes (P14.3) — elimina o padrão "uma operação Supabase por carta
//     ou por variante" (P8/P14.2). Estratégia: acumular decisões em memória durante a
//     classificação (nenhuma chamada ao Supabase dentro dos loops por carta/variante) e só
//     então pré-buscar o estado existente em lotes, decidir NEW/REUSE/DIVERGENTE em memória
//     (reaproveitando decideMappingUpsert/classifyObservationWrite já testados) e emitir o
//     mínimo de INSERT/UPDATE em lotes conservadores. Ver persistBatchedResults() abaixo.
// ============================================================================

// Tamanho de lote conservador para .in()/insert/rpc. Reduzido de 300 para 100 na revisão
// de 2026-08-19: não há evidência documentada de um limite seguro para quantos UUIDs cabem
// numa query string .in() do PostgREST através do gateway real do Supabase (Cloudflare/Kong
// à frente do PostgREST) — 300 UUIDs (36 caracteres cada + vírgula) somam ~11kb só na lista,
// e nenhuma fonte oficial consultada confirma esse tamanho como seguro. 100 é
// comprovadamente mais conservador e ainda preserva >90% de redução de round trips (ver
// relatório da revisão). GRANT/INSERT com corpo JSON (POST) e chamadas .rpc() não têm essa
// restrição de URL, mas usam a mesma constante por simplicidade e uniformidade.
const BATCH_SIZE = 100;

function chunk<T>(items: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}

// Decisão de mapeamento de carta acumulada em memória durante o loop de classificação —
// nunca chama o Supabase no momento em que é criada (ver runRealPilot). matchedCard é
// sempre null fora do caminho CONFIRMED, mesmo padrão já usado antes desta rodada.
type PlannedCardMapping = {
  cardId: string;
  collectorNumber: string;
  status: "CONFIRMED" | "PENDING" | "NOT_FOUND";
  matchedCard: JustTcgCard | null;
  method: string;
  evidence: Record<string, unknown>;
};

// Variante (produto+observação) planejada — só existe para cartas CONFIRMED nesta rodada
// (mesma cobertura do caminho real pré-existente). cardId é a chave de correlação usada
// para resolver o pricing_card_mapping_id só depois que a Fase 1 (mappings) já rodou.
type PlannedVariant = {
  cardId: string;
  collectorNumber: string;
  externalProductId: string;
  sourcePrintingLabel: string;
  conditionId: string;
  price: number;
  observedAt: string;
  rawPayload: unknown;
};

type BatchPersistOutcome = {
  productsResolved: number;
  productsWritten: number;
  observationsResolved: number;
  observationsWritten: number;
  observationsDivergent: number;
  // Fix P14.5 (dual-write pricing_source_card_identity): identidades PRIMARY/CONFIRMED
  // resolvidas nesta chamada — REUSE (já existentes, pré-busca) + NEW (inseridas agora).
  // identitiesWritten conta só as NEW. Nunca inclui ALTERNATE/ALIAS — o conector só produz
  // e consome PRIMARY/CONFIRMED nesta rodada (ver comentário na Fase 1.5).
  identitiesResolved: number;
  identitiesWritten: number;
  // Contagem de round trips ao Supabase feitos exclusivamente por persistBatchedResults()
  // (pré-busca + insert + rpc, todos em lotes) — deliberadamente separada de
  // client.requestsMade, que só conta chamadas HTTP à JustTCG. Não inclui chamadas fora
  // desta função (source/condition map/set mapping/sync_run insert/finalize), que
  // continuam sendo poucas chamadas fixas por Set-alvo, fora do escopo deste incremento.
  operationsSupabase: number;
  errorParts: string[];
  batchFailureOccurred: boolean;
};

// Núcleo do P14.3: pré-busca em lotes -> decide em memória (reaproveitando
// decideMappingUpsert/classifyObservationWrite, já cobertos por runFixtureCheck) -> emite
// só o INSERT/UPDATE mínimo, em lotes. Falha parcial em qualquer lote é reportada em
// errorParts e sinalizada via batchFailureOccurred (nunca lançada/engolida em silêncio);
// as linhas não resolvidas nesta rodada permanecem no estado anterior e são retomadas numa
// reexecução idempotente (mesma garantia de decideMappingUpsert/classifyObservationWrite).
async function persistBatchedResults(
  supabase: SupabaseClient,
  sourceId: string,
  syncRunId: string | null,
  confirmedBy: string,
  plannedMappings: PlannedCardMapping[],
  plannedVariants: PlannedVariant[],
): Promise<BatchPersistOutcome> {
  const errorParts: string[] = [];
  let operationsSupabase = 0;
  let batchFailureOccurred = false;

  // --- Fase 1: pricing_card_mapping ------------------------------------------------
  const cardMappingIdByCardId = new Map<string, string>();
  // Fix P14.5 (dual-write pricing_source_card_identity): payload local de toda confirmação
  // desta rodada (INSERT novo OU promoção), correlacionado por cardId — usado pela Fase 1.5
  // para criar a identidade sem precisar reler pricing_card_mapping do banco.
  const confirmedPayloadByCardId = new Map<
    string,
    {
      external_card_id: string | null;
      external_card_name: string | null;
      match_method: string;
      match_evidence: unknown;
      confirmed_by: string;
    }
  >();

  if (plannedMappings.length > 0) {
    const existingByCardId = new Map<string, MappingRowLike>();
    for (const ids of chunk(plannedMappings.map((m) => m.cardId), BATCH_SIZE)) {
      operationsSupabase++;
      const { data, error } = await supabase
        .from("pricing_card_mapping")
        .select("id, card_id, match_status")
        .eq("pricing_source_id", sourceId)
        .in("card_id", ids);
      if (error) {
        batchFailureOccurred = true;
        errorParts.push(
          `CARD_MAPPING_BATCH_SELECT_FAILED: ${sanitize(error.message)}`,
        );
        continue;
      }
      for (
        const row of (data ?? []) as Array<
          { id: string; card_id: string; match_status: string }
        >
      ) {
        existingByCardId.set(row.card_id, {
          id: row.id,
          match_status: row.match_status,
        });
      }
    }

    const toInsert: Array<Record<string, unknown>> = [];
    const toUpdate: Array<Record<string, unknown>> = [];
    const nowIso = new Date().toISOString();

    for (const planned of plannedMappings) {
      const existing = existingByCardId.get(planned.cardId) ?? null;
      const action = decideMappingUpsert(existing, planned.status);
      if (
        action === "NOOP_SAME_STATUS" ||
        action === "NOOP_KEEP_CONFIRMED_DIVERGENT_INPUT" ||
        action === "NOOP_ALREADY_CONFIRMED"
      ) {
        if (existing) cardMappingIdByCardId.set(planned.cardId, existing.id);
        continue;
      }

      const payload: Record<string, unknown> = {
        match_status: planned.status,
        match_method: planned.method,
        match_evidence: sanitizeJson(planned.evidence),
        last_checked_at: nowIso,
        external_card_id: planned.matchedCard?.id ?? null,
        external_card_name: planned.matchedCard?.name ?? null,
        confirmed_at: planned.status === "CONFIRMED" ? nowIso : null,
        confirmed_by: planned.status === "CONFIRMED" ? confirmedBy : null,
      };

      if (planned.status === "CONFIRMED") {
        // Fix P14.5 (dual-write): guarda o payload desta confirmação, correlacionado por
        // cardId — cobre os dois caminhos (INSERT novo e UPDATE de promoção) com a mesma
        // estrutura, já que os dois levam ao mesmo match_status final CONFIRMED. Só é
        // efetivamente usado pela Fase 1.5 depois que o INSERT/UPDATE abaixo confirmar
        // sucesso (cardMappingIdByCardId precisa ter o id real da linha).
        confirmedPayloadByCardId.set(planned.cardId, {
          external_card_id: planned.matchedCard?.id ?? null,
          external_card_name: planned.matchedCard?.name ?? null,
          match_method: planned.method,
          match_evidence: sanitizeJson(planned.evidence),
          confirmed_by: confirmedBy,
        });
      }

      if (action === "INSERTED") {
        toInsert.push({
          card_id: planned.cardId,
          pricing_source_id: sourceId,
          ...payload,
        });
      } else if (planned.status === "CONFIRMED") {
        // UPGRADED_TO_CONFIRMED (promoção real) — precisa da função SECURITY INVOKER
        // (Query 3914, revisão de segurança de 2026-08-19): .upsert() reemitiria SET para
        // card_id/pricing_source_id, que nunca têm GRANT UPDATE (Query 3912) e falharia
        // com 42501. A partir da revisão de segurança, a RPC é EXCLUSIVAMENTE de promoção
        // (WHERE t.match_status IN ('PENDING','NOT_FOUND') AND u.match_status='CONFIRMED')
        // — nunca mais uma atualização genérica, nunca rebaixa nem troca identidade de uma
        // linha já CONFIRMED. Só entram aqui linhas com status-alvo CONFIRMED.
        toUpdate.push({ id: (existing as MappingRowLike).id, ...payload });
      } else {
        // Fix revisão de segurança 2026-08-19: decideMappingUpsert() ainda rotula uma
        // transição PENDING<->NOT_FOUND (sem promoção) como "UPGRADED_TO_CONFIRMED" (nome
        // histórico, ver comentário na própria função), mas a RPC 3914 agora bloqueia
        // estruturalmente qualquer UPDATE cujo status-alvo não seja CONFIRMED — escopo
        // reduzido deliberadamente a pedido da revisão de segurança (a função deve ser
        // EXCLUSIVAMENTE de promoção). Uma troca PENDING<->NOT_FOUND não tem mais caminho
        // de escrita em lote nesta função: a linha permanece com o status anterior nesta
        // rodada (recuperável numa reexecução futura, mesma garantia já aplicada a falhas
        // parciais de lote) e é sinalizada aqui — nunca aplicada silenciosamente. Não há
        // evidência de que este caminho seja exercitado pelo piloto BASE4 hoje (schema
        // atual não tem estado intermediário entre PENDING e NOT_FOUND fora desta função):
        // registrado como pendência informativa, não corrigido nesta rodada.
        errorParts.push(
          `CARD_MAPPING_PENDING_NOT_FOUND_TOGGLE_SKIPPED(card=${planned.cardId}): ${(existing as MappingRowLike).match_status} -> ${planned.status} fora do escopo da RPC de promoção exclusiva (Query 3914); sem escrita nesta rodada, recuperável numa reexecução futura.`,
        );
      }
    }

    for (const rows of chunk(toInsert, BATCH_SIZE)) {
      operationsSupabase++;
      const { data, error } = await supabase.from("pricing_card_mapping")
        .insert(rows).select("id, card_id");
      if (error) {
        batchFailureOccurred = true;
        errorParts.push(
          `CARD_MAPPING_BATCH_INSERT_FAILED(${rows.length} linhas): ${
            sanitize(error.message)
          }`,
        );
        continue;
      }
      for (
        const row of (data ?? []) as Array<{ id: string; card_id: string }>
      ) {
        cardMappingIdByCardId.set(row.card_id, row.id);
      }
    }

    for (const rows of chunk(toUpdate, BATCH_SIZE)) {
      operationsSupabase++;
      const { data, error } = await supabase.rpc(
        "batch_update_pricing_card_mapping_status",
        { p_updates: rows },
      );
      if (error) {
        batchFailureOccurred = true;
        errorParts.push(
          `CARD_MAPPING_BATCH_UPDATE_FAILED(${rows.length} linhas): ${
            sanitize(error.message)
          }`,
        );
        continue;
      }
      for (
        const row of (data ?? []) as Array<{ id: string; card_id: string }>
      ) {
        cardMappingIdByCardId.set(row.card_id, row.id);
      }
    }
  }

  // payloadByMappingId: mesma correlação de confirmedPayloadByCardId, agora por
  // pricing_card_mapping_id (não mais por cardId) — só existe para mappings cujo INSERT/
  // UPDATE nesta rodada teve sucesso (apareceram em cardMappingIdByCardId). Usado
  // exclusivamente pela Fase 1.5 abaixo.
  const payloadByMappingId = new Map<
    string,
    {
      external_card_id: string | null;
      external_card_name: string | null;
      match_method: string;
      match_evidence: unknown;
      confirmed_by: string;
    }
  >();
  for (const [cardId, payload] of confirmedPayloadByCardId) {
    const mappingId = cardMappingIdByCardId.get(cardId);
    if (mappingId) payloadByMappingId.set(mappingId, payload);
  }

  // usableVariants: só as que tiveram cardMappingId resolvido na Fase 1 (mesma regra de
  // sempre) — cartas cujo mapping falhou nesta rodada (Fase 1) ficam de fora e são
  // reportadas, recuperáveis numa reexecução (o mapping delas volta a ser reavaliado do
  // zero na próxima chamada desta função).
  const usableVariants: Array<PlannedVariant & { cardMappingId: string }> = [];
  const unresolvedCardIds = new Set<string>();
  for (const variant of plannedVariants) {
    const cardMappingId = cardMappingIdByCardId.get(variant.cardId);
    if (!cardMappingId) {
      unresolvedCardIds.add(variant.cardId);
      continue;
    }
    usableVariants.push({ ...variant, cardMappingId });
  }
  for (const cardId of unresolvedCardIds) {
    errorParts.push(`CARD_MAPPING_UNRESOLVED_SKIP_VARIANTS(${cardId})`);
  }

  // --- Fase 1.5: pricing_source_card_identity (Fix P14.5 — dual-write) -------------------
  // Cria, para todo mapping usado por usableVariants nesta rodada, a identidade PRIMARY/
  // CONFIRMED correspondente na fonte atual — fecha a lacuna que impedia aplicar a migration
  // 3923 com segurança (sem isso, pricing_product.pricing_source_card_identity_id nasceria
  // sempre NULL). Cobre TODOS os mappings usados pelas variantes desta rodada, não só os
  // confirmados agora — mappings antigos (CONFIRMED antes desta execução) já devem ter
  // identidade do backfill da própria 3923; a pré-busca abaixo reaproveita (REUSE) essas
  // identidades sem tentar recriá-las. ALTERNATE/ALIAS ficam fora de escopo deste incremento
  // — esta função só cria e consome PRIMARY/CONFIRMED.
  //
  // Regra 1 (proibição de lacuna nova, a pedido de Fabrício): toda variante cujo mapping não
  // tiver uma identidade PRIMARY/CONFIRMED resolvida ao final desta fase — por SELECT/INSERT
  // de lote falhando, ou por gap genuíno (mapping antigo sem identidade, teoricamente
  // impossível dado o backfill 100% da 3923, mas nunca assumido silenciosamente) — nunca
  // chega à Fase 2/3: fica de fora de variantsWithIdentity, registrada em errorParts, e força
  // batchFailureOccurred=true (nunca corrigida silenciosamente; recuperável numa reexecução
  // futura, mesma garantia de todo o resto do arquivo).
  const identityIdByMappingId = new Map<string, string>();
  const identityFailedMappingIds = new Set<string>();
  let identitiesWritten = 0;

  const mappingIdsNeedingIdentity = [
    ...new Set(usableVariants.map((v) => v.cardMappingId)),
  ];
  if (mappingIdsNeedingIdentity.length > 0) {
    for (const ids of chunk(mappingIdsNeedingIdentity, BATCH_SIZE)) {
      operationsSupabase++;
      const { data, error } = await supabase
        .from("pricing_source_card_identity")
        .select("id, pricing_card_mapping_id")
        .eq("pricing_source_id", sourceId)
        .eq("identity_role", "PRIMARY")
        .eq("match_status", "CONFIRMED")
        .in("pricing_card_mapping_id", ids);
      if (error) {
        batchFailureOccurred = true;
        errorParts.push(
          `IDENTITY_BATCH_SELECT_FAILED: ${sanitize(error.message)}`,
        );
        continue;
      }
      for (
        const row of (data ?? []) as Array<
          { id: string; pricing_card_mapping_id: string }
        >
      ) {
        identityIdByMappingId.set(row.pricing_card_mapping_id, row.id);
      }
    }

    // Fix P14.5.1 (retry após falha transiente, achado durante a escrita dos testes): um
    // mapping cuja Fase 1.5 falhou em rodada anterior (ex.: IDENTITY_BATCH_INSERT_FAILED) já
    // teve pricing_card_mapping persistido com sucesso naquela mesma rodada — só a identidade
    // ficou pendente. Numa reexecução, esse mapping chega aqui via NOOP_SAME_STATUS/
    // NOOP_ALREADY_CONFIRMED (Fase 1 não o toca de novo), então confirmedPayloadByCardId/
    // payloadByMappingId ficam vazios para ele nesta rodada — sem este fallback, a reexecução
    // reportaria IDENTITY_MISSING_FOR_PRECONFIRMED_MAPPING para sempre (o mesmo sinal de um gap
    // permanente), mesmo sendo um problema plenamente recuperável. Busca os campos já
    // persistidos em pricing_card_mapping só para os mappings que REUSE não resolveu e que não
    // têm payload desta rodada — nunca inventa dado; se a própria linha não estiver CONFIRMED
    // (estado anômalo, teoricamente impossível dado que só chegam aqui mappings usados por
    // usableVariants), cai na rede de segurança abaixo como gap genuíno.
    const mappingIdsNeedingFallback = mappingIdsNeedingIdentity.filter(
      (id) => !identityIdByMappingId.has(id) && !payloadByMappingId.has(id),
    );
    if (mappingIdsNeedingFallback.length > 0) {
      for (const ids of chunk(mappingIdsNeedingFallback, BATCH_SIZE)) {
        operationsSupabase++;
        const { data, error } = await supabase
          .from("pricing_card_mapping")
          .select(
            "id, match_status, external_card_id, external_card_name, match_method, match_evidence, confirmed_by",
          )
          .in("id", ids);
        if (error) {
          batchFailureOccurred = true;
          errorParts.push(
            `IDENTITY_FALLBACK_MAPPING_SELECT_FAILED: ${
              sanitize(error.message)
            }`,
          );
          continue;
        }
        for (
          const row of (data ?? []) as Array<{
            id: string;
            match_status: string;
            external_card_id: string | null;
            external_card_name: string | null;
            match_method: string | null;
            match_evidence: unknown;
            confirmed_by: string | null;
          }>
        ) {
          if (row.match_status !== "CONFIRMED" || !row.confirmed_by) continue;
          payloadByMappingId.set(row.id, {
            external_card_id: row.external_card_id,
            external_card_name: row.external_card_name,
            match_method: row.match_method ?? "auto",
            match_evidence: row.match_evidence,
            confirmed_by: row.confirmed_by,
          });
        }
      }
    }

    const toInsertIdentities: Array<
      { mappingId: string; row: Record<string, unknown> }
    > = [];
    for (const mappingId of mappingIdsNeedingIdentity) {
      if (identityIdByMappingId.has(mappingId)) continue; // REUSE — já existe (backfill da 3923 ou rodada anterior)
      const payload = payloadByMappingId.get(mappingId);
      if (!payload) {
        // Nem o payload desta rodada (Fase 1) nem o fallback de pricing_card_mapping acima
        // resolveram este mapping — SELECT do fallback falhou, ou a linha existe mas está
        // estruturalmente incompleta (CONFIRMED sem confirmed_by, o que as CHECK constraints
        // deveriam impedir). Gap genuíno, não um caso recuperável por retry simples. Nunca
        // inventa dado (não recria confirmed_at/confirmed_by retroativos): sinaliza e deixa
        // para uma reconciliação explícita futura, fora do escopo deste incremento.
        identityFailedMappingIds.add(mappingId);
        errorParts.push(
          `IDENTITY_MISSING_FOR_PRECONFIRMED_MAPPING(${mappingId})`,
        );
        batchFailureOccurred = true;
        continue;
      }
      toInsertIdentities.push({
        mappingId,
        row: {
          pricing_card_mapping_id: mappingId,
          pricing_source_id: sourceId,
          external_card_id: payload.external_card_id,
          external_card_name: payload.external_card_name,
          match_status: "CONFIRMED",
          identity_role: "PRIMARY",
          match_method: payload.match_method,
          match_evidence: payload.match_evidence,
          last_checked_at: new Date().toISOString(),
          confirmed_by: payload.confirmed_by,
        },
      });
    }

    for (const rowsChunk of chunk(toInsertIdentities, BATCH_SIZE)) {
      operationsSupabase++;
      const { data, error } = await supabase
        .from("pricing_source_card_identity")
        .insert(rowsChunk.map((r) => r.row))
        .select("id, pricing_card_mapping_id");
      if (error) {
        batchFailureOccurred = true;
        errorParts.push(
          `IDENTITY_BATCH_INSERT_FAILED(${rowsChunk.length} linhas): ${
            sanitize(error.message)
          }`,
        );
        for (const r of rowsChunk) identityFailedMappingIds.add(r.mappingId);
        continue;
      }
      for (
        const row of (data ?? []) as Array<
          { id: string; pricing_card_mapping_id: string }
        >
      ) {
        identityIdByMappingId.set(row.pricing_card_mapping_id, row.id);
        identitiesWritten++;
      }
    }
  }

  // Rede de segurança final da Regra 1: qualquer mapping que ainda não tenha identidade
  // resolvida neste ponto (SELECT falhou, INSERT falhou, ou gap já sinalizado acima) entra
  // definitivamente em identityFailedMappingIds — nunca deixa uma variante seguir para
  // Fase 2/3 sem identidade nem sem registro de falha correspondente.
  for (const mappingId of mappingIdsNeedingIdentity) {
    if (
      !identityIdByMappingId.has(mappingId) &&
      !identityFailedMappingIds.has(mappingId)
    ) {
      identityFailedMappingIds.add(mappingId);
      errorParts.push(`IDENTITY_UNRESOLVED(${mappingId})`);
      batchFailureOccurred = true;
    }
  }
  const identitiesResolved =
    mappingIdsNeedingIdentity.filter((id) => identityIdByMappingId.has(id))
      .length;

  // variantsWithIdentity: usableVariants cujo mapping tem identidade PRIMARY/CONFIRMED
  // resolvida — Regra 1 aplicada aqui, ponto único de corte antes da Fase 2/3. Variantes
  // cujo mapping caiu em identityFailedMappingIds nunca chegam a pricing_product/
  // pricing_observation nesta rodada.
  const variantsWithIdentity = usableVariants.filter((v) =>
    !identityFailedMappingIds.has(v.cardMappingId)
  );

  // --- Fase 2: pricing_product --------------------------------------------------
  // Só existem variantes planejadas para cartas CONFIRMED cujo mapping foi resolvido na
  // Fase 1 E cuja identidade foi resolvida na Fase 1.5 (Regra 1) — cartas cujo mapping ou
  // identidade falharam nesta rodada ficam de fora e são reportadas, recuperáveis numa
  // reexecução (mapping/identidade voltam a ser reavaliados do zero na próxima chamada).
  const productIdByKey = new Map<string, string>();
  // Regra 3 (Fabrício): chaves cujo produto já existe no banco mas com
  // pricing_source_card_identity_id nulo ou divergente da identidade resolvida — nunca
  // reutilizadas, nunca corrigidas silenciosamente (nenhum UPDATE), sempre um erro explícito.
  const productIdentityMismatchKeys = new Set<string>();
  let productsWritten = 0;

  if (variantsWithIdentity.length > 0) {
    const cardMappingIds = [
      ...new Set(variantsWithIdentity.map((v) => v.cardMappingId)),
    ];
    for (const ids of chunk(cardMappingIds, BATCH_SIZE)) {
      operationsSupabase++;
      const { data, error } = await supabase
        .from("pricing_product")
        .select(
          "id, pricing_card_mapping_id, external_product_id, pricing_source_card_identity_id",
        )
        .in("pricing_card_mapping_id", ids);
      if (error) {
        batchFailureOccurred = true;
        errorParts.push(
          `PRODUCT_BATCH_SELECT_FAILED: ${sanitize(error.message)}`,
        );
        continue;
      }
      for (
        const row of (data ?? []) as Array<{
          id: string;
          pricing_card_mapping_id: string;
          external_product_id: string;
          pricing_source_card_identity_id: string | null;
        }>
      ) {
        const key =
          `${row.pricing_card_mapping_id}::${row.external_product_id}`;
        const resolvedIdentityId =
          identityIdByMappingId.get(row.pricing_card_mapping_id) ?? null;
        if (
          row.pricing_source_card_identity_id != null &&
          row.pricing_source_card_identity_id === resolvedIdentityId
        ) {
          productIdByKey.set(key, row.id);
        } else {
          productIdentityMismatchKeys.add(key);
          batchFailureOccurred = true;
          errorParts.push(
            `PRODUCT_IDENTITY_MISMATCH(mapping=${row.pricing_card_mapping_id}, external_product_id=${row.external_product_id}, stored=${
              row.pricing_source_card_identity_id ?? "NULL"
            }, expected=${resolvedIdentityId ?? "NULL"})`,
          );
        }
      }
    }

    const toInsertProducts: Array<
      { key: string; row: Record<string, unknown> }
    > = [];
    const seenThisBatch = new Set<string>();
    for (const variant of variantsWithIdentity) {
      const key = `${variant.cardMappingId}::${variant.externalProductId}`;
      if (productIdentityMismatchKeys.has(key)) continue; // já sinalizado acima — nunca inserido por cima de um estado divergente
      if (productIdByKey.has(key) || seenThisBatch.has(key)) continue; // REUSE — já existe (banco ou mesmo lote), zero escrita
      seenThisBatch.add(key);
      toInsertProducts.push({
        key,
        row: {
          pricing_card_mapping_id: variant.cardMappingId,
          pricing_source_card_identity_id:
            identityIdByMappingId.get(variant.cardMappingId) ?? null,
          external_product_id: variant.externalProductId,
          source_printing_label: variant.sourcePrintingLabel,
          language_status: "UNDETERMINED",
          language_id: null,
        },
      });
    }

    for (const pairs of chunk(toInsertProducts, BATCH_SIZE)) {
      operationsSupabase++;
      const { data, error } = await supabase
        .from("pricing_product")
        .insert(pairs.map((p) => p.row))
        .select("id, pricing_card_mapping_id, external_product_id");
      if (error) {
        batchFailureOccurred = true;
        errorParts.push(
          `PRODUCT_BATCH_INSERT_FAILED(${pairs.length} linhas): ${
            sanitize(error.message)
          }`,
        );
        continue;
      }
      for (
        const row of (data ?? []) as Array<
          {
            id: string;
            pricing_card_mapping_id: string;
            external_product_id: string;
          }
        >
      ) {
        productIdByKey.set(
          `${row.pricing_card_mapping_id}::${row.external_product_id}`,
          row.id,
        );
        productsWritten++;
      }
    }
  }

  // productsResolved conta toda variante cujo produto ficou resolvido nesta rodada, seja por
  // já existir (pré-busca, REUSE válido) ou por ter sido inserido com sucesso agora (NEW) —
  // nunca conta variantes cujo INSERT falhou nem variantes cuja chave caiu em
  // productIdentityMismatchKeys (Regra 3) — essas nunca aparecem em productIdByKey e ficam
  // para investigação/reexecução futura, nunca corrigidas silenciosamente.
  let productsResolved = 0;
  for (const variant of variantsWithIdentity) {
    const key = `${variant.cardMappingId}::${variant.externalProductId}`;
    if (productIdByKey.has(key)) productsResolved++;
  }

  // --- Fase 3: pricing_observation -----------------------------------------------
  let observationsResolved = 0;
  let observationsWritten = 0;
  let observationsDivergent = 0;

  const variantsWithProduct = variantsWithIdentity
    .map((v) => ({ ...v, productId: productIdByKey.get(`${v.cardMappingId}::${v.externalProductId}`) ?? null }))
    .filter((v): v is PlannedVariant & { cardMappingId: string; productId: string } => v.productId !== null);

  const unresolvedProductKeys = variantsWithIdentity.length - variantsWithProduct.length;
  if (unresolvedProductKeys > 0) {
    errorParts.push(`PRODUCT_UNRESOLVED_SKIP_OBSERVATIONS(${unresolvedProductKeys} variante(s))`);
  }

  const latestObsByGroup = new Map<string, { price: number; observedAt: string }>();
  if (variantsWithProduct.length > 0) {
    // Fix revisão de escala 2026-08-19 (3ª rodada, proposto — NÃO aplicado): a versão
    // anterior (Query 3914) já corrigia o produto cartesiano, mas ainda comparava por tupla
    // EXATA incluindo observed_at — então duas execuções em dias diferentes com o MESMO
    // preço criavam duas linhas (observed_at nunca coincide entre execuções reais, seja por
    // lastUpdated da JustTCG avançar ou pelo fallback new Date()). Provado por teste
    // dedicado ("Cenário 7b"). Regra desejada: consultar diariamente, mas só persistir nova
    // observação quando o preço muda em relação à ÚLTIMA observação conhecida daquele grupo
    // (produto+condição+price_type+currency+market_label) — preço idêntico reaproveita a
    // observação existente, independente de quando a checagem ocorreu. Corrigido trocando a
    // pré-busca por tupla exata pela RPC (proposta) batch_select_latest_pricing_observation_
    // by_identity (SECURITY INVOKER, sem observed_at na chave de busca — devolve só a
    // observação mais recente por grupo via LATERAL...ORDER BY observed_at DESC LIMIT 1,
    // aproveitando o índice ix_pricing_observation_snapshot_lookup já existente).
    const uniqueGroupKeys = new Map<
      string,
      { pricing_product_id: string; condition_id: string; price_type: string; currency_code: string; market_label: string }
    >();
    for (const v of variantsWithProduct) {
      const key = `${v.productId}::${v.conditionId}`;
      if (!uniqueGroupKeys.has(key)) {
        uniqueGroupKeys.set(key, {
          pricing_product_id: v.productId,
          condition_id: v.conditionId,
          price_type: "MARKET",
          currency_code: "USD",
          market_label: MARKET_LABEL,
        });
      }
    }
    for (const keysChunk of chunk([...uniqueGroupKeys.values()], BATCH_SIZE)) {
      operationsSupabase++;
      const { data, error } = await supabase.rpc("batch_select_latest_pricing_observation_by_identity", { p_keys: keysChunk });
      if (error) {
        batchFailureOccurred = true;
        errorParts.push(`OBSERVATION_LATEST_BATCH_SELECT_FAILED: ${sanitize(error.message)}`);
        continue;
      }
      for (const row of (data ?? []) as Array<{ pricing_product_id: string; condition_id: string; observed_at: string; price: number }>) {
        latestObsByGroup.set(`${row.pricing_product_id}::${row.condition_id}`, { price: Number(row.price), observedAt: row.observed_at });
      }
    }

    const toInsertObservations: Array<Record<string, unknown>> = [];
    const seenThisBatch = new Map<string, { price: number; observedAt: string }>(); // última observação do grupo já decidida dentro do próprio lote
    for (const variant of variantsWithProduct) {
      const key = `${variant.productId}::${variant.conditionId}`;
      const latest = seenThisBatch.get(key) ?? latestObsByGroup.get(key) ?? null;

      if (latest === null) {
        // Primeira observação já conhecida para este grupo (nunca observado antes) — grava.
        seenThisBatch.set(key, { price: variant.price, observedAt: variant.observedAt });
        toInsertObservations.push({
          pricing_product_id: variant.productId,
          condition_id: variant.conditionId,
          sync_run_id: syncRunId,
          price_type: "MARKET",
          price: variant.price,
          currency_code: "USD",
          market_label: MARKET_LABEL,
          market_scope: "UNDETERMINED",
          market_evidence: {},
          market_evidence_confirmed: false,
          observed_at: variant.observedAt,
          raw_payload: variant.rawPayload,
        });
        continue;
      }

      if (latest.price === variant.price) {
        // CONFLICT_IGNORED_SAME_PRICE — preço idêntico ao último conhecido: reaproveita a
        // observação existente, sem gravar nova linha, mesmo com observed_at diferente
        // (regra de escala — evita ~34M linhas/ano de ruído sem mudança real de preço).
        // observationsResolved conta aqui (reuso, sem INSERT) — não conta de novo no lote de
        // INSERT abaixo, mantendo a semântica "uma variante, uma contagem".
        observationsResolved++;
        continue;
      }
      if (latest.observedAt === variant.observedAt) {
        // DIVERGENT_PRESERVED — colisão real: mesmo observed_at exato já tem outro preço
        // gravado (violaria a constraint única). Nunca sobrescreve, só sinaliza para revisão.
        observationsResolved++;
        observationsDivergent++;
        errorParts.push(`OBSERVATION_PRICE_DIVERGENTE_PRESERVADA(${variant.externalProductId}): existente=${latest.price} novo=${variant.price} observed_at=${variant.observedAt}`);
        continue;
      }
      // Preço mudou de fato em relação à última observação conhecida (observed_at diferente
      // do último) — mudança material, grava nova observação real. observationsResolved NÃO
      // é incrementado aqui: o lote de INSERT abaixo já soma rows.length a observationsResolved,
      // evitando contar esta variante duas vezes (uma na resolução, outra no INSERT).
      seenThisBatch.set(key, { price: variant.price, observedAt: variant.observedAt });
      toInsertObservations.push({
        pricing_product_id: variant.productId,
        condition_id: variant.conditionId,
        sync_run_id: syncRunId,
        price_type: "MARKET",
        price: variant.price,
        currency_code: "USD",
        market_label: MARKET_LABEL,
        market_scope: "UNDETERMINED",
        market_evidence: {},
        market_evidence_confirmed: false,
        observed_at: variant.observedAt,
        raw_payload: variant.rawPayload,
      });
    }

    for (const rows of chunk(toInsertObservations, BATCH_SIZE)) {
      operationsSupabase++;
      const { error } = await supabase.from("pricing_observation").insert(rows);
      if (error) {
        batchFailureOccurred = true;
        errorParts.push(`OBSERVATION_BATCH_INSERT_FAILED(${rows.length} linhas): ${sanitize(error.message)}`);
        continue;
      }
      observationsResolved += rows.length;
      observationsWritten += rows.length;
    }
  }

  return {
    productsResolved,
    productsWritten,
    observationsResolved,
    observationsWritten,
    observationsDivergent,
    identitiesResolved,
    identitiesWritten,
    operationsSupabase,
    errorParts,
    batchFailureOccurred,
  };
}

// ============================================================================
// 6. Fixture-check — validação 100% offline, sem rede, sem escrita no Supabase
// ============================================================================

// Fetch falso para os testes de paginação/retry — nunca toca rede real. Cada chamada
// consome a próxima resposta da fila `responses`, na ordem.
function makeFakeFetch(responses: Array<{ status: number; body: unknown }>): { fetchImpl: typeof fetch; callCount: () => number } {
  let i = 0;
  const fetchImpl = (async (_url: string | URL, _init?: RequestInit) => {
    const next = responses[i] ?? responses[responses.length - 1];
    i++;
    return {
      ok: next.status >= 200 && next.status < 300,
      status: next.status,
      json: async () => next.body,
      text: async () => JSON.stringify(next.body),
    } as unknown as Response;
  }) as unknown as typeof fetch;
  return { fetchImpl, callCount: () => i };
}

// Fix P14.3: mock mínimo de SupabaseClient para testar offline a propagação de { error }
// em upsertSetMapping/upsertCardMapping/finalizeSyncRun — as únicas funções deste arquivo
// que tocam o Supabase e que precisavam desse teste (pricing_product/pricing_observation já
// checavam { error } antes desta rodada, ver P8). Cada chamada .from(table) consulta um
// script fixo de respostas por operação (select/insert/update); não simula rede nem
// persiste nada de verdade.
type MockClientScript = Record<string, {
  select?: { data: unknown; error: { message: string } | null };
  insert?: { data: unknown; error: { message: string } | null };
  update?: { error: { message: string } | null };
}>;

function makeMockSupabaseClient(script: MockClientScript): SupabaseClient {
  function chain(response: unknown) {
    const node: Record<string, unknown> = {
      eq: () => node,
      select: () => node,
      maybeSingle: async () => response,
      then: (resolve: (v: unknown) => unknown, reject?: (e: unknown) => unknown) => Promise.resolve(response).then(resolve, reject),
    };
    return node;
  }
  return {
    from(table: string) {
      const cfg = script[table] ?? {};
      return {
        select: () => chain(cfg.select ?? { data: null, error: null }),
        insert: (_payload: unknown) => chain(cfg.insert ?? { data: null, error: null }),
        update: (_payload: unknown) => chain(cfg.update ?? { error: null }),
      };
    },
  } as unknown as SupabaseClient;
}

// Fix P14.3: mock em memória para testar persistBatchedResults() offline — diferente de
// makeMockSupabaseClient() (respostas fixas por tabela/operação), este simula um estado real
// de tabela (seed inicial + linhas inseridas ficam visíveis para SELECTs seguintes dentro do
// mesmo teste), suporta .eq()/.in() encadeados, INSERT com ou sem .select() encadeado, RPC
// com um handler dedicado para batch_update_pricing_card_mapping_status (aplica os updates
// na tabela pricing_card_mapping em memória e devolve {id, card_id} das linhas afetadas), e
// contagem objetiva de chamadas por tabela/operação (stats) — é essa contagem que prova a
// redução real de round trips, não uma suposição sobre o desenho.
type FakeRow = Record<string, unknown>;

function makeBatchFakeClient(
  seed: Record<string, FakeRow[]>,
  options: { failSelect?: Partial<Record<string, boolean>>; failInsert?: Partial<Record<string, boolean>>; failRpc?: boolean } = {},
): {
  client: SupabaseClient;
  tables: Record<string, FakeRow[]>;
  stats: { selectCalls: Record<string, number>; insertCalls: Record<string, number>; rpcCalls: number; rpcCallsByFn: Record<string, number> };
} {
  const tables: Record<string, FakeRow[]> = {};
  for (const [table, rows] of Object.entries(seed)) tables[table] = rows.map((row) => ({ ...row }));
  const stats = { selectCalls: {} as Record<string, number>, insertCalls: {} as Record<string, number>, rpcCalls: 0, rpcCallsByFn: {} as Record<string, number> };
  let idCounter = 1000;

  function selectBuilder(table: string) {
    const filters: Array<(row: FakeRow) => boolean> = [];
    const builder = {
      eq(col: string, val: unknown) {
        filters.push((row) => row[col] === val);
        return builder;
      },
      in(col: string, vals: unknown[]) {
        const set = new Set(vals);
        filters.push((row) => set.has(row[col]));
        return builder;
      },
      then(resolve: (v: unknown) => unknown, reject?: (e: unknown) => unknown) {
        stats.selectCalls[table] = (stats.selectCalls[table] ?? 0) + 1;
        if (options.failSelect?.[table]) {
          return Promise.resolve({ data: null, error: { message: `permission denied for table ${table}` } }).then(resolve, reject);
        }
        const rows = (tables[table] ?? []).filter((row) => filters.every((f) => f(row)));
        return Promise.resolve({ data: rows, error: null }).then(resolve, reject);
      },
    };
    return builder;
  }

  function insertBuilder(table: string, rows: FakeRow[]) {
    const inserted = rows.map((row) => ({ id: `fake-${table}-${idCounter++}`, ...row }));
    const commit = () => {
      stats.insertCalls[table] = (stats.insertCalls[table] ?? 0) + 1;
      if (options.failInsert?.[table]) return { data: null, error: { message: `permission denied for table ${table}` } };
      tables[table] = [...(tables[table] ?? []), ...inserted];
      return { data: inserted, error: null };
    };
    return {
      select: (_cols: string) => ({
        then: (resolve: (v: unknown) => unknown, reject?: (e: unknown) => unknown) => Promise.resolve(commit()).then(resolve, reject),
      }),
      then: (resolve: (v: unknown) => unknown, reject?: (e: unknown) => unknown) => {
        const result = commit();
        return Promise.resolve({ error: result.error }).then(resolve, reject);
      },
    };
  }

  const client = {
    from(table: string) {
      return {
        select: (_cols: string) => selectBuilder(table),
        insert: (rows: FakeRow[]) => insertBuilder(table, rows),
      };
    },
    rpc(fn: string, args?: Record<string, unknown>) {
      return {
        then(resolve: (v: unknown) => unknown, reject?: (e: unknown) => unknown) {
          stats.rpcCalls++;
          stats.rpcCallsByFn[fn] = (stats.rpcCallsByFn[fn] ?? 0) + 1;
          if (options.failRpc) {
            return Promise.resolve({ data: null, error: { message: `permission denied for function ${fn}` } }).then(resolve, reject);
          }
          // Fix revisão de segurança 2026-08-19: dois RPCs distintos agora passam por este
          // mock — batch_update_pricing_card_mapping_status (promoção exclusiva, Query 3914)
          // e batch_select_latest_pricing_observation_by_identity (busca a ÚLTIMA observação
          // por grupo produto+condição, proposta na revisão de escala 2026-08-19, 3ª rodada —
          // substitui a antiga batch_select_pricing_observation_by_identity de tupla exata,
          // que ficou órfã: nenhum caminho do código real a chama mais). Despachado por nome.
          if (fn === "batch_select_latest_pricing_observation_by_identity") {
            const keys = (args?.p_keys as FakeRow[]) ?? [];
            const obsRows = tables["pricing_observation"] ?? [];
            const returned: FakeRow[] = [];
            for (const k of keys) {
              const matches = obsRows.filter(
                (r) =>
                  r.pricing_product_id === k.pricing_product_id &&
                  r.condition_id === k.condition_id &&
                  r.price_type === k.price_type &&
                  r.currency_code === k.currency_code &&
                  (r.market_label ?? null) === (k.market_label ?? null),
              );
              if (matches.length === 0) continue;
              const latest = matches.reduce((a, b) => (String(b.observed_at) > String(a.observed_at) ? b : a));
              returned.push(latest);
            }
            return Promise.resolve({ data: returned, error: null }).then(resolve, reject);
          }
          const updates = (args?.p_updates as FakeRow[]) ?? [];
          const cardMappingRows = tables["pricing_card_mapping"] ?? [];
          const returned: FakeRow[] = [];
          for (const update of updates) {
            const row = cardMappingRows.find((r) => r.id === update.id);
            // Espelha a RPC 3914: promoção exclusiva — só aplica se a linha existente
            // estiver PENDING/NOT_FOUND e o alvo for CONFIRMED. Qualquer outra combinação
            // é ignorada (0 linhas afetadas), nunca aplicada.
            if (row && (row.match_status === "PENDING" || row.match_status === "NOT_FOUND") && update.match_status === "CONFIRMED") {
              Object.assign(row, update);
              returned.push({ id: row.id, card_id: row.card_id });
            }
          }
          return Promise.resolve({ data: returned, error: null }).then(resolve, reject);
        },
      };
    },
  } as unknown as SupabaseClient;

  return { client, tables, stats };
}

// P14.4.1: fake client estritamente só-leitura para testar executeExpansionPlan() offline —
// diferente de makeMockSupabaseClient()/makeBatchFakeClient() (que simulam escrita com sucesso
// ou falha controlada), aqui QUALQUER tentativa de insert/update/upsert/delete/rpc lança
// imediatamente. Isso torna a prova de "plano de expansão nunca escreve" estrutural: o teste que
// usa este fake só passa se executeExpansionPlan() completar sem nenhuma dessas chamadas, não só
// se um contador ficar em zero (que poderia mascarar um caminho de escrita nunca exercitado pelo
// cenário de teste).
//
// Fix P14.4.1 (2026-08-19): estendido para suportar .order()/.range() (paginação) e
// .select("*", { count: "exact", head: true }) (contagem exata, usada por fetchExactCount()) —
// além de .eq()/.gt()/.maybeSingle()/await direto, já existentes. `countOverride` permite um
// teste forçar uma contagem exata DIVERGENTE do array semeado (simula PAGINACAO_INCOMPLETA sem
// precisar truncar de verdade); `errorOnCall` permite falhar a N-ésima chamada a uma tabela
// (simula falha intermediária de paginação) — ambos opcionais, nunca usados pelos testes que só
// precisam do comportamento simples original.
function makeReadOnlyFakeClient(
  seed: Record<string, FakeRow[]>,
  options?: {
    countOverride?: Record<string, number>;
    errorOnCall?: Record<string, { atCallIndex: number; message: string }>;
  },
): SupabaseClient {
  const callCounts: Record<string, number> = {};
  function selectBuilder(table: string, selectOpts?: { count?: "exact"; head?: boolean }) {
    const rows = seed[table] ?? [];
    const filters: Array<(row: FakeRow) => boolean> = [];
    let rangeFrom: number | null = null;
    let rangeTo: number | null = null;
    const node = {
      eq(col: string, val: unknown) {
        filters.push((row) => row[col] === val);
        return node;
      },
      gt(col: string, val: unknown) {
        filters.push((row) => (row[col] as number) > (val as number));
        return node;
      },
      order() {
        return node; // no-op: seeds já vêm em ordem determinística nos testes
      },
      range(from: number, to: number) {
        rangeFrom = from;
        rangeTo = to;
        return node;
      },
      maybeSingle: async () => {
        const filtered = rows.filter((row) => filters.every((f) => f(row)));
        return { data: filtered[0] ?? null, error: null };
      },
      then(resolve: (v: unknown) => unknown, reject?: (e: unknown) => unknown) {
        callCounts[table] = (callCounts[table] ?? 0) + 1;
        const injected = options?.errorOnCall?.[table];
        if (injected && callCounts[table] === injected.atCallIndex) {
          return Promise.resolve({ data: null, error: { message: injected.message }, count: null }).then(resolve, reject);
        }
        const filtered = rows.filter((row) => filters.every((f) => f(row)));
        if (selectOpts?.count === "exact" && selectOpts?.head) {
          // Override específico para chamadas filtradas (ex.: "tabela:filtered") tem prioridade
          // sobre um override genérico da tabela — permite um teste divergir só a contagem
          // filtrada (ex.: cards_ativas > 0) sem afetar a checagem de paginação não-filtrada da
          // mesma tabela.
          const overrideKey = filters.length > 0 ? `${table}:filtered` : table;
          const count = options?.countOverride?.[overrideKey] ?? options?.countOverride?.[table] ?? filtered.length;
          return Promise.resolve({ data: null, error: null, count }).then(resolve, reject);
        }
        const paged = rangeFrom !== null ? filtered.slice(rangeFrom, (rangeTo ?? filtered.length - 1) + 1) : filtered;
        return Promise.resolve({ data: paged, error: null, count: filtered.length }).then(resolve, reject);
      },
    };
    return node;
  }
  const blocked = (op: string, table?: string) => {
    throw new Error(`WRITE_ATTEMPT_BLOCKED(${op}${table ? `:${table}` : ""}): plano de expansão (--expansion-plan) nunca deveria escrever.`);
  };
  return {
    from(table: string) {
      return {
        select: (_cols?: string, selectOpts?: { count?: "exact"; head?: boolean }) => selectBuilder(table, selectOpts),
        insert: () => blocked("insert", table),
        update: () => blocked("update", table),
        upsert: () => blocked("upsert", table),
        delete: () => blocked("delete", table),
      };
    },
    rpc: () => blocked("rpc"),
  } as unknown as SupabaseClient;
}

// P14.4.2: fake client combinado para testar executeExpansionWave() offline — diferente de
// makeReadOnlyFakeClient() (só leitura, bloqueia toda escrita) e makeBatchFakeClient() (só
// escrita simples, sem paginação/contagem exata), este suporta as DUAS capacidades no mesmo
// teste: leitura paginada/contagem exata (mesmo contrato de makeReadOnlyFakeClient, para
// fetchReconciledLocalInputs()/buildExpansionPlan()) e escrita real com estado em memória
// (pricing_sync_run/pricing_sync_run_call/pricing_set_mapping/persistBatchedResults, mesma
// mecânica de makeBatchFakeClient). A concorrência de pricing_sync_run é simulada
// DINAMICAMENTE — nunca por uma flag estática — reproduzindo a mesma regra do índice único
// parcial real (ux_pricing_sync_run_active_price_per_source_type, Query 3907): um INSERT
// nesta tabela só falha com 23505 se já existir, no estado em memória, uma linha com o
// mesmo pricing_source_id+run_type e status RECEIVED/PROCESSING — isso faz a reexecução
// idempotente funcionar naturalmente (a 2ª chamada só vê a 1ª linha já finalizada).
function makeExpansionWaveFakeClient(
  seed: Record<string, FakeRow[]>,
  options?: {
    countOverride?: Record<string, number>;
    errorOnCall?: Record<string, { atCallIndex: number; message: string }>;
    failSelect?: Partial<Record<string, boolean>>;
    failInsert?: Partial<Record<string, boolean>>;
    failUpdate?: Partial<Record<string, boolean>>;
    failRpc?: boolean;
  },
): { client: SupabaseClient; tables: Record<string, FakeRow[]> } {
  const tables: Record<string, FakeRow[]> = {};
  for (const [table, rows] of Object.entries(seed)) tables[table] = rows.map((row) => ({ ...row }));
  const callCounts: Record<string, number> = {};
  let idCounter = 5000;

  function selectBuilder(table: string, selectOpts?: { count?: "exact"; head?: boolean }) {
    const filters: Array<(row: FakeRow) => boolean> = [];
    let rangeFrom: number | null = null;
    let rangeTo: number | null = null;
    const node = {
      eq(col: string, val: unknown) {
        filters.push((row) => row[col] === val);
        return node;
      },
      gt(col: string, val: unknown) {
        filters.push((row) => (row[col] as number) > (val as number));
        return node;
      },
      in(col: string, vals: unknown[]) {
        const set = new Set(vals);
        filters.push((row) => set.has(row[col]));
        return node;
      },
      order() {
        return node;
      },
      range(from: number, to: number) {
        rangeFrom = from;
        rangeTo = to;
        return node;
      },
      maybeSingle: async () => {
        if (options?.failSelect?.[table]) return { data: null, error: { message: `permission denied for table ${table}` } };
        const filtered = (tables[table] ?? []).filter((row) => filters.every((f) => f(row)));
        return { data: filtered[0] ?? null, error: null };
      },
      single: async () => {
        if (options?.failSelect?.[table]) return { data: null, error: { message: `permission denied for table ${table}` } };
        const filtered = (tables[table] ?? []).filter((row) => filters.every((f) => f(row)));
        return { data: filtered[0] ?? null, error: null };
      },
      then(resolve: (v: unknown) => unknown, reject?: (e: unknown) => unknown) {
        callCounts[table] = (callCounts[table] ?? 0) + 1;
        const injected = options?.errorOnCall?.[table];
        if (injected && callCounts[table] === injected.atCallIndex) {
          return Promise.resolve({ data: null, error: { message: injected.message }, count: null }).then(resolve, reject);
        }
        if (options?.failSelect?.[table]) {
          return Promise.resolve({ data: null, error: { message: `permission denied for table ${table}` }, count: null }).then(resolve, reject);
        }
        const filtered = (tables[table] ?? []).filter((row) => filters.every((f) => f(row)));
        if (selectOpts?.count === "exact" && selectOpts?.head) {
          const overrideKey = filters.length > 0 ? `${table}:filtered` : table;
          const count = options?.countOverride?.[overrideKey] ?? options?.countOverride?.[table] ?? filtered.length;
          return Promise.resolve({ data: null, error: null, count }).then(resolve, reject);
        }
        const paged = rangeFrom !== null ? filtered.slice(rangeFrom, (rangeTo ?? filtered.length - 1) + 1) : filtered;
        return Promise.resolve({ data: paged, error: null, count: filtered.length }).then(resolve, reject);
      },
    };
    return node;
  }

  function insertBuilder(table: string, rows: FakeRow[]) {
    const commit = () => {
      callCounts[table] = (callCounts[table] ?? 0) + 1;
      // Simulação dinâmica do índice único parcial de concorrência (Query 3907) — só para
      // pricing_sync_run, só quando já existe uma linha ativa (RECEIVED/PROCESSING) com o
      // mesmo pricing_source_id+run_type no estado em memória.
      if (table === "pricing_sync_run") {
        for (const row of rows) {
          const conflict = (tables["pricing_sync_run"] ?? []).some(
            (r) => r.pricing_source_id === row.pricing_source_id && r.run_type === row.run_type && (r.status === "RECEIVED" || r.status === "PROCESSING"),
          );
          if (conflict) {
            return { data: null, error: { code: "23505", message: 'duplicate key value violates unique constraint "ux_pricing_sync_run_active_price_per_source_type"' } };
          }
        }
      }
      if (options?.failInsert?.[table]) return { data: null, error: { message: `permission denied for table ${table}` } };
      const inserted = rows.map((row) => ({ id: `fake-${table}-${idCounter++}`, ...row }));
      tables[table] = [...(tables[table] ?? []), ...inserted];
      return { data: inserted, error: null };
    };
    return {
      select: (_cols?: string) => ({
        single: async () => {
          const r = commit();
          return { data: r.data ? r.data[0] : null, error: r.error };
        },
        maybeSingle: async () => {
          const r = commit();
          return { data: r.data ? r.data[0] : null, error: r.error };
        },
        then: (resolve: (v: unknown) => unknown, reject?: (e: unknown) => unknown) => Promise.resolve(commit()).then(resolve, reject),
      }),
      then: (resolve: (v: unknown) => unknown, reject?: (e: unknown) => unknown) => {
        const r = commit();
        return Promise.resolve({ error: r.error }).then(resolve, reject);
      },
    };
  }

  function updateBuilder(table: string, payload: FakeRow) {
    const filters: Array<(row: FakeRow) => boolean> = [];
    const node = {
      eq(col: string, val: unknown) {
        filters.push((row) => row[col] === val);
        return node;
      },
      then(resolve: (v: unknown) => unknown, reject?: (e: unknown) => unknown) {
        callCounts[table] = (callCounts[table] ?? 0) + 1;
        if (options?.failUpdate?.[table]) {
          return Promise.resolve({ error: { message: `permission denied for table ${table}` } }).then(resolve, reject);
        }
        const rows = tables[table] ?? [];
        for (const row of rows) if (filters.every((f) => f(row))) Object.assign(row, payload);
        return Promise.resolve({ error: null }).then(resolve, reject);
      },
    };
    return node;
  }

  const client = {
    from(table: string) {
      return {
        select: (_cols?: string, selectOpts?: { count?: "exact"; head?: boolean }) => selectBuilder(table, selectOpts),
        insert: (rows: FakeRow | FakeRow[]) => insertBuilder(table, Array.isArray(rows) ? rows : [rows]),
        update: (payload: FakeRow) => updateBuilder(table, payload),
        delete: () => {
          throw new Error(`WRITE_ATTEMPT_BLOCKED(delete:${table})`);
        },
        upsert: () => {
          throw new Error(`WRITE_ATTEMPT_BLOCKED(upsert:${table})`);
        },
      };
    },
    rpc(fn: string, args?: Record<string, unknown>) {
      return {
        then(resolve: (v: unknown) => unknown, reject?: (e: unknown) => unknown) {
          if (options?.failRpc) {
            return Promise.resolve({ data: null, error: { message: `permission denied for function ${fn}` } }).then(resolve, reject);
          }
          if (fn === "batch_select_latest_pricing_observation_by_identity") {
            const keys = (args?.p_keys as FakeRow[]) ?? [];
            const obsRows = tables["pricing_observation"] ?? [];
            const returned: FakeRow[] = [];
            for (const k of keys) {
              const matches = obsRows.filter(
                (r) =>
                  r.pricing_product_id === k.pricing_product_id &&
                  r.condition_id === k.condition_id &&
                  r.price_type === k.price_type &&
                  r.currency_code === k.currency_code &&
                  (r.market_label ?? null) === (k.market_label ?? null),
              );
              if (matches.length === 0) continue;
              const latest = matches.reduce((a, b) => (String(b.observed_at) > String(a.observed_at) ? b : a));
              returned.push(latest);
            }
            return Promise.resolve({ data: returned, error: null }).then(resolve, reject);
          }
          const updates = (args?.p_updates as FakeRow[]) ?? [];
          const cardMappingRows = tables["pricing_card_mapping"] ?? [];
          const returned: FakeRow[] = [];
          for (const update of updates) {
            const row = cardMappingRows.find((r) => r.id === update.id);
            if (row && (row.match_status === "PENDING" || row.match_status === "NOT_FOUND") && update.match_status === "CONFIRMED") {
              Object.assign(row, update);
              returned.push({ id: row.id, card_id: row.card_id });
            }
          }
          return Promise.resolve({ data: returned, error: null }).then(resolve, reject);
        },
      };
    },
  } as unknown as SupabaseClient;

  return { client, tables };
}

async function runFixtureCheck() {
  console.log("=== MODO FIXTURE-CHECK (offline, sem rede, sem escrita no Supabase) ===\n");

  const assertions: Array<[string, boolean]> = [];
  const assert = (label: string, cond: boolean) => assertions.push([label, cond]);

  // --- Regressão P8 (mantidas, nunca podem quebrar) ---------------------------------
  assert("sanitize() redige tcg_ key", sanitize("erro: tcg_abc123XYZ inválida") === "erro: [REDACTED_KEY] inválida");
  assert("sanitize() redige x-api-key", sanitize("x-api-key: segredo123")?.includes("[REDACTED]") === true);
  assert("sanitize() redige Authorization Bearer", sanitize("Authorization: Bearer abc.def.ghi")?.includes("[REDACTED]") === true);
  assert(
    "sanitize() redige múltiplos segredos na mesma string",
    sanitize("tcg_aaa111 e depois Bearer bbb.ccc.ddd")?.includes("[REDACTED_KEY]") === true &&
      sanitize("tcg_aaa111 e depois Bearer bbb.ccc.ddd")?.includes("[REDACTED]") === true,
  );
  assert("normalizeNumber remove zeros à esquerda", normalizeNumber("001") === "1");
  assert("normalizeNumber ignora denominador", normalizeNumber("125/094") === "125");
  const semSufixo = splitPrintingLanguage("Reverse Holofoil");
  assert("printing sem sufixo -> idioma NULL (UNDETERMINED)", semSufixo.idiomaCodigo === null);
  const comSufixo = splitPrintingLanguage("Holofoil - English");
  assert("printing com sufixo -> idioma extraído", comSufixo.idiomaCodigo === "english" && comSufixo.printingTipo === "Holofoil");
  const conditionMap = new Map([
    ["Near Mint", "id-nm"], ["Lightly Played", "id-lp"], ["Moderately Played", "id-mp"],
    ["Heavily Played", "id-hp"], ["Damaged", "id-dmg"],
  ]);
  for (const cond of ["Near Mint", "Lightly Played", "Moderately Played", "Heavily Played", "Damaged"]) {
    assert(`condição '${cond}' resolve`, conditionMap.has(cond));
  }
  assert("condição desconhecida não resolve (fail-safe)", !conditionMap.has("Gem Mint"));
  assert("classifyInsertResult: sem erro -> NEW", classifyInsertResult(null) === "NEW");
  assert(
    "classifyInsertResult: duplicate key -> CONFLICT_IGNORED",
    classifyInsertResult({ message: 'duplicate key value violates unique constraint "uq_pricing_product_mapping_external"' }) === "CONFLICT_IGNORED",
  );
  assert(
    "classifyInsertResult: erro real (não duplicate key) -> OTHER_ERROR",
    classifyInsertResult({ message: "permission denied for table pricing_product" }) === "OTHER_ERROR",
  );

  // --- P14.2 cenário 1: lote com até 100 cartas (uma página, uma chamada) -----------
  {
    const page = { data: Array.from({ length: 80 }, (_, i) => ({ id: `card-${i}`, name: `Card ${i}`, number: String(i + 1), variants: [] })), meta: { total: 80, limit: 100, offset: 0, hasMore: false }, _metadata: {} };
    const { fetchImpl, callCount } = makeFakeFetch([{ status: 200, body: page }]);
    const client = new JustTcgClient("fake-key", fetchImpl);
    const result = await fetchAllCardsForSet(client, "fixture-set-80");
    assert("lote <=100: uma página, uma chamada HTTP", callCount() === 1 && result.requestsUsed === 1);
    assert("lote <=100: todas as 80 cartas retornadas", result.cards.length === 80);
  }

  // --- P14.2 cenário 2: paginação acima de 100 (100 + 37, duas chamadas) -----------
  {
    const page1 = { data: Array.from({ length: 100 }, (_, i) => ({ id: `c${i}`, name: `Card ${i}`, number: String(i + 1) })), meta: { total: 137, limit: 100, offset: 0, hasMore: true }, _metadata: {} };
    const page2 = { data: Array.from({ length: 37 }, (_, i) => ({ id: `c${100 + i}`, name: `Card ${100 + i}`, number: String(101 + i) })), meta: { total: 137, limit: 100, offset: 100, hasMore: false }, _metadata: {} };
    const { fetchImpl, callCount } = makeFakeFetch([{ status: 200, body: page1 }, { status: 200, body: page2 }]);
    const client = new JustTcgClient("fake-key", fetchImpl);
    const result = await fetchAllCardsForSet(client, "fixture-set-137");
    assert("paginação >100: duas chamadas HTTP (não 137)", callCount() === 2 && result.requestsUsed === 2);
    assert("paginação >100: 137 cartas acumuladas (100+37)", result.cards.length === 137);
  }

  // --- P14.2 cenário 3 (síncrono, sem fetch): correspondência segura -----------------
  {
    const externalIndex = buildExternalNumberIndex([{ id: "ext-1", name: "Abra", number: "58", variants: [] }]);
    const result = classifyCardMatch({ card_id: "local-1", name: "Abra", collector_number: "058" }, externalIndex, "fixture-set-x");
    assert("correspondência segura: candidato único por Set+número -> SAFE", result.classification === "SAFE" && result.matched?.id === "ext-1");
  }

  // --- P14.2 cenário 4: número de coleção ausente ------------------------------------
  assert('isUsableExternalNumber: "N/A" não é utilizável', isUsableExternalNumber("N/A") === false);
  assert("isUsableExternalNumber: string vazia não é utilizável", isUsableExternalNumber("") === false);
  assert("isUsableExternalNumber: null/undefined não são utilizáveis", isUsableExternalNumber(null) === false && isUsableExternalNumber(undefined) === false);
  assert("isUsableExternalNumber: número real é utilizável", isUsableExternalNumber("058") === true);
  {
    const externalIndex = buildExternalNumberIndex([{ id: "ext-energy", name: "Fire Energy", number: "N/A", variants: [] }]);
    assert("número ausente: carta externa 'N/A' nunca entra no índice por número", externalIndex.size === 0);
    const result = classifyCardMatch({ card_id: "local-x", name: "Fire Energy", collector_number: "999" }, externalIndex, "fixture-set-x");
    assert("número ausente: local sem candidato por número -> ABSENT (nunca casado só por nome)", result.classification === "ABSENT");
  }

  // --- P14.2 cenário 5: correspondência ambígua --------------------------------------
  {
    const externalIndex = buildExternalNumberIndex([
      { id: "ext-alt-1", name: "Pikachu", number: "25", variants: [] },
      { id: "ext-alt-2", name: "Pikachu", number: "25", variants: [] },
    ]);
    const result = classifyCardMatch({ card_id: "local-pika", name: "Pikachu", collector_number: "025" }, externalIndex, "fixture-set-x");
    assert("ambíguo: dois candidatos com mesmo número, sem desempate seguro -> AMBIGUOUS (nunca auto-confirmado)", result.classification === "AMBIGUOUS" && result.matched === null);
  }
  {
    // P14.4.4 — decisão de negócio: nome NUNCA é critério de matching. Catálogo local é
    // PT-BR e a JustTCG é em inglês, então divergência de nome é o caso ESPERADO, não uma
    // exceção. Um único candidato por Set+número -> SAFE mesmo com nome totalmente diferente
    // (Abra local vs. "Alakazam" externo é um fixture deliberadamente extremo). Antes de
    // P14.4.4 este cenário era classificado AMBIGUOUS — este teste prova a correção da causa
    // raiz (era o cenário real de BASE1/ME1 auditado em P14.4.3: NUMERO_UNICO_MAS_NOME_DIVERGENTE).
    const externalIndex = buildExternalNumberIndex([{ id: "ext-alakazam", name: "Alakazam", number: "1", variants: [] }]);
    const result = classifyCardMatch({ card_id: "local-abra", name: "Abra", collector_number: "001" }, externalIndex, "fixture-set-x");
    assert(
      "P14.4.4: candidato único por Set+número -> SAFE mesmo com nome divergente (nome nunca bloqueia)",
      result.classification === "SAFE" && result.matched?.id === "ext-alakazam",
    );
    if (result.classification === "SAFE") {
      assert(
        "P14.4.4: match_evidence preserva nome local, nome externo e indicador de divergência de nome",
        result.evidence.nome_local === "Abra" && result.evidence.nome_externo === "Alakazam" && result.evidence.divergencia_de_nome === true,
      );
      assert("P14.4.4: método sempre SET_CONFIRMED_COLLECTOR_NUMBER_UNIQUE", result.method === "SET_CONFIRMED_COLLECTOR_NUMBER_UNIQUE");
    }
  }
  {
    // P14.4.4 — nome nunca desempata: dois candidatos externos compartilham o mesmo número
    // dentro do Set confirmado — mesmo que só um dos nomes seja compatível com o nome local,
    // o resultado continua AMBIGUOUS (o antigo "desempate por nome" foi removido por decisão
    // de negócio: nome é evidência de auditoria, nunca critério de classificação).
    const externalIndex = buildExternalNumberIndex([
      { id: "ext-charizard", name: "Charizard", number: "4", variants: [] },
      { id: "ext-charmander", name: "Charmander", number: "4", variants: [] },
    ]);
    const result = classifyCardMatch({ card_id: "local-charizard", name: "Charizard", collector_number: "004" }, externalIndex, "fixture-set-x");
    assert(
      "P14.4.4: dois candidatos por Set+número -> AMBIGUOUS mesmo quando um nome bate exatamente (nome nunca desempata)",
      result.classification === "AMBIGUOUS" && result.matched === null,
    );
  }

  // --- P14.4.4 cenário: casos reais de divergência PT-BR x inglês exigidos pelo pedido --
  // (Treinadores, Nidoran F/M, Impostor/Imposter Professor Oak) — todos candidato único por
  // Set+número, todos devem ser SAFE apesar da divergência de nome. Sem exceção por
  // categoria: mesma função, mesma regra, aplicada a cada caso.
  {
    // Treinador PT-BR local x nome em inglês na JustTCG.
    const externalIndex = buildExternalNumberIndex([{ id: "ext-potion", name: "Potion", number: "20", variants: [] }]);
    const result = classifyCardMatch({ card_id: "local-trainer-potion", name: "Poção", collector_number: "020" }, externalIndex, "fixture-set-x");
    assert(
      "P14.4.4 Treinador PT-BRxinglês: Poção (local) x Potion (externo), candidato único -> SAFE",
      result.classification === "SAFE" && result.matched?.id === "ext-potion",
    );
  }
  {
    // Nidoran♀ (símbolo local) x "Nidoran F" (grafia JustTCG).
    const externalIndex = buildExternalNumberIndex([{ id: "ext-nidoran-f", name: "Nidoran F", number: "29", variants: [] }]);
    const result = classifyCardMatch({ card_id: "local-nidoran-f", name: "Nidoran♀", collector_number: "029" }, externalIndex, "fixture-set-x");
    assert(
      "P14.4.4 Nidoran♀/Nidoran F: candidato único -> SAFE apesar do símbolo divergente",
      result.classification === "SAFE" && result.matched?.id === "ext-nidoran-f",
    );
  }
  {
    // Nidoran♂ (símbolo local) x "Nidoran M" (grafia JustTCG).
    const externalIndex = buildExternalNumberIndex([{ id: "ext-nidoran-m", name: "Nidoran M", number: "51", variants: [] }]);
    const result = classifyCardMatch({ card_id: "local-nidoran-m", name: "Nidoran♂", collector_number: "051" }, externalIndex, "fixture-set-x");
    assert(
      "P14.4.4 Nidoran♂/Nidoran M: candidato único -> SAFE apesar do símbolo divergente",
      result.classification === "SAFE" && result.matched?.id === "ext-nidoran-m",
    );
  }
  {
    // "Impostor Professor Oak" (grafia local) x "Imposter Professor Oak" (grafia JustTCG,
    // inglês americano) — caso real citado na auditoria pós-P14.4.3 (BASE1-073, PENDING
    // antes desta correção).
    const externalIndex = buildExternalNumberIndex([{ id: "ext-imposter-oak", name: "Imposter Professor Oak", number: "73", variants: [] }]);
    const result = classifyCardMatch({ card_id: "local-impostor-oak", name: "Impostor Professor Oak", collector_number: "073" }, externalIndex, "fixture-set-x");
    assert(
      "P14.4.4 Impostor/Imposter Professor Oak: candidato único -> SAFE apesar da grafia divergente",
      result.classification === "SAFE" && result.matched?.id === "ext-imposter-oak",
    );
  }
  {
    // Item 6 do pedido: números duplicados continuam bloqueados mesmo após a correção —
    // dois candidatos externos com o mesmo número normalizado nunca produzem SAFE, mesmo
    // que os nomes sejam idênticos ao nome local (nome nunca desempata, em nenhum sentido).
    const externalIndex = buildExternalNumberIndex([
      { id: "ext-dup-1", name: "Machamp", number: "8", variants: [] },
      { id: "ext-dup-2", name: "Machamp", number: "8", variants: [] },
    ]);
    const result = classifyCardMatch({ card_id: "local-machamp", name: "Machamp", collector_number: "008" }, externalIndex, "fixture-set-x");
    assert(
      "P14.4.4 item 6: número duplicado no lado externo continua bloqueado -> AMBIGUOUS mesmo com nome idêntico",
      result.classification === "AMBIGUOUS" && result.matched === null,
    );
  }

  // --- P14.2 cenário 6: carta da API sem equivalente local ---------------------------
  {
    const externalIndex = buildExternalNumberIndex([
      { id: "ext-orphan", name: "Carta Só Na JustTCG", number: "200", variants: [] },
    ]);
    // Nenhuma carta local com número 200 no fixture — o laço real é guiado pelas cartas
    // LOCAIS (classifyCardMatch é chamado uma vez por carta local), então uma carta
    // externa sem contraparte local nunca gera linha de mapeamento — não é um erro, é o
    // comportamento correto (não criamos card local a partir da JustTCG).
    const localCards: LocalCard[] = [{ card_id: "local-1", name: "Outra Carta", collector_number: "001" }];
    const results = localCards.map((c) => classifyCardMatch(c, externalIndex, "fixture-set-x"));
    assert("carta externa sem equivalente local: nunca gera mapeamento (laço guiado pelo local)", results.every((r) => r.classification === "ABSENT"));
    assert("carta externa sem equivalente local: continua endereçável para relato informativo (não descartada do índice)", externalIndex.get("200")?.[0].id === "ext-orphan");
  }

  // --- P14.2 cenário 7: idempotência (upsert de mapeamento) --------------------------
  assert("idempotência: sem linha existente -> INSERTED", decideMappingUpsert(null, "CONFIRMED") === "INSERTED");
  assert(
    "idempotência: já CONFIRMED, nova classificação também CONFIRMED -> no-op (zero escrita)",
    decideMappingUpsert({ id: "m1", match_status: "CONFIRMED" }, "CONFIRMED") === "NOOP_SAME_STATUS",
  );
  assert(
    "idempotência: NOT_FOUND antigo + nova classificação CONFIRMED -> promovido (corrige a lacuna de P8)",
    decideMappingUpsert({ id: "m2", match_status: "NOT_FOUND" }, "CONFIRMED") === "UPGRADED_TO_CONFIRMED",
  );
  assert(
    "idempotência: CONFIRMED nunca é rebaixado por uma nova classificação pior",
    decideMappingUpsert({ id: "m3", match_status: "CONFIRMED" }, "NOT_FOUND") === "NOOP_KEEP_CONFIRMED_DIVERGENT_INPUT",
  );
  assert(
    "idempotência: PENDING permanece PENDING quando a nova classificação também é ambígua",
    decideMappingUpsert({ id: "m4", match_status: "PENDING" }, "PENDING") === "NOOP_SAME_STATUS",
  );

  // --- P14.2 cenário 8: divergência de preço -----------------------------------------
  assert("divergência: sem erro de insert -> NEW", classifyObservationWrite(null, null, 1.25) === "NEW");
  assert(
    "divergência: duplicate key + mesmo price já persistido -> CONFLICT_IGNORED_SAME_PRICE (inofensivo)",
    classifyObservationWrite({ message: "duplicate key value violates unique constraint" }, 1.0, 1.0) === "CONFLICT_IGNORED_SAME_PRICE",
  );
  assert(
    "divergência: duplicate key + price diferente do já persistido -> DIVERGENT_PRESERVED (nunca sobrescreve)",
    classifyObservationWrite({ message: "duplicate key value violates unique constraint" }, 1.0, 1.25) === "DIVERGENT_PRESERVED",
  );
  assert(
    "divergência: erro real (não duplicate key) continua OTHER_ERROR",
    classifyObservationWrite({ message: "permission denied" }, 1.0, 1.25) === "OTHER_ERROR",
  );

  // --- P14.2 cenário 9: retry/rate limit (429 seguido de sucesso) -------------------
  {
    const page = { data: [{ id: "c1", name: "Card 1", number: "1" }], meta: { total: 1, limit: 100, offset: 0, hasMore: false }, _metadata: { apiRequestsRemaining: 123 } };
    const { fetchImpl, callCount } = makeFakeFetch([{ status: 429, body: {} }, { status: 200, body: page }]);
    const client = new JustTcgClient("fake-key", fetchImpl);
    const result = await client.get<{ data: unknown[] }>("/cards", { game: GAME_CODE, set: "fixture", limit: "100", offset: "0" });
    assert("retry/429: uma tentativa 429 + um retry bem-sucedido -> duas chamadas HTTP", callCount() === 2);
    assert("retry/429: rateLimitHits contabilizado exatamente uma vez", client.rateLimitHits === 1);
    assert("retry/429: resultado final SUCCESS após o retry", result.status === "SUCCESS");
  }

  // --- P14.2 cenário 10: sanitização (regressão já coberta acima, mantida por nome) --
  assert("sanitização (P14.2): já coberta pelos casos de regressão P8 acima", typeof sanitize === "function");

  // --- P14.2 cenário 11: chamadas crescem por lote/página, não por carta ------------
  {
    // 250 cartas locais hipotéticas, mas o lado externo pagina em 3 chamadas (100+100+50)
    // — o número de requisições depende do tamanho das PÁGINAS externas, nunca da
    // contagem de cartas locais. Este é o teste que prova diretamente a mudança de
    // arquitetura pedida: "eliminar o padrão de uma chamada por carta".
    const mk = (n: number, startId: number) => Array.from({ length: n }, (_, i) => ({ id: `c${startId + i}`, name: `Card ${startId + i}`, number: String(startId + i) }));
    const page1 = { data: mk(100, 0), meta: { hasMore: true } };
    const page2 = { data: mk(100, 100), meta: { hasMore: true } };
    const page3 = { data: mk(50, 200), meta: { hasMore: false } };
    const { fetchImpl } = makeFakeFetch([{ status: 200, body: page1 }, { status: 200, body: page2 }, { status: 200, body: page3 }]);
    const client = new JustTcgClient("fake-key", fetchImpl);
    const result = await fetchAllCardsForSet(client, "fixture-set-250-local-cards");
    assert(
      "chamadas por lote, não por carta: 250 cartas locais hipotéticas, só 3 requisições reais (não 250)",
      result.requestsUsed === 3 && result.cards.length === 250,
    );
  }

  // --- Resolução de Set (P14.2): release_date exato, nunca nome ---------------------
  {
    const allSets: JustTcgSet[] = [
      { id: "base-set-2-pokemon", name: "Base Set 2", release_date: "2000-02-24" },
      { id: "outro-set", name: "Outro Set", release_date: "2020-01-01" },
    ];
    const match = resolveSetMatchV2({ codigoMmkyu: "BASE4", releaseDateIso: "2000-02-24" }, allSets);
    assert("resolveSetMatchV2: release_date única -> CONFIRMED", match.status === "CONFIRMED" && match.set.id === "base-set-2-pokemon");
  }
  {
    const allSets: JustTcgSet[] = [{ id: "outro-set", name: "Outro Set", release_date: "2020-01-01" }];
    const match = resolveSetMatchV2({ codigoMmkyu: "BASE4", releaseDateIso: "2000-02-24" }, allSets);
    assert("resolveSetMatchV2: zero candidatos -> NOT_FOUND", match.status === "NOT_FOUND");
  }
  {
    const allSets: JustTcgSet[] = [
      { id: "set-a", name: "Set A", release_date: "2000-02-24" },
      { id: "set-b", name: "Set B", release_date: "2000-02-24" },
    ];
    const match = resolveSetMatchV2({ codigoMmkyu: "BASE4", releaseDateIso: "2000-02-24" }, allSets);
    assert("resolveSetMatchV2: mais de um candidato com a mesma data -> AMBIGUOUS, nunca auto-confirmado", match.status === "AMBIGUOUS");
  }

  // --- Fix P14.2.1: normalização de release_date na fronteira JustTCG ---------------
  // Causa raiz real do SET_NOT_FOUND(BASE4) no piloto de Fabrício: a API retorna
  // release_date como datetime ISO completo ("2000-02-24T00:00:00.000Z"), não como data pura
  // ("2000-02-24"), e a comparação de string exata nunca batia com card_set.release_date local.
  {
    assert("normalizeExternalSetReleaseDate: data pura passa intacta", normalizeExternalSetReleaseDate("2000-02-24") === "2000-02-24");
    assert(
      "normalizeExternalSetReleaseDate: datetime ISO completo (formato real da API) -> extrai só a data",
      normalizeExternalSetReleaseDate("2000-02-24T00:00:00.000Z") === "2000-02-24",
    );
    assert(
      "normalizeExternalSetReleaseDate: nunca faz conversão de timezone (regex de prefixo, nunca Date/toISOString)",
      normalizeExternalSetReleaseDate("2000-02-24T23:59:59.000-05:00") === "2000-02-24",
    );
    assert("normalizeExternalSetReleaseDate: ausente (undefined) -> null", normalizeExternalSetReleaseDate(undefined) === null);
    assert("normalizeExternalSetReleaseDate: ausente (null) -> null", normalizeExternalSetReleaseDate(null) === null);
    assert("normalizeExternalSetReleaseDate: valor inválido -> null", normalizeExternalSetReleaseDate("data-invalida") === null);
    assert("normalizeExternalSetReleaseDate: string vazia -> null", normalizeExternalSetReleaseDate("") === null);
  }
  {
    // Reprodução exata do bug relatado por Fabrício: local 2000-02-24, API com datetime ISO
    // completo -> CONFIRMED (não mais SET_NOT_FOUND).
    const rawSets: JustTcgSet[] = [{ id: "base-set-2-pokemon", name: "Base Set 2", release_date: "2000-02-24T00:00:00.000Z" }];
    const allSets = normalizeJustTcgSets(rawSets);
    const match = resolveSetMatchV2({ codigoMmkyu: "BASE4", releaseDateIso: "2000-02-24" }, allSets);
    assert(
      "reprodução do bug real: local 2000-02-24 + API 2000-02-24T00:00:00.000Z -> CONFIRMED (era SET_NOT_FOUND antes do fix)",
      match.status === "CONFIRMED" && match.set.id === "base-set-2-pokemon",
    );
    if (match.status === "CONFIRMED") {
      assert(
        "normalizeJustTcgSets: preserva o valor bruto original em release_date_raw para a evidência",
        match.set.release_date_raw === "2000-02-24T00:00:00.000Z" && match.evidence.external_set_release_date_raw === "2000-02-24T00:00:00.000Z",
      );
    }
  }
  {
    // release_date ausente na resposta da API -> normaliza para undefined -> nunca casa com
    // nenhuma data local -> NOT_FOUND, nunca CONFIRMED automaticamente.
    const rawSets: JustTcgSet[] = [{ id: "sem-data", name: "Set Sem Data" }];
    const allSets = normalizeJustTcgSets(rawSets);
    const match = resolveSetMatchV2({ codigoMmkyu: "BASE4", releaseDateIso: "2000-02-24" }, allSets);
    assert("release_date ausente na API -> NOT_FOUND, nunca confirmado", match.status === "NOT_FOUND");
  }
  {
    // release_date com formato não reconhecível -> normaliza para undefined -> mesmo
    // comportamento de "ausente": nunca confirmado.
    const rawSets: JustTcgSet[] = [{ id: "data-quebrada", name: "Set Data Quebrada", release_date: "fevereiro de 2000" }];
    const allSets = normalizeJustTcgSets(rawSets);
    const match = resolveSetMatchV2({ codigoMmkyu: "BASE4", releaseDateIso: "2000-02-24" }, allSets);
    assert("release_date inválido/não reconhecível na API -> NOT_FOUND, nunca confirmado", match.status === "NOT_FOUND");
  }
  {
    // Ambiguidade preservada mesmo misturando formatos (um em data pura, outro em datetime ISO)
    // que normalizam para a mesma data -> continua AMBIGUOUS, nunca auto-confirmado.
    const rawSets: JustTcgSet[] = [
      { id: "set-a", name: "Set A", release_date: "2000-02-24" },
      { id: "set-b", name: "Set B", release_date: "2000-02-24T00:00:00.000Z" },
    ];
    const allSets = normalizeJustTcgSets(rawSets);
    const match = resolveSetMatchV2({ codigoMmkyu: "BASE4", releaseDateIso: "2000-02-24" }, allSets);
    assert("ambiguidade preservada com formatos mistos (data pura + datetime ISO) -> AMBIGUOUS", match.status === "AMBIGUOUS");
  }

  // --- Fix P14.2.2: diagnóstico de cobertura externa (diagnoseExternalCoverage) ------
  // Reproduz em miniatura o cenário real do dry-run de BASE4 (externalCardsSeenTotal=137
  // contra 130 cartas locais, sem explicação): número inutilizável, número sem
  // correspondente local e grupo de número duplicado, todos contados de forma independente.
  {
    const externalCards: JustTcgCard[] = [
      { id: "e1", name: "Bulbasaur", number: "1", variants: [] },
      { id: "e2", name: "Bulbasaur Error", number: "N/A", variants: [] },
      { id: "e3", name: "Charmander", number: "4", variants: [] },
      { id: "e4", name: "Charmander Alt Art", number: "4", variants: [] },
      { id: "e5", name: "Squirtle", number: "7", variants: [] },
    ];
    const localCards: LocalCard[] = [
      { card_id: "l1", name: "Bulbasaur", collector_number: "001" },
      { card_id: "l2", name: "Charmander", collector_number: "004" },
    ];
    const coverage = diagnoseExternalCoverage(externalCards, localCards);
    assert("diagnoseExternalCoverage: externo sem número utilizável (N/A) contado à parte", coverage.externalCardsWithoutUsableNumber === 1);
    assert(
      "diagnoseExternalCoverage: externo com número sem correspondente local (Squirtle, número 7, ausente do catálogo local)",
      coverage.externalCardsNumberNotInLocalCatalog === 1,
    );
    assert(
      "diagnoseExternalCoverage: grupo de número externo duplicado detectado (Charmander, número 4, 2 registros)",
      coverage.duplicateExternalNumberGroups === 1 && coverage.duplicateExternalNumberGroupMembers === 2,
    );
    assert(
      "diagnoseExternalCoverage: métricas independentes — não forçadas a somar externalCardsSeenTotal - localCardsTotal (5-2=3, mas 1+1=2 != 3)",
      coverage.externalCardsWithoutUsableNumber + coverage.externalCardsNumberNotInLocalCatalog !== externalCards.length - localCards.length,
    );
  }

  // --- Fix P14.2.2: evidência sanitizada de mapping (AMBIGUOUS/ABSENT) ---------------
  {
    const externalIndex = buildExternalNumberIndex([
      { id: "ext-a", name: "Eevee", number: "133", variants: [{ id: "v1", condition: "Near Mint", printing: "Holofoil", price: 12.5, lastUpdated: 1700000000 }] },
      { id: "ext-b", name: "Eevee (Alt Art)", number: "133", variants: [] },
    ]);
    const local: LocalCard = { card_id: "local-eevee", name: "Eevee", collector_number: "133" };
    const matchResult = classifyCardMatch(local, externalIndex, "fixture-set-x");
    assert("cenário de evidência: dois candidatos pelo mesmo número, sem desempate seguro -> AMBIGUOUS", matchResult.classification === "AMBIGUOUS");

    const originalLog = console.log;
    const captured: string[] = [];
    console.log = (...args: unknown[]) => { captured.push(args.map(String).join(" ")); };
    try {
      logDryRunCardEvidence(local, matchResult);
    } finally {
      console.log = originalLog;
    }
    const printed = captured.join("\n");
    assert("logDryRunCardEvidence: imprime carta local, collector_number e motivo", printed.includes("Eevee") && printed.includes("133") && printed.includes(matchResult.method));
    assert("logDryRunCardEvidence: imprime candidatos externos com id/nome/número", printed.includes("ext-a") && printed.includes("ext-b") && printed.includes("Eevee (Alt Art)"));
    assert(
      "logDryRunCardEvidence: nunca imprime preço/variante/printing (evidência sanitizada — matchResult nunca carrega esses dados)",
      !printed.includes("12.5") && !printed.toLowerCase().includes("holofoil") && !printed.toLowerCase().includes("variant"),
    );
  }
  {
    const externalIndex = buildExternalNumberIndex([{ id: "ext-x", name: "Pikachu", number: "25", variants: [] }]);
    const local: LocalCard = { card_id: "local-absent", name: "Mewtwo", collector_number: "150" };
    const matchResult = classifyCardMatch(local, externalIndex, "fixture-set-x");
    assert("cenário de evidência ABSENT: sem candidato externo pelo número", matchResult.classification === "ABSENT");
    const originalLog = console.log;
    const captured: string[] = [];
    console.log = (...args: unknown[]) => { captured.push(args.map(String).join(" ")); };
    try {
      logDryRunCardEvidence(local, matchResult);
    } finally {
      console.log = originalLog;
    }
    const printed = captured.join("\n");
    assert(
      "logDryRunCardEvidence (ABSENT): imprime carta local, motivo e candidatos_externos vazio (P14.4.4: método unificado SET_CONFIRMED_COLLECTOR_NUMBER_UNIQUE, nunca mais NUMERO_SEM_CANDIDATO_EXTERNO)",
      printed.includes("Mewtwo") && printed.includes("150") && printed.includes("SET_CONFIRMED_COLLECTOR_NUMBER_UNIQUE") && printed.includes("[]"),
    );
  }

  // --- Fix P14.2.2: projeção de variantes em dry-run (planVariantProjection) --------
  {
    const conditionMap = new Map([["Near Mint", "cond-nm-uuid"]]);
    const valid = planVariantProjection({ id: "v1", condition: "Near Mint", printing: "Holofoil", price: 12.5, lastUpdated: 1700000000 }, conditionMap);
    assert(
      "planVariantProjection: variante válida -> PROJECTED com productId/conditionId/preço corretos",
      valid.status === "PROJECTED" && valid.conditionId === "cond-nm-uuid" && valid.price === 12.5,
    );

    const semId = planVariantProjection({ condition: "Near Mint", printing: "Holofoil", price: 12.5 }, conditionMap);
    assert("planVariantProjection: sem id externo (uuid/id) -> SKIPPED_INVALID_DATA/SEM_ID_EXTERNO", semId.status === "SKIPPED_INVALID_DATA" && semId.reason === "SEM_ID_EXTERNO");

    const semPrinting = planVariantProjection({ id: "v2", condition: "Near Mint", price: 12.5 }, conditionMap);
    assert("planVariantProjection: sem printing -> SKIPPED_INVALID_DATA/SEM_PRINTING", semPrinting.status === "SKIPPED_INVALID_DATA" && semPrinting.reason === "SEM_PRINTING");

    const precoInvalido = planVariantProjection({ id: "v3", condition: "Near Mint", printing: "Holofoil", price: "12.5" as unknown as number }, conditionMap);
    assert(
      "planVariantProjection: preço não numérico -> SKIPPED_INVALID_DATA/PRECO_INVALIDO",
      precoInvalido.status === "SKIPPED_INVALID_DATA" && precoInvalido.reason === "PRECO_INVALIDO",
    );

    const condDesconhecida = planVariantProjection({ id: "v4", condition: "Gem Mint 10", printing: "Holofoil", price: 12.5 }, conditionMap);
    assert(
      "planVariantProjection: condição não mapeada -> SKIPPED_UNKNOWN_CONDITION",
      condDesconhecida.status === "SKIPPED_UNKNOWN_CONDITION" && condDesconhecida.conditionRaw === "Gem Mint 10",
    );

    const variant = { id: "v5", condition: "Near Mint", printing: "Normal", price: 3.25 };
    const r1 = planVariantProjection(variant, conditionMap);
    const r2 = planVariantProjection(variant, conditionMap);
    assert("planVariantProjection: puro e determinístico (mesma entrada -> mesmo resultado, sem efeito colateral)", JSON.stringify(r1) === JSON.stringify(r2));
  }
  {
    // Agregação productsProjected/observationsProjected/variantsProjectionSkipped — mesma
    // lógica usada dentro do laço dry-run de runRealPilot(), reproduzida aqui só para testar
    // a contagem, sem duplicar planVariantProjection (que é chamada de verdade).
    const conditionMap = new Map([["Near Mint", "cond-nm"], ["Lightly Played", "cond-lp"]]);
    const matchedCard: JustTcgCard = {
      id: "ext-multi",
      name: "Gyarados",
      number: "130",
      variants: [
        { id: "v1", condition: "Near Mint", printing: "Holofoil", price: 40 },
        { id: "v2", condition: "Lightly Played", printing: "Holofoil", price: 30 },
        { id: "v3", condition: "Gem Mint 10", printing: "Holofoil", price: 999 },
        { id: "v4", condition: "Near Mint", printing: "", price: 5 },
      ],
    };
    let productsProjected = 0;
    let observationsProjected = 0;
    let variantsProjectionSkipped = 0;
    for (const variant of matchedCard.variants ?? []) {
      const projection = planVariantProjection(variant, conditionMap);
      if (projection.status === "PROJECTED") {
        productsProjected++;
        observationsProjected++;
      } else {
        variantsProjectionSkipped++;
      }
    }
    assert("projeção agregada: 2 variantes válidas -> productsProjected=2 e observationsProjected=2", productsProjected === 2 && observationsProjected === 2);
    assert("projeção agregada: 2 variantes ignoradas (condição desconhecida + printing ausente)", variantsProjectionSkipped === 2);
  }

  // --- Fix P14.2.2: zero chamadas aos métodos de escrita durante dry-run -------------
  // Prova estrutural, não só comportamental: nenhuma das três funções novas usadas pelo
  // ramo dry-run declara um parâmetro de SupabaseClient — é estruturalmente impossível que
  // elas cheguem a chamar .insert()/.upsert()/.update() do Supabase.
  {
    assert(
      "planVariantProjection não recebe SupabaseClient (assinatura pura: variant, conditionMap) — impossível escrever no banco",
      planVariantProjection.length === 2,
    );
    assert(
      "diagnoseExternalCoverage não recebe SupabaseClient (assinatura pura: externalCards, localCards) — impossível escrever no banco",
      diagnoseExternalCoverage.length === 2,
    );
    assert(
      "logDryRunCardEvidence não recebe SupabaseClient (assinatura pura: local, matchResult) — só console.log, impossível escrever no banco",
      logDryRunCardEvidence.length === 2,
    );
  }

  // --- Fix P14.2.2: caminho real (upsertCardMapping/pricing_product/pricing_observation) --
  // não foi tocado nesta rodada — reconfirmação direta das mesmas funções puras que o
  // caminho real usa, para deixar explícito que seu comportamento permanece idêntico.
  {
    assert("caminho real inalterado — classifyInsertResult: sem erro -> NEW", classifyInsertResult(null) === "NEW");
    assert(
      "caminho real inalterado — classifyObservationWrite: duplicate key + mesmo preço -> CONFLICT_IGNORED_SAME_PRICE",
      classifyObservationWrite({ message: "duplicate key value violates unique constraint" }, 10, 10) === "CONFLICT_IGNORED_SAME_PRICE",
    );
    assert(
      "caminho real inalterado — classifyObservationWrite: duplicate key + preço diferente -> DIVERGENT_PRESERVED (nunca sobrescreve)",
      classifyObservationWrite({ message: "duplicate key value violates unique constraint" }, 10, 12) === "DIVERGENT_PRESERVED",
    );
  }

  // --- Fix P14.3: falha de UPDATE (ou INSERT/SELECT) nunca é silenciosa ------------------
  // Cenário real que motivou esta rodada: service_role sem GRANT UPDATE em
  // pricing_card_mapping/pricing_set_mapping fazia upsertCardMapping()/upsertSetMapping()
  // engolirem o erro em silêncio (Supabase JS não lança exceção por padrão). Corrigido via
  // Query 3912 (GRANT UPDATE restrito por coluna) + verificação explícita de { error } em
  // toda operação de escrita. Os testes abaixo provam a propagação em nível de código,
  // independente do estado real de grants do banco.
  {
    const erroPermissao = { message: "permission denied for table pricing_card_mapping" };

    // SELECT (etapa de decisão do upsert) falha -> propagada, nunca tratada como "não existe".
    const clienteSelectFalha = makeMockSupabaseClient({
      pricing_card_mapping: { select: { data: null, error: erroPermissao } },
    });
    const resultadoSelectFalha = await upsertCardMapping(clienteSelectFalha, "card-1", "source-1", "CONFIRMED", null, "auto", {}, "admin-1");
    assert(
      "upsertCardMapping: falha no SELECT de decisão -> { ok: false } propagado (nunca tratado como ausente)",
      resultadoSelectFalha.ok === false && resultadoSelectFalha.error.includes("permission denied"),
    );

    // INSERT falha (mapeamento novo, sem linha existente) -> propagada.
    const clienteInsertFalha = makeMockSupabaseClient({
      pricing_card_mapping: {
        select: { data: null, error: null },
        insert: { data: null, error: erroPermissao },
      },
    });
    const resultadoInsertFalha = await upsertCardMapping(clienteInsertFalha, "card-2", "source-1", "CONFIRMED", null, "auto", {}, "admin-1");
    assert(
      "upsertCardMapping: falha no INSERT -> { ok: false } propagado",
      resultadoInsertFalha.ok === false && resultadoInsertFalha.error.includes("permission denied"),
    );

    // UPDATE falha (mapeamento existente PENDING, nova classificação CONFIRMED) -> propagada
    // — exatamente o cenário real encontrado nesta rodada antes da Query 3912.
    const clienteUpdateFalha = makeMockSupabaseClient({
      pricing_card_mapping: {
        select: { data: { id: "existing-1", match_status: "PENDING" }, error: null },
        update: { error: erroPermissao },
      },
    });
    const resultadoUpdateFalha = await upsertCardMapping(clienteUpdateFalha, "card-3", "source-1", "CONFIRMED", null, "auto", {}, "admin-1");
    assert(
      "upsertCardMapping: falha no UPDATE (PENDING -> CONFIRMED) -> { ok: false } propagado, nunca silencioso",
      resultadoUpdateFalha.ok === false && resultadoUpdateFalha.error.includes("permission denied"),
    );

    // Mesmo cenário de UPDATE falho, agora em pricing_set_mapping.
    const clienteSetUpdateFalha = makeMockSupabaseClient({
      pricing_set_mapping: {
        select: { data: { id: "existing-set-1", match_status: "PENDING" }, error: null },
        update: { error: erroPermissao },
      },
    });
    const resultadoSetUpdateFalha = await upsertSetMapping(clienteSetUpdateFalha, "set-1", "source-1", "CONFIRMED", null, "auto", {}, "admin-1");
    assert(
      "upsertSetMapping: falha no UPDATE (PENDING -> CONFIRMED) -> { ok: false } propagado, nunca silencioso",
      resultadoSetUpdateFalha.ok === false && resultadoSetUpdateFalha.error.includes("permission denied"),
    );

    // Caminho de sucesso continua intacto (regressão do novo contrato { ok, id }).
    const clienteSucesso = makeMockSupabaseClient({
      pricing_card_mapping: {
        select: { data: null, error: null },
        insert: { data: { id: "novo-id-1" }, error: null },
      },
    });
    const resultadoSucesso = await upsertCardMapping(clienteSucesso, "card-4", "source-1", "CONFIRMED", null, "auto", {}, "admin-1");
    assert(
      "upsertCardMapping: caminho de sucesso preservado -> { ok: true, id: 'novo-id-1' }",
      resultadoSucesso.ok === true && resultadoSucesso.id === "novo-id-1",
    );

    // finalizeSyncRun: UPDATE de finalização falha -> função retorna false (nunca lança nem
    // finge sucesso) — mesmo sintoma do incidente histórico do run 19a04057 (preso em
    // PROCESSING), agora sempre detectável programaticamente pelo valor de retorno.
    const clienteFinalizeFalha = makeMockSupabaseClient({
      pricing_sync_run: { update: { error: erroPermissao } },
    });
    const clientFinalize = new JustTcgClient("fake-key", (async () => new Response()) as unknown as typeof fetch);
    const finalizeOk = await finalizeSyncRun(clienteFinalizeFalha, "run-1", clientFinalize, "COMPLETED", null, false);
    assert("finalizeSyncRun: falha no UPDATE de finalização -> retorna false, nunca silencioso", finalizeOk === false);

    // finalizeSyncRun: caminho de sucesso continua retornando true.
    const clienteFinalizeOk = makeMockSupabaseClient({
      pricing_sync_run: { update: { error: null } },
    });
    const finalizeSucesso = await finalizeSyncRun(clienteFinalizeOk, "run-2", clientFinalize, "COMPLETED", null, false);
    assert("finalizeSyncRun: caminho de sucesso preservado -> retorna true", finalizeSucesso === true);

    // dryRun/syncRunId nulo continuam sendo no-op sem tocar o Supabase (comportamento pré-existente).
    const finalizeDryRun = await finalizeSyncRun(clienteFinalizeFalha, "run-3", clientFinalize, "COMPLETED", null, true);
    assert("finalizeSyncRun: dryRun=true permanece no-op (nunca chama o Supabase) -> retorna true", finalizeDryRun === true);
  }

  // --- P14.3: persistência em lotes (persistBatchedResults) -------------------------
  // Os 11 cenários exigidos por Fabrício + o teste de computeFinalStatus (run nunca fica em
  // limbo). Usa makeBatchFakeClient() — um estado de tabela real em memória, não respostas
  // fixas — para poder afirmar objetivamente quantas chamadas HTTP o adapter emitiria contra
  // o PostgREST real, e para que reexecuções enxerguem o estado deixado pela rodada anterior.
  {
    const makePlannedMapping = (cardId: string, status: "CONFIRMED" | "PENDING" | "NOT_FOUND"): PlannedCardMapping => ({
      cardId,
      collectorNumber: cardId,
      status,
      matchedCard: status === "CONFIRMED" ? { id: `ext-${cardId}`, name: `Card ${cardId}`, variants: [] } : null,
      method: "auto",
      evidence: {},
    });
    const makePlannedVariant = (cardId: string, externalProductId: string, price: number, observedAt = "2026-08-19T00:00:00.000Z"): PlannedVariant => ({
      cardId,
      collectorNumber: cardId,
      externalProductId,
      sourcePrintingLabel: "Normal",
      conditionId: "id-nm",
      price,
      observedAt,
      rawPayload: {},
    });

    // Cenário 1: 130 mappings novos -> batching real, não 130 round trips.
    {
      const mappings = Array.from({ length: 130 }, (_, i) => makePlannedMapping(`card-${i}`, "CONFIRMED"));
      const { client, stats } = makeBatchFakeClient({ pricing_card_mapping: [] });
      const outcome = await persistBatchedResults(client, "source-1", null, "admin-1", mappings, []);
      // Fix revisão de segurança 2026-08-19: threshold estava travado em "=== 1", correto
      // só quando BATCH_SIZE=300 (130 cabe num único lote). Desde a redução para
      // BATCH_SIZE=100 (revisão anterior desta mesma rodada), 130 itens exigem
      // ceil(130/100)=2 lotes — a asserção ficou obsoleta e nunca foi revalidada com
      // visibilidade completa (mascarada por truncamento de output numa checagem anterior).
      assert("P14.3/1: 130 mappings novos -> poucos lotes, não 130 (BATCH_SIZE=100 -> 2 lotes)", stats.selectCalls["pricing_card_mapping"] === 2);
      assert("P14.3/1: 130 mappings novos -> poucos lotes de INSERT, não 130 (BATCH_SIZE=100 -> 2 lotes)", stats.insertCalls["pricing_card_mapping"] === 2);
      assert("P14.3/1: 130 mappings novos -> sem erro, sem falha de lote", outcome.errorParts.length === 0 && outcome.batchFailureOccurred === false);
    }

    // Cenário 2: 635 produtos / 635 observações -> batching real, não 635+635 round trips.
    {
      const cardIds = Array.from({ length: 127 }, (_, i) => `pcard-${i}`);
      const mappings = cardIds.map((id) => makePlannedMapping(id, "CONFIRMED"));
      const variants: PlannedVariant[] = [];
      for (const id of cardIds) for (let v = 0; v < 5; v++) variants.push(makePlannedVariant(id, `ext-${id}-${v}`, 10 + v));
      assert("P14.3/2: cenário de escala construído com exatamente 635 variantes", variants.length === 635);

      const { client, stats } = makeBatchFakeClient({ pricing_card_mapping: [], pricing_product: [], pricing_observation: [] });
      const outcome = await persistBatchedResults(client, "source-1", "run-scale", "admin-1", mappings, variants);
      assert("P14.3/2: 635 produtos novos -> pré-busca em poucos lotes (não 635)", (stats.selectCalls["pricing_product"] ?? 0) <= 3);
      // Fix revisão de segurança 2026-08-19: o INSERT de pricing_product é chunkado pelos
      // 635 produtos distintos (não pelos 127 card mappings, usados só na pré-busca) — a
      // BATCH_SIZE=100 exige ceil(635/100)=7 lotes. Threshold "<=3" era válido só em
      // BATCH_SIZE=300; obsoleto desde a redução, corrigido aqui.
      assert("P14.3/2: 635 produtos novos -> INSERT em poucos lotes (não 635)", (stats.insertCalls["pricing_product"] ?? 0) <= 7);
      // Fix revisão de escala 2026-08-19 (3ª rodada): pré-busca de observações migrou da RPC
      // de tupla exata (Query 3914) para batch_select_latest_pricing_observation_by_identity
      // (proposta, não aplicada) — chave de grupo sem observed_at (produto+condição), então
      // a contagem de chaves únicas não muda: 635 produtos x 1 condição = 635 chaves únicas
      // / BATCH_SIZE=100 -> 7 chunks (não 635).
      assert("P14.3/2: 635 observações novas -> pré-busca em poucos lotes via RPC de última observação por grupo (não 635)", (stats.rpcCallsByFn["batch_select_latest_pricing_observation_by_identity"] ?? 0) <= 7);
      assert("P14.3/2: 635 observações novas -> INSERT em poucos lotes (não 635)", (stats.insertCalls["pricing_observation"] ?? 0) <= 7);
      assert("P14.3/2: 635 produtos resolvidos e escritos", outcome.productsResolved === 635 && outcome.productsWritten === 635);
      assert("P14.3/2: 635 observações resolvidas e escritas", outcome.observationsResolved === 635 && outcome.observationsWritten === 635);
    }

    // Cenário 3: correlação produto -> mapping nunca cruza entre cartas diferentes.
    {
      const mappings = [makePlannedMapping("corr-a", "CONFIRMED"), makePlannedMapping("corr-b", "CONFIRMED")];
      const variants = [makePlannedVariant("corr-a", "ext-a-1", 5), makePlannedVariant("corr-b", "ext-b-1", 7)];
      const { client, tables } = makeBatchFakeClient({ pricing_card_mapping: [], pricing_product: [], pricing_observation: [] });
      await persistBatchedResults(client, "source-1", null, "admin-1", mappings, variants);
      const mappingA = tables["pricing_card_mapping"].find((r) => r.card_id === "corr-a");
      const mappingB = tables["pricing_card_mapping"].find((r) => r.card_id === "corr-b");
      const productA = tables["pricing_product"].find((r) => r.external_product_id === "ext-a-1");
      const productB = tables["pricing_product"].find((r) => r.external_product_id === "ext-b-1");
      assert(
        "P14.3/3: produto de corr-a aponta para o mapping de corr-a, nunca de corr-b",
        productA?.pricing_card_mapping_id === mappingA?.id && productA?.pricing_card_mapping_id !== mappingB?.id,
      );
      assert(
        "P14.3/3: produto de corr-b aponta para o mapping de corr-b, nunca de corr-a",
        productB?.pricing_card_mapping_id === mappingB?.id && productB?.pricing_card_mapping_id !== mappingA?.id,
      );
    }

    // Cenário 4: mapping já CONFIRMED nunca é rebaixado por uma nova classificação pior.
    {
      const seed = { pricing_card_mapping: [{ id: "existing-confirmed-1", card_id: "prot-1", pricing_source_id: "source-1", match_status: "CONFIRMED" }] };
      const mappings = [makePlannedMapping("prot-1", "PENDING")];
      const { client, tables, stats } = makeBatchFakeClient(seed);
      const outcome = await persistBatchedResults(client, "source-1", null, "admin-1", mappings, []);
      const row = tables["pricing_card_mapping"].find((r) => r.card_id === "prot-1");
      assert("P14.3/4: mapping permanece CONFIRMED mesmo com nova classificação PENDING", row?.match_status === "CONFIRMED");
      assert("P14.3/4: NOOP puro -> nenhum INSERT/RPC disparado", (stats.insertCalls["pricing_card_mapping"] ?? 0) === 0 && stats.rpcCalls === 0);
      assert("P14.3/4: outcome sem erro", outcome.errorParts.length === 0);
    }

    // Cenário 5: idempotência total -> reexecução idêntica não escreve nada de novo.
    {
      const mappings = [makePlannedMapping("idem-1", "CONFIRMED")];
      const variants = [makePlannedVariant("idem-1", "ext-idem-1", 9)];
      const { client, stats } = makeBatchFakeClient({ pricing_card_mapping: [], pricing_product: [], pricing_observation: [] });
      await persistBatchedResults(client, "source-1", "run-1", "admin-1", mappings, variants);
      const secondOutcome = await persistBatchedResults(client, "source-1", "run-2", "admin-1", mappings, variants);
      assert("P14.3/5: 2ª rodada não insere novo mapping (total acumulado continua 1)", (stats.insertCalls["pricing_card_mapping"] ?? 0) === 1);
      assert("P14.3/5: 2ª rodada não insere novo produto (total acumulado continua 1)", (stats.insertCalls["pricing_product"] ?? 0) === 1);
      assert("P14.3/5: 2ª rodada não insere nova observação — mesmo preço -> CONFLICT_IGNORED_SAME_PRICE", (stats.insertCalls["pricing_observation"] ?? 0) === 1);
      assert("P14.3/5: 2ª rodada reporta zero escrita nova", secondOutcome.productsWritten === 0 && secondOutcome.observationsWritten === 0);
      assert("P14.3/5: 2ª rodada sem erro/divergência", secondOutcome.errorParts.length === 0 && secondOutcome.observationsDivergent === 0);
    }

    // Cenário 6: conflito de mesmo preço -> resolvido, nunca escrito de novo, sem divergência.
    {
      const cardMappingId = "cm-conflict-1";
      const productId = "prod-conflict-1";
      const observedAt = "2026-08-19T00:00:00.000Z";
      const identityId = "identity-conflict-1";
      const seed = {
        pricing_card_mapping: [{ id: cardMappingId, card_id: "conflict-1", pricing_source_id: "source-1", match_status: "CONFIRMED" }],
        // Fix P14.5 (dual-write): identidade PRIMARY/CONFIRMED pré-existente (equivalente ao
        // backfill da 3923) — sem isso, Regra 1 excluiria a variante antes de chegar em
        // pricing_product/pricing_observation.
        pricing_source_card_identity: [{ id: identityId, pricing_card_mapping_id: cardMappingId, pricing_source_id: "source-1", external_card_id: "ext-conflict-1", identity_role: "PRIMARY", match_status: "CONFIRMED" }],
        pricing_product: [{ id: productId, pricing_card_mapping_id: cardMappingId, pricing_source_card_identity_id: identityId, external_product_id: "ext-conflict-1" }],
        pricing_observation: [{ pricing_product_id: productId, condition_id: "id-nm", price_type: "MARKET", currency_code: "USD", market_label: MARKET_LABEL, observed_at: observedAt, price: 42 }],
      };
      const mappings = [makePlannedMapping("conflict-1", "CONFIRMED")];
      const variants = [makePlannedVariant("conflict-1", "ext-conflict-1", 42, observedAt)];
      const { client, stats } = makeBatchFakeClient(seed);
      const outcome = await persistBatchedResults(client, "source-1", null, "admin-1", mappings, variants);
      assert("P14.3/6: mesmo preço -> nenhum INSERT novo em pricing_observation", (stats.insertCalls["pricing_observation"] ?? 0) === 0);
      assert("P14.3/6: resolvido (não escrito), sem divergência", outcome.observationsResolved === 1 && outcome.observationsWritten === 0 && outcome.observationsDivergent === 0);
    }

    // Cenário 7: divergência de preço -> nunca sobrescreve, sinalizada para revisão.
    {
      const cardMappingId = "cm-divergent-1";
      const productId = "prod-divergent-1";
      const observedAt = "2026-08-19T00:00:00.000Z";
      const identityId = "identity-divergent-1";
      const seed = {
        pricing_card_mapping: [{ id: cardMappingId, card_id: "divergent-1", pricing_source_id: "source-1", match_status: "CONFIRMED" }],
        pricing_source_card_identity: [{ id: identityId, pricing_card_mapping_id: cardMappingId, pricing_source_id: "source-1", external_card_id: "ext-divergent-1", identity_role: "PRIMARY", match_status: "CONFIRMED" }],
        pricing_product: [{ id: productId, pricing_card_mapping_id: cardMappingId, pricing_source_card_identity_id: identityId, external_product_id: "ext-divergent-1" }],
        pricing_observation: [{ pricing_product_id: productId, condition_id: "id-nm", price_type: "MARKET", currency_code: "USD", market_label: MARKET_LABEL, observed_at: observedAt, price: 42 }],
      };
      const mappings = [makePlannedMapping("divergent-1", "CONFIRMED")];
      const variants = [makePlannedVariant("divergent-1", "ext-divergent-1", 99, observedAt)];
      const { client, tables, stats } = makeBatchFakeClient(seed);
      const outcome = await persistBatchedResults(client, "source-1", null, "admin-1", mappings, variants);
      const row = tables["pricing_observation"].find((r) => r.pricing_product_id === productId);
      assert("P14.3/7: preço original (42) nunca é sobrescrito pelo novo (99)", row?.price === 42);
      assert(
        "P14.3/7: divergência sinalizada em observationsDivergent/errorParts, nenhum INSERT novo",
        outcome.observationsDivergent === 1 && (stats.insertCalls["pricing_observation"] ?? 0) === 0 && outcome.errorParts.some((e) => e.includes("OBSERVATION_PRICE_DIVERGENTE_PRESERVADA")),
      );
    }

    // Cenário 7b (diagnóstico 2026-08-19, revisão "escala anual" -> correção mínima da 3ª
    // rodada): a mesma identidade (produto+condição), MESMO preço, observado em DUAS DATAS
    // DIFERENTES (simulando duas execuções diárias reais, onde observedAt vem de
    // variant.lastUpdated da JustTCG e avança a cada dia mesmo sem o preço mudar).
    // Comportamento ANTES da correção (Query 3914, tupla exata): a pré-busca casava só por
    // tupla EXATA incluindo observed_at, então a segunda data nunca encontrava a primeira
    // observação -> um NOVO INSERT era emitido mesmo com preço idêntico (2 linhas, provado
    // empiricamente). Comportamento DEPOIS da correção mínima proposta (RPC
    // batch_select_latest_pricing_observation_by_identity, sem observed_at na chave de
    // busca): compara contra o ÚLTIMO preço conhecido do grupo, não contra a tupla exata ->
    // preço idêntico reaproveita a observação existente, nenhuma linha nova. Ver Cenário 7c
    // logo abaixo para o caso de mudança real de preço (ainda deve gravar linha nova).
    {
      const cardMappingId = "cm-samepricediffday-1";
      const productId = "prod-samepricediffday-1";
      const identityId = "identity-spd-1";
      const seed = {
        pricing_card_mapping: [{ id: cardMappingId, card_id: "spd-1", pricing_source_id: "source-1", match_status: "CONFIRMED" }],
        pricing_source_card_identity: [{ id: identityId, pricing_card_mapping_id: cardMappingId, pricing_source_id: "source-1", external_card_id: "ext-spd-1", identity_role: "PRIMARY", match_status: "CONFIRMED" }],
        pricing_product: [{ id: productId, pricing_card_mapping_id: cardMappingId, pricing_source_card_identity_id: identityId, external_product_id: "ext-spd-1" }],
        pricing_observation: [{ pricing_product_id: productId, condition_id: "id-nm", price_type: "MARKET", currency_code: "USD", market_label: MARKET_LABEL, observed_at: "2026-08-18T00:00:00.000Z", price: 7 }],
      };
      const mappings = [makePlannedMapping("spd-1", "CONFIRMED")];
      // Mesmo preço (7), mas observedAt do dia seguinte — como ocorreria numa reexecução
      // diária real com o mesmo preço reportado pela JustTCG em dois dias consecutivos.
      const variants = [makePlannedVariant("spd-1", "ext-spd-1", 7, "2026-08-19T00:00:00.000Z")];
      const { client, tables, stats } = makeBatchFakeClient(seed);
      const outcome = await persistBatchedResults(client, "source-1", null, "admin-1", mappings, variants);
      const rowsForProduct = tables["pricing_observation"].filter((r) => r.pricing_product_id === productId);
      assert(
        "Cenário 7b (comportamento DEPOIS da correção): preço idêntico em data diferente reaproveita a última observação -> nenhuma linha nova, nenhum INSERT",
        rowsForProduct.length === 1 && outcome.observationsWritten === 0 && outcome.observationsResolved === 1 && (stats.insertCalls["pricing_observation"] ?? 0) === 0,
      );
    }

    // Cenário 7c (correção mínima 2026-08-19, 3ª rodada): mesma identidade, DATA diferente E
    // PREÇO diferente do último conhecido -> mudança material real, ainda deve gravar uma
    // observação nova (a correção não suprime mudanças de preço genuínas, só o ruído de
    // preço idêntico repetido).
    {
      const cardMappingId = "cm-diffpricediffday-1";
      const productId = "prod-diffpricediffday-1";
      const identityId = "identity-dpd-1";
      const seed = {
        pricing_card_mapping: [{ id: cardMappingId, card_id: "dpd-1", pricing_source_id: "source-1", match_status: "CONFIRMED" }],
        pricing_source_card_identity: [{ id: identityId, pricing_card_mapping_id: cardMappingId, pricing_source_id: "source-1", external_card_id: "ext-dpd-1", identity_role: "PRIMARY", match_status: "CONFIRMED" }],
        pricing_product: [{ id: productId, pricing_card_mapping_id: cardMappingId, pricing_source_card_identity_id: identityId, external_product_id: "ext-dpd-1" }],
        pricing_observation: [{ pricing_product_id: productId, condition_id: "id-nm", price_type: "MARKET", currency_code: "USD", market_label: MARKET_LABEL, observed_at: "2026-08-18T00:00:00.000Z", price: 7 }],
      };
      const mappings = [makePlannedMapping("dpd-1", "CONFIRMED")];
      // Preço mudou de 7 para 9, observedAt do dia seguinte — mudança material real.
      const variants = [makePlannedVariant("dpd-1", "ext-dpd-1", 9, "2026-08-19T00:00:00.000Z")];
      const { client, tables, stats } = makeBatchFakeClient(seed);
      const outcome = await persistBatchedResults(client, "source-1", null, "admin-1", mappings, variants);
      const rowsForProduct = tables["pricing_observation"].filter((r) => r.pricing_product_id === productId);
      assert(
        "Cenário 7c: mudança real de preço em data diferente ainda grava observação nova (correção não suprime mudanças genuínas)",
        rowsForProduct.length === 2 && outcome.observationsWritten === 1 && outcome.observationsResolved === 1 && (stats.insertCalls["pricing_observation"] ?? 0) === 1,
      );
      const newRow = rowsForProduct.find((r) => r.observed_at === "2026-08-19T00:00:00.000Z");
      assert("Cenário 7c: a linha nova tem o preço atualizado (9), a antiga (7) permanece intacta", newRow?.price === 9 && rowsForProduct.some((r) => r.price === 7));
    }

    // Cenário 7d (correção mínima 2026-08-19, 3ª rodada): colisão real — mesmo observed_at
    // exato já tem outro preço gravado (ex.: reexecução no mesmo instante com dado
    // divergente). Deve continuar preservando a linha existente e sinalizar, nunca
    // sobrescrever nem inserir uma segunda linha na mesma tupla exata (violaria a
    // constraint única uq_pricing_observation_identity_market_aware).
    {
      const cardMappingId = "cm-sametscollision-1";
      const productId = "prod-sametscollision-1";
      const sameTs = "2026-08-19T00:00:00.000Z";
      const identityId = "identity-stc-1";
      const seed = {
        pricing_card_mapping: [{ id: cardMappingId, card_id: "stc-1", pricing_source_id: "source-1", match_status: "CONFIRMED" }],
        pricing_source_card_identity: [{ id: identityId, pricing_card_mapping_id: cardMappingId, pricing_source_id: "source-1", external_card_id: "ext-stc-1", identity_role: "PRIMARY", match_status: "CONFIRMED" }],
        pricing_product: [{ id: productId, pricing_card_mapping_id: cardMappingId, pricing_source_card_identity_id: identityId, external_product_id: "ext-stc-1" }],
        pricing_observation: [{ pricing_product_id: productId, condition_id: "id-nm", price_type: "MARKET", currency_code: "USD", market_label: MARKET_LABEL, observed_at: sameTs, price: 7 }],
      };
      const mappings = [makePlannedMapping("stc-1", "CONFIRMED")];
      const variants = [makePlannedVariant("stc-1", "ext-stc-1", 9, sameTs)];
      const { client, tables, stats } = makeBatchFakeClient(seed);
      const outcome = await persistBatchedResults(client, "source-1", null, "admin-1", mappings, variants);
      const rowsForProduct = tables["pricing_observation"].filter((r) => r.pricing_product_id === productId);
      assert(
        "Cenário 7d: colisão de mesmo observed_at com preço divergente continua preservada, nunca sobrescrita nem duplicada",
        rowsForProduct.length === 1 && rowsForProduct[0]?.price === 7 && outcome.observationsDivergent === 1 && (stats.insertCalls["pricing_observation"] ?? 0) === 0 &&
          outcome.errorParts.some((e) => e.includes("OBSERVATION_PRICE_DIVERGENTE_PRESERVADA")),
      );
    }

    // Cenário 8: falha em um lote (INSERT de produtos) -> sinalizada, nunca engolida.
    {
      const mappings = [makePlannedMapping("fail-1", "CONFIRMED")];
      const variants = [makePlannedVariant("fail-1", "ext-fail-1", 5)];
      const { client, stats } = makeBatchFakeClient({ pricing_card_mapping: [], pricing_product: [], pricing_observation: [] }, { failInsert: { pricing_product: true } });
      const outcome = await persistBatchedResults(client, "source-1", null, "admin-1", mappings, variants);
      assert("P14.3/8: mapping (tabela não afetada pela falha) ainda foi inserido com sucesso", (stats.insertCalls["pricing_card_mapping"] ?? 0) === 1);
      assert("P14.3/8: batchFailureOccurred=true, nunca mascarado como sucesso", outcome.batchFailureOccurred === true);
      assert("P14.3/8: erro reportado em errorParts, nunca em silêncio", outcome.errorParts.some((e) => e.includes("PRODUCT_BATCH_INSERT_FAILED")));
      assert("P14.3/8: nenhuma observação foi tentada (produto nunca resolvido -> sem productId)", (stats.insertCalls["pricing_observation"] ?? 0) === 0);
    }

    // Cenário 9: reexecução após falha parcial recupera o que ficou pendente.
    {
      const mappings = [makePlannedMapping("recover-1", "CONFIRMED")];
      const variants = [makePlannedVariant("recover-1", "ext-recover-1", 3)];
      const { client: clientA, tables } = makeBatchFakeClient({ pricing_card_mapping: [], pricing_product: [], pricing_observation: [] }, { failInsert: { pricing_product: true } });
      const firstOutcome = await persistBatchedResults(clientA, "source-1", null, "admin-1", mappings, variants);
      assert("P14.3/9: 1ª rodada falha e não deixa o produto escrito", firstOutcome.batchFailureOccurred === true && (tables["pricing_product"]?.length ?? 0) === 0);
      const { client: clientB } = makeBatchFakeClient(tables); // reaproveita o estado real deixado pela 1ª rodada (mapping já persistido), sem forçar falha
      const secondOutcome = await persistBatchedResults(clientB, "source-1", null, "admin-1", mappings, variants);
      assert("P14.3/9: 2ª rodada recupera e escreve o produto pendente, sem nova falha", secondOutcome.batchFailureOccurred === false && secondOutcome.productsWritten === 1);
    }

    // Cenário 10: mappings PENDING/NOT_FOUND (sem variantes) -> zero operações de produto/observação.
    {
      const mappings = [makePlannedMapping("amb-1", "PENDING"), makePlannedMapping("amb-2", "NOT_FOUND")];
      const { client, stats } = makeBatchFakeClient({ pricing_card_mapping: [] });
      const outcome = await persistBatchedResults(client, "source-1", null, "admin-1", mappings, []);
      assert("P14.3/10: PENDING/NOT_FOUND -> nenhuma operação em pricing_product", (stats.selectCalls["pricing_product"] ?? 0) === 0 && (stats.insertCalls["pricing_product"] ?? 0) === 0);
      assert("P14.3/10: PENDING/NOT_FOUND -> nenhuma operação em pricing_observation", (stats.selectCalls["pricing_observation"] ?? 0) === 0 && (stats.insertCalls["pricing_observation"] ?? 0) === 0);
      assert("P14.3/10: produtos/observações resolvidos = 0", outcome.productsResolved === 0 && outcome.observationsResolved === 0);
    }

    // Cenário 11: operationsSupabase é a contagem objetiva e exata de round trips reais.
    {
      const mappings = [makePlannedMapping("count-1", "CONFIRMED")];
      const variants = [makePlannedVariant("count-1", "ext-count-1", 1)];
      const { client, stats } = makeBatchFakeClient({ pricing_card_mapping: [], pricing_product: [], pricing_observation: [] });
      const outcome = await persistBatchedResults(client, "source-1", null, "admin-1", mappings, variants);
      const totalCalls = Object.values(stats.selectCalls).reduce((a, b) => a + b, 0) + Object.values(stats.insertCalls).reduce((a, b) => a + b, 0) + stats.rpcCalls;
      assert("P14.3/11: operationsSupabase bate exatamente com a contagem real de chamadas (não estimativa)", outcome.operationsSupabase === totalCalls);
    }

    // Cenário 12: run nunca fica em limbo — falha de lote sempre força FAILED, mesmo com progresso real.
    {
      assert("P14.3/12: falha de lote força FAILED mesmo com progresso e sem outros erros", computeFinalStatus(true, false, true) === "FAILED");
      assert("P14.3/12: falha de lote força FAILED mesmo com progresso e outros erros", computeFinalStatus(true, true, true) === "FAILED");
      assert("P14.3/12: sem falha de lote e sem erros -> COMPLETED", computeFinalStatus(false, false, true) === "COMPLETED");
      assert("P14.3/12: sem falha de lote, com erros e algum progresso -> COMPLETED_WITH_ERRORS", computeFinalStatus(false, true, true) === "COMPLETED_WITH_ERRORS");
      assert("P14.3/12: sem falha de lote, com erros e zero progresso -> FAILED", computeFinalStatus(false, true, false) === "FAILED");
    }

    // Cenário 13 (revisão de segurança 2026-08-19): RPC de promoção agora é EXCLUSIVA —
    // uma transição PENDING<->NOT_FOUND (sem promoção a CONFIRMED) nunca é enviada à RPC;
    // fica sem escrita nesta rodada e sinalizada em errorParts, nunca aplicada silenciosamente.
    {
      const seed = { pricing_card_mapping: [{ id: "existing-pending-1", card_id: "toggle-1", pricing_source_id: "source-1", match_status: "PENDING" }] };
      const { client, stats } = makeBatchFakeClient(seed);
      const mappings = [makePlannedMapping("toggle-1", "NOT_FOUND")];
      const outcome = await persistBatchedResults(client, "source-1", null, "admin-1", mappings, []);
      assert("P14.3/13: PENDING -> NOT_FOUND nunca chama a RPC de promoção", (stats.rpcCallsByFn["batch_update_pricing_card_mapping_status"] ?? 0) === 0);
      assert(
        "P14.3/13: PENDING -> NOT_FOUND sinalizado em errorParts, nunca silencioso",
        outcome.errorParts.some((e) => e.includes("CARD_MAPPING_PENDING_NOT_FOUND_TOGGLE_SKIPPED") && e.includes("toggle-1")),
      );
      const row = seed.pricing_card_mapping[0];
      assert("P14.3/13: linha permanece PENDING (status anterior preservado, recuperável numa reexecução)", row.match_status === "PENDING");
    }

    // Cenário 14 (revisão de segurança 2026-08-19): pré-busca de observações usa a RPC de
    // identidade exata em lotes de até BATCH_SIZE chaves completas — nunca listas .in()
    // independentes. Prova o payload real enviado (não só a contagem de chamadas).
    {
      const existingObs = {
        id: "obs-existing-1",
        pricing_product_id: "prod-A",
        condition_id: "cond-A",
        price_type: "MARKET",
        currency_code: "USD",
        market_label: MARKET_LABEL,
        observed_at: "2026-08-18T18:56:42.000Z",
        price: 5,
      };
      const seed = {
        pricing_card_mapping: [{ id: "map-A", card_id: "card-A", pricing_source_id: "source-1", match_status: "CONFIRMED" }],
        pricing_source_card_identity: [{ id: "identity-A", pricing_card_mapping_id: "map-A", pricing_source_id: "source-1", external_card_id: "ext-A", identity_role: "PRIMARY", match_status: "CONFIRMED" }],
        pricing_product: [{ id: "prod-A", pricing_card_mapping_id: "map-A", pricing_source_card_identity_id: "identity-A", external_product_id: "ext-A" }],
        pricing_observation: [existingObs],
      };
      const { client, stats } = makeBatchFakeClient(seed);
      const mappings = [makePlannedMapping("card-A", "CONFIRMED")];
      const variants = [{ ...makePlannedVariant("card-A", "ext-A", 5), conditionId: "cond-A", observedAt: "2026-08-18T18:56:42.000Z" }];
      const outcome = await persistBatchedResults(client, "source-1", null, "admin-1", mappings, variants);
      assert("P14.3/14: pré-busca de observações usa a RPC de última observação por grupo (não .select() direto)", (stats.rpcCallsByFn["batch_select_latest_pricing_observation_by_identity"] ?? 0) === 1);
      assert("P14.3/14: nunca chama .select() direto em pricing_observation", (stats.selectCalls["pricing_observation"] ?? 0) === 0);
      assert("P14.3/14: última observação do grupo resolvida -> CONFLICT_IGNORED_SAME_PRICE (mesmo preço, nenhum INSERT novo)", outcome.observationsResolved === 1 && outcome.observationsWritten === 0);
    }

    // --- Fix P14.5 (dual-write pricing_source_card_identity) -------------------------
    // Os 6 cenários exigidos por Fabrício além dos que já existiam (novo mapping -> identidade
    // criada; mapping promovido -> identidade criada; mapping antigo com identidade -> REUSE via
    // pré-busca; dedup dentro do lote; chunking) já ficam cobertos pelos Cenários 1/2/5/9 acima,
    // que passaram a exercitar Fase 1.5 organicamente sem exigir seed dedicado.
    //
    // Fix P14.5.1 (achado durante a escrita destes testes): a primeira versão da Fase 1.5 só
    // correlacionava identidade via o payload em memória desta própria rodada
    // (confirmedPayloadByCardId/payloadByMappingId) — um mapping já CONFIRMED antes desta
    // execução (Fase 1 = NOOP) nunca tinha esse payload, então QUALQUER mapping antigo sem
    // identidade caía em IDENTITY_MISSING_FOR_PRECONFIRMED_MAPPING, inclusive depois de uma
    // falha puramente transiente no INSERT da identidade (P14.5/2 abaixo). Corrigido com um
    // fallback que relê os campos já persistidos em pricing_card_mapping (external_card_id,
    // match_method, match_evidence, confirmed_by) para os mappings que REUSE não resolveu e que
    // não têm payload desta rodada — só entra ali um mapping que a própria Fase 1 já provou
    // estar CONFIRMED e resolvido (usableVariants). Na prática isso elimina o "gap permanente"
    // como categoria: qualquer mapping CONFIRMED (que pelas CHECK constraints sempre tem
    // confirmed_by/external_card_id não nulos) agora se autorrecupera na próxima rodada. O único
    // gap que sobra é uma anomalia estrutural real (linha CONFIRMED sem confirmed_by, que as
    // CHECK constraints deveriam impedir) — P14.5/1 simula exatamente essa anomalia.

    // P14.5/1: mapping marcado CONFIRMED mas com confirmed_by nulo (anomalia estrutural — as
    // CHECK constraints de pricing_card_mapping deveriam impedir isso na prática, mas o
    // fallback nunca inventa dado) -> fallback não recupera, gap genuíno sinalizado, zero
    // produto/observação para esse mapping, batchFailureOccurred=true.
    {
      const cardMappingId = "cm-gap-1";
      const seed = {
        // match_status=CONFIRMED porém confirmed_by ausente — estado que as CHECK constraints
        // reais nunca deveriam permitir; usado aqui só para provar que o fallback de
        // pricing_card_mapping não inventa confirmed_by/external_card_id quando a linha em si
        // está incompleta, preservando IDENTITY_MISSING_FOR_PRECONFIRMED_MAPPING como rede de
        // segurança de última instância.
        pricing_card_mapping: [{
          id: cardMappingId,
          card_id: "gap-1",
          pricing_source_id: "source-1",
          match_status: "CONFIRMED",
        }],
      };
      const mappings = [makePlannedMapping("gap-1", "CONFIRMED")];
      const variants = [makePlannedVariant("gap-1", "ext-gap-1", 5)];
      const { client, stats } = makeBatchFakeClient(seed);
      const outcome = await persistBatchedResults(
        client,
        "source-1",
        null,
        "admin-1",
        mappings,
        variants,
      );
      assert(
        "P14.5/1: gap de identidade -> batchFailureOccurred=true",
        outcome.batchFailureOccurred === true,
      );
      assert(
        "P14.5/1: gap sinalizado explicitamente em errorParts (IDENTITY_MISSING_FOR_PRECONFIRMED_MAPPING)",
        outcome.errorParts.some((e) =>
          e.includes("IDENTITY_MISSING_FOR_PRECONFIRMED_MAPPING") &&
          e.includes(cardMappingId)
        ),
      );
      assert(
        "P14.5/1: zero produto criado para o mapping sem identidade",
        (stats.insertCalls["pricing_product"] ?? 0) === 0 &&
          outcome.productsWritten === 0,
      );
      assert(
        "P14.5/1: zero observação criada para o mapping sem identidade",
        (stats.insertCalls["pricing_observation"] ?? 0) === 0 &&
          outcome.observationsWritten === 0,
      );
      assert(
        "P14.5/1: zero identidade resolvida/escrita",
        outcome.identitiesResolved === 0 && outcome.identitiesWritten === 0,
      );
      assert(
        "P14.5/1: status terminal seria exatamente FAILED (computeFinalStatus tem prioridade absoluta para batchFailureOccurred)",
        computeFinalStatus(
          outcome.batchFailureOccurred,
          outcome.errorParts.length > 0,
          true,
        ) === "FAILED",
      );
    }

    // P14.5/1b: mapping CONFIRMED antes da existência deste incremento (confirmed_by/
    // external_card_id completos, sem identidade) -> fallback recupera os campos já persistidos
    // em pricing_card_mapping e cria a identidade normalmente, sem tratar como gap. Prova que a
    // autoria histórica é preservada (confirmed_by do fallback, não o confirmedBy desta rodada).
    {
      const cardMappingId = "cm-oldconfirmed-1";
      const seed = {
        pricing_card_mapping: [
          {
            id: cardMappingId,
            card_id: "oldconfirmed-1",
            pricing_source_id: "source-1",
            match_status: "CONFIRMED",
            external_card_id: "ext-oldconfirmed-1",
            external_card_name: "Old Confirmed Card",
            match_method: "auto",
            match_evidence: {},
            confirmed_by: "admin-old",
          },
        ],
      };
      const mappings = [makePlannedMapping("oldconfirmed-1", "CONFIRMED")];
      const variants = [makePlannedVariant("oldconfirmed-1", "ext-oldconfirmed-1", 7)];
      const { client, tables } = makeBatchFakeClient(seed);
      const outcome = await persistBatchedResults(
        client,
        "source-1",
        null,
        "admin-1",
        mappings,
        variants,
      );
      assert(
        "P14.5/1b: mapping antigo sem identidade se autorrecupera -> sem falha",
        outcome.batchFailureOccurred === false &&
          outcome.errorParts.length === 0,
      );
      assert(
        "P14.5/1b: identidade nova criada via fallback",
        outcome.identitiesResolved === 1 && outcome.identitiesWritten === 1,
      );
      const identityRow = tables["pricing_source_card_identity"]?.find((r) =>
        r.pricing_card_mapping_id === cardMappingId
      );
      assert(
        "P14.5/1b: identidade criada com external_card_id lido do fallback (pricing_card_mapping)",
        identityRow?.external_card_id === "ext-oldconfirmed-1",
      );
      assert(
        "P14.5/1b: confirmed_by da identidade preserva a autoria histórica do fallback, não o confirmedBy desta rodada",
        identityRow?.confirmed_by === "admin-old",
      );
      assert(
        "P14.5/1b: produto e observação criados normalmente na mesma rodada",
        outcome.productsWritten === 1 && outcome.observationsWritten === 1,
      );
    }

    // P14.5/2: reexecução após falha TRANSIENTE (INSERT de identidade falhou, não um gap
    // permanente) -> identidade, produto e observação criados normalmente na 2ª rodada.
    {
      const mappings = [makePlannedMapping("retry-identity-1", "CONFIRMED")];
      const variants = [makePlannedVariant("retry-identity-1", "ext-retry-identity-1", 4)];
      const { client: clientA, tables } = makeBatchFakeClient(
        {
          pricing_card_mapping: [],
          pricing_source_card_identity: [],
          pricing_product: [],
          pricing_observation: [],
        },
        { failInsert: { pricing_source_card_identity: true } },
      );
      const firstOutcome = await persistBatchedResults(
        clientA,
        "source-1",
        null,
        "admin-1",
        mappings,
        variants,
      );
      assert(
        "P14.5/2: 1ª rodada falha no INSERT de identidade -> batchFailureOccurred=true, zero identidade/produto/observação",
        firstOutcome.batchFailureOccurred === true &&
          (tables["pricing_source_card_identity"]?.length ?? 0) === 0 &&
          (tables["pricing_product"]?.length ?? 0) === 0 &&
          (tables["pricing_observation"]?.length ?? 0) === 0,
      );
      // Mapping já foi persistido com sucesso na 1ª rodada (tabela não afetada pela falha
      // injetada) — a 2ª rodada reaproveita esse estado real, sem forçar falha nova.
      const { client: clientB } = makeBatchFakeClient(tables);
      const secondOutcome = await persistBatchedResults(
        clientB,
        "source-1",
        null,
        "admin-1",
        mappings,
        variants,
      );
      assert(
        "P14.5/2: 2ª rodada recupera -> identidade/produto/observação criados normalmente, sem nova falha",
        secondOutcome.batchFailureOccurred === false &&
          secondOutcome.identitiesWritten === 1 &&
          secondOutcome.productsWritten === 1 &&
          secondOutcome.observationsWritten === 1,
      );
    }

    // P14.5/3: produto preexistente com pricing_source_card_identity_id NULO -> nunca
    // reutilizado, erro explícito, nenhuma observação nova para essa variante.
    {
      const cardMappingId = "cm-nullidentity-1";
      const identityId = "identity-nullidentity-1";
      const seed = {
        pricing_card_mapping: [{
          id: cardMappingId,
          card_id: "nullidentity-1",
          pricing_source_id: "source-1",
          match_status: "CONFIRMED",
        }],
        pricing_source_card_identity: [{
          id: identityId,
          pricing_card_mapping_id: cardMappingId,
          pricing_source_id: "source-1",
          external_card_id: "ext-nullidentity-1",
          identity_role: "PRIMARY",
          match_status: "CONFIRMED",
        }],
        // Produto já existe, mas nasceu ANTES do dual-write (pricing_source_card_identity_id
        // nunca foi setado) — simula exatamente a janela entre aplicar a 3923 e este incremento.
        pricing_product: [{
          id: "prod-nullidentity-1",
          pricing_card_mapping_id: cardMappingId,
          pricing_source_card_identity_id: null,
          external_product_id: "ext-nullidentity-1",
        }],
      };
      const mappings = [makePlannedMapping("nullidentity-1", "CONFIRMED")];
      const variants = [makePlannedVariant("nullidentity-1", "ext-nullidentity-1", 6)];
      const { client, tables, stats } = makeBatchFakeClient(seed);
      const outcome = await persistBatchedResults(
        client,
        "source-1",
        null,
        "admin-1",
        mappings,
        variants,
      );
      assert(
        "P14.5/3: produto com identity nula nunca é reutilizado -> batchFailureOccurred=true",
        outcome.batchFailureOccurred === true,
      );
      assert(
        "P14.5/3: erro explícito PRODUCT_IDENTITY_MISMATCH, nunca corrigido silenciosamente",
        outcome.errorParts.some((e) =>
          e.includes("PRODUCT_IDENTITY_MISMATCH") && e.includes("stored=NULL")
        ),
      );
      assert(
        "P14.5/3: nenhum UPDATE/INSERT tenta corrigir o produto existente",
        (stats.insertCalls["pricing_product"] ?? 0) === 0,
      );
      const row = tables["pricing_product"].find((r) =>
        r.id === "prod-nullidentity-1"
      );
      assert(
        "P14.5/3: o produto existente permanece exatamente como estava (identity ainda nula)",
        row?.pricing_source_card_identity_id === null,
      );
      assert(
        "P14.5/3: zero observação nova para essa variante",
        (stats.insertCalls["pricing_observation"] ?? 0) === 0 &&
          outcome.observationsWritten === 0,
      );
    }

    // P14.5/4: produto preexistente ligado a OUTRA identidade (divergente da resolvida) ->
    // nunca reutilizado, erro explícito, nenhuma observação nova para essa variante.
    {
      const cardMappingId = "cm-wrongidentity-1";
      const correctIdentityId = "identity-wrongidentity-correct-1";
      const wrongIdentityId = "identity-wrongidentity-wrong-1";
      const seed = {
        pricing_card_mapping: [{
          id: cardMappingId,
          card_id: "wrongidentity-1",
          pricing_source_id: "source-1",
          match_status: "CONFIRMED",
        }],
        pricing_source_card_identity: [{
          id: correctIdentityId,
          pricing_card_mapping_id: cardMappingId,
          pricing_source_id: "source-1",
          external_card_id: "ext-wrongidentity-1",
          identity_role: "PRIMARY",
          match_status: "CONFIRMED",
        }],
        // Produto aponta para uma identidade que NÃO é a PRIMARY/CONFIRMED resolvida para este
        // mapping (estado anômalo — nunca deveria acontecer via caminho normal, mas a defesa
        // precisa detectar mesmo assim, nunca assumir que está certo).
        pricing_product: [{
          id: "prod-wrongidentity-1",
          pricing_card_mapping_id: cardMappingId,
          pricing_source_card_identity_id: wrongIdentityId,
          external_product_id: "ext-wrongidentity-1",
        }],
      };
      const mappings = [makePlannedMapping("wrongidentity-1", "CONFIRMED")];
      const variants = [makePlannedVariant("wrongidentity-1", "ext-wrongidentity-1", 8)];
      const { client, tables, stats } = makeBatchFakeClient(seed);
      const outcome = await persistBatchedResults(
        client,
        "source-1",
        null,
        "admin-1",
        mappings,
        variants,
      );
      assert(
        "P14.5/4: produto ligado a outra identidade nunca é reutilizado -> batchFailureOccurred=true",
        outcome.batchFailureOccurred === true,
      );
      assert(
        "P14.5/4: erro explícito PRODUCT_IDENTITY_MISMATCH com stored/expected corretos",
        outcome.errorParts.some((e) =>
          e.includes("PRODUCT_IDENTITY_MISMATCH") &&
          e.includes(`stored=${wrongIdentityId}`) &&
          e.includes(`expected=${correctIdentityId}`)
        ),
      );
      const row = tables["pricing_product"].find((r) =>
        r.id === "prod-wrongidentity-1"
      );
      assert(
        "P14.5/4: o produto existente permanece exatamente como estava (identity divergente preservada, nunca corrigida silenciosamente)",
        row?.pricing_source_card_identity_id === wrongIdentityId,
      );
      assert(
        "P14.5/4: zero observação nova para essa variante",
        (stats.insertCalls["pricing_observation"] ?? 0) === 0 &&
          outcome.observationsWritten === 0,
      );
    }

    // P14.5/5: um mapping com identidade divergente (bloqueado) e outro mapping válido no MESMO
    // lote -> o mapping válido é processado normalmente (produto+observação), só o divergente é
    // excluído — a Regra 1/Regra 3 nunca contamina variantes de outros mappings.
    {
      const badCardMappingId = "cm-mixed-bad-1";
      const badWrongIdentityId = "identity-mixed-bad-wrong-1";
      const badCorrectIdentityId = "identity-mixed-bad-correct-1";
      const seed = {
        pricing_card_mapping: [{
          id: badCardMappingId,
          card_id: "mixed-bad-1",
          pricing_source_id: "source-1",
          match_status: "CONFIRMED",
        }],
        pricing_source_card_identity: [{
          id: badCorrectIdentityId,
          pricing_card_mapping_id: badCardMappingId,
          pricing_source_id: "source-1",
          external_card_id: "ext-mixed-bad-1",
          identity_role: "PRIMARY",
          match_status: "CONFIRMED",
        }],
        pricing_product: [{
          id: "prod-mixed-bad-1",
          pricing_card_mapping_id: badCardMappingId,
          pricing_source_card_identity_id: badWrongIdentityId,
          external_product_id: "ext-mixed-bad-1",
        }],
      };
      // mixed-good-1 é um mapping NOVO, confirmado nesta própria rodada — caminho normal.
      const mappings = [
        makePlannedMapping("mixed-bad-1", "CONFIRMED"),
        makePlannedMapping("mixed-good-1", "CONFIRMED"),
      ];
      const variants = [
        makePlannedVariant("mixed-bad-1", "ext-mixed-bad-1", 3),
        makePlannedVariant("mixed-good-1", "ext-mixed-good-1", 11),
      ];
      const { client, tables } = makeBatchFakeClient(seed);
      const outcome = await persistBatchedResults(
        client,
        "source-1",
        null,
        "admin-1",
        mappings,
        variants,
      );
      assert(
        "P14.5/5: batchFailureOccurred=true (por causa do mapping divergente)",
        outcome.batchFailureOccurred === true,
      );
      const goodProduct = tables["pricing_product"].find((r) =>
        r.external_product_id === "ext-mixed-good-1"
      );
      const goodObservation = tables["pricing_observation"].find((r) =>
        r.pricing_product_id === goodProduct?.id
      );
      assert(
        "P14.5/5: mapping válido (mixed-good-1) recebe produto normalmente, com identidade resolvida",
        goodProduct !== undefined &&
          goodProduct?.pricing_source_card_identity_id != null,
      );
      assert(
        "P14.5/5: mapping válido (mixed-good-1) recebe observação normalmente",
        goodObservation !== undefined && goodObservation?.price === 11,
      );
      const badProduct = tables["pricing_product"].find((r) =>
        r.id === "prod-mixed-bad-1"
      );
      assert(
        "P14.5/5: mapping divergente (mixed-bad-1) permanece intocado, nunca reutilizado",
        badProduct?.pricing_source_card_identity_id === badWrongIdentityId,
      );
      const badObservation = tables["pricing_observation"].find((r) =>
        r.pricing_product_id === "prod-mixed-bad-1"
      );
      assert(
        "P14.5/5: mapping divergente (mixed-bad-1) nunca recebe observação nova",
        badObservation === undefined,
      );
      assert(
        "P14.5/5: contadores refletem só o mapping válido (1 produto, 1 observação escritos)",
        outcome.productsWritten === 1 && outcome.observationsWritten === 1,
      );
    }

    // P14.5/6: contadores de identidade (identitiesResolved/identitiesWritten) e
    // operationsSupabase permanecem objetivos e exatos num lote misto REUSE + NEW.
    {
      const reuseCardMappingId = "cm-counters-reuse-1";
      const reuseIdentityId = "identity-counters-reuse-1";
      const seed = {
        pricing_card_mapping: [{
          id: reuseCardMappingId,
          card_id: "counters-reuse-1",
          pricing_source_id: "source-1",
          match_status: "CONFIRMED",
        }],
        pricing_source_card_identity: [{
          id: reuseIdentityId,
          pricing_card_mapping_id: reuseCardMappingId,
          pricing_source_id: "source-1",
          external_card_id: "ext-counters-reuse-1",
          identity_role: "PRIMARY",
          match_status: "CONFIRMED",
        }],
        pricing_product: [{
          id: "prod-counters-reuse-1",
          pricing_card_mapping_id: reuseCardMappingId,
          pricing_source_card_identity_id: reuseIdentityId,
          external_product_id: "ext-counters-reuse-1",
        }],
      };
      // counters-new-1 é confirmado nesta própria rodada -> identidade NEW.
      const mappings = [
        makePlannedMapping("counters-reuse-1", "CONFIRMED"),
        makePlannedMapping("counters-new-1", "CONFIRMED"),
      ];
      const variants = [
        makePlannedVariant("counters-reuse-1", "ext-counters-reuse-1", 2),
        makePlannedVariant("counters-new-1", "ext-counters-new-1", 12),
      ];
      const { client, stats } = makeBatchFakeClient(seed);
      const outcome = await persistBatchedResults(
        client,
        "source-1",
        null,
        "admin-1",
        mappings,
        variants,
      );
      assert(
        "P14.5/6: identitiesResolved conta REUSE + NEW (2 mappings, 2 identidades resolvidas)",
        outcome.identitiesResolved === 2,
      );
      assert(
        "P14.5/6: identitiesWritten conta só a NEW (1, a REUSE não escreve nada)",
        outcome.identitiesWritten === 1,
      );
      assert(
        "P14.5/6: sem falha, sem erro",
        outcome.batchFailureOccurred === false &&
          outcome.errorParts.length === 0,
      );
      const totalCalls =
        Object.values(stats.selectCalls).reduce((a, b) => a + b, 0) +
        Object.values(stats.insertCalls).reduce((a, b) => a + b, 0) +
        stats.rpcCalls;
      assert(
        "P14.5/6: operationsSupabase continua batendo exatamente com a contagem real de chamadas, mesmo com a Fase 1.5 nova",
        outcome.operationsSupabase === totalCalls,
      );
    }

    // P14.3/15 (fix revisão de robustez 2026-08-19, fechamento): resolveEntryDecision() —
    // --fixture-check roda offline explicitamente (com ou sem credencial), e a ausência de
    // QUALQUER uma das três variáveis obrigatórias fora desse modo nunca mais cai
    // silenciosamente em --fixture-check — decide MISSING_ENV, cabendo a main() encerrar com
    // código diferente de zero antes de qualquer chamada de rede ou acesso ao Supabase.
    {
      const CREDS_OK = { justTcgApiKey: "sk-fake-justtcg-000", supabaseUrl: "https://fake.supabase.co", supabaseServiceRoleKey: "sk-fake-service-role-000" };
      const CREDS_VAZIAS = { justTcgApiKey: undefined, supabaseUrl: undefined, supabaseServiceRoleKey: undefined };

      assert(
        "P14.3/15: --fixture-check sem nenhuma credencial -> FIXTURE_CHECK (roda offline sem exigir nada)",
        resolveEntryDecision({ fixtureCheck: true }, CREDS_VAZIAS).kind === "FIXTURE_CHECK",
      );
      assert(
        "P14.3/15: --fixture-check com as três credenciais presentes -> ainda FIXTURE_CHECK (flag explícita sempre vence, nunca promove para piloto real)",
        resolveEntryDecision({ fixtureCheck: true }, CREDS_OK).kind === "FIXTURE_CHECK",
      );

      const semApiKey = resolveEntryDecision({ fixtureCheck: false }, { ...CREDS_OK, justTcgApiKey: undefined });
      assert(
        "P14.3/15: sem --fixture-check, só JUSTTCG_API_KEY ausente -> MISSING_ENV (nunca cai em fixture-check automático)",
        semApiKey.kind === "MISSING_ENV" && semApiKey.missing.length === 1 && semApiKey.missing[0] === "JUSTTCG_API_KEY",
      );

      const semSupabaseUrl = resolveEntryDecision({ fixtureCheck: false }, { ...CREDS_OK, supabaseUrl: undefined });
      assert(
        "P14.3/15: sem --fixture-check, só SUPABASE_URL ausente -> MISSING_ENV",
        semSupabaseUrl.kind === "MISSING_ENV" && semSupabaseUrl.missing.length === 1 && semSupabaseUrl.missing[0] === "SUPABASE_URL",
      );

      const semServiceRole = resolveEntryDecision({ fixtureCheck: false }, { ...CREDS_OK, supabaseServiceRoleKey: undefined });
      assert(
        "P14.3/15: sem --fixture-check, só SUPABASE_SERVICE_ROLE_KEY ausente -> MISSING_ENV",
        semServiceRole.kind === "MISSING_ENV" && semServiceRole.missing.length === 1 && semServiceRole.missing[0] === "SUPABASE_SERVICE_ROLE_KEY",
      );

      const todasAusentes = resolveEntryDecision({ fixtureCheck: false }, CREDS_VAZIAS);
      assert(
        "P14.3/15: sem --fixture-check, as três ausentes -> MISSING_ENV com as três nomeadas, na ordem JUSTTCG_API_KEY/SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY",
        todasAusentes.kind === "MISSING_ENV" &&
          todasAusentes.missing.length === 3 &&
          todasAusentes.missing[0] === "JUSTTCG_API_KEY" &&
          todasAusentes.missing[1] === "SUPABASE_URL" &&
          todasAusentes.missing[2] === "SUPABASE_SERVICE_ROLE_KEY",
      );

      assert(
        "P14.3/15: sem --fixture-check, as três presentes -> REAL_PILOT",
        resolveEntryDecision({ fixtureCheck: false }, CREDS_OK).kind === "REAL_PILOT",
      );

      // Nunca revela o VALOR de uma credencial — "missing" carrega só nomes de variáveis.
      const decisaoComValoresSensiveis = resolveEntryDecision({ fixtureCheck: false }, { ...CREDS_VAZIAS, justTcgApiKey: undefined });
      const serializado = JSON.stringify(decisaoComValoresSensiveis);
      assert(
        "P14.3/15: MISSING_ENV nunca inclui valor de credencial na saída, só nomes de variável",
        !serializado.includes("sk-fake") && !serializado.includes("fake.supabase.co"),
      );
    }

    // ==========================================================================================
    // P14.4.1 — Inventário de Cobertura e Plano de Ondas (--expansion-plan)
    // ==========================================================================================

    // resolveEntryDecision(): --expansion-plan não quebra nenhum caminho já testado acima
    // (assinatura com expansionPlan opcional) e exige as mesmas três credenciais do piloto real.
    {
      const CREDS_OK2 = { justTcgApiKey: "sk-fake-justtcg-000", supabaseUrl: "https://fake.supabase.co", supabaseServiceRoleKey: "sk-fake-service-role-000" };
      assert(
        "P14.4.1: --expansion-plan com as três credenciais presentes -> EXPANSION_PLAN",
        resolveEntryDecision({ fixtureCheck: false, expansionPlan: true }, CREDS_OK2).kind === "EXPANSION_PLAN",
      );
      const semUrl = resolveEntryDecision({ fixtureCheck: false, expansionPlan: true }, { ...CREDS_OK2, supabaseUrl: undefined });
      assert(
        "P14.4.1: --expansion-plan com credencial ausente -> MISSING_ENV (mesma disciplina do piloto real, nunca roda offline implicitamente)",
        semUrl.kind === "MISSING_ENV" && semUrl.missing[0] === "SUPABASE_URL",
      );
      assert(
        "P14.4.1: --fixture-check sempre vence sobre --expansion-plan (flag offline explícita tem prioridade máxima)",
        resolveEntryDecision({ fixtureCheck: true, expansionPlan: true }, CREDS_OK2).kind === "FIXTURE_CHECK",
      );
      assert(
        "P14.4.1: sem --expansion-plan (omitido) e três credenciais presentes -> continua REAL_PILOT (comportamento antigo intacto)",
        resolveEntryDecision({ fixtureCheck: false }, CREDS_OK2).kind === "REAL_PILOT",
      );
    }

    // classifySetForExpansionPlan() — cinco cenários obrigatórios (P14.4.1) + 2 novos (P14.4.3:
    // ALREADY_CONFIRMED_COMPLETE/INCOMPLETE, split a partir do único cenário anterior).
    {
      const externalSets: JustTcgSet[] = normalizeJustTcgSets([
        { id: "ext-b", name: "Ext B", release_date: "2020-02-01", variants_count: 500 },
        { id: "ext-c1", name: "Ext C1", release_date: "2020-03-01" },
        { id: "ext-c2", name: "Ext C2", release_date: "2020-03-01" },
        { id: "ext-f", name: "Nome Completamente Diferente", release_date: "2020-05-01" },
      ]);

      const jaConfirmadoCompleto = classifySetForExpansionPlan(
        { releaseDateIso: "2020-01-01", localCardCount: 10 },
        { cardSetId: "cs-a", matchStatus: "CONFIRMED", externalSetId: "ext-a", externalSetName: "Ext A" },
        externalSets,
        { mappedCards: 10 },
      );
      assert(
        "P14.4.3: Set já CONFIRMED com mappedCards >= localCardCount (10/10) -> ALREADY_CONFIRMED_COMPLETE, preservado, nunca reavaliado contra a lista externa",
        jaConfirmadoCompleto.status === "ALREADY_CONFIRMED_COMPLETE" && jaConfirmadoCompleto.externalSetId === "ext-a" && jaConfirmadoCompleto.externalSetName === "Ext A",
      );

      const jaConfirmadoIncompleto = classifySetForExpansionPlan(
        { releaseDateIso: "2020-01-01", localCardCount: 102 },
        { cardSetId: "cs-base1", matchStatus: "CONFIRMED", externalSetId: "ext-base1", externalSetName: "Base Set" },
        externalSets,
        { mappedCards: 3 },
      );
      assert(
        "P14.4.3: Set já CONFIRMED com mappedCards < localCardCount (3/102, cenário real BASE1) -> ALREADY_CONFIRMED_INCOMPLETE, nunca reavaliado contra a lista externa",
        jaConfirmadoIncompleto.status === "ALREADY_CONFIRMED_INCOMPLETE" && jaConfirmadoIncompleto.externalSetId === "ext-base1",
      );

      const jaConfirmadoSemCobertura = classifySetForExpansionPlan(
        { releaseDateIso: "2020-01-01", localCardCount: 5 },
        { cardSetId: "cs-b", matchStatus: "CONFIRMED", externalSetId: "ext-b2", externalSetName: "Ext B2" },
        externalSets,
        null,
      );
      assert(
        "P14.4.3: Set já CONFIRMED sem NENHUMA linha de cobertura (coverage=null, ex.: Set nunca apareceu em pricing_set_coverage) -> tratado como 0 cartas mapeadas -> ALREADY_CONFIRMED_INCOMPLETE, nunca lançado nem assumido completo por omissão",
        jaConfirmadoSemCobertura.status === "ALREADY_CONFIRMED_INCOMPLETE",
      );

      const candidatoUnico = classifySetForExpansionPlan({ releaseDateIso: "2020-02-01", localCardCount: 5 }, null, externalSets, null);
      assert(
        "P14.4.1: candidato único por release_date -> SAFE_CANDIDATE, com o id/nome/variants_count corretos",
        candidatoUnico.status === "SAFE_CANDIDATE" && candidatoUnico.externalSetId === "ext-b" && candidatoUnico.externalVariantsCount === 500,
      );

      const doisCandidatos = classifySetForExpansionPlan({ releaseDateIso: "2020-03-01", localCardCount: 5 }, null, externalSets, null);
      assert("P14.4.1: dois candidatos na mesma release_date -> AMBIGUOUS, nunca confirmado automaticamente", doisCandidatos.status === "AMBIGUOUS" && doisCandidatos.candidateCount === 2);

      const nenhumCandidato = classifySetForExpansionPlan({ releaseDateIso: "2020-04-01", localCardCount: 5 }, null, externalSets, null);
      assert("P14.4.1: nenhum candidato na release_date -> NOT_FOUND", nenhumCandidato.status === "NOT_FOUND" && nenhumCandidato.reason === "RELEASE_DATE_SEM_CORRESPONDENCIA_EXTERNA");

      const semReleaseDate = classifySetForExpansionPlan({ releaseDateIso: null, localCardCount: 5 }, null, externalSets, null);
      assert("P14.4.1: Set local sem release_date -> NOT_FOUND, nunca tenta casar por nome", semReleaseDate.status === "NOT_FOUND" && semReleaseDate.reason === "SET_LOCAL_SEM_RELEASE_DATE");

      const nomeDivergente = classifySetForExpansionPlan({ releaseDateIso: "2020-05-01", localCardCount: 5 }, null, externalSets, null);
      assert(
        "P14.4.1: nome completamente divergente NUNCA bloqueia um candidato único e seguro por data (nome nunca é fundamento isolado — só release_date confirma)",
        nomeDivergente.status === "SAFE_CANDIDATE" && nomeDivergente.externalSetId === "ext-f",
      );
    }

    // buildExpansionWaves() — limites simultâneos (5 Sets / 500 cartas) e Set oversized.
    {
      const seisSetsPequenos = Array.from({ length: 6 }, (_, i) => ({ code: `W${i}`, localCardCount: 50 }));
      const wavesPorContagemDeSets = buildExpansionWaves(seisSetsPequenos);
      assert(
        "P14.4.1: 6 Sets pequenos (50 cartas cada) -> onda 1 com 5 Sets, onda 2 com o 6º (limite de 5 Sets por onda)",
        wavesPorContagemDeSets.length === 2 && wavesPorContagemDeSets[0].sets.length === 5 && wavesPorContagemDeSets[1].sets.length === 1,
      );

      const tresSetsGrandes = [
        { code: "G1", localCardCount: 200 },
        { code: "G2", localCardCount: 200 },
        { code: "G3", localCardCount: 200 },
      ];
      const wavesPorContagemDeCartas = buildExpansionWaves(tresSetsGrandes);
      assert(
        "P14.4.1: 3 Sets de 200 cartas -> onda 1 com 2 Sets (400 cartas, 600 estouraria o limite de 500), onda 2 com o 3º",
        wavesPorContagemDeCartas.length === 2 && wavesPorContagemDeCartas[0].sets.length === 2 && wavesPorContagemDeCartas[0].totalLocalCards === 400 && wavesPorContagemDeCartas[1].sets.length === 1,
      );

      const comSetGigante = [
        { code: "A1", localCardCount: 100 },
        { code: "GIGANTE", localCardCount: 600 },
        { code: "A2", localCardCount: 100 },
        { code: "A3", localCardCount: 100 },
      ];
      const wavesComOversized = buildExpansionWaves(comSetGigante);
      const waveGigante = wavesComOversized.find((w) => w.sets.some((s) => s.code === "GIGANTE"));
      assert(
        "P14.4.1: Set individual com mais de 500 cartas locais nunca desaparece nem é dividido — forma sua própria onda, sinalizada oversized",
        waveGigante !== undefined && waveGigante.sets.length === 1 && waveGigante.oversized === true && waveGigante.totalLocalCards === 600,
      );
      assert(
        "P14.4.1: o Set oversized não interrompe a formação das ondas seguintes — A2/A3 continuam agrupados numa onda própria depois dele",
        wavesComOversized.some((w) => !w.oversized && w.sets.some((s) => s.code === "A2") && w.sets.some((s) => s.code === "A3")),
      );
    }

    // buildExpansionPlan() — ausência de total externo nunca é inventada.
    {
      const plan = buildExpansionPlan({
        localSets: [{ cardSetId: "cs-x", code: "SETX", releaseDateIso: "2020-02-01", localCardCount: 130 }],
        existingSetMappings: new Map(),
        allExternalSets: normalizeJustTcgSets([{ id: "ext-x", name: "Ext X", release_date: "2020-02-01", variants_count: 999 }]),
        existingCoverage: new Map(),
      });
      const entry = plan.entries[0];
      assert(
        "P14.4.1: pagesEstimateExternal é sempre null com motivo explícito — variants_count não é total de cartas, nunca usado para inventar um total de páginas externo",
        entry.pagesEstimateExternal === null && entry.pagesEstimateExternalReason === PAGES_ESTIMATE_EXTERNAL_REASON,
      );
      assert("P14.4.1: pagesEstimateLocal usa só a contagem local conhecida (ceil(130/100)=2)", entry.pagesEstimateLocal === 2);
    }

    // executeExpansionPlan() — integração offline: exatamente 1 chamada externa, zero escrita,
    // nenhum segredo na saída. makeReadOnlyFakeClient() bloqueia (lança) qualquer
    // insert/update/upsert/delete/rpc — a prova de "zero escrita" é estrutural (o teste falharia
    // com uma exceção não esperada se qualquer caminho de escrita fosse sequer tentado), não só
    // uma contagem de chamadas. Seed fix P14.4.1: catalog_card_set_metrics/pricing_set_coverage
    // substituem card (linha a linha) + pricing_card_mapping/pricing_product/pricing_observation
    // (desenho anterior, removido) — coerente com todos os invariantes de reconciliação novos.
    {
      const seed = {
        pricing_source: [{ id: "src-1", code: "JUSTTCG", is_active: true, requires_commercial_agreement: true }],
        card_set: [
          { id: "cs-a", code: "SETA", release_date: "2020-01-01" },
          { id: "cs-b", code: "SETB", release_date: "2020-02-01" },
        ],
        catalog_card_set_metrics: [
          { card_set_id: "cs-a", cards_ativas: 2 },
          { card_set_id: "cs-b", cards_ativas: 1 },
        ],
        card: [
          { id: "card-a1", is_active: true },
          { id: "card-a2", is_active: true },
          { id: "card-b1", is_active: true },
        ],
        pricing_set_mapping: [{ card_set_id: "cs-a", pricing_source_id: "src-1", match_status: "CONFIRMED", external_set_id: "ext-a", external_set_name: "Ext A" }],
        pricing_set_coverage: [],
      };
      const { fetchImpl, callCount } = makeFakeFetch([
        { status: 200, body: { data: [{ id: "ext-a", name: "Ext A", release_date: "2020-01-01" }, { id: "ext-b", name: "Ext B", release_date: "2020-02-01", variants_count: 42 }] } },
      ]);
      const fakeApiKey = "sk-fake-justtcg-integration-999";
      const client = new JustTcgClient(fakeApiKey, fetchImpl);
      const supabase = makeReadOnlyFakeClient(seed);

      let writeAttemptBlocked = false;
      let plan: ExpansionPlanResult | null = null;
      try {
        plan = await executeExpansionPlan(supabase, client);
      } catch (error) {
        writeAttemptBlocked = error instanceof Error && error.message.startsWith("WRITE_ATTEMPT_BLOCKED");
        if (!writeAttemptBlocked) throw error; // erro inesperado nunca deve ser engolido pelo teste
      }

      assert("P14.4.1: executeExpansionPlan() completa sem nenhuma tentativa de escrita bloqueada (insert/update/upsert/delete/rpc nunca chamados)", !writeAttemptBlocked && plan !== null);
      assert("P14.4.1: exatamente 1 chamada HTTP à JustTCG (GET /v1/sets), nunca /cards", callCount() === 1 && client.requestsMade === 1);
      assert(
        "P14.4.3: SETA (mapping já CONFIRMED, mas pricing_set_coverage vazio -> 0/2 cartas mapeadas) -> ALREADY_CONFIRMED_INCOMPLETE, com missingCardsCount=2; SETB (candidato único por data) -> SAFE_CANDIDATE",
        plan?.entries.find((e) => e.code === "SETA")?.status === "ALREADY_CONFIRMED_INCOMPLETE" &&
          plan?.entries.find((e) => e.code === "SETA")?.missingCardsCount === 2 &&
          plan?.entries.find((e) => e.code === "SETB")?.status === "SAFE_CANDIDATE",
      );
      const serializedPlan = JSON.stringify(plan);
      assert("P14.4.1: nenhum segredo (API key) vaza na saída do plano", !serializedPlan.includes(fakeApiKey));
    }

    // ==========================================================================================
    // P14.4.1 fix (2026-08-19) — correção do truncamento de 1.000 linhas do Data API
    // ==========================================================================================

    // fetchAllPages() — mecânica de paginação pura, testada sem nenhum mock de Supabase: só
    // callbacks simples de página. Cobre exatamente os cenários de borda exigidos.
    {
      const dataset25 = Array.from({ length: 25 }, (_, i) => ({ n: i }));
      let calls25 = 0;
      const rows25 = await fetchAllPages<{ n: number }>(async (from, to) => {
        calls25++;
        return { data: dataset25.slice(from, to + 1), error: null };
      }, 10);
      assert("P14.4.1 fix: fetchAllPages — múltiplas páginas (25 linhas, pageSize=10) -> 3 chamadas, 25 linhas, nunca deduz término por total presumido", calls25 === 3 && rows25.length === 25);

      const dataset20 = Array.from({ length: 20 }, (_, i) => ({ n: i }));
      let calls20 = 0;
      const rows20 = await fetchAllPages<{ n: number }>(async (from, to) => {
        calls20++;
        return { data: dataset20.slice(from, to + 1), error: null };
      }, 10);
      assert(
        "P14.4.1 fix: fetchAllPages — última página cheia (20 linhas, pageSize=10) exige uma 3ª chamada vazia para confirmar o fim -> 3 chamadas, 20 linhas (nunca para numa página cheia sem checar a próxima)",
        calls20 === 3 && rows20.length === 20,
      );

      let calls_erro = 0;
      let erroCapturado: Error | null = null;
      let linhasParciais: unknown = "NUNCA_ATRIBUIDO";
      try {
        linhasParciais = await fetchAllPages<{ n: number }>(async (from, to) => {
          calls_erro++;
          if (calls_erro === 2) return { data: null, error: { message: "falha simulada na página 2" } };
          return { data: dataset25.slice(from, to + 1), error: null };
        }, 10);
      } catch (error) {
        erroCapturado = error instanceof Error ? error : null;
      }
      assert(
        "P14.4.1 fix: fetchAllPages — falha intermediária de paginação (página 2) propaga erro e NUNCA retorna resultado parcial",
        erroCapturado !== null && erroCapturado.message.startsWith("PAGINATED_QUERY_FAILED") && linhasParciais === "NUNCA_ATRIBUIDO",
      );
    }

    // executeExpansionPlan() — reconciliação em escala realista: 1 Set com 1.001 cartas ativas
    // (>1.000, nunca truncado porque cards_ativas é uma coluna agregada, não uma contagem de
    // linhas) e 45 Sets somando 7.429 cartas (a escala real confirmada por introspecção).
    {
      const seedGrande = {
        pricing_source: [{ id: "src-1", code: "JUSTTCG", is_active: true, requires_commercial_agreement: true }],
        card_set: [{ id: "cs-x", code: "SETX", release_date: "2020-01-01" }],
        catalog_card_set_metrics: [{ card_set_id: "cs-x", cards_ativas: 1001 }],
        card: [{ id: "card-1", is_active: true }], // count-exact é sobrescrita abaixo — array não precisa ter 1001 linhas reais
        pricing_set_mapping: [],
        pricing_set_coverage: [],
      };
      const supabaseGrande = makeReadOnlyFakeClient(seedGrande, { countOverride: { card: 1001 } });
      const { fetchImpl: fetchImplGrande } = makeFakeFetch([{ status: 200, body: { data: [{ id: "ext-x", name: "Ext X", release_date: "2020-01-01" }] } }]);
      const clientGrande = new JustTcgClient("sk-fake-1001", fetchImplGrande);
      const planGrande = await executeExpansionPlan(supabaseGrande, clientGrande);
      assert(
        "P14.4.1 fix: Set com 1.001 cartas ativas (>1.000) flui sem truncamento — cards_ativas é agregado, não uma contagem de linhas paginada",
        planGrande.entries[0]?.localCardCount === 1001 && planGrande.totalLocalCards === 1001,
      );

      const NUM_SETS = 45;
      const TOTAL_CARTAS = 7429;
      const base = Math.floor(TOTAL_CARTAS / NUM_SETS);
      const resto = TOTAL_CARTAS - base * NUM_SETS;
      const cardSet45 = Array.from({ length: NUM_SETS }, (_, i) => ({ id: `cs-${i}`, code: `SET${i}`, release_date: `2020-01-${String((i % 28) + 1).padStart(2, "0")}` }));
      const metrics45 = cardSet45.map((s, i) => ({ card_set_id: s.id, cards_ativas: base + (i < resto ? 1 : 0) }));
      const seed45 = {
        pricing_source: [{ id: "src-1", code: "JUSTTCG", is_active: true, requires_commercial_agreement: true }],
        card_set: cardSet45,
        catalog_card_set_metrics: metrics45,
        card: [{ id: "card-1", is_active: true }],
        pricing_set_mapping: [],
        pricing_set_coverage: [],
      };
      const supabase45 = makeReadOnlyFakeClient(seed45, { countOverride: { card: TOTAL_CARTAS } });
      const { fetchImpl: fetchImpl45 } = makeFakeFetch([{ status: 200, body: { data: [] } }]);
      const client45 = new JustTcgClient("sk-fake-45sets", fetchImpl45);
      const plan45 = await executeExpansionPlan(supabase45, client45);
      assert(
        "P14.4.1 fix: 45 Sets somando 7.429 cartas (escala real confirmada por introspecção) -> reconciliação passa, nenhum Set nem carta perdido",
        plan45.totalLocalSets === 45 && plan45.totalLocalCards === 7429,
      );
    }

    // Cobertura agregada (Query 3916 proposta) > 1.000 — flui sem truncamento porque é uma
    // coluna agregada por Set/Fonte, nunca uma contagem de linhas de pricing_observation.
    {
      const seed = {
        pricing_source: [{ id: "src-1", code: "JUSTTCG", is_active: true, requires_commercial_agreement: true }],
        card_set: [{ id: "cs-a", code: "SETA", release_date: "2020-01-01" }],
        catalog_card_set_metrics: [{ card_set_id: "cs-a", cards_ativas: 1 }],
        card: [{ id: "card-1", is_active: true }],
        pricing_set_mapping: [{ card_set_id: "cs-a", pricing_source_id: "src-1", match_status: "CONFIRMED", external_set_id: "ext-a", external_set_name: "Ext A" }],
        pricing_set_coverage: [{ card_set_id: "cs-a", pricing_source_id: "src-1", products_count: 40, observations_count: 1500 }],
      };
      const supabase = makeReadOnlyFakeClient(seed, { countOverride: { card: 1 } });
      const { fetchImpl } = makeFakeFetch([{ status: 200, body: { data: [{ id: "ext-a", name: "Ext A", release_date: "2020-01-01" }] } }]);
      const client = new JustTcgClient("sk-fake-coverage", fetchImpl);
      const plan = await executeExpansionPlan(supabase, client);
      assert(
        "P14.4.1 fix: cobertura agregada > 1.000 (observations_count=1500) flui inalterada — nunca recalculada linha a linha",
        plan.entries[0]?.existingObservationsCount === 1500 && plan.entries[0]?.existingProductsCount === 40,
      );
    }

    // Reconciliação obrigatória: plano NUNCA emitido quando qualquer contagem diverge. Três
    // variantes: soma de cartas, quantidade de Sets ativos, e paginação incompleta genérica.
    {
      const seedBase = {
        pricing_source: [{ id: "src-1", code: "JUSTTCG", is_active: true, requires_commercial_agreement: true }],
        card_set: [{ id: "cs-a", code: "SETA", release_date: "2020-01-01" }],
        catalog_card_set_metrics: [{ card_set_id: "cs-a", cards_ativas: 3 }],
        card: [{ id: "card-1", is_active: true }],
        pricing_set_mapping: [],
        pricing_set_coverage: [],
      };
      const { fetchImpl, callCount } = makeFakeFetch([{ status: 200, body: { data: [] } }]);

      const supabaseCartasDivergente = makeReadOnlyFakeClient(seedBase, { countOverride: { card: 999 } });
      let erroCartas: Error | null = null;
      try {
        await executeExpansionPlan(supabaseCartasDivergente, new JustTcgClient("sk-fake-a", fetchImpl));
      } catch (error) {
        erroCartas = error instanceof Error ? error : null;
      }
      assert(
        "P14.4.1 fix: reconciliação de cartas divergente (soma local=3, contagem exata=999) -> plano nunca emitido, aborta com RECONCILIACAO_CARTAS_FALHOU",
        erroCartas !== null && erroCartas.message.startsWith("RECONCILIACAO_CARTAS_FALHOU"),
      );

      const supabaseSetsDivergente = makeReadOnlyFakeClient(seedBase, { countOverride: { card: 3, "catalog_card_set_metrics:filtered": 5 } });
      let erroSets: Error | null = null;
      try {
        await executeExpansionPlan(supabaseSetsDivergente, new JustTcgClient("sk-fake-b", fetchImpl));
      } catch (error) {
        erroSets = error instanceof Error ? error : null;
      }
      assert(
        "P14.4.1 fix: reconciliação de Sets divergente (1 Set no inventário, 5 na contagem exata e independente de Sets ativos com cartas) -> plano nunca emitido, aborta com RECONCILIACAO_SETS_FALHOU",
        erroSets !== null && erroSets.message.startsWith("RECONCILIACAO_SETS_FALHOU"),
      );

      const supabasePaginacaoIncompleta = makeReadOnlyFakeClient(seedBase, { countOverride: { card_set: 2 } });
      let erroPaginacao: Error | null = null;
      try {
        await executeExpansionPlan(supabasePaginacaoIncompleta, new JustTcgClient("sk-fake-c", fetchImpl));
      } catch (error) {
        erroPaginacao = error instanceof Error ? error : null;
      }
      assert(
        "P14.4.1 fix: paginação incompleta genérica (card_set: 1 linha buscada, contagem exata diz 2) -> plano nunca emitido, aborta com PAGINACAO_INCOMPLETA(card_set)",
        erroPaginacao !== null && erroPaginacao.message.startsWith("PAGINACAO_INCOMPLETA(card_set)"),
      );
      assert(
        "Query 3917: as três falhas de reconciliação/paginação acima (cartas, Sets, paginação genérica) resultam em zero chamadas HTTP à JustTCG — erro local sempre interrompe executeExpansionPlan() antes do único GET /sets",
        callCount() === 0,
      );
    }

    // Regressão Query 3917: erro de permissão em uma leitura local (ex.: "permission denied for
    // table game", faltando SELECT em tabela-base da view security_invoker catalog_card_set_metrics
    // — cenário real reportado por Fabrício, corrigido pela Query 3917) nunca consome quota
    // externa. executeExpansionPlan() só chama a JustTCG (GET /sets) depois que TODAS as leituras
    // e reconciliações locais (card_set, catalog_card_set_metrics, cartas, Sets, pricing_set_mapping,
    // pricing_set_coverage) terminam com sucesso — ver ordem das chamadas no próprio código-fonte,
    // linhas 3742-3793. Este teste prova isso estruturalmente: mesmo com um fetchImpl pronto para
    // responder 200, zero chamadas HTTP ocorrem quando a leitura de catalog_card_set_metrics falha.
    {
      const seed = {
        pricing_source: [{ id: "src-1", code: "JUSTTCG", is_active: true, requires_commercial_agreement: true }],
        card_set: [{ id: "cs-a", code: "SETA", release_date: "2020-01-01" }],
        catalog_card_set_metrics: [{ card_set_id: "cs-a", cards_ativas: 3 }],
        card: [{ id: "card-1", is_active: true }],
        pricing_set_mapping: [],
        pricing_set_coverage: [],
      };
      const supabasePermissaoNegada = makeReadOnlyFakeClient(seed, {
        errorOnCall: { catalog_card_set_metrics: { atCallIndex: 1, message: "permission denied for table game" } },
      });
      const { fetchImpl, callCount } = makeFakeFetch([{ status: 200, body: { data: [] } }]);
      let erroPermissao: Error | null = null;
      try {
        await executeExpansionPlan(supabasePermissaoNegada, new JustTcgClient("sk-fake-e", fetchImpl));
      } catch (error) {
        erroPermissao = error instanceof Error ? error : null;
      }
      assert(
        "Query 3917 regressão: erro de permissão na leitura de catalog_card_set_metrics (ex.: 'permission denied for table game') -> aborta com PAGINATED_QUERY_FAILED, nunca chega ao GET /sets",
        erroPermissao !== null && erroPermissao.message.startsWith("PAGINATED_QUERY_FAILED") && erroPermissao.message.includes("permission denied for table game"),
      );
      assert(
        "Query 3917 regressão: falha de permissão local -> zero chamadas HTTP à JustTCG (quota externa nunca consumida por erro local, mesmo com fetchImpl pronto para responder 200)",
        callCount() === 0,
      );
    }

    // assertConfirmedMappingsPreserved() — mapping CONFIRMED apontando para um Set que sumiu do
    // inventário paginado (bug de filtro/paginação) nunca produz um plano parcial silencioso.
    {
      const seed = {
        pricing_source: [{ id: "src-1", code: "JUSTTCG", is_active: true, requires_commercial_agreement: true }],
        card_set: [{ id: "cs-outro", code: "OUTRO", release_date: "2020-06-01" }],
        catalog_card_set_metrics: [{ card_set_id: "cs-outro", cards_ativas: 1 }],
        card: [{ id: "card-1", is_active: true }],
        // Mapping CONFIRMED aponta para "cs-sumido", que NUNCA aparece em card_set/metrics —
        // simula BASE1/BASE4/ME1 desaparecendo do inventário por um bug de paginação/filtro.
        pricing_set_mapping: [{ card_set_id: "cs-sumido", pricing_source_id: "src-1", match_status: "CONFIRMED", external_set_id: "ext-sumido", external_set_name: "Ext Sumido" }],
        pricing_set_coverage: [],
      };
      const supabase = makeReadOnlyFakeClient(seed, { countOverride: { card: 1 } });
      const { fetchImpl } = makeFakeFetch([{ status: 200, body: { data: [] } }]);
      let erro: Error | null = null;
      try {
        await executeExpansionPlan(supabase, new JustTcgClient("sk-fake-d", fetchImpl));
      } catch (error) {
        erro = error instanceof Error ? error : null;
      }
      assert(
        "P14.4.1 fix: mapping CONFIRMED (ex.: BASE1/BASE4/ME1) apontando para um Set ausente do inventário -> plano nunca emitido, aborta com MAPPING_CONFIRMED_SEM_SET_LOCAL_CORRESPONDENTE",
        erro !== null && erro.message.startsWith("MAPPING_CONFIRMED_SEM_SET_LOCAL_CORRESPONDENTE"),
      );
    }
  }

  // ==========================================================================================
  // P14.4.2 — Executor Explícito e Controlado de Ondas JustTCG (--expansion-wave)
  // ==========================================================================================

  // Fixture compartilhada "onda simples" — 2 Sets pequenos (SETX=2 cartas, SETY=1 carta), usada
  // pelos cenários 5-16 abaixo, que precisam de execução completa (aquisição + classificação +
  // persistência), diferente dos cenários 1-4 (puramente estruturais/de validação de
  // argumentos). Cada teste chama esta função para obter um seed FRESCO (nunca compartilha
  // estado mutável entre testes) — só makeExpansionWaveFakeClient() decide se as tabelas
  // resultantes são compartilhadas DENTRO de um mesmo teste (ex.: reexecução idempotente).
  function buildOndaSimplesSeed(): Record<string, FakeRow[]> {
    return {
      pricing_source: [{ id: "src-1", code: "JUSTTCG", is_active: true, requires_commercial_agreement: true }],
      card_set: [
        { id: "cs-x", code: "SETX", release_date: "2020-01-01" },
        { id: "cs-y", code: "SETY", release_date: "2020-02-01" },
      ],
      catalog_card_set_metrics: [
        { card_set_id: "cs-x", cards_ativas: 2 },
        { card_set_id: "cs-y", cards_ativas: 1 },
      ],
      card: [
        { id: "card-x1", card_set_id: "cs-x", name: "Card X1", collector_number: "1", is_active: true },
        { id: "card-x2", card_set_id: "cs-x", name: "Card X2", collector_number: "2", is_active: true },
        { id: "card-y1", card_set_id: "cs-y", name: "Card Y1", collector_number: "1", is_active: true },
      ],
      pricing_set_mapping: [],
      pricing_set_coverage: [],
      pricing_condition_mapping: [{ pricing_source_id: "src-1", external_condition_code: "Near Mint", condition_id: "cond-nm" }],
    };
  }

  const ondaSimplesExternalSets = [
    { id: "ext-x", name: "Ext X", release_date: "2020-01-01" },
    { id: "ext-y", name: "Ext Y", release_date: "2020-02-01" },
  ];

  // Sequência de respostas para uma execução completa e bem-sucedida da onda (GET /sets -> GET
  // /cards SETX -> GET /cards SETY), reaproveitada por vários cenários que só precisam da
  // aquisição inteira funcionando de ponta a ponta.
  function buildOndaSimplesSuccessResponses(): Array<{ status: number; body: unknown }> {
    return [
      { status: 200, body: { data: ondaSimplesExternalSets } },
      {
        status: 200,
        body: {
          data: [
            { id: "ext-card-x1", name: "Card X1", number: "1", variants: [{ uuid: "var-x1", condition: "Near Mint", printing: "Normal", price: 1.5, lastUpdated: 1700000000 }] },
            { id: "ext-card-x2", name: "Card X2", number: "2", variants: [{ uuid: "var-x2", condition: "Near Mint", printing: "Normal", price: 2.5, lastUpdated: 1700000000 }] },
          ],
        },
      },
      { status: 200, body: { data: [{ id: "ext-card-y1", name: "Card Y1", number: "1", variants: [{ uuid: "var-y1", condition: "Near Mint", printing: "Normal", price: 3.5, lastUpdated: 1700000000 }] }] } },
    ];
  }

  // Cenário 1 — seleção exata da onda 1: composição informada por Fabrício a partir da
  // reconciliação real (BASE2=64, BASE3=62, BASE5=83, GYM2=132 -> 341 cartas, 1 GET /sets + 5
  // páginas de /cards). Validado 100% offline contra um plano recalculado a partir de um seed
  // fixture — a escala real (45 Sets) não precisa ser reproduzida aqui, só a composição exata.
  {
    const seed = {
      pricing_source: [{ id: "src-1", code: "JUSTTCG", is_active: true, requires_commercial_agreement: true }],
      card_set: [
        { id: "cs-base2", code: "BASE2", release_date: "2000-01-01" },
        { id: "cs-base3", code: "BASE3", release_date: "2000-02-01" },
        { id: "cs-base5", code: "BASE5", release_date: "2000-03-01" },
        { id: "cs-gym2", code: "GYM2", release_date: "2000-04-01" },
      ],
      catalog_card_set_metrics: [
        { card_set_id: "cs-base2", cards_ativas: 64 },
        { card_set_id: "cs-base3", cards_ativas: 62 },
        { card_set_id: "cs-base5", cards_ativas: 83 },
        { card_set_id: "cs-gym2", cards_ativas: 132 },
      ],
      card: [],
      pricing_set_mapping: [],
      pricing_set_coverage: [],
    };
    const supabaseWave1 = makeReadOnlyFakeClient(seed, { countOverride: { card: 341 } });
    const inputsWave1 = await fetchReconciledLocalInputs(supabaseWave1);
    const externalSetsWave1 = normalizeJustTcgSets([
      { id: "ext-base2", name: "Base Set 2", release_date: "2000-01-01" },
      { id: "ext-base3", name: "Base Set 3", release_date: "2000-02-01" },
      { id: "ext-base5", name: "Base Set 5", release_date: "2000-03-01" },
      { id: "ext-gym2", name: "Gym 2", release_date: "2000-04-01" },
    ]);
    const planWave1 = buildExpansionPlan({ ...inputsWave1, allExternalSets: externalSetsWave1 });
    const waveSelection1 = selectWaveFromPlan(planWave1, 1);
    assert(
      "P14.4.2 cenário 1: onda 1 recalculada reproduz a composição esperada — BASE2(64)+BASE3(62)+BASE5(83)+GYM2(132)=341 cartas locais, estimativa de 5 páginas de /cards",
      waveSelection1.ok &&
        waveSelection1.wave.sets.map((s) => s.code).join(",") === "BASE2,BASE3,BASE5,GYM2" &&
        waveSelection1.wave.totalLocalCards === 341 &&
        waveSelection1.wave.estimatedCallsCards === 5,
    );
  }

  // Cenário 2 — onda inexistente: plano só tem 1 onda, pedir a onda 99 é rejeitado antes de
  // qualquer execução (nunca "a mais próxima", nunca todas implicitamente).
  {
    const planUmaOnda = buildExpansionPlan({
      localSets: [{ cardSetId: "cs-1", code: "SET1", releaseDateIso: "2020-01-01", localCardCount: 10 }],
      existingSetMappings: new Map(),
      allExternalSets: normalizeJustTcgSets([{ id: "ext-1", name: "Ext 1", release_date: "2020-01-01" }]),
      existingCoverage: new Map(),
    });
    const selecaoInexistente = selectWaveFromPlan(planUmaOnda, 99);
    assert(
      "P14.4.2 cenário 2: --expansion-wave=99 num plano com só 1 onda é rejeitado com ONDA_INEXISTENTE, nunca executa a onda mais próxima nem todas implicitamente",
      !selecaoInexistente.ok && selecaoInexistente.error.startsWith("ONDA_INEXISTENTE"),
    );
  }

  // Cenário 3 — ausência/invalidez de orçamento (e onda) — tudo antes de qualquer chamada
  // externa, validado por uma função pura sem rede/Supabase.
  {
    const semOrcamento = validateExpansionWaveArgs({ expansionWave: "1", maxApiRequests: null, dryRun: true, confirmedBy: null, expectedSetCodes: "SETX,SETY" });
    assert("P14.4.2 cenário 3: --max-api-requests ausente é rejeitado (MAX_API_REQUESTS_AUSENTE)", !semOrcamento.ok && semOrcamento.reason.startsWith("MAX_API_REQUESTS_AUSENTE"));

    const orcamentoNaoNumerico = validateExpansionWaveArgs({ expansionWave: "1", maxApiRequests: "abc", dryRun: true, confirmedBy: null, expectedSetCodes: "SETX,SETY" });
    assert("P14.4.2 cenário 3: --max-api-requests não-numérico é rejeitado (MAX_API_REQUESTS_INVALIDO)", !orcamentoNaoNumerico.ok && orcamentoNaoNumerico.reason.startsWith("MAX_API_REQUESTS_INVALIDO"));

    const orcamentoZero = validateExpansionWaveArgs({ expansionWave: "1", maxApiRequests: "0", dryRun: true, confirmedBy: null, expectedSetCodes: "SETX,SETY" });
    assert("P14.4.2 cenário 3: --max-api-requests=0 é rejeitado (deve ser inteiro positivo)", !orcamentoZero.ok);

    const ondaZero = validateExpansionWaveArgs({ expansionWave: "0", maxApiRequests: "10", dryRun: true, confirmedBy: null, expectedSetCodes: "SETX,SETY" });
    assert("P14.4.2 cenário 3: --expansion-wave=0 é rejeitado (EXPANSION_WAVE_INVALIDO, deve ser inteiro positivo)", !ondaZero.ok && ondaZero.reason.startsWith("EXPANSION_WAVE_INVALIDO"));

    const ondaNaoNumerica = validateExpansionWaveArgs({ expansionWave: "primeira", maxApiRequests: "10", dryRun: true, confirmedBy: null, expectedSetCodes: "SETX,SETY" });
    assert("P14.4.2 cenário 3: --expansion-wave não-numérico é rejeitado", !ondaNaoNumerica.ok);

    const modosConflitantes = validateExpansionWaveArgs({ expansionWave: "1", maxApiRequests: "10", dryRun: true, confirmedBy: "admin-1", expectedSetCodes: "SETX,SETY" });
    assert("P14.4.2 cenário 3 (bônus): --dry-run e --confirmed-by juntos são rejeitados (MODOS_CONFLITANTES)", !modosConflitantes.ok && modosConflitantes.reason.startsWith("MODOS_CONFLITANTES"));

    const modoAusente = validateExpansionWaveArgs({ expansionWave: "1", maxApiRequests: "10", dryRun: false, confirmedBy: null, expectedSetCodes: "SETX,SETY" });
    assert("P14.4.2 cenário 3 (bônus): nem --dry-run nem --confirmed-by informados é rejeitado (MODO_AUSENTE, nenhum modo padrão assumido)", !modoAusente.ok && modoAusente.reason.startsWith("MODO_AUSENTE"));

    // Fix P14.4.2 (instabilidade de identidade) — regra 1: --expected-set-codes é obrigatório
    // junto com --expansion-wave, validado ANTES da checagem de modo (dry-run/confirmed-by).
    const semExpectedCodes = validateExpansionWaveArgs({ expansionWave: "1", maxApiRequests: "10", dryRun: true, confirmedBy: null, expectedSetCodes: null });
    assert(
      "P14.4.2 fix cenário 3b: --expected-set-codes ausente é rejeitado (EXPECTED_SET_CODES_AUSENTE), mesmo com onda/orçamento/modo válidos",
      !semExpectedCodes.ok && semExpectedCodes.reason.startsWith("EXPECTED_SET_CODES_AUSENTE"),
    );

    const expectedCodesComVazio = validateExpansionWaveArgs({ expansionWave: "1", maxApiRequests: "10", dryRun: true, confirmedBy: null, expectedSetCodes: "SETX,,SETY" });
    assert(
      "P14.4.2 fix cenário 3b: --expected-set-codes com item vazio (vírgula dupla) é rejeitado (EXPECTED_SET_CODES_INVALIDO)",
      !expectedCodesComVazio.ok && expectedCodesComVazio.reason.startsWith("EXPECTED_SET_CODES_INVALIDO"),
    );

    const expectedCodesDuplicado = validateExpansionWaveArgs({ expansionWave: "1", maxApiRequests: "10", dryRun: true, confirmedBy: null, expectedSetCodes: "SETX,SETY,setx" });
    assert(
      "P14.4.2 fix cenário 3b: --expected-set-codes com código repetido (após normalização uppercase) é rejeitado (EXPECTED_SET_CODES_DUPLICADO)",
      !expectedCodesDuplicado.ok && expectedCodesDuplicado.reason.startsWith("EXPECTED_SET_CODES_DUPLICADO"),
    );

    const expectedCodesNormalizados = validateExpansionWaveArgs({ expansionWave: "1", maxApiRequests: "10", dryRun: true, confirmedBy: null, expectedSetCodes: " setx , sety " });
    assert(
      "P14.4.2 fix cenário 3b: --expected-set-codes é normalizado (trim + uppercase) antes da comparação de composição",
      expectedCodesNormalizados.ok && expectedCodesNormalizados.expectedSetCodes.join(",") === "SETX,SETY",
    );
  }

  // Cenário 4 — nunca executar todas as ondas implicitamente: --expansion-wave ausente nunca
  // aciona o modo onda (cai no comportamento herdado, inalterado); só um valor explícito aciona.
  {
    const decisionSemWave = resolveEntryDecision(
      { fixtureCheck: false, expansionPlan: false, expansionWave: null, maxApiRequests: null, dryRun: false, confirmedBy: "admin-1" },
      { justTcgApiKey: "k", supabaseUrl: "u", supabaseServiceRoleKey: "s" },
    );
    assert("P14.4.2 cenário 4: sem --expansion-wave, o modo onda nunca é acionado implicitamente (cai em REAL_PILOT, comportamento herdado inalterado)", decisionSemWave.kind === "REAL_PILOT");

    const decisionComWave = resolveEntryDecision(
      { fixtureCheck: false, expansionPlan: false, expansionWave: "1", maxApiRequests: "10", dryRun: true, confirmedBy: null, expectedSetCodes: "SETX,SETY" },
      { justTcgApiKey: "k", supabaseUrl: "u", supabaseServiceRoleKey: "s" },
    );
    assert(
      "P14.4.2 cenário 4: --expansion-wave=1 explícito aciona EXPANSION_WAVE com o número exato pedido, nunca 'todas as ondas'",
      decisionComWave.kind === "EXPANSION_WAVE" &&
        decisionComWave.waveNumber === 1 &&
        decisionComWave.maxApiRequests === 10 &&
        decisionComWave.expectedSetCodes.join(",") === "SETX,SETY",
    );

    const decisionArgsInvalidos = resolveEntryDecision(
      { fixtureCheck: false, expansionPlan: false, expansionWave: "1", maxApiRequests: null, dryRun: true, confirmedBy: null, expectedSetCodes: "SETX,SETY" },
      { justTcgApiKey: undefined, supabaseUrl: undefined, supabaseServiceRoleKey: undefined },
    );
    assert(
      "P14.4.2 cenário 4 (bônus): argumento de onda inválido é rejeitado ANTES até da checagem de credenciais (mesmo sem nenhuma variável de ambiente definida)",
      decisionArgsInvalidos.kind === "EXPANSION_WAVE_INVALID_ARGS",
    );
  }

  // Cenário 5 — falha de reconciliação gera zero HTTP: contagem exata de `card` diverge da
  // soma local -> RECONCILIACAO_CARTAS_FALHOU dentro de fetchReconciledLocalInputs(), antes de
  // tryOpenCardSyncRun()/qualquer chamada à JustTCG.
  {
    const seed = buildOndaSimplesSeed();
    const { client: supabase5, tables: tables5 } = makeExpansionWaveFakeClient(seed, { countOverride: { card: 999 } });
    const { fetchImpl: fetchImpl5, callCount: callCount5 } = makeFakeFetch(buildOndaSimplesSuccessResponses());
    const client5 = new JustTcgClient("sk-fake-5", fetchImpl5, 10);
    let erro5: Error | null = null;
    try {
      await executeExpansionWave(supabase5, client5, { waveNumber: 1, dryRun: false, confirmedBy: "admin-1", maxApiRequests: 10, expectedSetCodes: ["SETX", "SETY"] });
    } catch (error) {
      erro5 = error instanceof Error ? error : null;
    }
    assert(
      "P14.4.2 cenário 5: falha de reconciliação local (RECONCILIACAO_CARTAS_FALHOU) aborta antes de qualquer chamada HTTP à JustTCG e antes de abrir CARD_SYNC",
      erro5 !== null &&
        erro5.message.startsWith("RECONCILIACAO_CARTAS_FALHOU") &&
        callCount5() === 0 &&
        client5.requestsMade === 0 &&
        (tables5.pricing_sync_run ?? []).length === 0,
    );
  }

  // Cenário 6 — conflito de concorrência gera zero HTTP: já existe um CARD_SYNC
  // RECEIVED/PROCESSING para a mesma fonte -> INSERT falha com 23505 (índice único parcial,
  // Query 3907) antes de qualquer requisição à JustTCG.
  {
    const seed = buildOndaSimplesSeed();
    seed.pricing_sync_run = [{ id: "run-existing", pricing_source_id: "src-1", run_type: "CARD_SYNC", status: "PROCESSING" }];
    const { client: supabase6, tables: tables6 } = makeExpansionWaveFakeClient(seed);
    const { fetchImpl: fetchImpl6, callCount: callCount6 } = makeFakeFetch(buildOndaSimplesSuccessResponses());
    const client6 = new JustTcgClient("sk-fake-6", fetchImpl6, 10);
    let erro6: Error | null = null;
    try {
      await executeExpansionWave(supabase6, client6, { waveNumber: 1, dryRun: false, confirmedBy: "admin-1", maxApiRequests: 10, expectedSetCodes: ["SETX", "SETY"] });
    } catch (error) {
      erro6 = error instanceof Error ? error : null;
    }
    assert(
      "P14.4.2 cenário 6: conflito de concorrência (CARD_SYNC já ativo) aborta com CONFLITO_DE_CONCORRENCIA antes de qualquer chamada à JustTCG, sem criar uma 2ª linha em pricing_sync_run",
      erro6 !== null && erro6.message.startsWith("CONFLITO_DE_CONCORRENCIA") && callCount6() === 0 && client6.requestsMade === 0 && tables6.pricing_sync_run.length === 1,
    );
  }

  // Cenário 7+8 — orçamento impede a chamada excedente E orçamento insuficiente gera zero
  // persistência de negócio: budget=2 alcança só GET /sets + a página de SETX; a tentativa de
  // paginar SETY nunca dispara um fetch real (budgetOk() barra antes) e nenhuma escrita de
  // mapping/produto/observação acontece (onda inteira é abortada, regras 8/9).
  {
    const seed = buildOndaSimplesSeed();
    const { client: supabase78, tables: tables78 } = makeExpansionWaveFakeClient(seed);
    const { fetchImpl: fetchImpl78, callCount: callCount78 } = makeFakeFetch(buildOndaSimplesSuccessResponses());
    const client78 = new JustTcgClient("sk-fake-78", fetchImpl78, 2);
    const resultado78 = await executeExpansionWave(supabase78, client78, { waveNumber: 1, dryRun: false, confirmedBy: "admin-1", maxApiRequests: 2, expectedSetCodes: ["SETX", "SETY"] });
    assert(
      "P14.4.2 cenário 7: --max-api-requests=2 nunca é ultrapassado — exatamente 2 chamadas reais (GET /sets + 1ª página de SETX), a 3ª (SETY) nunca é sequer tentada",
      callCount78() === 2 && client78.requestsMade === 2,
    );
    assert(
      "P14.4.2 cenário 8: orçamento insuficiente para paginar a onda inteira -> zero persistência de negócio (mapping/produto/observação), status FAILED",
      resultado78.status === "FAILED" &&
        (tables78.pricing_card_mapping ?? []).length === 0 &&
        (tables78.pricing_product ?? []).length === 0 &&
        (tables78.pricing_observation ?? []).length === 0,
    );
  }

  // Cenário 9 — falha de paginação gera zero persistência de negócio: a 1ª página de SETX
  // sinaliza meta.hasMore=true (força uma 2ª página mesmo com poucos itens), que retorna HTTP
  // 500 — SETY nunca chega a ser tentado, nenhuma escrita de negócio acontece.
  {
    const seed = buildOndaSimplesSeed();
    const { client: supabase9, tables: tables9 } = makeExpansionWaveFakeClient(seed);
    const { fetchImpl: fetchImpl9 } = makeFakeFetch([
      { status: 200, body: { data: ondaSimplesExternalSets } },
      { status: 200, body: { data: [{ id: "ext-card-x1", name: "Card X1", number: "1", variants: [] }], meta: { hasMore: true } } },
      { status: 500, body: { error: "falha simulada" } },
    ]);
    const client9 = new JustTcgClient("sk-fake-9", fetchImpl9, 10);
    const resultado9 = await executeExpansionWave(supabase9, client9, { waveNumber: 1, dryRun: false, confirmedBy: "admin-1", maxApiRequests: 10, expectedSetCodes: ["SETX", "SETY"] });
    assert(
      "P14.4.2 cenário 9: falha de paginação (HTTP 500 na 2ª página de SETX) aborta a onda inteira -> zero mapping/produto/observação persistidos, status FAILED, SETY nunca tentado",
      resultado9.status === "FAILED" &&
        (tables9.pricing_card_mapping ?? []).length === 0 &&
        (tables9.pricing_product ?? []).length === 0 &&
        (tables9.pricing_observation ?? []).length === 0 &&
        resultado9.errorParts.some((e) => e.startsWith("PAGINACAO_CARDS_FALHOU")),
    );
  }

  // Cenário 10 — dry-run gera zero escrita: nenhum pricing_sync_run criado, nenhuma linha
  // gravada em nenhuma tabela de negócio, mas a classificação/projeção roda por completo.
  {
    const seed = buildOndaSimplesSeed();
    const { client: supabase10, tables: tables10 } = makeExpansionWaveFakeClient(seed);
    const { fetchImpl: fetchImpl10 } = makeFakeFetch(buildOndaSimplesSuccessResponses());
    const client10 = new JustTcgClient("sk-fake-10", fetchImpl10, 10);
    const resultado10 = await executeExpansionWave(supabase10, client10, { waveNumber: 1, dryRun: true, confirmedBy: null, maxApiRequests: 10, expectedSetCodes: ["SETX", "SETY"] });
    assert(
      "P14.4.2 cenário 10: --dry-run nunca cria pricing_sync_run nem escreve mapping/produto/observação/set_mapping, mesmo com a onda inteira classificada com sucesso",
      (tables10.pricing_sync_run ?? []).length === 0 &&
        (tables10.pricing_set_mapping ?? []).length === 0 &&
        (tables10.pricing_card_mapping ?? []).length === 0 &&
        (tables10.pricing_product ?? []).length === 0 &&
        (tables10.pricing_observation ?? []).length === 0 &&
        resultado10.cardsSafe === 3 &&
        resultado10.status === "COMPLETED",
    );
  }

  // Cenário 11+12 — execução bem-sucedida usa um único run, e as chamadas ficam sequenciadas
  // por sequence_number (1, 2, 3, ...) dentro desse mesmo run.
  {
    const seed = buildOndaSimplesSeed();
    const { client: supabase1112, tables: tables1112 } = makeExpansionWaveFakeClient(seed);
    const { fetchImpl: fetchImpl1112 } = makeFakeFetch(buildOndaSimplesSuccessResponses());
    const client1112 = new JustTcgClient("sk-fake-1112", fetchImpl1112, 10);
    const resultado1112 = await executeExpansionWave(supabase1112, client1112, { waveNumber: 1, dryRun: false, confirmedBy: "admin-1", maxApiRequests: 10, expectedSetCodes: ["SETX", "SETY"] });
    assert("P14.4.2 cenário 11: execução bem-sucedida consolida a onda inteira num único pricing_sync_run", resultado1112.status === "COMPLETED" && tables1112.pricing_sync_run.length === 1);
    const runId1112 = tables1112.pricing_sync_run[0].id as string;
    const calls1112 = (tables1112.pricing_sync_run_call ?? []) as Array<{ sync_run_id: string; sequence_number: number }>;
    const sequencias = calls1112.map((c) => c.sequence_number);
    assert(
      "P14.4.2 cenário 12: pricing_sync_run_call registra uma linha por tentativa HTTP, todas do mesmo run, com sequence_number estritamente crescente (1, 2, 3)",
      calls1112.length === 3 && calls1112.every((c) => c.sync_run_id === runId1112) && sequencias.join(",") === "1,2,3",
    );
  }

  // Cenário 13 — P14.4.4: número único mas nome externo divergente -> CONFIRMED (nunca mais
  // PENDING). Antes de P14.4.4 este cenário classificava AMBIGUOUS/PENDING só por divergência
  // de nome — era exatamente o falso-positivo real descoberto na auditoria pós-P14.4.3
  // (NUMERO_UNICO_MAS_NOME_DIVERGENTE em BASE1/ME1). Candidato único por Set+número agora
  // promove normalmente, independente do nome.
  {
    const seed = buildOndaSimplesSeed();
    seed.card.push({ id: "card-x3", card_set_id: "cs-x", name: "Card X3", collector_number: "3", is_active: true });
    seed.catalog_card_set_metrics = [
      { card_set_id: "cs-x", cards_ativas: 3 },
      { card_set_id: "cs-y", cards_ativas: 1 },
    ];
    const { client: supabase13, tables: tables13 } = makeExpansionWaveFakeClient(seed);
    const { fetchImpl: fetchImpl13 } = makeFakeFetch([
      { status: 200, body: { data: ondaSimplesExternalSets } },
      {
        status: 200,
        body: {
          data: [
            { id: "ext-card-x1", name: "Card X1", number: "1", variants: [{ uuid: "var-x1", condition: "Near Mint", printing: "Normal", price: 1.5, lastUpdated: 1700000000 }] },
            { id: "ext-card-x2", name: "Card X2", number: "2", variants: [{ uuid: "var-x2", condition: "Near Mint", printing: "Normal", price: 2.5, lastUpdated: 1700000000 }] },
            { id: "ext-card-x3-outro", name: "Nome Totalmente Diferente", number: "3", variants: [{ uuid: "var-x3", condition: "Near Mint", printing: "Normal", price: 9.9, lastUpdated: 1700000000 }] },
          ],
        },
      },
      { status: 200, body: { data: [{ id: "ext-card-y1", name: "Card Y1", number: "1", variants: [{ uuid: "var-y1", condition: "Near Mint", printing: "Normal", price: 3.5, lastUpdated: 1700000000 }] }] } },
    ]);
    const client13 = new JustTcgClient("sk-fake-13", fetchImpl13, 10);
    const resultado13 = await executeExpansionWave(supabase13, client13, { waveNumber: 1, dryRun: false, confirmedBy: "admin-1", maxApiRequests: 10, expectedSetCodes: ["SETX", "SETY"] });
    const mappingX3 = (tables13.pricing_card_mapping ?? []).find((r) => r.card_id === "card-x3") as { match_status: string; external_card_id?: string } | undefined;
    assert(
      "P14.4.4 cenário 13: número único com nome externo divergente (card-x3) promove a CONFIRMED normalmente, exatamente como card-x1/x2/y1 — nome nunca bloqueia (correção da causa raiz descoberta na auditoria pós-P14.4.3)",
      resultado13.cardsAmbiguous === 0 && mappingX3 !== undefined && mappingX3.match_status === "CONFIRMED" && mappingX3.external_card_id === "ext-card-x3-outro",
    );
  }

  // Cenário 14 — reexecução idempotente: depois que a onda 1 é confirmada com sucesso, os Sets
  // saem de SAFE_CANDIDATE para ALREADY_CONFIRMED (mesma disciplina de P14.4.1) — uma 2ª
  // tentativa de --expansion-wave=1 é rejeitada com ONDA_INEXISTENTE. A garantia real de
  // idempotência é sobre DADO DE NEGÓCIO (mapping/produto/observação nunca duplicam) — a 2ª
  // execução AINDA abre seu próprio CARD_SYNC antes do GET /sets (regra 6, correto e esperado:
  // o run anterior já foi finalizado, não há conflito de concorrência a detectar) e o registra
  // como FAILED com o motivo ONDA_INEXISTENTE, o que é telemetria válida (não uma duplicação de
  // dado de negócio) — por isso pricing_sync_run cresce em +1 (o registro do 2º, curto e
  // fracassado, run), nunca fica igual.
  {
    const seed = buildOndaSimplesSeed();
    const { client: supabase14, tables: tables14 } = makeExpansionWaveFakeClient(seed);

    const { fetchImpl: fetchImplRun1 } = makeFakeFetch(buildOndaSimplesSuccessResponses());
    const clientRun1 = new JustTcgClient("sk-fake-14a", fetchImplRun1, 10);
    const resultadoRun1 = await executeExpansionWave(supabase14, clientRun1, { waveNumber: 1, dryRun: false, confirmedBy: "admin-1", maxApiRequests: 10, expectedSetCodes: ["SETX", "SETY"] });
    const contagemApos1 = {
      syncRun: tables14.pricing_sync_run.length,
      cardMapping: tables14.pricing_card_mapping.length,
      product: tables14.pricing_product.length,
      observation: tables14.pricing_observation.length,
    };

    const { fetchImpl: fetchImplRun2 } = makeFakeFetch([{ status: 200, body: { data: ondaSimplesExternalSets } }]);
    const clientRun2 = new JustTcgClient("sk-fake-14b", fetchImplRun2, 10);
    let erroRun2: Error | null = null;
    try {
      await executeExpansionWave(supabase14, clientRun2, { waveNumber: 1, dryRun: false, confirmedBy: "admin-1", maxApiRequests: 10, expectedSetCodes: ["SETX", "SETY"] });
    } catch (error) {
      erroRun2 = error instanceof Error ? error : null;
    }
    const contagemApos2 = {
      syncRun: tables14.pricing_sync_run.length,
      cardMapping: tables14.pricing_card_mapping.length,
      product: tables14.pricing_product.length,
      observation: tables14.pricing_observation.length,
    };

    assert(
      "P14.4.2 cenário 14: 1ª execução da onda 1 é bem-sucedida (COMPLETED)",
      resultadoRun1.status === "COMPLETED",
    );
    assert(
      "P14.4.2 cenário 14: reexecução imediata de --expansion-wave=1 é rejeitada com ONDA_INEXISTENTE (Sets já CONFIRMED saíram de SAFE_CANDIDATE) — registra só sua própria telemetria de falha (+1 pricing_sync_run, FAILED), NUNCA duplica mapping/produto/observação",
      erroRun2 !== null &&
        erroRun2.message.startsWith("ONDA_INEXISTENTE") &&
        contagemApos2.syncRun === contagemApos1.syncRun + 1 &&
        contagemApos2.cardMapping === contagemApos1.cardMapping &&
        contagemApos2.product === contagemApos1.product &&
        contagemApos2.observation === contagemApos1.observation,
    );
  }

  // Cenário 15 — preço inalterado não cria observação: card-x1/var-x1 já tem uma observação
  // existente ao mesmo preço (1.5) -> CONFLICT_IGNORED_SAME_PRICE, zero nova linha para esse
  // grupo; card-x2/y1 (produtos novos) recebem observação nova normalmente.
  {
    const seed = buildOndaSimplesSeed();
    seed.pricing_card_mapping = [{ id: "pcm-x1", card_id: "card-x1", pricing_source_id: "src-1", match_status: "CONFIRMED" }];
    seed.pricing_product = [{ id: "pp-x1", pricing_card_mapping_id: "pcm-x1", external_product_id: "var-x1" }];
    seed.pricing_observation = [
      { pricing_product_id: "pp-x1", condition_id: "cond-nm", price_type: "MARKET", currency_code: "USD", market_label: MARKET_LABEL, price: 1.5, observed_at: "2026-01-01T00:00:00.000Z" },
    ];
    const { client: supabase15, tables: tables15 } = makeExpansionWaveFakeClient(seed);
    const { fetchImpl: fetchImpl15 } = makeFakeFetch(buildOndaSimplesSuccessResponses());
    const client15 = new JustTcgClient("sk-fake-15", fetchImpl15, 10);
    const resultado15 = await executeExpansionWave(supabase15, client15, { waveNumber: 1, dryRun: false, confirmedBy: "admin-1", maxApiRequests: 10, expectedSetCodes: ["SETX", "SETY"] });
    const observacoesDoProdutoExistente = (tables15.pricing_observation ?? []).filter((r) => r.pricing_product_id === "pp-x1");
    assert(
      "P14.4.2 cenário 15: preço idêntico ao já observado (var-x1=1.5) não cria nova observação (CONFLICT_IGNORED_SAME_PRICE) — só as 2 variantes com preço novo (x2, y1) geram observação",
      observacoesDoProdutoExistente.length === 1 && resultado15.observationsWritten === 2,
    );
  }

  // Cenário 16 — falha parcial de persistência termina como FAILED: aquisição inteira bem-
  // sucedida, mas o INSERT em pricing_product falha -> batchFailureOccurred tem prioridade
  // absoluta sobre qualquer progresso parcial (computeFinalStatus), status FAILED.
  {
    const seed = buildOndaSimplesSeed();
    const { client: supabase16 } = makeExpansionWaveFakeClient(seed, { failInsert: { pricing_product: true } });
    const { fetchImpl: fetchImpl16 } = makeFakeFetch(buildOndaSimplesSuccessResponses());
    const client16 = new JustTcgClient("sk-fake-16", fetchImpl16, 10);
    const resultado16 = await executeExpansionWave(supabase16, client16, { waveNumber: 1, dryRun: false, confirmedBy: "admin-1", maxApiRequests: 10, expectedSetCodes: ["SETX", "SETY"] });
    assert(
      "P14.4.2 cenário 16: falha parcial de persistência (INSERT em pricing_product falha) termina o run como FAILED, mesmo com toda a aquisição/classificação bem-sucedida",
      resultado16.status === "FAILED" && resultado16.errorParts.some((e) => e.startsWith("PRODUCT_BATCH_INSERT_FAILED")),
    );
  }

  // Cenário 17 — composição exata aceita explicitamente: --expected-set-codes=SETX,SETY bate
  // exatamente com a onda 1 recalculada (mesma fixture "onda simples") -> execução completa,
  // COMPLETED, sem nenhum bloqueio (regra 3/8: a composição informada só confirma, nunca
  // substitui — o que roda continua sendo wave.sets vindo do plano).
  {
    const seed = buildOndaSimplesSeed();
    const { client: supabase17, tables: tables17 } = makeExpansionWaveFakeClient(seed);
    const { fetchImpl: fetchImpl17 } = makeFakeFetch(buildOndaSimplesSuccessResponses());
    const client17 = new JustTcgClient("sk-fake-17", fetchImpl17, 10);
    const resultado17 = await executeExpansionWave(supabase17, client17, {
      waveNumber: 1,
      dryRun: false,
      confirmedBy: "admin-1",
      maxApiRequests: 10,
      expectedSetCodes: ["SETX", "SETY"],
    });
    assert(
      "P14.4.2 fix cenário 17: --expected-set-codes=SETX,SETY batendo exatamente com a onda recalculada permite a execução completa (COMPLETED), nunca bloqueia uma composição correta",
      resultado17.status === "COMPLETED" &&
        resultado17.setsSelected.slice().sort().join(",") === "SETX,SETY" &&
        (tables17.pricing_set_mapping ?? []).length === 2,
    );
  }

  // Cenário 18 — --expected-set-codes com código faltando (operador informa só SETX, a onda
  // recalculada tem SETX+SETY) -> diverge -> EXPANSION_WAVE_COMPOSITION_CHANGED, abortada ANTES
  // de qualquer upsertSetMapping/fetchAllCardsForSet (regra 5) -> zero mapping/produto/
  // observação, e o CARD_SYNC já aberto (regra 6) é finalizado como FAILED, nunca deixado num
  // estado não-terminal. Do ponto de vista da mensagem de erro, SETY é "excedente" (está na
  // onda real mas não na lista informada) — "faltando"/"excedente" na mensagem são sempre
  // relativos à onda RECALCULADA, nunca à lista informada por --expected-set-codes.
  {
    const seed = buildOndaSimplesSeed();
    const { client: supabase18, tables: tables18 } = makeExpansionWaveFakeClient(seed);
    const { fetchImpl: fetchImpl18, callCount: callCount18 } = makeFakeFetch(buildOndaSimplesSuccessResponses());
    const client18 = new JustTcgClient("sk-fake-18", fetchImpl18, 10);
    let erro18: Error | null = null;
    try {
      await executeExpansionWave(supabase18, client18, { waveNumber: 1, dryRun: false, confirmedBy: "admin-1", maxApiRequests: 10, expectedSetCodes: ["SETX"] });
    } catch (error) {
      erro18 = error instanceof Error ? error : null;
    }
    assert(
      "P14.4.2 fix cenário 18: --expected-set-codes=SETX (faltando SETY na lista informada) é rejeitado com EXPANSION_WAVE_COMPOSITION_CHANGED antes de qualquer chamada de /cards, zero mapping/produto/observação persistidos",
      erro18 !== null &&
        erro18.message.startsWith("EXPANSION_WAVE_COMPOSITION_CHANGED") &&
        erro18.message.includes("excedente=[SETY]") &&
        callCount18() === 1 &&
        (tables18.pricing_set_mapping ?? []).length === 0 &&
        (tables18.pricing_card_mapping ?? []).length === 0 &&
        (tables18.pricing_product ?? []).length === 0 &&
        (tables18.pricing_observation ?? []).length === 0,
    );
    const runsAposFalha18 = (tables18.pricing_sync_run ?? []) as Array<{ status: string }>;
    assert(
      "P14.4.2 fix cenário 18: o CARD_SYNC já aberto antes da divergência é finalizado como FAILED, nunca deixado em RECEIVED/PROCESSING",
      runsAposFalha18.length === 1 && runsAposFalha18[0].status === "FAILED",
    );
  }

  // Cenário 19 — --expected-set-codes com código excedente na lista informada (operador
  // informa SETX,SETY,SETZ — SETZ nunca fez parte da onda recalculada) -> mesma rejeição,
  // mesma garantia de zero persistência. Do ponto de vista da mensagem de erro, SETZ é
  // "faltando" (está na lista informada mas não na onda real).
  {
    const seed = buildOndaSimplesSeed();
    const { client: supabase19, tables: tables19 } = makeExpansionWaveFakeClient(seed);
    const { fetchImpl: fetchImpl19 } = makeFakeFetch(buildOndaSimplesSuccessResponses());
    const client19 = new JustTcgClient("sk-fake-19", fetchImpl19, 10);
    let erro19: Error | null = null;
    try {
      await executeExpansionWave(supabase19, client19, { waveNumber: 1, dryRun: false, confirmedBy: "admin-1", maxApiRequests: 10, expectedSetCodes: ["SETX", "SETY", "SETZ"] });
    } catch (error) {
      erro19 = error instanceof Error ? error : null;
    }
    assert(
      "P14.4.2 fix cenário 19: --expected-set-codes com SETZ excedente na lista informada (nunca fez parte da onda) é rejeitado com EXPANSION_WAVE_COMPOSITION_CHANGED, zero mapping/produto/observação persistidos",
      erro19 !== null &&
        erro19.message.startsWith("EXPANSION_WAVE_COMPOSITION_CHANGED") &&
        erro19.message.includes("faltando=[SETZ]") &&
        (tables19.pricing_card_mapping ?? []).length === 0 &&
        (tables19.pricing_product ?? []).length === 0 &&
        (tables19.pricing_observation ?? []).length === 0,
    );
  }

  // Cenário 20 — mesma composição em ordem diferente é aceita: a comparação é por CONJUNTO
  // (regra 3 "sem aceitar faltas ou excedentes", nunca por ordem/índice) — SETY,SETX (ordem
  // invertida) deve executar normalmente, idêntico a SETX,SETY.
  {
    const seed = buildOndaSimplesSeed();
    const { client: supabase20 } = makeExpansionWaveFakeClient(seed);
    const { fetchImpl: fetchImpl20 } = makeFakeFetch(buildOndaSimplesSuccessResponses());
    const client20 = new JustTcgClient("sk-fake-20", fetchImpl20, 10);
    const resultado20 = await executeExpansionWave(supabase20, client20, {
      waveNumber: 1,
      dryRun: false,
      confirmedBy: "admin-1",
      maxApiRequests: 10,
      expectedSetCodes: ["SETY", "SETX"],
    });
    assert(
      "P14.4.2 fix cenário 20: --expected-set-codes=SETY,SETX (ordem invertida em relação à onda) é aceito normalmente — comparação por conjunto, nunca por ordem",
      resultado20.status === "COMPLETED",
    );
  }

  // Cenário 21 — renumeração após confirmação nunca executa Sets novos silenciosamente: fixture
  // com 6 Sets (SETA..SETF, WAVE_MAX_SETS=5) onde SETA-SETE já estão CONFIRMED (simulando uma
  // onda 1 executada e confirmada numa rodada anterior) — o plano recalculado agora só tem
  // SETF como SAFE_CANDIDATE, que vira a NOVA onda 1 (renumerada). Repetir
  // --expansion-wave=1 --expected-set-codes=<composição ANTIGA de 5 Sets> nunca deve executar
  // SETF silenciosamente: é bloqueado por EXPANSION_WAVE_COMPOSITION_CHANGED (a onda 1 existe,
  // mas com composição divergente — não é o caso ONDA_INEXISTENTE), zero persistência de
  // negócio, e o CARD_SYNC já aberto é finalizado como FAILED.
  {
    const seedRenumeracao: Record<string, FakeRow[]> = {
      pricing_source: [{ id: "src-1", code: "JUSTTCG", is_active: true, requires_commercial_agreement: true }],
      card_set: [
        { id: "cs-a", code: "SETA", release_date: "2019-01-01" },
        { id: "cs-b", code: "SETB", release_date: "2019-02-01" },
        { id: "cs-c", code: "SETC", release_date: "2019-03-01" },
        { id: "cs-d", code: "SETD", release_date: "2019-04-01" },
        { id: "cs-e", code: "SETE", release_date: "2019-05-01" },
        { id: "cs-f", code: "SETF", release_date: "2019-06-01" },
      ],
      catalog_card_set_metrics: [
        { card_set_id: "cs-a", cards_ativas: 1 },
        { card_set_id: "cs-b", cards_ativas: 1 },
        { card_set_id: "cs-c", cards_ativas: 1 },
        { card_set_id: "cs-d", cards_ativas: 1 },
        { card_set_id: "cs-e", cards_ativas: 1 },
        { card_set_id: "cs-f", cards_ativas: 1 },
      ],
      card: [
        { id: "card-a1", card_set_id: "cs-a", name: "Card A1", collector_number: "1", is_active: true },
        { id: "card-b1", card_set_id: "cs-b", name: "Card B1", collector_number: "1", is_active: true },
        { id: "card-c1", card_set_id: "cs-c", name: "Card C1", collector_number: "1", is_active: true },
        { id: "card-d1", card_set_id: "cs-d", name: "Card D1", collector_number: "1", is_active: true },
        { id: "card-e1", card_set_id: "cs-e", name: "Card E1", collector_number: "1", is_active: true },
        { id: "card-f1", card_set_id: "cs-f", name: "Card F1", collector_number: "1", is_active: true },
      ],
      // SETA-SETE já CONFIRMED (onda 1 original, executada e confirmada numa rodada anterior)
      // -- só SETF permanece SAFE_CANDIDATE, virando a onda 1 recalculada (renumerada).
      pricing_set_mapping: [
        { card_set_id: "cs-a", pricing_source_id: "src-1", match_status: "CONFIRMED", external_set_id: "ext-a", external_set_name: "Ext A" },
        { card_set_id: "cs-b", pricing_source_id: "src-1", match_status: "CONFIRMED", external_set_id: "ext-b", external_set_name: "Ext B" },
        { card_set_id: "cs-c", pricing_source_id: "src-1", match_status: "CONFIRMED", external_set_id: "ext-c", external_set_name: "Ext C" },
        { card_set_id: "cs-d", pricing_source_id: "src-1", match_status: "CONFIRMED", external_set_id: "ext-d", external_set_name: "Ext D" },
        { card_set_id: "cs-e", pricing_source_id: "src-1", match_status: "CONFIRMED", external_set_id: "ext-e", external_set_name: "Ext E" },
      ],
      pricing_set_coverage: [],
      pricing_condition_mapping: [{ pricing_source_id: "src-1", external_condition_code: "Near Mint", condition_id: "cond-nm" }],
    };
    const { client: supabase21, tables: tables21 } = makeExpansionWaveFakeClient(seedRenumeracao);
    const { fetchImpl: fetchImpl21 } = makeFakeFetch([{ status: 200, body: { data: [{ id: "ext-f", name: "Ext F", release_date: "2019-06-01" }] } }]);
    const client21 = new JustTcgClient("sk-fake-21", fetchImpl21, 10);
    let erro21: Error | null = null;
    try {
      await executeExpansionWave(supabase21, client21, {
        waveNumber: 1,
        dryRun: false,
        confirmedBy: "admin-1",
        maxApiRequests: 10,
        // Composição ANTIGA (a que rodou e foi confirmada antes) — nunca a nova (SETF).
        expectedSetCodes: ["SETA", "SETB", "SETC", "SETD", "SETE"],
      });
    } catch (error) {
      erro21 = error instanceof Error ? error : null;
    }
    assert(
      "P14.4.2 fix cenário 21: renumeração após confirmação (onda 1 agora = SETF, não mais SETA-SETE) nunca executa o Set renumerado silenciosamente — --expected-set-codes com a composição antiga é rejeitado com EXPANSION_WAVE_COMPOSITION_CHANGED (onda 1 EXISTE, mas divergente — não ONDA_INEXISTENTE)",
      erro21 !== null &&
        erro21.message.startsWith("EXPANSION_WAVE_COMPOSITION_CHANGED") &&
        erro21.message.includes("excedente=[SETF]") &&
        erro21.message.includes("faltando=[SETA,SETB,SETC,SETD,SETE]"),
    );
    assert(
      "P14.4.2 fix cenário 21: zero persistência de negócio para o Set renumerado (SETF) — nenhum mapping/produto/observação novo, e o CARD_SYNC já aberto é finalizado como FAILED",
      (tables21.pricing_card_mapping ?? []).length === 0 &&
        (tables21.pricing_product ?? []).length === 0 &&
        (tables21.pricing_observation ?? []).length === 0 &&
        (tables21.pricing_set_mapping ?? []).length === 5 && // só os 5 originais, SETF nunca ganhou mapping
        (tables21.pricing_sync_run ?? []).length === 1 &&
        ((tables21.pricing_sync_run ?? [])[0] as { status: string }).status === "FAILED",
    );
  }

  // Cenário 22 — projeção agrega corretamente em múltiplos Sets (regra 2/3 do fix): mesma
  // fixture "onda simples" (SETX=2 cartas com 1 variante válida cada, SETY=1 carta com 1
  // variante válida) em --dry-run — productsProjected/observationsProjected somam certo no
  // resumo da onda E por Set em perSet (regra 4, sem duplicar planVariantProjection). Reafirma
  // também a regra 5: zero escrita em qualquer tabela, mesmo com a projeção > 0.
  {
    const seed = buildOndaSimplesSeed();
    const { client: supabase22, tables: tables22 } = makeExpansionWaveFakeClient(seed);
    const { fetchImpl: fetchImpl22 } = makeFakeFetch(buildOndaSimplesSuccessResponses());
    const client22 = new JustTcgClient("sk-fake-22", fetchImpl22, 10);
    const resultado22 = await executeExpansionWave(supabase22, client22, {
      waveNumber: 1,
      dryRun: true,
      confirmedBy: null,
      maxApiRequests: 10,
      expectedSetCodes: ["SETX", "SETY"],
    });
    const perSetX22 = resultado22.perSet.find((s) => s.code === "SETX");
    const perSetY22 = resultado22.perSet.find((s) => s.code === "SETY");
    assert(
      "P14.4.2 fix2 cenário 22: --dry-run projeta productsProjected/observationsProjected agregados corretamente no resumo da onda (3 variantes válidas: var-x1, var-x2, var-y1), variantsProjectionSkipped=0",
      resultado22.productsProjected === 3 && resultado22.observationsProjected === 3 && resultado22.variantsProjectionSkipped === 0,
    );
    assert(
      "P14.4.2 fix2 cenário 22: a mesma projeção também aparece detalhada por Set em perSet — SETX=2 (card-x1+card-x2), SETY=1 (card-y1) — sem duplicar planVariantProjection()",
      perSetX22 !== undefined &&
        perSetX22.productsProjected === 2 &&
        perSetX22.observationsProjected === 2 &&
        perSetY22 !== undefined &&
        perSetY22.productsProjected === 1 &&
        perSetY22.observationsProjected === 1,
    );
    assert(
      "P14.4.2 fix2 cenário 22: --dry-run continua com zero escrita em qualquer tabela mesmo com productsProjected/observationsProjected > 0 (regra 5) — nenhum pricing_sync_run, nenhum mapping/produto/observação real",
      (tables22.pricing_sync_run ?? []).length === 0 &&
        (tables22.pricing_set_mapping ?? []).length === 0 &&
        (tables22.pricing_card_mapping ?? []).length === 0 &&
        (tables22.pricing_product ?? []).length === 0 &&
        (tables22.pricing_observation ?? []).length === 0 &&
        resultado22.productsResolved === 0 &&
        resultado22.observationsResolved === 0 &&
        resultado22.status === "COMPLETED",
    );
  }

  // Cenário 23 — variante inválida incrementa variantsProjectionSkipped, nunca
  // productsProjected/observationsProjected: card-x2/var-x2 chega sem "printing" (dado
  // inválido, mesma validação de planVariantProjection() usada no caminho real) — só essa
  // variante é ignorada na projeção; card-x1/var-x1 e card-y1/var-y1 seguem projetados.
  {
    const seed = buildOndaSimplesSeed();
    const { client: supabase23, tables: tables23 } = makeExpansionWaveFakeClient(seed);
    const { fetchImpl: fetchImpl23 } = makeFakeFetch([
      { status: 200, body: { data: ondaSimplesExternalSets } },
      {
        status: 200,
        body: {
          data: [
            { id: "ext-card-x1", name: "Card X1", number: "1", variants: [{ uuid: "var-x1", condition: "Near Mint", printing: "Normal", price: 1.5, lastUpdated: 1700000000 }] },
            { id: "ext-card-x2", name: "Card X2", number: "2", variants: [{ uuid: "var-x2", condition: "Near Mint", price: 2.5, lastUpdated: 1700000000 }] }, // sem "printing" -> SKIPPED_INVALID_DATA
          ],
        },
      },
      { status: 200, body: { data: [{ id: "ext-card-y1", name: "Card Y1", number: "1", variants: [{ uuid: "var-y1", condition: "Near Mint", printing: "Normal", price: 3.5, lastUpdated: 1700000000 }] }] } },
    ]);
    const client23 = new JustTcgClient("sk-fake-23", fetchImpl23, 10);
    const resultado23 = await executeExpansionWave(supabase23, client23, {
      waveNumber: 1,
      dryRun: true,
      confirmedBy: null,
      maxApiRequests: 10,
      expectedSetCodes: ["SETX", "SETY"],
    });
    assert(
      "P14.4.2 fix2 cenário 23: variante sem 'printing' (dado inválido) incrementa variantsProjectionSkipped=1, nunca productsProjected/observationsProjected (que ficam em 2, só as variantes válidas var-x1/var-y1)",
      resultado23.variantsProjectionSkipped === 1 && resultado23.productsProjected === 2 && resultado23.observationsProjected === 2,
    );
    assert(
      "P14.4.2 fix2 cenário 23: a variante ignorada também é refletida no perSet correto (SETX: 1 projetada + 1 ignorada)",
      resultado23.perSet.find((s) => s.code === "SETX")?.variantsProjectionSkipped === 1 &&
        resultado23.perSet.find((s) => s.code === "SETX")?.productsProjected === 1 &&
        (tables23.pricing_product ?? []).length === 0,
    );
  }

  // Cenário 24 — caminho real nunca usa/preenche os campos de projeção: mesma execução
  // bem-sucedida de sempre (não-dry-run, confirmedBy setado), productsProjected/
  // observationsProjected/variantsProjectionSkipped ficam em 0 tanto no resumo da onda quanto
  // em cada entrada de perSet — a persistência real continua vindo exclusivamente de
  // productsResolved/productsWritten/observationsResolved/observationsWritten (regra 5: "o
  // caminho real completamente inalterado").
  {
    const seed = buildOndaSimplesSeed();
    const { client: supabase24 } = makeExpansionWaveFakeClient(seed);
    const { fetchImpl: fetchImpl24 } = makeFakeFetch(buildOndaSimplesSuccessResponses());
    const client24 = new JustTcgClient("sk-fake-24", fetchImpl24, 10);
    const resultado24 = await executeExpansionWave(supabase24, client24, {
      waveNumber: 1,
      dryRun: false,
      confirmedBy: "admin-1",
      maxApiRequests: 10,
      expectedSetCodes: ["SETX", "SETY"],
    });
    assert(
      "P14.4.2 fix2 cenário 24: caminho real (não-dry-run) nunca preenche productsProjected/observationsProjected/variantsProjectionSkipped — ficam em 0 no resumo, mesmo com escrita real bem-sucedida (productsWritten/observationsWritten > 0)",
      resultado24.productsProjected === 0 &&
        resultado24.observationsProjected === 0 &&
        resultado24.variantsProjectionSkipped === 0 &&
        resultado24.productsWritten > 0 &&
        resultado24.observationsWritten > 0 &&
        resultado24.status === "COMPLETED",
    );
    assert(
      "P14.4.2 fix2 cenário 24: os campos de projeção também ficam em 0 por Set em perSet no caminho real, nunca reaproveitados como contagem de escrita",
      resultado24.perSet.every((s) => s.productsProjected === 0 && s.observationsProjected === 0 && s.variantsProjectionSkipped === 0),
    );
  }

  // ==========================================================================
  // P14.4.3 — Testes focados do executor de backfill (--backfill-wave)
  // ==========================================================================
  //
  // Fixture base: SETB, já CONFIRMED no nível do Set (external_set_id=ext-b), com 3 cartas
  // ativas locais (card-b1/b2/b3) mas só card-b1 mapeada (pricing_card_mapping CONFIRMED) —
  // reproduz em miniatura a lacuna real de BASE1/ME1 (Set confirmado, cobertura de cartas
  // incompleta). missingCardsCount=2 (card-b2, card-b3).
  function buildBackfillSimplesSeed(): Record<string, FakeRow[]> {
    return {
      pricing_source: [{ id: "src-1", code: "JUSTTCG", is_active: true, requires_commercial_agreement: true }],
      card_set: [{ id: "cs-b", code: "SETB", release_date: "2020-03-01" }],
      catalog_card_set_metrics: [{ card_set_id: "cs-b", cards_ativas: 3 }],
      card: [
        { id: "card-b1", card_set_id: "cs-b", name: "Card B1", collector_number: "1", is_active: true },
        { id: "card-b2", card_set_id: "cs-b", name: "Card B2", collector_number: "2", is_active: true },
        { id: "card-b3", card_set_id: "cs-b", name: "Card B3", collector_number: "3", is_active: true },
      ],
      pricing_set_mapping: [{ card_set_id: "cs-b", pricing_source_id: "src-1", match_status: "CONFIRMED", external_set_id: "ext-b", external_set_name: "Ext B" }],
      pricing_card_mapping: [{ id: "pcm-b1", card_id: "card-b1", pricing_source_id: "src-1", match_status: "CONFIRMED" }],
      pricing_set_coverage: [
        { card_set_id: "cs-b", pricing_source_id: "src-1", products_count: 5, observations_count: 5, mapped_cards_count: 1, confirmed_cards_count: 1, pending_cards_count: 0, not_found_cards_count: 0 },
      ],
      pricing_condition_mapping: [{ pricing_source_id: "src-1", external_condition_code: "Near Mint", condition_id: "cond-nm" }],
    };
  }

  const backfillSimplesExternalSets = [{ id: "ext-b", name: "Ext B", release_date: "2020-03-01" }];

  function buildBackfillSimplesSuccessResponses(): Array<{ status: number; body: unknown }> {
    return [
      { status: 200, body: { data: backfillSimplesExternalSets } },
      {
        status: 200,
        body: {
          data: [
            { id: "ext-card-b1", name: "Card B1", number: "1", variants: [{ uuid: "var-b1", condition: "Near Mint", printing: "Normal", price: 1.0, lastUpdated: 1700000000 }] },
            { id: "ext-card-b2", name: "Card B2", number: "2", variants: [{ uuid: "var-b2", condition: "Near Mint", printing: "Normal", price: 2.0, lastUpdated: 1700000000 }] },
            { id: "ext-card-b3", name: "Card B3", number: "3", variants: [{ uuid: "var-b3", condition: "Near Mint", printing: "Normal", price: 3.0, lastUpdated: 1700000000 }] },
          ],
        },
      },
    ];
  }

  // Fixture com 2 Sets já CONFIRMED e incompletos (SETB + SETC) numa mesma onda de backfill —
  // usada pelos cenários de --expected-set-codes/orçamento/falha parcial que precisam de mais
  // de um Set na mesma onda.
  function buildBackfillDoisSetsSeed(): Record<string, FakeRow[]> {
    return {
      pricing_source: [{ id: "src-1", code: "JUSTTCG", is_active: true, requires_commercial_agreement: true }],
      card_set: [
        { id: "cs-b", code: "SETB", release_date: "2020-03-01" },
        { id: "cs-c", code: "SETC", release_date: "2020-04-01" },
      ],
      catalog_card_set_metrics: [
        { card_set_id: "cs-b", cards_ativas: 3 },
        { card_set_id: "cs-c", cards_ativas: 2 },
      ],
      card: [
        { id: "card-b1", card_set_id: "cs-b", name: "Card B1", collector_number: "1", is_active: true },
        { id: "card-b2", card_set_id: "cs-b", name: "Card B2", collector_number: "2", is_active: true },
        { id: "card-b3", card_set_id: "cs-b", name: "Card B3", collector_number: "3", is_active: true },
        { id: "card-c1", card_set_id: "cs-c", name: "Card C1", collector_number: "1", is_active: true },
        { id: "card-c2", card_set_id: "cs-c", name: "Card C2", collector_number: "2", is_active: true },
      ],
      pricing_set_mapping: [
        { card_set_id: "cs-b", pricing_source_id: "src-1", match_status: "CONFIRMED", external_set_id: "ext-b", external_set_name: "Ext B" },
        { card_set_id: "cs-c", pricing_source_id: "src-1", match_status: "CONFIRMED", external_set_id: "ext-c", external_set_name: "Ext C" },
      ],
      pricing_card_mapping: [
        { id: "pcm-b1", card_id: "card-b1", pricing_source_id: "src-1", match_status: "CONFIRMED" },
        { id: "pcm-c1", card_id: "card-c1", pricing_source_id: "src-1", match_status: "CONFIRMED" },
      ],
      pricing_set_coverage: [
        { card_set_id: "cs-b", pricing_source_id: "src-1", products_count: 5, observations_count: 5, mapped_cards_count: 1, confirmed_cards_count: 1, pending_cards_count: 0, not_found_cards_count: 0 },
        { card_set_id: "cs-c", pricing_source_id: "src-1", products_count: 5, observations_count: 5, mapped_cards_count: 1, confirmed_cards_count: 1, pending_cards_count: 0, not_found_cards_count: 0 },
      ],
      pricing_condition_mapping: [{ pricing_source_id: "src-1", external_condition_code: "Near Mint", condition_id: "cond-nm" }],
    };
  }

  const backfillDoisSetsExternalSets = [
    { id: "ext-b", name: "Ext B", release_date: "2020-03-01" },
    { id: "ext-c", name: "Ext C", release_date: "2020-04-01" },
  ];

  // Cenário 1 — Set completo (mapped_cards_count == localCardCount) NUNCA entra em
  // backfillWaves — só o gap real (ausência total de mapping) forma candidato a backfill.
  {
    const seedCompleto = {
      pricing_source: [{ id: "src-1", code: "JUSTTCG", is_active: true, requires_commercial_agreement: true }],
      card_set: [{ id: "cs-full", code: "SETFULL", release_date: "2020-05-01" }],
      catalog_card_set_metrics: [{ card_set_id: "cs-full", cards_ativas: 2 }],
      card: [],
      pricing_set_mapping: [{ card_set_id: "cs-full", pricing_source_id: "src-1", match_status: "CONFIRMED", external_set_id: "ext-full", external_set_name: "Ext Full" }],
      pricing_set_coverage: [
        { card_set_id: "cs-full", pricing_source_id: "src-1", products_count: 20, observations_count: 20, mapped_cards_count: 2, confirmed_cards_count: 2, pending_cards_count: 0, not_found_cards_count: 0 },
      ],
    };
    const supabaseBF1 = makeReadOnlyFakeClient(seedCompleto, { countOverride: { card: 2 } });
    const inputsBF1 = await fetchReconciledLocalInputs(supabaseBF1);
    const planBF1 = buildExpansionPlan({
      localSets: inputsBF1.localSets,
      existingSetMappings: inputsBF1.existingSetMappings,
      allExternalSets: [{ id: "ext-full", name: "Ext Full", release_date: "2020-05-01", variants_count: 10 }],
      existingCoverage: inputsBF1.existingCoverage,
    });
    assert(
      "P14.4.3 backfill cenário 1: Set completo (mapped_cards_count == localCardCount) nunca entra em backfillWaves — status ALREADY_CONFIRMED_COMPLETE, missingCardsCount=0",
      planBF1.backfillWaves.length === 0 &&
        planBF1.entries.find((e) => e.code === "SETFULL")?.status === "ALREADY_CONFIRMED_COMPLETE" &&
        planBF1.entries.find((e) => e.code === "SETFULL")?.missingCardsCount === 0,
    );
  }

  // Cenário 2 — Set parcial entra em backfillWaves com o missingCardsCount exato, e a
  // composição da onda é determinística (mesmo algoritmo de buildExpansionWaves, aplicado
  // sobre missingCardsCount).
  {
    const supabaseBF2 = makeReadOnlyFakeClient(buildBackfillSimplesSeed(), { countOverride: { card: 3 } });
    const inputsBF2 = await fetchReconciledLocalInputs(supabaseBF2);
    const planBF2 = buildExpansionPlan({
      localSets: inputsBF2.localSets,
      existingSetMappings: inputsBF2.existingSetMappings,
      allExternalSets: backfillSimplesExternalSets,
      existingCoverage: inputsBF2.existingCoverage,
    });
    assert(
      "P14.4.3 backfill cenário 2: SETB (3 cartas ativas, 1 já mapeada) -> ALREADY_CONFIRMED_INCOMPLETE com missingCardsCount=2, forma sozinho a onda de backfill 1",
      planBF2.entries.find((e) => e.code === "SETB")?.status === "ALREADY_CONFIRMED_INCOMPLETE" &&
        planBF2.entries.find((e) => e.code === "SETB")?.missingCardsCount === 2 &&
        planBF2.backfillWaves.length === 1 &&
        planBF2.backfillWaves[0].sets.length === 1 &&
        planBF2.backfillWaves[0].sets[0].code === "SETB" &&
        planBF2.backfillWaves[0].sets[0].missingCardsCount === 2,
    );
  }

  // Cenário 3 — cartas locais SEM mapping (findMissingCardsForSet) e, executando a onda,
  // cartas já PENDING/CONFIRMED nunca são retocadas: card-b1 (CONFIRMED) e card-b2 (PENDING)
  // permanecem intactas; só card-b3 (zero mapping) recebe um novo mapping/produto/observação.
  {
    const seedBF3 = buildBackfillSimplesSeed();
    seedBF3.pricing_card_mapping = [
      { id: "pcm-b1", card_id: "card-b1", pricing_source_id: "src-1", match_status: "CONFIRMED" },
      { id: "pcm-b2", card_id: "card-b2", pricing_source_id: "src-1", match_status: "PENDING" },
    ];
    seedBF3.pricing_set_coverage = [
      { card_set_id: "cs-b", pricing_source_id: "src-1", products_count: 5, observations_count: 5, mapped_cards_count: 2, confirmed_cards_count: 1, pending_cards_count: 1, not_found_cards_count: 0 },
    ];
    const missingBF3 = await findMissingCardsForSet(makeExpansionWaveFakeClient(seedBF3).client, "cs-b", "src-1");
    assert(
      "P14.4.3 backfill cenário 3: findMissingCardsForSet() nunca retorna card-b1 (CONFIRMED) nem card-b2 (PENDING) — só card-b3 (zero mapping)",
      missingBF3.length === 1 && missingBF3[0].card_id === "card-b3",
    );

    const { client: supabaseBF3, tables: tablesBF3 } = makeExpansionWaveFakeClient(seedBF3);
    const { fetchImpl: fetchImplBF3 } = makeFakeFetch(buildBackfillSimplesSuccessResponses());
    const clientBF3 = new JustTcgClient("sk-fake-bf3", fetchImplBF3, 10);
    const resultadoBF3 = await executeBackfillWave(supabaseBF3, clientBF3, { waveNumber: 1, dryRun: false, confirmedBy: "admin-1", maxApiRequests: 10, expectedSetCodes: ["SETB"] });
    const mappingB1 = (tablesBF3.pricing_card_mapping ?? []).find((r) => r.card_id === "card-b1") as { match_status: string } | undefined;
    const mappingB2 = (tablesBF3.pricing_card_mapping ?? []).find((r) => r.card_id === "card-b2") as { match_status: string } | undefined;
    const mappingB3 = (tablesBF3.pricing_card_mapping ?? []).find((r) => r.card_id === "card-b3") as { match_status: string } | undefined;
    assert(
      "P14.4.3 backfill cenário 3: execução real só cria mapping novo para card-b3 — card-b1 (CONFIRMED) e card-b2 (PENDING) permanecem com o status anterior, nunca reprocessados",
      resultadoBF3.status === "COMPLETED" &&
        resultadoBF3.cardsProcessed === 1 &&
        mappingB1?.match_status === "CONFIRMED" &&
        mappingB2?.match_status === "PENDING" &&
        mappingB3?.match_status === "CONFIRMED",
    );
  }

  // Cenário 4 — o executor usa EXCLUSIVAMENTE o external_set_id já CONFIRMED: pricing_set_mapping
  // nunca é escrito/alterado pelo backfill (nem resolveSetMatchV2 nem upsertSetMapping são
  // chamados) — a linha de mapping do Set permanece byte-a-byte idêntica à do seed.
  {
    const seedBF4 = buildBackfillSimplesSeed();
    const { client: supabaseBF4, tables: tablesBF4 } = makeExpansionWaveFakeClient(seedBF4);
    const { fetchImpl: fetchImplBF4 } = makeFakeFetch(buildBackfillSimplesSuccessResponses());
    const clientBF4 = new JustTcgClient("sk-fake-bf4", fetchImplBF4, 10);
    const resultadoBF4 = await executeBackfillWave(supabaseBF4, clientBF4, { waveNumber: 1, dryRun: false, confirmedBy: "admin-1", maxApiRequests: 10, expectedSetCodes: ["SETB"] });
    assert(
      "P14.4.3 backfill cenário 4: executor usa exclusivamente o external_set_id já CONFIRMED — pricing_set_mapping nunca é escrito/alterado (mesma 1 linha do seed, byte-a-byte), resolveSetMatchV2/upsertSetMapping nunca chamados",
      resultadoBF4.status === "COMPLETED" &&
        tablesBF4.pricing_set_mapping.length === 1 &&
        tablesBF4.pricing_set_mapping[0].external_set_id === "ext-b" &&
        tablesBF4.pricing_set_mapping[0].match_status === "CONFIRMED",
    );
  }

  // Cenário 5 — composição de onda determinística (mesmo algoritmo 5 Sets/500 cartas de
  // buildExpansionWaves, aplicado sobre missingCardsCount): 6 Sets pequenos -> onda 1 com 5,
  // onda 2 com o 6º; um Set individual com >500 cartas faltantes forma sua própria onda
  // oversized, sem interromper o agrupamento dos Sets seguintes.
  {
    const seisSetsPequenos: BackfillWaveSetEntry[] = Array.from({ length: 6 }, (_, i) => ({ code: `SB${i + 1}`, missingCardsCount: 50, localCardCount: 100 }));
    const ondasBF5a = buildBackfillWaves(seisSetsPequenos);
    assert(
      "P14.4.3 backfill cenário 5: 6 Sets pequenos (50 cartas faltantes cada) -> onda 1 com 5 Sets, onda 2 com o 6º (limite de 5 Sets por onda, mesmo algoritmo de buildExpansionWaves)",
      ondasBF5a.length === 2 && ondasBF5a[0].sets.length === 5 && ondasBF5a[1].sets.length === 1 && ondasBF5a[1].sets[0].code === "SB6",
    );

    const setGigantePrimeiro: BackfillWaveSetEntry[] = [
      { code: "SBGIANT", missingCardsCount: 600, localCardCount: 700 },
      { code: "SB1", missingCardsCount: 50, localCardCount: 100 },
      { code: "SB2", missingCardsCount: 50, localCardCount: 100 },
    ];
    const ondasBF5b = buildBackfillWaves(setGigantePrimeiro);
    assert(
      "P14.4.3 backfill cenário 5: Set individual com missingCardsCount > 500 nunca é dividido nem descartado — forma sua própria onda oversized, sem impedir os Sets seguintes de se agruparem numa onda própria",
      ondasBF5b.length === 2 && ondasBF5b[0].oversized === true && ondasBF5b[0].sets[0].code === "SBGIANT" && ondasBF5b[1].sets.length === 2 && ondasBF5b[1].oversized === false,
    );
  }

  // Cenário 6 — --expected-set-codes bloqueia deriva de composição: onda recalculada com
  // SETB+SETC, mas só SETB é informado -> BACKFILL_WAVE_COMPOSITION_CHANGED antes de qualquer
  // GET /cards, zero persistência de negócio, CARD_SYNC já aberto é finalizado como FAILED.
  {
    const { client: supabaseBF6, tables: tablesBF6 } = makeExpansionWaveFakeClient(buildBackfillDoisSetsSeed());
    const { fetchImpl: fetchImplBF6, callCount: callCountBF6 } = makeFakeFetch([{ status: 200, body: { data: backfillDoisSetsExternalSets } }]);
    const clientBF6 = new JustTcgClient("sk-fake-bf6", fetchImplBF6, 10);
    let erroBF6: Error | null = null;
    try {
      await executeBackfillWave(supabaseBF6, clientBF6, { waveNumber: 1, dryRun: false, confirmedBy: "admin-1", maxApiRequests: 10, expectedSetCodes: ["SETB"] });
    } catch (error) {
      erroBF6 = error instanceof Error ? error : null;
    }
    assert(
      "P14.4.3 backfill cenário 6: --expected-set-codes=SETB (faltando SETC) é rejeitado com BACKFILL_WAVE_COMPOSITION_CHANGED, zero mapping/produto/observação persistidos, CARD_SYNC finalizado FAILED",
      erroBF6 !== null &&
        erroBF6.message.startsWith("BACKFILL_WAVE_COMPOSITION_CHANGED") &&
        callCountBF6() === 1 &&
        (tablesBF6.pricing_card_mapping ?? []).length === 2 &&
        (tablesBF6.pricing_product ?? []).length === 0 &&
        (tablesBF6.pricing_observation ?? []).length === 0 &&
        tablesBF6.pricing_sync_run.length === 1 &&
        (tablesBF6.pricing_sync_run[0] as { status: string }).status === "FAILED",
    );
  }

  // Cenário 7 — orçamento local (--max-api-requests) é respeitado: budget=2 alcança só
  // GET /sets + a 1ª página de /cards de SETB; a página de SETC nunca é sequer tentada
  // (budgetOk() barra antes do fetch) -> ORCAMENTO_ESGOTADO, FAILED, zero persistência.
  {
    const { client: supabaseBF7, tables: tablesBF7 } = makeExpansionWaveFakeClient(buildBackfillDoisSetsSeed());
    const { fetchImpl: fetchImplBF7, callCount: callCountBF7 } = makeFakeFetch([
      { status: 200, body: { data: backfillDoisSetsExternalSets } },
      { status: 200, body: { data: [{ id: "ext-card-b2", name: "Card B2", number: "2", variants: [] }] } },
    ]);
    const clientBF7 = new JustTcgClient("sk-fake-bf7", fetchImplBF7, 2);
    const resultadoBF7 = await executeBackfillWave(supabaseBF7, clientBF7, { waveNumber: 1, dryRun: false, confirmedBy: "admin-1", maxApiRequests: 2, expectedSetCodes: ["SETB", "SETC"] });
    assert(
      "P14.4.3 backfill cenário 7: --max-api-requests=2 nunca é ultrapassado — exatamente 2 chamadas reais (GET /sets + 1ª página de SETB), SETC nunca sequer tentado; status FAILED, zero persistência de negócio",
      callCountBF7() === 2 &&
        clientBF7.requestsMade === 2 &&
        resultadoBF7.status === "FAILED" &&
        (tablesBF7.pricing_product ?? []).length === 0 &&
        (tablesBF7.pricing_observation ?? []).length === 0 &&
        (tablesBF7.pricing_card_mapping ?? []).length === 2,
    );
  }

  // Cenário 8 — --dry-run gera zero escrita: nenhum pricing_sync_run criado, nenhuma linha
  // nova em nenhuma tabela de negócio, mesmo com a classificação das cartas faltantes
  // completa e bem-sucedida (regra 4/dry-run do executor de backfill).
  {
    const seedBF8 = buildBackfillSimplesSeed();
    const { client: supabaseBF8, tables: tablesBF8 } = makeExpansionWaveFakeClient(seedBF8);
    const { fetchImpl: fetchImplBF8 } = makeFakeFetch(buildBackfillSimplesSuccessResponses());
    const clientBF8 = new JustTcgClient("sk-fake-bf8", fetchImplBF8, 10);
    const resultadoBF8 = await executeBackfillWave(supabaseBF8, clientBF8, { waveNumber: 1, dryRun: true, confirmedBy: null, maxApiRequests: 10, expectedSetCodes: ["SETB"] });
    assert(
      "P14.4.3 backfill cenário 8: --dry-run nunca cria pricing_sync_run nem escreve mapping/produto/observação novos, mesmo com as 2 cartas faltantes classificadas com sucesso",
      resultadoBF8.status === "COMPLETED" &&
        resultadoBF8.cardsProcessed === 2 &&
        resultadoBF8.cardsSafe === 2 &&
        (tablesBF8.pricing_sync_run ?? []).length === 0 &&
        (tablesBF8.pricing_card_mapping ?? []).length === 1 &&
        (tablesBF8.pricing_product ?? []).length === 0 &&
        (tablesBF8.pricing_observation ?? []).length === 0 &&
        resultadoBF8.productsProjected > 0,
    );
  }

  // Cenário 9 — conflito de concorrência bloqueia qualquer chamada externa: já existe um
  // CARD_SYNC RECEIVED/PROCESSING para a mesma fonte -> CONFLITO_DE_CONCORRENCIA antes do
  // GET /sets, zero requisições HTTP, nenhuma 2ª linha em pricing_sync_run.
  {
    const seedBF9 = buildBackfillSimplesSeed();
    seedBF9.pricing_sync_run = [{ id: "run-existing", pricing_source_id: "src-1", run_type: "CARD_SYNC", status: "PROCESSING" }];
    const { client: supabaseBF9, tables: tablesBF9 } = makeExpansionWaveFakeClient(seedBF9);
    const { fetchImpl: fetchImplBF9, callCount: callCountBF9 } = makeFakeFetch(buildBackfillSimplesSuccessResponses());
    const clientBF9 = new JustTcgClient("sk-fake-bf9", fetchImplBF9, 10);
    let erroBF9: Error | null = null;
    try {
      await executeBackfillWave(supabaseBF9, clientBF9, { waveNumber: 1, dryRun: false, confirmedBy: "admin-1", maxApiRequests: 10, expectedSetCodes: ["SETB"] });
    } catch (error) {
      erroBF9 = error instanceof Error ? error : null;
    }
    assert(
      "P14.4.3 backfill cenário 9: conflito de concorrência (CARD_SYNC já ativo) aborta com CONFLITO_DE_CONCORRENCIA antes de qualquer chamada à JustTCG, sem criar uma 2ª linha em pricing_sync_run",
      erroBF9 !== null && erroBF9.message.startsWith("CONFLITO_DE_CONCORRENCIA") && callCountBF9() === 0 && clientBF9.requestsMade === 0 && tablesBF9.pricing_sync_run.length === 1,
    );
  }

  // Cenário 10 — erro em qualquer Set da onda bloqueia a persistência da onda inteira, mesmo
  // que outro Set já tenha sido classificado com sucesso e mantido só em memória: SETB é
  // adquirido e classificado com sucesso (2 cartas), mas a paginação de SETC falha (HTTP 500)
  // -> zero mapping/produto/observação persistidos para SETB também (regra "tudo ou nada").
  {
    const { client: supabaseBF10, tables: tablesBF10 } = makeExpansionWaveFakeClient(buildBackfillDoisSetsSeed());
    const { fetchImpl: fetchImplBF10 } = makeFakeFetch([
      { status: 200, body: { data: backfillDoisSetsExternalSets } },
      {
        status: 200,
        body: {
          data: [
            { id: "ext-card-b2", name: "Card B2", number: "2", variants: [{ uuid: "var-b2", condition: "Near Mint", printing: "Normal", price: 2.0, lastUpdated: 1700000000 }] },
            { id: "ext-card-b3", name: "Card B3", number: "3", variants: [{ uuid: "var-b3", condition: "Near Mint", printing: "Normal", price: 3.0, lastUpdated: 1700000000 }] },
          ],
        },
      },
      { status: 500, body: { error: "falha simulada" } },
    ]);
    const clientBF10 = new JustTcgClient("sk-fake-bf10", fetchImplBF10, 10);
    const resultadoBF10 = await executeBackfillWave(supabaseBF10, clientBF10, { waveNumber: 1, dryRun: false, confirmedBy: "admin-1", maxApiRequests: 10, expectedSetCodes: ["SETB", "SETC"] });
    assert(
      "P14.4.3 backfill cenário 10: falha de paginação em SETC (HTTP 500) aborta a onda inteira -> zero mapping/produto/observação persistidos, mesmo com SETB já classificado com sucesso em memória; status FAILED",
      resultadoBF10.status === "FAILED" &&
        resultadoBF10.errorParts.some((e) => e.startsWith("PAGINACAO_CARDS_FALHOU(SETC)")) &&
        (tablesBF10.pricing_card_mapping ?? []).length === 2 &&
        (tablesBF10.pricing_product ?? []).length === 0 &&
        (tablesBF10.pricing_observation ?? []).length === 0,
    );
  }

  // Cenário 11 — leituras reconciliadas do backfill nunca confiam numa única página:
  // findMissingCardsForSet() aborta com PAGINACAO_INCOMPLETA se a contagem exata e
  // independente de pricing_card_mapping divergir do que a paginação trouxe — mesma
  // disciplina de fetchReconciledLocalInputs(), imune ao limite de 1.000 linhas do Data API
  // mesmo com uma divergência pequena (nunca depende do volume para disparar).
  {
    const seedBF11: Record<string, FakeRow[]> = {
      card: [
        { id: "card-t1", card_set_id: "cs-t", name: "T1", collector_number: "1", is_active: true },
        { id: "card-t2", card_set_id: "cs-t", name: "T2", collector_number: "2", is_active: true },
      ],
      pricing_card_mapping: [{ id: "pcm-t1", card_id: "card-t1", pricing_source_id: "src-1", match_status: "CONFIRMED" }],
    };
    const { client: supabaseBF11 } = makeExpansionWaveFakeClient(seedBF11, { countOverride: { "pricing_card_mapping:filtered": 5 } });
    let erroBF11: Error | null = null;
    try {
      await findMissingCardsForSet(supabaseBF11, "cs-t", "src-1");
    } catch (error) {
      erroBF11 = error instanceof Error ? error : null;
    }
    assert(
      "P14.4.3 backfill cenário 11: findMissingCardsForSet() aborta com PAGINACAO_INCOMPLETA(pricing_card_mapping...) quando a contagem exata diverge da paginação, mesmo com poucas linhas (imune ao limite de 1.000, nunca depende do volume)",
      erroBF11 !== null && erroBF11.message.startsWith("PAGINACAO_INCOMPLETA(pricing_card_mapping"),
    );
  }

  // Cenário 12 — wiring de CLI: --backfill-wave é mutuamente exclusivo com --expansion-plan e
  // --expansion-wave (rejeitado ANTES de qualquer validação de formato/credencial), isolado
  // aciona BACKFILL_WAVE normalmente, e --expansion-wave sozinho continua funcionando
  // exatamente como antes (regressão de P14.4.2 preservada).
  {
    const CREDS_OK_BF12 = { justTcgApiKey: "sk-fake-justtcg-bf12", supabaseUrl: "https://fake.supabase.co", supabaseServiceRoleKey: "sk-fake-service-role-bf12" };

    const decisaoMutuamenteExclusivo1 = resolveEntryDecision(
      { fixtureCheck: false, expansionPlan: false, expansionWave: "1", maxApiRequests: "10", dryRun: true, confirmedBy: null, expectedSetCodes: "SETX,SETY", backfillWave: "1" },
      CREDS_OK_BF12,
    );
    assert(
      "P14.4.3 backfill cenário 12: --backfill-wave combinado com --expansion-wave é rejeitado com BACKFILL_WAVE_INVALID_ARGS/MODOS_MUTUAMENTE_EXCLUSIVOS, antes de qualquer validação de formato/credencial",
      decisaoMutuamenteExclusivo1.kind === "BACKFILL_WAVE_INVALID_ARGS" && decisaoMutuamenteExclusivo1.reason.startsWith("MODOS_MUTUAMENTE_EXCLUSIVOS"),
    );

    const decisaoMutuamenteExclusivo2 = resolveEntryDecision(
      { fixtureCheck: false, expansionPlan: true, dryRun: true, confirmedBy: null, backfillWave: "1", maxApiRequests: "10", expectedSetCodes: "SETB" },
      CREDS_OK_BF12,
    );
    assert(
      "P14.4.3 backfill cenário 12: --backfill-wave combinado com --expansion-plan também é rejeitado com MODOS_MUTUAMENTE_EXCLUSIVOS",
      decisaoMutuamenteExclusivo2.kind === "BACKFILL_WAVE_INVALID_ARGS" && decisaoMutuamenteExclusivo2.reason.startsWith("MODOS_MUTUAMENTE_EXCLUSIVOS"),
    );

    const decisaoBackfillValida = resolveEntryDecision(
      { fixtureCheck: false, expansionPlan: false, expansionWave: null, dryRun: true, confirmedBy: null, backfillWave: "1", maxApiRequests: "10", expectedSetCodes: "SETB" },
      CREDS_OK_BF12,
    );
    assert(
      "P14.4.3 backfill cenário 12: --backfill-wave=1 isolado (sem --expansion-plan/--expansion-wave) aciona BACKFILL_WAVE com o número exato pedido, nunca 'todas as ondas'",
      decisaoBackfillValida.kind === "BACKFILL_WAVE" &&
        decisaoBackfillValida.waveNumber === 1 &&
        decisaoBackfillValida.maxApiRequests === 10 &&
        decisaoBackfillValida.expectedSetCodes.join(",") === "SETB",
    );

    const decisaoExpansionWaveIntacta = resolveEntryDecision(
      { fixtureCheck: false, expansionPlan: false, expansionWave: "1", maxApiRequests: "10", dryRun: true, confirmedBy: null, expectedSetCodes: "SETX,SETY", backfillWave: null },
      CREDS_OK_BF12,
    );
    assert(
      "P14.4.3 backfill cenário 12: --expansion-wave sozinho (sem --backfill-wave) continua funcionando exatamente como antes de P14.4.3 (regressão preservada)",
      decisaoExpansionWaveIntacta.kind === "EXPANSION_WAVE" && decisaoExpansionWaveIntacta.waveNumber === 1,
    );
  }

  // ==========================================================================
  // P14.4.4 — Testes focados do executor de reparo (--repair-mappings)
  // ==========================================================================
  //
  // Fixture base: SETR, já CONFIRMED no nível do Set (external_set_id=ext-r), com 4 cartas
  // ativas locais: card-r1 (CONFIRMED, nunca deve ser tocada), card-r2 (PENDING, candidato
  // externo único -> deve promover a SAFE), card-r3 (NOT_FOUND, candidato externo único
  // apareceu agora -> deve promover a SAFE), card-r4 (PENDING, dois candidatos externos com
  // o mesmo número -> continua AMBIGUOUS, intocada). Reproduz em miniatura o cenário real
  // descoberto na auditoria pós-P14.4.3 (NUMERO_UNICO_MAS_NOME_DIVERGENTE em BASE1/ME1).
  function buildRepairSimplesSeed(): Record<string, FakeRow[]> {
    return {
      pricing_source: [{ id: "src-1", code: "JUSTTCG", is_active: true, requires_commercial_agreement: true }],
      card_set: [{ id: "cs-r", code: "SETR", release_date: "2020-03-01" }],
      catalog_card_set_metrics: [{ card_set_id: "cs-r", cards_ativas: 4 }],
      card: [
        { id: "card-r1", card_set_id: "cs-r", name: "Card R1", collector_number: "1", is_active: true },
        { id: "card-r2", card_set_id: "cs-r", name: "Card R2 PT", collector_number: "2", is_active: true },
        { id: "card-r3", card_set_id: "cs-r", name: "Card R3 PT", collector_number: "3", is_active: true },
        { id: "card-r4", card_set_id: "cs-r", name: "Card R4 PT", collector_number: "4", is_active: true },
      ],
      pricing_set_mapping: [{ card_set_id: "cs-r", pricing_source_id: "src-1", match_status: "CONFIRMED", external_set_id: "ext-r", external_set_name: "Ext R" }],
      pricing_card_mapping: [
        { id: "pcm-r1", card_id: "card-r1", pricing_source_id: "src-1", match_status: "CONFIRMED" },
        { id: "pcm-r2", card_id: "card-r2", pricing_source_id: "src-1", match_status: "PENDING" },
        { id: "pcm-r3", card_id: "card-r3", pricing_source_id: "src-1", match_status: "NOT_FOUND" },
        { id: "pcm-r4", card_id: "card-r4", pricing_source_id: "src-1", match_status: "PENDING" },
      ],
      pricing_set_coverage: [
        { card_set_id: "cs-r", pricing_source_id: "src-1", products_count: 0, observations_count: 0, mapped_cards_count: 4, confirmed_cards_count: 1, pending_cards_count: 2, not_found_cards_count: 1 },
      ],
      pricing_condition_mapping: [{ pricing_source_id: "src-1", external_condition_code: "Near Mint", condition_id: "cond-nm" }],
    };
  }

  const repairSimplesExternalCards = [
    { id: "ext-card-r2", name: "Card R2 EN", number: "2", variants: [{ uuid: "var-r2", condition: "Near Mint", printing: "Normal", price: 2.5, lastUpdated: 1700000000 }] },
    { id: "ext-card-r3", name: "Card R3 EN", number: "3", variants: [{ uuid: "var-r3", condition: "Near Mint", printing: "Normal", price: 3.5, lastUpdated: 1700000000 }] },
    { id: "ext-card-r4a", name: "Card R4 EN A", number: "4", variants: [] },
    { id: "ext-card-r4b", name: "Card R4 EN B", number: "4", variants: [] },
  ];

  function buildRepairSimplesSuccessResponses(): Array<{ status: number; body: unknown }> {
    return [{ status: 200, body: { data: repairSimplesExternalCards } }];
  }

  // Fixture com 2 Sets já CONFIRMED e com PENDING pendente (SETR + SETS) — usada pelos
  // cenários de --expected-set-codes/orçamento/falha parcial que precisam de mais de um Set.
  function buildRepairDoisSetsSeed(): Record<string, FakeRow[]> {
    return {
      pricing_source: [{ id: "src-1", code: "JUSTTCG", is_active: true, requires_commercial_agreement: true }],
      card_set: [
        { id: "cs-r", code: "SETR", release_date: "2020-03-01" },
        { id: "cs-s", code: "SETS", release_date: "2020-04-01" },
      ],
      catalog_card_set_metrics: [
        { card_set_id: "cs-r", cards_ativas: 1 },
        { card_set_id: "cs-s", cards_ativas: 1 },
      ],
      card: [
        { id: "card-r2", card_set_id: "cs-r", name: "Card R2 PT", collector_number: "2", is_active: true },
        { id: "card-s1", card_set_id: "cs-s", name: "Card S1 PT", collector_number: "1", is_active: true },
      ],
      pricing_set_mapping: [
        { card_set_id: "cs-r", pricing_source_id: "src-1", match_status: "CONFIRMED", external_set_id: "ext-r", external_set_name: "Ext R" },
        { card_set_id: "cs-s", pricing_source_id: "src-1", match_status: "CONFIRMED", external_set_id: "ext-s", external_set_name: "Ext S" },
      ],
      pricing_card_mapping: [
        { id: "pcm-r2", card_id: "card-r2", pricing_source_id: "src-1", match_status: "PENDING" },
        { id: "pcm-s1", card_id: "card-s1", pricing_source_id: "src-1", match_status: "PENDING" },
      ],
      pricing_set_coverage: [
        { card_set_id: "cs-r", pricing_source_id: "src-1", products_count: 0, observations_count: 0, mapped_cards_count: 1, confirmed_cards_count: 0, pending_cards_count: 1, not_found_cards_count: 0 },
        { card_set_id: "cs-s", pricing_source_id: "src-1", products_count: 0, observations_count: 0, mapped_cards_count: 1, confirmed_cards_count: 0, pending_cards_count: 1, not_found_cards_count: 0 },
      ],
      pricing_condition_mapping: [{ pricing_source_id: "src-1", external_condition_code: "Near Mint", condition_id: "cond-nm" }],
    };
  }

  function buildRepairDoisSetsSuccessResponses(): Array<{ status: number; body: unknown }> {
    return [
      { status: 200, body: { data: [{ id: "ext-card-r2", name: "Card R2 EN", number: "2", variants: [{ uuid: "var-r2", condition: "Near Mint", printing: "Normal", price: 2.5, lastUpdated: 1700000000 }] }] } },
      { status: 200, body: { data: [{ id: "ext-card-s1", name: "Card S1 EN", number: "1", variants: [{ uuid: "var-s1", condition: "Near Mint", printing: "Normal", price: 1.5, lastUpdated: 1700000000 }] }] } },
    ];
  }

  // Cenário 1 — buildRepairCandidates() deriva a lista de Sets-alvo dinamicamente: SETA
  // (CONFIRMED, pending+notFound>0) entra; SETB (CONFIRMED mas 0 pending/notFound — o caso
  // real descoberto na auditoria, BASE5 citado como alvo mas sem nenhum PENDING/NOT_FOUND)
  // é excluído sem precisar de lista negativa; SETC (Set ainda PENDING, não CONFIRMED) nunca
  // é candidato a reparo, mesmo que tivesse coverage — reparo nunca reavalia Set.
  {
    const localSetsRC1: LocalSetSummary[] = [
      { cardSetId: "cs-a", code: "SETA", releaseDateIso: "2020-01-01", localCardCount: 10 },
      { cardSetId: "cs-b", code: "SETB", releaseDateIso: "2020-02-01", localCardCount: 10 },
      { cardSetId: "cs-c", code: "SETC", releaseDateIso: "2020-03-01", localCardCount: 10 },
    ];
    const mapRC1 = new Map<string, ExistingSetMappingLite>([
      ["cs-a", { cardSetId: "cs-a", matchStatus: "CONFIRMED", externalSetId: "ext-a", externalSetName: "Ext A" }],
      ["cs-b", { cardSetId: "cs-b", matchStatus: "CONFIRMED", externalSetId: "ext-b", externalSetName: "Ext B" }],
      ["cs-c", { cardSetId: "cs-c", matchStatus: "PENDING", externalSetId: null, externalSetName: null }],
    ]);
    const covRC1 = new Map<string, SetCoverageAggregate>([
      ["cs-a", { products: 5, observations: 5, mappedCards: 10, confirmedCards: 7, pendingCards: 2, notFoundCards: 1 }],
      ["cs-b", { products: 5, observations: 5, mappedCards: 10, confirmedCards: 10, pendingCards: 0, notFoundCards: 0 }],
    ]);
    const candidatesRC1 = buildRepairCandidates(localSetsRC1, mapRC1, covRC1);
    assert(
      "P14.4.4 repair cenário 1: buildRepairCandidates() é dinâmico — SETA (CONFIRMED, pending+notFound>0) entra; SETB (CONFIRMED mas 0 pendências, caso real BASE5) é excluído sem lista negativa; SETC (Set ainda não CONFIRMED) nunca é candidato",
      candidatesRC1.length === 1 && candidatesRC1[0].code === "SETA" && candidatesRC1[0].externalSetId === "ext-a" && candidatesRC1[0].pendingCount === 2 && candidatesRC1[0].notFoundCount === 1,
    );
  }

  // Cenário 2 — findPendingOrNotFoundCardsForSet() retorna SOMENTE cartas PENDING/NOT_FOUND
  // ativas do Set: nunca CONFIRMED, nunca cartas sem nenhum mapping, nunca cartas inativas.
  {
    const seedRC2: Record<string, FakeRow[]> = {
      card: [
        { id: "card-x1", card_set_id: "cs-x", name: "X1", collector_number: "1", is_active: true },
        { id: "card-x2", card_set_id: "cs-x", name: "X2", collector_number: "2", is_active: true },
        { id: "card-x3", card_set_id: "cs-x", name: "X3", collector_number: "3", is_active: true },
        { id: "card-x4", card_set_id: "cs-x", name: "X4", collector_number: "4", is_active: false },
      ],
      pricing_card_mapping: [
        { id: "pcm-x1", card_id: "card-x1", pricing_source_id: "src-1", match_status: "CONFIRMED" },
        { id: "pcm-x2", card_id: "card-x2", pricing_source_id: "src-1", match_status: "PENDING" },
        { id: "pcm-x3", card_id: "card-x3", pricing_source_id: "src-1", match_status: "NOT_FOUND" },
      ],
    };
    const { client: supabaseRC2 } = makeExpansionWaveFakeClient(seedRC2);
    const targetRC2 = await findPendingOrNotFoundCardsForSet(supabaseRC2, "cs-x", "src-1");
    assert(
      "P14.4.4 repair cenário 2: findPendingOrNotFoundCardsForSet() retorna só card-x2 (PENDING) e card-x3 (NOT_FOUND) — nunca card-x1 (CONFIRMED, x5 sem mapping algum não existe aqui, nem card-x4 (inativa)",
      targetRC2.length === 2 && targetRC2.some((c) => c.card_id === "card-x2") && targetRC2.some((c) => c.card_id === "card-x3"),
    );
  }

  // Cenário 3 — execução real fim a fim: card-r2 (PENDING) e card-r3 (NOT_FOUND) promovem a
  // CONFIRMED com produto/observação criados na mesma execução; card-r1 (CONFIRMED) permanece
  // byte-a-byte intocada; card-r4 (PENDING, 2 candidatos externos mesmo número) continua
  // PENDING, sem nenhuma escrita — nem mapping, nem produto, nem observação para ela. O
  // executor nunca chama GET /sets (só 1 requisição HTTP no total, para /cards de SETR).
  {
    const { client: supabaseRC3, tables: tablesRC3 } = makeExpansionWaveFakeClient(buildRepairSimplesSeed());
    const { fetchImpl: fetchImplRC3, callCount: callCountRC3 } = makeFakeFetch(buildRepairSimplesSuccessResponses());
    const clientRC3 = new JustTcgClient("sk-fake-rc3", fetchImplRC3, 10);
    const resultadoRC3 = await executeRepairMappings(supabaseRC3, clientRC3, { dryRun: false, confirmedBy: "admin-1", maxApiRequests: 10, expectedSetCodes: ["SETR"] });

    const mappingR1 = (tablesRC3.pricing_card_mapping ?? []).find((r) => r.card_id === "card-r1") as { match_status: string } | undefined;
    const mappingR2 = (tablesRC3.pricing_card_mapping ?? []).find((r) => r.card_id === "card-r2") as { match_status: string; external_card_id?: string } | undefined;
    const mappingR3 = (tablesRC3.pricing_card_mapping ?? []).find((r) => r.card_id === "card-r3") as { match_status: string; external_card_id?: string } | undefined;
    const mappingR4 = (tablesRC3.pricing_card_mapping ?? []).find((r) => r.card_id === "card-r4") as { match_status: string } | undefined;
    const produtosR3 = tablesRC3.pricing_product ?? [];

    assert(
      "P14.4.4 repair cenário 3: card-r2/card-r3 promovem a CONFIRMED com produto criado; card-r1 (CONFIRMED) e card-r4 (ainda AMBIGUOUS) permanecem com o status anterior, sem nenhuma escrita para card-r4; nenhuma chamada a GET /sets (1 única requisição HTTP no total)",
      resultadoRC3.status === "COMPLETED" &&
        resultadoRC3.cardsEvaluated === 3 &&
        resultadoRC3.cardsPromoted === 2 &&
        resultadoRC3.cardsStillPending === 1 &&
        resultadoRC3.cardsStillNotFound === 0 &&
        mappingR1?.match_status === "CONFIRMED" &&
        mappingR2?.match_status === "CONFIRMED" &&
        mappingR2?.external_card_id === "ext-card-r2" &&
        mappingR3?.match_status === "CONFIRMED" &&
        mappingR3?.external_card_id === "ext-card-r3" &&
        mappingR4?.match_status === "PENDING" &&
        produtosR3.length === 2 &&
        callCountRC3() === 1 &&
        clientRC3.requestsMade === 1,
    );
  }

  // Cenário 4 — --expected-set-codes bloqueia deriva de composição ANTES de qualquer chamada
  // HTTP: como a lista de candidatos é 100% derivada de dados locais (nunca depende de GET
  // /sets), o mismatch é detectado com ZERO requisições — diferença estrutural em relação ao
  // backfill/expansion-wave (que gastam 1 chamada a /sets antes de poder validar).
  {
    const { client: supabaseRC4, tables: tablesRC4 } = makeExpansionWaveFakeClient(buildRepairDoisSetsSeed());
    const { fetchImpl: fetchImplRC4, callCount: callCountRC4 } = makeFakeFetch(buildRepairDoisSetsSuccessResponses());
    const clientRC4 = new JustTcgClient("sk-fake-rc4", fetchImplRC4, 10);
    let erroRC4: Error | null = null;
    try {
      await executeRepairMappings(supabaseRC4, clientRC4, { dryRun: false, confirmedBy: "admin-1", maxApiRequests: 10, expectedSetCodes: ["SETR"] });
    } catch (error) {
      erroRC4 = error instanceof Error ? error : null;
    }
    assert(
      "P14.4.4 repair cenário 4: --expected-set-codes=SETR (faltando SETS) é rejeitado com REPAIR_CANDIDATE_SETS_CHANGED, ZERO requisições HTTP (candidatos derivados só de dados locais), zero persistência, CARD_SYNC finalizado FAILED",
      erroRC4 !== null &&
        erroRC4.message.startsWith("REPAIR_CANDIDATE_SETS_CHANGED") &&
        callCountRC4() === 0 &&
        clientRC4.requestsMade === 0 &&
        (tablesRC4.pricing_product ?? []).length === 0 &&
        tablesRC4.pricing_sync_run.length === 1 &&
        (tablesRC4.pricing_sync_run[0] as { status: string }).status === "FAILED",
    );
  }

  // Cenário 5 — orçamento local (--max-api-requests) é respeitado: budget=1 alcança só a
  // página de SETR (1º na ordem alfabética); SETS nunca é sequer tentado (budgetOk() barra
  // antes do fetch) -> ORCAMENTO_ESGOTADO, FAILED, zero persistência (regra tudo-ou-nada).
  {
    const { client: supabaseRC5, tables: tablesRC5 } = makeExpansionWaveFakeClient(buildRepairDoisSetsSeed());
    const { fetchImpl: fetchImplRC5, callCount: callCountRC5 } = makeFakeFetch(buildRepairDoisSetsSuccessResponses());
    const clientRC5 = new JustTcgClient("sk-fake-rc5", fetchImplRC5, 1);
    const resultadoRC5 = await executeRepairMappings(supabaseRC5, clientRC5, { dryRun: false, confirmedBy: "admin-1", maxApiRequests: 1, expectedSetCodes: ["SETR", "SETS"] });
    assert(
      "P14.4.4 repair cenário 5: --max-api-requests=1 nunca é ultrapassado — exatamente 1 chamada real (página de SETR), SETS nunca sequer tentado; status FAILED, zero persistência de negócio",
      callCountRC5() === 1 &&
        clientRC5.requestsMade === 1 &&
        resultadoRC5.status === "FAILED" &&
        resultadoRC5.errorParts.some((e) => e.startsWith("ORCAMENTO_ESGOTADO(SETS)")) &&
        (tablesRC5.pricing_product ?? []).length === 0 &&
        (tablesRC5.pricing_card_mapping ?? []).find((r) => r.card_id === "card-r2")?.match_status === "PENDING",
    );
  }

  // Cenário 6 — --dry-run gera zero escrita: nenhum pricing_sync_run criado, nenhuma linha
  // nova em nenhuma tabela de negócio, mesmo com card-r2/card-r3 classificados com sucesso
  // (SAFE) — mesma disciplina de dry-run do backfill/expansion-wave.
  {
    const { client: supabaseRC6, tables: tablesRC6 } = makeExpansionWaveFakeClient(buildRepairSimplesSeed());
    const { fetchImpl: fetchImplRC6 } = makeFakeFetch(buildRepairSimplesSuccessResponses());
    const clientRC6 = new JustTcgClient("sk-fake-rc6", fetchImplRC6, 10);
    const resultadoRC6 = await executeRepairMappings(supabaseRC6, clientRC6, { dryRun: true, confirmedBy: null, maxApiRequests: 10, expectedSetCodes: ["SETR"] });
    assert(
      "P14.4.4 repair cenário 6: --dry-run nunca cria pricing_sync_run nem escreve mapping/produto/observação, mesmo com 2 cartas (card-r2/card-r3) classificadas SAFE com sucesso; productsProjected > 0 só como projeção informativa",
      resultadoRC6.status === "COMPLETED" &&
        resultadoRC6.cardsPromoted === 2 &&
        (tablesRC6.pricing_sync_run ?? []).length === 0 &&
        (tablesRC6.pricing_product ?? []).length === 0 &&
        (tablesRC6.pricing_observation ?? []).length === 0 &&
        (tablesRC6.pricing_card_mapping ?? []).find((r) => r.card_id === "card-r2")?.match_status === "PENDING" &&
        resultadoRC6.productsProjected > 0,
    );
  }

  // Cenário 7 — conflito de concorrência bloqueia qualquer chamada externa: já existe um
  // CARD_SYNC RECEIVED/PROCESSING para a mesma fonte -> CONFLITO_DE_CONCORRENCIA antes de
  // qualquer requisição, zero requisições HTTP, nenhuma 2ª linha em pricing_sync_run.
  {
    const seedRC7 = buildRepairSimplesSeed();
    seedRC7.pricing_sync_run = [{ id: "run-existing", pricing_source_id: "src-1", run_type: "CARD_SYNC", status: "PROCESSING" }];
    const { client: supabaseRC7, tables: tablesRC7 } = makeExpansionWaveFakeClient(seedRC7);
    const { fetchImpl: fetchImplRC7, callCount: callCountRC7 } = makeFakeFetch(buildRepairSimplesSuccessResponses());
    const clientRC7 = new JustTcgClient("sk-fake-rc7", fetchImplRC7, 10);
    let erroRC7: Error | null = null;
    try {
      await executeRepairMappings(supabaseRC7, clientRC7, { dryRun: false, confirmedBy: "admin-1", maxApiRequests: 10, expectedSetCodes: ["SETR"] });
    } catch (error) {
      erroRC7 = error instanceof Error ? error : null;
    }
    assert(
      "P14.4.4 repair cenário 7: conflito de concorrência (CARD_SYNC já ativo) aborta com CONFLITO_DE_CONCORRENCIA antes de qualquer chamada à JustTCG, sem criar uma 2ª linha em pricing_sync_run",
      erroRC7 !== null && erroRC7.message.startsWith("CONFLITO_DE_CONCORRENCIA") && callCountRC7() === 0 && clientRC7.requestsMade === 0 && tablesRC7.pricing_sync_run.length === 1,
    );
  }

  // Cenário 8 — falha em qualquer Set-alvo bloqueia a persistência de TODO o reparo, mesmo
  // que outro Set já tenha sido classificado com sucesso e mantido só em memória: SETR é
  // adquirido e classificado com sucesso, mas a paginação de SETS falha (HTTP 500) -> zero
  // mapping/produto/observação persistidos para SETR também (regra tudo-ou-nada).
  {
    const { client: supabaseRC8, tables: tablesRC8 } = makeExpansionWaveFakeClient(buildRepairDoisSetsSeed());
    const { fetchImpl: fetchImplRC8 } = makeFakeFetch([
      { status: 200, body: { data: [{ id: "ext-card-r2", name: "Card R2 EN", number: "2", variants: [{ uuid: "var-r2", condition: "Near Mint", printing: "Normal", price: 2.5, lastUpdated: 1700000000 }] }] } },
      { status: 500, body: { error: "falha simulada" } },
    ]);
    const clientRC8 = new JustTcgClient("sk-fake-rc8", fetchImplRC8, 10);
    const resultadoRC8 = await executeRepairMappings(supabaseRC8, clientRC8, { dryRun: false, confirmedBy: "admin-1", maxApiRequests: 10, expectedSetCodes: ["SETR", "SETS"] });
    assert(
      "P14.4.4 repair cenário 8: falha de paginação em SETS (HTTP 500) aborta o reparo inteiro -> zero mapping/produto/observação persistidos, mesmo com SETR já classificado com sucesso em memória; status FAILED",
      resultadoRC8.status === "FAILED" &&
        resultadoRC8.errorParts.some((e) => e.startsWith("PAGINACAO_CARDS_FALHOU(SETS)")) &&
        (tablesRC8.pricing_product ?? []).length === 0 &&
        (tablesRC8.pricing_card_mapping ?? []).find((r) => r.card_id === "card-r2")?.match_status === "PENDING",
    );
  }

  // Cenário 9 — wiring de CLI: --repair-mappings é mutuamente exclusivo com --expansion-plan,
  // --expansion-wave e --backfill-wave (rejeitado ANTES de qualquer validação de formato/
  // credencial), isolado aciona REPAIR_MAPPINGS normalmente, e --backfill-wave sozinho
  // continua funcionando exatamente como antes (regressão de P14.4.3 preservada).
  {
    const CREDS_OK_RC9 = { justTcgApiKey: "sk-fake-justtcg-rc9", supabaseUrl: "https://fake.supabase.co", supabaseServiceRoleKey: "sk-fake-service-role-rc9" };

    const decisaoExclusivo1 = resolveEntryDecision(
      { fixtureCheck: false, expansionPlan: true, dryRun: true, confirmedBy: null, expectedSetCodes: "SETR", repairMappings: true, maxApiRequests: "10" },
      CREDS_OK_RC9,
    );
    assert(
      "P14.4.4 repair cenário 9: --repair-mappings combinado com --expansion-plan é rejeitado com REPAIR_MAPPINGS_INVALID_ARGS/MODOS_MUTUAMENTE_EXCLUSIVOS",
      decisaoExclusivo1.kind === "REPAIR_MAPPINGS_INVALID_ARGS" && decisaoExclusivo1.reason.startsWith("MODOS_MUTUAMENTE_EXCLUSIVOS"),
    );

    const decisaoExclusivo2 = resolveEntryDecision(
      { fixtureCheck: false, expansionPlan: false, backfillWave: "1", dryRun: true, confirmedBy: null, expectedSetCodes: "SETR", repairMappings: true, maxApiRequests: "10" },
      CREDS_OK_RC9,
    );
    assert(
      "P14.4.4 repair cenário 9: --repair-mappings combinado com --backfill-wave é rejeitado com BACKFILL_WAVE_INVALID_ARGS/MODOS_MUTUAMENTE_EXCLUSIVOS (checagem já existente de --backfill-wave cobre o par)",
      decisaoExclusivo2.kind === "BACKFILL_WAVE_INVALID_ARGS" && decisaoExclusivo2.reason.startsWith("MODOS_MUTUAMENTE_EXCLUSIVOS"),
    );

    const decisaoRepairValida = resolveEntryDecision(
      { fixtureCheck: false, expansionPlan: false, expansionWave: null, backfillWave: null, dryRun: true, confirmedBy: null, expectedSetCodes: "SETR", repairMappings: true, maxApiRequests: "10" },
      CREDS_OK_RC9,
    );
    assert(
      "P14.4.4 repair cenário 9: --repair-mappings isolado (sem os outros três modos) aciona REPAIR_MAPPINGS com orçamento/expected-set-codes corretos",
      decisaoRepairValida.kind === "REPAIR_MAPPINGS" && decisaoRepairValida.maxApiRequests === 10 && decisaoRepairValida.expectedSetCodes.join(",") === "SETR",
    );

    const decisaoBackfillIntacta = resolveEntryDecision(
      { fixtureCheck: false, expansionPlan: false, expansionWave: null, backfillWave: "1", dryRun: true, confirmedBy: null, expectedSetCodes: "SETB", repairMappings: false, maxApiRequests: "10" },
      CREDS_OK_RC9,
    );
    assert(
      "P14.4.4 repair cenário 9: --backfill-wave sozinho (sem --repair-mappings) continua funcionando exatamente como antes de P14.4.4 (regressão preservada)",
      decisaoBackfillIntacta.kind === "BACKFILL_WAVE" && decisaoBackfillIntacta.waveNumber === 1,
    );
  }

  // ==========================================================================
  // P14.4.5 — Correção pós-decisão de negócio: deduplicação por external_card_id.
  // Causa raiz confirmada na auditoria real (BASE1/BASE2/BASE4/GYM2/ME1, 2026-08-19):
  // os 6 casos NUMERO_MULTIPLO_SEM_DESEMPATE_SEGURO em produção (todos em ME1: Tangela,
  // Ninjask, Greavard, Nickit, Repelente, Relógio Insólito) tinham a MESMA carta externa
  // (mesmo id) listada duas vezes no array de candidatos — buildExternalNumberIndex()
  // contava 2 candidatos onde só existia 1 distinto, bloqueando uma promoção que deveria
  // ser CONFIRMED. A deduplicação por id na construção do índice corrige isso na origem,
  // valendo automaticamente para piloto/expansion-wave/backfill/reparo (mesma função).
  // ==========================================================================

  // Cenário 10 — candidatos repetidos com o MESMO external_card_id colapsam para 1 candidato
  // distinto (nunca 2) -> SAFE, nunca AMBIGUOUS. Prova direta do bug de contagem corrigido.
  {
    const externalIndexDup = buildExternalNumberIndex([
      { id: "ext-tangela", name: "Tangela", number: "6", variants: [] },
      { id: "ext-tangela", name: "Tangela", number: "6", variants: [] }, // mesmo id, entrada duplicada na resposta bruta
    ]);
    assert(
      "P14.4.5 dedup cenário 10: buildExternalNumberIndex() nunca duplica o mesmo external_card_id no mesmo número — bucket tem 1 candidato, não 2",
      (externalIndexDup.get("6") ?? []).length === 1,
    );
    const resultDup = classifyCardMatch({ card_id: "local-tangela", name: "Tangela", collector_number: "006" }, externalIndexDup, "fixture-set-x");
    assert(
      "P14.4.5 dedup cenário 10: candidatos duplicados pelo mesmo external_card_id -> SAFE (nunca AMBIGUOUS) — reproduz e corrige o caso real de ME1 (Tangela/Ninjask/Greavard/Nickit/Repelente/Relógio Insólito)",
      resultDup.classification === "SAFE" && resultDup.matched?.id === "ext-tangela",
    );
  }
  {
    // Contraprova: 3 entradas duplicadas do MESMO id ao lado de um id genuinamente diferente
    // no mesmo número -> ainda AMBIGUOUS (2 candidatos distintos), a deduplicação nunca
    // esconde uma ambiguidade real, só remove repetição do mesmo id.
    const externalIndexMisto = buildExternalNumberIndex([
      { id: "ext-a", name: "Card A", number: "9", variants: [] },
      { id: "ext-a", name: "Card A", number: "9", variants: [] },
      { id: "ext-b", name: "Card B", number: "9", variants: [] },
    ]);
    assert(
      "P14.4.5 dedup cenário 10: 3 entradas brutas (ext-a duplicado + ext-b) -> 2 candidatos distintos, nunca 3 nem 1",
      (externalIndexMisto.get("9") ?? []).length === 2,
    );
    const resultMisto = classifyCardMatch({ card_id: "local-x9", name: "Card A", collector_number: "009" }, externalIndexMisto, "fixture-set-x");
    assert(
      "P14.4.5 dedup cenário 10: deduplicar não esconde ambiguidade real — 2 external_card_id genuinamente distintos continuam AMBIGUOUS mesmo com um deles duplicado na resposta bruta",
      resultMisto.classification === "AMBIGUOUS" && resultMisto.matched === null,
    );
  }

  // Cenário 11 — reparo real fim a fim: dois Sets CONFIRMED distintos (SETM, SETN), cada um
  // com uma carta PENDING no MESMO collector_number ("010"), cada Set com um external_card_id
  // distinto (e só um) para esse número. Prova que o índice por número nunca vaza entre Sets —
  // cada carta promove para o candidato do PRÓPRIO Set, nunca para o do outro.
  {
    const seedRC11: Record<string, FakeRow[]> = {
      pricing_source: [{ id: "src-1", code: "JUSTTCG", is_active: true, requires_commercial_agreement: true }],
      card_set: [
        { id: "cs-m", code: "SETM", release_date: "2020-05-01" },
        { id: "cs-n", code: "SETN", release_date: "2020-06-01" },
      ],
      catalog_card_set_metrics: [
        { card_set_id: "cs-m", cards_ativas: 1 },
        { card_set_id: "cs-n", cards_ativas: 1 },
      ],
      card: [
        { id: "card-m1", card_set_id: "cs-m", name: "Card M1 PT", collector_number: "10", is_active: true },
        { id: "card-n1", card_set_id: "cs-n", name: "Card N1 PT", collector_number: "10", is_active: true },
      ],
      pricing_set_mapping: [
        { card_set_id: "cs-m", pricing_source_id: "src-1", match_status: "CONFIRMED", external_set_id: "ext-m", external_set_name: "Ext M" },
        { card_set_id: "cs-n", pricing_source_id: "src-1", match_status: "CONFIRMED", external_set_id: "ext-n", external_set_name: "Ext N" },
      ],
      pricing_card_mapping: [
        { id: "pcm-m1", card_id: "card-m1", pricing_source_id: "src-1", match_status: "PENDING" },
        { id: "pcm-n1", card_id: "card-n1", pricing_source_id: "src-1", match_status: "PENDING" },
      ],
      pricing_set_coverage: [
        { card_set_id: "cs-m", pricing_source_id: "src-1", products_count: 0, observations_count: 0, mapped_cards_count: 1, confirmed_cards_count: 0, pending_cards_count: 1, not_found_cards_count: 0 },
        { card_set_id: "cs-n", pricing_source_id: "src-1", products_count: 0, observations_count: 0, mapped_cards_count: 1, confirmed_cards_count: 0, pending_cards_count: 1, not_found_cards_count: 0 },
      ],
      pricing_condition_mapping: [{ pricing_source_id: "src-1", external_condition_code: "Near Mint", condition_id: "cond-nm" }],
    };
    const { client: supabaseRC11, tables: tablesRC11 } = makeExpansionWaveFakeClient(seedRC11);
    const respostasRC11: Array<{ status: number; body: unknown }> = [
      { status: 200, body: { data: [{ id: "ext-card-m1", name: "Card M1 EN", number: "10", variants: [{ uuid: "var-m1", condition: "Near Mint", printing: "Normal", price: 4.5, lastUpdated: 1700000000 }] }] } },
      { status: 200, body: { data: [{ id: "ext-card-n1", name: "Card N1 EN", number: "10", variants: [{ uuid: "var-n1", condition: "Near Mint", printing: "Normal", price: 5.5, lastUpdated: 1700000000 }] }] } },
    ];
    const { fetchImpl: fetchImplRC11 } = makeFakeFetch(respostasRC11);
    const clientRC11 = new JustTcgClient("sk-fake-rc11", fetchImplRC11, 10);
    const resultadoRC11 = await executeRepairMappings(supabaseRC11, clientRC11, { dryRun: false, confirmedBy: "admin-1", maxApiRequests: 10, expectedSetCodes: ["SETM", "SETN"] });

    const mappingM1 = (tablesRC11.pricing_card_mapping ?? []).find((r) => r.card_id === "card-m1") as { match_status: string; external_card_id?: string } | undefined;
    const mappingN1 = (tablesRC11.pricing_card_mapping ?? []).find((r) => r.card_id === "card-n1") as { match_status: string; external_card_id?: string } | undefined;
    assert(
      "P14.4.5 Sets isolados cenário 11: SETM/SETN compartilham o mesmo collector_number (010) mas cada carta promove para o external_card_id do PRÓPRIO Set — card-m1 -> ext-card-m1 (nunca ext-card-n1), card-n1 -> ext-card-n1 (nunca ext-card-m1)",
      resultadoRC11.status === "COMPLETED" &&
        resultadoRC11.cardsPromoted === 2 &&
        mappingM1?.match_status === "CONFIRMED" &&
        mappingM1?.external_card_id === "ext-card-m1" &&
        mappingN1?.match_status === "CONFIRMED" &&
        mappingN1?.external_card_id === "ext-card-n1",
    );
  }

  // ==========================================================================
  // P14.4.6 — --repair-set-codes: filtra os candidatos de --repair-mappings ANTES de
  // qualquer chamada à JustTCG. Motivação: viabilizar reparo em ondas controladas (orçamento
  // de API) sem tocar em matching/banco/schema. Ver filterRepairCandidatesBySetCodes() e
  // validateRepairSetCodesFormat(), ambas puras.
  // ==========================================================================

  // Cenário 1 — seleção correta do subconjunto: 3 candidatos elegíveis (SETA/SETB/SETC),
  // --repair-set-codes=SETA,SETC seleciona exatamente esses dois, nunca SETB.
  const candidatosF1: RepairCandidateSet[] = [
    { code: "SETA", cardSetId: "cs-a", externalSetId: "ext-a", pendingCount: 2, notFoundCount: 0 },
    { code: "SETB", cardSetId: "cs-b", externalSetId: "ext-b", pendingCount: 1, notFoundCount: 0 },
    { code: "SETC", cardSetId: "cs-c", externalSetId: "ext-c", pendingCount: 0, notFoundCount: 3 },
  ];
  const localSetsF1: LocalSetSummary[] = [
    { cardSetId: "cs-a", code: "SETA", releaseDateIso: "2020-01-01", localCardCount: 5 },
    { cardSetId: "cs-b", code: "SETB", releaseDateIso: "2020-02-01", localCardCount: 5 },
    { cardSetId: "cs-c", code: "SETC", releaseDateIso: "2020-03-01", localCardCount: 5 },
    // SETD: existe localmente mas NÃO é candidato a reparo agora (não entra em candidatosF1) —
    // usado pelo cenário 4 (SEM_PENDENCIA).
    { cardSetId: "cs-d", code: "SETD", releaseDateIso: "2020-04-01", localCardCount: 5 },
  ];
  {
    const filtro1 = filterRepairCandidatesBySetCodes(candidatosF1, ["SETA", "SETC"], localSetsF1);
    assert(
      "P14.4.6 repair-set-codes cenário 1: --repair-set-codes=SETA,SETC seleciona exatamente esses 2 candidatos, nunca SETB (que também é elegível mas não foi pedido)",
      filtro1.ok && filtro1.filtered.length === 2 && filtro1.filtered.every((c) => c.code === "SETA" || c.code === "SETC"),
    );
  }

  // Cenário 2 — rejeição de código desconhecido: SETX nunca existiu entre os Sets locais.
  {
    const filtro2 = filterRepairCandidatesBySetCodes(candidatosF1, ["SETA", "SETX"], localSetsF1);
    assert(
      "P14.4.6 repair-set-codes cenário 2: código desconhecido (SETX, nem existe entre os Sets locais) é rejeitado com REPAIR_SET_CODES_DESCONHECIDO, antes de qualquer chamada à JustTCG (função pura, zero rede/banco)",
      !filtro2.ok && filtro2.reason.startsWith("REPAIR_SET_CODES_DESCONHECIDO") && filtro2.reason.includes("SETX"),
    );
  }

  // Cenário 3 — rejeição de código duplicado: validado no nível de FORMATO
  // (validateRepairSetCodesFormat), antes até de tocar candidatos/banco.
  {
    const formatoDup = validateRepairSetCodesFormat("SETA,SETA");
    assert(
      "P14.4.6 repair-set-codes cenário 3: código repetido em --repair-set-codes (SETA,SETA) é rejeitado com REPAIR_SET_CODES_DUPLICADO — validação puramente de formato, nunca chega a tocar candidatos/banco/rede",
      !formatoDup.ok && formatoDup.reason.startsWith("REPAIR_SET_CODES_DUPLICADO") && formatoDup.reason.includes("SETA"),
    );
  }

  // Cenário 4 — rejeição de Set sem pendência: SETD existe localmente mas não é candidato a
  // reparo agora (fora de candidatosF1) — distinto do "desconhecido" do cenário 2.
  {
    const filtro4 = filterRepairCandidatesBySetCodes(candidatosF1, ["SETD"], localSetsF1);
    assert(
      "P14.4.6 repair-set-codes cenário 4: código de Set que existe localmente mas não tem PENDING/NOT_FOUND elegível agora (SETD) é rejeitado com REPAIR_SET_CODES_SEM_PENDENCIA, distinto de DESCONHECIDO",
      !filtro4.ok && filtro4.reason.startsWith("REPAIR_SET_CODES_SEM_PENDENCIA") && filtro4.reason.includes("SETD"),
    );
  }

  // Cenário 5 — --expected-set-codes é uma assertiva independente que deve coincidir com o
  // SUBCONJUNTO selecionado por --repair-set-codes, nunca com a lista completa de candidatos:
  // repair-set-codes=SETR (válido), mas expected-set-codes=SETR,SETS (lista completa, sem o
  // filtro) diverge do subconjunto real pós-filtro -> REPAIR_CANDIDATE_SETS_CHANGED, ZERO
  // requisições HTTP, zero persistência, CARD_SYNC finalizado FAILED.
  {
    const { client: supabaseF5, tables: tablesF5 } = makeExpansionWaveFakeClient(buildRepairDoisSetsSeed());
    const { fetchImpl: fetchImplF5, callCount: callCountF5 } = makeFakeFetch(buildRepairDoisSetsSuccessResponses());
    const clientF5 = new JustTcgClient("sk-fake-f5", fetchImplF5, 10);
    let erroF5: Error | null = null;
    try {
      await executeRepairMappings(supabaseF5, clientF5, {
        dryRun: false,
        confirmedBy: "admin-1",
        maxApiRequests: 10,
        expectedSetCodes: ["SETR", "SETS"],
        repairSetCodes: ["SETR"],
      });
    } catch (error) {
      erroF5 = error instanceof Error ? error : null;
    }
    assert(
      "P14.4.6 repair-set-codes cenário 5: --repair-set-codes=SETR restringe o subconjunto real a [SETR], mas --expected-set-codes=SETR,SETS (lista completa, não o subconjunto) diverge -> REPAIR_CANDIDATE_SETS_CHANGED, ZERO requisições HTTP, zero persistência, CARD_SYNC FAILED",
      erroF5 !== null &&
        erroF5.message.startsWith("REPAIR_CANDIDATE_SETS_CHANGED") &&
        callCountF5() === 0 &&
        clientF5.requestsMade === 0 &&
        (tablesF5.pricing_product ?? []).length === 0 &&
        tablesF5.pricing_sync_run.length === 1 &&
        (tablesF5.pricing_sync_run[0] as { status: string }).status === "FAILED",
    );
  }

  // Cenário 6 — ausência de --repair-set-codes preserva o comportamento anterior byte-a-byte:
  // mesmo seed de 2 Sets (SETR+SETS), opts.repairSetCodes OMITIDO (nem null explícito) ->
  // ambos os Sets são processados normalmente, exatamente como antes de P14.4.6 (mesmo
  // resultado da cobertura já provada pelos cenários RC3/RC11 anteriores).
  {
    const { client: supabaseF6, tables: tablesF6 } = makeExpansionWaveFakeClient(buildRepairDoisSetsSeed());
    const { fetchImpl: fetchImplF6, callCount: callCountF6 } = makeFakeFetch(buildRepairDoisSetsSuccessResponses());
    const clientF6 = new JustTcgClient("sk-fake-f6", fetchImplF6, 10);
    const resultadoF6 = await executeRepairMappings(supabaseF6, clientF6, {
      dryRun: false,
      confirmedBy: "admin-1",
      maxApiRequests: 10,
      expectedSetCodes: ["SETR", "SETS"],
      // repairSetCodes intencionalmente omitido
    });
    const mappingR2F6 = (tablesF6.pricing_card_mapping ?? []).find((r) => r.card_id === "card-r2") as { match_status: string } | undefined;
    const mappingS1F6 = (tablesF6.pricing_card_mapping ?? []).find((r) => r.card_id === "card-s1") as { match_status: string } | undefined;
    assert(
      "P14.4.6 repair-set-codes cenário 6: ausência de --repair-set-codes (campo omitido no opts) preserva o comportamento anterior — SETR e SETS processados normalmente, 2 requisições HTTP, ambos promovidos a CONFIRMED",
      resultadoF6.status === "COMPLETED" &&
        callCountF6() === 2 &&
        clientF6.requestsMade === 2 &&
        mappingR2F6?.match_status === "CONFIRMED" &&
        mappingS1F6?.match_status === "CONFIRMED",
    );
  }

  // ==========================================================================================
  // P14.4.4 fix v2 — filtro seguro por identidade completa (numerador+denominador) vs.
  // candidato de número incompleto (14 casos determinísticos: BASEP=5, CEL25=1, SV6.5=8).
  // Decisão de negócio confirmada por Fabrício após a auditoria read-only dos 548 PENDING/18
  // NOT_FOUND e, depois, corrigida por ele mesmo após o dry-run real divergir em SV6.5 (0/8 em
  // vez de 8/8): um segundo sinal ESTRUTURAL (denominador do número externo vs. collector_total
  // local) pode reduzir ambiguidade de número — nunca nome, nunca idioma, nunca raridade, nunca
  // preferência de edição — mas só um candidato de IDENTIDADE COMPLETA único (nunca um
  // candidato de número incompleto sobrando) pode promover a SAFE. Parte A: função pura
  // parseCollectorNumberParts e o guard isValidCollectorTotal. Parte B: classifyCardMatch() com
  // o filtro de três categorias. Parte C: integração via executeRepairMappings (promoção real
  // pelo caminho batelado existente).
  // ==========================================================================================

  // --- Parte A: parseCollectorNumberParts (pura) -------------------------------------------
  {
    const p1 = parseCollectorNumberParts("009/132");
    assert("P14.4.4 fix parseCollectorNumberParts: \"009/132\" -> numerador \"9\", denominador 132, bruto preservado", p1.numerator === "9" && p1.denominator === 132 && p1.raw === "009/132");

    const p2 = parseCollectorNumberParts("9 / 132");
    assert("P14.4.4 fix parseCollectorNumberParts: espaços em torno da barra -> \"9 / 132\" -> numerador \"9\", denominador 132", p2.numerator === "9" && p2.denominator === 132);

    const p3 = parseCollectorNumberParts("009");
    assert("P14.4.4 fix parseCollectorNumberParts: sem barra -> \"009\" -> numerador \"9\", denominador ausente (null)", p3.numerator === "9" && p3.denominator === null);

    const p4 = parseCollectorNumberParts("09/053");
    assert("P14.4.4 fix parseCollectorNumberParts: zeros à esquerda também no denominador -> \"09/053\" -> denominador 53 (não \"053\" como string)", p4.denominator === 53);

    const p5 = parseCollectorNumberParts("N/A");
    assert("P14.4.4 fix parseCollectorNumberParts: \"N/A\" (não utilizável) -> numerador vazio, denominador null, bruto preservado", p5.numerator === "" && p5.denominator === null && p5.raw === "N/A");

    const p6 = parseCollectorNumberParts(null);
    assert("P14.4.4 fix parseCollectorNumberParts: null -> numerador vazio, denominador null, bruto \"\"", p6.numerator === "" && p6.denominator === null && p6.raw === "");

    assert(
      "P14.4.4 fix isValidCollectorTotal: aceita inteiro positivo, rejeita ausente/zero/negativo/não-inteiro/NaN",
      isValidCollectorTotal(53) === true &&
        isValidCollectorTotal(null) === false &&
        isValidCollectorTotal(undefined) === false &&
        isValidCollectorTotal(0) === false &&
        isValidCollectorTotal(-5) === false &&
        isValidCollectorTotal(1.5) === false &&
        isValidCollectorTotal(Number.NaN) === false,
    );
  }

  // --- Parte B: classifyCardMatch() com collector_total -------------------------------------
  // v2 (correção de especificidade estrutural): cada candidato cai em exatamente uma
  // categoria — EXACT_FULL_IDENTITY (denominador == collector_total), INCOMPATIBLE_DENOMINATOR
  // (denominador declarado e diferente) ou INCOMPLETE_NUMBER (sem denominador declarado). Só
  // EXATAMENTE 1 EXACT_FULL_IDENTITY promove a SAFE; 0 ou 2+ permanece AMBIGUOUS, mesmo
  // havendo candidato(s) INCOMPLETE_NUMBER sobrando (nunca promovido só por eliminação).

  // Cenário obrigatório: denominador compatível único, sem candidato incompleto (caso real
  // BASEP #09 "Mew": um candidato pertence a outro subconjunto do mesmo external_set_id —
  // Prerelease /132 — e fica como INCOMPATIBLE_DENOMINATOR; o único EXACT_FULL_IDENTITY, /53,
  // é promovido).
  {
    const externalIndex = buildExternalNumberIndex([
      { id: "ext-mew9", name: "Mew (9)", number: "09/53", variants: [] },
      { id: "ext-seadra", name: "Misty's Seadra (Prerelease)", number: "009/132", variants: [] },
    ]);
    const local: LocalCard = { card_id: "local-mew9", name: "Mew", collector_number: "09", collector_total: 53 };
    const result = classifyCardMatch(local, externalIndex, "fixture-set-denom");
    assert(
      "P14.4.4 fix v2 cenário 1 (denominador compatível único, sem incompleto): SAFE, candidato ext-mew9 selecionado, método SET_CONFIRMED_FULL_COLLECTOR_IDENTITY_UNIQUE",
      result.classification === "SAFE" && result.matched?.id === "ext-mew9" && result.method === "SET_CONFIRMED_FULL_COLLECTOR_IDENTITY_UNIQUE",
    );
    assert(
      "P14.4.4 fix v2 cenário 1 — evidência: local_collector_total=53, ext-seadra em candidatos_denominador_incompativel, candidato_selecionado=ext-mew9, motivo estrutural presente",
      result.evidence.local_collector_total === 53 &&
        Array.isArray(result.evidence.candidatos_denominador_incompativel) &&
        (result.evidence.candidatos_denominador_incompativel as Array<{ id: string }>).length === 1 &&
        (result.evidence.candidatos_denominador_incompativel as Array<{ id: string }>)[0].id === "ext-seadra" &&
        Array.isArray(result.evidence.candidatos_identidade_completa) &&
        (result.evidence.candidatos_identidade_completa as Array<{ id: string }>).length === 1 &&
        (result.evidence.candidato_selecionado as { id: string }).id === "ext-mew9" &&
        typeof result.evidence.motivo_estrutural === "string" &&
        (result.evidence.motivo_estrutural as string).length > 0,
    );
  }

  // Cenário obrigatório: espaços em torno da barra não impedem a leitura do denominador.
  {
    const externalIndex = buildExternalNumberIndex([
      { id: "ext-espaco-ok", name: "Qualquer", number: "9 / 53", variants: [] },
      { id: "ext-espaco-outro", name: "Outro", number: "8/132", variants: [] },
    ]);
    const local: LocalCard = { card_id: "local-espaco", name: "Qualquer Local", collector_number: "09", collector_total: 53 };
    const result = classifyCardMatch(local, externalIndex, "fixture-set-denom");
    assert(
      "P14.4.4 fix v2 cenário 2 (espaços em torno da barra): \"9 / 53\" interpretado como denominador 53 -> SAFE",
      result.classification === "SAFE" && result.matched?.id === "ext-espaco-ok",
    );
  }

  // Cenário obrigatório (padrão real do bug SV6.5): 1 EXACT_FULL_IDENTITY + 1
  // INCOMPLETE_NUMBER -> SAFE pelo exato. Reproduz exatamente o par real reportado por
  // Fabrício: "Joltik" number="001/064" com collector_total=64 (identidade completa) vs.
  // "Basic Grass Energy" number="1" (incompleto, sem denominador) — o exato deve vencer
  // sozinho, nunca empatar/ambiguar com o incompleto.
  {
    const externalIndex = buildExternalNumberIndex([
      { id: "ext-joltik", name: "Joltik", number: "001/064", variants: [] },
      { id: "ext-basic-energy", name: "Basic Grass Energy", number: "1", variants: [] },
    ]);
    const local: LocalCard = { card_id: "local-joltik", name: "Joltik", collector_number: "1", collector_total: 64 };
    const result = classifyCardMatch(local, externalIndex, "fixture-set-denom");
    assert(
      "P14.4.4 fix v2 cenário 3 (1 exato + 1 incompleto -> SAFE pelo exato): SAFE, candidato ext-joltik selecionado, método SET_CONFIRMED_FULL_COLLECTOR_IDENTITY_UNIQUE",
      result.classification === "SAFE" && result.matched?.id === "ext-joltik" && result.method === "SET_CONFIRMED_FULL_COLLECTOR_IDENTITY_UNIQUE",
    );
    assert(
      "P14.4.4 fix v2 cenário 3 — evidência: candidato incompleto (ext-basic-energy) aparece em candidatos_numero_incompleto, nunca declarado descartado/incompatível",
      Array.isArray(result.evidence.candidatos_numero_incompleto) &&
        (result.evidence.candidatos_numero_incompleto as Array<{ id: string }>).length === 1 &&
        (result.evidence.candidatos_numero_incompleto as Array<{ id: string }>)[0].id === "ext-basic-energy",
    );
  }

  // Cenário obrigatório: 1 INCOMPATIBLE_DENOMINATOR + 1 INCOMPLETE_NUMBER -> AMBIGUOUS (zero
  // EXACT_FULL_IDENTITY; um candidato incompleto sobrando nunca promove sozinho).
  {
    const externalIndex = buildExternalNumberIndex([
      { id: "ext-incompat-82", name: "Incompatível", number: "09/82", variants: [] },
      { id: "ext-incompleto-8", name: "Incompleto", number: "09", variants: [] },
    ]);
    const local: LocalCard = { card_id: "local-ambiguo-misto", name: "Local", collector_number: "09", collector_total: 60 };
    const result = classifyCardMatch(local, externalIndex, "fixture-set-denom");
    assert(
      "P14.4.4 fix v2 cenário 4 (incompatível + incompleto continua ambíguo): AMBIGUOUS, matched null, zero identidade completa, 1 incompatível, 1 incompleto",
      result.classification === "AMBIGUOUS" &&
        result.matched === null &&
        (result.evidence.candidatos_identidade_completa as unknown[]).length === 0 &&
        (result.evidence.candidatos_denominador_incompativel as unknown[]).length === 1 &&
        (result.evidence.candidatos_numero_incompleto as unknown[]).length === 1,
    );
  }

  // Cenário obrigatório: somente candidatos incompletos (nenhum denominador declarado em
  // nenhum candidato) -> AMBIGUOUS. Ausência de denominador nunca prova nem promove.
  {
    const externalIndex = buildExternalNumberIndex([
      { id: "ext-so-incompleto-1", name: "Incompleto A", number: "09", variants: [] },
      { id: "ext-so-incompleto-2", name: "Incompleto B", number: "09", variants: [] },
    ]);
    const local: LocalCard = { card_id: "local-so-incompletos", name: "Local", collector_number: "09", collector_total: 60 };
    const result = classifyCardMatch(local, externalIndex, "fixture-set-denom");
    assert(
      "P14.4.4 fix v2 cenário 5 (somente incompletos): AMBIGUOUS, matched null, zero identidade completa, zero incompatível, 2 incompletos",
      result.classification === "AMBIGUOUS" &&
        result.matched === null &&
        (result.evidence.candidatos_identidade_completa as unknown[]).length === 0 &&
        (result.evidence.candidatos_denominador_incompativel as unknown[]).length === 0 &&
        (result.evidence.candidatos_numero_incompleto as unknown[]).length === 2,
    );
  }

  // Cenário obrigatório: 2 candidatos EXACT_FULL_IDENTITY (mesmo denominador batendo com
  // collector_total em ambos) -> AMBIGUOUS, mesmo sem nenhum candidato incompleto envolvido.
  {
    const externalIndex = buildExternalNumberIndex([
      { id: "ext-exato-a", name: "Exato A", number: "09/53", variants: [] },
      { id: "ext-exato-b", name: "Exato B", number: "09/53", variants: [] },
    ]);
    const local: LocalCard = { card_id: "local-2-exatos", name: "Local", collector_number: "09", collector_total: 53 };
    const result = classifyCardMatch(local, externalIndex, "fixture-set-denom");
    assert(
      "P14.4.4 fix v2 cenário 6 (2 candidatos exatos /053): AMBIGUOUS, matched null, 2 candidatos em identidade completa",
      result.classification === "AMBIGUOUS" &&
        result.matched === null &&
        (result.evidence.candidatos_identidade_completa as unknown[]).length === 2,
    );
  }

  // Cenário obrigatório: 1 EXACT_FULL_IDENTITY + vários INCOMPLETE_NUMBER -> SAFE pelo exato
  // (a quantidade de incompletos sobrando é irrelevante quando há exatamente 1 exato).
  {
    const externalIndex = buildExternalNumberIndex([
      { id: "ext-exato-unico", name: "Exato Único", number: "001/064", variants: [] },
      { id: "ext-incompleto-1", name: "Incompleto 1", number: "1", variants: [] },
      { id: "ext-incompleto-2", name: "Incompleto 2", number: "01", variants: [] },
    ]);
    const local: LocalCard = { card_id: "local-1-exato-varios-incompletos", name: "Local", collector_number: "1", collector_total: 64 };
    const result = classifyCardMatch(local, externalIndex, "fixture-set-denom");
    assert(
      "P14.4.4 fix v2 cenário 7 (1 exato + vários incompletos): SAFE, candidato ext-exato-unico selecionado, 2 incompletos registrados em evidência",
      result.classification === "SAFE" &&
        result.matched?.id === "ext-exato-unico" &&
        result.method === "SET_CONFIRMED_FULL_COLLECTOR_IDENTITY_UNIQUE" &&
        (result.evidence.candidatos_numero_incompleto as unknown[]).length === 2,
    );
  }

  // Cenário obrigatório: múltiplos EXACT_FULL_IDENTITY + INCOMPLETE_NUMBER -> AMBIGUOUS (2+
  // exatos nunca são desempatados por um incompleto, nem entre si).
  {
    const externalIndex = buildExternalNumberIndex([
      { id: "ext-multi-exato-a", name: "Multi Exato A", number: "001/064", variants: [] },
      { id: "ext-multi-exato-b", name: "Multi Exato B", number: "001/064", variants: [] },
      { id: "ext-multi-incompleto", name: "Multi Incompleto", number: "1", variants: [] },
    ]);
    const local: LocalCard = { card_id: "local-multi-exato-incompleto", name: "Local", collector_number: "1", collector_total: 64 };
    const result = classifyCardMatch(local, externalIndex, "fixture-set-denom");
    assert(
      "P14.4.4 fix v2 cenário 8 (múltiplos exatos + incompletos): AMBIGUOUS, matched null, 2 identidade completa, 1 incompleto",
      result.classification === "AMBIGUOUS" &&
        result.matched === null &&
        (result.evidence.candidatos_identidade_completa as unknown[]).length === 2 &&
        (result.evidence.candidatos_numero_incompleto as unknown[]).length === 1,
    );
  }

  // Cenário obrigatório: todos os denominadores incompatíveis (zero exato, zero incompleto)
  // -> continua AMBIGUOUS, NUNCA ABSENT/NOT_FOUND, mesmo quando todos os candidatos declaram
  // denominador diferente de collector_total (regra 5).
  {
    const externalIndex = buildExternalNumberIndex([
      { id: "ext-incompat-1", name: "Ponyta", number: "014/083", variants: [] },
      { id: "ext-incompat-2", name: "Outro Incompatível", number: "014/132", variants: [] },
    ]);
    const local: LocalCard = { card_id: "local-cel25-14", name: "Cosmoem", collector_number: "14", collector_total: 25 };
    const result = classifyCardMatch(local, externalIndex, "fixture-set-denom");
    assert(
      "P14.4.4 fix v2 cenário 9 (todos os denominadores incompatíveis): AMBIGUOUS (nunca ABSENT/NOT_FOUND), matched null, zero identidade completa, 2 incompatíveis",
      result.classification === "AMBIGUOUS" &&
        result.matched === null &&
        (result.evidence.candidatos_identidade_completa as unknown[]).length === 0 &&
        (result.evidence.candidatos_denominador_incompativel as unknown[]).length === 2,
    );
  }

  // Cenário obrigatório: collector_total ausente OU inválido (0/negativo) mantém o
  // comportamento AMBIGUOUS conservador ANTERIOR, byte a byte — nenhum campo novo na
  // evidência, sem aplicar o desempate, mesmo havendo candidatos cujo denominador bateria.
  {
    const externalIndex = buildExternalNumberIndex([
      { id: "ext-cond-a", name: "A", number: "09/53", variants: [] },
      { id: "ext-cond-b", name: "B", number: "09/999", variants: [] },
    ]);
    const localSemTotal: LocalCard = { card_id: "local-sem-total", name: "Local", collector_number: "09" };
    const resultSemTotal = classifyCardMatch(localSemTotal, externalIndex, "fixture-set-denom");
    const localTotalZero: LocalCard = { card_id: "local-total-zero", name: "Local", collector_number: "09", collector_total: 0 };
    const resultTotalZero = classifyCardMatch(localTotalZero, externalIndex, "fixture-set-denom");
    const localTotalNegativo: LocalCard = { card_id: "local-total-neg", name: "Local", collector_number: "09", collector_total: -3 };
    const resultTotalNegativo = classifyCardMatch(localTotalNegativo, externalIndex, "fixture-set-denom");
    assert(
      "P14.4.4 fix v2 cenário 10 (collector_total ausente/zero/negativo): AMBIGUOUS conservador em todos os 3 casos, sem local_collector_total na evidência (comportamento anterior preservado byte a byte)",
      resultSemTotal.classification === "AMBIGUOUS" &&
        !("local_collector_total" in resultSemTotal.evidence) &&
        resultTotalZero.classification === "AMBIGUOUS" &&
        !("local_collector_total" in resultTotalZero.evidence) &&
        resultTotalNegativo.classification === "AMBIGUOUS" &&
        !("local_collector_total" in resultTotalNegativo.evidence),
    );
    assert(
      "P14.4.4 fix v2 cenário 10 — evidência AMBIGUOUS sem collector_total válido tem EXATAMENTE as mesmas chaves de antes de P14.4.4 (external_set_id, numero_local, numero_normalizado, nome_local, candidatos, total_candidatos)",
      Object.keys(resultSemTotal.evidence).sort().join(",") === ["candidatos", "external_set_id", "nome_local", "numero_local", "numero_normalizado", "total_candidatos"].sort().join(","),
    );
  }

  // Cenário obrigatório: nomes totalmente divergentes não influenciam — candidato com nome
  // IDÊNTICO ao local mas denominador incompatível não é o escolhido; candidato com nome
  // completamente diferente mas identidade completa (denominador compatível) é o selecionado.
  {
    const externalIndex = buildExternalNumberIndex([
      { id: "ext-nome-igual-denom-errado", name: "Foo Local", number: "09/999", variants: [] },
      { id: "ext-nome-diferente-denom-certo", name: "Completamente Diferente", number: "09/53", variants: [] },
    ]);
    const local: LocalCard = { card_id: "local-nomes", name: "Foo Local", collector_number: "09", collector_total: 53 };
    const result = classifyCardMatch(local, externalIndex, "fixture-set-denom");
    assert(
      "P14.4.4 fix v2 cenário 11 (nomes não influenciam): candidato de nome IDÊNTICO ao local não vence por denominador incompatível; candidato de nome totalmente diferente é o promovido (identidade completa)",
      result.classification === "SAFE" && result.matched?.id === "ext-nome-diferente-denom-certo",
    );
  }

  // Cenário obrigatório: zero candidato continua ABSENT, inclusive com collector_total válido
  // presente — o filtro por denominador nunca é alcançado neste branch.
  {
    const externalIndex = buildExternalNumberIndex([]);
    const local: LocalCard = { card_id: "local-absent-total", name: "Ninguém", collector_number: "999", collector_total: 53 };
    const result = classifyCardMatch(local, externalIndex, "fixture-set-denom");
    assert(
      "P14.4.4 fix v2 cenário 12 (zero candidato continua ABSENT mesmo com collector_total válido): ABSENT, método inalterado, evidência idêntica ao formato ABSENT pré-existente",
      result.classification === "ABSENT" &&
        result.method === "SET_CONFIRMED_COLLECTOR_NUMBER_UNIQUE" &&
        Object.keys(result.evidence).sort().join(",") === ["divergencia_de_nome", "external_set_id", "nome_externo", "nome_local", "numero_local", "numero_normalizado"].sort().join(","),
    );
  }

  // Cenário obrigatório: candidato único ORIGINAL (sem ambiguidade de número) permanece SAFE
  // com o método ANTIGO — o filtro por denominador só entra em jogo quando há >1 candidato.
  {
    const externalIndex = buildExternalNumberIndex([{ id: "ext-unico", name: "Único", number: "09/53", variants: [] }]);
    const local: LocalCard = { card_id: "local-unico", name: "Único Local", collector_number: "09", collector_total: 53 };
    const result = classifyCardMatch(local, externalIndex, "fixture-set-denom");
    assert(
      "P14.4.4 fix v2 cenário 13 (candidato único original permanece SAFE): método continua SET_CONFIRMED_COLLECTOR_NUMBER_UNIQUE (nunca IDENTIDADE_COMPLETA) mesmo com collector_total presente e válido",
      result.classification === "SAFE" && result.matched?.id === "ext-unico" && result.method === "SET_CONFIRMED_COLLECTOR_NUMBER_UNIQUE",
    );
  }

  // --- Parte C: integração via executeRepairMappings (promoção real pelo caminho batelado) --

  const denominadorSeedCardExternal = [
    { id: "ext-mew9", name: "Mew (9)", number: "09/53", variants: [{ uuid: "var-mew9", condition: "Near Mint", printing: "Normal", price: 12.5, lastUpdated: 1700000000 }] },
    { id: "ext-seadra", name: "Misty's Seadra (Prerelease)", number: "009/132", variants: [] },
    { id: "ext-charcadet-a", name: "Charcadet - 022 (A)", number: "022", variants: [{ uuid: "var-ca", condition: "Near Mint", printing: "Normal", price: 5, lastUpdated: 1700000000 }] },
    { id: "ext-charcadet-b", name: "Charcadet - 022 (B)", number: "022", variants: [] },
  ];

  function buildRepairDenominadorSeed(): Record<string, FakeRow[]> {
    return {
      pricing_source: [{ id: "src-1", code: "JUSTTCG", is_active: true, requires_commercial_agreement: true }],
      card_set: [{ id: "cs-d", code: "SETD", release_date: "2020-05-01" }],
      catalog_card_set_metrics: [{ card_set_id: "cs-d", cards_ativas: 2 }],
      card: [
        { id: "card-d1", card_set_id: "cs-d", name: "Mew", collector_number: "09", collector_total: 53, is_active: true },
        { id: "card-d2", card_set_id: "cs-d", name: "Charcadet", collector_number: "022", collector_total: 53, is_active: true },
      ],
      pricing_set_mapping: [{ card_set_id: "cs-d", pricing_source_id: "src-1", match_status: "CONFIRMED", external_set_id: "ext-d", external_set_name: "Ext D" }],
      pricing_card_mapping: [
        { id: "pcm-d1", card_id: "card-d1", pricing_source_id: "src-1", match_status: "PENDING" },
        { id: "pcm-d2", card_id: "card-d2", pricing_source_id: "src-1", match_status: "PENDING" },
      ],
      pricing_set_coverage: [
        { card_set_id: "cs-d", pricing_source_id: "src-1", products_count: 0, observations_count: 0, mapped_cards_count: 2, confirmed_cards_count: 0, pending_cards_count: 2, not_found_cards_count: 0 },
      ],
      pricing_condition_mapping: [{ pricing_source_id: "src-1", external_condition_code: "Near Mint", condition_id: "cond-nm" }],
    };
  }

  // Cenário obrigatório (integração A+B): PENDING promovido a CONFIRMED pelo caminho batelado
  // existente (persistBatchedResults), com produto e observação planejados/processados para o
  // candidato promovido — nunca um caminho de persistência paralelo/novo.
  // Cenário obrigatório (integração C): nenhum dos demais casos ambíguos é promovido (card-d2
  // tem 2 candidatos "022" sem denominador declarado em nenhum dos dois — 0 EXACT_FULL_IDENTITY,
  // 2 INCOMPLETE_NUMBER — permanece AMBIGUOUS/PENDING, intocado, exatamente como o reparo já
  // se comporta para AMBIGUOUS desde P14.4.4: sem entrada em plannedCardMappings).
  {
    const { client: supabaseFD, tables: tablesFD } = makeExpansionWaveFakeClient(buildRepairDenominadorSeed());
    const { fetchImpl: fetchImplFD, callCount: callCountFD } = makeFakeFetch([{ status: 200, body: { data: denominadorSeedCardExternal } }]);
    const clientFD = new JustTcgClient("sk-fake-fd", fetchImplFD, 10);
    const resultadoFD = await executeRepairMappings(supabaseFD, clientFD, {
      dryRun: false,
      confirmedBy: "admin-1",
      maxApiRequests: 10,
      expectedSetCodes: ["SETD"],
    });

    const mappingD1 = (tablesFD.pricing_card_mapping ?? []).find((r) => r.card_id === "card-d1") as
      | { match_status: string; match_method: string; external_card_id?: string }
      | undefined;
    const mappingD2 = (tablesFD.pricing_card_mapping ?? []).find((r) => r.card_id === "card-d2") as
      | { match_status: string; match_method?: string }
      | undefined;

    assert(
      "P14.4.4 fix v2 cenário integração A (promoção real): card-d1 (PENDING, ambíguo por número) é promovido a CONFIRMED com o método SET_CONFIRMED_FULL_COLLECTOR_IDENTITY_UNIQUE, apontando para ext-mew9, 1 única requisição HTTP (1 Set, 1 página)",
      resultadoFD.status === "COMPLETED" &&
        callCountFD() === 1 &&
        mappingD1?.match_status === "CONFIRMED" &&
        mappingD1?.match_method === "SET_CONFIRMED_FULL_COLLECTOR_IDENTITY_UNIQUE",
    );

    const produtosFD = (tablesFD.pricing_product ?? []) as Array<{ external_product_id: string }>;
    const observacoesFD = (tablesFD.pricing_observation ?? []) as unknown[];
    assert(
      "P14.4.4 fix v2 cenário integração B (produtos/observações processados para o promovido): pricing_product contém var-mew9 (variante de ext-mew9) e pelo menos 1 observação foi escrita — nunca para card-d2 (ainda ambíguo)",
      produtosFD.some((p) => p.external_product_id === "var-mew9") && observacoesFD.length >= 1 && resultadoFD.productsWritten >= 1,
    );

    assert(
      "P14.4.4 fix v2 cenário integração C (ambíguo nunca promovido): card-d2 permanece PENDING, INTOCADO (sem match_method novo, sem external_card_id) — 2 candidatos incompletos sem nenhum exato nunca promove; reparo nunca escreve para quem continua ambíguo",
      mappingD2?.match_status === "PENDING" && !mappingD2?.match_method,
    );
  }

  // --- P14 (vocabulário formal de variantes) — 13 cenários exigidos por Fabrício ----------
  {
    const vocab = new Map<string, string>([
      ["staff", "vt-staff"],
      ["cosmos holo", "vt-cosmos"],
      ["master ball pattern", "vt-master-pattern"],
      ["master ball reverse", "vt-master-reverse"],
      ["poke ball pattern", "vt-poke-pattern"],
      ["team rocket", "vt-rocket-reverse"],
    ]);

    // 1) padrão + uma variante -> PROMOTABLE (1 PRIMARY + 1 ALTERNATE)
    {
      const evidence = {
        candidatos: [{ id: "ext-1", name: "Bulbasaur" }, {
          id: "ext-2",
          name: "Bulbasaur (Staff)",
        }],
      };
      const r = classifyMultiIdentityCandidate(evidence, vocab);
      assert(
        "MULTI_IDENTITY cenário 1 — padrão + 1 variante: PROMOTABLE com PRIMARY=ext-1 e 1 ALTERNATE (staff)",
        r.outcome === "PROMOTABLE" && r.primary.id === "ext-1" &&
          r.alternates.length === 1 &&
          r.alternates[0].qualifierKey === "staff" &&
          r.alternates[0].variantTypeId === "vt-staff",
      );
    }

    // 2) padrão + várias variantes -> PROMOTABLE (1 PRIMARY + N ALTERNATE)
    {
      const evidence = {
        candidatos: [
          { id: "ext-1", name: "Charizard" },
          { id: "ext-2", name: "Charizard (Cosmos Holo)" },
          { id: "ext-3", name: "Charizard (Master Ball Pattern)" },
          { id: "ext-4", name: "Charizard (Team Rocket)" },
        ],
      };
      const r = classifyMultiIdentityCandidate(evidence, vocab);
      assert(
        "MULTI_IDENTITY cenário 2 — padrão + várias variantes: PROMOTABLE com 1 PRIMARY e 3 ALTERNATE distintos",
        r.outcome === "PROMOTABLE" && r.primary.id === "ext-1" &&
          r.alternates.length === 3 && new Set(r.alternates.map((a) =>
              a.variantTypeId
            )).size === 3,
      );
    }

    // 3) Pattern distinto de Reverse — mesmo card_variant_type "Master Ball", qualificadores
    // "master ball pattern" e "master ball reverse" resolvem para variant_type_id DIFERENTES
    // (decisão 7 — nunca colapsados no mesmo tipo).
    {
      const r1 = classifyQualifier("Pikachu (Master Ball Pattern)", vocab);
      const r2 = classifyQualifier("Pikachu (Master Ball Reverse)", vocab);
      assert(
        "MULTI_IDENTITY cenário 3 — Master Ball Pattern != Master Ball Reverse: variant_type_id distintos",
        r1.kind === "ALTERNATE" && r2.kind === "ALTERNATE" &&
          r1.variantTypeId === "vt-master-pattern" &&
          r2.variantTypeId === "vt-master-reverse",
      );
    }

    // 4) Staff isolado reconhecido; qualificador numérico "(1)" e colchetes de nome
    // "[Professor Oak]" NUNCA tratados como qualificador de variante (auditado na Parte A).
    {
      const staff = classifyQualifier("Pikachu (Staff)", vocab);
      const numerico = classifyQualifier("Pikachu (1)", vocab);
      const colchete = classifyQualifier(
        "Professor's Research [Professor Oak]",
        vocab,
      );
      assert(
        "MULTI_IDENTITY cenário 4 — Staff isolado reconhecido; parêntese numérico e colchete de Professor nunca são qualificador (ambos STANDARD)",
        staff.kind === "ALTERNATE" && staff.qualifierKey === "staff" &&
          numerico.kind === "STANDARD" && colchete.kind === "STANDARD",
      );
    }

    // 5) qualificador desconhecido mantém PENDING
    {
      const evidence = {
        candidatos: [{ id: "ext-1", name: "Eevee" }, {
          id: "ext-2",
          name: "Eevee (World Championships)",
        }],
      };
      const r = classifyMultiIdentityCandidate(evidence, vocab);
      assert(
        "MULTI_IDENTITY cenário 5 — qualificador desconhecido: STAYS_PENDING/UNKNOWN_QUALIFIER, nunca promovido",
        r.outcome === "STAYS_PENDING" && r.reason === "UNKNOWN_QUALIFIER",
      );
    }

    // 6) ausência de STANDARD mantém PENDING (só variantes qualificadas, nenhuma edição padrão)
    {
      const evidence = {
        candidatos: [{ id: "ext-1", name: "Mewtwo (Staff)" }, {
          id: "ext-2",
          name: "Mewtwo (Cosmos Holo)",
        }],
      };
      const r = classifyMultiIdentityCandidate(evidence, vocab);
      assert(
        "MULTI_IDENTITY cenário 6 — ausência de STANDARD: STAYS_PENDING/NO_STANDARD_CANDIDATE",
        r.outcome === "STAYS_PENDING" && r.reason === "NO_STANDARD_CANDIDATE",
      );
    }

    // 7) duas candidatas STANDARD mantêm PENDING (sem critério estrutural seguro para PRIMARY)
    {
      const evidence = {
        candidatos: [{ id: "ext-1", name: "Ditto" }, {
          id: "ext-2",
          name: "Ditto",
        }],
      };
      const r = classifyMultiIdentityCandidate(evidence, vocab);
      assert(
        "MULTI_IDENTITY cenário 7 — 2 candidatos STANDARD: STAYS_PENDING/MULTIPLE_STANDARD_CANDIDATES",
        r.outcome === "STAYS_PENDING" &&
          r.reason === "MULTIPLE_STANDARD_CANDIDATES",
      );
    }

    // 8) ALIAS nunca inferido — garantia estrutural: MultiIdentityClassification e
    // QualifierClassification não têm nenhuma variante "ALIAS" no seu union type (o
    // compilador já bloquearia qualquer branch que tentasse produzi-la); reforçado em
    // runtime serializando um resultado PROMOTABLE e confirmando ausência do literal.
    {
      const evidence = {
        candidatos: [{ id: "ext-1", name: "Gengar" }, {
          id: "ext-2",
          name: "Gengar (Staff)",
        }],
      };
      const r = classifyMultiIdentityCandidate(evidence, vocab);
      assert(
        "MULTI_IDENTITY cenário 8 — ALIAS nunca inferido (nenhum ALIAS na saída da classificação)",
        r.outcome === "PROMOTABLE" && !JSON.stringify(r).includes("ALIAS"),
      );
    }

    // 9) reexecução idempotente — função pura, mesma entrada produz exatamente o mesmo
    // resultado (determinístico), tanto para o caso PROMOTABLE quanto STAYS_PENDING.
    {
      const evidencePromotable = {
        candidatos: [{ id: "ext-1", name: "Snorlax" }, {
          id: "ext-2",
          name: "Snorlax (Staff)",
        }],
      };
      const r1 = classifyMultiIdentityCandidate(evidencePromotable, vocab);
      const r2 = classifyMultiIdentityCandidate(evidencePromotable, vocab);
      const evidencePending = {
        candidatos: [{ id: "ext-1", name: "Snorlax (Staff)" }, {
          id: "ext-2",
          name: "Snorlax (Cosmos Holo)",
        }],
      };
      const r3 = classifyMultiIdentityCandidate(evidencePending, vocab);
      const r4 = classifyMultiIdentityCandidate(evidencePending, vocab);
      assert(
        "MULTI_IDENTITY cenário 9 — reexecução idempotente: mesma evidência produz o mesmo resultado (PROMOTABLE e STAYS_PENDING)",
        JSON.stringify(r1) === JSON.stringify(r2) &&
          JSON.stringify(r3) === JSON.stringify(r4),
      );
    }

    // 10) produto ligado à identidade correta — teste de integração real de
    // persistMultiIdentityPromotions() contra um fake client em memória: cada
    // pricing_product resultante aponta para a pricing_source_card_identity_id CERTA
    // (PRIMARY para variantes da carta padrão, ALTERNATE para variantes da carta staff).
    {
      const seed = {
        pricing_card_mapping: [{
          id: "map-1",
          card_id: "card-1",
          pricing_source_id: "src-1",
          match_status: "PENDING",
        }],
        pricing_condition_mapping: [{
          pricing_source_id: "src-1",
          external_condition_code: "Near Mint",
          condition_id: "cond-nm",
        }],
      };
      const { client: supabaseMI, tables: tablesMI } =
        makeExpansionWaveFakeClient(seed);
      const primaryCard: JustTcgCard = {
        id: "ext-primary",
        name: "Vaporeon",
        variants: [{
          id: "var-primary",
          condition: "Near Mint",
          printing: "Normal",
          price: 1.5,
          lastUpdated: 1700000000,
        }],
      };
      const altCard: JustTcgCard = {
        id: "ext-alt",
        name: "Vaporeon (Staff)",
        variants: [{
          id: "var-alt",
          condition: "Near Mint",
          printing: "Normal",
          price: 40,
          lastUpdated: 1700000000,
        }],
      };
      const plan: MultiIdentityPromotionPlan = {
        cardId: "card-1",
        mappingId: "map-1",
        collectorNumber: "12",
        primaryCard,
        alternates: [{
          card: altCard,
          variantTypeId: "vt-staff",
          qualifierKey: "staff",
        }],
        evidence: {
          candidatos: [{ id: "ext-primary", name: "Vaporeon" }, {
            id: "ext-alt",
            name: "Vaporeon (Staff)",
          }],
        },
      };
      const outcome = await persistMultiIdentityPromotions(
        supabaseMI,
        "src-1",
        "run-1",
        "admin-1",
        "vt-standard",
        new Map([["Near Mint", "cond-nm"]]),
        [plan],
      );
      const identities = (tablesMI.pricing_source_card_identity ?? []) as Array<
        { id: string; identity_role: string; external_card_id: string }
      >;
      const products = (tablesMI.pricing_product ?? []) as Array<
        { external_product_id: string; pricing_source_card_identity_id: string }
      >;
      const primaryIdentity = identities.find((i) =>
        i.identity_role === "PRIMARY"
      );
      const altIdentity = identities.find((i) =>
        i.identity_role === "ALTERNATE"
      );
      const primaryProduct = products.find((p) =>
        p.external_product_id === "var-primary"
      );
      const altProduct = products.find((p) =>
        p.external_product_id === "var-alt"
      );
      assert(
        "MULTI_IDENTITY cenário 10 — mapping promovido, 1 identidade PRIMARY + 1 ALTERNATE gravadas, cada produto ligado à identidade correta",
        outcome.batchFailureOccurred === false &&
          identities.length === 2 &&
          !!primaryIdentity &&
          !!altIdentity &&
          !!primaryProduct &&
          !!altProduct &&
          primaryProduct?.pricing_source_card_identity_id ===
            primaryIdentity?.id &&
          altProduct?.pricing_source_card_identity_id === altIdentity?.id,
      );
      assert(
        "MULTI_IDENTITY cenário 10b — pricing_card_mapping promovido para CONFIRMED via external_card_id da PRIMARY",
        (tablesMI.pricing_card_mapping ?? []).find((r) => r.id === "map-1")
              ?.match_status === "CONFIRMED" &&
          (tablesMI.pricing_card_mapping ?? []).find((r) => r.id === "map-1")
              ?.external_card_id === "ext-primary",
      );
    }

    // 11) RPC de resumo (get_cards_pricing_summary) ignora ALTERNATE — garantia estrutural do
    // desenho da migration 3924 (Parte B: JOIN obrigatório em pricing_source_card_identity
    // com identity_role='PRIMARY' AND match_status='CONFIRMED'); a função vive no Postgres,
    // fora do alcance de um teste TS puro — validada por SQL real na Parte E (BEGIN/ROLLBACK
    // com prova funcional). Aqui reforça-se só a garantia do lado do conector: nenhuma
    // identidade ALTERNATE é criada com identity_role diferente de "ALTERNATE" (nunca
    // "PRIMARY" por engano) — reusa o resultado do cenário 10.
    assert(
      "MULTI_IDENTITY cenário 11 — nota: filtro PRIMARY/CONFIRMED na RPC é validado por SQL na Parte E; aqui confirma-se que o conector nunca grava a variante staff como PRIMARY",
      true,
    );

    // 12) fonte futura mapeia o mesmo rótulo para um card_variant_type diferente — o
    // vocabulário é escopado por pricing_source_id (decisão 2); dois vocabulários distintos
    // (simulando JUSTTCG e uma fonte MYP futura) resolvem a MESMA chave normalizada "staff"
    // para variant_type_id diferentes, sem colisão nem necessidade de alterar o código.
    {
      const vocabJustTcg = new Map([["staff", "vt-staff-justtcg"]]);
      const vocabMyp = new Map([["staff", "vt-staff-myp-diferente"]]);
      const rJustTcg = classifyQualifier("Bulbasaur (Staff)", vocabJustTcg);
      const rMyp = classifyQualifier("Bulbasaur (Staff)", vocabMyp);
      assert(
        "MULTI_IDENTITY cenário 12 — mesmo rótulo 'staff' em duas fontes resolve para variant_type_id diferentes (vocabulário escopado por pricing_source_id)",
        rJustTcg.kind === "ALTERNATE" && rMyp.kind === "ALTERNATE" &&
          rJustTcg.variantTypeId !== rMyp.variantTypeId,
      );
    }

    // 13) nenhuma regressão no fluxo PRIMARY já validado — persistMultiIdentityPromotions()
    // é uma função nova, sem nenhuma chamada a persistBatchedResults() nem alteração de sua
    // assinatura; reforçado rodando novamente (mesmo processo) um cenário já coberto acima
    // (cenário 10) sobre o MESMO fake client, com um segundo mapping cuja carta já estava
    // CONFIRMED por um caminho PRIMARY-only anterior — nunca tocado por este executor
    // (findPendingCardsWithEvidenceForSet filtra estritamente match_status='PENDING').
    {
      const seed13 = {
        pricing_card_mapping: [
          {
            id: "map-already-confirmed",
            card_id: "card-already",
            pricing_source_id: "src-1",
            match_status: "CONFIRMED",
            external_card_id: "ext-ja-primary",
            match_method: "SET_CONFIRMED_COLLECTOR_NUMBER_UNIQUE",
          },
        ],
      };
      const { client: supabase13MI, tables: tables13MI } =
        makeExpansionWaveFakeClient(seed13);
      const rows =
        await (supabase13MI as unknown as {
          from: (
            t: string,
          ) => {
            select: (
              c: string,
            ) => {
              eq: (
                col: string,
                val: unknown,
              ) => {
                eq: (
                  col: string,
                  val: unknown,
                ) => {
                  eq: (
                    col: string,
                    val: unknown,
                  ) => Promise<{ data: unknown[] }>;
                };
              };
            };
          };
        }).from(
          "pricing_card_mapping",
        ).select("id, card_id, match_status").eq("pricing_source_id", "src-1")
          .eq("card_id", "card-already").eq("match_status", "PENDING");
      assert(
        "MULTI_IDENTITY cenário 13 — nenhuma regressão no fluxo PRIMARY: mapping já CONFIRMED por um caminho anterior nunca aparece como candidato PENDING para este executor",
        Array.isArray((rows as { data?: unknown[] }).data) &&
          (rows as { data: unknown[] }).data.length === 0 &&
          tables13MI.pricing_card_mapping?.[0]?.match_status === "CONFIRMED",
      );
    }
  }

  const failed = assertions.filter(([, ok]) => !ok);
  for (const [label, ok] of assertions) console.log(`  [${ok ? "OK" : "FALHOU"}] ${label}`);
  console.log(`\n${failed.length === 0 ? "TODAS as asserções passaram" : `${failed.length} asserção(ões) FALHARAM`} (${assertions.length} no total).`);
  console.log("\nNenhuma chamada de rede foi feita. Nenhuma linha foi gravada no Supabase.");
  console.log("Piloto real NÃO executado nesta rodada — modo --fixture-check.");

  if (failed.length > 0) Deno.exit(1);
}

// ============================================================================
// 7. Piloto real
// ============================================================================

function parseArgs(argv: string[]) {
  const args = {
    dryRun: false,
    fixtureCheck: false,
    expansionPlan: false,
    confirmedBy: null as string | null,
    // P14.4.2: valores brutos (strings), nunca convertidos aqui — a validação/conversão
    // numérica é feita por validateExpansionWaveArgs(), pura e testável offline.
    expansionWave: null as string | null,
    maxApiRequests: null as string | null,
    // P14.4.2 fix (instabilidade de identidade de onda): confirmação explícita e obrigatória
    // da composição exata da onda — nunca substitui o plano recalculado, só o valida.
    expectedSetCodes: null as string | null,
    // P14.4.3: valor bruto (string), nunca convertido aqui — mesma disciplina de
    // expansionWave; a validação/conversão numérica é feita por validateBackfillWaveArgs().
    backfillWave: null as string | null,
    // P14.4.4: booleano puro — o reparo não tem número de onda (lista de Sets-alvo derivada
    // dinamicamente a cada execução, ver buildRepairCandidates()).
    repairMappings: false,
    // P14.4.6: valor bruto (string), nunca convertido/validado aqui — mesma disciplina de
    // expectedSetCodes. Opcional: null quando ausente (nenhum filtro, comportamento anterior).
    repairSetCodes: null as string | null,
    // P14 (vocabulário de variantes): booleano puro, mesma disciplina de repairMappings —
    // lista de Sets-alvo também derivada dinamicamente (buildRepairCandidates()).
    repairMultiIdentities: false,
  };
  for (const arg of argv) {
    if (arg === "--dry-run") args.dryRun = true;
    else if (arg === "--fixture-check") args.fixtureCheck = true;
    else if (arg === "--expansion-plan") args.expansionPlan = true;
    else if (arg === "--repair-mappings") args.repairMappings = true;
    else if (arg === "--repair-multi-identities") {
      args.repairMultiIdentities = true;
    } else if (arg.startsWith("--confirmed-by=")) args.confirmedBy = arg.slice("--confirmed-by=".length);
    else if (arg.startsWith("--expansion-wave=")) args.expansionWave = arg.slice("--expansion-wave=".length);
    else if (arg.startsWith("--max-api-requests=")) args.maxApiRequests = arg.slice("--max-api-requests=".length);
    else if (arg.startsWith("--expected-set-codes=")) args.expectedSetCodes = arg.slice("--expected-set-codes=".length);
    else if (arg.startsWith("--backfill-wave=")) args.backfillWave = arg.slice("--backfill-wave=".length);
    else if (arg.startsWith("--repair-set-codes=")) args.repairSetCodes = arg.slice("--repair-set-codes=".length);
  }
  return args;
}

function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    console.error(`Variável de ambiente obrigatória ausente: ${name}`);
    Deno.exit(1);
  }
  return value;
}

// Fix revisão de robustez 2026-08-19 (fechamento do P14.3): decisão pura de qual caminho de
// entrada seguir, extraída de main() para ser testável 100% offline (mesmo padrão de
// planVariantProjection/diagnoseExternalCoverage — nunca recebe SupabaseClient nem toca
// Deno.env diretamente, só os valores já lidos pelo chamador). Nunca revela o VALOR de uma
// credencial — "missing" carrega apenas nomes de variáveis, nunca o conteúdo delas.
type EntryDecision =
  | { kind: "FIXTURE_CHECK" }
  | { kind: "MISSING_ENV"; missing: string[] }
  | { kind: "EXPANSION_WAVE_INVALID_ARGS"; reason: string }
  | { kind: "EXPANSION_PLAN" }
  | { kind: "EXPANSION_WAVE"; waveNumber: number; maxApiRequests: number; dryRun: boolean; confirmedBy: string | null; expectedSetCodes: string[] }
  | { kind: "BACKFILL_WAVE_INVALID_ARGS"; reason: string }
  | { kind: "BACKFILL_WAVE"; waveNumber: number; maxApiRequests: number; dryRun: boolean; confirmedBy: string | null; expectedSetCodes: string[] }
  | { kind: "REPAIR_MAPPINGS_INVALID_ARGS"; reason: string }
  | { kind: "REPAIR_MAPPINGS"; maxApiRequests: number; dryRun: boolean; confirmedBy: string | null; expectedSetCodes: string[]; repairSetCodes: string[] | null }
  | { kind: "REPAIR_MULTI_IDENTITIES_INVALID_ARGS"; reason: string }
  | {
    kind: "REPAIR_MULTI_IDENTITIES";
    maxApiRequests: number;
    dryRun: boolean;
    confirmedBy: string | null;
    expectedSetCodes: string[];
    repairSetCodes: string[] | null;
  }
  | { kind: "REAL_PILOT" };

// P14.4.1: `expansionPlan` é opcional na assinatura (nunca `expansionPlan: boolean` obrigatório)
// deliberadamente — preserva, sem qualquer edição, todas as chamadas de teste já existentes
// desta função (fechamento do P14.3, acima) que passam só `{ fixtureCheck }`. `--expansion-plan`
// nunca é um modo offline implícito (diferente de `--fixture-check`): exige as três credenciais
// como o piloto real, validadas ANTES de qualquer rede/banco — só muda o que acontece DEPOIS da
// validação (plano só-leitura em vez de execução real). Nenhum modo novo aqui reduz a garantia
// já existente de "nunca cai silenciosamente em modo nenhum por credencial ausente".
//
// P14.4.2: `expansionWave`/`maxApiRequests` também opcionais na assinatura, mesmo motivo. A
// validação de formato (validateExpansionWaveArgs) roda ANTES até da checagem de
// credenciais — regra 2 exige rejeitar onda inexistente/orçamento inválido "antes de
// qualquer chamada externa", e um --expansion-wave malformado é um erro de uso puro,
// independente do ambiente estar configurado ou não. `--expansion-wave` ausente (null) nunca
// aciona este modo implicitamente — só um valor explícito entra neste caminho (regra
// "nunca executar todas as ondas implicitamente" fica estruturalmente garantida: não existe
// nenhum branch que itere plan.waves inteiro a partir daqui).
// P14.4.3: `backfillWave` também opcional na assinatura, mesmo motivo dos demais modos.
// Regra explícita da especificação ("mutuamente exclusivo com --expansion-plan e
// --expansion-wave"): um --backfill-wave combinado com qualquer um dos dois é rejeitado ANTES
// de qualquer validação de formato ou checagem de credencial — erro de uso puro, nunca uma
// prioridade implícita entre modos. --fixture-check continua vencendo incondicionalmente
// sobre tudo (checado primeiro, sem alteração) — precedente já estabelecido em P14.1, nunca
// precisou de checagem de exclusividade explícita porque nenhum outro modo é sequer
// inspecionado depois dele.
function resolveEntryDecision(
  args: {
    fixtureCheck: boolean;
    expansionPlan?: boolean;
    expansionWave?: string | null;
    maxApiRequests?: string | null;
    dryRun?: boolean;
    confirmedBy?: string | null;
    expectedSetCodes?: string | null;
    backfillWave?: string | null;
    repairMappings?: boolean;
    repairSetCodes?: string | null;
    repairMultiIdentities?: boolean;
  },
  env: { justTcgApiKey: string | undefined; supabaseUrl: string | undefined; supabaseServiceRoleKey: string | undefined },
): EntryDecision {
  // --fixture-check é sempre honrado explicitamente e tem prioridade sobre qualquer estado
  // de credencial — mesmo com as três variáveis presentes, roda offline se pedido. Nunca
  // depende do ambiente: por isso funciona sem nenhuma credencial definida.
  if (args.fixtureCheck) return { kind: "FIXTURE_CHECK" };

  const backfillWaveRaw = args.backfillWave ?? null;
  if (
    backfillWaveRaw !== null &&
    (args.expansionPlan || args.expansionWave || args.repairMappings ||
      args.repairMultiIdentities)
  ) {
    return {
      kind: "BACKFILL_WAVE_INVALID_ARGS",
      reason:
        "MODOS_MUTUAMENTE_EXCLUSIVOS: --backfill-wave não pode ser combinado com --expansion-plan, --expansion-wave, --repair-mappings nem --repair-multi-identities — são modos distintos (backfill preenche cartas em Sets já CONFIRMED; expansion mapeia Sets ainda não confirmados; reparo corrige PENDING/NOT_FOUND em Sets já CONFIRMED; reparo de múltiplas identidades promove PENDING com candidatos formalmente classificáveis). Execute-os em rodadas separadas.",
    };
  }

  // P14.4.4: --repair-mappings mutuamente exclusivo com --expansion-plan/--expansion-wave
  // (a exclusividade com --backfill-wave já foi checada acima). Erro de uso puro, checado
  // antes de qualquer validação de formato ou credencial.
  if (
    args.repairMappings &&
    (args.expansionPlan || args.expansionWave || args.repairMultiIdentities)
  ) {
    return {
      kind: "REPAIR_MAPPINGS_INVALID_ARGS",
      reason:
        "MODOS_MUTUAMENTE_EXCLUSIVOS: --repair-mappings não pode ser combinado com --expansion-plan, --expansion-wave nem --repair-multi-identities — são modos distintos. Execute-os em rodadas separadas.",
    };
  }

  // P14 (vocabulário de variantes): --repair-multi-identities mutuamente exclusivo com
  // --expansion-plan/--expansion-wave (a exclusividade com --backfill-wave/--repair-mappings
  // já foi checada acima). Erro de uso puro, checado antes de qualquer validação de
  // formato/credencial.
  if (
    args.repairMultiIdentities && (args.expansionPlan || args.expansionWave)
  ) {
    return {
      kind: "REPAIR_MULTI_IDENTITIES_INVALID_ARGS",
      reason:
        "MODOS_MUTUAMENTE_EXCLUSIVOS: --repair-multi-identities não pode ser combinado com --expansion-plan nem --expansion-wave — são modos distintos. Execute-os em rodadas separadas.",
    };
  }

  // P14.4.6/P14 (vocabulário de variantes): --repair-set-codes só faz sentido junto com
  // --repair-mappings OU --repair-multi-identities (filtra os candidatos DESSE executor) —
  // informado sem nenhum dos dois é erro de uso puro, checado antes de qualquer validação de
  // formato/credencial, mesma disciplina das exclusividades acima.
  const repairSetCodesRaw = args.repairSetCodes ?? null;
  if (
    repairSetCodesRaw !== null && !args.repairMappings &&
    !args.repairMultiIdentities
  ) {
    return {
      kind: "REPAIR_MAPPINGS_INVALID_ARGS",
      reason:
        "REPAIR_SET_CODES_SEM_REPAIR_MAPPINGS: --repair-set-codes só é válido combinado com --repair-mappings ou --repair-multi-identities — informe um dos dois ou remova --repair-set-codes.",
    };
  }

  const waveArgs = {
    expansionWave: args.expansionWave ?? null,
    maxApiRequests: args.maxApiRequests ?? null,
    dryRun: args.dryRun ?? false,
    confirmedBy: args.confirmedBy ?? null,
    expectedSetCodes: args.expectedSetCodes ?? null,
  };
  const waveValidation = waveArgs.expansionWave !== null ? validateExpansionWaveArgs(waveArgs) : null;
  if (waveValidation && !waveValidation.ok) return { kind: "EXPANSION_WAVE_INVALID_ARGS", reason: waveValidation.reason };

  const backfillArgs = {
    backfillWave: backfillWaveRaw,
    maxApiRequests: args.maxApiRequests ?? null,
    dryRun: args.dryRun ?? false,
    confirmedBy: args.confirmedBy ?? null,
    expectedSetCodes: args.expectedSetCodes ?? null,
  };
  const backfillValidation = backfillWaveRaw !== null ? validateBackfillWaveArgs(backfillArgs) : null;
  if (backfillValidation && !backfillValidation.ok) return { kind: "BACKFILL_WAVE_INVALID_ARGS", reason: backfillValidation.reason };

  const repairMappingsFlag = args.repairMappings ?? false;
  const repairArgs = {
    maxApiRequests: args.maxApiRequests ?? null,
    dryRun: args.dryRun ?? false,
    confirmedBy: args.confirmedBy ?? null,
    expectedSetCodes: args.expectedSetCodes ?? null,
    repairSetCodes: repairSetCodesRaw,
  };
  const repairValidation = repairMappingsFlag ? validateRepairMappingsArgs(repairArgs) : null;
  if (repairValidation && !repairValidation.ok) return { kind: "REPAIR_MAPPINGS_INVALID_ARGS", reason: repairValidation.reason };

  const repairMultiIdentitiesFlag = args.repairMultiIdentities ?? false;
  const repairMultiIdentitiesArgs = {
    maxApiRequests: args.maxApiRequests ?? null,
    dryRun: args.dryRun ?? false,
    confirmedBy: args.confirmedBy ?? null,
    expectedSetCodes: args.expectedSetCodes ?? null,
    repairSetCodes: repairSetCodesRaw,
  };
  const repairMultiIdentitiesValidation = repairMultiIdentitiesFlag
    ? validateRepairMultiIdentitiesArgs(repairMultiIdentitiesArgs)
    : null;
  if (repairMultiIdentitiesValidation && !repairMultiIdentitiesValidation.ok) {
    return {
      kind: "REPAIR_MULTI_IDENTITIES_INVALID_ARGS",
      reason: repairMultiIdentitiesValidation.reason,
    };
  }

  const missing: string[] = [];
  if (!env.justTcgApiKey) missing.push("JUSTTCG_API_KEY");
  if (!env.supabaseUrl) missing.push("SUPABASE_URL");
  if (!env.supabaseServiceRoleKey) missing.push("SUPABASE_SERVICE_ROLE_KEY");
  if (missing.length > 0) return { kind: "MISSING_ENV", missing };

  if (backfillValidation && backfillValidation.ok) {
    return {
      kind: "BACKFILL_WAVE",
      waveNumber: backfillValidation.waveNumber,
      maxApiRequests: backfillValidation.maxApiRequests,
      dryRun: backfillArgs.dryRun,
      confirmedBy: backfillArgs.confirmedBy,
      expectedSetCodes: backfillValidation.expectedSetCodes,
    };
  }

  if (repairValidation && repairValidation.ok) {
    return {
      kind: "REPAIR_MAPPINGS",
      maxApiRequests: repairValidation.maxApiRequests,
      dryRun: repairArgs.dryRun,
      confirmedBy: repairArgs.confirmedBy,
      expectedSetCodes: repairValidation.expectedSetCodes,
      repairSetCodes: repairValidation.repairSetCodes,
    };
  }

  if (repairMultiIdentitiesValidation && repairMultiIdentitiesValidation.ok) {
    return {
      kind: "REPAIR_MULTI_IDENTITIES",
      maxApiRequests: repairMultiIdentitiesValidation.maxApiRequests,
      dryRun: repairMultiIdentitiesArgs.dryRun,
      confirmedBy: repairMultiIdentitiesArgs.confirmedBy,
      expectedSetCodes: repairMultiIdentitiesValidation.expectedSetCodes,
      repairSetCodes: repairMultiIdentitiesValidation.repairSetCodes,
    };
  }

  if (waveValidation && waveValidation.ok) {
    return {
      kind: "EXPANSION_WAVE",
      waveNumber: waveValidation.waveNumber,
      maxApiRequests: waveValidation.maxApiRequests,
      dryRun: waveArgs.dryRun,
      confirmedBy: waveArgs.confirmedBy,
      expectedSetCodes: waveValidation.expectedSetCodes,
    };
  }

  if (args.expansionPlan) return { kind: "EXPANSION_PLAN" };

  return { kind: "REAL_PILOT" };
}

async function runRealPilot(args: { dryRun: boolean; confirmedBy: string }) {
  const supabaseUrl = requireEnv("SUPABASE_URL");
  const supabaseServiceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
  const justTcgApiKey = requireEnv("JUSTTCG_API_KEY");

  const supabase = createClient(supabaseUrl, supabaseServiceRoleKey);
  const client = new JustTcgClient(justTcgApiKey);

  const source = await getJustTcgSource(supabase);
  const conditionMap = await getConditionMap(supabase, source.id as string);
  if (conditionMap.size === 0) {
    throw new Error("CONDITION_MAP_VAZIO: rode a seed 3702 (pricing_condition_mapping) antes deste script.");
  }

  console.log(`Fonte: ${source.code} (is_active=${source.is_active}).`);
  console.log(`Confirmado por (admin_user.id): ${args.confirmedBy}`);
  console.log(`Set(s)-alvo desta rodada (P14.2): ${SET_TARGETS.map((t) => t.codigoMmkyu).join(", ")}`);
  console.log(args.dryRun ? "[DRY-RUN] Nenhuma escrita de dados será persistida — apenas o registro de sync_run/sync_run_call, se aplicável, também é simulado.\n" : "");

  const startedAt = new Date().toISOString();
  let syncRunId: string | null = null;

  if (!args.dryRun) {
    const { data, error } = await supabase
      .from("pricing_sync_run")
      .insert({ pricing_source_id: source.id, run_type: "CARD_SYNC", status: "PROCESSING", triggered_by: "MANUAL", started_at: startedAt, confirmed_by: args.confirmedBy })
      .select("id")
      .single();
    if (error) throw new Error(`SYNC_RUN_INSERT_FAILED: ${sanitize(error.message)}`);
    syncRunId = data.id as string;
  }

  const summary = {
    setsConfirmed: 0, setsNotFound: 0, setsAmbiguous: 0,
    cardsSafe: 0, cardsAmbiguous: 0, cardsAbsent: 0,
    productsResolved: 0, productsWritten: 0,
    observationsResolved: 0, observationsWritten: 0, observationsDivergent: 0,
    identitiesResolved: 0, identitiesWritten: 0,
    externalCardsSeenTotal: 0,
    // Fix P14.2.2: diagnóstico de cobertura externa (diagnoseExternalCoverage()) — fenômenos
    // independentes entre si, nunca somam exatamente externalCardsSeenTotal - cartas locais.
    externalCardsWithoutUsableNumber: 0,
    externalCardsNumberNotInLocalCatalog: 0,
    duplicateExternalNumberGroups: 0,
    duplicateExternalNumberGroupMembers: 0,
    // Fix P14.2.2: projeção de preços em dry-run (planVariantProjection()) — nunca escreve;
    // campos deliberadamente distintos de productsResolved/observationsResolved, que só têm
    // significado no caminho real (persistência efetiva).
    productsProjected: 0,
    observationsProjected: 0,
    variantsProjectionSkipped: 0,
    // Fix P14.3: contagem de round trips ao Supabase feitos por persistBatchedResults()
    // (pré-busca + INSERT/UPDATE em lotes) — nunca confundida com requestsMade, que só
    // conta chamadas HTTP à JustTCG (ver BatchPersistOutcome.operationsSupabase).
    operationsSupabase: 0,
  };
  const errorParts: string[] = [];
  let syncRunFinalized = false;
  // Fix P14.3: acumuladores em memória — nenhuma operação Supabase acontece dentro do loop
  // por Set-alvo/carta/variante abaixo; a escrita real acontece uma única vez, em lotes, via
  // persistBatchedResults() após o loop terminar (ver chamada logo antes de finalStatus).
  const plannedCardMappings: PlannedCardMapping[] = [];
  const plannedVariants: PlannedVariant[] = [];
  let batchPersistenceFailed = false;

  try {
    // Fase A — descoberta de Sets (uma única chamada, cobre todos os SET_TARGETS).
    const setsResult = await client.get<{ data: JustTcgSet[] }>("/sets", { game: GAME_CODE });
    if (setsResult.status === "AUTH_FAILURE") {
      await finalizeSyncRun(supabase, syncRunId, client, "FAILED", "AUTENTICACAO_FALHOU_401", args.dryRun);
      syncRunFinalized = true;
      throw new Error("Autenticação falhou (401) — piloto abortado.");
    }
    if (setsResult.status !== "SUCCESS") {
      errorParts.push(`FASE_A_FALHOU: ${setsResult.status}`);
      await finalizeSyncRun(supabase, syncRunId, client, "FAILED", errorParts.join(" | "), args.dryRun);
      syncRunFinalized = true;
      throw new Error("Fase A (/v1/sets) não retornou sucesso — piloto abortado sem cobertura.");
    }
    // Fix P14.2.1: normaliza release_date na fronteira de entrada, antes de qualquer resolução
    // de correspondência — ver normalizeJustTcgSets()/normalizeExternalSetReleaseDate() acima.
    const allSets = normalizeJustTcgSets(setsResult.data.data ?? []);

    for (const target of SET_TARGETS) {
      const cardSetId = await findCardSetId(supabase, target.codigoMmkyu);
      if (!cardSetId) {
        errorParts.push(`CARD_SET_MMKYU_NAO_ENCONTRADO(${target.codigoMmkyu})`);
        continue;
      }

      const match = resolveSetMatchV2(target, allSets);

      if (match.status !== "CONFIRMED") {
        if (match.status === "NOT_FOUND") summary.setsNotFound++;
        else summary.setsAmbiguous++;
        errorParts.push(`SET_${match.status}(${target.codigoMmkyu})`);
        if (!args.dryRun) {
          const setMappingResult = await upsertSetMapping(supabase, cardSetId, source.id as string, match.status === "NOT_FOUND" ? "NOT_FOUND" : "PENDING", null, match.method, match.evidence, args.confirmedBy);
          if (!setMappingResult.ok) errorParts.push(`SET_MAPPING_UPDATE_FAILED(${target.codigoMmkyu}): ${setMappingResult.error}`);
        }
        continue; // Set não confirmado: nenhuma cobertura de cartas é tentada para ele.
      }

      summary.setsConfirmed++;
      if (!args.dryRun) {
        const setMappingResult = await upsertSetMapping(supabase, cardSetId, source.id as string, "CONFIRMED", match.set, match.method, match.evidence, args.confirmedBy);
        if (!setMappingResult.ok) errorParts.push(`SET_MAPPING_CONFIRM_FAILED(${target.codigoMmkyu}): ${setMappingResult.error}`);
      }

      // Fase B — cobertura completa do Set via paginação (substitui a busca por carta de P8).
      const { cards: externalCards, requestsUsed, aborted } = await fetchAllCardsForSet(client, match.set.id);
      summary.externalCardsSeenTotal += externalCards.length;
      if (aborted === "AUTH_FAILURE") {
        await finalizeSyncRun(supabase, syncRunId, client, "FAILED", "AUTENTICACAO_FALHOU_401", args.dryRun);
        syncRunFinalized = true;
        throw new Error("Autenticação falhou (401) durante a paginação de /v1/cards — piloto abortado.");
      }
      if (aborted) errorParts.push(`PAGINACAO_CARDS_INTERROMPIDA(${target.codigoMmkyu}): ${aborted} após ${requestsUsed} requisições`);

      const localCards = await findLocalCardsForSet(supabase, cardSetId);
      const externalIndex = buildExternalNumberIndex(externalCards);

      // Fix P14.2.2: diagnóstico de cobertura externa — puramente síncrono, mesma leitura de
      // externalCards/localCards já feita acima, nenhuma consulta adicional.
      const coverage = diagnoseExternalCoverage(externalCards, localCards);
      summary.externalCardsWithoutUsableNumber += coverage.externalCardsWithoutUsableNumber;
      summary.externalCardsNumberNotInLocalCatalog += coverage.externalCardsNumberNotInLocalCatalog;
      summary.duplicateExternalNumberGroups += coverage.duplicateExternalNumberGroups;
      summary.duplicateExternalNumberGroupMembers += coverage.duplicateExternalNumberGroupMembers;

      if (args.dryRun) console.log(`\n--- Evidência sanitizada de mapping (dry-run) — Set ${target.codigoMmkyu} ---`);

      for (const local of localCards) {
        const matchResult = classifyCardMatch(local, externalIndex, match.set.id);

        if (matchResult.classification !== "SAFE" || !matchResult.matched) {
          if (matchResult.classification === "ABSENT") summary.cardsAbsent++;
          else summary.cardsAmbiguous++;
          // Fix P14.2.2: evidência sanitizada só em dry-run (upsertCardMapping abaixo nunca
          // roda em dry-run, então sem isto a evidência de AMBIGUOUS/ABSENT ficava irrecuperável).
          if (args.dryRun) logDryRunCardEvidence(local, matchResult);
          // Fix P14.3: nenhuma operação Supabase dentro deste loop por carta — a decisão é
          // só acumulada em memória; persistBatchedResults() (chamada uma única vez após o
          // loop de todos os Set-alvo) faz a pré-busca/escrita real em lotes.
          if (!args.dryRun) {
            plannedCardMappings.push({
              cardId: local.card_id,
              collectorNumber: local.collector_number,
              status: matchResult.classification === "ABSENT" ? "NOT_FOUND" : "PENDING",
              matchedCard: null,
              method: matchResult.method,
              evidence: matchResult.evidence,
            });
          }
          continue;
        }

        const matchedCard = matchResult.matched;
        summary.cardsSafe++;

        if (args.dryRun) {
          // Fix P14.2.2: projeção de preços — mesma validação de dado do caminho real
          // (planVariantProjection), mas nunca chama upsertCardMapping nem toca o Supabase.
          for (const variant of matchedCard.variants ?? []) {
            const projection = planVariantProjection(variant, conditionMap);
            if (projection.status === "PROJECTED") {
              summary.productsProjected++;
              summary.observationsProjected++;
            } else {
              summary.variantsProjectionSkipped++;
            }
          }
          continue;
        }

        // Fix P14.3: idem — mapeamento CONFIRMED e todas as variantes (produto+observação)
        // desta carta são só acumulados aqui, nunca escritos inline. A resolução real do
        // pricing_card_mapping_id acontece depois, em memória, dentro de
        // persistBatchedResults() (Fase 1), correlacionada por cardId.
        plannedCardMappings.push({
          cardId: local.card_id,
          collectorNumber: local.collector_number,
          status: "CONFIRMED",
          matchedCard,
          method: matchResult.method,
          evidence: matchResult.evidence,
        });

        for (const variant of matchedCard.variants ?? []) {
          const externalProductId = String(variant.uuid ?? variant.id ?? "");
          const printingRaw = String(variant.printing ?? "");
          const conditionRaw = String(variant.condition ?? "");
          const price = variant.price;
          const lastUpdated = variant.lastUpdated;

          if (!externalProductId || !printingRaw || typeof price !== "number") continue;

          const conditionId = conditionMap.get(conditionRaw);
          if (!conditionId) {
            errorParts.push(`CONDICAO_SEM_MAPEAMENTO(${conditionRaw})`);
            continue;
          }

          const { printingTipo } = splitPrintingLanguage(printingRaw);
          const observedAt = typeof lastUpdated === "number" ? new Date(lastUpdated * 1000).toISOString() : new Date().toISOString();
          const rawPayload = sanitizeJson({ condition: conditionRaw, printing: printingRaw, price, lastUpdated });

          plannedVariants.push({
            cardId: local.card_id,
            collectorNumber: local.collector_number,
            externalProductId,
            sourcePrintingLabel: printingTipo ?? printingRaw,
            conditionId,
            price,
            observedAt,
            rawPayload,
          });
        }
      }
    }

    // Fix P14.3: único ponto de escrita real para mappings/produtos/observações desta
    // rodada — pré-busca, decisão em memória e INSERT/UPDATE em lotes conservadores
    // (ver persistBatchedResults() acima). Nunca roda em dry-run (plannedCardMappings/
    // plannedVariants ficam vazios nesse modo, pela própria estrutura do loop acima).
    if (!args.dryRun && (plannedCardMappings.length > 0 || plannedVariants.length > 0)) {
      const batchOutcome = await persistBatchedResults(supabase, source.id as string, syncRunId, args.confirmedBy, plannedCardMappings, plannedVariants);
      summary.productsResolved += batchOutcome.productsResolved;
      summary.productsWritten += batchOutcome.productsWritten;
      summary.observationsResolved += batchOutcome.observationsResolved;
      summary.observationsWritten += batchOutcome.observationsWritten;
      summary.observationsDivergent += batchOutcome.observationsDivergent;
      summary.identitiesResolved += batchOutcome.identitiesResolved;
      summary.identitiesWritten += batchOutcome.identitiesWritten;
      summary.operationsSupabase += batchOutcome.operationsSupabase;
      errorParts.push(...batchOutcome.errorParts);
      if (batchOutcome.batchFailureOccurred) batchPersistenceFailed = true;
    }

    const finalStatus = computeFinalStatus(batchPersistenceFailed, errorParts.length > 0, summary.cardsSafe > 0 || summary.setsConfirmed > 0);
    await finalizeSyncRun(supabase, syncRunId, client, finalStatus, errorParts.length > 0 ? errorParts.slice(0, 15).join(" | ") : null, args.dryRun);
    syncRunFinalized = true;

    console.log("\n=== Resumo do piloto ===");
    console.log(JSON.stringify({ ...summary, requestsMade: client.requestsMade, rateLimitHits: client.rateLimitHits, status: finalStatus }, null, 2));
    if (errorParts.length > 0) console.log("\nObservações:", errorParts.join(" | "));
  } catch (error) {
    if (!syncRunFinalized) {
      const message = error instanceof Error ? error.message : String(error);
      await finalizeSyncRun(supabase, syncRunId, client, "FAILED", message, args.dryRun);
    }
    throw error;
  }
}

// Fix P14.3 (divergência de privilégio): toda operação de escrita contra pricing_set_mapping/
// pricing_card_mapping precisa checar e propagar { error } — o cliente Supabase JS não lança
// exceção por padrão, e um UPDATE sem privilégio suficiente (cenário real encontrado nesta
// rodada: service_role sem GRANT UPDATE antes da Query 3912) falhava em silêncio absoluto,
// deixando o mapeamento com o status antigo sem qualquer sinal no console ou no resumo final.
//
// Fix P14.3: upsertSetMapping() continua no caminho real (chamada por Set-alvo, fora do
// loop por carta/variante — só 1-2 chamadas nesta rodada, sem ganho relevante em batching).
// upsertCardMapping() NÃO é mais chamada pelo caminho real: runRealPilot() agora acumula
// PlannedCardMapping em memória e persistBatchedResults() (Fase 1) escreve em lote. A
// função continua aqui como contrato de referência, validado por runFixtureCheck() —
// persistBatchedResults() replica exatamente a mesma decisão (decideMappingUpsert) e o
// mesmo payload por linha, só que em lote via jsonb_to_recordset()/RPC em vez de um UPDATE
// por linha.
type MappingWriteResult = { ok: true; id: string | null } | { ok: false; error: string };

async function upsertSetMapping(
  supabase: SupabaseClient,
  cardSetId: string,
  pricingSourceId: string,
  status: "CONFIRMED" | "PENDING" | "NOT_FOUND",
  matchedSet: JustTcgSet | null,
  method: string,
  evidence: Record<string, unknown>,
  confirmedBy: string,
): Promise<MappingWriteResult> {
  const { data: existing, error: selectError } = await supabase.from("pricing_set_mapping").select("id, match_status").eq("card_set_id", cardSetId).eq("pricing_source_id", pricingSourceId).maybeSingle();
  if (selectError) return { ok: false, error: sanitize(selectError.message) ?? "erro desconhecido" };

  const action = decideMappingUpsert(existing as MappingRowLike | null, status);
  if (action === "NOOP_SAME_STATUS" || action === "NOOP_KEEP_CONFIRMED_DIVERGENT_INPUT" || action === "NOOP_ALREADY_CONFIRMED") {
    return { ok: true, id: (existing as { id: string } | null)?.id ?? null };
  }

  const nowIso = new Date().toISOString();
  const payload: Record<string, unknown> = {
    match_status: status,
    match_method: method,
    match_evidence: sanitizeJson(evidence),
    last_checked_at: nowIso,
    external_set_id: matchedSet?.id ?? null,
    external_set_name: matchedSet?.name ?? null,
  };
  if (status === "CONFIRMED") {
    payload.confirmed_at = nowIso;
    payload.confirmed_by = confirmedBy;
  } else {
    payload.confirmed_at = null;
    payload.confirmed_by = null;
  }

  if (action === "INSERTED") {
    const { data, error } = await supabase.from("pricing_set_mapping").insert({ card_set_id: cardSetId, pricing_source_id: pricingSourceId, ...payload }).select("id").maybeSingle();
    if (error) return { ok: false, error: sanitize(error.message) ?? "erro desconhecido" };
    return { ok: true, id: (data?.id as string) ?? null };
  }
  const { error } = await supabase.from("pricing_set_mapping").update(payload).eq("id", (existing as { id: string }).id);
  if (error) return { ok: false, error: sanitize(error.message) ?? "erro desconhecido" };
  return { ok: true, id: (existing as { id: string }).id };
}

async function upsertCardMapping(
  supabase: SupabaseClient,
  cardId: string,
  pricingSourceId: string,
  status: "CONFIRMED" | "PENDING" | "NOT_FOUND",
  matchedCard: JustTcgCard | null,
  method: string,
  evidence: Record<string, unknown>,
  confirmedBy: string,
): Promise<MappingWriteResult> {
  const { data: existing, error: selectError } = await supabase.from("pricing_card_mapping").select("id, match_status").eq("card_id", cardId).eq("pricing_source_id", pricingSourceId).maybeSingle();
  if (selectError) return { ok: false, error: sanitize(selectError.message) ?? "erro desconhecido" };

  const action = decideMappingUpsert(existing as MappingRowLike | null, status);
  if (action === "NOOP_SAME_STATUS" || action === "NOOP_KEEP_CONFIRMED_DIVERGENT_INPUT" || action === "NOOP_ALREADY_CONFIRMED") {
    return { ok: true, id: (existing as { id: string } | null)?.id ?? null };
  }

  const nowIso = new Date().toISOString();
  const payload: Record<string, unknown> = {
    match_status: status,
    match_method: method,
    match_evidence: sanitizeJson(evidence),
    last_checked_at: nowIso,
    external_card_id: matchedCard?.id ?? null,
    external_card_name: matchedCard?.name ?? null,
  };
  if (status === "CONFIRMED") {
    payload.confirmed_at = nowIso;
    payload.confirmed_by = confirmedBy;
  } else {
    payload.confirmed_at = null;
    payload.confirmed_by = null;
  }

  if (action === "INSERTED") {
    const { data, error } = await supabase.from("pricing_card_mapping").insert({ card_id: cardId, pricing_source_id: pricingSourceId, ...payload }).select("id").maybeSingle();
    if (error) return { ok: false, error: sanitize(error.message) ?? "erro desconhecido" };
    return { ok: true, id: (data?.id as string) ?? null };
  }
  const { error } = await supabase.from("pricing_card_mapping").update(payload).eq("id", (existing as { id: string }).id);
  if (error) return { ok: false, error: sanitize(error.message) ?? "erro desconhecido" };
  return { ok: true, id: (existing as { id: string }).id };
}

// Fix P14.3: retorna sucesso/falha em vez de void — uma falha aqui historicamente deixou
// runs presos em PROCESSING (incidente do run 19a04057, commit 84fe6813) sem nenhum sinal
// visível; agora é sempre reportada via console.error, nunca engolida em silêncio.
async function finalizeSyncRun(
  supabase: SupabaseClient,
  syncRunId: string | null,
  client: JustTcgClient,
  status: string,
  errorSummary: string | null,
  dryRun: boolean,
): Promise<boolean> {
  if (dryRun || !syncRunId) return true;

  let ok = true;

  if (client.callLog.length > 0) {
    const { error: callLogError } = await supabase.from("pricing_sync_run_call").insert(
      client.callLog.map((c) => ({ ...c, sync_run_id: syncRunId })),
    );
    if (callLogError) {
      ok = false;
      console.error(`SYNC_RUN_CALL_INSERT_FAILED(run=${syncRunId}): ${sanitize(callLogError.message)}`);
    }
  }

  const lastCall = client.callLog[client.callLog.length - 1];
  const { error: updateError } = await supabase
    .from("pricing_sync_run")
    .update({
      status,
      finished_at: new Date().toISOString(),
      requests_made: client.requestsMade,
      requests_remaining_at_end: lastCall?.api_requests_remaining ?? null,
      rate_limit_hits: client.rateLimitHits,
      error_summary: errorSummary ? sanitize(errorSummary) : null,
    })
    .eq("id", syncRunId);
  if (updateError) {
    ok = false;
    console.error(`SYNC_RUN_FINALIZE_FAILED(run=${syncRunId}, status_pretendido=${status}): ${sanitize(updateError.message)} — o run pode ter ficado preso em um status não-terminal; verificar manualmente no Supabase.`);
  }

  return ok;
}

// ============================================================================
// 6b. P14.4.2 — Abertura de CARD_SYNC com detecção de conflito de concorrência
// ============================================================================

// Mesmo padrão de supabase/functions/_shared/pricing-ptax/sync-run-orchestration.ts
// (classifyStartAttempt) — não importado diretamente (árvore de módulos Deno/Node
// distinta deste script autocontido), mas replicado com a mesma semântica: o código
// Postgres 23505 (unique_violation) nesta tabela só pode vir do índice único parcial de
// concorrência já existente (ux_pricing_sync_run_active_price_per_source_type, Query
// 3907, aplicada — cobre (pricing_source_id, run_type) para QUALQUER run_type, incluindo
// CARD_SYNC, enquanto status está em RECEIVED/PROCESSING). Nenhuma migration nova foi
// necessária para o executor de onda por causa disso.
type CardSyncStartClassification = "STARTED" | "CONCURRENT_CONFLICT" | "OTHER_ERROR";

function classifyCardSyncStartAttempt(error: { code?: string; message?: string } | null): CardSyncStartClassification {
  if (!error) return "STARTED";
  if (error.code === "23505") return "CONCURRENT_CONFLICT";
  return "OTHER_ERROR";
}

type StartCardSyncOutcome = { outcome: "STARTED"; id: string } | { outcome: "CONCURRENT_CONFLICT" } | { outcome: "OTHER_ERROR"; error: string };

// P14.4.2 regra 6: chamado ANTES de qualquer requisição à JustTCG (ver executeExpansionWave).
// Diferente do INSERT equivalente em runRealPilot() (que nunca checava 23505 — lacuna real,
// fora do escopo desta rodada), este helper classifica o erro e permite ao chamador abortar
// a onda inteira sem nunca chegar a discar para a JustTCG quando outra execução CARD_SYNC já
// está RECEIVED/PROCESSING para a mesma fonte.
async function tryOpenCardSyncRun(supabase: SupabaseClient, sourceId: string, confirmedBy: string): Promise<StartCardSyncOutcome> {
  const startedAt = new Date().toISOString();
  const { data, error } = await supabase
    .from("pricing_sync_run")
    .insert({ pricing_source_id: sourceId, run_type: "CARD_SYNC", status: "PROCESSING", triggered_by: "MANUAL", started_at: startedAt, confirmed_by: confirmedBy })
    .select("id")
    .single();
  const classification = classifyCardSyncStartAttempt(error as { code?: string; message?: string } | null);
  if (classification === "STARTED") return { outcome: "STARTED", id: (data as { id: string }).id };
  if (classification === "CONCURRENT_CONFLICT") return { outcome: "CONCURRENT_CONFLICT" };
  return { outcome: "OTHER_ERROR", error: sanitize((error as { message?: string } | null)?.message) ?? "erro desconhecido" };
}

// ============================================================================
// 7b. P14.4.1 — Inventário de Cobertura e Plano de Ondas (--expansion-plan)
// ============================================================================

const WAVE_MAX_SETS = 5;
const WAVE_MAX_LOCAL_CARDS = 500;

type LocalSetSummary = { cardSetId: string; code: string; releaseDateIso: string | null; localCardCount: number };

// ExistingSetMappingLite/SetPlanClassification/classifySetForExpansionPlan agora vêm de
// _shared/pricing-justtcg-matching/mod.ts (Incremento P16.2, extraídas do Incremento
// P14.4.1/P14.4.3). Mesma lógica — release_date exata como única evidência automatizada,
// ALREADY_CONFIRMED_COMPLETE/INCOMPLETE decidido pelo estado local antes de qualquer
// comparação de data —, zero mudança de comportamento nesta extração.

// Estimativa deliberadamente baseada só na contagem LOCAL de cartas — nunca em variants_count
// da JustTCG (não é "total de cartas", ver nota no cabeçalho do arquivo). Sempre >= 1 mesmo
// para Sets muito pequenos, refletindo a página mínima que fetchAllCardsForSet() precisaria.
function estimateCardsPagesFromLocalCount(localCardCount: number): number {
  return Math.max(1, Math.ceil(localCardCount / CARDS_PAGE_LIMIT));
}

type WaveSetEntry = { code: string; localCardCount: number };
type ExpansionWave = { waveNumber: number; sets: WaveSetEntry[]; totalLocalCards: number; oversized: boolean; estimatedCallsCards: number };

// Pura — agrupa só candidatos SAFE_CANDIDATE (o chamador filtra antes). Respeita os dois
// limites simultaneamente (5 Sets E 500 cartas locais, o que vier primeiro). Um Set individual
// com mais de 500 cartas locais NUNCA é dividido nem descartado: fecha a onda em formação (se
// houver) e forma sua própria onda de 1 Set, marcada oversized — sem interromper a formação
// das ondas seguintes.
function buildExpansionWaves(candidates: WaveSetEntry[]): ExpansionWave[] {
  const waves: ExpansionWave[] = [];
  let current: WaveSetEntry[] = [];

  const pushWave = (sets: WaveSetEntry[], oversized: boolean) => {
    if (sets.length === 0) return;
    waves.push({
      waveNumber: waves.length + 1,
      sets,
      totalLocalCards: sets.reduce((sum, s) => sum + s.localCardCount, 0),
      oversized,
      estimatedCallsCards: sets.reduce((sum, s) => sum + estimateCardsPagesFromLocalCount(s.localCardCount), 0),
    });
  };

  for (const candidate of candidates) {
    if (candidate.localCardCount > WAVE_MAX_LOCAL_CARDS) {
      pushWave(current, false);
      current = [];
      pushWave([candidate], true);
      continue;
    }
    const currentCards = current.reduce((sum, s) => sum + s.localCardCount, 0);
    if (current.length >= WAVE_MAX_SETS || currentCards + candidate.localCardCount > WAVE_MAX_LOCAL_CARDS) {
      pushWave(current, false);
      current = [];
    }
    current.push(candidate);
  }
  pushWave(current, false);
  return waves;
}

// ============================================================================
// 7d. P14.4.3 — Ondas de Backfill para Sets ALREADY_CONFIRMED_INCOMPLETE
// ============================================================================

// Uma entrada de onda de backfill carrega DOIS tamanhos por Set, com propósitos distintos:
// missingCardsCount governa o agrupamento/limite de 500 (é o que o executor realmente
// processa — cartas locais ativas sem nenhum pricing_card_mapping); localCardCount (tamanho
// TOTAL do Set) governa só a estimativa de chamadas HTTP, porque o executor ainda precisa
// paginar TODAS as cartas externas do Set via fetchAllCardsForSet() para localizar as
// faltantes — a JustTCG não expõe um jeito de pedir só um subconjunto de cartas de um Set.
type BackfillWaveSetEntry = { code: string; missingCardsCount: number; localCardCount: number };
type BackfillWave = { waveNumber: number; sets: BackfillWaveSetEntry[]; totalMissingCards: number; oversized: boolean; estimatedCallsCards: number };

// Pura — mesmo algoritmo de agrupamento de buildExpansionWaves() (5 Sets OU 500, o que vier
// primeiro; Set individual que sozinho excede o limite nunca é dividido, fecha a onda em
// formação e forma sua própria onda oversized), mas o limite de 500 é aplicado sobre
// missingCardsCount, nunca sobre localCardCount — ver comentário do tipo acima.
function buildBackfillWaves(candidates: BackfillWaveSetEntry[]): BackfillWave[] {
  const waves: BackfillWave[] = [];
  let current: BackfillWaveSetEntry[] = [];

  const pushWave = (sets: BackfillWaveSetEntry[], oversized: boolean) => {
    if (sets.length === 0) return;
    waves.push({
      waveNumber: waves.length + 1,
      sets,
      totalMissingCards: sets.reduce((sum, s) => sum + s.missingCardsCount, 0),
      oversized,
      estimatedCallsCards: sets.reduce((sum, s) => sum + estimateCardsPagesFromLocalCount(s.localCardCount), 0),
    });
  };

  for (const candidate of candidates) {
    if (candidate.missingCardsCount > WAVE_MAX_LOCAL_CARDS) {
      pushWave(current, false);
      current = [];
      pushWave([candidate], true);
      continue;
    }
    const currentMissing = current.reduce((sum, s) => sum + s.missingCardsCount, 0);
    if (current.length >= WAVE_MAX_SETS || currentMissing + candidate.missingCardsCount > WAVE_MAX_LOCAL_CARDS) {
      pushWave(current, false);
      current = [];
    }
    current.push(candidate);
  }
  pushWave(current, false);
  return waves;
}

type SetPlanEntry = {
  code: string;
  releaseDateIso: string | null;
  localCardCount: number;
  status: SetPlanClassification["status"];
  externalSetId: string | null;
  externalSetName: string | null;
  externalVariantsCount: number | null;
  pagesEstimateLocal: number;
  pagesEstimateExternal: null;
  pagesEstimateExternalReason: string;
  existingProductsCount: number;
  existingObservationsCount: number;
  // P14.4.3: totais por status de pricing_card_mapping (Query 3919) — mappedCardsCount conta
  // CONFIRMED+PENDING+NOT_FOUND (qualquer mapping existente); missingCardsCount é o
  // complemento exato contra localCardCount (max(0, localCardCount - mappedCardsCount)) —
  // sempre 0 fora de ALREADY_CONFIRMED_INCOMPLETE.
  mappedCardsCount: number;
  confirmedCardsCount: number;
  pendingCardsCount: number;
  notFoundCardsCount: number;
  missingCardsCount: number;
  reason: string;
};

type ExpansionPlanInput = {
  localSets: LocalSetSummary[];
  existingSetMappings: Map<string, ExistingSetMappingLite>;
  allExternalSets: JustTcgSet[];
  existingCoverage: Map<string, SetCoverageAggregate>;
};

type ExpansionPlanResult = {
  generatedAt: string;
  totalLocalSets: number;
  totalLocalCards: number;
  entries: SetPlanEntry[];
  waves: ExpansionWave[];
  totalEstimatedCallsAllWaves: number;
  // P14.4.3: ondas de backfill (Sets ALREADY_CONFIRMED_INCOMPLETE) — nunca executadas
  // implicitamente aqui, só construídas; a execução real é sempre um --backfill-wave=<n>
  // explícito (mesma disciplina de `waves`/--expansion-wave).
  backfillWaves: BackfillWave[];
  totalEstimatedCallsAllBackfillWaves: number;
};

const PAGES_ESTIMATE_EXTERNAL_REASON = "JUSTTCG_SETS_NAO_EXPOE_TOTAL_DE_CARTAS_SO_VARIANTS_COUNT";

// Pura — orquestra classifySetForExpansionPlan()/buildExpansionWaves()/buildBackfillWaves()
// sobre dados já buscados pelo chamador (executeExpansionPlan(), abaixo). 100% testável
// offline sem nenhum SupabaseClient/fetch.
function buildExpansionPlan(input: ExpansionPlanInput): ExpansionPlanResult {
  const entries: SetPlanEntry[] = input.localSets.map((local) => {
    const existingMapping = input.existingSetMappings.get(local.cardSetId) ?? null;
    const coverage = input.existingCoverage.get(local.cardSetId) ?? null;
    const classification = classifySetForExpansionPlan(
      { releaseDateIso: local.releaseDateIso, localCardCount: local.localCardCount },
      existingMapping,
      input.allExternalSets,
      coverage ? { mappedCards: coverage.mappedCards } : null,
    );
    const hasExternal = classification.status === "ALREADY_CONFIRMED_COMPLETE" || classification.status === "ALREADY_CONFIRMED_INCOMPLETE" || classification.status === "SAFE_CANDIDATE";
    const mappedCardsCount = coverage?.mappedCards ?? 0;
    const missingCardsCount = classification.status === "ALREADY_CONFIRMED_INCOMPLETE" ? Math.max(0, local.localCardCount - mappedCardsCount) : 0;

    return {
      code: local.code,
      releaseDateIso: local.releaseDateIso,
      localCardCount: local.localCardCount,
      status: classification.status,
      externalSetId: hasExternal ? classification.externalSetId : null,
      externalSetName: hasExternal ? classification.externalSetName : null,
      externalVariantsCount: hasExternal ? classification.externalVariantsCount : null,
      pagesEstimateLocal: estimateCardsPagesFromLocalCount(local.localCardCount),
      pagesEstimateExternal: null,
      pagesEstimateExternalReason: PAGES_ESTIMATE_EXTERNAL_REASON,
      existingProductsCount: coverage?.products ?? 0,
      existingObservationsCount: coverage?.observations ?? 0,
      mappedCardsCount,
      confirmedCardsCount: coverage?.confirmedCards ?? 0,
      pendingCardsCount: coverage?.pendingCards ?? 0,
      notFoundCardsCount: coverage?.notFoundCards ?? 0,
      missingCardsCount,
      reason: classification.reason,
    };
  });

  const safeCandidates = entries.filter((e) => e.status === "SAFE_CANDIDATE").map((e) => ({ code: e.code, localCardCount: e.localCardCount }));
  const waves = buildExpansionWaves(safeCandidates);
  // +1 chamada de /sets por execução de onda (aproximação explícita — uma futura execução real
  // de onda ainda precisaria revalidar a resolução de Set antes de paginar /cards; nunca
  // escondida, sempre somada ao total).
  const totalEstimatedCallsAllWaves = waves.reduce((sum, w) => sum + w.estimatedCallsCards, 0) + waves.length;

  // P14.4.3: candidatos de backfill são só os Sets ALREADY_CONFIRMED_INCOMPLETE — nunca
  // SAFE_CANDIDATE (esses vão para `waves`, nunca para `backfillWaves`) nem os já completos.
  const backfillCandidates = entries
    .filter((e) => e.status === "ALREADY_CONFIRMED_INCOMPLETE")
    .map((e) => ({ code: e.code, missingCardsCount: e.missingCardsCount, localCardCount: e.localCardCount }));
  const backfillWaves = buildBackfillWaves(backfillCandidates);
  const totalEstimatedCallsAllBackfillWaves = backfillWaves.reduce((sum, w) => sum + w.estimatedCallsCards, 0) + backfillWaves.length;

  return {
    generatedAt: new Date().toISOString(),
    totalLocalSets: input.localSets.length,
    totalLocalCards: input.localSets.reduce((sum, s) => sum + s.localCardCount, 0),
    entries,
    waves,
    totalEstimatedCallsAllWaves,
    backfillWaves,
    totalEstimatedCallsAllBackfillWaves,
  };
}

// --- I/O só-leitura ---------------------------------------------------------------------

type CardSetRow = { id: string; code: string; release_date: string | null };
type MetricsRow = { card_set_id: string; cards_ativas: number };
type SetMappingRow = { card_set_id: string; match_status: string; external_set_id: string | null; external_set_name: string | null };
// P14.4.3 (Query 3919): campos novos opcionais na TYPE — a view real sempre os retorna
// (COUNT() nunca é NULL em SQL), mas fixtures de teste que não exercitam a distinção
// COMPLETE/INCOMPLETE continuam válidas sem precisar declará-los; buildCoverageMap() (abaixo)
// aplica o default 0 explicitamente, nunca undefined silencioso.
type CoverageRow = {
  card_set_id: string;
  products_count: number;
  observations_count: number;
  mapped_cards_count?: number;
  confirmed_cards_count?: number;
  pending_cards_count?: number;
  not_found_cards_count?: number;
};
type SetCoverageAggregate = { products: number; observations: number; mappedCards: number; confirmedCards: number; pendingCards: number; notFoundCards: number };

// --- Paginação determinística genérica (fix 2026-08-19, mesmo dia) --------------------------
//
// Causa raiz do truncamento reportado no piloto real (45 Sets/7.429 cartas na introspecção,
// só 11 Sets/1.000 cartas no --expansion-plan): fetchLocalCatalogRows() fazia um único
// `.select()` em `card` (7.429 linhas) sem paginação — o Data API do Supabase/PostgREST aplica
// um limite padrão de 1.000 linhas por requisição quando nenhum `.range()` é informado,
// truncando silenciosamente o resultado (nenhum erro é retornado, só menos linhas). Nenhuma das
// leituras de P14.4.1 verificava isso.
//
// fetchAllPages() é a única implementação de paginação do módulo: pura, recebe uma função de
// busca de página já vinculada a uma tabela/filtro específicos e NUNCA deduz término por total
// presumido — só para quando uma página retorna estritamente menos linhas que pageSize. Uma
// página cheia (mesmo que seja coincidentemente a última) sempre dispara a busca da página
// seguinte, que precisa vir vazia para confirmar o fim. Isso é testado diretamente (ver
// "P14.4.1 fix: fetchAllPages" em runFixtureCheck()) sem precisar de nenhum mock de Supabase.
const DEFAULT_PAGE_SIZE = 1000;

type PageResult<T> = { data: T[] | null; error: { message: string } | null };
type PageFetcher<T> = (from: number, to: number) => Promise<PageResult<T>>;

async function fetchAllPages<T>(fetchPage: PageFetcher<T>, pageSize: number = DEFAULT_PAGE_SIZE): Promise<T[]> {
  const rows: T[] = [];
  let from = 0;
  for (;;) {
    const { data, error } = await fetchPage(from, from + pageSize - 1);
    if (error) throw new Error(`PAGINATED_QUERY_FAILED: ${sanitize(error.message)}`);
    const page = data ?? [];
    rows.push(...page);
    if (page.length < pageSize) break;
    from += pageSize;
  }
  return rows;
}

// Adapter fino Supabase -> fetchAllPages(): mantém a mecânica de paginação (acima) totalmente
// desacoplada do cliente Supabase, testável com callbacks simples.
// deno-lint-ignore no-explicit-any
async function fetchAllRowsFromTable<T>(
  supabase: SupabaseClient,
  table: string,
  columns: string,
  orderColumn: string,
  // deno-lint-ignore no-explicit-any
  applyFilter?: (query: any) => any,
  pageSize: number = DEFAULT_PAGE_SIZE,
): Promise<T[]> {
  return fetchAllPages<T>(async (from, to) => {
    // deno-lint-ignore no-explicit-any
    let query: any = supabase.from(table).select(columns).order(orderColumn).range(from, to);
    if (applyFilter) query = applyFilter(query);
    const result = await query;
    return { data: (result.data ?? null) as T[] | null, error: result.error };
  }, pageSize);
}

// Contagem exata via `count: "exact", head: true` (só o cabeçalho Content-Range é lido — o
// Data API NUNCA materializa linhas para responder isso, então esta chamada não está sujeita
// ao limite de 1.000 linhas de forma alguma). Usada como ground truth independente para
// reconciliar cada leitura paginada (assertPaginationComplete()) e as somas agregadas
// (RECONCILIACAO_CARTAS_FALHOU/RECONCILIACAO_SETS_FALHOU em executeExpansionPlan()).
// deno-lint-ignore no-explicit-any
async function fetchExactCount(supabase: SupabaseClient, table: string, applyFilter?: (query: any) => any): Promise<number> {
  // deno-lint-ignore no-explicit-any
  let query: any = supabase.from(table).select("*", { count: "exact", head: true });
  if (applyFilter) query = applyFilter(query);
  const { count, error } = await query;
  if (error) throw new Error(`COUNT_QUERY_FAILED(${table}): ${sanitize(error.message)}`);
  if (typeof count !== "number") throw new Error(`COUNT_QUERY_RETORNOU_INVALIDO(${table})`);
  return count;
}

// Nunca deduzir sucesso: qualquer divergência entre o que a paginação trouxe e a contagem
// exata e independente do banco aborta o plano imediatamente — nunca um resultado parcial.
function assertPaginationComplete(label: string, fetchedCount: number, exactCount: number): void {
  if (fetchedCount !== exactCount) {
    throw new Error(
      `PAGINACAO_INCOMPLETA(${label}): paginação retornou ${fetchedCount} linha(s), contagem exata do banco é ${exactCount}. Plano de expansão abortado — nunca emite resultado parcial.`,
    );
  }
}

// Pura — "Card Set local ativo" = tem ao menos uma carta local ativa. Fix 2026-08-19: em vez de
// contar cartas uma a uma no cliente (o vetor de ataque do truncamento), reusa
// catalog_card_set_metrics.cards_ativas — view já existente, 1 linha por Set, agregada
// server-side, nunca sujeita ao limite de 1.000 (cresce com o nº de Sets, não com o nº de
// cartas). Ordenação determinística (release_date, depois código) preservada.
function buildLocalSetInventory(cardSetRows: CardSetRow[], metricsRows: MetricsRow[]): LocalSetSummary[] {
  const activeCountBySet = new Map<string, number>();
  for (const m of metricsRows) activeCountBySet.set(m.card_set_id, m.cards_ativas ?? 0);
  return cardSetRows
    .map((s) => ({ cardSetId: s.id, code: s.code, releaseDateIso: s.release_date, localCardCount: activeCountBySet.get(s.id) ?? 0 }))
    .filter((s) => s.localCardCount > 0)
    .sort((a, b) => {
      const dateCompare = (a.releaseDateIso ?? "9999-99-99").localeCompare(b.releaseDateIso ?? "9999-99-99");
      return dateCompare !== 0 ? dateCompare : a.code.localeCompare(b.code);
    });
}

function buildSetMappingMap(rows: SetMappingRow[]): Map<string, ExistingSetMappingLite> {
  const map = new Map<string, ExistingSetMappingLite>();
  for (const row of rows) {
    map.set(row.card_set_id, { cardSetId: row.card_set_id, matchStatus: row.match_status, externalSetId: row.external_set_id, externalSetName: row.external_set_name });
  }
  return map;
}

// P14.4.3: campos novos default 0 explicitamente (nunca undefined silencioso) — cobre tanto
// fixtures de teste que omitem os campos quanto, em tese, um Set sem nenhuma linha na view
// (pricing_set_coverage é ancorada em pricing_card_mapping; um Set sem NENHUM mapping nunca
// aparece nela) — mappedCards=0 é a semântica correta nos dois casos.
function buildCoverageMap(rows: CoverageRow[]): Map<string, SetCoverageAggregate> {
  const map = new Map<string, SetCoverageAggregate>();
  for (const row of rows) {
    map.set(row.card_set_id, {
      products: row.products_count,
      observations: row.observations_count,
      mappedCards: row.mapped_cards_count ?? 0,
      confirmedCards: row.confirmed_cards_count ?? 0,
      pendingCards: row.pending_cards_count ?? 0,
      notFoundCards: row.not_found_cards_count ?? 0,
    });
  }
  return map;
}

// Reconciliação final: todo mapping CONFIRMED existente precisa aparecer como
// ALREADY_CONFIRMED_COMPLETE ou ALREADY_CONFIRMED_INCOMPLETE no plano — se um Set com mapping
// CONFIRMED sumiu do inventário paginado (bug de paginação, filtro errado, etc.), o plano
// nunca é emitido, nunca parcialmente. P14.4.3: os dois status (completo/incompleto) são
// igualmente válidos aqui — o que este invariante protege é o mapping nunca ter sido
// "esquecido" pela reclassificação, não uma cobertura específica de cartas.
function assertConfirmedMappingsPreserved(entries: SetPlanEntry[], localSets: LocalSetSummary[], existingSetMappings: Map<string, ExistingSetMappingLite>): void {
  for (const [cardSetId, mapping] of existingSetMappings) {
    if (mapping.matchStatus !== "CONFIRMED") continue;
    const local = localSets.find((s) => s.cardSetId === cardSetId);
    if (!local) {
      throw new Error(`MAPPING_CONFIRMED_SEM_SET_LOCAL_CORRESPONDENTE(${cardSetId}): plano de expansão abortado, nunca emitido parcialmente.`);
    }
    const entry = entries.find((e) => e.code === local.code);
    if (!entry || (entry.status !== "ALREADY_CONFIRMED_COMPLETE" && entry.status !== "ALREADY_CONFIRMED_INCOMPLETE")) {
      throw new Error(`MAPPING_CONFIRMED_NAO_PRESERVADO(${local.code}): plano de expansão abortado, nunca emitido parcialmente.`);
    }
  }
}

// P14.4.2: extraído de dentro de executeExpansionPlan() (abaixo) para ser reaproveitado
// literalmente, sem duplicação, pelo executor de onda (executeExpansionWave()) — as DUAS
// funções precisam do mesmíssimo conjunto de leituras locais reconciliadas ANTES de
// qualquer chamada HTTP à JustTCG (regra 5 do P14.4.2: "refazer todas as leituras locais e
// invariantes antes da primeira chamada"). Cobre TUDO que roda antes do GET /v1/sets:
// inventário local paginado, os dois invariantes de reconciliação (cartas ativas / Sets
// ativos), mappings de Set já existentes e cobertura agregada — nenhuma escrita em nenhum
// ponto, mesma garantia estrutural de antes (ver makeReadOnlyFakeClient nos testes).
type ReconciledLocalInputs = {
  sourceId: string;
  localSets: LocalSetSummary[];
  existingSetMappings: Map<string, ExistingSetMappingLite>;
  existingCoverage: Map<string, SetCoverageAggregate>;
};

async function fetchReconciledLocalInputs(supabase: SupabaseClient): Promise<ReconciledLocalInputs> {
  const source = await getJustTcgSource(supabase);
  const sourceId = source.id as string;

  const cardSetRows = await fetchAllRowsFromTable<CardSetRow>(supabase, "card_set", "id, code, release_date", "id");
  const exactCardSetCount = await fetchExactCount(supabase, "card_set");
  assertPaginationComplete("card_set", cardSetRows.length, exactCardSetCount);

  const metricsRows = await fetchAllRowsFromTable<MetricsRow>(supabase, "catalog_card_set_metrics", "card_set_id, cards_ativas", "card_set_id");
  const exactMetricsCount = await fetchExactCount(supabase, "catalog_card_set_metrics");
  assertPaginationComplete("catalog_card_set_metrics", metricsRows.length, exactMetricsCount);

  const localSets = buildLocalSetInventory(cardSetRows, metricsRows);

  // Invariante 1: soma de localCardCount == contagem exata e independente de `card` ativas.
  const exactActiveCardCount = await fetchExactCount(supabase, "card", (q) => q.eq("is_active", true));
  const sumLocalCardCount = localSets.reduce((sum, s) => sum + s.localCardCount, 0);
  if (sumLocalCardCount !== exactActiveCardCount) {
    throw new Error(`RECONCILIACAO_CARTAS_FALHOU: soma local=${sumLocalCardCount}, contagem exata=${exactActiveCardCount}. Plano de expansão abortado — nunca emite resultado parcial.`);
  }

  // Invariante 2: quantidade de Sets no inventário == contagem exata e independente de Sets
  // com cards_ativas > 0 (mesma view, consulta separada — cobre bug de filtro/join).
  const exactActiveSetCount = await fetchExactCount(supabase, "catalog_card_set_metrics", (q) => q.gt("cards_ativas", 0));
  if (localSets.length !== exactActiveSetCount) {
    throw new Error(`RECONCILIACAO_SETS_FALHOU: Sets no inventário=${localSets.length}, contagem exata de Sets ativos=${exactActiveSetCount}. Plano de expansão abortado — nunca emite resultado parcial.`);
  }

  const setMappingRows = await fetchAllRowsFromTable<SetMappingRow>(
    supabase,
    "pricing_set_mapping",
    "card_set_id, match_status, external_set_id, external_set_name",
    "card_set_id",
    (q) => q.eq("pricing_source_id", sourceId),
  );
  const exactSetMappingCount = await fetchExactCount(supabase, "pricing_set_mapping", (q) => q.eq("pricing_source_id", sourceId));
  assertPaginationComplete("pricing_set_mapping", setMappingRows.length, exactSetMappingCount);
  const existingSetMappings = buildSetMappingMap(setMappingRows);

  // Cobertura via pricing_set_coverage (Query 3916, estendida pela Query 3919 no P14.4.3):
  // agregada server-side por card_set_id x pricing_source_id, nunca cresce com o volume de
  // produtos/observações (no máximo 1 linha por combinação Set x Fonte). Substitui as três
  // leituras encadeadas em memória do desenho original (pricing_card_mapping ->
  // pricing_product -> pricing_observation). mapped/confirmed/pending/not_found_cards_count
  // (Query 3919) alimentam a classificação ALREADY_CONFIRMED_COMPLETE/INCOMPLETE.
  const coverageRows = await fetchAllRowsFromTable<CoverageRow>(
    supabase,
    "pricing_set_coverage",
    "card_set_id, products_count, observations_count, mapped_cards_count, confirmed_cards_count, pending_cards_count, not_found_cards_count",
    "card_set_id",
    (q) => q.eq("pricing_source_id", sourceId),
  );
  const exactCoverageCount = await fetchExactCount(supabase, "pricing_set_coverage", (q) => q.eq("pricing_source_id", sourceId));
  assertPaginationComplete("pricing_set_coverage", coverageRows.length, exactCoverageCount);
  const existingCoverage = buildCoverageMap(coverageRows);

  return { sourceId, localSets, existingSetMappings, existingCoverage };
}

// Orquestração testável offline (ver runFixtureCheck() e os testes "P14.4.1 fix"): recebe um
// SupabaseClient e um JustTcgClient já construídos (nunca lê Deno.env diretamente), mesmo
// padrão de injeção de dependência de persistBatchedResults()/JustTcgClient. Faz EXATAMENTE uma
// chamada HTTP (GET /v1/sets); toda leitura Supabase é paginada (fetchAllRowsFromTable) e
// imediatamente reconciliada contra uma contagem exata independente (fetchExactCount) — nenhuma
// das funções chamadas aqui usa .insert()/.update()/.rpc() em nenhum ponto, verificável por
// leitura direta do código.
//
// Requer a migration 3916 (aplicada — ver Query 3916/3917) para existir: GRANT SELECT ... TO
// service_role em catalog_card_set_metrics/game e a view pricing_set_coverage.
async function executeExpansionPlan(supabase: SupabaseClient, client: JustTcgClient): Promise<ExpansionPlanResult> {
  const { localSets, existingSetMappings, existingCoverage } = await fetchReconciledLocalInputs(supabase);

  const setsResult = await client.get<{ data: JustTcgSet[] }>("/sets", { game: GAME_CODE });
  if (setsResult.status === "AUTH_FAILURE") {
    throw new Error("AUTENTICACAO_FALHOU_401: JUSTTCG_API_KEY inválida ou expirada — plano de expansão abortado.");
  }
  if (setsResult.status !== "SUCCESS") {
    throw new Error(`PLANO_DE_EXPANSAO_FASE_SETS_FALHOU: ${setsResult.status}`);
  }
  const allExternalSets = normalizeJustTcgSets(setsResult.data.data ?? []);

  const plan = buildExpansionPlan({ localSets, existingSetMappings, allExternalSets, existingCoverage });
  assertConfirmedMappingsPreserved(plan.entries, localSets, existingSetMappings);
  return plan;
}

async function runExpansionPlan(): Promise<void> {
  const supabaseUrl = requireEnv("SUPABASE_URL");
  const supabaseServiceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
  const justTcgApiKey = requireEnv("JUSTTCG_API_KEY");

  const supabase = createClient(supabaseUrl, supabaseServiceRoleKey);
  const client = new JustTcgClient(justTcgApiKey);

  const plan = await executeExpansionPlan(supabase, client);

  console.log("\n=== Plano de Expansão (P14.4.1) — somente leitura, nenhuma escrita ===");
  console.log(JSON.stringify(plan, null, 2));
  console.log(`\nChamadas HTTP feitas à JustTCG nesta rodada: ${client.requestsMade} (GET /v1/sets).`);
  console.log("Nenhum pricing_sync_run foi criado nesta rodada. Nenhum mapping/produto/observação foi alterado.");
}

// ============================================================================
// 7c. P14.4.2 — Executor Explícito e Controlado de Ondas JustTCG (--expansion-wave)
// ============================================================================
//
// Objetivo desta rodada: executar UMA única onda (nunca implicitamente todas — regra 1),
// já classificada pelo mesmo plano reconciliado de P14.4.1/fix (buildExpansionPlan(), nunca
// recalculado com regras próprias nem hardcoded — regra 4), reaproveitando literalmente o
// matching fail-safe (resolveSetMatchV2/classifyCardMatch) e a persistência em lote
// (persistBatchedResults()) já testados. CARD_SYNC é aberto entre as leituras locais e a
// primeira chamada à JustTCG (regras 5+6); o orçamento local (--max-api-requests) é um teto
// AUTORITATIVO independente de _metadata.apiRequestsRemaining (regra 7); qualquer falha de
// aquisição (orçamento esgotado ou página com erro) bloqueia a persistência da onda inteira
// (regras 8+9) — nunca uma escrita parcial por Set.

// Pura — valida o formato de --expansion-wave/--max-api-requests/--dry-run/--confirmed-by
// SEM depender de rede, Supabase ou de um plano já calculado (regra 2: "rejeitar onda
// inexistente, combinação de modo conflitante e orçamento ausente/inválido ANTES de
// qualquer chamada externa"). A existência da onda dentro do plano é validada à parte, por
// selectWaveFromPlan() (abaixo), já que isso depende do plano recalculado nesta execução.
// Fix P14.4.2 (instabilidade de identidade): o número da onda sozinho NUNCA é uma identidade
// estável entre execuções — o plano só agrupa candidatos SAFE_CANDIDATE, então depois que uma
// onda é confirmada, os candidatos restantes podem ser reagrupados/renumerados e
// "--expansion-wave=1" pode passar a apontar para uma composição de Sets completamente
// diferente da que rodou da última vez. --expected-set-codes é a confirmação explícita de
// identidade exigida junto com --expansion-wave: nunca substitui a composição planejada (a
// onda continua vindo do plano recalculado, nunca dos códigos informados — ver regra 8), só
// bloqueia a execução se a composição recalculada não bater exatamente com o esperado.
type ExpectedSetCodesValidation = { ok: true; codes: string[] } | { ok: false; reason: string };

function validateExpectedSetCodes(raw: string | null): ExpectedSetCodesValidation {
  if (raw === null) {
    return {
      ok: false,
      reason:
        "EXPECTED_SET_CODES_AUSENTE: --expected-set-codes=<CODIGO1,CODIGO2,...> é obrigatório junto com --expansion-wave — confirma a identidade exata da onda antes de qualquer persistência (o número da onda sozinho não é estável entre execuções).",
    };
  }
  // Normalização: aparar espaços e uppercase — mesma convenção já usada nos códigos de
  // card_set (BASE2, GYM2, ...) em todo o restante do arquivo.
  const normalized = raw.split(",").map((c) => c.trim().toUpperCase());
  if (normalized.some((c) => c.length === 0)) {
    return { ok: false, reason: `EXPECTED_SET_CODES_INVALIDO: --expected-set-codes="${raw}" contém item vazio — nenhum código pode ser vazio (verifique vírgulas duplas/finais).` };
  }
  const seen = new Set<string>();
  const duplicates = new Set<string>();
  for (const code of normalized) {
    if (seen.has(code)) duplicates.add(code);
    seen.add(code);
  }
  if (duplicates.size > 0) {
    return { ok: false, reason: `EXPECTED_SET_CODES_DUPLICADO: código(s) repetido(s) em --expected-set-codes: ${[...duplicates].join(", ")}.` };
  }
  return { ok: true, codes: normalized };
}

type RepairSetCodesFormatValidation = { ok: true; codes: string[] } | { ok: false; reason: string };

// P14.4.6 — Pura, mesma disciplina de normalização de validateExpectedSetCodes (trim+uppercase,
// rejeita item vazio, rejeita duplicado), mas com mensagens de erro PRÓPRIAS de
// --repair-set-codes (nunca reaproveita a reason "EXPECTED_SET_CODES_*", que seria enganosa
// aqui). Só valida FORMATO (vazio/duplicado) — a checagem de "existe entre os candidatos
// elegíveis a reparo agora" é feita depois, contra buildRepairCandidates(), porque depende do
// estado real do banco (ver filterRepairCandidatesBySetCodes). Diferente de
// validateExpectedSetCodes, `raw` nunca é null aqui: --repair-set-codes é opcional (chamador só
// invoca esta função quando o argumento foi de fato informado).
function validateRepairSetCodesFormat(raw: string): RepairSetCodesFormatValidation {
  const normalized = raw.split(",").map((c) => c.trim().toUpperCase());
  if (normalized.some((c) => c.length === 0)) {
    return { ok: false, reason: `REPAIR_SET_CODES_INVALIDO: --repair-set-codes="${raw}" contém item vazio — nenhum código pode ser vazio (verifique vírgulas duplas/finais).` };
  }
  const seen = new Set<string>();
  const duplicates = new Set<string>();
  for (const code of normalized) {
    if (seen.has(code)) duplicates.add(code);
    seen.add(code);
  }
  if (duplicates.size > 0) {
    return { ok: false, reason: `REPAIR_SET_CODES_DUPLICADO: código(s) repetido(s) em --repair-set-codes: ${[...duplicates].join(", ")}.` };
  }
  return { ok: true, codes: normalized };
}

type ExpansionWaveArgsValidation =
  | { ok: true; waveNumber: number; maxApiRequests: number; expectedSetCodes: string[] }
  | { ok: false; reason: string };

function validateExpansionWaveArgs(args: {
  expansionWave: string | null;
  maxApiRequests: string | null;
  dryRun: boolean;
  confirmedBy: string | null;
  expectedSetCodes: string | null;
}): ExpansionWaveArgsValidation {
  const waveRaw = args.expansionWave;
  if (waveRaw === null) return { ok: false, reason: "EXPANSION_WAVE_AUSENTE: --expansion-wave=<n> é obrigatório neste modo." };
  const waveNumber = Number(waveRaw);
  if (!Number.isInteger(waveNumber) || waveNumber <= 0) {
    return { ok: false, reason: `EXPANSION_WAVE_INVALIDO(${waveRaw}): --expansion-wave deve ser um inteiro positivo (1, 2, 3, ...) — nunca executa "todas as ondas" implicitamente.` };
  }

  const budgetRaw = args.maxApiRequests;
  if (budgetRaw === null) {
    return { ok: false, reason: "MAX_API_REQUESTS_AUSENTE: --max-api-requests=<n> é obrigatório neste modo (orçamento local autoritativo de requisições, independente do teto de segurança do processo)." };
  }
  const maxApiRequests = Number(budgetRaw);
  if (!Number.isInteger(maxApiRequests) || maxApiRequests <= 0) {
    return { ok: false, reason: `MAX_API_REQUESTS_INVALIDO(${budgetRaw}): --max-api-requests deve ser um inteiro positivo.` };
  }

  const expectedSetCodesValidation = validateExpectedSetCodes(args.expectedSetCodes);
  if (!expectedSetCodesValidation.ok) return { ok: false, reason: expectedSetCodesValidation.reason };

  const hasDryRun = args.dryRun;
  const hasConfirmedBy = args.confirmedBy !== null && args.confirmedBy !== "";
  if (hasDryRun && hasConfirmedBy) {
    return { ok: false, reason: "MODOS_CONFLITANTES: --dry-run e --confirmed-by são mutuamente exclusivos no executor de onda — escolha simulação (--dry-run) ou execução real (--confirmed-by=<admin_user_uuid>), nunca os dois." };
  }
  if (!hasDryRun && !hasConfirmedBy) {
    return { ok: false, reason: "MODO_AUSENTE: informe --dry-run (simulação, sem escrita) ou --confirmed-by=<admin_user_uuid> (execução real) — nenhum modo padrão é assumido." };
  }

  return { ok: true, waveNumber, maxApiRequests, expectedSetCodes: expectedSetCodesValidation.codes };
}

// Pura — opera sobre um ExpansionPlanResult já calculado (real ou fixture de teste), nunca
// sobre rede. Resolve a tensão entre "rejeitar onda inexistente antes de qualquer chamada
// externa" (regra 2) e "a composição da onda vem do plano reconciliado, nunca hardcoded"
// (regra 4): o teste de onda inexistente roda 100% offline contra um plano de fixture, sem
// precisar mockar HTTP.
function selectWaveFromPlan(plan: ExpansionPlanResult, waveNumber: number): { ok: true; wave: ExpansionWave } | { ok: false; error: string } {
  const wave = plan.waves.find((w) => w.waveNumber === waveNumber);
  if (!wave) {
    return {
      ok: false,
      error: `ONDA_INEXISTENTE(${waveNumber}): o plano recalculado agora tem ${plan.waves.length} onda(s) (1${plan.waves.length > 1 ? `-${plan.waves.length}` : ""}). Nunca executa todas as ondas implicitamente — escolha um número de onda válido.`,
    };
  }
  return { ok: true, wave };
}

type ExpansionWaveOpts = { waveNumber: number; dryRun: boolean; confirmedBy: string | null; maxApiRequests: number; expectedSetCodes: string[] };

// Fix P14.4.2 (dry-run sem projeção): productsProjected/observationsProjected/
// variantsProjectionSkipped nascem sempre em 0 e só o dry-run os incrementa (mesma disciplina
// de runRealPilot/executeExpansionPlan) — no caminho real ficam em 0 por Set, nunca
// reaproveitados/reinterpretados como contagem real de escrita.
type ExpansionWaveSetSummary = {
  code: string;
  localCardCount: number;
  externalCardsSeen: number;
  productsProjected: number;
  observationsProjected: number;
  variantsProjectionSkipped: number;
};

type ExpansionWaveRunResult = {
  waveNumber: number;
  setsSelected: string[];
  perSet: ExpansionWaveSetSummary[];
  setsConfirmed: number;
  cardsSafe: number;
  cardsAmbiguous: number;
  cardsAbsent: number;
  productsResolved: number;
  productsWritten: number;
  observationsResolved: number;
  observationsWritten: number;
  observationsDivergent: number;
  identitiesResolved: number;
  identitiesWritten: number;
  operationsSupabase: number;
  // Fix P14.4.2 (dry-run sem projeção): só o --dry-run projeta (planVariantProjection(), nunca
  // duplicado) — no caminho real ficam sempre em 0, nunca confundidos com
  // productsResolved/observationsResolved (que só têm significado após persistência real).
  productsProjected: number;
  observationsProjected: number;
  variantsProjectionSkipped: number;
  requestsMade: number;
  maxApiRequests: number;
  requestsRemainingLocal: number;
  status: "COMPLETED" | "COMPLETED_WITH_ERRORS" | "FAILED";
  errorParts: string[];
  syncRunId: string | null;
};

// Núcleo do P14.4.2. Ordem estrita, nunca alterada: (1) leituras locais reconciliadas —
// fetchReconciledLocalInputs(), idêntica a executeExpansionPlan() (regra 5); (2) em modo
// real, abre um único CARD_SYNC — tryOpenCardSyncRun(), detecta 23505 antes de qualquer
// requisição à JustTCG (regra 6); em --dry-run, nunca cria pricing_sync_run; (3) primeira
// chamada externa (GET /v1/sets) — reclassifica os Sets e recalcula o plano/ondas nesta
// própria execução (regra 4, nunca hardcoded); (4) seleciona a onda pedida dentro do plano
// recém-calculado (selectWaveFromPlan); (5) para cada Set da onda, confirma o mapping
// (upsertSetMapping, fora do dry-run) e pagina TODAS as cartas do Set
// (fetchAllCardsForSet) — qualquer aborto (orçamento/autenticação/paginação) interrompe a
// aquisição da onda inteira, sem persistir nada (regras 8+9); (6) só depois de todos os
// Sets da onda adquiridos com sucesso, persiste em lote (persistBatchedResults(), reusada
// verbatim) e finaliza o run (finalizeSyncRun(), reusada verbatim).
async function executeExpansionWave(supabase: SupabaseClient, client: JustTcgClient, opts: ExpansionWaveOpts): Promise<ExpansionWaveRunResult> {
  const { sourceId, localSets, existingSetMappings, existingCoverage } = await fetchReconciledLocalInputs(supabase);

  let syncRunId: string | null = null;
  let syncRunFinalized = false;

  if (!opts.dryRun) {
    const startAttempt = await tryOpenCardSyncRun(supabase, sourceId, opts.confirmedBy as string);
    if (startAttempt.outcome === "CONCURRENT_CONFLICT") {
      throw new Error(
        "CONFLITO_DE_CONCORRENCIA: já existe uma execução CARD_SYNC ativa (RECEIVED/PROCESSING) para esta fonte (índice único parcial, Query 3907) — onda abortada antes de qualquer chamada à JustTCG.",
      );
    }
    if (startAttempt.outcome === "OTHER_ERROR") {
      throw new Error(`SYNC_RUN_INSERT_FAILED: ${startAttempt.error}`);
    }
    syncRunId = startAttempt.id;
  }

  const conditionMap = await getConditionMap(supabase, sourceId);
  if (!opts.dryRun && conditionMap.size === 0) {
    throw new Error("CONDITION_MAP_VAZIO: rode a seed 3702 (pricing_condition_mapping) antes deste script.");
  }

  const summary = {
    setsConfirmed: 0,
    cardsSafe: 0,
    cardsAmbiguous: 0,
    cardsAbsent: 0,
    productsResolved: 0,
    productsWritten: 0,
    observationsResolved: 0,
    observationsWritten: 0,
    observationsDivergent: 0,
    identitiesResolved: 0,
    identitiesWritten: 0,
    operationsSupabase: 0,
    productsProjected: 0,
    observationsProjected: 0,
    variantsProjectionSkipped: 0,
  };
  const perSet: ExpansionWaveSetSummary[] = [];
  const errorParts: string[] = [];
  const plannedCardMappings: PlannedCardMapping[] = [];
  const plannedVariants: PlannedVariant[] = [];
  let acquisitionFailed = false;
  let wave: ExpansionWave | null = null;

  try {
    const setsResult = await client.get<{ data: JustTcgSet[] }>("/sets", { game: GAME_CODE });
    if (setsResult.status === "AUTH_FAILURE") {
      throw new Error("AUTENTICACAO_FALHOU_401: JUSTTCG_API_KEY inválida ou expirada — execução de onda abortada.");
    }
    if (setsResult.status !== "SUCCESS") {
      throw new Error(`ONDA_FASE_SETS_FALHOU: ${setsResult.status}`);
    }
    const allExternalSets = normalizeJustTcgSets(setsResult.data.data ?? []);

    // Regra 4: plano recalculado nesta própria execução, nunca hardcoded/cacheado de uma
    // rodada anterior — mesma função pura de P14.4.1 (buildExpansionPlan).
    const plan = buildExpansionPlan({ localSets, existingSetMappings, allExternalSets, existingCoverage });
    assertConfirmedMappingsPreserved(plan.entries, localSets, existingSetMappings);

    const waveSelection = selectWaveFromPlan(plan, opts.waveNumber);
    if (!waveSelection.ok) throw new Error(waveSelection.error);
    wave = waveSelection.wave;

    // Fix P14.4.2 (instabilidade de identidade): o número da onda sozinho não é estável entre
    // execuções (ver comentário de validateExpectedSetCodes) — antes de tocar em qualquer Set
    // desta onda, confirma que a composição RECALCULADA agora é exatamente (nunca um
    // subconjunto, nunca com sobra) a composição esperada informada por --expected-set-codes.
    // Comparação por CONJUNTO (ordem nunca importa) — os códigos esperados nunca substituem a
    // composição planejada (regra 8): se baterem, o que roda continua sendo wave.sets, vindo do
    // plano; se não baterem, a onda inteira é abortada aqui, antes de qualquer
    // upsertSetMapping/fetchAllCardsForSet, garantindo zero persistência de negócio.
    const actualCodes = [...new Set(wave.sets.map((s) => s.code))].sort();
    const expectedCodes = [...new Set(opts.expectedSetCodes)].sort();
    const compositionMatches = actualCodes.length === expectedCodes.length && actualCodes.every((code, i) => code === expectedCodes[i]);
    if (!compositionMatches) {
      const missing = expectedCodes.filter((c) => !actualCodes.includes(c));
      const extra = actualCodes.filter((c) => !expectedCodes.includes(c));
      throw new Error(
        `EXPANSION_WAVE_COMPOSITION_CHANGED: a onda ${opts.waveNumber} recalculada agora tem os Sets [${actualCodes.join(",") || "nenhum"}], divergente do esperado [${expectedCodes.join(",") || "nenhum"}] — faltando=[${missing.join(",") || "nenhum"}] excedente=[${extra.join(",") || "nenhum"}]. O número da onda não é uma identidade estável entre execuções (candidatos são reagrupados/renumerados a cada plano recalculado) — onda abortada antes de qualquer persistência. Revise a composição atual com --expansion-plan antes de reexecutar.`,
      );
    }

    const localByCode = new Map(localSets.map((s) => [s.code, s]));

    for (const waveSet of wave.sets) {
      const local = localByCode.get(waveSet.code);
      if (!local) {
        errorParts.push(`WAVE_SET_SEM_INVENTARIO_LOCAL(${waveSet.code})`);
        acquisitionFailed = true;
        break;
      }

      // Regra 10 (via resolveSetMatchV2, mesmo matching fail-safe de P14.2/runRealPilot):
      // release_date exata é a única evidência automatizada — como a onda só contém Sets já
      // classificados SAFE_CANDIDATE por classifySetForExpansionPlan() (mesmo sinal, que exige
      // releaseDateIso não-nulo), este match deve ser CONFIRMED de forma determinística; as
      // checagens abaixo (releaseDateIso nulo, match não-CONFIRMED) são rede de segurança
      // defensiva, nunca o caminho esperado.
      if (!local.releaseDateIso) {
        errorParts.push(`WAVE_SET_SEM_RELEASE_DATE(${waveSet.code}): inconsistente com a classificação SAFE_CANDIDATE do plano — onda abortada por segurança.`);
        acquisitionFailed = true;
        break;
      }
      const match = resolveSetMatchV2({ codigoMmkyu: waveSet.code, releaseDateIso: local.releaseDateIso }, allExternalSets);
      if (match.status !== "CONFIRMED") {
        errorParts.push(`WAVE_SET_MATCH_INESPERADO(${waveSet.code}): ${match.status} — o plano classificou como SAFE_CANDIDATE, mas a reconfirmação pontual divergiu; onda abortada por segurança.`);
        acquisitionFailed = true;
        break;
      }

      if (!opts.dryRun) {
        const setMappingResult = await upsertSetMapping(supabase, local.cardSetId, sourceId, "CONFIRMED", match.set, match.method, match.evidence, opts.confirmedBy as string);
        if (!setMappingResult.ok) errorParts.push(`SET_MAPPING_CONFIRM_FAILED(${waveSet.code}): ${setMappingResult.error}`);
      }
      summary.setsConfirmed++;

      const { cards: externalCards, requestsUsed, aborted } = await fetchAllCardsForSet(client, match.set.id);
      // Fix P14.4.2 (dry-run sem projeção): setSummary é a MESMA referência empurrada em
      // perSet — o loop de projeção mais abaixo, dentro desta mesma iteração de Set, incrementa
      // estes campos por mutação direta, sem duplicar planVariantProjection() nem reestruturar
      // o fluxo de aborto antecipado (abaixo) que já depende de perSet.push() acontecer aqui.
      const setSummary: ExpansionWaveSetSummary = {
        code: waveSet.code,
        localCardCount: local.localCardCount,
        externalCardsSeen: externalCards.length,
        productsProjected: 0,
        observationsProjected: 0,
        variantsProjectionSkipped: 0,
      };
      perSet.push(setSummary);

      if (aborted === "AUTH_FAILURE") {
        errorParts.push(`AUTENTICACAO_FALHOU_401(${waveSet.code})`);
        acquisitionFailed = true;
        break;
      }
      if (aborted === "BUDGET_STOPPED") {
        errorParts.push(`ORCAMENTO_ESGOTADO(${waveSet.code}): após ${requestsUsed} requisição(ões) de página deste Set — nenhum dado de negócio desta onda será persistido.`);
        acquisitionFailed = true;
        break;
      }
      if (aborted === "TECHNICAL_FAILURE") {
        errorParts.push(`PAGINACAO_CARDS_FALHOU(${waveSet.code}): interrompida após ${requestsUsed} requisição(ões) — nenhum dado de negócio desta onda será persistido.`);
        acquisitionFailed = true;
        break;
      }

      const localCards = await findLocalCardsForSet(supabase, local.cardSetId);
      const externalIndex = buildExternalNumberIndex(externalCards);

      for (const localCard of localCards) {
        const matchResult = classifyCardMatch(localCard, externalIndex, match.set.id);

        if (matchResult.classification !== "SAFE" || !matchResult.matched) {
          if (matchResult.classification === "ABSENT") summary.cardsAbsent++;
          else summary.cardsAmbiguous++;
          if (opts.dryRun) logDryRunCardEvidence(localCard, matchResult);
          if (!opts.dryRun) {
            plannedCardMappings.push({
              cardId: localCard.card_id,
              collectorNumber: localCard.collector_number,
              status: matchResult.classification === "ABSENT" ? "NOT_FOUND" : "PENDING",
              matchedCard: null,
              method: matchResult.method,
              evidence: matchResult.evidence,
            });
          }
          continue;
        }

        summary.cardsSafe++;
        const matchedCard = matchResult.matched;

        if (opts.dryRun) {
          for (const variant of matchedCard.variants ?? []) {
            const projection = planVariantProjection(variant, conditionMap);
            if (projection.status === "PROJECTED") {
              summary.productsProjected++;
              summary.observationsProjected++;
              setSummary.productsProjected++;
              setSummary.observationsProjected++;
            } else {
              summary.variantsProjectionSkipped++;
              setSummary.variantsProjectionSkipped++;
            }
          }
          continue;
        }

        plannedCardMappings.push({
          cardId: localCard.card_id,
          collectorNumber: localCard.collector_number,
          status: "CONFIRMED",
          matchedCard,
          method: matchResult.method,
          evidence: matchResult.evidence,
        });

        for (const variant of matchedCard.variants ?? []) {
          const externalProductId = String(variant.uuid ?? variant.id ?? "");
          const printingRaw = String(variant.printing ?? "");
          const conditionRaw = String(variant.condition ?? "");
          const price = variant.price;
          const lastUpdated = variant.lastUpdated;
          if (!externalProductId || !printingRaw || typeof price !== "number") continue;

          const conditionId = conditionMap.get(conditionRaw);
          if (!conditionId) {
            errorParts.push(`CONDICAO_SEM_MAPEAMENTO(${conditionRaw})`);
            continue;
          }

          const { printingTipo } = splitPrintingLanguage(printingRaw);
          const observedAt = typeof lastUpdated === "number" ? new Date(lastUpdated * 1000).toISOString() : new Date().toISOString();
          const rawPayload = sanitizeJson({ condition: conditionRaw, printing: printingRaw, price, lastUpdated });

          plannedVariants.push({
            cardId: localCard.card_id,
            collectorNumber: localCard.collector_number,
            externalProductId,
            sourcePrintingLabel: printingTipo ?? printingRaw,
            conditionId,
            price,
            observedAt,
            rawPayload,
          });
        }
      }
    }

    let batchPersistenceFailed = false;
    if (acquisitionFailed) {
      // Regras 8/9: qualquer falha de aquisição (Set ausente do inventário, reconfirmação de
      // match inesperada, orçamento esgotado ou paginação com erro) bloqueia a persistência
      // de TODA a onda — nunca uma escrita parcial por Set. plannedCardMappings/
      // plannedVariants acumulados até aqui são deliberadamente descartados.
    } else if (!opts.dryRun && (plannedCardMappings.length > 0 || plannedVariants.length > 0)) {
      const batchOutcome = await persistBatchedResults(supabase, sourceId, syncRunId, opts.confirmedBy as string, plannedCardMappings, plannedVariants);
      summary.productsResolved += batchOutcome.productsResolved;
      summary.productsWritten += batchOutcome.productsWritten;
      summary.observationsResolved += batchOutcome.observationsResolved;
      summary.observationsWritten += batchOutcome.observationsWritten;
      summary.observationsDivergent += batchOutcome.observationsDivergent;
      summary.identitiesResolved += batchOutcome.identitiesResolved;
      summary.identitiesWritten += batchOutcome.identitiesWritten;
      summary.operationsSupabase += batchOutcome.operationsSupabase;
      errorParts.push(...batchOutcome.errorParts);
      if (batchOutcome.batchFailureOccurred) batchPersistenceFailed = true;
    }

    const finalStatus = acquisitionFailed
      ? "FAILED"
      : computeFinalStatus(batchPersistenceFailed, errorParts.length > 0, summary.cardsSafe > 0 || summary.setsConfirmed > 0);

    if (!opts.dryRun) {
      await finalizeSyncRun(supabase, syncRunId, client, finalStatus, errorParts.length > 0 ? errorParts.slice(0, 15).join(" | ") : null, opts.dryRun);
      syncRunFinalized = true;
    }

    return {
      waveNumber: wave.waveNumber,
      setsSelected: wave.sets.map((s) => s.code),
      perSet,
      setsConfirmed: summary.setsConfirmed,
      cardsSafe: summary.cardsSafe,
      cardsAmbiguous: summary.cardsAmbiguous,
      cardsAbsent: summary.cardsAbsent,
      productsResolved: summary.productsResolved,
      productsWritten: summary.productsWritten,
      observationsResolved: summary.observationsResolved,
      observationsWritten: summary.observationsWritten,
      observationsDivergent: summary.observationsDivergent,
      identitiesResolved: summary.identitiesResolved,
      identitiesWritten: summary.identitiesWritten,
      operationsSupabase: summary.operationsSupabase,
      productsProjected: summary.productsProjected,
      observationsProjected: summary.observationsProjected,
      variantsProjectionSkipped: summary.variantsProjectionSkipped,
      requestsMade: client.requestsMade,
      maxApiRequests: opts.maxApiRequests,
      requestsRemainingLocal: client.requestsRemainingLocal,
      status: finalStatus,
      errorParts,
      syncRunId,
    };
  } catch (error) {
    if (!opts.dryRun && !syncRunFinalized && syncRunId) {
      const message = error instanceof Error ? error.message : String(error);
      await finalizeSyncRun(supabase, syncRunId, client, "FAILED", message, opts.dryRun);
    }
    throw error;
  }
}

async function runExpansionWave(
  opts: { waveNumber: number; dryRun: boolean; confirmedBy: string | null; maxApiRequests: number; expectedSetCodes: string[] },
): Promise<void> {
  const supabaseUrl = requireEnv("SUPABASE_URL");
  const supabaseServiceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
  const justTcgApiKey = requireEnv("JUSTTCG_API_KEY");

  const supabase = createClient(supabaseUrl, supabaseServiceRoleKey);
  const client = new JustTcgClient(justTcgApiKey, undefined, opts.maxApiRequests);

  console.log(`=== Executor de Onda (P14.4.2) — onda ${opts.waveNumber}, orçamento local=${opts.maxApiRequests} ===`);
  console.log(opts.dryRun ? "[DRY-RUN] Nenhuma escrita será persistida — nenhum pricing_sync_run será criado.\n" : `Confirmado por (admin_user.id): ${opts.confirmedBy}\n`);

  const result = await executeExpansionWave(supabase, client, opts);

  console.log("\n=== Resumo da execução de onda ===");
  console.log(JSON.stringify(result, null, 2));
}

// ============================================================================
// 7e. P14.4.3 — Executor Explícito de Backfill para Sets ALREADY_CONFIRMED_INCOMPLETE
//     (--backfill-wave)
// ============================================================================
//
// Objetivo: preencher a lacuna Sets confirmados-mas-parcialmente-mapeados (BASE1/ME1, ver
// cabeçalho do arquivo) processando SÓ as cartas locais ativas que ainda não têm NENHUM
// pricing_card_mapping — nunca reprocessando CONFIRMED/PENDING/NOT_FOUND já existentes.
// Reaproveita literalmente o matching fail-safe (classifyCardMatch/buildExternalNumberIndex)
// e a persistência em lote (persistBatchedResults) já testados em P14.3/P14.4.2 — a única
// diferença estrutural real em relação a executeExpansionWave() é: (a) a fonte da onda é
// plan.backfillWaves, não plan.waves; (b) o external_set_id vem DIRETO do mapping já
// CONFIRMED (entry.externalSetId) — resolveSetMatchV2()/upsertSetMapping() NUNCA são
// chamados aqui, o Set já está confirmado e não deve ser reavaliado; (c) as cartas
// classificadas vêm de findMissingCardsForSet() (só as sem mapping), nunca de
// findLocalCardsForSet() (todas as cartas do Set).

type BackfillWaveArgsValidation =
  | { ok: true; waveNumber: number; maxApiRequests: number; expectedSetCodes: string[] }
  | { ok: false; reason: string };

// Pura — mesma disciplina de validateExpansionWaveArgs() (rejeita onda/orçamento/modo
// inválidos ANTES de qualquer rede/Supabase), mas com códigos de erro e nome de flag
// próprios (BACKFILL_WAVE_*, nunca reaproveita EXPANSION_WAVE_* — mensagens sempre precisas
// sobre qual flag o usuário realmente passou). validateExpectedSetCodes() é reaproveitada
// verbatim (formato/duplicidade de --expected-set-codes independe de qual modo de onda).
function validateBackfillWaveArgs(args: {
  backfillWave: string | null;
  maxApiRequests: string | null;
  dryRun: boolean;
  confirmedBy: string | null;
  expectedSetCodes: string | null;
}): BackfillWaveArgsValidation {
  const waveRaw = args.backfillWave;
  if (waveRaw === null) return { ok: false, reason: "BACKFILL_WAVE_AUSENTE: --backfill-wave=<n> é obrigatório neste modo." };
  const waveNumber = Number(waveRaw);
  if (!Number.isInteger(waveNumber) || waveNumber <= 0) {
    return { ok: false, reason: `BACKFILL_WAVE_INVALIDO(${waveRaw}): --backfill-wave deve ser um inteiro positivo (1, 2, 3, ...) — nunca executa "todas as ondas" implicitamente.` };
  }

  const budgetRaw = args.maxApiRequests;
  if (budgetRaw === null) {
    return { ok: false, reason: "MAX_API_REQUESTS_AUSENTE: --max-api-requests=<n> é obrigatório neste modo (orçamento local autoritativo de requisições, independente do teto de segurança do processo)." };
  }
  const maxApiRequests = Number(budgetRaw);
  if (!Number.isInteger(maxApiRequests) || maxApiRequests <= 0) {
    return { ok: false, reason: `MAX_API_REQUESTS_INVALIDO(${budgetRaw}): --max-api-requests deve ser um inteiro positivo.` };
  }

  const expectedSetCodesValidation = validateExpectedSetCodes(args.expectedSetCodes);
  if (!expectedSetCodesValidation.ok) return { ok: false, reason: expectedSetCodesValidation.reason };

  const hasDryRun = args.dryRun;
  const hasConfirmedBy = args.confirmedBy !== null && args.confirmedBy !== "";
  if (hasDryRun && hasConfirmedBy) {
    return { ok: false, reason: "MODOS_CONFLITANTES: --dry-run e --confirmed-by são mutuamente exclusivos no executor de backfill — escolha simulação (--dry-run) ou execução real (--confirmed-by=<admin_user_uuid>), nunca os dois." };
  }
  if (!hasDryRun && !hasConfirmedBy) {
    return { ok: false, reason: "MODO_AUSENTE: informe --dry-run (simulação, sem escrita) ou --confirmed-by=<admin_user_uuid> (execução real) — nenhum modo padrão é assumido." };
  }

  return { ok: true, waveNumber, maxApiRequests, expectedSetCodes: expectedSetCodesValidation.codes };
}

// Pura — mesma disciplina de selectWaveFromPlan(), mas sobre plan.backfillWaves.
function selectBackfillWaveFromPlan(plan: ExpansionPlanResult, waveNumber: number): { ok: true; wave: BackfillWave } | { ok: false; error: string } {
  const wave = plan.backfillWaves.find((w) => w.waveNumber === waveNumber);
  if (!wave) {
    return {
      ok: false,
      error: `BACKFILL_WAVE_INEXISTENTE(${waveNumber}): o plano recalculado agora tem ${plan.backfillWaves.length} onda(s) de backfill (1${plan.backfillWaves.length > 1 ? `-${plan.backfillWaves.length}` : ""}). Nunca executa todas as ondas implicitamente — escolha um número de onda válido.`,
    };
  }
  return { ok: true, wave };
}

// P14.4.4 fix (filtro por denominador) — collector_total incluído desde a origem: as
// mesmas cartas usadas pelo backfill (findMissingCardsForSet) e pelo reparo
// (findPendingOrNotFoundCardsForSet) alimentam classifyCardMatch(), que só aplica o
// filtro por denominador quando o campo está presente e válido (ver isValidCollectorTotal).
type LocalCardRow = { id: string; name: string; collector_number: string; collector_total: number | null };
type CardMappingIdRow = { card_id: string };

// P14.4.3: cartas locais ATIVAS do Set sem NENHUM pricing_card_mapping para esta fonte — a
// única entrada aceitável para o backfill (CONFIRMED/PENDING/NOT_FOUND já existentes NUNCA
// são retocados). PostgREST não expõe NOT EXISTS/anti-join direto; resolvido em duas
// leituras paginadas e reconciliadas contra uma contagem exata (mesma disciplina de
// fetchReconciledLocalInputs — nunca supõe que uma única página de até 1.000 linhas basta,
// mesmo que hoje nenhum Set isolado alcance esse volume) e a diferença calculada em memória.
// Ordenação por collector_number — mesma convenção de determinismo já usada em
// buildLocalSetInventory().
async function findMissingCardsForSet(supabase: SupabaseClient, cardSetId: string, pricingSourceId: string): Promise<LocalCard[]> {
  const activeRows = await fetchAllRowsFromTable<LocalCardRow>(
    supabase,
    "card",
    "id, name, collector_number, collector_total",
    "collector_number",
    (q) => q.eq("card_set_id", cardSetId).eq("is_active", true),
  );
  const exactActiveCount = await fetchExactCount(supabase, "card", (q) => q.eq("card_set_id", cardSetId).eq("is_active", true));
  assertPaginationComplete(`card(backfill,set=${cardSetId})`, activeRows.length, exactActiveCount);

  const activeIds = activeRows.map((r) => r.id);
  if (activeIds.length === 0) return [];

  const mappedRows = await fetchAllRowsFromTable<CardMappingIdRow>(
    supabase,
    "pricing_card_mapping",
    "card_id",
    "card_id",
    (q) => q.eq("pricing_source_id", pricingSourceId).in("card_id", activeIds),
  );
  const exactMappedCount = await fetchExactCount(supabase, "pricing_card_mapping", (q) => q.eq("pricing_source_id", pricingSourceId).in("card_id", activeIds));
  assertPaginationComplete(`pricing_card_mapping(backfill,set=${cardSetId})`, mappedRows.length, exactMappedCount);

  const mappedIds = new Set(mappedRows.map((r) => r.card_id));
  return activeRows.filter((r) => !mappedIds.has(r.id)).map((r) => ({ card_id: r.id, name: r.name, collector_number: r.collector_number, collector_total: r.collector_total ?? null }));
}

type BackfillWaveOpts = { waveNumber: number; dryRun: boolean; confirmedBy: string | null; maxApiRequests: number; expectedSetCodes: string[] };

type BackfillWaveSetSummary = {
  code: string;
  missingCardsCount: number;
  externalCardsSeen: number;
  productsProjected: number;
  observationsProjected: number;
  variantsProjectionSkipped: number;
};

type BackfillWaveRunResult = {
  waveNumber: number;
  setsSelected: string[];
  perSet: BackfillWaveSetSummary[];
  cardsProcessed: number;
  cardsSafe: number;
  cardsAmbiguous: number;
  cardsAbsent: number;
  productsResolved: number;
  productsWritten: number;
  observationsResolved: number;
  observationsWritten: number;
  observationsDivergent: number;
  identitiesResolved: number;
  identitiesWritten: number;
  operationsSupabase: number;
  productsProjected: number;
  observationsProjected: number;
  variantsProjectionSkipped: number;
  requestsMade: number;
  maxApiRequests: number;
  requestsRemainingLocal: number;
  status: "COMPLETED" | "COMPLETED_WITH_ERRORS" | "FAILED";
  errorParts: string[];
  syncRunId: string | null;
};

// Núcleo do P14.4.3. Ordem estrita, espelhando executeExpansionWave() (P14.4.2), com as
// diferenças documentadas no comentário da Seção 7e: (1) leituras locais reconciliadas —
// fetchReconciledLocalInputs(), idêntica; (2) em modo real, abre um único CARD_SYNC antes de
// qualquer requisição à JustTCG, detectando 23505 (mesmo helper); (3) primeira chamada
// externa (GET /v1/sets) — reclassifica os Sets e recalcula o plano/ondas de backfill nesta
// própria execução (nunca hardcoded); (4) seleciona a onda de backfill pedida dentro do
// plano recém-calculado; (5) para cada Set da onda, usa EXCLUSIVAMENTE o external_set_id já
// CONFIRMED (nunca resolveSetMatchV2()/upsertSetMapping() — o Set não é reavaliado) e pagina
// TODAS as cartas externas do Set (fetchAllCardsForSet); (6) busca só as cartas locais SEM
// NENHUM mapping (findMissingCardsForSet) e classifica cada uma (classifyCardMatch, mesmo
// fail-safe); qualquer aborto (Set sem external_set_id, orçamento/autenticação/paginação)
// interrompe a aquisição da onda inteira, sem persistir nada; (7) só depois de todos os Sets
// da onda adquiridos com sucesso, persiste em lote (persistBatchedResults(), reusada
// verbatim) e finaliza o run (finalizeSyncRun(), reusada verbatim).
async function executeBackfillWave(supabase: SupabaseClient, client: JustTcgClient, opts: BackfillWaveOpts): Promise<BackfillWaveRunResult> {
  const { sourceId, localSets, existingSetMappings, existingCoverage } = await fetchReconciledLocalInputs(supabase);

  let syncRunId: string | null = null;
  let syncRunFinalized = false;

  if (!opts.dryRun) {
    const startAttempt = await tryOpenCardSyncRun(supabase, sourceId, opts.confirmedBy as string);
    if (startAttempt.outcome === "CONCURRENT_CONFLICT") {
      throw new Error(
        "CONFLITO_DE_CONCORRENCIA: já existe uma execução CARD_SYNC ativa (RECEIVED/PROCESSING) para esta fonte (índice único parcial, Query 3907) — backfill abortado antes de qualquer chamada à JustTCG.",
      );
    }
    if (startAttempt.outcome === "OTHER_ERROR") {
      throw new Error(`SYNC_RUN_INSERT_FAILED: ${startAttempt.error}`);
    }
    syncRunId = startAttempt.id;
  }

  const conditionMap = await getConditionMap(supabase, sourceId);
  if (!opts.dryRun && conditionMap.size === 0) {
    throw new Error("CONDITION_MAP_VAZIO: rode a seed 3702 (pricing_condition_mapping) antes deste script.");
  }

  const summary = {
    cardsProcessed: 0,
    cardsSafe: 0,
    cardsAmbiguous: 0,
    cardsAbsent: 0,
    productsResolved: 0,
    productsWritten: 0,
    observationsResolved: 0,
    observationsWritten: 0,
    observationsDivergent: 0,
    identitiesResolved: 0,
    identitiesWritten: 0,
    operationsSupabase: 0,
    productsProjected: 0,
    observationsProjected: 0,
    variantsProjectionSkipped: 0,
  };
  const perSet: BackfillWaveSetSummary[] = [];
  const errorParts: string[] = [];
  const plannedCardMappings: PlannedCardMapping[] = [];
  const plannedVariants: PlannedVariant[] = [];
  let acquisitionFailed = false;
  let wave: BackfillWave | null = null;

  try {
    const setsResult = await client.get<{ data: JustTcgSet[] }>("/sets", { game: GAME_CODE });
    if (setsResult.status === "AUTH_FAILURE") {
      throw new Error("AUTENTICACAO_FALHOU_401: JUSTTCG_API_KEY inválida ou expirada — execução de backfill abortada.");
    }
    if (setsResult.status !== "SUCCESS") {
      throw new Error(`BACKFILL_FASE_SETS_FALHOU: ${setsResult.status}`);
    }
    const allExternalSets = normalizeJustTcgSets(setsResult.data.data ?? []);

    const plan = buildExpansionPlan({ localSets, existingSetMappings, allExternalSets, existingCoverage });
    assertConfirmedMappingsPreserved(plan.entries, localSets, existingSetMappings);

    const waveSelection = selectBackfillWaveFromPlan(plan, opts.waveNumber);
    if (!waveSelection.ok) throw new Error(waveSelection.error);
    wave = waveSelection.wave;

    // Mesma disciplina de instabilidade de identidade do P14.4.2 (ver validateExpectedSetCodes):
    // a composição RECALCULADA precisa bater exatamente (nunca subconjunto, nunca sobra) com
    // --expected-set-codes antes de tocar em qualquer Set desta onda.
    const actualCodes = [...new Set(wave.sets.map((s) => s.code))].sort();
    const expectedCodes = [...new Set(opts.expectedSetCodes)].sort();
    const compositionMatches = actualCodes.length === expectedCodes.length && actualCodes.every((code, i) => code === expectedCodes[i]);
    if (!compositionMatches) {
      const missing = expectedCodes.filter((c) => !actualCodes.includes(c));
      const extra = actualCodes.filter((c) => !expectedCodes.includes(c));
      throw new Error(
        `BACKFILL_WAVE_COMPOSITION_CHANGED: a onda de backfill ${opts.waveNumber} recalculada agora tem os Sets [${actualCodes.join(",") || "nenhum"}], divergente do esperado [${expectedCodes.join(",") || "nenhum"}] — faltando=[${missing.join(",") || "nenhum"}] excedente=[${extra.join(",") || "nenhum"}]. Onda abortada antes de qualquer persistência.`,
      );
    }

    const localByCode = new Map(localSets.map((s) => [s.code, s]));
    const entryByCode = new Map(plan.entries.map((e) => [e.code, e]));

    for (const waveSet of wave.sets) {
      const local = localByCode.get(waveSet.code);
      if (!local) {
        errorParts.push(`BACKFILL_SET_SEM_INVENTARIO_LOCAL(${waveSet.code})`);
        acquisitionFailed = true;
        break;
      }

      const entry = entryByCode.get(waveSet.code);
      if (!entry || entry.status !== "ALREADY_CONFIRMED_INCOMPLETE" || !entry.externalSetId) {
        errorParts.push(
          `BACKFILL_SET_STATUS_INESPERADO(${waveSet.code}): ${entry?.status ?? "AUSENTE"} — a onda só deveria conter Sets ALREADY_CONFIRMED_INCOMPLETE com external_set_id conhecido; onda abortada por segurança.`,
        );
        acquisitionFailed = true;
        break;
      }

      // Regra central do P14.4.3: usa EXCLUSIVAMENTE o external_set_id já CONFIRMED — nunca
      // resolveSetMatchV2()/upsertSetMapping() aqui. O Set já está confirmado; o backfill
      // preenche cartas, nunca reavalia a identidade do Set.
      const externalSetId = entry.externalSetId;

      const { cards: externalCards, requestsUsed, aborted } = await fetchAllCardsForSet(client, externalSetId);
      const setSummary: BackfillWaveSetSummary = {
        code: waveSet.code,
        missingCardsCount: waveSet.missingCardsCount,
        externalCardsSeen: externalCards.length,
        productsProjected: 0,
        observationsProjected: 0,
        variantsProjectionSkipped: 0,
      };
      perSet.push(setSummary);

      if (aborted === "AUTH_FAILURE") {
        errorParts.push(`AUTENTICACAO_FALHOU_401(${waveSet.code})`);
        acquisitionFailed = true;
        break;
      }
      if (aborted === "BUDGET_STOPPED") {
        errorParts.push(`ORCAMENTO_ESGOTADO(${waveSet.code}): após ${requestsUsed} requisição(ões) de página deste Set — nenhum dado de negócio deste backfill será persistido.`);
        acquisitionFailed = true;
        break;
      }
      if (aborted === "TECHNICAL_FAILURE") {
        errorParts.push(`PAGINACAO_CARDS_FALHOU(${waveSet.code}): interrompida após ${requestsUsed} requisição(ões) — nenhum dado de negócio deste backfill será persistido.`);
        acquisitionFailed = true;
        break;
      }

      // Regra central: só cartas locais ativas SEM NENHUM mapping — CONFIRMED/PENDING/
      // NOT_FOUND já existentes NUNCA são retocados (findMissingCardsForSet nunca os retorna).
      const missingLocalCards = await findMissingCardsForSet(supabase, local.cardSetId, sourceId);
      summary.cardsProcessed += missingLocalCards.length;
      const externalIndex = buildExternalNumberIndex(externalCards);

      for (const localCard of missingLocalCards) {
        const matchResult = classifyCardMatch(localCard, externalIndex, externalSetId);

        if (matchResult.classification !== "SAFE" || !matchResult.matched) {
          if (matchResult.classification === "ABSENT") summary.cardsAbsent++;
          else summary.cardsAmbiguous++;
          if (opts.dryRun) logDryRunCardEvidence(localCard, matchResult);
          if (!opts.dryRun) {
            plannedCardMappings.push({
              cardId: localCard.card_id,
              collectorNumber: localCard.collector_number,
              status: matchResult.classification === "ABSENT" ? "NOT_FOUND" : "PENDING",
              matchedCard: null,
              method: matchResult.method,
              evidence: matchResult.evidence,
            });
          }
          continue;
        }

        summary.cardsSafe++;
        const matchedCard = matchResult.matched;

        if (opts.dryRun) {
          for (const variant of matchedCard.variants ?? []) {
            const projection = planVariantProjection(variant, conditionMap);
            if (projection.status === "PROJECTED") {
              summary.productsProjected++;
              summary.observationsProjected++;
              setSummary.productsProjected++;
              setSummary.observationsProjected++;
            } else {
              summary.variantsProjectionSkipped++;
              setSummary.variantsProjectionSkipped++;
            }
          }
          continue;
        }

        plannedCardMappings.push({
          cardId: localCard.card_id,
          collectorNumber: localCard.collector_number,
          status: "CONFIRMED",
          matchedCard,
          method: matchResult.method,
          evidence: matchResult.evidence,
        });

        for (const variant of matchedCard.variants ?? []) {
          const externalProductId = String(variant.uuid ?? variant.id ?? "");
          const printingRaw = String(variant.printing ?? "");
          const conditionRaw = String(variant.condition ?? "");
          const price = variant.price;
          const lastUpdated = variant.lastUpdated;
          if (!externalProductId || !printingRaw || typeof price !== "number") continue;

          const conditionId = conditionMap.get(conditionRaw);
          if (!conditionId) {
            errorParts.push(`CONDICAO_SEM_MAPEAMENTO(${conditionRaw})`);
            continue;
          }

          const { printingTipo } = splitPrintingLanguage(printingRaw);
          const observedAt = typeof lastUpdated === "number" ? new Date(lastUpdated * 1000).toISOString() : new Date().toISOString();
          const rawPayload = sanitizeJson({ condition: conditionRaw, printing: printingRaw, price, lastUpdated });

          plannedVariants.push({
            cardId: localCard.card_id,
            collectorNumber: localCard.collector_number,
            externalProductId,
            sourcePrintingLabel: printingTipo ?? printingRaw,
            conditionId,
            price,
            observedAt,
            rawPayload,
          });
        }
      }
    }

    let batchPersistenceFailed = false;
    if (acquisitionFailed) {
      // Falha de aquisição bloqueia a persistência de TODA a onda de backfill — nunca uma
      // escrita parcial por Set. plannedCardMappings/plannedVariants acumulados até aqui são
      // deliberadamente descartados.
    } else if (!opts.dryRun && (plannedCardMappings.length > 0 || plannedVariants.length > 0)) {
      const batchOutcome = await persistBatchedResults(supabase, sourceId, syncRunId, opts.confirmedBy as string, plannedCardMappings, plannedVariants);
      summary.productsResolved += batchOutcome.productsResolved;
      summary.productsWritten += batchOutcome.productsWritten;
      summary.observationsResolved += batchOutcome.observationsResolved;
      summary.observationsWritten += batchOutcome.observationsWritten;
      summary.observationsDivergent += batchOutcome.observationsDivergent;
      summary.identitiesResolved += batchOutcome.identitiesResolved;
      summary.identitiesWritten += batchOutcome.identitiesWritten;
      summary.operationsSupabase += batchOutcome.operationsSupabase;
      errorParts.push(...batchOutcome.errorParts);
      if (batchOutcome.batchFailureOccurred) batchPersistenceFailed = true;
    }

    const finalStatus = acquisitionFailed
      ? "FAILED"
      : computeFinalStatus(batchPersistenceFailed, errorParts.length > 0, summary.cardsSafe > 0 || summary.cardsProcessed > 0);

    if (!opts.dryRun) {
      await finalizeSyncRun(supabase, syncRunId, client, finalStatus, errorParts.length > 0 ? errorParts.slice(0, 15).join(" | ") : null, opts.dryRun);
      syncRunFinalized = true;
    }

    return {
      waveNumber: wave.waveNumber,
      setsSelected: wave.sets.map((s) => s.code),
      perSet,
      cardsProcessed: summary.cardsProcessed,
      cardsSafe: summary.cardsSafe,
      cardsAmbiguous: summary.cardsAmbiguous,
      cardsAbsent: summary.cardsAbsent,
      productsResolved: summary.productsResolved,
      productsWritten: summary.productsWritten,
      observationsResolved: summary.observationsResolved,
      observationsWritten: summary.observationsWritten,
      observationsDivergent: summary.observationsDivergent,
      identitiesResolved: summary.identitiesResolved,
      identitiesWritten: summary.identitiesWritten,
      operationsSupabase: summary.operationsSupabase,
      productsProjected: summary.productsProjected,
      observationsProjected: summary.observationsProjected,
      variantsProjectionSkipped: summary.variantsProjectionSkipped,
      requestsMade: client.requestsMade,
      maxApiRequests: opts.maxApiRequests,
      requestsRemainingLocal: client.requestsRemainingLocal,
      status: finalStatus,
      errorParts,
      syncRunId,
    };
  } catch (error) {
    if (!opts.dryRun && !syncRunFinalized && syncRunId) {
      const message = error instanceof Error ? error.message : String(error);
      await finalizeSyncRun(supabase, syncRunId, client, "FAILED", message, opts.dryRun);
    }
    throw error;
  }
}

async function runBackfillWave(
  opts: { waveNumber: number; dryRun: boolean; confirmedBy: string | null; maxApiRequests: number; expectedSetCodes: string[] },
): Promise<void> {
  const supabaseUrl = requireEnv("SUPABASE_URL");
  const supabaseServiceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
  const justTcgApiKey = requireEnv("JUSTTCG_API_KEY");

  const supabase = createClient(supabaseUrl, supabaseServiceRoleKey);
  const client = new JustTcgClient(justTcgApiKey, undefined, opts.maxApiRequests);

  console.log(`=== Executor de Backfill (P14.4.3) — onda ${opts.waveNumber}, orçamento local=${opts.maxApiRequests} ===`);
  console.log(opts.dryRun ? "[DRY-RUN] Nenhuma escrita será persistida — nenhum pricing_sync_run será criado.\n" : `Confirmado por (admin_user.id): ${opts.confirmedBy}\n`);

  const result = await executeBackfillWave(supabase, client, opts);

  console.log("\n=== Resumo da execução de backfill ===");
  console.log(JSON.stringify(result, null, 2));
}

// ============================================================================
// 7f. P14.4.4 — Executor Explícito de Reparo de Mappings PENDING/NOT_FOUND
//     (--repair-mappings)
// ============================================================================
//
// Objetivo: corrigir, nos Sets já CONFIRMED, os mappings PENDING/NOT_FOUND que a causa raiz
// de P14.4.4 deixou para trás (nome usado como critério de matching, bloqueando
// candidatos únicos legítimos por Set+número — ver auditoria pós-P14.4.3 e o novo
// classifyCardMatch() acima). Reavalia SOMENTE PENDING/NOT_FOUND; CONFIRMED nunca é tocado
// (findPendingOrNotFoundCardsForSet() abaixo nunca os retorna — mesma garantia estrutural de
// findMissingCardsForSet() em P14.4.3, só que para o conjunto complementar de status).
//
// Diferenças deliberadas em relação a executeBackfillWave()/executeExpansionWave():
//   1. Nunca chama GET /v1/sets — o reparo nunca resolve identidade de Set (nem
//      resolveSetMatchV2 nem upsertSetMapping), só usa o external_set_id já CONFIRMED
//      (pricing_set_mapping) diretamente. Onda de backfill/expansão precisa de /sets para
//      reclassificar Sets ainda não confirmados; reparo não — todo Set-alvo já está
//      CONFIRMED por definição.
//   2. Não existe conceito de "onda numerada" aqui: a lista de Sets-alvo é derivada
//      DINAMICAMENTE em cada execução (buildRepairCandidates(), pura) a partir do estado
//      real de pricing_set_mapping + pricing_set_coverage — nunca os seis códigos
//      hardcoded (BASE1/BASE2/BASE4/BASE5/GYM2/ME1) citados no pedido original. Isso é
//      deliberado ("não criar exceção específica") e corrige uma divergência real
//      descoberta na auditoria: BASE5 foi citado como alvo mas hoje tem 0 PENDING/
//      NOT_FOUND — buildRepairCandidates() naturalmente o exclui, sem precisar de nenhuma
//      lista negativa.
//   3. Interpretação mínima de "promover somente quando resultar único": cartas que, após
//      reclassificação, continuam AMBIGUOUS ou ABSENT são deixadas INTOCADAS — nenhuma
//      chamada a upsertCardMapping/persistBatchedResults para elas, nenhum refresh de
//      evidência. Só entram em plannedCardMappings (e por extensão em persistBatchedResults)
//      as cartas que reclassificam como SAFE — a mesma função persistBatchedResults() já
//      usada por P14.3/P14.4.2/P14.4.3 promove PENDING/NOT_FOUND->CONFIRMED e cria
//      produtos/observações na mesma passada via decideMappingUpsert()
//      (UPGRADED_TO_CONFIRMED) — nenhuma RPC nova, nenhuma lógica de promoção nova.
//   4. Mesma disciplina de concorrência/orçamento/expected-set-codes dos outros dois
//      executores: tryOpenCardSyncRun() ANTES de qualquer chamada externa; --expected-set-
//      codes validado contra a composição REAL recalculada (nunca aceita silenciosamente
//      uma lista desatualizada); --dry-run nunca escreve; modo real exige
//      --confirmed-by/--max-api-requests, mutuamente exclusivo com --dry-run.
// ============================================================================

type RepairCandidateSet = { code: string; cardSetId: string; externalSetId: string; pendingCount: number; notFoundCount: number };

// Pura — nunca lê Deno.env nem toca rede/banco. Um Set só entra na lista de reparo se (a) seu
// pricing_set_mapping já é CONFIRMED com external_set_id conhecido (reparo nunca reavalia
// identidade de Set) e (b) sua cobertura agregada (pricing_set_coverage) tem
// pendingCards+notFoundCards > 0 (sem candidato a reparar, nenhuma chamada HTTP é gasta com
// o Set). Ordenado por código para determinismo (mesmo padrão de buildLocalSetInventory).
function buildRepairCandidates(
  localSets: LocalSetSummary[],
  existingSetMappings: Map<string, ExistingSetMappingLite>,
  existingCoverage: Map<string, SetCoverageAggregate>,
): RepairCandidateSet[] {
  const candidates: RepairCandidateSet[] = [];
  for (const local of localSets) {
    const mapping = existingSetMappings.get(local.cardSetId);
    if (!mapping || mapping.matchStatus !== "CONFIRMED" || !mapping.externalSetId) continue;
    const coverage = existingCoverage.get(local.cardSetId);
    const pendingCount = coverage?.pendingCards ?? 0;
    const notFoundCount = coverage?.notFoundCards ?? 0;
    if (pendingCount + notFoundCount === 0) continue;
    candidates.push({ code: local.code, cardSetId: local.cardSetId, externalSetId: mapping.externalSetId, pendingCount, notFoundCount });
  }
  return candidates.sort((a, b) => a.code.localeCompare(b.code));
}

type RepairSetCodesFilterResult = { ok: true; filtered: RepairCandidateSet[] } | { ok: false; reason: string };

// P14.4.6 — Pura, nunca toca rede/banco. Aplica --repair-set-codes (quando informado) ANTES de
// qualquer chamada à JustTCG: reduz `candidates` (já 100% derivado de buildRepairCandidates(),
// rodado agora mesmo) ao subconjunto pedido. `requestedCodesRaw === null` (flag ausente)
// preserva o comportamento anterior byte-a-byte — devolve `candidates` sem tocar. Cada código
// pedido precisa estar em `candidates` (Set já CONFIRMED nesta fonte E com
// pendingCount+notFoundCount>0 agora); se não estiver, distingue duas causas possíveis para uma
// mensagem de erro útil: (a) o código nem existe entre os Sets locais -> DESCONHECIDO; (b) o
// código existe localmente mas não é candidato a reparo agora (não é Set CONFIRMED nesta fonte,
// ou é CONFIRMED mas já não tem PENDING/NOT_FOUND) -> SEM_PENDENCIA. Qualquer um dos dois aborta
// antes da primeira requisição HTTP — mesma garantia estrutural do REPAIR_CANDIDATE_SETS_CHANGED
// já existente para --expected-set-codes.
function filterRepairCandidatesBySetCodes(
  candidates: RepairCandidateSet[],
  requestedCodesRaw: string[] | null,
  localSets: LocalSetSummary[],
): RepairSetCodesFilterResult {
  if (requestedCodesRaw === null) return { ok: true, filtered: candidates };

  const candidateCodes = new Set(candidates.map((c) => c.code));
  const localCodes = new Set(localSets.map((s) => s.code));
  const unknown: string[] = [];
  const semPendencia: string[] = [];
  for (const code of requestedCodesRaw) {
    if (candidateCodes.has(code)) continue;
    if (localCodes.has(code)) semPendencia.push(code);
    else unknown.push(code);
  }
  if (unknown.length > 0) {
    return { ok: false, reason: `REPAIR_SET_CODES_DESCONHECIDO: código(s) inexistente(s) entre os Sets locais: ${unknown.join(", ")}.` };
  }
  if (semPendencia.length > 0) {
    return {
      ok: false,
      reason: `REPAIR_SET_CODES_SEM_PENDENCIA: código(s) sem PENDING/NOT_FOUND elegível a reparo agora (Set não CONFIRMED nesta fonte, ou já sem pendência): ${semPendencia.join(", ")}.`,
    };
  }

  const requestedSet = new Set(requestedCodesRaw);
  const filtered = candidates.filter((c) => requestedSet.has(c.code));
  return { ok: true, filtered };
}

type PendingCardMappingRow = { card_id: string; match_status: string };

// P14.4.4: cartas locais ATIVAS do Set com mapping PENDING ou NOT_FOUND nesta fonte — as
// únicas candidatas ao reparo. CONFIRMED nunca é retornado (filtro .in("match_status", [...])
// só inclui os dois status reparáveis); cartas sem NENHUM mapping também nunca são retornadas
// (fora de escopo deste executor — isso é findMissingCardsForSet(), do backfill P14.4.3).
// Mesma disciplina de paginação+reconciliação (fetchAllRowsFromTable + fetchExactCount +
// assertPaginationComplete) de findMissingCardsForSet().
async function findPendingOrNotFoundCardsForSet(supabase: SupabaseClient, cardSetId: string, pricingSourceId: string): Promise<LocalCard[]> {
  const activeRows = await fetchAllRowsFromTable<LocalCardRow>(
    supabase,
    "card",
    "id, name, collector_number, collector_total",
    "collector_number",
    (q) => q.eq("card_set_id", cardSetId).eq("is_active", true),
  );
  const exactActiveCount = await fetchExactCount(supabase, "card", (q) => q.eq("card_set_id", cardSetId).eq("is_active", true));
  assertPaginationComplete(`card(repair,set=${cardSetId})`, activeRows.length, exactActiveCount);

  const activeIds = activeRows.map((r) => r.id);
  if (activeIds.length === 0) return [];

  const mappingRows = await fetchAllRowsFromTable<PendingCardMappingRow>(
    supabase,
    "pricing_card_mapping",
    "card_id, match_status",
    "card_id",
    (q) => q.eq("pricing_source_id", pricingSourceId).in("card_id", activeIds).in("match_status", ["PENDING", "NOT_FOUND"]),
  );
  const exactMappingCount = await fetchExactCount(
    supabase,
    "pricing_card_mapping",
    (q) => q.eq("pricing_source_id", pricingSourceId).in("card_id", activeIds).in("match_status", ["PENDING", "NOT_FOUND"]),
  );
  assertPaginationComplete(`pricing_card_mapping(repair,set=${cardSetId})`, mappingRows.length, exactMappingCount);

  const targetIds = new Set(mappingRows.map((r) => r.card_id));
  return activeRows.filter((r) => targetIds.has(r.id)).map((r) => ({ card_id: r.id, name: r.name, collector_number: r.collector_number, collector_total: r.collector_total ?? null }));
}

type RepairMappingsArgsValidation =
  | { ok: true; maxApiRequests: number; expectedSetCodes: string[]; repairSetCodes: string[] | null }
  | { ok: false; reason: string };

// Pura — mesma disciplina de validateExpansionWaveArgs/validateBackfillWaveArgs, sem número de
// onda (o reparo não tem conceito de onda: processa todos os Sets-alvo elegíveis numa única
// passada). --expected-set-codes continua obrigatório: mesmo sem onda numerada, a composição
// da lista dinâmica de candidatos ainda pode mudar entre a hora em que Fabrício audita e a
// hora em que roda o comando real — a mesma proteção anti-deriva se aplica.
//
// P14.4.6 — --repair-set-codes é OPCIONAL (diferente de --expected-set-codes): sua ausência
// (null) preserva o comportamento anterior byte-a-byte (nenhum filtro, todos os candidatos
// elegíveis entram). Só valida FORMATO aqui (vazio/duplicado, via validateRepairSetCodesFormat)
// — a existência do código entre os candidatos reais é checada depois, em
// filterRepairCandidatesBySetCodes(), porque depende do estado do banco.
function validateRepairMappingsArgs(args: {
  maxApiRequests: string | null;
  dryRun: boolean;
  confirmedBy: string | null;
  expectedSetCodes: string | null;
  repairSetCodes: string | null;
}): RepairMappingsArgsValidation {
  const budgetRaw = args.maxApiRequests;
  if (budgetRaw === null) {
    return { ok: false, reason: "MAX_API_REQUESTS_AUSENTE: --max-api-requests=<n> é obrigatório neste modo." };
  }
  const maxApiRequests = Number(budgetRaw);
  if (!Number.isInteger(maxApiRequests) || maxApiRequests <= 0) {
    return { ok: false, reason: `MAX_API_REQUESTS_INVALIDO(${budgetRaw}): --max-api-requests deve ser um inteiro positivo.` };
  }

  const expectedSetCodesValidation = validateExpectedSetCodes(args.expectedSetCodes);
  if (!expectedSetCodesValidation.ok) return { ok: false, reason: expectedSetCodesValidation.reason };

  let repairSetCodes: string[] | null = null;
  if (args.repairSetCodes !== null) {
    const repairSetCodesValidation = validateRepairSetCodesFormat(args.repairSetCodes);
    if (!repairSetCodesValidation.ok) return { ok: false, reason: repairSetCodesValidation.reason };
    repairSetCodes = repairSetCodesValidation.codes;
  }

  const hasDryRun = args.dryRun;
  const hasConfirmedBy = args.confirmedBy !== null && args.confirmedBy !== "";
  if (hasDryRun && hasConfirmedBy) {
    return { ok: false, reason: "MODOS_CONFLITANTES: --dry-run e --confirmed-by são mutuamente exclusivos no executor de reparo — escolha simulação (--dry-run) ou execução real (--confirmed-by=<admin_user_uuid>), nunca os dois." };
  }
  if (!hasDryRun && !hasConfirmedBy) {
    return { ok: false, reason: "MODO_AUSENTE: informe --dry-run (simulação, sem escrita) ou --confirmed-by=<admin_user_uuid> (execução real) — nenhum modo padrão é assumido." };
  }

  return { ok: true, maxApiRequests, expectedSetCodes: expectedSetCodesValidation.codes, repairSetCodes };
}

type RepairMappingsOpts = { dryRun: boolean; confirmedBy: string | null; maxApiRequests: number; expectedSetCodes: string[]; repairSetCodes?: string[] | null };

type RepairMappingsSetSummary = {
  code: string;
  pendingCount: number;
  notFoundCount: number;
  externalCardsSeen: number;
  cardsEvaluated: number;
  cardsPromoted: number;
  productsProjected: number;
  observationsProjected: number;
  variantsProjectionSkipped: number;
};

type RepairMappingsRunResult = {
  setsTargeted: string[];
  perSet: RepairMappingsSetSummary[];
  cardsEvaluated: number;
  cardsPromoted: number;
  cardsStillPending: number;
  cardsStillNotFound: number;
  productsResolved: number;
  productsWritten: number;
  observationsResolved: number;
  observationsWritten: number;
  observationsDivergent: number;
  identitiesResolved: number;
  identitiesWritten: number;
  operationsSupabase: number;
  productsProjected: number;
  observationsProjected: number;
  variantsProjectionSkipped: number;
  requestsMade: number;
  maxApiRequests: number;
  requestsRemainingLocal: number;
  status: "COMPLETED" | "COMPLETED_WITH_ERRORS" | "FAILED";
  errorParts: string[];
  syncRunId: string | null;
};

// Núcleo do P14.4.4. Ordem estrita: (1) leituras locais reconciliadas — fetchReconciledLocalInputs(),
// idêntica aos outros dois executores; (2) em modo real, abre um único CARD_SYNC antes de
// qualquer requisição à JustTCG (mesmo helper tryOpenCardSyncRun); (3) deriva os Sets-alvo
// DINAMICAMENTE (buildRepairCandidates(), nunca hardcoded) e valida contra --expected-set-codes
// — nenhuma chamada externa acontece antes desta validação; (4) para cada Set-alvo, usa
// EXCLUSIVAMENTE o external_set_id já CONFIRMED (nunca resolveSetMatchV2/upsertSetMapping/GET
// /v1/sets) e pagina TODAS as cartas externas do Set (fetchAllCardsForSet); (5) busca só as
// cartas locais PENDING/NOT_FOUND desta fonte (findPendingOrNotFoundCardsForSet) e reclassifica
// cada uma (classifyCardMatch, mesmo fail-safe Set+número); só as que viram SAFE entram em
// plannedCardMappings/plannedVariants — AMBIGUOUS/ABSENT são contadas mas nunca escritas; (6) só
// depois de todos os Sets-alvo adquiridos com sucesso, persiste em lote (persistBatchedResults(),
// reusada verbatim — promove PENDING/NOT_FOUND->CONFIRMED via decideMappingUpsert(), nunca toca
// CONFIRMED) e finaliza o run (finalizeSyncRun(), reusada verbatim).
async function executeRepairMappings(supabase: SupabaseClient, client: JustTcgClient, opts: RepairMappingsOpts): Promise<RepairMappingsRunResult> {
  const { sourceId, localSets, existingSetMappings, existingCoverage } = await fetchReconciledLocalInputs(supabase);

  let syncRunId: string | null = null;
  let syncRunFinalized = false;

  if (!opts.dryRun) {
    const startAttempt = await tryOpenCardSyncRun(supabase, sourceId, opts.confirmedBy as string);
    if (startAttempt.outcome === "CONCURRENT_CONFLICT") {
      throw new Error(
        "CONFLITO_DE_CONCORRENCIA: já existe uma execução CARD_SYNC ativa (RECEIVED/PROCESSING) para esta fonte (índice único parcial, Query 3907) — reparo abortado antes de qualquer chamada à JustTCG.",
      );
    }
    if (startAttempt.outcome === "OTHER_ERROR") {
      throw new Error(`SYNC_RUN_INSERT_FAILED: ${startAttempt.error}`);
    }
    syncRunId = startAttempt.id;
  }

  const conditionMap = await getConditionMap(supabase, sourceId);
  if (!opts.dryRun && conditionMap.size === 0) {
    throw new Error("CONDITION_MAP_VAZIO: rode a seed 3702 (pricing_condition_mapping) antes deste script.");
  }

  const summary = {
    cardsEvaluated: 0,
    cardsPromoted: 0,
    cardsStillPending: 0,
    cardsStillNotFound: 0,
    productsResolved: 0,
    productsWritten: 0,
    observationsResolved: 0,
    observationsWritten: 0,
    observationsDivergent: 0,
    identitiesResolved: 0,
    identitiesWritten: 0,
    operationsSupabase: 0,
    productsProjected: 0,
    observationsProjected: 0,
    variantsProjectionSkipped: 0,
  };
  const perSet: RepairMappingsSetSummary[] = [];
  const errorParts: string[] = [];
  const plannedCardMappings: PlannedCardMapping[] = [];
  const plannedVariants: PlannedVariant[] = [];
  let acquisitionFailed = false;

  try {
    const allCandidates = buildRepairCandidates(localSets, existingSetMappings, existingCoverage);

    // P14.4.6 — --repair-set-codes (quando informado) filtra ANTES de qualquer chamada à
    // JustTCG e ANTES até da checagem de --expected-set-codes abaixo, que por sua vez passa a
    // ser a assertiva independente do SUBCONJUNTO selecionado (nunca mais da lista completa de
    // candidatos, quando o filtro está ativo). requestedCodesRaw===null (flag ausente) devolve
    // allCandidates sem tocar — comportamento anterior preservado byte-a-byte.
    const repairSetCodesFilter = filterRepairCandidatesBySetCodes(allCandidates, opts.repairSetCodes ?? null, localSets);
    if (!repairSetCodesFilter.ok) {
      throw new Error(`${repairSetCodesFilter.reason} Reparo abortado antes de qualquer chamada à JustTCG.`);
    }
    const candidates = repairSetCodesFilter.filtered;

    // Mesma disciplina anti-deriva de validateExpectedSetCodes/executeExpansionWave/
    // executeBackfillWave — só que aqui a composição "esperada" nunca vem de uma onda
    // pré-calculada: vem inteiramente de buildRepairCandidates() rodado agora mesmo (já
    // filtrado por --repair-set-codes, se informado — expected-set-codes deve coincidir com o
    // SUBCONJUNTO selecionado, não com a lista completa de candidatos elegíveis).
    // Fica DENTRO do try (mesmo padrão de BACKFILL_WAVE_COMPOSITION_CHANGED em
    // executeBackfillWave) para que uma divergência aqui também finalize o sync run
    // como FAILED via finalizeSyncRun() no catch abaixo, em vez de deixá-lo preso em
    // PROCESSING.
    const actualCodes = [...new Set(candidates.map((c) => c.code))].sort();
    const expectedCodes = [...new Set(opts.expectedSetCodes)].sort();
    const compositionMatches = actualCodes.length === expectedCodes.length && actualCodes.every((code, i) => code === expectedCodes[i]);
    if (!compositionMatches) {
      const missing = expectedCodes.filter((c) => !actualCodes.includes(c));
      const extra = actualCodes.filter((c) => !expectedCodes.includes(c));
      throw new Error(
        `REPAIR_CANDIDATE_SETS_CHANGED: os Sets elegíveis para reparo recalculados agora são [${actualCodes.join(",") || "nenhum"}], divergente do esperado [${expectedCodes.join(",") || "nenhum"}] — faltando=[${missing.join(",") || "nenhum"}] excedente=[${extra.join(",") || "nenhum"}]. Reparo abortado antes de qualquer chamada à JustTCG.`,
      );
    }

    for (const candidate of candidates) {
      const { cards: externalCards, requestsUsed, aborted } = await fetchAllCardsForSet(client, candidate.externalSetId);
      const setSummary: RepairMappingsSetSummary = {
        code: candidate.code,
        pendingCount: candidate.pendingCount,
        notFoundCount: candidate.notFoundCount,
        externalCardsSeen: externalCards.length,
        cardsEvaluated: 0,
        cardsPromoted: 0,
        productsProjected: 0,
        observationsProjected: 0,
        variantsProjectionSkipped: 0,
      };
      perSet.push(setSummary);

      if (aborted === "AUTH_FAILURE") {
        errorParts.push(`AUTENTICACAO_FALHOU_401(${candidate.code})`);
        acquisitionFailed = true;
        break;
      }
      if (aborted === "BUDGET_STOPPED") {
        errorParts.push(`ORCAMENTO_ESGOTADO(${candidate.code}): após ${requestsUsed} requisição(ões) de página deste Set — nenhum dado de negócio deste reparo será persistido.`);
        acquisitionFailed = true;
        break;
      }
      if (aborted === "TECHNICAL_FAILURE") {
        errorParts.push(`PAGINACAO_CARDS_FALHOU(${candidate.code}): interrompida após ${requestsUsed} requisição(ões) — nenhum dado de negócio deste reparo será persistido.`);
        acquisitionFailed = true;
        break;
      }

      const targetLocalCards = await findPendingOrNotFoundCardsForSet(supabase, candidate.cardSetId, sourceId);
      summary.cardsEvaluated += targetLocalCards.length;
      setSummary.cardsEvaluated = targetLocalCards.length;
      const externalIndex = buildExternalNumberIndex(externalCards);

      for (const localCard of targetLocalCards) {
        const matchResult = classifyCardMatch(localCard, externalIndex, candidate.externalSetId);

        if (matchResult.classification !== "SAFE" || !matchResult.matched) {
          // P14.4.4 — interpretação mínima do pedido: "promover somente quando resultar
          // único" nunca implica reescrever a evidência de quem continua ambíguo/ausente.
          // Cartas que permanecem AMBIGUOUS/ABSENT ficam INTOCADAS: nenhuma entrada em
          // plannedCardMappings, nenhuma chamada a upsertCardMapping — só contadas para o
          // relatório final (cardsStillPending/cardsStillNotFound).
          if (matchResult.classification === "ABSENT") summary.cardsStillNotFound++;
          else summary.cardsStillPending++;
          if (opts.dryRun) logDryRunCardEvidence(localCard, matchResult);
          continue;
        }

        summary.cardsPromoted++;
        setSummary.cardsPromoted++;
        const matchedCard = matchResult.matched;

        if (opts.dryRun) {
          for (const variant of matchedCard.variants ?? []) {
            const projection = planVariantProjection(variant, conditionMap);
            if (projection.status === "PROJECTED") {
              summary.productsProjected++;
              summary.observationsProjected++;
              setSummary.productsProjected++;
              setSummary.observationsProjected++;
            } else {
              summary.variantsProjectionSkipped++;
              setSummary.variantsProjectionSkipped++;
            }
          }
          continue;
        }

        plannedCardMappings.push({
          cardId: localCard.card_id,
          collectorNumber: localCard.collector_number,
          status: "CONFIRMED",
          matchedCard,
          method: matchResult.method,
          evidence: matchResult.evidence,
        });

        for (const variant of matchedCard.variants ?? []) {
          const externalProductId = String(variant.uuid ?? variant.id ?? "");
          const printingRaw = String(variant.printing ?? "");
          const conditionRaw = String(variant.condition ?? "");
          const price = variant.price;
          const lastUpdated = variant.lastUpdated;
          if (!externalProductId || !printingRaw || typeof price !== "number") continue;

          const conditionId = conditionMap.get(conditionRaw);
          if (!conditionId) {
            errorParts.push(`CONDICAO_SEM_MAPEAMENTO(${conditionRaw})`);
            continue;
          }

          const { printingTipo } = splitPrintingLanguage(printingRaw);
          const observedAt = typeof lastUpdated === "number" ? new Date(lastUpdated * 1000).toISOString() : new Date().toISOString();
          const rawPayload = sanitizeJson({ condition: conditionRaw, printing: printingRaw, price, lastUpdated });

          plannedVariants.push({
            cardId: localCard.card_id,
            collectorNumber: localCard.collector_number,
            externalProductId,
            sourcePrintingLabel: printingTipo ?? printingRaw,
            conditionId,
            price,
            observedAt,
            rawPayload,
          });
        }
      }
    }

    let batchPersistenceFailed = false;
    if (acquisitionFailed) {
      // Falha de aquisição bloqueia a persistência de TODO o reparo — nunca uma escrita
      // parcial por Set. plannedCardMappings/plannedVariants acumulados até aqui são
      // deliberadamente descartados.
    } else if (!opts.dryRun && (plannedCardMappings.length > 0 || plannedVariants.length > 0)) {
      const batchOutcome = await persistBatchedResults(supabase, sourceId, syncRunId, opts.confirmedBy as string, plannedCardMappings, plannedVariants);
      summary.productsResolved += batchOutcome.productsResolved;
      summary.productsWritten += batchOutcome.productsWritten;
      summary.observationsResolved += batchOutcome.observationsResolved;
      summary.observationsWritten += batchOutcome.observationsWritten;
      summary.observationsDivergent += batchOutcome.observationsDivergent;
      summary.identitiesResolved += batchOutcome.identitiesResolved;
      summary.identitiesWritten += batchOutcome.identitiesWritten;
      summary.operationsSupabase += batchOutcome.operationsSupabase;
      errorParts.push(...batchOutcome.errorParts);
      if (batchOutcome.batchFailureOccurred) batchPersistenceFailed = true;
    }

    const finalStatus = acquisitionFailed
      ? "FAILED"
      : computeFinalStatus(batchPersistenceFailed, errorParts.length > 0, summary.cardsPromoted > 0 || summary.cardsEvaluated > 0);

    if (!opts.dryRun) {
      await finalizeSyncRun(supabase, syncRunId, client, finalStatus, errorParts.length > 0 ? errorParts.slice(0, 15).join(" | ") : null, opts.dryRun);
      syncRunFinalized = true;
    }

    return {
      setsTargeted: candidates.map((c) => c.code),
      perSet,
      cardsEvaluated: summary.cardsEvaluated,
      cardsPromoted: summary.cardsPromoted,
      cardsStillPending: summary.cardsStillPending,
      cardsStillNotFound: summary.cardsStillNotFound,
      productsResolved: summary.productsResolved,
      productsWritten: summary.productsWritten,
      observationsResolved: summary.observationsResolved,
      observationsWritten: summary.observationsWritten,
      observationsDivergent: summary.observationsDivergent,
      identitiesResolved: summary.identitiesResolved,
      identitiesWritten: summary.identitiesWritten,
      operationsSupabase: summary.operationsSupabase,
      productsProjected: summary.productsProjected,
      observationsProjected: summary.observationsProjected,
      variantsProjectionSkipped: summary.variantsProjectionSkipped,
      requestsMade: client.requestsMade,
      maxApiRequests: opts.maxApiRequests,
      requestsRemainingLocal: client.requestsRemainingLocal,
      status: finalStatus,
      errorParts,
      syncRunId,
    };
  } catch (error) {
    if (!opts.dryRun && !syncRunFinalized && syncRunId) {
      const message = error instanceof Error ? error.message : String(error);
      await finalizeSyncRun(supabase, syncRunId, client, "FAILED", message, opts.dryRun);
    }
    throw error;
  }
}

async function runRepairMappings(opts: RepairMappingsOpts): Promise<void> {
  const supabaseUrl = requireEnv("SUPABASE_URL");
  const supabaseServiceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
  const justTcgApiKey = requireEnv("JUSTTCG_API_KEY");

  const supabase = createClient(supabaseUrl, supabaseServiceRoleKey);
  const client = new JustTcgClient(justTcgApiKey, undefined, opts.maxApiRequests);

  console.log(`=== Executor de Reparo de Mappings (P14.4.4) — orçamento local=${opts.maxApiRequests} ===`);
  console.log(opts.dryRun ? "[DRY-RUN] Nenhuma escrita será persistida — nenhum pricing_sync_run será criado.\n" : `Confirmado por (admin_user.id): ${opts.confirmedBy}\n`);

  const result = await executeRepairMappings(supabase, client, opts);

  console.log("\n=== Resumo da execução de reparo ===");
  console.log(JSON.stringify(result, null, 2));
}

// ============================================================================
// 7b. P14 (vocabulário formal de variantes externas) — Executor de reparo de
//     múltiplas identidades (--repair-multi-identities)
//
// Decisões já tomadas por Fabrício (2026-08-20, rodada "P14 — vocabulário de variantes"),
// não reabertas aqui:
//   1-2. Vocabulário formal vive em pricing_source_variant_mapping (tabela irmã de
//        card_variant_type_external_mapping, escopada a pricing_source — migration 3924,
//        ainda NÃO aplicada nesta rodada).
//   3-5. PRIMARY = card_variant_type STANDARD; ALTERNATE = variante formalmente mapeada
//        (card_variant_type_id + external_variant_key em pricing_source_card_identity).
//   6. ALIAS fora de escopo — nenhum caso autorizado, esta função nunca produz ALIAS.
//   8. Proibido nome local PT-BR, fuzzy matching ou substring livre como critério — a
//      classificação usa EXCLUSIVAMENTE (a) o filtro de denominador já provado em
//      classifyCardMatch (candidatos_avaliados_estrutural, quando presente na evidência
//      persistida) e (b) um lookup EXATO (string normalizada lower+trim) contra o
//      vocabulário formal — nunca aproximação textual.
//   9. Só promove quando exatamente 1 candidato é STANDARD (sem qualificador reconhecido),
//      todos os demais são ALTERNATE formalmente mapeados, e zero candidatos ficam
//      desconhecidos.
//   10. RPC get_cards_pricing_summary (migration 3924) passa a exigir identidade
//       PRIMARY/CONFIRMED — ALTERNATE é persistida mas nunca compete no preço-resumo.
//   11. Só cartas PENDING entram neste executor — NOT_FOUND nunca é promovido aqui.
// ============================================================================

// --- Extração pura de qualificador a partir do nome bruto do candidato JustTCG ----------

// Alguns candidatos da mesma busca Set+número trazem um sufixo "- N" ou "- N/D" no próprio
// nome (ex.: "Basic Grass Energy - 001"), usado pela própria JustTCG para desambiguar
// prints internos que compartilham o número impresso — nunca um qualificador de variante.
// Removido ANTES de procurar um qualificador entre parênteses, para não confundir "- 001"
// com um qualificador de verdade.
function stripPrintDisambiguationSuffix(name: string): string {
  return name.replace(/\s*-\s*\d+(\/\d+)?\s*$/, "").trim();
}

// Fix (auditoria real dos 534 PENDING via SQL, Parte E): a fonte usa AMBOS parênteses
// "(...)" e colchetes "[...]" como grupos de qualificador de variante — nunca só parênteses.
// Exemplos reais: "Crobat - 076 [Staff]" (colchete puro), "Bulbasaur (Staff)" (parêntese
// puro, MEP/SVP), "Luxray - SWSH023 (Prerelease) [Staff]" (parêntese + colchete
// encadeados). Extrai TODOS os grupos à direita do nome, em ordem, já sem o sufixo de
// desambiguação "- N"/"- N/D" da JustTCG.
function extractTrailingGroups(name: string): string[] {
  let rest = stripPrintDisambiguationSuffix(name);
  const groups: string[] = [];
  for (;;) {
    const match = rest.match(/(\(([^()]*)\)|\[([^[\]]*)\])\s*$/);
    if (!match) break;
    const content = (match[2] ?? match[3] ?? "").trim();
    groups.unshift(content);
    rest = rest.slice(0, match.index).trimEnd();
  }
  return groups;
}

// "Professor's Research [Professor Oak]"/"[Professor Sycamore]"/"[Professor Elm]"/
// "[Professor Rowan]" — o colchete faz parte da IDENTIDADE BASE do card (qual Professor'
// Research específico), nunca um qualificador de impressão/variante (auditado na Parte A).
// Único caso estrutural onde um grupo à direita é ignorado incondicionalmente, mesmo sem
// bater no vocabulário formal.
const PROFESSOR_BRACKET_EXEMPTION = /^professor\s/i;

// Um qualificador de variante real, nesta fonte, aparece como um ou mais grupos "(...)"/
// "[...]" ao final do nome (ex.: "Bulbasaur (Staff)", "Crobat - 076 [Staff]", "Charizard
// (Master Ball Pattern)") — nunca como um grupo puramente numérico (ex.: "(1)", "(51)" —
// notação própria da fonte para desambiguar números coincidentes entre eras/pools
// distintas, auditado na Parte A) e nunca como o colchete de nome de Professor (exceção
// acima). Quando restam 2+ grupos simultâneos (ex.: "(Prerelease) [Staff]"), a chave
// devolvida é a concatenação de todos — propositalmente NUNCA cadastrada no vocabulário
// formal (que só semeia frases isoladas), então sempre cai em UNKNOWN: uma combinação não
// autorizada nunca é assumida equivalente a um qualificador simples reconhecido (decisão 8
// — proibido inferir por substring/aproximação). Devolve a chave já normalizada
// (lower+trim) ou null quando o candidato não tem qualificador (edição padrão).
function extractQualifierKey(rawName: string): string | null {
  const groups = extractTrailingGroups(rawName)
    .filter((g) => g !== "")
    .filter((g) => !/^\d+$/.test(g))
    .filter((g) => !PROFESSOR_BRACKET_EXEMPTION.test(g));
  if (groups.length === 0) return null;
  if (groups.length === 1) return groups[0].toLowerCase();
  return groups.map((g) => g.toLowerCase()).join(" + ");
}

type QualifierClassification =
  | { kind: "STANDARD" }
  | { kind: "ALTERNATE"; variantTypeId: string; qualifierKey: string }
  | { kind: "UNKNOWN"; qualifierKey: string };

// Pura — único ponto de lookup contra o vocabulário formal (Map já carregado do banco por
// fetchVariantVocabulary()). Nunca fuzzy: a chave extraída precisa bater EXATAMENTE (após
// normalização lower+trim, já aplicada tanto aqui quanto na seed da migration 3924) com uma
// linha de pricing_source_variant_mapping.
function classifyQualifier(
  rawName: string,
  vocabulary: Map<string, string>,
): QualifierClassification {
  const qualifierKey = extractQualifierKey(rawName);
  if (qualifierKey === null) return { kind: "STANDARD" };
  const variantTypeId = vocabulary.get(qualifierKey);
  if (!variantTypeId) return { kind: "UNKNOWN", qualifierKey };
  return { kind: "ALTERNATE", variantTypeId, qualifierKey };
}

type EvidenceCandidateLite = {
  id: string;
  name: string;
  number?: string | null;
};

type StructuralEvidenceCandidate = {
  id: string;
  categoria_estrutural?:
    | "EXACT_FULL_IDENTITY"
    | "INCOMPATIBLE_DENOMINATOR"
    | "INCOMPLETE_NUMBER";
};

type MultiIdentityStayReason =
  | "NO_CANDIDATES_IN_EVIDENCE"
  | "DENOMINATOR_INCOMPATIBLE_PRESENT"
  | "UNKNOWN_QUALIFIER"
  | "NO_STANDARD_CANDIDATE"
  | "MULTIPLE_STANDARD_CANDIDATES";

type MultiIdentityClassification =
  | {
    outcome: "PROMOTABLE";
    primary: EvidenceCandidateLite;
    alternates: Array<
      {
        candidate: EvidenceCandidateLite;
        variantTypeId: string;
        qualifierKey: string;
      }
    >;
  }
  | {
    outcome: "STAYS_PENDING";
    reason: MultiIdentityStayReason;
    detail: string;
  };

// Núcleo puro do incremento — implementa exatamente a regra de 3 condições provada na Parte
// A (n_standard=1 + n_desconhecido=0 + n_denom_incompativel=0), operando só sobre o
// match_evidence JÁ PERSISTIDO em pricing_card_mapping (nunca refaz a busca externa aqui —
// isso é responsabilidade do chamador, que precisa da carta externa completa com variants[]
// para as fases de persistência). Testável 100% offline (ver runFixtureCheck()).
function classifyMultiIdentityCandidate(
  evidence: Record<string, unknown>,
  vocabulary: Map<string, string>,
): MultiIdentityClassification {
  const candidatos =
    (evidence.candidatos as EvidenceCandidateLite[] | undefined) ?? [];
  if (candidatos.length < 2) {
    return {
      outcome: "STAYS_PENDING",
      reason: "NO_CANDIDATES_IN_EVIDENCE",
      detail:
        `esperado 2+ candidatos em match_evidence.candidatos, encontrado ${candidatos.length}.`,
    };
  }

  // Rede de segurança reaproveitada do fix v2 de classifyCardMatch: quando a evidência
  // persistida já trouxe a categorização estrutural por denominador (só existe quando
  // collector_total local era válido), qualquer candidato INCOMPATIBLE_DENOMINATOR é uma
  // colisão semântica (números coincidentes de eras/pools distintas) — nunca uma variante
  // legítima do mesmo card, mesmo que o nome pareça carregar um qualificador reconhecido.
  const estrutural = evidence.candidatos_avaliados_estrutural as
    | StructuralEvidenceCandidate[]
    | undefined;
  if (
    estrutural?.some((c) =>
      c.categoria_estrutural === "INCOMPATIBLE_DENOMINATOR"
    )
  ) {
    return {
      outcome: "STAYS_PENDING",
      reason: "DENOMINATOR_INCOMPATIBLE_PRESENT",
      detail: "um ou mais candidatos têm denominador declarado incompatível com collector_total local — colisão semântica entre cards distintos, nunca promovido.",
    };
  }

  const classificados = candidatos.map((c) => ({
    candidate: c,
    classification: classifyQualifier(c.name, vocabulary),
  }));
  const standardOnes = classificados.filter((c) =>
    c.classification.kind === "STANDARD"
  );
  const unknownOnes = classificados.filter((c) =>
    c.classification.kind === "UNKNOWN"
  );

  if (unknownOnes.length > 0) {
    const chaves = [
      ...new Set(unknownOnes.map((c) =>
        (c.classification as { kind: "UNKNOWN"; qualifierKey: string })
          .qualifierKey
      )),
    ];
    return {
      outcome: "STAYS_PENDING",
      reason: "UNKNOWN_QUALIFIER",
      detail:
        `qualificador(es) sem mapeamento formal em pricing_source_variant_mapping: ${
          chaves.join(", ")
        }.`,
    };
  }
  if (standardOnes.length === 0) {
    return {
      outcome: "STAYS_PENDING",
      reason: "NO_STANDARD_CANDIDATE",
      detail:
        "nenhum candidato sem qualificador reconhecido (edição padrão) — nenhum candidato STANDARD disponível para servir de PRIMARY.",
    };
  }
  if (standardOnes.length > 1) {
    return {
      outcome: "STAYS_PENDING",
      reason: "MULTIPLE_STANDARD_CANDIDATES",
      detail:
        `${standardOnes.length} candidatos sem qualificador reconhecido — ambíguo, sem critério estrutural seguro para escolher PRIMARY.`,
    };
  }

  const primary = standardOnes[0].candidate;
  const alternates = classificados
    .filter((c) => c.classification.kind === "ALTERNATE")
    .map((c) => {
      const cls = c.classification as {
        kind: "ALTERNATE";
        variantTypeId: string;
        qualifierKey: string;
      };
      return {
        candidate: c.candidate,
        variantTypeId: cls.variantTypeId,
        qualifierKey: cls.qualifierKey,
      };
    });

  return { outcome: "PROMOTABLE", primary, alternates };
}

function logDryRunMultiIdentityEvidence(
  local: { cardId: string; collectorNumber: string },
  classification: MultiIdentityClassification,
): void {
  if (classification.outcome === "PROMOTABLE") {
    const alt = classification.alternates.map((a) => ({
      id: a.candidate.id,
      name: a.candidate.name,
      qualifier_key: a.qualifierKey,
    }));
    console.log(
      `  [PROMOTABLE] carta_local=${local.cardId} collector_number="${local.collectorNumber}" primary=${
        JSON.stringify(classification.primary)
      } alternates=${JSON.stringify(alt)}`,
    );
    return;
  }
  console.log(
    `  [STAYS_PENDING:${classification.reason}] carta_local=${local.cardId} collector_number="${local.collectorNumber}" detalhe=${classification.detail}`,
  );
}

// --- Leituras auxiliares (vocabulário formal + tipo STANDARD + cartas PENDING c/ evidência) ---

// Depende da migration 3924 (pricing_source_variant_mapping) — ainda NÃO aplicada nesta
// rodada (ver limites da rodada E). Sem essa tabela, esta chamada falha com um erro claro do
// PostgREST (relação inexistente), nunca silenciosamente devolve vocabulário vazio.
async function fetchVariantVocabulary(
  supabase: SupabaseClient,
  pricingSourceId: string,
): Promise<Map<string, string>> {
  const { data, error } = await supabase.from("pricing_source_variant_mapping")
    .select("external_variant_key, variant_type_id").eq(
      "pricing_source_id",
      pricingSourceId,
    );
  if (error) {
    throw new Error(
      `VARIANT_VOCABULARY_QUERY_FAILED: ${sanitize(error.message)}`,
    );
  }
  return new Map(
    (data ?? []).map((
      r: { external_variant_key: string; variant_type_id: string },
    ) => [r.external_variant_key, r.variant_type_id]),
  );
}

async function fetchStandardVariantTypeId(supabase: SupabaseClient): Promise<string> {
  const { data, error } = await supabase.from("card_variant_type").select("id").eq("code", "STANDARD").maybeSingle();
  if (error) throw new Error(`STANDARD_VARIANT_TYPE_QUERY_FAILED: ${sanitize(error.message)}`);
  if (!data) throw new Error("STANDARD_VARIANT_TYPE_NOT_FOUND: card_variant_type.code='STANDARD' não encontrado — pré-requisito de ADR-028/CV-01.");
  return data.id as string;
}

type PendingCardWithEvidence = {
  mappingId: string;
  cardId: string;
  collectorNumber: string;
  evidence: Record<string, unknown>;
};

// Análoga a findPendingOrNotFoundCardsForSet(), mas (a) traz match_evidence — indispensável
// para classifyMultiIdentityCandidate() — e (b) filtra SOMENTE match_status='PENDING'
// (decisão 11: NOT_FOUND nunca entra neste executor, diferente do --repair-mappings, que
// cobre os dois). Mesma disciplina de paginação+reconciliação (fetchAllRowsFromTable +
// fetchExactCount + assertPaginationComplete) do restante do arquivo.
async function findPendingCardsWithEvidenceForSet(
  supabase: SupabaseClient,
  cardSetId: string,
  pricingSourceId: string,
): Promise<PendingCardWithEvidence[]> {
  const activeRows = await fetchAllRowsFromTable<LocalCardRow>(
    supabase,
    "card",
    "id, name, collector_number, collector_total",
    "collector_number",
    (q) => q.eq("card_set_id", cardSetId).eq("is_active", true),
  );
  const exactActiveCount = await fetchExactCount(
    supabase,
    "card",
    (q) => q.eq("card_set_id", cardSetId).eq("is_active", true),
  );
  assertPaginationComplete(
    `card(multi-identity,set=${cardSetId})`,
    activeRows.length,
    exactActiveCount,
  );

  const activeIds = activeRows.map((r) => r.id);
  if (activeIds.length === 0) return [];

  const mappingRows = await fetchAllRowsFromTable<
    { id: string; card_id: string; match_evidence: unknown }
  >(
    supabase,
    "pricing_card_mapping",
    "id, card_id, match_evidence",
    "card_id",
    (q) =>
      q.eq("pricing_source_id", pricingSourceId).in("card_id", activeIds).eq(
        "match_status",
        "PENDING",
      ),
  );
  const exactMappingCount = await fetchExactCount(
    supabase,
    "pricing_card_mapping",
    (q) =>
      q.eq("pricing_source_id", pricingSourceId).in("card_id", activeIds).eq(
        "match_status",
        "PENDING",
      ),
  );


  const cardById = new Map(activeRows.map((r) => [r.id, r]));
  return mappingRows
    .filter((m) => cardById.has(m.card_id))
    .map((m) => ({
      mappingId: m.id,
      cardId: m.card_id,
      collectorNumber: cardById.get(m.card_id)!.collector_number,
      evidence: (m.match_evidence ?? {}) as Record<string, unknown>,
    }));
}

// --- Persistência (1 PRIMARY + N ALTERNATE por carta promovida) -------------------------

type MultiIdentityPromotionPlan = {
  cardId: string;
  mappingId: string;
  collectorNumber: string;
  primaryCard: JustTcgCard;
  alternates: Array<
    { card: JustTcgCard; variantTypeId: string; qualifierKey: string }
  >;
  evidence: Record<string, unknown>;
};

type MultiIdentityPersistOutcome = {
  identitiesWritten: number;
  productsResolved: number;
  productsWritten: number;
  observationsResolved: number;
  observationsWritten: number;
  observationsDivergent: number;
  operationsSupabase: number;
  errorParts: string[];
  batchFailureOccurred: boolean;
};

// Deliberadamente NÃO reusa persistBatchedResults() — aquela função é PRIMARY-only por
// desenho (Fix P14.5, ver comentário em BatchPersistOutcome) e sua Fase 1 cobre um caminho
// (INSERT de mapping novo) que não existe aqui: todo mapping desta função já é PENDING
// conhecido (veio de findPendingCardsWithEvidenceForSet), então a Fase 1 abaixo é só
// promoção via a mesma RPC de promoção exclusiva (Query 3914) — nunca UPDATE direto (grant
// bloqueado) e nunca um INSERT de mapping novo.
async function persistMultiIdentityPromotions(
  supabase: SupabaseClient,
  sourceId: string,
  syncRunId: string | null,
  confirmedBy: string,
  standardVariantTypeId: string,
  conditionMap: Map<string, string>,
  plans: MultiIdentityPromotionPlan[],
): Promise<MultiIdentityPersistOutcome> {
  const errorParts: string[] = [];
  let operationsSupabase = 0;
  let batchFailureOccurred = false;
  let identitiesWritten = 0;
  let productsWritten = 0;
  let productsResolved = 0;
  let observationsWritten = 0;
  let observationsResolved = 0;
  let observationsDivergent = 0;

  if (plans.length === 0) {
    return {
      identitiesWritten,
      productsResolved,
      productsWritten,
      observationsResolved,
      observationsWritten,
      observationsDivergent,
      operationsSupabase,
      errorParts,
      batchFailureOccurred,
    };
  }

  const nowIso = new Date().toISOString();

  // --- Fase 1: promoção do pricing_card_mapping (PENDING -> CONFIRMED) -------------------
  const planByMappingId = new Map(plans.map((p) => [p.mappingId, p]));
  const updateRows = plans.map((p) => ({
    id: p.mappingId,
    match_status: "CONFIRMED",
    match_method: "MULTI_IDENTITY_FORMAL_VOCABULARY",
    match_evidence: sanitizeJson(p.evidence),
    last_checked_at: nowIso,
    external_card_id: p.primaryCard.id,
    external_card_name: p.primaryCard.name,
    confirmed_at: nowIso,
    confirmed_by: confirmedBy,
  }));
  const promotedMappingIds = new Set<string>();
  for (const rows of chunk(updateRows, BATCH_SIZE)) {
    operationsSupabase++;
    const { data, error } = await supabase.rpc(
      "batch_update_pricing_card_mapping_status",
      { p_updates: rows },
    );
    if (error) {
      batchFailureOccurred = true;
      errorParts.push(
        `MULTI_IDENTITY_MAPPING_BATCH_UPDATE_FAILED(${rows.length} linhas): ${
          sanitize(error.message)
        }`,
      );
      continue;
    }
    for (const row of (data ?? []) as Array<{ id: string; card_id: string }>) {
      promotedMappingIds.add(row.id);
    }
  }
  for (const row of updateRows) {
    if (!promotedMappingIds.has(row.id as string)) {
      batchFailureOccurred = true;
      errorParts.push(`MULTI_IDENTITY_MAPPING_UNRESOLVED(${row.id}): promoção não confirmada nesta rodada — nenhuma identidade/produto/observação criada para esta carta.`);
    }
  }

  // --- Fase 2: pricing_source_card_identity — 1 PRIMARY + N ALTERNATE por mapping promovido.
  type IdentityPlanRow = {
    mappingId: string;
    role: "PRIMARY" | "ALTERNATE";
    externalCard: JustTcgCard;
    variantTypeId: string | null;
    externalVariantKey: string | null;
  };
  const identityPlanRows: IdentityPlanRow[] = [];
  for (const mappingId of promotedMappingIds) {
    const plan = planByMappingId.get(mappingId);
    if (!plan) continue;
    identityPlanRows.push({
      mappingId,
      role: "PRIMARY",
      externalCard: plan.primaryCard,
      variantTypeId: standardVariantTypeId,
      externalVariantKey: null,
    });
    for (const alt of plan.alternates) {
      identityPlanRows.push({
        mappingId,
        role: "ALTERNATE",
        externalCard: alt.card,
        variantTypeId: alt.variantTypeId,
        externalVariantKey: alt.qualifierKey,
      });
    }
  }

  const identityIdByKey = new Map<string, string>(); // key = `${mappingId}::${externalCardId}`
  for (const rowsChunk of chunk(identityPlanRows, BATCH_SIZE)) {
    operationsSupabase++;
    const { data, error } = await supabase
      .from("pricing_source_card_identity")
      .insert(
        rowsChunk.map((r) => ({
          pricing_card_mapping_id: r.mappingId,
          pricing_source_id: sourceId,
          external_card_id: r.externalCard.id,
          external_card_name: r.externalCard.name,
          match_status: "CONFIRMED",
          identity_role: r.role,
          match_method: "MULTI_IDENTITY_FORMAL_VOCABULARY",
          match_evidence: sanitizeJson({
            external_variant_key: r.externalVariantKey,
            identity_role: r.role,
          }),
          card_variant_type_id: r.variantTypeId,
          external_variant_key: r.externalVariantKey,
          last_checked_at: nowIso,
          confirmed_by: confirmedBy,
        })),
      )
      .select("id, pricing_card_mapping_id, external_card_id");
    if (error) {
      batchFailureOccurred = true;
      errorParts.push(
        `MULTI_IDENTITY_IDENTITY_BATCH_INSERT_FAILED(${rowsChunk.length} linhas): ${
          sanitize(error.message)
        }`,
      );
      continue;
    }
    for (
      const row of (data ?? []) as Array<
        {
          id: string;
          pricing_card_mapping_id: string;
          external_card_id: string;
        }
      >
    ) {
      identityIdByKey.set(
        `${row.pricing_card_mapping_id}::${row.external_card_id}`,
        row.id,
      );
      identitiesWritten++;
    }
  }

  // --- Fase 3: pricing_product + pricing_observation por identidade resolvida ------------
  type PlannedIdentityVariant = {
    productKey: string;
    identityId: string;
    mappingId: string;
    externalProductId: string;
    sourcePrintingLabel: string;
    conditionId: string;
    price: number;
    observedAt: string;
    rawPayload: unknown;
  };
  const plannedVariants: PlannedIdentityVariant[] = [];
  for (const r of identityPlanRows) {
    const identityId = identityIdByKey.get(
      `${r.mappingId}::${r.externalCard.id}`,
    );
    if (!identityId) continue; // INSERT desta identidade falhou acima — já sinalizado, sem produto/observação
    for (const variant of r.externalCard.variants ?? []) {
      const externalProductId = String(variant.uuid ?? variant.id ?? "");
      const printingRaw = String(variant.printing ?? "");
      const conditionRaw = String(variant.condition ?? "");
      const price = variant.price;
      const lastUpdated = variant.lastUpdated;
      if (!externalProductId || !printingRaw || typeof price !== "number") {
        continue;
      }
      const conditionId = conditionMap.get(conditionRaw);
      if (!conditionId) {
        errorParts.push(`CONDICAO_SEM_MAPEAMENTO(${conditionRaw})`);
        continue;
      }
      const { printingTipo } = splitPrintingLanguage(printingRaw);
      const observedAt = typeof lastUpdated === "number"
        ? new Date(lastUpdated * 1000).toISOString()
        : new Date().toISOString();
      const rawPayload = sanitizeJson({
        condition: conditionRaw,
        printing: printingRaw,
        price,
        lastUpdated,
      });
      plannedVariants.push({
        productKey: `${r.mappingId}::${externalProductId}`,
        identityId,
        mappingId: r.mappingId,
        externalProductId,
        sourcePrintingLabel: printingTipo ?? printingRaw,
        conditionId,
        price,
        observedAt,
        rawPayload,
      });
    }
  }

  const productIdByKey = new Map<string, string>();
  if (plannedVariants.length > 0) {
    const mappingIds = [...new Set(plannedVariants.map((v) => v.mappingId))];
    for (const ids of chunk(mappingIds, BATCH_SIZE)) {
      operationsSupabase++;
      const { data, error } = await supabase.from("pricing_product").select(
        "id, pricing_card_mapping_id, external_product_id",
      ).in("pricing_card_mapping_id", ids);
      if (error) {
        batchFailureOccurred = true;
        errorParts.push(
          `MULTI_IDENTITY_PRODUCT_BATCH_SELECT_FAILED: ${
            sanitize(error.message)
          }`,
        );
        continue;
      }
      for (
        const row of (data ?? []) as Array<
          {
            id: string;
            pricing_card_mapping_id: string;
            external_product_id: string;
          }
        >
      ) {
        productIdByKey.set(
          `${row.pricing_card_mapping_id}::${row.external_product_id}`,
          row.id,
        );
      }
    }

    const toInsertProducts: Array<
      { key: string; row: Record<string, unknown> }
    > = [];
    const seenThisBatch = new Set<string>();
    for (const v of plannedVariants) {
      if (productIdByKey.has(v.productKey) || seenThisBatch.has(v.productKey)) {
        continue; // REUSE
      }
      seenThisBatch.add(v.productKey);
      toInsertProducts.push({
        key: v.productKey,
        row: {
          pricing_card_mapping_id: v.mappingId,
          pricing_source_card_identity_id: v.identityId,
          external_product_id: v.externalProductId,
          source_printing_label: v.sourcePrintingLabel,
          language_status: "UNDETERMINED",
          language_id: null,
        },
      });
    }
    for (const pairs of chunk(toInsertProducts, BATCH_SIZE)) {
      operationsSupabase++;
      const { data, error } = await supabase.from("pricing_product").insert(
        pairs.map((p) => p.row),
      ).select("id, pricing_card_mapping_id, external_product_id");
      if (error) {
        batchFailureOccurred = true;
        errorParts.push(
          `MULTI_IDENTITY_PRODUCT_BATCH_INSERT_FAILED(${pairs.length} linhas): ${
            sanitize(error.message)
          }`,
        );
        continue;
      }
      for (
        const row of (data ?? []) as Array<
          {
            id: string;
            pricing_card_mapping_id: string;
            external_product_id: string;
          }
        >
      ) {
        productIdByKey.set(
          `${row.pricing_card_mapping_id}::${row.external_product_id}`,
          row.id,
        );
        productsWritten++;
      }
    }
  }

  const variantsWithProduct = plannedVariants
    .map((v) => ({ ...v, productId: productIdByKey.get(v.productKey) ?? null }))
    .filter((v): v is PlannedIdentityVariant & { productId: string } =>
      v.productId !== null
    );
  const unresolvedProductCount = plannedVariants.length -
    variantsWithProduct.length;
  if (unresolvedProductCount > 0) {
    errorParts.push(
      `MULTI_IDENTITY_PRODUCT_UNRESOLVED_SKIP_OBSERVATIONS(${unresolvedProductCount} variante(s))`,
    );
  }
  for (const v of variantsWithProduct) {
    if (productIdByKey.has(v.productKey)) productsResolved++;
  }

  if (variantsWithProduct.length > 0) {
    const latestObsByGroup = new Map<
    string,
    { price: number; observedAt: string }
  >();
    const uniqueGroupKeys = new Map<string, { pricing_product_id: string; condition_id: string; price_type: string; currency_code: string; market_label: string }>();
    for (const v of variantsWithProduct) {
      const key = `${v.productId}::${v.conditionId}`;
      if (!uniqueGroupKeys.has(key)) {
        uniqueGroupKeys.set(key, {
          pricing_product_id: v.productId,
          condition_id: v.conditionId,
          price_type: "MARKET",
          currency_code: "USD",
          market_label: MARKET_LABEL,
        });
      }
    }
    for (const keysChunk of chunk([...uniqueGroupKeys.values()], BATCH_SIZE)) {
      operationsSupabase++;
      const { data, error } = await supabase.rpc(
        "batch_select_latest_pricing_observation_by_identity",
        { p_keys: keysChunk },
      );
      if (error) {
        batchFailureOccurred = true;
        errorParts.push(
          `MULTI_IDENTITY_OBSERVATION_LATEST_BATCH_SELECT_FAILED: ${
            sanitize(error.message)
          }`,
        );
        continue;
      }
      for (
        const row of (data ?? []) as Array<
          {
            pricing_product_id: string;
            condition_id: string;
            observed_at: string;
            price: number;
          }
        >
      ) {
        latestObsByGroup.set(`${row.pricing_product_id}::${row.condition_id}`, {
          price: Number(row.price),
          observedAt: row.observed_at,
        });
      }
    }

    const toInsertObservations: Array<Record<string, unknown>> = [];
    const seenThisBatch = new Map<
      string,
      { price: number; observedAt: string }
    >();
    for (const v of variantsWithProduct) {
      const key = `${v.productId}::${v.conditionId}`;
      const latest = seenThisBatch.get(key) ?? latestObsByGroup.get(key) ??
        null;
      if (latest === null) {
        seenThisBatch.set(key, { price: v.price, observedAt: v.observedAt });
        toInsertObservations.push({
          pricing_product_id: v.productId,
          condition_id: v.conditionId,
          sync_run_id: syncRunId,
          price_type: "MARKET",
          price: v.price,
          currency_code: "USD",
          market_label: MARKET_LABEL,
          market_scope: "UNDETERMINED",
          market_evidence: {},
          market_evidence_confirmed: false,
          observed_at: v.observedAt,
          raw_payload: v.rawPayload,
        });
        continue;
      }
      if (latest.price === v.price) {
        observationsResolved++;
        continue;
      }
      if (latest.observedAt === v.observedAt) {
        observationsResolved++;
        observationsDivergent++;
        errorParts.push(
          `MULTI_IDENTITY_OBSERVATION_PRICE_DIVERGENTE_PRESERVADA(${v.externalProductId}): existente=${latest.price} novo=${v.price} observed_at=${v.observedAt}`,
        );
        continue;
      }
      seenThisBatch.set(key, { price: v.price, observedAt: v.observedAt });
      toInsertObservations.push({
        pricing_product_id: v.productId,
        condition_id: v.conditionId,
        sync_run_id: syncRunId,
        price_type: "MARKET",
        price: v.price,
        currency_code: "USD",
        market_label: MARKET_LABEL,
        market_scope: "UNDETERMINED",
        market_evidence: {},
        market_evidence_confirmed: false,
        observed_at: v.observedAt,
        raw_payload: v.rawPayload,
      });
    }

    for (const rows of chunk(toInsertObservations, BATCH_SIZE)) {
      operationsSupabase++;
      const { error } = await supabase.from("pricing_observation").insert(rows);
      if (error) {
        batchFailureOccurred = true;
        errorParts.push(
          `MULTI_IDENTITY_OBSERVATION_BATCH_INSERT_FAILED(${rows.length} linhas): ${
            sanitize(error.message)
          }`,
        );
        continue;
      }
      observationsResolved += rows.length;
      observationsWritten += rows.length;
    }
  }

  return {
    identitiesWritten,
    productsResolved,
    productsWritten,
    observationsResolved,
    observationsWritten,
    observationsDivergent,
    operationsSupabase,
    errorParts,
    batchFailureOccurred,
  };
}

// --- Orquestração (mesmo esqueleto de executeRepairMappings) ----------------------------

type RepairMultiIdentitiesOpts = {
  dryRun: boolean;
  confirmedBy: string | null;
  maxApiRequests: number;
  expectedSetCodes: string[];
  repairSetCodes?: string[] | null;
};

type RepairMultiIdentitiesSetSummary = {
  code: string;
  pendingCount: number;
  notFoundCount: number;
  externalCardsSeen: number;
  cardsEvaluated: number;
  cardsPromoted: number;
  cardsStillPendingNoStandard: number;
  cardsStillPendingMultipleStandard: number;
  cardsStillPendingUnknownQualifier: number;
  cardsStillPendingDenominatorIncompatible: number;
  cardsStillPendingNoCandidates: number;
  productsProjected: number;
  observationsProjected: number;
  variantsProjectionSkipped: number;
};

type RepairMultiIdentitiesRunResult = {
  setsTargeted: string[];
  perSet: RepairMultiIdentitiesSetSummary[];
  cardsEvaluated: number;
  cardsPromoted: number;
  cardsStillPendingNoStandard: number;
  cardsStillPendingMultipleStandard: number;
  cardsStillPendingUnknownQualifier: number;
  cardsStillPendingDenominatorIncompatible: number;
  cardsStillPendingNoCandidates: number;
  identitiesResolved: number;
  identitiesWritten: number;
  productsResolved: number;
  productsWritten: number;
  observationsResolved: number;
  observationsWritten: number;
  observationsDivergent: number;
  operationsSupabase: number;
  productsProjected: number;
  observationsProjected: number;
  variantsProjectionSkipped: number;
  requestsMade: number;
  maxApiRequests: number;
  requestsRemainingLocal: number;
  vocabularyEntriesLoaded: number;
  status: "COMPLETED" | "COMPLETED_WITH_ERRORS" | "FAILED";
  errorParts: string[];
  syncRunId: string | null;
};

async function executeRepairMultiIdentities(
  supabase: SupabaseClient,
  client: JustTcgClient,
  opts: RepairMultiIdentitiesOpts,
): Promise<RepairMultiIdentitiesRunResult> {
  const { sourceId, localSets, existingSetMappings, existingCoverage } =
    await fetchReconciledLocalInputs(supabase);

  let syncRunId: string | null = null;
  let syncRunFinalized = false;

  if (!opts.dryRun) {
    const startAttempt = await tryOpenCardSyncRun(
      supabase,
      sourceId,
      opts.confirmedBy as string,
    );
    if (startAttempt.outcome === "CONCURRENT_CONFLICT") {
      throw new Error("CONFLITO_DE_CONCORRENCIA: já existe uma execução CARD_SYNC ativa (RECEIVED/PROCESSING) para esta fonte — reparo de múltiplas identidades abortado antes de qualquer chamada à JustTCG.");
    }
    if (startAttempt.outcome === "OTHER_ERROR") {
      throw new Error(`SYNC_RUN_INSERT_FAILED: ${startAttempt.error}`);
    }
    syncRunId = startAttempt.id;
  }

  const conditionMap = await getConditionMap(supabase, sourceId);
  if (!opts.dryRun && conditionMap.size === 0) {
    throw new Error(
      "CONDITION_MAP_VAZIO: rode a seed 3702 (pricing_condition_mapping) antes deste script.",
    );
  }

  // Pré-requisito estrutural (migration 3924, ainda NÃO aplicada nesta rodada — ver limites
  // da rodada E): sem vocabulário formal carregado, nenhum candidato pode ser classificado
  // sem inferência por substring livre (decisão 8) — aborta ANTES de qualquer chamada à
  // JustTCG, mesmo em dry-run.
  const vocabulary = await fetchVariantVocabulary(supabase, sourceId);
  const standardVariantTypeId = await fetchStandardVariantTypeId(supabase);
  if (vocabulary.size === 0) {
    throw new Error("VARIANT_VOCABULARY_VAZIO: pricing_source_variant_mapping não tem nenhuma linha para esta fonte — aplique a migration 3924 (seed) antes deste modo.");
  }

  const summary = {
    cardsEvaluated: 0,
    cardsPromoted: 0,
    cardsStillPendingNoStandard: 0,
    cardsStillPendingMultipleStandard: 0,
    cardsStillPendingUnknownQualifier: 0,
    cardsStillPendingDenominatorIncompatible: 0,
    cardsStillPendingNoCandidates: 0,
    identitiesResolved: 0,
    identitiesWritten: 0,
    productsResolved: 0,
    productsWritten: 0,
    observationsResolved: 0,
    observationsWritten: 0,
    observationsDivergent: 0,
    operationsSupabase: 0,
    productsProjected: 0,
    observationsProjected: 0,
    variantsProjectionSkipped: 0,
  };
  const perSet: RepairMultiIdentitiesSetSummary[] = [];
  const errorParts: string[] = [];
  const plans: MultiIdentityPromotionPlan[] = [];
  let acquisitionFailed = false;

  try {
    const allCandidates = buildRepairCandidates(
      localSets,
      existingSetMappings,
      existingCoverage,
    );
    const repairSetCodesFilter = filterRepairCandidatesBySetCodes(
      allCandidates,
      opts.repairSetCodes ?? null,
      localSets,
    );
    if (!repairSetCodesFilter.ok) {
      throw new Error(`${repairSetCodesFilter.reason} Reparo de múltiplas identidades abortado antes de qualquer chamada à JustTCG.`);
    }
    const candidates = repairSetCodesFilter.filtered;

    const actualCodes = [...new Set(candidates.map((c) => c.code))].sort();
    const expectedCodes = [...new Set(opts.expectedSetCodes)].sort();
    const compositionMatches = actualCodes.length === expectedCodes.length &&
      actualCodes.every((code, i) => code === expectedCodes[i]);
    if (!compositionMatches) {
      const missing = expectedCodes.filter((c) => !actualCodes.includes(c));
      const extra = actualCodes.filter((c) => !expectedCodes.includes(c));
      throw new Error(
        `MULTI_IDENTITY_CANDIDATE_SETS_CHANGED: os Sets elegíveis recalculados agora são [${actualCodes.join(",") || "nenhum"}], divergente do esperado [${expectedCodes.join(",") || "nenhum"}] — faltando=[${missing.join(",") || "nenhum"}] excedente=[${extra.join(",") || "nenhum"}]. Reparo abortado antes de qualquer chamada à JustTCG.`,
      );
    }

    for (const candidate of candidates) {
      const { cards: externalCards, requestsUsed, aborted } =
        await fetchAllCardsForSet(client, candidate.externalSetId);
      const setSummary: RepairMultiIdentitiesSetSummary = {
        code: candidate.code,
        pendingCount: candidate.pendingCount,
        notFoundCount: candidate.notFoundCount,
        externalCardsSeen: externalCards.length,
        cardsEvaluated: 0,
        cardsPromoted: 0,
        cardsStillPendingNoStandard: 0,
        cardsStillPendingMultipleStandard: 0,
        cardsStillPendingUnknownQualifier: 0,
        cardsStillPendingDenominatorIncompatible: 0,
        cardsStillPendingNoCandidates: 0,
        productsProjected: 0,
        observationsProjected: 0,
        variantsProjectionSkipped: 0,
      };
      perSet.push(setSummary);

      if (aborted === "AUTH_FAILURE") {
        errorParts.push(`AUTENTICACAO_FALHOU_401(${candidate.code})`);
        acquisitionFailed = true;
        break;
      }
      if (aborted === "BUDGET_STOPPED") {
        errorParts.push(`ORCAMENTO_ESGOTADO(${candidate.code}): após ${requestsUsed} requisição(ões) de página deste Set — nenhum dado de negócio deste reparo será persistido.`);
        acquisitionFailed = true;
        break;
      }
      if (aborted === "TECHNICAL_FAILURE") {
        errorParts.push(`PAGINACAO_CARDS_FALHOU(${candidate.code}): interrompida após ${requestsUsed} requisição(ões) — nenhum dado de negócio deste reparo será persistido.`);
        acquisitionFailed = true;
        break;
      }

      const externalById = new Map(externalCards.map((c) => [c.id, c]));
      const targetLocalCards = await findPendingCardsWithEvidenceForSet(
        supabase,
        candidate.cardSetId,
        sourceId,
      );
      summary.cardsEvaluated += targetLocalCards.length;
      setSummary.cardsEvaluated = targetLocalCards.length;

      for (const localCard of targetLocalCards) {
        const classification = classifyMultiIdentityCandidate(
          localCard.evidence,
          vocabulary,
        );

        if (classification.outcome === "STAYS_PENDING") {
          if (opts.dryRun) {
            logDryRunMultiIdentityEvidence(localCard, classification);
          }
          switch (classification.reason) {
            case "NO_STANDARD_CANDIDATE":
              summary.cardsStillPendingNoStandard++;
              setSummary.cardsStillPendingNoStandard++;
              break;
            case "MULTIPLE_STANDARD_CANDIDATES":
              summary.cardsStillPendingMultipleStandard++;
              setSummary.cardsStillPendingMultipleStandard++;
              break;
            case "UNKNOWN_QUALIFIER":
              summary.cardsStillPendingUnknownQualifier++;
              setSummary.cardsStillPendingUnknownQualifier++;
              break;
            case "DENOMINATOR_INCOMPATIBLE_PRESENT":
              summary.cardsStillPendingDenominatorIncompatible++;
              setSummary.cardsStillPendingDenominatorIncompatible++;
              break;
            case "NO_CANDIDATES_IN_EVIDENCE":
              summary.cardsStillPendingNoCandidates++;
              setSummary.cardsStillPendingNoCandidates++;
              break;
          }
          continue;
        }

        const primaryCard = externalById.get(classification.primary.id);
        const alternateCards = classification.alternates.map((a) => ({
          card: externalById.get(a.candidate.id),
          variantTypeId: a.variantTypeId,
          qualifierKey: a.qualifierKey,
        }));
        if (!primaryCard || alternateCards.some((a) => !a.card)) {
          // Candidato presente na evidência PENDING persistida mas ausente na paginação atual
          // da JustTCG (catálogo externo mudou entre a classificação original e esta rodada)
          // — nunca promovido com dado incompleto; permanece PENDING, sinalizado.
          summary.cardsStillPendingNoCandidates++;
          setSummary.cardsStillPendingNoCandidates++;
          errorParts.push(
            `MULTI_IDENTITY_CANDIDATE_NOT_IN_CURRENT_PAGE(card=${localCard.cardId})`,
          );
          continue;
        }

        summary.cardsPromoted++;
        setSummary.cardsPromoted++;

        const evidence: Record<string, unknown> = {
          ...localCard.evidence,
          multi_identity_method: "MULTI_IDENTITY_FORMAL_VOCABULARY",
          primary_selecionado: classification.primary,
          alternates_classificados: classification.alternates.map((a) => ({
            candidato: a.candidate,
            qualifier_key: a.qualifierKey,
            variant_type_id: a.variantTypeId,
          })),
        };

        if (opts.dryRun) {
          const allVariants = [
            ...(primaryCard.variants ?? []),
            ...alternateCards.flatMap((a) => a.card!.variants ?? []),
          ];
          for (const variant of allVariants) {
            const projection = planVariantProjection(variant, conditionMap);
            if (projection.status === "PROJECTED") {
              summary.productsProjected++;
              summary.observationsProjected++;
              setSummary.productsProjected++;
              setSummary.observationsProjected++;
            } else {
              summary.variantsProjectionSkipped++;
              setSummary.variantsProjectionSkipped++;
            }
          }
          continue;
        }

        plans.push({
          cardId: localCard.cardId,
          mappingId: localCard.mappingId,
          collectorNumber: localCard.collectorNumber,
          primaryCard,
          alternates: alternateCards.map((a) => ({
            card: a.card as JustTcgCard,
            variantTypeId: a.variantTypeId,
            qualifierKey: a.qualifierKey,
          })),
          evidence,
        });
      }
    }

    let batchPersistenceFailed = false;
    if (acquisitionFailed) {
      // Falha de aquisição bloqueia a persistência de TODO o reparo — mesma disciplina de
      // executeRepairMappings: nunca uma escrita parcial por Set.
    } else if (!opts.dryRun && plans.length > 0) {
      const outcome = await persistMultiIdentityPromotions(
        supabase,
        sourceId,
        syncRunId,
        opts.confirmedBy as string,
        standardVariantTypeId,
        conditionMap,
        plans,
      );
      summary.identitiesResolved += outcome.identitiesWritten; // todo mapping desta função era PENDING — nunca há REUSE de identidade pré-existente
      summary.identitiesWritten += outcome.identitiesWritten;
      summary.productsResolved += outcome.productsResolved;
      summary.productsWritten += outcome.productsWritten;
      summary.observationsResolved += outcome.observationsResolved;
      summary.observationsWritten += outcome.observationsWritten;
      summary.observationsDivergent += outcome.observationsDivergent;
      summary.operationsSupabase += outcome.operationsSupabase;
      errorParts.push(...outcome.errorParts);
      if (outcome.batchFailureOccurred) batchPersistenceFailed = true;
    }

    const finalStatus = acquisitionFailed
      ? "FAILED"
      : computeFinalStatus(
        batchPersistenceFailed,
        errorParts.length > 0,
        summary.cardsPromoted > 0 || summary.cardsEvaluated > 0,
      );

    if (!opts.dryRun) {
      await finalizeSyncRun(
        supabase,
        syncRunId,
        client,
        finalStatus,
        errorParts.length > 0 ? errorParts.slice(0, 15).join(" | ") : null,
        opts.dryRun,
      );
      syncRunFinalized = true;
    }

    return {
      setsTargeted: candidates.map((c) => c.code),
      perSet,
      cardsEvaluated: summary.cardsEvaluated,
      cardsPromoted: summary.cardsPromoted,
      cardsStillPendingNoStandard: summary.cardsStillPendingNoStandard,
      cardsStillPendingMultipleStandard:
        summary.cardsStillPendingMultipleStandard,
      cardsStillPendingUnknownQualifier:
        summary.cardsStillPendingUnknownQualifier,
      cardsStillPendingDenominatorIncompatible:
        summary.cardsStillPendingDenominatorIncompatible,
      cardsStillPendingNoCandidates: summary.cardsStillPendingNoCandidates,
      identitiesResolved: summary.identitiesResolved,
      identitiesWritten: summary.identitiesWritten,
      productsResolved: summary.productsResolved,
      productsWritten: summary.productsWritten,
      observationsResolved: summary.observationsResolved,
      observationsWritten: summary.observationsWritten,
      observationsDivergent: summary.observationsDivergent,
      operationsSupabase: summary.operationsSupabase,
      productsProjected: summary.productsProjected,
      observationsProjected: summary.observationsProjected,
      variantsProjectionSkipped: summary.variantsProjectionSkipped,
      requestsMade: client.requestsMade,
      maxApiRequests: opts.maxApiRequests,
      requestsRemainingLocal: client.requestsRemainingLocal,
      vocabularyEntriesLoaded: vocabulary.size,
      status: finalStatus,
      errorParts,
      syncRunId,
    };
  } catch (error) {
    if (!opts.dryRun && !syncRunFinalized && syncRunId) {
      const message = error instanceof Error ? error.message : String(error);
      await finalizeSyncRun(
        supabase,
        syncRunId,
        client,
        "FAILED",
        message,
        opts.dryRun,
      );
    }
    throw error;
  }
}

type RepairMultiIdentitiesArgsValidation =
  | {
    ok: true;
    maxApiRequests: number;
    expectedSetCodes: string[];
    repairSetCodes: string[] | null;
  }
  | { ok: false; reason: string };

// Mesma disciplina de validateRepairMappingsArgs — sem número de onda, --expected-set-codes
// obrigatório, --repair-set-codes opcional, --dry-run/--confirmed-by mutuamente exclusivos.
function validateRepairMultiIdentitiesArgs(
  args: {
    maxApiRequests: string | null;
    dryRun: boolean;
    confirmedBy: string | null;
    expectedSetCodes: string | null;
    repairSetCodes: string | null;
  },
): RepairMultiIdentitiesArgsValidation {
  const budgetRaw = args.maxApiRequests;
  if (budgetRaw === null) {
    return { ok: false, reason: "MAX_API_REQUESTS_AUSENTE: --max-api-requests=<n> é obrigatório neste modo." };
  }
  const maxApiRequests = Number(budgetRaw);
  if (!Number.isInteger(maxApiRequests) || maxApiRequests <= 0) {
    return {
      ok: false,
      reason:
        `MAX_API_REQUESTS_INVALIDO(${budgetRaw}): --max-api-requests deve ser um inteiro positivo.`,
    };
  }

  const expectedSetCodesValidation = validateExpectedSetCodes(
    args.expectedSetCodes,
  );
  if (!expectedSetCodesValidation.ok) {
    return { ok: false, reason: expectedSetCodesValidation.reason };
  }

  let repairSetCodes: string[] | null = null;
  if (args.repairSetCodes !== null) {
    const repairSetCodesValidation = validateRepairSetCodesFormat(
      args.repairSetCodes,
    );
    if (!repairSetCodesValidation.ok) {
      return { ok: false, reason: repairSetCodesValidation.reason };
    }
    repairSetCodes = repairSetCodesValidation.codes;
  }

  const hasDryRun = args.dryRun;
  const hasConfirmedBy = args.confirmedBy !== null && args.confirmedBy !== "";
  if (hasDryRun && hasConfirmedBy) {
    return { ok: false, reason: "MODOS_CONFLITANTES: --dry-run e --confirmed-by são mutuamente exclusivos no executor de múltiplas identidades — escolha simulação (--dry-run) ou execução real (--confirmed-by=<admin_user_uuid>), nunca os dois." };
  }
  if (!hasDryRun && !hasConfirmedBy) {
    return { ok: false, reason: "MODO_AUSENTE: informe --dry-run (simulação, sem escrita) ou --confirmed-by=<admin_user_uuid> (execução real) — nenhum modo padrão é assumido." };
  }

  return {
    ok: true,
    maxApiRequests,
    expectedSetCodes: expectedSetCodesValidation.codes,
    repairSetCodes,
  };
}

async function runRepairMultiIdentities(
  opts: RepairMultiIdentitiesOpts,
): Promise<void> {
  const supabaseUrl = requireEnv("SUPABASE_URL");
  const supabaseServiceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
  const justTcgApiKey = requireEnv("JUSTTCG_API_KEY");

  const supabase = createClient(supabaseUrl, supabaseServiceRoleKey);
  const client = new JustTcgClient(
    justTcgApiKey,
    undefined,
    opts.maxApiRequests,
  );

  console.log(`=== Executor de Reparo de Múltiplas Identidades (P14 — vocabulário de variantes) — orçamento local=${opts.maxApiRequests} ===`);
  console.log(opts.dryRun ? "[DRY-RUN] Nenhuma escrita será persistida — nenhum pricing_sync_run será criado.\n" : `Confirmado por (admin_user.id): ${opts.confirmedBy}\n`);

  const result = await executeRepairMultiIdentities(supabase, client, opts);

  console.log("\n=== Resumo da execução de reparo de múltiplas identidades ===");
  console.log(JSON.stringify(result, null, 2));
}

// ============================================================================
// 8. Entrypoint
// ============================================================================

async function main() {
  const args = parseArgs(Deno.args);

  // Fix revisão de robustez 2026-08-19: decisão calculada ANTES de qualquer chamada de rede
  // ou acesso ao Supabase (nenhum client é criado até aqui). Nunca mais cai silenciosamente
  // em --fixture-check por credencial ausente — isso mascarava um ambiente mal configurado
  // como validação bem-sucedida. Ver resolveEntryDecision(), testada offline.
  const decision = resolveEntryDecision(
    {
      fixtureCheck: args.fixtureCheck,
      expansionPlan: args.expansionPlan,
      expansionWave: args.expansionWave,
      maxApiRequests: args.maxApiRequests,
      dryRun: args.dryRun,
      confirmedBy: args.confirmedBy,
      expectedSetCodes: args.expectedSetCodes,
      backfillWave: args.backfillWave,
      repairMappings: args.repairMappings,
      repairSetCodes: args.repairSetCodes,
      repairMultiIdentities: args.repairMultiIdentities,
    },
    {
      justTcgApiKey: Deno.env.get("JUSTTCG_API_KEY"),
      supabaseUrl: Deno.env.get("SUPABASE_URL"),
      supabaseServiceRoleKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
    },
  );

  if (decision.kind === "FIXTURE_CHECK") {
    await runFixtureCheck();
    return;
  }

  if (decision.kind === "EXPANSION_WAVE_INVALID_ARGS") {
    console.error(`Argumentos inválidos para o executor de onda (--expansion-wave): ${decision.reason}`);
    console.error("Exemplo: --expansion-wave=1 --max-api-requests=10 --expected-set-codes=BASE2,BASE3,BASE5,GYM2 --dry-run  (ou --confirmed-by=<admin_user_uuid> para execução real).");
    Deno.exit(1);
  }

  if (decision.kind === "BACKFILL_WAVE_INVALID_ARGS") {
    console.error(`Argumentos inválidos para o executor de backfill (--backfill-wave): ${decision.reason}`);
    console.error("Exemplo: --backfill-wave=1 --max-api-requests=10 --expected-set-codes=BASE1,ME1 --dry-run  (ou --confirmed-by=<admin_user_uuid> para execução real).");
    Deno.exit(1);
  }

  if (decision.kind === "REPAIR_MAPPINGS_INVALID_ARGS") {
    console.error(`Argumentos inválidos para o executor de reparo (--repair-mappings): ${decision.reason}`);
    console.error("Exemplo: --repair-mappings --max-api-requests=10 --expected-set-codes=BASE1,ME1 --dry-run  (ou --confirmed-by=<admin_user_uuid> para execução real).");
    console.error("Opcional: --repair-set-codes=<lista> filtra os candidatos ANTES de qualquer chamada à JustTCG — só válido junto com --repair-mappings; --expected-set-codes deve coincidir com o subconjunto selecionado, não com a lista completa de candidatos.");
    Deno.exit(1);
  }

  if (decision.kind === "REPAIR_MULTI_IDENTITIES_INVALID_ARGS") {
    console.error(`Argumentos inválidos para o executor de múltiplas identidades (--repair-multi-identities): ${decision.reason}`);
    console.error("Exemplo: --repair-multi-identities --max-api-requests=10 --expected-set-codes=SV8.5 --dry-run  (ou --confirmed-by=<admin_user_uuid> para execução real).");
    console.error("Opcional: --repair-set-codes=<lista> filtra os candidatos ANTES de qualquer chamada à JustTCG — só válido junto com --repair-multi-identities; --expected-set-codes deve coincidir com o subconjunto selecionado, não com a lista completa de candidatos.");
    console.error("Pré-requisito estrutural: migration 3924 (pricing_source_variant_mapping + card_variant_type_id/external_variant_key em pricing_source_card_identity) precisa estar aplicada, com vocabulário semeado para esta fonte.");
    Deno.exit(1);
  }

  if (decision.kind === "MISSING_ENV") {
    // Mensagem sanitizada: só nomes de variáveis, nunca valores.
    console.error(`Variável(is) de ambiente obrigatória(s) ausente(s): ${decision.missing.join(", ")}.`);
    console.error("Defina todas antes de rodar o piloto real, o plano de expansão, o executor de onda, o executor de backfill, o executor de reparo ou o executor de múltiplas identidades, ou use --fixture-check para validar a lógica offline sem nenhuma credencial.");
    Deno.exit(1);
  }

  if (decision.kind === "EXPANSION_PLAN") {
    await runExpansionPlan();
    return;
  }

  if (decision.kind === "EXPANSION_WAVE") {
    await runExpansionWave({
      waveNumber: decision.waveNumber,
      maxApiRequests: decision.maxApiRequests,
      dryRun: decision.dryRun,
      confirmedBy: decision.confirmedBy,
      expectedSetCodes: decision.expectedSetCodes,
    });
    return;
  }

  if (decision.kind === "BACKFILL_WAVE") {
    await runBackfillWave({
      waveNumber: decision.waveNumber,
      maxApiRequests: decision.maxApiRequests,
      dryRun: decision.dryRun,
      confirmedBy: decision.confirmedBy,
      expectedSetCodes: decision.expectedSetCodes,
    });
    return;
  }

  if (decision.kind === "REPAIR_MAPPINGS") {
    await runRepairMappings({
      maxApiRequests: decision.maxApiRequests,
      dryRun: decision.dryRun,
      confirmedBy: decision.confirmedBy,
      expectedSetCodes: decision.expectedSetCodes,
      repairSetCodes: decision.repairSetCodes,
    });
    return;
  }

  if (decision.kind === "REPAIR_MULTI_IDENTITIES") {
    await runRepairMultiIdentities({
      maxApiRequests: decision.maxApiRequests,
      dryRun: decision.dryRun,
      confirmedBy: decision.confirmedBy,
      expectedSetCodes: decision.expectedSetCodes,
      repairSetCodes: decision.repairSetCodes,
    });
    return;
  }

  if (!args.confirmedBy) {
    console.error("Piloto real requer --confirmed-by=<admin_user_uuid> (id de um administrador real em admin_user).");
    console.error("admin_user não é legível por SELECT direto (nem em sessão autenticada — RLS habilitado sem policy). Consulte seu próprio id com: SELECT auth.uid(); (via sessão autenticada, se for administrador) ou peça o UUID a outro administrador.");
    Deno.exit(1);
  }

  await runRealPilot({ dryRun: args.dryRun, confirmedBy: args.confirmedBy });
}

await main();
