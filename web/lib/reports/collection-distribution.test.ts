// V1-14 R1-B — "Distribuição do Acervo por coleção" (página Minhas coleções): o relatório
// homologado antes chamado "Inventário geral e por coleção", realocado do Meu acervo em
// `CONTEXTUAL REPORT REALIGNMENT-05` sem mudar regras, layout nem impressão. Regras, leitura com
// cliente falso, menu da estante e checagens estáticas da integração. Sem rede, sem banco.
// Executar: node --experimental-strip-types --test lib/reports/collection-distribution.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { shareText } from "./acervo-reports.ts";
import { DISTRIBUTION_COLLECTION_PAGE, getCollectionDistributionReport } from "./collection-distribution-queries.ts";
import { buildCollectionDistributionReport, collectionDistributionIncompleteText, collectionDistributionSummaryLine } from "./collection-distribution.ts";
import { LIBRARY_REPORT_CATALOG, libraryReportMenuItems } from "./library-reports.ts";

const read = (path: string) => readFileSync(new URL(path, import.meta.url), "utf8");
const id = (n: number) => `00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`;

test("Minhas coleções: catálogo e menu próprios com \"Distribuição do Acervo por coleção\"", () => {
  assert.deepEqual(LIBRARY_REPORT_CATALOG.map((e) => [e.id, e.title, e.implemented]), [["distribution", "Distribuição do Acervo por coleção", true]]);
  assert.deepEqual(libraryReportMenuItems().map((i) => [i.id, i.label, i.icon, i.disabledReason]), [["distribution", "Distribuição do Acervo por coleção", "collections", null]]);
});

const summary = { totalCopies: 10, distinctItems: 7, distinctSets: 3, duplicateCopies: 3 };
const coll = (n: number, name: string, copies: number, extra: Partial<{ completionPolicy: string; lifecycleStatus: string }> = {}) => ({
  id: id(n),
  name,
  completionPolicy: extra.completionPolicy ?? "STANDARD_SET",
  lifecycleStatus: extra.lifecycleStatus ?? "ACTIVE",
  copiesCount: copies,
});

test("inventário: distribuição por coleção, sem coleção e total sem contar exemplar duas vezes", () => {
  const report = buildCollectionDistributionReport({
    summary,
    collections: [coll(1, "Base", 2), coll(2, "Fichário livre", 5, { completionPolicy: "NONE" }), coll(3, "Antiga", 1, { lifecycleStatus: "ARCHIVED", completionPolicy: "MASTER_SET" }), coll(4, "Vazia", 0)],
    unallocatedCopies: 2,
    collectionsComplete: true,
  });
  assert.equal(report.complete, true);
  assert.equal(report.allocatedCopies, 8);
  assert.equal(report.allocatedCopies + report.unallocatedCopies, report.totalCopies);
  assert.deepEqual(report.collections.map((c) => [c.name, c.copies, c.kindLabel, c.archived]), [
    ["Fichário livre", 5, "Livre", false],
    ["Base", 2, "Set", false],
    ["Antiga", 1, "Master Set", true],
  ]);
  assert.equal(report.emptyCollectionCount, 1);
  assert.equal(collectionDistributionSummaryLine(report), "10 exemplares · 7 diferentes · 3 coleções com cartas");
  assert.equal(shareText(5, 10), "50%");
  assert.equal(shareText(9999, 10000), "99%");
  assert.equal(shareText(1, 1000), "<1%");
  assert.equal(shareText(10, 10), "100%");
});

