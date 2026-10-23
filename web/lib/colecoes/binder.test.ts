// Fichário Digital (P2-B) — regras puras.
// Executar: node --experimental-strip-types --test lib/colecoes/binder.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { test } from "node:test";
import {
  BINDER_MODELS,
  BINDER_MARGIN,
  BINDER_UNITS,
  binderMargins,
  CARD_ASPECT,
  MIN_SPREAD_POCKET,
  applyClearReservation,
  moveInOrder,
  pageOccupancy,
  sameOrder,
  swapInOrder,
  applyLock,
  applyMove,
  applyRemove,
  applyReserveCurrent,
  binderHref,
  canReserveCurrent,
  deriveSlotState,
  firstPageOfView,
  viewCount,
  viewForPage,
  viewLabel,
  viewSides,
  classifySlotFailure,
  computeBinderFit,
  isOccupied,
  slotFailureNeedsReload,
  clampPage,
  classifyBinderFailure,
  binderEntryVisible,
  createBlocker,
  extrasBreakdown,
  isBinderModelKey,
  modelFor,
  modelLabel,
  parseBinderHeader,
  parseBinderPages,
  parseBinderPreview,
  parsePageParam,
  previewVerdict,
  readBatchStart,
  recoveryForBinder,
  slotDescription,
  spreadLabel,
  spreadPages,
  spreadStart,
} from "./binder.ts";

const TOKEN = `v1:${"a".repeat(64)}`;

test("sete modelos, colunas × linhas", () => {
  assert.deepEqual(
    BINDER_MODELS.map((m) => m.key),
    ["2x2", "3x3", "3x4", "4x3", "4x4", "4x5", "5x4"],
  );
  assert.equal(modelFor(3, 4)?.pockets, 12);
  assert.equal(modelFor(5, 5), null);
  assert.equal(modelLabel(3, 4), "3 × 4");
  assert.equal(isBinderModelKey("5x4"), true);
  assert.equal(isBinderModelKey("5x5"), false);
});

const headerRow = {
  collection_id: "c1",
  collection_name: "Base",
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
  can_create: true,
  default_storage_name: "Fichário azul",
  default_storage_kind_code: "BINDER",
};

test("cabeçalho: parse e bloqueios de criação", () => {
  const h = parseBinderHeader(headerRow);
  assert.ok(h);
  assert.equal(createBlocker(h), null);
  assert.equal(createBlocker({ ...h, canCreate: false, active: false }), "archived");
  assert.equal(createBlocker({ ...h, canCreate: false, defaultStorageKind: null }), "no_default_storage");
  assert.equal(createBlocker({ ...h, canCreate: false, defaultStorageKind: "BOX" }), "storage_not_binder");
  assert.equal(createBlocker({ ...h, canCreate: false, kind: "UNKNOWN" }), "unsupported");
  // Entrada só para coleções guardadas num fichário (ou que já têm fichário digital).
  assert.equal(binderEntryVisible(h), true);
  assert.equal(binderEntryVisible(null), true);
  assert.equal(binderEntryVisible({ ...h, defaultStorageKind: "BOX" }), false);
  assert.equal(binderEntryVisible({ ...h, defaultStorageKind: null }), false);
  assert.equal(binderEntryVisible({ ...h, defaultStorageKind: "BOX", hasBinder: true }), true);
  // Fichário existente exige grade.
  assert.equal(parseBinderHeader({ ...headerRow, has_binder: true }), null);
  assert.equal(parseBinderHeader({ ...headerRow, has_binder: true, grid_columns: 3, grid_rows: 3 })?.columns, 3);
  assert.equal(parseBinderHeader(null), null);
});

function slotRow(page: number, row: number, column: number, state: string, extra: Record<string, unknown> = {}) {
  return { page_id: `p${page}`, page_number: page, slot_id: `s${page}-${row}-${column}`, row_index: row, column_index: column, locked: false, slot_state: state, ...extra };
}

