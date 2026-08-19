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
3. classifyCardMatch() decide SAFE/AMBIGUOUS/ABSENT por carta local: número de coleção
   normalizado é a chave primária; nome só desempata quando o número aponta para mais de
   um candidato, ou invalida um candidato único cujo nome diverge fortemente. Cartas
   externas sem número utilizável (`number` ausente, vazio ou "N/A" — valor real
   documentado pela JustTCG para cartas sem numeração, ex. Energias promocionais) nunca
   entram no índice por número — ficam ABSENT deste lado, nunca casadas só pelo nome
   (nome é secundário, nunca a única evidência, por instrução explícita do pedido).
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

// ============================================================================
// 0. Configuração fixa do piloto
// ============================================================================

const JUSTTCG_API_BASE = "https://api.justtcg.com/v1";
const REQUEST_TIMEOUT_MS = 15_000;
// Teto de segurança local, independente do plano contratado (Starter: 10.000/mês,
// 1.000/dia, 50/min). Elevado de 20 (P8) para 30 nesta rodada: o piloto de um Set
// paginado consome poucas requisições (1 /sets + 1-2 páginas de /cards para o Set-alvo
// definido abaixo), mas o teto precisa acomodar Sets maiores que 100 cartas sem ficar
// artificialmente apertado. Ainda assim, a 3s de intervalo entre chamadas
// (DELAY_BETWEEN_REQUESTS_MS), o ritmo real fica em ~20/min — bem abaixo dos 50/min do
// plano.
const MAX_REQUESTS_PER_RUN = 30;
const DELAY_BETWEEN_REQUESTS_MS = 3_000;
const RATE_LIMIT_BACKOFF_MS = 10_000;

// Máximo de cartas por página de GET /v1/cards no plano Starter/Pro contratado
// (confirmado em https://justtcg.com/docs/api/cards, 2026-08-19 — tabela "Max cards per
// request": Free=20, Starter=100, Pro=100, Enterprise=200). Free cairia para 20; não é
// o caso aqui (premissa comercial confirmada por Fabrício no Incremento P14.1).
const CARDS_PAGE_LIMIT = 100;

const GAME_CODE = "pokemon";

type SetTarget = {
  codigoMmkyu: string;
  releaseDateIso: string; // YYYY-MM-DD, comparado 1:1 contra JustTcgSet.release_date
  overrideExternalSetId?: string; // compat P8 — não usado no piloto real desta rodada
};

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
// 1. Sanitização — mesma disciplina já validada na prova técnica (Protect-SensitiveText)
// ============================================================================

function sanitize(text: string | null | undefined): string | null {
  if (!text) return text ?? null;
  let t = text;
  t = t.replace(/tcg_[A-Za-z0-9]+/g, "[REDACTED_KEY]");
  t = t.replace(/x-api-key\s*:\s*\S+/gi, "x-api-key: [REDACTED]");
  t = t.replace(/authorization\s*:\s*\S+/gi, "authorization: [REDACTED]");
  t = t.replace(/bearer\s+\S+/gi, "Bearer [REDACTED]");
  return t;
}

function sanitizeJson(value: unknown): unknown {
  if (typeof value === "string") return sanitize(value);
  if (Array.isArray(value)) return value.map(sanitizeJson);
  if (value && typeof value === "object") {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) out[k] = sanitizeJson(v);
    return out;
  }
  return value;
}

// ============================================================================
// 2. Normalização — portado da prova técnica (Get-NomeNormalizado/Get-NumeroNormalizado)
// ============================================================================

function normalizeName(text: string): string {
  if (!text) return "";
  const semAcento = text.normalize("NFD").replace(/[̀-ͯ]/g, "");
  return semAcento.toLowerCase().replace(/\s+/g, " ").trim();
}

// Só deve ser chamada com um número já confirmado utilizável — ver isUsableExternalNumber().
// Não tenta adivinhar formato: assume dígitos/letras de coleção reais (ex. "058", "TG01").
function normalizeNumber(numero: string): string {
  if (!numero) return "";
  const numerador = numero.split("/")[0];
  const limpo = numerador.replace(/[^0-9A-Za-z]/g, "");
  const semZeros = limpo.replace(/^0+/, "");
  return (semZeros || "0").toLowerCase();
}

// A JustTCG documenta `number: "N/A"` como valor real para cartas sem numeração própria
// (ex. Energias promocionais — ver https://justtcg.com/docs/schema/card, exemplo). Sem
// esta checagem, normalizeNumber("N/A") interpretaria "/" como separador de denominador
// (["N","A"]) e devolveria "n" — uma chave normalizada plausível, porém falsa, que
// poderia colidir por acidente com uma carta real de número "N". Qualquer número externo
// ausente/vazio/"N/A" (case-insensitive) fica de fora do índice por número — a carta
// correspondente só poderia ser encontrada por nome, e nome é deliberadamente secundário
// nesta rodada (nunca a única evidência) — logo, permanece ABSENT do lado da JustTCG.
function isUsableExternalNumber(raw: string | null | undefined): raw is string {
  if (!raw) return false;
  const trimmed = raw.trim();
  if (!trimmed) return false;
  if (trimmed.toUpperCase() === "N/A") return false;
  return true;
}

// v1 documenta sufixo " - <Idioma>" em `printing` (removido só na v2). Sem sufixo ->
// UNDETERMINED, nunca presumir inglês nem qualquer outro idioma (regra obrigatória do
// pedido — nunca inferir idioma pelo fato de o preço estar em USD). Nota (P14.2): a
// JustTCG passou a expor um campo `variant.language` direto (ex. "English") — não
// adotado nesta rodada por ser mudança de escopo do modelo de idioma (language_status),
// decidido em P1 e fora do pedido de P14.2; registrado aqui só como achado de
// transparência para uma futura revisão de idioma.
function splitPrintingLanguage(printingRaw: string | null | undefined): { printingTipo: string | null; idiomaCodigo: string | null } {
  if (!printingRaw || !printingRaw.trim()) return { printingTipo: null, idiomaCodigo: null };
  const match = printingRaw.match(/^(.+?)\s*-\s*([A-Za-z]+)$/);
  if (match) return { printingTipo: match[1].trim(), idiomaCodigo: match[2].trim().toLowerCase() };
  return { printingTipo: printingRaw.trim(), idiomaCodigo: null };
}

// ============================================================================
// 3. Cliente tipado JustTCG v1 — timeout, 401/429/5xx, orçamento conservador, paginado
// ============================================================================

type CallOutcome = "SUCCESS" | "TECHNICAL_FAILURE" | "BUDGET_STOPPED";

type CallLogEntry = {
  sequence_number: number;
  endpoint: string;
  http_status_code: number | null;
  outcome: CallOutcome;
  error_detail: string | null;
  api_requests_remaining: number | null;
};

