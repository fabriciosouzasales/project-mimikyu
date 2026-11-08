// V1-14 R2-G — "Distribuição por raridade": junção posições × raridade da carta × catálogo, ordem e
// identificação, conferência com o resumo canônico, paginação da raridade, estados incompletos,
// textos e guardas de código (menu, ação, autorização, folha, sobreposição). Sem DOM: a renderização
// visual fica para a homologação do proprietário.
// Executar: node --experimental-strip-types --test lib/reports/rarity-distribution.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { type ChecklistKind, type ChecklistRow, collectionReportItems } from "./collection-checklist.ts";
import type { RarityCatalogInput } from "./distribution.ts";
import {
  type CardRarityRead,
  RARITY_UNRESOLVED_KEY,
  bandAriaText,
  bandBarPercent,
  bandMissingText,
  bandPercentText,
  buildRarityDistribution,
  mergeRarityPages,
  parseRarityPage,
  rarityDistributionIncompleteText,
} from "./rarity-distribution.ts";

const web = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const read = (path: string) => readFileSync(resolve(web, path), "utf8");
const code = (source: string) => source.replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "").replace(/\{\/\*[\s\S]*?\*\/\}/g, "");

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const CATALOG: RarityCatalogInput = {
  status: "ok",
  entries: [
    { code: "COMMON", name: "Comum", symbolCode: "BLACK_CIRCLE", displayOrder: 1 },
    { code: "UNCOMMON", name: "Incomum", symbolCode: "BLACK_DIAMOND", displayOrder: 2 },
    { code: "RARE", name: "Rara", symbolCode: "BLACK_STAR", displayOrder: 3 },
    { code: "DOUBLE_RARE", name: "Rara Dupla", symbolCode: "BLACK_DOUBLE_STAR", displayOrder: 4 },
    { code: "ILLUSTRATION_RARE", name: "Ilustração Rara", symbolCode: "GOLD_STAR", displayOrder: 6 },
    { code: "COMMON_ALT", name: "Comum", symbolCode: "BLACK_CIRCLE", displayOrder: 7 },
  ],
};

function pos(card: number, owned: boolean, finish: string | null = null): ChecklistRow {
  const cardId = id(card);
  return { key: finish ? `${cardId}:${finish}` : cardId, number: String(card), name: `Carta ${card}`, finish, owned, copies: owned ? 1 : 0, inAcervo: false, cardId };
}

function rarities(entries: Array<[number, string]>): CardRarityRead {
  return { status: "ok", rarities: new Map(entries.map(([n, c]) => [id(n), c])), total: entries.length };
}

function build(kind: ChecklistKind, positions: ChecklistRow[], r: CardRarityRead, canonical: { total: number; satisfied: number }, catalog = CATALOG, positionsComplete = true) {
  return buildRarityDistribution({ kind, positions, positionsComplete, rarities: r, catalog, canonical });
}

test("Set padrão: uma posição por carta, agrupada pela raridade da carta, na ordem do catálogo", () => {
  const r = build(
    "STANDARD_SET",
    [pos(1, true), pos(2, false), pos(3, true), pos(4, true), pos(5, false), pos(6, false)],
    rarities([[1, "COMMON"], [2, "COMMON"], [3, "DOUBLE_RARE"], [4, "UNCOMMON"], [5, "ILLUSTRATION_RARE"], [6, "DOUBLE_RARE"]]),
    { total: 6, satisfied: 3 },
  );
  assert.equal(r.complete, true);
  assert.deepEqual(
    r.bands.map((b) => [b.key, b.expected, b.satisfied, b.missing]),
    [
      ["COMMON", 2, 1, 1],
      ["UNCOMMON", 1, 1, 0],
      ["DOUBLE_RARE", 2, 1, 1],
      ["ILLUSTRATION_RARE", 1, 0, 1],
    ],
  );
  assert.equal(r.rarityCount, 4, "só raridades presentes no objetivo");
  assert.deepEqual([r.expected, r.satisfied, r.missing, r.sumExpected, r.sumSatisfied], [6, 3, 3, 6, 3]);
  assert.equal(r.bands[0]?.label, "Comum");
  assert.equal(r.bands[0]?.symbolCode, "BLACK_CIRCLE");
});

