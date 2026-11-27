// V1-13 · E2-3D — novidades do Catálogo pelo EDITOR: regras puras e campos protegidos em branco.
// Executar: node --experimental-strip-types --test lib/colecoes/editor-binder-catalog.test.ts (a partir de web/)
// Testes LOCAIS com respostas simuladas. Não provam autorização, exclusividade, isolamento de terceiros nem
// concorrência: isso é do servidor (5387) e das provas com sessões reais (C-244).

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { affectedPages, canApplyPreview, parseCatalogApply, parseCatalogPreview, planItemMessage, previewSummaryMessage } from "./binder-catalog.ts";
import {
  catalogApplyShifted,
  catalogOutcomeUncertain,
  classifyEditorCatalogFailure,
  editorCatalogAvailable,
  editorCatalogFailureMessage,
  noveltiesFromEditorPreview,
  noveltyNamesFrom,
  validEditorCatalogKeys,
} from "./editor-binder-catalog.ts";

const RC1 = `rc1:${"d".repeat(64)}`;
const C1 = "11111111-1111-4111-8111-111111111111";
const C2 = "22222222-2222-4222-8222-222222222222";
const V1 = "33333333-3333-4333-8333-333333333333";
const key1 = `${C1}:${V1}`;
const key2 = `${C2}:*`;

/** Prévia como a 5387 a entrega ao EDITOR: fichário, capacidade, livres e barreira de terceiros em branco. */
function editorRows(over: Record<string, unknown> = {}, items: Record<string, unknown>[] | null = null) {
  const header = {
    row_kind: "HEADER", outcome: "READY", reason: null, layout_id: null, total_items: 2, total_rows_moved: 3, row_limit: 500, item_limit: 100,
    requires_cross_page: true, requires_add_page: false, pages_added: 0, added_page_numbers: [], capacity_before: null, capacity_after: null, free_pockets_after: null, plan_token: RC1, ...over,
  };
  const rows = items ?? [
    { row_kind: "ITEM", step_no: 1, item_key: key1, card_id: C1, variant_type_id: V1, kind: "SHIFT", target_page: 2, target_row: 1, target_column: 3, end_page: 3, end_row: 1, end_column: 1, pockets_moved: 3, rows_moved: 3, other_reserves_moved: 0, crosses_page: true, adds_page: false, barrier_page: null, barrier_row: null, barrier_column: null, barrier_kind: null, layout_id: null },
    { row_kind: "ITEM", step_no: 2, item_key: key2, card_id: C2, variant_type_id: null, kind: "IN_PLACE", target_page: 4, target_row: 2, target_column: 2, pockets_moved: 0, rows_moved: 0, other_reserves_moved: 0, crosses_page: false, adds_page: false, barrier_page: null, barrier_row: null, barrier_column: null, barrier_kind: null, layout_id: null },
  ];
  return [header, ...rows];
}

test("só Master Set", () => {
  assert.equal(editorCatalogAvailable("MASTER_SET"), true);
  for (const p of ["STANDARD_SET", "REFERENCE_POSITION", "FREE", null]) assert.equal(editorCatalogAvailable(p), false, String(p));
});

test("campos protegidos em branco: o parser do titular aceita e NÃO os preenche", () => {
  const p = parseCatalogPreview(editorRows());
  assert.ok(p);
  assert.equal(p.outcome, "READY");
  assert.equal(p.capacityBefore, null);
  assert.equal(p.capacityAfter, null);
  assert.equal(p.freePocketsAfter, null);
  assert.ok(!("layoutId" in p), "id do fichário nem é lido");
  assert.equal(p.items[0]?.barrier, null);
  assert.deepEqual(affectedPages(p), [2, 3, 4]);
  // Barreira de terceiros: posição em branco, tipo presente → a tela não mostra barreira nenhuma (nem o tipo, nem a posição).
  const blocked = parseCatalogPreview(
    editorRows({ outcome: "BLOCKED", plan_token: null, requires_cross_page: false }, [
      { row_kind: "ITEM", step_no: 1, item_key: key1, card_id: C1, variant_type_id: V1, kind: "BLOCKED", barrier_page: null, barrier_row: null, barrier_column: null, barrier_kind: "LOCKED" },
    ]),
  );
  assert.ok(blocked && blocked.items[0]?.barrier === null);
  const text = planItemMessage(blocked.items[0]!);
  assert.ok(!/página \d|linha \d|coluna \d/.test(text), text);
  assert.ok(!canApplyPreview(blocked, { crossPage: true, addPage: true }), "BLOCKED nunca aplica");
});

