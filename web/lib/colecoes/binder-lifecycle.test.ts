import assert from "node:assert/strict";
import { test } from "node:test";
import {
  binderEnding,
  binderLifecycleMessage,
  classifyBinderLifecycleFailure,
  dismantleRemovals,
  parseDismantlePreview,
  parseDismantleResult,
  transferCandidates,
  transferFailureMessage,
} from "./binder-lifecycle.ts";

const TOKEN = `d1:${"a".repeat(64)}`;
const LAYOUT = "11111111-1111-4111-8111-111111111111";

function row(over: Record<string, unknown> = {}) {
  return {
    collection_id: "c",
    lifecycle_status: "ACTIVE",
    has_binder: true,
    layout_id: LAYOUT,
    grid_columns: 3,
    grid_rows: 3,
    pages_count: 4,
    slots_count: 36,
    locked_count: 2,
    assignments_count: 20,
    reservations_count: 3,
    regions_count: 1,
    dismantle_token: TOKEN,
    guest_count: 0,
    blocked_reason: null,
    images_count: 5,
    ...over,
  };
}

test("parseDismantlePreview lê a linha da 5242 e recusa formato inesperado", () => {
  const p = parseDismantlePreview([row()]);
  assert.ok(p);
  assert.equal(p.pages, 4);
  assert.equal(p.positions, 20);
  assert.equal(p.images, 5);
  assert.equal(p.token, TOKEN);
  assert.equal(parseDismantlePreview([row({ dismantle_token: "x" })]), null);
  assert.equal(parseDismantlePreview([row({ blocked_reason: "OTHER" })]), null);
  assert.equal(parseDismantlePreview([]), null);
  const none = parseDismantlePreview([row({ has_binder: false, layout_id: null, dismantle_token: null, blocked_reason: "COLLECTION_IS_BINDER_GUEST" })]);
  assert.ok(none);
  assert.equal(none.hasBinder, false);
  assert.equal(none.blocked, "is_guest");
});

test("binderEnding: vazio → excluir; com páginas → desmontar; convidadas, convidada e arquivada bloqueiam", () => {
  assert.equal(binderEnding(parseDismantlePreview([row({ pages_count: 0, slots_count: 0 })])!), "delete");
  assert.equal(binderEnding(parseDismantlePreview([row()])!), "dismantle");
  assert.equal(binderEnding(parseDismantlePreview([row({ guest_count: 1, blocked_reason: "BINDER_HAS_GUESTS" })])!), "blocked_guests");
  assert.equal(binderEnding(parseDismantlePreview([row({ lifecycle_status: "ARCHIVED" })])!), "archived");
  assert.equal(
    binderEnding(parseDismantlePreview([row({ has_binder: false, blocked_reason: "COLLECTION_IS_BINDER_GUEST" })])!),
    "blocked_is_guest",
  );
  assert.equal(binderEnding(parseDismantlePreview([row({ has_binder: false })])!), "absent");
});

test("dismantleRemovals lista só o que existe, com plural correto", () => {
  const all = dismantleRemovals(parseDismantlePreview([row()])!);
  assert.equal(all.length, 6);
  assert.match(all[0] ?? "", /4 páginas e 36 bolsos/);
  const min = dismantleRemovals(parseDismantlePreview([row({ pages_count: 1, slots_count: 9, locked_count: 0, assignments_count: 0, reservations_count: 0, regions_count: 0, images_count: 0 })])!);
  assert.deepEqual(min, ["1 página e 9 bolsos"]);
});

test("parseDismantleResult devolve caminhos das imagens", () => {
  const r = parseDismantleResult([{ outcome: "DISMANTLED", pages_removed: 4, assignments_removed: 20, images_removed: 2, image_paths: ["a/1.webp", "a/2.webp"] }]);
  assert.ok(r);
  assert.deepEqual(r.imagePaths, ["a/1.webp", "a/2.webp"]);
  assert.equal(parseDismantleResult([{ outcome: "X" }]), null);
});

test("classifyBinderLifecycleFailure cobre 5293/5294", () => {
  assert.equal(classifyBinderLifecycleFailure("P0001", "BINDER_HAS_GUESTS"), "has_guests");
  assert.equal(classifyBinderLifecycleFailure("23503", "update or delete violates foreign key"), "has_guests");
  assert.equal(classifyBinderLifecycleFailure("P0001", "DISMANTLE_PLAN_CHANGED"), "plan_changed");
  assert.equal(classifyBinderLifecycleFailure("P0001", "layout has 2 page(s) — remove all pages before deleting the layout"), "has_pages");
  assert.equal(classifyBinderLifecycleFailure("P0001", "collection is ARCHIVED — reactivate it before editing the layout"), "archived");
  assert.equal(classifyBinderLifecycleFailure("P0001", "collection layout not found or not owned by caller"), "not_found");
  assert.equal(classifyBinderLifecycleFailure("P0001", "authentication required"), "not_authenticated");
  assert.equal(classifyBinderLifecycleFailure("XX000", "boom"), "unknown");
  assert.match(binderLifecycleMessage("unknown", "dismantle"), /continua como estava/);
});

test("transferCandidates: só ativas, sem fichário próprio, sem ser convidada de outro; convidadas deste primeiro", () => {
  const list = transferCandidates({
    currentCollectionId: "A",
    layoutId: LAYOUT,
    active: [
      { id: "A", name: "Atual" },
      { id: "B", name: "Zeta" },
      { id: "C", name: "Dona de outro" },
      { id: "D", name: "Convidada de outro" },
      { id: "E", name: "Convidada deste" },
      { id: "F", name: "Alfa" },
    ],
    binderOwners: new Set(["a", "c"]),
    guestOf: new Map([
      ["d", "22222222-2222-4222-8222-222222222222"],
      ["e", LAYOUT],
    ]),
  });
  assert.deepEqual(
    list.map((c) => c.name),
    ["Convidada deste", "Alfa", "Zeta"],
  );
  assert.equal(list[0]?.sharesThisBinder, true);
  assert.match(transferFailureMessage("target_has_binder"), /fichário próprio/);
});