test("páginas: agrupa, ordena e lê reservas e exemplares", () => {
  const pages = parseBinderPages([
    slotRow(2, 1, 1, "EMPTY"),
    slotRow(1, 1, 2, "RESERVED_EMPTY", { expected_card_id: "k", expected_card_name: "Pikachu", expected_collector_number: "25", expected_collector_total: 102 }),
    slotRow(1, 1, 1, "OCCUPIED_MATCH", {
      physical_card_id: "pc",
      present_card_name: "Bulbasaur",
      present_collector_number: "1",
      assignment_id: "as1",
      collection_allocation_id: "al1",
      present_card_id: "card-b",
      present_variant_type_id: "vt-normal",
    }),
  ]);
  assert.ok(pages);
  assert.deepEqual(pages.map((p) => p.pageNumber), [1, 2]);
  const [first] = pages;
  assert.ok(first);
  const [occupied, reserved] = first.slots;
  assert.ok(occupied && reserved);
  assert.deepEqual(first.slots.map((s) => s.column), [1, 2]);
  assert.equal(occupied.present?.cardName, "Bulbasaur");
  assert.equal(occupied.assignmentId, "as1");
  assert.equal(occupied.allocationId, "al1");
  assert.equal(occupied.presentCardId, "card-b");
  assert.equal(occupied.presentVariantTypeId, "vt-normal");
  assert.equal(reserved.expectedCardId, "k");
  assert.equal(isOccupied(occupied), true);
  assert.equal(isOccupied(reserved), false);
  // Já casa com a reserva: nada a reservar. Sem reserva: pode reservar.
  assert.equal(canReserveCurrent(occupied), false);
  assert.equal(canReserveCurrent({ ...occupied, state: "OCCUPIED_UNPLANNED" }), true);
  assert.equal(canReserveCurrent({ ...occupied, state: "OCCUPIED_UNPLANNED", presentCardId: null }), false);
  assert.match(slotDescription(reserved), /reservado para Pikachu, 025\/102/);
  assert.equal(parseBinderPages([slotRow(1, 1, 1, "WHATEVER")]), null);
});

test("spreads e lotes de leitura", () => {
  assert.equal(readBatchStart(1), 1);
  assert.equal(readBatchStart(4), 1);
  assert.equal(readBatchStart(5), 5);
  assert.equal(spreadStart(4, 2), 3);
  assert.equal(spreadStart(5, 2), 5);
  assert.equal(spreadStart(4, 1), 4);
  assert.deepEqual(spreadPages(5, 2, 5), [5]);
  assert.deepEqual(spreadPages(3, 2, 5), [3, 4]);
  assert.equal(spreadLabel([3, 4], 12), "Páginas 3–4 de 12");
  assert.equal(spreadLabel([5], 12), "Página 5 de 12");
  assert.equal(clampPage(99, 12), 12);
  assert.equal(parsePageParam("7", 12), 7);
  assert.equal(parsePageParam("x", 12), 1);
  assert.equal(parsePageParam(["40"], 12), 12);
  assert.equal(binderHref("c1"), "/colecoes/colecoes/c1/fichario");
  assert.equal(binderHref("c1", 3), "/colecoes/colecoes/c1/fichario?pagina=3");
});

const previewRow = {
  collection_id: "c1",
  collection_kind: "MASTER_SET",
  completion_policy: "MASTER_SET",
  lifecycle_active: true,
  binder_exists: false,
  eligible: true,
  grid_columns: 3,
  grid_rows: 3,
  capacity_per_page: 9,
  extra_policy: "APPEND_PAGES",
  too_large: false,
  max_allocations: 10000,
  allocations_total: 40,
  positions_total: 30,
  positions_owned: 20,
  positions_reserved: 10,
  extras_total: 6,
  extras_identical: 3,
  extras_other_language: 2,
  extras_other_variant: 0,
  extras_out_of_objective: 1,
  extras_placed: 6,
  extras_unplaced: 0,
  has_identical_duplicates: true,
  pages_total: 5,
  slots_total: 45,
  slots_empty_trailing: 9,
  sample: [{ row: 1, column: 1, state: "ASSIGNED", card_name: "Pikachu", collector_number: "25", variant_type_code: "NORMAL", image_path: null }],
  plan_token: TOKEN,
};

test("prévia: parse, veredito e adicionais por categoria", () => {
  const p = parseBinderPreview(previewRow);
  assert.ok(p);
  assert.equal(previewVerdict(p), "ready");
  assert.equal(p.sample.length, 1);
  assert.deepEqual(
    extrasBreakdown(p).map((i) => i.key),
    ["out", "identical", "language"],
  );
  assert.equal(previewVerdict({ ...p, eligible: false }), "not_eligible");
  assert.equal(previewVerdict({ ...p, binderExists: true }), "exists");
  assert.equal(previewVerdict({ ...p, active: false }), "archived");
  assert.equal(previewVerdict({ ...p, tooLarge: true }), "too_large");
  // token inválido nunca libera a montagem
  const bad = parseBinderPreview({ ...previewRow, plan_token: "v1:xyz" });
  assert.ok(bad);
  assert.equal(previewVerdict(bad), "unsupported");
  assert.equal(parseBinderPreview({ ...previewRow, extra_policy: "OTHER" }), null);
});

