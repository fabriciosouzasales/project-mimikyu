import assert from "node:assert/strict";
import { test } from "node:test";
import {
  type FinishOption,
  MAX_FINISHES,
  classifyObjectiveFailure,
  initialSelection,
  objectiveFailureMessage,
  objectiveSubtitle,
  objectiveTitle,
  parseObjectiveOptions,
  parsePreview,
  planObjectiveChange,
  positionsDelta,
  previewFinishIds,
  sameSelection,
  savedSelection,
  selectionOrigin,
  toggleFinish,
  MASTER_SET_ADD_FROM_ACERVO_ENABLED,
  MASTER_SET_ADD_FROM_ACERVO_RELEASED,
  MASTER_SET_LOCAL_HOMOLOGATION,
  MASTER_SET_OBJECTIVE_ENABLED,
  MASTER_SET_OBJECTIVE_RELEASED,
  MASTER_SET_PAGE_SIZE,
  finishBadge,
  heroCardsFromMasterSet,
  masterSetTotalPages,
  outOfScopeReasonText,
  parseMasterSetPage,
  parseMasterSetPositions,
  parseOutOfScope,
  parsePositionCopies,
  positionCopyLabel,
  positionKey,
  positionStatusText,
  MASTER_SET_LINK_BATCH_SIZE,
  isPositionKey,
  parseMasterSetLinkCandidates,
  pickLinkCopies,
} from "./master-set.ts";
import { collectionKindLabel } from "./colecoes.ts";

const STD = "11111111-1111-4111-8111-111111111111";
const HOLO = "22222222-2222-4222-8222-222222222222";
const REV = "33333333-3333-4333-8333-333333333333";
const COSMOS = "44444444-4444-4444-8444-444444444444";

function finish(id: string, code: string, order: number, saved = false): FinishOption {
  return { id, code, name: code, order, positions: 10, ownedPositions: 2, saved };
}

const FOUR = [finish(STD, "STANDARD", 1), finish(HOLO, "HOLO", 2), finish(COSMOS, "COSMOS_HOLO", 3), finish(REV, "REVERSE_HOLO", 4)];

test("parseObjectiveOptions: acabamentos na ordem do catálogo, secretas à parte, linhas malformadas descartadas", () => {
  const parsed = parseObjectiveOptions([
    { row_kind: "FINISH", variant_type_id: REV, variant_type_code: "REVERSE_HOLO", variant_type_name: "Holográfica Reversa", display_order: 4, positions: 90, owned_positions: 12, is_selected: false },
    { row_kind: "FINISH", variant_type_id: STD, variant_type_code: "STANDARD", variant_type_name: "Padrão", display_order: 1, positions: "102", owned_positions: "40", is_selected: true },
    { row_kind: "FINISH", variant_type_id: "nao-e-uuid", variant_type_name: "X", positions: 1 },
    { row_kind: "FINISH", variant_type_id: HOLO, variant_type_name: "  ", positions: 1 },
    { row_kind: "SECRET_CARDS", variant_type_id: null, positions: 8, owned_positions: 3, is_selected: true },
  ]);
  assert.deepEqual(
    parsed.finishes.map((f) => [f.name, f.positions, f.ownedPositions, f.saved]),
    [
      ["Padrão", 102, 40, true],
      ["Holográfica Reversa", 90, 12, false],
    ],
  );
  assert.deepEqual(parsed.secrets, { positions: 8, ownedPositions: 3 });
});

test("parseObjectiveOptions: Set sem secretas → secrets null; owned nunca passa de positions", () => {
  const parsed = parseObjectiveOptions([
    { row_kind: "FINISH", variant_type_id: STD, variant_type_name: "Padrão", display_order: 1, positions: 5, owned_positions: 9 },
    { row_kind: "SECRET_CARDS", positions: 0, owned_positions: 0 },
  ]);
  assert.equal(parsed.secrets, null);
  assert.equal(parsed.finishes[0]?.ownedPositions, 5);
});

test("initialSelection: restaura a seleção guardada quando existe", () => {
  const finishes = [finish(STD, "STANDARD", 1), finish(COSMOS, "COSMOS_HOLO", 3, true)];
  assert.deepEqual(initialSelection(finishes), [COSMOS]);
  assert.equal(selectionOrigin(finishes), "saved");
});

