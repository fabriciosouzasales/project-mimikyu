// V1-14 R1-D — "Minhas favoritas": regras puras, leitura com cliente falso e integração estática.
// Executar: node --experimental-strip-types --test lib/reports/favorites-report.test.ts (a partir de web/)
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { PRICE_PARALLEL } from "./acervo-set-inventory-queries.ts";
import { getFavoritesReport } from "./favorites-report-queries.ts";
import {
  FAVORITES_REPORT_MAX,
  type FavoriteReportCardInput,
  buildFavoritesReport,
  collectorText,
  favoritesCoverageText,
  favoritesIncompleteText,
  favoritesOwnedText,
  ownedCopiesByCard,
  parseCardReferenceRows,
  parseFavoriteReportPage,
} from "./favorites-report.ts";
import { acervoReportMenuItems } from "./acervo-reports.ts";

const id = (n: number) => `00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`;
const card = (n: number, set: string, setName: string, number: string | null, name = `Carta ${n}`): FavoriteReportCardInput => ({
  cardId: id(n),
  name,
  collectorNumber: number,
  collectorTotal: 100,
  cardSetCode: set,
  cardSetName: setName,
  favoritedAt: "2026-11-01T12:00:00Z",
});
const build = (cards: FavoriteReportCardInput[], refs: [number, number][] = [], owned: [number, number][] = [], extra: Partial<Parameters<typeof buildFavoritesReport>[0]> = {}) =>
  buildFavoritesReport({
    cards,
    totalCount: cards.length,
    references: new Map(refs.map(([n, brl]) => [id(n), brl])),
    ownedCopies: new Map(owned.map(([n, c]) => [id(n), c])),
    withinLimit: true,
    ownershipComplete: true,
    ...extra,
  });

test("uma linha por carta; referência não multiplicada pela posse; favorita sem posse = 0 (—)", () => {
  const r = build([card(1, "AAA", "Alfa", "10"), card(2, "AAA", "Alfa", "2"), card(3, "BBB", "Beta", "1")], [[1, 12.5], [3, 0.1]], [[1, 4]]);
  assert.equal(r.favoriteCount, 3);
  const all = r.sets.flatMap((s) => s.cards);
  assert.equal(all.length, 3);
  const one = all.find((c) => c.cardId === id(1))!;
  assert.equal(one.ownedCopies, 4);
  assert.equal(one.referenceBrl, 12.5); // unitária, nunca 4 × 12,5
  assert.equal(r.totalReferenceBrl, 12.6); // 12,50 + 0,10 em centavos
  assert.equal(all.find((c) => c.cardId === id(2))!.ownedCopies, 0);
  assert.equal(r.ownedCount, 1);
  assert.equal(r.pricedCount, 2);
  assert.equal(favoritesOwnedText(r), "1 de 3 cartas favoritas com ao menos um exemplar");
  assert.equal(favoritesCoverageText(r), "2 de 3 cartas cotadas (66%)");
});

test("ordenação: Sets por nome pt-BR e código; cartas por número crescente (numérico) e desempate estável", () => {
  const r = build([
    card(1, "ZZ2", "Ébano", "10"),
    card(2, "ZZ1", "Ébano", "2"),
    card(3, "AA1", "Ametista", "10"),
    card(4, "AA1", "Ametista", "2"),
    card(5, "AA1", "Ametista", "2", "Abra"),
    card(6, "AA1", "Ametista", null),
  ]);
  assert.deepEqual(r.sets.map((s) => s.code), ["AA1", "ZZ1", "ZZ2"]);
  assert.deepEqual(r.sets[0]!.cards.map((c) => c.cardId), [id(5), id(4), id(3), id(6)]); // "2" (Abra, Carta 4) < "10" < sem número
  assert.equal(collectorText(r.sets[0]!.cards[3]!), "—");
  assert.equal(collectorText(r.sets[0]!.cards[0]!), "2/100");
});

