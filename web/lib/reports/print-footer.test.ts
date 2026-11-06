// V1-14 — rodapé institucional de impressão (INSTITUTIONAL PRINT FOOTER IMPLEMENTATION-01): regras
// puras (data/hora, textos, suporte), CSS Paged Media (caixas de margem e contadores), isolamento
// aos relatórios contextuais, proteção contra rodapé duplicado e não regressão do Checklist.
// Executar: node --experimental-strip-types --test lib/reports/print-footer.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import { CHECKLIST_LINHAS_POR_FOLHA_A4, checklistColunasA4, checklistPaginasA4 } from "../catalogo/relatorio-checklist.ts";
import {
  MIN_CHROMIUM_MARGIN_BOXES,
  PRINT_FOOTER_CENTER,
  PRINT_FOOTER_PAGE_CONTENT,
  PRINT_PAGE_NAME,
  chromiumMajor,
  cssString,
  formatPrintStamp,
  stampRule,
  supportsPagedFooter,
} from "./print-footer.ts";

const read = (path: string) => readFileSync(new URL(path, import.meta.url), "utf8");
const css = read("../../app/globals.css");
const pageRule = css.slice(css.indexOf(`@page ${PRINT_PAGE_NAME} {`), css.indexOf("@media print", css.indexOf(`@page ${PRINT_PAGE_NAME} {`)));
const footerPrintBlock = css.slice(css.indexOf("@media print", css.indexOf(`@page ${PRINT_PAGE_NAME} {`)));

test("1. data/hora: dd/MM/yyyy HH:mm no horário local, 24 h e zeros à esquerda", () => {
  assert.equal(formatPrintStamp(new Date(2026, 10, 6, 9, 5)), "06/11/2026 09:05");
  assert.equal(formatPrintStamp(new Date(2026, 0, 1, 0, 0)), "01/01/2026 00:00");
  assert.equal(formatPrintStamp(new Date(2026, 11, 31, 23, 59)), "31/12/2026 23:59");
  assert.equal(formatPrintStamp(new Date(2026, 10, 6, 14, 30, 59)), "06/11/2026 14:30"); // sem segundos
  assert.match(formatPrintStamp(new Date()), /^\d{2}\/\d{2}\/\d{4} \d{2}:\d{2}$/);
});