test("confirmações e limites: outra página exige a marcação; OVER_LIMIT não aplica", () => {
  const p = parseCatalogPreview(editorRows())!;
  assert.equal(canApplyPreview(p, { crossPage: false, addPage: false }), false, "outra página sem confirmação");
  assert.equal(canApplyPreview(p, { crossPage: true, addPage: false }), true);
  const needsPage = parseCatalogPreview(editorRows({ requires_add_page: true, pages_added: 1, added_page_numbers: [9] }))!;
  assert.equal(canApplyPreview(needsPage, { crossPage: true, addPage: false }), false, "página nova sem confirmação");
  assert.equal(canApplyPreview(needsPage, { crossPage: true, addPage: true }), true);
  const over = parseCatalogPreview(editorRows({ outcome: "OVER_LIMIT", reason: "ITEM_LIMIT", plan_token: null }))!;
  assert.equal(canApplyPreview(over, { crossPage: true, addPage: true }), false);
  assert.match(previewSummaryMessage(over), /o limite é 100/);
  const many = (n: number) => Array.from({ length: n }, (_, i) => `00000000-0000-4000-8000-${String(i).padStart(12, "0")}:*`);
  assert.equal(validEditorCatalogKeys(many(100)), true, "até 100");
  assert.equal(validEditorCatalogKeys(many(101)), false, "acima de 100: nem é enviado");
  assert.equal(validEditorCatalogKeys([key1, key1]), false, "repetida");
  assert.equal(validEditorCatalogKeys([]), false);
  assert.equal(validEditorCatalogKeys([key1, key2]), true);
});

test("lista a partir da prévia sem seleção + nomes da leitura de participante; 'já no fichário' desconhecido (null), nunca falso", () => {
  const p = parseCatalogPreview(editorRows())!;
  const names = noveltyNamesFrom([
    { cardId: C1, variantTypeId: V1, cardName: "Chi-Yu", collectorNumber: "059", finishName: "Holo Reversa" },
    { cardId: C2, variantTypeId: V1, cardName: "Mew", collectorNumber: "151", finishName: "Normal" },
  ]);
  const state = noveltiesFromEditorPreview(p, names);
  assert.ok(state.eligible);
  assert.equal(state.count, 2);
  assert.deepEqual(state.items.map((i) => [i.itemKey, i.cardName, i.collectorNumber, i.variantTypeName, i.placedInBinder]), [
    [key1, "Chi-Yu", "059", "Holo Reversa", null],
    [key2, "Mew", "151", null, null],
  ]);
  // "Já no fichário" é desconhecido para o EDITOR — nunca afirmado como "não está".
  assert.ok(state.items.every((i) => i.placedInBinder === null));
  const unnamed = noveltiesFromEditorPreview(p, new Map());
  assert.ok(unnamed.eligible && unnamed.items.every((i) => i.cardName === "Carta"), "sem nome: 'Carta', nada inventado");
  assert.deepEqual(noveltiesFromEditorPreview(parseCatalogPreview(editorRows({ outcome: "NOT_ELIGIBLE", plan_token: null }, []))!, names), { eligible: false, reason: "OTHER" });
});