test("inventário: contas que não fecham ou coleções truncadas → incompleto (impressão bloqueada)", () => {
  const mismatch = buildCollectionDistributionReport({ summary, collections: [coll(1, "A", 4)], unallocatedCopies: 2, collectionsComplete: true });
  assert.equal(mismatch.complete, false);
  assert.equal(mismatch.incompleteReason, "mismatch");
  assert.ok(collectionDistributionIncompleteText("mismatch"));
  const truncated = buildCollectionDistributionReport({ summary, collections: [coll(1, "A", 8)], unallocatedCopies: 2, collectionsComplete: false });
  assert.equal(truncated.incompleteReason, "truncated");
  assert.equal(collectionDistributionIncompleteText(null), null);
  // Acervo vazio fecha (0 + 0 = 0).
  const empty = buildCollectionDistributionReport({ summary: { totalCopies: 0, distinctItems: 0, distinctSets: 0, duplicateCopies: 0 }, collections: [], unallocatedCopies: 0, collectionsComplete: true });
  assert.equal(empty.complete, true);
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

test("leitura: só leituras existentes do titular, coleções ativas e arquivadas paginadas, sem escrita", async () => {
  const calls: Call[] = [];
  const many = Array.from({ length: DISTRIBUTION_COLLECTION_PAGE + 3 }, (_, i) => ({
    collection_id: id(i + 1),
    name: `C${i + 1}`,
    completion_policy: "NONE",
    lifecycle_status: i === 0 ? "ARCHIVED" : "ACTIVE",
    copies_count: 1,
    total_count: DISTRIBUTION_COLLECTION_PAGE + 3,
  }));
  const client = fakeClient((fn, args) => {
    if (fn === "get_my_inventory_summary") return { data: [{ total_copies: 105, distinct_items: 100, distinct_sets: 4, duplicate_copies: 5 }], error: null };
    if (fn === "get_my_inventory_items") return { data: [{ total_count: 1, total_copies: 2 }], error: null };
    if (fn === "get_my_collections") {
      const offset = Number(args.p_offset);
      return { data: many.slice(offset, offset + Number(args.p_limit)), error: null };
    }
    throw new Error(`RPC inesperada ${fn}`);
  }, calls);
  const load = await getCollectionDistributionReport(client, new Date("2026-11-06T12:00:00Z"));
  assert.equal(load.status, "ready");
  if (load.status !== "ready") return;
  assert.equal(load.data.report.complete, true);
  assert.equal(load.data.report.allocatedCopies, 103);
  assert.equal(load.data.report.unallocatedCopies, 2);
  assert.deepEqual([...new Set(calls.map((c) => c.fn))].sort(), ["get_my_collections", "get_my_inventory_items", "get_my_inventory_summary"]);
  const pages = calls.filter((c) => c.fn === "get_my_collections");
  assert.equal(pages.length, 2);
  for (const page of pages) assert.equal((page.args as Record<string, unknown>).p_include_archived, true);
  const without = calls.find((c) => c.fn === "get_my_inventory_items")?.args as Record<string, unknown>;
  assert.equal(without.p_without_collection, true);
  // Nenhum argumento identifica o usuário: o dono é auth.uid() no banco.
  assert.ok(calls.every((c) => !JSON.stringify(c.args ?? {}).match(/user|owner/i)));
});

test("leitura: falha ou resposta fora do contrato → erro; sem exemplares fora de coleção = 0", async () => {
  const calls: Call[] = [];
  const ok = (fn: string) =>
    fn === "get_my_inventory_summary"
      ? { data: [{ total_copies: 1, distinct_items: 1, distinct_sets: 1, duplicate_copies: 0 }], error: null }
      : fn === "get_my_inventory_items"
        ? { data: [], error: null }
        : { data: [{ collection_id: id(1), name: "A", completion_policy: "NONE", lifecycle_status: "ACTIVE", copies_count: 1, total_count: 1 }], error: null };
  const fine = await getCollectionDistributionReport(fakeClient(ok, calls));
  assert.equal(fine.status, "ready");
  if (fine.status === "ready") assert.equal(fine.data.report.unallocatedCopies, 0);
  for (const broken of ["get_my_inventory_summary", "get_my_inventory_items", "get_my_collections"]) {
    const load = await getCollectionDistributionReport(fakeClient((fn) => (fn === broken ? { data: null, error: { code: "XX000" } } : ok(fn)), []));
    assert.equal(load.status, "error", broken);
  }
  const bad = await getCollectionDistributionReport(fakeClient((fn) => (fn === "get_my_collections" ? { data: [{ name: "sem id", copies_count: 1 }], error: null } : ok(fn)), []));
  assert.equal(bad.status, "error");
});

test("integração: Relatórios no topo de Minhas coleções (menu próprio) e folha homologada preservada", () => {
  const view = read("../../components/colecoes/colecoes/library-view.tsx");
  assert.match(view, /<div className=\{acervoStyles\.heroBar\}>\s*<LibraryReportsAction \/>\s*<\/div>[\s\S]*<h1 className=\{acervoStyles\.title\}>Minhas coleções<\/h1>/);
  const action = read("../../components/reports/library-reports-action.tsx");
  assert.match(action, /<ActionCapsule label="Ações de Minhas coleções">/);
  assert.match(action, /contextLabel="De Minhas coleções"/); // nunca "Desta coleção" (coleção individual)
  assert.doesNotMatch(action, /contextLabel="Desta coleção"/);
  assert.match(action, /entry\.id === id && entry\.implemented/);
  const overlay = read("../../components/reports/library-report-overlay.tsx");
  assert.match(overlay, /<ReportSheetOverlay/);
  assert.match(overlay, /readCollectionDistributionReport\(\)/);
  assert.match(overlay, /<CollectionDistributionSheet report=/);
  assert.match(read("../../app/colecoes/colecoes/relatorios/actions.ts"), /export async function readCollectionDistributionReport\(\)/);
  const sheet = read("../../components/reports/collection-distribution-report.tsx");
  for (const piece of ["RelatorioFolha", "RelatorioCabecalho", "RelatorioRodape"]) assert.match(sheet, new RegExp(`<${piece}`));
  assert.match(sheet, /libraryReport\("distribution"\)/);
  assert.match(sheet, /identificacaoColecao="Minhas coleções"/);
  assert.match(sheet, /<thead>/); // cabeçalho e colunas repetem em toda folha
  // Ordem: cabeçalho → indicadores → títulos das colunas → linhas; última coluna "%".
  const thead = sheet.slice(sheet.indexOf("<thead>"), sheet.indexOf("</thead>"));
  assert.ok(thead.indexOf("{cabecalho}") < thead.indexOf("Indicadores do inventário"));
  assert.ok(thead.indexOf("Indicadores do inventário") < thead.indexOf("Onde estão os exemplares"));
  assert.match(thead, /<DataTableHeadRow className="border-neutral-200 text-neutral-500">/); // padrão da Central
  assert.match(thead, /bg-neutral-50/);
  // Tipo, Situação, Exemplares e %: centralizados (título e células).
  for (const label of ["Tipo", "Situação", "Exemplares", "%"]) {
    assert.match(thead, new RegExp(`align="center"[^>]*>\\s*${label}\\s*<`), `título ${label}`);
  }
  for (const cell of ["{row.kind}", "{row.status}", "{formatCount(row.copies)}", "{shareText(row.copies, report.totalCopies)}"]) {
    const at = sheet.indexOf(cell);
    assert.match(sheet.slice(sheet.lastIndexOf("<td", at), at), /text-center/, `célula ${cell}`);
  }
  assert.match(thead, />\s*%\s*<\/DataTableHeadCell>/);
  assert.doesNotMatch(sheet, />Do acervo</);
  assert.match(sheet, /Sem coleção/);
  assert.match(sheet, /Arquivada/);
  assert.match(sheet, /Total do acervo/);
  assert.doesNotMatch(sheet, /R\$|brl|valor estimado/i); // inventário não mistura valor (D7.6)
  // Saiu do Meu acervo.
  const acervoOverlay = read("../../components/reports/acervo-report-overlay.tsx");
  assert.doesNotMatch(acervoOverlay + read("../../app/colecoes/acervo/relatorios/actions.ts"), /CollectionDistribution|readInventoryReport/);
});