test("2. textos institucionais exatos nas três áreas", () => {
  assert.equal(PRINT_FOOTER_CENTER, "Gerado por MMKYU Collector");
  for (const box of ["@bottom-left", "@bottom-center", "@bottom-right"]) assert.ok(pageRule.includes(`${box} {`), box);
  assert.match(pageRule, /@bottom-center \{\s*content: "Gerado por MMKYU Collector";/);
  assert.match(pageRule, /@bottom-left \{\s*content: "";/); // preenchida pela regra dinâmica
  assert.match(pageRule, /text-align: left;[\s\S]*text-align: center;[\s\S]*text-align: right;/);
  const component = read("../../components/reports/print-footer.tsx");
  assert.match(component, /<span>\{PRINT_FOOTER_CENTER\}<\/span>/); // rodapé alternativo, mesmo texto
});

test("3. contadores nativos: \"Página \" counter(page) \" de \" counter(pages); margem própria, A4", () => {
  assert.equal(PRINT_FOOTER_PAGE_CONTENT, '"Página " counter(page) " de " counter(pages)');
  assert.ok(pageRule.includes(`@bottom-right {\n    content: ${PRINT_FOOTER_PAGE_CONTENT};`));
  assert.match(pageRule, /size: A4;/);
  assert.match(pageRule, /margin: 10mm 10mm 14mm 10mm;/); // rodapé na margem, fora da área do conteúdo
  assert.doesNotMatch(pageRule, /Página X de Y|counter\(pages\)\s*-|\d+ de \d+"/); // nada fixo ou estimado
  // Data/hora: regra dinâmica segura, sobrepondo só a caixa da esquerda.
  assert.equal(stampRule("06/11/2026 09:05"), `@page ${PRINT_PAGE_NAME} { @bottom-left { content: "06/11/2026 09:05"; } }`);
  assert.equal(cssString('a"b\\c\nd'), '"a\\"b\\\\c d"');
});

test("4. suporte: só Chrome/Edge 131+ com regras de margem interpretadas; resto → rodapé alternativo", () => {
  const chrome = (v: string) => [{ brand: "Not A(Brand", version: "99" }, { brand: "Google Chrome", version: v }, { brand: "Chromium", version: v }];
  const edge = (v: string) => [{ brand: "Microsoft Edge", version: v }, { brand: "Chromium", version: v }];
  assert.equal(MIN_CHROMIUM_MARGIN_BOXES, 131);
  assert.equal(supportsPagedFooter({ marginRulesParsed: true, brands: chrome("131") }), true);
  assert.equal(supportsPagedFooter({ marginRulesParsed: true, brands: edge("142") }), true);
  assert.equal(supportsPagedFooter({ marginRulesParsed: true, brands: chrome("130") }), false);
  assert.equal(supportsPagedFooter({ marginRulesParsed: false, brands: chrome("140") }), false); // UA sozinho não basta
  assert.equal(supportsPagedFooter({ marginRulesParsed: true, brands: null }), false); // Firefox/Safari: sem UA-CH
  assert.equal(supportsPagedFooter({ marginRulesParsed: true, brands: [{ brand: "Google Chrome", version: "140" }] }), false);
  assert.equal(chromiumMajor([{ brand: "Chromium", version: "abc" }]), null);
  assert.equal(chromiumMajor(undefined), null);
  // Fallback sempre presente sem a marca de suporte; a marca só existe com o componente montado.
  assert.match(footerPrintBlock, /html:not\(\[data-print-footer="paged"\]\) \[data-print-footer-scope\] \[data-print-footer-fallback\] \{\s*display: grid !important;/);
  const component = read("../../components/reports/print-footer.tsx");
  assert.match(component, /if \(supportsPagedFooter\(\{ marginRulesParsed: marginRulesParsed\(\), brands: brands\(\) \}\)\) root\.dataset\.printFooter = "paged";/);
  assert.match(component, /delete root\.dataset\.printFooter;/);
});

test("5. isolamento: regras só no escopo dos relatórios contextuais; Catálogo e Pricing intocados", () => {
  // Toda regra do bloco de impressão do rodapé é escopada por [data-print-footer-scope].
  const selectors = [...footerPrintBlock.matchAll(/\n\s*([^{}\n/][^{}]*)\{/g)].map((m) => m[1]!.trim()).filter((s) => !s.startsWith("@"));
  assert.ok(selectors.length >= 6);
  for (const selector of selectors) assert.match(selector, /\[data-print-footer-scope\]/, selector);
  assert.equal((css.match(/page: mmkyu-relatorio;/g) ?? []).length, 1); // página nomeada só no modo paginado do escopo
  // Escopo nas três cascas + rota direta do Checklist; PrintFooter uma vez em cada.
  for (const file of ["report-sheet-overlay.tsx", "collection-report-overlay.tsx", "collection-checklist-report.tsx"]) {
    const source = read(`../../components/reports/${file}`);
    assert.match(source, /data-print-footer-scope=""/, file);
    assert.equal((source.match(/<PrintFooter \/>/g) ?? []).length, 1, file);
  }
  // Os sete relatórios abrem nessas cascas.
  const acervo = read("../../components/reports/acervo-report-overlay.tsx");
  for (const sheet of ["AcervoSetSummarySheet", "AcervoSetInventorySheet", "AcervoValueSheet", "FavoritesReportSheet", "WishlistReportSheet"]) assert.match(acervo, new RegExp(`<${sheet} `), sheet);
  assert.match(acervo, /<ReportSheetOverlay/);
  assert.match(read("../../components/reports/library-report-overlay.tsx"), /<ReportSheetOverlay/); // Distribuição por coleção
  assert.match(read("../../components/reports/collection-report-overlay.tsx"), /<ChecklistReportBody/); // Checklist Set e Master Set
  // Central do Catálogo e Pricing: nenhum escopo, nenhum PrintFooter.
  const root = fileURLToPath(new URL("../../", import.meta.url));
  const files = (dir: string): string[] =>
    readdirSync(dir).flatMap((name) => {
      const path = join(dir, name);
      return statSync(path).isDirectory() ? files(path) : /\.tsx?$/.test(name) ? [path] : [];
    });
  for (const dir of ["app/catalogo", "app/pricing", "components/pricing"]) {
    for (const file of files(join(root, dir))) {
      const source = readFileSync(file, "utf8");
      assert.doesNotMatch(source, /data-print-footer-scope|<PrintFooter|stampPrintFooter/, file);
    }
  }
});

test("6. sem alteração em regras e dados: rodapé não lê banco nem recebe dados de relatório", () => {
  const lib = read("./print-footer.ts");
  const component = read("../../components/reports/print-footer.tsx");
  for (const source of [lib, component]) {
    assert.doesNotMatch(source, /supabase|\.rpc\(|fetch\(|from "\.\/(acervo|favorites|wishlist|collection)/);
  }
  assert.match(component, /export function PrintFooter\(\) \{/); // sem props: nada do relatório entra no rodapé
});

test("7. sem rodapé duplicado: um rodapé por modo, uma regra de data/hora, listener removido", () => {
  assert.match(footerPrintBlock, /\[data-print-footer-scope\] \[data-relatorio-rodape\] \{\s*display: none !important;/); // genérico sai nos dois modos
  assert.match(footerPrintBlock, /html\[data-print-footer="paged"\] \[data-print-footer-scope\] \[data-checklist-rodape\] \{\s*display: none !important;/);
  assert.match(footerPrintBlock, /html\[data-print-footer="paged"\] \[data-print-footer-scope\] \.relatorio-folha \{\s*page: mmkyu-relatorio;\s*padding-bottom: 0 !important;/);
  assert.match(footerPrintBlock, /:has\(\[data-checklist-folha\]\) \[data-print-footer-fallback\] \{\s*display: none !important;/); // Checklist alternativo: só o homologado
  assert.match(read("../../components/catalogo/relatorio-rodape.tsx"), /<p data-relatorio-rodape="" className=/);
  assert.match(read("../../components/catalogo/relatorio-checklist-tabela.tsx"), /<div data-checklist-rodape="" className="mt-auto grid/);
  const component = read("../../components/reports/print-footer.tsx");
  assert.match(component, /const STYLE_ID = "mmkyu-print-stamp";/);
  assert.match(component, /let style = document\.getElementById\(STYLE_ID\);/); // uma única regra, reaproveitada
  assert.match(component, /window\.addEventListener\("beforeprint", onBeforePrint\);[\s\S]*window\.removeEventListener\("beforeprint", onBeforePrint\);/);
  const button = read("../../components/reports/report-print-button.tsx");
  assert.match(button, /if \(!ready\) return;\s*\/\/[^\n]*\n\s*stampPrintFooter\(\);/); // hora gravada antes de abrir a impressão
});

test("8. Checklist sem regressão: distribuição das cartas inalterada (1, 2 e várias folhas; 2–4 colunas)", () => {
  assert.equal(CHECKLIST_LINHAS_POR_FOLHA_A4, 50);
  const cases: [number, number, number][] = [
    // [posições, colunas, folhas]
    [1, 2, 1],
    [46, 2, 1],
    [92, 2, 1],
    [93, 3, 1],
    [138, 3, 1],
    [150, 4, 1],
    [200, 4, 1],
    [201, 4, 2],
    [403, 4, 3],
  ];
  for (const [total, columns, sheets] of cases) {
    const { colunas, paginas } = checklistPaginasA4(total);
    assert.equal(colunas, columns, `colunas ${total}`);
    assert.equal(colunas, checklistColunasA4(total));
    assert.equal(paginas.length, sheets, `folhas ${total}`);
    assert.equal(paginas.reduce((n, p) => n + p.tamanho, 0), total); // nenhuma linha perdida
    for (const page of paginas) assert.ok(page.linhas <= CHECKLIST_LINHAS_POR_FOLHA_A4);
  }
  // Modo paginado: a altura mínima sai (o rodapé está na margem); a quebra entre folhas continua.
  assert.match(footerPrintBlock, /\[data-checklist-folha\] \{\s*min-height: 0 !important;/);
  const sheet = read("../../components/catalogo/relatorio-checklist-tabela.tsx");
  assert.match(sheet, /breakAfter: ultima \? "auto" : "page"/);
  assert.match(sheet, /Página \{paginaIndex \+ 1\} de \{paginas\.length\}/); // rodapé homologado preservado (tela e modo alternativo)
});
