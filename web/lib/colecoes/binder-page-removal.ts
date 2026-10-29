/**
 * Remoção segura de páginas do fichário — regras puras (sem I/O).
 *
 * Contrato do banco: `remove_layout_page(uuid, integer)` (5235/5260/5281/5285).
 * Ele já recusa, sob trava, página com carta, reserva, imagem em 2 bolsos e
 * imagem de bolso; referências de espécie só saem com a contagem exata
 * confirmada — aqui sempre 0, então página com referência é recusada pelo
 * próprio banco. Ao remover, as páginas seguintes são renumeradas (n → n-1)
 * e o Histórico grava o evento E14 (PAGE_REMOVED + PAGE_RENUMBERED).
 *
 * Bolso fixado e mínimo de páginas: conferidos no servidor antes da chamada
 * (e aqui, para a interface) e, com a 5286, também recusados pelo próprio
 * banco sob a trava do fichário (mensagens reconhecidas abaixo).
 * A elegibilidade nunca vem da aparência: vem dos dados de cada bolso.
 */

import type { BinderPage, BinderSlot } from "./binder.ts";

/** O fichário nunca fica com menos páginas que isto. */
export const MIN_BINDER_PAGES = 1;

export type PageRemovalBlocker = "cards" | "reservations" | "images" | "regions" | "locked" | "species" | "last_page";

export type PageRemovalCheck = { ok: true } | { ok: false; blockers: PageRemovalBlocker[] };

/** Ordem estável dos motivos (a mais grave primeiro). */
const ORDER: PageRemovalBlocker[] = ["last_page", "cards", "reservations", "images", "regions", "locked", "species"];

function slotHasCard(slot: BinderSlot): boolean {
  return slot.assignmentId !== null || slot.present !== null || (slot.physicalCardId ?? null) !== null || slot.state.startsWith("OCCUPIED");
}

function slotHasReservation(slot: BinderSlot): boolean {
  return slot.expected !== null || slot.expectedCardId !== null || slot.state === "RESERVED_EMPTY";
}

/** Motivos que impedem remover a página (vazio = elegível). Usa os dados, não a aparência. */
export function pageRemovalBlockers(page: Pick<BinderPage, "slots" | "regions">, totalPages: number): PageRemovalBlocker[] {
  const found = new Set<PageRemovalBlocker>();
  if (!Number.isInteger(totalPages) || totalPages <= MIN_BINDER_PAGES) found.add("last_page");
  if ((page.regions?.length ?? 0) > 0) found.add("regions");
  for (const slot of page.slots) {
    if (slotHasCard(slot)) found.add("cards");
    if (slotHasReservation(slot)) found.add("reservations");
    if (slot.image) found.add("images");
    if (slot.regionId) found.add("regions");
    if (slot.locked) found.add("locked");
    if (slot.speciesRef) found.add("species");
  }
  return ORDER.filter((reason) => found.has(reason));
}

export function checkPageRemoval(page: Pick<BinderPage, "slots" | "regions">, totalPages: number): PageRemovalCheck {
  const blockers = pageRemovalBlockers(page, totalPages);
  return blockers.length === 0 ? { ok: true } : { ok: false, blockers };
}

/** Frase curta por motivo — o que impede e o que fazer. */
export function pageRemovalBlockerLabel(reason: PageRemovalBlocker): string {
  switch (reason) {
    case "last_page":
      return "É a única página do fichário — o fichário precisa de ao menos uma.";
    case "cards":
      return "Tem cartas nos bolsos — tire-as do fichário antes.";
    case "reservations":
      return "Tem bolsos reservados — libere as reservas antes.";
    case "images":
      return "Tem imagens nos bolsos — remova as imagens antes.";
    case "regions":
      return "Tem uma imagem em 2 bolsos — separe os bolsos antes.";
    case "locked":
      return "Tem bolsos fixados — solte os cadeados antes.";
    case "species":
      return "Tem Pokémon de referência nos bolsos — limpe as referências antes.";
  }
}

/** Resumo de uma linha para dicas (tooltip, rótulo acessível). */
export function pageRemovalSummary(blockers: PageRemovalBlocker[]): string {
  if (blockers.length === 0) return "Página vazia — pode ser removida.";
  const first = blockers[0] as PageRemovalBlocker;
  const extra = blockers.length - 1;
  return extra > 0 ? `${pageRemovalBlockerLabel(first)} (+${extra} ${extra === 1 ? "motivo" : "motivos"})` : pageRemovalBlockerLabel(first);
}

