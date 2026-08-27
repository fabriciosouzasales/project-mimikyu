// Project Mimikyu — supabase/functions/_shared/pricing-justtcg-bootstrap/bootstrap-core.ts
// Núcleo puro do executor de bootstrap de Set (P16.5.2/P16.5.3, "executor de bootstrap +
// port/adapter", 2026-08-26) — dado um pricing_set_mapping_id já reivindicado pelas RPCs de
// P16.5.1 (migration 3955, PROPOSTA), conduz UMA invocação através de exatamente UMA das duas
// fases da máquina de estados de pricing_set_bootstrap_state (3953):
//
//   Fase de AQUISIÇÃO (status recebido de open_ é PENDING ou ACQUIRING):
//     adquire /cards da JustTCG por páginas a partir de acquisition_resume_offset, persiste
//     cada página no staging via checkpoint_ (só avança depois de staging confirmado), e ao
//     final chama close_ com NO_MORE_PAGES/BUDGET_STOPPED/DEADLINE_STOPPED/TRANSIENT_ERROR/
//     SET_TERMINAL_ERROR/AUTH_FAILURE. NO_MORE_PAGES transiciona PENDING/ACQUIRING->MATCHING
//     e LIBERA A LEASE (mesmo close_ que fecha esta invocação) — a fase de matching nunca
//     continua na mesma invocação; ela só começa numa invocação SEGUINTE que reclama o Set já
//     em MATCHING (prova estrutural, não uma escolha deste núcleo — ver checkpoint_/close_ em
//     3955: checkpoint só é válido em PENDING/ACQUIRING, e NO_MORE_PAGES sempre libera a
//     lease).
//
//   Fase de MATCHING (status recebido de open_ é MATCHING):
//     ZERO chamadas à JustTCG (client é recebido mas nunca invocado neste ramo — a prova de
//     "retomar sem nova chamada externa quando status=MATCHING" é estrutural: o client só é
//     tocado dentro de runAcquisitionPhase()). Carrega TODO o staging + todas as cartas ativas
//     locais do Set, roda buildExternalNumberIndex()+classifyCardMatch() do núcleo P16.2
//     (_shared/pricing-justtcg-matching/mod.ts — reuso integral, nenhuma regra de matching
//     reimplementada aqui), persiste em lote via persistMatchingBatch() e fecha com
//     MATCHING_COMPLETE (ou TRANSIENT_ERROR se a leitura local ou a persistência falhar). A
//     RPC close_ deriva ela mesma, por SQL, se a cobertura está completa — este núcleo NUNCA
//     calcula nem afirma COMPLETE; só reporta o finalStatus que a RPC devolveu (que pode ser
//     COMPLETE ou RECONCILIATION_INCOMPLETE mesmo depois de MATCHING_COMPLETE ser enviado).
//
// Regras obrigatórias preservadas estruturalmente (pedido de Fabrício, 2026-08-26):
//   - NÃO cria pricing_product/pricing_observation — BootstrapPort não expõe nenhuma operação
//     nessas tabelas.
//   - NÃO altera o price dispatcher — nenhum import de _shared/pricing-justtcg-refresh além de
//     deadline.ts (utilitário puro, já compartilhado por precedente).
//   - NÃO duplica lógica do P16.2 — buildExternalNumberIndex/classifyCardMatch são importados
//     de ../pricing-justtcg-matching/mod.ts, nunca reescritos.
//   - Matching só acontece após aquisição completa — estrutural (ver acima: a mesma invocação
//     nunca faz as duas fases).
//   - Checkpoint só avança depois do staging persistido — a RPC checkpoint_ já garante isso
//     (INSERT antes de avançar acquisition_resume_offset); este núcleo só chama close_(NO_MORE
//     _PAGES) depois que o checkpoint_ da última página retornou true.
//   - Persistência idempotente — reaproveita decideMappingUpsert (P16.2) via a mesma decisão
//     implementada em SQL na RPC 3957 (nunca rebaixa CONFIRMED/REJECTED); identidades usam
//     ON CONFLICT DO NOTHING.
//   - Evita N+1 — 1 leitura de staging + 1 leitura de cartas locais + 1 chamada de persistência
//     em lote por Set, independente da quantidade de cartas.

