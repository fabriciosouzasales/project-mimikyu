import {
  type AutoArrangeApplyResult,
  type AutoArrangeFailure,
  type AutoArrangePreview,
  type FailureNextStep,
  canConfirm,
  failureMessage,
  failureNextStep,
  interpretRevalidation,
  revalidationMessage,
} from "./binder-auto-arrange.ts";
import { type ArrangeView, type LocalVersion, isStale } from "./binder-auto-arrange-view.ts";

// ---------------------------------------------------------------------------
// Organizar automaticamente — CONFIRMAÇÃO E APLICAÇÃO (P2 UI E4).
//
// Máquina de estados pura do fluxo de confirmação, ortogonal à prévia
// (`ArrangeView`). Regras:
// - só uma prévia READY, válida (canConfirm) e não desatualizada abre a
//   revisão; a revisão fica presa à leitura (seq + token) que a originou;
// - confirmar exige a revisão ainda válida: qualquer nova leitura, mudança
//   local ou token diferente invalida a confirmação;
// - uma aplicação por vez (`applying` recusa um segundo início);
// - falhas nunca disparam nova escrita: 40001 pede nova prévia, 55P03/40P01/
//   57014 oferecem nova tentativa que COMEÇA por revalidação (leitura), e
//   resultado incerto revalida por leitura sem presumir que nada foi gravado;
// - nenhum plano novo é confirmado sozinho: depois de qualquer revalidação, a
//   volta à revisão ainda exige o clique em "Confirmar e posicionar".
// ---------------------------------------------------------------------------

export type CacheState = "revalidated" | "not_needed" | "failed";

export type ApplyFlow =
  | { kind: "idle"; notice: string | null }
  | { kind: "review"; planToken: string; previewSeq: number; notice: string | null }
  | { kind: "applying"; planToken: string; previewSeq: number }
  | { kind: "done"; result: AutoArrangeApplyResult; cache: CacheState }
  | { kind: "failed"; reason: AutoArrangeFailure; write: "not_applied" | "unknown"; planToken: string; step: FailureNextStep }
  | { kind: "revalidating"; previousToken: string; cause: "uncertain" | "retry" | "plan_changed" | "limit" };

export const FLOW_IDLE: ApplyFlow = { kind: "idle", notice: null };

/** Prévia que pode ser revisada: READY, contrato válido e sem mudança local desde a leitura. */
export function reviewablePreview(view: ArrangeView, current: LocalVersion): AutoArrangePreview | null {
  if (view.status !== "ready" || isStale(view, current) || !canConfirm(view.preview)) return null;
  return view.preview;
}

/** "Posicionar cartas" → revisão. `null` = bloqueado (EMPTY, LIMIT, erro, carregando, desatualizada). */
export function startReview(view: ArrangeView, current: LocalVersion, notice: string | null = null): ApplyFlow | null {
  const preview = reviewablePreview(view, current);
  if (!preview || view.status !== "ready") return null;
  return { kind: "review", planToken: preview.planToken, previewSeq: view.seq, notice };
}

/** A revisão ainda corresponde à prévia exibida (mesma leitura, mesmo token, nada mudou localmente). */
export function isReviewValid(flow: ApplyFlow, view: ArrangeView, current: LocalVersion): boolean {
  if (flow.kind !== "review") return false;
  const preview = reviewablePreview(view, current);
  return preview !== null && view.status === "ready" && view.seq === flow.previewSeq && preview.planToken === flow.planToken;
}

/**
 * "Confirmar e posicionar": só a partir de revisão válida. Devolve o novo
 * estado e o token a enviar; `null` = recusado (inclui segundo clique durante
 * a aplicação e prévia antiga).
 */
export function beginApply(flow: ApplyFlow, view: ArrangeView, current: LocalVersion): { flow: ApplyFlow; planToken: string } | null {
  if (flow.kind !== "review" || !isReviewValid(flow, view, current)) return null;
  return { flow: { kind: "applying", planToken: flow.planToken, previewSeq: flow.previewSeq }, planToken: flow.planToken };
}

