import assert from "node:assert/strict";
import { test } from "node:test";
import {
  STORAGE_NAME_MAX,
  normalizeStorageName,
  storageCardCountLabel,
  storageDeleteBlock,
  storageDeleteBlockMessage,
  storageFailureFromError,
  storageFailureMessage,
  storageLocationFacts,
  toStorageLocation,
} from "./storage-locations.ts";

test("normalizeStorageName: apara, recusa vazio e acima de 60 (mesma regra da 5213/5216/5217)", () => {
  assert.equal(normalizeStorageName("  Caixa azul  "), "Caixa azul");
  assert.equal(normalizeStorageName("   "), null);
  assert.equal(normalizeStorageName(""), null);
  assert.equal(normalizeStorageName("a".repeat(STORAGE_NAME_MAX)), "a".repeat(STORAGE_NAME_MAX));
  assert.equal(normalizeStorageName("a".repeat(STORAGE_NAME_MAX + 1)), null);
  assert.equal(normalizeStorageName(`  ${"a".repeat(STORAGE_NAME_MAX)}  `), "a".repeat(STORAGE_NAME_MAX));
});

test("toStorageLocation: converte a linha da 5219 e recusa formato inesperado", () => {
  const row = {
    storage_container_id: "11111111-1111-4111-8111-111111111111",
    name: "Fichário 1",
    kind_code: "BINDER",
    kind_label: "Fichário físico",
    card_count: "12",
    default_collection_count: 1,
    can_delete: false,
  };
  assert.deepEqual(toStorageLocation(row), {
    id: row.storage_container_id,
    name: "Fichário 1",
    kindCode: "BINDER",
    kindLabel: "Fichário físico",
    cardCount: 12,
    defaultCollectionCount: 1,
    canDelete: false,
  });
  assert.equal(toStorageLocation({ ...row, storage_container_id: null }), null);
  assert.equal(toStorageLocation({ ...row, card_count: "x" }), null);
  const noKind = toStorageLocation({ ...row, kind_code: null, kind_label: null, can_delete: true });
  assert.equal(noKind?.kindLabel, null);
  assert.equal(noKind?.canDelete, true);
});

test("contagem e linha de apoio na linguagem do colecionador", () => {
  assert.equal(storageCardCountLabel(0), "Nenhum exemplar");
  assert.equal(storageCardCountLabel(1), "1 exemplar");
  assert.equal(storageCardCountLabel(1248), "1.248 exemplares");
  assert.equal(storageLocationFacts({ kindLabel: "Caixa", cardCount: 3 }), "Caixa · 3 exemplares");
  assert.equal(storageLocationFacts({ kindLabel: null, cardCount: 0 }), "Nenhum exemplar");
});

test("storageDeleteBlock: mesma regra da 5218 (cartas primeiro, depois local padrão)", () => {
  assert.equal(storageDeleteBlock({ cardCount: 0, defaultCollectionCount: 0 }), null);
  assert.equal(storageDeleteBlock({ cardCount: 2, defaultCollectionCount: 1 }), "has_cards");
  assert.equal(storageDeleteBlock({ cardCount: 0, defaultCollectionCount: 1 }), "collection_default");
  assert.match(storageDeleteBlockMessage("has_cards", { cardCount: 2, defaultCollectionCount: 0 }), /2 exemplares/);
  assert.match(storageDeleteBlockMessage("collection_default", { cardCount: 0, defaultCollectionCount: 1 }), /de uma coleção/);
  assert.match(storageDeleteBlockMessage("collection_default", { cardCount: 0, defaultCollectionCount: 3 }), /de 3 coleções/);
});

test("storageFailureFromError: códigos das funções → motivo; desconhecido → indisponível", () => {
  assert.equal(storageFailureFromError({ message: "STORAGE_HAS_CARDS" }), "has_cards");
  assert.equal(storageFailureFromError({ message: "STORAGE_IS_COLLECTION_DEFAULT" }), "collection_default");
  assert.equal(storageFailureFromError({ message: "STORAGE_IN_USE" }), "in_use");
  assert.equal(storageFailureFromError({ message: "STORAGE_NOT_FOUND" }), "not_found");
  assert.equal(storageFailureFromError({ message: "INVALID_NAME" }), "invalid_name");
  assert.equal(storageFailureFromError({ message: "INVALID_KIND" }), "invalid_kind");
  assert.equal(storageFailureFromError({ message: "IDEMPOTENCY_KEY_REUSED" }), "idempotency_reused");
  assert.equal(storageFailureFromError({ message: "not_authenticated" }), "not_authenticated");
  assert.equal(storageFailureFromError({ message: "algo inesperado" }), "unavailable");
  assert.equal(storageFailureFromError(null), "unavailable");
  for (const reason of ["has_cards", "collection_default", "in_use", "not_found", "invalid_name", "unavailable"] as const) {
    const text = storageFailureMessage(reason);
    assert.ok(text.length > 0);
    assert.doesNotMatch(text, /STORAGE|Inventory|container|UUID/i);
  }
});
