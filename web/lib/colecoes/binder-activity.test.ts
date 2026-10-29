// Histórico de Atividades do Fichário (P3-B S7): regras puras de apresentação.
// Executar: node --experimental-strip-types --test lib/colecoes/binder-activity.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { test } from "node:test";
import {
  ACTIVITY_CATEGORIES,
  ACTIVITY_EVENT_TYPES,
  ACTIVITY_FILTERS,
  LEGACY_BADGE,
  type ActivityEvent,
  activityFailureMessage,
  cardLabel,
  categoryOf,
  classifyActivityFailure,
  countNewer,
  coverageNote,
  cursorAfter,
  compactDateTime,
  dayFullLabel,
  dayLabel,
  describeEvent,
  describeItem,
  emptyMessage,
  filterCategories,
  groupByDay,
  isCursor,
  mergeActivity,
  pagesLabel,
  detailFields,
  detailItems,
  headlineEvent,
  parseActivityCoverage,
  parseActivityEvent,
  parseActivityPage,
  positionLabel,
  timeLabel,
  truncationNote,
} from "./binder-activity.ts";

type RawItem = Record<string, unknown>;

function rawEvent(over: Record<string, unknown> = {}, items: RawItem[] = []): Record<string, unknown> {
  return {
    event_id: 10,
    occurred_at: "2026-10-28T22:07:20.286Z",
    event_type: "CARD_PLACED",
    category: "CARDS",
    source: "FICHARIO",
    is_legacy: false,
    collection_id: "fdac7045-c001-4bcb-b568-0b3515ea4fed",
    collection_name: "Caos Ascendente",
    binder_name: null,
    summary: {},
    item_count: items.length,
    items,
    items_truncated: false,
    ...over,
  };
}

const CARD = { card_name: "Mega Darkrai ex", collector_number: "120", variant_type_name: "Holo Reversa" };

function ev(type: string, items: RawItem[], over: Record<string, unknown> = {}): ActivityEvent {
  const e = parseActivityEvent(rawEvent({ event_type: type, category: undefined, ...over }, items.map((it, i) => ({ ordinal: i + 1, ...it }))));
  assert.ok(e, `evento ${type} deveria ser válido`);
  return e;
}

// ---------------------------------------------------------------------------

