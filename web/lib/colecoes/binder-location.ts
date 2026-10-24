import { pluralize } from "./acervo.ts";

/**
 * Fichário Digital = fichário físico (BINDER-PHYSICAL-LOCATION, 5247–5256) —
 * regras puras, sem banco e sem React (testável com `node --test`).
 *
 * D3: um exemplar posicionado num bolso que muda de local físico sai do
 * bolso — só com confirmação explícita, na mesma transação; bolso travado
 * impede a mudança até ser destravado. As prévias (5249) contam quantos
 * sairiam e quantos estão travados; os escritores confirmados recebem
 * `p_unplace_from_binder` e recusam com BINDER_POSITION_* quando falta
 * confirmação ou há cadeado.
 */

export type BinderImpact = { positioned: number; locked: number };

export const NO_BINDER_IMPACT: BinderImpact = { positioned: 0, locked: 0 };

function int(value: unknown): number | null {
  const n = typeof value === "string" && value.trim() !== "" ? Number(value) : value;
  return typeof n === "number" && Number.isInteger(n) && n >= 0 ? n : null;
}

/** Linha das prévias 5249 (`positioned_count`, `locked_count`) → impacto; `null` = formato inesperado. */
export function parseBinderImpact(rows: unknown): BinderImpact | null {
  if (!Array.isArray(rows)) return null;
  if (rows.length === 0) return NO_BINDER_IMPACT;
  if (rows.length !== 1 || !rows[0] || typeof rows[0] !== "object") return null;
  const r = rows[0] as Record<string, unknown>;
  const positioned = int(r.positioned_count);
  const locked = int(r.locked_count);
  if (positioned === null || locked === null) return null;
  return { positioned, locked };
}

export type BinderPositionBlock = "confirm_required" | "locked";

/** Recusa do banco por posição no fichário (5249/5256), ou `null` se o erro é outro. */
export function binderPositionBlock(error: { code?: string | null; message?: string | null } | null | undefined): BinderPositionBlock | null {
  const text = (error?.message ?? "").trim();
  if (text === "BINDER_POSITION_LOCKED") return "locked";
  if (text === "BINDER_POSITION_CONFIRMATION_REQUIRED") return "confirm_required";
  return null;
}

/** Aviso da prévia: quantos exemplares deixam os bolsos do fichário digital. */
export function binderUnplaceNotice(positioned: number): string | null {
  if (positioned <= 0) return null;
  return `${pluralize(positioned, "exemplar está", "exemplares estão")} num bolso do fichário digital e ${positioned === 1 ? "sairá do bolso" : "sairão dos bolsos"} ao mudar de local. A carta continua no acervo e na coleção.`;
}

/** Bloqueio por cadeado: a mudança não acontece enquanto houver bolso travado. */
export function binderLockedNotice(locked: number): string | null {
  if (locked <= 0) return null;
  return `${pluralize(locked, "exemplar está", "exemplares estão")} num bolso fixado do fichário digital. Solte o cadeado no fichário antes de mudar o local — nada foi alterado.`;
}

/** Rótulo curto da linha "No fichário digital" das prévias. */
export function binderImpactSummary(impact: BinderImpact): string | null {
  if (impact.locked > 0) return `${pluralize(impact.locked, "em bolso fixado", "em bolsos fixados")} — destrave antes`;
  if (impact.positioned > 0) return `${pluralize(impact.positioned, "sai do bolso", "saem dos bolsos")}`;
  return null;
}

// ---------------------------------------------------------------------------
// Transferência da âncora do fichário (5254) — caminho seguro antes de excluir
// a coleção proprietária. A interface ainda não expõe exclusão de coleção;
// o contrato fica pronto para quando expuser.
// ---------------------------------------------------------------------------

export type TransferOutcome = { outcome: "TRANSFERRED" | "UNCHANGED"; layoutId: string; reservationsPinned: number };

export function parseTransferOutcome(rows: unknown): TransferOutcome | null {
  const row = Array.isArray(rows) && rows.length === 1 ? (rows[0] as Record<string, unknown> | undefined) : undefined;
  if (!row || (row.outcome !== "TRANSFERRED" && row.outcome !== "UNCHANGED")) return null;
  const layoutId = typeof row.layout_id === "string" ? row.layout_id : null;
  const pinned = int(row.reservations_pinned);
  if (!layoutId || pinned === null) return null;
  return { outcome: row.outcome, layoutId, reservationsPinned: pinned };
}

export type TransferFailure =
  | "not_found"
  | "not_owner"
  | "target_archived"
  | "target_has_binder"
  | "target_is_guest"
  | "lock_busy"
  | "not_authenticated"
  | "invalid"
  | "unknown";

export function classifyTransferFailure(code: string | null | undefined, message: string | null | undefined): TransferFailure {
  const text = (message ?? "").trim();
  if (text === "BINDER_NOT_OWNED") return "not_owner";
  if (text === "COLLECTION_ARCHIVED") return "target_archived";
  if (text === "COLLECTION_HAS_OWN_BINDER") return "target_has_binder";
  if (text === "COLLECTION_IS_BINDER_GUEST") return "target_is_guest";
  if (code === "55P03") return "lock_busy";
  if (text === "COLLECTION_NOT_FOUND" || code === "P0002") return "not_found";
  if (code === "28000" || code === "42501" || text === "not_authenticated") return "not_authenticated";
  if (code === "22023" || code === "22P02") return "invalid";
  return "unknown";
}
