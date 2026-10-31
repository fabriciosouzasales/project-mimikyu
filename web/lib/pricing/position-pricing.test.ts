// V1-09 Fase B — preço por posição (Set, Master Set, Pokédex): regras puras.
// Executar: node --experimental-strip-types --test lib/pricing/position-pricing.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { test } from "node:test";
import {
  masterPositionVariants,
  parseCardVariantRows,
  parseRepresentativeRows,
  pokedexPositionVariants,
  positionVariantIds,
  setPositionVariants,
  singleVariant,
} from "./position-pricing.ts";

const CARD_X = "11111111-1111-4111-8111-111111111111";
const CARD_Y = "22222222-2222-4222-8222-222222222222";
const NORMAL = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const REVERSE = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const TYPE_NORMAL = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
const TYPE_REVERSE = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";
const V_X_NORMAL = "e1111111-1111-4111-8111-111111111111";
const V_X_REVERSE = "e2222222-2222-4222-8222-222222222222";
const V_Y = "e3333333-3333-4333-8333-333333333333";
const POS_1 = "f1111111-1111-4111-8111-111111111111";
const POS_2 = "f2222222-2222-4222-8222-222222222222";

function row(card: string, type: string | null, variant: string, copies: number, language = "pt-BR", label = "Normal") {
  return { card_id: card, variant_type_id: type, card_variant_id: variant, variant_label: label, language_code: language, copies };
}

test("parse 5333: descarta linha sem id, cópia zero ou negativa; não-lista = null", () => {
  assert.equal(parseCardVariantRows(null), null);
  assert.equal(parseCardVariantRows({}), null);
  const rows = parseCardVariantRows([
    row(CARD_X, TYPE_NORMAL, V_X_NORMAL, 2),
    { ...row(CARD_X, TYPE_NORMAL, V_X_NORMAL, 1), card_id: "x" },
    row(CARD_Y, TYPE_NORMAL, V_Y, 0),
    { ...row(CARD_Y, null, V_Y, 3), copies: "3" },
  ]);
  assert.equal(rows?.length, 2);
  assert.equal(rows?.[1]?.copies, 3);
  assert.equal(rows?.[1]?.variantTypeId, null);
});

test("Set: uma variante com várias cópias → preço unitário dessa variante", () => {
  const rows = parseCardVariantRows([row(CARD_X, TYPE_NORMAL, V_X_NORMAL, 3)]) ?? [];
  const map = setPositionVariants(rows);
  assert.deepEqual(map.get(CARD_X), { cardVariantId: V_X_NORMAL, variantLabel: "Normal", languageCode: "pt-BR" });
});

test("Set: variantes diferentes na mesma carta → nenhuma etiqueta (nunca atribui preço de outra variante)", () => {
  const rows =
    parseCardVariantRows([row(CARD_X, TYPE_NORMAL, V_X_NORMAL, 1), row(CARD_X, TYPE_REVERSE, V_X_REVERSE, 1, "pt-BR", "Reversa"), row(CARD_Y, TYPE_NORMAL, V_Y, 1)]) ?? [];
  const map = setPositionVariants(rows);
  assert.equal(map.has(CARD_X), false);
  assert.equal(map.get(CARD_Y)?.cardVariantId, V_Y);
});

test("mesma variante em idiomas diferentes: preço da variante, idioma não declarado", () => {
  const rows = parseCardVariantRows([row(CARD_X, TYPE_NORMAL, V_X_NORMAL, 1, "pt-BR"), row(CARD_X, TYPE_NORMAL, V_X_NORMAL, 1, "en")]) ?? [];
  const variant = singleVariant(rows);
  assert.equal(variant?.cardVariantId, V_X_NORMAL);
  assert.equal(variant?.languageCode, null);
});

test("sem exemplares → nada", () => {
  assert.equal(singleVariant([]), null);
  assert.equal(setPositionVariants([]).size, 0);
});

