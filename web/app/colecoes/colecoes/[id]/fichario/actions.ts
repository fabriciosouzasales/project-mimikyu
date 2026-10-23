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
import { collectionHref, isCollectionId } from "@/lib/colecoes/colecoes";
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