export type ApplyOutcome =
  | { ok: true; result: AutoArrangeApplyResult; cache: CacheState }
  | { ok: false; reason: AutoArrangeFailure; write: "not_applied" | "unknown"; planToken?: string };

/** Resposta da aplicação; ignorada se não houver aplicação em curso com o mesmo token. */
export function finishApply(flow: ApplyFlow, planToken: string, outcome: ApplyOutcome): ApplyFlow {
  if (flow.kind !== "applying" || flow.planToken !== planToken) return flow;
  if (outcome.ok) return { kind: "done", result: outcome.result, cache: outcome.cache };
  // Na dúvida sobre a escrita, o estado é sempre "desconhecido".
  const write = outcome.write === "not_applied" && outcome.reason !== "uncertain" && outcome.reason !== "invalid_response" ? "not_applied" : "unknown";
  return { kind: "failed", reason: outcome.reason, write, planToken, step: failureNextStep(outcome.reason) };
}

/**
 * O que o workspace faz depois de uma falha — sempre só LEITURA:
 * - `revalidate`: resultado incerto → lê a prévia já (automático, só leitura);
 * - `fresh_preview` / `show_limit`: lê a prévia nova (automático, só leitura);
 * - `offer_retry`: espera o colecionador pedir "Tentar de novo" (que revalida);
 * - `reauthenticate` / `close`: só mensagem.
 */
export type FailureFollowUp = { read: "now" | "on_request" | "never"; cause: "uncertain" | "retry" | "plan_changed" | "limit" | null };

export function failureFollowUp(flow: ApplyFlow): FailureFollowUp {
  if (flow.kind !== "failed") return { read: "never", cause: null };
  switch (flow.step) {
    case "revalidate":
      return { read: "now", cause: "uncertain" };
    case "fresh_preview":
      return { read: "now", cause: "plan_changed" };
    case "show_limit":
      return { read: "now", cause: "limit" };
    case "offer_retry":
      return { read: "on_request", cause: "retry" };
    default:
      return { read: "never", cause: null };
  }
}

/** Início da revalidação (só leitura) a partir de uma falha. */
export function startRevalidation(flow: ApplyFlow): ApplyFlow {
  const follow = failureFollowUp(flow);
  if (flow.kind !== "failed" || follow.cause === null) return flow;
  return { kind: "revalidating", previousToken: flow.planToken, cause: follow.cause };
}

/**
 * Conclusão da revalidação com a prévia nova (ou a falha da leitura).
 * Nunca aplica: no melhor caso volta à REVISÃO, que exige confirmação explícita.
 */
export function finishRevalidation(flow: ApplyFlow, fresh: ArrangeView, current: LocalVersion): ApplyFlow {
  if (flow.kind !== "revalidating") return flow;
  const preview = fresh.status === "ready" ? fresh.preview : null;
  if (flow.cause === "plan_changed") return { kind: "idle", notice: failureMessage("plan_changed") };
  if (flow.cause === "limit") return { kind: "idle", notice: failureMessage("limit_exceeded") };
  const verdict = interpretRevalidation(flow.previousToken, preview);
  if (verdict === "not_applied_same_plan") {
    // Mesmo token = a época não mudou = nada foi aplicado. Revisão de novo, sem confirmar.
    return startReview(fresh, current, revalidationMessage(verdict)) ?? { kind: "idle", notice: revalidationMessage(verdict) };
  }
  if (verdict === "changed_or_applied") {
    return {
      kind: "idle",
      notice: flow.cause === "uncertain" ? revalidationMessage(verdict) : "O fichário mudou desde a prévia. Veja o plano atualizado antes de confirmar de novo.",
    };
  }
  return { kind: "idle", notice: revalidationMessage("unknown") };
}

// ---- textos e decisões de interface ----

