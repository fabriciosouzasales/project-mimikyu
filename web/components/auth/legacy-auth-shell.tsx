import type { ReactNode } from "react";
import { BrandLogo } from "@/components/brand-logo";
import { ThemeToggle } from "@/components/theme-toggle";

/**
 * Casca legada do Auth — extraída de `app/(auth)/layout.tsx` (removido
 * nesta rodada, ver docs/log.md) sem qualquer alteração visual ou de
 * comportamento, só reembalada como componente explícito.
 *
 * Motivo da extração: o Login passou a usar `AuthHeroShell` (nova fundação
 * visual "cartas reais"), e um `layout.tsx` de route group aplica seu chrome
 * a TODAS as rotas irmãs — não dava para o Login divergir visualmente sem
 * tirar o layout compartilhado do meio. Cadastro, Recuperar Senha e
 * Atualizar Senha usam este componente explicitamente e continuam
 * IDÊNTICAS ao que eram antes (mesmo JSX, mesmas classes) — não fazem parte
 * do escopo deste incremento (ver docs/log.md).
 */
export function LegacyAuthShell({ children }: { children: ReactNode }) {
  return (
    <div className="flex min-h-dvh flex-col bg-background">
      <header className="flex h-14 items-center justify-between px-4">
        <BrandLogo className="h-8 w-auto" />
        <ThemeToggle />
      </header>
      <main className="flex flex-1 items-center justify-center p-4">
        <div className="w-full max-w-sm">{children}</div>
      </main>
    </div>
  );
}
