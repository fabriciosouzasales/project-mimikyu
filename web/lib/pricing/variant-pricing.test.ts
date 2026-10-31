// Preço NM por variante (V1-09) — regras puras.
// Executar: node --experimental-strip-types --test lib/pricing/variant-pricing.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { test } from "node:test";
import {
  FUTURE_TOLERANCE_MS,
  PRICE_STALE_AFTER_DAYS,
  VARIANT_PRICING_MAX_BODY_BYTES,
  VARIANT_PRICING_MAX_RAW_ENTRIES,
  NM_REFERENCE_NOTE,
  chunkVariantIds,
  compactPriceDetail,
  daysSince,
  formatBrl,
  isInternationalReference,
  isPriceMuted,
  isPriceShown,
  observedDateIssue,
  parseVariantPrices,
  priceIndicator,
  priceAccessibleText,
  priceDetail,
  priceState,
  validateVariantIdsBody,
  type VariantPrice,
} from "./variant-pricing.ts";
import { readJsonBodyWithLimit } from "./variant-pricing-request.ts";
import { BINDER_PRICES_STORAGE_KEY, parseBinderPricesPref, serializeBinderPricesPref } from "../colecoes/binder-price-pref.ts";

const NORMAL = "11111111-1111-4111-8111-111111111111";
const REVERSE = "22222222-2222-4222-8222-222222222222";
const NOW = Date.parse("2026-10-30T12:00:00Z");
const DAY = 86_400_000;

function iso(daysAgo: number): string {
  return new Date(NOW - daysAgo * DAY).toISOString();
}

function row(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    card_variant_id: NORMAL,
    card_id: "33333333-3333-4333-8333-333333333333",
    has_pricing: true,
    brl_amount: "1.14",
    source_amount: 0.21,
    source_currency: "USD",
    fx_status: "CONVERTED",
    printing_label: "Normal",
    price_basis: "VARIANT",
    price_origin: "AUTOMATIC",
    observed_at: iso(2),
    ...overrides,
  };
}

function priceOf(overrides: Record<string, unknown> = {}): VariantPrice {
  const map = parseVariantPrices([row(overrides)]);
  assert.ok(map);
  const price = map.get(String(overrides.card_variant_id ?? NORMAL).toLowerCase());
  assert.ok(price);
  return price;
}

// ---- leitura -------------------------------------------------------------

test("parse: identidade por variante — Normal e Reverse da mesma carta ficam separados", () => {
  const map = parseVariantPrices([
    row({ card_variant_id: NORMAL, brl_amount: 1.14, printing_label: "Normal" }),
    row({ card_variant_id: REVERSE, brl_amount: 7.9, printing_label: "Reverse Holofoil" }),
  ]);
  assert.ok(map);
  assert.equal(map.get(NORMAL)?.brlAmount, 1.14);
  assert.equal(map.get(REVERSE)?.brlAmount, 7.9);
  assert.equal(map.get(REVERSE)?.printingLabel, "Reverse Holofoil");
});

test("parse: numérico como texto, campos ausentes e formato inválido", () => {
  assert.equal(priceOf().brlAmount, 1.14);
  const empty = priceOf({ has_pricing: false, brl_amount: null, source_amount: null, source_currency: null, fx_status: null, printing_label: null, price_basis: null, price_origin: null, observed_at: null });
  assert.equal(empty.basis, null);
  assert.equal(empty.brlAmount, null);
  assert.equal(parseVariantPrices(null), null);
  assert.equal(parseVariantPrices([{ card_variant_id: "x", has_pricing: true }]), null);
  assert.equal(parseVariantPrices([row({ has_pricing: "sim" })]), null);
  assert.equal(parseVariantPrices([])?.size, 0);
});

// ---- cardinalidade (R1) --------------------------------------------------

