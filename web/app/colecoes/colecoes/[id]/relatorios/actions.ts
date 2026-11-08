"use server";

import { isCollectionId } from "@/lib/colecoes/colecoes";
import { type ChecklistReportData, prepareChecklistReport } from "@/lib/reports/checklist-queries";
import { type CollectionValueReportData, prepareCollectionValueReport } from "@/lib/reports/collection-value-queries";
import { type CompletionHistoryReportData, prepareCompletionHistoryReport } from "@/lib/reports/completion-history-queries";
import { type MissingCardsReportData, prepareMissingCardsReport } from "@/lib/reports/missing-cards-queries";
import { type SetFavoritesReportData, prepareSetFavoritesReport } from "@/lib/reports/set-favorites-queries";
import { type SetWishlistReportData, prepareSetWishlistReport } from "@/lib/reports/set-wishlist-queries";
import { parseChecklistFilter } from "@/lib/reports/collection-checklist";
import { createClient } from "@/lib/supabase/server";
import { getCachedUser } from "@/lib/supabase/request-auth-cache";

export type ChecklistReportResult =
  | { ok: true; data: ChecklistReportData }
  | { ok: false; reason: "not_found" | "unavailable" | "error" };

/**
 * V1-14 R1-A (UX REDIRECTION-02) — dados do Checklist para a sobreposição aberta SOBRE a coleção.
 * Mesma preparação da rota de acesso direto (`prepareChecklistReport`): só o titular
 * (`get_my_collection` + leituras `get_my_*`, todas restritas a `auth.uid()`), conjunto inteiro
 * do filtro, nenhuma escrita. Coleção alheia, compartilhada com você ou inexistente → `not_found`,
 * sem distinguir os casos.
 */
export async function readChecklistReport(input: { collectionId: string; filter: string }): Promise<ChecklistReportResult> {
  if (!isCollectionId(input?.collectionId)) return { ok: false, reason: "not_found" };
  const {
    data: { user },
  } = await getCachedUser();
  if (!user) return { ok: false, reason: "not_found" };
  const supabase = await createClient();
  try {
    const result = await prepareChecklistReport(supabase, input.collectionId.toLowerCase(), parseChecklistFilter(input.filter));
    if (result.status === "ready") return { ok: true, data: result.data };
    return { ok: false, reason: result.status };
  } catch (error) {
    console.error("[reports] readChecklistReport falhou", { message: error instanceof Error ? error.message : "unknown" });
    return { ok: false, reason: "error" };
  }
}

export type MissingCardsReportResult =
  | { ok: true; data: MissingCardsReportData }
  | { ok: false; reason: "not_found" | "unavailable" | "error" };

/**
 * V1-14 R2-B — "Cartas faltantes" para a sobreposição da coleção: a mesma preparação do Checklist
 * com o filtro de faltantes (`prepareMissingCardsReport`). Só o titular (`get_my_collection` +
 * leituras `get_my_*`, restritas a `auth.uid()`); coleção alheia, compartilhada com você ou
 * inexistente → `not_found`, sem distinguir. Somente leitura.
 */
export async function readMissingCardsReport(input: { collectionId: string }): Promise<MissingCardsReportResult> {
  if (!isCollectionId(input?.collectionId)) return { ok: false, reason: "not_found" };
  const {
    data: { user },
  } = await getCachedUser();
  if (!user) return { ok: false, reason: "not_found" };
  const supabase = await createClient();
  try {
    const result = await prepareMissingCardsReport(supabase, input.collectionId.toLowerCase());
    if (result.status === "ready") return { ok: true, data: result.data };
    return { ok: false, reason: result.status };
  } catch (error) {
    console.error("[reports] readMissingCardsReport falhou", { message: error instanceof Error ? error.message : "unknown" });
    return { ok: false, reason: "error" };
  }
}

export type SetWishlistReportResult =
  | { ok: true; data: SetWishlistReportData }
  | { ok: false; reason: "not_found" | "unavailable" | "error" };

/**
 * V1-14 R2-C — "Cartas desejadas do Card Set" para a sobreposição da coleção: coleção autorizada
 * primeiro (5332), depois os desejos do Card Set DELA (5351) e as referências NM (3989) —
 * `prepareSetWishlistReport`. Só o titular; nenhum Card Set nem identificador vindo do cliente
 * (só o id da coleção, validado); somente leitura.
 */
export async function readSetWishlistReport(input: { collectionId: string }): Promise<SetWishlistReportResult> {
  if (!isCollectionId(input?.collectionId)) return { ok: false, reason: "not_found" };
  const {
    data: { user },
  } = await getCachedUser();
  if (!user) return { ok: false, reason: "not_found" };
  const supabase = await createClient();
  try {
    // Miniaturas: mesma origem pública da Lista de desejos (bucket `card-front`, síncrono, sem transformação).
    const imageUrl = (path: string) => supabase.storage.from("card-front").getPublicUrl(path).data.publicUrl ?? null;
    const result = await prepareSetWishlistReport(supabase, input.collectionId.toLowerCase(), imageUrl);
    if (result.status === "ready") return { ok: true, data: result.data };
    return { ok: false, reason: result.status };
  } catch (error) {
    console.error("[reports] readSetWishlistReport falhou", { message: error instanceof Error ? error.message : "unknown" });
    return { ok: false, reason: "error" };
  }
}

