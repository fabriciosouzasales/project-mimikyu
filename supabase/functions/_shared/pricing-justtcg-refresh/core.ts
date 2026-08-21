// Project Mimikyu — supabase/functions/_shared/pricing-justtcg-refresh/core.ts
// Orquestração pura de UMA onda do refresh diário JustTCG — Incremento de Atualização
// Diária JustTCG (2026-08-21), item B. Único ponto do núcleo que amarra wave-plan.ts +
// extract.ts + observation-decision.ts + run-lifecycle.ts + o cliente JustTCG
// compartilhado (_shared/pricing-justtcg) — nenhuma lógica de decisão vive fora desses
// módulos menores; este arquivo só sequencia chamadas na ordem certa.
//
// Ordem de execução (contrato desta rodada, mesma disciplina de handler.ts do
// ptax-fx-refresh):
//   1. Lê candidatos e monta o plano — SEM tocar a JustTCG (100% leitura local).
//   2. Onda fora do plano (regra 6, ex.: onda 5 com só 4 ondas calculadas) -> NOOP, nunca
//      cria pricing_sync_run.
//   3. Capacidade excedida (regra 7) -> nenhuma onda escreve, nunca cria
//      pricing_sync_run.
//   4. Abre o run (triggered_by=SCHEDULED, confirmed_by=NULL, run_type=PRICE_REFRESH) —
//      SEMPRE antes de qualquer chamada à JustTCG. Conflito de concorrência (CARD_SYNC OU
//      PRICE_REFRESH já ativo, regra 9) aborta sem tocar a rede.
//   5. Por Set da onda: identidades PRIMARY/ALTERNATE CONFIRMED (regra 10/17) ->
//      fetchAllCardsForSet (núcleo compartilhado, mesma paginação do CLI) -> extração por
//      identidade (extract.ts, nunca matching, regra 12) -> resolução idempotente de
//      produto por identidade+external_product_id (regra 13, INSERT-only) -> comparação
//      com a última observação e escrita só se o preço mudou (regra 14/observation-
//      decision.ts).
//   6. Telemetria (pricing_sync_run_call) SEMPRE antes da finalização do run — a partir
//      desta rodada (2026-08-21, correção pós-incidente), em CHECKPOINTS incrementais
//      entre Sets, nunca só uma vez no fim (ver passo 6b abaixo e deadline.ts).
//   6b. Deadline interno de segurança (110s, WAVE_INTERNAL_DEADLINE_MS) verificado no topo
//      de cada iteração do laço por Set — nunca no meio do processamento de um Set. Ao
//      atingir o limite: nenhum Set novo é iniciado, a telemetria já acumulada é
//      persistida (checkpoint), e o run finaliza FAILED com um código fixo sanitizado —
//      nunca fica PROCESSING. Corrige o incidente real desta rodada (worker
//      shutdown_reason=WallClockTime aos 150s, run 6c2ca781-...-4818341c preso em
//      PROCESSING com zero telemetria).
//   7. Falha real de escrita (produto/observação) ou AUTH_FAILURE -> run finaliza FAILED,
//      nunca COMPLETED — mas nenhuma escrita já confirmada em rodadas/Sets anteriores é
//      desfeita (regra 15: falha preserva o último preço válido, nunca um rollback lógico
//      do que já foi persistido com sucesso nesta mesma onda).

import {
  fetchAllCardsForSet,
  type JustTcgClient,
  sanitize,
} from "../pricing-justtcg/mod.ts";
import {
  type Clock,
  hasExceededDeadline,
  WAVE_INTERNAL_DEADLINE_MS,
} from "./deadline.ts";
import {
  buildRefreshWavePlan,
  MAX_WAVES,
  type RefreshSetCandidate,
} from "./wave-plan.ts";
import {
  extractRefreshObservationCandidates,
  type RefreshIdentityIndex,
  type RefreshObservationCandidate,
} from "./extract.ts";
import { decideObservationWrite } from "./observation-decision.ts";
import {
  finalizeSyncRun,
  persistCallLog,
  type PriceRefreshRunPort,
  tryStartPriceRefreshRun,
} from "./run-lifecycle.ts";
import type { InsertObservationInput, InsertProductInput } from "./port.ts";