test("posse: exemplares de várias variantes e idiomas somados por carta; variante sem carta → posse inválida", () => {
  const variantToCard = new Map([
    ["v1", id(1)],
    ["v2", id(1)],
    ["v3", id(2)],
  ]);
  const owned = ownedCopiesByCard(
    [
      { cardVariantId: "v1", copies: 2 },
      { cardVariantId: "v2", copies: 3 },
      { cardVariantId: "v3", copies: 1 },
    ],
    variantToCard,
  )!;
  assert.equal(owned.get(id(1)), 5);
  assert.equal(owned.get(id(2)), 1);
  assert.equal(ownedCopiesByCard([{ cardVariantId: "v9", copies: 1 }], variantToCard), null);
});

test("cobertura: nenhuma cotada → soma Sem cotação (null), nunca R$ 0; referência ≤ 0 não é cotação", () => {
  const refs = parseCardReferenceRows([
    { card_id: id(1), has_pricing: true, brl_amount: "0" },
    { card_id: id(2), has_pricing: false, brl_amount: null },
    { card_id: id(3), has_pricing: true, brl_amount: 5 },
  ])!;
  assert.deepEqual([...refs], [[id(3), 5]]);
  assert.equal(parseCardReferenceRows([{ card_id: "x", has_pricing: true }]), null);
  const r = build([card(1, "A", "A", "1")]);
  assert.equal(r.totalReferenceBrl, null);
  assert.equal(r.pricedCount, 0);
});

test("integridade: repetição entre páginas ou total divergente → incompleto (impressão bloqueada)", () => {
  const dup = build([card(1, "A", "A", "1"), card(1, "A", "A", "1")], [], [], { totalCount: 2 });
  assert.equal(dup.favoriteCount, 1); // uma linha por carta mesmo assim
  assert.equal(dup.incompleteReason, "changed");
  assert.equal(build([card(1, "A", "A", "1")], [], [], { totalCount: 2 }).incompleteReason, "changed");
  assert.equal(build([card(1, "A", "A", "1")], [], [], { withinLimit: false }).incompleteReason, "too_large");
  assert.equal(build([card(1, "A", "A", "1")], [], [], { ownershipComplete: false }).incompleteReason, "ownership_too_large");
  for (const reason of ["changed", "too_large", "ownership_too_large"] as const) assert.ok(favoritesIncompleteText(reason));
  assert.equal(favoritesIncompleteText(null), null);
  // Página estrita: linha fora do contrato invalida a página inteira (nunca descarta em silêncio).
  assert.equal(parseFavoriteReportPage([{ card_id: id(1), card_name: "", card_set_code: "A", favorited_at: "x", total_count: 1 }]), null);
});

/** Cliente falso: N favoritas, acervo com variantes, preços para ids pares. Registra as chamadas. */
function fakeClient(opts: { favorites: number; inventoryVariants?: number }) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  let inFlight = 0;
  let maxPriceInFlight = 0;
  const favs = Array.from({ length: opts.favorites }, (_, i) => i + 1);
  const variants = Array.from({ length: opts.inventoryVariants ?? 0 }, (_, i) => i + 1);
  const rpc = async (fn: string, args: Record<string, unknown> = {}) => {
    calls.push({ fn, args });
    if (fn === "get_my_favorite_cards") {
      const offset = args.p_offset as number;
      const limit = args.p_limit as number;
      return {
        data: favs.slice(offset, offset + limit).map((n) => ({
          card_id: id(n),
          card_name: `Carta ${n}`,
          collector_number: String(n),
          collector_total: 999,
          card_set_code: `S${n % 3}`,
          card_set_name: `Set ${n % 3}`,
          favorited_at: "2026-11-01T12:00:00Z",
          total_count: opts.favorites,
        })),
        error: null,
      };
    }
    if (fn === "get_cards_pricing_summary") {
      inFlight += 1;
      maxPriceInFlight = Math.max(maxPriceInFlight, inFlight);
      await new Promise((resolve) => setTimeout(resolve, 1));
      inFlight -= 1;
      return { data: (args.p_card_ids as string[]).map((cid, i) => ({ card_id: cid, has_pricing: i % 2 === 0, brl_amount: i % 2 === 0 ? 1 : null })), error: null };
    }
    if (fn === "get_my_inventory_summary") {
      return { data: [{ total_copies: variants.length * 2, distinct_items: variants.length, distinct_sets: 1, duplicate_copies: variants.length }], error: null };
    }
    if (fn === "get_my_inventory_items") {
      const offset = args.p_offset as number;
      const limit = args.p_limit as number;
      return {
        data: variants.slice(offset, offset + limit).map((n) => ({
          card_variant_id: id(100000 + n),
          language_code: "EN",
          card_name: `Carta ${n}`,
          card_set_code: "S",
          copies_count: 2,
          total_count: variants.length,
        })),
        error: null,
      };
    }
    if (fn === "get_my_card_favorites_by_variant") {
      // variante 100000+n pertence à carta n (favorita se n ≤ favoritas)
      return { data: (args.p_card_variant_ids as string[]).map((v) => ({ card_variant_id: v, card_id: id(Number.parseInt(v.slice(-12), 16) - 100000), is_favorite: true })), error: null };
    }
    return { data: null, error: { code: "UNEXPECTED" } };
  };
  return { client: { rpc } as never, calls, maxPriceInFlight: () => maxPriceInFlight };
}

