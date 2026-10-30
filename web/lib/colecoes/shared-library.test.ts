// Coleções compartilhadas dentro da Biblioteca (V1-12) — regras puras.
// Executar: node --experimental-strip-types --test lib/colecoes/shared-library.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { test } from "node:test";
import {
  libraryItemHref,
  sharedCoverKey,
  sharedLibraryItem,
  sharedLibrarySlice,
  sharedOwnerText,
  withSharedIdentity,
} from "./shared-library.ts";
import type { SharedWithMe } from "./sharing.ts";

const ID = "11111111-1111-4111-8111-111111111111";

function shared(overrides: Partial<SharedWithMe> = {}): SharedWithMe {
  return {
    collectionId: ID,
    name: "Coleção da Ana",
    completionPolicy: "STANDARD_SET",
    archived: false,
    coverFinish: "vinho",
    cardSetCode: "SV1",
    cardSetName: "Scarlet & Violet",
    ownerDisplayName: "Ana Souza",
    copies: 12,
    progress: { total: 198, satisfied: 40, complete: false },
    ...overrides,
  };
}

test("sharedLibraryItem: mesmo formato do card próprio, com titular e sem edição", () => {
  const item = sharedLibraryItem(shared());
  assert.equal(item.id, ID);
  assert.equal(item.sharedBy, "Ana Souza");
  assert.equal(item.totalPositions, 198);
  assert.equal(item.satisfiedPositions, 40);
  assert.equal(item.isComplete, false);
  assert.equal(item.copiesCount, 12);
  assert.equal(item.finish, "vinho");
  assert.equal(item.finishEditable, false);
  assert.equal(item.lifecycleStatus, "ACTIVE");
  assert.equal(item.cardSetLogoPath, null);
});

test("sharedLibraryItem: sem progresso (coleção livre) e arquivada", () => {
  const item = sharedLibraryItem(shared({ progress: null, completionPolicy: null, archived: true, cardSetCode: null }));
  assert.equal(item.totalPositions, 0);
  assert.equal(item.completionPolicy, "NONE");
  assert.equal(item.lifecycleStatus, "ARCHIVED");
});

test("withSharedIdentity: Set usa o logo do Set; capa enviada só sem Set", () => {
  const setItem = sharedLibraryItem(shared());
  const a = withSharedIdentity(setItem, { cardSetLogoPath: "x/y.webp", coverUrl: null, coverCode: null });
  assert.equal(a.item.cardSetLogoPath, "x/y.webp");
  assert.equal(a.item.coverLogoPath, null);
  assert.equal(a.coverUrl, null);

  const freeItem = sharedLibraryItem(shared({ cardSetCode: null, cardSetName: null }));
  const b = withSharedIdentity(freeItem, { cardSetLogoPath: null, coverUrl: "https://signed", coverCode: "ANA" });
  assert.equal(b.item.coverLogoPath, sharedCoverKey(ID));
  assert.equal(b.item.coverCode, "ANA");
  assert.deepEqual(b.coverUrl, [sharedCoverKey(ID), "https://signed"]);

  const none = withSharedIdentity(freeItem, undefined);
  assert.equal(none.item, freeItem);
  assert.equal(none.coverUrl, null);
});

test("sharedLibrarySlice: só compartilhadas → página 1 cheia de compartilhadas", () => {
  assert.deepEqual(sharedLibrarySlice({ ownedTotal: 0, ownedOnPage: 0, sharedCount: 1, pageNumber: 1, pageSize: 48 }), {
    offset: 0,
    count: 1,
    total: 1,
  });
});

test("sharedLibrarySlice: próprias e compartilhadas na mesma estante", () => {
  // 3 próprias + 2 compartilhadas → uma página com as 5.
  assert.deepEqual(sharedLibrarySlice({ ownedTotal: 3, ownedOnPage: 3, sharedCount: 2, pageNumber: 1, pageSize: 48 }), {
    offset: 0,
    count: 2,
    total: 5,
  });
  // 50 próprias (48 + 2) + 60 compartilhadas: p1 só próprias; p2 2 próprias + 46; p3 as 14 restantes.
  assert.deepEqual(sharedLibrarySlice({ ownedTotal: 50, ownedOnPage: 48, sharedCount: 60, pageNumber: 1, pageSize: 48 }), {
    offset: 0,
    count: 0,
    total: 110,
  });
  assert.deepEqual(sharedLibrarySlice({ ownedTotal: 50, ownedOnPage: 2, sharedCount: 60, pageNumber: 2, pageSize: 48 }), {
    offset: 0,
    count: 46,
    total: 110,
  });
  assert.deepEqual(sharedLibrarySlice({ ownedTotal: 50, ownedOnPage: 0, sharedCount: 60, pageNumber: 3, pageSize: 48 }), {
    offset: 46,
    count: 14,
    total: 110,
  });
});

test("sharedLibrarySlice: nenhuma coleção e página além do fim", () => {
  assert.deepEqual(sharedLibrarySlice({ ownedTotal: 0, ownedOnPage: 0, sharedCount: 0, pageNumber: 1, pageSize: 48 }), {
    offset: 0,
    count: 0,
    total: 0,
  });
  assert.equal(sharedLibrarySlice({ ownedTotal: 2, ownedOnPage: 0, sharedCount: 1, pageNumber: 4, pageSize: 48 }).count, 0);
});

test("libraryItemHref e sharedOwnerText", () => {
  assert.equal(libraryItemHref({ id: ID, sharedBy: "Ana Souza" }), `/colecoes/compartilhada/${ID}`);
  assert.equal(libraryItemHref({ id: ID }), `/colecoes/colecoes/${ID}`);
  assert.equal(sharedOwnerText({ sharedBy: "Ana Souza" }), "de Ana Souza");
  assert.equal(sharedOwnerText({ sharedBy: null }), null);
});
