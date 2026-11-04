/**
 * Lista de desejos — seleção, remoção em lote e sugestão após aquisição (V1-11 W8) — regras puras.
 *
 * Contrato (wishlist-product-contract.md §3/§7, C-93, C-213): a posse é DERIVADA, nunca
 * gravada; quando o acervo já atende um desejo (mesma variante; mesmo idioma quando o desejo
 * tem idioma; qualquer exemplar quando é "qualquer idioma"), a interface pode SUGERIR a
 * remoção — que só acontece por ação explícita. Nunca há remoção automática.
 *
 * Seleção: sempre pela identidade exata do registro de desejo (`entryId` = variante +
 * idioma), nunca por carta ou variante — remover um idioma não remove os outros. A seleção
 * vive só na página exibida: mudar de página, filtro ou ordem recomeça do zero.
 */

import { normalizeId } from "./wishlist.ts";
import type { WishOwnership } from "./wishlist.ts";

/** Teto do lote de remoção: uma página da lista (60) com folga; a 5346 aceita até 500. */
export const WISHLIST_REMOVE_LIMIT = 100;

/** Posse que ATENDE o desejo (C-213): mesma variante e idioma compatível. Outra variante nunca atende. */
export function wishSatisfied(ownership: WishOwnership): boolean {
  return ownership === "SAME_VARIANT_LANGUAGE";
}

export type WishSelection = ReadonlySet<string>;

/** Liga/desliga um desejo (por `entryId`). Id fora da página exibida é ignorado. */
export function toggleWishSelection(selection: WishSelection, entryId: string, visibleIds: readonly string[]): Set<string> {
  const next = new Set(selection);
  if (next.has(entryId)) next.delete(entryId);
  else if (visibleIds.includes(entryId)) next.add(entryId);
  return next;
}

/** "Selecionar esta página": só os desejos visíveis agora — nunca os de outras páginas. */
export function selectWishPage(visibleIds: readonly string[]): Set<string> {
  return new Set(visibleIds);
}

/** Mantém só o que continua visível (após remoção, desfazer ou releitura). */
export function pruneWishSelection(selection: WishSelection, visibleIds: readonly string[]): Set<string> {
  const visible = new Set(visibleIds);
  return new Set([...selection].filter((id) => visible.has(id)));
}

/** Todos os visíveis estão marcados? (rótulo do "Selecionar esta página" / "Desmarcar"). */
export function allVisibleSelected(selection: WishSelection, visibleIds: readonly string[]): boolean {
  return visibleIds.length > 0 && visibleIds.every((id) => selection.has(id));
}

/**
 * Pedido de remoção vindo do navegador → ids válidos e distintos. `null` = pedido malformado
 * (vazio, id inválido ou acima do teto) — nada é removido. Duplicados contam uma vez.
 */
export function parseWishRemoveIds(raw: unknown): string[] | null {
  if (!Array.isArray(raw) || raw.length === 0) return null;
  const ids: string[] = [];
  for (const value of raw) {
    const id = normalizeId(value);
    if (!id) return null;
    if (!ids.includes(id)) ids.push(id);
  }
  return ids.length > WISHLIST_REMOVE_LIMIT ? null : ids;
}

export type WishRemoveSummary = {
  requested: number;
  removed: number;
  /** Já não existiam (removidos em outra aba) ou não pertencem à sessão — nada foi feito com eles. */
  notFound: number;
};

/** Contagem devolvida pela 5346 × ids pedidos → resumo honesto. `null` = resposta fora do contrato. */
export function summarizeWishRemove(requested: number, removedRaw: unknown): WishRemoveSummary | null {
  const removed =
    typeof removedRaw === "number" ? removedRaw : typeof removedRaw === "string" && removedRaw.trim() !== "" ? Number(removedRaw) : Number.NaN;
  if (!Number.isInteger(removed) || removed < 0 || removed > requested) return null;
  return { requested, removed, notFound: requested - removed };
}

/** Frase do resultado da remoção em lote. */
export function wishRemoveHeadline(summary: WishRemoveSummary): string {
  const { removed, notFound } = summary;
  const head = removed === 0 ? "Nenhum desejo removido" : removed === 1 ? "1 desejo removido da lista" : `${removed} desejos removidos da lista`;
  if (notFound === 0) return `${head}.`;
  return `${head} · ${notFound === 1 ? "1 já não estava na lista" : `${notFound} já não estavam na lista`}.`;
}

/** Pergunta da confirmação, com a quantidade exata de registros. */
export function wishRemoveConfirmation(count: number): string {
  return count === 1 ? "Remover 1 desejo da sua lista?" : `Remover ${count} desejos da sua lista?`;
}

/**
 * Sugestão após aquisição: quantos desejos o acervo já atende (contagem global da 5350,
 * opção de posse OWNED). Só aparece quando há algo a sugerir e a pessoa ainda não está
 * olhando exatamente esses desejos.
 */
export function satisfiedSuggestionCount(ownedOptionCount: number | null | undefined, viewingOwnedFilter: boolean): number {
  if (viewingOwnedFilter) return 0;
  return typeof ownedOptionCount === "number" && ownedOptionCount > 0 ? Math.floor(ownedOptionCount) : 0;
}
