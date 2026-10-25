import { test } from "node:test";
import assert from "node:assert/strict";
import {
  affectedPages,
  applyResultMessage,
  blockingItemKeys,
  canApplyPreview,
  catalogFailureMessage,
  classifyCatalogFailure,
  failureNeedsFreshPreview,
  isCatalogPlanToken,
  mayHaveCatalogNovelties,
  noveltyBadgeCount,
  noveltyLabel,
  parseCatalogApply,
  parseCatalogNovelties,
  parseCatalogPreview,
  planItemMessage,
  previewSummaryMessage,
  requiredConfirmations,
  selectionKeys,
} from "./binder-catalog.ts";

// Caso real de homologação (LIVE_90 Q90.7/Q90.8, 2026-10-25): Chi-Yu 059 Holo Reversa no Escuridão Absoluta.
const CHIYU_CARD = "433d73eb-7f25-4488-9b51-7b6719bc46cc";
const REVERSE = "b4c6000e-61e4-4fc3-8d58-cae137a7181a";
const CHIYU_KEY = `${CHIYU_CARD}:${REVERSE}`;
const OTHER_CARD = "11111111-2222-4333-8444-555555555555";
const TOKEN = `rc1:${"ab".repeat(32)}`;

const chiyuRow = {
  eligible: true,
  reason: null,
  novelty_count: 1,
  item_key: CHIYU_KEY,
  card_id: CHIYU_CARD,
  variant_type_id: REVERSE,
  collector_number: "059",
  card_name: "Chi-Yu",
  variant_type_code: "REVERSE_HOLO",
  variant_type_name: "Holo Reversa",
  born_at: "2026-10-24T20:02:22.822219+00:00",
  placed_in_binder: true,
};

function header(over: Record<string, unknown> = {}) {
  return {
    row_kind: "HEADER",
    step_no: null,
    item_key: null,
    kind: null,
    outcome: "READY",
    reason: null,
    total_items: 1,
    total_rows_moved: 0,
    row_limit: 500,
    item_limit: 100,
    requires_cross_page: false,
    requires_add_page: false,
    pages_added: 0,
    added_page_numbers: [],
    capacity_before: 360,
    capacity_after: 360,
    free_pockets_after: 164,
    plan_token: TOKEN,
    ...over,
  };
}

function item(over: Record<string, unknown> = {}) {
  return {
    row_kind: "ITEM",
    step_no: 1,
    item_key: CHIYU_KEY,
    card_id: CHIYU_CARD,
    variant_type_id: REVERSE,
    kind: "IN_PLACE",
    target_page: 13,
    target_row: 1,
    target_column: 3,
    end_page: null,
    end_row: null,
    end_column: null,
    anchor_page: 13,
    anchor_row: 1,
    anchor_column: 2,
    pockets_moved: null,
    rows_moved: 0,
    other_reserves_moved: 0,
    crosses_page: false,
    adds_page: false,
    barrier_page: null,
    barrier_row: null,
    barrier_column: null,
    barrier_kind: null,
    ...over,
  };
}

test("gate: só fichário existente, MASTER_SET e editável chama a RPC (Pokédex, Set, Livre e arquivada nunca)", () => {
  assert.equal(mayHaveCatalogNovelties({ hasBinder: true, kind: "MASTER_SET", editable: true }), true);
  assert.equal(mayHaveCatalogNovelties({ hasBinder: true, kind: "POKEDEX", editable: true }), false);
  assert.equal(mayHaveCatalogNovelties({ hasBinder: true, kind: "SET", editable: true }), false);
  assert.equal(mayHaveCatalogNovelties({ hasBinder: true, kind: "FREE", editable: true }), false);
  assert.equal(mayHaveCatalogNovelties({ hasBinder: true, kind: "MASTER_SET", editable: false }), false);
  assert.equal(mayHaveCatalogNovelties({ hasBinder: false, kind: "MASTER_SET", editable: true }), false);
});

