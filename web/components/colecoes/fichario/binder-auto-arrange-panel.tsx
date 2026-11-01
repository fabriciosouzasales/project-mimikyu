"use client";

import { useEffect, useRef } from "react";
import { AlertTriangle, CheckCircle2, ChevronRight, Loader2, RotateCcw, ShieldCheck, X } from "lucide-react";
import { REASONS_FOOTNOTE, applyResultMessage, confirmationText, excludedLines, pagesPhrase, previewSummary, unfilledLines } from "@/lib/colecoes/binder-auto-arrange";
import {
  AUTO_ARRANGE_PANEL_ID,
  type ArrangeView,
  SERVER_AUTHORITY_NOTE,
  STALE_MESSAGE,
  itemsOnPage,
  navigablePages,
  nextAffectedPage,
  previewAnnouncement,
  previewFailureMessage,
  previewRetryable,
  readyFacts,
} from "@/lib/colecoes/binder-auto-arrange-view";
import {
  type ApplyFlow,
  CACHE_FAILED_NOTE,
  CONFIRM_ACTION_LABEL,
  REVIEW_GUARANTEES,
  START_REVIEW_LABEL,
  applyFailureText,
  failureFollowUp,
  reviewActionState,
} from "@/lib/colecoes/binder-auto-arrange-flow";
import styles from "./binder-auto-arrange.module.css";

/**
 * Organizar automaticamente — prévia (P2 UI E3) + confirmação e aplicação
 * (P2 UI E4), tudo no próprio painel, sem modal.
 *
 * Mesmo encaixe de "Cartas disponíveis": `side` = coluna à direita
 * (≥ 1280 px), `bottom` = faixa abaixo do fichário; exclusivo com o Centro de
 * Controle e com Cartas disponíveis (o workspace garante).
 *
 * Fluxo: prévia READY válida → "Posicionar cartas" → revisão (quantidade,
 * páginas, garantias) → "Confirmar e posicionar" (única ação que grava, via
 * workspace) → resultado. O componente não chama nada sozinho: só pede ao
 * workspace, que valida de novo cada passo (`binder-auto-arrange-flow`).
 */
