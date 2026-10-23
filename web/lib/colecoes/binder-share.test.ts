// Fichário compartilhado (P2-SHARED-BINDER-FRONTEND-01) — regras puras.
// Executar: node --experimental-strip-types --test lib/colecoes/binder-share.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { test } from "node:test";
import { type BinderSlot, applyMove, applyReserveCurrent, canJoinExistingBinder, isSharedBinder, parseBinderHeader, parseBinderPages } from "./binder.ts";
import {
  applyPlaceAvailable,
  canReceiveAvailable,
  classifyShareFailure,
  isAddablePocket,
  placementSources,
  isForeignSlot,
  mergeAvailable,
  parseAttachOutcome,
  parseAvailableCards,
  parseDetachPreview,
  parseDetachResult,
  parseJoinCandidates,
  shareFailureMessage,
} from "./binder-share.ts";

const A = "11111111-1111-4111-8111-111111111111";
const B = "22222222-2222-4222-8222-222222222222";
const L = "33333333-3333-4333-8333-333333333333";
const S = "44444444-4444-4444-8444-444444444444";
const P = "55555555-5555-4555-8555-555555555555";
const C = "66666666-6666-4666-8666-666666666666";
const TOKEN = `g1:${"a".repeat(64)}`;

const baseHeader = {
  collection_id: B,
  collection_name: "Coleção Clássica",
  collection_kind: "SET",
  lifecycle_status: "ACTIVE",
  has_binder: false,
  layout_id: null,
  grid_columns: null,
  grid_rows: null,
  page_count: 0,
  slot_count: 0,
  filled_count: 0,
  reserved_count: 0,
  reserved_empty_count: 0,
  is_editable: false,
  can_create: true,
  default_storage_container_id: S,
  default_storage_name: "F001",
  default_storage_kind_code: "BINDER",
};

test("cabeçalho sem as colunas da 5230 continua legível (compatível com 5223)", () => {
  const h = parseBinderHeader(baseHeader);
  assert.ok(h);
  assert.equal(h.role, null);
  assert.equal(h.joinCandidateCount, 0);
  assert.equal(h.participantCount, 0);
  assert.equal(canJoinExistingBinder(h), false);
});

test("candidata: sem fichário, com fichário no mesmo local → usar o existente primeiro", () => {
  const h = parseBinderHeader({ ...baseHeader, binder_role: null, join_candidate_count: 1, participant_count: 0 });
  assert.ok(h);
  assert.equal(canJoinExistingBinder(h), true);
  assert.equal(canJoinExistingBinder({ ...h, active: false }), false);
});

test("convidada: papel GUEST, proprietária e contagens próprias", () => {
  const h = parseBinderHeader({
    ...baseHeader,
    has_binder: true,
    layout_id: L,
    grid_columns: 3,
    grid_rows: 3,
    page_count: 18,
    filled_count: 148,
    is_editable: true,
    can_create: false,
    binder_role: "GUEST",
    owner_collection_id: A,
    owner_collection_name: "Celebração de 30 Anos",
    participant_count: 2,
    own_filled_count: 0,
    own_unplaced_count: 7,
    join_candidate_count: 3,
  });
  assert.ok(h);
  assert.equal(h.role, "GUEST");
  assert.equal(h.ownerCollectionName, "Celebração de 30 Anos");
  assert.equal(h.ownUnplacedCount, 7);
  assert.equal(h.joinCandidateCount, 0, "com fichário, candidatos não contam");
  assert.equal(isSharedBinder(h), true);
});

test("bolsos: coleção da carta e da reserva vêm da 5230", () => {
  const pages = parseBinderPages([
    {
      page_id: P,
      page_number: 1,
      slot_id: S,
      row_index: 1,
      column_index: 1,
      locked: false,
      slot_state: "OCCUPIED_MATCH",
      expected_card_id: C,
      expected_card_name: "Pikachu",
      physical_card_id: C,
      present_card_name: "Pikachu",
      present_collection_id: A,
      expected_collection_id: A,
    },
  ]);
  assert.ok(pages);
  assert.equal(pages[0]?.slots[0]?.presentCollectionId, A);
  assert.equal(pages[0]?.slots[0]?.expectedCollectionId, A);
});