test("chunk: remove inválidos e duplicados (inclusive caixa), respeita 100 por bloco", () => {
  assert.deepEqual(chunkVariantIds([NORMAL, NORMAL.toUpperCase(), null, undefined, "x", REVERSE]), [[NORMAL, REVERSE]]);
  assert.deepEqual(chunkVariantIds([]), []);
  const ids = Array.from({ length: 205 }, (_, i) => `00000000-0000-4000-8000-${String(i).padStart(12, "0")}`);
  const chunks = chunkVariantIds(ids);
  assert.deepEqual(chunks.map((c) => c.length), [100, 100, 5]);
});

test("chunk: fichário — 4 páginas × 20 bolsos (4×5 e 5×4) = 80 ids cabem em uma leitura", () => {
  for (const pockets of [4, 9, 12, 12, 16, 20, 20]) {
    const ids = Array.from({ length: pockets * 4 }, (_, i) => `00000000-0000-4000-8000-${String(i).padStart(12, "0")}`);
    const chunks = chunkVariantIds(ids);
    assert.equal(chunks.length, 1);
    assert.ok(chunks[0]!.length <= 100);
  }
  // Uma vista (2 páginas) com muitos bolsos repetindo a mesma variante: 1 id.
  assert.deepEqual(chunkVariantIds(Array.from({ length: 40 }, () => NORMAL)), [[NORMAL]]);
});

test("endpoint em lote: vazio, formato inválido, mais de 100 distintos, duplicados colapsam", () => {
  assert.deepEqual(validateVariantIdsBody(null), { ok: false, error: "missing_variant_ids" });
  assert.deepEqual(validateVariantIdsBody({ variantIds: [] }), { ok: false, error: "missing_variant_ids" });
  assert.deepEqual(validateVariantIdsBody({ variantIds: [NORMAL, "1; drop"] }), { ok: false, error: "invalid_variant_id" });
  assert.deepEqual(validateVariantIdsBody({ variantIds: [[NORMAL]] }), { ok: false, error: "invalid_variant_id" });
  const many = Array.from({ length: 101 }, (_, i) => `00000000-0000-4000-8000-${String(i).padStart(12, "0")}`);
  assert.deepEqual(validateVariantIdsBody({ variantIds: many }), { ok: false, error: "too_many_variant_ids" });
  const dup = [...Array.from({ length: 150 }, () => NORMAL), REVERSE];
  assert.deepEqual(validateVariantIdsBody({ variantIds: dup }), { ok: true, ids: [NORMAL, REVERSE] });
});

test("C2: lista bruta acima de 400 recusada antes de percorrer; objeto obrigatório", () => {
  assert.equal(VARIANT_PRICING_MAX_RAW_ENTRIES, 400);
  const exact = Array.from({ length: 400 }, () => NORMAL);
  assert.deepEqual(validateVariantIdsBody({ variantIds: exact }), { ok: true, ids: [NORMAL] });
  assert.deepEqual(validateVariantIdsBody({ variantIds: [...exact, NORMAL] }), { ok: false, error: "too_many_entries" });
  // 401 entradas inválidas também param no teto (sem percorrer).
  assert.deepEqual(validateVariantIdsBody({ variantIds: Array.from({ length: 401 }, () => 1) }), { ok: false, error: "too_many_entries" });
  assert.deepEqual(validateVariantIdsBody([NORMAL]), { ok: false, error: "missing_variant_ids" });
  assert.deepEqual(validateVariantIdsBody("x"), { ok: false, error: "missing_variant_ids" });
  assert.deepEqual(validateVariantIdsBody({ variantIds: "abc" }), { ok: false, error: "missing_variant_ids" });
  assert.deepEqual(validateVariantIdsBody({ variantIds: [NORMAL, null] }), { ok: false, error: "invalid_variant_id" });
});

function streamOf(parts: (string | Uint8Array)[]): ReadableStream<Uint8Array> {
  const enc = new TextEncoder();
  return new ReadableStream<Uint8Array>({
    start(controller) {
      for (const part of parts) controller.enqueue(typeof part === "string" ? enc.encode(part) : part);
      controller.close();
    },
  });
}
const json = (extra: Record<string, string> = {}) => new Headers({ "content-type": "application/json", ...extra });