export function AutoArrangePanel({
  mode,
  view,
  stale,
  flow,
  canReview,
  reviewValid,
  writeBusy,
  totalPages,
  visiblePages,
  onRefresh,
  onGoToPage,
  onClose,
  onStartReview,
  onCancelReview,
  onConfirm,
  onRetry,
  onRefreshScreen,
}: {
  mode: "side" | "bottom";
  view: Exclude<ArrangeView, { status: "closed" }>;
  stale: boolean;
  flow: ApplyFlow;
  /** Prévia READY, válida e atual: "Posicionar cartas" disponível. */
  canReview: boolean;
  /** A revisão aberta ainda corresponde à prévia exibida. */
  reviewValid: boolean;
  /** Outra escrita do fichário em curso: as ações de posicionar ficam indisponíveis, com o motivo. */
  writeBusy: boolean;
  totalPages: number;
  visiblePages: readonly number[];
  onRefresh: () => void;
  onGoToPage: (page: number) => void;
  onClose: () => void;
  onStartReview: () => void;
  onCancelReview: () => void;
  onConfirm: () => void;
  onRetry: () => void;
  onRefreshScreen: () => void;
}) {
  const headingRef = useRef<HTMLHeadingElement>(null);
  // Foco gerenciado: ao abrir, o título do painel recebe o foco (sem rolar a página).
  useEffect(() => {
    headingRef.current?.focus({ preventScroll: true });
  }, []);
  // E5: ao trocar de etapa (revisão → aplicando → resultado, Voltar, nova leitura), o botão
  // que tinha o foco sai da tela. Se o foco caiu no documento, volta ao título do painel;
  // nunca rouba o foco de quem está em outro controle (ex.: virando páginas).
  useEffect(() => {
    const active = document.activeElement;
    if (active === null || active === document.body) headingRef.current?.focus({ preventScroll: true });
  }, [flow.kind, view.status]);

  const locked = flow.kind === "applying" || (flow.kind === "revalidating" && flow.cause === "uncertain");
  const announcement = flowAnnouncement(flow) ?? (stale ? STALE_MESSAGE : previewAnnouncement(view));
  const reviewing = flow.kind === "review" && reviewValid;
  const flowBody = flow.kind === "applying" || flow.kind === "done" || flow.kind === "failed" || flow.kind === "revalidating";

  return (
    <section
      id={AUTO_ARRANGE_PANEL_ID}
      className={styles.panel}
      data-mode={mode}
      role="region"
      aria-labelledby="organizar-titulo"
      aria-busy={view.status === "loading" || flow.kind === "applying" || flow.kind === "revalidating" || undefined}
    >
      <div className={styles.head}>
        <div className={styles.headText}>
          <h3 id="organizar-titulo" ref={headingRef} tabIndex={-1} className={styles.title}>
            Organizar automaticamente
          </h3>
          <p className={styles.hint}>Coloca nos bolsos reservados as cartas guardadas neste fichário que ainda não têm lugar.</p>
        </div>
        <button
          type="button"
          className={styles.close}
          onClick={locked ? undefined : onClose}
          aria-disabled={locked || undefined}
          aria-label={locked ? "Aguarde: posicionando as cartas" : "Fechar a organização automática (Esc)"}
        >
          <X className="h-4 w-4" aria-hidden />
        </button>
      </div>

      {/* Região viva ÚNICA: anuncia leitura, revisão, aplicação, resultado e falhas (os blocos visuais não repetem o anúncio). */}
      <p className="sr-only" role="status" aria-live="polite" aria-atomic="true">
        {announcement}
      </p>

      <div className={styles.body}>
        {flowBody ? (
          <FlowBody flow={flow} totalPages={totalPages} visiblePages={visiblePages} onGoToPage={onGoToPage} onRefresh={onRefresh} onRetry={onRetry} onRefreshScreen={onRefreshScreen} onClose={onClose} />
        ) : reviewing && view.status === "ready" ? (
          <ReviewBody view={view} notice={flow.kind === "review" ? flow.notice : null} writeBusy={writeBusy} onCancel={onCancelReview} onConfirm={onConfirm} />
        ) : (
          <>
            {flow.kind === "idle" && flow.notice ? (
              <div className={styles.stale} role="note">
                <AlertTriangle className="h-4 w-4 flex-none" aria-hidden />
                <span>{flow.notice}</span>
              </div>
            ) : null}
            {stale ? (
              <div className={styles.stale} role="note">
                <AlertTriangle className="h-4 w-4 flex-none" aria-hidden />
                <span>{STALE_MESSAGE}</span>
                <button type="button" className={styles.action} onClick={onRefresh}>
                  <RotateCcw className="h-3.5 w-3.5" aria-hidden />
                  Atualizar prévia
                </button>
              </div>
            ) : null}

            {view.status === "loading" ? (
              <div className={styles.skeleton} aria-hidden>
                <span />
                <span />
                <span />
              </div>
            ) : view.status === "error" ? (
              <div className={styles.state}>
                <span className={styles.stateTitle}>Prévia indisponível</span>
                {previewFailureMessage(view.reason)}
                {previewRetryable(view.reason) ? (
                  <div className={styles.actions}>
                    <button type="button" className={styles.action} onClick={onRefresh}>
                      <RotateCcw className="h-3.5 w-3.5" aria-hidden />
                      Tentar de novo
                    </button>
                  </div>
                ) : null}
              </div>
            ) : (
              <ReadyBody view={view} stale={stale} canReview={canReview} writeBusy={writeBusy} totalPages={totalPages} visiblePages={visiblePages} onGoToPage={onGoToPage} onRefresh={onRefresh} onStartReview={onStartReview} />
            )}
          </>
        )}
      </div>
    </section>
  );
}