test("vocabulário: 24 tipos, todos com categoria e frase própria (sem genérico)", () => {
  assert.equal(ACTIVITY_EVENT_TYPES.length, 24);
  const sample: Record<string, RawItem[]> = {
    BINDER_ASSEMBLED: [{ kind: "PAGE", effect: "PAGE_ADDED", to_page: 1 }],
    CARD_PLACED: [{ kind: "CARD", effect: "PLACED", ...CARD, to_page: 5, to_row: 1, to_col: 1 }],
    CARD_MOVED: [{ kind: "CARD", effect: "MOVED", ...CARD, from_page: 3, from_row: 2, from_col: 4, to_page: 5, to_row: 1, to_col: 1 }],
    CARDS_SWAPPED: [
      { kind: "CARD", effect: "SWAPPED", card_name: "A", from_page: 1, from_row: 1, from_col: 1, to_page: 2, to_row: 1, to_col: 1 },
      { kind: "CARD", effect: "SWAPPED", card_name: "B", from_page: 2, from_row: 1, from_col: 1, to_page: 1, to_row: 1, to_col: 1 },
    ],
    CARDS_REMOVED: [{ kind: "CARD", effect: "REMOVED", ...CARD, from_page: 4, from_row: 1, from_col: 1 }],
    CARDS_LEFT_BY_STORAGE: [{ kind: "CARD", effect: "LEFT", ...CARD, from_page: 4, from_row: 1, from_col: 1 }],
    CARDS_LEFT_BY_COLLECTION_STORAGE: [{ kind: "CARD", effect: "LEFT", ...CARD, from_page: 4, from_row: 1, from_col: 1 }],
    CARD_LEFT_BY_INVENTORY_EXIT: [{ kind: "CARD", effect: "LEFT", ...CARD, from_page: 4, from_row: 1, from_col: 1 }],
    POCKET_RESERVED: [{ kind: "RESERVATION", effect: "RESERVED", ...CARD, to_page: 2, to_row: 1, to_col: 3 }],
    RESERVATIONS_RELEASED: [{ kind: "RESERVATION", effect: "RELEASED", from_page: 2, from_row: 1, from_col: 3 }],
    POCKETS_LOCKED: [{ kind: "POCKET", effect: "LOCKED", from_page: 2, from_row: 1, from_col: 3 }],
    POCKETS_UNLOCKED: [{ kind: "POCKET", effect: "UNLOCKED", from_page: 2, from_row: 1, from_col: 3 }],
    GAP_OPENED: [{ kind: "CARD", effect: "SHIFTED", ...CARD, from_page: 2, from_row: 1, from_col: 1, to_page: 2, to_row: 1, to_col: 2 }],
    GAP_CLOSED: [{ kind: "CARD", effect: "SHIFTED", ...CARD, from_page: 2, from_row: 1, from_col: 2, to_page: 2, to_row: 1, to_col: 1 }],
    PAGES_ADDED: [{ kind: "PAGE", effect: "PAGE_ADDED", to_page: 23 }],
    PAGE_REMOVED: [{ kind: "PAGE", effect: "PAGE_REMOVED", from_page: 7 }],
    PAGES_REORDERED: [{ kind: "PAGE", effect: "PAGE_RENUMBERED", from_page: 2, to_page: 3 }],
    CATALOG_NOVELTIES_INCORPORATED: [{ kind: "RESERVATION", effect: "RESERVED", ...CARD, to_page: 2, to_row: 1, to_col: 1 }],
    COLLECTION_ATTACHED: [{ kind: "COLLECTION", effect: "ATTACHED" }],
    COLLECTION_DETACHED: [{ kind: "RESERVATION", effect: "RELEASED", from_page: 1, from_row: 1, from_col: 1 }, { kind: "COLLECTION", effect: "DETACHED" }],
    BINDER_DISMANTLED: [{ kind: "BINDER", effect: "CLOSED" }],
    BINDER_DELETED_EMPTY: [{ kind: "BINDER", effect: "CLOSED" }],
    BINDER_OWNERSHIP_TRANSFERRED: [{ kind: "BINDER", effect: "TRANSFERRED" }],
    LEGACY_CATALOG_INCORPORATION: [{ kind: "CARD", effect: "INCORPORATED", ...CARD }],
  };
  const titles = new Set<string>();
  for (const type of ACTIVITY_EVENT_TYPES) {
    const category = categoryOf(type);
    assert.ok(category && (ACTIVITY_CATEGORIES as readonly string[]).includes(category), `categoria de ${type}`);
    const over = type === "LEGACY_CATALOG_INCORPORATION" ? { source: "LEGADO", is_legacy: true } : {};
    const view = describeEvent(ev(type, sample[type] ?? [], over));
    assert.notEqual(view.title, "Atividade no fichário", `frase própria para ${type}`);
    assert.notEqual(view.icon, "activity", `ícone próprio para ${type}`);
    assert.doesNotMatch(view.title + (view.context ?? ""), /[A-Z]{3,}_[A-Z]/, `sem enum exposto em ${type}`);
    titles.add(`${type}:${view.title}`);
  }
  assert.equal(titles.size, 24);
});

test("categorias espelham a 5269 e os filtros seguem a §3.3", () => {
  assert.deepEqual(
    ACTIVITY_FILTERS.map((f) => f.label),
    ["Todas", "Cartas", "Reservas", "Fixação", "Páginas", "Catálogo", "Fichário"],
  );
  assert.equal(filterCategories("ALL"), null);
  assert.deepEqual(filterCategories("LOCKS"), ["LOCKS"]);
  assert.equal(categoryOf("PAGES_ADDED"), "PAGES");
  assert.equal(categoryOf("LEGACY_CATALOG_INCORPORATION"), "CATALOG");
  assert.equal(categoryOf("BINDER_OWNERSHIP_TRANSFERRED"), "BINDER");
  assert.equal(categoryOf("ALGO_NOVO"), null);
});

