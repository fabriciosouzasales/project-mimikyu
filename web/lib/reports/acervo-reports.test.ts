// V1-14 R1-B — Relatórios do Meu acervo: catálogo (8 independentes), menu com os dois
// inventários por Card Set, relatório 01 "Inventário resumido por Card Set" (regras, leitura com
// cliente falso), posição do menu (barra de rolagem/bordas) e checagens estáticas da integração.
// O 02 ("Inventário detalhado por Card Set") é coberto em acervo-set-inventory.test.ts; a
// "Distribuição do Acervo por coleção" (Minhas coleções), em collection-distribution.test.ts.
// Executar: node --experimental-strip-types --test lib/reports/acervo-reports.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { ACERVO_REPORT_CATALOG, acervoReportMenuItems, shareText } from "./acervo-reports.ts";
import { SET_INVENTORY_MAX_ITEMS, SET_INVENTORY_PAGE, getSetSummaryReport } from "./acervo-set-inventory-queries.ts";
import { buildSetSummaryReport, setSummaryIncompleteText, setSummaryLine } from "./acervo-set-summary.ts";
import { MENU_PANEL_WIDTH, MENU_VIEWPORT_GUTTER, placeReportMenu } from "./menu-placement.ts";

const read = (path: string) => readFileSync(new URL(path, import.meta.url), "utf8");
const id = (n: number) => `00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`;

test("catálogo: oito relatórios públicos, todos implementados, na ordem aprovada (R1-I retirada)", () => {
  assert.deepEqual(
    ACERVO_REPORT_CATALOG.map((e) => e.title),
    [
      "Inventário resumido por Card Set",
      "Inventário detalhado por Card Set",
      "Valor estimado total",
      "Minhas favoritas",
      "Minha Lista de Desejos",
      "Top 10 cartas mais valiosas",
      "Cartas repetidas",
      "Distribuição por Set, raridade e idioma",
    ],
  );
  assert.equal(new Set(ACERVO_REPORT_CATALOG.map((e) => e.id)).size, 8);
  assert.ok(ACERVO_REPORT_CATALOG.every((e) => e.implemented)); // oito públicos, nenhum em preparação
  assert.ok(!ACERVO_REPORT_CATALOG.some((e) => /cobertura de preços/i.test(e.title))); // R1-I retirada (iniciativa administrativa)
  assert.deepEqual(ACERVO_REPORT_CATALOG.filter((e) => e.implemented).map((e) => e.id), ["inventory-summary", "inventory-sets", "value", "favorites", "wishlist", "top", "duplicates", "distribution"]);
  assert.ok(ACERVO_REPORT_CATALOG.every((e) => !/coleção/i.test(e.title))); // análise por coleção mora em Minhas coleções
});

test("menu do acervo: inventários por Card Set, Valor estimado total, Minhas favoritas, Minha Lista de Desejos, Top 10, Cartas repetidas e Distribuição abrem; o restante numa única linha indisponível", () => {
  const items = acervoReportMenuItems({ totalCopies: 3 });
  assert.deepEqual(
    items.map((i) => [i.id, i.label, i.icon]),
    [
      ["inventory-summary", "Inventário resumido por Card Set", "inventory"],
      ["inventory-sets", "Inventário detalhado por Card Set", "inventory-sets"],
      ["value", "Valor estimado total", "value"],
      ["favorites", "Minhas favoritas", "favorite"],
      ["wishlist", "Minha Lista de Desejos", "wish"],
      ["top", "Top 10 cartas mais valiosas", "top"],
      ["duplicates", "Cartas repetidas", "duplicates"],
      ["distribution", "Distribuição por Set, raridade e idioma", "distribution"],
    ],
  );
  assert.equal(items[0]?.disabledReason, null);
  assert.equal(items[1]?.disabledReason, null);
  assert.equal(items[2]?.disabledReason, null);
  assert.equal(items[3]?.disabledReason, null);
  assert.equal(items[4]?.disabledReason, null);
  assert.equal(items[5]?.disabledReason, null);
  assert.equal(items[6]?.disabledReason, null);
  assert.equal(items[7]?.disabledReason, null);
  assert.equal(items.length, 8); // sem linha "em preparação"
  assert.ok(!items.some((i) => i.id === "upcoming"));
  assert.equal(acervoReportMenuItems({ totalCopies: 0 })[7]?.disabledReason, "Adicione cartas ao acervo para gerar o relatório."); // distribuição exige exemplares
  const empty = acervoReportMenuItems({ totalCopies: 0 }); // acervo vazio
  assert.ok(empty[0]?.disabledReason && empty[1]?.disabledReason && empty[2]?.disabledReason);
  assert.equal(empty[3]?.disabledReason, null); // favoritas independem de posse
  assert.equal(empty[4]?.disabledReason, null); // desejos também
  assert.ok(empty[5]?.disabledReason); // Top 10 depende de exemplares
  assert.ok(empty[6]?.disabledReason); // repetidas também
});

