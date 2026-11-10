// Placeholders da Pokédex (D7 §4q) — kit de fichário.
// Executar: node --experimental-strip-types --test lib/reports/pokedex-placeholders.test.ts (a partir de web/)
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import type { PokedexPosition } from "../colecoes/pokedex.ts";
import { collectionReportItems, freeCollectionReportItems, pokedexReportItems } from "./collection-checklist.ts";
import {
  GRID_MM,
  MMKYU_PUBLIC_URL,
  OPENING_PAGES,
  PLACEHOLDERS_PER_SHEET,
  PLACEHOLDER_MM,
  SHEET_MM,
  brandHost,
  buildPlaceholderKit,
  coverFanItems,
  displayUrl,
  kitPageCount,
  pdfPageOfSheet,
  printRangeExample,
  placeholderNameSize,
  placeholderNumber,
  placeholderScopeText,
  sheetHeaderText,
} from "./pokedex-placeholders.ts";
import type { SpeciesGeneration } from "./pokedex-species-report.ts";
import { encodeQr, qrSvgPath } from "./qr-code.ts";

const read = (path: string) => readFileSync(new URL(`../../${path}`, import.meta.url), "utf8");
const code = (src: string) => src.replace(/\/\*[\s\S]*?\*\/|\/\/.*$/gm, "");

// Faixas nacionais reais por geração (I..IX).
const RANGES: Array<[string, number, number, string]> = [
  ["GENERATION_I", 1, 151, "Kanto"],
  ["GENERATION_II", 152, 251, "Johto"],
  ["GENERATION_III", 252, 386, "Hoenn"],
  ["GENERATION_IV", 387, 493, "Sinnoh"],
  ["GENERATION_V", 494, 649, "Unova"],
  ["GENERATION_VI", 650, 721, "Kalos"],
  ["GENERATION_VII", 722, 809, "Alola"],
  ["GENERATION_VIII", 810, 905, "Galar"],
  ["GENERATION_IX", 906, 1025, "Paldea"],
];

function pos(n: number, gen: string, satisfied = false): PokedexPosition {
  return {
    positionId: `p${n}`,
    number: n,
    speciesId: `s${n}`,
    speciesName: `Espécie ${n}`,
    generationCode: gen,
    artworkPath: null,
    isSatisfied: satisfied,
    copiesInCollection: satisfied ? 1 : 0,
    copiesAvailable: 0,
    copiesElsewhere: 0,
    state: satisfied ? "OWNED" : "NOT_FOUND",
    representative: null,
  };
}

/** Gerações do objetivo como a F2-2 entrega (`buildPokedexSpeciesReport`). */
function generations(codes: string[]): SpeciesGeneration[] {
  return RANGES.filter(([c]) => codes.includes(c)).map(([c, from, to, region], i) => {
    const species: PokedexPosition[] = [];
    for (let n = from; n <= to; n += 1) species.push(pos(n, c, n % 7 === 0));
    return { code: c, ordinal: RANGES.findIndex(([x]) => x === c) + 1 + i * 0, name: c, region, species, satisfied: 0 };
  });
}

test("geometria: placeholder do tamanho da carta, 3 × 3 centralizado no A4", () => {
  assert.deepEqual(PLACEHOLDER_MM, { width: 63, height: 88 });
  assert.equal(PLACEHOLDERS_PER_SHEET, 9);
  assert.equal(GRID_MM.width, 189);
  assert.equal(GRID_MM.height, 264);
  assert.equal(GRID_MM.left * 2 + GRID_MM.width, SHEET_MM.width);
  assert.equal(GRID_MM.top * 2 + GRID_MM.height, SHEET_MM.height);
  assert.ok(GRID_MM.left >= 10 && GRID_MM.top >= 16, "respiro para as marcas de corte e o rodapé");
});

