// Project Mimikyu — supabase/functions/_shared/pricing-justtcg-refresh/set-refresh-core.ts
// Núcleo puro do dispatcher durável por Set (P15) — consome SetRefreshPort
// (set-refresh-port.ts) e JustTcgClient (_shared/pricing-justtcg) para processar UM Set
// por invocação: open -> fetch/processa páginas -> checkpoint -> close.
//
// Contrato desta rodada (pedido de Fabrício, "Base persistente do scheduler por Set
// APROVADA"):
//   - 1 Set por invocação (decidido inteiramente por open_pricing_set_refresh_attempt —
//     este núcleo nunca escolhe QUAL Set processar).
//   - Até SET_REQUEST_BUDGET=10 requisições (JustTcgClient aplica o teto — a checagem
//     real acontece dentro do próprio client.get(), nunca duplicada aqui).
//   - Deadline interno de SET_INTERNAL_DEADLINE_MS=110s (mesmo valor/margem de segurança
//     já validado em produção pelo desenho wave-based anterior — ver deadline.ts),
//     verificado ANTES de cada fetch de página (nunca no meio do processamento de uma
//     página já iniciada).
//   - SOURCE_BUSY/NO_CANDIDATE ("NO_WORK") terminam limpo, sem tocar a JustTCG e sem
//     nenhuma chamada a checkpoint_/close_ (nenhum pricing_sync_run foi aberto).
//   - BUDGET_STOPPED e DEADLINE_STOPPED são continuação normal (p_run_status=COMPLETED,
//     nunca FAILED) — o próprio desenho da RPC close_ já libera a lease com
//     next_due_at=now(), então o próximo tick do dispatcher retoma via resume_offset.
//   - RECONCILIATION_INCOMPLETE nunca é tratado como SUCCESS — ambos chegam aqui só como
//     CloseAttemptResult.finalOutcome (texto opaco desta camada, decidido inteiramente
//     pela RPC via reconciliação por identidade — este núcleo nunca recalcula cobertura).
//   - R1/R5 (resolveProductsBatch, NEW/REUSE pela chave econômica real),
//     PRIMARY/ALTERNATE (via RefreshIdentityRow.identityRole, propagado sem alteração) e
//     SAME_PRICE_SKIP (decideObservationWrite) são REUSO INTEGRAL do núcleo já validado —
//     nenhuma das 3 regras foi reescrita nesta rodada.
//   - Nenhuma escrita em pricing_set_mapping/pricing_card_mapping/
//     pricing_source_card_identity — SetRefreshPort não expõe nenhuma operação nessas
//     tabelas (garantia estrutural, ver set-refresh-port.ts).
//   - Telemetria pricing_sync_run_call (correção 2026-08-22, a pedido de Fabrício):
//     flushCallLogTelemetry() reaproveita port.insertSyncRunCalls tal como já existe
//     (mesma tabela, mesmo contrato — nunca uma tabela/coluna nova) em checkpoints
//     incrementais — um após cada página com checkpoint bem-sucedido, mais um flush final
//     antes de closeAttempt — mesma disciplina de core.ts (wave-based) pós-incidente
//     2026-08-21: nunca perde telemetria de calls já feitas por um corte inesperado.
//     client.callLog já distingue BUDGET_STOPPED (outcome="BUDGET_STOPPED",
//     http_status_code=null, sem HTTP real) de qualquer chamada que de fato saiu pela
//     rede — sequence_number é monotônico por client (1 client por tentativa de Set,
//     nunca reaproveitado entre tentativas). Falha no flush FINAL força
//     runStatus=FAILED (nunca reinterpreta p_page_outcome — este continua governando só
//     o estado de pricing_set_refresh_state).

import type { Clock } from "./deadline.ts";
import { hasExceededDeadline, WAVE_INTERNAL_DEADLINE_MS } from "./deadline.ts";
import {
  extractRefreshObservationCandidates,
  type RefreshIdentityIndex,
} from "./extract.ts";
import { decideObservationWrite } from "./observation-decision.ts";
import type {
  InsertObservationInput,
  LatestObservationKey,
  LatestObservationRow,
  PageOutcome,
  RefreshIdentityRow,
  ResolvedProductRow,
  ResolveProductsBatchInput,
  RunStatus,
  SetRefreshPort,
} from "./set-refresh-port.ts";
import {
  CARDS_PAGE_LIMIT,
  GAME_CODE,
  type JustTcgCard,
  type JustTcgClient,
} from "../pricing-justtcg/mod.ts";

