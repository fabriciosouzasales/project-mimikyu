import assert from "node:assert/strict";
import { test } from "node:test";
import { createSpeciesIndexLoader } from "./species-index-client.ts";

const body = { species: [[1, "Bulbasaur", null], [25, "Pikachu", null]] };

function fakeFetch(responses: Array<{ ok: boolean; json: unknown } | Error>) {
  let calls = 0;
  const impl = async () => {
    const next = responses[Math.min(calls, responses.length - 1)];
    calls += 1;
    if (!next || next instanceof Error) throw next ?? new Error("sem resposta");
    return { ok: next.ok, json: async () => next.json };
  };
  return { impl, calls: () => calls };
}

test("carregador do índice: uma requisição compartilhada e cache depois do sucesso", async () => {
  const fetcher = fakeFetch([{ ok: true, json: body }]);
  const loader = createSpeciesIndexLoader(fetcher.impl);
  assert.equal(loader.cached(), null);
  const [a, b] = await Promise.all([loader.load(), loader.load()]);
  assert.equal(fetcher.calls(), 1);
  assert.ok(a && a.length === 2);
  assert.equal(a, b);
  assert.equal(loader.cached(), a);
  await loader.load();
  assert.equal(fetcher.calls(), 1);
});

test("carregador do índice: falha não fica em cache — a próxima intenção tenta de novo", async () => {
  const fetcher = fakeFetch([new Error("rede"), { ok: false, json: null }, { ok: true, json: body }]);
  const loader = createSpeciesIndexLoader(fetcher.impl);
  assert.equal(await loader.load(), null);
  assert.equal(await loader.load(), null);
  const third = await loader.load();
  assert.equal(fetcher.calls(), 3);
  assert.equal(third?.length, 2);
});
