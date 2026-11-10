// Organizar automaticamente — interface de PRÉVIA (P2 UI E3).
// Executar: node --experimental-strip-types --test lib/colecoes/binder-auto-arrange-view.test.ts (a partir de web/)
//
// Fixtures SINTÉTICAS no formato da 5343 (passam por parsePreview). Nenhuma
// RPC é chamada; nenhuma escrita é possível a partir deste módulo.

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { type AutoArrangePreview, autoArrangeEntry, parsePreview } from "./binder-auto-arrange.ts";
import {
  ARRANGE_CLOSED,
  type ArrangeView,
  type LocalVersion,
  autoArrangeRailButton,
  closePreview,
  finishPreview,
  isStale,
  itemsOnPage,
  navigablePages,
  nextAffectedPage,
  previewAnnouncement,
  previewFailureMessage,
  previewRetryable,
  projectedSlotIds,
  readyFacts,
  sidePanelsWhenOpening,
  startPreview,
} from "./binder-auto-arrange-view.ts";

const TOKEN = `aa1:${"0123456789abcdef".repeat(4)}`;
const u = (n: number) => `00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`;
const item = (ord: number, page: number) => ({
  ord,
  slot_id: u(1000 + ord),
  physical_card_id: u(2000 + ord),
  page_number: page,
  row_index: 1,
  column_index: ord,
  card_id: u(3000 + ord),
  card_variant_id: u(4000 + ord),
});

function preview(raw: Record<string, unknown>): AutoArrangePreview {
  const p = parsePreview(raw);
  assert.ok(p, "fixture deve respeitar o contrato da 5343");
  return p;
}

const READY = preview({
  status: "READY",
  insert_count: 3,
  limit: 500,
  plan_token: TOKEN,
  excluded_cards: { COMPETING_CANDIDATES: 2 },
  unfilled_slots: { NO_CANDIDATE: 4, COMPETING_CANDIDATES: 1 },
  unfilled_count: 5,
  pages: [1, 3],
  items: [item(1, 1), item(2, 1), item(3, 3)],
});
const EMPTY = preview({ status: "EMPTY", insert_count: 0, limit: 500, plan_token: TOKEN, excluded_cards: {}, unfilled_slots: {}, unfilled_count: 0, pages: [], items: [] });
const LIMIT = preview({ status: "LIMIT_EXCEEDED", insert_count: 612, limit: 500, plan_token: TOKEN, excluded_cards: {}, unfilled_slots: {}, unfilled_count: 0, pages: [2, 4, 9], items: [] });

const V0: LocalVersion = { activity: 0, layout: 0 };

function readyView(p: AutoArrangePreview, version = V0): ArrangeView {
  const loading = startPreview(ARRANGE_CLOSED, version);
  assert.equal(loading.status, "loading");
  return finishPreview(loading, loading.status === "loading" ? loading.seq : 0, { ok: true, preview: p });
}

// ---------------------------------------------------------------------------
// Elegibilidade e indisponibilidade (botão do trilho)
// ---------------------------------------------------------------------------

test("trilho: Set e Master Set proprietárias → botão disponível; aberto muda o rótulo", () => {
  for (const kind of ["SET", "MASTER_SET"]) {
    const entry = autoArrangeEntry({ hasBinder: true, kind, active: true, editable: true, role: "OWNER" });
    assert.deepEqual(autoArrangeRailButton(entry, false), { present: true, enabled: true, label: "Organizar automaticamente — ver a prévia" });
    assert.deepEqual(autoArrangeRailButton(entry, true), { present: true, enabled: true, label: "Fechar a prévia da organização automática" });
  }
});

test("trilho: convidada, arquivada e só leitura → indisponível com explicação", () => {
  const guest = autoArrangeRailButton(autoArrangeEntry({ hasBinder: true, kind: "SET", active: true, editable: true, role: "GUEST" }), false);
  assert.equal(guest.present && guest.enabled, false);
  assert.match(guest.present ? guest.label : "", /Só a coleção dona deste fichário/);
  const archived = autoArrangeRailButton(autoArrangeEntry({ hasBinder: true, kind: "MASTER_SET", active: false, editable: false, role: "OWNER" }), false);
  assert.match(archived.present ? archived.label : "", /arquivada/);
  const readOnly = autoArrangeRailButton(autoArrangeEntry({ hasBinder: true, kind: "SET", active: true, editable: false, role: "OWNER" }), false);
  assert.match(readOnly.present ? readOnly.label : "", /só para leitura/);
  for (const b of [guest, archived, readOnly]) assert.equal(b.present && !b.enabled, true);
});

test("trilho: Pokédex da proprietária → botão presente", () => {
  assert.deepEqual(autoArrangeRailButton(autoArrangeEntry({ hasBinder: true, kind: "POKEDEX", active: true, editable: true, role: "OWNER" }), false), {
    present: true,
    enabled: true,
    label: "Organizar automaticamente — ver a prévia",
  });
});

