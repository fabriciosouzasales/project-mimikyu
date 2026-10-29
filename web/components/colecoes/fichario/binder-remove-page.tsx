"use client";

import { useEffect, useId, useMemo, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { FileMinus2, Loader2, ShieldAlert, X } from "lucide-react";
import { formatCount } from "@/lib/colecoes/acervo";
import type { BinderPage } from "@/lib/colecoes/binder";
import { pageRemovalBlockerLabel, pageRemovalBlockers, pageRemovalRenumbering } from "@/lib/colecoes/binder-page-removal";
import base from "./binder-add-pages.module.css";
import styles from "./binder-remove-page.module.css";

const FOCUSABLE = 'button:not([disabled]), input:not([disabled]), [tabindex]:not([tabindex="-1"])';

export type RemovePageCandidate = { number: number; page: BinderPage | null };

/**
 * Remover página — confirmação explícita (menu lateral e Organizar páginas).
 *
 * Mesma linguagem escura dos diálogos pequenos do fichário (Adicionar
 * páginas). A elegibilidade mostrada aqui vem dos dados de cada bolso
 * (`pageRemovalBlockers`), nunca da aparência; o servidor confere de novo
 * com uma leitura fresca e o banco recusa sob trava o que o contrato cobre.
 *
 * Com duas páginas à vista (fichário aberto), o colecionador escolhe qual;
 * uma página bloqueada mostra o porquê e o que fazer, sem botão de remover.
 * Teclado: Tab preso, Esc fecha, setas não viram a página por baixo.
 */
export function RemovePageDialog({
  host,
  candidates,
  initialNumber,
  totalPages,
  busy,
  error,
  onConfirm,
  onClose,
}: {
  host: HTMLElement | null;
  candidates: RemovePageCandidate[];
  initialNumber?: number;
  totalPages: number;
  busy: boolean;
  error?: string | null;
  onConfirm: (page: BinderPage) => void;
  onClose: () => void;
}) {
  const dialogRef = useRef<HTMLDivElement>(null);
  const titleId = useId();
  const descId = useId();
  const firstEligible = candidates.find((c) => c.page && pageRemovalBlockers(c.page, totalPages).length === 0)?.number;
  const [chosen, setChosen] = useState<number>(initialNumber ?? firstEligible ?? candidates[0]?.number ?? 1);
  const current = candidates.find((c) => c.number === chosen) ?? candidates[0];
  const blockers = useMemo(() => (current?.page ? pageRemovalBlockers(current.page, totalPages) : []), [current, totalPages]);
  const loading = !current?.page;
  const eligible = !loading && blockers.length === 0;
  const renumber = current ? pageRemovalRenumbering(current.number, totalPages) : null;

  useEffect(() => {
    const opener = document.activeElement as HTMLElement | null;
    dialogRef.current?.querySelector<HTMLElement>("[data-autofocus]")?.focus({ preventScroll: true });
    return () => {
      if (opener?.isConnected) opener.focus();
    };
  }, []);

  const onKey = (event: KeyboardEvent) => {
    const dialog = dialogRef.current;
    if (!dialog) return;
    if (event.key === "Escape") {
      event.preventDefault();
      event.stopPropagation();
      if (!busy) onClose();
      return;
    }
    if (["ArrowLeft", "ArrowRight", "PageUp", "PageDown", "Home", "End"].includes(event.key)) {
      event.stopPropagation();
      return;
    }
    if (event.key !== "Tab") return;
    event.stopPropagation();
    const nodes = [...dialog.querySelectorAll<HTMLElement>(FOCUSABLE)].filter((el) => el.offsetParent !== null);
    const first = nodes[0];
    const last = nodes[nodes.length - 1];
    if (!first || !last) return;
    if (event.shiftKey && (document.activeElement === first || document.activeElement === dialog)) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    } else if (!dialog.contains(document.activeElement)) {
      event.preventDefault();
      first.focus();
    }
  };
  const onKeyRef = useRef(onKey);
  onKeyRef.current = onKey;
  useEffect(() => {
    const listener = (event: KeyboardEvent) => onKeyRef.current(event);
    window.addEventListener("keydown", listener, true);
    return () => window.removeEventListener("keydown", listener, true);
  }, []);

  if (!host || !current) return null;
  const capacity = current.page?.slots.length ?? 0;

  return createPortal(
    <div className={base.veil} data-remove-page onPointerDown={(event) => event.target === event.currentTarget && !busy && onClose()}>
      <div
        ref={dialogRef}
        role="alertdialog"
        aria-modal="true"
        aria-labelledby={titleId}
        aria-describedby={descId}
        className={base.dialog}
        aria-busy={busy || undefined}
      >
        <div className={base.head}>
          <span className={styles.icon} data-blocked={!eligible || undefined} aria-hidden>
            {eligible || loading ? <FileMinus2 /> : <ShieldAlert />}
          </span>
          <div>
            <h2 id={titleId} className={base.title}>
              {eligible ? `Remover a página ${current.number}?` : loading ? "Remover página" : `A página ${current.number} não pode ser removida`}
            </h2>
            <p id={descId} className={base.lead}>
              {eligible
                ? "A página está vazia e sai do fichário com os seus bolsos. Isso não pode ser desfeito."
                : loading
                  ? "Carregando os bolsos desta página para conferir se ela está vazia…"
                  : "Só páginas totalmente vazias e sem bolsos fixados podem sair do fichário."}
            </p>
          </div>
          <button type="button" className={base.close} onClick={onClose} aria-label="Fechar" disabled={busy}>
            <X aria-hidden />
          </button>
        </div>

        {candidates.length > 1 ? (
          <div className={styles.options} role="radiogroup" aria-label="Página a remover">
            {candidates.map((candidate) => {
              const reasons = candidate.page ? pageRemovalBlockers(candidate.page, totalPages) : null;
              const ok = reasons !== null && reasons.length === 0;
              return (
                <button
                  key={candidate.number}
                  type="button"
                  role="radio"
                  aria-checked={candidate.number === current.number}
                  className={styles.option}
                  onClick={() => setChosen(candidate.number)}
                  disabled={busy}
                  data-autofocus={candidate.number === current.number || undefined}
                >
                  <span className={styles.optionNumber}>Página {candidate.number}</span>
                  <span className={styles.optionState} data-ok={ok || undefined}>
                    {reasons === null ? "carregando…" : ok ? "vazia" : "bloqueada"}
                  </span>
                </button>
              );
            })}
          </div>
        ) : null}

        {!loading && !eligible ? (
          <ul className={styles.reasons} aria-label="O que impede a remoção">
            {blockers.map((reason) => (
              <li key={reason}>{pageRemovalBlockerLabel(reason)}</li>
            ))}
          </ul>
        ) : null}

        {eligible ? (
          <dl className={base.facts}>
            <div>
              <dt>Páginas</dt>
              <dd>
                {formatCount(totalPages)} → <strong>{formatCount(totalPages - 1)}</strong>
              </dd>
            </div>
            <div>
              <dt>Bolsos vazios a menos</dt>
              <dd>
                <strong>−{formatCount(capacity)}</strong>
              </dd>
            </div>
          </dl>
        ) : null}
        {eligible ? (
          <p className={base.note}>
            {renumber
              ? `As páginas ${renumber.from}–${renumber.to} passam a ser ${renumber.from - 1}–${renumber.to - 1}. Cartas, reservas e cadeados das outras páginas não mudam.`
              : "É a última página: nenhuma outra muda de número."}
          </p>
        ) : null}

        {error ? (
          <p className={styles.error} role="alert">
            {error}
          </p>
        ) : null}

        <div className={base.actions}>
          {eligible ? (
            <>
              <button type="button" className={base.secondary} onClick={onClose} disabled={busy} data-autofocus={candidates.length > 1 ? undefined : true}>
                Cancelar
              </button>
              <button type="button" className={styles.danger} onClick={() => current.page && onConfirm(current.page)} disabled={busy}>
                {busy ? <Loader2 className="animate-spin motion-reduce:animate-none" aria-hidden /> : <FileMinus2 aria-hidden />}
                {busy ? "Removendo…" : `Remover página ${current.number}`}
              </button>
            </>
          ) : (
            <button type="button" className={base.secondary} onClick={onClose} disabled={busy} data-autofocus={candidates.length > 1 ? undefined : true}>
              Entendi
            </button>
          )}
        </div>
      </div>
    </div>,
    host,
  );
}
