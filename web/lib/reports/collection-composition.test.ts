// F2-3 (D7 §4q) — Composição da coleção (Pokédex e Coleção livre).
// Executar: node --experimental-strip-types --test lib/reports/collection-composition.test.ts (a partir de web/)
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import type { SetInventoryItemInput } from "./acervo-set-inventory.ts";
import { freeCollectionReportItems, pokedexReportItems } from "./collection-checklist.ts";
import { buildCollectionCompositionReport, compositionIncompleteText, compositionKindOf, compositionNotes } from "./collection-composition.ts";
import { prepareCollectionComposition } from "./collection-composition-queries.ts";
import type { CollectionValueReadCheck } from "./collection-value.ts";
import type { RarityCatalogInput } from "./distribution.ts";

const read = (path: string) => readFileSync(new URL(`../../${path}`, import.meta.url), "utf8");
const code = (src: string) => src.replace(/\/\*[\s\S]*?\*\/|\/\/.*$/gm, "");
const uuid = (n: number) => `00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`;
const COLLECTION = uuid(1);

const CATALOG: RarityCatalogInput = {
  status: "ok",
  entries: [
    { code: "NONE", name: "Comum", symbolCode: "c", displayOrder: 1 },
    { code: "COMMON", name: "Comum", symbolCode: "c", displayOrder: 2 },
    { code: "UNCOMMON", name: "Incomum", symbolCode: "u", displayOrder: 3 },
    { code: "RARE", name: "Rara", symbolCode: "r", displayOrder: 4 },
  ],
};

function item(n: number, set: string, rarity: string | null, lang: string, copies: number): SetInventoryItemInput {
  return {
    cardVariantId: uuid(100 + n),
    languageCode: lang,
    languageName: lang === "pt" ? "Português" : lang === "en" ? "Inglês" : null,
    cardName: `Carta ${n}`,
    collectorNumber: String(n),
    collectorTotal: 100,
    cardSetCode: set,
    cardSetName: `Set ${set}`,
    variantLabel: null,
    isDefaultVariant: true,
    copies,
    imagePath: null,
    rarityCode: rarity,
  };
}

const checkOf = (items: SetInventoryItemInput[], over: Partial<CollectionValueReadCheck> = {}): CollectionValueReadCheck => ({
  totalCount: items.length,
  totalCopies: items.reduce((s, i) => s + i.copies, 0),
  duplicate: false,
  inconsistentPages: false,
  ...over,
});

const SAMPLE = [
  item(1, "ME1", "COMMON", "pt", 3), // várias cópias da mesma carta
  item(2, "ME1", "RARE", "en", 1),
  item(3, "SV9", "UNCOMMON", "pt", 2),
  item(4, "SV9", "NONE", "ja", 1), // idioma sem nome
  item(5, "ME2", null, "pt", 1), // carta sem raridade
];

test("modalidades: só Pokédex e Coleção livre", () => {
  assert.equal(compositionKindOf("REFERENCE_POSITION"), "POKEDEX");
  assert.equal(compositionKindOf("NONE"), "FREE");
  for (const p of ["STANDARD_SET", "MASTER_SET", null, undefined, "X"]) assert.equal(compositionKindOf(p as string), null);
});

test("unidade = exemplar: cópias contam uma a uma; as três perspectivas somam o mesmo total", () => {
  const r = buildCollectionCompositionReport({ items: SAMPLE, read: checkOf(SAMPLE), collectionCopies: 8, rarities: CATALOG });
  assert.equal(r.complete, true);
  assert.equal(r.copies, 8);
  assert.equal(r.items, 5);
  assert.equal(r.sets, 3);
  assert.equal(r.languages, 3);
  assert.equal(r.rarities, 4); // NONE, COMMON, UNCOMMON, RARE; "Sem raridade definida" não conta
  const d = r.distribution;
  for (const dim of [d.sets, d.rarities!, d.languages]) {
    assert.equal(dim.bands.reduce((s, b) => s + b.copies, 0), 8);
    assert.equal(dim.copies, 8);
    assert.ok(dim.balanced);
  }
  // Card Set: exemplares ↓ (mesma regra da R1-H).
  assert.deepEqual(d.sets.bands.map((b) => [b.key, b.copies]), [["ME1", 4], ["SV9", 3], ["ME2", 1]]);
  assert.equal(d.sets.bands[0]?.top, true);
  // Raridade: ordem do catálogo; códigos com o mesmo nome nunca mesclados e identificados pelo código.
  assert.deepEqual(d.rarities!.bands.map((b) => [b.key, b.label, b.detail, b.copies]), [
    ["NONE", "Comum", "NONE", 1],
    ["COMMON", "Comum", "COMMON", 3],
    ["UNCOMMON", "Incomum", null, 2],
    ["RARE", "Rara", null, 1],
    ["∅", "Sem raridade definida", null, 1],
  ]);
  // Idioma: código e nome canônicos; sem nome → o código, nunca descartado nem redistribuído.
  assert.deepEqual(d.languages.bands.map((b) => [b.key, b.label, b.copies]), [["pt", "Português", 6], ["en", "Inglês", 1], ["ja", "ja", 1]]);
  // Sem valores: nada de preço é lido nem exibido.
  assert.equal(d.totalBrl, null);
  assert.ok(d.sets.bands.every((b) => b.valueBrl === null));
});

