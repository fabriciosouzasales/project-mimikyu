// Organização automática do fichário (P2) — regras puras.
// Executar: node --experimental-strip-types --test lib/colecoes/binder-auto-arrange.test.ts (a partir de web/)
//
// Fixtures SINTÉTICAS no formato das canônicas 5343/5344. Não são evidência de
// execução no LIVE: nenhuma RPC é chamada aqui.

import assert from "node:assert/strict";
import { test } from "node:test";
import {
  AUTO_ARRANGE_LIMIT,
  EXCLUDED_CARD_REASONS,
  REASONS_FOOTNOTE,
  UNFILLED_SLOT_REASONS,
  type AutoArrangeFailure,
  applyResultMessage,
  autoArrangeEntry,
  canConfirm,
  classifyAutoArrangeFailure,
  confirmLabel,
  confirmationText,
  entryHint,
  excludedCardReasonLabel,
  excludedLines,
  excludedPhrase,
  failureMessage,
  failureNextStep,
  interpretRevalidation,
  isPlanToken,
  needsFreshPreview,
  pagesPhrase,
  parseApply,
  parsePreview,
  previewSummary,
  revalidationMessage,
  unfilledLines,
  unfilledPhrase,
  unfilledSlotReasonLabel,
  writeDefinitelyNotApplied,
} from "./binder-auto-arrange.ts";

const TOKEN = `aa1:${"0123456789abcdef".repeat(4)}`;
const TOKEN_2 = `aa1:${"fedcba9876543210".repeat(4)}`;

function u(n: number): string {
  return `00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`;
}

function item(ord: number, page: number, row = 1, col = ord): Record<string, unknown> {
  return {
    ord,
    slot_id: u(1000 + ord),
    physical_card_id: u(2000 + ord),
    page_number: page,
    row_index: row,
    column_index: col,
    card_id: u(3000 + ord),
    card_variant_id: u(4000 + ord),
  };
}

function ready(over: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    status: "READY",
    insert_count: 3,
    limit: 500,
    plan_token: TOKEN,
    excluded_cards: { COMPETING_CANDIDATES: 2, NO_COMPATIBLE_RESERVATION: 1 },
    unfilled_slots: { NO_CANDIDATE: 4, COMPETING_CANDIDATES: 1 },
    unfilled_count: 5,
    pages: [1, 3],
    items: [item(1, 1), item(2, 1), item(3, 3)],
    ...over,
  };
}

const EMPTY = {
  status: "EMPTY",
  insert_count: 0,
  limit: 500,
  plan_token: TOKEN,
  excluded_cards: {},
  unfilled_slots: { NO_CANDIDATE: 31 },
  unfilled_count: 31,
  pages: [],
  items: [],
};

const LIMIT = {
  status: "LIMIT_EXCEEDED",
  insert_count: 501,
  limit: 500,
  plan_token: TOKEN,
  excluded_cards: {},
  unfilled_slots: {},
  unfilled_count: 0,
  pages: [1, 2, 3, 4, 5, 6, 7, 8],
  items: [],
};

// ---------------------------------------------------------------------------
// Token
// ---------------------------------------------------------------------------

test("token: só aa1 + 64 hex minúsculos (mesmo padrão da 5344)", () => {
  assert.equal(isPlanToken(TOKEN), true);
  assert.equal(isPlanToken(`aa1:${"A".repeat(64)}`), false); // maiúsculas
  assert.equal(isPlanToken(`aa1:${"0".repeat(63)}`), false);
  assert.equal(isPlanToken(`aa1:${"0".repeat(65)}`), false);
  assert.equal(isPlanToken(`v1:${"0".repeat(64)}`), false);
  assert.equal(isPlanToken(` ${TOKEN}`), false);
  assert.equal(isPlanToken(null), false);
  assert.equal(isPlanToken(42), false);
});

// ---------------------------------------------------------------------------
// Elegibilidade
// ---------------------------------------------------------------------------

