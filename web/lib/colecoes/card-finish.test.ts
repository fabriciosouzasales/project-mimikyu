// Meu acervo — classificação visual do acabamento (MY-INVENTORY-HOLOGRAPHIC-FINISH-FOUNDATION-01).
// Executar: node --experimental-strip-types --test lib/colecoes/card-finish.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { test } from "node:test";
import { classifyFinish, finishLayerSpec, isSecretNumber, type CardFinish } from "./card-finish.ts";

const effect = (t: string | null | undefined, r: string | null | undefined) => classifyFinish(t, r).effect;
const reason = (t: string | null | undefined, r: string | null | undefined) => {
  const f = classifyFinish(t, r);
  return f.effect === "none" ? f.reason : null;
};

test("STANDARD nunca recebe efeito, qualquer que seja a raridade", () => {
  for (const r of ["COMMON", "RARE", "ULTRA_RARE", "ILLUSTRATION_RARE", "PROMO", null]) {
    assert.deepEqual(classifyFinish("STANDARD", r), { effect: "none", reason: "standard" }, String(r));
  }
});

test("HOLO tradicional: janela só com moldura confiável", () => {
  for (const r of ["COMMON", "UNCOMMON", "RARE", "RARE_HOLO", "DOUBLE_RARE", "ACE_SPEC_RARE"]) {
    assert.equal(effect("HOLO", r), "holo-window", r);
  }
});

test("HOLO full art: carta inteira só com raridade de arte total", () => {
  for (const r of ["RARE_SECRET", "ILLUSTRATION_RARE", "SPECIAL_ILLUSTRATION_RARE", "ULTRA_RARE", "HYPER_RARE", "MEGA_HYPER_RARE", "SHINY_ULTRA_RARE"]) {
    assert.equal(effect("HOLO", r), "holo-full", r);
  }
});

test("PIKACHU_RARE e demais geometrias sem evidência: sem efeito", () => {
  for (const r of [
    "PIKACHU_RARE",
    "PROMO",
    "MEGA_ATTACK_RARE",
    "FUTURISTIC_RARE",
    "CLASSIC_COLLECTION",
    "SHINY_RARE",
    "RARE_HOLO_V",
    "RARE_HOLO_VMAX",
    "RARE_HOLO_VSTAR",
    "RARE_HOLO_LV_X",
    "RADIANT_RARE",
    "NONE",
    "QUALQUER_COISA_NOVA",
  ]) {
    assert.equal(reason("HOLO", r), "unsafe-geometry", r);
  }
});

test("REVERSE_HOLO: corpo da carta com moldura confiável; full art reversa não existe", () => {
  for (const r of ["COMMON", "UNCOMMON", "RARE", "DOUBLE_RARE"]) assert.equal(effect("REVERSE_HOLO", r), "reverse-body", r);
  for (const r of ["ILLUSTRATION_RARE", "ULTRA_RARE", "PROMO", "PIKACHU_RARE"]) {
    assert.equal(reason("REVERSE_HOLO", r), "unsafe-geometry", r);
  }
});

test("reversas com padrão: mesmo lugar físico do brilho (corpo)", () => {
  for (const t of [
    "POKE_BALL_REVERSE",
    "MASTER_BALL_REVERSE",
    "ENERGY_REVERSE",
    "LOVE_BALL_REVERSE",
    "FRIEND_BALL_REVERSE",
    "QUICK_BALL_REVERSE",
    "DUSK_BALL_REVERSE",
    "ROCKET_REVERSE",
    "COSMOS_REVERSE",
    "TINSEL_REVERSE",
  ]) {
    assert.equal(effect(t, "COMMON"), "reverse-body", t);
  }
});

test("COSMOS_HOLO: tratado como holográfica (mesmo lugar), sujeito à geometria", () => {
  assert.equal(effect("COSMOS_HOLO", "RARE"), "holo-window");
  // As 2 cópias reais são PROMO → sem efeito.
  assert.equal(reason("COSMOS_HOLO", "PROMO"), "unsafe-geometry");
});

test("METAL, LENTICULAR e holográficas de textura própria: sem efeito (especial)", () => {
  for (const t of ["METAL", "METAL_GOLD", "LENTICULAR", "RAINBOW_HOLO", "GOLD_HOLO", "CRACKED_ICE_HOLO", "GALAXY_HOLO", "TINSEL_HOLO", "MASTER_BALL_HOLO"]) {
    assert.deepEqual(classifyFinish(t, "RARE"), { effect: "none", reason: "special" }, t);
    assert.deepEqual(classifyFinish(t, "ULTRA_RARE"), { effect: "none", reason: "special" }, t);
  }
});

test("códigos desconhecidos, inativos ou estampados: sem efeito", () => {
  for (const t of ["STAFF_HOLO", "PROMO_STAMPED", "SET_LOGO_REVERSE", "EBGAMES_REVERSE", "PRERELEASE_HOLO", "W_PROMO_STAMPED", "XYZ"]) {
    assert.equal(reason(t, "RARE"), "unknown-type", t);
  }
});

