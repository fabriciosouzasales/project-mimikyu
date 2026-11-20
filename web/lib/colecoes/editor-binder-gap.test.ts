// V1-13 · E2-3B — abrir/fechar espaço pelo EDITOR: regras puras.
// Executar: node --experimental-strip-types --test lib/colecoes/editor-binder-gap.test.ts (a partir de web/)
// Testes LOCAIS de regra de tela. Não provam autorização, isolamento de terceiros nem concorrência:
// isso é do servidor (5385) e das provas com sessões reais (C-244).

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { gapServerPreviewMessage } from "./binder-insert.ts";
import {
  AT_BARRIER_MESSAGE,
  classifyEditorGapFailure,
  editorCanInsertGap,
  editorGapFailureDisablesEditing,
  editorGapFailureMessage,
  editorGapFailureRechecksAccess,
  gapConfirmations,
  gapInsertedMessage,
  gapOutcomeUncertain,
  gapStep,
  parseEditorGapClose,
  parseEditorGapInsert,
  parseEditorGapPreview,
} from "./editor-binder-gap.ts";

const G1 = `g1:${"a".repeat(64)}`;
const U1 = `u1:${"b".repeat(64)}`;
const row = (over: Record<string, unknown>) => [
  { outcome: "SAME_PAGE", moved_pockets: 3, moved_cards: 2, moved_reserves: 1, rows_moved: 3, row_limit: 500, pages: [2], target_page: 2, target_row: 1, target_column: 4, plan_token: G1, ...over },
];

test("prévia da 5385 → forma do titular, sem barreira, imagens nem ids", () => {
  const p = parseEditorGapPreview(row({}));
  assert.ok(p);
  assert.equal(p.outcome, "SAME_PAGE");
  assert.equal(p.movedPockets, 3);
  assert.equal(p.movedCards, 2);
  assert.equal(p.movedReserves, 1);
  assert.equal(p.movedImages, 0);
  assert.equal(p.barrier, null);
  assert.equal(p.targetSlotId, null);
  assert.equal(p.planToken, G1);
  // Executável sem token, token malformado, resultado desconhecido ou página inválida: rejeitados.
  assert.equal(parseEditorGapPreview(row({ plan_token: null })), null);
  assert.equal(parseEditorGapPreview(row({ plan_token: "g1:xyz" })), null);
  assert.equal(parseEditorGapPreview(row({ outcome: "WHATEVER" })), null);
  assert.equal(parseEditorGapPreview(row({ pages: [0] })), null);
  assert.equal(parseEditorGapPreview([]), null);
  // Não executáveis podem vir sem token.
  for (const outcome of ["BLOCKED", "OVER_LIMIT", "ALREADY_FREE", "AT_BARRIER", "NOT_FOUND"]) assert.ok(parseEditorGapPreview(row({ outcome, plan_token: null })), outcome);
});

test("estados da prévia: mesma página aplica; outra página/página nova confirma; bloqueios explicam; nada revela posição", () => {
  const step = (outcome: string) => gapStep(parseEditorGapPreview(row({ outcome, plan_token: ["SAME_PAGE", "CROSS_PAGE", "NEEDS_PAGE"].includes(outcome) ? G1 : null }))!);
  assert.equal(step("SAME_PAGE"), "run");
  assert.equal(step("CROSS_PAGE"), "confirm");
  assert.equal(step("NEEDS_PAGE"), "confirm");
  assert.equal(step("BLOCKED"), "explain");
  assert.equal(step("OVER_LIMIT"), "explain");
  assert.equal(step("ALREADY_FREE"), "already_free");
  assert.equal(step("AT_BARRIER"), "at_barrier");
  assert.equal(step("NOT_FOUND"), "not_found");
  // Texto do diálogo do titular sobre a prévia do EDITOR: BLOCKED sem barreira não cita página/linha/coluna.
  const blocked = gapServerPreviewMessage(parseEditorGapPreview(row({ outcome: "BLOCKED", plan_token: null }))!);
  assert.ok(!/página \d|linha \d|coluna \d/.test(blocked), blocked);
  assert.ok(!/fixado|imagem/i.test(AT_BARRIER_MESSAGE), "no bolso clicado, nem o tipo de barreira é dito");
});

