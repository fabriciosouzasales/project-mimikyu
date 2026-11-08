// V1-14 R2-E — E3 (interface e indicadores): menu, textos de linha e guardas de código da folha,
// da sobreposição e da ação. O executor de testes do projeto (Node, sem DOM) não renderiza `.tsx`:
// a renderização visual fica para a homologação do proprietário; aqui ficam as regras e as guardas.
// Executar: node --experimental-strip-types --test lib/reports/collection-value-ui.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { collectionReportItems } from "./collection-checklist.ts";
import {
  type CollectionValueItemInput,
  type CollectionValueLine,
  buildCollectionValueReport,
  collectionValueCollectorText,
  collectionValueLanguageText,
  collectionValueLineText,
  collectionValueObservedText,
  collectionValueUnitText,
  collectionValueVariantText,
} from "./collection-value.ts";

const web = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const read = (path: string) => readFileSync(resolve(web, path), "utf8");
const code = (source: string) => source.replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "").replace(/\{\/\*[\s\S]*?\*\/\}/g, "");
const sp = (text: string) => text.replace(/\s/g, " ");

const sheet = read("components/reports/collection-value-report.tsx");
const overlay = read("components/reports/collection-value-overlay.tsx");
const action = read("components/reports/collection-reports-action.tsx");
const actions = read("app/colecoes/colecoes/[id]/relatorios/actions.ts");
const shell = read("components/reports/report-sheet-overlay.tsx");

test("menu: cinco relatórios na ordem, os quatro publicados intactos; R2-E só em Set padrão e Master Set", () => {
  for (const policy of ["STANDARD_SET", "MASTER_SET"]) {
    const items = collectionReportItems({ collectionId: "c", completionPolicy: policy, totalPositions: 100, satisfiedPositions: 62 });
    assert.deepEqual(items.map((item) => item.id), ["checklist", "missing", "set-wishlist", "set-favorites", "collection-value"]);
    assert.deepEqual(items.map((item) => item.label), ["Checklist de completude", "Cartas faltantes", "Cartas desejadas do Card Set", "Cartas favoritas do Card Set", "Valor estimado"]);
    const value = items[4];
    assert.equal(value?.icon, "value");
    assert.equal(value?.disabledReason, null);
    assert.equal(value?.href, null);
    assert.ok(items[0]?.metric?.includes("62"), "métrica do Checklist preservada");
    assert.equal(items[1]?.metric, "38 faltam"); // métrica das Cartas faltantes preservada
  }
  for (const policy of ["POKEDEX", "REFERENCE_POSITION", "NONE"]) {
    const items = collectionReportItems({ collectionId: "c", completionPolicy: policy, totalPositions: 10, satisfiedPositions: 1 });
    assert.equal(items.length, 5);
    assert.ok(items.every((item) => item.disabledReason === "Para coleções de Set padrão e Master Set."));
  }
});

test("textos de linha: A mostra valores; B e C rótulos inequívocos, nunca zero", () => {
  const base = {
    collectorNumber: "12",
    collectorTotal: 158,
    variantLabel: null,
    isDefaultVariant: true,
    languageName: "Português",
    languageCode: "pt-BR",
    observedAt: "2026-11-01T00:00:00Z",
  } as const;
  const a = { ...base, state: "priced", unitCents: 1250, lineCents: 3750 } as CollectionValueLine;
  const b = { ...base, state: "unpriced", unitCents: null, lineCents: null } as CollectionValueLine;
  const c = { ...base, state: "unavailable", unitCents: null, lineCents: null } as CollectionValueLine;
  assert.equal(sp(collectionValueUnitText(a)), "R$ 12,50");
  assert.equal(sp(collectionValueLineText(a)), "R$ 37,50");
  assert.equal(collectionValueUnitText(b), "Sem cotação");
  assert.equal(collectionValueLineText(b), "—");
  assert.equal(collectionValueUnitText(c), "Preço indisponível");
  assert.equal(collectionValueLineText(c), "Indisponível");
  assert.ok(collectionValueObservedText(a)?.startsWith("obs. "));
  assert.equal(collectionValueObservedText(b), null);
  assert.equal(collectionValueCollectorText(a), "12/158");
  assert.equal(collectionValueCollectorText({ collectorNumber: null, collectorTotal: null }), "—");
  assert.equal(collectionValueVariantText(a), "Padrão");
  assert.equal(collectionValueVariantText({ variantLabel: "Holográfica", isDefaultVariant: false }), "Holográfica");
  assert.equal(collectionValueLanguageText(a), "Português");
});

