// Meu acervo — adicionar cartas: regras puras (MY-INVENTORY-ACTIONS-01).
// Executar: node --experimental-strip-types --test lib/colecoes/acervo-add.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { test } from "node:test";
import {
  ADD_MAX_QUANTITY,
  ADD_MAX_TOTAL,
  type DraftLine,
  addLine,
  classifyFailure,
  confirmCardsRequest,
  confirmSetRequest,
  defaultLanguageId,
  defaultVariant,
  draftProblem,
  failureMessage,
  isRetryable,
  issueMessage,
  parsePreview,
  parseRegister,
  previewCardsRequest,
  previewSetRequest,
  removeLine,
  selectionLabel,
  toRegisterItems,
  totalQuantity,
  updateLine,
  validRegisterItems,
} from "./acervo-add.ts";

const V1 = "11111111-1111-4111-8111-111111111111";
const V2 = "22222222-2222-4222-8222-222222222222";
const PT = "33333333-3333-4333-8333-333333333333";
const EN = "44444444-4444-4444-8444-444444444444";
const KEY = "55555555-5555-4555-8555-555555555555";
const SET = "66666666-6666-4666-8666-666666666666";

function line(overrides: Partial<DraftLine> = {}): DraftLine {
  return {
    cardId: "c1",
    cardName: "Pikachu",
    setCode: "base1",
    setName: "Base",
    collectorNumber: "58",
    collectorTotal: 102,
    imageUrl: null,
    variantId: V1,
    variantLabel: null,
    isDefaultVariant: true,
    languageId: PT,
    quantity: 1,
    ...overrides,
  };
}

test("addLine soma a mesma variante+idioma em vez de duplicar a linha", () => {
  const lines = addLine(addLine([], line()), line({ quantity: 2 }));
  assert.equal(lines.length, 1);
  assert.equal(lines[0]?.quantity, 3);
  const other = addLine(lines, line({ languageId: EN }));
  assert.equal(other.length, 2);
});

test("quantidade fica entre 1 e o máximo por linha", () => {
  const lines = addLine([line({ quantity: 98 })], line({ quantity: 5 }));
  assert.equal(lines[0]?.quantity, ADD_MAX_QUANTITY);
  assert.equal(updateLine(lines, 0, { quantity: 0 })[0]?.quantity, 1);
  assert.equal(updateLine(lines, 0, { quantity: Number.NaN })[0]?.quantity, 1);
  assert.equal(updateLine(lines, 0, { quantity: 2.7 })[0]?.quantity, 2);
});

test("updateLine funde linhas que passam a ser iguais, preservando a posição da primeira", () => {
  const lines = [line({ quantity: 2 }), line({ cardId: "x", variantId: V2, quantity: 1 }), line({ languageId: EN, quantity: 4 })];
  const merged = updateLine(lines, 2, { languageId: PT });
  assert.equal(merged.length, 2);
  assert.equal(merged[0]?.quantity, 6);
  assert.equal(merged[1]?.variantId, V2);
});

test("removeLine, totalQuantity e toRegisterItems", () => {
  const lines = [line({ quantity: 2 }), line({ variantId: V2, quantity: 3 })];
  assert.equal(totalQuantity(lines), 5);
  assert.deepEqual(toRegisterItems(lines), [
    { card_variant_id: V1, language_id: PT, quantity: 2 },
    { card_variant_id: V2, language_id: PT, quantity: 3 },
  ]);
  assert.equal(removeLine(lines, 0).length, 1);
});

test("draftProblem: vazio e acima do teto", () => {
  assert.match(draftProblem([]) ?? "", /ao menos uma/);
  assert.equal(draftProblem([line()]), null);
  const many = Array.from({ length: 11 }, (_, i) =>
    line({ variantId: `${String(i).padStart(8, "0")}-1111-4111-8111-111111111111`, quantity: ADD_MAX_QUANTITY }),
  );
  assert.ok(totalQuantity(many) > ADD_MAX_TOTAL);
  assert.match(draftProblem(many) ?? "", /máximo por vez/);
});

test("validRegisterItems recusa formato inválido, duplicata e teto", () => {
  assert.equal(validRegisterItems([{ card_variant_id: V1, language_id: PT, quantity: 1 }]), true);
  assert.equal(validRegisterItems([]), false);
  assert.equal(validRegisterItems("x"), false);
  assert.equal(validRegisterItems([{ card_variant_id: "nope", language_id: PT, quantity: 1 }]), false);
  assert.equal(validRegisterItems([{ card_variant_id: V1, language_id: PT, quantity: 0 }]), false);
  assert.equal(validRegisterItems([{ card_variant_id: V1, language_id: PT, quantity: 1.5 }]), false);
  assert.equal(
    validRegisterItems([
      { card_variant_id: V1, language_id: PT, quantity: 1 },
      { card_variant_id: V1, language_id: PT, quantity: 2 },
    ]),
    false,
  );
  const overTotal = Array.from({ length: 11 }, (_, i) => ({
    card_variant_id: `${String(i).padStart(8, "0")}-1111-4111-8111-111111111111`,
    language_id: PT,
    quantity: ADD_MAX_QUANTITY,
  }));
  assert.equal(validRegisterItems(overTotal), false);
});