test("contrato sem códigos (frontend antes da 5261/5262): sem efeito, nunca erro", () => {
  assert.deepEqual(classifyFinish(undefined, undefined), { effect: "none", reason: "missing" });
  assert.deepEqual(classifyFinish(null, "RARE"), { effect: "none", reason: "missing" });
  assert.deepEqual(classifyFinish("HOLO", null), { effect: "none", reason: "missing" });
  assert.deepEqual(classifyFinish("  ", "RARE"), { effect: "none", reason: "missing" });
  assert.deepEqual(classifyFinish("HOLO", ""), { effect: "none", reason: "missing" });
});

test("normalização: espaços e caixa não mudam a decisão", () => {
  assert.equal(effect(" holo ", " rare "), "holo-window");
  assert.equal(effect("reverse_holo", "common"), "reverse-body");
});

test("distribuição real do acervo de Fabrício (LIVE 2026-10-24) cai nas classes esperadas", () => {
  const cases: [string, string, CardFinish["effect"]][] = [
    ["HOLO", "DOUBLE_RARE", "holo-window"],
    ["HOLO", "RARE", "holo-window"],
    ["HOLO", "ILLUSTRATION_RARE", "holo-full"],
    ["HOLO", "SPECIAL_ILLUSTRATION_RARE", "holo-full"],
    ["HOLO", "ULTRA_RARE", "holo-full"],
    ["HOLO", "MEGA_HYPER_RARE", "holo-full"],
    ["HOLO", "PIKACHU_RARE", "none"],
    ["HOLO", "PROMO", "none"],
    ["HOLO", "CLASSIC_COLLECTION", "none"],
    ["HOLO", "MEGA_ATTACK_RARE", "none"], // sem número: geometria incerta
    ["HOLO", "FUTURISTIC_RARE", "none"],
    ["COSMOS_HOLO", "PROMO", "none"],
    ["REVERSE_HOLO", "COMMON", "reverse-body"],
    ["REVERSE_HOLO", "UNCOMMON", "reverse-body"],
    ["REVERSE_HOLO", "RARE", "reverse-body"],
  ];
  for (const [t, r, e] of cases) assert.equal(effect(t, r), e, `${t}/${r}`);
});

test("camadas: um nó por efeito; nenhum para 'none'", () => {
  assert.deepEqual(finishLayerSpec({ effect: "holo-window" }), { area: "window", tone: "holo" });
  assert.deepEqual(finishLayerSpec({ effect: "holo-full" }), { area: "full", tone: "holo" });
  assert.deepEqual(finishLayerSpec({ effect: "reverse-body" }), { area: "body", tone: "reverse" });
  for (const r of ["standard", "special", "unknown-type", "unsafe-geometry", "missing"] as const) {
    assert.equal(finishLayerSpec({ effect: "none", reason: r }), null, r);
  }
});

test("carta secreta do Set (número acima do total): brilho na carta toda, qualquer raridade", () => {
  const sec = (n: string, total: number | null) => ({ collectorNumber: n, collectorTotal: total });
  // Casos reais do acervo (LIVE 2026-10-24).
  assert.equal(classifyFinish("HOLO", "MEGA_ATTACK_RARE", sec("266", 217)).effect, "holo-full");
  assert.equal(classifyFinish("HOLO", "FUTURISTIC_RARE", sec("157", 128)).effect, "holo-full");
  assert.equal(classifyFinish("HOLO", "ILLUSTRATION_RARE", sec("133", 132)).effect, "holo-full");
  assert.equal(classifyFinish("HOLO", "MEGA_HYPER_RARE", sec("295", 217)).effect, "holo-full");
  // Secreta vence a janela e a geometria incerta.
  assert.equal(classifyFinish("HOLO", "RARE", sec("140", 132)).effect, "holo-full");
  assert.equal(classifyFinish("HOLO", "PIKACHU_RARE", sec("140", 128)).effect, "holo-full");
  assert.equal(classifyFinish("HOLO", "PROMO", sec("120", 111)).effect, "holo-full");
  // Não secreta: regra da raridade continua.
  assert.equal(classifyFinish("HOLO", "RARE", sec("010", 132)).effect, "holo-window");
  assert.equal(classifyFinish("HOLO", "PIKACHU_RARE", sec("023", 128)).effect, "none");
  assert.equal(classifyFinish("HOLO", "RARE", sec("132", 132)).effect, "holo-window"); // igual ao total não é secreta
  // Secreta não muda acabamento: padrão e especial seguem sem efeito; reversa secreta não existe.
  assert.equal(classifyFinish("STANDARD", "ULTRA_RARE", sec("150", 132)).effect, "none");
  assert.equal(classifyFinish("METAL", "RARE", sec("150", 132)).effect, "none");
  assert.deepEqual(classifyFinish("REVERSE_HOLO", "COMMON", sec("150", 132)), { effect: "none", reason: "unsafe-geometry" });
});

test("isSecretNumber: só número puro acima do total", () => {
  assert.equal(isSecretNumber("133", 132), true);
  assert.equal(isSecretNumber(" 0133 ", 132), true);
  assert.equal(isSecretNumber("132", 132), false);
  assert.equal(isSecretNumber("TG05", 30), false);
  assert.equal(isSecretNumber("SWSH031", null), false);
  assert.equal(isSecretNumber("150", 0), false);
  assert.equal(isSecretNumber(null, 132), false);
  assert.equal(isSecretNumber(undefined, undefined), false);
});
