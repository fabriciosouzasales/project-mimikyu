import assert from "node:assert/strict";
import { test } from "node:test";
import {
  STORAGE_BATCH_MAX,
  alreadyAtTarget,
  copyStorageFailureFromError,
  copyStorageFailureMessage,
  copyStorageLabel,
  normalizeStorageBatch,
  storageAssignConfirmation,
  storageAssignSuccess,
} from "./copy-storage.ts";

const A = "11111111-1111-4111-8111-111111111111";
const B = "22222222-2222-4222-8222-222222222222";

test("normalizeStorageBatch: deduplica, recusa vazio, inválido e acima de 500 (teto sobre o array recebido)", () => {
  assert.deepEqual(normalizeStorageBatch([A, A, B]), [A, B]);
  assert.equal(normalizeStorageBatch([]), null);
  assert.equal(normalizeStorageBatch(null), null);
  assert.equal(normalizeStorageBatch([A, "x"]), null);
  assert.equal(normalizeStorageBatch(Array(STORAGE_BATCH_MAX).fill(A))?.length, 1);
  assert.equal(normalizeStorageBatch(Array(STORAGE_BATCH_MAX + 1).fill(A)), null);
});

test("copyStorageFailureFromError: mensagens canônicas da 5024 e FK", () => {
  assert.equal(copyStorageFailureFromError({ message: "authentication required" }), "not_authenticated");
  assert.equal(copyStorageFailureFromError({ message: "lote excede o limite de 500 itens por chamada" }), "too_many");
  assert.equal(copyStorageFailureFromError({ message: "storage container not found" }), "storage_gone");
  assert.equal(copyStorageFailureFromError({ message: "storage container does not belong to caller inventory" }), "storage_gone");
  assert.equal(copyStorageFailureFromError({ code: "23503", message: "insert or update violates foreign key" }), "storage_gone");
  assert.equal(
    copyStorageFailureFromError({ message: "um ou mais physical_card_ids não pertencem ao inventory do chamador" }),
    "copies_gone",
  );
  assert.equal(copyStorageFailureFromError({ message: "p_physical_card_ids não pode ser vazio" }), "invalid");
  assert.equal(copyStorageFailureFromError({ message: "outra coisa" }), "unavailable");
  assert.equal(copyStorageFailureFromError(null), "unavailable");
  for (const reason of ["not_authenticated", "invalid", "too_many", "storage_gone", "copies_gone", "unavailable"] as const) {
    assert.doesNotMatch(copyStorageFailureMessage(reason), /physical_card|inventory|container|UUID/i);
  }
});

test("alreadyAtTarget e rótulo: compara por id do local, nunca por nome", () => {
  const byCopy = { [A]: "loc-1", [B]: null };
  assert.equal(alreadyAtTarget([A, B], byCopy, "loc-1"), 1);
  assert.equal(alreadyAtTarget([A, B], byCopy, null), 1);
  assert.equal(alreadyAtTarget([B], byCopy, "loc-2"), 0);
  assert.equal(copyStorageLabel(null), "Sem localização definida");
  assert.equal(copyStorageLabel("Caixa"), "Caixa");
});

test("storageAssignConfirmation: sempre pede confirmação (NS-13) e distingue local padrão de coleção", () => {
  const one = storageAssignConfirmation({ count: 1, targetName: "Local padrão", targetDefaultCollectionCount: 2 });
  assert.match(one.title, /Guardar 1 exemplar em “Local padrão”/);
  assert.match(one.body, /fisicamente/);
  assert.match(one.note ?? "", /local padrão de 2 coleções/);
  const plain = storageAssignConfirmation({ count: 3, targetName: "Caixa", targetDefaultCollectionCount: 0 });
  assert.equal(plain.note, null);
  assert.match(plain.body, /estes exemplares estão/);
  const clear = storageAssignConfirmation({ count: 2, targetName: null, targetDefaultCollectionCount: 0 });
  assert.match(clear.title, /Remover a localização de 2 exemplares/);
  assert.match(clear.body, /Sem localização definida/);
  assert.match(storageAssignSuccess(2, "Caixa"), /2 exemplares guardados em “Caixa”/);
  assert.match(storageAssignSuccess(1, null), /ficou sem localização definida/);
});
