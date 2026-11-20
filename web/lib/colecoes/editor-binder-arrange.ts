import {
  AUTO_ARRANGE_STATUSES,
  type AutoArrangeFailure,
  type AutoArrangePreview,
  type AutoArrangeStatus,
  type AutoArrangeTarget,
  EXCLUDED_CARD_REASONS,
  type RpcErrorLike,
  UNFILLED_SLOT_REASONS,
  classifyAutoArrangeFailure,
  failureMessage,
  isPlanToken,
  reasonsFootnote,
} from "./binder-auto-arrange.ts";
import { previewFailureMessage } from "./binder-auto-arrange-view.ts";

/**
 * V1-13 · E2-3C — organização automática pelo EDITOR (5386). Regras puras.
 *
 * Mesmo plano e mesmo token do titular (5342/5360): só INSERE exemplares de X
 * (alocados a X, no local do fichário, fora de bolso) em bolsos vazios de X,
 * 1:1 estrito, até 500 por confirmação, sem mover, substituir ou retirar
 * nada (C-221–C-225). O servidor exige o fichário EXCLUSIVO de X (C-237).
 *
 * Diferença de contrato: a prévia do EDITOR NÃO traz `slot_id` (só posição,
 * `physical_card_id`, `card_id` e `card_variant_id`). O parser do titular exige
 * `slot_id`; por isso este parser é próprio: valida tudo o que a 5386 entrega,
 * mas devolve à tela só o que ela usa — contagens, páginas e o número de
 * cartas por página. Nenhum `slot_id` é fabricado e nenhum identificador de
 * exemplar ou de carta chega ao navegador.
 */

/** Modalidade → alvo do plano. Coleção livre (ou desconhecida): sem organização automática. */
export function editorArrangeTarget(completionPolicy: string | null | undefined): AutoArrangeTarget | null {
  if (completionPolicy === "STANDARD_SET" || completionPolicy === "MASTER_SET") return "RESERVED";
  if (completionPolicy === "REFERENCE_POSITION") return "SPECIES";
  return null;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function obj(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value) ? (value as Record<string, unknown>) : null;
}

function int(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) ? value : null;
}

function reasonCounts<R extends string>(value: unknown, allowed: readonly R[]): { counts: Partial<Record<R, number>>; total: number } | null {
  const r = obj(value);
  if (!r) return null;
  const counts: Partial<Record<R, number>> = {};
  let total = 0;
  for (const [key, raw] of Object.entries(r)) {
    if (!(allowed as readonly string[]).includes(key)) return null;
    const n = int(raw);
    if (n === null || n < 1) return null;
    counts[key as R] = n;
    total += n;
  }
  return { counts, total };
}

/** O que a tela do EDITOR recebe: a prévia nos tipos do titular (sem itens) e cartas por página. */
export type EditorArrangePreview = { preview: AutoArrangePreview; perPage: Record<number, number> };

/**
 * Valida a prévia da 5386 por inteiro (mesmas regras de coerência do titular)
 * e devolve só agregados. `preview.items` vai VAZIO de propósito: os itens
 * do titular são chaveados por `slot_id`, que a 5386 não entrega.
 */