test("erros de domínio → mensagem e recuperação", () => {
  assert.equal(classifyBinderFailure("P0001", "PLAN_CHANGED"), "plan_changed");
  assert.equal(recoveryForBinder("plan_changed"), "refresh_preview");
  assert.equal(classifyBinderFailure("P0001", "LAYOUT_ALREADY_EXISTS"), "already_exists");
  assert.equal(recoveryForBinder("already_exists"), "open_binder");
  assert.equal(classifyBinderFailure("55000", "NOT_ELIGIBLE"), "not_eligible");
  assert.equal(classifyBinderFailure("55000", "COLLECTION_ARCHIVED"), "archived");
  assert.equal(classifyBinderFailure("54000", "COLLECTION_TOO_LARGE"), "too_large");
  assert.equal(classifyBinderFailure("22023", "INVALID_GRID"), "invalid_grid");
  assert.equal(classifyBinderFailure("55P03", "canceling statement due to lock timeout"), "lock_busy");
  assert.equal(recoveryForBinder("lock_busy"), "retry_allowed");
  assert.equal(classifyBinderFailure("P0002", "COLLECTION_NOT_FOUND"), "not_found");
  assert.equal(classifyBinderFailure("28000", "not_authenticated"), "not_authenticated");
  assert.equal(classifyBinderFailure("XX000", "boom"), "unknown");
});

test("encaixe: o fichário inteiro cabe na área, nos sete modelos, sem rolar", () => {
  const areas = [
    [1280, 640, true],
    [1920, 900, true],
    [1024, 560, true],
    [768, 900, false],
    [375, 560, false],
    [320, 480, false],
  ] as const;
  for (const model of BINDER_MODELS) {
    for (const [w, h, spread] of areas) {
      const fit = computeBinderFit(w, h, model.columns, model.rows, spread);
      assert.ok(fit.width <= w && fit.height <= h, `${model.key} em ${w}×${h}: ${fit.width}×${fit.height}`);
      assert.ok(fit.pocket > 0, `${model.key} em ${w}×${h}: bolso ${fit.pocket}`);
      if (!spread) assert.equal(fit.perView, 1);
      // Alguma dimensão encosta no limite (maior fichário possível; arredondamento ≤ 1 px por unidade), salvo o teto do bolso.
      const slack = Math.min(w - fit.width, h - fit.height);
      assert.ok(fit.pocket === 280 || slack <= 24, `${model.key} ${w}×${h} folga ${slack}`);
    }
  }
  // Desktop largo: 4 × 5 e 5 × 4 em duas páginas, bolso legível.
  const a = computeBinderFit(1280, 640, 4, 5, true);
  const b = computeBinderFit(1280, 640, 5, 4, true);
  assert.equal(a.perView, 2);
  assert.equal(b.perView, 2);
  assert.ok(a.pocket >= MIN_SPREAD_POCKET && b.pocket >= MIN_SPREAD_POCKET);
  // Altura manda no 4 × 5: as cinco linhas cabem.
  assert.ok(5 * a.pocket * CARD_ASPECT < 640);
  // Espaço estreito demais para duas páginas legíveis → uma.
  assert.equal(computeBinderFit(700, 300, 5, 4, true).perView, 1);
  assert.equal(BINDER_UNITS.gap > 0, true);
  // Entradas inválidas não quebram.
  assert.equal(computeBinderFit(Number.NaN, -5, 3, 3, true).pocket, 0);
});