type JustTcgMeta = { total?: number; limit?: number; offset?: number; hasMore?: boolean } | null;

type JustTcgResult<T> =
  | { status: "SUCCESS"; data: T; meta: JustTcgMeta; httpStatus: number; apiRequestsRemaining: number | null }
  | { status: "TECHNICAL_FAILURE"; httpStatus: number | null; errorDetail: string }
  | { status: "BUDGET_STOPPED" }
  | { status: "AUTH_FAILURE" };

class JustTcgClient {
  private requestCount = 0;
  readonly callLog: CallLogEntry[] = [];
  rateLimitHits = 0;
  private readonly fetchImpl: typeof fetch;
  // P14.4.2: teto local autoritativo desta execução — nunca o mesmo conceito de
  // MAX_REQUESTS_PER_RUN (teto de segurança fixo do processo, sempre vigente). Quando
  // informado (--max-api-requests=<n> do executor de onda), é o MENOR dos dois que vale —
  // Math.min() nunca permite que um orçamento de onda relaxe o teto de segurança global.
  // budgetOk() nunca inicia uma chamada que ultrapasse este valor (regra 7 do P14.4.2):
  // a checagem acontece ANTES de qualquer fetch, nunca depois.
  private readonly effectiveBudget: number;

  // fetchImpl injetável (default: fetch global) — permite testar paginação/retry/429
  // 100% offline em runFixtureCheck(), sem depender de --allow-net nem de rede real.
  // Mesmo padrão de injeção de dependência já usado em
  // supabase/functions/_shared/pricing-ptax/core.ts (runPtaxSync recebe fetch por parâmetro).
  constructor(private readonly apiKey: string, fetchImpl?: typeof fetch, requestBudget?: number) {
    this.fetchImpl = fetchImpl ?? fetch;
    this.effectiveBudget = typeof requestBudget === "number" ? Math.min(requestBudget, MAX_REQUESTS_PER_RUN) : MAX_REQUESTS_PER_RUN;
  }

  private budgetOk(): boolean {
    return this.requestCount < this.effectiveBudget;
  }

  async get<T>(endpoint: string, params: Record<string, string>): Promise<JustTcgResult<T>> {
    if (!this.budgetOk()) {
      this.callLog.push({
        sequence_number: this.callLog.length + 1,
        endpoint,
        http_status_code: null,
        outcome: "BUDGET_STOPPED",
        error_detail: `Teto local de ${this.effectiveBudget} requisições atingido.`,
        api_requests_remaining: null,
      });
      return { status: "BUDGET_STOPPED" };
    }

    if (this.requestCount > 0) await new Promise((r) => setTimeout(r, DELAY_BETWEEN_REQUESTS_MS));

    const query = new URLSearchParams(params).toString();
    const url = `${JUSTTCG_API_BASE}${endpoint}${query ? `?${query}` : ""}`;

    const attempt = async (): Promise<{ res: Response | null; err: string | null }> => {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
      try {
        const res = await this.fetchImpl(url, {
          method: "GET",
          headers: { "x-api-key": this.apiKey, Accept: "application/json" },
          signal: controller.signal,
        });
        return { res, err: null };
      } catch (error) {
        const message = error instanceof Error ? error.message : "UNEXPECTED_ERROR";
        return { res: null, err: sanitize(message) };
      } finally {
        clearTimeout(timeout);
      }
    };

    this.requestCount++;
    const seq = this.callLog.length + 1;
    let { res, err } = await attempt();

    if (res?.status === 401) {
      const body = sanitize(await res.text().catch(() => ""));
      this.callLog.push({ sequence_number: seq, endpoint, http_status_code: 401, outcome: "TECHNICAL_FAILURE", error_detail: `401 Unauthorized: ${body}`, api_requests_remaining: null });
      return { status: "AUTH_FAILURE" };
    }

    if (res?.status === 429) {
      this.rateLimitHits++;
      await new Promise((r) => setTimeout(r, RATE_LIMIT_BACKOFF_MS));
      if (!this.budgetOk()) {
        this.callLog.push({ sequence_number: seq, endpoint, http_status_code: 429, outcome: "BUDGET_STOPPED", error_detail: "429 seguido de orçamento esgotado antes do retry.", api_requests_remaining: null });
        return { status: "BUDGET_STOPPED" };
      }
      this.requestCount++;
      ({ res, err } = await attempt());
    }

    if (!res) {
      this.callLog.push({ sequence_number: seq, endpoint, http_status_code: null, outcome: "TECHNICAL_FAILURE", error_detail: err ?? "FALHA_DE_CONEXAO", api_requests_remaining: null });
      return { status: "TECHNICAL_FAILURE", httpStatus: null, errorDetail: err ?? "FALHA_DE_CONEXAO" };
    }

    if (!res.ok) {
      const body = sanitize(await res.text().catch(() => "")) ?? "";
      this.callLog.push({ sequence_number: seq, endpoint, http_status_code: res.status, outcome: "TECHNICAL_FAILURE", error_detail: `HTTP ${res.status}: ${body}`, api_requests_remaining: null });
      return { status: "TECHNICAL_FAILURE", httpStatus: res.status, errorDetail: `HTTP ${res.status}: ${body}` };
    }

    const json = await res.json();
    // apiRequestsRemaining é gravado exatamente como recebido, sem transformação — nunca
    // tratado como saldo monotônico ou autoritativo. Achado real do Incremento P14.1
    // (reconciliação de 2026-08-19): a própria metadata da JustTCG pode repetir o mesmo
    // valor por várias chamadas reais e distintas (consistência eventual do lado da API),
    // então nenhum código deste arquivo deve inferir "quanto resta" a partir dela — só
    // registrar o valor bruto em pricing_sync_run_call.api_requests_remaining.
    const apiRequestsRemaining = json?._metadata?.apiRequestsRemaining ?? null;
    const meta: JustTcgMeta = json?.meta ?? null;
    this.callLog.push({ sequence_number: seq, endpoint, http_status_code: res.status, outcome: "SUCCESS", error_detail: null, api_requests_remaining: apiRequestsRemaining });
    return { status: "SUCCESS", data: json as T, meta, httpStatus: res.status, apiRequestsRemaining };
  }

  get requestsMade() {
    return this.requestCount;
  }

  // P14.4.2: saldo local autoritativo restante — usado só para relatório do resumo da onda
  // (regra 12), nunca para decidir se uma chamada pode prosseguir (isso é budgetOk(), acima,
  // interno e já verificado antes de qualquer fetch).
  get requestsRemainingLocal() {
    return Math.max(0, this.effectiveBudget - this.requestCount);
  }
}

// ============================================================================
// 3b. Paginação de /v1/cards por Set — substitui a Fase B por carta de P8
// ============================================================================

