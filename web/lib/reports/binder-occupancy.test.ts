// V1-14 — bloco Locais — "Capacidade e Ocupação de Fichários" (D7 §4t).
// Executar: node --experimental-strip-types --test lib/reports/binder-occupancy.test.ts (a partir de web/)
// Dados sintéticos — nenhuma quantidade real da conta do proprietário.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { occupancyPercent } from "../colecoes/binder-identity.ts";
import { type BinderOccupancyInput, binderOccupancyIncompleteText, buildBinderOccupancy } from "./binder-occupancy.ts";
import { locationsReportMenuItems } from "./locations-reports.ts";

const read = (path: string) => readFileSync(new URL(`../../${path}`, import.meta.url), "utf8");
const code = (src: string) => src.replace(/\/\*[\s\S]*?\*\/|\/\/.*$/gm, "");

let seq = 0;
type Occ = NonNullable<BinderOccupancyInput["occupancy"]>;
function occ(columns: number, rows: number, pages: number, s: { cards?: number; images?: number; merged?: number; reservedEmpty?: number }): Occ {
  const pockets = columns * rows * pages;
  const cards = s.cards ?? 0;
  const images = s.images ?? 0;
  const merged = s.merged ?? 0;
  const reservedEmpty = s.reservedEmpty ?? 0;
  return { columns, rows, pages, pockets, cards, images, merged, reservedEmpty, free: pockets - cards - images - merged - reservedEmpty };
}
function binder(name: string, storedCopies: number, occupancy: Occ | null): BinderOccupancyInput {
  seq += 1;
  return { id: `00000000-0000-4000-8000-${String(seq).padStart(12, "0")}`, name, storedCopies, occupancy };
}
const build = (binders: BinderOccupancyInput[], readComplete = true) => buildBinderOccupancy({ binders, readComplete });

test("nenhum fichário físico: relatório vazio coerente, sem percentuais", () => {
  const r = build([]);
  assert.deepEqual([r.binders, r.capacity, r.percent, r.complete], [0, 0, null, true]);
});

test("fichário sem fichário digital: capacidade desconhecida (nunca 0), fora do consolidado, exemplares 'sem estrutura de bolsos'", () => {
  const r = build([binder("F000 - Fichário Antigo", 75, null)]);
  const row = r.rows[0]!;
  assert.deepEqual([row.state, row.capacity, row.percent, row.outsidePockets, row.configuration], ["unlinked", null, null, null, null]);
  assert.deepEqual([r.configured, r.unlinked, r.capacity, r.percent, r.unstructuredCopies, r.outsidePockets], [0, 1, 0, null, 75, 0]);
  assert.equal(r.complete, true, "sem vínculo não é erro");
});

test("vinculado sem exemplares, parcial, total; estados reconciliam com a capacidade; percentual inteiro do painel", () => {
  const empty = binder("F001 - Vazio", 0, occ(3, 3, 10, {}));
  const partial = binder("F002 - Parcial", 30, occ(3, 3, 10, { cards: 30, images: 1, merged: 2, reservedEmpty: 20 }));
  const full = binder("F003 - Cheio", 16, occ(4, 4, 1, { cards: 16 }));
  const r = build([empty, partial, full]);
  for (const row of r.rows) assert.equal(row.capacity, (row.occupied ?? 0) + (row.reservedEmpty ?? 0) + (row.free ?? 0));
  const p = r.rows.find((x) => x.code === "F002")!;
  assert.deepEqual([p.capacity, p.cards, p.visual, p.reservedEmpty, p.free, p.occupied], [90, 30, 3, 20, 37, 33]);
  assert.equal(p.percent, occupancyPercent({ pockets: 90, cards: 30, images: 1, merged: 2 }), "mesma regra do painel Informações");
  assert.equal(p.percent, 37);
  assert.equal(r.rows.find((x) => x.code === "F001")!.percent, 0);
  assert.equal(r.rows.find((x) => x.code === "F003")!.percent, 100);
  assert.equal(r.rows.find((x) => x.code === "F003")!.configuration, "4×4 · 1 página");
});

test("reservados vazios não são ocupação nem livres; imagens e mesclagens são ocupação (visuais), sem dupla contagem", () => {
  const r = build([binder("F1 - A", 0, occ(2, 2, 1, { images: 1, merged: 2, reservedEmpty: 1 }))]);
  const row = r.rows[0]!;
  assert.deepEqual([row.occupied, row.visual, row.cards, row.reservedEmpty, row.free, row.percent], [3, 3, 0, 1, 0, 75]);
});

test("bolso travado não é estado: a ocupação só usa os estados da 5245", () => {
  const src = code(read("lib/reports/binder-occupancy.ts"));
  assert.ok(!/locked|trav/i.test(src.replace(/A trava é atributo/i, "")), "nenhuma categoria de trava");
});

