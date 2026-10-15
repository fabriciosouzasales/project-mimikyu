// Geração visível na Pokédex Nacional (Pokédex P4c).
// Executar: node --experimental-strip-types --test lib/pokedex/visible-generation.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { test } from "node:test";
import { resolveVisibleGeneration, type SectionBox } from "./visible-generation.ts";

// Layout aproximado da grade: seções empilhadas com 44 px de espaço entre elas
// (gap de 2,75rem), coordenadas relativas à viewport após uma rolagem qualquer.
function layout(scroll: number): SectionBox[] {
  const heights: Array<[string, number]> = [
    ["GENERATION_I", 4200],
    ["GENERATION_II", 2800],
    ["GENERATION_III", 3700],
  ];
  let top = 600 - scroll; // 600 px de cabeçalho + régua antes da primeira seção
  return heights.map(([code, height]) => {
    const box = { code, top, bottom: top + height };
    top += height + 44;
    return box;
  });
}

const LINE = 62; // logo abaixo da régua fixa

test("1. topo da página: a primeira geração da galeria é a visível", () => {
  assert.equal(resolveVisibleGeneration(layout(0), LINE, null), "GENERATION_I");
});

test("1b. primeira seção cruzando a linha", () => {
  assert.equal(resolveVisibleGeneration(layout(1000), LINE, null), "GENERATION_I");
});

test("2. ao entrar na seção seguinte, o destaque muda", () => {
  // Fim da I em 600+4200=4800; II começa em 4844 (coordenadas de página).
  assert.equal(resolveVisibleGeneration(layout(4844 - LINE), LINE, "GENERATION_I"), "GENERATION_II");
  assert.equal(resolveVisibleGeneration(layout(4844 - LINE + 500), LINE, "GENERATION_I"), "GENERATION_II");
});

test("3. fronteira: no espaço entre seções mantém a anterior (sem piscar nem sumir)", () => {
  // Linha dentro do gap (4800..4844): continua a I, que já estava destacada.
  const inGap = layout(4820 - LINE);
  assert.equal(resolveVisibleGeneration(inGap, LINE, "GENERATION_I"), "GENERATION_I");
  // Vindo de baixo (rolando para cima) no mesmo gap: continua a II, sem oscilar.
  assert.equal(resolveVisibleGeneration(inGap, LINE, "GENERATION_II"), "GENERATION_II");
  // Sem histórico (ex.: retorno de ficha caindo no gap): última seção já passada.
  assert.equal(resolveVisibleGeneration(inGap, LINE, null), "GENERATION_I");
});

test("3b. limite exato: top == linha pertence à nova seção; bottom == linha já não pertence", () => {
  const sections: SectionBox[] = [
    { code: "A", top: -100, bottom: LINE },
    { code: "B", top: LINE, bottom: 900 },
  ];
  assert.equal(resolveVisibleGeneration(sections, LINE, "A"), "B");
});

test("3c. depois da última seção (fim da lista): a última continua destacada", () => {
  assert.equal(resolveVisibleGeneration(layout(20000), LINE, "GENERATION_III"), "GENERATION_III");
});

test("5. pesquisa na visão nacional: só as seções com resultados contam", () => {
  const search: SectionBox[] = [
    { code: "GENERATION_I", top: 700, bottom: 900 },
    { code: "GENERATION_IV", top: 944, bottom: 1144 },
  ];
  assert.equal(resolveVisibleGeneration(search, LINE, null), "GENERATION_I");
  assert.equal(resolveVisibleGeneration(search.map((s) => ({ ...s, top: s.top - 900, bottom: s.bottom - 900 })), LINE, "GENERATION_I"), "GENERATION_IV");
});

test("5b. pesquisa sem resultado: nenhuma geração destacada", () => {
  assert.equal(resolveVisibleGeneration([], LINE, "GENERATION_I"), null);
});

test("anterior que deixou de existir (seções mudaram) não é mantido no gap", () => {
  const sections: SectionBox[] = [
    { code: "GENERATION_I", top: -500, bottom: 40 },
    { code: "GENERATION_II", top: 84, bottom: 800 },
  ];
  assert.equal(resolveVisibleGeneration(sections, LINE, "GENERATION_IX"), "GENERATION_I");
});