test("trilho: Livre e sem fichário → botão ausente", () => {
  for (const kind of ["FREE"]) assert.deepEqual(autoArrangeRailButton(autoArrangeEntry({ hasBinder: true, kind, active: true, editable: true, role: "OWNER" }), false), { present: false });
  assert.deepEqual(autoArrangeRailButton(autoArrangeEntry({ hasBinder: false, kind: "SET", active: true, editable: false, role: null }), false), { present: false });
});

// ---------------------------------------------------------------------------
// Abertura, fechamento e alternância entre painéis
// ---------------------------------------------------------------------------

test("painéis: abrir um fecha os outros dois (mesma área do grid)", () => {
  assert.deepEqual(sidePanelsWhenOpening("arrange"), { control: false, available: false, arrange: true });
  assert.deepEqual(sidePanelsWhenOpening("control"), { control: true, available: false, arrange: false });
  assert.deepEqual(sidePanelsWhenOpening("available"), { control: false, available: true, arrange: false });
});

test("abrir → carregando; resposta READY preenche; fechar preserva a sequência", () => {
  const loading = startPreview(ARRANGE_CLOSED, V0);
  assert.deepEqual(loading, { status: "loading", seq: 1, version: V0 });
  const ready = finishPreview(loading, 1, { ok: true, preview: READY });
  assert.equal(ready.status, "ready");
  const closed = closePreview(ready);
  assert.deepEqual(closed, { status: "closed", lastSeq: 1 });
  // Resposta atrasada depois de fechar: ignorada (não reabre nem preenche).
  assert.deepEqual(finishPreview(closed, 1, { ok: true, preview: READY }), closed);
  // Reabrir usa sequência nova; a resposta da leitura antiga (seq 1) não vale para a nova (seq 2).
  const reopened = startPreview(closed, V0);
  assert.equal(reopened.status === "loading" && reopened.seq, 2);
  assert.deepEqual(finishPreview(reopened, 1, { ok: true, preview: EMPTY }), reopened);
});

test("atualizar durante uma leitura: só a resposta mais recente conta", () => {
  const first = startPreview(ARRANGE_CLOSED, V0);
  const second = startPreview(first, { activity: 1, layout: 0 });
  const stale = finishPreview(second, 1, { ok: true, preview: EMPTY });
  assert.equal(stale.status, "loading");
  const fresh = finishPreview(second, 2, { ok: true, preview: READY });
  assert.equal(fresh.status === "ready" && fresh.preview.status, "READY");
});

// ---------------------------------------------------------------------------
// READY, EMPTY, LIMIT_EXCEEDED e erro de leitura
// ---------------------------------------------------------------------------

test("READY: fatos (posicionáveis, páginas, reservas vazias, de fora) e projeção dos bolsos", () => {
  assert.deepEqual(
    readyFacts(READY).map((f) => [f.key, f.value, f.label]),
    [
      ["insert", "3", "cartas posicionáveis"],
      ["pages", "2", "páginas afetadas"],
      ["unfilled", "5", "reservas continuam vazias"],
      ["excluded", "2", "cartas ficam de fora"],
    ],
  );
  const view = readyView(READY);
  assert.deepEqual([...(projectedSlotIds(view, V0) ?? [])].sort(), [u(1001), u(1002), u(1003)].sort());
  assert.equal(itemsOnPage(READY, 1), 2);
  assert.equal(itemsOnPage(READY, 3), 1);
  assert.equal(itemsOnPage(READY, 2), 0);
  assert.equal(previewAnnouncement(view), "Prévia pronta: 3 cartas posicionáveis em 2 páginas.");
});

test("EMPTY: sem projeção, sem páginas, anúncio próprio", () => {
  const view = readyView(EMPTY);
  assert.equal(projectedSlotIds(view, V0), null);
  assert.deepEqual(navigablePages(EMPTY, 10), []);
  assert.equal(previewAnnouncement(view), "Prévia pronta: nenhuma carta para posicionar agora.");
});

test("LIMIT_EXCEEDED: sem projeção (itens vazios), páginas navegáveis, anúncio com o limite", () => {
  const view = readyView(LIMIT);
  assert.equal(projectedSlotIds(view, V0), null);
  assert.deepEqual(navigablePages(LIMIT, 8), [2, 4]); // página 9 não existe neste fichário
  assert.equal(previewAnnouncement(view), "Prévia pronta: 612 cartas, acima do limite de 500 por vez.");
});

