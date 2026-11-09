// V1-14 — Caderno de Cartas da Coleção: catálogo do Set (search_cards) validado, posse secundária a
// partir das posições canônicas, Master Set com acabamentos, paginação editorial, conferência e
// guardas de código (menu, ação, autorização, peça, impressão). Sem DOM: o visual fica para a
// homologação do proprietário.
// Executar: node --experimental-strip-types --test lib/reports/card-booklet.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import {
  BOOKLET_CARDS_PER_PAGE,
  type BookletCatalogCard,
  type BookletCatalogRead,
  bookletCardAria,
  bookletIncompleteText,
  bookletNumberText,
  bookletRangeText,
  bookletStatusText,
  buildCardBooklet,
  mergeCatalogPages,
  parseCatalogPage,
} from "./card-booklet.ts";
import { type ChecklistKind, type ChecklistRow, collectionReportItems } from "./collection-checklist.ts";
import type { RarityCatalogInput } from "./distribution.ts";

const web = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const read = (path: string) => readFileSync(resolve(web, path), "utf8");
const code = (source: string) => source.replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "").replace(/\{\/\*[\s\S]*?\*\/\}/g, "");

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const RARITIES: RarityCatalogInput = {
  status: "ok",
  entries: [
    { code: "COMMON", name: "Comum", symbolCode: "BLACK_CIRCLE", displayOrder: 1 },
    { code: "RARE", name: "Rara", symbolCode: "BLACK_STAR", displayOrder: 3 },
    { code: "SIR", name: "Ilustração Rara Especial", symbolCode: "GOLD_DOUBLE_STAR", displayOrder: 7 },
  ],
};

function card(n: number, rarity = "COMMON", image: string | null = `me2/pt-BR/${n}.webp`): BookletCatalogCard {
  return { cardId: id(n), number: String(n), total: 295, name: `Carta ${n}`, rarityCode: rarity, imagePath: image };
}

function pos(n: number, owned: boolean, finish: string | null = null, imagePath: string | null = null): ChecklistRow {
  const cardId = id(n);
  return { key: finish ? `${cardId}:${finish}` : cardId, number: String(n), name: `Carta ${n}`, finish, owned, copies: owned ? 1 : 0, inAcervo: false, cardId, imagePath };
}

const ok = (cards: BookletCatalogCard[]): BookletCatalogRead => ({ status: "ok", cards });

function build(kind: ChecklistKind, cards: BookletCatalogCard[], positions: ChecklistRow[], canonical: { total: number; satisfied: number }, extra: Partial<{ catalog: BookletCatalogRead; positionsComplete: boolean; rarityCatalog: RarityCatalogInput }> = {}) {
  return buildCardBooklet({
    kind,
    catalog: extra.catalog ?? ok(cards),
    positions,
    positionsComplete: extra.positionsComplete ?? true,
    rarityCatalog: extra.rarityCatalog ?? RARITIES,
    canonical,
  });
}

test("Set padrão: o Set inteiro na ordem do catálogo; posse secundária por carta; imagem da coleção primeiro", () => {
  const cards = [card(1), card(2, "RARE"), card(3, "SIR")];
  const r = build("STANDARD_SET", cards, [pos(1, true, null, "me2/pt-BR/1-colecao.webp"), pos(2, false), pos(3, false)], { total: 3, satisfied: 1 });
  assert.equal(r.complete, true);
  assert.deepEqual(r.cards.map((c) => [c.number, c.status]), [["1", "owned"], ["2", "missing"], ["3", "missing"]]);
  assert.equal(r.cards[0]?.imagePath, "me2/pt-BR/1-colecao.webp", "imagem da leitura da coleção");
  assert.equal(r.cards[1]?.imagePath, "me2/pt-BR/2.webp", "sem imagem na posição → a do catálogo");
  assert.deepEqual(r.cards[2]?.rarity, { code: "SIR", name: "Ilustração Rara Especial", symbolCode: "GOLD_DOUBLE_STAR" });
  assert.deepEqual(r.rarities.map((x) => [x.code, x.cards]), [["COMMON", 1], ["RARE", 1], ["SIR", 1]]);
  assert.deepEqual([r.positions, r.satisfied, r.missing, r.percentText], [3, 1, 2, "33%"]);
});

