// Contratos da resolução dos três eixos (P3b).
// Executar: node --experimental-strip-types --test lib/catalogo/axis-resolution.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { test } from "node:test";
import {
  currentItemAxis,
  draftFingerprint,
  effectiveScope,
  findProfileBySignature,
  isClassifiableItem,
  isValidProfileCode,
  nextDisplayOrder,
  parseAxisPreview,
  parseRowDiagnosis,
} from "./axis-resolution.ts";

const explain = {
  row_id: "r1",
  external_set_id: "swsh8",
  validation_status: "NEEDS_REVIEW",
  outcome: "B",
  printing: { state: "RESOLVED_NO_PRINTING", profile: null, traits: [] },
  edition_context: { state: "RESOLVED_NO_EDITION_CONTEXT", profile: null, traits: [] },
  finish: { evaluated: true, residual: { type: "NORMAL", foil: null, subtype: null, stamp: ["X"] }, variant_type: null },
  items: [
    { field: "type", raw: "normal", normalized: "NORMAL", allowed_axes: ["FINISH"], printing_mapping: null, edition_context_mapping: null, in_finish_residual: true, status: "NOT_EVALUATED" },
    { field: "stamp", raw: "x", normalized: "X", allowed_axes: ["FINISH", "PRINTING", "EDITION_CONTEXT"], printing_mapping: null, edition_context_mapping: null, in_finish_residual: true, status: "UNRECOGNIZED" },
    { field: "foil", raw: "y", normalized: "Y", allowed_axes: ["FINISH", "EDITION_CONTEXT"], printing_mapping: null, edition_context_mapping: { id: "m", active: true, scope: "SOURCE_SET", traits: [] }, in_finish_residual: false, status: "EDITION_CONTEXT" },
  ],
};

test("diagnóstico: desconhecido continua sem eixo; type não é classificável", () => {
  const d = parseRowDiagnosis(explain);
  assert.equal(d.items.length, 3);
  assert.equal(isClassifiableItem(d.items[0]!), false);
  assert.equal(isClassifiableItem(d.items[1]!), true);
  assert.equal(currentItemAxis(d.items[1]!), null);
  assert.equal(currentItemAxis(d.items[2]!), "EDITION_CONTEXT");
  assert.deepEqual(d.items[2]!.allowedAxes, ["FINISH", "EDITION_CONTEXT"]);
  assert.deepEqual(d.finish.residual.stamp, ["X"]);
});

test("prévia: impressão digital muda com qualquer campo, não com a ordem das características", () => {
  const base = { axis: "EDITION_CONTEXT" as const, field: "stamp" as const, token: "x", traitIds: ["b", "a"], scope: "SOURCE_SET" as const };
  assert.equal(draftFingerprint(base), draftFingerprint({ ...base, traitIds: ["a", "b"] }));
  assert.notEqual(draftFingerprint(base), draftFingerprint({ ...base, scope: "GLOBAL" }));
  assert.notEqual(draftFingerprint(base), draftFingerprint({ ...base, traitIds: ["a"] }));
});

test("escopo: impressão sempre global; contexto respeita a escolha", () => {
  assert.equal(effectiveScope("PRINTING", "SOURCE_SET"), "GLOBAL");
  assert.equal(effectiveScope("EDITION_CONTEXT", "SOURCE_SET"), "SOURCE_SET");
});

test("perfil: assinatura exata, ordem e código", () => {
  const profiles = [
    { id: "p1", code: "A", name: "A", displayOrder: 3, traitIds: ["t1"] },
    { id: "p2", code: "B", name: "B", displayOrder: 7, traitIds: ["t2", "t1"] },
  ];
  assert.equal(findProfileBySignature(profiles, ["t1", "t2"])?.id, "p2");
  assert.equal(findProfileBySignature(profiles, ["t2"]), null);
  assert.equal(findProfileBySignature(profiles, []), null);
  assert.equal(nextDisplayOrder(profiles), 8);
  assert.equal(isValidProfileCode("staff_promo"), true);
  assert.equal(isValidProfileCode("1X"), false);
});

test("prévia: falha preserva erro e não inventa contagens", () => {
  const p = parseAxisPreview({
    ok: false,
    error: "AXIS_MAPPING_OVERLAP: x",
    scope: "GLOBAL",
    conflicts: [{ code: "EDITION_CONTEXT_ACTIVE", scopes: ["swsh8"] }],
    impact: { rows_touched: 2, jobs: 1, card_sets: 1 },
    rows: [],
  });
  assert.equal(p.ok, false);
  assert.equal(p.impact.resolved, null);
  assert.equal(p.impact.rowsTouched, 2);
  assert.deepEqual(p.conflicts[0], { code: "EDITION_CONTEXT_ACTIVE", scopes: ["swsh8"] });
});
