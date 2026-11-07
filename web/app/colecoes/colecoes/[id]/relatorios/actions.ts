"use server";

import { isCollectionId } from "@/lib/colecoes/colecoes";
import { type ChecklistReportData, prepareChecklistReport } from "@/lib/reports/checklist-queries";
import { type MissingCardsReportData, prepareMissingCardsReport } from "@/lib/reports/missing-cards-queries";
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
