// V1-13 · E2-3C — organização automática pelo EDITOR: regras puras e adaptação da prévia por posição.
// Executar: node --experimental-strip-types --test lib/colecoes/editor-binder-arrange.test.ts (a partir de web/)
// Testes LOCAIS (respostas simuladas). Não provam autorização, exclusividade, isolamento de terceiros nem
// concorrência: isso é do servidor (5386) e das provas com sessões reais (C-244).

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { canConfirm, parseApply, parsePreview } from "./binder-auto-arrange.ts";
import { ARRANGE_CLOSED, finishPreview, isStale, startPreview } from "./binder-auto-arrange-view.ts";
import { FLOW_IDLE, beginApply, failureFollowUp, finishApply, finishRevalidation, startReview, startRevalidation } from "./binder-auto-arrange-flow.ts";
import {
  classifyEditorAutoArrangeFailure,
  editorArrangeDisablesEditing,
  editorArrangeFootnote,
  editorArrangeFailureText,
  editorArrangeRechecksAccess,
  editorArrangeTarget,
  parseEditorAutoArrangePreview,
} from "./editor-binder-arrange.ts";

const TOKEN = `aa1:${"c".repeat(64)}`;
const u = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const item = (ord: number, page: number, row = 1, col = ord) => ({ ord, physical_card_id: u(2000 + ord), page_number: page, row_index: row, column_index: col, card_id: u(3000 + ord), card_variant_id: u(4000 + ord) });
const ready = (over: Record<string, unknown> = {}) => ({
  status: "READY",
  insert_count: 3,
  limit: 500,
  plan_token: TOKEN,
  excluded_cards: { NO_COMPATIBLE_RESERVATION: 2 },
  unfilled_slots: { NO_CANDIDATE: 4 },
  unfilled_count: 4,
  pages: [2, 5],
  items: [item(1, 2), item(2, 2), item(3, 5, 1, 1)],
  ...over,
});

test("modalidades: Set padrão e Master Set = reservas; Pokédex = espécie; livre e desconhecida = sem organização", () => {
  assert.equal(editorArrangeTarget("STANDARD_SET"), "RESERVED");
  assert.equal(editorArrangeTarget("MASTER_SET"), "RESERVED");
  assert.equal(editorArrangeTarget("REFERENCE_POSITION"), "SPECIES");
  assert.equal(editorArrangeTarget("FREE"), null);
  assert.equal(editorArrangeTarget(null), null);
  assert.equal(editorArrangeTarget("OUTRA"), null);
});

test("slot_id: a prévia da 5386 (sem slot_id) é recusada pelo parser do titular e aceita pela adaptação por posição", () => {
  const raw = ready();
  assert.equal(parsePreview(raw), null, "o parser do titular continua exigindo slot_id (preservado)");
  const parsed = parseEditorAutoArrangePreview(raw);
  assert.ok(parsed);
  assert.equal(parsed.preview.status, "READY");
  assert.equal(parsed.preview.insertCount, 3);
  assert.deepEqual(parsed.preview.pages, [2, 5]);
  assert.deepEqual(parsed.perPage, { 2: 2, 5: 1 });
  assert.equal(parsed.preview.excludedCount, 2);
  assert.equal(parsed.preview.unfilledCount, 4);
  // Nenhum slot_id fabricado e nenhum identificador de exemplar/carta sai do parser.
  assert.deepEqual(parsed.preview.items, []);
  const text = JSON.stringify(parsed);
  for (const n of [2001, 2002, 2003, 3001, 4001]) assert.ok(!text.includes(u(n)), `id ${n} não chega à tela`);
  assert.ok(!/slot_id|slotId/.test(text), "nenhum slot_id/slotId");
  assert.equal(canConfirm(parsed.preview), true, "READY válido segue para a confirmação");
});

