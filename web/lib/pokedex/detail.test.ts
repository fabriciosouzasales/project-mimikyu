// Leitura do texto oficial em inglês da ficha (Pokédex P3d).
// Executar: node --experimental-strip-types --test lib/pokedex/detail.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { test } from "node:test";
import { getPokedexSpeciesOriginalText } from "./detail.ts";

function fakeClient(result: { data: unknown; error: { code?: string; message?: string } | null }) {
  const calls: Array<{ fn: string; args: unknown }> = [];
  const client = {
    rpc(fn: string, args: unknown) {
      calls.push({ fn, args });
      return Promise.resolve(result);
    },
  };
  return { client: client as never, calls };
}

test("pede a mesma função da ficha com p_language = en e devolve só os campos de texto", async () => {
  const { client, calls } = fakeClient({
    data: [
      {
        national_dex_number: 1,
        species_name: "Bulbasaur",
        genus: "Seed Pokémon",
        genus_language: "en",
        genus_is_official: true,
        description: "While it is young...",
        description_language: "en",
        description_is_official: true,
        description_source_version: "shield",
        height_m: 0.7,
      },
    ],
    error: null,
  });
  const text = await getPokedexSpeciesOriginalText(client, 1);
  assert.deepEqual(calls, [{ fn: "get_pokedex_species_detail", args: { p_national_dex_number: 1, p_language: "en" } }]);
  assert.deepEqual(text, {
    genus: "Seed Pokémon",
    genus_language: "en",
    genus_is_official: true,
    description: "While it is young...",
    description_language: "en",
    description_is_official: true,
    description_source_version: "shield",
  });
});

test("falha da leitura em inglês devolve null, sem lançar", async () => {
  const error = console.error;
  console.error = () => {};
  try {
    const { client } = fakeClient({ data: null, error: { code: "57014", message: "timeout" } });
    assert.equal(await getPokedexSpeciesOriginalText(client, 1), null);
  } finally {
    console.error = error;
  }
});

test("espécie sem linha devolve null", async () => {
  const { client } = fakeClient({ data: [], error: null });
  assert.equal(await getPokedexSpeciesOriginalText(client, 9999), null);
});
