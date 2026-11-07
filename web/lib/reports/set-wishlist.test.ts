// V1-14 R2-C — "Cartas desejadas do Card Set" (D7 v1.48 §4k): filtro pelo Card Set canônico da
// coleção autorizada, reimpressões fora, quatro estados C-213, qualquer idioma, mesma variante em
// dois idiomas, valor de todas as variantes sem duplicação, sem cotação × indisponível, variante
// desativada, estados, divergência e teto, autorização antes dos desejos, nenhum identificador do
// navegador, lista única sem filtro/grupo por posse, miniaturas e impressão, regressão (R1-E, R2-A, R2-B).
// Executar: node --experimental-strip-types --test lib/reports/set-wishlist.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { collectionReportItems } from "./collection-checklist.ts";
import { prepareSetWishlistReport } from "./set-wishlist-queries.ts";
import { buildSetWishlistReport, setWishlistIncompleteText } from "./set-wishlist.ts";
import { buildWishlistReport, wishOwnershipText, wishlistIncompleteText } from "./wishlist-report.ts";

console.error = () => {};
console.warn = () => {};
console.info = () => {};

const read = (path: string) => readFileSync(new URL(path, import.meta.url), "utf8");
const uuid = (n: number) => `00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`;
const COLLECTION = uuid(9001);
const SET_ME55 = uuid(5500);
const SET_ME55CC = uuid(5501);

type Wish = {
  n: number;
  variant: number;
  card?: number;
  set?: "ME5.5" | "ME5.5CC";
  lang?: string | null;
  ownership?: "SAME_VARIANT_LANGUAGE" | "SAME_VARIANT_OTHER_LANGUAGE" | "OTHER_VARIANT" | "NONE";
  available?: boolean;
};
function wishRow(w: Wish, total: number) {
  return {
    entry_id: uuid(1000 + w.n),
    card_variant_id: uuid(2000 + w.variant),
    card_id: uuid(3000 + (w.card ?? w.variant)),
    card_name: `Carta ${w.card ?? w.variant}`,
    collector_number: String(w.card ?? w.variant).padStart(3, "0"),
    collector_total: 158,
    card_set_id: w.set === "ME5.5CC" ? SET_ME55CC : SET_ME55,
    card_set_code: w.set ?? "ME5.5",
    card_set_name: w.set === "ME5.5CC" ? "Coleção Clássica" : "Celebração de 30 Anos",
    rarity_id: null,
    rarity_name: null,
    variant_label: "Holo",
    variant_available: w.available ?? true,
    language_code: w.lang === undefined ? "pt-BR" : w.lang,
    ownership: w.ownership ?? "NONE",
    image_path_pt: `cards/${w.variant}.webp`,
    image_path_en: null,
    wished_at: "2026-11-07T12:00:00Z",
    total_count: total,
  };
}

type Call = { fn: string; args: Record<string, unknown> };
function fakeClient(
  wishes: Wish[],
  options: { policy?: string; collection?: "missing" | "error"; cardSetId?: string | null; prices?: Record<number, number | null>; failPrices?: boolean; totalDelta?: number; leakSet?: boolean } = {},
) {
  const calls: Call[] = [];
  const order: string[] = [];
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
                completion_policy: options.policy ?? "STANDARD_SET",
                lifecycle_status: "ACTIVE",
                card_set_id: options.cardSetId === undefined ? SET_ME55 : options.cardSetId,
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
        if (fn === "get_my_wishlist_filtered") {
          // O "banco": filtra pelo Card Set recebido — só o da coleção autorizada.
          const filtered = wishes.filter((w) => options.leakSet || (w.set === "ME5.5CC" ? SET_ME55CC : SET_ME55) === args.p_card_set_id);
          const offset = Number(args.p_offset);
          const total = filtered.length + (options.totalDelta ?? 0);
          return { data: filtered.slice(offset, offset + Number(args.p_limit)).map((w) => wishRow(w, total)), error: null };
        }
        if (fn === "get_card_variants_pricing_summary") {
          if (options.failPrices) return { data: null, error: { code: "42501" } };
          const ids = args.p_card_variant_ids as string[];
          return {
            data: ids.map((id) => {
              const v = Number.parseInt(id.slice(-12), 16) - 2000;
              const brl = options.prices?.[v] ?? null;
              return { card_variant_id: id, has_pricing: brl !== null, brl_amount: brl, price_basis: "VARIANT", price_origin: "AUTOMATIC", fx_status: "CONFIRMED", observed_at: "2026-11-01T00:00:00Z" };
            }),
            error: null,
          };
        }
        return { data: null, error: { code: "PGRST202" } };
      },
    },
  };
}