export type WaveExecutionResult =
  | {
    kind: "NOOP_WAVE_NOT_IN_PLAN";
    waveNumber: number;
    planWaveCount: number;
    totalEstimatedPages: number;
  }
  | {
    kind: "CAPACITY_EXCEEDED";
    totalEstimatedPages: number;
    totalSets: number;
  }
  | { kind: "CONCURRENT_CONFLICT" }
  | { kind: "START_FAILED"; detail: string }
  | {
    kind: "EXECUTED";
    syncRunId: string;
    status: "COMPLETED" | "COMPLETED_WITH_ERRORS" | "FAILED";
    waveNumber: number;
    setsProcessed: number;
    identitiesConsidered: number;
    productsInserted: number;
    observationsWritten: number;
    observationsSkippedSamePrice: number;
    requestsMade: number;
    errorParts: string[];
  };

export async function executePriceRefreshWave(
  port: PriceRefreshRunPort,
  client: JustTcgClient,
  pricingSourceId: string,
  waveNumber: number,
  // Relógio injetável (correção pós-incidente, 2026-08-21) — produção nunca passa este
  // parâmetro (usa Date.now real via o valor padrão); testes injetam um relógio
  // determinístico para provar o corte no deadline sem esperar 110s de verdade. Ver
  // deadline.ts para o racional completo do valor e do incidente que motivou este
  // parâmetro.
  clock: Clock = Date.now,
): Promise<WaveExecutionResult> {
  // 1. Leitura local — nunca toca a JustTCG antes do plano estar decidido.
  const candidateSets: RefreshSetCandidate[] = await port
    .listRefreshCandidateSets(pricingSourceId);
  const plan = buildRefreshWavePlan(candidateSets);

  if (plan.status === "SCHEDULE_CAPACITY_EXCEEDED") {
    return {
      kind: "CAPACITY_EXCEEDED",
      totalEstimatedPages: plan.totalEstimatedPages,
      totalSets: plan.totalSets,
    };
  }

  if (waveNumber < 1 || waveNumber > MAX_WAVES) {
    // Defensivo — o handler da Edge Function já valida 1-30 antes de chamar core.ts
    // (elevado de 1-10 nesta rodada de correção pós-incidente, 2026-08-21); nunca deveria
    // chegar aqui, mas nunca cria run fora do intervalo válido.
    return {
      kind: "NOOP_WAVE_NOT_IN_PLAN",
      waveNumber,
      planWaveCount: plan.waves.length,
      totalEstimatedPages: plan.totalEstimatedPages,
    };
  }

  const wave = plan.waves.find((w) => w.waveNumber === waveNumber);
  if (!wave) {
    // Regra 6: com o volume atual (98 páginas -> 4 ondas), a onda 5 cai aqui — NOOP sem
    // criar pricing_sync_run.
    return {
      kind: "NOOP_WAVE_NOT_IN_PLAN",
      waveNumber,
      planWaveCount: plan.waves.length,
      totalEstimatedPages: plan.totalEstimatedPages,
    };
  }

  // 2. Abre o run — SEMPRE antes de qualquer chamada à JustTCG (mesmo precedente de
  // tryStartSyncRun no PTAX / tryOpenCardSyncRun no CLI).
  const startAttempt = await tryStartPriceRefreshRun(port, pricingSourceId);
  if (startAttempt.status === "CONCURRENT_CONFLICT") {
    return { kind: "CONCURRENT_CONFLICT" };
  }
  if (startAttempt.status === "OTHER_ERROR") {
    return { kind: "START_FAILED", detail: startAttempt.detail };
  }
  const syncRunId = startAttempt.syncRunId;

  const errorParts: string[] = [];
  let setsProcessed = 0;
  let identitiesConsidered = 0;
  let productsInserted = 0;
  let observationsWritten = 0;
  let observationsSkippedSamePrice = 0;
  // hardFailure: só para falhas REAIS (credencial inválida, escrita rejeitada pelo banco,
  // deadline interno atingido, falha ao persistir um checkpoint de telemetria) — nunca
  // para BUDGET_STOPPED (parada esperada por desenho, dentro do orçamento da onda) nem
  // para uma falha técnica pontual de UM Set entre vários (os demais Sets da onda ainda
  // são tentados).
  let hardFailure = false;

  // Deadline interno de segurança (correção pós-incidente, 2026-08-21) — contado a partir
  // do início do processamento por Set (logo após o run abrir com sucesso), verificado
  // SEMPRE no topo do laço, nunca no meio do processamento de um Set (regra 2 de
  // Fabrício: "verificável entre Sets"). Ver deadline.ts.
  const waveStartedAtMs = clock();

  // Checkpoint incremental de telemetria (correção pós-incidente, 2026-08-21, regra 3):
  // client.callLog cresce de forma monotônica (append-only, sequence_number nunca é
  // reaproveitado) — este índice marca até onde já foi persistido em
  // pricing_sync_run_call, para que cada checkpoint envie só as entradas NOVAS desde o
  // último flush (uq_pricing_sync_run_call_run_sequence é único por (sync_run_id,
  // sequence_number); reenviar uma entrada já persistida violaria essa constraint).
  let lastFlushedCallLogIndex = 0;
  async function checkpointTelemetry(): Promise<
    { ok: true } | { ok: false; detail: string }
  > {
    const newEntries = client.callLog.slice(lastFlushedCallLogIndex);
    if (newEntries.length === 0) return { ok: true };
    const result = await persistCallLog(port, syncRunId, newEntries);
    if (result.ok) {
      lastFlushedCallLogIndex = client.callLog.length;
    }
    return result;
  }

  const conditionMap = await port.getConditionMap(pricingSourceId);

  for (const setEntry of wave.sets) {
    // 2a. Checkpoint da telemetria acumulada pelo Set ANTERIOR — nunca perde calls já
    // feitas por um corte inesperado no meio da onda (regra 3). No-op na primeira
    // iteração (client.callLog ainda vazio).
    const checkpoint = await checkpointTelemetry();
    if (!checkpoint.ok) {
      errorParts.push(
        `PRICING_SYNC_RUN_CALL_CHECKPOINT_FAILED: ${checkpoint.detail}`,
      );
      hardFailure = true;
      break; // telemetria não confiável — não arrisca continuar a onda sem esse registro
    }

    // 2b. Deadline interno — SEMPRE verificado aqui, "entre Sets" (regra 2), nunca no
    // meio do processamento de um Set. Ao atingir o limite: nenhum Set novo é iniciado
    // (interrompe aquisição), a telemetria do Set anterior já foi persistida acima, e a
    // onda finaliza FAILED com um código fixo sanitizado (nunca fica PROCESSING).
    if (hasExceededDeadline(waveStartedAtMs, clock, WAVE_INTERNAL_DEADLINE_MS)) {
      hardFailure = true;
      errorParts.push(
        `WAVE_INTERNAL_DEADLINE_EXCEEDED(setsProcessed=${setsProcessed}, totalSetsInWave=${wave.sets.length})`,
      );
      break;
    }

    const identities = await port.listConfirmedIdentitiesForSet(
      pricingSourceId,
      setEntry.cardSetId,
    );
    identitiesConsidered += identities.length;
    if (identities.length === 0) {
      // Defensivo — corrida rara entre a leitura do plano e esta leitura por Set; o
      // candidato só entrou no plano porque tinha >=1 identidade confirmada no momento da
      // primeira leitura. Nunca um erro, só um Set sem trabalho nesta execução.
      setsProcessed++;
      continue;
    }
    const identityIndex: RefreshIdentityIndex = new Map(
      identities.map((
        i,
      ) => [i.externalCardId, {
        identityId: i.identityId,
        identityRole: i.identityRole,
        pricingCardMappingId: i.pricingCardMappingId,
      }]),
    );

    const { cards, aborted } = await fetchAllCardsForSet(
      client,
      setEntry.externalSetId,
    );
    if (aborted === "AUTH_FAILURE") {
      errorParts.push(`AUTH_FAILURE(set=${setEntry.setCode})`);
      hardFailure = true;
      break; // credencial inválida — nenhum Set adicional é tentado nesta onda
    }
    if (aborted === "BUDGET_STOPPED") {
      errorParts.push(`BUDGET_STOPPED(set=${setEntry.setCode})`);
      break; // teto de WAVE_PAGE_CAP requisições da onda atingido — Sets restantes ficam
      // para a próxima execução agendada; parada esperada, nunca uma falha real
    }
    if (aborted === "TECHNICAL_FAILURE") {
      errorParts.push(`TECHNICAL_FAILURE(set=${setEntry.setCode})`);
      continue; // falha pontual deste Set — os demais Sets da onda ainda são tentados
    }

    const { candidates, skippedReasons } = extractRefreshObservationCandidates(
      cards,
      identityIndex,
      conditionMap,
    );
    errorParts.push(
      ...skippedReasons.map((r) => `${r}(set=${setEntry.setCode})`),
    );

    if (candidates.length === 0) {
      setsProcessed++;
      continue;
    }

    // 3. Resolução idempotente de produto — SELECT existentes por identidade, INSERT só
    // os faltantes. Nunca UPDATE de um produto já existente (regra 13).
    const identityIds = [...new Set(candidates.map((c) => c.identityId))];
    const existingProducts = await port.findExistingProducts(identityIds);
    const productIdByKey = new Map<string, string>();
    for (const p of existingProducts) {
      productIdByKey.set(
        `${p.pricingSourceCardIdentityId}::${p.externalProductId}`,
        p.productId,
      );
    }

    const toInsertProducts: InsertProductInput[] = [];
    const seenThisSet = new Set<string>();
    for (const c of candidates) {
      const key = `${c.identityId}::${c.externalProductId}`;
      if (productIdByKey.has(key) || seenThisSet.has(key)) continue; // REUSE — zero escrita
      seenThisSet.add(key);
      toInsertProducts.push({
        pricingCardMappingId: c.pricingCardMappingId,
        pricingSourceCardIdentityId: c.identityId,
        externalProductId: c.externalProductId,
        sourcePrintingLabel: c.sourcePrintingLabel,
      });
    }
    if (toInsertProducts.length > 0) {
      const insertResult = await port.insertProducts(toInsertProducts);
      if (!insertResult.ok) {
        errorParts.push(
          `PRODUCT_INSERT_FAILED(set=${setEntry.setCode}): ${
            insertResult.message ?? "erro desconhecido"
          }`,
        );
        hardFailure = true;
      } else {
        for (const row of insertResult.inserted) {
          productIdByKey.set(
            `${row.pricingSourceCardIdentityId}::${row.externalProductId}`,
            row.productId,
          );
          productsInserted++;
        }
      }
    }

    // Candidatos cujo produto ficou resolvido nesta rodada (já existia OU foi inserido
    // com sucesso agora) — os demais ficam de fora, recuperáveis numa reexecução futura,
    // nunca corrigidos silenciosamente.
    const candidatesWithProduct = candidates
      .map((c) => ({
        ...c,
        productId:
          productIdByKey.get(`${c.identityId}::${c.externalProductId}`) ??
            null,
      }))
      .filter((
        c,
      ): c is RefreshObservationCandidate & { productId: string } =>
        c.productId !== null
      );

    const unresolved = candidates.length - candidatesWithProduct.length;
    if (unresolved > 0) {
      errorParts.push(
        `PRODUCT_UNRESOLVED_SKIP_OBSERVATIONS(set=${setEntry.setCode}, count=${unresolved})`,
      );
    }

    // 4. Compara com a última observação conhecida (produto+condição) e decide escrita —
    // regra 14: observação nova só quando o preço realmente muda.
    const uniqueGroupKeys = new Map<
      string,
      { productId: string; conditionId: string }
    >();
    for (const c of candidatesWithProduct) {
      const key = `${c.productId}::${c.conditionId}`;
      if (!uniqueGroupKeys.has(key)) {
        uniqueGroupKeys.set(key, {
          productId: c.productId,
          conditionId: c.conditionId,
        });
      }
    }
    const latestRows = await port.findLatestObservations([
      ...uniqueGroupKeys.values(),
    ]);
    const latestByGroup = new Map<
      string,
      { price: number; observedAt: string }
    >();
    for (const row of latestRows) {
      latestByGroup.set(`${row.productId}::${row.conditionId}`, {
        price: row.price,
        observedAt: row.observedAt,
      });
    }

    const toInsertObservations: InsertObservationInput[] = [];
    const decidedThisSet = new Map<
      string,
      { price: number; observedAt: string }
    >();
    for (const c of candidatesWithProduct) {
      const key = `${c.productId}::${c.conditionId}`;
      const latest = decidedThisSet.get(key) ?? latestByGroup.get(key) ?? null;
      const decision = decideObservationWrite(latest, {
        price: c.price,
        observedAt: c.observedAt,
      });
      if (decision.kind === "SAME_PRICE_SKIP") {
        observationsSkippedSamePrice++;
        continue;
      }
      if (decision.kind === "DIVERGENT_SAME_TIMESTAMP_PRESERVED") {
        errorParts.push(
          `OBSERVATION_DIVERGENTE_PRESERVADA(set=${setEntry.setCode}, produto=${c.externalProductId}): existente=${decision.existingPrice} novo=${c.price} observed_at=${c.observedAt}`,
        );
        continue;
      }
      // FIRST_OBSERVATION ou PRICE_CHANGED_WRITE — grava.
      decidedThisSet.set(key, { price: c.price, observedAt: c.observedAt });
      toInsertObservations.push({
        productId: c.productId,
        conditionId: c.conditionId,
        syncRunId,
        price: c.price,
        observedAt: c.observedAt,
        rawPayload: c.rawPayload,
      });
    }

    if (toInsertObservations.length > 0) {
      const obsResult = await port.insertObservations(toInsertObservations);
      if (!obsResult.ok) {
        errorParts.push(
          `OBSERVATION_INSERT_FAILED(set=${setEntry.setCode}): ${
            obsResult.message ?? "erro desconhecido"
          }`,
        );
        hardFailure = true;
      } else {
        observationsWritten += toInsertObservations.length;
      }
    }

    setsProcessed++;
  }

  // 5. Telemetria SEMPRE antes da finalização (Query 3909, mesma disciplina de PTAX/CLI)
  // — checkpoint FINAL, flush de qualquer entrada ainda não persistida do ÚLTIMO Set
  // tocado (loop terminado normalmente, por BUDGET_STOPPED/AUTH_FAILURE, ou pelo deadline
  // interno — checkpointTelemetry() só envia o que ainda não foi enviado, nunca reenvia).
  const callLogResult = await checkpointTelemetry();
  const requestsMade = client.requestsMade;
  const rateLimitHits = client.rateLimitHits;

  if (!callLogResult.ok) {
    const detail =
      `PRICING_SYNC_RUN_CALL_INSERT_FAILED: ${callLogResult.detail}`;
    await finalizeSyncRun(
      port,
      syncRunId,
      "FAILED",
      sanitize(detail),
      requestsMade,
      rateLimitHits,
    );
    return {
      kind: "EXECUTED",
      syncRunId,
      status: "FAILED",
      waveNumber,
      setsProcessed,
      identitiesConsidered,
      productsInserted,
      observationsWritten,
      observationsSkippedSamePrice,
      requestsMade,
      errorParts: [...errorParts, detail],
    };
  }

  const status: "COMPLETED" | "COMPLETED_WITH_ERRORS" | "FAILED" = hardFailure
    ? "FAILED"
    : errorParts.length > 0
    ? "COMPLETED_WITH_ERRORS"
    : "COMPLETED";
  const errorSummary = errorParts.length > 0
    ? sanitize(errorParts.join(" | "))
    : null;
  await finalizeSyncRun(
    port,
    syncRunId,
    status,
    errorSummary,
    requestsMade,
    rateLimitHits,
  );

  return {
    kind: "EXECUTED",
    syncRunId,
    status,
    waveNumber,
    setsProcessed,
    identitiesConsidered,
    productsInserted,
    observationsWritten,
    observationsSkippedSamePrice,
    requestsMade,
    errorParts,
  };
}