function slot(partial: Partial<BinderSlot>): BinderSlot {
  return {
    slotId: S,
    row: 1,
    column: 1,
    locked: false,
    state: "EMPTY",
    expected: null,
    present: null,
    assignmentId: null,
    allocationId: null,
    expectedCardId: null,
    presentCardId: null,
    presentVariantTypeId: null,
    presentCollectionId: null,
    expectedCollectionId: null,
    ...partial,
  };
}

const face = { cardName: "Pikachu", collectorNumber: "1", collectorTotal: 10, setCode: "ME5.5", imagePath: null, finishCode: null, finishName: null };

test("Só desta coleção: carta ou reserva de outra coleção é 'de fora'; vazio nunca", () => {
  assert.equal(isForeignSlot(slot({ state: "EMPTY" }), B), false);
  assert.equal(isForeignSlot(slot({ state: "OCCUPIED_UNPLANNED", present: { ...face, languageCode: null, variantLabel: null }, presentCollectionId: A }), B), true);
  assert.equal(isForeignSlot(slot({ state: "OCCUPIED_UNPLANNED", present: { ...face, languageCode: null, variantLabel: null }, presentCollectionId: B }), B), false);
  assert.equal(isForeignSlot(slot({ state: "RESERVED_EMPTY", expected: face, expectedCardId: C, expectedCollectionId: A }), B), true);
  assert.equal(isForeignSlot(slot({ state: "RESERVED_EMPTY", expected: face, expectedCardId: C, expectedCollectionId: B }), B), false);
});

test("carta disponível só entra em bolso vazio e solto (nunca substitui)", () => {
  assert.equal(canReceiveAvailable(slot({ state: "EMPTY" })), true);
  assert.equal(canReceiveAvailable(slot({ state: "RESERVED_EMPTY" })), true);
  assert.equal(canReceiveAvailable(slot({ state: "EMPTY", locked: true })), false);
  assert.equal(canReceiveAvailable(slot({ state: "OCCUPIED_MATCH" })), false);
});

const card = {
  allocationId: A,
  physicalCardId: C,
  cardId: C,
  variantTypeId: null,
  cardName: "Charizard",
  collectorNumber: "4",
  collectorTotal: 25,
  setCode: "ME5.5CC",
  variantLabel: "Normal",
  languageCode: "pt-BR",
  imagePath: null,
};

test("posicionar: estado otimista leva a coleção e a alocação", () => {
  const next = applyPlaceAvailable(slot({ state: "RESERVED_EMPTY", expected: face, expectedCardId: C }), card, B);
  assert.equal(next.presentCollectionId, B);
  assert.equal(next.allocationId, A);
  assert.equal(next.state, "OCCUPIED_MATCH");
  assert.equal(applyPlaceAvailable(slot({}), card, B).state, "OCCUPIED_UNPLANNED");
});

test("mover leva a coleção junto; reservar a carta atual registra a coleção dela", () => {
  const from = slot({ slotId: "a", state: "OCCUPIED_UNPLANNED", present: { ...face, languageCode: null, variantLabel: null }, presentCardId: C, presentCollectionId: B });
  const to = slot({ slotId: "b" });
  const [nextFrom, nextTo] = applyMove(from, to);
  assert.equal(nextFrom.presentCollectionId, null);
  assert.equal(nextTo.presentCollectionId, B);
  assert.equal(applyReserveCurrent(from).expectedCollectionId, B);
});

test("candidatos: formato válido e rejeição de linha malformada", () => {
  const ok = parseJoinCandidates([
    { layout_id: L, owner_collection_id: A, owner_collection_name: "Celebração de 30 Anos", grid_columns: 3, grid_rows: 3, page_count: 18, free_slot_count: 4, participant_count: 1 },
  ]);
  assert.deepEqual(ok?.[0], { layoutId: L, ownerCollectionId: A, ownerCollectionName: "Celebração de 30 Anos", columns: 3, rows: 3, pageCount: 18, freeSlotCount: 4, participantCount: 1 });
  assert.equal(parseJoinCandidates([{ layout_id: "x" }]), null);
  assert.deepEqual(parseJoinCandidates([]), []);
});