test("envelopes têm exatamente as chaves dos contratos", () => {
  const items = [{ card_variant_id: V1, language_id: PT, quantity: 1 }];
  assert.deepEqual(Object.keys(previewCardsRequest(items)).sort(), ["collection_id", "items", "operation_type", "storage_container_id"]);
  assert.equal(previewCardsRequest(items).operation_type, "REGISTER_PHYSICAL_CARDS");
  assert.deepEqual(Object.keys(confirmCardsRequest(KEY, "fp", items)).sort(), [
    "collection_id",
    "idempotency_key",
    "items",
    "preview_fingerprint",
    "storage_container_id",
  ]);
  assert.deepEqual(Object.keys(previewSetRequest(SET, PT)).sort(), [
    "card_set_id",
    "collection_id",
    "language_id",
    "operation_type",
    "storage_container_id",
  ]);
  assert.equal(previewSetRequest(SET, PT).operation_type, "REGISTER_CARD_SET");
  assert.deepEqual(Object.keys(confirmSetRequest(KEY, "fp", SET, PT)).sort(), [
    "card_set_id",
    "collection_id",
    "idempotency_key",
    "language_id",
    "preview_fingerprint",
    "storage_container_id",
  ]);
});

test("parsePreview: contrato binário e leitura defensiva", () => {
  const ok = parsePreview({
    operation_type: "REGISTER_PHYSICAL_CARDS",
    ok: true,
    preview_fingerprint: "abc",
    summary: { distinct_items: 2, total_quantity: "5" },
    issues: [],
  });
  assert.deepEqual(ok, { ok: true, fingerprint: "abc", distinctItems: 2, totalQuantity: 5, issues: [] });

  const blocked = parsePreview({
    ok: false,
    preview_fingerprint: null,
    summary: { distinct_items: 1, total_quantity: 1 },
    issues: [{ code: "CARD_DEFAULT_VARIANT_MISSING", severity: "BLOCKING", offenders: ["a", "b"] }, { nope: 1 }],
  });
  assert.equal(blocked?.ok, false);
  assert.deepEqual(blocked?.issues, [{ code: "CARD_DEFAULT_VARIANT_MISSING", count: 2 }]);

  assert.equal(parsePreview(null), null);
  assert.equal(parsePreview({ ok: "yes" }), null);
  // ok=true sem fingerprint viola o contrato: tratado como erro, nunca como liberação.
  assert.equal(parsePreview({ ok: true, preview_fingerprint: "  ", summary: {}, issues: [] }), null);
});

test("parseRegister aceita CREATED e REPLAY", () => {
  const created = parseRegister({ outcome: "CREATED", operation_id: KEY, result_summary: { created_count: 3, distinct_items: 2 } });
  assert.deepEqual(created, { replay: false, createdCount: 3, distinctItems: 2 });
  assert.equal(parseRegister({ outcome: "REPLAY", result_summary: { created_count: 3 } })?.replay, true);
  assert.equal(parseRegister({ outcome: "CONFLICT", result_summary: {} }), null);
  assert.equal(parseRegister({ outcome: "CREATED" }), null);
});

test("classifyFailure usa SQLSTATE e prefixos estáveis; nada de texto cru ao usuário", () => {
  assert.equal(classifyFailure("22023", "PREVIEW_STALE: o estado mudou desde o preview"), "stale");
  assert.equal(classifyFailure("22023", "BULK_IDEMPOTENCY_CONFLICT: idempotency_key ja usada"), "conflict");
  assert.equal(classifyFailure("22023", "CARD_VARIANT_INACTIVE: 1 card_variant_id inativa(s)"), "inactive_variant");
  assert.equal(classifyFailure("22023", "CARD_DEFAULT_VARIANT_MISSING: 2 card(s)"), "default_variant_missing");
  assert.equal(classifyFailure("22023", "a operacao criaria 1200 Physical Cards e excede o limite de 1000 por chamada"), "too_many");
  assert.equal(classifyFailure("22023", "card set not found"), "set_not_found");
  assert.equal(classifyFailure("22023", "card set has no active cards"), "set_empty");
  assert.equal(classifyFailure("28000", "authentication required"), "not_authenticated");
  assert.equal(classifyFailure("55000", "PHYSICAL_CARD_ALLOCATED: o exemplar está em uma coleção"), "allocated");
  assert.match(failureMessage("allocated"), /Retire-o da coleção/);
  assert.equal(classifyFailure("22023", "items nao pode ser vazio"), "invalid");
  assert.equal(classifyFailure("57014", "canceling statement due to statement timeout"), "unavailable");
  assert.equal(classifyFailure(undefined, undefined), "unavailable");
  for (const reason of ["stale", "conflict", "unavailable", "invalid"] as const) {
    assert.ok(failureMessage(reason).length > 10);
    assert.doesNotMatch(failureMessage(reason), /PREVIEW_STALE|idempotency|uuid/i);
  }
  assert.equal(isRetryable("unavailable"), true);
  assert.equal(isRetryable("stale"), false);
});

test("issueMessage em linguagem do colecionador", () => {
  assert.match(issueMessage({ code: "CARD_DEFAULT_VARIANT_MISSING", count: 3 }), /3 cartas deste Set/);
  assert.match(issueMessage({ code: "CARD_DEFAULT_VARIANT_MISSING", count: 1 }), /Uma carta deste Set/);
  assert.match(issueMessage({ code: "QUALQUER", count: 0 }), /impedimento/);
});

test("rótulos e padrões", () => {
  assert.equal(selectionLabel({ copies: 1, distinct: 1 }), "1 carta");
  assert.equal(selectionLabel({ copies: 12, distinct: 5 }), "12 cartas · 5 diferentes");
  assert.equal(defaultLanguageId([{ id: EN, code: "en", name: "English" }, { id: PT, code: "pt-BR", name: "Português" }]), PT);
  assert.equal(defaultLanguageId([{ id: EN, code: "en", name: "English" }]), EN);
  assert.equal(defaultLanguageId([]), null);
  assert.equal(defaultVariant([{ id: V2, label: "Holo", isDefault: false }, { id: V1, label: null, isDefault: true }])?.id, V1);
  assert.equal(defaultVariant([])?.id, undefined);
});