test("aviso: caso Chi-Yu (1 novidade, já colocada no fichário)", () => {
  const state = parseCatalogNovelties([chiyuRow]);
  assert.ok(state && state.eligible);
  assert.equal(state.count, 1);
  assert.equal(state.items[0]?.itemKey, CHIYU_KEY);
  assert.equal(state.items[0]?.placedInBinder, true);
  assert.equal(noveltyLabel(state.items[0]!), "Chi-Yu · 059 · Holo Reversa");
  assert.equal(noveltyBadgeCount(state), 1);
});

test("aviso: elegível sem novidade = uma linha com contagem 0 e sem item", () => {
  const state = parseCatalogNovelties([{ eligible: true, reason: null, novelty_count: 0, item_key: null }]);
  assert.deepEqual(state, { eligible: true, count: 0, items: [] });
  assert.equal(noveltyBadgeCount(state), 0);
});

test("aviso: inelegível devolve o motivo e nenhum badge", () => {
  for (const reason of ["BINDER_OWNER_POKEDEX", "SPECIES_REFERENCES_PRESENT", "MARKER_MISSING", "NOT_MASTER_SET", "COLLECTION_ARCHIVED"]) {
    const state = parseCatalogNovelties([{ eligible: false, reason, novelty_count: 0 }]);
    assert.deepEqual(state, { eligible: false, reason });
    assert.equal(noveltyBadgeCount(state), 0);
  }
  assert.deepEqual(parseCatalogNovelties([{ eligible: false, reason: "ALGO_NOVO", novelty_count: 0 }]), { eligible: false, reason: "OTHER" });
});

test("aviso: formato fora do contrato → null (nunca adivinha)", () => {
  assert.equal(parseCatalogNovelties(null), null);
  assert.equal(parseCatalogNovelties([]), null);
  assert.equal(parseCatalogNovelties([{ ...chiyuRow, novelty_count: 2 }]), null, "contagem ≠ linhas");
  assert.equal(parseCatalogNovelties([{ ...chiyuRow, item_key: "lixo" }]), null);
  assert.equal(parseCatalogNovelties([{ ...chiyuRow, card_id: OTHER_CARD }]), null, "chave de outra carta");
  assert.equal(parseCatalogNovelties([{ ...chiyuRow, variant_type_id: null }]), null, "chave tipada sem acabamento");
  assert.equal(parseCatalogNovelties([chiyuRow, chiyuRow].map((r) => ({ ...r, novelty_count: 2 }))), null, "chave repetida");
  assert.equal(parseCatalogNovelties([{ eligible: "sim" }]), null);
});

test("aviso: posição genérica (carta:*) é aceita", () => {
  const state = parseCatalogNovelties([{ ...chiyuRow, item_key: `${CHIYU_CARD}:*`, variant_type_id: null, variant_type_name: null }]);
  assert.ok(state && state.eligible);
  assert.equal(state.items[0]?.variantTypeId, null);
  assert.equal(noveltyLabel(state.items[0]!), "Chi-Yu · 059");
});

test("prévia: caso Chi-Yu — READY, IN_PLACE em 13·1·3, âncora 13·1·2, 360 → 360, 164 livres", () => {
  const preview = parseCatalogPreview([header(), item()]);
  assert.ok(preview);
  assert.equal(preview.outcome, "READY");
  assert.equal(preview.items.length, 1);
  assert.deepEqual(preview.items[0]?.target, { page: 13, row: 1, column: 3 });
  assert.deepEqual(preview.items[0]?.anchor, { page: 13, row: 1, column: 2 });
  assert.equal(preview.capacityBefore, 360);
  assert.equal(preview.capacityAfter, 360);
  assert.equal(preview.freePocketsAfter, 164);
  assert.deepEqual(affectedPages(preview), [13]);
  assert.deepEqual(requiredConfirmations(preview), { crossPage: false, addPage: false });
  assert.equal(canApplyPreview(preview, { crossPage: false, addPage: false }), true);
  assert.equal(planItemMessage(preview.items[0]!), "Reserva no bolso livre página 13, linha 1, coluna 3. Nada se move.");
  assert.match(previewSummaryMessage(preview), /1 novidade pronta para incorporar; nenhum bolso com conteúdo se move\./);
});