test("initialSelection: sem gravação, sugere Padrão + Holográfica + Reversa que existam no Set", () => {
  assert.deepEqual(initialSelection(FOUR), [STD, HOLO, REV]);
  assert.equal(selectionOrigin(FOUR), "suggested");
  assert.deepEqual(initialSelection([finish(COSMOS, "COSMOS_HOLO", 3), finish(HOLO, "HOLO", 2)]), [HOLO]);
});

test("initialSelection: sem nenhuma sugerida no Set, começa pelo primeiro acabamento; sem acabamentos, vazio", () => {
  assert.deepEqual(initialSelection([finish(COSMOS, "COSMOS_HOLO", 3)]), [COSMOS]);
  assert.deepEqual(initialSelection([]), []);
});

test("toggleFinish preserva a ordem do catálogo; sameSelection ignora ordem e caixa", () => {
  assert.deepEqual(toggleFinish([REV], STD, FOUR), [STD, REV]);
  assert.deepEqual(toggleFinish([STD, REV], STD, FOUR), [REV]);
  assert.ok(sameSelection([STD, REV], [REV.toUpperCase(), STD]));
  assert.ok(!sameSelection([STD], [STD, REV]));
});

test("plan: ativar com a seleção guardada intacta → restauração (NULL, preserva guardados ocultos)", () => {
  const finishes = [finish(STD, "STANDARD", 1, true), finish(HOLO, "HOLO", 2, true), finish(REV, "REVERSE_HOLO", 4)];
  const plan = planObjectiveChange({ policy: "STANDARD_SET", finishes }, "MASTER_SET", [HOLO, STD]);
  assert.deepEqual(plan, { kind: "activate", finishIds: null });
  assert.deepEqual(previewFinishIds(plan, { finishes }), [STD, HOLO]);
});

test("plan: ativar com seleção diferente (ou sem gravação) → lista explícita", () => {
  const saved = [finish(STD, "STANDARD", 1, true), finish(HOLO, "HOLO", 2)];
  assert.deepEqual(planObjectiveChange({ policy: "STANDARD_SET", finishes: saved }, "MASTER_SET", [STD, HOLO]), {
    kind: "activate",
    finishIds: [STD, HOLO],
  });
  assert.deepEqual(planObjectiveChange({ policy: "STANDARD_SET", finishes: FOUR }, "MASTER_SET", [STD]), {
    kind: "activate",
    finishIds: [STD],
  });
});

test("plan: em Master Set, mesma seleção → nada; outra → replace (5195)", () => {
  const finishes = [finish(STD, "STANDARD", 1, true), finish(HOLO, "HOLO", 2)];
  assert.deepEqual(planObjectiveChange({ policy: "MASTER_SET", finishes }, "MASTER_SET", [STD]), { kind: "none" });
  assert.deepEqual(planObjectiveChange({ policy: "MASTER_SET", finishes }, "MASTER_SET", [STD, HOLO]), {
    kind: "replace",
    finishIds: [STD, HOLO],
  });
});

test("plan: voltar ao Set padrão (5081) e Set padrão sem mudança", () => {
  assert.deepEqual(planObjectiveChange({ policy: "MASTER_SET", finishes: FOUR }, "STANDARD_SET", []), { kind: "to_standard" });
  assert.deepEqual(planObjectiveChange({ policy: "STANDARD_SET", finishes: FOUR }, "STANDARD_SET", [STD]), { kind: "none" });
  assert.equal(previewFinishIds({ kind: "to_standard" }, { finishes: FOUR }), null);
});

test("plan: seleção vazia ou acima do teto é recusada antes do banco", () => {
  assert.deepEqual(planObjectiveChange({ policy: "STANDARD_SET", finishes: FOUR }, "MASTER_SET", []), {
    kind: "invalid",
    reason: "empty_selection",
  });
  const many = Array.from({ length: MAX_FINISHES + 1 }, (_, i) => `00000000-0000-4000-8000-${String(i).padStart(12, "0")}`);
  assert.deepEqual(planObjectiveChange({ policy: "MASTER_SET", finishes: FOUR }, "MASTER_SET", many), {
    kind: "invalid",
    reason: "too_many",
  });
});

test("savedSelection ignora acabamentos não gravados", () => {
  assert.deepEqual(savedSelection([finish(STD, "STANDARD", 1, true), finish(HOLO, "HOLO", 2)]), [STD]);
});