test("elegibilidade: Set e Master Set da proprietária, ativa e editável", () => {
  const base = { hasBinder: true, active: true, editable: true, role: "OWNER" as const };
  assert.deepEqual(autoArrangeEntry({ ...base, kind: "SET" }), { visible: true, enabled: true });
  assert.deepEqual(autoArrangeEntry({ ...base, kind: "MASTER_SET" }), { visible: true, enabled: true });
  assert.equal(entryHint(autoArrangeEntry({ ...base, kind: "SET" })), null);
});

test("elegibilidade: convidada aparece indisponível com motivo; arquivada e só leitura também", () => {
  const guest = autoArrangeEntry({ hasBinder: true, active: true, editable: true, role: "GUEST", kind: "SET" });
  assert.deepEqual(guest, { visible: true, enabled: false, reason: "NOT_BINDER_OWNER" });
  assert.match(entryHint(guest) ?? "", /coleção dona/);
  const archived = autoArrangeEntry({ hasBinder: true, active: false, editable: false, role: "OWNER", kind: "MASTER_SET" });
  assert.deepEqual(archived, { visible: true, enabled: false, reason: "ARCHIVED" });
  assert.match(entryHint(archived) ?? "", /arquivada/);
  const readOnly = autoArrangeEntry({ hasBinder: true, active: true, editable: false, role: "OWNER", kind: "SET" });
  assert.deepEqual(readOnly, { visible: true, enabled: false, reason: "READ_ONLY" });
});

test("elegibilidade: Pokédex, Livre, desconhecido e sem fichário não mostram a ação", () => {
  const base = { hasBinder: true, active: true, editable: true, role: "OWNER" as const };
  for (const kind of ["POKEDEX", "FREE", "UNKNOWN"]) assert.deepEqual(autoArrangeEntry({ ...base, kind }), { visible: false }, kind);
  assert.deepEqual(autoArrangeEntry({ ...base, kind: "SET", hasBinder: false }), { visible: false });
  assert.deepEqual(autoArrangeEntry({ ...base, kind: "SET", role: null }), { visible: false });
  // Tipo não suportado tem precedência sobre convidada (mesma ordem da 5343).
  assert.deepEqual(autoArrangeEntry({ ...base, kind: "POKEDEX", role: "GUEST" }), { visible: false });
});

// ---------------------------------------------------------------------------
// Prévia: estados válidos
// ---------------------------------------------------------------------------

test("prévia READY: campos, contagens e itens do contrato", () => {
  const p = parsePreview(ready());
  assert.ok(p);
  assert.equal(p.status, "READY");
  assert.equal(p.insertCount, 3);
  assert.equal(p.limit, AUTO_ARRANGE_LIMIT);
  assert.equal(p.planToken, TOKEN); // token preservado como recebido
  assert.deepEqual(p.pages, [1, 3]);
  assert.equal(p.items.length, 3);
  assert.deepEqual(p.items[2], { ord: 3, slotId: u(1003), physicalCardId: u(2003), page: 3, row: 1, col: 3, cardId: u(3003), cardVariantId: u(4003) });
  assert.equal(p.excludedCount, 3);
  assert.equal(p.unfilledCount, 5);
  assert.equal(canConfirm(p), true);
  const s = previewSummary(p);
  assert.equal(s.headline, "3 cartas prontas para o seu lugar");
  assert.match(s.detail, /Entram em 2 páginas \(páginas 1 e 3\)/);
  assert.match(s.detail, /Nenhuma carta é substituída, movida ou retirada/);
  assert.equal(confirmLabel(p), "Posicionar 3 cartas");
  assert.match(confirmationText(p), /^3 cartas serão colocadas em 2 páginas\./);
  assert.equal(unfilledPhrase(p), "5 bolsos reservados continuam vazios");
  assert.equal(excludedPhrase(p), "3 cartas ficam de fora");
});