test("respiro do couro: proporcional ao bolso, com piso e teto, sem encolher demais as cartas", () => {
  assert.deepEqual(binderMargins(0), { x: 0, y: 0 });
  assert.deepEqual(binderMargins(40), { x: BINDER_MARGIN.x.min, y: BINDER_MARGIN.y.min });
  assert.deepEqual(binderMargins(200), { x: BINDER_MARGIN.x.max, y: BINDER_MARGIN.y.max });
  for (const [w, h, cols, rows, spread] of [
    [1280, 640, 3, 3, true],
    [1280, 640, 4, 5, true],
    [1280, 640, 5, 4, true],
    [375, 560, 3, 3, false],
    [375, 560, 4, 5, false],
    [375, 560, 5, 4, false],
  ] as const) {
    const fit = computeBinderFit(w, h, cols, rows, spread);
    assert.ok(fit.width <= w && fit.height <= h);
    assert.ok(fit.marginX >= BINDER_MARGIN.x.min && fit.marginX <= BINDER_MARGIN.x.max);
    assert.ok(fit.marginY >= BINDER_MARGIN.y.min && fit.marginY <= BINDER_MARGIN.y.max);
    // Sem o respiro o bolso seria no máximo ~8% maior.
    const kw = fit.perView * (cols + (cols - 1) * BINDER_UNITS.gap + 2 * BINDER_UNITS.pagePad) + (fit.perView - 1) * BINDER_UNITS.spine + 2 * BINDER_UNITS.pad;
    const kh = rows * CARD_ASPECT + (rows - 1) * BINDER_UNITS.gap + 2 * BINDER_UNITS.pagePad + 2 * BINDER_UNITS.pad;
    const without = Math.min(w / kw, h / kh, 280);
    assert.ok(fit.pocket >= without * 0.92, `${cols}×${rows} ${w}×${h}: ${fit.pocket} vs ${without.toFixed(1)}`);
  }
});

test("falhas das RPCs de bolso → motivo estável", () => {
  assert.equal(classifySlotFailure("P0001", "Slot de origem e/ou destino bloqueado (locked) — Move/Swap não permitido"), "locked");
  assert.equal(classifySlotFailure("P0001", "2 Slot(s) bloqueado(s) (locked) — Remove/Bandeja não permitido; a operação inteira foi rejeitada"), "locked");
  assert.equal(classifySlotFailure("P0001", "Slot de origem está vazio — nada a mover"), "source_empty");
  assert.equal(classifySlotFailure("P0001", "no-op: Slot de origem e destino são o mesmo"), "noop");
  assert.equal(classifySlotFailure("P0001", "collection is ARCHIVED — reactivate it before editing the layout"), "archived");
  assert.equal(classifySlotFailure("P0001", "layout slot not found or not owned by caller"), "stale");
  assert.equal(classifySlotFailure("P0001", "lote excede o limite de 500 itens por chamada"), "too_many");
  assert.equal(classifySlotFailure("55P03", "lock timeout"), "lock_busy");
  assert.equal(classifySlotFailure("P0001", "authentication required"), "not_authenticated");
  assert.equal(classifySlotFailure("XX000", "boom"), "unknown");
  assert.equal(slotFailureNeedsReload("stale"), true);
  assert.equal(slotFailureNeedsReload("too_many"), false);
});

test("vistas: capa, contracapa + página 1, pares e contracapa traseira", () => {
  // 5 páginas, duas por vista: capa | (contracapa,1) | (2,3) | (4,5)
  assert.equal(viewCount(2, 5), 4);
  assert.deepEqual(viewSides(1, 2, 5), ["inner", 1]);
  assert.deepEqual(viewSides(2, 2, 5), [2, 3]);
  assert.deepEqual(viewSides(3, 2, 5), [4, 5]);
  // 4 páginas: a última cai à esquerda e a contracapa traseira fecha o par.
  assert.equal(viewCount(2, 4), 4);
  assert.deepEqual(viewSides(3, 2, 4), [4, "inner"]);
  assert.equal(viewForPage(1, 2), 1);
  assert.equal(viewForPage(2, 2), 2);
  assert.equal(viewForPage(3, 2), 2);
  assert.equal(viewForPage(4, 2), 3);
  assert.equal(viewForPage(0, 2), 0);
  assert.equal(firstPageOfView(3, 2), 4);
  // Uma por vista: capa e cada página.
  assert.equal(viewCount(1, 5), 6);
  assert.deepEqual(viewSides(5, 1, 5), [5]);
  assert.equal(viewForPage(4, 1), 4);
  // A âncora (página) preserva o lugar ao trocar 2 → 1 → 2.
  assert.equal(viewForPage(firstPageOfView(viewForPage(5, 2), 2), 1), 4);
  assert.equal(viewLabel(0, 2, 5), "Capa");
  assert.equal(viewLabel(1, 2, 5), "Página 1 de 5");
  assert.equal(viewLabel(2, 2, 5), "Páginas 2–3 de 5");
  assert.equal(viewCount(2, 1), 2);
  assert.deepEqual(viewSides(1, 2, 1), ["inner", 1]);
});