test("parsePreview converte bigint em número e recusa política desconhecida", () => {
  const preview = parsePreview({
    current_policy: "STANDARD_SET",
    current_total: "102",
    current_satisfied: "40",
    proposed_total: "290",
    proposed_satisfied: "61",
    proposed_secret_positions: "3",
    positions_added: "290",
    positions_removed: "0",
    copies_in_collection: "75",
    copies_outside_after: "4",
  });
  assert.equal(preview?.proposedTotal, 290);
  assert.equal(preview?.copiesOutsideAfter, 4);
  assert.equal(parsePreview({ current_policy: "NONE" }), null);
  assert.equal(parsePreview(undefined), null);
});

test("rótulos oficiais N8/N9 — nunca o enum", () => {
  assert.equal(objectiveTitle("MASTER_SET"), "Master Set");
  assert.equal(objectiveSubtitle("MASTER_SET"), "os acabamentos que você escolher");
  assert.equal(objectiveTitle("STANDARD_SET"), "Set padrão");
  assert.equal(collectionKindLabel("MASTER_SET"), "Master Set — os acabamentos que você escolher");
  assert.equal(collectionKindLabel("STANDARD_SET"), "Set padrão — uma de cada carta");
});

test("positionsDelta", () => {
  assert.equal(positionsDelta(0, "+"), null);
  assert.equal(positionsDelta(1, "+"), "+1 posição");
  assert.equal(positionsDelta(1200, "−"), "−1.200 posições");
});

test("classifyObjectiveFailure: códigos de 5191–5195 e frases de 5081", () => {
  assert.equal(classifyObjectiveFailure("28000", "not_authenticated"), "not_authenticated");
  assert.equal(classifyObjectiveFailure("42501", "authentication required"), "not_authenticated");
  assert.equal(classifyObjectiveFailure("P0002", "COLLECTION_NOT_FOUND"), "not_found");
  assert.equal(classifyObjectiveFailure("P0002", "collection not found"), "not_found");
  assert.equal(classifyObjectiveFailure("P0001", "COLLECTION_ARCHIVED"), "archived");
  assert.equal(classifyObjectiveFailure("23514", "collection is archived — reactivate before changing completion policy"), "archived");
  assert.equal(classifyObjectiveFailure("P0001", "FINISH_NOT_IN_SET"), "stale");
  assert.equal(classifyObjectiveFailure("P0001", "NO_SAVED_FINISHES"), "stale");
  assert.equal(classifyObjectiveFailure("P0001", "MASTER_SET_NOT_ACTIVE"), "stale");
  assert.equal(classifyObjectiveFailure("P0001", "EMPTY_OBJECTIVE"), "empty_objective");
  assert.equal(classifyObjectiveFailure("22023", "INVALID_FINISHES"), "invalid");
  assert.equal(classifyObjectiveFailure(undefined, "fetch failed"), "unavailable");
});

test("mensagens de falha não expõem códigos técnicos", () => {
  const reasons = ["not_authenticated", "not_found", "archived", "stale", "empty_objective", "invalid", "disabled", "unavailable"] as const;
  for (const reason of reasons) {
    const text = objectiveFailureMessage(reason);
    assert.ok(text.length > 10);
    assert.ok(!/[A-Z]{3,}_[A-Z]/.test(text), `${reason} expõe enum: ${text}`);
  }
});

// ---------------------------------------------------------------------------
// MASTER-SET-FRONTEND-PHASE-02 — grade, fora do objetivo, adicionar
// ---------------------------------------------------------------------------

const CARD_A = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const CARD_S = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const COPY = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";

test("flags: Master Set publicado (2026-10-19); homologação local continua só em `next dev`", () => {
  assert.equal(MASTER_SET_OBJECTIVE_RELEASED, true);
  assert.equal(MASTER_SET_ADD_FROM_ACERVO_RELEASED, true);
  assert.equal(MASTER_SET_LOCAL_HOMOLOGATION, false);
  assert.equal(MASTER_SET_OBJECTIVE_ENABLED, true);
  assert.equal(MASTER_SET_ADD_FROM_ACERVO_ENABLED, true);
});

