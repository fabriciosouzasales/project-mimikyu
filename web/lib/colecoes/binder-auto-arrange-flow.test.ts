// Organizar automaticamente — confirmação e aplicação (P2 UI E4).
// Executar: node --experimental-strip-types --test lib/colecoes/binder-auto-arrange-flow.test.ts (a partir de web/)
//
// Respostas SIMULADAS (formato do adaptador E2). Nenhuma RPC é chamada aqui;
// a 5344 real nunca é executada.

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { type AutoArrangePreview, parsePreview } from "./binder-auto-arrange.ts";
import { ARRANGE_CLOSED, type ArrangeView, type LocalVersion, closePreview, finishPreview, startPreview } from "./binder-auto-arrange-view.ts";
import {
  type ApplyFlow,
  type ApplyOutcome,
  FLOW_IDLE,
  beginApply,
  failureFollowUp,
  finishApply,
  finishRevalidation,
  flowHidesProjection,
  flowLocksWrites,
  isReviewValid,
  WRITE_BUSY_HINT,
  refreshAfterApply,
  reviewActionState,
  reviewablePreview,
  startReview,
  startRevalidation,
} from "./binder-auto-arrange-flow.ts";

const TOKEN = `aa1:${"0123456789abcdef".repeat(4)}`;
const TOKEN_2 = `aa1:${"fedcba9876543210".repeat(4)}`;
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
  assert.ok(p);
  return p;
}
const ready = (token = TOKEN) =>
  preview({ status: "READY", insert_count: 3, limit: 500, plan_token: token, excluded_cards: {}, unfilled_slots: {}, unfilled_count: 0, pages: [1, 4], items: [item(1, 1), item(2, 1), item(3, 4)] });
const EMPTY = preview({ status: "EMPTY", insert_count: 0, limit: 500, plan_token: TOKEN, excluded_cards: {}, unfilled_slots: {}, unfilled_count: 0, pages: [], items: [] });
const LIMIT = preview({ status: "LIMIT_EXCEEDED", insert_count: 501, limit: 500, plan_token: TOKEN, excluded_cards: {}, unfilled_slots: {}, unfilled_count: 0, pages: [1], items: [] });

const V0: LocalVersion = { activity: 0, layout: 0 };

/** Leitura simulada: closed/estado anterior → loading → resposta. */
function read(from: ArrangeView, p: AutoArrangePreview | null, version = V0): ArrangeView {
  const loading = startPreview(from, version);
  if (loading.status !== "loading") throw new Error("esperava loading");
  return finishPreview(loading, loading.seq, p ? { ok: true, preview: p } : { ok: false, reason: "uncertain" });
}

const APPLIED: ApplyOutcome = { ok: true, result: { outcome: "APPLIED", inserted: 3, eventId: 9, pages: [1, 4] }, cache: "revalidated" };

/** Simula a ação do workspace: quantas vezes a "RPC" seria chamada. */
function simulateConfirm(flow: ApplyFlow, view: ArrangeView, current: LocalVersion, calls: string[]) {
  const begun = beginApply(flow, view, current);
  if (!begun) return { flow, begun: null };
  calls.push(begun.planToken);
  return { flow: begun.flow, begun };
}

// ---------------------------------------------------------------------------
// Confirmação em duas etapas
// ---------------------------------------------------------------------------

test("duas etapas: Posicionar cartas → revisão → Confirmar e posicionar → uma chamada com o token da prévia", () => {
  const view = read(ARRANGE_CLOSED, ready());
  const calls: string[] = [];
  // Sem revisão, nada é aplicado.
  assert.equal(simulateConfirm(FLOW_IDLE, view, V0, calls).begun, null);
  const review = startReview(view, V0);
  assert.ok(review && review.kind === "review");
  assert.equal(review.planToken, TOKEN);
  assert.equal(isReviewValid(review, view, V0), true);
  const { flow: applying } = simulateConfirm(review, view, V0, calls);
  assert.deepEqual(calls, [TOKEN]);
  assert.equal(applying.kind, "applying");
  assert.equal(flowLocksWrites(applying), true);
  assert.equal(flowHidesProjection(applying), true);
  const done = finishApply(applying, TOKEN, APPLIED);
  assert.deepEqual(done, { kind: "done", result: { outcome: "APPLIED", inserted: 3, eventId: 9, pages: [1, 4] }, cache: "revalidated" });
});

