// V1-13 · E2-3A — páginas do fichário compartilhado pelo EDITOR: regras puras.
// Executar: node --experimental-strip-types --test lib/colecoes/editor-binder-pages.test.ts (a partir de web/)
// Testes LOCAIS de regra de tela. Não provam autorização nem concorrência: isso é do servidor (5382) e das provas com sessões reais (C-244).

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import type { BinderPage } from "./binder.ts";
import {
  addPagesMessage,
  checkFreshPages,
  classifyPageFailure,
  editorRemovalBlockers,
  exclusivityLesson,
  freshCheckMessage,
  pageFailureDisablesEditing,
  pageFailureMessage,
  pageFailureRechecksAccess,
  pageSignature,
  reorderChanged,
  reorderPayload,
  structuralBlocker,
} from "./editor-binder-pages.ts";
import { type SharedPocket, sharedPageToBinderPage } from "./sharing.ts";

const EMPTY: SharedPocket = { row: 1, column: 1, kind: "empty", cardName: null, collectorNumber: null, collectorTotal: null, setCode: null, variantLabel: null, languageCode: null, imagePath: null };

function sharedPage(pageNumber: number, pockets: Partial<SharedPocket>[] = []): BinderPage {
  const grid: SharedPocket[] = [];
  for (let column = 1; column <= 3; column += 1) grid.push({ ...EMPTY, column, ...(pockets[column - 1] ?? {}) });
  return sharedPageToBinderPage({ pageNumber, pockets: grid });
}

const card = (name: string): Partial<SharedPocket> => ({ kind: "card", cardName: name, collectorNumber: "1", collectorTotal: 10, setCode: "s1", variantLabel: "Normal", languageCode: "pt" });
const reserve = (name: string): Partial<SharedPocket> => ({ kind: "reserve", cardName: name, collectorNumber: "2", collectorTotal: 10, setCode: "s1" });

test("recusas da 5382 → motivo estável; hint nunca é lido", () => {
  assert.equal(classifyPageFailure("42501", "OPERATION_RESERVED_TO_OWNER"), "reserved_to_owner");
  assert.equal(classifyPageFailure("55000", "PAGE_NOT_EMPTY"), "page_not_empty");
  assert.equal(classifyPageFailure("P0002", "PAGE_NOT_FOUND"), "page_not_found");
  assert.equal(classifyPageFailure("55000", "BINDER_MUST_KEEP_ONE_PAGE"), "keep_one_page");
  assert.equal(classifyPageFailure("P0001", "SPECIES_REFERENCES_ON_PAGE"), "species_on_page");
  assert.equal(classifyPageFailure("22023", "INVALID_PAGE_ORDER"), "order_changed");
  // Herdados da E2-1: barreira, perda de acesso, arquivada, trava ocupada.
  assert.equal(classifyPageFailure("42501", "CAPABILITY_NOT_ENABLED"), "capability_closed");
  assert.equal(classifyPageFailure("P0002", "COLLECTION_NOT_FOUND"), "access_lost");
  assert.equal(classifyPageFailure("55000", "COLLECTION_ARCHIVED"), "archived");
  assert.equal(classifyPageFailure("55P03", "lock not available"), "lock_busy");
  assert.equal(classifyPageFailure(undefined, undefined), "unknown");
  // A função de classificação só recebe código e mensagem: não há caminho para o hint.
  assert.equal(classifyPageFailure.length, 2);
  const actions = readFileSync(new URL("../../app/colecoes/compartilhada/[id]/fichario/actions.ts", import.meta.url), "utf8");
  const pagesBlock = actions.slice(actions.indexOf("E2-3A"));
  assert.ok(pagesBlock.length > 0 && !/\.hint|\.details/.test(pagesBlock), "as ações de páginas não leem hint nem details");
});

