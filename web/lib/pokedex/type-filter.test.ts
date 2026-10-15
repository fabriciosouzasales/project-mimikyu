// Filtro por tipo da Pokédex Nacional (Pokédex P5a).
// Executar: node --experimental-strip-types --test lib/pokedex/type-filter.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { test } from "node:test";
import { nationalPokedexHref, pokedexContextSearch, pokedexHref, speciesDetailHref, type PokedexContext } from "./format.ts";
import { resolveSpeciesNavigation, type NavigationSpecies } from "./navigation.ts";
import type { PokedexSpeciesTypes } from "./queries.ts";
import {
  MAX_TYPE_FILTERS,
  applyTypeFilter,
  canonicalTypes,
  joinTypeLabels,
  parseTypeParam,
  speciesMatchesTypes,
  toggleType,
  typeLabels,
} from "./type-filter.ts";

const LABEL: Record<string, string> = {
  GRASS: "Planta",
  POISON: "Venenoso",
  FIRE: "Fogo",
  FLYING: "Voador",
  WATER: "Água",
  NORMAL: "Normal",
  ICE: "Gelo",
};

function t(primary: string, secondary: string | null = null): PokedexSpeciesTypes {
  return { primaryCode: primary, primaryLabel: LABEL[primary]!, secondaryCode: secondary, secondaryLabel: secondary ? LABEL[secondary]! : null };
}

// Recorte real de Kanto (tipos como no índice 6135).
const INDEX = new Map<number, PokedexSpeciesTypes>([
  [1, t("GRASS", "POISON")],
  [4, t("FIRE")],
  [6, t("FIRE", "FLYING")],
  [7, t("WATER")],
  [16, t("NORMAL", "FLYING")],
  [144, t("ICE", "FLYING")],
  [146, t("FIRE", "FLYING")],
]);

const sp = (n: number, generation = 1) => ({ national_dex_number: n, generation_ordinal: generation });
const ALL = [1, 4, 6, 7, 16, 144, 146, 152].map((n) => sp(n, n > 151 ? 2 : 1)); // 152 sem tipos no índice
const numbers = (list: Array<{ national_dex_number: number }>) => list.map((item) => item.national_dex_number);

test("1. um tipo: espécies com o tipo como primário OU secundário", () => {
  assert.deepEqual(numbers(applyTypeFilter(ALL, INDEX, ["FIRE"]).species), [4, 6, 146]);
  assert.deepEqual(numbers(applyTypeFilter(ALL, INDEX, ["FLYING"]).species), [6, 16, 144, 146]);
});

test("2. dois tipos: só as espécies que têm ambos (E, nunca OU)", () => {
  assert.deepEqual(numbers(applyTypeFilter(ALL, INDEX, ["FIRE", "FLYING"]).species), [6, 146]);
  assert.deepEqual(numbers(applyTypeFilter(ALL, INDEX, ["FIRE", "WATER"]).species), []);
});

test("3. ordem dos tipos não importa para o resultado; a URL guarda a ordem escolhida", () => {
  assert.deepEqual(applyTypeFilter(ALL, INDEX, ["FLYING", "FIRE"]).species, applyTypeFilter(ALL, INDEX, ["FIRE", "FLYING"]).species);
  assert.deepEqual(canonicalTypes(["FIRE", "FLYING"]), ["FIRE", "FLYING"]);
  assert.deepEqual(parseTypeParam("FIRE,FLYING"), { types: ["FIRE", "FLYING"], isCanonical: true });
  assert.deepEqual(parseTypeParam("FLYING,FIRE"), { types: ["FLYING", "FIRE"], isCanonical: true });
});

test("4. limite de duas seleções", () => {
  assert.equal(MAX_TYPE_FILTERS, 2);
  assert.deepEqual(toggleType([], "FIRE"), ["FIRE"]);
  assert.deepEqual(toggleType(["FIRE"], "FLYING"), ["FIRE", "FLYING"]);
  assert.deepEqual(toggleType(["FIRE", "FLYING"], "WATER"), ["FIRE", "FLYING"], "terceiro tipo não entra");
  assert.deepEqual(toggleType(["FIRE", "FLYING"], "FIRE"), ["FLYING"], "remover continua possível no limite");
  assert.deepEqual(parseTypeParam("FIRE,WATER,GRASS").types, ["FIRE", "WATER"]);
  assert.equal(parseTypeParam("FIRE,WATER,GRASS").isCanonical, false);
});

test("5/6. combina com pesquisa e geração: filtra só a lista já reduzida por 6131", () => {
  // "Pesquisa" = lista vinda do banco já filtrada por nome (ex.: só 6 e 146).
  const searched = [sp(6), sp(146)];
  assert.deepEqual(numbers(applyTypeFilter(searched, INDEX, ["FLYING"]).species), [6, 146]);
  // Geração II na lista: nenhuma espécie com tipos → vazio, sem vazar Kanto.
  assert.deepEqual(numbers(applyTypeFilter([sp(152, 2)], INDEX, ["FIRE"]).species), []);
  // Ordem e agrupamento da entrada preservados (a grade agrupa por geração na sequência).
  assert.deepEqual(numbers(applyTypeFilter(ALL, INDEX, []).species), numbers(ALL));
});

