import { pluralize } from "./acervo.ts";
import type { TransferFailure } from "./binder-location.ts";

/**
 * Ciclo de vida do Fichário Digital (V1-05) — desmontar (E19), excluir vazio
 * (E19b) e transferir a coleção principal (E20). Regras puras, sem banco e
 * sem React (testável com `node --test`).
 *
 * Contratos LIVE e canônicos, sem mudança:
 * - `preview_my_collection_binder_dismantle(p_collection_id)` (5226 → 5229 →
 *   5236 → 5242): contagens, convidadas, bloqueio e token `d1:<64 hex>`. Não grava.
 * - `dismantle_my_collection_binder(p_collection_id, p_dismantle_token)` (5294):
 *   apaga páginas, bolsos, posições, reservas, mesclagens, imagens e o próprio
 *   fichário numa transação; recusa com convidadas, com plano alterado e para
 *   coleção convidada. Devolve `image_paths` — o cliente apaga os arquivos depois.
 * - `delete_collection_layout(p_layout_id)` (5293): só fichário SEM páginas, de
 *   coleção ativa do próprio usuário; convidada existente impede (FK RESTRICT).
 * - `transfer_my_binder_ownership(p_from, p_to)` (5254): muda só a âncora; nada
 *   no fichário muda. Destino ativo, sem fichário próprio e sem ser convidado
 *   de OUTRO fichário (convidada deste é aceita e deixa de sê-lo).
 *
 * Nenhum dos três toca exemplares (cartas físicas), alocações nem progresso.
 */

export const DISMANTLE_TOKEN = /^d1:[0-9a-f]{64}$/;

export type BinderLifecyclePreview = {
  hasBinder: boolean;
  active: boolean;
  layoutId: string | null;
  pages: number;
  slots: number;
  locked: number;
  positions: number;
  reservations: number;
  regions: number;
  images: number;
  guests: number;
  blocked: "has_guests" | "is_guest" | null;
  token: string | null;
};

function count(value: unknown): number | null {
  const n = typeof value === "string" && value.trim() !== "" ? Number(value) : value;
  return typeof n === "number" && Number.isInteger(n) && n >= 0 ? n : null;
}

/** Linha da prévia (5242) → modelo; `null` = formato inesperado. */
export function parseDismantlePreview(rows: unknown): BinderLifecyclePreview | null {
  const row = Array.isArray(rows) && rows.length === 1 ? (rows[0] as Record<string, unknown> | undefined) : undefined;
  if (!row || typeof row !== "object" || typeof row.has_binder !== "boolean") return null;
  const active = row.lifecycle_status === "ACTIVE";
  const blockedRaw = row.blocked_reason;
  const blocked = blockedRaw === "BINDER_HAS_GUESTS" ? "has_guests" : blockedRaw === "COLLECTION_IS_BINDER_GUEST" ? "is_guest" : blockedRaw == null ? null : undefined;
  if (blocked === undefined) return null;
  const guests = count(row.guest_count) ?? 0;
  const images = count(row.images_count) ?? 0;
  if (!row.has_binder) {
    return { hasBinder: false, active, layoutId: null, pages: 0, slots: 0, locked: 0, positions: 0, reservations: 0, regions: 0, images: 0, guests: 0, blocked, token: null };
  }
  const layoutId = typeof row.layout_id === "string" ? row.layout_id : null;
  const token = typeof row.dismantle_token === "string" && DISMANTLE_TOKEN.test(row.dismantle_token) ? row.dismantle_token : null;
  const pages = count(row.pages_count);
  const slots = count(row.slots_count);
  const locked = count(row.locked_count);
  const positions = count(row.assignments_count);
  const reservations = count(row.reservations_count);
  const regions = count(row.regions_count);
  if (!layoutId || !token || pages === null || slots === null || locked === null || positions === null || reservations === null || regions === null) return null;
  return { hasBinder: true, active, layoutId, pages, slots, locked, positions, reservations, regions, images, guests, blocked, token };
}

export type DismantleResult = { outcome: "DISMANTLED" | "ALREADY_ABSENT"; pages: number; positions: number; images: number; imagePaths: string[] };

export function parseDismantleResult(rows: unknown): DismantleResult | null {
  const row = Array.isArray(rows) && rows.length === 1 ? (rows[0] as Record<string, unknown> | undefined) : undefined;
  if (!row || (row.outcome !== "DISMANTLED" && row.outcome !== "ALREADY_ABSENT")) return null;
  const pages = count(row.pages_removed);
  const positions = count(row.assignments_removed);
  const images = count(row.images_removed);
  const paths = Array.isArray(row.image_paths) ? row.image_paths.filter((p): p is string => typeof p === "string" && p.length > 0) : null;
  if (pages === null || positions === null || images === null || paths === null) return null;
  return { outcome: row.outcome, pages, positions, images, imagePaths: paths };
}

