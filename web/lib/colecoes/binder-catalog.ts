/**
 * Fichário Digital × Catálogo — novidades do Catálogo Editorial no fichário
 * de uma coleção Master Set (BINDER-CATALOG-RECONCILIATION-FRONTEND-01).
 *
 * Camada pura: leitura e validação dos contratos LIVE 5265/5266 (aplicados
 * em 2026-10-25, ledger 20261025145358/145504), classificação de falhas e
 * textos na linguagem do colecionador. O banco é a autoridade: recalcula o
 * plano sob a trava do fichário e recusa se ele mudou (`plan_token`).
 *
 *   get_my_binder_catalog_novelties(p_collection_id)
 *     → eligible, reason, novelty_count, item_key, card_id, variant_type_id,
 *       collector_number, card_name, variant_type_code, variant_type_name,
 *       born_at, placed_in_binder
 *   preview_my_binder_catalog_reconciliation(p_collection_id, p_keys)
 *     → linha HEADER + linhas ITEM (destino, âncora, cadeia, barreira…)
 *   apply_my_binder_catalog_reconciliation(p_collection_id, p_keys,
 *       p_plan_token, p_confirm_cross_page, p_confirm_add_page)
 *     → outcome APPLIED | ALREADY_APPLIED | NOTHING_TO_DO + contagens
 *
 * Regras que a interface preserva (5264): só MASTER_SET; Pokédex nunca entra;
 * novidade = posição nascida depois do marco de participação, sem reserva
 * desta coleção e ainda não incorporada. Uma novidade incorporada e depois
 * liberada NÃO volta (W5); uma reserva liberada de posição antiga também não
 * é novidade (regra 5) — a interface nunca "restaura" reservas.
 */

/** Limites da 5264 (`c_item_limit`, `c_row_limit`). O banco é quem decide. */
export const CATALOG_ITEM_LIMIT = 100;
export const CATALOG_ROW_LIMIT = 500;

