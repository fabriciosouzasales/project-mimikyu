import { test } from "node:test";
import assert from "node:assert/strict";
import {
  librarySummary,
  availableCreationKinds,
  creationSteps,
  FREE_COLLECTION_ENABLED,
  initialCreationKind,
  suggestFreeCollectionName,
  canSubmitCreate,
  changedChoices,
  chunk,
  classifyCollectionFailure,
  collectionHref,
  collectionKindLabel,
  collectionProgressView,
  collectionSubtitle,
  findAlternatives,
  librarySearchWithMode,
  pickHeroCards,
  resolveLibraryMode,
  libraryHref,
  missingCount,
  normalizeCollectionName,
  optionKey,
  parseLibraryPage,
  parsePositionFilter,
  progressLabel,
  progressPercent,
  progressPercentText,
  progressBarPercent,
  storageStep,
  suggestCollectionName,
  toPositionsRpcFilter,
} from "./colecoes.ts";

const ID = "3aa3fcf6-5826-4a13-b6a2-8f652a2b485a";

test("URL da coleção e filtro Tenho/Faltam", () => {
  assert.equal(collectionHref(ID), `/colecoes/colecoes/${ID}`);
  assert.equal(collectionHref(ID, "tenho"), `/colecoes/colecoes/${ID}?ver=tenho`);
  assert.equal(parsePositionFilter({ ver: "faltam" }), "faltam");
  assert.equal(parsePositionFilter({ ver: "MISSING" }), "todas");
  assert.equal(parsePositionFilter({}), "todas");
  assert.equal(toPositionsRpcFilter("tenho"), "OWNED");
  assert.equal(toPositionsRpcFilter("faltam"), "MISSING");
  assert.equal(toPositionsRpcFilter("todas"), "ALL");
});

test("página da Biblioteca: valor inválido cai no padrão", () => {
  assert.equal(parseLibraryPage({ pagina: "3" }), 3);
  assert.equal(parseLibraryPage({ pagina: "-1" }), 1);
  assert.equal(parseLibraryPage({ pagina: "abc" }), 1);
  assert.equal(parseLibraryPage({ pagina: "99999" }), 1);
  assert.equal(libraryHref(1), "/colecoes/colecoes");
  assert.equal(libraryHref(2), "/colecoes/colecoes?pagina=2");
});

test("progresso: X de Y, percentual nunca chega a 100 antes de completar", () => {
  assert.equal(progressLabel(146, 158), "146 de 158");
  assert.equal(progressLabel(1248, 2000), "1.248 de 2.000");
  assert.equal(progressPercent(146, 158), 92);
  assert.equal(progressPercent(157, 158), 99);
  assert.equal(progressPercent(299, 300), 99);
  assert.equal(progressPercent(158, 158), 100);
  assert.equal(progressPercent(0, 0), 0);
  // UX-02: uma conquista nunca aparece como "0%".
  assert.equal(progressPercentText(1, 1025), "<1%");
  assert.equal(progressBarPercent(1, 1025), 1);
  assert.equal(progressPercentText(0, 1025), "0%");
  assert.equal(progressBarPercent(0, 1025), 0);
  assert.equal(progressPercentText(0, 0), "0%");
  assert.equal(progressPercentText(157, 158), "99%");
  assert.equal(progressPercentText(158, 158), "100%");
  assert.equal(missingCount(7, 30), 23);
  assert.equal(missingCount(31, 30), 0);
});

test("tipo de coleção na linguagem do colecionador (NS-14)", () => {
  assert.equal(collectionKindLabel("STANDARD_SET"), "Set padrão — uma de cada carta");
  assert.equal(collectionKindLabel("WHATEVER"), "Coleção");
  assert.equal(collectionKindLabel("REFERENCE_POSITION"), "Completar a Pokédex");
});

test("nome: sugestão pelo Set, normalização e vazio", () => {
  assert.equal(suggestCollectionName("Megaevolução — Fogo Fantasmagórico"), "Megaevolução — Fogo Fantasmagórico");
  assert.equal(suggestCollectionName(null), "");
  assert.equal(normalizeCollectionName("   "), null);
  assert.equal(normalizeCollectionName("  Meu   Set  "), "Meu Set");
  assert.equal(normalizeCollectionName("x".repeat(200))?.length, 80);
});

