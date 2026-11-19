// V1-13 · E2-1 — curadoria do EDITOR no fichário compartilhado: regras puras.
// Executar: node --experimental-strip-types --test lib/colecoes/editor-binder.test.ts (a partir de web/)
// Testes LOCAIS de regra de tela. Não provam autorização: isso é do servidor (5373/5374) e das provas S1–S10 (C-244).

import assert from "node:assert/strict";
import { test } from "node:test";
import type { BinderPage } from "./binder.ts";
import type { AvailableCard } from "./binder-share.ts";
import {
  applyPatch,
  canShowEditorCuration,
  classifyEditorFailure,
  editorCanPick,
  editorCanTarget,
  editorCurationFlagOn,
  editorFailureDisablesEditing,
  editorFailureMessage,
  editorFailureRechecksAccess,
  findUndoCandidate,
  isPocketPosition,
  parsePlaceableCards,
  patchMove,
  patchPlace,
  patchRemove,
  placeableEmptyState,
  settleEditorOutcome,
  sharedSlotPosition,
} from "./editor-binder.ts";
import { parseSharedCollection, sharedPageToBinderPage } from "./sharing.ts";

const CO = "11111111-1111-4111-8111-111111111111";
const PC = "22222222-2222-4222-8222-222222222222";
const PC2 = "33333333-3333-4333-8333-333333333333";

function at<T>(items: readonly T[], index: number): T {
  const item = items[index];
  if (item === undefined) throw new Error(`índice ${index} ausente`);
  return item;
}

function page(): BinderPage {
  return sharedPageToBinderPage({
    pageNumber: 2,
    pockets: [
      { row: 1, column: 1, kind: "card", cardName: "Pikachu", collectorNumber: "25", collectorTotal: 102, setCode: "base1", variantLabel: "Normal", languageCode: "en", imagePath: null },
      { row: 1, column: 2, kind: "empty", cardName: null, collectorNumber: null, collectorTotal: null, setCode: null, variantLabel: null, languageCode: null, imagePath: null },
      { row: 1, column: 3, kind: "reserve", cardName: "Raichu", collectorNumber: "14", collectorTotal: 102, setCode: "base1", variantLabel: null, languageCode: null, imagePath: null },
    ],
  });
}

const card = (over: Partial<AvailableCard> = {}): AvailableCard => ({
  allocationId: null, physicalCardId: PC, cardId: "", variantTypeId: null, cardName: "Pikachu", collectorNumber: "25", collectorTotal: 102,
  setCode: "base1", variantLabel: "Normal", languageCode: "en", imagePath: null, originKind: "THIS", originCollectionId: null,
  originCollectionName: null, originArchived: false, ...over,
});

test("D1: configuração desligada por padrão; só 'on' liga", () => {
  assert.equal(editorCurationFlagOn({}), false);
  assert.equal(editorCurationFlagOn({ MMKYU_V113_EDITOR_CURATION: "" }), false);
  assert.equal(editorCurationFlagOn({ MMKYU_V113_EDITOR_CURATION: "true" }), false);
  assert.equal(editorCurationFlagOn({ MMKYU_V113_EDITOR_CURATION: " ON " }), true);
});

test("controles só para EDITOR, com a configuração ligada e coleção ativa", () => {
  assert.equal(canShowEditorCuration({ flagOn: true, role: "EDITOR", archived: false }), true);
  assert.equal(canShowEditorCuration({ flagOn: false, role: "EDITOR", archived: false }), false, "EDITOR com a configuração desligada");
  assert.equal(canShowEditorCuration({ flagOn: true, role: "VIEWER", archived: false }), false, "VIEWER");
  assert.equal(canShowEditorCuration({ flagOn: true, role: null, archived: false }), false, "sem papel");
  assert.equal(canShowEditorCuration({ flagOn: true, role: "EDITOR", archived: true }), false, "arquivada");
});

test("5312: role EDITOR só junto de access VIEWER; titular e público sem papel", () => {
  const base = { collection_id: CO, name: "Base", visibility: "PRIVATE", owner_display_name: "Ana" };
  assert.equal(parseSharedCollection({ ...base, access: "VIEWER", role: "EDITOR" })?.role, "EDITOR");
  assert.equal(parseSharedCollection({ ...base, access: "VIEWER", role: "VIEWER" })?.role, "VIEWER");
  assert.equal(parseSharedCollection({ ...base, access: "VIEWER" })?.role, "VIEWER", "antes da 5368, sem a chave");
  assert.equal(parseSharedCollection({ ...base, access: "VIEWER", role: "ADMIN" })?.role, "VIEWER", "valor desconhecido nunca vira EDITOR");
  assert.equal(parseSharedCollection({ ...base, access: "OWNER", role: "EDITOR" })?.role, null);
  assert.equal(parseSharedCollection({ ...base, access: "PUBLIC", role: "EDITOR" })?.role, null);
});

