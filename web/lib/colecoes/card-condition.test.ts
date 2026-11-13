import assert from "node:assert/strict";
import { test } from "node:test";
import {
  CARD_CONDITION_CODES,
  DEFAULT_CARD_CONDITION,
  cardConditionAccessibleText,
  cardConditionLabel,
  cardConditionOptions,
  isCardConditionCode,
  toCardConditionCode,
} from "./card-condition.ts";

test("seis códigos canônicos, na ordem de condition_order (M, NM, LP, MP, HP, DMG); padrão NM", () => {
  assert.deepEqual([...CARD_CONDITION_CODES], ["M", "NM", "LP", "MP", "HP", "DMG"]);
  assert.equal(DEFAULT_CARD_CONDITION, "NM");
});

test("rótulos C-229: LP aparece como SP e DMG como DM; os demais mantêm a sigla", () => {
  const expected: Record<string, [string, string]> = {
    M: ["M", "M · Mint"],
    NM: ["NM", "NM · Near Mint"],
    LP: ["SP", "SP · Slightly Played"],
    MP: ["MP", "MP · Moderately Played"],
    HP: ["HP", "HP · Heavily Played"],
    DMG: ["DM", "DM · Damaged"],
  };
  for (const code of CARD_CONDITION_CODES) {
    const label = cardConditionLabel(code);
    assert.ok(label, code);
    assert.equal(label.code, code, "o código gravado continua o canônico");
    assert.equal(label.short, expected[code]?.[0]);
    assert.equal(label.label, expected[code]?.[1]);
  }
});

test("opções na ordem canônica, uma por código, sem rótulo exibido virando código", () => {
  const options = cardConditionOptions();
  assert.deepEqual(options.map((o) => o.code), [...CARD_CONDITION_CODES]);
  assert.deepEqual(options.map((o) => o.short), ["M", "NM", "SP", "MP", "HP", "DM"]);
  // SP e DM são só exibição: não são códigos aceitos.
  assert.equal(isCardConditionCode("SP"), false);
  assert.equal(isCardConditionCode("DM"), false);
});

test("validação: só os seis códigos, com caixa exata", () => {
  for (const code of CARD_CONDITION_CODES) assert.equal(isCardConditionCode(code), true);
  for (const value of ["nm", "Nm", " NM", "NM ", "", "XX", "GEM MINT", "10", 2, null, undefined, {}, ["NM"]]) {
    assert.equal(isCardConditionCode(value), false, JSON.stringify(value) ?? String(value));
  }
});

test("códigos inesperados ou ausentes viram null — nunca um rótulo inventado", () => {
  assert.equal(toCardConditionCode("LP"), "LP");
  for (const value of [null, undefined, "", "nm", "XX", 7, "SP"]) {
    assert.equal(toCardConditionCode(value), null);
    assert.equal(cardConditionLabel(value), null);
    assert.equal(cardConditionAccessibleText(value), null);
  }
});

test("descrição acessível deixa claro que é a condição declarada (não graduação)", () => {
  assert.equal(cardConditionAccessibleText("LP"), "Condição declarada: SP · Slightly Played");
  assert.equal(cardConditionAccessibleText("NM"), "Condição declarada: NM · Near Mint");
  assert.doesNotMatch(cardConditionAccessibleText("M") ?? "", /grad|nota|PSA|BGS|CGC/i);
});
