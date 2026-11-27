"use server";

import { revalidatePath } from "next/cache";
import { editorCurationFlagOn } from "@/lib/colecoes/editor-binder";
import {
  type AnyResult,
  type CopiesPage,
  type CopyScope,
  type EditorPokedexFailure,
  buildChooseCall,
  buildCopiesCall,
  buildMoveCall,
  buildRestoreCall,
  buildUnassignCall,
  classifyEditorPokedexFailure,
  parseChooseResult,
  parseCopiesPage,
  parseMoveResult,
  parseRestoreResult,
  parseUnassignResult,
  safeLogFields,
} from "@/lib/colecoes/editor-pokedex";
import { type WriteIntent, isWriteIntent } from "@/lib/colecoes/editor-pokedex-panel";
import { SHARED_COLLECTION_PATH } from "@/lib/colecoes/sharing";
import { createClient } from "@/lib/supabase/server";

/**
 * V1-13 · E3 / F3-2 — leitura (5391) e escritas (5392) da Pokédex compartilhada
 * pelo EDITOR. Server actions finas: revalidam a forma com os construtores da
 * F3-1 e chamam a RPC com a SESSÃO do usuário (nunca service role). Toda
 * autorização é do banco a cada chamada (barreira 5389, EDITOR ACTIVE, época do
 * papel, estado esperado). A configuração D1 só evita chamadas; não autoriza.
 * Só identificadores opacos (copy_token) e posições do catálogo trafegam aqui.
 */

export type EditorPokedexFail = { ok: false; reason: EditorPokedexFailure | "disabled" };

function fail(fn: string, startedAt: number, error: { code?: string; message?: string } | null): EditorPokedexFail {
  const reason = classifyEditorPokedexFailure(error?.code, error?.message);
  // Só função, duração, código e motivo: nunca token, ids ou texto do banco.
  console.error(JSON.stringify({ scope: "colecoes.editor_pokedex", ...safeLogFields(fn, reason), ms: Date.now() - startedAt, code: error?.code ?? "BAD_SHAPE" }));
  return { ok: false, reason };
}

/** Cópias da posição (AT_POSITION) ou que podem vir para ela (ASSIGNABLE). Zero linhas também pode ser falta de acesso. */
export async function readEditorPokedexCopies(input: {
  collectionId: string;
  positionId: string;
  scope: CopyScope;
  query?: string | null;
  offset?: number;
}): Promise<{ ok: true; page: CopiesPage } | EditorPokedexFail> {
  if (!editorCurationFlagOn(process.env)) return { ok: false, reason: "disabled" };
  const call = buildCopiesCall({
    collectionId: input?.collectionId,
    positionId: input?.positionId,
    scope: input?.scope,
    query: input?.query ?? null,
    offset: input?.offset ?? 0,
  });
  if (!call) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  try {
    const supabase = await createClient();
    const { data, error } = await supabase.rpc(call.fn, call.args);
    if (error) return fail(call.fn, startedAt, { code: error.code, message: error.message });
    const page = parseCopiesPage(data, call);
    if (!page) return fail(call.fn, startedAt, null);
    return { ok: true, page };
  } catch {
    return fail(call.fn, startedAt, null);
  }
}

function callFor(intent: WriteIntent) {
  switch (intent.kind) {
    case "move":
      return { call: buildMoveCall(intent), parse: parseMoveResult as (d: unknown) => AnyResult | null };
    case "unassign":
      return { call: buildUnassignCall(intent), parse: parseUnassignResult as (d: unknown) => AnyResult | null };
    case "choose":
      return { call: buildChooseCall(intent), parse: parseChooseResult as (d: unknown) => AnyResult | null };
    case "restore":
      return { call: buildRestoreCall(intent), parse: parseRestoreResult as (d: unknown) => AnyResult | null };
  }
}

/** Uma escrita da 5392. Nunca repete sozinha; resposta fora do contrato → "unknown" (pode ter acontecido). */
export async function writeEditorPokedex(intent: WriteIntent): Promise<{ ok: true; result: AnyResult } | EditorPokedexFail> {
  if (!editorCurationFlagOn(process.env)) return { ok: false, reason: "disabled" };
  if (!isWriteIntent(intent)) return { ok: false, reason: "invalid" };
  const { call, parse } = callFor(intent);
  if (!call) return { ok: false, reason: "invalid" };
  const startedAt = Date.now();
  try {
    const supabase = await createClient();
    const { data, error } = await supabase.rpc(call.fn, call.args);
    if (error) return fail(call.fn, startedAt, { code: error.code, message: error.message });
    const result = parse(data);
    if (!result) return fail(call.fn, startedAt, null);
    console.info(JSON.stringify({ scope: "colecoes.editor_pokedex", fn: call.fn, ms: Date.now() - startedAt, operation: result.operation }));
    if (result.operation !== "UNCHANGED") revalidatePath(`${SHARED_COLLECTION_PATH}/${intent.collectionId}`);
    return { ok: true, result };
  } catch {
    return fail(call.fn, startedAt, null);
  }
}