test("prévia READY com uma carta: singular", () => {
  const p = parsePreview(ready({ insert_count: 1, items: [item(1, 4)], pages: [4], excluded_cards: {}, unfilled_slots: {}, unfilled_count: 0 }));
  assert.ok(p);
  assert.equal(previewSummary(p).headline, "1 carta pronta para o seu lugar");
  assert.equal(confirmLabel(p), "Posicionar 1 carta");
  assert.equal(unfilledPhrase(p), null);
  assert.equal(excludedPhrase(p), null);
});

test("prévia READY no limite exato (500) ainda pode ser confirmada", () => {
  const items = Array.from({ length: 500 }, (_, i) => item(i + 1, Math.floor(i / 9) + 1, 1, (i % 9) + 1));
  const pages = [...new Set(items.map((i) => i.page_number as number))];
  const p = parsePreview(ready({ insert_count: 500, items, pages }));
  assert.ok(p);
  assert.equal(canConfirm(p), true);
  assert.equal(confirmLabel(p), "Posicionar 500 cartas");
});

test("prévia EMPTY: indicador de nenhuma alteração, sem confirmação", () => {
  const p = parsePreview(EMPTY);
  assert.ok(p);
  assert.equal(p.status, "EMPTY");
  assert.equal(canConfirm(p), false);
  assert.equal(previewSummary(p).headline, "Nenhuma alteração");
  assert.equal(unfilledPhrase(p), "31 bolsos reservados continuam vazios");
  assert.deepEqual(unfilledLines(p), [{ key: "NO_CANDIDATE", label: "Nenhuma cópia guardada neste fichário", count: 31 }]);
});

test("prévia LIMIT_EXCEEDED: 501 cartas, itens vazios, páginas presentes, sem confirmação", () => {
  const p = parsePreview(LIMIT);
  assert.ok(p);
  assert.equal(p.status, "LIMIT_EXCEEDED");
  assert.equal(p.items.length, 0);
  assert.equal(p.pages.length, 8);
  assert.equal(canConfirm(p), false);
  const s = previewSummary(p);
  assert.equal(s.headline, "501 cartas — o limite é 500 por vez");
  assert.match(s.detail, /Nada será posicionado agora/);
});

// ---------------------------------------------------------------------------
// Prévia: contratos inválidos (nunca adivinha)
// ---------------------------------------------------------------------------

test("prévia inválida: formato, estado, token e campos obrigatórios", () => {
  assert.equal(parsePreview(null), null);
  assert.equal(parsePreview([]), null);
  assert.equal(parsePreview("READY"), null);
  assert.equal(parsePreview(ready({ status: "OK" })), null);
  assert.equal(parsePreview(ready({ plan_token: "aa1:xyz" })), null);
  assert.equal(parsePreview(ready({ plan_token: undefined })), null);
  assert.equal(parsePreview(ready({ insert_count: "3" })), null);
  assert.equal(parsePreview(ready({ insert_count: -1 })), null);
  assert.equal(parsePreview(ready({ limit: 0 })), null);
  assert.equal(parsePreview(ready({ pages: "1,3" })), null);
  assert.equal(parsePreview(ready({ items: null })), null);
});

test("prévia inválida: coerência estado × contagem × itens", () => {
  assert.equal(parsePreview(ready({ insert_count: 2 })), null); // 3 itens ≠ 2
  assert.equal(parsePreview(ready({ insert_count: 0, items: [], pages: [] })), null); // READY vazio
  assert.equal(parsePreview({ ...EMPTY, insert_count: 1 }), null);
  assert.equal(parsePreview({ ...EMPTY, items: [item(1, 1)], pages: [1] }), null);
  assert.equal(parsePreview({ ...LIMIT, insert_count: 500 }), null); // não excede
  assert.equal(parsePreview({ ...LIMIT, items: [item(1, 1)] }), null); // LIMIT nunca traz itens
  assert.equal(parsePreview({ ...LIMIT, pages: [] }), null);
  const tooMany = Array.from({ length: 501 }, (_, i) => item(i + 1, 1, 1, i + 1));
  assert.equal(parsePreview(ready({ insert_count: 501, items: tooMany, pages: [1] })), null); // READY acima do limite
});

