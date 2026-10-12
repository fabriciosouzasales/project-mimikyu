"use client";

import { useRouter } from "next/navigation";
import { useEffect } from "react";

/**
 * Atalhos ← / → entre espécies vizinhas (Pokédex P3b, aprovados por Fabrício).
 * Não interferem em digitação nem em controles: ignorados com modificadores,
 * durante composição de texto (IME), quando outro handler já tratou a tecla,
 * e quando o foco está em campo de texto, select, área editável ou dentro de
 * diálogo/menu/listbox. Os links visíveis continuam sendo o caminho principal
 * (mouse, toque e Tab); os atalhos só aceleram.
 */
export function SpeciesKeyboardNav({ prevHref, nextHref }: { prevHref: string | null; nextHref: string | null }) {
  const router = useRouter();

  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if (event.defaultPrevented || event.isComposing) return;
      if (event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return;
      if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return;

      const target = event.target as HTMLElement | null;
      if (target) {
        const tag = target.tagName;
        if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT" || target.isContentEditable) return;
        if (target.closest("[role='dialog'], [role='menu'], [role='listbox'], [role='slider'], [role='tablist']")) return;
      }

      const href = event.key === "ArrowLeft" ? prevHref : nextHref;
      if (!href) return;
      event.preventDefault();
      router.push(href);
    }

    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [router, prevHref, nextHref]);

  return null;
}
