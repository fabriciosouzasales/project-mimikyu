// Reteste E4 — palco da Pokédex compartilhada igual ao do titular.
// Executar: node --experimental-strip-types --test lib/colecoes/e4-shared-pokedex-stage.test.ts (a partir de web/)
import assert from "node:assert/strict";
import { test } from "node:test";
import { type GenerationOption, POKEDEX_HERO_MASCOT, pokedexHeroPicks, sharedPokedexHeroOptions } from "./pokedex.ts";

function gen(ordinal: number, firstNumber: number, lastNumber: number): GenerationOption {
  return { code: `GEN_${ordinal}`, ordinal, name: `Ger. ${ordinal}`, region: null, speciesCount: lastNumber - firstNumber + 1, firstNumber, lastNumber, selected: null, satisfied: null };
}
const CATALOG = [gen(1, 1, 151), gen(2, 152, 251), gen(3, 252, 386)];

test("total da Pokédex inteira → todas as gerações; senão só as que aparecem na grade", () => {
  assert.deepEqual(sharedPokedexHeroOptions(CATALOG, [], 386)?.map((o) => o.selected), [true, true, true]);
  assert.deepEqual(sharedPokedexHeroOptions(CATALOG, ["GEN_2"], 100)?.map((o) => o.selected), [false, true, false]);
  assert.equal(sharedPokedexHeroOptions(CATALOG, [], 100), null, "sem prova de escopo → sem palco");
  assert.equal(sharedPokedexHeroOptions(null, ["GEN_1"], 386), null);
});

test("equipe: Mimikyu ao centro, favoritos de quem vê dentro do escopo, completada pelos iniciais", () => {
  const options = sharedPokedexHeroOptions(CATALOG, ["GEN_1"], 151);
  const picks = pokedexHeroPicks(new Set([25, 300]), options, null, () => 0);
  assert.equal(picks[0], POKEDEX_HERO_MASCOT);
  assert.equal(picks.length, 7);
  assert.ok(picks.includes(25), "favorito dentro do escopo entra");
  assert.ok(!picks.includes(300), "favorito fora do escopo fica de fora");
  assert.ok(picks.includes(6) && picks.includes(3), "iniciais completam a equipe");
});
