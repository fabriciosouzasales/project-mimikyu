// Indicadores do capítulo da geração (Pokédex P4b).
// Executar: node --experimental-strip-types --test lib/pokedex/generation-chapter.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { test } from "node:test";
import { buildGenerationChapter, splitChapterTypes, type ChapterTypeCount } from "./generation-chapter.ts";
import type { PokedexGeneration, PokedexSpeciesTypes } from "./queries.ts";

const LABEL: Record<string, string> = {
  GRASS: "Planta",
  POISON: "Venenoso",
  FIRE: "Fogo",
  FLYING: "Voador",
  WATER: "Água",
  NORMAL: "Normal",
  ELECTRIC: "Elétrico",
};

function t(primary: string, secondary: string | null = null): PokedexSpeciesTypes {
  return {
    primaryCode: primary,
    primaryLabel: LABEL[primary] ?? primary,
    secondaryCode: secondary,
    secondaryLabel: secondary ? (LABEL[secondary] ?? secondary) : null,
  };
}

function gen(over: Partial<PokedexGeneration> = {}): PokedexGeneration {
  return {
    generation_code: "GENERATION_I",
    generation_ordinal: 1,
    region_code: "KANTO",
    region_name: "Kanto",
    species_count: 6,
    first_number: 1,
    last_number: 6,
    ...over,
  };
}

// #1–#6 reais: Bulbasaur…Venusaur (Planta/Venenoso), Charmander, Charmeleon (Fogo), Charizard (Fogo/Voador).
const KANTO_START = new Map<number, PokedexSpeciesTypes>([
  [1, t("GRASS", "POISON")],
  [2, t("GRASS", "POISON")],
  [3, t("GRASS", "POISON")],
  [4, t("FIRE")],
  [5, t("FIRE")],
  [6, t("FIRE", "FLYING")],
  // fora da geração (não pode contar):
  [152, t("GRASS")],
]);

test("contagens reais: espécies com o tipo (primário ou secundário), soma pode passar do total", () => {
  const chapter = buildGenerationChapter(gen(), KANTO_START);
  assert.equal(chapter.speciesCount, 6);
  assert.equal(chapter.firstNumber, 1);
  assert.equal(chapter.lastNumber, 6);
  assert.ok(chapter.composition);
  assert.equal(chapter.composition.typedSpecies, 6);
  assert.deepEqual(
    chapter.composition.types.map((x) => [x.code, x.count]),
    [
      ["POISON", 3], // empate 3×3: ordem canônica dos 18 tipos (Venenoso antes de Fogo e Planta)
      ["FIRE", 3],
      ["GRASS", 3],
      ["FLYING", 1],
    ],
  );
  const sum = chapter.composition.types.reduce((acc, x) => acc + x.count, 0);
  assert.equal(sum, 10, "Bulbasaur conta em Planta e em Venenoso: soma 10 > 6 espécies");
  assert.equal(chapter.composition.types.length, 4, "tipos presentes ≠ espécies");
});

test("usa só o intervalo da geração; espécies de outra geração não entram", () => {
  const chapter = buildGenerationChapter(gen(), KANTO_START);
  const grass = chapter.composition?.types.find((x) => x.code === "GRASS");
  assert.equal(grass?.count, 3);
});

test("rótulos vêm do índice (pt-BR), nunca inventados", () => {
  const chapter = buildGenerationChapter(gen(), KANTO_START);
  assert.deepEqual(
    chapter.composition?.types.map((x) => x.label),
    ["Venenoso", "Fogo", "Planta", "Voador"],
  );
});

test("índice de tipos indisponível: sem composição, demais indicadores intactos", () => {
  const chapter = buildGenerationChapter(gen(), null);
  assert.equal(chapter.composition, null);
  assert.equal(chapter.speciesCount, 6);
  assert.equal(chapter.regionName, "Kanto");
});

test("cobertura parcial: typedSpecies menor que o total é informado, não preenchido", () => {
  const partial = new Map(KANTO_START);
  partial.delete(5);
  const chapter = buildGenerationChapter(gen(), partial);
  assert.equal(chapter.composition?.typedSpecies, 5);
  assert.equal(chapter.speciesCount, 6);
  assert.equal(chapter.composition?.types.find((x) => x.code === "FIRE")?.count, 2);
});

test("sem nenhuma espécie com tipo no intervalo: composição nula (nada de 0 tipos)", () => {
  const chapter = buildGenerationChapter(gen({ first_number: 300, last_number: 305 }), KANTO_START);
  assert.equal(chapter.composition, null);
});

test("intervalo ausente na geração: sem composição", () => {
  const chapter = buildGenerationChapter(gen({ first_number: null, last_number: null }), KANTO_START);
  assert.equal(chapter.composition, null);
  assert.equal(chapter.firstNumber, null);
});

test("geração sem região: título cai para o rótulo da geração (regionName nulo preservado)", () => {
  const chapter = buildGenerationChapter(gen({ region_name: null, region_code: null }), KANTO_START);
  assert.equal(chapter.regionName, null);
  assert.equal(chapter.generationCode, "GENERATION_I");
});

test("tipo secundário igual ao primário não conta duas vezes", () => {
  const chapter = buildGenerationChapter(gen({ species_count: 1, last_number: 1 }), new Map([[1, t("NORMAL", "NORMAL")]]));
  assert.deepEqual(chapter.composition?.types.map((x) => [x.code, x.count]), [["NORMAL", 1]]);
});

function counts(...values: number[]): ChapterTypeCount[] {
  return values.map((count, index) => ({ code: `T${index}`, label: `T${index}`, count }));
}

test("corte dos visíveis: 6 por padrão, sem separar empates", () => {
  // Geração I real: 33, 32, 22, 19, 14, 14, 14, 12, 12, ... → os três 14 ficam visíveis.
  const generationI = counts(33, 32, 22, 19, 14, 14, 14, 12, 12, 11, 9, 8, 5, 5, 3, 3, 2);
  const { visible, hidden } = splitChapterTypes(generationI);
  assert.equal(visible.length, 7);
  assert.equal(hidden.length, 10);
  assert.equal(visible.length + hidden.length, 17);
  const few = splitChapterTypes(counts(5, 4, 3));
  assert.equal(few.visible.length, 3);
  assert.equal(few.hidden.length, 0);
  const exact = splitChapterTypes(counts(9, 8, 7, 6, 5, 4, 3));
  assert.equal(exact.visible.length, 6);
  assert.equal(exact.hidden.length, 1);
});