import {
  hasExceededDeadline,
  WAVE_INTERNAL_DEADLINE_MS,
} from "../pricing-justtcg-refresh/deadline.ts";
import type { Clock } from "../pricing-justtcg-refresh/deadline.ts";
import {
  buildExternalNumberIndex,
  classifyCardMatch,
} from "../pricing-justtcg-matching/mod.ts";
import type { LocalCard } from "../pricing-justtcg-matching/mod.ts";
import {
  CARDS_PAGE_LIMIT,
  GAME_CODE,
  type JustTcgCard,
  type JustTcgClient,
} from "../pricing-justtcg/mod.ts";
import type {
  BootstrapPhaseOutcome,
  BootstrapPort,
  BootstrapRunStatus,
  PersistBootstrapRowInput,
  StagedCardInput,
} from "./bootstrap-port.ts";

// Teto de requisições por invocação — mesmo valor conservador de SET_REQUEST_BUDGET
// (set-refresh-core.ts) — a fase de aquisição de bootstrap tem o mesmo perfil de tráfego
// (1 Set por invocação, páginas de até 100 cartas).
export const BOOTSTRAP_REQUEST_BUDGET = 10;

// Mesma margem de segurança já validada em produção para o dispatcher de price-refresh
// (deadline.ts) — reexportado aqui só por conveniência de import único pelo chamador.
export const BOOTSTRAP_INTERNAL_DEADLINE_MS = WAVE_INTERNAL_DEADLINE_MS;

export type BootstrapExecutionResult =
  // Nenhum Set elegível agora — nenhum pricing_sync_run aberto.
  | { kind: "NO_WORK" }
  // Já existe outro CARD_SYNC/PRICE_REFRESH ativo para esta fonte (índices 3907/3926) —
  // nenhum pricing_sync_run aberto por este núcleo.
  | { kind: "SOURCE_BUSY" }
  // Lease perdida/expirada em pleno processamento — defensivo, nunca esperado com 1
  // invocação por vez; este núcleo para imediatamente, nunca chama close_.
  | { kind: "LEASE_LOST"; syncRunId: string }
  | {
    kind: "ACQUISITION_CLOSED";
    syncRunId: string;
    pricingSetMappingId: string;
    phaseOutcome: BootstrapPhaseOutcome;
    runStatus: BootstrapRunStatus;
    finalStatus: string;
    pagesProcessed: number;
    cardsStaged: number;
    requestsMade: number;
    rateLimitHits: number;
  }
  | {
    kind: "MATCHING_CLOSED";
    syncRunId: string;
    pricingSetMappingId: string;
    phaseOutcome: "MATCHING_COMPLETE" | "TRANSIENT_ERROR";
    runStatus: BootstrapRunStatus;
    finalStatus: string;
    cardsTotal: number;
    cardsSafe: number;
    cardsAmbiguous: number;
    cardsAbsent: number;
    mappingsInserted: number;
    mappingsUpgraded: number;
    mappingsNoop: number;
    identitiesCreated: number;
  };

// Mesma separação de responsabilidade de decideRunStatus (set-refresh-core.ts):
// p_phase_outcome governa o próximo estado operacional de pricing_set_bootstrap_state (já
// implementado na RPC), p_run_status governa só o status HISTÓRICO deste pricing_sync_run
// específico.
export function decideAcquisitionRunStatus(
  phaseOutcome: BootstrapPhaseOutcome,
): BootstrapRunStatus {
  switch (phaseOutcome) {
    case "AUTH_FAILURE":
      return "FAILED";
    case "TRANSIENT_ERROR":
    case "SET_TERMINAL_ERROR":
      return "COMPLETED_WITH_ERRORS";
    case "NO_MORE_PAGES":
    case "BUDGET_STOPPED":
    case "DEADLINE_STOPPED":
      return "COMPLETED";
    case "MATCHING_COMPLETE":
      // Nunca produzido pela fase de aquisição — presente só para exaustividade do union.
      return "COMPLETED";
  }
}

