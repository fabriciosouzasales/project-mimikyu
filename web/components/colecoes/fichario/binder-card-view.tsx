"use client";

import { CardImagePreview } from "@/components/card/card-image-preview";
import { CardPreviewOverlay } from "@/components/card/card-preview-overlay";
import { cardFrontUrl } from "@/lib/colecoes/acervo";
import type { BinderSlot } from "@/lib/colecoes/binder";
import { cardViewAlt, cardViewFor, cardViewTransitionName } from "@/lib/colecoes/binder-card-view";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;

/**
 * V1-08 — lupa da carta no fichário ("Ver carta"). D2 revisada (CATALOG CARD
 * PREVIEW VISUAL ALIGNMENT CORRECTION-01): a MESMA ampliação da página Cartas
 * do Catálogo Editorial, sem painel nem texto — `CardPreviewOverlay`
 * (backdrop, Esc e fundo fecham, foco preso e devolvido, sem chrome) +
 * `CardImagePreview` (`HoloCard` flutuante, fallback "Sem imagem") + o morph
 * miniatura → carta da View Transitions API quando o fichário pode usá-lo
 * (o bolso empresta o `view-transition-name` só durante o morph); sem
 * suporte, em tela cheia ou com movimento reduzido, o zoom+fade do Catálogo.
 *
 * Única adaptação: o preview monta na raiz do fichário (`container`), para
 * aparecer em tela cheia e na sobreposição. Nome da carta só para leitor de
 * tela (título do diálogo e texto alternativo). Nenhuma ação grava.
 */
export function BinderCardView({
  slot,
  container,
  useViewTransition,
  onClose,
}: {
  slot: BinderSlot | null;
  container: HTMLElement | null;
  /** O fichário orquestra o morph (abriu dentro de `startViewTransition`). */
  useViewTransition: boolean;
  onClose: () => void;
}) {
  const view = slot ? cardViewFor(slot) : null;
  return (
    <CardPreviewOverlay
      open={view !== null}
      onClose={onClose}
      title={view ? cardViewAlt(view) : "Carta ampliada"}
      useViewTransition={useViewTransition}
      container={container}
    >
      {view && slot ? (
        <CardImagePreview
          imageUrl={cardFrontUrl(SUPABASE_URL, view.imagePath)}
          alt={cardViewAlt(view)}
          viewTransitionName={useViewTransition ? cardViewTransitionName(slot.slotId) : undefined}
        />
      ) : null}
    </CardPreviewOverlay>
  );
}
