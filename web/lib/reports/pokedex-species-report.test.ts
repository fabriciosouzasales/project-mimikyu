// V1-14 F2-2 — "Checklist da Pokédex" e "Espécies faltantes": escopo pelas gerações do objetivo (Kanto 151,
// Johto 100, Kanto + Johto 251, Nacional 1.025), paginação integral da 5204, contagem única por espécie,
// três situações das faltantes, conferência com o resumo canônico, autorização e guardas de código.
// Executar: node --experimental-strip-types --test lib/reports/pokedex-species-report.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { pokedexReportItems, freeCollectionReportItems } from "./collection-checklist.ts";
import {
  buildPokedexSpeciesReport,
  generationLabel,
  mergePokedexPages,
  missingStateText,
  nationalNumberText,
  pokedexReportIncompleteText,
} from "./pokedex-species-report.ts";
import { preparePokedexSpeciesReport } from "./pokedex-species-report-queries.ts";

const web = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const read = (path: string) => readFileSync(resolve(web, path), "utf8");
const code = (source: string) => source.replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "").replace(/\{\/\*[\s\S]*?\*\/\}/g, "");

const uuid = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const COLLECTION = uuid(9001);

/** Gerações reais da Pokédex Nacional (número inicial e final). */
const GENS = [
  ["GEN_1", 1, "Geração I", "Kanto", 1, 151],
  ["GEN_2", 2, "Geração II", "Johto", 152, 251],
  ["GEN_3", 3, "Geração III", "Hoenn", 252, 386],
  ["GEN_4", 4, "Geração IV", "Sinnoh", 387, 493],
  ["GEN_5", 5, "Geração V", "Unova", 494, 649],
  ["GEN_6", 6, "Geração VI", "Kalos", 650, 721],
  ["GEN_7", 7, "Geração VII", "Alola", 722, 809],
  ["GEN_8", 8, "Geração VIII", "Galar", 810, 905],
  ["GEN_9", 9, "Geração IX", "Paldea", 906, 1025],
] as const;
const genOf = (n: number) => GENS.find((g) => n >= g[4] && n <= g[5])!;

type State = "OWNED" | "AVAILABLE" | "ELSEWHERE" | "NOT_FOUND";
/** Situação de cada espécie no "banco": padrão NOT_FOUND. */
type World = Map<number, { state: State; copies?: number }>;

function fakeClient(selected: string[], world: World = new Map(), options: { policy?: string; collection?: "missing"; failPage?: number; canonicalDelta?: number } = {}) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const scope = Array.from({ length: 1025 }, (_, i) => i + 1).filter((n) => selected.includes(genOf(n)[0]));
  const satisfied = scope.filter((n) => world.get(n)?.state === "OWNED").length;
  const client = {
    storage: { from: () => ({ createSignedUrls: async () => ({ data: [], error: null }) }) },
    rpc: async (fn: string, args: Record<string, unknown> = {}) => {
      calls.push({ fn, args });
      if (fn === "get_my_collection") {
        if (options.collection === "missing" || args.p_collection_id !== COLLECTION) return { data: [], error: null };
        return {
          data: [
            {
              collection_id: COLLECTION, name: "Minha Pokédex", mode: "REFERENCE_BASED", completion_policy: options.policy ?? "REFERENCE_POSITION",
              lifecycle_status: "ACTIVE", card_set_id: null, card_set_code: null, card_set_name: null, card_set_logo_path: null,
              total_positions: scope.length + (options.canonicalDelta ?? 0), satisfied_positions: satisfied, is_complete: false,
              copies_count: 0, cover_image_path: null, created_at: "2026-10-19T00:00:00Z", total_count: 1,
            },
          ],
          error: null,
        };
      }
      if (fn === "get_my_pokedex_generation_options") {
        return { data: GENS.map(([code, ord, name, region, first, last]) => ({ generation_code: code, generation_ordinal: ord, generation_name: name, region_name: region, species_count: last - first + 1, first_number: first, last_number: last, is_selected: selected.includes(code), satisfied_count: 0 })), error: null };
      }
      if (fn === "get_my_pokedex_positions") {
        const offset = Number(args.p_offset);
        if (options.failPage !== undefined && offset === options.failPage) return { data: null, error: { code: "57014" } };
        // A 5204 limita ao escopo da coleção e respeita o filtro de geração.
        const rows = scope.filter((n) => !args.p_generation_code || genOf(n)[0] === args.p_generation_code);
        const page = rows.slice(offset, offset + Number(args.p_limit));
        return {
          data: page.map((n) => {
            const w = world.get(n) ?? { state: "NOT_FOUND" as State };
            return {
              pokedex_position_id: uuid(n), position_number: n, species_id: uuid(5000 + n), species_name: `Espécie ${n}`, generation_code: genOf(n)[0],
              generation_ordinal: genOf(n)[1], species_artwork_path: null, is_satisfied: w.state === "OWNED", copies_in_collection: w.state === "OWNED" ? (w.copies ?? 1) : 0,
              copies_available: w.state === "AVAILABLE" ? (w.copies ?? 1) : 0, copies_elsewhere: w.state === "ELSEWHERE" ? (w.copies ?? 1) : 0, acervo_state: w.state, total_count: rows.length,
            };
          }),
          error: null,
        };
      }
      return { data: null, error: { code: "UNEXPECTED" } };
    },
  };
  return { client, calls };
}