// Teto de requisições por invocação — "até 10 requests" (pedido de Fabrício). Repassado
// ao construtor de JustTcgClient pelo chamador (index.ts/testes); JustTcgClient sempre
// aplica Math.min(requestBudget, MAX_REQUESTS_PER_RUN=30) internamente — este núcleo nunca
// verifica orçamento por conta própria, só reage ao status "BUDGET_STOPPED" já devolvido
// por client.get().
export const SET_REQUEST_BUDGET = 10;

// Mesmo valor/margem de segurança já validado em produção (incidente documentado em
// deadline.ts) — reexportado aqui só por conveniência de import único pelo chamador.
export const SET_INTERNAL_DEADLINE_MS = WAVE_INTERNAL_DEADLINE_MS;

export type SetRefreshExecutionResult =
  // Nenhum Set elegível agora — nenhum pricing_sync_run aberto.
  | { kind: "NO_WORK" }
  // Já existe outro PRICE_REFRESH/CARD_SYNC ativo para esta fonte — nenhum
  // pricing_sync_run aberto por este núcleo (o conflito é do run JÁ existente).
  | { kind: "SOURCE_BUSY" }
  // Lease perdida/expirada em pleno processamento (outro processo já reconciliou este run
  // como órfão) — defensivo, nunca esperado em operação normal de 1 invocação por vez;
  // este núcleo para IMEDIATAMENTE, nunca chama close_ (o run não é mais seu).
  | { kind: "LEASE_LOST"; syncRunId: string }
  | {
    kind: "CLOSED";
    syncRunId: string;
    pageOutcome: PageOutcome;
    runStatus: RunStatus;
    // Texto opaco devolvido pela RPC close_ — ver CloseAttemptResult.finalOutcome.
    finalOutcome: string;
    seenCount: number | null;
    expectedCount: number | null;
    requestsMade: number;
    rateLimitHits: number;
    pagesProcessed: number;
    candidatesExtracted: number;
    cardsUnmatchedTotal: number;
    productsNew: number;
    productsReused: number;
    observationsWritten: number;
    observationsSkippedSamePrice: number;
  };

// Decide p_run_status a partir do p_page_outcome que este núcleo já decidiu — separação
// deliberada de responsabilidade: p_page_outcome governa o próximo estado operacional de
// pricing_set_refresh_state (lease/backoff/pausa, já implementado na RPC), p_run_status
// governa só o status HISTÓRICO deste pricing_sync_run específico (nunca revalidado pela
// RPC). isPreOpenFailure=true é o único caminho que produz FAILED fora de AUTH_FAILURE:
// uma leitura local (identidades/condições) falhou ANTES de qualquer chamada à JustTCG —
// zero trabalho útil foi tentado, run realmente fracassado, não "parcialmente completo".
// AUTH_FAILURE também vira FAILED mesmo que páginas anteriores já tenham tido sucesso
// (credencial quebrada é severo o bastante para nunca aparecer como COMPLETED_WITH_ERRORS
// — mais fácil de um operador notar varrendo por status='FAILED').
export function decideRunStatus(
  pageOutcome: PageOutcome,
  isPreOpenFailure: boolean,
): RunStatus {
  if (isPreOpenFailure) return "FAILED";
  switch (pageOutcome) {
    case "AUTH_FAILURE":
      return "FAILED";
    case "TRANSIENT_ERROR":
    case "SET_TERMINAL_ERROR":
      return "COMPLETED_WITH_ERRORS";
    case "NO_MORE_PAGES":
    case "BUDGET_STOPPED":
    case "DEADLINE_STOPPED":
      return "COMPLETED";
  }
}

