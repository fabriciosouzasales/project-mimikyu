"use client";

import { useCallback, useState } from "react";

/**
 * Devolve o foco ao elemento que abriu um diálogo Radix montado sob demanda
 * (`{open ? <Painel /> : null}` com `<Dialog.Root open>`, sem `Dialog.Trigger`).
 *
 * Sem gatilho registrado, o Radix cancela a restauração padrão ao fechar e o
 * foco cai no `<body>` — quem navega por teclado perde o lugar na página.
 * Este hook guarda o elemento focado no momento da montagem do painel e o
 * reassume em `onCloseAutoFocus`. Se o elemento não estiver mais na página
 * (ex.: a lista foi re-renderizada), mantém o comportamento padrão.
 *
 * Uso: `const restoreFocus = useRestoreFocus();` no componente do painel e
 * `<Dialog.Content onCloseAutoFocus={restoreFocus}>`.
 */
export function useRestoreFocus() {
  const [origin] = useState<HTMLElement | null>(() => {
    if (typeof document === "undefined") return null;
    const active = document.activeElement;
    return active instanceof HTMLElement && active !== document.body ? active : null;
  });

  return useCallback(
    (event: Event) => {
      if (origin?.isConnected) {
        event.preventDefault();
        origin.focus();
      }
    },
    [origin],
  );
}