type JustTcgVariant = { uuid?: string; id?: string; condition?: string; printing?: string; price?: number; lastUpdated?: number };
type JustTcgCard = { id: string; uuid?: string; name: string; number?: string | null; rarity?: string; variants: JustTcgVariant[] };

// Pagina GET /v1/cards?game=&set=&limit=100&offset=N até meta.hasMore=false (ou, na
// ausência de `meta.hasMore`, até a página vir mais curta que CARDS_PAGE_LIMIT — mesmo
// fallback do próprio exemplo oficial "Price sync for inventory",
// https://justtcg.com/docs/examples). Retorna também `requestsUsed`, para o teste
// "chamadas crescem por lote/página, não por carta" poder comparar diretamente contra o
// total de cartas devolvidas.
async function fetchAllCardsForSet(
  client: JustTcgClient,
  externalSetId: string,
): Promise<{ cards: JustTcgCard[]; requestsUsed: number; aborted: "AUTH_FAILURE" | "TECHNICAL_FAILURE" | "BUDGET_STOPPED" | null }> {
  const cards: JustTcgCard[] = [];
  let offset = 0;
  let requestsUsed = 0;
  for (;;) {
    const result = await client.get<{ data: JustTcgCard[] }>("/cards", {
      game: GAME_CODE,
      set: externalSetId,
      limit: String(CARDS_PAGE_LIMIT),
      offset: String(offset),
    });
    if (result.status === "AUTH_FAILURE") return { cards, requestsUsed, aborted: "AUTH_FAILURE" };
    if (result.status === "BUDGET_STOPPED") return { cards, requestsUsed, aborted: "BUDGET_STOPPED" };
    if (result.status !== "SUCCESS") return { cards, requestsUsed, aborted: "TECHNICAL_FAILURE" };

    requestsUsed++;
    const page = result.data.data ?? [];
    cards.push(...page);

    const hasMore = result.meta?.hasMore ?? page.length === CARDS_PAGE_LIMIT;
    if (!hasMore || page.length === 0) break;
    offset += CARDS_PAGE_LIMIT;
  }
  return { cards, requestsUsed, aborted: null };
}

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

type LocalCard = { card_id: string; name: string; collector_number: string };

// Substitui a busca pontual por carta de P8 (findCard, uma query por card-alvo hardcoded)
// por uma única query trazendo TODAS as cartas locais do Set — necessário para o novo
// desenho, que classifica a cobertura inteira do Set, não uma lista fixa de 3 cartas.
async function findLocalCardsForSet(supabase: SupabaseClient, cardSetId: string): Promise<LocalCard[]> {
  const { data, error } = await supabase.from("card").select("id, name, collector_number").eq("card_set_id", cardSetId);
  if (error) throw new Error(`CARD_QUERY_FAILED: ${error.message}`);
  return (data ?? []).map((r: { id: string; name: string; collector_number: string }) => ({ card_id: r.id, name: r.name, collector_number: r.collector_number }));
}

// ============================================================================
// 5. Resolução de correspondência de Set — release_date exato, nunca nome
// ============================================================================

type JustTcgSet = { id: string; name: string; release_date?: string; release_date_raw?: string; variants_count?: number };

type SetMatchResult =
  | { status: "CONFIRMED"; set: JustTcgSet; method: string; evidence: Record<string, unknown> }
  | { status: "NOT_FOUND"; method: string; evidence: Record<string, unknown> }
  | { status: "AMBIGUOUS"; candidates: JustTcgSet[]; method: string; evidence: Record<string, unknown> };

// Fix P14.2.1 (2026-08-19, mesmo dia, correção pós-piloto real de Fabrício): a JustTCG pode
// retornar `release_date` tanto como data pura (`"2000-02-24"`, formato usado nos testes
// offline originais) quanto como datetime ISO completo (`"2000-02-24T00:00:00.000Z"`, formato
// real observado no piloto de BASE4 — causa raiz confirmada do `SET_NOT_FOUND(BASE4)`, já que
// `resolveSetMatchV2` comparava a string inteira contra `card_set.release_date` local, que o
// Postgres sempre serializa como `YYYY-MM-DD`). Normaliza para `YYYY-MM-DD` extraindo o
// prefixo por regex — nunca via `new Date()`/`toISOString()`, que dependeriam do fuso horário
// do processo e poderiam deslocar o dia civil. Retorna null se o valor estiver ausente ou não
// seguir o formato esperado; um Set sem `release_date` normalizável nunca entra em `allSets`
// com um valor comparável, então nunca é confirmado automaticamente (mesma disciplina de
// "nunca confirmar" já aplicada a números de coleção ausentes/inválidos em
// isUsableExternalNumber()).
function normalizeExternalSetReleaseDate(raw: string | null | undefined): string | null {
  if (typeof raw !== "string") return null;
  const match = raw.match(/^(\d{4}-\d{2}-\d{2})/);
  return match ? match[1] : null;
}

// Fronteira de entrada da JustTCG (fix P14.2.1): ponto único de normalização — todo Set vindo
// da API passa por aqui antes de qualquer resolução de correspondência. `resolveSetMatchV2()`
// e os testes de fixture nunca lidam com o formato bruto da API; o valor bruto é preservado em
// `release_date_raw` para ficar disponível na evidência de matching.
function normalizeJustTcgSets(rawSets: JustTcgSet[]): JustTcgSet[] {
  return rawSets.map((s) => ({
    ...s,
    release_date_raw: s.release_date,
    release_date: normalizeExternalSetReleaseDate(s.release_date) ?? undefined,
  }));
}

function resolveSetMatchV2(target: SetTarget, allSets: JustTcgSet[]): SetMatchResult {
  if (target.overrideExternalSetId) {
    const override = allSets.find((s) => s.id === target.overrideExternalSetId);
    if (override) {
      return { status: "CONFIRMED", set: override, method: "OVERRIDE_MANUAL", evidence: { external_set_id: override.id, external_set_name: override.name } };
    }
    return { status: "NOT_FOUND", method: "OVERRIDE_NAO_CONFIRMADO_NA_RESPOSTA_ATUAL", evidence: { esperado: target.overrideExternalSetId } };
  }

  // Sinal automatizado: release_date exata. Nome nunca é usado para casar Sets — nenhuma
  // tabela local tem um nome em inglês confiável (achado registrado no cabeçalho deste
  // arquivo). Zero candidatos -> NOT_FOUND; mais de um -> AMBIGUOUS (nunca confirmado
  // automaticamente); exatamente um -> CONFIRMED.
  const candidates = allSets.filter((s) => s.release_date === target.releaseDateIso);
  if (candidates.length === 0) {
    return { status: "NOT_FOUND", method: "RELEASE_DATE_EXACT_MATCH", evidence: { release_date_esperada: target.releaseDateIso, candidatos_encontrados: 0 } };
  }
  if (candidates.length > 1) {
    return {
      status: "AMBIGUOUS",
      candidates,
      method: "RELEASE_DATE_EXACT_MATCH",
      evidence: {
        release_date_esperada: target.releaseDateIso,
        candidatos: candidates.map((c) => ({ id: c.id, name: c.name, release_date_raw: c.release_date_raw ?? null })),
      },
    };
  }
  return {
    status: "CONFIRMED",
    set: candidates[0],
    method: "RELEASE_DATE_EXACT_MATCH",
    evidence: {
      release_date_esperada: target.releaseDateIso,
      external_set_id: candidates[0].id,
      external_set_name: candidates[0].name,
      external_set_release_date_raw: candidates[0].release_date_raw ?? null,
    },
  };
}