// ---------------------------------------------------------------------------
// Estados bloqueados
// ---------------------------------------------------------------------------

test("bloqueado: EMPTY, LIMIT_EXCEEDED, erro, carregando, fechado e desatualizada não abrem revisão", () => {
  assert.equal(startReview(read(ARRANGE_CLOSED, EMPTY), V0), null);
  assert.equal(startReview(read(ARRANGE_CLOSED, LIMIT), V0), null);
  assert.equal(startReview(read(ARRANGE_CLOSED, null), V0), null); // erro de leitura
  assert.equal(startReview(startPreview(ARRANGE_CLOSED, V0), V0), null); // carregando
  assert.equal(startReview(ARRANGE_CLOSED, V0), null);
  const view = read(ARRANGE_CLOSED, ready());
  assert.equal(startReview(view, { activity: 1, layout: 0 }), null); // desatualizada
  assert.equal(reviewablePreview(view, { activity: 0, layout: 1 }), null);
});

test("bloqueado: revisão aberta e a prévia fica desatualizada → confirmação recusada", () => {
  const view = read(ARRANGE_CLOSED, ready());
  const review = startReview(view, V0)!;
  const calls: string[] = [];
  assert.equal(isReviewValid(review, view, { activity: 1, layout: 0 }), false);
  assert.equal(simulateConfirm(review, view, { activity: 1, layout: 0 }, calls).begun, null);
  assert.deepEqual(calls, []);
});

// ---------------------------------------------------------------------------
// Duplo clique e prévias antigas
// ---------------------------------------------------------------------------

test("duplo clique: o segundo Confirmar durante a aplicação é recusado (uma única chamada)", () => {
  const view = read(ARRANGE_CLOSED, ready());
  const calls: string[] = [];
  const first = simulateConfirm(startReview(view, V0)!, view, V0, calls);
  const second = simulateConfirm(first.flow, view, V0, calls);
  assert.equal(second.begun, null);
  assert.deepEqual(calls, [TOKEN]);
});

test("prévia antiga: revisão de uma leitura anterior não confirma depois de nova leitura", () => {
  const first = read(ARRANGE_CLOSED, ready(TOKEN));
  const review = startReview(first, V0)!;
  const second = read(first, ready(TOKEN_2)); // "Atualizar prévia"
  const calls: string[] = [];
  assert.equal(isReviewValid(review, second, V0), false);
  assert.equal(simulateConfirm(review, second, V0, calls).begun, null);
  // Mesmo token numa leitura nova também não reaproveita a revisão antiga (seq diferente).
  const third = read(second, ready(TOKEN));
  assert.equal(isReviewValid(review, third, V0), false);
  assert.deepEqual(calls, []);
});

test("resposta atrasada: aplicação com outro token, ou fora de aplicação, é ignorada", () => {
  const view = read(ARRANGE_CLOSED, ready());
  const applying = beginApply(startReview(view, V0)!, view, V0)!.flow;
  assert.deepEqual(finishApply(applying, TOKEN_2, APPLIED), applying);
  assert.deepEqual(finishApply(FLOW_IDLE, TOKEN, APPLIED), FLOW_IDLE);
  const done = finishApply(applying, TOKEN, APPLIED);
  assert.deepEqual(finishApply(done, TOKEN, APPLIED), done, "segunda resposta não muda o resultado");
});

test("resposta atrasada da prévia depois de fechar não reabre nada", () => {
  const view = read(ARRANGE_CLOSED, ready());
  const loading = startPreview(view, V0);
  const closed = closePreview(loading);
  assert.deepEqual(finishPreview(closed, loading.status === "loading" ? loading.seq : 0, { ok: true, preview: ready() }), closed);
});

// ---------------------------------------------------------------------------
// Resultados: APPLIED, ALREADY_APPLIED, NOTHING_TO_DO, cache failed
// ---------------------------------------------------------------------------

