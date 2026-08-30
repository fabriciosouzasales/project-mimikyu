"use client";

import { useEffect, useRef, useState } from "react";
import { BinderCoverClosed } from "@/components/experimental/binder-nav-01/binder-cover-closed";

/**
 * COLLECTION-GALLERY-SPIKE-01 (2026-08-29) — wrapper de escala, NÃO uma
 * cópia/edição do Binder. `BinderCoverClosed` (aprovado como baseline em
 * 2026-08-29, ver memória de projeto) define sua própria largura via
 * `clamp(240px, min(80vw, 58dvh), 480px)` — relativa a VIEWPORT, não ao
 * elemento pai. Isso significa que ele não encolhe sozinho para caber num
 * card pequeno de galeria/grid.
 *
 * Solução isolada aqui (não requer tocar em `binder-nav-01/`): renderiza o
 * Binder no tamanho natural dele dentro de um wrapper absoluto, mede a
 * largura real via `ResizeObserver`, e aplica `transform: scale()` para
 * encaixar no `targetWidth` pedido. Funciona em qualquer viewport porque
 * mede o tamanho renderizado de verdade, não assume um valor fixo.
 */
export function BinderMiniPreview({ targetWidth }: { targetWidth: number }) {
  const innerRef = useRef<HTMLDivElement>(null);
  const [natural, setNatural] = useState<{ w: number; h: number } | null>(null);

  useEffect(() => {
    const el = innerRef.current;
    if (!el) return;

    const measure = () => {
      const rect = el.getBoundingClientRect();
      if (rect.width > 0 && rect.height > 0) {
        setNatural({ w: rect.width, h: rect.height });
      }
    };

    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  const scale = natural ? targetWidth / natural.w : 1;
  const targetHeight = natural ? natural.h * scale : targetWidth * (35 / 26);

  return (
    <div
      className="relative shrink-0 overflow-hidden"
      style={{ width: targetWidth, height: targetHeight }}
      aria-hidden
    >
      <div
        ref={innerRef}
        className="pointer-events-none absolute left-0 top-0"
        style={{ transform: `scale(${scale})`, transformOrigin: "top left" }}
      >
        <BinderCoverClosed />
      </div>
    </div>
  );
}