test("mudança otimista: mover, trocar, retirar, fixar e reservar", () => {
  const pages = parseBinderPages([
    slotRow(1, 1, 1, "OCCUPIED_MATCH", {
      physical_card_id: "pc1",
      present_card_name: "Pikachu",
      present_card_id: "k1",
      expected_card_id: "k1",
      expected_card_name: "Pikachu",
      assignment_id: "a1",
      collection_allocation_id: "al1",
    }),
    slotRow(1, 1, 2, "EMPTY"),
    slotRow(1, 1, 3, "OCCUPIED_UNPLANNED", { physical_card_id: "pc3", present_card_name: "Eevee", present_card_id: "k3", assignment_id: "a3" }),
  ]);
  assert.ok(pages);
  const [a, b, c] = pages[0]?.slots ?? [];
  assert.ok(a && b && c);
  // Mover para vazio: a origem vira reserva; o destino, carta sem reserva.
  const [a1, b1] = applyMove(a, b);
  assert.equal(a1.state, "RESERVED_EMPTY");
  assert.equal(b1.state, "OCCUPIED_UNPLANNED");
  assert.equal(b1.assignmentId, "a1");
  // Trocar: Eevee vai para o bolso reservado ao Pikachu (diverge).
  const [a2, c2] = applyMove(a, c);
  assert.equal(a2.state, "OCCUPIED_MISMATCH");
  assert.equal(c2.present?.cardName, "Pikachu");
  assert.equal(applyRemove(a).state, "RESERVED_EMPTY");
  assert.equal(applyRemove(c).state, "EMPTY");
  assert.equal(applyLock(c, true).locked, true);
  const reserved = applyReserveCurrent(c);
  assert.equal(reserved.state, "OCCUPIED_MATCH");
  assert.equal(reserved.expected?.cardName, "Eevee");
  assert.equal(applyClearReservation(a).state, "OCCUPIED_UNPLANNED");
  assert.equal(deriveSlotState({ present: null, presentCardId: null, expectedCardId: null }), "EMPTY");
});

test("visão geral: ocupação por página e reordenação local", () => {
  const pages = parseBinderPages([
    slotRow(1, 1, 1, "OCCUPIED_MATCH", { physical_card_id: "pc", present_card_name: "A", expected_card_id: "k", expected_card_name: "A" }),
    slotRow(1, 1, 2, "RESERVED_EMPTY", { expected_card_id: "k2", expected_card_name: "B" }),
    slotRow(1, 1, 3, "EMPTY"),
  ]);
  assert.ok(pages && pages[0]);
  assert.deepEqual(pageOccupancy(pages[0]), { capacity: 3, occupied: 1, reservedMissing: 1, empty: 1, images: 0 });
  assert.deepEqual(moveInOrder(["a", "b", "c"], 0, 1), ["b", "a", "c"]);
  assert.deepEqual(moveInOrder(["a", "b", "c"], 2, 5), ["a", "b", "c"]);
  assert.deepEqual(moveInOrder(["a", "b", "c"], 2, -2), ["c", "a", "b"]);
  assert.deepEqual(swapInOrder(["a", "b", "c"], 0, 2), ["c", "b", "a"]);
  assert.equal(sameOrder(["a"], ["a"]), true);
  assert.equal(sameOrder(["a", "b"], ["b", "a"]), false);
});

test("adicionar páginas: unidade é a página; resumo com folhas e bolsos", async () => {
  const { addPagesSummary, addPagesResultMessage, ADD_PAGES_MAX } = await import("./binder.ts");
  const two = addPagesSummary(2, 3, 3, 18);
  assert.equal(two.totalAfter, 20);
  assert.equal(two.slotsAdded, 18);
  assert.match(two.sheetsLabel, /1 folha/);
  assert.match(addPagesSummary(1, 3, 3, 18).sheetsLabel, /meia folha/);
  assert.match(addPagesSummary(3, 3, 3, 18).sheetsLabel, /1 folha e meia/);
  assert.equal(addPagesSummary(99, 3, 3, 0).count, ADD_PAGES_MAX);
  assert.equal(addPagesSummary(0, 3, 3, 0).count, 1);
  assert.match(addPagesResultMessage(2, 2, 9), /^2 páginas novas.*18 bolsos/);
  assert.match(addPagesResultMessage(1, 3, 9), /^Entraram 1 de 3/);
});
