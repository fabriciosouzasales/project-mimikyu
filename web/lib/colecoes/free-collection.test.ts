import assert from "node:assert/strict";
import { test } from "node:test";
import {
  FREE_SELECTION_MAX,
  type GroupCopy,
  type PickerGroup,
  type Selection,
  addNextCopy,
  buildCoverPath,
  checkCoverFile,
  isCoverPath,
  plateLogoKey,
  isCoverCode,
  normalizeCoverCode,
  plateCode,
  sanitizeCoverCodeInput,
  copyStatus,
  copyStatusLabel,
  countCopies,
  distinctSetCount,
  freeCollectionHref,
  freeHeroCards,
  freeTotalPages,
  groupKey,
  isFreeCollection,
  normalizeCopyIds,
  parseFreePage,
  reconcileSelection,
  removeLastCopy,
  selectAllFree,
  selectAllFromGroups,
  selectionCount,
  selectionGroupCount,
  selectionIds,
  toggleCopy,
  versionLabel,
  wantsPicker,
} from "./free-collection.ts";

const COLL = "11111111-1111-4111-8111-111111111111";
const OTHER = "22222222-2222-4222-8222-222222222222";
const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;

const group: PickerGroup = {
  cardVariantId: id(900),
  languageCode: "pt-BR",
  languageName: "Português",
  cardName: "Pikachu",
  collectorNumber: "25",
  collectorTotal: 102,
  cardSetCode: "base1",
  cardSetName: "Base Set",
  isDefaultVariant: true,
  variantLabel: null,
  imagePath: "base1/pt-BR/25.webp",
  copies: 3,
};

const copies: GroupCopy[] = [
  { physicalCardId: id(3), copyNumber: 3, addedAt: "", storageName: null, collectionId: null, collectionName: null },
  { physicalCardId: id(1), copyNumber: 1, addedAt: "", storageName: null, collectionId: null, collectionName: null },
  { physicalCardId: id(2), copyNumber: 2, addedAt: "", storageName: "Caixa", collectionId: OTHER, collectionName: "Base" },
  { physicalCardId: id(4), copyNumber: 4, addedAt: "", storageName: null, collectionId: COLL, collectionName: "Favoritas" },
];

test("Coleção livre: NONE e sem Set", () => {
  assert.equal(isFreeCollection({ completionPolicy: "NONE", cardSetCode: null }), true);
  assert.equal(isFreeCollection({ completionPolicy: "STANDARD_SET", cardSetCode: "base1" }), false);
  assert.equal(isFreeCollection({ completionPolicy: "NONE", cardSetCode: "base1" }), false);
  assert.equal(isFreeCollection({ completionPolicy: "REFERENCE_POSITION", cardSetCode: null }), false);
});

test("URL: página e abertura do seletor", () => {
  assert.equal(parseFreePage({}), 1);
  assert.equal(parseFreePage({ pagina: "3" }), 3);
  assert.equal(parseFreePage({ pagina: "-1" }), 1);
  assert.equal(parseFreePage({ pagina: "99999" }), 1);
  assert.equal(wantsPicker({ adicionar: "1" }), true);
  assert.equal(wantsPicker({ adicionar: "sim" }), false);
  assert.equal(freeCollectionHref(COLL), `/colecoes/colecoes/${COLL}`);
  assert.equal(freeCollectionHref(COLL, { page: 2 }), `/colecoes/colecoes/${COLL}?pagina=2`);
  assert.equal(freeCollectionHref(COLL, { openPicker: true }), `/colecoes/colecoes/${COLL}?adicionar=1`);
  assert.equal(freeTotalPages(0), 1);
  assert.equal(freeTotalPages(49), 2);
});