test("escopo = objetivo da coleção: Nacional 1.025, Kanto 151, Johto 100, Kanto + Johto 251", () => {
  const all = RANGES.map(([c]) => c);
  const cases: Array<[string[], number, number, string]> = [
    [all, 1025, 114, "Gerações I a IX"],
    [["GENERATION_I"], 151, 17, "Geração I · Kanto"],
    [["GENERATION_II"], 100, 12, "Geração II · Johto"],
    [["GENERATION_I", "GENERATION_II"], 251, 28, "Gerações I e II"],
    [["GENERATION_I", "GENERATION_III", "GENERATION_V"], 135 + 151 + 156, Math.ceil((135 + 151 + 156) / 9), "Gerações I, III e V"],
  ];
  for (const [codes, species, sheets, scope] of cases) {
    const kit = buildPlaceholderKit({ generations: generations(codes) });
    assert.equal(kit.species, species, codes.join());
    assert.equal(kit.sheets.length, sheets, codes.join());
    assert.equal(kit.scope, scope);
    assert.equal(kit.sheets.reduce((s, sh) => s + sh.items.length, 0), species);
    assert.ok(kit.sheets.slice(0, -1).every((sh) => sh.items.length === 9), "folhas cheias até a última");
  }
});

test("ordem nacional contínua (folha N = página N do fichário de 9 bolsos); uma vez por espécie", () => {
  const gens = generations(["GENERATION_I", "GENERATION_II"]);
  // A F2-2 entrega por geração; mesmo fora de ordem, o kit segue o número nacional.
  const kit = buildPlaceholderKit({ generations: [gens[1]!, { ...gens[0]!, species: [...gens[0]!.species].reverse() }] });
  const numbers = kit.sheets.flatMap((s) => s.items.map((i) => i.number));
  assert.deepEqual(numbers, Array.from({ length: 251 }, (_, i) => i + 1));
  assert.deepEqual([kit.sheets[16]!.first, kit.sheets[16]!.last], [145, 153]); // a folha atravessa Kanto → Johto
  assert.equal(kit.sheets[16]!.items[7]!.generation, "II");
  const dup = buildPlaceholderKit({ generations: [{ ...gens[0]!, species: [...gens[0]!.species, gens[0]!.species[0]!] }] });
  assert.equal(dup.species, 151, "espécie repetida entra uma vez");
  // Atendida ou pendente: o placeholder é o mesmo (sem status na peça).
  assert.ok(!("isSatisfied" in kit.sheets[0]!.items[0]!));
});

test("textos: número, cabeçalho da folha, tamanho do nome, escopo, host da marca", () => {
  assert.equal(placeholderNumber(25), "#0025");
  assert.equal(placeholderNumber(1025), "#1025");
  const kit = buildPlaceholderKit({ generations: generations(["GENERATION_I"]) });
  assert.equal(sheetHeaderText(kit.sheets[2]!, kit.sheets.length), "Folha 3 de 17 · #0019–#0027");
  assert.equal(sheetHeaderText(kit.sheets[16]!, 17), "Folha 17 de 17 · #0145–#0151");
  assert.equal(placeholderNameSize("Mew"), "regular");
  assert.equal(placeholderNameSize("Charmander"), "regular");
  assert.equal(placeholderNameSize("Iron Valiant"), "long");
  assert.equal(placeholderNameSize("Crabominable X"), "xlong");
  assert.equal(placeholderScopeText([]), "Nenhuma geração");
  assert.equal(placeholderScopeText([{ code: "GENERATION_IV", ordinal: 4, region: null }]), "Geração IV");
  assert.equal(brandHost("https://www.mmkyu.app/"), "mmkyu.app");
  assert.equal(brandHost("http://localhost:3000"), null);
  assert.equal(brandHost(undefined), null);
  assert.equal(brandHost("não é url"), null);
});

test("menu: só na Pokédex (primeiro item); Set, Master Set e livre sem o kit", () => {
  const pkx = pokedexReportItems();
  assert.deepEqual(pkx.map((i) => i.id), ["pokedex-placeholders", "pokedex-checklist", "pokedex-missing", "collection-value", "collection-composition"]);
  const item = pkx[0]!;
  assert.deepEqual([item.label, item.icon, item.disabledReason], ["Placeholders da Pokédex", "placeholders", null]);
  assert.ok(!freeCollectionReportItems().some((i) => i.id === "pokedex-placeholders"));
  for (const completionPolicy of ["STANDARD_SET", "MASTER_SET"]) {
    assert.ok(!collectionReportItems({ collectionId: "x", completionPolicy, totalPositions: 10, satisfiedPositions: 1 }).some((i) => i.id === "pokedex-placeholders"), completionPolicy);
  }
  const action = code(read("components/reports/collection-reports-action.tsx"));
  assert.ok(action.includes('report === "pokedex-placeholders" ? <PokedexPlaceholdersOverlay collectionId={collectionId}'));
  const menu = code(read("components/reports/report-menu.tsx"));
  assert.ok(menu.includes("placeholders: Scissors"));
});