test("parseMasterSetPositions: carta + acabamento e secreta genérica com chaves distintas", () => {
  const page = parseMasterSetPositions([
    { card_id: CARD_A, collector_number: "4", collector_total: 102, card_name: "Charizard", variant_type_id: STD, variant_type_name: "Padrão", is_secret: false, image_path: "a.png", is_satisfied: true, copies_in_collection: 2, copies_available: 1, total_count: "290" },
    { card_id: CARD_A, collector_number: "4", collector_total: 102, card_name: "Charizard", variant_type_id: HOLO, variant_type_name: "Holográfica", is_secret: false, image_path: "a.png", is_satisfied: false, copies_in_collection: 0, copies_available: 3, total_count: "290" },
    { card_id: CARD_S, collector_number: "110", collector_total: 102, card_name: "Pikachu", variant_type_id: null, variant_type_name: null, is_secret: true, image_path: null, is_satisfied: false, copies_in_collection: 0, copies_available: 0, total_count: "290" },
    { card_id: "x", variant_type_id: STD },
    { card_id: CARD_A, variant_type_id: "não-uuid" },
  ]);
  assert.equal(page.total, 290);
  assert.equal(page.items.length, 3);
  assert.deepEqual(
    page.items.map((p) => p.key),
    [positionKey(CARD_A, STD), positionKey(CARD_A, HOLO), positionKey(CARD_S, null)],
  );
  assert.equal(new Set(page.items.map((p) => p.key)).size, 3);
  const secret = page.items[2]!;
  assert.equal(secret.variantTypeId, null);
  assert.equal(secret.isSecret, true);
  assert.equal(finishBadge(secret), "Qualquer acabamento");
  assert.equal(finishBadge(page.items[1]!), "Holográfica");
});

test("positionStatusText distingue tenho / no acervo / falta", () => {
  assert.equal(positionStatusText({ isSatisfied: true, copiesAvailable: 0 }), "na coleção");
  assert.equal(positionStatusText({ isSatisfied: false, copiesAvailable: 2 }), "falta na coleção, mas você tem no acervo");
  assert.equal(positionStatusText({ isSatisfied: false, copiesAvailable: 0 }), "falta");
});

test("paginação: página da URL e total de páginas pelo contrato", () => {
  assert.equal(parseMasterSetPage(undefined), 1);
  assert.equal(parseMasterSetPage("3"), 3);
  assert.equal(parseMasterSetPage("0"), 1);
  assert.equal(parseMasterSetPage("abc"), 1);
  assert.equal(parseMasterSetPage(["2", "9"]), 2);
  assert.equal(masterSetTotalPages(0), 1);
  assert.equal(masterSetTotalPages(MASTER_SET_PAGE_SIZE), 1);
  assert.equal(masterSetTotalPages(MASTER_SET_PAGE_SIZE + 1), 2);
  assert.ok(MASTER_SET_PAGE_SIZE <= 500);
});

test("heroCardsFromMasterSet: uma entrada por carta, tem se qualquer posição tem", () => {
  const page = parseMasterSetPositions([
    { card_id: CARD_A, collector_number: "4", collector_total: 102, card_name: "C", variant_type_id: STD, is_satisfied: false, image_path: null },
    { card_id: CARD_A, collector_number: "4", collector_total: 102, card_name: "C", variant_type_id: HOLO, is_satisfied: true, image_path: "a.png" },
  ]);
  const hero = heroCardsFromMasterSet(page.items);
  assert.equal(hero.length, 1);
  assert.equal(hero[0]?.isSatisfied, true);
  assert.equal(hero[0]?.imagePath, "a.png");
});

test("parseOutOfScope: só motivos conhecidos; texto do motivo sem código", () => {
  const page = parseOutOfScope([
    { physical_card_id: COPY, card_name: "Charizard", collector_number: "4", variant_type_name: "Holográfica Cosmos", reason: "FINISH_NOT_SELECTED", total_count: 3 },
    { physical_card_id: COPY, reason: "OUTRO" },
  ]);
  assert.equal(page.items.length, 1);
  assert.equal(page.total, 3);
  for (const reason of ["CARD_INACTIVE", "PAIR_NOT_IN_CATALOG", "FINISH_NOT_SELECTED"] as const) {
    const text = outOfScopeReasonText(reason);
    assert.ok(!/[A-Z]{3,}_[A-Z]/.test(text));
  }
});

test("parsePositionCopies e rótulo versão + idioma", () => {
  const page = parsePositionCopies([
    { physical_card_id: COPY, variant_label: "Holográfica · 1ª Edição", is_default_variant: false, language_code: "pt-BR", language_name: "Português", storage_name: "Fichário 1", added_at: "2026-10-01T00:00:00Z", total_count: 1 },
    { physical_card_id: "x" },
  ]);
  assert.equal(page.items.length, 1);
  assert.equal(positionCopyLabel(page.items[0]!), "Holográfica · 1ª Edição · Português");
  assert.equal(positionCopyLabel({ variantLabel: null, isDefaultVariant: true, languageName: "" }), "Versão padrão");
});

