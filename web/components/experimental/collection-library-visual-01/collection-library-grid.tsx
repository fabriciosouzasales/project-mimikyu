"use client";

import { BinderMiniPreview } from "@/components/experimental/collection-gallery-spike-01/binder-mini-preview";
import {
  collectionProgress,
  type MockCollection,
} from "@/components/experimental/collection-gallery-spike-01/mock-collections";

/**
 * COLLECTION-LIBRARY-VISUAL-01 (2026-08-29) — refinamento visual do Premium
 * Grid/List aprovado no spike COLLECTION-GALLERY-SPIKE-01 (Modo B venceu a
 * comparação contra a Visual Gallery/Depth Carousel — ver
 * MMKYU-FRONTEND-REPERTOIRE-DRAFT.md, seções 4 e 11).
 *
 * Objetivo desta rodada (pedido de Fabrício): "biblioteca digital premium de
 * Binders", não "cards contendo Binders". Mudanças em relação ao
 * `premium-grid.tsx` original do spike anterior:
 *  - Binder maior (148px vs. 104px) e protagonista do item;
 *  - sem borda/painel de card (`bg-surface` + `border` removidos) — a
 *    separação entre Collections vem de espaço (gap generoso) e sombra, não
 *    de contorno;
 *  - profundidade via `drop-shadow` no próprio Binder, que intensifica no
 *    hover/focus junto com uma pequena elevação (`translate-y`) — sinaliza
 *    "objeto físico levantável", não "botão de formulário";
 *  - progresso discreto: barra fina de 3px + percentual em texto pequeno,
 *    em vez da barra de largura total usada antes;
 *  - clique único abre a Collection (sem estado de seleção intermediário —
 *    não há necessidade de diferenciar visualmente um item "selecionado" de
 *    um "focado", o que já reduziria a sensação de objeto simples e não de
 *    controle de formulário).
 *
 * Reaproveita `BinderMiniPreview`/`mock-collections` do spike anterior sem
 * duplicar — e não redesenha `BinderCoverClosed` (baseline aprovado),
 * conforme instrução explícita de não reabrir o Binder fechado.
 */

interface CollectionLibraryGridProps {
  collections: MockCollection[];
}

export function CollectionLibraryGrid({ collections }: CollectionLibraryGridProps) {
  return (
    <div
      className="grid justify-items-center gap-x-6 gap-y-12"
      style={{ gridTemplateColumns: "repeat(auto-fill, minmax(148px, 1fr))" }}
    >
      {collections.map((collection) => {
        const progress = collectionProgress(collection);
        return (
          <button
            key={collection.id}
            type="button"
            aria-label={`${collection.name}, ${progress}% completo`}
            onClick={() => {
              // Spike sem backend — apenas confirma que o "acesso à
              // Collection" é acionável; não há navegação/domínio real aqui.
              console.log(`[COLLECTION-LIBRARY-VISUAL-01] Abrir Collection: ${collection.id}`);
            }}
            className="group flex w-full max-w-[168px] flex-col items-center gap-3 rounded-lg bg-transparent p-2 outline-none transition-transform duration-300 ease-out hover:-translate-y-1 focus-visible:-translate-y-1 focus-visible:ring-2 focus-visible:ring-accent focus-visible:ring-offset-2 focus-visible:ring-offset-background"
          >
            <span className="pointer-events-none block transition-[filter] duration-300 ease-out [filter:drop-shadow(0_6px_10px_rgb(0_0_0_/_0.18))] group-hover:[filter:drop-shadow(0_16px_24px_rgb(0_0_0_/_0.30))] group-focus-visible:[filter:drop-shadow(0_16px_24px_rgb(0_0_0_/_0.30))]">
              <BinderMiniPreview targetWidth={148} />
            </span>
            <span className="flex w-full flex-col items-center gap-1.5 text-center">
              <span className="w-full truncate text-sm font-medium text-foreground">{collection.name}</span>
              <span className="flex items-center gap-1.5">
                <span className="h-[3px] w-10 overflow-hidden rounded-full bg-surface-muted">
                  <span
                    className="block h-full rounded-full bg-foreground/70"
                    style={{ width: `${progress}%` }}
                  />
                </span>
                <span className="text-[11px] tabular-nums text-muted-foreground">{progress}%</span>
              </span>
            </span>
          </button>
        );
      })}
    </div>
  );
}
