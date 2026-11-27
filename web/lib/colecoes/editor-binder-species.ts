import { isSpeciesPlanToken } from "./binder-species.ts";

/**
 * V1-13 · E3-6 / F2 — referências de espécie pelo EDITOR (5383), regras puras.
 *
 * Contrato conferido na versão protegida implantada (5383 v1.1):
 *  - `editor_preview_binder_species_references(p_collection_id)` → positions_in_scope,
 *    slots_total, pair_count, slots_left_free, positions_unplaced, first_page,
 *    last_page, first_number, last_number, existing_count, already_applied,
 *    plan_token. SEM `slots_with_content` (C-243: revelaria conteúdo mascarado)
 *    e SEM o estado de exibição (mostrar/ocultar).
 *  - `editor_apply_binder_species_references(p_collection_id, p_plan_token)` →
 *    (operation APPLIED | ALREADY_APPLIED, reference_count, references_visible).
 *  - `editor_clear_binder_species_references(p_collection_id, p_expected_count)` →
 *    (operation REMOVED, removed_count).
 *  - `editor_set_binder_species_reference_visibility(p_collection_id, p_visible)` →
 *    (references_visible, operation UPDATED | UNCHANGED).
 *  As quatro operam sobre a camada INTEIRA do fichário (bolso n ↔ posição n da
 *  Pokédex), nunca por bolso; só no fichário EXCLUSIVO de X (Pokédex, sem
 *  convidadas, sem referências de outra coleção). Nenhuma toca carta, reserva,
 *  imagem, página, alocação ou local.
 *
 * O que a tela NÃO sabe: o fichário compartilhado (5315) nunca devolve
 * referências de espécie, e nenhuma leitura de participante diz se elas estão
 * visíveis. Por isso: nada de interruptor com estado presumido — "mostrar" e
 * "ocultar" são duas ações explícitas, e o resultado vem do servidor.
 */

export type EditorSpeciesPreview = {
  positionsInScope: number;
  slotsTotal: number;
  pairCount: number;
  slotsLeftFree: number;
  positionsUnplaced: number;
  firstPage: number | null;
  lastPage: number | null;
  firstNumber: number | null;
  lastNumber: number | null;
  existingCount: number;
  alreadyApplied: boolean;
  planToken: string;
};

function int(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) ? value : null;
}

function rowOf(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? (data.length === 1 ? data[0] : null) : data;
  return row && typeof row === "object" && !Array.isArray(row) ? (row as Record<string, unknown>) : null;
}

export function parseEditorSpeciesPreview(data: unknown): EditorSpeciesPreview | null {
  const row = rowOf(data);
  if (!row) return null;
  const count = (key: string): number | null => {
    const v = int(row[key]);
    return v !== null && v >= 0 ? v : null;
  };
  const positionsInScope = count("positions_in_scope");
  const slotsTotal = count("slots_total");
  const pairCount = count("pair_count");
  const slotsLeftFree = count("slots_left_free");
  const positionsUnplaced = count("positions_unplaced");
  const existingCount = count("existing_count");
  if (positionsInScope === null || slotsTotal === null || pairCount === null || slotsLeftFree === null || positionsUnplaced === null || existingCount === null) return null;
  if (typeof row.already_applied !== "boolean" || !isSpeciesPlanToken(row.plan_token)) return null;
  return {
    positionsInScope,
    slotsTotal,
    pairCount,
    slotsLeftFree,
    positionsUnplaced,
    firstPage: int(row.first_page),
    lastPage: int(row.last_page),
    firstNumber: int(row.first_number),
    lastNumber: int(row.last_number),
    existingCount,
    alreadyApplied: row.already_applied,
    planToken: row.plan_token,
  };
}

/** O que a prévia permite oferecer (sem inferir nada além dela). */
export type EditorSpeciesStage = "apply" | "applied" | "outdated" | "nothing";

export function editorSpeciesStage(preview: EditorSpeciesPreview): EditorSpeciesStage {
  if (preview.existingCount === 0) return preview.pairCount > 0 ? "apply" : "nothing";
  // Há referências, mas não as do plano atual (páginas mudaram): a 5383 recusa aplicar por cima.
  return preview.alreadyApplied ? "applied" : "outdated";
}

export type ApplyResult = { operation: "APPLIED" | "ALREADY_APPLIED"; referenceCount: number; visible: boolean };
export type ClearResult = { removedCount: number };
export type VisibilityResult = { visible: boolean; changed: boolean };

export function parseEditorSpeciesApply(data: unknown): ApplyResult | null {
  const row = rowOf(data);
  const n = row ? int(row.reference_count) : null;
  if (!row || (row.operation !== "APPLIED" && row.operation !== "ALREADY_APPLIED") || n === null || n < 0 || typeof row.references_visible !== "boolean") return null;
  return { operation: row.operation, referenceCount: n, visible: row.references_visible };
}

export function parseEditorSpeciesClear(data: unknown): ClearResult | null {
  const row = rowOf(data);
  const n = row ? int(row.removed_count) : null;
  if (!row || row.operation !== "REMOVED" || n === null || n < 0) return null;
  return { removedCount: n };
}

export function parseEditorSpeciesVisibility(data: unknown): VisibilityResult | null {
  const row = rowOf(data);
  if (!row || typeof row.references_visible !== "boolean" || (row.operation !== "UPDATED" && row.operation !== "UNCHANGED")) return null;
  return { visible: row.references_visible, changed: row.operation === "UPDATED" };
}

