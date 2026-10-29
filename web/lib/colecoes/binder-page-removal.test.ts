// Remoção segura de páginas — regras puras.
// Executar: node --experimental-strip-types --test lib/colecoes/binder-page-removal.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { test } from "node:test";
import type { BinderPage, BinderSlot } from "./binder.ts";
import {
  MIN_BINDER_PAGES,
  anchorAfterPageRemoval,
  cacheAfterPageRemoval,
  checkPageRemoval,
  classifyPageRemovalFailure,
  pageRemovalBlockers,
  pageRemovalFailureMessage,
  pageRemovalRenumbering,
  pageRemovalSummary,
  pageRemovedMessage,
} from "./binder-page-removal.ts";

function slot(id: string, over: Partial<BinderSlot> = {}): BinderSlot {
  return {
    slotId: id,
    row: 1,
    column: 1,
    locked: false,
    state: "EMPTY",
    expected: null,
    present: null,
    assignmentId: null,
    allocationId: null,
    physicalCardId: null,
    expectedCardId: null,
    presentCardId: null,
    presentVariantTypeId: null,
    presentCollectionId: null,
    expectedCollectionId: null,
    ...over,
  };
}

function page(n: number, slots: BinderSlot[] = [slot(`s${n}a`), slot(`s${n}b`)], regions: BinderPage["regions"] = undefined): BinderPage {
  return { pageNumber: n, pageId: `p${n}`, slots, regions };
}

test("página realmente vazia é elegível (com mais de uma página)", () => {
  assert.deepEqual(checkPageRemoval(page(3), 5), { ok: true });
  assert.deepEqual(pageRemovalBlockers(page(3), 5), []);
});

test("mínimo de páginas: a única página nunca é removível", () => {
  assert.equal(MIN_BINDER_PAGES, 1);
  assert.deepEqual(pageRemovalBlockers(page(1), 1), ["last_page"]);
  assert.deepEqual(pageRemovalBlockers(page(1), 0), ["last_page"]);
});

test("carta bloqueia — mesmo que o estado visual pareça vazio (assignment/exemplar presentes)", () => {
  assert.deepEqual(pageRemovalBlockers(page(2, [slot("a", { state: "OCCUPIED_MATCH", presentCardId: "c" })]), 4), ["cards"]);
  // Aparência "EMPTY" mas com vínculo de exemplar: dados mandam, não a aparência.
  assert.deepEqual(pageRemovalBlockers(page(2, [slot("a", { assignmentId: "x" })]), 4), ["cards"]);
  assert.deepEqual(pageRemovalBlockers(page(2, [slot("a", { physicalCardId: "pc" })]), 4), ["cards"]);
});

test("reserva, imagem, imagem em 2 bolsos, fixação e referência de espécie bloqueiam", () => {
  assert.deepEqual(pageRemovalBlockers(page(2, [slot("a", { state: "RESERVED_EMPTY", expectedCardId: "c" })]), 4), ["reservations"]);
  assert.deepEqual(pageRemovalBlockers(page(2, [slot("a", { expectedCardId: "c" })]), 4), ["reservations"]);
  assert.deepEqual(
    pageRemovalBlockers(page(2, [slot("a", { image: { path: "x", url: "u", focalY: 50, updatedAt: "t" } as unknown as BinderSlot["image"] })]), 4),
    ["images"],
  );
  assert.deepEqual(pageRemovalBlockers(page(2, [slot("a", { regionId: "r" })]), 4), ["regions"]);
  assert.deepEqual(pageRemovalBlockers(page(2, [slot("a")], [{ regionId: "r" } as NonNullable<BinderPage["regions"]>[number]]), 4), ["regions"]);
  assert.deepEqual(pageRemovalBlockers(page(2, [slot("a", { locked: true })]), 4), ["locked"]);
  assert.deepEqual(pageRemovalBlockers(page(2, [slot("a", { speciesRef: { speciesId: "x" } as unknown as BinderSlot["speciesRef"] })]), 4), ["species"]);
});

test("vários motivos: ordem estável e sem repetição", () => {
  const p = page(2, [
    slot("a", { locked: true, state: "OCCUPIED_UNPLANNED", presentCardId: "c" }),
    slot("b", { state: "RESERVED_EMPTY", expectedCardId: "d", locked: true }),
    slot("c", { state: "OCCUPIED_MISMATCH", presentCardId: "e" }),
  ]);
  assert.deepEqual(pageRemovalBlockers(p, 1), ["last_page", "cards", "reservations", "locked"]);
  assert.match(pageRemovalSummary(pageRemovalBlockers(p, 1)), /única página.*\(\+3 motivos\)/);
  assert.equal(pageRemovalSummary([]), "Página vazia — pode ser removida.");
});