test("confirmações enviadas são só as que a prévia mostrou", () => {
  const conf = (outcome: string) => gapConfirmations(parseEditorGapPreview(row({ outcome }))!);
  assert.deepEqual(conf("SAME_PAGE"), { crossPage: false, addPage: false });
  assert.deepEqual(conf("CROSS_PAGE"), { crossPage: true, addPage: false });
  assert.deepEqual(conf("NEEDS_PAGE"), { crossPage: true, addPage: true });
});

test("aplicação: INSERTED exige posição final e token u1; desfazer guarda tudo por posição", () => {
  const gap = { page: 2, row: 1, column: 2 };
  const r = parseEditorGapInsert([{ outcome: "INSERTED", end_page: 3, end_row: 1, end_column: 1, added_page_number: 3, moved_pockets: 5, rows_moved: 5, pages: [2, 3], undo_token: U1 }], gap);
  assert.ok(r && r.outcome === "INSERTED");
  assert.deepEqual(r.undo, { gap, end: { page: 3, row: 1, column: 1 }, undoToken: U1, addedPageNumber: 3 });
  assert.deepEqual(parseEditorGapInsert([{ outcome: "ALREADY_FREE" }], gap), { outcome: "ALREADY_FREE" });
  assert.equal(parseEditorGapInsert([{ outcome: "INSERTED", end_page: 3, end_row: 1, end_column: 1, undo_token: "u1:x" }], gap), null);
  assert.equal(parseEditorGapInsert([{ outcome: "INSERTED", end_page: null, end_row: 1, end_column: 1, undo_token: U1 }], gap), null);
  assert.deepEqual(parseEditorGapClose([{ outcome: "CLOSED", moved_pockets: 5, rows_moved: 5, page_removed: true }]), { movedPockets: 5, pageRemoved: true });
  assert.equal(parseEditorGapClose([{ outcome: "OPEN" }]), null);
  assert.equal(gapInsertedMessage(1, false), "Espaço aberto: 1 bolso avançou.");
  assert.match(gapInsertedMessage(4, true), /4 bolsos avançaram\. Uma página nova entrou no fim do fichário\./);
});

test("recusas: plano mudou, confirmação faltando, barreira, limite, desfazer expirado, exclusividade, permissão", () => {
  assert.equal(classifyEditorGapFailure("40001", "GAP_PLAN_CHANGED"), "plan_changed");
  assert.equal(classifyEditorGapFailure("55000", "GAP_CONFIRMATION_REQUIRED"), "plan_changed", "nova prévia; o hint nunca é lido");
  assert.equal(classifyEditorGapFailure("55000", "GAP_BLOCKED"), "blocked");
  assert.equal(classifyEditorGapFailure("54000", "GAP_OVER_LIMIT"), "over_limit");
  assert.equal(classifyEditorGapFailure("40001", "GAP_UNDO_EXPIRED"), "undo_expired");
  assert.equal(classifyEditorGapFailure("P0001", "GAP_INCONSISTENT"), "inconsistent");
  assert.equal(classifyEditorGapFailure("P0002", "SLOT_NOT_FOUND"), "slot_not_found");
  assert.equal(classifyEditorGapFailure("42501", "OPERATION_RESERVED_TO_OWNER"), "reserved_to_owner");
  assert.equal(classifyEditorGapFailure("42501", "CAPABILITY_NOT_ENABLED"), "capability_closed");
  assert.equal(classifyEditorGapFailure("P0002", "COLLECTION_NOT_FOUND"), "access_lost");
  assert.equal(classifyEditorGapFailure("55000", "COLLECTION_ARCHIVED"), "archived");
  assert.equal(classifyEditorGapFailure("55P03", "lock not available"), "lock_busy");
  assert.equal(classifyEditorGapFailure(undefined, undefined), "unknown");
  assert.equal(classifyEditorGapFailure.length, 2, "só código e nome da exceção");
  for (const r of ["capability_closed", "access_lost", "archived", "not_authenticated", "disabled"] as const) assert.equal(editorGapFailureDisablesEditing(r), true, r);
  for (const r of ["plan_changed", "blocked", "over_limit", "undo_expired", "inconsistent", "slot_not_found", "reserved_to_owner", "lock_busy", "unknown"] as const)
    assert.equal(editorGapFailureDisablesEditing(r), false, r);
  assert.equal(editorGapFailureRechecksAccess("access_lost"), true);
  // Só o resultado incerto conta como "posições podem ter mudado"; recusas do banco desfazem a transação.
  assert.equal(gapOutcomeUncertain("unknown"), true);
  for (const r of ["plan_changed", "blocked", "reserved_to_owner", "access_lost"] as const) assert.equal(gapOutcomeUncertain(r), false, r);
});

