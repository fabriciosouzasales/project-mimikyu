"use server";

import { type ActivityCursor, type ActivityEvent, isCursor } from "@/lib/colecoes/binder-activity";
import {
  COLLECTION_ACTIVITY_NOTE,
  COLLECTION_ACTIVITY_PAGE_SIZE,
  COLLECTION_ACTIVITY_RPC,
  type CollectionActivityFailure,
  classifyCollectionActivityFailure,
  parseCollectionActivityPage,
} from "@/lib/colecoes/collection-activity";
import { isCollectionId } from "@/lib/colecoes/colecoes";
import { editorCurationFlagOn } from "@/lib/colecoes/editor-binder";
import { createClient } from "@/lib/supabase/server";

/**
 * V1-13 · E3 / F3-4 — histórico da Pokédex da coleção (5395) para titular e
 * participantes, com a SESSÃO do usuário. E3-7a: fica em `app/colecoes/` porque a
 * página do titular e a coleção compartilhada usam a MESMA leitura. Quem decide o acesso é a função do
 * banco (barreira 5389; titular ou participante ACTIVE pela 5302). A
 * configuração D-E3-1 desligada → nenhuma chamada. Cursor = id do último
 * evento (keyset do servidor). Nenhum evento, autor ou id vai para o log.
 */
export async function readCollectionActivity(input: {
  collectionId: string;
  cursor: ActivityCursor | null;
}): Promise<{ ok: true; events: ActivityEvent[]; hasMore: boolean; note?: string | null } | { ok: false; reason: CollectionActivityFailure }> {
  if (!editorCurationFlagOn(process.env)) return { ok: false, reason: "unavailable" };
  if (!isCollectionId(input?.collectionId)) return { ok: false, reason: "invalid" };
  if (input.cursor !== null && !isCursor(input.cursor)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const log = (code: string | undefined, reason: CollectionActivityFailure) =>
    console.error(JSON.stringify({ scope: "colecoes.collection_activity", fn: COLLECTION_ACTIVITY_RPC, ms: Date.now() - startedAt, code: code ?? "BAD_SHAPE", reason }));
  try {
    const supabase = await createClient();
    const { data, error } = await supabase.rpc(COLLECTION_ACTIVITY_RPC, {
      p_collection_id: input.collectionId.toLowerCase(),
      p_before_id: input.cursor?.id ?? null,
      p_limit: COLLECTION_ACTIVITY_PAGE_SIZE,
    });
    if (error) {
      const reason = classifyCollectionActivityFailure(error.code, error.message);
      log(error.code, reason);
      return { ok: false, reason };
    }
    const events = parseCollectionActivityPage(data);
    if (!events || events.length > COLLECTION_ACTIVITY_PAGE_SIZE) {
      log(undefined, "unknown");
      return { ok: false, reason: "unknown" };
    }
    const hasMore = events.length === COLLECTION_ACTIVITY_PAGE_SIZE;
    return input.cursor === null ? { ok: true, events, hasMore, note: COLLECTION_ACTIVITY_NOTE } : { ok: true, events, hasMore };
  } catch {
    log(undefined, "unknown");
    return { ok: false, reason: "unknown" };
  }
}