test("frases dos exemplos da especificação", () => {
  const moved = describeEvent(ev("CARD_MOVED", [{ kind: "CARD", effect: "MOVED", card_name: "Mega Darkrai ex", collector_number: "120", from_page: 3, from_row: 2, from_col: 4, to_page: 5, to_row: 1, to_col: 1 }]));
  assert.equal(moved.title, "Mega Darkrai ex · 120 movida da página 3 (linha 2, coluna 4) para a página 5 (linha 1, coluna 1)");
  assert.equal(moved.expandable, false);

  const removed = describeEvent(
    ev(
      "CARDS_REMOVED",
      Array.from({ length: 7 }, (_, i) => ({ kind: "CARD", effect: "REMOVED", card_name: `C${i}`, from_page: i < 4 ? 4 : 5, from_row: 1, from_col: i + 1 })),
    ),
  );
  assert.equal(removed.title, "7 cartas retiradas · páginas 4 e 5");
  assert.equal(removed.expandable, true);

  const locked = describeEvent(ev("POCKETS_LOCKED", [1, 2, 3].map((c) => ({ kind: "POCKET", effect: "LOCKED", from_page: 2, from_row: 1, from_col: c }))));
  assert.equal(locked.title, "3 bolsos fixados · página 2");

  const left = describeEvent(ev("CARDS_LEFT_BY_STORAGE", [{ kind: "CARD", effect: "LEFT", card_name: "Chi-Yu", collector_number: "059", variant_type_name: "Holo Reversa", from_page: 1, from_row: 1, from_col: 1 }], { summary: { storage_container_name: "Caixa 2" } }));
  assert.equal(left.title, "Chi-Yu · 059 · Holo Reversa saiu do fichário");
  assert.equal(left.context, "Mudou de local no Meu acervo · Caixa 2");
});

test("montagem do fichário (evento real 83): resumo e contagem sem inferir de lista truncada", () => {
  const items = Array.from({ length: 50 }, (_, i) => ({ kind: "PAGE", effect: "PAGE_ADDED", to_page: (i % 22) + 1 }));
  const e = ev("BINDER_ASSEMBLED", items, { item_count: 220, items_truncated: true, summary: { grid_rows: 3, grid_columns: 3, extra_policy: "PRINCIPAL_ONLY", extras_unplaced: 0 } });
  const view = describeEvent(e);
  assert.equal(view.title, "Fichário montado");
  assert.equal(view.context, "Coleção Caos Ascendente · grade 3 × 3");
  assert.equal(truncationNote(e), "Mostrando 50 de 220 alterações deste registro.");

  const complete = ev("BINDER_ASSEMBLED", [
    { kind: "PAGE", effect: "PAGE_ADDED", to_page: 1 },
    { kind: "PAGE", effect: "PAGE_ADDED", to_page: 2 },
    { kind: "RESERVATION", effect: "RESERVED", card_name: "X", to_page: 1, to_row: 1, to_col: 1 },
  ], { summary: { grid_rows: 3, grid_columns: 3 } });
  assert.equal(describeEvent(complete).context, "Coleção Caos Ascendente · grade 3 × 3 · 2 páginas · 1 reserva");
  assert.equal(truncationNote(complete), null);
});

test("páginas adicionadas permanecem eventos individuais (sem agrupamento D6)", () => {
  const a = describeEvent(ev("PAGES_ADDED", [{ kind: "PAGE", effect: "PAGE_ADDED", to_page: 23 }]));
  assert.equal(a.title, "Página 23 adicionada");
  assert.equal(a.expandable, false);
});

test("legado e encerramento", () => {
  const legacy = ev("LEGACY_CATALOG_INCORPORATION", [{ kind: "CARD", effect: "INCORPORATED", card_name: "Chi-Yu", collector_number: "059" }], { source: "LEGADO", is_legacy: true });
  const view = describeEvent(legacy);
  assert.equal(view.legacy, true);
  assert.equal(view.title, "Chi-Yu · 059 incorporada do Catálogo");
  assert.equal(LEGACY_BADGE, "Registro anterior ao histórico completo");
  assert.equal(describeEvent(ev("BINDER_DISMANTLED", [{ kind: "BINDER", effect: "CLOSED" }], { summary: { pages: 22 } })).context, "22 páginas desfeitas · o histórico continua guardado");
  assert.equal(describeEvent(ev("BINDER_OWNERSHIP_TRANSFERRED", [{ kind: "BINDER", effect: "TRANSFERRED" }], { collection_name: "Coleção Clássica" })).title, "O fichário passou a ser da coleção Coleção Clássica");
  assert.equal(describeEvent(ev("COLLECTION_DETACHED", [{ kind: "RESERVATION", effect: "RELEASED", from_page: 1 }, { kind: "COLLECTION", effect: "DETACHED" }])).context, "1 reserva liberada");
});

