"use client";

import { ThemeProvider as NextThemesProvider } from "next-themes";
import type { ComponentProps } from "react";

/**
 * Provider de tema claro/escuro (Etapa 0 — pedido explícito de Fabrício).
 * Estratégia de classe (`class="dark"` na raiz), sem uso de localStorage direto:
 * o next-themes cuida da persistência e evita flash de tema errado no load.
 */
export function ThemeProvider({ children, ...props }: ComponentProps<typeof NextThemesProvider>) {
  return <NextThemesProvider {...props}>{children}</NextThemesProvider>;
}