test("adaptação valida tudo o que a 5386 entrega (coerência do titular)", () => {
  assert.equal(parseEditorAutoArrangePreview(ready({ plan_token: "aa1:xyz" })), null, "token");
  assert.equal(parseEditorAutoArrangePreview(ready({ items: [item(1, 2), item(1, 2, 1, 2), item(3, 5)] })), null, "ord fora de sequência");
  assert.equal(parseEditorAutoArrangePreview(ready({ items: [item(1, 2), { ...item(2, 2), column_index: 1 }, item(3, 5)] })), null, "posição repetida");
  assert.equal(parseEditorAutoArrangePreview(ready({ items: [item(1, 2), { ...item(2, 2), physical_card_id: u(2001) }, item(3, 5)] })), null, "exemplar repetido (1:1)");
  assert.equal(parseEditorAutoArrangePreview(ready({ items: [item(1, 2), item(2, 2), item(3, 7)] })), null, "página fora da lista");
  assert.equal(parseEditorAutoArrangePreview(ready({ insert_count: 4 })), null, "contagem × itens");
  assert.equal(parseEditorAutoArrangePreview(ready({ pages: [5, 2] })), null, "páginas fora de ordem");
  assert.equal(parseEditorAutoArrangePreview(ready({ excluded_cards: { MOTIVO_NOVO: 1 } })), null, "motivo desconhecido");
  assert.equal(parseEditorAutoArrangePreview(ready({ unfilled_count: 3 })), null, "soma dos motivos");
  assert.equal(parseEditorAutoArrangePreview(ready({ items: [{ ...item(1, 2), physical_card_id: "x" }, item(2, 2), item(3, 5)] })), null, "id malformado");
  assert.equal(parseEditorAutoArrangePreview(null), null);
});

test("EMPTY e LIMIT_EXCEEDED: válidos, sem confirmação", () => {
  const empty = parseEditorAutoArrangePreview(ready({ status: "EMPTY", insert_count: 0, items: [], pages: [] }));
  assert.ok(empty && empty.preview.status === "EMPTY" && !canConfirm(empty.preview));
  const over = parseEditorAutoArrangePreview(ready({ status: "LIMIT_EXCEEDED", insert_count: 612, items: [], pages: [1, 2, 3] }));
  assert.ok(over && over.preview.status === "LIMIT_EXCEEDED" && !canConfirm(over.preview), "acima de 500: sem aplicar (C-225)");
  assert.equal(parseEditorAutoArrangePreview(ready({ status: "LIMIT_EXCEEDED", insert_count: 400, items: [], pages: [1] })), null);
});

test("aplicação: APPLIED, ALREADY_APPLIED e NOTHING_TO_DO (mesmo formato do titular)", () => {
  assert.deepEqual(parseApply({ status: "APPLIED", inserted: 3, event_id: 9, pages: [2, 5] }), { outcome: "APPLIED", inserted: 3, eventId: 9, pages: [2, 5] });
  assert.deepEqual(parseApply({ status: "ALREADY_APPLIED", inserted: 0, event_id: 9 }), { outcome: "ALREADY_APPLIED", inserted: 0, eventId: 9 });
  assert.deepEqual(parseApply({ status: "NOTHING_TO_DO", inserted: 0 }), { outcome: "NOTHING_TO_DO", inserted: 0 });
  assert.equal(parseApply({ status: "APPLIED", inserted: 501, event_id: 9, pages: [1] }), null);
});

test("fluxo do titular com a prévia do EDITOR: revisão, uma escrita, plano mudou → só leitura e nova confirmação", () => {
  const v0 = { activity: 0, layout: 0 };
  const loading = startPreview(ARRANGE_CLOSED, v0);
  const parsed = parseEditorAutoArrangePreview(ready())!;
  const view = finishPreview(loading, loading.status === "loading" ? loading.seq : 0, { ok: true, preview: parsed.preview });
  const review = startReview(view, v0);
  assert.ok(review && review.kind === "review");
  const begun = beginApply(review, view, v0);
  assert.ok(begun && begun.planToken === TOKEN);
  assert.equal(beginApply(begun.flow, view, v0), null, "segundo clique durante a aplicação: recusado");
  // Plano mudou (40001): nada gravado; segue para leitura (nova prévia), nunca para nova escrita.
  const changed = finishApply(begun.flow, TOKEN, { ok: false, reason: classifyEditorAutoArrangeFailure({ code: "40001", message: "AUTO_ARRANGE_PLAN_CHANGED" }), write: "not_applied" });
  assert.equal(changed.kind, "failed");
  assert.deepEqual(failureFollowUp(changed), { read: "now", cause: "plan_changed" });
  const revalidating = startRevalidation(changed);
  const after = finishRevalidation(revalidating, view, v0);
  assert.equal(after.kind, "idle", "volta ao início: exige nova revisão e nova confirmação");
  // Mudança local depois da leitura (escrita de bolso ou releitura completa): prévia desatualizada, sem revisão.
  assert.equal(isStale(view, { activity: 1, layout: 0 }), true);
  assert.equal(isStale(view, { activity: 0, layout: 1 }), true);
  assert.equal(startReview(view, { activity: 1, layout: 0 }), null);
  assert.equal(FLOW_IDLE.kind, "idle");
});

