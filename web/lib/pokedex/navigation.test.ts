// Navegação entre fichas por contexto (Pokédex P4a).
// Executar: node --experimental-strip-types --test lib/pokedex/navigation.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { test } from "node:test";
import {
  type PokedexContext,
  nationalPokedexHref,
  speciesAnchorId,
  speciesDetailHref,
} from "./format.ts";
import { type NavigationSpecies, isGenerationContextMismatch, resolveSpeciesNavigation } from "./navigation.ts";

const GENERATIONS: Record<number, { code: string; region: string }> = {
  1: { code: "GENERATION_I", region: "Kanto" },
  2: { code: "GENERATION_II", region: "Johto" },
  9: { code: "GENERATION_IX", region: "Paldea" },
};

function sp(n: number, generation: number, name = `Sp${n}`): NavigationSpecies {
  const meta = GENERATIONS[generation];
  assert.ok(meta, `geração ${generation} sem fixture`);
  return {
    national_dex_number: n,
    species_name: name,
    artwork_path: null,
    generation_ordinal: generation,
    generation_code: meta.code,
    region_name: meta.region,
  };
}

const NATIONAL: PokedexContext = { query: null, generation: null };
const GEN_I: PokedexContext = { query: null, generation: 1 };
const GEN_II: PokedexContext = { query: null, generation: 2 };
const GEN_IX: PokedexContext = { query: null, generation: 9 };

/** Simula a ficha: espécie atual + vizinhos ±1 (como a página lê) e o contexto. */
function nav(current: NavigationSpecies, previous: NavigationSpecies | null, next: NavigationSpecies | null, context: PokedexContext) {
  return resolveSpeciesNavigation({ current, previous, next, context });
}

const ANCHOR = /^#especie-(\d{4})$/; // mesmo padrão do RecentSpeciesMarker

test("1. nacional: #151 → #152 atravessa a fronteira e o voltar preserva o contexto nacional", () => {
  const result = nav(sp(151, 1, "Mew"), sp(150, 1), sp(152, 2, "Chikorita"), NATIONAL);
  assert.equal(result.next?.national_dex_number, 152);
  assert.equal(result.previous?.national_dex_number, 150);
  assert.equal(result.nextGeneration, null);
  assert.equal(speciesDetailHref(152, NATIONAL), "/pokedex/152");
  assert.equal(nationalPokedexHref(NATIONAL, 152), "/pokedex#especie-0152");
  // e de volta: #152 no nacional tem #151 (outra geração) como anterior
  const back = nav(sp(152, 2), sp(151, 1), sp(153, 2), NATIONAL);
  assert.equal(back.previous?.national_dex_number, 151);
});

test("2. geração I filtrada no #151: sem próximo de outra geração; transição explícita para a II", () => {
  const result = nav(sp(151, 1, "Mew"), sp(150, 1), sp(152, 2, "Chikorita"), GEN_I);
  assert.equal(result.next, null);
  assert.equal(result.previous?.national_dex_number, 150);
  assert.ok(result.nextGeneration);
  assert.equal(result.nextGeneration.generationOrdinal, 2);
  assert.equal(result.nextGeneration.generationCode, "GENERATION_II");
  assert.equal(result.nextGeneration.regionName, "Johto");
  assert.equal(result.nextGeneration.first.national_dex_number, 152);
  assert.deepEqual(result.nextGeneration.context, GEN_II);
});

test("3. transição I → II: abre #152 com ?geracao=2 e o voltar procura #152 dentro da geração II", () => {
  const { nextGeneration } = nav(sp(151, 1), sp(150, 1), sp(152, 2), GEN_I);
  assert.ok(nextGeneration);
  const href = speciesDetailHref(nextGeneration.first.national_dex_number, nextGeneration.context);
  assert.equal(href, "/pokedex/152?geracao=2");
  const landed = nav(sp(152, 2), sp(151, 1), sp(153, 2), nextGeneration.context);
  assert.equal(isGenerationContextMismatch(nextGeneration.context, 2), false);
  assert.equal(nationalPokedexHref(nextGeneration.context, 152), "/pokedex?geracao=2#especie-0152");
  assert.equal(landed.previous, null, "não volta para a geração I mantendo o filtro da II");
  assert.equal(landed.next?.national_dex_number, 153);
});