test("resultados de sucesso e falha de cache mantêm o sucesso", () => {
  const view = read(ARRANGE_CLOSED, ready());
  const applying = () => beginApply(startReview(view, V0)!, view, V0)!.flow;
  const already = finishApply(applying(), TOKEN, { ok: true, result: { outcome: "ALREADY_APPLIED", inserted: 0, eventId: 9 }, cache: "revalidated" });
  assert.equal(already.kind === "done" && already.result.outcome, "ALREADY_APPLIED");
  const nothing = finishApply(applying(), TOKEN, { ok: true, result: { outcome: "NOTHING_TO_DO", inserted: 0 }, cache: "not_needed" });
  assert.equal(nothing.kind === "done" && nothing.result.outcome, "NOTHING_TO_DO");
  const cacheFailed = finishApply(applying(), TOKEN, { ...APPLIED, cache: "failed" } as ApplyOutcome);
  assert.equal(cacheFailed.kind, "done", "falha de cache nunca vira erro de escrita");
  assert.equal(cacheFailed.kind === "done" && cacheFailed.cache, "failed");
  assert.equal(failureFollowUp(cacheFailed).read, "never", "sem releitura automática nem nova aplicação");
});

// ---------------------------------------------------------------------------
// Atualização da interface: páginas, Cartas disponíveis/mão, Histórico
// ---------------------------------------------------------------------------

test("atualização: APPLIED relê as páginas do resultado e ajusta contagens; ALREADY relê as confirmadas; NOTHING nada", () => {
  assert.deepEqual(refreshAfterApply({ outcome: "APPLIED", inserted: 3, eventId: 9, pages: [1, 4] }, [1, 4, 6]), {
    pages: [1, 4],
    filledDelta: 3,
    availableDelta: -3,
    reloadAvailable: true,
    clearHand: true,
  });
  assert.deepEqual(refreshAfterApply({ outcome: "ALREADY_APPLIED", inserted: 0, eventId: 9 }, [2, 5]), {
    pages: [2, 5],
    filledDelta: 0,
    availableDelta: 0,
    reloadAvailable: true,
    clearHand: true,
  });
  assert.deepEqual(refreshAfterApply({ outcome: "NOTHING_TO_DO", inserted: 0 }, [2, 5]), {
    pages: [],
    filledDelta: 0,
    availableDelta: 0,
    reloadAvailable: false,
    clearHand: false,
  });
  // O resultado some a projeção (bolsos já gravados não são mais "prévia").
  assert.equal(flowHidesProjection({ kind: "done", result: { outcome: "APPLIED", inserted: 3, eventId: 9, pages: [1] }, cache: "revalidated" }), true);
});

// ---------------------------------------------------------------------------
// Mudança de plano (40001), retry controlado (55P03/40P01/57014), incerto
// ---------------------------------------------------------------------------

function failedWith(reason: string, write: "not_applied" | "unknown" = "not_applied"): ApplyFlow {
  const view = read(ARRANGE_CLOSED, ready());
  const applying = beginApply(startReview(view, V0)!, view, V0)!.flow;
  return finishApply(applying, TOKEN, { ok: false, reason: reason as never, write });
}

test("40001: nova prévia automática (só leitura) e nunca confirmação automática", () => {
  const failed = failedWith("plan_changed");
  assert.equal(failed.kind === "failed" && failed.write, "not_applied");
  assert.deepEqual(failureFollowUp(failed), { read: "now", cause: "plan_changed" });
  const revalidating = startRevalidation(failed);
  assert.equal(revalidating.kind, "revalidating");
  const fresh = read(ARRANGE_CLOSED, ready(TOKEN_2));
  const after = finishRevalidation(revalidating, fresh, V0);
  assert.equal(after.kind, "idle", "plano novo exige novo 'Posicionar cartas' + confirmação");
  assert.match(after.kind === "idle" ? (after.notice ?? "") : "", /confirme de novo/);
});

