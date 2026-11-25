// V1-13 · E3-3 — metadados da coleção pelo EDITOR: regras puras.
// Executar: node --experimental-strip-types --test lib/colecoes/editor-collection-metadata.test.ts (a partir de web/)
// Testes LOCAIS com respostas simuladas. Não provam autorização nem concorrência: isso é do servidor (5376)
// e das provas com sessões reais (C-244).

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import {
  COLLECTION_DESCRIPTION_MAX,
  classifyMetadataFailure,
  editorCoverCodeApplies,
  metadataFailureMessage,
  metadataFailureRechecks,
  normalizeCollectionDescription,
  sameText,
  validCoverCode,
  validFinish,
  validTextInput,
} from "./editor-collection-metadata.ts";

test("validação: nome não vazio (até 80), descrição até 500 (vazia = sem descrição), código 2–6, acabamento da lista", () => {
  assert.deepEqual(validTextInput("  Base  Set ", "  Minha meta  "), { name: "Base Set", description: "Minha meta" });
  assert.deepEqual(validTextInput("Base", "   "), { name: "Base", description: null });
  assert.equal(validTextInput("   ", "x"), null);
  assert.equal(validTextInput("Base", "x".repeat(COLLECTION_DESCRIPTION_MAX + 1)), null);
  assert.equal(normalizeCollectionDescription("x".repeat(COLLECTION_DESCRIPTION_MAX)), "x".repeat(COLLECTION_DESCRIPTION_MAX));
  assert.equal(validCoverCode("mmk"), "MMK");
  assert.equal(validCoverCode(""), null);
  assert.equal(validCoverCode("a"), "invalid");
  assert.equal(validCoverCode("ABCDEFG"), "invalid");
  for (const f of ["onix", "vinho", "floresta", "marinho", "caramelo", "perola"]) assert.equal(validFinish(f), true, f);
  assert.equal(validFinish("ouro"), false);
});

test("código da placa só em coleção livre ou Pokédex (a 5376 recusa as demais)", () => {
  assert.equal(editorCoverCodeApplies({ completionPolicy: "NONE", cardSetCode: null }), true);
  assert.equal(editorCoverCodeApplies({ completionPolicy: "REFERENCE_POSITION", cardSetCode: null }), true);
  assert.equal(editorCoverCodeApplies({ completionPolicy: "STANDARD_SET", cardSetCode: "base1" }), false);
  assert.equal(editorCoverCodeApplies({ completionPolicy: "MASTER_SET", cardSetCode: "base1" }), false);
});

test("recusas da 5376 → motivo estável; sem SQLSTATE = resultado incerto", () => {
  assert.equal(classifyMetadataFailure("42501", "CAPABILITY_NOT_ENABLED"), "capability_closed");
  assert.equal(classifyMetadataFailure("P0002", "COLLECTION_NOT_FOUND"), "access_lost", "rebaixado, removido, saiu: indistinguíveis");
  assert.equal(classifyMetadataFailure("55000", "COLLECTION_ARCHIVED"), "archived");
  assert.equal(classifyMetadataFailure("55000", "NOT_FREE_COLLECTION"), "not_free");
  assert.equal(classifyMetadataFailure("22023", "INVALID_FINISH"), "invalid");
  assert.equal(classifyMetadataFailure("22023", "INVALID_COVER_CODE"), "invalid");
  assert.equal(classifyMetadataFailure("22023", "p_name não pode ser vazio"), "invalid");
  assert.equal(classifyMetadataFailure("28000", "not_authenticated"), "not_authenticated");
  assert.equal(classifyMetadataFailure("", "fetch failed"), "uncertain");
  assert.equal(classifyMetadataFailure(undefined, undefined), "uncertain");
  assert.equal(classifyMetadataFailure("XX000", "boom"), "unknown");
  assert.equal(classifyMetadataFailure.length, 2, "só código e nome da exceção");
  for (const r of ["changed", "access_lost", "archived", "capability_closed", "uncertain"] as const) assert.equal(metadataFailureRechecks(r), true, r);
  for (const r of ["invalid", "not_free", "unknown"] as const) assert.equal(metadataFailureRechecks(r), false, r);
  for (const r of ["changed", "invalid", "not_free", "archived", "capability_closed", "access_lost", "uncertain", "unknown"] as const) {
    const text = metadataFailureMessage(r);
    assert.ok(text.length > 0 && !/[A-Z]{3,}_[A-Z]/.test(text) && !/titular .*@|uuid/i.test(text), `${r}: ${text}`);
  }
  assert.match(metadataFailureMessage("uncertain"), /Não conseguimos confirmar/);
});

