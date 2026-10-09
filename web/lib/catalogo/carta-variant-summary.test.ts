// Testes do modelo do indicador de variantes (VARIANT-DISPLAY-SEMANTICS-01 / F2.2).
// Execução: node --experimental-strip-types --test lib/catalogo/carta-variant-summary.test.ts

import assert from "node:assert/strict";
import { test } from "node:test";

import {
  buildVariantSummaryModel,
  cartaVariantCount,
  hasCartaVariants,
  VARIANT_LABEL_SEPARATOR,
} from "./carta-variant-summary.ts";
import { buildCartaVariantView, CARD_VARIANT_LABEL_SEPARATOR, type CartaVariantViewState } from "./carta-variants.ts";

const CARD = "11111111-1111-4111-8111-111111111111";
const HOLO = { id: "aaaaaaaa-0000-4000-8000-000000000001", code: "HOLO", name: "Holográfica", display_order: 30 };
const FIRST_ED = { id: "bbbbbbbb-0000-4000-8000-000000000001", name: "1ª Edição", display_order: 10 };
const PLAYER_REWARDS = { id: "cccccccc-0000-4000-8000-000000000001", name: "Programa Player Rewards", display_order: 20 };

function row(id: string, printing: typeof FIRST_ED | null, ec: typeof PLAYER_REWARDS | null) {
  return {
    id,
    card_id: CARD,
    variant_type_id: HOLO.id,
    printing_profile_id: printing ? printing.id : null,
    edition_context_profile_id: ec ? ec.id : null,
    card_variant_type: HOLO,
    card_printing_profile: printing,
    card_edition_context_profile: ec,
  };
}

const V1 = "dddddddd-0000-4000-8000-000000000001";
const V2 = "dddddddd-0000-4000-8000-000000000002";
const V3 = "dddddddd-0000-4000-8000-000000000003";

test("M0: separador do cliente é o mesmo da decisão D1", () => {
  assert.equal(VARIANT_LABEL_SEPARATOR, CARD_VARIANT_LABEL_SEPARATOR);
  assert.equal(VARIANT_LABEL_SEPARATOR, " / ");
});

test("M1: NONE, null e undefined escondem o indicador", () => {
  assert.deepEqual(buildVariantSummaryModel({ status: "NONE", rawCount: 0 }, "X"), { kind: "HIDDEN" });
  assert.deepEqual(buildVariantSummaryModel(null, "X"), { kind: "HIDDEN" });
  assert.deepEqual(buildVariantSummaryModel(undefined, "X"), { kind: "HIDDEN" });
});

test("M2: Dark Alakazam — duas Holográficas distintas, identidade completa e ordem da F1", () => {
  const view = buildCartaVariantView([row(V2, FIRST_ED, null), row(V1, null, null)], "BASE5");
  const model = buildVariantSummaryModel(view, "Dark Alakazam");
  assert.equal(model.kind, "LIST");
  if (model.kind !== "LIST") return;
  assert.equal(model.count, 2);
  assert.deepEqual(model.lines.map((l) => l.id), [V1, V2]);
  assert.deepEqual(model.lines.map((l) => l.label), ["Holográfica", "Holográfica / 1ª Edição"]);
  assert.deepEqual(model.lines[1]!.parts, [
    { axis: "FINISH", text: "Holográfica", emphasis: "primary" },
    { axis: "PRINTING", text: "1ª Edição", emphasis: "qualifier" },
  ]);
  assert.equal(model.lines.some((l) => l.repeatedLabel), false);
  assert.equal(model.triggerLabel, "Ver variações de Dark Alakazam: 2 variações cadastradas");
});

test("M3: Edition Context vira qualificador; singular no rótulo do gatilho", () => {
  const view = buildCartaVariantView([row(V3, null, PLAYER_REWARDS)], "SVE");
  const model = buildVariantSummaryModel(view, "Energia");
  assert.equal(model.kind, "LIST");
  if (model.kind !== "LIST") return;
  assert.equal(model.lines[0]!.label, "Holográfica / Programa Player Rewards");
  assert.equal(model.lines[0]!.parts[1]!.emphasis, "qualifier");
  assert.equal(model.triggerLabel, "Ver variações de Energia: 1 variação cadastrada");
});

