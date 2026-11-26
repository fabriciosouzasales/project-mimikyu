// V1-13 · E3-5 — histórico compartilhado (5388). Respostas simuladas: não prova a 5388, a barreira nem sessões reais.
// Executar: node --experimental-strip-types --test lib/colecoes/shared-binder-activity.test.ts (a partir de web/)
import assert from "node:assert/strict";
import { test } from "node:test";
import { attributionByline, attributionLabel, detailFields, headlineEvent, parseActivityEvent } from "./binder-activity.ts";
import {
  SHARED_ACTIVITY_FILTERS,
  SHARED_PARTIAL_NOTE,
  classifySharedActivityFailure,
  isSharedActivityFilter,
  parseSharedActivityEvent,
  parseSharedActivityPage,
  parseSharedActivityStatus,
  sharedActivityFailureMessage,
  sharedActivityRetry,
  sharedEmptyMessage,
  sharedHistoryNote,
} from "./shared-binder-activity.ts";

const row = (over: Record<string, unknown> = {}) => ({
  event_id: 41,
  occurred_at: "2026-11-24T15:30:00Z",
  event_type: "CARD_PLACED",
  category: "CARDS",
  source: "FICHARIO",
  is_legacy: false,
  actor_role: "PARTICIPANT",
  actor_display_name: "Ana",
  item_count: 1,
  items: [{ ordinal: 1, kind: "CARD", effect: "PLACED", card_id: "c1", card_name: "Pikachu", collector_number: "25", card_set_code: "base1", variant_type_name: "Normal", to_page: 2, to_row: 1, to_col: 3 }],
  items_truncated: false,
  ...over,
});

test("linha da 5388: só os campos do contrato; autor com nome de exibição", () => {
  const e = parseSharedActivityEvent(row());
  assert.ok(e);
  assert.equal(e.id, 41);
  assert.deepEqual(e.attribution, { role: "PARTICIPANT", displayName: "Ana" });
  assert.equal(e.collectionName, null);
  assert.equal(e.binderName, null);
  assert.deepEqual(e.summary, {});
  assert.equal(headlineEvent(e), "Pikachu colocada");
  assert.equal(attributionByline(e), "por Ana");
});

test("campos fora do contrato nunca chegam à tela (summary, detail, ids, nomes gravados)", () => {
  const e = parseSharedActivityEvent(
    row({
      summary: { storage_container_name: "Caixa secreta" },
      collection_name: "Outra coleção",
      binder_name: "Fichário gravado",
      actor_user_id: "u-1",
      owner_user_id: "u-2",
      items: [{ ordinal: 1, kind: "CARD", effect: "PLACED", card_name: "Pikachu", to_page: 2, to_row: 1, to_col: 3, detail: { physical_card_id: "p-1", condition_code: "NM" } }],
    }),
  );
  assert.ok(e);
  const dump = JSON.stringify(e) + JSON.stringify(detailFields(e));
  for (const secret of ["Caixa secreta", "Outra coleção", "Fichário gravado", "u-1", "u-2", "p-1", "NM"]) assert.ok(!dump.includes(secret), secret);
  assert.equal(e.items[0]?.detail, null);
});

test("autor: nome → papel → nada inferido", () => {
  assert.equal(attributionLabel({ role: "OWNER", displayName: "Fabrício" }, false), "Fabrício");
  assert.equal(attributionLabel({ role: "OWNER", displayName: null }, false), "Titular");
  assert.equal(attributionLabel({ role: "PARTICIPANT", displayName: null }, false), "Participante");
  assert.equal(attributionLabel({ role: null, displayName: null }, true), "Não registrado (anterior ao histórico)");
  assert.equal(attributionLabel({ role: null, displayName: null }, false), "Não identificado");
  // Sem papel, um nome que viesse é ignorado (o contrato só nomeia quem tem papel).
  const legacy = parseSharedActivityEvent(row({ event_type: "LEGACY_CATALOG_INCORPORATION", source: "LEGADO", is_legacy: true, actor_role: null, actor_display_name: "X" }));
  assert.ok(legacy);
  assert.deepEqual(legacy.attribution, { role: null, displayName: null });
  assert.equal(attributionByline(legacy), null);
  const noName = parseSharedActivityEvent(row({ actor_display_name: "   " }));
  assert.equal(noName && attributionByline(noName), "por Participante");
});

