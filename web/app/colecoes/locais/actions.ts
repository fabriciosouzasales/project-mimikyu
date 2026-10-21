"use server";

import { revalidatePath } from "next/cache";
import { ACERVO_PATH } from "@/lib/colecoes/acervo";
import { isUuid } from "@/lib/colecoes/acervo-add";
import { COLECOES_PATH } from "@/lib/colecoes/colecoes";
import {
  LOCAIS_PATH,
  type StorageFailure,
  isStorageKindCode,
  normalizeStorageName,
  storageFailureFromError,
} from "@/lib/colecoes/storage-locations";
import { createClient } from "@/lib/supabase/server";

/**
 * "Meus locais" — ações de gravação (WHERE-02 FRONTEND IMPLEMENTATION-01).
 *
 * Só chamam os contratos homologados no LIVE, com a sessão do usuário
 * (cookies) — nunca `service_role`:
 *   - criar   → `create_my_storage_container` (5216, idempotente);
 *   - editar  → `update_my_storage_container` (5217, nome e tipo);
 *   - excluir → `delete_my_storage_container` (5218, só vazio e não-padrão).
 *
 * Dono, isolamento entre acervos, regra de nome, tipo ativo, bloqueios de
 * exclusão e concorrência são decididos pelo banco. Esta camada só confere o
 * formato para responder cedo e traduz o resultado em `StorageFailure`
 * (mensagens em `storage-locations.ts`). Nenhuma ação move, atribui ou apaga
 * carta, e nenhuma muda o local padrão de coleção.
 */

type Fail = { ok: false; reason: StorageFailure };

export type SavedLocation = { id: string; name: string; kindCode: string | null };

/** Tipo opcional: vazio/ausente = sem tipo; formato inválido = recusado. */
function readKind(value: unknown): string | null | "invalid" {
  if (value === null || value === undefined || value === "") return null;
  return isStorageKindCode(value) ? value : "invalid";
}

/**
 * Cria um local. A chave vem do cliente, gerada uma vez por conteúdo do
 * formulário e reaproveitada em toda nova tentativa do MESMO envio — clique
 * duplo, timeout ou rede devolvem o mesmo local (`replayed`), nunca dois.
 */
export async function createStorageLocation(input: {
  idempotencyKey: string;
  name: string;
  kindCode: string | null;
}): Promise<({ ok: true; replayed: boolean } & SavedLocation) | Fail> {
  const name = normalizeStorageName(typeof input?.name === "string" ? input.name : "");
  const kind = readKind(input?.kindCode);
  if (!isUuid(input?.idempotencyKey)) return { ok: false, reason: "unavailable" };
  if (name === null) return { ok: false, reason: "invalid_name" };
  if (kind === "invalid") return { ok: false, reason: "invalid_kind" };

  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("create_my_storage_container", {
    p_idempotency_key: input.idempotencyKey,
    p_name: name,
    p_kind_code: kind,
  });
  if (error) return fail("create_my_storage_container", startedAt, error);
  const row = Array.isArray(data) ? (data[0] as Record<string, unknown> | undefined) : undefined;
  // Replay de um pedido cujo local já foi excluído: 5216 devolve id nulo e nunca recria.
  if (!row || !isUuid(row.storage_container_id) || typeof row.name !== "string") {
    return fail("create_my_storage_container", startedAt, { code: row ? "REPLAY_DELETED" : "BAD_SHAPE" }, "not_found");
  }
  console.info(JSON.stringify({ scope: "colecoes.locais_create", ms: Date.now() - startedAt, replayed: row.replayed === true }));
  revalidateStorageViews();
  return {
    ok: true,
    replayed: row.replayed === true,
    id: row.storage_container_id,
    name: row.name,
    kindCode: typeof row.kind_code === "string" ? row.kind_code : null,
  };
}

/** Renomeia e/ou troca o tipo (`kindCode` nulo = sem tipo). Idempotente por estado. */
export async function updateStorageLocation(input: {
  id: string;
  name: string;
  kindCode: string | null;
}): Promise<({ ok: true; changed: boolean } & SavedLocation) | Fail> {
  const name = normalizeStorageName(typeof input?.name === "string" ? input.name : "");
  const kind = readKind(input?.kindCode);
  if (!isUuid(input?.id)) return { ok: false, reason: "not_found" };
  if (name === null) return { ok: false, reason: "invalid_name" };
  if (kind === "invalid") return { ok: false, reason: "invalid_kind" };

  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("update_my_storage_container", {
    p_storage_container_id: input.id,
    p_name: name,
    p_kind_code: kind,
  });
  if (error) return fail("update_my_storage_container", startedAt, error);
  const row = Array.isArray(data) ? (data[0] as Record<string, unknown> | undefined) : undefined;
  if (!row || !isUuid(row.storage_container_id) || typeof row.name !== "string") {
    return fail("update_my_storage_container", startedAt, { code: "BAD_SHAPE" });
  }
  const changed = row.changed === true;
  console.info(JSON.stringify({ scope: "colecoes.locais_update", ms: Date.now() - startedAt, changed }));
  if (changed) revalidateStorageViews();
  return {
    ok: true,
    changed,
    id: row.storage_container_id,
    name: row.name,
    kindCode: typeof row.kind_code === "string" ? row.kind_code : null,
  };
}

/**
 * Exclui um local vazio que não é local padrão de nenhuma coleção. Os
 * bloqueios (exemplares, local padrão, uso concorrente) vêm do banco; o
 * histórico de criação é preservado pela FK SET NULL (R4, 5214/5215).
 */
export async function deleteStorageLocation(input: { id: string }): Promise<{ ok: true; id: string } | Fail> {
  if (!isUuid(input?.id)) return { ok: false, reason: "not_found" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("delete_my_storage_container", { p_storage_container_id: input.id });
  if (error) {
    const result = fail("delete_my_storage_container", startedAt, error);
    // Bloqueio ou corrida: a lista da página está desatualizada — o próximo render traz o estado real.
    if (result.reason !== "unavailable" && result.reason !== "not_authenticated") revalidatePath(LOCAIS_PATH);
    return result;
  }
  const row = Array.isArray(data) ? (data[0] as Record<string, unknown> | undefined) : undefined;
  if (!row || row.deleted !== true) return fail("delete_my_storage_container", startedAt, { code: "BAD_SHAPE" });
  console.info(JSON.stringify({ scope: "colecoes.locais_delete", ms: Date.now() - startedAt }));
  revalidateStorageViews();
  return { ok: true, id: input.id };
}

/** Telas que mostram nomes de locais: Meus locais, criação/Ajustes de coleção e o detalhe do acervo. */
function revalidateStorageViews() {
  revalidatePath(LOCAIS_PATH);
  revalidatePath(COLECOES_PATH, "layout");
  revalidatePath(ACERVO_PATH);
}

function fail(
  fn: string,
  startedAt: number,
  error: { code?: string; message?: string } | null,
  forced?: StorageFailure,
): Fail {
  const reason = forced ?? storageFailureFromError(error);
  // Sem dados do usuário: só função, duração, código e a classe do erro.
  console.error(JSON.stringify({ scope: "colecoes.write", fn, ms: Date.now() - startedAt, code: error?.code ?? "NO_DATA", reason }));
  return { ok: false, reason };
}
