// Regras da descrição bilíngue da ficha (Pokédex P3d).
// Executar: node --experimental-strip-types --test lib/pokedex/description-presentation.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { test } from "node:test";
import {
  EDITORIAL_LABEL,
  type SpeciesTextFields,
  buildDescriptionPresentation,
  buildLegacySourceNote,
  needsOriginalText,
} from "./description-presentation.ts";

const official = (over: Partial<SpeciesTextFields> = {}): SpeciesTextFields => ({
  genus: "Seed Pokémon",
  genus_language: "en",
  genus_is_official: true,
  description: "While it is young, it uses the nutrients that are stored in the seed on its back in order to grow.",
  description_language: "en",
  description_is_official: true,
  description_source_version: "shield",
  ...over,
});

const editorial = (over: Partial<SpeciesTextFields> = {}): SpeciesTextFields => ({
  genus: "Pokémon Semente",
  genus_language: "pt-BR",
  genus_is_official: false,
  description: "A semente nas costas de Bulbasaur não é enfeite.",
  description_language: "pt-BR",
  description_is_official: false,
  description_source_version: null,
  ...over,
});

test("sem editorial: modo único com a nota da P3b, sem leitura em inglês", () => {
  const species = official();
  assert.equal(needsOriginalText(species), false);
  const result = buildDescriptionPresentation(species, null);
  assert.equal(result.mode, "single");
  if (result.mode !== "single") return;
  assert.equal(result.editorial, false);
  assert.equal(result.variant.lang, "en");
  assert.equal(result.variant.note, "Classificação e descrição oficiais em inglês, de Pokémon Shield.");
  assert.equal(result.variant.note, buildLegacySourceNote(species));
});

test("sem editorial: nota idêntica à P3b nos demais casos", () => {
  assert.equal(buildLegacySourceNote(official({ genus_language: "pt-BR" })), "Descrição oficial em inglês, de Pokémon Shield.");
  assert.equal(
    buildLegacySourceNote(official({ genus_language: "pt-BR", description_language: "pt-BR" })),
    "Descrição oficial de Pokémon Shield.",
  );
  assert.equal(
    buildLegacySourceNote(official({ genus_language: "pt-BR", description_language: "pt-BR", description_source_version: null })),
    null,
  );
});

test("sem descrição: nada a apresentar", () => {
  assert.equal(buildDescriptionPresentation(official({ description: null }), null).mode, "none");
});

test("editorial + original: bilíngue, português primeiro com o rótulo editorial", () => {
  const species = editorial();
  assert.equal(needsOriginalText(species), true);
  const result = buildDescriptionPresentation(species, official());
  assert.equal(result.mode, "bilingual");
  if (result.mode !== "bilingual") return;
  assert.deepEqual(result.portuguese, {
    text: species.description,
    lang: "pt-BR",
    note: EDITORIAL_LABEL,
  });
  assert.equal(EDITORIAL_LABEL, "Texto editorial MMKYU · Português brasileiro");
});

test("variante inglesa: texto oficial, lang en, proveniência com a versão do jogo", () => {
  const result = buildDescriptionPresentation(editorial(), official({ description_source_version: "legends-arceus" }));
  if (result.mode !== "bilingual") return assert.fail("esperado bilíngue");
  assert.equal(result.english.lang, "en");
  assert.equal(result.english.text, official().description);
  assert.equal(result.english.note, "Descrição oficial em inglês · Pokémon Legends: Arceus");
});

test("variante inglesa sem versão de origem: proveniência sem versão", () => {
  const result = buildDescriptionPresentation(editorial(), official({ description_source_version: null }));
  if (result.mode !== "bilingual") return assert.fail("esperado bilíngue");
  assert.equal(result.english.note, "Descrição oficial em inglês");
});

test("falha na leitura em inglês: ficha utilizável só em português, com o rótulo", () => {
  const result = buildDescriptionPresentation(editorial(), null);
  assert.equal(result.mode, "single");
  if (result.mode !== "single") return;
  assert.equal(result.editorial, true);
  assert.equal(result.variant.lang, "pt-BR");
  assert.equal(result.variant.note, EDITORIAL_LABEL);
});

test("original que não é oficial em inglês nunca vira 'descrição oficial'", () => {
  assert.equal(buildDescriptionPresentation(editorial(), official({ description_is_official: false })).mode, "single");
  assert.equal(buildDescriptionPresentation(editorial(), official({ description_language: "pt-BR" })).mode, "single");
  assert.equal(buildDescriptionPresentation(editorial(), official({ description: null })).mode, "single");
});

test("texto pt-BR marcado como oficial não é tratado como editorial", () => {
  const species = editorial({ description_is_official: true });
  assert.equal(needsOriginalText(species), false);
  assert.equal(buildDescriptionPresentation(species, official()).mode, "single");
});
