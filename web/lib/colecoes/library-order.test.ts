import assert from "node:assert/strict";
import { test } from "node:test";
import { moveAnchor, moveId, positionLabel, sameOrder, shiftId } from "./library-order.ts";

const ids = ["a", "b", "c", "d"];

test("arrastar: move para a posição do alvo", () => {
  assert.deepEqual(moveId(ids, "d", "a"), ["d", "a", "b", "c"]);
  assert.deepEqual(moveId(ids, "a", "c"), ["b", "c", "a", "d"]);
  assert.deepEqual(moveId(ids, "b", "b"), ids);
  assert.deepEqual(moveId(ids, "x", "a"), ids);
});

test("teclado: desloca sem sair da lista", () => {
  assert.deepEqual(shiftId(ids, "b", 1), ["a", "c", "b", "d"]);
  assert.deepEqual(shiftId(ids, "b", -5), ["b", "a", "c", "d"]);
  assert.deepEqual(shiftId(ids, "d", 3), ids);
  assert.deepEqual(shiftId(ids, "a", 2), ["b", "c", "a", "d"], "grade: uma linha abaixo");
});

test("âncora: depois da anterior; na primeira, antes da seguinte", () => {
  assert.deepEqual(moveAnchor(["d", "a", "b", "c"], "d"), { afterId: null, beforeId: "a" });
  assert.deepEqual(moveAnchor(["b", "c", "a", "d"], "a"), { afterId: "c", beforeId: null });
  assert.equal(moveAnchor(["a"], "a"), null);
  assert.equal(moveAnchor(ids, "x"), null);
});

test("comparação e rótulo", () => {
  assert.equal(sameOrder(ids, ["a", "b", "c", "d"]), true);
  assert.equal(sameOrder(ids, ["a", "c", "b", "d"]), false);
  assert.equal(positionLabel(ids, "c"), "3 de 4");
});
