"use client";

import type { CSSProperties } from "react";
import { HoloCard } from "@/components/card/holo-card";

/**
 * Imagem ampliada de uma carta — fonte única de "como uma carta aparece
 * quando ampliada" no projeto, extraída em 2026-08-17 do modal `Cartas`
 * (`CartaZoomDialog`, `cartas-gallery.tsx`) para ser reutilizada por
 * `/pesquisa` sem reimplementar a experiência do zero (pedido de Fabrício:
 * "o preview de cartas em Pesquisa deve ser estruturalmente compartilhado
 * com Cartas, não apenas visualmente parecido"). Mesma composição de
 * `CartaZoomDialog`/`CartaZoomDialogReadOnly`: `HoloCard` com `floating`
 * (motion senoidal + inclinação de hover, ver `holo-card.tsx`) e sombra
 * projetada; placeholder "Sem imagem" idêntico quando a carta não tem
 * imagem importada.
 *
 * Deliberadamente sem qualquer prop de edição/ativação/importação/filtros
 * de Catálogo, Pricing ou Collection — só recebe o necessário para exibir
 * uma imagem ampliada: URL da imagem, texto alternativo, e o nome opcional
 * do View Transition compartilhado com a miniatura de origem (ver
 * `lib/view-transitions.ts`).
 */
export function CardImagePreview({
  imageUrl,
  alt,
  viewTransitionName,
}: {
  imageUrl: string | null;
  alt: string;
  /** Nome do `view-transition-name` compartilhado com a miniatura do grid que originou a abertura — omitir quando o chamador não usa View Transitions (ex.: fallback de `prefers-reduced-motion` ou navegador sem suporte). */
  viewTransitionName?: string;
}) {
  return (
    <HoloCard
      floating
      className="drop-shadow-[0_25px_50px_-12px_hsl(var(--foreground)/0.55)]"
      style={viewTransitionName ? ({ viewTransitionName } as CSSProperties) : undefined}
    >
      {imageUrl ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={imageUrl} alt={alt} className="w-full rounded-lg" />
      ) : (
        <div className="flex aspect-[5/7] w-full items-center justify-center rounded-lg border border-dashed border-border bg-surface-muted text-xs text-muted-foreground">
          Sem imagem
        </div>
      )}
    </HoloCard>
  );
}
