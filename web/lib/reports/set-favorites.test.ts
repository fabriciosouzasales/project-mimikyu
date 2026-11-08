// V1-14 R2-D — "Cartas favoritas do Card Set" (D7 §4l): 5332 antes da 5356, nenhuma leitura para
// coleção não autorizada, filtro canônico, reimpressões fora, uma linha por carta, lista única
// ordenada, posse de todas as variantes e idiomas, KPIs, referência por carta sem multiplicação,
// sem cotação × falha temporária, estados e incompletude, paginação e teto, impressão sem caixa
// e preparo de imagens, regressão (R1-D, R2-A, R2-B, R2-C).
// Executar: node --experimental-strip-types --test lib/reports/set-favorites.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { collectionReportItems } from "./collection-checklist.ts";
import { buildFavoritesReport, favoritesIncompleteText } from "./favorites-report.ts";
import { prepareSetFavoritesReport } from "./set-favorites-queries.ts";
import { buildSetFavoritesReport, setFavoriteOwnershipText, setFavoriteReferenceText, setFavoritesIncompleteText, setFavoritesTotalText } from "./set-favorites.ts";

console.error = () => {};
console.warn = () => {};
console.info = () => {};

const read = (path: string) => readFileSync(new URL(path, import.meta.url), "utf8");
const uuid = (n: number) => `00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`;
const brl = (n: number) => `R$ ${n.toFixed(2).replace(".", ",")}`;
const COLLECTION = uuid(9001);
const SET = uuid(5500);
const OTHER_SET = uuid(5501);

/** Favorita no "banco": carta n do Set (ou de outro), na ordem collector_order = n. */
type Fav = { card: number; set?: string; order?: number };
/** Exemplares do acervo: variante → carta, idioma e quantidade. */
type Copy = { variant: number; card: number; lang?: string; copies: number };

function fakeClient(
  favs: Fav[],
  options: {
    policy?: string;
    collection?: "missing" | "error";
    cardSetId?: string | null;
    prices?: Record<number, number | null>;
    failPrices?: boolean;
    inventory?: Copy[];
    failOwnership?: boolean;
    leakSet?: boolean;
    totalDelta?: number;
    inventoryTotalOverride?: number;
  } = {},
) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const order: string[] = [];
  const inventory = options.inventory ?? [];
  return {
    calls,
    order,
    client: {
      storage: { from: () => ({ createSignedUrls: async () => ({ data: [], error: null }) }) },
      rpc: async (fn: string, args: Record<string, unknown> = {}) => {
        calls.push({ fn, args });
        order.push(`${fn}:start`);
        await new Promise((resolve) => setTimeout(resolve, 1));
        order.push(`${fn}:end`);
        if (fn === "get_my_collection") {
          if (options.collection === "error") return { data: null, error: { code: "57014" } };
          if (options.collection === "missing") return { data: [], error: null };
          return {
            data: [
              {
                collection_id: COLLECTION,
                name: "Minha ME5.5",
                mode: "REFERENCE_BASED",
                completion_policy: options.policy ?? "MASTER_SET",
                lifecycle_status: "ACTIVE",
                card_set_id: options.cardSetId === undefined ? SET : options.cardSetId,
                card_set_code: "ME5.5",
                card_set_name: "Celebração de 30 Anos",
                card_set_logo_path: null,
                total_positions: 158,
                satisfied_positions: 149,
                is_complete: false,
                copies_count: 300,
                cover_image_path: null,
                created_at: "2026-10-01T00:00:00Z",
                total_count: 1,
              },
            ],
            error: null,
          };
        }
        if (fn === "get_my_favorite_cards_by_card_set") {
          // O "banco": filtra pelo Card Set recebido e ordena por collector_order.
          const filtered = favs.filter((f) => options.leakSet || (f.set ?? SET) === args.p_card_set_id).sort((a, b) => (a.order ?? a.card) - (b.order ?? b.card));
          const offset = Number(args.p_offset);
          const total = filtered.length + (options.totalDelta ?? 0);
          return {
            data: filtered.slice(offset, offset + Number(args.p_limit)).map((f) => ({
              card_id: uuid(3000 + f.card),
              card_name: `Carta ${f.card}`,
              collector_number: String(f.order ?? f.card).padStart(3, "0"),
              collector_total: 158,
              card_set_id: f.set ?? SET,
              card_set_code: "ME5.5",
              card_set_name: "Celebração de 30 Anos",
              image_path_pt: `cards/${f.card}.webp`,
              image_path_en: null,
              favorited_at: "2026-11-07T12:00:00Z",
              total_count: total,
            })),
            error: null,
          };
        }
        if (fn === "get_cards_pricing_summary") {
          if (options.failPrices) return { data: null, error: { code: "57014" } };
          const ids = args.p_card_ids as string[];
          return {
            data: ids.map((id) => {
              const n = Number.parseInt(id.slice(-12), 16) - 3000;
              const brlAmount = options.prices?.[n] ?? null;
              return { card_id: id, has_pricing: brlAmount !== null, brl_amount: brlAmount };
            }),
            error: null,
          };
        }
        if (fn === "get_my_inventory_summary") {
          const copies = inventory.reduce((n, c) => n + c.copies, 0);
          return { data: [{ total_copies: copies, distinct_items: inventory.length, distinct_sets: 1, duplicate_copies: copies - inventory.length }], error: null };
        }
        if (fn === "get_my_inventory_items") {
          const offset = Number(args.p_offset);
          const total = options.inventoryTotalOverride ?? inventory.length;
          return {
            data: inventory.slice(offset, offset + Number(args.p_limit)).map((c) => ({
              card_variant_id: uuid(6000 + c.variant),
              language_code: c.lang ?? "pt-BR",
              language_name: "Português",
              card_name: `Carta ${c.card}`,
              collector_number: String(c.card),
              collector_total: 158,
              card_set_code: "ME5.5",
              card_set_name: "Celebração de 30 Anos",
              is_default_variant: true,
              variant_label: null,
              copies_count: c.copies,
              image_path: null,
              total_count: total,
            })),
            error: null,
          };
        }
        if (fn === "get_my_card_favorites_by_variant") {
          if (options.failOwnership) return { data: null, error: { code: "57014" } };
          const ids = args.p_card_variant_ids as string[];
          return {
            data: ids.map((id) => {
              const v = Number.parseInt(id.slice(-12), 16) - 6000;
              const copy = inventory.find((c) => c.variant === v)!;
              return { card_variant_id: id, card_id: uuid(3000 + copy.card), is_favorite: true };
            }),
            error: null,
          };
        }
        return { data: null, error: { code: "PGRST202" } };
      },
    },
  };
}