test("C2: corpo limitado — Content-Type, Content-Length, leitura incremental, vazio, JSON malformado", async () => {
  assert.equal(VARIANT_PRICING_MAX_BODY_BYTES, 20_000);
  const max = VARIANT_PRICING_MAX_BODY_BYTES;
  const okBody = JSON.stringify({ variantIds: [NORMAL] });
  assert.deepEqual(await readJsonBodyWithLimit(json(), streamOf([okBody]), max), { ok: true, value: { variantIds: [NORMAL] } });
  // charset e ausência de Content-Type aceitos
  assert.equal((await readJsonBodyWithLimit(new Headers({ "content-type": "application/json; charset=utf-8" }), streamOf([okBody]), max)).ok, true);
  assert.equal((await readJsonBodyWithLimit(new Headers(), streamOf([okBody]), max)).ok, true);
  assert.deepEqual(await readJsonBodyWithLimit(new Headers({ "content-type": "text/plain" }), streamOf([okBody]), max), { ok: false, status: 415, error: "unsupported_media_type" });
  // Content-Length declarado acima do teto: recusa sem ler nada.
  let pulled = false;
  const lazy = new ReadableStream<Uint8Array>({ pull() { pulled = true; } }, { highWaterMark: 0 });
  assert.deepEqual(await readJsonBodyWithLimit(json({ "content-length": String(max + 1) }), lazy, max), { ok: false, status: 413, error: "payload_too_large" });
  assert.equal(pulled, false);
  assert.deepEqual(await readJsonBodyWithLimit(json({ "content-length": "-5" }), streamOf([okBody]), max), { ok: false, status: 400, error: "invalid_content_length" });
  // Sem Content-Length (ou mentindo): corta na leitura.
  const big = "x".repeat(6000);
  assert.deepEqual(await readJsonBodyWithLimit(json(), streamOf([big, big, big, big]), max), { ok: false, status: 413, error: "payload_too_large" });
  assert.deepEqual(await readJsonBodyWithLimit(json({ "content-length": "10" }), streamOf([big, big, big, big]), max), { ok: false, status: 413, error: "payload_too_large" });
  // Exatamente no teto passa da leitura (e falha só no JSON).
  assert.deepEqual(await readJsonBodyWithLimit(json(), streamOf(["x".repeat(max)]), max), { ok: false, status: 400, error: "invalid_json" });
  assert.deepEqual(await readJsonBodyWithLimit(json(), null, max), { ok: false, status: 400, error: "empty_body" });
  assert.deepEqual(await readJsonBodyWithLimit(json(), streamOf([]), max), { ok: false, status: 400, error: "empty_body" });
  assert.deepEqual(await readJsonBodyWithLimit(json(), streamOf(["{oops"]), max), { ok: false, status: 400, error: "invalid_json" });
  assert.deepEqual(await readJsonBodyWithLimit(json(), streamOf([new Uint8Array([0xff, 0xfe, 0x7b])]), max), { ok: false, status: 400, error: "invalid_json" });
  // 400 UUIDs (teto bruto) cabem no teto de bytes.
  const full = JSON.stringify({ variantIds: Array.from({ length: 400 }, () => NORMAL) });
  assert.ok(new TextEncoder().encode(full).byteLength <= max);
});

// ---- estados e D1 --------------------------------------------------------

test("D1: 14 dias ainda é atualizado; 15 dias é desatualizado", () => {
  assert.equal(PRICE_STALE_AFTER_DAYS, 14);
  assert.equal(priceState(priceOf({ observed_at: iso(0) }), NOW), "FRESH");
  assert.equal(priceState(priceOf({ observed_at: iso(14) }), NOW), "FRESH");
  assert.equal(priceState(priceOf({ observed_at: iso(14.99) }), NOW), "FRESH");
  assert.equal(priceState(priceOf({ observed_at: iso(15) }), NOW), "STALE");
  assert.equal(priceState(priceOf({ observed_at: iso(120) }), NOW), "STALE");
});