test("folha: nenhum cálculo financeiro nem leitura de preço no cliente; só textos do núcleo", () => {
  const body = code(sheet);
  assert.ok(!/\bcents\s*[*/+-]|\*\s*100|\/\s*100\b|\.reduce\(/.test(body), "sem aritmética monetária na folha");
  assert.ok(!/pricing|readVariantPrices|get_card_variants_pricing_summary|supabase/.test(body), "sem Pricing nem banco");
  assert.ok(!/router\.refresh\(\)/.test(body));
  for (const helper of ["collectionValueTotalText", "collectionValueCoverageText", "collectionValueUnitText", "collectionValueLineText", "collectionValuePriceFlags", "collectionValueNotes"]) {
    assert.ok(body.includes(helper), `usa ${helper}`);
  }
  // Três indicadores, exatamente.
  assert.equal(body.match(/<Indicator\s/g)?.length, 3);
  for (const label of ['label="Valor estimado"', 'label="Exemplares alocados"', 'label="Sem cotação"']) assert.ok(body.includes(label));
  // Estados: vazio, provisório/incompleto identificados, fora da soma rotulado.
  assert.ok(body.includes("Nenhum exemplar alocado a esta coleção."));
  assert.ok(body.includes("não definitivo — relatório incompleto"));
  assert.ok(body.includes("Fora da soma"));
  // Valores monetários à direita e algarismos tabulares; celular em cartões de uma coluna.
  assert.ok(body.includes("text-right") && body.includes("tabular-nums"));
  assert.ok(body.includes("sm:table") && body.includes("sm:hidden"));
  // Mesmo componente da tela (E3 homologada): as partes de tela só ganharam `print:hidden`.
  assert.ok(body.includes("sm:table print:hidden") && body.includes("sm:hidden print:hidden"));
});

test("sobreposição: uma leitura por abertura (shareInFlight); impressão bloqueada só por integridade ou falha de preço; sem bloqueio transitório", () => {
  const body = code(overlay);
  assert.ok(body.includes("shareInFlight(() => readCollectionValueReport({ collectionId }))"));
  assert.ok(/!report\.complete \? collectionValueIncompleteText\(report\.incompleteReason\) : report\.provisional \? COLLECTION_VALUE_PROVISIONAL_TEXT : null;/.test(body));
  // Ausência legítima de cotação não entra na condição (só complete/provisional).
  assert.ok(!/unpriced/.test(body));
  // Bloqueio transitório da E3 removido por completo (código, testes de tela e textos).
  for (const source of [overlay, sheet]) assert.ok(!/PRINT_PENDING|ainda não está disponível|printUnavailable/.test(source));
  // Miniaturas preparadas antes de imprimir (R1-G), só com linhas.
  assert.ok(body.includes("preparePrint: report.lines.length > 0 ? (onProgress) => preparePrintImages(onProgress) : undefined"));
  assert.ok(!/router\.refresh\(\)/.test(body));
  // A casca homologada não foi alterada: qualquer motivo em `incomplete` bloqueia o botão e o Ctrl+P.
  assert.ok(code(shell).includes("const ready = entry.status === \"ready\" && incomplete === null;"));
});

test("impressão A4: cabeçalho repetido, títulos de coluna repetidos, KPIs só na 1ª, linhas fixas indivisíveis, miniaturas preparadas, total e notas no fim", () => {
  const body = code(sheet);
  // Cabeçalho institucional no <thead> da tabela externa (repete em toda folha).
  assert.ok(/<thead>\s*<tr>\s*<th className="p-0 text-left font-normal">\s*<div className="-mx-4 sm:-mx-6 print:mx-0">\{cabecalho\}<\/div>/.test(body));
  // KPIs fora de qualquer <thead> (só na 1ª folha) e em três colunas na impressão.
  const kpiAt = body.indexOf('aria-label="Indicadores do valor estimado"');
  assert.ok(kpiAt > body.indexOf("<tbody>"));
  assert.ok(body.includes("sm:grid-cols-3 print:grid-cols-3"));
  // Tabela de impressão: títulos no <thead>, sem caixa de marcação, valores à direita.
  const print = body.slice(body.indexOf("function PrintTable"), body.indexOf("function PrintRow"));
  assert.ok(/<thead>[\s\S]*Carta[\s\S]*Qtd\.[\s\S]*Referência NM[\s\S]*Valor[\s\S]*<\/thead>/.test(print));
  assert.ok(!/checkbox|\bbox\b|□/i.test(print));
  assert.ok(print.includes("text-right"));
  // Ordem: cotadas → faixa "Fora da soma" (presa à seguinte) → fora da soma → total.
  const order = ["priced.map", "Fora da soma", "outside.map", "Valor estimado"].map((token) => print.indexOf(token));
  assert.ok(order.every((at, i) => at > 0 && (i === 0 || at > (order[i - 1] as number))));
  assert.ok(print.includes('breakInside: "avoid", breakAfter: "avoid"'));
  // Linhas de altura fixa em mm, indivisíveis; miniatura na proporção da carta.
  const row = body.slice(body.indexOf("function PrintRow"), body.indexOf("function Thumb"));
  assert.ok(row.includes("height: `${COLLECTION_VALUE_PRINT_ROW_MM}mm`, breakInside: \"avoid\", pageBreakInside: \"avoid\""));
  assert.ok(row.includes("Sem imagem no catálogo"));
  assert.ok(row.includes('loading="lazy"'), "miniaturas impressas só carregam no preparo");
  const thumb = sheet.match(/COLLECTION_VALUE_PRINT_THUMB_MM = \{ width: ([\d.]+), height: ([\d.]+) \}/);
  const rowMm = Number(sheet.match(/COLLECTION_VALUE_PRINT_ROW_MM = ([\d.]+);/)?.[1]);
  assert.ok(thumb);
  const [w, h] = [Number(thumb[1]), Number(thumb[2])];
  assert.ok(Math.abs(w / h - 63 / 88) < 0.01, "proporção da carta");
  assert.ok(rowMm >= h && rowMm >= 6.2, "linha comporta a miniatura e o piso de legibilidade (§2)");
  assert.ok(row.includes("text-[11px]"), "nome no piso de 11 px");
  // A tabela de impressão está dentro do gate de miniaturas (Ctrl+P com pendência imprime só o aviso).
  assert.ok(/<PrintImageGate>\s*<PrintTable /.test(body));
  assert.ok(body.includes('<div className="hidden print:block">'));
  // Notas no fim, indivisíveis.
  assert.ok(/notes\.map[\s\S]*<\/ul>/.test(body) && body.indexOf("notes.map") > body.indexOf("<PrintTable"));
});

test("abertura pelo menu e ação do servidor: id validado, coleção autorizada, cálculo no servidor", () => {
  assert.ok(code(action).includes('{report === "collection-value" ? <CollectionValueOverlay collectionId={collectionId} onClose={() => setReport(null)} /> : null}'));
  for (const id of ["checklist", "missing", "set-wishlist", "set-favorites"]) assert.ok(action.includes(`report === "${id}"`), `${id} preservado`);
  const fn = actions.slice(actions.indexOf("export async function readCollectionValueReport"));
  assert.ok(fn.includes("if (!isCollectionId(input?.collectionId)) return { ok: false, reason: \"not_found\" };"));
  assert.ok(fn.includes("if (!user) return { ok: false, reason: \"not_found\" };"));
  assert.ok(fn.includes("prepareCollectionValueReport(supabase, input.collectionId.toLowerCase(), imageUrl)"));
});

test("elegibilidade (cenários): todas cotadas e ausência legítima de cotação imprimem; falha de preço e divergência bloqueiam; vazio imprime", () => {
  const item = (n: number, copies = 1): CollectionValueItemInput => ({
    cardVariantId: `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`,
    languageCode: "en",
    cardName: `Carta ${n}`,
    collectorNumber: String(n),
    collectorTotal: 10,
    cardSetCode: "ME5.5",
    cardSetName: "Celebração",
    variantLabel: null,
    isDefaultVariant: true,
    copies,
    order: n,
  });
  const id = (n: number) => item(n).cardVariantId;
  const run = (items: CollectionValueItemInput[], priced: number[], unavailable: number[] = [], expectedCopies?: number) => {
    const copies = items.reduce((sum, i) => sum + i.copies, 0);
    return buildCollectionValueReport({
      items,
      prices: new Map(priced.map((n) => [id(n), { brl: n, basis: "VARIANT" as const, observedAt: "2026-11-05T00:00:00Z" }])),
      unavailable: new Set(unavailable.map(id)),
      read: { totalCount: items.length, totalCopies: copies, duplicate: false, inconsistentPages: false },
      collectionCopies: expectedCopies ?? copies,
      now: Date.parse("2026-11-07T12:00:00Z"),
    });
  };
  // Mesma condição da sobreposição: bloqueia se !complete ou provisional (= !printable).
  const blocked = (r: ReturnType<typeof run>) => !r.complete || r.provisional;
  const all = run([item(1), item(2, 3)], [1, 2]);
  assert.equal(blocked(all), false);
  assert.equal(all.printable, true);
  const unpriced = run([item(1), item(2)], [1]);
  assert.equal(blocked(unpriced), false); // ausência legítima não bloqueia
  assert.equal(blocked(run([item(1), item(2)], [1], [2])), true); // falha técnica de preço
  assert.equal(blocked(run([item(1)], [1], [], 5)), true); // divergência de integridade
  const empty = run([], []);
  assert.equal(empty.state, "empty");
  assert.equal(blocked(empty), false);
  // A condição da folha é exatamente a do núcleo.
  for (const r of [all, unpriced, empty]) assert.equal(!blocked(r), r.printable);
  // Master Set: a impressão não depende do objetivo (a única diferença é a nota do Master Set, testada no núcleo).
  assert.ok(!/MASTER_SET/.test(code(overlay)));
});