async function prepare(favs: Fav[], options: Parameters<typeof fakeClient>[1] = {}) {
  const fake = fakeClient(favs, options);
  const result = await prepareSetFavoritesReport(fake.client as never, COLLECTION, (p) => `https://img/${p}`, new Date("2026-11-07T12:00:00Z"));
  return { ...fake, result };
}

test("autorização 5332 antes da 5356; Card Set só da coleção autorizada; nenhum identificador do navegador", async () => {
  const { result, calls, order } = await prepare([{ card: 1 }]);
  assert.equal(result.status, "ready");
  assert.equal(calls[0]?.fn, "get_my_collection");
  assert.ok(order.indexOf("get_my_collection:end") < order.indexOf("get_my_favorite_cards_by_card_set:start"));
  const fav = calls.find((c) => c.fn === "get_my_favorite_cards_by_card_set");
  assert.equal(fav?.args.p_card_set_id, SET);
  assert.equal(fav?.args.p_limit, 100);
  assert.ok(calls.every((c) => Object.keys(c.args).every((key) => !/user|owner_id|owner_user|profile/i.test(key))));
  const actions = read("../../app/colecoes/colecoes/[id]/relatorios/actions.ts");
  assert.match(actions, /export async function readSetFavoritesReport\(input: \{ collectionId: string \}\)/);
  assert.match(actions, /prepareSetFavoritesReport\(supabase, input\.collectionId\.toLowerCase\(\), imageUrl\)/);
});

test("coleção não autorizada, sem Card Set, Pokédex ou livre: nenhuma leitura de favoritas", async () => {
  for (const [opts, status] of [
    [{ collection: "missing" }, "not_found"],
    [{ collection: "error" }, "error"],
    [{ cardSetId: null }, "unavailable"],
    [{ policy: "REFERENCE_POSITION" }, "unavailable"],
    [{ policy: "NONE" }, "unavailable"],
  ] as const) {
    const r = await prepare([{ card: 1 }], opts);
    assert.equal(r.result.status, status, JSON.stringify(opts));
    assert.ok(!r.calls.some((c) => c.fn === "get_my_favorite_cards_by_card_set" || c.fn === "get_cards_pricing_summary" || c.fn === "get_my_inventory_items"), JSON.stringify(opts));
  }
});