export const CATALOG_PLAN_TOKEN = /^rc1:[0-9a-f]{64}$/;
const ITEM_KEY = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}:([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|\*)$/;

export function isCatalogPlanToken(value: unknown): value is string {
  return typeof value === "string" && CATALOG_PLAN_TOKEN.test(value);
}

export function isCatalogItemKey(value: unknown): value is string {
  return typeof value === "string" && ITEM_KEY.test(value);
}

/**
 * Leitura só faz sentido em fichário existente de coleção Master Set ativa.
 * Pokédex, Set, Livre e arquivada nem chamam a RPC (requisitos 2 e 3). O
 * banco ainda decide o resto (dona Pokédex, referências de espécie, marco).
 */
export function mayHaveCatalogNovelties(header: { hasBinder: boolean; kind: string; editable: boolean }): boolean {
  return header.hasBinder && header.kind === "MASTER_SET" && header.editable;
}

// ---------------------------------------------------------------------------
// Aviso de novidades (5265 get_my_binder_catalog_novelties)
// ---------------------------------------------------------------------------

export type CatalogIneligibleReason =
  | "NOT_MASTER_SET"
  | "BINDER_NOT_FOUND"
  | "BINDER_OWNER_POKEDEX"
  | "SPECIES_REFERENCES_PRESENT"
  | "COLLECTION_REFERENCE_MISSING"
  | "COLLECTION_ARCHIVED"
  | "MARKER_MISSING"
  | "OWNERSHIP_MISMATCH"
  | "COLLECTION_NOT_FOUND"
  | "OTHER";

const INELIGIBLE = new Set<string>([
  "NOT_MASTER_SET",
  "BINDER_NOT_FOUND",
  "BINDER_OWNER_POKEDEX",
  "SPECIES_REFERENCES_PRESENT",
  "COLLECTION_REFERENCE_MISSING",
  "COLLECTION_ARCHIVED",
  "MARKER_MISSING",
  "OWNERSHIP_MISMATCH",
  "COLLECTION_NOT_FOUND",
]);

export type CatalogNovelty = {
  itemKey: string;
  cardId: string;
  /** `null` = posição genérica da carta (sem acabamento). */
  variantTypeId: string | null;
  collectorNumber: string | null;
  cardName: string;
  variantTypeCode: string | null;
  variantTypeName: string | null;
  bornAt: string | null;
  /** Já há exemplar desta coleção dessa posição em algum bolso (W6). */
  placedInBinder: boolean;
};

export type CatalogNoveltyState =
  | { eligible: false; reason: CatalogIneligibleReason }
  | { eligible: true; count: number; items: CatalogNovelty[] };

function str(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function int(value: unknown): number | null {
  const n = typeof value === "number" ? value : typeof value === "string" && value.trim() !== "" ? Number(value) : Number.NaN;
  return Number.isInteger(n) ? n : null;
}

function bool(value: unknown): boolean | null {
  return typeof value === "boolean" ? value : null;
}

/** Converte o retorno do aviso — `null` quando o formato não bate (nunca adivinha). */
export function parseCatalogNovelties(data: unknown): CatalogNoveltyState | null {
  if (!Array.isArray(data) || data.length === 0) return null;
  const rows = data as Record<string, unknown>[];
  const first = rows[0];
  if (!first || typeof first !== "object") return null;
  const eligible = bool(first.eligible);
  if (eligible === null) return null;
  if (!eligible) {
    if (rows.length !== 1) return null;
    const reason = str(first.reason);
    return { eligible: false, reason: reason && INELIGIBLE.has(reason) ? (reason as CatalogIneligibleReason) : "OTHER" };
  }
  const count = int(first.novelty_count);
  if (count === null || count < 0) return null;
  if (count === 0) return rows.length === 1 && first.item_key == null ? { eligible: true, count: 0, items: [] } : null;
  if (rows.length !== count) return null;
  const items: CatalogNovelty[] = [];
  const seen = new Set<string>();
  for (const r of rows) {
    if (!r || typeof r !== "object" || r.eligible !== true || int(r.novelty_count) !== count) return null;
    const itemKey = str(r.item_key);
    const cardId = str(r.card_id);
    if (!isCatalogItemKey(itemKey) || !cardId || !itemKey.startsWith(`${cardId}:`) || seen.has(itemKey)) return null;
    const variantTypeId = str(r.variant_type_id);
    if (itemKey !== `${cardId}:${variantTypeId ?? "*"}`) return null;
    seen.add(itemKey);
    items.push({
      itemKey,
      cardId,
      variantTypeId,
      collectorNumber: str(r.collector_number),
      cardName: str(r.card_name) ?? "Carta",
      variantTypeCode: str(r.variant_type_code),
      variantTypeName: str(r.variant_type_name),
      bornAt: str(r.born_at),
      placedInBinder: r.placed_in_binder === true,
    });
  }
  return { eligible: true, count, items };
}

/** "Chi-Yu · 059 · Holo Reversa" — nunca ids. */
export function noveltyLabel(item: Pick<CatalogNovelty, "cardName" | "collectorNumber" | "variantTypeName">): string {
  return [item.cardName, item.collectorNumber, item.variantTypeName].filter((part): part is string => Boolean(part)).join(" · ");
}

/** Contagem que aparece no aviso: só quando elegível e com novidade. */
export function noveltyBadgeCount(state: CatalogNoveltyState | null): number {
  return state && state.eligible ? state.count : 0;
}

// ---------------------------------------------------------------------------
// Prévia (5265 preview_my_binder_catalog_reconciliation)
// ---------------------------------------------------------------------------

export type CatalogOutcome = "READY" | "BLOCKED" | "NEEDS_REVIEW" | "NO_ANCHOR" | "OVER_LIMIT" | "NOTHING_TO_DO" | "NOT_ELIGIBLE";
const OUTCOMES = new Set<string>(["READY", "BLOCKED", "NEEDS_REVIEW", "NO_ANCHOR", "OVER_LIMIT", "NOTHING_TO_DO", "NOT_ELIGIBLE"]);

export type CatalogItemKind =
  | "IN_PLACE"
  | "RESERVE_PLACED"
  | "SHIFT"
  | "UPGRADE_RESERVATION"
  | "BLOCKED"
  | "REVIEW_REQUIRED"
  | "OUT_OF_ORDER"
  | "NO_ANCHOR"
  | "NOT_EVALUATED";
const KINDS = new Set<string>(["IN_PLACE", "RESERVE_PLACED", "SHIFT", "UPGRADE_RESERVATION", "BLOCKED", "REVIEW_REQUIRED", "OUT_OF_ORDER", "NO_ANCHOR", "NOT_EVALUATED"]);
const EXECUTABLE_KINDS = new Set<CatalogItemKind>(["IN_PLACE", "RESERVE_PLACED", "SHIFT", "UPGRADE_RESERVATION"]);

export type CatalogBarrierKind = "LOCKED" | "REGION" | "PLACED_OUT_OF_ORDER" | "GENERIC_RESERVATION";
const BARRIERS = new Set<string>(["LOCKED", "REGION", "PLACED_OUT_OF_ORDER", "GENERIC_RESERVATION"]);

export type PocketPosition = { page: number; row: number; column: number };

export type CatalogPlanItem = {
  step: number;
  itemKey: string;
  cardId: string;
  variantTypeId: string | null;
  kind: CatalogItemKind;
  /** Bolso que recebe a reserva (nulo quando o item não é executável). */
  target: PocketPosition | null;
  /** Último bolso da cadeia que anda (só SHIFT). */
  end: PocketPosition | null;
  /** Posição vizinha que serviu de referência. */
  anchor: PocketPosition | null;
  barrier: (PocketPosition & { kind: CatalogBarrierKind }) | null;
  pocketsMoved: number;
  rowsMoved: number;
  otherReservesMoved: number;
  crossesPage: boolean;
  addsPage: boolean;
};

export type CatalogPreview = {
  outcome: CatalogOutcome;
  reason: string | null;
  totalItems: number;
  totalRowsMoved: number;
  rowLimit: number;
  itemLimit: number;
  requiresCrossPage: boolean;
  requiresAddPage: boolean;
  pagesAdded: number;
  addedPageNumbers: number[];
  capacityBefore: number | null;
  capacityAfter: number | null;
  freePocketsAfter: number | null;
  planToken: string | null;
  items: CatalogPlanItem[];
};

function position(page: unknown, row: unknown, column: unknown): PocketPosition | null {
  const p = int(page);
  const r = int(row);
  const c = int(column);
  return p !== null && r !== null && c !== null ? { page: p, row: r, column: c } : null;
}

/** Converte HEADER + ITEMs da prévia — `null` quando o formato não bate. */
export function parseCatalogPreview(data: unknown): CatalogPreview | null {
  if (!Array.isArray(data) || data.length === 0) return null;
  const rows = data as Record<string, unknown>[];
  const headers = rows.filter((r) => r && typeof r === "object" && r.row_kind === "HEADER");
  if (headers.length !== 1) return null;
  const h = headers[0]!;
  const outcome = str(h.outcome);
  if (!outcome || !OUTCOMES.has(outcome)) return null;
  const planToken = str(h.plan_token);
  if (planToken !== null && !isCatalogPlanToken(planToken)) return null;
  // Só READY é executável — e precisa de token. Os demais podem ter token (BLOCKED, NEEDS_REVIEW…), mas não liberam a aplicação.
  if (outcome === "READY" && !planToken) return null;
  const totalItems = int(h.total_items) ?? 0;

  const items: CatalogPlanItem[] = [];
  for (const r of rows) {
    if (!r || typeof r !== "object") return null;
    if (r.row_kind === "HEADER") continue;
    if (r.row_kind !== "ITEM") return null;
    const kind = str(r.kind);
    const itemKey = str(r.item_key);
    const cardId = str(r.card_id);
    const step = int(r.step_no);
    if (!kind || !KINDS.has(kind) || !isCatalogItemKey(itemKey) || !cardId || step === null) return null;
    const barrierKind = str(r.barrier_kind);
    const barrierPos = position(r.barrier_page, r.barrier_row, r.barrier_column);
    const target = position(r.target_page, r.target_row, r.target_column);
    if (EXECUTABLE_KINDS.has(kind as CatalogItemKind) && !target) return null;
    items.push({
      step,
      itemKey,
      cardId,
      variantTypeId: str(r.variant_type_id),
      kind: kind as CatalogItemKind,
      target,
      end: position(r.end_page, r.end_row, r.end_column),
      anchor: position(r.anchor_page, r.anchor_row, r.anchor_column),
      barrier: barrierPos && barrierKind && BARRIERS.has(barrierKind) ? { ...barrierPos, kind: barrierKind as CatalogBarrierKind } : null,
      pocketsMoved: int(r.pockets_moved) ?? 0,
      rowsMoved: int(r.rows_moved) ?? 0,
      otherReservesMoved: int(r.other_reserves_moved) ?? 0,
      crossesPage: r.crosses_page === true,
      addsPage: r.adds_page === true,
    });
  }
  items.sort((a, b) => a.step - b.step);
  if (outcome === "READY" && (items.length !== totalItems || items.some((i) => !EXECUTABLE_KINDS.has(i.kind)))) return null;
  const added = Array.isArray(h.added_page_numbers) ? h.added_page_numbers.map(int) : [];
  if (added.some((n) => n === null)) return null;

  return {
    outcome: outcome as CatalogOutcome,
    reason: str(h.reason),
    totalItems,
    totalRowsMoved: int(h.total_rows_moved) ?? 0,
    rowLimit: int(h.row_limit) ?? CATALOG_ROW_LIMIT,
    itemLimit: int(h.item_limit) ?? CATALOG_ITEM_LIMIT,
    requiresCrossPage: h.requires_cross_page === true,
    requiresAddPage: h.requires_add_page === true,
    pagesAdded: int(h.pages_added) ?? 0,
    addedPageNumbers: added as number[],
    capacityBefore: int(h.capacity_before),
    capacityAfter: int(h.capacity_after),
    freePocketsAfter: int(h.free_pockets_after),
    planToken,
    items,
  };
}

/** Páginas que a operação toca (destinos, cadeias e páginas novas), em ordem. */
export function affectedPages(preview: Pick<CatalogPreview, "items" | "addedPageNumbers">): number[] {
  const pages = new Set<number>(preview.addedPageNumbers);
  for (const item of preview.items) {
    if (!EXECUTABLE_KINDS.has(item.kind)) continue;
    if (item.target) pages.add(item.target.page);
    if (item.kind === "SHIFT" && item.target && item.end) for (let p = item.target.page; p <= item.end.page; p += 1) pages.add(p);
  }
  return [...pages].sort((a, b) => a - b);
}

export type CatalogConfirmations = { crossPage: boolean; addPage: boolean };

/** Confirmações extras que a prévia exige (além do "Incorporar"). */
export function requiredConfirmations(preview: Pick<CatalogPreview, "requiresCrossPage" | "requiresAddPage">): CatalogConfirmations {
  return { crossPage: preview.requiresCrossPage, addPage: preview.requiresAddPage };
}

/** O botão de aplicar só acende com prévia READY, token e todas as confirmações exigidas marcadas. */
export function canApplyPreview(preview: CatalogPreview | null, confirmed: CatalogConfirmations): boolean {
  if (!preview || preview.outcome !== "READY" || !isCatalogPlanToken(preview.planToken) || preview.items.length === 0) return false;
  if (preview.requiresCrossPage && !confirmed.crossPage) return false;
  if (preview.requiresAddPage && !confirmed.addPage) return false;
  return true;
}

/**
 * Chaves enviadas à prévia e à aplicação: SEMPRE a lista explícita escolhida
 * (na ordem do aviso), nunca `null` — uma novidade que nasça entre a prévia e
 * a confirmação não entra sem ser vista (o token também recusaria).
 */
export function selectionKeys(items: CatalogNovelty[], selected: ReadonlySet<string>): string[] {
  return items.filter((item) => selected.has(item.itemKey)).map((item) => item.itemKey);
}

export function pocketLabel(p: PocketPosition): string {
  return `página ${p.page}, linha ${p.row}, coluna ${p.column}`;
}

/** Uma linha por item da prévia, na linguagem do colecionador. */
export function planItemMessage(item: CatalogPlanItem): string {
  const where = item.target ? pocketLabel(item.target) : null;
  const moved = (n: number) => (n === 1 ? "1 bolso avança uma posição" : `${n} bolsos avançam uma posição`);
  switch (item.kind) {
    case "IN_PLACE":
      return item.addsPage ? `Reserva na página nova (${where}).` : `Reserva no bolso livre ${where}. Nada se move.`;
    case "RESERVE_PLACED":
      return `A carta já está no bolso certo (${where}); ele passa a ficar reservado para ela.`;
    case "SHIFT":
      return `Reserva em ${where}; ${moved(item.pocketsMoved)}${item.end ? ` até a ${pocketLabel(item.end)}` : ""}${item.otherReservesMoved > 0 ? `, levando ${item.otherReservesMoved} ${item.otherReservesMoved === 1 ? "reserva" : "reservas"} de outra coleção` : ""}.`;
    case "UPGRADE_RESERVATION":
      return `A reserva genérica desta carta (${where}) passa a indicar o acabamento. Nada se move.`;
    case "BLOCKED":
      return item.barrier
        ? `Bloqueada: ${item.barrier.kind === "LOCKED" ? "bolso fixado" : "imagem em 2 bolsos"} na ${pocketLabel(item.barrier)}.`
        : "Bloqueada por um bolso fixado ou uma imagem em 2 bolsos.";
    case "REVIEW_REQUIRED":
      return "Precisa de revisão: há mais de uma reserva genérica desta carta (ou mais de um acabamento novo). Resolva no fichário e veja a prévia de novo.";
    case "OUT_OF_ORDER":
      return item.barrier
        ? `Precisa de revisão: a carta já está no fichário, fora da ordem (${pocketLabel(item.barrier)}). Ela fica onde está.`
        : "Precisa de revisão: a carta já está no fichário, fora da ordem. Ela fica onde está.";
    case "NO_ANCHOR":
      return "Sem posição vizinha no fichário para servir de referência.";
    case "NOT_EVALUATED":
      return "Não avaliada: uma novidade anterior está bloqueada.";
  }
}

/** Resumo do resultado da prévia (cabeçalho). */
export function previewSummaryMessage(preview: CatalogPreview): string {
  const n = preview.totalItems;
  const items = n === 1 ? "1 novidade" : `${n} novidades`;
  switch (preview.outcome) {
    case "READY": {
      const moves = preview.totalRowsMoved;
      const parts = [`${items} pronta${n === 1 ? "" : "s"} para incorporar`];
      parts.push(moves === 0 ? "nenhum bolso com conteúdo se move" : `${moves} ${moves === 1 ? "item muda" : "itens mudam"} de bolso`);
      if (preview.pagesAdded > 0) parts.push(preview.pagesAdded === 1 ? `1 página nova (${preview.addedPageNumbers.join(", ")})` : `${preview.pagesAdded} páginas novas (${preview.addedPageNumbers.join(", ")})`);
      return `${parts.join("; ")}.`;
    }
    case "BLOCKED":
      return "Um bolso fixado ou uma imagem em 2 bolsos está no caminho. Nada foi feito — desafixe, separe a imagem ou desmarque a novidade bloqueada.";
    case "NEEDS_REVIEW":
      return "Há novidade que precisa de revisão (carta fora da ordem ou reserva genérica ambígua). Desmarque-a para incorporar as demais.";
    case "NO_ANCHOR":
      return "Há novidade sem posição vizinha no fichário. Desmarque-a para incorporar as demais.";
    case "OVER_LIMIT":
      return preview.reason === "ITEM_LIMIT"
        ? `São muitas novidades de uma vez — o limite é ${preview.itemLimit}. Selecione menos.`
        : `Isso moveria itens demais de uma vez (${preview.totalRowsMoved}; o limite é ${preview.rowLimit}). Selecione menos novidades.`;
    case "NOTHING_TO_DO":
      return "Não há novidade pendente: tudo já está no fichário.";
    case "NOT_ELIGIBLE":
      return ineligibleMessage(preview.reason);
  }
}

/** Itens que impedem a aplicação (para destacar e sugerir desmarcar). */
export function blockingItemKeys(preview: CatalogPreview): string[] {
  return preview.items.filter((i) => i.kind === "BLOCKED" || i.kind === "REVIEW_REQUIRED" || i.kind === "OUT_OF_ORDER" || i.kind === "NO_ANCHOR").map((i) => i.itemKey);
}

export function ineligibleMessage(reason: string | null): string {
  switch (reason) {
    case "NOT_MASTER_SET":
      return "As novidades do Catálogo valem só para coleções Master Set.";
    case "BINDER_NOT_FOUND":
      return "Esta coleção ainda não tem fichário.";
    case "BINDER_OWNER_POKEDEX":
    case "SPECIES_REFERENCES_PRESENT":
      return "Este fichário segue a ordem de uma Pokédex; as novidades do Catálogo não se aplicam a ele.";
    case "COLLECTION_REFERENCE_MISSING":
      return "A coleção está sem Set ou sem acabamentos no objetivo. Ajuste o objetivo para receber novidades.";
    case "COLLECTION_ARCHIVED":
      return "A coleção está arquivada: o fichário pode ser visto, mas não organizado.";
    default:
      return "As novidades do Catálogo não estão disponíveis para este fichário.";
  }
}

// ---------------------------------------------------------------------------
// Aplicação (5266 apply_my_binder_catalog_reconciliation) — NÃO executada no
// LIVE em BINDER-CATALOG-RECONCILIATION-FRONTEND-01; contrato pronto.
// ---------------------------------------------------------------------------

export type CatalogApplyResult = {
  outcome: "APPLIED" | "ALREADY_APPLIED" | "NOTHING_TO_DO";
  itemsApplied: number;
  reservationsCreated: number;
  reservationsUpgraded: number;
  pocketsMoved: number;
  rowsMoved: number;
  pagesAdded: number;
  addedPageNumbers: number[];
};

export function parseCatalogApply(data: unknown): CatalogApplyResult | null {
  if (!Array.isArray(data) || data.length !== 1) return null;
  const r = data[0] as Record<string, unknown> | null;
  if (!r || typeof r !== "object") return null;
  if (r.outcome !== "APPLIED" && r.outcome !== "ALREADY_APPLIED" && r.outcome !== "NOTHING_TO_DO") return null;
  const nums = [r.items_applied, r.reservations_created, r.reservations_upgraded, r.pockets_moved, r.rows_moved, r.pages_added].map(int);
  if (nums.some((n) => n === null || n < 0)) return null;
  const [itemsApplied, reservationsCreated, reservationsUpgraded, pocketsMoved, rowsMoved, pagesAdded] = nums as number[];
  const added = Array.isArray(r.added_page_numbers) ? r.added_page_numbers.map(int) : [];
  if (added.some((n) => n === null) || added.length !== pagesAdded) return null;
  if (r.outcome === "APPLIED" && (itemsApplied! < 1 || reservationsCreated! + reservationsUpgraded! !== itemsApplied)) return null;
  if (r.outcome !== "APPLIED" && itemsApplied !== 0) return null;
  return {
    outcome: r.outcome,
    itemsApplied: itemsApplied!,
    reservationsCreated: reservationsCreated!,
    reservationsUpgraded: reservationsUpgraded!,
    pocketsMoved: pocketsMoved!,
    rowsMoved: rowsMoved!,
    pagesAdded: pagesAdded!,
    addedPageNumbers: added as number[],
  };
}

export function applyResultMessage(result: CatalogApplyResult): string {
  switch (result.outcome) {
    case "APPLIED": {
      const n = result.itemsApplied;
      const head = n === 1 ? "1 novidade foi incorporada ao fichário" : `${n} novidades foram incorporadas ao fichário`;
      const extra: string[] = [];
      if (result.pocketsMoved > 0) extra.push(result.pocketsMoved === 1 ? "1 bolso avançou" : `${result.pocketsMoved} bolsos avançaram`);
      if (result.pagesAdded > 0) extra.push(result.pagesAdded === 1 ? `página ${result.addedPageNumbers[0]} adicionada` : `páginas ${result.addedPageNumbers.join(", ")} adicionadas`);
      return `${head}${extra.length ? ` (${extra.join("; ")})` : ""}.`;
    }
    case "ALREADY_APPLIED":
      return "Essas novidades já estavam incorporadas. Nada mudou.";
    case "NOTHING_TO_DO":
      return "Não havia novidade pendente. Nada mudou.";
  }
}

export type CatalogFailure =
  | "plan_changed"
  | "selection_invalid"
  | "blocked"
  | "needs_review"
  | "no_anchor"
  | "over_limit"
  | "confirm_cross_page"
  | "confirm_add_page"
  | "not_eligible"
  | "not_master_set"
  | "reference_missing"
  | "archived"
  | "not_found"
  | "inconsistent"
  | "lock_busy"
  | "not_authenticated"
  | "unavailable"
  | "invalid"
  | "unknown";

/**
 * Classe da falha a partir do erro do PostgREST. A MENSAGEM vem antes do
 * código: vários erros da 5264–5266 compartilham 22023/55000/P0001/P0002.
 */
export function classifyCatalogFailure(code: string | null | undefined, message: string | null | undefined, hint?: string | null): CatalogFailure {
  const text = (message ?? "").toUpperCase();
  if (code === "PGRST202" || code === "42883") return "unavailable";
  if (code === "28000" || text.includes("NOT_AUTHENTICATED")) return "not_authenticated";
  if (text.includes("RECONCILE_PLAN_CHANGED") || code === "40001") return "plan_changed";
  if (text.includes("RECONCILE_OVER_LIMIT") || code === "54000") return "over_limit";
  if (text.includes("RECONCILE_BLOCKED")) return "blocked";
  if (text.includes("RECONCILE_NEEDS_REVIEW")) return "needs_review";
  if (text.includes("RECONCILE_NO_ANCHOR")) return "no_anchor";
  if (text.includes("RECONCILE_CONFIRMATION_REQUIRED")) return (hint ?? "").toUpperCase().includes("ADD_PAGE") ? "confirm_add_page" : "confirm_cross_page";
  if (text.includes("RECONCILE_INCONSISTENT")) return "inconsistent";
  if (text.includes("SELECTION_INVALID")) return "selection_invalid";
  if (text.includes("NOT_MASTER_SET")) return "not_master_set";
  if (text.includes("BINDER_NOT_ELIGIBLE")) return "not_eligible";
  if (text.includes("COLLECTION_REFERENCE_MISSING")) return "reference_missing";
  if (text.includes("COLLECTION_ARCHIVED")) return "archived";
  if (code === "55P03" || text.includes("LOCK TIMEOUT")) return "lock_busy";
  if (text.includes("NOT_FOUND") || code === "P0002") return "not_found";
  if (text.includes("INVALID_ARGUMENT") || code === "22023") return "invalid";
  return "unknown";
}

export function catalogFailureMessage(reason: CatalogFailure): string {
  switch (reason) {
    case "plan_changed":
      return "O fichário ou o Catálogo mudou desde a prévia. Veja a prévia de novo antes de incorporar.";
    case "selection_invalid":
      return "Alguma novidade selecionada não está mais pendente (já entrou no fichário). A lista foi relida.";
    case "blocked":
      return "Um bolso fixado ou uma imagem em 2 bolsos está no caminho. Nada foi movido.";
    case "needs_review":
      return "Há novidade que precisa de revisão. Desmarque-a e incorpore as demais. Nada foi movido.";
    case "no_anchor":
      return "Há novidade sem posição vizinha no fichário. Desmarque-a. Nada foi movido.";
    case "over_limit":
      return "Isso moveria itens demais de uma vez. Selecione menos novidades. Nada foi movido.";
    case "confirm_cross_page":
    case "confirm_add_page":
      return "Confirme a mudança de página e a página nova na prévia para continuar.";
    case "not_eligible":
      return "Este fichário não recebe novidades do Catálogo (fichário de Pokédex ou com Pokémon nos bolsos).";
    case "not_master_set":
      return "As novidades do Catálogo valem só para coleções Master Set.";
    case "reference_missing":
      return "A coleção está sem Set ou sem acabamentos no objetivo.";
    case "archived":
      return "A coleção está arquivada: o fichário pode ser visto, mas não organizado.";
    case "not_found":
      return "Não encontramos este fichário. Recarregue a página.";
    case "inconsistent":
      return "O resultado não conferiu com a prévia e nada foi gravado. O fichário foi relido — veja a prévia de novo.";
    case "lock_busy":
      return "O fichário está sendo atualizado agora. Tente de novo em instantes.";
    case "not_authenticated":
      return "Sua sessão expirou. Entre de novo para continuar.";
    case "unavailable":
      return "As novidades do Catálogo ainda não estão disponíveis.";
    case "invalid":
      return "Não foi possível usar essa seleção.";
    case "unknown":
      return "Não conseguimos confirmar o resultado. O fichário foi relido — confira antes de tentar de novo.";
  }
}

/** Depois destas falhas a prévia é refeita automaticamente (estado mudou). */
export function failureNeedsFreshPreview(reason: CatalogFailure): boolean {
  return reason === "plan_changed" || reason === "selection_invalid" || reason === "inconsistent" || reason === "blocked" || reason === "needs_review" || reason === "no_anchor";
}