function flowAnnouncement(flow: ApplyFlow): string | null {
  switch (flow.kind) {
    case "review":
      return "Revise e confirme para posicionar as cartas.";
    case "applying":
      return "Posicionando as cartas.";
    case "revalidating":
      return "Conferindo o fichário.";
    case "done":
      return applyResultMessage(flow.result);
    case "failed":
      return applyFailureText(flow);
    default:
      return flow.notice;
  }
}

function ReadyBody({
  view,
  stale,
  canReview,
  writeBusy,
  totalPages,
  visiblePages,
  onGoToPage,
  onRefresh,
  onStartReview,
}: {
  view: Extract<ArrangeView, { status: "ready" }>;
  stale: boolean;
  canReview: boolean;
  writeBusy: boolean;
  totalPages: number;
  visiblePages: readonly number[];
  onGoToPage: (page: number) => void;
  onRefresh: () => void;
  onStartReview: () => void;
}) {
  const preview = view.preview;
  const summary = previewSummary(preview);
  const pages = navigablePages(preview, totalPages);
  const next = nextAffectedPage(pages, visiblePages);
  const excluded = excludedLines(preview);
  const unfilled = unfilledLines(preview);
  const action = reviewActionState(canReview, writeBusy);

  return (
    <div className={styles.ready} data-stale={stale || undefined}>
      <div>
        <p className={styles.headline}>{summary.headline}</p>
        <p className={styles.detail}>{preview.status === "READY" ? "Nenhuma carta é substituída, movida ou retirada." : summary.detail}</p>
      </div>

      {preview.status === "READY" ? (
        <dl className={styles.facts}>
          {readyFacts(preview).map((fact) => (
            <div key={fact.key} className={styles.fact} data-key={fact.key}>
              <dt>{fact.label}</dt>
              <dd>{fact.value}</dd>
            </div>
          ))}
        </dl>
      ) : null}

      {action.show ? (
        <div className={styles.actions}>
          <button
            type="button"
            className={styles.primary}
            onClick={action.enabled ? onStartReview : undefined}
            aria-disabled={!action.enabled || undefined}
            aria-describedby={action.hint ? "organizar-ocupado" : undefined}
          >
            {START_REVIEW_LABEL}
          </button>
          {action.hint ? (
            <p id="organizar-ocupado" className={styles.busyHint}>
              {action.hint}
            </p>
          ) : null}
        </div>
      ) : null}

      {pages.length > 0 ? (
        <div className={styles.section}>
          <div className={styles.sectionHead}>
            <h4 className={styles.sectionTitle}>{preview.status === "READY" ? "Páginas afetadas" : "Páginas envolvidas"}</h4>
            {next !== null && pages.length > 1 ? (
              <button type="button" className={styles.linkButton} onClick={() => onGoToPage(next)}>
                Próxima
                <ChevronRight className="h-3.5 w-3.5" aria-hidden />
              </button>
            ) : null}
          </div>
          <PageList pages={pages} visiblePages={visiblePages} counts={preview.status === "READY" ? (p) => itemsOnPage(preview, p) : () => 0} onGoToPage={onGoToPage} />
          {preview.status === "READY" && !stale ? <p className={styles.legend}>Bolsos marcados com contorno dourado tracejado receberiam uma carta. É só uma prévia.</p> : null}
        </div>
      ) : null}

      {excluded.length > 0 ? <ReasonList title="Cartas que ficam de fora" lines={excluded} /> : null}
      {unfilled.length > 0 ? <ReasonList title="Reservas que continuam vazias" lines={unfilled} /> : null}
      {excluded.length > 0 || unfilled.length > 0 ? <p className={styles.footnote}>{REASONS_FOOTNOTE}</p> : null}

      <div className={styles.notes}>
        <p>{SERVER_AUTHORITY_NOTE}</p>
      </div>

      {!stale ? (
        <div className={styles.actions}>
          <button type="button" className={styles.action} onClick={onRefresh}>
            <RotateCcw className="h-3.5 w-3.5" aria-hidden />
            Atualizar prévia
          </button>
        </div>
      ) : null}
    </div>
  );
}