test("posição do bolso a partir do id mascarado", () => {
  assert.deepEqual(sharedSlotPosition("shared:2:1:3"), { page: 2, row: 1, column: 3 });
  assert.equal(sharedSlotPosition("shared:0:1:1"), null);
  assert.equal(sharedSlotPosition("shared:1:11:1"), null);
  assert.equal(sharedSlotPosition("8f2c…"), null);
  assert.equal(sharedSlotPosition("shared:1:1"), null);
  assert.equal(isPocketPosition({ page: 1, row: 1, column: 1 }), true);
  assert.equal(isPocketPosition({ page: 1.5, row: 1, column: 1 }), false);
  assert.equal(isPocketPosition({ page: 1, row: 0, column: 1 }), false);
});

test("5373: lista elegível sem campos patrimoniais; formato inválido → null", () => {
  const parsed = parsePlaceableCards([
    { physical_card_id: PC.toUpperCase(), card_name: "Pikachu", collector_number: "25", collector_total: 102, card_set_code: "base1", variant_label: "Normal", language_code: "en", image_path: null, total_count: 3 },
  ]);
  assert.ok(parsed);
  assert.equal(parsed.total, 3);
  assert.equal(at(parsed.items, 0).physicalCardId, PC);
  assert.equal(at(parsed.items, 0).originKind, "THIS");
  assert.equal(at(parsed.items, 0).allocationId, null);
  assert.deepEqual(parsePlaceableCards([]), { items: [], total: 0 });
  assert.equal(parsePlaceableCards([{ card_name: "x" }]), null);
  assert.equal(parsePlaceableCards({}), null);
});

test("recusas: códigos do servidor → motivos estáveis", () => {
  assert.equal(classifyEditorFailure("42501", "CAPABILITY_NOT_ENABLED"), "capability_closed");
  assert.equal(classifyEditorFailure("42501", "SLOT_NOT_EDITABLE"), "not_editable");
  assert.equal(classifyEditorFailure("P0002", "PHYSICAL_CARD_NOT_ELIGIBLE"), "not_eligible");
  assert.equal(classifyEditorFailure("P0001", "CARD_ALREADY_PLACED"), "already_placed");
  assert.equal(classifyEditorFailure("P0002", "SLOT_EMPTY"), "source_empty");
  assert.equal(classifyEditorFailure("55000", "SLOT_LOCKED"), "locked");
  assert.equal(classifyEditorFailure("P0001", "COLLECTION_ARCHIVED"), "archived");
  assert.equal(classifyEditorFailure("P0002", "COLLECTION_NOT_FOUND"), "access_lost");
  assert.equal(classifyEditorFailure("P0002", "BINDER_NOT_FOUND"), "access_lost");
  assert.equal(classifyEditorFailure("55P03", "could not obtain lock"), "lock_busy");
  assert.equal(classifyEditorFailure("22023", "INVALID_ARGUMENT"), "invalid");
  assert.equal(classifyEditorFailure(null, "algo novo"), "unknown");
});

test("D3: bolso fixado → 'Esse bolso está fixado'", () => {
  assert.equal(editorFailureMessage("locked"), "Esse bolso está fixado.");
});

test("privacidade: nenhuma mensagem descreve conteúdo, local, outra coleção ou identificador", () => {
  const reasons = ["not_editable", "not_eligible", "already_placed", "source_empty", "locked", "archived", "lock_busy", "capability_closed", "access_lost", "not_authenticated", "disabled", "invalid", "unknown"] as const;
  for (const reason of reasons) {
    const text = editorFailureMessage(reason).toLowerCase();
    for (const banned of ["outra coleção", "local", "acervo", "condição", "imagem", "reserv", "sem coleção", "alocad", "uuid", "id "]) {
      assert.ok(!text.includes(banned), `${reason}: "${text}" cita "${banned}"`);
    }
  }
  // SLOT_NOT_EDITABLE e posição inexistente recebem a MESMA mensagem: não revela se o bolso existe nem o que o ocupa.
  assert.equal(classifyEditorFailure("42501", "SLOT_NOT_EDITABLE"), "not_editable");
});

