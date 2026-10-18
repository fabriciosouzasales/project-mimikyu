import assert from "node:assert/strict";
import { test } from "node:test";
import {
  type CopyGroup,
  addedLabel,
  copiesInCollection,
  copyTitle,
  groupLabel,
  removalAffectsProgress,
  sameCollectorNumber,
  storageLabel,
  totalCopies,
  withoutCopy,
} from "./collection-manage.ts";
import { classifyCollectionFailure } from "./colecoes.ts";

const HERE = "11111111-1111-4111-8111-111111111111";
const OTHER = "22222222-2222-4222-8222-222222222222";

const rows = [
  { physicalCardId: "p3", copyNumber: 3, addedAt: "2026-10-03T00:00:00Z", storageName: "Caixa A", collectionId: HERE },
  { physicalCardId: "p1", copyNumber: 1, addedAt: "2026-10-01T00:00:00Z", storageName: null, collectionId: HERE.toUpperCase() },
  { physicalCardId: "p2", copyNumber: 2, addedAt: "2026-10-02T00:00:00Z", storageName: "Caixa A", collectionId: OTHER },
  { physicalCardId: "p4", copyNumber: 4, addedAt: "2026-10-04T00:00:00Z", storageName: null, collectionId: null },
];

test("só exemplares desta coleção, em ordem de número (livre e de outra coleção ficam de fora)", () => {
  const copies = copiesInCollection(rows, HERE);
  assert.deepEqual(
    copies.map((copy) => copy.physicalCardId),
    ["p1", "p3"],
  );
  assert.equal(copies.some((copy) => copy.physicalCardId === "p2"), false);
  assert.equal(copies.some((copy) => copy.physicalCardId === "p4"), false);
  assert.deepEqual(copiesInCollection(rows, OTHER).map((copy) => copy.physicalCardId), ["p2"]);
  assert.deepEqual(copiesInCollection([], HERE), []);
});

test("número de colecionador: zeros à esquerda e caixa não importam", () => {
  assert.equal(sameCollectorNumber("025", "25"), true);
  assert.equal(sameCollectorNumber(" 25 ", "025"), true);
  assert.equal(sameCollectorNumber("TG05", "tg05"), true);
  assert.equal(sameCollectorNumber("25", "250"), false);
  assert.equal(sameCollectorNumber("25a", "25"), false);
});

const groups: CopyGroup[] = [
  {
    cardVariantId: "v1",
    languageCode: "pt-BR",
    languageName: "Português",
    variantLabel: null,
    isDefaultVariant: true,
    copies: [
      { physicalCardId: "p1", copyNumber: 1, addedAt: "2026-10-01T00:00:00Z", storageName: null },
      { physicalCardId: "p3", copyNumber: 3, addedAt: "2026-10-03T00:00:00Z", storageName: "Caixa A" },
    ],
  },
  {
    cardVariantId: "v2",
    languageCode: "en",
    languageName: "Inglês",
    variantLabel: "Reverse Holo",
    isDefaultVariant: false,
    copies: [{ physicalCardId: "p9", copyNumber: 1, addedAt: "2026-10-05T00:00:00Z", storageName: null }],
  },
];

test("tirar um exemplar remove só aquele; grupo vazio sai da lista", () => {
  const afterOne = withoutCopy(groups, "p3");
  assert.equal(totalCopies(afterOne), 2);
  assert.deepEqual(afterOne[0]?.copies.map((copy) => copy.physicalCardId), ["p1"]);
  assert.deepEqual(afterOne[1]?.copies.map((copy) => copy.physicalCardId), ["p9"]);
  const afterGroup = withoutCopy(groups, "p9");
  assert.equal(afterGroup.length, 1);
  assert.equal(totalCopies(withoutCopy(groups, "desconhecido")), 3);
  // A lista original não é alterada.
  assert.equal(totalCopies(groups), 3);
});

test("rótulos sem ambiguidade e em linguagem de colecionador", () => {
  assert.equal(copyTitle({ copyNumber: 2 }), "Exemplar nº 2");
  assert.equal(storageLabel(null), "Sem localização definida");
  assert.equal(storageLabel("  "), "Sem localização definida");
  assert.equal(storageLabel("Caixa A"), "Guardado em Caixa A");
  assert.equal(addedLabel("2026-10-01T00:00:00Z"), "Registrado em 01/10/2026");
  assert.equal(addedLabel("não é data"), "");
  assert.equal(groupLabel({ variantLabel: null, isDefaultVariant: true, languageName: "Português" }), "Versão padrão · Português");
  assert.equal(groupLabel({ variantLabel: "Reverse Holo", isDefaultVariant: false, languageName: "Inglês" }), "Reverse Holo · Inglês");
});

test("progresso: só a última cópia da carta numa coleção de Set muda o progresso", () => {
  assert.equal(removalAffectsProgress("card_set", 1), true);
  assert.equal(removalAffectsProgress("card_set", 2), false);
  assert.equal(removalAffectsProgress("free", 1), false);
});

test("erros de 5047/5036 viram motivos claros (texto cru nunca chega ao usuário)", () => {
  assert.equal(
    classifyCollectionFailure("P0001", "uma ou mais physical_card_ids não estão alocadas a esta Collection"),
    "not_linked",
  );
  assert.equal(classifyCollectionFailure("P0001", "collection not found or not owned by caller"), "not_found");
  assert.equal(classifyCollectionFailure("P0001", "collection is archived — reactivate before deallocating"), "not_found");
  assert.equal(classifyCollectionFailure("P0001", "storage container does not belong to caller inventory"), "storage_invalid");
  // O "já estão alocadas" da 5046 continua sendo outro caso.
  assert.equal(classifyCollectionFailure("P0001", "uma ou mais physical_card_ids já estão alocadas a uma Collection"), "already_linked");
});

test("Adicionar as que já tenho: uma por carta que falta, com a arte do grupo sugerido; escolha filtra pela lista", async () => {
  const { linkItems, selectedCardIds } = await import("./colecoes.ts");
  const candidates = [
    { physicalCardId: "p1", cardId: "c1", collectorNumber: "006", cardName: "Cherubi", languageCode: "pt-BR" },
    { physicalCardId: "p2", cardId: "c2", collectorNumber: "007", cardName: "Cherrim", languageCode: "en" },
    { physicalCardId: "p3", cardId: "c3", collectorNumber: "008", cardName: "Vivillon", languageCode: "en" },
  ];
  const groups = [
    { collectorNumber: "006", imagePath: "rev.png", isDefaultVariant: false, languageCode: "pt-BR" },
    { collectorNumber: "006", imagePath: "pad-pt.png", isDefaultVariant: true, languageCode: "pt-BR" },
    { collectorNumber: "007", imagePath: "pad-pt.png", isDefaultVariant: true, languageCode: "pt-BR" },
  ];
  const items = linkItems(candidates, groups);
  assert.deepEqual(
    items.map((item) => [item.cardId, item.imagePath]),
    [
      ["c1", "pad-pt.png"],
      ["c2", "pad-pt.png"],
      ["c3", null],
    ],
  );
  // Uma entrada por carta — nunca repetidas.
  assert.equal(new Set(items.map((item) => item.cardId)).size, items.length);
  assert.deepEqual(selectedCardIds(items, new Set(["c3", "c1", "fora"])), ["c1", "c3"]);
  assert.deepEqual(selectedCardIds(items, new Set()), []);
});
