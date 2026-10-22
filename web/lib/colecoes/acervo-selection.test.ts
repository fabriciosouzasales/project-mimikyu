// WHERE-05B — seleção de cartas na galeria (estado puro).
// Executar: node --experimental-strip-types --test lib/colecoes/acervo-selection.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { test } from "node:test";
import { MOVE_KEYS_MAX } from "./acervo-move.ts";
import {
  type SelectedItem,
  emptySelection,
  isSelected,
  pageFullySelected,
  reconcileScope,
  removeKeys,
  selectPage,
  selectionTotals,
  toggleItem,
  unselectPage,
} from "./acervo-selection.ts";

const item = (n: number, copies = 1): SelectedItem => ({ key: `k${n}`, name: `Carta ${n}`, copies });

test("marcar e desmarcar", () => {
  let s = emptySelection("q=a");
  s = toggleItem(s, item(1, 3)).selection;
  assert.ok(isSelected(s, "k1"));
  assert.deepEqual(selectionTotals(s), { cards: 1, copies: 3 });
  s = toggleItem(s, item(1, 3)).selection;
  assert.equal(s.items.length, 0);
});

test("selecionar esta página: soma às páginas anteriores (D3/D4)", () => {
  let s = selectPage(emptySelection(""), [item(1), item(2)]).selection;
  s = selectPage(s, [item(2), item(3)]).selection; // página 2 repete k2
  assert.deepEqual(s.items.map((x) => x.key), ["k1", "k2", "k3"]);
  assert.ok(pageFullySelected(s, ["k2", "k3"]));
  assert.equal(pageFullySelected(s, []), false);
  s = unselectPage(s, ["k2", "k3"]);
  assert.deepEqual(s.items.map((x) => x.key), ["k1"]);
});

test("teto de cartas: não marca além de 500", () => {
  const page = Array.from({ length: MOVE_KEYS_MAX + 3 }, (_, i) => item(i));
  const { selection, skipped } = selectPage(emptySelection(""), page);
  assert.equal(selection.items.length, MOVE_KEYS_MAX);
  assert.equal(skipped, 3);
  const extra = toggleItem(selection, item(9999));
  assert.equal(extra.capped, true);
  assert.equal(extra.selection.items.length, MOVE_KEYS_MAX);
});

test("mudou o escopo (busca ou filtro) → seleção limpa com aviso", () => {
  const s = selectPage(emptySelection("local=x"), [item(1)]).selection;
  assert.deepEqual(reconcileScope(s, "local=x"), { selection: s, cleared: false });
  const changed = reconcileScope(s, "local=y");
  assert.equal(changed.cleared, true);
  assert.equal(changed.selection.items.length, 0);
  assert.equal(changed.selection.scope, "local=y");
  assert.equal(reconcileScope(emptySelection("a"), "b").cleared, false);
});

test("remover chaves não resolvidas", () => {
  const s = selectPage(emptySelection(""), [item(1), item(2), item(3)]).selection;
  assert.deepEqual(removeKeys(s, ["k2"]).items.map((x) => x.key), ["k1", "k3"]);
});
