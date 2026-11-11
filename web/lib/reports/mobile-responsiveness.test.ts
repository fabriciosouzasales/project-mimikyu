// V1-14 — CROSS-REPORT MOBILE RESPONSIVENESS CORRECTION-01: estratégia de prévia por relatório.
// Executar: node --experimental-strip-types --test lib/reports/mobile-responsiveness.test.ts (a partir de web/)
// Complementa a medição geométrica com os componentes reais (feita fora da suíte): aqui só se trava a ESTRUTURA —
// quem usa FitSheet, quem usa o cabeçalho ajustável, e que impressão e Catálogo não mudam.
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { test } from "node:test";
import { A4_SCREEN_PX, sheetFitScale } from "./sheet-fit.ts";

const read = (path: string) => readFileSync(new URL(`../../${path}`, import.meta.url), "utf8");
const code = (src: string) => src.replace(/\/\*[\s\S]*?\*\/|\/\/.*$/gm, "");
const fitWrapped = (src: string, sheet: string) => new RegExp(`<FitSheet>\\s*<${sheet}[\\s>]`).test(src);

// Grupo A — folhas de documento sem versão própria para celular: prévia proporcional (FitSheet) na casca.
const GROUP_A: Record<string, string[]> = {
  "components/reports/acervo-report-overlay.tsx": [
    "AcervoSetSummarySheet",
    "AcervoSetInventorySheet",
    "AcervoValueSheet",
    "FavoritesReportSheet",
    "WishlistReportSheet",
    "TopCardsSheet",
    "DuplicatesSheet",
    "DistributionSheet",
  ],
  "components/reports/library-report-overlay.tsx": ["CollectionDistributionSheet"],
  "components/reports/collection-composition-overlay.tsx": ["CollectionCompositionSheet"],
};

// Grupo B — conteúdo próprio para celular: SEM FitSheet; cabeçalho ajustável e tabela externa fixa.
const GROUP_B = [
  "missing-cards-report",
  "set-wishlist-report",
  "set-favorites-report",
  "collection-value-report",
  "completion-history-report",
  "rarity-distribution-report",
  "pokedex-species-report",
];
const GROUP_B_OVERLAYS = [
  "missing-cards-overlay",
  "set-wishlist-overlay",
  "set-favorites-overlay",
  "collection-value-overlay",
  "completion-history-overlay",
  "rarity-distribution-overlay",
  "pokedex-species-overlay",
];

test("Grupo A: cada folha do Acervo, de Minhas coleções e a Composição abre dentro de FitSheet", () => {
  for (const [file, sheets] of Object.entries(GROUP_A)) {
    const src = code(read(file));
    assert.ok(src.includes('import { FitSheet } from "./fit-sheet"'), file);
    for (const sheet of sheets) assert.ok(fitWrapped(src, sheet), `${sheet} em FitSheet (${file})`);
    // As folhas em si não mudam: a escala é só da casca.
    for (const sheet of sheets) assert.ok(!/FitSheet/.test(code(read(sheetFile(sheet)))), `${sheet} sem FitSheet interno`);
  }
});

test("Grupo B: sem FitSheet (leitura em tamanho natural); cabeçalho ajustável e tabela externa fixa", () => {
  for (const name of GROUP_B_OVERLAYS) assert.ok(!/FitSheet/.test(code(read(`components/reports/${name}.tsx`))), name);
  for (const name of GROUP_B) {
    const src = code(read(`components/reports/${name}.tsx`));
    assert.ok(/<RelatorioCabecalho\s+ajusteCelular/.test(src), `${name}: cabeçalho ajustável`);
    assert.ok(src.includes('<table className="w-full" style={{ borderCollapse: "collapse", tableLayout: "fixed" }}>'), `${name}: tabela externa (uma coluna) fixa`);
    assert.ok(!/<table className="w-full" style=\{\{ borderCollapse: "collapse" \}\}>/.test(src), `${name}: nenhuma tabela externa automática restante`);
  }
});