test("D-A: sem locais não pergunta; com locais exige escolha explícita, mesmo com um só", () => {
  assert.equal(storageStep([]), "auto");
  assert.equal(storageStep([{ id: "a", name: "Local padrão" }]), "choose");

  const base = { setCode: "me5.5", name: "Meu Set" };
  assert.equal(canSubmitCreate({ ...base, locations: [], storageId: null }), true);
  const one = [{ id: "a", name: "Local padrão" }];
  assert.equal(canSubmitCreate({ ...base, locations: one, storageId: null }), false, "um local, sem escolha → bloqueado");
  assert.equal(canSubmitCreate({ ...base, locations: one, storageId: "a" }), true);
  assert.equal(canSubmitCreate({ ...base, locations: one, storageId: "outro" }), false, "id que não é do usuário");
  assert.equal(canSubmitCreate({ ...base, name: "  ", locations: [], storageId: null }), false);
  assert.equal(canSubmitCreate({ ...base, setCode: null, locations: [], storageId: null }), false);
});

test("alternativas: só cartas com mais de um grupo pedem escolha; sugestão = padrão no idioma de R3", () => {
  const candidates = [
    { physicalCardId: "p1", cardId: "c1", collectorNumber: "1", cardName: "Bulbasaur", languageCode: "pt-BR" },
    { physicalCardId: "p2", cardId: "c2", collectorNumber: "2", cardName: "Ivysaur", languageCode: "pt-BR" },
  ];
  const group = (number: string, variant: string, lang: string, isDefault: boolean) => ({
    collectorNumber: number,
    cardVariantId: variant,
    languageCode: lang,
    languageName: lang,
    variantLabel: isDefault ? null : "Reverse Holo",
    isDefaultVariant: isDefault,
    copies: 1,
    imagePath: null,
  });
  const groups = [
    group("1", "v1", "pt-BR", true),
    group("2", "v2r", "pt-BR", false),
    group("2", "v2", "pt-BR", true),
    group("2", "v2", "en", true),
  ];
  const choices = findAlternatives(candidates, groups);
  assert.equal(choices.length, 1);
  const [first] = choices;
  assert.ok(first);
  assert.equal(first.cardId, "c2");
  assert.equal(first.suggestedKey, "v2.pt-BR");
  assert.equal(first.options.length, 3);
  assert.equal(first.options[0]?.isDefaultVariant, true);

  assert.deepEqual(changedChoices(choices, { c2: "v2.pt-BR" }), [], "manter a sugestão não envia nada");
  assert.deepEqual(changedChoices(choices, { c2: optionKey({ cardVariantId: "v2r", languageCode: "pt-BR" }) }), [
    { cardId: "c2", collectorNumber: "2", cardVariantId: "v2r", languageCode: "pt-BR" },
  ]);
  assert.deepEqual(changedChoices(choices, { c2: "inexistente.xx" }), []);
});

test("acervo de um grupo por carta (caso ME5.5 real): nenhuma pergunta", () => {
  const candidates = [{ physicalCardId: "p1", cardId: "c1", collectorNumber: "1", cardName: "A", languageCode: "pt-BR" }];
  const groups = [
    {
      collectorNumber: "1",
      cardVariantId: "v1",
      languageCode: "pt-BR",
      languageName: "Português",
      variantLabel: null,
      isDefaultVariant: true,
      copies: 3,
      imagePath: null,
    },
  ];
  assert.deepEqual(findAlternatives(candidates, groups), []);
});

test("lotes de no máximo 500 (teto de 5046)", () => {
  const ids = Array.from({ length: 1201 }, (_, index) => index);
  const batches = chunk(ids, 500);
  assert.deepEqual(
    batches.map((batch) => batch.length),
    [500, 500, 201],
  );
  assert.deepEqual(chunk([], 500), []);
  assert.throws(() => chunk([1], 0));
});

test("tradução de erros dos contratos", () => {
  assert.equal(classifyCollectionFailure("28000", "not_authenticated"), "not_authenticated");
  assert.equal(classifyCollectionFailure("55000", "STORAGE_CONTAINER_REQUIRED"), "storage_required");
  assert.equal(classifyCollectionFailure("22023", "STORAGE_CONTAINER_INVALID"), "storage_invalid");
  assert.equal(classifyCollectionFailure("22023", "CARD_SET_NOT_FOUND"), "set_not_found");
  assert.equal(classifyCollectionFailure("22023", "IDEMPOTENCY_KEY_REUSED"), "conflict");
  assert.equal(classifyCollectionFailure("22023", "INVALID_REQUEST"), "invalid");
  assert.equal(classifyCollectionFailure("23505", "duplicate key value"), "already_linked");
  assert.equal(
    classifyCollectionFailure("P0001", "uma ou mais physical_card_ids já estão alocadas a uma Collection"),
    "already_linked",
  );
  assert.equal(classifyCollectionFailure("P0001", "collection is archived — reactivate before allocating"), "not_found");
  assert.equal(classifyCollectionFailure("P0001", "authentication required"), "not_authenticated");
  assert.equal(classifyCollectionFailure(undefined, undefined), "unavailable");
  assert.equal(classifyCollectionFailure("55000", "NOT_FREE_COLLECTION"), "not_found");
  assert.equal(classifyCollectionFailure("P0002", "COLLECTION_NOT_FOUND"), "not_found");
  assert.equal(classifyCollectionFailure("22023", "INVALID_COVER_CODE"), "invalid");
});