export async function executeSetRefreshAttempt(
  port: SetRefreshPort,
  client: JustTcgClient,
  pricingSourceId: string,
  clock: Clock = Date.now,
): Promise<SetRefreshExecutionResult> {
  const startedAtMs = clock();

  const openResult = await port.openAttempt(pricingSourceId);
  if (openResult.outcome === "NO_CANDIDATE") {
    return { kind: "NO_WORK" };
  }
  if (openResult.outcome === "SOURCE_BUSY") {
    return { kind: "SOURCE_BUSY" };
  }

  const { syncRunId, cardSetId, externalSetId } = openResult;

  // Telemetria (pricing_sync_run_call) — checkpoint incremental, reaproveitando
  // port.insertSyncRunCalls tal como já existe (ver cabeçalho). client.callLog cresce de
  // forma monotônica (append-only); este índice marca até onde já foi persistido, para
  // que cada flush envie só as entradas NOVAS desde o último (uq_pricing_sync_run_call_
  // run_sequence é único por (sync_run_id, sequence_number) — reenviar uma entrada já
  // persistida violaria essa constraint).
  let lastFlushedCallLogIndex = 0;
  async function flushCallLogTelemetry(): Promise<boolean> {
    const newEntries = client.callLog.slice(lastFlushedCallLogIndex);
    if (newEntries.length === 0) return true;
    const result = await port.insertSyncRunCalls(syncRunId, newEntries);
    if (result.ok) {
      lastFlushedCallLogIndex = client.callLog.length;
      return true;
    }
    return false;
  }

  // Leitura local (identidades PRIMARY/ALTERNATE CONFIRMED do Set + mapa de condições) —
  // UMA vez por Set, nunca por página (mesma disciplina do núcleo wave-based anterior).
  // Falha aqui significa ZERO trabalho útil tentado: fecha como FAILED/TRANSIENT_ERROR
  // sem nunca ter tocado a JustTCG nem processado nenhuma página.
  let identityRows: RefreshIdentityRow[];
  let conditionMap: Map<string, string>;
  try {
    [identityRows, conditionMap] = await Promise.all([
      port.listConfirmedIdentitiesForSet(pricingSourceId, cardSetId),
      port.getConditionMap(pricingSourceId),
    ]);
  } catch {
    // client.callLog está sempre vazio aqui (falha ocorre ANTES de qualquer chamada à
    // JustTCG) — flush é um no-op estrutural, chamado mesmo assim só para manter o
    // invariante "sempre flush antes de qualquer closeAttempt" verificável por leitura.
    await flushCallLogTelemetry();
    const closeResult = await port.closeAttempt(
      syncRunId,
      "TRANSIENT_ERROR",
      decideRunStatus("TRANSIENT_ERROR", true),
      0,
      0,
      "LOCAL_IDENTITY_OR_CONDITION_READ_FAILED",
    );
    return {
      kind: "CLOSED",
      syncRunId,
      pageOutcome: "TRANSIENT_ERROR",
      runStatus: "FAILED",
      finalOutcome: closeResult.finalOutcome,
      seenCount: closeResult.seenCount,
      expectedCount: closeResult.expectedCount,
      requestsMade: 0,
      rateLimitHits: 0,
      pagesProcessed: 0,
      candidatesExtracted: 0,
      cardsUnmatchedTotal: 0,
      productsNew: 0,
      productsReused: 0,
      observationsWritten: 0,
      observationsSkippedSamePrice: 0,
    };
  }

  const identityIndex: RefreshIdentityIndex = new Map();
  for (const row of identityRows) {
    identityIndex.set(row.externalCardId, {
      identityId: row.identityId,
      identityRole: row.identityRole,
      pricingCardMappingId: row.pricingCardMappingId,
    });
  }

  let offset = openResult.resumeOffset;
  const cumulativeSeen = new Set(openResult.cycleSeenExternalCardIds);

  let pagesProcessed = 0;
  let candidatesExtracted = 0;
  let cardsUnmatchedTotal = 0;
  let productsNew = 0;
  let productsReused = 0;
  let observationsWritten = 0;
  let observationsSkippedSamePrice = 0;

  let pageOutcome: PageOutcome | null = null;
  let errorSummary: string | null = null;

  pageLoop: for (;;) {
    if (hasExceededDeadline(startedAtMs, clock, SET_INTERNAL_DEADLINE_MS)) {
      pageOutcome = "DEADLINE_STOPPED";
      break pageLoop;
    }

    const pageResult = await client.get<{ data: JustTcgCard[] }>("/cards", {
      game: GAME_CODE,
      set: externalSetId,
      limit: String(CARDS_PAGE_LIMIT),
      offset: String(offset),
    });

    if (pageResult.status === "BUDGET_STOPPED") {
      pageOutcome = "BUDGET_STOPPED";
      break pageLoop;
    }
    if (pageResult.status === "AUTH_FAILURE") {
      pageOutcome = "AUTH_FAILURE";
      errorSummary = "JUSTTCG_AUTH_FAILURE";
      break pageLoop;
    }
    if (pageResult.status === "TECHNICAL_FAILURE") {
      // 404 = o próprio Set/rota não existe mais na JustTCG — estrutural, repetir nunca
      // resolve (SET_TERMINAL_ERROR, pausa o Set até intervenção manual). Qualquer outro
      // status (5xx, timeout local com httpStatus=null) é tratado como transitório —
      // backoff exponencial via TRANSIENT_ERROR, tenta de novo no próximo tick.
      if (pageResult.httpStatus === 404) {
        pageOutcome = "SET_TERMINAL_ERROR";
        errorSummary = "JUSTTCG_SET_NOT_FOUND_404";
      } else {
        pageOutcome = "TRANSIENT_ERROR";
        errorSummary = "JUSTTCG_PAGE_FETCH_TECHNICAL_FAILURE";
      }
      break pageLoop;
    }

    // status === "SUCCESS"
    pagesProcessed++;
    const cards = pageResult.data?.data ?? [];

    const extractResult = extractRefreshObservationCandidates(
      cards,
      identityIndex,
      conditionMap,
    );
    candidatesExtracted += extractResult.candidates.length;
    cardsUnmatchedTotal += extractResult.cardsUnmatchedCount;

    if (extractResult.candidates.length > 0) {
      const resolveInput: ResolveProductsBatchInput[] = extractResult.candidates
        .map((c) => ({
          pricingCardMappingId: c.pricingCardMappingId,
          pricingSourceCardIdentityId: c.identityId,
          externalProductId: c.externalProductId,
          sourcePrintingLabel: c.sourcePrintingLabel,
        }));
      const resolveResult = await port.resolveProductsBatch(resolveInput);
      if (!resolveResult.ok) {
        pageOutcome = "TRANSIENT_ERROR";
        errorSummary = "PRODUCT_RESOLUTION_FAILED";
        break pageLoop;
      }

      const productByKey = new Map<string, ResolvedProductRow>();
      for (const row of resolveResult.rows) {
        productByKey.set(
          `${row.pricingCardMappingId}::${row.externalProductId}`,
          row,
        );
        if (row.classification === "NEW") productsNew++;
        else productsReused++;
      }

      const obsKeys: LatestObservationKey[] = [];
      const seenObsKeys = new Set<string>();
      for (const candidate of extractResult.candidates) {
        const product = productByKey.get(
          `${candidate.pricingCardMappingId}::${candidate.externalProductId}`,
        );
        if (!product) continue; // defensivo — resolveProductsBatch garante 1:1 (migration 3928)
        const key = `${product.productId}::${candidate.conditionId}`;
        if (seenObsKeys.has(key)) continue;
        seenObsKeys.add(key);
        obsKeys.push({
          productId: product.productId,
          conditionId: candidate.conditionId,
        });
      }
      const latestRows = await port.findLatestObservations(obsKeys);
      const latestByKey = new Map<string, LatestObservationRow>();
      for (const row of latestRows) {
        latestByKey.set(`${row.productId}::${row.conditionId}`, row);
      }

      const toInsert: InsertObservationInput[] = [];
      for (const candidate of extractResult.candidates) {
        const product = productByKey.get(
          `${candidate.pricingCardMappingId}::${candidate.externalProductId}`,
        );
        if (!product) continue;
        const latest = latestByKey.get(
          `${product.productId}::${candidate.conditionId}`,
        ) ?? null;
        const decision = decideObservationWrite(
          latest ? { price: latest.price, observedAt: latest.observedAt } : null,
          { price: candidate.price, observedAt: candidate.observedAt },
        );
        if (
          decision.kind === "FIRST_OBSERVATION" ||
          decision.kind === "PRICE_CHANGED_WRITE"
        ) {
          toInsert.push({
            productId: product.productId,
            conditionId: candidate.conditionId,
            syncRunId,
            price: candidate.price,
            observedAt: candidate.observedAt,
            rawPayload: candidate.rawPayload,
          });
        } else if (decision.kind === "SAME_PRICE_SKIP") {
          observationsSkippedSamePrice++;
        }
        // DIVERGENT_SAME_TIMESTAMP_PRESERVED — nunca escreve, nunca conta como skip "normal"
        // (mesma disciplina do núcleo antigo: só sinalizado, não contabilizado aqui).
      }

      if (toInsert.length > 0) {
        const insertResult = await port.insertObservations(toInsert);
        if (!insertResult.ok) {
          pageOutcome = "TRANSIENT_ERROR";
          errorSummary = "OBSERVATION_INSERT_FAILED";
          break pageLoop;
        }
        observationsWritten += toInsert.length;
      }
    }

    // Checkpoint desta página — SEMPRE, mesmo com zero candidatos (a página pode ser
    // 100% cartas não confirmadas nossas; o offset precisa avançar de qualquer forma).
    const newlySeenThisPage: string[] = [];
    for (const card of cards) {
      const id = String(card.id ?? "");
      if (id && !cumulativeSeen.has(id)) {
        newlySeenThisPage.push(id);
      }
    }
    for (const id of newlySeenThisPage) cumulativeSeen.add(id);
    offset += CARDS_PAGE_LIMIT;

    const checkpointOk = await port.checkpointPage(
      syncRunId,
      offset,
      newlySeenThisPage,
    );
    if (!checkpointOk) {
      // Lease perdida/expirada — nunca chama close_ (o run não é mais nosso). Defensivo,
      // nunca esperado com 1 invocação por vez (garantia operacional deste incremento).
      // Flush best-effort — as requisições já feitas a esta página são reais e válidas
      // independente do destino do run; resultado nunca muda o retorno LEASE_LOST.
      await flushCallLogTelemetry();
      return { kind: "LEASE_LOST", syncRunId };
    }

    // Telemetria — checkpoint incremental desta página (mesma disciplina de core.ts
    // wave-based: nunca perde calls já feitas por um corte inesperado). Falha aqui
    // encerra o laço (nenhuma página nova é iniciada) — a página atual já teve seu
    // trabalho de negócio e checkpoint persistidos com sucesso; só a telemetria falhou.
    if (!(await flushCallLogTelemetry())) {
      pageOutcome = "TRANSIENT_ERROR";
      errorSummary = "PRICING_SYNC_RUN_CALL_INSERT_FAILED";
      break pageLoop;
    }

    // Mesmo critério de fim-de-páginas de fetchAllCardsForSet (pagination.ts) — meta.hasMore
    // quando presente, senão página mais curta que o limite = última.
    const hasMore = pageResult.meta?.hasMore ?? cards.length === CARDS_PAGE_LIMIT;
    if (!hasMore || cards.length === 0) {
      pageOutcome = "NO_MORE_PAGES";
      break pageLoop;
    }
    // Senão, continua — próxima iteração reavalia deadline antes do próximo fetch.
  }

  const finalPageOutcome = pageOutcome as PageOutcome; // todo caminho de saída do loop (exceto LEASE_LOST, já retornado acima) atribui um valor
  let runStatus = decideRunStatus(finalPageOutcome, false);

  // Flush final — cobre entradas ainda não persistidas (BUDGET_STOPPED/AUTH_FAILURE/
  // TECHNICAL_FAILURE/DEADLINE_STOPPED nunca passam pelo flush por página acima, já que
  // saem do laço antes de chegar lá) e reforça o invariante "sempre flush antes de
  // closeAttempt" (mesma disciplina de core.ts wave-based, passo 5: "telemetria SEMPRE
  // antes da finalização"). Falha aqui nunca reinterpreta p_page_outcome (continua
  // governando só pricing_set_refresh_state) — só força runStatus=FAILED, mesmo padrão
  // de severidade do núcleo antigo para uma falha de telemetria no flush final.
  if (!(await flushCallLogTelemetry())) {
    runStatus = "FAILED";
    errorSummary = "PRICING_SYNC_RUN_CALL_INSERT_FAILED";
  }

  const closeResult = await port.closeAttempt(
    syncRunId,
    finalPageOutcome,
    runStatus,
    client.requestsMade,
    client.rateLimitHits,
    errorSummary,
  );

  return {
    kind: "CLOSED",
    syncRunId,
    pageOutcome: finalPageOutcome,
    runStatus,
    finalOutcome: closeResult.finalOutcome,
    seenCount: closeResult.seenCount,
    expectedCount: closeResult.expectedCount,
    requestsMade: client.requestsMade,
    rateLimitHits: client.rateLimitHits,
    pagesProcessed,
    candidatesExtracted,
    cardsUnmatchedTotal,
    productsNew,
    productsReused,
    observationsWritten,
    observationsSkippedSamePrice,
  };
}
