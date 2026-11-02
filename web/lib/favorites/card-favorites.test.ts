// V1-10 — Favoritos de cartas: regras puras.
// Executar: node --experimental-strip-types --test lib/favorites/card-favorites.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import {
  favoritesKpis,
  chunkIds,
  favoriteCardNameFromLabel,
  favoriteToggleLabel,
  initialFavoriteEntry,
  normalizeId,
  parseFavoriteCardsPage,
  parsePageParam,
  settleCardFavorite,
  toFavoriteIdSet,
  toggleCardFavorite,
  toVariantFavoriteMap,
  parseFavoriteReferenceValue,
  formatBrlWhole,
  visibleFavoriteCards,
} from "./card-favorites.ts";

const CARD = "11111111-1111-4111-8111-111111111111";
const CARD_B = "22222222-2222-4222-8222-222222222222";
const VARIANT = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";

test("ids: normaliza, descarta inválidos e duplicados, blocos de até 500 (nunca 1 chamada por carta)", () => {
  assert.equal(normalizeId(CARD.toUpperCase()), CARD);
  assert.equal(normalizeId("x"), null);
  assert.deepEqual(chunkIds([CARD, CARD.toUpperCase(), "lixo", null, CARD_B]), [[CARD, CARD_B]]);
  const many = Array.from({ length: 1001 }, (_, i) => `00000000-0000-4000-8000-${String(i).padStart(12, "0")}`);
  const blocks = chunkIds(many);
  assert.deepEqual(blocks.map((b) => b.length), [500, 500, 1]);
  assert.deepEqual(chunkIds([]), []);
});

test("lote por carta e por variante: só linhas dentro do contrato", () => {
  assert.deepEqual([...toFavoriteIdSet([{ card_id: CARD }, { card_id: "x" }, {}])], [CARD]);
  const map = toVariantFavoriteMap([
    { card_variant_id: VARIANT, card_id: CARD, is_favorite: true },
    { card_variant_id: VARIANT.replace("a", "b"), card_id: CARD, is_favorite: "true" },
  ]);
  assert.equal(map.size, 1);
  assert.deepEqual(map.get(VARIANT), { cardId: CARD, isFavorite: true });
});

test("máquina: clique otimista, uma gravação por vez, última intenção vence", () => {
  let entry = initialFavoriteEntry(false);
  let step = toggleCardFavorite(CARD, entry);
  assert.deepEqual(step.send, { cardId: CARD, value: true });
  entry = step.entry;
  // Novo clique durante a gravação: nada sai agora; a tela mostra a última intenção (false).
  entry = toggleCardFavorite(CARD, entry).entry; // desired false
  assert.equal(entry.desired, false);
  assert.equal(toggleCardFavorite(CARD, entry).send, null);
  // Gravação de "true" confirmada, mas a intenção atual é false → reenvia false.
  const settled = settleCardFavorite(CARD, entry, { ok: true, value: true });
  assert.deepEqual(settled.send, { cardId: CARD, value: false });
  assert.equal(settled.entry.confirmed, true);
  const done = settleCardFavorite(CARD, settled.entry, { ok: true, value: false });
  assert.equal(done.send, null);
  assert.deepEqual(done.entry, { confirmed: false, desired: false, inFlight: false });
});

test("máquina: falha reverte ao último estado confirmado (nada fica favoritado de mentira)", () => {
  const step = toggleCardFavorite(CARD, initialFavoriteEntry(false));
  const failed = settleCardFavorite(CARD, step.entry, { ok: false });
  assert.equal(failed.reverted, true);
  assert.deepEqual(failed.entry, { confirmed: false, desired: false, inFlight: false });
});

test("rótulo acessível constante e nome recuperável dele", () => {
  assert.equal(favoriteToggleLabel("Pikachu"), "Favoritar Pikachu");
  assert.equal(favoriteCardNameFromLabel("Favoritar Pikachu"), "Pikachu");
  assert.equal(favoriteCardNameFromLabel("Outro"), null);
});

