// Project Mimikyu — supabase/functions/_shared/pricing-justtcg-refresh/port.ts
// Porta funcional do núcleo de refresh diário JustTCG — Incremento de Atualização Diária
// JustTCG (2026-08-21), item B.
//
// Mesma disciplina de porta funcional já usada em
// supabase/functions/_shared/pricing-ptax/run-lifecycle.ts (PtaxSyncRunPort): o núcleo
// (core.ts) depende SOMENTE desta interface — operações de domínio, nunca um tipo que
// reproduza a API fluente do PostgREST (.from().select().eq()...). Quem implementa a
// porta sobre o SupabaseClient real é supabase-adapter.ts, construído uma única vez pelo
// chamador (Edge Function). Isso torna core.ts 100% testável offline com um fake da
// porta, sem nenhum SupabaseClient real nem rede.
//
// Superfície de escrita deliberadamente estreita — reflete as regras fechadas por
// Fabrício:
//   11. Nunca escreve em pricing_set_mapping, pricing_card_mapping ou
//       pricing_source_card_identity — a porta simplesmente NÃO EXPÕE nenhuma operação de
//       escrita nessas três tabelas; a garantia é estrutural (impossível de violar por
//       acidente a partir de core.ts), não apenas disciplina de código.
//   13. Produtos resolvidos por identidade + external_product_id — insertProducts() é
//       INSERT-only (nunca UPDATE de um produto já existente).
//   14. Observação nova só quando o preço muda — insertObservations() é INSERT-only
//       (pricing_observation nunca é UPDATE/DELETE por este núcleo).

import type { RefreshSetCandidate } from "./wave-plan.ts";
import type { ConfirmedIdentityRole } from "./extract.ts";

export type { RefreshSetCandidate };

export type RefreshIdentityRow = {
  identityId: string;
  externalCardId: string;
  identityRole: ConfirmedIdentityRole;
  // pricing_product.pricing_card_mapping_id é NOT NULL no schema físico — para
  // identidades ALTERNATE (não só PRIMARY), este valor é o mesmo pricing_card_mapping_id
  // já gravado na própria linha de pricing_source_card_identity no momento da confirmação
  // original (identidades PRIMARY e ALTERNATE da mesma carta local compartilham o mesmo
  // pricing_card_mapping_id — um por (card_id, pricing_source_id)). Nunca resolvido por
  // uma segunda leitura: já vem junto na leitura da identidade.
  pricingCardMappingId: string;
};

export type ExistingProductRow = {
  productId: string;
  pricingSourceCardIdentityId: string;
  externalProductId: string;
};

export type InsertProductInput = {
  pricingCardMappingId: string;
  pricingSourceCardIdentityId: string;
  externalProductId: string;
  sourcePrintingLabel: string;
};

export type InsertedProductRow = {
  productId: string;
  pricingSourceCardIdentityId: string;
  externalProductId: string;
};

export type InsertProductsResult =
  | { ok: true; inserted: InsertedProductRow[] }
  | { ok: false; message: string | null };

export type LatestObservationKey = { productId: string; conditionId: string };

export type LatestObservationRow = {
  productId: string;
  conditionId: string;
  price: number;
  observedAt: string;
};

export type InsertObservationInput = {
  productId: string;
  conditionId: string;
  syncRunId: string;
  price: number;
  observedAt: string;
  rawPayload: unknown;
};

export type InsertObservationsResult =
  | { ok: true }
  | { ok: false; message: string | null };

// ============================================================================
// Ciclo de vida de pricing_sync_run/pricing_sync_run_call para PRICE_REFRESH — mesmo
// contrato de SyncRunTrigger/InsertSyncRunResult de _shared/pricing-ptax/run-lifecycle.ts,
// mas SEMPRE triggered_by=SCHEDULED/confirmed_by=NULL (regra 8 — nunca um caminho MANUAL
// nesta porta; a execução manual, se um dia existir, teria sua própria porta/decisão
// explícita, fora do escopo desta rodada).
// ============================================================================

export type InsertPriceRefreshRunResult =
  | { outcome: "STARTED"; syncRunId: string }
  | { outcome: "CONCURRENT_CONFLICT" }
  | { outcome: "OTHER_ERROR"; message: string | null };

export type FinalRefreshRunStatus =
  | "COMPLETED"
  | "COMPLETED_WITH_ERRORS"
  | "FAILED";

export type UpdateSyncRunPatch = {
  status: FinalRefreshRunStatus;
  errorSummary: string | null;
  requestsMade: number;
  rateLimitHits: number;
};

export type PriceRefreshCallLogEntry = {
  sequence_number: number;
  endpoint: string;
  http_status_code: number | null;
  outcome: "SUCCESS" | "TECHNICAL_FAILURE" | "BUDGET_STOPPED";
  error_detail: string | null;
  api_requests_remaining: number | null;
};

export interface RefreshPort {
  // ---- Leitura — nunca escreve nada. --------------------------------------------
  // Só Sets com >=1 identidade PRIMARY/ALTERNATE CONFIRMED da fonte informada — PENDING/
  // NOT_FOUND/REJECTED/ALIAS já filtrados na origem (regra 17).
  listRefreshCandidateSets(
    pricingSourceId: string,
  ): Promise<RefreshSetCandidate[]>;
  // Identidades PRIMARY/ALTERNATE CONFIRMED de um Set específico — mesmo filtro acima,
  // por Set (usado por core.ts ao processar cada onda).
  listConfirmedIdentitiesForSet(
    pricingSourceId: string,
    cardSetId: string,
  ): Promise<RefreshIdentityRow[]>;
  getConditionMap(pricingSourceId: string): Promise<Map<string, string>>;
  findExistingProducts(
    identityIds: readonly string[],
  ): Promise<ExistingProductRow[]>;
  findLatestObservations(
    keys: readonly LatestObservationKey[],
  ): Promise<LatestObservationRow[]>;

  // ---- Escrita — só pricing_product (INSERT-only) e pricing_observation
  // (INSERT-only). Nunca pricing_set_mapping/pricing_card_mapping/
  // pricing_source_card_identity (regra 11 — superfície estrutural, ver cabeçalho). ------
  insertProducts(
    rows: readonly InsertProductInput[],
  ): Promise<InsertProductsResult>;
  insertObservations(
    rows: readonly InsertObservationInput[],
  ): Promise<InsertObservationsResult>;

  // ---- Ciclo de vida do run PRICE_REFRESH. --------------------------------------
  insertPriceRefreshRun(
    pricingSourceId: string,
  ): Promise<InsertPriceRefreshRunResult>;
  insertSyncRunCalls(
    syncRunId: string,
    callLog: readonly PriceRefreshCallLogEntry[],
  ): Promise<InsertObservationsResult>;
  updateSyncRun(syncRunId: string, patch: UpdateSyncRunPatch): Promise<void>;
}