/** O que a pessoa pode fazer para encerrar o fichário, segundo a prévia. */
export type BinderEnding = "delete" | "dismantle" | "blocked_guests" | "blocked_is_guest" | "archived" | "absent";

export function binderEnding(preview: BinderLifecyclePreview): BinderEnding {
  if (preview.blocked === "is_guest") return "blocked_is_guest";
  if (!preview.hasBinder) return "absent";
  if (!preview.active) return "archived";
  if (preview.guests > 0 || preview.blocked === "has_guests") return "blocked_guests";
  // E19b só existe para o fichário sem páginas; com páginas, o caminho é desmontar (E19).
  return preview.pages === 0 ? "delete" : "dismantle";
}

/** O que a desmontagem remove — só o que existe, com números da prévia. */
export function dismantleRemovals(preview: BinderLifecyclePreview): string[] {
  const out: string[] = [];
  out.push(`${pluralize(preview.pages, "página", "páginas")} e ${pluralize(preview.slots, "bolso", "bolsos")}`);
  if (preview.positions > 0) out.push(`${pluralize(preview.positions, "posição de carta", "posições de cartas")} nos bolsos`);
  if (preview.reservations > 0) out.push(pluralize(preview.reservations, "reserva de bolso", "reservas de bolso"));
  if (preview.regions > 0) out.push(pluralize(preview.regions, "mesclagem", "mesclagens"));
  if (preview.images > 0) out.push(pluralize(preview.images, "imagem personalizada", "imagens personalizadas"));
  if (preview.locked > 0) out.push(`${pluralize(preview.locked, "cadeado de bolso", "cadeados de bolso")} (soltos junto)`);
  return out;
}

/** O que fica — igual em toda desmontagem/exclusão. */
export const BINDER_ENDING_KEEPS: readonly string[] = [
  "Cartas físicas, acervo e locais continuam exatamente como estão.",
  "A coleção, o progresso e as alocações não mudam.",
  "O histórico do fichário registra o encerramento.",
];

export const TRANSFER_EFFECTS: readonly string[] = [
  "Bolsos, posições, reservas, imagens, nome e local do fichário continuam iguais.",
  "A coleção atual passa a usar o fichário como convidada — pode sair dele depois em Ajustes.",
  "Nenhuma carta muda de coleção.",
];

export type BinderLifecycleFailure =
  | "has_guests"
  | "is_guest"
  | "has_pages"
  | "plan_changed"
  | "archived"
  | "lock_busy"
  | "not_found"
  | "not_authenticated"
  | "invalid"
  | "inconsistent"
  | "unknown";

/** Classifica pelas mensagens estáveis de 5242/5293/5294; o texto cru nunca chega ao usuário. */
export function classifyBinderLifecycleFailure(code: string | null | undefined, message: string | null | undefined): BinderLifecycleFailure {
  const text = (message ?? "").trim();
  if (text === "BINDER_HAS_GUESTS" || code === "23503") return "has_guests";
  if (text === "COLLECTION_IS_BINDER_GUEST") return "is_guest";
  if (text === "DISMANTLE_PLAN_CHANGED" || text === "INVALID_DISMANTLE_TOKEN") return "plan_changed";
  if (text === "BINDER_DISMANTLE_INCONSISTENT") return "inconsistent";
  if (/^layout has \d+ page/.test(text)) return "has_pages";
  if (text.startsWith("collection is ARCHIVED")) return "archived";
  if (code === "55P03") return "lock_busy";
  if (text === "COLLECTION_NOT_FOUND" || text.startsWith("collection layout not found") || code === "P0002") return "not_found";
  if (code === "28000" || code === "42501" || text === "not_authenticated" || text === "authentication required") return "not_authenticated";
  if (code === "22023" || code === "22P02") return "invalid";
  return "unknown";
}