test("leitura: lotes (100 favoritas e 100 preços por chamada, 2 preços simultâneos), posse somada, uma linha por carta", async () => {
  const fake = fakeClient({ favorites: 250, inventoryVariants: 3 });
  const r = await getFavoritesReport(fake.client);
  assert.equal(r.status, "ready");
  if (r.status !== "ready") return;
  const rep = r.data.report;
  assert.equal(rep.favoriteCount, 250);
  assert.equal(rep.complete, true);
  assert.equal(rep.ownedCount, 3); // cartas 1..3 têm 2 exemplares cada
  assert.equal(rep.sets.flatMap((s) => s.cards).find((c) => c.cardId === id(1))!.ownedCopies, 2);
  assert.equal(fake.calls.filter((c) => c.fn === "get_my_favorite_cards").length, 3);
  const priceCalls = fake.calls.filter((c) => c.fn === "get_cards_pricing_summary");
  assert.equal(priceCalls.length, 3);
  assert.ok(priceCalls.every((c) => (c.args.p_card_ids as string[]).length <= 100));
  assert.ok(fake.maxPriceInFlight() <= PRICE_PARALLEL);
  assert.ok(fake.calls.every((c) => !("p_user_id" in c.args) && !("user_id" in c.args))); // nenhum identificador do titular
});

test("teto de 5.000 favoritas: lê até o teto e marca incompleto; sem favoritas não lê preços nem acervo", async () => {
  const big = fakeClient({ favorites: FAVORITES_REPORT_MAX + 1 });
  const r = await getFavoritesReport(big.client);
  assert.equal(r.status, "ready");
  if (r.status === "ready") {
    assert.equal(r.data.report.favoriteCount, FAVORITES_REPORT_MAX);
    assert.equal(r.data.report.incompleteReason, "too_large");
  }
  assert.ok(big.calls.filter((c) => c.fn === "get_my_favorite_cards").every((c) => (c.args.p_offset as number) < FAVORITES_REPORT_MAX));
  const empty = fakeClient({ favorites: 0 });
  const e = await getFavoritesReport(empty.client);
  assert.equal(e.status, "ready");
  assert.deepEqual(empty.calls.map((c) => c.fn), ["get_my_favorite_cards"]);
  // Favorito independe de posse: no menu do Acervo, "Minhas favoritas" abre mesmo com o acervo vazio.
  assert.equal(acervoReportMenuItems({ totalCopies: 0 }).find((i) => i.id === "favorites")?.disabledReason, null);
});

const src = (path: string) => readFileSync(new URL(path, import.meta.url), "utf8");

