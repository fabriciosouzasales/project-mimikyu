import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { variantOptionLabel } from "./acervo-add.ts";

const read = (path: string) => readFileSync(new URL(`../../${path}`, import.meta.url), "utf8");

test("variantOptionLabel: padrão nunca repete 'Padrão (Padrão)'", () => {
  assert.equal(variantOptionLabel({ isDefault: true, label: "Padrão" }), "Padrão");
  assert.equal(variantOptionLabel({ isDefault: true, label: " padrão " }), "Padrão", "caixa e espaços");
  assert.equal(variantOptionLabel({ isDefault: true, label: null }), "Padrão");
  assert.equal(variantOptionLabel({ isDefault: true, label: "" }), "Padrão");
  assert.equal(variantOptionLabel({ isDefault: true, label: "Holográfica" }), "Padrão (Holográfica)", "rótulo diferente continua visível");
  assert.equal(variantOptionLabel({ isDefault: false, label: "Holográfica Reversa" }), "Holográfica Reversa");
  assert.equal(variantOptionLabel({ isDefault: false, label: null }), "Outra versão");
  assert.equal(variantOptionLabel({ isDefault: false, label: "  " }), "Outra versão");
});

test("SelectionLine: Versão + Idioma na 1ª linha, Condição + Cópias na 2ª; Versão só com mais de uma opção", () => {
  const src = read("components/colecoes/acervo/acervo-add.tsx");
  const body = src.slice(src.indexOf("function SelectionLine"), src.indexOf("// Adicionar um Set inteiro"));
  const iControls = body.indexOf("<div className={styles.lineControls}>");
  const iRow1 = body.indexOf("{list.length > 1 || languages.length > 1 ? (");
  const iVersion = body.indexOf("htmlFor={`${id}-variant`}");
  const iLanguage = body.indexOf("htmlFor={`${id}-language`}");
  const iRow2 = body.indexOf("<div className={styles.lineRow}>", iLanguage);
  const iCondition = body.indexOf("htmlFor={`${id}-condition`}", iRow2);
  const iCopies = body.indexOf("id={`${id}-qty`}", iCondition);
  assert.ok(iControls > 0 && iControls < iRow1 && iRow1 < iVersion && iVersion < iLanguage && iLanguage < iRow2 && iRow2 < iCondition && iCondition < iCopies, "ordem dos campos");
  assert.match(body, /\{list\.length > 1 \? \(\s*<div className=\{styles\.field\}>\s*<label htmlFor=\{`\$\{id\}-variant`\}/, "Versão só com mais de uma opção");
  assert.match(body, /\{variantOptionLabel\(variant\)\}/);
  // Rótulos associados (teclado/leitor de tela) e controles inalterados.
  assert.match(body, /htmlFor=\{`\$\{id\}-language`\}/);
  assert.match(body, /htmlFor=\{`\$\{id\}-condition`\}/);
  assert.match(body, /role="group" aria-labelledby=\{`\$\{id\}-qty`\}/);
  assert.match(body, /if \(isCardConditionCode\(value\)\) onChange\(\{ conditionCode: value \}\);/);
  assert.match(body, /onChange\(\{ quantity: line\.quantity - 1 \}\)/);
});

test("CSS: grade de 2 colunas, campo sozinho ocupa a linha, 1 coluna em painel estreito; campos do Set intocados", () => {
  const css = read("components/colecoes/acervo/acervo-add.module.css");
  assert.match(css, /\.lineMain \{[^}]*container-type: inline-size;[^}]*container-name: acervo-add-line;/);
  assert.match(css, /\.lineRow \{[^}]*grid-template-columns: repeat\(2, minmax\(0, 1fr\)\);/);
  assert.match(css, /\.lineRow > :only-child \{\s*grid-column: 1 \/ -1;/);
  assert.match(css, /@container acervo-add-line \(max-width: 24rem\) \{\s*\.lineRow \{\s*grid-template-columns: minmax\(0, 1fr\);/);
  assert.match(css, /\.lineRow > \.field \{\s*min-width: 0;/, "sem largura mínima que corte rótulos");
  // `.field` base (usado também pelo Set e pelo Local) continua igual.
  assert.match(css, /\.field \{\s*display: flex;\s*flex-direction: column;\s*gap: 0\.25rem;\s*min-width: 8rem;\s*flex: 1 1 8rem;\s*\}/);
  assert.doesNotMatch(css, /\.lineControls \.field:last-child/);
});