// P14.4.4/dedup pós-P14.4.5 já resolve duplicidade de external_card_id DENTRO do índice de
// matching (buildExternalNumberIndex) — mas a checkpoint_ RPC (3955) faz
// INSERT ... ON CONFLICT DO UPDATE a partir de um único jsonb_array_elements() por chamada, e
// o Postgres rejeita ("cannot affect row a second time") se o MESMO external_card_id aparecer
// duas vezes dentro do MESMO array de uma única invocação de INSERT. Uma página bruta da
// JustTCG poderia (teoricamente) repetir um id — dedupe aqui, ANTES de montar o payload da
// checkpoint_, evita esse erro de banco sem exigir nenhuma lógica adicional na RPC. Mantém a
// PRIMEIRA ocorrência (mesmo critério "não duplica o candidato" de buildExternalNumberIndex).
export function dedupeCardsForStaging(
  cards: readonly JustTcgCard[],
): JustTcgCard[] {
  const seen = new Set<string>();
  const result: JustTcgCard[] = [];
  for (const card of cards) {
    const id = String(card.id ?? "");
    if (!id || seen.has(id)) continue;
    seen.add(id);
    result.push(card);
  }
  return result;
}

async function runAcquisitionPhase(
  port: BootstrapPort,
  client: JustTcgClient,
  syncRunId: string,
  pricingSetMappingId: string,
  externalSetId: string,
  initialOffset: number,
  clock: Clock,
  startedAtMs: number,
): Promise<BootstrapExecutionResult> {
  let offset = initialOffset;
  let pagesProcessed = 0;
  let cardsStaged = 0;
  let phaseOutcome: BootstrapPhaseOutcome | null = null;
  let errorSummary: string | null = null;

  pageLoop: for (;;) {
    if (
      hasExceededDeadline(startedAtMs, clock, BOOTSTRAP_INTERNAL_DEADLINE_MS)
    ) {
      phaseOutcome = "DEADLINE_STOPPED";
      break pageLoop;
    }

    const pageResult = await client.get<{ data: JustTcgCard[] }>("/cards", {
      game: GAME_CODE,
      set: externalSetId,
      limit: String(CARDS_PAGE_LIMIT),
      offset: String(offset),
    });

    if (pageResult.status === "BUDGET_STOPPED") {
      phaseOutcome = "BUDGET_STOPPED";
      break pageLoop;
    }
    if (pageResult.status === "AUTH_FAILURE") {
      phaseOutcome = "AUTH_FAILURE";
      errorSummary = "JUSTTCG_AUTH_FAILURE";
      break pageLoop;
    }
    if (pageResult.status === "TECHNICAL_FAILURE") {
      // Mesmo critério de set-refresh-core.ts: 404 = Set não existe mais na JustTCG
      // (estrutural, SET_TERMINAL_ERROR); qualquer outro status é transitório.
      if (pageResult.httpStatus === 404) {
        phaseOutcome = "SET_TERMINAL_ERROR";
        errorSummary = "JUSTTCG_SET_NOT_FOUND_404";
      } else {
        phaseOutcome = "TRANSIENT_ERROR";
        errorSummary = "JUSTTCG_PAGE_FETCH_TECHNICAL_FAILURE";
      }
      break pageLoop;
    }

    // status === "SUCCESS"
    pagesProcessed++;
    const rawCards = pageResult.data?.data ?? [];
    const dedupedCards = dedupeCardsForStaging(rawCards);
    const stagedInput: StagedCardInput[] = dedupedCards.map((c) => ({
      externalCardId: String(c.id),
      number: c.number ?? null,
      name: c.name ?? null,
    }));
    cardsStaged += stagedInput.length;
    offset += CARDS_PAGE_LIMIT;

    // Checkpoint SEMPRE, mesmo com página vazia — a RPC (3955) exige ao menos 1 checkpoint
    // bem-sucedido (que transiciona PENDING->ACQUIRING) antes de aceitar NO_MORE_PAGES; um
    // Set sem nenhuma página externa (0 cartas) precisa desse checkpoint vazio para poder
    // fechar corretamente.
    const checkpointOk = await port.checkpointAcquisitionPage(
      syncRunId,
      offset,
      stagedInput,
    );
    if (!checkpointOk) {
      // Lease perdida/expirada — nunca chama close_ (o run não é mais nosso). Defensivo,
      // nunca esperado com 1 invocação por vez.
      return { kind: "LEASE_LOST", syncRunId };
    }

    const hasMore = pageResult.meta?.hasMore ??
      rawCards.length === CARDS_PAGE_LIMIT;
    if (!hasMore || rawCards.length === 0) {
      phaseOutcome = "NO_MORE_PAGES";
      break pageLoop;
    }
    // Senão, continua — próxima iteração reavalia deadline antes do próximo fetch.
  }

  const finalPhaseOutcome = phaseOutcome as BootstrapPhaseOutcome; // todo caminho de saída (exceto LEASE_LOST, já retornado acima) atribui um valor
  const runStatus = decideAcquisitionRunStatus(finalPhaseOutcome);
  const closeResult = await port.closeAttempt(
    syncRunId,
    finalPhaseOutcome,
    runStatus,
    client.requestsMade,
    client.rateLimitHits,
    errorSummary,
  );

  return {
    kind: "ACQUISITION_CLOSED",
    syncRunId,
    pricingSetMappingId,
    phaseOutcome: finalPhaseOutcome,
    runStatus,
    finalStatus: closeResult.finalStatus,
    pagesProcessed,
    cardsStaged,
    requestsMade: client.requestsMade,
    rateLimitHits: client.rateLimitHits,
  };
}

