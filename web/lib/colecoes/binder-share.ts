import { type BinderSlot, deriveSlotState, isOccupied } from "./binder.ts";

/**
 * Fichário Digital compartilhado (P2-SHARED-BINDER-FRONTEND-01) — regras
 * puras, sem banco e sem React (testável com `node --test`).
 *
 * Contratos LIVE, canônicos em `database/schema/`:
 *  - 5230 `list_my_binder_join_candidates(coleção)` — fichários que a coleção
 *    pode usar (mesmo dono, mesmo fichário físico; não grava);
 *  - 5229 `attach_my_collection_to_binder(coleção, fichário)` — associação
 *    explícita; não toca bolso, reserva nem alocação (D1/D3);
 *  - 5230 `get_my_collection_binder_unplaced(coleção, limite ≤ 96, início)` —
 *    "Cartas disponíveis": exemplares desta coleção fora dos bolsos;
 *  - 5131 `assign_card_to_slot(bolso, alocação)` — posicionar (D4);
 *  - 5229 `preview_my_collection_binder_detach(coleção)` + `detach_…(coleção,
 *    token, soltar_fixados)` — sair do fichário compartilhado (D5/D6).
 *
 * Vocabulário (não confundir na interface): **Cartas disponíveis** são
 * exemplares persistentes ainda sem bolso; a **Bandeja** é transporte
 * temporário entre páginas, só na tela.
 */

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function int(value: unknown): number | null {
  const n = typeof value === "string" && value.trim() !== "" ? Number(value) : value;
  return typeof n === "number" && Number.isInteger(n) ? n : null;
}

function str(value: unknown): string | null {
  return typeof value === "string" && value !== "" ? value : null;
}

function uuid(value: unknown): string | null {
  return typeof value === "string" && UUID.test(value) ? value : null;
}

// ---------------------------------------------------------------------------
// Candidatos (5230)
// ---------------------------------------------------------------------------

export type JoinCandidate = {
  layoutId: string;
  ownerCollectionId: string;
  ownerCollectionName: string;
  columns: number;
  rows: number;
  pageCount: number;
  freeSlotCount: number;
  participantCount: number;
};

/** Linhas da 5230 → candidatos válidos (linha malformada é descartada, nunca adivinhada). */
export function parseJoinCandidates(rows: unknown): JoinCandidate[] | null {
  if (!Array.isArray(rows)) return null;
  const out: JoinCandidate[] = [];
  for (const raw of rows) {
    if (!raw || typeof raw !== "object") return null;
    const r = raw as Record<string, unknown>;
    const layoutId = uuid(r.layout_id);
    const ownerCollectionId = uuid(r.owner_collection_id);
    const columns = int(r.grid_columns);
    const rowsN = int(r.grid_rows);
    if (!layoutId || !ownerCollectionId || columns === null || rowsN === null || columns < 1 || rowsN < 1) return null;
    out.push({
      layoutId,
      ownerCollectionId,
      ownerCollectionName: str(r.owner_collection_name) ?? "Coleção",
      columns,
      rows: rowsN,
      pageCount: Math.max(0, int(r.page_count) ?? 0),
      freeSlotCount: Math.max(0, int(r.free_slot_count) ?? 0),
      participantCount: Math.max(1, int(r.participant_count) ?? 1),
    });
  }
  return out;
}

export type AttachOutcome = "ATTACHED" | "ALREADY_ATTACHED";

export function parseAttachOutcome(rows: unknown): AttachOutcome | null {
  const row = Array.isArray(rows) && rows.length === 1 ? (rows[0] as Record<string, unknown> | undefined) : undefined;
  const outcome = row?.outcome;
  return outcome === "ATTACHED" || outcome === "ALREADY_ATTACHED" ? outcome : null;
}

// ---------------------------------------------------------------------------
// Cartas disponíveis (5230)
// ---------------------------------------------------------------------------

