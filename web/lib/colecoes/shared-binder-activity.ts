import {
  ACTIVITY_FILTERS,
  ACTIVITY_PAGE_SIZE,
  type ActivityAttribution,
  type ActivityEvent,
  type ActivityFilterKey,
  type ActivityItem,
  categoryOf,
  classifyActivityFailure,
  parseActivityItem,
} from "./binder-activity.ts";

/**
 * V1-13 · E3-5 — histórico do fichário para participantes (5388), regras
 * puras, sem rede.
 *
 * Contrato (C-241 + D12–D14), conferido na 5388 implantada:
 *  - `get_shared_binder_activity(p_collection_id, p_categories, p_before_occurred_at,
 *    p_before_id, p_limit)` → event_id, occurred_at, event_type, category,
 *    source, is_legacy, actor_role ('OWNER' | 'PARTICIPANT' | null),
 *    actor_display_name, item_count (só itens VISÍVEIS), items (até 50, só
 *    campos de catálogo e posição), items_truncated. Limite 1..50; cursor
 *    (occurred_at, id) como na 5269; categorias da 5269/5341.
 *  - `get_shared_binder_activity_status(p_collection_id)` → has_binder,
 *    history_may_be_partial. Zero linhas = sem acesso OU barreira fechada.
 *  - Nunca saem summary, detail, ids de pessoas, coleção, fichário ou nomes
 *    gravados. Sem acesso (ou barreira fechada) → zero linhas, sem erro.
 *
 * Este módulo não preenche nada que a 5388 não devolve: nome da coleção, do
 * fichário e resumo ficam vazios; detalhes por item, também. Campos extras
 * que viessem na linha são ignorados.
 */

/** Filtros com suporte no contrato: a 5388 não mostra nenhum evento da categoria Fichário (E01, E17–E20 ocultos). */
export const SHARED_ACTIVITY_FILTERS: readonly { key: ActivityFilterKey; label: string }[] = ACTIVITY_FILTERS.filter((f) => f.key !== "BINDER");

export function isSharedActivityFilter(value: unknown): value is ActivityFilterKey {
  return SHARED_ACTIVITY_FILTERS.some((f) => f.key === value);
}

export const SHARED_ACTIVITY_PAGE_SIZE = ACTIVITY_PAGE_SIZE;

function obj(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value) ? (value as Record<string, unknown>) : null;
}

function int(value: unknown): number | null {
  const n = typeof value === "string" && value.trim() !== "" ? Number(value) : value;
  return typeof n === "number" && Number.isInteger(n) ? n : null;
}

function text(value: unknown): string | null {
  return typeof value === "string" && value.trim() !== "" ? value.trim() : null;
}

/**
 * Uma linha da 5388 → evento da tela. Formato inesperado → `null` (a página
 * inteira é recusada, nada é adivinhado). Só os campos do contrato são lidos.
 */
export function parseSharedActivityEvent(value: unknown): ActivityEvent | null {
  const r = obj(value);
  if (!r) return null;
  const id = int(r.event_id);
  const type = text(r.event_type);
  if (id === null || id < 1 || !type || typeof r.occurred_at !== "string" || Number.isNaN(Date.parse(r.occurred_at))) return null;
  const role = r.actor_role === null || r.actor_role === undefined ? null : r.actor_role;
  if (role !== null && role !== "OWNER" && role !== "PARTICIPANT") return null;
  if (!Array.isArray(r.items)) return null;
  const items: ActivityItem[] = [];
  for (const raw of r.items) {
    const item = parseActivityItem(raw);
    if (!item) return null;
    // Sem detalhe por item: a 5388 não devolve, e nada que viesse é exibido.
    items.push({ ...item, detail: null });
  }
  items.sort((a, b) => a.ordinal - b.ordinal);
  const itemCount = int(r.item_count);
  if (itemCount === null || itemCount < items.length) return null;
  const known = ["CARDS", "RESERVATIONS", "LOCKS", "PAGES", "CATALOG"] as const;
  const category = (known as readonly string[]).includes(r.category as string) ? (r.category as (typeof known)[number]) : categoryOf(type);
  const attribution: ActivityAttribution = { role, displayName: role === null ? null : text(r.actor_display_name) };
  return {
    id,
    occurredAt: r.occurred_at,
    type,
    category,
    source: text(r.source) ?? "",
    legacy: r.is_legacy === true,
    collectionName: null,
    binderName: null,
    summary: {},
    itemCount,
    items,
    truncated: r.items_truncated === true || itemCount > items.length,
    attribution,
  };
}