test("recusas: reservada ao titular, barreira, permissão, plano mudou, confirmação faltando, limite, incerto", () => {
  const r = classifyEditorCatalogFailure("42501", "OPERATION_RESERVED_TO_OWNER");
  assert.equal(r.message, "Neste fichário, as novidades do Catálogo são incorporadas pelo titular.");
  assert.equal(r.disables, false);
  assert.equal(classifyEditorCatalogFailure("40001", "RECONCILE_PLAN_CHANGED").reason, "plan_changed");
  assert.equal(classifyEditorCatalogFailure("55000", "RECONCILE_CONFIRMATION_REQUIRED").reason, "plan_changed", "o hint nunca é lido");
  assert.equal(classifyEditorCatalogFailure("54000", "RECONCILE_OVER_LIMIT").reason, "over_limit");
  assert.equal(classifyEditorCatalogFailure("55000", "RECONCILE_BLOCKED").reason, "blocked");
  assert.equal(classifyEditorCatalogFailure("22023", "SELECTION_INVALID").reason, "selection_invalid");
  assert.equal(classifyEditorCatalogFailure("P0001", "RECONCILE_INCONSISTENT").reason, "inconsistent");
  for (const [code, msg] of [["42501", "CAPABILITY_NOT_ENABLED"], ["P0002", "COLLECTION_NOT_FOUND"], ["P0002", "BINDER_NOT_FOUND"], ["55000", "COLLECTION_ARCHIVED"], ["28000", "not_authenticated"]] as const) {
    assert.equal(classifyEditorCatalogFailure(code, msg).disables, true, msg);
  }
  assert.equal(classifyEditorCatalogFailure("P0002", "COLLECTION_NOT_FOUND").recheck, true);
  assert.equal(classifyEditorCatalogFailure(undefined, "fetch failed").reason, "unknown");
  assert.equal(catalogOutcomeUncertain("unknown"), true);
  assert.equal(catalogOutcomeUncertain("plan_changed"), false);
  assert.equal(classifyEditorCatalogFailure.length, 2, "só código e nome da exceção");
  for (const reason of ["blocked", "not_eligible", "reference_missing", "not_found", "plan_changed", "over_limit", "unknown"] as const) {
    assert.ok(!/convidad|outra cole|terceir|página \d/i.test(editorCatalogFailureMessage(reason)), reason);
  }
});

test("aplicação: APPLIED com ou sem deslocamento; ALREADY_APPLIED e NOTHING_TO_DO", () => {
  const shifted = parseCatalogApply([{ outcome: "APPLIED", items_applied: 2, reservations_created: 2, reservations_upgraded: 0, pockets_moved: 3, rows_moved: 3, pages_added: 0, added_page_numbers: [] }])!;
  assert.equal(catalogApplyShifted(shifted), true, "deslocou: fixação aprendida volta a UNKNOWN");
  const inPlace = parseCatalogApply([{ outcome: "APPLIED", items_applied: 1, reservations_created: 1, reservations_upgraded: 0, pockets_moved: 0, rows_moved: 0, pages_added: 0, added_page_numbers: [] }])!;
  assert.equal(catalogApplyShifted(inPlace), false, "só reserva no lugar: nada é invalidado");
  assert.equal(catalogApplyShifted(parseCatalogApply([{ outcome: "APPLIED", items_applied: 1, reservations_created: 1, reservations_upgraded: 0, pockets_moved: 0, rows_moved: 0, pages_added: 1, added_page_numbers: [9] }])!), true);
  assert.equal(parseCatalogApply([{ outcome: "ALREADY_APPLIED", items_applied: 0, reservations_created: 0, reservations_upgraded: 0, pockets_moved: 0, rows_moved: 0, pages_added: 0, added_page_numbers: [] }])?.outcome, "ALREADY_APPLIED");
  assert.equal(parseCatalogApply([{ outcome: "NOTHING_TO_DO", items_applied: 0, reservations_created: 0, reservations_upgraded: 0, pockets_moved: 0, rows_moved: 0, pages_added: 0, added_page_numbers: [] }])?.outcome, "NOTHING_TO_DO");
});

test("uma escrita por confirmação; sem repetição; hint/details nunca lidos; nenhuma leitura ao abrir o fichário", () => {
  const hook = readFileSync(new URL("../../components/colecoes/sharing/shared-binder-catalog.tsx", import.meta.url), "utf8");
  const code = hook.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/.*$/gm, "");
  assert.equal(code.match(/editorApplyCatalog\(/g)?.length, 1, "uma chamada de incorporação");
  assert.ok(!/setTimeout\(|setInterval\(|useEffect\(/.test(code), "sem repetição nem leitura automática");
  const actions = readFileSync(new URL("../../app/colecoes/compartilhada/[id]/fichario/actions.ts", import.meta.url), "utf8");
  // O bloco das novidades termina onde começa o das referências de espécie (E3-6 / F2), se houver.
  const end = actions.indexOf("E3-6 / F2");
  const block = actions.slice(actions.indexOf("E2-3D"), end > 0 ? end : undefined);
  assert.ok(block.length > 0 && !/\.hint|\.details?\b/.test(block), "as ações de novidades não leem hint nem details");
  assert.equal(block.match(/rpc\(/g)?.length, 2, "prévia e incorporação: um ponto de chamada cada");
});
