// V1-14 — bloco Locais — "Distribuição do Acervo por Local" (Quantidade de Exemplares por Local).
// Executar: node --experimental-strip-types --test lib/reports/location-distribution.test.ts (a partir de web/)
// Dados sintéticos — nenhuma quantidade real da conta do proprietário.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import {
  type DistributionLocationInput,
  UNTYPED_KIND_LABEL,
  buildLocationDistribution,
  distributionShareText,
  locationDistributionIncompleteText,
} from "./location-distribution.ts";
import { locationsReportMenuItems } from "./locations-reports.ts";

const read = (path: string) => readFileSync(new URL(`../../${path}`, import.meta.url), "utf8");
const code = (src: string) => src.replace(/\/\*[\s\S]*?\*\/|\/\/.*$/gm, "");

let seq = 0;
function loc(name: string, kindCode: string | null, cardCount: number, kindLabel: string | null = kindCode ? `Tipo ${kindCode}` : null): DistributionLocationInput {
  seq += 1;
  return { id: `00000000-0000-4000-8000-${String(seq).padStart(12, "0")}`, name, kindCode, kindLabel, cardCount };
}
function summary(locations: DistributionLocationInput[], unlocated: number) {
  const located = locations.reduce((n, l) => n + l.cardCount, 0);
  return { totalCards: located + unlocated, locatedCards: located, unlocatedCards: unlocated, locationCount: locations.length };
}

test("acervo vazio: sem percentuais inválidos; locais aparecem com 0", () => {
  const locations = [loc("F001 - Fichário Azul", "BINDER", 0)];
  const r = buildLocationDistribution({ locations, summary: summary(locations, 0), readComplete: true });
  assert.equal(r.totalCopies, 0);
  assert.equal(r.organization, "—");
  assert.equal(r.unlocatedShare, "—");
  assert.equal(r.locations[0]!.share, "—");
  assert.equal(r.locations[0]!.bar, 0);
  assert.equal(r.complete, true);
  assert.ok(!JSON.stringify(r).includes("NaN"));
  const none = buildLocationDistribution({ locations: [], summary: { totalCards: 0, locatedCards: 0, unlocatedCards: 0, locationCount: 0 }, readComplete: true });
  assert.deepEqual([none.locations.length, none.kinds.length, none.complete], [0, 0, true]);
});

test("um único recipiente; sem localização separado; reconciliação total = com local + sem localização", () => {
  const locations = [loc("BX001 - Caixa Vermelha", "BOX", 30)];
  const r = buildLocationDistribution({ locations, summary: summary(locations, 10), readComplete: true });
  assert.equal(r.totalCopies, 40);
  assert.equal(r.locatedCopies + r.unlocatedCopies, r.totalCopies);
  assert.equal(r.organization, "75,0%");
  assert.equal(r.unlocatedShare, "25,0%");
  assert.deepEqual(r.kinds.map((k) => [k.code, k.locations, k.copies, k.share]), [["BOX", 1, 30, "75,0%"]]);
  assert.ok(!r.kinds.some((k) => /localiza/i.test(k.label)), "sem localização não é um tipo de recipiente");
  assert.deepEqual([r.locations[0]!.code, r.locations[0]!.title, r.locations[0]!.bar], ["BX001", "Caixa Vermelha", 100]);
});

test("vários tipos e vários locais do mesmo tipo: agrupa pelo CÓDIGO, % sobre o acervo total, vazios com 0 e 0,0%", () => {
  const locations = [
    loc("F001 - Fichário A", "BINDER", 300, "Fichário físico"),
    loc("F002 - Fichário B", "BINDER", 100, "Fichário físico"),
    loc("ETB01 - Caixa de Treinador", "ETB", 500, "ETB"),
    loc("Gaveta", "OTHER", 0, "Outro"),
    loc("Pasta antiga", null, 50),
  ];
  const r = buildLocationDistribution({ locations, summary: summary(locations, 50), readComplete: true });
  assert.equal(r.totalCopies, 1000);
  assert.deepEqual(
    r.kinds.map((k) => [k.code, k.label, k.locations, k.copies, k.share]),
    [
      ["ETB", "ETB", 1, 500, "50,0%"],
      ["BINDER", "Fichário físico", 2, 400, "40,0%"],
      [null, UNTYPED_KIND_LABEL, 1, 50, "5,0%"],
      ["OTHER", "Outro", 1, 0, "0,0%"],
    ],
  );
  // Σ tipos = com local; Σ locais = com local.
  assert.equal(r.kinds.reduce((n, k) => n + k.copies, 0), r.locatedCopies);
  assert.equal(r.locations.reduce((n, l) => n + l.copies, 0), r.locatedCopies);
  // Local vazio listado, 0 e 0,0%; barra relativa ao maior, % sobre o total (denominadores diferentes, de propósito).
  const gaveta = r.locations.find((l) => l.title === "Gaveta")!;
  assert.deepEqual([gaveta.code, gaveta.copies, gaveta.share, gaveta.bar], [null, 0, "0,0%", 0]);
  const f001 = r.locations.find((l) => l.code === "F001")!;
  assert.equal(f001.share, "30,0%");
  assert.equal(f001.bar, 60);
  assert.equal(r.emptyLocations, 1);
  assert.equal(r.complete, true);
});

test("tipos com o mesmo rótulo e códigos diferentes não se fundem (nunca por texto)", () => {
  const locations = [loc("A", "BOX", 2, "Caixa"), loc("B", "BOX_LONG", 3, "Caixa")];
  const r = buildLocationDistribution({ locations, summary: summary(locations, 0), readComplete: true });
  assert.deepEqual(r.kinds.map((k) => k.code), ["BOX_LONG", "BOX"]);
});