test("associação: só ATTACHED/ALREADY_ATTACHED contam como sucesso", () => {
  assert.equal(parseAttachOutcome([{ outcome: "ATTACHED" }]), "ATTACHED");
  assert.equal(parseAttachOutcome([{ outcome: "ALREADY_ATTACHED" }]), "ALREADY_ATTACHED");
  assert.equal(parseAttachOutcome([]), null);
  assert.equal(parseAttachOutcome([{ outcome: "X" }]), null);
});

test("cartas disponíveis: total e junção sem duplicar", () => {
  const rows = [{ collection_allocation_id: A, physical_card_id: C, card_id: C, card_name: "Charizard", total_count: 7 }];
  const parsed = parseAvailableCards(rows);
  assert.equal(parsed?.total, 7);
  assert.equal(parsed?.items.length, 1);
  assert.deepEqual(parseAvailableCards([]), { items: [], total: 0 });
  assert.equal(parseAvailableCards([{ card_name: "x" }]), null);
  const item = parsed?.items[0];
  assert.ok(item);
  assert.equal(mergeAvailable([item], [item]).length, 1);
});

test("prévia da desassociação: sem linha = não é convidada", () => {
  assert.equal(parseDetachPreview([]), undefined);
  const preview = parseDetachPreview([
    { layout_id: L, owner_collection_id: A, owner_collection_name: "Celebração", assignments_count: 2, reservations_count: 1, locked_count: 0, detach_token: TOKEN },
  ]);
  assert.equal(preview?.assignmentsCount, 2);
  assert.equal(preview?.token, TOKEN);
  assert.equal(parseDetachPreview([{ layout_id: L, owner_collection_id: A, assignments_count: 0, reservations_count: 0, locked_count: 0, detach_token: "bad" }]), null);
  assert.deepEqual(parseDetachResult([{ outcome: "DETACHED", assignments_removed: 2, reservations_removed: 1, locks_released: 0 }]), {
    outcome: "DETACHED",
    assignmentsRemoved: 2,
    reservationsRemoved: 1,
    locksReleased: 0,
  });
  assert.equal(parseDetachResult([{ outcome: "DETACHED" }]), null);
});

test("falhas 5229/5230 → motivo estável com mensagem", () => {
  assert.equal(classifyShareFailure("P0001", "NOT_SAME_LOCATION"), "not_same_location");
  assert.equal(classifyShareFailure("P0001", "DETACH_PLAN_CHANGED"), "plan_changed");
  assert.equal(classifyShareFailure("P0001", "LOCKED_SLOTS_REQUIRE_CONFIRMATION"), "locks_need_confirmation");
  assert.equal(classifyShareFailure("P0002", "BINDER_NOT_FOUND"), "binder_not_found");
  assert.equal(classifyShareFailure("P0002", "COLLECTION_NOT_FOUND"), "not_found");
  assert.equal(classifyShareFailure("55P03", "lock timeout"), "lock_busy");
  assert.equal(classifyShareFailure("22023", "INVALID_DETACH_TOKEN"), "invalid");
  assert.equal(classifyShareFailure("XX000", "boom"), "unknown");
  assert.match(shareFailureMessage("unknown"), /Nada foi alterado/);
});

test("bolso reservado só recebe carta da coleção dona da reserva", () => {
  const reserved = slot({ state: "RESERVED_EMPTY", expected: face, expectedCardId: C, expectedCollectionId: A });
  assert.equal(canReceiveAvailable(reserved, A), true);
  assert.equal(canReceiveAvailable(reserved, B), false);
  assert.equal(canReceiveAvailable(slot({ state: "EMPTY" }), B), true);
  assert.equal(isAddablePocket(reserved), true);
  assert.equal(isAddablePocket(slot({ state: "EMPTY", locked: true })), false);
  assert.equal(isAddablePocket(slot({ state: "OCCUPIED_UNPLANNED" })), false);
});

test("origens das cartas: convidada vê a própria e a da dona; dona e coleção única só a própria", () => {
  const base = { collectionId: B, collectionName: "Clássica", ownerCollectionId: A, ownerCollectionName: "Celebração" };
  assert.deepEqual(placementSources({ ...base, role: "GUEST" }).map((s) => s.collectionId), [B, A]);
  assert.deepEqual(placementSources({ ...base, collectionId: A, role: "OWNER" }).map((s) => s.collectionId), [A]);
  assert.deepEqual(placementSources({ ...base, role: null, ownerCollectionId: null }).map((s) => s.collectionId), [B]);
});