test("exemplares fora de bolsos = exemplares do local − bolsos com carta; negativo → inconsistente, nunca ajustado", () => {
  const ok = build([binder("F4 - B", 76, occ(4, 4, 66, { cards: 71 }))]);
  assert.deepEqual([ok.rows[0]!.outsidePockets, ok.outsidePockets, ok.complete], [5, 5, true]);
  const bad = build([binder("F5 - C", 10, occ(3, 3, 2, { cards: 12 }))]);
  assert.equal(bad.incompleteReason, "mismatch");
  assert.equal(bad.rows[0]!.outsidePockets, -2, "a anomalia não é escondida com max(0, …)");
  const broken = build([binder("F6 - D", 0, { columns: 3, rows: 3, pages: 1, pockets: 9, cards: 0, images: 0, merged: 0, reservedEmpty: 0, free: 8 })]);
  assert.equal(broken.incompleteReason, "mismatch", "estados que não somam a capacidade");
});

test("grades diferentes, consolidação PONDERADA pela capacidade (não média dos percentuais), capacidade zero e ordem", () => {
  const big = binder("F10 - Grande", 100, occ(4, 4, 25, { cards: 100 })); // 400 bolsos, 25%
  const small = binder("F2 - Pequeno", 9, occ(3, 3, 1, { cards: 9 })); // 9 bolsos, 100%
  const zero = binder("F7 - Sem páginas", 3, occ(3, 3, 0, {}));
  const none = binder("Caixa de fichário", 4, null);
  const r = build([none, zero, big, small]);
  assert.equal(r.capacity, 409);
  assert.equal(r.occupied, 109);
  assert.equal(r.percent, Math.round((109 / 409) * 100), "ponderada");
  assert.notEqual(r.percent, Math.round((25 + 100) / 2));
  const z = r.rows.find((x) => x.code === "F7")!;
  assert.deepEqual([z.state, z.capacity, z.percent, z.outsidePockets], ["no_pockets", 0, null, 3]);
  assert.deepEqual([r.configured, r.noPockets, r.unlinked], [2, 1, 1]);
  assert.deepEqual(r.rows.map((x) => x.code ?? x.title), ["F2", "F10", "F7", "Caixa de fichário"], "configurados por ocupação desc; sem bolsos; sem vínculo ao final");
  const again = build([small, big, zero, none].map((b) => ({ ...b })));
  assert.deepEqual(again.rows.map((x) => x.id), r.rows.map((x) => x.id), "determinística");
});

test("leitura incompleta → impressão bloqueada", () => {
  assert.equal(build([binder("F8 - E", 0, occ(3, 3, 1, {}))], false).incompleteReason, "read");
  assert.match(binderOccupancyIncompleteText("read") ?? "", /bloqueada/);
  assert.match(binderOccupancyIncompleteText("mismatch") ?? "", /não conferem/);
  assert.equal(binderOccupancyIncompleteText(null), null);
});

test("leitura: só BINDER (5219), vínculo exato do fichário digital, 5245 com concorrência limitada; falha → erro; arquivada não filtrada", () => {
  const q = code(read("lib/colecoes/storage-locations-queries.ts"));
  const fn = q.slice(q.indexOf("export async function getBinderOccupancyRead"));
  assert.ok(fn.includes('supabase.rpc("get_my_storage_locations")'));
  assert.ok(fn.includes('l.kindCode === "BINDER"'), "só fichários físicos pelo código canônico");
  assert.ok(fn.includes('{ count: "exact" }') && fn.includes("layouts.count !== layouts.data.length"), "nenhum vínculo perdido por limite");
  assert.ok(fn.includes('supabase.rpc("get_my_binder_occupancy", { p_collection_id:'), "leitura homologada do painel");
  assert.ok(fn.includes("i += BINDER_READ_CONCURRENCY"), "concorrência limitada");
  assert.ok(fn.includes("if (failed) return null;"), "falha parcial → erro controlado");
  assert.ok(!/archived|arquivad/i.test(fn), "coleção arquivada não é excluída");
  assert.ok(!/\.insert\(|\.update\(|\.delete\(|\.upsert\(/.test(q));
  const actions = code(read("app/colecoes/locais/actions.ts"));
  assert.ok(actions.includes("export async function readBinderOccupancy(): Promise"), "global, sem parâmetros");
});

test("acesso e folha: menu De Meus locais; A4 com FitSheet; capacidade desconhecida nunca como 0; exceções", () => {
  assert.ok(locationsReportMenuItems().some((i) => i.id === "binders" && i.disabledReason === null));
  const action = code(read("components/reports/locations-reports-action.tsx"));
  assert.ok(action.includes('<BinderOccupancyOverlay'));
  const overlay = code(read("components/reports/binder-occupancy-overlay.tsx"));
  assert.ok(overlay.includes("<ReportSheetOverlay") && overlay.includes("<FitSheet>") && overlay.includes("binderOccupancyIncompleteText(report.incompleteReason)"));
  const sheet = code(read("components/reports/binder-occupancy-report.tsx"));
  for (const t of ["Capacidade configurada", "Ocupação consolidada", "Entre os fichários com capacidade configurada", "Capacidade desconhecida", "Exceções e qualidade da informação", "Fora de bolsos", "Reservados", "Livres"]) {
    assert.ok(sheet.includes(t), t);
  }
  assert.ok(sheet.includes("<thead>") && sheet.includes("RelatorioRodape"), "cabeçalho repetido e rodapé A4");
  assert.ok(/não é uma medição do fichário real/.test(sheet), "capacidade configurada ≠ física, dito na folha");
});
