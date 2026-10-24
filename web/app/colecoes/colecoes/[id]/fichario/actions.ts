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
import { getMyBinderJoinCandidates, getMyCollectionBinderPages } from "@/lib/colecoes/binder-queries";
import {
  AVAILABLE_PAGE_SIZE,
  DETACH_TOKEN,
  type AttachOutcome,
  type AvailableCard,
  type DetachPreview,
  type DetachResult,
  type JoinCandidate,
  type ShareFailure,
  classifyShareFailure,
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
}): Promise<{ ok: true; firstPage: number; pages: BinderPage[] } | Fail> {
  if (!isCollectionId(input?.collectionId) || !Number.isInteger(input.page) || input.page < 1 || input.page > 100_000) {
    return { ok: false, reason: "invalid" };
  }
  const firstPage = readBatchStart(input.page);
  const supabase = await createClient();
  const pages = await getMyCollectionBinderPages(supabase, input.collectionId, firstPage);
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

/** Desfazer a retirada: devolve o mesmo exemplar ao mesmo bolso (5131, ADD). */
export async function restoreToSlot(input: {
  collectionId: string;
  slotId: string;
  allocationId: string;
}): Promise<{ ok: true } | SlotFail> {
  if (!isCollectionId(input?.collectionId) || !isUuid(input.slotId) || !isUuid(input.allocationId)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { error } = await supabase.rpc("assign_card_to_slot", { p_slot_id: input.slotId, p_collection_allocation_id: input.allocationId });
  if (error) return slotFail("assign_card_to_slot", startedAt, error);
  slotDone("assign_card_to_slot", startedAt, input.collectionId);
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

/** "Cartas disponíveis": exemplares desta coleção ainda sem bolso (5230, paginado). */
export async function readAvailableCards(input: {
  collectionId: string;
  offset: number;
}): Promise<{ ok: true; items: AvailableCard[]; total: number } | ShareFail> {
  if (!isCollectionId(input?.collectionId) || !Number.isInteger(input.offset) || input.offset < 0 || input.offset > 1_000_000) {
    return { ok: false, reason: "invalid" };
  }
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_my_collection_binder_unplaced", {
    p_collection_id: input.collectionId,
    p_limit: AVAILABLE_PAGE_SIZE,
    p_offset: input.offset,
  });
  if (error) return shareFail("get_my_collection_binder_unplaced", startedAt, error);
  const parsed = parseAvailableCards(data);
  if (!parsed) return shareFail("get_my_collection_binder_unplaced", startedAt, { code: "BAD_SHAPE" });
  return { ok: true, items: parsed.items, total: parsed.total };
}

/**
 * Posiciona uma carta disponível num bolso (5131 `assign_card_to_slot`). A
 * interface só oferece bolsos vazios e soltos; o banco revalida dono,
 * participação no fichário, coleção ativa e cadeado.
 */
export async function placeAvailableCard(input: {
  collectionId: string;
  slotId: string;
  allocationId: string;
}): Promise<{ ok: true; operation: "ADD" | "REPLACE" } | SlotFail> {
  if (!isCollectionId(input?.collectionId) || !isUuid(input.slotId) || !isUuid(input.allocationId)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("assign_card_to_slot", { p_slot_id: input.slotId, p_collection_allocation_id: input.allocationId });
  if (error) return slotFail("assign_card_to_slot", startedAt, error);
  const operation = Array.isArray(data) ? (data[0] as Record<string, unknown> | undefined)?.operation : undefined;
  if (operation !== "ADD" && operation !== "REPLACE") return slotFail("assign_card_to_slot", startedAt, { code: "BAD_SHAPE" });
  slotDone("assign_card_to_slot", startedAt, input.collectionId, { operation });
  return { ok: true, operation };
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
