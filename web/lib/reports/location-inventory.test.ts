// V1-14 — bloco Locais — "Inventário do Local" (Relação de cartas armazenadas em um local).
// Executar: node --experimental-strip-types --test lib/reports/location-inventory.test.ts (a partir de web/)
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { type InventoryItemInput, buildLocationInventory, locationInventoryIncompleteText } from "./location-inventory.ts";

const read = (path: string) => readFileSync(new URL(`../../${path}`, import.meta.url), "utf8");
const code = (src: string) => src.replace(/\/\*[\s\S]*?\*\/|\/\/.*$/gm, "");

function item(n: number, set: string, copies: number, over: Partial<InventoryItemInput> = {}): InventoryItemInput {
  return {
    cardVariantId: `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`,
    languageCode: "pt-BR",
    languageName: "Português (Brasil)",
    cardName: `Carta ${n}`,
    collectorNumber: String(n),
    collectorTotal: 88,
    cardSetCode: set,
    cardSetName: `Set ${set}`,
    isDefaultVariant: true,
    variantLabel: "Padrão",
    copiesCount: copies,
    ...over,
  };
}

// Ordem da leitura (Set e número), como a 5220 devolve.
const ITEMS = [
  item(35, "me3", 1, { isDefaultVariant: false, variantLabel: "Holográfica Reversa" }),
  item(36, "me3", 4),
  item(40, "me3", 5),
  item(40, "me3", 1, { cardVariantId: "00000000-0000-4000-8000-000000000999", isDefaultVariant: false, variantLabel: "Holográfica Reversa" }),
  item(40, "me3", 2, { cardVariantId: "00000000-0000-4000-8000-000000000998", languageCode: "en", languageName: "Inglês" }),
  item(7, "me2", 3),
];

test("agrupa por Card Set na ordem da leitura; cartas = identidades, exemplares = Σ físico", () => {
  const r = buildLocationInventory({ items: ITEMS, readComplete: true, locationCopies: 16 });
  assert.equal(r.complete, true);
  assert.deepEqual(r.sets.map((s) => [s.code, s.cards, s.copies]), [["me3", 5, 13], ["me2", 1, 3]]);
  assert.equal(r.cards, 6);
  assert.equal(r.copies, 16);
  // Mesma carta, variante e idioma diferentes = linhas distintas (nunca mescladas pelo nome).
  const forty = r.sets[0]!.lines.filter((l) => l.name === "Carta 40");
  assert.deepEqual(forty.map((l) => [l.variant, l.language, l.copies]), [["Padrão", "Português (Brasil)", 5], ["Holográfica Reversa", "Português (Brasil)", 1], ["Padrão", "Inglês", 2]]);
  assert.equal(r.sets[0]!.lines[0]!.number, "35/88");
});

test("conferência: leitura incompleta ou total diferente do local → incompleto (impressão bloqueada)", () => {
  assert.equal(buildLocationInventory({ items: ITEMS, readComplete: false, locationCopies: 16 }).incompleteReason, "read");
  assert.equal(buildLocationInventory({ items: ITEMS, readComplete: true, locationCopies: 17 }).incompleteReason, "mismatch");
  assert.match(locationInventoryIncompleteText("read") ?? "", /incompleto/);
  assert.match(locationInventoryIncompleteText("mismatch") ?? "", /não conferem/);
  assert.equal(locationInventoryIncompleteText(null), null);
});

test("local vazio: completo, sem grupos", () => {
  const r = buildLocationInventory({ items: [], readComplete: true, locationCopies: 0 });
  assert.equal(r.complete, true);
  assert.equal(r.sets.length, 0);
  assert.equal(r.copies, 0);
});

