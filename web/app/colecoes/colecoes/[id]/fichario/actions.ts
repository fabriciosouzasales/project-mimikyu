"use server";

import { revalidatePath } from "next/cache";
import {
  ADD_PAGES_MAX,
  BINDER_PLAN_TOKEN,
  SLOT_BATCH_MAX,
  type BinderFailure,
  type SlotFailure,
  type BinderPage,
  type BinderPreview,
  type ExtraPolicy,
  binderHref,
  classifyBinderFailure,
  classifySlotFailure,
  isBinderModelKey,
  isExtraPolicy,
  modelByKey,
  parseBinderPreview,
  readBatchStart,
} from "@/lib/colecoes/binder";
import { getMyBinderJoinCandidates, getMyBinderTransferContext, getMyCollectionBinderPages } from "@/lib/colecoes/binder-queries";
import {
  DISMANTLE_TOKEN,
  type BinderLifecycleFailure,
  type BinderLifecyclePreview,
  type DismantleResult,
  type TransferCandidate,
  classifyBinderLifecycleFailure,
  parseDismantlePreview,
  parseDismantleResult,
  transferCandidates,
} from "@/lib/colecoes/binder-lifecycle";
import {
  AVAILABLE_PAGE_SIZE,
  DETACH_TOKEN,
  type AttachOutcome,
  type AvailableCard,
  type AvailableOrigin,
  type DetachPreview,
  type DetachResult,
  type JoinCandidate,
  type ShareFailure,
  classifyShareFailure,
  isAvailableOrigin,
  parseAttachOutcome,
  parseAvailableCards,
  parseDetachPreview,
  parseDetachResult,
} from "@/lib/colecoes/binder-share";
import {
  type ImageFailure,
  type SetImageResult,
  type SlotImageSummary,
  classifyImageFailure,
  isSlotImagePath,
  parseClearResult,
  parseFocusResult,
  parseImageSummary,
  parseSetImageResult,
  parseUnlinked,
} from "@/lib/colecoes/binder-images";
import {
  type GapFailure,
  type GapInsertResult,
  type GapPreview,
  classifyGapFailure,
  isPlanToken,
  isUndoToken,
  parseGapClose,
  parseGapInsert,
  parseGapPreview,
} from "@/lib/colecoes/binder-insert";
import {
  type MergeResult,
  type RegionFailure,
  type RegionImageResult,
  classifyRegionFailure,
  parseMergeResult,
  parseRegionFocusResult,
  parseRegionImageResult,
  parseSeparateResult,
} from "@/lib/colecoes/binder-region";
import {
  type BinderOccupancy,
  type BinderParticipant,
  type IdentityFailure,
  type BinderProgressInput,
  classifyIdentityFailure,
  normalizeBinderName,
  parseBinderOccupancy,
  parseBinderParticipants,
  parseIdentityWrite,
} from "@/lib/colecoes/binder-identity";
import {
  type TransferFailure,
  type TransferOutcome,
  classifyTransferFailure,
  parseTransferOutcome,
} from "@/lib/colecoes/binder-location";
import {
  type SpeciesFailure,
  type SpeciesReferencePreview,
  type SpeciesReferenceState,
  classifySpeciesFailure,
  isSpeciesPlanToken,
  parseSpeciesPreview,
  parseSpeciesReferenceState,
} from "@/lib/colecoes/binder-species";
import {
  CATALOG_ITEM_LIMIT,
  type CatalogApplyResult,
  type CatalogFailure,
  type CatalogNoveltyState,
  type CatalogPreview,
  classifyCatalogFailure,
  isCatalogItemKey,
  isCatalogPlanToken,
  parseCatalogApply,
  parseCatalogNovelties,
  parseCatalogPreview,
} from "@/lib/colecoes/binder-catalog";
import {
  type PageRemovalBlocker,
  type PageRemovalFailure,
  classifyPageRemovalFailure,
  pageRemovalBlockers,
} from "@/lib/colecoes/binder-page-removal";
import {
  ACTIVITY_FILTERS,
  ACTIVITY_PAGE_SIZE,
  type ActivityCoverage,
  type ActivityCursor,
  type ActivityEvent,
  type ActivityFailure,
  type ActivityFilterKey,
  classifyActivityFailure,
  filterCategories,
  isCursor,
  parseActivityCoverage,
  parseActivityPage,
} from "@/lib/colecoes/binder-activity";
import { collectionHref, isCollectionId } from "@/lib/colecoes/colecoes";
import { getMyCollectionsByIds } from "@/lib/colecoes/colecoes-queries";
import { createClient } from "@/lib/supabase/server";

/**
 * Fichário Digital (P2-B) — ações do servidor. Só os contratos LIVE da 5223
 * (leitura) e da 5224 (prévia e montagem), com a sessão do colecionador;
 * nunca `service_role`, nunca tabela direta. A autorização é do banco.
 */

type Fail = { ok: false; reason: BinderFailure };

function fail(fn: string, startedAt: number, error: { code?: string; message?: string } | null): Fail {
  const reason = classifyBinderFailure(error?.code, error?.message);
  // Sem dados do usuário no log: função, duração, código e classe.
  console.error(JSON.stringify({ scope: "colecoes.binder", fn, ms: Date.now() - startedAt, code: error?.code ?? "NO_DATA", reason }));
  return { ok: false, reason };
}

/** Lote de até quatro páginas (alinhado em 1, 5, 9…) para a navegação no cliente. Só leitura. */
export async function readBinderPages(input: {
  collectionId: string;
  page: number;
  /** Fichário de Pokédex (ou convidada): também lê as referências de espécie (5259). */
  speciesReferences?: boolean;
}): Promise<{ ok: true; firstPage: number; pages: BinderPage[] } | Fail> {
  if (!isCollectionId(input?.collectionId) || !Number.isInteger(input.page) || input.page < 1 || input.page > 100_000) {
    return { ok: false, reason: "invalid" };
  }
  const firstPage = readBatchStart(input.page);
  const supabase = await createClient();
  const pages = await getMyCollectionBinderPages(supabase, input.collectionId, firstPage, { speciesReferences: input.speciesReferences === true });
  if (pages === undefined) return { ok: false, reason: "not_found" };
  if (pages === null) return { ok: false, reason: "unknown" };
  return { ok: true, firstPage, pages };
}

/**
 * Prévia da montagem (5224, não grava): contagens, adicionais por categoria,
 * amostra da página 1 e o `plan_token` que a montagem exige.
 */
export async function previewBinder(input: {
  collectionId: string;
  model: string;
  extraPolicy: ExtraPolicy;
}): Promise<{ ok: true; preview: BinderPreview } | Fail> {
  if (!isCollectionId(input?.collectionId) || !isBinderModelKey(input.model) || !isExtraPolicy(input.extraPolicy)) {
    return { ok: false, reason: "invalid" };
  }
  const model = modelByKey(input.model);
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("preview_my_collection_binder", {
    p_collection_id: input.collectionId,
    p_grid_columns: model.columns,
    p_grid_rows: model.rows,
    p_extra_policy: input.extraPolicy,
  });
  if (error) return fail("preview_my_collection_binder", startedAt, error);
  const preview = Array.isArray(data) && data.length === 1 ? parseBinderPreview(data[0]) : null;
  if (!preview) return fail("preview_my_collection_binder", startedAt, { code: "BAD_SHAPE" });
  console.info(JSON.stringify({ scope: "colecoes.binder_preview", ms: Date.now() - startedAt, pages: preview.pagesTotal }));
  return { ok: true, preview };
}

/**
 * Monta o fichário (5224), numa transação só, com exatamente o modelo, a
 * opção e o `plan_token` que o colecionador viu. O banco recalcula sob a
 * trava da coleção e recusa (`PLAN_CHANGED`) se algo mudou — a interface
 * então exige uma nova prévia; nada é criado em silêncio.
 */
export async function createBinder(input: {
  collectionId: string;
  model: string;
  extraPolicy: ExtraPolicy;
  planToken: string;
}): Promise<{ ok: true; outcome: "CREATED" | "ALREADY_EXISTS"; pages: number } | Fail> {
  if (
    !isCollectionId(input?.collectionId) ||
    !isBinderModelKey(input.model) ||
    !isExtraPolicy(input.extraPolicy) ||
    typeof input.planToken !== "string" ||
    !BINDER_PLAN_TOKEN.test(input.planToken)
  ) {
    return { ok: false, reason: "invalid" };
  }
  const model = modelByKey(input.model);
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("create_my_collection_binder", {
    p_collection_id: input.collectionId,
    p_grid_columns: model.columns,
    p_grid_rows: model.rows,
    p_extra_policy: input.extraPolicy,
    p_plan_token: input.planToken,
  });
  if (error) return fail("create_my_collection_binder", startedAt, error);
  const row = Array.isArray(data) ? (data[0] as Record<string, unknown> | undefined) : undefined;
  const outcome = row?.outcome;
  const pages = Number(row?.pages_created);
  if ((outcome !== "CREATED" && outcome !== "ALREADY_EXISTS") || !Number.isInteger(pages) || pages < 0) {
    // Resultado desconhecido: a interface relê o cabeçalho antes de qualquer nova tentativa.
    return fail("create_my_collection_binder", startedAt, { code: "BAD_SHAPE" });
  }
  console.info(JSON.stringify({ scope: "colecoes.binder_create", ms: Date.now() - startedAt, outcome, pages }));
  revalidatePath(binderHref(input.collectionId));
  revalidatePath(collectionHref(input.collectionId));
  return { ok: true, outcome, pages };
}