test("prévia: ordem do HEADER irrelevante; itens ordenados por passo", () => {
  const second = item({ step_no: 2, item_key: `${OTHER_CARD}:*`, card_id: OTHER_CARD, variant_type_id: null, target_column: 4 });
  const preview = parseCatalogPreview([second, header({ total_items: 2 }), item()]);
  assert.ok(preview);
  assert.deepEqual(preview.items.map((i) => i.step), [1, 2]);
});

test("prévia: SHIFT atravessando página e página nova exigem as duas confirmações", () => {
  const preview = parseCatalogPreview([
    header({ requires_cross_page: true, requires_add_page: true, pages_added: 1, added_page_numbers: [41], total_rows_moved: 12, capacity_after: 369 }),
    item({ kind: "SHIFT", end_page: 41, end_row: 1, end_column: 1, pockets_moved: 6, rows_moved: 12, other_reserves_moved: 1, crosses_page: false, adds_page: true }),
  ]);
  assert.ok(preview);
  assert.deepEqual(requiredConfirmations(preview), { crossPage: true, addPage: true });
  assert.equal(canApplyPreview(preview, { crossPage: false, addPage: false }), false);
  assert.equal(canApplyPreview(preview, { crossPage: true, addPage: false }), false);
  assert.equal(canApplyPreview(preview, { crossPage: false, addPage: true }), false);
  assert.equal(canApplyPreview(preview, { crossPage: true, addPage: true }), true);
  assert.deepEqual(affectedPages(preview).slice(0, 2), [13, 14]);
  assert.equal(affectedPages(preview).at(-1), 41);
  assert.match(planItemMessage(preview.items[0]!), /6 bolsos avançam uma posição até a página 41, linha 1, coluna 1, levando 1 reserva de outra coleção/);
  assert.match(previewSummaryMessage(preview), /1 página nova \(41\)/);
});

test("prévia: bloqueios nunca liberam a aplicação, mesmo com token", () => {
  for (const [outcome, kind, barrier] of [
    ["BLOCKED", "BLOCKED", "LOCKED"],
    ["NEEDS_REVIEW", "OUT_OF_ORDER", "PLACED_OUT_OF_ORDER"],
    ["NEEDS_REVIEW", "REVIEW_REQUIRED", "GENERIC_RESERVATION"],
    ["NO_ANCHOR", "NO_ANCHOR", null],
  ] as const) {
    const preview = parseCatalogPreview([
      header({ outcome }),
      item({ kind, target_page: null, target_row: null, target_column: null, barrier_kind: barrier, barrier_page: barrier ? 13 : null, barrier_row: barrier ? 1 : null, barrier_column: barrier ? 2 : null }),
    ]);
    assert.ok(preview, `${outcome}/${kind}`);
    assert.equal(canApplyPreview(preview, { crossPage: true, addPage: true }), false, `${outcome}/${kind}`);
    assert.deepEqual(blockingItemKeys(preview), [CHIYU_KEY]);
    assert.ok(previewSummaryMessage(preview).length > 0);
    assert.ok(planItemMessage(preview.items[0]!).length > 0);
  }
});