test("itens dos detalhes", () => {
  const base = { ordinal: 1, cardName: "Pikachu", collectorNumber: "025", setCode: null, variantName: null, detail: null };
  assert.equal(describeItem({ ...base, kind: "CARD", effect: "PLACED", from: null, to: { page: 2, row: 1, col: 3 } }), "Pikachu · 025 · → página 2 (linha 1, coluna 3)");
  assert.equal(describeItem({ ...base, kind: "CARD", effect: "SHIFTED", from: { page: 2, row: 1, col: 3 }, to: { page: 2, row: 1, col: 4 } }), "Pikachu · 025 · página 2 (linha 1, coluna 3) → página 2 (linha 1, coluna 4)");
  assert.equal(describeItem({ ...base, cardName: null, kind: "PAGE", effect: "PAGE_RENUMBERED", from: { page: 2, row: null, col: null }, to: { page: 5, row: null, col: null } }), "Página 2 → posição 5");
  assert.equal(describeItem({ ...base, cardName: null, kind: "POCKET", effect: "UNLOCKED", from: { page: 1, row: 2, col: 2 }, to: null }), "Bolso desafixado · página 1 (linha 2, coluna 2)");
});

test("rótulos auxiliares", () => {
  assert.equal(cardLabel({ cardName: null, collectorNumber: null, variantName: null }), "Carta");
  assert.equal(positionLabel({ page: 3, row: null, col: null }), "página 3");
  assert.equal(pagesLabel([5, 4, 4]), "páginas 4 e 5");
  assert.equal(pagesLabel([1, 2, 3]), "páginas 1, 2 e 3");
  assert.equal(pagesLabel([1, 2, 3, 4, 5, 6, 7]), "7 páginas");
  assert.equal(pagesLabel([]), "");
});

test("parse rejeita formato inesperado e aceita página vazia", () => {
  assert.deepEqual(parseActivityPage(null), []);
  assert.deepEqual(parseActivityPage([]), []);
  assert.equal(parseActivityPage({}), null);
  assert.equal(parseActivityPage([rawEvent({ event_id: "x" })]), null);
  assert.equal(parseActivityPage([rawEvent({ occurred_at: "ontem" })]), null);
  assert.equal(parseActivityPage([rawEvent({}, [{ ordinal: 1, kind: "CARD" }])]), null);
  const ok = parseActivityPage([rawEvent({ event_id: "42" }, [{ ordinal: 2, kind: "CARD", effect: "PLACED", to_page: 1 }, { ordinal: 1, kind: "CARD", effect: "PLACED", to_page: 2 }])]);
  assert.ok(ok);
  assert.equal(ok[0]?.id, 42);
  assert.deepEqual(ok[0]?.items.map((i) => i.ordinal), [1, 2]);
  // linha/coluna só valem juntas
  const half = parseActivityEvent(rawEvent({}, [{ ordinal: 1, kind: "CARD", effect: "PLACED", to_page: 1, to_row: 2 }]));
  assert.deepEqual(half?.items[0]?.to, { page: 1, row: null, col: null });
  // item_count maior que os itens → truncado mesmo sem a flag
  assert.equal(parseActivityEvent(rawEvent({ item_count: 3 }, [{ ordinal: 1, kind: "CARD", effect: "PLACED", to_page: 1 }]))?.truncated, true);
});

test("cobertura", () => {
  assert.deepEqual(parseActivityCoverage([]), { coveredFrom: null, hasLegacy: false, binderIsMine: false });
  const c = parseActivityCoverage([{ full_coverage_from: "2026-10-27T02:48:29Z", covered_from: "2026-10-27T02:48:29Z", coverage_reason: null, has_legacy: true, binder_is_mine: true }]);
  assert.deepEqual(c, { coveredFrom: "2026-10-27T02:48:29Z", hasLegacy: true, binderIsMine: true });
  assert.match(coverageNote(c) ?? "", /^Histórico registrado a partir de 26 de outubro de 2026\./);
  assert.equal(coverageNote(null), null);
  assert.equal(parseActivityCoverage("x"), null);
});