test("prévia inválida: itens, páginas e 1:1 estrito", () => {
  assert.equal(parsePreview(ready({ items: [item(1, 1), item(3, 1), item(2, 3)] })), null); // ord fora de sequência
  assert.equal(parsePreview(ready({ items: [item(1, 1), { ...item(2, 1), slot_id: u(1001) }, item(3, 3)] })), null); // bolso repetido
  assert.equal(parsePreview(ready({ items: [item(1, 1), { ...item(2, 1), physical_card_id: u(2001) }, item(3, 3)] })), null); // exemplar repetido
  assert.equal(parsePreview(ready({ items: [item(1, 1), item(2, 1), item(3, 9)] })), null); // página fora de `pages`
  assert.equal(parsePreview(ready({ pages: [3, 1] })), null); // fora de ordem
  assert.equal(parsePreview(ready({ pages: [1, 1, 3] })), null); // repetida
  assert.equal(parsePreview(ready({ pages: [1, 3, 5] })), null); // página sem inserção em READY
  assert.equal(parsePreview(ready({ items: [item(1, 1), item(2, 1), { ...item(3, 3), slot_id: "não-é-uuid" }] })), null);
  assert.equal(parsePreview(ready({ items: [item(1, 1), item(2, 1), { ...item(3, 3), row_index: 0 }] })), null);
});

test("prévia inválida: motivos desconhecidos ou contagens incoerentes", () => {
  assert.equal(parsePreview(ready({ excluded_cards: { NOVO_MOTIVO: 1 } })), null);
  assert.equal(parsePreview(ready({ unfilled_slots: { NO_COMPATIBLE_RESERVATION: 5 } })), null); // motivo de exemplar em bolso
  assert.equal(parsePreview(ready({ excluded_cards: { COMPETING_CANDIDATES: 0 } })), null);
  assert.equal(parsePreview(ready({ excluded_cards: [] })), null);
  assert.equal(parsePreview(ready({ unfilled_count: 4 })), null); // soma 5 ≠ 4
});

// ---------------------------------------------------------------------------
// Textos de motivo
// ---------------------------------------------------------------------------

test("motivos: todos com texto de colecionador, na ordem do contrato, sem códigos", () => {
  for (const r of EXCLUDED_CARD_REASONS) assert.doesNotMatch(excludedCardReasonLabel(r), /[A-Z]{3,}_/, r);
  for (const r of UNFILLED_SLOT_REASONS) assert.doesNotMatch(unfilledSlotReasonLabel(r), /[A-Z]{3,}_/, r);
  const p = parsePreview(ready({ excluded_cards: { NO_COMPATIBLE_RESERVATION: 1, INACTIVE_VARIANT: 2, COMPETING_CANDIDATES: 3, MULTIPLE_DESTINATIONS: 4 } }));
  assert.ok(p);
  assert.deepEqual(excludedLines(p).map((l) => l.key), ["INACTIVE_VARIANT", "NO_COMPATIBLE_RESERVATION", "MULTIPLE_DESTINATIONS", "COMPETING_CANDIDATES"]);
  assert.deepEqual(unfilledLines(p).map((l) => [l.key, l.count]), [["NO_CANDIDATE", 4], ["COMPETING_CANDIDATES", 1]]);
  assert.doesNotMatch(REASONS_FOOTNOTE, /[A-Z]{3,}_/);
});

test("páginas: frase curta", () => {
  assert.equal(pagesPhrase([]), "");
  assert.equal(pagesPhrase([4]), "página 4");
  assert.equal(pagesPhrase([2, 3]), "páginas 2 e 3");
  assert.equal(pagesPhrase([1, 2, 5]), "páginas 1, 2 e 5");
  assert.equal(pagesPhrase([1, 2, 3, 4, 5, 6, 7]), "7 páginas");
});

// ---------------------------------------------------------------------------
// Confirmação: resultados
// ---------------------------------------------------------------------------