test("prévia: OVER_LIMIT por itens e por linhas; NOTHING_TO_DO", () => {
  const items = parseCatalogPreview([header({ outcome: "OVER_LIMIT", reason: "ITEM_LIMIT", total_items: 101, plan_token: null })]);
  assert.ok(items);
  assert.equal(canApplyPreview(items, { crossPage: true, addPage: true }), false);
  assert.match(previewSummaryMessage(items), /limite é 100/);
  const rows = parseCatalogPreview([header({ outcome: "OVER_LIMIT", reason: "ROW_LIMIT", total_rows_moved: 612 }), item({ kind: "SHIFT", end_page: 20, end_row: 3, end_column: 3, pockets_moved: 300, rows_moved: 612 })]);
  assert.ok(rows);
  assert.match(previewSummaryMessage(rows), /612; o limite é 500/);
  const none = parseCatalogPreview([header({ outcome: "NOTHING_TO_DO", total_items: 0, plan_token: null })]);
  assert.ok(none);
  assert.equal(canApplyPreview(none, { crossPage: false, addPage: false }), false);
});

test("prévia: formato fora do contrato → null", () => {
  assert.equal(parseCatalogPreview([]), null);
  assert.equal(parseCatalogPreview([item()]), null, "sem HEADER");
  assert.equal(parseCatalogPreview([header(), header(), item()]), null, "dois HEADERs");
  assert.equal(parseCatalogPreview([header({ plan_token: null }), item()]), null, "READY sem token");
  assert.equal(parseCatalogPreview([header({ plan_token: "g1:abc" }), item()]), null, "token de outro contrato");
  assert.equal(parseCatalogPreview([header({ outcome: "TALVEZ" }), item()]), null);
  assert.equal(parseCatalogPreview([header(), item({ kind: "VOAR" })]), null);
  assert.equal(parseCatalogPreview([header(), item({ target_page: null })]), null, "executável sem destino");
  assert.equal(parseCatalogPreview([header({ total_items: 2 }), item()]), null, "READY com itens faltando");
  assert.equal(parseCatalogPreview([header(), item({ kind: "BLOCKED" })]), null, "READY com item não executável");
});

test("seleção: sempre lista explícita, na ordem do aviso (nunca null)", () => {
  const state = parseCatalogNovelties([
    { ...chiyuRow, novelty_count: 2 },
    { ...chiyuRow, novelty_count: 2, item_key: `${OTHER_CARD}:*`, card_id: OTHER_CARD, variant_type_id: null },
  ]);
  assert.ok(state && state.eligible);
  assert.deepEqual(selectionKeys(state.items, new Set([`${OTHER_CARD}:*`, CHIYU_KEY])), [CHIYU_KEY, `${OTHER_CARD}:*`]);
  assert.deepEqual(selectionKeys(state.items, new Set()), []);
});

test("aplicação: APPLIED / ALREADY_APPLIED / NOTHING_TO_DO e formatos inválidos", () => {
  const applied = parseCatalogApply([{ outcome: "APPLIED", items_applied: 1, reservations_created: 1, reservations_upgraded: 0, pockets_moved: 0, rows_moved: 0, pages_added: 0, added_page_numbers: [] }]);
  assert.ok(applied);
  assert.equal(applyResultMessage(applied), "1 novidade foi incorporada ao fichário.");
  const already = parseCatalogApply([{ outcome: "ALREADY_APPLIED", items_applied: 0, reservations_created: 0, reservations_upgraded: 0, pockets_moved: 0, rows_moved: 0, pages_added: 0, added_page_numbers: [] }]);
  assert.ok(already);
  assert.match(applyResultMessage(already), /já estavam incorporadas/);
  const shifted = parseCatalogApply([{ outcome: "APPLIED", items_applied: 2, reservations_created: 1, reservations_upgraded: 1, pockets_moved: 4, rows_moved: 8, pages_added: 1, added_page_numbers: [41] }]);
  assert.ok(shifted);
  assert.equal(applyResultMessage(shifted), "2 novidades foram incorporadas ao fichário (4 bolsos avançaram; página 41 adicionada).");
  assert.equal(parseCatalogApply([]), null);
  assert.equal(parseCatalogApply([{ outcome: "APPLIED", items_applied: 2, reservations_created: 1, reservations_upgraded: 0, pockets_moved: 0, rows_moved: 0, pages_added: 0, added_page_numbers: [] }]), null, "criadas + convertidas ≠ itens");
  assert.equal(parseCatalogApply([{ outcome: "APPLIED", items_applied: 1, reservations_created: 1, reservations_upgraded: 0, pockets_moved: 0, rows_moved: 0, pages_added: 1, added_page_numbers: [] }]), null, "páginas sem números");
  assert.equal(parseCatalogApply([{ outcome: "ALREADY_APPLIED", items_applied: 1, reservations_created: 1, reservations_upgraded: 0, pockets_moved: 0, rows_moved: 0, pages_added: 0, added_page_numbers: [] }]), null);
});