// ---------------------------------------------------------------------------
// Organização do fichário (P2-B-UX-CORRECTION-01) — só os contratos LIVE da
// Binder Foundation (5128–5133), com a sessão do colecionador. O banco valida
// dono, coleção ativa, cadeado e mesmo fichário; aqui só o formato do pedido.
// A Bandeja é estado da tela: "bolso A → Bandeja → bolso B" vira UMA chamada
// de mover (C-45/LDM-36). Nada aqui grava sem um gesto explícito.
// ---------------------------------------------------------------------------

type SlotFail = { ok: false; reason: SlotFailure };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function isUuid(value: unknown): value is string {
  return typeof value === "string" && UUID.test(value);
}

function slotIdsOk(ids: unknown): ids is string[] {
  return Array.isArray(ids) && ids.length > 0 && ids.length <= SLOT_BATCH_MAX && ids.every(isUuid) && new Set(ids).size === ids.length;
}

function slotFail(fn: string, startedAt: number, error: { code?: string; message?: string } | null): SlotFail {
  const reason = classifySlotFailure(error?.code, error?.message);
  console.error(JSON.stringify({ scope: "colecoes.binder_slot", fn, ms: Date.now() - startedAt, code: error?.code ?? "NO_DATA", reason }));
  return { ok: false, reason };
}

function slotDone(fn: string, startedAt: number, collectionId: string, extra: Record<string, unknown> = {}) {
  console.info(JSON.stringify({ scope: "colecoes.binder_slot", fn, ms: Date.now() - startedAt, ...extra }));
  // A página da coleção mostra o resumo do fichário; a área de trabalho já
  // reflete a mudança no cliente e relê o lote afetado.
  revalidatePath(collectionHref(collectionId));
}

/** Mover (bolso vazio) ou trocar (bolso ocupado) — 5132, atômico. */
export async function moveSlot(input: {
  collectionId: string;
  fromSlotId: string;
  toSlotId: string;
}): Promise<{ ok: true; operation: "MOVE" | "SWAP" } | SlotFail> {
  if (!isCollectionId(input?.collectionId) || !isUuid(input.fromSlotId) || !isUuid(input.toSlotId) || input.fromSlotId === input.toSlotId) {
    return { ok: false, reason: "invalid" };
  }
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("move_slot_assignment", { p_from_slot_id: input.fromSlotId, p_to_slot_id: input.toSlotId });
  if (error) return slotFail("move_slot_assignment", startedAt, error);
  const operation = Array.isArray(data) ? (data[0] as Record<string, unknown> | undefined)?.operation : undefined;
  if (operation !== "MOVE" && operation !== "SWAP") return slotFail("move_slot_assignment", startedAt, { code: "BAD_SHAPE" });
  slotDone("move_slot_assignment", startedAt, input.collectionId, { operation });
  return { ok: true, operation };
}

