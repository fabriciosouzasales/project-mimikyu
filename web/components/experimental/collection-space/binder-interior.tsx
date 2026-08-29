"use client";

import { X } from "lucide-react";
import { MOCK_BINDER_PAGES, type MockStorageContainer } from "@/app/experimental/collection-space/mock-data";
import { cn } from "@/lib/utils";

/**
 * Primeira vista interna do Binder — spike do "Visual Collection Space"
 * (pedido de Fabrício, 2026-08-28). Duas páginas mockadas lado a lado, só
 * para dar volume visual ("sensação de objetos físicos"); slots NÃO são
 * funcionais nesta rodada (sem cadastro, sem drag de carta, sem dado real —
 * ver `mock-data.ts`). `viewTransitionName` é controlado pelo componente
 * pai (`collection-space-view.tsx`), que também decide o nome — este
 * componente só recebe `transitionName` pronto para aplicar no painel raiz,
 * mantendo a lógica de "quem tem o nome agora" num único lugar.
 */
export function BinderInterior({
  container,
  transitionName,
  onClose,
}: {
  container: MockStorageContainer;
  transitionName: string | undefined;
  onClose: () => void;
}) {
  return (
    <div
      className="fixed inset-0 z-50 flex flex-col bg-[hsl(30_24%_6%)]"
      style={{ viewTransitionName: transitionName }}
      role="dialog"
      aria-modal="true"
      aria-label={`Interior de ${container.name}`}
    >
      <header className="flex items-center justify-between px-6 py-4 sm:px-10">
        <div>
          <p className="text-sm font-semibold text-white/95">{container.name}</p>
          <p className="text-xs text-white/50">{container.subtitle} · vista experimental, sem slots funcionais</p>
        </div>
        <button
          type="button"
          onClick={onClose}
          className="rounded-full border border-white/15 p-2 text-white/70 transition-colors hover:bg-white/10 hover:text-white"
          aria-label="Fechar binder e voltar ao Collection Space"
        >
          <X className="h-4 w-4" aria-hidden />
        </button>
      </header>

      <div className="flex flex-1 items-center justify-center overflow-auto px-4 pb-10 sm:px-10">
        <div className="grid w-full max-w-4xl grid-cols-1 gap-3 sm:grid-cols-2 sm:gap-1">
          {MOCK_BINDER_PAGES.map((page, pageIndex) => (
            <div
              key={page.id}
              className={cn(
                "rounded-lg border border-white/10 bg-white/[0.04] p-4 shadow-[0_20px_50px_-25px_rgba(0,0,0,0.8)]",
                pageIndex === 0 ? "sm:rounded-r-none sm:border-r-0" : "sm:rounded-l-none",
              )}
            >
              <div className="grid grid-cols-3 gap-2.5">
                {page.slots.map((slot) => (
                  <div
                    key={slot.id}
                    className={cn(
                      "aspect-[5/7] rounded-sm border",
                      slot.filled
                        ? "border-white/10 bg-gradient-to-br from-white/20 to-white/5"
                        : "border-dashed border-white/10 bg-white/[0.02]",
                    )}
                    aria-hidden
                  />
                ))}
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