test("falhas: mensagem tem precedência sobre o código (códigos compartilhados)", () => {
  assert.equal(classifyCatalogFailure("40001", "RECONCILE_PLAN_CHANGED"), "plan_changed");
  assert.equal(classifyCatalogFailure("54000", "RECONCILE_OVER_LIMIT"), "over_limit");
  assert.equal(classifyCatalogFailure("55000", "RECONCILE_BLOCKED"), "blocked");
  assert.equal(classifyCatalogFailure("55000", "RECONCILE_NEEDS_REVIEW"), "needs_review");
  assert.equal(classifyCatalogFailure("55000", "RECONCILE_NO_ANCHOR"), "no_anchor");
  assert.equal(classifyCatalogFailure("55000", "RECONCILE_CONFIRMATION_REQUIRED", "CROSS_PAGE"), "confirm_cross_page");
  assert.equal(classifyCatalogFailure("55000", "RECONCILE_CONFIRMATION_REQUIRED", "ADD_PAGE"), "confirm_add_page");
  assert.equal(classifyCatalogFailure("55000", "COLLECTION_ARCHIVED"), "archived");
  assert.equal(classifyCatalogFailure("P0001", "RECONCILE_INCONSISTENT"), "inconsistent");
  assert.equal(classifyCatalogFailure("P0001", "COLLECTION_REFERENCE_MISSING"), "reference_missing");
  assert.equal(classifyCatalogFailure("22023", "SELECTION_INVALID"), "selection_invalid");
  assert.equal(classifyCatalogFailure("22023", "NOT_MASTER_SET"), "not_master_set");
  assert.equal(classifyCatalogFailure("22023", "BINDER_NOT_ELIGIBLE"), "not_eligible");
  assert.equal(classifyCatalogFailure("22023", "INVALID_ARGUMENT"), "invalid");
  assert.equal(classifyCatalogFailure("P0002", "COLLECTION_NOT_FOUND"), "not_found");
  assert.equal(classifyCatalogFailure("P0002", "BINDER_NOT_FOUND"), "not_found");
  assert.equal(classifyCatalogFailure("28000", "not_authenticated"), "not_authenticated");
  assert.equal(classifyCatalogFailure("55P03", "canceling statement due to lock timeout"), "lock_busy");
  assert.equal(classifyCatalogFailure("PGRST202", "Could not find the function"), "unavailable");
  assert.equal(classifyCatalogFailure("XX000", "boom"), "unknown");
  for (const r of ["plan_changed", "selection_invalid", "inconsistent"] as const) assert.equal(failureNeedsFreshPreview(r), true);
  assert.equal(failureNeedsFreshPreview("lock_busy"), false);
  assert.ok(catalogFailureMessage("plan_changed").includes("prévia"));
});

test("token: só o formato rc1 da 5264", () => {
  assert.equal(isCatalogPlanToken(TOKEN), true);
  assert.equal(isCatalogPlanToken(`g1:${"ab".repeat(32)}`), false);
  assert.equal(isCatalogPlanToken("rc1:ABC"), false);
  assert.equal(isCatalogPlanToken(null), false);
});