/** Página da leitura de cartas disponíveis (teto do contrato: 96). */
export const AVAILABLE_PAGE_SIZE = 48;
export const AVAILABLE_MAX_LIMIT = 96;

export type AvailableCard = {
  allocationId: string;
  physicalCardId: string;
  cardId: string;
  variantTypeId: string | null;
  cardName: string;
  collectorNumber: string | null;
  collectorTotal: number | null;
  setCode: string | null;
  variantLabel: string | null;
  languageCode: string | null;
  imagePath: string | null;
};

export function parseAvailableCards(rows: unknown): { items: AvailableCard[]; total: number } | null {
  if (!Array.isArray(rows)) return null;
  const items: AvailableCard[] = [];
  let total = 0;
  for (const raw of rows) {
    if (!raw || typeof raw !== "object") return null;
    const r = raw as Record<string, unknown>;
    const allocationId = uuid(r.collection_allocation_id);
    const physicalCardId = uuid(r.physical_card_id);
    const cardId = uuid(r.card_id);
    const name = str(r.card_name);
    if (!allocationId || !physicalCardId || !cardId || !name) return null;
    total = Math.max(total, int(r.total_count) ?? 0);
    items.push({
      allocationId,
      physicalCardId,
      cardId,
      variantTypeId: uuid(r.variant_type_id),
      cardName: name,
      collectorNumber: str(r.collector_number),
      collectorTotal: int(r.collector_total),
      setCode: str(r.card_set_code),
      variantLabel: str(r.variant_label),
      languageCode: str(r.language_code),
      imagePath: str(r.image_path),
    });
  }
  return { items, total: items.length === 0 ? 0 : Math.max(total, items.length) };
}

/** Junta páginas sem duplicar (a lista pode ter mudado entre uma página e outra). */
export function mergeAvailable(current: readonly AvailableCard[], next: readonly AvailableCard[]): AvailableCard[] {
  const seen = new Set(current.map((item) => item.allocationId));
  return [...current, ...next.filter((item) => !seen.has(item.allocationId))];
}

/**
 * Só bolso vazio e solto recebe uma carta disponível — nunca substitui outra
 * em silêncio. Bolso reservado só recebe carta da coleção dona da reserva
 * (respeita o plano da outra coleção no fichário compartilhado).
 */
export function canReceiveAvailable(
  slot: Pick<BinderSlot, "state" | "locked"> & Partial<Pick<BinderSlot, "expectedCollectionId" | "image" | "regionId">>,
  cardCollectionId?: string,
): boolean {
  // Bolso com imagem personalizada (C-198) não recebe carta — o banco recusa com SLOT_HAS_IMAGE.
  // Bolso de imagem em 2 bolsos também não (5238: SLOT_IN_REGION).
  if (slot.locked || isOccupied(slot) || slot.image || slot.regionId) return false;
  if (slot.state === "RESERVED_EMPTY" && cardCollectionId && slot.expectedCollectionId && slot.expectedCollectionId !== cardCollectionId) return false;
  return true;
}

/** Bolso vazio que abre "Adicionar carta" ao ser tocado (vazio ou só reservado, solto e sem imagem). */
export function isAddablePocket(slot: Pick<BinderSlot, "state" | "locked"> & Partial<Pick<BinderSlot, "image" | "regionId">>): boolean {
  return !slot.locked && !slot.image && !slot.regionId && (slot.state === "EMPTY" || slot.state === "RESERVED_EMPTY");
}

/**
 * Coleções cujas cartas sem bolso podem ir para este fichário, a partir do
 * que o cabeçalho (5230) revela: a própria e, para a convidada, a
 * proprietária. A proprietária não conhece as convidadas pela leitura atual
 * (não há contrato que as liste), então vê só as próprias cartas.
 */