test("Master Set: cartas fora do objetivo continuam no caderno, sem marca; parcial por acabamentos", () => {
  const cards = [card(1), card(2), card(3, "SIR")];
  const r = build(
    "MASTER_SET",
    cards,
    [pos(1, true, "Padrão"), pos(1, false, "Holográfica Reversa"), pos(3, true, "Qualquer acabamento")],
    { total: 3, satisfied: 2 },
  );
  assert.equal(r.complete, true);
  assert.deepEqual(r.cards.map((c) => c.status), ["partial", "outside", "owned"]);
  assert.deepEqual(r.cards[0]?.finishes.map((f) => [f.code, f.owned]), [["PA", true], ["HR", false]]);
  assert.equal(bookletStatusText(r.cards[0]!), "1 de 2 acabamentos atendidos");
  assert.equal(bookletStatusText(r.cards[2]!), "Completa");
  assert.equal(bookletStatusText({ status: "missing", finishes: [{ key: "k", label: "Padrão", code: "PA", owned: false }] }), "Pendente", "Master Set: pendente, não \"falta\" (posse física ≠ objetivo)");
  assert.equal(bookletStatusText({ status: "missing", finishes: [] }), "Falta");
  assert.equal(r.outsideCards, 1);
  assert.deepEqual(r.finishLegend.map((f) => f.code), ["PA", "HR", "QA"]);
  assert.match(bookletCardAria(r.cards[0]!), /Padrão: atendido; Holográfica Reversa: pendente/);
});

test("paginação editorial: capa e abertura, 20 cartas por página, encerramento; faixa de números", () => {
  const cards = Array.from({ length: 45 }, (_, i) => card(i + 1));
  const r = build("STANDARD_SET", cards, cards.map((c, i) => pos(i + 1, i % 2 === 0)), { total: 45, satisfied: 23 });
  assert.equal(BOOKLET_CARDS_PER_PAGE, 20);
  assert.deepEqual(r.pages.map((p) => [p.pageNumber, p.cards.length]), [[3, 20], [4, 20], [5, 5]]);
  assert.equal(r.closingPage, 6);
  assert.equal(r.totalPages, 6);
  assert.equal(bookletRangeText(r.pages[0]!), "Cartas 1–20");
  assert.equal(bookletRangeText({ firstNumber: "45", lastNumber: "45" }), "Carta 45");
});

test("conferência: catálogo, posições, raridade e totais — incompleto bloqueia a impressão", () => {
  const cards = [card(1), card(2)];
  const positions = [pos(1, true), pos(2, false)];
  const canonical = { total: 2, satisfied: 1 };
  assert.equal(build("STANDARD_SET", cards, positions, canonical, { catalog: { status: "incomplete", cards, reason: "pages" } }).incompleteReason, "catalog");
  assert.equal(build("STANDARD_SET", cards, positions, canonical, { positionsComplete: false }).incompleteReason, "positions");
  assert.equal(build("STANDARD_SET", cards, positions, canonical, { rarityCatalog: { status: "unavailable" } }).incompleteReason, "catalog_unavailable");
  assert.equal(build("STANDARD_SET", [card(1), card(2, "NEW")], positions, canonical).incompleteReason, "rarity_unknown");
  assert.equal(build("STANDARD_SET", [card(1)], positions, canonical).incompleteReason, "position_outside_catalog", "posição de carta inativa/ausente do catálogo");
  assert.equal(build("STANDARD_SET", cards, [...positions, pos(1, true)], canonical).incompleteReason, "duplicate_position");
  assert.equal(build("STANDARD_SET", cards, positions, { total: 2, satisfied: 2 }).incompleteReason, "total_mismatch");
  for (const reason of ["catalog", "positions", "catalog_unavailable", "rarity_unknown", "position_outside_catalog", "duplicate_position", "total_mismatch"] as const) {
    assert.match(bookletIncompleteText(reason) ?? "", /^Caderno incompleto: /);
  }
  assert.equal(bookletIncompleteText(null), null);
});

