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
  hasStorageFilter,
  parseAcervoState,
  parseItemKey,
  pluralize,
  resultSummary,
  storageMatchAccessible,
  storageMatchLabel,
  storageScopeSummary,
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
    storage: { kind: "all" },
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
    p_storage_container_id: null,
    p_without_storage: false,
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

// ---------------------------------------------------------------------------
// WHERE-04 — filtro por localização física (5220)
// ---------------------------------------------------------------------------

test("WHERE-04: ?local= — id, sem e inválido", () => {
  const loc = parseAcervoState({ local: UUID.toUpperCase() });
  assert.deepEqual(loc.storage, { kind: "location", id: UUID });
  assert.equal(hasActiveFilters(loc), true);
  assert.equal(hasStorageFilter(loc), true);
  assert.equal(acervoHref(loc), `${ACERVO_PATH}?local=${UUID}`);

  const sem = parseAcervoState({ local: "sem" });
  assert.deepEqual(sem.storage, { kind: "none" });
  assert.equal(acervoHref(sem), `${ACERVO_PATH}?local=sem`);

  for (const raw of ["", "qualquer", "123", `${UUID}x`, "SEM"]) {
    const s = parseAcervoState({ local: raw });
    assert.deepEqual(s.storage, { kind: "all" }, raw);
    assert.equal(hasStorageFilter(s), false);
  }
  assert.deepEqual(parseAcervoState({}).storage, { kind: "all" });
});

test("WHERE-04: parâmetros da 5220 — nunca os dois filtros de local juntos", () => {
  const all = toItemsRpcParams(parseAcervoState({}));
  assert.equal(all.p_storage_container_id, null);
  assert.equal(all.p_without_storage, false);

  const loc = toItemsRpcParams(parseAcervoState({ local: UUID }));
  assert.equal(loc.p_storage_container_id, UUID);
  assert.equal(loc.p_without_storage, false);

  const sem = toItemsRpcParams(parseAcervoState({ local: "sem" }));
  assert.equal(sem.p_storage_container_id, null);
  assert.equal(sem.p_without_storage, true);

  // Qualquer combinação de entrada: no máximo um dos dois ativo.
  for (const local of [UUID, "sem", "", "x", [UUID, "sem"], ["sem", UUID]]) {
    const p = toItemsRpcParams(parseAcervoState({ local }));
    assert.ok(!(p.p_storage_container_id !== null && p.p_without_storage), String(local));
  }
});

test("WHERE-04: local combina com os demais filtros, ordenação e página", () => {
  const s = parseAcervoState({ q: "Mew", set: "me2", idioma: "en", colecao: "sem", local: UUID, ordem: "set", pagina: "3" });
  const p = toItemsRpcParams(s);
  assert.equal(p.p_search, "Mew");
  assert.equal(p.p_card_set_code, "me2");
  assert.equal(p.p_language_code, "en");
  assert.equal(p.p_without_collection, true);
  assert.equal(p.p_storage_container_id, UUID);
  assert.equal(p.p_sort, "SET_NUMBER");
  assert.equal(p.p_offset, 2 * ACERVO_PAGE_SIZE);
  // Paginar preserva o local; remover o local preserva o resto e volta à página 1.
  assert.ok(acervoHref({ ...s, page: 4 }).includes(`local=${UUID}`));
  const removed = acervoHref({ ...s, storage: { kind: "all" }, page: 1, detail: null });
  assert.equal(removed, `${ACERVO_PATH}?q=Mew&set=me2&idioma=en&colecao=sem&ordem=set`);
  // Fechar o detalhe mantém o filtro de local.
  const withDetail = parseAcervoState({ local: "sem", carta: `${UUID}.en` });
  assert.equal(acervoHref(withoutDetail(withDetail)), `${ACERVO_PATH}?local=sem`);
});

test("WHERE-04: indicadores — filtrado nunca substitui o total possuído", () => {
  assert.equal(storageMatchLabel("location", 2, 5), "2 aqui · 5 no total");
  assert.equal(storageMatchLabel("none", 1, 1), "1 sem local · 1 no total");
  assert.equal(storageMatchLabel("location", 1200, 1500), "1.200 aqui · 1.500 no total");
  assert.equal(storageMatchAccessible("location", 2, 5), "2 de 5 exemplares neste local");
  assert.equal(storageMatchAccessible("none", 1, 1), "1 de 1 exemplar sem localização definida");
  assert.equal(storageScopeSummary("location", "Fichário A", 30, 12), "30 exemplares em Fichário A, em 12 cartas diferentes.");
  assert.equal(storageScopeSummary("none", null, 1, 1), "1 exemplar sem localização definida, em 1 carta diferente.");
  assert.equal(storageScopeSummary("location", null, 2, 2), "2 exemplares neste local, em 2 cartas diferentes.");
});
