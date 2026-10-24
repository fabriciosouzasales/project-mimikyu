"use client";

import { useEffect } from "react";

/**
 * Rastreio do ponteiro para o brilho do acabamento (Meu acervo) —
 * MY-INVENTORY-HOLOGRAPHIC-FINISH-FOUNDATION-01.
 *
 * Um único listener delegado no documento (não um por carta): galerias com
 * centenas de exemplares não pagam nada até o mouse passar sobre uma carta com
 * acabamento (`[data-finish]`). Só mouse — no toque o brilho fica estático. A
 * escrita é limitada a um quadro por `requestAnimationFrame` e mexe apenas em
 * custom properties do contêiner da carta (`--holo-x/--holo-y`, o mesmo
 * contrato do `HoloCard`) e, no detalhe (`data-finish-tilt`), na inclinação.
 *
 * Com `prefers-reduced-motion: reduce` não registra nada: o CSS já esconde o
 * reflexo e a inclinação, e o foil estático continua informando o acabamento.
 */
export function FinishPointer() {
  useEffect(() => {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

    let frame = 0;
    let target: HTMLElement | null = null;
    let lastX = 0;
    let lastY = 0;

    function paint() {
      frame = 0;
      const node = target;
      if (!node) return;
      const rect = node.getBoundingClientRect();
      if (rect.width === 0 || rect.height === 0) return;
      const x = Math.min(1, Math.max(0, (lastX - rect.left) / rect.width));
      const y = Math.min(1, Math.max(0, (lastY - rect.top) / rect.height));
      node.style.setProperty("--holo-x", `${(x * 100).toFixed(1)}%`);
      node.style.setProperty("--holo-y", `${(y * 100).toFixed(1)}%`);
      if (node.hasAttribute("data-finish-tilt")) {
        // Mesma amplitude do HoloCard (±8°), sem escala: o painel de detalhe é estreito.
        node.style.setProperty(
          "--finish-tilt",
          `perspective(800px) rotateX(${((0.5 - y) * 16).toFixed(2)}deg) rotateY(${((x - 0.5) * 16).toFixed(2)}deg)`,
        );
      }
    }

    function reset(node: HTMLElement) {
      node.style.removeProperty("--holo-x");
      node.style.removeProperty("--holo-y");
      node.style.removeProperty("--finish-tilt");
    }

    function onMove(event: PointerEvent) {
      if (event.pointerType !== "mouse") return;
      const hit = event.target instanceof Element ? event.target.closest<HTMLElement>("[data-finish]") : null;
      if (hit !== target) {
        if (target) reset(target);
        target = hit;
      }
      if (!target) return;
      lastX = event.clientX;
      lastY = event.clientY;
      if (!frame) frame = requestAnimationFrame(paint);
    }

    function onLeaveDocument() {
      if (target) reset(target);
      target = null;
    }

    document.addEventListener("pointermove", onMove, { passive: true });
    document.documentElement.addEventListener("pointerleave", onLeaveDocument);
    return () => {
      document.removeEventListener("pointermove", onMove);
      document.documentElement.removeEventListener("pointerleave", onLeaveDocument);
      if (frame) cancelAnimationFrame(frame);
      if (target) reset(target);
    };
  }, []);

  return null;
}
