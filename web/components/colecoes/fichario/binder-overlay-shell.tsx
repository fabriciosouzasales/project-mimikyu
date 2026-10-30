"use client";

import { type ReactNode, useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { usePrefersReducedMotion } from "@/lib/use-prefers-reduced-motion";
import styles from "./binder-overlay.module.css";

const FOCUSABLE = 'a[href], button:not([disabled]), input:not([disabled]), select, textarea, [tabindex]:not([tabindex="-1"])';

/**
 * Casca da sobreposição do Fichário Digital (extraída de `BinderOverlay` em
 * V1-12 SHARED EXPERIENCE-01, sem mudança de comportamento): o fichário abre
 * SOBRE a página da coleção, que fica desfocada e escurecida ao fundo e volta
 * exatamente como estava ao fechar.
 *
 * Diálogo modal acessível: `role="dialog"` + `aria-modal`, o resto da página
 * fica `inert`, Tab circula dentro, o foco volta a quem abriu, rolagem do
 * fundo travada. Movimento só com opacidade/escala, desligado com
 * prefers-reduced-motion. O conteúdo (área de trabalho do titular ou leitor
 * só leitura do participante) recebe `close` e decide quando chamar (Esc,
 * botão de fechar).
 *
 * Uma única casca para os dois perfis: qualquer refinamento de abertura,
 * véu ou foco vale para titular e participante.
 */
export function BinderOverlayShell({
  labelledBy,
  onClose,
  children,
}: {
  /** id do título do conteúdo (aria-labelledby do diálogo). */
  labelledBy: string;
  onClose: () => void;
  children: (close: () => void) => ReactNode;
}) {
  const reducedMotion = usePrefersReducedMotion();
  const dialogRef = useRef<HTMLDivElement>(null);
  const [host, setHost] = useState<HTMLElement | null>(null);
  const [closing, setClosing] = useState(false);

  // Hospedeiro próprio no <body> + fundo inerte + rolagem travada.
  useEffect(() => {
    const node = document.createElement("div");
    node.setAttribute("data-binder-overlay", "");
    document.body.appendChild(node);
    const siblings = [...document.body.children].filter((el) => el !== node && !el.hasAttribute("inert")) as HTMLElement[];
    for (const el of siblings) el.setAttribute("inert", "");
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    const opener = document.activeElement as HTMLElement | null;
    setHost(node);
    return () => {
      for (const el of siblings) el.removeAttribute("inert");
      document.body.style.overflow = previousOverflow;
      node.remove();
      if (opener?.isConnected) opener.focus();
    };
  }, []);

  // Foco inicial no diálogo e Tab preso dentro dele.
  useEffect(() => {
    const dialog = dialogRef.current;
    if (!dialog) return;
    const first = dialog.querySelector<HTMLElement>("[data-autofocus]") ?? dialog;
    first.focus({ preventScroll: true });
    function onKey(event: KeyboardEvent) {
      if (event.key !== "Tab" || !dialog) return;
      const items = [...dialog.querySelectorAll<HTMLElement>(FOCUSABLE)].filter((el) => el.offsetParent !== null || el === document.activeElement);
      if (items.length === 0) return;
      const firstItem = items[0];
      const lastItem = items[items.length - 1];
      if (!firstItem || !lastItem) return;
      if (event.shiftKey && (document.activeElement === firstItem || document.activeElement === dialog)) {
        event.preventDefault();
        lastItem.focus();
      } else if (!event.shiftKey && document.activeElement === lastItem) {
        event.preventDefault();
        firstItem.focus();
      }
    }
    dialog.addEventListener("keydown", onKey);
    return () => dialog.removeEventListener("keydown", onKey);
  }, [host]);

  const close = () => {
    if (document.fullscreenElement) void document.exitFullscreen();
    if (reducedMotion) return onClose();
    setClosing(true);
    window.setTimeout(onClose, 160);
  };

  if (!host) return null;

  return createPortal(
    <div className={`binder-nav-01-scope ${styles.veil}`} data-closing={closing || undefined}>
      <div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby={labelledBy}
        tabIndex={-1}
        className={styles.dialog}
        data-closing={closing || undefined}
      >
        {children(close)}
      </div>
    </div>,
    host,
  );
}