test("mensagens neutras: nada sobre o conteúdo ou o motivo da exclusividade", () => {
  const all = (["add", "remove", "reorder"] as const).flatMap((op) =>
    (["reserved_to_owner", "page_not_empty", "page_not_found", "keep_one_page", "species_on_page", "order_changed", "unknown", "access_lost", "lock_busy"] as const).map((r) => pageFailureMessage(op, r)),
  );
  for (const text of all) {
    assert.ok(!/convidad|outra cole|terceir|espécie|imagem|fixad|cadead/i.test(text), `mensagem neutra: ${text}`);
  }
  assert.equal(pageFailureMessage("remove", "species_on_page"), pageFailureMessage("remove", "reserved_to_owner"), "D2: sem gestão de referências — mesma recusa");
});

test("perda de permissão desliga a edição; recusas de página não", () => {
  for (const r of ["capability_closed", "access_lost", "archived", "not_authenticated", "disabled"] as const) assert.equal(pageFailureDisablesEditing(r), true, r);
  for (const r of ["reserved_to_owner", "page_not_empty", "page_not_found", "keep_one_page", "species_on_page", "order_changed", "lock_busy", "unknown"] as const)
    assert.equal(pageFailureDisablesEditing(r), false, r);
  assert.equal(pageFailureRechecksAccess("access_lost"), true);
  assert.equal(pageFailureRechecksAccess("reserved_to_owner"), false);
});

test("D1: só adicionar/reordenar recusados por exclusividade ensinam 'não exclusivo'", () => {
  assert.equal(exclusivityLesson("add", "reserved_to_owner"), "NOT_EXCLUSIVE");
  assert.equal(exclusivityLesson("reorder", "reserved_to_owner"), "NOT_EXCLUSIVE");
  // Remover recusa igual por conteúdo de terceiros NA PÁGINA: ambíguo.
  assert.equal(exclusivityLesson("remove", "reserved_to_owner"), null);
  for (const r of ["page_not_empty", "access_lost", "capability_closed", "lock_busy", "unknown", "order_changed"] as const) {
    assert.equal(exclusivityLesson("add", r), null);
    assert.equal(exclusivityLesson("reorder", r), null);
  }
});

test("R1: releitura confere número de páginas e conteúdo visível de cada página mostrada", () => {
  const shown = [sharedPage(1, [card("Pikachu")]), sharedPage(2), sharedPage(3, [undefined as never, reserve("Raichu")])];
  const fresh = new Map(shown.map((p) => [p.pageNumber, sharedPage(p.pageNumber, p.pageNumber === 1 ? [card("Pikachu")] : p.pageNumber === 3 ? [undefined as never, reserve("Raichu")] : [])]));
  assert.deepEqual(checkFreshPages(shown, 3, 3, fresh), { ok: true });
  assert.deepEqual(checkFreshPages(shown, 3, 4, fresh), { ok: false, reason: "count_changed" });
  assert.deepEqual(checkFreshPages(shown, 3, null, fresh), { ok: false, reason: "unreadable" });
  assert.deepEqual(checkFreshPages(shown, 3, 3, null), { ok: false, reason: "unreadable" });
  // O titular trocou as páginas 1 e 3 de lugar: o número 1 agora mostra outra coisa.
  const swapped = new Map(fresh);
  swapped.set(1, sharedPage(1, [undefined as never, reserve("Raichu")]));
  swapped.set(3, sharedPage(3, [card("Pikachu")]));
  assert.deepEqual(checkFreshPages(shown, 3, 3, swapped), { ok: false, reason: "content_changed" });
  // Limitação: duas páginas que a tela mostra iguais (vazias) continuam indistinguíveis.
  assert.equal(pageSignature(sharedPage(2)), pageSignature(sharedPage(5)));
  assert.ok(freshCheckMessage("remove", "content_changed").length > 0 && freshCheckMessage("reorder", "count_changed") !== freshCheckMessage("reorder", "content_changed"));
});