export type SetFavoritesReportResult =
  | { ok: true; data: SetFavoritesReportData }
  | { ok: false; reason: "not_found" | "unavailable" | "error" };

/**
 * V1-14 R2-D — "Cartas favoritas do Card Set" para a sobreposição da coleção: coleção autorizada
 * primeiro (5332), depois as favoritas do Card Set DELA (5356), a referência por carta e a posse no
 * acervo (regras da R1-D) — `prepareSetFavoritesReport`. Só o titular; nenhum Card Set nem
 * identificador vindo do cliente (só o id da coleção, validado); somente leitura.
 */
export async function readSetFavoritesReport(input: { collectionId: string }): Promise<SetFavoritesReportResult> {
  if (!isCollectionId(input?.collectionId)) return { ok: false, reason: "not_found" };
  const {
    data: { user },
  } = await getCachedUser();
  if (!user) return { ok: false, reason: "not_found" };
  const supabase = await createClient();
  try {
    // Miniaturas: mesma origem pública da página Cartas favoritas (bucket `card-front`, síncrono, sem transformação).
    const imageUrl = (path: string) => supabase.storage.from("card-front").getPublicUrl(path).data.publicUrl ?? null;
    const result = await prepareSetFavoritesReport(supabase, input.collectionId.toLowerCase(), imageUrl);
    if (result.status === "ready") return { ok: true, data: result.data };
    return { ok: false, reason: result.status };
  } catch (error) {
    console.error("[reports] readSetFavoritesReport falhou", { message: error instanceof Error ? error.message : "unknown" });
    return { ok: false, reason: "error" };
  }
}

export type CollectionValueReportResult =
  | { ok: true; data: CollectionValueReportData }
  | { ok: false; reason: "not_found" | "unavailable" | "error" };

/**
 * V1-14 R2-E — "Valor estimado dos exemplares alocados" para a sobreposição da coleção (D7 §4m):
 * coleção autorizada primeiro (5332), depois os exemplares ALOCADOS a ela (5159 com o id da coleção
 * autorizada, páginas em sequência) e a referência NM por variante (3989, concorrência 2) —
 * `prepareCollectionValueReport`. Só o titular; nenhum identificador do cliente além do id da
 * coleção, validado; somente leitura; cálculo financeiro só no servidor.
 */
export async function readCollectionValueReport(input: { collectionId: string }): Promise<CollectionValueReportResult> {
  if (!isCollectionId(input?.collectionId)) return { ok: false, reason: "not_found" };
  const {
    data: { user },
  } = await getCachedUser();
  if (!user) return { ok: false, reason: "not_found" };
  const supabase = await createClient();
  try {
    // Miniaturas: mesma origem pública dos demais relatórios (bucket `card-front`, sem transformação).
    const imageUrl = (path: string) => supabase.storage.from("card-front").getPublicUrl(path).data.publicUrl ?? null;
    const result = await prepareCollectionValueReport(supabase, input.collectionId.toLowerCase(), imageUrl);
    if (result.status === "ready") return { ok: true, data: result.data };
    return { ok: false, reason: result.status };
  } catch (error) {
    console.error("[reports] readCollectionValueReport falhou", { message: error instanceof Error ? error.message : "unknown" });
    return { ok: false, reason: "error" };
  }
}

export type CompletionHistoryReportResult =
  | { ok: true; data: CompletionHistoryReportData }
  | { ok: false; reason: "not_found" | "unavailable" | "error" };

/**
 * V1-14 R2-F (B2) — "Evolução da completude" para a sobreposição da coleção (D7 §4n): coleção
 * autorizada primeiro (5332, com a completude atual canônica da 5188), depois o histórico do titular
 * (5358 `get_my_collection_completion_history`, com o id da coleção autorizada) —
 * `prepareCompletionHistoryReport`. Só o titular; coleção alheia, compartilhada com você ou
 * inexistente → `not_found`, sem distinguir; somente leitura.
 */
export async function readCompletionHistoryReport(input: { collectionId: string }): Promise<CompletionHistoryReportResult> {
  if (!isCollectionId(input?.collectionId)) return { ok: false, reason: "not_found" };
  const {
    data: { user },
  } = await getCachedUser();
  if (!user) return { ok: false, reason: "not_found" };
  const supabase = await createClient();
  try {
    const result = await prepareCompletionHistoryReport(supabase, input.collectionId.toLowerCase());
    if (result.status === "ready") return { ok: true, data: result.data };
    return { ok: false, reason: result.status };
  } catch (error) {
    console.error("[reports] readCompletionHistoryReport falhou", { message: error instanceof Error ? error.message : "unknown" });
    return { ok: false, reason: "error" };
  }
}