test("perda de permissão e barreira fechada desligam a edição; acesso perdido relê a coleção", () => {
  for (const r of ["capability_closed", "access_lost", "archived", "disabled", "not_authenticated"] as const) assert.equal(editorFailureDisablesEditing(r), true, r);
  for (const r of ["not_editable", "not_eligible", "locked", "lock_busy", "source_empty", "already_placed", "unknown"] as const) assert.equal(editorFailureDisablesEditing(r), false, r);
  assert.equal(editorFailureRechecksAccess("access_lost"), true);
  assert.equal(editorFailureRechecksAccess("capability_closed"), false);
});

test("a tela não decide autorização pelo aspecto: bolso vazio é alvo, a resposta do servidor é que vale", () => {
  const p = page();
  const [occupied, empty, reserved] = [at(p.slots, 0), at(p.slots, 1), at(p.slots, 2)];
  assert.equal(editorCanTarget(empty), true);
  assert.equal(editorCanTarget(reserved), true);
  assert.equal(editorCanPick(occupied), true);
  assert.equal(editorCanPick(empty), false);
  assert.equal(editorCanTarget({ ...empty, image: { path: "x", focalY: 50, updatedAt: "", url: "u" } }), false, "imagem do titular nunca é alvo");
  assert.equal(editorCanTarget({ ...empty, regionId: "shared-region:2:1:2" }), false, "mesclagem nunca é alvo");
});

test("otimista: colocar, mover/trocar e retirar; reversão restaura o estado anterior", () => {
  const p = page();
  const cache = new Map([[2, p]]);
  const [occupied, empty] = [at(p.slots, 0), at(p.slots, 1)];

  const placed = applyPatch(cache, patchPlace(empty, card({ physicalCardId: PC2, cardName: "Bulbasaur" })));
  assert.equal(placed.cache.get(2)?.slots[1]?.present?.cardName, "Bulbasaur");
  const reverted = applyPatch(placed.cache, placed.previous);
  assert.deepEqual(reverted.cache.get(2), p, "reverter devolve exatamente o bolso lido");

  const moved = applyPatch(cache, patchMove(occupied, empty));
  assert.equal(moved.cache.get(2)?.slots[0]?.present, null);
  assert.equal(moved.cache.get(2)?.slots[1]?.present?.cardName, "Pikachu");

  const removed = applyPatch(cache, patchRemove(occupied));
  assert.equal(removed.cache.get(2)?.slots[0]?.present, null);
  assert.deepEqual(applyPatch(removed.cache, removed.previous).cache.get(2), p);
  assert.deepEqual(cache.get(2), p, "o cache original não é mutado");
});

test("D2: desfazer só com candidato único; ambíguo ou ausente → sem desfazer", () => {
  const removed = at(page().slots, 0);
  assert.equal(findUndoCandidate([card()], removed)?.physicalCardId, PC);
  assert.equal(findUndoCandidate([card(), card({ physicalCardId: PC2 })], removed), null, "dois exemplares idênticos");
  assert.equal(findUndoCandidate([card({ languageCode: "pt" })], removed), null, "outro idioma");
  assert.equal(findUndoCandidate([], removed), null);
});

// ---- fechamento das escritas (mesma função usada pela área de trabalho) ----

test("fluxo: colocar, mover/trocar, retirar e desfazer com sucesso", () => {
  const none = new Map();
  const add = settleEditorOutcome({ kind: "place", cardName: "Pikachu", page: 2 }, { ok: true, operation: "ADD" }, none);
  assert.deepEqual([add.toast.text, add.filledDelta, add.revert, add.disable], ["Pikachu foi para a página 2.", 1, null, false]);
  assert.equal(settleEditorOutcome({ kind: "place", cardName: "P", page: 1 }, { ok: true, operation: "REPLACE" }, none).filledDelta, 0, "substituir não muda a contagem");
  assert.equal(settleEditorOutcome({ kind: "place", cardName: "P", page: 1 }, { ok: true, operation: "UNCHANGED" }, none).toast.text, "A carta já está nesse bolso.");
  assert.equal(settleEditorOutcome({ kind: "move", cardName: "A", otherName: "B", page: 3 }, { ok: true, operation: "SWAP" }, none).toast.text, "A e B trocaram de lugar.");
  assert.equal(settleEditorOutcome({ kind: "move", cardName: "A", otherName: null, page: 3 }, { ok: true, operation: "MOVE" }, none).toast.text, "A foi para a página 3.");
  const rm = settleEditorOutcome({ kind: "remove" }, { ok: true, operation: "REMOVED" }, none);
  assert.deepEqual([rm.toast.text, rm.filledDelta], ["A carta saiu do fichário e continua na coleção.", -1]);
  assert.equal(settleEditorOutcome({ kind: "undo", cardName: "Pikachu" }, { ok: true, operation: "ADD" }, none).toast.text, "Pikachu voltou para o bolso.");
});