async function runMatchingPhase(
  port: BootstrapPort,
  syncRunId: string,
  pricingSetMappingId: string,
  cardSetId: string,
  externalSetId: string,
  pricingSourceId: string,
): Promise<BootstrapExecutionResult> {
  // Leitura local (staging completo + cartas ativas do Set) — UMA vez, nunca por carta.
  // Falha aqui significa zero trabalho útil tentado nesta invocação: fecha como
  // TRANSIENT_ERROR/COMPLETED_WITH_ERRORS sem inventar nenhum dado.
  let stagingRows: Awaited<ReturnType<BootstrapPort["loadFullStaging"]>>;
  let localCards: Awaited<ReturnType<BootstrapPort["loadLocalActiveCards"]>>;
  try {
    [stagingRows, localCards] = await Promise.all([
      port.loadFullStaging(pricingSetMappingId),
      port.loadLocalActiveCards(cardSetId),
    ]);
  } catch {
    const closeResult = await port.closeAttempt(
      syncRunId,
      "TRANSIENT_ERROR",
      "FAILED",
      0,
      0,
      "BOOTSTRAP_LOCAL_STAGING_OR_CARD_READ_FAILED",
    );
    return {
      kind: "MATCHING_CLOSED",
      syncRunId,
      pricingSetMappingId,
      phaseOutcome: "TRANSIENT_ERROR",
      runStatus: "FAILED",
      finalStatus: closeResult.finalStatus,
      cardsTotal: 0,
      cardsSafe: 0,
      cardsAmbiguous: 0,
      cardsAbsent: 0,
      mappingsInserted: 0,
      mappingsUpgraded: 0,
      mappingsNoop: 0,
      identitiesCreated: 0,
    };
  }

  // Reuso INTEGRAL do núcleo P16.2 — externalCards é reconstruído a partir do staging
  // (id/name/number, os únicos 3 campos que buildExternalNumberIndex()/classifyCardMatch()
  // leem de um JustTcgCard — ver card-matching.ts) sem nenhuma regra de matching duplicada.
  const externalCards: JustTcgCard[] = stagingRows.map((row) => ({
    id: row.externalCardId,
    name: row.externalName,
    number: row.externalNumber ?? undefined,
    variants: [],
  }));
  const externalIndex = buildExternalNumberIndex(externalCards);

  const rows: PersistBootstrapRowInput[] = [];
  let cardsSafe = 0;
  let cardsAmbiguous = 0;
  let cardsAbsent = 0;
  for (const local of localCards) {
    const localCard: LocalCard = {
      card_id: local.cardId,
      name: local.name,
      collector_number: local.collectorNumber,
      collector_total: local.collectorTotal,
    };
    const result = classifyCardMatch(localCard, externalIndex, externalSetId);
    if (result.classification === "SAFE") cardsSafe++;
    else if (result.classification === "AMBIGUOUS") cardsAmbiguous++;
    else cardsAbsent++;

    rows.push({
      cardId: local.cardId,
      classification: result.classification,
      externalCardId: result.matched ? String(result.matched.id) : null,
      externalCardName: result.matched ? result.matched.name : null,
      matchMethod: result.method,
      matchEvidence: result.evidence,
    });
  }

  const persistResult = await port.persistMatchingBatch(
    pricingSourceId,
    syncRunId,
    rows,
  );
  if (!persistResult.ok) {
    const closeResult = await port.closeAttempt(
      syncRunId,
      "TRANSIENT_ERROR",
      "COMPLETED_WITH_ERRORS",
      0,
      0,
      "BOOTSTRAP_MATCHING_PERSIST_FAILED",
    );
    return {
      kind: "MATCHING_CLOSED",
      syncRunId,
      pricingSetMappingId,
      phaseOutcome: "TRANSIENT_ERROR",
      runStatus: "COMPLETED_WITH_ERRORS",
      finalStatus: closeResult.finalStatus,
      cardsTotal: localCards.length,
      cardsSafe,
      cardsAmbiguous,
      cardsAbsent,
      mappingsInserted: 0,
      mappingsUpgraded: 0,
      mappingsNoop: 0,
      identitiesCreated: 0,
    };
  }

  const mappingsInserted =
    persistResult.rows.filter((r) => r.action === "INSERTED").length;
  const mappingsUpgraded =
    persistResult.rows.filter((r) => r.action === "UPGRADED").length;
  const mappingsNoop =
    persistResult.rows.filter((r) => r.action.startsWith("NOOP")).length;
  const identitiesCreated =
    persistResult.rows.filter((r) => r.identityCreated).length;

  // ZERO chamadas à JustTCG nesta fase -> requestsMade/rateLimitHits sempre 0,0 aqui, nunca
  // lidos de um client (esta função não recebe nenhum JustTcgClient — prova estrutural, não
  // apenas comportamental). Autoria: persistMatchingBatch() acima já recebeu syncRunId — o
  // adapter usa esse valor como confirmed_sync_run_id (autoria automatizada real, nunca um ator
  // fictício — ver migration 3957/3958).
  const closeResult = await port.closeAttempt(
    syncRunId,
    "MATCHING_COMPLETE",
    "COMPLETED",
    0,
    0,
    null,
  );

  return {
    kind: "MATCHING_CLOSED",
    syncRunId,
    pricingSetMappingId,
    phaseOutcome: "MATCHING_COMPLETE",
    runStatus: "COMPLETED",
    finalStatus: closeResult.finalStatus,
    cardsTotal: localCards.length,
    cardsSafe,
    cardsAmbiguous,
    cardsAbsent,
    mappingsInserted,
    mappingsUpgraded,
    mappingsNoop,
    identitiesCreated,
  };
}