test("recusas: reservada ao titular, barreira, permissão, arquivada, limite, incerto — mensagens neutras", () => {
  assert.equal(classifyEditorAutoArrangeFailure({ code: "42501", message: "OPERATION_RESERVED_TO_OWNER" }), "not_owner");
  assert.equal(classifyEditorAutoArrangeFailure({ code: "42501", message: "CAPABILITY_NOT_ENABLED" }), "unavailable");
  assert.equal(classifyEditorAutoArrangeFailure({ code: "P0002", message: "COLLECTION_NOT_FOUND" }), "collection_not_found");
  assert.equal(classifyEditorAutoArrangeFailure({ code: "55000", message: "COLLECTION_ARCHIVED" }), "archived");
  assert.equal(classifyEditorAutoArrangeFailure({ code: "54000", message: "AUTO_ARRANGE_LIMIT_EXCEEDED" }), "limit_exceeded");
  assert.equal(classifyEditorAutoArrangeFailure({ code: "22023", message: "AUTO_ARRANGE_UNSUPPORTED_COLLECTION" }), "unsupported");
  assert.equal(classifyEditorAutoArrangeFailure(null), "uncertain");
  assert.equal(classifyEditorAutoArrangeFailure({ code: "", message: "fetch failed" }), "uncertain");
  assert.equal(editorArrangeFailureText("not_owner", "apply"), "Neste fichário, a organização automática é feita pelo titular.");
  for (const r of ["not_owner", "unavailable", "forbidden", "collection_not_found", "binder_not_found", "archived", "limit_exceeded", "plan_changed", "uncertain", "unsupported"] as const) {
    for (const phase of ["preview", "apply"] as const) {
      const text = editorArrangeFailureText(r, phase);
      assert.ok(!/convidad|outra cole|terceir|coleção dona|Reative/i.test(text), `${r}/${phase}: ${text}`);
    }
  }
  for (const r of ["unavailable", "forbidden", "collection_not_found", "binder_not_found", "archived", "not_authenticated"] as const) assert.equal(editorArrangeDisablesEditing(r), true, r);
  for (const r of ["not_owner", "plan_changed", "limit_exceeded", "lock_timeout", "uncertain", "unsupported"] as const) assert.equal(editorArrangeDisablesEditing(r), false, r);
  assert.equal(editorArrangeRechecksAccess("collection_not_found"), true);
  assert.equal(editorArrangeRechecksAccess("not_owner"), false);
});

test("uma escrita por confirmação; nenhuma repetição automática; hint/detail nunca lidos", () => {
  const hook = readFileSync(new URL("../../components/colecoes/sharing/shared-binder-arrange.tsx", import.meta.url), "utf8");
  const code = hook.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/.*$/gm, "");
  assert.equal(code.match(/editorApplyAutoArrange\(/g)?.length, 1, "uma chamada de aplicação");
  assert.ok(!/setTimeout\(|setInterval\(/.test(code), "sem repetição temporizada");
  const actions = readFileSync(new URL("../../app/colecoes/compartilhada/[id]/fichario/actions.ts", import.meta.url), "utf8");
  const block = actions.slice(actions.indexOf("E2-3C"));
  assert.ok(block.length > 0 && !/\.hint|\.details?\b/.test(block), "as ações de organização não leem hint nem detail");
  assert.equal(block.match(/rpc\(/g)?.length, 1, "um único ponto de chamada ao banco");
});

test("nota dos motivos: Pokédex do EDITOR sem 'escolha outra representante' (D4); Set/Master Set = nota do titular", () => {
  assert.ok(!/representante na Pokédex/i.test(editorArrangeFootnote("SPECIES")));
  assert.match(editorArrangeFootnote("SPECIES"), /posicione manualmente/);
  assert.equal(editorArrangeFootnote("RESERVED"), "Para resolver, posicione essas cartas manualmente ou ajuste as reservas dos bolsos.");
});
