// Fichário Digital = fichário físico (BINDER-PHYSICAL-LOCATION) — regras puras.
// Executar: node --experimental-strip-types --test lib/colecoes/binder-location.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { test } from "node:test";
import { binderRegisterContext, classifySlotFailure, parseBinderHeader, parseBinderPages, slotFailureMessage, slotFailureNeedsReload } from "./binder.ts";
import {
  NO_BINDER_IMPACT,
  binderImpactSummary,
  binderLockedNotice,
  binderPositionBlock,
  binderUnplaceNotice,
  classifyTransferFailure,
  parseBinderImpact,
  parseTransferOutcome,
} from "./binder-location.ts";
import { copyStorageFailureFromError, copyStorageFailureMessage } from "./copy-storage.ts";
import { moveFailureFromWrite, moveFailureMessage } from "./acervo-move.ts";
import { binderImpactFor, classifyOrganizeFailure, organizeFailureMessage, recoveryFor } from "./collection-organize.ts";

const A = "11111111-1111-4111-8111-111111111111";
const C = "66666666-6666-4666-8666-666666666666";

test("prévias 5249: linha única → impacto; vazio → zero; forma inválida → null", () => {
  assert.deepEqual(parseBinderImpact([{ positioned_count: 2, locked_count: 1 }]), { positioned: 2, locked: 1 });
  assert.deepEqual(parseBinderImpact([{ positioned_count: "3", locked_count: "0" }]), { positioned: 3, locked: 0 });
  assert.deepEqual(parseBinderImpact([]), NO_BINDER_IMPACT);
  assert.equal(parseBinderImpact(null), null);
  assert.equal(parseBinderImpact([{ positioned_count: -1, locked_count: 0 }]), null);
  assert.equal(parseBinderImpact([{ positioned_count: 1 }]), null);
  assert.equal(parseBinderImpact([{}, {}]), null);
});

test("recusas BINDER_POSITION_* são reconhecidas; outros erros não", () => {
  assert.equal(binderPositionBlock({ code: "55000", message: "BINDER_POSITION_CONFIRMATION_REQUIRED" }), "confirm_required");
  assert.equal(binderPositionBlock({ code: "55000", message: "BINDER_POSITION_LOCKED" }), "locked");
  assert.equal(binderPositionBlock({ code: "P0001", message: "PLAN_CHANGED" }), null);
  assert.equal(binderPositionBlock(null), null);
});

test("textos de impacto: singular/plural e ausência quando não há impacto", () => {
  assert.equal(binderUnplaceNotice(0), null);
  assert.match(binderUnplaceNotice(1) ?? "", /^1 exemplar está num bolso do fichário digital e sairá do bolso/);
  assert.match(binderUnplaceNotice(3) ?? "", /^3 exemplares estão .* sairão dos bolsos/);
  assert.equal(binderLockedNotice(0), null);
  assert.match(binderLockedNotice(2) ?? "", /cadeado/);
  assert.equal(binderImpactSummary(NO_BINDER_IMPACT), null);
  assert.equal(binderImpactSummary({ positioned: 2, locked: 0 }), "2 saem dos bolsos");
  assert.match(binderImpactSummary({ positioned: 2, locked: 1 }) ?? "", /fixado/);
});

test("Meu acervo (local do exemplar): recusas do fichário viram motivos próprios", () => {
  assert.equal(copyStorageFailureFromError({ code: "55000", message: "BINDER_POSITION_CONFIRMATION_REQUIRED" }), "binder_positioned");
  assert.equal(copyStorageFailureFromError({ code: "55000", message: "BINDER_POSITION_LOCKED" }), "binder_locked");
  assert.match(copyStorageFailureMessage("binder_positioned"), /nada foi alterado/);
  assert.match(copyStorageFailureMessage("binder_locked"), /cadeado/);
  // Mover em lote: posição nova sem confirmação → nova prévia; cadeado → motivo próprio.
  assert.equal(moveFailureFromWrite({ code: "55000", message: "BINDER_POSITION_CONFIRMATION_REQUIRED" }), "plan_changed");
  assert.equal(moveFailureFromWrite({ code: "55000", message: "BINDER_POSITION_LOCKED" }), "binder_locked");
  assert.match(moveFailureMessage("binder_locked"), /nada foi alterado/);
});

test("Organizar armazenamento (D1): impacto por modalidade e recuperação das recusas", () => {
  const plan = { binder: { UNLOCATED: { positioned: 0, locked: 0 }, ALL: { positioned: 4, locked: 1 } } };
  assert.deepEqual(binderImpactFor(plan, "ALL"), { positioned: 4, locked: 1 });
  assert.deepEqual(binderImpactFor(plan, "UNLOCATED"), NO_BINDER_IMPACT);
  assert.deepEqual(binderImpactFor({}, "ALL"), NO_BINDER_IMPACT);
  assert.equal(classifyOrganizeFailure("55000", "BINDER_POSITION_CONFIRMATION_REQUIRED"), "plan_changed");
  assert.equal(recoveryFor("plan_changed"), "refresh_plan");
  assert.equal(classifyOrganizeFailure("55000", "BINDER_POSITION_LOCKED"), "binder_locked");
  assert.equal(recoveryFor("binder_locked"), "stop");
  assert.match(organizeFailureMessage("binder_locked"), /nada foi movido/);
});