test("Master Set: acabamentos somam na raridade da carta; nenhuma categoria de acabamento", () => {
  const r = build(
    "MASTER_SET",
    [pos(1, true, "normal"), pos(1, false, "reverse"), pos(2, true, "normal"), pos(2, true, "reverse"), pos(3, false, "secreta")],
    rarities([[1, "COMMON"], [2, "RARE"], [3, "ILLUSTRATION_RARE"]]),
    { total: 5, satisfied: 3 },
  );
  assert.equal(r.complete, true);
  assert.deepEqual(r.bands.map((b) => [b.key, b.expected, b.satisfied]), [["COMMON", 2, 1], ["RARE", 2, 2], ["ILLUSTRATION_RARE", 1, 0]]);
  assert.ok(r.bands.every((b) => !/reverse|normal|acabamento/i.test(b.label)));
});

test("mesmo nome com códigos diferentes: nunca mescla; identificação ganha o código", () => {
  const r = build("STANDARD_SET", [pos(1, true), pos(2, false)], rarities([[1, "COMMON"], [2, "COMMON_ALT"]]), { total: 2, satisfied: 1 });
  assert.deepEqual(r.bands.map((b) => [b.key, b.label, b.detail]), [["COMMON", "Comum", "COMMON"], ["COMMON_ALT", "Comum", "COMMON_ALT"]]);
});

test("conferência: soma diferente do resumo canônico → incompleto (impressão bloqueada), nada redistribuído", () => {
  const r = build("STANDARD_SET", [pos(1, true), pos(2, false)], rarities([[1, "COMMON"], [2, "RARE"]]), { total: 3, satisfied: 1 });
  assert.equal(r.complete, false);
  assert.equal(r.incompleteReason, "total_mismatch");
  assert.deepEqual([r.expected, r.sumExpected], [3, 2], "indicadores canônicos; soma das categorias exposta");
  const sat = build("STANDARD_SET", [pos(1, true), pos(2, false)], rarities([[1, "COMMON"], [2, "RARE"]]), { total: 2, satisfied: 2 });
  assert.equal(sat.incompleteReason, "total_mismatch");
});

test("posição sem raridade resolvida (ex.: carta que a busca não devolve) → grupo próprio, por último, incompleto", () => {
  const r = build("STANDARD_SET", [pos(1, true), pos(2, false)], rarities([[1, "COMMON"]]), { total: 2, satisfied: 1 });
  assert.equal(r.incompleteReason, "rarity_unresolved");
  assert.deepEqual(r.bands.map((b) => b.key), ["COMMON", RARITY_UNRESOLVED_KEY]);
  assert.equal(r.bands[1]?.label, "Sem raridade identificada");
  assert.equal(r.sumExpected, 2, "a soma continua visível");
});

test("código fora do catálogo, catálogo indisponível, posição repetida, leituras incompletas", () => {
  const unknown = build("STANDARD_SET", [pos(1, true)], rarities([[1, "NEW_RARITY"]]), { total: 1, satisfied: 1 });
  assert.equal(unknown.incompleteReason, "rarity_unknown");
  assert.deepEqual([unknown.bands[0]?.label, unknown.bands[0]?.detail], ["Raridade não reconhecida", "NEW_RARITY"]);
  const noCatalog = build("STANDARD_SET", [pos(1, true)], rarities([[1, "COMMON"]]), { total: 1, satisfied: 1 }, { status: "unavailable" });
  assert.equal(noCatalog.incompleteReason, "catalog_unavailable");
  const dup = build("STANDARD_SET", [pos(1, true), pos(1, true)], rarities([[1, "COMMON"]]), { total: 1, satisfied: 1 });
  assert.equal(dup.incompleteReason, "duplicate_position");
  assert.equal(dup.bands[0]?.expected, 1, "classificada uma única vez");
  const partial = build("STANDARD_SET", [pos(1, true)], rarities([[1, "COMMON"]]), { total: 1, satisfied: 1 }, CATALOG, false);
  assert.equal(partial.incompleteReason, "positions");
  const pages: CardRarityRead = { status: "incomplete", rarities: new Map([[id(1), "COMMON"]]), total: 2, reason: "pages" };
  assert.equal(build("STANDARD_SET", [pos(1, true)], pages, { total: 1, satisfied: 1 }).incompleteReason, "rarity_read");
  for (const reason of ["positions", "rarity_read", "catalog_unavailable", "rarity_unknown", "rarity_unresolved", "duplicate_position", "total_mismatch"] as const) {
    assert.match(rarityDistributionIncompleteText(reason) ?? "", /^Relatório incompleto: /);
  }
  assert.equal(rarityDistributionIncompleteText(null), null);
});