/** O que acontece com a numeração: páginas seguintes descem uma posição. */
export function pageRemovalRenumbering(pageNumber: number, totalPages: number): { from: number; to: number } | null {
  if (pageNumber >= totalPages) return null;
  return { from: pageNumber + 1, to: totalPages };
}

/**
 * Cache local depois da remoção confirmada pelo banco: tira a página removida
 * e renumera as seguintes (n → n-1), sem perder as já lidas. Não muta.
 */
export function cacheAfterPageRemoval(cache: ReadonlyMap<number, BinderPage>, removed: number): Map<number, BinderPage> {
  const next = new Map<number, BinderPage>();
  for (const [number, page] of cache) {
    if (number === removed) continue;
    if (number > removed) next.set(number - 1, { ...page, pageNumber: number - 1 });
    else next.set(number, page);
  }
  return next;
}

/** Página âncora depois da remoção: fica onde estava, limitada ao novo total. */
export function anchorAfterPageRemoval(anchor: number, removed: number, totalAfter: number): number {
  const shifted = anchor > removed ? anchor - 1 : anchor;
  return Math.min(Math.max(1, shifted), Math.max(1, totalAfter));
}

// ---------------------------------------------------------------------------
// Falhas do servidor / banco
// ---------------------------------------------------------------------------

export type PageRemovalFailure = "blocked" | "stale" | "archived" | "lock_busy" | "not_authenticated" | "invalid" | "unknown";

/** Mensagens da RPC → motivo estável (+ bloqueio específico quando o banco recusa pelo conteúdo). */
export function classifyPageRemovalFailure(
  code: string | null | undefined,
  message: string | null | undefined,
  hint?: string | null,
): { reason: PageRemovalFailure; blocker?: PageRemovalBlocker } {
  const text = (message ?? "").toLowerCase();
  if (code === "55P03") return { reason: "lock_busy" };
  if (code === "28000" || text.includes("authentication required")) return { reason: "not_authenticated" };
  if (text.includes("archived")) return { reason: "archived" };
  // 5286: recusas do próprio banco para mínimo de páginas e bolso fixado.
  if (text.includes("at least one page")) return { reason: "blocked", blocker: "last_page" };
  if (text.includes("locked slot")) return { reason: "blocked", blocker: "locked" };
  if (text.includes("slot assignment")) return { reason: "blocked", blocker: "cards" };
  if (text.includes("expected content")) return { reason: "blocked", blocker: "reservations" };
  if (text.includes("layout region")) return { reason: "blocked", blocker: "regions" };
  if (text.includes("custom image")) return { reason: "blocked", blocker: "images" };
  if (text.includes("species reference") || (hint ?? "").startsWith("SPECIES_REFERENCES_ON_PAGE")) return { reason: "blocked", blocker: "species" };
  if (text.includes("not found or not owned")) return { reason: "stale" };
  if (code === "22023" || code === "22P02") return { reason: "invalid" };
  return { reason: "unknown" };
}

export function pageRemovalFailureMessage(reason: PageRemovalFailure, blockers: PageRemovalBlocker[] = []): string {
  switch (reason) {
    case "blocked":
      return blockers.length > 0
        ? `A página não pode ser removida. ${pageRemovalBlockerLabel(blockers[0] as PageRemovalBlocker)}`
        : "A página não pode ser removida no estado atual. Atualizamos o fichário.";
    case "stale":
      return "O fichário mudou em outra tela. Atualizamos as páginas — confira antes de tentar de novo.";
    case "archived":
      return "A coleção está arquivada. Reative-a para organizar o fichário.";
    case "lock_busy":
      return "O fichário está sendo atualizado em outra tela. Tente de novo em alguns segundos.";
    case "not_authenticated":
      return "Sua sessão terminou. Entre de novo para continuar.";
    case "invalid":
      return "Não foi possível entender o pedido. Recarregue a página e tente de novo.";
    default:
      return "Não foi possível remover a página agora. Nada foi alterado — tente de novo em instantes.";
  }
}

export function pageRemovedMessage(pageNumber: number, totalBefore: number): string {
  const renumber = pageRemovalRenumbering(pageNumber, totalBefore);
  return renumber
    ? `Página ${pageNumber} removida. As páginas ${renumber.from}–${renumber.to} passaram a ser ${renumber.from - 1}–${renumber.to - 1}.`
    : `Página ${pageNumber} removida.`;
}