test("posicionar pelo exemplar (5250): mensagens = códigos → motivos estáveis", () => {
  assert.equal(classifySlotFailure("55000", "CARD_NOT_IN_BINDER_LOCATION"), "not_in_location");
  assert.equal(classifySlotFailure("23505", "CARD_ALREADY_PLACED"), "already_placed");
  assert.equal(classifySlotFailure("55000", "SLOT_LOCKED"), "locked");
  assert.equal(classifySlotFailure("P0002", "PHYSICAL_CARD_NOT_FOUND"), "stale");
  assert.equal(classifySlotFailure("55000", "COLLECTION_ARCHIVED"), "archived");
  assert.match(slotFailureMessage("not_in_location"), /Meu acervo/);
  assert.equal(slotFailureNeedsReload("not_in_location"), true);
});

test("cabeçalho 5252: disponíveis de todas as origens; sem a 5252 cai para o contrato antigo", () => {
  const base = { collection_id: A, collection_name: "Celebração", has_binder: true, grid_columns: 3, grid_rows: 3, own_unplaced_count: 2 };
  assert.equal(parseBinderHeader({ ...base, available_count: 27, binder_storage_name: "F001" })?.availableCount, 27);
  assert.equal(parseBinderHeader({ ...base, available_count: 27, binder_storage_name: "F001" })?.binderStorageName, "F001");
  assert.equal(parseBinderHeader(base)?.availableCount, 2);
  assert.equal(parseBinderHeader(base)?.binderStorageName, null);
});

test("cadastro pelo fichário: usa o fichário físico (5247) só quando ele é legível; nunca presume local", () => {
  const base = { collection_id: A, collection_name: "Celebração", has_binder: true, grid_columns: 3, grid_rows: 3, own_unplaced_count: 0 };
  const withStorage = parseBinderHeader({ ...base, collection_kind: "SET", binder_storage_container_id: A, binder_storage_name: "F001" })!;
  assert.equal(withStorage.binderStorageId, A);
  const set = { code: "sv1", name: "Escarlate e Violeta" };
  assert.deepEqual(binderRegisterContext(withStorage, set), { kind: "set", cardSet: set, storage: { id: A, name: "F001" } });
  // Set sem referência legível: ação ausente.
  assert.equal(binderRegisterContext(withStorage, null), null);
  // Sem vínculo físico legível: escolha explícita (storage null), nada presumido.
  const free = parseBinderHeader({ ...base, collection_kind: "FREE" })!;
  assert.deepEqual(binderRegisterContext(free, set), { kind: "free", cardSet: null, storage: null });
  assert.equal(binderRegisterContext(parseBinderHeader({ ...base, collection_kind: "POKEDEX" })!, null)?.kind, "pokedex");
  assert.equal(binderRegisterContext(parseBinderHeader({ ...base, collection_kind: "OTHER" })!, set), null);
});

test("páginas: o bolso guarda o exemplar (posição sem alocação continua válida)", () => {
  const pages = parseBinderPages([
    {
      page_id: A,
      page_number: 1,
      slot_id: C,
      row_index: 1,
      column_index: 1,
      slot_state: "OCCUPIED_UNPLANNED",
      physical_card_id: C,
      collection_allocation_id: null,
      present_card_name: "Mudkip",
    },
  ]);
  const slot = pages?.[0]?.slots[0];
  assert.ok(slot);
  assert.equal(slot.physicalCardId, C);
  assert.equal(slot.allocationId, null);
  assert.equal(slot.present?.cardName, "Mudkip");
});

test("transferência (5254): resultado e falhas", () => {
  assert.deepEqual(parseTransferOutcome([{ outcome: "TRANSFERRED", layout_id: A, reservations_pinned: 3 }]), {
    outcome: "TRANSFERRED",
    layoutId: A,
    reservationsPinned: 3,
  });
  assert.equal(parseTransferOutcome([{ outcome: "UNCHANGED", layout_id: A, reservations_pinned: 0 }])?.outcome, "UNCHANGED");
  assert.equal(parseTransferOutcome([{ outcome: "X", layout_id: A, reservations_pinned: 0 }]), null);
  assert.equal(parseTransferOutcome([]), null);
  assert.equal(classifyTransferFailure("55000", "COLLECTION_ARCHIVED"), "target_archived");
  assert.equal(classifyTransferFailure("55000", "COLLECTION_HAS_OWN_BINDER"), "target_has_binder");
  assert.equal(classifyTransferFailure("55000", "COLLECTION_IS_BINDER_GUEST"), "target_is_guest");
  assert.equal(classifyTransferFailure("P0002", "BINDER_NOT_OWNED"), "not_owner");
  assert.equal(classifyTransferFailure("P0002", "COLLECTION_NOT_FOUND"), "not_found");
  assert.equal(classifyTransferFailure("55P03", "lock"), "lock_busy");
});
