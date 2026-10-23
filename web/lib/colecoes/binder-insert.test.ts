// Inserir espaço e imagem em 2 bolsos — regras puras (espelho da proposta 5239–5243).
// Executar: node --experimental-strip-types --test lib/colecoes/binder-insert.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { test } from "node:test";
import {
  GAP_ROW_LIMIT,
  type GapPocket,
  applyCloseGap,
  applyInsertGap,
  gapPreviewMessage,
  isFreePocket,
  planCloseGap,
  planInsertGap,
  readingOrder,
} from "./binder-insert.ts";
import { canMergeRight, clampFocal2, mergeCheckMessage, regionObjectPosition } from "./binder-region.ts";

/** Os 7 modelos de grade (colunas × linhas), 5228. */
const GRIDS: Array<[number, number]> = [
  [2, 2],
  [3, 3],
  [3, 4],
  [4, 3],
  [4, 4],
  [4, 5],
  [5, 4],
];

type Fill = Partial<Pick<GapPocket, "locked" | "inRegion" | "hasCard" | "hasReservation" | "hasImage">>;

function binder(cols: number, rows: number, pages: number, fill: (page: number, index: number) => Fill = () => ({ hasCard: true })): GapPocket[] {
  const out: GapPocket[] = [];
  for (let p = 1; p <= pages; p += 1) {
    let i = 0;
    for (let r = 1; r <= rows; r += 1) {
      for (let c = 1; c <= cols; c += 1) {
        out.push({
          slotId: `p${p}r${r}c${c}`,
          pageNumber: p,
          row: r,
          column: c,
          locked: false,
          inRegion: false,
          hasCard: false,
          hasReservation: false,
          hasImage: false,
          ...fill(p, i),
        });
        i += 1;
      }
    }
  }
  return out;
}

function newPage(cols: number, rows: number, page: number): GapPocket[] {
  return binder(cols, rows, 1, () => ({})).map((p) => ({ ...p, slotId: p.slotId.replace("p1", `p${page}`), pageNumber: page }));
}

/** Assinatura de conteúdo em ordem de leitura: C carta, R reserva, I imagem, . livre, # barreira. */
function sig(pockets: GapPocket[]): string {
  return readingOrder(pockets)
    .map((p) => (p.locked || p.inRegion ? "#" : p.hasCard ? "C" : p.hasReservation ? "R" : p.hasImage ? "I" : "."))
    .join("");
}

test("mesma página: o bolso livre mais próximo absorve o deslocamento", () => {
  const b = binder(3, 3, 2, (p, i) => (p === 1 && i === 5 ? {} : { hasCard: true }));
  const plan = planInsertGap(b, "p1r1c2");
  assert.equal(plan.kind, "SAME_PAGE");
  if (plan.kind !== "SAME_PAGE") return;
  assert.equal(plan.targetSlotId, "p1r2c3");
  assert.equal(plan.moves.length, 4);
  assert.deepEqual(plan.pages, [1]);
  const after = applyInsertGap(b, plan);
  assert.equal(sig(after).slice(0, 9), "C.CCCCCCC");
  assert.equal(after.filter((p) => p.hasCard).length, b.filter((p) => p.hasCard).length, "nenhuma carta criada ou perdida");
});

test("o bolso inteiro anda junto: carta, reserva e imagem preservadas", () => {
  const b = binder(3, 3, 1, (_p, i) => (i === 0 ? { hasCard: true } : i === 1 ? { hasReservation: true } : i === 2 ? { hasImage: true } : {}));
  const plan = planInsertGap(b, "p1r1c1");
  assert.equal(plan.kind, "SAME_PAGE");
  if (plan.kind !== "SAME_PAGE") return;
  assert.equal(plan.rows, 3);
  assert.deepEqual([plan.cards, plan.reservations, plan.images], [1, 1, 1]);
  assert.equal(sig(applyInsertGap(b, plan)), ".CRI.....");
});

test("atravessa página quando não há livre na mesma: CROSS_PAGE com páginas envolvidas", () => {
  const b = binder(2, 2, 3, (p, i) => (p === 3 && i === 1 ? {} : { hasCard: true }));
  const plan = planInsertGap(b, "p1r2c1");
  assert.equal(plan.kind, "CROSS_PAGE");
  if (plan.kind !== "CROSS_PAGE") return;
  assert.deepEqual(plan.pages, [1, 2, 3]);
  assert.equal(plan.moves.length, 7);
  assert.match(gapPreviewMessage(plan), /7 bolsos avançam uma posição, nas páginas 1, 2, 3/);
});