const g = (set: string, copies: number) => ({ cardSetCode: set, cardSetName: `Set ${set}`, copies });

test("resumo por Card Set: exemplares, diferentes (variante + idioma), repetidas e % por Set; somas = totais", () => {
  // Set B (mais recente, vem primeiro): 3 grupos (1, 3, 2 cópias) → 6 exemplares, 3 diferentes, 3 repetidas.
  // Set A: 2 grupos (1, 1) → 2 exemplares, 2 diferentes, 0 repetidas. Mesma carta em outro idioma = outro grupo.
  const items = [g("B", 1), g("B", 3), g("B", 2), g("A", 1), g("A", 1)];
  const r = buildSetSummaryReport({ summary: { totalCopies: 8, distinctItems: 5, distinctSets: 2, duplicateCopies: 3 }, items, itemsComplete: true });
  assert.equal(r.complete, true);
  assert.deepEqual(r.sets.map((s) => [s.code, s.copies, s.distinct, s.duplicates]), [
    ["B", 6, 3, 3],
    ["A", 2, 2, 0],
  ]);
  assert.equal(r.sets.reduce((n, s) => n + s.copies, 0), r.totalCopies);
  assert.equal(r.sets.reduce((n, s) => n + s.distinct, 0), r.distinctItems);
  assert.equal(r.sets.reduce((n, s) => n + s.duplicates, 0), r.duplicateCopies);
  assert.deepEqual(r.sets.map((s) => shareText(s.copies, r.totalCopies)), ["75%", "25%"]);
  assert.equal(shareText(1, 3), "33%"); // truncado
  assert.equal(shareText(2, 3), "66%"); // nunca arredonda para cima
  assert.equal(setSummaryLine(r), "8 exemplares · 5 diferentes · 2 Card Sets");
});

test("resumo por Card Set: totais que não fecham, teto e acervo vazio", () => {
  const items = [g("A", 2)];
  for (const summary of [
    { totalCopies: 3, distinctItems: 1, distinctSets: 1, duplicateCopies: 1 }, // exemplares
    { totalCopies: 2, distinctItems: 2, distinctSets: 1, duplicateCopies: 1 }, // diferentes
    { totalCopies: 2, distinctItems: 1, distinctSets: 1, duplicateCopies: 0 }, // repetidas
    { totalCopies: 2, distinctItems: 1, distinctSets: 2, duplicateCopies: 1 }, // Sets
  ]) {
    assert.equal(buildSetSummaryReport({ summary, items, itemsComplete: true }).incompleteReason, "mismatch", JSON.stringify(summary));
  }
  assert.ok(setSummaryIncompleteText("mismatch"));
  const big = buildSetSummaryReport({ summary: { totalCopies: 2, distinctItems: 1, distinctSets: 1, duplicateCopies: 1 }, items, itemsComplete: false });
  assert.equal(big.incompleteReason, "too_large");
  const empty = buildSetSummaryReport({ summary: { totalCopies: 0, distinctItems: 0, distinctSets: 0, duplicateCopies: 0 }, items: [], itemsComplete: true });
  assert.equal(empty.complete, true);
  assert.equal(setSummaryIncompleteText(null), null);
});

type Call = { fn: string; args: unknown };
function fakeClient(handler: (fn: string, args: Record<string, unknown>) => { data: unknown; error: { code?: string } | null }, calls: Call[]) {
  return {
    rpc: (fn: string, args?: Record<string, unknown>) => {
      calls.push({ fn, args: args ?? null });
      return Promise.resolve(handler(fn, args ?? {}));
    },
  } as never;
}