export function placementSources(input: {
  collectionId: string;
  collectionName: string;
  role: "OWNER" | "GUEST" | null;
  ownerCollectionId: string | null;
  ownerCollectionName: string | null;
}): { collectionId: string; name: string }[] {
  const sources = [{ collectionId: input.collectionId, name: input.collectionName }];
  if (input.role === "GUEST" && input.ownerCollectionId && input.ownerCollectionId !== input.collectionId) {
    sources.push({ collectionId: input.ownerCollectionId, name: input.ownerCollectionName ?? "Coleção dona do fichário" });
  }
  return sources;
}

/** Estado provável do bolso logo depois de posicionar (a tela relê o lote em seguida). */
export function applyPlaceAvailable(slot: BinderSlot, card: AvailableCard, collectionId: string): BinderSlot {
  const next: BinderSlot = {
    ...slot,
    present: {
      cardName: card.cardName,
      collectorNumber: card.collectorNumber,
      collectorTotal: card.collectorTotal,
      setCode: card.setCode,
      imagePath: card.imagePath,
      finishCode: null,
      finishName: null,
      languageCode: card.languageCode,
      variantLabel: card.variantLabel,
    },
    assignmentId: null,
    allocationId: card.allocationId,
    presentCardId: card.cardId,
    presentVariantTypeId: card.variantTypeId,
    presentCollectionId: collectionId,
  };
  return { ...next, state: deriveSlotState(next) };
}

// ---------------------------------------------------------------------------
// "Só desta coleção" — destaque visual, nunca muda a organização
// ---------------------------------------------------------------------------

/**
 * O bolso pertence a OUTRA coleção do fichário compartilhado? Carta de outra
 * coleção, ou só a reserva de outra coleção. Bolso vazio nunca é "de outra".
 * A reserva sem coleção gravada é da proprietária (5230 já resolve isso em
 * `expected_collection_id`).
 */
export function isForeignSlot(slot: Pick<BinderSlot, "presentCollectionId" | "expectedCollectionId" | "state">, collectionId: string): boolean {
  if (isOccupied(slot)) return slot.presentCollectionId !== null && slot.presentCollectionId !== collectionId;
  if (slot.state === "RESERVED_EMPTY") return slot.expectedCollectionId !== null && slot.expectedCollectionId !== collectionId;
  return false;
}

// ---------------------------------------------------------------------------
// Desassociação (5229)
// ---------------------------------------------------------------------------

export const DETACH_TOKEN = /^g1:[0-9a-f]{64}$/;

export type DetachPreview = {
  layoutId: string;
  ownerCollectionId: string;
  ownerCollectionName: string;
  assignmentsCount: number;
  reservationsCount: number;
  lockedCount: number;
  token: string;
};

/** `null` = formato inesperado; `undefined` = a coleção não é convidada (sem linha). */
export function parseDetachPreview(rows: unknown): DetachPreview | null | undefined {
  if (!Array.isArray(rows)) return null;
  if (rows.length === 0) return undefined;
  if (rows.length !== 1) return null;
  const r = rows[0] as Record<string, unknown>;
  const layoutId = uuid(r?.layout_id);
  const ownerCollectionId = uuid(r?.owner_collection_id);
  const a = int(r?.assignments_count);
  const e = int(r?.reservations_count);
  const k = int(r?.locked_count);
  const token = typeof r?.detach_token === "string" && DETACH_TOKEN.test(r.detach_token) ? r.detach_token : null;
  if (!layoutId || !ownerCollectionId || a === null || e === null || k === null || !token) return null;
  return {
    layoutId,
    ownerCollectionId,
    ownerCollectionName: str(r.owner_collection_name) ?? "Coleção",
    assignmentsCount: Math.max(0, a),
    reservationsCount: Math.max(0, e),
    lockedCount: Math.max(0, k),
    token,
  };
}

export type DetachResult = { outcome: "DETACHED" | "ALREADY_DETACHED"; assignmentsRemoved: number; reservationsRemoved: number; locksReleased: number };