test("RelatorioCabecalho: sem a prop, exatamente o de antes; com ela, só abaixo de 640 px de tela", () => {
  const src = read("components/catalogo/relatorio-cabecalho.tsx");
  assert.ok(src.includes("ajusteCelular = false"), "padrão desligado");
  assert.ok(src.includes(': "truncate";'), "sem a prop, as linhas continuam com `truncate`");
  assert.ok(src.includes('"flex items-center justify-between gap-4 border-b-4 border-primary pb-3"'), "cabeçalho padrão intacto");
  // Com a prop: empilhar/quebrar só com `max-sm:` (inativo a partir de 640 px — e na impressão, cuja página é mais larga);
  // a partir de `sm`, o mesmo `truncate` de sempre.
  assert.ok(src.includes("max-sm:whitespace-normal") && src.includes("sm:truncate") && src.includes("max-sm:flex-col"));
  assert.ok(!/ajusteCelular[^\n]*print:/.test(src.replace(/print:px-0 print:pt-0/g, "")), "nenhuma regra de impressão nova");
});

test("Catálogo, Pricing e Locais não usam o cabeçalho ajustável (alcance restrito aos relatórios de Coleções)", () => {
  const roots = ["app/catalogo/relatorios", "app/pricing/relatorios", "components/pricing", "components/catalogo"];
  for (const root of roots) {
    for (const file of walk(root)) {
      if (file.endsWith("relatorio-cabecalho.tsx")) continue;
      assert.ok(!read(file).includes("ajusteCelular"), file);
    }
  }
  for (const name of ["location-inventory-report", "location-distribution-report", "binder-occupancy-report"]) {
    assert.ok(!read(`components/reports/${name}.tsx`).includes("ajusteCelular"), name);
  }
});

test("peças conformes preservadas: Checklist, Caderno e Placeholders sem FitSheet; Locais continuam com FitSheet", () => {
  for (const name of ["collection-report-overlay", "card-booklet-overlay", "pokedex-placeholders-overlay"]) {
    assert.ok(!/FitSheet/.test(code(read(`components/reports/${name}.tsx`))), name);
  }
  for (const name of ["location-inventory-overlay", "location-distribution-overlay", "binder-occupancy-overlay"]) {
    assert.ok(/<FitSheet>/.test(code(read(`components/reports/${name}.tsx`))), name);
  }
});

test("impressão: a escala da prévia é anulada no papel; listas de celular com coluna encolhível", () => {
  const css = read("components/reports/fit-sheet.module.css");
  assert.ok(/@media print[\s\S]*height: auto !important[\s\S]*width: auto !important;\s*transform: none !important/.test(css));
  assert.equal(sheetFitScale(1200), null, "telas largas: sem escala");
  assert.equal(sheetFitScale(A4_SCREEN_PX), null);
  assert.ok((sheetFitScale(288) ?? 1) < 0.4, "320 px: folha A4 inteira visível");
  // Várias folhas (ex.: tabelas longas): a escala é uma só sobre a altura total medida.
  const fit = code(read("components/reports/fit-sheet.tsx"));
  assert.ok(fit.includes("sheet.offsetHeight * scale") && fit.includes("observer.observe(sheet)"));
  // Lista de celular do Valor estimado da coleção: nome longo (truncate) não alarga a grade.
  const value = code(read("components/reports/collection-value-report.tsx"));
  assert.ok(value.includes('<ul className="grid grid-cols-[minmax(0,1fr)] gap-2 sm:hidden print:hidden"'));
  assert.ok(value.includes('className="grid grid-cols-[minmax(0,1fr)] gap-2">'));
});

function sheetFile(sheet: string): string {
  const map: Record<string, string> = {
    AcervoSetSummarySheet: "components/reports/acervo-set-summary-report.tsx",
    AcervoSetInventorySheet: "components/reports/acervo-set-inventory-report.tsx",
    AcervoValueSheet: "components/reports/acervo-value-report.tsx",
    FavoritesReportSheet: "components/reports/favorites-report.tsx",
    WishlistReportSheet: "components/reports/wishlist-report.tsx",
    TopCardsSheet: "components/reports/top-cards-report.tsx",
    DuplicatesSheet: "components/reports/duplicates-report.tsx",
    DistributionSheet: "components/reports/distribution-report.tsx",
    CollectionDistributionSheet: "components/reports/collection-distribution-report.tsx",
    CollectionCompositionSheet: "components/reports/collection-composition-report.tsx",
  };
  return map[sheet]!;
}

function walk(dir: string): string[] {
  const out: string[] = [];
  for (const entry of readdirSync(new URL(`../../${dir}`, import.meta.url), { withFileTypes: true })) {
    const path = `${dir}/${entry.name}`;
    if (entry.isDirectory()) out.push(...walk(path));
    else if (/\.(tsx?|css)$/.test(entry.name)) out.push(path);
  }
  return out;
}