test("paginação estável: cursor, junção sem duplicar, ordem decrescente", () => {
  const e = (id: number, at: string) => ev("PAGES_ADDED", [{ kind: "PAGE", effect: "PAGE_ADDED", to_page: id }], { event_id: id, occurred_at: at });
  const page1 = [e(101, "2026-10-28T22:07:44Z"), e(100, "2026-10-28T22:07:44Z"), e(99, "2026-10-28T22:07:43Z")];
  assert.deepEqual(cursorAfter(page1), { occurredAt: "2026-10-28T22:07:43Z", id: 99 });
  assert.equal(cursorAfter([]), null);
  assert.equal(isCursor({ occurredAt: "2026-10-28T22:07:43Z", id: 99 }), true);
  assert.equal(isCursor({ occurredAt: "x", id: 99 }), false);
  assert.equal(isCursor({ occurredAt: "2026-10-28T22:07:43Z", id: 0 }), false);
  const page2 = [e(99, "2026-10-28T22:07:43Z"), e(98, "2026-10-28T22:07:42Z")];
  const merged = mergeActivity(page1, page2);
  assert.deepEqual(merged.map((x) => x.id), [101, 100, 99, 98]);
  const fresh = [e(102, "2026-10-28T22:10:00Z"), e(101, "2026-10-28T22:07:44Z")];
  assert.equal(countNewer(merged, fresh), 1);
  assert.deepEqual(mergeActivity(merged, fresh).map((x) => x.id), [102, 101, 100, 99, 98]);
});

test("agrupamento por dia no fuso de São Paulo", () => {
  const now = new Date("2026-10-28T23:30:00Z"); // 20:30 em São Paulo
  const e = (id: number, at: string) => ev("PAGES_ADDED", [{ kind: "PAGE", effect: "PAGE_ADDED", to_page: 1 }], { event_id: id, occurred_at: at });
  const days = groupByDay([e(3, "2026-10-28T22:07:20Z"), e(2, "2026-10-28T02:00:00Z"), e(1, "2025-12-31T12:00:00Z")], now);
  assert.deepEqual(days.map((d) => d.label), ["Hoje", "Ontem", "31 dez 2025"]);
  assert.equal(days[1]?.events[0]?.id, 2); // 23:00 de 27/10 em São Paulo
  assert.equal(dayLabel("2026-09-03", now), "3 set");
  assert.equal(dayFullLabel("2026-10-27"), "27 de outubro de 2026");
  assert.equal(compactDateTime("2026-10-29T00:42:00Z"), "28 out 2026 · 21:42");
  assert.equal(timeLabel("2026-10-28T22:07:20Z"), "19:07");
});

test("mensagens de estado e falha", () => {
  assert.match(emptyMessage("ALL"), /Nenhuma atividade registrada/);
  assert.match(emptyMessage("LOCKS"), /Fixação/);
  assert.equal(classifyActivityFailure("28000"), "not_authenticated");
  assert.equal(classifyActivityFailure("22023"), "invalid");
  assert.equal(classifyActivityFailure("PGRST202"), "unavailable");
  assert.equal(classifyActivityFailure("XX000"), "unknown");
  assert.match(activityFailureMessage("unknown"), /Não foi possível/);
});