test("erro de leitura: mensagem nunca sugere escrita; tentar de novo só quando faz sentido", () => {
  const loading = startPreview(ARRANGE_CLOSED, V0);
  const failed = finishPreview(loading, 1, { ok: false, reason: "uncertain" });
  assert.equal(failed.status, "error");
  assert.equal(projectedSlotIds(failed, V0), null);
  for (const reason of ["uncertain", "invalid_response", "unknown", "statement_timeout", "deadlock"] as const) {
    assert.match(previewFailureMessage(reason), /Nada foi alterado no fichário/);
    assert.equal(previewRetryable(reason), true, reason);
  }
  for (const reason of ["not_owner", "archived", "unsupported", "binder_not_found", "not_authenticated", "forbidden"] as const) {
    assert.equal(previewRetryable(reason), false, reason);
    assert.doesNotMatch(previewFailureMessage(reason), /posicionad|aplicad/i);
  }
});

// ---------------------------------------------------------------------------
// Navegação pelas páginas afetadas
// ---------------------------------------------------------------------------

test("navegação: próxima página afetada depois das que estão à vista (circular)", () => {
  assert.equal(nextAffectedPage([1, 3, 7], []), 1);
  assert.equal(nextAffectedPage([1, 3, 7], [1, 2]), 3);
  assert.equal(nextAffectedPage([1, 3, 7], [3]), 7);
  assert.equal(nextAffectedPage([1, 3, 7], [7, 8]), 1);
  assert.equal(nextAffectedPage([], [1]), null);
});

// ---------------------------------------------------------------------------
// Prévia desatualizada
// ---------------------------------------------------------------------------

test("desatualizada: escrita local (activityVersion) ou reordenação de páginas; some a projeção", () => {
  const view = readyView(READY, { activity: 4, layout: 0 });
  assert.equal(isStale(view, { activity: 4, layout: 0 }), false);
  assert.equal(isStale(view, { activity: 5, layout: 0 }), true);
  assert.equal(isStale(view, { activity: 4, layout: 1 }), true);
  assert.equal(projectedSlotIds(view, { activity: 5, layout: 0 }), null);
  // Carregando, erro e fechado nunca são "desatualizados" (não há plano exibido).
  assert.equal(isStale(startPreview(ARRANGE_CLOSED, V0), { activity: 9, layout: 9 }), false);
  assert.equal(isStale(ARRANGE_CLOSED, { activity: 9, layout: 9 }), false);
});

test("desatualizada: escrita durante a leitura deixa a prévia desatualizada assim que chega", () => {
  const loading = startPreview(ARRANGE_CLOSED, { activity: 2, layout: 0 });
  const ready = finishPreview(loading, 1, { ok: true, preview: READY });
  assert.equal(isStale(ready, { activity: 3, layout: 0 }), true);
});

// ---------------------------------------------------------------------------
// Segurança: a interface só conhece a prévia
// ---------------------------------------------------------------------------

test("segurança: a aplicação (5344) só existe na confirmação explícita do workspace", () => {
  const others = [
    "components/colecoes/fichario/binder-auto-arrange-panel.tsx",
    "components/colecoes/fichario/binder-tool-rail.tsx",
    "components/colecoes/fichario/binder-slot.tsx",
    "components/colecoes/fichario/binder-view.tsx",
    "components/colecoes/fichario/binder-overlay.tsx",
    "lib/colecoes/binder-auto-arrange-view.ts",
    "lib/colecoes/binder-auto-arrange-flow.ts",
  ];
  for (const file of others) {
    const source = readFileSync(new URL(`../../${file}`, import.meta.url), "utf8");
    assert.doesNotMatch(source, /applyAutoArrange|applyMyBinderAutoArrange|apply_my_binder_auto_arrange/, file);
  }
  const workspace = readFileSync(new URL("../../components/colecoes/fichario/binder-workspace.tsx", import.meta.url), "utf8");
  assert.match(workspace, /previewAutoArrange\(\{ collectionId \}\)/, "a prévia continua só leitura");
  // Exatamente uma chamada à aplicação, com coleção + token, dentro de confirmArrange.
  const calls = [...workspace.matchAll(/applyAutoArrange\(/g)];
  assert.equal(calls.length, 1, "uma única chamada a applyAutoArrange");
  const confirmStart = workspace.indexOf("const confirmArrange = useCallback(");
  const confirmEnd = workspace.indexOf("const retryArrange = useCallback(");
  assert.ok(confirmStart > 0 && confirmEnd > confirmStart);
  assert.ok(calls[0]!.index! > confirmStart && calls[0]!.index! < confirmEnd, "a chamada fica dentro de confirmArrange");
  assert.match(workspace.slice(confirmStart, confirmEnd), /applyAutoArrange\(\{ collectionId, planToken: begun\.planToken \}\)/);
  // Nenhum efeito dispara leitura ou escrita da organização automaticamente.
  assert.doesNotMatch(workspace, /useEffect\(\(\) => \{[^}]*(readArrangePreview|confirmArrange)/s);
});
