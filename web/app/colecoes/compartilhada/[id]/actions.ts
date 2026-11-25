"use server";

import { revalidatePath } from "next/cache";
import { COLECOES_PATH, isCollectionId } from "@/lib/colecoes/colecoes";
import { editorCurationFlagOn } from "@/lib/colecoes/editor-binder";
import {
  type MetadataBaseline,
  type MetadataFailure,
  classifyMetadataFailure,
  editorCoverCodeApplies,
  sameText,
  validCoverCode,
  validFinish,
  validTextInput,
} from "@/lib/colecoes/editor-collection-metadata";
import { SHARED_COLLECTION_PATH, type SharedCollection, parseSharedCollection, parseSharedCover } from "@/lib/colecoes/sharing";
import { createClient } from "@/lib/supabase/server";

/**
 * V1-13 · E3-3 — metadados da coleção pelo EDITOR (5376). Server actions
 * finas: conferem a configuração (D-E3-1, desligada por padrão — não
 * autoriza nada), validam o formato, relêem o valor atual pela leitura do
 * participante (5312/5328) e só então chamam a função do EDITOR com a SESSÃO
 * do usuário. Toda autorização é do banco (EDITOR ACTIVE, coleção ativa,
 * barreira 5389). Uma chamada por pedido; `hint`/`details` nunca são lidos;
 * nenhum id no log.
 */

type Fail = { ok: false; reason: MetadataFailure };

function enabled(): boolean {
  return editorCurationFlagOn(process.env);
}

function fail(fn: string, startedAt: number, error: { code?: string; message?: string } | null, reason?: MetadataFailure): Fail {
  const r = reason ?? classifyMetadataFailure(error?.code, error?.message);
  console.error(JSON.stringify({ scope: "colecoes.editor_metadata", fn, ms: Date.now() - startedAt, code: error?.code ?? "BAD_SHAPE", reason: r }));
  return { ok: false, reason: r };
}

function revalidate(collectionId: string) {
  // Página compartilhada, fichário compartilhado e Biblioteca (nome e capa aparecem nos três).
  revalidatePath(`${SHARED_COLLECTION_PATH}/${collectionId}`);
  revalidatePath(`${SHARED_COLLECTION_PATH}/${collectionId}/fichario`);
  revalidatePath(COLECOES_PATH, "layout");
}

/** Releitura do participante: a coleção ainda é dele como EDITOR ativo e como estava? Não autoriza nada (o banco decide). */
async function readCurrent(supabase: Awaited<ReturnType<typeof createClient>>, collectionId: string): Promise<SharedCollection | MetadataFailure> {
  const { data, error } = await supabase.rpc("get_shared_collection", { p_collection_id: collectionId });
  if (error) return "unknown";
  const collection = parseSharedCollection(data);
  if (!collection || collection.access !== "VIEWER" || collection.role !== "EDITOR") return "access_lost";
  if (collection.archived) return "archived";
  return collection;
}

/** Nome e descrição juntos (a 5376 grava os dois). `baseline` = o que a tela mostrou ao abrir. */
export async function editorSaveCollectionText(input: {
  collectionId: string;
  name: string;
  description: string;
  baseline: MetadataBaseline;
}): Promise<{ ok: true; name: string; description: string | null } | Fail> {
  if (!enabled()) return { ok: false, reason: "disabled" };
  if (!isCollectionId(input?.collectionId) || typeof input.name !== "string" || typeof input.description !== "string") return { ok: false, reason: "invalid" };
  const text = validTextInput(input.name, input.description);
  const base = input.baseline;
  if (!text || !base || typeof base.name !== "string" || (base.description !== null && typeof base.description !== "string")) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const current = await readCurrent(supabase, input.collectionId);
  if (typeof current === "string") return fail("get_shared_collection", startedAt, null, current);
  if (!sameText({ name: current.name, description: current.description }, base)) return fail("get_shared_collection", startedAt, null, "changed");
  const { data, error } = await supabase.rpc("editor_update_collection_metadata", {
    p_collection_id: input.collectionId,
    p_name: text.name,
    p_description: text.description,
  });
  if (error) return fail("editor_update_collection_metadata", startedAt, error);
  const row = Array.isArray(data) ? (data[0] as { name?: unknown; description?: unknown } | undefined) : undefined;
  if (!row || typeof row.name !== "string") return fail("editor_update_collection_metadata", startedAt, null, "uncertain");
  console.info(JSON.stringify({ scope: "colecoes.editor_metadata", fn: "editor_update_collection_metadata", ms: Date.now() - startedAt }));
  revalidate(input.collectionId);
  return { ok: true, name: row.name, description: typeof row.description === "string" ? row.description : null };
}

/** Acabamento da capa da coleção (não o do fichário). `baseline` = acabamento mostrado ao abrir. */
export async function editorSaveCoverFinish(input: { collectionId: string; finish: string; baseline: string | null }): Promise<{ ok: true; finish: string } | Fail> {
  if (!enabled()) return { ok: false, reason: "disabled" };
  if (!isCollectionId(input?.collectionId) || !validFinish(input.finish)) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const current = await readCurrent(supabase, input.collectionId);
  if (typeof current === "string") return fail("get_shared_collection", startedAt, null, current);
  if ((current.coverFinish ?? null) !== (input.baseline ?? null)) return fail("get_shared_collection", startedAt, null, "changed");
  const { data, error } = await supabase.rpc("editor_set_collection_cover_finish", { p_collection_id: input.collectionId, p_finish: input.finish });
  if (error) return fail("editor_set_collection_cover_finish", startedAt, error);
  if (!validFinish(data)) return fail("editor_set_collection_cover_finish", startedAt, null, "uncertain");
  revalidate(input.collectionId);
  return { ok: true, finish: data };
}

/** Código da placa (só coleção livre ou Pokédex). Vazio = sem código. `baseline` = código mostrado ao abrir. */
export async function editorSaveCoverCode(input: { collectionId: string; code: string; baseline: string | null }): Promise<{ ok: true; code: string | null } | Fail> {
  if (!enabled()) return { ok: false, reason: "disabled" };
  if (!isCollectionId(input?.collectionId) || typeof input.code !== "string") return { ok: false, reason: "invalid" };
  const code = validCoverCode(input.code);
  if (code === "invalid") return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const current = await readCurrent(supabase, input.collectionId);
  if (typeof current === "string") return fail("get_shared_collection", startedAt, null, current);
  if (!editorCoverCodeApplies(current)) return { ok: false, reason: "not_free" };
  const cover = await supabase.rpc("get_shared_collection_cover", { p_collection_id: input.collectionId });
  const now = cover.error ? null : parseSharedCover(cover.data);
  if (!now) return fail("get_shared_collection_cover", startedAt, null, "unknown");
  if ((now.code ?? null) !== (input.baseline ?? null)) return fail("get_shared_collection_cover", startedAt, null, "changed");
  const { data, error } = await supabase.rpc("editor_set_collection_cover_code", { p_collection_id: input.collectionId, p_code: code });
  if (error) return fail("editor_set_collection_cover_code", startedAt, error);
  if (data !== null && (typeof data !== "string" || validCoverCode(data) !== data)) return fail("editor_set_collection_cover_code", startedAt, null, "uncertain");
  revalidate(input.collectionId);
  return { ok: true, code: data };
}
