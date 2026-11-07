// PERFORMANCE INCIDENT-01, E1 (C2a) — uma atualização por mutação no Meu acervo.
// Executar: node --experimental-strip-types --test lib/colecoes/acervo-refresh.test.ts (a partir de web/)
//
// Duas camadas:
// 1. as regras puras de quando o cliente ainda pede `router.refresh()`;
// 2. guardas de código: todo desfecho em que o cliente deixou de pedir refresh continua revalidado
//    pela própria ação (senão a tela ficaria velha), e os componentes do acervo não voltam a pedir
//    refresh fora dos pontos documentados.

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import {
  MOVE_CONFIRM_REVALIDATED_REASONS,
  activeProvisional,
  addCommitNeedsClientRefresh,
  moveConfirmNeedsClientRefresh,
  quantityToSyncAfterSave,
} from "./acervo-refresh.ts";

const web = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const read = (path: string) => readFileSync(resolve(web, path), "utf8");
const actions = read("app/colecoes/acervo/actions.ts");

/** Corpo de uma Server Action exportada de actions.ts (até a próxima `export`). */
function actionBody(name: string): string {
  const start = actions.indexOf(`export async function ${name}(`);
  assert.ok(start >= 0, `ação ${name} não encontrada`);
  const next = actions.indexOf("\nexport ", start + 1);
  return actions.slice(start, next === -1 ? undefined : next);
}

/** Código sem comentários (os comentários citam `router.refresh()` para explicar a ausência dele). */
const code = (source: string) => source.replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "");
const refreshCalls = (source: string) => code(source).match(/router\.refresh\(\)/g)?.length ?? 0;

test("mover: refresh só quando a ação não revalidou (unresolved) ou o desfecho é incerto (unknown)", () => {
  assert.equal(moveConfirmNeedsClientRefresh({ ok: true }), false);
  assert.equal(moveConfirmNeedsClientRefresh({ ok: false, reason: "plan_changed" }), false);
  assert.equal(moveConfirmNeedsClientRefresh({ ok: false, reason: "storage_gone" }), false);
  assert.equal(moveConfirmNeedsClientRefresh({ ok: false, reason: "unresolved" }), true);
  assert.equal(moveConfirmNeedsClientRefresh({ ok: false, reason: "unknown" }), true);
  // Falhas que nada gravam e nunca pediram refresh continuam sem ele.
  assert.equal(moveConfirmNeedsClientRefresh({ ok: false, reason: "invalid" }), false);
});

test("cadastro: sem refresh no Meu acervo; com destino (coleção, fichário) o refresh continua", () => {
  assert.equal(addCommitNeedsClientRefresh({ hasTarget: false }), false);
  assert.equal(addCommitNeedsClientRefresh({ hasTarget: true }), true);
});

test("guarda: moveMyCopies revalida exatamente sucesso + os desfechos que o cliente deixou de atualizar", () => {
  const body = actionBody("moveMyCopies");
  const condition = body.match(/if \((result\.ok[^)]*)\) \{\s*\/\/[^\n]*\n\s*revalidatePath\(ACERVO_PATH\)/);
  assert.ok(condition, "condição de revalidação de moveMyCopies mudou — rever lib/colecoes/acervo-refresh.ts");
  const reasons: string[] = [...(condition[1] ?? "").matchAll(/result\.reason === "([a-z_]+)"/g)].map((m) => m[1] ?? "").sort();
  assert.deepEqual(reasons, [...MOVE_CONFIRM_REVALIDATED_REASONS].map(String).sort());
  // Todo desfecho sem refresh no cliente precisa estar revalidado no servidor.
  for (const reason of ["plan_changed", "storage_gone"]) {
    assert.equal(moveConfirmNeedsClientRefresh({ ok: false, reason }), false);
    assert.ok(reasons.includes(reason), `${reason} sem refresh no cliente e sem revalidação no servidor`);
  }
  assert.ok(!reasons.includes("unresolved"), "unresolved passou a revalidar: o refresh do cliente pode sair");
});

test("guarda: cadastro, quantidade e lixeira revalidam o acervo nos desfechos que antes pediam refresh", () => {
  // register() — usado por confirmAddCards/confirmAddSet/addMyCopies — revalida após gravar com sucesso.
  const register = actions.slice(actions.indexOf("async function register("), actions.indexOf("\nexport ", actions.indexOf("async function register(")));
  assert.match(register, /if \(error\) return fail\(fn, startedAt, error\);[\s\S]*revalidatePath\(ACERVO_PATH\);\s*\/\/ Com coleção/);
  // removeMyCopy: revalida depois de remover.
  assert.match(actionBody("removeMyCopy"), /revalidatePath\(ACERVO_PATH\);\s*return \{ ok: true, removed: data \}/);
  // removeMyCopies: revalida na falha parcial (removed > 0) e no fim.
  const removeMany = actionBody("removeMyCopies");
  assert.match(removeMany, /if \(removed > 0\) revalidatePath\(ACERVO_PATH\);/);
  assert.match(removeMany, /revalidatePath\(ACERVO_PATH\);\s*return \{ ok: true, removed \}/);
});