test("detalhes: tipo e autor no participante; titular sem autoria atribuída", () => {
  const shared = parseSharedActivityEvent(row({ actor_role: "OWNER", actor_display_name: null }));
  assert.ok(shared);
  const f = Object.fromEntries(detailFields(shared).map((x) => [x.label, x.value]));
  assert.equal(f.Por, "Titular");
  assert.equal(f.Tipo, "Cartas");
  assert.equal(f["Coleção"], undefined);
  const owner = parseActivityEvent({ ...row(), collection_name: "Base", actor_role: undefined });
  assert.ok(owner);
  assert.equal(owner.attribution, undefined);
  const o = Object.fromEntries(detailFields(owner).map((x) => [x.label, x.value]));
  assert.equal(o.Por, undefined, "a 5269 não comprova o autor");
  assert.equal(o.Tipo, undefined);
  assert.equal(attributionByline(owner), null);
});

test("formato inesperado: a página inteira é recusada", () => {
  assert.equal(parseSharedActivityEvent(row({ actor_role: "EDITOR" })), null);
  assert.equal(parseSharedActivityEvent(row({ item_count: 0 })), null, "contagem menor que os itens");
  assert.equal(parseSharedActivityEvent(row({ items: null })), null);
  assert.equal(parseSharedActivityEvent(row({ occurred_at: "ontem" })), null);
  assert.equal(parseSharedActivityPage([row(), row({ event_id: "x" })]), null);
  assert.deepEqual(parseSharedActivityPage(null), []);
  assert.deepEqual(parseSharedActivityPage([]), []);
  assert.equal(parseSharedActivityPage({}), null);
});

test("contagem e truncamento só dos itens visíveis", () => {
  const items = Array.from({ length: 50 }, (_, i) => ({ ordinal: i + 1, kind: "CARD", effect: "PLACED", card_name: `C${i}`, to_page: 1, to_row: 1, to_col: 1 }));
  const e = parseSharedActivityEvent(row({ item_count: 63, items, items_truncated: true }));
  assert.ok(e && e.truncated && e.itemCount === 63 && e.items.length === 50);
  assert.equal(headlineEvent(e), "63 cartas colocadas");
});

test("estado: zero linhas ≠ vazio; booleanos obrigatórios", () => {
  assert.equal(parseSharedActivityStatus([]), null);
  assert.equal(parseSharedActivityStatus(null), null);
  assert.deepEqual(parseSharedActivityStatus([{ has_binder: true, history_may_be_partial: true }]), { hasBinder: true, mayBePartial: true });
  assert.equal(parseSharedActivityStatus([{ has_binder: "sim" }]), undefined);
  assert.equal(sharedHistoryNote({ hasBinder: true, mayBePartial: true }), SHARED_PARTIAL_NOTE);
  assert.equal(sharedHistoryNote({ hasBinder: true, mayBePartial: false }), null);
  assert.equal(sharedHistoryNote(null), null);
  assert.equal(SHARED_PARTIAL_NOTE, "O histórico compartilhado pode não incluir atividades anteriores à disponibilização deste recurso.");
});

test("filtros: só categorias com eventos permitidos (sem Fichário)", () => {
  assert.deepEqual(SHARED_ACTIVITY_FILTERS.map((f) => f.key), ["ALL", "CARDS", "RESERVATIONS", "LOCKS", "PAGES", "CATALOG"]);
  assert.ok(isSharedActivityFilter("PAGES") && !isSharedActivityFilter("BINDER") && !isSharedActivityFilter("x"));
});

test("estados distintos: vazio, indisponível, acesso perdido, sem fichário, falha", () => {
  const empty = sharedEmptyMessage("ALL");
  assert.ok(!/nenhuma atividade registrada|nada aconteceu|ainda não houve/i.test(empty), "vazio não é prova de ausência");
  assert.match(sharedEmptyMessage("CARDS"), /Cartas/);
  const messages = (["unavailable", "access_lost", "no_binder", "unknown", "not_authenticated"] as const).map(sharedActivityFailureMessage);
  assert.equal(new Set(messages).size, messages.length);
  assert.ok(!messages.includes(empty));
  assert.equal(sharedActivityRetry("unknown"), true);
  for (const r of ["unavailable", "access_lost", "no_binder", "not_authenticated"] as const) assert.equal(sharedActivityRetry(r), false, r);
  assert.equal(classifySharedActivityFailure("PGRST202"), "unavailable");
  assert.equal(classifySharedActivityFailure("28000"), "not_authenticated");
  assert.equal(classifySharedActivityFailure("22023"), "invalid");
  assert.equal(classifySharedActivityFailure("XX000"), "unknown");
});