test("Master Set: cada acabamento tem a própria posição — preço não migra entre Normal e Reversa", () => {
  const rows =
    parseCardVariantRows([row(CARD_X, TYPE_NORMAL, V_X_NORMAL, 2), row(CARD_X, TYPE_REVERSE, V_X_REVERSE, 1, "pt-BR", "Reversa")]) ?? [];
  const positions = [
    { key: "normal", cardId: CARD_X, variantTypeId: TYPE_NORMAL },
    { key: "reversa", cardId: CARD_X, variantTypeId: TYPE_REVERSE },
    { key: "vazia", cardId: CARD_Y, variantTypeId: TYPE_NORMAL },
  ];
  const map = masterPositionVariants(rows, positions);
  assert.equal(map.get("normal")?.cardVariantId, V_X_NORMAL);
  assert.equal(map.get("reversa")?.cardVariantId, V_X_REVERSE);
  assert.equal(map.has("vazia"), false);
});

test("Master Set: secreta genérica com um acabamento → preço; com dois → nenhuma etiqueta", () => {
  const one = parseCardVariantRows([row(CARD_X, TYPE_NORMAL, V_X_NORMAL, 1)]) ?? [];
  const two = parseCardVariantRows([row(CARD_X, TYPE_NORMAL, V_X_NORMAL, 1), row(CARD_X, TYPE_REVERSE, V_X_REVERSE, 1)]) ?? [];
  const positions = [{ key: "secreta", cardId: CARD_X, variantTypeId: null }];
  assert.equal(masterPositionVariants(one, positions).get("secreta")?.cardVariantId, V_X_NORMAL);
  assert.equal(masterPositionVariants(two, positions).has("secreta"), false);
});

test("Master Set: duas variantes do mesmo acabamento (ex.: carimbos) → nenhuma etiqueta", () => {
  const rows = parseCardVariantRows([row(CARD_X, TYPE_NORMAL, V_X_NORMAL, 1), row(CARD_X, TYPE_NORMAL, V_Y, 1, "pt-BR", "Normal · Carimbo")]) ?? [];
  assert.equal(masterPositionVariants(rows, [{ key: "normal", cardId: CARD_X, variantTypeId: TYPE_NORMAL }]).size, 0);
});

test("Pokédex: preço do representante só quando a carta coincide com a exibida (número + Set)", () => {
  const rows =
    parseRepresentativeRows([
      { pokedex_position_id: POS_1, card_variant_id: V_X_NORMAL, variant_label: "Normal", language_code: "pt-BR", collector_number: "025", card_set_code: "sv1" },
      { pokedex_position_id: POS_2, card_variant_id: V_Y, variant_label: "Normal", language_code: "en", collector_number: "004", card_set_code: "base1" },
    ]) ?? [];
  const positions = [
    { positionId: POS_1, isSatisfied: true, representative: { collectorNumber: "025", setCode: "SV1" } },
    { positionId: POS_2, isSatisfied: true, representative: { collectorNumber: "005", setCode: "base1" } },
  ];
  const map = pokedexPositionVariants(rows, positions);
  assert.equal(map.get(POS_1)?.cardVariantId, V_X_NORMAL);
  assert.equal(map.has(POS_2), false);
});

test("Pokédex: posição não conquistada ou sem representante → nada", () => {
  const rows =
    parseRepresentativeRows([
      { pokedex_position_id: POS_1, card_variant_id: V_X_NORMAL, collector_number: "025", card_set_code: "sv1" },
    ]) ?? [];
  assert.equal(pokedexPositionVariants(rows, [{ positionId: POS_1, isSatisfied: false, representative: { collectorNumber: "025", setCode: "sv1" } }]).size, 0);
  assert.equal(pokedexPositionVariants(rows, [{ positionId: POS_1, isSatisfied: true, representative: null }]).size, 0);
});

test("ids para o lote de preços: distintos", () => {
  const map = new Map([
    ["a", { cardVariantId: V_Y, variantLabel: null, languageCode: null }],
    ["b", { cardVariantId: V_Y, variantLabel: null, languageCode: null }],
    ["c", { cardVariantId: V_X_NORMAL, variantLabel: null, languageCode: null }],
  ]);
  assert.deepEqual(positionVariantIds(map).sort(), [V_X_NORMAL, V_Y].sort());
});