test("Activity Log: manchete curta objeto + ação para os 24 tipos", () => {
  const card = (name: string) => ({ kind: "CARD", card_name: name, collector_number: "009", from_page: 3, from_row: 2, from_col: 4, to_page: 5, to_row: 1, to_col: 1 });
  assert.equal(headlineEvent(ev("CARD_PLACED", [{ ...card("Exeggcute"), effect: "PLACED", from_page: undefined, from_row: undefined, from_col: undefined }])), "Exeggcute colocada");
  assert.equal(headlineEvent(ev("CARD_MOVED", [{ ...card("Exeggutor de Alola"), effect: "MOVED" }])), "Exeggutor de Alola movida");
  assert.equal(headlineEvent(ev("CARDS_SWAPPED", [{ ...card("A"), effect: "SWAPPED" }, { ...card("B"), effect: "SWAPPED" }])), "A trocada com B");
  assert.equal(headlineEvent(ev("CARDS_REMOVED", Array.from({ length: 7 }, () => ({ ...card("X"), effect: "REMOVED" })))), "7 cartas retiradas");
  assert.equal(headlineEvent(ev("PAGE_REMOVED", [{ kind: "PAGE", effect: "PAGE_REMOVED", from_page: 41 }])), "Página 41 removida");
  assert.equal(headlineEvent(ev("PAGES_ADDED", [{ kind: "PAGE", effect: "PAGE_ADDED", to_page: 23 }])), "Página 23 adicionada");
  assert.equal(headlineEvent(ev("PAGES_REORDERED", [])), "Páginas reordenadas");
  assert.equal(headlineEvent(ev("POCKET_RESERVED", [{ kind: "RESERVATION", effect: "RESERVED", to_page: 1 }])), "Reserva criada");
  assert.equal(headlineEvent(ev("POCKETS_LOCKED", [{ kind: "POCKET", effect: "LOCKED", from_page: 1 }])), "Bolso fixado");
  assert.equal(headlineEvent(ev("POCKETS_LOCKED", [1, 2, 3].map(() => ({ kind: "POCKET", effect: "LOCKED", from_page: 1 })))), "3 bolsos fixados");
  assert.equal(headlineEvent(ev("BINDER_ASSEMBLED", [])), "Fichário montado");
  assert.equal(headlineEvent(ev("COLLECTION_ATTACHED", [])), "Coleção associada");
  // Lista parcial: total do evento, nunca contagem dos itens parciais.
  assert.equal(headlineEvent(ev("CARDS_REMOVED", [{ ...card("X"), effect: "REMOVED" }], { item_count: 90, items_truncated: true })), "90 cartas retiradas");
  const seen = new Set<string>();
  for (const type of ACTIVITY_EVENT_TYPES) {
    const h = headlineEvent(ev(type, [], type === "LEGACY_CATALOG_INCORPORATION" ? { source: "LEGADO", is_legacy: true } : {}));
    assert.notEqual(h, "Atividade registrada", `manchete própria para ${type}`);
    assert.ok(h.length <= 40, `manchete curta para ${type}: ${h}`);
    assert.doesNotMatch(h, /[A-Z]{3,}_/, `sem código interno em ${type}`);
    seen.add(h);
  }
  assert.ok(seen.size >= 20);
});

test("detalhes: campos completos, sem inventar dados", () => {
  const moved = ev("CARD_MOVED", [{ kind: "CARD", effect: "MOVED", card_name: "Mega Darkrai ex", collector_number: "120", card_set_code: "MEG", variant_type_name: "Holo Reversa", from_page: 3, from_row: 2, from_col: 4, to_page: 5, to_row: 1, to_col: 1 }], { binder_name: "Fichário Azul" });
  const f = Object.fromEntries(detailFields(moved).map((x) => [x.label, x.value]));
  assert.match(f["Ação"] ?? "", /movida da página 3 \(linha 2, coluna 4\)/);
  assert.equal(f["Carta"], "Mega Darkrai ex · 120 · MEG · Holo Reversa");
  assert.equal(f["De"], "Página 3 (linha 2, coluna 4)");
  assert.equal(f["Para"], "Página 5 (linha 1, coluna 1)");
  assert.equal(f["Coleção"], "Caos Ascendente");
  assert.equal(f["Fichário"], "Fichário Azul");
  assert.equal(f["Por"], "Você");
  assert.match(f["Quando"] ?? "", /^28 out 2026 · 19:07$/);
  assert.deepEqual(detailItems(moved), []);

  const legacy = ev("LEGACY_CATALOG_INCORPORATION", [{ kind: "CARD", effect: "INCORPORATED", card_name: "Chi-Yu" }], { source: "LEGADO", is_legacy: true, collection_name: null });
  const lf = Object.fromEntries(detailFields(legacy).map((x) => [x.label, x.value]));
  assert.equal(lf["Por"], "Não registrado (anterior ao histórico)");
  assert.equal(lf["Coleção"], undefined);

  const storage = ev("CARDS_LEFT_BY_STORAGE", [{ kind: "CARD", effect: "LEFT", card_name: "A", from_page: 1 }, { kind: "CARD", effect: "LEFT", card_name: "B", from_page: 2 }], { summary: { storage_container_name: "Caixa 2" } });
  const sf = detailFields(storage).map((x) => x.label);
  assert.ok(sf.includes("Destino"));
  assert.equal(detailItems(storage).length, 2);
});