test("filtro canônico: reimpressões de outro Set fora; linha de outro Set na resposta → inconsistência; uma linha por carta", async () => {
  const favs: Fav[] = [{ card: 1 }, { card: 2 }, { card: 50, set: OTHER_SET }];
  const { result } = await prepare(favs);
  assert.equal(result.status === "ready" && result.data.report.cardCount, 2);
  const leak = await prepare(favs, { leakSet: true });
  assert.equal(leak.result.status === "ready" && leak.result.data.report.incompleteReason, "set_mismatch");
  assert.match(setFavoritesIncompleteText("set_mismatch", favoritesIncompleteText) ?? "", /impressão fica indisponível/);
  // Duplicada entre páginas: uma linha por carta e relatório incompleto (regra da R1-D).
  const dup = buildFavoritesReport({
    cards: [1, 1].map((n) => ({ cardId: uuid(3000 + n), name: "Carta", collectorNumber: "001", collectorTotal: 158, cardSetCode: "ME5.5", cardSetName: "X", favoritedAt: "2026-11-07T12:00:00Z" })),
    totalCount: 2,
    references: new Map(),
    ownedCopies: new Map(),
    withinLimit: true,
    ownershipComplete: true,
  });
  const r = buildSetFavoritesReport({ favorites: dup, order: [uuid(3001)], foreignSet: false, pricesUnavailable: false });
  assert.equal(r.lines.length, 1);
  assert.equal(r.incompleteReason, "changed");
});