test("catálogo paginado: total estável, sem repetição, só o Set da coleção, conjunto fechado, ordem preservada", () => {
  const rows = (ns: number[], total: number, set = "ME2.5") =>
    ns.map((n) => ({ card_id: id(n).toUpperCase(), card_name: `C${n}`, collector_number: String(n), collector_total: 3, card_set_code: set, rarity_code: "COMMON", image_path_pt: null, image_path_en: `en/${n}.webp`, total_count: total }));
  const p1 = parseCatalogPage(rows([1, 2], 3));
  const p2 = parseCatalogPage(rows([3], 3));
  const merged = mergeCatalogPages("me2.5", [p1, p2], 2);
  assert.equal(merged.status, "ok");
  assert.deepEqual(merged.status === "ok" ? merged.cards.map((c) => [c.number, c.imagePath]) : null, [["1", "en/1.webp"], ["2", "en/2.webp"], ["3", "en/3.webp"]]);
  assert.equal(mergeCatalogPages("ME2.5", [p1, null], 2).status, "incomplete");
  assert.equal(mergeCatalogPages("ME2.5", [p1, parseCatalogPage(rows([2], 3))], 2).status, "incomplete");
  assert.equal(mergeCatalogPages("ME2.5", [p1, parseCatalogPage(rows([3], 3, "ME2"))], 2).status, "incomplete");
  assert.equal(mergeCatalogPages("ME2.5", [p1, parseCatalogPage(rows([3], 4))], 2).status, "incomplete");
  assert.equal(mergeCatalogPages("ME2.5", [null], 1).status, "error");
  assert.equal(parseCatalogPage([{ card_id: id(1), card_name: "x", collector_number: "1", card_set_code: "S", rarity_code: null, total_count: 1 }]), null);
});

test("número de coleção com zeros à esquerda pelo total do Set", () => {
  assert.equal(bookletNumberText({ number: "7", total: 295 }), "007/295");
  assert.equal(bookletNumberText({ number: "TG07", total: 30 }), "TG07/30");
  assert.equal(bookletNumberText({ number: "12", total: null }), "12");
});

test("menu: 'Caderno de Cartas' é o 8º item; indisponível com motivo fora de Set padrão/Master Set", () => {
  for (const policy of ["STANDARD_SET", "MASTER_SET"]) {
    const items = collectionReportItems({ collectionId: "c", completionPolicy: policy, totalPositions: 10, satisfiedPositions: 1 });
    assert.equal(items[7]?.id, "card-booklet");
    assert.equal(items[7]?.label, "Caderno de Cartas");
    assert.equal(items[7]?.icon, "booklet");
    assert.equal(items[7]?.disabledReason, null);
    assert.deepEqual(items.slice(0, 7).map((i) => i.id), ["checklist", "missing", "set-wishlist", "set-favorites", "collection-value", "completion-history", "rarity-distribution"]);
  }
  for (const policy of ["REFERENCE_POSITION", "NONE"]) {
    assert.equal(collectionReportItems({ collectionId: "c", completionPolicy: policy, totalPositions: 1, satisfiedPositions: 0 })[7]?.disabledReason, "Para coleções de Set padrão e Master Set.");
  }
  assert.ok(read("components/reports/report-menu.tsx").includes("booklet: BookOpen"));
});

