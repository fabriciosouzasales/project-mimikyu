"use server";

import { revalidatePath } from "next/cache";
import { isUuid } from "@/lib/colecoes/acervo-add";
import { isCollectionId } from "@/lib/colecoes/colecoes";
import {
  type EditorFailure,
  type PocketPosition,
  PLACEABLE_PAGE_SIZE,
  candidatesFromCatalogSearch,
  candidatesFromSharedPositions,
  classifyEditorFailure,
  editorCurationFlagOn,
  editorReserveScope,
  isPocketPosition,
  parsePlaceableCards,
} from "@/lib/colecoes/editor-binder";
import { type PageFailure, classifyPageFailure, reorderChanged, reorderPayload } from "@/lib/colecoes/editor-binder-pages";
import {
  type EditorGapFailure,
  type EditorGapInsert,
  type EditorGapUndo,
  classifyEditorGapFailure,
  isGapPlanToken,
  isGapUndoToken,
  parseEditorGapClose,
  parseEditorGapInsert,
  parseEditorGapPreview,
} from "@/lib/colecoes/editor-binder-gap";
import type { GapPreview } from "@/lib/colecoes/binder-insert";
import type { AvailableCard } from "@/lib/colecoes/binder-share";
import type { ReserveCandidate, ReserveScope } from "@/lib/colecoes/binder-reserve";
import { SHARED_COLLECTION_PATH, parseSharedBinder, parseSharedCollection } from "@/lib/colecoes/sharing";
import { createClient } from "@/lib/supabase/server";

/**
 * V1-13 · E2-1 — escritas do EDITOR no fichário compartilhado (5373/5374).
 *
 * Server actions finas: validam formato, chamam a RPC com a SESSÃO do usuário
 * (nunca service role) e traduzem a resposta. Toda autorização é do banco, a
 * cada chamada: papel EDITOR ativo da coleção, classificação do bolso sob
 * trava (C-237), elegibilidade do exemplar (C-235/DR-1) e a barreira da V1-13
 * (5389). A configuração `MMKYU_V113_EDITOR_CURATION` (D1, desligada por
 * padrão) só evita chamadas quando a curadoria não está habilitada no
 * frontend; ela NÃO autoriza nada.
 */

type Fail = { ok: false; reason: EditorFailure };

function enabled(): boolean {
  return editorCurationFlagOn(process.env);
}

function fail(fn: string, startedAt: number, error: { code?: string; message?: string } | null): Fail {
  const reason = classifyEditorFailure(error?.code, error?.message);
  // Sem ids nem conteúdo no log: função, duração, código e motivo.
  console.error(JSON.stringify({ scope: "colecoes.editor_binder", fn, ms: Date.now() - startedAt, code: error?.code ?? "BAD_SHAPE", reason }));
  return { ok: false, reason };
}

function done(fn: string, startedAt: number, collectionId: string, operation: string) {
  console.info(JSON.stringify({ scope: "colecoes.editor_binder", fn, ms: Date.now() - startedAt, operation }));
  // O cabeçalho da coleção compartilhada mostra a contagem do fichário; a área de trabalho relê o lote.
  revalidatePath(`${SHARED_COLLECTION_PATH}/${collectionId}`);
}

function operationOf(data: unknown): string | null {
  const row = Array.isArray(data) ? (data[0] as Record<string, unknown> | undefined) : undefined;
  return typeof row?.operation === "string" ? row.operation : null;
}

/** Exemplares que o EDITOR pode colocar (5373): só da coleção e guardados neste fichário, sem bolso. */
export async function readEditorPlaceableCards(input: { collectionId: string; offset: number }): Promise<{ ok: true; items: AvailableCard[]; total: number } | Fail> {
  if (!enabled()) return { ok: false, reason: "disabled" };
  if (!isCollectionId(input?.collectionId) || !Number.isInteger(input.offset) || input.offset < 0 || input.offset > 100000) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_shared_binder_placeable_cards", {
    p_collection_id: input.collectionId,
    p_limit: PLACEABLE_PAGE_SIZE,
    p_offset: input.offset,
  });
  if (error) return fail("get_shared_binder_placeable_cards", startedAt, error);
  const parsed = parsePlaceableCards(data);
  if (!parsed) return fail("get_shared_binder_placeable_cards", startedAt, null);
  return { ok: true, items: parsed.items, total: parsed.total };
}