test("C3: futuro dentro da tolerância de 24 h = atualizado; além disso = data desconhecida", () => {
  assert.equal(FUTURE_TOLERANCE_MS, DAY);
  const at = (ms: number) => new Date(NOW + ms).toISOString();
  // Fusos/relógio: até exatamente 24 h à frente conta como agora.
  assert.equal(daysSince(at(3 * 3600_000), NOW), 0);
  assert.equal(priceState(priceOf({ observed_at: at(3 * 3600_000) }), NOW), "FRESH");
  assert.equal(priceState(priceOf({ observed_at: at(DAY) }), NOW), "FRESH");
  assert.equal(observedDateIssue(at(DAY), NOW), null);
  // Um milissegundo além: inconsistente, nunca atualizado; nada é alterado.
  assert.equal(daysSince(at(DAY + 1), NOW), null);
  assert.equal(priceState(priceOf({ observed_at: at(DAY + 1) }), NOW), "DATE_UNKNOWN");
  assert.equal(observedDateIssue(at(DAY + 1), NOW), "future");
  const far = priceOf({ observed_at: "2099-01-01T00:00:00Z" });
  assert.equal(priceState(far, NOW), "DATE_UNKNOWN");
  assert.equal(far.observedAt, "2099-01-01T00:00:00Z");
  const d = priceDetail(far, { variantName: "Normal", languageCode: "en", now: NOW });
  assert.ok(d.notes.some((n) => n.includes("posterior à data atual")));
  assert.equal(observedDateIssue(null, NOW), "missing");
  assert.equal(observedDateIssue("ontem", NOW), "missing");
});

test("fallback sem data = data desconhecida, nunca atualizado (R2)", () => {
  const fb = priceOf({ price_basis: "CARD_FALLBACK", observed_at: null, source_amount: null, source_currency: null, printing_label: "Holofoil" });
  assert.equal(priceState(fb, NOW), "DATE_UNKNOWN");
  assert.ok(isPriceShown("DATE_UNKNOWN"));
  assert.ok(isPriceMuted("DATE_UNKNOWN"));
  // data ilegível também é desconhecida
  assert.equal(priceState(priceOf({ observed_at: "ontem" }), NOW), "DATE_UNKNOWN");
});

test("câmbio indisponível e sem preço: nada na grade, mensagens distintas", () => {
  const fx = priceOf({ has_pricing: false, brl_amount: null, fx_status: "FX_RATE_UNAVAILABLE", price_basis: null });
  assert.equal(priceState(fx, NOW), "FX_UNAVAILABLE");
  assert.equal(isPriceShown("FX_UNAVAILABLE"), false);
  const none = priceOf({ has_pricing: false, brl_amount: null, fx_status: null, price_basis: null });
  assert.equal(priceState(none, NOW), "UNAVAILABLE");
  assert.equal(priceState(undefined, NOW), "UNAVAILABLE");
  assert.equal(isPriceShown("UNAVAILABLE"), false);
  assert.match(priceDetail(fx, { variantName: "Normal", languageCode: "en", now: NOW }).headline, /câmbio/);
  assert.match(priceDetail(none, { variantName: "Normal", languageCode: "en", now: NOW }).headline, /Sem preço/);
  assert.equal(priceDetail(none, { variantName: "Normal", languageCode: "en", now: NOW }).amount, null);
});

test("has_pricing verdadeiro sem valor nunca vira zero", () => {
  const odd = priceOf({ brl_amount: null });
  assert.equal(priceState(odd, NOW), "UNAVAILABLE");
  assert.equal(priceAccessibleText(odd, NOW), null);
});

// ---- detalhe -------------------------------------------------------------