test("subtítulo: Set com código; livre com código opcional", () => {
  assert.equal(collectionSubtitle({ cardSetName: "Base Set", cardSetCode: "bs", completionPolicy: "STANDARD_SET" }), "Base Set · BS");
  const free = collectionSubtitle({ cardSetName: null, cardSetCode: null, completionPolicy: "NONE" });
  assert.equal(collectionSubtitle({ cardSetName: null, cardSetCode: null, completionPolicy: "NONE", coverCode: "MMK" }), `${free} · MMK`);
  assert.equal(collectionSubtitle({ cardSetName: null, cardSetCode: null, completionPolicy: "NONE", coverCode: null }), free);
});

test("resumo da Biblioteca: só com todas as coleções na página; livre fora do progresso", () => {
  const items = [
    { satisfiedPositions: 147, totalPositions: 158, isComplete: false },
    { satisfiedPositions: 30, totalPositions: 30, isComplete: true },
    { satisfiedPositions: 0, totalPositions: 0, isComplete: false },
  ];
  assert.deepEqual(librarySummary(items, 3), {
    collections: 3,
    ownedCards: 177,
    targetCards: 188,
    overallPercent: 94,
    complete: 1,
  });
  assert.equal(librarySummary(items, 60), null);
  // Pokédex: posições são Pokémon, não cartas — fica fora de "cartas reunidas" e do progresso geral.
  const withDex = [...items, { satisfiedPositions: 151, totalPositions: 1025, isComplete: false, completionPolicy: "REFERENCE_POSITION" }];
  assert.deepEqual(librarySummary(withDex, 4), {
    collections: 4,
    ownedCards: 177,
    targetCards: 188,
    overallPercent: 94,
    complete: 1,
  });
  assert.equal(librarySummary([], 0), null);
});

test("modo da Biblioteca: URL vence cookie; valor estranho cai em Cards", () => {
  assert.equal(resolveLibraryMode({}, undefined), "cards");
  assert.equal(resolveLibraryMode({ modo: "lista" }, undefined), "lista");
  assert.equal(resolveLibraryMode({ modo: "carrossel" }, "lista"), "carrossel");
  assert.equal(resolveLibraryMode({}, "carrossel"), "carrossel");
  assert.equal(resolveLibraryMode({ modo: "tabela" }, "lista"), "lista");
  assert.equal(resolveLibraryMode({ modo: ["lista", "cards"] }, undefined), "lista");
  assert.equal(resolveLibraryMode({}, "admin"), "cards");
  assert.equal(librarySearchWithMode("", "lista"), "?modo=lista");
  assert.equal(librarySearchWithMode("?pagina=2", "carrossel"), "?pagina=2&modo=carrossel");
  assert.equal(librarySearchWithMode("?pagina=2&modo=lista", "cards"), "?pagina=2");
  assert.equal(librarySearchWithMode("?modo=lista", "cards"), "");
});

test("progresso em Lista/Carrossel: coleção livre não vira 0 de 0", () => {
  assert.deepEqual(collectionProgressView({ totalPositions: 158, satisfiedPositions: 146, isComplete: false, copiesCount: 150 }), {
    kind: "goal",
    percent: 92,
    percentText: "92%",
    barPercent: 92,
    label: "146 de 158",
    complete: false,
  });
  assert.deepEqual(collectionProgressView({ totalPositions: 0, satisfiedPositions: 0, isComplete: false, copiesCount: 12 }), {
    kind: "free",
    copies: 12,
  });
  assert.equal(collectionSubtitle({ cardSetName: "Base Set", cardSetCode: "base1", completionPolicy: "STANDARD_SET" }), "Base Set · BASE1");
  assert.equal(collectionSubtitle({ cardSetName: null, cardSetCode: null, completionPolicy: "NONE" }), "Coleção livre");
});