test("coleção vazia: completa, zero em tudo, sem faixas", () => {
  const r = buildCollectionCompositionReport({ items: [], read: checkOf([]), collectionCopies: 0, rarities: { status: "ok", entries: [] } });
  assert.equal(r.complete, true);
  assert.equal(r.copies, 0);
  assert.equal(r.distribution.sets.bands.length, 0);
});

test("integridade: divergências bloqueiam (sem estimar)", () => {
  // 5159 ≠ resumo canônico da coleção (5332).
  assert.equal(buildCollectionCompositionReport({ items: SAMPLE, read: checkOf(SAMPLE), collectionCopies: 9, rarities: CATALOG }).incompleteReason, "mismatch");
  // Grupos lidos não fecham com o total da leitura.
  assert.equal(buildCollectionCompositionReport({ items: SAMPLE, read: checkOf(SAMPLE, { totalCopies: 9 }), collectionCopies: 9, rarities: CATALOG }).incompleteReason, "mismatch");
  // Leitura com grupo repetido ou página instável.
  assert.equal(buildCollectionCompositionReport({ items: SAMPLE, read: checkOf(SAMPLE, { duplicate: true }), collectionCopies: 8, rarities: CATALOG }).incompleteReason, "read");
  assert.equal(buildCollectionCompositionReport({ items: SAMPLE, read: checkOf(SAMPLE, { inconsistentPages: true }), collectionCopies: 8, rarities: CATALOG }).incompleteReason, "read");
  // Acima do teto de leitura.
  assert.equal(buildCollectionCompositionReport({ items: [], read: { totalCount: 5001, totalCopies: 6000, duplicate: false, inconsistentPages: false }, collectionCopies: 6000, rarities: CATALOG }).incompleteReason, "too_large");
  // Raridade fora do catálogo / catálogo indisponível.
  const odd = [...SAMPLE, item(9, "ME1", "MYSTERY", "pt", 1)];
  assert.equal(buildCollectionCompositionReport({ items: odd, read: checkOf(odd), collectionCopies: 9, rarities: CATALOG }).incompleteReason, "rarity_unknown");
  const noCatalog = buildCollectionCompositionReport({ items: SAMPLE, read: checkOf(SAMPLE), collectionCopies: 8, rarities: { status: "unavailable" } });
  assert.equal(noCatalog.incompleteReason, "rarity_unavailable");
  assert.equal(noCatalog.distribution.rarities, null);
  for (const reason of ["too_large", "read", "mismatch", "rarity_unknown", "rarity_unavailable"] as const) assert.match(compositionIncompleteText(reason) ?? "", /incompleto/);
  assert.equal(compositionIncompleteText(null), null);
});

test("textos: sem completude; Pokédex distingue espécie, carta e exemplar; livre sem objetivo", () => {
  const pkx = compositionNotes("POKEDEX", 3).join(" ");
  assert.match(pkx, /3 espécies estão atendidas/);
  assert.match(pkx, /Espécie, carta e exemplar são grandezas diferentes/);
  assert.match(pkx, /não é completude/);
  const free = compositionNotes("FREE", null).join(" ");
  assert.match(free, /sem objetivo de completude/);
  assert.doesNotMatch(free, /espécie/);
});

// ---------------------------------------------------------------------------
// Leitura (cliente falso)

function fakeClient(groups: SetInventoryItemInput[], options: { policy?: string; missing?: boolean; copiesCount?: number } = {}) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const copies = groups.reduce((s, g) => s + g.copies, 0);
  const client = {
    rpc: async (fn: string, args: Record<string, unknown> = {}) => {
      calls.push({ fn, args });
      if (fn === "get_my_collection") {
        if (options.missing || args.p_collection_id !== COLLECTION) return { data: [], error: null };
        return {
          data: [
            {
              collection_id: COLLECTION,
              name: "Minha Pokédex",
              completion_policy: options.policy ?? "REFERENCE_POSITION",
              lifecycle_status: "ACTIVE",
              total_positions: 151,
              satisfied_positions: 4,
              copies_count: options.copiesCount ?? copies,
              total_count: 1,
            },
          ],
          error: null,
        };
      }
      if (fn === "get_my_inventory_items") {
        const offset = Number(args.p_offset);
        const limit = Number(args.p_limit);
        const rows = groups.slice(offset, offset + limit).map((g) => ({
          card_variant_id: g.cardVariantId,
          language_code: g.languageCode,
          language_name: g.languageName,
          card_name: g.cardName,
          collector_number: g.collectorNumber,
          collector_total: g.collectorTotal,
          card_set_code: g.cardSetCode,
          card_set_name: g.cardSetName,
          is_default_variant: true,
          variant_label: null,
          copies_count: g.copies,
          image_path: null,
          rarity_code: g.rarityCode,
          total_count: groups.length,
          total_copies: copies,
        }));
        return { data: rows, error: null };
      }
      if (fn === "get_rarity_catalog") {
        return { data: (CATALOG.status === "ok" ? CATALOG.entries : []).map((e) => ({ code: e.code, name: e.name, symbol_code: e.symbolCode, display_order: e.displayOrder })), error: null };
      }
      return { data: null, error: { code: "UNEXPECTED" } };
    },
  };
  return { client: client as never, calls };
}

