import { test } from "node:test";
import assert from "node:assert/strict";
import { BINDER_FINISHES, OPEN_LEATHER_STOPS, defaultFinish, finishLabel, isBinderFinish, openLeatherStops, resolveFinish } from "./binder-finish.ts";

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

test("couro do fichário aberto: todo acabamento tem tons; ônix mantém o aprovado; desconhecido cai no ônix", () => {
  for (const finish of BINDER_FINISHES) {
    const stops = OPEN_LEATHER_STOPS[finish.key];
    assert.equal(stops.length, 3);
    for (const stop of stops) assert.match(stop, /^\d{1,3} \d{1,3}% \d{1,3}%$/);
  }
  assert.deepEqual(openLeatherStops("onix"), ["30 6% 13%", "30 5% 8%", "30 6% 4%"]);
  assert.deepEqual(openLeatherStops("marinho"), OPEN_LEATHER_STOPS.marinho);
  assert.deepEqual(openLeatherStops("azul"), OPEN_LEATHER_STOPS.onix);
  assert.deepEqual(openLeatherStops(null), OPEN_LEATHER_STOPS.onix);
});