test("barreira fixada: não atravessa; informa onde está", () => {
  const b = binder(4, 3, 1, (_p, i) => (i === 3 ? { locked: true, hasCard: true } : i === 6 ? {} : { hasCard: true }));
  const plan = planInsertGap(b, "p1r1c1");
  assert.equal(plan.kind, "BLOCKED");
  if (plan.kind !== "BLOCKED") return;
  assert.equal(plan.barrier.kind, "LOCKED");
  assert.equal(plan.barrier.slotId, "p1r1c4");
  assert.match(gapPreviewMessage(plan), /bolso fixado \(página 1, linha 1, coluna 4\)/);
  assert.throws(() => applyInsertGap(b, plan), /não executável/);
});

test("barreira de mesclagem, inclusive a parte direita", () => {
  const b = binder(4, 3, 1, (_p, i) => (i === 2 || i === 3 ? { inRegion: true } : { hasCard: true }));
  const plan = planInsertGap(b, "p1r1c1");
  assert.equal(plan.kind, "BLOCKED");
  if (plan.kind === "BLOCKED") assert.equal(plan.barrier.kind, "REGION");
});

test("livre antes da barreira: a barreira nunca é tocada", () => {
  const b = binder(4, 3, 1, (_p, i) => (i === 2 ? {} : i === 3 ? { locked: true, hasCard: true } : { hasCard: true }));
  const plan = planInsertGap(b, "p1r1c1");
  assert.equal(plan.kind, "SAME_PAGE");
  if (plan.kind !== "SAME_PAGE") return;
  assert.ok(plan.moves.every((m) => m.from !== "p1r1c4" && m.to !== "p1r1c4"));
});

test("bolso inicial fixado, mesclado ou já livre", () => {
  const b = binder(3, 3, 1, (_p, i) => (i === 0 ? { locked: true } : i === 1 ? { inRegion: true } : i === 2 ? {} : { hasCard: true }));
  assert.equal(planInsertGap(b, "p1r1c1").kind, "AT_BARRIER");
  assert.equal(planInsertGap(b, "p1r1c2").kind, "AT_BARRIER");
  assert.equal(planInsertGap(b, "p1r1c3").kind, "ALREADY_FREE");
  assert.equal(planInsertGap(b, "nao-existe").kind, "NOT_FOUND");
});

test("sem livre até o fim: NEEDS_PAGE (exige confirmação) e a página nova recebe o último", () => {
  for (const [cols, rows] of GRIDS) {
    const b = binder(cols, rows, 2);
    const plan = planInsertGap(b, "p2r1c1");
    assert.equal(plan.kind, "NEEDS_PAGE", `${cols}x${rows}`);
    if (plan.kind !== "NEEDS_PAGE") continue;
    assert.deepEqual(plan.pages, [2, 3]);
    const after = applyInsertGap(b, plan, newPage(cols, rows, 3));
    const ord = readingOrder(after);
    assert.equal(ord.length, cols * rows * 3);
    assert.ok(isFreePocket(ord.find((p) => p.slotId === "p2r1c1")!));
    assert.ok(ord.find((p) => p.slotId === "p3r1c1")!.hasCard, "último bolso foi para a 1ª posição da página nova");
    assert.equal(after.filter((p) => p.hasCard).length, cols * rows * 2);
  }
});

test("os 7 modelos de grade: inserir no começo e desfazer devolve o estado original", () => {
  for (const [cols, rows] of GRIDS) {
    const n = cols * rows;
    const b = binder(cols, rows, 3, (p, i) => (p === 3 && i === n - 1 ? {} : i % 5 === 1 ? { hasReservation: true } : i % 7 === 3 ? { hasImage: true } : { hasCard: true }));
    const before = sig(b);
    const plan = planInsertGap(b, "p1r1c1");
    assert.equal(plan.kind, "CROSS_PAGE", `${cols}x${rows}`);
    if (plan.kind !== "CROSS_PAGE") continue;
    const after = applyInsertGap(b, plan);
    assert.equal(sig(after), "." + before.slice(0, -1), `${cols}x${rows}: deslocamento de uma posição`);
    const close = planCloseGap(after, "p1r1c1", plan.targetSlotId);
    assert.ok(close);
    assert.equal(sig(applyCloseGap(after, close!)), before, `${cols}x${rows}: desfazer restaura`);
  }
});