test("55P03 / 40P01 / 57014: tentativa só quando pedida, e começa por revalidação; mesmo plano volta à REVISÃO (sem aplicar)", () => {
  for (const reason of ["lock_timeout", "deadlock", "statement_timeout"]) {
    const failed = failedWith(reason);
    assert.deepEqual(failureFollowUp(failed), { read: "on_request", cause: "retry" }, reason);
    const revalidating = startRevalidation(failed);
    const sameFresh = read(ARRANGE_CLOSED, ready(TOKEN));
    const back = finishRevalidation(revalidating, sameFresh, V0);
    assert.equal(back.kind, "review", "precisa de novo clique em Confirmar");
    assert.equal(back.kind === "review" && back.planToken, TOKEN);
    const changed = finishRevalidation(revalidating, read(ARRANGE_CLOSED, ready(TOKEN_2)), V0);
    assert.equal(changed.kind, "idle");
  }
});

test("resultado incerto: revalida por leitura; nunca diz que nada foi gravado sem prova; trava escritas enquanto confere", () => {
  for (const reason of ["uncertain", "invalid_response"]) {
    const failed = failedWith(reason, "unknown");
    assert.equal(failed.kind === "failed" && failed.write, "unknown", reason);
    assert.deepEqual(failureFollowUp(failed), { read: "now", cause: "uncertain" });
    const revalidating = startRevalidation(failed);
    assert.equal(flowLocksWrites(revalidating), true);
    // Token igual = prova de não aplicado → revisão (sem aplicar sozinho).
    const same = finishRevalidation(revalidating, read(ARRANGE_CLOSED, ready(TOKEN)), V0);
    assert.equal(same.kind, "review");
    // Token diferente = pode ter sido aplicado → sem revisão, aviso para conferir.
    const changed = finishRevalidation(revalidating, read(ARRANGE_CLOSED, ready(TOKEN_2)), V0);
    assert.equal(changed.kind, "idle");
    assert.match(changed.kind === "idle" ? (changed.notice ?? "") : "", /pode ter sido concluída/);
    // Leitura falhou → continua bloqueado, sem afirmar nada.
    const unknown = finishRevalidation(revalidating, read(ARRANGE_CLOSED, null), V0);
    assert.equal(unknown.kind, "idle");
    assert.doesNotMatch(unknown.kind === "idle" ? (unknown.notice ?? "") : "", /nada foi posicionado/i);
  }
  // "write: not_applied" vindo junto com incerto é rebaixado para desconhecido.
  const forced = failedWith("uncertain", "not_applied");
  assert.equal(forced.kind === "failed" && forced.write, "unknown");
});

test("erros terminais (28000, 42501, 55000...): sem leitura nem tentativa automática", () => {
  for (const reason of ["not_authenticated", "not_owner", "archived", "unsupported", "unknown"]) {
    const failed = failedWith(reason);
    assert.equal(failureFollowUp(failed).read, "never", reason);
    assert.deepEqual(startRevalidation(failed), failed);
  }
});

test("54000: lê a nova prévia (que mostra o limite) e não oferece confirmação", () => {
  const failed = failedWith("limit_exceeded");
  assert.deepEqual(failureFollowUp(failed), { read: "now", cause: "limit" });
  const after = finishRevalidation(startRevalidation(failed), read(ARRANGE_CLOSED, LIMIT), V0);
  assert.equal(after.kind, "idle");
  assert.equal(startReview(read(ARRANGE_CLOSED, LIMIT), V0), null);
});

// ---------------------------------------------------------------------------
// CLOSEOUT-05: "Posicionar cartas" indisponível durante outra escrita local
// ---------------------------------------------------------------------------

test("escrita local em curso: ação visível, indisponível e com motivo; volta quando termina", () => {
  assert.deepEqual(reviewActionState(true, false), { show: true, enabled: true, hint: null });
  assert.deepEqual(reviewActionState(true, true), { show: true, enabled: false, hint: WRITE_BUSY_HINT });
  // Concluída a escrita (busy volta a false), a ação volta a ficar disponível.
  assert.deepEqual(reviewActionState(true, false).enabled, true);
  // Sem prévia revisável (EMPTY, LIMIT, erro, desatualizada), continua ausente — com ou sem escrita.
  assert.deepEqual(reviewActionState(false, true), { show: false, enabled: false, hint: null });
  assert.deepEqual(reviewActionState(false, false), { show: false, enabled: false, hint: null });
  assert.match(WRITE_BUSY_HINT, /Aguarde/);
});