test("concorrência: a gravação só segue se o valor atual ainda é o que a tela mostrou", () => {
  assert.equal(sameText({ name: "Base", description: "Meta" }, { name: "Base", description: "Meta" }), true);
  assert.equal(sameText({ name: "Base", description: " Meta " }, { name: "Base", description: "Meta" }), true, "mesma normalização");
  assert.equal(sameText({ name: "Base 2", description: "Meta" }, { name: "Base", description: "Meta" }), false, "titular renomeou");
  assert.equal(sameText({ name: "Base", description: null }, { name: "Base", description: "Meta" }), false, "titular apagou a descrição");
});

test("ações: configuração antes de tudo; releitura antes da escrita; uma chamada por pedido; sem hint/details", () => {
  const src = readFileSync(new URL("../../app/colecoes/compartilhada/[id]/actions.ts", import.meta.url), "utf8");
  for (const fn of ["editorSaveCollectionText", "editorSaveCoverFinish", "editorSaveCoverCode"]) {
    const start = src.indexOf(`export async function ${fn}`);
    const body = src.slice(start, src.indexOf("\nexport async function", start + 10) > 0 ? src.indexOf("\nexport async function", start + 10) : undefined);
    assert.ok(body.indexOf('if (!enabled()) return { ok: false, reason: "disabled" }') > 0, `${fn}: configuração primeiro`);
    const read = body.indexOf("readCurrent(");
    const write = body.search(/rpc\("editor_/);
    assert.ok(read > 0 && write > read, `${fn}: releitura antes da escrita`);
    assert.equal((body.match(/rpc\("editor_/g) ?? []).length, 1, `${fn}: uma escrita`);
    assert.ok(body.includes('"changed"'), `${fn}: recusa se mudou`);
  }
  assert.ok(!/\.hint|\.details/.test(src));
  const editor = readFileSync(new URL("../../components/colecoes/sharing/shared-collection-editor.tsx", import.meta.url), "utf8");
  assert.ok(!/setTimeout\(|retry/i.test(editor.replace(/\/\/.*$/gm, "")), "sem repetição automática");
  for (const forbidden of ["setCollectionVisibility", "archive", "invite", "removeCollectionMember", "completion_policy", "collection_reference"]) {
    assert.ok(!editor.includes(forbidden), `sem ${forbidden} na tela do EDITOR`);
  }
});

test("revisão final: limite da descrição também na ação; resultado parcial sem sucesso global; sem repetição", () => {
  // V1: a ação valida com a mesma regra (500) antes de qualquer leitura ou escrita.
  const actions = readFileSync(new URL("../../app/colecoes/compartilhada/[id]/actions.ts", import.meta.url), "utf8");
  const text = actions.slice(actions.indexOf("export async function editorSaveCollectionText"), actions.indexOf("export async function editorSaveCoverFinish"));
  assert.ok(text.indexOf("validTextInput(input.name, input.description)") < text.indexOf("readCurrent("));
  assert.ok(text.includes('if (!text || !base'), "inválida → recusa sem chamar o banco");
  assert.equal(validTextInput("Base", "x".repeat(COLLECTION_DESCRIPTION_MAX + 1)), null);
  // V2: no formulário, nome/descrição e código são gravações independentes; parcial nunca vira "Informações salvas".
  const form = readFileSync(new URL("../../components/colecoes/colecoes/collection-identity-settings.tsx", import.meta.url), "utf8");
  const editorPath = form.slice(form.indexOf("if (save) {"), form.indexOf("if (nameChanged) {", form.indexOf("if (save) {")));
  const firstFail = editorPath.indexOf("return;");
  assert.ok(firstFail > 0 && firstFail < editorPath.indexOf("save.code("), "falha em nome/descrição: o código nem é tentado");
  assert.ok(editorPath.includes("Nome e descrição salvos. O código não foi salvo:"), "parcial informado por parte");
  assert.ok(editorPath.lastIndexOf("setSaved(true)") > editorPath.lastIndexOf("save.code("), "sucesso global só depois de todas as partes");
  assert.equal((editorPath.match(/save\.text\(/g) ?? []).length, 1);
  assert.equal((editorPath.match(/save\.code\(/g) ?? []).length, 1);
  assert.ok((editorPath.match(/router\.refresh\(\)/g) ?? []).length >= 3, "relê depois de falha, parcial e sucesso");
});