/** Etapa de revisão (no painel): quantidade, páginas, garantias e a confirmação explícita. */
function ReviewBody({
  view,
  notice,
  writeBusy,
  onCancel,
  onConfirm,
}: {
  view: Extract<ArrangeView, { status: "ready" }>;
  notice: string | null;
  writeBusy: boolean;
  onCancel: () => void;
  onConfirm: () => void;
}) {
  const preview = view.preview;
  const action = reviewActionState(true, writeBusy);
  // E5: o foco vai para o título da revisão (não para o botão que grava): dois
  // Enter seguidos nunca confirmam sem leitura, e o título fica visível na faixa baixa.
  const reviewHeadingRef = useRef<HTMLParagraphElement>(null);
  useEffect(() => {
    const heading = reviewHeadingRef.current;
    heading?.focus({ preventScroll: true });
    heading?.scrollIntoView({ block: "nearest" });
  }, []);
  return (
    <div className={styles.ready}>
      {notice ? (
        <div className={styles.stale} role="note">
          <AlertTriangle className="h-4 w-4 flex-none" aria-hidden />
          <span>{notice}</span>
        </div>
      ) : null}
      <div>
        <p ref={reviewHeadingRef} tabIndex={-1} className={styles.headline}>
          Revisar antes de posicionar
        </p>
        <p className={styles.detail}>{confirmationText(preview)}</p>
      </div>
      <dl className={styles.facts}>
        <div className={styles.fact} data-key="insert">
          <dt>{preview.insertCount === 1 ? "carta será posicionada" : "cartas serão posicionadas"}</dt>
          <dd>{preview.insertCount.toLocaleString("pt-BR")}</dd>
        </div>
        <div className={styles.fact}>
          <dt>{pagesPhrase(preview.pages)}</dt>
          <dd>{preview.pages.length.toLocaleString("pt-BR")}</dd>
        </div>
      </dl>
      <ul className={styles.guarantees} aria-label="O que é preservado">
        {REVIEW_GUARANTEES.map((text) => (
          <li key={text}>
            <ShieldCheck className="h-3.5 w-3.5 flex-none" aria-hidden />
            <span>{text}</span>
          </li>
        ))}
      </ul>
      <div className={styles.actions}>
        <button
          type="button"
          className={styles.primary}
          onClick={action.enabled ? onConfirm : undefined}
          aria-disabled={!action.enabled || undefined}
          aria-describedby={action.hint ? "organizar-ocupado-revisao" : undefined}
        >
          {CONFIRM_ACTION_LABEL}
        </button>
        <button type="button" className={styles.action} onClick={onCancel}>
          Voltar
        </button>
        {action.hint ? (
          <p id="organizar-ocupado-revisao" className={styles.busyHint}>
            {action.hint}
          </p>
        ) : null}
      </div>
    </div>
  );
}