test("hero da coleção: secretas primeiro (número acima do total), sem imagem fica de fora", () => {
  const card = (n: string, total: number | null, image = true, owned = false) => ({
    cardId: `c${n}`,
    cardName: `Carta ${n}`,
    collectorNumber: n,
    collectorTotal: total,
    imagePath: image ? `x/${n}.webp` : null,
    isSatisfied: owned,
  });
  const set = [card("1", 128), card("64", 128), card("128", 128), card("129", 128, true, true), card("140", 128), card("158", 128, false), card("150", 128), card("TG01", 128)];
  const picked = pickHeroCards(set, 5);
  assert.deepEqual(picked.cards.map((c) => c.collectorNumber), ["150", "140", "129", "128", "64"]);
  assert.equal(picked.secret, 3);
  assert.equal(picked.cards[2]?.isSatisfied, true);
  assert.equal(new Set(picked.cards.map((c) => c.cardId)).size, 5);
  assert.deepEqual(pickHeroCards([...set].reverse(), 5).cards.map((c) => c.cardId), picked.cards.map((c) => c.cardId));

  const noSecrets = pickHeroCards([card("1", 102), card("5", 102), card("102", 102), card("50", 102)], 5);
  assert.deepEqual(noSecrets.cards.map((c) => c.collectorNumber), ["102", "50", "5", "1"]);
  assert.equal(noSecrets.secret, 0);

  const oneSecret = pickHeroCards([card("1", 10), card("9", 10), card("11", 10), card("10", 10)], 5);
  assert.deepEqual(oneSecret.cards.map((c) => c.collectorNumber), ["11", "10", "9", "1"]);
  assert.equal(pickHeroCards([], 5).cards.length, 0);
  assert.equal(pickHeroCards([card("1", null)], 5).cards.length, 1);
  const short = pickHeroCards([card("3", 10), card("TG02", 10), card("TG01", 10), card("4", 10, false)], 5);
  assert.deepEqual(short.cards.map((c) => c.collectorNumber), ["3", "TG01", "TG02"]);

  // Curadoria do Set (Celebração de 30 Anos): ordem por slot, completa com a regra automática.
  const me55 = Array.from({ length: 158 }, (_, i) => card(String(i + 1), 128));
  const curated = pickHeroCards(me55, 5, "ME5.5");
  assert.deepEqual(curated.cards.map((c) => c.collectorNumber), ["149", "157", "158", "155", "154"]);
  assert.equal(curated.secret, 5);
  assert.deepEqual(pickHeroCards(me55, 5, "outro").cards.map((c) => c.collectorNumber), ["158", "157", "156", "155", "154"]);
  const me55NoArt = me55.map((c) => (c.collectorNumber === "149" ? { ...c, imagePath: null } : c));
  assert.deepEqual(pickHeroCards(me55NoArt, 5, "me5.5").cards.map((c) => c.collectorNumber), ["157", "158", "155", "154", "156"]);

  // Coleção Clássica 30 Anos (sem secretas, números com zeros à esquerda).
  const cc = Array.from({ length: 30 }, (_, i) => card(String(i + 1).padStart(3, "0"), 30));
  assert.deepEqual(pickHeroCards(cc, 5, "ME5.5CC").cards.map((c) => c.collectorNumber), ["001", "029", "030", "027", "026"]);
  assert.deepEqual(pickHeroCards(cc, 5, null).cards.map((c) => c.collectorNumber), ["030", "029", "028", "027", "026"]);
});