test("hero: mais recentes, uma por carta, só com imagem", () => {
  const items = [
    { cardVariantId: id(1), languageCode: "pt-BR", cardName: "A", cardSetCode: "s1", collectorNumber: "1", collectorTotal: 10, imagePath: "s1/pt-BR/1.webp" },
    { cardVariantId: id(1), languageCode: "en", cardName: "A", cardSetCode: "s1", collectorNumber: "1", collectorTotal: 10, imagePath: "s1/en/1.webp" },
    { cardVariantId: id(2), languageCode: "pt-BR", cardName: "B", cardSetCode: "s2", collectorNumber: "1", collectorTotal: 10, imagePath: null },
    { cardVariantId: id(3), languageCode: "pt-BR", cardName: "C", cardSetCode: "s2", collectorNumber: "2", collectorTotal: 10, imagePath: "s2/pt-BR/2.webp" },
  ];
  const hero = freeHeroCards(items, 5);
  assert.deepEqual(hero.map((card) => card.cardName), ["A", "C"]);
  assert.ok(hero.every((card) => card.isSatisfied));
  assert.equal(freeHeroCards(items, 1).length, 1);
});

test("Sets distintos só com a coleção inteira na página", () => {
  const items = [{ cardSetCode: "s1" }, { cardSetCode: "S1" }, { cardSetCode: "s2" }];
  assert.equal(distinctSetCount(items, 3), 2);
  assert.equal(distinctSetCount(items, 50), null);
  assert.equal(distinctSetCount([], 0), null);
});

test("estado do exemplar e contagem", () => {
  assert.equal(copyStatus({ collectionId: null }, COLL), "free");
  assert.equal(copyStatus({ collectionId: COLL.toUpperCase() }, COLL), "here");
  assert.equal(copyStatus({ collectionId: OTHER }, COLL), "elsewhere");
  assert.deepEqual(countCopies(copies, COLL), { free: 2, here: 1, elsewhere: 1 });
  assert.equal(copyStatusLabel("elsewhere", "Base"), "Em «Base»");
  assert.equal(copyStatusLabel("here", null), "Já está nesta coleção");
  assert.equal(versionLabel(true, "Holo"), "Versão padrão");
  assert.equal(versionLabel(false, " "), "Outra versão");
});

test("adicionar: livre mais antigo, nunca exemplar de outra coleção", () => {
  let selection: Selection = {};
  const first = addNextCopy(selection, group, copies, COLL);
  assert.ok(first.ok);
  selection = first.selection;
  assert.deepEqual(selectionIds(selection), [id(1)]);
  const second = addNextCopy(selection, group, copies, COLL);
  assert.ok(second.ok);
  selection = second.selection;
  assert.deepEqual(selectionIds(selection), [id(1), id(3)]);
  const third = addNextCopy(selection, group, copies, COLL);
  assert.deepEqual(third, { ok: false, reason: "none_free" });
  assert.equal(selectionCount(selection), 2);
  assert.equal(selectionGroupCount(selection), 1);
  selection = removeLastCopy(selection, groupKey(group));
  assert.deepEqual(selectionIds(selection), [id(1)]);
  selection = removeLastCopy(selection, groupKey(group));
  assert.deepEqual(selection, {});
});

test("teto da seleção", () => {
  const full = addNextCopy({}, group, copies, COLL, 0);
  assert.deepEqual(full, { ok: false, reason: "limit" });
  assert.equal(FREE_SELECTION_MAX, 500);
});

test("exemplar específico: só livres, desmarca", () => {
  const blocked = toggleCopy({}, group, copies, id(2), COLL);
  assert.deepEqual(blocked, { ok: false, reason: "not_free" });
  const here = toggleCopy({}, group, copies, id(4), COLL);
  assert.deepEqual(here, { ok: false, reason: "not_free" });
  const on = toggleCopy({}, group, copies, id(3), COLL);
  assert.ok(on.ok);
  assert.deepEqual(selectionIds(on.selection), [id(3)]);
  const off = toggleCopy(on.selection, group, copies, id(3), COLL);
  assert.ok(off.ok);
  assert.deepEqual(off.selection, {});
});

test("todas as disponíveis respeitam o teto", () => {
  const all = selectAllFree({}, group, copies, COLL);
  assert.deepEqual(selectionIds(all.selection), [id(1), id(3)]);
  assert.equal(all.limited, false);
  const capped = selectAllFree({}, group, copies, COLL, 1);
  assert.deepEqual(selectionIds(capped.selection), [id(1)]);
  assert.equal(capped.limited, true);
});

