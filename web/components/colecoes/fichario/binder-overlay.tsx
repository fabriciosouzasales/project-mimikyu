"use client";

import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import type { BinderHeader } from "@/lib/colecoes/binder";
import { collectionHref } from "@/lib/colecoes/colecoes";
import { usePrefersReducedMotion } from "@/lib/use-prefers-reduced-motion";
import { BinderWorkspace } from "./binder-workspace";
import styles from "./binder-overlay.module.css";

const FOCUSABLE = 'a[href], button:not([disabled]), input:not([disabled]), select, textarea, [tabindex]:not([tabindex="-1"])';

/**
 * Fichário aberto SOBRE a página da coleção (P2-B-SPIKE-RECOVERY-01): sem
 * navegar, a coleção fica desfocada e escurecida ao fundo e volta exatamente
 * como estava ao fechar.
 *
 * Diálogo modal acessível: `role="dialog"` + `aria-modal`, o resto da página
 * fica `inert` (nem foco nem leitor de tela chegam lá), Tab circula dentro do
 * fichário, Esc fecha (a área de trabalho desfaz antes, em camadas: carta
 * escolhida, Bandeja, seleção), o foco volta ao botão que abriu, rolagem do
 * fundo travada. Movimento só com opacidade/escala, desligado com
 * prefers-reduced-motion.
 */
export function BinderOverlay({
  collectionId,
  collectionName,
  coverSubtitle,
  header,
  onClose,
}: {
  collectionId: string;
  collectionName: string;
  coverSubtitle: string | null;
  header: BinderHeader;
  onClose: () => void;
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

  if (!host || !header.columns || !header.rows) return null;

  return createPortal(
    <div className={`binder-nav-01-scope ${styles.veil}`} data-closing={closing || undefined}>
      <div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby="fichario-titulo"
        tabIndex={-1}
        className={styles.dialog}
        data-closing={closing || undefined}
      >
        <BinderWorkspace
          variant="overlay"
          collectionId={collectionId}
          collectionName={collectionName}
          coverSubtitle={coverSubtitle}
          columns={header.columns}
          rows={header.rows}
          totalPages={header.pageCount}
          layoutId={header.layoutId}
          filledCount={header.filledCount}
          role={header.role}
          ownerCollectionId={header.ownerCollectionId}
          ownerCollectionName={header.ownerCollectionName}
          participantCount={header.participantCount}
          ownUnplacedCount={header.ownUnplacedCount}
          editable={header.editable}
          initialAnchor={1}
          initialPages={[]}
          backHref={collectionHref(collectionId)}
          onClose={close}
        />
      </div>
    </div>,
    host,
  );
}