test("detalhe VARIANT: valor unitário, nome da variante do catálogo, fonte, data, original e câmbio", () => {
  const d = priceDetail(priceOf(), { variantName: "Holográfica reversa", languageCode: "en", now: NOW });
  assert.equal(d.state, "FRESH");
  assert.equal(d.amount, formatBrl(1.14));
  assert.equal(d.headline, "NM · Holográfica reversa");
  assert.deepEqual(d.facts.map((f) => f.label), ["Fonte", "Data de referência", "Valor original", "Câmbio"]);
  assert.equal(d.facts[0]!.value, "JustTCG");
  assert.deepEqual(d.notes, []);
});

test("detalhe CARD_FALLBACK: não atribui a impressão ao exemplar e não usa o nome da variante", () => {
  const fb = priceOf({ price_basis: "CARD_FALLBACK", observed_at: null, source_amount: null, source_currency: null, printing_label: "Holofoil" });
  const d = priceDetail(fb, { variantName: "Holográfica reversa", languageCode: "en", now: NOW });
  assert.equal(d.headline, "NM · preço geral da carta");
  assert.ok(d.notes[0]!.includes("impressão Holográfica"));
  assert.ok(d.notes[0]!.includes("pode não corresponder"));
  assert.equal(d.facts.find((f) => f.label === "Data de referência")?.value, "Não disponível");
  assert.ok(d.notes.some((n) => n.includes("não é possível confirmar")));
  assert.equal(d.facts.some((f) => f.label === "Valor original"), false);
});

test("detalhe: manual, desatualizado e idioma (D4)", () => {
  const manual = priceOf({ price_basis: "CARD_FALLBACK", price_origin: "MANUAL", observed_at: null, source_amount: null, source_currency: null, printing_label: null });
  const dm = priceDetail(manual, { variantName: null, languageCode: "pt-BR", now: NOW });
  assert.equal(dm.facts[0]!.value, "Curadoria MMKYU");
  assert.ok(dm.notes.some((n) => n.includes("manualmente")));
  assert.ok(dm.notes.some((n) => n.includes("mercado internacional")));
  const stale = priceDetail(priceOf({ observed_at: iso(20) }), { variantName: "Normal", languageCode: "ja", now: NOW });
  assert.ok(stale.notes.some((n) => n.includes("há 20 dias")));
});

// ---- composição compacta do detalhe (REFINEMENT-06) ---------------------

test("compacto VARIANT: primário = valor, acabamento, fonte e atualização; secundário = original, câmbio e nota NM", () => {
  const c = compactPriceDetail(priceOf(), { variantName: "Holográfica reversa", languageCode: "en", now: NOW });
  assert.equal(c.amount, formatBrl(1.14));
  assert.equal(c.finish, "Holográfica reversa");
  assert.equal(c.generalCardPrice, false);
  assert.equal(c.source, "JustTCG");
  assert.deepEqual(c.freshness, { tone: "current", text: "Atualizado em 28/10/2026" });
  assert.deepEqual(c.facts.map((f) => f.label), ["Data de referência", "Valor original", "Câmbio"]);
  assert.deepEqual(c.notes, [NM_REFERENCE_NOTE]);
  assert.equal(c.message, null);
});

test("compacto: desatualizado e sem data ficam na camada principal (nunca só no detalhe)", () => {
  const stale = compactPriceDetail(priceOf({ observed_at: iso(PRICE_STALE_AFTER_DAYS + 6) }), { variantName: "Normal", languageCode: "en", now: NOW });
  assert.deepEqual(stale.freshness, { tone: "stale", text: "Desatualizado · há 20 dias" });
  const future = compactPriceDetail(priceOf({ observed_at: new Date(NOW + 3 * DAY).toISOString() }), { variantName: "Normal", languageCode: "en", now: NOW });
  assert.deepEqual(future.freshness, { tone: "unknown", text: "Data inconsistente" });
  assert.ok(future.notes.some((n) => n.includes("posterior à data atual")));
});