test("sobreposição: mesma leitura autorizada da F2-2, impressão bloqueada se incompleta, artes em JPEG no Imprimir", () => {
  const overlay = code(read("components/reports/pokedex-placeholders-overlay.tsx"));
  assert.ok(overlay.includes("readPokedexSpeciesReport({ collectionId })"), "mesma ação: titularidade, modalidade e objetivo no servidor");
  assert.ok(overlay.includes("pokedexReportIncompleteText(data.report.incompleteReason)"));
  assert.ok(overlay.includes('preparePrintJpegs("[data-pokedex-placeholders] img[data-print-jpeg-species]"'));
  assert.ok(overlay.includes("<ReportSheetOverlay"));
  assert.ok(overlay.includes("shareInFlight"));
});

test("impressão A4: página própria de margem zero, sem o rodapé institucional; folha em mm reais", () => {
  const css = read("app/globals.css");
  assert.match(css, /@page mmkyu-placeholders \{\s*size: A4;\s*margin: 0;/);
  assert.ok(css.includes("[data-print-footer-scope]:has([data-pokedex-placeholders]) [data-print-footer-fallback]"));
  const sheetCss = read("components/reports/pokedex-placeholders.module.css");
  assert.ok(sheetCss.includes("page: mmkyu-placeholders;"));
  assert.ok(/width: 210mm;\s*height: 297mm;/.test(sheetCss));
  assert.ok(sheetCss.includes("container-type: inline-size"));
  assert.ok(sheetCss.includes("--mm: calc(100cqw / 210)"));
  const sheet = code(read("components/reports/pokedex-placeholders.tsx"));
  assert.ok(sheet.includes("<PrintImageGate>"));
  assert.ok(sheet.includes('data-print-jpeg-species=""'));
  assert.ok(!/isSatisfied|Atendida|Pendente|Completude/.test(sheet), "sem status nem completude na peça");
});

// ---------------------------------------------------------------------------
// Abertura editorial (capa + orientações) — EDITORIAL & BRANDING REFINEMENT-01

test("abertura: capa + orientações antes das folhas; Nacional = 116 páginas; Folha N = página N + 2", () => {
  const all = RANGES.map(([c]) => c);
  const kit = buildPlaceholderKit({ generations: generations(all) });
  assert.equal(OPENING_PAGES, 2);
  assert.equal(kit.sheets.length, 114, "folhas e paginação física inalteradas");
  assert.equal(kitPageCount(kit), 116);
  assert.equal(pdfPageOfSheet(1), 3);
  assert.equal(pdfPageOfSheet(114), 116);
  assert.deepEqual(printRangeExample(kit), { pages: "3–5", sheets: "as Folhas 1 a 3" });
  const kanto = buildPlaceholderKit({ generations: generations(["GENERATION_I"]) });
  assert.equal(kitPageCount(kanto), 19);
  const two = buildPlaceholderKit({ generations: [{ ...generations(["GENERATION_I"])[0]!, species: generations(["GENERATION_I"])[0]!.species.slice(0, 12) }] });
  assert.deepEqual(printRangeExample(two), { pages: "3–4", sheets: "as Folhas 1 e 2" });
  assert.equal(printRangeExample({ sheets: [] }), null);
  // O cabeçalho das folhas continua "Folha N de M" (não o número da página do PDF).
  assert.match(sheetHeaderText(kit.sheets[0]!, kit.sheets.length), /^Folha 1 de 114 · /);
});

test("endereço público provisório aprovado: QR e texto com exatamente https://mmkyu.vercel.app/", () => {
  assert.equal(MMKYU_PUBLIC_URL, "https://mmkyu.vercel.app/");
  assert.equal(displayUrl(MMKYU_PUBLIC_URL!), "mmkyu.vercel.app");
  const qr = encodeQr(MMKYU_PUBLIC_URL!)!;
  assert.ok(qr.version <= 3, "QR pequeno: módulos grandes a 30 mm");
  assert.equal(displayUrl("https://www.mmkyu.app/colecoes/"), "mmkyu.app/colecoes");
  const sheet = code(read("components/reports/pokedex-placeholders.tsx"));
  assert.ok(sheet.includes("publicUrl = MMKYU_PUBLIC_URL"));
  assert.ok(sheet.includes("{publicUrl && qr ? ("), "QR só com endereço oficial");
  assert.ok(sheet.includes('data-access="brand"'), "sem endereço: só a marca");
  assert.ok(!/https?:\/\/[a-z0-9.-]*mmkyu/i.test(sheet), "nenhum domínio no código da peça");
});

test("orientações: os quatro passos, dimensões, 9 posições, economia de impressão, descoberta e aviso de independência", () => {
  const sheet = read("components/reports/pokedex-placeholders.tsx");
  for (const text of [
    "Imprima em A4, escala 100%",
    "Recorte pelas marcações",
    "Coloque no bolso certo",
    "Troque pela carta",
    "posições</strong>",
    "Capa e orientações são opcionais",
    "Descubra o MMKYU Collector",
    "Seu fichário começa no papel.",
    "Sua coleção continua no MMKYU.",
    "não é produto oficial nem afiliado à The Pokémon Company",
  ]) assert.ok(sheet.includes(text), text);
  assert.ok(!/melhor plataforma|em breve|grátis|oficial da Pokémon/i.test(sheet), "sem promessa nem endosso");
  // Os cartões continuam com a assinatura discreta e sem QR individual.
  const card = sheet.slice(sheet.indexOf("function PlaceholderCard"), sheet.indexOf("function Ring"));
  assert.ok(card.includes("MMKYU Collector") && !card.includes("encodeQr"));
});

test("QR Code: estrutura da norma (tamanho por versão, localizadores, temporização) e caminho SVG", () => {
  for (const [text, version] of [["https://mmkyu.app", 2], ["https://exemplo.com/" + "x".repeat(60), 5], ["https://exemplo.com/" + "z".repeat(180), 10]] as const) {
    const qr = encodeQr(text)!;
    assert.equal(qr.version, version, text);
    assert.equal(qr.size, version * 4 + 17);
    const m = qr.modules;
    // Localizador no canto superior esquerdo: anel escuro 7 × 7, anel claro, núcleo 3 × 3.
    for (let i = 0; i < 7; i += 1) assert.ok(m[0]![i] && m[6]![i] && m[i]![0] && m[i]![6]);
    assert.ok(!m[1]![1] && m[3]![3] && !m[7]![7]);
    // Linha de temporização alternada.
    for (let x = 8; x < qr.size - 8; x += 1) assert.equal(m[6]![x], x % 2 === 0);
    // Módulo escuro fixo.
    assert.equal(m[qr.size - 8]![8], true);
  }
  assert.equal(encodeQr("x".repeat(400)), null, "acima da versão 10 → sem QR");
  assert.match(qrSvgPath(encodeQr("A")!), /^M4 4h1v1h-1z/);
});

test("capa: leque com os iniciais de Kanto (#0001, #0004, #0007); sem eles, as primeiras espécies do kit", () => {
  const nacional = buildPlaceholderKit({ generations: generations(RANGES.map(([c]) => c)) });
  assert.deepEqual(coverFanItems(nacional).map((p) => p.number), [1, 4, 7]);
  const johto = buildPlaceholderKit({ generations: generations(["GENERATION_II"]) });
  assert.deepEqual(coverFanItems(johto).map((p) => p.number), [152, 153, 154]);
  const tiny = buildPlaceholderKit({ generations: [{ ...generations(["GENERATION_I"])[0]!, species: generations(["GENERATION_I"])[0]!.species.slice(0, 5) }] });
  assert.deepEqual(coverFanItems(tiny).map((p) => p.number), [1, 4, 2]);
  assert.ok(code(read("components/reports/pokedex-placeholders.tsx")).includes("const fan = coverFanItems(kit);"));
});