export async function executeBootstrapAttempt(
  port: BootstrapPort,
  client: JustTcgClient,
  pricingSourceId: string,
  clock: Clock = Date.now,
): Promise<BootstrapExecutionResult> {
  const startedAtMs = clock();

  const openResult = await port.openAttempt(pricingSourceId);
  if (openResult.outcome === "NO_CANDIDATE") {
    return { kind: "NO_WORK" };
  }
  if (openResult.outcome === "SOURCE_BUSY") {
    return { kind: "SOURCE_BUSY" };
  }

  const {
    syncRunId,
    pricingSetMappingId,
    cardSetId,
    externalSetId,
    status,
    acquisitionResumeOffset,
  } = openResult;

  if (status === "MATCHING") {
    // Prova estrutural de "nunca refaz aquisição quando já em MATCHING": `client` nunca é
    // referenciado dentro de runMatchingPhase() (a assinatura da função nem o recebe).
    return await runMatchingPhase(
      port,
      syncRunId,
      pricingSetMappingId,
      cardSetId,
      externalSetId,
      pricingSourceId,
    );
  }

  // status === "PENDING" || status === "ACQUIRING"
  return await runAcquisitionPhase(
    port,
    client,
    syncRunId,
    pricingSetMappingId,
    externalSetId,
    acquisitionResumeOffset,
    clock,
    startedAtMs,
  );
}
