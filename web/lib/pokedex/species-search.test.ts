// Contratos da busca rápida da ficha da espécie (Pokédex P3b).
// Executar: node --experimental-strip-types --test lib/pokedex/species-search.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { test } from "node:test";
import {
  type SpeciesIndexEntry,
  normalizeSpeciesName,
  parseNumberQuery,
  parseSpeciesIndex,
  searchSpecies,
} from "./species-search.ts";

const INDEX: SpeciesIndexEntry[] = [
  [1, "Bulbasaur", "official-artwork/0001/w320-aaaaaaaaaaaaaaaa.webp"],
  [6, "Charizard", null],
  [25, "Pikachu", null],
  [26, "Raichu", null],
  [29, "Nidoran♀", null],
  [32, "Nidoran♂", null],
  [122, "Mr. Mime", null],
  [250, "Ho-Oh", null],
  [251, "Celebi", null],
  [439, "Mime Jr.", null],
  [669, "Flabébé", null],
  [772, "Type: Null", null],
  [1025, "Pecharunt", null],
];

const numbers = (results: ReturnType<typeof searchSpecies>) => results.map((r) => r.nationalDexNumber);

test("número: aceita 25, 0025, #25, Nº 25, n 25", () => {
  for (const q of ["25", "0025", "#25", "Nº 25", "nº25", "n 25", " 25 "]) assert.equal(parseNumberQuery(q), 25, q);
  for (const q of ["0", "#", "25a", "12345", "pika"]) assert.equal(parseNumberQuery(q), null, q);
});

test("número: exato primeiro, depois prefixos em ordem", () => {
  assert.deepEqual(numbers(searchSpecies(INDEX, "25")), [25, 250, 251]);
  assert.deepEqual(numbers(searchSpecies(INDEX, "#0006")), [6]);
  assert.deepEqual(numbers(searchSpecies(INDEX, "0025")), [25]);
  assert.deepEqual(numbers(searchSpecies(INDEX, "6")), [6, 669]);
  assert.deepEqual(numbers(searchSpecies(INDEX, "1025")), [1025]);
  assert.deepEqual(numbers(searchSpecies(INDEX, "9999")), []);
});

test("nome: sem acento, caixa e pontuação", () => {
  assert.equal(normalizeSpeciesName("Flabébé"), "flabebe");
  assert.equal(normalizeSpeciesName("Mr. Mime"), "mrmime");
  assert.deepEqual(numbers(searchSpecies(INDEX, "flabebe")), [669]);
  assert.deepEqual(numbers(searchSpecies(INDEX, "mr mime")), [122]);
  assert.deepEqual(numbers(searchSpecies(INDEX, "HO-OH")), [250]);
  assert.deepEqual(numbers(searchSpecies(INDEX, "type null")), [772]);
});

test("nome: exato > começo > palavra > trecho; empate pelo número", () => {
  assert.deepEqual(numbers(searchSpecies(INDEX, "pikachu")), [25]);
  assert.deepEqual(numbers(searchSpecies(INDEX, "nidoran")), [29, 32]);
  // "mime": começo de "Mime Jr." (439) vem antes de palavra em "Mr. Mime" (122).
  assert.deepEqual(numbers(searchSpecies(INDEX, "mime")), [439, 122]);
  // "chu": só trecho no meio.
  assert.deepEqual(numbers(searchSpecies(INDEX, "chu")), [25, 26]);
});

test("vazio, só pontuação e limite", () => {
  assert.deepEqual(searchSpecies(INDEX, ""), []);
  assert.deepEqual(searchSpecies(INDEX, "   "), []);
  assert.deepEqual(searchSpecies(INDEX, "..."), []);
  assert.equal(searchSpecies(INDEX, "a", 3).length, 3);
});

test("sugestão carrega nome e caminho da arte", () => {
  assert.deepEqual(searchSpecies(INDEX, "1")[0], {
    nationalDexNumber: 1,
    name: "Bulbasaur",
    artworkPath: "official-artwork/0001/w320-aaaaaaaaaaaaaaaa.webp",
  });
});

test("parseSpeciesIndex: descarta linhas fora do contrato", () => {
  assert.equal(parseSpeciesIndex(null), null);
  assert.equal(parseSpeciesIndex({ species: "x" }), null);
  assert.deepEqual(
    parseSpeciesIndex({
      species: [[1, "Bulbasaur", null], [0, "Zero", null], [2, "", null], [3, "Venusaur", 7], ["4", "Charmander", null], [5, "Charmeleon", "p"]],
    }),
    [
      [1, "Bulbasaur", null],
      [5, "Charmeleon", "p"],
    ],
  );
});