test("4. primeira espécie de uma geração filtrada: sem anterior de outra geração", () => {
  const result = nav(sp(152, 2), sp(151, 1), sp(153, 2), GEN_II);
  assert.equal(result.previous, null);
  assert.equal(result.next?.national_dex_number, 153);
  assert.equal(result.nextGeneration, null);
});

test("5. voltar à galeria preserva geração e posição, com âncora reconhecida pelo marcador", () => {
  for (const [context, n] of [
    [GEN_I, 25],
    [GEN_II, 152],
    [{ query: "char", generation: 1 }, 4],
  ] as const) {
    const href = nationalPokedexHref(context, n);
    const hash = href.slice(href.indexOf("#"));
    assert.match(hash, ANCHOR);
    assert.equal(hash, `#${speciesAnchorId(n)}`);
    assert.ok(href.includes(`geracao=${context.generation}`));
  }
});

test("6. pesquisa + geração: vizinhos e transição mantêm a pesquisa; só a geração muda na transição", () => {
  const context: PokedexContext = { query: "mew", generation: 1 };
  const inside = nav(sp(150, 1), sp(149, 1), sp(151, 1), context);
  assert.equal(speciesDetailHref(inside.next!.national_dex_number, context), "/pokedex/151?q=mew&geracao=1");
  const edge = nav(sp(151, 1), sp(150, 1), sp(152, 2), context);
  assert.deepEqual(edge.nextGeneration?.context, { query: "mew", generation: 2 });
  assert.equal(speciesDetailHref(152, edge.nextGeneration!.context), "/pokedex/152?q=mew&geracao=2");
});

test("7. URL compartilhada: geração que não corresponde à espécie é detectada (a página redireciona ao nacional)", () => {
  assert.equal(isGenerationContextMismatch({ query: null, generation: 1 }, 2), true);
  assert.equal(isGenerationContextMismatch({ query: "x", generation: 99 }, 1), true);
  assert.equal(isGenerationContextMismatch({ query: null, generation: 2 }, 2), false);
  assert.equal(isGenerationContextMismatch(NATIONAL, 2), false);
  // destino do redirecionamento: mesma espécie, mesma pesquisa, sem geração
  assert.equal(speciesDetailHref(152, { query: "chi", generation: null }), "/pokedex/152?q=chi");
  // entrada direta sem contexto: comportamento nacional
  const direct = nav(sp(152, 2), sp(151, 1), sp(153, 2), NATIONAL);
  assert.equal(direct.previous?.national_dex_number, 151);
});

test("8. limites #0001 e #1025, nacionais e filtrados", () => {
  const first = nav(sp(1, 1), null, sp(2, 1), NATIONAL);
  assert.equal(first.previous, null);
  assert.equal(first.next?.national_dex_number, 2);
  const firstFiltered = nav(sp(1, 1), null, sp(2, 1), GEN_I);
  assert.equal(firstFiltered.previous, null);
  assert.equal(firstFiltered.nextGeneration, null);

  const last = nav(sp(1025, 9), sp(1024, 9), null, NATIONAL);
  assert.equal(last.next, null);
  assert.equal(last.previous?.national_dex_number, 1024);
  const lastFiltered = nav(sp(1025, 9), sp(1024, 9), null, GEN_IX);
  assert.equal(lastFiltered.next, null);
  assert.equal(lastFiltered.nextGeneration, null, "sem geração seguinte: nenhuma transição inventada");
  assert.equal(lastFiltered.previous?.national_dex_number, 1024);
});

test("9. contexto e 'Última ficha': a âncora do voltar sempre pertence à geração filtrada", () => {
  // Percorre fichas de uma geração filtrada como o usuário faria (próximo → próximo → transição).
  const chain = [sp(149, 1), sp(150, 1), sp(151, 1), sp(152, 2), sp(153, 2)];
  let context: PokedexContext = GEN_I;
  let index = 0;
  for (let step = 0; step < 4; step += 1) {
    const current = chain[index];
    assert.ok(current);
    assert.equal(isGenerationContextMismatch(context, current.generation_ordinal), false);
    const back = nationalPokedexHref(context, current.national_dex_number);
    assert.ok(back.includes(`geracao=${current.generation_ordinal}`), back);
    const result = nav(current, chain[index - 1] ?? null, chain[index + 1] ?? null, context);
    if (result.next) {
      index += 1;
    } else if (result.nextGeneration) {
      context = result.nextGeneration.context;
      index += 1;
    }
  }
  assert.equal(chain[index]?.national_dex_number, 153);
  assert.deepEqual(context, GEN_II);
});