async function prepare(selected: string[], world?: World, options?: Parameters<typeof fakeClient>[2]) {
  const fake = fakeClient(selected, world, options);
  const result = await preparePokedexSpeciesReport(fake.client as never, COLLECTION, new Date("2026-11-09T12:00:00Z"));
  return { result, calls: fake.calls };
}

test("escopo = gerações do objetivo: Kanto 151, Johto 100, Kanto + Johto 251, Nacional 1.025; nenhuma espécie de fora", async () => {
  for (const [selected, expected, gens] of [
    [["GEN_1"], 151, ["GEN_1"]],
    [["GEN_2"], 100, ["GEN_2"]],
    [["GEN_1", "GEN_2"], 251, ["GEN_1", "GEN_2"]],
    [GENS.map((g) => g[0]), 1025, GENS.map((g) => g[0])],
  ] as const) {
    const { result } = await prepare([...selected]);
    assert.equal(result.status, "ready");
    if (result.status !== "ready") continue;
    const r = result.data.report;
    assert.equal(r.complete, true, `${expected}`);
    assert.equal(r.total, expected);
    assert.equal(r.generations.reduce((s, g) => s + g.species.length, 0), expected);
    assert.deepEqual(r.generations.map((g) => g.code), [...gens], "só as gerações do objetivo, em ordem");
    assert.equal(r.missingGroups.reduce((s, g) => s + g.species.length, 0), expected, "tudo pendente: soma dos grupos = pendentes");
    for (const g of r.generations) for (let i = 1; i < g.species.length; i += 1) assert.ok(g.species[i]!.number > g.species[i - 1]!.number, "ordem nacional");
  }
});

test("paginação integral da 5204 (500 por página, sem filtro de geração, só a coleção autorizada)", async () => {
  const { calls } = await prepare(GENS.map((g) => g[0]));
  const pages = calls.filter((c) => c.fn === "get_my_pokedex_positions");
  assert.deepEqual(pages.map((c) => c.args.p_offset), [0, 500, 1000]);
  assert.ok(pages.every((c) => c.args.p_filter === "ALL" && c.args.p_generation_code === null && c.args.p_limit === 500 && c.args.p_collection_id === COLLECTION));
  assert.equal(calls[0]?.fn, "get_my_collection", "5332 antes de tudo");
  assert.deepEqual([...new Set(calls.map((c) => c.fn))].sort(), ["get_my_collection", "get_my_pokedex_generation_options", "get_my_pokedex_positions"], "somente leitura");
  const kanto = await prepare(["GEN_1"]);
  assert.equal(kanto.calls.filter((c) => c.fn === "get_my_pokedex_positions").length, 1);
});