test("contagens do seletor: tamanho do resultado se o tipo for acrescentado", () => {
  const none = applyTypeFilter(ALL, INDEX, []).counts;
  assert.equal(none.get("FLYING"), 4);
  assert.equal(none.get("FIRE"), 3);
  const fire = applyTypeFilter(ALL, INDEX, ["FIRE"]).counts;
  assert.equal(fire.get("FLYING"), 2, "Fogo + Voador = 6 e 146");
  assert.equal(fire.get("WATER") ?? 0, 0, "Fogo + Água esvaziaria: opção indisponível");
  assert.equal(fire.get("FIRE"), 3);
});

test("7. URL e retorno da ficha preservam os tipos", () => {
  const context: PokedexContext = { query: "char", generation: 1, types: ["FIRE", "FLYING"] };
  assert.equal(pokedexContextSearch(context), "?q=char&geracao=1&tipo=FIRE,FLYING");
  assert.equal(pokedexHref({ query: null, generation: null, types: ["FIRE"] }), "/pokedex?tipo=FIRE");
  assert.equal(pokedexHref({ query: null, generation: null, types: [] }), "/pokedex");
  assert.equal(speciesDetailHref(6, context), "/pokedex/6?q=char&geracao=1&tipo=FIRE,FLYING");
  assert.equal(nationalPokedexHref(context, 6), "/pokedex?q=char&geracao=1&tipo=FIRE,FLYING#especie-0006");
  // Espécie fora do filtro (próximo nacional = 7, Água): voltar sem âncora.
  assert.equal(speciesMatchesTypes(["WATER", null], context.types), false);
  assert.equal(nationalPokedexHref(context, undefined), "/pokedex?q=char&geracao=1&tipo=FIRE,FLYING");
  // A URL gerada é lida de volta como canônica (sem redirecionamento em laço).
  const tipo = new URLSearchParams(pokedexContextSearch(context).slice(1)).get("tipo") ?? undefined;
  assert.deepEqual(parseTypeParam(tipo), { types: ["FIRE", "FLYING"], isCanonical: true });
});

test("7b. P4a preservada: transição para a próxima geração mantém pesquisa e tipos", () => {
  const node = (n: number, generation: number): NavigationSpecies => ({
    national_dex_number: n,
    species_name: `#${n}`,
    artwork_path: null,
    generation_ordinal: generation,
    generation_code: `GENERATION_${generation === 1 ? "I" : "II"}`,
    region_name: null,
  });
  const context: PokedexContext = { query: null, generation: 1, types: ["FIRE"] };
  const nav = resolveSpeciesNavigation({ current: node(151, 1), previous: node(150, 1), next: node(152, 2), context });
  assert.deepEqual(nav.nextGeneration?.context, { query: null, generation: 2, types: ["FIRE"] });
  // Sem tipos, o contexto continua idêntico ao da P4a.
  const plain = resolveSpeciesNavigation({ current: node(151, 1), previous: null, next: node(152, 2), context: { query: null, generation: 1 } });
  assert.deepEqual(plain.nextGeneration?.context, { query: null, generation: 2 });
});

test("8. links diretos e parâmetros inválidos", () => {
  assert.deepEqual(parseTypeParam(undefined), { types: [], isCanonical: true });
  assert.deepEqual(parseTypeParam("fire"), { types: ["FIRE"], isCanonical: false });
  assert.deepEqual(parseTypeParam(" Fire , flying "), { types: ["FIRE", "FLYING"], isCanonical: false });
  assert.deepEqual(parseTypeParam("FIRE,FIRE"), { types: ["FIRE"], isCanonical: false });
  assert.deepEqual(parseTypeParam("DRAGAO,<script>"), { types: [], isCanonical: false });
  assert.deepEqual(parseTypeParam(""), { types: [], isCanonical: false });
  assert.deepEqual(parseTypeParam(["FIRE", "FLYING"]), { types: ["FIRE", "FLYING"], isCanonical: false });
  assert.deepEqual(parseTypeParam("FIRE FLYING"), { types: ["FIRE", "FLYING"], isCanonical: false }, "'+' na URL vira espaço");
  assert.deepEqual(parseTypeParam("X".repeat(5000)).types, []);
  assert.deepEqual(parseTypeParam("FIRE"), { types: ["FIRE"], isCanonical: true });
});

test("9. sem índice de tipos não há filtro (a página não aplica nada pela metade)", () => {
  // A página só chama applyTypeFilter com índice; com índice vazio, tipo nenhum casa.
  assert.deepEqual(numbers(applyTypeFilter(ALL, new Map(), ["FIRE"]).species), []);
  assert.deepEqual(numbers(applyTypeFilter(ALL, new Map(), []).species), numbers(ALL));
  assert.equal(typeLabels(new Map()).size, 0, "sem rótulos o seletor não é renderizado");
});

test("10. resultado vazio e espécie sem tipos no índice", () => {
  assert.deepEqual(numbers(applyTypeFilter(ALL, INDEX, ["ICE", "FIRE"]).species), []);
  assert.ok(!numbers(applyTypeFilter(ALL, INDEX, ["FLYING"]).species).includes(152));
  assert.equal(speciesMatchesTypes([null, null], ["FIRE"]), false);
  assert.equal(speciesMatchesTypes([null, null], []), true);
});

test("rótulos na ordem oficial e frase do resultado", () => {
  assert.deepEqual([...typeLabels(INDEX).keys()], ["NORMAL", "FLYING", "POISON", "FIRE", "WATER", "GRASS", "ICE"]);
  assert.equal(joinTypeLabels(["Fogo"]), "Fogo");
  assert.equal(joinTypeLabels(["Fogo", "Voador"]), "Fogo e Voador");
});
