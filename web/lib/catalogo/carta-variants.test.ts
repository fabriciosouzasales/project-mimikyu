// Regressão VARIANT-GALLERY-REACT-KEY-01 — chave React da tooltip de variantes.
//
// Fixtures SINTÉTICAS (ids inventados); reproduzem apenas a FORMA do caso
// Dark Alakazam: duas Card Variants distintas com o mesmo tipo "Holográfica".
//
// Executar: node --experimental-strip-types --test lib/catalogo/carta-variants.test.ts

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { mapCartaVariants, type CartaVariantRawRow } from "./carta-variants.ts";

const HOLO = { name: "Holográfica", display_order: 2 };
const PADRAO = { name: "Padrão", display_order: 1 };

test("K1: duas variantes Holográficas com ids diferentes continuam sendo dois itens", () => {
  const rows: CartaVariantRawRow[] = [
    { id: "00000000-0000-4000-8000-0000000000a1", card_variant_type: HOLO },
    { id: "00000000-0000-4000-8000-0000000000a2", card_variant_type: HOLO },
  ];
  const out = mapCartaVariants(rows);
  assert.equal(out.length, 2);
  assert.deepEqual(out.map((v) => v.name), ["Holográfica", "Holográfica"]);
  assert.deepEqual(out.map((v) => v.id), [
    "00000000-0000-4000-8000-0000000000a1",
    "00000000-0000-4000-8000-0000000000a2",
  ]);
});

test("K2: as chaves (ids) são únicas mesmo com nomes repetidos", () => {
  const rows: CartaVariantRawRow[] = [
    { id: "id-3", card_variant_type: HOLO },
    { id: "id-1", card_variant_type: PADRAO },
    { id: "id-2", card_variant_type: HOLO },
  ];
  const out = mapCartaVariants(rows);
  const names = out.map((v) => v.name);
  const keys = out.map((v) => v.id);
  assert.ok(new Set(names).size < names.length, "fixture deve ter nomes repetidos");
  assert.equal(new Set(keys).size, keys.length);
});

test("K3: ordem preservada — display_order do tipo, empates na ordem recebida (sort estável)", () => {
  const rows: CartaVariantRawRow[] = [
    { id: "h-first", card_variant_type: HOLO },
    { id: "p", card_variant_type: PADRAO },
    { id: "h-second", card_variant_type: HOLO },
  ];
  assert.deepEqual(mapCartaVariants(rows).map((v) => v.id), ["p", "h-first", "h-second"]);
});

test("K4: variantNames derivado = regra anterior (mesmos nomes, mesma ordem, mesma quantidade)", () => {
  const rows: CartaVariantRawRow[] = [
    { id: "a", card_variant_type: HOLO },
    { id: "b", card_variant_type: null },
    { id: "c", card_variant_type: PADRAO },
    { id: "d", card_variant_type: HOLO },
  ];
  // Regra anterior, copiada literalmente de getCartasCompletas (pré-correção).
  const legacy = rows
    .filter((variant): variant is CartaVariantRawRow & { card_variant_type: { name: string; display_order: number } } => variant.card_variant_type !== null)
    .sort((a, b) => a.card_variant_type.display_order - b.card_variant_type.display_order)
    .map((variant) => variant.card_variant_type.name);
  assert.deepEqual(mapCartaVariants(rows).map((v) => v.name), legacy);
  assert.equal(mapCartaVariants(rows).length, 3);
});

test("K5: entrada nula/vazia e não mutação da entrada", () => {
  assert.deepEqual(mapCartaVariants(null), []);
  assert.deepEqual(mapCartaVariants(undefined), []);
  const rows: CartaVariantRawRow[] = [
    { id: "x", card_variant_type: HOLO },
    { id: "y", card_variant_type: PADRAO },
  ];
  const snapshot = JSON.stringify(rows);
  mapCartaVariants(rows);
  assert.equal(JSON.stringify(rows), snapshot);
});

test("K6: a galeria usa o id como chave, nunca o nome", () => {
  const here = dirname(fileURLToPath(import.meta.url));
  const src = readFileSync(resolve(here, "../../components/catalogo/cartas-gallery.tsx"), "utf8");
  assert.ok(src.includes("key={variant.id}"));
  assert.ok(!src.includes("key={variantName}"));
  assert.ok(!/key=\{variant\.name\}/.test(src));
});