export const REVIEW_GUARANTEES: readonly string[] = [
  "Nenhuma carta é substituída, movida ou retirada.",
  "Só bolsos reservados e vazios recebem carta.",
  "Reservas, bolsos fixados e imagens ficam como estão.",
  "As cartas que ficam de fora continuam sem bolso.",
];

/** Pokédex: o bolso de cada espécie recebe só a representante; as cópias extras ficam disponíveis. */
export const SPECIES_REVIEW_GUARANTEES: readonly string[] = [
  "Nenhuma carta é substituída, movida ou retirada.",
  "Só bolsos de espécie vazios recebem carta — a representante da espécie.",
  "Bolsos fixados e imagens ficam como estão.",
  "As cópias extras continuam em Cartas disponíveis.",
];

export function reviewGuarantees(target: "RESERVED" | "SPECIES"): readonly string[] {
  return target === "SPECIES" ? SPECIES_REVIEW_GUARANTEES : REVIEW_GUARANTEES;
}

export const CONFIRM_ACTION_LABEL = "Confirmar e posicionar";
export const WRITE_BUSY_HINT = "Aguarde a alteração em andamento no fichário terminar.";

/**
 * "Posicionar cartas" / "Confirmar e posicionar" com outra escrita local em
 * curso (`busy`): visível, indisponível e com o motivo. Volta sozinho quando
 * a escrita termina. A trava do servidor e a do duplo clique não mudam.
 */
export function reviewActionState(available: boolean, writeBusy: boolean): { show: boolean; enabled: boolean; hint: string | null } {
  if (!available) return { show: false, enabled: false, hint: null };
  return writeBusy ? { show: true, enabled: false, hint: WRITE_BUSY_HINT } : { show: true, enabled: true, hint: null };
}
export const START_REVIEW_LABEL = "Posicionar cartas";

/** Mensagem de falha da APLICAÇÃO, com o caso "resultado desconhecido" explícito. */
export function applyFailureText(flow: Extract<ApplyFlow, { kind: "failed" }>): string {
  return failureMessage(flow.reason);
}

/** Enquanto aplica (ou revalida após incerteza), outras escritas do fichário ficam bloqueadas e o painel não fecha. */
export function flowLocksWrites(flow: ApplyFlow): boolean {
  return flow.kind === "applying" || (flow.kind === "revalidating" && flow.cause === "uncertain");
}

/** Prévia exibida deve sumir (projeção e números) quando o fluxo terminou ou falhou. */
export function flowHidesProjection(flow: ApplyFlow): boolean {
  return flow.kind === "done" || flow.kind === "failed" || flow.kind === "revalidating" || flow.kind === "applying";
}

/**
 * Atualização da interface depois de uma resposta de SUCESSO.
 * - APPLIED: relê as páginas do resultado; Cartas disponíveis e contagem de
 *   cartas mudam em `inserted`; Histórico relê (activityVersion);
 * - ALREADY_APPLIED: a gravação foi anterior — relê as páginas da prévia
 *   confirmada e as listas (contagens exatas vêm do banco na releitura);
 * - NOTHING_TO_DO: nada mudou; nenhuma releitura de páginas.
 * A página à vista nunca muda aqui.
 */
export type RefreshPlan = { pages: number[]; filledDelta: number; availableDelta: number; reloadAvailable: boolean; clearHand: boolean };

export function refreshAfterApply(result: AutoArrangeApplyResult, confirmedPages: readonly number[]): RefreshPlan {
  switch (result.outcome) {
    case "APPLIED":
      return { pages: [...result.pages], filledDelta: result.inserted, availableDelta: -result.inserted, reloadAvailable: true, clearHand: true };
    case "ALREADY_APPLIED":
      return { pages: [...confirmedPages], filledDelta: 0, availableDelta: 0, reloadAvailable: true, clearHand: true };
    case "NOTHING_TO_DO":
      return { pages: [], filledDelta: 0, availableDelta: 0, reloadAvailable: false, clearHand: false };
  }
}

export const CACHE_FAILED_NOTE = "A organização está registrada, mas a tela pode não ter se atualizado por completo.";