test("objetivo vazio e coleção completa", () => {
  const empty = build("STANDARD_SET", [], rarities([]), { total: 0, satisfied: 0 });
  assert.equal(empty.complete, true);
  assert.deepEqual(empty.bands, []);
  const full = build("STANDARD_SET", [pos(1, true), pos(2, true)], rarities([[1, "COMMON"], [2, "RARE"]]), { total: 2, satisfied: 2 });
  assert.ok(full.bands.every((b) => b.missing === 0));
  assert.equal(bandMissingText(full.bands[0]!), "Completa");
});

test("paginação da raridade: total estável, sem repetição, só o Set da coleção, conjunto fechado", () => {
  const page = (rows: Array<[number, string, string?]>, total: number) =>
    rows.map(([n, rarity, set]) => ({ card_id: id(n).toUpperCase(), rarity_code: rarity, card_set_code: set ?? "ME2.5", total_count: String(total) }));
  const p1 = parseRarityPage(page([[1, "COMMON"], [2, "RARE"]], 3));
  const p2 = parseRarityPage(page([[3, "RARE"]], 3));
  assert.ok(p1 && p2);
  const ok = mergeRarityPages("me2.5", [p1, p2], 2);
  assert.equal(ok.status, "ok");
  assert.equal(ok.status === "ok" ? ok.rarities.get(id(1)) : null, "COMMON", "ids normalizados");
  // Página faltando, repetida, de outro Set, total instável, forma inválida.
  assert.equal(mergeRarityPages("ME2.5", [p1, null], 2).status, "incomplete");
  assert.equal(mergeRarityPages("ME2.5", [p1, parseRarityPage(page([[2, "RARE"]], 3))], 2).status, "incomplete");
  assert.equal(mergeRarityPages("ME2.5", [p1, parseRarityPage(page([[3, "RARE", "ME2"]], 3))], 2).status, "incomplete");
  assert.equal(mergeRarityPages("ME2.5", [p1, parseRarityPage(page([[3, "RARE"]], 4))], 2).status, "incomplete");
  assert.equal(mergeRarityPages("ME2.5", [null], 1).status, "error");
  assert.equal(parseRarityPage([{ card_id: id(1), rarity_code: "", card_set_code: "X", total_count: 1 }]), null);
  assert.equal(parseRarityPage({}), null);
  assert.deepEqual(parseRarityPage([]), { rows: [], total: 0 });
});

test("textos e barra: regra de percentual do produto; leitura acessível", () => {
  const band = { key: "RARE", kind: "rarity" as const, label: "Rara", detail: null, symbolCode: "BLACK_STAR", expected: 1025, satisfied: 1, missing: 1024 };
  assert.equal(bandPercentText(band), "<1%");
  assert.equal(bandBarPercent(band), 1);
  assert.equal(bandPercentText({ satisfied: 39, expected: 40 }), "97%");
  assert.equal(bandAriaText(band), "Rara: 1 de 1.025 posições satisfeitas, <1%, faltam 1.024");
});

