// Project Mimikyu — supabase/functions/_shared/pricing-justtcg-bootstrap/bootstrap-port.ts
// Porta funcional do executor de bootstrap de Set (P16.5.2/P16.5.3, 2026-08-26) — implementa
// o ciclo de vida de pricing_sync_run/pricing_set_bootstrap_state EXCLUSIVAMENTE via as 3
// RPCs da migration 3955 (open_/checkpoint_/close_pricing_set_bootstrap_attempt, PROPOSTAS
// nesta rodada, testadas em BEGIN/ROLLBACK, aguardando autorização de aplicação) e via a RPC
// persist_pricing_bootstrap_card_batch (migration 3958, também PROPOSTA nesta rodada — depende
// da coluna confirmed_sync_run_id criada pela migration 3957, autoria relacional).
//
// Mesmo padrão de _shared/pricing-justtcg-refresh/set-refresh-port.ts: uma interface mínima,
// só com os acessos que bootstrap-core.ts realmente precisa, para permitir testar o núcleo
// 100% offline com um fake em memória (ver .test.ts). Nenhuma escrita em
// pricing_set_mapping/pricing_source (regra estrutural — esta porta simplesmente não expõe
// nenhuma operação nessas tabelas).

export type OpenBootstrapAttemptResult =
  | { outcome: "NO_CANDIDATE" }
  | { outcome: "SOURCE_BUSY" }
  | {
    outcome: "CLAIMED";
    syncRunId: string;
    pricingSetMappingId: string;
    cardSetId: string;
    externalSetId: string;
    // Estado ANTES desta chamada (open_ nunca muda status — só lease/last_started_at). É
    // este campo que decide, em bootstrap-core.ts, se a invocação faz aquisição (PENDING/
    // ACQUIRING) ou pula direto para matching sem nenhuma chamada externa (MATCHING) — a
    // prova estrutural de "retomar sem nova chamada externa quando status=MATCHING" exigida
    // por Fabrício.
    status: "PENDING" | "ACQUIRING" | "MATCHING";
    acquisitionResumeOffset: number;
  };

// checkpoint_pricing_set_bootstrap_acquisition_page — true = lease ainda válida e staging
// persistido; false = lease perdida/expirada (ou status fora de PENDING/ACQUIRING — mesmo
// vocabulário booleano simples devolvido pela RPC, 3955).
export type CheckpointAcquisitionResult = boolean;

// Payload de UMA página já buscada da JustTCG, já deduplicada por external_card_id (ver
// dedupeCardsForStaging em bootstrap-core.ts) — o `number`/`name` brutos são preservados sem
// normalização (a normalização é responsabilidade do núcleo P16.2 na fase de matching, nunca
// da fase de aquisição).
export type StagedCardInput = {
  externalCardId: string;
  number: string | null;
  name: string | null;
};

// Vocabulário EXATO de p_phase_outcome aceito por close_pricing_set_bootstrap_attempt (3955)
// — reexportado aqui em vez de redeclarado em outro lugar.
export type BootstrapPhaseOutcome =
  | "NO_MORE_PAGES"
  | "BUDGET_STOPPED"
  | "DEADLINE_STOPPED"
  | "MATCHING_COMPLETE"
  | "TRANSIENT_ERROR"
  | "SET_TERMINAL_ERROR"
  | "AUTH_FAILURE";

// p_run_status não é validado pela RPC (mesma decisão de design de set-refresh-port.ts) — só
// os 3 valores que bootstrap-core.ts realmente decide (nunca RECEIVED/CANCELLED aqui).
export type BootstrapRunStatus =
  | "COMPLETED"
  | "COMPLETED_WITH_ERRORS"
  | "FAILED";

export type CloseBootstrapAttemptResult = {
  // Espelha exatamente o texto devolvido pela RPC (MATCHING | PENDING | ACQUIRING | COMPLETE
  // | PAUSED | RECONCILIATION_INCOMPLETE | INVALID_TRANSITION | LEASE_INVALID) — nunca
  // reinterpretado aqui.
  finalStatus: string;
};

// Uma linha do staging já persistido (pricing_set_bootstrap_card_staging, 3954) — carregada
// integralmente só quando a fase de matching começa (status=MATCHING), nunca durante a
// aquisição.
export type StagedCardRow = {
  externalCardId: string;
  externalNumber: string | null;
  externalName: string;
};

// Uma carta local ativa do Set — mesmo formato de LocalCard exigido por
// buildExternalNumberIndex()/classifyCardMatch() (núcleo P16.2), só com nomes de campo
// idiomáticos no port (a conversão para o formato LocalCard acontece em bootstrap-core.ts).
export type LocalActiveCard = {
  cardId: string;
  name: string;
  collectorNumber: string;
  collectorTotal: number | null;
};

// Uma linha de entrada para persist_pricing_bootstrap_card_batch — já classificada pelo
// núcleo P16.2 (classification é literalmente CardMatchClassification de
// _shared/pricing-justtcg-matching/types.ts, nunca reinterpretada aqui).
export type PersistBootstrapRowInput = {
  cardId: string;
  classification: "SAFE" | "AMBIGUOUS" | "ABSENT";
  externalCardId: string | null;
  externalCardName: string | null;
  matchMethod: string;
  matchEvidence: Record<string, unknown>;
};

export type PersistBootstrapRowResult = {
  cardId: string;
  // INSERTED | UPGRADED | NOOP_SAME_STATUS | NOOP_KEEP_PROTECTED_STATUS — mesmo vocabulário
  // devolvido pela RPC (3957), nunca reinterpretado aqui.
  action: string;
  finalMatchStatus: string;
  identityCreated: boolean;
};

export type PersistBootstrapBatchResult =
  | { ok: true; rows: PersistBootstrapRowResult[] }
  | { ok: false };

export interface BootstrapPort {
  // ---- Ciclo de vida do run CARD_SYNC por Set — RPCs 3955, único escritor de
  // pricing_sync_run/pricing_set_bootstrap_state a partir deste núcleo. ------
  openAttempt(pricingSourceId: string): Promise<OpenBootstrapAttemptResult>;
  checkpointAcquisitionPage(
    syncRunId: string,
    newResumeOffset: number,
    stagedCards: readonly StagedCardInput[],
  ): Promise<CheckpointAcquisitionResult>;
  closeAttempt(
    syncRunId: string,
    phaseOutcome: BootstrapPhaseOutcome,
    runStatus: BootstrapRunStatus,
    requestsMade: number,
    rateLimitHits: number,
    errorSummary: string | null,
  ): Promise<CloseBootstrapAttemptResult>;

  // ---- Leitura — só usada na fase de matching (status=MATCHING), nunca durante aquisição.
  loadFullStaging(pricingSetMappingId: string): Promise<StagedCardRow[]>;
  loadLocalActiveCards(cardSetId: string): Promise<LocalActiveCard[]>;

  // ---- Escrita — só pricing_card_mapping e pricing_source_card_identity (RPC
  // persist_pricing_bootstrap_card_batch, 3958) — nunca pricing_product/pricing_observation
  // (regra estrutural: esta porta não expõe nenhuma operação nessas duas tabelas).
  // syncRunId é repassado para a RPC como p_confirmed_sync_run_id — autoria automatizada real
  // (aponta para o próprio pricing_sync_run que está chamando), nunca um ator fictício (ver
  // migration 3957: confirmed_by e confirmed_sync_run_id são mutuamente exclusivos).
  persistMatchingBatch(
    pricingSourceId: string,
    syncRunId: string,
    rows: readonly PersistBootstrapRowInput[],
  ): Promise<PersistBootstrapBatchResult>;
}