test("reconciliação após mudança no acervo", () => {
  const selection: Selection = { [groupKey(group)]: { group, ids: [id(1), id(3), id(9)] } };
  const now: GroupCopy[] = [
    { ...copies[1]!, collectionId: COLL, collectionName: "Favoritas" },
    { ...copies[0]!, collectionId: OTHER, collectionName: "Base" },
  ];
  const result = reconcileSelection(selection, groupKey(group), now, COLL);
  assert.equal(result.here, 1);
  assert.equal(result.elsewhere, 1);
  assert.equal(result.gone, 1);
  assert.deepEqual(result.selection, {});
});

test("normalização do envio", () => {
  assert.deepEqual(normalizeCopyIds([id(1), id(1).toUpperCase(), id(2)]), [id(1), id(2)]);
  assert.equal(normalizeCopyIds([]), null);
  assert.equal(normalizeCopyIds(["x"]), null);
  assert.equal(normalizeCopyIds("x"), null);
  assert.equal(normalizeCopyIds(Array.from({ length: 501 }, (_, n) => id(n))), null);
});

test("selecionar todas: várias cartas, mantém escolhidas, respeita o teto", () => {
  const other: PickerGroup = { ...group, cardVariantId: id(901), cardName: "Raichu" };
  const otherCopies: GroupCopy[] = [
    { physicalCardId: id(11), copyNumber: 1, addedAt: "", storageName: null, collectionId: null, collectionName: null },
  ];
  const start: Selection = { [groupKey(group)]: { group, ids: [id(3)] } };
  const all = selectAllFromGroups(start, [{ group, copies }, { group: other, copies: otherCopies }], COLL);
  assert.deepEqual(selectionIds(all.selection), [id(3), id(1), id(11)]);
  assert.equal(all.added, 2);
  assert.equal(all.limited, false);
  const capped = selectAllFromGroups({}, [{ group, copies }, { group: other, copies: otherCopies }], COLL, 2);
  assert.equal(selectionCount(capped.selection), 2);
  assert.equal(capped.limited, true);
});

test("capa enviada: caminho, arquivo e chave da placa", () => {
  const path = buildCoverPath(COLL.toUpperCase(), OTHER, "image/webp", id(5));
  assert.equal(path, `${COLL}/${OTHER}/${id(5)}.webp`);
  assert.equal(isCoverPath(path), true);
  assert.equal(buildCoverPath(COLL, OTHER, "image/gif", id(5)), null);
  assert.equal(isCoverPath("../x.png"), false);
  assert.equal(checkCoverFile({ type: "image/png", size: 1000 }), "ok");
  assert.equal(checkCoverFile({ type: "image/gif", size: 1000 }), "type");
  assert.equal(checkCoverFile({ type: "image/png", size: 2 * 1024 * 1024 }), "size");
  assert.equal(checkCoverFile({ type: "image/png", size: 0 }), "empty");
  assert.equal(plateLogoKey({ cardSetLogoPath: "a", coverLogoPath: "b" }), "a");
  assert.equal(plateLogoKey({ cardSetLogoPath: null, coverLogoPath: "b" }), "b");
  assert.equal(plateLogoKey({ cardSetLogoPath: null }), null);
});

test("código opcional: normaliza, vazio = sem código, formato 2–6", () => {
  assert.equal(normalizeCoverCode(undefined), null);
  assert.equal(normalizeCoverCode("   "), null);
  assert.equal(normalizeCoverCode(" mmk1 "), "MMK1");
  assert.equal(normalizeCoverCode("A1B2C3"), "A1B2C3");
  assert.equal(normalizeCoverCode("A"), "invalid");
  assert.equal(normalizeCoverCode("ABCDEFG"), "invalid");
  assert.equal(normalizeCoverCode("AB-1"), "invalid");
  assert.equal(normalizeCoverCode("ÁB"), "invalid");
  assert.equal(sanitizeCoverCodeInput("ab-1 çx99"), "AB1X99");
  assert.equal(isCoverCode("MMK"), true);
  assert.equal(isCoverCode("mmk"), false);
  assert.equal(plateCode({ cardSetCode: "sv1", coverCode: "MMK" }), "sv1");
  assert.equal(plateCode({ cardSetCode: null, coverCode: "MMK" }), "MMK");
  assert.equal(plateCode({ cardSetCode: null }), null);
});