test("criação: tipos disponíveis, passos por tipo e envio da Coleção livre", () => {
  // Enquanto 5175 não está no LIVE, só "Completar um Set" é oferecido (nunca fluxo sem conclusão).
  assert.equal(FREE_COLLECTION_ENABLED, true);
  // Pokédex publicada (2026-10-19): o padrão já oferece os três tipos.
  assert.deepEqual(availableCreationKinds(), ["card_set", "free", "pokedex"]);
  assert.deepEqual(availableCreationKinds(false, false), ["card_set"]);
  assert.deepEqual(availableCreationKinds(true, false), ["card_set", "free"]);
  // Pokédex só com a flag; Master Set nunca é tipo de criação.
  assert.ok(!availableCreationKinds(true, false).some((kind) => (kind as string) === "pokedex" || (kind as string) === "master_set"));
  assert.deepEqual(availableCreationKinds(true, true), ["card_set", "free", "pokedex"]);
  assert.deepEqual(availableCreationKinds(false, true), ["card_set", "pokedex"]);
  assert.deepEqual(creationSteps("pokedex", 3), ["type", "generations", "details"]);
  assert.deepEqual(creationSteps("pokedex", 3, true), ["type", "generations", "details"], "Pokédex não tem objetivo de Set");
  assert.equal(canSubmitCreate({ kind: "pokedex", setCode: null, name: "Minha Pokédex", locations: [], storageId: null, generationCount: 9 }), true);
  assert.equal(canSubmitCreate({ kind: "pokedex", setCode: null, name: "Minha Pokédex", locations: [], storageId: null, generationCount: 0 }), false);
  assert.equal(canSubmitCreate({ kind: "pokedex", setCode: null, name: "Minha Pokédex", locations: [], storageId: null }), false);

  // Com dois tipos, o passo de escolha aparece; com um só, a criação abre direto nele.
  assert.deepEqual(creationSteps("card_set", 2), ["type", "set", "details"]);
  assert.deepEqual(creationSteps("free", 2), ["type", "details"]);
  assert.deepEqual(creationSteps(null, 2), ["type", "set", "details"]);
  assert.deepEqual(creationSteps("card_set", 1), ["set", "details"]);
  assert.deepEqual(creationSteps("card_set"), ["type", "set", "details"], "dois tipos → escolha de tipo primeiro");
  assert.deepEqual(creationSteps("free"), ["type", "details"]);
  assert.deepEqual(creationSteps("card_set", 2, true), ["type", "set", "objective", "details"], "Master Set ligado → passo Objetivo");
  assert.deepEqual(creationSteps("card_set", 1, true), ["set", "objective", "details"]);
  assert.deepEqual(creationSteps("free", 2, true), ["type", "details"], "Coleção livre não tem objetivo");
  assert.equal(initialCreationKind(), null);
  assert.equal(initialCreationKind(["card_set"]), "card_set");
  assert.equal(initialCreationKind(["card_set", "free"]), null);

  const one = [{ id: "a", name: "Local padrão" }];
  assert.equal(canSubmitCreate({ kind: "free", setCode: null, name: "Favoritas", locations: [], storageId: null }), true, "livre não exige Set");
  assert.equal(canSubmitCreate({ kind: "free", setCode: null, name: " ", locations: [], storageId: null }), false);
  assert.equal(canSubmitCreate({ kind: "free", setCode: null, name: "Favoritas", locations: one, storageId: null }), false, "D-A vale também na livre");
  assert.equal(canSubmitCreate({ kind: "free", setCode: null, name: "Favoritas", locations: one, storageId: "a" }), true);
  assert.equal(canSubmitCreate({ kind: "card_set", setCode: null, name: "x", locations: [], storageId: null }), false);
  assert.equal(suggestFreeCollectionName().length > 0, true);
});

// UX-08 — selo de tipo na Biblioteca
import { collectionKindBadge, collectionKindDetail } from "./colecoes.ts";

test("collectionKindBadge: um selo curto por política; desconhecida sem selo", () => {
  assert.deepEqual(collectionKindBadge("STANDARD_SET"), { kind: "set", label: "Set" });
  assert.deepEqual(collectionKindBadge("MASTER_SET"), { kind: "master", label: "Master Set" });
  assert.deepEqual(collectionKindBadge("REFERENCE_POSITION"), { kind: "pokedex", label: "Pokédex" });
  assert.deepEqual(collectionKindBadge("NONE"), { kind: "free", label: "Livre" });
  assert.equal(collectionKindBadge(null), null);
});

test("collectionKindDetail: código antes do nome do Set; código próprio; descrição curta sem código", () => {
  assert.equal(collectionKindDetail({ cardSetName: "Escuridão Absoluta", cardSetCode: "me5", completionPolicy: "MASTER_SET" }), "ME5 – Escuridão Absoluta");
  assert.equal(collectionKindDetail({ cardSetName: "Escuridão Absoluta", cardSetCode: null, completionPolicy: "STANDARD_SET" }), "Escuridão Absoluta");
  assert.equal(collectionKindDetail({ cardSetName: null, cardSetCode: null, completionPolicy: "REFERENCE_POSITION", coverCode: "PKX" }), "PKX");
  assert.equal(collectionKindDetail({ cardSetName: null, cardSetCode: null, completionPolicy: "REFERENCE_POSITION" }), "Pokédex Nacional");
  assert.equal(collectionKindDetail({ cardSetName: null, cardSetCode: null, completionPolicy: "NONE", coverCode: null }), "Organizada do seu jeito");
});