test("página de favoritos: contrato, total e paginação", () => {
  assert.equal(parseFavoriteCardsPage(null), null);
  const page = parseFavoriteCardsPage([
    {
      card_id: CARD, card_name: "Pikachu", collector_number: "025", collector_total: 165,
      card_set_code: "SV1", card_set_name: "Escarlate e Violeta", image_path_pt: "a.png", image_path_en: null,
      favorited_at: "2026-10-31T12:00:00Z", total_count: 61,
    },
    { card_id: "x", card_name: "inválida", favorited_at: "2026-10-31T12:00:00Z", total_count: 61 },
  ]);
  assert.equal(page?.cards.length, 1);
  assert.equal(page?.totalCount, 61);
  assert.equal(page?.cards[0]?.imagePathEn, null);
  assert.equal(parsePageParam("3"), 3);
  assert.equal(parsePageParam("0"), 1);
  assert.equal(parsePageParam(["2"]), 2);
  assert.equal(parsePageParam("abc"), 1);
});

test("painel de favoritos: só números sustentados por contrato; ausência nunca vira zero", () => {
  const format = (value: number) => String(value);
  const formatMoney = (value: number) => `R$ ${value.toFixed(2)}`;
  const base = { format, formatMoney, ownedCount: 3, favoriteCardSetCount: 2 };
  const kpis = favoritesKpis({ ...base, favoriteCount: 8, referenceValue: { favoriteCount: 8, pricedCount: 6, totalBrl: 123.4 } });
  assert.deepEqual(kpis.map((kpi) => kpi.key), ["reference_value", "favorites", "owned", "favorite_card_sets"]);
  assert.equal(kpis[1]?.value, "8");
  assert.equal(kpis[0]?.lead, true);
  assert.equal(kpis[1]?.lead, undefined);
  assert.equal(kpis[0]?.value, "R$ 123.40");
  assert.equal(kpis[0]?.hint, "6 de 8 com cotação");
  assert.equal(kpis[2]?.value, "3");
  assert.equal(kpis[2]?.name, "No meu acervo");
  assert.equal(kpis[2]?.hint, "favoritas que você possui");
  assert.equal(kpis[3]?.value, "2");
  assert.equal(kpis[3]?.name, "Card Sets");
  assert.equal(kpis[3]?.hint, "com cartas favoritas");
  // Valor: sem cobertura → "—" com a cobertura; sem favoritas e leitura falha → "—" com motivo.
  const uncovered = favoritesKpis({ ...base, favoriteCount: 4, referenceValue: { favoriteCount: 4, pricedCount: 0, totalBrl: null } })[0];
  assert.equal(uncovered?.value, null);
  assert.equal(uncovered?.hint, "0 de 4 com cotação");
  assert.equal(favoritesKpis({ ...base, favoriteCount: 0, referenceValue: { favoriteCount: 0, pricedCount: 0, totalBrl: null } })[0]?.hint, "sem cartas favoritas");
  const failed = favoritesKpis({ ...base, favoriteCount: 3, referenceValue: null, ownedCount: null, favoriteCardSetCount: null });
  assert.deepEqual([failed[0], failed[2], failed[3]].map((kpi) => [kpi?.value, kpi?.hint]), [
    [null, "indisponível agora"],
    [null, "indisponível agora"],
    [null, "indisponível agora"],
  ]);
  // Zero legítimo continua zero.
  const zero = favoritesKpis({ ...base, favoriteCount: 2, referenceValue: { favoriteCount: 2, pricedCount: 1, totalBrl: 0 }, ownedCount: 0, favoriteCardSetCount: 0 });
  assert.equal(zero[0]?.value, "R$ 0.00");
  assert.equal(zero[1]?.value, "2");
  assert.equal(zero[2]?.value, "0");
  assert.equal(zero[3]?.value, "0");
  assert.equal(favoritesKpis({ ...base, favoriteCount: 1, referenceValue: null })[1]?.name, "Carta favorita");
  assert.equal(favoritesKpis({ ...base, favoriteCount: 1, referenceValue: null, favoriteCardSetCount: 1 })[3]?.name, "Card Set");
});