test("limite operacional: linhas movidas acima de 500 são recusadas", () => {
  // 5x4 = 20 por página; 30 páginas cheias = 600 cartas antes do 1º livre.
  const b = binder(5, 4, 31, (p, i) => (p === 31 && i === 0 ? {} : { hasCard: true }));
  const plan = planInsertGap(b, "p1r1c1");
  assert.equal(plan.kind, "OVER_LIMIT");
  if (plan.kind === "OVER_LIMIT") {
    assert.equal(plan.limit, GAP_ROW_LIMIT);
    assert.equal(plan.rows, 600);
  }
  // Exatamente 500 linhas passa.
  const ok = binder(5, 4, 26, (p, i) => (p === 26 && i === 0 ? {} : { hasCard: true }));
  assert.equal(planInsertGap(ok, "p1r1c1").kind, "CROSS_PAGE");
});

test("desfazer recusa se o espaço não está mais livre ou há barreira no caminho", () => {
  const b = binder(3, 3, 1, (_p, i) => (i === 8 ? {} : { hasCard: true }));
  const plan = planInsertGap(b, "p1r1c1");
  assert.equal(plan.kind, "SAME_PAGE");
  if (plan.kind !== "SAME_PAGE") return;
  const after = applyInsertGap(b, plan);
  const filled = after.map((p) => (p.slotId === "p1r1c1" ? { ...p, hasCard: true } : p));
  assert.equal(planCloseGap(filled, "p1r1c1", plan.targetSlotId), null);
  const locked = after.map((p) => (p.slotId === "p1r2c2" ? { ...p, locked: true } : p));
  assert.equal(planCloseGap(locked, "p1r1c1", plan.targetSlotId), null);
});

test("mesclagem: só 2 bolsos livres lado a lado, na mesma linha", () => {
  const b = binder(3, 2, 1, (_p, i) => (i === 1 ? { hasReservation: true } : i === 3 || i === 4 ? {} : { hasCard: true }));
  assert.deepEqual(canMergeRight(b, "p1r2c1"), { ok: true, leftSlotId: "p1r2c1", rightSlotId: "p1r2c2", row: 2, leftColumn: 1 });
  assert.deepEqual(canMergeRight(b, "p1r1c3"), { ok: false, reason: "LAST_COLUMN" }, "nunca quebra linha");
  assert.deepEqual(canMergeRight(b, "p1r1c1"), { ok: false, reason: "LEFT_NOT_FREE" });
  assert.deepEqual(canMergeRight(b, "p1r2c2"), { ok: false, reason: "RIGHT_NOT_FREE" });
  const fixed = b.map((p) => (p.slotId === "p1r2c2" ? { ...p, locked: true } : p));
  assert.equal(canMergeRight(fixed, "p1r2c1").ok, false);
  assert.match(mergeCheckMessage(canMergeRight(b, "p1r2c2")) ?? "", /à direita precisa estar livre/);
});

test("enquadramento em dois eixos", () => {
  assert.deepEqual(clampFocal2(-5, 140), { focalX: 0, focalY: 100 });
  assert.deepEqual(clampFocal2(Number.NaN, 33.4), { focalX: 50, focalY: 33 });
  assert.equal(regionObjectPosition(20, 70), "20% 70%");
});

// ---------------------------------------------------------------------------
// Contrato das RPCs 5240/5241/5243 (respostas do banco → tela)
// ---------------------------------------------------------------------------

import { classifyGapFailure, isPlanToken, isUndoToken, parseGapClose, parseGapInsert, parseGapPreview } from "./binder-insert.ts";
import { classifyRegionFailure, isDefiniteRegionRefusal, parseMergeResult, parseRegionImages, parseSeparateResult, regionCells } from "./binder-region.ts";
import type { BinderPage, BinderSlot } from "./binder.ts";

const H = "a".repeat(64);
const U1 = "11111111-1111-4111-8111-111111111111";
const U2 = "22222222-2222-4222-8222-222222222222";
const PATH = `${U1}/${U2}/${U1}.webp`;