test("menu: 'Distribuição por raridade' é o 7º item; indisponível com motivo fora de Set padrão/Master Set", () => {
  for (const policy of ["STANDARD_SET", "MASTER_SET"]) {
    const items = collectionReportItems({ collectionId: "c", completionPolicy: policy, totalPositions: 100, satisfiedPositions: 62 });
    assert.deepEqual(items.map((i) => i.id), ["checklist", "missing", "set-wishlist", "set-favorites", "collection-value", "completion-history", "rarity-distribution"]);
    assert.equal(items[6]?.label, "Distribuição por raridade");
    assert.equal(items[6]?.icon, "rarity");
    assert.equal(items[6]?.disabledReason, null);
  }
  for (const policy of ["REFERENCE_POSITION", "NONE"]) {
    const items = collectionReportItems({ collectionId: "c", completionPolicy: policy, totalPositions: 10, satisfiedPositions: 1 });
    assert.equal(items[6]?.disabledReason, "Para coleções de Set padrão e Master Set.");
  }
  assert.ok(read("components/reports/report-menu.tsx").includes("rarity: Gem"));
});

test("autorização e leituras: id e sessão validados; 5332 antes de tudo; código do Set da coleção autorizada; sem SQL nova", () => {
  const action = code(read("components/reports/collection-reports-action.tsx"));
  assert.ok(action.includes('{report === "rarity-distribution" ? <RarityDistributionOverlay collectionId={collectionId} onClose={() => setReport(null)} /> : null}'));
  const actions = read("app/colecoes/colecoes/[id]/relatorios/actions.ts");
  const fn = actions.slice(actions.indexOf("export async function readRarityDistributionReport"));
  assert.ok(fn.includes('if (!isCollectionId(input?.collectionId)) return { ok: false, reason: "not_found" };'));
  assert.ok(fn.includes('if (!user) return { ok: false, reason: "not_found" };'));
  assert.ok(fn.includes("prepareRarityDistributionReport(supabase, input.collectionId.toLowerCase())"));
  const q = code(read("lib/reports/rarity-distribution-queries.ts"));
  const authorize = q.indexOf("await getMyCollection(supabase, collectionId)");
  const unavailable = q.indexOf('if (kind === null) return { status: "unavailable"');
  const reads = q.indexOf("await Promise.all([");
  assert.ok(authorize > 0 && unavailable > authorize && reads > unavailable, "5332 → objetivo → leituras");
  assert.ok(q.includes('getChecklist(supabase, authorizedId, kind, "todas")'), "mesma leitura de posições do Checklist, conjunto inteiro");
  assert.ok(q.includes("const setCode = collection.cardSetCode;"), "Set da coleção autorizada, nunca do navegador");
  assert.ok(q.includes("readRarityCatalog(rpc)"), "catálogo 5355");
  assert.ok(q.includes("canonical: { total: collection.totalPositions, satisfied: collection.satisfiedPositions }"));
  assert.ok(!/\.from\(\s*["']/.test(q), "nenhuma leitura direta de tabela");
});

test("folha e sobreposição: incompleto bloqueia a impressão; tabela única com barras; cartões no celular", () => {
  const overlay = code(read("components/reports/rarity-distribution-overlay.tsx"));
  assert.ok(overlay.includes("incomplete: rarityDistributionIncompleteText(data.report.incompleteReason)"));
  assert.ok(overlay.includes("shareInFlight("));
  const sheet = code(read("components/reports/rarity-distribution-report.tsx"));
  assert.ok(sheet.includes("sm:table print:table"), "tabela no desktop e na impressão");
  assert.ok(sheet.includes("sm:hidden print:hidden"), "cartões só no celular");
  assert.ok(sheet.includes("print:!bg-neutral-700"), "barra legível em cinza na impressão");
  assert.ok(sheet.includes('role={label ? "meter" : undefined}'), "barra acessível");
  for (const label of ['label="Completude geral"', 'label="Esperadas"', 'label="Satisfeitas"', 'label="Faltantes"']) assert.ok(sheet.includes(label), label);
  assert.ok(!/exemplares? f[ií]sicos? satisfeit/i.test(sheet), "unidade é posição");
});
