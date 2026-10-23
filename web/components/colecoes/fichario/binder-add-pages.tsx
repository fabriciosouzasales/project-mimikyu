"use client";

import { useEffect, useId, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { FilePlus2, Loader2, Minus, Plus, X } from "lucide-react";
import { formatCount } from "@/lib/colecoes/acervo";
import { ADD_PAGES_MAX, addPagesSummary } from "@/lib/colecoes/binder";
import styles from "./binder-add-pages.module.css";

const FOCUSABLE = 'button:not([disabled]), input:not([disabled]), [tabindex]:not([tabindex="-1"])';

/**
 * Adicionar páginas ao fim do fichário (P2-BINDER-CAPACITY-AND-EMPTY-SLOT-01).
 *
 * Unidade REAL do contrato (5125 `add_layout_page`): uma PÁGINA — uma face
 * de folha, com todos os bolsos do modelo atual, vazios. Como a folha física
 * de um fichário tem duas faces, a interface conta em páginas e mostra a
 * equivalência em folhas, sem ambiguidade. Nada do que já existe muda; as
 * páginas novas entram depois da última.
 *
 * Diálogo pequeno sobre o fichário, na linguagem escura do spike: contador
 * 1–20 (padrão 2 = uma folha), resumo do antes/depois e confirmação
 * explícita. Teclado: Tab preso, Esc fecha, setas não viram a página por baixo.
 */
export function AddPagesDialog({
  host,
  columns,
  rows,
  totalPages,
  busy,
  onConfirm,
  onClose,
}: {
  host: HTMLElement | null;
  columns: number;
  rows: number;
  totalPages: number;
  busy: boolean;
  onConfirm: (count: number) => void;
  onClose: () => void;
}) {
  const dialogRef = useRef<HTMLDivElement>(null);
  const titleId = useId();
  const [count, setCount] = useState(2);
  const summary = addPagesSummary(count, columns, rows, totalPages);

  useEffect(() => {
    const opener = document.activeElement as HTMLElement | null;
    dialogRef.current?.querySelector<HTMLElement>("[data-autofocus]")?.focus({ preventScroll: true });
    return () => {
      if (opener?.isConnected) opener.focus();
    };
  }, []);

  // Teclado em captura (como a visão geral): nada vaza para o fichário por baixo nem para o diálogo do overlay.
  const onKey = (event: KeyboardEvent) => {
    const dialog = dialogRef.current;
    if (!dialog) return;
    if (event.key === "Escape") {
      event.preventDefault();
      event.stopPropagation();
      !busy && onClose();
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

  if (!host) return null;


  return createPortal(
    <div className={styles.veil} onPointerDown={(event) => event.target === event.currentTarget && !busy && onClose()}>
      <div ref={dialogRef} role="dialog" aria-modal="true" aria-labelledby={titleId} className={styles.dialog} aria-busy={busy || undefined}>
        <div className={styles.head}>
          <span className={styles.icon} aria-hidden>
            <FilePlus2 />
          </span>
          <div>
            <h2 id={titleId} className={styles.title}>
              Adicionar páginas
            </h2>
            <p className={styles.lead}>
              As páginas novas entram no fim do fichário, com {columns} × {rows} bolsos vazios cada. Uma folha física tem 2 páginas (frente e verso).
            </p>
          </div>
          <button type="button" className={styles.close} onClick={onClose} aria-label="Fechar" disabled={busy}>
            <X aria-hidden />
          </button>
        </div>

        <div className={styles.stepper} role="group" aria-label="Quantidade de páginas">
          <button type="button" className={styles.step} onClick={() => setCount((n) => Math.max(1, n - 1))} disabled={busy || count <= 1} aria-label="Uma página a menos">
            <Minus aria-hidden />
          </button>
          <output className={styles.value} aria-live="polite" data-autofocus tabIndex={-1}>
            <span className={styles.number}>{count}</span>
            <span className={styles.unit}>{count === 1 ? "página" : "páginas"}</span>
            <span className={styles.sheets}>{summary.sheetsLabel}</span>
          </output>
          <button
            type="button"
            className={styles.step}
            onClick={() => setCount((n) => Math.min(ADD_PAGES_MAX, n + 1))}
            disabled={busy || count >= ADD_PAGES_MAX}
            aria-label="Uma página a mais"
          >
            <Plus aria-hidden />
          </button>
        </div>

        <dl className={styles.facts}>
          <div>
            <dt>Páginas</dt>
            <dd>
              {formatCount(totalPages)} → <strong>{formatCount(summary.totalAfter)}</strong>
            </dd>
          </div>
          <div>
            <dt>Bolsos vazios novos</dt>
            <dd>
              <strong>+{formatCount(summary.slotsAdded)}</strong>
            </dd>
          </div>
        </dl>
        <p className={styles.note}>Nada do que já está no fichário muda: páginas, cartas, reservas e bolsos fixados ficam onde estão.</p>

        <div className={styles.actions}>
          <button type="button" className={styles.secondary} onClick={onClose} disabled={busy}>
            Cancelar
          </button>
          <button type="button" className={styles.primary} onClick={() => onConfirm(count)} disabled={busy}>
            {busy ? <Loader2 className="animate-spin" aria-hidden /> : <Plus aria-hidden />}
            {busy ? "Adicionando…" : `Adicionar ${count === 1 ? "1 página" : `${count} páginas`}`}
          </button>
        </div>
      </div>
    </div>,
    host,
  );
}