test("atendidas contam uma vez (várias cópias); faltantes em três grupos com soma = pendentes", async () => {
  const world: World = new Map([
    [1, { state: "OWNED", copies: 3 }],
    [4, { state: "OWNED" }],
    [7, { state: "AVAILABLE", copies: 2 }],
    [25, { state: "ELSEWHERE" }],
  ]);
  const { result } = await prepare(["GEN_1"], world);
  assert.equal(result.status, "ready");
  if (result.status !== "ready") return;
  const r = result.data.report;
  assert.deepEqual([r.total, r.satisfied, r.missing, r.percentText], [151, 2, 149, "1%"]);
  assert.equal(r.multiCopySpecies, 1, "Bulbasaur com 3 cópias conta uma espécie");
  const [available, elsewhere, notFound] = r.missingGroups;
  assert.deepEqual(available?.species.map((p) => p.number), [7]);
  assert.deepEqual(elsewhere?.species.map((p) => p.number), [25]);
  assert.equal(notFound?.species.length, 147);
  assert.equal(available!.species.length + elsewhere!.species.length + notFound!.species.length, r.missing);
  assert.ok(!r.missingGroups.some((g) => g.species.some((p) => p.isSatisfied)), "atendidas nunca aparecem nas faltantes");
  assert.equal(missingStateText(available!.species[0]!), "2 exemplares livres");
  assert.equal(missingStateText(elsewhere!.species[0]!), "1 exemplar em outra coleção");
  assert.equal(missingStateText(notFound!.species[0]!), "Sem exemplar no acervo");
});

test("mudança de gerações reflete o novo escopo (mesmos vínculos; espécies de fora somem)", async () => {
  const world: World = new Map([[1, { state: "OWNED" }], [152, { state: "OWNED" }]]);
  const only2 = await prepare(["GEN_2"], world);
  assert.equal(only2.result.status === "ready" ? only2.result.data.report.satisfied : null, 1);
  assert.ok(only2.result.status === "ready" && only2.result.data.report.generations.every((g) => g.code === "GEN_2"));
});

test("integridade: página que falha, total divergente do resumo, estado incoerente, fora do escopo → incompleto", async () => {
  const fail = await prepare(GENS.map((g) => g[0]), new Map(), { failPage: 500 });
  assert.equal(fail.result.status === "ready" ? fail.result.data.report.incompleteReason : null, "read");
  const failFirst = await prepare(["GEN_1"], new Map(), { failPage: 0 });
  assert.equal(failFirst.result.status, "error");
  const mismatch = await prepare(["GEN_1"], new Map(), { canonicalDelta: 1 });
  assert.equal(mismatch.result.status === "ready" ? mismatch.result.data.report.incompleteReason : null, "total_mismatch");

  const pos = (n: number, extra: Partial<{ isSatisfied: boolean; state: "OWNED" | "AVAILABLE" | "ELSEWHERE" | "NOT_FOUND"; generationCode: string }> = {}) => ({
    positionId: uuid(n), number: n, speciesId: uuid(n), speciesName: `E${n}`, generationCode: "GEN_1", artworkPath: null, isSatisfied: false,
    copiesInCollection: 0, copiesAvailable: 0, copiesElsewhere: 0, state: "NOT_FOUND" as const, representative: null, ...extra,
  });
  const gens = [{ code: "GEN_1", ordinal: 1, name: "Geração I", region: "Kanto", speciesCount: 151, firstNumber: 1, lastNumber: 151, selected: true, satisfied: 0 }];
  const ok = (positions: ReturnType<typeof pos>[]) => ({ status: "ok" as const, positions, total: positions.length });
  assert.equal(buildPokedexSpeciesReport({ read: ok([pos(1, { isSatisfied: true, state: "NOT_FOUND" })]), generations: gens, canonical: { total: 1, satisfied: 1 } }).incompleteReason, "state_mismatch");
  assert.equal(buildPokedexSpeciesReport({ read: ok([pos(200, { generationCode: "GEN_2" })]), generations: gens, canonical: { total: 1, satisfied: 0 } }).incompleteReason, "out_of_scope");
  assert.equal(buildPokedexSpeciesReport({ read: ok([pos(1), pos(1)]), generations: gens, canonical: { total: 1, satisfied: 0 } }).incompleteReason, "duplicate");
  for (const reason of ["read", "duplicate", "out_of_scope", "state_mismatch", "total_mismatch"] as const) assert.match(pokedexReportIncompleteText(reason) ?? "", /^Relatório incompleto: /);
  // Páginas: curta no meio, total instável, faltando.
  const page = (from: number, count: number, total: number) => ({ items: Array.from({ length: count }, (_, i) => pos(from + i)), total });
  assert.equal(mergePokedexPages([page(1, 500, 600), page(501, 100, 600)], 2).status, "ok");
  assert.equal(mergePokedexPages([page(1, 499, 600), page(501, 100, 600)], 2).status, "incomplete");
  assert.equal(mergePokedexPages([page(1, 500, 600), page(501, 100, 601)], 2).status, "incomplete");
  assert.equal(mergePokedexPages([page(1, 500, 600), null], 2).status, "incomplete");
});