export function binderLifecycleMessage(reason: BinderLifecycleFailure, action: "dismantle" | "delete" | "preview"): string {
  switch (reason) {
    case "has_guests":
      return "Outras coleções usam este fichário. Desassocie-as (em Ajustes de cada uma) ou transfira o fichário antes. Nada foi alterado.";
    case "is_guest":
      return "Esta coleção usa o fichário de outra coleção. Para sair dele, use Ajustes da coleção. Nada foi alterado.";
    case "has_pages":
      return "O fichário ganhou páginas. Atualizamos as opções — agora o caminho é desmontar.";
    case "plan_changed":
      return "O fichário mudou desde a revisão. Revise os números atualizados e confirme de novo — nada foi alterado.";
    case "archived":
      return "A coleção está arquivada. Reative-a para encerrar o fichário. Nada foi alterado.";
    case "lock_busy":
      return "O fichário está sendo alterado agora. Tente de novo em instantes — nada foi alterado.";
    case "not_found":
      return "Este fichário não está mais disponível. Recarregue a página.";
    case "not_authenticated":
      return "Sua sessão expirou. Entre novamente para continuar.";
    case "invalid":
      return "Algo no pedido não está certo. Recarregue a página e tente de novo.";
    case "inconsistent":
      return "A desmontagem foi interrompida por segurança e nada foi alterado. Tente de novo.";
    default:
      if (action === "preview") return "Não conseguimos ler o fichário agora. Tente novamente.";
      return action === "dismantle"
        ? "Não foi possível desmontar agora. O fichário continua como estava — tente novamente."
        : "Não foi possível excluir agora. O fichário continua como estava — tente novamente.";
  }
}

// ---------------------------------------------------------------------------
// Transferência da coleção principal (E20, 5254)
// ---------------------------------------------------------------------------

export type TransferCandidate = { collectionId: string; name: string; sharesThisBinder: boolean };

/**
 * Destinos válidos para a âncora: coleções ATIVAS do próprio usuário, diferentes
 * da atual, que não são donas de outro fichário e não são convidadas de OUTRO
 * fichário. Convidadas deste vêm primeiro (já usam o fichário); depois por nome.
 * O banco revalida tudo (5254) — esta lista só evita oferecer o inválido.
 */
export function transferCandidates(input: {
  currentCollectionId: string;
  layoutId: string;
  active: ReadonlyArray<{ id: string; name: string }>;
  binderOwners: ReadonlySet<string>;
  guestOf: ReadonlyMap<string, string>;
}): TransferCandidate[] {
  const current = input.currentCollectionId.toLowerCase();
  const layout = input.layoutId.toLowerCase();
  const out: TransferCandidate[] = [];
  const seen = new Set<string>();
  for (const c of input.active) {
    const id = c.id.toLowerCase();
    if (id === current || seen.has(id) || input.binderOwners.has(id)) continue;
    const guestLayout = input.guestOf.get(id);
    if (guestLayout && guestLayout.toLowerCase() !== layout) continue;
    seen.add(id);
    out.push({ collectionId: c.id, name: c.name, sharesThisBinder: guestLayout !== undefined });
  }
  return out.sort((a, b) => (a.sharesThisBinder !== b.sharesThisBinder ? (a.sharesThisBinder ? -1 : 1) : a.name.localeCompare(b.name, "pt-BR")));
}

/** Mensagem para as classes de recusa da 5254 (`classifyTransferFailure`, binder-location). */
export function transferFailureMessage(reason: TransferFailure): string {
  switch (reason) {
    case "not_owner":
      return "Esta coleção não é mais a principal do fichário. Atualizamos as opções.";
    case "target_archived":
      return "A coleção escolhida foi arquivada. Escolha outra — nada foi alterado.";
    case "target_has_binder":
      return "A coleção escolhida já tem um fichário próprio. Escolha outra — nada foi alterado.";
    case "target_is_guest":
      return "A coleção escolhida usa outro fichário. Escolha outra — nada foi alterado.";
    case "lock_busy":
      return "O fichário está sendo alterado agora. Tente de novo em instantes — nada foi alterado.";
    case "not_found":
      return "Uma das coleções não está mais disponível. Recarregue a página.";
    case "not_authenticated":
      return "Sua sessão expirou. Entre novamente para continuar.";
    case "invalid":
      return "Algo no pedido não está certo. Recarregue a página e tente de novo.";
    default:
      return "Não foi possível transferir agora. O fichário continua com a coleção atual — tente novamente.";
  }
}

/** Marcador de sessão: o resultado atravessa a navegação de volta à coleção. */
export const BINDER_ENDED_KEY = "mmkyu:fichario-encerrado";
export type BinderEndedKind = "dismantled" | "deleted";

export function binderEndedMessage(kind: BinderEndedKind): string {
  return kind === "dismantled"
    ? "Fichário desmontado. Suas cartas continuam no acervo e na coleção."
    : "Fichário excluído. Nada mais foi alterado.";
}

/**
 * Abrir o fichário na chegada à coleção (V1-05 FUNCTIONAL-CORRECTION-01): a
 * montagem acontece na página `/fichario`; ao concluir, a pessoa volta à
 * coleção e o fichário recém-montado abre na sobreposição de sempre
 * (`BinderOverlay`). O pedido atravessa a navegação por um marcador de sessão
 * lido uma única vez — sem novo mecanismo de apresentação.
 */
export const BINDER_OPEN_ON_ARRIVAL_KEY = "mmkyu:abrir-fichario";
