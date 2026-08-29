"use client";

import { useEffect, useState } from "react";

/**
 * Hook para `prefers-reduced-motion: reduce` — mesmo padrão já validado em
 * `components/card/holo-card.tsx` (checagem via `window.matchMedia`, sem
 * dependência nova), só extraído para hook reutilizável porque o spike do
 * "Visual Collection Space" (`app/experimental/collection-space/`) precisa
 * do valor em mais de um componente (carrossel + transição de abertura do
 * Binder), não só num único `useEffect` local como o `HoloCard`.
 *
 * SSR-safe: assume `false` (motion habilitado) até o primeiro efeito rodar
 * no cliente, igual ao racional já usado no projeto para preferências só
 * disponíveis via `window`.
 */
export function usePrefersReducedMotion(): boolean {
  const [prefersReduced, setPrefersReduced] = useState(false);

  useEffect(() => {
    const query = window.matchMedia("(prefers-reduced-motion: reduce)");
    setPrefersReduced(query.matches);

    const handleChange = (event: MediaQueryListEvent) => setPrefersReduced(event.matches);
    query.addEventListener("change", handleChange);
    return () => query.removeEventListener("change", handleChange);
  }, []);

  return prefersReduced;
}
