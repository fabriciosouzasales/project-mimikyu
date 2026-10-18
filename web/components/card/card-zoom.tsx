"use client";

import { type CSSProperties, type ReactNode, createContext, useCallback, useContext, useMemo, useState } from "react";
import { flushSync } from "react-dom";
import { CardImagePreview } from "@/components/card/card-image-preview";
import { CardPreviewOverlay } from "@/components/card/card-preview-overlay";
import { canUseViewTransitions, cardImagePreviewTransitionName, runWithViewTransition } from "@/lib/view-transitions";

/**
 * Ampliar uma carta ao clicar — o MESMO preview do Catálogo Editorial
 * (`/catalogo/cartas`) e de `/pesquisa`, sem reimplementar nada:
 * `CardPreviewOverlay` (backdrop, Esc, foco preso e devolvido) +
 * `CardImagePreview` (`HoloCard` flutuante com sombra) + o morph
 * miniatura → carta ampliada da View Transitions API
 * (`lib/view-transitions.ts`). Sem suporte no navegador ou com
 * `prefers-reduced-motion`, cai no zoom+fade padrão do Dialog — o mesmo
 * fallback do Catálogo.
 *
 * Uso: `CardZoomProvider` envolve a grade (pode receber Server Components
 * como filhos); cada miniatura vai dentro de um `CardZoomTrigger`, que vira
 * o botão "Ampliar" e empresta o `view-transition-name` à miniatura só
 * durante o morph (mesmo princípio de `transitionTargetId` em
 * `CartasGallery`/`PesquisaView`).
 */

type ZoomCard = { id: string; imageUrl: string | null; name: string };

type ZoomContextValue = {
  open: (card: ZoomCard) => void;
  transitionTargetId: string | null;
  zoomedId: string | null;
};

/**
 * `view-transition-name` precisa ser um <custom-ident> válido e ÚNICO na
 * página: ids com ponto (ex.: "variante.pt-BR") são normalizados.
 */
function transitionName(id: string): string {
  return cardImagePreviewTransitionName(id.replace(/[^A-Za-z0-9_-]/g, "-"));
}

const ZoomContext = createContext<ZoomContextValue | null>(null);

export function CardZoomProvider({ children }: { children: ReactNode }) {
  const [zoomCard, setZoomCard] = useState<ZoomCard | null>(null);
  const [transitionTargetId, setTransitionTargetId] = useState<string | null>(null);

  // Marca a miniatura-alvo ANTES do snapshot "antigo" e troca o estado dentro
  // do callback da transição — idêntico a `openZoom`/`closeZoom` do Catálogo.
  const open = useCallback((card: ZoomCard) => {
    flushSync(() => setTransitionTargetId(card.id));
    runWithViewTransition(() => setZoomCard(card));
  }, []);

  const close = useCallback(() => {
    runWithViewTransition(() => setZoomCard(null));
    setTransitionTargetId(null);
  }, []);

  const zoomedId = zoomCard?.id ?? null;
  const value = useMemo(() => ({ open, transitionTargetId, zoomedId }), [open, transitionTargetId, zoomedId]);

  return (
    <ZoomContext.Provider value={value}>
      {children}
      <CardPreviewOverlay
        open={Boolean(zoomCard)}
        onClose={close}
        title={zoomCard?.name ?? "Carta"}
        useViewTransition={canUseViewTransitions()}
      >
        {zoomCard ? (
          <CardImagePreview
            imageUrl={zoomCard.imageUrl}
            alt={zoomCard.name}
            viewTransitionName={transitionName(zoomCard.id)}
          />
        ) : null}
      </CardPreviewOverlay>
    </ZoomContext.Provider>
  );
}

/**
 * Miniatura clicável. `id` identifica a carta na grade (único na página);
 * `imageUrl` é a frente da carta (a mesma da miniatura). Sem provider, só
 * renderiza os filhos (degrada sem quebrar).
 */
export function CardZoomTrigger({
  id,
  imageUrl,
  name,
  className,
  children,
}: {
  id: string;
  imageUrl: string | null;
  name: string;
  className?: string;
  children: ReactNode;
}) {
  const zoom = useContext(ZoomContext);
  if (!zoom) return <>{children}</>;
  // Mesma regra do Catálogo (`isTransitionSource`): com a carta já ampliada, a
  // miniatura solta o nome — dois elementos com o mesmo `view-transition-name`
  // abortam a transição (InvalidStateError).
  const isSource = zoom.transitionTargetId === id && zoom.zoomedId !== id;
  return (
    <button
      type="button"
      className={className}
      onClick={() => zoom.open({ id, imageUrl, name })}
      aria-label={`Ampliar ${name}`}
      style={{ viewTransitionName: isSource ? transitionName(id) : "none" } as CSSProperties}
    >
      {children}
    </button>
  );
}