async function prepare(wishes: Wish[], options: Parameters<typeof fakeClient>[1] = {}) {
  const fake = fakeClient(wishes, options);
  const result = await prepareSetWishlistReport(fake.client as never, COLLECTION, (p) => `https://img/${p}`, new Date("2026-11-07T12:00:00Z"));
  return { ...fake, result };
}

test("autorização antes dos desejos; Card Set só da coleção autorizada; nenhum identificador do navegador", async () => {
  const { result, calls, order } = await prepare([{ n: 1, variant: 1 }]);
  assert.equal(result.status, "ready");
  assert.equal(calls[0]?.fn, "get_my_collection");
  assert.ok(order.indexOf("get_my_collection:end") < order.indexOf("get_my_wishlist_filtered:start")); // 5351 só depois da 5332
  const wish = calls.find((c) => c.fn === "get_my_wishlist_filtered");
  assert.equal(wish?.args.p_card_set_id, SET_ME55); // o Card Set devolvido pela coleção
  assert.equal(wish?.args.p_sort, "SET_NUMBER");
  assert.equal(wish?.args.p_limit, 100);
  // Nenhum identificador de titular (p_ownership é o filtro de posse da 5351, nulo aqui).
  assert.ok(calls.every((c) => Object.keys(c.args).every((key) => !/user|owner_id|owner_user|profile/i.test(key))));
  assert.equal(wish?.args.p_ownership, null);
  // A ação só aceita o id da coleção (validado); nenhum Card Set vem do cliente.
  const actions = read("../../app/colecoes/colecoes/[id]/relatorios/actions.ts");
  assert.match(actions, /export async function readSetWishlistReport\(input: \{ collectionId: string \}\)/);
  assert.match(actions, /prepareSetWishlistReport\(supabase, input\.collectionId\.toLowerCase\(\), imageUrl\)/);
  // Coleção alheia/inexistente, falha de leitura, sem Card Set ou objetivo sem Set: nenhum desejo lido.
  for (const [opts, status] of [
    [{ collection: "missing" }, "not_found"],
    [{ collection: "error" }, "error"],
    [{ cardSetId: null }, "unavailable"],
    [{ policy: "REFERENCE_POSITION" }, "unavailable"],
    [{ policy: "NONE" }, "unavailable"],
  ] as const) {
    const r = await prepare([{ n: 1, variant: 1 }], opts);
    assert.equal(r.result.status, status, JSON.stringify(opts));
    assert.ok(!r.calls.some((c) => c.fn === "get_my_wishlist_filtered"), `sem 5351 em ${JSON.stringify(opts)}`);
  }
});

test("filtro pelo Card Set canônico: reimpressões de outro Set (ME5.5CC) não entram; desejo de outro Set na resposta → inconsistência", async () => {
  const wishes: Wish[] = [
    { n: 1, variant: 1 },
    { n: 2, variant: 50, set: "ME5.5CC" },
  ];
  const { result } = await prepare(wishes);
  assert.equal(result.status === "ready" && result.data.report.entryCount, 1);
  const leak = await prepare(wishes, { leakSet: true });
  assert.equal(leak.result.status === "ready" && leak.result.data.report.incompleteReason, "set_mismatch");
  assert.match(setWishlistIncompleteText("set_mismatch", wishlistIncompleteText) ?? "", /impressão fica indisponível/);
});

