// Meu acervo — ajuste de quantidade (INVENTORY-COPY-QUANTITY-01).
// Executar: node --experimental-strip-types --test lib/colecoes/acervo-quantity.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { test } from "node:test";
import { ADD_MAX_QUANTITY } from "./acervo-add.ts";
import { clampQuantity, copiesToRemove, quantityBounds, quantityChangeLabel } from "./acervo-quantity.ts";

const copies = [
  { physicalCardId: "a", copyNumber: 1, inCollection: false },
  { physicalCardId: "b", copyNumber: 2, inCollection: true },
  { physicalCardId: "c", copyNumber: 3, inCollection: false },
  { physicalCardId: "d", copyNumber: 4, inCollection: false },
];

test("limites: mínimo = exemplares em coleção (pelo menos 1); máximo = total + teto por vez", () => {
  assert.deepEqual(quantityBounds(copies, 4), { min: 1, max: 4 + ADD_MAX_QUANTITY });
  const allAllocated = copies.map((c) => ({ ...c, inCollection: true }));
  assert.equal(quantityBounds(allAllocated, 4).min, 4);
});

test("clampQuantity respeita limites e ignora valores inválidos", () => {
  const bounds = { min: 2, max: 10 };
  assert.equal(clampQuantity(0, bounds), 2);
  assert.equal(clampQuantity(50, bounds), 10);
  assert.equal(clampQuantity(6.8, bounds), 6);
  assert.equal(clampQuantity(Number.NaN, bounds), 2);
});

test("copiesToRemove escolhe os mais recentes fora de coleção e nunca um alocado", () => {
  assert.deepEqual(copiesToRemove(copies, 2), ["d", "c"]);
  assert.deepEqual(copiesToRemove(copies, 5), ["d", "c", "a"]);
  assert.deepEqual(copiesToRemove(copies, 0), []);
});

test("rótulos da mudança", () => {
  assert.match(quantityChangeLabel(5), /5 exemplares novos/);
  assert.match(quantityChangeLabel(1), /1 exemplar novo/);
  assert.match(quantityChangeLabel(-2), /Os 2 exemplares mais recentes/);
  assert.match(quantityChangeLabel(-1), /O exemplar mais recente/);
});