// ============================================================================
// 5b. Correlação de cartas — número de coleção primário, nome só desempata/verifica
// ============================================================================

// Índice por número normalizado -> candidatos externos com aquele número. Cartas sem
// número utilizável (ver isUsableExternalNumber) nunca entram aqui.
function buildExternalNumberIndex(externalCards: JustTcgCard[]): Map<string, JustTcgCard[]> {
  const index = new Map<string, JustTcgCard[]>();
  for (const card of externalCards) {
    if (!isUsableExternalNumber(card.number)) continue;
    const key = normalizeNumber(card.number as string);
    const bucket = index.get(key) ?? [];
    bucket.push(card);
    index.set(key, bucket);
  }
  return index;
}

// Verificação secundária de nome — nunca a evidência primária. Regra conservadora e
// determinística (sem distância de edição/fuzzy): igualdade normalizada, ou um nome é
// prefixo do outro seguido de espaço (cobre qualificadores como "(...)" / " ex" / " V"
// já observados em P8). Qualquer coisa fora disso é tratada como divergência de nome —
// erra para o lado de marcar ambíguo, nunca para o lado de confirmar sem certeza.
function isNameCompatible(localName: string, externalName: string): boolean {
  const a = normalizeName(localName);
  const b = normalizeName(externalName);
  if (!a || !b) return false;
  if (a === b) return true;
  if (a.startsWith(`${b} `) || b.startsWith(`${a} `)) return true;
  return false;
}

type CardMatchClassification = "SAFE" | "AMBIGUOUS" | "ABSENT";

type CardMatchResult = {
  classification: CardMatchClassification;
  matched: JustTcgCard | null;
  method: string;
  evidence: Record<string, unknown>;
};

// Núcleo da correlação exigida pelo pedido: número de coleção (dentro do Set já
// CONFIRMED) é a identidade principal; nome só entra para (a) desempatar quando o
// número aponta para mais de um candidato, ou (b) invalidar um candidato único cujo
// nome diverge fortemente (evita casar por coincidência de numeração entre cartas
// diferentes). Nunca confirma uma ambiguidade automaticamente.
function classifyCardMatch(local: LocalCard, externalIndex: Map<string, JustTcgCard[]>): CardMatchResult {
  const localNumNorm = normalizeNumber(local.collector_number);
  const candidates = externalIndex.get(localNumNorm) ?? [];

  if (candidates.length === 0) {
    return { classification: "ABSENT", matched: null, method: "NUMERO_SEM_CANDIDATO_EXTERNO", evidence: { numero_normalizado: localNumNorm } };
  }

  if (candidates.length === 1) {
    const candidate = candidates[0];
    if (isNameCompatible(local.name, candidate.name)) {
      return {
        classification: "SAFE",
        matched: candidate,
        method: "NUMERO_UNICO_MAIS_NOME_COMPATIVEL",
        evidence: { numero_normalizado: localNumNorm, nome_local: local.name, nome_externo: candidate.name },
      };
    }
    return {
      classification: "AMBIGUOUS",
      matched: null,
      method: "NUMERO_UNICO_MAS_NOME_DIVERGENTE",
      evidence: {
        numero_normalizado: localNumNorm,
        nome_local: local.name,
        nome_externo: candidate.name,
        // Fix P14.2.2: número bruto do candidato incluído para a evidência sanitizada de
        // dry-run (logDryRunCardEvidence) poder mostrar id/nome/número sem consulta extra.
        candidatos: [{ id: candidate.id, name: candidate.name, number: candidate.number ?? null }],
      },
    };
  }

  // Mais de um candidato compartilha o mesmo número (ex. variantes alt-art) — nome tenta
  // desempatar; se não sobrar exatamente um, permanece ambíguo.
  const nameFiltered = candidates.filter((c) => isNameCompatible(local.name, c.name));
  if (nameFiltered.length === 1) {
    return {
      classification: "SAFE",
      matched: nameFiltered[0],
      method: "NUMERO_MULTIPLO_DESEMPATADO_POR_NOME",
      evidence: { numero_normalizado: localNumNorm, nome_local: local.name, nome_externo: nameFiltered[0].name, total_candidatos_por_numero: candidates.length },
    };
  }
  return {
    classification: "AMBIGUOUS",
    matched: null,
    method: "NUMERO_MULTIPLO_SEM_DESEMPATE_SEGURO",
    evidence: {
      numero_normalizado: localNumNorm,
      nome_local: local.name,
      candidatos: candidates.map((c) => ({ id: c.id, name: c.name, number: c.number ?? null })),
      candidatos_compativeis_por_nome: nameFiltered.length,
    },
  };
}

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
// 5d. Upsert idempotente de mapeamentos — corrige a lacuna de P8 (insert-e-tolera nunca
//     promovia PENDING/NOT_FOUND para CONFIRMED numa reexecução)
// ============================================================================

type MappingRowLike = { id: string; match_status: string };
type UpsertAction = "INSERTED" | "UPGRADED_TO_CONFIRMED" | "NOOP_ALREADY_CONFIRMED" | "NOOP_KEEP_CONFIRMED_DIVERGENT_INPUT" | "NOOP_SAME_STATUS";