/** Acervo falso com `groups` grupos variante + idioma (2 cópias cada) em 3 Sets, 50 grupos seguidos por Set. */
function fakeAcervo(groups: number, calls: Call[], broken?: string) {
  const setOf = (i: number) => `S${Math.floor(i / 50) % 3}`;
  const all = Array.from({ length: groups }, (_, i) => ({
    card_variant_id: id(i + 1),
    language_code: "en",
    card_name: `Carta ${i + 1}`,
    collector_number: String((i % 50) + 1),
    collector_total: 50,
    card_set_code: setOf(i),
    card_set_name: "Set",
    is_default_variant: true,
    variant_label: null,
    copies_count: 2,
    total_count: groups,
    total_copies: groups * 2,
  }));
  const sets = new Set(all.map((r) => r.card_set_code)).size;
  return fakeClient((fn, args) => {
    if (fn === broken) return { data: null, error: { code: "XX000" } };
    if (fn === "get_my_inventory_summary") return { data: [{ total_copies: groups * 2, distinct_items: groups, distinct_sets: sets, duplicate_copies: groups }], error: null };
    if (fn === "get_my_inventory_items") {
      const offset = Number(args.p_offset);
      return { data: all.slice(offset, offset + Number(args.p_limit)), error: null };
    }
    throw new Error(`RPC inesperada ${fn}`);
  }, calls);
}

test("leitura do resumo: acervo inteiro em SET_NUMBER, todas as páginas, sem preços e sem identificar o usuário", async () => {
  const calls: Call[] = [];
  const load = await getSetSummaryReport(fakeAcervo(120, calls), new Date("2026-11-06T12:00:00Z"));
  assert.equal(load.status, "ready");
  if (load.status !== "ready") return;
  const r = load.data.report;
  assert.equal(r.complete, true);
  assert.deepEqual(r.sets.map((s) => [s.code, s.copies, s.distinct, s.duplicates]), [
    ["S0", 100, 50, 50],
    ["S1", 100, 50, 50],
    ["S2", 40, 20, 20],
  ]);
  const pages = calls.filter((c) => c.fn === "get_my_inventory_items").map((c) => c.args as Record<string, unknown>);
  assert.equal(pages.length, Math.ceil(120 / SET_INVENTORY_PAGE));
  for (const page of pages) {
    assert.equal(page.p_sort, "SET_NUMBER");
    assert.equal(page.p_collection_id, null); // não depende da alocação
    assert.equal(page.p_without_collection, false);
  }
  assert.deepEqual([...new Set(calls.map((c) => c.fn))].sort(), ["get_my_inventory_items", "get_my_inventory_summary"]);
  assert.ok(calls.every((c) => !JSON.stringify(c.args ?? {}).match(/user|owner/i))); // dono = auth.uid() no banco
});

test("leitura do resumo: teto e falhas → incompleto/erro", async () => {
  const many = await getSetSummaryReport(fakeAcervo(SET_INVENTORY_MAX_ITEMS + 10, []));
  assert.equal(many.status, "ready");
  if (many.status === "ready") assert.equal(many.data.report.incompleteReason, "too_large");
  for (const broken of ["get_my_inventory_summary", "get_my_inventory_items"]) {
    assert.equal((await getSetSummaryReport(fakeAcervo(10, [], broken))).status, "error", broken);
  }
  assert.equal((await getSetSummaryReport(fakeAcervo(0, []))).status, "ready");
});