export function parseSharedActivityPage(data: unknown): ActivityEvent[] | null {
  if (data === null || data === undefined) return [];
  if (!Array.isArray(data)) return null;
  const events: ActivityEvent[] = [];
  for (const row of data) {
    const event = parseSharedActivityEvent(row);
    if (!event) return null;
    events.push(event);
  }
  return events;
}

/** `null` = zero linhas (sem acesso ou barreira fechada — indistinguíveis aqui); `undefined` = formato inválido. */
export type SharedActivityStatus = { hasBinder: boolean; mayBePartial: boolean };

export function parseSharedActivityStatus(data: unknown): SharedActivityStatus | null | undefined {
  if (data === null || data === undefined) return null;
  const row = Array.isArray(data) ? data[0] : data;
  if (row === undefined) return null;
  const r = obj(row);
  if (!r || typeof r.has_binder !== "boolean" || typeof r.history_may_be_partial !== "boolean") return undefined;
  return { hasBinder: r.has_binder, mayBePartial: r.history_may_be_partial };
}

// ---------------------------------------------------------------------------
// Estados e textos
// ---------------------------------------------------------------------------

/**
 * - `unavailable`: a leitura não devolveu o estado, mas a coleção ainda
 *   aparece para esta sessão (5312) — provavelmente configuração desligada
 *   ou barreira fechada, sem prova da causa;
 * - `access_lost`: nem o estado nem a releitura do participante (5312)
 *   devolvem a coleção — indício de acesso perdido, não prova;
 * - `no_binder`: a coleção não participa de um fichário agora (C-208);
 * - `not_authenticated`, `invalid`, `unknown`: como no histórico do titular.
 */
export type SharedActivityFailure = "unavailable" | "access_lost" | "no_binder" | "not_authenticated" | "invalid" | "unknown";

export function classifySharedActivityFailure(code?: string, message?: string): SharedActivityFailure {
  const reason = classifyActivityFailure(code, message);
  return reason === "unavailable" ? "unavailable" : reason;
}

export function sharedActivityFailureMessage(reason: SharedActivityFailure): string {
  switch (reason) {
    // V2: a causa de uma resposta vazia nem sempre é determinável — o texto não afirma uma causa que não foi comprovada.
    case "unavailable":
      return "O histórico compartilhado não está disponível agora.";
    case "access_lost":
      return "Não foi possível confirmar seu acesso a esta coleção. Recarregue a página para conferir.";
    case "no_binder":
      return "Esta coleção não está em um fichário agora. O histórico do fichário fica com o titular.";
    case "not_authenticated":
      return "Sua sessão expirou. Entre de novo para ver o histórico.";
    default:
      return "Não foi possível carregar o histórico.";
  }
}

/** Tentar de novo só quando outra leitura pode dar outro resultado agora. */
export function sharedActivityRetry(reason: SharedActivityFailure): boolean {
  return reason === "unknown" || reason === "invalid";
}

export const SHARED_PARTIAL_NOTE = "O histórico compartilhado pode não incluir atividades anteriores à disponibilização deste recurso.";

/** Nota discreta: só quando a 5388 sinaliza que pode haver registro anterior não exibido (D12). */
export function sharedHistoryNote(status: SharedActivityStatus | null): string | null {
  return status?.mayBePartial ? SHARED_PARTIAL_NOTE : null;
}

/** Vazio nunca é prova de que nada aconteceu: diz o que a lista mostra, não o que houve. */
export function sharedEmptyMessage(filter: ActivityFilterKey): string {
  if (filter === "ALL") return "Nenhuma atividade para mostrar. Aparecem aqui as mudanças desta coleção no fichário que o histórico compartilhado registra.";
  const label = SHARED_ACTIVITY_FILTERS.find((f) => f.key === filter)?.label ?? "este filtro";
  return `Nenhuma atividade em ${label}. Escolha “Todas” para ver o histórico completo.`;
}
