import type { BinderSlot } from "./binder.ts";
import { isOccupied } from "./binder.ts";
import { GAP_ROW_LIMIT, type GapOutcome, type GapPreview } from "./binder-insert.ts";
import {
  type EditorFailure,
  type PocketPosition,
  classifyEditorFailure,
  editorFailureDisablesEditing,
  editorFailureMessage,
  editorFailureRechecksAccess,
  isPocketPosition,
} from "./editor-binder.ts";

/**
 * V1-13 · E2-3B — abrir e fechar espaço pelo EDITOR (5385), por POSIÇÃO.
 * Regras puras, sem rede.
 *
 * O servidor é a autoridade: fichário exclusivo da coleção (C-237), cadeia
 * inteira de X ou livre conferida sob as travas antes de qualquer escrita,
 * mesmo plano e token do titular (g1/u1), bolso fixado ou mesclado como
 * barreira e referências de espécie paradas no lugar. A prévia do EDITOR não
 * traz posição de barreira, imagens nem ids — e a tela não tenta deduzi-los.
 */

const OUTCOMES = new Set<GapOutcome>(["NOT_FOUND", "ALREADY_FREE", "AT_BARRIER", "BLOCKED", "OVER_LIMIT", "SAME_PAGE", "CROSS_PAGE", "NEEDS_PAGE"]);
const PLAN_TOKEN = /^g1:[0-9a-f]{64}$/;
const UNDO_TOKEN = /^u1:[0-9a-f]{64}$/;

function int(value: unknown): number | null {
  const n = typeof value === "number" ? value : typeof value === "string" && value.trim() !== "" ? Number(value) : Number.NaN;
  return Number.isInteger(n) ? n : null;
}