test("M4: rótulos repetidos são sinalizados e nunca deduplicados (M3 da F1)", () => {
  const view: CartaVariantViewState = {
    status: "OK",
    rawCount: 2,
    variants: [
      { id: V1, parts: [{ axis: "FINISH", text: "Holográfica" }], collidesWith: [V2], renderedCollidesWith: [V2] },
      { id: V2, parts: [{ axis: "FINISH", text: "Holográfica" }], collidesWith: [V1], renderedCollidesWith: [V1] },
    ],
  };
  const model = buildVariantSummaryModel(view, "X");
  assert.equal(model.kind, "LIST");
  if (model.kind !== "LIST") return;
  assert.equal(model.lines.length, 2);
  assert.deepEqual(model.lines.map((l) => l.repeatedLabel), [true, true]);
});

test("M5: colisão só do texto renderizado também é sinalizada", () => {
  const view: CartaVariantViewState = {
    status: "OK",
    rawCount: 2,
    variants: [
      { id: V1, parts: [{ axis: "FINISH", text: "A / B" }], collidesWith: [], renderedCollidesWith: [V2] },
      { id: V2, parts: [{ axis: "FINISH", text: "A" }, { axis: "PRINTING", text: "B" }], collidesWith: [], renderedCollidesWith: [V1] },
    ],
  };
  const model = buildVariantSummaryModel(view, "X");
  assert.equal(model.kind, "LIST");
  if (model.kind !== "LIST") return;
  assert.deepEqual(model.lines.map((l) => l.repeatedLabel), [true, true]);
});

test("M6: ERROR mostra a contagem bruta e nenhum nome (D2, sem fallback)", () => {
  const view = buildCartaVariantView([row(V1, null, null), { ...row(V2, null, null), card_variant_type: null }], "BASE5");
  assert.equal(view.status, "ERROR");
  const model = buildVariantSummaryModel(view, "Dark Alakazam");
  assert.deepEqual(model, {
    kind: "UNAVAILABLE",
    count: 2,
    triggerLabel: "Dark Alakazam: 2 variações cadastradas, detalhes indisponíveis",
  });
  assert.equal(JSON.stringify(model).includes("Holográfica"), false);
});

test("M7: ERROR sem contagem (lista não chegou como array)", () => {
  const view = buildCartaVariantView(null, "BASE5");
  assert.equal(view.status, "ERROR");
  const model = buildVariantSummaryModel(view, "X");
  assert.deepEqual(model, { kind: "UNAVAILABLE", count: null, triggerLabel: "X: variações cadastradas, detalhes indisponíveis" });
});

test("M8: contagem = rawCount = número de linhas (G-COMP)", () => {
  const view = buildCartaVariantView([row(V1, null, null), row(V2, FIRST_ED, null), row(V3, null, PLAYER_REWARDS)], "BASE5");
  const model = buildVariantSummaryModel(view, "X");
  assert.equal(model.kind, "LIST");
  if (model.kind !== "LIST") return;
  assert.equal(model.count, 3);
  assert.equal(model.lines.length, 3);
});

// F2.3 — presença e contagem para filtros e totais do relatório.

test("M9: presença — NONE/ausente = sem; OK e ERROR = com", () => {
  assert.equal(hasCartaVariants(undefined), false);
  assert.equal(hasCartaVariants(null), false);
  assert.equal(hasCartaVariants({ status: "NONE", rawCount: 0 }), false);
  assert.equal(hasCartaVariants(buildCartaVariantView([row(V1, null, null)], "BASE5")), true);
  assert.equal(hasCartaVariants(buildCartaVariantView(null, "BASE5")), true);
});

test("M10: contagem — rawCount; 0 sem variante; null quando desconhecida", () => {
  assert.equal(cartaVariantCount(undefined), 0);
  assert.equal(cartaVariantCount({ status: "NONE", rawCount: 0 }), 0);
  assert.equal(cartaVariantCount(buildCartaVariantView([row(V1, null, null), row(V2, FIRST_ED, null)], "BASE5")), 2);
  const err = buildCartaVariantView([row(V1, null, null), { ...row(V2, null, null), card_variant_type: null }], "BASE5");
  assert.equal(err.status, "ERROR");
  assert.equal(cartaVariantCount(err), 2);
  assert.equal(cartaVariantCount(buildCartaVariantView(null, "BASE5")), null);
});