// Pura por design (recebe a linha existente, se houver, e a nova classificação; devolve
// só a decisão) — testável em runFixtureCheck() sem tocar o Supabase. Uma linha CONFIRMED
// nunca é rebaixada por uma nova classificação pior (ABSENT/AMBIGUOUS): fica preservada,
// só sinalizada como divergência para revisão humana, nunca reescrita silenciosamente.
function decideMappingUpsert(existing: MappingRowLike | null, newStatus: "CONFIRMED" | "PENDING" | "NOT_FOUND"): UpsertAction {
  if (!existing) return "INSERTED";
  if (existing.match_status === "CONFIRMED") {
    return newStatus === "CONFIRMED" ? "NOOP_SAME_STATUS" : "NOOP_KEEP_CONFIRMED_DIVERGENT_INPUT";
  }
  if (newStatus === "CONFIRMED") return "UPGRADED_TO_CONFIRMED";
  return existing.match_status === newStatus ? "NOOP_SAME_STATUS" : "UPGRADED_TO_CONFIRMED"; // PENDING<->NOT_FOUND também é atualizado, sem novo status no schema
}

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
        errorParts.push(`CARD_MAPPING_BATCH_SELECT_FAILED: ${sanitize(error.message)}`);
        continue;
      }
      for (const row of (data ?? []) as Array<{ id: string; card_id: string; match_status: string }>) {
        existingByCardId.set(row.card_id, { id: row.id, match_status: row.match_status });
      }
    }

    const toInsert: Array<Record<string, unknown>> = [];
    const toUpdate: Array<Record<string, unknown>> = [];
    const nowIso = new Date().toISOString();

    for (const planned of plannedMappings) {
      const existing = existingByCardId.get(planned.cardId) ?? null;
      const action = decideMappingUpsert(existing, planned.status);
      if (action === "NOOP_SAME_STATUS" || action === "NOOP_KEEP_CONFIRMED_DIVERGENT_INPUT" || action === "NOOP_ALREADY_CONFIRMED") {
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

      if (action === "INSERTED") {
        toInsert.push({ card_id: planned.cardId, pricing_source_id: sourceId, ...payload });
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
        // atual não tem estado intermediário entre PENDING e NOT_FOUND fora desta função);
        // registrado como pendência informativa, não corrigido nesta rodada.
        errorParts.push(
          `CARD_MAPPING_PENDING_NOT_FOUND_TOGGLE_SKIPPED(card=${planned.cardId}): ${(existing as MappingRowLike).match_status} -> ${planned.status} fora do escopo da RPC de promoção exclusiva (Query 3914); sem escrita nesta rodada, recuperável numa reexecução futura.`,
        );
      }
    }

    for (const rows of chunk(toInsert, BATCH_SIZE)) {
      operationsSupabase++;
      const { data, error } = await supabase.from("pricing_card_mapping").insert(rows).select("id, card_id");
      if (error) {
        batchFailureOccurred = true;
        errorParts.push(`CARD_MAPPING_BATCH_INSERT_FAILED(${rows.length} linhas): ${sanitize(error.message)}`);
        continue;
      }
      for (const row of (data ?? []) as Array<{ id: string; card_id: string }>) {
        cardMappingIdByCardId.set(row.card_id, row.id);
      }
    }

    for (const rows of chunk(toUpdate, BATCH_SIZE)) {
      operationsSupabase++;
      const { data, error } = await supabase.rpc("batch_update_pricing_card_mapping_status", { p_updates: rows });
      if (error) {
        batchFailureOccurred = true;
        errorParts.push(`CARD_MAPPING_BATCH_UPDATE_FAILED(${rows.length} linhas): ${sanitize(error.message)}`);
        continue;
      }
      for (const row of (data ?? []) as Array<{ id: string; card_id: string }>) {
        cardMappingIdByCardId.set(row.card_id, row.id);
      }
    }
  }

  // --- Fase 2: pricing_product --------------------------------------------------
  // Só existem variantes planejadas para cartas CONFIRMED cujo mapping foi resolvido acima
  // (inserido, promovido ou já existente) — cartas cujo mapping falhou nesta rodada (Fase 1)
  // ficam de fora e são reportadas, recuperáveis numa reexecução (o mapping delas volta a
  // ser reavaliado do zero na próxima chamada desta função).
  const productIdByKey = new Map<string, string>();
  const usableVariants: Array<PlannedVariant & { cardMappingId: string }> = [];
  const unresolvedCardIds = new Set<string>();
  let productsWritten = 0;

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

  if (usableVariants.length > 0) {
    const cardMappingIds = [...new Set(usableVariants.map((v) => v.cardMappingId))];
    for (const ids of chunk(cardMappingIds, BATCH_SIZE)) {
      operationsSupabase++;
      const { data, error } = await supabase
        .from("pricing_product")
        .select("id, pricing_card_mapping_id, external_product_id")
        .in("pricing_card_mapping_id", ids);
      if (error) {
        batchFailureOccurred = true;
        errorParts.push(`PRODUCT_BATCH_SELECT_FAILED: ${sanitize(error.message)}`);
        continue;
      }
      for (const row of (data ?? []) as Array<{ id: string; pricing_card_mapping_id: string; external_product_id: string }>) {
        productIdByKey.set(`${row.pricing_card_mapping_id}::${row.external_product_id}`, row.id);
      }
    }

    const toInsertProducts: Array<{ key: string; row: Record<string, unknown> }> = [];
    const seenThisBatch = new Set<string>();
    for (const variant of usableVariants) {
      const key = `${variant.cardMappingId}::${variant.externalProductId}`;
      if (productIdByKey.has(key) || seenThisBatch.has(key)) continue; // REUSE — já existe (banco ou mesmo lote), zero escrita
      seenThisBatch.add(key);
      toInsertProducts.push({
        key,
        row: {
          pricing_card_mapping_id: variant.cardMappingId,
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
        errorParts.push(`PRODUCT_BATCH_INSERT_FAILED(${pairs.length} linhas): ${sanitize(error.message)}`);
        continue;
      }
      for (const row of (data ?? []) as Array<{ id: string; pricing_card_mapping_id: string; external_product_id: string }>) {
        productIdByKey.set(`${row.pricing_card_mapping_id}::${row.external_product_id}`, row.id);
        productsWritten++;
      }
    }
  }

  // productsResolved conta toda variante cujo produto ficou resolvido nesta rodada, seja por
  // já existir (pré-busca, REUSE) ou por ter sido inserido com sucesso agora (NEW) — nunca
  // conta variantes cujo INSERT falhou (essas simplesmente não aparecem em productIdByKey e
  // são retomadas na próxima reexecução). productsWritten conta só as NEW bem-sucedidas.
  let productsResolved = 0;
  for (const variant of usableVariants) {
    const key = `${variant.cardMappingId}::${variant.externalProductId}`;
    if (productIdByKey.has(key)) productsResolved++;
  }

  // --- Fase 3: pricing_observation -----------------------------------------------
  let observationsResolved = 0;
  let observationsWritten = 0;
  let observationsDivergent = 0;

  const variantsWithProduct = usableVariants
    .map((v) => ({ ...v, productId: productIdByKey.get(`${v.cardMappingId}::${v.externalProductId}`) ?? null }))
    .filter((v): v is PlannedVariant & { cardMappingId: string; productId: string } => v.productId !== null);

  const unresolvedProductKeys = usableVariants.length - variantsWithProduct.length;
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
    const result = classifyCardMatch({ card_id: "local-1", name: "Abra", collector_number: "058" }, externalIndex);
    assert("correspondência segura: número+nome batem -> SAFE", result.classification === "SAFE" && result.matched?.id === "ext-1");
  }

  // --- P14.2 cenário 4: número de coleção ausente ------------------------------------
  assert('isUsableExternalNumber: "N/A" não é utilizável', isUsableExternalNumber("N/A") === false);
  assert("isUsableExternalNumber: string vazia não é utilizável", isUsableExternalNumber("") === false);
  assert("isUsableExternalNumber: null/undefined não são utilizáveis", isUsableExternalNumber(null) === false && isUsableExternalNumber(undefined) === false);
  assert("isUsableExternalNumber: número real é utilizável", isUsableExternalNumber("058") === true);
  {
    const externalIndex = buildExternalNumberIndex([{ id: "ext-energy", name: "Fire Energy", number: "N/A", variants: [] }]);
    assert("número ausente: carta externa 'N/A' nunca entra no índice por número", externalIndex.size === 0);
    const result = classifyCardMatch({ card_id: "local-x", name: "Fire Energy", collector_number: "999" }, externalIndex);
    assert("número ausente: local sem candidato por número -> ABSENT (nunca casado só por nome)", result.classification === "ABSENT");
  }

  // --- P14.2 cenário 5: correspondência ambígua --------------------------------------
  {
    const externalIndex = buildExternalNumberIndex([
      { id: "ext-alt-1", name: "Pikachu", number: "25", variants: [] },
      { id: "ext-alt-2", name: "Pikachu", number: "25", variants: [] },
    ]);
    const result = classifyCardMatch({ card_id: "local-pika", name: "Pikachu", collector_number: "025" }, externalIndex);
    assert("ambíguo: dois candidatos com mesmo número e nome, sem desempate seguro -> AMBIGUOUS (nunca auto-confirmado)", result.classification === "AMBIGUOUS" && result.matched === null);
  }
  {
    const externalIndex = buildExternalNumberIndex([{ id: "ext-alakazam", name: "Alakazam", number: "1", variants: [] }]);
    const result = classifyCardMatch({ card_id: "local-abra", name: "Abra", collector_number: "001" }, externalIndex);
    assert("ambíguo: número único mas nome diverge fortemente -> AMBIGUOUS, não SAFE", result.classification === "AMBIGUOUS" && result.matched === null);
  }
  {
    // Desempate correto: dois candidatos por número, só um com nome compatível -> SAFE.
    const externalIndex = buildExternalNumberIndex([
      { id: "ext-charizard", name: "Charizard", number: "4", variants: [] },
      { id: "ext-charmander", name: "Charmander", number: "4", variants: [] },
    ]);
    const result = classifyCardMatch({ card_id: "local-charizard", name: "Charizard", collector_number: "004" }, externalIndex);
    assert("desempate por nome funciona quando exatamente um candidato bate", result.classification === "SAFE" && result.matched?.id === "ext-charizard");
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
    const results = localCards.map((c) => classifyCardMatch(c, externalIndex));
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
    const matchResult = classifyCardMatch(local, externalIndex);
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
    const matchResult = classifyCardMatch(local, externalIndex);
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
      "logDryRunCardEvidence (ABSENT): imprime carta local e motivo, candidatos_externos vazio",
      printed.includes("Mewtwo") && printed.includes("150") && printed.includes("NUMERO_SEM_CANDIDATO_EXTERNO") && printed.includes("[]"),
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
      const seed = {
        pricing_card_mapping: [{ id: cardMappingId, card_id: "conflict-1", pricing_source_id: "source-1", match_status: "CONFIRMED" }],
        pricing_product: [{ id: productId, pricing_card_mapping_id: cardMappingId, external_product_id: "ext-conflict-1" }],
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
      const seed = {
        pricing_card_mapping: [{ id: cardMappingId, card_id: "divergent-1", pricing_source_id: "source-1", match_status: "CONFIRMED" }],
        pricing_product: [{ id: productId, pricing_card_mapping_id: cardMappingId, external_product_id: "ext-divergent-1" }],
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
      const seed = {
        pricing_card_mapping: [{ id: cardMappingId, card_id: "spd-1", pricing_source_id: "source-1", match_status: "CONFIRMED" }],
        pricing_product: [{ id: productId, pricing_card_mapping_id: cardMappingId, external_product_id: "ext-spd-1" }],
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
      const seed = {
        pricing_card_mapping: [{ id: cardMappingId, card_id: "dpd-1", pricing_source_id: "source-1", match_status: "CONFIRMED" }],
        pricing_product: [{ id: productId, pricing_card_mapping_id: cardMappingId, external_product_id: "ext-dpd-1" }],
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
      const seed = {
        pricing_card_mapping: [{ id: cardMappingId, card_id: "stc-1", pricing_source_id: "source-1", match_status: "CONFIRMED" }],
        pricing_product: [{ id: productId, pricing_card_mapping_id: cardMappingId, external_product_id: "ext-stc-1" }],
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
        pricing_product: [{ id: "prod-A", pricing_card_mapping_id: "map-A", external_product_id: "ext-A" }],
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

    // classifySetForExpansionPlan() — cinco cenários obrigatórios.
    {
      const externalSets: JustTcgSet[] = normalizeJustTcgSets([
        { id: "ext-b", name: "Ext B", release_date: "2020-02-01", variants_count: 500 },
        { id: "ext-c1", name: "Ext C1", release_date: "2020-03-01" },
        { id: "ext-c2", name: "Ext C2", release_date: "2020-03-01" },
        { id: "ext-f", name: "Nome Completamente Diferente", release_date: "2020-05-01" },
      ]);

      const jaConfirmado = classifySetForExpansionPlan(
        { releaseDateIso: "2020-01-01" },
        { cardSetId: "cs-a", matchStatus: "CONFIRMED", externalSetId: "ext-a", externalSetName: "Ext A" },
        externalSets,
      );
      assert(
        "P14.4.1: Set já CONFIRMED -> ALREADY_CONFIRMED, preservado, nunca reavaliado contra a lista externa",
        jaConfirmado.status === "ALREADY_CONFIRMED" && jaConfirmado.externalSetId === "ext-a" && jaConfirmado.externalSetName === "Ext A",
      );

      const candidatoUnico = classifySetForExpansionPlan({ releaseDateIso: "2020-02-01" }, null, externalSets);
      assert(
        "P14.4.1: candidato único por release_date -> SAFE_CANDIDATE, com o id/nome/variants_count corretos",
        candidatoUnico.status === "SAFE_CANDIDATE" && candidatoUnico.externalSetId === "ext-b" && candidatoUnico.externalVariantsCount === 500,
      );

      const doisCandidatos = classifySetForExpansionPlan({ releaseDateIso: "2020-03-01" }, null, externalSets);
      assert("P14.4.1: dois candidatos na mesma release_date -> AMBIGUOUS, nunca confirmado automaticamente", doisCandidatos.status === "AMBIGUOUS" && doisCandidatos.candidateCount === 2);

      const nenhumCandidato = classifySetForExpansionPlan({ releaseDateIso: "2020-04-01" }, null, externalSets);
      assert("P14.4.1: nenhum candidato na release_date -> NOT_FOUND", nenhumCandidato.status === "NOT_FOUND" && nenhumCandidato.reason === "RELEASE_DATE_SEM_CORRESPONDENCIA_EXTERNA");

      const semReleaseDate = classifySetForExpansionPlan({ releaseDateIso: null }, null, externalSets);
      assert("P14.4.1: Set local sem release_date -> NOT_FOUND, nunca tenta casar por nome", semReleaseDate.status === "NOT_FOUND" && semReleaseDate.reason === "SET_LOCAL_SEM_RELEASE_DATE");

      const nomeDivergente = classifySetForExpansionPlan({ releaseDateIso: "2020-05-01" }, null, externalSets);
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
        "P14.4.1: SETA (mapping já CONFIRMED) -> ALREADY_CONFIRMED; SETB (candidato único por data) -> SAFE_CANDIDATE",
        plan?.entries.find((e) => e.code === "SETA")?.status === "ALREADY_CONFIRMED" && plan?.entries.find((e) => e.code === "SETB")?.status === "SAFE_CANDIDATE",
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

  // Cenário 13 — ambiguidades preservadas: número único mas nome externo divergente -> PENDING
  // (nunca CONFIRMED, nunca NOT_FOUND).
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
    const mappingX3 = (tables13.pricing_card_mapping ?? []).find((r) => r.card_id === "card-x3") as { match_status: string } | undefined;
    assert(
      "P14.4.2 cenário 13: número único com nome externo divergente (card-x3) fica PENDING (ambíguo) — nunca CONFIRMED, nunca NOT_FOUND — enquanto card-x1/x2/y1 são confirmados normalmente",
      resultado13.cardsAmbiguous === 1 && mappingX3 !== undefined && mappingX3.match_status === "PENDING",
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
  };
  for (const arg of argv) {
    if (arg === "--dry-run") args.dryRun = true;
    else if (arg === "--fixture-check") args.fixtureCheck = true;
    else if (arg === "--expansion-plan") args.expansionPlan = true;
    else if (arg.startsWith("--confirmed-by=")) args.confirmedBy = arg.slice("--confirmed-by=".length);
    else if (arg.startsWith("--expansion-wave=")) args.expansionWave = arg.slice("--expansion-wave=".length);
    else if (arg.startsWith("--max-api-requests=")) args.maxApiRequests = arg.slice("--max-api-requests=".length);
    else if (arg.startsWith("--expected-set-codes=")) args.expectedSetCodes = arg.slice("--expected-set-codes=".length);
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
function resolveEntryDecision(
  args: {
    fixtureCheck: boolean;
    expansionPlan?: boolean;
    expansionWave?: string | null;
    maxApiRequests?: string | null;
    dryRun?: boolean;
    confirmedBy?: string | null;
    expectedSetCodes?: string | null;
  },
  env: { justTcgApiKey: string | undefined; supabaseUrl: string | undefined; supabaseServiceRoleKey: string | undefined },
): EntryDecision {
  // --fixture-check é sempre honrado explicitamente e tem prioridade sobre qualquer estado
  // de credencial — mesmo com as três variáveis presentes, roda offline se pedido. Nunca
  // depende do ambiente: por isso funciona sem nenhuma credencial definida.
  if (args.fixtureCheck) return { kind: "FIXTURE_CHECK" };

  const waveArgs = {
    expansionWave: args.expansionWave ?? null,
    maxApiRequests: args.maxApiRequests ?? null,
    dryRun: args.dryRun ?? false,
    confirmedBy: args.confirmedBy ?? null,
    expectedSetCodes: args.expectedSetCodes ?? null,
  };
  const waveValidation = waveArgs.expansionWave !== null ? validateExpansionWaveArgs(waveArgs) : null;
  if (waveValidation && !waveValidation.ok) return { kind: "EXPANSION_WAVE_INVALID_ARGS", reason: waveValidation.reason };

  const missing: string[] = [];
  if (!env.justTcgApiKey) missing.push("JUSTTCG_API_KEY");
  if (!env.supabaseUrl) missing.push("SUPABASE_URL");
  if (!env.supabaseServiceRoleKey) missing.push("SUPABASE_SERVICE_ROLE_KEY");
  if (missing.length > 0) return { kind: "MISSING_ENV", missing };

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
        const matchResult = classifyCardMatch(local, externalIndex);

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

type ExistingSetMappingLite = { cardSetId: string; matchStatus: string; externalSetId: string | null; externalSetName: string | null };

type SetPlanClassification =
  | { status: "ALREADY_CONFIRMED"; externalSetId: string; externalSetName: string | null; externalVariantsCount: number | null; reason: string }
  | { status: "SAFE_CANDIDATE"; externalSetId: string; externalSetName: string; externalVariantsCount: number | null; reason: string }
  | { status: "AMBIGUOUS"; candidateCount: number; reason: string }
  | { status: "NOT_FOUND"; reason: string };

// Pura — mesmo sinal primário automatizado já validado em resolveSetMatchV2() (P14.2):
// release_date normalizada é a ÚNICA evidência usada para confirmar automaticamente. Nome
// nunca é fundamento isolado (não é usado nem como desempate nesta rodada — zero candidatos
// na mesma data já é o caso raro o suficiente para não precisar de um segundo sinal; ver nota
// no cabeçalho do arquivo). Um mapping já CONFIRMED é sempre preservado, nunca reavaliado
// contra allExternalSets — ALREADY_CONFIRMED é decidido só pelo estado local, antes de
// qualquer comparação de data.
function classifySetForExpansionPlan(
  local: { releaseDateIso: string | null },
  existingMapping: ExistingSetMappingLite | null,
  allExternalSets: JustTcgSet[],
): SetPlanClassification {
  if (existingMapping && existingMapping.matchStatus === "CONFIRMED") {
    const knownExternal = existingMapping.externalSetId ? allExternalSets.find((s) => s.id === existingMapping.externalSetId) : undefined;
    return {
      status: "ALREADY_CONFIRMED",
      externalSetId: existingMapping.externalSetId ?? "",
      externalSetName: existingMapping.externalSetName,
      externalVariantsCount: knownExternal?.variants_count ?? null,
      reason: "MAPPING_JA_CONFIRMED_PRESERVADO",
    };
  }

  if (!local.releaseDateIso) {
    return { status: "NOT_FOUND", reason: "SET_LOCAL_SEM_RELEASE_DATE" };
  }

  const candidates = allExternalSets.filter((s) => s.release_date === local.releaseDateIso);
  if (candidates.length === 0) {
    return { status: "NOT_FOUND", reason: "RELEASE_DATE_SEM_CORRESPONDENCIA_EXTERNA" };
  }
  if (candidates.length > 1) {
    return { status: "AMBIGUOUS", candidateCount: candidates.length, reason: "RELEASE_DATE_COM_MULTIPLOS_CANDIDATOS" };
  }
  return {
    status: "SAFE_CANDIDATE",
    externalSetId: candidates[0].id,
    externalSetName: candidates[0].name,
    externalVariantsCount: candidates[0].variants_count ?? null,
    reason: "RELEASE_DATE_EXACT_MATCH_UNICO",
  };
}

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
  reason: string;
};

type ExpansionPlanInput = {
  localSets: LocalSetSummary[];
  existingSetMappings: Map<string, ExistingSetMappingLite>;
  allExternalSets: JustTcgSet[];
  existingCoverage: Map<string, { products: number; observations: number }>;
};

type ExpansionPlanResult = {
  generatedAt: string;
  totalLocalSets: number;
  totalLocalCards: number;
  entries: SetPlanEntry[];
  waves: ExpansionWave[];
  totalEstimatedCallsAllWaves: number;
};

const PAGES_ESTIMATE_EXTERNAL_REASON = "JUSTTCG_SETS_NAO_EXPOE_TOTAL_DE_CARTAS_SO_VARIANTS_COUNT";

// Pura — orquestra classifySetForExpansionPlan()/buildExpansionWaves() sobre dados já
// buscados pelo chamador (executeExpansionPlan(), abaixo). 100% testável offline sem nenhum
// SupabaseClient/fetch.
function buildExpansionPlan(input: ExpansionPlanInput): ExpansionPlanResult {
  const entries: SetPlanEntry[] = input.localSets.map((local) => {
    const existingMapping = input.existingSetMappings.get(local.cardSetId) ?? null;
    const classification = classifySetForExpansionPlan({ releaseDateIso: local.releaseDateIso }, existingMapping, input.allExternalSets);
    const coverage = input.existingCoverage.get(local.cardSetId) ?? { products: 0, observations: 0 };
    const hasExternal = classification.status === "ALREADY_CONFIRMED" || classification.status === "SAFE_CANDIDATE";

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
      existingProductsCount: coverage.products,
      existingObservationsCount: coverage.observations,
      reason: classification.reason,
    };
  });

  const safeCandidates = entries.filter((e) => e.status === "SAFE_CANDIDATE").map((e) => ({ code: e.code, localCardCount: e.localCardCount }));
  const waves = buildExpansionWaves(safeCandidates);
  // +1 chamada de /sets por execução de onda (aproximação explícita — uma futura execução real
  // de onda ainda precisaria revalidar a resolução de Set antes de paginar /cards; nunca
  // escondida, sempre somada ao total).
  const totalEstimatedCallsAllWaves = waves.reduce((sum, w) => sum + w.estimatedCallsCards, 0) + waves.length;

  return {
    generatedAt: new Date().toISOString(),
    totalLocalSets: input.localSets.length,
    totalLocalCards: input.localSets.reduce((sum, s) => sum + s.localCardCount, 0),
    entries,
    waves,
    totalEstimatedCallsAllWaves,
  };
}

// --- I/O só-leitura ---------------------------------------------------------------------

type CardSetRow = { id: string; code: string; release_date: string | null };
type MetricsRow = { card_set_id: string; cards_ativas: number };
type SetMappingRow = { card_set_id: string; match_status: string; external_set_id: string | null; external_set_name: string | null };
type CoverageRow = { card_set_id: string; products_count: number; observations_count: number };

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

function buildCoverageMap(rows: CoverageRow[]): Map<string, { products: number; observations: number }> {
  const map = new Map<string, { products: number; observations: number }>();
  for (const row of rows) map.set(row.card_set_id, { products: row.products_count, observations: row.observations_count });
  return map;
}

// Reconciliação final: todo mapping CONFIRMED existente precisa aparecer como
// ALREADY_CONFIRMED no plano — se um Set com mapping CONFIRMED sumiu do inventário paginado
// (bug de paginação, filtro errado, etc.), o plano nunca é emitido, nunca parcialmente.
function assertConfirmedMappingsPreserved(entries: SetPlanEntry[], localSets: LocalSetSummary[], existingSetMappings: Map<string, ExistingSetMappingLite>): void {
  for (const [cardSetId, mapping] of existingSetMappings) {
    if (mapping.matchStatus !== "CONFIRMED") continue;
    const local = localSets.find((s) => s.cardSetId === cardSetId);
    if (!local) {
      throw new Error(`MAPPING_CONFIRMED_SEM_SET_LOCAL_CORRESPONDENTE(${cardSetId}): plano de expansão abortado, nunca emitido parcialmente.`);
    }
    const entry = entries.find((e) => e.code === local.code);
    if (!entry || entry.status !== "ALREADY_CONFIRMED") {
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
  existingCoverage: Map<string, { products: number; observations: number }>;
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

  // Cobertura via pricing_set_coverage (Query 3916): agregada server-side por card_set_id x
  // pricing_source_id, nunca cresce com o volume de produtos/observações (no máximo 1 linha
  // por combinação Set x Fonte). Substitui as três leituras encadeadas em memória do desenho
  // original (pricing_card_mapping -> pricing_product -> pricing_observation).
  const coverageRows = await fetchAllRowsFromTable<CoverageRow>(
    supabase,
    "pricing_set_coverage",
    "card_set_id, products_count, observations_count",
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
        const matchResult = classifyCardMatch(localCard, externalIndex);

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

  if (decision.kind === "MISSING_ENV") {
    // Mensagem sanitizada: só nomes de variáveis, nunca valores.
    console.error(`Variável(is) de ambiente obrigatória(s) ausente(s): ${decision.missing.join(", ")}.`);
    console.error("Defina todas antes de rodar o piloto real, o plano de expansão ou o executor de onda, ou use --fixture-check para validar a lógica offline sem nenhuma credencial.");
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

  if (!args.confirmedBy) {
    console.error("Piloto real requer --confirmed-by=<admin_user_uuid> (id de um administrador real em admin_user).");
    console.error("admin_user não é legível por SELECT direto (nem em sessão autenticada — RLS habilitado sem policy). Consulte seu próprio id com: SELECT auth.uid(); (via sessão autenticada, se for administrador) ou peça o UUID a outro administrador.");
    Deno.exit(1);
  }

  await runRealPilot({ dryRun: args.dryRun, confirmedBy: args.confirmedBy });
}

await main();