test("compacto CARD_FALLBACK: 'preço geral da carta' visível, sem acabamento, sem data; avisos no detalhe", () => {
  const fb = priceOf({ price_basis: "CARD_FALLBACK", observed_at: null, source_amount: null, source_currency: null, printing_label: "Holofoil" });
  const c = compactPriceDetail(fb, { variantName: "Holográfica reversa", languageCode: "ja", now: NOW });
  assert.equal(c.generalCardPrice, true);
  assert.equal(c.finish, null);
  assert.deepEqual(c.freshness, { tone: "unknown", text: "Data não disponível" });
  assert.deepEqual(c.facts.map((f) => f.label), ["Data de referência"]);
  assert.equal(c.notes[0], NM_REFERENCE_NOTE);
  assert.ok(c.notes.some((n) => n.includes("pode não corresponder")));
  assert.ok(c.notes.some((n) => n.includes("mercado internacional")));
});

test("compacto: manual identificado como fonte e no detalhe; sem preço e câmbio ausente viram uma linha", () => {
  const manual = priceOf({ price_origin: "MANUAL", source_currency: "BRL", source_amount: 5 });
  const m = compactPriceDetail(manual, { variantName: "Normal", languageCode: "en", now: NOW });
  assert.equal(m.source, "Curadoria MMKYU");
  assert.ok(m.notes.some((n) => n.includes("manualmente")));
  assert.equal(m.facts.some((f) => f.label === "Valor original" || f.label === "Câmbio"), false);
  const none = compactPriceDetail(null, { variantName: "Normal", languageCode: "en", now: NOW });
  assert.equal(none.amount, null);
  assert.match(none.message ?? "", /Sem preço/);
  assert.equal(none.freshness, null);
  const fx = compactPriceDetail(priceOf({ has_pricing: false, brl_amount: null, fx_status: "FX_RATE_UNAVAILABLE", price_basis: null }), { variantName: "Normal", languageCode: "en", now: NOW });
  assert.equal(fx.amount, null);
  assert.match(fx.message ?? "", /câmbio/);
});

test("D4: inglês não recebe aviso; outros idiomas recebem", () => {
  assert.equal(isInternationalReference("en"), false);
  assert.equal(isInternationalReference("EN"), false);
  assert.equal(isInternationalReference("en-US"), false);
  assert.equal(isInternationalReference("pt-BR"), true);
  assert.equal(isInternationalReference("ja"), true);
  assert.equal(isInternationalReference(null), false);
});

test("C1: cada estado exibível tem forma de ícone e texto próprios (não só cor)", () => {
  const fresh = priceIndicator("FRESH");
  const stale = priceIndicator("STALE");
  const unknown = priceIndicator("DATE_UNKNOWN");
  assert.ok(fresh && stale && unknown);
  assert.deepEqual(new Set([fresh.glyph, stale.glyph, unknown.glyph]).size, 3);
  assert.notEqual(fresh.label, stale.label);
  assert.notEqual(stale.label, unknown.label);
  assert.equal(priceIndicator("UNAVAILABLE"), null);
  assert.equal(priceIndicator("FX_UNAVAILABLE"), null);
});

test("texto acessível acompanha o estado", () => {
  assert.equal(priceAccessibleText(priceOf(), NOW), `referência NM ${formatBrl(1.14)}`);
  assert.match(priceAccessibleText(priceOf({ observed_at: iso(30) }), NOW) ?? "", /desatualizado/);
  assert.match(priceAccessibleText(priceOf({ price_basis: "CARD_FALLBACK", observed_at: null }), NOW) ?? "", /preço geral da carta, sem data confirmada/);
});

// ---- preferência do fichário (D2) ----------------------------------------

test("preferência: ligada por padrão; só desliga com valor explícito", () => {
  assert.equal(BINDER_PRICES_STORAGE_KEY, "mmkyu:binder-prices:v1");
  assert.equal(parseBinderPricesPref(null), true);
  assert.equal(parseBinderPricesPref(""), true);
  assert.equal(parseBinderPricesPref("{oops"), true);
  assert.equal(parseBinderPricesPref(JSON.stringify({ visible: "no" })), true);
  assert.equal(parseBinderPricesPref(serializeBinderPricesPref(false)), false);
  assert.equal(parseBinderPricesPref(serializeBinderPricesPref(true)), true);
});