test("lista única na ordem canônica da 5356 (collector_order), sem filtros nem grupos", async () => {
  // Ordem do Set diferente da ordem textual do número: a 5356 (collector_order) manda.
  const favs: Fav[] = [{ card: 3, order: 1 }, { card: 1, order: 3 }, { card: 2, order: 2 }];
  const { result } = await prepare(favs);
  assert.equal(result.status, "ready");
  if (result.status !== "ready") return;
  assert.deepEqual(result.data.report.lines.map((l) => l.name), ["Carta 3", "Carta 2", "Carta 1"]);
  const sheet = read("../../components/reports/set-favorites-report.tsx");
  assert.doesNotMatch(sheet, /aria-pressed|setFilter|useState|groups/); // sem filtros nem grupos
  assert.match(sheet, /\{report\.lines\.map\(\(line\) => \(\s*<ScreenCard key=\{line\.cardId\}/);
});

test("posse de todas as variantes e idiomas; No acervo X de Y; Exemplares no acervo", async () => {
  const favs: Fav[] = [{ card: 1 }, { card: 2 }, { card: 3 }];
  const inventory: Copy[] = [
    { variant: 1, card: 1, lang: "pt-BR", copies: 2 },
    { variant: 1, card: 1, lang: "en", copies: 1 }, // mesma variante, outro idioma
    { variant: 2, card: 1, copies: 3 }, // outra variante da mesma carta
    { variant: 3, card: 2, copies: 1 },
    { variant: 4, card: 99, copies: 7 }, // carta não favorita: não entra
  ];
  const { result } = await prepare(favs, { inventory });
  assert.equal(result.status, "ready");
  if (result.status !== "ready") return;
  const r = result.data.report;
  assert.deepEqual(r.lines.map((l) => l.ownedCopies), [6, 1, 0]);
  assert.equal(r.ownedCount, 2);
  assert.equal(r.ownedCopies, 7);
  assert.equal(setFavoriteOwnershipText(6), "No acervo: 6 exemplares");
  assert.equal(setFavoriteOwnershipText(1), "No acervo: 1 exemplar");
  assert.equal(setFavoriteOwnershipText(0), "Não está no acervo");
  // Acervo lido de forma incompleta (acima do teto) → posse não confiável, impressão bloqueada.
  const partial = await prepare(favs, { inventory, inventoryTotalOverride: 6000 });
  assert.equal(partial.result.status === "ready" && partial.result.data.report.incompleteReason, "ownership_too_large");
  // Falha da leitura de posse → erro (regra da R1-D).
  const fail = await prepare(favs, { inventory, failOwnership: true });
  assert.equal(fail.result.status, "error");
});

test("referência NM geral por carta, uma vez (nunca × exemplares); sem cotação × falha temporária", async () => {
  const favs: Fav[] = [{ card: 1 }, { card: 2 }, { card: 3 }];
  const inventory: Copy[] = [{ variant: 1, card: 1, copies: 5 }];
  const { result } = await prepare(favs, { inventory, prices: { 1: 18.5, 2: 0.33, 3: null } });
  assert.equal(result.status, "ready");
  if (result.status !== "ready") return;
  const r = result.data.report;
  assert.equal(r.totalReferenceBrl, 18.83); // 18,50 + 0,33 — nunca 5 × 18,50
  assert.equal(r.pricedCount, 2);
  assert.equal(r.complete, true); // sem cotação não bloqueia
  assert.equal(setFavoriteReferenceText(r.lines[2]!, false, brl), "Sem cotação");
  assert.equal(setFavoritesTotalText(r, brl), "R$ 18,83");
  // Falha temporária de preço: provisório, lista preservada, referências "Indisponível", impressão bloqueada.
  const failed = await prepare(favs, { inventory, failPrices: true });
  assert.equal(failed.result.status, "ready");
  if (failed.result.status !== "ready") return;
  const f = failed.result.data.report;
  assert.equal(f.incompleteReason, "prices_unavailable");
  assert.equal(f.lines.length, 3);
  assert.equal(setFavoriteReferenceText(f.lines[0]!, f.pricesUnavailable, brl), "Indisponível");
  assert.equal(setFavoritesTotalText(f, brl), "Indisponível");
  assert.match(setFavoritesIncompleteText("prices_unavailable", favoritesIncompleteText) ?? "", /provisório/);
});

test("estados: sem favoritas (sem preço nem posse lidos); todas ou nenhuma no acervo = lista normal; total divergente e teto", async () => {
  const empty = await prepare([]);
  assert.equal(empty.result.status === "ready" && empty.result.data.report.state, "empty");
  assert.equal(empty.result.status === "ready" && empty.result.data.report.complete, true);
  assert.ok(!empty.calls.some((c) => c.fn === "get_cards_pricing_summary" || c.fn === "get_my_inventory_items"));
  assert.match(read("../../components/reports/set-favorites-report.tsx"), /Nenhuma carta favorita deste Card Set\./);
  const none = await prepare([{ card: 1 }]);
  assert.equal(none.result.status === "ready" && none.result.data.report.state, "list");
  const all = await prepare([{ card: 1 }], { inventory: [{ variant: 1, card: 1, copies: 1 }] });
  assert.equal(all.result.status === "ready" && all.result.data.report.state, "list");
  const changed = await prepare([{ card: 1 }], { totalDelta: 1 });
  assert.equal(changed.result.status === "ready" && changed.result.data.report.incompleteReason, "changed");
  // Paginação de 100: 230 favoritas = 3 páginas, todas lidas.
  const many = Array.from({ length: 230 }, (_, i) => ({ card: i + 1 }));
  const big = await prepare(many);
  assert.equal(big.calls.filter((c) => c.fn === "get_my_favorite_cards_by_card_set").length, 3);
  assert.equal(big.result.status === "ready" && big.result.data.report.lines.length, 230);
  // Teto de 5.000 (regra da R1-D).
  const over = buildFavoritesReport({ cards: [], totalCount: 6000, references: new Map(), ownedCopies: new Map(), withinLimit: false, ownershipComplete: true });
  assert.equal(buildSetFavoritesReport({ favorites: over, order: [], foreignSet: false, pricesUnavailable: false }).incompleteReason, "too_large");
});

test("impressão A4: cartões em duas colunas, miniatura 14 × 19,6 mm, SEM caixa de marcação, preparo de imagens da R1-G", () => {
  const sheet = read("../../components/reports/set-favorites-report.tsx");
  assert.match(sheet, /<div className="hidden print:block">\s*<PrintImageGate>\s*<PrintList lines=\{report\.lines\}/);
  const printPart = sheet.slice(sheet.indexOf("function PrintList"), sheet.indexOf("function StateMessage"));
  assert.match(printPart, /<col style=\{\{ width: "50%" \}\} \/>\s*<col style=\{\{ width: "50%" \}\} \/>/);
  assert.match(printPart, /<tr key=\{left\.cardId\} style=\{\{ breakInside: "avoid" \}\}>/);
  assert.match(sheet, /SET_FAVORITES_PRINT_THUMB_MM = \{ width: 14, height: 19\.6 \}/);
  assert.doesNotMatch(printPart, /h-\[5mm\] w-\[5mm\]|data-check-box|CheckBox/); // D6: sem caixa
  assert.doesNotMatch(printPart, /min-h-\[|minHeight/); // altura variável
  assert.match(printPart, /<FavoriteDetails line=\{line\} pricesUnavailable=\{pricesUnavailable\} print \/>/);
  const details = sheet.slice(sheet.indexOf("function FavoriteDetails"), sheet.indexOf("function ScreenCard"));
  for (const piece of ["collectorText(line)", "line.name", "setFavoriteOwnershipText(line.ownedCopies)", "Referência NM: ", "Favoritada em {favoritedAtText(line.favoritedAt)}"])
    assert.ok(details.includes(piece), piece);
  assert.match(sheet, /<Heart aria-hidden="true"/); // coração discreto
  const head = sheet.slice(sheet.indexOf("<thead>"), sheet.indexOf("</thead>"));
  assert.match(head, /\{cabecalho\}/);
  assert.doesNotMatch(head, /Indicator/); // KPIs só na 1ª página
  for (const label of ["Cartas favoritas", "No acervo", "Exemplares no acervo", "Referência NM"]) assert.match(sheet, new RegExp(`label="${label}"`), label);
  assert.match(sheet, /Não é patrimônio, valor de revenda nem custo de\s+aquisição/);
  assert.match(sheet, /não é desejo de compra, não é posse e não é carta faltante/);
  const overlay = read("../../components/reports/set-favorites-overlay.tsx");
  assert.match(overlay, /shareInFlight\(\(\) => readSetFavoritesReport\(\{ collectionId \}\)\)/);
  assert.match(overlay, /preparePrint: data\.report\.state !== "empty" \? \(onProgress\) => preparePrintImages\(onProgress\) : undefined/);
  for (const source of [sheet, overlay]) assert.doesNotMatch(source, /render\/image|\?width=|&quality=|set_card_favorite|setCardFavorite/); // sem transformação, sem favoritar
});

test("menu da coleção e regressão: R1-D, R2-A, R2-B e R2-C preservados", () => {
  const c = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
  const set = collectionReportItems({ collectionId: c, completionPolicy: "STANDARD_SET", totalPositions: 100, satisfiedPositions: 62 });
  // R2-E acrescentou um 5º item (Valor estimado) depois destes; a posição e os dados dos quatro não mudam.
  assert.deepEqual(set.slice(0, 4).map((i) => i.id), ["checklist", "missing", "set-wishlist", "set-favorites"]);
  assert.equal(set[3]?.label, "Cartas favoritas do Card Set");
  assert.equal(set[3]?.icon, "favorite");
  assert.equal(set[3]?.disabledReason, null);
  for (const policy of ["REFERENCE_POSITION", "NONE"]) {
    assert.equal(collectionReportItems({ collectionId: c, completionPolicy: policy, totalPositions: 1, satisfiedPositions: 0 })[3]?.disabledReason, "Para coleções de Set padrão e Master Set.");
  }
  const action = read("../../components/reports/collection-reports-action.tsx");
  assert.match(action, /report === "set-favorites" \? <SetFavoritesOverlay collectionId=\{collectionId\}/);
  // R1-D continua com a leitura própria (5336) e a mesma regra de erro.
  const r1d = read("./favorites-report-queries.ts");
  assert.match(r1d, /supabase\.rpc\("get_my_favorite_cards", \{ p_limit: FAVORITES_REPORT_PAGE, p_offset: 0 \}\)/);
  assert.match(r1d, /if \(prices\.status === "error"\) return fail\(prices\.stage, prices\.code\);/);
  for (const source of [read("./set-favorites.ts"), read("./set-favorites-queries.ts")]) assert.doesNotMatch(source, /\.insert\(|\.update\(|\.delete\(|\.upsert\(|set_card_favorite/);
});

test("tela: miniatura com a altura exata do bloco de texto (do Nº à base de \"Favoritada em\"), proporção da carta, sem depender do tamanho da imagem", () => {
  const sheet = read("../../components/reports/set-favorites-report.tsx");
  const details = sheet.slice(sheet.indexOf("function FavoriteDetails"), sheet.indexOf("function ScreenCard"));
  // Na tela, cada linha tem altura fixa: Nº, posse, referência e data = 14 px; nome = 16 px (uma linha).
  assert.match(details, /const row = print \? "h-\[3\.8mm\] leading-\[3\.8mm\] truncate" : "h-\[14px\] leading-\[14px\] truncate";/);
  assert.equal((details.match(/\$\{row\}/g) ?? []).length, 4);
  assert.match(details, /h-\[16px\] truncate text-\[12px\] leading-\[16px\]/);
  assert.match(sheet, /SET_FAVORITES_SCREEN_TEXT_PX = 14 \+ 16 \+ 14 \+ 14 \+ 14;/); // = 72 px, a soma das linhas
  assert.match(sheet, /SET_FAVORITES_SCREEN_THUMB_PX = \{ width: 52, height: SET_FAVORITES_SCREEN_TEXT_PX \}/);
  assert.ok(Math.abs(52 / 72 - 63 / 88) < 0.01); // proporção da carta
  const screen = sheet.slice(sheet.indexOf("function ScreenCard"), sheet.indexOf("function PrintList"));
  assert.match(screen, /<li className="relative flex items-start/); // topo alinhado: base da miniatura = base da data
  assert.match(screen, /style=\{\{ width: SET_FAVORITES_SCREEN_THUMB_PX\.width, height: SET_FAVORITES_SCREEN_THUMB_PX\.height \}\}/); // tamanho definido no contêiner
  assert.match(screen, /className="absolute inset-0 h-full w-full object-cover"/); // a imagem nunca dita o tamanho
  assert.doesNotMatch(screen, /aspect-\[63\/88\]|self-stretch/); // abordagem anterior (falhou na homologação) removida
  assert.match(sheet, /SET_FAVORITES_PRINT_THUMB_MM = \{ width: 14, height: 19\.6 \}/);
});

test("impressão: miniatura com a altura exata do bloco de texto (19,6 mm), proporção da carta", () => {
  const sheet = read("../../components/reports/set-favorites-report.tsx");
  assert.match(sheet, /SET_FAVORITES_PRINT_TEXT_MM = 3\.6 \+ 4\.6 \+ 3\.8 \+ 3\.8 \+ 3\.8;/);
  assert.ok(Math.abs(3.6 + 4.6 + 3.8 * 3 - 19.6) < 1e-9);
  assert.ok(Math.abs(14 / 19.6 - 63 / 88) < 0.005); // proporção da carta
  const details = sheet.slice(sheet.indexOf("function FavoriteDetails"), sheet.indexOf("function ScreenCard"));
  assert.match(details, /const row = print \? "h-\[3\.8mm\] leading-\[3\.8mm\] truncate"/); // posse, referência, data
  assert.match(details, /h-\[3\.6mm\] truncate text-\[9\.5px\]/); // Nº
  assert.match(details, /h-\[4\.6mm\] truncate text-\[12\.5px\] leading-\[4\.6mm\]/); // nome
  const printCard = sheet.slice(sheet.indexOf("function PrintCard"), sheet.indexOf("function StateMessage"));
  assert.match(printCard, /flex items-start/); // topo alinhado: base da miniatura = base da data
  assert.match(printCard, /style=\{\{ width: `\$\{SET_FAVORITES_PRINT_THUMB_MM\.width\}mm`, height: `\$\{SET_FAVORITES_PRINT_THUMB_MM\.height\}mm` \}\}/);
});

test("gate de impressão: atualização síncrona ao terminar cada miniatura (1ª impressão nunca sai com o aviso)", () => {
  const gate = read("../../components/reports/print-image-gate.tsx");
  assert.match(gate, /import \{ flushSync \} from "react-dom";/);
  assert.match(gate, /const onImage = \(\) => flushSync\(\(\) => setPending\(count\(\)\)\);/);
  assert.match(gate, /img\.addEventListener\("load", onImage\);/);
  assert.match(gate, /if \(ok\) await new Promise<void>\(\(resolve\) => requestAnimationFrame\(\(\) => resolve\(\)\)\);/);
  // Imagem do cache fica pronta sem `load` a tempo: o preparo avisa o gate de forma síncrona (evento).
  assert.match(gate, /root\.dispatchEvent\(new Event\(READY_EVENT\)\);/);
  assert.match(gate, /root\.addEventListener\(READY_EVENT, onImage\);/);
  assert.ok(gate.indexOf("root.dispatchEvent(new Event(READY_EVENT));") < gate.indexOf("if (ok) await new Promise<void>")); // avisa antes de liberar a impressão
});
