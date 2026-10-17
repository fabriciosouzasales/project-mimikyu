// Meu acervo — regras puras de URL e apresentação (MY-INVENTORY-IMPLEMENTATION-01).
// Executar: node --experimental-strip-types --test lib/colecoes/acervo.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { test } from "node:test";
import {
  ACERVO_PAGE_SIZE,
  ACERVO_PATH,
  acervoHref,
  cardFrontUrl,
  formatCollectorNumber,
  formatItemKey,
  hasActiveFilters,
  parseAcervoState,
  parseItemKey,
  pluralize,
  resultSummary,
  toItemsRpcParams,
  totalPages,
  variantTag,
  withoutDetail,
} from "./acervo.ts";

const UUID = "3f2a1b4c-5d6e-4f70-8a9b-0c1d2e3f4a5b";

test("estado padrão: sem parâmetros", () => {
  const s = parseAcervoState({});
  assert.deepEqual(s, {
    query: null,
    setCode: null,
    languageCode: null,
    collection: { kind: "all" },
    sort: "recentes",
    page: 1,
    detail: null,
  });
  assert.equal(hasActiveFilters(s), false);
  assert.equal(acervoHref(s), ACERVO_PATH);
});

test("parâmetros válidos são lidos e voltam canônicos na URL", () => {
  const s = parseAcervoState({
    q: "  Pikachu ",
    set: "me2",
    idioma: "pt-BR",
    colecao: UUID.toUpperCase(),
    ordem: "set",
    pagina: "3",
    carta: `${UUID}.en`,
  });
  assert.equal(s.query, "Pikachu");
  assert.equal(s.setCode, "me2");
  assert.equal(s.languageCode, "pt-BR");
  assert.deepEqual(s.collection, { kind: "collection", id: UUID });
  assert.equal(s.sort, "set");
  assert.equal(s.page, 3);
  assert.deepEqual(s.detail, { cardVariantId: UUID, languageCode: "en" });
  assert.equal(hasActiveFilters(s), true);
  assert.equal(
    acervoHref(s),
    `${ACERVO_PATH}?q=Pikachu&set=me2&idioma=pt-BR&colecao=${UUID}&ordem=set&pagina=3&carta=${UUID}.en`,
  );
});

test("valores inválidos caem no padrão, nunca em erro", () => {
  const s = parseAcervoState({
    set: "me2'; drop",
    idioma: "português",
    colecao: "123",
    ordem: "preco",
    pagina: "-4",
    carta: "abc.pt-BR",
  });
  assert.equal(s.setCode, null);
  assert.equal(s.languageCode, null);
  assert.deepEqual(s.collection, { kind: "all" });
  assert.equal(s.sort, "recentes");
  assert.equal(s.page, 1);
  assert.equal(s.detail, null);
});

test("página: limites e array de parâmetros", () => {
  assert.equal(parseAcervoState({ pagina: "99999" }).page, 1); // 5 dígitos: inválido
  assert.equal(parseAcervoState({ pagina: "9999" }).page, 2000); // teto
  assert.equal(parseAcervoState({ pagina: "0" }).page, 1);
  assert.equal(parseAcervoState({ pagina: ["2", "5"] }).page, 2);
});

test("busca é truncada no limite da função SQL", () => {
  const long = "x".repeat(250);
  assert.equal(parseAcervoState({ q: long }).query?.length, 100);
  assert.equal(parseAcervoState({ q: "   " }).query, null);
});

test("coleção: 'sem' e id", () => {
  const sem = parseAcervoState({ colecao: "sem" });
  assert.deepEqual(sem.collection, { kind: "none" });
  assert.equal(acervoHref(sem), `${ACERVO_PATH}?colecao=sem`);
});

test("chave do grupo: ida e volta", () => {
  const key = { cardVariantId: UUID, languageCode: "pt-BR" };
  assert.deepEqual(parseItemKey(formatItemKey(key)), key);
  assert.equal(parseItemKey(undefined), null);
  assert.equal(parseItemKey(`${UUID}`), null);
  assert.equal(parseItemKey(`${UUID}.`), null);
  assert.equal(parseItemKey(`.pt-BR`), null);
});

test("fechar o detalhe preserva a lista", () => {
  const s = parseAcervoState({ q: "Mew", pagina: "2", carta: `${UUID}.en` });
  assert.equal(acervoHref(withoutDetail(s)), `${ACERVO_PATH}?q=Mew&pagina=2`);
});

test("parâmetros da 5159", () => {
  const s = parseAcervoState({ colecao: "sem", ordem: "set", pagina: "2", idioma: "en" });
  assert.deepEqual(toItemsRpcParams(s), {
    p_search: null,
    p_card_set_code: null,
    p_language_code: "en",
    p_collection_id: null,
    p_without_collection: true,
    p_sort: "SET_NUMBER",
    p_limit: ACERVO_PAGE_SIZE,
    p_offset: ACERVO_PAGE_SIZE,
  });
  const c = parseAcervoState({ colecao: UUID });
  assert.equal(toItemsRpcParams(c).p_collection_id, UUID);
  assert.equal(toItemsRpcParams(c).p_without_collection, false);
  assert.equal(toItemsRpcParams(c).p_sort, "RECENT");
  assert.ok(ACERVO_PAGE_SIZE <= 96, "dentro do teto da 5159");
});

test("total de páginas", () => {
  assert.equal(totalPages(0), 1);
  assert.equal(totalPages(48), 1);
  assert.equal(totalPages(49), 2);
});

test("textos do colecionador", () => {
  assert.equal(pluralize(1, "carta", "cartas"), "1 carta");
  assert.equal(pluralize(1248, "carta", "cartas"), "1.248 cartas");
  assert.equal(resultSummary(1), "1 carta diferente");
  assert.equal(resultSummary(914), "914 cartas diferentes");
  assert.equal(formatCollectorNumber("25", 94), "25/94");
  assert.equal(formatCollectorNumber("7", 165), "007/165");
  assert.equal(formatCollectorNumber("SWSH031", null), "SWSH031");
  assert.equal(formatCollectorNumber("TG05", 30), "TG05/30");
});

test("etiqueta de variante só quando não é a padrão", () => {
  assert.equal(variantTag(true, "Holográfica"), null);
  assert.equal(variantTag(false, "Reverse Holo · 1ª Edição"), "Reverse Holo · 1ª Edição");
  assert.equal(variantTag(false, "  "), null);
  assert.equal(variantTag(false, null), null);
});

test("URL da imagem: só caminhos do pipeline", () => {
  const base = "https://x.supabase.co/";
  assert.equal(
    cardFrontUrl(base, "me2/pt-BR/001.webp"),
    "https://x.supabase.co/storage/v1/object/public/card-front/me2/pt-BR/001.webp",
  );
  assert.equal(cardFrontUrl(base, "xyp/en/XY99.webp")?.endsWith("/card-front/xyp/en/XY99.webp"), true);
  assert.equal(cardFrontUrl(base, "../secret/a.webp"), null);
  assert.equal(cardFrontUrl(base, "me2/pt-BR/001.svg"), null);
  assert.equal(cardFrontUrl(base, "https://evil.example/a.webp"), null);
  assert.equal(cardFrontUrl(undefined, "me2/pt-BR/001.webp"), null);
  assert.equal(cardFrontUrl(base, null), null);
});