test("resultado APPLIED, ALREADY_APPLIED e NOTHING_TO_DO", () => {
  const applied = parseApply({ status: "APPLIED", inserted: 148, event_id: 422, pages: [1, 2, 5] });
  assert.deepEqual(applied, { outcome: "APPLIED", inserted: 148, eventId: 422, pages: [1, 2, 5] });
  assert.equal(applyResultMessage(applied!), "148 cartas posicionadas em 3 páginas.");
  const one = parseApply({ status: "APPLIED", inserted: 1, event_id: 9, pages: [7] });
  assert.equal(applyResultMessage(one!), "1 carta posicionada em 1 página.");
  const again = parseApply({ status: "ALREADY_APPLIED", inserted: 0, event_id: 422 });
  assert.deepEqual(again, { outcome: "ALREADY_APPLIED", inserted: 0, eventId: 422 });
  assert.match(applyResultMessage(again!), /já tinha sido aplicada/);
  const nothing = parseApply({ status: "NOTHING_TO_DO", inserted: 0 });
  assert.deepEqual(nothing, { outcome: "NOTHING_TO_DO", inserted: 0 });
  assert.equal(applyResultMessage(nothing!), "Nada a posicionar agora.");
});

test("resultado inválido: nunca adivinha", () => {
  assert.equal(parseApply(null), null);
  assert.equal(parseApply({ status: "OK", inserted: 1 }), null);
  assert.equal(parseApply({ status: "APPLIED", inserted: 0, event_id: 1, pages: [1] }), null);
  assert.equal(parseApply({ status: "APPLIED", inserted: 501, event_id: 1, pages: [1] }), null);
  assert.equal(parseApply({ status: "APPLIED", inserted: 2, event_id: null, pages: [1] }), null);
  assert.equal(parseApply({ status: "APPLIED", inserted: 2, event_id: 1, pages: [] }), null);
  assert.equal(parseApply({ status: "APPLIED", inserted: 2, event_id: 1, pages: [2, 1] }), null);
  assert.equal(parseApply({ status: "APPLIED", inserted: 1, event_id: 1, pages: [1, 2] }), null); // mais páginas que cartas
  assert.equal(parseApply({ status: "NOTHING_TO_DO", inserted: 1 }), null);
  assert.equal(parseApply({ status: "ALREADY_APPLIED", inserted: 0 }), null);
  assert.equal(parseApply({ status: "ALREADY_APPLIED", inserted: 3, event_id: 1 }), null);
});

// ---------------------------------------------------------------------------
// Falhas
// ---------------------------------------------------------------------------

test("40001 / 55P03 / 40P01: tratamentos distintos (contrato v1.4)", () => {
  const changed = classifyAutoArrangeFailure({ code: "40001", message: "AUTO_ARRANGE_PLAN_CHANGED" });
  assert.equal(changed, "plan_changed");
  assert.equal(failureNextStep(changed), "fresh_preview");
  assert.match(failureMessage(changed), /mudou desde a prévia/);

  const lock = classifyAutoArrangeFailure({ code: "55P03", message: "canceling statement due to lock timeout" });
  assert.equal(lock, "lock_timeout");
  assert.equal(failureNextStep(lock), "offer_retry");
  assert.match(failureMessage(lock), /sendo alterado agora/);

  const dead = classifyAutoArrangeFailure({ code: "40P01", message: "deadlock detected" });
  assert.equal(dead, "deadlock");
  assert.equal(failureNextStep(dead), "offer_retry");
  assert.match(failureMessage(dead), /conflito temporário/);

  for (const r of [changed, lock, dead]) {
    assert.equal(writeDefinitelyNotApplied(r), true, r);
    assert.equal(needsFreshPreview(r), true, r);
  }
});