test("reversão: recusa devolve exatamente o estado lido antes da mudança otimista", () => {
  const p = page();
  const cache = new Map([[2, p]]);
  const [occupied, empty] = [at(p.slots, 0), at(p.slots, 1)];
  for (const [label, change] of [
    ["colocar", patchPlace(empty, card({ physicalCardId: PC2 }))],
    ["mover", patchMove(occupied, empty)],
    ["retirar", patchRemove(occupied)],
  ] as const) {
    const optimistic = applyPatch(cache, change);
    const s = settleEditorOutcome({ kind: "remove" }, { ok: false, reason: "not_editable" }, optimistic.previous);
    assert.ok(s.revert, label);
    assert.deepEqual(applyPatch(optimistic.cache, s.revert).cache.get(2), p, label);
    assert.equal(s.toast.tone, "error");
    assert.equal(s.filledDelta, 0, `${label}: recusa não mexe na contagem`);
  }
});

test("perda de permissão (papel trocado, saída, remoção): reverte, desliga a edição e relê a coleção", () => {
  const p = page();
  const optimistic = applyPatch(new Map([[2, p]]), patchRemove(at(p.slots, 0)));
  const s = settleEditorOutcome({ kind: "remove" }, { ok: false, reason: "access_lost" }, optimistic.previous);
  assert.deepEqual([s.disable, s.recheck, s.toast.text], [true, true, "Sua permissão para organizar este fichário mudou."]);
  assert.ok(s.revert);
});

test("barreira fechada (CAPABILITY_NOT_ENABLED): desliga a edição, sem afirmar nada sobre o bolso", () => {
  const s = settleEditorOutcome({ kind: "place", cardName: "P", page: 1 }, { ok: false, reason: classifyEditorFailure("42501", "CAPABILITY_NOT_ENABLED") }, new Map());
  assert.deepEqual([s.disable, s.recheck, s.toast.text], [true, false, "A organização compartilhada ainda não está disponível."]);
});

test("D3: bolso fixado — mensagem própria, edição continua", () => {
  const s = settleEditorOutcome({ kind: "move", cardName: "A", otherName: null, page: 1 }, { ok: false, reason: classifyEditorFailure("55000", "SLOT_LOCKED") }, new Map());
  assert.deepEqual([s.toast.text, s.disable], ["Esse bolso está fixado.", false]);
});

test("D2: falha no desfazer — mensagem neutra, nada a reverter, contagem intacta", () => {
  for (const code of ["SLOT_NOT_EDITABLE", "PHYSICAL_CARD_NOT_ELIGIBLE", "CARD_ALREADY_PLACED"]) {
    const s = settleEditorOutcome({ kind: "undo", cardName: "Pikachu" }, { ok: false, reason: classifyEditorFailure("P0001", code) }, new Map());
    assert.equal(s.revert, null, code);
    assert.equal(s.filledDelta, 0, code);
    assert.equal(s.toast.tone, "error", code);
    assert.ok(!s.toast.text.includes("Pikachu"), `${code}: a falha não cita a carta nem o bolso`);
  }
});

test("lista vazia: 'Tudo no lugar' só com a curadoria comprovada; antes, texto neutro (barreira fechada não vira 'nada a colocar')", () => {
  const confirmed = placeableEmptyState(true);
  assert.equal(confirmed.title, "Tudo no lugar");
  const neutral = placeableEmptyState(false);
  assert.notEqual(neutral.title, "Tudo no lugar");
  const text = `${neutral.title} ${neutral.text}`.toLowerCase();
  for (const banned of ["tudo no lugar", "já estão", "barreira", "bloque", "permiss", "titular", "local", "acervo"]) assert.ok(!text.includes(banned), banned);
});