test("menu: afastado da barra de rolagem e das bordas, alinhado ao botão, em qualquer largura", () => {
  // Gatilho no canto direito (Acervo/Coleção): painel alinhado à borda direita da cápsula.
  for (const viewport of [1440, 1280, 1024, 768]) {
    const capsuleRight = viewport - 24;
    const p = placeReportMenu({ triggerLeft: capsuleRight - 120, triggerWidth: 116, capsuleRight, capsuleBottom: 100, viewportWidth: viewport });
    assert.ok(p.left >= MENU_VIEWPORT_GUTTER, `esquerda ${viewport}`);
    assert.ok(p.left + p.width <= viewport - MENU_VIEWPORT_GUTTER, `direita ${viewport}`);
    assert.equal(p.left + p.width, capsuleRight, `alinhado à cápsula ${viewport}`);
    assert.ok(p.notch >= 16 && p.notch <= p.width - 16);
    assert.equal(p.top, 108);
  }
  // Viewport útil menor que a cápsula (barra de rolagem descontada): ainda cabe, com margem.
  const tight = placeReportMenu({ triggerLeft: 1300, triggerWidth: 116, capsuleRight: 1420, capsuleBottom: 80, viewportWidth: 1425 });
  assert.ok(tight.left + tight.width <= 1425 - MENU_VIEWPORT_GUTTER);
  // Gatilho à esquerda: comportamento anterior (alinhado ao botão).
  const leftSide = placeReportMenu({ triggerLeft: 300, triggerWidth: 100, capsuleRight: 600, capsuleBottom: 50, viewportWidth: 1280 });
  assert.equal(leftSide.left, 294);
  // Viewport estreita: painel encolhe e fica dentro das margens.
  const narrow = placeReportMenu({ triggerLeft: 200, triggerWidth: 40, capsuleRight: 250, capsuleBottom: 60, viewportWidth: 280 });
  assert.equal(narrow.width, 280 - MENU_VIEWPORT_GUTTER * 2);
  assert.equal(narrow.left, MENU_VIEWPORT_GUTTER);
  assert.equal(MENU_PANEL_WIDTH, 288);
  // O componente usa a largura sem a barra de rolagem.
  const menu = read("../../components/reports/report-menu.tsx");
  assert.match(menu, /viewportWidth: document\.documentElement\.clientWidth/);
  assert.doesNotMatch(menu, /window\.innerWidth - PANEL_WIDTH/);
});

test("integração: Relatórios no topo do Acervo, sobreposição comum e cada inventário com leitura e folha próprias", () => {
  const view = read("../../components/colecoes/acervo/acervo-view.tsx");
  assert.match(view, /<div className=\{styles\.heroBar\}>\s*<AcervoReportsAction totalCopies=\{summary\.totalCopies\} \/>\s*<\/div>[\s\S]*<h1 className=\{styles\.title\}>Meu acervo<\/h1>/);
  const action = read("../../components/reports/acervo-reports-action.tsx");
  assert.match(action, /<ActionCapsule label="Ações do acervo">/);
  assert.match(action, /contextLabel="Do acervo"/);
  assert.match(action, /entry\.id === id && entry\.implemented/); // indisponível nunca abre
  const shell = read("../../components/reports/report-sheet-overlay.tsx");
  assert.match(shell, /<BinderOverlayShell labelledBy=\{titleId\}/);
  assert.match(shell, /data-report-overlay=""/);
  assert.match(shell, /<ReportPrintButton ready=\{ready\}/);
  assert.match(shell, /role="status" aria-live="polite"/);
  assert.match(shell, /nada foi impresso/);
  const overlay = read("../../components/reports/acervo-report-overlay.tsx");
  assert.match(overlay, /<ReportSheetOverlay/);
  assert.match(overlay, /if \(report === "inventory-sets"\) \{\s*return readSetInventoryReport\(\)/);
  assert.match(overlay, /return readSetSummaryReport\(\)/);
  assert.match(overlay, /<AcervoSetSummarySheet report=/);
  assert.match(overlay, /<AcervoSetInventorySheet report=/);
  const actions = read("../../app/colecoes/acervo/relatorios/actions.ts");
  assert.match(actions, /export async function readSetSummaryReport\(\)/);
  assert.match(actions, /export async function readSetInventoryReport\(\)/);
  const sheet = read("../../components/reports/acervo-set-summary-report.tsx");
  for (const piece of ["RelatorioFolha", "RelatorioCabecalho", "RelatorioRodape"]) assert.match(sheet, new RegExp(`<${piece}`));
  assert.match(sheet, /acervoReport\("inventory-summary"\)/);
  // Mesma identidade da folha homologada: cabeçalho → indicadores → títulos (no <thead>, repetem) → linhas → total.
  const thead = sheet.slice(sheet.indexOf("<thead>"), sheet.indexOf("</thead>"));
  assert.ok(thead.indexOf("{cabecalho}") < thead.indexOf("Indicadores do inventário"));
  assert.ok(thead.indexOf("Indicadores do inventário") < thead.indexOf(">Card Set<"));
  assert.match(thead, /<DataTableHeadRow className="border-neutral-200 text-neutral-500">/);
  for (const label of ["Exemplares", "Diferentes", "Repetidas", "%"]) assert.match(thead, new RegExp(`align="center"[^>]*>\\s*${label}\\s*<`), label);
  assert.match(sheet, /Total do acervo/);
  assert.match(sheet, /100%/);
  assert.doesNotMatch(sheet, /R\$|brl|Sem coleção/i); // sem valor e sem coleções
});