test("integração: 4º relatório do menu do Meu acervo; fora da página Cartas favoritas; sem SQL nova; miniatura na tela e na impressão", () => {
  const acervo = src("./acervo-reports.ts");
  assert.match(acervo, /id: "favorites",\s+title: "Minhas favoritas"[\s\S]*?implemented: true/);
  const view = src("../../components/favorites/favorite-cards-view.tsx");
  assert.doesNotMatch(view, /Relatórios|ReportsAction|heroBar/); // página Cartas favoritas como antes
  const queries = src("./favorites-report-queries.ts");
  for (const fn of ["get_my_favorite_cards", "get_cards_pricing_summary", "get_my_card_favorites_by_variant"]) assert.match(queries, new RegExp(`"${fn}"`));
  assert.doesNotMatch(queries, /inventory-value|get_my_inventory_value_report/);
  const action = src("../../app/colecoes/acervo/relatorios/actions.ts");
  assert.match(action, /export async function readFavoritesReport\(\): Promise<FavoritesReportLoad> \{\s+const \{\s+data: \{ user \},\s+\} = await getCachedUser\(\);\s+if \(!user\) return \{ status: "error" \};/);
  const overlay = src("../../components/reports/acervo-report-overlay.tsx");
  // Sobreposição institucional do Meu acervo; incompleto → impressão bloqueada pela casca.
  assert.match(overlay, /report === "favorites"[\s\S]*readFavoritesReport\(\)[\s\S]*favoritesIncompleteText\(r\.data\.report\.incompleteReason\)/);
  const sheet = src("../../components/reports/favorites-report.tsx");
  assert.doesNotMatch(sheet, /next\/image|variantLabel|languageCode/);
  // Miniatura: uma só <img>, visível na tela e na impressão; carregamento imediato até o teto (impressão completa).
  assert.equal((sheet.match(/<img /g) ?? []).length, 1);
  assert.match(sheet, /className="h-\[34px\] w-\[24px\] shrink-0 overflow-hidden rounded-\[2px\] bg-neutral-100">\s*\{card\.imageUrl \? \([\s\S]*?<img src=\{card\.imageUrl\} alt="" width=\{24\} height=\{34\} loading=\{eagerImages \? "eager" : "lazy"\}/);
  assert.match(sheet, /export const EAGER_IMAGES_MAX = 300;/);
  assert.match(sheet, /const eagerImages = report\.favoriteCount <= EAGER_IMAGES_MAX;/);
  assert.match(sheet, /Não representa\s+patrimônio físico nem valor de revenda/);
});

test("miniatura: caminho pt-BR (senão en) → URL pública pelo resolvedor; sem imagem = null; sem resolvedor = null", () => {
  const page = parseFavoriteReportPage([
    { card_id: id(1), card_name: "A", card_set_code: "S", favorited_at: "2026-11-01T00:00:00Z", total_count: 3, image_path_pt: "pt/1.webp", image_path_en: "en/1.webp" },
    { card_id: id(2), card_name: "B", card_set_code: "S", favorited_at: "2026-11-01T00:00:00Z", total_count: 3, image_path_pt: null, image_path_en: "en/2.webp" },
    { card_id: id(3), card_name: "C", card_set_code: "S", favorited_at: "2026-11-01T00:00:00Z", total_count: 3 },
  ])!;
  const resolved = buildFavoritesReport({
    cards: page.cards,
    totalCount: 3,
    references: new Map(),
    ownedCopies: new Map(),
    withinLimit: true,
    ownershipComplete: true,
    imageUrl: (path) => `https://cdn.test/card-front/${path}`,
  });
  const urls = Object.fromEntries(resolved.sets[0]!.cards.map((c) => [c.name, c.imageUrl]));
  assert.deepEqual(urls, { A: "https://cdn.test/card-front/pt/1.webp", B: "https://cdn.test/card-front/en/2.webp", C: null });
  const bare = buildFavoritesReport({ cards: page.cards, totalCount: 3, references: new Map(), ownedCopies: new Map(), withinLimit: true, ownershipComplete: true });
  assert.ok(bare.sets[0]!.cards.every((c) => c.imageUrl === null));
  assert.ok(resolved.sets[0]!.cards.every((c) => !("imagePath" in c))); // o caminho não vaza para a folha
  const action = src("../../app/colecoes/acervo/relatorios/actions.ts");
  assert.match(action, /storage\.from\("card-front"\)\.getPublicUrl\(path\)/);
});