test("todos os desejos aparecem, qualquer que seja a posse, numa lista única e ordenada; quatro estados preservados", async () => {
  const wishes: Wish[] = [
    { n: 1, variant: 4, ownership: "NONE" },
    { n: 2, variant: 1, ownership: "SAME_VARIANT_LANGUAGE" },
    { n: 3, variant: 3, ownership: "OTHER_VARIANT" },
    { n: 4, variant: 2, ownership: "SAME_VARIANT_OTHER_LANGUAGE" },
    { n: 5, variant: 5, lang: null, ownership: "SAME_VARIANT_LANGUAGE" }, // qualquer idioma, satisfeito pela 5351
  ];
  const { result } = await prepare(wishes);
  assert.equal(result.status, "ready");
  if (result.status !== "ready") return;
  const r = result.data.report;
  assert.equal(r.state, "list");
  assert.equal(r.lines.length, 5); // nenhum desejo excluído por posse
  assert.deepEqual(r.lines.map((l) => l.collectorNumber), ["001", "002", "003", "004", "005"]); // ordem canônica (número)
  assert.deepEqual(r.lines.map((l) => l.ownership), ["SAME_VARIANT_LANGUAGE", "SAME_VARIANT_OTHER_LANGUAGE", "OTHER_VARIANT", "NONE", "SAME_VARIANT_LANGUAGE"]);
  assert.equal(r.lines[4]?.languageCode, null);
  assert.deepEqual(
    ["SAME_VARIANT_LANGUAGE", "SAME_VARIANT_OTHER_LANGUAGE", "OTHER_VARIANT", "NONE"].map((o) => wishOwnershipText(o as never)),
    ["Já no acervo", "No acervo em outro idioma", "Você tem outra variante", "Não possui"],
  );
  // Todos já no acervo: a lista continua normal (sem estado alternativo que a substitua).
  const all = await prepare([{ n: 1, variant: 1, ownership: "SAME_VARIANT_LANGUAGE" }]);
  assert.equal(all.result.status === "ready" && all.result.data.report.state, "list");
  assert.equal(all.result.status === "ready" && all.result.data.report.lines.length, 1);
  const sheet = read("../../components/reports/set-wishlist-report.tsx");
  assert.doesNotMatch(sheet, /Pendentes|Já no acervo"|aria-pressed|setFilter|groups|Todos os desejos deste Card Set já estão/); // sem filtros, grupos nem estado alternativo
  assert.match(sheet, /\{report\.lines\.map\(\(line\) => \(\s*<ScreenCard key=\{line\.entryId\}/);
  assert.match(sheet, /wishOwnershipText\(line\.ownership\)/); // a posse segue em cada cartão
});

test("cartas e variantes distintas; Referência NM de TODAS as variantes (atendidas e pendentes), uma vez cada; centavos; sem cotação × indisponível", async () => {
  const wishes: Wish[] = [
    { n: 1, variant: 1, card: 10, lang: "pt-BR", ownership: "SAME_VARIANT_LANGUAGE" },
    { n: 2, variant: 1, card: 10, lang: "en", ownership: "SAME_VARIANT_OTHER_LANGUAGE" }, // mesma variante, outro idioma
    { n: 3, variant: 2, card: 10, ownership: "NONE" }, // outra variante da mesma carta
    { n: 4, variant: 3, card: 11, ownership: "NONE" }, // sem cotação
    { n: 5, variant: 4, card: 12, ownership: "SAME_VARIANT_LANGUAGE" }, // atendida: ENTRA no valor
  ];
  const { result } = await prepare(wishes, { prices: { 1: 10.1, 2: 0.33, 3: null, 4: 99 } });
  assert.equal(result.status, "ready");
  if (result.status !== "ready") return;
  const r = result.data.report;
  assert.equal(r.entryCount, 5);
  assert.equal(r.cardCount, 3); // 10, 11, 12
  assert.equal(r.variantCount, 4); // 1, 2, 3, 4
  assert.equal(r.value.variants, 4);
  assert.equal(r.value.totalBrl, 109.43); // 10,10 + 0,33 + 99,00 — a variante 1 conta uma vez, nunca 2 × 10,10
  assert.equal(r.value.priced, 3);
  assert.equal(r.complete, true); // sem cotação não bloqueia
  assert.equal(r.lines.find((l) => l.cardVariantId === uuid(2003))?.reference.kind, "none");
  // Falha de preço: provisório, linhas preservadas, impressão bloqueada.
  const failed = await prepare(wishes, { failPrices: true });
  assert.equal(failed.result.status === "ready" && failed.result.data.report.incompleteReason, "prices_unavailable");
  assert.equal(failed.result.status === "ready" && failed.result.data.report.lines.length, 5);
  assert.equal(failed.result.status === "ready" && failed.result.data.report.lines[0]?.reference.kind, "unavailable");
  assert.equal(failed.result.status === "ready" && failed.result.data.report.value.totalBrl, null);
});

test("variante desativada continua listada e sinalizada; estado vazio explicativo", async () => {
  const off = await prepare([{ n: 1, variant: 1, available: false }]);
  assert.equal(off.result.status === "ready" && off.result.data.report.lines[0]?.variantAvailable, false);
  assert.match(read("../../components/reports/set-wishlist-report.tsx"), /line\.variantAvailable \? null : <span[^>]*> · Indisponível no catálogo<\/span>/);
  const empty = await prepare([]);
  assert.equal(empty.result.status === "ready" && empty.result.data.report.state, "empty");
  assert.equal(empty.result.status === "ready" && empty.result.data.report.complete, true);
  assert.ok(!empty.calls.some((c) => c.fn === "get_card_variants_pricing_summary")); // nada a cotar
  assert.match(read("../../components/reports/set-wishlist-report.tsx"), /Nenhum desejo deste Card Set na sua Lista de Desejos\./);
});

test("divergência de totais e teto de 5.000 → incompleto (regras da R1-E)", async () => {
  const changed = await prepare([{ n: 1, variant: 1 }], { totalDelta: 1 });
  assert.equal(changed.result.status === "ready" && changed.result.data.report.incompleteReason, "changed");
  const r = buildSetWishlistReport({
    wishlist: buildWishlistReport({ entries: [], totalCount: 6000, withinLimit: false, prices: new Map(), unavailable: new Set() }),
    cardSetCode: "ME5.5",
  });
  assert.equal(r.incompleteReason, "too_large");
  assert.equal(r.complete, false);
  // Paginação de 100: 250 desejos = 3 páginas.
  const many = Array.from({ length: 250 }, (_, i) => ({ n: i + 1, variant: i + 1 }));
  const big = await prepare(many);
  assert.equal(big.calls.filter((c) => c.fn === "get_my_wishlist_filtered").length, 3);
  assert.equal(big.result.status === "ready" && big.result.data.report.entryCount, 250);
});

test("impressão: todos os desejos em cartões de duas colunas, miniaturas preparadas pela R1-G; indicadores e cabeçalho", async () => {
  const many = Array.from({ length: 37 }, (_, i) => ({ n: i + 1, variant: i + 1, ownership: (i % 2 === 0 ? "NONE" : "SAME_VARIANT_LANGUAGE") as Wish["ownership"] }));
  const { result } = await prepare(many);
  assert.equal(result.status, "ready");
  if (result.status !== "ready") return;
  const r = result.data.report;
  assert.equal(r.lines.length, 37); // impressão = r.lines inteira (não há filtro de tela)
  assert.equal(r.lines[0]?.imageUrl, "https://img/cards/1.webp"); // imagem canônica, sem transformação
  const sheet = read("../../components/reports/set-wishlist-report.tsx");
  assert.match(sheet, /<div className="hidden print:block">\s*<PrintImageGate>\s*<PrintList lines=\{report\.lines\} \/>/);
  const printPart = sheet.slice(sheet.indexOf("function PrintList"), sheet.indexOf("function StateMessage"));
  assert.match(printPart, /<col style=\{\{ width: "50%" \}\} \/>\s*<col style=\{\{ width: "50%" \}\} \/>/);
  assert.match(printPart, /<tr key=\{left\.entryId\} style=\{\{ breakInside: "avoid" \}\}>/);
  assert.match(printPart, /h-\[5mm\] w-\[5mm\]/); // caixa de 5 mm
  assert.match(sheet, /SET_WISH_PRINT_THUMB_MM = \{ width: 16\.8, height: 23\.4 \}/);
  assert.match(printPart, /<WishDetails line=\{line\} print \/>/);
  const details = sheet.slice(sheet.indexOf("function WishDetails"), sheet.indexOf("function PrintList"));
  for (const piece of ["wishCollectorText(line)", "line.cardName", "wishVariantText(line)", "wishOwnershipText(line.ownership)", "Referência NM: ", "Desejado em {wishedAtText(line.wishedAt)}"])
    assert.ok(details.includes(piece), piece);
  assert.doesNotMatch(printPart, /min-h-\[|minHeight/); // altura variável
  const head = sheet.slice(sheet.indexOf("<thead>"), sheet.indexOf("</thead>"));
  assert.match(head, /\{cabecalho\}/);
  assert.doesNotMatch(head, /Indicator/); // KPIs só na 1ª página
  for (const label of ["Desejos", "Cartas distintas", "Variantes distintas", "Referência NM"]) assert.match(sheet, new RegExp(`label="${label}"`), label);
  assert.doesNotMatch(sheet, /label="Referência NM dos pendentes"/);
  assert.match(sheet, /value=\{valueText\} note=\{wishCoverageText\(report\.value\)\}/);
  assert.match(sheet, /não custo de\s+aquisição/);
  assert.match(sheet, /considera todo o seu acervo, não só os\s+exemplares desta coleção/);
  const overlay = read("../../components/reports/set-wishlist-overlay.tsx");
  assert.match(overlay, /shareInFlight\(\(\) => readSetWishlistReport\(\{ collectionId \}\)\)/);
  assert.match(overlay, /preparePrint: data\.report\.state !== "empty" \? \(onProgress\) => preparePrintImages\(onProgress\) : undefined/);
  for (const source of [sheet, overlay]) assert.doesNotMatch(source, /render\/image|\?width=|&quality=/);
  assert.doesNotMatch(read("./set-wishlist.ts"), /pending|satisfied|filter/i); // nenhuma classificação por posse nas regras
});

test("menu da coleção e regressão: R2-A, R2-B e R1-E inalterados", () => {
  const c = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
  const set = collectionReportItems({ collectionId: c, completionPolicy: "MASTER_SET", totalPositions: 100, satisfiedPositions: 62 });
  assert.deepEqual(set.map((i) => i.id).slice(0, 3), ["checklist", "missing", "set-wishlist"]); // R2-D entra depois (set-favorites.test.ts)
  assert.equal(set[2]?.label, "Cartas desejadas do Card Set");
  assert.equal(set[2]?.icon, "wish");
  assert.equal(set[2]?.disabledReason, null);
  assert.equal(set[0]?.metric, "62%"); // Checklist
  assert.equal(set[1]?.metric, "38 faltam"); // Cartas faltantes
  for (const policy of ["REFERENCE_POSITION", "NONE"]) {
    const items = collectionReportItems({ collectionId: c, completionPolicy: policy, totalPositions: 10, satisfiedPositions: 1 });
    assert.equal(items[2]?.disabledReason, "Para coleções de Set padrão e Master Set.");
  }
  const action = read("../../components/reports/collection-reports-action.tsx");
  assert.match(action, /report === "set-wishlist" \? <SetWishlistOverlay collectionId=\{collectionId\}/);
  // R1-E continua lendo a lista inteira (sem Card Set).
  const r1e = read("./wishlist-report-queries.ts");
  assert.match(r1e, /const wishes = await readAllWishes\(supabase\);/);
  assert.match(r1e, /export async function readAllWishes\(supabase: Rpc, cardSetId: string \| null = null\)/);
  for (const source of [read("./set-wishlist.ts"), read("./set-wishlist-queries.ts")]) assert.doesNotMatch(source, /\.insert\(|\.update\(|\.delete\(|\.upsert\(/);
});

test("miniaturas com a altura do bloco de texto: tela 62 × 86 px e impressão 16,8 × 23,4 mm, proporção da carta", () => {
  const sheet = read("../../components/reports/set-wishlist-report.tsx");
  assert.match(sheet, /SET_WISH_SCREEN_TEXT_PX = 14 \+ 16 \+ 14 \+ 14 \+ 14 \+ 14;/); // 86 px
  assert.match(sheet, /SET_WISH_SCREEN_THUMB_PX = \{ width: 62, height: SET_WISH_SCREEN_TEXT_PX \}/);
  assert.ok(Math.abs(62 / 86 - 63 / 88) < 0.01);
  assert.match(sheet, /SET_WISH_PRINT_TEXT_MM = 3\.6 \+ 4\.6 \+ 3\.8 \+ 3\.8 \+ 3\.8 \+ 3\.8;/); // 23,4 mm
  assert.ok(Math.abs(3.6 + 4.6 + 3.8 * 4 - 23.4) < 1e-9);
  assert.ok(Math.abs(16.8 / 23.4 - 63 / 88) < 0.005);
  const details = sheet.slice(sheet.indexOf("function WishDetails"), sheet.indexOf("function PrintList"));
  assert.match(details, /const row = print \? "h-\[3\.8mm\] leading-\[3\.8mm\] truncate" : "h-\[14px\] leading-\[14px\] truncate";/);
  assert.equal((details.match(/\$\{row\}/g) ?? []).length, 5); // Nº (tela), variante, situação, referência, data
  const screen = sheet.slice(sheet.indexOf("function ScreenCard"), sheet.indexOf("function WishDetails"));
  assert.match(screen, /style=\{\{ width: SET_WISH_SCREEN_THUMB_PX\.width, height: SET_WISH_SCREEN_THUMB_PX\.height \}\}/);
  assert.match(screen, /className="absolute inset-0 h-full w-full object-cover"/); // a imagem nunca dita o tamanho
  assert.doesNotMatch(screen, /h-\[56px\] w-\[40px\]/);
});