test("escrita local em curso: painel e workspace usam o estado de ocupado sem tocar nas travas existentes", () => {
  const panel = readFileSync(new URL("../../components/colecoes/fichario/binder-auto-arrange-panel.tsx", import.meta.url), "utf8");
  const workspace = readFileSync(new URL("../../components/colecoes/fichario/binder-workspace.tsx", import.meta.url), "utf8");
  // Botões ficam aria-disabled e sem onClick enquanto ocupado.
  assert.match(panel, /onClick=\{action\.enabled \? onStartReview : undefined\}/);
  assert.match(panel, /onClick=\{action\.enabled \? onConfirm : undefined\}/);
  assert.equal((panel.match(/aria-disabled=\{!action\.enabled \|\| undefined\}/g) ?? []).length, 2);
  // O workspace repassa `busy` e também recusa abrir a revisão enquanto ocupado.
  assert.match(workspace, /writeBusy=\{busy\}/);
  const start = workspace.indexOf("const startArrangeReview = useCallback(");
  assert.ok(start > 0);
  assert.match(workspace.slice(start, start + 300), /if \(busy\) return;/);
  // Travas anteriores intactas: duplo clique e escrita em curso na confirmação.
  const confirm = workspace.slice(workspace.indexOf("const confirmArrange = useCallback("));
  assert.match(confirm, /if \(applyingRef\.current\) return; \/\/ duplo clique/);
  assert.match(confirm, /if \(busy\) return;/);
});

// ---------------------------------------------------------------------------
// E5: polimento visual e de acessibilidade (inspeção estática do painel)
// ---------------------------------------------------------------------------

test("E5 acessibilidade: revisão foca o título (nunca o botão que grava) e o foco perdido volta ao painel", () => {
  const panel = readFileSync(new URL("../../components/colecoes/fichario/binder-auto-arrange-panel.tsx", import.meta.url), "utf8");
  assert.doesNotMatch(panel, /confirmRef/, "o botão Confirmar não recebe foco automático");
  assert.match(panel, /ref=\{reviewHeadingRef\} tabIndex=\{-1\}/);
  assert.match(panel, /\}, \[flow\.kind, view\.status\]\);/, "recuperação de foco a cada troca de etapa");
  assert.match(panel, /active === null \|\| active === document\.body/, "só quando o foco foi perdido");
});

test("E5 acessibilidade: uma única região viva (sem anúncio duplicado nos blocos visuais)", () => {
  const panel = readFileSync(new URL("../../components/colecoes/fichario/binder-auto-arrange-panel.tsx", import.meta.url), "utf8");
  assert.equal((panel.match(/role="status"/g) ?? []).length, 1, "só a região viva sr-only");
  assert.equal((panel.match(/role="alert"/g) ?? []).length, 0);
  assert.match(panel, /className="sr-only" role="status" aria-live="polite" aria-atomic="true"/);
});

test("E5 visual: fechar indisponível tem aparência de indisponível; alvos de toque ≥ 44 px", () => {
  const css = readFileSync(new URL("../../components/colecoes/fichario/binder-auto-arrange.module.css", import.meta.url), "utf8");
  assert.match(css, /\.close\[aria-disabled="true"\] \{[^}]*opacity: 0\.35;[^}]*cursor: not-allowed;/s);
  const minHeights = [...css.matchAll(/\.(close|action|linkButton|page|primary)\s*\{[^}]*min-height: ([\d.]+)rem/gs)].map((m) => [m[1], Number(m[2])] as const);
  for (const [cls, rem] of minHeights) assert.ok(rem >= 2.75, `${cls}: ${rem}rem < 2.75rem`);
  assert.ok(minHeights.some(([c]) => c === "linkButton"), "linkButton medido");
  // .close usa height fixa de 2.75rem.
  assert.match(css, /\.close \{[^}]*width: 2\.75rem;[^}]*height: 2\.75rem;/s);
});