export function parseDetachResult(rows: unknown): DetachResult | null {
  const row = Array.isArray(rows) && rows.length === 1 ? (rows[0] as Record<string, unknown> | undefined) : undefined;
  if (!row || (row.outcome !== "DETACHED" && row.outcome !== "ALREADY_DETACHED")) return null;
  const a = int(row.assignments_removed);
  const e = int(row.reservations_removed);
  const k = int(row.locks_released);
  if (a === null || e === null || k === null) return null;
  return { outcome: row.outcome, assignmentsRemoved: a, reservationsRemoved: e, locksReleased: k };
}

// ---------------------------------------------------------------------------
// Falhas (5229/5230) → motivo estável e mensagem para o colecionador
// ---------------------------------------------------------------------------

export type ShareFailure =
  | "binder_not_found"
  | "binder_archived"
  | "collection_archived"
  | "not_same_location"
  | "has_own_binder"
  | "already_in_binder"
  | "plan_changed"
  | "locks_need_confirmation"
  | "lock_busy"
  | "not_found"
  | "not_authenticated"
  | "invalid"
  | "unknown";

export function classifyShareFailure(code: string | null | undefined, message: string | null | undefined): ShareFailure {
  const text = (message ?? "").trim();
  if (text === "BINDER_NOT_FOUND") return "binder_not_found";
  if (text === "BINDER_ARCHIVED") return "binder_archived";
  if (text === "COLLECTION_ARCHIVED") return "collection_archived";
  if (text === "NOT_SAME_LOCATION") return "not_same_location";
  if (text === "COLLECTION_HAS_OWN_BINDER") return "has_own_binder";
  if (text === "COLLECTION_ALREADY_IN_BINDER") return "already_in_binder";
  if (text === "DETACH_PLAN_CHANGED") return "plan_changed";
  if (text === "LOCKED_SLOTS_REQUIRE_CONFIRMATION") return "locks_need_confirmation";
  if (code === "55P03") return "lock_busy";
  if (text === "COLLECTION_NOT_FOUND" || code === "P0002") return "not_found";
  if (code === "28000" || code === "42501" || text === "not_authenticated") return "not_authenticated";
  if (code === "22023" || code === "22P02") return "invalid";
  return "unknown";
}

export function shareFailureMessage(reason: ShareFailure): string {
  switch (reason) {
    case "binder_not_found":
      return "Esse fichário não está mais disponível. Atualizamos as opções.";
    case "binder_archived":
      return "A coleção dona desse fichário está arquivada. Reative-a para compartilhar o fichário.";
    case "collection_archived":
      return "Esta coleção está arquivada. Reative-a para usar um fichário.";
    case "not_same_location":
      return "Esta coleção não está guardada no mesmo fichário físico. Confira o local padrão em Ajustes → Onde guardo.";
    case "has_own_binder":
      return "Esta coleção já tem um fichário próprio.";
    case "already_in_binder":
      return "Esta coleção já usa outro fichário compartilhado.";
    case "plan_changed":
      return "O fichário mudou desde a prévia. Revise os números atualizados e confirme de novo — nada foi alterado.";
    case "locks_need_confirmation":
      return "Há bolsos fixados com cartas ou reservas desta coleção. Confirme que eles podem ser soltos.";
    case "lock_busy":
      return "O fichário está sendo atualizado em outra tela. Tente de novo em alguns segundos.";
    case "not_found":
      return "Não encontramos esta coleção na sua conta.";
    case "not_authenticated":
      return "Sua sessão terminou. Entre de novo para continuar.";
    case "invalid":
      return "Não foi possível entender o pedido. Recarregue a página e tente de novo.";
    default:
      return "Não foi possível concluir agora. Nada foi alterado — tente de novo em instantes.";
  }
}

/** Quantidade com substantivo no singular/plural ("1 carta", "3 cartas"). */
export function plural(count: number, one: string, many: string): string {
  return `${count.toLocaleString("pt-BR")} ${count === 1 ? one : many}`;
}
