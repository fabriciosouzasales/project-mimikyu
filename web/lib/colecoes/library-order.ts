/**
 * Ordem da Biblioteca escolhida pelo colecionador (LIBRARY-ORDER-01).
 *
 * Regras puras (sem React, sem rede), testáveis com
 * `node --experimental-strip-types --test lib/colecoes/library-order.test.ts`.
 *
 * Contratos: R1 `get_my_collections` v3 (5182) devolve a ordem gravada;
 * `move_my_collection` (5183) grava um movimento por vez, ancorado em
 * "depois de" ou "antes de" outra coleção — a âncora "antes de" existe para a
 * paginação (na primeira posição de uma página a coleção anterior está na
 * página de antes). O banco renumera e decide dono; aqui só se calcula o
 * que a interface mostra e qual âncora mandar.
 */

/**
 * Arrastar e soltar em Cards e Lista. Contratos no LIVE desde 2026-10-18
 * (`database/schema/5181`–`5183`; harness 5835 22/22 PASS). Ligado
 * localmente para a homologação no navegador — publicar (commit/deploy) só
 * depois dessa homologação funcional e visual.
 */
export const LIBRARY_REORDER_ENABLED = true;

/** Move `id` para a posição de `overId` (mesma semântica do arrastar). */
export function moveId(ids: readonly string[], id: string, overId: string): string[] {
  const from = ids.indexOf(id);
  const to = ids.indexOf(overId);
  if (from < 0 || to < 0 || from === to) return [...ids];
  const next = [...ids];
  next.splice(from, 1);
  next.splice(to, 0, id);
  return next;
}

/** Move `id` por `delta` posições (teclado), sem sair da lista. */
export function shiftId(ids: readonly string[], id: string, delta: number): string[] {
  const from = ids.indexOf(id);
  if (from < 0 || delta === 0) return [...ids];
  const to = Math.max(0, Math.min(ids.length - 1, from + delta));
  return to === from ? [...ids] : moveId(ids, id, ids[to] as string);
}

export type MoveAnchor = { afterId: string; beforeId: null } | { afterId: null; beforeId: string };

/**
 * Âncora para gravar a posição de `id` em `ids` (ordem já reordenada):
 * "depois da anterior"; na primeira posição, "antes da seguinte".
 * `null` quando não há o que gravar (lista com uma coleção).
 */
export function moveAnchor(ids: readonly string[], id: string): MoveAnchor | null {
  const index = ids.indexOf(id);
  if (index < 0 || ids.length < 2) return null;
  if (index > 0) return { afterId: ids[index - 1] as string, beforeId: null };
  return { afterId: null, beforeId: ids[1] as string };
}

/** `true` quando as duas ordens têm os mesmos ids na mesma sequência. */
export function sameOrder(a: readonly string[], b: readonly string[]): boolean {
  return a.length === b.length && a.every((id, index) => id === b[index]);
}

/** Texto curto da posição, para o leitor de tela ("3 de 12"). */
export function positionLabel(ids: readonly string[], id: string): string {
  return `${ids.indexOf(id) + 1} de ${ids.length}`;
}