/** Tirar cartas do fichário (5133). A carta continua na coleção; só sai do bolso. */
export async function removeSlots(input: { collectionId: string; slotIds: string[] }): Promise<{ ok: true; count: number } | SlotFail> {
  if (!isCollectionId(input?.collectionId) || !slotIdsOk(input.slotIds)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("remove_slot_assignment", { p_slot_ids: input.slotIds });
  if (error) return slotFail("remove_slot_assignment", startedAt, error);
  const count = Number(data);
  if (!Number.isInteger(count) || count < 0) return slotFail("remove_slot_assignment", startedAt, { code: "BAD_SHAPE" });
  slotDone("remove_slot_assignment", startedAt, input.collectionId, { count });
  return { ok: true, count };
}

/**
 * Desfazer a retirada: devolve o mesmo EXEMPLAR ao mesmo bolso (5250, pelo
 * exemplar — vale também para carta sem coleção). O banco revalida local
 * físico, cadeado e dono.
 */
export async function restoreToSlot(input: {
  collectionId: string;
  slotId: string;
  physicalCardId: string;
}): Promise<{ ok: true } | SlotFail> {
  if (!isCollectionId(input?.collectionId) || !isUuid(input.slotId) || !isUuid(input.physicalCardId)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { error } = await supabase.rpc("place_my_physical_card_in_slot", {
    p_collection_id: input.collectionId,
    p_slot_id: input.slotId,
    p_physical_card_id: input.physicalCardId,
  });
  if (error) return slotFail("place_my_physical_card_in_slot", startedAt, error);
  slotDone("place_my_physical_card_in_slot", startedAt, input.collectionId, { undo: true });
  return { ok: true };
}

/** Fixar ou soltar bolsos (5130). Bolso fixado não aceita mover, trocar nem retirar. */
export async function setSlotsLock(input: {
  collectionId: string;
  slotIds: string[];
  locked: boolean;
}): Promise<{ ok: true; count: number } | SlotFail> {
  if (!isCollectionId(input?.collectionId) || !slotIdsOk(input.slotIds) || typeof input.locked !== "boolean") return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("set_slot_lock", { p_slot_ids: input.slotIds, p_locked: input.locked });
  if (error) return slotFail("set_slot_lock", startedAt, error);
  const count = Number(data);
  if (!Number.isInteger(count) || count < 0) return slotFail("set_slot_lock", startedAt, { code: "BAD_SHAPE" });
  slotDone("set_slot_lock", startedAt, input.collectionId, { count, locked: input.locked });
  return { ok: true, count };
}

/**
 * Reservar o bolso para a carta que está nele (5128, granularidade carta +
 * acabamento — a mesma da montagem). Se a carta sair, o bolso fica guardado
 * para ela.
 */
export async function reserveSlot(input: {
  collectionId: string;
  slotId: string;
  cardId: string;
  variantTypeId: string | null;
}): Promise<{ ok: true } | SlotFail> {
  if (
    !isCollectionId(input?.collectionId) ||
    !isUuid(input.slotId) ||
    !isUuid(input.cardId) ||
    (input.variantTypeId !== null && !isUuid(input.variantTypeId))
  ) {
    return { ok: false, reason: "invalid" };
  }
  const startedAt = Date.now();
  const supabase = await createClient();
  const { error } = await supabase.rpc("set_slot_expected_content", {
    p_slot_id: input.slotId,
    p_card_id: input.cardId,
    p_card_variant_id: null,
    p_expected_variant_type_id: input.variantTypeId,
  });
  if (error) return slotFail("set_slot_expected_content", startedAt, error);
  slotDone("set_slot_expected_content", startedAt, input.collectionId);
  return { ok: true };
}

/** Liberar reservas (5129). A carta no bolso, se houver, continua lá. */
export async function clearReservations(input: { collectionId: string; slotIds: string[] }): Promise<{ ok: true; count: number } | SlotFail> {
  if (!isCollectionId(input?.collectionId) || !slotIdsOk(input.slotIds)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("clear_slot_expected_content", { p_slot_ids: input.slotIds });
  if (error) return slotFail("clear_slot_expected_content", startedAt, error);
  const count = Number(data);
  if (!Number.isInteger(count) || count < 0) return slotFail("clear_slot_expected_content", startedAt, { code: "BAD_SHAPE" });
  slotDone("clear_slot_expected_content", startedAt, input.collectionId, { count });
  return { ok: true, count };
}

/**
 * Reordenar as páginas do fichário (5127 `reorder_layout_pages`, Binder
 * Foundation, LIVE). O contrato exige o conjunto COMPLETO de páginas na nova
 * ordem; o banco valida dono, coleção ativa, cardinalidade, duplicados e
 * pertencimento sob trava, e só muda `page_number` (identidade, bolsos,
 * cartas e reservas acompanham a página — C-39).
 */
export async function reorderPages(input: {
  collectionId: string;
  layoutId: string;
  pageIds: string[];
}): Promise<{ ok: true; count: number } | SlotFail> {
  if (
    !isCollectionId(input?.collectionId) ||
    !isUuid(input.layoutId) ||
    !Array.isArray(input.pageIds) ||
    input.pageIds.length === 0 ||
    input.pageIds.length > 10_000 ||
    !input.pageIds.every(isUuid) ||
    new Set(input.pageIds).size !== input.pageIds.length
  ) {
    return { ok: false, reason: "invalid" };
  }
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("reorder_layout_pages", { p_layout_id: input.layoutId, p_page_ids_ordered: input.pageIds });
  if (error) return slotFail("reorder_layout_pages", startedAt, error);
  const count = Array.isArray(data) ? data.length : 0;
  if (count !== input.pageIds.length) return slotFail("reorder_layout_pages", startedAt, { code: "BAD_SHAPE" });
  slotDone("reorder_layout_pages", startedAt, input.collectionId, { count });
  revalidatePath(binderHref(input.collectionId));
  return { ok: true, count };
}

// ---------------------------------------------------------------------------
// Remover página (remove_layout_page 5235/5260/5281/5285). O banco recusa,
// sob trava, página com carta, reserva, imagem e imagem em 2 bolsos; com
// p_confirm_species_references = 0 também recusa referência de espécie. Bolso
// fixado e mínimo de páginas o contrato NÃO cobre: são conferidos aqui, no
// servidor, com uma leitura fresca da própria página (nunca com o estado do
// cliente). O Histórico grava E14 no próprio banco.
// ---------------------------------------------------------------------------

type PageRemovalFail = { ok: false; reason: PageRemovalFailure; blockers: PageRemovalBlocker[] };

function pageRemovalFail(
  fn: string,
  startedAt: number,
  error: { code?: string; message?: string; hint?: string } | null,
): PageRemovalFail {
  const { reason, blocker } = classifyPageRemovalFailure(error?.code, error?.message, error?.hint);
  console.error(JSON.stringify({ scope: "colecoes.binder_page", fn, ms: Date.now() - startedAt, code: error?.code ?? "NO_DATA", reason }));
  return { ok: false, reason, blockers: blocker ? [blocker] : [] };
}

export async function removePage(input: {
  collectionId: string;
  pageId: string;
  /** Número que o cliente viu: a leitura fresca precisa achar o mesmo id nesse número (senão o fichário mudou). */
  pageNumber: number;
}): Promise<{ ok: true; pageNumber: number; totalBefore: number; totalAfter: number } | PageRemovalFail> {
  if (!isCollectionId(input?.collectionId) || !isUuid(input.pageId) || !Number.isInteger(input.pageNumber) || input.pageNumber < 1 || input.pageNumber > 100_000) {
    return { ok: false, reason: "invalid", blockers: [] };
  }
  const startedAt = Date.now();
  const supabase = await createClient();

  // 1) Total de páginas (mínimo) — leitura do dono (5246).
  const occupancyRead = await supabase.rpc("get_my_binder_occupancy", { p_collection_id: input.collectionId });
  if (occupancyRead.error) return pageRemovalFail("get_my_binder_occupancy", startedAt, occupancyRead.error);
  const occupancy = parseBinderOccupancy(occupancyRead.data);
  if (occupancy === "absent" || !occupancy) return pageRemovalFail("get_my_binder_occupancy", startedAt, { code: "NO_BINDER", message: "not found or not owned" });

  // 2) Leitura fresca do lote da página (bolsos, imagens, mesclagens e referências de espécie).
  const pages = await getMyCollectionBinderPages(supabase, input.collectionId, readBatchStart(input.pageNumber), { speciesReferences: true });
  if (pages === undefined) return { ok: false, reason: "stale", blockers: [] };
  if (pages === null) return { ok: false, reason: "unknown", blockers: [] };
  const page = pages.find((p) => p.pageNumber === input.pageNumber);
  if (!page || page.pageId !== input.pageId) return { ok: false, reason: "stale", blockers: [] };

  // 3) Elegibilidade pelos dados (inclui fixação e mínimo, que o contrato não cobre).
  const blockers = pageRemovalBlockers(page, occupancy.pages);
  if (blockers.length > 0) {
    console.info(JSON.stringify({ scope: "colecoes.binder_page", fn: "remove_page_precheck", ms: Date.now() - startedAt, blocked: blockers }));
    return { ok: false, reason: "blocked", blockers };
  }

  // 4) Remoção (0 referências confirmadas: qualquer referência faz o banco recusar).
  const { error } = await supabase.rpc("remove_layout_page", { p_page_id: input.pageId, p_confirm_species_references: 0 });
  if (error) return pageRemovalFail("remove_layout_page", startedAt, error);
  console.info(JSON.stringify({ scope: "colecoes.binder_page", fn: "remove_layout_page", ms: Date.now() - startedAt, page: input.pageNumber, total: occupancy.pages }));
  revalidatePath(binderHref(input.collectionId));
  revalidatePath(collectionHref(input.collectionId));
  return { ok: true, pageNumber: input.pageNumber, totalBefore: occupancy.pages, totalAfter: occupancy.pages - 1 };
}

// ---------------------------------------------------------------------------
// Fichário compartilhado (P2-SHARED-BINDER-FRONTEND-01) — contratos LIVE
// 5229/5230, com a sessão do colecionador. Associar e desassociar só com um
// gesto explícito de confirmação na interface; nada aqui associa sozinho.
// ---------------------------------------------------------------------------

type ShareFail = { ok: false; reason: ShareFailure };

function shareFail(fn: string, startedAt: number, error: { code?: string; message?: string } | null): ShareFail {
  const reason = classifyShareFailure(error?.code, error?.message);
  console.error(JSON.stringify({ scope: "colecoes.binder_share", fn, ms: Date.now() - startedAt, code: error?.code ?? "NO_DATA", reason }));
  return { ok: false, reason };
}

/** Fichários existentes que a coleção pode usar (5230, só leitura). */
export async function listJoinCandidates(input: { collectionId: string }): Promise<{ ok: true; candidates: JoinCandidate[] } | ShareFail> {
  if (!isCollectionId(input?.collectionId)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const candidates = await getMyBinderJoinCandidates(supabase, input.collectionId);
  if (candidates === undefined) return shareFail("list_my_binder_join_candidates", startedAt, { code: "P0002" });
  if (candidates === null) return { ok: false, reason: "unknown" };
  return { ok: true, candidates };
}

/**
 * Associa a coleção, como convidada, ao fichário de outra coleção do mesmo
 * dono (5229). Não move nem posiciona nada: a organização atual é preservada
 * e as cartas desta coleção ficam em "Cartas disponíveis".
 */
export async function attachToBinder(input: { collectionId: string; layoutId: string }): Promise<{ ok: true; outcome: AttachOutcome } | ShareFail> {
  if (!isCollectionId(input?.collectionId) || !isUuid(input.layoutId)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("attach_my_collection_to_binder", { p_collection_id: input.collectionId, p_layout_id: input.layoutId });
  if (error) return shareFail("attach_my_collection_to_binder", startedAt, error);
  const outcome = parseAttachOutcome(data);
  // Resultado desconhecido: a interface relê o cabeçalho; nunca anuncia sucesso.
  if (!outcome) return shareFail("attach_my_collection_to_binder", startedAt, { code: "BAD_SHAPE" });
  console.info(JSON.stringify({ scope: "colecoes.binder_attach", ms: Date.now() - startedAt, outcome }));
  revalidatePath(binderHref(input.collectionId));
  revalidatePath(collectionHref(input.collectionId));
  return { ok: true, outcome };
}

/**
 * "Cartas disponíveis": exemplares GUARDADOS no fichário físico e ainda sem
 * bolso, de qualquer origem (5252, paginado). `origin` só recorta a lista
 * (Todas · Desta coleção · Outras coleções · Sem coleção); a elegibilidade é
 * sempre o local físico. `originCollectionId` recorta (no servidor, com total
 * e paginação corretos) os exemplares de uma coleção — bolso reservado por
 * outra coleção do fichário.
 */
export async function readAvailableCards(input: {
  collectionId: string;
  offset: number;
  origin?: AvailableOrigin;
  originCollectionId?: string | null;
}): Promise<{ ok: true; items: AvailableCard[]; total: number } | ShareFail> {
  const origin = input?.origin ?? "ALL";
  const originCollectionId = input?.originCollectionId ?? null;
  if (
    !isCollectionId(input?.collectionId) ||
    !Number.isInteger(input.offset) ||
    input.offset < 0 ||
    input.offset > 1_000_000 ||
    !isAvailableOrigin(origin) ||
    (originCollectionId !== null && !isCollectionId(originCollectionId))
  ) {
    return { ok: false, reason: "invalid" };
  }
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_my_collection_binder_unplaced", {
    p_collection_id: input.collectionId,
    p_limit: AVAILABLE_PAGE_SIZE,
    p_offset: input.offset,
    p_origin: origin,
    p_origin_collection_id: originCollectionId,
  });
  if (error) return shareFail("get_my_collection_binder_unplaced", startedAt, error);
  const parsed = parseAvailableCards(data);
  if (!parsed) return shareFail("get_my_collection_binder_unplaced", startedAt, { code: "BAD_SHAPE" });
  return { ok: true, items: parsed.items, total: parsed.total };
}

/**
 * Posiciona um exemplar disponível num bolso (5250
 * `place_my_physical_card_in_slot`). A interface só oferece bolsos vazios e
 * soltos; o banco revalida dono, local físico do exemplar, coleção aberta
 * ativa e cadeado. Não altera coleção, alocação nem valor.
 */
export async function placeAvailableCard(input: {
  collectionId: string;
  slotId: string;
  physicalCardId: string;
}): Promise<{ ok: true; operation: "ADD" | "REPLACE" | "UNCHANGED" } | SlotFail> {
  if (!isCollectionId(input?.collectionId) || !isUuid(input.slotId) || !isUuid(input.physicalCardId)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("place_my_physical_card_in_slot", {
    p_collection_id: input.collectionId,
    p_slot_id: input.slotId,
    p_physical_card_id: input.physicalCardId,
  });
  if (error) return slotFail("place_my_physical_card_in_slot", startedAt, error);
  const operation = Array.isArray(data) ? (data[0] as Record<string, unknown> | undefined)?.operation : undefined;
  if (operation !== "ADD" && operation !== "REPLACE" && operation !== "UNCHANGED") {
    return slotFail("place_my_physical_card_in_slot", startedAt, { code: "BAD_SHAPE" });
  }
  slotDone("place_my_physical_card_in_slot", startedAt, input.collectionId, { operation });
  return { ok: true, operation };
}

/**
 * Passa a âncora do fichário da coleção proprietária para outra coleção ativa
 * do mesmo usuário (5254). Nada no fichário muda (bolsos, posições, imagens,
 * travas, nome, local); a antiga proprietária vira convidada. Caminho seguro
 * antes de excluir a proprietária. Exposto em "Gerenciar fichário" (V1-05).
 */
export async function transferBinderOwnership(input: {
  fromCollectionId: string;
  toCollectionId: string;
}): Promise<{ ok: true; result: TransferOutcome } | { ok: false; reason: TransferFailure }> {
  if (!isCollectionId(input?.fromCollectionId) || !isCollectionId(input?.toCollectionId) || input.fromCollectionId === input.toCollectionId) {
    return { ok: false, reason: "invalid" };
  }
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("transfer_my_binder_ownership", {
    p_from_collection_id: input.fromCollectionId,
    p_to_collection_id: input.toCollectionId,
  });
  const result = error ? null : parseTransferOutcome(data);
  if (!result) {
    const reason = error ? classifyTransferFailure(error.code, error.message) : "unknown";
    console.error(JSON.stringify({ scope: "colecoes.binder_transfer", ms: Date.now() - startedAt, code: error?.code ?? "BAD_SHAPE", reason }));
    return { ok: false, reason };
  }
  console.info(JSON.stringify({ scope: "colecoes.binder_transfer", ms: Date.now() - startedAt, outcome: result.outcome }));
  for (const id of [input.fromCollectionId, input.toCollectionId]) {
    revalidatePath(binderHref(id));
    revalidatePath(collectionHref(id));
  }
  return { ok: true, result };
}

// ---------------------------------------------------------------------------
// Ciclo de vida do fichário (V1-05): desmontar (E19, 5294), excluir vazio
// (E19b, 5293) e destinos da transferência (E20, 5254). Só contratos LIVE,
// com a sessão do colecionador; a autorização é do banco.
// ---------------------------------------------------------------------------

type LifecycleFail = { ok: false; reason: BinderLifecycleFailure };

function lifecycleFail(fn: string, startedAt: number, error: { code?: string; message?: string } | null): LifecycleFail {
  const reason = classifyBinderLifecycleFailure(error?.code, error?.message);
  // Sem dados do usuário no log: função, duração, código e classe.
  console.error(JSON.stringify({ scope: "colecoes.binder_lifecycle", fn, ms: Date.now() - startedAt, code: error?.code ?? "NO_DATA", reason }));
  return { ok: false, reason };
}

/**
 * Estado para o bloco "Gerenciar fichário": prévia da desmontagem (5242, não
 * grava) e, para a coleção principal, os destinos válidos da transferência.
 * `candidates: null` = leitura dos destinos falhou (a prévia continua valendo).
 */
export async function readBinderLifecycle(input: {
  collectionId: string;
  layoutId: string;
}): Promise<{ ok: true; preview: BinderLifecyclePreview; candidates: TransferCandidate[] | null } | LifecycleFail> {
  if (!isCollectionId(input?.collectionId) || !isCollectionId(input?.layoutId)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const [previewRead, context] = await Promise.all([
    supabase.rpc("preview_my_collection_binder_dismantle", { p_collection_id: input.collectionId }),
    getMyBinderTransferContext(supabase),
  ]);
  if (previewRead.error) return lifecycleFail("preview_my_collection_binder_dismantle", startedAt, previewRead.error);
  const preview = parseDismantlePreview(previewRead.data);
  if (!preview) return lifecycleFail("preview_my_collection_binder_dismantle", startedAt, { code: "BAD_SHAPE" });
  // Só a coleção principal deste fichário transfere; o layout informado precisa ser o da prévia.
  const isOwner = preview.hasBinder && preview.layoutId?.toLowerCase() === input.layoutId.toLowerCase();
  const candidates =
    isOwner && context
      ? transferCandidates({ currentCollectionId: input.collectionId, layoutId: input.layoutId, active: context.active, binderOwners: context.binderOwners, guestOf: context.guestOf })
      : isOwner
        ? null
        : [];
  return { ok: true, preview, candidates };
}

/**
 * Desmonta o fichário (5294) com o token da prévia que a pessoa revisou.
 * Apaga páginas, bolsos, posições, reservas, mesclagens, imagens e o fichário;
 * cartas físicas, acervo, alocações e progresso não mudam. Devolve os
 * caminhos das imagens removidas — o cliente apaga os arquivos depois.
 */
export async function dismantleBinder(input: { collectionId: string; token: string }): Promise<{ ok: true; result: DismantleResult } | LifecycleFail> {
  if (!isCollectionId(input?.collectionId) || typeof input.token !== "string" || !DISMANTLE_TOKEN.test(input.token)) {
    return { ok: false, reason: "invalid" };
  }
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("dismantle_my_collection_binder", {
    p_collection_id: input.collectionId,
    p_dismantle_token: input.token,
  });
  if (error) return lifecycleFail("dismantle_my_collection_binder", startedAt, error);
  const result = parseDismantleResult(data);
  if (!result) return lifecycleFail("dismantle_my_collection_binder", startedAt, { code: "BAD_SHAPE" });
  console.info(JSON.stringify({ scope: "colecoes.binder_lifecycle", fn: "dismantle_my_collection_binder", ms: Date.now() - startedAt, outcome: result.outcome, images: result.images }));
  revalidatePath(binderHref(input.collectionId));
  revalidatePath(collectionHref(input.collectionId));
  return { ok: true, result };
}

/**
 * Exclui o fichário vazio (5293): só sem páginas, de coleção ativa da própria
 * sessão; com convidadas o banco recusa. Nada além do fichário vazio muda.
 */
export async function deleteEmptyBinder(input: { collectionId: string; layoutId: string }): Promise<{ ok: true } | LifecycleFail> {
  if (!isCollectionId(input?.collectionId) || !isCollectionId(input?.layoutId)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { error } = await supabase.rpc("delete_collection_layout", { p_layout_id: input.layoutId });
  if (error) return lifecycleFail("delete_collection_layout", startedAt, error);
  console.info(JSON.stringify({ scope: "colecoes.binder_lifecycle", fn: "delete_collection_layout", ms: Date.now() - startedAt }));
  revalidatePath(binderHref(input.collectionId));
  revalidatePath(collectionHref(input.collectionId));
  return { ok: true };
}

/** Prévia de sair do fichário compartilhado (5229, não grava). `preview: null` = a coleção não é convidada. */
export async function previewDetach(input: { collectionId: string }): Promise<{ ok: true; preview: DetachPreview | null } | ShareFail> {
  if (!isCollectionId(input?.collectionId)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("preview_my_collection_binder_detach", { p_collection_id: input.collectionId });
  if (error) return shareFail("preview_my_collection_binder_detach", startedAt, error);
  const preview = parseDetachPreview(data);
  if (preview === null) return shareFail("preview_my_collection_binder_detach", startedAt, { code: "BAD_SHAPE" });
  return { ok: true, preview: preview ?? null };
}

/**
 * Sai do fichário compartilhado (5229) com o token da prévia que o
 * colecionador viu. Remove só as posições e reservas desta coleção; cartas
 * físicas, alocações e progresso não mudam. Bolsos fixados afetados só são
 * soltos com `releaseLocks` explícito.
 */
export async function detachFromBinder(input: {
  collectionId: string;
  token: string;
  releaseLocks: boolean;
}): Promise<{ ok: true; result: DetachResult } | ShareFail> {
  if (!isCollectionId(input?.collectionId) || typeof input.token !== "string" || !DETACH_TOKEN.test(input.token) || typeof input.releaseLocks !== "boolean") {
    return { ok: false, reason: "invalid" };
  }
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("detach_my_collection_from_binder", {
    p_collection_id: input.collectionId,
    p_detach_token: input.token,
    p_release_locks: input.releaseLocks,
  });
  if (error) return shareFail("detach_my_collection_from_binder", startedAt, error);
  const result = parseDetachResult(data);
  if (!result) return shareFail("detach_my_collection_from_binder", startedAt, { code: "BAD_SHAPE" });
  console.info(JSON.stringify({ scope: "colecoes.binder_detach", ms: Date.now() - startedAt, outcome: result.outcome }));
  revalidatePath(binderHref(input.collectionId));
  revalidatePath(collectionHref(input.collectionId));
  return { ok: true, result };
}

// ---------------------------------------------------------------------------
// Imagem personalizada do bolso (C-198, P2-BINDER-CUSTOM-IMAGES-CLOSEOUT-
// AND-FRONTEND-01) — só os contratos LIVE 5233/5234, com a sessão do
// colecionador. O arquivo vai do navegador direto ao bucket privado (envio
// com caminho novo, nunca sobrescreve); aqui só o vínculo, o enquadramento e
// a remoção do vínculo. Apagar arquivo é sempre do cliente, depois da
// resposta do banco — e a política do bucket recusa apagar arquivo vinculado.
// ---------------------------------------------------------------------------

type ImageFail = { ok: false; reason: ImageFailure };

function imageFail(fn: string, startedAt: number, error: { code?: string; message?: string } | null): ImageFail {
  const reason = classifyImageFailure(error?.code, error?.message);
  // Sem caminhos (contêm o id do usuário) nem dados do arquivo no log.
  console.error(JSON.stringify({ scope: "colecoes.binder_image", fn, ms: Date.now() - startedAt, code: error?.code ?? "NO_DATA", reason }));
  return { ok: false, reason };
}

function imageDone(fn: string, startedAt: number, collectionId: string, extra: Record<string, unknown> = {}) {
  console.info(JSON.stringify({ scope: "colecoes.binder_image", fn, ms: Date.now() - startedAt, ...extra }));
  revalidatePath(binderHref(collectionId));
}

/**
 * Vincula ao bolso o arquivo recém-enviado (5233). `REPLACED` devolve o
 * arquivo anterior, que o cliente apaga só agora. Recusa definitiva: o
 * cliente apaga só o arquivo que acabou de enviar. Resposta incerta
 * (`unknown`): nada é apagado.
 */
export async function setSlotImage(input: {
  collectionId: string;
  slotId: string;
  path: string;
  focalY: number;
}): Promise<{ ok: true; result: SetImageResult } | ImageFail> {
  if (!isCollectionId(input?.collectionId) || !isUuid(input.slotId) || !isSlotImagePath(input.path) || !Number.isInteger(input.focalY) || input.focalY < 0 || input.focalY > 100) {
    return { ok: false, reason: "invalid" };
  }
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("set_my_binder_slot_image", {
    p_collection_id: input.collectionId,
    p_slot_id: input.slotId,
    p_storage_path: input.path,
    p_focal_y: input.focalY,
  });
  if (error) return imageFail("set_my_binder_slot_image", startedAt, error);
  const result = parseSetImageResult(data);
  if (!result || result.slotId !== input.slotId || result.path !== input.path) return imageFail("set_my_binder_slot_image", startedAt, { code: "BAD_SHAPE" });
  imageDone("set_my_binder_slot_image", startedAt, input.collectionId, { operation: result.operation });
  return { ok: true, result };
}

/** Só o enquadramento vertical (5233). Idempotente. */
export async function setSlotImageFocus(input: {
  collectionId: string;
  slotId: string;
  focalY: number;
}): Promise<{ ok: true; focalY: number } | ImageFail> {
  if (!isCollectionId(input?.collectionId) || !isUuid(input.slotId) || !Number.isInteger(input.focalY) || input.focalY < 0 || input.focalY > 100) {
    return { ok: false, reason: "invalid" };
  }
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("set_my_binder_slot_image_focus", {
    p_collection_id: input.collectionId,
    p_slot_id: input.slotId,
    p_focal_y: input.focalY,
  });
  if (error) return imageFail("set_my_binder_slot_image_focus", startedAt, error);
  const result = parseFocusResult(data);
  if (!result || result.slotId !== input.slotId) return imageFail("set_my_binder_slot_image_focus", startedAt, { code: "BAD_SHAPE" });
  imageDone("set_my_binder_slot_image_focus", startedAt, input.collectionId);
  return { ok: true, focalY: result.focalY };
}

/** Tira a imagem do bolso (5233). `REMOVED` devolve o arquivo, que o cliente apaga depois. Idempotente. */
export async function clearSlotImage(input: {
  collectionId: string;
  slotId: string;
}): Promise<{ ok: true; outcome: "REMOVED" | "ALREADY_ABSENT"; previousPath: string | null } | ImageFail> {
  if (!isCollectionId(input?.collectionId) || !isUuid(input.slotId)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("clear_my_binder_slot_image", { p_collection_id: input.collectionId, p_slot_id: input.slotId });
  if (error) return imageFail("clear_my_binder_slot_image", startedAt, error);
  const result = parseClearResult(data);
  if (!result) return imageFail("clear_my_binder_slot_image", startedAt, { code: "BAD_SHAPE" });
  imageDone("clear_my_binder_slot_image", startedAt, input.collectionId, { outcome: result.outcome });
  return { ok: true, ...result };
}

/** Quantas imagens o colecionador tem e o limite (5234, só leitura). */
export async function readSlotImageSummary(input: { collectionId: string }): Promise<{ ok: true; summary: SlotImageSummary } | ImageFail> {
  if (!isCollectionId(input?.collectionId)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_my_binder_slot_image_summary", { p_collection_id: input.collectionId });
  if (error) return imageFail("get_my_binder_slot_image_summary", startedAt, error);
  const summary = parseImageSummary(data);
  if (!summary) return imageFail("get_my_binder_slot_image_summary", startedAt, { code: "BAD_SHAPE" });
  return { ok: true, summary };
}

/**
 * Arquivos da própria pasta sem vínculo e com mais de 1 hora (5234) — envio
 * abandonado ou arquivo antigo que não chegou a ser apagado. O cliente apaga
 * pelo Storage; envios em curso nunca aparecem (carência de 1 h) e a política
 * do bucket recusa apagar o que for vinculado entre a lista e a remoção.
 */
export async function listUnlinkedSlotImages(): Promise<{ ok: true; paths: string[] } | ImageFail> {
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("list_my_unlinked_binder_slot_images", { p_limit: 50 });
  if (error) return imageFail("list_my_unlinked_binder_slot_images", startedAt, error);
  const paths = parseUnlinked(data);
  if (!paths) return imageFail("list_my_unlinked_binder_slot_images", startedAt, { code: "BAD_SHAPE" });
  return { ok: true, paths };
}

// ---------------------------------------------------------------------------
// Capacidade do fichário (P2-BINDER-CAPACITY-AND-EMPTY-SLOT-01)
// ---------------------------------------------------------------------------

/**
 * Acrescenta páginas ao FIM do fichário com `add_layout_page` (5125, LIVE).
 * Unidade do contrato: UMA página (uma face de folha), com todos os bolsos
 * do modelo atual, vazios — sem carta, reserva nem cadeado; o banco deriva
 * a grade do layout (C-39/C-40) e numera em sequência sob a trava do layout.
 * Nada existente é renumerado ou tocado. Cada página é atômica: se uma
 * falhar, as anteriores ficam e a resposta diz quantas entraram.
 */
export async function addPages(input: {
  collectionId: string;
  layoutId: string;
  count: number;
}): Promise<{ ok: true; added: number; lastPageNumber: number | null; slotsPerPage: number | null; failure: SlotFailure | null } | SlotFail> {
  if (!isCollectionId(input?.collectionId) || !isUuid(input.layoutId) || !Number.isInteger(input.count) || input.count < 1 || input.count > ADD_PAGES_MAX) {
    return { ok: false, reason: "invalid" };
  }
  const startedAt = Date.now();
  const supabase = await createClient();
  let added = 0;
  let lastPageNumber: number | null = null;
  let slotsPerPage: number | null = null;
  let failure: SlotFailure | null = null;
  for (let i = 0; i < input.count; i += 1) {
    const { data, error } = await supabase.rpc("add_layout_page", { p_layout_id: input.layoutId });
    if (error) {
      failure = slotFail("add_layout_page", startedAt, error).reason;
      break;
    }
    const row = Array.isArray(data) ? (data[0] as Record<string, unknown> | undefined) : undefined;
    const pageNumber = Number(row?.page_number);
    const slots = Number(row?.slots_created);
    if (!Number.isInteger(pageNumber) || pageNumber < 1 || !Number.isInteger(slots) || slots < 1) {
      failure = slotFail("add_layout_page", startedAt, { code: "BAD_SHAPE" }).reason;
      break;
    }
    added += 1;
    lastPageNumber = pageNumber;
    slotsPerPage = slots;
  }
  if (added === 0) return { ok: false, reason: failure ?? "unknown" };
  slotDone("add_layout_page", startedAt, input.collectionId, { added, requested: input.count });
  revalidatePath(binderHref(input.collectionId));
  return { ok: true, added, lastPageNumber, slotsPerPage, failure };
}

// ---------------------------------------------------------------------------
// Inserir espaço (proposta 5243) — prévia do banco, execução com o plan_token
// da prévia e desfazer com o undo_token. O banco é a autoridade: recalcula
// tudo sob a trava do fichário e recusa se o plano mudou.
// ---------------------------------------------------------------------------

type GapFail = { ok: false; reason: GapFailure };

function gapFail(fn: string, startedAt: number, error: { code?: string; message?: string; hint?: string } | null): GapFail {
  const reason = classifyGapFailure(error?.code, error?.message, error?.hint);
  console.error(JSON.stringify({ scope: "colecoes.binder_gap", fn, ms: Date.now() - startedAt, code: error?.code ?? "NO_DATA", reason }));
  return { ok: false, reason };
}

/** Prévia de "Inserir espaço" (não grava). */
export async function previewInsertGap(input: { collectionId: string; slotId: string }): Promise<{ ok: true; preview: GapPreview } | GapFail> {
  if (!isCollectionId(input?.collectionId) || !isUuid(input.slotId)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("preview_my_binder_insert_gap", { p_collection_id: input.collectionId, p_slot_id: input.slotId });
  if (error) return gapFail("preview_my_binder_insert_gap", startedAt, error);
  const preview = parseGapPreview(data);
  if (!preview) return gapFail("preview_my_binder_insert_gap", startedAt, { code: "BAD_SHAPE" });
  return { ok: true, preview };
}

/** Abre o espaço (5243). Página nova e travessia de página só com confirmação explícita. */
export async function insertGap(input: {
  collectionId: string;
  slotId: string;
  planToken: string;
  confirmCrossPage: boolean;
  confirmAddPage: boolean;
}): Promise<{ ok: true; result: GapInsertResult } | GapFail> {
  if (!isCollectionId(input?.collectionId) || !isUuid(input.slotId) || !isPlanToken(input.planToken)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("insert_my_binder_gap", {
    p_collection_id: input.collectionId,
    p_slot_id: input.slotId,
    p_plan_token: input.planToken,
    p_confirm_cross_page: input.confirmCrossPage === true,
    p_confirm_add_page: input.confirmAddPage === true,
  });
  if (error) return gapFail("insert_my_binder_gap", startedAt, error);
  const result = parseGapInsert(data);
  if (!result || result.gapSlotId !== input.slotId) return gapFail("insert_my_binder_gap", startedAt, { code: "BAD_SHAPE" });
  console.info(JSON.stringify({ scope: "colecoes.binder_gap", fn: "insert_my_binder_gap", ms: Date.now() - startedAt, moved: result.movedPockets, addedPage: Boolean(result.addedPageId) }));
  revalidatePath(binderHref(input.collectionId));
  return { ok: true, result };
}

/** Desfaz a inserção, se o fichário ainda está como ela deixou (undo_token). */
export async function closeGap(input: {
  collectionId: string;
  gapSlotId: string;
  endSlotId: string;
  undoToken: string;
  addedPageId: string | null;
}): Promise<{ ok: true; movedPockets: number; pageRemoved: boolean } | GapFail> {
  if (
    !isCollectionId(input?.collectionId) ||
    !isUuid(input.gapSlotId) ||
    !isUuid(input.endSlotId) ||
    !isUndoToken(input.undoToken) ||
    (input.addedPageId !== null && !isUuid(input.addedPageId))
  ) {
    return { ok: false, reason: "invalid" };
  }
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("close_my_binder_gap", {
    p_collection_id: input.collectionId,
    p_gap_slot_id: input.gapSlotId,
    p_end_slot_id: input.endSlotId,
    p_undo_token: input.undoToken,
    p_added_page_id: input.addedPageId,
  });
  if (error) return gapFail("close_my_binder_gap", startedAt, error);
  const result = parseGapClose(data);
  if (!result) return gapFail("close_my_binder_gap", startedAt, { code: "BAD_SHAPE" });
  revalidatePath(binderHref(input.collectionId));
  return { ok: true, ...result };
}

// ---------------------------------------------------------------------------
// Imagem em 2 bolsos (propostas 5239–5241). Mesma ordem segura da imagem do
// bolso: o arquivo já foi enviado a um caminho NOVO pelo navegador; aqui só o
// vínculo. Apagar arquivo é do cliente, depois da resposta.
// ---------------------------------------------------------------------------

type RegionFail = { ok: false; reason: RegionFailure };

function regionFail(fn: string, startedAt: number, error: { code?: string; message?: string } | null): RegionFail {
  const reason = classifyRegionFailure(error?.code, error?.message);
  console.error(JSON.stringify({ scope: "colecoes.binder_region", fn, ms: Date.now() - startedAt, code: error?.code ?? "NO_DATA", reason }));
  return { ok: false, reason };
}

function isFocal(value: unknown): value is number {
  return Number.isInteger(value) && (value as number) >= 0 && (value as number) <= 100;
}

export async function mergeSlotsWithImage(input: {
  collectionId: string;
  leftSlotId: string;
  path: string;
  focalX: number;
  focalY: number;
}): Promise<{ ok: true; result: MergeResult } | RegionFail> {
  if (!isCollectionId(input?.collectionId) || !isUuid(input.leftSlotId) || !isSlotImagePath(input.path) || !isFocal(input.focalX) || !isFocal(input.focalY)) {
    return { ok: false, reason: "invalid" };
  }
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("merge_my_binder_slots_with_image", {
    p_collection_id: input.collectionId,
    p_left_slot_id: input.leftSlotId,
    p_storage_path: input.path,
    p_focal_x: input.focalX,
    p_focal_y: input.focalY,
  });
  if (error) return regionFail("merge_my_binder_slots_with_image", startedAt, error);
  const result = parseMergeResult(data);
  if (!result || result.leftSlotId !== input.leftSlotId || result.path !== input.path) return regionFail("merge_my_binder_slots_with_image", startedAt, { code: "BAD_SHAPE" });
  revalidatePath(binderHref(input.collectionId));
  return { ok: true, result };
}

export async function setRegionImage(input: {
  collectionId: string;
  regionId: string;
  path: string;
  focalX: number;
  focalY: number;
}): Promise<{ ok: true; result: RegionImageResult } | RegionFail> {
  if (!isCollectionId(input?.collectionId) || !isUuid(input.regionId) || !isSlotImagePath(input.path) || !isFocal(input.focalX) || !isFocal(input.focalY)) {
    return { ok: false, reason: "invalid" };
  }
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("set_my_binder_region_image", {
    p_collection_id: input.collectionId,
    p_region_id: input.regionId,
    p_storage_path: input.path,
    p_focal_x: input.focalX,
    p_focal_y: input.focalY,
  });
  if (error) return regionFail("set_my_binder_region_image", startedAt, error);
  const result = parseRegionImageResult(data);
  if (!result || result.regionId !== input.regionId || result.path !== input.path) return regionFail("set_my_binder_region_image", startedAt, { code: "BAD_SHAPE" });
  revalidatePath(binderHref(input.collectionId));
  return { ok: true, result };
}

export async function setRegionImageFocus(input: {
  collectionId: string;
  regionId: string;
  focalX: number;
  focalY: number;
}): Promise<{ ok: true; focalX: number; focalY: number } | RegionFail> {
  if (!isCollectionId(input?.collectionId) || !isUuid(input.regionId) || !isFocal(input.focalX) || !isFocal(input.focalY)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("set_my_binder_region_image_focus", {
    p_collection_id: input.collectionId,
    p_region_id: input.regionId,
    p_focal_x: input.focalX,
    p_focal_y: input.focalY,
  });
  if (error) return regionFail("set_my_binder_region_image_focus", startedAt, error);
  const result = parseRegionFocusResult(data);
  if (!result || result.regionId !== input.regionId) return regionFail("set_my_binder_region_image_focus", startedAt, { code: "BAD_SHAPE" });
  revalidatePath(binderHref(input.collectionId));
  return { ok: true, focalX: result.focalX, focalY: result.focalY };
}

/** Separa os bolsos: desvincula a imagem e desfaz a mesclagem na mesma transação. Idempotente. */
export async function separateSlots(input: {
  collectionId: string;
  regionId: string;
}): Promise<{ ok: true; outcome: "SEPARATED" | "ALREADY_ABSENT"; previousPath: string | null } | RegionFail> {
  if (!isCollectionId(input?.collectionId) || !isUuid(input.regionId)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("separate_my_binder_slots", { p_collection_id: input.collectionId, p_region_id: input.regionId });
  if (error) return regionFail("separate_my_binder_slots", startedAt, error);
  const result = parseSeparateResult(data);
  if (!result || result.regionId !== input.regionId) return regionFail("separate_my_binder_slots", startedAt, { code: "BAD_SHAPE" });
  revalidatePath(binderHref(input.collectionId));
  return { ok: true, outcome: result.outcome, previousPath: result.previousPath };
}

// ---- Identidade e Centro de Controle (P3-A, 5245/5246) ----

type IdentityFail = { ok: false; reason: IdentityFailure };

function identityFail(fn: string, startedAt: number, error: { code?: string; message?: string } | null): IdentityFail {
  const reason = classifyIdentityFailure(error?.code, error?.message);
  console.error(JSON.stringify({ scope: "colecoes.binder_identity", fn, ms: Date.now() - startedAt, code: error?.code ?? "NO_DATA", reason }));
  return { ok: false, reason };
}

/**
 * Grava nome próprio e exibir/ocultar logomarca (5245). O banco é a fronteira:
 * só a proprietária ativa grava, normaliza o nome e devolve o estado canônico.
 * Aqui só recusamos o que nunca seria aceito (tipo, tamanho, controle) para
 * não gastar uma ida ao banco. Não toca em cartas, reservas, páginas ou
 * mesclagens.
 */
export async function saveBinderIdentity(input: {
  collectionId: string;
  displayName: string | null;
  showBrandMark: boolean;
}): Promise<{ ok: true; displayName: string | null; effectiveName: string; showBrandMark: boolean; changed: boolean } | IdentityFail> {
  if (!isCollectionId(input?.collectionId) || typeof input.showBrandMark !== "boolean") return { ok: false, reason: "invalid" };
  if (input.displayName !== null && typeof input.displayName !== "string") return { ok: false, reason: "invalid" };
  const normalized = input.displayName === null ? { ok: true as const, value: null } : normalizeBinderName(input.displayName);
  if (!normalized.ok) return { ok: false, reason: "invalid_name" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("set_my_binder_identity", {
    p_collection_id: input.collectionId,
    p_display_name: normalized.value,
    p_show_brand_mark: input.showBrandMark,
  });
  if (error) return identityFail("set_my_binder_identity", startedAt, error);
  const result = parseIdentityWrite(data);
  if (!result) return identityFail("set_my_binder_identity", startedAt, { code: "BAD_SHAPE" });
  console.info(JSON.stringify({ scope: "colecoes.binder_identity", fn: "set_my_binder_identity", ms: Date.now() - startedAt, changed: result.changed }));
  if (result.changed) {
    revalidatePath(binderHref(input.collectionId));
    revalidatePath(collectionHref(input.collectionId));
  }
  return { ok: true, ...result };
}

/** Ocupação do fichário (5245, só leitura) — lida quando o painel Informações abre. */
export async function readBinderOccupancy(input: { collectionId: string }): Promise<{ ok: true; occupancy: BinderOccupancy | null } | IdentityFail> {
  if (!isCollectionId(input?.collectionId)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_my_binder_occupancy", { p_collection_id: input.collectionId });
  if (error) return identityFail("get_my_binder_occupancy", startedAt, error);
  const occupancy = parseBinderOccupancy(data);
  if (occupancy === "absent") return { ok: true, occupancy: null };
  if (!occupancy) return identityFail("get_my_binder_occupancy", startedAt, { code: "BAD_SHAPE" });
  return { ok: true, occupancy };
}

/** Coleções que usam o fichário (5246, só leitura). */
export async function readBinderParticipants(input: { collectionId: string }): Promise<{ ok: true; participants: BinderParticipant[] } | IdentityFail> {
  if (!isCollectionId(input?.collectionId)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_my_binder_participants", { p_collection_id: input.collectionId });
  if (error) return identityFail("get_my_binder_participants", startedAt, error);
  const participants = parseBinderParticipants(data);
  if (!participants) return identityFail("get_my_binder_participants", startedAt, { code: "BAD_SHAPE" });
  return { ok: true, participants };
}

/**
 * Coleções do fichário + progresso oficial de cada uma (P3A-BINDER-CONTROL-
 * MULTI-COLLECTION-PROGRESS-01), só leitura, numa ida só do painel.
 *
 * - Quem participa vem de 5246 (owner-scoped): a dona vê todas as coleções do
 *   fichário; uma convidada vê só a dona e a si mesma. O cliente informa só a
 *   coleção aberta — nenhum id de outra coleção é aceito do navegador.
 * - O progresso vem do resumo oficial (R1 `get_my_collections`), numa única
 *   varredura para todos os participantes, restrito aos ids que 5246 devolveu.
 *   R1 só lê coleções da própria sessão; nada é ampliado.
 * - `progress: null` = participantes lidos, mas o resumo falhou (o painel
 *   mostra a lista e um erro só no bloco de progresso). Id ausente do mapa =
 *   indisponível para esta sessão.
 */
export async function readBinderCollections(input: { collectionId: string }): Promise<
  { ok: true; participants: BinderParticipant[]; progress: Record<string, BinderProgressInput> | null } | IdentityFail
> {
  if (!isCollectionId(input?.collectionId)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_my_binder_participants", { p_collection_id: input.collectionId });
  if (error) return identityFail("get_my_binder_participants", startedAt, error);
  const participants = parseBinderParticipants(data);
  if (!participants) return identityFail("get_my_binder_participants", startedAt, { code: "BAD_SHAPE" });
  const ids = participants.map((p) => p.collectionId).filter(isCollectionId);
  const summaries = await getMyCollectionsByIds(supabase, ids);
  if (summaries === null) {
    console.error(JSON.stringify({ scope: "colecoes.binder_identity", fn: "get_my_collections", ms: Date.now() - startedAt, code: "READ_FAILED" }));
    return { ok: true, participants, progress: null };
  }
  const progress: Record<string, BinderProgressInput> = {};
  for (const [id, s] of summaries) {
    progress[id] = {
      name: s.name,
      completionPolicy: s.completionPolicy,
      lifecycleStatus: s.lifecycleStatus,
      totalPositions: s.totalPositions,
      satisfiedPositions: s.satisfiedPositions,
      isComplete: s.isComplete,
    };
  }
  return { ok: true, participants, progress };
}

// ---------------------------------------------------------------------------
// Histórico de Atividades (P3-B S7) — só leitura, contratos LIVE da 5269
// ---------------------------------------------------------------------------

type ActivityFail = { ok: false; reason: ActivityFailure };

function activityFail(fn: string, startedAt: number, error: { code?: string; message?: string } | null): ActivityFail {
  const reason = classifyActivityFailure(error?.code, error?.message);
  // Sem dados do usuário no log: função, duração, código e classe.
  console.error(JSON.stringify({ scope: "colecoes.binder_activity", fn, ms: Date.now() - startedAt, code: error?.code ?? "NO_DATA", reason }));
  return { ok: false, reason };
}

/**
 * Uma página do histórico do fichário (5269 `get_my_binder_activity`): do mais
 * recente ao mais antigo, cursor (ocorrido, id), 20 por vez. A função só devolve
 * eventos cujo titular é a sessão — chave alheia ou inexistente = lista vazia.
 * O cliente informa só a chave do fichário aberto, a categoria do filtro e o cursor.
 */
export async function readBinderActivity(input: {
  layoutId: string;
  filter: ActivityFilterKey;
  cursor: ActivityCursor | null;
}): Promise<{ ok: true; events: ActivityEvent[]; hasMore: boolean } | ActivityFail> {
  if (!isCollectionId(input?.layoutId)) return { ok: false, reason: "invalid" };
  if (!ACTIVITY_FILTERS.some((f) => f.key === input.filter)) return { ok: false, reason: "invalid" };
  if (input.cursor !== null && !isCursor(input.cursor)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_my_binder_activity", {
    p_layout_key: input.layoutId,
    p_categories: filterCategories(input.filter),
    p_before_occurred_at: input.cursor?.occurredAt ?? null,
    p_before_id: input.cursor?.id ?? null,
    p_limit: ACTIVITY_PAGE_SIZE,
  });
  if (error) return activityFail("get_my_binder_activity", startedAt, error);
  const events = parseActivityPage(data);
  if (!events) return activityFail("get_my_binder_activity", startedAt, { code: "BAD_SHAPE" });
  return { ok: true, events, hasMore: events.length === ACTIVITY_PAGE_SIZE };
}

/** Início da cobertura do histórico deste fichário (5269 `get_my_binder_activity_coverage`). */
export async function readBinderActivityCoverage(input: { layoutId: string }): Promise<{ ok: true; coverage: ActivityCoverage } | ActivityFail> {
  if (!isCollectionId(input?.layoutId)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_my_binder_activity_coverage", { p_layout_key: input.layoutId });
  if (error) return activityFail("get_my_binder_activity_coverage", startedAt, error);
  const coverage = parseActivityCoverage(data);
  if (!coverage) return activityFail("get_my_binder_activity_coverage", startedAt, { code: "BAD_SHAPE" });
  return { ok: true, coverage };
}

// ---------------------------------------------------------------------------
// Referências de espécie nos bolsos (POKEDEX-BINDER-SPECIES-REFERENCE, 5258/5259)
// ---------------------------------------------------------------------------

type SpeciesFail = { ok: false; reason: SpeciesFailure };

function speciesFail(fn: string, startedAt: number, error: { code?: string; message?: string } | null): SpeciesFail {
  const reason = classifySpeciesFailure(error?.code, error?.message);
  // Sem dados do usuário no log: função, duração, código e classe.
  console.error(JSON.stringify({ scope: "colecoes.binder_species", fn, ms: Date.now() - startedAt, code: error?.code ?? "NO_DATA", reason }));
  return { ok: false, reason };
}

async function readSpeciesState(supabase: Awaited<ReturnType<typeof createClient>>, collectionId: string, startedAt: number) {
  const { data, error } = await supabase.rpc("get_my_binder_species_reference_state", { p_collection_id: collectionId });
  if (error) return speciesFail("get_my_binder_species_reference_state", startedAt, error);
  const state = parseSpeciesReferenceState(data);
  if (!state) return speciesFail("get_my_binder_species_reference_state", startedAt, { code: "BAD_SHAPE" });
  return { ok: true as const, state };
}

/** Estado leve (5259) — usado pelo fichário aberto sobre a coleção (overlay). Só leitura. */
export async function readSpeciesReferenceState(input: { collectionId: string }): Promise<{ ok: true; state: SpeciesReferenceState } | SpeciesFail> {
  if (!isCollectionId(input?.collectionId)) return { ok: false, reason: "invalid" };
  const supabase = await createClient();
  return readSpeciesState(supabase, input.collectionId, Date.now());
}

/** Prévia (5258, não grava): pares bolso ↔ espécie, bolsos livres e o token da aplicação. */
export async function previewSpeciesReferences(input: { collectionId: string }): Promise<{ ok: true; preview: SpeciesReferencePreview } | SpeciesFail> {
  if (!isCollectionId(input?.collectionId)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("preview_my_binder_species_references", { p_collection_id: input.collectionId });
  if (error) return speciesFail("preview_my_binder_species_references", startedAt, error);
  const preview = parseSpeciesPreview(data);
  if (!preview) return speciesFail("preview_my_binder_species_references", startedAt, { code: "BAD_SHAPE" });
  return { ok: true, preview };
}

/** Aplicação (5258): grava o plano da prévia, idempotente; devolve o estado relido. */
export async function applySpeciesReferences(input: {
  collectionId: string;
  planToken: string;
}): Promise<{ ok: true; alreadyApplied: boolean; state: SpeciesReferenceState } | SpeciesFail> {
  if (!isCollectionId(input?.collectionId) || !isSpeciesPlanToken(input.planToken)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("apply_my_binder_species_references", {
    p_collection_id: input.collectionId,
    p_plan_token: input.planToken,
  });
  if (error) return speciesFail("apply_my_binder_species_references", startedAt, error);
  const row = Array.isArray(data) && data.length === 1 ? (data[0] as Record<string, unknown>) : null;
  if (!row || (row.operation !== "APPLIED" && row.operation !== "ALREADY_APPLIED")) {
    return speciesFail("apply_my_binder_species_references", startedAt, { code: "BAD_SHAPE" });
  }
  const read = await readSpeciesState(supabase, input.collectionId, startedAt);
  if (!read.ok) return read;
  return { ok: true, alreadyApplied: row.operation === "ALREADY_APPLIED", state: read.state };
}

/** Mostrar/ocultar (5258, ajuste A): só a preferência; os vínculos ficam intactos. */
export async function setSpeciesReferenceVisibility(input: {
  collectionId: string;
  visible: boolean;
}): Promise<{ ok: true; visible: boolean } | SpeciesFail> {
  if (!isCollectionId(input?.collectionId) || typeof input.visible !== "boolean") return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("set_my_binder_species_reference_visibility", {
    p_collection_id: input.collectionId,
    p_visible: input.visible,
  });
  if (error) return speciesFail("set_my_binder_species_reference_visibility", startedAt, error);
  const row = Array.isArray(data) && data.length === 1 ? (data[0] as Record<string, unknown>) : null;
  if (!row || typeof row.references_visible !== "boolean") {
    return speciesFail("set_my_binder_species_reference_visibility", startedAt, { code: "BAD_SHAPE" });
  }
  return { ok: true, visible: row.references_visible };
}

/** Remoção explícita (5258): exige a contagem atual; devolve o estado relido. */
export async function clearSpeciesReferences(input: {
  collectionId: string;
  expectedCount: number;
}): Promise<{ ok: true; removed: number; state: SpeciesReferenceState } | SpeciesFail> {
  if (!isCollectionId(input?.collectionId) || !Number.isInteger(input.expectedCount) || input.expectedCount < 0 || input.expectedCount > 100_000) {
    return { ok: false, reason: "invalid" };
  }
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("clear_my_binder_species_references", {
    p_collection_id: input.collectionId,
    p_expected_count: input.expectedCount,
  });
  if (error) return speciesFail("clear_my_binder_species_references", startedAt, error);
  const row = Array.isArray(data) && data.length === 1 ? (data[0] as Record<string, unknown>) : null;
  const removed = row && typeof row.removed_count === "number" ? row.removed_count : null;
  if (removed === null) return speciesFail("clear_my_binder_species_references", startedAt, { code: "BAD_SHAPE" });
  const read = await readSpeciesState(supabase, input.collectionId, startedAt);
  if (!read.ok) return read;
  return { ok: true, removed, state: read.state };
}

// ---------------------------------------------------------------------------
// Novidades do Catálogo no fichário (BINDER-CATALOG-RECONCILIATION, 5263–5266
// LIVE desde 2026-10-25). Só MASTER_SET; Pokédex nunca entra. Aviso e prévia
// só leem; a incorporação exige o plan_token da prévia e as confirmações de
// outra página / página nova. O banco recalcula tudo sob a trava do fichário.
// ---------------------------------------------------------------------------

type CatalogFail = { ok: false; reason: CatalogFailure };

function catalogFail(fn: string, startedAt: number, error: { code?: string; message?: string; hint?: string } | null): CatalogFail {
  const reason = classifyCatalogFailure(error?.code, error?.message, error?.hint);
  // Sem dados do usuário no log: função, duração, código e classe.
  console.error(JSON.stringify({ scope: "colecoes.binder_catalog", fn, ms: Date.now() - startedAt, code: error?.code ?? "NO_DATA", reason }));
  return { ok: false, reason };
}

function validCatalogKeys(keys: unknown): keys is string[] {
  return Array.isArray(keys) && keys.length >= 1 && keys.length <= CATALOG_ITEM_LIMIT && keys.every(isCatalogItemKey) && new Set(keys).size === keys.length;
}

/** Aviso leve (5265): elegibilidade + novidades pendentes. Nunca falha por inelegibilidade. Só leitura. */
export async function readCatalogNovelties(input: { collectionId: string }): Promise<{ ok: true; state: CatalogNoveltyState } | CatalogFail> {
  if (!isCollectionId(input?.collectionId)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_my_binder_catalog_novelties", { p_collection_id: input.collectionId });
  if (error) return catalogFail("get_my_binder_catalog_novelties", startedAt, error);
  const state = parseCatalogNovelties(data);
  if (!state) return catalogFail("get_my_binder_catalog_novelties", startedAt, { code: "BAD_SHAPE" });
  return { ok: true, state };
}

/** Prévia (5265, não grava) da seleção explícita: destinos, deslocamentos, páginas, capacidade e o token. */
export async function previewCatalogReconciliation(input: {
  collectionId: string;
  keys: string[];
}): Promise<{ ok: true; preview: CatalogPreview } | CatalogFail> {
  if (!isCollectionId(input?.collectionId) || !validCatalogKeys(input.keys)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("preview_my_binder_catalog_reconciliation", { p_collection_id: input.collectionId, p_keys: input.keys });
  if (error) return catalogFail("preview_my_binder_catalog_reconciliation", startedAt, error);
  const preview = parseCatalogPreview(data);
  if (!preview) return catalogFail("preview_my_binder_catalog_reconciliation", startedAt, { code: "BAD_SHAPE" });
  return { ok: true, preview };
}

/**
 * Incorporação (5266): mesma seleção e mesmo token da prévia; outra página e
 * página nova só com confirmação explícita. Atômica e idempotente no banco
 * (ALREADY_APPLIED / NOTHING_TO_DO não gravam nada). Revalida o fichário e a
 * página da coleção (indicadores de reservas/progresso).
 */
export async function applyCatalogReconciliation(input: {
  collectionId: string;
  keys: string[];
  planToken: string;
  confirmCrossPage: boolean;
  confirmAddPage: boolean;
}): Promise<{ ok: true; result: CatalogApplyResult } | CatalogFail> {
  if (!isCollectionId(input?.collectionId) || !validCatalogKeys(input.keys) || !isCatalogPlanToken(input.planToken)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("apply_my_binder_catalog_reconciliation", {
    p_collection_id: input.collectionId,
    p_keys: input.keys,
    p_plan_token: input.planToken,
    p_confirm_cross_page: input.confirmCrossPage === true,
    p_confirm_add_page: input.confirmAddPage === true,
  });
  if (error) return catalogFail("apply_my_binder_catalog_reconciliation", startedAt, error);
  const result = parseCatalogApply(data);
  if (!result) return catalogFail("apply_my_binder_catalog_reconciliation", startedAt, { code: "BAD_SHAPE" });
  console.info(
    JSON.stringify({ scope: "colecoes.binder_catalog", fn: "apply_my_binder_catalog_reconciliation", ms: Date.now() - startedAt, outcome: result.outcome, items: result.itemsApplied, pagesAdded: result.pagesAdded }),
  );
  if (result.outcome === "APPLIED") {
    revalidatePath(binderHref(input.collectionId));
    revalidatePath(collectionHref(input.collectionId));
  }
  return { ok: true, result };
}