test("prévia: executável exige plan_token válido; barreira chega com posição", () => {
  assert.equal(parseGapPreview([{ outcome: "SAME_PAGE", moved_pockets: 3, pages: [2] }]), null);
  const ok = parseGapPreview([{ outcome: "CROSS_PAGE", moved_pockets: 7, moved_cards: 6, pages: [2, 3], rows_moved: 13, row_limit: 500, plan_token: `g1:${H}` }]);
  assert.equal(ok?.outcome, "CROSS_PAGE");
  assert.deepEqual(ok?.pages, [2, 3]);
  const blocked = parseGapPreview([{ outcome: "BLOCKED", barrier_slot_id: U1, barrier_kind: "LOCKED", barrier_page: 4, barrier_row: 1, barrier_column: 2 }]);
  assert.deepEqual(blocked?.barrier, { slotId: U1, kind: "LOCKED", pageNumber: 4, row: 1, column: 2 });
  assert.equal(parseGapPreview([{ outcome: "WHATEVER" }]), null);
  assert.equal(isPlanToken(`g1:${H}`), true);
  assert.equal(isPlanToken(`u1:${H}`), false);
});

test("inserção e desfazer: INSERTED exige undo_token e fim; CLOSED", () => {
  assert.equal(parseGapInsert([{ outcome: "INSERTED", gap_slot_id: U1, end_slot_id: U2 }]), null);
  const done = parseGapInsert([{ outcome: "INSERTED", gap_slot_id: U1, end_slot_id: U2, undo_token: `u1:${H}`, moved_pockets: 2, pages: [1] }]);
  assert.equal(done?.movedPockets, 2);
  assert.equal(isUndoToken(done?.undoToken), true);
  assert.deepEqual(parseGapInsert([{ outcome: "ALREADY_FREE", gap_slot_id: U1 }])?.outcome, "ALREADY_FREE");
  assert.deepEqual(parseGapClose([{ outcome: "CLOSED", moved_pockets: 2, page_removed: true }]), { movedPockets: 2, pageRemoved: true });
  assert.equal(parseGapClose([{ outcome: "OTHER" }]), null);
});

test("erros do espaço: confirmação usa o hint; função ausente = indisponível", () => {
  assert.equal(classifyGapFailure("P0001", "GAP_CONFIRMATION_REQUIRED", "ADD_PAGE"), "confirm_add_page");
  assert.equal(classifyGapFailure("P0001", "GAP_CONFIRMATION_REQUIRED", "CROSS_PAGE"), "confirm_cross_page");
  assert.equal(classifyGapFailure("40001", "GAP_PLAN_CHANGED"), "plan_changed");
  assert.equal(classifyGapFailure("54000", "GAP_OVER_LIMIT"), "over_limit");
  assert.equal(classifyGapFailure("PGRST202", "Could not find the function"), "unavailable");
});

test("mesclagem: contrato e recusas definitivas × incertas", () => {
  const merged = parseMergeResult([{ region_id: U1, left_slot_id: U1, right_slot_id: U2, storage_path: PATH, focal_x: 40, focal_y: 60, operation: "ADDED" }]);
  assert.equal(merged?.focalX, 40);
  assert.equal(parseMergeResult([{ region_id: U1, left_slot_id: U1, right_slot_id: U2, storage_path: "../x.webp", focal_x: 40, focal_y: 60, operation: "ADDED" }]), null);
  assert.deepEqual(parseSeparateResult([{ region_id: U1, outcome: "SEPARATED", previous_path: PATH }]), { regionId: U1, outcome: "SEPARATED", previousPath: PATH });
  assert.equal(classifyRegionFailure("P0001", "SLOTS_NOT_FREE"), "slots_not_free");
  assert.equal(classifyRegionFailure("P0001", "IMAGE_PATH_IN_USE"), "path_in_use");
  assert.equal(isDefiniteRegionRefusal("slots_not_free"), true);
  assert.equal(isDefiniteRegionRefusal("unknown"), false);
  const byPage = parseRegionImages([{ region_id: U1, page_number: 3, top_row: 1, left_column: 2, height: 1, width: 2, storage_path: PATH, focal_x: 50, focal_y: 50 }]);
  assert.equal(byPage?.get(3)?.[0]?.width, 2);
});

test("página com mesclagem: âncora desenha a peça, o vizinho é coberto (mesmo sem imagem lida)", () => {
  const slot = (row: number, column: number, regionId: string | null): BinderSlot => ({
    slotId: `s${row}${column}`,
    row,
    column,
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
    regionId,
  });
  const page = { pageNumber: 1, slots: [slot(1, 1, null), slot(1, 2, "r"), slot(1, 3, "r"), slot(2, 1, null)] } as unknown as BinderPage;
  const cells = regionCells(page);
  assert.equal(cells.anchors.get("s12")?.width, 2);
  assert.equal(cells.anchors.get("s12")?.region, null);
  assert.deepEqual([...cells.covered], ["s13"]);
});
