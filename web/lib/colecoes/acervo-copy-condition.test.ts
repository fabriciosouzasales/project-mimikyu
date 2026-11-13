import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { toAcervoCopy } from "./acervo-queries.ts";

const base = {
  physical_card_id: "11111111-1111-4111-8111-111111111111",
  copy_number: 2,
  added_at: "2026-11-10T01:28:40.583864+00:00",
  collection_id: "22222222-2222-4222-8222-222222222222",
  collection_name: "Base Set",
  storage_name: "Fichário azul",
};

test("toAcervoCopy: mapeia a 21ª coluna (condition_code, 5363) e preserva os campos existentes", () => {
  assert.deepEqual(toAcervoCopy({ ...base, condition_code: "LP" }), {
    physicalCardId: base.physical_card_id,
    copyNumber: 2,
    addedAt: base.added_at,
    collectionId: base.collection_id,
    collectionName: "Base Set",
    storageName: "Fichário azul",
    conditionCode: "LP",
  });
});

test("toAcervoCopy: seis códigos canônicos passam; ausente, nulo ou inesperado vira null", () => {
  for (const code of ["M", "NM", "LP", "MP", "HP", "DMG"]) {
    assert.equal(toAcervoCopy({ ...base, condition_code: code }).conditionCode, code);
  }
  assert.equal(toAcervoCopy({ ...base }).conditionCode, null, "linha sem a coluna (leitura anterior à 5363)");
  for (const value of [null, "", "nm", "SP", "XX"]) {
    assert.equal(toAcervoCopy({ ...base, condition_code: value }).conditionCode, null, String(value));
  }
});

test("toAcervoCopy: coleção ausente continua null; nenhum outro campo depende da condição", () => {
  const copy = toAcervoCopy({ ...base, collection_id: null, collection_name: null, storage_name: null, condition_code: "DMG" });
  assert.equal(copy.collectionId, null);
  assert.equal(copy.collectionName, null);
  assert.equal(copy.storageName, null);
  assert.equal(copy.conditionCode, "DMG");
});

test("lista de exemplares: selo só com condição conhecida, sigla visível e descrição acessível (com o provisório da edição)", () => {
  const src = readFileSync(new URL("../../components/colecoes/acervo/copy-storage-list.tsx", import.meta.url), "utf8");
  assert.ok(src.includes("const shownCondition = conditionOf(copy.physicalCardId);"), "condição exibida já considera o provisório");
  assert.ok(src.includes("cardConditionLabel(shownCondition)"), "rótulo vem do mapa único");
  assert.ok(src.includes("{condition ? ("), "sem condição conhecida, nada é mostrado");
  assert.ok(src.includes('aria-hidden="true">\n                        {condition.short}'), "sigla visível escondida do leitor de tela");
  assert.ok(src.includes("cardConditionAccessibleText(shownCondition)"), "descrição completa para leitor de tela");
});