test("valor de referência no painel: reais inteiros, arredondado só na apresentação", () => {
  const norm = (value: string) => value.replace(/\u00a0/g, " ");
  assert.equal(norm(formatBrlWhole(3206.75)), "R$ 3.207");
  assert.equal(norm(formatBrlWhole(2215.49)), "R$ 2.215");
  assert.equal(norm(formatBrlWhole(0.4)), "R$ 0");
  assert.equal(norm(formatBrlWhole(1234567.5)), "R$ 1.234.568");
  // O contrato lido continua com centavos: o arredondamento não volta para o dado.
  const reference = parseFavoriteReferenceValue([{ favorite_count: 8, priced_count: 8, total_brl: 3206.75 }]);
  assert.equal(reference?.totalBrl, 3206.75);
  const kpi = favoritesKpis({ favoriteCount: 8, referenceValue: reference, ownedCount: 7, favoriteCardSetCount: 2, format: String, formatMoney: formatBrlWhole })[0];
  assert.equal(norm(kpi?.value ?? ""), "R$ 3.207");
});

test("valor de referência: só a forma da 5340 é aceita", () => {
  assert.deepEqual(parseFavoriteReferenceValue([{ favorite_count: 8, priced_count: 6, total_brl: 123.4 }]), { favoriteCount: 8, pricedCount: 6, totalBrl: 123.4 });
  assert.deepEqual(parseFavoriteReferenceValue({ favorite_count: "3", priced_count: "1", total_brl: "10.50" }), { favoriteCount: 3, pricedCount: 1, totalBrl: 10.5 });
  assert.deepEqual(parseFavoriteReferenceValue([{ favorite_count: 0, priced_count: 0, total_brl: null }]), { favoriteCount: 0, pricedCount: 0, totalBrl: null });
  assert.equal(parseFavoriteReferenceValue([]), null);
  assert.equal(parseFavoriteReferenceValue([{ favorite_count: 1, priced_count: 0, total_brl: null }, { favorite_count: 1, priced_count: 0, total_brl: null }]), null);
  assert.equal(parseFavoriteReferenceValue({ favorite_count: 2, priced_count: 3, total_brl: 1 }), null);
  assert.equal(parseFavoriteReferenceValue({ favorite_count: 2, priced_count: 1, total_brl: null }), null);
  assert.equal(parseFavoriteReferenceValue({ favorite_count: 2, priced_count: 0, total_brl: 5 }), null);
  assert.equal(parseFavoriteReferenceValue({ favorite_count: 2, priced_count: 1, total_brl: -1 }), null);
  assert.equal(parseFavoriteReferenceValue({ favorite_count: 1.5, priced_count: 1, total_brl: 1 }), null);
  assert.equal(parseFavoriteReferenceValue(null), null);
});

// HOMOLOGATION-04 — desfavoritar na página Cartas favoritas
test("favoritas: carta desfavoritada (confirmada) sai da grade; Desfazer recoloca sem duplicar", () => {
  const server = [{ id: "A" }, { id: "b" }, { id: "c" }];
  assert.deepEqual(visibleFavoriteCards(server, new Set(["a"]), []).map((c) => c.id), ["b", "c"]);
  // Antes da releitura: restaurada aparece na hora; depois da releitura: uma vez só.
  assert.deepEqual(visibleFavoriteCards([{ id: "b" }], new Set(), [{ id: "a" }]).map((c) => c.id), ["a", "b"]);
  assert.deepEqual(visibleFavoriteCards(server, new Set(), [{ id: "a" }]).map((c) => c.id), ["A", "b", "c"]);
  // Nada oculto = lista intacta (nenhuma outra carta some).
  assert.deepEqual(visibleFavoriteCards(server, new Set(), []).length, 3);
});

test("favoritas (estático): remoção só após confirmação do servidor + releitura da página", () => {
  const view = readFileSync(new URL("../../components/favorites/favorite-cards-view.tsx", import.meta.url), "utf8");
  assert.match(view, /onConfirmed=\{onFavoriteConfirmed\}/);
  assert.match(view, /router\.refresh\(\)/);
  assert.match(view, /visible\.map\(/);
  assert.doesNotMatch(view, /\{cards\.map\(/);
  const ctrl = readFileSync(new URL("../../components/favorites/card-favorites-controller.tsx", import.meta.url), "utf8");
  // onConfirmed só no ramo final (não revertido) da máquina de intenção.
  assert.ok(ctrl.indexOf("if (step.reverted)") < ctrl.indexOf("onConfirmed?.("));
  assert.match(ctrl, /mode === "favorites" && !step\.entry\.confirmed\) entries\.current\.delete/);
});
