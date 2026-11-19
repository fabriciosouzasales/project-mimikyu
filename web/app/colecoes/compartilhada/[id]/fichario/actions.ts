"use server";

import { revalidatePath } from "next/cache";
import { isUuid } from "@/lib/colecoes/acervo-add";
import { isCollectionId } from "@/lib/colecoes/colecoes";
import {
  type EditorFailure,
  type PocketPosition,
  PLACEABLE_PAGE_SIZE,
  classifyEditorFailure,
  editorCurationFlagOn,
  isPocketPosition,
  parsePlaceableCards,
} from "@/lib/colecoes/editor-binder";
import type { AvailableCard } from "@/lib/colecoes/binder-share";
import { SHARED_COLLECTION_PATH } from "@/lib/colecoes/sharing";
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