export function validExpectedCount(value: unknown): value is number {
  return typeof value === "number" && Number.isInteger(value) && value >= 0 && value <= 100_000;
}

// ---------------------------------------------------------------------------
// Recusas — só o código e o NOME da exceção; `hint`/`detail` nunca são lidos.

export type EditorSpeciesFailure =
  | "unavailable"
  | "owner_only"
  | "access_lost"
  | "archived"
  | "not_pokedex"
  | "plan_changed"
  | "present"
  | "nothing"
  | "count_mismatch"
  | "lock_busy"
  | "not_authenticated"
  | "invalid"
  | "unknown";

export type EditorSpeciesFail = { reason: EditorSpeciesFailure; message: string; disables: boolean; recheck: boolean; reloadPreview: boolean };

export function classifyEditorSpeciesFailure(code: string | null | undefined, message: string | null | undefined): EditorSpeciesFailure {
  const text = (message ?? "").trim();
  if (text === "CAPABILITY_NOT_ENABLED") return "unavailable";
  if (code === "PGRST202" || code === "42883") return "unavailable";
  if (text === "OPERATION_RESERVED_TO_OWNER") return "owner_only";
  if (text === "COLLECTION_NOT_FOUND" || text === "BINDER_NOT_FOUND") return "access_lost";
  if (text === "COLLECTION_ARCHIVED") return "archived";
  if (text === "NOT_POKEDEX_COLLECTION") return "not_pokedex";
  if (text === "PLAN_CHANGED") return "plan_changed";
  if (text === "SPECIES_REFERENCES_PRESENT") return "present";
  if (text === "NOTHING_TO_APPLY") return "nothing";
  if (text === "COUNT_MISMATCH") return "count_mismatch";
  if (code === "55P03") return "lock_busy";
  if (code === "28000" || text === "not_authenticated") return "not_authenticated";
  if (code === "P0002") return "access_lost";
  if (code === "22023" || code === "22P02") return "invalid";
  return "unknown";
}

export function editorSpeciesFailureMessage(reason: EditorSpeciesFailure): string {
  switch (reason) {
    case "unavailable":
      return "A organização compartilhada ainda não está disponível.";
    case "owner_only":
      return "Neste fichário, os Pokémon dos bolsos são definidos pelo titular.";
    case "access_lost":
      return "Sua permissão para organizar este fichário mudou.";
    case "archived":
      return "A coleção está arquivada. O fichário fica só para leitura.";
    case "not_pokedex":
      return "Os Pokémon nos bolsos existem só nos fichários de coleções Pokédex.";
    case "plan_changed":
      return "O fichário mudou desde a prévia. Revise e confirme de novo.";
    case "present":
      return "Este fichário já tem Pokémon nos bolsos. A prévia foi atualizada.";
    case "nothing":
      return "Não há bolsos ou Pokémon para posicionar.";
    case "count_mismatch":
      return "A quantidade de referências mudou. A prévia foi atualizada; revise antes de remover.";
    case "lock_busy":
      return "O fichário está sendo alterado. Tente de novo em instantes.";
    case "not_authenticated":
      return "Sua sessão expirou. Entre de novo para continuar.";
    case "invalid":
      return "Não foi possível concluir. Nada foi alterado; tente de novo.";
    default:
      return "Não foi possível confirmar o resultado. Abra de novo para conferir antes de repetir.";
  }
}

export function editorSpeciesFail(reason: EditorSpeciesFailure): EditorSpeciesFail {
  return {
    reason,
    message: editorSpeciesFailureMessage(reason),
    disables: reason === "unavailable" || reason === "access_lost" || reason === "archived" || reason === "not_authenticated",
    recheck: reason === "access_lost",
    reloadPreview: reason === "plan_changed" || reason === "present" || reason === "count_mismatch" || reason === "nothing",
  };
}

/** Escrita sem resposta legível: pode ter acontecido. Nunca repetir sozinho. */
export function speciesWriteUncertain(reason: EditorSpeciesFailure): boolean {
  return reason === "unknown";
}

export function applyMessage(result: ApplyResult): string {
  if (result.operation === "ALREADY_APPLIED") return "Os Pokémon já estavam associados aos bolsos.";
  const n = result.referenceCount;
  const base = n === 1 ? "1 Pokémon foi associado aos bolsos vazios." : `${n.toLocaleString("pt-BR")} Pokémon foram associados aos bolsos vazios.`;
  return result.visible ? base : `${base} A exibição está desligada neste fichário.`;
}

export function visibilityMessage(result: VisibilityResult): string {
  if (result.visible) return result.changed ? "Os Pokémon de referência voltam a aparecer nos bolsos vazios." : "Os Pokémon de referência já estavam visíveis.";
  return result.changed ? "Os Pokémon de referência foram ocultados. A associação continua." : "Os Pokémon de referência já estavam ocultos.";
}

export function clearMessage(result: ClearResult): string {
  return result.removedCount === 1
    ? "1 referência foi removida. Cartas, reservas e páginas não mudaram."
    : `${result.removedCount.toLocaleString("pt-BR")} referências foram removidas. Cartas, reservas e páginas não mudaram.`;
}
