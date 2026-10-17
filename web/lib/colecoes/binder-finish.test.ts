import { test } from "node:test";
import assert from "node:assert/strict";
import { BINDER_FINISHES, defaultFinish, finishLabel, isBinderFinish, resolveFinish } from "./binder-finish.ts";

const A = "3aa3fcf6-5826-4a13-b6a2-8f652a2b485a";

test("acabamento padrão é estável e sempre válido", () => {
  assert.equal(defaultFinish(A), defaultFinish(A));
  assert.ok(isBinderFinish(defaultFinish(A)));
  assert.ok(isBinderFinish(defaultFinish("")));
});

test("o padrão se distribui entre as cores (não colapsa numa só)", () => {
  const seen = new Set<string>();
  for (let index = 0; index < 200; index += 1) seen.add(defaultFinish(`00000000-0000-4000-8000-${String(index).padStart(12, "0")}`));
  assert.equal(seen.size, BINDER_FINISHES.length);
});

test("escolha gravada vence; valor desconhecido cai no padrão", () => {
  assert.equal(resolveFinish(A, "vinho"), "vinho");
  assert.equal(resolveFinish(A, "roxo-neon"), defaultFinish(A));
  assert.equal(resolveFinish(A, null), defaultFinish(A));
  assert.equal(finishLabel("perola"), "Pérola");
});
