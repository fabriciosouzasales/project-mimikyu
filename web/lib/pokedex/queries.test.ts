// Contratos do leitor de tipos da galeria (Pokédex P3c, Query 6135).
// Executar: node --experimental-strip-types --test lib/pokedex/queries.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { test } from "node:test";
import { getPokedexSpeciesTypeIndex } from "./queries.ts";

type Row = Record<string, unknown>;
type Page = { data: Row[] | null; error: { code?: string; message?: string } | null };

/** Cliente mínimo: rpc(...).order(...).range(from, to) devolve as páginas na ordem. */
function fakeClient(pages: Page[]) {
  const calls: Array<{ fn: string; args: unknown; from: number; to: number }> = [];
  let i = 0;
  const client = {
    rpc(fn: string, args: unknown) {
      return {
        order() {
          return {
            range(from: number, to: number) {
              calls.push({ fn, args, from, to });
              return Promise.resolve(pages[i++] ?? { data: [], error: null });
            },
          };
        },
      };
    },
  };
  return { client: client as never, calls };
}

const row = (n: number, t1: string, l1: string, t2: string | null = null, l2: string | null = null) => ({
  national_dex_number: n,
  primary_type_code: t1,
  primary_type_label: l1,
  secondary_type_code: t2,
  secondary_type_label: l2,
});

test("lê em lote, pagina pelo teto de 1.000 e indexa por número nacional", async () => {
  const first = Array.from({ length: 1000 }, (_, k) => row(k + 1, "NORMAL", "Normal"));
  first[0] = row(1, "GRASS", "Planta", "POISON", "Venenoso");
  const { client, calls } = fakeClient([
    { data: first, error: null },
    { data: [row(1001, "GRASS", "Planta", "DRAGON", "Dragão"), row(1025, "POISON", "Venenoso", "GHOST", "Fantasma")], error: null },
  ]);
  const index = await getPokedexSpeciesTypeIndex(client);
  assert.ok(index);
  assert.equal(index.size, 1002);
  assert.deepEqual(index.get(1), { primaryCode: "GRASS", primaryLabel: "Planta", secondaryCode: "POISON", secondaryLabel: "Venenoso" });
  assert.deepEqual(index.get(1025)?.secondaryCode, "GHOST");
  assert.equal(calls.length, 2);
  assert.deepEqual(
    calls.map((c) => [c.fn, c.from, c.to]),
    [
      ["get_pokedex_species_type_index", 0, 999],
      ["get_pokedex_species_type_index", 1000, 1999],
    ],
  );
  assert.deepEqual(calls[0]?.args, { p_language: "pt-BR" });
});

test("tipo único: secundário nulo", async () => {
  const { client } = fakeClient([{ data: [row(25, "ELECTRIC", "Elétrico")], error: null }]);
  const index = await getPokedexSpeciesTypeIndex(client);
  assert.deepEqual(index?.get(25), { primaryCode: "ELECTRIC", primaryLabel: "Elétrico", secondaryCode: null, secondaryLabel: null });
});

test("função ausente (PGRST202): devolve null — cards no tom neutro", async () => {
  const warn = console.warn;
  console.warn = () => {};
  try {
    const { client } = fakeClient([{ data: null, error: { code: "PGRST202", message: "not found" } }]);
    assert.equal(await getPokedexSpeciesTypeIndex(client), null);
  } finally {
    console.warn = warn;
  }
});

test("qualquer outra falha também degrada para null, sem lançar", async () => {
  const error = console.error;
  console.error = () => {};
  try {
    const { client } = fakeClient([{ data: null, error: { code: "57014", message: "timeout" } }]);
    assert.equal(await getPokedexSpeciesTypeIndex(client), null);
  } finally {
    console.error = error;
  }
});

test("linha sem tipo primário é ignorada", async () => {
  const { client } = fakeClient([{ data: [row(7, "", ""), row(8, "WATER", "Água")], error: null }]);
  const index = await getPokedexSpeciesTypeIndex(client);
  assert.equal(index?.has(7), false);
  assert.equal(index?.get(8)?.primaryCode, "WATER");
});