const LC_CARD_A = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const LC_CARD_B = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const PC1 = "c1c1c1c1-c1c1-4c1c-8c1c-c1c1c1c1c1c1";
const PC2 = "c2c2c2c2-c2c2-4c2c-8c2c-c2c2c2c2c2c2";
const PC3 = "c3c3c3c3-c3c3-4c3c-8c3c-c3c3c3c3c3c3";

test("parseMasterSetLinkCandidates: uma linha por posição, genérica com chave 'secreta', total do contrato", () => {
  const parsed = parseMasterSetLinkCandidates([
    { physical_card_id: PC1.toUpperCase(), card_id: LC_CARD_A, variant_type_id: STD, collector_number: "001", card_name: "Um", variant_type_name: " Padrão ", is_secret: false, language_code: "pt-BR", image_path: "a.webp", total_count: "93" },
    { physical_card_id: PC2, card_id: LC_CARD_B, variant_type_id: null, collector_number: "200", card_name: "Secreta", variant_type_name: "ignorado", is_secret: true, language_code: null, image_path: "", total_count: 93 },
  ]);
  assert.equal(parsed.total, 93);
  assert.equal(parsed.items.length, 2);
  assert.deepEqual(parsed.items[0], {
    key: positionKey(LC_CARD_A, STD), physicalCardId: PC1, cardId: LC_CARD_A, variantTypeId: STD, collectorNumber: "001",
    cardName: "Um", variantTypeName: "Padrão", isSecret: false, languageCode: "pt-BR", imagePath: "a.webp",
  });
  assert.equal(parsed.items[1]?.key, `${LC_CARD_B}:secreta`);
  assert.equal(parsed.items[1]?.variantTypeName, null);
  assert.equal(parsed.items[1]?.imagePath, null);
  assert.equal(parsed.items[1]?.languageCode, null);
});

test("parseMasterSetLinkCandidates: descarta malformadas e nunca repete posição ou exemplar", () => {
  const parsed = parseMasterSetLinkCandidates([
    { physical_card_id: "x", card_id: LC_CARD_A, variant_type_id: STD, total_count: 3 },
    { physical_card_id: PC1, card_id: LC_CARD_A, variant_type_id: "nao-uuid", total_count: 3 },
    { physical_card_id: PC1, card_id: LC_CARD_A, variant_type_id: STD, total_count: 3 },
    { physical_card_id: PC2, card_id: LC_CARD_A, variant_type_id: STD, total_count: 3 },
    { physical_card_id: PC1, card_id: LC_CARD_A, variant_type_id: REV, total_count: 3 },
    { physical_card_id: PC3, card_id: LC_CARD_A, variant_type_id: REV, total_count: 3 },
  ]);
  assert.deepEqual(parsed.items.map((item) => item.physicalCardId), [PC1, PC3]);
  assert.equal(parsed.total, 3);
  assert.deepEqual(parseMasterSetLinkCandidates([]), { items: [], total: 0 });
});

test("isPositionKey aceita carta:acabamento e carta:secreta; recusa o resto", () => {
  assert.ok(isPositionKey(positionKey(LC_CARD_A, STD)));
  assert.ok(isPositionKey(positionKey(LC_CARD_B, null)));
  for (const bad of ["", LC_CARD_A, `${LC_CARD_A}:`, `${LC_CARD_A}:x`, `x:${STD}`, `${LC_CARD_A}:${STD}:${STD}`, 42, null]) {
    assert.equal(isPositionKey(bad), false, String(bad));
  }
});

test("pickLinkCopies: só posições marcadas que continuam faltando, na ordem do Set", () => {
  const { items } = parseMasterSetLinkCandidates([
    { physical_card_id: PC1, card_id: LC_CARD_A, variant_type_id: STD, total_count: 3 },
    { physical_card_id: PC2, card_id: LC_CARD_A, variant_type_id: REV, total_count: 3 },
    { physical_card_id: PC3, card_id: LC_CARD_B, variant_type_id: null, total_count: 3 },
  ]);
  const wanted = new Set([positionKey(LC_CARD_B, null), positionKey(LC_CARD_A, STD), "outra:posicao-ja-atendida"]);
  assert.deepEqual(pickLinkCopies(items, wanted), [PC1, PC3]);
  assert.deepEqual(pickLinkCopies(items, new Set()), []);
  assert.equal(MASTER_SET_LINK_BATCH_SIZE, 500);
});