test("autorização e leituras: id e sessão validados; 5332 antes de tudo; Set da coleção autorizada; sem SQL nova", () => {
  const action = code(read("components/reports/collection-reports-action.tsx"));
  assert.ok(action.includes('{report === "card-booklet" ? <CardBookletOverlay collectionId={collectionId} onClose={() => setReport(null)} /> : null}'));
  const actions = read("app/colecoes/colecoes/[id]/relatorios/actions.ts");
  const fn = actions.slice(actions.indexOf("export async function readCardBooklet"));
  assert.ok(fn.includes('if (!isCollectionId(input?.collectionId)) return { ok: false, reason: "not_found" };'));
  assert.ok(fn.includes('if (!user) return { ok: false, reason: "not_found" };'));
  assert.ok(fn.includes("prepareCardBooklet(supabase, input.collectionId.toLowerCase())"));
  const q = code(read("lib/reports/card-booklet-queries.ts"));
  const authorize = q.indexOf("await getMyCollection(supabase, collectionId)");
  const unavailable = q.indexOf('if (kind === null || !collection.cardSetCode) return { status: "unavailable"');
  const reads = q.indexOf("await Promise.all([");
  assert.ok(authorize > 0 && unavailable > authorize && reads > unavailable, "5332 → objetivo → leituras");
  assert.ok(q.includes("readSetCatalog(rpc, collection.cardSetCode)"), "Set da coleção autorizada, nunca do navegador");
  assert.ok(q.includes('getChecklist(supabase, authorizedId, kind, "todas")'));
  assert.ok(q.includes("canonical: { total: collection.totalPositions, satisfied: collection.satisfiedPositions }"));
  assert.ok(!/\.from\(\s*["']/.test(q), "nenhuma leitura direta de tabela");
});

test("peça e impressão: página A4 própria, imagens preparadas antes de imprimir, incompleto bloqueia", () => {
  const overlay = code(read("components/reports/card-booklet-overlay.tsx"));
  assert.ok(overlay.includes("incomplete: bookletIncompleteText(data.report.incompleteReason)"));
  assert.ok(overlay.includes("preparePrint: (onProgress) => prepareBookletPrint(onProgress)"));
  const piece = code(read("components/reports/card-booklet.tsx"));
  assert.ok(piece.includes("<PrintImageGate>"), "Ctrl+P com imagens pendentes não imprime folhas sem cartas");
  assert.ok(piece.includes('loading={eager ? "eager" : "lazy"}'));
  const css = read("components/reports/card-booklet.module.css");
  assert.ok(/page: mmkyu-caderno;/.test(css) && /width: 210mm;/.test(css) && /height: 297mm;/.test(css));
  assert.ok(/grid-template-columns: repeat\(5, 34mm\)/.test(css), "5 × 4 cartas no A4");
  assert.ok(/:global\(\.dark\) \.booklet/.test(css), "tema escuro");
  const globals = read("app/globals.css");
  assert.ok(/@page mmkyu-caderno \{\s*size: A4;\s*margin: 0;/.test(globals));
  const brand = read("components/reports/booklet-brand.tsx");
  assert.ok(!/logo-full|icon-mark/.test(code(brand)), "fundo com a marca decomposta, não o logotipo");
});

test("PDF: cartas em JPEG no tamanho de impressão (o Chrome regrava WebP sem perdas) — nunca ampliadas", async () => {
  const { PRINT_JPEG_MAX_WIDTH, PRINT_JPEG_QUALITY, printJpegSize } = await import("./print-jpeg.ts");
  assert.equal(PRINT_JPEG_MAX_WIDTH, 520);
  assert.ok(PRINT_JPEG_MAX_WIDTH / (34 / 25.4) >= 300, "≥ 300 dpi na carta de 34 mm");
  assert.ok(PRINT_JPEG_QUALITY >= 0.85 && PRINT_JPEG_QUALITY <= 0.92);
  assert.deepEqual(printJpegSize(734, 1024), { width: 520, height: 725 });
  assert.deepEqual(printJpegSize(400, 558), { width: 400, height: 558 }, "imagem menor não é ampliada");
  assert.deepEqual(printJpegSize(0, 10), { width: 0, height: 0 });
  const piece = code(read("components/reports/card-booklet.tsx"));
  assert.ok(piece.includes('data-print-jpeg=""'), "cartas marcadas para a versão de impressão");
  const overlay = code(read("components/reports/card-booklet-overlay.tsx"));
  assert.ok(overlay.includes("preparePrint: (onProgress) => prepareBookletPrint(onProgress)"));
  const prep = code(read("components/reports/booklet-print-images.ts"));
  assert.ok(prep.includes('canvas.toBlob(resolve, "image/jpeg", PRINT_JPEG_QUALITY)'));
  assert.ok(prep.includes("return preparePrintImages(onProgress);"), "preparo homologado da R1-G mantido");
  assert.ok(prep.includes('fetch(src, { mode: "cors", credentials: "omit" })'));
});