test("guarda: localização revalida no sucesso e em storage_gone/copies_gone", () => {
  const body = actionBody("setMyCopiesStorage");
  assert.match(body, /if \(reason === "storage_gone" \|\| reason === "copies_gone"\) revalidatePath\(ACERVO_PATH\);/);
  assert.match(body, /revalidatePath\(ACERVO_PATH\);\s*revalidatePath\(LOCAIS_PATH\);\s*revalidatePath\(COLECOES_PATH, "layout"\);\s*return \{ ok: true/);
});

test("guarda: componentes do acervo sem refresh redundante fora dos pontos documentados", () => {
  // Quantidade, lixeira e localização: nenhuma chamada a router.refresh().
  assert.equal(refreshCalls(read("components/colecoes/acervo/copy-quantity-control.tsx")), 0);
  assert.equal(refreshCalls(read("components/colecoes/acervo/copy-remove-button.tsx")), 0);
  assert.equal(refreshCalls(read("components/colecoes/acervo/copy-storage-list.tsx")), 0);
  // Lixeira, último exemplar: continua fechando o detalhe (navegação, não refresh).
  assert.match(read("components/colecoes/acervo/copy-remove-button.tsx"), /if \(isLastCopy\) startNavigation\(\(\) => router\.replace\(closeHref, \{ scroll: false \}\)\);/);
  // Mover: um único ponto de refresh (helper), chamado na prévia (storage_gone) e pela regra da confirmação.
  const move = read("components/colecoes/acervo/acervo-move-panel.tsx");
  assert.equal(refreshCalls(move), 1);
  assert.match(move, /if \(moveConfirmNeedsClientRefresh\(result\)\) refresh\(\);/);
  assert.equal(code(move).match(/\brefresh\(\);/g)?.length, 2, "esperado: prévia storage_gone + regra da confirmação");
  // Cadastro: refresh só com destino.
  const add = read("components/colecoes/acervo/acervo-add.tsx");
  assert.equal(refreshCalls(add), 1);
  assert.match(add, /if \(addCommitNeedsClientRefresh\(\{ hasTarget \}\)\) startRefresh\(\(\) => router\.refresh\(\)\);/);
  assert.equal(add.match(/hasTarget: target !== undefined/g)?.length, 2, "CardsFlow e SetFlow");
});

test("provisório de localização estabiliza no servidor em qualquer ordem de chegada", () => {
  const before = { storageByCopy: { a: null } };
  const after = { storageByCopy: { a: "box" } };
  const patch = { ids: ["a"], id: "box", name: "Caixa", basis: before };
  // Ordem 1: provisório gravado, leitura nova chega depois → provisório some.
  assert.equal(activeProvisional(patch, before), patch);
  assert.equal(activeProvisional(patch, after), null);
  // Ordem 2: leitura nova já exibida quando o provisório é gravado → ele nunca vale.
  assert.equal(activeProvisional({ ...patch, basis: before }, after), null);
  // Leitura indisponível depois da gravação (contexto `null`) → servidor manda.
  assert.equal(activeProvisional(patch, null), null);
  assert.equal(activeProvisional(null, before), null);
});

test("quantidade sincroniza com o total do servidor só quando ele mudou durante o envio", () => {
  assert.equal(quantityToSyncAfterSave(3, 5), 5); // +2 confirmado, resposta chegou durante o envio
  assert.equal(quantityToSyncAfterSave(5, 4), 4); // falha parcial: 1 saiu
  assert.equal(quantityToSyncAfterSave(3, 3), null); // falha sem alteração: escolha preservada
});

test("guarda: componentes usam as regras determinísticas do provisório", () => {
  const storage = code(read("components/colecoes/acervo/copy-storage-list.tsx"));
  assert.match(storage, /const activePatch = activeProvisional\(patch, storage\);/);
  assert.match(storage, /const basis = storage;/);
  assert.match(storage, /setPatch\(\{ ids, id: target, name, basis \}\);/);
  // Nenhuma leitura direta do provisório fora da regra: só a declaração do estado.
  assert.equal(storage.match(/\bpatch\b(?!\s*,\s*storage\))/g)?.length, 1);
  const quantity = code(read("components/colecoes/acervo/copy-quantity-control.tsx"));
  assert.match(quantity, /quantityToSyncAfterSave\(totalAtStart, latestTotal\.current\)/);
  assert.match(quantity, /latestTotal\.current = total;/);
});