export function parseEditorAutoArrangePreview(value: unknown): EditorArrangePreview | null {
  const r = obj(value);
  if (!r) return null;
  const status = r.status;
  if (typeof status !== "string" || !(AUTO_ARRANGE_STATUSES as readonly string[]).includes(status)) return null;
  const insertCount = int(r.insert_count);
  const limit = int(r.limit);
  const unfilledCount = int(r.unfilled_count);
  if (insertCount === null || insertCount < 0 || limit === null || limit < 1 || unfilledCount === null || unfilledCount < 0) return null;
  if (!isPlanToken(r.plan_token)) return null;
  const excluded = reasonCounts(r.excluded_cards, EXCLUDED_CARD_REASONS);
  const unfilled = reasonCounts(r.unfilled_slots, UNFILLED_SLOT_REASONS);
  if (!excluded || !unfilled || unfilled.total !== unfilledCount) return null;

  if (!Array.isArray(r.pages)) return null;
  const pages: number[] = [];
  for (const raw of r.pages) {
    const p = int(raw);
    if (p === null || p < 1 || (pages.length > 0 && p <= pages[pages.length - 1]!)) return null;
    pages.push(p);
  }

  if (!Array.isArray(r.items)) return null;
  const positions = new Set<string>();
  const cards = new Set<string>();
  const perPage: Record<number, number> = {};
  let n = 0;
  for (const raw of r.items) {
    const item = obj(raw);
    if (!item) return null;
    const ord = int(item.ord);
    const page = int(item.page_number);
    const row = int(item.row_index);
    const col = int(item.column_index);
    if (ord === null || ord !== n + 1 || page === null || page < 1 || row === null || row < 1 || col === null || col < 1) return null;
    const physical = item.physical_card_id;
    if (typeof physical !== "string" || !UUID_RE.test(physical)) return null;
    if (typeof item.card_id !== "string" || !UUID_RE.test(item.card_id) || typeof item.card_variant_id !== "string" || !UUID_RE.test(item.card_variant_id)) return null;
    const key = `${page}:${row}:${col}`;
    // 1:1 estrito (C-222): posição e exemplar únicos — validado aqui, nunca exposto.
    if (positions.has(key) || cards.has(physical.toLowerCase()) || !pages.includes(page)) return null;
    positions.add(key);
    cards.add(physical.toLowerCase());
    perPage[page] = (perPage[page] ?? 0) + 1;
    n += 1;
  }

  if (status === "EMPTY" && (insertCount !== 0 || n !== 0 || pages.length !== 0)) return null;
  if (status === "READY" && (insertCount < 1 || insertCount > limit || n !== insertCount || Object.keys(perPage).length !== pages.length)) return null;
  if (status === "LIMIT_EXCEEDED" && (insertCount <= limit || n !== 0 || pages.length === 0)) return null;

  return {
    preview: {
      status: status as AutoArrangeStatus,
      insertCount,
      limit,
      planToken: r.plan_token,
      excludedCards: excluded.counts,
      excludedCount: excluded.total,
      unfilledSlots: unfilled.counts,
      unfilledCount,
      pages,
      items: [],
    },
    perPage,
  };
}

/**
 * Recusa → classe do titular, sem ler `hint`/`detail`. Dois casos próprios
 * do EDITOR, ambos 42501, viram classes existentes de mensagem neutra:
 * `OPERATION_RESERVED_TO_OWNER` → `not_owner` (organização reservada ao
 * titular neste fichário) e `CAPABILITY_NOT_ENABLED` → `unavailable`.
 */
export function classifyEditorAutoArrangeFailure(error: RpcErrorLike): AutoArrangeFailure {
  const text = (error?.message ?? "").trim().toUpperCase();
  if (text === "OPERATION_RESERVED_TO_OWNER") return "not_owner";
  if (text === "CAPABILITY_NOT_ENABLED") return "unavailable";
  return classifyAutoArrangeFailure(error ? { code: error.code, message: error.message } : error);
}

/** Texto neutro para o EDITOR (prévia ou aplicação); o resto, as mensagens do titular. */
export function editorArrangeFailureText(reason: AutoArrangeFailure, phase: "preview" | "apply"): string {
  switch (reason) {
    case "not_owner":
      return "Neste fichário, a organização automática é feita pelo titular.";
    case "unavailable":
      return "A organização compartilhada ainda não está disponível.";
    case "forbidden":
    case "collection_not_found":
      return "Sua permissão para organizar este fichário mudou.";
    case "binder_not_found":
      return "Este fichário não está disponível para organizar agora.";
    case "archived":
      return "A coleção está arquivada. O fichário fica só para leitura.";
    default:
      return phase === "preview" ? previewFailureMessage(reason) : failureMessage(reason);
  }
}

/** Depois destas recusas a edição é desligada nesta tela (mesma regra da E2-1). */
export function editorArrangeDisablesEditing(reason: AutoArrangeFailure): boolean {
  return reason === "unavailable" || reason === "forbidden" || reason === "collection_not_found" || reason === "binder_not_found" || reason === "archived" || reason === "not_authenticated";
}

export function editorArrangeRechecksAccess(reason: AutoArrangeFailure): boolean {
  return reason === "forbidden" || reason === "collection_not_found" || reason === "binder_not_found";
}

/**
 * Nota dos motivos para o EDITOR: só ações que ele tem na tela compartilhada.
 * Pokédex: escolher outra representante não está disponível ao EDITOR (D4,
 * pendente), então a nota fala só em posicionar manualmente. Set/Master Set:
 * a nota do titular já cabe (posicionar manualmente ou ajustar reservas).
 */
export const EDITOR_SPECIES_REASONS_FOOTNOTE = "As cópias extras continuam em Cartas disponíveis. Para colocar outra carta no bolso, posicione manualmente.";

export function editorArrangeFootnote(target: AutoArrangeTarget): string {
  return target === "SPECIES" ? EDITOR_SPECIES_REASONS_FOOTNOTE : reasonsFootnote(target);
}