test("demais erros contratuais da 5343/5344", () => {
  const cases: [string, string, AutoArrangeFailure, string][] = [
    ["28000", "not_authenticated", "not_authenticated", "reauthenticate"],
    ["22023", "INVALID_ARGUMENT", "invalid_argument", "close"],
    ["22023", "AUTO_ARRANGE_UNSUPPORTED_COLLECTION", "unsupported", "close"],
    ["42501", "AUTO_ARRANGE_NOT_BINDER_OWNER", "not_owner", "close"],
    ["42501", "permission denied for function apply_my_binder_auto_arrange", "forbidden", "close"],
    ["P0002", "COLLECTION_NOT_FOUND", "collection_not_found", "close"],
    ["P0002", "BINDER_NOT_FOUND", "binder_not_found", "close"],
    ["55000", "COLLECTION_ARCHIVED", "archived", "close"],
    ["54000", "AUTO_ARRANGE_LIMIT_EXCEEDED", "limit_exceeded", "show_limit"],
    ["57014", "canceling statement due to statement timeout", "statement_timeout", "offer_retry"],
    ["PGRST202", "Could not find the function", "unavailable", "close"],
    ["42883", "function does not exist", "unavailable", "close"],
    ["XX000", "internal error", "unknown", "close"],
  ];
  for (const [code, message, reason, step] of cases) {
    const got = classifyAutoArrangeFailure({ code, message });
    assert.equal(got, reason, `${code} ${message}`);
    assert.equal(failureNextStep(got), step, `${code} → passo`);
    assert.equal(writeDefinitelyNotApplied(got), true, `${code}: erro do banco = transação desfeita`);
    const text = failureMessage(got);
    assert.ok(text.length > 0);
    assert.doesNotMatch(text, /[A-Z]{3,}_[A-Z]/, `sem código interno: ${text}`);
  }
});

test("resultado incerto após perda de conexão: não afirma nada sobre a escrita", () => {
  for (const error of [null, undefined, {}, { code: "", message: "TypeError: fetch failed" }, { code: "ECONNRESET", message: "socket hang up" }, { message: "Gateway Timeout" }]) {
    const r = classifyAutoArrangeFailure(error as never);
    assert.equal(r, "uncertain", JSON.stringify(error));
    assert.equal(writeDefinitelyNotApplied(r), false);
    assert.equal(failureNextStep(r), "revalidate");
    assert.equal(needsFreshPreview(r), true);
    assert.match(failureMessage(r), /Não conseguimos confirmar o resultado/);
  }
  // Resposta de sucesso ilegível também deixa o resultado em aberto.
  assert.equal(writeDefinitelyNotApplied("invalid_response"), false);
  assert.equal(failureNextStep("invalid_response"), "revalidate");
});

test("revalidação: mesmo token prova que nada foi aplicado; token diferente não prova", () => {
  const same = parsePreview(ready());
  assert.equal(interpretRevalidation(TOKEN, same), "not_applied_same_plan");
  assert.match(revalidationMessage("not_applied_same_plan"), /nada foi posicionado/);
  // Depois de uma aplicação a época muda: a prévia nova traz outro token (ou fica vazia).
  const after = parsePreview({ ...EMPTY, plan_token: TOKEN_2 });
  assert.equal(interpretRevalidation(TOKEN, after), "changed_or_applied");
  assert.match(revalidationMessage("changed_or_applied"), /Histórico/);
  assert.equal(interpretRevalidation(TOKEN, null), "unknown");
  assert.equal(interpretRevalidation("lixo", same), "unknown");
});

test("nenhuma mensagem expõe identificadores ou códigos internos", () => {
  const p = parsePreview(ready())!;
  const all = [
    ...Object.values(previewSummary(p)),
    confirmationText(p),
    confirmLabel(p),
    ...(["plan_changed", "lock_timeout", "deadlock", "statement_timeout", "limit_exceeded", "unsupported", "not_owner", "forbidden", "archived", "collection_not_found", "binder_not_found", "not_authenticated", "invalid_argument", "unavailable", "invalid_response", "uncertain", "unknown"] as const).map(failureMessage),
    revalidationMessage("not_applied_same_plan"),
    revalidationMessage("changed_or_applied"),
    revalidationMessage("unknown"),
  ].join(" | ");
  assert.ok(!all.includes(TOKEN));
  assert.doesNotMatch(all, /aa1:|[0-9a-f]{8}-[0-9a-f]{4}-|[A-Z]{3,}_[A-Z]/i);
});