test("leitura: titularidade primeiro, 5159 só com a coleção autorizada, sem preços", async () => {
  const { client, calls } = fakeClient(SAMPLE);
  const result = await prepareCollectionComposition(client, COLLECTION.toUpperCase());
  assert.equal(result.status, "ready");
  assert.equal(calls[0]?.fn, "get_my_collection");
  const items = calls.filter((c) => c.fn === "get_my_inventory_items");
  assert.ok(items.length > 0 && items.every((c) => c.args.p_collection_id === COLLECTION && c.args.p_without_collection === false));
  assert.ok(!calls.some((c) => c.fn === "get_card_variants_pricing_summary"), "nenhuma leitura de preço");
  assert.equal(calls.filter((c) => c.fn === "get_rarity_catalog").length, 1);
  if (result.status === "ready") {
    assert.equal(result.data.kind, "POKEDEX");
    assert.equal(result.data.satisfiedSpecies, 4);
    assert.equal(result.data.report.copies, 8);
    assert.equal(result.data.report.complete, true);
  }
});

test("leitura: coleção livre; sem exemplares não lê 5159 nem 5355", async () => {
  const free = fakeClient(SAMPLE, { policy: "NONE" });
  const r = await prepareCollectionComposition(free.client, COLLECTION);
  assert.ok(r.status === "ready" && r.data.kind === "FREE" && r.data.satisfiedSpecies === null);
  const empty = fakeClient([], { policy: "NONE" });
  const e = await prepareCollectionComposition(empty.client, COLLECTION);
  assert.ok(e.status === "ready" && e.data.report.copies === 0 && e.data.report.complete);
  assert.deepEqual(empty.calls.map((c) => c.fn), ["get_my_collection"]);
});

test("autorização: coleção alheia/inexistente → not_found; Set e Master Set → indisponível, sem ler exemplares", async () => {
  const missing = fakeClient(SAMPLE, { missing: true });
  assert.equal((await prepareCollectionComposition(missing.client, COLLECTION)).status, "not_found");
  assert.deepEqual(missing.calls.map((c) => c.fn), ["get_my_collection"]);
  for (const policy of ["STANDARD_SET", "MASTER_SET"]) {
    const set = fakeClient(SAMPLE, { policy });
    assert.equal((await prepareCollectionComposition(set.client, COLLECTION)).status, "unavailable");
    assert.deepEqual(set.calls.map((c) => c.fn), ["get_my_collection"]);
  }
});

test("exclusão de exemplares externos: total da coleção (5332) diferente da leitura → incompleto", async () => {
  const { client } = fakeClient(SAMPLE, { copiesCount: 7 });
  const r = await prepareCollectionComposition(client, COLLECTION);
  assert.ok(r.status === "ready" && r.data.report.incompleteReason === "mismatch");
});

// ---------------------------------------------------------------------------
// Menu, sobreposição, folha e impressão

test("menus: Composição habilitada na Pokédex e na livre; demais preservados; Set/Master Set sem mudança", () => {
  assert.deepEqual(pokedexReportItems().map((i) => [i.id, i.disabledReason]), [
    ["pokedex-checklist", null],
    ["pokedex-missing", null],
    ["collection-value", null],
    ["collection-composition", null],
  ]);
  assert.deepEqual(freeCollectionReportItems().map((i) => [i.id, i.disabledReason]), [["collection-value", null], ["collection-composition", null]]);
  const action = code(read("components/reports/collection-reports-action.tsx"));
  assert.ok(action.includes('report === "collection-composition" ? <CollectionCompositionOverlay collectionId={collectionId}'));
});

test("sobreposição, ação e folha: casca única, só leitura, impressão bloqueada se incompleto, sem valores", () => {
  const overlay = code(read("components/reports/collection-composition-overlay.tsx"));
  assert.ok(overlay.includes("<ReportSheetOverlay"));
  assert.ok(overlay.includes("compositionIncompleteText(data.report.incompleteReason)"));
  assert.ok(overlay.includes("shareInFlight"));
  const actions = code(read("app/colecoes/colecoes/[id]/relatorios/actions.ts"));
  assert.ok(actions.includes("export async function readCollectionComposition"));
  assert.ok(actions.includes("prepareCollectionComposition(supabase, input.collectionId.toLowerCase())"));
  const sheet = code(read("components/reports/collection-composition-report.tsx"));
  for (const label of ['label="Exemplares"', 'label="Card Sets"', 'label="Raridades"', 'label="Idiomas"']) assert.ok(sheet.includes(label), label);
  assert.ok(!/Valor estimado|formatBrl|Completude|faltante/i.test(sheet), "sem valor nem completude");
  assert.ok(sheet.includes("<thead>") && sheet.includes("RelatorioRodape"), "cabeçalho repetido e rodapé na impressão");
});
