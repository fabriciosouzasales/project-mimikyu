import { MOVE_KEYS_MAX } from "./acervo-move.ts";

/**
 * WHERE-05B — seleção de cartas na galeria de Meu acervo (estado puro,
 * imutável; testado em `acervo-selection.test.ts`).
 *
 * Uma carta selecionada = um item da galeria (variante + idioma). A seleção
 * pertence a UM escopo (busca, Set, idioma, coleção e local): sobrevive à
 * paginação e é descartada quando o escopo muda (D3). Não existe "selecionar
 * tudo" do resultado — só "selecionar esta página" (D4).
 *
 * `copies` é INDICATIVO (contagem da galeria no momento em que a carta foi
 * marcada). O conjunto real é sempre resolvido de novo no servidor.
 */

export type SelectedItem = { key: string; name: string; copies: number };

export type Selection = {
  scope: string;
  /** Ordem de marcação preservada (a prévia lista nessa ordem). */
  items: readonly SelectedItem[];
};

export function emptySelection(scope: string): Selection {
  return { scope, items: [] };
}

export function isSelected(selection: Selection, key: string): boolean {
  return selection.items.some((item) => item.key === key);
}

/** Marca ou desmarca. Ao atingir o teto, não marca (`capped: true`). */
export function toggleItem(selection: Selection, item: SelectedItem): { selection: Selection; capped: boolean } {
  if (isSelected(selection, item.key)) {
    return { selection: { ...selection, items: selection.items.filter((x) => x.key !== item.key) }, capped: false };
  }
  if (selection.items.length >= MOVE_KEYS_MAX) return { selection, capped: true };
  return { selection: { ...selection, items: [...selection.items, item] }, capped: false };
}

/** D4 — marca as cartas da página atual que ainda não estão marcadas, até o teto. */
export function selectPage(selection: Selection, page: readonly SelectedItem[]): { selection: Selection; skipped: number } {
  const room = MOVE_KEYS_MAX - selection.items.length;
  const fresh = page.filter((item) => !isSelected(selection, item.key));
  const added = fresh.slice(0, Math.max(room, 0));
  return { selection: { ...selection, items: [...selection.items, ...added] }, skipped: fresh.length - added.length };
}

/** Desmarca as cartas da página atual (as das outras páginas continuam). */
export function unselectPage(selection: Selection, pageKeys: readonly string[]): Selection {
  const drop = new Set(pageKeys);
  return { ...selection, items: selection.items.filter((item) => !drop.has(item.key)) };
}

export function removeKeys(selection: Selection, keys: readonly string[]): Selection {
  const drop = new Set(keys);
  return { ...selection, items: selection.items.filter((item) => !drop.has(item.key)) };
}

/** Todas as cartas da página já marcadas? (página vazia → falso) */
export function pageFullySelected(selection: Selection, pageKeys: readonly string[]): boolean {
  return pageKeys.length > 0 && pageKeys.every((key) => isSelected(selection, key));
}

/** D3 — escopo diferente → seleção descartada (`cleared` diz se havia algo). */
export function reconcileScope(selection: Selection, scope: string): { selection: Selection; cleared: boolean } {
  if (selection.scope === scope) return { selection, cleared: false };
  return { selection: emptySelection(scope), cleared: selection.items.length > 0 };
}

export function selectionTotals(selection: Selection): { cards: number; copies: number } {
  return {
    cards: selection.items.length,
    copies: selection.items.reduce((sum, item) => sum + Math.max(item.copies, 0), 0),
  };
}