test("ordem determinística: maior quantidade, depois nome (numérico, sem acento), depois id", () => {
  const locations = [loc("F10 - Fichário", "BINDER", 5), loc("F2 - Fichário", "BINDER", 5), loc("Álbum", "BINDER", 7), loc("caixa", "BOX", 0), loc("Caixa", "BOX", 0)];
  const r = buildLocationDistribution({ locations, summary: summary(locations, 0), readComplete: true });
  assert.deepEqual(r.locations.map((l) => l.code ?? l.title), ["Álbum", "F2", "F10", "caixa", "Caixa"]);
  const again = buildLocationDistribution({ locations: [...locations].reverse(), summary: summary(locations, 0), readComplete: true });
  assert.deepEqual(again.locations.map((l) => l.id), r.locations.map((l) => l.id), "independe da ordem de chegada");
});

test("percentuais: uma casa, <0,1% para participações mínimas, nunca 100,0% sem ser o total", () => {
  assert.equal(distributionShareText(1, 4062), "<0,1%");
  assert.equal(distributionShareText(576, 4062), "14,2%");
  assert.equal(distributionShareText(0, 4062), "0,0%");
  assert.equal(distributionShareText(9999, 10000), "99,9%");
  assert.equal(distributionShareText(5, 0), "—");
});

test("acervo grande: todos os locais, sem limite artificial", () => {
  const locations = Array.from({ length: 1200 }, (_, i) => loc(`L${i + 1} - Local`, i % 3 === 0 ? "BINDER" : "BOX", (i * 7) % 50));
  const r = buildLocationDistribution({ locations, summary: summary(locations, 3), readComplete: true });
  assert.equal(r.locations.length, 1200);
  assert.equal(r.complete, true);
  assert.equal(r.kinds.reduce((n, k) => n + k.locations, 0), 1200);
});

test("conferência: leitura incompleta ou totais divergentes → incompleto (impressão bloqueada), nunca ajustado", () => {
  const locations = [loc("A", "BOX", 10)];
  assert.equal(buildLocationDistribution({ locations, summary: summary(locations, 0), readComplete: false }).incompleteReason, "read");
  const off = buildLocationDistribution({ locations, summary: { totalCards: 12, locatedCards: 11, unlocatedCards: 1, locationCount: 1 }, readComplete: true });
  assert.equal(off.incompleteReason, "mismatch");
  assert.equal(off.locatedCopies, 11, "mostra o que o banco diz, sem ajustar");
  assert.equal(buildLocationDistribution({ locations, summary: { totalCards: 10, locatedCards: 10, unlocatedCards: 0, locationCount: 2 }, readComplete: true }).incompleteReason, "mismatch");
  assert.match(locationDistributionIncompleteText("read") ?? "", /bloqueada/);
  assert.match(locationDistributionIncompleteText("mismatch") ?? "", /não conferem/);
  assert.equal(locationDistributionIncompleteText(null), null);
});

test("leitura e acesso: 5219 inteira (locais + resumo), global, somente leitura; menu De Meus locais; folha A4 com FitSheet", () => {
  const queries = code(read("lib/colecoes/storage-locations-queries.ts"));
  const fn = queries.slice(queries.indexOf("export async function getLocationDistribution"), queries.indexOf("export const BINDER_READ_CONCURRENCY"));
  assert.ok(fn.includes('supabase.rpc("get_my_storage_locations")') && fn.includes('supabase.rpc("get_my_storage_summary")'));
  assert.ok(!/\.limit\(|\.range\(|p_page|storage_container_id/.test(fn), "sem limite nem leitura por local/exemplar");
  assert.ok(!/\.insert\(|\.update\(|\.delete\(|\.upsert\(/.test(queries));
  const actions = code(read("app/colecoes/locais/actions.ts"));
  const action = actions.slice(actions.indexOf("export async function readLocationDistribution"));
  assert.ok(action.includes("readLocationDistribution(): Promise"), "sem parâmetros: não depende de local selecionado nem de filtros");
  const items = locationsReportMenuItems();
  // Menu "De Meus locais": só os dois relatórios consolidados (o Inventário do Local fica nas ações do local).
  assert.deepEqual(items.map((i) => [i.id, i.disabledReason === null]), [["distribution", true], ["binders", true]]);
  const view = code(read("components/colecoes/locais/locations-view.tsx"));
  assert.ok(view.includes("<LocationsReportsAction />") && view.includes("acervoStyles.heroBar"), "mesmo lugar da ação Relatórios das outras páginas");
  const overlay = code(read("components/reports/location-distribution-overlay.tsx"));
  assert.ok(overlay.includes("<ReportSheetOverlay") && overlay.includes("<FitSheet>"), "casca única + prévia mobile da folha A4");
  assert.ok(overlay.includes("locationDistributionIncompleteText(report.incompleteReason)"));
  const sheet = code(read("components/reports/location-distribution-report.tsx"));
  for (const h of ["Exemplares físicos", "Com local definido", "Sem localização", "Organização do acervo", "Por tipo de armazenamento", "Por local", "% do acervo"]) {
    assert.ok(sheet.includes(h), h);
  }
  assert.ok(sheet.includes("<thead>") && sheet.includes("RelatorioRodape"), "cabeçalho repetido e rodapé na impressão A4");
  assert.ok(!/capacidade|bolso|ocupad/i.test(sheet.replace("Capacidade e ocupação de fichários não fazem parte deste relatório.", "")), "sem capacidade nem ocupação");
});