/** Colocar (C-235): ADD, REPLACE (só carta desta coleção) ou UNCHANGED. Também é o "Desfazer" da retirada (D2). */
export async function editorPlaceCard(input: {
  collectionId: string;
  position: PocketPosition;
  physicalCardId: string;
}): Promise<{ ok: true; operation: "ADD" | "REPLACE" | "UNCHANGED" } | Fail> {
  if (!enabled()) return { ok: false, reason: "disabled" };
  if (!isCollectionId(input?.collectionId) || !isPocketPosition(input.position) || !isUuid(input.physicalCardId)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("editor_place_card_in_binder", {
    p_collection_id: input.collectionId,
    p_page: input.position.page,
    p_row: input.position.row,
    p_column: input.position.column,
    p_physical_card_id: input.physicalCardId,
  });
  if (error) return fail("editor_place_card_in_binder", startedAt, error);
  const operation = operationOf(data);
  if (operation !== "ADD" && operation !== "REPLACE" && operation !== "UNCHANGED") return fail("editor_place_card_in_binder", startedAt, null);
  done("editor_place_card_in_binder", startedAt, input.collectionId, operation);
  return { ok: true, operation };
}

/** Mover (destino livre) ou trocar (destino com carta desta coleção) — C-237. */
export async function editorMoveCard(input: {
  collectionId: string;
  from: PocketPosition;
  to: PocketPosition;
}): Promise<{ ok: true; operation: "MOVE" | "SWAP" } | Fail> {
  if (!enabled()) return { ok: false, reason: "disabled" };
  if (!isCollectionId(input?.collectionId) || !isPocketPosition(input.from) || !isPocketPosition(input.to)) return { ok: false, reason: "invalid" };
  if (input.from.page === input.to.page && input.from.row === input.to.row && input.from.column === input.to.column) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("editor_move_binder_card", {
    p_collection_id: input.collectionId,
    p_from_page: input.from.page,
    p_from_row: input.from.row,
    p_from_column: input.from.column,
    p_to_page: input.to.page,
    p_to_row: input.to.row,
    p_to_column: input.to.column,
  });
  if (error) return fail("editor_move_binder_card", startedAt, error);
  const operation = operationOf(data);
  if (operation !== "MOVE" && operation !== "SWAP") return fail("editor_move_binder_card", startedAt, null);
  done("editor_move_binder_card", startedAt, input.collectionId, operation);
  return { ok: true, operation };
}

/** Retirar do bolso (C-236): a carta continua na coleção, no mesmo local e no acervo do titular. */
export async function editorRemoveCard(input: { collectionId: string; position: PocketPosition }): Promise<{ ok: true } | Fail> {
  if (!enabled()) return { ok: false, reason: "disabled" };
  if (!isCollectionId(input?.collectionId) || !isPocketPosition(input.position)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("editor_remove_binder_card", {
    p_collection_id: input.collectionId,
    p_page: input.position.page,
    p_row: input.position.row,
    p_column: input.position.column,
  });
  if (error) return fail("editor_remove_binder_card", startedAt, error);
  if (operationOf(data) !== "REMOVED") return fail("editor_remove_binder_card", startedAt, null);
  done("editor_remove_binder_card", startedAt, input.collectionId, "REMOVED");
  return { ok: true };
}

// ---------------------------------------------------------------------------
// V1-13 · E2-2 — reservas e fixação pelo EDITOR (5375), por posição. Mesma
// fronteira: a configuração D1 só evita chamadas; a autorização é do banco.

/** Reservar (ou trocar a reserva de) um bolso para uma carta — sempre registrada para esta coleção. */
export async function editorSetReservation(input: {
  collectionId: string;
  position: PocketPosition;
  cardId: string;
  /** Master Set: acabamento esperado; `null` = só a carta. */
  variantTypeId: string | null;
}): Promise<{ ok: true; operation: "RESERVED" | "REPLACED" | "UNCHANGED" } | Fail> {
  if (!enabled()) return { ok: false, reason: "disabled" };
  if (!isCollectionId(input?.collectionId) || !isPocketPosition(input.position) || !isUuid(input.cardId) || (input.variantTypeId !== null && !isUuid(input.variantTypeId))) {
    return { ok: false, reason: "invalid" };
  }
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("editor_set_binder_reservation", {
    p_collection_id: input.collectionId,
    p_page: input.position.page,
    p_row: input.position.row,
    p_column: input.position.column,
    p_card_id: input.cardId,
    p_card_variant_id: null,
    p_expected_variant_type_id: input.variantTypeId,
  });
  if (error) return fail("editor_set_binder_reservation", startedAt, error);
  const operation = operationOf(data);
  if (operation !== "RESERVED" && operation !== "REPLACED" && operation !== "UNCHANGED") return fail("editor_set_binder_reservation", startedAt, null);
  done("editor_set_binder_reservation", startedAt, input.collectionId, operation);
  return { ok: true, operation };
}

/** Liberar a reserva desta coleção num bolso. Sem reserva → UNCHANGED (sem evento). */
export async function editorClearReservation(input: { collectionId: string; position: PocketPosition }): Promise<{ ok: true; operation: "RELEASED" | "UNCHANGED" } | Fail> {
  if (!enabled()) return { ok: false, reason: "disabled" };
  if (!isCollectionId(input?.collectionId) || !isPocketPosition(input.position)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("editor_clear_binder_reservation", {
    p_collection_id: input.collectionId,
    p_page: input.position.page,
    p_row: input.position.row,
    p_column: input.position.column,
  });
  if (error) return fail("editor_clear_binder_reservation", startedAt, error);
  const operation = operationOf(data);
  if (operation !== "RELEASED" && operation !== "UNCHANGED") return fail("editor_clear_binder_reservation", startedAt, null);
  done("editor_clear_binder_reservation", startedAt, input.collectionId, operation);
  return { ok: true, operation };
}

/** Fixar (`locked = true`) ou soltar um bolso desta coleção. */
export async function editorSetLock(input: { collectionId: string; position: PocketPosition; locked: boolean }): Promise<{ ok: true; operation: "LOCKED" | "UNLOCKED" | "UNCHANGED" } | Fail> {
  if (!enabled()) return { ok: false, reason: "disabled" };
  if (!isCollectionId(input?.collectionId) || !isPocketPosition(input.position) || typeof input.locked !== "boolean") return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("editor_set_binder_lock", {
    p_collection_id: input.collectionId,
    p_page: input.position.page,
    p_row: input.position.row,
    p_column: input.position.column,
    p_locked: input.locked,
  });
  if (error) return fail("editor_set_binder_lock", startedAt, error);
  const operation = operationOf(data);
  if (operation !== "LOCKED" && operation !== "UNLOCKED" && operation !== "UNCHANGED") return fail("editor_set_binder_lock", startedAt, null);
  done("editor_set_binder_lock", startedAt, input.collectionId, operation);
  return { ok: true, operation };
}

const POSITIONS_PAGE = 500;
const POSITIONS_MAX = 4000;

/**
 * Cartas para o seletor de reserva do EDITOR, pela leitura que o participante
 * já tem, conforme o tipo da coleção: Set padrão → 5320; Master Set → 5323;
 * coleção livre → Catálogo (`search_cards`, como o titular). Pokédex não tem
 * reserva por carta. Nada do acervo do titular.
 */
export async function readEditorReserveCandidates(input: {
  collectionId: string;
  query?: string;
  offset?: number;
}): Promise<{ ok: true; scope: ReserveScope; candidates: ReserveCandidate[]; total: number; complete: boolean } | { ok: false; reason: "invalid" | "not_found" | "unsupported" | "unavailable" }> {
  if (!enabled()) return { ok: false, reason: "unavailable" };
  if (!isCollectionId(input?.collectionId)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const header = await supabase.rpc("get_shared_collection", { p_collection_id: input.collectionId });
  if (header.error) return { ok: false, reason: "unavailable" };
  const collection = parseSharedCollection(header.data);
  if (!collection || collection.access !== "VIEWER") return { ok: false, reason: "not_found" };
  const scope = editorReserveScope(collection.completionPolicy);
  if (scope === null) return { ok: false, reason: "unsupported" };

  if (scope === "FREE") {
    const query = typeof input.query === "string" ? input.query.trim().slice(0, 120) : "";
    if (query.length < 2) return { ok: true, scope, candidates: [], total: 0, complete: true };
    const offset = Number.isInteger(input.offset) && (input.offset as number) > 0 ? Math.min(input.offset as number, 5000) : 0;
    const { data, error } = await supabase.rpc("search_cards", {
      p_query: query,
      p_card_id: null,
      p_card_set_code: null,
      p_category_code: null,
      p_rarity_code: null,
      p_limit: 36,
      p_offset: offset,
    });
    const candidates = error ? null : candidatesFromCatalogSearch(data);
    if (!candidates) {
      console.error(JSON.stringify({ scope: "colecoes.editor_binder", fn: "search_cards", ms: Date.now() - startedAt, code: error?.code ?? "BAD_SHAPE" }));
      return { ok: false, reason: "unavailable" };
    }
    const total = Number((data as Array<{ total_count?: unknown }>)[0]?.total_count ?? 0) || candidates.length;
    return { ok: true, scope, candidates, total, complete: offset + candidates.length >= total };
  }

  const fn = scope === "MASTER_SET" ? "get_shared_master_set_positions" : "get_shared_collection_positions";
  const set = { code: collection.cardSetCode, name: collection.cardSetName };
  const candidates: ReserveCandidate[] = [];
  let total = 0;
  for (let offset = 0; offset < POSITIONS_MAX; offset += POSITIONS_PAGE) {
    const { data, error } = await supabase.rpc(fn, { p_collection_id: input.collectionId, p_filter: "ALL", p_limit: POSITIONS_PAGE, p_offset: offset });
    const rows = error ? null : candidatesFromSharedPositions(scope, data, set);
    if (!rows) {
      console.error(JSON.stringify({ scope: "colecoes.editor_binder", fn, ms: Date.now() - startedAt, code: error?.code ?? "BAD_SHAPE" }));
      return { ok: false, reason: "unavailable" };
    }
    total = Math.max(total, Number((data as Array<{ total_count?: unknown }>)[0]?.total_count ?? 0) || 0);
    candidates.push(...rows);
    if (rows.length < POSITIONS_PAGE) break;
  }
  return { ok: true, scope, candidates, total: Math.max(total, candidates.length), complete: candidates.length >= total };
}

// ---------------------------------------------------------------------------
// V1-13 · E2-3A — páginas pelo EDITOR (5382), só no fichário exclusivo da
// coleção. Nenhuma das três ações lê `hint`/`details` do erro: a recusa vira um
// motivo estável pelo nome da exceção (classifyPageFailure). Sem repetição
// automática: quem chama relê o estado e decide.

type PageFail = { ok: false; reason: PageFailure };

function pageFail(fn: string, startedAt: number, error: { code?: string; message?: string } | null): PageFail {
  const reason = classifyPageFailure(error?.code, error?.message);
  console.error(JSON.stringify({ scope: "colecoes.editor_binder", fn, ms: Date.now() - startedAt, code: error?.code ?? "BAD_SHAPE", reason }));
  return { ok: false, reason };
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : null;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

/** Cabeçalho autorizado do fichário compartilhado (5314) — releitura antes e depois das operações de página. */
export async function readEditorBinderHeader(input: { collectionId: string }): Promise<{ ok: true; pageCount: number; columns: number; rows: number; ownFilled: number } | PageFail> {
  if (!enabled()) return { ok: false, reason: "disabled" };
  if (!isCollectionId(input?.collectionId)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_shared_collection_binder", { p_collection_id: input.collectionId });
  if (error) return pageFail("get_shared_collection_binder", startedAt, error);
  const binder = parseSharedBinder(data);
  // Sem fichário ou formato inesperado: a tela trata como acesso que mudou (relê a coleção).
  if (!binder || !binder.hasBinder) return { ok: false, reason: "access_lost" };
  return { ok: true, pageCount: binder.pageCount, columns: binder.columns, rows: binder.rows, ownFilled: binder.ownFilled };
}

/** Adicionar UMA página vazia no fim (5382). O lote é feito por quem chama, uma página por vez. */
export async function editorAddPage(input: { collectionId: string }): Promise<{ ok: true; pageNumber: number } | PageFail> {
  if (!enabled()) return { ok: false, reason: "disabled" };
  if (!isCollectionId(input?.collectionId)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("editor_add_binder_page", { p_collection_id: input.collectionId });
  if (error) return pageFail("editor_add_binder_page", startedAt, error);
  const pageNumber = Number(firstRow(data)?.page_number);
  if (!Number.isInteger(pageNumber) || pageNumber < 1) return pageFail("editor_add_binder_page", startedAt, null);
  done("editor_add_binder_page", startedAt, input.collectionId, "PAGE_ADDED");
  return { ok: true, pageNumber };
}

/**
 * Remover a página de NÚMERO informado (5382), só se estiver totalmente vazia
 * e sem conteúdo de terceiros. A confirmação de referências de espécie nunca é
 * enviada (D2): página com referência é recusada.
 */
export async function editorRemovePage(input: { collectionId: string; pageNumber: number }): Promise<{ ok: true; removedPageNumber: number } | PageFail> {
  if (!enabled()) return { ok: false, reason: "disabled" };
  if (!isCollectionId(input?.collectionId) || !Number.isInteger(input.pageNumber) || input.pageNumber < 1 || input.pageNumber > 100000) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("editor_remove_binder_page", { p_collection_id: input.collectionId, p_page_number: input.pageNumber });
  if (error) return pageFail("editor_remove_binder_page", startedAt, error);
  const removed = Number(firstRow(data)?.removed_page_number);
  if (removed !== input.pageNumber) return pageFail("editor_remove_binder_page", startedAt, null);
  done("editor_remove_binder_page", startedAt, input.collectionId, "PAGE_REMOVED");
  return { ok: true, removedPageNumber: removed };
}

/** Reordenar (5382): `order[i]` = número ATUAL da página que passa a ser a página i+1. Permutação completa. */
export async function editorReorderPages(input: { collectionId: string; order: number[] }): Promise<{ ok: true; changed: boolean } | PageFail> {
  if (!enabled()) return { ok: false, reason: "disabled" };
  const order = Array.isArray(input?.order) ? input.order : null;
  if (!isCollectionId(input?.collectionId) || !order || order.length < 1 || order.length > 10000) return { ok: false, reason: "invalid" };
  const payload = reorderPayload(order.map((pageNumber) => ({ pageNumber })), order.length);
  if (!payload) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("editor_reorder_binder_pages", { p_collection_id: input.collectionId, p_page_numbers_ordered: payload });
  if (error) return pageFail("editor_reorder_binder_pages", startedAt, error);
  if (!Array.isArray(data) || data.length !== payload.length) return pageFail("editor_reorder_binder_pages", startedAt, null);
  const changed = reorderChanged(payload);
  done("editor_reorder_binder_pages", startedAt, input.collectionId, changed ? "PAGES_REORDERED" : "UNCHANGED");
  return { ok: true, changed };
}

// ---------------------------------------------------------------------------
// V1-13 · E2-3B — abrir e fechar espaço pelo EDITOR (5385), por POSIÇÃO. Uma
// chamada por pedido, sem repetição; `hint`/`details` nunca são lidos.

type GapEditorFail = { ok: false; reason: EditorGapFailure };

function gapEditorFail(fn: string, startedAt: number, error: { code?: string; message?: string } | null): GapEditorFail {
  const reason = classifyEditorGapFailure(error?.code, error?.message);
  console.error(JSON.stringify({ scope: "colecoes.editor_binder", fn, ms: Date.now() - startedAt, code: error?.code ?? "BAD_SHAPE", reason }));
  return { ok: false, reason };
}

/** Prévia (não grava): plano e token da 5385 para o bolso nesta posição. */
export async function editorPreviewGap(input: { collectionId: string; position: PocketPosition }): Promise<{ ok: true; preview: GapPreview } | GapEditorFail> {
  if (!enabled()) return { ok: false, reason: "disabled" };
  if (!isCollectionId(input?.collectionId) || !isPocketPosition(input.position)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("editor_preview_binder_insert_gap", {
    p_collection_id: input.collectionId,
    p_page: input.position.page,
    p_row: input.position.row,
    p_column: input.position.column,
  });
  if (error) return gapEditorFail("editor_preview_binder_insert_gap", startedAt, error);
  const preview = parseEditorGapPreview(data);
  if (!preview) return gapEditorFail("editor_preview_binder_insert_gap", startedAt, null);
  return { ok: true, preview };
}

/** Abre o espaço com o token da prévia; outra página e página nova só com a confirmação já dada. */
export async function editorInsertGap(input: {
  collectionId: string;
  position: PocketPosition;
  planToken: string;
  confirmCrossPage: boolean;
  confirmAddPage: boolean;
}): Promise<{ ok: true; result: EditorGapInsert } | GapEditorFail> {
  if (!enabled()) return { ok: false, reason: "disabled" };
  if (!isCollectionId(input?.collectionId) || !isPocketPosition(input.position) || !isGapPlanToken(input.planToken)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("editor_insert_binder_gap", {
    p_collection_id: input.collectionId,
    p_page: input.position.page,
    p_row: input.position.row,
    p_column: input.position.column,
    p_plan_token: input.planToken,
    p_confirm_cross_page: input.confirmCrossPage === true,
    p_confirm_add_page: input.confirmAddPage === true,
  });
  if (error) return gapEditorFail("editor_insert_binder_gap", startedAt, error);
  const result = parseEditorGapInsert(data, input.position);
  if (!result) return gapEditorFail("editor_insert_binder_gap", startedAt, null);
  done("editor_insert_binder_gap", startedAt, input.collectionId, result.outcome);
  return { ok: true, result };
}

/** Desfaz um espaço aberto (token u1), se o trecho ainda está como a abertura o deixou. */
export async function editorCloseGap(input: { collectionId: string; undo: EditorGapUndo }): Promise<{ ok: true; movedPockets: number; pageRemoved: boolean } | GapEditorFail> {
  if (!enabled()) return { ok: false, reason: "disabled" };
  const undo = input?.undo;
  if (
    !isCollectionId(input?.collectionId) ||
    !undo ||
    !isPocketPosition(undo.gap) ||
    !isPocketPosition(undo.end) ||
    !isGapUndoToken(undo.undoToken) ||
    (undo.addedPageNumber !== null && !(Number.isInteger(undo.addedPageNumber) && undo.addedPageNumber >= 1))
  ) {
    return { ok: false, reason: "invalid" };
  }
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("editor_close_binder_gap", {
    p_collection_id: input.collectionId,
    p_gap_page: undo.gap.page,
    p_gap_row: undo.gap.row,
    p_gap_column: undo.gap.column,
    p_end_page: undo.end.page,
    p_end_row: undo.end.row,
    p_end_column: undo.end.column,
    p_undo_token: undo.undoToken,
    p_added_page_number: undo.addedPageNumber,
  });
  if (error) return gapEditorFail("editor_close_binder_gap", startedAt, error);
  const result = parseEditorGapClose(data);
  if (!result) return gapEditorFail("editor_close_binder_gap", startedAt, null);
  done("editor_close_binder_gap", startedAt, input.collectionId, "CLOSED");
  return { ok: true, ...result };
}
