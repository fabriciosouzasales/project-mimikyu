"use server";

import { type ActivityCursor, type ActivityEvent, type ActivityFilterKey, filterCategories, isCursor } from "@/lib/colecoes/binder-activity";
import { isCollectionId } from "@/lib/colecoes/colecoes";
import { editorCurationFlagOn } from "@/lib/colecoes/editor-binder";
import {
  SHARED_ACTIVITY_PAGE_SIZE,
  type SharedActivityFailure,
  type SharedActivityStatus,
  classifySharedActivityFailure,
  isSharedActivityFilter,
  parseSharedActivityPage,
  parseSharedActivityStatus,
  sharedHistoryNote,
} from "@/lib/colecoes/shared-binder-activity";
import { parseSharedCollection } from "@/lib/colecoes/sharing";
import { createClient } from "@/lib/supabase/server";

/**
 * V1-13 · E3-5 — histórico do fichário para o participante (EDITOR e VIEWER),
 * pela 5388 com a SESSÃO do usuário. Nada privilegiado: quem decide o acesso,
 * o fichário atual, os eventos e os itens visíveis é a função do banco.
 *
 * A configuração D-E3-1 (`MMKYU_V113_EDITOR_CURATION`, desligada por padrão)
 * vale também aqui: desligada, nenhuma chamada. Zero linhas na leitura de
 * estado = sem acesso OU barreira fechada; só nesse caso a coleção é relida
 * (5312) para separar dois indícios — a coleção some (acesso provavelmente
 * perdido) ou continua (leitura indisponível) —, sem afirmar a causa. Nenhum
 * evento, autor ou id vai para o log: função, duração, código e classe.
 */

type Fail = { ok: false; reason: SharedActivityFailure };
type Supabase = Awaited<ReturnType<typeof createClient>>;

function fail(fn: string, startedAt: number, code: string | undefined, reason: SharedActivityFailure): Fail {
  console.error(JSON.stringify({ scope: "colecoes.shared_activity", fn, ms: Date.now() - startedAt, code: code ?? "NO_DATA", reason }));
  return { ok: false, reason };
}

/** Estado nulo: a coleção ainda aparece para esta sessão? Indício, não prova: some → acesso não confirmado; continua → leitura indisponível. */
async function explainNoStatus(supabase: Supabase, collectionId: string, startedAt: number): Promise<Fail> {
  const { data, error } = await supabase.rpc("get_shared_collection", { p_collection_id: collectionId });
  if (error) return fail("get_shared_collection", startedAt, error.code, classifySharedActivityFailure(error.code, error.message));
  const collection = parseSharedCollection(data);
  if (!collection || collection.access !== "VIEWER") return fail("get_shared_collection", startedAt, "NO_ROWS", "access_lost");
  return fail("get_shared_binder_activity_status", startedAt, "NO_ROWS", "unavailable");
}

async function readStatus(supabase: Supabase, collectionId: string, startedAt: number): Promise<SharedActivityStatus | Fail> {
  const { data, error } = await supabase.rpc("get_shared_binder_activity_status", { p_collection_id: collectionId });
  if (error) return fail("get_shared_binder_activity_status", startedAt, error.code, classifySharedActivityFailure(error.code, error.message));
  const status = parseSharedActivityStatus(data);
  if (status === undefined) return fail("get_shared_binder_activity_status", startedAt, "BAD_SHAPE", "unknown");
  if (status === null) return explainNoStatus(supabase, collectionId, startedAt);
  if (!status.hasBinder) return fail("get_shared_binder_activity_status", startedAt, "NO_BINDER", "no_binder");
  return status;
}

/**
 * Uma página do histórico compartilhado. Primeira página (`cursor = null`):
 * estado e lista em paralelo; a nota de histórico parcial vem junto. Página
 * seguinte vazia: o estado é relido para não confundir perda de acesso com
 * fim do histórico.
 */
export async function readSharedActivity(input: {
  collectionId: string;
  filter: ActivityFilterKey;
  cursor: ActivityCursor | null;
}): Promise<{ ok: true; events: ActivityEvent[]; hasMore: boolean; note?: string | null } | Fail> {
  if (!editorCurationFlagOn(process.env)) return { ok: false, reason: "unavailable" };
  if (!isCollectionId(input?.collectionId) || !isSharedActivityFilter(input.filter)) return { ok: false, reason: "invalid" };
  if (input.cursor !== null && !isCursor(input.cursor)) return { ok: false, reason: "invalid" };
  const collectionId = input.collectionId.toLowerCase();
  const first = input.cursor === null;
  const startedAt = Date.now();
  const supabase = await createClient();
  const list = supabase.rpc("get_shared_binder_activity", {
    p_collection_id: collectionId,
    p_categories: filterCategories(input.filter),
    p_before_occurred_at: input.cursor?.occurredAt ?? null,
    p_before_id: input.cursor?.id ?? null,
    p_limit: SHARED_ACTIVITY_PAGE_SIZE,
  });
  const [status, { data, error }] = await Promise.all([first ? readStatus(supabase, collectionId, startedAt) : Promise.resolve(null), list]);
  if (status && "ok" in status) return status;
  if (error) return fail("get_shared_binder_activity", startedAt, error.code, classifySharedActivityFailure(error.code, error.message));
  const events = parseSharedActivityPage(data);
  if (!events) return fail("get_shared_binder_activity", startedAt, "BAD_SHAPE", "unknown");
  if (!first && events.length === 0) {
    const again = await readStatus(supabase, collectionId, startedAt);
    if ("ok" in again) return again;
  }
  return first
    ? { ok: true, events, hasMore: events.length === SHARED_ACTIVITY_PAGE_SIZE, note: sharedHistoryNote(status) }
    : { ok: true, events, hasMore: events.length === SHARED_ACTIVITY_PAGE_SIZE };
}