test("renumeração posterior: as seguintes descem uma posição", () => {
  assert.deepEqual(pageRemovalRenumbering(3, 10), { from: 4, to: 10 });
  assert.equal(pageRemovalRenumbering(10, 10), null);
  assert.equal(pageRemovedMessage(3, 10), "Página 3 removida. As páginas 4–10 passaram a ser 3–9.");
  assert.equal(pageRemovedMessage(10, 10), "Página 10 removida.");
});

test("cache depois da remoção: tira a página e renumera as seguintes sem mutar", () => {
  const cache = new Map<number, BinderPage>([1, 2, 3, 4, 6].map((n) => [n, page(n)]));
  const before = [...cache.keys()];
  const next = cacheAfterPageRemoval(cache, 3);
  assert.deepEqual([...next.keys()].sort((a, b) => a - b), [1, 2, 3, 5]);
  assert.equal(next.get(3)?.pageId, "p4");
  assert.equal(next.get(3)?.pageNumber, 3);
  assert.equal(next.get(5)?.pageId, "p6");
  assert.equal(next.get(2), cache.get(2)); // anteriores intactas (mesma referência)
  assert.deepEqual([...cache.keys()], before); // original não muda
  assert.equal(cache.get(4)?.pageNumber, 4);
});

test("âncora depois da remoção", () => {
  assert.equal(anchorAfterPageRemoval(5, 3, 9), 4);
  assert.equal(anchorAfterPageRemoval(3, 3, 9), 3);
  assert.equal(anchorAfterPageRemoval(2, 3, 9), 2);
  assert.equal(anchorAfterPageRemoval(10, 10, 9), 9);
  assert.equal(anchorAfterPageRemoval(1, 1, 1), 1);
});

test("falhas do banco → motivo estável (texto real de remove_layout_page / 5122)", () => {
  assert.deepEqual(classifyPageRemovalFailure("P0001", "page has 2 slot assignment(s) — remove them before deleting the page"), { reason: "blocked", blocker: "cards" });
  assert.deepEqual(classifyPageRemovalFailure("P0001", "page has 1 expected content entr(y/ies) — clear them before deleting the page"), { reason: "blocked", blocker: "reservations" });
  assert.deepEqual(classifyPageRemovalFailure("P0001", "page has 1 layout region(s) — unmerge them before deleting the page"), { reason: "blocked", blocker: "regions" });
  assert.deepEqual(classifyPageRemovalFailure("P0001", "page has 1 custom image(s) — remove them before deleting the page"), { reason: "blocked", blocker: "images" });
  assert.deepEqual(
    classifyPageRemovalFailure("P0001", "page has 3 species reference(s) — confirm their removal before deleting the page", "SPECIES_REFERENCES_ON_PAGE:3"),
    { reason: "blocked", blocker: "species" },
  );
  // 5286 (hardening no banco)
  assert.deepEqual(classifyPageRemovalFailure("P0001", "layout has only 1 page(s) — a binder must keep at least one page"), { reason: "blocked", blocker: "last_page" });
  assert.deepEqual(classifyPageRemovalFailure("P0001", "page has 2 locked slot(s) — unlock them before deleting the page"), { reason: "blocked", blocker: "locked" });
  assert.deepEqual(classifyPageRemovalFailure("P0001", "layout page not found or not owned by caller"), { reason: "stale" });
  assert.deepEqual(classifyPageRemovalFailure("P0001", "collection is ARCHIVED — reactivate it before editing the layout"), { reason: "archived" });
  assert.deepEqual(classifyPageRemovalFailure("55P03", "canceling statement due to lock timeout"), { reason: "lock_busy" });
  assert.deepEqual(classifyPageRemovalFailure("P0001", "authentication required"), { reason: "not_authenticated" });
  assert.deepEqual(classifyPageRemovalFailure("XX000", "boom"), { reason: "unknown" });
});

test("mensagens dizem o que aconteceu e o que fazer", () => {
  assert.match(pageRemovalFailureMessage("blocked", ["locked"]), /fixados/);
  assert.match(pageRemovalFailureMessage("unknown"), /Nada foi alterado/);
  assert.match(pageRemovalFailureMessage("stale"), /mudou/);
});