function first(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : null;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

export function isGapPlanToken(value: unknown): value is string {
  return typeof value === "string" && PLAN_TOKEN.test(value);
}

export function isGapUndoToken(value: unknown): value is string {
  return typeof value === "string" && UNDO_TOKEN.test(value);
}

/**
 * Prévia da 5385 → a mesma forma da prévia do titular (para o diálogo do
 * titular), sem nada que a 5385 não entrega: barreira, imagens e ids ficam
 * vazios de propósito.
 */
export function parseEditorGapPreview(data: unknown): GapPreview | null {
  const r = first(data);
  if (!r) return null;
  const outcome = r.outcome as GapOutcome;
  if (!OUTCOMES.has(outcome)) return null;
  const pagesRaw = Array.isArray(r.pages) ? r.pages.map(int) : [];
  if (pagesRaw.some((p) => p === null || p < 1)) return null;
  const planToken = typeof r.plan_token === "string" && r.plan_token.length > 0 ? r.plan_token : null;
  if (planToken !== null && !isGapPlanToken(planToken)) return null;
  const executable = outcome === "SAME_PAGE" || outcome === "CROSS_PAGE" || outcome === "NEEDS_PAGE";
  if (executable && !planToken) return null;
  return {
    outcome,
    movedPockets: Math.max(0, int(r.moved_pockets) ?? 0),
    movedCards: Math.max(0, int(r.moved_cards) ?? 0),
    movedReserves: Math.max(0, int(r.moved_reserves) ?? 0),
    movedImages: 0,
    rowsMoved: Math.max(0, int(r.rows_moved) ?? 0),
    rowLimit: int(r.row_limit) ?? GAP_ROW_LIMIT,
    pages: pagesRaw as number[],
    targetSlotId: null,
    barrier: null,
    planToken,
  };
}

/** Desfazer de um espaço aberto pelo EDITOR: tudo por posição, como a 5385 pede. */
export type EditorGapUndo = { gap: PocketPosition; end: PocketPosition; undoToken: string; addedPageNumber: number | null };

export type EditorGapInsert =
  | { outcome: "ALREADY_FREE" }
  | { outcome: "INSERTED"; movedPockets: number; pages: number[]; addedPageNumber: number | null; undo: EditorGapUndo };

export function parseEditorGapInsert(data: unknown, gap: PocketPosition): EditorGapInsert | null {
  const r = first(data);
  if (!r) return null;
  if (r.outcome === "ALREADY_FREE") return { outcome: "ALREADY_FREE" };
  if (r.outcome !== "INSERTED") return null;
  const end = { page: int(r.end_page), row: int(r.end_row), column: int(r.end_column) };
  if (!isPocketPosition(end)) return null;
  if (!isGapUndoToken(r.undo_token)) return null;
  const added = r.added_page_number === null || r.added_page_number === undefined ? null : int(r.added_page_number);
  if (added !== null && added < 1) return null;
  const pages = Array.isArray(r.pages) ? r.pages.map(int).filter((p): p is number => p !== null && p >= 1) : [];
  return {
    outcome: "INSERTED",
    movedPockets: Math.max(0, int(r.moved_pockets) ?? 0),
    pages,
    addedPageNumber: added,
    undo: { gap, end: end as PocketPosition, undoToken: r.undo_token, addedPageNumber: added },
  };
}

export function parseEditorGapClose(data: unknown): { movedPockets: number; pageRemoved: boolean } | null {
  const r = first(data);
  if (!r || r.outcome !== "CLOSED") return null;
  return { movedPockets: Math.max(0, int(r.moved_pockets) ?? 0), pageRemoved: r.page_removed === true };
}

// ---------------------------------------------------------------------------
// Recusas. Só o código e o NOME da exceção: `hint`/`details` nunca são lidos
// (a 5385 descreve no hint o motivo da recusa e quantos itens excedem o limite).

export type EditorGapFailure = "plan_changed" | "blocked" | "over_limit" | "undo_expired" | "inconsistent" | "slot_not_found" | "reserved_to_owner" | EditorFailure;

export function classifyEditorGapFailure(code: string | null | undefined, message: string | null | undefined): EditorGapFailure {
  const text = (message ?? "").trim().toUpperCase();
  if (text === "GAP_PLAN_CHANGED") return "plan_changed";
  // A confirmação exigida só pode faltar se o plano mudou depois da prévia (a tela sempre envia a da prévia).
  if (text === "GAP_CONFIRMATION_REQUIRED") return "plan_changed";
  if (text === "GAP_BLOCKED") return "blocked";
  if (text === "GAP_OVER_LIMIT") return "over_limit";
  if (text === "GAP_UNDO_EXPIRED") return "undo_expired";
  if (text === "GAP_INCONSISTENT") return "inconsistent";
  if (text === "SLOT_NOT_FOUND") return "slot_not_found";
  if (text === "OPERATION_RESERVED_TO_OWNER") return "reserved_to_owner";
  return classifyEditorFailure(code, message);
}

const GAP_OWN = new Set(["plan_changed", "blocked", "over_limit", "undo_expired", "inconsistent", "slot_not_found", "reserved_to_owner"]);

export function editorGapFailureDisablesEditing(reason: EditorGapFailure): boolean {
  return !GAP_OWN.has(reason) && editorFailureDisablesEditing(reason as EditorFailure);
}

export function editorGapFailureRechecksAccess(reason: EditorGapFailure): boolean {
  return !GAP_OWN.has(reason) && editorFailureRechecksAccess(reason as EditorFailure);
}

/**
 * Resultado de uma escrita que pode ter mexido nas posições? Recusas do banco
 * desfazem a transação inteira (nada andou); só o resultado incerto (rede,
 * tempo esgotado) é tratado como "pode ter andado".
 */
export function gapOutcomeUncertain(reason: EditorGapFailure): boolean {
  return reason === "unknown";
}

/** Mensagem neutra: nunca diz o que ocupa o caminho nem onde está a barreira. */
export function editorGapFailureMessage(op: "preview" | "insert" | "close", reason: EditorGapFailure): string {
  switch (reason) {
    case "plan_changed":
      return "O fichário mudou desde a prévia. Veja a prévia de novo antes de abrir o espaço.";
    case "blocked":
      return "Um bolso fixado ou com imagem está no caminho. Nada foi movido.";
    case "over_limit":
      return "Isso moveria itens demais de uma vez. Nada foi movido.";
    case "undo_expired":
      return "Não dá mais para desfazer: o fichário mudou depois que o espaço foi aberto.";
    case "inconsistent":
      return "Não foi possível abrir o espaço agora. Nada foi movido.";
    case "slot_not_found":
      return "Esse bolso não está mais neste fichário. Atualizamos as páginas.";
    case "reserved_to_owner":
      return op === "close" ? "Esse espaço só pode ser desfeito pelo titular agora." : "Neste fichário, esse espaço só pode ser aberto pelo titular.";
    case "unknown":
      return "Não conseguimos confirmar o resultado. Atualizamos o fichário — confira antes de tentar de novo.";
    default:
      return editorFailureMessage(reason);
  }
}

// ---------------------------------------------------------------------------
// Prévia → próximo passo (paridade com o titular: mesma página abre direto,
// com "Desfazer"; outra página ou página nova só com confirmação).

export type GapStep = "run" | "confirm" | "explain" | "already_free" | "at_barrier" | "not_found";

export function gapStep(preview: GapPreview): GapStep {
  switch (preview.outcome) {
    case "SAME_PAGE":
      return "run";
    case "CROSS_PAGE":
    case "NEEDS_PAGE":
      return "confirm";
    case "BLOCKED":
    case "OVER_LIMIT":
      return "explain";
    case "ALREADY_FREE":
      return "already_free";
    case "AT_BARRIER":
      return "at_barrier";
    case "NOT_FOUND":
      return "not_found";
  }
}

/** Confirmações enviadas: só as que a prévia mostrou e o EDITOR aceitou. */
export function gapConfirmations(preview: GapPreview): { crossPage: boolean; addPage: boolean } {
  return { crossPage: preview.outcome === "CROSS_PAGE" || preview.outcome === "NEEDS_PAGE", addPage: preview.outcome === "NEEDS_PAGE" };
}

export const AT_BARRIER_MESSAGE = "Não dá para abrir espaço a partir deste bolso.";

/**
 * Onde a tela OFERECE abrir espaço para o EDITOR: antes de carta ou reserva
 * desta coleção que ele vê, fora de bolso sabido fixado, imagem ou mesclagem.
 * Bolso que parece vazio não oferece (pode estar livre ou guardar conteúdo
 * que só o titular vê). Oferecer não autoriza: o servidor decide.
 */
export function editorCanInsertGap(slot: Pick<BinderSlot, "locked" | "regionId" | "image" | "state">): boolean {
  if (slot.locked || slot.regionId || slot.image) return false;
  return isOccupied(slot) || slot.state === "RESERVED_EMPTY";
}

export function gapInsertedMessage(movedPockets: number, addedPage: boolean): string {
  return (movedPockets === 1 ? "Espaço aberto: 1 bolso avançou." : `Espaço aberto: ${movedPockets} bolsos avançaram.`) + (addedPage ? " Uma página nova entrou no fim do fichário." : "");
}
