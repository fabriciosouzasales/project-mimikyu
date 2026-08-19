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

Credencial: somente `JUSTTCG_API_KEY` (variável de ambiente, nunca argumento de linha de
comando, nunca logada). Se ausente, o script roda em modo --fixture-check: valida toda a
lógica de parsing/normalização/paginação/idempotência contra dados sintéticos embutidos,
100% offline (nenhuma chamada de rede, nenhuma escrita no Supabase) — e imprime um aviso
explícito de que nenhum piloto real foi executado. Nunca solicita a chave interativamente
nem aceita literal em texto.

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

Uso:

  # PowerShell — defina as variáveis de ambiente ANTES de rodar. NUNCA cole a Service
  # Role Key nem a JUSTTCG_API_KEY em chat/log.
  $env:SUPABASE_URL = "https://qjfutqujxrbzgrtkpgkg.supabase.co"
  $env:SUPABASE_SERVICE_ROLE_KEY = "<service_role_key>"
  $env:JUSTTCG_API_KEY = "<justtcg_api_key>"   # opcional — ausente força --fixture-check

  # Validação offline (sempre segura, não requer nenhuma variável de rede/segredo):
  deno run --allow-env scripts/sync-justtcg-pricing.ts --fixture-check

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

  // fetchImpl injetável (default: fetch global) — permite testar paginação/retry/429
  // 100% offline em runFixtureCheck(), sem depender de --allow-net nem de rede real.
  // Mesmo padrão de injeção de dependência já usado em
  // supabase/functions/_shared/pricing-ptax/core.ts (runPtaxSync recebe fetch por parâmetro).
  constructor(private readonly apiKey: string, fetchImpl?: typeof fetch) {
    this.fetchImpl = fetchImpl ?? fetch;
  }

  private budgetOk(): boolean {
    return this.requestCount < MAX_REQUESTS_PER_RUN;
  }

  async get<T>(endpoint: string, params: Record<string, string>): Promise<JustTcgResult<T>> {
    if (!this.budgetOk()) {
      this.callLog.push({
        sequence_number: this.callLog.length + 1,
        endpoint,
        http_status_code: null,
        outcome: "BUDGET_STOPPED",
        error_detail: `Teto local de ${MAX_REQUESTS_PER_RUN} requisições atingido.`,
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

function classifyInsertResult(error: { message: string } | null): InsertOutcome {
  if (!error) return "NEW";
  return `${error.message}`.includes("duplicate key") ? "CONFLICT_IGNORED" : "OTHER_ERROR";
}

function accumulateWriteOutcome(counts: { resolved: number; written: number }, outcome: Exclude<InsertOutcome, "OTHER_ERROR">): void {
  counts.resolved++;
  if (outcome === "NEW") counts.written++;
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

  const failed = assertions.filter(([, ok]) => !ok);
  for (const [label, ok] of assertions) console.log(`  [${ok ? "OK" : "FALHOU"}] ${label}`);
  console.log(`\n${failed.length === 0 ? "TODAS as asserções passaram" : `${failed.length} asserção(ões) FALHARAM`} (${assertions.length} no total).`);
  console.log("\nNenhuma chamada de rede foi feita. Nenhuma linha foi gravada no Supabase.");
  console.log("Piloto real NÃO executado nesta rodada — JUSTTCG_API_KEY ausente ou --fixture-check pedido explicitamente.");

  if (failed.length > 0) Deno.exit(1);
}

// ============================================================================
// 7. Piloto real
// ============================================================================

function parseArgs(argv: string[]) {
  const args = { dryRun: false, fixtureCheck: false, confirmedBy: null as string | null };
  for (const arg of argv) {
    if (arg === "--dry-run") args.dryRun = true;
    else if (arg === "--fixture-check") args.fixtureCheck = true;
    else if (arg.startsWith("--confirmed-by=")) args.confirmedBy = arg.slice("--confirmed-by=".length);
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
  };
  const errorParts: string[] = [];
  let syncRunFinalized = false;

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
          await upsertSetMapping(supabase, cardSetId, source.id as string, match.status === "NOT_FOUND" ? "NOT_FOUND" : "PENDING", null, match.method, match.evidence, args.confirmedBy);
        }
        continue; // Set não confirmado: nenhuma cobertura de cartas é tentada para ele.
      }

      summary.setsConfirmed++;
      if (!args.dryRun) {
        await upsertSetMapping(supabase, cardSetId, source.id as string, "CONFIRMED", match.set, match.method, match.evidence, args.confirmedBy);
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
          if (!args.dryRun) {
            await upsertCardMapping(supabase, local.card_id, source.id as string, matchResult.classification === "ABSENT" ? "NOT_FOUND" : "PENDING", null, matchResult.method, matchResult.evidence, args.confirmedBy);
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

        const cardMappingId = await upsertCardMapping(supabase, local.card_id, source.id as string, "CONFIRMED", matchedCard, matchResult.method, matchResult.evidence, args.confirmedBy);
        if (!cardMappingId) continue;

        for (const variant of matchedCard.variants ?? []) {
          const externalProductId = String(variant.uuid ?? variant.id ?? "");
          const printingRaw = String(variant.printing ?? "");
          const conditionRaw = String(variant.condition ?? "");
          const price = variant.price;
          const lastUpdated = variant.lastUpdated;

          if (!externalProductId || !printingRaw || typeof price !== "number") continue;

          const { printingTipo } = splitPrintingLanguage(printingRaw);

          const { data: productData, error: productError } = await supabase
            .from("pricing_product")
            .insert({
              pricing_card_mapping_id: cardMappingId,
              external_product_id: externalProductId,
              source_printing_label: printingTipo ?? printingRaw,
              language_status: "UNDETERMINED",
              language_id: null,
            })
            .select("id")
            .maybeSingle();

          let productId: string | null = productData?.id as string | undefined ?? null;
          const productOutcome = classifyInsertResult(productError);
          if (productOutcome === "OTHER_ERROR") {
            errorParts.push(`PRODUCT_INSERT_FAILED(${externalProductId}): ${sanitize((productError as { message: string }).message)}`);
            continue;
          }
          if (!productId) {
            const { data: existingProduct } = await supabase.from("pricing_product").select("id").eq("pricing_card_mapping_id", cardMappingId).eq("external_product_id", externalProductId).maybeSingle();
            productId = (existingProduct?.id as string) ?? null;
          }
          if (!productId) continue;
          {
            const productCounts = { resolved: summary.productsResolved, written: summary.productsWritten };
            accumulateWriteOutcome(productCounts, productOutcome);
            summary.productsResolved = productCounts.resolved;
            summary.productsWritten = productCounts.written;
          }

          const conditionId = conditionMap.get(conditionRaw);
          if (!conditionId) {
            errorParts.push(`CONDICAO_SEM_MAPEAMENTO(${conditionRaw})`);
            continue;
          }

          const observedAt = typeof lastUpdated === "number" ? new Date(lastUpdated * 1000).toISOString() : new Date().toISOString();
          const rawPayload = sanitizeJson({ condition: conditionRaw, printing: printingRaw, price, lastUpdated });

          const { error: obsError } = await supabase.from("pricing_observation").insert({
            pricing_product_id: productId,
            condition_id: conditionId,
            sync_run_id: syncRunId,
            price_type: "MARKET",
            price,
            currency_code: "USD",
            market_label: MARKET_LABEL,
            market_scope: "UNDETERMINED",
            market_evidence: {},
            market_evidence_confirmed: false,
            observed_at: observedAt,
            raw_payload: rawPayload,
          });

          let existingPrice: number | null = null;
          if (obsError && `${obsError.message}`.includes("duplicate key")) {
            const { data: existingObs } = await supabase
              .from("pricing_observation")
              .select("price")
              .eq("pricing_product_id", productId)
              .eq("condition_id", conditionId)
              .eq("price_type", "MARKET")
              .eq("currency_code", "USD")
              .eq("market_label", MARKET_LABEL)
              .eq("observed_at", observedAt)
              .maybeSingle();
            existingPrice = existingObs?.price != null ? Number(existingObs.price) : null;
          }
          const observationOutcome = classifyObservationWrite(obsError, existingPrice, price);
          if (observationOutcome === "OTHER_ERROR") {
            errorParts.push(`OBSERVATION_INSERT_FAILED(${externalProductId}): ${sanitize((obsError as { message: string }).message)}`);
            continue;
          }
          if (observationOutcome === "DIVERGENT_PRESERVED") {
            summary.observationsDivergent++;
            errorParts.push(`OBSERVATION_PRICE_DIVERGENTE_PRESERVADA(${externalProductId}): existente=${existingPrice} novo=${price} observed_at=${observedAt}`);
          }
          summary.observationsResolved += observationOutcome === "NEW" || observationOutcome === "CONFLICT_IGNORED_SAME_PRICE" || observationOutcome === "DIVERGENT_PRESERVED" ? 1 : 0;
          if (observationOutcome === "NEW") summary.observationsWritten++;
        }
      }
    }

    const finalStatus = errorParts.length === 0 ? "COMPLETED" : summary.cardsSafe > 0 || summary.setsConfirmed > 0 ? "COMPLETED_WITH_ERRORS" : "FAILED";
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

async function upsertSetMapping(
  supabase: SupabaseClient,
  cardSetId: string,
  pricingSourceId: string,
  status: "CONFIRMED" | "PENDING" | "NOT_FOUND",
  matchedSet: JustTcgSet | null,
  method: string,
  evidence: Record<string, unknown>,
  confirmedBy: string,
): Promise<void> {
  const { data: existing } = await supabase.from("pricing_set_mapping").select("id, match_status").eq("card_set_id", cardSetId).eq("pricing_source_id", pricingSourceId).maybeSingle();
  const action = decideMappingUpsert(existing as MappingRowLike | null, status);
  if (action === "NOOP_SAME_STATUS" || action === "NOOP_KEEP_CONFIRMED_DIVERGENT_INPUT" || action === "NOOP_ALREADY_CONFIRMED") return;

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
    await supabase.from("pricing_set_mapping").insert({ card_set_id: cardSetId, pricing_source_id: pricingSourceId, ...payload });
  } else {
    await supabase.from("pricing_set_mapping").update(payload).eq("id", (existing as { id: string }).id);
  }
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
): Promise<string | null> {
  const { data: existing } = await supabase.from("pricing_card_mapping").select("id, match_status").eq("card_id", cardId).eq("pricing_source_id", pricingSourceId).maybeSingle();
  const action = decideMappingUpsert(existing as MappingRowLike | null, status);

  if (action === "NOOP_SAME_STATUS" || action === "NOOP_KEEP_CONFIRMED_DIVERGENT_INPUT" || action === "NOOP_ALREADY_CONFIRMED") {
    return (existing as { id: string } | null)?.id ?? null;
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
    const { data } = await supabase.from("pricing_card_mapping").insert({ card_id: cardId, pricing_source_id: pricingSourceId, ...payload }).select("id").maybeSingle();
    return (data?.id as string) ?? null;
  }
  await supabase.from("pricing_card_mapping").update(payload).eq("id", (existing as { id: string }).id);
  return (existing as { id: string }).id;
}

async function finalizeSyncRun(
  supabase: SupabaseClient,
  syncRunId: string | null,
  client: JustTcgClient,
  status: string,
  errorSummary: string | null,
  dryRun: boolean,
) {
  if (dryRun || !syncRunId) return;

  if (client.callLog.length > 0) {
    await supabase.from("pricing_sync_run_call").insert(
      client.callLog.map((c) => ({ ...c, sync_run_id: syncRunId })),
    );
  }

  const lastCall = client.callLog[client.callLog.length - 1];
  await supabase
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
}

// ============================================================================
// 8. Entrypoint
// ============================================================================

async function main() {
  const args = parseArgs(Deno.args);
  const hasApiKey = !!Deno.env.get("JUSTTCG_API_KEY");

  if (args.fixtureCheck || !hasApiKey) {
    if (!hasApiKey && !args.fixtureCheck) {
      console.log("JUSTTCG_API_KEY ausente — executando automaticamente em modo --fixture-check.\n");
    }
    await runFixtureCheck();
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