test("mensagens neutras: nada de posição, conteúdo de terceiros ou motivo da exclusividade", () => {
  const reasons = ["plan_changed", "blocked", "over_limit", "undo_expired", "inconsistent", "slot_not_found", "reserved_to_owner", "unknown", "access_lost", "lock_busy"] as const;
  for (const op of ["preview", "insert", "close"] as const) {
    for (const r of reasons) {
      const text = editorGapFailureMessage(op, r);
      assert.ok(!/convidad|outra cole|terceir|espécie|página \d|linha \d|coluna \d/i.test(text), `${op}/${r}: ${text}`);
    }
  }
});

test("onde a tela oferece abrir espaço (EDITOR): só antes de carta ou reserva visível desta coleção", () => {
  const base = { locked: false, regionId: null, image: null };
  assert.equal(editorCanInsertGap({ ...base, state: "OCCUPIED_MATCH" }), true);
  assert.equal(editorCanInsertGap({ ...base, state: "RESERVED_EMPTY" }), true);
  assert.equal(editorCanInsertGap({ ...base, state: "EMPTY" }), false, "bolso que parece vazio não oferece");
  assert.equal(editorCanInsertGap({ ...base, state: "OCCUPIED_MATCH", locked: true }), false, "sabido fixado");
  assert.equal(editorCanInsertGap({ ...base, state: "EMPTY", image: { path: "x", focalY: 50, updatedAt: null, url: null } }), false, "imagem do titular");
  assert.equal(editorCanInsertGap({ ...base, state: "EMPTY", regionId: "r" }), false, "mesclagem");
});

test("uma escrita por pedido; nova prévia quando o plano muda; nenhuma repetição automática", () => {
  const src = readFileSync(new URL("../../components/colecoes/sharing/shared-binder-gap.tsx", import.meta.url), "utf8");
  const code = src.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/.*$/gm, "");
  assert.equal(code.match(/editorInsertGap\(/g)?.length, 1, "abrir: uma chamada");
  assert.equal(code.match(/editorCloseGap\(/g)?.length, 1, "desfazer: uma chamada");
  // Depois de plano mudado, só leitura (prévia) e nova confirmação: a escrita não está dentro desse ramo.
  const changed = code.slice(code.indexOf('r.reason === "plan_changed"'), code.indexOf("await syncAfter(r.ok ? r.result"));
  assert.ok(changed.includes("editorPreviewGap(") && !changed.includes("editorInsertGap("), "plano mudou → só nova prévia");
  assert.ok(!/setTimeout\(|retry/i.test(code), "sem repetição automática");
  const actions = readFileSync(new URL("../../app/colecoes/compartilhada/[id]/fichario/actions.ts", import.meta.url), "utf8");
  const block = actions.slice(actions.indexOf("E2-3B"));
  assert.ok(block.length > 0 && !/\.hint|\.details/.test(block), "as ações de espaço não leem hint nem details");
});