test("reordenar: permutação completa 1..N por número atual; nada é enviado fora disso", () => {
  const order = [3, 1, 2].map((n) => ({ pageNumber: n }));
  assert.deepEqual(reorderPayload(order, 3), [3, 1, 2]);
  assert.equal(reorderChanged([3, 1, 2]), true);
  assert.equal(reorderChanged([1, 2, 3]), false);
  assert.equal(reorderPayload(order, 4), null, "contagem diferente");
  assert.equal(reorderPayload([1, 1, 2].map((n) => ({ pageNumber: n })), 3), null, "repetida");
  assert.equal(reorderPayload([0, 1, 2].map((n) => ({ pageNumber: n })), 3), null, "fora do intervalo");
  assert.equal(reorderPayload([], 0), null);
});

test("remoção vista pelo EDITOR: só bloqueia o que ele vê; página aparentemente vazia não é 'vazia'", () => {
  assert.deepEqual(editorRemovalBlockers(sharedPage(2), 3), []);
  assert.deepEqual(editorRemovalBlockers(sharedPage(1), 1), ["last_page"]);
  assert.deepEqual(editorRemovalBlockers(sharedPage(2, [card("Pikachu"), reserve("Raichu")]), 3), ["cards", "reservations"]);
  const withImage: BinderPage = { ...sharedPage(2), slots: sharedPage(2).slots.map((s, i) => (i === 0 ? { ...s, image: { path: "x", focalY: 50, updatedAt: null, url: "u" } } : s)) };
  assert.deepEqual(editorRemovalBlockers(withImage, 3), ["owner_content"]);
  // O diálogo do EDITOR não afirma que a página está vazia (texto conferido no componente).
  const dialog = readFileSync(new URL("../../components/colecoes/sharing/shared-binder-pages.tsx", import.meta.url), "utf8");
  assert.ok(!/A página está vazia/.test(dialog), "sem afirmar vazio pela tela mascarada");
});

test("operações estruturais bloqueadas com Bandeja, carta na mão, seleção, confirmação ou outra escrita", () => {
  const free = { busy: false, trayCount: 0, armed: false, armedCard: false, dragging: false, confirming: false, reserving: false };
  assert.equal(structuralBlocker(free), null);
  for (const over of [{ busy: true }, { trayCount: 1 }, { armed: true }, { armedCard: true }, { dragging: true }, { confirming: true }, { reserving: true }]) {
    assert.ok(structuralBlocker({ ...free, ...over }), JSON.stringify(over));
  }
});

test("adicionar em lote: para na primeira recusa, informa o parcial, sem repetir", () => {
  assert.deepEqual(addPagesMessage(3, 3, null), { tone: "success", text: "3 páginas adicionadas no fim do fichário." });
  assert.deepEqual(addPagesMessage(1, 1, null), { tone: "success", text: "1 página adicionada no fim do fichário." });
  assert.equal(addPagesMessage(3, 0, "reserved_to_owner").text, pageFailureMessage("add", "reserved_to_owner"));
  assert.match(addPagesMessage(3, 2, "unknown").text, /^Adicionamos 2 de 3 páginas\./);
});

test("C2: uma única gravação por aplicação; nenhuma repetição automática de escrita", () => {
  const src = readFileSync(new URL("../../components/colecoes/sharing/shared-binder-pages.tsx", import.meta.url), "utf8");
  const code = src.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/.*$/gm, "");
  assert.equal(code.match(/editorReorderPages\(/g)?.length, 1, "reordenar: uma chamada");
  assert.equal(code.match(/editorRemovePage\(/g)?.length, 1, "remover: uma chamada");
  assert.equal(code.match(/editorAddPage\(/g)?.length, 1, "adicionar: uma chamada por página do lote");
  // Nenhum laço de nova tentativa em torno das escritas: o único laço com escrita é o lote de "Adicionar páginas", que para na primeira recusa.
  const addLoop = code.slice(code.indexOf("for (let i = 0; i < count; i += 1)"), code.indexOf("await syncAfter(false)"));
  assert.ok(addLoop.includes("break"), "lote de adicionar para na primeira recusa");
  assert.ok(!/retry|tentarDeNovo|setTimeout\(/i.test(code), "sem repetição automática");
});