/** Aplicação em curso, resultado, falha ou revalidação (sempre só leitura depois da falha). */
function FlowBody({
  flow,
  totalPages,
  visiblePages,
  onGoToPage,
  onRefresh,
  onRetry,
  onRefreshScreen,
  onClose,
}: {
  flow: ApplyFlow;
  totalPages: number;
  visiblePages: readonly number[];
  onGoToPage: (page: number) => void;
  onRefresh: () => void;
  onRetry: () => void;
  onRefreshScreen: () => void;
  onClose: () => void;
}) {
  if (flow.kind === "applying" || flow.kind === "revalidating") {
    return (
      <div className={styles.state}>
        <span className={styles.progress}>
          <Loader2 className="h-4 w-4 animate-spin motion-reduce:animate-none" aria-hidden />
          <span className={styles.stateTitle}>{flow.kind === "applying" ? "Posicionando as cartas…" : "Conferindo o fichário…"}</span>
        </span>
        {flow.kind === "applying"
          ? "Não feche o fichário. Enquanto isso, você pode virar as páginas; as outras alterações ficam em espera."
          : "Leitura de conferência, sem nenhuma alteração. Nenhuma tentativa é repetida sozinha."}
      </div>
    );
  }
  if (flow.kind === "done") {
    const pages = flow.result.outcome === "APPLIED" ? flow.result.pages.filter((p) => p >= 1 && p <= totalPages) : [];
    return (
      <div className={styles.ready}>
        <div className={styles.success}>
          <CheckCircle2 className="h-5 w-5 flex-none" aria-hidden />
          <div>
            <p className={styles.headline}>{flow.result.outcome === "APPLIED" ? "Cartas posicionadas" : flow.result.outcome === "ALREADY_APPLIED" ? "Organização já aplicada" : "Nenhuma alteração"}</p>
            <p className={styles.detail}>{applyResultMessage(flow.result)}</p>
          </div>
        </div>
        {flow.cache === "failed" ? (
          <div className={styles.stale} role="note">
            <AlertTriangle className="h-4 w-4 flex-none" aria-hidden />
            <span>{CACHE_FAILED_NOTE}</span>
            <button type="button" className={styles.action} onClick={onRefreshScreen}>
              <RotateCcw className="h-3.5 w-3.5" aria-hidden />
              Atualizar a tela
            </button>
          </div>
        ) : null}
        {pages.length > 0 ? (
          <div className={styles.section}>
            <h4 className={styles.sectionTitle}>Ver as páginas</h4>
            <PageList pages={pages} visiblePages={visiblePages} counts={() => 0} onGoToPage={onGoToPage} />
          </div>
        ) : null}
        <div className={styles.actions}>
          <button type="button" className={styles.action} onClick={onRefresh}>
            <RotateCcw className="h-3.5 w-3.5" aria-hidden />
            Nova prévia
          </button>
          <button type="button" className={styles.action} onClick={onClose}>
            Fechar
          </button>
        </div>
      </div>
    );
  }
  if (flow.kind !== "failed") return null;
  const follow = failureFollowUp(flow);
  return (
    <div className={styles.state}>
      <span className={styles.stateTitle}>{flow.write === "unknown" ? "Resultado ainda não confirmado" : "Nada foi posicionado"}</span>
      {applyFailureText(flow)}
      <div className={styles.actions}>
        {follow.read === "on_request" ? (
          <button type="button" className={styles.action} onClick={onRetry}>
            <RotateCcw className="h-3.5 w-3.5" aria-hidden />
            Tentar de novo
          </button>
        ) : null}
        <button type="button" className={styles.action} onClick={onClose}>
          Fechar
        </button>
      </div>
    </div>
  );
}

function PageList({
  pages,
  visiblePages,
  counts,
  onGoToPage,
}: {
  pages: readonly number[];
  visiblePages: readonly number[];
  counts: (page: number) => number;
  onGoToPage: (page: number) => void;
}) {
  return (
    <ul className={styles.pages} aria-label="Ir para uma página afetada">
      {pages.map((page) => {
        const here = visiblePages.includes(page);
        const n = counts(page);
        return (
          <li key={page}>
            <button
              type="button"
              className={styles.page}
              aria-current={here ? "page" : undefined}
              aria-label={`Página ${page}${n > 0 ? `, ${n} ${n === 1 ? "carta" : "cartas"}` : ""}${here ? ", à vista" : ""}`}
              onClick={() => onGoToPage(page)}
            >
              <span className={styles.pageNumber}>{page}</span>
              {n > 0 ? <span className={styles.pageCount}>{n}</span> : null}
            </button>
          </li>
        );
      })}
    </ul>
  );
}

function ReasonList({ title, lines }: { title: string; lines: { key: string; label: string; count: number }[] }) {
  return (
    <div className={styles.section}>
      <h4 className={styles.sectionTitle}>{title}</h4>
      <ul className={styles.reasons}>
        {lines.map((line) => (
          <li key={line.key}>
            <span>{line.label}</span>
            <span className={styles.reasonCount}>{line.count.toLocaleString("pt-BR")}</span>
          </li>
        ))}
      </ul>
    </div>
  );
}