test("autorização: alheia/inexistente → not_found; outra modalidade → indisponível, sem ler a Pokédex", async () => {
  const missing = await prepare(["GEN_1"], new Map(), { collection: "missing" });
  assert.equal(missing.result.status, "not_found");
  assert.deepEqual(missing.calls.map((c) => c.fn), ["get_my_collection"]);
  for (const policy of ["STANDARD_SET", "MASTER_SET", "NONE"]) {
    const other = await prepare(["GEN_1"], new Map(), { policy });
    assert.equal(other.result.status, "unavailable");
    assert.deepEqual(other.calls.map((c) => c.fn), ["get_my_collection"]);
  }
  const actions = read("app/colecoes/colecoes/[id]/relatorios/actions.ts");
  const fn = actions.slice(actions.indexOf("export async function readPokedexSpeciesReport"));
  assert.ok(fn.includes('if (!isCollectionId(input?.collectionId)) return { ok: false, reason: "not_found" };'));
  assert.ok(fn.includes('if (!user) return { ok: false, reason: "not_found" };'));
});

test("textos: número nacional, geração e a semântica de 'sem exemplar no acervo'", () => {
  assert.equal(nationalNumberText(25), "#0025");
  // Rótulo em pt-BR a partir do código (o nome canônico do catálogo é "Generation I"), igual à página Pokédex.
  assert.equal(generationLabel({ code: "GENERATION_I", region: "Kanto" }), "Geração I · Kanto");
  assert.equal(generationLabel({ code: "GENERATION_IX", region: "Paldea" }), "Geração IX · Paldea");
  assert.equal(generationLabel({ code: "GENERATION_IV", region: null }), "Geração IV");
  const sheet = code(read("components/reports/pokedex-species-report.tsx"));
  assert.ok(sheet.includes("não significa que não exista carta da espécie"));
  for (const label of ['label="Faltantes"', 'label="Disponíveis para vincular"', 'label="Em outras coleções"', 'label="Sem exemplar no acervo"', 'label="Completude"', 'label="Espécies no objetivo"', 'label="Atendidas"', 'label="Pendentes"']) assert.ok(sheet.includes(label), label);
});

test("menu e sobreposição: Checklist e Faltantes da Pokédex habilitados (Composição: F2-3); livre só Valor e Composição", () => {
  const items = pokedexReportItems();
  assert.deepEqual(items.filter((i) => i.disabledReason === null).map((i) => i.id), ["pokedex-checklist", "pokedex-missing", "collection-value", "collection-composition"]);
  assert.deepEqual(freeCollectionReportItems().map((i) => [i.id, i.disabledReason]), [["collection-value", null], ["collection-composition", null]]);
  const action = code(read("components/reports/collection-reports-action.tsx"));
  assert.ok(action.includes('report === "pokedex-checklist" ? <PokedexSpeciesOverlay collectionId={collectionId} mode="checklist"'));
  assert.ok(action.includes('report === "pokedex-missing" ? <PokedexSpeciesOverlay collectionId={collectionId} mode="missing"'));
  const overlay = code(read("components/reports/pokedex-species-overlay.tsx"));
  assert.ok(overlay.includes("incomplete: pokedexReportIncompleteText(data.report.incompleteReason)"), "incompleto bloqueia a impressão");
  assert.ok(overlay.includes('preparePrintJpegs("[data-pokedex-report] img[data-print-jpeg-species]"'), "arte em JPEG para o PDF");
  const css = read("components/reports/pokedex-species-report.module.css");
  assert.ok(/grid-template-columns: repeat\(10, minmax\(0, 1fr\)\)/.test(css), "10 colunas no A4");
  assert.ok(!code(read("components/reports/booklet-print-images.ts")).includes("data-print-jpeg-species"), "Caderno intocado");
});