test("leitura: TODO o local (todas as páginas), só o titular, somente leitura; entrada no painel", () => {
  const queries = code(read("lib/colecoes/storage-locations-queries.ts"));
  const all = queries.slice(queries.indexOf("export async function readAllLocationItems"), queries.indexOf("export type LocationContents"));
  assert.ok(all.includes("for (let page = 2; page <= pages; page += 4)"), "todas as páginas, não só a 1ª");
  const inv = queries.slice(queries.indexOf("export async function getLocationInventory"));
  assert.ok(inv.includes("getMyStorageLocations(supabase)"), "titularidade pela 5219");
  assert.ok(inv.includes('return { status: "not_found" }'));
  assert.ok(!/\.insert\(|\.update\(|\.delete\(|\.upsert\(/.test(queries));
  const overlay = code(read("components/reports/location-inventory-overlay.tsx"));
  assert.ok(overlay.includes("<ReportSheetOverlay"));
  assert.ok(overlay.includes("locationCopies: location.cardCount"), "Σ conferida com o total do local");
  assert.ok(overlay.includes("locationInventoryIncompleteText(report.incompleteReason)"));
  const sheet = code(read("components/reports/location-inventory-report.tsx"));
  for (const h of ["Nº", "Carta", "Variante", "Idioma", "Qtd."]) assert.ok(sheet.includes(h), h);
  assert.ok(sheet.includes("<thead>") && sheet.includes("RelatorioRodape"), "cabeçalho repetido e rodapé na impressão A4");
  assert.ok(!/<img|capacidade|ocupa/i.test(sheet), "sem imagens e sem capacidade");
  const manager = code(read("components/colecoes/locais/locations-manager.tsx"));
  assert.ok(manager.includes("<LocationInventoryOverlay") && manager.includes("locationId={panel.location.id}"), "usa o local aberto");
});

test("prévia no celular: folha A4 reduzida para caber na tela; desktop e impressão intactos", async () => {
  const { A4_SCREEN_PX, sheetFitScale } = await import("./sheet-fit.ts");
  assert.equal(A4_SCREEN_PX, 794);
  assert.equal(sheetFitScale(1200), null, "desktop: sem redução");
  assert.equal(sheetFitScale(794), null);
  assert.ok(Math.abs((sheetFitScale(343) ?? 0) - 343 / 794) < 1e-9, "iPhone 375: largura inteira visível");
  assert.equal(sheetFitScale(0), null);
  const fit = code(read("components/reports/fit-sheet.tsx"));
  assert.ok(fit.includes("transform: `scale(${fit.scale})`") && fit.includes("width: A4_SCREEN_PX"), "composta na largura A4, só reduzida");
  const css = read("components/reports/fit-sheet.module.css");
  assert.ok(/@media print[\s\S]*width: auto !important;\s*transform: none !important/.test(css), "impressão sem ajuste");
  const overlay = code(read("components/reports/location-inventory-overlay.tsx"));
  assert.ok(overlay.includes("<FitSheet>") && overlay.includes("<LocationInventorySheet"), "só o Inventário do Local; outros relatórios intactos");
  const sheet = read("components/reports/location-inventory-report.tsx");
  assert.ok(sheet.includes('width: "4.25rem"') && sheet.includes('width: "8.5rem"'), "colunas da folha impressa inalteradas");
});

test("acesso (ACCESS UX REFINEMENT-01): fora do menu Relatórios; 'Imprimir inventário' no menu … do local abre a MESMA prévia do painel", async () => {
  const { locationsReportMenuItems } = await import("./locations-reports.ts");
  const items = locationsReportMenuItems();
  assert.deepEqual(items.map((i) => i.id), ["distribution", "binders"], "só os dois relatórios consolidados");
  assert.ok(!items.some((i) => /invent/i.test(i.id + i.label)), "Inventário do Local fora do menu Relatórios");

  const manager = code(read("components/colecoes/locais/locations-manager.tsx"));
  const menu = manager.slice(manager.indexOf("function ActionsMenu"), manager.indexOf("function visibleGroups"));
  const edit = menu.indexOf("Editar local");
  const print = menu.indexOf("Imprimir inventário");
  const del = menu.indexOf("Excluir local");
  assert.ok(edit > 0 && print > edit && del > print, "Editar → Imprimir inventário → Excluir");
  assert.ok(menu.indexOf('role="separator"') > print && menu.indexOf('role="separator"') < del, "separação antes de Excluir");
  assert.ok(menu.includes('choose({ kind: "report", location })'), "o local da própria linha");
  assert.ok(!/window\.print|\.print\(/.test(menu), "abre a prévia; nada é impresso automaticamente");
  assert.ok(menu.includes('choose({ kind: "edit", location })') && menu.includes('choose({ kind: "delete", location })'), "Editar e Excluir preservados");
  assert.ok(!/storageDeleteBlock\(location\)[^;]*report|canEdit|canDelete/.test(menu.slice(menu.indexOf("Imprimir"))), "não depende de editar/excluir");

  // Um só caminho de emissão: painel e menu usam o mesmo estado e a mesma casca.
  const provider = manager.slice(manager.indexOf("export function LocationsProvider"), manager.indexOf("export function NewLocationButton"));
  assert.equal((provider.match(/<LocationInventoryOverlay/g) ?? []).length, 1, "uma única prévia do inventário");
  assert.ok(provider.includes('setPanel({ kind: "report", location })'), "o botão do painel continua levando à mesma prévia");
  const panel = manager.slice(manager.indexOf("function LocationContentPanel"), manager.indexOf("function CardTile"));
  assert.ok(panel.includes("Gerar inventário deste local") && panel.includes("onClick={() => onReport(location)}"));
  // Estado único `panel`: abrir o inventário de outro local substitui o anterior; ao fechar, volta a null.
  assert.ok(provider.includes("locationId={panel.location.id}") && provider.includes("setPanel(null)"));
});
